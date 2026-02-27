-- BrainrotSaveServer (Script, ServerScriptService)
--
-- Saves which brainrots a player has deposited and which slot they were in,
-- then re-spawns them when the player rejoins – even if they land on a
-- different PlayerIsland than last time.
--
-- Slot identity is stored as a "slot index" derived from the sorted order of
-- each Slot's distance from the centre of BrainrotSlots. Because every island
-- should have identically-laid-out BrainrotSlots, slot index 1 on island A
-- maps to the same logical position as slot index 1 on island B.
--
-- Brainrot templates are sourced from ReplicatedStorage.Brainrots,
-- the same folder used by SpawnScript.lua.
--
-- DataStore schema (per player key = tostring(userId)):
--   {
--     slots = {
--       [slotIndex: number] = brainrotName: string,
--       ...
--     }
--   }
--
-- Dependencies created at runtime (if missing):
--   ServerStorage > BrainrotSlotChanged  (BindableEvent)  – also used by proximityprompt.lua
--   ServerStorage > MoneyBridge          (BindableFunction) – already created by MoneyServer

local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local ServerStorage     = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------------
local DATASTORE_KEY_PREFIX = "BrainrotSlots_v1_"  -- versioned to allow wipes
local ISLAND_MODEL_NAME    = "PlayerIsland"
local SLOTS_MODEL_NAME     = "BrainrotSlots"
local SLOT_MODEL_NAME      = "Slot"
local SPAWN_PART_NAME      = "Spawn"
local SLOT_SCALE           = 0.5                   -- must match proximityprompt.lua
local RESTORE_DELAY        = 3                     -- seconds after PlayerAdded before restoring
                                                   -- (gives the island time to load / assign)
local FIND_ISLAND_TIMEOUT  = 15                    -- seconds to wait for the island to appear

----------------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------------
local BrainrotStore = DataStoreService:GetDataStore(DATASTORE_KEY_PREFIX .. "main")

----------------------------------------------------------------------
-- BINDABLE SETUP
-- Create BrainrotSlotChanged if it doesn't exist yet.
-- proximityprompt.lua also waits for it; whichever script runs first creates it.
----------------------------------------------------------------------
local function getOrCreate(parent, class, name)
	local existing = parent:FindFirstChild(name)
	if existing then return existing end
	local obj = Instance.new(class)
	obj.Name   = name
	obj.Parent = parent
	return obj
end

local slotChanged  = getOrCreate(ServerStorage, "BindableEvent",  "BrainrotSlotChanged")
local islandBridge = getOrCreate(ServerStorage, "BindableFunction", "IslandBridge")
local moneyBridge  = ServerStorage:WaitForChild("MoneyBridge", 30)  -- created by MoneyServer

----------------------------------------------------------------------
-- ISLAND ASSIGNMENT MAP
-- playerIslandMap[userId] = PlayerIsland model
-- Set as soon as we resolve the player's island; read by IslandBridge.
----------------------------------------------------------------------
local playerIslandMap = {}

-- claimedIslands: tracks which islands are already assigned to a player.
-- Used to prevent two simultaneous joiners from grabbing the same island.
-- { [islandModel] = userId }
local claimedIslands = {}

-- assignmentLock: a simple boolean per-coroutine mutex.
-- Only one coroutine at a time runs the "find + claim" step.
local assignmentLock = false

-- IslandBridge.OnInvoke: returns the assigned island for a userId, or nil
islandBridge.OnInvoke = function(userId)
	return playerIslandMap[userId]
end

----------------------------------------------------------------------
-- BRAINROT TEMPLATES
-- Same folder that SpawnScript.lua uses: ReplicatedStorage > Brainrots
----------------------------------------------------------------------
local templatesFolder = ReplicatedStorage:WaitForChild("Brainrots", 30)
if not templatesFolder then
	warn("[BrainrotSaveServer] ReplicatedStorage.Brainrots not found. Saved brainrots cannot be restored.")
end

----------------------------------------------------------------------
-- SLOT INDEX HELPERS
--
-- "Slot index" = 1-based position of a Slot in a list sorted by each
-- Slot's distance from the centre of its BrainrotSlots model.
-- This is stable: same logical slot = same index on every island.
----------------------------------------------------------------------

