-- AdminServer (Script, ServerScriptService)
-- Handles all privileged admin commands fired from AdminClient.lua.
-- ► Add Roblox user IDs to ADMINS below.

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerStorage      = game:GetService("ServerStorage")
local Lighting           = game:GetService("Lighting")
local MessagingService   = game:GetService("MessagingService")

-- Topic used for all cross-server admin broadcasts
local GLOBAL_TOPIC = "AdminGlobal_v1"

----------------------------------------------------------------------
-- ► ADMIN LIST  (Roblox UserId numbers)
----------------------------------------------------------------------
local ADMINS = {
	1796242043,   -- replace with your UserId
	825790015
}

-- Temporary admins: userId → true  (cleared when player leaves)
local tempAdmins = {}

local function isAdmin(userId)
	if tempAdmins[userId] then return true end
	for _, id in ipairs(ADMINS) do
		if id == userId then return true end
	end
	return false
end

local function isPermanentAdmin(userId)
	for _, id in ipairs(ADMINS) do
		if id == userId then return true end
	end
	return false
end

-- Clean up temp admin when player leaves
Players.PlayerRemoving:Connect(function(player)
	tempAdmins[player.UserId] = nil
end)

----------------------------------------------------------------------
-- SHARED OBJECTS
----------------------------------------------------------------------
local moneyBridge    = ServerStorage:WaitForChild("MoneyBridge",  30)
local brainrotFolder = ReplicatedStorage:WaitForChild("Brainrots", 30)

local function getOrCreate(parent, class, name)
	local e = parent:FindFirstChild(name)
	if e then return e end
	local obj = Instance.new(class); obj.Name = name; obj.Parent = parent
	return obj
end

local remotes      = getOrCreate(ReplicatedStorage, "Folder",         "MoneyRemotes")
local adminRemote  = getOrCreate(remotes,           "RemoteFunction",  "AdminCommand")
local adminEvent   = getOrCreate(remotes,           "RemoteEvent",     "AdminBroadcast")

----------------------------------------------------------------------
-- CROSS-SERVER MESSAGING  (MessagingService)
-- Every server subscribes to GLOBAL_TOPIC.
-- When a message arrives it is executed locally in this server.
-- Supported message types:
--   { type = "spawnBrainrot", name = string, x = n, y = n, z = n }
--   { type = "announce",      msg  = string }
----------------------------------------------------------------------
task.spawn(function()
	local ok, err = pcall(function()
		MessagingService:SubscribeAsync(GLOBAL_TOPIC, function(message)
			local data = message.Data
			if type(data) ~= "table" then return end

			if data.type == "spawnBrainrot" then
				-- Spawn at a random spawner in this server (position from sender
				-- would be in a different server so we pick a local one)
				local spawnPos
				for _, obj in ipairs(workspace:GetDescendants()) do
					if obj:IsA("BasePart") and obj.Name == "Spawner" then
						spawnPos = obj.Position + Vector3.new(0, 5, 0)
						break
					end
				end
				spawnPos = spawnPos or Vector3.new(0, 20, 0)
				pcall(spawnBrainrotAt, data.name, spawnPos)
				adminEvent:FireAllClients("announce",
					string.format("🌐 Global spawn: %s appeared in all servers!", data.name),
					Color3.fromRGB(80, 220, 255))

			elseif data.type == "announce" then
				adminEvent:FireAllClients("announce", data.msg, Color3.fromRGB(255, 210, 60))
			end
		end)
	end)
	if not ok then
		warn("[AdminServer] MessagingService subscribe failed:", err)
	end
end)

-- Helper: publish a message to every server including this one
local function publishGlobal(data)
	local ok, err = pcall(function()
		MessagingService:PublishAsync(GLOBAL_TOPIC, data)
	end)
	if not ok then
		warn("[AdminServer] MessagingService publish failed:", err)
		return false
	end
	return true
end

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------
local function anchorModel(model)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored   = true
			p.CanCollide = true
			p.Massless   = false
		end
	end
end

local function formatMoney(n)
	if n >= 1e6 then return string.format("%.1fM", n/1e6) end
	if n >= 1e3 then return string.format("%.1fK", n/1e3) end
	return tostring(n)
