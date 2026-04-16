#include "include/classify.h"
#include "include/cost_matrix.h"
#include "include/hungarian.h"
#include "include/geometry.h"
#include "include/centroid.h"
#include "include/classify.h"
#include <math.h>
#include <string.h>
#include <stdio.h>

// static int gesd_debug = 1; 

// math helpers

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

// Approximation of the inverse t-distribution CDF
// Uses a rational approximation - accurate enough for our purposes
// Returns t such that P(T <= t) = p for T ~ t(df)
static float t_inv(float p, int df)
{
    // use normal approximation for large df
    if (df > 100) {
        // Rational approximation of normal inverse CDF (Beasley-Springer-Moro)
        float q = p - 0.5f;
        float r;
        if (fabsf(q) <= 0.42f) {
            r = q * q;
            return q * ((((-25.4410604f * r + 41.3911977f) * r
                          - 18.6150006f) * r + 2.5066282f)
                        / ((((3.13082909f * r - 21.0622410f) * r
                             + 23.0833674f) * r - 8.4735109f) * r + 1.0f));
        } else {
            r = (q > 0) ? (1.0f - p) : p;
            r = sqrtf(-logf(r));
            float t = (((1.4272223f * r + 3.0271426f) * r
                        - 0.4533108f) * r - 2.9729552f)
                      / ((1.6370678f * r + 3.5425892f) * r + 1.0f);
            return (q > 0) ? t : -t;
        }
    }

    // For smaller df, use a simple iterative approximation
    // based on the relationship between t and F distributions
    float z = t_inv(p, 10000); // start with normal approx
    float correction = (z * z * z + z) / (4.0f * df);
    return z + correction;
}

// -- GESD outlier detection --
// Implements Rosner (1983) Generalized ESD test
// Alpha = 0.05 significance level
void gesd_outliers(const float *values, int count, int max_outliers, int *is_outlier)
{
    for (int i = 0; i < count; i++) is_outlier[i] = 0;

    if (count < 3 || max_outliers <= 0) return;

    int r = max_outliers;
    if (r > count / 2) r = count / 2;

    float working[MAX_CENTROIDS];
    int working_idx[MAX_CENTROIDS]; // original indices
    for (int i = 0; i < count; i++) {
        working[i] = values[i];
        working_idx[i] = i;
    }

    float R[MAX_CENTROIDS]; // test statistics
    int removed_idx[MAX_CENTROIDS]; // which original indices were removed
    int n = count;

    // Compute r test statistics by iteratively removing the most extreme value
    for (int i = 0; i < r; i++) {
        float mean = array_mean(working, n);
        float std = array_std(working, n, mean);
        if (std < 1e-6f) break; // cant compute meaningful statistic

        if (std < 1e-10f) break;

        // find the value that maximized |x - mean|
        float max_dev = -1.0f;
        int max_j = 0;
        for (int j = 0; j < n; j++) {
            float dev = fabsf(working[j] - mean);
            if (dev > max_dev) {
                max_dev = dev;
                max_j = j;
            }
        }

        R[i] = max_dev / std;
        removed_idx[i] = working_idx[max_j];

        // remove the most extreme value
        for (int j = max_j; j < n - 1; j++) {
            working[j] = working[j + 1];
            working_idx[j] = working_idx[j + 1];
        }
        n--;
    }

    // compute critical values and find largest i where R[i] > lambda[i]
    float alpha = 0.05f;
    int num_outliers = 0;

    for (int i = 0; i < r; i++) {
        int ni = count - i;
        float p = 1.0f - alpha / (2.0f * (count - i + 1));
        int df = ni - 2;

        if (df < 1) break;

        float t = t_inv(p, df);
        float t2 = t * t;
        float lambda = ((float)(ni) * t)
               / sqrtf(((float)(ni - 1) + t2) * (float)(ni + 1));
        // if (gesd_debug) {
        //     printf("i=%d R=%.4f lambda=%.4f n=%d df=%d t=%.4f\n",
        //             i, R[i], lambda, ni, df, t);
        // }

        if (R[i] > lambda)
            num_outliers = i + 1;
    }

    //printf("DEBUG num_outliers=%d\n", num_outliers);

    // Mark the first num_outliers removed indices as outliers
    for (int i = 0; i < num_outliers; i++)
        is_outlier[removed_idx[i]] = 1;
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

    // DEBUG — print first frame's translations
    static int print_count = 0;
    if (print_count < 3 && nm > 0) {
        print_count++;
        // printf("=== Translation debug frame call %d (nm=%d) ===\n", print_count, nm);
        // for (int i = 0; i < nm && i < 5; i++) {
        //     printf("  T[%d] = (%.4f, %.4f) mag=%.4f\n",
        //            i,
        //            out->translations[i].x,
        //            out->translations[i].y,
        //            sqrtf(out->translations[i].x * out->translations[i].x +
        //                  out->translations[i].y * out->translations[i].y));
        // }
    }
    
    // printf("DEBUG nm=%d before labeling\n", nm);
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
}