-- BoostStoreClient (LocalScript, StarterPlayerScripts)
-- Toggle button bottom-left opens the Power-Up Store.
-- LIGHT THEME  |  Wide landscape panel  |  2-column scrollable card grid
-- All icons use ASCII / Roblox-safe text — no emoji.
-- Products: 2x Money (15min / 30min / 1hr, per-player) + 2x Luck (15min, server-wide)
-- Separate active countdowns for both boosts shown simultaneously.
-- Full-screen server announcement fires for everyone on Luck purchase.

local Players            = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local TweenService       = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------------
-- REMOTE SETUP
----------------------------------------------------------------------
local remotes        = ReplicatedStorage:WaitForChild("MoneyRemotes", 15)
local boostUpdate    = remotes and remotes:WaitForChild("BoostUpdate",        15)
local luckUpdate     = remotes and remotes:WaitForChild("LuckBoostUpdate",    15)
local announcementEv = remotes and remotes:WaitForChild("ServerAnnouncement", 15)
local boostInfoFunc  = remotes and remotes:WaitForChild("RequestBoostInfo",   15)

local boostInfo = boostInfoFunc and boostInfoFunc:InvokeServer() or {}

local PRODUCT_15MIN    = boostInfo.product15min or 3544443843
local PRODUCT_30MIN    = boostInfo.product30min or 3544444088
local PRODUCT_1HR      = boostInfo.product1hr   or 3544444447
local PRODUCT_LUCK     = boostInfo.productLuck  or 3544436072
local MULTIPLIER_LABEL = string.format("%dx", boostInfo.multiplier or 2)

local serverOffset = os.time() - math.floor(tick())
local activeExpiry = boostInfo.expiryTime or 0
local luckExpiry   = boostInfo.luckExpiry or 0

----------------------------------------------------------------------
-- TIME HELPERS
----------------------------------------------------------------------
local function serverTsToLocal(ts) return ts - serverOffset end

local function moneyRemaining()
	if activeExpiry <= 0 then return 0 end
	local r = serverTsToLocal(activeExpiry) - tick()
	return r > 0 and r or 0
end

local function luckRemaining()
	if luckExpiry <= 0 then return 0 end
	local r = serverTsToLocal(luckExpiry) - tick()
	return r > 0 and r or 0
end

local function formatTime(secs)
	secs = math.floor(secs)
	local h = math.floor(secs / 3600)
	local m = math.floor((secs % 3600) / 60)
	local s = secs % 60
	if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
	return string.format("%d:%02d", m, s)
end

----------------------------------------------------------------------
-- LIGHT THEME PALETTE
-- Warm parchment background · navy text · amber-gold accents
-- Teal for money boosts · violet for luck boosts
----------------------------------------------------------------------
-- Backgrounds
local C_PAPER       = Color3.fromRGB(252, 249, 243)   -- warm off-white panel bg
local C_CARD        = Color3.fromRGB(255, 255, 255)   -- pure white cards
local C_CARD_HOVER  = Color3.fromRGB(248, 246, 255)   -- faint violet tint on hover
local C_SIDEBAR     = Color3.fromRGB(245, 241, 232)   -- slightly warmer sidebar
local C_DIVIDER     = Color3.fromRGB(224, 218, 205)   -- warm grey lines

-- Accent colours
local C_AMBER       = Color3.fromRGB(214, 145,  30)   -- primary gold/amber
local C_AMBER_LIGHT = Color3.fromRGB(254, 243, 210)   -- amber tint wash
local C_TEAL        = Color3.fromRGB( 22, 168, 138)   -- money boost accent
local C_TEAL_LIGHT  = Color3.fromRGB(214, 248, 240)   -- teal tint wash
local C_VIOLET      = Color3.fromRGB(120,  80, 220)   -- luck boost accent
local C_VIOLET_LIGHT= Color3.fromRGB(237, 230, 255)   -- violet tint wash
local C_CRIMSON     = Color3.fromRGB(196,  48,  48)   -- close / danger
local C_CRIMSON_LT  = Color3.fromRGB(255, 235, 235)   -- close hover wash

-- Text
local C_INK         = Color3.fromRGB( 28,  26,  40)   -- primary dark text
local C_INK_MID     = Color3.fromRGB( 90,  85, 105)   -- secondary text
local C_INK_FAINT   = Color3.fromRGB(160, 155, 170)   -- placeholder / muted

-- Toggle button
local C_TOGGLE_BG   = Color3.fromRGB( 28,  26,  40)   -- dark pill
local C_TOGGLE_HV   = Color3.fromRGB( 50,  46,  70)   -- hover

-- Shadow / shadow-like border
local C_SHADOW      = Color3.fromRGB(200, 192, 178)

