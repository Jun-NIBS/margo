function expmt = parseCeilingBouts(expmt)

% query available memory to determine how many batches to process data in
[umem,msz] = memory;
msz = msz.PhysicalMemory.Available;
switch expmt.Area.map.Format{1}
    case 'single', prcn = 4;
    case 'double', prcn = 8;
end

nbatch = msz / (prcn * expmt.nFrames * expmt.nTracks * 8 * 10);
if nbatch < 1
    bsz = floor(expmt.nFrames * nbatch);
else
    bsz = expmt.nFrames;
end

idx = round(linspace(1,expmt.nFrames,bsz));


hwb = waitbar(0,['processing trace 1 of ' num2str(expmt.nTracks)],'Name','Parsing floor/ceiling bouts');
thresh = NaN(expmt.nTracks,1);
ints = NaN(expmt.nTracks,1);
means = NaN(expmt.nTracks,2)';
sigmas = NaN(expmt.nTracks,2)';
expmt.Area.ceiling = false(expmt.nFrames,expmt.nTracks);
expmt.Area.floor = false(expmt.nFrames,expmt.nTracks);


for i = 1:expmt.nTracks
    
    if ishghandle(hwb)
        waitbar(i/expmt.nTracks,hwb,...
            ['processing trace ' num2str(i) ' of ' num2str(expmt.nTracks)]);
    end

    % find threshold for each individual
    moving = autoSlice(expmt,'Speed',i) > 0.8;
    a= autoSlice(expmt,'Area',i);
    a(~moving) = NaN;

    % find upper and lower area modes
    [tmp_i,tmp_means,tmp_sig] = fitBimodalHist(a);
    if ~isempty(tmp_i)
        ints(i) = tmp_i;
        means(:,i) = tmp_means;
        sigmas(:,i) = tmp_sig;
    end
    
    % parse data into arena ceiling and floor frames
    expmt.Area.ceiling(:,i) = a > ints(i);
    expmt.Area.floor(:,i) = a < ints(i);
    clear a moving

end

if ishghandle(hwb)
    delete(hwb);
end

% get gravity index
expmt.Gravity.index = (sum(expmt.Area.ceiling,1)-sum(expmt.Area.floor,1))'./...
    (sum(expmt.Area.ceiling,1)+sum(expmt.Area.floor,1))';   

