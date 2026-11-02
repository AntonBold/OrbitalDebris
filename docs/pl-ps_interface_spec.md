# PL-PS Interface Specification

## Orbital Debris Tracker — Centroid Handoff

**Version:** 0.3  
**Authors:** Adam Welsh 
**Status:** Draft

---

## Overview

The PL (`cca_top`) computes per-object sums from each video frame and writes them to a shared BRAM. Once a full frame has been written, the PL pulses its interrupt line. An AXI Interrupt Controller latches that pulse and interrupts the PS. The PS acknowledges the interrupt, reads the newest frame, divides the sums into centroids, runs tracking and classification, and waits for the next interrupt.

Three frames are held in BRAM at all times. The PL overwrites the oldest one with each new frame.

---

## Video Parameters

| Parameter               | Value          |
| ----------------------- | -------------- |
| Resolution              | 1920 x 1080    |
| Frame rate              | 60 fps         |
| Coordinates             | 0-based integer pixels; the PL reports sums, the PS divides |
| Max centroids per frame | 256            |

---

## Centroid Word Format

Each centroid is stored as 2 **32-bit words**:

```
Word 1
Bit 31-0
[ X sum (32 bits)                                   ]
Word 2
Bits 31-10                          Bits 9-1      Bit 0
[ Y sum (22 bits)                 ][pixel count][valid]
```

| Word  | Bits  | Field     | Description                         |
| ----- | ----- | --------  | ----------------------------------- |
|   1   | 31:0  | X sum     | Sum of the object's pixel x coordinates |
|   2   | 31:10 | Y sum     | Sum of the object's pixel y coordinates, 22-bit |
|   2   | 9:1   | \# pixels | Object area in pixels, 9-bit (max 511) |
|   2   |  0    | Valid     | 1 = valid centroid                  |

The PS computes the centroid as `x = X_sum / area`, `y = Y_sum / area`.

Objects are expected to be well under 511 pixels. At that size the Y sum is at
most 511 × 1079 = 551,369 and the X sum at most 511 × 1919 = 980,609, so both
fit the fields easily and are exact in a 32-bit float (below 2²⁴).
For larger objects, see Limits.

---

## BRAM Layout

Total BRAM size: **3 frames × (4 byte header + 256 centroids × 2 words × 4 bytes) = 6156 bytes = 0x180C** (~6 KB)

Each frame occupies a fixed 513-word block:

```
Offset 0x000        Frame slot 0 header       (1 word)
Offset 0x004        Frame slot 0 centroid 0   (2 words)
Offset 0x00C        Frame slot 0 centroid 1   (2 words)
...
Offset 0x7FC        Frame slot 0 centroid 255 (2 words)

Offset 0x804        Frame slot 1 header       (1 word)
Offset 0x808        Frame slot 1 centroid 0   (2 words)
...
Offset 0x1000       Frame slot 1 centroid 255 (2 words)

Offset 0x1008       Frame slot 2 header       (1 word)
Offset 0x100C       Frame slot 2 centroid 0   (2 words)
...
Offset 0x1804       Frame slot 2 centroid 255 (2 words)
```

Frame block size: `513 × 4 = 2052 bytes = 0x804`

### Frame Header Word

```
Bits 31:9   — Frame number (23-bit). 1 for the first frame after PL reset, +1 per frame.
Bits 8:0    — Centroid count (0–256). 0 is a valid, empty frame (no objects found).
```

The PS reads the header first to know how many centroid word pairs to read.
Centroids are stored in ascending order of each object's first pixel in raster
order (top to bottom, left to right).

### Frame Slot Selection

The PL writes frames round-robin starting at slot 0 after reset, so **frame
*n* is in slot (*n* − 1) mod 3**.

The PS reads the newest frame: it scans the three headers and takes the
highest frame number. It cross-checks that slot against the round-robin
order. A frame number more than one past the last frame read means the PS
fell behind, and those frames were skipped.

### How long a frame stays readable

