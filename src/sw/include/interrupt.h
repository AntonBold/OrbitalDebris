#ifndef INTERRUPT_H
#define INTERRUPT_H

// Frame-ready interrupt: cca_top.o_interrupt (1-cycle pulse) -> axi_intc
// (rising-edge input) -> GIC (pl_ps_irq0) -> Cortex-A53.
// See docs/pl-ps_interface_spec.md, "Interrupt Protocol".

#include <stdint.h>

// IDs below must match the block design. Check them against the generated
// xparameters.h after rebuilding the platform; override here if they differ.

// GIC interrupt ID of pl_ps_irq0[0] on Zynq UltraScale+ (SPI 89 -> ID 121)
#ifndef FRAME_GIC_INT_ID
#define FRAME_GIC_INT_ID        121U
#endif

// axi_intc input that cca_top.o_interrupt is wired to (bit 0 of intr[])
#ifndef FRAME_INTC_INPUT_ID
#define FRAME_INTC_INPUT_ID     0U
#endif

// Number of frame interrupts since interrupt_init(). Written only by the ISR,
// so the main loop can compare it with the last value it handled without
// disabling interrupts (a 0/1 flag could lose an interrupt that lands
// between reading and clearing it).
extern volatile uint32_t frame_irq_count;

// Set up the GIC and axi_intc and enable the frame interrupt.
// Returns 0 on success, nonzero if a driver call failed.
int interrupt_init(void);

#endif // INTERRUPT_H
