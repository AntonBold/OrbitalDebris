#include "include/track.h"
#include "include/centroid.h"
#include "include/cost_matrix.h"   
#include "include/hungarian.h"
#include "include/geometry.h"
#include <string.h>

void trackFrame(const TrackedFrame *prev, const ClassifiedFrame *curr_clf, const ClassifierConfig *config,
                TrackedFrame *out)
{
    // Extract object centroids from current classifid frame
    out->centroids.count = 0;
    out->matches.count = 0;
    out->rotations.count = 0;
    out->prev_frame_idx = -1;

    for (int i = 0; i < curr_clf->labels.count; i++) {
        if (curr_clf->labels.labels[i] == LABEL_OBJECT) {
            out->centroids.centroids[out->centroids.count] = curr_clf->frame.centroids[i];
            out->centroids.count++;
        }
    }

    // need objects in both frames to track
    if (prev == NULL || prev->centroids.count == 0 || out->centroids.count == 0)
        return;

    const CentroidFrame *C1 = &prev->centroids;
    const CentroidFrame *C2 = &out->centroids;
    int n1 = C1->count;
    int n2 = C2->count;

    // build cost matrix with translation prediction if available
    float D[MAX_CENTROIDS][MAX_CENTROIDS];

    if (prev->matches.count > 0 && prev->rotations.count > 0) {
        // apply rotation and translation prediction
        CentroidFrame C1_predicted = *C1;
        Vec2 T[MAX_CENTROIDS] = {0};

        for (int k = 0; k < prev->matches.count; k++) {
            int idx = prev->matches.matches[k].to;
            if (idx < n1) T[idx] = prev->translations[k];
        }
        
        for (int i = 0; i < n1; i++) {
            // check if this point has a rotation
            int has_rotation = 0;
            for (int k = 0; k < prev->rotations.count; k++) {
                if (prev->rotations.rotations[k].i3 == i) {
                    const Rotation *R = &prev->rotations.rotations[k];
                    if (R->angle != 0.0f && R->center.x < INF && R->center.y < INF) {
                        Vec2 p = { C1->centroids[i].x, C1->centroids[i].y };
                        Vec2 rp = rotate2D(p, R->angle, R->center);
                        C1_predicted.centroids[i].x = rp.x;
                        C1_predicted.centroids[i].y = rp.y;
                    } else {
                        C1_predicted.centroids[i].x += T[i].x;
                        C1_predicted.centroids[i].y += T[i].y;
                    }
                    has_rotation = 1;
                    break;
                }
            }
            if (!has_rotation) {
                C1_predicted.centroids[i].x += T[i].x;
                C1_predicted.centroids[i].y += T[i].y;
            }
        }
        
        getCostMatrix(C1_predicted.centroids, n1, C2->centroids, n2, D);
    } else if (prev->matches.count > 0) {
        // translation only prediction
        CentroidFrame C1_predicted = *C1;
        Vec2 T[MAX_CENTROIDS] = {0};
        for (int k = 0; k < prev->matches.count; k++) {
            int idx = prev->matches.matches[k].to;
            if (idx < n1) T[idx] = prev->translations[k];
        }
        for (int i = 0; i < n1; i++) {
            C1_predicted.centroids[i].x += T[i].x;
            C1_predicted.centroids[i].y += T[i].y;
        }
        getCostMatrix(C1_predicted.centroids, n1, C2->centroids, n2, D);
    } else {
        getCostMatrix(C1->centroids, n1, C2->centroids, n2, D);
    }

    // Run hungarian algorithm
    Match matches[MAX_CENTROIDS];
    int nm = hungarian(D, n1, n2, config->unmatched_cost, matches);

    for (int i = 0; i < nm; i++)
        out->matches.matches[i] = matches[i];
    out->matches.count = nm;

    // compute translations
    getTranslations(C1->centroids, C2->centroids, matches, nm, out->translations);

    out->prev_frame_idx = -1;
}

void makeTags(const TrackedFrame *tracked, int n_frames, TagSet *tags_out) 
{
    int next_tag = 0;

    // initialize all tags to -1
    for (int t = 0; t < n_frames; t++) {
        tags_out[t].count = tracked[t].centroids.count;
        for (int i = 0; i < MAX_CENTROIDS; i++) 
            tags_out[t].tags[i] = -1;
    }
    
    // first frame, assign fresh tags to all objects
    for (int i = 0; i < tracked[0].centroids.count; i++)
        tags_out[0].tags[i] = next_tag++;

    // propagate tags through matches
    for (int t = 1; t < n_frames; t++) {
        const MatchSet *M = &tracked[t].matches;
        
        for (int k = 0; k < M->count; k++) {
            int from = M->matches[k].from;
            int to = M->matches[k].to;
            
            if (tags_out[t-1].tags[from] == -1) {
                tags_out[t-1].tags[from] = next_tag++;
            }
            tags_out[t].tags[to] = tags_out[t-1].tags[from];
        }
    }
}
                