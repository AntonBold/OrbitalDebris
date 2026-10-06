#ifndef CENTROID_H
#define CENTROID_H

#include <stdint.h>

// -- Constants --

#define MAX_CENTROIDS   256
#define MAX_OBJECTS     10
#define UNMATCHED_COST  100
#define DELTA           10
#define EPS             1e-2f
#define INF             1e5f

// -- Core Types --

typedef struct {
    float x;
    float y;
} Centroid;

typedef struct {
    int from;   // index in previous frame
    int to;     // index in current frame 
} Match;

typedef struct {
    float x;
    float y;
} Vec2;

typedef struct {
    Vec2 center;
    float angle;
    int i1;     // index in frame t-2
    int i2;     // index in frame t-1
    int i3;     // index in frame t
} Rotation;

typedef struct {
    Centroid centroids[MAX_CENTROIDS];
    int count;
} CentroidFrame;

typedef struct {
    Match matches[MAX_CENTROIDS];
    int count;
} MatchSet;

typedef struct {
    Rotation rotations[MAX_CENTROIDS];
    int count;
} RotationSet;

// Label values

#define LABEL_STAR      0
#define LABEL_OBJECT    1
#define LABEL_UNKNOWN   -1

typedef struct {
    int8_t labels[MAX_CENTROIDS]; // LABEL_STAR, LABEL_OBJECT, or LABEL_UNKNOWN
    int count;
} LabelSet;

#endif // CENTROID_H