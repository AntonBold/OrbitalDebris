# PL-PS Interface Specification

## Orbital Debris Tracker — Centroid Handoff

**Version:** 0.1  
**Authors:** Adam Welsh 
**Status:** Draft

---

## Overview

The PL computes object centroids from each video frame and writes them to a shared BRAM. Once a full frame's centroids have been written, the PL asserts an interrupt to notify the PS. The PS reads the BRAM, runs tracking and classification algorithms, and waits for the next interrupt.

Three frames of centroid data are held in BRAM at all times. The oldest frame is overwritten when a new frame is processed.

---

## Video Parameters

| Parameter               | Value          |
| ----------------------- | -------------- |
| Resolution              | 1920 x 1080    |
| Frame rate              | 60 fps         |
| Coordinate type         | Integer pixels |
| Max centroids per frame | 256            |

---

## Centroid Word Format

Each centroid is stored as one **32-bit word**:

```
Bit 31        Bit 21  Bit 20       Bit 11  Bit 10   Bit 9-0
[ X (11 bits)       ][ Y (11 bits)       ][ valid ][ reserved ]
```

| Bits  | Field    | Description                        |
| ----- | -------- | ---------------------------------- |
| 31:21 | X        | Centroid x coordinate, 0–1919      |
| 20:10 | Y        | Centroid y coordinate, 0–1079      |
| 10    | Valid    | 1 = valid centroid, 0 = empty slot |
| 9:0   | Reserved | Set to 0                           |

X range 0–1919 fits in 11 bits (max 2047).  
Y range 0–1079 fits in 11 bits (max 2047).

---

## BRAM Layout

Total BRAM size: **3 frames × 257 words × 4 bytes = 3,084 bytes** (~3 KB)

Each frame occupies a fixed 257-word block:

```
Offset 0x000        Frame 0 header      (1 word)
Offset 0x004        Frame 0 centroid 0  (1 word)
Offset 0x008        Frame 0 centroid 1  (1 word)
...
Offset 0x400        Frame 0 centroid 255 (1 word)

Offset 0x404        Frame 1 header      (1 word)
Offset 0x408        Frame 1 centroid 0  (1 word)
...
Offset 0x808        Frame 1 centroid 255 (1 word)

Offset 0x80C        Frame 2 header      (1 word)
Offset 0x810        Frame 2 centroid 0  (1 word)
...
Offset 0xC0C        Frame 2 centroid 255 (1 word)
```

Frame block size: `257 × 4 = 1028 bytes = 0x404`

### Frame Header Word

The first word of each frame block is a header:

```
Bits 31:8   — Frame number (incrementing counter, wraps at 0xFFFFFF)
Bits 7:0    — Centroid count (number of valid centroids in this frame, 0–256)
```

The PS reads the header first to know how many centroid words to process — it does not need to scan all 256 slots.

### Frame Slot Selection

The PL writes frames in round-robin order: slot 0 → slot 1 → slot 2 → slot 0 → ...

The PS determines which slot contains the newest frame by reading the frame number from each header and taking the highest value.

---

## Interrupt Protocol

The PL asserts a single-cycle pulse on the interrupt line after:

1. All centroid words for the new frame have been written to BRAM
2. The frame header has been written

**The header must be written last** to guarantee the PS never reads a partially written frame.

The PS clears the interrupt in its interrupt service routine before reading BRAM.

---

## Vivado Block Design Requirements

| Component                 | Purpose                         |
| ------------------------- | ------------------------------- |
| Zynq UltraScale+ MPSoC IP | PS configuration                |
| AXI BRAM Controller       | PS read access to centroid BRAM |
| Block Memory Generator    | The shared BRAM                 |
| AXI Interrupt Controller  | Routes PL interrupt to PS GIC   |

The BRAM controller should be configured in **Simple** mode (not ECC).  
The BRAM base address must be agreed upon and noted here before implementation: `0xA000_0000`

Interrupt controller address: `0xA001_0000`

---

## PS Software Requirements

On interrupt:

1. Clear interrupt
2. Read all three frame headers to identify newest frame slot
3. Read `centroid_count` words from that frame's data region
4. Pass centroid array to tracking/classification algorithm
5. Return to wait state

### C Struct Definition

```c
typedef struct {
    uint16_t x;       // 0–1919
    uint16_t y;       // 0–1079
    uint8_t  valid;
} Centroid;

typedef struct {
    uint32_t frame_number;
    uint8_t  centroid_count;
    Centroid centroids[256];
} FrameBlock;
```

> Note: the packed BRAM word format and this C struct will need a simple unpack function on the PS side — x and y are not byte-aligned in the 32-bit word.

---

## Open Questions

- [ ] Confirm BRAM base address once assigned in Vivado address editor
- [ ] Confirm interrupt line number on PS GIC
- [ ] Decide whether frame_number wraps or saturates at 0xFFFFFF
- [ ] Confirm 256 max centroids is sufficient for worst-case video
- [ ] Define behavior if PS has not finished processing when next interrupt arrives (frame skip vs queue)

---

## Revision History

| Version | Date       | Notes         |
| ------- | ---------- | ------------- |
| 0.1     | 2026-03-24 | Initial draft |
