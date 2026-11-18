--[[
	SUPERHERO DUELS -- AUTO PUT BEST

	game: [NEW] Superhero Duels
	root place: 108228062074817  (universe 10774293033)

	what it does
	  AUTO PUT       finds the "+" button beside a stat name (Strength, Speed,
	                 Superpower, IQ, Battle IQ, Durability) and clicks it. it
	                 uses the game's own buttons, no remotes are invented.
	  PUT 1 POINT    one click of the chosen stat's plus, no loop.
	  AUTO ROLL      finds the visible button whose text contains ROLL and
	                 clicks it on a delay, optionally stopping when the rolled
	                 rarity reaches the target.
	  PROBE          dumps the visible GUI and every RemoteEvent /
	                 RemoteFunction under ReplicatedStorage, and can record the
	                 remotes the game fires while you click a stat once.

	honest bits
	  - this has not been run in the game yet. the game is new and has no
	    public remote map, so the panel works by finding the on-screen buttons.
	  - if it cannot find a "+" button, run PROBE -> dump gui then paste the
	    output. the paths and positions show how this build lays the menu out.
	  - nothing here writes profile data, grants stats or calls an invented
	    remote. the only clicks are the same ones your mouse would send.
	  - P panics: stops both loops and closes the window.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local LocalPlayer = Players.LocalPlayer

local CFG = {
	autoStats = false,
	bestStat = "Superpower",
	delay = 0.25,
	maxClicks = 0, -- 0 = unlimited
	autoRoll = false,
	rollDelay = 2.5,
	stopRarity = "Rare",
	clickMethod = "auto", -- auto / signal / virtual
}

local STATS = { "Superpower", "Strength", "Speed", "Durability", "Battle IQ", "IQ" }
local RARITIES = { "common", "uncommon", "rare", "epic", "legendary", "mythic", "secret", "ultra" }

local dead = false
local clicks = 0
local lastStatAt = 0
local lastRollAt = 0
local lastScan = 0
local missCount = 0
local lastFound = nil
local lastRollRarity = nil
local rollArmedAt = 0
local inputConn = nil
local window

local function now()
	return os.clock()
end

local function notify(text)
	if not window then return end
	pcall(function()
		window:Notify({ title = "SUPERHERO DUELS", content = tostring(text), duration = 4 })
	end)
end

local function log(text)
	print("[SUPERHERO AUTO] " .. tostring(text))
end

--// ui -------------------------------------------------------------------------

if _G.SuperheroAutoPanel and _G.SuperheroAutoPanel.unload then
	pcall(_G.SuperheroAutoPanel.unload)
end

local okLib, Rayfield = pcall(function()
	return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)
if not okLib or type(Rayfield) ~= "table" then
	warn("[SUPERHERO AUTO] Rayfield failed to load; internet is required for the window")
	return
end

local okWin, win = pcall(function()
	return Rayfield:CreateWindow({
		Name = "SUPERHERO DUELS // AUTO",
		LoadingTitle = "SUPERHERO DUELS",
		LoadingSubtitle = "auto put best  -  auto roll",
		KeySystem = false,
	})
end)
if not okWin or not win then
	warn("[SUPERHERO AUTO] window failed: " .. tostring(win))
	return
end
window = win

pcall(function()
	win:ChangeTheme({
		WindowColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(16, 10, 8)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(36, 20, 12)),
		}),
		ShadowColor = Color3.fromRGB(6, 3, 2),
		CornerRoundness = UDim.new(0, 16),
		ElementCornerRadius = UDim.new(0, 10),
		PillCornerRadius = UDim.new(1, 0),
		AccentColor = Color3.fromRGB(255, 176, 32),
		AccentStroke = Color3.fromRGB(255, 236, 150),
		AccentGlow = 0.55,
		ContentColor = Color3.fromRGB(250, 244, 236),
		TitlingColor = Color3.fromRGB(255, 255, 255),
		ElementStroke = Color3.fromRGB(74, 44, 22),
		ElementStrokeHover = Color3.fromRGB(255, 176, 32),
		SliderProgress = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 120)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 150, 24)),
		}),
	})