----------------------------------------------------------------------
-- TWEEN PRESETS  (smooth cubic curves)
----------------------------------------------------------------------
local TI_FAST   = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_MED    = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_SPRING = TweenInfo.new(0.32, Enum.EasingStyle.Back,  Enum.EasingDirection.Out)
local TI_EASE   = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)

local function tween(obj, info, props)
	TweenService:Create(obj, info, props):Play()
end

----------------------------------------------------------------------
-- ROOT GUI
----------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "BoostStoreGui"
screenGui.ResetOnSpawn   = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder   = 10
screenGui.Parent         = playerGui

----------------------------------------------------------------------
-- HELPER: rounded pill-shaped icon badge
-- Returns the outer Frame. Used for the toggle button icon and card icons.
----------------------------------------------------------------------
local function makePill(parent, size, pos, bgColor, textStr, textColor, zBase)
	local pill = Instance.new("Frame", parent)
	pill.Size             = size
	pill.Position         = pos
	pill.BackgroundColor3 = bgColor
	pill.BorderSizePixel  = 0
	pill.ZIndex           = zBase
	Instance.new("UICorner", pill).CornerRadius = UDim.new(0, 999)
	local lbl = Instance.new("TextLabel", pill)
	lbl.Size                   = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text                   = textStr
	lbl.TextColor3             = textColor
	lbl.TextScaled             = true
	lbl.Font                   = Enum.Font.GothamBlack
	lbl.ZIndex                 = zBase + 1
	return pill, lbl
end

----------------------------------------------------------------------
-- TOGGLE BUTTON  (bottom-left, dark rounded square)
----------------------------------------------------------------------
local toggleBtn = Instance.new("TextButton", screenGui)
toggleBtn.Name             = "ToggleBtn"
toggleBtn.Size             = UDim2.new(0, 54, 0, 54)
toggleBtn.Position         = UDim2.new(0, 18, 1, -76)
toggleBtn.BackgroundColor3 = C_TOGGLE_BG
toggleBtn.BorderSizePixel  = 0
toggleBtn.Text             = ""
toggleBtn.AutoButtonColor  = false
toggleBtn.ZIndex           = 10
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 14)

-- Drop shadow effect (larger frame behind)
local toggleShadow = Instance.new("Frame", screenGui)
toggleShadow.Size             = UDim2.new(0, 54, 0, 54)
toggleShadow.Position         = UDim2.new(0, 20, 1, -74)  -- offset 2px right+down
toggleShadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
toggleShadow.BackgroundTransparency = 0.82
toggleShadow.BorderSizePixel  = 0
toggleShadow.ZIndex           = 9
Instance.new("UICorner", toggleShadow).CornerRadius = UDim.new(0, 14)

-- "SHOP" text as the icon (all-caps, bold, readable)
local toggleLabel = Instance.new("TextLabel", toggleBtn)
toggleLabel.Size                   = UDim2.fromScale(1, 0.46)
toggleLabel.Position               = UDim2.fromScale(0, 0.14)
toggleLabel.BackgroundTransparency = 1
toggleLabel.Text                   = "SHOP"
toggleLabel.TextColor3             = C_AMBER
toggleLabel.TextScaled             = true
toggleLabel.Font                   = Enum.Font.GothamBlack
toggleLabel.ZIndex                 = 11

local toggleSub = Instance.new("TextLabel", toggleBtn)
toggleSub.Size                   = UDim2.fromScale(1, 0.28)
toggleSub.Position               = UDim2.fromScale(0, 0.62)
toggleSub.BackgroundTransparency = 1
toggleSub.Text                   = "Power-Ups"
toggleSub.TextColor3             = C_INK_FAINT
toggleSub.TextScaled             = true
toggleSub.Font                   = Enum.Font.Gotham
toggleSub.ZIndex                 = 11

-- Active indicator dots
local moneyDot = Instance.new("Frame", screenGui)
moneyDot.Size             = UDim2.new(0, 10, 0, 10)
moneyDot.Position         = UDim2.new(0, 62, 1, -80)
moneyDot.BackgroundColor3 = C_TEAL
moneyDot.BorderSizePixel  = 0
moneyDot.ZIndex           = 12
moneyDot.Visible          = false
Instance.new("UICorner", moneyDot).CornerRadius = UDim.new(1, 0)

local luckDot = Instance.new("Frame", screenGui)
luckDot.Size             = UDim2.new(0, 10, 0, 10)
luckDot.Position         = UDim2.new(0, 62, 1, -68)
luckDot.BackgroundColor3 = C_VIOLET
luckDot.BorderSizePixel  = 0
luckDot.ZIndex           = 12
luckDot.Visible          = false
Instance.new("UICorner", luckDot).CornerRadius = UDim.new(1, 0)

