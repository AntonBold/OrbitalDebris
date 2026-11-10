# Integration Plan: HDMI RX → Centroiding

Demo: 2026-12-11. Req IDs → https://claude.ai/artifact/Qs3cKKW3BTtnfsy52Njzy5. Contract → `docs/hdmi-cca_interface.md`.

## Decisions

- **1080p30.** 60 fps needs ≥124.6 MHz; Fmax is ~85 MHz.
- **One 75 MHz PL clock (`pl_clk0`; `pl_clk2` disabled) for everything, no 100 MHz:** RX video and control, video PHY, threshold, converter, SmartConnect, centroiding. No user clock-domain crossings; the RX bridge handles `rx_video_clk` → 75 MHz.
- **Centroiding = block-design hierarchy built by a Tcl proc:** `cca_top`, BRAM, BRAM controller, `axi_intc`. Ports: 1-bit AXI4-Stream in, clock, reset, AXI slave, IRQ out.
- **`pattern_gen` stays out of the hierarchy.** Fallback = `pre-hdmi-75mhz` bitstream.
- `NUM_LABELS` = 256.

## State (2026-11-09)

- RX locks, RGB, 74.25 MHz pixel clock (1080p30 unconfirmed), 2 px/clk at 150 MHz. `origin/hdmi` has only `.bd` and `.xdc`.
- CCA at 100 MHz fails: −1.821 ns (TL→TL→Features Table add), −1.661 ns (TL write, on the label loop). TL is built from flip-flops, not LUTRAM.

## Open

- [ ] D2: threshold method and value (Adam + Anthony)
- [ ] D4: owner of the start-of-frame gate (OUT-4) and error flag (OUT-6)

## Phase 0 — blockers (Nov 9–12)

Exit: all pass, or re-plan.

- [ ] (Anthony) INT-4: licence allows `write_bitstream`, valid past Dec 11
- [ ] (Anthony) SRC-1/2/3: EDID offers 1080p30 only; hot-plug toggled; driver log shows 2200×1125 progressive RGB
- [ ] (Anthony) CLK-1: `pl_clk0` = 75.000 MHz, `pl_clk2` disabled, its 4 loads moved to `pl_clk0` (Actual Frequency); HDMI IP clock settings + BSP updated; RX still locks. If not → tell Adam
- [ ] (Adam) Find why the TL isn't LUTRAM (`synth_1/runme.log`, `mem_reg`)
- [ ] (Adam) Out-of-context `cca_top` at 13.333 ns: WNS, WHS, worst endpoint

## Phase 1 — each side separately (Nov 12–18)

Exit: both halves pass their own checks.

- [ ] (Anthony) Threshold, converter, gate (THR-1–4, CNV-1–4, OUT-4) + Verilator TB (VER-1)
- [ ] (Anthony) VER-2 ILA at 1080p30: 1920×1080, one `tuser`, gap ~100k cycles
- [ ] (Anthony) INT-2 IRQ list; `write_bd_tcl` HDMI design into `scripts/bd/`
- [ ] (Adam) Centroiding hierarchy proc from `scripts/bd/pl_ps.tcl`
- [ ] (Adam) Fallback build from the proc at 75 MHz: WNS/WHS ≥ 0, interrupt count = frame count; tag `pre-hdmi-75mhz`
- [ ] (Adam) `docs/hdmi-cca_interface.md` v0.2: 1080p30, clock, threshold, reset
- [ ] (Shared) D2, D4

## Phase 2 — merge (Nov 18–24)

Exit: fresh clone builds, timing met, RX locks with the merged app.

- [ ] (Shared) INT-1: proc inside HDMI design; RX → threshold → converter → hierarchy
- [ ] (Shared) One PS config: HPM0_FPD + HPM0_LPD, one PL clock, pick the telemetry UART
- [ ] (Adam) Keep BRAM `0xA000_0000` and `axi_intc` `0xA001_0000`; check for no overlap with HDMI addresses
- [ ] (Adam) IRQ → `ilconcat_0/In2` = GIC 123; fix `interrupt.h:15` (121)
- [ ] (Adam) Make the `main.c:27` write to `0xA002_0000` build-dependent (no `axi_gpio` in HDMI build)
- [ ] (Adam) VER-4. If WNS < 0: TL → LUTRAM; `regress.sh full` passes before and after
- [ ] (Shared) INT-3: one Vitis app, one GIC init

## Phase 3 — on board (Nov 24–Dec 3; no lab Nov 26–29)

Exit: test image matches golden; 10 min without fault.

- [ ] (Shared) VER-3: known test image → board = `cca_golden.py`
- [ ] (Adam) Star-field video over HDMI vs golden
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
