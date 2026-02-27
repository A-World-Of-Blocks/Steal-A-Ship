-- MoneyServer (Script, ServerScriptService)
-- Handles:
--   • Persistent money saved via DataStore (survives player leaving)
--   • $/s billboard GUI above each brainrot's PrimaryPart
--   • Paying the last player who deposited a brainrot while it stays in a slot
--   • A BindableFunction "MoneyBridge" in ServerStorage so other ServerScripts
--     (the brainrot pickup scripts) can signal deposits/pickups/balance queries directly.

local Players            = game:GetService("Players")
local DataStoreService   = game:GetService("DataStoreService")
local RunService         = game:GetService("RunService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerStorage      = game:GetService("ServerStorage")

local MoneyStore    = DataStoreService:GetDataStore("BrainrotMoney_v1")
local OfflineStore  = DataStoreService:GetDataStore("BrainrotOffline_v1")
local PendingStore  = DataStoreService:GetDataStore("BrainrotPending_v1")
-- Stores { leaveTime = unixTimestamp, totalDps = number } per player

----------------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------------
local SAVE_INTERVAL           = 30   -- auto-save every N seconds
local SLOT_BILLBOARD_Y_OFFSET = 20   -- studs above the Spawn part (pending money billboard)
local WORLD_BILLBOARD_Y_OFFSET = 6   -- studs above the brainrot PrimaryPart ($/s label)
local OFFLINE_CAP             = 600  -- max offline seconds to credit (10 minutes)

-- ► SET THIS to your Auto-Collect gamepass ID.
-- Players who own it receive $/s directly into their balance instead of
-- accumulating pending money that must be manually collected.
local AUTO_COLLECT_GAMEPASS_ID = 1727487379   -- ← replace with your real gamepass ID

----------------------------------------------------------------------
-- In-memory ledger  { [userId] = dollars }
----------------------------------------------------------------------
local balances = {}

----------------------------------------------------------------------
-- Pending money  { [userId] = { [slotKey] = accumulatedAmount } }
-- slotKey = spawnPart:GetFullName() — unique per deposited brainrot slot.
-- Players must physically touch their slot to claim it (unless gamepass).
----------------------------------------------------------------------
local pendingMoney = {}

-- Auto-collect gamepass owners cache  { [userId] = bool }
local autoCollectCache = {}

local MarketplaceService = game:GetService("MarketplaceService")

local function hasAutoCollect(userId)
	if AUTO_COLLECT_GAMEPASS_ID == 0 then return false end
	if autoCollectCache[userId] ~= nil then return autoCollectCache[userId] end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, AUTO_COLLECT_GAMEPASS_ID)
	end)
	local result = ok and owns or false
	autoCollectCache[userId] = result
	return result
end

local function getPending(userId)
	if not pendingMoney[userId] then pendingMoney[userId] = {} end
	return pendingMoney[userId]
end

local function getTotalPending(userId)
	local total = 0
	for _, amt in pairs(getPending(userId)) do
		total += amt
	end
	return total
end

local function savePending(userId)
	local data = {}
	for slotKey, amt in pairs(getPending(userId)) do
		if amt > 0 then data[slotKey] = amt end
	end
	pcall(function()
		PendingStore:SetAsync(tostring(userId), data)
	end)
end

local function loadPending(userId)
	local ok, data = pcall(function()
		return PendingStore:GetAsync(tostring(userId))
	end)
	if ok and type(data) == "table" then
		-- Migration: drop any legacy bare-name keys (e.g. "Spawn") left over
		-- from before GetFullName() was used. Valid keys always contain a dot
		-- (e.g. "Workspace.PlayerIsland.BrainrotSlots.Slot.Spawn") or are the
		-- reserved "offline" bucket.
		local cleaned = {}
		for slotKey, amt in pairs(data) do
			-- Valid keys: "offline", a full path with dots ("Workspace.X.Y"),
			-- or the new "Workspace.X.Y/ModelName" format.
			if slotKey == "offline" or slotKey:find(".", 1, true) then
				cleaned[slotKey] = amt
			else
				warn(string.format(
					"[MoneyServer] Dropping legacy pending key '%s' for %s",
					slotKey, tostring(userId)
					))
			end
		end
		pendingMoney[userId] = cleaned
	else
		pendingMoney[userId] = {}
	end
end

