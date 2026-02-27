-- AdminClient.lua  (LocalScript → StarterPlayerScripts)
-- Full admin panel UI. Script exits silently if the player is not an admin.

local Players         = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService    = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer

----------------------------------------------------------------------
-- REMOTES
----------------------------------------------------------------------
local remotes     = ReplicatedStorage:WaitForChild("MoneyRemotes", 15)
local adminRemote = remotes:WaitForChild("AdminCommand",   15)
local adminEvent  = remotes:WaitForChild("AdminBroadcast", 15)

----------------------------------------------------------------------
-- ADMIN CHECK  — panel stays hidden for non-admins unless granted
----------------------------------------------------------------------
local checkResult = adminRemote:InvokeServer("isAdmin")
local isAdminAtJoin = checkResult and checkResult.success == true

----------------------------------------------------------------------
-- COLORS / STYLE
----------------------------------------------------------------------
local C = {
	bg         = Color3.fromRGB(18,  18,  24),
	panel      = Color3.fromRGB(26,  26,  36),
	tab        = Color3.fromRGB(36,  36,  50),
	tabActive   = Color3.fromRGB(50,  50,  72),
	accent      = Color3.fromRGB(220, 80,  80),
	accentGreen = Color3.fromRGB(60,  200, 110),
	accentGold  = Color3.fromRGB(255, 200, 40),
	accentBlue  = Color3.fromRGB(60,  160, 255),
	text        = Color3.fromRGB(230, 230, 240),
	subtext     = Color3.fromRGB(140, 140, 160),
	btn         = Color3.fromRGB(60,  60,  85),
	btnHover    = Color3.fromRGB(80,  80, 110),
	btnRed      = Color3.fromRGB(180, 50,  50),
	btnGreen    = Color3.fromRGB(40,  160, 80),
	btnGold     = Color3.fromRGB(180, 140, 20),
	inputBg     = Color3.fromRGB(30,  30,  44),
}

----------------------------------------------------------------------
-- HELPER BUILDERS
----------------------------------------------------------------------
local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	if parent then inst.Parent = parent end
	return inst
end

local function makeBtn(text, color, parent, size, pos)
	local btn = make("TextButton", {
		Text            = text,
		Size            = size  or UDim2.new(0, 120, 0, 32),
		Position        = pos   or UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = color or C.btn,
		TextColor3      = C.text,
		Font            = Enum.Font.GothamBold,
		TextSize        = 14,
		BorderSizePixel = 0,
		AutoButtonColor = true,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, btn)
	return btn
end

local function makeLabel(text, parent, size, pos, textColor, fontSize, font)
	return make("TextLabel", {
		Text            = text,
		Size            = size      or UDim2.new(1, 0, 0, 24),
		Position        = pos       or UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1,
		TextColor3      = textColor or C.text,
		Font            = font      or Enum.Font.Gotham,
		TextSize        = fontSize  or 14,
		TextXAlignment  = Enum.TextXAlignment.Left,
	}, parent)
end

local function makeInput(placeholder, parent, size, pos)
	local box = make("TextBox", {
		PlaceholderText  = placeholder,
		Text             = "",
		Size             = size or UDim2.new(1, 0, 0, 32),
		Position         = pos  or UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = C.inputBg,
		TextColor3       = C.text,
		PlaceholderColor3= C.subtext,
		Font             = Enum.Font.Gotham,
		TextSize         = 14,
		BorderSizePixel  = 0,
		ClearTextOnFocus = false,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, box)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
	}, box)
	return box
end

local function makeSeparator(parent)
	local f = make("Frame", {
		Size            = UDim2.new(1, -16, 0, 1),
		Position        = UDim2.new(0, 8, 0, 0),
		BackgroundColor3 = Color3.fromRGB(55, 55, 75),
		BorderSizePixel = 0,
	}, parent)
	return f
end

-- Hover effect
local function addHover(btn, normalColor, hoverColor)
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = hoverColor }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = normalColor }):Play()
	end)
end

-- Toast notification at bottom of screen
local toastGui
local function toast(msg, color)
	if toastGui then toastGui:Destroy() end
	local sg = make("ScreenGui", {
		Name           = "AdminToast",
		ResetOnSpawn   = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, localPlayer.PlayerGui)
	toastGui = sg

	local frame = make("Frame", {
		Size            = UDim2.new(0, 380, 0, 48),
		Position        = UDim2.new(0.5, -190, 1, 10),
		BackgroundColor3 = color or C.accentGold,
		BorderSizePixel  = 0,
	}, sg)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, frame)
	make("TextLabel", {
		Text        = msg,
		Size        = UDim2.new(1, -16, 1, 0),
		Position    = UDim2.new(0, 8, 0, 0),
		BackgroundTransparency = 1,
		TextColor3  = Color3.new(1,1,1),
		Font        = Enum.Font.GothamBold,
		TextSize    = 15,
		TextWrapped = true,
	}, frame)

	TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Back),
		{ Position = UDim2.new(0.5, -190, 1, -70) }):Play()
	task.delay(2.8, function()
		if sg.Parent then
			TweenService:Create(frame, TweenInfo.new(0.3),
				{ Position = UDim2.new(0.5, -190, 1, 10) }):Play()
			task.delay(0.35, function() sg:Destroy() end)
		end
	end)
end

----------------------------------------------------------------------
-- ANNOUNCEMENT BANNER (from AdminBroadcast)
----------------------------------------------------------------------
local annGui
local function showAnnouncement(msg, color)
	if annGui then annGui:Destroy() end
	local sg = make("ScreenGui", {
		Name           = "AdminAnnouncement",
		ResetOnSpawn   = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, localPlayer.PlayerGui)
	annGui = sg

	local banner = make("Frame", {
		Size            = UDim2.new(1, 0, 0, 60),
		Position        = UDim2.new(0, 0, 0, -70),
		BackgroundColor3 = color or C.accentGold,
		BorderSizePixel  = 0,
	}, sg)
	make("TextLabel", {
		Text        = msg,
		Size        = UDim2.new(1, -20, 1, 0),
		Position    = UDim2.new(0, 10, 0, 0),
		BackgroundTransparency = 1,
		TextColor3  = Color3.new(1,1,1),
		Font        = Enum.Font.GothamBold,
		TextSize    = 16,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, banner)

	TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Back),
		{ Position = UDim2.new(0, 0, 0, 0) }):Play()
	task.delay(4, function()
		if sg.Parent then
			TweenService:Create(banner, TweenInfo.new(0.3),
				{ Position = UDim2.new(0, 0, 0, -70) }):Play()
			task.delay(0.35, function() sg:Destroy() end)
		end
	end)
end

