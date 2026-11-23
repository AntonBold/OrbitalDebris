#!/usr/bin/env python3
"""Parameter sweep for the PS classifier on board-like input.

    python3 scripts/classify_sweep.py                       # default grid, runs 1 5 9
    python3 scripts/classify_sweep.py --runs 9 --d 1 2 5 10 --uc 1000 --K 10
    python3 scripts/classify_sweep.py --input exact60        # MATLAB-style input

Feeds the advisor's ground truth (original_data/truth) through the C
classifier (scripts/classify_replay.c, compiled against src/sw) for every
combination of unmatched cost c, delay d, max outliers K and feature set,
and scores the labels.

--input:
  pixel30  (default) what the board sees: every other frame (30 fps over HDMI)
           and whole-pixel positions (board pixel = round(MATLAB) - 1)
  exact30  every other frame, exact sub-pixel positions
  exact60  every frame, exact positions (the advisor's MATLAB setting)

Scores per run: TPR and TNR as c_exporting.m (per-frame mean), PPV (pooled
precision) and false objects per frame. The first 2d+10 frames are skipped
(classifier memory filling). Results are averaged over runs, sorted by
(TPR + TNR) / 2, and written to sim/build/sweep_<input>.csv.

Features are tm ta rc ra (translation magnitude/angle, rotation
center/angle), e.g. 1110. Standard library only, plus a C compiler.
"""

import argparse
import collections
import csv
import gzip
import itertools
import os
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SW = os.path.join(ROOT, "src", "sw")
TRUTH = os.path.join(ROOT, "original_data", "truth", "SampleDataRun%d.csv.gz")


def build(tmp):
    exe = os.path.join(tmp, "classify_replay")
    srcs = [os.path.join(HERE, "classify_replay.c")] + [os.path.join(SW, f) for f in
                                                         ("classify.c", "hungarian.c", "cost_matrix.c", "geometry.c")]
    subprocess.run([os.environ.get("CC", "cc"), "-O2", "-I", os.path.join(SW, "include"), "-o", exe] + srcs + ["-lm"],
                   check=True)
    return exe


def prepare(run, mode, tmp):
    """Write the replay input for one run. Returns (path, [truth labels per frame])."""
    frames = collections.OrderedDict()
    with gzip.open(TRUTH % run, "rt") as f:
        for r in csv.reader(f):
            frames.setdefault(int(r[0]), []).append((float(r[1]), float(r[2]), int(r[3])))
    keep = sorted(frames) if mode == "exact60" else sorted(frames)[::2]
    path = os.path.join(tmp, "run%d_%s.csv" % (run, mode))
    labels = []
    with open(path, "w") as f:
        for k, fr in enumerate(keep):
            for x, y, _ in frames[fr]:
                if mode == "pixel30":
                    x, y = round(x) - 1, round(y) - 1
                f.write("%d,%.6f,%.6f\n" % (k, x, y))
            labels.append([l for _, _, l in frames[fr]])
    return path, labels


def score(out, labels, skip):
    pred = collections.defaultdict(list)
    for line in out.split():
        k, _, lab = line.split(",")
        pred[int(k)].append(int(lab))
    tpr, tnr, tp, fp, frames = [], [], 0, 0, 0
    for k, truth in enumerate(labels):
        if k < skip:
            continue
        p = pred[k]
        pos = [a for a, t in zip(p, truth) if t == 1]
        neg = [a for a, t in zip(p, truth) if t == 0]
        tpr.append(sum(a == 1 for a in pos) / len(pos) if pos else 1.0)
        if neg:
            tnr.append(sum(a == 0 for a in neg) / len(neg))
        tp += sum(a == 1 for a in pos)
        fp += sum(a == 1 for a in neg)
        frames += 1
    mean = lambda v: sum(v) / len(v) if v else float("nan")
    return mean(tpr), mean(tnr), tp / (tp + fp) if tp + fp else float("nan"), fp / max(frames, 1)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--input", choices=("pixel30", "exact30", "exact60"), default="pixel30")
    ap.add_argument("--runs", type=int, nargs="+", default=[1, 5, 9])
    ap.add_argument("--uc", type=float, nargs="+", default=[100, 1000])
    ap.add_argument("--d", type=int, nargs="+", default=[1, 2, 3, 4, 5, 6, 8, 10])
    ap.add_argument("--K", type=int, nargs="+", default=[5, 10, 15])
    ap.add_argument("--features", nargs="+", default=["1110", "1100", "1000", "0010"])
    ap.add_argument("--top", type=int, default=20)
    ap.add_argument("-j", type=int, default=os.cpu_count())
    a = ap.parse_args()

    with tempfile.TemporaryDirectory() as tmp:
        exe = build(tmp)
        data = {r: prepare(r, a.input, tmp) for r in a.runs}
        configs = list(itertools.product(a.uc, a.d, a.K, a.features))
        jobs = [(c, r) for c in configs for r in a.runs]
        print(f"{len(configs)} configs x {len(a.runs)} runs = {len(jobs)} replays, input {a.input}", file=sys.stderr)

        def run(job):
            (uc, d, K, feat), r = job
            path, labels = data[r]
            out = subprocess.run([exe, path, str(uc), *feat, str(d), str(K)],
                                 check=True, capture_output=True, text=True).stdout
            return job, score(out, labels, 2 * d + 10)

        results = collections.defaultdict(dict)
        with ThreadPoolExecutor(a.j) as pool:
            for n, ((cfg, r), s) in enumerate(pool.map(run, jobs), 1):
                results[cfg][r] = s
                if n % 50 == 0:
                    print(f"  {n}/{len(jobs)}", file=sys.stderr)

    rows = []
    for (uc, d, K, feat), per in results.items():
        avg = [sum(per[r][i] for r in a.runs) / len(a.runs) for i in range(4)]
        rows.append(dict(uc=uc, d=d, K=K, features=feat, TPR=avg[0], TNR=avg[1], PPV=avg[2], FP_per_frame=avg[3],
                         **{f"TPR_run{r}": per[r][0] for r in a.runs}, **{f"TNR_run{r}": per[r][1] for r in a.runs}))
    rows.sort(key=lambda x: (x["TPR"] + x["TNR"]) / 2, reverse=True)

    os.makedirs(os.path.join(ROOT, "sim", "build"), exist_ok=True)
    out_csv = os.path.join(ROOT, "sim", "build", f"sweep_{a.input}.csv")
    with open(out_csv, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)

    runs_hdr = " ".join(f"{'TPR r%d' % r:>8}" for r in a.runs)
    print(f"\n{'uc':>6} {'d':>3} {'K':>3} {'feat':>5} {'TPR':>7} {'TNR':>7} {'PPV':>7} {'FP/fr':>6}  {runs_hdr}")
    for x in rows[:a.top]:
        per = " ".join(f"{x['TPR_run%d' % r]:>8.4f}" for r in a.runs)
        print(f"{x['uc']:>6.0f} {x['d']:>3} {x['K']:>3} {x['features']:>5} {x['TPR']:>7.4f} {x['TNR']:>7.4f} "
              f"{x['PPV']:>7.4f} {x['FP_per_frame']:>6.2f}  {per}")
    print(f"\nall {len(rows)} configs: {out_csv}")


if __name__ == "__main__":
    main()
