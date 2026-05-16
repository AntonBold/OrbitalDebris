# Real-Time FPGA Implementation of an Orbital Debris Tracking Algorithm

## Spring 2026 Progress Report

**Adam Welsh** — PS/PL Integration & ARM Software  
**Anthony Bolda** — PL Video Data Infrastructure  
**May 2026**

---

## 1. Project Overview

This project implements a real-time FPGA-accelerated pipeline for classifying and tracking orbital debris in video feeds. The system is based on a MATLAB algorithm developed by the project advisor and targets the Digilent Genesys ZU board (Zynq UltraScale+ XCZU5EV) using Vivado/Vitis 2025.2.

The architecture is split into two processing domains:

- **PL (FPGA Fabric):** Handles pixel-domain processing — ingests raw 1920x1080 HDMI video at 60fps, binarizes frames, runs streaming connected component labeling, and computes object centroids
- **PS (ARM Cortex-A53):** Runs the classification and tracking algorithm in C — receives centroid data from the PL over BRAM and executes the computationally intensive classification and tracking logic

---

## 2. Team Roles

| Team Member   | Role                      | Responsibilities                                                         |
| ------------- | ------------------------- | ------------------------------------------------------------------------ |
| Adam Welsh    | MPSoC Infrastructure      | PS/PL integration, Vivado block design, C application, testing           |
| Anthony Bolda | Video Data Infrastructure | HDMI frontend, streaming CCL pipeline, centroid accumulator, Verilog RTL |

---

## 3. Hardware & Software Requirements

The following are the minimum requirements to reproduce, build, and run this project. These are provided to support grant proposal planning.

### 3.1 Development Machine

| Resource | Minimum            | Recommended        | Notes                                                                                                                                                                                                |
| -------- | ------------------ | ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| RAM      | 16GB               | 32GB+              | 16GB minimum for Vivado synthesis on Zynq UltraScale+; 32GB recommended for comfortable implementation/place-and-route. Our experience: 7.6GB is insufficient — OOM killer terminates Vivado mid-run |
| CPU      | 4 cores            | 8+ cores           | More cores reduce synthesis time significantly; Vivado parallelizes heavily                                                                                                                          |
| Storage  | 100GB free         | 200GB SSD          | Vivado installation ~60GB, project build artifacts 20–40GB per run; SSD strongly preferred                                                                                                           |
| OS       | Ubuntu 22.04.5 LTS | Ubuntu 22.04.5 LTS | Required for Vivado/Vitis 2025.2 Linux support                                                                                                                                                       |

### 3.2 Software Licenses

| Software                 | License Type               | Notes                                                                                                |
| ------------------------ | -------------------------- | ---------------------------------------------------------------------------------------------------- |
| Vivado ML Edition 2025.2 | Free (device-locked)       | Zynq UltraScale+ is covered under the free Vivado ML Standard tier — no paid license required        |
| Vitis 2025.2             | Free (bundled with Vivado) | Included with Vivado ML download                                                                     |
| Vitis HLS 2025.2         | Free (bundled with Vivado) | Included with Vivado ML download                                                                     |
| MATLAB                   | University license         | Required for algorithm validation and ground truth CSV export from professor's .mat simulation files |

### 3.3 Hardware

| Item                                  | Purpose                                      | Estimated Cost   |
| ------------------------------------- | -------------------------------------------- | ---------------- |
| Digilent Genesys ZU (XCZU5EV variant) | Target FPGA board                            | ~$2000           |
| DisplayPort/HDMI monitor              | Video output verification                    | Available in lab |
| USB-JTAG cable                        | Board programming (included with Genesys ZU) | Included         |
| 12V DC power supply                   | Board power (included with Genesys ZU)       | Included         |

### 3.4 Notes

- All Xilinx/AMD tools (Vivado, Vitis, HLS) are available at no cost under the free ML Standard license tier, which covers the XCZU5EV device used in this project. No paid EDA licenses are required.
- MATLAB is the only paid software dependency, and only for the validation/testing workflow. The embedded C application itself has no MATLAB dependency.
- The primary hardware bottleneck this semester was development machine RAM. A machine with 32GB+ RAM is the single most impactful resource for unblocking synthesis. 3. Hardware & Tools

| Component      | Specification                                  |
| -------------- | ---------------------------------------------- |
| Board          | Digilent Genesys ZU (Zynq UltraScale+ XCZU5EV) |
| Processor      | ARM Cortex-A53 (64-bit, bare-metal)            |
| Vivado / Vitis | 2025.2                                         |
| HDL            | Verilog                                        |
| HLS            | Vitis HLS 2025.2                               |