The PL only rewrites a slot when it dumps frame *n* + 3, which starts after
frame *n* + 2's header is written. That gives the PS about two frame times
(~33 ms at 60 fps) to copy frame *n* out after its interrupt. The PS copies the
slot first, then checks that no header has reached *n* + 2. If one has, it
discards the copy (`BRAM_TORN_READ`) and reads the newest frame instead.

---

## Interrupt Protocol

The PL (`cca_top.o_interrupt`) drives a **single-cycle, active-high pulse**
after:

1. All centroid words for the frame have been written to BRAM
2. The frame header has been written (**the header is always written last**)

The pulse goes into an **AXI Interrupt Controller** (`axi_intc`) clocked by
the same PL clock as `cca_top`. With its input configured as rising-edge
sensitive, the controller samples on that clock, so it cannot miss a
one-cycle pulse. It latches the event and holds a level interrupt to the PS
GIC until software acknowledges it.

| Step | Who | Action |
| ---- | --- | ------ |
| 1 | PL | writes centroids, then the header, then pulses `o_interrupt` for 1 cycle |
| 2 | `axi_intc` | latches the rising edge, raises its `irq` output to the GIC |
| 3 | PS | the `axi_intc` driver's dispatcher (`XIntc_InterruptHandler`, called by the GIC) acknowledges the edge input and calls the frame ISR, which increments a frame-interrupt counter |
| 4 | PS main loop | reads the newest frame from BRAM (see Frame Slot Selection) |

**Nothing is cleared in the PL.** `cca_top` has no interrupt status register
and needs no acknowledgement. The acknowledge in step 3 clears the latch in
`axi_intc`, and the driver does it, not application code. If a second frame finishes before the PS acknowledges, the two
edges merge into one interrupt. The frame numbers show the skip, and the PS
still reads the newest frame.

---

## Reset

- A PL reset restarts the frame number at 1 and the slot at 0. The PL does
  **not** clear the BRAM.
- System reset restarts the PS too. Before releasing the PL from reset, PS
  boot code zeroes the three header words, so a header of 0 means "no frame
  yet" and stale frames from before the reset are never read.
- After the PL leaves reset it needs `NUM_LABELS` (1024) idle cycles before
  the first pixel (see `docs/hdmi-cca_interface.md`, Frame Timing).

---

## Vivado Block Design Requirements

| Component                 | Purpose                         |
| ------------------------- | ------------------------------- |
| Zynq UltraScale+ MPSoC IP | PS configuration                |
| AXI BRAM Controller       | PS read access to centroid BRAM |
| Block Memory Generator    | The shared BRAM                 |
| AXI Interrupt Controller  | Latches `cca_top.o_interrupt`, interrupts the PS GIC |
| AXI GPIO (1-bit output)   | Frame trigger: PS-driven `pattern_gen` enable (see Frame Trigger) |

The BRAM controller should be configured in **Simple** mode (not ECC).  
BRAM base address: `0xA000_0000`  
Interrupt controller address: `0xA001_0000`  
Frame trigger (AXI GPIO) address: `0xA002_0000`

AXI Interrupt Controller settings:

| Setting | Value | Why |
| ------- | ----- | --- |
| Interrupt input type | Edge, rising | `o_interrupt` is a 1-cycle pulse |
| Input synchronization | Synchronous to `s_axi_aclk` | `cca_top` and `axi_intc` share the PL clock |
| Output (`irq`) | Level, active high, single output | Matches the GIC's default for PL interrupts |
| `irq` connected to | `zynq_ultra_ps_e_0/pl_ps_irq0` | |

> The block design currently wires `o_interrupt` straight to `pl_ps_irq0`
> through an `xlconcat`. It needs the `axi_intc` inserted between them.

### Frame Trigger

Bring-up only: it drives the test-pattern generator, which the HDMI input
replaces. `axi_gpio_0` bit 0 (`GPIO_DATA`, offset `0x0`, reset value 0) is
ORed with the debounced button pulse into `pattern_gen.i_enable`.

| Write | Effect |
| ----- | ------ |
| `1` (held) | `pattern_gen` free-runs: frame, vertical blanking (45 lines × 2200 clocks = 99,000 cycles), frame, ... — about 46 frames/s at 100 MHz |
| `0` | stops after the current frame and its blanking; the button still sends one frame per press |

