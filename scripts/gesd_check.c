// gesd_check.c -- compare gesd_outliers (src/sw/classify.c) with MATLAB's
// isoutlier(...,'gesd') on the vectors from scripts/golden/gesd_vectors.m.
//
//   cc -O2 -Isrc/sw/include -o sim/build/gesd_check scripts/gesd_check.c \
//      src/sw/classify.c src/sw/hungarian.c src/sw/cost_matrix.c src/sw/geometry.c -lm
//   sim/build/gesd_check sim/build/gesd_vectors.csv [-v]
//
// Prints each mismatching case (-v: also the flagged indices) and a summary.
// Exit status 0 only if every case matches.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "centroid.h"
#include "classify.h"

#define MAX_LINE 65536

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s gesd_vectors.csv [-v]\n", argv[0]);
        return 2;
    }
    int verbose = argc > 2 && strcmp(argv[2], "-v") == 0;
    FILE *f = fopen(argv[1], "r");
    if (!f) { perror(argv[1]); return 2; }

    static char line[MAX_LINE];
    int cases = 0, bad = 0, too_many = 0, too_few = 0;
    while (fgets(line, sizeof line, f)) {
        char *p = line;
        int id = (int)strtol(p, &p, 10); p++;
        int K  = (int)strtol(p, &p, 10); p++;
        int n  = (int)strtol(p, &p, 10);
        if (n < 1 || n > MAX_CENTROIDS) continue;

        float v[MAX_CENTROIDS];
        int want[MAX_CENTROIDS], got[MAX_CENTROIDS];
        for (int i = 0; i < n; i++) { p++; v[i] = strtof(p, &p); }
        for (int i = 0; i < n; i++) { p++; want[i] = (int)strtol(p, &p, 10); }

        gesd_outliers(v, n, K, got);
        cases++;

        int nw = 0, ng = 0, diff = 0;
        for (int i = 0; i < n; i++) {
            nw += want[i];
            ng += got[i];
            diff += want[i] != got[i];
        }
        if (diff) {
            bad++;
            too_many += ng > nw;
            too_few += ng < nw;
            printf("case %4d  n=%3d K=%2d  MATLAB flags %2d, C flags %2d\n", id, n, K, nw, ng);
            if (verbose) {
                printf("   MATLAB:");
                for (int i = 0; i < n; i++) if (want[i]) printf(" %d(%.4g)", i, v[i]);
                printf("\n   C:     ");
                for (int i = 0; i < n; i++) if (got[i]) printf(" %d(%.4g)", i, v[i]);
                printf("\n");
            }
        }
    }
    fclose(f);
    printf("%d/%d cases match MATLAB", cases - bad, cases);
    if (bad)
        printf("  (C flags more: %d, fewer: %d, same count but different points: %d)",
               too_many, too_few, bad - too_many - too_few);
    printf("\n");
    return bad != 0;
}