end)

local mainTab = win:CreateTab({ name = "AUTO" })
local rollTab = win:CreateTab({ name = "ROLL" })
local probeTab = win:CreateTab({ name = "PROBE" })
local sysTab = win:CreateTab({ name = "SYS" })

local statusText = mainTab:CreateText({ name = "status", text = "idle" })
local clickText = rollTab:CreateText({ name = "roll status", text = "idle" })

--// gui discovery --------------------------------------------------------------

local function visible(inst)
	if not inst or not inst:IsA("GuiObject") then return false end
	if not inst.Visible then return false end
	if inst.AbsoluteSize.X < 4 or inst.AbsoluteSize.Y < 4 then return false end
	local p = inst.Parent
	while p and p ~= game do
		if p:IsA("ScreenGui") and not p.Enabled then return false end
		if p:IsA("GuiObject") and not p.Visible then return false end
		p = p.Parent
	end
	return true
end

local function playerGui()
	if not LocalPlayer then return nil end
	return LocalPlayer:FindFirstChildOfClass("PlayerGui")
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

-- the screenshot rows are label on the left and a square + button immediately
-- right of it, on the same line. this finds that button by geometry rather
-- than by a hard-coded path, so a re-skin does not break it.
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
			elseif #loose < 12 and string.find(txt, wanted, 1, true) then
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
					score = score - 1000 -- prefer a literal plus
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

--// clicking -------------------------------------------------------------------

local function signal(btn)
	if type(firesignal) ~= "function" then return false end
	local ok = pcall(firesignal, btn.MouseButton1Click)
	return ok
end

local function virtualClick(btn)
	local ok = pcall(function()
		local x, y = center(btn)
		VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
		task.wait(0.03)
		VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
	end)
	return ok
end

local function clickButton(btn)
	if not btn then return false end
	if CFG.clickMethod == "signal" then
		return signal(btn)
	elseif CFG.clickMethod == "virtual" then
		return virtualClick(btn)
	end
	-- auto: a signal is exact when the executor has it; a virtual mouse click is
	-- the fallback for executors without firesignal.
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
	lastFound = btn
	local ok = clickButton(btn)
	if ok then
		clicks = clicks + 1
		log("clicked " .. CFG.bestStat .. " + (" .. tostring(clicks) .. ")")
	end
	return ok
end

local function findRollButton()
	local best = nil
	local bestScore = nil
	for _, btn in ipairs(guiObjects("TextButton")) do
		local txt = string.lower(btn.Text or "")
		if string.find(txt, "roll", 1, true) and not string.find(txt, "control", 1, true) then
			-- prefer the largest match: a full-width ROLL bar beats a tiny label
			local size = btn.AbsoluteSize.X * btn.AbsoluteSize.Y
			if not bestScore or size > bestScore then
				bestScore = size
				best = btn
			end
		end
	end
	return best
end

local function readRarity()
	local bestRank = nil
	local bestWord = nil
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

--// loops ----------------------------------------------------------------------

