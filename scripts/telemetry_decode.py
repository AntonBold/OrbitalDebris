#!/usr/bin/env python3
"""Decode the PS's binary UART telemetry (docs/uart-telemetry.md).

Read live from the board (configures the serial port itself, no pyserial):
    python3 scripts/telemetry_decode.py /dev/ttyUSB1
    python3 scripts/telemetry_decode.py /dev/ttyUSB1 --csv run1.csv

Or from a capture (raw bytes, e.g. `cat /dev/ttyUSB1 > capture.bin` after
`stty -F /dev/ttyUSB1 921600 raw -echo`):
    python3 scripts/telemetry_decode.py capture.bin --csv run1.csv

Text the PS prints with xil_printf (banner, debug lines) is shown prefixed
with "| ". --csv writes frame,x,y,label rows, the format of the ground-truth
CSVs read by src/sw/test_harness.c. Ctrl-C prints a summary.

    python3 scripts/telemetry_decode.py --selftest
"""

import argparse
import os
import stat
import struct
import sys

SYNC = b"\xA5\x5A"
VERSION = 1
TYPE_FRAME = 1
HEADER_BYTES = 6
FRAME_FIXED = 10
CENTROID_BYTES = 7
CRC_BYTES = 2
MAX_CENTROIDS = 256
MAX_PAYLOAD = FRAME_FIXED + CENTROID_BYTES * MAX_CENTROIDS
LABELS = {1: "object", 0: "star", -1: "unknown"}


def crc16(data):
    """CRC-16/CCITT-FALSE: poly 0x1021, init 0xFFFF, no reflection."""
    crc = 0xFFFF
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def decode_frame(payload):
    frame_number, frames_skipped, count = struct.unpack_from("<IIH", payload, 0)
    if len(payload) != FRAME_FIXED + CENTROID_BYTES * count:
        return None
    centroids = []
    for i in range(count):
        x, y, area, label = struct.unpack_from("<HHHb", payload, FRAME_FIXED + CENTROID_BYTES * i)
        centroids.append({"x": x / 32.0, "y": y / 32.0, "area": area, "label": label})
    return {"frame": frame_number, "frames_skipped": frames_skipped, "centroids": centroids}


class Decoder:
    """Feed raw bytes; get ("frame", dict) and ("text", str) events back.

    Bytes only count as a packet when the sync word, header and CRC all
    check out; anything else is treated as text, so a stray 0xA5 0x5A in a
    printed line costs at most a short delay, never a bogus frame.
    """

    def __init__(self):
        self.buf = bytearray()
        self.line = bytearray()
        self.packets = 0
        self.crc_errors = 0
        self.bad_headers = 0

    def _text(self, data, events):
        for b in data:
            if b == 0x0A:
                events.append(("text", self.line.decode("ascii", "replace")))
                self.line.clear()
            elif 0x20 <= b < 0x7F or b == 0x09:
                self.line.append(b)

    def feed(self, data):
        self.buf += data
        events = []
        while True:
            i = self.buf.find(SYNC)
            if i < 0:
                # keep a trailing 0xA5: it may be the start of the next sync
                keep = 1 if self.buf[-1:] == SYNC[:1] else 0
                self._text(self.buf[:len(self.buf) - keep], events)
                del self.buf[:len(self.buf) - keep]
                return events
            self._text(self.buf[:i], events)
            del self.buf[:i]

            if len(self.buf) < HEADER_BYTES:
                return events
            version, ptype, length = struct.unpack_from("<BBH", self.buf, 2)
            if version != VERSION or ptype != TYPE_FRAME or length < FRAME_FIXED or length > MAX_PAYLOAD:
                self.bad_headers += 1
                del self.buf[:1]                # not a packet: resync past this byte
                continue

            total = HEADER_BYTES + length + CRC_BYTES
            if len(self.buf) < total:
                return events
            body = bytes(self.buf[2:HEADER_BYTES + length])
            (crc,) = struct.unpack_from("<H", self.buf, HEADER_BYTES + length)
            frame = decode_frame(body[4:]) if crc16(body) == crc else None
            if frame is None:
                self.crc_errors += 1
                del self.buf[:1]
                continue
            del self.buf[:total]
            # The PS prints whole lines and sends packets between them, so a
            # partial line here is the tail of a rejected packet
            self.line.clear()
            self.packets += 1
            events.append(("frame", frame))


def open_source(path, baud):
    """File descriptor for a capture file, or a tty set to raw 8N1 at baud."""
    fd = os.open(path, os.O_RDONLY | os.O_NOCTTY)
    if not stat.S_ISCHR(os.fstat(fd).st_mode):
        return fd, False
    import termios
    speed = getattr(termios, "B%d" % baud, None)
    if speed is None:
        sys.exit("this OS's termios has no B%d (use Linux, or capture to a file)" % baud)
    attrs = termios.tcgetattr(fd)
    attrs[0] = 0                                            # iflag: raw
    attrs[1] = 0                                            # oflag
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL  # 8N1, no flow control
    attrs[3] = 0                                            # lflag: no echo/canonical
    attrs[4] = attrs[5] = speed
    attrs[6][termios.VMIN] = 1
    attrs[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIFLUSH)
    return fd, True


