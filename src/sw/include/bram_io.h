#ifndef BRAM_IO_H
#define BRAM_IO_H

// PS reader for the centroid BRAM written by cca_top.
// Format and protocol: docs/pl-ps_interface_spec.md

#include "centroid.h"
#include <stdint.h>

// BRAM base address -- must match the Vivado address editor
#define BRAM_BASE_ADDR          0xA0000000u

// Layout: 3 slots of 513 words (1 header + 256 centroids x 2 words)
#define BRAM_NUM_SLOTS          3
#define BRAM_SLOT_WORDS         513
#define BRAM_MAX_CENTROIDS      256

// Header word
#define HDR_FRAME_SHIFT         9
#define HDR_FRAME_MASK          0x7FFFFFu       // bits 31:9
#define HDR_COUNT_MASK          0x1FFu          // bits 8:0

// Centroid word 2 (word 1 is the 32-bit X sum)
#define C2_YSUM_SHIFT           10              // bits 31:10
#define C2_AREA_SHIFT           1
#define C2_AREA_MASK            0x1FFu          // bits 9:1
#define C2_VALID_MASK           0x1u            // bit 0

// bram_read_frame() return codes (frame numbers start at 1, so >0 is a frame)
#define BRAM_NO_NEW_FRAME       (-1)            // no frame newer than the last one read
#define BRAM_TORN_READ          (-2)            // PL overwrote the slot while we copied it

typedef struct {
    uint32_t frames_read;       // frames returned successfully
    uint32_t frames_skipped;    // gaps in the frame number (PS fell behind / missed interrupts)
    uint32_t slot_mismatches;   // newest frame wasn't in the slot round-robin predicts
    uint32_t torn_reads;        // copies discarded because the PL caught up
    uint32_t bad_counts;        // header count > 256 (clamped)
    uint32_t invalid_entries;   // centroid with the valid bit clear
    uint32_t zero_area_entries; // valid centroid with area field 0 (area >= 512 truncated)
} BramStats;

// Use the hardware BRAM at BRAM_BASE_ADDR
void bram_init(void);

// Use any memory as the BRAM (host-side tests)
void bram_init_at(volatile uint32_t *base);

// Zero the three header words ("no frame yet"). Call once at boot, before
// enabling the frame interrupt, so frames from before a reset are never read.
void bram_clear_headers(void);

// Read the newest frame into frame_out, dividing the sums into centroids.
// Call once per interrupt (polling also works: it returns BRAM_NO_NEW_FRAME
// until the PL finishes another frame).
// Returns the frame number (> 0), or BRAM_NO_NEW_FRAME / BRAM_TORN_READ.
int bram_read_frame(CentroidFrame *frame_out);

const BramStats *bram_get_stats(void);

#endif // BRAM_IO_H