----------------------------------------------------------------------
-- MAIN SCREEN GUI
----------------------------------------------------------------------
local screenGui = make("ScreenGui", {
	Name           = "AdminPanel",
	ResetOnSpawn   = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, localPlayer.PlayerGui)

----------------------------------------------------------------------
-- TOGGLE BUTTON (bottom-right corner)
----------------------------------------------------------------------
local toggleBtn = make("TextButton", {
	Text            = "⚡ ADMIN",
	Size            = UDim2.new(0, 110, 0, 36),
	Position        = UDim2.new(1, -120, 1, -50),
	BackgroundColor3 = C.accentGold,
	TextColor3      = Color3.fromRGB(20, 20, 20),
	Font            = Enum.Font.GothamBlack,
	TextSize        = 15,
	BorderSizePixel = 0,
	ZIndex          = 20,
	Visible         = isAdminAtJoin,   -- hidden for non-admins until granted
}, screenGui)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, toggleBtn)
addHover(toggleBtn, C.accentGold, Color3.fromRGB(255, 220, 70))

----------------------------------------------------------------------
-- MAIN PANEL
----------------------------------------------------------------------
local panelOpen = false
local PANEL_W, PANEL_H = 720, 500

local panel = make("Frame", {
	Name            = "Panel",
	Size            = UDim2.new(0, PANEL_W, 0, PANEL_H),
	Position        = UDim2.new(0.5, -PANEL_W/2, 0.5, -PANEL_H/2),
	BackgroundColor3 = C.bg,
	BorderSizePixel  = 0,
	Visible          = false,
	ZIndex           = 10,
}, screenGui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, panel)
make("UIStroke", {
	Color     = C.accentGold,
	Thickness = 1.5,
}, panel)

-- Title bar
local titleBar = make("Frame", {
	Size            = UDim2.new(1, 0, 0, 44),
	BackgroundColor3 = C.accentGold,
	BorderSizePixel  = 0,
	ZIndex           = 11,
}, panel)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, titleBar)
-- Bottom part of rounded titlebar: cover bottom corners
make("Frame", {
	Size             = UDim2.new(1, 0, 0.5, 0),
	Position         = UDim2.new(0, 0, 0.5, 0),
	BackgroundColor3 = C.accentGold,
	BorderSizePixel  = 0,
	ZIndex           = 11,
}, titleBar)

make("TextLabel", {
	Text        = "⚡  ADMIN PANEL",
	Size        = UDim2.new(1, -50, 1, 0),
	Position    = UDim2.new(0, 14, 0, 0),
	BackgroundTransparency = 1,
	TextColor3  = Color3.fromRGB(20, 20, 20),
	Font        = Enum.Font.GothamBlack,
	TextSize    = 18,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex       = 12,
}, titleBar)

-- Close button
local closeBtn = make("TextButton", {
	Text            = "✕",
	Size            = UDim2.new(0, 36, 0, 36),
	Position        = UDim2.new(1, -40, 0, 4),
	BackgroundColor3 = Color3.fromRGB(200, 50, 50),
	TextColor3      = Color3.new(1,1,1),
	Font            = Enum.Font.GothamBold,
	TextSize        = 16,
	BorderSizePixel = 0,
	ZIndex          = 13,
}, titleBar)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, closeBtn)

----------------------------------------------------------------------
-- TAB BAR  (left sidebar, below title bar)
-- Buttons are positioned manually by Y offset — no UIListLayout, no
-- UICorner cover hack — nothing to accidentally push them out of place.
----------------------------------------------------------------------
local TAB_NAMES  = { "🎭 Spawn", "👥 Players", "🌍 World", "💰 Money", "📢 Announce" }
local tabBtns    = {}
local pages      = {}
local activeTab  = 0

-- switchTab must be declared before the button loop so the closures can see it
local function switchTab(idx)
	activeTab = idx
	for i, btn in ipairs(tabBtns) do
		btn.BackgroundColor3 = (i == idx) and C.tabActive or C.tab
		btn.TextColor3       = (i == idx) and C.accentGold or C.text
		btn.Font             = (i == idx) and Enum.Font.GothamBold or Enum.Font.Gotham
	end
	for i, page in ipairs(pages) do
		page.Visible = (i == idx)
	end
end

local tabBar = make("Frame", {
	Size             = UDim2.new(0, 148, 1, -52),
	Position         = UDim2.new(0, 4, 0, 48),
	BackgroundColor3 = C.panel,
	BorderSizePixel  = 0,
	ClipsDescendants = true,
}, panel)

local TAB_BTN_H   = 42
local TAB_BTN_GAP = 4
local TAB_PAD_TOP = 8

for i, name in ipairs(TAB_NAMES) do
	local yPos = TAB_PAD_TOP + (i - 1) * (TAB_BTN_H + TAB_BTN_GAP)
	local btn = make("TextButton", {
		Text             = name,
		Size             = UDim2.new(1, -8, 0, TAB_BTN_H),
		Position         = UDim2.new(0, 4, 0, yPos),
		BackgroundColor3 = C.tab,
		TextColor3       = C.text,
		Font             = Enum.Font.Gotham,
		TextSize         = 13,
		BorderSizePixel  = 0,
		TextXAlignment   = Enum.TextXAlignment.Left,
	}, tabBar)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, btn)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10) }, btn)
	tabBtns[i] = btn
	btn.MouseButton1Click:Connect(function() switchTab(i) end)
end

----------------------------------------------------------------------
-- CONTENT AREA  (right side, below title bar)
----------------------------------------------------------------------
local contentArea = make("Frame", {
	Size             = UDim2.new(1, -164, 1, -58),
	Position         = UDim2.new(0, 158, 0, 53),
	BackgroundColor3 = C.panel,
	BorderSizePixel  = 0,
	ClipsDescendants = true,
}, panel)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, contentArea)

local function makePage()
	local f = make("Frame", {
		Size             = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Visible          = false,
		ClipsDescendants = true,
	}, contentArea)
	return f
end

----------------------------------------------------------------------
-- SCROLLING LIST HELPER
----------------------------------------------------------------------
local function makeScrollFrame(parent, canvasH)
	local scroll = make("ScrollingFrame", {
		Size             = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.accentGold,
		CanvasSize       = UDim2.new(0, 0, 0, canvasH or 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BorderSizePixel  = 0,
	}, parent)
	local layout = make("UIListLayout", {
		Padding   = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, scroll)
	make("UIPadding", {
		PaddingLeft  = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop   = UDim.new(0, 8),
	}, scroll)
	return scroll, layout
end

----------------------------------------------------------------------
-- SELECTED STATE (shared across tabs)
----------------------------------------------------------------------
local selectedPlayer  = nil   -- string name
local selectedBrainrot = nil  -- string name

----------------------------------------------------------------------
-- ════════════════════════════════════════════════════════════════
-- TAB 1 — SPAWN
-- ════════════════════════════════════════════════════════════════
----------------------------------------------------------------------
local spawnPage = makePage()
pages[1] = spawnPage

make("UIPadding", {
	PaddingTop   = UDim.new(0, 10),
	PaddingLeft  = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
}, spawnPage)

makeLabel("Brainrot List", spawnPage,
	UDim2.new(1, 0, 0, 20), UDim2.new(0, 0, 0, 0),
	C.accentGold, 13, Enum.Font.GothamBold)

-- Two column layout: list | controls
local spawnLeft = make("Frame", {
	Size            = UDim2.new(0.5, -6, 1, -34),
	Position        = UDim2.new(0, 0, 0, 24),
	BackgroundColor3 = C.bg,
	BorderSizePixel  = 0,
}, spawnPage)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, spawnLeft)

local spawnRight = make("Frame", {
	Size            = UDim2.new(0.5, -6, 1, -34),
	Position        = UDim2.new(0.5, 6, 0, 24),
	BackgroundColor3 = C.bg,
	BorderSizePixel  = 0,
}, spawnPage)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, spawnRight)

