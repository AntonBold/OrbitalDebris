// Host-side unit test for bram_io.c (not part of the Vitis build, which
// lists its sources explicitly). Points the reader at a plain array laid out
// like the PL's BRAM.
//
//   cc -std=c99 -Wall -Wextra -o /tmp/test_bram_io \
//      src/sw/test_bram_io.c src/sw/bram_io.c && /tmp/test_bram_io

#include <stdio.h>
#include <string.h>
#include <math.h>
#include "include/bram_io.h"

static uint32_t fake[BRAM_NUM_SLOTS * BRAM_SLOT_WORDS];
static int failures = 0;

#define CHECK(cond, ...) do { if (!(cond)) { failures++; printf("FAIL %s:%d: ", __FILE__, __LINE__); \
                              printf(__VA_ARGS__); printf("\n"); } } while (0)

typedef struct { uint32_t x_sum, y_sum, area, valid; } Obj;

// Write a frame the way feature_extract does: centroids, then the header
static void pl_write(int slot, uint32_t frame, const Obj *objs, uint32_t n)
{
    uint32_t *s = &fake[slot * BRAM_SLOT_WORDS];
    for (uint32_t i = 0; i < n; i++) {
        s[1 + 2 * i] = objs[i].x_sum;
        s[2 + 2 * i] = (objs[i].y_sum << 10) | ((objs[i].area & 0x1FF) << 1) | objs[i].valid;
    }
    s[0] = (frame << 9) | (n & 0x1FF);
}

static void pl_write_frame(uint32_t frame, const Obj *objs, uint32_t n)
{
    pl_write((frame - 1) % BRAM_NUM_SLOTS, frame, objs, n);
}

static int near(float a, float b) { return fabsf(a - b) < 1e-4f; }

int main(void)
{
    CentroidFrame f;
    const BramStats *st;

    memset(fake, 0, sizeof(fake));
    bram_init_at(fake);
    st = bram_get_stats();

    // After reset (BRAM zeroed by the PS at boot): no frame yet
    CHECK(bram_read_frame(&f) == BRAM_NO_NEW_FRAME, "empty BRAM should give NO_NEW_FRAME");

    // Frame 1: the cca_top_tb objects (10x10 square at 20,20 and 20x20 at 100,100)
    Obj f1[] = { {2450, 2450, 100, 1}, {43800, 43800, 400, 1} };
    pl_write_frame(1, f1, 2);
    CHECK(bram_read_frame(&f) == 1, "frame 1");
    CHECK(f.frame_number == 1 && f.count == 2, "frame 1 header: number %u count %d", f.frame_number, f.count);
    CHECK(near(f.centroids[0].x, 24.5f) && near(f.centroids[0].y, 24.5f) && f.centroids[0].area == 100,
          "obj 0 = (%f, %f) area %u", f.centroids[0].x, f.centroids[0].y, f.centroids[0].area);
    CHECK(near(f.centroids[1].x, 109.5f) && f.centroids[1].area == 400, "obj 1 x = %f", f.centroids[1].x);
    CHECK(bram_read_frame(&f) == BRAM_NO_NEW_FRAME, "same frame twice");

    // Empty frame is a real frame (count 0)
    pl_write_frame(2, NULL, 0);
    CHECK(bram_read_frame(&f) == 2 && f.count == 0, "empty frame 2: count %d", f.count);

    // Fell behind: frames 3 and 4 both written before we read -> get 4, skip 1
    Obj one[] = { {5, 7, 1, 1} };
    pl_write_frame(3, one, 1);
    pl_write_frame(4, one, 1);
    CHECK(bram_read_frame(&f) == 4, "newest frame is 4");
    CHECK(st->frames_skipped == 1, "frames_skipped = %u", st->frames_skipped);

    // Invalid entry and a zero-area entry (area 512 truncated) are dropped
    Obj mixed[] = { {10, 20, 2, 1}, {1, 1, 1, 0}, {5000, 5000, 512, 1}, {30, 40, 10, 1} };
    pl_write_frame(5, mixed, 4);
    CHECK(bram_read_frame(&f) == 5 && f.count == 2, "mixed frame count %d", f.count);
    CHECK(near(f.centroids[0].x, 5.0f) && near(f.centroids[1].y, 4.0f), "mixed centroids");
    CHECK(st->invalid_entries == 1 && st->zero_area_entries == 1, "invalid %u zero_area %u",
          st->invalid_entries, st->zero_area_entries);

    // Count > 256 in the header (RTL known issue 2) is clamped
    Obj many[BRAM_MAX_CENTROIDS];
    for (int i = 0; i < BRAM_MAX_CENTROIDS; i++) many[i] = (Obj){ (uint32_t)i, (uint32_t)i, 1, 1 };
    pl_write_frame(6, many, BRAM_MAX_CENTROIDS);
    fake[((6 - 1) % 3) * BRAM_SLOT_WORDS] = (6u << 9) | 257u;
    CHECK(bram_read_frame(&f) == 6 && f.count == BRAM_MAX_CENTROIDS, "clamped count %d", f.count);
    CHECK(st->bad_counts == 1, "bad_counts %u", st->bad_counts);
    CHECK(near(f.centroids[255].x, 255.0f), "last centroid x %f", f.centroids[255].x);

    // Frame in the wrong slot is still read, and flagged
    pl_write(0, 7, one, 1);        // frame 7 belongs in slot 0: fine
    CHECK(bram_read_frame(&f) == 7 && st->slot_mismatches == 0, "frame 7");
    pl_write(0, 8, one, 1);        // frame 8 belongs in slot 1
    CHECK(bram_read_frame(&f) == 8 && st->slot_mismatches == 1, "slot mismatch counted");

    // Max-size object: sums at the top of their range, exact in float
    Obj big[] = { {511u * 1919u, 511u * 1079u, 511, 1} };
    pl_write_frame(9, big, 1);
    CHECK(bram_read_frame(&f) == 9 && near(f.centroids[0].x, 1919.0f) && near(f.centroids[0].y, 1079.0f),
          "max object (%f, %f)", f.centroids[0].x, f.centroids[0].y);

    CHECK(st->frames_read == 8, "frames_read %u", st->frames_read);

    // Boot-time clear: headers zeroed, centroid words left alone
    bram_clear_headers();
    CHECK(fake[0] == 0 && fake[BRAM_SLOT_WORDS] == 0 && fake[2 * BRAM_SLOT_WORDS] == 0, "headers cleared");
    CHECK(fake[1] != 0, "centroid words untouched");

    // Not covered here: BRAM_TORN_READ needs the PL to write during the copy

    printf("%s (%d failure%s)\n", failures ? "TEST_BRAM_IO FAILED" : "TEST_BRAM_IO PASSED",
           failures, failures == 1 ? "" : "s");
    return failures ? 1 : 0;
}
