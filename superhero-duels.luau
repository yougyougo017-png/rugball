--[[
	SUPERHERO DUELS -- AUTO PUT BEST  (custom UI build)

	target: [NEW] Superhero Duels  (root place 108228062074817,
	        universe 10774293033)

	what it does
	  AUTO PUT       finds the "+" beside a stat name (Strength, Speed,
	                 Superpower, IQ, Battle IQ, Durability) and clicks it.
	  PUT 1 POINT    one click of the chosen stat's plus, no loop.
	  AUTO ROLL      finds the visible button whose text contains ROLL and
	                 clicks it on a delay, optionally stopping at a rarity.
	  PROBE          dumps visible GUI / ReplicatedStorage remotes, and records
	                 the game's own remote calls for 15 seconds.

	this build replaces the Rayfield window with a small in-script panel:
	nothing is fetched for the UI, so it still opens when sirius.menu is down.
	it is client-side only. no remotes are invented and no profile data is
	written. the stat/roll clicks are the same buttons your mouse would press.

	P panics. the window can be dragged by its title bar.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer

local CFG = {
	autoStats = false,
	bestStat = "Superpower",
	delay = 0.25,
	maxClicks = 0,
	autoRoll = false,
	rollDelay = 2.5,
	stopRarity = "Rare",
	clickMethod = "auto",
}

local STATS = { "Superpower", "Strength", "Speed", "Durability", "Battle IQ", "IQ" }
local RARITIES = { "common", "uncommon", "rare", "epic", "legendary", "mythic", "secret", "ultra" }

local dead = false
local clicks = 0
local lastStatAt = 0
local lastRollAt = 0
local lastScan = 0
local missCount = 0
local lastRollRarity = nil
local lastRollClick = 0
local inputConn
local ownScreen = nil
local unload
local setStatus = function() end
local setRollInfo = function() end
local uiToggle = {}
local conns = {}
local picker = nil

--// gui lookup / clicking ------------------------------------------------------

local function now()
	return os.clock()
end

local function playerGui()
	return LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui") or nil
end

local function visible(inst)
	if not inst or not inst:IsA("GuiObject") or not inst.Visible then return false end
	if ownScreen and inst:IsDescendantOf(ownScreen) then return false end
	if inst.AbsoluteSize.X < 4 or inst.AbsoluteSize.Y < 4 then return false end
	local p = inst.Parent
	while p and p ~= game do
		if p:IsA("ScreenGui") and not p.Enabled then return false end
		if p:IsA("GuiObject") and not p.Visible then return false end
		p = p.Parent
	end
	return true
end

local function guiObjects(class)
	local gui = playerGui()
	local out = {}
	if not gui then return out end
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA(class) and visible(d) then
			out[#out + 1] = d
		end
	end
	return out
end

local function center(obj)
	local p = obj.AbsolutePosition
	local s = obj.AbsoluteSize
	return p.X + s.X * 0.5, p.Y + s.Y * 0.5
end

-- the menu rows are stat label on the left and a square + immediately right.
-- find the + by geometry so a re-skin does not break a hard-coded path.
local function findPlus(statName)
	local gui = playerGui()
	if not gui then return nil end

	local wanted = string.lower(statName)
	local labels = {}
	local loose = {}
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("TextLabel") and visible(d) then
			local txt = string.lower((d.Text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
			if txt == wanted then
				labels[#labels + 1] = d
			elseif #loose < 8 and string.find(txt, wanted, 1, true) then
				loose[#loose + 1] = d
			end
		end
	end
	if #labels == 0 then labels = loose end
	if #labels == 0 then return nil end

	local buttons = {}
	for _, d in ipairs(gui:GetDescendants()) do
		if (d:IsA("TextButton") or d:IsA("ImageButton")) and visible(d) then
			buttons[#buttons + 1] = d
		end
	end

	local bestBtn = nil
	local bestScore = nil
	for _, label in ipairs(labels) do
		local lx, ly = center(label)
		local tolerance = math.max(14, label.AbsoluteSize.Y * 0.9)
		for _, btn in ipairs(buttons) do
			local bx, by = center(btn)
			local dy = math.abs(by - ly)
			local dx = bx - lx
			if dx > 0 and dx < 420 and dy <= tolerance then
				local score = dx
				if btn:IsA("TextButton") and string.find(btn.Text or "", "+", 1, true) then
					score = score - 1000
				end
				if not bestScore or score < bestScore then
					bestScore = score
					bestBtn = btn
				end
			end
		end
	end
	return bestBtn
end

local function signal(btn)
	if type(firesignal) ~= "function" then return false end
	return pcall(firesignal, btn.MouseButton1Click)
end

local function virtualClick(btn)
	return pcall(function()
		local x, y = center(btn)
		VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
		task.wait(0.03)
		VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
	end)
end

local function clickButton(btn)
	if not btn then return false end
	if CFG.clickMethod == "signal" then return signal(btn) end
	if CFG.clickMethod == "virtual" then return virtualClick(btn) end
	if signal(btn) then return true end
	return virtualClick(btn)
end

local function putOne()
	local btn = findPlus(CFG.bestStat)
	if not btn then
		missCount = missCount + 1
		return false
	end
	missCount = 0
	local ok = clickButton(btn)
	if ok then
		clicks = clicks + 1
		print("[SUPERHERO] clicked " .. CFG.bestStat .. " + (" .. tostring(clicks) .. ")")
	end
	return ok
end

local function findRollButton()
	local best = nil
	local bestSize = nil
	for _, btn in ipairs(guiObjects("TextButton")) do
		local txt = string.lower(btn.Text or "")
		if string.find(txt, "roll", 1, true) and not string.find(txt, "control", 1, true) then
			local size = btn.AbsoluteSize.X * btn.AbsoluteSize.Y
			if not bestSize or size > bestSize then
				bestSize = size
				best = btn
			end
		end
	end
	return best
end

local function readRarity()
	local bestRank, bestWord = nil, nil
	for _, label in ipairs(guiObjects("TextLabel")) do
		local txt = string.lower(label.Text or "")
		for rank, word in ipairs(RARITIES) do
			if txt == word or string.find(txt, word, 1, true) then
				if not bestRank or rank > bestRank then
					bestRank = rank
					bestWord = word
				end
				break
			end
		end
	end
	return bestRank, bestWord
end

local function rarityRank(word)
	word = string.lower(tostring(word or ""))
	for i, w in ipairs(RARITIES) do
		if w == word then return i end
	end
	return 0
end

--// probe ----------------------------------------------------------------------

local function dumpGui()
	local lines = {}
	lines[#lines + 1] = "place=" .. tostring(game.PlaceId) .. "  game=" .. tostring(game.GameId)
	local gui = playerGui()
	if not gui then
		lines[#lines + 1] = "no PlayerGui"
	else
		for _, d in ipairs(gui:GetDescendants()) do
			if (d:IsA("TextButton") or d:IsA("ImageButton")) and visible(d) then
				local x, y = center(d)
				lines[#lines + 1] = string.format("BTN %s  text=%q  pos=%d,%d  size=%dx%d",
					d:GetFullName(), tostring(d.Text), math.floor(x), math.floor(y),
					math.floor(d.AbsoluteSize.X), math.floor(d.AbsoluteSize.Y))
			end
		end
		for _, stat in ipairs(STATS) do
			local btn = findPlus(stat)
			if btn then
				lines[#lines + 1] = "PLUS " .. stat .. " -> " .. btn:GetFullName() .. "  text=" .. tostring(btn.Text)
			else
				lines[#lines + 1] = "PLUS " .. stat .. " -> NOT FOUND"
			end
		end
	end
	return table.concat(lines, "\n")
end

local function dumpRemotes()
	local lines = { "place=" .. tostring(game.PlaceId) .. "  game=" .. tostring(game.GameId) }
	local function walk(inst, depth)
		if depth > 3 then return end
		for _, c in ipairs(inst:GetChildren()) do
			if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") or c:IsA("UnreliableRemoteEvent") then
				lines[#lines + 1] = c.ClassName .. "  " .. c:GetFullName()
			end
			if c:IsA("Folder") or c:IsA("Configuration") or c:IsA("Model") then
				walk(c, depth + 1)
			end
		end
	end
	walk(ReplicatedStorage, 0)
	if #lines == 1 then lines[#lines + 1] = "no remotes found under ReplicatedStorage" end
	return table.concat(lines, "\n")
end

local function present(text, label)
	print("[SUPERHERO PROBE] " .. label .. "\n" .. text)
	if type(setclipboard) == "function" then
		pcall(setclipboard, text)
		setStatus(label .. " printed + copied")
	else
		setStatus(label .. " printed to console")
	end
end

--// custom ui ------------------------------------------------------------------

local COL = {
	bg = Color3.fromRGB(9, 13, 19),
	panel = Color3.fromRGB(15, 21, 29),
	panel2 = Color3.fromRGB(20, 28, 38),
	row = Color3.fromRGB(24, 33, 45),
	track = Color3.fromRGB(34, 46, 60),
	stroke = Color3.fromRGB(40, 56, 72),
	text = Color3.fromRGB(232, 241, 248),
	dim = Color3.fromRGB(133, 152, 169),
	accent = Color3.fromRGB(62, 214, 255),
	accent2 = Color3.fromRGB(113, 255, 176),
	danger = Color3.fromRGB(255, 92, 108),
}

local W, H = 560, 470

local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
	return c
end

local function stroke(inst, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color or COL.stroke
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

local function label(parent, text, size, color, font)
	return make("TextLabel", {
		BackgroundTransparency = 1,
		Size = size,
		Text = text,
		Font = font or Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = color or COL.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false,
	}, parent)
end

local gui = playerGui()
if not gui then
	warn("[SUPERHERO] no PlayerGui; cannot build the panel")
	return
end

if _G.SuperheroPanel and _G.SuperheroPanel.unload then
	pcall(_G.SuperheroPanel.unload)
end
if _G.SuperheroAutoPanel and _G.SuperheroAutoPanel.unload then
	pcall(_G.SuperheroAutoPanel.unload)
end
if _G.SuperheroMiniStop then
	pcall(_G.SuperheroMiniStop)
end

local screen = make("ScreenGui", {
	Name = "SlimSuperheroPanel",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Global,
	IgnoreGuiInset = true,
	DisplayOrder = 100000,
}, gui)
ownScreen = screen

local cam = workspace.CurrentCamera
local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
local scale = math.clamp(math.min(vp.X / 600, (vp.Y - 40) / 500), 0.68, 1)
make("UIScale", { Scale = scale }, screen)

local startX = math.max(0, (vp.X / scale - W) * 0.5)
local startY = math.max(0, (vp.Y / scale - H) * 0.5)

local main = make("Frame", {
	Name = "Main",
	Position = UDim2.fromOffset(startX, startY),
	Size = UDim2.fromOffset(W, H),
	BackgroundColor3 = COL.bg,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	ZIndex = 10,
}, screen)
corner(main, 14)
stroke(main, COL.stroke, 1, 0)

-- title bar
local header = make("Frame", {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, 46),
	BackgroundColor3 = COL.panel,
	BorderSizePixel = 0,
	Active = true,
	ZIndex = 11,
}, main)
corner(header, 14)
local headerBar = make("Frame", {
	Position = UDim2.fromOffset(14, 13),
	Size = UDim2.fromOffset(4, 20),
	BackgroundColor3 = COL.accent,
	BorderSizePixel = 0,
	ZIndex = 12,
}, header)
corner(headerBar, 2)
local title = label(header, "SUPERHERO DUELS", UDim2.fromOffset(180, 18), COL.text, Enum.Font.GothamBold)
title.Position = UDim2.fromOffset(28, 8)
title.TextSize = 14
local subtitle = label(header, "auto put best  ·  auto roll  ·  probe", UDim2.fromOffset(280, 14), COL.dim)
subtitle.Position = UDim2.fromOffset(28, 24)
subtitle.TextSize = 10

local closeBtn = make("TextButton", {
	Name = "Close",
	Text = "×",
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	TextColor3 = COL.dim,
	BackgroundColor3 = COL.panel2,
	AutoButtonColor = false,
	Position = UDim2.new(1, -38, 0, 10),
	Size = UDim2.fromOffset(26, 26),
	ZIndex = 12,
}, header)
corner(closeBtn, 7)
stroke(closeBtn, COL.stroke, 1, 0)

local minBtn = make("TextButton", {
	Name = "Minimize",
	Text = "–",
	Font = Enum.Font.GothamBold,
	TextSize = 16,
	TextColor3 = COL.dim,
	BackgroundColor3 = COL.panel2,
	AutoButtonColor = false,
	Position = UDim2.new(1, -70, 0, 10),
	Size = UDim2.fromOffset(26, 26),
	ZIndex = 12,
}, header)
corner(minBtn, 7)
stroke(minBtn, COL.stroke, 1, 0)

-- tabs
local tabsBar = make("Frame", {
	Name = "Tabs",
	Position = UDim2.fromOffset(0, 46),
	Size = UDim2.new(1, 0, 0, 38),
	BackgroundColor3 = COL.bg,
	BorderSizePixel = 0,
	ZIndex = 11,
}, main)

local body = make("Frame", {
	Name = "Body",
	Position = UDim2.fromOffset(0, 84),
	Size = UDim2.new(1, 0, 1, -114),
	BackgroundTransparency = 1,
	ZIndex = 11,
}, main)

local footer = make("Frame", {
	Name = "Footer",
	Position = UDim2.new(0, 0, 1, -30),
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = COL.panel,
	BorderSizePixel = 0,
	ZIndex = 12,
}, main)

local statusLabel = label(footer, "idle", UDim2.new(1, -120, 1, 0), COL.dim)
statusLabel.Position = UDim2.fromOffset(14, 0)
statusLabel.TextSize = 10
local panicLabel = label(footer, "P  panic", UDim2.fromOffset(80, 30), COL.accent)
panicLabel.Position = UDim2.new(1, -92, 0, 0)
panicLabel.TextSize = 10
panicLabel.TextXAlignment = Enum.TextXAlignment.Right

local tabNames = { "AUTO", "ROLL", "PROBE", "SYS" }
local tabButtons = {}
local pages = {}
local currentTab = 1

local function selectTab(index)
	currentTab = index
	for i, page in ipairs(pages) do
		page.Visible = (i == index)
	end
	for i, btn in ipairs(tabButtons) do
		btn.BackgroundColor3 = (i == index) and COL.panel2 or COL.bg
		btn.TextColor3 = (i == index) and COL.accent or COL.dim
		local underline = btn:FindFirstChild("Underline")
		if underline then underline.Visible = (i == index) end
	end
end

for i, tabName in ipairs(tabNames) do
	local btn = make("TextButton", {
		Name = tabName,
		Text = tabName,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = COL.dim,
		BackgroundColor3 = COL.bg,
		AutoButtonColor = false,
		Position = UDim2.fromOffset(12 + (i - 1) * 132, 4),
		Size = UDim2.fromOffset(126, 30),
		ZIndex = 12,
	}, tabsBar)
	corner(btn, 7)
	local underline = make("Frame", {
		Name = "Underline",
		Position = UDim2.new(0, 22, 0, 27),
		Size = UDim2.new(1, -44, 0, 2),
		BackgroundColor3 = COL.accent,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 13,
	}, btn)
	corner(underline, 1)
	btn.MouseButton1Click:Connect(function() selectTab(i) end)
	tabButtons[i] = btn

	local page = make("ScrollingFrame", {
		Name = tabName .. "Page",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = COL.accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		Visible = (i == 1),
		ZIndex = 11,
	}, body)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.Parent = page
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = page
	pages[i] = page
end
selectTab(1)

-- components
local function section(parent, text)
	local l = label(parent, string.upper(text), UDim2.new(1, 0, 0, 22), COL.accent, Enum.Font.GothamBold)
	l.TextSize = 10
	return l
end

local function actionButton(parent, titleText, desc, onClick)
	local height = desc and 54 or 40
	local row = make("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = COL.panel2,
		BorderSizePixel = 0,
	}, parent)
	corner(row, 8)
	stroke(row, COL.stroke, 1, 0.15)
	local bar = make("Frame", {
		Position = UDim2.fromOffset(11, desc and 16 or 11),
		Size = UDim2.fromOffset(3, desc and 22 or 18),
		BackgroundColor3 = COL.accent,
		BorderSizePixel = 0,
	}, row)
	corner(bar, 2)
	local t = label(row, titleText, UDim2.new(1, -32, 0, 18), COL.text, Enum.Font.GothamBold)
	t.Position = UDim2.fromOffset(22, desc and 7 or 11)
	t.TextSize = 12
	if desc then
		local d = label(row, desc, UDim2.new(1, -34, 0, 20), COL.dim)
		d.Position = UDim2.fromOffset(22, 27)
		d.TextSize = 10
		d.TextWrapped = true
	end
	row.MouseEnter:Connect(function() row.BackgroundColor3 = COL.row end)
	row.MouseLeave:Connect(function() row.BackgroundColor3 = COL.panel2 end)
	row.MouseButton1Click:Connect(function()
		if onClick then pcall(onClick) end
	end)
	return row
end

local function toggleRow(parent, titleText, desc, initial, onChange)
	local on = initial and true or false
	local row = make("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = COL.panel2,
		BorderSizePixel = 0,
	}, parent)
	corner(row, 8)
	stroke(row, COL.stroke, 1, 0.15)
	local t = label(row, titleText, UDim2.new(1, -86, 0, 18), COL.text, Enum.Font.GothamBold)
	t.Position = UDim2.fromOffset(12, 8)
	t.TextSize = 12
	local d = label(row, desc, UDim2.new(1, -86, 0, 24), COL.dim)
	d.Position = UDim2.fromOffset(12, 26)
	d.TextSize = 10
	d.TextWrapped = true

	local pill = make("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(44, 24),
		BackgroundColor3 = on and COL.accent or COL.track,
		BorderSizePixel = 0,
	}, row)
	corner(pill, 12)
	local knob = make("Frame", {
		Position = UDim2.fromOffset(on and 23 or 3, 3),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = Color3.fromRGB(250, 253, 255),
		BorderSizePixel = 0,
	}, pill)
	corner(knob, 9)

	local api = {}
	function api.set(value, silent)
		on = value and true or false
		pcall(function()
			TweenService:Create(pill, TweenInfo.new(0.14), {
				BackgroundColor3 = on and COL.accent or COL.track,
			}):Play()
			TweenService:Create(knob, TweenInfo.new(0.14), {
				Position = UDim2.fromOffset(on and 23 or 3, 3),
			}):Play()
		end)
		if not silent and onChange then onChange(on) end
	end
	row.MouseButton1Click:Connect(function() api.set(not on) end)
	return api
end

local function sliderRow(parent, titleText, minimum, maximum, step, initial, fmt, onChange)
	local row = make("Frame", {
		Size = UDim2.new(1, 0, 0, 62),
		BackgroundColor3 = COL.panel2,
		BorderSizePixel = 0,
	}, parent)
	corner(row, 8)
	stroke(row, COL.stroke, 1, 0.15)
	local t = label(row, titleText, UDim2.new(1, -120, 0, 18), COL.text, Enum.Font.GothamBold)
	t.Position = UDim2.fromOffset(12, 8)
	t.TextSize = 12
	local valueLabel = label(row, "", UDim2.fromOffset(100, 18), COL.accent)
	valueLabel.Position = UDim2.new(1, -112, 0, 8)
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.TextSize = 11

	local track = make("Frame", {
		Position = UDim2.fromOffset(12, 42),
		Size = UDim2.new(1, -24, 0, 8),
		BackgroundColor3 = COL.track,
		BorderSizePixel = 0,
		Active = true,
	}, row)
	corner(track, 4)
	local fill = make("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = COL.accent,
		BorderSizePixel = 0,
	}, track)
	corner(fill, 4)
	local knob = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = Color3.fromRGB(250, 253, 255),
		BorderSizePixel = 0,
		ZIndex = 2,
	}, track)
	corner(knob, 8)

	local value = initial
	local function apply(v, silent)
		value = math.clamp(v, minimum, maximum)
		if step > 0 then
			value = minimum + math.floor((value - minimum) / step + 0.5) * step
			value = math.clamp(value, minimum, maximum)
		end
		local alpha = (maximum > minimum) and (value - minimum) / (maximum - minimum) or 0
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		valueLabel.Text = fmt(value)
		if not silent and onChange then onChange(value) end
	end
	local dragging = false
	local function fromX(x)
		local alpha = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		apply(minimum + (maximum - minimum) * alpha)
	end
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromX(input.Position.X)
		end
	end)
	conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch) then
			fromX(input.Position.X)
		end
	end)
	conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	apply(initial, true)
	return { set = function(v) apply(v, true) end, get = function() return value end }
end

local function openPicker(titleText, options, current, onPick)
	if picker then
		pcall(function() picker:Destroy() end)
		picker = nil
	end
	local overlay = make("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.5,
		ZIndex = 200,
	}, main)
	local cardH = 52 + #options * 34 + 10
	local card = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(300, cardH),
		BackgroundColor3 = COL.panel,
		BorderSizePixel = 0,
		ZIndex = 201,
	}, overlay)
	corner(card, 10)
	stroke(card, COL.accent, 1, 0.4)
	local t = label(card, string.upper(titleText), UDim2.new(1, -24, 0, 20), COL.accent, Enum.Font.GothamBold)
	t.Position = UDim2.fromOffset(12, 12)
	t.TextSize = 11
	local list = make("Frame", {
		Position = UDim2.fromOffset(10, 44),
		Size = UDim2.new(1, -20, 0, #options * 34),
		BackgroundTransparency = 1,
		ZIndex = 202,
	}, card)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list
	for _, opt in ipairs(options) do
		local selected = tostring(opt) == tostring(current)
		local b = make("TextButton", {
			Text = tostring(opt),
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextColor3 = selected and COL.accent or COL.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = selected and COL.panel2 or COL.row,
			AutoButtonColor = false,
			Size = UDim2.new(1, 0, 0, 30),
			ZIndex = 203,
		}, list)
		corner(b, 6)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.Parent = b
		b.MouseButton1Click:Connect(function()
			overlay:Destroy()
			picker = nil
			if onPick then pcall(onPick, opt) end
		end)
	end
	overlay.MouseButton1Click:Connect(function()
		overlay:Destroy()
		picker = nil
	end)
	picker = overlay
end

local function dropdownRow(parent, titleText, options, initial, onPick)
	local value = initial
	local row = make("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = COL.panel2,
		BorderSizePixel = 0,
	}, parent)
	corner(row, 8)
	stroke(row, COL.stroke, 1, 0.15)
	local t = label(row, titleText, UDim2.new(0.5, 0, 0, 18), COL.text, Enum.Font.GothamBold)
	t.Position = UDim2.fromOffset(12, 8)
	t.TextSize = 12
	local valueLabel = label(row, tostring(value), UDim2.new(0.5, -24, 0, 18), COL.accent)
	valueLabel.Position = UDim2.new(0.5, 0, 0, 8)
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.TextSize = 11
	local hint = label(row, "click to change", UDim2.new(1, -24, 0, 18), COL.dim)
	hint.Position = UDim2.fromOffset(12, 26)
	hint.TextSize = 10
	local api = {}
	function api.set(v, silent)
		value = v
		valueLabel.Text = tostring(v)
		if not silent and onPick then onPick(v) end
	end
	row.MouseButton1Click:Connect(function()
		openPicker(titleText, options, value, function(v) api.set(v) end)
	end)
	return api
end

--// tabs -----------------------------------------------------------------------

-- AUTO
local autoPage = pages[1]
section(autoPage, "stat points")
local bestStatDrop = dropdownRow(autoPage, "best stat", STATS, CFG.bestStat, function(v)
	CFG.bestStat = tostring(v)
	missCount = 0
end)
actionButton(autoPage, "PUT 1 POINT IN BEST STAT",
	"one click of the + beside the chosen stat, no loop",
	function()
		if putOne() then
			setStatus("clicked " .. CFG.bestStat .. " +  (total " .. tostring(clicks) .. ")")
		else
			setStatus("no + found for " .. CFG.bestStat .. " - run PROBE > dump gui")
		end
	end)
uiToggle.autoStats = toggleRow(autoPage, "AUTO PUT  |  click the plus",
	"clicks the + beside the chosen stat on the delay below; stops after 4 misses",
	CFG.autoStats,
	function(v)
		CFG.autoStats = v
		if v then
			clicks = 0
			missCount = 0
			setStatus("auto put armed: " .. CFG.bestStat)
		else
			setStatus("auto put off")
		end
	end)
sliderRow(autoPage, "click delay", 5, 100, 5, 25,
	function(v) return string.format("%.2fs", v * 0.01) end,
	function(v) CFG.delay = math.max(0.05, v * 0.01) end)
sliderRow(autoPage, "max clicks", 0, 500, 10, 0,
	function(v) return v == 0 and "unlimited" or tostring(v) end,
	function(v) CFG.maxClicks = v end)

-- ROLL
local rollPage = pages[2]
section(rollPage, "rolling")
uiToggle.autoRoll = toggleRow(rollPage, "AUTO ROLL",
	"clicks the visible button whose text contains ROLL every roll delay",
	CFG.autoRoll,
	function(v)
		CFG.autoRoll = v
		if v then
			lastRollRarity = nil
			setRollInfo("rolling")
			setStatus("auto roll armed")
		else
			setStatus("auto roll off")
		end
	end)
local stopDrop = dropdownRow(rollPage, "stop at rarity", { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret", "never" }, CFG.stopRarity, function(v)
	CFG.stopRarity = tostring(v)
end)
sliderRow(rollPage, "roll delay", 5, 100, 5, 25,
	function(v) return string.format("%.1fs", v * 0.1) end,
	function(v) CFG.rollDelay = math.max(0.5, v * 0.1) end)
actionButton(rollPage, "ROLL ONCE", "one click of the roll button", function()
	local btn = findRollButton()
	if btn and clickButton(btn) then
		lastRollClick = now()
		setStatus("rolled")
	else
		setStatus("no ROLL button found - run PROBE")
	end
end)
local rollInfoLabel = label(rollPage, "last rarity: none", UDim2.new(1, 0, 0, 20), COL.dim)
rollInfoLabel.TextSize = 11
setRollInfo = function(text)
	if rollInfoLabel then rollInfoLabel.Text = "last rarity: " .. tostring(text or "none") end
end

-- PROBE
local probePage = pages[3]
section(probePage, "capture")
actionButton(probePage, "DUMP VISIBLE GUI",
	"every visible button + the + found for each stat; copied to clipboard",
	function() present(dumpGui(), "gui dump") end)
actionButton(probePage, "DUMP REMOTES",
	"RemoteEvent / RemoteFunction names under ReplicatedStorage",
	function() present(dumpRemotes(), "remote dump") end)
actionButton(probePage, "CAPTURE CLICKS 15s",
	"records the game's own remote calls while you click a + and roll once",
	function()
		if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
			setStatus("this executor has no hookmetamethod")
			return
		end
		local captured = 0
		local old
		local okHook = pcall(function()
			old = hookmetamethod(game, "__namecall", function(self, ...)
				local method = getnamecallmethod()
				if method == "FireServer" and typeof(self) == "Instance"
					and (self:IsA("RemoteEvent") or self:IsA("UnreliableRemoteEvent")) then
					local parts = {}
					for i = 1, select("#", ...) do
						local v = select(i, ...)
						local kind = typeof(v)
						if kind == "Instance" then
							parts[#parts + 1] = v:GetFullName()
						elseif kind == "table" then
							parts[#parts + 1] = "{table}"
						else
							parts[#parts + 1] = tostring(v)
						end
					end
					captured = captured + 1
					print("[SUPERHERO CAPTURE] " .. self:GetFullName() .. "  args: " .. table.concat(parts, " | "))
				end
				return old(self, ...)
			end)
		end)
		if not okHook or not old then
			setStatus("capture hook failed")
			return
		end
		setStatus("capturing for 15s - click a + and roll once")
		task.delay(15, function()
			pcall(function() hookmetamethod(game, "__namecall", old) end)
			print("[SUPERHERO CAPTURE] done, " .. tostring(captured) .. " remote call(s)")
			setStatus("capture done: " .. tostring(captured) .. " call(s)")
		end)
	end)
local note = label(probePage, "read-only: this tab prints and copies, it does not fire anything.",
	UDim2.new(1, 0, 0, 34), COL.dim)
note.TextSize = 10
note.TextWrapped = true

-- SYS
local sysPage = pages[4]
section(sysPage, "input")
dropdownRow(sysPage, "click method", { "auto", "signal", "virtual" }, CFG.clickMethod, function(v)
	CFG.clickMethod = tostring(v)
end)
local sysNote = label(sysPage,
	"auto tries firesignal first, then a virtual mouse click. pick virtual if signal does nothing in your executor.",
	UDim2.new(1, 0, 0, 40), COL.dim)
sysNote.TextSize = 10
sysNote.TextWrapped = true
actionButton(sysPage, "UNLOAD", "stops both loops and closes the panel", function()
	if unload then unload() end
end)

--// window controls ------------------------------------------------------------

local minimized = false
minBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	tabsBar.Visible = not minimized
	body.Visible = not minimized
	footer.Visible = not minimized
	main.Size = minimized and UDim2.fromOffset(W, 46) or UDim2.fromOffset(W, H)
	minBtn.Text = minimized and "+" or "–"
end)

closeBtn.MouseButton1Click:Connect(function()
	if unload then unload() end
end)

local dragging = false
local dragStart = nil
local startPos = nil
header.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = main.Position
	end
end)
conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
	if not dragging then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		local d = input.Position - dragStart
		local nx = startPos.X.Offset + d.X / scale
		local ny = startPos.Y.Offset + d.Y / scale
		local vps = vp / scale
		nx = math.clamp(nx, -W + 120, vps.X - 120)
		ny = math.clamp(ny, 0, vps.Y - 40)
		main.Position = UDim2.fromOffset(nx, ny)
	end
end)
conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

setStatus = function(text)
	if statusLabel then statusLabel.Text = tostring(text) end
end
setStatus("ready  |  " .. CFG.bestStat)

--// loops ----------------------------------------------------------------------

task.spawn(function()
	while not dead do
		local t = now()
		if CFG.autoStats and t >= lastStatAt + CFG.delay then
			lastStatAt = t
			local ok = putOne()
			if not ok and missCount >= 4 then
				CFG.autoStats = false
				if uiToggle.autoStats then uiToggle.autoStats.set(false, true) end
				setStatus("stopped: no + found for " .. CFG.bestStat)
			end
			if CFG.maxClicks > 0 and clicks >= CFG.maxClicks then
				CFG.autoStats = false
				if uiToggle.autoStats then uiToggle.autoStats.set(false, true) end
				setStatus("stopped after " .. tostring(clicks) .. " clicks")
			end
			if CFG.autoStats then
				setStatus(CFG.bestStat .. "  |  clicks " .. tostring(clicks))
			end
		end
		if CFG.autoRoll and t >= lastRollAt + CFG.rollDelay then
			lastRollAt = t
			local btn = findRollButton()
			if btn then
				clickButton(btn)
				lastRollClick = t
				setStatus("rolling  |  last " .. tostring(lastRollRarity or "?"))
			else
				CFG.autoRoll = false
				if uiToggle.autoRoll then uiToggle.autoRoll.set(false, true) end
				setStatus("stopped: no ROLL button visible")
			end
		end
		if t - lastScan > 0.4 then
			lastScan = t
			-- only read rarity text for a few seconds after an actual roll click,
			-- so a static rarity chart does not stop the loop on its own
			if lastRollClick > 0 and t - lastRollClick < 5 then
				local rank, word = readRarity()
				if rank and word then
					lastRollRarity = word
					setRollInfo(word)
					if CFG.autoRoll and CFG.stopRarity ~= "never" then
						local want = rarityRank(CFG.stopRarity)
						if want > 0 and rank >= want then
							CFG.autoRoll = false
							if uiToggle.autoRoll then uiToggle.autoRoll.set(false, true) end
							setStatus("stopped on " .. string.upper(word) .. " (target " .. CFG.stopRarity .. ")")
						end
					end
				end
			end
		end
		task.wait(0.05)
	end
end)

--// lifecycle -------------------------------------------------------------------

unload = function()
	if dead then return end
	dead = true
	CFG.autoStats = false
	CFG.autoRoll = false
	for _, c in ipairs(conns) do
		pcall(function() c:Disconnect() end)
	end
	conns = {}
	if inputConn then
		pcall(function() inputConn:Disconnect() end)
		inputConn = nil
	end
	pcall(function() screen:Destroy() end)
	if _G.SuperheroPanel and _G.SuperheroPanel.unload == unload then
		_G.SuperheroPanel = nil
	end
	print("[SUPERHERO] unloaded")
end

_G.SuperheroPanel = { unload = unload }

inputConn = UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.P then
		unload()
	end
end)

print("[SUPERHERO] loaded  place=" .. tostring(game.PlaceId) .. "  stat=" .. CFG.bestStat)
