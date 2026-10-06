#ifndef HUNGARIAN_H
#define HUNGARIAN_H

#include "centroid.h"

// Finds the optimal assignment between n1 points in C1 and n2 points in C2
// using the Hungarian algorithm on the provided cost matrix.
// Only matches where cost < unmatched_cost are included.
// Returns the number of matches found.
int hungarian(float D[MAX_CENTROIDS][MAX_CENTROIDS], int n1, int n2, float unmatched_cost, Match *matches_out);

#endif // HUNGARIAN_H