function varargout = run_basictracking(expmt,gui_handles,varargin)
%
% This is a blank experimental template to serve as a framework for new
% custom experiments. The function takes the master experiment struct
% (expmt) and the handles to the gui (gui_handles) as inputs and outputs
% the data assigned to out. In this example, object centroid, pixel area,
% and the time of each frame are output to file.

%% Parse variable inputs

for i = 1:length(varargin)
    
    arg = varargin{i};
    
    if ischar(arg)
        switch arg
            case 'Trackdat'
                i=i+1;
                trackDat = varargin{i};     % manually pass in trackDat rather than initializing
        end
    end
end

%% Initialization: Get handles and set default preferences

gui_notify(['executing ' mfilename '.m'],gui_handles.disp_note);

% clear memory
clearvars -except gui_handles expmt

% get handles
gui_fig = gui_handles.gui_fig;                            % gui figure handle
imh = findobj(gui_handles.axes_handle,'-depth',3,'Type','image');   % image handle


%% Experimental Setup
    
% Initialize reference stack
ref_stack = repmat(expmt.ref, 1, 1, gui_handles.edit_ref_depth.Value);

% properties of the tracked objects to be recorded
trackDat.fields={'Centroid';'Time'};                 

% initialize labels, files, and cam/video
[trackDat,expmt] = autoInitialize(trackDat,expmt,gui_handles);

% lastFrame = false until last frame of the last video file is reached
trackDat.lastFrame = false;


%% Main Experimental Loop

% initialize previous frame time stamp
tPrev = toc;

% initialize centroid markers
clean_gui(gui_handles.axes_handle);
hold on
hMark = plot(trackDat.Centroid(:,1),trackDat.Centroid(:,2),'ro');
hold off

% run experimental loop until duration is exceeded or last frame
% of the last video file is reached
while ~trackDat.lastFrame
    
    % update time stamps and frame rate
    [trackDat, tPrev] = updateTime(trackDat, tPrev, expmt, gui_handles);

    % Take single frame
    if strcmp(expmt.source,'camera')
        
        % grab frame from camera
        trackDat.im = peekdata(expmt.camInfo.vid,1);
        
    else
        % get next frame from video file
        [trackDat.im, expmt.video] = nextFrame(expmt.video,gui_handles);
        
        % stop expmt when last frame of last video is reached
        if isfield(expmt.video,'fID')
            trackDat.lastFrame = feof(expmt.video.fID);
        elseif ~hasFrame(expmt.video.vid) && expmt.video.ct == expmt.video.nVids
            trackDat.lastFrame = true;
        end
        
    end

    % ensure that image is mono
    if size(trackDat.im,3)>1
        trackDat.im=trackDat.im(:,:,2);
    end

    % track, sort to ROIs, output optional fields set during intialization
    % and compare noise to the noise distribution measured during sampling
    trackDat = autoTrack(trackDat,expmt,gui_handles);



    % output data tracked fields to binary files
    for i = 1:length(trackDat.fields)
        precision = class(trackDat.(trackDat.fields{i}));
        fwrite(expmt.(trackDat.fields{i}).fID,trackDat.(trackDat.fields{i}),precision);
    end

    % update ref at the reference frequency or reset if noise thresh is exceeded
    [trackDat, ref_stack, expmt] = updateRef(trackDat, ref_stack, expmt, gui_handles);

    % display update
    if gui_handles.display_menu.UserData ~= 5
        
        % set image data
        updateDisplay(trackDat, expmt, imh, gui_handles);

        % update centroid mark position
        hMark.XData = trackDat.Centroid(:,1);
        hMark.YData = trackDat.Centroid(:,2);
    end
    
    % force immediate screen drawing and callback evaluation
    drawnow limitrate                 
    
    % listen for gui pause/unpause
    while gui_handles.pause_togglebutton.Value || gui_handles.stop_pushbutton.UserData.Value
        [expmt,tPrev,exit] = updatePauseStop(trackDat,expmt,gui_handles);
        if exit
            return
        end
    end
        
    % optional: save vid data to file if record video menu item is checked
    if ~isfield(expmt,'VideoData') && strcmp(gui_handles.record_video_menu.Checked,'on')
        [trackDat,expmt] = initializeVidRecording(trackDat,expmt,gui_handles);
    elseif isfield(expmt,'VideoData')
        writeVideo(expmt.VideoData.obj,trackDat.im);
    end
    
end


%% post-experiment wrap-up

if finish
    
    % % auto process data and save master struct
    expmt = autoFinish(trackDat, expmt, gui_handles);

end

for i=1:nargout
    switch i
        case 1, varargout(i) = expmt;
        case 2, varargout(i) = trackDat;
    end
end

