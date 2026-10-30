#include <stdio.h>
#include "centroid.h"
#include "bram_io.h"
#include "classify.h"
#include "track.h"
#include "interrupt.h"
#include "bram_debug.h"
#include "xil_printf.h"

// PL bring-up: poll the BRAM (so the data path can be checked even if the
// interrupt path isn't working yet) and print every frame over UART, with
// the interrupt count alongside so the interrupt path is checked separately.
// Set to 0 once both work, to wait on the interrupt instead.
#define BRINGUP_PRINT 1

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
    bram_clear_headers();   // before the interrupt is enabled (see pl-ps spec, Reset)

    // Printed before interrupt_init(): if that hangs (e.g. the axi_intc isn't
    // reachable on the bus), this is the last line you see
    xil_printf("\r\ndebris_app: starting, initializing interrupts...\r\n");

    // If interrupt setup fails, fall back to polling the BRAM headers
    int irq_ok = (interrupt_init() == 0);
    int use_irq = irq_ok && !BRINGUP_PRINT;
    uint32_t irq_handled = 0;

    xil_printf("debris_app: BRAM at 0x%08x, interrupt init %s, %s\r\n", BRAM_BASE_ADDR,
               irq_ok ? "ok" : "FAILED", use_irq ? "waiting on interrupts" : "polling the BRAM");
    bram_print_headers();

    while(1) {
        if (use_irq) {
            // wait for the next frame interrupt; the ISR only counts them
            uint32_t irq_now = frame_irq_count;
            if (irq_now == irq_handled)
                continue;
            irq_handled = irq_now;
        }

        // read newest frame from bram
        CentroidFrame new_frame;
        int frame_num = bram_read_frame(&new_frame);

        // no new frame available -- keep waiting. (A torn read means the PL
        // lapped us mid-copy; the newer frame's interrupt is already counted,
        // so the next pass picks it up.)
        if (frame_num < 0)
            continue;

#if BRINGUP_PRINT
        bram_print_frame(&new_frame, frame_irq_count);
        bram_print_raw_frame((uint32_t)frame_num);
        bram_print_stats();
#endif

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
    }

    return 0;
}