----------------------------------------------------------------------
-- Deposited brainrots  { [brainrotModel] = { owner=userId, dps=number, spawnPart=BasePart } }
----------------------------------------------------------------------
local depositedBrainrots = {}

----------------------------------------------------------------------
-- MONEY HELPERS
----------------------------------------------------------------------
local function getBalance(userId)
	if not balances[userId] then
		local ok, val = pcall(function()
			return MoneyStore:GetAsync(tostring(userId))
		end)
		balances[userId] = (ok and type(val) == "number") and val or 0
	end
	return balances[userId]
end

local function addMoney(userId, amount)
	balances[userId] = getBalance(userId) + amount
end

local function saveBalance(userId)
	local ok, err = pcall(function()
		MoneyStore:SetAsync(tostring(userId), balances[userId])
	end)
	if not ok then
		warn("[MoneyServer] Failed to save balance for", userId, err)
	end
end

----------------------------------------------------------------------
-- REMOTE EVENT  (server -> client balance updates)
----------------------------------------------------------------------
local function getOrCreate(parent, class, name)
	return parent:FindFirstChild(name) or Instance.new(class, parent)
end

local remotes      = getOrCreate(ReplicatedStorage, "Folder", "MoneyRemotes")
local evtUpdateBal = getOrCreate(remotes, "RemoteEvent", "UpdateBalance")
local _evtOffline  = getOrCreate(remotes, "RemoteEvent", "OfflineEarnings")
-- OfflineEarnings fired server->client: (player, amountEarned, secondsElapsed)

local function pushBalance(userId)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		evtUpdateBal:FireClient(player, balances[userId])
	end
end

----------------------------------------------------------------------
-- OFFLINE EARNINGS
----------------------------------------------------------------------
-- Returns the total $/s currently deposited by a userId.
local function getTotalDpsForPlayer(userId)
	local total = 0
	for _, info in pairs(depositedBrainrots) do
		if info.owner == userId then
			total += info.dps
		end
	end
	return total
end

-- Called on PlayerAdded: credit any earnings while they were offline.
-- Offline earnings go into the pending bucket (not directly to balance),
-- unless the player has the auto-collect gamepass.
local function applyOfflineEarnings(userId)
	local ok, data = pcall(function()
		return OfflineStore:GetAsync(tostring(userId))
	end)
	if not ok or type(data) ~= "table" then return end

	local leaveTime = tonumber(data.leaveTime)
	local totalDps  = tonumber(data.totalDps)
	if not leaveTime or not totalDps or totalDps <= 0 then return end

	local now     = os.time()
	local elapsed = math.clamp(now - leaveTime, 0, OFFLINE_CAP)
	local earned  = math.floor(elapsed * totalDps)

	if earned > 0 then
		if hasAutoCollect(userId) then
			-- Gamepass owners get it straight to their balance
			addMoney(userId, earned)
			print(string.format(
				"[MoneyServer] Offline earnings (auto-collect): +$%d to %s (%ds offline @ $%g/s)",
				earned, tostring(userId), elapsed, totalDps
				))
		else
			-- Everyone else: lump it into a special "offline" pending key
			local pending = getPending(userId)
			pending["offline"] = (pending["offline"] or 0) + earned
			print(string.format(
				"[MoneyServer] Offline earnings (pending): +$%d to %s (%ds offline @ $%g/s)",
				earned, tostring(userId), elapsed, totalDps
				))
		end

		-- Fire notification regardless
		local player = Players:GetPlayerByUserId(userId)
		if player then
			local offlineEvt = remotes:FindFirstChild("OfflineEarnings")
			if offlineEvt then
				offlineEvt:FireClient(player, earned, elapsed)
			end
		end
	end

	pcall(function() OfflineStore:RemoveAsync(tostring(userId)) end)
end

-- Called on PlayerRemoving: snapshot timestamp + current $/s.
local function saveOfflineSnapshot(userId)
	local totalDps = getTotalDpsForPlayer(userId)
	if totalDps <= 0 then return end   -- nothing deposited, nothing to track

	local snapshot = { leaveTime = os.time(), totalDps = totalDps }
	local ok, err = pcall(function()
		OfflineStore:SetAsync(tostring(userId), snapshot)
	end)
	if not ok then
		warn("[MoneyServer] Failed to save offline snapshot for", userId, err)
	else
		print(string.format(
			"[MoneyServer] Offline snapshot saved for %s: $%g/s @ t=%d",
			tostring(userId), totalDps, snapshot.leaveTime
			))
	end