--- Returns the world-space centre of a BrainrotSlots model.
local function getBrainrotSlotsCenter(brainrotSlotsModel)
	local primary = brainrotSlotsModel.PrimaryPart
	if primary then
		return primary.Position
	end
	-- Fallback: average of all BaseParts
	local sum   = Vector3.new(0, 0, 0)
	local count = 0
	for _, d in ipairs(brainrotSlotsModel:GetDescendants()) do
		if d:IsA("BasePart") then
			sum   = sum + d.Position
			count = count + 1
		end
	end
	if count > 0 then
		return sum / count
	end
	return brainrotSlotsModel:GetPivot().Position
end

--- Returns a sorted list of Slot models ordered by distance from center.
local function getSortedSlots(brainrotSlotsModel)
	local center = getBrainrotSlotsCenter(brainrotSlotsModel)
	local slots  = {}

	for _, child in ipairs(brainrotSlotsModel:GetChildren()) do
		if child:IsA("Model") and child.Name == SLOT_MODEL_NAME then
			local pivot = child:GetPivot().Position
			-- Use X and Z only so vertical variation doesn't skew ordering
			local dx    = pivot.X - center.X
			local dz    = pivot.Z - center.Z
			local dist  = math.sqrt(dx*dx + dz*dz)
			table.insert(slots, { model = child, dist = dist, pivot = pivot })
		end
	end

	-- Primary sort: distance ascending; secondary: angle (atan2) for ties
	table.sort(slots, function(a, b)
		if math.abs(a.dist - b.dist) > 0.01 then
			return a.dist < b.dist
		end
		local acx = a.pivot.X - getBrainrotSlotsCenter(brainrotSlotsModel).X
		local acz = a.pivot.Z - getBrainrotSlotsCenter(brainrotSlotsModel).Z
		local bcx = b.pivot.X - getBrainrotSlotsCenter(brainrotSlotsModel).X
		local bcz = b.pivot.Z - getBrainrotSlotsCenter(brainrotSlotsModel).Z
		return math.atan2(acz, acx) < math.atan2(bcz, bcx)
	end)

	return slots
end

--- Given a specific Slot model inside a BrainrotSlots model, return its index.
local function getSlotIndex(slotModel)
	local brainrotSlotsModel = slotModel.Parent
	if not brainrotSlotsModel or brainrotSlotsModel.Name ~= SLOTS_MODEL_NAME then
		return nil
	end
	local sorted = getSortedSlots(brainrotSlotsModel)
	for i, entry in ipairs(sorted) do
		if entry.model == slotModel then
			return i
		end
	end
	return nil
end

--- Given a BrainrotSlots model and a slot index, return the Slot model.
local function getSlotByIndex(brainrotSlotsModel, index)
	local sorted = getSortedSlots(brainrotSlotsModel)
	local entry  = sorted[index]
	return entry and entry.model or nil
end

----------------------------------------------------------------------
-- ISLAND FINDER
--
-- Finds the closest unclaimed PlayerIsland to the player's character.
-- Falls back to any unclaimed island if character position is unavailable.
-- Already-claimed islands (assigned to another online player) are skipped.
----------------------------------------------------------------------
local function findClosestIsland(player)
	local character  = player.Character
	local playerPos  = nil

	if character then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then playerPos = root.Position end
	end

	local bestIsland = nil
	local bestDist   = math.huge

	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("Model") and obj.Name == ISLAND_MODEL_NAME then
			local slotsModel = obj:FindFirstChild(SLOTS_MODEL_NAME, true)
			if slotsModel then
				-- Skip islands already assigned to another online player
				if claimedIslands[obj] and claimedIslands[obj] ~= player.UserId then
					continue
				end
				if playerPos then
					local center = getBrainrotSlotsCenter(slotsModel)
					local d      = (center - playerPos).Magnitude
					if d < bestDist then
						bestDist   = d
						bestIsland = obj
					end
				else
					-- No position available, pick first unclaimed found
					return obj
				end
			end
		end
	end

	return bestIsland
end

----------------------------------------------------------------------
-- DATASTORE HELPERS
----------------------------------------------------------------------
local function loadData(userId)
	local ok, result = pcall(function()
		return BrainrotStore:GetAsync(tostring(userId))
	end)
	if ok and type(result) == "table" then
		return result
	end
	return { slots = {} }