toggleBtn.MouseEnter:Connect(function()
	tween(toggleBtn, TI_FAST, {BackgroundColor3 = C_TOGGLE_HV})
end)
toggleBtn.MouseLeave:Connect(function()
	tween(toggleBtn, TI_FAST, {BackgroundColor3 = C_TOGGLE_BG})
end)

----------------------------------------------------------------------
-- OVERLAY  (blurred bg — semi-transparent white for light theme)
----------------------------------------------------------------------
local overlay = Instance.new("TextButton", screenGui)
overlay.Name                   = "Overlay"
overlay.Size                   = UDim2.fromScale(1, 1)
overlay.BackgroundColor3       = Color3.fromRGB(60, 55, 80)
overlay.BackgroundTransparency = 0.62
overlay.BorderSizePixel        = 0
overlay.Text                   = ""
overlay.ZIndex                 = 8
overlay.Visible                = false

----------------------------------------------------------------------
-- PANEL  — wide landscape, light parchment
-- ~78% wide x ~58% tall, clamped 320–720px × 250–410px
----------------------------------------------------------------------
local panel = Instance.new("Frame", screenGui)
panel.Name                   = "StorePanel"
panel.Size                   = UDim2.new(0.78, 0, 0.58, 0)
panel.AnchorPoint            = Vector2.new(0.5, 0.5)
panel.Position               = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3       = C_PAPER
panel.BackgroundTransparency = 1   -- starts invisible; tweened on open
panel.BorderSizePixel        = 0
panel.ClipsDescendants       = true
panel.Visible                = false
panel.ZIndex                 = 9
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 20)

local panelConstraint = Instance.new("UISizeConstraint", panel)
panelConstraint.MaxSize = Vector2.new(720, 410)
panelConstraint.MinSize = Vector2.new(320, 250)

-- Outer border (subtle warm shadow ring)
local pStroke = Instance.new("UIStroke", panel)
pStroke.Color        = C_SHADOW
pStroke.Thickness    = 1.5
pStroke.Transparency = 0.0

-- Amber top accent bar (brand stripe)
local topAccent = Instance.new("Frame", panel)
topAccent.Size             = UDim2.new(1, 0, 0, 4)
topAccent.BackgroundColor3 = C_AMBER
topAccent.BorderSizePixel  = 0
topAccent.ZIndex           = 9

----------------------------------------------------------------------
-- LEFT SIDEBAR
-- Slightly warmer tone than the main panel, with a right border line.
----------------------------------------------------------------------
local SIDEBAR_W = 0.27

local sidebar = Instance.new("Frame", panel)
sidebar.Name             = "Sidebar"
sidebar.Size             = UDim2.new(SIDEBAR_W, 0, 1, 0)
sidebar.BackgroundColor3 = C_SIDEBAR
sidebar.BorderSizePixel  = 0
sidebar.ZIndex           = 10
Instance.new("UICorner", sidebar).CornerRadius = UDim.new(0, 20)

-- Flush the right side of sidebar corners
local sbSquare = Instance.new("Frame", sidebar)
sbSquare.Size             = UDim2.new(0.35, 0, 1, 0)
sbSquare.Position         = UDim2.new(0.65, 0, 0, 0)
sbSquare.BackgroundColor3 = C_SIDEBAR
sbSquare.BorderSizePixel  = 0
sbSquare.ZIndex           = 10

-- Subtle right-side divider
local sbDivider = Instance.new("Frame", sidebar)
sbDivider.Size             = UDim2.new(0, 1, 1, 0)
sbDivider.Position         = UDim2.new(1, -1, 0, 0)
sbDivider.BackgroundColor3 = C_DIVIDER
sbDivider.BorderSizePixel  = 0
sbDivider.ZIndex           = 11

-- Amber top accent on sidebar (continues the stripe)
local sbAccent = Instance.new("Frame", sidebar)
sbAccent.Size             = UDim2.new(1, 0, 0, 4)
sbAccent.BackgroundColor3 = C_AMBER
sbAccent.BorderSizePixel  = 0
sbAccent.ZIndex           = 11

-- Amber monogram pill icon
local logoOuter = Instance.new("Frame", sidebar)
logoOuter.Size             = UDim2.new(0, 44, 0, 44)
logoOuter.Position         = UDim2.new(0.5, -22, 0, 20)
logoOuter.BackgroundColor3 = C_AMBER
logoOuter.BorderSizePixel  = 0
logoOuter.ZIndex           = 12
Instance.new("UICorner", logoOuter).CornerRadius = UDim.new(0, 12)

local logoLbl = Instance.new("TextLabel", logoOuter)
logoLbl.Size                   = UDim2.fromScale(1, 1)
logoLbl.BackgroundTransparency = 1
logoLbl.Text                   = "PU"   -- Power-Up
logoLbl.TextColor3             = Color3.fromRGB(255, 255, 255)
logoLbl.TextScaled             = true
logoLbl.Font                   = Enum.Font.GothamBlack
logoLbl.ZIndex                 = 13

