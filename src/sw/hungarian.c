#include "include/hungarian.h"
#include "include/centroid.h"
#include <float.h>

#define N_MAX (2 * MAX_CENTROIDS)
#define BIG   1e30f

// Hungarian algorithm (Munkres assignment), solving the same problem as
// MATLAB matchpairs (paper Algorithm 4):
//   minimize  sum of matched D[i][j]  +  unmatched_cost * (unmatched rows + unmatched columns)
// The n1 x n2 matrix is extended to (n1+n2) x (n1+n2) so any row or column
// can stay unmatched at unmatched_cost. A pair is matched only when that is
// cheaper than leaving both ends unmatched (D < 2 * unmatched_cost at most).

int hungarian(float D[MAX_CENTROIDS][MAX_CENTROIDS], int n1, int n2, float unmatched_cost, Match *matches_out)
{
    int n = n1 + n2; // matchpairs: every row and column may stay unmatched at unmatched_cost

    static float cost[N_MAX][N_MAX];
    static unsigned char starred[N_MAX][N_MAX];
    static unsigned char primed[N_MAX][N_MAX];
    int row_covered[N_MAX] = {0};
    int col_covered[N_MAX] = {0};
    for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++) { starred[i][j] = 0; primed[i][j] = 0; }


    // Build the (n1+n2) square matrix:
    //   top-left     D               real pairs
    //   top-right    uc on diagonal  row i left unmatched (BIG elsewhere)
    //   bottom-left  uc on diagonal  column j left unmatched (BIG elsewhere)
    //   bottom-right 0               dummy to dummy, free
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
             if (i < n1 && j < n2)
                cost[i][j] = D[i][j];                                   // real pair
            else if (i < n1)
                cost[i][j] = (j - n2 == i) ? unmatched_cost : BIG;      // row i unmatched
            else if (j < n2)
                cost[i][j] = (i - n1 == j) ? unmatched_cost : BIG;      // column j unmatched
            else
                cost[i][j] = 0.0f;                                      // dummy-dummy
        }
    }
    
    // step 1: subtract row minimums
    for (int i = 0; i < n; i++){
        float min = cost[i][0];
        for (int j = 1; j < n; j++)
            if (cost[i][j] < min) min = cost[i][j];
        for (int j = 0; j < n; j++)
            cost[i][j] -= min;
    }   

    // step 2: subtract column minimums
    for (int j = 0; j < n; j++) {
        float min = cost [0][j];
        for (int i = 1; i < n; i++)
            if (cost[i][j] < min) min = cost[i][j];
        for (int i = 0; i < n; i++)
            cost[i][j] -= min;
    }

    // step 3: star zeros
    int row_has_star[N_MAX] = {0};
    int col_has_star[N_MAX] = {0};
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            if (cost[i][j] == 0.0f && !row_has_star[i] && !col_has_star[j]) {
                starred[i][j] = 1;
                row_has_star[i] = 1;
                col_has_star[j] = 1;
            }
        }
    }

    // main loop
    while (1) {
        // Step 4: cover columns with starred zeros
        int covered_count = 0;
        for (int j = 0; j < n; j++) {
            col_covered[j] = 0;
            for (int i = 0; i < n; i ++) {
                if (starred[i][j]) {
                    col_covered[j] = 1;
                    covered_count++;
                    break;
                }
            }
        }

        if (covered_count >= n)
            break; // optimal assignment found

        // step 5: Find an uncovered zero and prime it
        while(1) {
            int found_row = -1, found_col = -1;
            for (int i = 0; i < n && found_row == -1; i ++) {
                if (row_covered[i]) continue;
                for (int j = 0; j < n; j++) {
                    if (!col_covered[j] && cost[i][j] == 0.0f) {
                        found_row = i;
                        found_col = j;
                        break;
                    }
                }
            }
            
            if (found_row == -1) {
                // Step 6: no uncovered zero - adjust matrix
                float min = FLT_MAX;
                for (int i = 0; i < n; i++) {
                    if (row_covered[i]) continue;
                    for (int j = 0; j < n; j++) {
                        if (!col_covered[j] && cost[i][j] < min)
                            min = cost[i][j];
                    }
                }
                for (int i = 0; i < n; i++) {
                    for (int j = 0; j < n; j++) {
                        if (row_covered[i]) cost[i][j] += min;
                        if (!col_covered[j]) cost[i][j] -= min;
                    }
                }
                continue;
            }
            
            primed[found_row][found_col] = 1;

            // is there a starred zero in this row?
            int star_col = -1;
            for (int j = 0; j < n; j++) {
                if (starred[found_row][j]) {
                    star_col = j;
                    break;
                }
            }

            if (star_col == -1) {
                // step 5b: augment path
                int path_row[N_MAX * 2];
                int path_col[N_MAX * 2];
                int path_len = 1;
                path_row[0] = found_row;
                path_col[0] = found_col;
                
                while (1){
                    // Find starred zero in column
                    int pc = path_col[path_len - 1];
                    int sr = -1;
                    for (int i = 0; i < n; i++) {
                        if (starred[i][pc]) { sr = i; break; }
                    }
                    if (sr == -1) break;

                    path_row[path_len] = sr;
                    path_col[path_len] = pc;
                    path_len++;

                    // Find primed zero in row
                    int sc = -1;
                    for (int j = 0; j < n; j++) {
                        if (primed[sr][j]) {sc = j; break; }
                    }
                    path_row[path_len] = sr;
                    path_col[path_len] = sc;
                    path_len++;
                }

                // flip stars along path
                for (int k = 0; k < path_len; k++) {
                    int r = path_row[k], c = path_col[k];
                    starred[r][c] = starred[r][c] ? 0 : 1;
                }
                
                // clear covers and primes
                for (int i = 0; i < n; i++) {
                    row_covered[i] = 0;
                    col_covered[i] = 0;
                    for (int j = 0; j < n; j++)
                        primed[i][j] = 0;
                }
                break;
            } else {
                row_covered[found_row] = 1;
                col_covered[star_col] = 0;
            }
        }
    }

    // extract assignment from starred zeros
    int count = 0;
    for (int i = 0; i < n1; i++) {
        for (int j = 0; j < n2; j++) {
            if (starred[i][j]) {
                matches_out[count].from = i;
                matches_out[count].to = j;
                count ++;
            }
        }
    }

    return count;
}