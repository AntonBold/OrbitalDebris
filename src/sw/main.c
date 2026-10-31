#include <stdio.h>
#include "centroid.h"
#include "bram_io.h"
#include "classify.h"
#include "track.h"
#include "interrupt.h"
#include "bram_debug.h"
#include "telemetry.h"
#include "xil_printf.h"
#include "xil_io.h"

// Each classified frame goes out as a binary telemetry packet on UART0 at
// 921600 baud (docs/uart-telemetry.md; decode with scripts/telemetry_decode.py).
// Frames are read on the interrupt; if interrupt_init() fails the loop falls
// back to polling the BRAM.
//
// BRINGUP_PRINT 1 also prints every frame as text (decoded, raw words,
// reader stats, interrupt count). The decoder shows those lines too, but
// they're ~700 bytes a frame, so leave it off unless debugging.
#define BRINGUP_PRINT 0

// Frame trigger: axi_gpio_0 bit 0, ORed with the button into pattern_gen's
// i_enable (docs/pl-ps_interface_spec.md, "Frame Trigger"). FREE_RUN 1 holds
// it high once the interrupt is set up, so pattern_gen streams continuously
// (~46 frames/s at 100 MHz: 1920x1080 pixels + 99,000 blanking cycles) with
// no button press. FREE_RUN 0 leaves it low: one frame per button press.
#define FRAME_TRIGGER_ADDR      0xA0020000u     // axi_gpio_0 GPIO_DATA
#define FREE_RUN 1

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
    // First, before anything is printed: every byte after this is at 921600
    int tel_ok = (telemetry_uart_init() == 0);

    // Stop the generator (after its current frame) before clearing the
    // headers, in case a previous run left the trigger high
    Xil_Out32(FRAME_TRIGGER_ADDR, 0);

    bram_init();
    bram_clear_headers();   // before the interrupt is enabled (see pl-ps spec, Reset)

    // Printed before interrupt_init(): if that hangs (e.g. the axi_intc isn't
    // reachable on the bus), this is the last line you see
    xil_printf("\r\ndebris_app: starting, initializing interrupts...\r\n");

    // If interrupt setup fails, fall back to polling the BRAM headers
    int irq_ok = (interrupt_init() == 0);
    int use_irq = irq_ok;
    uint32_t irq_handled = 0;

    xil_printf("debris_app: BRAM at 0x%08x, interrupt init %s, %s\r\n", BRAM_BASE_ADDR,
               irq_ok ? "ok" : "FAILED", use_irq ? "waiting on interrupts" : "polling the BRAM");
    xil_printf("debris_app: telemetry %s\r\n", tel_ok ? "at 921600 baud" : "UART init FAILED, still at boot baud");
    bram_print_headers();

#if FREE_RUN
    Xil_Out32(FRAME_TRIGGER_ADDR, 1);
    xil_printf("debris_app: free-running (frame trigger at 0x%08x held high)\r\n", FRAME_TRIGGER_ADDR);
#else
    xil_printf("debris_app: press BTN2 for a frame\r\n");
#endif

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

        // one packet per frame: centroids and their labels
        telemetry_send_frame(&clf_current.frame, &clf_current.labels, bram_get_stats()->frames_skipped);

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