end

----------------------------------------------------------------------
-- SLOT COLLECT BILLBOARD
-- Shown 20 studs above the Spawn part of each occupied slot.
-- Updates in real-time to show the pending $ amount.
-- Destroyed when the player claims or when the brainrot is picked up.
----------------------------------------------------------------------
local slotBillboards = {}   -- [spawnPart] = { bg=BillboardGui, label=TextLabel }
local slotTouchConns = {}   -- [spawnPart] = RBXScriptConnection

local function makeSlotBillboard(spawnPart, ownerUserId)
	-- Remove any existing billboard on this part
	local old = spawnPart:FindFirstChild("SlotPendingBillboard")
	if old then old:Destroy() end
	if slotBillboards[spawnPart] then
		slotBillboards[spawnPart] = nil
	end

	local bg = Instance.new("BillboardGui")
	bg.Name           = "SlotPendingBillboard"
	bg.Adornee        = spawnPart
	bg.Size           = UDim2.new(0, 180, 0, 70)
	bg.StudsOffset    = Vector3.new(0, SLOT_BILLBOARD_Y_OFFSET, 0)
	bg.AlwaysOnTop    = false
	bg.MaxDistance    = 60
	bg.ResetOnSpawn   = false
	bg.LightInfluence = 0

	local frame = Instance.new("Frame", bg)
	frame.Size                   = UDim2.fromScale(1, 1)
	frame.BackgroundColor3       = Color3.fromRGB(10, 30, 15)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel        = 0
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
	local stroke = Instance.new("UIStroke", frame)
	stroke.Color       = Color3.fromRGB(80, 255, 120)
	stroke.Thickness   = 1.5

	local topLabel = Instance.new("TextLabel", frame)
	topLabel.Size                   = UDim2.new(1, 0, 0.45, 0)
	topLabel.Position               = UDim2.new(0, 0, 0, 0)
	topLabel.BackgroundTransparency = 1
	topLabel.Text                   = "💰 Pending"
	topLabel.TextColor3             = Color3.fromRGB(255, 210, 60)
	topLabel.TextScaled             = true
	topLabel.Font                   = Enum.Font.GothamBold

	local amtLabel = Instance.new("TextLabel", frame)
	amtLabel.Name                   = "AmountLabel"
	amtLabel.Size                   = UDim2.new(1, 0, 0.55, 0)
	amtLabel.Position               = UDim2.new(0, 0, 0.45, 0)
	amtLabel.BackgroundTransparency = 1
	amtLabel.Text                   = "$0"
	amtLabel.TextColor3             = Color3.fromRGB(100, 255, 130)
	amtLabel.TextScaled             = true
	amtLabel.Font                   = Enum.Font.GothamBold

	local hintLabel = Instance.new("TextLabel", frame)
	hintLabel.Size                   = UDim2.new(1, 0, 0.3, 0)
	hintLabel.Position               = UDim2.new(0, 0, 0.7, 0)
	hintLabel.BackgroundTransparency = 1
	hintLabel.Text                   = "Touch slot to collect"
	hintLabel.TextColor3             = Color3.fromRGB(180, 180, 180)
	hintLabel.TextScaled             = true
	hintLabel.Font                   = Enum.Font.Gotham

	bg.Parent = spawnPart
	slotBillboards[spawnPart] = { bg = bg, label = amtLabel, owner = ownerUserId }
	return amtLabel
end

local function updateSlotBillboard(spawnPart, amount)
	local entry = slotBillboards[spawnPart]
	if not entry then return end
	entry.label.Text = string.format("$%s", math.floor(amount))
end

local function removeSlotBillboard(spawnPart)
	local entry = slotBillboards[spawnPart]
	if entry then
		if entry.bg and entry.bg.Parent then
			entry.bg:Destroy()
		end
		slotBillboards[spawnPart] = nil
	end
	if slotTouchConns[spawnPart] then
		slotTouchConns[spawnPart]:Disconnect()
		slotTouchConns[spawnPart] = nil
	end
end