-- Store title
local sbTitle = Instance.new("TextLabel", sidebar)
sbTitle.Size                   = UDim2.new(1, -20, 0, 22)
sbTitle.Position               = UDim2.new(0, 10, 0, 72)
sbTitle.BackgroundTransparency = 1
sbTitle.Text                   = "Power-Up Store"
sbTitle.TextColor3             = C_INK
sbTitle.TextScaled             = true
sbTitle.Font                   = Enum.Font.GothamBlack
sbTitle.TextXAlignment         = Enum.TextXAlignment.Center
sbTitle.ZIndex                 = 12

-- Subtitle
local sbSub = Instance.new("TextLabel", sidebar)
sbSub.Size                   = UDim2.new(1, -16, 0, 15)
sbSub.Position               = UDim2.new(0, 8, 0, 96)
sbSub.BackgroundTransparency = 1
sbSub.Text                   = "Boost your adventure"
sbSub.TextColor3             = C_INK_MID
sbSub.TextScaled             = true
sbSub.Font                   = Enum.Font.Gotham
sbSub.TextXAlignment         = Enum.TextXAlignment.Center
sbSub.ZIndex                 = 12

-- Hairline divider
local sbLine = Instance.new("Frame", sidebar)
sbLine.Size             = UDim2.new(0.72, 0, 0, 1)
sbLine.Position         = UDim2.new(0.14, 0, 0, 118)
sbLine.BackgroundColor3 = C_DIVIDER
sbLine.BorderSizePixel  = 0
sbLine.ZIndex           = 12

----------------------------------------------------------------------
-- ACTIVE BOOST BANNERS  (in sidebar, below divider)
----------------------------------------------------------------------
local function makeSidebarBanner(yPos, washColor, accentColor, labelText)
	local f = Instance.new("Frame", sidebar)
	f.Size             = UDim2.new(1, -20, 0, 52)
	f.Position         = UDim2.new(0, 10, 0, yPos)
	f.BackgroundColor3 = washColor
	f.BackgroundTransparency = 0.0
	f.BorderSizePixel  = 0
	f.Visible          = false
	f.ZIndex           = 12
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 10)

	-- Left accent stripe
	local stripe = Instance.new("Frame", f)
	stripe.Size             = UDim2.new(0, 3, 1, 0)
	stripe.BackgroundColor3 = accentColor
	stripe.BorderSizePixel  = 0
	stripe.ZIndex           = 13
	Instance.new("UICorner", stripe).CornerRadius = UDim.new(0, 999)
	-- square right side of stripe
	local sq = Instance.new("Frame", stripe)
	sq.Size             = UDim2.new(0.6, 0, 1, 0)
	sq.Position         = UDim2.new(0.4, 0, 0, 0)
	sq.BackgroundColor3 = accentColor
	sq.BorderSizePixel  = 0
	sq.ZIndex           = 13

	-- Header label (e.g. "ACTIVE")
	local tag = Instance.new("TextLabel", f)
	tag.Size                   = UDim2.new(1, -12, 0, 14)
	tag.Position               = UDim2.new(0, 10, 0, 7)
	tag.BackgroundTransparency = 1
	tag.Text                   = "ACTIVE"
	tag.TextColor3             = accentColor
	tag.TextScaled             = true
	tag.Font                   = Enum.Font.GothamBlack
	tag.TextXAlignment         = Enum.TextXAlignment.Left
	tag.ZIndex                 = 13

	-- Timer label (the countdown)
	local lbl = Instance.new("TextLabel", f)
	lbl.Size                   = UDim2.new(1, -12, 0, 18)
	lbl.Position               = UDim2.new(0, 10, 0, 24)
	lbl.BackgroundTransparency = 1
	lbl.Text                   = labelText
	lbl.TextColor3             = C_INK
	lbl.TextScaled             = true
	lbl.Font                   = Enum.Font.GothamBold
	lbl.TextXAlignment         = Enum.TextXAlignment.Left
	lbl.ZIndex                 = 13
	return f, lbl
end

local moneyBanner, moneyTimerLabel = makeSidebarBanner(128, C_TEAL_LIGHT,  C_TEAL,   "Money boost")
local luckBanner,  luckTimerLabel  = makeSidebarBanner(188, C_VIOLET_LIGHT, C_VIOLET, "Luck boost")

----------------------------------------------------------------------
-- CLOSE BUTTON  (bottom of sidebar, subtle crimson)
----------------------------------------------------------------------
local closeBtn = Instance.new("TextButton", sidebar)
closeBtn.Size             = UDim2.new(1, -24, 0, 34)
closeBtn.Position         = UDim2.new(0, 12, 1, -46)
closeBtn.BackgroundColor3 = C_CRIMSON_LT
closeBtn.BorderSizePixel  = 0
closeBtn.Text             = ""
closeBtn.AutoButtonColor  = false
closeBtn.ZIndex           = 12
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 10)

