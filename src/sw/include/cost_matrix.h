#ifndef COST_MATRIX_H
#define COST_MATRIX_H

#include "centroid.h"

// Fills D with the euclidean distance between each pair of centroids
// D must be pre-allocated as a float D[n1][MAX_CENTROIDS]
void getCostMatrix(const Centroid *C1, int n1, const Centroid *C2, int n2, float D[MAX_CENTROIDS][MAX_CENTROIDS]);

// Fills T with the translation vector for each matched pair
void getTranslations(const Centroid *C1, const Centroid *C2, const Match *matches, int num_matches, Vec2 *T);

#endif // COST_MATRIX_H