end

local function saveData(userId, data)
	local ok, err = pcall(function()
		BrainrotStore:SetAsync(tostring(userId), data)
	end)
	if not ok then
		warn("[BrainrotSaveServer] Failed to save for", userId, err)
	end
end

----------------------------------------------------------------------
-- IN-MEMORY STATE
-- Tracks each player's current slot assignments so we can build the
-- save payload on PlayerRemoving without querying the world.
----------------------------------------------------------------------
-- playerSlots[userId] = { [slotIndex] = brainrotName }
local playerSlots = {}

local function ensurePlayerData(userId)
	if not playerSlots[userId] then
		playerSlots[userId] = {}
	end
end

----------------------------------------------------------------------
-- BRAINROT RESTORE
-- Clones a template brainrot and places it into the specified slot.
----------------------------------------------------------------------
local function restoreBrainrot(userId, slotIndex, brainrotName, brainrotSlotsModel)
	if not templatesFolder then
		warn("[BrainrotSaveServer] Cannot restore – templates folder missing.")
		return
	end

	local template = templatesFolder:FindFirstChild(brainrotName)
	if not template then
		warn("[BrainrotSaveServer] Template not found for brainrot:", brainrotName)
		return
	end

	local slotModel = getSlotByIndex(brainrotSlotsModel, slotIndex)
	if not slotModel then
		warn("[BrainrotSaveServer] Slot index", slotIndex, "not found in", brainrotSlotsModel:GetFullName())
		return
	end

	local spawnPart = slotModel:FindFirstChild(SPAWN_PART_NAME)
	if not spawnPart then
		warn("[BrainrotSaveServer] Slot", slotModel:GetFullName(), "has no Spawn part.")
		return
	end

	-- Check if the slot is already occupied by a live brainrot
	if spawnPart:FindFirstChildWhichIsA("Model") then
		warn("[BrainrotSaveServer] Slot", slotIndex, "already occupied; skipping restore of", brainrotName)
		return
	end

	local clone = template:Clone()
	clone:PivotTo(spawnPart.CFrame)
	clone:ScaleTo(SLOT_SCALE)
	clone.Parent = spawnPart

	-- Anchor all parts so the brainrot sits still in the slot
	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored   = true
			part.CanCollide = true
			part.Massless   = false
		end
	end

	-- Mark as already purchased — this brainrot was previously owned and
	-- deposited by the player, so it should be free to steal immediately.
	-- proximityprompt.lua creates this tag too, but it won't exist on a
	-- fresh clone from the template.
	local purchasedTag = clone:FindFirstChild("HasBeenPurchased")
	if not purchasedTag then
		purchasedTag       = Instance.new("BoolValue")
		purchasedTag.Name  = "HasBeenPurchased"
		purchasedTag.Parent = clone
	end
	purchasedTag.Value = true

	-- Re-register with MoneyServer so money starts accumulating immediately
	if moneyBridge then
		-- Read DPS from the cloned model's ProximityPrompt > MoneyConfig
		local dps = 0
		local prompt = clone:FindFirstChildWhichIsA("ProximityPrompt", true)
		if prompt then
			local cfg = prompt:FindFirstChild("MoneyConfig")
			if cfg then
				local ok, cfgData = pcall(require, cfg)
				if ok and type(cfgData) == "table" then
					dps = cfgData.DollarsPerSecond or 0
				end
			end
		end
		moneyBridge:Invoke("deposit", userId, clone, dps)
	end

	-- Record in memory
	ensurePlayerData(userId)
	playerSlots[userId][slotIndex] = brainrotName

	print(string.format("[BrainrotSaveServer] Restored '%s' into slot %d for player %d",
		brainrotName, slotIndex, userId))
end