-- "CLOSE" label
local closeLbl = Instance.new("TextLabel", closeBtn)
closeLbl.Size                   = UDim2.fromScale(1, 1)
closeLbl.BackgroundTransparency = 1
closeLbl.Text                   = "CLOSE"
closeLbl.TextColor3             = C_CRIMSON
closeLbl.TextScaled             = true
closeLbl.Font                   = Enum.Font.GothamBold
closeLbl.ZIndex                 = 13

closeBtn.MouseEnter:Connect(function()
	tween(closeBtn, TI_FAST, {BackgroundColor3 = C_CRIMSON})
	tween(closeLbl, TI_FAST, {TextColor3 = Color3.fromRGB(255,255,255)})
end)
closeBtn.MouseLeave:Connect(function()
	tween(closeBtn, TI_FAST, {BackgroundColor3 = C_CRIMSON_LT})
	tween(closeLbl, TI_FAST, {TextColor3 = C_CRIMSON})
end)

----------------------------------------------------------------------
-- SCROLLABLE CARD AREA  (right side of panel)
----------------------------------------------------------------------
local cardArea = Instance.new("ScrollingFrame", panel)
cardArea.Name                   = "CardArea"
cardArea.Size                   = UDim2.new(1 - SIDEBAR_W, -20, 1, -24)
cardArea.Position               = UDim2.new(SIDEBAR_W, 10, 0, 12)
cardArea.BackgroundTransparency = 1
cardArea.BorderSizePixel        = 0
cardArea.ScrollBarThickness     = 4
cardArea.ScrollBarImageColor3   = C_DIVIDER
cardArea.CanvasSize             = UDim2.new(0, 0, 0, 0)
cardArea.AutomaticCanvasSize    = Enum.AutomaticSize.Y
cardArea.ScrollingDirection     = Enum.ScrollingDirection.Y
cardArea.ElasticBehavior        = Enum.ElasticBehavior.WhenScrollable
cardArea.ZIndex                 = 10

local gridLayout = Instance.new("UIGridLayout", cardArea)
gridLayout.SortOrder            = Enum.SortOrder.LayoutOrder
gridLayout.CellSize             = UDim2.new(0.47, 0, 0, 130)
gridLayout.CellPadding          = UDim2.new(0.04, 0, 0, 12)
gridLayout.FillDirection        = Enum.FillDirection.Horizontal
gridLayout.HorizontalAlignment  = Enum.HorizontalAlignment.Center
gridLayout.VerticalAlignment    = Enum.VerticalAlignment.Top
gridLayout.StartCorner          = Enum.StartCorner.TopLeft

local gridPad = Instance.new("UIPadding", cardArea)
gridPad.PaddingTop    = UDim.new(0, 10)
gridPad.PaddingBottom = UDim.new(0, 10)
gridPad.PaddingLeft   = UDim.new(0, 4)
gridPad.PaddingRight  = UDim.new(0, 4)

