-- HighSpawnScript (Script, ServerScriptService)
--
-- Every 10 minutes, spawns ultra/secret-rarity brainrots at every part
-- named "HighSpawner" in the workspace.
--
-- Setup:
--   • Place BaseParts named "HighSpawner" wherever you want rare spawns.
--   • Place a Model named "Volcano" in the workspace (with a PrimaryPart set).
--     A large countdown billboard will be attached above it automatically.
--   • In each brainrot template's MoneyConfig, add a `rarity` field:
--       return { DollarsPerSecond = 50, rarity = "ultra" }
--       return { DollarsPerSecond = 120, rarity = "secret" }
--   • Rarity values are case-insensitive ("Ultra", "ULTRA", "ultra" all match).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

----------------------------------------------------------------------
-- CONFIGURATION
----------------------------------------------------------------------
local SPAWN_INTERVAL   = 600          -- 10 minutes in seconds
local HIGH_RARITIES    = { ultra = true, secret = true }  -- accepted rarity values (lowercase)
local SPAWNER_NAME     = "HighSpawner"
local VOLCANO_NAME     = "MainIsland"
local TAG_ATTRIBUTE    = "HighSpawnerOccupied"

local BRAINROT_FOLDER  = ReplicatedStorage:WaitForChild("Brainrots")

----------------------------------------------------------------------
-- VOLCANO BILLBOARD
-- A large dramatic display above the Volcano model's PrimaryPart.
-- Shows MM:SS countdown; pulses red when spawning.
----------------------------------------------------------------------
local volcanoModel     = workspace:WaitForChild(VOLCANO_NAME)
local billboardGui     = nil
local countdownLabel   = nil
local subtitleLabel    = nil
local bgFrame          = nil

local function buildVolcanoBillboard(adornPart)
	-- Remove any old one
	local old = adornPart:FindFirstChild("HighSpawnBillboard")
	if old then old:Destroy() end

	local bg = Instance.new("BillboardGui")
	bg.Name           = "HighSpawnBillboard"
	bg.Adornee        = adornPart
	bg.Size           = UDim2.new(0, 300, 0, 120)
	bg.StudsOffset    = Vector3.new(0, 65, 0)
	bg.AlwaysOnTop    = false
	bg.MaxDistance    = 500
	bg.ResetOnSpawn   = false
	bg.LightInfluence = 0
	bg.Parent         = adornPart
	billboardGui      = bg

	-- Outer frame
	local frame = Instance.new("Frame", bg)
	frame.Size                   = UDim2.fromScale(1, 1)
	frame.BackgroundColor3       = Color3.fromRGB(10, 5, 20)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel        = 0
	bgFrame = frame

	local corner = Instance.new("UICorner", frame)
	corner.CornerRadius = UDim.new(0, 14)

	local stroke = Instance.new("UIStroke", frame)
	stroke.Color       = Color3.fromRGB(180, 60, 255)
	stroke.Thickness   = 2.5
	stroke.Transparency = 0.2

	-- Title row
	local titleLabel = Instance.new("TextLabel", frame)
	titleLabel.Name                   = "TitleLabel"
	titleLabel.Size                   = UDim2.new(1, -16, 0, 30)
	titleLabel.Position               = UDim2.new(0, 8, 0, 6)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text                   = "🌋 RARE SPAWN"
	titleLabel.TextColor3             = Color3.fromRGB(220, 100, 255)
	titleLabel.Font                   = Enum.Font.GothamBlack
	titleLabel.TextScaled             = true

	-- Countdown row
	local cdLabel = Instance.new("TextLabel", frame)
	cdLabel.Name                   = "CountdownLabel"
	cdLabel.Size                   = UDim2.new(1, -16, 0, 50)
	cdLabel.Position               = UDim2.new(0, 8, 0, 36)
	cdLabel.BackgroundTransparency = 1
	cdLabel.Text                   = "10:00"
	cdLabel.TextColor3             = Color3.fromRGB(255, 220, 60)
	cdLabel.Font                   = Enum.Font.GothamBlack
	cdLabel.TextScaled             = true
	countdownLabel = cdLabel

	-- Subtitle / status row
	local subLabel = Instance.new("TextLabel", frame)
	subLabel.Name                   = "SubtitleLabel"
	subLabel.Size                   = UDim2.new(1, -16, 0, 22)
	subLabel.Position               = UDim2.new(0, 8, 0, 90)
	subLabel.BackgroundTransparency = 1
	subLabel.Text                   = "Next ultra/secret spawn..."
	subLabel.TextColor3             = Color3.fromRGB(160, 120, 220)
	subLabel.Font                   = Enum.Font.GothamBold
	subLabel.TextScaled             = true
	subtitleLabel = subLabel

	return bg
