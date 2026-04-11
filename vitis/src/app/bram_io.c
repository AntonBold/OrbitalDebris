#include "include/bram_io.h"
#include "include/centroid.h"
#include <stdint.h>

// Pointer to BRAM base, volatile because hardware writes to it
static volatile uint32_t *bram = (volatile uint32_t *)BRAM_BASE_ADDR;

// tracks the last frame number we processed
static uint32_t last_frame_num = 0xFFFFFFFF;

void bram_init(void)
{
    last_frame_num = 0xFFFFFFFF;
}

int bram_read_frame(CentroidFrame *frame_out)
{
    // search all three frame blocks for the newest one
    uint32_t newest_frame_num = 0;
    int newest_block = -1;

    for (int b = 0; b < NUM_FRAME_BLOCKS; b++) {
        uint32_t offset = b * FRAME_BLOCK_WORDS;
        uint32_t header = bram[offset];

        uint32_t frame_num = header >> HEADER_FRAME_NUM_SHIFT;
        uint32_t centroid_count = header & HEADER_CENTROID_COUNT_MASK;

        // skip empty or invalid blocks
        if (centroid_count == 0 || centroid_count > MAX_CENTROIDS)
            continue;

        if (newest_block == -1 || frame_num > newest_frame_num) {
            newest_frame_num = frame_num;
            newest_block = b;
        }
    }

    if (newest_block == -1)
        return -1;
    
    // skip if we already processed this frame
    if (newest_frame_num == last_frame_num)
        return -1;

    last_frame_num = newest_frame_num;

    // read centroid data from the newest block
    uint32_t offset = newest_block * FRAME_BLOCK_WORDS;
    uint32_t header = bram[offset];
    uint32_t count = header & HEADER_CENTROID_COUNT_MASK;

    frame_out->count = 0;
    
    for (uint32_t i = 0; i < count; i++) {
        uint32_t word = bram[offset + 1 + i];

        uint32_t valid = (word >> 9) & 0x1;
        if(!valid)
            continue;

        uint32_t x = (word >> CENTROID_X_SHIFT) & CENTROID_X_MASK;
        uint32_t y = (word >> CENTROID_Y_SHIFT) & CENTROID_Y_MASK;

        frame_out->centroids[frame_out->count].x = (float)x;
        frame_out->centroids[frame_out->count].y = (float)y;
        frame_out->count++;
    }

    return (int)newest_frame_num;
}