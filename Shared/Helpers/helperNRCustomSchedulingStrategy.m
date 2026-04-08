classdef helperNRCustomSchedulingStrategy < nrScheduler
    %helperNRCustomSchedulingStrategy Implements the custom uplink(UL) and downlink(DL) scheduling strategy
    % This class implements scheduling strategy to allocate resources for new
    % transmissions among User Equipments (UEs) with varying priorities. In
    % each scheduled slot, scheduling strategy randomly selects high priority
    % UEs and allots fixed number of Resource Blocks (RBs). After serving
    % high priority UEs, the remaining RBs are distributed equally among low
    % priority UEs. The same strategy is used for both UL and DL directions.

    %   Copyright 2024 The MathWorks, Inc.

    properties (Access=private)
        %NumRBHighPriority The fixed number of RBs allocated to a high priority UE in a DL assignment or a UL grant.
        % If free RBs are lesser than NumRBHighPriority, then all the free RBs are
        % allotted to a randomly selected high priority UE
        NumRBHighPriority = 4;

        %StatAllottedRBHighPriority Cumulative number of the RBs allotted to high priority UEs.
        % This only includes allotted RBs for new transmissions. A vector of two
        % elements. First and second elements represent the total number of
        % allotted RBs in downlink and uplink directions respectively.
        StatAllottedRBHighPriority = zeros(1, 2);

        %StatAllottedRBLowPriority Cumulative number of the RBs allotted to low priority UEs.
        % This only includes allotted RBs for new transmissions. A vector of two
        % elements. First and second elements represent the total number of
        % allotted RBs in downlink and uplink directions respectively.
        StatAllottedRBLowPriority = zeros(1, 2);
    end

    properties(Constant)
        %CQITable CQI table as per TS 38.214 - Table 5.2.2.1-3.
        % This table is used to indicate channel quality for DL direction
        % Modulation CodeRate Efficiency
        CQITable = helperNRCustomSchedulingStrategy.getCQITable();

        %MCSTable MCS table as per TS 38.214 - Table 5.1.3.1-2.
        % This table is used to indicate MCS for both UL and DL directions
        % Modulation CodeRate Efficiency
        MCSTable = helperNRCustomSchedulingStrategy.getMCSTable();
    end

    methods
        function obj = helperNRCustomSchedulingStrategy(varargin)
            %helperNRCustomSchedulingStrategy Initialize the custom scheduler class
            %   helperNRCustomSchedulingStrategy properties (configurable through N-V pair):
            %
            %   NumRBHighPriority - The fixed number of RBs allocated to a high
            %   priority UE in a DL assignment or a UL grant.

            % Name-value pair check
            coder.internal.errorIf(mod(nargin, 2) == 1,'MATLAB:system:invalidPVPairs');
            if nargin == 2
                obj.(varargin{1}) = varargin{2};
            end
        end

        function [statHighPriority, statLowPriority] = getAllottedRBCount(obj)
            %getAllottedRBCount Get the total number of allotted RBs for high priority UEs and low priority UEs in downlink and uplink directions.
            % This only includes allotted RBs for new transmissions.

            % Two elements vector which represents the total number of allotted RBs for
            % high and low priority UEs in downlink and uplink directions respectively
            statHighPriority = obj.StatAllottedRBHighPriority;
            statLowPriority = obj.StatAllottedRBLowPriority;
        end
    end

    methods (Access = protected)
        function ulGrants = scheduleNewTransmissionsUL(obj, timeResource, frequencyResource, schedulingInfo)
            %scheduleNewTransmissionsUL Assign resources for new UL transmissions in a transmission time interval (TTI)
            %
            %   ULGRANTS is a struct array where each element represents one UL grant.Refer <a href="matlab:help('nrScheduler.scheduleNewTransmissionsUL')">scheduleNewTransmissionsUL</a> 
            %   for more information on the grant fields to be filled in this function. The remaining grant fields are 
            %   filled by the caller of this function.


            % Read eligible UEs. For more information about eligible UEs, see the
            % scheduleNewTransmissionsUL method of nrScheduler class.
            eligibleUEs = schedulingInfo.EligibleUEs;
            % Stores UL grants of this TTI
            ulGrantStruct = struct('RNTI',[],'FrequencyAllocation',[], ...
                'MCSIndex',[],'NumLayers',[],'TPMI',[]);
            ulGrants = repmat(ulGrantStruct,numel(eligibleUEs),1);

            % Segregate UEs into high priority and low priority
            ueContext = obj.UEContext;
            highPriorityUEs = [];
            lowPriorityUEs = [];
            for i=1:numel(eligibleUEs)
                priority = ueContext(eligibleUEs(i)).CustomContext.Priority;
                if priority == 1 % High priority UE
                    highPriorityUEs(end+1) = eligibleUEs(i);
                else % Low priority UE
                    lowPriorityUEs(end+1) = eligibleUEs(i);
                end
            end

            %% Allocate resources to high priority UEs
            % Create random order of the high priority UEs and trim it with
            % consideration to the number of allowed users per TTI
            eligibleHighPriorityUEs = highPriorityUEs(randperm(numel(highPriorityUEs)));
            selectedHighPriorityUEs = eligibleHighPriorityUEs(1:min(schedulingInfo.MaxNumUsersTTI, numel(eligibleHighPriorityUEs)));
            % Find index of the first free RB in the bandwidth. The retransmission
            % grants (if any) use contiguous RBs from start of the bandwidth hence all
            % the RBs after the first free RB are available for new transmission.
            firstFreeRBIndex = find(frequencyResource==0, 1)-1;
            numRBs = obj.CellConfig.NumResourceBlocks;
            numAllottedGrants = 0;
            % Allocate fixed number of RBs to high priority UEs. If free RBs are lesser
            % than NumRBHighPriority, then allocate all the free RBs to the selected UE
            for i=1:numel(selectedHighPriorityUEs)
                remFreeRBs = numRBs - firstFreeRBIndex;
                allottedRBCount = min(remFreeRBs, obj.NumRBHighPriority);
                % Fill the new transmission uplink grant properties
                selectedUE = selectedHighPriorityUEs(i);
                ueInfo = ueContext(selectedUE);
                csiMeasurement = ueInfo.CSIMeasurementUL;
                ulGrants(i).RNTI = selectedUE;
                ulGrants(i).FrequencyAllocation = [firstFreeRBIndex allottedRBCount];
                % Use SRS based channel measurement report to fill MCSIndex, NumLayers and TPMI
                ulGrants(i).MCSIndex = csiMeasurement.MCSIndex;
                ulGrants(i).NumLayers = csiMeasurement.RI;
                ulGrants(i).TPMI = csiMeasurement.TPMI;
                % Update the stats
                obj.StatAllottedRBHighPriority(2) = obj.StatAllottedRBHighPriority(2) + allottedRBCount;
                numAllottedGrants = numAllottedGrants + 1;
                firstFreeRBIndex = firstFreeRBIndex + allottedRBCount;
                if firstFreeRBIndex == numRBs
                    break; % All RBs are allotted
                end
            end

            %% Allocate resources to low priority UEs
            % Create random order of the low priority UEs and trim it with
            % consideration to the number of allowed users per TTI
            eligibleLowPriorityUEs = lowPriorityUEs(randperm(numel(lowPriorityUEs)));
            selectedLowPriorityUEs = eligibleLowPriorityUEs(1:min(schedulingInfo.MaxNumUsersTTI - numAllottedGrants, numel(eligibleLowPriorityUEs)));
            numSelectedLowPriorityUEs = numel(selectedLowPriorityUEs);
            if(firstFreeRBIndex < numRBs) && numSelectedLowPriorityUEs % If there are free RBs and eligible low priority UE(s)
                numFreeRBs = numRBs - firstFreeRBIndex;
                % Equally distribute the frequency resources among low priority UEs.
                rbForLowPriorityUE = floor(numFreeRBs/numSelectedLowPriorityUEs);
                if rbForLowPriorityUE < 1
                    % If free RBs are less than number of selected low priority UEs, then
                    % allocate all the free RBs to the first UE in the selected order
                    numSelectedLowPriorityUEs = 1;
                end
                for i=1:numSelectedLowPriorityUEs
                    remFreeRBs = numRBs - firstFreeRBIndex;
                    allottedRBCount = min(remFreeRBs, rbForLowPriorityUE);
                    if i == numSelectedLowPriorityUEs
                        % Allocate all the extra remaining RBs to the last selected UE
                        allottedRBCount = remFreeRBs;
                    end
                    % Fill the new transmission uplink grant properties
                    selectedUE = selectedLowPriorityUEs(i);
                    ueInfo = ueContext(selectedUE);
                    csiMeasurement = ueInfo.CSIMeasurementUL;
                    numAllottedGrants = numAllottedGrants + 1;
                    ulGrants(numAllottedGrants).RNTI = selectedUE;
                    ulGrants(numAllottedGrants).FrequencyAllocation = [firstFreeRBIndex allottedRBCount];
                    % Use SRS based channel measurement report to fill MCSIndex, NumLayers and TPMI
                    ulGrants(numAllottedGrants).MCSIndex = csiMeasurement.MCSIndex;
                    ulGrants(numAllottedGrants).NumLayers = csiMeasurement.RI;
                    ulGrants(numAllottedGrants).TPMI = csiMeasurement.TPMI;
                    % Update the stats
                    obj.StatAllottedRBLowPriority(2) = obj.StatAllottedRBLowPriority(2) + allottedRBCount;
                    firstFreeRBIndex = firstFreeRBIndex + allottedRBCount;
                    if firstFreeRBIndex == numRBs
                        break; % All RBs are filled
                    end
                end
            end

            ulGrants = ulGrants(1:numAllottedGrants); % Remove invalid trailing entries
        end

        function dlAssignments = scheduleNewTransmissionsDL(obj, timeResource, frequencyResource, schedulingInfo)
            %scheduleNewTransmissionsDL Assign resources for new DL transmissions in a transmission time interval (TTI)
            %
            %   DLASSIGNMENTS is a struct array where each element represents DL assignment. Refer <a href="matlab:help('nrScheduler.scheduleNewTransmissionsDL')">scheduleNewTransmissionsDL</a> 
            %  for more information on the assignment fields to be filled in this function. The remaining assignment fields 
            %  are filled by the caller of this function.

            % Read eligible UEs. For more information about eligible UEs, see the
            % scheduleNewTransmissionsDL method of nrScheduler class.
            eligibleUEs = schedulingInfo.EligibleUEs;
            % Stores DL assignments of this TTI
            dlAssignmentStruct = struct('RNTI',[],'FrequencyAllocation',[], 'MCSIndex',[], 'W',[]);
            dlAssignments = repmat(dlAssignmentStruct, numel(eligibleUEs), 1);

            % Segregate UEs into high priority and low priority
            ueContext = obj.UEContext;
            highPriorityUEs = [];
            lowPriorityUEs = [];
            for i=1:numel(eligibleUEs)
                priority = ueContext(eligibleUEs(i)).CustomContext.Priority;
                if priority == 1 % High priority UE
                    highPriorityUEs(end+1) = eligibleUEs(i);
                else % Low priority UE
                    lowPriorityUEs(end+1) = eligibleUEs(i);
                end
            end

            %% Allocate resources to high priority UEs
            % Create random order of the high priority UEs and trim it with
            % consideration to the number of allowed users per TTI
            eligibleHighPriorityUEs = highPriorityUEs(randperm(numel(highPriorityUEs)));
            selectedHighPriorityUEs = eligibleHighPriorityUEs(1:min(schedulingInfo.MaxNumUsersTTI, numel(eligibleHighPriorityUEs)));
            % Find index of the first free RB in the bandwidth. The retransmission
            % assignments (if any) use contiguous RBs from start of the bandwidth hence
            % all the RBs after the first free RB are available for new transmission.
            firstFreeRBIndex = find(frequencyResource==0, 1)-1;
            numRBs = obj.CellConfig.NumResourceBlocks;
            numAllottedAssignments = 0;
            % Allocate fixed number of RBs to high priority UEs. If free RBs are lesser
            % than NumRBHighPriority, then allocate all the free RBs to the selected UE
            for i=1:numel(selectedHighPriorityUEs)
                remFreeRBs = numRBs - firstFreeRBIndex;
                allottedRBCount = min(remFreeRBs, obj.NumRBHighPriority);
                % Fill the new transmission downlink assignment properties
                selectedUE = selectedHighPriorityUEs(i);
                csiMeasurement = ueContext(selectedUE).CSIMeasurementDL;
                csiMeasurementCQI = csiMeasurement.CSIRS.CQI;
                dlAssignments(i).RNTI = selectedUE;
                dlAssignments(i).FrequencyAllocation = [firstFreeRBIndex allottedRBCount];
                % Use CSI-RS based channel measurement report to fill MCSIndex and W
                dlAssignments(i).MCSIndex = getMCS(obj, csiMeasurementCQI);
                % CSI-RS reported W matrix has dimension NumPorts-by-NumLayers.
                % Transposing it to get required dimension NumLayers-by-NumPorts.
                dlAssignments(i).W = csiMeasurement.CSIRS.W.';
                % Update the stats
                obj.StatAllottedRBHighPriority(1) = obj.StatAllottedRBHighPriority(1) + allottedRBCount;
                numAllottedAssignments = numAllottedAssignments + 1;
                firstFreeRBIndex = firstFreeRBIndex + allottedRBCount;
                if firstFreeRBIndex == numRBs
                    break; % All RBs are allotted
                end
            end

            %% Allocate resources to low priority UEs
            % Create random order of the low priority UEs and trim it with
            % consideration to the number of allowed users per TTI
            eligibleLowPriorityUEs = lowPriorityUEs(randperm(numel(lowPriorityUEs)));
            selectedLowPriorityUEs = eligibleLowPriorityUEs(1:min(schedulingInfo.MaxNumUsersTTI - numAllottedAssignments, numel(eligibleLowPriorityUEs)));
            numSelectedLowPriorityUEs = numel(selectedLowPriorityUEs);
            if(firstFreeRBIndex < numRBs) && numSelectedLowPriorityUEs % If there are free RBs and eligible low priority UE(s)
                numFreeRBs = numRBs - firstFreeRBIndex;
                % Equally distribute the frequency resources among low priority UEs.
                rbForLowPriorityUE = floor(numFreeRBs/numSelectedLowPriorityUEs);
                if rbForLowPriorityUE < 1
                    % If free RBs are less than number of selected low priority UEs, then
                    % allocate all the free RBs to the first UE in the selected order
                    numSelectedLowPriorityUEs = 1;
                end
                for i=1:numSelectedLowPriorityUEs
                    remFreeRBs = numRBs - firstFreeRBIndex;
                    allottedRBCount = min(remFreeRBs, rbForLowPriorityUE);
                    if i == numSelectedLowPriorityUEs
                        % Allocate all the extra remaining RBs to the last selected UE
                        allottedRBCount = remFreeRBs;
                    end
                    % Fill the new transmission downlink assignment properties
                    selectedUE = selectedLowPriorityUEs(i);
                    csiMeasurement = ueContext(selectedUE).CSIMeasurementDL;
                    csiMeasurementCQI = csiMeasurement.CSIRS.CQI;
                    numAllottedAssignments = numAllottedAssignments + 1;
                    dlAssignments(numAllottedAssignments).RNTI = selectedUE;
                    dlAssignments(numAllottedAssignments).FrequencyAllocation = [firstFreeRBIndex allottedRBCount];
                    % Use CSI-RS based channel measurement report to fill MCSIndex and W
                    dlAssignments(numAllottedAssignments).MCSIndex = getMCS(obj, csiMeasurementCQI);
                    % CSI-RS reported W matrix has dimension NumPorts-by-NumLayers.
                    % Transposing it to get required dimension NumLayers-by-NumPorts.
                    dlAssignments(numAllottedAssignments).W = csiMeasurement.CSIRS.W.';
                    % Update the stats
                    obj.StatAllottedRBLowPriority(1) = obj.StatAllottedRBLowPriority(1) + allottedRBCount;
                    firstFreeRBIndex = firstFreeRBIndex + allottedRBCount;
                    if firstFreeRBIndex == numRBs
                        break; % All RBs are filled
                    end
                end
            end

            dlAssignments = dlAssignments(1:numAllottedAssignments); % Remove invalid trailing entries
        end
    end

    methods (Access = private)
        function mcsRowIndex = getMCS(obj, cqiIndex)
            %getMCS Returns the MCS row index

            cqiTable = obj.CQITable;
            mcsTable = obj.MCSTable;
            modulation = cqiTable(cqiIndex + 1, 1);
            codeRate = cqiTable(cqiIndex + 1, 2);
            for mcsRowIndex = 1:28 % MCS indices
                if modulation ~= mcsTable(mcsRowIndex, 1)
                    continue;
                end
                if codeRate <= mcsTable(mcsRowIndex, 2)
                    break;
                end
            end
            mcsRowIndex = mcsRowIndex - 1;
        end
    end

    methods (Static)
        function mcsTable = getMCSTable()
            %getMCSTable  Returns the MCS table as per TS 38.214 - Section 5.1.3.1-2
            %This table is used to indicate MCS for both DL and UL directions.
            % Modulation CodeRate Efficiency

            mcsTables = nrPUSCHMCSTables;
            mcsTable = mcsTables.QAM256Table;

            % Extract the required columns
            mcsTable = mcsTable(:, ["Qm","TargetCodeRate","SpectralEfficiency"]);
            % Convert table to 2-D array for performance optimization
            mcsTable = table2array(mcsTable);
            % Replace NaN values with 0
            mcsTable(isnan(mcsTable)) = 0;
            % Multiply target code rate by 1024 to get code rate
            mcsTable(:,2) = mcsTable(:,2).*1024;
        end

        function cqiTable = getCQITable()
            %getCQITable Returns the CQI table as per TS 38.214 - Section 5.2.2.1-3
            %This table is used to indicate channel quality for DL direction.
            % Modulation CodeRate Efficiency

            cqiTables = nrCQITables;
            cqiTable = cqiTables.CQITable2;

            % Extract the required columns
            cqiTable = cqiTable(:, ["Qm","TargetCodeRate","SpectralEfficiency"]);
            % Convert table to 2-D array for performance optimization
            cqiTable = table2array(cqiTable);
            % Replace NaN values with 0
            cqiTable(isnan(cqiTable)) = 0;
            % Multiply target code rate by 1024 to get code rate
            cqiTable(:,2) = cqiTable(:,2).*1024;
        end
    end
end