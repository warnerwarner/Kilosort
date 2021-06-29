function Wrot = get_whitening_matrix(rez)
    % based on a subset of the data, compute a channel whitening matrix
    % this requires temporal filtering first (gpufilter)
    
    ops = rez.ops;
    Nbatch = ops.Nbatch;
    twind = ops.twind;
    NchanTOT = ops.NchanTOT;
    NT = ops.NT;
    NTbuff = ops.NTbuff;
    chanMap = ops.chanMap;
    Nchan = rez.ops.Nchan;
    xc = rez.xc;
    yc = rez.yc;
    
    % load data into patches, filter, compute covariance
    if isfield(ops,'fslow')&&ops.fslow<ops.fs/2
        [b1, a1] = butter(3, [ops.fshigh/ops.fs,ops.fslow/ops.fs]*2, 'bandpass');
    else
        [b1, a1] = butter(3, ops.fshigh/ops.fs*2, 'high');
    end
    
    fprintf('Getting channel whitening matrix... \n');
    CC = gpuArray.zeros( Nchan,  Nchan, 'single'); % we'll estimate the covariance from data batches, then add to this variable
    
    
    ibatch = 1;
    while ibatch<=Nbatch
        offset = max(1, twind + ((NT - ops.ntbuff) * (ibatch-1) - 2*ops.ntbuff));
        buff = h5read(ops.fbinary, '/sig', [offset 1], [NTbuff NchanTOT]);
    
        buff = buff'; % Transpose it so that it is channels x time and works for the rest of the script
        if isempty(buff)
            break;
        end
        nsampcurr = size(buff,2);
        if nsampcurr<NTbuff
            buff(:, nsampcurr+1:NTbuff) = repmat(buff(:,nsampcurr), 1, NTbuff-nsampcurr);
        end
    
        datr    = gpufilter(buff, ops, rez.ops.chanMap); % apply filters and median subtraction
    
        CC        = CC + (datr' * datr)/NT; % sample covariance
    
        ibatch = ibatch + ops.nSkipCov; % skip this many batches
    end
    CC = CC / ceil((Nbatch-1)/ops.nSkipCov); % normalize by number of batches
    
    
    if ops.whiteningRange<Inf
        % if there are too many channels, a finite whiteningRange is more robust to noise in the estimation of the covariance
        ops.whiteningRange = min(ops.whiteningRange, Nchan);
        Wrot = whiteningLocal(gather(CC), yc, xc, ops.whiteningRange); % this function performs the same matrix inversions as below, just on subsets of channels around each channel
    else
        Wrot = whiteningFromCovariance(CC);
    end
    Wrot    = ops.scaleproc * Wrot; % scale this from unit variance to int 16 range. The default value of 200 should be fine in most (all?) situations.
    
    fprintf('Channel-whitening matrix computed. \n');
    