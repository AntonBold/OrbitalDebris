// track_replay.c -- run the PS tracker (src/sw/track.c, trackStep) on the
// host, frame by frame, the way src/sw/main.c runs it. Built and driven by
// scripts/track_check.py; not part of the board build.
//
//   track_replay <in.csv> given    [uc]
//   track_replay <in.csv> classify [uc tm ta rc ra d K]
//
// in.csv : frame,x,y,label rows, grouped by frame, in processing order.
// given    : track the labels in the file (e.g. MATLAB's), so only the
//            tracker is tested. label -2 (not classified) counts as unknown.
// classify : run classifyFrame first (as main.c) and track its labels.
//
// Output: frame,index,label,tag for every centroid, in input order
// (tag -1: not an object, or untagged).

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "centroid.h"
#include "classify.h"
#include "track.h"

#define MAX_D 20

static ClassifiedFrame memory[2 * MAX_D];
static int mem_len, memory_count;
static ClassifiedFrame clf;
static TrackerState tracker;

static CentroidFrame in_frame;
static int8_t in_labels[MAX_CENTROIDS];

static void run(int frame, int classify, const ClassifierConfig *cfg)
{
    if (classify) {
        classifyFrame(memory, memory_count, &in_frame, cfg, &clf);
        if (memory_count < mem_len) {
            memory[memory_count++] = clf;
        } else {
            for (int i = 0; i < mem_len - 1; i++)
                memory[i] = memory[i + 1];
            memory[mem_len - 1] = clf;
        }
    } else {
        clf.frame = in_frame;
        clf.labels.count = in_frame.count;
        for (int i = 0; i < in_frame.count; i++)
            clf.labels.labels[i] = in_labels[i];
    }

    trackStep(&tracker, &clf, cfg);

    // per-spot tags, as main.c sends them over telemetry
    static int32_t tags[MAX_CENTROIDS];
    trackTagsBySpot(&clf.labels, &tracker.current, tags);
    for (int i = 0; i < clf.labels.count; i++)
        printf("%d,%d,%d,%d\n", frame, i, clf.labels.labels[i], (int)tags[i]);
}

int main(int argc, char **argv)
{
    if (argc < 3 || (strcmp(argv[2], "given") && strcmp(argv[2], "classify"))) {
        fprintf(stderr, "usage: %s in.csv given|classify [uc [tm ta rc ra d K]]\n", argv[0]);
        return 2;
    }
    FILE *f = fopen(argv[1], "r");
    if (!f) { perror(argv[1]); return 1; }
    int classify = strcmp(argv[2], "classify") == 0;

    int na = argc - 3;
    char **v = argv + 3;
    ClassifierConfig cfg = {
        .unmatched_cost            = na > 0 ? (float)atof(v[0]) : UNMATCHED_COST,
        .use_translation_magnitude = na > 1 ? atoi(v[1]) : 1,
        .use_translation_angle     = na > 2 ? atoi(v[2]) : 1,
        .use_rotation_center       = na > 3 ? atoi(v[3]) : 1,
        .use_rotation_angle        = na > 4 ? atoi(v[4]) : 0,
        .delta                     = na > 5 ? atoi(v[5]) : DELTA,
        .max_num_objects           = na > 6 ? atoi(v[6]) : MAX_OBJECTS,
    };
    if (cfg.delta < 1 || cfg.delta > MAX_D) {
        fprintf(stderr, "d must be 1..%d\n", MAX_D);
        return 2;
    }
    mem_len = 2 * cfg.delta;

    int cur = -1, count = 0, frame, label;
    double x, y;
    while (fscanf(f, "%d,%lf,%lf,%d\n", &frame, &x, &y, &label) == 4) {
        if (frame != cur) {
            if (cur >= 0)
                run(cur, classify, &cfg);
            cur = frame;
            count = 0;
            in_frame.frame_number = (uint32_t)frame;
        }
        if (count < MAX_CENTROIDS) {
            in_frame.centroids[count].x = x;
            in_frame.centroids[count].y = y;
            in_frame.centroids[count].area = 0;
            in_labels[count] = (int8_t)(label == -2 ? LABEL_UNKNOWN : label);
            in_frame.count = ++count;
        }
    }
    if (cur >= 0)
        run(cur, classify, &cfg);
    fclose(f);
    return 0;
}
