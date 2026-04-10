#include "include/classify.h"
#include "include/cost_matrix.h"
#include "include/hungarian.h"
#include "include/geometry.h"
#include "include/centroid.h"
#include "include/classify.h"
#include <math.h>
#include <string.h>

// -- isOutlier --
// Simplified outlier detection to replace MATLAB's isoutlier(..., 'gesd')
// Uses median absolute deviation (MAD) method - robust and cheap to compute
// returns 1 if values [idx] is an outlier, writes results to is_outlier array

static float median(float *arr, int n)
{
    // simple insertion sort for small arrays
    float sorted[MAX_CENTROIDS];
    for (int i = 0; i < n; i++) sorted[i] = arr[i];
    for (int i = 1; i < n; i++) {
        float key = sorted[i];
        int j = i - 1;
        while (j >= 0 && sorted[j] > key) {
            sorted[j+1] = sorted[j];
            j--;
        }
        sorted[j+1] = key;
    }
    if (n%2 == 0)
        return (sorted[n/2 - 1] + sorted[n/2]) / 2.0f;
    return sorted[n/2];
}

int isOutlier(float *values, int count, int max_outliers)
{
    if (count < 2) return 0;
    
    float med = median(values, count);
    
    float deviations[MAX_CENTROIDS];
    for (int i = 0; i < count; i++)
        deviations[i] = fabsf(values[i] - med);

    float mad = median(deviations, count);

    // MAD-based outlier threshold (3.5 sigma equivalent)
    float threshold = 3.5f * mad / 0.6745f;

    int outlier_count = 0;
    for (int i = 0; i < count; i++) {
        if (deviations[i] > threshold)
            outlier_count++;
    }

    // Respect max_outliers cap
    return outlier_count <= max_outliers ? outlier_count : max_outliers;
}

// -- classifyFrame --

void classifyFrame(ClassifiedFrame *memory, int memory_count, const CentroidFrame *new_frame,
                   const ClassifierConfig *config, ClassifiedFrame *out)
{
    // copy new frame into output
    out->frame = *new_frame;
    out->rotations.count = 0;
    out->matches.count = 0;
    out->prev_frame_idx = -1;

    // initialize all labels to unkown

    for (int i = 0; i < new_frame->count; i++)
        out->labels.labels[i] = LABEL_UNKNOWN;
    out->labels.count = new_frame->count;

    // need at least one previous frame to classify
    if (memory_count == 0)
        return;

    ClassifiedFrame *prev = &memory[memory_count - 1];
    const CentroidFrame *C1 = &prev->frame;
    const CentroidFrame *C2 = new_frame;

    int n1 = C1->count;
    int n2 = C2->count;

    // skip if centroid counts differ too much
    if (fabsf((float) n1 -n2) >= config->max_num_objects)
        return;
    
    // build cost matrix
    float D[MAX_CENTROIDS][MAX_CENTROIDS];
    getCostMatrix(C1->centroids, n1, C2->centroids, n2, D);

    // apply translation prediction if we have previous matches
    if (prev->matches.count > 0) {
        Vec2 T[MAX_CENTROIDS] = {0};
        for (int k = 0; k < prev->matches.count; k++) {
            int idx = prev->matches.matches[k].to;
            T[idx] = prev->translations[k];
        }

        CentroidFrame C1_predicted = *C1;
        for (int i = 0; i < n1; i++) {
            C1_predicted.centroids[i].x += T[i].x;
            C1_predicted.centroids[i].y += T[i].y;
        }
        getCostMatrix(C1_predicted.centroids, n1, C2->centroids, n2, D);
    }   

    // Run hungarian algorithm
    Match matches[MAX_CENTROIDS];
    int nm = hungarian(D, n1, n2, config->unmatched_cost, matches);

    // store matches
    for (int i = 0; i < nm; i++)
        out->matches.matches[i] = matches[i];
    out->matches.count = nm;

    // compute translations
    getTranslations(C1->centroids, C2->centroids, matches, nm, out->translations);

    // label matched centroids based on translation outliers
    if (nm > 0) {
        int8_t tf[MAX_CENTROIDS] = {0};

        if (config->use_translation_magnitude) {
            float magnitudes[MAX_CENTROIDS];
            for (int i = 0; i < nm; i++) {
                float dx = out->translations[i].x;
                float dy = out->translations[i].y;
                magnitudes[i] = sqrtf(dx*dx + dy+dy);
            }
            int n_outliers = isOutlier(magnitudes, nm, config->max_num_objects);
            
            // mark top outliers
            float med = median(magnitudes, nm);
            for (int i = 0; i < nm && n_outliers > 0; i++) {
                if (fabsf(magnitudes[i] - med) > 3.5f) {
                    tf[i] = 1;
                    n_outliers--;
                }
            }
        }

        if (config->use_translation_angle) {
            float angles[MAX_CENTROIDS];
            for (int i = 0; i < nm; i ++)
                angles[i] = atan2f(out->translations[i].y, out->translations[i].x);
            int n_outliers = isOutlier(angles, nm, config->max_num_objects);
            float med = median(angles, nm);
            for (int i = 0; i < nm && n_outliers > 0; i++) {
                if (fabsf(angles[i] - med) > 3.5f) {
                    tf[i] |= 1;
                    n_outliers--;
                }
            }
        }
        
        // assign labels to matched centroids
        for (int i = 0; i < nm; i++)
            out->labels.labels[matches[i].to] = tf[i] ? LABEL_OBJECT : LABEL_STAR;  
    }
}