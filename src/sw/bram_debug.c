#include "include/bram_debug.h"
#include "include/bram_io.h"

// On the board this prints with xil_printf (small, but no %f). Host builds
// can pass -DBRAM_DEBUG_PRINTF=printf with <stdio.h>.
#ifndef BRAM_DEBUG_PRINTF
#include "xil_printf.h"
#define BRAM_DEBUG_PRINTF xil_printf
#else
#include <stdio.h>
#endif

#define PRINT BRAM_DEBUG_PRINTF

// Fixed point with 3 decimals, since xil_printf can't format floats.
// Centroids are never negative.
static void print_milli(const char *label, float v)
{
    int milli = (int)(v * 1000.0f + 0.5f);
    PRINT("%s%d.%03d", label, milli / 1000, milli % 1000);
}

void bram_print_headers(void)
{
    for (int s = 0; s < BRAM_NUM_SLOTS; s++) {
        uint32_t hdr = bram_peek((uint32_t)s * BRAM_SLOT_WORDS);
        PRINT("  slot %d header 0x%08x: frame %d, count %d\r\n", s, hdr,
              (int)((hdr >> HDR_FRAME_SHIFT) & HDR_FRAME_MASK), (int)(hdr & HDR_COUNT_MASK));
    }
}

void bram_print_frame(const CentroidFrame *f, uint32_t irq_count)
{
    PRINT("frame %d: %d centroid(s), interrupts so far %d\r\n",
          (int)f->frame_number, f->count, (int)irq_count);
    for (int i = 0; i < f->count; i++) {
        PRINT("  [%d]", i);
        print_milli(" x=", f->centroids[i].x);
        print_milli(" y=", f->centroids[i].y);
        PRINT(" area=%d\r\n", (int)f->centroids[i].area);
    }
}

void bram_print_raw_frame(uint32_t frame_number)
{
    // frame n is in slot (n - 1) % 3 (docs/pl-ps_interface_spec.md)
    uint32_t base = ((frame_number - 1) % BRAM_NUM_SLOTS) * BRAM_SLOT_WORDS;
    uint32_t hdr = bram_peek(base);
    uint32_t count = hdr & HDR_COUNT_MASK;
    PRINT("  raw slot %d header 0x%08x\r\n", (int)(base / BRAM_SLOT_WORDS), hdr);
    if (count > BRAM_MAX_CENTROIDS)
        count = BRAM_MAX_CENTROIDS;
    for (uint32_t i = 0; i < count; i++) {
        uint32_t w1 = bram_peek(base + 1 + 2 * i);
        uint32_t w2 = bram_peek(base + 2 + 2 * i);
        PRINT("  raw [%d] x_sum=%d y_sum=%d area=%d valid=%d (0x%08x 0x%08x)\r\n", (int)i,
              (int)w1, (int)(w2 >> C2_YSUM_SHIFT), (int)((w2 >> C2_AREA_SHIFT) & C2_AREA_MASK),
              (int)(w2 & C2_VALID_MASK), w1, w2);
    }
}

void bram_print_stats(void)
{
    const BramStats *s = bram_get_stats();
    PRINT("  stats: read %d, skipped %d, slot mismatches %d, torn %d, bad counts %d, "
          "invalid %d, zero area %d\r\n",
          (int)s->frames_read, (int)s->frames_skipped, (int)s->slot_mismatches, (int)s->torn_reads,
          (int)s->bad_counts, (int)s->invalid_entries, (int)s->zero_area_entries);
}
