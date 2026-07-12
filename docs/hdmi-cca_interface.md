# PL Interface Specification

## HDMI Video Pipeline → Centroiding (CCL/CCA) Module Handoff

**Version:** 0.1
**Authors:** Adam Welsh

---

## Overview

The video pipeline (HDMI RX Subsystem → thresholding) hands off a binarized, one-bit-per-pixel video stream to the Centroiding module over AXI4-Stream. The video pipeline owns everything upstream of this interface — clock recovery, pixel format, thresholding, and any internal width/clock conversion needed to produce the format below. The Centroiding module owns everything downstream, starting from this interface.

Everything in this document describes the **contract at the boundary only**. Neither side needs to know how the other implements its side, as long as this contract is met.

---

## Interface Signals

| Signal          | Width  | Direction (rel. to Centroiding module) | Description                                  |
| --------------- | ------ | --------------------------------------- | --------------------------------------------- |
| `s_axis_tdata`  | 8 bits | in                                       | Bit 0 = pixel value. Bits [7:1] reserved, don't-care. |
| `s_axis_tvalid` | 1 bit  | in                                       | Standard AXI4-Stream valid                    |
| `s_axis_tready` | 1 bit  | out                                      | Standard AXI4-Stream ready (see Backpressure) |
| `s_axis_tlast`  | 1 bit  | in                                       | End of scan line                              |
| `s_axis_tuser`  | 1 bit  | in                                       | Start of frame (asserted on first pixel only) |
| `s_axis_aclk`   | —      | in                                       | Interface clock (see Clocking)                |
| `s_axis_aresetn`| 1 bit  | in                                       | Active-low reset                              |

**Note on `tdata` width:** the pixel value is logically 1 bit. It is carried in an 8-bit (1-byte) field because standard AXI4-Stream infrastructure IP (width converters, FIFOs) operates on byte granularity — sub-byte `TDATA` widths aren't a configurable option. This is a hardware constraint of the shared toolchain, not a design preference by either side.

### Pixel Value Convention

| Value | Meaning     |
| ----- | ----------- |
| 1     | Foreground  |
| 0     | Background  |

### Framing

- `tuser` pulses high on the very first pixel of a frame.
- `tlast` pulses high on the last pixel of each scan line.
- Standard raster order: left-to-right within a line, top-to-bottom across lines.

---

## Clocking

`s_axis_aclk` must sustain the true, real-time 1920×1080@60fps pixel rate — i.e., the interface must never fall behind during active video, with no sustained backlog forming.

This document intentionally does not pin an exact clock frequency (in MHz) or clock name. The video pipeline side is responsible for choosing/deriving a clock (from the recovered HDMI clock, an internal PLL, or otherwise) that satisfies the rate requirement above. If a specific clock net or frequency is finalized, record it below for reference, but the requirement is the rate guarantee, not the specific number:

> Clock net / frequency: _TBD — video pipeline owner to fill in once finalized_

---

## Backpressure

Standard AXI4-Stream handshake (`tvalid`/`tready`) is retained for IP compatibility, but note: live HDMI video cannot be paused at the source. The video pipeline should not rely on `tready` deasserting as a normal flow-control mechanism — the Centroiding module is designed to always be ready to accept a pixel once video is flowing (see Clocking above). `tready` deassertion should be treated as an abnormal/error condition, not a routine backpressure path.

---

## Key Decisions

| Decision                                              | Rationale                                                                 |
| ------------------------------------------------------ | -------------------------------------------------------------------------- |
| Thresholding happens in the video pipeline, not in Centroiding | Keeps the Centroiding module's input trivial (1 bit/pixel) and avoids carrying full-width color/luma data across the width-conversion and clock-domain-crossing chain. |
| Data carried as 1 byte (not fewer) per pixel          | Forced by AXI4-Stream infrastructure IP, which is byte-granular. Bits [7:1] are unused by Centroiding. |
| Exact clock frequency left unspecified                | The real requirement is a rate guarantee (no backlog), not a specific number — avoids re-deriving this document if pipeline-internal clocking choices change. |

---

## Open Questions

- [ ] Confirm which clock net actually drives `s_axis_aclk` once video pipeline clocking is finalized
- [ ] Confirm reset synchronization requirements between the two clock domains, if `s_axis_aclk` differs from other PL clocks in the design
- [ ] Confirm whether `tuser`/`tlast` timing exactly matches the convention above once the thresholding block is implemented

---

## Revision History

| Version | Date       | Notes         |
| ------- | ---------- | ------------- |
| 0.1     | 2026-07-11 | Initial draft |