#!/usr/bin/env python3
"""Check the board's track ids (telemetry v2) against the ground truth.

    python3 scripts/board_track_check.py results/run6.csv original_data/truth/SampleDataRun9.csv.gz

The truth has labels but no object ids, so true tracks are built here: each
true object is linked to the nearest true object in the previous truth frame
(within LINK_PX; objects are a few and move slowly). Board frames are aligned
to truth frames and board centroids to truth spots as in classify_check.py.
Each pass through the video (split where the truth frame jumps back by more
than WRAP, i.e. the loop wrap) counts separately: the board rightly starts new
tracks when the video loops. Dropped board frames don't split a pass: the
tracker carries on across them.

Reported:
  per true track   share of its board observations that carry a tag, and how
                   many different board tags it got (1 = never lost or
                   swapped)
  id switches      consecutive observations of one true object, both tagged,
                   with different tags
  false tracks     board tags whose observations are mostly stars: how many,
                   and how long they last
Standard library only.
"""

import argparse
import collections
import csv
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from classify_check import load, align, MATCH_PX, WRAP  # noqa: E402

LINK_PX = 3.0


def true_tracks(truth):
    """{(truth frame, spot index): true track id} for objects."""
    ids, prev, nxt = {}, [], 0
    for tf in sorted(truth):
        cur = []
        for i, (x, y, lab) in enumerate(truth[tf]):
            if lab != 1:
                continue
            best = min(prev, key=lambda p: math.hypot(p[0] - x, p[1] - y), default=None)
            if best is not None and math.hypot(best[0] - x, best[1] - y) <= LINK_PX:
                tid = best[2]
            else:
                tid, nxt = nxt, nxt + 1
            ids[(tf, i)] = tid
            cur.append((x, y, tid))
        prev = cur
    return ids


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("board", help="board CSV with tags (telemetry_decode.py --csv, telemetry v2)")
    ap.add_argument("truth", help="original_data/truth/SampleDataRun<N>.csv(.gz)")
    a = ap.parse_args()

    board, truth = load(a.board), load(a.truth)
    tags = collections.defaultdict(list)
    with open(a.board) as f:
        for r in csv.reader(f):
            tags[int(r[0])].append(int(r[4]) if len(r) > 4 else -1)
    if all(t == -1 for v in tags.values() for t in v):
        sys.exit("no tags in %s: capture with telemetry v2" % a.board)

    aligned = align(board, truth)
    tid_of = true_tracks(truth)
    piece_of, n_pass, last_tf = {}, 0, None
    for bf in board:
        tf = aligned[bf][0]
        if tf is not None:
            if last_tf is not None and tf < last_tf - WRAP:
                n_pass += 1
            last_tf = tf
        piece_of[bf] = n_pass

    obs = collections.defaultdict(list)          # true track -> [(board frame, tag)]
    tag_truth = collections.defaultdict(collections.Counter)   # board tag -> truth labels
    tag_frames = collections.defaultdict(set)
    for bf in board:
        tf = aligned[bf][0]
        if tf is None:
            continue
        for (x, y, lab), tag in zip(board[bf], tags[bf]):
            d, i = min(((math.hypot(sx - 1 - x, sy - 1 - y), i) for i, (sx, sy, _) in enumerate(truth[tf])),
                       default=(1e9, -1))
            t_lab = truth[tf][i][2] if d <= MATCH_PX else None
            if tag >= 0:
                tag_truth[tag][t_lab] += 1
                tag_frames[tag].add(bf)
            if t_lab == 1:
                obs[(piece_of[bf], tid_of[(tf, i)])].append((bf, tag))

    tagged = sum(t >= 0 for v in obs.values() for _, t in v)
    total = sum(len(v) for v in obs.values())
    frags, switches = [], 0
    for v in obs.values():
        v.sort()
        frags.append(len({t for _, t in v if t >= 0}))
        last = None
        for _, t in v:
            if t >= 0:
                if last is not None and t != last:
                    switches += 1
                last = t
    false = [g for g, c in tag_truth.items() if c[0] > c[1]]
    flen = sorted(len(tag_frames[g]) for g in false)

    print(f"video passes: {n_pass + 1}")
    print(f"true objects seen by the board: {len(obs)} tracks, {total} observations, "
          f"{tagged / max(total, 1):.4f} tagged")
    print(f"board tags per true track (1 = never lost): {dict(sorted(collections.Counter(min(x, 5) for x in frags).items()))}"
          "   (5 = 5+, 0 = never tagged)")
    print(f"id switches: {switches}")
    if flen:
        print(f"false tracks (tags mostly on stars): {len(false)}, frames each: median {flen[len(flen) // 2]}, "
              f"max {flen[-1]}")
    else:
        print("false tracks (tags mostly on stars): 0")


if __name__ == "__main__":
    main()
