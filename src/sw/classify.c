#include "include/classify.h"
#include "include/cost_matrix.h"
#include "include/hungarian.h"
#include "include/geometry.h"
#include "include/centroid.h"
#include <math.h>
#include <string.h>
#include <stdio.h>
#include "include/gesd_table.h"

static float array_mean (const float *arr, int n)
{
    float sum = 0.0f;
    for (int i = 0; i < n; i++) sum += arr[i];
    return sum / n;
}

static float array_std(const float *arr, int n, float mean)
{
    float sum = 0.0f;
    for (int i = 0; i < n; i++) {
        float d = arr[i] - mean;
        sum += d * d;
    }
    return sqrtf(sum / (n - 1));
}



// -- GESD outlier detection --
// Implements Rosner (1983) Generalized ESD test
// Alpha = 0.05 significance level
void gesd_outliers(const float *values, int count, int max_outliers, int *is_outlier)
{
    for (int i = 0; i < count; i++) is_outlier[i] = 0;
    if (count < 3 || max_outliers <= 0) return;

    int r = max_outliers < count ? max_outliers : count;

    float working[MAX_CENTROIDS];
    
    for (int i = 0; i < count; i++)
        working[i] = values[i];

    float step_mean[MAX_CENTROIDS], step_std[MAX_CENTROIDS], step_lam[MAX_CENTROIDS];
    int n = count;
    int last = 0;

    for (int k = 0; k < r; k++) 
    {
        float mean = array_mean(working, n);
        float std = n > 1 ? array_std(working, n, mean) : 0.0f;
        float lam = n >= 3 ? GESD_LAMBDA[n] : 0.0f;
        step_mean[k] = mean;
        step_std[k] = std;
        step_lam[k] = lam;
        if (std == 0.0f) break;

        float max_dev = -1.0f;
        int max_j = 0;
        for (int j = 0; j < n; j++) {
            float dev = fabsf(working[j] - mean);
            if (dev > max_dev) 
            { 
                max_dev = dev; 
                max_j = j;
            }
        }
        if (lam > 0.0f && max_dev / std > lam)
            last = k + 1;

        for (int j = max_j; j < n - 1; j++)
            working[j] = working[j + 1];

        n--;
    }
    // baounds come from the step after the last significant one (MATLAB isoutlier).
    // last is 1-based
    int t = last;
    if (t > r - 1)
        t = r -1;

    if (step_lam[t] == 0.0f) return;
    float lo = step_mean[t] - step_std[t] * step_lam[t];
    float hi = step_mean[t] + step_std[t] * step_lam[t];

    for (int i = 0; i < count; i++)
        if (values[i] < lo || values[i] > hi)
            is_outlier[i] = 1;
}

// -- classifyFrame --

