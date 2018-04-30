function [FullChannels, thetaChannels, phiChannels, alphaChannels] = o_generate_5Gchannels(conf, nUsers,...
                    thetaUsers, phiUsers, NxPatch, NyPatch, freq, maxnChannelPaths)
% Boolean to check whether we have already selected the channels to remove
    % for each user    
    if conf.verbosity >= 1
        fprintf('=======================================================\n');
        fprintf('The channels were not assigned AoA:\n');
        fprintf('Assigning CDL-C 3GPP ETSI TR 38.901 compliant values...\n');
    end
    FullChannels = cell(1,nUsers);
    thetaChannels = ones(nUsers,maxnChannelPaths)*NaN;
    phiChannels = ones(nUsers,maxnChannelPaths)*NaN;
    alphaChannels = ones(nUsers,maxnChannelPaths)*NaN;
    for u=1:nUsers
        ZOD_LOS = thetaUsers(u);
        AOD_LOS = phiUsers(u);
        cdlChan = nr5gCDLChannel;
        cdlChan.SampleRate = 1760e6 / 1; %% SC-1760e6 sa/s, OFDM 2640e6 sa/s
        cdlChan.TransmitAntennaArray.Size = [NxPatch, NyPatch, 1, 1, 1];
        cdlChan.ReceiveAntennaArray.Size = [1, 1, 1, 1, 1];
        cdlChan.DelayProfile = 'CDL-C';
        cdlChan.DelaySpread = 100e-9;
        cdlChan.CarrierFrequency = freq;
        cdlChan.AngleScaling = true;
        cdlChan.MeanAngles = [AOD_LOS 180-AOD_LOS 90+ZOD_LOS 90-ZOD_LOS];
        disp(cdlChan.MeanAngles);
        cdlChan.MaximumDopplerShift = (5 / 3.6) / ...
            physconst('lightspeed') * freq; % 5km/h pedestrian    
        FullChannels{u} = s_phased_channel_SRM( ...
            'numInputElements_row',     NxPatch, ...
            'numInputElements_col',     NyPatch, ...
            'numOutputElements_row',    1, ...
            'numOutputElements_col',    1, ...
            'CDLChannel',               cdlChan);
        data = info(FullChannels{u}.CDLChannel);
        nPathsConsidered = min(maxnChannelPaths,length(data.AnglesAoD));
        thetaChannels(u,1:nPathsConsidered) = ZOD_LOS + ...
            (data.AnglesZoD(1:nPathsConsidered))-90;
        phiChannels(u,1:nPathsConsidered) = AOD_LOS + ...
            data.AnglesAoD(1:nPathsConsidered);
        FullChannels{u}.CDLChannel = cdlChan;
        alphaChannels(u,1:nPathsConsidered) = 10.^(data.AveragePathGains(1:nPathsConsidered)/10);
    end
    % We may need to delete some columns (same for three different vectors)
    [~,c] = find(isnan(thetaChannels));
    thetaChannels(:,c) = [];
    phiChannels(:,c) = [];
    alphaChannels(:,c) = [];
    if conf.verbosity >= 1
        fprintf('New elevations assigned:\n');
        disp(thetaChannels);
    end
    
    if conf.verbosity >= 1
        fprintf('New azimuths assigned:\n');
        disp(phiChannels);
    end
    
    if conf.verbosity >= 1
        fprintf('New gains assigned:\n');
        display(alphaChannels);
    end
end

