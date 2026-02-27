-- MoneyDisplay (LocalScript, StarterPlayerScripts)
-- Listens for UpdateBalance events and shows the player their current balance.
-- Attach a ScreenGui called "MoneyGui" with a TextLabel called "BalanceLabel"
-- under StarterGui, OR let this script create it automatically.
--
-- VISUAL DESIGN: matches the BoostStore light theme
--   Palette  : warm parchment bg · ink text · amber accent · teal money green
--   Icons    : ASCII-safe text labels (no emoji — Roblox renders them unreliably)
--   Motion   : Quint/Back easing, smooth open/close, hover micro-interactions
--   Layout   : balance chip top-right · SHOP pill below it · slide-in panel

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService       = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------------
-- CONFIGURE  (keep identical to moneyserver.lua)
----------------------------------------------------------------------
local AUTO_COLLECT_GAMEPASS_ID = 1727487379
local AUTO_COLLECT_NAME        = "Auto-Collect"
local AUTO_COLLECT_DESC        = "$/s goes straight to your balance — no need to touch your slots!"
local AUTO_COLLECT_PRICE       = "See in store"

----------------------------------------------------------------------
-- SHARED PALETTE  (mirrors BoostStoreClient exactly)
----------------------------------------------------------------------
local C_PAPER        = Color3.fromRGB(252, 249, 243)   -- warm off-white
local C_CARD         = Color3.fromRGB(255, 255, 255)   -- pure white cards
local C_SIDEBAR      = Color3.fromRGB(245, 241, 232)   -- warm sidebar tone
local C_DIVIDER      = Color3.fromRGB(224, 218, 205)   -- hairline lines

local C_AMBER        = Color3.fromRGB(214, 145,  30)   -- brand gold
local C_AMBER_LIGHT  = Color3.fromRGB(254, 243, 210)   -- amber wash
local C_TEAL         = Color3.fromRGB( 22, 168, 138)   -- money / positive
local C_TEAL_LIGHT   = Color3.fromRGB(214, 248, 240)   -- teal wash
local C_CRIMSON      = Color3.fromRGB(196,  48,  48)   -- close / danger
local C_CRIMSON_LT   = Color3.fromRGB(255, 235, 235)   -- close wash

local C_INK          = Color3.fromRGB( 28,  26,  40)   -- primary text
local C_INK_MID      = Color3.fromRGB( 90,  85, 105)   -- secondary text
local C_INK_FAINT    = Color3.fromRGB(160, 155, 170)   -- muted / hint

local C_TOGGLE_BG    = Color3.fromRGB( 28,  26,  40)   -- dark chip bg
local C_TOGGLE_HV    = Color3.fromRGB( 50,  46,  70)   -- chip hover
local C_SHADOW       = Color3.fromRGB(200, 192, 178)   -- outer border