local brainrotScroll, _ = makeScrollFrame(spawnLeft)

-- Selected brainrot label
local selectedBrainrotLabel = makeLabel("No brainrot selected", spawnRight,
	UDim2.new(1, -16, 0, 36),
	UDim2.new(0, 8, 0, 8),
	C.subtext, 13)
selectedBrainrotLabel.TextWrapped = true

-- Target player label
local spawnTargetLabel = makeLabel("Target: none (world spawner)", spawnRight,
	UDim2.new(1, -16, 0, 20),
	UDim2.new(0, 8, 0, 50),
	C.subtext, 12)

-- Spawn above player button
local spawnAboveBtn = makeBtn("Spawn Above Player", C.accentBlue, spawnRight,
	UDim2.new(1, -16, 0, 36),
	UDim2.new(0, 8, 0, 78))
addHover(spawnAboveBtn, C.accentBlue, Color3.fromRGB(80, 180, 255))

-- Spawn at random spawner button
local spawnWorldBtn = makeBtn("Spawn at World Spawner", C.btn, spawnRight,
	UDim2.new(1, -16, 0, 36),
	UDim2.new(0, 8, 0, 122))
addHover(spawnWorldBtn, C.btn, C.btnHover)

-- Divider
make("Frame", {
	Size            = UDim2.new(1, -16, 0, 1),
	Position        = UDim2.new(0, 8, 0, 166),
	BackgroundColor3 = Color3.fromRGB(55, 55, 75),
	BorderSizePixel  = 0,
}, spawnRight)

-- Global spawn button (all servers via MessagingService)
local spawnGlobalBtn = makeBtn("🌐 Spawn in ALL Servers", Color3.fromRGB(120, 60, 200), spawnRight,
	UDim2.new(1, -16, 0, 36),
	UDim2.new(0, 8, 0, 175))
addHover(spawnGlobalBtn, Color3.fromRGB(120, 60, 200), Color3.fromRGB(150, 90, 230))

make("TextLabel", {
	Text            = "Spawns at a world spawner in every server",
	Size            = UDim2.new(1, -16, 0, 18),
	Position        = UDim2.new(0, 8, 0, 214),
	BackgroundTransparency = 1,
	TextColor3      = C.subtext,
	Font            = Enum.Font.Gotham,
	TextSize        = 11,
	TextXAlignment  = Enum.TextXAlignment.Left,
}, spawnRight)

-- Populate brainrot list
local function refreshBrainrots()
	for _, c in ipairs(brainrotScroll:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	local result = adminRemote:InvokeServer("getBrainrots")
	if not (result and result.success) then return end
	for _, name in ipairs(result.data) do
		local btn = make("TextButton", {
			Text             = name,
			Size             = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = C.tab,
			TextColor3       = C.text,
			Font             = Enum.Font.Gotham,
			TextSize         = 12,
			BorderSizePixel  = 0,
			TextXAlignment   = Enum.TextXAlignment.Left,
		}, brainrotScroll)
		make("UICorner", { CornerRadius = UDim.new(0, 4) }, btn)
		make("UIPadding", { PaddingLeft = UDim.new(0, 8) }, btn)
		local bname = name
		btn.MouseButton1Click:Connect(function()
			selectedBrainrot = bname
			selectedBrainrotLabel.Text = "Selected: " .. bname
			selectedBrainrotLabel.TextColor3 = C.accentGold
			-- highlight
			for _, c2 in ipairs(brainrotScroll:GetChildren()) do
				if c2:IsA("TextButton") then
					c2.BackgroundColor3 = C.tab
					c2.TextColor3 = C.text
				end
			end
			btn.BackgroundColor3 = C.accentGold
			btn.TextColor3 = Color3.fromRGB(20, 20, 20)
		end)
	end
end

spawnAboveBtn.MouseButton1Click:Connect(function()
	if not selectedBrainrot then toast("Select a brainrot first!", C.accent) return end
	local target = selectedPlayer or localPlayer.Name
	local result = adminRemote:InvokeServer("spawnBrainrot", selectedBrainrot, target)
	toast(result and result.message or "Error", result and result.success and C.accentGreen or C.accent)
end)

spawnWorldBtn.MouseButton1Click:Connect(function()
	if not selectedBrainrot then toast("Select a brainrot first!", C.accent) return end
	local result = adminRemote:InvokeServer("spawnBrainrot", selectedBrainrot, nil)
	toast(result and result.message or "Error", result and result.success and C.accentGreen or C.accent)
end)

spawnGlobalBtn.MouseButton1Click:Connect(function()
	if not selectedBrainrot then toast("Select a brainrot first!", C.accent) return end
	local result = adminRemote:InvokeServer("spawnBrainrotGlobal", selectedBrainrot)
	toast(result and result.message or "Error", result and result.success and Color3.fromRGB(180, 120, 255) or C.accent)
end)

----------------------------------------------------------------------
-- TAB 2 — PLAYERS
----------------------------------------------------------------------
local playerPage = makePage()
pages[2] = playerPage

make("UIPadding", {
	PaddingTop   = UDim.new(0, 10),
	PaddingLeft  = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
}, playerPage)

makeLabel("Player List", playerPage,
	UDim2.new(1, 0, 0, 20), UDim2.new(0, 0, 0, 0),
	C.accentGold, 13, Enum.Font.GothamBold)

local playerLeft = make("Frame", {
	Size            = UDim2.new(0.38, -6, 1, -34),
	Position        = UDim2.new(0, 0, 0, 24),
	BackgroundColor3 = C.bg,
	BorderSizePixel  = 0,
}, playerPage)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, playerLeft)

local playerRight = make("Frame", {
	Size            = UDim2.new(0.62, -6, 1, -34),
	Position        = UDim2.new(0.38, 6, 0, 24),
	BackgroundColor3 = C.bg,
	BorderSizePixel  = 0,
}, playerPage)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, playerRight)

local playerScroll, _ = makeScrollFrame(playerLeft)

