# Integration Plan: HDMI RX → Centroiding

Written 2026-11-09 (Mon). Demo 2026-12-11 (Fri), about 4.5 weeks out. HDMI input is required for the demo.

Requirement IDs (SRC-, CLK-, THR-, CNV-, OUT-, INT-, VER-) refer to the HDMI RX Integration Requirements page: https://claude.ai/artifact/Qs3cKKW3BTtnfsy52Njzy5. The page is private until it's shared. The boundary contract is `docs/hdmi-cca_interface.md`.

## Locked decisions

| Decision | Value | Why |
| --- | --- | --- |
| Frame rate | **1080p30** | At 1080p60 the CCL would need at least ~124.6 MHz. Measured Fmax is ~85 MHz. |
| Pipeline clock | **75 MHz on `pl_clk2`**, shared by the RX AXI4-Stream output, threshold, 2→1 converter and `cca_top` | Above 74.25 Mpx/s within a line, so no backlog builds and no rate-matching FIFO is needed. About +1.5 ns of slack against the current worst path. |
| Clock crossing on the video path | **None in user logic** | The RX subsystem's internal bridge already crosses from `rx_video_clk` (37.125 MHz) to `pl_clk2`. |
| Pixel format at `cca_top` | 1 bit/pixel in `tdata[0]`, ≤1 px/clock, `tready` always high | Unchanged contract |
| `NUM_LABELS` | 256 | 1024 doesn't route |

## Where things stand (2026-11-09)

**HDMI side (`origin/hdmi` @ `c418aa2`):**
- RX locks on the board with RGB input. The source pixel clock reads 74.25 MHz.
- That pixel clock could also be 720p60 or 1080i60. **1080p30 isn't confirmed** until the driver prints 2200×1125 totals, progressive.
- RX output: 2 px/clock, 48-bit, on `pl_clk2` = **150 MHz**, still to be changed to 75 MHz.
- On GitHub: only `.bd` and `.xdc`. No threshold or converter yet. Not part of the scripted build. Commits are under Adam's git identity.

**CCA side (`pl_ps`):**
- `pattern_gen` → `cca_top` → BRAM → `axi_intc` → GIC works on the board.
- Everything runs on `pl_clk0` at 100 MHz (`scripts/bd/pl_ps.tcl:119–128`), and that build **fails timing**.

| Routed path at 100 MHz | Slack | Implied Fmax |
| --- | --- | --- |
| Line buffer → TL → TL → Features Table add (`fe/sum_x_ram`) | −1.821 ns | ~84.6 MHz |
| Line buffer → TL → TL → max → TL write (`tl/mem_reg[*]/CE`), **on the label loop** | −1.661 ns | ~85.8 MHz |
| Line buffer → TL → min → `reg_label` | +3.343 ns | — |

- The Translator LUT is built from **flip-flops, not LUTRAM**: the write path ends on `mem_reg/CE`, and each read is a 2-level LUT6/F7/F8 mux tree. The reason isn't known yet.
- Pipelining the Features Table stage alone gains ~1%, because the TL write path is right behind it. It's not planned.

## Open decisions (owner: Adam unless noted)

- [ ] **D1. AXI-side clock.** `cca_top` moves to 75 MHz. The BRAM controller and `axi_intc` can either stay on `pl_clk0` (100 MHz) or move to `pl_clk2`. The RX subsystem's AXI-Lite port and the video PHY's DRP clock run on `pl_clk0` in Anthony's design and stay there.
  - **Design question:** if `cca_top` and `axi_intc` are on different clocks, what happens to the one-cycle `o_interrupt` pulse? And what does the BRAM's port B clock have to be?
- [ ] **D2. Threshold** method and value (THR-3), with Anthony. The options are one RGB channel or luma.
- [ ] **D3. Fallback stimulus.** Either keep `pattern_gen` selectable in the integrated design, or rely on the tagged pre-HDMI bitstream as the fallback.
  - **Design question:** what would a mux in front of `cca_top` cost in timing, and how long would a fallback take to swap in on demo day?
- [ ] **D4. Who owns** the start-of-frame gate (OUT-4) and the error flag (OUT-6). The requirements currently put both on the HDMI side.

## Phase 0: Blockers. Nov 9–12

**Exit:** each Tier 1 item below has a written yes/no answer. If any is a no, stop and re-plan before Phase 1.

- [ ] (Anthony) **INT-4:** `write_bitstream` finishes with `v_hdmi_rx_ss`. The licence type is stated and valid past Dec 11.
- [ ] (Anthony) **SRC-1/2:** the EDID offers only 1080p30 for 1080 (VIC 34 present, VIC 16 removed, checksum fixed), and hot-plug toggles after the EDID loads.
- [ ] (Anthony) **SRC-3:** a saved driver log shows 1920×1080 active, 2200×1125 total, progressive, ~74.25 MHz, RGB, and the colour range.
- [ ] (Anthony) **CLK-1:** `pl_clk2` set to 75 MHz. Actual Frequency reads back as 75.000 (or the nearest value above it), and the RX still locks.
- [ ] (Adam) Find why the TL didn't become LUTRAM. Search `synth_1/runme.log` for `mem_reg` and messages saying the RAM was dissolved or implemented in registers. Write down the reason. No RTL change yet.
- [ ] (Adam) Out-of-context run of `cca_top` at 13.333 ns, `NUM_LABELS=256`, with input and output delays. Record WNS, WHS and the worst endpoint. This is the best-case margin at 75 MHz.
- [ ] (Adam) Close D1.

## Phase 1: Each side working on its own. Nov 12–18

**Exit:** both halves pass their own checks against the same contract, before any block design merge.

