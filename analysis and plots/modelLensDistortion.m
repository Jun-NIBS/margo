function expmt = modelLensDistortion(expmt)


% query available memory to determine how many batches to process data in
[bsz, nBatch] = getBatchSize(expmt, 4);


if expmt.meta.num_frames > 10000
    smpl = sort(randperm(expmt.meta.num_frames,10000));
else
    smpl = 1:expmt.meta.num_frames;
end

reset(expmt);

% intialize cam center coords for distance calculation
cc = [size(expmt.meta.ref.im,2)/2 size(expmt.meta.ref.im,1)/2]; 
cam_dist = squeeze(sqrt((expmt.data.centroid.raw(smpl,1,:)-cc(1)).^2 +...
    (expmt.data.centroid.raw(smpl,2,:)-cc(2)).^2));

detach(expmt.data.centroid);
spd = expmt.data.speed.raw(smpl,:);
reset(expmt);

% find adaptive speed threshold
[spd_thresh,~,~] = fitBimodalHist(log(spd));
spd_thresh = exp(spd_thresh);
spd_thresh = 0;
filt = ~isnan(spd) & spd>spd_thresh;

if any(filt)
    lm = fitlm(cam_dist(filt),spd(filt),'linear');
    expmt.meta.speed.model = lm;
else
    warning('Could not fit speed regression model. Not enough valid data points');
    return
end

if (lm.Coefficients{2,4})<0.05
    f = 'regressed_speed';
    nf = expmt.meta.num_frames;
    pre_existing = addRawDataFiles(f, expmt);
    if pre_existing
        return
    end
    
    cc = [size(expmt.meta.ref.im,2)/2 size(expmt.meta.ref.im,1)/2]; 
    for j=1:nBatch    
        
        reset(expmt.data.centroid);
        reset(expmt.data.speed);
        % get x and y coordinates and normalize to camera center
        if j==nBatch
            idx = (j-1)*bsz+1:nf;
        else
            idx = (j-1)*bsz+1:j*bsz;
        end
        cam_dist = ...
            squeeze(sqrt((expmt.data.centroid.raw(idx,1,:)-cc(1)).^2 +...
                (expmt.data.centroid.raw(idx,2,:)-cc(2)).^2));
        spd = expmt.data.speed.raw(idx,:) - lm.Coefficients{2,1}.*cam_dist;
        fwrite(expmt.data.(f).fID, spd',expmt.data.(f).precision);
        clear cam_dist idx spd
    end
    fclose('all');
    reset(expmt);
end
clear lm

if isfield(expmt,'Gravity') && isfield(expmt.Gravity,'index')
    
    spd_table = table(expmt.meta.roi.cam_dist,expmt.Gravity.index',...
        'VariableNames',{'Center_Distance';'Gravity'});
    lm = fitlm(spd_table,'Gravity~Center_Distance');
    if (lm.Coefficients{2,4})<0.05
        expmt.Gravity.index = expmt.Gravity.index' - ...
            lm.Coefficients{2,1}.*expmt.meta.roi.cam_dist;
    end
     
    % re-initialize raw data maps to free memory
    reset(expmt);
end


clear spd_table cam_dist lm