end

local function initVolcanoBillboard()
	if not volcanoModel then
		-- Keep looking — the map might still be loading
		workspace.DescendantAdded:Connect(function(obj)
			if obj:IsA("Model") and obj.Name == VOLCANO_NAME and not volcanoModel then
				volcanoModel = obj
				local adorn = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
				if adorn then
					buildVolcanoBillboard(adorn)
				else
					obj.ChildAdded:Connect(function(child)
						if child:IsA("BasePart") and not billboardGui then
							buildVolcanoBillboard(child)
						end
					end)
				end
			end
		end)
		return
	end

	local adorn = volcanoModel.PrimaryPart or volcanoModel:FindFirstChildWhichIsA("BasePart")
	if adorn then
		buildVolcanoBillboard(adorn)
	end
end

initVolcanoBillboard()

----------------------------------------------------------------------
-- BILLBOARD UPDATE HELPERS
----------------------------------------------------------------------
local function setCountdownText(seconds)
	if not countdownLabel then return end
	local mins = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)
	countdownLabel.Text = string.format("%d:%02d", mins, secs)

	-- Colour shifts: white > 2min, gold 2min-30s, orange 30s-0
	if seconds > 120 then
		countdownLabel.TextColor3 = Color3.fromRGB(255, 220, 60)
	elseif seconds > 30 then
		countdownLabel.TextColor3 = Color3.fromRGB(255, 150, 40)
	else
		countdownLabel.TextColor3 = Color3.fromRGB(255, 60, 60)
	end
end

