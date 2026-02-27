-- LoadingScreen (LocalScript, StarterPlayerScripts)
-- Beautiful animated loading screen for "Steal A Ship For Brainrots".
-- Waits for ContentProvider to finish loading all game assets,
-- drives a real progress bar, then fades out.
-- A "Skip" button appears after SKIP_DELAY seconds for impatient players.

local ContentProvider  = game:GetService("ContentProvider")
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------------
-- CONFIGURATION
----------------------------------------------------------------------
local SKIP_DELAY        = 4     -- seconds before the skip button appears
local FADE_OUT_TIME     = 0.8   -- how long the final fade-out takes (seconds)
local WAVE_SPEED        = 1.4   -- speed of the shimmer/wave animation
local PARTICLE_COUNT    = 22    -- floating background particles

----------------------------------------------------------------------
-- COLOURS
----------------------------------------------------------------------
local C_BG_TOP    = Color3.fromRGB(5,  10, 28)
local C_BG_BOT    = Color3.fromRGB(8,  22, 55)
local C_ACCENT    = Color3.fromRGB(80, 220, 255)
local C_GOLD      = Color3.fromRGB(255, 210, 60)
local C_WHITE     = Color3.fromRGB(255, 255, 255)
local C_DIM       = Color3.fromRGB(120, 160, 200)
local C_BAR_BG    = Color3.fromRGB(15,  30, 65)
local C_BAR_FILL  = Color3.fromRGB(80, 220, 255)
local C_BAR_GLOW  = Color3.fromRGB(150, 240, 255)
local C_SKIP_BG   = Color3.fromRGB(20,  40, 90)
local C_SKIP_TXT  = Color3.fromRGB(160, 200, 240)

----------------------------------------------------------------------
-- ROOT GUI  (IgnoreGuiInset so it covers the full screen incl. topbar)
----------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name              = "LoadingScreen"
screenGui.DisplayOrder      = 999
screenGui.ResetOnSpawn      = false
screenGui.IgnoreGuiInset    = true
screenGui.ZIndexBehavior    = Enum.ZIndexBehavior.Sibling
screenGui.Parent            = playerGui

----------------------------------------------------------------------
-- FULL-SCREEN BACKGROUND (gradient)
----------------------------------------------------------------------
local bg = Instance.new("Frame", screenGui)
bg.Name              = "Background"
bg.Size              = UDim2.fromScale(1, 1)
bg.BackgroundColor3  = C_BG_TOP
bg.BorderSizePixel   = 0
bg.ZIndex            = 1

local gradient = Instance.new("UIGradient", bg)
gradient.Color    = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C_BG_TOP),
	ColorSequenceKeypoint.new(1, C_BG_BOT),
})
gradient.Rotation = 120

----------------------------------------------------------------------
-- FLOATING PARTICLE DOTS  (purely decorative)
----------------------------------------------------------------------
math.randomseed(tick())
local particles = {}
for i = 1, PARTICLE_COUNT do
	local dot = Instance.new("Frame", bg)
	local sz  = math.random(3, 9)
	dot.Size              = UDim2.new(0, sz, 0, sz)
	dot.Position          = UDim2.new(math.random(), 0, math.random(), 0)
	dot.BackgroundColor3  = (math.random() > 0.5) and C_ACCENT or C_GOLD
	dot.BackgroundTransparency = math.random() * 0.5 + 0.3
	dot.BorderSizePixel   = 0
	dot.ZIndex            = 2
	local dc = Instance.new("UICorner", dot)
	dc.CornerRadius = UDim.new(1, 0)

	particles[i] = {
		frame  = dot,
		speed  = math.random() * 0.04 + 0.01,
		drift  = (math.random() - 0.5) * 0.015,
		startY = math.random(),
	}
end

