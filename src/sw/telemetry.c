#include "include/telemetry.h"

// Encoder for the UART telemetry packets (docs/uart-telemetry.md). The
// encode and CRC functions are plain C so test_telemetry.c can run them on
// the host (built with -DTELEMETRY_HOST); the UART parts need the BSP.

static void put_u16(uint8_t *p, uint16_t v)
{
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
}

static void put_u32(uint8_t *p, uint32_t v)
{
    put_u16(p, (uint16_t)v);
    put_u16(p + 2, (uint16_t)(v >> 16));
}

// Pixels -> unsigned 1/32-pixel units, rounded to nearest. Centroids are
// never negative; clamp anyway so a bad value can't wrap.
static uint16_t to_q5(float v)
{
    float q = v * 32.0f + 0.5f;
    if (q <= 0.0f)
        return 0;
    if (q >= 65535.0f)
        return 65535;
    return (uint16_t)q;
}

uint16_t telemetry_crc16(const uint8_t *data, size_t len)
{
    uint16_t crc = 0xFFFF;
    for (size_t i = 0; i < len; i++) {
        crc ^= (uint16_t)data[i] << 8;
        for (int b = 0; b < 8; b++)
            crc = (crc & 0x8000) ? (uint16_t)((crc << 1) ^ 0x1021) : (uint16_t)(crc << 1);
    }
    return crc;
}

size_t telemetry_encode_frame(const CentroidFrame *frame, const LabelSet *labels,
                              uint32_t frames_skipped, uint8_t *buf)
{
    int count = frame->count;
    if (count > MAX_CENTROIDS)
        count = MAX_CENTROIDS;
    if (count < 0)
        count = 0;

    uint16_t payload_len = (uint16_t)(TELEMETRY_FRAME_FIXED + TELEMETRY_CENTROID_BYTES * count);

    buf[0] = TELEMETRY_SYNC0;
    buf[1] = TELEMETRY_SYNC1;
    buf[2] = TELEMETRY_VERSION;
    buf[3] = TELEMETRY_TYPE_FRAME;
    put_u16(buf + 4, payload_len);

    uint8_t *p = buf + TELEMETRY_HEADER_BYTES;
    put_u32(p, frame->frame_number);
    put_u32(p + 4, frames_skipped);
    put_u16(p + 8, (uint16_t)count);
    p += TELEMETRY_FRAME_FIXED;

    for (int i = 0; i < count; i++) {
        const Centroid *c = &frame->centroids[i];
        put_u16(p, to_q5(c->x));
        put_u16(p + 2, to_q5(c->y));
        put_u16(p + 4, c->area);
        p[6] = (uint8_t)(i < labels->count ? labels->labels[i] : LABEL_UNKNOWN);
        p += TELEMETRY_CENTROID_BYTES;
    }

    // CRC over version through payload (not the sync word)
    size_t crc_len = (size_t)(p - (buf + 2));
    put_u16(p, telemetry_crc16(buf + 2, crc_len));
    return (size_t)(p - buf) + TELEMETRY_CRC_BYTES;
}

#ifndef TELEMETRY_HOST

#include "xparameters.h"
#include "xstatus.h"
#include "xuartps.h"
#include "xil_printf.h"

#ifdef SDT
#define UART_ID     STDOUT_BASEADDRESS
#else
#define UART_ID     XPAR_XUARTPS_0_DEVICE_ID
#endif

static XUartPs uart;
static uint8_t packet[TELEMETRY_MAX_PACKET];

int telemetry_uart_init(void)
{
    // Let anything already queued (e.g. FSBL output) finish at the old rate
    while (!(XUartPs_ReadReg(STDOUT_BASEADDRESS, XUARTPS_SR_OFFSET) & XUARTPS_SR_TXEMPTY))
        ;

    XUartPs_Config *cfg = XUartPs_LookupConfig(UART_ID);
    if (cfg == NULL)
        return XST_FAILURE;
    int status = XUartPs_CfgInitialize(&uart, cfg, cfg->BaseAddress);
    if (status != XST_SUCCESS)
        return status;
    return XUartPs_SetBaudRate(&uart, TELEMETRY_BAUD);
}

void telemetry_send_frame(const CentroidFrame *frame, const LabelSet *labels,
                          uint32_t frames_skipped)
{
    size_t n = telemetry_encode_frame(frame, labels, frames_skipped, packet);
    // outbyte is xil_printf's polled byte writer, so packets and text
    // can't interleave mid-byte
    for (size_t i = 0; i < n; i++)
        outbyte((char)packet[i]);
}

#endif // TELEMETRY_HOST
