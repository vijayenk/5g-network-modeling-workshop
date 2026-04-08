function uePositions = generateUEPositions(cellRadius,gNBPositions,numUEsPerCell,varargin)
%generateUEPositions Return the position of UE nodes in each cell

numCells = size(gNBPositions,1);
uePositions = cell(numCells,1);
ueHeight = 3; % In meters
% 0, π/6, π/3, π/2, 2π/3, 5π/6, π, 7π/6, 4π/3, 3π/2, 5π/3, 11π/6, 2π
for cellIdx=1:numCells
    gnbXCo = gNBPositions(cellIdx,1); % gNB X-coordinate
    gnbYCo = gNBPositions(cellIdx,2); % gNB Y-coordinate
    if nargin > 4
        if(varargin{2} == 1)
            startAngle = 0;
            endAngle = pi/6;
            theta = (endAngle-startAngle).*rand(numUEsPerCell,1) + startAngle;
        elseif(varargin{2} == 2)
            startAngle = pi/6;
            endAngle = pi/3;
            theta = (endAngle-startAngle).*rand(numUEsPerCell,1) + startAngle;
        elseif(varargin{2} == 3)
            startAngle = pi/3;
            endAngle = pi/2;
            theta = (endAngle-startAngle).*rand(numUEsPerCell,1) + startAngle;
        elseif(varargin{2} == 4)
            startAngle =pi/2;
            endAngle = 2*pi/3;
            theta = (endAngle-startAngle).*rand(numUEsPerCell,1) + startAngle;
        elseif(varargin{2} == 5)
            startAngle = 2*pi/3;
            endAngle = 5*pi/6;
            theta = (endAngle-startAngle).*rand(numUEsPerCell,1) + startAngle;
        elseif(varargin{2} == 6)
            startAngle = 5*pi/6;
            endAngle = pi;
            theta = (endAngle-startAngle).*rand(numUEsPerCell,1) + startAngle;
        elseif(varargin{2} == 7)
            startAngle = pi;
            endAngle = 7*pi/6;
            theta = (endAngle-startAngle).*rand(numUEsPerCell,1) + startAngle;
        elseif(varargin{2} == 8)
            startAngle = 7*pi/6;
            endAngle = 4*pi/3;
            theta = (endAngle-startAngle).*rand(numUEsPerCell,1) + startAngle;
        elseif(varargin{2} == 9)
            startAngle = 7*pi/6;
            endAngle = 4*pi/3;
            theta = (endAngle-startAngle).*rand(numUEsPerCell,1) + startAngle;
        elseif(varargin{2} == 10)
            startAngle = 4*pi/3;
            endAngle = 3*pi/2;
            theta = (endAngle-startAngle).*rand(numUEsPerCell,1) + startAngle;
        elseif(varargin{2} == 11)
            startAngle = 3*pi/2;
            endAngle = 5*pi/3;
            theta = (endAngle-startAngle).*rand(numUEsPerCell,1) + startAngle;
        elseif(varargin{2} == 12)
            startAngle = 11*pi/6;
            endAngle = 2*pi;
            theta = (endAngle-startAngle).*rand(numUEsPerCell,1) + startAngle;
        end
    else
        theta = rand(numUEsPerCell,1)*(2*pi);
    end

    % Use these expressions to calculate the position of UE nodes within the cell. By default,
    % the placement of the UE nodes is random within the cell
    if nargin > 3
        startDistance = varargin{1}*cellRadius;
        endDistance = cellRadius;
        r= (endDistance-startDistance).*rand(numUEsPerCell,1) + startDistance;
    else
        r = sqrt(rand(numUEsPerCell,1))*cellRadius;
    end
    x = round(gnbXCo + r.*cos(theta));
    y = round(gnbYCo + r.*sin(theta));
    z = ones(numUEsPerCell,1) * ueHeight;
    uePositions{cellIdx} = [x y z];
end
uePositions = cell2mat(uePositions);
end