----------------------------------------------------------------------
-- TWEEN HELPERS  (same presets as BoostStoreClient)
----------------------------------------------------------------------
local TI_FAST   = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_MED    = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_SPRING = TweenInfo.new(0.35, Enum.EasingStyle.Back,  Enum.EasingDirection.Out)
local TI_SLIDE  = TweenInfo.new(0.30, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function tw(obj, info, props) TweenService:Create(obj, info, props):Play() end

----------------------------------------------------------------------
-- BUILD GUI
----------------------------------------------------------------------
local function getOrCreateGui()
	local gui = playerGui:FindFirstChild("MoneyGui")
	if gui then
		return gui:FindFirstChild("BalanceLabel")
	end

	gui = Instance.new("ScreenGui")
	gui.Name         = "MoneyGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent       = playerGui

	--------------------------------------------------------------------
	-- BALANCE CHIP  (top-right, dark pill matching toggle style)
	-- Shows "$12,345" in teal on a dark rounded rectangle.
	--------------------------------------------------------------------
	local chipShadow = Instance.new("Frame", gui)
	chipShadow.Size             = UDim2.new(0, 164, 0, 44)
	chipShadow.Position         = UDim2.new(1, -168, 0, 16)  -- 2px shadow offset
	chipShadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	chipShadow.BackgroundTransparency = 0.82
	chipShadow.BorderSizePixel  = 0
	chipShadow.ZIndex           = 3
	Instance.new("UICorner", chipShadow).CornerRadius = UDim.new(0, 14)

	local chip = Instance.new("Frame", gui)
	chip.Name             = "BalanceChip"
	chip.Size             = UDim2.new(0, 164, 0, 44)
	chip.Position         = UDim2.new(1, -170, 0, 14)
	chip.BackgroundColor3 = C_TOGGLE_BG
	chip.BorderSizePixel  = 0
	chip.ZIndex           = 4
	Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 14)

	-- Amber top stripe (brand accent)
	local chipStripe = Instance.new("Frame", chip)
	chipStripe.Size             = UDim2.new(1, 0, 0, 3)
	chipStripe.BackgroundColor3 = C_AMBER
	chipStripe.BorderSizePixel  = 0
	chipStripe.ZIndex           = 5
	Instance.new("UICorner", chipStripe).CornerRadius = UDim.new(0, 14)
	local chipStripeFill = Instance.new("Frame", chipStripe)
	chipStripeFill.Size             = UDim2.new(1, 0, 0.5, 0)
	chipStripeFill.Position         = UDim2.new(0, 0, 0.5, 0)
	chipStripeFill.BackgroundColor3 = C_AMBER
	chipStripeFill.BorderSizePixel  = 0
	chipStripeFill.ZIndex           = 5

	-- "$" icon pill on left
	local chipIcon = Instance.new("Frame", chip)
	chipIcon.Size             = UDim2.new(0, 28, 0, 28)
	chipIcon.Position         = UDim2.new(0, 10, 0.5, -14)
	chipIcon.BackgroundColor3 = C_TEAL
	chipIcon.BorderSizePixel  = 0
	chipIcon.ZIndex           = 6
	Instance.new("UICorner", chipIcon).CornerRadius = UDim.new(0, 8)

	local chipIconLbl = Instance.new("TextLabel", chipIcon)
	chipIconLbl.Size                   = UDim2.fromScale(1, 1)
	chipIconLbl.BackgroundTransparency = 1
	chipIconLbl.Text                   = "$"
	chipIconLbl.TextColor3             = Color3.fromRGB(255, 255, 255)
	chipIconLbl.TextScaled             = true
	chipIconLbl.Font                   = Enum.Font.GothamBlack
	chipIconLbl.ZIndex                 = 7

	-- Balance value label
	local label = Instance.new("TextLabel", chip)
	label.Name                   = "BalanceLabel"
	label.Size                   = UDim2.new(1, -50, 1, 0)
	label.Position               = UDim2.new(0, 44, 0, 0)
	label.BackgroundTransparency = 1
	label.Text                   = "$0"
	label.TextColor3             = C_TEAL
	label.TextScaled             = true
	label.Font                   = Enum.Font.GothamBlack
	label.TextXAlignment         = Enum.TextXAlignment.Left
	label.ZIndex                 = 6

	--------------------------------------------------------------------
	-- SHOP BUTTON  (dark pill, sits below the balance chip)
	--------------------------------------------------------------------
	local shopBtnShadow = Instance.new("Frame", gui)
	shopBtnShadow.Size             = UDim2.new(0, 164, 0, 38)
	shopBtnShadow.Position         = UDim2.new(1, -168, 0, 64)
	shopBtnShadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shopBtnShadow.BackgroundTransparency = 0.82
	shopBtnShadow.BorderSizePixel  = 0
	shopBtnShadow.ZIndex           = 3
	Instance.new("UICorner", shopBtnShadow).CornerRadius = UDim.new(0, 12)

	local storeBtn = Instance.new("TextButton", gui)
	storeBtn.Name             = "StoreButton"
	storeBtn.Size             = UDim2.new(0, 164, 0, 38)
	storeBtn.Position         = UDim2.new(1, -170, 0, 62)
	storeBtn.BackgroundColor3 = C_AMBER
	storeBtn.BorderSizePixel  = 0
	storeBtn.Text             = ""
	storeBtn.AutoButtonColor  = false
	storeBtn.ZIndex           = 5
	Instance.new("UICorner", storeBtn).CornerRadius = UDim.new(0, 12)

	-- Left icon pill on shop button
	local shopIcon = Instance.new("Frame", storeBtn)
	shopIcon.Size             = UDim2.new(0, 24, 0, 24)
	shopIcon.Position         = UDim2.new(0, 8, 0.5, -12)
	shopIcon.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	shopIcon.BackgroundTransparency = 0.78
	shopIcon.BorderSizePixel  = 0
	shopIcon.ZIndex           = 6
	Instance.new("UICorner", shopIcon).CornerRadius = UDim.new(0, 6)

	local shopIconLbl = Instance.new("TextLabel", shopIcon)
	shopIconLbl.Size                   = UDim2.fromScale(1, 1)
	shopIconLbl.BackgroundTransparency = 1
	shopIconLbl.Text                   = "S"
	shopIconLbl.TextColor3             = Color3.fromRGB(255, 255, 255)
	shopIconLbl.TextScaled             = true
	shopIconLbl.Font                   = Enum.Font.GothamBlack
	shopIconLbl.ZIndex                 = 7

	local shopLbl = Instance.new("TextLabel", storeBtn)
	shopLbl.Size                   = UDim2.new(1, -42, 1, 0)
	shopLbl.Position               = UDim2.new(0, 38, 0, 0)
	shopLbl.BackgroundTransparency = 1
	shopLbl.Text                   = "SHOP"
	shopLbl.TextColor3             = Color3.fromRGB(255, 255, 255)
	shopLbl.TextScaled             = true
	shopLbl.Font                   = Enum.Font.GothamBlack
	shopLbl.TextXAlignment         = Enum.TextXAlignment.Left
	shopLbl.ZIndex                 = 6

	storeBtn.MouseEnter:Connect(function()
		tw(storeBtn, TI_FAST, {BackgroundColor3 = Color3.fromRGB(235, 158, 20)})
	end)
	storeBtn.MouseLeave:Connect(function()
		tw(storeBtn, TI_FAST, {BackgroundColor3 = C_AMBER})
	end)

	--------------------------------------------------------------------
	-- STORE PANEL  — light parchment, slides in from the right
	-- Matches BoostStore: warm paper bg, amber top stripe, sidebar-style
	-- header, white cards with teal accents.
	--------------------------------------------------------------------
	local PANEL_W = 360
	local PANEL_H = 460

	-- Shadow behind panel
	local panelShadow = Instance.new("Frame", gui)
	panelShadow.Size                   = UDim2.new(0, PANEL_W + 8, 0, PANEL_H + 8)
	panelShadow.Position               = UDim2.new(1, 14, 0.5, -(PANEL_H / 2) - 2)
	panelShadow.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
	panelShadow.BackgroundTransparency = 0.72
	panelShadow.BorderSizePixel        = 0
	panelShadow.ZIndex                 = 9
	panelShadow.Visible                = false
	Instance.new("UICorner", panelShadow).CornerRadius = UDim.new(0, 22)

	local panel = Instance.new("Frame", gui)
	panel.Name                   = "StorePanel"
	panel.Size                   = UDim2.new(0, PANEL_W, 0, PANEL_H)
	panel.Position               = UDim2.new(1, 10, 0.5, -PANEL_H / 2)  -- off-screen right
	panel.BackgroundColor3       = C_PAPER
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel        = 0
	panel.ZIndex                 = 10
	panel.Visible                = false
	panel.ClipsDescendants       = true
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 20)

	-- Outer border (subtle warm ring)
	local pStroke = Instance.new("UIStroke", panel)
	pStroke.Color        = C_SHADOW
	pStroke.Thickness    = 1.5
	pStroke.Transparency = 0.0

	-- Amber top accent stripe
	local panelStripe = Instance.new("Frame", panel)
	panelStripe.Size             = UDim2.new(1, 0, 0, 4)
	panelStripe.BackgroundColor3 = C_AMBER
	panelStripe.BorderSizePixel  = 0
	panelStripe.ZIndex           = 11

	--------------------------------------------------------------------
	-- HEADER BAR  (sidebar-style, warm tone)
	--------------------------------------------------------------------
	local header = Instance.new("Frame", panel)
	header.Size             = UDim2.new(1, 0, 0, 62)
	header.Position         = UDim2.new(0, 0, 0, 0)
	header.BackgroundColor3 = C_SIDEBAR
	header.BorderSizePixel  = 0
	header.ZIndex           = 11
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 20)

	-- Square off bottom corners of header
	local hFill = Instance.new("Frame", header)
	hFill.Size             = UDim2.new(1, 0, 0.5, 0)
	hFill.Position         = UDim2.new(0, 0, 0.5, 0)
	hFill.BackgroundColor3 = C_SIDEBAR
	hFill.BorderSizePixel  = 0
	hFill.ZIndex           = 11

	-- Amber stripe continues across header top
	local headerStripe = Instance.new("Frame", header)
	headerStripe.Size             = UDim2.new(1, 0, 0, 4)
	headerStripe.BackgroundColor3 = C_AMBER
	headerStripe.BorderSizePixel  = 0
	headerStripe.ZIndex           = 12

	-- Store monogram icon
	local headerIcon = Instance.new("Frame", header)
	headerIcon.Size             = UDim2.new(0, 36, 0, 36)
	headerIcon.Position         = UDim2.new(0, 14, 0.5, -18)
	headerIcon.BackgroundColor3 = C_AMBER
	headerIcon.BorderSizePixel  = 0
	headerIcon.ZIndex           = 13
	Instance.new("UICorner", headerIcon).CornerRadius = UDim.new(0, 10)

	local headerIconLbl = Instance.new("TextLabel", headerIcon)
	headerIconLbl.Size                   = UDim2.fromScale(1, 1)
	headerIconLbl.BackgroundTransparency = 1
	headerIconLbl.Text                   = "GP"   -- Game Passes
	headerIconLbl.TextColor3             = Color3.fromRGB(255, 255, 255)
	headerIconLbl.TextScaled             = true
	headerIconLbl.Font                   = Enum.Font.GothamBlack
	headerIconLbl.ZIndex                 = 14

	-- Title
	local titleLabel = Instance.new("TextLabel", header)
	titleLabel.Size                   = UDim2.new(1, -110, 0, 22)
	titleLabel.Position               = UDim2.new(0, 58, 0, 10)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text                   = "Shop"
	titleLabel.TextColor3             = C_INK
	titleLabel.TextScaled             = true
	titleLabel.Font                   = Enum.Font.GothamBlack
	titleLabel.TextXAlignment         = Enum.TextXAlignment.Left
	titleLabel.ZIndex                 = 13

	-- Subtitle
	local titleSub = Instance.new("TextLabel", header)
	titleSub.Size                   = UDim2.new(1, -110, 0, 16)
	titleSub.Position               = UDim2.new(0, 58, 0, 34)
	titleSub.BackgroundTransparency = 1
	titleSub.Text                   = "Game passes & upgrades"
	titleSub.TextColor3             = C_INK_MID
	titleSub.TextScaled             = true
	titleSub.Font                   = Enum.Font.Gotham
	titleSub.TextXAlignment         = Enum.TextXAlignment.Left
	titleSub.ZIndex                 = 13

	-- Close button (crimson, right side of header)
	local closeBtn = Instance.new("TextButton", header)
	closeBtn.Size             = UDim2.new(0, 70, 0, 30)
	closeBtn.Position         = UDim2.new(1, -82, 0.5, -15)
	closeBtn.BackgroundColor3 = C_CRIMSON_LT
	closeBtn.BorderSizePixel  = 0
	closeBtn.Text             = ""
	closeBtn.AutoButtonColor  = false
	closeBtn.ZIndex           = 13
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

	local closeLbl = Instance.new("TextLabel", closeBtn)
	closeLbl.Size                   = UDim2.fromScale(1, 1)
	closeLbl.BackgroundTransparency = 1
	closeLbl.Text                   = "CLOSE"
	closeLbl.TextColor3             = C_CRIMSON
	closeLbl.TextScaled             = true
	closeLbl.Font                   = Enum.Font.GothamBold
	closeLbl.ZIndex                 = 14

	closeBtn.MouseEnter:Connect(function()
		tw(closeBtn, TI_FAST, {BackgroundColor3 = C_CRIMSON})
		tw(closeLbl, TI_FAST, {TextColor3 = Color3.fromRGB(255, 255, 255)})
	end)
	closeBtn.MouseLeave:Connect(function()
		tw(closeBtn, TI_FAST, {BackgroundColor3 = C_CRIMSON_LT})
		tw(closeLbl, TI_FAST, {TextColor3 = C_CRIMSON})
	end)

	-- Hairline divider under header
	local headerLine = Instance.new("Frame", panel)
	headerLine.Size             = UDim2.new(1, -28, 0, 1)
	headerLine.Position         = UDim2.new(0, 14, 0, 63)
	headerLine.BackgroundColor3 = C_DIVIDER
	headerLine.BorderSizePixel  = 0
	headerLine.ZIndex           = 11

	--------------------------------------------------------------------
	-- SCROLLING ITEM LIST
	--------------------------------------------------------------------
	local scroll = Instance.new("ScrollingFrame", panel)
	scroll.Name                   = "ItemList"
	scroll.Size                   = UDim2.new(1, -20, 1, -80)
	scroll.Position               = UDim2.new(0, 10, 0, 72)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel        = 0
	scroll.ScrollBarThickness     = 4
	scroll.ScrollBarImageColor3   = C_DIVIDER
	scroll.CanvasSize             = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
	scroll.ZIndex                 = 11

	local listLayout = Instance.new("UIListLayout", scroll)
	listLayout.SortOrder     = Enum.SortOrder.LayoutOrder
	listLayout.Padding       = UDim.new(0, 10)
	listLayout.FillDirection = Enum.FillDirection.Vertical

	local listPad = Instance.new("UIPadding", scroll)
	listPad.PaddingTop    = UDim.new(0, 8)
	listPad.PaddingBottom = UDim.new(0, 8)
	listPad.PaddingLeft   = UDim.new(0, 2)
	listPad.PaddingRight  = UDim.new(0, 2)

	--------------------------------------------------------------------
	-- ITEM CARD FACTORY
	-- isGamepass=true → prompts MarketplaceService on buy click
	-- Design: white card, amber top bar, left icon pill, right buy button
	--------------------------------------------------------------------
	local function makeItemCard(layoutOrder, icon, name, desc, priceText, isGamepass, passId)
		local card = Instance.new("Frame", scroll)
		card.Name             = name
		card.LayoutOrder      = layoutOrder
		card.Size             = UDim2.new(1, 0, 0, 118)
		card.BackgroundColor3 = C_CARD
		card.BorderSizePixel  = 0
		card.ZIndex           = 12
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)

		-- Subtle border
		local cardStroke = Instance.new("UIStroke", card)
		cardStroke.Color        = C_DIVIDER
		cardStroke.Thickness    = 1
		cardStroke.Transparency = 0.0

		-- Amber top accent bar
		local cardBar = Instance.new("Frame", card)
		cardBar.Size             = UDim2.new(1, 0, 0, 4)
		cardBar.BackgroundColor3 = C_AMBER
		cardBar.BorderSizePixel  = 0
		cardBar.ZIndex           = 13
		Instance.new("UICorner", cardBar).CornerRadius = UDim.new(0, 14)
		local cbFill = Instance.new("Frame", cardBar)
		cbFill.Size             = UDim2.new(1, 0, 0.5, 0)
		cbFill.Position         = UDim2.new(0, 0, 0.5, 0)
		cbFill.BackgroundColor3 = C_AMBER
		cbFill.BorderSizePixel  = 0
		cbFill.ZIndex           = 13

		-- Icon pill (amber background, left side)
		local iconPill = Instance.new("Frame", card)
		iconPill.Size             = UDim2.new(0, 42, 0, 42)
		iconPill.Position         = UDim2.new(0, 14, 0.5, -21)
		iconPill.BackgroundColor3 = C_AMBER_LIGHT
		iconPill.BorderSizePixel  = 0
		iconPill.ZIndex           = 13
		Instance.new("UICorner", iconPill).CornerRadius = UDim.new(0, 12)

		local iconLbl = Instance.new("TextLabel", iconPill)
		iconLbl.Size                   = UDim2.fromScale(1, 1)
		iconLbl.BackgroundTransparency = 1
		iconLbl.Text                   = icon
		iconLbl.TextColor3             = C_AMBER
		iconLbl.TextScaled             = true
		iconLbl.Font                   = Enum.Font.GothamBlack
		iconLbl.ZIndex                 = 14

		-- Item name
		local nameLabel = Instance.new("TextLabel", card)
		nameLabel.Size                   = UDim2.new(1, -76, 0, 22)
		nameLabel.Position               = UDim2.new(0, 68, 0, 14)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text                   = name
		nameLabel.TextColor3             = C_INK
		nameLabel.TextScaled             = true
		nameLabel.Font                   = Enum.Font.GothamBlack
		nameLabel.TextXAlignment         = Enum.TextXAlignment.Left
		nameLabel.ZIndex                 = 13

		-- Description
		local descLabel = Instance.new("TextLabel", card)
		descLabel.Size                   = UDim2.new(1, -76, 0, 34)
		descLabel.Position               = UDim2.new(0, 68, 0, 38)
		descLabel.BackgroundTransparency = 1
		descLabel.Text                   = desc
		descLabel.TextColor3             = C_INK_MID
		descLabel.TextScaled             = true
		descLabel.Font                   = Enum.Font.Gotham
		descLabel.TextXAlignment         = Enum.TextXAlignment.Left
		descLabel.TextWrapped            = true
		descLabel.ZIndex                 = 13

		-- Buy button (teal, full width bottom strip)
		local buyBtn = Instance.new("TextButton", card)
		buyBtn.Size             = UDim2.new(1, -24, 0, 28)
		buyBtn.Position         = UDim2.new(0, 12, 1, -36)
		buyBtn.BackgroundColor3 = C_TEAL
		buyBtn.BorderSizePixel  = 0
		buyBtn.Text             = priceText
		buyBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
		buyBtn.TextScaled       = true
		buyBtn.Font             = Enum.Font.GothamBlack
		buyBtn.ZIndex           = 13
		Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 8)

		-- Card hover
		local function setHover(on)
			if on then
				tw(card, TI_FAST, {BackgroundColor3 = C_TEAL_LIGHT})
				tw(cardStroke, TI_FAST, {Transparency = 0.5})
			else
				tw(card, TI_FAST, {BackgroundColor3 = C_CARD})
				tw(cardStroke, TI_FAST, {Transparency = 0.0})
			end
		end
		card.MouseEnter:Connect(function() setHover(true) end)
		card.MouseLeave:Connect(function() setHover(false) end)

		-- Buy button hover
		buyBtn.MouseEnter:Connect(function()
			tw(buyBtn, TI_FAST, {BackgroundColor3 = Color3.fromRGB(18, 148, 120)})
		end)
		buyBtn.MouseLeave:Connect(function()
			tw(buyBtn, TI_FAST, {BackgroundColor3 = C_TEAL})
		end)

		--------------------------------------------------------------------
		-- GAMEPASS LOGIC  (identical to original)
		--------------------------------------------------------------------
		if isGamepass and passId and passId ~= 0 then
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(passId, Enum.InfoType.GamePass)
				end)
				if ok and info then
					buyBtn.Text = string.format("R$ %s", tostring(info.PriceInRobux or "?"))
				end
			end)

			buyBtn.MouseButton1Click:Connect(function()
				MarketplaceService:PromptGamePassPurchase(player, passId)
			end)

		elseif passId == 0 then
			buyBtn.Text                  = "ID not set"
			buyBtn.BackgroundColor3      = C_DIVIDER
			buyBtn.TextColor3            = C_INK_FAINT
			buyBtn.Active                = false
		end

		return card
	end

	--------------------------------------------------------------------
	-- AUTO-COLLECT GAMEPASS CARD  (LayoutOrder = 1, always pinned first)
	--------------------------------------------------------------------
	makeItemCard(
		1,
		"AC",                    -- "Auto-Collect" abbreviation, ASCII-safe
		AUTO_COLLECT_NAME,
		AUTO_COLLECT_DESC,
		AUTO_COLLECT_PRICE,
		true,
		AUTO_COLLECT_GAMEPASS_ID
	)

	--------------------------------------------------------------------
	-- OPEN / CLOSE ANIMATION  (slide in from right, identical logic)
	--------------------------------------------------------------------
	local panelOpen = false
	local OPEN_POS  = UDim2.new(1, -(PANEL_W + 14), 0.5, -PANEL_H / 2)
	local CLOSE_POS = UDim2.new(1,  10,              0.5, -PANEL_H / 2)

	local OPEN_SHADOW  = UDim2.new(1, -(PANEL_W + 18), 0.5, -PANEL_H / 2 - 4)
	local CLOSE_SHADOW = UDim2.new(1,  14,              0.5, -PANEL_H / 2 - 4)

	local function openPanel()
		panel.Visible       = true
		panelShadow.Visible = true
		panelOpen           = true
		tw(panel,       TI_SLIDE, {Position = OPEN_POS})
		tw(panelShadow, TI_SLIDE, {Position = OPEN_SHADOW})
	end

	local function closePanel()
		panelOpen = false
		tw(panel,       TI_SLIDE, {Position = CLOSE_POS})
		tw(panelShadow, TI_SLIDE, {Position = CLOSE_SHADOW})
		task.delay(0.32, function()
			if not panelOpen then
				panel.Visible       = false
				panelShadow.Visible = false
			end
		end)
	end

	storeBtn.MouseButton1Click:Connect(function()
		if panelOpen then closePanel() else openPanel() end
	end)
	closeBtn.MouseButton1Click:Connect(closePanel)

	return label