local selectedPlayerLabel = makeLabel("Select a player →", playerRight,
	UDim2.new(1, -16, 0, 24),
	UDim2.new(0, 8, 0, 8),
	C.accentGold, 14, Enum.Font.GothamBold)

-- Action buttons grid
local actionPad = make("Frame", {
	Size            = UDim2.new(1, -16, 1, -42),
	Position        = UDim2.new(0, 8, 0, 38),
	BackgroundTransparency = 1,
}, playerRight)

local actLayout = make("UIGridLayout", {
	CellSize    = UDim2.new(0.5, -4, 0, 36),
	CellPadding = UDim2.new(0, 6, 0, 6),
	SortOrder   = Enum.SortOrder.LayoutOrder,
}, actionPad)

local function playerAction(cmd, extraArg, label, successMsg)
	if not selectedPlayer then toast("Select a player first!", C.accent) return end
	local result = adminRemote:InvokeServer(cmd, selectedPlayer, extraArg)
	toast((result and result.message) or label, result and result.success and C.accentGreen or C.accent)
end

local actionDefs = {
	{ "Kill",        C.btnRed,   function() playerAction("kill",     nil,   "Kill") end },
	{ "Bring",       C.accentBlue, function() playerAction("bring",  nil,   "Bring") end },
	{ "Freeze",      C.accentBlue, function() playerAction("freeze", true,  "Freeze") end },
	{ "Unfreeze",    C.btn,      function() playerAction("freeze",   false, "Unfreeze") end },
	{ "Teleport To", C.btn,      function() playerAction("teleport", nil,   "Teleport") end },
	{ "God ON",      C.accentGreen, function() playerAction("godMode", true, "God ON") end },
	{ "God OFF",     C.btn,      function() playerAction("godMode",  false, "God OFF") end },
}

for i, def in ipairs(actionDefs) do
	local btn = make("TextButton", {
		Text             = def[1],
		Size             = UDim2.new(0, 0, 0, 0),  -- sized by grid
		BackgroundColor3 = def[2],
		TextColor3       = C.text,
		Font             = Enum.Font.GothamBold,
		TextSize         = 13,
		BorderSizePixel  = 0,
		LayoutOrder      = i,
		AutoButtonColor  = true,
	}, actionPad)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, btn)
	btn.MouseButton1Click:Connect(def[3])
end

-- Kick with reason
local kickSep = makeSeparator(actionPad)
kickSep.LayoutOrder = #actionDefs + 1

local kickInput = make("TextBox", {
	PlaceholderText  = "Kick reason...",
	Text             = "",
	Size             = UDim2.new(0, 0, 0, 0),
	BackgroundColor3 = C.inputBg,
	TextColor3       = C.text,
	PlaceholderColor3 = C.subtext,
	Font             = Enum.Font.Gotham,
	TextSize         = 13,
	BorderSizePixel  = 0,
	LayoutOrder      = #actionDefs + 2,
	ClearTextOnFocus = false,
}, actionPad)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, kickInput)
make("UIPadding", { PaddingLeft = UDim.new(0, 8) }, kickInput)

local kickBtn = make("TextButton", {
	Text             = "⛔ Kick",
	Size             = UDim2.new(0, 0, 0, 0),
	BackgroundColor3 = C.btnRed,
	TextColor3       = C.text,
	Font             = Enum.Font.GothamBold,
	TextSize         = 13,
	BorderSizePixel  = 0,
	LayoutOrder      = #actionDefs + 3,
	AutoButtonColor  = true,
}, actionPad)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, kickBtn)
kickBtn.MouseButton1Click:Connect(function()
	if not selectedPlayer then toast("Select a player first!", C.accent) return end
	local reason = kickInput.Text ~= "" and kickInput.Text or "Kicked by admin"
	local result = adminRemote:InvokeServer("kick", selectedPlayer, reason)
	toast(result and result.message or "Error", result and result.success and C.accentGreen or C.accent)
end)

-- Speed input
local speedInput = make("TextBox", {
	PlaceholderText  = "Speed (e.g. 30)...",
	Text             = "",
	Size             = UDim2.new(0, 0, 0, 0),
	BackgroundColor3 = C.inputBg,
	TextColor3       = C.text,
	PlaceholderColor3 = C.subtext,
	Font             = Enum.Font.Gotham,
	TextSize         = 13,
	BorderSizePixel  = 0,
	LayoutOrder      = #actionDefs + 4,
	ClearTextOnFocus = false,
}, actionPad)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, speedInput)
make("UIPadding", { PaddingLeft = UDim.new(0, 8) }, speedInput)

local speedBtn = make("TextButton", {
	Text             = "🏃 Set Speed",
	Size             = UDim2.new(0, 0, 0, 0),
	BackgroundColor3 = C.accentBlue,
	TextColor3       = C.text,
	Font             = Enum.Font.GothamBold,
	TextSize         = 13,
	BorderSizePixel  = 0,
	LayoutOrder      = #actionDefs + 5,
	AutoButtonColor  = true,
}, actionPad)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, speedBtn)
speedBtn.MouseButton1Click:Connect(function()
	if not selectedPlayer then toast("Select a player first!", C.accent) return end
	local spd = tonumber(speedInput.Text)
	if not spd then toast("Enter a valid number!", C.accent) return end
	local result = adminRemote:InvokeServer("speed", selectedPlayer, spd)
	toast(result and result.message or "Speed set!", result and result.success and C.accentGreen or C.accent)
end)

-- ── GRANT / REVOKE TEMP ADMIN ────────────────────────────────────
local adminSep = makeSeparator(actionPad)
adminSep.LayoutOrder = #actionDefs + 6

local grantAdminBtn = make("TextButton", {
	Text             = "⚡ Grant Temp Admin",
	Size             = UDim2.new(0, 0, 0, 0),
	BackgroundColor3 = C.accentGold,
	TextColor3       = Color3.fromRGB(20, 20, 20),
	Font             = Enum.Font.GothamBold,
	TextSize         = 13,
	BorderSizePixel  = 0,
	LayoutOrder      = #actionDefs + 7,
	AutoButtonColor  = true,
}, actionPad)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, grantAdminBtn)
grantAdminBtn.MouseButton1Click:Connect(function()
	if not selectedPlayer then toast("Select a player first!", C.accent) return end
	local result = adminRemote:InvokeServer("grantAdmin", selectedPlayer)
	toast(result and result.message or "Error", result and result.success and C.accentGold or C.accent)
end)

local revokeAdminBtn = make("TextButton", {
	Text             = "🚫 Revoke Admin",
	Size             = UDim2.new(0, 0, 0, 0),
	BackgroundColor3 = C.btnRed,
	TextColor3       = C.text,
	Font             = Enum.Font.GothamBold,
	TextSize         = 13,
	BorderSizePixel  = 0,
	LayoutOrder      = #actionDefs + 8,
	AutoButtonColor  = true,
}, actionPad)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, revokeAdminBtn)
revokeAdminBtn.MouseButton1Click:Connect(function()
	if not selectedPlayer then toast("Select a player first!", C.accent) return end
	local result = adminRemote:InvokeServer("revokeAdmin", selectedPlayer)
	toast(result and result.message or "Error", result and result.success and C.accentGreen or C.accent)
end)

