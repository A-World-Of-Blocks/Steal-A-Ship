local RunService = game:GetService("RunService")

local model = script.Parent
local primaryPart = model.PrimaryPart

if not primaryPart then
	warn("Grazing Script: Please assign a 'PrimaryPart' in the Model's properties!")
	return
end

-- Automatically anchor all parts so physics don't fight our math
for _, part in model:GetDescendants() do
	if part:IsA("BasePart") then
		part.Anchored = true
	end
end

-----------------------
-- CONFIGURATION --
-----------------------
local moveSpeed = 4 
local wanderRadius = 30 
local maxWaitTime = 8 

-- BOBBING CONFIGURATION
local bobSpeed = 6 -- How fast the model steps (higher = faster steps)
local bobHeight = 0.2 -- How high the model lifts off the ground per step (in studs)

-- Raycast setup
local raycastParams = RaycastParams.new()
raycastParams.FilterDescendantsInstances = {model}
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = false 

local startPos = model:GetPivot().Position
-- Start the initial height check lower so it doesn't hit a tree right away
local initialRay = workspace:Raycast(startPos + Vector3.new(0, 5, 0), Vector3.new(0, -50, 0), raycastParams)
local heightOffset = initialRay and (startPos.Y - initialRay.Position.Y) or 2

-----------------------
-- AI FUNCTIONS --
-----------------------
local function getSafeTargetPoint()
	local currentPos = model:GetPivot().Position

	for i = 1, 10 do
		local randomX = math.random(-wanderRadius, wanderRadius)
		local randomZ = math.random(-wanderRadius, wanderRadius)

		-- FIX: Cast from 10 studs above the model's current height, not 50 studs up in the sky.
		-- This shoots the ray from UNDER the tree canopy.
		local testPosition = currentPos + Vector3.new(randomX, 10, randomZ) 
		local raycastResult = workspace:Raycast(testPosition, Vector3.new(0, -20, 0), raycastParams)

		if raycastResult and raycastResult.Material ~= Enum.Material.Water then
			return raycastResult.Position
		end
	end

	return nil 
end

local function customMoveTo(targetPoint)
	local reached = false
	local connection
	local startTime = os.clock()

	connection = RunService.Heartbeat:Connect(function(deltaTime)
		local currentCFrame = model:GetPivot()
		local currentPos = currentCFrame.Position

		local direction = (targetPoint - currentPos)
		direction = Vector3.new(direction.X, 0, direction.Z)

		local distanceToTarget = direction.Magnitude

		if distanceToTarget < 0.5 then
			reached = true
			connection:Disconnect()
			return
		end

		local stepAmount = math.min(moveSpeed * deltaTime, distanceToTarget)
		local moveVector = direction.Unit * stepAmount
		local newPosXZ = currentPos + moveVector

		-- FIX: Raycast exactly 10 studs above the model's current Y height to hug the ground and ignore leaves
		local terrainRayOrigin = Vector3.new(newPosXZ.X, currentPos.Y + 10, newPosXZ.Z)
		local terrainRay = workspace:Raycast(terrainRayOrigin, Vector3.new(0, -20, 0), raycastParams)

		local finalPos
		if terrainRay and terrainRay.Material ~= Enum.Material.Water then
			finalPos = Vector3.new(newPosXZ.X, terrainRay.Position.Y + heightOffset, newPosXZ.Z)
		else
			reached = true
			connection:Disconnect()
			return
		end

		-- BOBBING EFFECT:
		-- math.sin goes up and down smoothly based on the clock.
		-- math.abs ensures the model only bobs UP (like a footstep) and never sinks below the ground.
		local bobOffset = math.abs(math.sin(os.clock() * bobSpeed)) * bobHeight
		finalPos = finalPos + Vector3.new(0, bobOffset, 0)

		-- Face the direction and apply the new position (including the bob)
		local lookAtCFrame = CFrame.lookAt(finalPos, finalPos + direction)
		model:PivotTo(lookAtCFrame)
	end)

	repeat
		task.wait(0.1)
	until reached or (os.clock() - startTime) > maxWaitTime

	if connection.Connected then
		connection:Disconnect()
	end
end

-----------------------
-- MAIN LOOP --
-----------------------
while true do
	local targetPoint = getSafeTargetPoint()

	if targetPoint then
		customMoveTo(targetPoint)
	else
		task.wait(1)
	end

	task.wait(math.random(1, 4))
end