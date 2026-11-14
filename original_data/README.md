# original_data

The advisor's simulated star-field datasets, from
[`nnategh/orbital-debris`](https://github.com/nnategh/orbital-debris) (`assets/data/`),
MIT licence (`LICENSE`, Copyright 2019 Yasin Zamani). Made with NASA Marshall's
Dynamic Star Field Simulator. `run_description.txt` lists each run's initial
spacecraft angular velocity `w0`. Run 9 (slow Z rotation) is the one played
over HDMI so far.

| Path | What | In git |
| --- | --- | --- |
| `video/SampleDataRun<N>.mp4` | 1920×1080, 60 fps, 60 s (3,600 frames). Objects are single pixels (grey ≈244 on 0). Played full-screen over HDMI for board runs | yes |
| `truth/SampleDataRun<N>.csv.gz` | Ground truth per spot: `frame,x,y,label` (frame 1..3600, MATLAB pixel coordinates, label 1 = object, 0 = star). Same layout as the CSVs read by `src/sw/test_harness.c` | yes |
| `mat/SampleDataRun<N>.mat` | Raw datasets (48–67 MB each), read by `original_matlab/DataReader.m` | no: `./fetch_mat.sh [runs]` |
| `export_truth.m` | Regenerates `truth/` from `mat/` | yes |
| `fetch_mat.sh` | Downloads `mat/` from the advisor's repo | yes |

## Regenerating `truth/`

```bash
original_data/fetch_mat.sh                      # all runs, ~530 MB
mkdir -p /tmp/mlrun && cd /tmp/mlrun            # DataReader creates ./assets/results here
matlab -batch "addpath('<repo>/original_matlab'); addpath('<repo>/original_data'); \
               export_truth('<repo>/original_data/mat', '<repo>/original_data/truth')"
gzip -n -9 <repo>/original_data/truth/*.csv
```

MATLAB's background ServiceHost process can keep the terminal's output pipe
open after `matlab -batch` finishes: if the command doesn't return, check that
all 10 CSVs end at frame 3600 and press Ctrl-C. Run 1's export is
byte-identical to the `centroids1.csv` used in `docs/spring26_report.md`.

To use a run with `test_harness.c`: `gunzip -k` it and point `CSV_PATH` at the
`.csv`.
