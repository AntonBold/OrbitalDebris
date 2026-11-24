# Evaluation Plan: Accuracy, Real-Time Performance, Cost vs Software-Only

**Date:** 2026-11-23 · **Demo:** 2026-12-11 (freeze 2026-12-04)

**Goal:** show the design is accurate, real-time and efficient, and compare it with doing the whole pipeline in software.

## Measurements

| # | Measurement | Method | Owner | Status |
| --- | --- | --- | --- | --- |
| 1 | **Accuracy**: board vs C on host vs MATLAB | One table from what exists: `test_harness` Runs 1/5/10 (C vs MATLAB), board `results/run5.csv` (`scripts/classify_check.py`), tracking parity (`scripts/track_check.py`), board tracking `results/run6.csv` (`scripts/board_track_check.py`) | Claude | data in hand |
| 2 | **PL centroiding time per frame** | Analytic: 1 px/clk at 75 MHz, results a few cycles after the frame's last pixel (frame streams in ~27.6 ms at 1080p30 line rate). Confirm with the ILA (VER-2) | Adam / Anthony | to do |
| 3 | **PS time per frame**: classify, track, telemetry | A53 cycle counter (`XTime_GetTime`) around each stage in `main.c`; print min/mean/max every 300 frames (the decoder shows text lines) | Claude (code), Adam (board run) | to do |
| 4 | **Software-only baseline** | Same binarise + CCL + centroids in C (port of `scripts/golden/cca_golden.py`) on (a) the A53 with a frame in DDR, (b) the laptop; plus MATLAB `regionprops` time. ms per 1920×1080 frame vs item 2 | Claude (code), Adam (board run) | to do |
| 5 | **FPGA cost** | Vivado utilisation (LUT/FF/BRAM/DSP) and power reports of the HDMI build | Adam | to do |
| 6 | **Robustness** | 10-minute soak (dropped frames, `frames_skipped`), HDMI replug | Adam | to do |

**Main comparison for the report:** item 4 (software CCL on the A53, ms per frame) against item 2 (PL at line rate). That's the core argument for putting centroiding in the FPGA.

## Known results (2026-11-23)

- Classification, board (Run 9, d = 5): TPR 0.983, TNR 0.991; matches the host replay exactly.
- Host vs MATLAB: classifier parity on the translation features; tracker identical to MATLAB on Runs 1, 5, 10.
- Tracking, board (run6): 96.5% of true object observations tagged, 88% of true tracks keep one id; false tracks short (median 4 frames).
- Frame drops: only around the video loop wrap with telemetry v1; telemetry v2 at 921600 baud added a few steady-state drops (UART send ~14 ms/frame). Telemetry moved to 1.5 Mbaud: to verify (run7).

## Order

1. Items 3 and 4: code (Claude).
2. One lab session: run7 (1.5 Mbaud check), item 3 timing, item 4a, item 5 reports, item 6 soak/replug.
3. Tables and figures for the report (Claude), from `results/`.
