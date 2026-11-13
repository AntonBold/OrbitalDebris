#!/usr/bin/env python3
"""Run one screenshot through the golden model and (optionally) compare with
the board.

    python3 scripts/golden/png_frame.py frame.png --thr 64
    python3 scripts/golden/png_frame.py frame.png --thr 64 --csv results/run1.csv --frame 91
    python3 scripts/golden/png_frame.py frame.png --thr 64 --out golden.csv

Threshold: the same integer compare as src/hdl/threshold.sv,
    2989 R + 5870 G + 1140 B >= THR * 10000 + 5000   (grey > THR)
Objects: cca_golden.label_objects (4-connected flood fill, what cca_top is
specified to do). The 8-connected count is printed too: if 4-conn gives about
twice as many objects as 8-conn, objects are being split at diagonal joins.

With --csv (scripts/telemetry_decode.py --csv output: frame,x,y,label), each
golden centroid is matched to the nearest board centroid. Board centroids
outside the image (area overflow) are ignored.

The PNG must be the exact 1920x1080 frame sent over HDMI (a full-screen
screenshot of that display). Standard library only: 8-bit, non-interlaced
RGB, RGBA, grey or grey+alpha PNGs.
"""

import argparse
import csv
import math
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cca_golden import label_objects, MAX_CENTROIDS, AREA_BITS  # noqa: E402


# ---------------------------------------------------------------------------
# PNG decode (stdlib)
# ---------------------------------------------------------------------------

def read_png(path):
    """Returns (w, h, rows), rows[y] = list of (r, g, b)."""
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path}: not a PNG")
    pos, idat, hdr = 8, [], None
    while pos < len(data):
        n, typ = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        pos += 12 + n
        if typ == b"IHDR":
            hdr = struct.unpack(">IIBBBBB", body)
        elif typ == b"IDAT":
            idat.append(body)
        elif typ == b"IEND":
            break
    w, h, depth, ctype, _, _, interlace = hdr
    chans = {0: 1, 2: 3, 4: 2, 6: 4}.get(ctype)
    if depth != 8 or chans is None or interlace:
        raise SystemExit(f"{path}: need 8-bit non-interlaced RGB/RGBA/grey "
                         f"(got depth {depth}, colour type {ctype}, interlace {interlace})")
    raw = zlib.decompress(b"".join(idat))
    bpp, stride = chans, w * chans
    rows, prev = [], bytearray(stride)
    for y in range(h):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if f == 1:
                line[i] = (line[i] + a) & 0xFF
            elif f == 2:
                line[i] = (line[i] + b) & 0xFF
            elif f == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 0xFF
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        prev = line
        if chans >= 3:
            rows.append([(line[x * chans], line[x * chans + 1], line[x * chans + 2]) for x in range(w)])
        else:
            rows.append([(line[x * chans],) * 3 for x in range(w)])
    return w, h, rows


# ---------------------------------------------------------------------------
# Threshold (matches src/hdl/threshold.sv) and 8-connected count
# ---------------------------------------------------------------------------

def binarize(rows, thr):
    lim = thr * 10000 + 5000
    return [[1 if 2989 * r + 5870 * g + 1140 * b >= lim else 0 for (r, g, b) in row]
            for row in rows]


def count_8conn(img):
    h, w = len(img), len(img[0])
    seen = [[False] * w for _ in range(h)]
    n = 0
    for y in range(h):
        for x in range(w):
            if img[y][x] and not seen[y][x]:
                n += 1
                seen[y][x] = True
                stack = [(x, y)]
                while stack:
                    cx, cy = stack.pop()
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            nx, ny = cx + dx, cy + dy
                            if 0 <= nx < w and 0 <= ny < h and img[ny][nx] and not seen[ny][nx]:
                                seen[ny][nx] = True
                                stack.append((nx, ny))
    return n


# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("png")
    ap.add_argument("--thr", type=int, required=True, help="grey level 0..255, foreground = grey > THR")
    ap.add_argument("--csv", help="board telemetry CSV (frame,x,y,label)")
    ap.add_argument("--frame", type=int, help="frame number in --csv (default: first)")
    ap.add_argument("--out", help="write golden centroids as x,y,area CSV")
    a = ap.parse_args()

    w, h, rows = read_png(a.png)
    if (w, h) != (1920, 1080):
        print(f"WARNING: image is {w}x{h}, not 1920x1080: not the frame the board sees")
    img = binarize(rows, a.thr)
    fg = sum(map(sum, img))

    objs = label_objects(img)                          # [(x_sum, y_sum, area)], raster order
    n8 = count_8conn(img)
    cents = [(xs / ar, ys / ar, ar) for xs, ys, ar in objs]
    big = [c for c in cents if c[2] >= (1 << AREA_BITS)]

    print(f"{a.png}: {w}x{h}, THR {a.thr}, {fg} foreground px")
    print(f"  objects, 4-connected: {len(objs)}   (what cca_top should report"
          f"{', capped at 256' if len(objs) > MAX_CENTROIDS else ''})")
    print(f"  objects, 8-connected: {n8}")
    if n8 and len(objs) > 1.3 * n8:
        print(f"  -> 4-conn finds {len(objs) / n8:.1f}x as many: objects split at diagonal joins")
    if big:
        print(f"  {len(big)} object(s) with area > {(1 << AREA_BITS) - 1} (board area field overflows):",
              ", ".join(f"({x:.0f},{y:.0f}) area {ar}" for x, y, ar in big))
    areas = sorted(c[2] for c in cents)
    if areas:
        print(f"  area: min {areas[0]}, median {areas[len(areas) // 2]}, max {areas[-1]}")

    if a.out:
        with open(a.out, "w", newline="") as f:
            csv.writer(f).writerows((f"{x:.5f}", f"{y:.5f}", ar) for x, y, ar in cents)
        print(f"  wrote {len(cents)} golden centroids to {a.out}")

    if a.csv:
        board = {}
        for r in csv.reader(open(a.csv)):
            board.setdefault(int(r[0]), []).append((float(r[1]), float(r[2])))
        fnum = a.frame if a.frame is not None else min(board)
        if fnum not in board:
            raise SystemExit(f"frame {fnum} not in {a.csv} (frames: {sorted(board)[:20]} ...)")
        bpts = [p for p in board[fnum] if p[0] < w and p[1] < h]
        print(f"board frame {fnum}: {len(board[fnum])} centroids ({len(board[fnum]) - len(bpts)} out of image ignored)")
        exact = near = 0
        for x, y, _ in cents[:MAX_CENTROIDS]:
            d = min((math.hypot(x - bx, y - by) for bx, by in bpts), default=1e9)
            exact += d <= 0.05
            near += d <= 2
        g = min(len(cents), MAX_CENTROIDS)
        print(f"  golden centroids with a board centroid within 0.05 px: {exact}/{g}, within 2 px: {near}/{g}")
        print("  (a different video frame than the screenshot will lower these; the counts still compare)")


if __name__ == "__main__":
    main()
