# Orbital Debris Tracker

FPGA-accelerated video processing pipeline for classifying and tracking orbital debris. Based on algorithms developed in MATLAB, reimplemented in hardware using a pixel-domain/centroid-domain split architecture on the Genesys ZU (Zynq UltraScale+ MPSoC).

The FPGA fabric handles per-pixel centroid calculation in Verilog. The ARM processing system runs the computationally intensive classification and tracking algorithms in software using centroid data from the PL.

---

## Hardware & Tools

|        |                        |
| ------ | ---------------------- |
| Board  | Digilent Genesys ZU    |
| SoC    | Zynq UltraScale+ MPSoC |
| Vivado | 2025.2                 |
| Vitis  | 2025.2                 |
| HDL    | Verilog                |

---

## Repo Structure
```
OrbitalDebris/
├── boards/
│   └── digilent/
│       └── genesys-zu-5ev/   # Board files — no separate installation needed
├── src/
│   ├── hdl/          # Synthesizable Verilog source files
│   ├── xdc/          # Constraint files (timing, pin assignments)
│   ├── bd/           # Block designs
│   ├── tb/           # Testbenches
│   ├── sim/          # Scripts to run testbenches in ModelSim
│   └── sw/           # Software for ARM Processor
│       ├── include/  # Include files for software

├── scripts/          # Important scripts (i.e. create_project.tcl)
├── docs/             # Specs, diagrams, reference material
└── README.md
```

---

## Getting Started

### Prerequisites

- Vivado 2025.2 with Vitis
- Git

No separate board file installation is required. The Digilent Genesys ZU-5EV board files are included in `boards/` and are loaded automatically by `create_project.tcl`. The project can be recreated on any machine with a bare Vivado 2025.2 install.

### Clone the repo
```bash
git clone git@github.com:AntonBold/OrbitalDebris.git
cd OrbitalDebris
```

### Recreate the Vivado project

From the root of the repo:
```bash
vivado -mode batch -source create_project.tcl
```

This recreates the full project from source files — no need to commit build artifacts.

### Regenerate IP output products

After recreating the project, open Vivado and in the Tcl console run:
```tcl
generate_target all [get_ips]
```

Or right-click each IP in the catalog and select *Generate Output Products*.

---

## Contributing

### Where to put your files

| File type                    | Location                           |
| ---------------------------- | ---------------------------------- |
| Verilog source (`.v`, `.sv`) | `src/hdl/`                         |
| Constraint files (`.xdc`)    | `src/xdc/`                         |
| IP cores                     | `src/ip/` — `.xci` descriptor only |
| Block designs                | `src/bd/`                          |
| Testbenches                  | `sim/tb/`                          |
| C/C++ application code       | `vitis/src/app/`                   |
| Custom drivers               | `vitis/src/drivers/`               |
| Docs, diagrams, specs        | `docs/`                            |

Never manually put files inside `vivado/*.runs`, `vivado/*.cache`, or `vitis/Debug/` — those are managed by the tools and are gitignored.

### Daily workflow

Always pull before starting work:
```bash
git pull origin main
```

When you're done:
```bash
git add src/hdl/your_file.v      # add specific files, not git add .
git commit -m "brief description of what you changed"
git push origin main
```

Before pushing, verify nothing unintended is staged:
```bash
git status
```

You should only see files under `src/`, `sim/`, `vitis/src/`, `boards/`, or `docs/`. If anything under `vivado/` or `vitis/Debug/` shows up, stop and check with the repo owner — the `.gitignore` may need updating.

### What not to commit

The `.gitignore` handles this automatically, but as a rule never commit:

- `vivado/*.runs/`, `vivado/*.cache/`, `vivado/*.sim/`, `vivado/*.hw/`
- `vivado/*.ip_user_files/`, `vivado/*.gen/`
- `vitis/Debug/`, `vitis/Release/`, `vitis/**/_ide/`
- `*.elf`, `*.bit`, `*.log`, `*.jou`

### Merge conflicts

Don't force push. Message the group and sort it out together.

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

## Architecture Overview

The design splits the processing pipeline into two domains:

**Pixel domain (PL — Verilog)** — processes raw video frames and computes object centroids. Runs on the FPGA fabric for deterministic, high-throughput per-pixel operations.

**Centroid domain (PS — C/C++)** — receives centroid data from the PL and runs classification and tracking algorithms. Runs on the ARM cores where complex, data-dependent logic is easier to implement and iterate on.

---

## Team

- Adam Welsh - MPSoC Infrastructure Development, Centroiding Algorithm HDL Implementation

- Anthony Bolda - Video Data Infrastructure Development
