#ifndef HDMI_RX_H
#define HDMI_RX_H

// HDMI RX bring-up for the integrated design (scripts/bd/integrate.tcl,
// variant hdmi): board I2C mux + Si5342, video PHY, HDMI RX subsystem, and
// the 1080p30-only EDID. Cut down from Digilent's Genesys ZU HDMI demo
// (xhdmi_example.c): RX only, no TX/TPG/audio/HDCP/menu.
//
// Compiles to stubs on a platform without the HDMI RX subsystem (the
// pattern_gen build), so the same app builds for both variants.

#include <stdint.h>
#include "xscugic.h"

// Set from the RX callbacks (interrupt context); read from the main loop
extern volatile uint32_t hdmi_rx_connected;     // cable / 5 V present
extern volatile uint32_t hdmi_rx_stream_up;     // locked, video flowing
extern volatile uint32_t hdmi_rx_stream_ups;    // number of stream-up events
extern volatile uint32_t hdmi_rx_bridge_overflows;
extern volatile uint32_t hdmi_rx_vphy_errors;

// Call after interrupt_init(): connects the video PHY and RX subsystem
// interrupts to the already-running GIC. Returns 0 on success, or 0 with
// nothing done on a platform without HDMI RX.
int hdmi_rx_init(XScuGic *gic);

// 1 if this platform has the HDMI RX subsystem
int hdmi_rx_present(void);

#endif // HDMI_RX_H
