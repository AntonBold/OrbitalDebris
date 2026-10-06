#include <stdio.h>
#include "centroid.h"
#include "bram_io.h"
#include "classify.h"
#include "track.h"

// Config --

static const ClassifierConfig config = {
    .unmatched_cost             = UNMATCHED_COST,
    .max_num_objects            = MAX_OBJECTS,
    .delta                      = DELTA,
    .use_translation_magnitude  = 1,
    .use_translation_angle      = 1,
    .use_rotation_center        = 1,
    .use_rotation_angle         = 0,    
};

// State --

// Ring buffer of classified frames (memory for classifier)
static ClassifiedFrame clf_memory[DELTA];
static int clf_memory_count = 0;

// current classified and tracked frames
static ClassifiedFrame clf_current;
static TrackedFrame trk_prev;
static TrackedFrame trk_current;
static int trk_initialized = 0;

// Main --

int main(void)
{
    bram_init();

    while(1) {
        // read newest frame from bram
        CentroidFrame new_frame;
        int frame_num = bram_read_frame(&new_frame);

        // no new frame available -- keep waiting
        if (frame_num < 0)
            continue;
        
        // classify the new frame
        classifyFrame(clf_memory, clf_memory_count, &new_frame, &config, &clf_current);

        // track objects
        trackFrame(trk_initialized ? &trk_prev : NULL, &clf_current, &config, &trk_current);

        trk_prev = trk_current;
        trk_initialized = 1;

        // update classifier memory ring bufffer
        if (clf_memory_count < DELTA) {
            clf_memory[clf_memory_count++] = clf_current;
        } else {
            // shift memory left, add new frame at end
            for (int i = 0; i < DELTA - 1; i++)
                clf_memory[i] = clf_memory[i + 1];
            clf_memory[DELTA - 1] = clf_current;
        }

        // TODO: write results back to PL for HDMI overlay
        // TODO: add interrupt handler instead of polling
    }

    return 0;
}