----------------------------------------------------------------------
-- ATTACH TOUCH COLLECTOR on a SpawnPart
-- When the owner (or anyone for stealing-proof: just the owner) walks
-- into the slot, all pending money is claimed into their balance.
----------------------------------------------------------------------
local function attachTouchCollector(spawnPart, ownerUserId, slotKey)
	-- Remove any old connection first
	if slotTouchConns[spawnPart] then
		slotTouchConns[spawnPart]:Disconnect()
	end

	slotTouchConns[spawnPart] = spawnPart.Parent:FindFirstChild("Collect").Touched:Connect(function(hit)
		-- hit must belong to the owner's character
		local character = hit.Parent
		if not character then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player or player.UserId ~= ownerUserId then return end

		-- Collect pending for this specific slot + the offline bucket
		local pending    = getPending(ownerUserId)
		local slotAmt    = pending[slotKey] or 0
		local offlineAmt = pending["offline"] or 0
		local total      = slotAmt + offlineAmt

		if total <= 0 then return end

		pending[slotKey]   = 0
		pending["offline"] = 0
		addMoney(ownerUserId, total)
		pushBalance(ownerUserId)
		savePending(ownerUserId)

		-- Clear the billboard
		updateSlotBillboard(spawnPart, 0)

		print(string.format(
			"[MoneyServer] %s collected $%d from slot (key=%s)",
			tostring(ownerUserId), total, slotKey
			))
	end)
end

----------------------------------------------------------------------
-- BINDABLE BRIDGE  (server -> server, used by pickup ServerScripts)
-- Creates a BindableFunction named "MoneyBridge" in ServerStorage.
-- Invoke signature:  bridge:Invoke(action, userId, model, dps)
--   action = "deposit"  -> register model as accumulating for userId at dps/s
--   action = "pickup"   -> unregister model (stop accumulating, remove billboard)
----------------------------------------------------------------------
local bridge = getOrCreate(ServerStorage, "BindableFunction", "MoneyBridge")

bridge.OnInvoke = function(action, userId, model, dps)
	if action == "deposit" then
		if not model or not userId then return end

		-- Find the SpawnPart: the brainrot is parented to it at deposit time.
		-- proximityprompt.lua re-parents to spawnPart before calling notifyDeposit.
		local spawnPart = model.Parent
		if not spawnPart or not spawnPart:IsA("BasePart") then
			-- Fallback: look one level up from model's current parent
			spawnPart = nil
		end

		-- Build a unique slot key from spawnPart path + brainrot name.
		-- spawnPart:GetFullName() alone is NOT unique because every slot is named
		-- "Slot", giving the same path. Appending the model name makes it unique
		-- since each slot holds a different brainrot.
		local slotKey = spawnPart and (spawnPart:GetFullName() .. "/" .. model.Name) or nil

		depositedBrainrots[model] = { owner = userId, dps = dps, spawnPart = spawnPart, slotKey = slotKey }
		print(string.format("[MoneyServer] Deposit: %s earns $%g/s from %s (key=%s)", tostring(userId), dps, model.Name, tostring(slotKey)))

		-- Set up the slot billboard and touch collector (unless gamepass owner)
		if spawnPart and slotKey and not hasAutoCollect(userId) then
			makeSlotBillboard(spawnPart, userId)
			-- Initialise billboard amount from any existing pending for this slot
			local existing = getPending(userId)[slotKey] or 0
			updateSlotBillboard(spawnPart, existing)
			attachTouchCollector(spawnPart, userId, slotKey)
		end

	elseif action == "pickup" then
		if model and depositedBrainrots[model] then
			local info = depositedBrainrots[model]
			saveBalance(info.owner)
			-- Remove the slot billboard & touch collector
			if info.spawnPart then
				removeSlotBillboard(info.spawnPart)
			end
			depositedBrainrots[model] = nil
			print(string.format("[MoneyServer] Pickup: stopped payout for %s", model.Name))
		end

	elseif action == "getBalance" then
		return getBalance(userId)

	elseif action == "getSpawnPart" then
		-- Returns the SpawnPart a brainrot model is currently deposited in,
		-- or nil if it isn't registered. Used by proximityprompt.lua to tag
		-- stolen brainrots whose parent has been moved back to workspace.
		local info = model and depositedBrainrots[model]
		return info and info.spawnPart or nil

	elseif action == "deductBalance" then
		local amount = model
		if not userId or not amount then return end
		local current = getBalance(userId)
		balances[userId] = math.max(0, current - amount)
		pushBalance(userId)
		print(string.format("[MoneyServer] Charged $%g from %s (was $%g, now $%g)",
			amount, tostring(userId), current, balances[userId]))

	elseif action == "addMoney" then
		local amount = model
		if not userId or not amount then return end
		addMoney(userId, amount)
		pushBalance(userId)
		print(string.format("[MoneyServer] Admin credit: +$%g to %s (now $%g)",
			amount, tostring(userId), balances[userId]))

	elseif action == "takeMoney" then
		local amount = model
		if not userId or not amount then return end
		local current = getBalance(userId)
		balances[userId] = math.max(0, current - amount)
		saveBalance(userId)
		pushBalance(userId)
		print(string.format("[MoneyServer] Admin took $%g from %s (was $%g, now $%g)",
			amount, tostring(userId), current, balances[userId]))
		return balances[userId]

	elseif action == "resetMoney" then
		if not userId then return end
		local old = getBalance(userId)
		balances[userId] = 0
		saveBalance(userId)
		pushBalance(userId)
		print(string.format("[MoneyServer] Admin reset money for %s (was $%g)", tostring(userId), old))

	elseif action == "clearPlayer" then
		-- Deregister all deposited brainrots owned by userId, remove their
		-- billboards/touch collectors, and return the list of model instances
		-- so the caller can destroy them.
		-- Used by BrainrotSaveServer when a player leaves to reset their island.
		if not userId then return end
		local removed = {}
		for model, info in pairs(depositedBrainrots) do
			if info.owner == userId then
				if info.spawnPart then
					removeSlotBillboard(info.spawnPart)
				end
				depositedBrainrots[model] = nil
				table.insert(removed, model)
			end
		end
		return removed
	end