---

## 4. PL Video Pipeline — Anthony Bolda

### 4.1 System Architecture

The PL video pipeline processes HDMI input in a fully streaming fashion at one pixel per clock cycle. The dataflow is:

1. HDMI 1.4 TMDS signals enter the FPGA
2. Video PHY recovers the pixel clock and converts TMDS to parallel format
3. HDMI RX Subsystem decodes TMDS and outputs AXI4-Stream
4. AXI4S-to-Video bridge generates pixel data with sync and coordinate signals
5. Spot Centroids block: Binarize → Streaming CCL → Centroid Accumulate
6. Three BRAMs store line buffer, equivalence table, and centroid stats
7. PS reads centroid stats BRAM and computes final centroid positions

<!-- Anthony: replace or supplement with your block diagram image -->

<!-- ![HDMI to Centroid Pipeline Block Diagram](images/block_diagram.png) -->

### 4.2 MATLAB vs FPGA Centroid Extraction

The PL approach diverges from MATLAB's `regionprops()` because of hardware implementation

| Stage        | MATLAB (regionprops)      | FPGA (Streaming)                           |
| ------------ | ------------------------- | ------------------------------------------ |
| Input        | Full frame in memory      | Pixel stream (AXI4-Stream)                 |
| Grayscale    | `rgb2gray()`              | Grayscale hardware block                   |
| Binarization | `imbinarize(I, T)`        | Threshold hardware block                   |
| CCL          | Implicit in regionprops   | Streaming CCL (neighbor check + labeling)  |
| Centroid     | `regionprops('Centroid')` | Centroid Accumulator (sum_x, sum_y, count) |
| Output       | Centroid list (x, y)      | Stats BRAM → PS reads via AXI              |

MATLAB processes full frames using high-level functions. The FPGA processes pixels in a streaming pipeline at 1 pixel/clock, explicitly implementing CCL, memory management, and accumulation in hardware.

The MATLAB approach processes full frames one at a time. The FPGA breaks a frame into lines, processing the current line and the previous line one at a time. 

### 4.3 BRAM Allocation

Three BRAMs are used in the PL pipeline:

- **Line Buffer BRAM:** Stores previous row labels for neighbor lookups during streaming CCL. Size: 1920 entries × label width.
- **Equivalence Table BRAM:** Stores mappings for label merging during CCL. Updated per frame.
- **Stats BRAM:** Stores centroid accumulation data (sum_x 32-bit, sum_y 32-bit, count 21-bit) per label. Output location read by PS (which then calculates approximate centroid positions)

### 4.4 Implementation

The pipeline is implemented using three complementary approaches:

- **Block Design:** Xilinx IP blocks (Video PHY, HDMI RX Subsystem, AXI BRAM Controller, Zynq MPSoC) connected via AXI interfaces
- **Custom RTL (Verilog):** Streaming CCL engine, centroid accumulator, preprocessing logic
- **HLS (Vitis HLS):** Threshold block implemented in C++ and synthesized to RTL

### 4.5 Current Status & Next Steps

Given the setbacks in setting up a working machine, development in Vivado has only just started. However, the foundation is laid above; all that is required is implementation.

The Orbital Debris Video Processing design will closely follow the the front-end of Vivado's Genesuys ZU HDMI tutorial project, which means there is a detailed block diagram our work can draw from. We have conducted successful simulations of said HDMI tutorial project; now we must insert our own centroid logic and construct test cases. This is no easy task, but I am confident.

Once the logic is complete, simulation will begin. Once a fully working video processing front end is complete; I will work with Adam to create the interface between PS & PL.

More concretely, I must:

- Route the complete block diagram based of the HDMI project
- Write the SpotCentroids algorithm in Verilog
- Insert the SpotCentroids hardware blocks alongside our other custom RTLs into the block diagram from above.
- Write testbenches and validate the full pipeline
- Work with Adam to confirm our PL and PS sides are integratable. 

---

## 5. PS/PL Integration & ARM Software — Adam Welsh

### 5.1 Vivado Block Design

The MPSoC-side Vivado block design has been completed with the following IP blocks instantiated, connected, and address-assigned:

- Zynq UltraScale+ MPSoC
- AXI BRAM Controller
- Block Memory Generator
- AXI Interrupt Controller

A `create_project.tcl` script was developed to reproduce the entire Vivado project from scratch with a single command. Digilent Genesys ZU-5EV board files are committed directly into the repository under `boards/`, eliminating any dependency on system-level Vivado configuration.

### 5.2 PL/PS Interface Specification

The PL writes centroid data into a shared BRAM at base address `0xA0000000`. The BRAM is organized as three sequential frame blocks in a round-robin buffer (oldest overwritten):