end

-- Mirror of SpawnScript's readDPSFromTemplate / injection logic
local RANDOM_DPS_MIN = 5
local RANDOM_DPS_MAX = 35

local function readDPSFromTemplate(model)
	local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
	local cfg = prompt and prompt:FindFirstChild("MoneyConfig")
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

local function spawnBrainrotAt(name, position)
	local template = brainrotFolder:FindFirstChild(name)
	if not template then return false, "Template not found: " .. name end

	local clone = template:Clone()

	-- Snap to ground: cast downward from 50 studs above the target position,
	-- matching the same approach BrainrotWander uses for its initial height check.
	local rcParams = RaycastParams.new()
	rcParams.FilterDescendantsInstances = {clone}
	rcParams.FilterType = Enum.RaycastFilterType.Exclude
	rcParams.IgnoreWater = false
	local castOrigin = Vector3.new(position.X, position.Y + 50, position.Z)
	local groundHit = workspace:Raycast(castOrigin, Vector3.new(0, -100, 0), rcParams)
	local spawnY = groundHit and (groundHit.Position.Y + 2) or position.Y
	local spawnCFrame = CFrame.new(position.X, spawnY, position.Z)

	clone:PivotTo(spawnCFrame)
	clone.Parent = workspace
	anchorModel(clone)

	-- Inject MoneyConfig for brainrots that don't have one (same as SpawnScript)
	if readDPSFromTemplate(clone) == nil then
		local randomDPS = math.random(RANDOM_DPS_MIN, RANDOM_DPS_MAX)
		local prompt = clone:FindFirstChildWhichIsA("ProximityPrompt", true)
		local cfg = Instance.new("ModuleScript")
		cfg.Name   = "MoneyConfig"
		cfg.Source = string.format("return { DollarsPerSecond = %d }", randomDPS)
		cfg.Parent = prompt or clone
	end

	-- Wander script (same as SpawnScript)
	local scripts = ReplicatedStorage:FindFirstChild("Scripts")
	local wanderSrc = scripts and scripts:FindFirstChild("BrainrotWander")
	if wanderSrc then wanderSrc:Clone().Parent = clone end

	-- Mark as free to pick up immediately
	local tag = clone:FindFirstChild("HasBeenPurchased") or Instance.new("BoolValue")
	tag.Name   = "HasBeenPurchased"
	tag.Value  = true
	tag.Parent = clone

	return true, clone
end

local function giveMoney(userId, amount)
	if not moneyBridge then return false end
	local ok = pcall(function()
		moneyBridge:Invoke("addMoney", userId, amount)
	end)
	return ok
end

