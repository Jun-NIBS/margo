function [trackDat] = autoTrack(trackDat,expmt,gui_handles)
% This function is the core tracking routine of MARGO and consists of:
% 
%   A. Image Processing:
%
%       1. Vignette correct current frame and background reference
%       2. Subtract background to create difference image
%       3. Binarize by thresholding difference image
%       4. Use ROI masks to set non-ROI parts of image to zero
%       5. Blob dilation/erosion (optional) to stitch neighboring blobs
%
%   B. Noise Measurement:
%
%       1. Count above-threshold pixel number
%       2. Compare to baseline pixel distribution during noise sampling
%       3. Skip current frame if above threshold pixel number is too far
%          above baseline (7 standard deviations)
%
%   C. Tracking:
%
%       1. Extract blob areas and remove blobs too small or big
%       2. Get blob features via regionprops (features specified by in_fields)
%       3. Find blob to trace index permutation according to one of two modes:
%           - Single Track:   max one tracked object per ROI
%           - Multi Track:    up to nTracesPerROI objects in each ROI
%       4. Apply permutation to all output fields and update data to record
%          in trackDat
%
% ----------------------------------------------------------------------%

% increment frame counter
trackDat.ct = trackDat.ct + 1;

prop_fields = trackDat.prop_fields;
% add BoundingBox as a field if dilate/erode mode
if expmt.parameters.dilate_sz > 0 || expmt.parameters.erode_sz > 0
    prop_fields = [prop_fields; {'BoundingBox'}];
end


% calculate difference image and current for vignetting
switch expmt.parameters.bg_mode
    case 'light'
        trackDat.diffim = trackDat.ref.im - trackDat.im;
    case 'dark'
        trackDat.diffim = trackDat.im - trackDat.ref.im;
end


% get current image threshold and use it to extract region properties     
im_thresh = get(gui_handles.track_thresh_slider,'value');

% adjust difference image to enhance contrast
if expmt.parameters.bg_adjust
    diffim_upper_bound = double(max(trackDat.diffim(:)));
    diffim_upper_bound(diffim_upper_bound==0) = 255;
    trackDat.diffim = imadjust(trackDat.diffim, [0 diffim_upper_bound/255], [0 1]);
end

% threshold difference image
trackDat.thresh_im = trackDat.diffim > im_thresh;
if trackDat.has.roi_mask
    % set pixels outside ROIs to zero
    trackDat.thresh_im = trackDat.thresh_im & expmt.meta.roi.mask;
end

% check image noise and dump frame if noise is too high
record = true;

if trackDat.has.px_dist && expmt.parameters.noise_sample

    % update rolling distribution and calculate deviation from baseline
    idx = mod(trackDat.ct,length(trackDat.px_dist))+1;
    trackDat.px_dist(idx) = sum(trackDat.thresh_im(:));
    trackDat.px_dev(idx) = ((nanmean(trackDat.px_dist) - ...
            expmt.meta.noise.mean)/expmt.meta.noise.std);

    % query skip threshold or assign default
    if ~trackDat.has.noise_skip_thresh
        expmt.parameters.noise_skip_thresh = 9;
    end
    if trackDat.px_dev(idx) > expmt.parameters.noise_skip_thresh
        record = false;
    end
end

