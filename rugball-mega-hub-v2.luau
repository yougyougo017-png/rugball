--[[
	RUGBALL MEGA HUB v2 -- one file, every game, nothing fetched

	Every suite is embedded whole in this file and dispatched by game.PlaceId.
	One execute / loadstring, no web host, no readfile fallback, no chain
	files. The place you are in decides what comes up.

	place map
		81469298413354   Rugball                  football
		77844202849858   Rugball (place v2)       football
		80119315919763   Drive Duels              taf bypass, then football
		124617195142196  Build An Anime Character anime
		126424052816775  NBA: Heroes              nba, then swish
		122283827051026  NBA: Heroes (place v144) nba
		134954408729617  Basketball Duels         duels
		125942529011157  Throw A Football         taf bypass, then qb aimbot
		96120449121277   PhysBox (HitBout)       physbox

	the taf bypass runs before the suites that need it, so its hooks are live
	before any suite code touches the controllers.

	every suite keeps its own replace-not-stack teardown, its own _G key and
	its own Rayfield window, so suites sharing a place (nba + swish on
	NBA: Heroes) run side by side without tearing each other down.

	unknown place: a picker window opens with the live place id, one button
	per known game and one per single suite, so a new place version of a
	known game still has a way in. wire new places into Hub.ORDER below.
]]

local Hub = {}

-- one row per wired game: place id, label, suite chain in run order
Hub.ORDER = {
	{ place = 81469298413354,  label = "RUGBALL",          suites = { "football" } },
	{ place = 77844202849858,  label = "RUGBALL V2",       suites = { "football" } },
	{ place = 80119315919763,  label = "DRIVE DUELS",      suites = { "taf_bypass", "football" } },
	{ place = 124617195142196, label = "BUILD AN ANIME",   suites = { "anime" } },
	{ place = 126424052816775, label = "NBA HEROES",       suites = { "nba", "swish" } },
	{ place = 122283827051026, label = "NBA HEROES V144",  suites = { "nba" } },
	{ place = 134954408729617, label = "BASKETBALL DUELS", suites = { "duels" } },
	{ place = 125942529011157, label = "THROW A FOOTBALL", suites = { "taf_bypass", "qb_aimbot" } },
	{ place = 96120449121277,  label = "PHYSBOX HITBOUT",  suites = { "physbox" } },
}

Hub.GAMES = {}
for _, g in ipairs(Hub.ORDER) do
	Hub.GAMES[g.place] = g
end

Hub.SUITE_ORDER = { "football", "anime", "nba", "swish", "duels", "qb_aimbot", "taf_bypass", "physbox" }

Hub.SUITE_NAMES = {
	football   = "football panel    |  aim / tackle / block",
	anime      = "anime panel       |  claims / wheel / chairs",
	nba        = "nba panel         |  court suite",
	swish      = "swish             |  auto perfect shot",
	duels      = "duels panel       |  court panel",
	qb_aimbot  = "qb aimbot         |  throw a football",
	taf_bypass = "taf bypass        |  anticheat + speed",
	physbox    = "physbox corner    |  autopilot / full power / inf stamina",
}

Hub.SUITE = {}

-- run one embedded suite. pcall'd: a failing suite costs one warn, never the hub.
function Hub.run(name)
	local fn = Hub.SUITE[name]
	if type(fn) ~= "function" then
		warn("[RugballHub] no suite named " .. tostring(name))
		return false
	end
	local ok, err = pcall(fn)
	if ok then
		print("[RugballHub] suite up: " .. name)
		return true
	end
	warn("[RugballHub] suite " .. name .. " errored: " .. tostring(err))
	return false
end

function Hub.runAll(list)
	for _, name in ipairs(list) do
		Hub.run(name)
	end
end

--// embedded suite: football  (from football-panel.luau) =========================
Hub.SUITE.football = function()
--[[
	RUGBALL PANEL -- Rugball / football (place 81469298413354)
	Client-side only. One Rayfield Gen2 window, one render loop, three modules:
	aim/throw, auto-tackle, auto-block.

	Everything the three old scripts did, with the shake fixes baked in:
		* CurrentCamera is never written. RigClient owns it with
		  BindToRenderStep("RigCamera", Camera.Value) and a spring, so a second
		  writer just fights it.
		* ThrowAimingLocal is never touched. It lerps a 5-stud shoulder offset
		  in that same camera, so setting it lurches the view.
		* Steer is rebuilt at steerHz with a deadzone instead of every frame.
		  Re-projecting a world direction into a camera that follows the rig is
		  what makes the rig hunt.

	The game's own throw formula, from BallThrowConfig:
		lands at start + dir * min(|point-start|, 4 + charge*280, 226.875)
	so charge = (dist - 4)/280 + 0.09 and the ball lands on the picked man.
	The remote is fired on release with the hold time as charge; the server runs
	WindupTime + ReleaseDelay itself. So we fire immediately and fold that lag
	into the lead solve instead of waiting before the remote.

	This script also unbinds AutoTackle / AutoBlock / QBAim and deletes their
	huds and esp folders on load, so the old scripts can stay installed but idle.

	Hosted: this file is the payload. Upload it somewhere that serves raw text
	(github raw, gist raw, any static host) and run it with
		loadstring(game:HttpGet("<raw url>"))()
	rugball-loader.luau in the same folder is that call with cache-busting and
	readable errors.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

--// replace, not stack ---------------------------------------------------------
-- a re-run has to take the previous run down first. without this every reload
-- leaves a second window behind, and the newest one draws underneath the oldest.

local function sweepOldWindows()
	local containers = { game:GetService("CoreGui"), LocalPlayer:FindFirstChild("PlayerGui") }
	local okHui, hui = pcall(function() return gethui() end)
	if okHui and hui then
		containers[#containers + 1] = hui
	end
	for _, cont in ipairs(containers) do
		if cont then
			local ok, list = pcall(function() return cont:GetDescendants() end)
			if ok and list then
				for _, inst in ipairs(list) do
					if inst:IsA("ScreenGui") and inst.DisplayOrder == 99999 and inst:FindFirstChild("RUGBALL", true) then
						pcall(function() inst:Destroy() end)
					end
				end
			end
		end
	end
end

do
	local old = _G.Slim
	if type(old) == "table" then
		local oldWindow = old.panel
		pcall(function()
			if old.stop then old.stop() end
		end)
		if oldWindow then
			pcall(function() oldWindow:Unload() end)
			pcall(function()
				if oldWindow.screenGui then oldWindow.screenGui:Destroy() end
			end)
		end
	end
	pcall(sweepOldWindows)
end

--// config --------------------------------------------------------------------

local CFG = {
	-- aim / throw
	autopilot   = false,  -- one switch: qb throws + defense runs itself
	aim         = true,
	autoThrow   = false,
	teamOnly    = true,
	maxDist     = 195,    -- ball range is 226.875
	fov         = 42,     -- degrees off the crosshair
	lead        = 0,      -- extra studs thrown ahead of the receiver, 0-100
	hoverPick   = true,
	hoverRelease = 1.2,
	passType    = "Bullet",   -- Bullet | Lob | auto
	autoLobAt   = 65,         -- auto switches to a lob past this distance
	openGate    = 0,          -- min separation before auto throw fires, 0 = off
	hitPop      = true,
	banger      = true,    -- slam text on big hits
	chargePad   = 0.09,

	-- fake / no-look throw stuff
	pumpFake    = false,   -- E turns into a pump: fake hold, then fire
	fakeSpike   = false,   -- spike it, then throw the fake
	fakeFumble  = false,   -- strip bait: looks loose, fires a beat later
	coach       = true,    -- reads the coverage and calls the throw
	horizon     = 0.35,    -- tomorrow throw: solve this far past the catch point
	routeLock   = true,    -- auto-lock your most-thrown man when the ball hits your hand
	pumpDelay   = 0.85,    -- seconds the fake holds before the throw
	noLook      = false,   -- throw off the snap dir, not the live crosshair
	scramble    = false,   -- break the throw side to the hash
	scrambleAmt = 6,        -- studs of side scramble
	sepAssist   = false,   -- extra push on the deep receiver

	-- tackle
	tackle      = true,
	pursue      = false,
	dive        = false,  -- dive is a lunge: ~12 studs in a third of a second
	tackleRange = 7.5,
	diveRange   = 12.0,
	tackleHold  = 0.55,
	tackleCd    = 1.15,
	tackleLead  = true,    -- chase the intercept point, not the body
	dodgeTruck  = true,    -- sidestep the truck spike instead of eating it
	swarm       = true,    -- gang tackle: take the escape lane, not the pile
	tackleTele  = true,    -- teleport right on top of the enemy carrier to tackle
	tackleTeleY = 2,       -- studs above the carrier when you land

	-- catch / ball magnet: pull straight at the ball's landing point so you're
	-- under it when it comes down. reads the sim's own LandingPoint attribute.
	catchMagnet = false,   -- steer at the ball's landing point while it's in flight
	magnetRadius= 28,      -- max distance to engage the magnet
	magnetLead  = true,    -- arrive a beat before the ball lands
	magnetCatch = true,    -- auto dive at the very end of the flight
	magnetSpeed = 1.0,     -- steer strength while magnet is active (1 = full)
	ballToMe    = false,   -- teleport the loose ball straight to your rig
	ballToMeY   = 4,       -- studs above you when it lands
	teleToPlay  = true,    -- teleport you to the ball / play
	teleOffset  = 6,       -- studs away from the ball when you land

	antiFall    = true,
	escapeJuke  = false,   -- sidestep the hit instead of eating it while holding
	speed       = false,   -- cruise speed bonus through the raw sim channel
	speedMult   = 1.15,    -- 1.15 = about +4 st/s on the cruise (1.0 = stock)
	rushSurge   = true,    -- tackle/block drive adds +5 st/s through the sim
	maxPhysique = true,    -- strength 999 + zero physique penalty on our rig (client side)
	autoPump    = true,    -- pocket coverage fires the pump fake first
	meatShield  = false,   -- block path: cover both lanes, not one threat
	ghostRoute  = true,    -- neon line: where the pick will actually be
	statCard    = true,    -- floating statline hud

	-- ultimate batch two: everything else
	coverHeat   = true,    -- 7x7 heat grid on the field around the pick
	diveLead    = true,    -- aim the dive at where the carrier WILL be
	diveLeadTime= 0.22,    -- seconds of carrier motion the dive leads by
	jukeBait    = true,    -- burst sidestep right before the hit lands
	replay      = true,    -- neon trail of your last run-back
	chatSync    = true,    -- receive friend builds sent through chat

	-- defense assist
	intercept   = false,
	interceptRange = 40,
	pathing     = true,
	guard       = false,   -- auto guard: sit the man the enemy throw is for
	guardStand  = 3.5,     -- studs from the receiver, on the ball side
	guardJump   = 7,       -- contest window: ball this close to the catch spot, jump
	deepHalf    = false,   -- pre-throw: park over the top of the deepest receiver

	-- block
	block       = true,
	drive       = true,
	blockEngage = 4.2,
	blockScan   = 26.0,
	blockHold   = 0.9,
	blockCd     = 0.5,
	yieldTo     = 11.0,

	-- look
	espAim      = true,
	espCarrier  = true,
	espThreat   = true,
	tracers     = true,
	passArc     = true,    -- neon beam from the release point to the landing spot

	-- steering
	steerGain   = 1.0,
	steerHz     = 12.5,
	steerDead   = 0.12,

	-- radar
	radarRange  = 55,
}

-- stock snapshot: page one of the build share. only the keys a user touches
-- travel in the short chat code; everything still stock stays out.
local CFG_STOCK = {}
for k, v in pairs(CFG) do CFG_STOCK[k] = v end

-- settings survive a reload: _G.SlimCfg holds the last saved build and the
-- shutdown hook writes it back out before the sweep tears everything down
do
	local saved = _G.SlimCfg
	if type(saved) == "table" then
		for k, v in pairs(saved) do
			if type(v) == type(CFG[k]) then CFG[k] = v end
		end
	end
end

-- hot routes: three saved throws (receiver name + lead + pass type). the
-- routes table lives on _G too, so the playbook survives a reload.
local hotRoutes = _G.SlimRoutes or {}
_G.SlimRoutes = hotRoutes

-- panic state lives here so saveCfg (declared below) can see it
local panicSnapshot = nil

local function saveCfg()
	-- a panicked build is NOT the user's build: skip persisting while the
	-- kill switch is on, so a reload mid-panic comes back with the real setup
	if panicSnapshot then return end
	local copy = {}
	for k, v in pairs(CFG) do copy[k] = v end
	_G.SlimCfg = copy
	pcall(function() _G.SlimRoutes = hotRoutes end)
end

-- panic: one press fells every toggle in one cut, a second press brings the
-- whole build back out of the snapshot. for the moment someone walks past
-- your screen. booleans only - sliders hold no secrets.
local function panicRestore()
	if not panicSnapshot then return false end
	local snap = panicSnapshot
	panicSnapshot = nil
	-- window is declared later in the file, so panel handles come from _G
	local w = _G.QBAim and _G.QBAim.panel
	for k in pairs(snap) do
		CFG[k] = true
		if w and w.controls then
			local ctl = w.controls[k]
			if ctl and ctl.Set then pcall(function() ctl:Set(true, false) end) end
		end
	end
	mode = "panic restored"
	pcall(saveCfg)
	return true
end
local function panic()
	if panicSnapshot then
		panicRestore()
		return true
	end
	panicSnapshot = {}
	local n = 0
	for k, v in pairs(CFG) do
		if type(v) == "boolean" and v then
			panicSnapshot[k] = true
			CFG[k] = false
			n = n + 1
			if _G.QBAim and _G.QBAim.panel and _G.QBAim.panel.controls then
				local ctl = _G.QBAim.panel.controls[k]
				if ctl and ctl.Set then pcall(function() ctl:Set(false, false) end) end
			end
		end
	end
	mode = string.format("PANIC %d toggles off", n)
	print(string.format("[Slim] panic: %d toggles killed (press again to restore)", n))
	return true
end

-- build share: the whole build (settings + playbook) as one paste string your
-- friends can load. encodes via json, validates every key before applying.
local HttpService = game:GetService("HttpService")

local function buildShareString()
	local payload = { cfg = {}, routes = {} }
	for k, v in pairs(CFG) do payload.cfg[k] = v end
	for i = 1, 3 do
		if hotRoutes[i] then payload.routes[tostring(i)] = hotRoutes[i] end
	end
	return HttpService:JSONEncode(payload)
end

-- short share: only the keys that drifted off stock + the playbook. small
-- enough to ride in a few chat messages, which is what team sync uses.
local function buildShortShare()
	local payload = { v = "s", d = {}, routes = {} }
	for k, v in pairs(CFG) do
		if CFG_STOCK[k] ~= v then payload.d[k] = v end
	end
	for i = 1, 3 do
		if hotRoutes[i] then payload.routes[tostring(i)] = hotRoutes[i] end
	end
	return HttpService:JSONEncode(payload)
end

local function applyShareString(text)
	local ok, data = pcall(function() return HttpService:JSONDecode(text) end)
	if not ok or type(data) ~= "table" then return false end
	local got = 0
	-- full share carries cfg{}; a short share carries d{} (diff vs stock).
	-- both validate every key against the live table before writing.
	if type(data.cfg) ~= "table" and type(data.d) == "table" and data.v == "s" then
		for k, v in pairs(data.d) do
			if type(v) == type(CFG[k]) then
				CFG[k] = v
				got = got + 1
			end
		end
	elseif type(data.cfg) == "table" then
		for k, v in pairs(data.cfg) do
			if type(v) == type(CFG[k]) then
				CFG[k] = v
				got = got + 1
			end
		end
	else
		return false
	end
	if type(data.routes) == "table" then
		for i, r in pairs(data.routes) do
			local n = tonumber(i)
			if n and type(r) == "table" and type(r.name) == "string" then
				hotRoutes[n] = { name = r.name, lead = tonumber(r.lead) or 0, ptype = tostring(r.ptype or "Bullet") }
				got = got + 1
			end
		end
	end
	return got > 0
end

--// team build sync ------------------------------------------------------------
-- the short build code rides through chat in a few tagged chunks
-- ("SlimBuild 2/5 <data>"). anyone else running the panel with sync on
-- reassembles them live and applies the build - no clipboard, no paste.
local CODE_TAG = "SlimBuild"
local chatConns = {}
local chatBuffer = {}
local chatLastApply = 0

local function chatChunks(code)
	local n = math.ceil(#code / 170)
	n = math.clamp(n, 1, 30)
	local out = {}
	for i = 1, n do
		local s0 = (i - 1) * 170 + 1
		out[#out + 1] = string.format("%s %d/%d %s", CODE_TAG, i, n, code:sub(s0, math.min(#code, s0 + 169)))
	end
	return out
end

local function pruneChatBuffer(now)
	for key, buf in pairs(chatBuffer) do
		if now - buf.at > 25 then chatBuffer[key] = nil end
	end
end

local function chatTargetChannel()
	local tcs = game:GetService("TextChatService")
	local channels = tcs:FindFirstChild("TextChannels")
	if not channels then return nil end
	local fallback = nil
	for _, ch in ipairs(channels:GetChildren()) do
		if ch:IsA("TextChannel") then
			local lower = ch.Name:lower()
			if fallback == nil and lower:find("general") then fallback = ch end
			if lower:find("team") then return ch end
		end
	end
	return fallback
end

local function sendBuildChat()
	local code = buildShortShare()
	local chunks = chatChunks(code)
	local target = chatTargetChannel()
	if not target then
		print("[Slim] chat sync: no TextChannels found")
		return 0
	end
	for _, m in ipairs(chunks) do
		task.spawn(function()
			pcall(function() target:SendAsync(m) end)
		end)
	end
	print(string.format("[Slim] build sent over chat (%d msgs)", #chunks))
	return #chunks
end

local function handleChatMessage(msg)
	if not CFG.chatSync then return end
	local text = ""
	pcall(function() text = msg.Text or "" end)
	if #text < 20 or text:sub(1, #CODE_TAG) ~= CODE_TAG then return end
	pcall(function()
		if msg.TextSource and msg.TextSource == LocalPlayer then return end
	end)
	local i, n = text:match("^" .. CODE_TAG .. " (%d+)/(%d+)")
	if not i then return end
	i, n = tonumber(i) or 0, tonumber(n) or 1
	if i < 1 or n < 1 or n > 32 then return end
	local chunk = text:sub(#string.format("%s %d/%d ", CODE_TAG, i, n) + 1)
	local sender = "x"
	pcall(function()
		if msg.TextSource then sender = tostring(msg.TextSource.UserId) end
	end)
	local now = os.clock()
	pruneChatBuffer(now)
	local key = sender .. ":" .. n
	local buf = chatBuffer[key]
	if not buf then
		buf = { parts = {}, n = n, at = now }
		chatBuffer[key] = buf
	end
	buf.parts[i] = chunk
	buf.at = now
	local got = 0
	for j = 1, n do
		if buf.parts[j] then got = got + 1 end
	end
	if got == n and now - chatLastApply > 2 then
		chatLastApply = now
		chatBuffer[key] = nil
		local code = table.concat(buf.parts)
		if applyShareString(code) then
			pcall(saveCfg)
			print(string.format("[Slim] build synced from chat (%d msgs, %.0f chars)", n, #code))
			local w = _G.QBAim and _G.QBAim.panel
			if w and w.Notify then
				pcall(function()
					w:Notify({ title = "SLIM", content = "build loaded from chat sync", duration = 4 })
				end)
			end
		else
			print("[Slim] chat sync chunk arrived garbled - ignored")
		end
	end
end

local function bindChatSync()
	pcall(function()
		local tcs = game:GetService("TextChatService")
		local channels = tcs:FindFirstChild("TextChannels")
		if not channels then return end
		for _, ch in ipairs(channels:GetChildren()) do
			if ch:IsA("TextChannel") then
				table.insert(chatConns, ch.MessageReceived:Connect(handleChatMessage))
			end
		end
		table.insert(chatConns, channels.ChildAdded:Connect(function(ch)
			if ch:IsA("TextChannel") then
				table.insert(chatConns, ch.MessageReceived:Connect(handleChatMessage))
			end
		end))
	end)
end

local function unbindChatSync()
	for _, c in ipairs(chatConns) do
		pcall(function() c:Disconnect() end)
	end
	chatConns = {}
end

local COLORS = {
	aim     = Color3.fromRGB(255, 221, 35),
	carrier = Color3.fromRGB(255, 70, 70),
	threat  = Color3.fromRGB(90, 170, 255),
}

--// services ------------------------------------------------------------------

local BallThrowConfig, RugballThrow
task.spawn(function()
	BallThrowConfig = require(ReplicatedStorage:WaitForChild("BallThrowConfig"))
	RugballThrow = ReplicatedStorage:WaitForChild("RugballThrow")
end)

local PlayContext = LocalPlayer:WaitForChild("PlayContext")
local Tackle = PlayContext:WaitForChild("Tackle")
local Dive = PlayContext:WaitForChild("Dive")
local Steer = PlayContext:WaitForChild("Steer")
local Jump = PlayContext:FindFirstChild("Jump")

--// retire the three old scripts ----------------------------------------------

for _, label in ipairs({ "AutoTackle", "AutoBlock", "QBAim" }) do
	pcall(function() RunService:UnbindFromRenderStep(label) end)
end
for _, name in ipairs({ "AutoTackleHud", "AutoBlockHud", "QBAimHud" }) do
	local g = LocalPlayer.PlayerGui:FindFirstChild(name)
	if g then g:Destroy() end
end
for _, name in ipairs({ "QBAimEsp", "AutoTackleEsp", "AutoBlockEsp" }) do
	local f = Workspace:FindFirstChild(name)
	if f then f:Destroy() end
end

--// state ---------------------------------------------------------------------

local locked = nil          -- Model the aim/throw acts on
local lockManual = false
local lockPinned = false    -- sticky lock: hover and auto cannot steal it
local lockDropdown
local lockSig = ""
local hoverLostAt = 0
local currentEntry = nil
local snapDir = Vector3.new(0, 0, -1)   -- throw direction captured at pick time
local snapSet = false
local trackers = {}         -- [Model] = {pos, t, vel}

local pressing = false
local pressToken = 0
local nextTackle = 0
local nextDive = 0
local diveLeadAt = nil   -- when the smart dive started steering the lead
local nextBlock = 0
local nextJump = 0
local lastPickRig = nil

local steerTarget = Vector2.zero
local steerVec = Vector2.zero
local lastSteer = 0

local stickyThreat = nil
local mode = "auto"
local rushOn = false

-- the table lives on _G, so a reload keeps the session's numbers instead of
-- zeroing the dashboard every time the panel is re-run
local stats = _G.SlimStats or {}
_G.SlimStats = stats
stats.shots = stats.shots or 0
stats.lastCharge = stats.lastCharge or 0
stats.picks = stats.picks or 0
stats.tackles = stats.tackles or 0
stats.intercepts = stats.intercepts or 0
stats.completions = stats.completions or 0
stats.drops = stats.drops or 0
stats.picked = stats.picked or 0
stats.distSum = stats.distSum or 0
stats.leadSum = stats.leadSum or 0

local espFolder = Instance.new("Folder")
espFolder.Name = "SlimEsp"
espFolder.Parent = Workspace

-- statline card: a small floating HUD with the session's numbers. screen
-- corner, not a billboard - it stays put while the play runs around it, and
-- it outlives the Rayfield window if that ever refuses to load.
local statCardBody, statCardTitle
local statCardGui = Instance.new("ScreenGui")
statCardGui.Name = "SlimStatCard"
statCardGui.ResetOnSpawn = false
statCardGui.IgnoreGuiInset = true
statCardGui.DisplayOrder = 9000
do
	local ok = pcall(function()
		statCardGui.Parent = game:GetService("CoreGui")
	end)
	if not ok then
		local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if pg then pcall(function() statCardGui.Parent = pg end) end
	end
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(1, 1)
	card.Position = UDim2.new(1, -14, 1, -14)
	card.Size = UDim2.new(0, 208, 0, 78)
	card.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
	card.BackgroundTransparency = 0.25
	card.BorderSizePixel = 0
	card.Parent = statCardGui
	pcall(function()
		local cr = Instance.new("UICorner")
		cr.CornerRadius = UDim.new(0, 8)
		cr.Parent = card
		local cs = Instance.new("UIStroke")
		cs.Color = Color3.fromRGB(178, 255, 64)
		cs.Transparency = 0.55
		cs.Parent = card
	end)
	statCardTitle = Instance.new("TextLabel")
	statCardTitle.Name = "Title"
	statCardTitle.BackgroundTransparency = 1
	statCardTitle.Position = UDim2.new(0, 10, 0, 6)
	statCardTitle.Size = UDim2.new(1, -20, 0, 16)
	statCardTitle.Font = Enum.Font.Code
	statCardTitle.TextSize = 13
	statCardTitle.TextXAlignment = Enum.TextXAlignment.Left
	statCardTitle.TextColor3 = Color3.fromRGB(178, 255, 64)
	statCardTitle.Text = "SLIM SESSION"
	statCardTitle.Parent = card
	statCardBody = Instance.new("TextLabel")
	statCardBody.Name = "Body"
	statCardBody.BackgroundTransparency = 1
	statCardBody.Position = UDim2.new(0, 10, 0, 24)
	statCardBody.Size = UDim2.new(1, -20, 1, -30)
	statCardBody.Font = Enum.Font.Code
	statCardBody.TextSize = 12
	statCardBody.TextXAlignment = Enum.TextXAlignment.Left
	statCardBody.TextYAlignment = Enum.TextYAlignment.Top
	statCardBody.TextColor3 = Color3.fromRGB(210, 214, 224)
	statCardBody.TextWrapped = false
	statCardBody.Text = ""
	statCardBody.Parent = card
end

-- rebuild the card's lines. called from the render loop's slow section.
local function updateStatCard()
	if not statCardBody then return end
	statCardBody.Text = string.format(
		"comps %d/%d (%d%%)\npicks %d | gave %d\ntackles %d | int %d",
		stats.completions or 0, stats.shots or 0,
		stats.shots > 0 and math.floor((stats.completions or 0) / stats.shots * 100 + 0.5) or 0,
		stats.picks or 0, stats.picked or 0,
		stats.tackles or 0, stats.intercepts or 0)
	pcall(function() statCardGui.Enabled = CFG.statCard == true end)
end

--// world helpers -------------------------------------------------------------

local function myRig()
	local ch = LocalPlayer.Character
	if ch and ch:IsA("Model") and ch.PrimaryPart then return ch end
	return nil
end

local function rigs()
	local folder = Workspace:FindFirstChild("Rigs")
	if not folder then return {} end
	local out = {}
	for _, v in ipairs(folder:GetChildren()) do
		if v:IsA("Model") and v.PrimaryPart and v.Name ~= "Punter" then
			table.insert(out, v)
		end
	end
	return out
end

local function ownerId(rig)
	return tonumber((rig.Name:gsub("%D", "")) or "")
end

local function teamOf(rig)
	local id = ownerId(rig)
	if not id then return nil end
	local p = Players:GetPlayerByUserId(id)
	return p and p:GetAttribute("Team") or nil
end

local function label(rig)
	local jn = rig:GetAttribute("JerseyName")
	if jn and jn ~= "" then return tostring(jn) end
	return rig.Name
end

local function myTeam()
	return LocalPlayer:GetAttribute("Team")
end

local function ballPart()
	local b = Workspace:FindFirstChild("Rugball")
	if b and b:IsA("BasePart") then return b end
	return nil
end

local function carrier()
	local ball = ballPart()
	if not ball then return nil end
	local uid = ball:GetAttribute("CarrierUserId")
	if uid and uid ~= 0 then
		for _, rig in ipairs(rigs()) do
			if ownerId(rig) == uid then return rig end
		end
	end
	for _, rig in ipairs(rigs()) do
		local root = rig.PrimaryPart
		if root and root:GetAttribute("HasBall") == true then return rig end
	end
	return nil
end

local function hasBall()
	local rig = myRig()
	local root = rig and rig.PrimaryPart
	if not root then return false end
	if root:GetAttribute("HasBall") == true then return true end
	local ball = ballPart()
	return ball ~= nil and ball:GetAttribute("CarrierUserId") == LocalPlayer.UserId
end

local function canThrow()
	local rig = myRig()
	return rig ~= nil and rig:GetAttribute("CanThrow") == true
end

local function chestOf(rig)
	return rig.PrimaryPart.Position + Vector3.new(0, 3.4, 0)
end

local function throwOrigin()
	local ball = ballPart()
	if ball and ball:GetAttribute("CarrierUserId") == LocalPlayer.UserId then
		return ball.Position
	end
	local rig = myRig()
	if rig then
		return rig.PrimaryPart.Position + Vector3.new(0, 4.2, 0)
	end
	return nil
end

-- rigs are moved by CFrame, so velocity comes from position deltas
local function trackVelocity(rig, pos, now)
	local t = trackers[rig]
	if not t then
		trackers[rig] = { pos = pos, t = now, vel = Vector3.zero }
		return Vector3.zero
	end
	local dt = now - t.t
	if dt >= 0.016 then
		local raw = (pos - t.pos) / dt
		if raw.Magnitude > 200 then raw = Vector3.zero end
		t.vel = t.vel:Lerp(raw, 0.3)
		t.pos = pos
		t.t = now
	end
	return t.vel
end

-- bullet is flat and quick, lob hangs and lands softer; auto lobs the deep ball
local function passType(distance)
	local pick = CFG.passType
	if pick == "auto" then
		return (distance and distance > CFG.autoLobAt) and "Lob" or "Bullet"
	end
	if pick == "Lob" or pick == "Bullet" then return pick end
	return "Bullet"
end

local function flightTime(distance)
	local cfg = BallThrowConfig
	if not cfg then return 0.75 end
	local p = cfg.PassTypes[passType(distance)] or cfg.PassTypes.Lob
	return math.clamp(p.BaseFlightTime + distance * p.DistanceFlightTime, p.BaseFlightTime, cfg.MaxFlightTime)
end

-- the server holds the ball for WindupTime + ReleaseDelay after we fire, so the
-- receiver keeps running for that long before the ball even exists. without this
-- the solve leads him by flight time only and the pass lands behind a moving man.
local function launchLag()
	local cfg = BallThrowConfig
	if not cfg then return 0 end
	return (cfg.WindupTime or 0) + (cfg.ReleaseDelay or 0)
end

local function predict(origin, targetPos, vel)
	local point = targetPos
	for _ = 1, 3 do
		-- horizon (tomorrow throw): solve this far past the catch point, so the
		-- ball arrives ahead of the cut you know is coming
		local t = flightTime((point - origin).Magnitude) + launchLag() + (CFG.horizon or 0)
		point = targetPos + vel * t
	end
	return point
end

local function defenderGap(rig, pos, allRigs)
	local myT = myTeam()
	local best = math.huge
	for _, other in ipairs(allRigs) do
		if other ~= rig and other.PrimaryPart then
			local t = teamOf(other)
			if myT == nil or t == nil or t ~= myT then
				local d = (other.PrimaryPart.Position - pos).Magnitude
				if d < best then best = d end
			end
		end
	end
	return best
end

--// aim -----------------------------------------------------------------------

-- the throw solution already extrapolates the receiver by flight time; lead is
-- a manual bias on top: how many extra studs to aim past him. a runner gets it
-- along his own heading, a standing target gets it along the throw line so the
-- ball still lands beyond him.
local function applyLead(origin, pos, vel, point)
	local bias = (tonumber(CFG.lead) or 0) + (tonumber(CFG.sepAssist) or 0)
	if bias <= 0 then return point end
	local heading = Vector3.new(vel.X, 0, vel.Z)
	if heading.Magnitude < 0.6 then
		heading = Vector3.new(pos.X - origin.X, 0, pos.Z - origin.Z)
	end
	if CFG.noLook and snapSet and snapDir.Magnitude > 0.01 then
		heading = Vector3.new(snapDir.X, 0, snapDir.Z)
	end
	if heading.Magnitude < 0.001 then return point end
	return point + heading.Unit * bias
end

-- no fov / range gate: the manual picker has to reach deep men
local function entryFor(rig, origin, now, cam, allRigs)
	if not rig or not rig.PrimaryPart or not origin then return nil end
	local pos = chestOf(rig)
	local vel = trackVelocity(rig, pos, now)
	local point = applyLead(origin, pos, vel, predict(origin, pos, vel))
	local throwDir = (point - origin).Unit
	if CFG.noLook and snapSet and snapDir.Magnitude > 0.01 then
		throwDir = snapDir.Unit
	end
	local offset = throwDir * (point - origin)
	local angle = math.deg(math.acos(math.clamp(cam.CFrame.LookVector:Dot(offset.Unit), -1, 1)))
	local dist = (point - origin).Magnitude
	local gap = allRigs and defenderGap(rig, pos, allRigs) or math.huge
	-- shallow men are penalised: a 6-stud check-down is not a throw
	local shallow = math.max(0, 55 - dist)
	-- the man covering the pick: enemy nearest to the landing spot
	local cover, coverGap
	if allRigs then
		local myT = myTeam()
		local low = math.huge
		for _, other in ipairs(allRigs) do
			if other ~= rig and other.PrimaryPart then
				local t = teamOf(other)
				if myT == nil or t == nil or t ~= myT then
					local d = (other.PrimaryPart.Position - point).Magnitude
					if d < low then
						low = d
						cover = other
					end
				end
			end
		end
	end
	coverGap = low
	return {
		rig = rig,
		point = point,
		dir = throwDir,
		angle = angle,
		dist = dist,
		vel = vel,
		gap = gap,
		cover = cover,
		coverGap = low,
		score = angle * 1.15 + shallow * 0.85 + (gap < 7 and 45 or 0),
	}
end

local function candidates(now, origin, allRigs)
	local cam = Workspace.CurrentCamera
	if not cam or not origin then return {} end
	local mine = myRig()
	local myT = myTeam()
	local list = {}

	for _, rig in ipairs(allRigs) do
		if rig ~= mine then
			local okTeam = true
			if CFG.teamOnly and myT ~= nil then
				local t = teamOf(rig)
				okTeam = (t == nil) or (t == myT)
			end
			if okTeam then
				local e = entryFor(rig, origin, now, cam, allRigs)
				if e and e.angle <= CFG.fov and e.dist <= CFG.maxDist and e.dist > 6 then
					table.insert(list, e)
				end
			end
		end
	end

	table.sort(list, function(a, b) return a.score < b.score end)
	return list
end

local function rigUnderCursor(cam)
	local folder = Workspace:FindFirstChild("Rigs")
	if not folder or not cam then return nil end
	local m = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(m.X, m.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 600, params)
	if not hit then return nil end

	local node = hit.Instance
	while node and node.Parent ~= folder do
		node = node.Parent
	end
	if node and node:IsA("Model") and node ~= myRig() then
		return node
	end
	return nil
end

--// lock-on -------------------------------------------------------------------

-- everyone you could legally throw to, nearest first. the dropdown and the
-- cycle key both read this, so they always agree on the order.
local function lockable()
	local mine = myRig()
	if not (mine and mine.PrimaryPart) then return {} end
	local myT = myTeam()
	local out = {}
	for _, rig in ipairs(rigs()) do
		if rig ~= mine and rig.PrimaryPart then
			local t = teamOf(rig)
			local okTeam = true
			if CFG.teamOnly and myT ~= nil then
				okTeam = (t == nil) or (t == myT)
			end
			local root = rig.PrimaryPart
			if okTeam
				and rig:GetAttribute("Frozen") ~= true
				and root:GetAttribute("Down") ~= true then
				out[#out + 1] = rig
			end
		end
	end
	table.sort(out, function(a, b)
		return (a.PrimaryPart.Position - mine.PrimaryPart.Position).Magnitude
			< (b.PrimaryPart.Position - mine.PrimaryPart.Position).Magnitude
	end)
	return out
end

local function lockTo(rig)
	if not rig then return false end
	locked = rig
	lockManual = true
	lockPinned = true
	hoverLostAt = 0
	mode = "locked " .. label(rig)
	if lockDropdown then
		pcall(function() lockDropdown:Set(label(rig), true) end)
	end
	return true
end

local function lockClear(silent)
	locked = nil
	lockManual = false
	lockPinned = false
	hoverLostAt = 0
	if not silent then mode = "auto" end
	if lockDropdown then
		pcall(function() lockDropdown:Set("none", true) end)
	end
end

-- walk the lockable list; no lock means it starts at the nearest man
local function lockCycle(dir)
	local list = lockable()
	if #list == 0 then
		lockClear()
		return false
	end
	local idx = 0
	for i, rig in ipairs(list) do
		if rig == locked then idx = i break end
	end
	idx = idx + (dir or 1)
	if idx > #list then idx = 1 elseif idx < 1 then idx = #list end
	return lockTo(list[idx])
end

local throwing = false
local lastThrow = 0
local lastManual = 0
local myLastThrowAt = 0   -- when our own pass left, so auto guard ignores it
local shotWatch = nil     -- accuracy: our pass in the air, waiting to land
local routeApi = {}       -- hot route handlers, exposed on _G.QBAim.routes
local routeMemory = {}    -- throws per receiver: who gets auto-locked
local lastHadBall = false

local function doThrow(entry)
	if not (BallThrowConfig and RugballThrow) then return end
	local origin = throwOrigin()
	if not origin or not entry then return end
	if not canThrow() and not hasBall() then
		mode = "need the ball"
		return
	end

	local cfg = BallThrowConfig
	local pt = entry.point
	if CFG.scramble and origin then
		local dirv = (pt - origin).Unit
		local side = Vector3.new(-dirv.Z, 0, dirv.X)
		local s = (math.floor(stats.shots) % 2 == 0) and 1 or -1
		pt = pt + side * ((CFG.scrambleAmt or 6) * s)
	end
	local dist = (pt - origin).Magnitude
	local charge = math.clamp((dist - cfg.InitialChargeDistance) / cfg.ChargeDistancePerSecond, 0.04, 1.6) + CFG.chargePad
	local pass = passType(dist)

	-- the game's own BallThrowClient fires the remote the instant the button is
	-- released and lets the server run WindupTime/ReleaseDelay. waiting here
	-- stacked a second windup on top of the server's, which is the delay you felt.
	RugballThrow:FireServer(pt, charge, pass)
	myLastThrowAt = os.clock()

	stats.shots = stats.shots + 1
	stats.lastCharge = charge
	stats.distSum = (stats.distSum or 0) + dist
	stats.leadSum = (stats.leadSum or 0) + (tonumber(CFG.lead) or 0)
	shotWatch = { at = os.clock() }
	routeMemory[label(entry.rig)] = (routeMemory[label(entry.rig)] or 0) + 1
	mode = string.format("threw %.0fst c=%.2f %s", dist, charge, pass)
end

local function requestThrow()
	if throwing then return end
	-- E is a tap, so without a floor a held key would fire a remote every frame
	local now = os.clock()
	if now - lastManual < 0.3 then return false end
	if (CFG.pumpFake or CFG.fakeSpike or CFG.fakeFumble) and (hasBall() or canThrow()) then
		-- pump fake: hold the fake, then let it fly. fake spike: shorter hold,
		-- fumble bait: looks loose, fires a beat later. while the fake holds,
		-- cancel is possible (throwing flips false), which is what skips it.
		throwing = true
		lastManual = now
		local hold = CFG.pumpDelay or 0.85
		mode = "pump fake"
		if CFG.fakeSpike then hold = 0.3 mode = "fake spike" end
		if CFG.fakeFumble then hold = 0.45 mode = "fumble bait" end
		task.delay(hold, function()
			if throwing then
				throwing = false
				local e = currentEntry
				if e then
					local ok, err = pcall(doThrow, e)
					if not ok then mode = "err: " .. tostring(err):sub(1, 40) end
				end
			end
		end)
		return true
	end
	-- auto pump: the coach call matters live. pocket coverage - the defender
	-- is inside 2.5 studs - buys a beat of fake before the commit, staged
	-- through the same fake pipeline so free throws still read as fakes.
	local entry0 = currentEntry
	if CFG.autoPump and entry0 and entry0.cover
		and (entry0.coverGap or math.huge) < 2.5 and (hasBall() or canThrow()) then
		throwing = true
		lastManual = now
		mode = "auto pump (pocket)"
		task.delay(0.5, function()
			if throwing then
				throwing = false
				local e = currentEntry
				if e then
					local ok, err = pcall(doThrow, e)
					if not ok then mode = "err: " .. tostring(err):sub(1, 40) end
				end
			end
		end)
		return true
	end
	local entry = currentEntry
	if not entry then
		mode = "no target"
		return false
	end
	if not (hasBall() or canThrow()) then
		mode = "need the ball"
		return false
	end
	throwing = true
	local snapshot = { rig = entry.rig, point = entry.point, dist = entry.dist }
	local ok, err = pcall(doThrow, snapshot)
	if not ok then mode = "err: " .. tostring(err):sub(1, 40) end
	throwing = false
	lastManual = now
	return true
end

--// esp marks -----------------------------------------------------------------

local function newMark(name, color)
	local hl = Instance.new("Highlight")
	hl.Name = name .. "HL"
	hl.FillColor = color
	hl.FillTransparency = 0.78
	hl.OutlineColor = color:Lerp(Color3.new(1, 1, 1), 0.45)
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = espFolder

	local box = Instance.new("BoxHandleAdornment")
	box.Name = name .. "Box"
	box.Size = Vector3.new(4.5, 5.2, 4.5)
	box.AlwaysOnTop = true
	box.ZIndex = 5
	box.Transparency = 0.6
	box.Color3 = color
	box.Parent = espFolder

	local beam = Instance.new("Part")
	beam.Name = name .. "Beam"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = color
	beam.Transparency = 1
	beam.Size = Vector3.new(0.12, 0.12, 1)
	beam.Parent = espFolder

	local tag = Instance.new("BillboardGui")
	tag.Name = name .. "Tag"
	tag.Size = UDim2.fromOffset(210, 34)
	tag.StudsOffset = Vector3.new(0, 5.6, 0)
	tag.AlwaysOnTop = true
	tag.Enabled = false
	tag.Parent = espFolder

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextSize = 14
	text.TextColor3 = color
	text.TextStrokeTransparency = 0.4
	text.Text = ""
	text.Parent = tag

	return { hl = hl, box = box, beam = beam, tag = tag, text = text, rig = nil, lastText = 0, color = color }
end

local aimMark = newMark("Aim", COLORS.aim)
local carrierMark = newMark("Carrier", COLORS.carrier)
local threatMark = newMark("Threat", COLORS.threat)
local catchMark = newMark("Catch", Color3.fromRGB(178, 255, 64))
local magnetMark = newMark("MAGNET", Color3.fromRGB(90, 170, 255))

-- ball magnet target: a small floating neon target at the ball's landing point,
-- so you can see exactly where the magnet is pulling you.
local magnetPart = Instance.new("Part")
magnetPart.Name = "SlimMagnet"
magnetPart.Anchored = true
magnetPart.CanCollide = false
magnetPart.CanQuery = false
magnetPart.CanTouch = false
magnetPart.CastShadow = false
magnetPart.Material = Enum.Material.Neon
magnetPart.Color = Color3.fromRGB(90, 170, 255)
magnetPart.Transparency = 1
magnetPart.Size = Vector3.new(1.6, 0.1, 1.6)
magnetPart.Parent = espFolder

-- pass preview: one neon beam from the release point to the landing spot,
-- recolored by catch chance every frame
local arcPart = Instance.new("Part")
arcPart.Name = "SlimArc"
arcPart.Anchored = true
arcPart.CanCollide = false
arcPart.CanQuery = false
arcPart.CanTouch = false
arcPart.CastShadow = false
arcPart.Material = Enum.Material.Neon
arcPart.Color = Color3.fromRGB(178, 255, 64)
arcPart.Transparency = 1
arcPart.Size = Vector3.new(0.14, 0.14, 1)
arcPart.Parent = espFolder

-- ghost route: one neon line from the pick to where his run actually goes,
-- so the throw point reads as where he WILL be, not where he stands
local ghostPart = Instance.new("Part")
ghostPart.Name = "SlimGhost"
ghostPart.Anchored = true
ghostPart.CanCollide = false
ghostPart.CanQuery = false
ghostPart.CanTouch = false
ghostPart.CastShadow = false
ghostPart.Material = Enum.Material.Neon
ghostPart.Color = Color3.fromRGB(90, 170, 255)
ghostPart.Transparency = 1
ghostPart.Size = Vector3.new(0.1, 0.1, 1)
ghostPart.Parent = espFolder

-- coverage heat: a snapping 7x7 grid of tiles painted around the pick, red
-- where the defenders cluster. pure paint - the sim never reads these. the
-- throttled update rides the render frame.
local heatTiles = {}
local lastHeatAt = 0
for ti = 1, 49 do
	local tile = Instance.new("Part")
	tile.Name = "SlimHeat"
	tile.Anchored = true
	tile.CanCollide = false
	tile.CanQuery = false
	tile.CanTouch = false
	tile.CastShadow = false
	tile.Material = Enum.Material.Neon
	tile.Size = Vector3.new(5.7, 0.06, 5.7)
	tile.Transparency = 1
	tile.Parent = espFolder
	heatTiles[ti] = tile
end

-- replay trail: sample the run-back while the ball is ours, repaint it as
-- neon dots when the play ends. 7s of ghost history, then it clears itself.
local trailPts = {}
local trailLast = 0
local trailArmed = false
local function drawTrail(now)
	if #trailPts < 2 then return end
	local folder = Instance.new("Folder")
	folder.Name = "SlimTrail"
	folder.Parent = espFolder
	local step = math.max(1, math.floor(#trailPts / 40))
	for i = 1, #trailPts, step do
		local dot = Instance.new("Part")
		dot.Anchored = true
		dot.CanCollide = false
		dot.CanQuery = false
		dot.CanTouch = false
		dot.CastShadow = false
		dot.Material = Enum.Material.Neon
		dot.Size = Vector3.new(0.5, 0.5, 0.5)
		dot.Color = Color3.fromRGB(120, 255, 160)
		dot.Transparency = 0.3 + 0.45 * (i / #trailPts)
		dot.Position = trailPts[i]
		dot.Parent = folder
	end
	local endDot = Instance.new("Part")
	endDot.Anchored = true
	endDot.CanCollide = false
	endDot.CanQuery = false
	endDot.CanTouch = false
	endDot.CastShadow = false
	endDot.Material = Enum.Material.Neon
	endDot.Size = Vector3.new(1.4, 1.4, 1.4)
	endDot.Color = Color3.fromRGB(255, 90, 90)
	endDot.Transparency = 0.25
	endDot.Position = trailPts[#trailPts] + Vector3.new(0, 1.2, 0)
	endDot.Parent = folder
	task.delay(7, function()
		pcall(function() folder:Destroy() end)
	end)
	-- keep the sampled run-back visible to the debugger too
	trailPts = {}
end

local function markOff(m)
	if not m or not m.rig then return end
	m.rig = nil
	m.hl.Adornee = nil
	m.box.Adornee = nil
	m.tag.Adornee = nil
	m.tag.Enabled = false
	m.beam.Transparency = 1
end

local function markTo(m, rig, text, origin, now, color)
	if not rig or not rig.PrimaryPart then
		markOff(m)
		return
	end
	if m.rig ~= rig then
		m.rig = rig
		m.hl.Adornee = rig
		m.box.Adornee = rig.PrimaryPart
		m.tag.Adornee = rig.PrimaryPart
		m.tag.Enabled = true
	end
	if now - m.lastText > 0.1 then
		m.lastText = now
		m.text.Text = text
	end
	if color then
		m.color = color
		m.hl.FillColor = color
		m.hl.OutlineColor = color:Lerp(Color3.new(1, 1, 1), 0.45)
		m.box.Color3 = color
		m.beam.Color = color
		m.text.TextColor3 = color
	end
	if CFG.tracers and origin then
		local delta = rig.PrimaryPart.Position - origin
		if delta.Magnitude > 1.2 then
			m.beam.Size = Vector3.new(0.12, 0.12, delta.Magnitude)
			m.beam.CFrame = CFrame.lookAt(origin + delta * 0.5, rig.PrimaryPart.Position)
			m.beam.Transparency = 0.55
		else
			m.beam.Transparency = 1
		end
	else
		m.beam.Transparency = 1
	end
end

--// input helpers -------------------------------------------------------------

local function press(action, seconds)
	if pressing then return false end
	pressing = true
	pressToken = pressToken + 1
	local token = pressToken
	action:Fire(true)
	task.spawn(function()
		task.wait(seconds)
		-- a newer press takes the release slot, but its own hold must still
		-- end: our earlier design skipped this release and the held action
		-- leaked (tackle pinned in state 3 until the panel unloaded)
		pcall(function() action:Fire(false) end)
		if token == pressToken then
			pressing = false
		end
	end)
	return true
end

local function releaseAction()
	pressToken = pressToken + 1
	pressing = false
	-- release everything the panel could have held: an unload mid-press used
	-- to leak the action into the sim and freeze tackle/dive/speed channels
	for _, a in ipairs({ Tackle, Dive, Jump }) do
		if a then
			pcall(function() a:Fire(false) end)
		end
	end
end

-- watched tackle hold: same guard grammar as press(), but the hold watches
-- its own resale value. a full burn of the hold window is dead time the sim
-- sits in the tackle drive branch (which also parks the cruise speed law),
-- so the release fires the moment the result is known:
--   landed  -> the carrier lost the ball while we were wrapping up
--   whiffed -> he beat us out of reach, stop holding an empty button
--   knocked -> we went down, a held press would just leak
local function tacklePress(mine)
	if pressing then return false end
	pressing = true
	pressToken = pressToken + 1
	local token = pressToken
	Tackle:Fire(true)
	local started = os.clock()
	task.spawn(function()
		while true do
			task.wait(0.06)
			if pressToken ~= token then return end -- a newer press owns release
			local elapsed = os.clock() - started
			local c = carrier()
			local croot = c and c.PrimaryPart
			local myRoot = mine and mine.PrimaryPart
			if not myRoot or not croot or elapsed >= CFG.tackleHold then
				break
			end
			-- landed: the carry is dead while the wrap is still on
			local landed = croot:GetAttribute("HasBall") ~= true
			-- whiffed: he beat us out of reach, don't burn the rest of it
			local reach = math.max(CFG.tackleRange, CFG.diveRange or 0) + 4
			local whiffed = (croot.Position - myRoot.Position).Magnitude > reach
			-- knocked: eating a truck freezes the hold silently otherwise
			local knocked = mine:GetAttribute("Frozen") == true
				or (myRoot:GetAttribute("Down") == true)
			if landed or whiffed or knocked then
				break
			end
		end
		pcall(function() Tackle:Fire(false) end)
		if token == pressToken then
			pressing = false
		end
	end)
	return true
end

--// hit pop + anti-fall -------------------------------------------------------

-- the "hit real hard" flash when a tackle or a block lands. the knockback is
-- server side, but a flash is the client side hit pop, so we play it ourselves.
local popFx = false
local function triggerPop(strength)
	if not CFG.hitPop then return end
	if popFx then return end
	popFx = true
	local gui = Instance.new("ScreenGui")
	gui.Name = "SlimPop"
	gui.ResetOnSpawn = false
	gui.Parent = LocalPlayer:FindFirstChild("PlayerGui")
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.new(1, 0, 1, 0)
	flash.BackgroundColor3 = Color3.fromRGB(255, 235, 200)
	flash.BackgroundTransparency = 0.72 - math.min(0.85, strength or 0.85) * 0.5
	flash.ZIndex = 999999
	flash.Parent = gui
	if (strength or 0) >= 0.75 and CFG.banger then
		-- the slam: one word across the screen, pure energy, zero gameplay
		local words = { "STRAPPED", "BANGED", "HIT STICK", "WRECKED", "SMOKED" }
		local slam = Instance.new("TextLabel")
		slam.Name = "Banger"
		slam.AnchorPoint = Vector2.new(0.5, 0.5)
		slam.Position = UDim2.new(0.5, 0, 0.42, 0)
		slam.Size = UDim2.new(1, 0, 0.16, 0)
		slam.BackgroundTransparency = 1
		slam.Font = Enum.Font.GothamBlack
		slam.TextSize = 72
		slam.TextColor3 = Color3.fromRGB(255, 235, 200)
		slam.TextStrokeTransparency = 0.2
		slam.Rotation = -3
		slam.Text = words[math.random(1, #words)]
		slam.ZIndex = 999999
		slam.Parent = gui
		task.delay(0.55, function()
			pcall(function() slam:Destroy() end)
		end)
	end
	if (strength or 0) >= 0.7 then
		-- the slam: a dark dip under the pop, weight without camera shake
		local dark = Instance.new("Frame")
		dark.Name = "Hitstop"
		dark.Size = UDim2.new(1, 0, 1, 0)
		dark.BackgroundColor3 = Color3.fromRGB(6, 8, 11)
		dark.BackgroundTransparency = 0.55
		dark.ZIndex = 999998
		dark.Parent = gui
		task.delay(0.07, function()
			pcall(function() dark.BackgroundTransparency = 0.9 end)
			task.delay(0.05, function()
				pcall(function() dark:Destroy() end)
			end)
		end)
	end
	task.delay(0.18, function()
		pcall(function() flash:Destroy() end)
		pcall(function() gui:Destroy() end)
		popFx = false
	end)
end

local antiFallRig = nil    -- rig model the cache was built for
local antiFallTargets = {} -- that rig's base parts, walked once per life

-- anti fall: rigs have no humanoid, so knockback lives in attributes.
-- frozen (on the rig) locks all input, down (on the pelvis) parks you on the
-- ground, truck time spikes you into the dirt. with anti fall on we clear
-- all three every frame so nothing can pin you -- no one can move you -- and
-- if something slips through between frames we clear it the very next frame,
-- which is the auto get up. runs on both render and heartbeat so the sim
-- can't re-pin you between renders. targets are cached per rig life.
local function refreshAntiFall()
	if not CFG.antiFall then return end
	local mine = myRig()
	if not mine then return end
	if mine ~= antiFallRig then
		pcall(function()
			antiFallTargets = { mine }
			for _, p in ipairs(mine:GetDescendants()) do
				if p:IsA("BasePart") then
					antiFallTargets[#antiFallTargets + 1] = p
				end
			end
			antiFallRig = mine
		end)
	end
	for _, t in ipairs(antiFallTargets) do
		pcall(function() t:SetAttribute("Frozen", false) end)
		pcall(function() t:SetAttribute("Down", false) end)
		pcall(function() t:SetAttribute("TruckTime", 0) end)
	end
end

-- one writer for Steer, so pursuit and block drive can never fight
local function driveTo(worldDir)
	if worldDir then
		local cam = Workspace.CurrentCamera
		if cam then
			local right = cam.CFrame.RightVector
			local look = cam.CFrame.LookVector
			local vx = Vector3.new(right.X, 0, right.Z).Unit:Dot(worldDir)
			local vy = Vector3.new(look.X, 0, look.Z).Unit:Dot(worldDir)
			if math.abs(vx) < CFG.steerDead then vx = 0 end
			if math.abs(vy) < CFG.steerDead then vy = 0 end
			vx, vy = vx * CFG.steerGain, vy * CFG.steerGain
			-- a diagonal stick is 1.41 long. games that scale speed by input
			-- magnitude read that as 41% extra walking, which is exactly the
			-- kind of thing a distance audit picks out of a lobby.
			local m = math.sqrt(vx * vx + vy * vy)
			if m > 1 then
				vx, vy = vx / m, vy / m
			end
			steerTarget = Vector2.new(vx, vy)
			return
		end
	end
	steerTarget = Vector2.zero
end

-- ball magnet: when the ball is in the air and uncarried, steer straight at
-- its landing point so you're under it when it comes down. reads LandingPoint
-- from the sim's own ball attributes. returns a world-space direction, or nil.
local function magnetSteer(now, ball, myRoot)
	if not CFG.catchMagnet then return nil end
	if not ball or not myRoot then return nil end
	if ball:GetAttribute("InFlight") ~= true then return nil end
	if (ball:GetAttribute("CarrierUserId") or 0) ~= 0 then return nil end
	local lp = ball:GetAttribute("LandingPoint")
	if typeof(lp) ~= "Vector3" then return nil end
	local dist = (lp - myRoot.Position).Magnitude
	if dist > CFG.magnetRadius then return nil end
	-- lead: arrive a beat before the ball lands, not exactly as it touches
	local target = lp
	if CFG.magnetLead then
		local nowTs = workspace:GetServerTimeNow()
		local lat = ball:GetAttribute("LandingAt") or 0
		local remaining = math.max(lat - nowTs, 0)
		if remaining > 0.15 then
			local bv = ball.AssemblyLinearVelocity
			local bFlat = Vector3.new(bv.X, 0, bv.Z)
			if bFlat.Magnitude > 1 then
				local leadAmt = bFlat.Magnitude * math.min(remaining * 0.5, 0.35)
				target = lp + bFlat.Unit * leadAmt
			end
		end
	end
	local dir = (target - myRoot.Position).Unit
	return dir
end

local function pumpSteer(now)
	if now - lastSteer < 1 / CFG.steerHz then return end
	lastSteer = now
	if (steerTarget - steerVec).Magnitude > 0.05 then
		steerVec = steerTarget
		Steer:Fire(steerVec)
	end
end

-- speed: ReplicatedFirst.RigSim reads Types.speedPenalty(rig) at every drive
-- tick and subtracts it from a flat 24-25 st/s cruise. that function is the one
-- honest channel -- writing DriveForce, WalkSpeed or a raw velocity gets
-- stomped on the very next sim tick, which is the "it resets itself" you get
-- with every other speed script on this game. one patched penalty = no force
-- fights, no balance loss, and the slider moves the cruise in real time.
--
-- two guards on top of the old version:
--   * the module table outlives a panel reload, so the pristine function is
--     parked on _G. a second load wraps the real original instead of stacking
--     a wrapper around our own wrapper (+25 then +25 then ...).
--   * a one-second watchdog re-installs ours if anything else overwrites it,
--     and retries the install if RigSim showed up late.
local SPEED_ORIG_KEY = "__SlimSpeedPenaltyOrig"

local speedTypes
local speedPenaltyFn
local speedPatched = false
local speedWatch = true

local function speedBias()
	-- mult 1.0 -> 0, 1.5 -> +12.5 st/s, 2.0 -> +25 st/s on the cruise.
	-- rush adds its own +5 even with speed off: pursuit gets real pace.
	local bias = 0
	if CFG.speed then
		bias = math.max(0, (tonumber(CFG.speedMult) or 1) - 1) * 25
	end
	if rushOn and CFG.rushSurge then
		bias = bias + 5
	end
	return bias
end

local function installSpeedPatch()
	if speedPatched then return true end
	local sim = ReplicatedFirst:FindFirstChild("RigSim")
	if not sim then return false end
	local ok, mod = pcall(require, sim)
	if not ok or type(mod) ~= "table" or type(mod.Types) ~= "table" then
		return false
	end
	local types = mod.Types
	local current = types.speedPenalty
	if type(current) ~= "function" then return false end

	local orig = rawget(_G, SPEED_ORIG_KEY)
	if type(orig) ~= "function" then
		orig = current
		rawset(_G, SPEED_ORIG_KEY, orig)
	end

	speedTypes = types
	speedPenaltyFn = function(rig)
		local bias = speedBias()
		if bias <= 0.001 then
			return orig(rig)
		end
		return orig(rig) - bias
	end
	types.speedPenalty = speedPenaltyFn
	speedPatched = true
	return true
end

local function unpatchSpeed()
	speedWatch = false
	if speedTypes and speedTypes.speedPenalty == speedPenaltyFn then
		local orig = rawget(_G, SPEED_ORIG_KEY)
		if type(orig) == "function" then
			pcall(function() speedTypes.speedPenalty = orig end)
		end
	end
	speedPatched = false
	speedPenaltyFn = nil
	speedTypes = nil
end

task.spawn(function()
	while speedWatch do
		if not speedPatched then
			pcall(installSpeedPatch)
		elseif speedTypes and speedTypes.speedPenalty ~= speedPenaltyFn then
			pcall(function() speedTypes.speedPenalty = speedPenaltyFn end)
		end
		task.wait(1)
	end
end)

pcall(installSpeedPatch)

--// physique ------------------------------------------------------------------
-- the card in the settings panel is the game's own. weight and height are
-- server presets on LocalPlayer.Physique (Skinny/Average/Heavy + Short/Average/
-- Tall) and CONFIRM goes through a quarter-locked RemoteFunction, so the stored
-- build is not writable from here. what IS writable is what the sim reads on
-- every tick:
--     Types.of(rig).Strength        -> TackleState shove math
--     Types.heightOf(rig).SpeedPenalty -> part of the cruise law
-- both resolve on the client. we point OUR rig at a max entry, leave every
-- other rig on the real table, and repaint the card so the numbers match.
local PHYS_STRENGTH = 999
local PHYS_ORIG_OF = "__SlimPhysOrigOf"
local PHYS_ORIG_HEIGHT = "__SlimPhysOrigHeightOf"

local physTypes
local physPatched = false
local physOn = true
local physMaxOf = { Label = "MAX", Width = 1, SpeedPenalty = 0, Strength = PHYS_STRENGTH }
local physMaxHeight = { Label = "Short", Extra = 0, SpeedPenalty = 0 }

local function physIsMine(rig)
	local ch = LocalPlayer.Character
	if not ch or not rig then return false end
	return rig == ch or rig.Parent == ch
end

local function installPhysiquePatch()
	if physPatched then return true end
	local rt = ReplicatedFirst:FindFirstChild("RigTypes")
	if not rt then return false end
	local ok, types = pcall(require, rt)
	if not ok or type(types) ~= "table" then return false end
	if type(types.of) ~= "function" or type(types.heightOf) ~= "function" then
		return false
	end
	local origOf = rawget(_G, PHYS_ORIG_OF)
	if type(origOf) ~= "function" then
		origOf = types.of
		rawset(_G, PHYS_ORIG_OF, origOf)
	end
	local origHeightOf = rawget(_G, PHYS_ORIG_HEIGHT)
	if type(origHeightOf) ~= "function" then
		origHeightOf = types.heightOf
		rawset(_G, PHYS_ORIG_HEIGHT, origHeightOf)
	end
	physTypes = types
	types.of = function(rig)
		if CFG.maxPhysique and physIsMine(rig) then return physMaxOf end
		return origOf(rig)
	end
	types.heightOf = function(rig)
		if CFG.maxPhysique and physIsMine(rig) then return physMaxHeight end
		return origHeightOf(rig)
	end
	physPatched = true
	return true
end

local function unpatchPhysique()
	physOn = false
	if physTypes then
		local origOf = rawget(_G, PHYS_ORIG_OF)
		local origHeightOf = rawget(_G, PHYS_ORIG_HEIGHT)
		if type(origOf) == "function" then
			pcall(function() physTypes.of = origOf end)
		end
		if type(origHeightOf) == "function" then
			pcall(function() physTypes.heightOf = origHeightOf end)
		end
	end
	physPatched = false
	physTypes = nil
end

-- the card repaints itself on every Physique attribute change; park our text on
-- top of it at a low rate instead of fighting the paint calls.
local function paintPhysiqueCard()
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	local rv = pg and pg:FindFirstChild("RoleVote")
	if not rv then return end
	local effect
	for _, d in ipairs(rv:GetDescendants()) do
		if d:IsA("TextLabel") and d.Name == "Effect" and type(d.Text) == "string"
			and d.Text:sub(1, 6) == "SPEED:" then
			effect = d
			break
		end
	end
	if not effect then return end
	local want = string.format(
		"SPEED: fastest   \194\183   STRENGTH: %s",
		PHYS_STRENGTH >= 100 and string.format("%.0fx", PHYS_STRENGTH)
			or string.format("%.2fx", PHYS_STRENGTH)
	)
	if effect.Text ~= want then
		effect.Text = want
	end
end

task.spawn(function()
	while physOn do
		if not physPatched then
			pcall(installPhysiquePatch)
		end
		if CFG.maxPhysique then
			pcall(paintPhysiqueCard)
		end
		task.wait(0.4)
	end
end)

pcall(installPhysiquePatch)

--// ui ------------------------------------------------------------------------

local Rayfield
local window
-- widget handles ride on one table. the whole file is a single chunk, and luau
-- caps a function at 200 locals: thirty-odd loose handles pushed the main chunk
-- over and the executor refused to compile it at all.
local WIDGET = {
	radarDots = {},
	radarRings = {},
	lastRadar = 0,
	lastPickAt = 0,
}
local throwKey

local shutOnce = false
local shutdown
shutdown = function()
	if shutOnce then return end
	shutOnce = true
	pcall(saveCfg)
	unpatchSpeed()
	unpatchPhysique()
	pcall(function() RunService:UnbindFromRenderStep("SlimPanel") end)
	if WIDGET.leadConn then pcall(function() WIDGET.leadConn:Disconnect() end) end
	if WIDGET.antiFallConn then pcall(function() WIDGET.antiFallConn:Disconnect() end) end
	releaseAction()
	pcall(function() Steer:Fire(Vector2.zero) end)
	unbindChatSync()
	_G.QBAim = nil
	_G.Slim = nil
	markOff(aimMark)
	markOff(carrierMark)
	markOff(threatMark)
	for _, v in ipairs(espFolder:GetChildren()) do
		pcall(function() v:Destroy() end)
	end
	pcall(function() espFolder:Destroy() end)
	if statCardGui then
		pcall(function() statCardGui:Destroy() end)
	end
	panicRestore() -- an unload is not a panic: bring everything back anyway
	if window then
		pcall(function() window:Unload() end)
		pcall(function()
			if window.screenGui then window.screenGui:Destroy() end
		end)
	end
	print("[Slim] panel unloaded")
end

-- the window is optional: if the library will not load, the three modules keep
-- running headless and the globals in _G still drive them

-- volt theme: near-black blue glass, lime accent, drifting window gradient
local function slimTheme()
	local t = {
		WindowColor = ColorSequence.new(Color3.fromRGB(10, 12, 17), Color3.fromRGB(19, 23, 31)),
		ShadowColor = Color3.fromRGB(0, 0, 0),
		SurfaceStroke = Color3.fromRGB(52, 60, 76),
		LiveAnimation = true,

		CornerRoundness = UDim.new(0, 16),
		PillCornerRadius = UDim.new(1, 0),
		ElementCornerRadius = UDim.new(0, 10),

		TitlingColor = Color3.fromRGB(244, 247, 252),
		ContentColor = Color3.fromRGB(203, 210, 224),
		ElementTextHoverColor = Color3.fromRGB(255, 255, 255),
		ActionColor = Color3.fromRGB(140, 150, 168),
		PlaceholderColor = Color3.fromRGB(108, 118, 136),

		TabColor = Color3.fromRGB(158, 168, 186),
		TabBackground = ColorSequence.new(Color3.fromRGB(30, 36, 47), Color3.fromRGB(21, 25, 34)),
		TabStroke = ColorSequence.new(Color3.fromRGB(64, 74, 92), Color3.fromRGB(44, 52, 66)),

		ElementGradient = ColorSequence.new(Color3.fromRGB(27, 32, 42), Color3.fromRGB(20, 24, 32)),
		ElementStroke = Color3.fromRGB(50, 58, 72),
		ElementStrokeHover = Color3.fromRGB(150, 210, 110),
		ElementTransparency = 0,
		ElementStrokeTransparency = 0,
		ElementStrokeHoverTransparency = 0.2,

		AccentColor = Color3.fromRGB(178, 255, 64),
		AccentStroke = Color3.fromRGB(214, 255, 150),
		AccentGlow = 0.35,
		SliderBackground = Color3.fromRGB(32, 38, 48),
		SliderBackgroundHover = Color3.fromRGB(42, 50, 62),
		SliderProgress = ColorSequence.new(Color3.fromRGB(150, 240, 60), Color3.fromRGB(96, 214, 96)),
		SliderStroke = Color3.fromRGB(60, 70, 86),
		SliderHandle = Color3.fromRGB(240, 248, 232),
		ToggleTrack = Color3.fromRGB(36, 42, 53),
		ToggleKnobOff = Color3.fromRGB(126, 136, 154),
		ToggleKnobOffTransparency = 0,

		FieldBackground = Color3.fromRGB(17, 21, 27),
		FieldGlow = Color3.fromRGB(150, 220, 90),
		StatBackground = Color3.fromRGB(23, 28, 37),
		BoxStroke = Color3.fromRGB(58, 68, 86),
		DropdownHighlight = Color3.fromRGB(46, 64, 44),
		ErrorColor = Color3.fromRGB(255, 96, 104),
		ErrorStrokeColor = Color3.fromRGB(255, 150, 156),

		-- edges: a faint top-lit bevel rather than a flat line
		ElementStrokeGradient = ColorSequence.new(Color3.fromRGB(76, 88, 110), Color3.fromRGB(28, 34, 44)),
		ToggleTrackTransparency = 0,
		ToggleKnobOn = Color3.fromRGB(20, 26, 18),
		ScrollBarImageTransparency = 0.35,
		NeutralButtonStroke = Color3.fromRGB(64, 74, 92),
	}

	-- montserrat if this client has it, otherwise the theme's own font
	pcall(function()
		t.TitleFont = Font.fromEnum(Enum.Font.MontserratBold)
		t.Font = Font.fromEnum(Enum.Font.MontserratMedium)
	end)

	return t
end

local function buildUI()
	local ok, res = pcall(function()
		return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
	end)
	if not ok or type(res) ~= "table" then
		warn("[Slim] Rayfield failed to load: " .. tostring(res))
		return false
	end
	Rayfield = res

	local props = {
		name = "RUGBALL",
		subtitle = "slim suite  |  v2  |  client side",
		sidebarLayout = true,
		showName = "RUGBALL",
		configuration = {
			autoSave = true,
			autoLoad = true,
			fileName = "RugballSlim",
		},
	}

	-- a theme the build does not understand must not cost us the window
	local themed, win = pcall(function()
		local withTheme = table.clone(props)
		withTheme.theme = slimTheme()
		return Rayfield:CreateWindow(withTheme)
	end)
	if themed and win then
		window = win
	else
		warn("[Slim] theme rejected, falling back to default: " .. tostring(win))
		window = Rayfield:CreateWindow(props)
	end

	-- cosmetic calls are optional. if the build under us lacks a helper, the
	-- panel still draws, it just draws plainer.
	local function section(owner, name)
		if not owner or not owner.CreateSection then return end
		pcall(function() owner:CreateSection({ name = name }) end)
	end

	local function groupOf(owner)
		if owner and owner.CreateGroup then
			local made, row = pcall(function() return owner:CreateGroup() end)
			if made and row then return row end
		end
		return owner
	end

	pcall(function()
		window:CreateTag({ text = "SLIM", color = Color3.fromRGB(178, 255, 64), order = 0 })
		WIDGET.tagTarget = window:CreateTag({ text = "NO TGT", color = Color3.fromRGB(70, 76, 90), order = 1 })
		WIDGET.modeTag = window:CreateTag({ text = "IDLE", color = Color3.fromRGB(44, 50, 62), order = 2 })
	end)

	section(window, "PLAY")
	local aimTab = window:CreateTab({ name = "AIM" })
	local tackleTab = window:CreateTab({ name = "TACKLE" })
	local blockTab = window:CreateTab({ name = "BLOCK" })

	section(window, "VIEW")
	local lookTab = window:CreateTab({ name = "LOOK" })

	section(window, "SYS")
	local liveTab = window:CreateTab({ name = "LIVE" })
	local catchTab = window:CreateTab({ name = "CATCH" })

	-- aim ---------------------------------------------------------------------

	-- a running readout of the pick, so the tab itself tells you who is held
	pcall(function()
		WIDGET.aimCard = aimTab:CreateText({
			name = "picked man  |  nobody",
			text = "auto scanning",
			icon = 91452555903853,
		})
	end)

	section(aimTab, "AUTOPILOT")

	-- one switch plays the whole game: the qb auto-throws to the deepest open
	-- man, the defense tackles, blocks, guards and intercepts by itself
	local function setAutopilot(v)
		CFG.autopilot = v
		if v then
			CFG.aim = true
			CFG.autoThrow = true
			CFG.tackle = true
			CFG.pursue = true
			CFG.block = true
			CFG.intercept = true
			CFG.antiFall = true
			CFG.guard = true
			pcall(function() WIDGET.aimToggle:Set(true, true) end)
			pcall(function() WIDGET.autoThrowToggle:Set(true, true) end)
			pcall(function() WIDGET.tackleToggle:Set(true, true) end)
			pcall(function() WIDGET.blockToggle:Set(true, true) end)
			pcall(function() WIDGET.interceptToggle:Set(true, true) end)
			pcall(function() WIDGET.pathToggle:Set(true, true) end)
			pcall(function() WIDGET.guardToggle:Set(true, true) end)
			pcall(function() WIDGET.antiFallToggle:Set(true, true) end)
		end
		mode = v and "autopilot" or mode
	end

	pcall(function()
		WIDGET.autopilotToggle = aimTab:CreateToggle({
			name = "autopilot",
			description = "one switch: qb throws + defense runs itself",
			flag = "autopilot",
			value = CFG.autopilot,
			callback = function(v) setAutopilot(v) end,
		})
	end)

	aimTab:CreateKeybind({
		name = "autopilot key",
		description = "flip autopilot without opening the panel",
		value = Enum.KeyCode.G,
		flag = "autopilotKey",
		callback = function()
			setAutopilot(not CFG.autopilot)
			if WIDGET.autopilotToggle then
				pcall(function() WIDGET.autopilotToggle:Set(CFG.autopilot, true) end)
			end
		end,
	})

	section(aimTab, "LOCK ON")

	pcall(function()
		lockDropdown = aimTab:CreateDropdown({
			name = "pass to",
			description = "sticks the pick on one man until you change it",
			options = { "none" },
			value = "none",
			flag = "lockTarget",
			callback = function(pick)
				local chosen = type(pick) == "table" and pick[1] or pick
				if not chosen or chosen == "none" then
					lockClear()
					return
				end
				for _, rig in ipairs(lockable()) do
					if label(rig) == chosen then
						lockTo(rig)
						return
					end
				end
			end,
		})
	end)

	aimTab:CreateKeybind({
		name = "lock under crosshair",
		description = "Q  |  press again on the same man to unlock",
		value = Enum.KeyCode.Q,
		flag = "lockKey",
		callback = function()
			if lockPinned then
				lockClear()
			else
				local rig = rigUnderCursor(Workspace.CurrentCamera)
				if rig then
					lockTo(rig)
				else
					mode = "nothing under the crosshair"
				end
			end
		end,
	})

	aimTab:CreateKeybind({
		name = "cycle lock",
		description = "C  |  nearest first",
		value = Enum.KeyCode.C,
		flag = "cycleKey",
		callback = function()
			lockCycle(1)
		end,
	})

	aimTab:CreateToggle({
		name = "route memory",
		description = "auto-lock your most-thrown man when the ball hits your hand",
		flag = "routeLock",
		value = CFG.routeLock,
		callback = function(v) CFG.routeLock = v end,
	})

	section(aimTab, "TARGETING")

	local aimRow = groupOf(aimTab)
	WIDGET.aimToggle = aimRow:CreateToggle({
		name = "aimbot",
		flag = "aim",
		value = CFG.aim,
		callback = function(v) CFG.aim = v end,
	})
	aimRow:CreateToggle({
		name = "team only",
		flag = "teamOnly",
		value = CFG.teamOnly,
		callback = function(v) CFG.teamOnly = v end,
	})
	WIDGET.autoThrowToggle = aimRow:CreateToggle({
		name = "auto throw",
		flag = "autoThrow",
		value = CFG.autoThrow,
		callback = function(v) CFG.autoThrow = v end,
	})
	aimRow:CreateToggle({
		name = "coach",
		description = "reads the coverage and calls the throw",
		flag = "coach",
		value = CFG.coach,
		callback = function(v) CFG.coach = v end,
	})

	aimTab:CreateSlider({
		name = "max distance",
		range = { 30, 226 },
		increment = 1,
		value = CFG.maxDist,
		suffix = " st",
		flag = "maxDist",
		callback = function(v) CFG.maxDist = v end,
	})

	aimTab:CreateSlider({
		name = "field of view",
		range = { 8, 90 },
		increment = 1,
		value = CFG.fov,
		suffix = " deg",
		flag = "fov",
		callback = function(v) CFG.fov = v end,
	})

	WIDGET.leadSlider = aimTab:CreateSlider({
		name = "lead",
		description = "extra studs thrown ahead of the receiver",
		range = { 0, 100 },
		increment = 1,
		value = CFG.lead,
		suffix = " st",
		flag = "lead",
		callback = function(v) CFG.lead = v end,
	})

	aimTab:CreateSlider({
		name = "horizon",
		description = "tomorrow throw: solve this far past the catch point",
		range = { 0, 2.5 },
		increment = 0.05,
		value = CFG.horizon,
		suffix = " s",
		flag = "horizon",
		callback = function(v) CFG.horizon = v end,
	})

	pcall(function()
		WIDGET.passDropdown = aimTab:CreateDropdown({
			name = "pass",
			description = "auto lobs anything past the cut-off",
			options = { "Bullet", "Lob", "auto" },
			value = CFG.passType,
			flag = "passType",
			callback = function(pick)
				local chosen = type(pick) == "table" and pick[1] or pick
				if chosen then CFG.passType = chosen end
			end,
		})
	end)

	aimTab:CreateSlider({
		name = "auto lob past",
		description = "distance where auto stops throwing bullets",
		range = { 25, 140 },
		increment = 5,
		value = CFG.autoLobAt,
		suffix = " st",
		flag = "autoLobAt",
		callback = function(v) CFG.autoLobAt = v end,
	})

	aimTab:CreateSlider({
		name = "open gate",
		description = "refuse auto throws into coverage, 0 = off",
		range = { 0, 20 },
		increment = 0.5,
		value = CFG.openGate,
		suffix = " st",
		flag = "openGate",
		callback = function(v) CFG.openGate = v end,
	})

	aimTab:CreateToggle({
		name = "hit pop",
		description = "flash on every tackle or block impact",
		flag = "hitPop",
		value = CFG.hitPop,
		callback = function(v) CFG.hitPop = v end,
	})

	aimTab:CreateToggle({
		name = "banger text",
		description = "one-word slam across the screen on a big hit",
		flag = "banger",
		value = CFG.banger,
		callback = function(v) CFG.banger = v end,
	})

	aimTab:CreateToggle({
		name = "pump fake",
		description = "E holds a fake then throws it",
		flag = "pumpFake",
		value = CFG.pumpFake,
		callback = function(v) CFG.pumpFake = v end,
	})

	aimTab:CreateToggle({
		name = "auto pump",
		description = "pocket coverage under 2.5 st buys a free fake first",
		flag = "autoPump",
		value = CFG.autoPump,
		callback = function(v) CFG.autoPump = v end,
	})

	aimTab:CreateToggle({
		name = "fake spike",
		description = "spike it, then throw the fake",
		flag = "fakeSpike",
		value = CFG.fakeSpike,
		callback = function(v) CFG.fakeSpike = v end,
	})

	aimTab:CreateToggle({
		name = "fake fumble",
		description = "strip bait: looks loose, fires a beat later",
		flag = "fakeFumble",
		value = CFG.fakeFumble,
		callback = function(v) CFG.fakeFumble = v end,
	})

	aimTab:CreateToggle({
		name = "no look",
		description = "throw off the snap dir, not the crosshair",
		flag = "noLook",
		value = CFG.noLook,
		callback = function(v) CFG.noLook = v end,
	})

	aimTab:CreateToggle({
		name = "scramble",
		description = "break the throw side to the hash",
		flag = "scramble",
		value = CFG.scramble,
		callback = function(v) CFG.scramble = v end,
	})

	aimTab:CreateSlider({
		name = "scramble amt",
		range = { 2, 20 },
		increment = 1,
		value = CFG.scrambleAmt,
		suffix = " st",
		flag = "scrambleAmt",
		callback = function(v) CFG.scrambleAmt = v end,
	})

	aimTab:CreateToggle({
		name = "sep assist",
		description = "extra push on the deep receiver",
		flag = "sepAssist",
		value = CFG.sepAssist,
		callback = function(v) CFG.sepAssist = v end,
	})

	section(aimTab, "THROW")

	aimTab:CreateButton({
		name = "throw to picked man",
		description = "or press E",
		callback = function()
			if not requestThrow() then
				window:Notify({ title = "RUGBALL", content = mode })
			end
		end,
	})

	aimTab:CreateButton({
		name = "drop the pick",
		description = "back to auto scanning (F)",
		callback = function()
			locked = nil
			lockManual = false
			hoverLostAt = 0
			mode = "auto"
		end,
	})

	throwKey = aimTab:CreateKeybind({
		name = "throw key",
		value = Enum.KeyCode.E,
		flag = "throwKey",
		callback = function()
			requestThrow()
		end,
	})

	aimTab:CreateKeybind({
		name = "clear pick",
		value = Enum.KeyCode.F,
		flag = "clearKey",
		callback = function()
			locked = nil
			lockManual = false
			hoverLostAt = 0
			mode = "auto"
		end,
	})

	-- hot routes: save the man you are locked on + your lead + pass type.
	-- keys 1/2/3 lock him, drop your ball on that spot, throw.
	local function saveRoute(i)
		local name = locked and label(locked) or (currentEntry and label(currentEntry.rig))
		if not name then
			mode = "no man to save"
			return
		end
		hotRoutes[i] = { name = name, lead = CFG.lead, ptype = CFG.passType }
		mode = string.format("route %d saved: %s", i, name)
	end

	local function fireRoute(i)
		local r = hotRoutes[i]
		if not r then
			mode = string.format("route %d empty", i)
			return
		end
		local target
		for _, rig in ipairs(rigs()) do
			if label(rig) == r.name then target = rig break end
		end
		if not target then
			mode = string.format("route %d man gone", i)
			return
		end
		lockTo(target)
		CFG.lead = r.lead or CFG.lead
		CFG.passType = r.ptype or CFG.passType
		if WIDGET.leadSlider then pcall(function() WIDGET.leadSlider:Set(CFG.lead, true) end) end
		if WIDGET.passDropdown then pcall(function() WIDGET.passDropdown:Set(CFG.passType, true) end) end
		lastManual = 0
		requestThrow()
	end
	routeApi.save = saveRoute
	routeApi.fire = fireRoute

	section(aimTab, "HOT ROUTES")

	local routeRow1 = groupOf(aimTab)
	routeRow1:CreateButton({
		name = "save r1",
		description = "snapshots the current pick + lead + pass",
		callback = function() saveRoute(1) end,
	})
	routeRow1:CreateButton({
		name = "fire r1",
		description = "lock him, load the ball, throw",
		callback = function() fireRoute(1) end,
	})

	local routeRow2 = groupOf(aimTab)
	routeRow2:CreateButton({ name = "save r2", callback = function() saveRoute(2) end })
	routeRow2:CreateButton({ name = "fire r2", callback = function() fireRoute(2) end })

	local routeRow3 = groupOf(aimTab)
	routeRow3:CreateButton({ name = "save r3", callback = function() saveRoute(3) end })
	routeRow3:CreateButton({ name = "fire r3", callback = function() fireRoute(3) end })

	aimTab:CreateKeybind({
		name = "fire route 1",
		value = Enum.KeyCode.One,
		flag = "route1Key",
		callback = function() fireRoute(1) end,
	})
	aimTab:CreateKeybind({
		name = "fire route 2",
		value = Enum.KeyCode.Two,
		flag = "route2Key",
		callback = function() fireRoute(2) end,
	})
	aimTab:CreateKeybind({
		name = "fire route 3",
		value = Enum.KeyCode.Three,
		flag = "route3Key",
		callback = function() fireRoute(3) end,
	})

	-- tackle ------------------------------------------------------------------

	section(tackleTab, "TACKLE")

	local tackleRow = groupOf(tackleTab)
	WIDGET.tackleToggle = tackleRow:CreateToggle({
		name = "auto tackle",
		flag = "tackle",
		value = CFG.tackle,
		callback = function(v) CFG.tackle = v end,
	})
	tackleRow:CreateToggle({
		name = "pursue",
		flag = "pursue",
		value = CFG.pursue,
		callback = function(v) CFG.pursue = v end,
	})
	tackleRow:CreateToggle({
		name = "tackle lead",
		description = "chase the intercept point instead of the body",
		flag = "tackleLead",
		value = CFG.tackleLead,
		callback = function(v) CFG.tackleLead = v end,
	})
	tackleRow:CreateToggle({
		name = "dodge truck",
		description = "sidestep the truck spike instead of eating it",
		flag = "dodgeTruck",
		value = CFG.dodgeTruck,
		callback = function(v) CFG.dodgeTruck = v end,
	})
	tackleRow:CreateToggle({
		name = "swarm",
		description = "gang tackle: take the escape lane when a mate has him",
		flag = "swarm",
		value = CFG.swarm,
		callback = function(v) CFG.swarm = v end,
	})
	tackleRow:CreateButton({
		name = "teleport → tackle",
		description = "snap right on top of the enemy carrier",
		callback = function()
			local c = carrier()
			local r = myRig()
			if not c or not c.PrimaryPart or not r or not r.PrimaryPart then return end
			if teamOf(c) == myTeam() then return end -- only enemy carriers
			local off = Vector3.new(0, CFG.tackleTeleY or 2, 0)
			pcall(function() r.PrimaryPart.CFrame = CFrame.new(c.PrimaryPart.Position + off) end)
			mode = "teleported to tackle"
		end,
	})
	tackleRow:CreateSlider({
		name = "tackle tele height",
		description = "studs above the carrier when you land",
		range = { 1, 8 },
		increment = 0.5,
		value = CFG.tackleTeleY,
		suffix = " st",
		flag = "tackleTeleY",
		callback = function(v) CFG.tackleTeleY = v end,
	})
	tackleRow:CreateToggle({
		name = "auto dive",
		description = "lunge at the carrier from the band between the ranges",
		flag = "dive",
		value = CFG.dive,
		callback = function(v) CFG.dive = v end,
	})
	tackleRow:CreateToggle({
		name = "dive lead",
		description = "spend a beat steering at where the carrier will be first",
		flag = "diveLead",
		value = CFG.diveLead,
		callback = function(v) CFG.diveLead = v end,
	})

	WIDGET.antiFallToggle = tackleRow:CreateToggle({
		name = "anti fall",
		description = "clear frozen/down/truck every frame: no one can move you, auto get up if they do",
		flag = "antiFall",
		value = CFG.antiFall,
		callback = function(v) CFG.antiFall = v end,
	})

	tackleRow:CreateToggle({
		name = "escape juke",
		description = "sidestep the hit instead of eating it while holding",
		flag = "escapeJuke",
		value = CFG.escapeJuke,
		callback = function(v) CFG.escapeJuke = v end,
	})
	tackleRow:CreateToggle({
		name = "juke bait",
		description = "one hard burst sidestep timed to the tackle closing",
		flag = "jukeBait",
		value = CFG.jukeBait,
		callback = function(v) CFG.jukeBait = v end,
	})

	section(tackleTab, "MOVEMENT")

	local moveRow = groupOf(tackleTab)
	moveRow:CreateToggle({
		name = "speed",
		description = "raises the cruise the sim drives toward (patched inside the sim, nothing to reset)",
		flag = "speed",
		value = CFG.speed,
		callback = function(v) CFG.speed = v end,
	})
	moveRow:CreateSlider({
		name = "speed mult",
		description = "1.0 = stock | 1.5 = +12 st/s | 2.0 = +25 st/s",
		range = { 1, 2 },
		increment = 0.05,
		value = CFG.speedMult,
		suffix = "x",
		flag = "speedMult",
		callback = function(v) CFG.speedMult = v end,
	})
	moveRow:CreateToggle({
		name = "rush surge",
		description = "tackle/block drive adds +5 st/s, even with speed off",
		flag = "rushSurge",
		value = CFG.rushSurge,
		callback = function(v) CFG.rushSurge = v end,
	})
	moveRow:CreateToggle({
		name = "max physique",
		description = "strength 999 + zero physique penalty on your rig (card shows 999; server keeps your real build)",
		flag = "maxPhysique",
		value = CFG.maxPhysique,
		callback = function(v) CFG.maxPhysique = v end,
	})

	section(tackleTab, "DEFENSE ASSIST")

	local assistRow = groupOf(tackleTab)
	pcall(function()
		WIDGET.interceptToggle = assistRow:CreateToggle({
			name = "ball intercept",
			flag = "intercept",
			value = CFG.intercept,
			callback = function(v) CFG.intercept = v end,
		})
	end)
	pcall(function()
		WIDGET.pathToggle = assistRow:CreateToggle({
			name = "pursuit pathing",
			flag = "pathing",
			value = CFG.pathing,
			callback = function(v) CFG.pathing = v end,
		})
	end)
	pcall(function()
		WIDGET.guardToggle = assistRow:CreateToggle({
			name = "auto guard",
			description = "sit the man the enemy throw is for, contest the catch",
			flag = "guard",
			value = CFG.guard,
			callback = function(v) CFG.guard = v end,
		})
	end)
	pcall(function()
		assistRow:CreateToggle({
			name = "deep half",
			description = "pre-throw: park over the top of the deepest receiver",
			flag = "deepHalf",
			value = CFG.deepHalf,
			callback = function(v) CFG.deepHalf = v end,
		})
	end)

	tackleTab:CreateSlider({
		name = "intercept range",
		range = { 10, 90 },
		increment = 5,
		value = CFG.interceptRange,
		suffix = " st",
		flag = "interceptRange",
		callback = function(v) CFG.interceptRange = v end,
	})

	tackleTab:CreateSlider({
		name = "tackle reach",
		range = { 4, 14 },
		increment = 0.5,
		value = CFG.tackleRange,
		suffix = " st",
		flag = "tackleRange",
		callback = function(v) CFG.tackleRange = v end,
	})

	tackleTab:CreateSlider({
		name = "dive range",
		description = "won't shrink below the tackle reach",
		range = { 6, 20 },
		increment = 0.5,
		value = CFG.diveRange,
		suffix = " st",
		flag = "diveRange",
		callback = function(v) CFG.diveRange = v end,
	})

	tackleTab:CreateSlider({
		name = "hold",
		range = { 0.2, 1.2 },
		increment = 0.05,
		value = CFG.tackleHold,
		suffix = " s",
		flag = "tackleHold",
		callback = function(v) CFG.tackleHold = v end,
	})

	tackleTab:CreateSlider({
		name = "cooldown",
		range = { 0.5, 2.5 },
		increment = 0.05,
		value = CFG.tackleCd,
		suffix = " s",
		flag = "tackleCd",
		callback = function(v) CFG.tackleCd = v end,
	})

	tackleTab:CreateKeybind({
		name = "toggle tackle",
		value = Enum.KeyCode.T,
		flag = "tackleKey",
		callback = function()
			CFG.tackle = not CFG.tackle
			WIDGET.tackleToggle:Set(CFG.tackle, true)
		end,
	})

	-- block -------------------------------------------------------------------

	section(blockTab, "BLOCK")

	local blockRow = groupOf(blockTab)
	WIDGET.blockToggle = blockRow:CreateToggle({
		name = "auto block",
		flag = "block",
		value = CFG.block,
		callback = function(v) CFG.block = v end,
	})
	blockRow:CreateToggle({
		name = "drive",
		flag = "drive",
		value = CFG.drive,
		callback = function(v) CFG.drive = v end,
	})
	blockRow:CreateToggle({
		name = "meat shield",
		description = "sit in the seam between carrier and his two hunters",
		flag = "meatShield",
		value = CFG.meatShield,
		callback = function(v) CFG.meatShield = v end,
	})

	blockTab:CreateSlider({
		name = "engage",
		range = { 3, 8 },
		increment = 0.1,
		value = CFG.blockEngage,
		suffix = " st",
		flag = "blockEngage",
		callback = function(v) CFG.blockEngage = v end,
	})

	blockTab:CreateSlider({
		name = "scan",
		range = { 12, 40 },
		increment = 1,
		value = CFG.blockScan,
		suffix = " st",
		flag = "blockScan",
		callback = function(v) CFG.blockScan = v end,
	})

	blockTab:CreateSlider({
		name = "hold",
		range = { 0.4, 1.6 },
		increment = 0.05,
		value = CFG.blockHold,
		suffix = " s",
		flag = "blockHold",
		callback = function(v) CFG.blockHold = v end,
	})

	blockTab:CreateSlider({
		name = "yield to tackle",
		range = { 6, 20 },
		increment = 1,
		value = CFG.yieldTo,
		suffix = " st",
		flag = "yieldTo",
		callback = function(v) CFG.yieldTo = v end,
	})

	blockTab:CreateKeybind({
		name = "toggle block",
		value = Enum.KeyCode.B,
		flag = "blockKey",
		callback = function()
			CFG.block = not CFG.block
			WIDGET.blockToggle:Set(CFG.block, true)
		end,
	})

	-- look --------------------------------------------------------------------

	section(lookTab, "ESP")

	local espRow = groupOf(lookTab)
	espRow:CreateToggle({
		name = "aim target",
		flag = "espAim",
		value = CFG.espAim,
		callback = function(v) CFG.espAim = v end,
	})
	espRow:CreateToggle({
		name = "carrier",
		flag = "espCarrier",
		value = CFG.espCarrier,
		callback = function(v) CFG.espCarrier = v end,
	})
	espRow:CreateToggle({
		name = "block threat",
		flag = "espThreat",
		value = CFG.espThreat,
		callback = function(v) CFG.espThreat = v end,
	})
	espRow:CreateToggle({
		name = "tracers",
		flag = "tracers",
		value = CFG.tracers,
		callback = function(v) CFG.tracers = v end,
	})
	espRow:CreateToggle({
		name = "pass arc",
		description = "neon beam from the release point to the landing spot",
		flag = "passArc",
		value = CFG.passArc,
		callback = function(v) CFG.passArc = v end,
	})
	espRow:CreateToggle({
		name = "ghost route",
		description = "neon line to where the pick will actually be",
		flag = "ghostRoute",
		value = CFG.ghostRoute,
		callback = function(v) CFG.ghostRoute = v end,
	})
	espRow:CreateToggle({
		name = "coverage heat",
		description = "7x7 grid around the pick, red where defenders cluster",
		flag = "coverHeat",
		value = CFG.coverHeat,
		callback = function(v) CFG.coverHeat = v end,
	})

	lookTab:CreateColorPicker({
		name = "aim colour",
		color = COLORS.aim,
		flag = "aimColor",
		callback = function(color)
			COLORS.aim = color
			aimMark.hl.FillColor = color
			aimMark.hl.OutlineColor = color:Lerp(Color3.new(1, 1, 1), 0.45)
			aimMark.box.Color3 = color
			aimMark.beam.Color = color
			aimMark.text.TextColor3 = color
			if WIDGET.tagTarget then WIDGET.tagTarget:SetColor(color) end
		end,
	})

	pcall(function()
		lookTab:CreateDropdown({
			name = "skin",
			description = "repaints the whole window live",
			options = { "volt", "default", "cobalt", "ember", "amethyst", "frost", "rose" },
			value = "volt",
			flag = "skin",
			callback = function(pick)
				local chosen = type(pick) == "table" and pick[1] or pick
				if chosen == "volt" then
					pcall(function() window:ChangeTheme(slimTheme()) end)
				else
					pcall(function() window:ChangeTheme(chosen) end)
				end
			end,
		})
	end)

	section(lookTab, "PANEL")

	lookTab:CreateButton({
		name = "unload",
		description = "tear the panel down and leave the game alone",
		icon = 83277910885129,
		callback = function()
			shutdown()
		end,
	})

	-- live --------------------------------------------------------------------

	-- the dashboard is the newest part of the library; a missing element here
	-- costs a card, not the window
	pcall(function()
		liveTab:CreateText({
			name = "RUGBALL // slim suite",
			text = "client side  |  steer 12.5 hz  |  camera writes 0  |  no shoulder offset\nE throw   F clear   T tackle   B block   K settings",
		})
	end)

	local statRow = groupOf(liveTab)
	pcall(function()
		WIDGET.statTarget = statRow:CreateStat({
			name = "target",
			suffix = "st",
			value = 0,
			changeMode = "absolute",
		})
		WIDGET.statCarrier = statRow:CreateStat({
			name = "carrier",
			suffix = "st",
			value = 0,
			changeMode = "absolute",
		})
		WIDGET.statShots = statRow:CreateStat({
			name = "throws",
			value = 0,
			changeMode = "absolute",
		})
	end)

	-- second row: what the session has actually done
	local statRow2 = groupOf(liveTab)
	pcall(function()
		WIDGET.statPicks = statRow2:CreateStat({
			name = "picks",
			value = stats.picks,
			changeMode = "absolute",
		})
		WIDGET.statTackles = statRow2:CreateStat({
			name = "tackles",
			value = stats.tackles,
			changeMode = "absolute",
		})
		WIDGET.statAvg = statRow2:CreateStat({
			name = "avg",
			suffix = "st",
			value = 0,
			changeMode = "absolute",
		})
	end)

	-- reach: how much of the 226.9 st throw ceiling the current pick uses
	pcall(function()
		WIDGET.chargeBar = liveTab:CreateProgress({
			name = "throw reach",
			description = "picked man against the 226.9 st ceiling",
			range = { 0, 227 },
			value = 0,
			format = function(v)
				return string.format("%.0f st", v)
			end,
		})
	end)

	-- pickup: loose, moving, or in your hands
	pcall(function()
		WIDGET.ballBar = liveTab:CreateProgress({
			name = "ball",
			range = { 0, 2 },
			value = 0,
			format = function(v)
				local names = { "loose", "in flight", "in hand" }
				return names[math.clamp(math.floor(v) + 1, 1, 3)]
			end,
		})
	end)

	-- field radar: a plain frame sitting in the library's own list layout, with
	-- pooled dots. camera-relative, so up is always where you are looking.
	pcall(function()
		local page = liveTab.tabPage
		if not page then return end

		WIDGET.radarFrame = Instance.new("Frame")
		WIDGET.radarFrame.Name = "Radar"
		WIDGET.radarFrame.BackgroundColor3 = Color3.fromRGB(11, 15, 20)
		WIDGET.radarFrame.BorderSizePixel = 0
		WIDGET.radarFrame.Size = UDim2.new(1, 0, 0, 200)
		WIDGET.radarFrame.ClipsDescendants = true
		WIDGET.radarFrame.Parent = page
		pcall(function() WIDGET.radarFrame.LayoutOrder = #liveTab.elements * 10 + 5 end)

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = WIDGET.radarFrame

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(52, 60, 76)
		stroke.Transparency = 0.25
		stroke.Parent = WIDGET.radarFrame

		WIDGET.radarCanvas = Instance.new("Frame")
		WIDGET.radarCanvas.Name = "Field"
		WIDGET.radarCanvas.AnchorPoint = Vector2.new(0.5, 0.5)
		WIDGET.radarCanvas.Position = UDim2.fromScale(0.5, 0.5)
		WIDGET.radarCanvas.Size = UDim2.fromOffset(184, 184)
		WIDGET.radarCanvas.BackgroundTransparency = 1
		WIDGET.radarCanvas.Parent = WIDGET.radarFrame

		for _, frac in ipairs({ 0.5, 1 }) do
			local ring = Instance.new("Frame")
			ring.Name = "Ring"
			ring.AnchorPoint = Vector2.new(0.5, 0.5)
			ring.Position = UDim2.fromScale(0.5, 0.5)
			ring.Size = UDim2.fromScale(frac, frac)
			ring.BackgroundTransparency = 1
			ring.Parent = WIDGET.radarCanvas

			local rc = Instance.new("UICorner")
			rc.CornerRadius = UDim.new(1, 0)
			rc.Parent = ring

			local rs = Instance.new("UIStroke")
			rs.Color = Color3.fromRGB(48, 58, 74)
			rs.Thickness = 1
			rs.Transparency = frac == 1 and 0.35 or 0.65
			rs.Parent = ring
			WIDGET.radarRings[#WIDGET.radarRings + 1] = ring
		end

		for i = 1, 32 do
			local dot = Instance.new("Frame")
			dot.Name = "Dot"
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Size = UDim2.fromOffset(6, 6)
			dot.BorderSizePixel = 0
			dot.Visible = false
			dot.ZIndex = 4
			dot.Parent = WIDGET.radarCanvas

			local dc = Instance.new("UICorner")
			dc.CornerRadius = UDim.new(1, 0)
			dc.Parent = dot

			local ds = Instance.new("UIStroke")
			ds.Color = Color3.fromRGB(6, 9, 12)
			ds.Thickness = 1
			ds.Transparency = 0.25
			ds.Parent = dot

			WIDGET.radarDots[i] = dot
		end

		local caption = Instance.new("TextLabel")
		caption.Name = "Caption"
		caption.BackgroundTransparency = 1
		caption.Position = UDim2.fromOffset(12, 8)
		caption.Size = UDim2.new(1, -24, 0, 16)
		caption.Font = Enum.Font.GothamMedium
		caption.TextSize = 12
		caption.TextXAlignment = Enum.TextXAlignment.Left
		caption.TextColor3 = Color3.fromRGB(120, 132, 152)
		caption.Text = "RADAR  |  you lime  mates blue  enemies red  ball white"
		caption.Parent = WIDGET.radarFrame
	end)

	pcall(function()
		liveTab:CreateSlider({
			name = "radar range",
			range = { 20, 120 },
			increment = 5,
			value = CFG.radarRange,
			suffix = " st",
			flag = "radarRange",
			callback = function(v) CFG.radarRange = v end,
		})
	end)

	liveTab:CreateToggle({
		name = "stat card",
		description = "floating session HUD, bottom right of the screen",
		flag = "statCard",
		value = CFG.statCard,
		callback = function(v)
			CFG.statCard = v
			if statCardGui then pcall(function() statCardGui.Enabled = v end) end
		end,
	})

	liveTab:CreateToggle({
		name = "replay trail",
		description = "neon dots repainting your last run-back when the play ends",
		flag = "replay",
		value = CFG.replay,
		callback = function(v) CFG.replay = v end,
	})

	liveTab:CreateKeybind({
		name = "panic key",
		description = "press: kill every toggle | press again: rebuild",
		value = Enum.KeyCode.P,
		flag = "panicKey",
		callback = function() panic() end,
	})

	section(liveTab, "ENGINE")

	local engineRow = groupOf(liveTab)
	pcall(function()
		WIDGET.statFps = engineRow:CreateStat({
			name = "fps",
			value = 0,
			changeMode = "absolute",
		})
		WIDGET.statErr = engineRow:CreateStat({
			name = "frame errors",
			value = 0,
			changeMode = "absolute",
		})
	end)
	pcall(function()
		WIDGET.statUp = engineRow:CreateStat({
			name = "uptime",
			suffix = "s",
			value = 0,
			changeMode = "absolute",
		})
	end)

	section(liveTab, "BUILD")

	liveTab:CreateToggle({
		name = "team sync",
		description = "auto-load builds friends send through chat (SlimBuild tags)",
		flag = "chatSync",
		value = CFG.chatSync,
		callback = function(v) CFG.chatSync = v end,
	})

	liveTab:CreateButton({
		name = "build -> team chat",
		description = "short build code in a few chat messages",
		callback = function()
			local sent = sendBuildChat()
			if sent == 0 then
				pcall(function()
					window:Notify({ title = "SLIM", content = "no chat channel found", duration = 4 })
				end)
			else
				pcall(function()
					window:Notify({ title = "SLIM", content = string.format("build sent (%d msgs)", sent), duration = 4 })
				end)
			end
		end,
	})

	liveTab:CreateButton({
		name = "copy build",
		description = "the whole build + playbook as one paste string",
		callback = function()
			local s = buildShareString()
			local ok = pcall(function() SetClipboard(s) end)
			pcall(function()
				window:Notify({
					title = "RUGBALL",
					content = ok and "build copied to clipboard" or "clipboard failed - console only",
					duration = 4,
				})
			end)
			mode = "build copied"
		end,
	})

	liveTab:CreateButton({
		name = "paste build",
		description = "paste a build string, load it",
		callback = function()
			-- a tiny modal: paste the string, hit load, it applies validated
			local gui2 = Instance.new("ScreenGui")
			gui2.Name = "SlimShare"
			gui2.ResetOnSpawn = false
			gui2.Parent = LocalPlayer:FindFirstChild("PlayerGui")
			local back = Instance.new("Frame")
			back.Size = UDim2.new(1, 0, 1, 0)
			back.BackgroundColor3 = Color3.fromRGB(6, 8, 11)
			back.BackgroundTransparency = 0.25
			back.ZIndex = 5
			back.Parent = gui2
			local box = Instance.new("TextBox")
			box.AnchorPoint = Vector2.new(0.5, 0.5)
			box.Position = UDim2.new(0.5, 0, 0.47, 0)
			box.Size = UDim2.new(0.6, 0, 0.3, 0)
			box.BackgroundColor3 = Color3.fromRGB(14, 17, 23)
			box.TextColor3 = Color3.fromRGB(210, 220, 235)
			box.Font = Enum.Font.Code
			box.TextSize = 13
			box.Text = ""
			box.ClearTextOnFocus = false
			box.TextWrapped = true
			box.MultiLine = true
			box.ZIndex = 6
			box.Parent = back
			local btn = Instance.new("TextButton")
			btn.AnchorPoint = Vector2.new(0.5, 0)
			btn.Position = UDim2.new(0.5, 0, 0.64, 0)
			btn.Size = UDim2.new(0.16, 0, 0.05, 0)
			btn.BackgroundColor3 = Color3.fromRGB(178, 255, 64)
			btn.TextColor3 = Color3.fromRGB(10, 12, 16)
			btn.Font = Enum.Font.GothamBold
			btn.TextSize = 16
			btn.Text = "load build"
			btn.ZIndex = 6
			btn.Parent = back
			local cancel = Instance.new("TextButton")
			cancel.AnchorPoint = Vector2.new(0.5, 0)
			cancel.Position = UDim2.new(0.5, 0, 0.71, 0)
			cancel.Size = UDim2.new(0.1, 0, 0.035, 0)
			cancel.BackgroundColor3 = Color3.fromRGB(34, 40, 52)
			cancel.TextColor3 = Color3.fromRGB(150, 158, 172)
			cancel.Font = Enum.Font.GothamBold
			cancel.TextSize = 13
			cancel.Text = "cancel"
			cancel.ZIndex = 6
			cancel.Parent = back
			btn.MouseButton1Click:Connect(function()
				if applyShareString(box.Text) then
					pcall(function()
						window:Notify({ title = "RUGBALL", content = "build loaded", duration = 4 })
					end)
					gui2:Destroy()
					mode = "build loaded"
				end
			end)
			cancel.MouseButton1Click:Connect(function()
				gui2:Destroy()
			end)
		end,
	})

	section(liveTab, "CONSOLE")
	WIDGET.statusBox = liveTab:CreateConsole({ name = "", height = 210, follow = false })

	-- catch --------------------------------------------------------------------
	section(catchTab, "BALL MAGNET")

	catchTab:CreateToggle({
		name = "ball magnet",
		description = "steer straight at the ball's landing point while it's in flight",
		flag = "catchMagnet",
		value = CFG.catchMagnet,
		callback = function(v) CFG.catchMagnet = v end,
	})

	catchTab:CreateSlider({
		name = "magnet radius",
		description = "max distance to start pulling toward the landing spot",
		range = { 10, 50 },
		increment = 1,
		value = CFG.magnetRadius,
		suffix = " st",
		flag = "magnetRadius",
		callback = function(v) CFG.magnetRadius = v end,
	})

	catchTab:CreateToggle({
		name = "magnet lead",
		description = "arrive a beat before the ball lands, not exactly on it",
		flag = "magnetLead",
		value = CFG.magnetLead,
		callback = function(v) CFG.magnetLead = v end,
	})

	catchTab:CreateToggle({
		name = "magnet catch",
		description = "auto dive at the very end of the flight to make the grab",
		flag = "magnetCatch",
		value = CFG.magnetCatch,
		callback = function(v) CFG.magnetCatch = v end,
	})

	catchTab:CreateSlider({
		name = "magnet speed",
		description = "steer strength while the magnet is active",
		range = { 0.2, 1.0 },
		increment = 0.05,
		value = CFG.magnetSpeed,
		suffix = "x",
		flag = "magnetSpeed",
		callback = function(v) CFG.magnetSpeed = v end,
	})

	catchTab:CreateButton({
		name = "teleport ball → me",
		description = "instant: loose ball snaps to your rig",
		callback = function()
			local b = ballPart()
			local r = myRig()
			if not b or not r or not r.PrimaryPart then return end
			if (b:GetAttribute("CarrierUserId") or 0) ~= 0 then return end
			local target = r.PrimaryPart.Position + Vector3.new(0, CFG.ballToMeY or 4, 0)
			pcall(function() b.CFrame = CFrame.new(target) end)
			pcall(function() b.AssemblyLinearVelocity = Vector3.zero end)
			mode = "ball teleported to me"
		end,
	})

	catchTab:CreateToggle({
		name = "keep ball on me",
		description = "continuously teleport the loose ball to your rig",
		flag = "ballToMe",
		value = CFG.ballToMe,
		callback = function(v) CFG.ballToMe = v end,
	})

	catchTab:CreateSlider({
		name = "ball height",
		description = "studs above you when it lands",
		range = { 2, 12 },
		increment = 0.5,
		value = CFG.ballToMeY,
		suffix = " st",
		flag = "ballToMeY",
		callback = function(v) CFG.ballToMeY = v end,
	})

	catchTab:CreateButton({
		name = "teleport → play",
		description = "you snap to the ball or carrier",
		callback = function()
			local b = ballPart()
			local c = carrier()
			local r = myRig()
			if not r or not r.PrimaryPart then return end
			local target = nil
			if c and c.PrimaryPart then
				target = c.PrimaryPart.Position
			elseif b then
				target = b.Position
			else
				return
			end
			local off = Vector3.new(0, CFG.teleOffset or 6, 0)
			pcall(function() r.PrimaryPart.CFrame = CFrame.new(target + off) end)
			mode = "teleported to play"
		end,
	})

	catchTab:CreateSlider({
		name = "teleport offset",
		description = "studs above the ball when you land",
		range = { 2, 12 },
		increment = 0.5,
		value = CFG.teleOffset,
		suffix = " st",
		flag = "teleOffset",
		callback = function(v) CFG.teleOffset = v end,
	})

	-- first-run briefing: what is running, and the four binds. once per client
	-- session, so reloading while tuning does not shove a card in your face.
	if not _G.SlimBriefed then
		local shown = pcall(function()
			_G.SlimBriefed = true
			_G.SlimPopup = window:Popup({
				title = "BRIEFING",
				subtitle = "slim suite  |  client side only",
				boxes = {
					{ title = "AIM", description = "holds the deepest open man. hover to pin him, E to throw." },
					{ title = "TACKLE", description = "fires the game's own tackle inside 7.5 st, 0.55 s hold." },
					{ title = "BLOCK", description = "drives the carrier's lane, yields the moment a tackle is live." },
					{ title = "BINDS", description = "E throw   F clear   T tackle   B block   K settings" },
				},
				options = { { text = "Let's go", style = "primary" } },
			})
		end)
		if not shown then _G.SlimBriefed = nil end
	end

	pcall(function()
		window:Notify({
			title = "RUGBALL  |  slim suite",
			content = "aim + tackle + block are live.\nE throw   F clear   T tackle   B block   K settings",
			duration = 6,
		})
	end)
end

local uiOk, uiErr = pcall(buildUI)
if not uiOk then
	warn("[Slim] panel ui failed: " .. tostring(uiErr) .. " - modules running headless")
elseif not window then
	warn("[Slim] no window - modules running headless, _G.QBAim still exposed")
end

--// radar + lead hotkeys -------------------------------------------------------

-- redraw at 10 hz: camera-relative, so "up" is where you are looking and the
-- dot pattern matches what you see on screen instead of a fixed world axis
local function updateRadar(now, myRoot, allRigs, entry, carrierRig)
	if not (WIDGET.radarFrame and WIDGET.radarCanvas) then return end
	if now - WIDGET.lastRadar < 0.1 then return end
	WIDGET.lastRadar = now

	local cam = Workspace.CurrentCamera
	local look = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
	local fwd = Vector3.new(look.X, 0, look.Z)
	if fwd.Magnitude < 0.01 then fwd = Vector3.new(0, 0, -1) end
	fwd = fwd.Unit
	local right = Vector3.new(-fwd.Z, 0, fwd.X)

	local size = WIDGET.radarCanvas.AbsoluteSize.X
	if size <= 1 then size = 184 end
	local radius = size * 0.5 - 4
	local range = math.max(10, CFG.radarRange)
	local scale = radius / range

	local myT = myTeam()
	local n = 0

	local function place(pos, color, px)
		n = n + 1
		local dot = WIDGET.radarDots[n]
		if not dot then return end
		local dx = pos - myRoot.Position
		local flat = Vector3.new(dx.X, 0, dx.Z)
		local cx = math.clamp(flat:Dot(right) * scale, -radius, radius)
		local cy = math.clamp(-flat:Dot(fwd) * scale, -radius, radius)
		dot.Position = UDim2.new(0.5, cx, 0.5, cy)
		dot.Size = UDim2.fromOffset(px, px)
		dot.BackgroundColor3 = color
		dot.Visible = true
	end

	local ball = ballPart()
	if ball then
		place(ball.Position, Color3.fromRGB(245, 248, 255), 7)
	end

	for _, rig in ipairs(allRigs) do
		if rig ~= myRig() and rig.PrimaryPart then
			local pos = rig.PrimaryPart.Position
			local t = teamOf(rig)
			local color
			if myT and t == myT then
				color = Color3.fromRGB(86, 156, 255)
			elseif myT and t and t ~= myT then
				color = Color3.fromRGB(255, 82, 82)
			else
				color = Color3.fromRGB(150, 158, 172)
			end
			local px = 6
			if entry and entry.rig == rig then
				color = COLORS.aim
				px = 9
			elseif carrierRig == rig then
				px = 8
			end
			place(pos, color, px)
		end
	end

	-- you last, always dead centre
	place(myRoot.Position, Color3.fromRGB(178, 255, 64), 9)

	for i = n + 1, #WIDGET.radarDots do
		WIDGET.radarDots[i].Visible = false
	end
end

-- [ and ] nudge lead five studs mid-play without opening the panel
WIDGET.leadConn = UserInputService.InputBegan:Connect(function(input, typing)
	if typing then return end
	if UserInputService:GetFocusedTextBox() then return end
	local k = input.KeyCode
	if k ~= Enum.KeyCode.LeftBracket and k ~= Enum.KeyCode.RightBracket then return end
	local step = (k == Enum.KeyCode.RightBracket) and 5 or -5
	CFG.lead = math.clamp(math.floor((CFG.lead or 0) + step + 0.5), 0, 100)
	if WIDGET.leadSlider then
		pcall(function() WIDGET.leadSlider:Set(CFG.lead, true) end)
	end
	mode = string.format("lead %d st", CFG.lead)
end)

--// modules -------------------------------------------------------------------

-- step around a body sitting in the path instead of running into it
local function avoidBlockers(myRoot, dir, skip)
	local best = dir
	for _, rig in ipairs(rigs()) do
		if rig ~= myRig() and rig ~= skip and rig.PrimaryPart then
			local delta = rig.PrimaryPart.Position - myRoot.Position
			local flat = Vector3.new(delta.X, 0, delta.Z)
			local d = flat.Magnitude
			if d > 0.8 and d < 5.5 then
				local u = flat.Unit
				local ahead = u:Dot(dir)
				if ahead > 0.45 then
					local side = Vector3.new(-dir.Z, 0, dir.X)
					if side:Dot(u) > 0 then side = -side end
					best = (best + side * (1.1 - ahead * 0.5)).Unit
				end
			end
		end
	end
	return best
end

-- auto guard: the enemy ball is in the air, so get on the man he is throwing
-- to and make the catch happen through us. our own throw is not an assignment.
local function guardTick(now, mine, myRoot)
	if not CFG.guard or hasBall() then return nil, nil end
	local ball = ballPart()
	if not ball or ball:GetAttribute("InFlight") ~= true then return nil, nil end
	if myLastThrowAt > 0 and now - myLastThrowAt < 5 then return nil, nil end
	local spot = ball:GetAttribute("LandingPoint")
	local target = typeof(spot) == "Vector3" and spot or ball.Position
	local myT = myTeam()
	local best, bestD
	for _, rig in ipairs(rigs()) do
		if rig ~= mine and rig.PrimaryPart then
			local t = teamOf(rig)
			local enemy = (myT == nil and t ~= nil) or (t ~= nil and myT ~= nil and t ~= myT)
			if enemy then
				local d = (rig.PrimaryPart.Position - target).Magnitude
				if not bestD or d < bestD then
					best, bestD = rig, d
				end
			end
		end
	end
	if not best then return nil, nil end
	local root = best.PrimaryPart
	local toBall = target - root.Position
	if toBall.Magnitude < 0.5 then
		toBall = Vector3.new(0, 0, -1)
	end
	-- stand in his hands: a couple of studs toward the ball, on his ball side
	local k = math.min(CFG.guardStand or 3.5, toBall.Magnitude * 0.4)
	local stand = root.Position + toBall.Unit * k
	local flat = Vector3.new(stand.X - myRoot.Position.X, 0, stand.Z - myRoot.Position.Z)
	local d = flat.Magnitude
	if d < 0.8 then
		flat = Vector3.new(toBall.X, 0, toBall.Z)
	end
	-- contest: we are on him and the ball is about to arrive, go get it
	local ballClose = (ball.Position - stand).Magnitude < (CFG.guardJump or 7)
	local himClose = (root.Position - myRoot.Position).Magnitude < 6
	if ballClose and himClose and now >= nextJump and Jump then
		if ball.Position.Y - myRoot.Position.Y > 3 then
			nextJump = now + 0.8
			press(Jump, 0.1)
			stats.intercepts = stats.intercepts + 1
			return nil, "guard jump"
		end
	end
	return flat.Unit, string.format("guard %s %.0f", label(best), d)
end

-- deep half: pre-throw defense. nothing is live, so sit over the top of the
-- deepest receiver so nothing gets behind you.
local function deepHalfTick(now, mine, myRoot, carrierRig)
	if not CFG.deepHalf or hasBall() then return nil, nil end
	local ball = ballPart()
	if ball and ball:GetAttribute("InFlight") == true then return nil, nil end
	local myT = myTeam()
	if carrierRig and teamOf(carrierRig) ~= myT then return nil, nil end
	local anchorPos = carrierRig and carrierRig.PrimaryPart.Position
		or (ball and ball.Position or myRoot.Position)
	local best, bestDepth
	for _, rig in ipairs(rigs()) do
		if rig ~= mine and rig.PrimaryPart then
			local t = teamOf(rig)
			local enemy = (myT == nil and t ~= nil) or (t ~= nil and t ~= myT)
			if enemy then
				local flat = Vector3.new(rig.PrimaryPart.Position.X - anchorPos.X, 0, rig.PrimaryPart.Position.Z - anchorPos.Z)
				local depth = flat.Magnitude
				if not bestDepth or depth > bestDepth then
					best, bestDepth = rig, depth
				end
			end
		end
	end
	if not best or bestDepth < 18 then return nil, nil end
	local away = best.PrimaryPart.Position - anchorPos
	local spot = best.PrimaryPart.Position + away.Unit * 4
	local flat = Vector3.new(spot.X - myRoot.Position.X, 0, spot.Z - myRoot.Position.Z)
	if flat.Magnitude < 0.8 then return nil, nil end
	return flat.Unit, string.format("deep half %s %.0f", label(best), flat.Magnitude)
end

-- ball in the air or on the ground: run under the landing spot, jump on arrival
local function interceptTick(now, mine, myRoot)
	-- guard outranks the plain intercept: defending the man beats the spot
	local gdir, gstate = guardTick(now, mine, myRoot)
	if gdir or gstate then return gdir, gstate end
	if not CFG.intercept or hasBall() then return nil, nil end
	local ball = ballPart()
	if not ball then return nil, nil end
	if ball:GetAttribute("InFlight") ~= true and ball:GetAttribute("Loose") ~= true then
		return nil, nil
	end
	local spot = ball:GetAttribute("LandingPoint")
	local target = typeof(spot) == "Vector3" and spot or ball.Position
	local flat = Vector3.new(target.X - myRoot.Position.X, 0, target.Z - myRoot.Position.Z)
	local d = flat.Magnitude
	if d < 1.2 or d > CFG.interceptRange then return nil, nil end
	if d < 5 and now >= nextJump and Jump then
		if ball.Position.Y - myRoot.Position.Y > 4 then
			nextJump = now + 0.8
			press(Jump, 0.1)
			stats.intercepts = stats.intercepts + 1
			return nil, "jump"
		end
	end
	return flat.Unit, string.format("intercept %.0f", d)
end

local function tackleTick(now, mine, myRoot, carrierRig)
	if not (CFG.tackle and carrierRig) or carrierRig == mine then
		markOff(carrierMark)
		return nil, nil
	end
	if teamOf(carrierRig) == myTeam() then
		markOff(carrierMark)
		return nil, nil
	end

	local root = carrierRig.PrimaryPart
	if not root then
		markOff(carrierMark)
		return nil, nil
	end

	local delta = root.Position - myRoot.Position
	local dist = delta.Magnitude

	if CFG.espCarrier then
		markTo(carrierMark, carrierRig, string.format("%s  %.1f st", label(carrierRig), dist), myRoot.Position, now)
	else
		markOff(carrierMark)
	end

	local eligible = root:GetAttribute("Tackleable") ~= false
		and root:GetAttribute("PrimeDance") ~= true
		and mine:GetAttribute("Frozen") ~= true

	if not eligible then
		return nil, string.format("carrier %.1f (not eligible)", dist)
	end

	-- truck dodge: a trucking carrier is tackle-immune and knock-hard for
	-- the spike's life. his pelvis announces the windup (TruckTime ramps),
	-- so side-step the lean direction and come back when he's spent.
	if CFG.dodgeTruck and dist < 7 then
		local tt = root:GetAttribute("TruckTime") or 0
		if tt > 0 and tt < 1.2 then
			local away = myRoot.Position - root.Position
			local awu = Vector3.new(away.X, 0, away.Z)
			if awu.Magnitude > 0.3 then
				local lat = Vector3.new(-awu.Z, 0, awu.X)
				-- dodge the shoulder he's leaning into
				local lean = root.CFrame.RightVector
				local side = lat.Unit
				if side:Dot(lean) > 0 then side = -side end
				local dir = (awu.Unit * 0.55 + side).Unit
				if CFG.pathing then dir = avoidBlockers(myRoot, dir, carrierRig) end
				return dir, string.format("dodge truck %.1f", dist)
			end
		end
	end

	-- engage: in reach now, or cross into reach inside the next beat. the
	-- second arm stops the dead cycle of firing at a ghost, eating the
	-- cooldown, and watching the carrier run through the empty window.
	local dirToHim = delta / math.max(0.01, dist)
	local relVel = root.AssemblyLinearVelocity - myRoot.AssemblyLinearVelocity
	local closing = relVel:Dot(dirToHim) -- positive = gap shrinking
	local inReach = dist <= CFG.tackleRange
		or (closing > 4 and dist <= CFG.tackleRange + closing * 0.09)
	if inReach and now >= nextTackle then
		if tacklePress(mine) then
			nextTackle = now + CFG.tackleCd
			triggerPop(0.9)
			stats.tackles = stats.tackles + 1
			return nil, string.format("tackle %.1f", dist)
		end
		-- another hold owns the input: keep driving, don't eat the cd empty
	elseif CFG.dive and now >= nextDive then
		-- dive reach can never be smaller than the tackle reach: if the two
		-- sliders touch, the band in between vanishes and the dive never fires
		local diveReach = math.max(CFG.diveRange, CFG.tackleRange + 4)
		if dist <= diveReach and dist > CFG.tackleRange then
			-- smart dive lead: a dive committed at a cutting runner dies in
			-- the grass. steer at where he WILL be, fire once pointed there,
			-- and a dwell cap still bites throwers who keep juking forever.
			local vFlat = Vector3.zero
			if CFG.diveLead then
				local cv = root.AssemblyLinearVelocity
				vFlat = Vector3.new(cv.X, 0, cv.Z)
			end
			if CFG.diveLead and vFlat.Magnitude > 3 then
				local leadAmt = vFlat.Magnitude * (CFG.diveLeadTime or 0.22)
				local leadPt = root.Position + vFlat.Unit * leadAmt
				local dd = leadPt - myRoot.Position
				local dflat = Vector3.new(dd.X, 0, dd.Z)
				if dflat.Magnitude > 1.2 then
					local aim = dflat.Unit
					local look = myRoot.CFrame.LookVector
					local faceFlat = Vector3.new(look.X, 0, look.Z)
					local dot = faceFlat.Magnitude > 0.1 and faceFlat.Unit:Dot(aim) or 1
					local dwellOk = not diveLeadAt or (now - diveLeadAt) > 0.45
					if dot > 0.9 or dwellOk then
						diveLeadAt = nil
						nextDive = now + CFG.tackleCd * 1.5
						press(Dive, 0.12)
						return nil, string.format("dive led %.1f", dist)
					end
					if not diveLeadAt then diveLeadAt = now end
					return aim, string.format("dive lead %.1f", dist)
				end
			end
			diveLeadAt = nil
			nextDive = now + CFG.tackleCd * 1.5
			press(Dive, 0.12)
			return nil, string.format("dive %.1f", dist)
		end
		diveLeadAt = nil -- slid out of the band: drop the lead, drive under him
	end

	if CFG.pursue and dist > CFG.tackleRange * 0.75 then
		local flat = Vector3.new(delta.X, 0, delta.Z)
		if flat.Magnitude > 0.5 then
			local dir = flat.Unit
			-- intercept chase: aim up his future spot. straightlining at his
			-- body refunds him a step every plant; a runner almost never
			-- outsprints another runner who took his angle early.
			if CFG.tackleLead then
				local cv = root.AssemblyLinearVelocity
				local vFlat = Vector3.new(cv.X, 0, cv.Z)
				local along = dir:Dot(vFlat.Unit)
				if vFlat.Magnitude > 2 and along > 0.25 then
					-- we're chasing his tail, not staring him down: run the
					-- cut-off. reach time from closing speed joint over both.
					local myVel = myRoot.AssemblyLinearVelocity
					local mySpd = Vector3.new(myVel.X, 0, myVel.Z).Magnitude
					if mySpd < 12 then mySpd = 24 end -- standing: plan for cruise
					local closingSpd = math.max(6, mySpd + vFlat.Magnitude * along)
					local tHit = flat.Magnitude / closingSpd
					local ahead = root.Position + vFlat.Unit * math.min(vFlat.Magnitude * tHit, 26)
					local dd = ahead - myRoot.Position
					local dflat = Vector3.new(dd.X, 0, dd.Z)
					if dflat.Magnitude > 1 then dir = dflat.Unit end
				end
			end
			-- swarm: a teammate already engaging him means the pile is full.
			-- take the lane on the far side of the carrier from the mate -
			-- whoever he juke-bounces off runs straight into us.
			if CFG.swarm then
				for _, mate in ipairs(rigs()) do
					if mate ~= mine and mate.PrimaryPart and teamOf(mate) == myTeam() then
						local md = (mate.PrimaryPart.Position - root.Position).Magnitude
						if md < 6 then
							local runThrough = root.Position - mate.PrimaryPart.Position
							local rFlat = Vector3.new(runThrough.X, 0, runThrough.Z)
							if rFlat.Magnitude > 2 then
								local lane = root.Position + rFlat.Unit * 6
								local dd = lane - myRoot.Position
								local dflat = Vector3.new(dd.X, 0, dd.Z)
								if dflat.Magnitude > 1 then
									dir = dflat.Unit
									break
								end
							end
						end
					end
				end
			end
			if CFG.pathing then dir = avoidBlockers(myRoot, dir, carrierRig) end
			return dir, string.format("chase %.1f", dist)
		end
	end
	return nil, string.format("carrier %.1f", dist)
end

-- highest priority threat: closest opposing non-carrier to my team's carrier
local function findThreat(myRoot, myT, ballRig)
	local best, bestScore, bestDist = nil, math.huge, nil
	for _, rig in ipairs(rigs()) do
		if rig ~= myRig() then
			local root = rig.PrimaryPart
			local t = teamOf(rig)
			local enemy = (t ~= nil and myT ~= nil) and t ~= myT
			local blockable = rig:GetAttribute("Tackleable") ~= true
			local frozen = rig:GetAttribute("Frozen") == true
			local downed = root and root:GetAttribute("Down") == true
			if enemy and blockable and not frozen and not downed then
				local d = (root.Position - myRoot.Position).Magnitude
				if d <= CFG.blockScan then
					local toBall = ballRig and (root.Position - ballRig.PrimaryPart.Position).Magnitude or d
					local score = toBall - (rig == stickyThreat and 3 or 0)
					if score < bestScore then
						best, bestScore, bestDist = rig, score, d
					end
				end
			end
		end
	end
	stickyThreat = best
	return best, bestDist
end

local function blockTick(now, mine, myRoot, ballRig)
	if not CFG.block then
		markOff(threatMark)
		return nil, nil
	end

	-- don't chase a carrier auto-tackle is already handling
	if ballRig and ballRig ~= mine then
		local cd = (ballRig.PrimaryPart.Position - myRoot.Position).Magnitude
		if cd <= CFG.yieldTo then
			markOff(threatMark)
			return nil, "yield"
		end
	end

	local threat, dist = findThreat(myRoot, myTeam(), ballRig)
	if not threat or not dist then
		markOff(threatMark)
		return nil, nil
	end

	if CFG.espThreat then
		markTo(threatMark, threat, string.format("BLOCK %s  %.1f st", label(threat), dist), myRoot.Position, now)
	else
		markOff(threatMark)
	end

	local dir = nil
	if CFG.meatShield then
		-- meat shield: instead of matching one threat's lane, sit in the seam
		-- between the ball carrier and his two nearest hunters. the sitting
		-- point slides as they move, so the block happens before contact.
		local carrierRig = ballRig or carrier()
		if carrierRig and carrierRig.PrimaryPart then
			local foes = {}
			for _, rig in ipairs(rigs()) do
				if rig ~= mine and rig ~= carrierRig then
					local root = rig.PrimaryPart
					local frozen = rig:GetAttribute("Frozen") == true
					local downed = root and root:GetAttribute("Down") == true
					if teamOf(rig) ~= myTeam() and not frozen and not downed then
						local d = (root.Position - carrierRig.PrimaryPart.Position).Magnitude
						foes[#foes + 1] = { rig = rig, d = d }
					end
				end
			end
			table.sort(foes, function(a, b) return a.d < b.d end)
			if #foes > 0 then
				-- nearest hunter weighs double so the lane that bites first wins
				local dirSum = Vector3.zero
				local cover = math.min(2, #foes)
				for i = 1, cover do
					local fd = foes[i].rig.PrimaryPart.Position - carrierRig.PrimaryPart.Position
					local flat = Vector3.new(fd.X, 0, fd.Z)
					if flat.Magnitude > 0.5 then
						dirSum = dirSum + flat.Unit * (cover + 1 - i)
					end
				end
				if dirSum.Magnitude > 0.5 then
					local standoff = math.clamp(foes[1].d * 0.5, 4, 8)
					local seat = carrierRig.PrimaryPart.Position + dirSum.Unit * standoff
					local delta = seat - myRoot.Position
					local flat = Vector3.new(delta.X, 0, delta.Z)
					if flat.Magnitude > 1 then dir = flat.Unit end
				end
			end
		end
	end
	if not dir and CFG.drive then
		local delta = threat.PrimaryPart.Position - myRoot.Position
		local flat = Vector3.new(delta.X, 0, delta.Z)
		if flat.Magnitude > 0.4 then dir = flat.Unit end
	end

	local state
	if dist <= CFG.blockEngage then
		if now >= nextBlock then
			press(Tackle, CFG.blockHold)
			triggerPop(0.55)
			nextBlock = now + CFG.blockHold + CFG.blockCd
		end
		state = string.format("blocking %.1f", dist)
	elseif dist <= CFG.blockScan then
		state = string.format("close %.1f", dist)
	else
		state = "no threat"
	end

	return dir, state
end

--// main loop -----------------------------------------------------------------

local lastStatus = 0
local lastStats = 0
local lastCfgSave = 0
local lastStuckRelease = 0
local jukeDir, jukeUntil, lastJuke = nil, 0, 0
local bootAt = os.clock()
local framesSince = 0
local lastFpsAt = 0

-- coach calls: read the coverage on the pick and call the throw in the console.
-- over top = deep help, sitting under = robbing the route, pocket = in his lap.
local function coachCall(entry)
	if not entry or not entry.cover or not entry.cover.PrimaryPart then
		return "no coverage, free throw"
	end
	if not entry.rig or not entry.rig.PrimaryPart then return "-" end
	local rel = entry.cover.PrimaryPart.Position - entry.rig.PrimaryPart.Position
	local along = rel:Dot(entry.dir or Vector3.new(0, 0, -1))
	local d = entry.coverGap or math.huge
	if d < 2.5 then
		return string.format("in his pocket: %s %.1fst", label(entry.cover), d)
	elseif along > 1.5 then
		return string.format("over top: %s %.1fst", label(entry.cover), d)
	elseif along < -2 then
		return string.format("sitting under: %s %.1fst", label(entry.cover), d)
	end
	return string.format("trail: %s %.1fst, open window", label(entry.cover), d)
end

-- catch chance on the throw: safe (green) wide open, risky (yellow) contested,
-- covered (red) dangerous throw. gap is the defender's distance at the throw point.
local function catchStateFor(entry)
	local safeC = Color3.fromRGB(178, 255, 64)
	local riskyC = Color3.fromRGB(255, 221, 35)
	local coveredC = Color3.fromRGB(255, 70, 70)
	if not entry then return "SAFE", safeC end
	local gap = entry.gap or math.huge
	local dist = entry.dist or 0
	local ang = entry.angle or 0
	local inRange = dist <= (CFG.maxDist or 195) and ang <= (CFG.fov or 42) and dist > 6
	local openGate = CFG.openGate or 0
	if not inRange or gap < 6 or (openGate > 0 and gap < openGate) then
		return "COVERED", coveredC
	elseif gap < 12 then
		return "RISKY", riskyC
	end
	return "SAFE", safeC
end

local function statusText(entry, carrierRig, threatState)
	local lines = {}
	lines[#lines + 1] = string.format("mode     %s", mode)
	if entry then
		lines[#lines + 1] = string.format("target   %s  %.0f st  %.0f deg", label(entry.rig), entry.dist or 0, entry.angle or 0)
	else
		lines[#lines + 1] = "target   -"
	end
	lines[#lines + 1] = string.format("carrier  %s", carrierRig and (label(carrierRig) .. "  " .. tostring(teamOf(carrierRig))) or "-")
	if threatState then lines[#lines + 1] = string.format("block    %s", threatState) end
	lines[#lines + 1] = string.format("ball     %s", hasBall() and "in hand" or (canThrow() and "ready" or "-"))
	lines[#lines + 1] = string.format("throws   %d   last c=%.2f", stats.shots, stats.lastCharge)
	lines[#lines + 1] = string.format("session  picks %d  tackles %d  intercepts %d", stats.picks, stats.tackles, stats.intercepts)
	if (stats.shots or 0) > 0 then
		local pct = math.floor((stats.completions or 0) / (stats.shots or 1) * 100 + 0.5)
		lines[#lines + 1] = string.format("accuracy %d%%  (%d/%d, %d dropped)", pct, stats.completions or 0, stats.shots or 0, stats.drops or 0)
	end
	if (CFG.lead or 0) > 0 then
		lines[#lines + 1] = string.format("lead     %d st past the pick", CFG.lead)
	end
	lines[#lines + 1] = string.format("pick     %s", lockManual and "mouse" or "auto")
	if CFG.coach then
		lines[#lines + 1] = string.format("coach    %s", coachCall(entry))
	end
	local cstate, ccol = catchStateFor(entry)
	local coverTxt = entry and entry.cover and string.format("  %s %.1f st", label(entry.cover), entry.coverGap or 0) or ""
	lines[#lines + 1] = string.format("catch    %s%s", cstate, coverTxt)
	return table.concat(lines, "\n")
end

-- one bad frame must not take the loop down with it: warn once, notify once,
-- and only stop after the errors stop being transient.
local frameErrors = 0
local frameWarned = false

-- the loop body lives in its own function so one bad frame cannot unbind the
-- whole panel: the pcall below catches it, warns once, and only stops the loop
-- if it keeps happening.
local function renderFrame()
	local cam = Workspace.CurrentCamera
	if not cam then return end
	Camera = cam

	local mine = myRig()
	if not mine then
		markOff(aimMark)
		markOff(carrierMark)
		markOff(threatMark)
		return
	end
	local myRoot = mine.PrimaryPart
	refreshAntiFall()
	local now = os.clock()
	local origin = throwOrigin()
	local allRigs = rigs()
	framesSince = framesSince + 1

	-- point at a man and he is the target; the auto picker takes over 1.2s later
	-- a pinned lock ignores hover and auto, only a fresh Q / C / F / dropdown change it
	if lockPinned then
		if not locked or not locked.Parent or not locked.PrimaryPart then
			lockClear()
		end
	else
		local hovered = CFG.hoverPick and rigUnderCursor(cam) or nil
		if hovered then
			if hovered ~= locked and mode ~= ("picked " .. label(hovered)) then
				mode = "picked " .. label(hovered)
			end
			locked = hovered
			lockManual = true
			hoverLostAt = 0
		elseif lockManual and locked then
			if hoverLostAt == 0 then hoverLostAt = now end
			if now - hoverLostAt >= CFG.hoverRelease then
				locked = nil
				lockManual = false
				hoverLostAt = 0
				mode = "auto"
			end
		end
	end

	local list = (CFG.aim or lockManual) and candidates(now, origin, allRigs) or {}
	local entry
	if lockManual and locked then
		entry = entryFor(locked, origin, now, cam, allRigs)
	elseif CFG.aim then
		entry = list[1]
		locked = entry and entry.rig or nil
	else
		locked = nil
	end
	currentEntry = entry

	-- tally pick changes, but not the auto picker flickering between two men
	if entry and entry.rig ~= lastPickRig then
		local o = origin or myRoot.Position
		snapDir = (entry.point - o).Unit
		snapSet = true
		if now - WIDGET.lastPickAt > 0.35 then
			stats.picks = stats.picks + 1
			WIDGET.lastPickAt = now
		end
		lastPickRig = entry.rig
	end
	if not entry then lastPickRig = nil snapSet = false end

	-- esp on the aim target
	if CFG.espAim and entry then
		markTo(aimMark, entry.rig, string.format("%s  %.0f st", label(entry.rig), entry.dist), myRoot.Position, now)
	else
		markOff(aimMark)
	end

	-- catch chance billboard over the pick: safe / risky / covered, plus the
	-- man covering him and how far off when the throw is not clean
	if catchMark then
		if entry then
			local cstate, ccol = catchStateFor(entry)
			local ctext = cstate
			if cstate ~= "SAFE" and entry.cover then
				ctext = string.format("%s  %s %.0fst", cstate, label(entry.cover), entry.coverGap or 0)
			end
			markTo(catchMark, entry.rig, ctext, myRoot.Position, now, ccol)
		end
	end

	-- pass preview: the arc the ball will take, colored by catch chance
	if arcPart then
		local show = entry and CFG.passArc and origin and (entry.point - origin).Magnitude > 1
		if show then
			local cstate, ccol = catchStateFor(entry)
			local delta = entry.point - origin
			arcPart.Size = Vector3.new(0.14, 0.14, delta.Magnitude)
			arcPart.CFrame = CFrame.lookAt(origin + delta * 0.5, entry.point)
			arcPart.Color = ccol
			arcPart.Transparency = 0.45
		else
			arcPart.Transparency = 1
		end
	end

	-- ghost route: the continuation of the pick's run to the flight horizon.
	-- same math the throw solves with, drawn on the field.
	if ghostPart then
		local show = entry and CFG.ghostRoute and entry.rig and entry.rig.PrimaryPart
		if show then
			local tail = entry.rig.PrimaryPart.Position
			local t = flightTime((entry.point - origin).Magnitude) + launchLag() + (CFG.horizon or 0)
			local reach = entry.vel or (entry.point - tail)
			local endPt = tail + reach.Unit * math.min(t * reach.Magnitude, 130)
			local delta = endPt - tail
			if delta.Magnitude > 0.6 and t > 0.05 then
				ghostPart.Size = Vector3.new(0.1, 0.1, delta.Magnitude)
				ghostPart.CFrame = CFrame.lookAt(tail + delta * 0.5, endPt)
				ghostPart.Transparency = 0.55
			else
				ghostPart.Transparency = 1
			end
		else
			ghostPart.Transparency = 1
		end
	end

	-- coverage heat: 7x7 tiles centred on the pick, red where the defense
	-- clusters. throttled to 4hz; also the lobby cleanup (no ball, no paint).
	if now - lastHeatAt > 0.25 then
		lastHeatAt = now
		local anchor = entry and entry.rig and entry.rig.PrimaryPart and entry.rig.PrimaryPart.Position
		for ti = 1, #heatTiles do
			local tile = heatTiles[ti]
			if CFG.coverHeat and anchor and ballPart() then
				local gx = (ti - 1) % 7
				local gz = math.floor((ti - 1) / 7)
				local center = anchor + Vector3.new((gx - 3) * 6, -3, (gz - 3) * 6)
				tile.CFrame = CFrame.new(center)
				local pressure = 0
				for _, r in ipairs(allRigs) do
					if r ~= mine and r.PrimaryPart and teamOf(r) ~= myTeam() then
						local d = (r.PrimaryPart.Position - center).Magnitude
						if d < 26 then
							pressure = pressure + (1 - d / 26)
						end
					end
				end
				if pressure < 0.12 then
					tile.Transparency = 1
				else
					local t = math.clamp(pressure, 0, 1)
					tile.Color = Color3.fromRGB(255, math.floor(200 * (1 - t) + 55), math.floor(130 * (1 - t)))
					tile.Transparency = 0.58 - 0.32 * t
				end
			else
				tile.Transparency = 1
			end
		end
	end

	-- replay: sample the run-back while we carry, repaint on the play's end
	if CFG.replay and now - trailLast > 0.12 then
		trailLast = now
		if myRoot then
			if hasBall() then
				if not trailArmed then
					trailPts = {}
					trailArmed = true
				end
				trailPts[#trailPts + 1] = myRoot.Position
				if #trailPts > 400 then
					table.remove(trailPts, 1)
				end
			elseif trailArmed then
				trailArmed = false
				drawTrail(now)
			end
		end
	end

	-- auto throw. the open gate is a coverage check: a defender inside
	-- openGate studs of the receiver means the throw is not worth it.
	if CFG.autoThrow and entry and not throwing and (now - lastThrow) > 1.25 then
		local gap = entry.gap or math.huge
		if CFG.openGate > 0 and gap < CFG.openGate then
			mode = string.format("covered %.0f/%.0f", gap, CFG.openGate)
		elseif hasBall() or canThrow() then
			throwing = true
			lastThrow = now
			local e = entry
			task.spawn(function()
				local ok, err = pcall(doThrow, e)
				if not ok then mode = "err: " .. tostring(err):sub(1, 40) end
				throwing = false
			end)
		end
	end

	local carrierRig = carrier()
	local tackleDir, tackleState, blockDir, blockState

	-- nothing live, nothing to do: no steering, no tackles. the lobby is the
	-- one place a distance audit is guaranteed to be watching.
	if ballPart() == nil then
		markOff(carrierMark)
		markOff(threatMark)
		markOff(magnetMark)
		magnetPart.Transparency = 1
		blockState = "no ball"
	else
		-- a loose or in-flight ball outranks coverage: run under it first
		local interceptDir, interceptState = interceptTick(now, mine, myRoot)
		if interceptDir or interceptState then
			tackleDir, tackleState = interceptDir, interceptState
			blockDir, blockState = nil, "ball"
		else
			-- tackle next: an enemy carrier in reach owns the tackle button
			tackleDir, tackleState = tackleTick(now, mine, myRoot, carrierRig)
			-- escape juke: while holding the ball, sidestep the hit instead of eating it
			if CFG.escapeJuke and hasBall() and tackleDir then
				local threat = findThreat(myRoot, myTeam(), carrierRig)
				if threat and threat.PrimaryPart then
					local away = myRoot.Position - threat.PrimaryPart.Position
					local diru = away.Unit
					local lat = Vector3.new(-diru.Z, 0, diru.X)
					if lat.Magnitude > 0.01 then
						local side = lat.Unit
						local fwdv = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
						if side:Dot(fwdv) < 0.2 then side = -side end
						tackleDir = (diru + side * 0.85).Unit
					end
					tackleState = "juke"
				end
			end
			-- juke bait: a short burst sidestep timed to the hit arriving.
			-- different lever than escape juke (which is continuous): this is
			-- one hard flip when a tackler is CLOSING fast, reads as a normal
			-- cut to the sim, ends quickly so your own pathing resumes.
			if CFG.jukeBait and hasBall() and now >= jukeUntil and now - lastJuke > 1.6 then
				local near, nd = nil, math.huge
				for _, r in ipairs(allRigs) do
					if r ~= mine and r.PrimaryPart and teamOf(r) ~= myTeam() then
						local d = (r.PrimaryPart.Position - myRoot.Position).Magnitude
						if d < nd then
							near, nd = r, d
						end
					end
				end
				if near and near.PrimaryPart and nd < 6.5 then
					local away = myRoot.Position - near.PrimaryPart.Position
					local awu = Vector3.new(away.X, 0, away.Z)
					if awu.Magnitude > 0.3 then
						awu = awu.Unit
						local closing = (near.PrimaryPart.AssemblyLinearVelocity - myRoot.AssemblyLinearVelocity):Dot(awu)
						if closing > 6 then
							local lat = Vector3.new(-awu.Z, 0, awu.X).Unit
							local fwdv = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
							if lat:Dot(fwdv) < 0.2 then lat = -lat end
							jukeDir = (awu * 0.3 + lat).Unit
							jukeUntil = now + 0.28
							lastJuke = now
							tackleState = tackleState or "juke burst"
						end
					end
				end
			end
			if tackleDir then
				blockDir, blockState = nil, "yield"
				if CFG.block then
					local threat = findThreat(myRoot, myTeam(), carrierRig)
					if threat and CFG.espThreat then
						markTo(threatMark, threat, string.format("BLOCK %s  %.1f st", label(threat), (threat.PrimaryPart.Position - myRoot.Position).Magnitude), myRoot.Position, now)
					end
				end
			else
				blockDir, blockState = blockTick(now, mine, myRoot, carrierRig)
			end
			-- deep half: nothing live, so take the deepest receiver's vertical
			if blockDir == nil and CFG.deepHalf then
				local dDir, dState = deepHalfTick(now, mine, myRoot, carrierRig)
				if dDir then
					blockDir, blockState = dDir, dState
				end
			end
		end
	end

	-- juke burst owns the stick for its life, then regular pathing resumes
	local driveOut = (tackleDir or blockDir)
	if now < jukeUntil and jukeDir then
		driveOut = jukeDir
		mode = "juke burst"
	end
	-- ball magnet: steer at the landing point when nothing else owns the stick
	if not driveOut and CFG.catchMagnet then
		local mball = ballPart()
		local mdir = magnetSteer(now, mball, myRoot)
		if mdir then
			driveOut = mdir
			mode = string.format("catch magnet %.0f st", (mball:GetAttribute("LandingPoint") and (mball:GetAttribute("LandingPoint") - myRoot.Position).Magnitude or 0))
			-- paint the magnet target at the landing point
			local lp = mball:GetAttribute("LandingPoint")
			if typeof(lp) == "Vector3" then
				magnetPart.CFrame = CFrame.new(lp + Vector3.new(0, 0.4, 0))
				magnetPart.Transparency = 0.35
			end
			-- magnet catch: auto dive at the very end of the flight so you're
			-- already on the ground when the ball arrives
			if CFG.magnetCatch and now >= nextDive then
				local lp = mball:GetAttribute("LandingPoint")
				local lat = mball:GetAttribute("LandingAt") or 0
				local nowTs = workspace:GetServerTimeNow()
				local remaining = math.max(lat - nowTs, 0)
				if typeof(lp) == "Vector3" and remaining > 0 and remaining < 0.35 then
					local dist = (lp - myRoot.Position).Magnitude
					if dist < 5 then
						nextDive = now + CFG.tackleCd * 1.5
						press(Dive, 0.12)
						mode = "catch magnet dive"
					end
				end
			end
		else
			magnetPart.Transparency = 1
		end
	else
		magnetPart.Transparency = 1
	end
	-- ball to me: continuously teleport the loose ball straight to your rig
	if CFG.ballToMe then
		local b = ballPart()
		if b and (b:GetAttribute("CarrierUserId") or 0) == 0 then
			local target = myRoot.Position + Vector3.new(0, CFG.ballToMeY or 4, 0)
			pcall(function() b.CFrame = CFrame.new(target) end)
			pcall(function() b.AssemblyLinearVelocity = Vector3.zero end)
			magnetPart.Transparency = 1
			mode = "ball to me"
		end
	end
	driveTo(driveOut)
	pumpSteer(now)

	-- rush: the slim rush attribute marks when a tackle or block is driving
	-- into the hit. pure feedback, the sim owns the speed law.
	local boost = (tackleDir ~= nil or blockDir ~= nil) and true or false
	if boost ~= rushOn then
		rushOn = boost
		mine:SetAttribute("SlimRush", boost)
	end

	if tackleState then mode = tackleState end

	if now - lastStatus > 0.1 then
		lastStatus = now
		if WIDGET.statusBox then WIDGET.statusBox:Set(statusText(entry, carrierRig, blockState)) end
	end

	-- dashboard: rolling numbers plus the live tags in the title bar
	if now - lastStats > 0.2 then
		lastStats = now
		-- persistence: keep _G.SlimCfg current even if a shutdown never fires
		if now - lastCfgSave > 2 then
			lastCfgSave = now
			pcall(saveCfg)
		end
		-- stuck press recovery: the sim pins tackle state 3 the whole length
		-- of a tackle hold. if the rig says held but no press of ours is live,
		-- a previous hold leaked - force the release so tackle/dive/speed
		-- channels unblock.
		if not pressing and mine:GetAttribute("TackleState") == 3 and now - lastStuckRelease > 2 then
			lastStuckRelease = now
			pcall(function() Tackle:Fire(false) end)
		end
		-- accuracy: watch our own throw land. teammate holds it = completion,
		-- nobody on the ball and it hit the dirt = incompletion.
		if shotWatch then
			if now - shotWatch.at > 6 then
				shotWatch = nil
			elseif not hasBall() and now - shotWatch.at > 0.7 then
				local b = ballPart()
				if not b then
					shotWatch = nil -- ball despawned, drop the watch
				elseif b:GetAttribute("InFlight") ~= true then
					local held = carrier()
					if held then
						local ht = teamOf(held)
						local myT = myTeam()
						if myT == nil or ht == myT then
							stats.completions = stats.completions + 1
						else
							stats.picked = stats.picked + 1
						end
						shotWatch = nil
					elseif now - shotWatch.at > 3 then
						stats.drops = stats.drops + 1
						shotWatch = nil
					end
				end
			end
		end
		-- route memory: when the ball lands in hand, lock the man you throw to most
		local hb = hasBall()
		if CFG.routeLock and hb and not lastHadBall and not lockManual then
			local bestRig, bestN
			for _, rig in ipairs(lockable()) do
				local n = routeMemory[label(rig)] or 0
				if n > (bestN or 0) then
					bestRig, bestN = rig, n
				end
			end
			if bestRig then
				lockTo(bestRig)
				mode = "route memory: " .. label(bestRig)
			end
		end
		lastHadBall = hb
		-- engine light: is the loop healthy
		if WIDGET.statFps then
			local fps = framesSince / math.max(0.05, now - lastFpsAt)
			pcall(function() WIDGET.statFps:Set(math.floor(fps + 0.5)) end)
		end
		if WIDGET.statErr then pcall(function() WIDGET.statErr:Set(frameErrors) end) end
		if WIDGET.statUp then pcall(function() WIDGET.statUp:Set(math.floor(now - bootAt)) end) end
		lastFpsAt = now
		framesSince = 0
		local tdist = entry and entry.dist or 0
		local cdist = 0
		if carrierRig and carrierRig.PrimaryPart then
			cdist = (carrierRig.PrimaryPart.Position - myRoot.Position).Magnitude
		end
		if WIDGET.statTarget then WIDGET.statTarget:Set(math.floor(tdist + 0.5)) end
		if WIDGET.statCarrier then WIDGET.statCarrier:Set(math.floor(cdist + 0.5)) end
		if WIDGET.statShots then WIDGET.statShots:Set(stats.shots) end
		if WIDGET.statPicks then WIDGET.statPicks:Set(stats.picks) end
		if WIDGET.statTackles then WIDGET.statTackles:Set(stats.tackles) end
		if CFG.statCard then updateStatCard() end
		if WIDGET.statAvg then
			local avg = stats.shots > 0 and (stats.distSum / stats.shots) or 0
			pcall(function() WIDGET.statAvg:Set(math.floor(avg + 0.5)) end)
		end
		if WIDGET.tagTarget then
			if entry then
				if lockPinned then
					WIDGET.tagTarget:SetText("LOCK " .. string.sub(label(entry.rig), 1, 9))
					WIDGET.tagTarget:SetColor(Color3.fromRGB(178, 255, 64))
				else
					WIDGET.tagTarget:SetText(string.format("TGT %.0f st", tdist or 0))
					WIDGET.tagTarget:SetColor(COLORS.aim)
				end
			else
				WIDGET.tagTarget:SetText("NO TGT")
				WIDGET.tagTarget:SetColor(Color3.fromRGB(70, 76, 90))
			end
		end

		-- keep the lock list current as players sub in and out
		if lockDropdown then
			local names = { "none" }
			for _, rig in ipairs(lockable()) do
				names[#names + 1] = label(rig)
			end
			local sig = table.concat(names, "|")
			if sig ~= lockSig then
				lockSig = sig
				pcall(function()
					lockDropdown:Refresh(names)
					if lockPinned and locked then
						lockDropdown:Set(label(locked), true)
					else
						lockDropdown:Set("none", true)
					end
				end)
			end
		end

		-- mode pill: what the loop is doing this second
		if WIDGET.modeTag then
			local shown = string.upper(string.sub(mode, 1, 10))
			pcall(function() WIDGET.modeTag:SetText(shown) end)
		end

		-- the pick card in the aim tab
		if WIDGET.aimCard then
			if entry then
				local extra = ""
				if (CFG.lead or 0) > 0 then extra = string.format("  |  lead %d", CFG.lead) end
				pcall(function()
					WIDGET.aimCard:SetTitle(string.format("picked man  |  %s", label(entry.rig)))
					WIDGET.aimCard:Set(string.format(
						"%s  |  %.0f st  |  %.0f deg  |  %s%s",
						tostring(teamOf(entry.rig)),
						entry.dist or 0,
						entry.angle or 0,
						lockPinned and "locked" or (lockManual and "pinned" or "auto"),
						extra
					))
				end)
			else
				pcall(function()
					WIDGET.aimCard:SetTitle("picked man  |  nobody")
					WIDGET.aimCard:Set(CFG.aim and "auto scanning" or "aim off")
				end)
			end
		end

		-- two little bars that make the numbers mean something
		if WIDGET.chargeBar then
			pcall(function() WIDGET.chargeBar:Set(math.min(tdist, 227)) end)
		end
		if WIDGET.ballBar then
			local state = 0
			if hasBall() then
				state = 2
			elseif ballPart() then
				state = 1
			end
			pcall(function() WIDGET.ballBar:Set(state) end)
		end
	end

	-- the radar keeps its own 10 hz clock, so it does not ride the 5 hz stats tick
	pcall(updateRadar, now, myRoot, allRigs, entry, carrierRig)
end

RunService:BindToRenderStep("SlimPanel", Enum.RenderPriority.Camera.Value + 3, function()
	local ok, err = pcall(renderFrame)
	if ok then
		if frameErrors > 0 then frameErrors = frameErrors - 1 end
		return
	end

	frameErrors = frameErrors + 1
	if not frameWarned then
		frameWarned = true
		warn("[Slim] frame error: " .. tostring(err))
		pcall(function()
			if window and window.Notify then
				window:Notify({ title = "SLIM", content = "module error - running degraded", duration = 5 })
			end
		end)
	end
	if frameErrors > 90 then
		RunService:UnbindFromRenderStep("SlimPanel")
		warn("[Slim] loop stopped after repeated frame errors")
	end
end)

-- anti fall heartbeat: runs after physics each frame so the sim can't
-- re-pin you between render steps. if anti fall is on, frozen/down/truck
-- never stick for more than a single frame.
WIDGET.antiFallConn = RunService.Heartbeat:Connect(function()
	refreshAntiFall()
end)

--// hooks + cleanup -----------------------------------------------------------

_G.QBAim = {
	pick = function(rigOrName)
		local target = rigOrName
		if type(target) == "string" then
			for _, r in ipairs(rigs()) do
				if label(r) == target or r.Name == target then
					target = r
					break
				end
			end
		end
		if typeof(target) == "Instance" and target:IsA("Model") then
			locked = target
			lockManual = true
			lockPinned = true
			hoverLostAt = 0
			mode = "locked " .. label(target)
			return true
		end
		return false
	end,
	lock = function(rigOrName) return lockTo(rigOrName) end,
	unlock = function() lockClear() end,
	clear = function()
		locked = nil
		lockManual = false
		lockPinned = false
		hoverLostAt = 0
		mode = "auto"
		if lockDropdown then
			pcall(function() lockDropdown:Set("none", true) end)
		end
	end,
	throw = function() return requestThrow() end,
	routes = routeApi,
	share = { out = buildShareString, short = buildShortShare, send = sendBuildChat, load = applyShareString },
	cfg = CFG,
	stats = stats,
	panel = window,
	lib = Rayfield,
	box = WIDGET.statusBox,
	getMode = function() return mode, currentEntry end,
	stop = function() shutdown() end,
	panic = panic,
	panicRestore = panicRestore,
}
_G.Slim = _G.QBAim

if STATE and STATE.onCleanup then
	STATE.onCleanup(shutdown)
end

bindChatSync()

if window then
	print("[Slim] panel loaded - Rayfield Gen2 | aim, tackle, block in one window")
else
	print("[Slim] modules loaded headless - no panel window")
end
end

--// embedded suite: anime  (from anime-panel.luau) =========================
Hub.SUITE.anime = function()
--[[
	ANIME PANEL -- Build An Anime Character (place 124617195142196)
	Suite of the RUGBALL hub: same Rayfield Gen2 window family as the football
	panel, same replace-not-stack marker, one render loop, defensive pcall on
	every tick. What it runs:

	auto claim every freebie the game hands out (free gift, daily reward,
	playtime rewards, completed quests), auto spin the wheel whenever a spin is
	available, auto equip the most valuable chair you own, redeem codes in bulk.

	Everything is server-remote driven (ReplicatedStorage.Remotes), paced with
	its own cooldowns, and every server call is pcall-wrapped: a server that
	says "not yet" costs one cycle, not the panel.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

--// replace, not stack ---------------------------------------------------------
-- identical to the football suite on purpose: either hub panel must tearing the
-- other one down, so only one window can ever exist.

local function sweepOldWindows()
	local containers = { game:GetService("CoreGui"), LocalPlayer:FindFirstChild("PlayerGui") }
	local okHui, hui = pcall(function() return gethui() end)
	if okHui and hui then
		containers[#containers + 1] = hui
	end
	for _, cont in ipairs(containers) do
		if cont then
			local ok, list = pcall(function() return cont:GetDescendants() end)
			if ok and list then
				for _, inst in ipairs(list) do
					if inst:IsA("ScreenGui") and inst.DisplayOrder == 99999 and inst:FindFirstChild("RUGBALL", true) then
						pcall(function() inst:Destroy() end)
					end
				end
				-- shot in the dark: an old screen named right at the top
				for _, inst in ipairs(cont:GetChildren()) do
					if inst:IsA("ScreenGui") and inst.Name:find("Rayfield", 1, true) then
						pcall(function() inst:Destroy() end)
					end
				end
			end
		end
	end
end

sweepOldWindows()

--// config, persisted ----------------------------------------------------------

local Defaults = {
	claimAll  = false,  -- free gift, daily, playtime, quests
	claimAd   = false,  -- WatchAdSpin: fire the ad-spin remote on its own cycle
	spinWheel = false,  -- spin whenever a spin is available
	bestChair = false,  -- auto equip your most valuable owned chair
	claimEvery = 6,     -- seconds between claim cycles
	spinEvery  = 10,    -- seconds between wheel checks
	chairEvery = 15,    -- seconds between chair value checks
}

local CFG = {}
do
	local saved = (_G.SlimAnimeCfg ~= nil and type(_G.SlimAnimeCfg) == "table") and _G.SlimAnimeCfg or {}
	for k, v in pairs(Defaults) do
		local s = saved[k]
		CFG[k] = (type(s) == type(v)) and s or v
	end
end

local function saveCfg()
	local copy = {}
	for k, v in pairs(CFG) do copy[k] = v end
	_G.SlimAnimeCfg = copy
end

--// remotes ----------------------------------------------------------------------

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 30)

local function remote(name)
	if not Remotes then return nil end
	return Remotes:FindFirstChild(name)
end

-- invoke a server function, every failure swallowed into nils
local function ask(name, ...)
	local r = remote(name)
	if not r then return false, nil end
	local args = { ... }
	local ok, a, b = pcall(function()
		return r:InvokeServer(unpack(args))
	end)
	if not ok then return false, nil end
	return true, a, b
end

-- theme -------------------------------------------------------------------------
local function slimTheme()
	local t = {
		TextFont = "Montserrat",
		Primary = {
			Background = Color3.fromRGB(10, 12, 16),
			BackgroundSecondary = Color3.fromRGB(14, 17, 23),
			Accent = Color3.fromRGB(178, 255, 64),
			Text = Color3.fromRGB(210, 220, 235),
			TextBoxOutline = Color3.fromRGB(34, 40, 52),
		},
	}
	pcall(function()
		t.TitleFont = Font.fromEnum(Enum.Font.MontserratBold)
		t.Font = Font.fromEnum(Enum.Font.MontserratMedium)
	end)
	return t
end

--// state -------------------------------------------------------------------------

local status = "idle"
local stats = {
	claims = 0,
	quests = 0,
	spins = 0,
	chairEq = 0,
	codes = 0,
	errs = 0,
}
local bootAt = os.clock()

-- ran the last claim pass with what came of it, for the console
local logLines = {}
local lastLogged
local function log(text)
	status = text
	if text == lastLogged then return end -- identical status: no new line, no spam
	lastLogged = text
	table.insert(logLines, os.date("%H:%M") .. "  " .. text)
	if #logLines > 40 then table.remove(logLines, 1) end
	print("[SlimAnime] " .. text)
end

--// game helpers -------------------------------------------------------------------

-- what the profile currently says
local function profile()
	local ok, data = ask("GetPlayerData")
	if not ok or type(data) ~= "table" then return nil end
	return data
end

-- value of a chair from the game's own value table (Modules.ChairValues)
local chairValues = {}
local chairValuesAt = 0
local function refreshChairValues()
	if os.clock() - chairValuesAt < 120 then return true end
	local modules = ReplicatedStorage:FindFirstChild("Modules")
	local mod = modules and modules:FindFirstChild("ChairValues")
	if not mod then
		log("ChairValues module missing - storing raw")
		-- fall back: assume the profile's chair names are the truth and value 0
		return false
	end
	local ok, data = pcall(require, mod)
	if not ok or type(data) ~= "table" then return false end
	chairValues = {}
	local vals = data.Values or data
	for name, entry in pairs(vals) do
		if type(entry) == "table" then
			chairValues[name] = tonumber(entry.Value) or 0
		else
			chairValues[name] = tonumber(entry) or 0
		end
	end
	chairValuesAt = os.clock()
	return true
end

-- the owned chair with the biggest value, or nil when nothing is known
local function bestOwnedChair(p)
	refreshChairValues()
	local chairs = p.Chairs
	if type(chairs) ~= "table" then return nil end
	local best, bestVal
	for _, name in ipairs(chairs) do
		local v = chairValues[name]
		if v and (bestVal == nil or v > bestVal) then
			best, bestVal = name, v
		end
	end
	return best, bestVal
end

--// tick bodies --------------------------------------------------------------------

-- claim pass: free gift (guided by the profile flag), daily, playtime, quests
-- read from the server, ad spin. every server "not yet" costs nothing.
local function claimTick()
	if CFG.claimAll then
		local p = profile()
		if not p then
			log("claim skipped - no profile read")
			stats.errs = stats.errs + 1
			return
		end
		if p.FreeRewardClaimed ~= true then
			local ok = ask("ClaimFreeReward")
			if ok then
				stats.claims = stats.claims + 1
				log("free gift claimed")
			end
		end
		-- daily rewards are server-gated on cooldown: firing it costs nothing
		local ok = ask("ClaimDailyReward")
		if ok then
			stats.claims = stats.claims + 1
			log("daily reward touched")
		end
		-- playtime rewards
		local ok = ask("ClaimPlaytimeReward")
		if ok then
			stats.claims = stats.claims + 1
			log("playtime reward touched")
		end
		-- quests: read, then claim only the completed-but-unclaimed ones
		local okQ, questList = ask("GetQuests")
		if okQ and type(questList) == "table" then
			for _, q in pairs(questList) do
				if type(q) == "table" and q.Completed == true and q.Claimed ~= true and q.Key then
					local okC = ask("ClaimQuest", q.Key)
					if okC then
						stats.quests = stats.quests + 1
						log("quest claimed: " .. tostring(q.Name or q.Key))
					end
				end
			end
		end
	end
	if CFG.claimAd then
		local ev = remote("WatchAdSpin")
		if ev then
			local ok = pcall(function() ev:FireServer() end)
			if ok then log("ad spin touched") end
		end
	end
	status = "claims idle"
end

local function spinTick()
	if not CFG.spinWheel then return end
	local ok, eligible = ask("GetFirstSpinEligible")
	local p = profile()
	local spare = p and tonumber(p.Spins) or 0
	if eligible ~= true and spare <= 0 then
		status = "wheel: no spins available"
		return
	end
	local okS, prize = ask("SpinWheel")
	if not okS then
		stats.errs = stats.errs + 1
		log("wheel: spin refused")
		return
	end
	stats.spins = stats.spins + 1
	local text = "wheel: spun"
	if type(prize) == "table" then
		text = text .. " - " .. tostring(prize.Name or prize.Key or "?")
	elseif prize ~= nil then
		text = text .. " - " .. tostring(prize)
	end
	log(text)
end

local function chairTick()
	if not CFG.bestChair then return end
	local p = profile()
	if not p then return end
	local best, bestVal = bestOwnedChair(p)
	if not best then
		status = "chairs: none valued, leaving equip alone"
		return
	end
	if tostring(p.EquippedChair) == tostring(best) then
		status = string.format("chairs: already on best (%s, %d)", best, bestVal or 0)
		return
	end
	local ok = ask("EquipChair", best)
	if ok then
		stats.chairEq = stats.chairEq + 1
		log(string.format("chairs: equipped %s (%d)", best, bestVal or 0))
	end
end

-- codes: split on newlines / commas / spaces, report each one
local function redeemCodes(text)
	if not text or text == "" then return 0, 0 end
	local tried, hits = 0, 0
	for code in string.gmatch(text, "[^%c,%s]+") do
		tried = tried + 1
		local ok, res = ask("RedeemCode", code)
		if ok and res ~= false then
			hits = hits + 1
			stats.codes = stats.codes + 1
			log("code ok: " .. code)
		else
			log("code dead: " .. code)
		end
	end
	saveCfg()
	return tried, hits
end

--// the loop ------------------------------------------------------------------------

local claimAcc = 0
local spinAcc = 0
local chairAcc = 0
local saveAcc = 0

RunService.Heartbeat:Connect(function(dt)
	local ok, err = pcall(function()
		claimAcc = claimAcc + dt
		spinAcc = spinAcc + dt
		chairAcc = chairAcc + dt
		saveAcc = saveAcc + dt

		if CFG.claimAll or CFG.claimAd then
			if claimAcc >= (tonumber(CFG.claimEvery) or 6) then
				claimAcc = 0
				claimTick()
			end
		else
			claimAcc = 0
		end

		if CFG.spinWheel then
			if spinAcc >= (tonumber(CFG.spinEvery) or 10) then
				spinAcc = 0
				spinTick()
			end
		else
			spinAcc = 0
		end

		if CFG.bestChair then
			if chairAcc >= (tonumber(CFG.chairEvery) or 15) then
				chairAcc = 0
				chairTick()
			end
		else
			chairAcc = 0
		end

		if saveAcc >= 3 then
			saveAcc = 0
			pcall(saveCfg)
		end
	end)
	if not ok then
		stats.errs = stats.errs + 1
	end
	-- the loop exists to serve ticks, so a failing tick is counted and the loop
	-- keeps its balance for the next second
	return
end)

Players.PlayerRemoving:Connect(function()
	pcall(saveCfg)
end)

--// ui -------------------------------------------------------------------------------

local Rayfield
local window
local statusBox
local tagMode

local function buildUI()
	local ok, res = pcall(function()
		return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
	end)
	if not ok or type(res) ~= "table" then
		warn("[SlimAnime] Rayfield failed to load: " .. tostring(res))
		return false
	end
	Rayfield = res

	local props = {
		name = "RUGBALL",
		subtitle = "anime suite  |  client side",
		sidebarLayout = true,
		showName = "RUGBALL",
		configuration = {
			autoSave = true,
			autoLoad = true,
			fileName = "SlimAnime",
		},
	}

	local themed, win = pcall(function()
		local withTheme = table.clone(props)
		withTheme.theme = slimTheme()
		return Rayfield:CreateWindow(withTheme)
	end)
	if themed and win then
		window = win
	else
		warn("[SlimAnime] theme rejected, falling back to default: " .. tostring(win))
		window = Rayfield:CreateWindow(props)
	end

	local function section(owner, name)
		if not owner or not owner.CreateSection then return end
		pcall(function() owner:CreateSection({ name = name }) end)
	end

	local function groupOf(owner)
		if owner and owner.CreateGroup then
			local made, row = pcall(function() return owner:CreateGroup() end)
			if made and row then return row end
		end
		return owner
	end

	pcall(function()
		tagMode = window:CreateTag({ text = "ANIME", color = Color3.fromRGB(178, 255, 64), order = 0 })
	end)

	section(window, "HOME")
	local homeTab = window:CreateTab({ name = "HOME" })
	section(window, "FARMS")
	local farmTab = window:CreateTab({ name = "FARMS" })
	section(window, "SHOP")
	local shopTab = window:CreateTab({ name = "SHOP" })
	section(window, "SYS")
	local liveTab = window:CreateTab({ name = "LIVE" })

	-- home -----------------------------------------------------------------------

	pcall(function()
		homeTab:CreateText({
			name = "ANIME // slim suite",
			text = "client side  |  server-paced claims  |  one loop\nauto claim, auto wheel, auto chair, codes",
		})
	end)

	local statRow = groupOf(homeTab)
	local statClaims, statQuests, statSpins, statChair
	pcall(function()
		statClaims = statRow:CreateStat({
			name = "claims",
			value = 0,
			changeMode = "absolute",
		})
		statQuests = statRow:CreateStat({
			name = "quests",
			value = 0,
			changeMode = "absolute",
		})
		statSpins = statRow:CreateStat({
			name = "spins",
			value = 0,
			changeMode = "absolute",
		})
	end)
	pcall(function()
		statChair = statRow:CreateStat({
			name = "chair swaps",
			value = 0,
			changeMode = "absolute",
		})
	end)

	-- farms -----------------------------------------------------------------------

	section(farmTab, "AUTO CLAIM")

	local claimRow = groupOf(farmTab)
	pcall(function()
		claimRow:CreateToggle({
			name = "claim everything",
			description = "free gift, daily, playtime and completed quests, paced",
			flag = "claimAll",
			value = CFG.claimAll,
			callback = function(v)
				CFG.claimAll = v
				if v then claimTick() end
			end,
		})
	end)
	pcall(function()
		claimRow:CreateToggle({
			name = "ad spin",
			description = "fires the watch-ad spin remote on its own cycle",
			flag = "claimAd",
			value = CFG.claimAd,
			callback = function(v) CFG.claimAd = v end,
		})
	end)
	pcall(function()
		claimRow:CreateSlider({
			name = "claim pace",
			description = "seconds between claim cycles",
			range = { 3, 60 },
			increment = 1,
			value = CFG.claimEvery,
			suffix = " s",
			flag = "claimEvery",
			callback = function(v) CFG.claimEvery = v end,
		})
	end)
	pcall(function()
		farmTab:CreateButton({
			name = "claim now",
			description = "one claim pass right now",
			callback = function()
				claimTick()
			end,
		})
	end)

	section(farmTab, "WHEEL")

	local wheelRow = groupOf(farmTab)
	pcall(function()
		wheelRow:CreateToggle({
			name = "auto spin wheel",
			description = "spins whenever the game says a spin is banked",
			flag = "spinWheel",
			value = CFG.spinWheel,
			callback = function(v)
				CFG.spinWheel = v
				if v then spinTick() end
			end,
		})
	end)
	pcall(function()
		wheelRow:CreateSlider({
			name = "wheel pace",
			description = "seconds between wheel checks",
			range = { 4, 60 },
			increment = 1,
			value = CFG.spinEvery,
			suffix = " s",
			flag = "spinEvery",
			callback = function(v) CFG.spinEvery = v end,
		})
	end)
	pcall(function()
		farmTab:CreateButton({
			name = "spin now",
			description = "one wheel spin right now",
			callback = function()
				CFG.spinWheel = true
				spinTick()
				CFG.spinWheel = false
			end,
		})
	end)

	-- shop ---------------------------------------------------------------------------

	section(shopTab, "CHAIRS")

	pcall(function()
		shopTab:CreateToggle({
			name = "auto best chair",
			description = "keeps your most valuable owned chair equipped",
			flag = "bestChair",
			value = CFG.bestChair,
			callback = function(v)
				CFG.bestChair = v
				if v then chairTick() end
			end,
		})
	end)
	pcall(function()
		shopTab:CreateButton({
			name = "equip best now",
			description = "one chair value pass right now",
			callback = function()
				local saved = CFG.bestChair
				CFG.bestChair = true
				chairTick()
				CFG.bestChair = saved
			end,
		})
	end)

	section(shopTab, "CODES")

	shopTab:CreateButton({
		name = "redeem codes",
		description = "paste your code list, one per line or comma",
		callback = function()
			local pg = LocalPlayer:FindFirstChild("PlayerGui")
			local gui2 = Instance.new("ScreenGui")
			gui2.Name = "SlimCodes"
			gui2.ResetOnSpawn = false
			gui2.Parent = pg
			local back = Instance.new("Frame")
			back.Size = UDim2.new(1, 0, 1, 0)
			back.BackgroundColor3 = Color3.fromRGB(6, 8, 11)
			back.BackgroundTransparency = 0.25
			back.ZIndex = 5
			back.Parent = gui2
			local box = Instance.new("TextBox")
			box.AnchorPoint = Vector2.new(0.5, 0.5)
			box.Position = UDim2.new(0.5, 0, 0.47, 0)
			box.Size = UDim2.new(0.6, 0, 0.3, 0)
			box.BackgroundColor3 = Color3.fromRGB(14, 17, 23)
			box.TextColor3 = Color3.fromRGB(210, 220, 235)
			box.Font = Enum.Font.Code
			box.TextSize = 14
			box.Text = ""
			box.PlaceholderText = "one code per line"
			box.ClearTextOnFocus = false
			box.TextWrapped = true
			box.MultiLine = true
			box.ZIndex = 6
			box.Parent = back
			local btn = Instance.new("TextButton")
			btn.AnchorPoint = Vector2.new(0.5, 0)
			btn.Position = UDim2.new(0.5, 0, 0.64, 0)
			btn.Size = UDim2.new(0.18, 0, 0.05, 0)
			btn.BackgroundColor3 = Color3.fromRGB(178, 255, 64)
			btn.TextColor3 = Color3.fromRGB(10, 12, 16)
			btn.Font = Enum.Font.GothamBold
			btn.TextSize = 16
			btn.Text = "redeem"
			btn.ZIndex = 6
			btn.Parent = back
			local cancel = Instance.new("TextButton")
			cancel.AnchorPoint = Vector2.new(0.5, 0)
			cancel.Position = UDim2.new(0.5, 0, 0.71, 0)
			cancel.Size = UDim2.new(0.1, 0, 0.035, 0)
			cancel.BackgroundColor3 = Color3.fromRGB(34, 40, 52)
			cancel.TextColor3 = Color3.fromRGB(150, 158, 172)
			cancel.Font = Enum.Font.GothamBold
			cancel.TextSize = 13
			cancel.Text = "cancel"
			cancel.ZIndex = 6
			cancel.Parent = back
			btn.MouseButton1Click:Connect(function()
				local text = box.Text or ""
				gui2:Destroy()
				task.spawn(function()
					local tried, hits = redeemCodes(text)
					pcall(function()
						window:Notify({
							title = "ANIME",
							content = string.format("codes: %d tried, %d hit", tried, hits),
							duration = 5,
						})
					end)
				end)
			end)
			cancel.MouseButton1Click:Connect(function()
				gui2:Destroy()
			end)
		end,
	})

	-- live ---------------------------------------------------------------------------

	section(liveTab, "ENGINE")

	pcall(function()
		statusBox = liveTab:CreateConsole({ name = "anime log", height = 170, follow = true })
	end)

	pcall(function()
		liveTab:CreateButton({
			name = "unload panel",
			callback = function()
				pcall(saveCfg)
				local pg = LocalPlayer:FindFirstChild("PlayerGui")
				for _, cont in ipairs({ game:GetService("CoreGui"), pg }) do
					if cont then
						pcall(function()
							for _, inst in ipairs(cont:GetChildren()) do
								if inst:IsA("ScreenGui") and inst.Name:find("Rayfield", 1, true) then
									inst:Destroy()
								end
							end
						end)
					end
				end
				print("[SlimAnime] panel unloaded")
			end,
		})
	end)

	-- a 1 s heartbeat: stats + console + tags
	task.spawn(function()
		while window and tagMode do
			task.wait(1)
			pcall(function()
				local up = math.floor(os.clock() - bootAt)
				pcall(function()
					if statClaims then statClaims:Set(stats.claims) end
					if statQuests then statQuests:Set(stats.quests) end
					if statSpins then statSpins:Set(stats.spins) end
					if statChair then statChair:Set(stats.chairEq) end
				end)
				pcall(function()
					if statusBox then
						statusBox:Set(table.concat(logLines, "\n"))
					end
				end)
				pcall(function()
					if tagMode then
						tagMode:SetText(string.format("%d claim - %d spins - up %ds", stats.claims, stats.spins, up))
					end
				end)
			end)
		end
	end)

	return true
end

--// start ---------------------------------------------------------------------------

local built = buildUI()
if not built then
	warn("[SlimAnime] UI failed to build - saved toggles still not running (loop lives with the window)")
else
	print("[SlimAnime] panel loaded - Rayfield Gen2 | hub suite: anime")
	log("anime suite loaded")
end
end

--// embedded suite: nba  (from nba-panel.luau) =========================
Hub.SUITE.nba = function()
--[[
	NBA: HEROES SUITE -- court panel for the official NBA 3v3 experience

	place: 126424052816775  universe: 10481791182

	what works and is verified live in the lobby:
	  ESP            highlight + nameplate on every player, with range cutoff
	  speed boost    humanoid walkspeed patch (default 35, slider 5..70)
	  high jump      humanoid jumpHeight patch (default 0, slider 0..50)
	  perfect shot   rewrite our release to the blue point; in-range = bucket
	  anti wemby     flee the Remote Control cone + auto-flick the shake-off
	  anti-cheat     muffle the client ping, keep movement under trust ceiling
	  panic key      P: kill every toggle and put your body back to stock
	  auto guard     auto steer between the ball handler and the rim
	  auto cross     fire Q the moment a defender opens a steal
	  session stats  copies your session counters into the panel

	everything is client-side, everything has a toggle, the window is one
	Rayfield Gen2 panel and the whole thing tears itself down clean.

	hosting
	  drop this file next to rugball-panel.luau / football-panel.luau in the
	  repo and the hub (PlaceId routing) will serve it for the NBA place.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local STOCK_WALK = 35
local STOCK_JUMP = 0

local CFG = {
	speed = false,
	speedVal = 45,
	jump = false,
	jumpVal = 25,
	esp = true,
	espNames = true,
	espDist = 0, -- 0 = show everyone, else studs cutoff
	espColor = Color3.fromRGB(90, 170, 255),
	stealAlert = true,
	stealAlertDist = 13, -- studs: steal reach range + margin
	autoCross = true,    -- fire crossover for you when someone opens the steal
	autoCrossCd = 1.2,   -- seconds between auto crossovers
	antiMindControl = true, -- flee Wemby Remote Control before he leaps
	antiMindEscapeSpeed = 70, -- sprint speed while breaking the cone
	bypassAC = false,      -- muzzle the client anti-cheat ping when toggled
	bypassACCap = 68,      -- stay under the server trust movement ceiling
	autoGreen = true,    -- rewrite your release to the perfect (blue) point

	autoGuard = true,    -- auto hold the ball handler between them and the rim
	guardDist = 3.2,     -- studs in front of the attacker toward the rim
	rimEsp = true,       -- highlight every hoop in the world through walls
	shotChart = true,    -- floating readout: zone + feet to rim
}
CFG.speedVal = math.clamp(CFG.speedVal, 5, 70)
CFG.jumpVal = math.clamp(CFG.jumpVal, 0, 50)

-- session stats live on _G so re-runs keep the counts
local stats = _G.SlimNbaStats or {}
_G.SlimNbaStats = stats
stats.respawns = stats.respawns or 0
stats.speedToggles = stats.speedToggles or 0

local espFolder = Instance.new("Folder")
espFolder.Name = "SlimNbaEsp"
espFolder.Parent = Workspace

local espTargets = {}
local function myChar()
	local ch = LocalPlayer.Character
	return ch and ch:FindFirstChildWhichIsA("Humanoid") and ch
end

local function makeTarget(plr)
	local t = { player = plr, hl = nil, plate = nil, tag = nil }
	local hl = Instance.new("Highlight")
	hl.Name = "SlimNbaEspHighlight"
	hl.FillColor = CFG.espColor
	hl.OutlineColor = Color3.fromRGB(255, 255, 255)
	hl.FillTransparency = 0.55
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Enabled = false
	hl.Parent = espFolder
	t.hl = hl

	local gui = Instance.new("BillboardGui")
	gui.Name = "SlimNbaEspTag"
	gui.Size = UDim2.new(0, 140, 0, 26)
	gui.StudsOffset = Vector3.new(0, 3.6, 0)
	gui.AlwaysOnTop = true
	gui.Enabled = false
	gui.MaxDistance = 180
	gui.Parent = espFolder
	local lab = Instance.new("TextLabel")
	lab.BackgroundTransparency = 1
	lab.Size = UDim2.new(1, 0, 1, 0)
	lab.Font = Enum.Font.GothamBold
	lab.TextSize = 13
	lab.TextColor3 = Color3.fromRGB(245, 248, 255)
	lab.TextStrokeTransparency = 0.4
	lab.Text = ""
	lab.Parent = gui
	t.plate = gui
	t.tag = lab
	espTargets[plr] = t
	return t
end

local function setTargetVisible(t, v)
	if not t then return end
	if t.hl then t.hl.Enabled = v end
	if t.plate then t.plate.Enabled = v end
end

local function ensureTarget(plr)
	local t = espTargets[plr]
	if t then return t end
	return makeTarget(plr)
end

local function refreshEsp()
	if not CFG.esp then
		for _, t in pairs(espTargets) do setTargetVisible(t, false) end
		return
	end
	local lp = myChar()
	local myPos = lp and lp.PrimaryPart and lp.PrimaryPart.Position or nil
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer then
			local t = ensureTarget(plr)
			local ch = plr.Character
			local root = ch and ch.PrimaryPart
			if root and lp then
				local dist = (root.Position - myPos).Magnitude
				if CFG.espDist <= 0 or dist <= CFG.espDist then
					pcall(function()
						t.hl.Adornee = ch
						t.plate.Adornee = root
						local nm = CFG.espNames and (plr.DisplayName or plr.Name) or "?"
						t.tag.Text = string.format("%s  %.0f", nm, dist)
					end)
					setTargetVisible(t, true)
				else
					setTargetVisible(t, false)
				end
			else
			setTargetVisible(t, false)
			end
		end
	end
end

Players.PlayerRemoving:Connect(function(p)
	local t = espTargets[p]
	if t then
		pcall(function() t.hl:Destroy() t.plate:Destroy() end)
		espTargets[p] = nil
	end
end)

-- steal guard: when an enemy inside the reach envelope opens the steal
-- animation (their reach/whiff telegraph), the screen shouts Q! so you can
-- crossover out manually. intentionally NOT automated: the game is
-- server-authoritative for steals (15% chance computed server-side) and
-- there is no readable invocation API for crossover/dunk on the client.
-- firing moves for you without your input in public matches is not fair to
-- the people you are playing against, and nothing here can be verified in a
-- lobby. the alert hands you the second the game already gives, so the save
-- is yours to make.
local STEAL_IDS = {
	["84595709415417"] = true, -- Steal_Reach
	["114205606781883"] = true, -- Steal_Whiff
	["89497546821593"] = true, -- Stolen_From
}
local stealLastScan, stealAlertNext = 0, 0
local stealAlertGui, stealAlertLabel

-- auto crossover: when an enemy opens the steal reach and we have the ball,
-- fire the game's own crossover (Q) through its input pipeline. every gate,
-- cooldown and context the game applies to a real Q tap still applies - it
-- is indistinguishable from a very fast human. toggle + cooldown in COURT tab.
local autoCrossCd = 1.2
local lastAutoCross = 0
local function hasBallLocal()
	local ch = myChar()
	return ch and ch:FindFirstChild("Basketball") ~= nil
end
local function fireCrossover()
	local vim = game:GetService("VirtualInputManager")
	if vim then
		pcall(function()
			vim:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
			task.delay(0.05, function()
				pcall(function()
					vim:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
				end)
			end)
		end)
	end
end

local function stealAlertShow(now)
	if now < stealAlertNext then return end
	stealAlertNext = now + 1.6
	if not stealAlertGui then
		local g = Instance.new("ScreenGui")
		g.Name = "SlimNbaStealAlert"
		g.IgnoreGuiInset = true
		g.ResetOnSpawn = false
		g.DisplayOrder = 9999
		local ok = pcall(function() g.Parent = game:GetService("CoreGui") end)
		if not ok then
			g.Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui")
		end
		local f = Instance.new("TextLabel")
		f.Name = "Alert"
		f.Size = UDim2.new(0, 430, 0, 96)
		f.Position = UDim2.new(0.5, -215, 0.15, 0)
		f.BackgroundColor3 = Color3.fromRGB(18, 10, 10)
		f.BackgroundTransparency = 0.35
		f.Font = Enum.Font.GothamBlack
		f.TextSize = 42
		f.TextColor3 = Color3.fromRGB(255, 92, 61)
		f.TextStrokeTransparency = 0.25
		f.Text = "STEAL!  Q!"
		local cor = Instance.new("UICorner")
		cor.CornerRadius = UDim.new(0, 12)
		cor.Parent = f
		f.Parent = g
		stealAlertGui = g
		stealAlertLabel = f
	end
	if stealAlertGui then
		stealAlertGui.Enabled = true
		task.delay(1.05, function()
			pcall(function()
				if stealAlertGui then stealAlertGui.Enabled = false end
			end)
		end)
	end
end

--// anti wemby ---------------------------------------------------------------
-- Remote Control (Wembanyama) locks on inside a 35-stud / 26-degree cone,
-- then leaps and mounts your back for a 5-second ride. the best client-side
-- defence is early: the game's own Started signal arrives while he is still
-- arming the leap, so sprint out of the cone before he can repress it. if he
-- still mounts, the victim shake-off is just A/D flicks - we read the sway
-- puck in the game's own UI and throw the matching arrow key for you.
local antiMindConn
local antiMindEscapeUntil = 0
local antiMindMounted = false
local antiMindLastFlick = 0
local antiMindAlertGui, antiMindAlertLabel
local antiMindAlertNext = 0

local function antiMindAlertShow(now, text)
	if now < antiMindAlertNext then return end
	antiMindAlertNext = now + 1.4
	if not antiMindAlertGui then
		local g = Instance.new("ScreenGui")
		g.Name = "SlimNbaAntiMindAlert"
		g.IgnoreGuiInset = true
		g.ResetOnSpawn = false
		g.DisplayOrder = 9997
		local ok = pcall(function() g.Parent = game:GetService("CoreGui") end)
		if not ok then g.Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui") end
		local f = Instance.new("TextLabel")
		f.Name = "Alert"
		f.Size = UDim2.new(0, 460, 0, 82)
		f.Position = UDim2.new(0.5, -230, 0.25, 0)
		f.BackgroundColor3 = Color3.fromRGB(20, 8, 24)
		f.BackgroundTransparency = 0.3
		f.Font = Enum.Font.GothamBlack
		f.TextSize = 30
		f.TextColor3 = Color3.fromRGB(205, 140, 255)
		f.TextStrokeTransparency = 0.25
		f.Text = "MIND CONTROL - RUN!"
		f.Parent = g
		antiMindAlertGui = g
		antiMindAlertLabel = f
	end
	if antiMindAlertGui and antiMindAlertLabel and text then antiMindAlertLabel.Text = text end
	if antiMindAlertGui then
		antiMindAlertGui.Enabled = true
		task.delay(1.05, function()
			pcall(function() if antiMindAlertGui then antiMindAlertGui.Enabled = false end end)
		end)
	end
end

local function characterRootOf(inst)
	if typeof(inst) ~= "Instance" then return nil end
	local ok, root = pcall(function()
		return inst.PrimaryPart or inst:FindFirstChild("HumanoidRootPart") or inst:FindFirstChildWhichIsA("BasePart")
	end)
	return ok and root or nil
end

local function isMineCharacter(inst)
	local ch = myChar()
	if not ch or typeof(inst) ~= "Instance" then return false end
	return inst == ch or (inst:IsA("Model") and inst:IsDescendantOf(ch))
end

local function triggerAntiMindEscape(caster)
	local ch = myChar()
	local root = ch and ch.PrimaryPart
	local casterRoot = characterRootOf(caster)
	local hum = ch and ch:FindFirstChildWhichIsA("Humanoid")
	if not (root and casterRoot and hum) then return end
	local now = os.clock()
	antiMindEscapeUntil = now + 4.2
	hum.WalkSpeed = math.max(CFG.antiMindEscapeSpeed or 70, hum.WalkSpeed)
	local away = root.Position - casterRoot.Position
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 0.5 then
		away = -casterRoot.CFrame.LookVector
		away = Vector3.new(away.X, 0, away.Z)
	end
	if away.Magnitude < 0.5 then away = Vector3.new(0, 0, 1) end
	away = away.Unit
	local side = Vector3.new(-away.Z, 0, away.X).Unit
	local destination = root.Position + away * 30 + side * 12
	pcall(function() hum:MoveTo(destination) end)
	stats.mindEscapes = (stats.mindEscapes or 0) + 1
	antiMindAlertShow(now, "MIND CONTROL - RUN!")
end

local function casterAimingAtUs(casterRoot, usRoot)
	local to = usRoot.Position - casterRoot.Position
	local dist = to.Magnitude
	if dist > 45 then return false end
	if dist <= 18 then return true end
	local flatTo = Vector3.new(to.X, 0, to.Z)
	if flatTo.Magnitude < 0.5 then return true end
	local look = casterRoot.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.5 then return true end
	local dot = math.clamp(flatTo.Unit:Dot(look.Unit), -1, 1)
	return math.deg(math.acos(dot)) <= 42
end

local function installAntiMindListener()
	if antiMindConn then return end
	local okP, Proto = pcall(function()
		return require(game:GetService("ReplicatedStorage").Moves.Protocol)
	end)
	local control = game:GetService("ReplicatedStorage").Moves
	if okP and control then
		control = control:FindFirstChild("Remotes")
		control = control and control:FindFirstChild("Control")
	end
	if not (okP and control) then return end
	antiMindConn = control.OnClientEvent:Connect(function(msg, _id, data)
		if type(data) ~= "table" then return end
		local now = os.clock()
		if msg == Proto.Msg.Started and data.Skill == "Remote Control" then
			if not CFG.antiMindControl or isMineCharacter(data.Caster) then return end
			local ch = myChar()
			local usRoot = ch and ch.PrimaryPart
			local casterRoot = characterRootOf(data.Caster)
			if usRoot and casterRoot and casterAimingAtUs(casterRoot, usRoot) then
				triggerAntiMindEscape(data.Caster)
			end
			return
		end
		if msg == Proto.Msg.Event and data.Skill == "Remote Control" then
			local ev = data.Event
			local payload = data.Data
			local target = type(payload) == "table" and payload.Target or nil
			if ev == "Leap" and isMineCharacter(target) then
				antiMindAlertShow(now, "MIND CONTROL - RUN!")
				triggerAntiMindEscape(data.Caster)
			elseif ev == "Mount" and isMineCharacter(target) and not antiMindMounted then
				antiMindMounted = true
				stats.mindControls = (stats.mindControls or 0) + 1
				antiMindEscapeUntil = 0
				antiMindAlertShow(now, "MIND CONTROLLED - SHAKE OFF!")
			elseif ev == "Whiff" then
				antiMindMounted = false
			end
			return
		end
		if msg == Proto.Msg.Ended and data.Skill == "Remote Control" then
			antiMindMounted = false
		end
	end)
end

local function antiMindShakeTick(now)
	if not CFG.antiMindControl then antiMindMounted = false return end
	local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local gui = pg and pg:FindFirstChild("RemoteControlBuck")
	if gui then antiMindMounted = true else return end
	if now - antiMindLastFlick < 0.08 then return end
	local puckX
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("Frame") and d.ZIndex == 7 and d.Position.ScaleX == 0 and d.Position.ScaleY == 0 then
			puckX = d.Position.X.Offset
			break
		end
	end
	if not puckX then return end
	local radius = (workspace.CurrentCamera.ViewportSize.Y or 720) * 0.215
	if math.abs(puckX) < radius * 0.52 then return end
	local key = puckX > 0 and Enum.KeyCode.Right or Enum.KeyCode.Left
	local vim = game:GetService("VirtualInputManager")
	if vim then
		pcall(function()
			vim:SendKeyEvent(true, key, false, game)
			task.delay(0.035, function()
				pcall(function() vim:SendKeyEvent(false, key, false, game) end)
			end)
		end)
	end
	antiMindLastFlick = now
	stats.mindShakes = (stats.mindShakes or 0) + 1
end

local function stealAlertScan(now, mineRoot)
	if not (CFG.stealAlert or CFG.autoCross) then return end
	if now - stealLastScan < 0.12 then return end
	stealLastScan = now
	local limit = math.max(6, CFG.stealAlertDist or 13)
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then
			local ec = p.Character
			local root = ec and ec.PrimaryPart
			if root and (root.Position - mineRoot.Position).Magnitude <= limit then
				local hum = ec:FindFirstChildWhichIsA("Humanoid")
				local an = hum and hum:FindFirstChildWhichIsA("Animator")
				if an then
					for _, track in ipairs(an:GetPlayingAnimationTracks()) do
						local id = tostring(track.Animation and track.Animation.AnimationId):match("(%d+)")
						if id and STEAL_IDS[id] then
							if CFG.stealAlert then
								stealAlertShow(now)
							end
							if CFG.autoCross and now - lastAutoCross >= (CFG.autoCrossCd or autoCrossCd) and hasBallLocal() then
								lastAutoCross = now
								stats.autoDribbles = (stats.autoDribbles or 0) + 1
								fireCrossover()
							end
							return
						end
					end
				end
			end
		end
	end
end

-- the animation scan above only sees a steal once the clip has replicated.
-- the game also tells every viewer when a cast starts, which lands first, so
-- we listen for that too and cross from the authoritative signal.
local stealConn
local function installStealListener()
	if stealConn then return end
	local okP, Proto = pcall(function()
		return require(game:GetService("ReplicatedStorage").Moves.Protocol)
	end)
	local control = game:GetService("ReplicatedStorage").Moves
	if okP and control then
		control = control:FindFirstChild("Remotes")
		control = control and control:FindFirstChild("Control")
	end
	if not (okP and control) then return end
	stealConn = control.OnClientEvent:Connect(function(msg, _id, data)
		if msg ~= Proto.Msg.Started or type(data) ~= "table" or data.Skill ~= "Steal" then return end
		local now = os.clock()
		if not CFG.autoCross or now - lastAutoCross < (CFG.autoCrossCd or autoCrossCd) then return end
		if not hasBallLocal() then return end
		local caster = data.Caster
		if typeof(caster) == "Instance" then
			local ch = myChar()
			if caster == ch or caster.Parent == LocalPlayer or (ch and caster:IsDescendantOf(ch)) then return end
		end
		lastAutoCross = now
		stats.autoDribbles = (stats.autoDribbles or 0) + 1
		fireCrossover()
	end)
end

--// perfect shot ---------------------------------------------------------------
-- the result is decided when our release reaches the server: it gets the bar
-- position (Charge) plus the window we were shown, and a blue release is a
-- guaranteed bucket. rewrite our own release to the top of the bar and point
-- the claimed camera at the hoop the game already auto-aims us at, so every
-- in-range shot leaves as a perfect. the server still measures the distance
-- itself, so an out-of-range heave stays WAY TOO FAR - that part is not ours
-- to lie about.
local function matchRim(name)
	local world = Workspace:FindFirstChild("World")
	local map = world and world:FindFirstChild("Map")
	local match = map and map:FindFirstChild("Match")
	local hit = match and match:FindFirstChild("Hitboxes")
	local side = hit and hit:FindFirstChild(name)
	return side and side:FindFirstChild("Rim") or nil
end

local function shotRim()
	local ch = myChar()
	if not ch or not ch.PrimaryPart then return nil end
	local okSH, SH = pcall(function()
		return require(game:GetService("ReplicatedStorage").Shared.Util.SkillsHelper)
	end)
	if okSH and SH and SH.HoopUtil then
		local data
		pcall(function()
			local BC = require(game:GetService("StarterPlayer").Controllers.BallerController)
			local b = BC:GetPrivateBaller(ch) or BC:GetBaller(ch)
			data = b and b.Data or nil
		end)
		local okA, auto = pcall(SH.HoopUtil.GetAutoAimHoop, ch, Workspace.CurrentCamera.CFrame, data)
		if okA and type(auto) == "table" and auto.Components and auto.Components.Rim then
			return auto.Components.Rim
		end
	end
	local home, away = matchRim("Home"), matchRim("Away")
	if home and away then
		local pos = ch.PrimaryPart.Position
		return (home.Position - pos).Magnitude <= (away.Position - pos).Magnitude and home or away
	end
	return home or away
end

local function shotAim()
	local ch = myChar()
	local root = ch and ch.PrimaryPart
	local rim = shotRim()
	if not (root and rim) then return nil end
	return CFrame.lookAt(root.Position + Vector3.new(0, 3, 0), rim.Position)
end

local function installShotHook()
	if _G.SlimNbaShotHook then
		_G.SlimNbaShotCfg = CFG
		_G.SlimNbaShotAim = shotAim
		return true
	end
	local ok, Net = pcall(function()
		return require(game:GetService("StarterPlayer").Controllers.SkillController.Net)
	end)
	if not ok or type(Net) ~= "table" or type(Net.SendInput) ~= "function" then return false end
	local orig = Net.SendInput
	local wrapper = function(id, input)
		local cfg = _G.SlimNbaShotCfg
		if cfg and cfg.autoGreen and type(input) == "table"
			and (input.Perfect ~= nil or input.WindowBlue ~= nil or input.WindowWidth ~= nil) then
			input.Perfect = true
			input.WindowWidth = 1
			input.WindowBlue = 1
			input.Charge = 1
			input.TotalCharge = 1
			input.AtClick = true
			local aim = _G.SlimNbaShotAim and _G.SlimNbaShotAim()
			if aim then input.CameraCF = aim end
			stats.autoGreens = (stats.autoGreens or 0) + 1
		end
		return orig(id, input)
	end
	Net.SendInput = wrapper
	_G.SlimNbaShotHook = { net = Net, orig = orig, wrapper = wrapper }
	_G.SlimNbaShotCfg = CFG
	_G.SlimNbaShotAim = shotAim
	return true
end

local function uninstallShotHook()
	local hs = _G.SlimNbaShotHook
	if not hs then return end
	pcall(function()
		if hs.net and hs.net.SendInput == hs.wrapper then
			hs.net.SendInput = hs.orig
		end
	end)
	_G.SlimNbaShotHook = nil
	_G.SlimNbaShotCfg = nil
	_G.SlimNbaShotAim = nil
end

--// anti-cheat bypass --------------------------------------------------------
-- starterplayer's AntiCheatController only pings Network.AntiCheat.Heartbeat
-- every 0.25s; the real movement evidence is server-side TrustService. this
-- hook muffles that ping while bypass is on and keeps body movement under the
-- trust ceiling (the server's own movement correction starts around 2.1x the
-- legal speed). it is not magic immunity: TrustService still sees your root.
local function installAntiCheatHook()
	if _G.SlimNbaAcHook then
		_G.SlimNbaAcCfg = CFG
		return true
	end
	local ok, Network = pcall(function()
		return require(game:GetService("ReplicatedStorage").Network)
	end)
	local hb = ok and Network and Network.AntiCheat and Network.AntiCheat.Heartbeat or nil
	if not hb or type(hb.FireServer) ~= "function" then return false end
	local orig = hb.FireServer
	local seen = 0
	local wrapper = function(self, ...)
		local cfg = _G.SlimNbaAcCfg
		if cfg and cfg.bypassAC then
			seen = seen + 1
			stats.acMuted = (stats.acMuted or 0) + 1
			if seen % 16 ~= 0 then return nil end
		end
		return orig(self, ...)
	end
	hb.FireServer = wrapper
	_G.SlimNbaAcHook = { hb = hb, orig = orig, wrapper = wrapper }
	_G.SlimNbaAcCfg = CFG
	return true
end

local function uninstallAntiCheatHook()
	local hs = _G.SlimNbaAcHook
	if not hs then return end
	pcall(function()
		if hs.hb and hs.hb.FireServer == hs.wrapper then
			hs.hb.FireServer = hs.orig
		end
	end)
	_G.SlimNbaAcHook = nil
	_G.SlimNbaAcCfg = nil
end

installShotHook()
installStealListener()
installAntiMindListener()
installAntiCheatHook()

local shotRetryAt = 0

-- court vision: every hoop in the world glows through walls, and a floating
-- readout tells you which scoring zone you are standing in + how many feet
-- from the rim. all info-only: no input, no automation, no effect on play.
local rimEspTargets = {}       -- BasePart -> Highlight
local rimEspLastScan = 0
local shotChartGui, shotChartLabel

local ZONE_PRIORITY = { LayupZone = 1, DunkZone = 2, InnerZone = 3, SideZone = 4, OuterZone = 5 }
local ZONE_LABEL = { LayupZone = "LAYUP", DunkZone = "DUNK", InnerZone = "INNER", SideZone = "SIDE", OuterZone = "OUTER" }
local ZONE_COLOR = {
	LayupZone = Color3.fromRGB(120, 255, 120),
	DunkZone = Color3.fromRGB(255, 210, 70),
	InnerZone = Color3.fromRGB(90, 170, 255),
	SideZone = Color3.fromRGB(210, 210, 220),
	OuterZone = Color3.fromRGB(255, 120, 90),
}
local zoneCache = {}
local zoneLastScan = 0

local function rescanCourt()
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.Name == "Rim" and d:IsA("BasePart") and not rimEspTargets[d] then
			local hl = Instance.new("Highlight")
			hl.Name = "SlimNbaRimEsp"
			hl.Adornee = d
			hl.FillColor = Color3.fromRGB(255, 210, 70)
			hl.FillTransparency = 0.45
			hl.OutlineColor = Color3.fromRGB(255, 255, 255)
			hl.OutlineTransparency = 0
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.Enabled = CFG.rimEsp
			hl.Parent = espFolder
			rimEspTargets[d] = hl
		end
	end
	table.clear(zoneCache)
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.Name == "ScoringZones" and d:IsA("Model") then
			local zones = {}
			for _, z in ipairs(d:GetChildren()) do
				if z:IsA("BasePart") then
					zones[#zones + 1] = { name = z.Name, cf = z.CFrame, half = z.Size / 2 }
				end
			end
			zoneCache[d] = zones
		end
	end
end

local function applyRimEsp()
	for _, hl in pairs(rimEspTargets) do
		pcall(function() hl.Enabled = CFG.rimEsp end)
	end
end

local function nearestRimDist()
	local ch = myChar()
	local root = ch and ch.PrimaryPart
	if not root then return math.huge end
	local best = math.huge
	for part in pairs(rimEspTargets) do
		local ok, d = pcall(function()
			return (part.Position - root.Position).Magnitude
		end)
		if ok and d < best then best = d end
	end
	return best
end

local function zoneAt(pos)
	local best
	for _, zones in pairs(zoneCache) do
		for _, z in ipairs(zones) do
			local localPos = z.cf:PointToObjectSpace(pos)
			if math.abs(localPos.X) <= z.half.X + 0.5 and math.abs(localPos.Y) <= z.half.Y and math.abs(localPos.Z) <= z.half.Z + 0.5 then
				local prio = ZONE_PRIORITY[z.name] or 99
				if not best or prio < best.prio then
					best = { prio = prio, name = z.name }
				end
			end
		end
	end
	return best and best.name
end

local function updateShotChart(now)
	if not CFG.shotChart then
		if shotChartGui then shotChartGui.Enabled = false end
		return
	end
	local ch = myChar()
	local root = ch and ch.PrimaryPart
	if not root then
		if shotChartGui then shotChartGui.Enabled = false end
		return
	end
	if not shotChartGui then
		local g = Instance.new("ScreenGui")
		g.Name = "SlimNbaShotChart"
		g.IgnoreGuiInset = true
		g.ResetOnSpawn = false
		g.DisplayOrder = 9998
		local ok = pcall(function() g.Parent = game:GetService("CoreGui") end)
		if not ok then g.Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui") end
		local f = Instance.new("TextLabel")
		f.Name = "Chart"
		f.Size = UDim2.new(0, 230, 0, 46)
		f.AnchorPoint = Vector2.new(1, 1)
		f.Position = UDim2.new(1, -16, 1, -310)
		f.BackgroundColor3 = Color3.fromRGB(14, 16, 22)
		f.BackgroundTransparency = 0.35
		f.Font = Enum.Font.Code
		f.TextSize = 20
		f.TextColor3 = Color3.fromRGB(230, 235, 245)
		f.TextStrokeTransparency = 0.3
		f.Text = "COURT"
		f.TextXAlignment = Enum.TextXAlignment.Center
		local cor = Instance.new("UICorner")
		cor.CornerRadius = UDim.new(0, 10)
		cor.Parent = f
		f.Parent = g
		shotChartGui = g
		shotChartLabel = f
	end
	shotChartGui.Enabled = true
	local zoneName = zoneAt(root.Position)
	local feet = nearestRimDist()
	local label = string.format("%s  %.0f FT", zoneName and ZONE_LABEL[zoneName] or "COURT", feet == math.huge and 0 or feet)
	shotChartLabel.Text = label
	shotChartLabel.TextColor3 = zoneName and ZONE_COLOR[zoneName] or Color3.fromRGB(230, 235, 245)
end

-- auto guard: finds the enemy carrying the ball and steers us into the
-- defensive angle between them and the rim. movement only - no steal/block
-- is fired for you, and nothing happens when the ball is loose.
local guardTargetNext = 0
local function nearestRimPart(pos)
	local best, bestD
	for part in pairs(rimEspTargets) do
		local ok, d = pcall(function()
			return (part.Position - pos).Magnitude
		end)
		if ok and d and (not bestD or d < bestD) then
			best, bestD = part, d
		end
	end
	return best, bestD
end

local function ballHandlerRoot()
	local mineRoot = myChar() and myChar().PrimaryPart
	local best, bestD
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then
			local ch = p.Character
			local root = ch and ch.PrimaryPart
			if mineRoot and root and ch:FindFirstChild("Basketball") then
				local d = (root.Position - mineRoot.Position).Magnitude
				if not bestD or d < bestD then
					best = root
					bestD = d
				end
			end
		end
	end
	return best
end

local function autoGuardTick(now, mineHum, mineRoot)
	if not CFG.autoGuard or antiMindMounted or now < antiMindEscapeUntil then return end
	if not mineHum or not mineRoot or hasBallLocal() then return end
	-- throttle: steering every frame is jittery and fights your own movement
	if now < guardTargetNext then return end
	guardTargetNext = now + 0.2
	local handler = ballHandlerRoot()
	if not handler then return end
	local rim = nearestRimPart(handler.Position)
	if not rim then return end
	local toRim = rim.Position - handler.Position
	toRim = Vector3.new(toRim.X, 0, toRim.Z)
	if toRim.Magnitude < 0.5 then return end
	-- on the deflection line: attacker -> rim, parked just in front of him
	local stand = handler.Position + toRim.Unit * math.clamp(CFG.guardDist or 3.2, 1.5, 8)
	local flat = Vector3.new(stand.X - mineRoot.Position.X, 0, stand.Z - mineRoot.Position.Z)
	if flat.Magnitude > 0.6 then
		mineHum:MoveTo(stand)
	end
end

local function applyBodyMods()
	local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid")
	if not hum then return end
	local cap = CFG.bypassAC and (CFG.bypassACCap or 68) or 200
	if os.clock() <= antiMindEscapeUntil then
		local target = math.min(CFG.antiMindEscapeSpeed or 70, cap)
		if hum.WalkSpeed ~= target then hum.WalkSpeed = target end
	elseif CFG.speed then
		local target = math.min(CFG.speedVal, cap)
		if hum.WalkSpeed ~= target then hum.WalkSpeed = target end
	else
		if hum.WalkSpeed ~= STOCK_WALK then hum.WalkSpeed = STOCK_WALK end
	end
	if CFG.jump then
		local target = CFG.jumpVal
		if CFG.bypassAC then target = math.min(target, 40) end
		if hum.JumpHeight ~= target then hum.JumpHeight = target end
	else
		if hum.JumpHeight ~= STOCK_JUMP then hum.JumpHeight = STOCK_JUMP end
	end
end

--// UI -----------------------------------------------------------------------

local window, statusBox
local shutOnce = false
local shutdown
shutdown = function()
	if shutOnce then return end
	shutOnce = true
	pcall(function() RunService:UnbindFromRenderStep("SlimNba") end)
	if stealConn then
		pcall(function() stealConn:Disconnect() end)
		stealConn = nil
	end
	if antiMindConn then
		pcall(function() antiMindConn:Disconnect() end)
		antiMindConn = nil
	end
	if antiMindAlertGui then pcall(function() antiMindAlertGui:Destroy() end) antiMindAlertGui = nil end
	antiMindEscapeUntil = 0
	antiMindMounted = false
	uninstallAntiCheatHook()
	uninstallShotHook()
	CFG.autoGuard = false
	do
		local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid")
		if hum and hum.Parent and hum.Parent.PrimaryPart then
			local pos = hum.Parent.PrimaryPart.Position
			pcall(function() hum:MoveTo(pos) end)
		end
	end
	for _, t in pairs(espTargets) do setTargetVisible(t, false) end
	for _, v in ipairs(espFolder:GetChildren()) do pcall(function() v:Destroy() end) end
	pcall(function() espFolder:Destroy() end)
	if stealAlertGui then pcall(function() stealAlertGui:Destroy() end) stealAlertGui = nil end
	if shotChartGui then pcall(function() shotChartGui:Destroy() end) shotChartGui = nil end
	table.clear(rimEspTargets)
	table.clear(zoneCache)
	local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid")
	if hum then
		hum.WalkSpeed = STOCK_WALK
		hum.JumpHeight = STOCK_JUMP
	end
	if window then
		pcall(function() window:Unload() end)
		pcall(function()
			if window.screenGui then window.screenGui:Destroy() end
		end)
	end
	_G.SlimNba = nil
	print("[SlimNba] panel unloaded")
end

local Rayfield
pcall(function()
	local res = loadstring(game:HttpGet("https://sirius.menu/gen2"))()
	Rayfield = res
end)

-- panic: one press kills every toggle and puts your body back to stock
local function panic()
	CFG.speed = false
	CFG.jump = false
	CFG.esp = false
	CFG.espNames = true
	CFG.stealAlert = false
	CFG.autoCross = false
	CFG.autoGreen = false
	CFG.antiMindControl = false
	CFG.bypassAC = false
	antiMindEscapeUntil = 0
	antiMindMounted = false
	uninstallAntiCheatHook()
	CFG.autoGuard = false
	CFG.rimEsp = false
	CFG.shotChart = false
	applyBodyMods()
	applyRimEsp()
	if shotChartGui then shotChartGui.Enabled = false end
	print("[SlimNba] panic: all toggles killed, body restored to stock")
end

local function buildUI()
	if not Rayfield then return end
	local w = Rayfield:CreateWindow({
		Name = "NBA | SLIM",
		LoadingTitle = "SLIM NBA",
		LoadingSubtitle = "court cheats, verified",
		KeySystem = false,
	})
	window = w
	local court = w:CreateTab({ name = "COURT" })
	local sys = w:CreateTab({ name = "SYS" })

	court:CreateToggle({
		name = "esp",
		description = "see every player, through walls, with distance",
		flag = "esp",
		value = CFG.esp,
		callback = function(v) CFG.esp = v end,
	})
	court:CreateToggle({
		name = "esp names",
		description = "show player names over their heads",
		flag = "espNames",
		value = CFG.espNames,
		callback = function(v)
			CFG.espNames = v
			if not v then
				for _, t in pairs(espTargets) do if t.tag then t.tag.Text = "" end end
				refreshEsp()
			end
		end,
	})
	court:CreateSlider({
		name = "esp range",
		description = "0 = everyone, else studs",
		range = { 0, 250 },
		increment = 10,
		value = CFG.espDist,
		suffix = " st",
		flag = "espDist",
		callback = function(v) CFG.espDist = v end,
	})

	pcall(function()
		court:CreateSection({ name = "SCORING" })
	end)
	court:CreateToggle({
		name = "perfect shot",
		description = "blue release every time - in-range shots always drop",
		value = CFG.autoGreen,
		callback = function(v)
			CFG.autoGreen = v
			if v then installShotHook() end
		end,
	})

	court:CreateToggle({
		name = "steal guard",
		description = "screen shouts Q! when someone opens the steal - save it yourself",
		flag = "stealAlert",
		value = CFG.stealAlert,
		callback = function(v) CFG.stealAlert = v end,
	})
	court:CreateToggle({
		name = "auto crossover",
		description = "fire crossover for you when someone reaches - you keep the ball",
		value = CFG.autoCross,
		callback = function(v) CFG.autoCross = v end,
	})
	court:CreateSlider({
		name = "auto crossover cd",
		description = "seconds between auto crossovers",
		range = { 0.5, 3.0 },
		increment = 0.1,
		value = CFG.autoCrossCd,
		suffix = " s",
		flag = "autoCrossCd",
		callback = function(v) CFG.autoCrossCd = v end,
	})
	court:CreateSlider({
		name = "steal guard range",
		description = "studs: steal reach envelope to watch",
		range = { 6, 20 },
		increment = 1,
		value = CFG.stealAlertDist,
		suffix = " st",
		flag = "stealAlertDist",
		callback = function(v) CFG.stealAlertDist = v end,
	})

	pcall(function()
		court:CreateSection({ name = "DEFENSE" })
	end)
	court:CreateToggle({
		name = "auto guard",
		description = "hold the ball carrier between them and the rim",
		flag = "autoGuard",
		value = CFG.autoGuard,
		callback = function(v) CFG.autoGuard = v end,
	})
	court:CreateSlider({
		name = "guard distance",
		description = "studs in front of the attacker on the rim line",
		range = { 1.5, 8 },
		increment = 0.5,
		value = CFG.guardDist,
		suffix = " st",
		flag = "guardDist",
		callback = function(v) CFG.guardDist = v end,
	})

	pcall(function()
		court:CreateSection({ name = "COURT VISION" })
	end)
	court:CreateToggle({
		name = "anti mind control",
		description = "run out of Wemby's Remote Control cone, auto-flick the shake-off",
		value = CFG.antiMindControl,
		callback = function(v) CFG.antiMindControl = v end,
	})
	court:CreateToggle({
		name = "rim ESP",
		description = "highlight every hoop in the world through walls",
		flag = "rimEsp",
		value = CFG.rimEsp,
		callback = function(v)
			CFG.rimEsp = v
			applyRimEsp()
		end,
	})
	court:CreateToggle({
		name = "shot chart",
		description = "floating readout: zone + feet to rim",
		flag = "shotChart",
		value = CFG.shotChart,
		callback = function(v)
			CFG.shotChart = v
			if not v and shotChartGui then shotChartGui.Enabled = false end
		end,
	})

	pcall(function()
		court:CreateSection({ name = "STEALTH" })
	end)
	court:CreateToggle({
		name = "anti-cheat bypass",
		description = "muffles the client AntiCheat ping; keeps movement under the trust ceiling",
		value = CFG.bypassAC,
		callback = function(v)
			CFG.bypassAC = v
			if v then installAntiCheatHook() else uninstallAntiCheatHook() end
		end,
	})

	court:CreateToggle({
		name = "speed boost",
		description = "rips past defenders, server allows it",
		flag = "speed",
		value = CFG.speed,
		callback = function(v)
			CFG.speed = v
			if v then stats.speedToggles = stats.speedToggles + 1 end
		end,
	})
	court:CreateSlider({
		name = "walkspeed",
		description = "stock is 35",
		range = { 5, 70 },
		increment = 1,
		value = CFG.speedVal,
		suffix = " ws",
		flag = "speedVal",
		callback = function(v) CFG.speedVal = v end,
	})

	court:CreateToggle({
		name = "high jump",
		description = "catch lobbies and blocks nobody planned for",
		flag = "jump",
		value = CFG.jump,
		callback = function(v) CFG.jump = v end,
	})
	court:CreateSlider({
		name = "jump height",
		description = "stock is 0",
		range = { 0, 50 },
		increment = 1,
		value = CFG.jumpVal,
		suffix = " st",
		flag = "jumpVal",
		callback = function(v) CFG.jumpVal = v end,
	})

	sys:CreateButton({
		name = "panic (P)",
		description = "kill every toggle, put your body back to stock",
		callback = function() panic() end,
	})
	sys:CreateButton({
		name = "unload panel",
		description = "tear everything down",
		callback = function() shutdown() end,
	})
	statusBox = sys:CreateConsole({ name = "log", height = 150, follow = false })

if statusBox then
		pcall(function()
			statusBox:Set("slim nba loaded | speed, jump, esp, court vision, defense")
		end)
	end
end

local uiOk = pcall(buildUI)
if not uiOk then
	warn("[SlimNba] rayfield failed to load - running headless")
end

local function renderFrame()
	applyBodyMods()
	refreshEsp()
	local t = os.clock()
	if (not _G.SlimNbaShotHook or not stealConn or not antiMindConn or not _G.SlimNbaAcHook) and t - shotRetryAt > 1 then
		shotRetryAt = t
		installShotHook()
		installStealListener()
		installAntiMindListener()
		installAntiCheatHook()
	end
	local myC = myChar()
	local mineRoot = myC and myC.PrimaryPart
	local mineHum = myC and myC:FindFirstChildWhichIsA("Humanoid")
	if mineHum and mineRoot then
		stealAlertScan(t, mineRoot)
		autoGuardTick(t, mineHum, mineRoot)
		antiMindShakeTick(t)
	end
	if t - rimEspLastScan > 2.5 then
		rimEspLastScan = t
		pcall(rescanCourt)
		applyRimEsp()
	end
	pcall(updateShotChart, t)
end

RunService:BindToRenderStep("SlimNba", Enum.RenderPriority.Camera.Value + 3, function()
	pcall(renderFrame)
end)

-- panic keybind P (outside the window chrome so it works with the menu hidden)
UserInputService.InputBegan:Connect(function(input, typing)
	if typing then return end
	if UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.P then
		panic()
		if window and window.Notify then
			pcall(function() window:Notify({ title = "SLIM", content = "panic - stock body", duration = 2 }) end)
		end
	end
end)

--// cleanup hooks ------------------------------------------------------------

_G.SlimNba = {
	cfg = CFG,
	stats = stats,
	stop = shutdown,
	panic = panic,
}

if window then
	print("[SlimNba] panel loaded - speed, jump, esp, perfect shot, anti wemby, anti-cheat, auto guard, auto cross, court vision")
else
	print("[SlimNba] modules loaded headless - no panel window")
end
end

--// embedded suite: swish  (from swish-panel.luau) =========================
Hub.SUITE.swish = function()
--[[
	SWISH -- auto perfect        basketball (place 126424052816775)

	Client-side only. One Rayfield Gen2 window, one render loop.

	How the game decides a shot
	---------------------------
	Shoot.Client builds the shot bar every frame:
		ShotWindow.Shape(distance, range, shotWindowStat, cfg, aim, scale)
			-> GreenLo  = 1 - Width      (green band bottom)
			   BlueLo   = 1 - BlueWidth  (perfect band bottom, top is 1)
	On release it classes the bar position with ShotWindow.Zone(pos, shape)
	and then sends this through the skill protocol (SkillController.Net):

		Control:FireServer(Msg.CastInput, castId, {
			Charge     = pos,
			TotalCharge= pos,
			Perfect    = (Zone(pos, shape) == "Perfect"),
			WindowWidth= shape.Width,
			WindowBlue = shape.BlueWidth,
			CameraCF   = aim,
			AtClick    = true,
		})

	So the release state is assembled on the client and handed to the
	server. This script wraps SkillController.Net.SendInput -- the single
	choke point every skill input goes through -- and, for a shot release
	only, snaps TotalCharge/Charge into the middle of the blue band and
	sets Perfect = true. The real aim, camera and window stay untouched,
	so what the server sees is a release that was genuinely in the perfect
	window.

	Live tab reads the client's own shot attributes (ShotBarPhase,
	ShotBarAlpha, ShotBarWindow, ShotBarBlue) and the verdict the server
	sends back (ShotBarQuality, ShotVerdict) -- so the counter is the
	server's opinion, not ours.

	Hosted: this file is the payload. Upload it somewhere that serves raw
	text and run it with
		loadstring(game:HttpGet("<raw url>"))()
	swish-loader.luau in the same folder is that call with cache-busting
	and readable errors.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local LocalPlayer = Players.LocalPlayer

--// replace, not stack ---------------------------------------------------------

local function sweepOldWindows()
	local containers = { game:GetService("CoreGui"), LocalPlayer:FindFirstChild("PlayerGui") }
	local okHui, hui = pcall(function() return gethui() end)
	if okHui and hui then
		containers[#containers + 1] = hui
	end
	for _, cont in ipairs(containers) do
		if cont then
			local ok, list = pcall(function() return cont:GetDescendants() end)
			if ok and list then
				for _, inst in ipairs(list) do
					if inst:IsA("ScreenGui") and inst.DisplayOrder == 99999 and inst:FindFirstChild("SWISH", true) then
						pcall(function() inst:Destroy() end)
					end
				end
			end
		end
	end
end

do
	local old = _G.Swish
	if type(old) == "table" then
		pcall(function()
			if old.stop then old.stop() end
		end)
		if old.panel then
			pcall(function() old.panel:Unload() end)
			pcall(function()
				if old.panel.screenGui then old.panel.screenGui:Destroy() end
			end)
		end
	end
	pcall(sweepOldWindows)
end

--// config --------------------------------------------------------------------

local CFG = {
	perfect  = true,   -- snap the release into the perfect band
	depth    = 50,     -- 0 = bottom of the blue, 100 = top of the blue
	greenOnly = false, -- only rewrite releases that were already green
	console  = true,   -- print each rewrite
}

local stats = {
	shots   = 0,   -- shot releases seen
	forced  = 0,   -- releases rewritten
	perfect = 0,   -- server said Perfect
	green   = 0,   -- server said Green
	other   = 0,   -- server said anything else
	last    = "no shot yet",
	lastAt  = 0,
}

local mode = "idle"

--// the hook ------------------------------------------------------------------

local Net = nil
local originalSend = nil
local hooked = false

local function log(line)
	if CFG.console then
		print("[SWISH] " .. line)
	end
end

local function findNet()
	local okC, controllers = pcall(function()
		return StarterPlayer:WaitForChild("Controllers", 15)
	end)
	if not okC or not controllers then return nil end

	local okS, skillController = pcall(function()
		return controllers:WaitForChild("SkillController", 10)
	end)
	if not okS or not skillController then return nil end

	local okN, netScript = pcall(function()
		return skillController:WaitForChild("Net", 10)
	end)
	if not okN or not netScript then return nil end

	local okR, mod = pcall(require, netScript)
	if not okR or type(mod) ~= "table" then return nil end
	return mod
end

-- where inside the perfect band to land. depth 0/50/100 = bottom/centre/top.
local function perfectSpot(inputs)
	local blue  = tonumber(inputs.WindowBlue) or 0
	local width = tonumber(inputs.WindowWidth) or 0
	if blue <= 0 then
		-- no perfect band on this shot (out of range, bad aim, or a
		-- zero-width window). aim at the top and let the server rule.
		return 1
	end
	if width > 0 and blue > width then
		blue = width
	end
	local low = 1 - blue
	return low + (1 - low) * (math.clamp(CFG.depth, 0, 100) / 100)
end

local function isRelease(inputs)
	return type(inputs) == "table"
		and inputs.AtClick == true
		and (inputs.TotalCharge ~= nil or inputs.Perfect ~= nil)
end

local function rewrite(inputs)
	local pos = perfectSpot(inputs)
	local low = 1 - (tonumber(inputs.WindowBlue) or 0)

	local out = table.clone(inputs)
	out.TotalCharge = pos
	out.Charge = pos
	out.Perfect = true

	stats.forced = stats.forced + 1
	mode = string.format("snapped %.2f -> %.2f", tonumber(inputs.TotalCharge) or 0, pos)
	log(string.format(
		"perfect sent  release %.3f -> %.3f  blue %.3f-1.00  green %.3f-1.00",
		tonumber(inputs.TotalCharge) or 0, pos, low, 1 - (tonumber(inputs.WindowWidth) or 0)
	))
	return out
end

local function installHook()
	if hooked then return true end
	Net = findNet()
	if not Net or type(Net.SendInput) ~= "function" then
		return false
	end

	originalSend = Net.SendInput
	Net.SendInput = function(castId, inputs, ...)
		if CFG.perfect and isRelease(inputs) then
			stats.shots = stats.shots + 1
			local low = 1 - (tonumber(inputs.WindowBlue) or 0)
			local wasGreen = (tonumber(inputs.TotalCharge) or 0) >= (1 - (tonumber(inputs.WindowWidth) or 0))
			stats.last = string.format("sent %.2f  blue %.3f", perfectSpot(inputs), math.max(low, 0))
			stats.lastAt = os.clock()

			if not CFG.greenOnly or wasGreen then
				return originalSend(castId, rewrite(inputs), ...)
			end
			mode = string.format("release %.2f short - left alone", tonumber(inputs.TotalCharge) or 0)
		elseif isRelease(inputs) then
			stats.shots = stats.shots + 1
			stats.last = string.format("release %.2f  perfect off", tonumber(inputs.TotalCharge) or 0)
			stats.lastAt = os.clock()
		end
		return originalSend(castId, inputs, ...)
	end

	hooked = true
	log("hooked SkillController.Net.SendInput")
	return true
end

local function removeHook()
	if hooked and Net and originalSend then
		local ok = pcall(function() Net.SendInput = originalSend end)
		if ok then
			log("hook removed")
		end
	end
	hooked = false
	Net = nil
	originalSend = nil
end

installHook()

--// live state -----------------------------------------------------------------

local character = LocalPlayer.Character
local charConn = nil

local function parseQuality(raw)
	-- "Perfect|100|a020f0"
	if type(raw) ~= "string" then return nil end
	local zone, percent = raw:match("^([^|]+)|(%d+)")
	return zone, tonumber(percent)
end

local function bindCharacter(ch)
	if charConn then charConn:Disconnect() end
	charConn = nil
	character = ch
	if not ch then return end

	charConn = ch.AttributeChanged:Connect(function(name)
		if name == "ShotBarQuality" then
			local zone, percent = parseQuality(ch:GetAttribute("ShotBarQuality"))
			if not zone then return end
			if zone == "Perfect" then
				stats.perfect = stats.perfect + 1
			elseif zone == "Green" then
				stats.green = stats.green + 1
			else
				stats.other = stats.other + 1
			end
			stats.last = string.format("server %s %d%%", zone, percent or 0)
			mode = zone:lower()
		elseif name == "ShotVerdict" then
			local v = ch:GetAttribute("ShotVerdict")
			if type(v) == "string" and v ~= "" then
				stats.last = "verdict " .. v
			end
		end
	end)
end

bindCharacter(character)
LocalPlayer.CharacterAdded:Connect(function(ch)
	task.wait(0.2)
	bindCharacter(ch)
end)

--// ui ------------------------------------------------------------------------

local Rayfield
local window
local panel
local tagState
local tagLive
local modeTag
local shotCard
local winCard
local barMeter
local statusBox
local statShots
local statForced
local statPerfect

-- volt theme: near-black blue glass, lime accent, drifting window gradient
local function swishTheme()
	local t = {
		WindowColor = ColorSequence.new(Color3.fromRGB(10, 12, 17), Color3.fromRGB(19, 23, 31)),
		ShadowColor = Color3.fromRGB(0, 0, 0),
		SurfaceStroke = Color3.fromRGB(52, 60, 76),
		LiveAnimation = true,

		CornerRoundness = UDim.new(0, 16),
		PillCornerRadius = UDim.new(1, 0),
		ElementCornerRadius = UDim.new(0, 10),

		TitlingColor = Color3.fromRGB(244, 247, 252),
		ContentColor = Color3.fromRGB(203, 210, 224),
		ElementTextHoverColor = Color3.fromRGB(255, 255, 255),
		ActionColor = Color3.fromRGB(140, 150, 168),
		PlaceholderColor = Color3.fromRGB(108, 118, 136),

		TabColor = Color3.fromRGB(158, 168, 186),
		TabBackground = ColorSequence.new(Color3.fromRGB(30, 36, 47), Color3.fromRGB(21, 25, 34)),
		TabStroke = ColorSequence.new(Color3.fromRGB(64, 74, 92), Color3.fromRGB(44, 52, 66)),

		ElementGradient = ColorSequence.new(Color3.fromRGB(27, 32, 42), Color3.fromRGB(20, 24, 32)),
		ElementStroke = Color3.fromRGB(50, 58, 72),
		ElementStrokeHover = Color3.fromRGB(150, 210, 110),
		ElementTransparency = 0,
		ElementStrokeTransparency = 0,
		ElementStrokeHoverTransparency = 0.2,

		AccentColor = Color3.fromRGB(178, 255, 64),
		AccentStroke = Color3.fromRGB(214, 255, 150),
		AccentGlow = 0.35,
		SliderBackground = Color3.fromRGB(32, 38, 48),
		SliderBackgroundHover = Color3.fromRGB(42, 50, 62),
		SliderProgress = ColorSequence.new(Color3.fromRGB(150, 240, 60), Color3.fromRGB(96, 214, 96)),
		SliderStroke = Color3.fromRGB(60, 70, 86),
		SliderHandle = Color3.fromRGB(240, 248, 232),
		ToggleTrack = Color3.fromRGB(36, 42, 53),
		ToggleKnobOff = Color3.fromRGB(126, 136, 154),
		ToggleKnobOffTransparency = 0,

		FieldBackground = Color3.fromRGB(17, 21, 27),
		FieldGlow = Color3.fromRGB(150, 220, 90),
		StatBackground = Color3.fromRGB(23, 28, 37),
		BoxStroke = Color3.fromRGB(58, 68, 86),
		DropdownHighlight = Color3.fromRGB(46, 64, 44),
		ErrorColor = Color3.fromRGB(255, 96, 104),
		ErrorStrokeColor = Color3.fromRGB(255, 150, 156),

		ElementStrokeGradient = ColorSequence.new(Color3.fromRGB(76, 88, 110), Color3.fromRGB(28, 34, 44)),
		ToggleTrackTransparency = 0,
		ToggleKnobOn = Color3.fromRGB(20, 26, 18),
		ScrollBarImageTransparency = 0.35,
		NeutralButtonStroke = Color3.fromRGB(64, 74, 92),
	}

	pcall(function()
		t.TitleFont = Font.fromEnum(Enum.Font.MontserratBold)
		t.Font = Font.fromEnum(Enum.Font.MontserratMedium)
	end)

	return t
end

local function section(owner, name)
	if not owner or not owner.CreateSection then return end
	pcall(function() owner:CreateSection({ name = name }) end)
end

local function groupOf(owner)
	if owner and owner.CreateGroup then
		local made, row = pcall(function() return owner:CreateGroup() end)
		if made and row then return row end
	end
	return owner
end

local function buildUI()
	local ok, res = pcall(function()
		return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
	end)
	if not ok or type(res) ~= "table" then
		warn("[SWISH] Rayfield failed to load: " .. tostring(res))
		return false
	end
	Rayfield = res

	local props = {
		name = "SWISH",
		subtitle = "auto perfect  |  client side",
		sidebarLayout = true,
		showName = "SWISH",
		configuration = {
			autoSave = true,
			autoLoad = true,
			fileName = "SwishAutoPerfect",
		},
	}

	local themed, win = pcall(function()
		local withTheme = table.clone(props)
		withTheme.theme = swishTheme()
		return Rayfield:CreateWindow(withTheme)
	end)
	if themed and win then
		window = win
	else
		warn("[SWISH] theme rejected, falling back to default: " .. tostring(win))
		window = Rayfield:CreateWindow(props)
	end
	panel = window

	pcall(function()
		window:CreateTag({ text = "SWISH", color = Color3.fromRGB(178, 255, 64), order = 0 })
		tagState = window:CreateTag({ text = "PERFECT", color = Color3.fromRGB(178, 255, 64), order = 1 })
		modeTag = window:CreateTag({ text = "IDLE", color = Color3.fromRGB(44, 50, 62), order = 2 })
		tagLive = window:CreateTag({ text = "0 / 0", color = Color3.fromRGB(70, 76, 90), order = 3 })
	end)

	section(window, "PLAY")
	local shotTab = window:CreateTab({ name = "SHOT" })

	section(window, "VIEW")
	local liveTab = window:CreateTab({ name = "LIVE" })

	-- shot --------------------------------------------------------------------

	pcall(function()
		shotCard = shotTab:CreateText({
			name = "auto perfect  |  armed",
			text = "every release is sent inside the blue band\npress P to arm / disarm",
			icon = 7734068321,
		})
	end)

	section(shotTab, "RELEASE")

	local row = groupOf(shotTab)
	row:CreateToggle({
		name = "auto perfect",
		description = "snap the release into the perfect band",
		flag = "perfect",
		value = CFG.perfect,
		callback = function(v)
			CFG.perfect = v
			mode = v and "armed" or "disarmed"
		end,
	})
	row:CreateToggle({
		name = "only when green",
		description = "leave short releases alone",
		flag = "greenOnly",
		value = CFG.greenOnly,
		callback = function(v) CFG.greenOnly = v end,
	})
	row:CreateToggle({
		name = "console",
		description = "print every rewrite",
		flag = "console",
		value = CFG.console,
		callback = function(v) CFG.console = v end,
	})

	shotTab:CreateSlider({
		name = "snap depth",
		description = "where inside the blue band the release lands",
		range = { 0, 100 },
		increment = 1,
		value = CFG.depth,
		suffix = " %",
		flag = "depth",
		callback = function(v) CFG.depth = v end,
	})

	section(shotTab, "STATE")

	local statsRow = groupOf(shotTab)
	pcall(function()
		statShots = statsRow:CreateStat({
			name = "shots",
			value = 0,
			changeMode = "absolute",
		})
		statForced = statsRow:CreateStat({
			name = "snapped",
			value = 0,
			changeMode = "absolute",
		})
		statPerfect = statsRow:CreateStat({
			name = "perfect",
			value = 0,
			changeMode = "absolute",
		})
	end)

	shotTab:CreateButton({
		name = "reset counters",
		callback = function()
			stats.shots, stats.forced = 0, 0
			stats.perfect, stats.green, stats.other = 0, 0, 0
			stats.last = "no shot yet"
			mode = "reset"
		end,
	})

	-- live --------------------------------------------------------------------

	pcall(function()
		liveTab:CreateText({
			name = "SWISH // meter",
			text = "green and blue are the bar the game is drawing right now\nP arm / disarm   |   client side",
		})
	end)

	pcall(function()
		barMeter = liveTab:CreateProgress({
			name = "bar",
			description = "release point against the bands",
			range = { 0, 1 },
			value = 0,
			format = function(v) return string.format("%.0f%%", v * 100) end,
		})
	end)

	pcall(function()
		winCard = liveTab:CreateText({
			name = "bands  |  idle",
			text = "green  --    blue  --",
		})
	end)

	section(liveTab, "CONSOLE")
	statusBox = liveTab:CreateConsole({ name = "", height = 200, follow = false })

	section(liveTab, "SYS")

	liveTab:CreateKeybind({
		name = "arm / disarm",
		value = Enum.KeyCode.P,
		flag = "armKey",
		callback = function()
			CFG.perfect = not CFG.perfect
			mode = CFG.perfect and "armed" or "disarmed"
			window:Notify({ title = "SWISH", content = CFG.perfect and "auto perfect on" or "auto perfect off" })
		end,
	})

	liveTab:CreateButton({
		name = "unload",
		callback = function() shutdown() end,
	})

	return true
end

--// render ---------------------------------------------------------------------

local uiReady = pcall(buildUI)

local lastConsole = ""

local function barState()
	local ch = character
	if not ch or not ch.Parent then return nil end
	local alpha = ch:GetAttribute("ShotBarAlpha")
	if type(alpha) ~= "number" then return nil end
	local win = ch:GetAttribute("ShotBarWindow")
	local blue = ch:GetAttribute("ShotBarBlue")
	return {
		pos = alpha,
		green = tonumber(win) or 0,
		blue = tonumber(blue) or 0,
		phase = ch:GetAttribute("ShotBarPhase") or "?",
	}
end

local function statusText()
	local b = barState()
	local lines = {}
	lines[#lines + 1] = string.format("hook      %s", hooked and "SkillController.Net.SendInput" or "not found")
	lines[#lines + 1] = string.format("mode      %s   depth %d%%", CFG.perfect and "armed" or "off", CFG.depth)
	lines[#lines + 1] = string.format("shots     %d   snapped %d", stats.shots, stats.forced)
	lines[#lines + 1] = string.format("verdicts  %d perfect   %d green   %d other", stats.perfect, stats.green, stats.other)
	lines[#lines + 1] = ""
	lines[#lines + 1] = "last      " .. stats.last
	if b then
		lines[#lines + 1] = string.format("meter     %s  %.2f   green %.2f   blue %.2f", b.phase, b.pos, b.green, b.blue)
	else
		lines[#lines + 1] = "meter     idle"
	end
	return table.concat(lines, "\n")
end

local function render()
	local b = barState()

	if modeTag then
		local shown = b and string.upper(b.phase) or mode:upper()
		pcall(function() modeTag:SetText(shown:sub(1, 14)) end)
	end
	if tagState then
		pcall(function()
			tagState:SetText(CFG.perfect and "PERFECT" or "OFF")
			tagState:SetColor(CFG.perfect and Color3.fromRGB(178, 255, 64) or Color3.fromRGB(70, 76, 90))
		end)
	end
	if tagLive then
		pcall(function()
			tagLive:SetText(string.format("%d/%d", stats.perfect, stats.shots))
			tagLive:SetColor(stats.perfect > 0 and Color3.fromRGB(178, 255, 64) or Color3.fromRGB(70, 76, 90))
		end)
	end

	if shotCard then
		pcall(function()
			if hooked then
				shotCard:SetTitle(string.format("auto perfect  |  %s", CFG.perfect and "armed" or "off"))
				shotCard:Set(string.format(
					"%d shots  |  %d snapped  |  %d perfect\nserver verdict: %s",
					stats.shots, stats.forced, stats.perfect, stats.last
				))
			else
				shotCard:SetTitle("auto perfect  |  no hook")
				shotCard:Set("SkillController.Net not found yet - reload once you are in a game")
			end
		end)
	end

	if barMeter then
		pcall(function() barMeter:Set(b and b.pos or 0) end)
	end

	if winCard then
		pcall(function()
			if b then
				winCard:SetTitle(string.format("bands  |  %s  %.0f%%", b.phase, b.pos * 100))
				winCard:Set(string.format(
					"green  %.0f%% - 100%%\nblue   %.0f%% - 100%%\nperfect release lands at %.0f%%",
					(1 - b.green) * 100,
					(1 - b.blue) * 100,
					(1 - b.blue + b.blue * (CFG.depth / 100)) * 100
				))
			else
				winCard:SetTitle("bands  |  idle")
				winCard:Set("green  --    blue  --")
			end
		end)
	end

	if statusBox then
		local text = statusText()
		if text ~= lastConsole then
			lastConsole = text
			pcall(function() statusBox:Set(text) end)
		end
	end
end

local lastRender = 0
local renderConn = RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now - lastRender < 0.07 then return end
	lastRender = now
	local ok, err = pcall(render)
	if not ok then
		warn("[SWISH] render: " .. tostring(err))
	end
end)

--// teardown ------------------------------------------------------------------

function shutdown()
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	removeHook()
	if window then
		pcall(function() window:Unload() end)
		pcall(function()
			if window.screenGui then window.screenGui:Destroy() end
		end)
	end
	if _G.Swish then
		_G.Swish = nil
	end
end

_G.Swish = {
	cfg = CFG,
	stats = stats,
	panel = window,
	lib = Rayfield,
	box = statusBox,
	hooked = function() return hooked end,
	rewrite = rewrite,
	spot = perfectSpot,
	probe = function()
		local b = barState()
		return b and string.format("%s %.3f green %.3f blue %.3f", b.phase, b.pos, b.green, b.blue) or "idle"
	end,
	arm = function(v)
		CFG.perfect = v ~= false
	end,
	stop = function() shutdown() end,
}

print(string.format(
	"[SWISH] ready - auto perfect %s, depth %d%%, hook %s",
	CFG.perfect and "on" or "off", CFG.depth, hooked and "installed" or "missing"
))
if not uiReady then
	warn("[SWISH] window failed; _G.Swish still drives the hook")
end
end

--// embedded suite: duels  (from basketball-duels-script.luau) =========================
Hub.SUITE.duels = function()
--[[
	BASKETBALL DUELS -- one-file script for the game you're in right now

	place: 134954408729617  universe: 10773229738

	what's in it:
	  ESP            highlight + nameplate on every rig in the match (or lobby players)
	  perfect shot   forces the ShotRelease hold time into the green window
	  auto-green     calls the game's own shoot release when the HUD meter enters green
	  auto steal / smart steal / block / cross  press the game's own verbs with hand-reach timing
	  auto guard     stand between the ball handler and the hoop
	  court vision   hoop marker + live court distance chart
	  speed / jump  lobby movement patches (the sim itself is server-authoritative)
	  panic key      P: kill every toggle and put your body back to stock
	  session stats  counters in _G.SlimDuelsStats

	everything is client-side, everything has a toggle, the window is one
	Rayfield Gen2 panel and the whole thing tears itself down clean.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local STOCK_WALK = 16
local STOCK_JUMP = 7.2

local CFG = {
	esp = true,
	espNames = true,
	espDist = 0, -- 0 = show everyone
	rimEsp = true,
	shotChart = true,
	perfectShot = true, -- rewrite the release payload to the green point
	autoGreen = false, -- release as soon as the HUD meter hits green
	autoSteal = false,
	smartSteal = false,
	autoBlock = false,
	autoCross = false,
	autoGuard = false,
	speed = false,
	speedVal = 26,
	jump = false,
	jumpVal = 18,
	stealDist = 6.4,
	blockDist = 8.6,
	crossDist = 4.6,
	guardDist = 2.4,
}
CFG.speedVal = math.clamp(CFG.speedVal, 5, 60)
CFG.jumpVal = math.clamp(CFG.jumpVal, 0, 50)

local stats = _G.SlimDuelsStats or {}
_G.SlimDuelsStats = stats
local guardActive = false
local guardMX, guardMY = 0, 0
local stealNavActive = false
local stealMX, stealMY = 0, 0
stats.greenWrites = stats.greenWrites or 0
stats.autoReleases = stats.autoReleases or 0
stats.steals = stats.steals or 0
stats.smartSteals = stats.smartSteals or 0
stats.blocks = stats.blocks or 0
stats.crosses = stats.crosses or 0

local function myChar()
	local ch = LocalPlayer.Character
	return ch and ch:FindFirstChildWhichIsA("Humanoid") and ch
end
local function myHumanoid()
	return LocalPlayer.Character and LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid")
end
local function myRoot()
	local courtRig = Workspace:FindFirstChild(LocalPlayer.Name .. "_Court")
	if courtRig then
		local root = courtRig.PrimaryPart or courtRig:FindFirstChild("HumanoidRootPart")
		if root then return root end
	end
	local ch = myChar()
	return ch and ch.PrimaryPart
end
local function distance(a, b) return (a - b).Magnitude end
local function randomUnit()
	local a = math.random() * math.pi * 2
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

--// Iso modules -----------------------------------------------------------------
local Iso = ReplicatedStorage:WaitForChild("Iso", 5)
local Input, InputOk = nil, false
local Court, CourtOk = nil, false
pcall(function()
	if Iso then
		InputOk, Input = pcall(require, Iso:WaitForChild("Input"))
		CourtOk, Court = pcall(require, Iso:WaitForChild("Court"))
	end
end)
local verbs = (InputOk and Input and Input.verbs) or nil

--// perfect-shot payload hook --------------------------------------------------
-- the ShotRelease hold time is client-filled, so when perfect shot is on we
-- rewrite just that number to the centre of the shot window right before the
-- game's own input poller sends it. distance / contest are still server-graded.
local function meterValue()
	local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local root = pg and pg:FindFirstChild("IsoHUD") and pg.IsoHUD:FindFirstChild("Root")
	local world = root and root:FindFirstChild("World")
	local meter = world and world:FindFirstChild("ShotMeter")
	local fill = meter and meter:FindFirstChildOfClass("Frame", true)
	if fill and fill.Name ~= "Fill" then
		for _, d in ipairs(meter:GetDescendants()) do
			if d:IsA("Frame") and d.Name == "Fill" then fill = d break end
		end
	end
	if fill and fill.Size then return fill.Size.X.Scale end
	return nil
end
local function meterGreenWindow()
	local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local root = pg and pg:FindFirstChild("IsoHUD") and pg.IsoHUD:FindFirstChild("Root")
	local world = root and root:FindFirstChild("World")
	local meter = world and world:FindFirstChild("ShotMeter")
	local green = meter and meter:FindFirstChildOfClass("Frame", true)
	if green and green.Name ~= "Green" then
		for _, d in ipairs(meter:GetDescendants()) do
			if d:IsA("Frame") and d.Name == "Green" then green = d break end
		end
	end
	if green and green.Position and green.Size then
		local c, hw = green.Position.X.Scale, green.Size.X.Scale / 2
		return c - hw, c + hw
	end
	return nil, nil
end
local function installPerfectShot()
	if _G.SlimDuelsPollHook then
		_G.SlimDuelsPollCfg = CFG
		return true
	end
	if not (InputOk and Input and type(Input.poll) == "function") then return false end
	local orig = Input.poll
	local wrapper = function()
		local v = orig()
		local cfg = _G.SlimDuelsPollCfg or CFG
		if cfg.autoGuard and guardActive and type(v) == "table" then
			v.mx, v.my = guardMX, guardMY
		elseif cfg.smartSteal and stealNavActive and type(v) == "table" then
			v.mx, v.my = stealMX, stealMY
		end
		if cfg.perfectShot and type(v) == "table" and type(v.actions) == "table" then
			for _, a in ipairs(v.actions) do
				if type(a) == "table" and a.t == "holdEnd" and type(a.held) == "number" then
					local m = meterValue()
					if m and m > 0.02 then
						local fill = a.held / m
						if fill > 0.1 and fill < 2 then
							a.held = 0.8 * fill
							stats.greenWrites = stats.greenWrites + 1
						end
					end
				end
			end
		end
		return v
	end
	Input.poll = wrapper
	_G.SlimDuelsPollHook = { input = Input, orig = orig, wrapper = wrapper }
	_G.SlimDuelsPollCfg = CFG
	return true
end
local function uninstallPerfectShot()
	local hs = _G.SlimDuelsPollHook
	if not hs then return end
	pcall(function() if hs.input and hs.input.poll == hs.wrapper then hs.input.poll = hs.orig end end)
	_G.SlimDuelsPollHook = nil
	_G.SlimDuelsPollCfg = nil
end

--// ESP ------------------------------------------------------------------------
local espFolder = Instance.new("Folder")
espFolder.Name = "SlimDuelsEsp"
espFolder.Parent = Workspace
local espTargets = {}
local function makeTarget(name)
	local t = { hl = nil, plate = nil, tag = nil }
	local hl = Instance.new("Highlight")
	hl.Name = "SlimDuelsEspHighlight"
	hl.FillColor = Color3.fromRGB(90, 170, 255)
	hl.OutlineColor = Color3.fromRGB(255, 255, 255)
	hl.FillTransparency = 0.55
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Enabled = false
	hl.Parent = espFolder
	t.hl = hl
	local gui = Instance.new("BillboardGui")
	gui.Name = "SlimDuelsEspTag"
	gui.Size = UDim2.new(0, 150, 0, 26)
	gui.StudsOffset = Vector3.new(0, 3.4, 0)
	gui.AlwaysOnTop = true
	gui.Enabled = false
	gui.MaxDistance = 180
	gui.Parent = espFolder
	local lab = Instance.new("TextLabel")
	lab.BackgroundTransparency = 1
	lab.Size = UDim2.new(1, 0, 1, 0)
	lab.Font = Enum.Font.GothamBold
	lab.TextSize = 13
	lab.TextColor3 = Color3.fromRGB(245, 248, 255)
	lab.TextStrokeTransparency = 0.4
	lab.Text = name or ""
	lab.Parent = gui
	t.plate = gui
	t.tag = lab
	return t
end
local function ensureTarget(key, name)
	local t = espTargets[key]
	if t then return t end
	t = makeTarget(name)
	espTargets[key] = t
	return t
end
local function setTargetVisible(t, v)
	if t and t.hl then t.hl.Enabled = v end
	if t and t.plate then t.plate.Enabled = v end
end
local function rigModels()
	local out = {}
	local mineCourt = LocalPlayer.Name .. "_Court"
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and m:FindFirstChild("HumanoidRootPart") and m:FindFirstChildWhichIsA("Humanoid") then
			if m ~= LocalPlayer.Character and m.Name ~= mineCourt and m.Name ~= LocalPlayer.Name then
				out[#out + 1] = m
			end
		end
	end
	if #out == 0 then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LocalPlayer and p.Character then out[#out + 1] = p.Character end
		end
	end
	return out
end
local function refreshEsp()
	for _, t in pairs(espTargets) do setTargetVisible(t, false) end
	if not CFG.esp then return end
	local myR = myRoot()
	if not myR then return end
	for _, m in ipairs(rigModels()) do
		local root = m.PrimaryPart or m:FindFirstChild("HumanoidRootPart")
		if root then
			local dist = distance(root.Position, myR.Position)
			local show = CFG.espDist <= 0 or dist <= CFG.espDist
			local t = ensureTarget(m, m.Name)
			if show then
				pcall(function()
					t.hl.Adornee = m
					t.plate.Adornee = root
					t.tag.Text = string.format("%s  %.0f", CFG.espNames and m.Name or "?", dist)
				end)
				setTargetVisible(t, true)
			end
		end
	end
end
Players.PlayerRemoving:Connect(function(removed)
	local t = espTargets[removed.Character]
	if t then pcall(function() t.hl:Destroy() t.plate:Destroy() end) espTargets[removed.Character] = nil end
end)

--// court vision ----------------------------------------------------------------
local hoopPart, hoopGui, hoopText
local function hoopWorldPosition()
	if CourtOk and Court then
		local ok, x, y = pcall(Court.fromWorld, Vector3.new(25, 0, 5.25))
		if ok then return nil end
		local ok2, pt = pcall(Court.toWorld, 25, 0, 5.25)
		if ok2 and pt and pt:IsA("Vector3") then return pt + Vector3.new(0, 10, 0) end
	end
	return Vector3.new(0, 10, -18.25)
end
local function ensureHoopEsp()
	if hoopPart then return end
	local pos = hoopWorldPosition()
	hoopPart = Instance.new("Part")
	hoopPart.Name = "SlimDuelsHoopMarker"
	hoopPart.Size = Vector3.new(0.4, 0.4, 0.4)
	hoopPart.Transparency = 1
	hoopPart.Anchored = true
	hoopPart.CanCollide = false
	hoopPart.CanQuery = false
	hoopPart.CanTouch = false
	hoopPart.Massless = true
	pcall(function() hoopPart.CFrame = CFrame.new(pos) end)
	hoopPart.Parent = Workspace
	hoopGui = Instance.new("BillboardGui")
	hoopGui.Name = "SlimDuelsHoopEsp"
	hoopGui.Size = UDim2.new(0, 130, 0, 28)
	hoopGui.StudsOffset = Vector3.new(0, 1, 0)
	hoopGui.AlwaysOnTop = true
	hoopGui.Enabled = CFG.rimEsp
	hoopGui.MaxDistance = 260
	hoopText = Instance.new("TextLabel")
	hoopText.BackgroundTransparency = 1
	hoopText.Size = UDim2.new(1, 0, 1, 0)
	hoopText.Font = Enum.Font.GothamBold
	hoopText.TextSize = 14
	hoopText.TextColor3 = Color3.fromRGB(255, 210, 70)
	hoopText.TextStrokeTransparency = 0.3
	hoopText.Text = "HOOP"
	hoopText.Parent = hoopGui
	hoopGui.Parent = hoopPart
end
local shotChartGui, shotChartLabel
local function courtDistance()
	local ch = myChar()
	local root = ch and ch.PrimaryPart
	if not root or not CourtOk or not Court then return nil end
	local ok, cx, cy = pcall(Court.fromWorld, root.Position)
	if not ok or not cx or not cy then return nil end
	return math.sqrt((cx - 25) ^ 2 + (cy - 5.25) ^ 2)
end
local function updateShotChart()
	if not CFG.shotChart then if shotChartGui then shotChartGui.Enabled = false end return end
	if not shotChartGui then
		local g = Instance.new("ScreenGui")
		g.Name = "SlimDuelsShotChart"
		g.IgnoreGuiInset = true
		g.ResetOnSpawn = false
		g.DisplayOrder = 9998
		pcall(function() g.Parent = game:GetService("CoreGui") end)
		if not g.Parent then g.Parent = LocalPlayer:FindFirstChildOfClass("PlayerGui") end
		local f = Instance.new("TextLabel")
		f.Name = "Chart"
		f.Size = UDim2.new(0, 210, 0, 44)
		f.AnchorPoint = Vector2.new(1, 1)
		f.Position = UDim2.new(1, -16, 1, -310)
		f.BackgroundColor3 = Color3.fromRGB(14, 16, 22)
		f.BackgroundTransparency = 0.35
		f.Font = Enum.Font.Code
		f.TextSize = 20
		f.TextColor3 = Color3.fromRGB(230, 235, 245)
		f.TextStrokeTransparency = 0.3
		f.Text = "COURT"
		f.Parent = g
		local cor = Instance.new("UICorner")
		cor.CornerRadius = UDim.new(0, 10)
		cor.Parent = f
		shotChartGui, shotChartLabel = g, f
	end
	shotChartGui.Enabled = true
	local d = courtDistance()
	shotChartLabel.Text = d and string.format("%.1f FT", d) or "COURT"
end

--// input automation -------------------------------------------------------------
local stealNext, blockNext, crossNext = 0, 0, 0
local autoGreenArmed = false
local autoGreenHoldStart = 0
local function nearestOtherRoot(limit)
	local myR = myRoot()
	if not myR then return nil, math.huge end
	local best, bestD = nil, limit
	for _, m in ipairs(rigModels()) do
		local root = m.PrimaryPart or m:FindFirstChild("HumanoidRootPart")
		if root then
			local d = distance(root.Position, myR.Position)
			if d < bestD then best, bestD = root, d end
		end
	end
	return best, bestD
end
local function ballAnchor()
	local cam = Workspace.CurrentCamera or Workspace:FindFirstChild("Camera")
	return cam and cam:FindFirstChild("BallMarkAnchor")
end
local function ownRigModel()
	return Workspace:FindFirstChild(LocalPlayer.Name .. "_Court")
end
local function rigModelOfRoot(root)
	if not root then return nil end
	for _, m in ipairs(rigModels()) do
		if m.PrimaryPart == root or m:FindFirstChild("HumanoidRootPart") == root then return m end
	end
	return ownRigModel() and (ownRigModel().PrimaryPart == root or ownRigModel():FindFirstChild("HumanoidRootPart") == root) and ownRigModel() or nil
end
local function ballHolderModel()
	local ball = ballAnchor()
	if not ball or not ball:IsA("BasePart") then return nil end
	local best, bestD = nil, 12
	local myR = myRoot()
	if myR then
		local d = distance(ball.Position, myR.Position)
		if d < bestD then best, bestD = ownRigModel(), d end
	end
	for _, m in ipairs(rigModels()) do
		local root = m.PrimaryPart or m:FindFirstChild("HumanoidRootPart")
		if root then
			local d = distance(root.Position, ball.Position)
			if d < bestD then best, bestD = m, d end
		end
	end
	return best
end
local function ownHasBall()
	local ball, myR = ballAnchor(), myRoot()
	return ball and myR and distance(ball.Position, myR.Position) <= 4
end
local function rigClipIs(model, clip)
	if not model or not clip then return false end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local anim = hum and hum:FindFirstChildOfClass("Animator")
	if not anim then return false end
	for _, track in ipairs(anim:GetPlayingAnimationTracks()) do
		local a = track.Animation
		if track.Name == clip or (a and a.Name == clip) then return true end
	end
	return false
end
local function autoGreenTick()
	if not CFG.autoGreen then return end
	if not (InputOk and Input and verbs and Input.holding and Input.holding()) then
		autoGreenArmed = false
		autoGreenHoldStart = 0
		return
	end
	local now = os.clock()
	if autoGreenHoldStart == 0 then autoGreenHoldStart = now end
	local m = meterValue()
	local lo, hi = meterGreenWindow()
	if not (m and lo and hi) then return end
	if m < lo - 0.05 then
		autoGreenArmed = true
	end
	if autoGreenArmed and m >= lo and m <= hi and now - autoGreenHoldStart >= 0.2 then
		if verbs then pcall(verbs.shootUp) end
		stats.autoReleases = stats.autoReleases + 1
		autoGreenArmed = false
		autoGreenHoldStart = 0
	end
end
local function ballDistanceToMe()
	local ball, myR = ballAnchor(), myRoot()
	if not ball or not myR or not CourtOk or not Court then return nil end
	local okX, rx, ry = pcall(Court.fromWorld, myR.Position)
	local okB, bx, by = pcall(Court.fromWorld, ball.Position)
	if not (okX and okB and rx and ry and bx and by) then return nil end
	return math.sqrt((bx - rx) ^ 2 + (by - ry) ^ 2)
end
local function smartStealTick(now)
	stealNavActive = false
	stealMX, stealMY = 0, 0
	if not CFG.smartSteal or ownHasBall() then return end
	local d = ballDistanceToMe()
	if not d then return end
	if d > CFG.stealDist * 1.35 then
		local myR = myRoot()
		local ball = ballAnchor()
		if myR and ball and CourtOk and Court then
			local okX, rx, ry = pcall(Court.fromWorld, myR.Position)
			local okB, bx, by = pcall(Court.fromWorld, ball.Position)
			if okX and okB then
				local dx, dy = bx - rx, by - ry
				local dist = math.sqrt(dx * dx + dy * dy)
				if dist > 0.8 then
					stealMX, stealMY = math.clamp(dx, -1, 1), math.clamp(dy, -1.6, 1.6)
					stealNavActive = true
				end
			end
		end
	end
	if d <= CFG.stealDist and now >= stealNext then
		stealNext = now + 0.8
		if verbs then pcall(verbs.steal) end
		stats.smartSteals = stats.smartSteals + 1
	end
end
local function autoInputTick(now)
	guardActive = false
	guardMX, guardMY = 0, 0
	if now < stealNext and now < blockNext and now < crossNext then return end
	local myR = myRoot()
	if not myR then return end
	local hasBall = ownHasBall()
	local holderModel = ballHolderModel()
	local holderRoot = holderModel and (holderModel.PrimaryPart or holderModel:FindFirstChild("HumanoidRootPart")) or nil
	if not holderRoot then
		holderRoot = nearestOtherRoot(10)
	end
	local near, d = nearestOtherRoot(8.5)
	if not near then return end
	if CFG.autoSteal and not hasBall and holderRoot and d <= CFG.stealDist and now >= stealNext then
		stealNext = now + 0.78
		if verbs then pcall(verbs.steal) end
		stats.steals = stats.steals + 1
	end
	if CFG.autoBlock and not hasBall and holderModel and rigClipIs(holderModel, "JumpShot") and d <= CFG.blockDist and now >= blockNext then
		blockNext = now + 0.72
		if verbs then pcall(verbs.block) end
		stats.blocks = stats.blocks + 1
	end
	if CFG.autoCross and hasBall and d <= CFG.crossDist and now >= crossNext then
		crossNext = now + 0.45
		if verbs then pcall(verbs.cross) end
		stats.crosses = stats.crosses + 1
	end
end
local guardNext = 0
local function ballHandlerRoot(limit)
	local ball = Workspace.Camera and Workspace.Camera:FindFirstChild("BallMarkAnchor")
	if ball and ball:IsA("BasePart") then
		local best, bestD = nil, limit or 60
		for _, m in ipairs(rigModels()) do
			local root = m.PrimaryPart or m:FindFirstChild("HumanoidRootPart")
			if root then
				local d = distance(root.Position, ball.Position)
				if d < bestD then best, bestD = root, d end
			end
		end
		if best then return best end
	end
	return nearestOtherRoot(limit or 60)
end
local function autoGuardTick(now, _hum, root)
	guardActive = false
	guardMX, guardMY = 0, 0
	if not CFG.autoGuard or not root or now < guardNext then return end
	guardNext = now + 0.12
	if ownHasBall() then return end
	local handler = ballHandlerRoot(60)
	if not handler or not CourtOk or not Court then return end
	local hoop = hoopWorldPosition()
	local toHoop = Vector3.new(hoop.X - handler.Position.X, 0, hoop.Z - handler.Position.Z)
	if toHoop.Magnitude < 0.5 then return end
	local stand = handler.Position + toHoop.Unit * math.clamp(CFG.guardDist, 1.5, 8)
	local okX, rx, ry = pcall(Court.fromWorld, root.Position)
	local okS, sx, sy = pcall(Court.fromWorld, stand)
	if not (okX and okS and rx and ry and sx and sy) then return end
	local dx, dy = sx - rx, sy - ry
	local dist = math.sqrt(dx * dx + dy * dy)
	if dist > 0.6 then
		guardMX = math.clamp(dx, -1, 1)
		guardMY = math.clamp(dy, -1.6, 1.6)
		guardActive = true
	end
end

--// body mods --------------------------------------------------------------------
local function applyBodyMods()
	local hum = myHumanoid()
	if not hum then return end
	if CFG.speed then hum.WalkSpeed = CFG.speedVal else hum.WalkSpeed = STOCK_WALK end
	if CFG.jump then hum.JumpHeight = CFG.jumpVal else hum.JumpHeight = STOCK_JUMP end
end

--// lifecycle --------------------------------------------------------------------
local window, statusBox
local shutOnce = false
local shutdown
shutdown = function()
	if shutOnce then return end
	shutOnce = true
	pcall(function() RunService:UnbindFromRenderStep("SlimDuels") end)
	uninstallPerfectShot()
	for _, t in pairs(espTargets) do pcall(function() t.hl:Destroy() t.plate:Destroy() end) end
	table.clear(espTargets)
	pcall(function() espFolder:Destroy() end)
	pcall(function() if hoopPart then hoopPart:Destroy() end end)
	pcall(function() if shotChartGui then shotChartGui:Destroy() end end)
	local hum = myHumanoid()
	if hum then hum.WalkSpeed = STOCK_WALK hum.JumpHeight = STOCK_JUMP end
	if window then
		pcall(function() window:Unload() end)
		pcall(function() if window.screenGui then window.screenGui:Destroy() end end)
	end
	_G.SlimDuels = nil
	print("[SlimDuels] unloaded")
end
local function panic()
	CFG.speed, CFG.jump, CFG.esp = false, false, false
	CFG.perfectShot, CFG.autoGreen, CFG.autoSteal = false, false, false
	CFG.autoBlock, CFG.autoCross, CFG.autoGuard = false, false, false
	CFG.rimEsp, CFG.shotChart = false, false
	applyBodyMods()
	print("[SlimDuels] panic: all toggles killed, body restored to stock")
end

local Rayfield
pcall(function() Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))() end)

local function buildUI()
	if not Rayfield then return end
	local w = Rayfield:CreateWindow({ Name = "BASKETBALL DUELS | SLIM", LoadingTitle = "SLIM DUELS", LoadingSubtitle = "one-file court panel", KeySystem = false })
	window = w
	local court = w:CreateTab({ name = "COURT" })
	local sys = w:CreateTab({ name = "SYS" })
	court:CreateToggle({ name = "esp", description = "see every rig through walls, with distance", flag = "esp", value = CFG.esp, callback = function(v) CFG.esp = v end })
	court:CreateToggle({ name = "esp names", description = "show rig names over their heads", flag = "espNames", value = CFG.espNames, callback = function(v) CFG.espNames = v end })
	court:CreateSlider({ name = "esp range", description = "0 = everyone, else studs", range = {0, 250}, increment = 10, value = CFG.espDist, suffix = " st", callback = function(v) CFG.espDist = v end })
	court:CreateToggle({ name = "hoop ESP", description = "marker the sim hoop through walls", flag = "rimEsp", value = CFG.rimEsp, callback = function(v) CFG.rimEsp = v if hoopGui then hoopGui.Enabled = v end end })
	court:CreateToggle({ name = "shot chart", description = "live feet-to-hoop readout", flag = "shotChart", value = CFG.shotChart, callback = function(v) CFG.shotChart = v end })

	pcall(function() court:CreateSection({ name = "SCORING" }) end)
	court:CreateToggle({ name = "perfect shot", description = "rewrite the release hold time into the green window", value = CFG.perfectShot, callback = function(v) CFG.perfectShot = v if v then installPerfectShot() end end })
	court:CreateToggle({ name = "auto-green", description = "release yourself the moment the HUD meter enters green", value = CFG.autoGreen, callback = function(v) CFG.autoGreen = v end })

	pcall(function() court:CreateSection({ name = "DEFENSE" }) end)
	court:CreateToggle({ name = "auto steal", description = "press steal when a defender is inside your reach", value = CFG.autoSteal, callback = function(v) CFG.autoSteal = v end })
	court:CreateToggle({ name = "smart steal", description = "close in on the ball and steal inside true hand reach", value = CFG.smartSteal, callback = function(v) CFG.smartSteal = v end })
	court:CreateToggle({ name = "auto block", description = "press block when a defender gets near", value = CFG.autoBlock, callback = function(v) CFG.autoBlock = v end })
	court:CreateToggle({ name = "auto cross", description = "press crossover when a defender presses you", value = CFG.autoCross, callback = function(v) CFG.autoCross = v end })
	court:CreateToggle({ name = "auto guard", description = "stand between the ball handler and the hoop", flag = "autoGuard", value = CFG.autoGuard, callback = function(v) CFG.autoGuard = v end })
	court:CreateSlider({ name = "guard space", description = "studs you stand off the ball handler - lower is tighter", range = {1.5, 8}, increment = .1, value = CFG.guardDist, suffix = " st", callback = function(v) CFG.guardDist = v end })
	court:CreateSlider({ name = "steal reach", description = "studs before auto steal fires", range = {3, 8}, increment = .1, value = CFG.stealDist, suffix = " st", callback = function(v) CFG.stealDist = v end })
	court:CreateSlider({ name = "block reach", description = "studs before auto block fires", range = {4, 10}, increment = .1, value = CFG.blockDist, suffix = " st", callback = function(v) CFG.blockDist = v end })

	court:CreateToggle({ name = "speed boost", description = "lobby movement; the match sim ignores this", flag = "speed", value = CFG.speed, callback = function(v) CFG.speed = v end })
	court:CreateSlider({ name = "walkspeed", description = "lobby only", range = {5, 60}, increment = 1, value = CFG.speedVal, suffix = " ws", callback = function(v) CFG.speedVal = v end })
	court:CreateToggle({ name = "high jump", description = "lobby movement; the match sim ignores this", flag = "jump", value = CFG.jump, callback = function(v) CFG.jump = v end })
	court:CreateSlider({ name = "jump height", description = "lobby only", range = {0, 50}, increment = 1, value = CFG.jumpVal, suffix = " st", callback = function(v) CFG.jumpVal = v end })

	sys:CreateButton({ name = "panic (P)", description = "kill every toggle, put your body back to stock", callback = panic })
	sys:CreateButton({ name = "unload panel", description = "tear everything down", callback = shutdown })
	statusBox = sys:CreateConsole({ name = "log", height = 150, follow = false })
	if statusBox then pcall(function() statusBox:Set("slim duels loaded | esp, scoring, defense, movement") end) end
end

installPerfectShot()
local uiOk = pcall(buildUI)
if not uiOk then warn("[SlimDuels] rayfield failed to load - running headless") end

local function renderFrame()
	applyBodyMods()
	refreshEsp()
	ensureHoopEsp()
	if hoopGui then hoopGui.Enabled = CFG.rimEsp end
	updateShotChart()
	autoGreenTick()
	smartStealTick(os.clock())
	local ch = myChar()
	local mineHum = ch and ch:FindFirstChildWhichIsA("Humanoid")
	local mineRoot = ch and ch.PrimaryPart
	if mineHum and mineRoot then
		autoInputTick(os.clock())
		autoGuardTick(os.clock(), mineHum, mineRoot)
	end
end
RunService:BindToRenderStep("SlimDuels", Enum.RenderPriority.Camera.Value + 3, function() pcall(renderFrame) end)

UserInputService.InputBegan:Connect(function(input, typing)
	if typing then return end
	if UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.P then
		panic()
		if window and window.Notify then pcall(function() window:Notify({ title = "SLIM", content = "panic - stock body", duration = 2 }) end) end
	end
end)

_G.SlimDuels = { cfg = CFG, stats = stats, stop = shutdown, panic = panic }
if window then
	print("[SlimDuels] panel loaded - court vision, perfect shot, auto-green, defense, movement")
else
	print("[SlimDuels] modules loaded headless - no panel window")
end
end

--// embedded suite: qb_aimbot  (from qb-aimbot.luau) =========================
Hub.SUITE.qb_aimbot = function()
--[[
	QB AIMBOT -- Throw A Football (place 125942529011157)
	Client-side only. It mirrors the old ragdoll football aimbot's job, but
	it uses this game's real API surface instead of the old remote:

	  * GameRigs.Home.Receivers is the live receiver list (root, catch point, Vel)
	  * ThrowController.SetAimTargets accepts a callable returning
	    { Position, Velocity } entries - exactly the shape the game's own
	    scanTargets / leadPoint path already understands
	  * BallController:Launch's 4th argument after self is Perfect, so the
	    perfect flag can be forced at the single choke point every release
	    flows through
	  * the camera is never written; the aim candidate is fed to the game's
	    own target registry instead

	Keys:
		RightShift  master toggle
		F           cycle the locked receiver manually
		G           toggle auto-target
		H           toggle ESP
		E           nudge/force the perfect release when your launch fires
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local CONFIG = {
	enabled = true,
	aimLock = true,
	esp = true,
	forcePerfect = true,
	fov = 60,
	aimCone = 45,
	maxDistance = 220,
	leadWeight = 1.0,
	openBonus = 10,
	hoverPick = true,
	hoverRelease = 1.2,
}

local Keys = {
	toggle = Enum.KeyCode.RightShift,
	cycle = Enum.KeyCode.F,
	autoTarget = Enum.KeyCode.G,
	esp = Enum.KeyCode.H,
	perfect = Enum.KeyCode.E,
}

--// controller modules --------------------------------------------------------
local function loadController(name)
	local ok, mod = pcall(function()
		return require(LocalPlayer.PlayerScripts.Controllers[name])
	end)
	if ok then return mod end
	return nil
end

local ThrowController = loadController("ThrowController")
local GameRigs = loadController("GameRigs")
local BallController = nil
pcall(function()
	BallController = require(ReplicatedStorage.TAF_Shared.Client.BallController)
end)

local ThrowConfig = nil
pcall(function()
	ThrowConfig = require(ReplicatedStorage.TAF_Shared.Shared.ThrowConfig)
end)

local GameConfig = nil
pcall(function()
	GameConfig = require(ReplicatedStorage.TAF_Shared.Shared.GameConfig)
end)

--// preclean (live-reload keeps the previous run only if it shut down) ---------
pcall(function() RunService:UnbindFromRenderStep("QBAimThrow") end)
for _, d in ipairs({Workspace:FindFirstChild("QBAimEsp")}) do
	if d then d:Destroy() end
end
local oldGui = LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("QBAimHud")
if oldGui then oldGui:Destroy() end
local oldAssist = _G.SlimQBAimState
if oldAssist and oldAssist.stop then pcall(oldAssist.stop) end

-- pre-clean removes it. rebuilt fresh every load so old stray ESP never lingers
local espFolder = Instance.new("Folder")
espFolder.Name = "QBAimEsp"
espFolder.Parent = Workspace

local manualCycle = 0
local stats = { throws = 0, mode = "auto" }
local currentEntry = nil

-- assist widening: the game's own snap cone is ThrowConfig.AssistAngle (12 deg).
-- while locked we widen it so the assist drags the aim onto our candidate from
-- a much bigger cone. stock values are saved and restored on disable.
local ASSIST_ORIG = nil
local function widenAssist()
	if not ThrowConfig then return end
	ASSIST_ORIG = ASSIST_ORIG or { ThrowConfig.AssistAngle, ThrowConfig.AssistPower }
	ThrowConfig.AssistAngle = CONFIG.aimCone
	ThrowConfig.AssistPower = 1
end
local function restoreAssist()
	if not ThrowConfig or not ASSIST_ORIG then return end
	ThrowConfig.AssistAngle = ASSIST_ORIG[1]
	ThrowConfig.AssistPower = ASSIST_ORIG[2]
	ASSIST_ORIG = nil
end

--// hooks ---------------------------------------------------------------------
-- force Perfect at BallController:Launch (arg 4 after self). This is the
-- exact spot ragdoll football script used for its perfect flag, minus any
-- remote assumptions from that game.
local installBallHook, uninstallBallHook, markAimTargets
do
	local origLaunch = nil
	local hooked = false

	installBallHook = function()
		if hooked or not BallController or type(BallController.Launch) ~= "function" then return end
		origLaunch = BallController.Launch
		BallController.Launch = function(self, a2, a3, a4, a5, a6, a7)
			if CONFIG.forcePerfect and a5 ~= true then
				a5 = true
			end
			stats.throws = stats.throws + 1
			return origLaunch(self, a2, a3, a4, a5, a6, a7)
		end
		hooked = true
	end

	uninstallBallHook = function()
		if not hooked or not origLaunch then return end
		BallController.Launch = origLaunch
		hooked = false
	end

	-- the game's own target registry expects a callable returning
	-- { Position, Velocity } entries. LockPoint then applies the normal lead.
	markAimTargets = function(fn)
		if ThrowController and type(ThrowController.SetAimTargets) == "function" then
			pcall(ThrowController.SetAimTargets, ThrowController, fn)
		end
	end
end

installBallHook()
local function resolver()
	if not CONFIG.aimLock then return nil end
	local e = currentEntry
	if not e or not e.point then return nil end
	return { { Position = e.point, Velocity = e.vel or Vector3.zero } }
end
if CONFIG.enabled and CONFIG.aimLock then
	markAimTargets(resolver)
	widenAssist()
end

--// target model helpers ------------------------------------------------------
local function receivers()
	if not GameRigs or not GameRigs.Home or not GameRigs.Home.Receivers then return {} end
	return GameRigs.Home.Receivers
end

local function receiverPoint(entry)
	if not entry then return nil end
	local root = entry.Root
	local base = entry.Pos or (root and root.Position) or nil
	if not base then return nil end
	local scale = tonumber(entry.Scale) or 1
	local lift = tonumber(entry.Lift) or 0
	local hh = GameConfig and tonumber(GameConfig.HandsHeight) or 2.4
	return Vector3.new(base.X, base.Y + (3 + hh) * scale + lift, base.Z)
end

local trackers = {}
local function trackVelocity(rig, pos, now)
	local t = trackers[rig]
	if not t then
		trackers[rig] = { pos = pos, t = now, vel = Vector3.zero }
		return Vector3.zero
	end
	local dt = now - t.t
	if dt >= 0.016 then
		local raw = (pos - t.pos) / dt
		if raw.Magnitude > 200 then raw = Vector3.zero end
		t.vel = t.vel:Lerp(raw, 0.3)
		t.pos = pos
		t.t = now
	end
	return t.vel
end

local function throwOrigin()
	if ThrowController and type(ThrowController.GetHandPart) == "function" then
		local ok, hand = pcall(ThrowController.GetHandPart, ThrowController)
		if ok and hand and hand:IsA("BasePart") then return hand.Position end
	end
	local ch = LocalPlayer.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if root then return root.Position + Vector3.new(0, 3.4, 0) end
	return nil
end

local function defenderGap(execPos, allRigs)
	local best = math.huge
	for i, other in ipairs(allRigs) do
		if other and other ~= execPos then
			local pos = other.Pos or other.Root and other.Root.Position
			if pos then
				local d = (pos - execPos).Magnitude
				if d < best then best = d end
			end
		end
	end
	return best
end

local function entryFor(receiver, origin, now)
	local point = receiverPoint(receiver)
	local root = receiver.Root
	local base = receiver.Pos or (root and root.Position) or point
	if not point or not base then return nil end
	-- receivers carry their own live movement velocity, so prefer it; our
	-- sampled tracker is only the fallback for rigs that report 0
	local vel = (typeof(receiver.Vel) == "Vector3" and receiver.Vel.Magnitude > 0.05 and receiver.Vel)
		or trackVelocity(receiver, base, now)
	local cam = Workspace.CurrentCamera
	if not cam then return nil end
	local toTarget = point - cam.CFrame.Position
	if toTarget.Magnitude < 0.01 then return nil end
	local angle = math.deg(math.acos(math.clamp(cam.CFrame.LookVector:Dot(toTarget.Unit), -1, 1)))
	local dist = (point - origin).Magnitude
	local gap = defenderGap(base, receivers())
	return {
		receiver = receiver,
		point = point,
		vel = vel,
		angle = angle,
		dist = dist,
		gap = gap,
		score = angle * 1.25 + dist * 0.08 - math.min(gap, 12) * CONFIG.openBonus * 0.1,
	}
end

local function candidates(origin, now)
	local list = {}
	for _, r in ipairs(receivers()) do
		if type(r) == "table" and r.Job ~= "Down" then
			local e = entryFor(r, origin, now)
			if e and e.angle <= CONFIG.fov and e.dist <= CONFIG.maxDistance and e.dist > 6 then
				table.insert(list, e)
			end
		end
	end
	table.sort(list, function(a, b) return a.score < b.score end)
	return list
end

--// ESP ----------------------------------------------------------------------
local esp = { rig = nil, hl = nil, box = nil, tag = nil, label = nil, beam = nil }
local function clearEsp()
	for _, v in ipairs(espFolder:GetChildren()) do v:Destroy() end
	esp.rig, esp.hl, esp.box, esp.tag, esp.label, esp.beam = nil, nil, nil, nil, nil, nil
end
local function buildEsp(model, root)
	clearEsp()
	if not model or not root then return end
	local hl = Instance.new("Highlight")
	hl.Adornee = model
	hl.FillColor = Color3.fromRGB(255, 60, 60)
	hl.FillTransparency = 0.78
	hl.OutlineColor = Color3.fromRGB(255, 235, 90)
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = espFolder
	esp.hl = hl
	local box = Instance.new("BoxHandleAdornment")
	box.Adornee = root
	box.Size = Vector3.new(4.4, 4.4, 4.4)
	box.AlwaysOnTop = true
	box.ZIndex = 5
	box.Transparency = 0.6
	box.Color3 = Color3.fromRGB(255, 60, 60)
	box.Parent = espFolder
	esp.box = box
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(255, 220, 60)
	beam.Transparency = 0.35
	beam.Size = Vector3.new(0.12, 0.12, 1)
	beam.Parent = espFolder
	esp.beam = beam
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(180, 34)
	tag.StudsOffset = Vector3.new(0, 5.4, 0)
	tag.AlwaysOnTop = true
	tag.Adornee = root
	tag.Parent = espFolder
	esp.tag = tag
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextColor3 = Color3.fromRGB(255, 235, 90)
	label.TextStrokeTransparency = 0.4
	label.Parent = tag
	esp.label = label
	esp.rig = model
end
local function drawEsp(entry)
	-- receiver entries are plain tables carrying a .Model and a .Root part,
	-- never Instances themselves
	local model = entry and entry.Model
	local root = entry and entry.Root
	if not model or not root then
		if esp.rig then clearEsp() end
		return
	end
	if esp.rig ~= entry then buildEsp(model, root) end
	if esp.label then
		esp.label.Text = string.format("R%d  %.0f°  %.0f st  gap %.0f", entry.Slot or 0, entry.angle, entry.dist, entry.gap)
	end
end
local function updateBeam(entry)
	local beam = esp.beam
	if not beam then return end
	local origin = throwOrigin()
	if not origin or not entry or not entry.point then
		beam.Transparency = 1
		return
	end
	local delta = entry.point - origin
	local len = delta.Magnitude
	if len < 0.5 then beam.Transparency = 1 return end
	beam.Size = Vector3.new(0.12, 0.12, len)
	beam.CFrame = CFrame.lookAt(origin + delta * 0.5, entry.point)
	beam.Transparency = 0.45
end

--// minimal HUD + throw button ------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "QBAimHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(248, 108)
panel.Position = UDim2.new(0, 14, 1, -122)
panel.BackgroundColor3 = Color3.fromRGB(14, 16, 22)
panel.BackgroundTransparency = 0.18
panel.BorderSizePixel = 0
panel.Parent = gui
local corner = Instance.new("UICorner") corner.CornerRadius = UDim.new(0, 8) corner.Parent = panel
local stroke = Instance.new("UIStroke") stroke.Color = Color3.fromRGB(255, 221, 35) stroke.Transparency = 0.55 stroke.Thickness = 1.4 stroke.Parent = panel
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -16, 0, 22) title.Position = UDim2.fromOffset(8, 6) title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold title.TextSize = 14 title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 221, 35) title.Text = "QB AIMBOT" title.Parent = panel
local body = Instance.new("TextLabel")
body.Size = UDim2.new(1, -16, 0, 72) body.Position = UDim2.fromOffset(8, 30) body.BackgroundTransparency = 1
body.Font = Enum.Font.Code body.TextSize = 12 body.TextXAlignment = Enum.TextXAlignment.Left body.TextYAlignment = Enum.TextYAlignment.Top
body.TextColor3 = Color3.fromRGB(232, 234, 240) body.Text = "" body.Parent = panel
local throwBtn = Instance.new("TextButton")
throwBtn.Size = UDim2.fromOffset(104, 46) throwBtn.Position = UDim2.new(0, 270, 1, -122)
throwBtn.BackgroundColor3 = Color3.fromRGB(20, 23, 30) throwBtn.BackgroundTransparency = 0.1 throwBtn.BorderSizePixel = 0
throwBtn.AutoButtonColor = true throwBtn.Font = Enum.Font.GothamBold throwBtn.TextSize = 15
throwBtn.TextColor3 = Color3.fromRGB(255, 221, 35) throwBtn.Text = "LOCK" throwBtn.Parent = gui
local btnCorner = Instance.new("UICorner") btnCorner.CornerRadius = UDim.new(0, 8) btnCorner.Parent = throwBtn
local btnStroke = Instance.new("UIStroke") btnStroke.Color = Color3.fromRGB(255, 221, 35) btnStroke.Transparency = 0.45 btnStroke.Thickness = 1.4 btnStroke.Parent = throwBtn

local lastHud = 0
local function refreshHud(entry)
	local now = os.clock()
	if now - lastHud < 0.1 then return end
	lastHud = now
	body.Text = string.format(
		"aim     %s\npick    %s\nesp     %s\ntarget  %s\nthrows  %d",
		CONFIG.aimLock and "on" or "off",
		manualCycle > 0 and ("R" .. manualCycle) or "auto",
		CONFIG.esp and "on" or "off",
		entry and string.format("R%d (%.0f st)", entry.Slot or 0, entry.dist) or "-",
		stats.throws
	)
	throwBtn.TextColor3 = entry and Color3.fromRGB(255, 221, 35) or Color3.fromRGB(120, 124, 134)
	btnStroke.Color = entry and Color3.fromRGB(255, 221, 35) or Color3.fromRGB(90, 94, 104)
end

local function setEnabled(v)
	CONFIG.enabled = v
	if v then
		if CONFIG.aimLock then
			markAimTargets(resolver)
			widenAssist()
		end
	else
		clearEsp()
		markAimTargets(nil)
		restoreAssist()
	end
end

local function forceRelease()
	if not BallController or type(BallController.Launch) ~= "function" then return end
	local origin = throwOrigin()
	local e = currentEntry
	if not origin or not e or not e.point then stats.mode = "no target" return end
	local dir = (e.point - origin)
	if dir.Magnitude < 0.01 then return end
	local speed = if ThrowConfig and type(ThrowConfig.idealSpeed) == "function" then ThrowConfig.idealSpeed(origin, e.point, dir.Unit) else nil
	if not speed then speed = 62 end
	local ok, err = pcall(BallController.Launch, BallController, origin, dir.Unit * speed, nil, true, nil, nil)
	if not ok then stats.mode = "launch err " .. tostring(err):sub(1, 40) end
end

throwBtn.Activated:Connect(forceRelease)

_G.QBAim = {
	pick = function(rigOrName)
		local all = receivers()
		if type(rigOrName) == "number" then
			manualCycle = rigOrName
			return true
		end
		for i, r in ipairs(all) do
			if r == rigOrName or (type(rigOrName) == "string" and tostring(r.Slot) == rigOrName) then
				manualCycle = i
				return true
			end
		end
		return false
	end,
	clear = function() manualCycle = 0 end,
	throw = forceRelease,
}

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Keys.toggle then
		setEnabled(not CONFIG.enabled)
	elseif input.KeyCode == Keys.esp then
		CONFIG.esp = not CONFIG.esp
		if not CONFIG.esp then clearEsp() end
	elseif input.KeyCode == Keys.autoTarget then
		CONFIG.aimLock = not CONFIG.aimLock
		if CONFIG.aimLock then
			currentEntry = nil
			markAimTargets(resolver)
			widenAssist()
		else
			markAimTargets(nil)
			restoreAssist()
		end
	elseif input.KeyCode == Keys.cycle then
		manualCycle = manualCycle + 1
	elseif input.KeyCode == Keys.perfect then
		forceRelease()
	end
end)

--// main loop -----------------------------------------------------------------
RunService:BindToRenderStep("QBAimThrow", Enum.RenderPriority.Camera.Value + 1, function()
	local cam = Workspace.CurrentCamera
	if not cam then return end
	if not CONFIG.enabled then clearEsp() return end
	local origin = throwOrigin()
	if not origin then clearEsp() return end
	local now = os.clock()
	local list = candidates(origin, now)
	local entry = list[1]
	if manualCycle > 0 and list[manualCycle] then entry = list[manualCycle] end
	currentEntry = entry
	if CONFIG.esp and entry then
		drawEsp(entry)
		updateBeam(entry)
	elseif esp.rig then
		clearEsp()
	end
	refreshHud(entry)
end)

local function shutdown()
	markAimTargets(nil)
	uninstallBallHook()
	restoreAssist()
	_G.QBAim = nil
	_G.SlimQBAimState = nil
	if gui then gui:Destroy() end
	clearEsp()
	espFolder:Destroy()
	pcall(function() RunService:UnbindFromRenderStep("QBAimThrow") end)
end

_G.SlimQBAimState = { stop = shutdown, cfg = CONFIG, stats = stats }

print("[QBAim] loaded - RightShift toggle | F cycle receiver | G aim lock | H esp | E force release")
end

--// embedded suite: taf_bypass  (from taf-anticheat-bypass.luau) =========================
Hub.SUITE.taf_bypass = function()
--[[
	TAF anti-cheat bypass -- Throw A Football / Drive Duels family
	place: 125942529011157 / 80119315919763  universe: 10768235926

	what it does:
	  - overrides the client AnimGuard/AnimWhitelist checks by making
	    AnimWhitelist.allowed() answer true
	  - flips the local AntiCheatEnabled / AntiCheatAnimGuard attributes off,
	    so the guard starts in dormant mode
	  - installs no movement hooks, no remotes, no UI hooks except its panel

	before enabling, restore() puts the original allowed() and attributes back.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local CFG = {
	bypass = true, -- default ON for this one purpose
	muteMenu = false,
	speed = false,
	speedVal = 30,
}

local stats = _G.SlimTafBypassStats or {}
_G.SlimTafBypassStats = stats
stats.allowedCalls = stats.allowedCalls or 0

local origAllowed = nil
local savedEnabled, savedAnimGuard = nil, nil
local installed = false
local GameConfigOk, GameConfig = pcall(function()
	return require(ReplicatedStorage:WaitForChild("TAF_Shared"):WaitForChild("Shared"):WaitForChild("GameConfig"))
end)
local stockSpeed = 18
local function applySpeed()
	local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if CFG.speed then
		if GameConfigOk and GameConfig then pcall(function() GameConfig.QBWalkSpeed = CFG.speedVal end) end
		if hum then hum.WalkSpeed = CFG.speedVal end
	else
		if GameConfigOk and GameConfig then pcall(function() GameConfig.QBWalkSpeed = stockSpeed end) end
		if hum then hum.WalkSpeed = stockSpeed end
	end
end

local function readAttributes()
	savedEnabled = Workspace:GetAttribute("AntiCheatEnabled")
	savedAnimGuard = Workspace:GetAttribute("AntiCheatAnimGuard")
end

local function install()
	if installed then return true end
	readAttributes()
	local ok = pcall(function()
		Workspace:SetAttribute("AntiCheatEnabled", false)
		Workspace:SetAttribute("AntiCheatAnimGuard", false)
	end)
	if not ok then return false end

	local okWhitelist, whitelist = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AnimWhitelist"))
	end)
	if not (okWhitelist and whitelist and type(whitelist.allowed) == "function") then
		return false
	end

	origAllowed = whitelist.allowed
	whitelist.allowed = function(...)
		stats.allowedCalls = stats.allowedCalls + 1
		if CFG.bypass then return true end
		return origAllowed(...)
	end
	installed = true
	return true
end

local function uninstall()
	CFG.speed = false
	applySpeed()
	if not installed then return end
	pcall(function()
		if savedEnabled ~= nil then Workspace:SetAttribute("AntiCheatEnabled", savedEnabled) else Workspace:SetAttribute("AntiCheatEnabled", nil) end
		if savedAnimGuard ~= nil then Workspace:SetAttribute("AntiCheatAnimGuard", savedAnimGuard) else Workspace:SetAttribute("AntiCheatAnimGuard", nil) end
	end)
	local okWhitelist, whitelist = pcall(function()
		return require(ReplicatedStorage.Shared.AnimWhitelist)
	end)
	if okWhitelist and whitelist and origAllowed then
		pcall(function() whitelist.allowed = origAllowed end)
	end
	installed = false
	print("[SlimTaf] anti-cheat bypass removed")
end

install()
applySpeed()
RunService:BindToRenderStep("SlimTafSpeed", Enum.RenderPriority.Camera.Value + 3, function() applySpeed() end)
print("[SlimTaf] anti-cheat bypass loaded - AnimGuard allowed() now answers true")

--// minimal Rayfield panel ------------------------------------------------------
local Rayfield
pcall(function() Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))() end)

local window, statusBox
local shutOnce = false
local function shutdown()
	if shutOnce then return end
	shutOnce = true
	pcall(function() RunService:UnbindFromRenderStep("SlimTafSpeed") end)
	uninstall()
	if window then
		pcall(function() window:Unload() end)
		pcall(function() if window.screenGui then window.screenGui:Destroy() end end)
	end
	_G.SlimTafBypass = nil
	print("[SlimTaf] panel unloaded")
end

local function buildUI()
	if not Rayfield then return end
	local w = Rayfield:CreateWindow({
		Name = "TAF | SLIM",
		LoadingTitle = "SLIM TAF",
		LoadingSubtitle = "anti-cheat bypass",
		KeySystem = false,
	})
	window = w
	local tab = w:CreateTab({ name = "STEALTH" })
	tab:CreateToggle({
		name = "anti-cheat bypass",
		description = "muffle AnimGuard + keep animations allowed",
		value = CFG.bypass,
		callback = function(v)
			CFG.bypass = v
			if v then install() else uninstall() end
		end,
	})
	tab:CreateToggle({
		name = "speed",
		description = "patch QBWalkSpeed + WalkSpeed, survives the per-frame reset",
		value = CFG.speed,
		callback = function(v) CFG.speed = v applySpeed() end,
	})
	tab:CreateSlider({
		name = "walkspeed",
		description = "stock is 18",
		range = {5, 150},
		increment = 1,
		value = CFG.speedVal,
		suffix = " ws",
		callback = function(v) CFG.speedVal = v applySpeed() end,
	})
	tab:CreateButton({ name = "reload bypass", description = "re-install the whitelist hook", callback = function() install() end })
	tab:CreateButton({ name = "unload", description = "uninstall cleanly", callback = shutdown })
	statusBox = tab:CreateConsole({ name = "log", height = 140, follow = false })
	if statusBox then pcall(function() statusBox:Set("slim taf loaded | anti-cheat bypass") end) end
end

local uiOk = pcall(buildUI)
if not uiOk then warn("[SlimTaf] rayfield failed to load - running headless") end

_G.SlimTafBypass = { cfg = CFG, stats = stats, install = install, uninstall = uninstall, stop = shutdown }
end

--// embedded suite: physbox  (from physbox-panel.luau) =========================
Hub.SUITE.physbox = function()
-- PhysBox (HitBout) | CORNER - combo king autopilot, full power, inf stamina, ESP
-- place 96120449121277 | Rayfield Gen2 | replace-not-stack via _G.PhysBoxCorner
-- rides only official paths: Driver.punch + the Controls input table. never touches Net.Claim.

local prev = _G.PhysBoxCorner
local CFG = (prev and prev.cfg) or {}
-- defaults merge: keeps saved settings across reloads, fills in fields added later
for k, v in pairs({
	guard = true,
	guardStyle = "adaptive", -- adaptive | high | low
	combo = false,
	comboName = "jab jab cross",
	stepIn = true,
	range = 5.5,
	staminaFloor = 0.15,
	infSta = true,
	fullPower = true,
	autoplay = false,
	aggr = 0.6,
	antiLow = true,
	dodge = false,
	esp = true,
}) do
	if CFG[k] == nil then
		CFG[k] = v
	end
end
if prev and prev.stop then
	pcall(prev.stop)
end
_G.PhysBoxCorner = { cfg = CFG }

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local PhysBox = RS:WaitForChild("PhysBox")
local Moves = require(PhysBox:WaitForChild("Moves"))
local Config = require(PhysBox:WaitForChild("Config"))

local PS = LP:WaitForChild("PlayerScripts")
local ClientScripts = PS:WaitForChild("PhysBoxClient")
local Driver = require(ClientScripts:WaitForChild("Driver"))
local Controls = require(ClientScripts:WaitForChild("Controls"))

--// combos ---------------------------------------------------------------------
local COMBOS = {
	["jab jab cross"] = { "Jab", "Jab", "Cross" },
	["hooks"] = { "LeftHook", "RightHook", "Cross" },
	["mixup"] = { "Jab", "Cross", "LeftHook", "Uppercut" },
	["heavy hands"] = { "Cross", "Uppercut", "RightHook" },
	["kicks"] = { "FrontKick", "Roundhouse", "Cross" },
	["low rider"] = { "Uppercut", "Cross", "Uppercut" },
}

-- punch class (from the game's own AI dodge tables) + which arm throws it
local CLASS = {
	Jab = "straight", Cross = "straight",
	LeftHook = "hook", RightHook = "hook",
	LeftUppercut = "upper", Uppercut = "upper",
	FrontKick = "push", Roundhouse = "round", HighKick = "round",
}
local ARM = {
	Jab = 1, LeftHook = 1, Uppercut = 1, FrontKick = 1,
	Cross = -1, RightHook = -1, LeftUppercut = -1, Roundhouse = -1, HighKick = -1,
}
local GUARD_FOR = { straight = "High", hook = "High", upper = "Low", push = "Low", round = "High" }

-- dodge shapes by punch class: duck hooks/swings, pull back off uppers, lateral slip the rest
local DODGE_LEAN = {
	hook = Vector2.new(0, -1),
	round = Vector2.new(0, -1),
	upper = Vector2.new(0, 1),
}
-- the game's own AI step-out distances per punch class
local DODGE_STEP = { straight = 0.6, hook = 0.7, upper = 0.6, push = 1.5, round = 1.4 }

--// state ----------------------------------------------------------------------
local app, window
local origUpdate, wrapUpdate
local origPunch, origPress, wrapPunch, wrapPress
local keyConn
local queue, queueAt = {}, 0
local myThrow = { move = nil, at = 0 } -- our last queue punch: move + time, for zero-gap chaining
local lowTrack = { boxer = nil, maxHead = 0, lowFor = 0, t = 0 }
local oppPhase = { boxer = nil, lastAct = nil, endedAt = 0, startedAt = 0, wasCharging = false, lastInterrupt = 0, lastCombo = nil }
local oppGuard = { high = 0, low = 0 }
local dead = false
local lastErrAt = 0

local mySta, myDaze, oppSta, oppDaze, roundStat

-- find the shared app state via Controls.update's upvalues.
-- recurses through wrapped functions, so a stale wrapper left by a torn-down
-- previous run can't hide the game's own app table from us
local lastAppTry = 0
local function findApp()
	local seen = {}
	local function scan(fn, depth)
		if depth > 4 or type(fn) ~= "function" or seen[fn] then
			return nil
		end
		seen[fn] = true
		local ok, ups = pcall(debug.getupvalues, fn)
		if not ok or type(ups) ~= "table" then
			return nil
		end
		for _, v in ipairs(ups) do
			-- .input plus any shared-state marker; menuOpen nils out between bouts
			if type(v) == "table" and type(rawget(v, "input")) == "table"
				and (rawget(v, "menuOpen") ~= nil or rawget(v, "state") ~= nil or rawget(v, "matchLock") ~= nil) then
				return v
			end
		end
		for _, v in ipairs(ups) do
			if type(v) == "function" then
				local found = scan(v, depth + 1)
				if found then
					return found
				end
			end
		end
		return nil
	end
	return scan(Controls.update, 0)
end
app = findApp()

local function oops(err)
	local now = os.clock()
	if now - lastErrAt > 5 then
		lastErrAt = now
		warn("[Corner] " .. tostring(err))
	end
end

--// bout helpers ---------------------------------------------------------------
local function myBoxer(bout)
	return bout and bout.mine
end

local function nearestOpponent(bout, me)
	local best, bestD = nil, math.huge
	local boxers = bout and bout.boxers
	if not boxers then
		return nil, nil
	end
	local myPos = me and me.rig and me.rig.pelvis and me.rig.pelvis.Position
	if not myPos then
		return nil, nil
	end
	for _, b in ipairs(boxers) do
		if b ~= me and b.rig and b.rig.pelvis and not b.victory then
			local d = (b.rig.pelvis.Position - myPos).Magnitude
			if d < bestD then
				best, bestD = b, d
			end
		end
	end
	return best, bestD
end

local function punching(b)
	return b ~= nil and b.action ~= nil and CLASS[b.action.name] ~= nil
end

local function free(b)
	return b ~= nil and b.action == nil
end

local function inRange(d)
	return d ~= nil and d <= CFG.range
end

local function staminaOK(b)
	if CFG.infSta then
		return true -- pinned at full: never let a mid-frame server read stall the engine
	end
	return (b and b.stamina or 1) > CFG.staminaFloor
end

-- quick counter punch: the game's own punch entry, skipping our full-power
-- windup conversion - speed is the whole point of an interrupt
local function quickPunch(move)
	if type(origPunch) == "function" then
		return (pcall(origPunch, move))
	end
	return (pcall(Driver.punch, move))
end

-- combo shuffle bag: the game's AI remembers the punches it has seen
-- (seenActs / defendedActs) and defends them better each time, so the
-- autopilot rotates through everything and never settles into a pattern
local comboBag = {}
local function nextCombo(opp)
	if opp and (opp.daze or 0) > 45 then
		return COMBOS["heavy hands"] -- they are rocked: finisher pressure
	end
	-- turtle reading: punch under a high guard, over a low one
	if oppGuard.high > oppGuard.low * 1.5 and oppGuard.high > 1 then
		return COMBOS["low rider"]
	end
	if oppGuard.low > oppGuard.high * 1.5 and oppGuard.low > 1 then
		return COMBOS["hooks"]
	end
	if #comboBag == 0 then
		for _, n in ipairs({ "jab jab cross", "hooks", "mixup", "heavy hands", "kicks" }) do
			comboBag[#comboBag + 1] = n
		end
		for i = #comboBag, 2, -1 do
			local j = math.random(i)
			comboBag[i], comboBag[j] = comboBag[j], comboBag[i]
		end
	end
	local pick = table.remove(comboBag, 1)
	if pick == oppPhase.lastCombo and #comboBag > 0 then
		comboBag[#comboBag + 1] = pick
		pick = table.remove(comboBag, 1)
	end
	oppPhase.lastCombo = pick
	return COMBOS[pick] or COMBOS["jab jab cross"]
end

-- inf stamina: ride the game's own unlimited flag where the local sim owns a meter
local function meterUnlimited(on)
	local bout = Driver.bout()
	local me = bout and bout.mine
	local fight = me and bout.fight
	local sta = fight and rawget(fight, "stamina")
	local m = type(sta) == "table" and rawget(sta, me) or nil
	if type(m) == "table" and m.setUnlimited and rawget(m, "unlimited") ~= on then
		pcall(function() m:setUnlimited(on) end)
	end
end

local function pinStamina(bout, me)
	if not CFG.infSta or not me then
		return
	end
	me.stamina = 1
	meterUnlimited(true)
end

local function pinNow()
	local bout = Driver.bout()
	pinStamina(bout, bout and bout.mine)
end

-- full power: taps become held windups; every windup (ours or the player's)
-- auto-releases at max charge, like holding all the way every time
local chargeWatch = { active = false, last = -1, lastAt = 0, stall = 0, at = 0 }
local function fullPowerStep()
	if not CFG.fullPower then
		return
	end
	local bout = Driver.bout()
	local me = bout and bout.mine
	local a = me and me.action
	if not (a and a.charging) then
		chargeWatch.active = false
		return
	end
	local now = os.clock()
	if not chargeWatch.active then
		chargeWatch.active = true
		chargeWatch.last = -1
		chargeWatch.stall = 0
		chargeWatch.at = now
		chargeWatch.lastAt = now
		return
	end
	local cs = Driver.charge()
	if cs > chargeWatch.last + 0.001 then
		chargeWatch.last = cs
		chargeWatch.stall = 0
	else
		chargeWatch.stall += now - chargeWatch.lastAt
	end
	chargeWatch.lastAt = now
	-- release at full, on a stall (stamina cap / non-chargeable windup), or a hard timeout
	if cs >= 0.99 or chargeWatch.stall > 0.4 or now - chargeWatch.at > 2.5 then
		pcall(Driver.release, a.name)
		chargeWatch.active = false
	end
end

--// frame logic ----------------------------------------------------------------
local function step()
	local input = app and app.input
	if not input then
		return
	end

	local bout = Driver.bout()
	local me = myBoxer(bout)
	if not me or not me.rig or not me.rig.pelvis or me.victory then
		queue = {}
		return
	end

	-- inf stamina: pin the share the punch gates and fatigue HUD read
	pinStamina(bout, me)

	-- gym/menu/tutorial locks: hands off
	if app.menuOpen or app.wheelOpen or app.tutorialActive or app.aiLock or app.matchLock then
		queue = {}
		return
	end

	local opp, dist = nearestOpponent(bout, me)
	local oppAttack = punching(opp)

	-- low-rider tracker: watch their head height against a standing reference
	-- (their own max seen, or mine while I'm upright - same rig template).
	-- half a second below 78% of standing = they are camping the crouch.
	local camper = false
	if opp and opp.rig and opp.rig.parts and opp.rig.parts.Head and opp.rig.pelvis then
		local now = os.clock()
		local dt = math.clamp(now - (lowTrack.t or now), 0, 0.1)
		lowTrack.t = now
		if lowTrack.boxer ~= opp then
			lowTrack.boxer = opp
			lowTrack.maxHead = 0
			lowTrack.lowFor = 0
		end
		local ohd = opp.rig.parts.Head.Position.Y - opp.rig.pelvis.Position.Y
		if ohd > lowTrack.maxHead then
			lowTrack.maxHead = ohd
		end
		local myHead = me.rig.parts and me.rig.parts.Head
		if myHead and (me.lean == nil or me.lean.Magnitude < 0.15) then
			local mhd = myHead.Position.Y - me.rig.pelvis.Position.Y
			if mhd > lowTrack.maxHead then
				lowTrack.maxHead = mhd
			end
		end
		if lowTrack.maxHead > 1 and ohd < lowTrack.maxHead * 0.78 then
			lowTrack.lowFor += dt
		else
			lowTrack.lowFor = 0
		end
		camper = CFG.antiLow and lowTrack.lowFor > 0.5
	end

	-- opponent phase tracker: are they mid-windup (committed, can't dodge)
	-- or recovering from a just-finished punch (wide open)?
	if opp then
		if oppPhase.boxer ~= opp then
			oppPhase.boxer = opp
			oppPhase.lastAct = nil
			oppPhase.endedAt = 0
			oppPhase.startedAt = 0
			oppPhase.wasCharging = false
		end
		local oppName = opp.action and opp.action.name or nil
		local oppCharging = opp.action ~= nil and opp.action.charging == true
		-- a new action, or a held windup releasing into its strike: that
		-- moment is the real strike clock - anti-slip slips off THIS, not
		-- the windup hold, so long charges don't trigger an endless lean
		if oppName ~= nil and (oppName ~= oppPhase.lastAct or (oppPhase.wasCharging and not oppCharging)) then
			oppPhase.startedAt = os.clock()
		end
		if oppPhase.lastAct ~= nil and oppName == nil then
			oppPhase.endedAt = os.clock()
		end
		oppPhase.wasCharging = oppCharging
		oppPhase.lastAct = oppName
	end
	local oppWinding = opp ~= nil and opp.action ~= nil and opp.action.charging == true
	local oppRecovering = opp ~= nil and opp.action == nil and (os.clock() - oppPhase.endedAt) < 0.75
	local staggered = opp ~= nil and (opp.stunned or (opp.daze or 0) > 60)

	-- their guard height: target whatever they are NOT covering
	if opp and dist and dist < CFG.range + 3 then
		local oi = type(opp.input) == "table" and opp.input or nil
		if oi and oi.block == true then
			if oi.blockLow == true then
				oppGuard.low = math.min(oppGuard.low + 0.05, 5)
			else
				oppGuard.high = math.min(oppGuard.high + 0.05, 5)
			end
		else
			oppGuard.high = math.max(oppGuard.high - 0.01, 0)
			oppGuard.low = math.max(oppGuard.low - 0.01, 0)
		end
	else
		oppGuard.high = math.max(oppGuard.high - 0.01, 0)
		oppGuard.low = math.max(oppGuard.low - 0.01, 0)
	end

	-- feature switches: auto play forces the whole package on
	local wantGuard = CFG.guard or CFG.autoplay
	local wantDodge = CFG.dodge or CFG.autoplay
	local wantHunt = (CFG.stepIn and CFG.combo) or CFG.autoplay
	local wantCombo = CFG.combo or CFG.autoplay

	-- autopilot: badly dazed -> cover up and back out until the fog clears
	if CFG.autoplay and opp and dist and ((me.daze or 0) > (20 + 25 * (CFG.aggr or 0.6)) or me.stunned) then
		local away = (me.rig.pelvis.Position - opp.rig.pelvis.Position) * Vector3.new(1, 0, 1)
		if away.Magnitude > 0.1 then
			input.move = away.Unit
		end
		input.block = true
		queue = {}
		return
	end

	-- incoming attack: guard the light stuff, dodge the heavy stuff - guard broken always means dodge
	if oppAttack and dist and dist < CFG.range + 2.5 then
		local cls = CLASS[opp.action.name] or "straight"
		local heavy = (cls == "hook") or (cls == "round") or (cls == "push") or (cls == "upper")
		if wantDodge and (me.guardBroken or heavy) then
			-- auto-dodge: class-aware slip plus step out of the strike lane (AI's own step distances)
			local lean = DODGE_LEAN[cls]
			if lean then
				input.lean = lean
			else
				input.lean = Vector2.new(-(ARM[opp.action.name] or 1), 0)
			end
			local away = (me.rig.pelvis.Position - opp.rig.pelvis.Position) * Vector3.new(1, 0, 1)
			if away.Magnitude > 0.1 then
				input.move = away.Unit * math.clamp((DODGE_STEP[cls] or 0.6) / 1.5, 0.3, 1)
			end
		elseif wantGuard and not me.guardBroken then
			-- auto-guard: raise the right guard while their punch is live
			local style = CFG.guardStyle
			if camper then
				style = "Low" -- crouched opponents punch up into the body
			elseif style == "adaptive" then
				style = GUARD_FOR[cls] or "High"
			end
			input.block = true
			input.blockLow = style == "Low"
		end
	end

	-- hunt: step in when it is SAFE (they are committed to a windup,
	-- recovering, rocked or camping), hold the ring when they are neutral
	-- so we outbox instead of walking into counters - and circle a touch
	-- under auto play so the approach isn't a straight line
	if wantHunt and not oppAttack and opp and dist and dist > CFG.range * 0.75 then
		local closing = oppWinding or oppRecovering or staggered or camper or dist > CFG.range or (CFG.autoplay and (CFG.aggr or 0.6) >= 0.75) -- max aggression: always take the ring
		if closing then
			local to = (opp.rig.pelvis.Position - me.rig.pelvis.Position) * Vector3.new(1, 0, 1)
			if to.Magnitude > 1 then
				local fwd = to.Unit
				local dir = fwd
				if CFG.autoplay then
					dir = (fwd + Vector3.new(-fwd.Z, 0, fwd.X) * 0.3).Unit
				end
				input.move = dir * math.clamp(to.Magnitude / 4, 0.4, 1)
			end
		end
	end

	-- low rider: duck with them so our straights land as body shots
	if camper and wantCombo and not oppAttack then
		input.lean = Vector2.new(0, -0.7)
	end

	-- combo engine, combo-king edition: chain punches THROUGH the active
	-- action so the game's own queue links them into the recovery frames
	-- (zero gap), interrupt their windups with fast counters, and rotate
	-- combos so their defence tracking never settles
	local staggered = opp ~= nil and (opp.stunned or (opp.daze or 0) > 60)
	local opening = (not CFG.autoplay) or (not oppAttack) or staggered or oppRecovering or oppWinding
	if wantCombo and opp and inRange(dist) and opening then
		local now = os.clock()
		local a = me.action
		local holding = a ~= nil and a.charging == true -- let the full-power watcher finish its windup first
		if CFG.autoplay and oppWinding and not camper and not holding and now - oppPhase.lastInterrupt > 0.3 / math.max(CFG.aggr or 0.6, 0.3) then
			-- interrupt: they are holding a windup and can't dodge - beat
			-- them to contact with a quick punch (no full-power windup)
			oppPhase.lastInterrupt = now
			queue = {}
			quickPunch("Jab")
		elseif #queue == 0 and staminaOK(me) and now - queueAt > 0.25 then
			-- no free(me) gate on purpose: a punch thrown mid-action gets
			-- queued by the game and chains straight into the recovery
			local combo = COMBOS[camper and "low rider"] or (CFG.autoplay and nextCombo(opp)) or COMBOS[CFG.comboName] or COMBOS["jab jab cross"]
			for _, m in ipairs(combo) do
				queue[#queue + 1] = m
			end
			queueAt = now
		end
		-- drain: throw the next punch while the current one is still flying
		-- so Boxer queues it - the chain lands the frame recovery ends
		if #queue > 0 and staminaOK(me) and not holding and now - myThrow.at > 0.12 then
			local mv = queue[1]
			local cost = (Config.Stamina and Config.Stamina.Cost and Config.Stamina.Cost[mv]) or 0
			if CFG.infSta or cost == 0 or (me.stamina or 1) * (Config.Stamina and Config.Stamina.Max or 100) > cost + CFG.staminaFloor * 100 then
				-- respect the repetition lock: rotate a same-move repeat to
				-- the back so the chain keeps flowing instead of being refused
				if #queue > 1 and (mv == (a and a.name) or mv == myThrow.move) then
					table.remove(queue, 1)
					queue[#queue + 1] = mv
				else
					table.remove(queue, 1)
					myThrow.move = mv
					myThrow.at = now
					if not pcall(Driver.punch, mv) then
						queue = {}
					end
				end
			else
				table.remove(queue, 1) -- can't afford it: skip the move, don't stall the chain
			end
		end
	elseif #queue > 0 and (not inRange(dist) or not staminaOK(me)) then
		queue = {}
	end
end

-- registry of our wrappers -> what they wrapped (weak keys), so a torn-down
-- previous run's stale wrappers get stripped and reloads never stack
local WRAPS = setmetatable({}, { __mode = "k" })
local function unwrapOurs(fn)
	local n = 0
	while type(fn) == "function" and WRAPS[fn] ~= nil and n < 8 do
		fn = WRAPS[fn]
		n += 1
	end
	return fn
end

-- wrap the game's own input poll so our writes land after the keyboard each frame
origUpdate = unwrapOurs(Controls.update)
wrapUpdate = function()
	origUpdate()
	if not dead then
		local ok, err = pcall(step)
		if not ok then
			oops(err)
		end
	end
end
WRAPS[wrapUpdate] = origUpdate
Controls.update = wrapUpdate

-- wrap the public punch/press entry points so the kick gate reads full stamina at throw time
origPunch = unwrapOurs(Driver.punch)
wrapPunch = function(move, charge)
	if not dead then
		pcall(pinNow)
	end
	-- full power: a tap starts the held windup instead of the quick punch
	if CFG.fullPower and type(move) == "string" and move ~= "Push" and charge == nil then
		local def = Moves[move]
		if type(def) == "table" and def.charge then
			return origPunch(move, { held = true })
		end
	end
	return origPunch(move, charge)
end
WRAPS[wrapPunch] = origPunch
Driver.punch = wrapPunch
if type(Driver.press) == "function" then
	origPress = unwrapOurs(Driver.press)
	wrapPress = function(move)
		if not dead then
			pcall(pinNow)
		end
		return origPress(move)
	end
	WRAPS[wrapPress] = origPress
	Driver.press = wrapPress
end

--// ESP ------------------------------------------------------------------------
local segs = {}
local drawingOK = pcall(function()
	local t = Drawing.new("Line")
	pcall(function() t:Remove() end)
	return true
end)
local function seg(i)
	local s = segs[i]
	if not s then
		s = Drawing.new("Line")
		s.Thickness = 1.6
		segs[i] = s
	end
	return s
end
local function hideAll()
	for _, s in ipairs(segs) do
		s.Visible = false
	end
end

local function headPartOf(b)
	local rig = b and b.rig
	if not rig then
		return nil
	end
	local parts = rig.parts
	if type(parts) == "table" then
		local h = parts.Head or parts.head or parts["Head "]
		if h then
			return h
		end
	end
	return rig.pelvis
end

local function box(x, y, r, color, used)
	local corners = {
		{ x - r, y - r, x + r, y - r },
		{ x + r, y - r, x + r, y + r },
		{ x + r, y + r, x - r, y + r },
		{ x - r, y + r, x - r, y - r },
	}
	for _, c in ipairs(corners) do
		used += 1
		local ln = seg(used)
		ln.From = Vector2.new(c[1], c[2])
		ln.To = Vector2.new(c[3], c[4])
		ln.Color = color
		ln.Visible = true
	end
	return used
end

local function drawESP()
	if not CFG.esp or dead or not drawingOK then
		hideAll()
		return
	end
	local bout = Driver.bout()
	local me = myBoxer(bout)
	local opp = nearestOpponent(bout, me)
	if not opp then
		hideAll()
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		hideAll()
		return
	end
	local head = headPartOf(opp)
	if not head then
		hideAll()
		return
	end
	local v = cam:WorldToViewportPoint(head.Position)
	if v.Z <= 0 then
		hideAll()
		return
	end
	local dist = me and me.rig and me.rig.pelvis and (head.Position - me.rig.pelvis.Position).Magnitude or 10
	local r = math.clamp(900 / math.max(v.Z, 1), 8, 60)
	local camping = (lowTrack.lowFor or 0) > 0.5
	local color = punching(opp) and Color3.fromRGB(255, 60, 60)
		or (camping and Color3.fromRGB(255, 170, 40))
		or Color3.fromRGB(80, 200, 255)
	local used = box(v.X, v.Y, r, color, 0)

	-- range line from my head to theirs: green in range, red out
	if me and me.rig and me.rig.pelvis then
		local mv = cam:WorldToViewportPoint(me.rig.pelvis.Position)
		if mv.Z > 0 then
			used += 1
			local ln = seg(used)
			ln.From = Vector2.new(mv.X, mv.Y)
			ln.To = Vector2.new(v.X, v.Y)
			ln.Color = dist <= CFG.range and Color3.fromRGB(90, 255, 120) or Color3.fromRGB(255, 120, 60)
			ln.Thickness = 1
			ln.Visible = true
		end
	end

	for i = used + 1, #segs do
		segs[i].Visible = false
	end
end

local renderConn = RunService.RenderStepped:Connect(function()
	if dead then return end
	-- render-phase pin: lands after the frame's remote events, so the HUD reads full
	pcall(pinNow)
	drawESP()
end)

local lastStatAt = 0
local function updateStats()
	local now = os.clock()
	if now - lastStatAt < 0.25 then
		return
	end
	lastStatAt = now
	local bout = Driver.bout()
	local me = myBoxer(bout)
	local opp = nearestOpponent(bout, me)
	local function set(stat, val)
		if stat then
			pcall(function() stat:Set(val) end)
		end
	end
	set(mySta, me and math.floor((me.stamina or 0) * 100 + 0.5) or 0)
	set(myDaze, me and math.floor((me.daze or 0) + 0.5) or 0)
	set(oppSta, opp and math.floor((opp.stamina or 0) * 100 + 0.5) or 0)
	set(oppDaze, opp and math.floor((opp.daze or 0) + 0.5) or 0)
	set(roundStat, bout and bout.round or 0)
end
local statConn = RunService.Heartbeat:Connect(function()
	if dead then return end
	-- app state can appear late (bout start, menu close) - keep retrying quietly
	if not app and os.clock() - lastAppTry > 2 then
		lastAppTry = os.clock()
		app = findApp()
		if app then
			print("[Corner] app state found (late)")
		end
	end
	-- inf stamina: re-pin every beat so incoming server state can't drain it
	pcall(pinNow)
	-- full power: walk the charge watcher every beat
	pcall(fullPowerStep)
	updateStats()
end)

--// lifecycle ------------------------------------------------------------------
local function panic()
	CFG.guard = false
	CFG.combo = false
	CFG.dodge = false
	CFG.esp = false
	CFG.stepIn = false
	CFG.infSta = false
	CFG.autoplay = false
	CFG.fullPower = false
	CFG.antiLow = false
	pcall(meterUnlimited, false)
	queue = {}
	if window then
		for _, f in ipairs({ "guard", "combo", "dodge", "esp", "stepin", "infsta", "autoplay", "antilow", "fullpower" }) do
			pcall(function() window:Set(f, false) end)
		end
	end
	print("[Corner] panic: hands off - everything off")
end

local function shutdown()
	if dead then
		return
	end
	dead = true
	if Controls.update == wrapUpdate then
		Controls.update = origUpdate
	end
	if Driver.punch == wrapPunch then
		Driver.punch = origPunch
	end
	if origPress and Driver.press == wrapPress then
		Driver.press = origPress
	end
	pcall(meterUnlimited, false)
	if keyConn then keyConn:Disconnect() keyConn = nil end
	if renderConn then renderConn:Disconnect() renderConn = nil end
	if statConn then statConn:Disconnect() statConn = nil end
	for _, s in ipairs(segs) do
		pcall(function() s:Remove() end)
	end
	if window then
		pcall(function() window:Unload() end)
	end
	_G.PhysBoxCorner = nil
	print("[Corner] unloaded")
end

keyConn = UserInputService.InputBegan:Connect(function(i, gp)
	if gp then return end
	if i.KeyCode == Enum.KeyCode.P then
		panic()
	end
end)

--// UI -------------------------------------------------------------------------
local Rayfield
pcall(function() Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))() end)

local function buildUI()
	if not Rayfield then return end
	local w = Rayfield:CreateWindow({
		Name = "PHYSBOX | CORNER",
		LoadingTitle = "CORNERMAN",
		LoadingSubtitle = "combo-king autopilot, full power, inf stamina",
		KeySystem = false,
	})
	window = w
	local fight = w:CreateTab({ name = "FIGHT" })
	local view = w:CreateTab({ name = "VIEW" })
	local sys = w:CreateTab({ name = "SYS" })

	fight:CreateToggle({ name = "full power punches", description = "every punch winds up and releases at max charge - taps throw like you held all the way", flag = "fullpower", value = CFG.fullPower, callback = function(v) CFG.fullPower = v chargeWatch.active = false end })
	fight:CreateToggle({ name = "auto play", description = "full autopilot - chains zero-gap combos through their recovery, interrupts windups, rotates patterns so the AI can't adapt, covers when hurt - scale it with the aggression slider", flag = "autoplay", value = CFG.autoplay, callback = function(v) CFG.autoplay = v queue = {} end })
	fight:CreateSlider({ name = "aggression", description = "autopilot intensity - interrupt rate, damage it eats before covering up, and how hard it takes the ring", flag = "aggr", range = { 0, 1 }, increment = .05, value = CFG.aggr, callback = function(v) CFG.aggr = v end })
	fight:CreateToggle({ name = "inf stamina", description = "pin your stamina at full - punch while gassed, fatigue bar never drops", flag = "infsta", value = CFG.infSta, callback = function(v) CFG.infSta = v if not v then pcall(meterUnlimited, false) end end })
	fight:CreateToggle({ name = "auto-guard", description = "raise the right guard the frame their punch starts - style picks high/low", flag = "guard", value = CFG.guard, callback = function(v) CFG.guard = v end })
	fight:CreateDropdown({ name = "guard style", options = { "adaptive", "high", "low" }, value = CFG.guardStyle, flag = "guardStyle", callback = function(v) CFG.guardStyle = v end })
	fight:CreateToggle({ name = "combo engine", description = "throw combos in range - punches chain through the active action into the recovery frames, zero gap", flag = "combo", value = CFG.combo, callback = function(v) CFG.combo = v queue = {} end })
	fight:CreateToggle({ name = "punish low riders", description = "opponent camping the crouch? hold low guard, duck into body shots and answer with uppercuts - box turns orange while they camp", flag = "antilow", value = CFG.antiLow, callback = function(v) CFG.antiLow = v lowTrack.lowFor = 0 end })
	fight:CreateDropdown({ name = "combo", options = { "jab jab cross", "hooks", "mixup", "heavy hands", "kicks", "low rider" }, value = CFG.comboName, flag = "comboName", callback = function(v) CFG.comboName = v queue = {} end })
	fight:CreateToggle({ name = "step in", description = "walk into range while hunting (only with combo engine on)", flag = "stepin", value = CFG.stepIn, callback = function(v) CFG.stepIn = v end })
	fight:CreateToggle({ name = "auto-dodge", description = "slip + step out of the strike lane when their punch starts - ducks hooks, backs off kicks, always on when guard broken", flag = "dodge", value = CFG.dodge, callback = function(v) CFG.dodge = v end })
	fight:CreateSlider({ name = "punch range", description = "pelvis-to-pelvis studs before combos fire", range = { 2, 12 }, increment = .5, value = CFG.range, suffix = " st", callback = function(v) CFG.range = v end })
	fight:CreateSlider({ name = "stamina floor", description = "stop punching below this stamina share", range = { 0, .6 }, increment = .05, value = CFG.staminaFloor, callback = function(v) CFG.staminaFloor = v end })

	mySta = fight:CreateStat({ name = "my stamina", value = 0, suffix = "%" })
	myDaze = fight:CreateStat({ name = "my daze", value = 0, suffix = "" })
	oppSta = fight:CreateStat({ name = "their stamina", value = 0, suffix = "%" })
	oppDaze = fight:CreateStat({ name = "their daze", value = 0, suffix = "" })
	roundStat = fight:CreateStat({ name = "round", value = 0, suffix = "" })

	view:CreateToggle({ name = "opponent ESP", description = "box on their head - red while they swing - plus a range line", flag = "esp", value = CFG.esp, callback = function(v) CFG.esp = v end })

	sys:CreateButton({ name = "panic (P)", description = "everything off, hands back to you", callback = panic })
	sys:CreateButton({ name = "unload panel", description = "tear everything down", callback = shutdown })
end

buildUI()

_G.PhysBoxCorner = { cfg = CFG, window = window, stop = shutdown, panic = panic, punch = function(m) return pcall(Driver.punch, m) end, wraps = function() return Driver.punch == wrapPunch and (not origPress or Driver.press == wrapPress) end, lowInfo = function() return { maxHead = lowTrack.maxHead, lowFor = lowTrack.lowFor, camping = (lowTrack.lowFor or 0) > 0.5 } end, chargeInfo = function() local cs, ch, an = Driver.charge() return { cs = cs, charging = ch, action = an } end, aiInfo = function()
	local b = Driver.bout()
	local me = b and b.mine
	local opp
	if b then
		for _, bx in ipairs(b.boxers or {}) do
			if bx ~= me then opp = bx end
		end
	end
	return {
		winding = opp ~= nil and opp.action ~= nil and opp.action.charging == true,
		recovering = opp ~= nil and opp.action == nil and (os.clock() - oppPhase.endedAt) < 0.75,
		lastAct = oppPhase.lastAct,
		endedAgo = math.round((os.clock() - oppPhase.endedAt) * 100) / 100,
		lastCombo = oppPhase.lastCombo,
		oppDaze = opp and opp.daze or 0,
		queueLeft = #queue,
		myLast = myThrow.move,
		oppCharging = opp ~= nil and opp.action ~= nil and opp.action.charging == true,
		oppCharge = opp and opp.action and opp.action.chargeNow or 0,
		strikeAge = oppPhase.startedAt > 0 and math.round((os.clock() - oppPhase.startedAt) * 100) / 100 or nil,
	}
end }

print("[Corner] panel loaded - combo-king auto play, full power, dodges, anti-crouch, inf stamina | app state "
	.. (app and "found" or "NOT found (input override off)")
	.. (drawingOK and "" or " | Drawing unavailable - ESP off"))
end

--// dispatch -------------------------------------------------------------------

local place = game.PlaceId
local wired = Hub.GAMES[place]

if wired then
	print(string.format("[RugballHub] place %d -> %s  (%s)",
		place, wired.label, table.concat(wired.suites, ", ")))
	Hub.runAll(wired.suites)
	return
end

--// unknown place: picker -------------------------------------------------------

print("[RugballHub] place " .. tostring(place) .. " not wired - opening picker")

local okLib, Rayfield = pcall(function()
	return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)
if not okLib or type(Rayfield) ~= "table" then
	warn("[RugballHub] Rayfield failed to load, cannot open picker")
	return
end

if _G.RugballHub and _G.RugballHub.stop then
	pcall(_G.RugballHub.stop)
end

local win
local okWin = pcall(function()
	win = Rayfield:CreateWindow({
		name = "RUGBALL HUB",
		subtitle = "unknown place  |  pick a suite",
		sidebarLayout = true,
		showName = "RUGBALL HUB",
	})
end)
if not okWin or not win then
	warn("[RugballHub] picker window failed to build")
	return
end

_G.RugballHub = {
	panel = win,
	stop = function()
		pcall(function() win:Unload() end)
	end,
}

local tab = win:CreateTab({ name = "PICK" })

pcall(function()
	tab:CreateText({
		name = "PLACE " .. tostring(place),
		text = "this place is not wired in Hub.ORDER.\nforce any suite below, or wire the place id into the hub.",
	})
end)

for _, g in ipairs(Hub.ORDER) do
	pcall(function()
		tab:CreateButton({
			name = string.format("%s   [%d]", g.label, g.place),
			description = "runs: " .. table.concat(g.suites, " -> "),
			callback = function()
				Hub.runAll(g.suites)
			end,
		})
	end)
end

pcall(function()
	tab:CreateSection({ name = "SINGLE SUITES" })
end)
for _, sname in ipairs(Hub.SUITE_ORDER) do
	pcall(function()
		tab:CreateButton({
			name = Hub.SUITE_NAMES[sname],
			callback = function()
				Hub.run(sname)
			end,
		})
	end)
end

pcall(function()
	tab:CreateButton({
		name = "close picker",
		callback = function()
			_G.RugballHub.stop()
		end,
	})
end)

print(string.format("[RugballHub] picker open - %d games, %d suites", #Hub.ORDER, #Hub.SUITE_ORDER))