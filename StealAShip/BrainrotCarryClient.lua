-- LocalScript: BrainrotCarryClient
-- Place in StarterPlayerScripts (or StarterCharacterScripts).
--
-- Listens for the CarryBrainrot RemoteEvent fired by proximityprompt.lua (server).
-- Runs the smooth PivotTo follow loop ENTIRELY ON THE CLIENT so updates happen
-- at the local frame-rate with zero network round-trip latency.
--
-- Also listens for PickupDenied to show a "Not enough money!" toast.
--
-- Protocol:
--   server → client  "start"  brainrotModel  offsetCFrame
--      Begin Heartbeat loop: brainrotModel:PivotTo(torso.CFrame * offsetCFrame)
--   server → client  "stop"   brainrotModel
--      Disconnect the loop for that model.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")

local remotes     = ReplicatedStorage:WaitForChild("MoneyRemotes", 10)
local carryEvent  = remotes and remotes:WaitForChild("CarryBrainrot",  10)
local deniedEvent = remotes and remotes:WaitForChild("PickupDenied",   10)
local dropEvent   = remotes and remotes:WaitForChild("DropBrainrot",   10)

if not carryEvent then
	warn("[BrainrotCarryClient] CarryBrainrot RemoteEvent not found – smooth carry disabled.")
end

----------------------------------------------------------------------
-- CARRY LOOP
----------------------------------------------------------------------
-- keyed by brainrotModel → { conn = RBXScriptConnection, active = bool }
local activeCarries = {}

if carryEvent then
	carryEvent.OnClientEvent:Connect(function(action, brainrotModel, offsetCFrame)
		if action == "start" then
			-- Stop any leftover loop for this model first
			if activeCarries[brainrotModel] then
				activeCarries[brainrotModel].active = false
				activeCarries[brainrotModel].conn:Disconnect()
				activeCarries[brainrotModel] = nil
			end

			local character = localPlayer.Character
			if not character then return end

			local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
			if not torso then return end

			-- Track with a flag so we can stop from the "stop" action without
			-- relying on parent checks (the reparent replication can lag behind
			-- the RemoteEvent, causing an immediate false-positive disconnect).
			local entry = { active = true, conn = nil }
			activeCarries[brainrotModel] = entry

			entry.conn = RunService.Heartbeat:Connect(function()
				-- Stop if explicitly told to stop via "stop" action
				if not entry.active then
					entry.conn:Disconnect()
					activeCarries[brainrotModel] = nil
					return
				end
				-- Stop if torso is gone (character died / reset)
				if not torso.Parent then
					entry.active = false
					entry.conn:Disconnect()
					activeCarries[brainrotModel] = nil
					return
				end
				brainrotModel:PivotTo(torso.CFrame * offsetCFrame)
			end)

			showDropButton()

		elseif action == "stop" then
			if activeCarries[brainrotModel] then
				activeCarries[brainrotModel].active = false
				activeCarries[brainrotModel].conn:Disconnect()
				activeCarries[brainrotModel] = nil
			end
			hideDropButton()
		end
	end)
end

----------------------------------------------------------------------
-- DROP BUTTON UI  ([G] key or on-screen button while carrying)
----------------------------------------------------------------------
local dropGui = Instance.new("ScreenGui")
dropGui.Name           = "DropBrainrotGui"
dropGui.ResetOnSpawn   = false
dropGui.DisplayOrder   = 55
dropGui.IgnoreGuiInset = true
dropGui.Parent         = playerGui

local dropFrame = Instance.new("Frame", dropGui)
dropFrame.Size              = UDim2.new(0, 200, 0, 54)
dropFrame.Position          = UDim2.new(0.5, -100, 1, -110)
dropFrame.BackgroundColor3  = Color3.fromRGB(30, 30, 44)
dropFrame.BackgroundTransparency = 0.1
dropFrame.BorderSizePixel   = 0
dropFrame.Visible           = false
Instance.new("UICorner", dropFrame).CornerRadius = UDim.new(0, 12)
local dropStroke = Instance.new("UIStroke", dropFrame)
dropStroke.Color      = Color3.fromRGB(255, 160, 40)
dropStroke.Thickness  = 2
dropStroke.Transparency = 0.4

