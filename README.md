# Orbital Debris Tracker

FPGA-accelerated video processing pipeline for classifying and tracking orbital debris. Based on a MATLAB algorithm developed by the project advisor, reimplemented on the Digilent Genesys ZU (Zynq UltraScale+ XCZU5EV) with a pixel-domain / centroid-domain split:

- **PL (FPGA fabric, SystemVerilog):** binarized 1920×1080 video in, streaming connected-component analysis (single-pass CCL + per-object area and coordinate sums), results written to a shared BRAM, one interrupt per frame.
- **PS (ARM Cortex-A53, bare-metal C):** reads the centroids on the interrupt, runs the advisor's classification (assignment + GESD outlier test) and tracking, and streams results over UART.

**Status (2026-11-13): end-to-end on live HDMI video.** A laptop plays the advisor's star-field video (`SampleDataRun9.mp4`) full-screen over HDMI at 1920×1080p30. The board thresholds it, runs CCA in the PL, and classifies and tracks on the PS at the full 30 frames/s (no frames skipped). Every board centroid matched the source video pixel-exactly in the frames checked (`results/run2.csv` against `scripts/golden/png_frame.py`; 10 frames, 116–123 objects each, 0 missing, 0 extra). Timing is met at 75 MHz (WNS +0.65 ns).

- **Pipeline:** HDMI RX Subsystem (2 px/clk) → `threshold` (grey > 64) → `pix_2to1` (2 px/beat → 1 px/clk, start-of-frame gate) → `cca_top` → BRAM + interrupt → PS → UART telemetry.
- **Not yet verified:** the PS's star/object labels against the MATLAB reference; a 10-minute soak; HDMI replug.
- **Fallback build:** `create_project.tcl -tclargs pattern` swaps HDMI for the on-chip test pattern (3 static shapes + 1 moving square).

---

## Project materials

An index of the project's materials: code, documents, figures, data and references. It covers all branches. The tables below say which branch each item is on, where it isn't on every branch.

### Branches

| Branch | What's on it | State |
| --- | --- | --- |
| `main` | Everything: CCA RTL and its verification environment, HDMI front end (`scripts/bd/hdmi_hier.tcl`), threshold, 2:1 converter, integrated block design, PS application, scripted build flow | Default branch. The HDMI-to-centroids milestone was merged from `integrate` (Nov 2026) |