- **Header word:** frame number (upper bits) + centroid count (lower 10 bits)
- **Centroid words (32-bit packed):** bits 31:21 = X (11-bit, 0–1919), bits 20:10 = Y (11-bit, 0–1079), bit 9 = valid flag
- Maximum 256 centroids per frame block
- PL pulses interrupt on frame completion; PS reads newest frame and skips if still processing

### 5.3 Hardware Blocker

Bitstream generation has been the primary hardware blocker this semester. The assigned lab machine has only 7.6GB of RAM, which is insufficient for Vivado synthesis on the Zynq UltraScale+ (requires 16–32GB minimum). The Linux OOM killer repeatedly terminates Vivado mid-synthesis.

Secondary lab machines run Vivado 2022.1, which is incompatible with the 2025.2 project IP versions. As a resolution, the senior capstone lab machine (Ryzen 9 9950X, 96GB RAM) has been identified. Internet connectivity has been established on the machine. The remaining blocker is Ubuntu 22.04.5 driver support for the new motherboard hardware — once resolved, Vivado+Vitis will be installed and bitstream generation will proceed via `create_project.tcl`.

### 5.4 Vitis Environment

The Vitis bare-metal development environment has been fully configured:

- `debris_platform` created from bitstream-free XSA export
- `debris_app` application project targeting `psu_cortexa53_0` (ARM Cortex-A53, 64-bit, standalone)
- `UserConfig.cmake` configured with include paths, source files, and math library linkage (`-lm`)
- Full project builds successfully and produces `debris_app.elf`

### 5.5 MATLAB-to-C Algorithm Translation

The professor's MATLAB `Tracker` class (~1000 lines, OOP) has been translated into modular embedded C. All file I/O, video rendering, and visualization were stripped and replaced with a BRAM hardware interface.

| Module          | Description                                                    | Replaces                         |
| --------------- | -------------------------------------------------------------- | -------------------------------- |
| `centroid.h`    | Core data structures and constants                             | MATLAB class properties          |
| `cost_matrix.c` | Euclidean distance matrix between centroid sets                | Inline distance computation      |
| `hungarian.c`   | Optimal centroid-to-centroid assignment                        | MATLAB `matchpairs()`            |
| `geometry.c`    | Rotation math: bisectors, intersection, angle, rotation center | Tracker static methods           |
| `classify.c`    | Classification loop with GESD outlier detection                | `Tracker.classify()`             |
| `track.c`       | Object tracking and persistent ID assignment                   | `Tracker.track()` + `makeTags()` |
| `bram_io.c`     | PS/PL interface: reads packed centroid words from BRAM         | `DataReader` file I/O            |
| `interrupt.c`   | Interrupt handler stub for frame-ready signal                  | N/A (new for hardware)           |
| `main.c`        | Bare-metal entry point and frame processing loop               | `Tracker.main()`                 |

**Key translation challenges:**

- `matchpairs()` → Full Munkres Hungarian algorithm implemented from scratch
- `isoutlier(..., 'gesd')` → Rosner (1983) Generalized ESD test with t-distribution quantile approximation
- Dynamic MATLAB arrays → Fixed-size static arrays (`MAX_CENTROIDS=256`) for embedded constraints
- `NaN` labels → Explicit `LABEL_UNKNOWN=-1` integer sentinel value

---

## 6. Testing Methodology

A standalone test harness (`test_harness.c`) was developed that compiles and runs on any Linux/Mac machine without requiring hardware:

- Exports centroid ground truth from professor's `.mat` simulation files to CSV (frame, x, y, label)
- Reads CSV frame by frame through the full C classification pipeline
- Computes TPR, TNR, and unknown rate — identical metrics to the MATLAB reference evaluation
- Accepts command line arguments for all classifier config parameters
- `--quick` mode processes first 500 frames for rapid iteration

A Python parameter sweep script tests all combinations of classifier configuration parameters across 960 total configurations, outputting results to `sweep_results.csv`.

**Compile and run:**

```bash
cd vitis/src/app
gcc -o test_harness test_harness.c classify.c cost_matrix.c geometry.c hungarian.c track.c -lm -I./include
./test_harness 1000 10 1 1 0 1 0
```

---

## 7. Validation Results

### 7.1 Performance vs MATLAB Reference

**SampleDataRun1** — 3,601 frames, 410,245 centroid observations

| Metric            | C Implementation | MATLAB Reference |
| ----------------- | ---------------- | ---------------- |
| TPR (Recall)      | 0.9620           | 0.9999           |
| TNR (Specificity) | 0.9799           | 0.9959           |
| Unknown Rate      | 0.0004           | 0.0010           |