`i_enable` is only sampled while the generator is idle and at the end of a
blanking period, so a button press during the ~1 ms of blanking after a frame
is ignored. `src/sw/main.c` writes 0 at start-up and 1 once the interrupt is
enabled (`FREE_RUN`).

---

## PS Software Requirements

At boot:

1. Zero the three header words (`0xA000_0000`, `+0x804`, `+0x1008`): `bram_clear_headers()`
2. Initialize the GIC and `axi_intc` and enable the interrupt: `interrupt_init()`
   (falls back to polling the headers if it fails)

On interrupt (`src/sw/interrupt.c`):

1. GIC → `XIntc_InterruptHandler`, which acknowledges the `axi_intc` input
2. Frame ISR increments `frame_irq_count` (no BRAM access in the ISR). A counter
   rather than a flag, so the main loop never loses an interrupt that lands
   between reading and clearing a flag.

In the main loop, when `frame_irq_count` has changed since the last pass:

1. Call `bram_read_frame()` (`src/sw/bram_io.c`):
   - scans the three headers for the newest frame number
   - copies that slot, then checks the PL hasn't caught up with it
   - divides each valid centroid's sums by its area
2. Pass the centroid frame to classification and tracking
3. Return to waiting

`bram_read_frame()` returns the frame number, or `BRAM_NO_NEW_FRAME` /
`BRAM_TORN_READ`. `bram_get_stats()` counts frames read and skipped, slot
mismatches, torn reads, and dropped entries.

### C Types

Raw BRAM words (what the PL writes):

```c
// Header:   [31:9] frame number   [8:0] centroid count
// Word 1:   [31:0] X sum
// Word 2:   [31:10] Y sum   [9:1] area   [0] valid
```

After `bram_read_frame()` (`src/sw/include/centroid.h`):

```c
typedef struct {
    float x;            // X_sum / area
    float y;            // Y_sum / area
    uint16_t area;      // pixels
} Centroid;

typedef struct {
    Centroid centroids[MAX_CENTROIDS];
    int count;
    uint32_t frame_number;
} CentroidFrame;
```

---

## Limits (current RTL)

These are tested as expected-fail cases in `src/tb/cca_directed_tb`:

| Condition | What the PL does | What `bram_read_frame()` does |
| --------- | ---------------- | ----------------------------- |
| More than 256 objects | writes past the slot into the next one, and the count can exceed 256 | clamps the count to 256 and counts it in `bad_counts` |
| Object area ≥ 512 | area field keeps only the low 9 bits | drops entries whose area field is 0 (`zero_area_entries`); other truncated areas give wrong centroids |
| Frame number reaches 0x7FFFFF (~39 h at 60 fps) | saturates | sees no newer frame and stops returning frames |
| More than 1023 labels in one frame | label counter wraps to the background label; objects are lost | — |

---

## Open Questions

- [x] BRAM base address: `0xA000_0000`
- [ ] Confirm the GIC interrupt ID for `pl_ps_irq0[0]` in `xparameters.h` (expected 121 on Zynq UltraScale+)
- [ ] Frame number at 0x7FFFFF: wrap (needs a wrap-aware newest-frame comparison) or saturate
- [ ] Confirm 256 max centroids is sufficient for worst-case video
- [x] PS still busy when the next interrupt arrives: the edges merge in `axi_intc`; the PS reads the newest frame and counts the skip

---

## Revision History

| Version | Date       | Notes         |
| ------- | ---------- | ------------- |
| 0.1     | 2026-03-24 | Initial draft |
| 0.2     | 2026-10-28 | Match the RTL: 1-cycle pulse latched by an edge-sensitive `axi_intc` (nothing cleared in the PL), frame-number/slot rules, reset, read window, `bram_read_frame()` behaviour, Limits |
| 0.3     | 2026-10-30 | Frame trigger AXI GPIO at `0xA002_0000` (free-running test pattern without the button) |
