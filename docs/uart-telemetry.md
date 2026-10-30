# UART Telemetry Format

**Version:** 1
**Link:** PS UART0 (the board's USB-UART), 921600 baud, 8N1
**Encoder:** `src/sw/telemetry.c` | **Decoder:** `scripts/telemetry_decode.py`

The PS sends one binary packet per frame after classifying it. Text from
`xil_printf` (the boot banner, debug prints) shares the same UART; the
decoder passes those lines through and only treats bytes as a packet when the
sync word, header and CRC all check out.

## Packet

All multi-byte fields are little-endian (the A53's native order).

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 2 | sync | `0xA5 0x5A` |
| 2 | 1 | version | `1` |
| 3 | 1 | type | `1` = frame |
| 4 | 2 | length | payload bytes, `L` |
| 6 | L | payload | below |
| 6+L | 2 | crc | CRC-16/CCITT-FALSE over offsets 2 .. 6+L-1 (version through payload) |

CRC-16/CCITT-FALSE: polynomial `0x1021`, initial value `0xFFFF`, no bit
reflection, no final XOR. Check value: `"123456789"` gives `0x29B1`.

## Frame payload (type 1)

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 4 | frame_number | from the BRAM header (1 = first frame after PL reset) |
| 4 | 4 | frames_skipped | cumulative frames the PS fell behind on (`BramStats.frames_skipped`) |
| 8 | 2 | count | centroids in this packet, 0..256 |
| 10 | 7 x count | centroids | below |

Each centroid, 7 bytes:

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 2 | x | unsigned, units of 1/32 pixel (`x = raw / 32`) |
| 2 | 2 | y | unsigned, units of 1/32 pixel |
| 4 | 2 | area | pixels (9 bits from the PL, RTL known issue 3) |
| 6 | 1 | label | signed: `1` object, `0` star, `-1` unknown |

`L = 10 + 7 x count`. Centroids are in BRAM order, the same order as
`ClassifiedFrame.frame` / `.labels`.

1/32 pixel: 1919.97 x 32 = 61439 fits in 16 bits. The encoder rounds to
nearest, so a centroid is off by at most 1/64 pixel.

## Bandwidth

A packet is `18 + 7 x count` bytes. At 921600 baud (92,160 bytes/s) and
60 fps there are 1,536 bytes per frame, enough for 217 centroids. Past that
the PS's UART writes take longer than a frame and it falls behind, which
shows up as `frames_skipped` growing. The UART writes are blocking (polled);
an interrupt-driven TX would let processing overlap the send.

## Decoder output

`scripts/telemetry_decode.py --csv out.csv` writes one row per centroid as
`frame,x,y,label`, the same columns as the ground-truth CSVs that
`src/sw/test_harness.c` reads, so board output and ground truth can be
compared row for row.