local dropBtn = Instance.new("TextButton", dropFrame)
dropBtn.Size                = UDim2.new(1, -16, 0, 36)
dropBtn.Position            = UDim2.new(0, 8, 0.5, -18)
dropBtn.BackgroundColor3    = Color3.fromRGB(180, 90, 20)
dropBtn.TextColor3          = Color3.new(1, 1, 1)
dropBtn.Font                = Enum.Font.GothamBold
dropBtn.TextSize            = 15
dropBtn.Text                = "🔽  Drop  [G]"
dropBtn.BorderSizePixel     = 0
dropBtn.AutoButtonColor     = true
Instance.new("UICorner", dropBtn).CornerRadius = UDim.new(0, 8)

-- Hover tween
dropBtn.MouseEnter:Connect(function()
	TweenService:Create(dropBtn, TweenInfo.new(0.1),
		{ BackgroundColor3 = Color3.fromRGB(220, 120, 40) }):Play()
end)
dropBtn.MouseLeave:Connect(function()
	TweenService:Create(dropBtn, TweenInfo.new(0.1),
		{ BackgroundColor3 = Color3.fromRGB(180, 90, 20) }):Play()
end)

local function showDropButton()
	dropFrame.Visible = true
	dropFrame.Position = UDim2.new(0.5, -100, 1, -110)
	TweenService:Create(dropFrame, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, -100, 1, -130) }):Play()
end

local function hideDropButton()
	TweenService:Create(dropFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.new(0.5, -100, 1, -90) }):Play()
	task.delay(0.22, function() dropFrame.Visible = false end)
end

local function fireDrop()
	if dropEvent then
		dropEvent:FireServer()
	end
end

dropBtn.MouseButton1Click:Connect(fireDrop)

-- [G] keybind
UserInputService.InputBegan:Connect(function(inp, processed)
	if processed then return end
	if inp.KeyCode == Enum.KeyCode.G and dropFrame.Visible then
		fireDrop()
	end
end)

----------------------------------------------------------------------
-- "NOT ENOUGH MONEY" TOAST
-- Server fires PickupDenied(cost, balance) when the player can't afford
-- a first-purchase brainrot.
----------------------------------------------------------------------
local toastGui = Instance.new("ScreenGui")
toastGui.Name           = "DeniedToastGui"
toastGui.ResetOnSpawn   = false
toastGui.DisplayOrder   = 50
toastGui.IgnoreGuiInset = true
toastGui.Parent         = playerGui

local toast = Instance.new("Frame", toastGui)
toast.Size              = UDim2.new(0, 320, 0, 64)
toast.Position          = UDim2.new(0.5, -160, 0, -80)   -- starts above screen
toast.BackgroundColor3  = Color3.fromRGB(120, 20, 20)
toast.BackgroundTransparency = 0.15
toast.BorderSizePixel   = 0
toast.Visible           = false

local tc = Instance.new("UICorner", toast)
tc.CornerRadius = UDim.new(0, 12)

local ts = Instance.new("UIStroke", toast)
ts.Color      = Color3.fromRGB(255, 80, 80)
ts.Thickness  = 2
ts.Transparency = 0.3

local toastLabel = Instance.new("TextLabel", toast)
toastLabel.Size                   = UDim2.fromScale(1, 1)
toastLabel.BackgroundTransparency = 1
toastLabel.TextColor3             = Color3.fromRGB(255, 200, 200)
toastLabel.TextScaled             = true
toastLabel.Font                   = Enum.Font.GothamBold
toastLabel.Text                   = "❌  Not enough money!"

local toastActive = false

local function showToast(cost, balance)
	local needed = cost - balance
	toastLabel.Text = string.format("❌  Need $%g more to buy this!", math.ceil(needed))

	if toastActive then return end
	toastActive   = true
	toast.Visible = true

	-- Slide down into view
	local slideIn = TweenService:Create(toast,
		TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, -160, 0, 20) }
	)
	slideIn:Play()
	slideIn.Completed:Wait()

	task.wait(2.2)

	-- Slide back up and hide
	local slideOut = TweenService:Create(toast,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.new(0.5, -160, 0, -80) }
	)
	slideOut:Play()
	slideOut.Completed:Wait()

	toast.Visible = false
	toastActive   = false
end

if deniedEvent then
	deniedEvent.OnClientEvent:Connect(function(cost, balance)
		showToast(cost, balance)
	end)
end