----------------------------------------------------------------------
-- COMMAND HANDLER
----------------------------------------------------------------------
adminRemote.OnServerInvoke = function(player, cmd, ...)
	if not isAdmin(player.UserId) then
		return { success = false, message = "Not an admin." }
	end

	local args = { ... }

	-- ── CHECK ADMIN ─────────────────────────────────────────────────
	if cmd == "isAdmin" then
		return { success = true, data = true }

		-- ── GET LISTS ───────────────────────────────────────────────────
	elseif cmd == "getPlayers" then
		local list = {}
		for _, p in ipairs(Players:GetPlayers()) do
			table.insert(list, p.Name)
		end
		return { success = true, data = list }

	elseif cmd == "getBrainrots" then
		local list = {}
		for _, t in ipairs(brainrotFolder:GetChildren()) do
			table.insert(list, t.Name)
		end
		table.sort(list)
		return { success = true, data = list }

		-- ── SPAWN BRAINROT ───────────────────────────────────────────────
		-- args[1] = brainrotName, args[2] = playerName (spawn above them) or nil
	elseif cmd == "spawnBrainrot" then
		local name       = args[1]
		local targetName = args[2]
		local spawnPos

		if targetName and targetName ~= "" then
			local target = Players:FindFirstChild(targetName)
			if target and target.Character then
				local root = target.Character:FindFirstChild("HumanoidRootPart")
				if root then spawnPos = root.Position + Vector3.new(0, 10, 0) end
			end
		end

		if not spawnPos then
			for _, obj in ipairs(workspace:GetDescendants()) do
				if obj:IsA("BasePart") and obj.Name == "Spawner" then
					spawnPos = obj.Position + Vector3.new(0, 5, 0)
					break
				end
			end
		end

		spawnPos = spawnPos or Vector3.new(0, 20, 0)

		local ok, result = spawnBrainrotAt(name, spawnPos)
		if ok then
			adminEvent:FireAllClients("announce",
				string.format("🎉 %s spawned a %s!", player.Name, name),
				Color3.fromRGB(80, 220, 255))
			return { success = true, message = "Spawned " .. name }
		else
			return { success = false, message = result }
		end

		-- ── GIVE MONEY ───────────────────────────────────────────────────
		-- args[1] = playerName or "everyone", args[2] = amount
	elseif cmd == "giveMoney" then
		local targetName = args[1]
		local amount     = tonumber(args[2]) or 0
		if amount <= 0 then return { success = false, message = "Amount must be > 0" } end

		if targetName == "everyone" then
			for _, p in ipairs(Players:GetPlayers()) do
				giveMoney(p.UserId, amount)
			end
			adminEvent:FireAllClients("announce",
				string.format("💰 %s gave everyone $%s!", player.Name, formatMoney(amount)),
				Color3.fromRGB(80, 255, 130))
			return { success = true, message = "Gave $" .. amount .. " to everyone" }
		else
			local target = Players:FindFirstChild(targetName)
			if not target then return { success = false, message = "Player not found" } end
			giveMoney(target.UserId, amount)
			adminEvent:FireAllClients("announce",
				string.format("💰 %s gave %s $%s!", player.Name, target.Name, formatMoney(amount)),
				Color3.fromRGB(80, 255, 130))
			return { success = true, message = "Gave $" .. amount .. " to " .. target.Name }
		end

		-- ── TAKE MONEY ───────────────────────────────────────────────────
		-- args[1] = playerName or "everyone", args[2] = amount
	elseif cmd == "takeMoney" then
		local targetName = args[1]
		local amount     = tonumber(args[2]) or 0
		if amount <= 0 then return { success = false, message = "Amount must be > 0" } end

		local function doTake(p)
			if not moneyBridge then return end
			pcall(function() moneyBridge:Invoke("takeMoney", p.UserId, amount) end)
		end

		if targetName == "everyone" then
			for _, p in ipairs(Players:GetPlayers()) do doTake(p) end
			adminEvent:FireAllClients("announce",
				string.format("💸 %s removed $%s from everyone!", player.Name, formatMoney(amount)),
				Color3.fromRGB(220, 120, 40))
			return { success = true, message = "Took $" .. formatMoney(amount) .. " from everyone" }
		else
			local target = Players:FindFirstChild(targetName)
			if not target then return { success = false, message = "Player not found" } end
			doTake(target)
			return { success = true, message = "Took $" .. formatMoney(amount) .. " from " .. target.Name }
		end

		-- ── RESET MONEY ──────────────────────────────────────────────────
		-- args[1] = playerName or "everyone"
	elseif cmd == "resetMoney" then
		local targetName = args[1]

		local function doReset(p)
			if not moneyBridge then return end
			pcall(function() moneyBridge:Invoke("resetMoney", p.UserId) end)
		end

		if targetName == "everyone" then
			for _, p in ipairs(Players:GetPlayers()) do doReset(p) end
			adminEvent:FireAllClients("announce",
				string.format("🗑️ %s reset everyone's money to $0!", player.Name),
				Color3.fromRGB(220, 60, 60))
			return { success = true, message = "Reset money for everyone" }
		else
			local target = Players:FindFirstChild(targetName)
			if not target then return { success = false, message = "Player not found" } end
			doReset(target)
			return { success = true, message = "Reset money for " .. target.Name }
		end

		-- ── SET TIME ─────────────────────────────────────────────────────
		-- args[1] = hours (0-24)
	elseif cmd == "setTime" then
		local hours = tonumber(args[1])
		if not hours then return { success = false, message = "Invalid time" } end
		hours = math.clamp(hours, 0, 24)
		Lighting.ClockTime = hours
		adminEvent:FireAllClients("announce",
			string.format("🕐 %s set the time to %02d:00", player.Name, math.floor(hours)),
			Color3.fromRGB(255, 210, 60))
		return { success = true, message = "Time set to " .. hours }

		-- ── KICK ─────────────────────────────────────────────────────────
		-- args[1] = playerName, args[2] = reason (optional)
	elseif cmd == "kick" then
		local targetName = args[1]
		local reason     = args[2] or "Kicked by an admin."
		if targetName == player.Name then return { success = false, message = "Cannot kick yourself" } end
		local target = Players:FindFirstChild(targetName)
		if not target then return { success = false, message = "Player not found" } end
		if isAdmin(target.UserId) then return { success = false, message = "Cannot kick an admin" } end
		target:Kick(reason)
		return { success = true, message = "Kicked " .. targetName }

		-- ── KILL ─────────────────────────────────────────────────────────
		-- args[1] = playerName or "everyone"
	elseif cmd == "kill" then
		local targetName = args[1]
		local function killPlayer(p)
			if p.Character then
				local hum = p.Character:FindFirstChildWhichIsA("Humanoid")
				if hum then hum.Health = 0 end
			end
		end
		if targetName == "everyone" then
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= player then killPlayer(p) end
			end
			adminEvent:FireAllClients("announce",
				string.format("💀 %s killed everyone!", player.Name),
				Color3.fromRGB(220, 60, 60))
		else
			local target = Players:FindFirstChild(targetName)
			if not target then return { success = false, message = "Player not found" } end
			killPlayer(target)
		end
		return { success = true, message = "Killed " .. targetName }

		-- ── FREEZE / UNFREEZE ────────────────────────────────────────────
		-- args[1] = playerName or "everyone", args[2] = true/false
	elseif cmd == "freeze" then
		local targetName = args[1]
		local freeze     = args[2]
		local function setFreeze(p, state)
			if p.Character then
				for _, part in ipairs(p.Character:GetDescendants()) do
					if part:IsA("BasePart") then part.Anchored = state end
				end
			end
		end
		if targetName == "everyone" then
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= player then setFreeze(p, freeze) end
			end
		else
			local target = Players:FindFirstChild(targetName)
			if not target then return { success = false, message = "Player not found" } end
			setFreeze(target, freeze)
		end
		local verb = freeze and "🧊 froze" or "🔥 unfroze"
		adminEvent:FireAllClients("announce",
			string.format("%s %s %s!", player.Name, verb, targetName),
			Color3.fromRGB(80, 200, 255))
		return { success = true, message = (freeze and "Froze " or "Unfroze ") .. targetName }

		-- ── GOD MODE ─────────────────────────────────────────────────────
		-- args[1] = playerName, args[2] = true/false
	elseif cmd == "godMode" then
		local targetName = args[1]
		local enable     = args[2]
		local target = Players:FindFirstChild(targetName)
		if not target then return { success = false, message = "Player not found" } end
		if target.Character then
			local hum = target.Character:FindFirstChildWhichIsA("Humanoid")
			if hum then
				hum.MaxHealth = enable and math.huge or 100
				hum.Health    = enable and math.huge or 100
			end
		end
		local label = enable and ("⭐ gave god mode to " .. targetName)
			or ("Removed god mode from " .. targetName)
		return { success = true, message = label }

		-- ── TELEPORT TO ──────────────────────────────────────────────────
		-- args[1] = playerName  (admin teleports to them)
	elseif cmd == "teleport" then
		local target = Players:FindFirstChild(args[1])
		if not target or not target.Character then
			return { success = false, message = "Player/character not found" }
		end
		if not player.Character then return { success = false, message = "Your character not ready" } end
		local tRoot = target.Character:FindFirstChild("HumanoidRootPart")
		local mRoot = player.Character:FindFirstChild("HumanoidRootPart")
		if tRoot and mRoot then
			mRoot.CFrame = tRoot.CFrame + Vector3.new(3, 0, 0)
		end
		return { success = true, message = "Teleported to " .. args[1] }

		-- ── BRING ────────────────────────────────────────────────────────
		-- args[1] = playerName  (pull them to admin)
	elseif cmd == "bring" then
		local target = Players:FindFirstChild(args[1])
		if not target or not target.Character then
			return { success = false, message = "Player/character not found" }
		end
		if not player.Character then return { success = false, message = "Your character not ready" } end
		local mRoot = player.Character:FindFirstChild("HumanoidRootPart")
		local tRoot = target.Character:FindFirstChild("HumanoidRootPart")
		if mRoot and tRoot then
			tRoot.CFrame = mRoot.CFrame + Vector3.new(3, 0, 0)
		end
		return { success = true, message = "Brought " .. args[1] }

		-- ── SPEED ────────────────────────────────────────────────────────
		-- args[1] = playerName or "everyone", args[2] = walkspeed number
	elseif cmd == "speed" then
		local targetName = args[1]
		local spd        = tonumber(args[2]) or 16
		local function setSpeed(p)
			if p.Character then
				local hum = p.Character:FindFirstChildWhichIsA("Humanoid")
				if hum then hum.WalkSpeed = spd end
			end
		end
		if targetName == "everyone" then
			for _, p in ipairs(Players:GetPlayers()) do setSpeed(p) end
		else
			local target = Players:FindFirstChild(targetName)
			if not target then return { success = false, message = "Player not found" } end
			setSpeed(target)
		end
		return { success = true, message = string.format("Set speed %s -> %g", targetName, spd) }

		-- ── CLEAR WORLD BRAINROTS ────────────────────────────────────────
	elseif cmd == "clearBrainrots" then
		local count = 0
		for _, obj in ipairs(workspace:GetDescendants()) do
			if obj:IsA("Model") and brainrotFolder:FindFirstChild(obj.Name) then
				local inSlot = false
				local p = obj.Parent
				while p and p ~= workspace do
					if p.Name == "Spawn" then inSlot = true; break end
					p = p.Parent
				end
				if not inSlot then obj:Destroy(); count += 1 end
			end
		end
		return { success = true, message = "Cleared " .. count .. " world brainrots" }

		-- ── SERVER ANNOUNCE ──────────────────────────────────────────────
		-- args[1] = message string
	elseif cmd == "announce" then
		local msg = tostring(args[1] or "")
		adminEvent:FireAllClients("announce", "📢 [ADMIN] " .. msg, Color3.fromRGB(255, 210, 60))
		return { success = true, message = "Announced" }

	-- ── GRANT TEMP ADMIN ─────────────────────────────────────────────
	-- args[1] = target player name
	elseif cmd == "grantAdmin" then
		-- Only permanent admins can grant admin
		if not isPermanentAdmin(player.UserId) then
			return { success = false, message = "Only permanent admins can grant admin" }
		end
		local targetName = args[1]
		local target = Players:FindFirstChild(targetName)
		if not target then return { success = false, message = "Player not found" } end
		if isAdmin(target.UserId) then
			return { success = false, message = target.Name .. " is already an admin" }
		end
		tempAdmins[target.UserId] = true
		adminEvent:FireAllClients("announce",
			string.format("⚡ %s has been granted temporary admin by %s!", target.Name, player.Name),
			Color3.fromRGB(255, 200, 40))
		-- Tell the newly-granted client to reload their admin state
		adminEvent:FireClient(target, "adminGranted")
		return { success = true, message = "Granted temp admin to " .. target.Name }

	-- ── REVOKE TEMP ADMIN ─────────────────────────────────────────────
	-- args[1] = target player name
	elseif cmd == "revokeAdmin" then
		if not isPermanentAdmin(player.UserId) then
			return { success = false, message = "Only permanent admins can revoke admin" }
		end
		local targetName = args[1]
		local target = Players:FindFirstChild(targetName)
		if not target then return { success = false, message = "Player not found" } end
		if isPermanentAdmin(target.UserId) then
			return { success = false, message = "Cannot revoke a permanent admin" }
		end
		if not tempAdmins[target.UserId] then
			return { success = false, message = target.Name .. " is not a temp admin" }
		end
		tempAdmins[target.UserId] = nil
		adminEvent:FireAllClients("announce",
			string.format("🚫 %s's temporary admin has been revoked by %s.", target.Name, player.Name),
			Color3.fromRGB(220, 80, 80))
		adminEvent:FireClient(target, "adminRevoked")
		return { success = true, message = "Revoked temp admin from " .. target.Name }

	-- ── GET TEMP ADMIN LIST ───────────────────────────────────────────
	elseif cmd == "getTempAdmins" then
		local list = {}
		for userId, _ in pairs(tempAdmins) do
			local p = Players:GetPlayerByUserId(userId)
			if p then table.insert(list, p.Name) end
		end
		return { success = true, data = list }

	-- ── GLOBAL SPAWN (all servers) ────────────────────────────────────
	-- args[1] = brainrotName
	elseif cmd == "spawnBrainrotGlobal" then
		local name = args[1]
		if not brainrotFolder:FindFirstChild(name) then
			return { success = false, message = "Template not found: " .. tostring(name) }
		end
		local ok = publishGlobal({ type = "spawnBrainrot", name = name })
		if ok then
			return { success = true, message = "🌐 Spawning " .. name .. " in all servers!" }
		else
			return { success = false, message = "MessagingService unavailable (Studio?)" }
		end

	-- ── GLOBAL ANNOUNCE (all servers) ────────────────────────────────
	-- args[1] = message string
	elseif cmd == "announceGlobal" then
		local msg = tostring(args[1] or "")
		if msg == "" then return { success = false, message = "Message is empty" } end
		local fullMsg = "📢 [GLOBAL ADMIN] " .. msg
		local ok = publishGlobal({ type = "announce", msg = fullMsg })
		if ok then
			return { success = true, message = "Sent to all servers!" }
		else
			return { success = false, message = "MessagingService unavailable (Studio?)" }
		end

	-- ── INVISIBLE ────────────────────────────────────────────────────
	-- args[1] = playerName, args[2] = true/false
	-- Makes the player's character fully transparent to others.
	-- Uses server-side Transparency so all clients see the effect.
	elseif cmd == "invisible" then
		local targetName = args[1]
		local enable     = args[2]
		local target     = Players:FindFirstChild(targetName)
		if not target then return { success = false, message = "Player not found" } end
		if not target.Character then return { success = false, message = "Character not loaded" } end
		for _, part in ipairs(target.Character:GetDescendants()) do
			if part:IsA("BasePart") or part:IsA("Decal") then
				if enable then
					-- Store original transparency as an attribute before hiding
					if part:IsA("BasePart") and not part:GetAttribute("OrigTransparency") then
						part:SetAttribute("OrigTransparency", part.Transparency)
					end
					part.Transparency = 1
				else
					-- Restore original transparency
					if part:IsA("BasePart") then
						local orig = part:GetAttribute("OrigTransparency")
						part.Transparency = (orig ~= nil) and orig or 0
					else
						part.Transparency = 0
					end
				end
			end
		end
		-- Also hide the name/health bar
		local humanoid = target.Character:FindFirstChildWhichIsA("Humanoid")
		if humanoid then
			humanoid.DisplayDistanceType = enable
				and Enum.HumanoidDisplayDistanceType.None
				or  Enum.HumanoidDisplayDistanceType.Viewer
		end
		local label = enable and ("👻 " .. targetName .. " is now invisible")
			or (targetName .. " is now visible")
		return { success = true, message = label }

	-- ── TRIGGER HIGH SPAWN ────────────────────────────────────────────
	elseif cmd == "triggerHighSpawn" then
		local triggerEvent = ServerStorage:FindFirstChild("TriggerHighSpawn")
		if not triggerEvent then
			return { success = false, message = "TriggerHighSpawn event not found — is HighSpawnScript running?" }
		end
		triggerEvent:Fire()
		adminEvent:FireAllClients("announce",
			string.format("🌋 %s triggered a rare spawn wave!", player.Name),
			Color3.fromRGB(180, 60, 255))
		return { success = true, message = "🌋 Rare spawn wave triggered!" }
	end

	return { success = false, message = "Unknown command: " .. tostring(cmd) }
end

print(string.format("[AdminServer] Ready. %d admin(s) registered.", #ADMINS))