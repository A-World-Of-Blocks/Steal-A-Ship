local Players       = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local TweenService  = game:GetService("TweenService")

----------------------------------------------------------------------
-- CONFIGURATION
----------------------------------------------------------------------
local BILLBOARD_HEIGHT_OFFSET = 30    -- studs above the island's highest part
local BILLBOARD_MAX_DISTANCE  = 0     -- 0 = unlimited
local ISLAND_NAME_PATTERN     = "PlayerIsland"
local BILLBOARD_NAME          = "YourBaseBillboard"
local SPAWNLOC_NAME           = "PlayerRespawn"  -- name we give the per-player SpawnLocation

-- How long to wait (seconds) for IslandBridge to resolve before falling back
-- to the old closest-position method.
local ISLAND_BRIDGE_TIMEOUT   = 20

----------------------------------------------------------------------
-- ISLAND BRIDGE
-- BrainrotSaveServer creates and owns this BindableFunction.
-- We wait up to ISLAND_BRIDGE_TIMEOUT seconds for it to appear so we don't
-- race against it on server start.
----------------------------------------------------------------------
local islandBridge = ServerStorage:WaitForChild("IslandBridge", ISLAND_BRIDGE_TIMEOUT)

local function getAssignedIsland(userId)
	if islandBridge then
		local ok, result = pcall(function()
			return islandBridge:Invoke(userId)
		end)
		if ok and result then return result end
	end
	return nil
end

----------------------------------------------------------------------
-- FALLBACK: find closest island by position (used only when IslandBridge
-- hasn't resolved yet, e.g. the player is a brand-new first-joiner and
-- BrainrotSaveServer is still in its RESTORE_DELAY wait).
----------------------------------------------------------------------
local function findClosestIslandByPos(rootPosition)
	local closest  = nil
	local bestDist = math.huge
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("Model") and string.find(obj.Name, ISLAND_NAME_PATTERN) then
			local pivot = obj:GetPivot().Position
			local dist  = (rootPosition - pivot).Magnitude
			if dist < bestDist then
				bestDist = dist
				closest  = obj
			end
		end
	end
	return closest
end

----------------------------------------------------------------------
-- SPAWN LOCATION HELPERS
-- Each island gets exactly one SpawnLocation named SPAWNLOC_NAME.
-- We create it if it doesn't exist, positioned at the island's pivot.
-- Setting player.RespawnLocation to this makes Roblox always spawn/
-- respawn THAT player there, with no other player sharing it.
----------------------------------------------------------------------
local function getOrCreateRespawnLocation(island)
	-- Re-use an existing one if already set up
	local existing = island:FindFirstChild(SPAWNLOC_NAME, true)
	if existing and existing:IsA("SpawnLocation") then
		return existing
	end

	-- Find a sensible position: PrimaryPart or highest BasePart
	local anchor = island.PrimaryPart
	if not anchor then
		local highY = -math.huge
		for _, p in ipairs(island:GetDescendants()) do
			if p:IsA("BasePart") and p.Position.Y > highY then
				highY  = p.Position.Y
				anchor = p
			end
		end
	end

	local spawnPos = anchor and CFrame.new(anchor.Position + Vector3.new(0, 5, 0))
		or island:GetPivot() * CFrame.new(0, 5, 0)

	local sl = Instance.new("SpawnLocation")
	sl.Name          = SPAWNLOC_NAME
	sl.Size          = Vector3.new(6, 1, 6)
	sl.CFrame        = spawnPos
	sl.Anchored      = true
	sl.CanCollide    = false   -- invisible underfoot, doesn't block movement
	sl.Transparency  = 1
	sl.Duration      = 0      -- no force field
	-- Neutral team – player.RespawnLocation overrides team assignment anyway
	sl.Neutral       = true
	sl.Parent        = island

	return sl
end

----------------------------------------------------------------------
-- ATTACH "YOUR BASE" BILLBOARD TO AN ISLAND
----------------------------------------------------------------------
local function attachBaseBillboard(island, playerName)
	local existing = island:FindFirstChild(BILLBOARD_NAME, true)
	if existing then existing:Destroy() end

	local adornPart = island.PrimaryPart
	if not adornPart then
		local highestY = -math.huge
		for _, p in ipairs(island:GetDescendants()) do
			if p:IsA("BasePart") and p.Position.Y > highestY then
				highestY  = p.Position.Y
				adornPart = p
			end
		end
	end
	if not adornPart then return end

	local bg = Instance.new("BillboardGui")
	bg.Name           = BILLBOARD_NAME
	bg.Adornee        = adornPart
	bg.Size           = UDim2.new(0, 260, 0, 70)
	bg.StudsOffset    = Vector3.new(0, BILLBOARD_HEIGHT_OFFSET, 0)
	bg.AlwaysOnTop    = false
	bg.MaxDistance    = BILLBOARD_MAX_DISTANCE
	bg.ResetOnSpawn   = false
	bg.LightInfluence = 0

	local frame = Instance.new("Frame", bg)
	frame.Size                   = UDim2.fromScale(1, 1)
	frame.BackgroundColor3       = Color3.fromRGB(0, 30, 60)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel        = 0
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 14)

	local stroke = Instance.new("UIStroke", frame)
	stroke.Color        = Color3.fromRGB(80, 220, 255)
	stroke.Thickness    = 2
	stroke.Transparency = 0.3

	local label = Instance.new("TextLabel", frame)
	label.Size                   = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3             = Color3.fromRGB(80, 220, 255)
	label.TextScaled             = true
	label.Font                   = Enum.Font.GothamBold
	label.Text                   = string.format("🏠 %s's Base", playerName)
	label.TextStrokeTransparency = 0.5
	label.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)

	bg.Parent = adornPart
