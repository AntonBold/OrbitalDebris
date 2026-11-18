#!/usr/bin/env python3
"""Check the board's star/object labels against the advisor's ground truth.

    python3 scripts/classify_check.py results/run2.csv original_data/truth/SampleDataRun9.csv.gz

1. Align: each board frame is matched to the truth frame whose spots it lands
   on (board pixel = round(truth) - 1: MATLAB is 1-indexed).
2. Score: every board centroid takes the label of the truth spot it matched.
   Board labels are scored with c_exporting.m's formulas (per-frame TPR, TNR,
   unknown rate, averaged) and a pooled confusion table.
3. Host replay (scripts/classify_replay.c, compiled against src/sw/ with cc):
   a. the board's own centroids through the classifier: should reproduce the
      board's labels exactly (same code, same config as main.c). A mismatch is
      an implementation/platform difference.
   c. truth spots (sub-pixel), the frames the board saw: algorithm baseline
      on the board's frame sampling.
   d. c with the spots rounded to the board's integer pixels: what rendering
      the video to whole pixels costs.
   e. truth spots, every frame (60 fps): the algorithm as the advisor ran it.

The first --skip frames of each piece are left out of every score (classifier
memory filling up). Pieces break where the board frame number jumps (restart)
or the aligned truth frame jumps by more than WRAP (mpv loop wrap). Standard library
only, plus a C compiler for step 3 (--no-replay to skip it).
"""

import argparse
import collections
import csv
import gzip
import math
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SW = os.path.join(ROOT, "src", "sw")
MATCH_PX = 1.0          # board centroid to truth spot, after the -1 offset
WRAP = 30               # truth frame jump that counts as a discontinuity


def load(path):
    rows = collections.OrderedDict()
    op = gzip.open if path.endswith(".gz") else open
    with op(path, "rt") as f:
        for r in csv.reader(f):
            rows.setdefault(int(r[0]), []).append((float(r[1]), float(r[2]), int(r[3])))
    return rows


# ---------------------------------------------------------------------------
# Alignment
# ---------------------------------------------------------------------------

def align(board, truth):
    """board frame -> (truth frame, [truth label per board centroid or None])"""
    index = collections.defaultdict(set)
    for tf, spots in truth.items():
        for x, y, _ in spots:
            index[(round(x) - 1, round(y) - 1)].add(tf)
    out = {}
    for bf, cents in board.items():
        votes = collections.Counter()
        for x, y, _ in cents:
            for tf in index.get((round(x), round(y)), ()):
                votes[tf] += 1
        best = None
        for tf, _ in votes.most_common(5):              # slow motion: neighbours tie
            labels, err = match(cents, truth[tf])
            key = (sum(l is not None for l in labels), -err)
            if best is None or key > best[0]:
                best = (key, tf, labels)
        out[bf] = (best[1], best[2]) if best else (None, [None] * len(cents))
    return out


def match(cents, spots):
    """Nearest truth spot within MATCH_PX for each board centroid."""
    labels, err = [], 0.0
    for x, y, _ in cents:
        d, lab = min(((math.hypot(sx - 1 - x, sy - 1 - y), l) for sx, sy, l in spots), default=(1e9, None))
        if d <= MATCH_PX:
            labels.append(lab)
            err += d
        else:
            labels.append(None)
    return labels, err


def segments(board, aligned):
    """runs: board frames split where the board frame number jumps (the PS
    classifier memory starts over). pieces: runs split again where the truth
    frame jumps by more than WRAP (mpv loop wrap). Memory carries over a
    piece boundary on the board, but the motion doesn't."""
    runs, pieces, prev = [], [], None
    for bf in board:
        tf = aligned[bf][0]
        if prev is None or bf != prev[0] + 1:
            runs.append([])
            pieces.append([])
        elif tf is None or prev[1] is None or abs(tf - prev[1]) > WRAP:
            pieces.append([])
        runs[-1].append(bf)
        pieces[-1].append(bf)
        prev = (bf, tf)
    return runs, pieces


# ---------------------------------------------------------------------------
# Scoring
# ---------------------------------------------------------------------------

class Score:
    def __init__(self):
        self.conf = collections.Counter()     # (truth, pred)
        self.tpr, self.tnr, self.unk = [], [], []
        self.frames = 0

    def add(self, preds, truths):
        pairs = [(t, p) for p, t in zip(preds, truths) if t is not None]
        if not pairs:
            return
        self.frames += 1
        self.conf.update(pairs)
        pos = [p for t, p in pairs if t == 1]
        neg = [p for t, p in pairs if t == 0]
        self.tpr.append(sum(p == 1 for p in pos) / len(pos) if pos else 1.0)
        if neg:
            self.tnr.append(sum(p == 0 for p in neg) / len(neg))
        self.unk.append(sum(p == -1 for _, p in pairs) / len(pairs))

    def report(self, name):
        mean = lambda v: sum(v) / len(v) if v else float("nan")
        c = self.conf
        print(f"{name}: {self.frames} frames, {sum(c.values())} spots")
        print(f"  TPR {mean(self.tpr):.4f}  TNR {mean(self.tnr):.4f}  UNK {mean(self.unk):.4f}   (c_exporting.m: per-frame mean)")
        print("  %12s %8s %8s %8s" % ("truth \\ pred", "object", "star", "unknown"))
        for t, n in ((1, "object"), (0, "star")):
            print(f"  {n:>12} {c[(t, 1)]:>8} {c[(t, 0)]:>8} {c[(t, -1)]:>8}")


