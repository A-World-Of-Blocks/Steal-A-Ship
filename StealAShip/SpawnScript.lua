-- BrainrotSpawner (Script, ServerScriptService)
-- Finds every part named "Spawner" in workspace (including descendants).
-- Each Spawner independently counts down 30 seconds, then spawns a random
-- brainrot model from ReplicatedStorage.Brainrots if one isn't already there.
-- A billboard above the spawner shows the countdown when empty.
-- When a server-wide Luck Boost is active, rarer brainrots spawn more often.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local ServerStorage     = game:GetService("ServerStorage")

local SPAWN_INTERVAL  = 10     -- seconds between spawns
local BRAINROT_FOLDER = ReplicatedStorage:WaitForChild("Brainrots")
local SPAWNER_NAME    = "Spawner"
local TAG_ATTRIBUTE   = "SpawnerOccupied"  -- attribute we set on the spawner part

-- BoostBridge: query BoostServer for the active luck power (nil = no boost)
local boostBridge = ServerStorage:WaitForChild("BoostBridge", 10)

local function getActiveLuckPower()
	if not boostBridge then return nil end
	local ok, val = pcall(function()
		return boostBridge:Invoke("getLuckPower")
	end)
	return (ok and type(val) == "number") and val or nil
end

----------------------------------------------------------------------
-- BILLBOARD HELPERS
----------------------------------------------------------------------
local function getOrCreateBillboard(spawnerPart)
	local existing = spawnerPart:FindFirstChild("SpawnerBillboard")
	if existing then return existing:FindFirstChildWhichIsA("TextLabel", true) end

	local bg = Instance.new("BillboardGui")
	bg.Name          = "SpawnerBillboard"
	bg.Adornee       = spawnerPart
	bg.Size          = UDim2.new(0, 140, 0, 50)
	bg.StudsOffset   = Vector3.new(0, 16, 0)
	bg.AlwaysOnTop   = false
	bg.MaxDistance   = 50
	bg.ResetOnSpawn  = false
	bg.Parent        = spawnerPart

	local frame = Instance.new("Frame", bg)
	frame.Size                   = UDim2.fromScale(1, 1)
	frame.BackgroundColor3       = Color3.fromRGB(15, 15, 15)
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel        = 0

	local corner = Instance.new("UICorner", frame)
	corner.CornerRadius = UDim.new(0, 8)

	local label = Instance.new("TextLabel", frame)
	label.Name                   = "CountdownLabel"
	label.Size                   = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3             = Color3.fromRGB(255, 200, 60)
	label.TextScaled             = true
	label.Font                   = Enum.Font.GothamBold

	return label
end

local function showCountdown(spawnerPart, seconds)
	local label = getOrCreateBillboard(spawnerPart)
	label.Text = string.format("⏱ %ds", math.ceil(seconds))
	label.Parent.Parent.Enabled = true
end

local function hideBillboard(spawnerPart)
	local bg = spawnerPart:FindFirstChild("SpawnerBillboard")
	if bg then bg.Enabled = false end
end

----------------------------------------------------------------------
-- SPAWN LOGIC
----------------------------------------------------------------------
-- RARITY / WEIGHTED SELECTION
-- We compute rarity automatically from each template's MoneyConfig.DollarsPerSecond.
-- Higher $/s -> lower weight (rarer).
-- Templates without a MoneyConfig get a random DPS between these values at spawn time:
local RARITY_BASE      = 1    -- avoids division by zero; >1 increases commonness of low-value items
local RARITY_POWER     = 1    -- >1 makes high-DPS even rarer; tweak to taste
local RANDOM_DPS_MIN   = 5    -- minimum $/s assigned to brainrots with no MoneyConfig
local RANDOM_DPS_MAX   = 35   -- maximum $/s assigned to brainrots with no MoneyConfig