**SampleDataRun5** — 3,601 frames, 392,419 centroid observations

| Metric            | C Implementation | MATLAB Reference |
| ----------------- | ---------------- | ---------------- |
| TPR (Recall)      | 0.4342           | 0.9973           |
| TNR (Specificity) | 0.9630           | 0.9945           |
| Unknown Rate      | 0.0006           | 0.0026           |

### 7.2 Dataset Motion Analysis

Root cause analysis of the Run5 performance gap was conducted by comparing object and star motion characteristics:

| Dataset | Avg Spots | Avg Objects | Obj Motion (px/frame) | Star Motion (px/frame) | Obj/Star Ratio |
| ------- | --------- | ----------- | --------------------- | ---------------------- | -------------- |
| Run1    | 114.0     | 5.1         | 1008.3 ± 569.2        | 826.5 ± 432.7          | **1.22**       |
| Run5    | 109.0     | 4.9         | 920.5 ± 549.7         | 829.7 ± 431.1          | **1.11**       |
| Run10   | 133.5     | 1.1         | 626.3 ± 417.5         | 822.6 ± 428.9          | **0.76**       |

When the object/star motion ratio exceeds ~1.2 (Run1), translation-based GESD reliably identifies objects. When the ratio falls below 1.0 (Run10), objects move slower than stars on average — translation alone is insufficient and rotation-based classification becomes the primary discriminator. This directly explains the Run5 and Run10 performance gaps and motivates the rotation delta chain fix as the highest priority remaining algorithm work.

### 7.3 Optimal Classifier Configuration

| Parameter                   | Optimal Value | Notes                                        |
| --------------------------- | ------------- | -------------------------------------------- |
| `unmatched_cost`            | 1000.0        | Insensitive above 500                        |
| `max_num_objects`           | 10            | Best TPR/TNR balance                         |
| `delta`                     | 1             | Irrelevant until delta chain fix implemented |
| `use_translation_magnitude` | 1 (enabled)   | Essential — disabling collapses TPR to ~0.5% |
| `use_translation_angle`     | 0 (disabled)  | No measurable benefit                        |
| `use_rotation_center`       | 1 (enabled)   | Improves TNR                                 |
| `use_rotation_angle`        | 0 (disabled)  | Marginal improvement only                    |

---

## 8. Known Remaining Work

### 8.1 PL Pipeline (Anthony)

Summarizing what was covered in detail above for my section, the workflow will be:

- Route complete block diagram
- Write SpotCentroids algorithm in Verilog
- Write testbenches and validate full pipeline
- Integrate with Adam's BRAM interface specification

### 8.2 Algorithm (Adam)

- **Rotation delta chain:** MATLAB chains back through full delta window via `matches{t1}.t`. C currently uses `memory[memory_count-2]` (one frame back). Proper fix requires storing and following match chain through ring buffer history. Primary cause of Run5/Run10 performance gap.
- **Frame rate vs delta analysis:** Subsample simulation data at 60/30/15fps and sweep delta to characterize the tradeoff the professor identified.
- **Confusion matrix output:** Add to test harness for complete performance reporting.

### 8.3 Hardware Integration

- Bitstream generation: pending Ubuntu driver resolution on senior capstone lab machine
- Interrupt handler: stub written, needs `XIntc` BSP wiring once bitstream available
- BRAM validation: interface implemented but untested against real hardware
- End-to-end hardware test: full pipeline validation with live video input

### 8.4 Performance Characterization

- Latency and throughput: requires hardware
- Memory footprint: can be extracted from ELF now via `size debris_app.elf`
- Energy/power: requires hardware and power measurement equipment
- Scalability vs frame rate: can be done in test harness via CSV subsampling

### 8.5 Stretch Goals

- HDMI output overlay with labeled objects
- Labeled video generation

---

## 10. Summer / Fall 2026 Plan

**Immediate (Summer):**

- Resolve Ubuntu driver issue on Ryzen 9 9950X lab machine
- Install Vivado+Vitis 2025.2, generate bitstream via `create_project.tcl`
- Rebuild Vitis platform against hardware XSA, wire interrupt handler
- Validate BRAM interface against real PL centroid data
- Anthony: complete SpotCentroids Verilog and testbenches

**Fall 2026:**

- Implement rotation delta chain fix
- Run frame rate vs delta analysis
- End-to-end system validation with live video input
- Hardware performance characterization (latency, memory, compute cost, power)
- Final report

---

*Repository: github.com/AntonBold/OrbitalDebris | Progress reports: docs/*
