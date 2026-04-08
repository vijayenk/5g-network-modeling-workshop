classdef hNRCustomChannelModel
    %hNRCustomChannelModel Create a custom channel model as an array of link-level CDL channels

    %   Copyright 2022-2026 The MathWorks, Inc.

    properties (SetAccess=private)
        %PHYModel Physical layer model as "abstract-phy" or "full-phy"
        PHYModel = "abstract-phy"

        %PathlossMethod Pathloss type as "fspl" or "nrPathLoss"
        PathlossMethod = "fspl"

        %NRPathLossConfig NR path loss configuration as an object of type nrPathLossConfig
        % This property is only meaningful when property 'PathlossMethod' is set to value "nrPathLoss"
        NRPathLossConfig

        %ChannelModelMatrix Matrix of channel models for the links
        ChannelModelMatrix

        %MaxChannelDelayMatrix Matrix of maximum channel delay for the links
        MaxChannelDelayMatrix

        %PathFilter Matrix of path filters for the links
        PathFilter

        %ChannelFilter Matrix of channel filter objects for the links
        ChannelFilter

        %Los Binary matrix to store if line-of-sight (LOS) exists between transmitter and receiver
        Los
    end

    properties(Access=private)
        %PHYModelNum Representation of PHYModel as a number (To speed up runtime check of PHY flavor)
        % Values 1 and 0 represent that PHYModel is set to "abstract-phy" and
        % "full-phy", respectively.
        PHYModelNum

        %FilterContinuityStruct Structure of filter continuity options
        FilterContinuityStruct = struct('in',[],'g',[],'nSections',[],'idx',[],'canUseBatchMode',0);
    end

    methods
        % Constructor
        function obj = hNRCustomChannelModel(channelModelMatrix, varargin)
            % OBJ = hNRCustomChannelModel(CHANNELMODELMATRIX) creates a default
            % channel model. The default mode works with physical layer (PHY)
            % abstraction and assumes free-space-path-loss as pathloss type.
            %
            % CHANNELMODELMATRIX is a N-by-N array of link-level channels where N is
            % the number nodes
            %
            % OBJ = hNRCustomChannelModel(CHANNELMODELMATRIX, CHANNELCONFIGURATION)
            % creates a channel model where you can specify the PHY flavor and pathloss
            % type. CHANNELCONFIGURATION is a structure which can contain these fields.
            % PHYModel       - PHY abstraction method used. Value as
            %                  "abstract-phy" (for abstract PHY) or "full-phy" (for full
            %                  PHY). The default value is "abstract-phy".
            % PathlossMethod - Path loss method used. Value as "fspl" or
            %                  "nrPathLoss". The default value is "fspl".
            % PathlossConfig - Path loss configuration object used. Value of type
            %                  <a href="matlab:help('nrPathLossConfig')">nrPathLossConfig</a>

            if nargin > 1
                % Set PHY abstraction and pathloss type
                param = varargin{1};
                if isfield(param, 'PHYModel')
                    obj.PHYModel = param.PHYModel;
                end
                if isfield(param, 'PathlossMethod')
                    obj.PathlossMethod = param.PathlossMethod;
                end
                if strcmpi(obj.PathlossMethod, "nrPathLoss")
                    if isfield(param, 'PathlossConfig')
                        obj.NRPathLossConfig = param.PathlossConfig;
                    else
                        obj.NRPathLossConfig = nrPathLossConfig;
                        % Set the configuration as per urban macro scenario. See <a
                        % href="matlab:help('nrPathLossConfig')">nrPathLossConfig</a> for
                        % customizing the configuration
                        obj.NRPathLossConfig.Scenario = 'UMa';  % Urban macrocell
                        obj.NRPathLossConfig.EnvironmentHeight = 1; % Average height of the environment in UMa/UMi
                    end
                end
            end
            obj.PHYModelNum = ~strcmp(obj.PHYModel, "full-phy");
            obj.ChannelModelMatrix = channelModelMatrix;
            obj.MaxChannelDelayMatrix = zeros(size(obj.ChannelModelMatrix));
            obj.Los = zeros(size(obj.ChannelModelMatrix));
            for i=1:size(obj.ChannelModelMatrix,1)
                for j=1:size(obj.ChannelModelMatrix,2)
                    if ~isempty(obj.ChannelModelMatrix{i,j})
                        chInfo = info(obj.ChannelModelMatrix{i,j});
                        obj.MaxChannelDelayMatrix(i,j) = ceil(max(chInfo.PathDelays*obj.ChannelModelMatrix{i,j}.SampleRate)) + chInfo.ChannelFilterDelay;
                        [obj.ChannelFilter{i,j}, obj.PathFilter{i,j}] = getPathFilter(obj.ChannelModelMatrix{i,j});
                        kFactor = chInfo.KFactorFirstCluster; % dB
                        % Determine LOS between Tx and Rx based on Rician factor, K
                        obj.Los(i,j) = kFactor>-Inf;
                    end
                end
            end
        end

        function outputData = applyChannelModel(obj, rxInfo, txData)
            %applyChannelModel Apply the channel model to the transmitted data

            outputData = txData;
            if strcmp(obj.PathlossMethod, "fspl") % Free space pathloss
                distance = norm(txData.TransmitterPosition - rxInfo.Position);
                lambda = physconst('LightSpeed')/txData.CenterFrequency; % Wavelength
                pathLoss = fspl(distance, lambda);
            else % NR pathloss
                pathLoss = nrPathLoss(obj.NRPathLossConfig,txData.CenterFrequency,obj.Los(txData.TransmitterID,rxInfo.ID), ...
                    txData.TransmitterPosition',rxInfo.Position');
            end

            outputData.Power = outputData.Power - pathLoss;

            if ~isempty(obj.ChannelModelMatrix{txData.TransmitterID, rxInfo.ID})
                % There is channel model between the Tx and Rx node
                obj.ChannelModelMatrix{txData.TransmitterID, rxInfo.ID}.InitialTime = outputData.StartTime;
                obj.ChannelModelMatrix{txData.TransmitterID, rxInfo.ID}.NumTimeSamples =  ...
                    txData.Metadata.NumSamples + obj.MaxChannelDelayMatrix(txData.TransmitterID, rxInfo.ID);

                % Get path gains and sample times
                [pathGains, outputData.Metadata.Channel.SampleTimes] = obj.ChannelModelMatrix{txData.TransmitterID, rxInfo.ID}();

                % Find the subset of pathGains for the given NumTransmitAntennas and
                % NumReceiveAntennas
                outputData.Metadata.Channel.PathGains = pathGains(:, :, 1:txData.NumTransmitAntennas, 1:rxInfo.NumReceiveAntennas);
                
                % Normalize the path gains by the number of receive antennas
                outputData.Metadata.Channel.PathGains = outputData.Metadata.Channel.PathGains / sqrt(rxInfo.NumReceiveAntennas);

                % Assign path filters
                outputData.Metadata.Channel.PathFilters = obj.PathFilter{txData.TransmitterID, rxInfo.ID};

                if ~obj.PHYModelNum % full-phy
                    rxWaveform = [txData.Data; zeros(obj.MaxChannelDelayMatrix(txData.TransmitterID, rxInfo.ID), ...
                        size(txData.Data,2))];

                    % Get the filtered data
                    filteredWaveform = channelFilterWrapper( ...
                        obj.ChannelModelMatrix{txData.TransmitterID, rxInfo.ID}, rxWaveform, outputData.Metadata.Channel.PathGains, ...
                        outputData.Metadata.Channel.SampleTimes, obj.ChannelFilter{txData.TransmitterID, rxInfo.ID}, ...
                        outputData.Metadata.Channel.PathFilters, obj.FilterContinuityStruct);

                    % Apply path loss
                    outputData.Data = filteredWaveform.*(10.^(-pathLoss/20));

                    % Update duration
                    outputData.Duration = outputData.Duration + (1/outputData.SampleRate)*obj.MaxChannelDelayMatrix(txData.TransmitterID, rxInfo.ID);
                end
            else
                % There is no channel model between the Tx and Rx node
                outputData.Metadata.Channel.PathGains = permute(ones(outputData.NumTransmitAntennas,rxInfo.NumReceiveAntennas),[3 4 1 2]) / sqrt(rxInfo.NumReceiveAntennas);
                outputData.Metadata.Channel.PathDelays = 0;
                outputData.Metadata.Channel.PathFilters = 1;
                outputData.Metadata.Channel.SampleTimes = 0;
                if obj.PHYModelNum == 0 % Full PHY
                    numTxAnts = outputData.NumTransmitAntennas;
                    numRxAnts = rxInfo.NumReceiveAntennas;
                    H = fft(eye(max([numTxAnts numRxAnts])));
                    H = H(1:numTxAnts,1:numRxAnts);
                    H = H / norm(H);
                    outputData.Data = txData.Data * H; % Apply channel on the waveform
                end
            end
        end
    end