----------------------------------------------------------------------
-- RESTORE ALL BRAINROTS FOR A PLAYER
----------------------------------------------------------------------
local function restorePlayerBrainrots(player)
	local userId = player.UserId
	local data   = loadData(userId)

	-- Wait a moment for the world to set up the player's island
	task.wait(RESTORE_DELAY)

	-- Player may have left during the wait
	if not Players:GetPlayerByUserId(userId) then return end

	-- Find the closest island and record it immediately in the map
	-- so spawnpointremover.lua can use it the moment CharacterAdded fires.
	--
	-- MUTEX: only one coroutine at a time runs the find+claim step so that
	-- two players joining simultaneously can't both pick the same island
	-- before either has registered their claim in claimedIslands.
	while assignmentLock do
		task.wait(0.05)
		if not Players:GetPlayerByUserId(userId) then return end
	end
	assignmentLock = true

	local island = findClosestIsland(player)
	if not island then
		-- Keep waiting up to FIND_ISLAND_TIMEOUT
		local elapsed = 0
		local step    = 1
		while elapsed < FIND_ISLAND_TIMEOUT do
			task.wait(step)
			elapsed = elapsed + step
			if not Players:GetPlayerByUserId(userId) then
				assignmentLock = false
				return
			end
			island = findClosestIsland(player)
			if island then break end
		end
	end

	if not island then
		assignmentLock = false
		warn("[BrainrotSaveServer] Could not find a PlayerIsland for", player.Name, "– brainrots not restored.")
		ensurePlayerData(userId)
		return
	end

	-- Claim the island before releasing the lock so the next coroutine
	-- sees it as taken when it calls findClosestIsland.
	claimedIslands[island]  = userId
	playerIslandMap[userId] = island
	assignmentLock          = false
	print(string.format("[BrainrotSaveServer] Assigned island '%s' to %s", island.Name, player.Name))

	if not data.slots or next(data.slots) == nil then
		ensurePlayerData(userId)
		return
	end

	local slotsModel = island:FindFirstChild(SLOTS_MODEL_NAME, true)
	if not slotsModel then
		warn("[BrainrotSaveServer] PlayerIsland has no BrainrotSlots model:", island:GetFullName())
		ensurePlayerData(userId)
		return
	end

	-- Initialise in-memory table before restoring
	ensurePlayerData(userId)

	for slotIndexStr, brainrotName in pairs(data.slots) do
		local slotIndex = tonumber(slotIndexStr)
		if slotIndex and brainrotName and brainrotName ~= "" then
			restoreBrainrot(userId, slotIndex, brainrotName, slotsModel)
		end
	end
end

----------------------------------------------------------------------
-- DEPOSIT / PICKUP LISTENER
-- Receives events from proximityprompt.lua via BrainrotSlotChanged.
--
-- deposit: (action, player, slotModel, brainrotModel)
-- pickup:  (action, nil,    nil,       brainrotModel)
----------------------------------------------------------------------
slotChanged.Event:Connect(function(action, player, slotModel, brainrotModel)
	if action == "deposit" then
		if not player or not slotModel or not brainrotModel then return end

		local userId    = player.UserId
		local slotIndex = getSlotIndex(slotModel)

		if not slotIndex then
			warn("[BrainrotSaveServer] Could not determine slot index for", slotModel:GetFullName())
			return
		end

		ensurePlayerData(userId)
		playerSlots[userId][slotIndex] = brainrotModel.Name

		print(string.format("[BrainrotSaveServer] Recorded slot %d = '%s' for player %d",
			slotIndex, brainrotModel.Name, userId))

	elseif action == "pickup" then
		if not brainrotModel then return end

		-- slotModel is non-nil only when the brainrot was actually sitting
		-- in a slot at the moment of pickup. If it was in the open world
		-- (not yet deposited, or already picked up) slotModel is nil and
		-- there is nothing to clear — this prevents false erasures when
		-- two brainrots share the same name.
		if player and slotModel then
			local userId    = player.UserId
			local slotIndex = getSlotIndex(slotModel)
			if slotIndex and playerSlots[userId] then
				playerSlots[userId][slotIndex] = nil
				print(string.format("[BrainrotSaveServer] Cleared slot %d for userId %d (pickup of '%s' from slot)",
					slotIndex, userId, brainrotModel.Name))
			end
		end
	end
end)

