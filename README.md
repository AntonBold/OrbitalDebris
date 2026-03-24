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
├── src/
│   ├── hdl/          # Synthesizable Verilog source files
│   ├── ip/           # IP core descriptors (.xci files only)
│   ├── xdc/          # Constraint files (timing, pin assignments)
│   └── bd/           # Block designs
├── sim/
│   ├── tb/           # Testbenches
│   └── scripts/      # Simulation Tcl scripts
├── vitis/
│   ├── src/
│   │   ├── app/      # Application C/C++ source
│   │   ├── drivers/  # Custom drivers
│   │   └── bsp/      # Board support package config
│   └── scripts/      # Vitis workspace Tcl scripts
├── docs/             # Specs, diagrams, reference material
├── vivado/           # Vivado project (.xpr tracked, build output ignored)
├── create_project.tcl
└── README.md
```

---

## Getting Started

### Prerequisites

- Vivado 2025.2 with Vitis
- Genesys ZU board files installed ([download from Digilent](https://digilent.com/reference/programmable-logic/genesys-zu/start))
- Git

### Clone the repo

```bash
git clone git@github.com:AntonBold/OrbitalDebris.git
cd OrbitalDebris
```

### Recreate the Vivado project

**Not ready yet** 

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

Or right-click each IP in the catalog and select *Generate Output Products*.

---

## Contributing

### Where to put your files

| File type                    | Location                           |
| ---------------------------- | ---------------------------------- |
| Verilog source (`.v`, `.sv`) | `src/hdl/`                         |
| Constraint files (`.xdc`)    | `src/xdc/`                         |
| IP cores                     | `src/ip/` — `.xci` descriptor only |
| Block designs                | `src/bd/`                          |
| Testbenches                  | `sim/tb/`                          |
| C/C++ application code       | `vitis/src/app/`                   |
| Custom drivers               | `vitis/src/drivers/`               |
| Docs, diagrams, specs        | `docs/`                            |

Never manually put files inside `vivado/*.runs`, `vivado/*.cache`, or `vitis/Debug/` — those are managed by the tools and are gitignored.

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

You should only see files under `src/`, `sim/`, `vitis/src/`, or `docs/`. If anything under `vivado/` or `vitis/Debug/` shows up, stop and check with the repo owner — the `.gitignore` may need updating.

### What not to commit

The `.gitignore` handles this automatically, but as a rule never commit:

- `vivado/*.runs/`, `vivado/*.cache/`, `vivado/*.sim/`, `vivado/*.hw/`
- `vivado/*.ip_user_files/`, `vivado/*.gen/`
- `vitis/Debug/`, `vitis/Release/`, `vitis/**/_ide/`
- `*.elf`, `*.bit`, `*.log`, `*.jou`

### Merge conflicts

Don't force push. Message the group and sort it out together.

---

## Architecture Overview

The design splits the processing pipeline into two domains:

**Pixel domain (PL — Verilog)** — processes raw video frames and computes object centroids. Runs on the FPGA fabric for deterministic, high-throughput per-pixel operations.

**Centroid domain (PS — C/C++)** — receives centroid data from the PL and runs classification and tracking algorithms. Runs on the ARM cores where complex, data-dependent logic is easier to implement and iterate on.

---

## Team

- Adam Welsh - MPSoC Infrastructure Development

- Anthony Bolda - Video Data Infrastructure Development

- Lemon Scott - Centroid Algorithm HDL Implementation