end

----------------------------------------------------------------------
-- INITIALISE
----------------------------------------------------------------------
local balanceLabel = getOrCreateGui()

local remotes   = ReplicatedStorage:WaitForChild("MoneyRemotes", 15)
local evtUpdate = remotes and remotes:WaitForChild("UpdateBalance", 15)

if evtUpdate then
	evtUpdate.OnClientEvent:Connect(function(newBalance)
		if balanceLabel then
			print()   -- kept identical to original
			balanceLabel.Text = string.format("$%s", math.floor(newBalance))
		end
	end)
end

----------------------------------------------------------------------
-- OFFLINE EARNINGS TOAST
-- Brief banner crediting money earned while offline.
-- Slides in from top, holds for 4s, slides back out.
----------------------------------------------------------------------
local evtOffline = remotes and remotes:WaitForChild("OfflineEarnings", 15)

local function showOfflineToast(amount, seconds)
	local gui = playerGui:FindFirstChild("MoneyGui")
	if not gui then return end

	local mins = math.floor(seconds / 60)
	local secs = seconds % 60
	local timeStr
	if mins > 0 then
		timeStr = string.format("%dm %ds", mins, secs)
	else
		timeStr = string.format("%ds", secs)
	end

	-- Toast frame (light theme: white card, teal accent)
	local toast = Instance.new("Frame")
	toast.Size                   = UDim2.new(0, 300, 0, 68)
	toast.Position               = UDim2.new(0.5, -150, 0, -80)
	toast.BackgroundColor3       = C_CARD
	toast.BackgroundTransparency = 0
	toast.BorderSizePixel        = 0
	toast.ZIndex                 = 20
	toast.Parent                 = gui
	Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 14)

	local toastStroke = Instance.new("UIStroke", toast)
	toastStroke.Color        = C_TEAL
	toastStroke.Thickness    = 2
	toastStroke.Transparency = 0.0

	-- Teal top stripe
	local toastStripe = Instance.new("Frame", toast)
	toastStripe.Size             = UDim2.new(1, 0, 0, 4)
	toastStripe.BackgroundColor3 = C_TEAL
	toastStripe.BorderSizePixel  = 0
	toastStripe.ZIndex           = 21
	Instance.new("UICorner", toastStripe).CornerRadius = UDim.new(0, 14)
	local tsFill = Instance.new("Frame", toastStripe)
	tsFill.Size             = UDim2.new(1, 0, 0.5, 0)
	tsFill.Position         = UDim2.new(0, 0, 0.5, 0)
	tsFill.BackgroundColor3 = C_TEAL
	tsFill.BorderSizePixel  = 0
	tsFill.ZIndex           = 21

	-- Icon pill
	local toastIcon = Instance.new("Frame", toast)
	toastIcon.Size             = UDim2.new(0, 36, 0, 36)
	toastIcon.Position         = UDim2.new(0, 14, 0.5, -18)
	toastIcon.BackgroundColor3 = C_TEAL_LIGHT
	toastIcon.BorderSizePixel  = 0
	toastIcon.ZIndex           = 22
	Instance.new("UICorner", toastIcon).CornerRadius = UDim.new(0, 10)

	local toastIconLbl = Instance.new("TextLabel", toastIcon)
	toastIconLbl.Size                   = UDim2.fromScale(1, 1)
	toastIconLbl.BackgroundTransparency = 1
	toastIconLbl.Text                   = "ZZ"
	toastIconLbl.TextColor3             = C_TEAL
	toastIconLbl.TextScaled             = true
	toastIconLbl.Font                   = Enum.Font.GothamBlack
	toastIconLbl.ZIndex                 = 23

	-- Main line
	local toastTitle = Instance.new("TextLabel", toast)
	toastTitle.Size                   = UDim2.new(1, -62, 0, 24)
	toastTitle.Position               = UDim2.new(0, 58, 0, 12)
	toastTitle.BackgroundTransparency = 1
	toastTitle.Text                   = string.format("Offline earnings: +$%s", math.floor(amount))
	toastTitle.TextColor3             = C_INK
	toastTitle.TextScaled             = true
	toastTitle.Font                   = Enum.Font.GothamBlack
	toastTitle.TextXAlignment         = Enum.TextXAlignment.Left
	toastTitle.ZIndex                 = 22

	-- Sub line
	local toastSub = Instance.new("TextLabel", toast)
	toastSub.Size                   = UDim2.new(1, -62, 0, 18)
	toastSub.Position               = UDim2.new(0, 58, 0, 38)
	toastSub.BackgroundTransparency = 1
	toastSub.Text                   = string.format("You were away for %s", timeStr)
	toastSub.TextColor3             = C_INK_MID
	toastSub.TextScaled             = true
	toastSub.Font                   = Enum.Font.Gotham
	toastSub.TextXAlignment         = Enum.TextXAlignment.Left
	toastSub.ZIndex                 = 22

	-- Slide in
	toast:TweenPosition(
		UDim2.new(0.5, -150, 0, 10),
		Enum.EasingDirection.Out,
		Enum.EasingStyle.Back,
		0.38,
		true
	)

	task.wait(4)

	-- Slide back out
	toast:TweenPosition(
		UDim2.new(0.5, -150, 0, -80),
		Enum.EasingDirection.In,
		Enum.EasingStyle.Quint,
		0.30,
		true
	)
	task.wait(0.35)
	toast:Destroy()
end

if evtOffline then
	evtOffline.OnClientEvent:Connect(function(amount, seconds)
		task.spawn(showOfflineToast, amount, seconds)
	end)
end