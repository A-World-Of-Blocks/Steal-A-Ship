-- ToolStoreServer  (Script, child of the tool-shop ProximityPrompt)
--
-- Setup:
--   • Place this Script as a CHILD of a ProximityPrompt on your shop part.
--   • Put Tool instances in  ReplicatedStorage > Tools
--   • Each tool needs two Attributes:
--       "name"  (string) – display name shown in the store card
--       "price" (number) – cost in in-game dollars
--
-- What this script does:
--   • On PlayerAdded  → loads owned-tool list from DataStore and gives
--     every tool the player already owns into their Backpack.
--   • On PlayerRemoving → saves their owned-tool list.
--   • ProximityPrompt.Triggered → fires OpenToolStore RemoteEvent to
--     the triggering client with the full tool catalogue so the client
--     can build the store UI (no sensitive data needed client-side).
--   • BuyTool RemoteEvent (client → server) → validates balance, deducts
--     money via MoneyBridge, records purchase, gives tool, saves.
--
-- RemoteEvents created in  ReplicatedStorage > ToolStoreRemotes:
--   OpenToolStore  (server → client)   payload: array of { name, price, id }
--   BuyTool        (client → server)   payload: toolId (string = tool name)
--   BuyResult      (server → client)   payload: success (bool), message (string)

local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")

----------------------------------------------------------------------
-- CONFIGURATION
----------------------------------------------------------------------
local TOOLS_FOLDER_NAME = "Tools"       -- ReplicatedStorage child
local DATASTORE_NAME    = "ToolOwned_v1"

----------------------------------------------------------------------
-- SERVICES / BRIDGES
----------------------------------------------------------------------
local prompt      = script.Parent   -- ProximityPrompt this script lives inside
local ToolStore   = DataStoreService:GetDataStore(DATASTORE_NAME)
local moneyBridge = ServerStorage:WaitForChild("MoneyBridge", 30)

local toolsFolder = ReplicatedStorage:WaitForChild(TOOLS_FOLDER_NAME, 30)
if not toolsFolder then
	warn("[ToolStoreServer] ReplicatedStorage." .. TOOLS_FOLDER_NAME .. " not found – store will be empty.")
end

----------------------------------------------------------------------
-- REMOTE SETUP
----------------------------------------------------------------------
local function getOrCreate(parent, class, name)
	local existing = parent:FindFirstChild(name)
	if existing then return existing end
	local obj = Instance.new(class)
	obj.Name   = name
	obj.Parent = parent
	return obj
end

local storeRemotes = getOrCreate(ReplicatedStorage, "Folder",      "ToolStoreRemotes")
local evtOpen      = getOrCreate(storeRemotes,      "RemoteEvent", "OpenToolStore")
local evtBuy       = getOrCreate(storeRemotes,      "RemoteEvent", "BuyTool")
local evtResult    = getOrCreate(storeRemotes,      "RemoteEvent", "BuyResult")

----------------------------------------------------------------------
-- IN-MEMORY OWNED TOOLS   { [userId] = { [toolName] = true } }
----------------------------------------------------------------------
local ownedTools = {}

----------------------------------------------------------------------
-- DATASTORE HELPERS
----------------------------------------------------------------------
local function loadOwned(userId)
	local ok, data = pcall(function()
		return ToolStore:GetAsync(tostring(userId))
	end)
	if ok and type(data) == "table" then
		ownedTools[userId] = data
	else
		ownedTools[userId] = {}
	end
end

local function saveOwned(userId)
	pcall(function()
		ToolStore:SetAsync(tostring(userId), ownedTools[userId] or {})
	end)
end

local function isOwned(userId, toolName)
	return ownedTools[userId] and ownedTools[userId][toolName] == true
end

local function markOwned(userId, toolName)
	if not ownedTools[userId] then ownedTools[userId] = {} end
	ownedTools[userId][toolName] = true
end

----------------------------------------------------------------------
-- MONEY HELPERS  (via MoneyBridge)
----------------------------------------------------------------------
local function getBalance(userId)
	if not moneyBridge then return 0 end
	local ok, val = pcall(function()
		return moneyBridge:Invoke("getBalance", userId)
	end)
	return (ok and type(val) == "number") and val or 0
end

local function deductBalance(userId, amount)
	if not moneyBridge then return false end
	local ok = pcall(function()
		moneyBridge:Invoke("deductBalance", userId, amount)
	end)
	return ok
end

