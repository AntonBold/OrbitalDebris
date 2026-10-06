#include "include/interrupt.h"

volatile int frame_ready = 0;

void frame_ready_isr(void *callback_ref) 
{
    (void)callback_ref;
    frame_ready = 1;
    // TODO: XIntc_Acknowledge when BSP drivers available
}

int interrupt_init(void)
{
    // TODO: implement when bitstream is available
    // XIntc_Initialize, XIntc_connect, XIntc_Start,
    // XIntc_Enable, Xil_Exception_enable
    return 0;
}

