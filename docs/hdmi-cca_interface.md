# PL Interface Specification

## HDMI Video Pipeline → Centroiding (CCL/CCA) Module Handoff

**Version:** 0.2
**Authors:** Adam Welsh

---

## Overview

The video pipeline (HDMI RX Subsystem → threshold) hands a binarized video stream, 2 pixels per beat, to the `centroiding` hierarchy over AXI4-Stream. Inside `centroiding`, `pix_2to1` (`docs/pix_2to1_spec.md`) converts it to 1 pixel per clock for `cca_top`.

The video pipeline owns everything up to and including the threshold output. Centroiding owns everything from `centroiding/s_axis_*` onward. This document is the contract at that boundary only.

---

## Interface Signals

| Signal          | Width | Direction (rel. to Centroiding) | Description |
| --------------- | ----- | ------------------------------- | ----------- |
| `s_axis_tdata`  | 16    | in  | Bit 0 = pixel 0 (left), bit 8 = pixel 1 (right). All other bits don't-care. |
| `s_axis_tvalid` | 1     | in  | Standard AXI4-Stream valid |
| `s_axis_tready` | 1     | out | Standard AXI4-Stream ready (see Backpressure) |
| `s_axis_tuser`  | 1     | in  | Start of frame: first beat of a frame only |
| `s_axis_tlast`  | 1     | in  | End of line: last beat of each line only |

Clock and reset are shared, not part of the stream: see Clocking and Reset.

### Pixel Value Convention

| Value | Meaning    |
| ----- | ---------- |
| 1     | Foreground |
| 0     | Background |

### Framing

- Every beat carries 2 real pixels, so a 1920-pixel line is exactly **960 beats**, pairing pixels (0,1), (2,3) … (1918,1919). No partial beats, no `tkeep`.
- **1080 lines per frame.**
- `tuser` is high on the first beat of a frame (row 0, pixels 0–1) and on no other beat.
- `tlast` is high on beat 959 of every line (pixels 1918–1919) and on no other beat.
- Raster order: left to right within a line, top to bottom across lines.

---

## Clocking

- **One clock:** `pl_clk0` at **75 MHz** drives the RX subsystem's AXI4-Stream output, the threshold, `pix_2to1` and `cca_top`. No clock-domain crossing at this boundary.
- **Video mode: 1920×1080p30** (74.25 MHz pixel clock, 2200 × 1125 total).
- **Rate:** within a line, video arrives at 37.125 M beats/s (74.25 Mpx/s), so on average about **one beat every 2 clocks**. `pix_2to1` accepts up to one beat every 2 clocks (75 Mpx/s), so the boundary never builds a backlog.

---

## Backpressure

`s_axis_tready` **is a normal flow-control signal**, not an error condition. `pix_2to1` holds it low about every other cycle while it sends the second pixel of a beat, and never for more than 1 cycle in a row while video is flowing.

The video pipeline must:

- Follow the AXI4-Stream rule: once `tvalid` is high, hold `tdata`, `tuser` and `tlast` stable until `tready` accepts the beat.
- Never drop or duplicate a beat while `tready` is low. The RX subsystem's internal FIFO absorbs the stall, provided the threshold passes `tready` straight through.

---

## Frame Timing

Blanking must reach the boundary as `tvalid` low: no frame buffering, and no compressing frames back to back. `cca_top` uses the idle cycles between frames to dump results to BRAM and clear its tables.

| Gap | Minimum | Expected at 1080p30 |
| --- | ------- | ------------------- |
| Last beat of a frame → first beat of the next | 3,000 clocks | ≈ 100,000 clocks (45 blank lines) |
| Line to line | none | ≈ 300 clocks |

---

## Reset

- The video pipeline's stream logic uses the active-low `rst_pl/peripheral_aresetn`, the same reset block as `centroiding`.
- During reset, `s_axis_tvalid` must be low.
- **Partial frames are handled on the Centroiding side:** after reset, `pix_2to1` discards beats until the first `tuser`. The video pipeline does not need to gate its output.
- `cca_top` needs `NUM_LABELS` (256 in the current build) idle clocks after reset before the first pixel. This is met in practice because the RX locks long after the PL reset is released.

---

## Key Decisions

| Decision | Rationale |
| -------- | --------- |
| Threshold in the video pipeline | Keeps the Centroiding input at 1 bit per pixel instead of carrying 48-bit RGB. |
| 2 px/beat at the boundary, converted inside Centroiding | The RX subsystem outputs 2 px/clk. The conversion and its start-of-frame gate sit next to the consumer, which owns the 1 px/clk requirement. |
| Each pixel in its own byte (bits 0 and 8) | AXI4-Stream tooling is byte-granular. |
| 1080p30 on one 75 MHz clock | `cca_top`'s Fmax is about 85 MHz. 1080p60 would need about 125 MHz. At 30 fps no rate-matching FIFO or CDC is needed. |

---

## Open Questions

- [x] Threshold method and value (THR-3): MATLAB `rgb2gray` grey > 64 (`scripts/bd/integrate.tcl`). Verified on `SampleDataRun9.mp4`, where objects are grey 244 on 0.
- [x] Pixel order (THR-1): confirmed on the board. Centroids match the source video pixel-exactly (`results/run2.csv`, 2026-11-13), which a swapped pair would break.

---

## Revision History

| Version | Date       | Notes |
| ------- | ---------- | ----- |
| 0.1     | 2026-07-11 | Initial draft |
| 0.2     | 2026-11-13 | Boundary moves to the threshold output: 16-bit, 2 px/beat. 1080p30 on `pl_clk0` at 75 MHz. `tready` low is normal backpressure. Start-of-frame gate in `pix_2to1`. Reset and `NUM_LABELS` updated. |