----------------------------------------------------------------------
-- SHIP SILHOUETTE  (Unicode art centred on screen)
----------------------------------------------------------------------
local shipLabel = Instance.new("TextLabel", bg)
shipLabel.Size                   = UDim2.new(0, 500, 0, 120)
shipLabel.Position               = UDim2.new(0.5, -250, 0.12, 0)
shipLabel.BackgroundTransparency = 1
shipLabel.Text                   = "⛵"
shipLabel.TextScaled             = true
shipLabel.Font                   = Enum.Font.GothamBold
shipLabel.TextColor3             = C_ACCENT
shipLabel.TextTransparency       = 0.1
shipLabel.ZIndex                 = 3

----------------------------------------------------------------------
-- GAME TITLE
----------------------------------------------------------------------
local titleLabel = Instance.new("TextLabel", bg)
titleLabel.Size                   = UDim2.new(0, 700, 0, 80)
titleLabel.Position               = UDim2.new(0.5, -350, 0.32, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text                   = "STEAL A SHIP"
titleLabel.TextScaled             = true
titleLabel.Font                   = Enum.Font.GothamBlack
titleLabel.TextColor3             = C_WHITE
titleLabel.TextStrokeColor3       = C_ACCENT
titleLabel.TextStrokeTransparency = 0.3
titleLabel.ZIndex                 = 3

local subLabel = Instance.new("TextLabel", bg)
subLabel.Size                   = UDim2.new(0, 700, 0, 36)
subLabel.Position               = UDim2.new(0.5, -350, 0.32 + 0.11, 0)
subLabel.BackgroundTransparency = 1
subLabel.Text                   = "FOR BRAINROTS"
subLabel.TextScaled             = true
subLabel.Font                   = Enum.Font.GothamBold
subLabel.TextColor3             = C_GOLD
subLabel.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
subLabel.TextStrokeTransparency = 0.5
subLabel.ZIndex                 = 3

----------------------------------------------------------------------
-- PROGRESS BAR CONTAINER
----------------------------------------------------------------------
local barContainer = Instance.new("Frame", bg)
barContainer.Size              = UDim2.new(0, 560, 0, 22)
barContainer.Position          = UDim2.new(0.5, -280, 0.72, 0)
barContainer.BackgroundColor3  = C_BAR_BG
barContainer.BorderSizePixel   = 0
barContainer.ZIndex            = 3

local barCorner = Instance.new("UICorner", barContainer)
barCorner.CornerRadius = UDim.new(1, 0)

local barStroke = Instance.new("UIStroke", barContainer)
barStroke.Color       = C_ACCENT
barStroke.Thickness   = 1.5
barStroke.Transparency = 0.5

-- Fill bar
local barFill = Instance.new("Frame", barContainer)
barFill.Name             = "Fill"
barFill.Size             = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = C_BAR_FILL
barFill.BorderSizePixel  = 0
barFill.ZIndex           = 4

local fillCorner = Instance.new("UICorner", barFill)
fillCorner.CornerRadius = UDim.new(1, 0)

local fillGradient = Instance.new("UIGradient", barFill)
fillGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0,   C_BAR_FILL),
	ColorSequenceKeypoint.new(0.7, C_BAR_FILL),
	ColorSequenceKeypoint.new(1,   C_BAR_GLOW),
})

-- Shimmer overlay on bar fill
local shimmer = Instance.new("Frame", barFill)
shimmer.Size              = UDim2.new(0.35, 0, 1, 0)
shimmer.Position          = UDim2.new(-0.35, 0, 0, 0)
shimmer.BackgroundColor3  = Color3.fromRGB(255, 255, 255)
shimmer.BackgroundTransparency = 0.75
shimmer.BorderSizePixel   = 0
shimmer.ZIndex            = 5
shimmer.ClipsDescendants  = false

local shimCorner = Instance.new("UICorner", shimmer)
shimCorner.CornerRadius = UDim.new(1, 0)