end

----------------------------------------------------------------------
-- BILLBOARD GUI  (cost + $/s label floating above each brainrot)
----------------------------------------------------------------------
local function makeBillboard(model, dps, cost)
	local primaryPart = model.PrimaryPart
	if not primaryPart then return end

	local old = primaryPart:FindFirstChild("BrainrotBillboard")
	if old then old:Destroy() end

	-- Taller billboard to fit two rows when a cost is present
	local hasCost = cost and cost > 0
	local billHeight = hasCost and 64 or 40

	local bg = Instance.new("BillboardGui")
	bg.Name          = "BrainrotBillboard"
	bg.Adornee       = primaryPart
	bg.Size          = UDim2.new(0, 150, 0, billHeight)
	bg.StudsOffset   = Vector3.new(0, WORLD_BILLBOARD_Y_OFFSET, 0)
	bg.AlwaysOnTop   = false
	bg.MaxDistance   = 50
	bg.ResetOnSpawn  = false
	bg.LightInfluence = 0

	local frame = Instance.new("Frame", bg)
	frame.Size                   = UDim2.fromScale(1, 1)
	frame.BackgroundColor3       = Color3.fromRGB(12, 18, 35)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel        = 0

	local corner = Instance.new("UICorner", frame)
	corner.CornerRadius = UDim.new(0, 8)

	local stroke = Instance.new("UIStroke", frame)
	stroke.Color       = Color3.fromRGB(80, 220, 255)
	stroke.Thickness   = 1.5
	stroke.Transparency = 0.5

	local listLayout = Instance.new("UIListLayout", frame)
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.SortOrder     = Enum.SortOrder.LayoutOrder
	listLayout.Padding       = UDim.new(0, 0)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment   = Enum.VerticalAlignment.Center

	-- $/s row (always shown)
	local dpsLabel = Instance.new("TextLabel", frame)
	dpsLabel.LayoutOrder             = 1
	dpsLabel.Size                    = hasCost and UDim2.new(1, 0, 0.5, 0) or UDim2.fromScale(1, 1)
	dpsLabel.BackgroundTransparency  = 1
	dpsLabel.Text                    = string.format("$%g / sec", dps)
	dpsLabel.TextColor3              = Color3.fromRGB(80, 255, 100)
	dpsLabel.TextScaled              = true
	dpsLabel.Font                    = Enum.Font.GothamBold

	-- Cost row (only shown when cost > 0 and not yet purchased)
	if hasCost then
		-- Watch HasBeenPurchased so the cost row hides after first buy
		local purchasedTag = model:FindFirstChild("HasBeenPurchased")

		local costLabel = Instance.new("TextLabel", frame)
		costLabel.LayoutOrder            = 2
		costLabel.Size                   = UDim2.new(1, 0, 0.5, 0)
		costLabel.BackgroundTransparency = 1
		costLabel.Text                   = string.format("🛒 $%g to buy", cost)
		costLabel.TextColor3             = Color3.fromRGB(255, 210, 60)
		costLabel.TextScaled             = true
		costLabel.Font                   = Enum.Font.Gotham

		-- Update cost label visibility live (hide once purchased)
		local function refreshCostLabel()
			local purchased = purchasedTag and purchasedTag.Value
			costLabel.Visible = not purchased
			-- Shrink dps label to full height if cost row is hidden
			dpsLabel.Size = purchased and UDim2.fromScale(1, 1) or UDim2.new(1, 0, 0.5, 0)
		end
		refreshCostLabel()
		if purchasedTag then
			purchasedTag:GetPropertyChangedSignal("Value"):Connect(refreshCostLabel)
		end
	end

	bg.Parent = primaryPart
