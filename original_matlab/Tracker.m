classdef Tracker < handle
    % Classify spots to starts or objects then track objects
    
    % Properties
    properties (Constant)
        ASSETS_FOLDER = './assets';
        DATA_FOLDER = './assets/data/';
        
        BINARIZATION_THRESHOLD = 0.1;
        UNMATCHED_COST = 100;
        MAX_NUM_OBJECTS = 10; % todo: must be `10`
        DELTA = 10;
        IS_VELOCITY_MAGNITUDE = true; % todo: change `is` to `use`
        IS_VELOCITY_DIRECTION = true;
        IS_ROTATION_CENTER = true;
        IS_ROTATION_ANGLE = true;
        
        DELTA_SET = [1, 5, 10, 15, 20, 25, 30];
        UNMATCHED_COST_SET = [1, 2, 4, 8, 16, 32, 64];
        
        FIGURE_TYPE = '.png';
        
        EPS = 1e-2;
        INF = 1e5;
    end
    
    properties
        folders % path of folders
        filenames % path of filenames
        
        binarizationThreshold % threshold of binarization
        unmatchedCost % cost of unmatched (unknown labels)
        maxNumObjects % maximum number of objects
        delta % length of memory (time-delta : time)
        
        % is ... as a classification feature
        isTranslationMagnitude % use magnitude of velocity to find outliers
        isTranslationAngle % use direction of velocity to find outliers
        isRotationCenter % use center of rotation to find outliers
        isRotationAngle % use angle of rotation to find outliers
    end
    
    % Constructor
    methods
        function this = Tracker(...
                filename, ...
                binarizationThreshold, ...
                unmatchedCost, ...
                maxNumObjects, ...
                delta, ...
                isTranslationMagnitude, ...
                isTranslationAngle, ...
                isRotationCenter, ...
                isRotationAngle)
            % Constructor
            
            this.binarizationThreshold = binarizationThreshold;
            this.unmatchedCost = unmatchedCost;
            this.maxNumObjects = maxNumObjects;
            this.delta = delta;
            this.isTranslationMagnitude = isTranslationMagnitude;
            this.isTranslationAngle = isTranslationAngle;
            this.isRotationCenter = isRotationCenter;
            this.isRotationAngle = isRotationAngle;
            
            this.initFolders(filename);
            this.initFilenames(filename);
        end
        
        % Folders/Filenames
        function initFolders(this, filename)
            % Init `Folders` property
            
            assets = Tracker.ASSETS_FOLDER;
            % resutls = Tracker.getResultsFolder(filename);
            
            [~, name] = fileparts(filename);
            results = fullfile(assets, 'results', sprintf('%s-%s', name, this.getPostfix()));    
            
            if ~exist(results, 'dir')
                mkdir(results);
            end
            
            this.folders = struct(...
                'assets', assets, ...
                'results', results);
        end
        
        function initFilenames(this, filename)
            % Init `Filenames` property
            
            [folder, name] = fileparts(filename);
            
            this.filenames = struct(...
                'video', filename, ...
                'data', fullfile(folder, [name, '.mat']), ...
                'output', fullfile(this.folders.results, sprintf('%s-output.mat', name)), ...
                'classifiedVideo', fullfile(this.folders.results, sprintf('%s-classified.mp4', name)), ...
                'trackedVideo', fullfile(this.folders.results, sprintf('%s-tracked.mp4', name)));
        end
        
        function postfix = getPostfix(this)
            postfix = sprintf('d-%d-c-%d-tm-%d-ta-%d-rc-%d-ra-%d', ...
                this.delta, ...
                this.unmatchedCost, ...
                this.isTranslationMagnitude, ...
                this.isTranslationAngle, ...
                this.isRotationCenter, ...
                this.isRotationAngle);
        end
        
        % Save
        function save(this)
            props = {};
            
            props.filename = this.filenames.video;
            props.binarizationThreshold = this.binarizationThreshold;
            props.unmatchedCost = this.unmatchedCost;
            props.maxNumObjects = this.maxNumObjects;
            props.delta = this.delta;
            props.isTranslationMagnitude = this.isTranslationMagnitude;
            props.isTranslationAngle = this.isTranslationAngle;
            props.isRotationCenter = this.isRotationCenter;
            props.isRotationAngle = this.isRotationAngle;
            
            save(this.filenames.output, 'props');
        end
    end
    
    methods (Static)
        % Load
        function tracker = load(filename)
            load(filename, 'props');
            
             tracker = Tracker(...
                props.filename, ...
                props.binarizationThreshold, ...
                props.unmatchedCost, ...
                props.maxNumObjects, ...
                props.delta, ...
                props.isTranslationMagnitude, ...
                props.isTranslationAngle, ...
                props.isRotationCenter, ...
                props.isRotationAngle);
        end
    end
    
    % Classify
    methods
        function classify(this)
            % Classify spots to
            %   - true: Object
            %   - false: Star
            %   - NaN: Unknown
            
            if this.existOutputField('classification')
                return
            end
            
            % properties
            uc = this.unmatchedCost; % unmatched/unknown cost
            K = this.maxNumObjects; % maximum number of objects
            d = this.delta; % delay/memory length
            
            memory = cell(d, 1); % memory
            centroids = cell(d, 1); % centroids
            labels = cell(d, 1); % labels
            matches = cell(d, 1); % matches
            translations = cell(d, 1); % translations
            rotations = cell(d, 1); % rotations
            
            % load sample video
            dr = DataReader(this.filenames.data);
            N = dr.N; % number of frames
            C = dr.pp.spot; % pixel positions of spots
            
            % fprintf('\nCompute centroid labels: ...\n');
            % tic();
            
            % read first `d` frames to memory
            for t1 = 1:d
                 C1 = C{t1}; % centroids of previous frame
                 memory{t1} = struct('t', t1, 'C', C1);
                 centroids{t1} = C1;
                 labels{t1} = [];
                 matches{t1} = struct('t', [], 'D', [], 'M', []);
                 translations{t1} = [];
                 rotations{t1} = struct('center', [], 'angle', [], 'M', []);
                 
                 % fprintf('Frame: %d, \tSpots: %d, \tSkipped\n', i, size(C1, 1));
            end
            
            C1 = memory{1}.C;
            numOfFoundedMatch = 0;
            for t2 = (d + 1):N % time of current frame
                if numOfFoundedMatch == d
                    break;
                end
                
                t1 = memory{1}.t; % time of previous frame
                
                C2 = C{t2};
                
                % number of spots are same as previous frames
                n1 = size(C1, 1);
                n2 = size(C2, 1);
                
                txt = sprintf('Frame: %d, \tSpots: %d', t2, n2);
                
                if abs(n1 - n2) < K
                    numOfFoundedMatch = numOfFoundedMatch + 1;
                    
                    L = nan(n2, 1); % labels of current iteration
                    
                    % matching
                    M01 = matches{t1}.M;
                    
                    if isempty(M01)
                        D = Tracker.getCostMatrix(C1, C2);
                    else
                        T = zeros(size(C1));
                        T(M01(:, 2), :) = translations{t1};
                        
                        D = Tracker.getCostMatrix(C1 + T, C2);
                    end
                    
                    
                    M12 = matchpairs(D, uc);
                    nm = size(M12, 1); % number of match pairs

                    % translations
                    T = Tracker.getTranslations(C1, C2, M12);

                    % labeling
                    TF = false(nm, 1);
                    
                    if nm > 0
                        if this.isTranslationMagnitude
                            TF = TF | this.isObject(vecnorm(T, 2, 2));
                        end
                        if this.isTranslationAngle
                            TF = TF | this.isObject(atan2(T(:, 2), T(:, 1)));
                        end
                    end

                    L(M12(:, 2)) = TF; 

                    memory(1) = [];
                    memory{d} = struct('t', t2, 'C', C2);
                    C1 = memory{1}.C;
                    
                    txt = [txt, ...
                        sprintf('\tObjects: %d, \tUnknonw: %d\n', ...
                        sum(L == 1), sum(isnan(L)))];
                elseif n1 > n2
                    D = [];
                    M12 = [];
                    t1 = [];
                    L = [];
                    T = [];
                    
                    memory(1) = [];
                    memory{d} = struct('t', t2, 'C', C2);
                    C1 = memory{1}.C;
                    
                    txt = [txt, '\tSkipped\n'];
                else
                    D = [];
                    M12 = [];
                    t1 = [];
                    L = [];
                    T = [];
                    
                    txt = [txt, '\tSkipped\n'];
                end
                
                % fprintf(txt);
                
                centroids{t2} = C2;
                labels{t2} = L;
                matches{t2} = struct('t', t1, 'D', D, 'M', M12);
                translations{t2} = T;
                rotations{t2} = struct('center', [], 'angle', [], 'M', []);
            end
            
            for t2 = t2:N
                t1 = memory{1}.t; % time of previous frame
                
                C2 = C{t2};
                
                % number of spots are same as previous frames
                n1 = size(C1, 1);
                n2 = size(C2, 1);
                
                txt = sprintf('Frame: %d, \tSpots: %d', t2, n2);
                
                if abs(n1 - n2) < K
                    L = nan(n2, 1); % labels of current iteration
                    
                    % matching
                    R = rotations{t1};
                    M01 = matches{t1}.M;
                    
                    if isempty(M01)
                        D = Tracker.getCostMatrix(C1, C2);
                    else
                        T = zeros(size(C1));
                        T(M01(:, 2), :) = translations{t1};
                        
                        if ~isempty(R.M)
                            % rotate
                            RC1 = C1;
                            for j = 1:size(R.M, 1)
                                ind = R.M(j, 3);
                                % if R.angle(j) == 0 || (R.center(j, 1) == Tracker.INF && R.center(j, 2) == Tracker.INF)
                                if R.angle(j) == 0 || any(isinf(R.center(j, :)))
                                    RC1(ind, :) = C1(ind, :) + T(ind, :);
                                else
                                    RC1(ind, :) = Tracker.rotate(C1(ind, :)', R.angle(j), R.center(j, :)');
                                end
                            end

                            D = Tracker.getCostMatrix(RC1, C2);
                        else
                            D = Tracker.getCostMatrix(C1 + T, C2);
                        end
                    end
                    
                    M12 = matchpairs(D, uc);
                    nm = size(M12, 1); % number of match pairs
                    
                    % translations
                    T = Tracker.getTranslations(C1, C2, M12);
                    
                    % rotations
                    t0 = matches{t1}.t;
                    C0 = centroids{t0};
                    
                    R = Tracker.getRotations(C0, C1, C2, M01, M12);

                    % labeling
                    TF = false(nm, 1);
                    
                    % - translations
                    if nm > 0
                        if this.isTranslationMagnitude
                            TF = TF | this.isObject(vecnorm(T, 2, 2));
                        end
                        if this.isTranslationAngle
                            TF = TF | this.isObject(atan2(T(:, 2), T(:, 1)));
                        end
                    end
                    
                    LT = nan(size(L));
                    if nm > 0
                        LT(M12(:, 2)) = TF;
                    end
                    
                    % - rotations
                    nm = size(R.M, 1); % number of match pairs
                    TF = false(nm, 1);
                    if nm > 0
                        % -- center
                        if this.isRotationCenter
                            TF = TF | this.isObject(Tracker.getDistanceFromMedianCenter(R.center));
                        end
                            
                        % -- angle
                        if this.isRotationAngle
                            TF = TF | this.isObject(R.angle);
                        end
                    end
                    
                    LR = nan(size(L));
                    if nm > 0
                        LR(R.M(:, 3)) = TF;
                    end
                    
                    L = Tracker.nanor(LT, LR);

                    memory(1) = [];
                    memory{d} = struct('t', t2, 'C', C2);
                    C1 = memory{1}.C;
                    
                    txt = [txt, ...
                        sprintf('\tObjects: %d, \tUnknonw: %d\n', ...
                        sum(L == 1), sum(isnan(L)))];
                elseif n1 > n2
                    D = [];
                    M12 = [];
                    t1 = [];
                    L = [];
                    T = [];
                    
                    memory(1) = [];
                    memory{d} = struct('t', t2, 'C', C2);
                    C1 = memory{1}.C;
                    
                    txt = [txt, '\tSkipped\n'];
                else
                    D = [];
                    M12 = [];
                    t1 = [];
                    L = [];
                    T = [];
                    
                    txt = [txt, '\tSkipped\n'];
                end
                
                % fprintf(txt);
                
                centroids{t2} = C2;
                labels{t2} = L;
                matches{t2} = struct('t', t1, 'D', D, 'M', M12);
                translations{t2} = T;
                rotations{t2} = R;
            end
            
            % fprintf('\nFile `%s` saved: ', this.filenames.output);
            this.save();
            classification.centroids = centroids;
            classification.labels = labels;
            classification.matches = matches;
            classification.translations = translations;
            classification.rotations = rotations;
            save(this.filenames.output, 'classification', '-append');
            % toc();
        end
        
        function TF = isObject(this, A)
            TF = isoutlier(...
                A, ...
                'gesd', ...
                'MaxNumOutliers', min(this.maxNumObjects, numel(A)));
        end
        
        function video = loadVideo(this)
            fprintf('Load `%s`: ', this.filenames.video);
            tic();
            video = VideoReader(this.filenames.video);
            toc();
        end
    end
    
    % Rotation
    methods (Static)
        function d = getDistanceFromMedianCenter(C)
            mc = median(C); % median center
            C = C - mc;
            d = vecnorm(C, 2, 2);
            d(isnan(d)) = 0;
        end
        
        function R = getRotations(C1, C2, C3, M12, M23)
            center = [];
            angle = [];
            M = [];
            
            for i = 1:size(M12, 1)
                i1 = M12(i, 1);
                i2 = M12(i, 2);
                
                j = find(M23(:, 1) == i2);
                if isempty(j)
                    continue;
                end
                
                i3 = M23(j, 2);
                
                p0 = C1(i1, :)';
                p1 = C2(i2, :)';
                p2 = C3(i3, :)';
                
                [c, a] = Tracker.getCenterAngleOfRotation(p0, p1, p2);
                center(end + 1, :) = c';
                angle(end + 1, 1) = a;
                M(end + 1, :) = [i1, i2, i3];
            end
            
            R = struct('center', center, 'angle', angle, 'M', M);
        end
        
        function [c, a] = getCenterAngleOfRotation(p1, p2, p3)
            % Center
            l1 = Tracker.getPerpBisector(p1, p2);
            l2 = Tracker.getPerpBisector(p2, p3);

            c = Tracker.getIntersectionOfTwoLines(l1, l2);

            % Angle
            % u1 = p1 - c;
            u2 = p2 - c;
            u3 = p3 - c;

            % a1 = Tracker.getAngleBetweenTwoVectors(u1, u2);
            a2 = Tracker.getAngleBetweenTwoVectors(u2, u3);

            % a = (a1 + a2) / 2;
            a = a2;
        end
        
        function l = getPerpBisector(p1, p2)
            l = Tracker.getLine(p1, p2);
            n = l(1:2);
            n = Tracker.rotate(n, pi / 2);

            m = (p1 + p2) / 2;
            c = dot(n, m);

            l = [n; -c];
        end
       
        function l = getLine(p1, p2)
            p1 = [p1; 1];
            p2 = [p2; 1];
            l = cross(p1, p2);
        end

        function p = rotate(p, a, c)
            if nargin < 3
                c = [0, 0]';
            end

            p = p - c;

            R = Tracker.getRotationMatrix(a);
            p = R * p;

            p = p + c;
        end

        function R = getRotationMatrix(a)
            % Get rotation matrix
            c = cos(a);
            s = sin(a);
            R = [c -s; s c];
        end
        
        function p = getIntersectionOfTwoLines(l1, l2)
            p = cross(l1, l2);
            p = p / p(3);
            p = p(1:2);
            
            if any(isnan(p) | abs(p) > Tracker.INF)
                %? p = [Tracker.INF, Tracker.INF]';
                p = [inf, inf]';
            end
        end

        function a = getAngleBetweenTwoVectors(u1, u2)
            % a = acos(dot(u1, u2) / (norm(u1) * norm(u2)));
            
            u1 = [u1; 0];
            u2 = [u2; 0];

            d = dot(u1, u2);
            c = cross(u1, u2);
            
            a = sign(c(3)) * atan2(norm(c), d);
            
            if isnan(a) || abs(a) < Tracker.EPS
                a = 0;
            end
        end
    end
    
    % Tracking
    methods
        function track(this)
            % Track objects
            
            if this.existOutputField('tracking')
                return
            end
            
            if ~this.existOutputField('classification')
                this.classify();
            end
            
            load(this.filenames.output, 'classification');
            
            % properties
            uc = this.unmatchedCost; % unmatched/unknown cost
            d = 1; % delay/memory length instead of `this.delta`
            N = numel(classification.centroids); % number of frames
            
            memory = cell(d, 1); % memory
            centroids = cell(N, 1); % centroids
            matches = cell(N, 1); % matches
            translations = cell(N, 1); % translations
            rotations = cell(N, 1); % rotations
            
            fprintf('\nCompute object tags: ...\n');
            tic();
            
            % read first frames to memory
            for t1 = 1:d
                 C1 = classification.centroids{t1}(classification.labels{t1} == 1, :); % centroids of previous frame
                 memory{t1} = struct('t', t1, 'C', C1);
                 matches{t1} = struct('t', [], 'D', [], 'M', []); % todo: fixme: remove `D`
                 translations{t1} = [];
                 rotations{t1} = struct('center', [], 'angle', [], 'M', []);
                 
                 fprintf('Frame: %d, \tObjects: %d, \tSkipped\n', t1, size(C1, 1));
            end
            
            C1 = memory{1}.C;
            for t2 = (d + 1):N % time of current frame
                t1 = memory{1}.t; % time of previous frame
                
                L1 = classification.labels{t1} == 1; % labels of previous frame
                L2 = classification.labels{t2} == 1; % labels of current frame
                
                C2 = classification.centroids{t2}(L2, :); % centroids of next frame
                
                txt = sprintf('Frame: %d, \tObjects: %d', t2, size(C2, 1));
                
                if any(L1) && any(L2)
                    
                    % matching
                    R = rotations{t1};
                    M01 = matches{t1}.M;
                    
                    if isempty(M01)
                        D = Tracker.getCostMatrix(C1, C2);
                    else
                        T = zeros(size(C1));
                        T(M01(:, 2), :) = translations{t1};
                        
                        if ~isempty(R.M)
                            % rotate
                            RC1 = C1;
                            for j = 1:size(R.M, 1)
                                ind = R.M(j, 3);
                                % if R.angle(j) == 0 || (R.center(j, 1) == Tracker.INF && R.center(j, 2) == Tracker.INF)
                                if R.angle(j) == 0 || any(isinf(R.center(j, :)))
                                    RC1(ind, :) = C1(ind, :) + T(ind, :);
                                else
                                    RC1(ind, :) = Tracker.rotate(C1(ind, :)', R.angle(j), R.center(j, :)');
                                end
                            end

                            D = Tracker.getCostMatrix(RC1, C2);
                        else
                            D = Tracker.getCostMatrix(C1 + T, C2);
                        end
                    end
                    
                    M12 = matchpairs(D, uc);

                    % translations
                    T = Tracker.getTranslations(C1, C2, M12);
                    
                    % rotations
                    if isempty(M01)
                        R = struct('center', [], 'angle', [], 'M', []);
                    else
                        t0 = matches{t1}.t;
                        C0 = centroids{t0};
                        R = Tracker.getRotations(C0, C1, C2, M01, M12);
                    end

                    memory(1) = [];
                    memory{d} = struct('t', t2, 'C', C2);
                    C1 = memory{1}.C;
                    
                    txt = [txt, ...
                        sprintf('\tMatched: %d, \tUnmatched: %d\n', ...
                        size(M12, 1), size(C2, 1) - size(M12, 1))];
                elseif ~any(L1)
                    M12 = [];
                    t1 = [];
                    T = [];
                    R = struct('center', [], 'angle', [], 'M', []);
                    
                    memory(1) = [];
                    memory{d} = struct('t', t2, 'C', C2);
                    C1 = memory{1}.C;
                    
                    txt = [txt, '\tSkipped\n'];
                else
                    M12 = [];
                    t1 = [];
                    T = [];
                    R = struct('center', [], 'angle', [], 'M', []);
                    
                    txt = [txt, '\tSkipped\n'];
                end
                
                fprintf(txt);
                
                centroids{t2} = C2;
                matches{t2} = struct('t', t1, 'M', M12);
                translations{t2} = T;
                rotations{t2} = R;
            end
            
            fprintf('\nFile `%s` saved: ', this.filenames.output);
            tracking.centroids = centroids;
            tracking.matches = matches;
            tracking.translations = translations;
            tracking.rotations = rotations;
            save(this.filenames.output, 'tracking', '-append');
            toc();
        end
        
        function tags = makeTags(this)
            
            if this.existOutputField('tags')
                return
            end
            
            if ~this.existOutputField('tracking')
                this.track();
            end
            
            load(this.filenames.output, 'classification', 'tracking');
            
            nt = numel(classification.labels); % number of times/frames
            tags = cell(nt, 1);
            
            nextTag = 1;
            for t2 = 1:nt
                C = tracking.centroids{t2};
                nc = size(C, 1); % number of centroids
                
                tags{t2} = nan(nc, 1);
                
                M = tracking.matches{t2}.M;
                nm = size(M, 1); % number of matches
                
                if nm == 0
                    continue
                end
                
                t1 = tracking.matches{t2}.t;
                for i = 1:nm
                    if isnan(tags{t1}(M(i, 1)))
                        tags{t2}(M(i, 2)) = nextTag;
                        nextTag = nextTag + 1;
                    else
                        tags{t2}(M(i, 2)) = tags{t1}(M(i, 1));
                    end
                end
            end
            
            for t = 1:nt
                if ~isempty(tags{t})
                    L = classification.labels{t} == 1;
                    
                    tmp = nan(numel(L), 1);
                    tmp(L) = tags{t};
                    
                    tags{t} = tmp;
                end
            end
            
            save(this.filenames.output, 'tags', '-append');
        end
        
        function pathes = findPathes(~, matches)
            % Find pathes
            
            T = numel(matches);
            times = true(T, 1);
            pathes = {};
            
            while true
                t = find(times, 1, 'last');
                
                if isempty(t)
                    break;
                end
                
                pathes{end + 1} = t;
                times(t) = false;
                
                while true
                    t = matches{t}.t;
                    
                    if isempty(t)
                        break;
                    end
                    
                    pathes{end}(end + 1) = t;
                    times(t) = false;
                end
                
                pathes{end} = sort(pathes{end});
            end
        end
        
        function tags = findTags(~, centroids, matches, path)
            % Find tags
            
            T = numel(centroids);
            tags = cell(T, 1);
            
            % first time
            t = path(1);
            C = centroids{t};
            nc = size(C, 1); % number of centroids 
            tags{t} = (1:nc)';
            nextTag = nc + 1;
            
            for i = 2:numel(path)
                t_ = path(i - 1);
                t = path(i);
                
                
                M = matches{t}.M;
                nm = size(M, 1); % number of matches
                
                C = centroids{t};
                nc = size(C, 1); % number of centroids
                
                tags{t} = nan(nc, 1);
                for j = 1:nm
                    if isnan(tags{t_}(M(j, 1)))
                        tags{t_}(M(j, 1)) = nextTag;
                        nextTag = nextTag + 1;
                    end
                    
                    tags{t}(M(j, 2)) = tags{t_}(M(j, 1));
                end
            end
        end
    end
    
    methods (Static)
        function C = getCentroids(I, T)
            BW = imbinarize(rgb2gray(I), T); % binary image

            C = regionprops(BW, 'Centroid');
            C = [C.Centroid];
            C = reshape(C, 2, [])';
        end
        
        function D = getCostMatrix(C1, C2)
            n1 = size(C1, 1);
            n2 = size(C2, 1);
            D = zeros(n1, n2);
            for i = 1:n1
              D(i,:) = vecnorm([C1(i, 1) - C2(:, 1), C1(i, 2) - C2(:, 2)], 2, 2)';
            end
        end
        
        function TC = getTotalCost(D, M)
            % assigned cost
            AC = sum(D(sub2ind(size(D), M(:,1), M(:,2))));
            % unassigned cost
            UC = costUnmatched * (sum(size(Cost)) - 2 * size(M,1));
            % total cost
            TC = AC + UC;
        end
        
        function T = getTranslations(C1, C2, M)
            % Get tranlation vectors
            T = C2(M(:, 2), :) - C1(M(:, 1), :); % [dx, dy]
        end
    end
    
    % Classification Performance
    methods
        function cp = getClassificationPerformance(this)
            
            if ~this.existOutputField('classification')
                this.classify();
            end
            
            load(this.filenames.output, 'classification');
            
            d = this.delta;
            
            dr = DataReader(this.filenames.data);
            N = dr.N;
            
            TPR = nan(N, 1);
            TNR = nan(N, 1);
            UNK = nan(N, 1);
            
            for i = (d + 1):N
                y_ = classification.labels{i};
                n = numel(y_);
                
                if n == 0
                    continue;
                end
                
                y = zeros(n, 1);
                y(dr.idx.obj{i}) = 1;
                
                P = sum(y == 1);
                if P
                    TPR(i) = sum(y_ == 1 & y == 1) / sum(y == 1);
                else
                    TPR(i) = 1;
                end
                
                TNR(i) = sum(y_ == 0 & y == 0) / sum(y == 0);
                UNK(i) = sum(isnan(y_))/ n;
            end
            
            cp = struct(...
                'TPR', struct('mean', nanmean(TPR), 'std', nanstd(TPR)), ...
                'TNR', struct('mean', nanmean(TNR), 'std', nanstd(TNR)), ...
                'UNK', struct('mean', nanmean(UNK), 'std', nanstd(UNK)));
        end
        
        function plotClassificationAccuracy(this, ul)
            
            figureName = sprintf('classification-accuracy-ul-%d', ul);
            
            if this.openFigure(figureName)
                return
            end
            
            cp = this.getClassificationPerformance1(ul);
            
            edgeColor = 'none';
            faceAlpha = 0.9;
            
            DataReader.createFigure('Classification - Accuracy');
            area(cp.ACC, ...
                'DisplayName', 'Accuracy', ...
                'EdgeColor', edgeColor, ...
                'FaceAlpha', faceAlpha);
            
            if ul
                title('Unknonws are Objects');
            else
                title('Unknonws are Stars');
            end
                
            xlabel('Frame')
            ylabel('Accuracy');
            
            nf = numel(cp.ACC); % number of frames
            xticks(unique([1, this.delta, nf]));

            ylim([0.95, 1]);
            yticks([0.95, 0.99, 1]);
            box('off');
            Tracker.setFontSize();
            
            this.saveFigure(figureName);
        end
        
        function plotUnknonwNumbers(this)
            
            figureName = 'classification-unknonw-numbers';
            
            if this.openFigure(figureName)
                return
            end
            
            cp = this.getClassificationPerformance1();
            
            edgeColor = 'none';
            faceAlpha = 0.9;
            
            DataReader.createFigure('Classification - Number of Unknonws');
            area(cp.NO, ...
                'DisplayName', 'Target Objects', ...
                'EdgeColor', edgeColor, ...
                'FaceAlpha', faceAlpha);
            hold('on');
            area(cp.NO_, ...
                'DisplayName', 'Output Objects', ...
                'EdgeColor', edgeColor, ...
                'FaceAlpha', faceAlpha);
            area(cp.NU, ...
                'DisplayName', 'Output Unknonws', ...
                'EdgeColor', edgeColor, ...
                'FaceAlpha', faceAlpha);
            legend();
            
            title('');
            xlabel('Frame')
            ylabel('Number');
            
            nf = numel(cp.NO); % number of frames
            xticks(unique([1, this.delta, nf]));

            axis('tight');
            box('off');
            Tracker.setFontSize();
            
            this.saveFigure(figureName);
        end
        
        function plotConfusionMatrix(this, ul)
            
            figureName = sprintf('classification-confusion-matrix-ul-%d', ul);
            
            if this.openFigure(figureName)
                return
            end
            
            cp = this.getClassificationPerformance1(ul);
            d = this.delta;
            
            y = cell2mat(cp.Y((d + 1):end));
            y_ = cell2mat(cp.Y_((d + 1):end));
            
            % DataReader.createFigure('Classification - Confusion Matrix');
            figure('Name', 'Classification - Confusion Matrix', 'Color', [1, 1, 1]);
            
            cm = confusionchart(y, y_);
            cm.ColumnSummary = 'column-normalized';
            cm.RowSummary = 'row-normalized';
            % cm.ClassLabels = {'Star', 'Object'};
            
            % plotconfusion(y', y_')
            
            if ul
                title('Unknonws are Objects');
            else
                title('Unknonws are Stars');
            end
            
            Tracker.setFontSize();
            
            this.saveFigure(figureName);
        end
    end
    
    % Viz
    methods
        function makeClassifiedVideo(this, tags)
            
            if exist('tags', 'var')
                filename = this.filenames.trackedVideo;
            else
                filename = this.filenames.classifiedVideo;
            end
            
            if isfile(filename)
                return
            end
            
            fprintf('\nMake classified video: ...\n');
            tic();
            
            vr = VideoReader(this.filenames.video);
            width = vr.Width;
            height = vr.Height;
            fps = vr.FrameRate;
            
            vw = VideoWriter(filename, 'MPEG-4');
            vw.FrameRate = fps;
            open(vw);
            
            if this.existOutputField('classification')
                this.classify();
            end
            
            load(this.filenames.output, 'classification');
            
            T = numel(classification.labels);
            
            if nargin < 2
                tags = cell(T, 1);
            end
            
            for t = 1:T
                I = zeros(height, width, 3);
                l = classification.labels{t};
                c = classification.centroids{t};
                
                txt = sprintf('Frame: %d, Spots: %d', t, size(c, 1));
                
                if isempty(l)
                    % spots
                    I = drawSpots(I, c, [1, 1, 1]);
                    
                    % title
                    txt = sprintf('%s, Skipped', txt);
                else
                    % unknow
                    I = drawSpots(I, c(isnan(l), :), [1, 0, 1]);
                    % stars
                    I = drawSpots(I, c(l == 0, :), [1, 1, 1]);
                    % objects
                    I = drawSpots(I, c(l == 1, :), [1, 0, 0]);

                    % title
                    txt = sprintf(...
                        '%s, Objects: %d, Unknown: %d', ...
                        txt, sum(l == 1), sum(isnan(l)));
                end
                
                % tracking
                if ~isempty(tags{t}) && ~isempty(l)
                    idx = ~isnan(tags{t}) & (l == 1);
                    
                    if any(idx)
                        position = c(idx, :);
                        text = cellstr(string(tags{t}(idx)));
                        
                        I = insertText(...
                            I, ...
                            position, ...
                            text, ...
                            'Font', 'LucidaTypewriterBold', ...
                            'TextColor', [1, 1, 1], ...
                            'BoxOpacity', 0.4);
                    end
                end
                
                I = insertText(...
                    I, ...
                    [10, 10], ...
                    txt, ...
                    'FontSize', 24, ...
                    'BoxColor', [1, 1, 0], ...
                    'BoxOpacity', 0.4, ...
                    'TextColor', [1, 1, 1]);
            
                writeVideo(vw, I);
                
                disp(txt);
            end
            
            close(vw);
            
            fprintf('\nFile `%s` saved: ', filename);
            toc();
            
            % implay(filename);
            
            % Local functions
            function I = drawSpots(I, position, color)
                r = 5;
                opacity = 0.7;
                
                position = [position, r * ones(size(position, 1), 1)];
                
                I = insertShape(I, ...
                    'FilledCircle', position, ...
                    'Color', color, ...
                    'Opacity', opacity ...
                );
            end
        end
        
        function saveFigure(this, name)
            % name = sprintf('%s-%s', name, this.getPostfix());
            saveas(gcf(), fullfile(this.folders.results, [name, Tracker.FIGURE_TYPE]));
        end
        
        function tf = openFigure(this, name)
            % name = sprintf('%s-%s', name, this.getPostfix());
            
            filename = fullfile(this.folders.results, [name, Tracker.FIGURE_TYPE]);
            if isfile(filename)
                switch Tracker.FIGURE_TYPE
                    case '.fig'
                        uiopen(filename, 1);
                    case '.png'
                        imshow(filename);
                end
                tf = true;
                return
            end
            
            tf = false;
        end
    end
    
    % Main
    methods (Static)
        function main()
            close('all');
            clc();
            
            % Properties
            binarizationThreshold = 0.1;
            unmatchedCost = 1000;
            maxNumObjects = 10;
            delta = 1;
            isTranslationMagnitude = true;
            isTranslationAngle = true;
            isRotationCenter = true;
            isRotationAngle = false;
            
            listing = dir(fullfile(Tracker.DATA_FOLDER, '*.mp4'));
            parfor i = 1:numel(listing)
                try
                    filename = fullfile(listing(i).folder, listing(i).name);
                    fprintf('%>>> d - %s\n', i, filename);
                    
                    % Tracker
                    tracker = Tracker(...
                        filename, ...
                        binarizationThreshold, ...
                        unmatchedCost, ...
                        maxNumObjects, ...
                        delta, ...
                        isTranslationMagnitude, ...
                        isTranslationAngle, ...
                        isRotationCenter, ...
                        isRotationAngle);

                    % Classification
                    tracker.classify();
                    tracker.makeClassifiedVideo();

                    % Classification performance

                    tracker.plotClassificationAccuracy(0);
                    tracker.plotClassificationAccuracy(1);
                    tracker.plotUnknonwNumbers();
                    tracker.plotConfusionMatrix(0);
                    tracker.plotConfusionMatrix(1);
                    
                    % Tracking
                    tracker.track();

                    % Output
                    tracker.makeTags();
                    tags = getfield(load(tracker.filenames.output, 'tags'), 'tags');
                    tracker.makeClassifiedVideo(tags);
                    
                    close('all');
                catch ME
                    warning(filename);
                    warning(ME.message);
                end
            end
        end
    end
    
    % Helper
    methods
        function tf = existOutputField(this, field)
            tf = false;
            
            if isfile(this.filenames.output)
                info = who('-file', this.filenames.output);
                if ismember(field, info)
                    tf = true;
                end
            end
        end
    end
    
    methods (Static)
        function nan2one()
            filename = './assets/results/output.mat';
            
            load(filename, 'labels');
            
            for i = 1:numel(labels)
                labels{i}(isnan(labels{i})) = 1;
            end
            
            save(filename, 'labels', '-append');
        end
        
        function C = nanor(A, B)
            n = numel(A);
            C = zeros(n, 1);
            
            for i = 1:n
                a = A(i);
                b = B(i);
                
                if isnan(a)
                    c = b;
                elseif isnan(b)
                    c = a;
                else
                    c = a | b;
                end
                
                C(i) = c;
            end
        end
        
        function resultsFolder = getResultsFolder(filename)
            
            [~, name] = fileparts(filename);
            resultsFolder = fullfile(Tracker.ASSETS_FOLDER, 'results', name);    
            
            if ~exist(resultsFolder, 'dir')
                mkdir(resultsFolder);
            end
        end
        
        function setFontSize()
            set(gca, 'FontSize', 18);
        end
    end
end