----------------------------------------------------------------------
-- PERCENTAGE LABEL  (sits above the bar)
----------------------------------------------------------------------
local pctLabel = Instance.new("TextLabel", bg)
pctLabel.Size                   = UDim2.new(0, 560, 0, 24)
pctLabel.Position               = UDim2.new(0.5, -280, 0.72, -28)
pctLabel.BackgroundTransparency = 1
pctLabel.Text                   = "0%"
pctLabel.TextScaled             = true
pctLabel.Font                   = Enum.Font.GothamBold
pctLabel.TextColor3             = C_ACCENT
pctLabel.TextXAlignment         = Enum.TextXAlignment.Right
pctLabel.ZIndex                 = 3

----------------------------------------------------------------------
-- STATUS LABEL  (e.g. "Loading assets…")
----------------------------------------------------------------------
local statusLabel = Instance.new("TextLabel", bg)
statusLabel.Size                   = UDim2.new(0, 560, 0, 28)
statusLabel.Position               = UDim2.new(0.5, -280, 0.72, 28)
statusLabel.BackgroundTransparency = 1
statusLabel.Text                   = "Loading assets…"
statusLabel.TextScaled             = true
statusLabel.Font                   = Enum.Font.Gotham
statusLabel.TextColor3             = C_DIM
statusLabel.TextXAlignment         = Enum.TextXAlignment.Left
statusLabel.ZIndex                 = 3

----------------------------------------------------------------------
-- SKIP BUTTON  (appears after SKIP_DELAY seconds)
----------------------------------------------------------------------
local skipBtn = Instance.new("TextButton", bg)
skipBtn.Size              = UDim2.new(0, 140, 0, 40)
skipBtn.Position          = UDim2.new(0.5, -70, 0.88, 0)
skipBtn.BackgroundColor3  = C_SKIP_BG
skipBtn.BackgroundTransparency = 0.3
skipBtn.BorderSizePixel   = 0
skipBtn.Text              = "Skip  ›"
skipBtn.TextScaled        = true
skipBtn.Font              = Enum.Font.GothamBold
skipBtn.TextColor3        = C_SKIP_TXT
skipBtn.AutoButtonColor   = false
skipBtn.Visible           = false
skipBtn.ZIndex            = 6

local skipCorner = Instance.new("UICorner", skipBtn)
skipCorner.CornerRadius = UDim.new(0, 10)

local skipStroke = Instance.new("UIStroke", skipBtn)
skipStroke.Color       = C_ACCENT
skipStroke.Thickness   = 1.5
skipStroke.Transparency = 0.6

skipBtn.MouseEnter:Connect(function()
	skipBtn.BackgroundTransparency = 0.05
	skipStroke.Transparency = 0.1
end)
skipBtn.MouseLeave:Connect(function()
	skipBtn.BackgroundTransparency = 0.3
	skipStroke.Transparency = 0.6
end)

----------------------------------------------------------------------
-- BOTTOM TAGLINE
----------------------------------------------------------------------
local tagLabel = Instance.new("TextLabel", bg)
tagLabel.Size                   = UDim2.new(0, 400, 0, 24)
tagLabel.Position               = UDim2.new(0.5, -200, 0.94, 0)
tagLabel.BackgroundTransparency = 1
tagLabel.Text                   = "steal ships · collect brainrots · get rich"
tagLabel.TextScaled             = true
tagLabel.Font                   = Enum.Font.Gotham
tagLabel.TextColor3             = Color3.fromRGB(60, 90, 130)
tagLabel.ZIndex                 = 3

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------
local dismissed = false

local function dismiss()
	if dismissed then return end
	dismissed = true

	-- Fade the whole screen to transparent then destroy
	local fadeInfo = TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeTween = TweenService:Create(bg, fadeInfo, { BackgroundTransparency = 1 })

	-- Fade child labels / frames
	local function fadeChild(obj, prop, target)
		TweenService:Create(obj, fadeInfo, { [prop] = target }):Play()
	end

	for _, child in ipairs(bg:GetDescendants()) do
		if child:IsA("TextLabel") or child:IsA("TextButton") then
			fadeChild(child, "TextTransparency", 1)
			fadeChild(child, "BackgroundTransparency", 1)
		elseif child:IsA("Frame") then
			fadeChild(child, "BackgroundTransparency", 1)
		elseif child:IsA("UIStroke") then
			fadeChild(child, "Transparency", 1)
		end
	end

	fadeTween:Play()
	fadeTween.Completed:Wait()
	screenGui:Destroy()
