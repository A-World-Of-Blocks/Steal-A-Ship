-- BaseLocker (Script, child of a ProximityPrompt)
--
-- When a player triggers the ProximityPrompt on their island's lock,
-- a visible cylindrical force-field is raised around their PlayerIsland
-- for 30 seconds. Only the triggering player can pass through it –
-- anyone else is pushed back out on contact.
--
-- Setup requirements (no extra parts needed):
--   • This script must be a child of a ProximityPrompt.
--   • The ProximityPrompt (and its parent part) must be a descendant of a
--     Model named "PlayerIsland" (e.g. on a "LockButton" BasePart).
--
--   • Island ownership: the PlayerIsland that CONTAINS the triggered prompt
--     is treated as that player's island. Make sure each player's island is
--     the Model named "PlayerIsland" that is an ancestor of the prompt.
--
-- The island centre is computed automatically from all BaseParts inside
-- the PlayerIsland model – no PrimaryPart required.

local RunService   = game:GetService("RunService")
local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local prompt = script.Parent  -- ProximityPrompt

print("[BaseLocker] Script loaded.")
print("[BaseLocker] script.Parent =", script.Parent, "| ClassName:", script.Parent and script.Parent.ClassName or "nil")
print("[BaseLocker] script.Parent.Parent =", script.Parent and script.Parent.Parent or "nil")

----------------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------------
local ISLAND_NAME      = "PlayerIsland"
local SHIELD_RADIUS    = 60        -- studs from island centre
local SHIELD_HEIGHT    = 80        -- tall enough to block jumpers
local SHIELD_THICKNESS = 2         -- wall thickness in studs
local SHIELD_DURATION  = 30        -- seconds the shield stays up (manual trigger)
local JOIN_SHIELD_DURATION = 60    -- seconds for the automatic join-protection shield
local SHIELD_COLOR     = Color3.fromRGB(0, 180, 255)
local SHIELD_TRANS     = 0.45      -- transparency of the shield wall
local CAP_TRANS        = 0.50      -- transparency of the flat top cap
local PUSH_VELOCITY    = 60        -- outward speed applied to intruders (studs/s)
local COOLDOWN         = 5         -- seconds before the prompt can be re-triggered

----------------------------------------------------------------------
-- FIND PARENT ISLAND
----------------------------------------------------------------------
local function findIsland(instance)
	print("[BaseLocker] findIsland() starting from:", instance:GetFullName())
	local current = instance
	while current do
		print("[BaseLocker]   checking ancestor:", current:GetFullName(), "| ClassName:", current.ClassName)
		if current:IsA("Model") and current.Name == ISLAND_NAME then
			print("[BaseLocker]   --> Found island:", current:GetFullName())
			return current
		end
		current = current.Parent
	end
	print("[BaseLocker]   --> No ancestor named '" .. ISLAND_NAME .. "' found. Walked all the way to nil.")
	return nil
end

local island = findIsland(prompt)
if not island then
	warn("[BaseLocker] ProximityPrompt is not a descendant of a model named '"
		.. ISLAND_NAME .. "'. Shield will not work.")
else
	print("[BaseLocker] Island found:", island:GetFullName())
end

----------------------------------------------------------------------
-- COMPUTE ISLAND CENTRE
-- Average position of all BaseParts in the island, Y set to the
-- lowest part so the shield sits on the ground.
----------------------------------------------------------------------
local function getIslandCenter(islandModel)
	local sum    = Vector3.new(0, 0, 0)
	local count  = 0
	local minY   = math.huge

	for _, obj in ipairs(islandModel:GetDescendants()) do
		if obj:IsA("BasePart") then
			sum   = sum + obj.Position
			count = count + 1
			local bottom = obj.Position.Y - obj.Size.Y / 2
			if bottom < minY then minY = bottom end
		end
	end

	print(string.format("[BaseLocker] getIslandCenter(): found %d BaseParts in '%s'", count, islandModel.Name))

	if count == 0 then
		local fallback = islandModel:GetPivot().Position
		warn("[BaseLocker] No BaseParts found in island – falling back to pivot:", fallback)
		return fallback
	end

	local avg = sum / count
	local result = Vector3.new(avg.X, minY, avg.Z)
	print(string.format("[BaseLocker] Island centre = (%.2f, %.2f, %.2f)  |  minY = %.2f", result.X, result.Y, result.Z, minY))
	return result
end