Earlier branches were merged and deleted: `centroiding` (CCA, PR #2), `pl_ps` (PS/PL integration and build flow, PR #4), `hdmi` (HDMI RX), `thresholding` (threshold block) and `integrate` (HDMI + centroiding in one block design). New work goes on a short-lived branch off `main`.

### Where things are, and who can access them

| What | Where | Access |
| --- | --- | --- |
| All code, specs, figures, report | GitHub [`AntonBold/OrbitalDebris`](https://github.com/AntonBold/OrbitalDebris), on the branches above | Repo is public |
| Datasets (advisor's simulation runs) | Advisor's public repo [`nnategh/orbital-debris`](https://github.com/nnategh/orbital-debris), folder [`assets/data/`](https://github.com/nnategh/orbital-debris/tree/master/assets/data) | Public |
| CSVs exported from those datasets, sweep results | Not in the repo. Local copy: `~/Desktop/orbital-debris/capstone_assets/` on Adam's laptop | **TODO:** add to the repo (or a shared drive) and link it here |
| Presentation slides (milestone presentations) | Google Drive | Accessible by team members only |
| Lab machine (Vivado/Vitis 2025.2 + board) | `vivadoclinic` lab PC. Clone at `~/Desktop/adam_stuff/OrbitalDebris` (HDMI licence is node-locked to this PC) | Team |

### Code

| Directory | Contents | Language |
| --- | --- | --- |
| `src/hdl/` | Synthesizable RTL: video threshold (`threshold`), 2:1 pixel converter with start-of-frame gate (`pix_2to1`), CCA pipeline (`cca_top`, `cca_control`, `ccl_decision`, `label_decision_logic`, `translator_lut`, `fifo`, `feature_extract`), test pattern generator (`pattern_gen`), button debouncer, Verilog shells for the block design (`*_bd.v`) | SystemVerilog / Verilog |
| `src/tb/` | Self-checking testbenches (see [Verifying the centroiding pipeline](#verifying-the-centroiding-pipeline-cca_top)) | SystemVerilog |
| `src/sw/` | PS application: BRAM reader, interrupt setup, HDMI RX bring-up (`hdmi/`), classifier, Hungarian assignment, tracker, UART telemetry, host unit tests (`test_*.c`) and the dataset test harness (`test_harness.c`) | C |
| `src/sw/vitis/` | Vitis app config: source list (`UserConfig.cmake`) and linker script (`lscript.ld`, 2 MB stack) | CMake / ld |
| `src/xdc/` | Pin constraints (Digilent Genesys ZU rev C XDC, HDMI pins enabled) | XDC |
| `src/bd/` | `hdmi_rx/hdmi_rx.bd`: Anthony's original HDMI RX design, kept for reference only. The block design is built from Tcl by `scripts/create_project.tcl` (`scripts/bd/integrate.tcl` + `*_hier.tcl`) | Vivado BD |
| `src/sim/` | QuestaSim/ModelSim run scripts | Tcl / sh |
| `scripts/` | Build flow (`create_project.tcl`, `generate_bitstream.tcl`, `create_vitis.py`, `build_app.py`, `run_board.tcl`), block design (`bd/integrate.tcl` top, `bd/hdmi_hier.tcl`, `bd/centroid_hier.tcl`; `bd/pl_ps.tcl` legacy), simulation (`simulate.sh`, `filelists/`), regressions (`regress.sh`, `golden/`), screenshot-vs-board check (`golden/png_frame.py`), telemetry decoder (`telemetry_decode.py`) | Tcl / Python / sh |
| `compression_scripts/` | Converts grayscale video to the 1-bit-per-pixel format, and plays it back (own README) | Python |
| `original_matlab/` | The advisor's MATLAB reference implementation of the classifier and tracker, copied from [`nnategh/orbital-debris`](https://github.com/nnategh/orbital-debris) | MATLAB |
| `boards/` | Digilent Genesys ZU board files, loaded by `create_project.tcl` | XML |

**Comments:** every file in `src/sw/`, `scripts/` and most of `src/tb/` starts with a header comment explaining what it does and how it's used. Specs are cross-referenced by section. **TODO:** add header comments to the core RTL files that don't have one yet: `cca_top.sv`, `ccl_decision.sv`, `label_decision_logic.sv`, `feature_extract.sv`, `fifo.sv`, `blinky.sv`, plus `compression_scripts/*.py` and `original_matlab/main.m`.

### Documents and writing

| Document | What it is |
| --- | --- |
| [`docs/spring26_report.md`](docs/spring26_report.md) | Spring 2026 progress report: architecture, MATLAB→C translation, test harness, validation results vs MATLAB |
| [`docs/hdmi-cca_interface.md`](docs/hdmi-cca_interface.md) | Threshold output → centroiding interface (v0.2): 16-bit, 2 px/beat AXI4-Stream, 1080p30 on 75 MHz, backpressure, frame timing |
| [`docs/pix_2to1_spec.md`](docs/pix_2to1_spec.md) | 2:1 pixel converter and start-of-frame gate: interface, behaviour, requirements, test plan |
| [`docs/PLAN.md`](docs/PLAN.md) | HDMI → centroiding integration plan and status, to the Dec 11 demo |
| [`docs/pl-ps_interface_spec.md`](docs/pl-ps_interface_spec.md) | PL → PS handoff (v0.3): BRAM layout, word formats, interrupt protocol, reset, frame trigger, limits |
| [`docs/uart-telemetry.md`](docs/uart-telemetry.md) | Binary UART telemetry packet format (921600 baud) and the decoder |
| `compression_scripts/README.md` | How to produce 1-bit-per-pixel test video |

### Figures

| Figure | What it shows | How it was made |
| --- | --- | --- |
| `docs/top_level_cca_architecture.jpg` | Top-level CCA hardware architecture | **TODO:** source/tool |
| `docs/feature_extract_top_bd.jpg` | Feature-extract module block diagram | **TODO:** source/tool |
| `docs/golden_model_flow.svg` / `.png` | How the golden model checks the hardware: the same frame goes through the RTL and an independent flood-fill model, and the BRAM contents are compared | Hand-written SVG, rendered to PNG with `rsvg-convert` |

Simulation results are printed by the testbenches, not saved as figures. Waveforms go to `sim/build/dump.vcd` when requested (GTKWave). **TODO:** put the figures in a slide deck with a caption for each.

### Data

| Dataset | Location | Description |
| --- | --- | --- |
| `SampleDataRun1`–`SampleDataRun10` (`.mat` + `.mp4` each) | [`nnategh/orbital-debris/assets/data`](https://github.com/nnategh/orbital-debris/tree/master/assets/data), described in `Run Description.txt` there | Simulated star-field videos from NASA Marshall's Dynamic Star Field Simulator: 1920×1080, 60 fps, 60 s (3,601 frames), grayscale 0–1, ~110–135 spots and ~1–5 objects per frame, with ground-truth labels. Each run sets a different initial spacecraft angular velocity `w0`: Run1 original, Run2 no rotation, Run3 single X, Run4 single Z, Run5 faster Z, Run6 faster X, Run7 slow full, Run8 slow X, Run9 slow Z, Run10 faster full. The `.mat` files are read by `original_matlab/DataReader.m`. Runs 1, 5 and 10 are the ones used in `docs/spring26_report.md` §7 |
| `centroids*.csv` | Not in repo (local: `capstone_assets/`). **TODO:** add, with the export script | Centroids exported from the `.mat` files as `frame,x,y,label`. Input to `src/sw/test_harness.c` (path set by `CSV_PATH` at the top of that file). Results in `docs/spring26_report.md` §7 |
| `sweep_results.csv` | Not in repo. **TODO:** add with the sweep script | Classifier parameter sweep (960 configurations), report §7.3 |
| `compression_scripts/onebpp_vid/process_attempt1` | In repo | 1-bit-per-pixel test video, 15 frames of 1920×1080 |
| Golden-model vectors | Generated into `sim/build/vectors/` by each testbench run (not stored) | Random and directed frames plus expected centroids, reproducible from the printed seed |
| Board telemetry captures | Produced by `scripts/telemetry_decode.py --csv run.csv` (not stored yet) | Per-frame centroids and labels from the board |

### References and acknowledgements

**Papers**
- **Classification and tracking algorithm:** the advisor's paper (unpublished manuscript; not in this repo, ask the advisor for a copy). The MATLAB code in `original_matlab/` is an unmodified copy of `main.m`, `Tracker.m` and `DataReader.m` from [`nnategh/orbital-debris`](https://github.com/nnategh/orbital-debris) (MIT License, © 2019 Yasin Zamani). The C classifier and tracker in `src/sw/` are translated from it.
- **CCA hardware:** Spagnolo, Perri & Corsonello, "An Efficient Hardware-Oriented Single-Pass Approach for Connected Component Analysis," *Sensors* 2019 (`docs/fpga-accelerator-paper.pdf`, open access).
- **Golden-model flood fill:** standard connected-component labeling by flood fill. See Rosenfeld & Pfaltz, "Sequential Operations in Digital Picture Processing," *J. ACM* 13(4), 1966.

**Third-party files**
- `original_matlab/`: MIT License, © 2019 Yasin Zamani (see above).
- `boards/` and `src/xdc/Genesys-ZU-5EV-D-Master.xdc`: Digilent.
- `src/sw/vitis/UserConfig.cmake` and `lscript.ld`: generated from AMD Vitis 2025.2 templates (MIT), then edited.
- The PS uses the AMD/Xilinx standalone BSP drivers (`xil_*`, `XScuGic`, `XIntc`, `XUartPs`).

**Use of AI tools:** this project used AI assistants (Anthropic's Claude, through Claude Code) for assistance with:
- Verification
- RTL bug fixes
- PS software
- Build and board scripts
- Documentation

---

## Hardware & Tools

|        |                        |
| ------ | ---------------------- |
| Board  | Digilent Genesys ZU-5EV |
| SoC    | Zynq UltraScale+ XCZU5EV |
| Vivado | 2025.2                 |
| Vitis  | 2025.2                 |
| HDL    | SystemVerilog (Verilog shells for the block design) |
| Simulation | Verilator 5 (QuestaSim optional) |

---

## Building and running on the board

Everything Vivado and Vitis generate (`build/`, `vitis/`) is gitignored and is recreated from the repo. Run from the repo root, with Vivado/Vitis 2025.2 on `PATH`:

```bash
# 1. Vivado project (board files from boards/, block design from scripts/bd/integrate.tcl)
#    default: HDMI input.  -tclargs pattern: on-chip test pattern instead
vivado -mode batch -source scripts/create_project.tcl -log create.log -nojournal

# 2. Bitstream + build/pl_ps.xsa (prints WNS at the end). Last argument = parallel jobs
vivado -mode batch -source scripts/generate_bitstream.tcl -log build/bit.log -nojournal -tclargs $(nproc)

# 3. Vitis platform + app from the XSA -> vitis/debris_app/build/debris_app.elf
vitis -s scripts/create_vitis.py
#    after editing src/sw only:  vitis -s scripts/build_app.py

# 4. Board in JTAG boot mode. Start the decoder, then program and run
python3 scripts/telemetry_decode.py --baud 921600 /dev/ttyUSB1 --csv results/run.csv   # terminal 1
xsdb scripts/run_board.tcl                                 # terminal 2
```

`run_board.tcl` doesn't use Vitis's Run button, which hangs on this board. It runs `psu_init`, programs the PL and starts the app over JTAG.

**HDMI source (laptop):** set the board's display to exactly 1920×1080 (30 Hz, extended, no HiDPI scaling) and play the video full-screen at 1:1, with no player controls or cursor. Objects are single pixels, so any scaling destroys them:

```bash
mpv --fs --fs-screen=1 --screen=1 --video-unscaled=yes --no-osc --osd-level=0 \
    --cursor-autohide=always --loop SampleDataRun9.mp4
```

**Pattern build:** with `FREE_RUN 1` in `src/sw/main.c`, the PS starts the test pattern itself through an AXI GPIO. With `FREE_RUN 0`, press BTN2 for each frame.

---

## Contributing

### Where to put your files

| File type                    | Location                           |
| ---------------------------- | ---------------------------------- |
| SystemVerilog / Verilog RTL  | `src/hdl/`                         |
| Constraint files (`.xdc`)    | `src/xdc/`                         |
| IP cores                     | `src/ip/` (`.xci` descriptor only) |
| Block design                 | `scripts/bd/` (Tcl)                |
| Testbenches                  | `src/tb/` + a file list in `scripts/filelists/` |
| ARM application code         | `src/sw/` (headers in `src/sw/include/`) |
| Vitis app config             | `src/sw/vitis/`                    |
| Docs, diagrams, specs        | `docs/`                            |

Never put files in `build/` or `vitis/`. Both are generated and gitignored.

### Daily workflow

Always pull before starting work:
```bash
git pull
```

When you're done:
```bash
git add src/hdl/your_file.sv      # add specific files, not git add .
git commit -m "brief description of what you changed"
git push
```

Before pushing, check that nothing unintended is staged with `git status`. Never commit `build/`, `vitis/`, `*.elf`, `*.bit`, `*.log` or `*.jou` (the `.gitignore` handles these). If a push is rejected because the remote is ahead, run `git pull --rebase` and push again. Don't force push. If there's a conflict you can't sort out, message the group.

---

## Verifying the centroiding pipeline (cca_top)

Simulation uses Verilator (`./simulate <testbench> [+plusargs]`). The `cca_*_tb`
testbenches are self-checking: each frame is compared against an independent
golden model (`scripts/golden/cca_golden.py`, a plain 4-connected flood fill,
not the hardware's algorithm). The testbench reads the BRAM the way the PS
does, per `docs/pl-ps_interface_spec.md`.

| Command | What it runs | Time |
| --- | --- | --- |
| `scripts/regress.sh smoke` | golden self-test, `cca_top_tb`, directed suite, 30 random frames | ~20 s |
| `scripts/regress.sh full [seed]` | smoke + label-capacity suite + 5 × 300 random frames + 1920×1080 frames + checker self-tests | ~1 min |
| `scripts/regress.sh selftest` | injects a fault for each checker and confirms it fires | ~15 s |
| `./simulate cca_random_tb +seed=N +n=300` | reproduce one random run (the seed is printed by every run) | |
| `./simulate cca_directed_tb +dump_test=12 +dump_scope=decision` | VCD of one test and one scope only (`sim/build/dump.vcd`) | |
| `src/sim/questa_run.sh cca_directed_tb` | the same testbench under QuestaSim | |

Testbenches (all share `src/tb/cca_env_tb.sv`):

- `cca_directed_tb` (64×48): edge cases, merge shapes, BRAM/TL capacity,
  tvalid gaps, frame-timing limits, reset injection, frame-number limit, and
  malformed framing.
- `cca_wide_tb` (256×64): 1022/1023/1024/1100 labels per frame.
- `cca_random_tb` (64×48): constrained-random frames, gaps and resets.
- `cca_full_tb` (1920×1080): a few full-resolution frames.
- `cca_top_tb`: the original `pattern_gen` smoke test.

Each test prints `PASS`/`FAIL`. Known issues and accepted limitations print
`XFAIL`. Out-of-contract stimulus prints `INFO` (reported, never judged). The
run exits nonzero on any `FAIL`, or on an `XPASS` (an expected-fail test that
passed: update its tag). Run-end sections list every checker count and a
coverage table, which flags any class that was never hit.

To shrink a failing frame to a minimal repro:
`scripts/golden/minimize.py --binary sim/build/sim_cca_random_tb --vectors sim/build/vectors/cca_random.txt --test <name>`.

**Out-of-contract framing** (observed in `cca_directed_tb`). Frame boundaries
come from counting `tlast`; `tuser` only resets the row/column counters. A
frame without exactly HEIGHT lines leaves line-buffer, TL and feature-table
state behind, and that state corrupts the following frame. A reset recovers.

| Stimulus | Observed |
| --- | --- |
| missing `tlast` / short frame | no interrupt; the next frame reports the leftover objects too |
| extra `tlast` / long frame | interrupt on schedule; the following frame is corrupted |
| missing `tuser` | that frame is corrupted (first-pixel handling relies on it); the next frame is fine |
| short / long line | that frame is corrupted; the next frame is fine |

---

## Team

- Adam Welsh - MPSoC Infrastructure Development, Centroiding Algorithm HDL Implementation

- Anthony Bolda - Video Data Infrastructure Development
