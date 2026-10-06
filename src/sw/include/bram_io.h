#ifndef BRAM_IO_H
#define BRAM_IO_H

#include "centroid.h"
#include <stdint.h>

// BRAM base address -- must match vivado address assignment
#define BRAM_BASE_ADDR      0xA0000000

// Each frame block: 1 header word + 256 centroid words
#define FRAME_BLOCK_WORDS   257
#define NUM_FRAME_BLOCKS    3

// Header word layout
#define HEADER_FRAME_NUM_SHIFT      10
#define HEADER_CENTROID_COUNT_MASK  0x3FF // bits 9:0

// Centroid word layout (32-bit packed)
// [31:21] X (11 bits, 0-1919)
// [20:10] Y (11 bits, 0-1079)
// [9]     valid flag
#define CENTROID_X_SHIFT    21
#define CENTROID_X_MASK     0x7FF
#define CENTROID_Y_SHIFT    10
#define CENTROID_Y_MASK     0x7FF
#define CENTROID_VALID_MASK 0x200

// initialize BRAM access
void bram_init(void);

// read the newest frame's centroids from BRAM into a CentroidFrame
// returns the frame number, or -1 on error
int bram_read_frame (CentroidFrame *frame_out);

#endif // BRAM_IO_H