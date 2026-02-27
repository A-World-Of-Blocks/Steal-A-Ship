--[[
	BrainrotReturnServer.lua  ·  Script → ServerScriptService
	──────────────────────────────────────────────────────────
	When a player who is carrying a STOLEN brainrot takes any damage,
	the brainrot immediately flies back (TweenService glide) to the
	Slot it was originally stolen from and re-deposits itself there.

	"Stolen" = the brainrot has an ObjectValue named "OriginSlot"
	pointing to the Spawn BasePart it was taken from.  This tag is
	written by proximityprompt.lua at pickup time and cleared on a
	legitimate deposit or drop.

	No bat, no tool — damage from anything (fall, player attack, etc.)
	triggers the return.
--]]

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")

----------------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------------
local SLOT_SCALE        = 0.5
local RETURN_TWEEN_TIME = 1.4   -- seconds for the glide animation
local RETURN_TWEEN_INFO = TweenInfo.new(
	RETURN_TWEEN_TIME,
	Enum.EasingStyle.Quad,
	Enum.EasingDirection.Out
)

----------------------------------------------------------------------
-- SHARED REMOTES / BRIDGES
----------------------------------------------------------------------
local moneyRemotes = ReplicatedStorage:WaitForChild("MoneyRemotes", 15)
local carryEvent   = moneyRemotes and moneyRemotes:WaitForChild("CarryBrainrot", 10)
local moneyBridge  = ServerStorage:WaitForChild("MoneyBridge",         15)
local slotChanged  = ServerStorage:WaitForChild("BrainrotSlotChanged", 15)
local islandBridge = ServerStorage:WaitForChild("IslandBridge",        15)

----------------------------------------------------------------------
-- RETURN TRACKING  (prevent double-returns for the same model)
----------------------------------------------------------------------
local returning = {}   -- [brainrotModel] = true

----------------------------------------------------------------------
-- NOTIFY HELPER
----------------------------------------------------------------------
local function notifyPlayer(player, message)
	local notifyRemote = moneyRemotes and moneyRemotes:FindFirstChild("Notify")
	if notifyRemote then
		notifyRemote:FireClient(player, message, Color3.fromRGB(255, 80, 80))
	end
	print(string.format("[BrainrotReturn] %s → %s", player.Name, message))
end