----------------------------------------------------------------------
-- CARD FACTORY
----------------------------------------------------------------------
local function makeProductCard(layoutOrder, iconText, iconBg, title, duration, subtext, productId, accentColor, accentWash, badgeText)

	local card = Instance.new("TextButton", cardArea)
	card.Name             = "Card_" .. layoutOrder
	card.BackgroundColor3 = C_CARD
	card.BorderSizePixel  = 0
	card.Text             = ""
	card.AutoButtonColor  = false
	card.LayoutOrder      = layoutOrder
	card.ZIndex           = 11
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)

	-- Subtle border
	local cs = Instance.new("UIStroke", card)
	cs.Color        = C_DIVIDER
	cs.Thickness    = 1
	cs.Transparency = 0.0

	-- Top coloured accent bar
	local topBar = Instance.new("Frame", card)
	topBar.Size             = UDim2.new(1, 0, 0, 4)
	topBar.BackgroundColor3 = accentColor
	topBar.BorderSizePixel  = 0
	topBar.ZIndex           = 12
	Instance.new("UICorner", topBar).CornerRadius = UDim.new(0, 14)
	local tbFill = Instance.new("Frame", topBar)
	tbFill.Size             = UDim2.new(1, 0, 0.5, 0)
	tbFill.Position         = UDim2.new(0, 0, 0.5, 0)
	tbFill.BackgroundColor3 = accentColor
	tbFill.BorderSizePixel  = 0
	tbFill.ZIndex           = 12

	-- Icon pill (top-left of card body)
	local iconPill = Instance.new("Frame", card)
	iconPill.Size             = UDim2.new(0, 36, 0, 36)
	iconPill.Position         = UDim2.new(0, 12, 0, 14)
	iconPill.BackgroundColor3 = iconBg
	iconPill.BorderSizePixel  = 0
	iconPill.ZIndex           = 12
	Instance.new("UICorner", iconPill).CornerRadius = UDim.new(0, 10)

	local iconLbl = Instance.new("TextLabel", iconPill)
	iconLbl.Size                   = UDim2.fromScale(1, 1)
	iconLbl.BackgroundTransparency = 1
	iconLbl.Text                   = iconText
	iconLbl.TextColor3             = accentColor
	iconLbl.TextScaled             = true
	iconLbl.Font                   = Enum.Font.GothamBlack
	iconLbl.ZIndex                 = 13

	-- Optional badge (e.g. "SERVER")
	if badgeText then
		local badge = Instance.new("Frame", card)
		badge.Size             = UDim2.new(0, 58, 0, 18)
		badge.Position         = UDim2.new(1, -70, 0, 14)
		badge.BackgroundColor3 = accentWash
		badge.BorderSizePixel  = 0
		badge.ZIndex           = 13
		Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 999)
		local bl = Instance.new("TextLabel", badge)
		bl.Size                   = UDim2.fromScale(1, 1)
		bl.BackgroundTransparency = 1
		bl.Text                   = badgeText
		bl.TextColor3             = accentColor
		bl.TextScaled             = true
		bl.Font                   = Enum.Font.GothamBold
		bl.ZIndex                 = 14
	end

	-- Title
	local titleLbl = Instance.new("TextLabel", card)
	titleLbl.Size                   = UDim2.new(1, -16, 0, 20)
	titleLbl.Position               = UDim2.new(0, 12, 0, 56)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text                   = title
	titleLbl.TextColor3             = C_INK
	titleLbl.TextScaled             = true
	titleLbl.Font                   = Enum.Font.GothamBlack
	titleLbl.TextXAlignment         = Enum.TextXAlignment.Left
	titleLbl.ZIndex                 = 12

	-- Duration label
	local durLbl = Instance.new("TextLabel", card)
	durLbl.Size                   = UDim2.new(1, -16, 0, 15)
	durLbl.Position               = UDim2.new(0, 12, 0, 78)
	durLbl.BackgroundTransparency = 1
	durLbl.Text                   = duration
	durLbl.TextColor3             = accentColor
	durLbl.TextScaled             = true
	durLbl.Font                   = Enum.Font.GothamBold
	durLbl.TextXAlignment         = Enum.TextXAlignment.Left
	durLbl.ZIndex                 = 12

	-- Sub text (e.g. "Per-player · stacks")
	local subLbl = Instance.new("TextLabel", card)
	subLbl.Size                   = UDim2.new(1, -16, 0, 13)
	subLbl.Position               = UDim2.new(0, 12, 0, 95)
	subLbl.BackgroundTransparency = 1
	subLbl.Text                   = subtext
	subLbl.TextColor3             = C_INK_MID
	subLbl.TextScaled             = true
	subLbl.Font                   = Enum.Font.Gotham
	subLbl.TextXAlignment         = Enum.TextXAlignment.Left
	subLbl.ZIndex                 = 12

	-- BUY button (full-width bottom strip)
	local buyBtn = Instance.new("TextButton", card)
	buyBtn.Size             = UDim2.new(1, -24, 0, 26)
	buyBtn.Position         = UDim2.new(0, 12, 1, -34)
	buyBtn.BackgroundColor3 = accentColor
	buyBtn.BorderSizePixel  = 0
	buyBtn.Text             = "BUY NOW"
	buyBtn.TextScaled       = true
	buyBtn.Font             = Enum.Font.GothamBlack
	buyBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
	buyBtn.ZIndex           = 13
	Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 8)

	-- Hover states
	local function setHover(on)
		if on then
			tween(card,   TI_FAST, {BackgroundColor3 = accentWash})
			tween(cs,     TI_FAST, {Transparency = 0.5})
			tween(buyBtn, TI_FAST, {BackgroundColor3 = accentColor})
		else
			tween(card,   TI_FAST, {BackgroundColor3 = C_CARD})
			tween(cs,     TI_FAST, {Transparency = 0.0})
		end
	end

	local buyHoverColor = Color3.new(
		math.min(accentColor.R * 1.12, 1),
		math.min(accentColor.G * 1.12, 1),
		math.min(accentColor.B * 1.12, 1)
	)

	buyBtn.MouseEnter:Connect(function() tween(buyBtn, TI_FAST, {BackgroundColor3 = buyHoverColor}) end)
	buyBtn.MouseLeave:Connect(function() tween(buyBtn, TI_FAST, {BackgroundColor3 = accentColor}) end)
	card.MouseEnter:Connect(function() setHover(true) end)
	card.MouseLeave:Connect(function() setHover(false) end)

	local function doPurchase()
		if productId == 0 then
			warn("[BoostStore] Product ID not configured for:", title)
			return
		end
		MarketplaceService:PromptProductPurchase(player, productId)
	end
	card.Activated:Connect(doPurchase)
	buyBtn.Activated:Connect(doPurchase)
