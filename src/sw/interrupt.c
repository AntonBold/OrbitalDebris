#include "include/interrupt.h"

#include "xparameters.h"
#include "xstatus.h"
#include "xil_exception.h"
#include "xscugic.h"
#include "xintc.h"

// Two levels of interrupt controller:
//
//   cca_top.o_interrupt --(rising edge)--> axi_intc --(level)--> GIC --> A53
//
// The GIC calls XIntc_InterruptHandler (the axi_intc driver's dispatcher),
// which reads which input fired and calls frame_isr. For inputs configured
// as edge-sensitive in Vivado, that dispatcher acknowledges the input before
// calling the handler, so frame_isr doesn't acknowledge anything itself and
// nothing in the PL needs clearing.
//
// Vitis 2023.2+ platforms use the system-device-tree (SDT) flow, where the
// drivers look devices up by base address instead of device ID; both are
// handled below. The xparameters.h names are the usual generated ones --
// check them against your platform if this doesn't compile.

#ifdef SDT
#define GIC_ID      XPAR_XSCUGIC_0_BASEADDR
#define INTC_ID     XPAR_XINTC_0_BASEADDR
#else
#define GIC_ID      XPAR_SCUGIC_SINGLE_DEVICE_ID
#define INTC_ID     XPAR_INTC_0_DEVICE_ID
#endif

#define GIC_PRIORITY        0xA0    // middle priority (lower value = higher)
#define GIC_TRIGGER_LEVEL   0x1     // axi_intc's irq output is level, active high

volatile uint32_t frame_irq_count = 0;

static XScuGic gic;
static XIntc   intc;

// Runs in interrupt context: count the frame and return. The main loop does
// the BRAM read (docs/pl-ps_interface_spec.md, PS Software Requirements).
static void frame_isr(void *callback_ref)
{
    (void)callback_ref;
    frame_irq_count++;
}

int interrupt_init(void)
{
    int status;

    // GIC
    XScuGic_Config *gic_cfg = XScuGic_LookupConfig(GIC_ID);
    if (gic_cfg == NULL)
        return XST_FAILURE;
    status = XScuGic_CfgInitialize(&gic, gic_cfg, gic_cfg->CpuBaseAddress);
    if (status != XST_SUCCESS)
        return status;

    // axi_intc: route its input to frame_isr, then start it in real mode
    // (hardware interrupts, not the driver's simulation mode)
    status = XIntc_Initialize(&intc, INTC_ID);
    if (status != XST_SUCCESS)
        return status;
    status = XIntc_Connect(&intc, FRAME_INTC_INPUT_ID, (XInterruptHandler)frame_isr, NULL);
    if (status != XST_SUCCESS)
        return status;
    status = XIntc_Start(&intc, XIN_REAL_MODE);
    if (status != XST_SUCCESS)
        return status;
    XIntc_Enable(&intc, FRAME_INTC_INPUT_ID);

    // GIC input from axi_intc -> the axi_intc dispatcher
    XScuGic_SetPriorityTriggerType(&gic, FRAME_GIC_INT_ID, GIC_PRIORITY, GIC_TRIGGER_LEVEL);
    status = XScuGic_Connect(&gic, FRAME_GIC_INT_ID,
                             (Xil_InterruptHandler)XIntc_InterruptHandler, &intc);
    if (status != XST_SUCCESS)
        return status;
    XScuGic_Enable(&gic, FRAME_GIC_INT_ID);

    // CPU: send IRQ exceptions to the GIC driver, then unmask them
    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                                 (Xil_ExceptionHandler)XScuGic_InterruptHandler, &gic);
    Xil_ExceptionEnable();

    return XST_SUCCESS;
}
