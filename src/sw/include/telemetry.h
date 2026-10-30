#ifndef TELEMETRY_H
#define TELEMETRY_H

// Binary per-frame packets over the PS UART (docs/uart-telemetry.md).

#include <stddef.h>
#include <stdint.h>
#include "centroid.h"

#define TELEMETRY_BAUD          921600u

#define TELEMETRY_SYNC0         0xA5u
#define TELEMETRY_SYNC1         0x5Au
#define TELEMETRY_VERSION       1u
#define TELEMETRY_TYPE_FRAME    1u

#define TELEMETRY_HEADER_BYTES  6       // sync, version, type, length
#define TELEMETRY_FRAME_FIXED   10      // frame_number, frames_skipped, count
#define TELEMETRY_CENTROID_BYTES 7      // x, y, area, label
#define TELEMETRY_CRC_BYTES     2
#define TELEMETRY_MAX_PACKET    (TELEMETRY_HEADER_BYTES + TELEMETRY_FRAME_FIXED + \
                                 TELEMETRY_CENTROID_BYTES * MAX_CENTROIDS + TELEMETRY_CRC_BYTES)

// Switch UART0 (stdout) to TELEMETRY_BAUD. Call before the first print.
// Returns 0 on success; on failure the UART keeps its boot baud rate.
int telemetry_uart_init(void);

// Build a frame packet into buf (at least TELEMETRY_MAX_PACKET bytes).
// labels must have one entry per centroid. Returns the packet length.
size_t telemetry_encode_frame(const CentroidFrame *frame, const LabelSet *labels,
                              uint32_t frames_skipped, uint8_t *buf);

// Encode and send a frame packet on UART0 (blocking).
void telemetry_send_frame(const CentroidFrame *frame, const LabelSet *labels,
                          uint32_t frames_skipped);

// CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF)
uint16_t telemetry_crc16(const uint8_t *data, size_t len);

#endif // TELEMETRY_H
