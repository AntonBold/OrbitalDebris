#!/usr/bin/env python3
"""Golden model + scenario generator for the cca_top testbenches.

The golden model is independent of the RTL algorithm on purpose: objects are
found with a plain 4-connected flood fill, not a translator LUT. Expected BRAM
contents follow docs/pl-ps_interface_spec.md.

Expected values are the *true* per-object sums (what the PS should get). The
only limit applied is the spec's 256-centroid cap per frame (the first 256
objects in raster order of their first pixel). Field overflows (9-bit area,
22-bit Y_sum, 32-bit X_sum) are flagged, and frames that hit them are tagged
as expected-fail automatically, so overflow is checked on purpose rather than
by accident.

Vector file format (read by src/tb/cca_env_tb.sv):

    K <class> <class> ...              all coverage classes in this suite
    T <name> <tag> <count> <flags> <nlabels> <classes>
    O <key=value> ...                  scenario options ("O -" = none)
    R <W chars of 0/1>                 H rows, top row first
    C <x_sum> <y_sum> <area>           <count> lines, decimal, true values

<tag>: "-" must pass; ISSUE2/ISSUE3/ISSUE4/LIMIT_TL_CHAIN/UNDEF_LABEL_OVF are
expected-fail; EXPECT_TIMING passes only if the frame-timing checker fires;
INFO is out of contract (behaviour is reported, never pass/fail).
<nlabels>: provisional labels a raster 4-connected labeller hands out (a
foreground pixel whose north and west neighbours are both background). This
is a property of the image, used for label-capacity tests and coverage.

Usage:
    cca_golden.py directed --out FILE            64x48 directed + protocol
    cca_golden.py wide     --out FILE            256x64 label-capacity tests
    cca_golden.py random   --out FILE --seed N --n N [--w 64 --h 48]
    cca_golden.py full     --out FILE            a few 1920x1080 frames
"""

import argparse
import os
import random
import sys

MAX_CENTROIDS = 256
AREA_BITS = 9
Y_BITS = 22
X_BITS = 32
MAX_LABELS = 1023          # NUM_LABELS - 1 (label 0 is background)


# ---------------------------------------------------------------------------
# Golden model
# ---------------------------------------------------------------------------

def label_objects(img):
    """4-connected flood fill. Returns [(x_sum, y_sum, area)] ordered by the
    raster position of each object's first pixel."""
    h, w = len(img), len(img[0])
    seen = [[False] * w for _ in range(h)]
    objs = []
    for y in range(h):
        for x in range(w):
            if not img[y][x] or seen[y][x]:
                continue
            stack = [(x, y)]
            seen[y][x] = True
            sx = sy = area = 0
            while stack:
                cx, cy = stack.pop()
                sx += cx
                sy += cy
                area += 1
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < w and 0 <= ny < h and img[ny][nx] and not seen[ny][nx]:
                        seen[ny][nx] = True
                        stack.append((nx, ny))
            objs.append((sx, sy, area))
    return objs


def count_new_labels(img):
    """Foreground pixels whose north and west neighbours are background."""
    n = 0
    for y, row in enumerate(img):
        for x, v in enumerate(row):
            if v and not (y > 0 and img[y - 1][x]) and not (x > 0 and row[x - 1]):
                n += 1
    return n


def expected(img):
    """(count, [(x, y, area)], flags, nlabels) with the spec's limits applied."""
    objs = label_objects(img)
    flags = set()
    if len(objs) > MAX_CENTROIDS:
        flags.add("CENT_CAP")
    kept = objs[:MAX_CENTROIDS]
    for sx, sy, a in kept:
        if a >= (1 << AREA_BITS):
            flags.add("AREA_OVF")
        if sy >= (1 << Y_BITS):
            flags.add("Y_OVF")
        if sx >= (1 << X_BITS):
            flags.add("X_OVF")
    nl = count_new_labels(img)
    if nl > MAX_LABELS:
        flags.add("LABEL_OVF")
    return len(kept), kept, flags, nl