-- Returns the DollarsPerSecond from the template's MoneyConfig, or nil if none found.
local function readDPSFromTemplate(model)
	local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
	local cfg = nil
	if prompt then
		cfg = prompt:FindFirstChild("MoneyConfig")
	end
	if not cfg then
		cfg = model:FindFirstChild("MoneyConfig", true)
	end
	if cfg then
		local ok, tab = pcall(require, cfg)
		if ok and type(tab) == "table" then
			local v = tonumber(tab.DollarsPerSecond)
			if v then return v end
		end
	end
	return nil  -- signals "no config present"
end

-- Returns an effective DPS value for weighting; uses RANDOM_DPS_MIN/MAX midpoint for unknown configs.
local function effectiveDPSForWeight(model)
	return readDPSFromTemplate(model) or ((RANDOM_DPS_MIN + RANDOM_DPS_MAX) / 2)
end

local function getRandomBrainrot()
	local models = BRAINROT_FOLDER:GetChildren()
	if #models == 0 then
		warn("[BrainrotSpawner] No brainrot models found in ReplicatedStorage.Brainrots!")
		return nil
	end

	-- When a luck boost is active, use the elevated rarity power so that
	-- high-DPS (rare) brainrots get a proportionally larger weight share.
	local luckPower = getActiveLuckPower()
	local activePower = luckPower or RARITY_POWER
	if luckPower then
		print(string.format("[BrainrotSpawner] 🍀 Luck boost active — using RARITY_POWER=%.1f", activePower))
	end

	-- Build weights: inversely proportional to (DPS + base)^power
	-- Templates with no MoneyConfig use the midpoint of RANDOM_DPS_MIN/MAX for stable weighting.
	local weights = {}
	local total = 0
	for i, m in ipairs(models) do
		local dps = effectiveDPSForWeight(m)
		local weight = 1 / ((dps + RARITY_BASE) ^ activePower)
		weights[i] = weight
		total = total + weight
	end

	-- If total is 0 for some reason (shouldn't happen), fall back to uniform random
	if total <= 0 then
		return models[math.random(1, #models)]
	end

	local pick = math.random() * total
	local acc = 0
	for i, m in ipairs(models) do
		acc = acc + weights[i]
		if pick <= acc then
			return m
		end
	end

	-- Fallback
	return models[#models]
end

local function isBrainrotPresent(spawnerPart)
	-- Check the attribute we set when a brainrot is spawned here
	return spawnerPart:GetAttribute(TAG_ATTRIBUTE) == true
end

local function spawnBrainrot(spawnerPart)
	local template = getRandomBrainrot()
	if not template then return end

	local newBrainrot = template:Clone()

	-- If this brainrot has no MoneyConfig, inject one with a random $/s
	if readDPSFromTemplate(newBrainrot) == nil then
		local randomDPS = math.random(RANDOM_DPS_MIN, RANDOM_DPS_MAX)
		-- Find the ProximityPrompt to parent the config to (same place proximityprompt.lua looks)
		local prompt = newBrainrot:FindFirstChildWhichIsA("ProximityPrompt", true)
		local configParent = prompt or newBrainrot
		local cfg = Instance.new("ModuleScript")
		cfg.Name = "MoneyConfig"
		cfg.Source = string.format("return { DollarsPerSecond = %d }", randomDPS)
		cfg.Parent = configParent
	end
	local wanderScript = game.ReplicatedStorage.Scripts:WaitForChild("BrainrotWander"):Clone()
	wanderScript.Parent = newBrainrot

	-- Position it at the spawner's CFrame
	if newBrainrot.PrimaryPart then
		newBrainrot:PivotTo(spawnerPart.CFrame)
	else
		-- Fallback: move every part
		for _, part in ipairs(newBrainrot:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CFrame = spawnerPart.CFrame
				break
			end
		end
	end

	newBrainrot.Parent = workspace

	-- Anchor all parts immediately so the brainrot cannot fall through the
	-- world before the first Heartbeat. BrainrotWander moves via PivotTo
	-- (CFrame-based), so parts must stay anchored the whole time they are
	-- wandering — exactly the same setup proximityprompt uses in slots.
	for _, part in ipairs(newBrainrot:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored   = true
			part.CanCollide = true
			part.Massless   = false
		end
	end

	-- Mark the spawner as occupied
	spawnerPart:SetAttribute(TAG_ATTRIBUTE, true)

	-- Watch for the brainrot being removed/picked up so we can clear the flag
	-- We do this by watching for the model leaving workspace
	newBrainrot.AncestryChanged:Connect(function(_, newParent)
		-- If it moved out of workspace (picked up by a player or destroyed)
		if newParent ~= workspace then
			spawnerPart:SetAttribute(TAG_ATTRIBUTE, false)
		end
	end)

	hideBillboard(spawnerPart)
	print(string.format("[BrainrotSpawner] Spawned '%s' at spawner '%s'", newBrainrot.Name, spawnerPart:GetFullName()))
end

----------------------------------------------------------------------
-- PER-SPAWNER STATE
-- { spawnerPart = { timer = number } }
----------------------------------------------------------------------
local spawners = {}

local function registerSpawner(part)
	if spawners[part] then return end  -- already registered
	spawners[part] = { timer = SPAWN_INTERVAL }
	part:SetAttribute(TAG_ATTRIBUTE, false)
	print(string.format("[BrainrotSpawner] Registered spawner: %s", part:GetFullName()))
end

-- Find all existing Spawner parts
local function scanWorkspace()
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") and obj.Name == SPAWNER_NAME then
			registerSpawner(obj)
			-- Spawn immediately at server start so players don't wait the full interval
			if not isBrainrotPresent(obj) then
				pcall(function() spawnBrainrot(obj) end)
			end
		end
	end
end

-- Also watch for Spawner parts added at runtime
workspace.DescendantAdded:Connect(function(obj)
	if obj:IsA("BasePart") and obj.Name == SPAWNER_NAME then
		registerSpawner(obj)
		-- If a spawner is added at runtime and it's empty, spawn immediately
		if not isBrainrotPresent(obj) then
			pcall(function() spawnBrainrot(obj) end)
		end
	end
end)

-- Clean up if a spawner is removed
workspace.DescendantRemoving:Connect(function(obj)
	if spawners[obj] then
		spawners[obj] = nil
	end
end)

scanWorkspace()

-- Debug: print computed DPS and spawn weight for each template
local SHOW_RARITY_LOG = true
if SHOW_RARITY_LOG then
	local models = BRAINROT_FOLDER:GetChildren()
	if #models > 0 then
		print("[BrainrotSpawner] Rarity table (template -> DPS -> weight):")
		-- Recompute weights using effectiveDPSForWeight (same as getRandomBrainrot)
		local weights = {}
		local total = 0
		for i, m in ipairs(models) do
			local dps = effectiveDPSForWeight(m)
			local weight = 1 / ((dps + RARITY_BASE) ^ RARITY_POWER)
			weights[i] = weight
			total = total + weight
		end
		for i, m in ipairs(models) do
			local configDPS = readDPSFromTemplate(m)
			local w = weights[i]
			local pct = total > 0 and (w / total * 100) or 0
			local dpsLabel = configDPS
				and string.format("$%g/s", configDPS)
				or string.format("$%d-%d/s (random, no config)", RANDOM_DPS_MIN, RANDOM_DPS_MAX)
			print(string.format("  %-30s  %-32s  weight=%.6f  chance=%.2f%%", m.Name, dpsLabel, w, pct))
		end
	end
end

----------------------------------------------------------------------
-- MAIN LOOP
----------------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt)
	for spawnerPart, state in pairs(spawners) do
		-- If a brainrot is already here, reset the timer and hide UI
		if isBrainrotPresent(spawnerPart) then
			state.timer = SPAWN_INTERVAL
			hideBillboard(spawnerPart)
			continue
		end

		state.timer -= dt

		if state.timer <= 0 then
			-- Time to spawn
			state.timer = SPAWN_INTERVAL
			spawnBrainrot(spawnerPart)
		else
			-- Show countdown
			showCountdown(spawnerPart, state.timer)
		end
	end
end)

print("[BrainrotSpawner] Ready. Watching for Spawner parts in workspace.")