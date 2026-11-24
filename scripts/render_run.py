#!/usr/bin/env python3
"""Render a board run as a video: every centroid the board reported, its
label, and its track, with a per-frame summary bar on top.

    python3 scripts/render_run.py results/run6.csv -o results/run6.mp4
    python3 scripts/render_run.py results/run6.csv -o results/run6.mp4 \\
        --truth original_data/truth/SampleDataRun9.csv.gz          # mark errors
    python3 scripts/render_run.py results/run6.csv -o clip.mp4 --frames 500 800 --scale 0.5

Input: scripts/telemetry_decode.py --csv output (frame,x,y,label[,tag]).

Drawn per frame (1920x1080 field, black, plus a summary bar on top):
  star     small grey dot
  object   box in the track's colour, "#tag" next to it, and a trail of the
           track's last --trail positions; untagged object: white box
  unknown  yellow dot with "?"
With --truth (board frames aligned to the ground truth as in
classify_check.py), errors are marked in red: "FP" on a star the board called
an object, a red ring and "MISS" on a true object the board called a star.
The bar shows the frame number, counts, tracks, and (with --truth) TP/FP/FN.

Output: H.264 MP4 at --fps (default 30, the board's rate) via ffmpeg, which
must be on PATH. Standard library only otherwise.
"""

import argparse
import collections
import csv
import math
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

W, H = 1920, 1080
BAR = 60                                    # summary bar height, full scale

# ---------------------------------------------------------------------------
# 5x7 bitmap font (the characters the overlay uses)
# ---------------------------------------------------------------------------

FONT = {
    "0": "01110 10001 10011 10101 11001 10001 01110", "1": "00100 01100 00100 00100 00100 00100 01110",
    "2": "01110 10001 00001 00010 00100 01000 11111", "3": "11110 00001 00001 01110 00001 00001 11110",
    "4": "00010 00110 01010 10010 11111 00010 00010", "5": "11111 10000 11110 00001 00001 10001 01110",
    "6": "00110 01000 10000 11110 10001 10001 01110", "7": "11111 00001 00010 00100 01000 01000 01000",
    "8": "01110 10001 10001 01110 10001 10001 01110", "9": "01110 10001 10001 01111 00001 00010 01100",
    "A": "01110 10001 10001 11111 10001 10001 10001", "B": "11110 10001 10001 11110 10001 10001 11110",
    "C": "01110 10001 10000 10000 10000 10001 01110", "D": "11110 10001 10001 10001 10001 10001 11110",
    "E": "11111 10000 10000 11110 10000 10000 11111", "F": "11111 10000 10000 11110 10000 10000 10000",
    "G": "01110 10001 10000 10111 10001 10001 01111", "H": "10001 10001 10001 11111 10001 10001 10001",
    "I": "01110 00100 00100 00100 00100 00100 01110", "J": "00111 00010 00010 00010 00010 10010 01100",
    "K": "10001 10010 10100 11000 10100 10010 10001", "L": "10000 10000 10000 10000 10000 10000 11111",
    "M": "10001 11011 10101 10101 10001 10001 10001", "N": "10001 10001 11001 10101 10011 10001 10001",
    "O": "01110 10001 10001 10001 10001 10001 01110", "P": "11110 10001 10001 11110 10000 10000 10000",
    "Q": "01110 10001 10001 10001 10101 10010 01101", "R": "11110 10001 10001 11110 10100 10010 10001",
    "S": "01111 10000 10000 01110 00001 00001 11110", "T": "11111 00100 00100 00100 00100 00100 00100",
    "U": "10001 10001 10001 10001 10001 10001 01110", "V": "10001 10001 10001 10001 10001 01010 00100",
    "W": "10001 10001 10001 10101 10101 10101 01010", "X": "10001 10001 01010 00100 01010 10001 10001",
    "Y": "10001 10001 01010 00100 00100 00100 00100", "Z": "11111 00001 00010 00100 01000 10000 11111",
    "#": "01010 01010 11111 01010 11111 01010 01010", "?": "01110 10001 00001 00010 00100 00000 00100",
    ":": "00000 01100 01100 00000 01100 01100 00000", ".": "00000 00000 00000 00000 00000 01100 01100",
    ",": "00000 00000 00000 00000 01100 00100 01000", "/": "00001 00010 00010 00100 01000 01000 10000",
    "-": "00000 00000 00000 11111 00000 00000 00000", "%": "11000 11001 00010 00100 01000 10011 00011",
    "(": "00010 00100 01000 01000 01000 00100 00010", ")": "01000 00100 00010 00010 00010 00100 01000",
    "=": "00000 00000 11111 00000 11111 00000 00000", " ": "00000 00000 00000 00000 00000 00000 00000",
}
GLYPH = {c: [[ch == "1" for ch in row] for row in rows.split()] for c, rows in FONT.items()}

