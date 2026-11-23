#!/usr/bin/env python3
"""Compare the PS tracker (src/sw/track.c) with the advisor's MATLAB tracker.

    python3 scripts/track_check.py sim/build/ml_tags_run1.csv original_data/truth/SampleDataRun1.csv.gz
    python3 scripts/track_check.py ML.csv TRUTH.csv --mode classify     # C classifier + C tracker

ML.csv comes from scripts/golden/export_tags.m (frame,index,label,tag).
The truth CSV gives the spot positions in the same order.

--mode given (default): the C tracker gets MATLAB's labels, so only tracking
  is compared. --mode classify: the C classifier labels the spots first (as on
  the board), so label differences show up in tracking too.
The tracker runs through trackStep (src/sw/track.c), the same call main.c
makes, via scripts/track_replay.c.

Tag numbers differ between implementations, so tracks are compared by their
links: each tagged object is linked to the most recent earlier observation
with the same tag. Reported:
  links      MATLAB's links the C tracker also makes (recall), and C links
             MATLAB also makes (precision)
  fragments  for each MATLAB track, how many C tags cover it (1 = intact)
  merges     for each C track, how many MATLAB tags it covers (1 = clean)
Standard library only, plus a C compiler.
"""

import argparse
import collections
import csv
import gzip
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SW = os.path.join(os.path.dirname(HERE), "src", "sw")


def read_tags(lines):
    """-> {(frame, index): (label, tag)}"""
    out = {}
    for r in csv.reader(lines):
        out[(int(r[0]), int(r[1]))] = (int(r[2]), int(r[3]))
    return out


def links(tags):
    """{(frame, index): tag} -> set of ((frame, index), (frame, index)) same-tag links"""
    last, out = {}, set()
    for key in sorted(tags):
        g = tags[key]
        if g < 0:
            continue
        if g in last:
            out.add((last[g], key))
        last[g] = key
    return out


def coverage(a, b):
    """For each tag in a: number of distinct tags b gives the same observations."""
    cover = collections.defaultdict(set)
    for key, g in a.items():
        if g >= 0 and b.get(key, -1) >= 0:
            cover[g].add(b[key])
    return [len(v) for v in cover.values()]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("matlab", help="export_tags.m output")
    ap.add_argument("truth", help="original_data/truth/SampleDataRun<N>.csv(.gz)")
    ap.add_argument("--mode", choices=("given", "classify"), default="given")
    ap.add_argument("--config", nargs="*", default=["1000"],
                    help="replay config: uc [tm ta rc ra d K] (default 1000, MATLAB Tracker.main)")
    a = ap.parse_args()

    ml = read_tags(open(a.matlab))
    op = gzip.open if a.truth.endswith(".gz") else open
    with tempfile.TemporaryDirectory() as tmp:
        exe = os.path.join(tmp, "track_replay")
        srcs = [os.path.join(HERE, "track_replay.c")] + [os.path.join(SW, f) for f in
                                                         ("track.c", "classify.c", "hungarian.c", "cost_matrix.c",
                                                          "geometry.c")]
        subprocess.run([os.environ.get("CC", "cc"), "-O2", "-I", os.path.join(SW, "include"), "-o", exe] + srcs
                       + ["-lm"], check=True)
        inp = os.path.join(tmp, "in.csv")
        with op(a.truth, "rt") as f, open(inp, "w") as g:
            idx = collections.Counter()
            for r in csv.reader(f):
                fr = int(r[0])
                lab = ml.get((fr, idx[fr]), (-2, -1))[0]
                g.write(f"{fr},{r[1]},{r[2]},{lab}\n")
                idx[fr] += 1
        args = [exe, inp, a.mode] + a.config
        c = read_tags(subprocess.run(args, check=True, capture_output=True, text=True).stdout.splitlines())

    ml_tag = {k: v[1] for k, v in ml.items()}
    c_tag = {k: v[1] for k, v in c.items()}
    lab_same = sum(ml[k][0] == c[k][0] for k in ml if k in c and ml[k][0] != -2)
    lab_tot = sum(1 for k in ml if k in c and ml[k][0] != -2)
    L_ml, L_c = links(ml_tag), links(c_tag)
    both = len(L_ml & L_c)
    frag, merge = coverage(ml_tag, c_tag), coverage(c_tag, ml_tag)

    print(f"mode {a.mode}, config {' '.join(a.config)}")
    print(f"labels identical to MATLAB: {lab_same}/{lab_tot}")
    print(f"tagged objects: MATLAB {sum(g >= 0 for g in ml_tag.values())}, C {sum(g >= 0 for g in c_tag.values())}")
    print(f"tracks:         MATLAB {len(set(g for g in ml_tag.values() if g >= 0))}, "
          f"C {len(set(g for g in c_tag.values() if g >= 0))}")
    print(f"links: MATLAB {len(L_ml)}, C {len(L_c)}, shared {both}  "
          f"(recall {both / max(len(L_ml), 1):.4f}, precision {both / max(len(L_c), 1):.4f})")
    hist = lambda v: dict(sorted(collections.Counter(min(x, 5) for x in v).items()))
    print(f"fragments per MATLAB track (5 = 5+): {hist(frag)}")
    print(f"MATLAB tracks per C track   (5 = 5+): {hist(merge)}")


if __name__ == "__main__":
    main()