end

----------------------------------------------------------------------
-- ASSET LOADING
----------------------------------------------------------------------
-- Collect every instance in the game that ContentProvider might need
local function getAllInstances()
	local list = {}
	for _, obj in ipairs(game:GetDescendants()) do
		list[#list + 1] = obj
	end
	return list
end

local loadingDone = false
local progress    = 0   -- 0 → 1

-- Run loading in a background thread so we can animate simultaneously
task.spawn(function()
	local instances = getAllInstances()
	local total     = #instances

	if total == 0 then
		progress    = 1
		loadingDone = true
		return
	end

	local loaded = 0
	ContentProvider:PreloadAsync(instances, function(_assetId, _status)
		loaded   = loaded + 1
		progress = loaded / total
	end)

	progress    = 1
	loadingDone = true
end)

-- Show skip button after delay
task.delay(SKIP_DELAY, function()
	if not dismissed then
		skipBtn.Visible = true
		-- Fade in
		skipBtn.BackgroundTransparency = 1
		TweenService:Create(skipBtn, TweenInfo.new(0.4), { BackgroundTransparency = 0.3 }):Play()
	end
end)

skipBtn.Activated:Connect(dismiss)

----------------------------------------------------------------------
-- ANIMATION LOOP
----------------------------------------------------------------------
-- Title "breathe" tween
TweenService:Create(shipLabel,
	TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ Position = UDim2.new(0.5, -250, 0.12 + 0.012, 0) }
):Play()

-- Displayed progress (smoothly interpolates toward real progress)
local displayedProgress = 0
local shimmerX          = -0.35
local lastStatusUpdate  = ""

RunService.Heartbeat:Connect(function(dt)
	if dismissed then return end

	-- Smooth the bar toward real progress
	displayedProgress = displayedProgress + (progress - displayedProgress) * math.min(dt * 4, 1)
	local pct = math.clamp(displayedProgress, 0, 1)

	-- Update bar fill width
	barFill.Size = UDim2.new(pct, 0, 1, 0)

	-- Update percentage label
	pctLabel.Text = string.format("%d%%", math.floor(pct * 100))

	-- Shimmer sweep across the fill
	if pct > 0.01 then
		shimmerX = shimmerX + dt * WAVE_SPEED
		if shimmerX > 1.35 then shimmerX = -0.35 end
		shimmer.Position = UDim2.new(shimmerX, 0, 0, 0)
	end

	-- Status text
	local statusText
	if pct < 0.25 then
		statusText = "Loading world…"
	elseif pct < 0.55 then
		statusText = "Loading ships & islands…"
	elseif pct < 0.80 then
		statusText = "Loading brainrots…"
	elseif pct < 1 then
		statusText = "Almost ready…"
	else
		statusText = "Setting sail! 🚢"
	end
	if statusText ~= lastStatusUpdate then
		statusLabel.Text  = statusText
		lastStatusUpdate  = statusText
	end

	-- Float particles upward
	for _, p in ipairs(particles) do
		local pos = p.frame.Position
		local newY = pos.Y.Scale - p.speed * dt
		local newX = pos.X.Scale + p.drift * dt
		if newY < -0.05 then
			newY = 1.05
			newX = math.random()
		end
		p.frame.Position = UDim2.new(newX, 0, newY, 0)
	end

	-- Dismiss automatically once fully loaded
	if loadingDone and pct >= 0.999 then
		task.wait(0.3)   -- brief pause at 100% so the player sees it
		dismiss()
	end
end)