end

----------------------------------------------------------------------
-- REMOVE OLD DEFAULT SPAWNLOCATIONS
-- Destroys any vanilla SpawnLocation that isn't one of ours, so players
-- can't accidentally respawn at a shared spawn.
----------------------------------------------------------------------
local function purgeDefaultSpawns()
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("SpawnLocation") and obj.Name ~= SPAWNLOC_NAME then
			obj:Destroy()
		end
	end
end

-- Run once at startup and watch for any that get added later
purgeDefaultSpawns()
workspace.DescendantAdded:Connect(function(obj)
	if obj:IsA("SpawnLocation") and obj.Name ~= SPAWNLOC_NAME then
		obj:Destroy()
	end
end)

----------------------------------------------------------------------
-- MAIN: ASSIGN ISLAND + RESPAWN POINT PER PLAYER
----------------------------------------------------------------------
local function setupPlayer(player)
	local userId = player.UserId

	-- ── 1. Resolve the player's island ───────────────────────────
	-- First try IslandBridge (authoritative, set by BrainrotSaveServer).
	-- If it's not ready yet, poll until ISLAND_BRIDGE_TIMEOUT then fall
	-- back to character position.
	local island = getAssignedIsland(userId)

	if not island then
		-- Poll IslandBridge for up to ISLAND_BRIDGE_TIMEOUT seconds
		local elapsed = 0
		while elapsed < ISLAND_BRIDGE_TIMEOUT do
			task.wait(1)
			elapsed = elapsed + 1
			island = getAssignedIsland(userId)
			if island then break end
			-- Safety: player may have left
			if not Players:GetPlayerByUserId(userId) then return end
		end
	end

	-- Fallback: use the character's spawn position if bridge never resolved
	if not island then
		local character = player.Character or player.CharacterAdded:Wait()
		local root      = character:WaitForChild("HumanoidRootPart", 10)
		if root then
			island = findClosestIslandByPos(root.Position)
		end
	end

	if not island then
		warn("[spawnpointremover] Could not resolve island for", player.Name)
		return
	end

	-- ── 2. Create/reuse the private SpawnLocation on their island ─
	local spawnLoc = getOrCreateRespawnLocation(island)

	-- Assign as the player's personal respawn point.
	-- Roblox will now always spawn THIS player at this location.
	-- No other player has this set, so nobody else spawns here.
	player.RespawnLocation = spawnLoc

	-- ── 3. Teleport to island on the FIRST spawn ─────────────────
	-- RespawnLocation only takes effect for future spawns, not the one
	-- that already happened while we were waiting for IslandBridge.
	-- If the character exists but is far from the SpawnLocation, move them.
	local spawnTarget = spawnLoc.CFrame * CFrame.new(0, 3, 0)

	local character = player.Character
	if character then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - spawnLoc.Position).Magnitude > 20 then
			root.CFrame = spawnTarget
		end
	else
		-- Character hasn't spawned yet – wait for it then move it
		local conn
		conn = player.CharacterAdded:Connect(function(char)
			conn:Disconnect()
			local root = char:WaitForChild("HumanoidRootPart", 10)
			if root then
				-- One frame delay so Roblox finishes placing the character
				task.defer(function()
					root.CFrame = spawnTarget
				end)
			end
		end)
	end

	-- ── 4. Attach "Your Base" billboard ──────────────────────────
	attachBaseBillboard(island, player.Name)

	print(string.format("[spawnpointremover] Island '%s' assigned to %s; RespawnLocation set.",
		island.Name, player.Name))
end

----------------------------------------------------------------------
-- PLAYER CONNECTIONS
----------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	task.spawn(setupPlayer, player)
end)

-- Clean up RespawnLocation reference when the player leaves
Players.PlayerRemoving:Connect(function(player)
	player.RespawnLocation = nil
end)

-- Handle players already in the server when this script runs
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end