-- Script (ServerScript, inside each brainrot's ProximityPrompt)
-- Handles pickup, deposit, and notifies the MoneyServer directly
-- since this already runs on the server.
--
-- PURCHASE SYSTEM:
--   The FIRST time a brainrot is picked up it costs `Cost` dollars (from MoneyConfig).
--   After it has been purchased once (tracked via a BoolValue "HasBeenPurchased" on the
--   model), anyone can steal it for free — just like a real steal mechanic.
--   Players can never go negative; if they can't afford it they get a UI notification.
--
-- Smooth carrying is handled CLIENT-SIDE via the CarryBrainrot RemoteEvent
-- so that PivotTo updates happen locally with zero network lag.

local prompt        = script.Parent
local brainrotModel = prompt.Parent

----------------------------------------------------------------------
-- CONFIGURATION
----------------------------------------------------------------------
local OFFSET_CFRAME   = CFrame.new(0, 0, 0.6) * CFrame.Angles(0, math.rad(180), 0)
local SLOT_NAME       = "Slot"
local SPAWN_PART_NAME = "Spawn"
local HELD_SCALE      = 0.8
local SLOT_SCALE      = 0.5

----------------------------------------------------------------------
-- READ MoneyConfig  (DollarsPerSecond + Cost)
----------------------------------------------------------------------
local config = prompt:FindFirstChild("MoneyConfig")
local DPS  = 0
local COST = 0
if config then
	local ok, cfg = pcall(require, config)
	if ok and type(cfg) == "table" then
		DPS  = cfg.DollarsPerSecond or 0
		COST = cfg.Cost             or 0
	end
end

-- "HasBeenPurchased" BoolValue on the model tracks whether the first-time
-- cost has already been paid. Once true, all future pickups are free steals.
local purchasedTag = brainrotModel:FindFirstChild("HasBeenPurchased")
if not purchasedTag then
	purchasedTag        = Instance.new("BoolValue")
	purchasedTag.Name   = "HasBeenPurchased"
	purchasedTag.Value  = false
	purchasedTag.Parent = brainrotModel
end

----------------------------------------------------------------------
-- SERVICES & SHARED OBJECTS
----------------------------------------------------------------------
local ServerStorage     = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

-- MoneyBridge: deposit / pickup / getBalance / deductBalance
local moneyBridge = ServerStorage:WaitForChild("MoneyBridge", 10)

-- IslandBridge: (userId) → PlayerIsland model
local islandBridge = ServerStorage:WaitForChild("IslandBridge", 10)

-- BrainrotSlotChanged BindableEvent – consumed by BrainrotSaveServer
local slotChanged = ServerStorage:WaitForChild("BrainrotSlotChanged", 10)

-- RemoteEvents live in ReplicatedStorage > MoneyRemotes
local remotes = ReplicatedStorage:WaitForChild("MoneyRemotes", 10)

local function getOrCreateRemote(name)
	if not remotes then return nil end
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name   = name
		r.Parent = remotes
	end
	return r
end

-- CarryBrainrot: tells the client to start/stop the smooth follow loop
local carryEvent  = getOrCreateRemote("CarryBrainrot")
-- PickupDenied: tells the client to show a "not enough money" toast
local deniedEvent = getOrCreateRemote("PickupDenied")
-- DropBrainrot: client fires this when the player wants to drop mid-carry
local dropEvent   = getOrCreateRemote("DropBrainrot")

----------------------------------------------------------------------
-- MONEY BRIDGE HELPERS
----------------------------------------------------------------------
local function getBalance(userId)
	if not moneyBridge then return 0 end
	local ok, val = pcall(function()
		return moneyBridge:Invoke("getBalance", userId)
	end)
	return (ok and type(val) == "number") and val or 0
end

local function deductBalance(userId, amount)
	if not moneyBridge then return end
	pcall(function()
		moneyBridge:Invoke("deductBalance", userId, amount)
	end)
end

local function notifyDeposit(userId, player, slotModel)
	if moneyBridge then
		print("[proximityprompt] invoking moneybridge deposit")
		moneyBridge:Invoke("deposit", userId, brainrotModel, DPS)
	end
	if slotChanged then
		slotChanged:Fire("deposit", player, slotModel, brainrotModel)
	end
end

local function notifyPickup(player)
	if moneyBridge then
		moneyBridge:Invoke("pickup", nil, brainrotModel, nil)
	end
	if slotChanged then
		-- Determine whether this brainrot was sitting in a slot at the
		-- time of pickup. brainrotModel.Parent is the Spawn part when
		-- deposited, and Spawn's parent is the Slot model.
		-- Pass the slotModel so BrainrotSaveServer only clears the entry
		-- when the brainrot was genuinely removed from a slot.
		local spawn     = brainrotModel.Parent
		local slotModel = (spawn and spawn.Name == SPAWN_PART_NAME)
			and spawn.Parent or nil
		slotChanged:Fire("pickup", player, slotModel, brainrotModel)
	end
end

----------------------------------------------------------------------
-- DROP HANDLER  (client fires DropBrainrot when player presses [G])
----------------------------------------------------------------------
if dropEvent then
	dropEvent.OnServerEvent:Connect(function(player)
		local character = player.Character
		if not character then return end

		-- Only handle the drop if this brainrot is actually being carried by this player
		if brainrotModel.Parent ~= character then return end

		local tag = character:FindFirstChild("BrainrotWeld")
		if not tag then return end

		-- Stop client carry loop first
		if carryEvent then
			carryEvent:FireClient(player, "stop", brainrotModel)
		end

		tag:Destroy()

		-- Clear stolen-tracking tags so a world-drop doesn't count as "stolen"
		local originSlotTag  = brainrotModel:FindFirstChild("OriginSlot")
		local originOwnerTag = brainrotModel:FindFirstChild("OriginOwner")
		if originSlotTag  then originSlotTag:Destroy()  end
		if originOwnerTag then originOwnerTag:Destroy() end

		-- Place brainrot on the ground just in front of the player
		local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
		local dropCFrame = torso
			and (torso.CFrame * CFrame.new(0, -2, -3))
			or  brainrotModel:GetPivot()

		brainrotModel.Parent = workspace
		brainrotModel:PivotTo(dropCFrame)
		brainrotModel:ScaleTo(1)   -- restore to full world scale

		-- Restore physics so it can be picked up again normally
		for _, part in pairs(brainrotModel:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored   = true   -- keep anchored so it doesn't fly off
				part.CanCollide = true
				part.CanTouch   = true
				part.Massless   = false
			end
		end

		-- Notify money system that the brainrot was picked up (unpaid / slot cleared)
		notifyPickup(player)

		prompt.Enabled = true

		print(string.format("[proximityprompt] %s dropped %s", player.Name, brainrotModel.Name))
	end)
end

----------------------------------------------------------------------
-- PICKUP HANDLER
----------------------------------------------------------------------
prompt.Triggered:Connect(function(player)
	local character = player.Character
	if not character or brainrotModel.Parent == character then return end

	-- One brainrot at a time
	if character:FindFirstChild("BrainrotWeld", true) then return end

	local torso    = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local mainPart = brainrotModel.PrimaryPart
	if not torso or not mainPart then return end

	-- ── PURCHASE CHECK ─────────────────────────────────────────────
	-- Only applies the very first time this instance is picked up.
	local needsToPay = (COST > 0) and (not purchasedTag.Value)
	if needsToPay then
		local balance = getBalance(player.UserId)
		if balance < COST then
			-- Not enough money — notify client and bail out, do NOT disable prompt
			if deniedEvent then
				deniedEvent:FireClient(player, COST, balance)
			end
			print(string.format(
				"[proximityprompt] %s can't afford %s (cost $%g, balance $%g)",
				player.Name, brainrotModel.Name, COST, balance
				))
			return
		end
		-- Charge the player
		deductBalance(player.UserId, COST)
		print(string.format(
			"[proximityprompt] %s purchased %s for $%g",
			player.Name, brainrotModel.Name, COST
			))
	end

	-- Mark as purchased so all future pickups are free steals
	purchasedTag.Value = true

	prompt.Enabled = false

	-- ── STOLEN TRACKING ────────────────────────────────────────────
	-- If the brainrot was sitting in a Slot's Spawn part at the time of
	-- pickup, record the original SpawnPart and island owner so the
	-- return system can send it back if the thief takes damage.
	--
	-- After deposit, the brainrot's parent is moved back to workspace
	-- (so its parent.Name is NOT "Spawn" anymore). We therefore query
	-- MoneyBridge first, which tracks the registered spawnPart regardless
	-- of where the model is currently parented.
	do
		local spawnPart = nil

		-- Primary: ask MoneyBridge which slot this model is registered in
		if moneyBridge then
			local ok, result = pcall(function()
				return moneyBridge:Invoke("getSpawnPart", nil, brainrotModel, nil)
			end)
			if ok and result and result:IsA("BasePart") then
				spawnPart = result
			end
		end

		-- Fallback: brainrot was never deposited this session but is still
		-- physically sitting inside a Spawn part (e.g. just restored by
		-- BrainrotSaveServer and not yet picked up before).
		if not spawnPart then
			local parentNow = brainrotModel.Parent
			if parentNow and parentNow.Name == SPAWN_PART_NAME then
				spawnPart = parentNow
			end
		end

		if spawnPart then
			-- Tag the brainrot as stolen so BrainrotReturnServer can find it
			local originTag = Instance.new("ObjectValue")
			originTag.Name   = "OriginSlot"
			originTag.Value  = spawnPart
			originTag.Parent = brainrotModel

			-- Record which player owns this island
			if islandBridge then
				local slotIsland = spawnPart.Parent and spawnPart.Parent.Parent -- Spawn → Slot → Island
				if slotIsland then
					for _, plr in ipairs(Players:GetPlayers()) do
						local ok, island = pcall(function()
							return islandBridge:Invoke(plr.UserId)
						end)
						if ok and island == slotIsland then
							local ownerTag = Instance.new("StringValue")
							ownerTag.Name   = "OriginOwner"
							ownerTag.Value  = tostring(plr.UserId)
							ownerTag.Parent = brainrotModel
							break
						end
					end
				end
			end
		end
	end

	-- Stop any existing payout for this brainrot
	notifyPickup(player)

	-- Scale while still in world, then freeze all parts
	brainrotModel:ScaleTo(HELD_SCALE)

	for _, part in pairs(brainrotModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored   = true
			part.CanCollide = false
			part.CanTouch   = false
			part.Massless   = true
		end
	end

	-- Snap to carry position and reparent into the character
	brainrotModel:PivotTo(torso.CFrame * OFFSET_CFRAME)
	brainrotModel.Parent = character

	-- Tag so other prompts know something is being carried
	local tag     = Instance.new("StringValue")
	tag.Name      = "BrainrotWeld"
	tag.Value     = brainrotModel.Name
	tag.Parent    = character

	-- Tell the CLIENT to start the smooth follow loop.
	-- Deferred one frame so the reparent replication reaches the client
	-- before the Heartbeat loop starts (avoids an immediate false-stop).
	if carryEvent then
		task.defer(function()
			carryEvent:FireClient(player, "start", brainrotModel, OFFSET_CFRAME)
		end)
	end

	-- ── DEPOSIT LOGIC ───────────────────────────────────────────────
	local touchConnection
	touchConnection = character.PrimaryPart.Touched:Connect(function(hit)
		local slotModel = hit:FindFirstAncestor(SLOT_NAME)
		if slotModel then
			local spawnPart = slotModel:FindFirstChild(SPAWN_PART_NAME)
			if spawnPart then

				-- ── GUARD 1: own island only ────────────────────────
				-- Hierarchy: PlayerIsland → BrainrotSlots → Slot → Spawn
				-- slotModel.Parent        = BrainrotSlots (container)
				-- slotModel.Parent.Parent = PlayerIsland  ← what IslandBridge returns
				-- If IslandBridge hasn't resolved yet (nil), allow through.
				local slotIsland = slotModel.Parent and slotModel.Parent.Parent
				if islandBridge and slotIsland then
					local ok, playerIsland = pcall(function()
						return islandBridge:Invoke(player.UserId)
					end)
					-- Only block if we got a valid island back AND it differs
					if ok and playerIsland ~= nil and playerIsland ~= slotIsland then
						-- Wrong island — silently ignore this touch
						return
					end
				end

				-- ── GUARD 2: one brainrot per slot ──────────────────
				-- Reject deposit if the SpawnPart already has a brainrot
				-- sitting in it (any child Model counts).
				for _, child in ipairs(spawnPart:GetChildren()) do
					if child:IsA("Model") then
						-- Slot is occupied — silently ignore
						return
					end
				end

				touchConnection:Disconnect()
				tag:Destroy()

				-- Clear stolen-tracking tags (brainrot is home now)
				local originSlotTag  = brainrotModel:FindFirstChild("OriginSlot")
				local originOwnerTag = brainrotModel:FindFirstChild("OriginOwner")
				if originSlotTag  then originSlotTag:Destroy()  end
				if originOwnerTag then originOwnerTag:Destroy() end

				-- Stop the client follow loop before repositioning
				if carryEvent then
					carryEvent:FireClient(player, "stop", brainrotModel)
				end

				brainrotModel:PivotTo(spawnPart.CFrame)
				brainrotModel.Parent = spawnPart
				brainrotModel:ScaleTo(SLOT_SCALE)

				notifyDeposit(player.UserId, player, slotModel)
				prompt.Enabled = true
				brainrotModel.BrainrotWander.Enabled = false

				-- Restore physics in slot
				brainrotModel.Parent = workspace
				for _, part in pairs(brainrotModel:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Anchored   = true
						part.CanCollide = true
						part.CanTouch   = true
						part.Massless   = false
					end
				end

				print(string.format(
					"[proximityprompt] %s deposited %s — earning $%g/s",
					player.Name, brainrotModel.Name, DPS
					))
			end
		end
	end)
end)