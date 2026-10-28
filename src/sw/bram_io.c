#include "include/bram_io.h"
#include "include/centroid.h"
#include <stdint.h>
#include <string.h>

// Reader for the centroid BRAM (docs/pl-ps_interface_spec.md).
//
// The PL writes each frame into the next of three slots (frame n -> slot
// (n-1) % 3 after reset), header last, then interrupts. We always take the
// newest frame: scan the three headers, copy that slot out, and divide the
// sums into centroids. Frame numbers tell us when we fell behind.
//
// Known limit (RTL known issue 4): the frame number saturates at 0x7FFFFF
// (~39 h at 60 fps). After that every header looks the same and this reader
// reports BRAM_NO_NEW_FRAME forever. Fixing it needs the RTL to wrap and the
// newest-frame comparison below to become wrap-aware.

// volatile: the PL writes this memory behind the CPU's back
static volatile uint32_t *bram = (volatile uint32_t *)BRAM_BASE_ADDR;

static uint32_t  last_frame;    // last frame returned; 0 = none since init
static BramStats stats;

// The slot is copied out before decoding, so the PL can reuse it any time
// after the copy without affecting this frame
static uint32_t slot_copy[BRAM_SLOT_WORDS];

static uint32_t header_frame(uint32_t hdr)
{
    return (hdr >> HDR_FRAME_SHIFT) & HDR_FRAME_MASK;
}

void bram_init(void)
{
    bram_init_at((volatile uint32_t *)BRAM_BASE_ADDR);
}

void bram_init_at(volatile uint32_t *base)
{
    bram = base;
    last_frame = 0;
    memset(&stats, 0, sizeof(stats));
}

void bram_clear_headers(void)
{
    for (int s = 0; s < BRAM_NUM_SLOTS; s++)
        bram[s * BRAM_SLOT_WORDS] = 0;
}

const BramStats *bram_get_stats(void)
{
    return &stats;
}

// Slot holding the highest frame number, or -1 if every header is 0
// (nothing written since reset -- the PS zeroes the BRAM at boot)
static int newest_slot(uint32_t *frame_out)
{
    int slot = -1;
    uint32_t best = 0;
    for (int s = 0; s < BRAM_NUM_SLOTS; s++) {
        uint32_t f = header_frame(bram[s * BRAM_SLOT_WORDS]);
        if (f > best) {
            best = f;
            slot = s;
        }
    }
    *frame_out = best;
    return slot;
}

int bram_read_frame(CentroidFrame *frame_out)
{
    uint32_t frame;
    int slot = newest_slot(&frame);

    if (slot < 0 || frame <= last_frame)
        return BRAM_NO_NEW_FRAME;

    // Cross-check against the round-robin order. A mismatch means the PL
    // and PS disagree about where frames go (e.g. the PL was reset but the
    // PS wasn't), which is worth knowing about even though we still read
    // the newest frame.
    if (slot != (int)((frame - 1) % BRAM_NUM_SLOTS))
        stats.slot_mismatches++;

    // Copy the slot: header, then count x 2 words
    const uint32_t base = (uint32_t)slot * BRAM_SLOT_WORDS;
    uint32_t hdr = bram[base];
    uint32_t count = hdr & HDR_COUNT_MASK;
    if (count > BRAM_MAX_CENTROIDS) {
        // Only possible if the PL found more than 256 objects (RTL known
        // issue 2); the words past 256 belong to the next slot
        stats.bad_counts++;
        count = BRAM_MAX_CENTROIDS;
    }
    slot_copy[0] = hdr;
    for (uint32_t i = 0; i < 2 * count; i++)
        slot_copy[1 + i] = bram[base + 1 + i];

    // Torn-read check. The PL only rewrites this slot when it dumps frame+3,
    // and that dump can only start after frame+2's header is written. If no
    // header shows frame+2 yet, nothing touched this slot during the copy.
    uint32_t newest_after;
    newest_slot(&newest_after);
    if (newest_after >= frame + 2) {
        // Leave last_frame alone: the next call reads the newest frame and
        // counts this one as skipped
        stats.torn_reads++;
        return BRAM_TORN_READ;
    }

    if (last_frame != 0 && frame > last_frame + 1)
        stats.frames_skipped += frame - last_frame - 1;

    // Divide as soon as the sums are out of BRAM. float is exact here: with
    // area <= 511 the sums stay below 2^24 (511 * 1919 = 980,609), inside
    // float's 24-bit mantissa.
    int n = 0;
    for (uint32_t i = 0; i < count; i++) {
        uint32_t x_sum = slot_copy[1 + 2 * i];
        uint32_t w2    = slot_copy[2 + 2 * i];

        if (!(w2 & C2_VALID_MASK)) {
            stats.invalid_entries++;
            continue;
        }
        uint32_t area  = (w2 >> C2_AREA_SHIFT) & C2_AREA_MASK;
        uint32_t y_sum = w2 >> C2_YSUM_SHIFT;
        if (area == 0) {
            // A valid object always has area >= 1, so 0 means the 9-bit
            // field wrapped (area a multiple of 512, RTL known issue 3).
            // There's no usable centroid; drop it rather than divide by 0.
            stats.zero_area_entries++;
            continue;
        }
        frame_out->centroids[n].x    = (float)x_sum / (float)area;
        frame_out->centroids[n].y    = (float)y_sum / (float)area;
        frame_out->centroids[n].area = (uint16_t)area;
        n++;
    }
    frame_out->count = n;
    frame_out->frame_number = frame;

    last_frame = frame;
    stats.frames_read++;
    return (int)frame;
}
