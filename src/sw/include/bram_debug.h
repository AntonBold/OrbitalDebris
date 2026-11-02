#ifndef BRAM_DEBUG_H
#define BRAM_DEBUG_H

// UART debug output for PL bring-up: what the PS reads from the centroid
// BRAM, both decoded (bram_read_frame) and as raw words.

#include "centroid.h"
#include <stdint.h>

// The three slot headers, raw (all 0 right after bram_clear_headers())
void bram_print_headers(void);

// Decoded frame: frame number, count, and each centroid's x, y, area
void bram_print_frame(const CentroidFrame *f, uint32_t irq_count);

// Raw words of the slot holding frame_number: header, then per centroid
// X_sum, Y_sum, area, valid -- compare these with the golden model's sums
void bram_print_raw_frame(uint32_t frame_number);

// bram_get_stats() counters
void bram_print_stats(void);

#endif // BRAM_DEBUG_H