-- ── SELF ACTIONS (invisible toggle) ──────────────────────────────
local selfSep = makeSeparator(actionPad)
selfSep.LayoutOrder = #actionDefs + 9

make("TextLabel", {
	Text             = "Self Actions",
	Size             = UDim2.new(0, 0, 0, 0),
	BackgroundTransparency = 1,
	TextColor3       = C.subtext,
	Font             = Enum.Font.GothamBold,
	TextSize         = 12,
	BorderSizePixel  = 0,
	LayoutOrder      = #actionDefs + 10,
	TextXAlignment   = Enum.TextXAlignment.Left,
}, actionPad)

local isInvisible = false

local invisBtn = make("TextButton", {
	Text             = "👻 Go Invisible",
	Size             = UDim2.new(0, 0, 0, 0),
	BackgroundColor3 = Color3.fromRGB(80, 50, 120),
	TextColor3       = C.text,
	Font             = Enum.Font.GothamBold,
	TextSize         = 13,
	BorderSizePixel  = 0,
	LayoutOrder      = #actionDefs + 11,
	AutoButtonColor  = true,
}, actionPad)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, invisBtn)
invisBtn.MouseButton1Click:Connect(function()
	isInvisible = not isInvisible
	local result = adminRemote:InvokeServer("invisible", localPlayer.Name, isInvisible)
	if result and result.success then
		invisBtn.Text            = isInvisible and "👁️ Become Visible" or "👻 Go Invisible"
		invisBtn.BackgroundColor3 = isInvisible
			and Color3.fromRGB(50, 120, 80)
			or  Color3.fromRGB(80, 50, 120)
		toast(result.message, isInvisible and Color3.fromRGB(80, 200, 120) or C.accentBlue)
	else
		isInvisible = not isInvisible  -- revert toggle on failure
		toast((result and result.message) or "Error", C.accent)
	end
end)

local function refreshPlayers()
	for _, c in ipairs(playerScroll:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	local result = adminRemote:InvokeServer("getPlayers")
	if not (result and result.success) then return end
	for _, name in ipairs(result.data) do
		local btn = make("TextButton", {
			Text             = name,
			Size             = UDim2.new(1, 0, 0, 32),
			BackgroundColor3 = C.tab,
			TextColor3       = C.text,
			Font             = Enum.Font.Gotham,
			TextSize         = 13,
			BorderSizePixel  = 0,
			TextXAlignment   = Enum.TextXAlignment.Left,
		}, playerScroll)
		make("UICorner", { CornerRadius = UDim.new(0, 4) }, btn)
		make("UIPadding", { PaddingLeft = UDim.new(0, 8) }, btn)
		local pname = name
		btn.MouseButton1Click:Connect(function()
			selectedPlayer = pname
			selectedPlayerLabel.Text = "Selected: " .. pname
			spawnTargetLabel.Text = "Target: " .. pname
			for _, c2 in ipairs(playerScroll:GetChildren()) do
				if c2:IsA("TextButton") then
					c2.BackgroundColor3 = C.tab
					c2.TextColor3 = C.text
				end
			end
			btn.BackgroundColor3 = C.accentGold
			btn.TextColor3 = Color3.fromRGB(20, 20, 20)
		end)
	end
end

----------------------------------------------------------------------
-- TAB 3 — WORLD
----------------------------------------------------------------------
local worldPage = makePage()
pages[3] = worldPage

local worldPad = make("UIPadding", {
	PaddingTop   = UDim.new(0, 16),
	PaddingLeft  = UDim.new(0, 16),
	PaddingRight = UDim.new(0, 16),
}, worldPage)

local worldLayout = make("UIListLayout", {
	Padding   = UDim.new(0, 14),
	SortOrder = Enum.SortOrder.LayoutOrder,
	FillDirection = Enum.FillDirection.Vertical,
}, worldPage)

-- Time section
local timeHeader = makeLabel("🕐 Time of Day", worldPage,
	UDim2.new(1, 0, 0, 22), nil, C.accentGold, 15, Enum.Font.GothamBold)
timeHeader.LayoutOrder = 1

local timeValueLabel = makeLabel("12:00 (Noon)", worldPage,
	UDim2.new(1, 0, 0, 20), nil, C.text, 13)
timeValueLabel.LayoutOrder = 2
timeValueLabel.TextXAlignment = Enum.TextXAlignment.Center

local timeSlider = make("Frame", {
	Size            = UDim2.new(1, 0, 0, 24),
	BackgroundColor3 = C.tab,
	BorderSizePixel  = 0,
	LayoutOrder      = 3,
}, worldPage)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, timeSlider)

local timeTrack = make("Frame", {
	Size            = UDim2.new(0, 0, 1, 0),
	BackgroundColor3 = C.accentGold,
	BorderSizePixel  = 0,
}, timeSlider)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, timeTrack)

local timeHandle = make("TextButton", {
	Text            = "",
	Size            = UDim2.new(0, 22, 0, 22),
	Position        = UDim2.new(0.5, -11, 0.5, -11),
	BackgroundColor3 = Color3.new(1,1,1),
	BorderSizePixel  = 0,
	ZIndex           = 2,
}, timeSlider)
make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, timeHandle)

local sliderValue = 12 / 24

local function updateSlider(frac)
	frac = math.clamp(frac, 0, 1)
	sliderValue = frac
	timeTrack.Size = UDim2.new(frac, 0, 1, 0)
	timeHandle.Position = UDim2.new(frac, -11, 0.5, -11)
	local hours = math.floor(frac * 24)
	local suffix = hours < 12 and "AM" or "PM"
	local displayH = hours % 12
	if displayH == 0 then displayH = 12 end
	timeValueLabel.Text = string.format("%d:00 %s", displayH, suffix)
end

updateSlider(0.5)

local dragging = false
timeHandle.MouseButton1Down:Connect(function() dragging = true end)
UserInputService.InputEnded:Connect(function(inp)
	if inp.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = false
	end
end)
UserInputService.InputChanged:Connect(function(inp)
	if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
		local sliderAbs = timeSlider.AbsolutePosition
		local sliderSz  = timeSlider.AbsoluteSize
		local mouseX    = inp.Position.X
		local frac = (mouseX - sliderAbs.X) / sliderSz.X
		updateSlider(frac)
	end
end)

local setTimeBtn = makeBtn("✅ Set Time", C.accentGold, worldPage,
	UDim2.new(0.4, 0, 0, 36))