task.spawn(function()
	while not dead do
		local t = now()
		if CFG.autoStats and t >= lastStatAt + CFG.delay then
			lastStatAt = t
			local ok = putOne()
			if not ok and missCount >= 4 then
				CFG.autoStats = false
				pcall(function() win:Set("ssd_autoStats", false) end)
				notify("stopped: no + button found for " .. CFG.bestStat)
			end
			if CFG.maxClicks > 0 and clicks >= CFG.maxClicks then
				CFG.autoStats = false
				pcall(function() win:Set("ssd_autoStats", false) end)
				notify("stopped after " .. tostring(clicks) .. " clicks")
			end
			if statusText then
				pcall(function()
					statusText:Set(CFG.bestStat .. "  |  clicks " .. tostring(clicks))
				end)
			end
		end
		if CFG.autoRoll and t >= lastRollAt + CFG.rollDelay then
			lastRollAt = t
			local btn = findRollButton()
			if btn then
				rollArmedAt = t
				clickButton(btn)
				log("clicked ROLL")
				if clickText then
					pcall(function() clickText:Set("rolling  |  last " .. tostring(lastRollRarity or "?")) end)
				end
			else
				CFG.autoRoll = false
				pcall(function() win:Set("ssd_autoRoll", false) end)
				notify("stopped: no ROLL button visible")
			end
		end
		if t - lastScan > 0.4 then
			lastScan = t
			local rank, word = readRarity()
			if rank and word then
				lastRollRarity = word
				if CFG.autoRoll and CFG.stopRarity ~= "never" then
					local want = rarityRank(CFG.stopRarity)
					if want > 0 and rank >= want then
						CFG.autoRoll = false
						pcall(function() win:Set("ssd_autoRoll", false) end)
						notify("stopped on " .. string.upper(word) .. " (target " .. CFG.stopRarity .. ")")
					end
				end
			end
		end
		task.wait(0.05)
	end
end)

--// main tab -------------------------------------------------------------------

mainTab:CreateSection({ name = "STAT POINTS" })
mainTab:CreateDropdown({
	name = "best stat",
	description = "the row this panel clicks. the + button is found by its position beside this stat name, so the game's own handler runs.",
	flag = "ssd_bestStat",
	options = STATS,
	value = CFG.bestStat,
	callback = function(v)
		CFG.bestStat = tostring(v)
		missCount = 0
	end,
})
mainTab:CreateToggle({
	name = "AUTO PUT  |  click the plus",
	description = "keeps clicking the + beside the chosen stat on the delay below. it stops on its own after four misses (button gone) or when max clicks is reached. panic P stops it instantly.",
	flag = "ssd_autoStats",
	value = false,
	callback = function(v)
		CFG.autoStats = v
		if v then
			clicks = 0
			missCount = 0
			notify("auto put armed: " .. CFG.bestStat)
		end
	end,
})
mainTab:CreateButton({
	name = "PUT 1 POINT IN BEST STAT",
	description = "one click, no loop. useful for checking the button is found before leaving the toggle on.",
	callback = function()
		if putOne() then
			notify("clicked " .. CFG.bestStat .. " +  (total " .. tostring(clicks) .. ")")
		else
			notify("no + button found for " .. CFG.bestStat .. " - run PROBE -> dump gui")
		end
		if statusText then pcall(function() statusText:Set(CFG.bestStat .. "  |  clicks " .. tostring(clicks)) end) end
	end,
})
mainTab:CreateSlider({
	name = "click delay",
	description = "seconds between + clicks.",
	flag = "ssd_delay",
	range = { 5, 100 },
	increment = 5,
	value = 25,
	suffix = " x0.01s",
	callback = function(v) CFG.delay = math.max(0.05, tonumber(v) * 0.01) end,
})
mainTab:CreateSlider({
	name = "max clicks",
	description = "0 means keep going until the button disappears or you panic.",
	flag = "ssd_maxClicks",
	range = { 0, 500 },
	increment = 10,
	value = 0,
	callback = function(v) CFG.maxClicks = tonumber(v) or 0 end,
})

--// roll tab -------------------------------------------------------------------

rollTab:CreateSection({ name = "ROLLING" })
rollTab:CreateToggle({
	name = "AUTO ROLL",
	description = "clicks the visible button whose text contains ROLL every roll delay. it does not equip or choose anything for you.",
	flag = "ssd_autoRoll",
	value = false,
	callback = function(v)
		CFG.autoRoll = v
		if v then
			lastRollRarity = nil
			notify("auto roll armed")
		end
	end,
})
rollTab:CreateDropdown({
	name = "stop at rarity",
	description = "when a visible rarity label at or above this appears after a roll, auto roll turns itself off. 'never' keeps rolling.",
	flag = "ssd_stopRarity",
	options = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret", "never" },
	value = CFG.stopRarity,
	callback = function(v) CFG.stopRarity = tostring(v) end,
})
rollTab:CreateSlider({
	name = "roll delay",
	description = "seconds between roll clicks. keep it above the game's roll animation.",
	flag = "ssd_rollDelay",
	range = { 5, 100 },
	increment = 5,
	value = 25,
	suffix = " x0.1s",
	callback = function(v) CFG.rollDelay = math.max(0.5, tonumber(v) * 0.1) end,
})
rollTab:CreateButton({
	name = "ROLL ONCE",
	description = "one click of the roll button.",
	callback = function()
		local btn = findRollButton()
		if btn and clickButton(btn) then
			notify("rolled")
		else
			notify("no ROLL button found - run PROBE")
		end
	end,
})

