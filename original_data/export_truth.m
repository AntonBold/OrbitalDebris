function export_truth(mat_dir, out_dir)
% export_truth  Write each run's ground truth as frame,x,y,label CSV.
%
%   export_truth('original_data/mat', 'original_data/truth')
%
% Reads SampleDataRun<N>.mat (fetch with original_data/fetch_mat.sh) through
% original_matlab/DataReader.m and writes truth/SampleDataRun<N>.csv:
%
%   frame  1-based frame index into the .mat (dr.N frames)
%   x, y   dr.pp.spot{frame}: spot pixel position, MATLAB coordinates
%   label  1 = object, 0 = star (dr.idx.obj{frame})
%
% Same layout as the CSVs read by src/sw/test_harness.c, following the export
% in the advisor's c_exporting.m. Run from MATLAB with original_matlab/ on the
% path. DataReader creates ./assets/results in the current folder, so run it
% from a scratch folder (see original_data/README.md).

if ~exist(out_dir, 'dir'), mkdir(out_dir); end
files = dir(fullfile(mat_dir, 'SampleDataRun*.mat'));
for k = 1:numel(files)
    src = fullfile(files(k).folder, files(k).name);
    [~, name] = fileparts(src);
    dr = DataReader(src);
    fid = fopen(fullfile(out_dir, [name '.csv']), 'w');
    for i = 1:dr.N
        C = dr.pp.spot{i};
        L = zeros(size(C, 1), 1);
        L(dr.idx.obj{i}) = 1;
        for j = 1:size(C, 1)
            fprintf(fid, '%d,%f,%f,%d\n', i, C(j,1), C(j,2), L(j));
        end
    end
    fclose(fid);
    fprintf('%s: %d frames\n', name, dr.N);
end
end
