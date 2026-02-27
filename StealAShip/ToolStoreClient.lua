-- ToolStoreClient  (LocalScript, StarterPlayerScripts)
--
-- Listens for the OpenToolStore RemoteEvent from ToolStoreServer, then
-- builds a scrollable store panel with one card per tool.
--
-- Each card shows:
--   • A viewport frame rendering a live 3D preview of the tool model
--   • The tool's display name  (tool:GetAttribute("name"))
--   • The price               (tool:GetAttribute("price"))
--   • An "owned" badge when the player already has it, or a Buy button
--
-- Clicking Buy fires BuyTool to the server.
-- The server replies via BuyResult; on success the button turns to "Owned".

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------------
-- REMOTES
----------------------------------------------------------------------
local storeRemotes = ReplicatedStorage:WaitForChild("ToolStoreRemotes", 20)
local evtOpen      = storeRemotes:WaitForChild("OpenToolStore", 10)
local evtBuy       = storeRemotes:WaitForChild("BuyTool",       10)
local evtResult    = storeRemotes:WaitForChild("BuyResult",     10)

local toolsFolder  = ReplicatedStorage:WaitForChild("Tools", 20)

----------------------------------------------------------------------
-- COLOURS / SIZES
----------------------------------------------------------------------
local CLR_BG        = Color3.fromRGB(10, 14, 26)
local CLR_CARD      = Color3.fromRGB(18, 26, 46)
local CLR_BORDER    = Color3.fromRGB(80, 180, 255)
local CLR_GOLD      = Color3.fromRGB(255, 200, 50)
local CLR_GREEN     = Color3.fromRGB(60, 220, 100)
local CLR_RED       = Color3.fromRGB(220, 60, 60)
local CLR_OWNED     = Color3.fromRGB(40, 40, 60)
local CLR_TITLE_BAR = Color3.fromRGB(20, 90, 180)

local PANEL_W, PANEL_H = 420, 520
local CARD_H           = 120
local CARD_PAD         = 10
local TWEEN_IN  = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEEN_OUT = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

----------------------------------------------------------------------
-- GUI CONSTRUCTION
----------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name          = "ToolStoreGui"
gui.ResetOnSpawn  = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled       = false
gui.Parent        = playerGui

-- Dim overlay
local overlay = Instance.new("Frame", gui)
overlay.Name                   = "Overlay"
overlay.Size                   = UDim2.fromScale(1, 1)
overlay.BackgroundColor3       = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 0.5
overlay.BorderSizePixel        = 0
overlay.ZIndex                 = 1

-- Main panel
local panel = Instance.new("Frame", gui)
panel.Name                   = "StorePanel"
panel.Size                   = UDim2.new(0, PANEL_W, 0, PANEL_H)
panel.Position               = UDim2.new(0.5, -PANEL_W / 2, 0.5, -PANEL_H / 2)
panel.BackgroundColor3       = CLR_BG
panel.BackgroundTransparency = 0
panel.BorderSizePixel        = 0
panel.ZIndex                 = 2
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Color     = CLR_BORDER
panelStroke.Thickness = 1.5

-- Title bar
local titleBar = Instance.new("Frame", panel)
titleBar.Size             = UDim2.new(1, 0, 0, 52)
titleBar.BackgroundColor3 = CLR_TITLE_BAR
titleBar.BorderSizePixel  = 0
titleBar.ZIndex           = 3
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 14)
-- square off bottom corners
local titleFill = Instance.new("Frame", titleBar)
titleFill.Size             = UDim2.new(1, 0, 0.5, 0)
titleFill.Position         = UDim2.new(0, 0, 0.5, 0)
titleFill.BackgroundColor3 = CLR_TITLE_BAR
titleFill.BorderSizePixel  = 0
titleFill.ZIndex           = 3

