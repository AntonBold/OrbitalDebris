function gesd_vectors(out_csv)
% gesd_vectors  Reference GESD results from MATLAB's isoutlier, for
% scripts/gesd_check.c (the C gesd_outliers in src/sw/classify.c).
%
%   gesd_vectors('sim/build/gesd_vectors.csv')
%
% Each row: id,K,n,v1..vn,f1..fn   (f = isoutlier(v,'gesd','MaxNumOutliers',
% min(K,n)), as Tracker.isObject calls it). Values are rounded to single
% precision first, so the C code (float) sees exactly the same inputs.
%
% Cases: translation-magnitude-like data (~N(1,0.05)) and angle-like data
% (~N(0.3,0.02)) with 0..12 planted outliers, n from 3 to 256, K = 5/10/15;
% integer-valued data with many ties (what whole-pixel board centroids give);
% constant data.

rng(1);
fid = fopen(out_csv, 'w');
id = 0;
ns = [3 4 5 6 8 10 15 20 30 50 80 117 150 200 256];
for K = [5 10 15]
    for n = ns
        for k = [0 1 2 5 10 12]
            if k >= n, continue; end
            for kind = 1:2
                for rep = 1:3
                    if kind == 1
                        v = 1 + 0.05 * randn(n, 1);
                        v(1:k) = 1 + (0.3 + rand(k, 1)) .* sign(randn(k, 1));
                    else
                        v = 0.3 + 0.02 * randn(n, 1);
                        v(1:k) = 0.3 + (0.1 + 0.5 * rand(k, 1)) .* sign(randn(k, 1));
                    end
                    v = v(randperm(n));
                    id = id + 1;
                    write_row(fid, id, K, v);
                end
            end
        end
        % ties: whole-pixel translations (mostly 0/1, a few objects at 2..5)
        for rep = 1:3
            v = double(rand(n, 1) < 0.3);
            m = min(3, n - 1);
            v(1:m) = randi([2 5], m, 1);
            v = v(randperm(n));
            id = id + 1;
            write_row(fid, id, K, v);
        end
        id = id + 1;
        write_row(fid, id, K, ones(n, 1));          % constant
    end
end
fclose(fid);
fprintf('%d cases written to %s\n', id, out_csv);
end

function write_row(fid, id, K, v)
v = double(single(v));
f = isoutlier(v, 'gesd', 'MaxNumOutliers', min(K, numel(v)));
fprintf(fid, '%d,%d,%d', id, K, numel(v));
fprintf(fid, ',%.9g', v);
fprintf(fid, ',%d', f);
fprintf(fid, '\n');
end