----------------------------------------------------------------------
-- BILLBOARD COUNTDOWN (floats above the island centre)
----------------------------------------------------------------------
local function createCountdownBillboard(adornPart, labelColor)
	labelColor = labelColor or Color3.fromRGB(80, 220, 255)
	print("[BaseLocker] createCountdownBillboard() adornee:", adornPart:GetFullName())
	local bg = Instance.new("BillboardGui")
	bg.Name         = "ShieldCountdown"
	bg.Adornee      = adornPart
	bg.Size         = UDim2.new(0, 220, 0, 65)
	bg.StudsOffset  = Vector3.new(0, SHIELD_HEIGHT / 2 + 10, 0)
	bg.AlwaysOnTop  = false
	bg.MaxDistance  = 200
	bg.ResetOnSpawn = false

	local frame = Instance.new("Frame", bg)
	frame.Size                   = UDim2.fromScale(1, 1)
	frame.BackgroundColor3       = Color3.fromRGB(0, 30, 60)
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel        = 0

	local corner = Instance.new("UICorner", frame)
	corner.CornerRadius = UDim.new(0, 12)

	local label = Instance.new("TextLabel", frame)
	label.Name                   = "TimeLabel"
	label.Size                   = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3             = labelColor
	label.TextScaled             = true
	label.Font                   = Enum.Font.GothamBold
	label.Text                   = "🛡 …"

	bg.Parent = adornPart
	print("[BaseLocker] BillboardGui created and parented to:", adornPart:GetFullName())
	return label
end

----------------------------------------------------------------------
-- BUILD THE CYLINDRICAL SHIELD WALL
-- A ring of overlapping flat panels using ForceField material, plus a
-- flat cap that seals the top so players can't fly/jump in from above.
-- CanCollide is FALSE — the wall is purely visual.
-- Enforcement is done with a per-frame proximity check (Heartbeat) so
-- that both walking players AND players in boats/vehicles are handled
-- correctly. The owner is always exempt.
----------------------------------------------------------------------
local PANEL_COUNT       = 80     -- more panels = seamless wall with no visible gaps
local CHECK_INTERVAL    = 0.1    -- seconds between enforcement checks (10/s is plenty)
local INNER_PUSH_RADIUS = SHIELD_RADIUS + 4  -- push anyone within this flat XZ radius