setTimeBtn.LayoutOrder = 4
setTimeBtn.TextColor3 = Color3.fromRGB(20, 20, 20)
setTimeBtn.Font = Enum.Font.GothamBold
addHover(setTimeBtn, C.accentGold, Color3.fromRGB(255, 220, 70))
setTimeBtn.MouseButton1Click:Connect(function()
	local hours = sliderValue * 24
	local result = adminRemote:InvokeServer("setTime", hours)
	toast(result and result.message or "Time set!", result and result.success and C.accentGreen or C.accent)
end)

makeSeparator(worldPage).LayoutOrder = 5

-- Clear brainrots
makeLabel("🗑️ World Cleanup", worldPage,
	UDim2.new(1, 0, 0, 22), nil, C.accentGold, 15, Enum.Font.GothamBold).LayoutOrder = 6

local clearBtn = makeBtn("☠️ Clear World Brainrots", C.btnRed, worldPage,
	UDim2.new(0.6, 0, 0, 40))
clearBtn.LayoutOrder = 7
clearBtn.Font = Enum.Font.GothamBold
clearBtn.TextSize = 15
addHover(clearBtn, C.btnRed, Color3.fromRGB(210, 70, 70))
clearBtn.MouseButton1Click:Connect(function()
	local result = adminRemote:InvokeServer("clearBrainrots")
	toast(result and result.message or "Cleared!", result and result.success and C.accentGreen or C.accent)
end)

makeSeparator(worldPage).LayoutOrder = 8

makeLabel("🌋 Rare Spawn", worldPage,
	UDim2.new(1, 0, 0, 22), nil, Color3.fromRGB(200, 100, 255), 15, Enum.Font.GothamBold).LayoutOrder = 9

makeLabel("Manually triggers the HighSpawner wave and resets the 10-min countdown.", worldPage,
	UDim2.new(1, 0, 0, 18), nil, C.subtext, 12).LayoutOrder = 10

local triggerSpawnBtn = makeBtn("🌋 Force Rare Spawn", Color3.fromRGB(120, 60, 200), worldPage,
	UDim2.new(0.6, 0, 0, 40))
triggerSpawnBtn.LayoutOrder = 11
triggerSpawnBtn.Font = Enum.Font.GothamBold
triggerSpawnBtn.TextSize = 15
addHover(triggerSpawnBtn, Color3.fromRGB(120, 60, 200), Color3.fromRGB(150, 90, 230))
triggerSpawnBtn.MouseButton1Click:Connect(function()
	local result = adminRemote:InvokeServer("triggerHighSpawn")
	toast(result and result.message or "Error", result and result.success and Color3.fromRGB(180, 120, 255) or C.accent)
end)

----------------------------------------------------------------------
-- TAB 4 — MONEY
----------------------------------------------------------------------
local moneyPage = makePage()
pages[4] = moneyPage

local moneyPad = make("UIPadding", {
	PaddingTop   = UDim.new(0, 16),
	PaddingLeft  = UDim.new(0, 16),
	PaddingRight = UDim.new(0, 16),
}, moneyPage)

local moneyListLayout = make("UIListLayout", {
	Padding   = UDim.new(0, 12),
	SortOrder = Enum.SortOrder.LayoutOrder,
	FillDirection = Enum.FillDirection.Vertical,
}, moneyPage)

makeLabel("💰 Give Money", moneyPage,
	UDim2.new(1, 0, 0, 22), nil, C.accentGold, 15, Enum.Font.GothamBold).LayoutOrder = 1

makeLabel("Target Player (name or 'everyone')", moneyPage,
	UDim2.new(1, 0, 0, 18), nil, C.subtext, 12).LayoutOrder = 2

local moneyTargetInput = makeInput("Player name or 'everyone'", moneyPage,
	UDim2.new(1, 0, 0, 36))
moneyTargetInput.LayoutOrder = 3

makeLabel("Amount", moneyPage,
	UDim2.new(1, 0, 0, 18), nil, C.subtext, 12).LayoutOrder = 4

local moneyAmountInput = makeInput("e.g. 5000", moneyPage,
	UDim2.new(1, 0, 0, 36))
moneyAmountInput.LayoutOrder = 5

local giveMoneyBtn = makeBtn("💸 Give Money", C.accentGreen, moneyPage,
	UDim2.new(0.5, 0, 0, 40))
giveMoneyBtn.LayoutOrder = 6
giveMoneyBtn.Font = Enum.Font.GothamBold
giveMoneyBtn.TextSize = 15
giveMoneyBtn.TextColor3 = Color3.fromRGB(20, 20, 20)
addHover(giveMoneyBtn, C.accentGreen, Color3.fromRGB(80, 220, 120))
giveMoneyBtn.MouseButton1Click:Connect(function()
	local target = moneyTargetInput.Text
	local amount = tonumber(moneyAmountInput.Text)
	if target == "" then toast("Enter a target!", C.accent) return end
	if not amount or amount <= 0 then toast("Enter a valid amount!", C.accent) return end
	local result = adminRemote:InvokeServer("giveMoney", target, amount)
	toast(result and result.message or "Done!", result and result.success and C.accentGreen or C.accent)
end)

makeSeparator(moneyPage).LayoutOrder = 7

makeLabel("Quick Give Buttons", moneyPage,
	UDim2.new(1, 0, 0, 18), nil, C.subtext, 12).LayoutOrder = 8

local quickMoneyRow = make("Frame", {
	Size            = UDim2.new(1, 0, 0, 36),
	BackgroundTransparency = 1,
	LayoutOrder      = 9,
}, moneyPage)

local quickLayout = make("UIListLayout", {
	Padding       = UDim.new(0, 6),
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder     = Enum.SortOrder.LayoutOrder,
}, quickMoneyRow)

local quickAmounts = { 100, 500, 1000, 5000, 10000 }
for i, amt in ipairs(quickAmounts) do
	local qBtn = makeBtn("$" .. amt, C.btn, quickMoneyRow,
		UDim2.new(0, 80, 0, 36))
	qBtn.Font = Enum.Font.GothamBold
	qBtn.TextSize = 12
	qBtn.LayoutOrder = i
	addHover(qBtn, C.btn, C.btnHover)
	local qAmt = amt
	qBtn.MouseButton1Click:Connect(function()
		moneyAmountInput.Text = tostring(qAmt)
	end)
end

----------------------------------------------------------------------
-- TAKE MONEY
----------------------------------------------------------------------
makeSeparator(moneyPage).LayoutOrder = 10

makeLabel("➖ Take Money", moneyPage,
	UDim2.new(1, 0, 0, 22), nil, Color3.fromRGB(255, 130, 60), 15, Enum.Font.GothamBold).LayoutOrder = 11

makeLabel("Target Player (name or 'everyone')", moneyPage,
	UDim2.new(1, 0, 0, 18), nil, C.subtext, 12).LayoutOrder = 12

local takeTargetInput = makeInput("Player name or 'everyone'", moneyPage,
	UDim2.new(1, 0, 0, 36))