local titleLabel = Instance.new("TextLabel", titleBar)
titleLabel.Size                   = UDim2.new(1, -52, 1, 0)
titleLabel.Position               = UDim2.new(0, 14, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text                   = "🛠  Tool Shop"
titleLabel.TextColor3             = Color3.new(1, 1, 1)
titleLabel.TextScaled             = true
titleLabel.Font                   = Enum.Font.GothamBold
titleLabel.TextXAlignment         = Enum.TextXAlignment.Left
titleLabel.ZIndex                 = 4

local closeBtn = Instance.new("TextButton", titleBar)
closeBtn.Size             = UDim2.new(0, 36, 0, 36)
closeBtn.Position         = UDim2.new(1, -44, 0.5, -18)
closeBtn.BackgroundColor3 = CLR_RED
closeBtn.BorderSizePixel  = 0
closeBtn.Text             = "✕"
closeBtn.TextColor3       = Color3.new(1, 1, 1)
closeBtn.TextScaled       = true
closeBtn.Font             = Enum.Font.GothamBold
closeBtn.ZIndex           = 5
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

-- Scrolling list of cards
local scroll = Instance.new("ScrollingFrame", panel)
scroll.Name                   = "ItemList"
scroll.Size                   = UDim2.new(1, -16, 1, -60)
scroll.Position               = UDim2.new(0, 8, 0, 56)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel        = 0
scroll.ScrollBarThickness     = 5
scroll.ScrollBarImageColor3   = CLR_BORDER
scroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
scroll.CanvasSize             = UDim2.new(0, 0, 0, 0)
scroll.ZIndex                 = 3

local listLayout = Instance.new("UIListLayout", scroll)
listLayout.SortOrder      = Enum.SortOrder.LayoutOrder
listLayout.Padding        = UDim.new(0, CARD_PAD)
listLayout.FillDirection  = Enum.FillDirection.Vertical

Instance.new("UIPadding", scroll).PaddingTop = UDim.new(0, 4)

----------------------------------------------------------------------
-- TOAST NOTIFICATION
----------------------------------------------------------------------
local function showToast(message, success)
	local existing = gui:FindFirstChild("Toast")
	if existing then existing:Destroy() end

	local toast = Instance.new("Frame", gui)
	toast.Name                   = "Toast"
	toast.Size                   = UDim2.new(0, 340, 0, 52)
	toast.Position               = UDim2.new(0.5, -170, 1, 10)
	toast.BackgroundColor3       = success and Color3.fromRGB(20, 60, 20) or Color3.fromRGB(60, 20, 20)
	toast.BackgroundTransparency = 0.1
	toast.BorderSizePixel        = 0
	toast.ZIndex                 = 20
	Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 10)
	local s = Instance.new("UIStroke", toast)
	s.Color     = success and CLR_GREEN or CLR_RED
	s.Thickness = 1.5

	local lbl = Instance.new("TextLabel", toast)
	lbl.Size                   = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text                   = message
	lbl.TextColor3             = success and CLR_GREEN or Color3.fromRGB(255, 100, 100)
	lbl.TextScaled             = true
	lbl.Font                   = Enum.Font.GothamBold
	lbl.ZIndex                 = 21
	lbl.TextWrapped            = true

	TweenService:Create(toast, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, -170, 1, -70) }):Play()
	task.delay(3, function()
		if toast and toast.Parent then
			TweenService:Create(toast, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
				{ Position = UDim2.new(0.5, -170, 1, 10) }):Play()
			task.wait(0.3)
			toast:Destroy()
		end
	end)
end

----------------------------------------------------------------------
-- VIEWPORT PREVIEW
-- Clones the tool model into a ViewportFrame so players can see what
-- they're buying as a live 3D render.
----------------------------------------------------------------------
local function makeViewport(parent, toolTemplate)
	local vp = Instance.new("ViewportFrame", parent)
	vp.Size                   = UDim2.new(0, CARD_H - 16, 1, -16)
	vp.Position               = UDim2.new(0, 8, 0, 8)
	vp.BackgroundColor3       = Color3.fromRGB(8, 12, 22)
	vp.BackgroundTransparency = 0
	vp.BorderSizePixel        = 0
	vp.LightDirection         = Vector3.new(-1, -2, -1)
	vp.LightColor             = Color3.new(1, 1, 1)
	vp.Ambient                = Color3.fromRGB(180, 180, 180)
	Instance.new("UICorner", vp).CornerRadius = UDim.new(0, 8)

	-- Clone the tool into the viewport
	local clone = toolTemplate:Clone()
	clone.Parent = vp

	-- Position camera to frame the tool nicely
	local cf = CFrame.new()
	local size = Vector3.new(1, 1, 1)
	if clone:IsA("Tool") then
		local handle = clone:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			cf   = handle.CFrame
			size = handle.Size
		end
	end

	local cam = Instance.new("Camera", vp)
	cam.CFrame     = CFrame.new(
		cf.Position + Vector3.new(0, size.Y * 0.6, size.Z * 2.2),
		cf.Position
	)
	vp.CurrentCamera = cam

	return vp
end

----------------------------------------------------------------------
-- BUILD ONE TOOL CARD
----------------------------------------------------------------------
-- buyButtons table maps toolId → button, so BuyResult can update it
local buyButtons = {}

