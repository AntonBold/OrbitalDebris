#!/usr/bin/env bash
# fetch_mat.sh  --  download the raw .mat datasets into original_data/mat/
#
#   original_data/fetch_mat.sh          all 10 runs (~530 MB)
#   original_data/fetch_mat.sh 9 1      only runs 9 and 1
#
# The .mat files (48-67 MB each) aren't committed; the videos and the exported
# ground truth (truth/*.csv.gz) are. Only needed to re-run export_truth.m or
# the advisor's MATLAB code. Source: github.com/nnategh/orbital-debris (MIT).
set -euo pipefail
dir="$(cd "$(dirname "$0")" && pwd)/mat"
mkdir -p "$dir"
base="https://raw.githubusercontent.com/nnategh/orbital-debris/master/assets/data"
runs=("$@")
[ ${#runs[@]} -eq 0 ] && runs=(1 2 3 4 5 6 7 8 9 10)
for n in "${runs[@]}"; do
    f="SampleDataRun$n.mat"
    if [ -f "$dir/$f" ]; then echo "$f: already there"; continue; fi
    echo "$f: downloading"
    curl -fL --progress-bar -o "$dir/$f.part" "$base/$f"
    mv "$dir/$f.part" "$dir/$f"
done