end

%% Local functions for channel filtering
function [f, pathFilterCoeffs] = getPathFilter(ch)
    %GETPATHFILTER Returns the channel filter and coefficients
    %   [F, PATHFILTERCOEFFS] = GETPATHFILTER(CH) returns the channel filter and the
    %   coefficient matrix used to convert path gains of the channel CH to
    %   channel filter tap gains

    % Channel info
    ci = info(ch);
    
    % Create the channel filter
    f = comm.ChannelFilter( ...
        'SampleRate',ch.SampleRate, ....
        'PathDelays',ci.PathDelays, ...
        'FilterDelaySource','Custom', ...
        'FilterDelay',ci.ChannelFilterDelay, ...
        'NormalizeChannelOutputs',false);
    
    pathFilterCoeffs = info(f).ChannelFilterCoefficients;
end

function y = channelFilterWrapper(ch,x,pg,t,f,pf,filterContinuity)
    %CHANNELFILTERWRAPPER Apply channel filter to the waveform
    %   Y = CHANNELFILTERWRAPPER(CH, X, PG, T, F, PF) filters waveform X
    %   through channel CH and path gains PG at times T with filter F having
    %   path filter coefficients PF.
    
    insize = size(x);
    
    % Normalize time to start at zero
    t0 = t(1);
    if t0 ~= 0
        t = t - t0;
    end
    
    outputtype = class(x);
    % If the channel filter is not locked (i.e., hasn't yet been used)
    if ~isLocked(f)
        % Determine the best filter option for the current input
        sizg = size(pg,1:4);
        T = insize(1);
        p = wireless.internal.channelmodels.getFilterPolicy(outputtype,[sizg T]);
        % If the option is to filter waveform sections where each section
        % corresponds to a first dimension element of 'pg', configure the channel
        % filter for efficient execution of this case
        f.OptimizeScalarGainFilter = (p.FilterOption==2);
    end
    
    filterOption = 1 + f.OptimizeScalarGainFilter;
    
    y = wireless.internal.channelmodels.smartChannelFiltering(x,f,f.SampleRate, ...
        pg,insize,ch.SampleDensity,t,outputtype,filterOption,f,pf,filterContinuity);
end