def auto_tag(tag, flags):
    """Frames that hit a known overflow are expected-fail unless the test
    already says otherwise."""
    if tag != "-":
        return tag
    if "LABEL_OVF" in flags:
        return "UNDEF_LABEL_OVF"
    if "CENT_CAP" in flags:
        return "ISSUE2"
    if flags & {"AREA_OVF", "Y_OVF", "X_OVF"}:
        return "ISSUE3"
    return tag


# ---------------------------------------------------------------------------
# Image helpers
# ---------------------------------------------------------------------------

def blank(w, h):
    return [[0] * w for _ in range(h)]


def put(img, pts, dx=0, dy=0):
    for x, y in pts:
        img[y + dy][x + dx] = 1
    return img


def rect(x0, y0, rw, rh, hollow=False):
    return [(x, y) for y in range(y0, y0 + rh) for x in range(x0, x0 + rw)
            if not hollow or x in (x0, x0 + rw - 1) or y in (y0, y0 + rh - 1)]


def parse_art(art):
    return [(x, y) for y, row in enumerate(art) for x, c in enumerate(row) if c == "#"]


def img_of(w, h, pts, dx=0, dy=0):
    return put(blank(w, h), pts, dx, dy)


# Hook shape: a label is merged 3 -> 2 -> 1 in one row after the leftmost pixel
# was written to the line buffer (needs the second TL lookup).
TL_CHAIN_HOOK = [
    ".....##.",
    "......##",
    ".......#",
    ".....#.#",
    "....####",
    "....#..#",
]

# Arc labelled 1 encloses a tooth (label 2) and a bar that starts after a gap
# (label 3); the bar merges 3 -> 2 -> 1. Row 5 then reaches the bar's first
# pixel (stored as 3) from the west with label 1.
MERGE_SAME_ROOT = [
    "#########",
    "#.......#",
    "#....#..#",
    "#....#..#",
    "#.#######",
    "###......",
]

TL_OVERWRITE = [
    "........#",
    "#...#..##",
    "#.######.",
    "###......",
    "#........",
]

U_SHAPE = ["#...#", "#...#", "#...#", "#####"]
C_SHAPE = ["#####", "#....", "#....", "#....", "#####"]
REV_C = ["#####", "....#", "....#", "....#", "#####"]
SPIRAL = [
    "###########",
    "#.........#",
    "#.#######.#",
    "#.#.....#.#",
    "#.#.###.#.#",
    "#.#.#.#.#.#",
    "#.#...#.#.#",
    "#.#####.#.#",
    "#.......#.#",
    "#########.#",
]


def comb_dec(teeth):
    """Teeth start one row lower each, right to left; labels come out 1..teeth
    right to left and the bar merges them in decreasing order: a TL chain of
    length `teeth`. A pixel hangs under the bar's left end."""
    pts = []
    right = 3 * teeth - 1
    for j in range(teeth):
        x = right - 3 * j
        pts += [(x, r) for r in range(j, teeth)]
    pts += [(x, teeth) for x in range(right + 1)]
    pts.append((0, teeth + 1))
    return pts


def comb_inc(teeth, x0=0, y0=0, pitch=2):
    """Teeth all start on the same row, so labels increase left to right and
    every tooth merges straight into the bar's (minimum) label: many labels,
    one object, no chain."""
    pts = [(x0 + pitch * j, y0) for j in range(teeth)]
    pts += [(x, y0 + 1) for x in range(x0, x0 + pitch * (teeth - 1) + 1)]
    return pts


def grid_points(w, h, n, step=2):
    """n isolated pixels on a step x step grid (all separate objects)."""
    pts = [(x, y) for y in range(0, h - 1, step) for x in range(0, w - 1, step)]
    assert n <= len(pts), (n, len(pts))
    return pts[:n]


# ---------------------------------------------------------------------------
# Test records
# ---------------------------------------------------------------------------

