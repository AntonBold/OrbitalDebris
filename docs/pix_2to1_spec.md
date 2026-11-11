# 2:1 Pixel Converter Specification

**Version:** 0.2 (2026-11-10) · **Owner:** Adam · **Module:** `src/hdl/pix_2to1.sv` (BD shell `src/hdl/pix_2to1_bd.v`)

Turns the threshold block's 2-pixels-per-beat stream into the 1-pixel-per-clock stream that `cca_top` takes (`docs/hdmi-cca_interface.md`). It sits at the input of the `centroiding` hierarchy (`scripts/bd/centroid_hier.tcl`), so the HDMI → centroiding boundary moves to the threshold output (see [Boundary change](#boundary-change)).

## Context

| | Value |
| --- | --- |
| Clock | `pl_clk0`, 75 MHz, same as the threshold and `cca_top` (no CDC) |
| Input rate | 1080p30, 2 px/beat: 37.125 M beats/s within a line, 0 during blanking |
| Output capacity | 1 px/clk = 75 Mpx/s, against 74.25 Mpx/s needed within a line |
| Downstream ready | `cca_top.o_trdy` is high except in reset |
| Upstream | Threshold → HDMI RX SS AXI4-Stream bridge, which has a FIFO and accepts `tready` low |

## Interface

| Signal | Width | Dir | Description |
| --- | --- | --- | --- |
| `aclk` | 1 | in | 75 MHz |
| `aresetn` | 1 | in | Active-low synchronous reset (`rst_pl/peripheral_aresetn`) |
| `s_axis_tdata` | 16 | in | Byte 0 (`[7:0]`): pixel 0 (left) in bit 0. Byte 1 (`[15:8]`): pixel 1 in bit 8. Other bits don't-care |
| `s_axis_tvalid` | 1 | in | |
| `s_axis_tready` | 1 | out | |
| `s_axis_tuser` | 1 | in | Start of frame, on the first beat of a frame |
| `s_axis_tlast` | 1 | in | End of line, on the last beat of a line |
| `m_axis_tdata` | 8 | out | Bit 0 = pixel, bits [7:1] = 0 |
| `m_axis_tvalid` | 1 | out | |
| `m_axis_tready` | 1 | in | |
| `m_axis_tuser` | 1 | out | Start of frame |
| `m_axis_tlast` | 1 | out | End of line |

The master side follows `docs/hdmi-cca_interface.md`: 1 = foreground, raster order.

**BD shell:** Vivado block-design module references need a Verilog or VHDL top file (they reject `.sv`). `pix_2to1_bd.v` is a logic-free Verilog wrapper with the same ports that instantiates `pix_2to1`, following `src/hdl/cca_top_bd.v`. Keep the port names above so Vivado infers the `s_axis`/`m_axis` interfaces, `aclk` and `aresetn`.

## Behavior

1. **Order:** each input beat produces two output pixels: byte 0 first, then byte 1.
2. **`tuser`:** a beat with `tuser = 1` outputs `tuser = 1` on its **first** pixel only.
3. **`tlast`:** a beat with `tlast = 1` outputs `tlast = 1` on its **second** pixel only.
4. **No loss, no duplication:** every accepted beat produces exactly two output pixels, including under `m_axis_tready` backpressure. Standard AXI4-Stream: an output pixel is held stable until accepted.
5. **Throughput:**
   - With `m_axis_tready` held high, the converter must sustain one beat per two clocks.
   - Within a line, while `m_axis_tready` is high, `s_axis_tready` must not stay low for more than 1 consecutive cycle.
   - Being able to accept a new beat while emitting the second pixel of the previous one (2 px/clk peak) is allowed but not required.
