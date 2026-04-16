#ifndef CLASSIFY_H
#define CLASSIFY_H

#include "centroid.h"

// Configuration for the classifier
typedef struct {
    float unmatched_cost;
    int max_num_objects;
    int delta;
    int use_translation_magnitude;
    int use_translation_angle;
    int use_rotation_center;
    int use_rotation_angle;
} ClassifierConfig;

// Holds all state for one frame's classification output
typedef struct {
    CentroidFrame frame;
    LabelSet labels;
    MatchSet matches;
    Vec2 translations[MAX_CENTROIDS];
    RotationSet rotations;
    int prev_frame_idx; // index of previous frame in memory
} ClassifiedFrame;

// classify a new frame of centroids given the memory of previous frames.
// memory       : ring buffer of previous ClassifiedFrames, size = delta
// memory_count : how many frames are currently in memory (fills up to delta)
// new_frame    : the new frame of centroids to classify
// config       : classifier settings
// out          : output classification for this frame
void classifyFrame(ClassifiedFrame *memory, int memory_count, const CentroidFrame *new_frame, 
                   const ClassifierConfig *config, ClassifiedFrame *out);

// Returns a bitmask array of which indices are outliers
// values     : input array
// count      : number of elements
// max_outliers: upper bound on number of outliers (r)
// is_outlier : output array, 1 = outlier, 0 = not, must be size count
void gesd_outliers(const float *values, int count, int max_outliers, int *is_outlier);


#endif // CLASSIFY_H