#include <stdio.h>
#include <string.h>
#include <math.h>
#include "centroid.h"
#include "classify.h"
#include "track.h"

#define CSV_PATH "/Users/adamwelsh/Desktop/Capstone/centroids.csv"

// -- ground truth storage --

typedef struct {
    CentroidFrame frame;
    int8_t ground_truth[MAX_CENTROIDS]; // 1=object, 0=star 
} GroundTruthFrame;

static GroundTruthFrame gt_frames[MAX_FRAMES];
static int n_frames = 0;

// performance metrics 

typedef struct {
    int TP; // correctly labeled object
    int TN; // correctly labeled star
    int FP; // star labeled as object
    int FN; // object labeled as star
    int UNK; // labeled unknown
} FrameMetrics;

// Load CSV

static int load_csv(const char *path)
{
    FILE *f = fopen(path, "r");
    if (!f) {
        printf("ERROR: could not open %s\n", path);
        return -1;
    }

    int frame, label;
    float x, y;
    int current_frame = -1;

    while (fscanf(f, "%d,%f,%f,%d\n", &frame, &x, &y, &label) == 4) {
        if (frame != current_frame) {
            if (frame > MAX_FRAMES) {
                printf("ERROR: frame %d exceeds MAX_FRAMES\n", frame);
                fclose(f);
                return -1;
            }
            current_frame = frame;
            gt_frames[frame].frame.count = 0;
            if (frame + 1 > n_frames)
                n_frames = frame + 1;
        }

        int idx = gt_frames[frame].frame.count;
        if (idx >= MAX_CENTROIDS) continue;

        gt_frames[frame].frame.centroids[idx].x = x;
        gt_frames[frame].frame.centroids[idx].y = y;
        gt_frames[frame].ground_truth[idx] = (int8_t) label;
        gt_frames[frame].frame.count++;
    }

    fclose(f);
    printf("Loaded %d frames from CSV\n", n_frames);
    return 0;
}

// Compute metrics for one frame

static FrameMetrics compute_metrics(const LabelSet *predicted, const int8_t *ground_truth, int count)
{
    FrameMetrics m = {0};

    for (int i = 0; i < count; i++) {
        int8_t pred = predicted->labels[i];
        int8_t gt = ground_truth[i];

        if(pred == LABEL_UNKNOWN) {
            m.UNK++;
        } else if (pred == LABEL_OBJECT && gt == 1) {
            m.TP++;
        } else if (pred == LABEL_STAR && gt == 0) {
            m.TN++;
        } else if (pred == LABEL_OBJECT && gt == 0) {
            m.FP++;
        } else if (pred == LABEL_STAR && gt == 1) {
            m.FN++;
        }
    }

    return m;
}

// main

int main(void)
{
    printf("=== Debris Tracker Test Harness ===\n\n");
    
    // Load CSV
    if (load_csv(CSV_PATH) < 0)
        return -1;

    // classifier config - matches matlab params
    ClassifierConfig config = {
        .unmatched_cost             = 100.0f,
        .max_num_objects            = 10,
        .delta                      = 10,
        .use_translation_magnitude  = 1,
        .use_translation_angle      = 1,
        .use_rotation_center        = 1,
        .use_rotation_angle         = 0,
    };

    // State
    ClassifiedFrame clf_memory[DELTA];
    int clf_memory_count = 0;
    ClassifiedFrame clf_current;

    // accumulate metrics
    int total_TP = 0, total_TN = 0;
    int total_FP = 0, total_FN = 0;
    int total_UNK = 0;
    int total_spots = 0;

    printf("%-8s %-8s %-8s %-8s %-8s %-8s %-8s\n", 
           "Frame", "Spots", "Obj_GT", "TP", "TN", "FP+FN", "UNK");
    printf("--------------------------------------------------------\n");

    for (int t = 0; t < n_frames; t++) {
        CentroidFrame *frame = &gt_frames[t].frame;
        int8_t *gt = gt_frames[t].ground_truth;

        // Run Classifier
        classifyFrame(clf_memory, clf_memory_count, frame, &config, & clf_current);

        // compute metrics
        FrameMetrics m = compute_metrics(&clf_current.labels, gt, frame->count);

        total_TP += m.TP;
        total_TN += m.TN;
        total_FP += m.FP;
        total_FN += m.FN;
        total_UNK += m.UNK;
        total_spots += frame->count;

        // count ground truth objects
        int gt_objects = 0;
        for (int i = 0; i < frame->count; i++)
            if (gt[i] == 1) gt_objects++;
        
        // print per frame summary every 10 frames
        if (t % 10 == 0) {
            printf("%-8d %-8d %-8d %-8d %-8d %-8d %-8d\n",
                   t, frame->count, gt_objects,
                   m.TP, m.TN, m.FP + m.FN, m.UNK);
        }

        // update classifier memory
        if (clf_memory_count < DELTA) {
            clf_memory[clf_memory_count++] = clf_current;
        } else {
            for (int i = 0; i < DELTA - 1; i++)
                clf_memory[i] = clf_memory[i+1];
            clf_memory[DELTA-1] = clf_current;
        }
    }

    // final summary 
    int total_p = total_TP + total_FN;
    int total_n = total_TN + total_FP;
    
    float TPR = total_p > 0 ? (float)total_TP / total_p : 0.0f;
    float TNR = total_n > 0 ? (float)total_TN / total_n : 0.0f;
    float UNK = total_spots > 0 ? (float) total_UNK / total_spots : 0.0f;

    printf("\n=== Final Results ===\n");
    printf("Frames processed : %d\n", n_frames);
    printf("Total spots      : %d\n", total_spots);
    printf("TPR (Recall)     : %.4f\n", TPR);
    printf("TNR (Specificity): %.4f\n", TNR);
    printf("Unknown rate     : %.4f\n", UNK);
    printf("TP: %d  TN: %d  FP: %d  FN: %d  UNK: %d\n",
           total_TP, total_TN, total_FP, total_FN, total_UNK);

    return 0;
}