#!/usr/bin/env python3
"""Shrink a failing frame to a minimal repro by deleting foreground pixels one
at a time and keeping each deletion that still fails. The real RTL decides
(via a built testbench binary); the golden model supplies expected values.

    scripts/golden/minimize.py --binary sim/build/sim_cca_random_tb \\
        --vectors sim/build/vectors/cca_random.txt --test rand_1_41_mixed

Scenario options (gaps, resets) are dropped: this isolates image-dependent
failures. Prints the minimal shape and the testbench's mismatch lines.
"""
import argparse
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cca_golden as g


def load(path, test):
    w = h = None
    img = None
    with open(path) as f:
        lines = f.read().splitlines()
    for ln in lines:
        if ln.startswith("# generated"):
            for tok in ln.split():
                if tok.startswith("W="): w = int(tok[2:])
                if tok.startswith("H="): h = int(tok[2:])
    for i, ln in enumerate(lines):
        if ln.startswith("T ") and ln.split()[1] == test:
            rows = [l[2:] for l in lines[i + 2:i + 2 + h]]
            img = [[1 if c == "1" else 0 for c in r] for r in rows]
    if img is None:
        sys.exit(f"test {test} not found in {path}")
    return w, h, img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--binary", required=True)
    ap.add_argument("--vectors", required=True)
    ap.add_argument("--test", required=True)
    a = ap.parse_args()
    w, h, img = load(a.vectors, a.test)
    binary = os.path.abspath(a.binary)
    work = tempfile.mkdtemp(prefix="cca_min_")
    vec = os.path.join(work, "min.txt")

    def run(im):
        g.write_vectors(vec, [g.Test("min", im)], w, h)
        r = subprocess.run([binary, "+vectors=" + vec], cwd=work, capture_output=True, text=True)
        return r.stdout

    def fails(im):
        return "FAIL  0 min" in run(im)

    if not fails(img):
        sys.exit("frame passes on its own (it may need the preceding frames or its scenario options)")
    changed = True
    while changed:
        changed = False
        for y in range(h):
            for x in range(w):
                if img[y][x]:
                    img[y][x] = 0
                    if fails(img):
                        changed = True
                    else:
                        img[y][x] = 1
    ys = [y for y in range(h) if any(img[y])]
    xs = [x for x in range(w) if any(img[y][x] for y in range(h))]
    print(f"minimal repro: {sum(map(sum, img))} pixels at origin ({xs[0]},{ys[0]})")
    for y in range(ys[0], ys[-1] + 1):
        print("  " + "".join("#" if img[y][x] else "." for x in range(xs[0], xs[-1] + 1)))
    for ln in run(img).splitlines():
        if any(k in ln for k in ("MISMATCH", "MISSING", "EXTRA", "CHECK")):
            print(ln)


if __name__ == "__main__":
    main()
