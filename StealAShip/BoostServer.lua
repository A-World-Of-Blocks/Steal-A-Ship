-- BoostServer (Script, ServerScriptService)
-- Handles 2x money boost developer product purchases AND a server-wide 2x luck boost.
-- Uses os.time() (real wall-clock seconds, NOT playtime) for expiry
-- so the boost lasts the correct calendar duration even across rejoins.
--
-- ─── SETUP ──────────────────────────────────────────────────────────────────
-- 1. Create FOUR Developer Products in the Creator Hub.
-- 2. Fill in the product IDs below.
-- 3. Place this script in ServerScriptService.
-- ────────────────────────────────────────────────────────────────────────────

local MarketplaceService = game:GetService("MarketplaceService")
local Players            = game:GetService("Players")
local DataStoreService   = game:GetService("DataStoreService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerStorage      = game:GetService("ServerStorage")

----------------------------------------------------------------------
-- ► FILL THESE IN with your actual Developer Product IDs ◄
----------------------------------------------------------------------
local PRODUCT_15MIN  = 3544443843   -- 2x Money 15 min  (per-player)
local PRODUCT_30MIN  = 3544444088   -- 2x Money 30 min  (per-player)
local PRODUCT_1HR    = 3544444447   -- 2x Money 1 hour  (per-player)
local PRODUCT_LUCK   = 3544436072   -- 2x Luck  15 min  (SERVER-WIDE)

-- Duration in seconds for each product
local PRODUCT_DURATIONS = {
	[PRODUCT_15MIN] = 15 * 60,
	[PRODUCT_30MIN] = 30 * 60,
	[PRODUCT_1HR]   = 60 * 60,
	[PRODUCT_LUCK]  = 15 * 60,
}

local BOOST_MULTIPLIER = 2   -- money $/s multiplier
-- Luck boost raises RARITY_POWER in SpawnScript so rare brainrots spawn more often.
-- The actual value used is read by SpawnScript via BoostBridge "getLuckPower".
local LUCK_RARITY_POWER = 2  -- default RARITY_POWER in SpawnScript is 1; higher = rarer items more likely

----------------------------------------------------------------------
-- DataStore – persists money boost expiry per-player across rejoins.
----------------------------------------------------------------------
local BoostStore = DataStoreService:GetDataStore("BoostExpiry_v1")

-- Per-player money boost:  { [userId] = expiryTimestamp }
local boostExpiry = {}

-- Server-wide luck boost (single expiry, not per-player, not persisted — resets on server restart)
local luckExpiry = 0   -- os.time() epoch; 0 = inactive

local function loadExpiry(userId)
	if boostExpiry[userId] ~= nil then return boostExpiry[userId] end
	local ok, val = pcall(function()
		return BoostStore:GetAsync(tostring(userId))
	end)
	boostExpiry[userId] = (ok and type(val) == "number") and val or 0
	return boostExpiry[userId]
end

local function saveExpiry(userId)
	pcall(function()
		BoostStore:SetAsync(tostring(userId), boostExpiry[userId] or 0)
	end)
end

local function getMultiplier(userId)
	local expiry = loadExpiry(userId)
	if expiry and expiry > os.time() then
		return BOOST_MULTIPLIER
	end
	return 1
end

local function isLuckActive()
	return luckExpiry > os.time()
end

local function getLuckRemainingSeconds()
	return isLuckActive() and (luckExpiry - os.time()) or 0
end

----------------------------------------------------------------------
-- RemoteEvents for client UI
----------------------------------------------------------------------
local function getOrCreate(parent, class, name)
	local el = parent:FindFirstChild(name) or Instance.new(class, parent)
	el.Name = name
	return el
end

local remotes     = getOrCreate(ReplicatedStorage, "Folder", "MoneyRemotes")
-- Per-player money boost update: (expiryTimestamp, multiplier)
local boostUpdate = getOrCreate(remotes, "RemoteEvent", "BoostUpdate")
-- Server-wide luck boost update fired to ALL clients: (luckExpiry, luckRarityPower)
local luckUpdate  = getOrCreate(remotes, "RemoteEvent", "LuckBoostUpdate")
-- Server-wide announcement fired to ALL clients: (buyerName, productLabel)
local announcement = getOrCreate(remotes, "RemoteEvent", "ServerAnnouncement")

local boostInfoFunc = getOrCreate(remotes, "RemoteFunction", "RequestBoostInfo")

boostInfoFunc.OnServerInvoke = function(player)
	return {
		product15min   = PRODUCT_15MIN,
		product30min   = PRODUCT_30MIN,
		product1hr     = PRODUCT_1HR,
		productLuck    = PRODUCT_LUCK,
		multiplier     = BOOST_MULTIPLIER,
		expiryTime     = loadExpiry(player.UserId),
		luckExpiry     = luckExpiry,
		luckRarityPower = LUCK_RARITY_POWER,
	}
end

local function pushBoostToClient(player)
	local expiry = loadExpiry(player.UserId)
	boostUpdate:FireClient(player, expiry or 0, getMultiplier(player.UserId))
end

local function pushLuckToAll()
	luckUpdate:FireAllClients(luckExpiry, LUCK_RARITY_POWER)
end

----------------------------------------------------------------------
-- BindableFunction "BoostBridge" – called by MoneyServer and SpawnScript
----------------------------------------------------------------------
local boostBridge = getOrCreate(ServerStorage, "BindableFunction", "BoostBridge")

boostBridge.OnInvoke = function(action, userId)
	if action == "getMultiplier" then
		return getMultiplier(userId)
	elseif action == "getExpiry" then
		return loadExpiry(userId)
	elseif action == "isLuckActive" then
		return isLuckActive()
	elseif action == "getLuckPower" then
		-- Returns the elevated RARITY_POWER when luck is active, else 1 (SpawnScript default)
		return isLuckActive() and LUCK_RARITY_POWER or nil
	elseif action == "getLuckExpiry" then
		return luckExpiry
	end
	return 1
end

----------------------------------------------------------------------
-- PURCHASE RECEIPT HANDLER
----------------------------------------------------------------------
MarketplaceService.ProcessReceipt = function(receiptInfo)
	local userId    = receiptInfo.PlayerId
	local productId = receiptInfo.ProductId
	local duration  = PRODUCT_DURATIONS[productId]

	if not duration then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local now    = os.time()
	local player = Players:GetPlayerByUserId(userId)
	local buyerName = player and player.Name or ("Player " .. userId)

	-- ── LUCK BOOST (server-wide) ──────────────────────────────────
	if productId == PRODUCT_LUCK then
		local base      = luckExpiry > now and luckExpiry or now
		luckExpiry      = base + duration
		pushLuckToAll()

		-- Announce to every player
		announcement:FireAllClients(buyerName, "2x Luck", luckExpiry)

		print(string.format("[BoostServer] %s activated server-wide 2x Luck for %ds. Expires %d",
			buyerName, duration, luckExpiry))

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- ── MONEY BOOST (per-player) ──────────────────────────────────
	local current   = loadExpiry(userId)
	local base      = (current and current > now) and current or now
	local newExpiry = base + duration

	boostExpiry[userId] = newExpiry
	saveExpiry(userId)

	if player then
		pushBoostToClient(player)
		print(string.format("[BoostServer] %s purchased %ds money boost. Expires at %d (in %ds)",
			buyerName, duration, newExpiry, newExpiry - now))
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

----------------------------------------------------------------------
-- PLAYER LIFECYCLE
----------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	loadExpiry(player.UserId)
	task.wait(1)
	pushBoostToClient(player)
	-- Also send current luck state so their UI is up to date on join
	luckUpdate:FireClient(player, luckExpiry, LUCK_RARITY_POWER)
end)

Players.PlayerRemoving:Connect(function(player)
	saveExpiry(player.UserId)
end)

----------------------------------------------------------------------
-- PERIODIC PUSH
----------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(30)
		for _, player in ipairs(Players:GetPlayers()) do
			pushBoostToClient(player)
		end
		-- Re-broadcast luck state so all clients stay in sync
		pushLuckToAll()
	end
end)

print("[BoostServer] Ready. Products:", PRODUCT_15MIN, PRODUCT_30MIN, PRODUCT_1HR, PRODUCT_LUCK)