takeTargetInput.LayoutOrder = 13

makeLabel("Amount to remove", moneyPage,
	UDim2.new(1, 0, 0, 18), nil, C.subtext, 12).LayoutOrder = 14

local takeAmountInput = makeInput("e.g. 1000", moneyPage,
	UDim2.new(1, 0, 0, 36))
takeAmountInput.LayoutOrder = 15

local takeMoneyBtn = makeBtn("➖ Take Money", Color3.fromRGB(200, 100, 30), moneyPage,
	UDim2.new(0.5, 0, 0, 40))
takeMoneyBtn.LayoutOrder = 16
takeMoneyBtn.Font = Enum.Font.GothamBold
takeMoneyBtn.TextSize = 15
addHover(takeMoneyBtn, Color3.fromRGB(200, 100, 30), Color3.fromRGB(230, 130, 50))
takeMoneyBtn.MouseButton1Click:Connect(function()
	local target = takeTargetInput.Text
	local amount = tonumber(takeAmountInput.Text)
	if target == "" then toast("Enter a target!", C.accent) return end
	if not amount or amount <= 0 then toast("Enter a valid amount!", C.accent) return end
	local result = adminRemote:InvokeServer("takeMoney", target, amount)
	toast(result and result.message or "Done!", result and result.success and Color3.fromRGB(255, 150, 60) or C.accent)
end)

-- Quick take buttons (mirror of quick give)
local quickTakeRow = make("Frame", {
	Size            = UDim2.new(1, 0, 0, 36),
	BackgroundTransparency = 1,
	LayoutOrder      = 17,
}, moneyPage)
make("UIListLayout", {
	Padding       = UDim.new(0, 6),
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder     = Enum.SortOrder.LayoutOrder,
}, quickTakeRow)

local quickTakeAmounts = { 100, 500, 1000, 5000, 10000 }
for i, amt in ipairs(quickTakeAmounts) do
	local qBtn = makeBtn("-$" .. amt, Color3.fromRGB(140, 60, 20), quickTakeRow,
		UDim2.new(0, 80, 0, 36))
	qBtn.Font = Enum.Font.GothamBold
	qBtn.TextSize = 12
	qBtn.LayoutOrder = i
	addHover(qBtn, Color3.fromRGB(140, 60, 20), Color3.fromRGB(180, 80, 30))
	local qAmt = amt
	qBtn.MouseButton1Click:Connect(function()
		takeAmountInput.Text = tostring(qAmt)
	end)
end

----------------------------------------------------------------------
-- RESET MONEY
----------------------------------------------------------------------
makeSeparator(moneyPage).LayoutOrder = 18

makeLabel("🗑️ Reset Money", moneyPage,
	UDim2.new(1, 0, 0, 22), nil, C.accent, 15, Enum.Font.GothamBold).LayoutOrder = 19

makeLabel("Wipes balance to $0. Cannot be undone.", moneyPage,
	UDim2.new(1, 0, 0, 18), nil, C.subtext, 12).LayoutOrder = 20

makeLabel("Target Player (name or 'everyone')", moneyPage,
	UDim2.new(1, 0, 0, 18), nil, C.subtext, 12).LayoutOrder = 21

local resetTargetInput = makeInput("Player name or 'everyone'", moneyPage,
	UDim2.new(1, 0, 0, 36))
resetTargetInput.LayoutOrder = 22

-- Button row: single player | everyone (with confirmation guard on "everyone")
local resetBtnRow = make("Frame", {
	Size            = UDim2.new(1, 0, 0, 40),
	BackgroundTransparency = 1,
	LayoutOrder      = 23,
}, moneyPage)
make("UIListLayout", {
	Padding       = UDim.new(0, 8),
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder     = Enum.SortOrder.LayoutOrder,
}, resetBtnRow)

local resetBtn = makeBtn("🗑️ Reset Player", C.btnRed, resetBtnRow,
	UDim2.new(0, 160, 0, 40))
resetBtn.LayoutOrder = 1
resetBtn.Font = Enum.Font.GothamBold
resetBtn.TextSize = 14
addHover(resetBtn, C.btnRed, Color3.fromRGB(210, 70, 70))
resetBtn.MouseButton1Click:Connect(function()
	local target = resetTargetInput.Text
	if target == "" then toast("Enter a player name!", C.accent) return end
	if target:lower() == "everyone" then
		toast("Use the 'Reset Everyone' button for that.", C.accent) return
	end
	local result = adminRemote:InvokeServer("resetMoney", target)
	toast(result and result.message or "Done!", result and result.success and C.accentGreen or C.accent)
end)

-- "Reset Everyone" requires double-click as a safety measure
local resetEveryoneBtn = makeBtn("☢️ Reset Everyone", Color3.fromRGB(140, 20, 20), resetBtnRow,
	UDim2.new(0, 160, 0, 40))
resetEveryoneBtn.LayoutOrder = 2
resetEveryoneBtn.Font = Enum.Font.GothamBold
resetEveryoneBtn.TextSize = 14
addHover(resetEveryoneBtn, Color3.fromRGB(140, 20, 20), Color3.fromRGB(180, 30, 30))

local resetEveryoneArmed = false
local resetEveryoneTimer = nil
resetEveryoneBtn.MouseButton1Click:Connect(function()
	if not resetEveryoneArmed then
		-- First click: arm it, change label, auto-disarm after 3s
		resetEveryoneArmed = true
		resetEveryoneBtn.Text = "⚠️ Click Again!"
		resetEveryoneBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 20)
		if resetEveryoneTimer then task.cancel(resetEveryoneTimer) end
		resetEveryoneTimer = task.delay(3, function()
			resetEveryoneArmed = false
			resetEveryoneBtn.Text = "☢️ Reset Everyone"
			resetEveryoneBtn.BackgroundColor3 = Color3.fromRGB(140, 20, 20)
		end)
	else
		-- Second click within 3s: actually execute
		resetEveryoneArmed = false
		if resetEveryoneTimer then task.cancel(resetEveryoneTimer) end
		resetEveryoneBtn.Text = "☢️ Reset Everyone"
		resetEveryoneBtn.BackgroundColor3 = Color3.fromRGB(140, 20, 20)
		local result = adminRemote:InvokeServer("resetMoney", "everyone")
		toast(result and result.message or "Done!", result and result.success and C.accentGreen or C.accent)
	end
end)

----------------------------------------------------------------------
-- TAB 5 — ANNOUNCE
----------------------------------------------------------------------
local annPage = makePage()
pages[5] = annPage

local annPad = make("UIPadding", {
	PaddingTop   = UDim.new(0, 16),
	PaddingLeft  = UDim.new(0, 16),
	PaddingRight = UDim.new(0, 16),
}, annPage)

