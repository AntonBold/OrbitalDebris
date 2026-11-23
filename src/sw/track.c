#include "include/track.h"
#include "include/centroid.h"
#include "include/cost_matrix.h"   
#include "include/hungarian.h"
#include "include/geometry.h"
#include <string.h>

void trackFrame(const TrackedFrame *prev2, const TrackedFrame *prev, const ClassifiedFrame *curr_clf,
                const ClassifierConfig *config, TrackedFrame *out)
{
    // Extract object centroids from current classifid frame
    out->centroids.count = 0;
    out->matches.count = 0;
    out->rotations.count = 0;

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

    // predict where prev's objects are now (rotation, else translation), then cost matrix
    Centroid C1_predicted[MAX_CENTROIDS];
    predictPositions(C1->centroids, n1, &prev->matches, prev->translations,
                     &prev->rotations, C1_predicted);
    float D[MAX_CENTROIDS][MAX_CENTROIDS];
    getCostMatrix(C1_predicted, n1, C2->centroids, n2, D);

    // Run hungarian algorithm
    Match matches[MAX_CENTROIDS];
    int nm = hungarian(D, n1, n2, config->unmatched_cost, matches);

    for (int i = 0; i < nm; i++)
        out->matches.matches[i] = matches[i];
    out->matches.count = nm;

    // compute translations
    getTranslations(C1->centroids, C2->centroids, matches, nm, out->translations);

    // rotations from prev2 -> prev -> current (paper Algorithm 10, line 9)
    if (prev2 != NULL && prev->matches.count > 0 && nm > 0)
        getRotations(prev2->centroids.centroids, prev->centroids.centroids, C2->centroids,
                     prev->matches.matches, prev->matches.count, matches, nm, &out->rotations);
}

void tagFrame(const TrackedFrame *prev, TrackedFrame *cur, int *next_tag)
{
    for (int j = 0; j < cur->centroids.count; j++)
        cur->tags[j] = -1;
    if (prev == NULL)
        return;

    for (int k = 0; k < cur->matches.count; k++) {
        int from = cur->matches.matches[k].from;
        int to = cur->matches.matches[k].to;
        cur->tags[to] = prev->tags[from] >= 0 ? prev->tags[from] : (*next_tag)++;
    }
}

void trackTagsBySpot(const LabelSet *labels, const TrackedFrame *trk, int32_t *tags_out)
{
    // trackFrame takes the objects in label order, so object k is the k-th
    // spot labelled LABEL_OBJECT
    int obj = 0;
    for (int i = 0; i < labels->count; i++)
        tags_out[i] = labels->labels[i] == LABEL_OBJECT ? trk->tags[obj++] : -1;
}

void trackStep(TrackerState *s, const ClassifiedFrame *curr_clf, const ClassifierConfig *config)
{
    trackFrame(s->have_prev2 ? &s->prev2 : NULL, s->have_prev ? &s->prev : NULL,
               curr_clf, config, &s->current);
    tagFrame(s->have_prev ? &s->prev : NULL, &s->current, &s->next_tag);

    // MATLAB Tracker.track: if prev had objects and this frame has none, keep prev
    if (s->current.centroids.count > 0 || !s->have_prev || s->prev.centroids.count == 0) {
        s->prev2 = s->prev;
        s->have_prev2 = s->have_prev;
        s->prev = s->current;
        s->have_prev = 1;
    }
}