end

local function tryAttachBillboard(model)
	local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt then return end
	local config = prompt:FindFirstChild("MoneyConfig")
	if not config then return end
	local ok, cfg = pcall(require, config)
	if not ok or type(cfg) ~= "table" or not cfg.DollarsPerSecond then return end
	local cost = cfg.Cost or 0
	makeBillboard(model, cfg.DollarsPerSecond, cost)
end

-- Scan existing workspace models
for _, obj in ipairs(workspace:GetDescendants()) do
	if obj:IsA("Model") and obj.PrimaryPart then
		tryAttachBillboard(obj)
	end
end

-- Watch for newly added models
workspace.DescendantAdded:Connect(function(obj)
	if obj:IsA("Model") and obj.PrimaryPart then
		tryAttachBillboard(obj)
	end
	if obj:IsA("BasePart") then
		local model = obj:FindFirstAncestorWhichIsA("Model")
		if model and model.PrimaryPart == obj then
			tryAttachBillboard(model)
		end
	end
end)

----------------------------------------------------------------------
-- BOOST BRIDGE  (query BoostServer for the current multiplier per player)
----------------------------------------------------------------------
local boostBridge = ServerStorage:WaitForChild("BoostBridge", 10)

local function getBoostMultiplier(userId)
	if boostBridge then
		local ok, mult = pcall(function()
			return boostBridge:Invoke("getMultiplier", userId)
		end)
		if ok and type(mult) == "number" then return mult end
	end
	return 1
end

----------------------------------------------------------------------
-- PAYOUT LOOP  - every second, accumulate pending money for each deposited brainrot.
-- Gamepass owners get it directly to balance; everyone else must collect by touch.
----------------------------------------------------------------------
local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 1 then return end
	accumulator -= 1

	for model, info in pairs(depositedBrainrots) do
		if not model or not model.Parent then
			depositedBrainrots[model] = nil
			continue
		end
		local multiplier = getBoostMultiplier(info.owner)
		local earned     = info.dps * multiplier

		if hasAutoCollect(info.owner) then
			-- Gamepass: instant to balance, no pending
			addMoney(info.owner, earned)
			pushBalance(info.owner)
		else
			-- Accumulate into pending for this slot
			if not info.spawnPart or not info.slotKey then continue end
			local pending = getPending(info.owner)
			pending[info.slotKey] = (pending[info.slotKey] or 0) + earned
			-- Update the billboard label live
			updateSlotBillboard(info.spawnPart, pending[info.slotKey])
		end
	end
end)

----------------------------------------------------------------------
-- AUTO-SAVE LOOP
----------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(SAVE_INTERVAL)
		for userId in pairs(balances) do
			saveBalance(userId)
		end
		for userId in pairs(pendingMoney) do
			savePending(userId)
		end
	end
end)

----------------------------------------------------------------------
-- PLAYER LIFECYCLE
----------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	local userId = player.UserId
	getBalance(userId)
	loadPending(userId)
	-- Apply offline earnings before pushing balance so the client sees
	-- the already-credited total on first UpdateBalance fire.
	applyOfflineEarnings(userId)
	pushBalance(userId)
end)

Players.PlayerRemoving:Connect(function(player)
	local userId = player.UserId
	saveBalance(userId)
	savePending(userId)
	saveOfflineSnapshot(userId)
	autoCollectCache[userId] = nil
	-- depositedBrainrots entries for this player are intentionally kept --
	-- the brainrot stays in the slot; the $/s is saved in the offline
	-- snapshot so it can be credited when they rejoin.
end)

print("[MoneyServer] Ready.")