void classifyFrame(ClassifiedFrame *memory, int memory_count, const CentroidFrame *new_frame,
                   const ClassifierConfig *config, ClassifiedFrame *out)
{
    // copy new frame into output
    out->frame = *new_frame;
    out->rotations.count = 0;
    out->matches.count = 0;

    // initialize all labels to unkown

    for (int i = 0; i < new_frame->count; i++)
        out->labels.labels[i] = LABEL_UNKNOWN;
    out->labels.count = new_frame->count;
    
    // match against the frame d back
    int d = config->delta;
    if (memory_count < d)
        return;

    ClassifiedFrame *prev = &memory[memory_count - d];
    const CentroidFrame *C1 = &prev->frame;
    const CentroidFrame *C2 = new_frame;

    int n1 = C1->count;
    int n2 = C2->count;

    // skip if centroid counts differ too much
    if (fabsf((float) n1 -n2) >= config->max_num_objects)
        return;
    
    // predict where prev's points are now (rotation, else translation), then cost matrix
    Centroid C1_predicted[MAX_CENTROIDS];
    predictPositions(C1->centroids, n1, &prev->matches, prev->translations,
                     &prev->rotations, C1_predicted);
    float D[MAX_CENTROIDS][MAX_CENTROIDS];
    getCostMatrix(C1_predicted, n1, C2->centroids, n2, D);


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
        int is_outlier[MAX_CENTROIDS] = {0};
        int8_t tf[MAX_CENTROIDS] = {0};

        if (config->use_translation_magnitude) {
            float magnitudes[MAX_CENTROIDS];
            for (int i = 0; i < nm; i++) {
                float dx = out->translations[i].x;
                float dy = out->translations[i].y;
                magnitudes[i] = sqrtf(dx*dx + dy*dy);
            }
            gesd_outliers(magnitudes, nm, config->max_num_objects, is_outlier);
            // gesd_debug = 0;
            for (int i = 0; i < nm; i++)
                tf[i] |= is_outlier[i];
        }

        if (config->use_translation_angle) {
            float angles[MAX_CENTROIDS];
            for (int i = 0; i < nm; i ++)
                angles[i] = atan2f(out->translations[i].y, out->translations[i].x);
            gesd_outliers(angles, nm, config->max_num_objects, is_outlier);
            for(int i = 0; i < nm; i++)
                tf[i] |= is_outlier[i];
        }
        
        // assign labels to matched centroids
        for (int i = 0; i < nm; i++)
            out->labels.labels[matches[i].to] = tf[i] ? LABEL_OBJECT : LABEL_STAR;  
    }

    // Rotation labeling: triplets from frames i-2d, i-d, i (paper Algorithm 1)

    // requires frames i-d and i-2d in memory
    if (memory_count >= 2*d && (config->use_rotation_center || config->use_rotation_angle)) {

        // prev1's matches go from prev2 to prev1, so prev2 is d frames before it
        ClassifiedFrame *prev1 = &memory[memory_count - d];
        ClassifiedFrame *prev2 = &memory[memory_count - 2 * d];


        // only proceed if prev1 has matches back to prev2
        if (prev1->matches.count > 0 && nm > 0) {
            RotationSet R;
            getRotations(prev2->frame.centroids, prev1->frame.centroids,
                         C2->centroids, prev1->matches.matches,
                         prev1->matches.count, matches, nm, &R);
            

            if (R.count > 0) {
                int is_outlier[MAX_CENTROIDS] = {0};
                int8_t rot_tf[MAX_CENTROIDS] = {0};

                if (config->use_rotation_center) {
                    float distances[MAX_CENTROIDS];
                    getDistanceFromMedianCenter(&R, distances);

                   
                    gesd_outliers(distances, R.count, config->max_num_objects, is_outlier);
                    for (int i = 0; i < R.count; i++)
                        rot_tf[i] |= is_outlier[i];
                }

                if (config->use_rotation_angle) {
                    float angles[MAX_CENTROIDS];
                    for(int i = 0; i < R.count; i++)
                        angles[i] = R.rotations[i].angle;
                    gesd_outliers(angles, R.count, config->max_num_objects, is_outlier);
                    for (int i = 0; i < R.count; i++)
                        rot_tf[i] |= is_outlier[i];
                }

                // only label something as object if both translation and rotation agree
                for (int i = 0; i < R.count; i++) {
                    int centroid_idx = R.rotations[i].i3;
                    int8_t current = out->labels.labels[centroid_idx];
                    int8_t rot_label = rot_tf[i] ? LABEL_OBJECT : LABEL_STAR;

                    if (current == LABEL_UNKNOWN) {
                        out->labels.labels[centroid_idx] = rot_label;
                    } else if (current == LABEL_STAR && rot_label == LABEL_OBJECT) {
                        out->labels.labels[centroid_idx] = LABEL_OBJECT;
                    } else if (current == LABEL_OBJECT) {
                        out->labels.labels[centroid_idx] = LABEL_OBJECT;
                    } else {
                        out->labels.labels[centroid_idx] = LABEL_STAR;
                    }
                }

                // store rotations for next frame
                out->rotations = R;
            }
        }
    }
}