----------------------------------------------------------------------
-- GIVE TOOL TO PLAYER
-- Clones the tool from ReplicatedStorage.Tools into the player's Backpack.
-- Safe to call multiple times — won't duplicate if already in Backpack/StarterGear.
----------------------------------------------------------------------
local function giveTool(player, toolName)
	if not toolsFolder then return end
	local template = toolsFolder:FindFirstChild(toolName)
	if not template then
		warn("[ToolStoreServer] Tool template '" .. toolName .. "' not found in " .. TOOLS_FOLDER_NAME)
		return
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then return end

	-- Don't duplicate if they already have it equipped or in backpack
	if backpack:FindFirstChild(toolName) then return end
	local character = player.Character
	if character and character:FindFirstChild(toolName) then return end

	local clone = template:Clone()
	clone.Parent = backpack
end

----------------------------------------------------------------------
-- GIVE ALL OWNED TOOLS ON JOIN / RESPAWN
----------------------------------------------------------------------
local function giveAllOwned(player)
	local userId = player.UserId
	for toolName, owned in pairs(ownedTools[userId] or {}) do
		if owned then
			giveTool(player, toolName)
		end
	end
end

----------------------------------------------------------------------
-- BUILD TOOL CATALOGUE
-- Returns an array of { id, name, price } for every tool in the folder.
-- "id" is the tool instance name (used as the purchase key).
----------------------------------------------------------------------
local function buildCatalogue()
	local catalogue = {}
	if not toolsFolder then return catalogue end
	for _, tool in ipairs(toolsFolder:GetChildren()) do
		if tool:IsA("Tool") then
			local displayName = tool:GetAttribute("name")  or tool.Name
			local price       = tonumber(tool:GetAttribute("price")) or 0
			table.insert(catalogue, {
				id    = tool.Name,
				name  = displayName,
				price = price,
			})
		end
	end
	-- Sort by price ascending so cheap items appear first
	table.sort(catalogue, function(a, b) return a.price < b.price end)
	return catalogue
end

----------------------------------------------------------------------
-- PROXIMITY PROMPT  → open store on triggering client
----------------------------------------------------------------------
prompt.Triggered:Connect(function(player)
	local catalogue = buildCatalogue()

	-- Annotate each entry with whether this player already owns it
	local userId = player.UserId
	for _, entry in ipairs(catalogue) do
		entry.owned = isOwned(userId, entry.id)
	end

	evtOpen:FireClient(player, catalogue)
end)

----------------------------------------------------------------------
-- BUY HANDLER  (client → server)
----------------------------------------------------------------------
evtBuy.OnServerEvent:Connect(function(player, toolId)
	-- Validate toolId is a string and corresponds to a real tool
	if type(toolId) ~= "string" then return end
	if not toolsFolder or not toolsFolder:FindFirstChild(toolId) then
		evtResult:FireClient(player, false, "That tool doesn't exist.")
		return
	end

	local userId = player.UserId

	-- Already owned?
	if isOwned(userId, toolId) then
		evtResult:FireClient(player, false, "You already own this!")
		-- Give it anyway in case they lost it (e.g. after reset)
		giveTool(player, toolId)
		return
	end

	-- Find the price from the template
	local template = toolsFolder:FindFirstChild(toolId)
	local price    = tonumber(template:GetAttribute("price")) or 0

	-- Check balance
	local balance = getBalance(userId)
	if balance < price then
		evtResult:FireClient(player, false,
			string.format("Not enough money! Need $%g (you have $%g).", price, balance))
		return
	end

	-- Deduct money
	local ok = deductBalance(userId, price)
	if not ok then
		evtResult:FireClient(player, false, "Transaction failed — please try again.")
		return
	end

	-- Record ownership and give the tool
	markOwned(userId, toolId)
	saveOwned(userId)
	giveTool(player, toolId)

	local displayName = template:GetAttribute("name") or toolId
	evtResult:FireClient(player, true,
		string.format("✅ You bought %s for $%g!", displayName, price))

	print(string.format("[ToolStoreServer] %s bought '%s' for $%g", player.Name, toolId, price))
end)

----------------------------------------------------------------------
-- PLAYER LIFECYCLE
----------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	loadOwned(player.UserId)

	-- Give owned tools immediately if character already exists,
	-- and again on every subsequent respawn.
	if player.Character then
		giveAllOwned(player)
	end
	player.CharacterAdded:Connect(function()
		-- Small delay so the Backpack is ready
		task.wait(0.5)
		giveAllOwned(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	saveOwned(player.UserId)
	ownedTools[player.UserId] = nil
end)

-- Handle players already in-game (Studio test / script reload)
for _, player in ipairs(Players:GetPlayers()) do
	loadOwned(player.UserId)
	if player.Character then
		giveAllOwned(player)
	end
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		giveAllOwned(player)
	end)
end

print("[ToolStoreServer] Ready. Watching", toolsFolder and #toolsFolder:GetChildren() or 0, "tools.")
