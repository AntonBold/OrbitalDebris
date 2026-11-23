function export_tags(mat_file, out_csv, uc, K, d, tm, ta, rc, ra)
% export_tags  Run the advisor's MATLAB classifier + tracker
% (original_matlab/Tracker.m: classify, track, makeTags) on one dataset and
% write the label and track tag of every spot.
%
%   export_tags('original_data/mat/SampleDataRun1.mat', 'sim/build/ml_tags_run1.csv', ...
%               1000, 10, 1, true, true, true, false)       % Tracker.main() config
%
% Arguments after out_csv are Tracker's: unmatchedCost, maxNumObjects, delta,
% isTranslationMagnitude, isTranslationAngle, isRotationCenter, isRotationAngle.
%
% Output rows: frame,index,label,tag  (index 0-based, same order as
% original_data/truth; label 1 object, 0 star, -1 unknown, -2 frame not
% classified; tag = track id from makeTags, -1 = none: not an object, or an
% object makeTags left untagged, which it does for an object's first frame).
%
% Needs original_matlab/ on the path. Tracker writes ./assets/results under
% the current folder, so run from a scratch folder; delete that folder to
% force a re-run (Tracker skips steps whose output already exists).

tracker = Tracker(mat_file, 0.1, uc, K, d, tm, ta, rc, ra);
tracker.classify();
tracker.track();
tracker.makeTags();
load(tracker.filenames.output, 'classification', 'tags');
dr = DataReader(mat_file);

fid = fopen(out_csv, 'w');
for i = 1:numel(classification.labels)
    n = size(dr.pp.spot{i}, 1);
    lab = classification.labels{i};
    if isempty(lab)
        fprintf(fid, '%d,%d,-2,-1\n', [repmat(i, 1, n); 0:n-1]);
        continue
    end
    lab(isnan(lab)) = -1;
    g = -ones(n, 1);
    if ~isempty(tags{i})
        g = tags{i};
        g(isnan(g)) = -1;
    end
    fprintf(fid, '%d,%d,%d,%d\n', [repmat(i, 1, n); 0:n-1; lab(:)'; g(:)']);
end
fclose(fid);
fprintf('%s: %d frames\n', out_csv, numel(classification.labels));
end