local function makeCard(layoutOrder, entry)
	local toolTemplate = toolsFolder and toolsFolder:FindFirstChild(entry.id)

	local card = Instance.new("Frame", scroll)
	card.Name                   = entry.id
	card.LayoutOrder            = layoutOrder
	card.Size                   = UDim2.new(1, 0, 0, CARD_H)
	card.BackgroundColor3       = CLR_CARD
	card.BorderSizePixel        = 0
	card.ZIndex                 = 4
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)
	local cardStroke = Instance.new("UIStroke", card)
	cardStroke.Color     = CLR_BORDER
	cardStroke.Thickness = 1

	-- 3D preview (left side)
	if toolTemplate then
		pcall(makeViewport, card, toolTemplate)
	end

	local infoX = CARD_H + 8   -- pixels from left where text starts

	-- Tool name
	local nameLabel = Instance.new("TextLabel", card)
	nameLabel.Size                   = UDim2.new(1, -(infoX + 8), 0, 32)
	nameLabel.Position               = UDim2.new(0, infoX, 0, 10)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text                   = entry.name
	nameLabel.TextColor3             = CLR_GOLD
	nameLabel.TextScaled             = true
	nameLabel.Font                   = Enum.Font.GothamBold
	nameLabel.TextXAlignment         = Enum.TextXAlignment.Left
	nameLabel.ZIndex                 = 5

	-- Price label
	local priceLabel = Instance.new("TextLabel", card)
	priceLabel.Size                   = UDim2.new(1, -(infoX + 8), 0, 24)
	priceLabel.Position               = UDim2.new(0, infoX, 0, 44)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Text                   = entry.price == 0 and "Free" or string.format("💰 $%g", entry.price)
	priceLabel.TextColor3             = entry.price == 0 and CLR_GREEN or Color3.fromRGB(200, 200, 200)
	priceLabel.TextScaled             = true
	priceLabel.Font                   = Enum.Font.Gotham
	priceLabel.TextXAlignment         = Enum.TextXAlignment.Left
	priceLabel.ZIndex                 = 5

	-- Buy / Owned button
	local btn = Instance.new("TextButton", card)
	btn.Size             = UDim2.new(1, -(infoX + 12), 0, 30)
	btn.Position         = UDim2.new(0, infoX, 1, -40)
	btn.BorderSizePixel  = 0
	btn.TextScaled       = true
	btn.Font             = Enum.Font.GothamBold
	btn.ZIndex           = 5
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)

	local function setOwned()
		btn.Text             = "✅ Owned"
		btn.BackgroundColor3 = CLR_OWNED
		btn.TextColor3       = Color3.fromRGB(120, 200, 120)
		btn.Active           = false
		cardStroke.Color     = CLR_GREEN
	end

	local function setAvailable()
		btn.Text             = entry.price == 0 and "Get for Free" or ("Buy for $" .. tostring(entry.price))
		btn.BackgroundColor3 = Color3.fromRGB(30, 120, 200)
		btn.TextColor3       = Color3.new(1, 1, 1)
		btn.Active           = true
	end

	if entry.owned then
		setOwned()
	else
		setAvailable()
		btn.MouseButton1Click:Connect(function()
			if not btn.Active then return end
			btn.Text   = "⏳ Buying…"
			btn.Active = false
			evtBuy:FireServer(entry.id)
		end)
	end

	buyButtons[entry.id] = { btn = btn, setOwned = setOwned, setAvailable = setAvailable }
	return card
end

----------------------------------------------------------------------
-- OPEN / CLOSE
----------------------------------------------------------------------
local panelOpen = false

local function openStore(catalogue)
	-- Clear previous cards
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	buyButtons = {}

	-- Build a card for each tool
	for i, entry in ipairs(catalogue) do
		makeCard(i, entry)
	end

	gui.Enabled = true
	panelOpen   = true

	panel.Position = UDim2.new(0.5, -PANEL_W / 2, 0.5, -PANEL_H / 2 - 40)
	panel.BackgroundTransparency = 1
	TweenService:Create(panel, TWEEN_IN, {
		Position               = UDim2.new(0.5, -PANEL_W / 2, 0.5, -PANEL_H / 2),
		BackgroundTransparency = 0,
	}):Play()
end

local function closeStore()
	panelOpen = false
	TweenService:Create(panel, TWEEN_OUT, {
		Position               = UDim2.new(0.5, -PANEL_W / 2, 0.5, -PANEL_H / 2 + 30),
		BackgroundTransparency = 1,
	}):Play()
	task.delay(0.3, function()
		if not panelOpen then
			gui.Enabled = false
		end
	end)
end

closeBtn.MouseButton1Click:Connect(closeStore)
overlay.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		closeStore()
	end
end)

----------------------------------------------------------------------
-- REMOTE LISTENERS
----------------------------------------------------------------------
evtOpen.OnClientEvent:Connect(function(catalogue)
	openStore(catalogue)
end)

evtResult.OnClientEvent:Connect(function(success, message)
	showToast(message, success)

	if success then
		-- Find which button is in the "Buying…" state and flip it to Owned
		for _, entry in pairs(buyButtons) do
			if entry.btn.Text == "⏳ Buying…" then
				entry.setOwned()
				break
			end
		end
	else
		-- Restore the button to its previous available state
		for _, entry in pairs(buyButtons) do
			if entry.btn.Text == "⏳ Buying…" then
				entry.setAvailable()
				break
			end
		end
	end
end)
