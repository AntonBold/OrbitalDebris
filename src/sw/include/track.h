#ifndef TRACK_H
#define TRACK_H

#include "centroid.h"
#include "classify.h"

#define MAX_FRAMES 3600 // maximum num of frames to track

typedef struct {
    CentroidFrame centroids; // object centroids only (stars filtered out)
    MatchSet matches;
    Vec2 translations[MAX_CENTROIDS];
    RotationSet rotations;
    int prev_frame_idx;
} TrackedFrame;

typedef struct {
    int tags[MAX_CENTROIDS]; // persistent object id, -1 if unassigned
    int count;
} TagSet;

// Track objects across two consecutive classified frames
// prev     : previous tracked frame
// curr_clf : current classified frame (labels already assigned)
// config   : same classifier config (uses unmatched_cost)
// out      : output tracked jframe
void trackFrame(const TrackedFrame *prev, const ClassifiedFrame *curr_clf, const ClassifierConfig *config, 
                TrackedFrame *out);

// assign persisistent tags to tracked objects across frames
// tracked  : array of tracked frames
// n_frames : number of frames
// tags_out : output tag sets, one per frame
void makeTags(const TrackedFrame *tracked, int n_frames, TagSet *tags_out);

#endif  // TRACK_H