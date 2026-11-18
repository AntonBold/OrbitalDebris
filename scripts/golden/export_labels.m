function export_labels(mat_file, out_csv, uc, K, d, tm, ta, rc, ra)
% export_labels  Run the advisor's MATLAB classifier (original_matlab/Tracker.m)
% on one dataset and write its label for every spot.
%
%   export_labels('original_data/mat/SampleDataRun1.mat', 'sim/build/ml_run1.csv', ...
%                 1000, 10, 10, true, false, false, false)     % c_exporting.m config
%
% Arguments after out_csv are Tracker's: unmatchedCost, maxNumObjects, delta,
% isTranslationMagnitude, isTranslationAngle, isRotationCenter, isRotationAngle.
%
% Output rows: frame,index,label  (index 0-based, in the same order as
% original_data/truth; label 1 object, 0 star, -1 unknown (NaN), -2 frame not
% classified: the first d frames and skipped frames).
% Also prints TPR/TNR/UNK with c_exporting.m's formulas (per-frame mean,
% frames d+1..N).
%
% Needs original_matlab/ on the path. Tracker writes ./assets/results under
% the current folder, so run from a scratch folder.

tracker = Tracker(mat_file, 0.1, uc, K, d, tm, ta, rc, ra);
tracker.classify();
load(tracker.filenames.output, 'classification');
dr = DataReader(mat_file);

N = numel(classification.labels);
TPR = nan(N, 1); TNR = nan(N, 1); UNK = nan(N, 1);
fid = fopen(out_csv, 'w');
for i = 1:N
    y_ = classification.labels{i};
    n = size(dr.pp.spot{i}, 1);
    if isempty(y_)
        fprintf(fid, '%d,%d,-2\n', [repmat(i, 1, n); 0:n-1]);
        continue
    end
    lab = y_;
    lab(isnan(lab)) = -1;
    fprintf(fid, '%d,%d,%d\n', [repmat(i, 1, n); 0:n-1; lab(:)']);
    if i <= d, continue, end
    y = zeros(n, 1);
    y(dr.idx.obj{i}) = 1;
    if any(y == 1)
        TPR(i) = sum(y_ == 1 & y == 1) / sum(y == 1);
    else
        TPR(i) = 1;
    end
    TNR(i) = sum(y_ == 0 & y == 0) / sum(y == 0);
    UNK(i) = sum(isnan(y_)) / n;
end
fclose(fid);
fprintf('TPR %.4f  TNR %.4f  UNK %.4f  (c_exporting.m: per-frame mean)\n', ...
        mean(TPR, 'omitnan'), mean(TNR, 'omitnan'), mean(UNK, 'omitnan'));
end
