#ifndef TRACK_H
#define TRACK_H

#include "centroid.h"
#include "classify.h"

#define MAX_FRAMES 3600 // maximum num of frames to track

typedef struct {
    CentroidFrame centroids; // object centroids only (stars filtered out)
    MatchSet matches;        // prev object index -> this frame's object index
    Vec2 translations[MAX_CENTROIDS];
    RotationSet rotations;
    int tags[MAX_CENTROIDS]; // track id per object, -1 = untagged
} TrackedFrame;

// Tracker state carried from frame to frame (zero-initialise before the first frame)
typedef struct {
    TrackedFrame prev2;      // frame prev was matched against
    TrackedFrame prev;       // previous frame with objects
    TrackedFrame current;    // result of the last trackStep
    int have_prev2;
    int have_prev;
    int next_tag;
} TrackerState;

// Match this frame's objects to prev's (paper Algorithm 10, one iteration)
// prev2    : frame prev was matched against (for rotations), or NULL
// prev     : previous tracked frame, or NULL
// curr_clf : current classified frame (labels already assigned)
// config   : classifier config (uses unmatched_cost)
// out      : output tracked frame (tags not set; see tagFrame)
void trackFrame(const TrackedFrame *prev2, const TrackedFrame *prev, const ClassifiedFrame *curr_clf,
                const ClassifierConfig *config, TrackedFrame *out);

// Tag this frame's objects from prev's tags (MATLAB Tracker.makeTags): a
// matched object keeps its predecessor's tag, or starts a new tag if the
// predecessor had none; unmatched objects stay untagged (-1) until matched.
void tagFrame(const TrackedFrame *prev, TrackedFrame *cur, int *next_tag);

// One frame of tracking: trackFrame + tagFrame, then update prev/prev2 as
// MATLAB Tracker.track does (if prev has objects and this frame has none,
// keep prev). The result is in state->current.
void trackStep(TrackerState *state, const ClassifiedFrame *curr_clf, const ClassifierConfig *config);

#endif  // TRACK_H
