// Host-side unit test for the telemetry encoder (not part of the Vitis
// build, which lists its sources explicitly). Also writes a byte stream, as
// the board would send it, for scripts/telemetry_decode.py to decode.
//
//   cc -std=c99 -Wall -Wextra -DTELEMETRY_HOST -o /tmp/test_telemetry \
//      src/sw/test_telemetry.c src/sw/telemetry.c && /tmp/test_telemetry /tmp/telemetry.bin
//   python3 scripts/telemetry_decode.py /tmp/telemetry.bin -v --csv /tmp/telemetry.csv

#include <stdio.h>
#include <string.h>
#include "include/telemetry.h"

static int failures = 0;

#define CHECK(cond, ...) do { if (!(cond)) { failures++; printf("FAIL %s:%d: ", __FILE__, __LINE__); \
                              printf(__VA_ARGS__); printf("\n"); } } while (0)

static uint16_t u16(const uint8_t *p) { return (uint16_t)(p[0] | p[1] << 8); }
static uint32_t u32(const uint8_t *p) { return u16(p) | (uint32_t)u16(p + 2) << 16; }

// pattern_gen's frame as the board reads it, with one label of each kind
static void pattern_frame(CentroidFrame *f, LabelSet *l, uint32_t frame_number)
{
    memset(f, 0, sizeof(*f));
    f->count = 3;
    f->frame_number = frame_number;
    f->centroids[0] = (Centroid){102.0f, 102.0f, 25};
    f->centroids[1] = (Centroid){502.0f, 502.0f, 25};
    f->centroids[2] = (Centroid){807.0f, 805.5862f, 87};    // 70086 / 87
    l->count = 3;
    l->labels[0] = LABEL_OBJECT;
    l->labels[1] = LABEL_STAR;
    l->labels[2] = LABEL_UNKNOWN;
}

int main(int argc, char **argv)
{
    static uint8_t buf[TELEMETRY_MAX_PACKET];
    CentroidFrame f;
    LabelSet l;

    CHECK(telemetry_crc16((const uint8_t *)"123456789", 9) == 0x29B1, "CRC check value");

    // ---- one packet, byte by byte -------------------------------------------
    pattern_frame(&f, &l, 7);
    size_t n = telemetry_encode_frame(&f, &l, 2, buf);
    CHECK(n == 18 + 7 * 3, "length %zu", n);
    CHECK(buf[0] == 0xA5 && buf[1] == 0x5A, "sync");
    CHECK(buf[2] == 1 && buf[3] == 1, "version/type");
    CHECK(u16(buf + 4) == 10 + 7 * 3, "payload length %u", u16(buf + 4));
    CHECK(u32(buf + 6) == 7, "frame number");
    CHECK(u32(buf + 10) == 2, "frames_skipped");
    CHECK(u16(buf + 14) == 3, "count");
    const uint8_t *c = buf + 16;
    CHECK(u16(c) == 102 * 32 && u16(c + 2) == 102 * 32, "c0 x/y %u %u", u16(c), u16(c + 2));
    CHECK(u16(c + 4) == 25 && (int8_t)c[6] == 1, "c0 area/label");
    CHECK((int8_t)c[7 + 6] == 0, "c1 label star");
    CHECK(u16(c + 14 + 2) == 25779, "c2 y = round(805.5862 * 32) = 25779, got %u", u16(c + 16));
    CHECK((int8_t)c[14 + 6] == -1, "c2 label unknown");
    CHECK(u16(buf + n - 2) == telemetry_crc16(buf + 2, n - 4), "CRC field");

    // ---- edge values ----------------------------------------------------------
    f.count = 2;
    f.centroids[0].x = 1919.99f;                // largest x on a 1920-wide frame
    f.centroids[1].x = -1.0f;                   // can't happen; must clamp, not wrap
    n = telemetry_encode_frame(&f, &l, 0, buf);
    CHECK(u16(buf + 16) == 61440, "x 1919.99 -> 61440, got %u", u16(buf + 16));
    CHECK(u16(buf + 23) == 0, "x -1 clamps to 0, got %u", u16(buf + 23));

    f.count = 0;
    n = telemetry_encode_frame(&f, &l, 0, buf);
    CHECK(n == 18 && u16(buf + 14) == 0, "empty frame: %zu bytes", n);

    // ---- stream for the Python decoder ------------------------------------------
    // text, frames 1-3 with frame 2 corrupted in transit, more text
    if (argc > 1) {
        FILE *out = fopen(argv[1], "wb");
        if (!out) { printf("cannot write %s\n", argv[1]); return 1; }
        fputs("debris_app: starting\r\n", out);
        for (uint32_t fn = 1; fn <= 3; fn++) {
            pattern_frame(&f, &l, fn);
            n = telemetry_encode_frame(&f, &l, 0, buf);
            if (fn == 2)
                buf[20] ^= 0x40;                // flip a bit in a centroid
            fwrite(buf, 1, n, out);
        }
        fputs("debris_app: done\r\n", out);
        fclose(out);
        printf("wrote %s (frame 2 corrupted)\n", argv[1]);
    }

    if (failures == 0)
        printf("TEST_TELEMETRY PASSED\n");
    else
        printf("TEST_TELEMETRY FAILED (%d)\n", failures);
    return failures != 0;
}