local annListLayout = make("UIListLayout", {
	Padding   = UDim.new(0, 12),
	SortOrder = Enum.SortOrder.LayoutOrder,
	FillDirection = Enum.FillDirection.Vertical,
}, annPage)

makeLabel("📢 Server Announcement", annPage,
	UDim2.new(1, 0, 0, 22), nil, C.accentGold, 15, Enum.Font.GothamBold).LayoutOrder = 1
makeLabel("Send a banner to players in this server, or every server.", annPage,
	UDim2.new(1, 0, 0, 18), nil, C.subtext, 12).LayoutOrder = 2

local annMsgInput = make("TextBox", {
	PlaceholderText  = "Type your announcement...",
	Text             = "",
	Size             = UDim2.new(1, 0, 0, 80),
	BackgroundColor3 = C.inputBg,
	TextColor3       = C.text,
	PlaceholderColor3 = C.subtext,
	Font             = Enum.Font.Gotham,
	TextSize         = 14,
	BorderSizePixel  = 0,
	MultiLine        = true,
	TextWrapped      = true,
	ClearTextOnFocus = false,
	LayoutOrder      = 3,
}, annPage)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, annMsgInput)
make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 6) }, annMsgInput)

-- Button row: This Server | ALL Servers
local annBtnRow = make("Frame", {
	Size            = UDim2.new(1, 0, 0, 44),
	BackgroundTransparency = 1,
	LayoutOrder      = 4,
}, annPage)
make("UIListLayout", {
	Padding       = UDim.new(0, 8),
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder     = Enum.SortOrder.LayoutOrder,
}, annBtnRow)

local sendAnnBtn = makeBtn("📡 This Server", C.accentGold, annBtnRow,
	UDim2.new(0, 180, 0, 44))
sendAnnBtn.LayoutOrder = 1
sendAnnBtn.Font = Enum.Font.GothamBlack
sendAnnBtn.TextSize = 14
sendAnnBtn.TextColor3 = Color3.fromRGB(20, 20, 20)
addHover(sendAnnBtn, C.accentGold, Color3.fromRGB(255, 220, 70))
sendAnnBtn.MouseButton1Click:Connect(function()
	local msg = annMsgInput.Text
	if msg == "" then toast("Type a message first!", C.accent) return end
	local result = adminRemote:InvokeServer("announce", msg)
	toast(result and result.message or "Sent!", result and result.success and C.accentGreen or C.accent)
	annMsgInput.Text = ""
end)

local sendGlobalAnnBtn = makeBtn("🌐 ALL Servers", Color3.fromRGB(120, 60, 200), annBtnRow,
	UDim2.new(0, 180, 0, 44))
sendGlobalAnnBtn.LayoutOrder = 2
sendGlobalAnnBtn.Font = Enum.Font.GothamBlack
sendGlobalAnnBtn.TextSize = 14
addHover(sendGlobalAnnBtn, Color3.fromRGB(120, 60, 200), Color3.fromRGB(150, 90, 230))
sendGlobalAnnBtn.MouseButton1Click:Connect(function()
	local msg = annMsgInput.Text
	if msg == "" then toast("Type a message first!", C.accent) return end
	local result = adminRemote:InvokeServer("announceGlobal", msg)
	toast(result and result.message or "Sent!", result and result.success and Color3.fromRGB(180, 120, 255) or C.accent)
	annMsgInput.Text = ""
end)

-- Preset announcements
makeSeparator(annPage).LayoutOrder = 5
makeLabel("Quick Presets", annPage,
	UDim2.new(1, 0, 0, 18), nil, C.subtext, 12).LayoutOrder = 6

local presets = {
	"🎉 Admin Abuse Event starting NOW!",
	"⚠️ Server restart in 5 minutes!",
	"💰 Free money drop happening NOW!",
	"🎭 Rare brainrot spawning soon!",
}

for i, preset in ipairs(presets) do
	local pBtn = makeBtn(preset, C.tab, annPage,
		UDim2.new(1, 0, 0, 32))
	pBtn.TextXAlignment = Enum.TextXAlignment.Left
	pBtn.TextSize = 12
	pBtn.LayoutOrder = 6 + i
	make("UIPadding", { PaddingLeft = UDim.new(0, 8) }, pBtn)
	addHover(pBtn, C.tab, C.tabActive)
	local msg = preset
	pBtn.MouseButton1Click:Connect(function()
		annMsgInput.Text = msg
	end)
end

----------------------------------------------------------------------
-- PANEL TOGGLE LOGIC
----------------------------------------------------------------------
local function openPanel()
	panelOpen = true
	panel.Visible = true
	panel.Size = UDim2.new(0, 0, 0, 0)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size     = UDim2.new(0, PANEL_W, 0, PANEL_H),
		Position = UDim2.new(0.5, -PANEL_W/2, 0.5, -PANEL_H/2),
	}):Play()
	-- Refresh data when opening
	task.spawn(refreshBrainrots)
	task.spawn(refreshPlayers)
	if activeTab == 0 then switchTab(1) end
end

local function closePanel()
	panelOpen = false
	TweenService:Create(panel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size     = UDim2.new(0, 0, 0, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
	}):Play()
	task.delay(0.25, function() panel.Visible = false end)
end

toggleBtn.MouseButton1Click:Connect(function()
	if panelOpen then closePanel() else openPanel() end
end)
closeBtn.MouseButton1Click:Connect(closePanel)

-- Also allow clicking outside the panel to close (optional)
-- ESC to close
UserInputService.InputBegan:Connect(function(inp, processed)
	if processed then return end
	if inp.KeyCode == Enum.KeyCode.Escape and panelOpen then
		closePanel()
	end
end)

----------------------------------------------------------------------
-- PLAYER JOIN / LEAVE — auto refresh player list
----------------------------------------------------------------------
Players.PlayerAdded:Connect(function()
	if panelOpen and activeTab == 2 then
		task.wait(1)
		refreshPlayers()
	end
end)
Players.PlayerRemoving:Connect(function(p)
	if selectedPlayer == p.Name then
		selectedPlayer = nil
		selectedPlayerLabel.Text = "Select a player →"
		spawnTargetLabel.Text = "Target: none (world spawner)"
	end
	if panelOpen and activeTab == 2 then
		refreshPlayers()
	end
end)

adminEvent.OnClientEvent:Connect(function(eventType, msg, color)
	if eventType == "announce" then
		showAnnouncement(msg, color)
	elseif eventType == "adminGranted" then
		showAnnouncement("⚡ You have been granted temporary admin!", Color3.fromRGB(255, 200, 40))
		toggleBtn.Visible = true
	elseif eventType == "adminRevoked" then
		showAnnouncement("🚫 Your temporary admin has been revoked.", Color3.fromRGB(220, 80, 80))
		if panelOpen then closePanel() end
		task.delay(0.4, function()
			toggleBtn.Visible = false
		end)
	end
end)

print("[AdminClient] Admin panel loaded for", localPlayer.Name)