- [ ] (Anthony) Threshold, 2→1 converter and start gate (THR-1–4, CNV-1–4, OUT-4).
- [ ] (Anthony) **VER-1:** a self-checking Verilator testbench under `src/tb/` with a file list in `scripts/filelists/`, run with `./simulate`. It checks pixel order, `tuser`/`tlast` placement, no drops under random `tready`, and a mid-frame reset.
- [ ] (Anthony) **VER-2:** an ILA capture at the converter output on the board, at 1080p30. It shows 1920 px per line, 1080 lines, one `tuser`, and the measured idle gap between frames (expect ~100k cycles at 75 MHz).
- [ ] (Anthony) **INT-2:** list the RX subsystem and video PHY interrupt lines and their GIC IDs. List the driver files the PS app needs.
- [ ] (Adam) Move `cca_top` to a 75 MHz clock in the current `pattern_gen` build, using the clock arrangement chosen in D1. Routed WNS ≥ 0 and WHS ≥ 0.
  - Running on the board, the interrupt count still equals the frame count. This proves the new clocking before HDMI is added.
- [ ] (Adam) Tag that build as `pre-hdmi-75mhz`. It's the known-good fallback.
- [ ] (Adam) Update `docs/hdmi-cca_interface.md` to v0.2:
  - 1080p30 instead of 1080p60
  - clock net `pl_clk2`, 75 MHz
  - the threshold convention from D2
  - reset-domain notes
  - close its open questions
- [ ] (Shared) Close D2–D4.

## Phase 2: Merge into one design. Nov 18–24

**Exit:** a fresh clone builds the integrated bitstream from scripts. It meets timing on every clock, and the RX locks with the merged PS app.

- [ ] (Anthony + Adam) **INT-1:**
  - Fold the HDMI hierarchy into the scripted block design.
  - Merge the PS settings from `hdmi_rx.bd` into `scripts/bd/pl_ps_zynq.tcl`: `pl_clk2`, GPIO EMIO, UART, HP0 and IRQs. There's one `zynq_ultra_ps_e`.
  - Signal path: RX output → threshold → converter → `cca_top`, all on `pl_clk2`.
  - Commit with the correct git identities. Stage specific files only.
- [ ] (Adam) **VER-4:** routed timing of the integrated design.
  - **If WNS < 0 at 75 MHz:** fix it on the CCA side by getting the TL into LUTRAM. Don't lower the clock.
  - The TL change must give the same results: `regress.sh full` passes before and after, and the patch is validated in scratch and approved before it's applied.
- [ ] (Anthony + Adam) **INT-3:**
  - One Vitis app with the RX and video PHY drivers plus the debris app.
  - One GIC init, with the HDMI interrupts and `axi_intc` both registered.
  - The app boots, the RX locks, and the frame ISR runs.

## Phase 3: End to end on the board. Nov 24–Dec 3 (Thanksgiving Nov 26: assume no lab access Nov 26–29)

**Exit:** a known test image from the laptop produces centroids that match the golden model on the board, and the system runs 10 minutes without a fault.

- [ ] (Shared) **SRC-4 / VER-3:**
  - Test images are black, with single white pixels and small blobs at known coordinates.
  - Play them full-screen at native 1080p.
  - Board centroid sums and areas match `scripts/golden/cca_golden.py` for the same image after thresholding.
- [ ] (Adam) Feed the advisor's star-field video over HDMI. Compare against the golden model, using a threshold applied to the same frames.
- [ ] (Shared) **Soak test:** 10 minutes. Interrupt count equals frame count, no CRC errors on telemetry, and OUT-6 (if built) never set.
- [ ] (Shared) **Replug test:** unplug and replug HDMI. The RX relocks and the first frame forwarded starts on a `tuser`.

## Phase 4: Freeze and rehearse. Dec 4–10

- [ ] Dec 4: tag `demo-freeze`. After that, RTL changes only for a bug that blocks the demo, each with the full regression.
- [ ] Write `docs/demo-runbook.md`: cold boot → laptop settings → app → telemetry display. The other person must run the demo from it once without help.
- [ ] Record a backup video of the end-to-end run.
- [ ] Three clean rehearsals, including one with the fallback (the `pre-hdmi-75mhz` bitstream, or the D3 choice).

## Risks

| Risk | Sign | Response |
| --- | --- | --- |
| Licence blocks the bitstream | INT-4 fails | Stop. Find a full licence or the university's licence server before anything else. |
| Laptop won't hold 1080p30, or uses non-standard timing | SRC-3 log | EDID offers only 1080p30. Redo the blanking math from the logged totals. Try another source device. |
| Integrated timing fails at 75 MHz | VER-4 WNS < 0 | TL → LUTRAM. Possibly also the line buffer BRAM output register (it adds a cycle of read latency, so check alignment). |
| RX bridge FIFO overflows | OUT-6 or missing pixels in VER-2 | Check the output clock really is 75 MHz and the converter isn't stalling longer than expected. |
| PS app merge conflicts (GIC init, interrupt IDs) | INT-3 | Merge early in Phase 2, not at the end. |
| Lost lab time over Thanksgiving | — | Finish Phase 2 by Nov 24. |

## Questions to be able to answer for the advisor

- Why 1080p30? Show the backlog math for 60 fps at 75, 100 and 125 MHz.
- Why is there no clock-crossing FIFO on the video path? Where does the crossing actually happen?
- What sets Fmax? Name the two paths, and explain why pipelining the Features Table alone doesn't help.
- Why did the TL end up in flip-flops, and what did that cost?
- How much margin is there at 75 MHz on the rate side and on the timing side, and which one is tighter?
