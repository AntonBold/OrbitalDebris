// classify_replay.c -- run the PS classifier on the host, frame by frame,
// the way src/sw/main.c runs it on the board. Built and driven by
// scripts/classify_check.py; not part of the board build.
//
//   classify_replay <in.csv> [unmatched_cost [tm ta rc ra [d [K]]]]
//
// in.csv : frame,x,y rows, grouped by frame, in processing order. The
//          classifier memory is cleared whenever frame != previous frame + 1.
// Config is main.c's (centroid.h macros) unless given: unmatched_cost, the
// four feature switches (translation magnitude/angle, rotation center/angle),
// the delay d, and max_num_objects K. Memory holds the last 2*d frames
// (rotations need frames i-d and i-2d).
//
// Output: frame,index,label for every centroid, in input order.

#include <stdio.h>
#include <stdlib.h>
#include "centroid.h"
#include "classify.h"

#define MAX_D 20

static ClassifiedFrame memory[2 * MAX_D];
static int mem_len;
static ClassifiedFrame current;
static CentroidFrame next;

static void run(int frame, int count, int *memory_count, const ClassifierConfig *cfg)
{
    next.count = count;
    next.frame_number = (uint32_t)frame;
    classifyFrame(memory, *memory_count, &next, cfg, &current);
    for (int i = 0; i < current.frame.count; i++)
        printf("%d,%d,%d\n", frame, i, current.labels.labels[i]);

    if (*memory_count < mem_len) {
        memory[(*memory_count)++] = current;
    } else {
        for (int i = 0; i < mem_len - 1; i++)
            memory[i] = memory[i + 1];
        memory[mem_len - 1] = current;
    }
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s in.csv [unmatched_cost [tm ta rc ra [d [K]]]]\n", argv[0]);
        return 2;
    }
    FILE *f = fopen(argv[1], "r");
    if (!f) { perror(argv[1]); return 1; }

    ClassifierConfig cfg = {
        .unmatched_cost            = argc > 2 ? (float)atof(argv[2]) : UNMATCHED_COST,
        .use_translation_magnitude = argc > 3 ? atoi(argv[3]) : 1,
        .use_translation_angle     = argc > 4 ? atoi(argv[4]) : 1,
        .use_rotation_center       = argc > 5 ? atoi(argv[5]) : 1,
        .use_rotation_angle        = argc > 6 ? atoi(argv[6]) : 0,
        .delta                     = argc > 7 ? atoi(argv[7]) : DELTA,
        .max_num_objects           = argc > 8 ? atoi(argv[8]) : MAX_OBJECTS,
    };
    if (cfg.delta < 1 || cfg.delta > MAX_D) {
        fprintf(stderr, "d must be 1..%d\n", MAX_D);
        return 2;
    }
    mem_len = 2 * cfg.delta;

    int memory_count = 0, cur = -1, count = 0, frame;
    double x, y;
    while (fscanf(f, "%d,%lf,%lf\n", &frame, &x, &y) == 3) {
        if (frame != cur) {
            if (cur >= 0)
                run(cur, count, &memory_count, &cfg);
            if (frame != cur + 1)
                memory_count = 0;
            cur = frame;
            count = 0;
        }
        if (count < MAX_CENTROIDS) {
            next.centroids[count].x = x;
            next.centroids[count].y = y;
            next.centroids[count].area = 0;
            count++;
        }
    }
    if (cur >= 0)
        run(cur, count, &memory_count, &cfg);
    fclose(f);
    return 0;
}