end

--                  order  icon  iconBg         title              duration        subtext               productId      accent     accentWash      badge
makeProductCard(1, "$x2",  C_TEAL_LIGHT,   MULTIPLIER_LABEL.." Money", "15 Minutes",    "Per-player  |  Stacks",   PRODUCT_15MIN, C_TEAL,   C_TEAL_LIGHT)
makeProductCard(2, "$x2",  C_TEAL_LIGHT,   MULTIPLIER_LABEL.." Money", "30 Minutes",    "Per-player  |  Stacks",   PRODUCT_30MIN, C_TEAL,   C_TEAL_LIGHT)
makeProductCard(3, "$x2",  C_TEAL_LIGHT,   MULTIPLIER_LABEL.." Money", "1 Hour",        "Per-player  |  Stacks",   PRODUCT_1HR,   C_TEAL,   C_TEAL_LIGHT)
makeProductCard(4, "*x2",  C_VIOLET_LIGHT, "2x Luck",                  "15 Minutes",    "Server-wide boost!",      PRODUCT_LUCK,  C_VIOLET, C_VIOLET_LIGHT, "SERVER")

----------------------------------------------------------------------
-- PANEL OPEN / CLOSE  (smooth scale + fade)
----------------------------------------------------------------------
local panelOpen = false

local function setPanelOpen(open)
	panelOpen = open
	if open then
		overlay.Visible              = true
		panel.Visible                = true
		panel.BackgroundTransparency = 1
		-- Animate in: fade
		tween(panel, TI_SPRING, {BackgroundTransparency = 0})
		-- Animate overlay in
		overlay.BackgroundTransparency = 0.85
		tween(overlay, TI_MED, {BackgroundTransparency = 0.62})
	else
		tween(panel,   TI_EASE, {BackgroundTransparency = 1})
		tween(overlay, TI_EASE, {BackgroundTransparency = 0.85})
		task.delay(0.25, function()
			if not panelOpen then
				panel.Visible   = false
				overlay.Visible = false
			end
		end)
	end
end

toggleBtn.Activated:Connect(function() setPanelOpen(not panelOpen) end)
closeBtn.Activated:Connect(function()  setPanelOpen(false) end)
overlay.Activated:Connect(function()   setPanelOpen(false) end)

----------------------------------------------------------------------
-- BOOST UI REFRESH
----------------------------------------------------------------------
local function refreshBoostUI()
	local mRem = moneyRemaining()
	local lRem = luckRemaining()

	-- Money banner
	moneyBanner.Visible = mRem > 0
	if mRem > 0 then
		moneyTimerLabel.Text = MULTIPLIER_LABEL .. " Money  -  " .. formatTime(mRem)
	end

	-- Luck banner
	luckBanner.Visible = lRem > 0
	if lRem > 0 then
		luckTimerLabel.Text = "2x Luck  -  " .. formatTime(lRem)
	end

	-- Restack banners
	local BASE_Y = 128
	moneyBanner.Position = UDim2.new(0, 10, 0, BASE_Y)
	luckBanner.Position  = UDim2.new(0, 10, 0, BASE_Y + (mRem > 0 and 62 or 0))

	-- Toggle indicator dots
	moneyDot.Visible = mRem > 0
	luckDot.Visible  = lRem > 0
end

-- BoostUpdate fires ONLY for per-player money boosts.
-- It must NEVER touch luckExpiry.
if boostUpdate then
	boostUpdate.OnClientEvent:Connect(function(expiryTs, _mult)
		-- Sanity check: ignore if this looks like a luck timestamp being
		-- accidentally fired through the wrong remote (server-side bug guard).
		-- A money boost updates activeExpiry only.
		activeExpiry = expiryTs
		-- Do NOT touch luckExpiry here.
		refreshBoostUI()
	end)
end

-- LuckBoostUpdate fires ONLY for server-wide luck boosts.
-- It must NEVER touch activeExpiry (money).
if luckUpdate then
	luckUpdate.OnClientEvent:Connect(function(expiry, _power)
		-- Update luck expiry only.
		luckExpiry = expiry
		-- Do NOT touch activeExpiry here.
		refreshBoostUI()
	end)
end

refreshBoostUI()
RunService.Heartbeat:Connect(refreshBoostUI)