--// probe ---------------------------------------------------------------------

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
		notify(label .. " printed and copied to clipboard")
	else
		notify(label .. " printed to console (no setclipboard)")
	end
end

probeTab:CreateButton({
	name = "DUMP VISIBLE GUI",
	description = "lists every visible button and the + button it finds for each stat. paste this if auto put says no button found.",
	callback = function() present(dumpGui(), "gui dump") end,
})
probeTab:CreateButton({
	name = "DUMP REMOTES",
	description = "lists RemoteEvent / RemoteFunction names under ReplicatedStorage. read-only.",
	callback = function() present(dumpRemotes(), "remote dump") end,
})

probeTab:CreateButton({
	name = "CAPTURE CLICKS 15s",
	description = "hooks __namecall for 15 seconds and prints any remote the game fires while you manually click a + button and roll once. run it, click the game UI, then paste the [SUPERHERO CAPTURE] lines.",
	callback = function()
		if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
			notify("this executor has no hookmetamethod - use the GUI dump instead")
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
			notify("capture hook failed")
			return
		end
		notify("capturing for 15s - click a stat + once and roll once")
		task.delay(15, function()
			pcall(function() hookmetamethod(game, "__namecall", old) end)
			print("[SUPERHERO CAPTURE] done, " .. tostring(captured) .. " remote call(s)")
			notify("capture done: " .. tostring(captured) .. " remote call(s) in console")
		end)
	end,
})
probeTab:CreateText({
	name = "note",
	text = "nothing in this tab writes anything. the capture only listens to the game's own remote calls for 15 seconds.",
})

--// sys -----------------------------------------------------------------------

sysTab:CreateDropdown({
	name = "click method",
	description = "auto tries firesignal first and falls back to a virtual mouse click. pick signal or virtual if only one works in your executor.",
	flag = "ssd_clickMethod",
	options = { "auto", "signal", "virtual" },
	value = CFG.clickMethod,
	callback = function(v) CFG.clickMethod = tostring(v) end,
})
sysTab:CreateText({
	name = "panic",
	text = "press P at any time: both loops stop and the window closes.",
})
sysTab:CreateButton({
	name = "UNLOAD",
	description = "same as P: stop, disconnect and destroy the window.",
	callback = function()
		if _G.SuperheroAutoPanel and _G.SuperheroAutoPanel.unload then
			_G.SuperheroAutoPanel.unload()
		end
	end,
})

--// lifecycle -----------------------------------------------------------------

local api = {}
function api.unload()
	if dead then return end
	dead = true
	CFG.autoStats = false
	CFG.autoRoll = false
	if inputConn then
		pcall(function() inputConn:Disconnect() end)
		inputConn = nil
	end
	pcall(function()
		if type(win.Unload) == "function" then
			win:Unload()
		elseif win.screenGui then
			win.screenGui:Destroy()
		elseif type(win.Destroy) == "function" then
			win:Destroy()
		end
	end)
	if _G.SuperheroAutoPanel == api then
		_G.SuperheroAutoPanel = nil
	end
	print("[SUPERHERO AUTO] unloaded")
end
_G.SuperheroAutoPanel = api

inputConn = UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.P then
		api.unload()
	end
end)

log("loaded  place=" .. tostring(game.PlaceId) .. "  stat=" .. CFG.bestStat)