% do tracking if frame is clean
if record

    % check optional blob dilation/erosion
    if trackDat.has.dilate_sz &&...
            (expmt.parameters.dilate_sz || expmt.parameters.erode_sz)

        if ~isfield(expmt.parameters,'dilate_element') ||...
                isempty(expmt.parameters.dilate_element) ||...
                expmt.parameters.dilate_element.Dimensionality ~= expmt.parameters.dilate_sz
            expmt.parameters.dilate_element = ...
                strel('disk',expmt.parameters.dilate_sz);
        end
        if ~isfield(expmt.parameters,'erode_element') ||...
                isempty(expmt.parameters.erode_element) ||...
                expmt.parameters.erode_element.Dimensionality ~= expmt.parameters.erode_sz
            expmt.parameters.erode_element = ...
                strel('disk',expmt.parameters.erode_sz);
        end

        % dilate foreground image blobs
        if expmt.parameters.dilate_sz
            trackDat.thresh_im = imdilate(trackDat.thresh_im,expmt.parameters.dilate_element);
        end
        % erode foreground image blobs
        if expmt.parameters.erode_sz
            trackDat.thresh_im = imerode(trackDat.thresh_im, expmt.parameters.erode_element);
        end         
    end

    % get region properties
    cc = bwconncomp(trackDat.thresh_im, 4);
    area = cellfun(@numel,cc.PixelIdxList);

    % threshold blobs by area
    below_min = area  .* (expmt.parameters.mm_per_pix^2) < ...
        expmt.parameters.area_min;
    above_max = area .* (expmt.parameters.mm_per_pix^2) >...
        expmt.parameters.area_max;
    oob = below_min | above_max;
    if any(oob)
        cc.PixelIdxList(oob) = [];
        cc.NumObjects = cc.NumObjects - sum(oob);
        area(oob) = [];
    end

    % extract blob properties
    props=regionprops(cc, prop_fields);

    % track objects
    switch expmt.meta.track_mode

        % track multiple objects per roi
        case 'multitrack'
            [trackDat, expmt, props] = multiTrack(props, trackDat, expmt);
            trackDat.centroid = cat(1,trackDat.traces.cen);
            update = cat(1,trackDat.traces.updated);
            permutation = cat(2,trackDat.permutation{:})';

        % track one object per roi
        case 'single'
            raw_cen = cat(1,props.Centroid);
            % Match centroids to last known centroid positions
            [permutation,update,raw_cen] = sortCentroids(raw_cen,trackDat,expmt);

            % Apply speed threshold to centroid tracking
            speed = NaN(size(update));

            if any(update)
                % calculate distance and convert from pix to mm
                d = sqrt((raw_cen(permutation,1)-trackDat.centroid(update,1)).^2 ...
                         + (raw_cen(permutation,2)-trackDat.centroid(update,2)).^2);
                d = d .* expmt.parameters.mm_per_pix;

                % time elapsed since each centroid was last updated
                dt = trackDat.t - trackDat.tStamp(update);

                % calculate speed and exclude centroids over speed threshold
                tmp_spd = d./dt;
                above_spd_thresh = tmp_spd > expmt.parameters.speed_thresh;
                permutation(above_spd_thresh)=[];
                update(update) = ~above_spd_thresh;
                speed(update) = tmp_spd(~above_spd_thresh);
            end

            % Use permutation vector to sort raw centroid data and update
            % vector to specify which centroids are reliable and should be updated
            trackDat.centroid(update,:) = single(raw_cen(permutation,:));
            cen_cell = num2cell(single(raw_cen(permutation,:)),2);
            [trackDat.traces(update).cen] = cen_cell{:};
            trackDat.tStamp(update) = trackDat.t;
            if trackDat.record.weightedCentroid
                raw_cen = reshape([props.WeightedCentroid],2,...
                    length([props.WeightedCentroid])/2)';
                trackDat.weightedCentroid(update,:) = ...
                    single(raw_cen(permutation,:));
            end

            % update centroid drop count for objects not updated this frame
            if trackDat.has.drop_ct
                trackDat.drop_ct(~update) = trackDat.drop_ct(~update) + 1;
            end

            trackDat = singleTrack_updateDuration(...
                trackDat,update,expmt.parameters.max_trace_duration);

    end
    trackDat.update = update;
    trackDat.dropped_frames = ~update;
else

    % increment drop count for all objects if entire frame is dropped   
    trackDat.drop_ct = trackDat.drop_ct + 1;
    trackDat.update = false(size(trackDat.drop_ct));
    trackDat.dropped_frames(:) = false;
end
    
%% Assign outputs

% assign any optional sorted output fields to the trackDat
% structure if listed in expmt.meta.fields. 
% return NaNs if record = false
expmt.meta.num_frames = trackDat.ct;
expmt.meta.num_dropped = trackDat.drop_ct;
if trackDat.record.speed
    if record
        if exist('speed','var')
            trackDat.speed = single(speed);
        else
            trackDat.speed = cat(1,trackDat.traces.speed);
        end
    else
        trackDat.speed = single(NaN(size(trackDat.centroid,1),1)); 
    end
end

if trackDat.record.area
    tmp_area = NaN(size(trackDat.centroid,1),1);
    if record
        tmp_area(update) = area(permutation);
    end
    trackDat.area = single(tmp_area .* (expmt.parameters.mm_per_pix^2));
end

if trackDat.record.orientation
    orientation = NaN(size(trackDat.centroid,1),1);
    if record
        orientation(update) = [props(permutation).Orientation];
    end
    trackDat.orientation = single(orientation);
end

if trackDat.record.pixelIdxList
    pxList = cell(size(trackDat.centroid,1),1);
    if record
        pxList(update) = {props(permutation).PixelIdxList};
    end
    trackDat.pixelIdxList = (pxList);
end

if trackDat.record.majorAxisLength
    maLength = NaN(size(trackDat.centroid,1),1);
    if record
        maLength(update) =[props(permutation).MajorAxisLength];
    end
    trackDat.majorAxisLength = single(maLength .* expmt.parameters.mm_per_pix);
end

if trackDat.record.minorAxisLength
    miLength = NaN(size(trackDat.centroid,1),1);
    if record
        miLength(update) =[props(permutation).MinorAxisLength];
    end
    trackDat.minorAxisLength = single(miLength .* expmt.parameters.mm_per_pix);
end

if trackDat.record.time
    trackDat.time = single(trackDat.ifi);
end

if trackDat.record.VideoData
    trackDat.VideoData = trackDat.im;
end

if trackDat.record.VideoIndex
    trackDat.VideoIndex = trackDat.ct;
end

