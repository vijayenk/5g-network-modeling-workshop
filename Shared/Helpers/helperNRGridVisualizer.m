classdef helperNRGridVisualizer < handle
    %helperNRGridVisualizer Scheduler log visualization
    %   The class implements visualization of logs by querying from the
    %   logger (helperNRSchedulingLogger object).
    %   The following two types of visualizations are shown:
    %    (i) Display of MCS values for UEs over the bandwidth
    %   (ii) Display of resource grid assignment to UEs. This 2D time-frequency
    %        grid shows the RB allocation to the UEs in the previous slot for
    %        symbol based scheduling and previous frame for slot based
    %        scheduling. HARQ process for the assignments is also shown
    %        alongside the UE's RNTI
    %
    %   helperNRGridVisualizer methods:
    %
    %   plotRBGrids         - Plot RB grid visualization
    %   plotMCSRBGrids      - Plot the MCS grid visualization
    %
    %   helperNRGridVisualizer Name-Value pairs:
    %
    %   CellOfInterest    - Cell ID to which the visualization object belongs
    %   SchedulingLogger  - Scheduling logger handle object
    %   LinkDirection     - Flag to indicate the plots to visualize

    %   Copyright 2023-2026 The MathWorks, Inc.

    properties
        %CellOfInterest Cell ID to which the visualization object belongs
        CellOfInterest (1, 1) {mustBeInteger, mustBeBetween(CellOfInterest, 0, 1007)} = 1;

        %LinkDirection  Indicates the plots to visualize
        % It takes the values 0, 1, 2 and represent downlink, uplink, and both
        % respectively. Default value is 2.
        LinkDirection (1, 1) {mustBeInteger, mustBeBetween(LinkDirection, 0, 2)} = 2;

        %SchedulingLogger MAC logger handle object of type helperNRSchedulingLogger
        SchedulingLogger {mustBeScalarOrEmpty}
    end

    properties(Hidden)
        %ResourceGridVisualization Switch to turn on/off the resource grid visualization (resource-grid occupancy)
        ResourceGridVisualization = false;

        %RGMaxRBsToDisplay Max number of RBs displayed in resource grid visualization
        RGMaxRBsToDisplay = 20

        %RGMaxSlotsToDisplay Max number of slots displayed in resource grid visualization
        RGMaxSlotsToDisplay = 10

        %MCSGridVisualization Switch to turn on/off the MCS grid visualization
        MCSGridVisualization = false;

        %CVMaxRBsToDisplay Max number of RBs to be displayed in MCS visualization
        CVMaxRBsToDisplay = 20

        %CVMaxUEsToDisplay Max number of UEs to be displayed in MCS visualization
        CVMaxUEsToDisplay = 10

        %MCSVisualizationFigHandle Handle of the MCS visualization
        MCSVisualizationFigHandle

        %RGVisualizationFigHandle Handle of the resource grid visualization
        RGVisualizationFigHandle

        %IsLogReplay Flag to decide the type of post-simulation visualization
        % whether to show plain replay of the resource assignment during
        % simulation or of the selected slot (or frame). During the
        % post-simulation visualization, setting the value to 1 just
        % replays the resource assignment of the simulation frame-by-frame
        % (or slot-by-slot). Setting value to 0 gives the option to select
        % a particular frame (or slot) to see the way resources are
        % assigned in the chosen frame (or slot)
        IsLogReplay

        %SimulationLogs Simulation logs of the network
        SimulationLogs
    end

    properties (Constant)
        %NumSym Number of symbols in a slot
        NumSym = 14;

        % Duplexing mode related constants
        %FDDDuplexMode Frequency division duplexing mode
        FDDDuplexMode = 0;
        %TDDDuplexMode Time division duplexing mode
        TDDDuplexMode = 1;

        % Constants related to scheduling type
        %SymbolBased Symbol based scheduling
        SymbolBased = 1;
        %SlotBased Slot based scheduling
        SlotBased = 0;

        % Constants related to downlink and uplink information. These
        % constants are used for indexing logs and identifying plots
        %DownlinkIdx Index for all downlink information
        DownlinkIdx = 1;
        %UplinkIdx Index for all downlink information
        UplinkIdx = 2;

        %MaxCells Maximum number of cells
        MaxCells = 1008;
    end

    properties (Access=private)
        %NumUEs Count of UEs
        NumUEs

        %NumFrames Number of frames in simulation
        NumFrames

        %SchedulingType Type of scheduling (slot based or symbol based)
        % Value 0 means slot based and value 1 means symbol based. The
        % default value is 0
        SchedulingType (1, 1) {mustBeMember(SchedulingType, [0, 1])} = 0;

        %DuplexMode Duplexing mode
        % Frequency division duplexing (FDD) or time division duplexing (TDD)
        % Value 0 means FDD and 1 means TDD. The default value is 0
        DuplexMode (1, 1) {mustBeMember(DuplexMode, [0, 1])} = 0;

        %ColumnIndexMap Mapping the column names of logs to respective column indices
        % It is a map object
        ColumnIndexMap

        %NumRBs Number of resource blocks
        % A vector of two elements. First element represents number of
        % PDSCH RBs and second element represents number of PUSCH RBs
        NumRBs = zeros(2, 1);

        %NumSlotsFrame Number of slots in 10ms time frame
        NumSlotsFrame

        %CurrFrame Current frame number
        CurrFrame

        %CurrSlot Current slot in the frame
        CurrSlot

        %NumLogs Number of logs to be created based on number of links
        NumLogs = 2;

        %SymSlotInfo Information about how each symbol/slot (UL/DL/Guard) is allocated
        SymSlotInfo

        %PlotIds IDs of the plots
        PlotIds

        %ResourceGridInfo a 2x1 struct array containing resource grid
        % information for DL and UL. In FDD mode, the first element
        % contains DL resource grid information, and the second element
        % contains UL resource grid information. In TDD mode, the first
        % element contains resource grid information for both DL and UL,
        % and the second element is unused. Each element is a struct with
        % the following fields:
        %   - UEAssignment: A 2D cell array of size N-by-P, storing how UEs are
        %     assigned different time-frequency resources.
        %   - TxType: A 2D cell array of size N-by-P,
        %     storing transmission status (new-transmission or
        %     retransmission).
        %   - HarqID: A 2D cell array of size N-by-P,
        %     storing the HARQ process identifiers.
        % Dimension definitions:
        %     N: Number of slots (for slot-based scheduling) or symbols
        %     (for symbol-based scheduling)
        %     P: Number of RBs in the bandwidth
        ResourceGridInfo = struct(...
            'UEAssignment', {{}; {}}, ...
            'TxType', {{}; {}}, ...
            'HarqID', {{}; {}} ...
            );

        %ResourceGridInfoText Stores the text that will be shown in each cell of the RBGridTable
        % First element contains text related to downlink and second
        % element contains text related to uplink for FDD mode. In TDD mode
        % first element contains text related to both downlink and uplink.
        ResourceGridInfoText = cell(2, 1)

        %RVCurrView Type of scheduler scheduling information displayed in
        % MCS Visualization. Value 1 represents downlink and value 2
        % represents uplink
        RVCurrView = 1

        %RGTxtHandle UI control handle to display the frame number in resource grid visualization
        RGTxtHandle

        %RGSlotTxtHandle UI control handle to display the slot number in resource grid visualization
        RGSlotTxtHandle

        %RGLowerRBIndex Index of the first RB displayed in resource grid visualization
        RGLowerRBIndex = 0

        %RGUpperRBIndex Index of the last RB displayed in resource grid visualization
        RGUpperRBIndex

        %RGLowerSlotIndex Index of the first slot displayed in resource grid visualization
        RGLowerSlotIndex = 0

        %RGUpperSlotIndex Index of the last slot displayed in resource grid visualization
        RGUpperSlotIndex

        % MCS information related properties
        %MCSInfo First element contains downlink MCS information and
        % second element contains uplink MCS information. Each element is
        % an N-by-P matrix where 'N' is the number of UEs and 'P' is the
        % number of RBs in the bandwidth. A matrix element at position (i,
        % j) corresponds to MCS value for UE with RNTI 'i' at RB 'j'
        MCSInfo = cell(2, 1);

        %MCSVisualizationGridHandles Handles to display UE MCSs on the RBs of the bandwidth
        MCSVisualizationGridHandles

        %MCSMapHandle Handle of the MCS heat map
        MCSMapHandle

        %CVCurrView Type of MCS displayed in MCS visualization. Value 1
        % represents downlink and value 2 represents
        % uplink
        CVCurrView = 1

        %CVLowerUEIndex Index of the first UE to be displayed in MCS visualization
        CVLowerUEIndex = 0

        %CVUpperUEIndex Index of the last UE to be displayed in MCS visualization
        CVUpperUEIndex

        %CVLowerRBIndex Index of the first RB to be displayed in MCS visualization
        CVLowerRBIndex = 0

        %CVUpperRBIndex Index of the last RB to be displayed in MCS visualization
        CVUpperRBIndex

        %CVTxtHandle UI control handle to display the frame number in MCS visualization
        CVTxtHandle

        %UENames Names of the UEs
        UENames
    end

    properties(Hidden)
        %IsLegendRequired Flag to control the GUI elements on the grid
        IsLegendRequired = false;

        %AlertBoxTitle Title for the alert box
        AlertBoxTitle = string(message('nr5g:networkModeler:GridVisualizer'));

        %RBGridTable Resource allocation grid table
        RBGridTable
    end

    methods
        function obj = helperNRGridVisualizer(numFrameSim, gNB, UEs, varargin)
            %helperNRGridVisualizer Construct scheduling log visualization object
            %
            % OBJ = helperNRGridVisualizer(NUMFRAMESIM, GNB, UES) Create
            % grid visualization object.
            %
            % NUMFRAMESSIM is simulation time in terms of number of 10 ms frames.
            %
            % GNB is an object of type nrGNB.
            %
            % UEs is a vector of node objects of type nrUE. They must be connected to
            % the same GNB.

            % Initialize the properties
            for idx = 1:2:numel(varargin)
                if (varargin{idx}) == "SchedulingLogger"
                    obj.(varargin{idx}) = matlab.lang.WeakReference(varargin{idx+1}).Handle;
                else
                    obj.(varargin{idx}) = varargin{idx+1};
                end
            end

            % Validate number of frames in simulation
            obj.NumFrames = numFrameSim;

            if ~isempty(obj.IsLogReplay) && ~isempty(obj.SimulationLogs) && obj.IsLogReplay == 0
                cellChanged(obj, obj.SimulationLogs{1}.CellName);
            else
                updateContext(obj, gNB, UEs);
            end

            if ~obj.IsLegendRequired
                setupGUI(obj);
            end
        end

        function updateContext(obj, gNB, UEs)
            %updateContext Update the context of the object

            obj.NumUEs = numel(UEs);
            if obj.NumUEs > 0
                obj.UENames = [UEs.Name];
            end
            obj.NumSlotsFrame = (10 * gNB.SubcarrierSpacing*1e-3) / 15; % Number of slots in a 10 ms frame

            % Verify Duplex mode and update the properties
            if strcmpi(gNB.DuplexMode, "TDD")
                obj.DuplexMode = 1;
            end
            if obj.DuplexMode == obj.TDDDuplexMode % TDD
                obj.NumLogs = 1;
                obj.RVCurrView = 1; % Only one view for resource grid
            end

            % Determine the plots
            % Downlink & Uplink
            obj.PlotIds = [obj.DownlinkIdx obj.UplinkIdx];
            % Show the enabled visualization as current view
            if obj.LinkDirection ~= 2
                obj.PlotIds = obj.LinkDirection+1;
                obj.RVCurrView = obj.PlotIds;
                obj.CVCurrView = obj.PlotIds;
            end

            % Initialize number of RBs, MCS and metrics properties
            for idx = 1: numel(obj.PlotIds)
                logIdx = obj.PlotIds(idx);
                obj.NumRBs(logIdx) = gNB.NumResourceBlocks; % Number of RBs in DL/UL
                obj.MCSInfo{logIdx} = zeros(obj.NumUEs, obj.NumRBs(logIdx)); % DL/UL MCS
            end

            if obj.SchedulingType % Symbol based scheduling
                gridLength = obj.NumSym;
            else % Slot based scheduling
                gridLength = obj.NumSlotsFrame;
            end

            % Initialize the scheduling logs and resources grid related
            % properties
            for idx=1:min(obj.NumLogs,numel(obj.PlotIds))
                plotId = obj.PlotIds(idx);
                if obj.DuplexMode == obj.FDDDuplexMode
                    logIdx = plotId; % FDD
                else
                    logIdx = idx; % TDD
                end
                % Construct the log format
                gridSize = [gridLength, obj.NumRBs(logIdx)];
                cellGrid = cell(gridSize);
                obj.ResourceGridInfo(logIdx) = struct(...
                    'UEAssignment', {cellGrid}, ...
                    'TxType', {cellGrid}, ...
                    'HarqID', {cellGrid} ...
                    );
                obj.ResourceGridInfoText{logIdx} = strings(gridSize);
            end
            obj.RGLowerRBIndex = 0;
            obj.RGLowerSlotIndex = 0;
            obj.CVLowerUEIndex = 0;
            obj.CVLowerRBIndex = 0;
        end

        function plotMCSRBGrids(obj, varargin)
            %plotMCSRBGrids Updates the MCS grid visualization
            %
            % plotMCSRBGrids(OBJ, SIMSLOTNUM) To update the MCS
            % grid and MCS visualization in live visualization
            %
            % SIMSLOTNUM - Cumulative slot number in the simulation

            % Update frame number in the figure (in live visualization)
            if isempty(obj.IsLogReplay)
                slotNum = varargin{1};
                obj.CurrFrame = floor(slotNum / obj.NumSlotsFrame)-1;
                obj.CurrSlot = mod(slotNum-1, obj.NumSlotsFrame);
            end
            updateMCSVisualization(obj);
            drawnow;
        end

        function plotRBGrids(obj, varargin)
            %plotRBGrids Updates the resource grid visualization
            %
            % plotRBGrids(OBJ) To update the resource
            % grid and MCS visualization in post-simulation visualization
            %
            % plotRBGrids(OBJ, SIMSLOTNUM) To update the resource
            % grid and MCS visualization in live visualization
            %
            % SIMSLOTNUM - Cumulative slot number in the simulation

            % Check if the figure handle is valid
            if isempty(obj.RGVisualizationFigHandle) || ~ishghandle(obj.RGVisualizationFigHandle)
                return;
            end

            % Update frame number in the figure (in live visualization)
            if isempty(obj.IsLogReplay)
                slotNum = varargin{1};
                obj.CurrFrame = floor((slotNum-1) / obj.NumSlotsFrame);
                if obj.CurrFrame < 0
                    obj.CurrFrame = 0;
                end
                obj.CurrSlot = mod(slotNum-1, obj.NumSlotsFrame);
            end

            if isempty(obj.CurrFrame)
                return;
            end
            if obj.DuplexMode == obj.TDDDuplexMode
                [obj.ResourceGridInfo, obj.SymSlotInfo] = obj.SchedulingLogger.getRBGridsInfo(obj.CurrFrame, obj.CurrSlot);
            else
                obj.ResourceGridInfo = obj.SchedulingLogger.getRBGridsInfo(obj.CurrFrame, obj.CurrSlot);
            end

            for idx = 1:min(obj.NumLogs, numel(obj.PlotIds))
                plotId = obj.PlotIds(idx);
                if obj.DuplexMode == obj.FDDDuplexMode
                    logIdx = obj.PlotIds(idx);
                else
                    logIdx = 1;
                end

                slIdx = size(obj.ResourceGridInfo(logIdx).UEAssignment, 1);
                % Clear the previously plotted text in the resource grid
                for p = 1:slIdx
                    for q = 1 : obj.NumRBs(plotId)
                        obj.ResourceGridInfoText{logIdx}(p, q) = '';
                    end
                end

                for p = 1:slIdx
                    for q = 1 : obj.NumRBs(plotId)
                        if isempty(obj.ResourceGridInfo(logIdx).UEAssignment{p, q})
                            % Clear the previously plotted text in the resource grid
                            obj.ResourceGridInfoText{logIdx}(p, q)  = '';
                        else
                            % Create the text to be plotted in the resource
                            % grid
                            if obj.ResourceGridInfo(logIdx).TxType{p,q}(1) == 2 % Re-Tx (Assuming for retransmissions UEs are not paired)
                                obj.ResourceGridInfoText{logIdx}(p, q) = strjoin( "<font style='color:var(--mw-graphics-colorOrder-1-quaternary)'>" + ...
                                    obj.UENames(obj.ResourceGridInfo(logIdx).UEAssignment{p, q}) + ...
                                    "(" + obj.ResourceGridInfo(logIdx).HarqID{p, q} + ")</font>", ', ');
                            else
                                obj.ResourceGridInfoText{logIdx}(p, q) = strjoin( "<font style='color:var(--mw-graphics-colorNeutral-line-tertiary)'>" +...
                                    obj.UENames(obj.ResourceGridInfo(logIdx).UEAssignment{p, q}) +  ...
                                    "(" + obj.ResourceGridInfo(logIdx).HarqID{p, q} + ")</font>", ', ');
                            end
                        end
                    end
                end
            end

            updateResourceGridVisualization(obj);
        end

        function constructMCSGridVisualization(obj, varargin)
            %constructMCSGridVisualization Construct MCS grid visualization
            %
            % constructMCSGridVisualization(OBJ, Info) Construct MCS grid visualization
            %
            % Info - Info can be figure handle or a logical value. If it is a figure
            % handle, it is used for plotting. If it is logical value existing figure
            % is used.

            maxRBs = max(obj.NumRBs(obj.PlotIds));
            updateLegend = true;
            if nargin == 2
                if islogical(varargin{1})
                    updateLegend = varargin{1};
                    g = obj.MCSVisualizationFigHandle.Children;
                else
                    obj.MCSVisualizationFigHandle = varargin{1};
                    obj.MCSGridVisualization = true;
                end
            end
            compCounter = 2; % Row number to start adding the components to the grid
            if updateLegend
                g = uigridlayout(obj.MCSVisualizationFigHandle);
                g.RowHeight = {'fit','fit','fit','fit','fit','fit','fit','1x'};
                g.ColumnWidth = {'fit','fit','1x','fit','1x'};

                if ~isempty(obj.IsLogReplay) && ~isempty(obj.SimulationLogs) && obj.IsLogReplay == 0
                    numCells = numel(obj.SimulationLogs);
                    cellNames = strings(numCells,1);
                    for idx=1:numCells
                        cellNames(idx) = obj.SimulationLogs{idx}.CellName;
                    end
                    lb1 = uilabel(g,'Text',string(message('nr5g:networkModeler:CellLabelText')));
                    lb1.Layout.Row = compCounter;
                    lb1.Layout.Column = 1;
                    dd = uidropdown(g,'Items',cellNames, 'ItemsData', 1:numCells, ...
                        'ValueChangedFcn', @(dd, event) cellChanged(obj, dd.Items{dd.Value}));
                    dd.Layout.Row = compCounter;
                    dd.Layout.Column = 2;
                    if numCells == 1
                        dd.Enable = 'off';
                    end
                    compCounter = compCounter + 1;
                end
                if obj.LinkDirection == 2
                    lb1 = uilabel(g,'Text',string(message('nr5g:networkModeler:LinkLabelText')));
                    lb1.Layout.Row = compCounter;
                    lb1.Layout.Column = 1;

                    % Link direction
                    dd1 = uidropdown(g, ...
                        'Items',[...
                        string(message('nr5g:networkModeler:LinkDirectionDownlinkText')), ...
                        string(message('nr5g:networkModeler:LinkDirectionUplinkText'))], ...
                        'ItemsData', obj.PlotIds, ...
                        'ValueChangedFcn', @(dd, event) cbSelectedLinkType(obj, dd.Value), ...
                        'ToolTip',string(message('nr5g:networkModeler:LinkLabelTooltip')));

                    dd1.Layout.Row = compCounter;
                    dd1.Layout.Column = 2;
                else
                    compCounter = 2;
                end
            else
                compCounter = obj.MCSVisualizationFigHandle.Children.Children(end).Layout.Row;
            end
            if obj.CVMaxRBsToDisplay <= maxRBs
                compCounter = compCounter + 1;
                obj.CVUpperRBIndex = obj.CVMaxRBsToDisplay;
                lb2 = uilabel(g, ...
                    'Text',string(message('nr5g:networkModeler:RBRangeLabelText')),...
                    'ToolTip',string(message('nr5g:networkModeler:RBRangeLabelTooltip')));
                lb2.Layout.Row = compCounter;
                lb2.Layout.Column = 1;
                [items, itemsData] = constructRBItemList(obj, obj.NumRBs(obj.CVCurrView));
                dd2 = uidropdown(g,'Items', items, 'ItemsData', itemsData, 'ValueChangedFcn', ...
                    @(dd, event) cbSelectedRBRange(obj, dd.Value),...
                    'ToolTip',string(message('nr5g:networkModeler:RBRangeDropDownTooltip')));
                dd2.Layout.Row = compCounter;
                dd2.Layout.Column = 2;
            else
                obj.CVUpperRBIndex = maxRBs;
            end

            % Number of UEs to be displayed in the default view of MCS visualization
            if obj.NumUEs >= obj.CVMaxUEsToDisplay
                compCounter = compCounter + 1;
                obj.CVUpperUEIndex = obj.CVMaxUEsToDisplay;
                obj.CVUpperRBIndex = obj.CVMaxRBsToDisplay;
                lb2 = uilabel(g,...
                    'Text',string(message('nr5g:networkModeler:UERangeLabelText')),...
                    'ToolTip',string(message('nr5g:networkModeler:UERangeLabelTooltip')));
                lb2.Layout.Row = compCounter;
                lb2.Layout.Column = 1;
                [items, itemsData] = cvDropDownForUERange(obj);
                dd2 = uidropdown(g,'Items',items, 'ItemsData', itemsData, ...
                    'ValueChangedFcn', @(dd, event) cbSelectedUERange(obj, dd.Value),...
                    'ToolTip',string(message('nr5g:networkModeler:UERangeDropDownTooltip')));
                dd2.Layout.Row = compCounter;
                dd2.Layout.Column = 2;
            else
                obj.CVUpperUEIndex = obj.NumUEs;
            end

            % If post simulation log analysis enabled
            if isempty(obj.IsLogReplay) || obj.IsLogReplay
                % Create label for frame number
                compCounter = compCounter + 1;
                lb3 = uilabel(g, 'Text', string(message('nr5g:networkModeler:FrameNumberLabelText')));
                lb3.Layout.Row = compCounter;
                lb3.Layout.Column = 1;
                obj.CVTxtHandle = uilabel(g, 'Text', ' ');
                obj.CVTxtHandle.Layout.Row = compCounter;
                obj.CVTxtHandle.Layout.Column = 2;
            else
                if obj.IsLegendRequired
                    compCounter = compCounter + 1;
                    lb3 = uilabel(g, ...
                        'Text', string(message('nr5g:networkModeler:TotalFramesLabelText')),...
                        'ToolTip',string(message('nr5g:networkModeler:TotalFramesLabelTooltip')));
                    lb3.Layout.Row = compCounter;
                    lb3.Layout.Column = 1;
                    lb3 = uilabel(g, ...
                        'Text', ""+obj.NumFrames,...
                        'ToolTip',string(message('nr5g:networkModeler:TotalFramesLabelTooltip')));
                    lb3.Layout.Row = compCounter;
                    lb3.Layout.Column = 2;
                end
                compCounter = compCounter + 1;
                lb4  = uilabel(g, ...
                    'Text',string(message('nr5g:networkModeler:FrameNumberEditLabelText')),...
                    'ToolTip',string(message('nr5g:networkModeler:FrameNumberEditLabelTooltip')));
                lb4.Layout.Row = compCounter;
                lb4.Layout.Column = 1;
                if obj.IsLegendRequired
                    obj.CVTxtHandle = uieditfield(g, 'numeric', 'Value', 0, 'ValueChangedFcn', @(dd, event) showFrame(obj, dd.Value),...
                        'Limits', [0 obj.NumFrames-1],...
                        'ToolTip',string(message('nr5g:networkModeler:FrameNumberEditLabelTooltip')));
                else
                    obj.CVTxtHandle = uilabel(g, 'Text', ' ');
                end
                obj.CVTxtHandle.Layout.Row = compCounter;
                obj.CVTxtHandle.Layout.Column = 2;
            end

            % Construct the MCS map
            titleText = string(message('nr5g:networkModeler:MCSTitleText'));
            if ~obj.IsLegendRequired
                titleText = titleText+" for Cell ID - "+num2str(obj.CellOfInterest);
            end
            if obj.CVMaxRBsToDisplay <= maxRBs
                obj.CVUpperRBIndex = obj.CVMaxRBsToDisplay;
            else
                obj.CVUpperRBIndex = maxRBs;
            end

            % Number of UEs to be displayed in the default view of MCS visualization
            if obj.CVMaxUEsToDisplay <= obj.NumUEs
                obj.CVUpperUEIndex = obj.CVMaxUEsToDisplay;
            else
                obj.CVUpperUEIndex = obj.NumUEs;
            end
            numRBsToDisplay = obj.CVUpperRBIndex - obj.CVLowerRBIndex;
            numUEsToDisplay = obj.CVUpperUEIndex - obj.CVLowerUEIndex;

            title = uilabel(g, ...
                'Text',titleText, ...
                'FontSize', 18, 'WordWrap', 'on');
            title.Layout.Row = [1 2];
            title.Layout.Column = 4;
            if obj.NumUEs == 0 % Display the message
                bannerText = string(message('nr5g:networkModeler:NoUEBannerText'));
                obj.MCSMapHandle = uilabel(g , 'HorizontalAlignment', 'center', 'Text', bannerText, ...
                    'FontSize', 20,"WordWrap","on");
                if ~isempty(obj.MCSMapHandle)
                    obj.MCSMapHandle.Visible = 'off';
                end
            else % Display the MCS Map
                obj.MCSMapHandle = heatmap(g, -1*ones(numRBsToDisplay, numUEsToDisplay), ...
                    'CellLabelColor', 'none', 'XLabel', 'UEs', 'YLabel', ...
                    'Resource Blocks', 'ColorLimits', [-1 27], 'Colormap', parula(29),'GridVisible',true);
            end
            % Set MCS-visualization axis label
            updateMCSMapProperties(obj);

            % Set the layout
            obj.MCSMapHandle.Layout.Row = [1 8];
             obj.MCSMapHandle.Layout.Column = [3 5];
        end

        function constructResourceGridVisualization(obj, varargin)
            %constructResourceGridVisualization Construct resource grid visualization
            %
            % constructResourceGridVisualization(OBJ, Info) Construct resource grid visualization
            %
            % Info - Info can be figure handle or a logical value. If it is a figure
            % handle, it is used for plotting. If it is logical value existing figure
            % is used.

            import matlab.graphics.internal.themes.specifyThemePropertyMappings
            maxRBs = max(obj.NumRBs(obj.PlotIds));
            updateLegend = true;
            if nargin == 2
                if islogical(varargin{1})
                    updateLegend = varargin{1};
                    g = obj.RGVisualizationFigHandle.Children;
                else
                    obj.RGVisualizationFigHandle = varargin{1};
                    obj.ResourceGridVisualization = true;
                end
            end

            if updateLegend % Update the cell specific legend information
                g = uigridlayout(obj.RGVisualizationFigHandle, [15 3], 'Scrollable','on');
                titleText = string(message('nr5g:networkModeler:ResourceGridAllocation'));
                if ~obj.IsLegendRequired
                    titleText = titleText+" for Cell ID - "+num2str(obj.CellOfInterest);
                end
                g.ColumnWidth = {'fit','fit','1x', 'fit', '1x'};
                g.RowHeight = {'fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit'};

                title = uilabel(g, 'Text', titleText, 'FontSize', 18);
                title.Layout.Row = [1 2];
                title.Layout.Column = 4;
                obj.RBGridTable = uitable(g, Data=table, RowStriping='off');
                obj.RBGridTable.Layout.Column = [3 5];
                obj.RBGridTable.Layout.Row = [3 15];
                htmlInterp = uistyle("Interpreter",'html'); % Necessary for html markup in the cells
                addStyle(obj.RBGridTable,htmlInterp);

                compCounter = 2;
                lb1 = uilabel(g,'Text',string(message('nr5g:networkModeler:UeNTransmissionText')));
                lb1.Layout.Row = compCounter;
                compCounter = compCounter + 1;
                lb1.Layout.Column = [1 2];
                lb1 = uilabel(g,'Text',string(message('nr5g:networkModeler:UeNRetransmissionText')));
                specifyThemePropertyMappings(lb1,FontColor="--mw-graphics-colorOrder-1-quaternary")
                lb1.Layout.Row = compCounter;
                compCounter = compCounter + 1;
                lb1.Layout.Column = [1 2];
                lb1 = uilabel(g,'Text',string(message('nr5g:networkModeler:UeNameText')));
                lb1.Layout.Row = compCounter;
                compCounter = compCounter + 1;
                lb1.Layout.Column = [1 2];
                lb1 = uilabel(g,'Text', string(message('nr5g:networkModeler:HarqProcessIdText')));
                lb1.Layout.Row = compCounter;
                compCounter = compCounter + 1;
                lb1.Layout.Column = [1 2];

                if ~isempty(obj.IsLogReplay) && ~isempty(obj.SimulationLogs) && obj.IsLogReplay == 0
                    numCells = numel(obj.SimulationLogs);
                    compCounter = compCounter + 1;
                    cellNames = strings(numCells,1);
                    for idx=1:numCells
                        cellNames(idx) = obj.SimulationLogs{idx}.CellName;
                    end
                    lb1 = uilabel(g, ...
                        'Text',string(message('nr5g:networkModeler:CellLabelText')), ...
                        'ToolTip',string(message('nr5g:networkModeler:CellLabelTooltip')));
                    lb1.Layout.Row = compCounter;
                    lb1.Layout.Column = 1;
                    dd = uidropdown(g, ...
                        'Items',cellNames, ...
                        'ItemsData', 1:numCells, ...
                        'ValueChangedFcn', @(dd, event) cellChanged(obj, dd.Items{dd.Value}), ...
                        'ToolTip',string(message('nr5g:networkModeler:CellLabelTooltip')));
                    dd.Layout.Row = compCounter;
                    dd.Layout.Column = 2;
                    if numCells == 1
                        dd.Enable = false;
                    end
                end

                % Create drop-down for link type
                if min(obj.NumLogs, numel(obj.PlotIds))== 2
                    compCounter = compCounter + 1;
                    lb1 = uilabel(g, ...
                        'Text',string(message('nr5g:networkModeler:LinkLabelText')), ...
                        'ToolTip',string(message('nr5g:networkModeler:LinkLabelTooltip')));
                    lb1.Layout.Row = compCounter;
                    lb1.Layout.Column = 1;
                    dd1 = uidropdown(g, ...
                        'Items',[...
                        string(message('nr5g:networkModeler:LinkDirectionDownlinkText')), ...
                        string(message('nr5g:networkModeler:LinkDirectionUplinkText'))], ...
                        'ItemsData', obj.PlotIds, ...
                        'ValueChangedFcn', @(dd, event) rbSelectedLinkType(obj, dd.Value), ...
                        'ToolTip',string(message('nr5g:networkModeler:LinkLabelTooltip')));
                    dd1.Layout.Row = compCounter;
                    dd1.Layout.Column = 2;
                end
            else
                compCounter = obj.RGVisualizationFigHandle.Children.Children(end).Layout.Row;
            end

            % Construct drop down menu for RB range
            if obj.RGMaxRBsToDisplay <= maxRBs
                compCounter = compCounter + 1;
                lb2 = uilabel(g, ...
                    'Text',string(message('nr5g:networkModeler:RBRangeLabelText')), ...
                    'ToolTip',string(message('nr5g:networkModeler:RBRangeLabelTooltip')));
                lb2.Layout.Row = compCounter;
                lb2.Layout.Column = 1;
                [items, itemsData] = constructRBItemList(obj, obj.NumRBs(obj.RVCurrView));
                dd2 = uidropdown(g, ...
                    'Items',items, ...
                    'ItemsData', itemsData, ...
                    'ValueChangedFcn', @(dd, event) rgSelectedRBRange(obj, dd.Value), ...
                    'ToolTip',string(message('nr5g:networkModeler:RBRangeLabelTooltip')));
                dd2.Layout.Row = compCounter;
                dd2.Layout.Column = 2;
            end

            % If post simulation log analysis enabled
            if isempty(obj.IsLogReplay) || obj.IsLogReplay
                compCounter = compCounter + 1;
                % Create label for frame number
                lb3 = uilabel(g, 'Text', string(message('nr5g:networkModeler:FrameNumberLabelText')));
                lb3.Layout.Row = compCounter;
                lb3.Layout.Column = 1;
                obj.RGTxtHandle  = uilabel(g, 'Text', '');
                obj.RGTxtHandle.Layout.Row = compCounter;
                obj.RGTxtHandle.Layout.Column = 2;
                if obj.SchedulingType % Symbol based scheduling
                    compCounter = compCounter + 1;
                    % Create label for slot number
                    lb3 = uilabel(g, 'Text', string(message('nr5g:networkModeler:SlotNumberLabelText')));
                    lb3.Layout.Row = compCounter;
                    lb3.Layout.Column = 1;
                    obj.RGSlotTxtHandle = uilabel(g, 'Text', '');
                    obj.RGSlotTxtHandle.Layout.Row = compCounter;
                    obj.RGSlotTxtHandle.Layout.Column = 2;
                end
            else
                compCounter = compCounter + 1;
                lb3 = uilabel(g, ...
                    'Text', string(message('nr5g:networkModeler:TotalFramesLabelText')), ...
                    'ToolTip', string(message('nr5g:networkModeler:TotalFramesLabelTooltip')));
                lb3.Layout.Row = compCounter;
                lb3.Layout.Column = 1;
                lb3 = uilabel(g, ...
                    'Text', ""+obj.NumFrames, ...
                    'ToolTip', string(message('nr5g:networkModeler:TotalFramesLabelTooltip')));
                lb3.Layout.Row = compCounter;
                lb3.Layout.Column = 2;
                compCounter = compCounter + 1;
                lb4  = uilabel(g, ...
                    'Text', string(message('nr5g:networkModeler:FrameNumberEditLabelText')), ...
                    'ToolTip', string(message('nr5g:networkModeler:RbFrameNumberEditLabelTooltip')));
                lb4.Layout.Row = compCounter;
                lb4.Layout.Column = 1;
                obj.RGTxtHandle = uieditfield(g, 'numeric', 'Value' , 0, ...
                    'ValueChangedFcn', @(dd, event) showFrame(obj, dd.Value), ...
                    'Limits', [0 obj.NumFrames-1], ...
                    'ToolTip', string(message('nr5g:networkModeler:RbFrameNumberEditLabelTooltip')));
                obj.RGTxtHandle.Layout.Row = compCounter;
                obj.RGTxtHandle.Layout.Column = 2;
                if obj.SchedulingType % Symbol based scheduling
                    compCounter = compCounter + 1;
                    lb4  = uilabel(g, ...
                        'Text', string(message('nr5g:networkModeler:SlotNumberEditLabelText')), ...
                        'ToolTip', string(message('nr5g:networkModeler:SlotNumberEditLabelTooltip')));
                    lb4.Layout.Row = compCounter;
                    lb4.Layout.Column = 1;
                    obj.RGSlotTxtHandle = uieditfield(g, 'numeric', 'Value' , 0, ...
                        'ValueChangedFcn', @(dd, event) showSlot(obj, dd.Value), ...
                        'Limits', [0 obj.NumSlotsFrame-1], ...
                        'ToolTip', string(message('nr5g:networkModeler:SlotNumberEditLabelTooltip')));
                    obj.RGSlotTxtHandle.Layout.Row = compCounter;
                    obj.RGSlotTxtHandle.Layout.Column = 2;
                    obj.CurrFrame  = 0;
                    obj.CurrSlot = 0;
                end
            end

            if obj.SchedulingType == obj.SlotBased && obj.RGMaxSlotsToDisplay < obj.NumSlotsFrame
                compCounter = compCounter + 1;
                % Create drop-down for Slot range
                lb2 = uilabel(g, ...
                    'Text', string(message('nr5g:networkModeler:SlotRangeLabelText')), ...
                    'ToolTip', string(message('nr5g:networkModeler:SlotRangeLabelTooltip')));
                lb2.Layout.Row = compCounter;
                lb2.Layout.Column = 1;
                [items, itemsData] = rgDropDownForSlotRange(obj);
                dd2 = uidropdown(g,'Items',items, 'ItemsData', itemsData, ...
                    'ValueChangedFcn', @(dd, event) rgSelectedSlotRange(obj, dd.Value), ...
                    'ToolTip', string(message('nr5g:networkModeler:SlotRangeLabelTooltip')));
                dd2.Layout.Row = compCounter;
                dd2.Layout.Column = 2;
            end

            % Number of RBs to be displayed in the default view of resource grid visualization
            if obj.RGMaxRBsToDisplay <= maxRBs
                obj.RGUpperRBIndex = obj.RGMaxRBsToDisplay;
            else
                obj.RGUpperRBIndex = maxRBs;
            end
            % Number of slots to be displayed in the default view of resource grid visualization
            if obj.NumSlotsFrame >= obj.RGMaxSlotsToDisplay
                obj.RGUpperSlotIndex = obj.RGMaxSlotsToDisplay;
            else
                obj.RGUpperSlotIndex = obj.NumSlotsFrame;
            end

            if obj.SchedulingType
                % Initialize the symbol pattern in a slot
                for sidx =1:obj.NumSym
                    obj.SymSlotInfo{sidx} = "Symbol-" + (sidx-1);
                end
            else
                % Initialize the slot pattern in a frame
                for sidx =1:obj.NumSlotsFrame
                    obj.SymSlotInfo{sidx} = "Slot-" + (sidx-1);
                end
            end

            % Set resource-grid visualization axis label
            rgSelectedSlotRange(obj, 0);
            rgSelectedRBRange(obj, 0);
            updateResourceGridVisualization(obj);
            drawnow;
        end

        function updateMCSVisualization(obj)
            %updateMCSVisualization Update the MCS map

            if obj.NumUEs == 0 || isempty(obj.CurrFrame)
                return;
            end

            % Check if the figure handle is valid
            if ~obj.IsLegendRequired && (isempty(obj.MCSVisualizationFigHandle) || ~ishghandle(obj.MCSVisualizationFigHandle))
                return;
            end

            if obj.SchedulingType == obj.SlotBased
                obj.CurrSlot = obj.NumSlotsFrame - 1;
            end

            if ~obj.IsLegendRequired
                obj.CVTxtHandle.Text = ""+obj.CurrFrame;
            end

            % Get the MCS information
            [obj.MCSInfo{1}, obj.MCSInfo{2}] = obj.SchedulingLogger.getMCSRBGridsInfo(obj.CurrFrame, obj.CurrSlot);
            % Make the MCS Map grid structure similar to RBG map
            obj.MCSMapHandle.ColorData = obj.MCSInfo{obj.CVCurrView}(obj.CVLowerUEIndex+1:obj.CVUpperUEIndex, obj.CVLowerRBIndex+1:obj.CVUpperRBIndex)';
            drawnow;
        end

        function updateResourceGridVisualization(obj)
            %updateResourceGridVisualization Update the resource grid visualization

            import matlab.graphics.internal.themes.specifyThemePropertyMappings
            if isempty(obj.IsLogReplay) || obj.IsLogReplay == 1
                if isempty(obj.CurrFrame)
                    obj.RGTxtHandle.Text = "";
                else
                    obj.RGTxtHandle.Text = ""+obj.CurrFrame; % Update the frame number
                end
            end
            if obj.SchedulingType % For symbol based scheduling
                lowLogIdx = 0;
                uppLogIdx = obj.NumSym;
                % Update the column names
                obj.RBGridTable.ColumnName = obj.SymSlotInfo;
                if isempty(obj.IsLogReplay) || obj.IsLogReplay == 1
                    obj.RGSlotTxtHandle.Text = ""+obj.CurrSlot; % Update the slot number
                end
            else % For slot based scheduling
                lowLogIdx = obj.RGLowerSlotIndex;
                uppLogIdx = obj.RGUpperSlotIndex;
                obj.RBGridTable.ColumnName = obj.SymSlotInfo(lowLogIdx+1:uppLogIdx);
            end

            obj.RBGridTable.Data = obj.ResourceGridInfoText{obj.RVCurrView}(lowLogIdx+1:uppLogIdx,obj.RGLowerRBIndex+1:obj.RGUpperRBIndex)';
            drawnow;
        end

        function plotPostSimRBGrids(obj, simSlotNum)
            %plotPostSimRBGrids Post simulation log visualization
            %
            % plotPostSimRBGrids(OBJ, SIMSLOTNUM) To update the resource
            % grid and MCS visualization based on the post simulation logs.
            %
            % SIMSLOTNUM - Cumulative slot number in the simulation

            % Update slot number
            if obj.SchedulingType % Symbol based scheduling
                obj.CurrSlot = mod(simSlotNum-1, obj.NumSlotsFrame);
                if obj.CurrSlot == 0
                    obj.CurrFrame = floor(simSlotNum/obj.NumSlotsFrame);
                end
            else % Slot based scheduling
                obj.CurrSlot = obj.NumSlotsFrame - 1;
                obj.CurrFrame = floor(simSlotNum/obj.NumSlotsFrame) - 1;
            end

            % Update grid information at slot boundary (for symbol based
            % scheduling) and frame boundary (for slot based scheduling)
            % Update resource grid visualization
            plotRBGrids(obj);
            % Update MCS visualization
            plotMCSRBGrids(obj);
        end

        function showFrame(obj, frameNumber)
            %showFrame Handle the event when user enters a
            % number to visualize a particular frame number in the
            % simulation

            if obj.NumUEs == 0
                return;
            end
            % Update the resource grid and MCS grid visualization
            try
                validateattributes(frameNumber, {'numeric'}, {'real', 'integer', 'scalar'});
            catch
                if ~obj.IsLegendRequired || obj.ResourceGridVisualization
                    figure = obj.RGVisualizationFigHandle;
                    obj.RGTxtHandle.Value = obj.CurrFrame;
                else
                    figure = obj.MCSVisualizationFigHandle;
                    obj.CVTxtHandle.Value = obj.CurrFrame;
                end
                uialert(figure, string(message('nr5g:networkModeler:FrameNumberNonnegativeInteger')), ...
                    obj.AlertBoxTitle,'Interpreter','html');
                return;
            end

            obj.CurrFrame = frameNumber;
            if obj.MCSGridVisualization
                updateMCSVisualization(obj);
            end
            if obj.ResourceGridVisualization
                plotRBGrids(obj);
            end
        end

        function showSlot(obj, slotNumber)
            %showFrame Handle the event when user enters a
            % number to visualize a particular slot number in the
            % simulation

            try
                validateattributes(slotNumber, {'numeric'}, {'real', 'integer', 'scalar'});
            catch
                obj.RGSlotTxtHandle.Value = obj.CurrSlot;
                uialert(obj.RGVisualizationFigHandle, string(message('nr5g:networkModeler:SlotNumberNonnegativeInteger')), ...
                    obj.AlertBoxTitle,'Interpreter','html');
                return;
            end
            obj.CurrSlot = slotNumber;
            % Update the resource grid and MCS grid visualization
            if obj.ResourceGridVisualization
                plotRBGrids(obj);
            end
        end
    end

    methods(Access = public)
        function [itemList, itemData] = constructRBItemList(obj, numRBs)
            %constructRBItemList Create the items for the drop-down component

            % Create the items for the drop-down component
            numItems = floor(numRBs / obj.RGMaxRBsToDisplay);
            itemList = strings(numItems, 1);
            itemData = zeros(ceil(numRBs / obj.RGMaxRBsToDisplay), 1);
            for i = 1 : numItems
                itemData(i) = (i - 1) * obj.RGMaxRBsToDisplay;
                itemList(i) = "RB "+itemData(i)+"-"+(itemData(i)+obj.RGMaxRBsToDisplay-1);
            end
            if (mod(numRBs,obj.RGMaxRBsToDisplay) > 0)
                itemData(i+1) = i * obj.RGMaxRBsToDisplay;
                itemList(i+1) = "RB "+itemData(i+1)+'-'+(numRBs - 1);
            end
        end

        function [itemList, itemData] = rgDropDownForSlotRange(obj)
            %rgDropDownForSlotRange Construct drop-down component for selecting slot range

            % Create the items for the drop-down component
            numItems = floor(obj.NumSlotsFrame / obj.RGMaxSlotsToDisplay);
            itemData = zeros(ceil(obj.NumSlotsFrame / obj.RGMaxSlotsToDisplay), 1);
            itemList = strings(numItems, 1);
            for i = 1 : numItems
                itemData(i) = (i-1) * obj.RGMaxSlotsToDisplay ;
                itemList(i) = "Slot "+itemData(i)+'-'+(itemData(i)+obj.RGMaxSlotsToDisplay-1);
            end
            if (mod(obj.NumSlotsFrame, obj.RGMaxSlotsToDisplay) > 0)
                itemData(i+1) = i * obj.RGMaxSlotsToDisplay + 1;
                itemList(i) = "Slot "+(itemData(i+1)-1)+'-'+(obj.NumSlotsFrame-1);
            end
        end

        function [itemList, itemData] = cvDropDownForUERange(obj)
            %cvDropDownForUERange Construct drop-down component for selecting UEs

            % Create the items for the drop-down component
            numItems = floor(obj.NumUEs / obj.CVMaxUEsToDisplay);
            itemData = zeros(ceil(obj.NumUEs / obj.CVMaxUEsToDisplay), 1);
            itemList = strings(numItems, 1);
            for i = 1 : numItems
                itemData(i) = (i - 1) * obj.CVMaxUEsToDisplay;
                itemList(i) = "UE "+(itemData(i)+1)+'-'+(itemData(i)+obj.CVMaxUEsToDisplay);
            end
            if (mod(obj.NumUEs,obj.CVMaxUEsToDisplay) > 0)
                itemData(i+1) = i * obj.CVMaxUEsToDisplay;
                itemList(i+1) = "UE "+(itemData(i+1)+1)+'-'+(itemData(i+1)+mod(obj.NumUEs, obj.CVMaxUEsToDisplay));
            end
        end

        function cellChanged(obj, cellName)
            %cellChanged Handle the event when user selects a cell

            for idx=1:numel(obj.SimulationLogs)
                if obj.SimulationLogs{idx}.CellName == cellName
                    break;
                end
            end

            logInfo = obj.SimulationLogs{idx};
            updateContext(obj, logInfo.GNB, logInfo.UEs)
            % Determine which logger object to create
            logObj = nrwnm.schedulingLogger(logInfo.NumFramesSim, logInfo.GNB, logInfo.UEs, IsLogReplay=0);
            if strcmpi(logInfo.GNB.DuplexMode,"TDD") % TDD
                logObj.SchedulingLog{1} = logInfo.TimeStepLogs(2:end,:);
            else % FDD
                logObj.SchedulingLog{1} = logInfo.DLTimeStepLogs(2:end,:);
                logObj.SchedulingLog{2} = logInfo.ULTimeStepLogs(2:end,:);
            end
            obj.SchedulingLogger = matlab.lang.WeakReference(logObj).Handle;
            if obj.ResourceGridVisualization
                % Delete the old components and add new components related
                % to the selected cell configuration
                if obj.DuplexMode
                    idx = 9;
                else
                    idx= 11;
                end
                delete(obj.RGVisualizationFigHandle.Children.Children(idx:end));
                constructResourceGridVisualization(obj, false);
            end
            if obj.MCSGridVisualization
                delete(obj.MCSVisualizationFigHandle.Children.Children(6:end));
                constructMCSGridVisualization(obj, false);
            end
            showFrame(obj, 0);
        end

        function rgSelectedRBRange(obj, lowerRBIndex)
            %rgSelectedRBRange Handle the event when user selects RB range in resource grid visualization

            obj.RGLowerRBIndex = lowerRBIndex;
            obj.RGUpperRBIndex = obj.RGLowerRBIndex + obj.RGMaxRBsToDisplay;
            if obj.RGUpperRBIndex > obj.NumRBs(obj.RVCurrView)
                obj.RGUpperRBIndex = obj.NumRBs(obj.RVCurrView);
            end
            obj.RBGridTable.RowName = "RB-"+(obj.RGLowerRBIndex:obj.RGUpperRBIndex);
            updateResourceGridVisualization(obj);
        end

        function rgSelectedSlotRange(obj, lowerSlotIndex)
            %rgSelectedSlotRange Handle the event when user selects slot range in resource grid visualization

            obj.RGLowerSlotIndex = lowerSlotIndex;
            obj.RGUpperSlotIndex = obj.RGLowerSlotIndex + obj.RGMaxSlotsToDisplay;
            if obj.RGUpperSlotIndex > obj.NumSlotsFrame
                obj.RGUpperSlotIndex = obj.NumSlotsFrame;
            end
            % Update the X-Axis of the resource grid visualization with
            % selected slot range
            obj.RBGridTable.ColumnName = "Slot-"+(obj.RGLowerSlotIndex:obj.RGUpperSlotIndex);
            updateResourceGridVisualization(obj);
        end

        function rbSelectedLinkType(obj, plotIdx)
            %rbSelectedLinkType Handle the event when user selects link type in resource grid visualization

            % Update the resource grid visualization with selected link type
            if numel(obj.PlotIds) == 2
                obj.RVCurrView = plotIdx;
            end
            updateResourceGridVisualization(obj);
        end

        function mcsSelectedLinkType(obj, plotIdx)
            %mcscSelectedLinkType Handle the event when user selects link type in MCS visualization

            % Update the MCS visualization with selected link type
            if numel(obj.PlotIds) == 2
                obj.RVCurrView = plotIdx;
            end
            updateMCSMapProperties(obj);
        end

        function cbSelectedRBRange(obj, lowerRBIndex)
            %cbSelectedRBRange Handle the event when user selects RB range in MCS grid visualization

            obj.CVLowerRBIndex = lowerRBIndex;
            obj.CVUpperRBIndex = obj.CVLowerRBIndex + obj.CVMaxRBsToDisplay;
            if obj.CVUpperRBIndex > obj.NumRBs(obj.CVCurrView)
                obj.CVUpperRBIndex = obj.NumRBs(obj.CVCurrView);
            end
            % Update the Y-Axis limits of the MCS grid visualization with
            % selected RB range
            updateMCSMapProperties(obj);
        end

        function cbSelectedUERange(obj, lowerUEIndex)
            %cbSelectedUERange Handle the event when user selects UE range in MCS grid visualization

            obj.CVLowerUEIndex = lowerUEIndex;
            obj.CVUpperUEIndex = obj.CVLowerUEIndex + obj.CVMaxUEsToDisplay;
            if obj.CVUpperUEIndex  > obj.NumUEs
                obj.CVUpperUEIndex = obj.NumUEs;
            end
            % Update the X-Axis limits of the MCS grid visualization with
            % selected UE range
            updateMCSMapProperties(obj)
        end

        function cbSelectedLinkType(obj, plotIdx)
            %cbSelectedLinkType Handle the event when user selects link type in MCS grid visualization

            % Update the MCS grid visualization with selected link type
            if numel(obj.PlotIds) == 2
                obj.CVCurrView = plotIdx;
            end
            % Update the Y-Axis limits of the MCS grid visualization with
            % selected RB range
            updateMCSMapProperties(obj);
        end

        function updateMCSMapProperties(obj)
            %updateMCSMapProperties Update the MCS grid along X-axis or Y-axis w.r.t to the given input parameters

            numRBsToDisplay = obj.CVUpperRBIndex - obj.CVLowerRBIndex;
            numUEsToDisplay = obj.CVUpperUEIndex - obj.CVLowerUEIndex;
            obj.MCSMapHandle.ColorData = -1*ones(numRBsToDisplay, numUEsToDisplay);
            % Update X-Axis
            xTicksLabel = cell(numUEsToDisplay, 0);
            for i = 1:numUEsToDisplay
                xTicksLabel{i} = obj.UENames(obj.CVLowerUEIndex + i );
            end
            obj.MCSMapHandle.XDisplayLabels = xTicksLabel;

            % Update Y-Axis
            yTicksLabel = cell(numRBsToDisplay, 0);
            for i = 1 : numRBsToDisplay
                yTicksLabel{i} = "RB-" + (obj.CVLowerRBIndex+i-1);
            end
            obj.MCSMapHandle.YDisplayLabels = yTicksLabel;
            updateMCSVisualization(obj);
        end

        function setupGUI(obj)
            %setupGUI Create the visualization for cell of interest

            % Using the screen width and height, calculate the figure width and height
            isMO = matlab.internal.environment.context.isMATLABOnline || ...
                matlab.ui.internal.desktop.isMOTW;
            if isMO
                resolution = connector.internal.webwindowmanager.instance().defaultPosition;
            else
                resolution = get(0, 'ScreenSize');
            end

            screenWidth = resolution(3);
            screenHeight = resolution(4);
            figureWidth = screenWidth * 0.90;
            figureHeight = screenHeight * 0.85;

            if obj.MCSGridVisualization % Create MCS visualization
                obj.MCSVisualizationFigHandle = uifigure(Name=string(message('nr5g:networkModeler:MCSVisualization')), ...
                    Position=[screenWidth * 0.05 screenHeight * 0.05 figureWidth figureHeight], HandleVisibility='on');
                % Use desktop theme to support dark theme mode
                matlab.graphics.internal.themes.figureUseDesktopTheme(obj.MCSVisualizationFigHandle);
                constructMCSGridVisualization(obj);
                if ~isempty(obj.SchedulingLogger)
                    addDepEvent(obj.SchedulingLogger, @obj.plotMCSRBGrids, obj.NumSlotsFrame); % Invoke for every frame
                end
            end

            if obj.ResourceGridVisualization % Create resource grid visualization
                obj.RGVisualizationFigHandle = uifigure(Name=string(message('nr5g:networkModeler:ResourceGridAllocation')), ...
                    Position=[screenWidth*0.05 screenHeight*0.05 figureWidth figureHeight], HandleVisibility='on');
                % Use desktop theme to support dark theme mode
                matlab.graphics.internal.themes.figureUseDesktopTheme(obj.RGVisualizationFigHandle);
                constructResourceGridVisualization(obj);
                if ~isempty(obj.SchedulingLogger)
                    if obj.SchedulingType == obj.SymbolBased
                        addDepEvent(obj.SchedulingLogger, @obj.plotRBGrids, 1); % Invoke for every slot
                    else
                        addDepEvent(obj.SchedulingLogger, @obj.plotRBGrids, obj.NumSlotsFrame); % Invoke for every frame
                    end
                end
            end
        end
    end
end
