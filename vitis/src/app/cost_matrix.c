#include "include/cost_matrix.h"
#include "include/centroid.h"
#include <math.h>

void getCostMatrix(const Centroid *C1, int n1, const Centroid *C2, int n2, float D[MAX_CENTROIDS][MAX_CENTROIDS])
{
    for(int i = 0; i < n1; i++) {
        for (int j = 0; j < n2; j++) {
            float dx = C1[i].x - C2[j].x;
            float dy = C2[i].y - C2[j].y;
            D[i][j] = sqrtf(dx*dx + dy*dy);
        }
    }
}

void getTranslations(const Centroid *C1, const Centroid *C2, const Match *matches, int num_matches, Vec2 *T) 
{
    for (int i = 0; i < num_matches; i++) {
        T[i].x = C2[matches[i].to].x - C1[matches[i].from].x;
        T[i].y = C2[matches[i].to].y - C1[matches[i].from].y;
    }    
}