----------------------------------------------------------------------
-- CORE RETURN FUNCTION
-- Detaches the brainrot from the carrier, tweens it back to its
-- original SpawnPart, then re-deposits it as if the player had
-- walked into their own slot.
----------------------------------------------------------------------
local function returnBrainrot(brainrotModel, spawnPart, carrier)
	if returning[brainrotModel] then return end
	returning[brainrotModel] = true

	-- 1. Stop the carrier's client carry loop and remove the weld tag
	local character = carrier and carrier.Character
	if character then
		local tag = character:FindFirstChild("BrainrotWeld")
		if tag then tag:Destroy() end
	end
	if carryEvent and carrier then
		carryEvent:FireClient(carrier, "stop", brainrotModel)
	end

	-- 2. Detach from character → move to workspace for the tween
	brainrotModel.Parent = workspace

	for _, part in ipairs(brainrotModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored   = true
			part.CanCollide = false
			part.CanTouch   = false
		end
	end

	-- 3. Tween PrimaryPart toward the SpawnPart
	local primaryPart = brainrotModel.PrimaryPart
	if primaryPart then
		local tween = TweenService:Create(primaryPart, RETURN_TWEEN_INFO, {
			CFrame = spawnPart.CFrame
		})
		tween:Play()
		tween.Completed:Wait()
	end

	-- 4. Snap exactly into position, scale down, restore physics
	brainrotModel:PivotTo(spawnPart.CFrame)
	brainrotModel:ScaleTo(SLOT_SCALE)

	for _, part in ipairs(brainrotModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored   = true
			part.CanCollide = true
			part.CanTouch   = true
			part.Massless   = false
		end
	end

	brainrotModel.Parent = spawnPart

	-- 5. Clean up stolen tags
	local originSlotTag  = brainrotModel:FindFirstChild("OriginSlot")
	local originOwnerTag = brainrotModel:FindFirstChild("OriginOwner")
	if originSlotTag  then originSlotTag:Destroy()  end
	if originOwnerTag then originOwnerTag:Destroy() end

	-- 6. Re-enable the proximity prompt
	local prompt = brainrotModel:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt then prompt.Enabled = true end

	-- 7. Stop the brainrot from wandering while deposited
	local wander = brainrotModel:FindFirstChild("BrainrotWander")
	if wander then wander.Enabled = false end

	-- 8. Notify money/slot system → re-start income for the island owner
	local slotModel  = spawnPart.Parent     -- Spawn → Slot
	local slotIsland = slotModel and slotModel.Parent  -- Slot → Island

	local dps = 0
	local moneyConfig = brainrotModel:FindFirstChild("MoneyConfig")
	if moneyConfig then
		local dpsVal = moneyConfig:FindFirstChild("DPS")
		dps = dpsVal and dpsVal.Value or 0
	end

	local ownerPlayer = nil
	if islandBridge and slotIsland then
		for _, plr in ipairs(Players:GetPlayers()) do
			if islandBridge:Invoke(plr.UserId) == slotIsland then
				ownerPlayer = plr
				break
			end
		end
	end

	if moneyBridge and ownerPlayer then
		moneyBridge:Invoke("deposit", ownerPlayer.UserId, brainrotModel, dps)
	end
	if slotChanged and ownerPlayer then
		slotChanged:Fire("deposit", ownerPlayer, slotModel, brainrotModel)
	end

	-- 9. Tell the thief their stolen brainrot was returned
	if carrier then
		notifyPlayer(carrier, "💥 You took damage — your stolen brainrot was returned!")
	end

	returning[brainrotModel] = nil
	print(string.format("[BrainrotReturn] Returned '%s' to its slot.", brainrotModel.Name))
end

----------------------------------------------------------------------
-- FIND STOLEN BRAINROT ON A CHARACTER
-- Returns (brainrotModel, spawnPart) or (nil, nil)
----------------------------------------------------------------------
local function findStolenBrainrot(character)
	local weldTag = character:FindFirstChild("BrainrotWeld")
	if not weldTag then return nil, nil end

	-- Find the model by name first
	local brainrotModel = character:FindFirstChild(weldTag.Value)
	-- Fallback: any child Model that has an OriginSlot tag
	if not brainrotModel then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Model") and child:FindFirstChild("OriginSlot") then
				brainrotModel = child
				break
			end
		end
	end
	if not brainrotModel then return nil, nil end

	-- Must have an OriginSlot to qualify as "stolen"
	local originSlotTag = brainrotModel:FindFirstChild("OriginSlot")
	if not originSlotTag or not originSlotTag.Value then return nil, nil end

	-- SpawnPart must still exist in the world
	local spawnPart = originSlotTag.Value
	if not spawnPart or not spawnPart.Parent then return nil, nil end

	return brainrotModel, spawnPart
end

----------------------------------------------------------------------
-- HOOK UP DAMAGE DETECTION PER CHARACTER
----------------------------------------------------------------------
local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end

	humanoid.HealthChanged:Connect(function(newHealth)
		-- Only fire when health DECREASES (ignore healing)
		if newHealth >= humanoid.MaxHealth then return end
		-- Only care while they're still alive
		if newHealth <= 0 then return end

		local brainrotModel, spawnPart = findStolenBrainrot(character)
		if not brainrotModel then return end

		-- Kick off the return asynchronously so HealthChanged returns fast
		task.spawn(returnBrainrot, brainrotModel, spawnPart, player)
	end)
end

----------------------------------------------------------------------
-- CONNECT FOR ALL PLAYERS
----------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end)

-- Handle players already in-game (Studio test / script reload)
for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end