----------------------------------------------------------------------
-- SERVER ANNOUNCEMENT  (slides in from top on Luck purchase)
----------------------------------------------------------------------
local announceBg = Instance.new("Frame", screenGui)
announceBg.Size                   = UDim2.new(0.58, 0, 0, 82)
announceBg.AnchorPoint            = Vector2.new(0.5, 0)
announceBg.Position               = UDim2.new(0.5, 0, 0, -100)
announceBg.BackgroundColor3       = Color3.fromRGB(255, 255, 255)
announceBg.BackgroundTransparency = 0.0
announceBg.BorderSizePixel        = 0
announceBg.ZIndex                 = 30
announceBg.Visible                = false
Instance.new("UICorner", announceBg).CornerRadius = UDim.new(0, 16)

local annConstraint = Instance.new("UISizeConstraint", announceBg)
annConstraint.MaxSize = Vector2.new(520, 96)
annConstraint.MinSize = Vector2.new(240, 72)

local annStroke = Instance.new("UIStroke", announceBg)
annStroke.Color        = C_VIOLET
annStroke.Thickness    = 2
annStroke.Transparency = 0.0

-- Violet top accent
local annAccent = Instance.new("Frame", announceBg)
annAccent.Size             = UDim2.new(1, 0, 0, 4)
annAccent.BackgroundColor3 = C_VIOLET
annAccent.BorderSizePixel  = 0
annAccent.ZIndex           = 30
Instance.new("UICorner", annAccent).CornerRadius = UDim.new(0, 16)
local annAccFill = Instance.new("Frame", annAccent)
annAccFill.Size             = UDim2.new(1, 0, 0.5, 0)
annAccFill.Position         = UDim2.new(0, 0, 0.5, 0)
annAccFill.BackgroundColor3 = C_VIOLET
annAccFill.BorderSizePixel  = 0
annAccFill.ZIndex           = 30

-- Icon pill
local annIcon = Instance.new("Frame", announceBg)
annIcon.Size             = UDim2.new(0, 38, 0, 38)
annIcon.Position         = UDim2.new(0, 14, 0.5, -19)
annIcon.BackgroundColor3 = C_VIOLET_LIGHT
annIcon.BorderSizePixel  = 0
annIcon.ZIndex           = 31
Instance.new("UICorner", annIcon).CornerRadius = UDim.new(0, 10)

local annIconLbl = Instance.new("TextLabel", annIcon)
annIconLbl.Size                   = UDim2.fromScale(1, 1)
annIconLbl.BackgroundTransparency = 1
annIconLbl.Text                   = "LUCK"
annIconLbl.TextColor3             = C_VIOLET
annIconLbl.TextScaled             = true
annIconLbl.Font                   = Enum.Font.GothamBlack
annIconLbl.ZIndex                 = 32

local annLabel = Instance.new("TextLabel", announceBg)
annLabel.Size                   = UDim2.new(1, -68, 0, 26)
annLabel.Position               = UDim2.new(0, 62, 0, 14)
annLabel.BackgroundTransparency = 1
annLabel.Text                   = "2x Luck Boost Activated!"
annLabel.TextColor3             = C_INK
annLabel.TextScaled             = true
annLabel.Font                   = Enum.Font.GothamBlack
annLabel.TextXAlignment         = Enum.TextXAlignment.Left
annLabel.ZIndex                 = 31

local annSub = Instance.new("TextLabel", announceBg)
annSub.Size                   = UDim2.new(1, -68, 0, 18)
annSub.Position               = UDim2.new(0, 62, 0, 42)
annSub.BackgroundTransparency = 1
annSub.Text                   = ""
annSub.TextColor3             = C_INK_MID
annSub.TextScaled             = true
annSub.Font                   = Enum.Font.Gotham
annSub.TextXAlignment         = Enum.TextXAlignment.Left
annSub.ZIndex                 = 31

local announceActive = false

local function showAnnouncement(buyerName, productLabel, expiry)
	-- IMPORTANT: only update luckExpiry here — NEVER activeExpiry.
	-- The announcement carries the luck boost expiry, not the money expiry.
	if expiry and expiry > 0 then
		luckExpiry = expiry
	end
	refreshBoostUI()

	annLabel.Text = productLabel .. " Activated!"
	annSub.Text   = buyerName .. " activated this boost for the whole server!"

	if announceActive then return end
	announceActive     = true
	announceBg.Visible = true

	local slideIn = TweenService:Create(announceBg,
		TweenInfo.new(0.40, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Position = UDim2.new(0.5, 0, 0, 16)})
	slideIn:Play()
	slideIn.Completed:Wait()

	task.wait(5)

	local slideOut = TweenService:Create(announceBg,
		TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
		{Position = UDim2.new(0.5, 0, 0, -100)})
	slideOut:Play()
	slideOut.Completed:Wait()

	announceBg.Visible = false
	announceActive     = false
end

if announcementEv then
	announcementEv.OnClientEvent:Connect(function(buyerName, productLabel, expiry)
		task.spawn(showAnnouncement, buyerName, productLabel, expiry)
	end)
end