def run(args):
    fd, live = open_source(args.source, args.baud)
    csv = open(args.csv, "w") if args.csv else None
    dec = Decoder()
    last = None
    gaps = 0
    print("reading %s%s" % (args.source, " at %d baud" % args.baud if live else ""), file=sys.stderr)
    try:
        while True:
            data = os.read(fd, 4096)
            if not data:
                break                                   # end of a capture file
            for kind, ev in dec.feed(data):
                if kind == "text":
                    if not args.quiet:
                        print("| " + ev)
                    continue
                f = ev
                if last is not None and f["frame"] != last + 1:
                    gaps += 1
                    print("!! frame %d after %d" % (f["frame"], last))
                last = f["frame"]
                if csv:
                    for c in f["centroids"]:
                        csv.write("%d,%.5f,%.5f,%d\n" % (f["frame"], c["x"], c["y"], c["label"]))
                if not args.quiet:
                    labels = [c["label"] for c in f["centroids"]]
                    print("frame %d: %d centroid(s), %d object, %d star, %d unknown, skipped so far %d"
                          % (f["frame"], len(labels), labels.count(1), labels.count(0),
                             labels.count(-1), f["frames_skipped"]))
                    if args.verbose:
                        for i, c in enumerate(f["centroids"]):
                            print("  [%d] x=%.3f y=%.3f area=%d %s"
                                  % (i, c["x"], c["y"], c["area"], LABELS.get(c["label"], c["label"])))
    except KeyboardInterrupt:
        pass
    finally:
        if csv:
            csv.close()
    print("packets %d, CRC errors %d, bad headers %d, frame-number gaps %d"
          % (dec.packets, dec.crc_errors, dec.bad_headers, gaps), file=sys.stderr)


def encode_frame(frame_number, frames_skipped, centroids):
    """Python mirror of telemetry_encode_frame(), for --selftest."""
    payload = struct.pack("<IIH", frame_number, frames_skipped, len(centroids))
    for x, y, area, label in centroids:
        payload += struct.pack("<HHHb", int(x * 32 + 0.5), int(y * 32 + 0.5), area, label)
    body = struct.pack("<BBH", VERSION, TYPE_FRAME, len(payload)) + payload
    return SYNC + body + struct.pack("<H", crc16(body))


def selftest():
    fails = []

    def check(cond, what):
        print(("PASS  " if cond else "FAIL  ") + what)
        if not cond:
            fails.append(what)

    check(crc16(b"123456789") == 0x29B1, "CRC-16/CCITT-FALSE check value 0x29B1")

    objs = [(102.0, 102.0, 25, 1), (502.0, 502.0, 25, 0), (807.0, 805.586, 87, -1)]
    p1, p2 = encode_frame(1, 0, objs), encode_frame(2, 0, objs[:1])
    noise = b"debris_app: starting\r\n" + b"\xA5\x5A\xFFjunk" + b"x\xA5\x5A\x01\x01\xFF\xFFtail\r\n"
    bad = bytearray(p2)
    bad[10] ^= 0x01                                     # corrupt one payload byte
    stream = noise + p1 + bytes(bad) + p2 + b"done\r\n"

    for chunk in (len(stream), 1, 7):                   # whole, byte by byte, odd chunks
        dec = Decoder()
        ev = []
        for i in range(0, len(stream), chunk):
            ev += dec.feed(stream[i:i + chunk])
        frames = [e for k, e in ev if k == "frame"]
        texts = [e for k, e in ev if k == "text"]
        check([f["frame"] for f in frames] == [1, 2], "chunk %d: frames 1, 2 decoded" % chunk)
        check(dec.crc_errors == 1, "chunk %d: corrupted packet rejected (CRC errors %d)" % (chunk, dec.crc_errors))
        check(texts[0] == "debris_app: starting" and texts[-1] == "done", "chunk %d: text passed through" % chunk)
        f = frames[0]["centroids"]
        check([(c["x"], c["area"], c["label"]) for c in f] == [(102.0, 25, 1), (502.0, 25, 0), (807.0, 87, -1)],
              "chunk %d: fields decoded" % chunk)
        check(abs(f[2]["y"] - 805.586) <= 1 / 64, "chunk %d: y within 1/64 px (%.5f)" % (chunk, f[2]["y"]))

    print("SELFTEST %s" % ("PASSED" if not fails else "FAILED (%d)" % len(fails)))
    return 0 if not fails else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", nargs="?", help="serial device (e.g. /dev/ttyUSB1) or capture file")
    ap.add_argument("--baud", type=int, default=921600)
    ap.add_argument("--csv", help="write frame,x,y,label rows here")
    ap.add_argument("-v", "--verbose", action="store_true", help="print every centroid")
    ap.add_argument("-q", "--quiet", action="store_true", help="only the final summary (and gaps)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        sys.exit(selftest())
    if not args.source:
        ap.error("source is required (or --selftest)")
    run(args)


if __name__ == "__main__":
    main()