6. **Blanking passes through:** output `tvalid` is low whenever there's nothing to send. Don't buffer whole lines or frames: the ≥3,000 idle-cycle gap between frames must survive (`hdmi-cca_interface.md`, Frame Timing).
7. **Latency:** with `m_axis_tready` high, fixed and ≤ 3 clocks from input acceptance to the first output pixel.
8. **Reset:** while `aresetn` is low, `m_axis_tvalid = 0`, `s_axis_tready = 0`, and any held pixel is discarded.
9. **Start-of-frame gate (OUT-4):** after reset, accept and discard every beat (`s_axis_tready` held high, `m_axis_tvalid` low) until a beat with `tuser = 1`. That beat and everything after it are converted as normal. The gate only re-arms on reset, so a relock mid-stream only gets dropped if the reset is asserted for it.
10. **No input checking:** malformed input (`tuser` mid-line, missing or extra `tlast`, short lines) is converted as-is, by the rules above. Error detection is out of scope.

## Requirements

| ID | Requirement |
| --- | --- |
| P2-1 | Pixel order as in Behavior 1 |
| P2-2 | `tuser` only on the first output pixel of a `tuser` beat |
| P2-3 | `tlast` only on the second output pixel of a `tlast` beat |
| P2-4 | No loss or duplication under any `m_axis_tready` pattern |
| P2-5 | Sustains 1 beat / 2 clocks with `m_axis_tready` high; `s_axis_tready` low ≤ 1 consecutive cycle |
| P2-6 | Blanking passes through as `tvalid` low; no line or frame buffering |
| P2-7 | Reset behavior as in Behavior 8 |
| P2-8 | Synthesizes in the 75 MHz domain without reducing the design's WNS below 0 |
| P2-9 | Start-of-frame gate as in Behavior 9: the first pixel out after reset carries `tuser` |

## Verification

Verilator testbench `src/tb/pix_2to1_tb.sv`, with a file list in `scripts/filelists/`, run as `./simulate pix_2to1_tb`. Self-checking: it compares against a reference queue built from the input beats.

| Test | Checks |
| --- | --- |
| Back-to-back beats, `m_axis_tready` = 1 | P2-1, P2-5: output is 2 px per beat, in order; stall pattern on `s_axis_tready` |
| Beats with random gaps | P2-1, P2-6 |
| Random `m_axis_tready` | P2-4 |
| `tuser` on beat 0, `tlast` every 960th beat | P2-2, P2-3 |
| Full 1920×1080 frame + 49,500-cycle blank at 37.125 M beats/s | 1920 px per `tlast`, 1080 `tlast`s, one `tuser`, ≥ 3,000 idle cycles between frames at the output |
| Reset mid-line | P2-7: no stale pixel comes out after reset |
| Start mid-frame | P2-9: beats before the first `tuser` produce no output; the first output pixel carries `tuser` |
| End to end | Through `cca_env_tb` with the golden model, fed 2 px/beat (follow-up) |

On the board: ILA at the converter output (requirement VER-2 on the requirements page).

## Boundary change

The HDMI → centroiding contract moves from the converter output to the threshold output:

| | Before | After |
| --- | --- | --- |
| HDMI side (Anthony) delivers | 8-bit, 1 px/clk | 16-bit, 2 px/beat (format above) |
| `centroiding` hierarchy input | `cca_top` directly | `pix_2to1` → `cca_top` |

`docs/hdmi-cca_interface.md` v0.2 needs this, plus 1080p30 and the 75 MHz clock. `centroid_hier.tcl` exposes a 16-bit `s_axis` instead of 8-bit. The `pattern` variant (`pattern_gen`, 1 px/clk) bypasses the converter or gets its own path, which is still to be decided.

## Open

- [x] Start-of-frame gate (OUT-4) lives here: Behavior 9, P2-9. Decided 2026-11-10.
- [ ] Confirm pixel order with Anthony's ILA: is the RX SS's pixel 0 in the low 24 bits, and does the threshold keep that order?
- [x] Custom RTL, not Xilinx `axis_dwidth_converter`: the IP can't implement the start-of-frame gate (Behavior 9), and it needs `tuser` per byte. Decided 2026-11-10.