def scored_frames(segs, skip):
    return [bf for s in segs for bf in s[skip:]]


# ---------------------------------------------------------------------------
# Host replay
# ---------------------------------------------------------------------------

def build(tmp):
    exe = os.path.join(tmp, "classify_replay")
    srcs = [os.path.join(HERE, "classify_replay.c")] + [os.path.join(SW, f) for f in
                                                         ("classify.c", "hungarian.c", "cost_matrix.c", "geometry.c")]
    cc = os.environ.get("CC", "cc")
    subprocess.run([cc, "-O2", "-I", os.path.join(SW, "include"), "-o", exe] + srcs + ["-lm"], check=True)
    return exe


def replay(exe, tmp, frames):
    """frames: [(id, [(x, y)])], ids consecutive within a segment. -> {id: [label]}"""
    path = os.path.join(tmp, "in.csv")
    with open(path, "w") as f:
        for fid, pts in frames:
            for x, y in pts:
                f.write(f"{fid},{x:.6f},{y:.6f}\n")
    out = subprocess.run([exe, path], check=True, capture_output=True, text=True).stdout
    labels = collections.defaultdict(list)
    for line in out.split():
        fid, _, lab = map(int, line.split(","))
        labels[fid].append(lab)
    return labels


def renumber(segs):
    """Give each segment its own consecutive id range with a gap between."""
    ids, base = [], 0
    for s in segs:
        ids.append(list(range(base, base + len(s))))
        base += len(s) + 2
    return ids


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("board", help="board CSV (scripts/telemetry_decode.py --csv)")
    ap.add_argument("truth", help="original_data/truth/SampleDataRun<N>.csv(.gz)")
    ap.add_argument("--skip", type=int, default=10, help="frames left out at the start of each segment")
    ap.add_argument("--no-replay", action="store_true")
    a = ap.parse_args()

    board, truth = load(a.board), load(a.truth)
    aligned = align(board, truth)
    runs, pieces = segments(board, aligned)

    # -- alignment summary
    nb = sum(len(c) for c in board.values())
    unmatched = sum(l is None for _, ls in aligned.values() for l in ls)
    steps = collections.Counter(aligned[p[i + 1]][0] - aligned[p[i]][0] for p in pieces for i in range(len(p) - 1))
    missed = sum(len(truth[tf]) - sum(l is not None for l in ls) for tf, ls in aligned.values() if tf is not None)
    print(f"board: {len(board)} frames, {nb} centroids; {unmatched} with no truth spot within {MATCH_PX} px; "
          f"{missed} truth spots not reported")
    print("pieces: " + ", ".join(f"board {p[0]}..{p[-1]} = truth {aligned[p[0]][0]}..{aligned[p[-1]][0]}" for p in pieces))
    print(f"truth frames per board frame: {dict(sorted(steps.items()))}")
    print()

    keep = set(scored_frames(pieces, a.skip))
    s = Score()
    for bf in board:
        if bf in keep:
            s.add([c[2] for c in board[bf]], aligned[bf][1])
    s.report("BOARD")

    if a.no_replay:
        return

    with tempfile.TemporaryDirectory() as tmp:
        exe = build(tmp)

        # a: the board's own centroids, memory continuous within a run
        idmap = {bf: i for run, rid in zip(runs, renumber(runs)) for bf, i in zip(run, rid)}
        frames = [(idmap[bf], [(c[0], c[1]) for c in board[bf]]) for bf in board]
        for name in ("HOST a: board centroids",):
            lab = replay(exe, tmp, frames)
            sc, same, total = Score(), 0, 0
            for bf in board:
                hl = lab[idmap[bf]]
                total += len(hl)
                same += sum(h == c[2] for h, c in zip(hl, board[bf]))
                if bf in keep:
                    sc.add(hl, aligned[bf][1])
            print()
            sc.report(name)
            print(f"  labels identical to the board's (all frames): {same}/{total}")

        # c/d/e: truth spots per piece, memory restarted per piece
        def truth_run(name, seqs, pos):
            frames, scored = [], []
            for seq, sid in zip(seqs, renumber(seqs)):
                for k, (tf, i) in enumerate(zip(seq, sid)):
                    frames.append((i, [pos(x, y) for x, y, _ in truth[tf]]))
                    if k >= a.skip:
                        scored.append((i, tf))
            lab = replay(exe, tmp, frames)
            sc = Score()
            for i, tf in scored:
                sc.add(lab[i], [l for _, _, l in truth[tf]])
            print()
            sc.report(name)

        saw = [[aligned[bf][0] for bf in p] for p in pieces]
        every = [list(range(min(q), max(q) + 1)) for q in saw]
        exact = lambda x, y: (x, y)
        pixel = lambda x, y: (round(x) - 1, round(y) - 1)
        truth_run("HOST c: truth spots, frames the board saw", saw, exact)
        truth_run("HOST d: truth spots rounded to the board's pixels, frames the board saw", saw, pixel)
        truth_run("HOST e: truth spots, every frame (60 fps)", every, exact)


if __name__ == "__main__":
    main()
