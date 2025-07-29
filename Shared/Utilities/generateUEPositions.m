function uePositions = generateUEPositions(cellRadius,gNBPositions,numUEsPerCell)
%generateUEPositions Return the position of UE nodes in each cell

numCells = size(gNBPositions,1);
uePositions = cell(numCells,1);
ueHeight = 3; % In meters
for cellIdx=1:numCells
    gnbXCo = gNBPositions(cellIdx,1); % gNB X-coordinate
    gnbYCo = gNBPositions(cellIdx,2); % gNB Y-coordinate
    theta = rand(numUEsPerCell,1)*(2*pi);
    % Use these expressions to calculate the position of UE nodes within the cell. By default,
    % the placement of the UE nodes is random within the cell
    r = sqrt(rand(numUEsPerCell,1))*cellRadius;
    x = round(gnbXCo + r.*cos(theta));
    y = round(gnbYCo + r.*sin(theta));
    z = ones(numUEsPerCell,1) * ueHeight;
    uePositions{cellIdx} = [x y z];
end
end