local function buildShield(center, ownerPlayer, duration, labelColor, isAutoShield)
	duration      = duration      or SHIELD_DURATION
	labelColor    = labelColor    or Color3.fromRGB(80, 220, 255)
	isAutoShield  = isAutoShield  or false

	print(string.format("[BaseLocker] buildShield() called | owner: %s | center: (%.2f, %.2f, %.2f) | duration: %ds",
		ownerPlayer.Name, center.X, center.Y, center.Z, duration))

	-- Container model so we can destroy everything at once
	local shieldModel  = Instance.new("Model")
	shieldModel.Name   = "IslandShield"
	shieldModel.Parent = workspace

	-- Invisible anchor part at the centre – used for the billboard
	local anchorPart        = Instance.new("Part")
	anchorPart.Name         = "ShieldAnchor"
	anchorPart.Size         = Vector3.new(0.1, 0.1, 0.1)
	anchorPart.CFrame       = CFrame.new(center + Vector3.new(0, SHIELD_HEIGHT / 2, 0))
	anchorPart.Anchored     = true
	anchorPart.CanCollide   = false
	anchorPart.Transparency = 1
	anchorPart.CastShadow   = false
	anchorPart.Parent       = shieldModel

	print("[BaseLocker] Anchor part placed at:", anchorPart.CFrame.Position)
	local countdownLabel = createCountdownBillboard(anchorPart, labelColor)

	-- chord = 2 * r * sin(halfAngle); 10% overlap so no gaps
	local angleStep  = (2 * math.pi) / PANEL_COUNT
	local panelWidth = 2 * SHIELD_RADIUS * math.sin(angleStep / 2) * 1.10

	print(string.format("[BaseLocker] Building %d panels | radius=%.1f | height=%.1f | panelWidth=%.3f",
		PANEL_COUNT, SHIELD_RADIUS, SHIELD_HEIGHT, panelWidth))

	local panels = {}

	for i = 0, PANEL_COUNT - 1 do
		local angle = i * angleStep
		local px = center.X + SHIELD_RADIUS * math.cos(angle)
		local pz = center.Z + SHIELD_RADIUS * math.sin(angle)
		local py = center.Y + SHIELD_HEIGHT / 2

		local panel        = Instance.new("Part")
		panel.Name         = "ShieldPanel"
		panel.Size         = Vector3.new(SHIELD_THICKNESS, SHIELD_HEIGHT, panelWidth)
		panel.CFrame       = CFrame.new(px, py, pz) * CFrame.Angles(0, angle, 0)
		panel.Anchored     = true
		panel.CanCollide   = false
		panel.CastShadow   = false
		panel.Material     = Enum.Material.ForceField
		panel.Color        = SHIELD_COLOR
		panel.Transparency = 1
		panel.Parent       = shieldModel

		TweenService:Create(panel,
			TweenInfo.new(0.6, Enum.EasingStyle.Sine),
			{ Transparency = SHIELD_TRANS }
		):Play()

		table.insert(panels, panel)
	end

	-- ── TOP CAP ────────────────────────────────────────────────────
	-- A flat circular disc that seals the top of the cylinder so
	-- nobody can fly or jump in from above.
	local capTopY     = center.Y + SHIELD_HEIGHT
	local capDiameter = SHIELD_RADIUS * 2
	local cap         = Instance.new("Part")
	cap.Name          = "ShieldCap"
	cap.Size          = Vector3.new(capDiameter, SHIELD_THICKNESS, capDiameter)
	cap.CFrame        = CFrame.new(center.X, capTopY, center.Z)
	cap.Anchored      = true
	cap.CanCollide    = false
	cap.CastShadow    = false
	cap.Material      = Enum.Material.ForceField
	cap.Color         = SHIELD_COLOR
	cap.Transparency  = 1
	cap.Shape         = Enum.PartType.Cylinder   -- round disc

	-- Cylinder in Roblox is oriented along X, so rotate 90° around Z to
	-- make the flat face point upward.
	cap.CFrame = CFrame.new(center.X, capTopY, center.Z) * CFrame.Angles(0, 0, math.pi / 2)
	cap.Parent = shieldModel

	TweenService:Create(cap,
		TweenInfo.new(0.6, Enum.EasingStyle.Sine),
		{ Transparency = CAP_TRANS }
	):Play()

	table.insert(panels, cap)   -- include in teardown loop
	print(string.format("[BaseLocker] Top cap placed at Y=%.2f, diameter=%.1f", capTopY, capDiameter))
	print(string.format("[BaseLocker] %d shield panels created (including top cap).", #panels))

	----------------------------------------------------------------------
	-- ENFORCEMENT: per-frame proximity check
	--
	-- For each non-owner player we check TWO positions every tick:
	--   1. Their HumanoidRootPart (walking / swimming)
	--   2. The BasePart their Humanoid.SeatPart is connected to (vehicle/boat)
	-- If either position is inside the shield radius on the XZ plane,
	-- we apply an outward push to whichever root part is relevant.
	-- The owner is skipped entirely.
	----------------------------------------------------------------------
	local enforceConn
	local elapsed = 0

	enforceConn = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < CHECK_INTERVAL then return end
		elapsed = 0

		for _, player in ipairs(Players:GetPlayers()) do
			-- Owner always passes freely
			if player == ownerPlayer then continue end

			local character = player.Character
			if not character then continue end

			local hrp = character:FindFirstChild("HumanoidRootPart")
			if not hrp then continue end

			-- Determine the "effective position" to check.
			-- If the player is seated in a vehicle, use the vehicle's root part
			-- so the entire boat gets pushed, not just the invisible character.
			local pushTarget = hrp   -- default: push the character root

			local humanoid = character:FindFirstChildWhichIsA("Humanoid")
			if humanoid and humanoid.SeatPart then
				-- SeatPart is the Seat/VehicleSeat the player is sitting on.
				-- Walk up to its root BasePart (the assembly root).
				local seat = humanoid.SeatPart
				local assemblyRoot = seat:GetRootPart()  -- physics assembly root
				if assemblyRoot then
					pushTarget = assemblyRoot
				end
			end

			-- Flat XZ distance from island centre to the push target
			local flatPos = Vector3.new(pushTarget.Position.X, center.Y, pushTarget.Position.Z)
			local dist    = (flatPos - center).Magnitude

			if dist <= INNER_PUSH_RADIUS then
				-- Push outward — stronger the closer they are to centre
				local outward = (flatPos - center)
				if outward.Magnitude < 0.1 then
					outward = Vector3.new(1, 0, 0)  -- fallback if exactly at centre
				end
				outward = outward.Unit

				-- Scale push force: full velocity at centre, tapers toward edge
				local strength = PUSH_VELOCITY * (1 + (INNER_PUSH_RADIUS - dist) / INNER_PUSH_RADIUS)

				print(string.format("[BaseLocker] Pushing '%s' outward (dist=%.1f, strength=%.0f)",
					player.Name, dist, strength))

				pushTarget.AssemblyLinearVelocity = Vector3.new(
					outward.X * strength,
					pushTarget.AssemblyLinearVelocity.Y,  -- preserve vertical so they don't fly up
					outward.Z * strength
				)
			end

			-- ── TOP CAP ENFORCEMENT ─────────────────────────────────
			-- If the player is above the shield ceiling AND within the
			-- XZ radius, push them upward (away from the interior).
			local topY = center.Y + SHIELD_HEIGHT
			if pushTarget.Position.Y > topY - 4
				and pushTarget.Position.Y < topY + 6
				and dist <= INNER_PUSH_RADIUS then
				-- They are trying to enter through the top — push upward
				pushTarget.AssemblyLinearVelocity = Vector3.new(
					pushTarget.AssemblyLinearVelocity.X,
					PUSH_VELOCITY,
					pushTarget.AssemblyLinearVelocity.Z
				)
			end
		end
	end)

	----------------------------------------------------------------------
	-- COUNTDOWN LOOP & TEARDOWN
	----------------------------------------------------------------------
	task.spawn(function()
		local timeLeft = duration

		while timeLeft > 0 do
			countdownLabel.Text = string.format("🛡 %ds", math.ceil(timeLeft))
			task.wait(0.1)
			timeLeft -= 0.1
		end

		-- Stop enforcement immediately
		enforceConn:Disconnect()

		-- Tween out panels
		for _, panel in ipairs(panels) do
			TweenService:Create(panel,
				TweenInfo.new(0.5, Enum.EasingStyle.Sine),
				{ Transparency = 1 }
			):Play()
		end

		task.wait(0.55)
		shieldModel:Destroy()

		-- Re-enable the prompt after cooldown (only if this was a manual trigger)
		if not isAutoShield then
			task.wait(COOLDOWN)
			if prompt and prompt.Parent then
				prompt.Enabled = true
			end
		end
	end)

	return shieldModel
end

----------------------------------------------------------------------
-- ACTIVE SHIELD GUARD (prevent stacking multiple shields)
----------------------------------------------------------------------
local shieldActive = false

----------------------------------------------------------------------
-- AUTO JOIN SHIELD
-- Fires as soon as the owning player's island is known and
-- protects their base for JOIN_SHIELD_DURATION seconds.
----------------------------------------------------------------------
if island then
	-- Find which player owns this island by watching PlayerAdded
	-- and cross-referencing via IslandBridge once it resolves.
	local ServerStorage  = game:GetService("ServerStorage")
	local islandBridge   = ServerStorage:FindFirstChild("IslandBridge")

	local function tryAutoShield(player)
		-- Poll until the island is assigned to this player (max 30 s)
		local resolvedIsland = nil
		for _ = 1, 300 do
			if islandBridge then
				resolvedIsland = islandBridge:Invoke(player.UserId)
			end
			if resolvedIsland == island then break end
			task.wait(0.1)
			resolvedIsland = nil
		end

		if resolvedIsland ~= island then return end  -- different island or timed out

		-- Only raise the join shield if no shield is currently active
		if shieldActive then return end
		shieldActive = true
		prompt.Enabled = false

		local center = getIslandCenter(island)
		-- Golden colour so players know this is the join-protection shield
		buildShield(center, player, JOIN_SHIELD_DURATION, Color3.fromRGB(255, 210, 60), true)

		task.delay(JOIN_SHIELD_DURATION + 0.6 + 0.1, function()
			shieldActive = false
			-- Re-enable the prompt now that join shield expired
			if prompt and prompt.Parent then
				prompt.Enabled = true
			end
		end)

		print(string.format("[BaseLocker] Join-protection shield raised for %s (%ds)", player.Name, JOIN_SHIELD_DURATION))
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(tryAutoShield, player)
	end)

	-- Handle players already in the server (Studio test / script reload)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(tryAutoShield, player)
	end
end

----------------------------------------------------------------------
-- TRIGGER (manual activation via ProximityPrompt)
----------------------------------------------------------------------
prompt.Triggered:Connect(function(player)
	if shieldActive then return end
	if not island then return end

	shieldActive      = true
	prompt.Enabled    = false

	local center = getIslandCenter(island)
	buildShield(center, player, SHIELD_DURATION, Color3.fromRGB(80, 220, 255), false)

	-- shieldActive is cleared when the shield teardown re-enables the prompt
	task.delay(SHIELD_DURATION + 0.6 + COOLDOWN + 0.1, function()
		shieldActive = false
	end)
end)