local function playSpawnEffect()
	if not billboardGui then return end

	-- Flash the background red/purple rapidly
	task.spawn(function()
		local flashColors = {
			Color3.fromRGB(180, 30, 30),
			Color3.fromRGB(120, 20, 180),
			Color3.fromRGB(255, 60, 60),
			Color3.fromRGB(160, 40, 220),
		}
		for rep = 1, 6 do
			if bgFrame then
				bgFrame.BackgroundColor3 = flashColors[(rep % #flashColors) + 1]
			end
			task.wait(0.18)
		end
		if bgFrame then
			bgFrame.BackgroundColor3 = Color3.fromRGB(10, 5, 20)
		end
	end)

	-- Big "SPAWNING!" text for 3 seconds
	if countdownLabel then
		countdownLabel.Text      = "SPAWNING!"
		countdownLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
	end
	if subtitleLabel then
		subtitleLabel.Text      = "🌋 Ultra & Secret Brainrots!"
		subtitleLabel.TextColor3 = Color3.fromRGB(255, 180, 60)
	end
	task.wait(3)
	if subtitleLabel then
		subtitleLabel.Text      = "Next ultra/secret spawn..."
		subtitleLabel.TextColor3 = Color3.fromRGB(160, 120, 220)
	end
end

----------------------------------------------------------------------
-- RARITY FILTERING
----------------------------------------------------------------------
local function getRarityFromTemplate(model)
	local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
	local cfg    = prompt and prompt:FindFirstChild("MoneyConfig")
	if not cfg then cfg = model:FindFirstChild("MoneyConfig", true) end
	if not cfg then return nil end

	local ok, tab = pcall(require, cfg)
	if not ok or type(tab) ~= "table" then return nil end

	local r = tab.rarity
	return r and tostring(r):lower() or nil
end

local function getHighRarityTemplates()
	local results = {}
	for _, template in ipairs(BRAINROT_FOLDER:GetChildren()) do
		local rarity = getRarityFromTemplate(template)
		if rarity and HIGH_RARITIES[rarity] then
			table.insert(results, template)
		end
	end
	return results
end

----------------------------------------------------------------------
-- SPAWN HELPERS  (mirrored from SpawnScript / AdminServer)
----------------------------------------------------------------------
local RANDOM_DPS_MIN = 5
local RANDOM_DPS_MAX = 35

local function readDPSFromTemplate(model)
	local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
	local cfg    = prompt and prompt:FindFirstChild("MoneyConfig")
	if not cfg then cfg = model:FindFirstChild("MoneyConfig", true) end
	if cfg then
		local ok, tab = pcall(require, cfg)
		if ok and type(tab) == "table" then
			local v = tonumber(tab.DollarsPerSecond)
			if v then return v end
		end
	end
	return nil
end

local function anchorModel(model)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored   = true
			p.CanCollide = true
			p.Massless   = false
		end
	end
end

local function spawnTemplateAt(template, spawnerPart)
	local clone = template:Clone()

	-- Ground-snap: cast downward from above the spawner
	local rcParams = RaycastParams.new()
	rcParams.FilterDescendantsInstances = { clone }
	rcParams.FilterType = Enum.RaycastFilterType.Exclude
	rcParams.IgnoreWater = false
	local origin   = spawnerPart.Position + Vector3.new(0, 50, 0)
	local hit      = workspace:Raycast(origin, Vector3.new(0, -100, 0), rcParams)
	local spawnY   = hit and (hit.Position.Y + 2) or spawnerPart.Position.Y
	local spawnCF  = CFrame.new(spawnerPart.Position.X, spawnY, spawnerPart.Position.Z)

	if clone.PrimaryPart then
		clone:PivotTo(spawnCF)
	else
		-- Fallback: move every BasePart
		for _, p in ipairs(clone:GetDescendants()) do
			if p:IsA("BasePart") then p.CFrame = spawnCF; break end
		end
	end

	clone.Parent = workspace
	anchorModel(clone)

	-- Read the existing MoneyConfig from the clone (it was cloned from the template)
	local existingPrompt = clone:FindFirstChildWhichIsA("ProximityPrompt", true)
	local existingCfg    = existingPrompt and existingPrompt:FindFirstChild("MoneyConfig")
	if not existingCfg then existingCfg = clone:FindFirstChild("MoneyConfig", true) end

	local cloneDPS, cloneCost, cloneRarity = nil, nil, "ultra"
	if existingCfg then
		local ok, tab = pcall(require, existingCfg)
		if ok and type(tab) == "table" then
			cloneDPS    = tonumber(tab.DollarsPerSecond)
			cloneCost   = tonumber(tab.Cost)
			cloneRarity = tab.rarity and tostring(tab.rarity):lower() or "ultra"
		end
	end

	-- Inject a MoneyConfig only if the clone somehow has none
	if cloneDPS == nil then
		local randomDPS  = math.random(RANDOM_DPS_MIN, RANDOM_DPS_MAX)
		local randomCost = randomDPS * 20   -- sensible default cost for a rare brainrot
		local prompt     = existingPrompt or clone:FindFirstChildWhichIsA("ProximityPrompt", true)
		local cfg        = Instance.new("ModuleScript")
		cfg.Name         = "MoneyConfig"
		cfg.Source       = string.format(
			"return { DollarsPerSecond = %d, Cost = %d, rarity = %q }",
			randomDPS, randomCost, "ultra"
		)
		cfg.Parent = prompt or clone
	end

	-- Attach wander script
	local scripts   = ReplicatedStorage:FindFirstChild("Scripts")
	local wanderSrc = scripts and scripts:FindFirstChild("BrainrotWander")
	if wanderSrc then wanderSrc:Clone().Parent = clone end

	-- DO NOT set HasBeenPurchased = true here.
	-- The first player to pick this up must pay the Cost from MoneyConfig,
	-- exactly like normal world spawns. After that, anyone can steal it free.
	-- Remove any pre-existing tag that might have been baked into the template.
	local existingTag = clone:FindFirstChild("HasBeenPurchased")
	if existingTag then existingTag:Destroy() end

	-- Mark spawner occupied; clear when brainrot leaves workspace
	spawnerPart:SetAttribute(TAG_ATTRIBUTE, true)
	clone.AncestryChanged:Connect(function(_, newParent)
		if newParent ~= workspace then
			spawnerPart:SetAttribute(TAG_ATTRIBUTE, false)
		end
	end)

	return clone
end

----------------------------------------------------------------------
-- HIGH SPAWNER REGISTRY
----------------------------------------------------------------------
local highSpawners = {}  -- { [BasePart] = true }

local function registerHighSpawner(part)
	if highSpawners[part] then return end
	highSpawners[part] = true
	part:SetAttribute(TAG_ATTRIBUTE, false)
	print(string.format("[HighSpawnScript] Registered HighSpawner: %s", part:GetFullName()))
end

-- Scan existing workspace
for _, obj in ipairs(workspace:GetDescendants()) do
	if obj:IsA("BasePart") and obj.Name == SPAWNER_NAME then
		registerHighSpawner(obj)
	end
end

-- Watch for runtime additions
workspace.DescendantAdded:Connect(function(obj)
	if obj:IsA("BasePart") and obj.Name == SPAWNER_NAME then
		registerHighSpawner(obj)
	end
end)

workspace.DescendantRemoving:Connect(function(obj)
	highSpawners[obj] = nil
end)

----------------------------------------------------------------------
-- SPAWN WAVE
----------------------------------------------------------------------
local function runSpawnWave()
	local templates = getHighRarityTemplates()

	if #templates == 0 then
		warn("[HighSpawnScript] No ultra/secret brainrots found in ReplicatedStorage.Brainrots!")
		warn("  → Make sure MoneyConfig modules include:  rarity = \"ultra\"  or  rarity = \"secret\"")
		return
	end

	local spawnerList = {}
	for part in pairs(highSpawners) do
		table.insert(spawnerList, part)
	end

	if #spawnerList == 0 then
		warn("[HighSpawnScript] No HighSpawner parts found in workspace!")
		return
	end

	-- Play the volcano effect first
	playSpawnEffect()

	-- Give the flash animation a moment before actually spawning
	task.wait(1)

	local spawned = 0
	for _, spawnerPart in ipairs(spawnerList) do
		-- Skip if already occupied
		if spawnerPart:GetAttribute(TAG_ATTRIBUTE) then continue end

		-- Pick a random high-rarity template
		local template = templates[math.random(1, #templates)]
		local ok, err = pcall(spawnTemplateAt, template, spawnerPart)
		if ok then
			spawned += 1
			print(string.format(
				"[HighSpawnScript] Spawned '%s' (rarity: %s) at %s",
				template.Name, getRarityFromTemplate(template) or "?", spawnerPart:GetFullName()
				))
		else
			warn("[HighSpawnScript] Failed to spawn at", spawnerPart:GetFullName(), "–", err)
		end
	end

	print(string.format("[HighSpawnScript] Wave complete: %d brainrot(s) spawned.", spawned))
end

----------------------------------------------------------------------
-- MAIN COUNTDOWN LOOP
----------------------------------------------------------------------
local timer = SPAWN_INTERVAL   -- start counting immediately

-- BindableEvent in ServerStorage: other scripts (AdminServer) can fire
-- this to trigger an immediate wave and reset the countdown.
local triggerEvent = Instance.new("BindableEvent")
triggerEvent.Name   = "TriggerHighSpawn"
triggerEvent.Parent = game:GetService("ServerStorage")

triggerEvent.Event:Connect(function()
	timer = 0   -- set to 0 so the Heartbeat fires the wave on the next tick
	print("[HighSpawnScript] Admin-triggered rare spawn!")
end)

RunService.Heartbeat:Connect(function(dt)
	timer = timer - dt

	if timer <= 0 then
		timer = SPAWN_INTERVAL
		task.spawn(runSpawnWave)  -- run in a separate thread so Heartbeat isn't blocked
		return
	end

	setCountdownText(timer)
end)

----------------------------------------------------------------------
-- STARTUP LOG
----------------------------------------------------------------------
local function logRarityTable()
	local models = BRAINROT_FOLDER:GetChildren()
	local ultraCount, secretCount = 0, 0
	for _, m in ipairs(models) do
		local r = getRarityFromTemplate(m)
		if r == "ultra"  then ultraCount  += 1 end
		if r == "secret" then secretCount += 1 end
	end
	print(string.format(
		"[HighSpawnScript] Ready. %d ultra + %d secret templates eligible. %d HighSpawner(s) found.",
		ultraCount, secretCount, (function() local n=0; for _ in pairs(highSpawners) do n+=1 end; return n end)()
		))
end

task.spawn(logRarityTable)
print("[HighSpawnScript] 10-minute rare spawn timer started.")