----------------------------------------------------------------------
-- ISLAND RESET
-- Called when a player leaves. Cleans up everything their island holds
-- so it is blank and ready for the next player who joins.
--
-- Cleaned up:
--   1. All brainrots sitting in slots  (deregistered from MoneyBridge too)
--   2. Any brainrots in the open world that are still registered to this
--      player (e.g. being carried by a thief or lying on the ground)
--   3. "Your Base" billboard  (added by spawnpointremover.lua)
--   4. Active shield model    (IslandShield, added by BaseLocker.lua)
--   5. Private SpawnLocation  (PlayerRespawn, added by spawnpointremover.lua)
----------------------------------------------------------------------
local BILLBOARD_NAME   = "YourBaseBillboard"
local SHIELD_NAME      = "IslandShield"
local SPAWNLOC_NAME    = "PlayerRespawn"

local function resetIsland(userId, island)
	-- ── 1 & 2. Remove all brainrots registered to this player ──────
	-- Ask MoneyBridge to deregister every model owned by this player and
	-- return the list so we can destroy the instances.
	if moneyBridge then
		local ok, removed = pcall(function()
			return moneyBridge:Invoke("clearPlayer", userId, nil, nil)
		end)
		if ok and type(removed) == "table" then
			for _, model in ipairs(removed) do
				if model and model.Parent then
					model:Destroy()
				end
			end
		end
	end

	-- Also sweep the island's BrainrotSlots for any brainrot that was
	-- restored by BrainrotSaveServer but never registered with MoneyBridge
	-- (e.g. the player left during the RESTORE_DELAY window).
	local slotsModel = island:FindFirstChild(SLOTS_MODEL_NAME, true)
	if slotsModel then
		for _, slot in ipairs(slotsModel:GetChildren()) do
			if slot:IsA("Model") and slot.Name == SLOT_MODEL_NAME then
				local spawnPart = slot:FindFirstChild(SPAWN_PART_NAME)
				if spawnPart then
					for _, child in ipairs(spawnPart:GetChildren()) do
						if child:IsA("Model") then
							child:Destroy()
						end
					end
				end
			end
		end
	end

	-- ── 3. Remove "Your Base" billboard ────────────────────────────
	local billboard = island:FindFirstChild(BILLBOARD_NAME, true)
	if billboard then billboard:Destroy() end

	-- ── 4. Destroy the active shield (if any) ──────────────────────
	-- BaseLocker parents IslandShield directly to workspace.
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj.Name == SHIELD_NAME and obj:IsA("Model") then
			-- Verify this shield belongs to this island by checking if
			-- its ShieldAnchor is within 10 studs of the island centre.
			local anchor = obj:FindFirstChild("ShieldAnchor")
			if anchor then
				local islandPivot = island:GetPivot().Position
				local flat = Vector3.new(anchor.Position.X, islandPivot.Y, anchor.Position.Z)
				if (flat - islandPivot).Magnitude < 80 then
					obj:Destroy()
				end
			end
		end
	end

	-- ── 5. Destroy the private SpawnLocation ───────────────────────
	-- spawnpointremover.lua creates one SpawnLocation named SPAWNLOC_NAME
	-- inside the island. Destroying it lets the next occupant get a fresh one.
	local spawnLoc = island:FindFirstChild(SPAWNLOC_NAME, true)
	if spawnLoc then spawnLoc:Destroy() end

	print(string.format("[BrainrotSaveServer] Island '%s' fully reset after %d left.",
		island.Name, userId))
end

----------------------------------------------------------------------
-- PLAYER LIFECYCLE
----------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	task.spawn(restorePlayerBrainrots, player)
end)

Players.PlayerRemoving:Connect(function(player)
	local userId = player.UserId
	local slots  = playerSlots[userId] or {}

	-- Build a clean table (remove any nil holes left by pickups)
	local saveSlots = {}
	local saveCount = 0
	for slotIndex, brainrotName in pairs(slots) do
		if brainrotName and brainrotName ~= "" then
			saveSlots[tostring(slotIndex)] = brainrotName
			saveCount = saveCount + 1
		end
	end

	saveData(userId, { slots = saveSlots })

	-- Reset the island so it is clean for the next player who joins
	local island = playerIslandMap[userId]
	if island then
		resetIsland(userId, island)
		claimedIslands[island] = nil
	end
	playerSlots[userId]     = nil
	playerIslandMap[userId] = nil

	print(string.format("[BrainrotSaveServer] Saved %d brainrot slot(s) for player %d",
		saveCount, userId))
end)

-- Handle players who were already in-game when this script loaded
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(restorePlayerBrainrots, player)
end

print("[BrainrotSaveServer] Ready.")