class Test:
    def __init__(self, name, img, tag="-", opts=None, classes=()):
        self.name, self.img, self.tag = name, img, tag
        self.opts = dict(opts or {})
        self.classes = list(classes)


def directed_tests(w=64, h=48):
    assert (w, h) == (64, 48), "directed suite is laid out for 64x48"
    T = []
    add = lambda *a, **k: T.append(Test(*a, **k))

    # --- basic content -------------------------------------------------------
    add("empty_frame", blank(w, h), classes=["empty"])
    add("single_px_center", img_of(w, h, [(32, 24)]), classes=["single_px", "min_obj"])
    add("corner_px_tl", img_of(w, h, [(0, 0)]), classes=["corner_px"])
    add("corner_px_tr", img_of(w, h, [(w - 1, 0)]), classes=["corner_px"])
    add("corner_px_bl", img_of(w, h, [(0, h - 1)]), classes=["corner_px"])
    # Known issue 1 regression: foreground on the frame's last pixel, then blanking
    add("corner_px_br", img_of(w, h, [(w - 1, h - 1)]), classes=["corner_px", "issue1_last_pixel"])
    add("four_corner_objs", img_of(w, h, rect(0, 0, 3, 3) + rect(w - 3, 0, 3, 3) +
                                   rect(0, h - 3, 3, 3) + rect(w - 3, h - 3, 3, 3)),
        classes=["corner_obj", "issue1_last_pixel"])
    add("full_line_row0", img_of(w, h, rect(0, 0, w, 1)), classes=["full_line"])
    add("full_line_mid", img_of(w, h, rect(0, 20, w, 1)), classes=["full_line"])
    add("full_line_last", img_of(w, h, rect(0, h - 1, w, 1)), classes=["full_line", "issue1_last_pixel"])
    add("border_objs", img_of(w, h, rect(20, 0, 8, 2) + rect(20, h - 2, 8, 2) +
                              rect(0, 20, 2, 8) + rect(w - 2, 20, 2, 8)), classes=["border_obj"])
    add("full_cols_lr", img_of(w, h, rect(0, 0, 1, h) + rect(w - 1, 0, 1, h)),
        classes=["border_obj", "lr_edge_same_rows", "issue1_last_pixel"])
    add("lr_edge_same_rows", img_of(w, h, rect(0, 10, 3, 11) + rect(w - 3, 10, 3, 11)),
        classes=["lr_edge_same_rows"])

    # --- line-buffer alignment / neighbourhood -----------------------------------
    add("row1_vertical_pair", img_of(w, h, [(5, 0), (5, 1)]), classes=["row1_align", "edge_contact"])
    add("row1_diag_pair", img_of(w, h, [(5, 0), (6, 1)]), classes=["row1_align", "corner_contact"])
    add("row1_antidiag_pair", img_of(w, h, [(6, 0), (5, 1)]), classes=["row1_align", "corner_contact"])
    add("row1_first_col_pair", img_of(w, h, [(0, 0), (0, 1)]), classes=["row1_align"])
    add("row1_last_col_pair", img_of(w, h, [(w - 1, 0), (w - 1, 1)]), classes=["row1_align"])
    add("row1_full_rows", img_of(w, h, rect(0, 0, w, 2)), classes=["row1_align"])
    add("row1_bars_offset", img_of(w, h, rect(10, 0, 10, 1) + rect(20, 1, 10, 1)),
        classes=["row1_align", "corner_contact"])
    add("row3_vertical_pair", img_of(w, h, [(5, 2), (5, 3)]), classes=["edge_contact"])
    add("row3_diag_pair", img_of(w, h, [(5, 2), (6, 3)]), classes=["corner_contact"])
    add("row3_antidiag_pair", img_of(w, h, [(6, 2), (5, 3)]), classes=["corner_contact"])
    add("edge_contact_h", img_of(w, h, [(10, 10), (11, 10)]), classes=["edge_contact"])
    add("diagonal_line", img_of(w, h, [(i + 5, i) for i in range(41)]), classes=["diagonal"])
    add("antidiagonal_line", img_of(w, h, [(45 - i, i + 2) for i in range(41)]), classes=["diagonal"])

    # --- merge shapes ----------------------------------------------------------
    add("u_shape", img_of(w, h, parse_art(U_SHAPE), 10, 10), classes=["u_shape"])
    add("c_shape", img_of(w, h, parse_art(C_SHAPE), 10, 10), classes=["c_shape"])
    add("rev_c_shape", img_of(w, h, parse_art(REV_C), 10, 10), classes=["c_shape"])
    add("spiral", img_of(w, h, parse_art(SPIRAL), 10, 10), classes=["spiral"])
    add("tl_chain_hook", img_of(w, h, parse_art(TL_CHAIN_HOOK), 10, 10), classes=["tl_chain"])
    # A pixel whose north (stale label 3 -> 2) and west (root 1) differ after
    # one TL lookup but agree after two: the feature table must not treat it
    # as a merge of two objects (ccl_decision: o_valid_coll = lut_we && dof != dog)
    # Minimised from random seed 1004: a collision whose north label is one
    # hop stale overwrote TL[3]=1 with TL[3]=2, losing 2 == 1 in the TL
    add("tl_overwrite", img_of(w, h, parse_art(TL_OVERWRITE), 10, 10), classes=["tl_chain", "tl_overwrite"])
    add("merge_same_root", img_of(w, h, parse_art(MERGE_SAME_ROOT), 10, 10), classes=["merge_same_root"])
    add("comb_inc_30", img_of(w, h, comb_inc(30, 1, 10)), classes=["comb_inc", "many_way_merge"])
    add("tl_chain_comb2", img_of(w, h, comb_dec(2), 10, 20), classes=["comb_dec", "tl_chain"])
    add("tl_chain_comb3", img_of(w, h, comb_dec(3), 10, 20), tag="LIMIT_TL_CHAIN",
        classes=["comb_dec", "tl_chain"])
    add("tl_chain_comb6", img_of(w, h, comb_dec(6), 10, 20), tag="LIMIT_TL_CHAIN",
        classes=["comb_dec", "tl_chain", "many_way_merge"])
    add("bridge_last_line", img_of(w, h, rect(10, 30, 1, 18) + rect(12, 30, 1, 18) + [(11, h - 1)]),
        classes=["bridge_last_line"])
    add("bridge_last_pixel", img_of(w, h, rect(w - 1, 30, 1, 17) + rect(50, h - 1, 13, 1) + [(w - 1, h - 1)]),
        classes=["bridge_last_line", "issue1_last_pixel"])

    # --- stale state across frames -----------------------------------------------
    add("stale_north_setup", img_of(w, h, [(w - 1, h - 2)]), classes=["stale_north"])
    add("row0_after_stale", img_of(w, h, [(5, 0), (5, 10)]), classes=["stale_north"])

    # --- sizes / accumulators ----------------------------------------------------
    a511 = rect(32, 32, 32, 16)[1:]          # 511 px in the bottom rows: max area, max Y
    add("max_area_511", img_of(w, h, a511), classes=["max_area_511"])
    add("area_512", img_of(w, h, rect(32, 32, 32, 16)), classes=["area_512"])
    add("solid_frame", img_of(w, h, rect(0, 0, w, h)), classes=["solid_frame", "issue1_last_pixel"])

    # --- BRAM / TL capacity --------------------------------------------------------
    for n in (255, 256, 257):
        add(f"cent_{n}", img_of(w, h, grid_points(w, h, n)), classes=[f"cent_{n}"])
    add("checkerboard", [[(x + y) % 2 for x in range(w)] for y in range(h)], classes=["checkerboard"])

    # --- protocol: tvalid gaps -------------------------------------------------
    shapes = img_of(w, h, parse_art(U_SHAPE) + [(x + 20, y) for x, y in parse_art(SPIRAL)] +
                    rect(40, 30, 6, 6), 2, 5)
    add("gaps_30pct", shapes, opts={"gap": 30}, classes=["gaps"])
    add("gaps_90pct", shapes, opts={"gap": 90}, classes=["gaps"])
    add("gaps_last_pixel", img_of(w, h, rect(w - 4, h - 4, 4, 4)), opts={"gap": 50},
        classes=["gaps", "issue1_last_pixel"])

    # --- protocol: inter-frame gap and TL init (frame timing contract) ------------
    add("ifg_min_a", shapes, opts={"ifg": "min"}, classes=["ifg_min"])
    add("ifg_min_b", img_of(w, h, rect(5, 5, 4, 4)), classes=["ifg_min"])
    add("ifg_short_a", shapes, opts={"ifg": "min-1"}, classes=["ifg_min_minus1"])
    add("ifg_short_b", img_of(w, h, rect(5, 5, 4, 4)), tag="EXPECT_TIMING", classes=["ifg_min_minus1"])
    add("tl_init_min", shapes, opts={"rst_before": "min"}, classes=["tl_init_min", "rst_recovery"])
    add("tl_init_early", shapes, tag="EXPECT_TIMING", opts={"rst_before": "min-1"}, classes=["tl_init_early"])

    # --- protocol: reset injection -------------------------------------------------
    busy = img_of(w, h, [(x, y) for y in range(h) for x in range(w) if (x // 4 + y // 4) % 3 == 0])
    add("rst_mid_frame", busy, opts={"rst_before": "min", "rst_at_pixel": w * h // 2},
        classes=["rst_mid_frame"])
    add("rst_mid_frame_recovery", shapes, classes=["rst_mid_frame", "rst_recovery"])
    add("rst_in_dump", busy, opts={"rst_after": 200}, classes=["rst_in_dump"])
    add("rst_in_dump_recovery", shapes, classes=["rst_in_dump", "rst_recovery"])
    add("rst_in_blank", busy, opts={"rst_after_irq": 50}, classes=["rst_in_blank"])
    add("rst_in_blank_recovery", shapes, classes=["rst_in_blank", "rst_recovery"])

    # --- protocol: frame number near the 23-bit limit ------------------------------
    small = img_of(w, h, rect(5, 5, 3, 3))
    add("fnum_7ffffe", small, opts={"rst_before": "min", "fnum": 0x7FFFFE}, classes=["fnum_limit"])
    add("fnum_7fffff", small, classes=["fnum_limit"])
    add("fnum_wrap", small, tag="ISSUE4", classes=["fnum_limit"])

    # --- out-of-contract framing (reported, not judged) ---------------------------
    malformed = [
        ("missing_tlast", "missing_tlast:10"),
        ("extra_tlast", "extra_tlast:10:20"),
        ("missing_tuser", "missing_tuser"),
        ("short_frame", "rows:40"),
        ("long_frame", "rows:52"),
        ("short_line", "line_len:10:50"),
        ("long_line", "line_len:10:70"),
    ]
    for name, spec in malformed:
        add(f"malf_{name}", shapes, tag="INFO", opts={"rst_before": "min", "malform": spec},
            classes=[f"malformed_{name}"])
        add(f"malf_{name}_next", shapes, tag="INFO", classes=[f"malformed_{name}"])
    add("final_clean_frame", shapes, opts={"rst_before": "min"}, classes=["rst_recovery"])
    return T


def wide_tests(w=256, h=64):
    """Label-capacity tests: same-row combs use many labels for few objects."""
    T = []
    for n in (1022, 1023, 1024, 1100):
        pts, left, band = [], n, 0
        while left > 0:
            teeth = min(left, w // 2)
            pts += comb_inc(teeth, 0, 3 * band)
            left -= teeth
            band += 1
        assert 3 * band <= h
        T.append(Test(f"labels_{n}", img_of(w, h, pts), classes=[f"labels_{n}"]))
    T.append(Test("labels_after_ovf", img_of(w, h, rect(10, 10, 5, 5)), classes=["labels_1100"]))
    return T


def random_frame(rng, w, h):
    img = blank(w, h)
    style = rng.choice(["debris", "debris", "rects", "noise", "blobs"])
    if style == "debris":                    # small compact blobs, like the real target
        for _ in range(rng.randint(1, 40)):
            cx, cy, r = rng.randrange(w), rng.randrange(h), rng.choice([0, 1, 1, 2, 3])
            for y in range(cy - r, cy + r + 1):
                for x in range(cx - r, cx + r + 1):
                    if 0 <= x < w and 0 <= y < h and (x - cx) ** 2 + (y - cy) ** 2 <= r * r + rng.randint(0, 2):
                        img[y][x] = 1
    elif style == "rects":
        for _ in range(rng.randint(1, 12)):
            rw, rh = rng.randint(1, w // 3), rng.randint(1, h // 3)
            put(img, rect(rng.randint(0, w - rw), rng.randint(0, h - rh), rw, rh, rng.random() < 0.4))
    elif style == "noise":
        p = rng.choice([0.02, 0.05, 0.1, 0.2])
        img = [[1 if rng.random() < p else 0 for _ in range(w)] for _ in range(h)]
    else:                                    # random-walk blobs
        for _ in range(rng.randint(1, 8)):
            x, y = rng.randrange(w), rng.randrange(h)
            for _ in range(rng.randint(5, 120)):
                img[y][x] = 1
                x = min(w - 1, max(0, x + rng.choice((-1, 0, 1))))
                y = min(h - 1, max(0, y + rng.choice((-1, 0, 1))))
    return style, img


def random_tests(w, h, n, seed):
    rng = random.Random(seed)
    T = []
    for i in range(n):
        style, img = random_frame(rng, w, h)
        opts, classes = {}, [f"rand_{style}"]
        r = rng.random()
        if r < 0.25:
            opts["gap"] = rng.choice([5, 20, 50, 80])
            classes.append("gaps")
        if rng.random() < 0.08:
            opts["ifg"] = "min"
            classes.append("ifg_min")
        if rng.random() < 0.05:
            opts["rst_before"] = rng.choice(["min", 1500, 4000])
            classes.append("rst_recovery")
        if rng.random() < 0.04:              # aborted frame, then this frame recovers
            abort = Test(f"rand_{seed}_{i}_abort", random_frame(rng, w, h)[1],
                         opts={"rst_before": "min", "rst_at_pixel": rng.randrange(1, w * h)},
                         classes=["rst_mid_frame"])
            T.append(abort)
            classes.append("rst_recovery")
        T.append(Test(f"rand_{seed}_{i}_{style}", img, opts=opts, classes=classes))
    return T


def full_tests(w=1920, h=1080, seed=1):
    rng = random.Random(seed)
    T = []
    pts = []
    for _ in range(60):
        cx, cy, r = rng.randrange(4, w - 4), rng.randrange(4, h - 4), rng.choice([0, 1, 2, 3])
        pts += [(x, y) for y in range(cy - r, cy + r + 1) for x in range(cx - r, cx + r + 1)
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r]
    T.append(Test("full_debris", img_of(w, h, sorted(set(pts))), classes=["full_hd"]))
    T.append(Test("full_borders", img_of(w, h, rect(0, 0, 4, 4) + rect(w - 4, 0, 4, 4) + rect(0, h - 4, 4, 4) +
                                         rect(w - 4, h - 4, 4, 4) + rect(0, 500, 3, 20) + rect(w - 3, 500, 3, 20) +
                                         rect(900, 0, 20, 2) + rect(900, h - 2, 20, 2) +
                                         parse_art_offset(SPIRAL, 1000, 700) + comb_inc(100, 100, 300)),
                  classes=["full_hd", "border_obj", "corner_obj", "lr_edge_same_rows"]))
    T.append(Test("full_y_sum_22bit", img_of(w, h, rect(0, 1000, w, 80)),
                  classes=["full_hd", "y_sum_22bit"]))
    return T


def parse_art_offset(art, dx, dy):
    return [(x + dx, y + dy) for x, y in parse_art(art)]


# ---------------------------------------------------------------------------
# Writer
# ---------------------------------------------------------------------------

def write_vectors(path, tests, w, h, note=""):
    d = os.path.dirname(os.path.abspath(path))
    os.makedirs(d, exist_ok=True)
    classes = []
    for t in tests:
        for c in t.classes:
            if c not in classes:
                classes.append(c)
    with open(path, "w") as f:
        f.write(f"# generated by scripts/golden/cca_golden.py {note} W={w} H={h}\n")
        f.write("K " + " ".join(classes) + "\n")
        for t in tests:
            assert len(t.img) == h and all(len(r) == w for r in t.img), t.name
            count, objs, flags, nl = expected(t.img)
            # an aborted frame's data is never compared, so overflow can't make it fail
            tag = t.tag if "rst_at_pixel" in t.opts else auto_tag(t.tag, flags)
            flag_str = ",".join(sorted(flags)) or "-"
            cls = ",".join(t.classes) or "-"
            f.write(f"T {t.name} {tag} {count} {flag_str} {nl} {cls}\n")
            opts = " ".join(f"{k}={v}" for k, v in t.opts.items()) or "-"
            f.write(f"O {opts}\n")
            for row in t.img:
                f.write("R " + "".join("1" if v else "0" for v in row) + "\n")
            for sx, sy, a in objs:
                f.write(f"C {sx} {sy} {a}\n")
    return len(tests)


def self_test():
    """Sanity checks of the golden model itself."""
    assert label_objects([[1, 1], [1, 1]]) == [(2, 2, 4)]
    assert len(label_objects([[1, 0], [0, 1]])) == 2           # corner contact: separate
    assert len(label_objects(img_of(9, 6, comb_dec(3)))) == 1
    assert len(label_objects(img_of(20, 3, comb_inc(5)))) == 1
    assert count_new_labels(img_of(20, 3, comb_inc(5))) == 5
    assert count_new_labels(img_of(4, 4, grid_points(4, 4, 4))) == 4
    c, objs, flags, _ = expected(img_of(64, 48, grid_points(64, 48, 257)))
    assert c == 256 and "CENT_CAP" in flags
    assert "AREA_OVF" in expected(img_of(64, 48, rect(0, 0, 32, 16)))[2]
    assert "AREA_OVF" not in expected(img_of(64, 48, rect(0, 0, 32, 16)[1:]))[2]
    print("cca_golden self-test: OK")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("suite", choices=["directed", "wide", "random", "full", "selftest"])
    ap.add_argument("--w", type=int)
    ap.add_argument("--h", type=int)
    ap.add_argument("--n", type=int, default=50)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out")
    a = ap.parse_args()
    if a.suite == "selftest":
        return self_test()
    if a.suite == "directed":
        w, h = a.w or 64, a.h or 48
        tests, note = directed_tests(w, h), ""
    elif a.suite == "wide":
        w, h = a.w or 256, a.h or 64
        tests, note = wide_tests(w, h), ""
    elif a.suite == "random":
        w, h = a.w or 64, a.h or 48
        tests, note = random_tests(w, h, a.n, a.seed), f"seed={a.seed}"
    else:
        w, h = a.w or 1920, a.h or 1080
        tests, note = full_tests(w, h, a.seed), f"seed={a.seed}"
    n = write_vectors(a.out, tests, w, h, note)
    print(f"cca_golden: {a.suite} {note} wrote {n} frames ({w}x{h}) to {a.out}")


if __name__ == "__main__":
    sys.exit(main())
