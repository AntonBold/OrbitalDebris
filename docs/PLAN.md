# Integration Plan: HDMI RX → Centroiding

Demo: 2026-12-11. Req IDs → https://claude.ai/artifact/Qs3cKKW3BTtnfsy52Njzy5. Contract → `docs/hdmi-cca_interface.md`.

## Decisions

- **1080p30.** 60 fps needs ≥124.6 MHz; Fmax is ~85 MHz.
- **One 75 MHz PL clock (`pl_clk0`; `pl_clk2` disabled) for everything except the video PHY DRP clock (`pl_clk1`, 100 MHz, fixed by the IP, used only inside it):** RX video and control, video PHY, threshold, converter, SmartConnect, centroiding. No user clock-domain crossings; the RX bridge handles `rx_video_clk` → 75 MHz.
- **Centroiding = block-design hierarchy built by a Tcl proc:** `pix_2to1`, `cca_top`, BRAM, BRAM controller, `axi_intc`. Ports: 16-bit, 2 px/beat AXI4-Stream in, clock, reset, AXI slave, IRQ out. The `pattern` build skips `pix_2to1` (`with_conv` 0).
- **`pattern_gen` stays out of the hierarchy.** Fallback = `pre-hdmi-75mhz` bitstream.
- `NUM_LABELS` = 256.

## State (2026-11-13)

- **End to end on live HDMI:** `SampleDataRun9.mp4` at 1080p30 → threshold → `pix_2to1` → `cca_top` → PS at 30 frames/s, no frames skipped. Board centroids match the source video pixel-exactly (`results/run2.csv`, 10 frames checked with `scripts/golden/png_frame.py`).
- Routed timing at 75 MHz: WNS +0.65 ns.
- PS built with `-O2`. At ~120 centroids/frame classify + track keeps up.

## State (2026-11-23): classification

- **PS classifier matches the MATLAB/paper baseline** (branch `classifier-fixes`): GESD as MATLAB `isoutlier`, rotation-center median, rotation frames, positions in `double`, `matchpairs`-equivalent assignment, rotation/translation prediction, delay `d`. Host harness: Run 1 TPR 0.901 / TNR 0.995, Run 5 0.9999 / 0.998.
- **On the board, d = 5** (chosen with `scripts/classify_sweep.py` on board-like Run 9: whole pixels, 30 fps): TPR 0.983, TNR 0.991, ~1 false object per frame (`results/run5.csv`, checked with `scripts/classify_check.py`). The board reproduces the host's labels exactly; the limit is the whole-pixel video, not the code. d = 1 gave TPR 0.625 (`results/run4.csv`).
- **Known limitation:** after a scene discontinuity (video loop, HDMI re-lock) the PS drops ~30 frames over ~1.5 s, because for 2d frames the matcher pairs unrelated star fields (its worst case), then recovers. Steady state: 0 dropped frames. Accepted; a faster solver (Jonker–Volgenant) is the fix if needed.

## Open

- [x] D2: threshold = MATLAB `rgb2gray`, foreground = grey > 64 (verified on Run 9; objects are grey 244 on 0)
- [ ] D4: start-of-frame gate (OUT-4) is in `pix_2to1`. Error flag (OUT-6) owner still open
- [x] PS labels (star/object) vs the MATLAB reference on the same frames (board sees every other frame of the 60 fps video): see State 2026-11-23

## Phase 0 — blockers (Nov 9–12)

Exit: all pass, or re-plan.

- [x] (Anthony) INT-4: licence allows `write_bitstream`, valid past Dec 11
- [x] (Anthony) SRC-1/2/3: EDID offers 1080p30 only; hot-plug toggled; driver log shows 2200×1125 progressive RGB
- [x] (Anthony) CLK-1: `pl_clk0` = 75.000 MHz, `pl_clk2` disabled, its 4 loads moved to `pl_clk0` (Actual Frequency); HDMI IP clock settings + BSP updated; RX still locks. If not → tell Adam
- [x] (Adam) Find why the TL isn't LUTRAM: its own read outputs drive its address ("invalid driver of address port")
- [ ] (Adam) Out-of-context `cca_top` at 13.333 ns: WNS, WHS, worst endpoint

## Phase 1 — each side separately (Nov 12–18)

Exit: both halves pass their own checks.

- [x] (Anthony) Threshold (THR-1–4) + Verilator TB (`threshold_tb`)
- [x] (Adam) Converter + start-of-frame gate (CNV-1–4, OUT-4) + Verilator TB (`pix_2to1_tb`), spec `docs/pix_2to1_spec.md`
- [ ] (Anthony) VER-2 ILA at 1080p30: 1920×1080, one `tuser`, gap ~100k cycles
- [x] (Anthony) INT-2 IRQ list (GIC 121 vphy, 122 RX, 123 centroiding); HDMI design as `scripts/bd/hdmi_hier.tcl`
- [x] (Adam) Centroiding hierarchy proc (`scripts/bd/centroid_hier.tcl`)
- [ ] (Adam) Fallback build from the proc at 75 MHz: WNS/WHS ≥ 0, interrupt count = frame count; tag `pre-hdmi-75mhz`
- [x] (Adam) `docs/hdmi-cca_interface.md` v0.2: 1080p30, clock, threshold, reset
- [ ] (Shared) D2, D4

## Phase 2 — merge (Nov 18–24)

Exit: fresh clone builds, timing met, RX locks with the merged app.

- [x] (Shared) INT-1: proc inside HDMI design; RX → threshold → converter → hierarchy
- [x] (Shared) One PS config: HPM0_FPD + HPM0_LPD, one PL clock, pick the telemetry UART
- [ ] (Adam) Keep BRAM `0xA000_0000` and `axi_intc` `0xA001_0000`; check for no overlap with HDMI addresses
- [x] (Adam) IRQ → `irq_concat/In2` = GIC 123; `interrupt.h` updated
- [x] (Adam) Make the write to `0xA002_0000` build-dependent (`HAS_FRAME_TRIGGER` in `main.c`)
- [x] (Adam) VER-4: WNS +0.65 ns at 75 MHz with HDMI, threshold and converter (no TL change needed)
- [x] (Shared) INT-3: one Vitis app, one GIC init

## Phase 3 — on board (Nov 24–Dec 3; no lab Nov 26–29)

Exit: test image matches golden; 10 min without fault.

- [ ] (Shared) VER-3: known test image → board = `cca_golden.py`
- [x] (Adam) Star-field video over HDMI vs golden: pixel-exact (`results/run2.csv`)
- [ ] (Shared) 10-min soak; HDMI replug relocks and starts on `tuser`

## Phase 4 — freeze (Dec 4–10)

- [ ] Dec 4: tag `demo-freeze`; demo-blocking fixes only
- [ ] `docs/demo-runbook.md`, run by the other person
- [ ] Backup video; 3 rehearsals, one on the fallback

## Risks

| Risk | Response |
| --- | --- |
| Licence | Stop; get a full licence |
| No stable 1080p30 | 1080p30-only EDID; another source |
| HDMI IPs fail at 75 MHz | Reopen: separate control clock |
| Timing fails at 75 MHz | TL → LUTRAM; BRAM output register |
| App merge conflicts | Merge early in Phase 2 |
