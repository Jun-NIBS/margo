% Creates a movie with tracking overlay from an expmt master struct and raw
% movie file of the tracking. Set overlay parameters. Set parameters for
% the tracking over. Browse to the expmt .mat file, accompanying movie
% file, and select a save path for output video.

% Parameters
cen_marker = 'o';           % centroid marker style
cen_color = 'r';        % centroid marker color
cen_size = 3;
trail_marker = '-';           % centroid marker style
trail_color = [1 .5 0];        % centroid marker color
trail_length = 30;        % centroid trail length (number of frames)
frame_rate = 60;        % output frame rate

%% get file paths

[ePath,eDir] = uigetfile('*.mat','Select a expmt .mat file containing centroid traces');
load([eDir,ePath]);
[movPath,movDir] = uigetfile({'*.avi;*.mp4;*.mov'},'Select accompanying raw movie file',eDir);
savePath = [movDir expmt.meta.path.name '_track_overlay'];
[SaveName,SaveDir] = uiputfile({'*.avi';'*.mov';'*.mp4'},'Select path and file name for output movie',savePath);



%%

% intialize video objects
rVid = VideoReader([movDir,movPath]);
wVid = VideoWriter([SaveDir,SaveName],'Motion JPEG AVI');
wVid.FrameRate = frame_rate;
wVid.Quality = 100;
if expmt.meta.num_frames ~= rVid.NumberOfFrames
    error('frame number mismatch between tracking and video files');
end

% find first frame with traces
attach(expmt);
max_n = 10000;
max_n(max_n>expmt.meta.num_frames) = expmt.meta.num_frames;
tmp_c = [expmt.data.centroid.raw(1:max_n,1,:);...
    expmt.data.centroid.raw(1:max_n,2,:)];
[r,~] = find(~isnan(tmp_c));
fr_offset = min(r);

% intialize axes and image
fh = figure('units','normalized','outerposition',[0 0 1 1]);
fh.Units = 'pixels';
fh.MenuBar = 'none';
fh.Name = 'Video Preview';
open(wVid);
fr = read(rVid,fr_offset);
oob = size(fr)' + 10;
imh = image(fr);
imh.CDataMapping = 'scaled';
colormap('gray');
ah = gca;
ah.Units = 'normalized';
ah.Position = [0 0 1 1];
set(ah,'Xtick',[],'YTick',[],'Units','pixels');
dim = ah.Position(3:4);
ah.Position(3) = ah.Position(4)*(rVid.Width/rVid.Height);
fh.Position(3) = ah.Position(3);
ah.Units = 'normalized';
axis equal tight
%ah.PlotBoxAspectRatioMode = 'manual';
ah.CLim = [0 255];
fh.Resize = 'off';

% initialize centroid markers
attach(expmt);
c = [expmt.data.centroid.raw(fr_offset,1,:);...
    expmt.data.centroid.raw(fr_offset,2,:)];
c_prev = c;
c(:,isnan(c(1,:))) = repmat(oob,1,sum(isnan(c(1,:))));
trail = repmat(c,1,1,trail_length);
trail = permute(trail,[3,2,1]);
xidx = 1:numel(trail)/2;
yidx = numel(trail)/2+1:numel(trail);
hold on
th = plot(trail(xidx),trail(yidx),trail_marker,'Color',trail_color,'Parent',ah,'LineWidth',2);
pause(0.01);
eh = th.Edge;
eh.ColorType = 'truecoloralpha';
trail_cdata = repmat(eh.ColorData,1,trail_length);
trail_cdata(4,:) = uint8(linspace(255,0,trail_length));
trail_cdata(4,1) = 0;
trail_cdata = repmat(trail_cdata,1,1,expmt.meta.num_traces);
trail_cdata = reshape(trail_cdata(:),4,numel(trail_cdata)/4);
set(eh,'ColorBinding','interpolated','ColorData',trail_cdata);
ch = plot(c(1,:),c(2,:),cen_marker,'Color',cen_color,...
    'Parent',ah,'LineWidth',2.5,'MarkerSize',cen_size);
pause(0.01);
ceh = ch.MarkerHandle;
ceh.EdgeColorType = 'truecoloralpha';
ceh.FaceColorData = ceh.EdgeColorData;
ceh.EdgeColorData = uint8([0;0;0;0]);
hold off


%%
ct = fr_offset;

while ct < expmt.meta.num_frames
    ct = ct+1;
    fr = read(rVid,ct);
    if size(fr,3)>1
        fr = fr(:,:,2);
    end
    imh.CData = fr;
    c = [expmt.data.centroid.raw(ct,1,:);...
        expmt.data.centroid.raw(ct,2,:)];
    prev_filt = ~isnan(c_prev(1,:));
    curr_filt = ~isnan(c(1,:));
    c_prev = c;
    c(:,~curr_filt) = repmat(oob,1,sum(~curr_filt));
    trail = circshift(trail,1,1);
    trail(1,:,1) = c(1,:)';
    trail(1,:,2) = c(2,:)';
    new_trace = curr_filt > prev_filt;
    dead_trace = prev_filt > curr_filt;
    if any(new_trace)
        trail(:,new_trace,:) = ...
            repmat(permute(c(:,new_trace),[3 2 1]),size(trail,1),1,1);
    elseif any(dead_trace)
        trail(:,dead_trace,:) = ...
            repmat(permute(oob,[3 2 1]),size(trail,1),sum(dead_trace),1);
    end

    ceh.VertexData(1,:) = c(1,:);
    ceh.VertexData(2,:) = c(2,:);
    th.XData = trail(xidx);
    th.YData = trail(yidx);
    drawnow
    im_out = getframe(ah);
    writeVideo(wVid,im_out.cdata);
end

close(wVid);