PALETTE = [(255, 80, 80), (80, 200, 255), (120, 255, 120), (255, 170, 40), (200, 120, 255),
           (255, 110, 200), (60, 230, 200), (230, 230, 80), (150, 180, 255), (255, 140, 120)]
GREY, WHITE, YELLOW, RED = (150, 150, 150), (255, 255, 255), (255, 230, 0), (255, 40, 40)


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.buf = bytearray(w * h * 3)

    def px(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            i = (y * self.w + x) * 3
            self.buf[i:i + 3] = bytes(c)

    def rect(self, x0, y0, x1, y1, c):
        """Filled rectangle, clipped."""
        x0, x1 = max(x0, 0), min(x1, self.w)
        row = bytes(c) * max(x1 - x0, 0)
        for y in range(max(y0, 0), min(y1, self.h)):
            i = (y * self.w + x0) * 3
            self.buf[i:i + len(row)] = row

    def box(self, cx, cy, r, c, t=1):
        self.rect(cx - r, cy - r, cx + r + 1, cy - r + t, c)
        self.rect(cx - r, cy + r - t + 1, cx + r + 1, cy + r + 1, c)
        self.rect(cx - r, cy - r, cx - r + t, cy + r + 1, c)
        self.rect(cx + r - t + 1, cy - r, cx + r + 1, cy + r + 1, c)

    def ring(self, cx, cy, r, c):
        for k in range(64):
            a = 2 * math.pi * k / 64
            self.px(int(cx + r * math.cos(a)), int(cy + r * math.sin(a)), c)

    def text(self, x, y, s, c, scale=2):
        for ch in s.upper():
            g = GLYPH.get(ch, GLYPH["?"])
            for gy, row in enumerate(g):
                for gx, on in enumerate(row):
                    if on:
                        self.rect(x + gx * scale, y + gy * scale, x + (gx + 1) * scale, y + (gy + 1) * scale, c)
            x += 6 * scale


def load_board(path):
    frames = collections.OrderedDict()
    with open(path) as f:
        for r in csv.reader(f):
            frames.setdefault(int(r[0]), []).append(
                (float(r[1]), float(r[2]), int(r[3]), int(r[4]) if len(r) > 4 else -1))
    return frames


def truth_flags(board, truth_path):
    """{board frame: [flag per centroid]} with 'tp','fp','fn','tn' or None, and
    {board frame: [(x, y)]} of true objects the board didn't report."""
    from classify_check import load, align
    b4 = collections.OrderedDict((k, [(x, y, l) for x, y, l, _ in v]) for k, v in board.items())
    truth = load(truth_path)
    aligned = align(b4, truth)
    flags = {}
    for bf, (tf, labels) in aligned.items():
        out = []
        for (x, y, lab, _), t in zip(board[bf], labels):
            if t is None:
                out.append(None)
            elif t == 1:
                out.append("tp" if lab == 1 else "fn")
            else:
                out.append("fp" if lab == 1 else "tn")
        flags[bf] = out
    return flags


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("board", help="board CSV (frame,x,y,label[,tag])")
    ap.add_argument("-o", "--out", required=True, help="output .mp4")
    ap.add_argument("--truth", help="ground truth CSV(.gz) to mark misclassifications")
    ap.add_argument("--frames", type=int, nargs=2, metavar=("FIRST", "LAST"), help="board frame range")
    ap.add_argument("--scale", type=float, default=1.0, help="output size factor (0.5 = 960x540 field)")
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--trail", type=int, default=30, help="track trail length in frames (0 = none)")
    a = ap.parse_args()

    board = load_board(a.board)
    if a.frames:
        board = collections.OrderedDict((k, v) for k, v in board.items() if a.frames[0] <= k <= a.frames[1])
    if not board:
        sys.exit("no frames to render")
    flags = truth_flags(board, a.truth) if a.truth else {}

    s = a.scale
    fw, fh = int(W * s) // 2 * 2, int(H * s) // 2 * 2
    bar = max(int(BAR * s) // 2 * 2, 24)
    cw, ch = fw, fh + bar
    ts = max(1, round(2 * s))                     # text scale
    r_obj = max(3, round(10 * s))

    ff = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
                           "-s", f"{cw}x{ch}", "-r", str(a.fps), "-i", "-",
                           "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", a.out],
                          stdin=subprocess.PIPE)
    trails = collections.defaultdict(collections.deque)      # tag -> recent (x, y)
    totals = collections.Counter()
    for n, (bf, cents) in enumerate(board.items()):
        cv = Canvas(cw, ch)
        P = lambda x, y: (int(x * s), int(y * s) + bar)
        fl = flags.get(bf, [None] * len(cents))

        # trails first, under the markers
        seen = set()
        for x, y, lab, tag in cents:
            if tag >= 0:
                seen.add(tag)
                trails[tag].append((x, y))
                while len(trails[tag]) > max(a.trail, 1):
                    trails[tag].popleft()
        for tag in list(trails):
            if tag not in seen:
                del trails[tag]
            elif a.trail:
                col = PALETTE[tag % len(PALETTE)]
                for tx, ty in list(trails[tag])[:-1]:
                    cx, cy = P(tx, ty)
                    cv.rect(cx - 1, cy - 1, cx + 1, cy + 1, col)

        n_obj = n_star = n_unk = 0
        for (x, y, lab, tag), f in zip(cents, fl):
            cx, cy = P(x, y)
            if lab == 1:
                n_obj += 1
                col = PALETTE[tag % len(PALETTE)] if tag >= 0 else WHITE
                cv.box(cx, cy, r_obj, col, max(1, round(2 * s)))
                cv.text(cx + r_obj + 3, cy - r_obj, f"#{tag}" if tag >= 0 else "OBJ", col, ts)
                if f == "fp":
                    cv.text(cx + r_obj + 3, cy - r_obj + 9 * ts, "FP", RED, ts)
            elif lab == 0:
                n_star += 1
                cv.rect(cx - 1, cy - 1, cx + 2, cy + 2, GREY)
                if f == "fn":
                    cv.ring(cx, cy, r_obj + 2, RED)
                    cv.text(cx + r_obj + 4, cy - r_obj, "MISS", RED, ts)
            else:
                n_unk += 1
                cv.rect(cx - 1, cy - 1, cx + 2, cy + 2, YELLOW)
                cv.text(cx + 4, cy - 4 * ts, "?", YELLOW, ts)
            if f:
                totals[f] += 1

        # summary bar
        cv.rect(0, 0, cw, bar, (25, 25, 40))
        tracks = sorted({t for *_, t in cents if t >= 0})
        line1 = (f"FRAME {bf}   OBJECTS {n_obj}   STARS {n_star}   UNKNOWN {n_unk}   "
                 f"TRACKS {len(tracks)}: " + " ".join(f"#{t}" for t in tracks[:12]) + (" ..." if len(tracks) > 12 else ""))
        cv.text(8, max(2, bar // 2 - 9 * ts), line1, WHITE, ts)
        if flags:
            c = collections.Counter(x for x in fl if x)
            pos = totals["tp"] + totals["fn"]
            neg = totals["tn"] + totals["fp"]
            line2 = (f"THIS FRAME TP {c['tp']} FP {c['fp']} FN {c['fn']}    "
                     f"SO FAR TPR {totals['tp'] / max(pos, 1):.3f} TNR {totals['tn'] / max(neg, 1):.3f}")
            cv.text(8, bar // 2 + ts, line2, (200, 200, 200), ts)

        ff.stdin.write(cv.buf)
        if n % 300 == 0:
            print(f"  frame {n + 1}/{len(board)}", file=sys.stderr)
    ff.stdin.close()
    if ff.wait():
        sys.exit("ffmpeg failed")
    print(f"wrote {a.out}: {len(board)} frames, {cw}x{ch} at {a.fps} fps")


if __name__ == "__main__":
    main()
