#ifndef INTERRUPT_H
#define INTERRUPT_H

#include <stdint.h>

// Hardware includes -- uncomment when bitstream is available
// and platform bsp has been rebuilt with hardware drivers
// #include <xintc.h>
// #include <xscugic.h>

#ifndef XPAR_INTC_0_DEVICE_ID
#define XPAR_INTC_0_DEVICE_ID   0
#endif

#ifndef XPAR_INTC_0_BASEADDR
#define XPAR_INTC_0_BASEADDR    0x00000000
#endif

#ifndef XPAR_FABRIC_FRAME_READ_INTR
#define XPAR_FABRIC_FRAME_READ_INTR 0
#endif 

// flag set by isr, read by main loop
extern volatile int frame_ready;

// initialize interrupt controller -- stub until bitstream available
int interrupt_init(void);

// ISR called by hardware when PL signals frame ready
void frame_ready_isr(void *callback_ref);


#endif // INTERRUPT_H