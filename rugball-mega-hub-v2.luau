--[[
	RUGBALL MEGA HUB v2 -- one file, every game, nothing fetched

	Every suite is embedded whole in this file and dispatched by game.PlaceId.
	One execute / loadstring, no web host, no readfile fallback, no chain
	files. The place you are in decides what comes up.

	place map
		81469298413354   Rugball                  football
		77844202849858   Rugball (place v2)       football
		80119315919763   Throw A Football (Drive Duels)  qb aimbot
		124617195142196  Build An Anime Character anime
		126424052816775  NBA: Heroes              nba, then swish
		122283827051026  NBA: Heroes (place v144) nba
		134954408729617  Basketball Duels         duels
		125942529011157  Throw A Football         qb aimbot (bypass built in)
		87966800745299   Throw A Football (7s)    qb aimbot
		96120449121277   PhysBox (HitBout)       physbox
		335760407        TPS: Street Soccer      tps
		75703135112691   TPS: Street Soccer      tps (match sub-place)
		82886081053523   Track & Field Legends   track
		14315258385      Realistic Street Soccer rss
		124780003623150  Realistic Ragdoll MMA   mma
		101880234193261  Car Soccer              carsoccer
		131576717722076  FD6 - Skyview           skyview
		108228062074817  Superhero Duels         superhero
		83048653078891   Criminal Simulator      criminal
		73251213967624   Criminal Simulator      criminal (live sub-place)

	the taf bypass suite is standalone now. Throw A Football's Drive Duels and 7s
	modes both run qb_aimbot, which carries the same MoveGuard/AnimGuard layers,
	so loading taf_bypass there would install the same hooks twice. The football
	panel is still used by the Rugball places.

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
	{ place = 80119315919763, label = "THROW A FOOTBALL DRIVE DUELS", suites = { "qb_aimbot" } },
	{ place = 124617195142196, label = "BUILD AN ANIME",   suites = { "anime" } },
	{ place = 126424052816775, label = "NBA HEROES",       suites = { "nba", "swish" } },
	{ place = 122283827051026, label = "NBA HEROES V144",  suites = { "nba" } },
	{ place = 134954408729617, label = "BASKETBALL DUELS", suites = { "duels" } },
	{ place = 125942529011157, label = "THROW A FOOTBALL", suites = { "qb_aimbot" } },
	{ place = 87966800745299,  label = "THROW A FOOTBALL 7S", suites = { "qb_aimbot" } },
	{ place = 96120449121277,  label = "PHYSBOX HITBOUT",  suites = { "physbox" } },
	{ place = 335760407,       label = "TPS STREET SOCCER", suites = { "tps" } },
	{ place = 75703135112691, label = "TPS MATCH",         suites = { "tps" } },
	{ place = 82886081053523, label = "TRACK & FIELD",     suites = { "track" } },
	{ place = 14315258385,    label = "RSS STREET SOCCER", suites = { "rss" } },
	{ place = 124780003623150, label = "REALISTIC RAGDOLL MMA", suites = { "mma" } },
	{ place = 101880234193261, label = "CAR SOCCER",       suites = { "carsoccer" } },
	{ place = 131576717722076, label = "FD6 - THE SKYVIEW EXPERIENCE", suites = { "skyview" } },
	{ place = 108228062074817, label = "SUPERHERO DUELS", suites = { "superhero" } },
	{ place = 83048653078891,  label = "CRIMINAL SIMULATOR", suites = { "criminal" } },
	{ place = 73251213967624,  label = "CRIMINAL SIMULATOR", suites = { "criminal" } },
}

Hub.GAMES = {}
for _, g in ipairs(Hub.ORDER) do
	Hub.GAMES[g.place] = g
end

-- fallback by universe id: an unwired sub-place of a known experience runs the
-- same suite chain. exact place ids above always win, so modes with their own
-- mapping (Drive Duels) keep it. Throw A Football / Albie's Arcade is
-- universe 10768235926; place 87966800745299 ("7s") is its live match place.
Hub.UNIVERSE = {
	[10768235926] = { "qb_aimbot" },
	[10774293033] = { "superhero" },
	[10769851460] = { "criminal" },
}

Hub.SUITE_ORDER = { "football", "anime", "nba", "swish", "duels", "qb_aimbot", "taf_bypass", "physbox", "tps", "track", "rss", "mma", "carsoccer", "skyview", "superhero", "criminal" }

Hub.SUITE_NAMES = {
	football   = "football panel    |  aim / tackle / block",
	anime      = "anime panel       |  claims / wheel / chairs",
	nba        = "nba panel         |  court suite",
	swish      = "swish             |  auto perfect shot",
	duels      = "duels panel       |  court panel",
	qb_aimbot  = "qb aimbot         |  ballistic solver / target lock / auto play / rebirth",
	taf_bypass = "taf bypass        |  moveguard / animguard / speed",
	physbox    = "physbox corner    |  autopilot / full power / inf stamina",
	tps        = "tps street         |  auto shot / tackle / GK / esp",
	track      = "track & field      |  auto race / auto field timing",
	rss        = "rss street          |  auto shot / pass / tackle / header / GK dive",
	mma        = "mma panel         |  fight / ground / rage / subs + hud",
	carsoccer  = "car soccer        |  autopilot / boost / ball path",
	skyview    = "skyview panel     |  esp / teleport / movement",
	superhero  = "superhero duels    |  auto put best stat / auto roll / probe",
	criminal   = "criminal simulator |  loot esp / prompt sniper / grab / movement",
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

--// embedded suite: football  (from football.luau) =========================
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

--// embedded suite: anime  (from anime.luau) =========================
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

--// embedded suite: nba  (from nba.luau) =========================
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

--// embedded suite: swish  (from swish.luau) =========================
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

--// embedded suite: duels  (from duels.luau) =========================
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

--// embedded suite: qb_aimbot  (from qb_aimbot.luau) =========================
Hub.SUITE.qb_aimbot = function()
--[[
	QB AIMBOT -- Throw A Football (place 125942529011157)
	Rayfield Gen2 | replace-not-stack via _G.SlimQbAim

	how a throw actually works in this game
	  every release funnels through BallController:Launch(position, velocity,
	  gravity, perfect, wobble, drift). the ball is simulated on the client and
	  the result is streamed to the server through Net.Cast, so the velocity
	  handed to Launch is the whole throw.

	  ThrowConfig owns the ballistics:
	    launchDirection(from, to)  lofted unit vector
	    idealSpeed(from, to)       exact speed to land on `to`
	    maxSpeed(power)            the player's own ceiling

	  so this suite never touches the camera and never fires a remote. it solves
	  the trajectory onto the chosen receiver's catch point and rewrites the
	  Launch arguments the game itself passes in. perfect is forced true and
	  wobble/drift are zeroed, which is exactly what a perfect release does.

	what "better" means here
	  * target = the receiver with the most separation from the nearest defender,
	    not the one closest to the crosshair. the defender list is the game's own
	    GameRigs.Away.Covers unit, and separation is measured to the catch point
	    and to the throw line, so a defender sitting under the route still counts
	    as coverage.
	  * the target lock pins the solver on one receiver of your choice while
	    auto target, lead, perfect release and power all keep running. it
	    follows the current offense and falls back to the auto pick when that
	    receiver is down or off the field.
	  * real players are read from Players and GameRigs.All as well as
	    Home.Receivers, so a human receiver is still throwable and every human
	    is labeled even when the game's AI receiver list is empty. opponents
	    stay coverage, and unknown-side players are marked P? and scored lower.
	  * the lead uses the game's own three-pass leadPoint loop, so a running
	    receiver is met where he will be, not where he is.
	  * BallController.Launch is wrapped, not replaced: the controller's state
	    machine, Thrown signal, reload and animation all still run.
	  * out-of-range throws are left alone instead of being fired at a clamped
	    speed, so the ball never dies short of the target.
	  * power assist is the game's own PowerAssist field; the rank override is
	    opt-in and off by default.
	  * auto throw drives the game's real throw input (a mouse click) instead of
	    calling Launch behind the controller's back. it waits for a clean look,
	    then charges and releases.
	  * auto play calls ModeController.StartGame, the same path the Play button
	    takes, so it obeys the lobby, tutorial and match state machine. it retries
	    whenever the game says a match cannot start yet. once a ball is in hand it
	    waits holdWait for separation and then releases even into tight coverage,
	    so a covered drive cannot stall.
	  * auto rebirth uses the Rebirth panel's own Request("Rebirth") path and only
	    fires when the profile money covers Formulas.rebirthCost for the next
	    level, so the server still validates every reset.

	keys
	  RightShift  master toggle        F  cycle locked receiver
	  G           auto target          H  visuals
	  T           auto throw           E  release now
	  LeftShift   sprint (MOVE: infinite + auto)
	  P           panic

	_G.SlimQbAim exports cfg, stats, pick, list, probe, catchProbe, playerProbe,
	throw, cycle, lock, unlock, next, locked, panic, stop, play, rebirth, farm,
	sprint, autoSprint.
--]]

if game.PlaceId ~= 125942529011157 then
	warn("[QBAIM] this suite is built for Throw A Football (125942529011157); running on " .. tostring(game.PlaceId))
end

local prev = _G.SlimQbAim
if prev and prev.stop then
	pcall(prev.stop)
end

-- the previous hub build shipped this suite as _G.SlimQBAimState and used
-- QBAimHud / QBAimEsp / QBAimThrow. shut that copy down too, otherwise its
-- Launch hook and HUD would survive the upgrade.
local legacy = _G.SlimQBAimState
if legacy and legacy.stop then
	pcall(legacy.stop)
end
_G.SlimQBAimState = nil

-- the aimbot now owns the bypass. if the standalone suite is already running
-- (old hub build, manual load), take it down first so its hooks are not layered
-- under ours and its panel does not sit next to this one.
local prevAc = _G.TafAcBypass or _G.SlimTafBypass
if prevAc and prevAc.stop then
	pcall(prevAc.stop)
end
_G.TafAcBypass = nil
_G.SlimTafBypass = nil

--// config --------------------------------------------------------------------

local DEFAULTS = {
	enabled = true,
	autoTarget = true,
	perfect = true,
	idealSpeed = true,
	powerAssist = true,
	powerBoost = false,
	snap = true,
	assistAngle = 45,
	esp = true,
	ring = true,
	labels = true,
	arc = true,
	defLines = false,
	playerEsp = true,
	playerTargets = true,
	playerCoverage = true,
	hud = true,
	autoThrow = false,
	safeCatch = false,
	autoDelay = 0.55,
	holdWait = 2.5,
	autoPlay = false,
	playDelay = 4,
	autoRebirth = false,
	rebirthDelay = 5,
	respectUi = true,
	minGap = 5,
	maxDistance = 300,
	speedCap = 110,
	lead = true,
	-- anti-cheat bypass (MoveGuard + AnimGuard + movement)
	closure = true,
	block = true,
	index = true,
	anim = true,
	animTracks = false,
	admin = false,
	inflate = false,
	rootStep = false,
	groundOnly = true,
	stepExtra = 20,
	infJump = false,
	customJump = false,
	jumpHeight = 20,
	lowGravity = false,
	gravity = 80,
	walkSpeed = false,
	walkSpeedValue = 30,
	infSprint = false,
	autoSprint = false,
	sprintSpeed = 32,
	spoofWalk = 18,
	spoofJumpPower = 50,
	spoofJumpHeight = 7.2,
	spoofGravity = 196.2,
}

local CFG = {}
for key, value in pairs(DEFAULTS) do
	CFG[key] = value
end

local CFG_FILE = "slimhub-qbaim.cfg"

local function loadCfg()
	if not (isfile and readfile and isfile(CFG_FILE)) then return end
	local ok, data = pcall(readfile, CFG_FILE)
	if not ok or type(data) ~= "string" then return end
	for line in string.gmatch(data, "[^\r\n]+") do
		local k, v = string.match(line, "^([%w_]+)=(.*)$")
		if k and CFG[k] ~= nil then
			if v == "true" then
				CFG[k] = true
			elseif v == "false" then
				CFG[k] = false
			elseif tonumber(v) then
				CFG[k] = tonumber(v)
			end
		end
	end
end

local function saveCfg()
	if not writefile then return end
	local keys = {}
	for k in pairs(CFG) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	local out = {}
	for _, k in ipairs(keys) do
		out[#out + 1] = k .. "=" .. tostring(CFG[k])
	end
	pcall(writefile, CFG_FILE, table.concat(out, "\n"))
end

loadCfg()

--// services ------------------------------------------------------------------

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LP = Players.LocalPlayer

local TAG = "SlimQbAim"
local HUD_NAME = "SlimQbAimHud"
local FX_NAME = "SlimQbAimFx"

-- anything an earlier build of this suite (or the old 17 KB one) left behind if
-- the session was reloaded without a clean unload. these names are specific
-- enough that clearing them cannot touch the game's own UI.
local function sweepLegacy()
	local pg = LP:FindFirstChild("PlayerGui")
	if pg then
		for _, name in ipairs({ "QBAimHud", "QBAimGui", "QBAimEsp", HUD_NAME }) do
			local inst = pg:FindFirstChild(name)
			if inst then
				pcall(function()
					inst:Destroy()
				end)
			end
		end
	end
	for _, name in ipairs({ "QBAimEsp", "QBAimArc", "QBAimFx", FX_NAME }) do
		local inst = Workspace:FindFirstChild(name)
		if inst then
			pcall(function()
				inst:Destroy()
			end)
		end
	end
	for _, name in ipairs({ "QBAim", "QBAimRender", "SlimQBAim", "SlimQbAcWalkSpeed" }) do
		pcall(function()
			RunService:UnbindFromRenderStep(name)
		end)
	end
end

sweepLegacy()

local OPEN_COLOR = Color3.fromRGB(120, 230, 140)
local CUT_COLOR = Color3.fromRGB(255, 96, 96)
local FAR_COLOR = Color3.fromRGB(255, 160, 60)
local LOCK_COLOR = Color3.fromRGB(255, 221, 35)

local dead = false
local inputConn = nil
local ui = { flags = {}, window = nil, status = nil, acState = nil, acCover = nil, acCounters = nil, acLogText = nil, farm = nil, lockDrop = nil, lockText = nil }
local hooks = { launch = false, snap = false, powerSaved = false, rankSaved = false }
local stats = { throws = 0, aimed = 0, auto = 0, plays = 0, rebirths = 0, lastSpeed = 0, missed = 0 }
local pick = nil
local targetList = {}
local cycle = 0
local lockSlot = nil
local lockName = nil
local lockMissingAt = nil
local lockSig = nil
local lockShown = nil
local lockOptions = {}
local lockSyncing = false
local manualPick = false
local lastBuild = 0
local lastHud = 0
local lastStatus = 0
local nextClick = 0
local autoAt = 0
local holdAt = 0
local statusLine = "starting"

--// anti-cheat bypass ---------------------------------------------------------
-- ported from the standalone taf_bypass suite so one script covers both jobs.
-- five client-side layers, none of which replicate:
--   closure  hookfunction on MoveGuard._check, the exact closure its loop calls
--   registry fallback if the controller module path changes
--   index    caps what game code reads for WalkSpeed/JumpPower/JumpHeight/Gravity
--   namecall drops AntiCheatGuard before the report leaves the client
--   anim     AnimWhitelist.allowed answers true, AnimTrackGuard.Prune stubbed
-- movement is separate: DriveExtras rewrites WalkSpeed to 18 every frame, so
-- root step moves the root part and direct speed re-writes WalkSpeed after it.

local ac = {
	reports = 0,
	blocked = 0,
	closures = 0,
	reads = 0,
	anim = 0,
	prunes = 0,
}

-- the anti-cheat internals run inside this block so their locals are freed at
-- the end of it; only the small exported surface below stays on the suite's
-- top-level local stack (Luau allows 200 locals per function).
do
ac.events = {}
local acLastEvent = 0
local acLastRemote = 0
local acLastGuard = 0
local acLastApply = 0
local acLastSync = 0
local acDefensePending = false

ac.remote = nil
local acGuard = nil
local acGuardSource = nil
local acGuardOriginal = nil
ac.closure = false
local acIndexTarget = nil

local acWhitelist = nil
local acWhitelistOriginal = nil
local acWhitelistHook = nil
local acWhitelistOn = false
local acTrackGuard = nil
local acTrackOriginal = nil
local acTrackHook = nil
local acTrackOn = false
local acWalkBound = false
local acSprintBound = false
local acSprintActive = false
local acHeartbeat = nil
local startAcTick

local acSaved = {
	admin = false,
	adminValue = nil,
	inflate = nil,
	inflateHumanoid = nil,
	jump = nil,
	jumpHumanoid = nil,
	gravity = nil,
	walkSpeed = nil,
	walkHumanoid = nil,
}

local function acLog(text)
	if dead then return end
	local now = os.clock()
	if now - acLastEvent < 0.05 then return end
	acLastEvent = now
	table.insert(ac.events, 1, os.date("%H:%M:%S") .. "  " .. tostring(text))
	while #ac.events > 12 do
		table.remove(ac.events)
	end
end

local function acNotify(text)
	print("[QBAIM/AC] " .. tostring(text))
	acLog(text)
	if ui.window and ui.window.Notify then
		pcall(function()
			ui.window:Notify({ title = "QB // BYPASS", content = tostring(text), duration = 3 })
		end)
	end
end

local function currentHumanoid()
	local ch = LP.Character
	return ch and ch:FindFirstChildOfClass("Humanoid") or nil
end

local function refreshAcRemote()
	local candidate = ReplicatedStorage:FindFirstChild("AntiCheatGuard")
	if candidate and candidate:IsA("BaseRemoteEvent") then
		ac.remote = candidate
	else
		ac.remote = nil
	end
end

local function guardFromRegistry()
	local ok, registry = pcall(getregistry)
	if not ok or type(registry) ~= "table" then return nil end
	for _, value in pairs(registry) do
		if type(value) == "table"
			and rawget(value, "CHECK") == 0.25
			and rawget(value, "HOLD") == 0.6
			and type(rawget(value, "_check")) == "function"
		then
			return value
		end
	end
	return nil
end

local function findGuard()
	local scripts = LP:FindFirstChild("PlayerScripts")
	local controllers = scripts and scripts:FindFirstChild("Controllers")
	local module = controllers and controllers:FindFirstChild("MoveGuard")
	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" and type(result._check) == "function" then
			acGuard = result
			acGuardSource = "module"
			return "module"
		end
	end
	local found = guardFromRegistry()
	if found then
		acGuard = found
		acGuardSource = "registry"
		return "registry"
	end
	acGuard = nil
	acGuardSource = nil
	return nil
end

local function installClosure()
	if dead or ac.closure then return ac.closure end
	startAcTick()
	if (not acGuard or type(acGuard._check) ~= "function") and not findGuard() then
		return false
	end
	local ok, original = pcall(hookfunction, acGuard._check, function()
		ac.closures = ac.closures + 1
	end)
	if ok and original then
		acGuardOriginal = original
		ac.closure = true
		acLog("closure attached via " .. tostring(acGuardSource))
		return true
	end
	return false
end

local function removeClosure()
	if not ac.closure then return end
	if acGuard and type(acGuard._check) == "function" and acGuardOriginal then
		pcall(hookfunction, acGuard._check, acGuardOriginal)
	end
	acGuardOriginal = nil
	ac.closure = false
end

local mt = nil
pcall(function()
	mt = getrawmetatable(game)
end)
local mtReadonly = true
if type(isreadonly) == "function" then
	local ok, value = pcall(isreadonly, mt)
	if ok and value ~= nil then
		mtReadonly = value
	end
end

local acIndexOld = nil
local acIndexHook = nil

local function writeMetatable(fn)
	if not mt then return false end
	local ok = pcall(function()
		setreadonly(mt, false)
		fn()
		setreadonly(mt, mtReadonly)
	end)
	if not ok then
		pcall(function()
			setreadonly(mt, mtReadonly)
		end)
	end
	return ok
end

local function installIndex()
	if not mt or acIndexHook then return acIndexHook ~= nil end
	startAcTick()
	acIndexOld = mt.__index
	if not acIndexOld then return false end
	acIndexHook = newcclosure(function(self, key)
		local value = acIndexOld(self, key)
		if dead or checkcaller() or type(key) ~= "string" then
			return value
		end
		if self == acIndexTarget then
			if key == "WalkSpeed" then
				ac.reads = ac.reads + 1
				if CFG.index then
					return math.min(value, CFG.spoofWalk)
				end
			elseif key == "JumpPower" then
				ac.reads = ac.reads + 1
				if CFG.index then
					return math.min(value, CFG.spoofJumpPower)
				end
			elseif key == "JumpHeight" then
				ac.reads = ac.reads + 1
				if CFG.index then
					return math.min(value, CFG.spoofJumpHeight)
				end
			end
		elseif self == Workspace and key == "Gravity" and CFG.lowGravity then
			ac.reads = ac.reads + 1
			if CFG.index then
				return math.max(value, CFG.spoofGravity or value)
			end
		end
		return value
	end, "qb_ac_index")
	local ok = writeMetatable(function()
		mt.__index = acIndexHook
	end)
	if not ok then
		acIndexHook = nil
		acIndexOld = nil
	end
	return ok
end

local function removeIndex()
	if not mt or not acIndexHook then return end
	writeMetatable(function()
		if mt.__index == acIndexHook then
			mt.__index = acIndexOld
		end
	end)
	acIndexHook = nil
	acIndexOld = nil
end

local acNamecallOld = nil
ac.namecallHook = nil

local function previewArgs(...)
	local count = select("#", ...)
	local parts = {}
	for i = 1, math.min(count, 4) do
		local value = select(i, ...)
		local ok, text = pcall(function()
			if typeof(value) == "Instance" then
				return value:GetFullName()
			end
			return tostring(value)
		end)
		text = ok and text or "?"
		if #text > 40 then
			text = string.sub(text, 1, 37) .. "..."
		end
		parts[#parts + 1] = text
	end
	return table.concat(parts, ", ")
end

local function handleReport(...)
	ac.reports = ac.reports + 1
	acLog("report  " .. previewArgs(...))
	if CFG.block then
		ac.blocked = ac.blocked + 1
		return true
	end
	if not (CFG.closure or CFG.admin or CFG.inflate) then
		acDefensePending = true
	end
	return false
end

local function installNamecall()
	if not mt or ac.namecallHook then return ac.namecallHook ~= nil end
	startAcTick()
	acNamecallOld = mt.__namecall
	if not acNamecallOld then return false end
	ac.namecallHook = newcclosure(function(self, ...)
		if not dead and not checkcaller() then
			local ok, method = pcall(getnamecallmethod)
			if ok and (method == "FireServer" or method == "InvokeServer") then
				local isGuard = self == ac.remote
				if not isGuard and typeof(self) == "Instance" and self.Name == "AntiCheatGuard" then
					isGuard = self:IsA("BaseRemoteEvent")
				end
				if isGuard and handleReport(...) then
					return nil
				end
			end
		end
		return acNamecallOld(self, ...)
	end, "qb_ac_namecall")
	local ok = writeMetatable(function()
		mt.__namecall = ac.namecallHook
	end)
	if not ok then
		ac.namecallHook = nil
		acNamecallOld = nil
	end
	return ok
end

local function removeNamecall()
	if not mt or not ac.namecallHook then return end
	writeMetatable(function()
		if mt.__namecall == ac.namecallHook then
			mt.__namecall = acNamecallOld
		end
	end)
	ac.namecallHook = nil
	acNamecallOld = nil
end

local function applyAdmin(on)
	if on then
		startAcTick()
		if not acSaved.admin then
			acSaved.admin = true
			acSaved.adminValue = LP:GetAttribute("ACAdmin")
		end
		LP:SetAttribute("ACAdmin", true)
	elseif acSaved.admin then
		LP:SetAttribute("ACAdmin", acSaved.adminValue)
		acSaved.admin = false
		acSaved.adminValue = nil
	end
end

local function applyInflate(on)
	local humanoid = currentHumanoid()
	if on then
		startAcTick()
		if humanoid then
			if not acSaved.inflate then
				acSaved.inflate = {
					walk = humanoid:GetAttribute("ACWalk"),
					jumpPower = humanoid:GetAttribute("ACJumpPower"),
					jumpHeight = humanoid:GetAttribute("ACJumpHeight"),
					cap = Workspace:GetAttribute("ACWalkCap"),
					gravity = Workspace:GetAttribute("ACGravity"),
				}
				acSaved.inflateHumanoid = humanoid
			elseif acSaved.inflateHumanoid ~= humanoid then
				acSaved.inflateHumanoid = humanoid
				acSaved.inflate.walk = humanoid:GetAttribute("ACWalk")
				acSaved.inflate.jumpPower = humanoid:GetAttribute("ACJumpPower")
				acSaved.inflate.jumpHeight = humanoid:GetAttribute("ACJumpHeight")
			end
			humanoid:SetAttribute("ACWalk", 999)
			humanoid:SetAttribute("ACJumpPower", 999)
			humanoid:SetAttribute("ACJumpHeight", 999)
		end
		Workspace:SetAttribute("ACWalkCap", 999)
		if CFG.lowGravity then
			Workspace:SetAttribute("ACGravity", Workspace.Gravity)
		end
	elseif acSaved.inflate then
		local original = acSaved.inflate
		local target = acSaved.inflateHumanoid or humanoid
		if target then
			target:SetAttribute("ACWalk", original.walk)
			target:SetAttribute("ACJumpPower", original.jumpPower)
			target:SetAttribute("ACJumpHeight", original.jumpHeight)
		end
		Workspace:SetAttribute("ACWalkCap", original.cap)
		Workspace:SetAttribute("ACGravity", original.gravity)
		acSaved.inflate = nil
		acSaved.inflateHumanoid = nil
	end
end

local function applyJump(on)
	local humanoid = currentHumanoid()
	if not humanoid then return end
	if on then
		startAcTick()
		if not acSaved.jump or acSaved.jumpHumanoid ~= humanoid then
			acSaved.jump = {
				use = humanoid.UseJumpPower,
				power = humanoid.JumpPower,
				height = humanoid.JumpHeight,
			}
			acSaved.jumpHumanoid = humanoid
		end
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = CFG.jumpHeight
	elseif acSaved.jump then
		local original = acSaved.jump
		local target = acSaved.jumpHumanoid or humanoid
		target.UseJumpPower = original.use
		target.JumpPower = original.power
		target.JumpHeight = original.height
		acSaved.jump = nil
		acSaved.jumpHumanoid = nil
	end
end

local function applyGravity(on)
	if on then
		startAcTick()
		if not acSaved.gravity then
			acSaved.gravity = Workspace.Gravity
			CFG.spoofGravity = acSaved.gravity
		end
		Workspace.Gravity = CFG.gravity
		if CFG.inflate then
			Workspace:SetAttribute("ACGravity", CFG.gravity)
		end
	elseif acSaved.gravity then
		Workspace.Gravity = acSaved.gravity
		if CFG.inflate then
			Workspace:SetAttribute("ACGravity", acSaved.gravity)
		end
		acSaved.gravity = nil
	end
end

local function installAnim()
	if acWhitelistOn then return true end
	startAcTick()
	local module = nil
	local ok = pcall(function()
		local shared = ReplicatedStorage:FindFirstChild("Shared")
		local inst = shared and shared:FindFirstChild("AnimWhitelist")
		if inst then
			module = require(inst)
		end
	end)
	if not (ok and type(module) == "table" and type(module.allowed) == "function") then
		return false
	end
	acWhitelist = module
	acWhitelistOriginal = module.allowed
	acWhitelistHook = function(...)
		ac.anim = ac.anim + 1
		if dead then
			return acWhitelistOriginal(...)
		end
		return true
	end
	module.allowed = acWhitelistHook
	acWhitelistOn = true
	acLog("AnimGuard whitelist detached")
	return true
end

local function removeAnim()
	if not acWhitelistOn or not acWhitelist then return end
	pcall(function()
		if acWhitelist.allowed == acWhitelistHook then
			acWhitelist.allowed = acWhitelistOriginal
		end
	end)
	acWhitelistOn = false
	acWhitelistOriginal = nil
	acWhitelistHook = nil
end

local function installTrackGuard()
	if acTrackOn then return true end
	startAcTick()
	local module = nil
	local ok = pcall(function()
		local taf = ReplicatedStorage:FindFirstChild("TAF_Shared")
		local client = taf and taf:FindFirstChild("Client")
		local inst = client and client:FindFirstChild("AnimTrackGuard")
		if inst then
			module = require(inst)
		end
	end)
	if not (ok and type(module) == "table" and type(module.Prune) == "function") then
		return false
	end
	acTrackGuard = module
	acTrackOriginal = module.Prune
	acTrackHook = function()
		ac.prunes = ac.prunes + 1
		return 0
	end
	module.Prune = acTrackHook
	acTrackOn = true
	return true
end

local function removeTrackGuard()
	if not acTrackOn or not acTrackGuard then return end
	pcall(function()
		if acTrackGuard.Prune == acTrackHook then
			acTrackGuard.Prune = acTrackOriginal
		end
	end)
	acTrackOn = false
	acTrackOriginal = nil
	acTrackHook = nil
end

local function applyWalkSpeed(on)
	local humanoid = currentHumanoid()
	if on then
		startAcTick()
		if humanoid and acSaved.walkHumanoid ~= humanoid then
			acSaved.walkHumanoid = humanoid
			acSaved.walkSpeed = humanoid.WalkSpeed
		end
		if not acWalkBound then
			RunService:BindToRenderStep("SlimQbAcWalkSpeed", Enum.RenderPriority.Camera.Value + 3, function()
				if dead or not CFG.walkSpeed then return end
				local hum = currentHumanoid()
				if not hum then return end
				if acSaved.walkHumanoid ~= hum then
					acSaved.walkHumanoid = hum
					acSaved.walkSpeed = hum.WalkSpeed
				end
				hum.WalkSpeed = CFG.walkSpeedValue
			end)
			acWalkBound = true
		end
	else
		if acWalkBound then
			pcall(function()
				RunService:UnbindFromRenderStep("SlimQbAcWalkSpeed")
			end)
			acWalkBound = false
		end
		local target = acSaved.walkHumanoid or humanoid
		if target and acSaved.walkSpeed then
			target.WalkSpeed = acSaved.walkSpeed
		end
		acSaved.walkHumanoid = nil
		acSaved.walkSpeed = nil
	end
end

-- sprint is the same contract as the walk override: write WalkSpeed after the
-- controller's own write on the same frame (Camera+3 is the walk layer, this is
-- Camera+4), so DriveExtras cannot overwrite it back to 18. no stamina is read
-- or spent because the game's sprint action is never invoked; the speed is ours.
local function sprintEnabled()
	return CFG.infSprint or CFG.autoSprint
end

local function sprintWanted(humanoid)
	if CFG.autoSprint then
		return humanoid.MoveDirection.Magnitude > 0.05
	end
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
end

local function applySprint(on)
	if on then
		startAcTick()
		if not acSprintBound then
			RunService:BindToRenderStep("SlimQbSprint", Enum.RenderPriority.Camera.Value + 4, function()
				if dead or not sprintEnabled() then return end
				local hum = currentHumanoid()
				if not hum or hum.Health <= 0 or hum.SeatPart then return end
				if sprintWanted(hum) then
					hum.WalkSpeed = math.max(CFG.sprintSpeed, CFG.walkSpeed and CFG.walkSpeedValue or 0)
					acSprintActive = true
				elseif acSprintActive then
					acSprintActive = false
					if not CFG.walkSpeed then
						hum.WalkSpeed = CFG.spoofWalk
					end
				end
			end)
			acSprintBound = true
		end
	else
		if acSprintBound then
			pcall(function()
				RunService:UnbindFromRenderStep("SlimQbSprint")
			end)
			acSprintBound = false
		end
		acSprintActive = false
		local hum = currentHumanoid()
		if hum and not CFG.walkSpeed then
			hum.WalkSpeed = CFG.spoofWalk
		end
	end
end

local function stepTick(dt)
	local humanoid = currentHumanoid()
	local character = LP.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) then return end
	if humanoid.SeatPart then return end
	if CFG.groundOnly and humanoid.FloorMaterial == Enum.Material.Air then return end
	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.05 then return end
	root.CFrame = root.CFrame + direction.Unit * (CFG.stepExtra * math.min(dt, 0.1))
end

ac.jumpConn = UserInputService.JumpRequest:Connect(function()
	if dead or not CFG.infJump then return end
	local humanoid = currentHumanoid()
	if humanoid and humanoid.Health > 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end)

local function acStateText()
	return string.format(
		"closure %s  |  block %s  |  index %s  |  anim %s",
		ac.closure and "ON" or "off",
		ac.namecallHook and (CFG.block and "ON" or "watch") or "off",
		acIndexHook and (CFG.index and "ON" or "watch") or "off",
		acWhitelistOn and "ON" or "off"
	)
end

local function acCoverageText()
	if ac.closure then
		return "guard coverage: closure"
	end
	if CFG.admin then
		return "guard coverage: ACAdmin attribute"
	end
	if CFG.inflate then
		return "guard coverage: attribute inflation"
	end
	return "guard coverage: NONE - MoveGuard will clamp and report"
end

local function bypassTick(dt)
	if dead then return end
	local now = os.clock()

	if now - acLastRemote > 3 then
		acLastRemote = now
		refreshAcRemote()
	end

	acIndexTarget = currentHumanoid()

	if now - acLastGuard > 2 then
		acLastGuard = now
		if CFG.closure and not ac.closure then installClosure() end
		if CFG.anim and not acWhitelistOn then installAnim() end
		if CFG.animTracks and not acTrackOn then installTrackGuard() end
		if CFG.walkSpeed and not acWalkBound then applyWalkSpeed(true) end
		if sprintEnabled() and not acSprintBound then applySprint(true) end
	end

	if now - acLastApply > 0.5 then
		acLastApply = now
		if CFG.admin then
			LP:SetAttribute("ACAdmin", true)
		end
		if CFG.inflate then
			applyInflate(true)
		end
		if CFG.customJump then
			local humanoid = currentHumanoid()
			if humanoid then
				humanoid.UseJumpPower = false
				humanoid.JumpHeight = CFG.jumpHeight
			end
		end
		if CFG.lowGravity then
			Workspace.Gravity = CFG.gravity
			if CFG.inflate then
				Workspace:SetAttribute("ACGravity", CFG.gravity)
			end
		end
	end

	if acDefensePending then
		acDefensePending = false
		CFG.admin = true
		CFG.inflate = true
		applyAdmin(true)
		applyInflate(true)
		pcall(function()
			if ui.window then
				ui.window:Set("qb_ac_admin", true)
				ui.window:Set("qb_ac_inflate", true)
			end
		end)
		acNotify("a report escaped - ACAdmin and inflation armed as cover")
	end

	if CFG.rootStep then
		pcall(stepTick, dt)
	end

	if now - acLastSync > 0.4 then
		acLastSync = now
		if ui.acState then
			pcall(function()
				ui.acState:Set(acStateText())
			end)
		end
		if ui.acCover then
			pcall(function()
				ui.acCover:Set(acCoverageText())
			end)
		end
		if ui.acCounters then
			pcall(function()
				ui.acCounters:Set(string.format(
					"reports %d  |  blocked %d\nclosure %d  |  index %d  |  anim %d  |  prunes %d",
					ac.reports, ac.blocked, ac.closures, ac.reads, ac.anim, ac.prunes
				))
			end)
		end
		if ui.acLogText then
			pcall(function()
				ui.acLogText:Set(#ac.events > 0 and table.concat(ac.events, "\n") or "-")
			end)
		end
	end
end

startAcTick = function()
	if acHeartbeat or dead then return end
	acHeartbeat = RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(bypassTick, dt)
		if not ok then
			warn("[QBAIM/AC] tick: " .. tostring(err))
		end
	end)
end

local function installBypass()
	refreshAcRemote()
	findGuard()
	acIndexTarget = currentHumanoid()
	startAcTick()
	if CFG.closure then installClosure() end
	installNamecall()
	if CFG.index then installIndex() end
	if CFG.anim then installAnim() end
	if CFG.animTracks then installTrackGuard() end
	if CFG.walkSpeed then applyWalkSpeed(true) end
	if sprintEnabled() then applySprint(true) end
	if CFG.admin then applyAdmin(true) end
	if CFG.inflate then applyInflate(true) end
	if CFG.customJump then applyJump(true) end
	if CFG.lowGravity then applyGravity(true) end
end

local function applyBypassAll()
	if CFG.closure then installClosure() else removeClosure() end
	installNamecall()
	if CFG.index then installIndex() else removeIndex() end
	if CFG.anim then installAnim() else removeAnim() end
	if CFG.animTracks then installTrackGuard() else removeTrackGuard() end
	if CFG.walkSpeed then applyWalkSpeed(true) else applyWalkSpeed(false) end
	if sprintEnabled() then applySprint(true) else applySprint(false) end
	if CFG.admin then applyAdmin(true) else applyAdmin(false) end
	if CFG.inflate then applyInflate(true) else applyInflate(false) end
	if CFG.customJump then applyJump(true) else applyJump(false) end
	if CFG.lowGravity then applyGravity(true) else applyGravity(false) end
end

local function stopBypass()
	if acHeartbeat then
		pcall(function()
			acHeartbeat:Disconnect()
		end)
		acHeartbeat = nil
	end
	applyWalkSpeed(false)
	applySprint(false)
	removeAnim()
	removeTrackGuard()
	removeNamecall()
	removeIndex()
	removeClosure()
	applyAdmin(false)
	applyInflate(false)
	applyJump(false)
	applyGravity(false)
end

local function acProbe()
	return string.format(
		"ac closure=%s namecall=%s index=%s anim=%s reports=%d blocked=%d reads=%d guard=%s",
		tostring(ac.closure), tostring(ac.namecallHook ~= nil), tostring(acIndexHook ~= nil),
		tostring(acWhitelistOn), ac.reports, ac.blocked, ac.reads, tostring(acGuardSource)
	)
end

-- exported surface: the UI, panic and public API only need these handles
ac.notify = acNotify
ac.refreshRemote = refreshAcRemote
ac.findGuard = findGuard
ac.installClosure = installClosure
ac.removeClosure = removeClosure
ac.installIndex = installIndex
ac.removeIndex = removeIndex
ac.installNamecall = installNamecall
ac.applyAdmin = applyAdmin
ac.applyInflate = applyInflate
ac.applyJump = applyJump
ac.applyGravity = applyGravity
ac.installAnim = installAnim
ac.removeAnim = removeAnim
ac.installTrackGuard = installTrackGuard
ac.removeTrackGuard = removeTrackGuard
ac.applyWalkSpeed = applyWalkSpeed
ac.sprintEnabled = sprintEnabled
ac.applySprint = applySprint
ac.stateText = acStateText
ac.coverageText = acCoverageText
ac.installBypass = installBypass
ac.applyBypassAll = applyBypassAll
ac.stopBypass = stopBypass
ac.probe = acProbe
end

--// modules -------------------------------------------------------------------

local function softRequire(inst)
	if not inst then return nil end
	local ok, mod = pcall(require, inst)
	if ok then return mod end
	return nil
end

local PlayerScripts = LP:FindFirstChild("PlayerScripts")
	or LP:WaitForChild("PlayerScripts", 20)
local Controllers = PlayerScripts and (PlayerScripts:FindFirstChild("Controllers")
	or PlayerScripts:WaitForChild("Controllers", 20))

local TC = softRequire(Controllers and Controllers:FindFirstChild("ThrowController"))
local GR = softRequire(Controllers and Controllers:FindFirstChild("GameRigs"))
local DC = softRequire(Controllers and Controllers:FindFirstChild("DataController"))
local CamCtl = softRequire(Controllers and Controllers:FindFirstChild("CameraController"))
local BC = softRequire(Controllers and Controllers:FindFirstChild("BallController"))

local TAF = ReplicatedStorage:FindFirstChild("TAF_Shared")
local Shared = TAF and TAF:FindFirstChild("Shared")
local TCfg = softRequire(Shared and Shared:FindFirstChild("ThrowConfig"))
local GCfg = softRequire(Shared and Shared:FindFirstChild("GameConfig"))
local Formulas = softRequire(Shared and Shared:FindFirstChild("Formulas"))

if not BC and TAF then
	local Client = TAF:FindFirstChild("Client")
	BC = softRequire(Client and Client:FindFirstChild("BallController"))
end

-- the hub can run before every controller module has finished requiring, so
-- give the important ones a bounded retry instead of silently doing nothing.
if not (TC and BC and TCfg) then
	local deadline = os.clock() + 12
	repeat
		task.wait(0.25)
		if not Controllers and PlayerScripts then
			Controllers = PlayerScripts:FindFirstChild("Controllers")
		end
		if Controllers then
			TC = TC or softRequire(Controllers:FindFirstChild("ThrowController"))
			GR = GR or softRequire(Controllers:FindFirstChild("GameRigs"))
			DC = DC or softRequire(Controllers:FindFirstChild("DataController"))
			CamCtl = CamCtl or softRequire(Controllers:FindFirstChild("CameraController"))
			BC = BC or softRequire(Controllers:FindFirstChild("BallController"))
		end
		TAF = TAF or ReplicatedStorage:FindFirstChild("TAF_Shared")
		Shared = Shared or (TAF and TAF:FindFirstChild("Shared"))
		TCfg = TCfg or softRequire(Shared and Shared:FindFirstChild("ThrowConfig"))
	until (TC and BC and TCfg) or os.clock() > deadline
end

if not (TC and BC and TCfg) then
	if ac.jumpConn then
		pcall(function()
			ac.jumpConn:Disconnect()
		end)
		ac.jumpConn = nil
	end
	warn("[QBAIM] game modules are not ready yet (throw/ball controller or throw config missing); run the suite again once the match has loaded")
	return
end

local HANDS = tonumber(GCfg and GCfg.HandsHeight) or 1.3
local GRAVITY = tonumber(TCfg.Gravity) or 40

--// auto play + rebirth --------------------------------------------------------
-- ModeController owns the lobby/match state machine ("Practice", "Game",
-- "Encounter", "Spectate"). StartGame asks the server for GameStart and only
-- works outside a live game, so the loop below is a queue tick, not a teleport.
-- RebirthPanel:Request("Rebirth") is the same path the panel button takes; the
-- server validates the cost and owns the reset.

local ModeCtl = nil
local PanelCtl = nil
local playAt = 0
local rebirthAt = 0
local playPending = false
local rebirthPending = false
local lastMode = nil

local function requireController(name)
	local inst = Controllers and Controllers:FindFirstChild(name)
	if not inst then return nil end
	local ok, mod = pcall(require, inst)
	if ok and type(mod) == "table" then
		return mod
	end
	return nil
end

local function modeController()
	if not ModeCtl then
		ModeCtl = requireController("ModeController")
	end
	return ModeCtl
end

local function panelController()
	if not PanelCtl then
		PanelCtl = requireController("PanelController")
	end
	return PanelCtl
end

local function rebirthCost(level)
	if Formulas and type(Formulas.rebirthCost) == "function" then
		local ok, value = pcall(Formulas.rebirthCost, level)
		if ok and tonumber(value) then
			return tonumber(value)
		end
	end
	return math.floor(7500 * 2.5 ^ math.max(0, tonumber(level) or 0) + 0.5)
end

local function shortMoney(value)
	local n = tonumber(value) or 0
	if n >= 1e9 then
		return string.format("%.2fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.2fM", n / 1e6)
	elseif n >= 1e3 then
		return string.format("%.1fK", n / 1e3)
	end
	return string.format("%d", n)
end

local function profileNumber(name)
	local value = LP:GetAttribute(name)
	if value == nil then
		local dc = DC
		local profile = dc and dc.Profile
		if type(profile) == "table" then
			value = profile[name]
		end
	end
	return tonumber(value)
end

local function farmText()
	local mc = modeController()
	local level = profileNumber("Rebirths") or 0
	local money = profileNumber("Money") or 0
	local cost = rebirthCost(level)
	return string.format(
		"mode %s  |  R%d  |  $%s of $%s  |  plays %d  |  rebirths %d",
		tostring(mc and mc.Mode or "?"), level, shortMoney(money), shortMoney(cost),
		stats.plays, stats.rebirths
	)
end

local function startMatch()
	if playPending then return end
	local mc = modeController()
	if not mc then
		statusLine = "auto play: controller missing"
		return
	end
	playPending = true
	task.spawn(function()
		local ok, started, why = pcall(mc.StartGame, mc)
		playPending = false
		if ok and started then
			stats.plays = stats.plays + 1
			stats.lastPlay = os.date("%H:%M:%S")
			statusLine = "auto play: match " .. tostring(stats.plays) .. " started"
		else
			statusLine = "auto play: " .. tostring(ok and why or started)
		end
	end)
end

local function requestRebirth()
	if rebirthPending then return end
	local pc = panelController()
	if not pc then
		statusLine = "auto rebirth: controller missing"
		return
	end
	rebirthPending = true
	local before = profileNumber("Rebirths") or 0
	task.spawn(function()
		local ok, result = pcall(pc.Request, pc, "Rebirth")
		rebirthPending = false
		if not (ok and result) then
			statusLine = "auto rebirth: request refused"
			rebirthAt = os.clock() + 8
			return
		end
		local deadline = os.clock() + 3
		local after = before
		repeat
			task.wait(0.2)
			after = profileNumber("Rebirths") or before
		until after > before or os.clock() > deadline
		if after > before then
			stats.rebirths = stats.rebirths + 1
			stats.lastRebirth = string.format("R%d to R%d", before, after)
			statusLine = "auto rebirth: R" .. tostring(after)
		else
			statusLine = "auto rebirth: server held it"
			rebirthAt = os.clock() + 10
		end
	end)
end

local function autoFarmStep(now)
	if dead then return end
	if CFG.autoPlay then
		local mc = modeController()
		if mc then
			local mode = tostring(mc.Mode or "?")
			if mode ~= lastMode then
				lastMode = mode
				if mode ~= "Game" then
					statusLine = "auto play: " .. mode:lower()
				end
			end
			if mode ~= "Game" and now >= playAt and not playPending then
				playAt = now + math.max(2, tonumber(CFG.playDelay) or 4)
				local ok, can, reason = pcall(mc.CanStart, mc)
				if ok and can then
					startMatch()
				elseif ok then
					statusLine = "auto play: " .. tostring(reason)
				end
			end
		end
	end
	if CFG.autoRebirth and now >= rebirthAt and not rebirthPending then
		rebirthAt = now + math.max(3, tonumber(CFG.rebirthDelay) or 5)
		local level = profileNumber("Rebirths") or 0
		local money = profileNumber("Money") or 0
		local cost = rebirthCost(level)
		if money >= cost then
			requestRebirth()
		end
	end
end

--// rig model -----------------------------------------------------------------

local trackers = setmetatable({}, { __mode = "k" })

local function baseOf(r)
	local root = r.Root
	local rp = root and root.Parent and root.Position or nil
	local p = r.Pos
	if typeof(p) == "Vector3" then
		if not rp then
			return p
		end
		-- the rig's own root wins when Pos has gone stale (lobby leftovers sit
		-- thousands of studs away from the live character).
		local dx = p.X - rp.X
		local dz = p.Z - rp.Z
		if dx * dx + dz * dz <= 144 then
			return p
		end
	end
	if rp then
		return rp - Vector3.new(0, 3, 0)
	end
	return nil
end

local function catchOf(r, base)
	local spot = r.PassSpot
	if typeof(spot) == "Vector3" then
		if (spot - base).Magnitude <= 18 then
			return spot
		end
	end
	local scale = tonumber(r.Scale) or 1
	return Vector3.new(base.X, base.Y + (3 + HANDS) * scale, base.Z)
end

local function velOf(r, base, now)
	local v = r.Vel
	if typeof(v) == "Vector3" and v.Magnitude > 0.5 then
		return v
	end
	local t = trackers[r]
	if not t then
		trackers[r] = { p = base, t = now, v = Vector3.zero }
		return Vector3.zero
	end
	local dt = now - t.t
	if dt >= 0.05 then
		local raw = (base - t.p) / dt
		if raw.Magnitude > 120 then
			raw = Vector3.zero
		end
		t.v = t.v:Lerp(raw, 0.35)
		t.p = base
		t.t = now
	end
	return t.v
end

-- exactly the loop ThrowController uses for its own lead, so the aim point is
-- the game's aim point rather than a different approximation.
local function leadPoint(from, point, vel)
	if not vel or vel.Magnitude < 0.5 then
		return point
	end
	local p = point
	for _ = 1, 3 do
		local dir = TCfg.launchDirection(from, p)
		local speed = TCfg.idealSpeed(from, p, dir)
		if not speed then
			break
		end
		local horiz = speed * math.sqrt(dir.X * dir.X + dir.Z * dir.Z)
		if horiz < 0.01 then
			break
		end
		p = point + vel * ((Vector3.new(p.X - from.X, 0, p.Z - from.Z)).Magnitude / horiz)
	end
	return p
end

-- real players are not guaranteed to be in GameRigs.Home.Receivers. the game
-- keeps its AI route runners there, while a human receiver can exist only as a
-- character in Workspace and as an entry in GameRigs.All. these helpers build a
-- throwable record for the real character and use the rig Side / Player.Team
-- only to keep opponents out of the receiver list.
local playerRigs = setmetatable({}, { __mode = "k" })
local playerSlotSeq = 0

local function rootOfRig(r)
	if type(r) ~= "table" then
		return nil
	end
	local root = r.Root
	if typeof(root) == "Instance" then
		if root:IsA("BasePart") then
			return root
		end
		if root:IsA("Model") and root.PrimaryPart then
			return root.PrimaryPart
		end
		local part = root:FindFirstChild("HumanoidRootPart") or root:FindFirstChildWhichIsA("BasePart")
		if part then
			return part
		end
	end
	return nil
end

local function descendantOf(inst, parent)
	if typeof(inst) ~= "Instance" or typeof(parent) ~= "Instance" then
		return false
	end
	local ok, res = pcall(function()
		return inst:IsDescendantOf(parent)
	end)
	return ok and res
end

local function rootMatchesList(root, list)
	if typeof(root) ~= "Instance" or type(list) ~= "table" then
		return false
	end
	for _, r in ipairs(list) do
		if type(r) == "table" then
			local rr = rootOfRig(r)
			if rr and (rr == root or descendantOf(root, rr.Parent) or descendantOf(rr, root.Parent)) then
				return true
			end
		end
	end
	return false
end

local function rigSideOfRoot(root)
	if typeof(root) ~= "Instance" then
		return nil
	end
	local all = GR and GR.All
	if type(all) ~= "table" then
		return nil
	end
	for _, r in ipairs(all) do
		if type(r) == "table" then
			local rr = rootOfRig(r)
			if rr and (rr == root or descendantOf(root, rr.Parent) or descendantOf(rr, root.Parent)) then
				local side = tostring(r.Side or "")
				if side ~= "" then
					return side
				end
			end
		end
	end
	return nil
end

local function localSide()
	local ch = LP.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local side = root and rigSideOfRoot(root) or nil
	if side then
		return side
	end
	local all = GR and GR.All
	if type(all) == "table" then
		for _, r in ipairs(all) do
			if type(r) == "table" then
				local nm = tostring(r.Name or "")
				if nm ~= "" and (nm == LP.Name or nm == LP.DisplayName) then
					local s = tostring(r.Side or "")
					if s ~= "" then
						return s
					end
				end
			end
		end
	end
	return nil
end

-- true = same side, false = other side, nil = the game gives us no side for
-- this player. nil is treated as a possible receiver so a human route runner
-- is still selectable, but it is scored below a known receiver.
local function playerOnSide(player, side)
	if player.Team and LP.Team then
		return player.Team == LP.Team
	end
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local ps = root and rigSideOfRoot(root) or nil
	if ps and side then
		return ps == side
	end
	-- last resort: the game's own unit lists. a character that is one of your
	-- Home receivers is on your side; a character in Away.Covers is not.
	local recs = GR and GR.Home and GR.Home.Receivers
	if root and rootMatchesList(root, recs) then
		return true
	end
	local covers = GR and GR.Away and GR.Away.Covers
	if root and rootMatchesList(root, covers) then
		return false
	end
	return nil
end

local function playerRig(player, index)
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then
		playerRigs[player] = nil
		return nil
	end
	local rec = playerRigs[player]
	if not rec then
		playerSlotSeq = playerSlotSeq + 1
		rec = {
			Slot = -1000 - playerSlotSeq,
			Job = "Catch",
			Scale = 1,
			Player = player,
		}
		playerRigs[player] = rec
	end
	local v = root.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude > 60 then
		flat = Vector3.zero
	end
	-- Pos on a GameRigs record is the feet/base point, and catchOf adds the
	-- body height on top of it. keep the synthetic record in the same space.
	rec.Root = root
	rec.Pos = root.Position - Vector3.new(0, 3, 0)
	rec.Vel = flat
	rec.Name = player.DisplayName or player.Name
	rec.Slot = rec.Slot or (-1000 - index)
	return rec
end

local function receiverRigs(side)
	local out = {}
	local seen = {}
	local function add(r)
		if type(r) ~= "table" then
			return
		end
		local root = rootOfRig(r)
		local name = tostring(r.Name or "")
		if root and descendantOf(root, LP.Character) then
			return
		end
		if name ~= "" and (name == LP.Name or name == LP.DisplayName) then
			return
		end
		local key = root or r
		if seen[key] then
			return
		end
		seen[key] = true
		out[#out + 1] = r
	end

	local recs = GR and GR.Home and GR.Home.Receivers
	if type(recs) == "table" then
		for i = 1, #recs do
			add(recs[i])
		end
	end

	-- a human receiver can be in GameRigs.All without being in Home.Receivers.
	-- PassSpot is what makes a rig an eligible target; only use it as a fallback
	-- when the local side is known, so the old Side mix-up cannot return.
	if side and type(GR and GR.All) == "table" then
		for _, r in ipairs(GR.All) do
			if type(r) == "table" and tostring(r.Side or "") == side then
				local job = tostring(r.Job or "")
				if typeof(r.PassSpot) == "Vector3" or job == "Catch" then
					add(r)
				end
			end
		end
	end

	if CFG.playerTargets then
		local index = 0
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LP then
				index = index + 1
				local rec = playerRig(p, index)
				if rec then
					local same = playerOnSide(p, side)
					if same ~= false then
						rec.__unknown = same == nil
						add(rec)
					end
				end
			end
		end
	end
	return out
end

local function currentPower()
	if CFG.powerBoost then
		return 99
	end
	local up = DC and DC.Profile and DC.Profile.Upgrades
	return tonumber(up and up.Power) or 0
end

local function defenderPositions(side)
	local out = {}
	-- GameRigs separates the two units explicitly: Home is your offense,
	-- Away.Covers is the secondary that actually covers your receivers.
	-- All[].Side is labelled from the other team's point of view, so the old
	-- filter by Side ~= "Home" picked up your own receivers. real players are
	-- checked against the local side instead, not against the string "Home".
	local away = GR and GR.Away
	local covers = type(away) == "table" and away.Covers or nil
	if type(covers) == "table" then
		for _, r in ipairs(covers) do
			if type(r) == "table" then
				local job = tostring(r.Job or "")
				local p = baseOf(r)
				if p and job ~= "Down" and job ~= "Dive" then
					out[#out + 1] = p
				end
			end
		end
	end

	-- a human defender is not guaranteed to be in Away.Covers. add any real
	-- player the game clearly marks as the other side; unknown players are
	-- left out so they cannot make every receiver look covered.
	if CFG.playerCoverage then
		local ch = LP.Character
		local myRoot = ch and ch:FindFirstChild("HumanoidRootPart")
		local origin = myRoot and myRoot.Position or nil
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LP and playerOnSide(p, side) == false then
				local pch = p.Character
				local root = pch and pch:FindFirstChild("HumanoidRootPart")
				if root then
					-- do not let a pass rusher standing on the QB count as
					-- coverage for every route. 10 studs is inside the pocket.
					local near = false
					if origin then
						local dx = root.Position.X - origin.X
						local dz = root.Position.Z - origin.Z
						near = dx * dx + dz * dz < 100
					end
					if not near then
						out[#out + 1] = root.Position
					end
				end
			end
		end
	end

	return out
end

-- distance from the nearest defender to either the catch point or the throw
-- line. a defender directly under the route but 3 studs off the line still
-- counts, which a plain catch-point distance does not see.
local function separation(from, point, defs)
	local best = 99
	local near = nil
	local sx = point.X - from.X
	local sz = point.Z - from.Z
	local len2 = sx * sx + sz * sz
	for i = 1, #defs do
		local dp = defs[i]
		local cx = dp.X - point.X
		local cz = dp.Z - point.Z
		local catchD = math.sqrt(cx * cx + cz * cz)
		local lineD = catchD
		if len2 > 0.01 then
			local ax = dp.X - from.X
			local az = dp.Z - from.Z
			local t = (ax * sx + az * sz) / len2
			if t < 0 then
				t = 0
			elseif t > 1 then
				t = 1
			end
			local nx = from.X + sx * t
			local nz = from.Z + sz * t
			local dx = dp.X - nx
			local dz = dp.Z - nz
			lineD = math.sqrt(dx * dx + dz * dz) + 1.5
		end
		local s = math.min(catchD, lineD)
		if s < best then
			best = s
			near = dp
		end
	end
	return best, near
end

local function throwOrigin()
	local ok, hand = pcall(TC.GetHandPart, TC)
	if ok and typeof(hand) == "Instance" and hand:IsA("BasePart") then
		return hand.Position
	end
	local ch = LP.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if root then
		return root.Position + Vector3.new(0, 1.2, 0)
	end
	return nil
end

--// target lock ----------------------------------------------------------------

local AUTO_LABEL = "auto (best open)"

local function receiverRecords()
	local out = {}
	local recs = receiverRigs(localSide())
	for i = 1, #recs do
		local r = recs[i]
		if type(r) == "table" then
			out[#out + 1] = {
				rig = r,
				slot = tonumber(r.Slot) or i,
				name = tostring(r.Name or ("R" .. i)),
				real = r.Player ~= nil,
				unknown = r.__unknown == true,
			}
		end
	end
	return out
end

local function lockMatches(rec)
	if lockName == nil then
		return lockSlot ~= nil and rec.slot == lockSlot
	end
	if rec.name ~= lockName then
		return false
	end
	return lockSlot == nil or rec.slot == lockSlot
end

local function clearLock()
	lockSlot = nil
	lockName = nil
	lockMissingAt = nil
	manualPick = false
	cycle = 0
end

local function setLock(rec)
	if not rec then
		clearLock()
		return
	end
	lockSlot = rec.slot
	lockName = rec.name
	lockMissingAt = nil
	manualPick = false
	cycle = 0
end

local function nextLock()
	local recs = receiverRecords()
	if #recs == 0 then
		clearLock()
		return false
	end
	local idx = 0
	for i = 1, #recs do
		if lockMatches(recs[i]) then
			idx = i
			break
		end
	end
	setLock(recs[(idx % #recs) + 1])
	return true
end

local function receiverOptions()
	local recs = receiverRecords()
	local counts = {}
	for _, rec in ipairs(recs) do
		counts[rec.name] = (counts[rec.name] or 0) + 1
	end
	local opts = { AUTO_LABEL }
	local map = {}
	local used = { [AUTO_LABEL] = true }
	for _, rec in ipairs(recs) do
		local baseName = rec.name
		if rec.real then
			baseName = rec.unknown and ("P? " .. rec.name) or ("P: " .. rec.name)
		end
		local label = baseName
		if (counts[rec.name] or 0) > 1 then
			label = string.format("%s #%d", baseName, rec.slot)
		end
		local base = label
		local n = 2
		while used[label] do
			label = string.format("%s (%d)", base, n)
			n = n + 1
		end
		used[label] = true
		map[label] = rec
		opts[#opts + 1] = label
	end
	return recs, opts, map
end

-- keeps the dropdown in step with the live offense. a receiver that leaves the
-- field stays locked for three seconds before the pick falls back to auto, so a
-- short substitution or a play reset does not drop your choice.
local function syncReceiverOptions(now)
	local recs, opts, map = receiverOptions()
	lockOptions = map
	local sig = table.concat(opts, "\31")
	if sig ~= lockSig then
		lockSig = sig
		lockShown = nil
		if ui.lockDrop then
			lockSyncing = true
			pcall(function()
				ui.lockDrop:Refresh(opts)
			end)
			lockSyncing = false
		end
	end

	local found = nil
	for _, rec in ipairs(recs) do
		if lockMatches(rec) then
			found = rec
			break
		end
	end
	if lockSlot ~= nil or lockName ~= nil then
		if found then
			lockMissingAt = nil
			lockSlot = found.slot
			lockName = found.name
		else
			lockMissingAt = lockMissingAt or now
			if now - lockMissingAt > 3 then
				clearLock()
			end
		end
	end

	local label = AUTO_LABEL
	if found then
		for text, rec in pairs(map) do
			if rec.slot == found.slot and rec.name == found.name then
				label = text
				break
			end
		end
	end
	if label ~= lockShown then
		lockShown = label
		if ui.lockDrop then
			lockSyncing = true
			pcall(function()
				ui.lockDrop:Set(label, true)
			end)
			lockSyncing = false
		end
	end
end

local function findLocked(list)
	for i = 1, #list do
		if lockMatches(list[i]) then
			return list[i]
		end
	end
	return nil
end

local function crosshairPick(list, origin)
	local cam = Workspace.CurrentCamera
	if not cam then
		return nil
	end
	local look = cam.CFrame.LookVector
	local bestDot = math.cos(math.rad(math.clamp(CFG.assistAngle, 10, 80)))
	local best = nil
	for i = 1, #list do
		local e = list[i]
		local d = e.point - origin
		if d.Magnitude > 0.1 then
			local dot = look:Dot(d.Unit)
			if dot > bestDot then
				bestDot = dot
				best = e
			end
		end
	end
	return best
end

local function autoPick(list, origin)
	if #list == 0 then
		return nil
	end
	if cycle > 0 then
		return list[((cycle - 1) % #list) + 1]
	end
	if CFG.autoTarget then
		-- unknown-side humans stay selectable by lock, F and the crosshair, but
		-- a known receiver wins the automatic pick. otherwise a 1v1 opponent
		-- with no side data could become the default target.
		for i = 1, #list do
			if not list[i].unknown then
				return list[i]
			end
		end
		return list[1]
	end
	return crosshairPick(list, origin)
end

local function build(now)
	syncReceiverOptions(now)
	local origin = throwOrigin()
	if not origin then
		targetList = {}
		pick = nil
		return
	end
	local side = localSide()
	local defs = defenderPositions(side)
	local power = currentPower()
	local maxs = TCfg.maxSpeed(power)
	local list = {}
	local recs = receiverRigs(side)

	if type(recs) == "table" then
		for i = 1, #recs do
			local r = recs[i]
			if type(r) == "table" then
				local job = tostring(r.Job or "")
				local base = job ~= "Down" and job ~= "Dive" and baseOf(r) or nil
				local spot = base and catchOf(r, base)
				if base and spot then
					local vel = velOf(r, base, now)
					local aim = spot
					if CFG.lead then
						aim = leadPoint(origin, spot, vel)
					end
					local dir = TCfg.launchDirection(origin, aim)
					local speed = TCfg.idealSpeed(origin, aim, dir)
					if speed then
						local flat = (Vector3.new(aim.X - origin.X, 0, aim.Z - origin.Z)).Magnitude
						local sep, near = separation(origin, aim, defs)
						local reachable = speed <= CFG.speedCap and flat <= CFG.maxDistance
						local open = sep >= CFG.minGap
						local slider = TCfg.sliderFor(power, math.min(speed, maxs))
						local score = sep * 1.5
							- flat * 0.03
							+ (job == "Catch" and 3 or 0)
							+ (open and 10 or 0)
							+ (reachable and 5 or -5)
							- (r.__unknown and 8 or 0)
						list[#list + 1] = {
							rig = r,
							index = i,
							base = base,
							raw = spot,
							point = aim,
							vel = vel,
							dir = dir,
							speed = speed,
							maxs = maxs,
							dist = flat,
							sep = sep,
							nearest = near,
							job = job,
							open = open,
							reachable = reachable,
							slot = tonumber(r.Slot) or i,
							name = tostring(r.Name or ("R" .. i)),
							real = r.Player ~= nil,
							unknown = r.__unknown == true,
							slider = slider and math.clamp(slider, 0, 1) or 0,
							score = score,
						}
					end
				end
			end
		end
	end

	table.sort(list, function(a, b)
		if a.reachable ~= b.reachable then
			return a.reachable
		end
		if a.open ~= b.open then
			return a.open
		end
		return a.score > b.score
	end)
	targetList = list

	manualPick = false
	if #list == 0 then
		pick = nil
	else
		local locked = (lockSlot ~= nil or lockName ~= nil) and findLocked(list) or nil
		if locked then
			pick = locked
			manualPick = true
		else
			-- no lock, or the locked receiver is not throwable this frame:
			-- the normal auto / cycle / crosshair pick takes over.
			pick = autoPick(list, origin)
		end
	end
end

--// visuals -------------------------------------------------------------------

local fxFolder = Instance.new("Folder")
fxFolder.Name = FX_NAME
fxFolder.Parent = Workspace

local esp = {}
local realEsp = {}

local function ensureEsp(rig, root)
	local item = esp[rig]
	if item and item.billboard and item.billboard.Parent then
		return item
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "qbaim"
	bb.Size = UDim2.fromOffset(200, 96)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 500
	bb.Adornee = root
	bb.Parent = fxFolder

	local ring = Instance.new("Frame")
	ring.BackgroundTransparency = 1
	ring.Size = UDim2.fromOffset(64, 64)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Transparency = 0.1
	stroke.Parent = ring

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromOffset(200, 22)
	label.Position = UDim2.new(0.5, 0, 0.5, 40)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextStrokeTransparency = 0.35
	label.Text = ""
	label.Parent = bb

	item = { billboard = bb, ring = ring, stroke = stroke, label = label }
	esp[rig] = item
	return item
end

local arcPool = {}
local arcReady = false
local marker = nil
local defLine = nil
local markerReady = false

local function ensureArc()
	if arcReady then
		return
	end
	for i = 1, 26 do
		if not arcPool[i] then
			local p = Instance.new("Part")
			p.Name = "qbaim_arc"
			p.Shape = Enum.PartType.Ball
			p.Size = Vector3.new(0.22, 0.22, 0.22)
			p.Material = Enum.Material.Neon
			p.Color = LOCK_COLOR
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Transparency = 1
			p.Parent = fxFolder
			arcPool[i] = p
		end
	end
	arcReady = true
end

local function ensureMarkers()
	if markerReady then
		return
	end
	if not marker then
		local p = Instance.new("Part")
		p.Name = "qbaim_mark"
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(2.6, 2.6, 2.6)
		p.Material = Enum.Material.Neon
		p.Color = LOCK_COLOR
		p.Transparency = 1
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = fxFolder
		marker = p
	end
	if not defLine then
		local p = Instance.new("Part")
		p.Name = "qbaim_def"
		p.Size = Vector3.new(0.12, 0.12, 1)
		p.Material = Enum.Material.Neon
		p.Color = CUT_COLOR
		p.Transparency = 1
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = fxFolder
		defLine = p
	end
	markerReady = true
end

local function clearVisuals()
	for _, item in pairs(esp) do
		if item.billboard and item.billboard.Parent then
			item.billboard.Enabled = false
		end
	end
	for _, item in pairs(realEsp) do
		if item.billboard and item.billboard.Parent then
			item.billboard.Enabled = false
		end
	end
	for _, p in ipairs(arcPool) do
		p.Transparency = 1
	end
	if marker then
		marker.Transparency = 1
	end
	if defLine then
		defLine.Transparency = 1
	end
end

local function drawVisuals()
	if not CFG.enabled or not CFG.esp then
		for _, item in pairs(esp) do
			if item.billboard and item.billboard.Parent then
				item.billboard.Enabled = false
			end
		end
		return
	end
	local seen = {}
	for _, e in ipairs(targetList) do
		local root = e.rig.Root
		if root and root.Parent then
			local item = ensureEsp(e.rig, root)
			item.billboard.Adornee = root
			item.billboard.StudsOffsetWorldSpace = e.raw - root.Position
			item.billboard.Enabled = CFG.esp

			local locked = pick == e
			local col = OPEN_COLOR
			if not e.open then
				col = CUT_COLOR
			elseif not e.reachable then
				col = FAR_COLOR
			elseif locked then
				col = LOCK_COLOR
			end

			item.stroke.Color = col
			item.stroke.Thickness = locked and 3 or 2
			item.ring.Visible = CFG.ring
			item.label.Visible = CFG.labels
			item.label.TextColor3 = col
			item.label.Text = string.format(
				"%s%s  %.0f st  %s  sep %.0f  pwr %d%%",
				e.real and (e.unknown and "P? " or "P: ") or "",
				e.name, e.dist, e.open and "open" or "cut", e.sep, math.floor(e.slider * 100)
			)
			seen[e.rig] = true
		end
	end
	for rig, item in pairs(esp) do
		if not seen[rig] and item.billboard and item.billboard.Parent then
			item.billboard.Enabled = false
		end
	end
end

local function ensureRealEsp(player, root)
	local item = realEsp[player]
	if item and item.billboard and item.billboard.Parent then
		return item
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "qbaim_player"
	bb.Size = UDim2.fromOffset(190, 24)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 500
	bb.StudsOffset = Vector3.new(0, 3.4, 0)
	bb.Adornee = root
	bb.Parent = fxFolder

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextStrokeTransparency = 0.35
	label.Text = ""
	label.Parent = bb

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.4
	stroke.Parent = label

	item = { billboard = bb, label = label, stroke = stroke }
	realEsp[player] = item
	return item
end

-- every other real player in the match, independent of whether they are in the
-- game's target registry. this is the part that answers "does it see the human
-- players": green = same side, red = other side, white = the game gave no side.
local function drawRealEsp()
	if not CFG.enabled or not CFG.playerEsp then
		for _, item in pairs(realEsp) do
			if item.billboard and item.billboard.Parent then
				item.billboard.Enabled = false
			end
		end
		return
	end
	local me = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
	local origin = me and me.Position or Vector3.zero
	local side = localSide()
	local inTargets = {}
	if CFG.esp then
		for _, e in ipairs(targetList) do
			if e.real and e.rig.Player then
				inTargets[e.rig.Player] = true
			end
		end
	end
	local seen = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP and not inTargets[p] then
			local ch = p.Character
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 then
				local item = ensureRealEsp(p, root)
				item.billboard.Adornee = root
				item.billboard.Enabled = true
				local same = playerOnSide(p, side)
				local col = same == true and OPEN_COLOR
					or (same == false and CUT_COLOR or Color3.fromRGB(235, 235, 245))
				local tag = same == true and "" or (same == false and "OP " or "? ")
				item.stroke.Color = col
				item.label.TextColor3 = col
				item.label.Text = string.format(
					"%s%s  %.0f st",
					tag,
					p.DisplayName,
					(root.Position - origin).Magnitude
				)
				seen[p] = true
			end
		end
	end
	for p, item in pairs(realEsp) do
		if not seen[p] and item.billboard and item.billboard.Parent then
			item.billboard.Enabled = false
		end
	end
end

local function drawArc()
	ensureArc()
	ensureMarkers()
	if not pick or not CFG.enabled or not CFG.arc then
		for _, p in ipairs(arcPool) do
			p.Transparency = 1
		end
		marker.Transparency = 1
		return
	end
	local origin = throwOrigin()
	if not origin then
		return
	end
	local dir = TCfg.launchDirection(origin, pick.point)
	local speed = TCfg.idealSpeed(origin, pick.point, dir)
	if not speed then
		return
	end
	speed = math.min(speed, CFG.speedCap)
	local v = dir * speed
	local pos = origin
	local dt = 0.06
	local shown = 0
	for i = 1, #arcPool do
		local p = arcPool[i]
		p.Position = pos
		p.Transparency = 0.1 + i * 0.025
		local shrink = 1 - math.min(0.5, i * 0.015)
		p.Size = Vector3.new(0.22, 0.22, 0.22) * shrink
		shown = i
		pos = pos + v * dt
		v = v - Vector3.new(0, GRAVITY * dt, 0)
		if pos.Y < pick.point.Y - 2 then
			break
		end
	end
	for i = shown + 1, #arcPool do
		arcPool[i].Transparency = 1
	end
	marker.Position = pick.point
	marker.Transparency = 0.72
end

local function drawDefLine()
	ensureMarkers()
	if not CFG.defLines or not pick or not pick.nearest or not CFG.enabled then
		defLine.Transparency = 1
		return
	end
	local a = pick.point
	local b = pick.nearest
	local d = b - a
	if d.Magnitude < 0.5 then
		defLine.Transparency = 1
		return
	end
	defLine.Size = Vector3.new(0.12, 0.12, d.Magnitude)
	defLine.CFrame = CFrame.lookAt(a + d * 0.5, b)
	defLine.Transparency = 0.35
end

--// hud -----------------------------------------------------------------------

local hudGui = nil
local hudBody = nil
local hudBadge = nil

local function buildHud()
	local pg = LP:FindFirstChild("PlayerGui") or LP:WaitForChild("PlayerGui", 10)
	if not pg then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = HUD_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Parent = pg

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(286, 112)
	frame.Position = UDim2.new(0.5, -143, 0, 14)
	frame.BackgroundColor3 = Color3.fromRGB(14, 16, 22)
	frame.BackgroundTransparency = 0.18
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = LOCK_COLOR
	stroke.Transparency = 0.55
	stroke.Thickness = 1.4
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 0, 20)
	title.Position = UDim2.fromOffset(8, 5)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = LOCK_COLOR
	title.Text = "QB AIMBOT"
	title.Parent = frame

	hudBadge = Instance.new("TextLabel")
	hudBadge.Size = UDim2.fromOffset(64, 20)
	hudBadge.Position = UDim2.new(1, -72, 0, 5)
	hudBadge.BackgroundTransparency = 1
	hudBadge.Font = Enum.Font.GothamBold
	hudBadge.TextSize = 12
	hudBadge.TextXAlignment = Enum.TextXAlignment.Right
	hudBadge.TextColor3 = OPEN_COLOR
	hudBadge.Text = "LIVE"
	hudBadge.Parent = frame

	hudBody = Instance.new("TextLabel")
	hudBody.Size = UDim2.new(1, -16, 0, 80)
	hudBody.Position = UDim2.fromOffset(8, 26)
	hudBody.BackgroundTransparency = 1
	hudBody.Font = Enum.Font.Code
	hudBody.TextSize = 12
	hudBody.TextXAlignment = Enum.TextXAlignment.Left
	hudBody.TextYAlignment = Enum.TextYAlignment.Top
	hudBody.TextColor3 = Color3.fromRGB(232, 234, 240)
	hudBody.Text = ""
	hudBody.Parent = frame

	hudGui = gui
end

local function updateHud(now)
	if not hudGui then
		return
	end
	hudGui.Enabled = CFG.hud
	if not CFG.hud then
		return
	end
	if now - lastHud < 0.08 then
		return
	end
	lastHud = now

	local e = pick
	local lines = {}
	lines[#lines + 1] = string.format(
		"aim %s   auto %s   %s",
		CFG.enabled and "ON" or "OFF",
		CFG.autoTarget and "ON" or "OFF",
		e and ("LOCK " .. e.name .. (manualPick and "  (locked)" or "")) or "no target"
	)
	if e then
		lines[#lines + 1] = string.format(
			"%.0f st   sep %.1f   %s",
			e.dist, e.sep, e.open and "OPEN" or "COVERED"
		)
		lines[#lines + 1] = string.format(
			"pwr %d%%   need %.1f   cap %.0f",
			math.floor(e.slider * 100), e.speed, CFG.speedCap
		)
	elseif not CFG.autoTarget then
		lines[#lines + 1] = "crosshair mode: look at a receiver"
		lines[#lines + 1] = "or press F to cycle"
	else
		lines[#lines + 1] = "no receiver in range"
		lines[#lines + 1] = "waiting for a route"
	end
	lines[#lines + 1] = string.format(
		"throws %d   aimed %d   auto %d",
		stats.throws, stats.aimed, stats.auto
	)

	if hudBody then
		hudBody.Text = table.concat(lines, "\n")
	end
	if hudBadge then
		hudBadge.Text = CFG.enabled and "LIVE" or "OFF"
		hudBadge.TextColor3 = CFG.enabled and OPEN_COLOR or CUT_COLOR
	end
end

--// hooks ---------------------------------------------------------------------

local function installLaunch()
	if hooks.launch or type(BC.Launch) ~= "function" then
		return
	end
	local orig = BC.Launch
	local wrapper = function(self, pos, vel, grav, perfect, wobble, drift)
		stats.throws = stats.throws + 1
		local e = pick
		if CFG.enabled and e and typeof(pos) == "Vector3" then
			if CFG.idealSpeed then
				local dir = TCfg.launchDirection(pos, e.point)
				local speed = TCfg.idealSpeed(pos, e.point, dir)
				if speed and speed <= CFG.speedCap and e.reachable then
					vel = dir * speed
					stats.aimed = stats.aimed + 1
					stats.lastSpeed = speed
				else
					stats.missed = stats.missed + 1
				end
			end
			if CFG.perfect then
				perfect = true
				wobble = 0
				drift = Vector3.new(0, 0, 0)
			end
		end
		stats.lastPos = pos
		stats.lastVel = vel
		stats.lastPoint = e and e.point or nil
		stats.lastName = e and e.name or nil
		return orig(self, pos, vel, grav, perfect, wobble, drift)
	end
	local ok = pcall(function()
		BC.Launch = wrapper
	end)
	if ok and BC.Launch == wrapper then
		hooks.launch = true
		hooks.launchOrig = orig
	else
		warn("[QBAIM] could not hook BallController.Launch")
	end
end

local function installSnap()
	if hooks.snap or type(TC.SetAimTargets) ~= "function" then
		return
	end
	local function resolver()
		local e = pick
		if not e or not e.reachable then
			return nil
		end
		return { { Position = e.raw, Velocity = e.vel or Vector3.zero } }
	end
	pcall(TC.SetAimTargets, TC, resolver)
	hooks.snap = true
end

local function removeSnap()
	if not hooks.snap then
		return
	end
	pcall(TC.SetAimTargets, TC, nil)
	hooks.snap = false
end

local assistOrig = nil

local function widenAssist()
	assistOrig = assistOrig or { TCfg.AssistAngle, TCfg.AssistPower }
	TCfg.AssistAngle = CFG.assistAngle
	TCfg.AssistPower = 1
end

local function restoreAssist()
	if assistOrig then
		TCfg.AssistAngle = assistOrig[1]
		TCfg.AssistPower = assistOrig[2]
		assistOrig = nil
	end
end

local function applyPower()
	if CFG.enabled and CFG.powerAssist then
		if not hooks.powerSaved then
			hooks.powerOrig = TC.PowerAssist
			hooks.powerSaved = true
		end
		TC.PowerAssist = 1
	elseif hooks.powerSaved then
		TC.PowerAssist = hooks.powerOrig
		hooks.powerSaved = false
	end

	if CFG.enabled and CFG.powerBoost then
		if not hooks.rankSaved then
			hooks.rankOrig = TC.RankOverride
			hooks.rankSaved = true
		end
		TC.RankOverride = { Accuracy = 12, Power = 99 }
	elseif hooks.rankSaved then
		TC.RankOverride = hooks.rankOrig
		hooks.rankSaved = false
	end
end

local function restoreAll()
	if hooks.launch and hooks.launchOrig then
		BC.Launch = hooks.launchOrig
		hooks.launch = false
		hooks.launchOrig = nil
	end
	removeSnap()
	restoreAssist()
	if hooks.powerSaved then
		TC.PowerAssist = hooks.powerOrig
		hooks.powerSaved = false
	end
	if hooks.rankSaved then
		TC.RankOverride = hooks.rankOrig
		hooks.rankSaved = false
	end
end

local function setEnabled(v)
	CFG.enabled = v
	if v then
		installLaunch()
		if CFG.snap then
			installSnap()
			widenAssist()
		else
			removeSnap()
			restoreAssist()
		end
		applyPower()
	else
		restoreAll()
		clearVisuals()
	end
	statusLine = v and "aim on" or "aim off"
end

--// auto throw ----------------------------------------------------------------

local function mouseClick()
	local ok, fn = pcall(function()
		return mouse1click
	end)
	if ok and type(fn) == "function" then
		pcall(fn)
		return true
	end
	return false
end

local function gameActive()
	local ok, fn = pcall(function()
		return isrbxactive
	end)
	if ok and type(fn) == "function" then
		local ok2, v = pcall(fn)
		return ok2 and v == true
	end
	return true
end

local function uiOpen()
	if not CamCtl then
		return false
	end
	local ok, v = pcall(CamCtl.IsUiOpen, CamCtl)
	return ok and v == true
end

local function releaseNow()
	if dead then
		return false
	end
	if not gameActive() then
		return false
	end
	local now = os.clock()
	if now < nextClick then
		return false
	end
	local okPower, powering = pcall(TC.IsPowering, TC)
	if okPower and powering then
		nextClick = now + 0.4
		if mouseClick() then
			stats.auto = stats.auto + 1
			return true
		end
		return false
	end
	local okHold, holding = pcall(TC.IsHolding, TC)
	if okHold and holding then
		nextClick = now + 0.4
		return mouseClick()
	end
	return false
end

local function autoThrowStep(now, force)
	if not (CFG.autoThrow or force) or dead then
		autoAt = 0
		holdAt = 0
		return
	end
	local e = pick
	if not e or not e.reachable then
		autoAt = 0
		return
	end
	local okHold, holding = pcall(TC.IsHolding, TC)
	if not okHold or not holding then
		autoAt = 0
		holdAt = 0
		return
	end
	if holdAt == 0 then
		holdAt = now
	end
	if CFG.respectUi and uiOpen() then
		autoAt = 0
		return
	end
	if not gameActive() then
		autoAt = 0
		return
	end
	-- an open receiver is thrown to as soon as it appears. when auto play is
	-- forcing the ball, a covered look is still released after holdWait so a
	-- tight window cannot stall the drive forever. safeCatch removes that
	-- forced release, so auto play waits for separation instead of throwing
	-- into coverage. it does not change the game's catch roll.
	local ready = e.open or (not CFG.safeCatch and force and now - holdAt >= CFG.holdWait)
	if not ready then
		return
	end
	if now < nextClick then
		return
	end
	local okPower, powering = pcall(TC.IsPowering, TC)
	if okPower and powering then
		if autoAt == 0 then
			autoAt = now
		end
		if now - autoAt >= CFG.autoDelay then
			autoAt = 0
			nextClick = now + 0.5
			if mouseClick() then
				stats.auto = stats.auto + 1
			end
		end
	else
		-- first click starts the charge, second click commits the throw
		autoAt = now
		nextClick = now + 0.3
		mouseClick()
	end
end

--// ui ------------------------------------------------------------------------

local function reg(flag, key)
	ui.flags[#ui.flags + 1] = { flag, key }
end

local function syncUi()
	if not ui.window then
		return
	end
	for _, f in ipairs(ui.flags) do
		pcall(function()
			ui.window:Set(f[1], CFG[f[2]])
		end)
	end
end

local function buildUI()
	local Rayfield
	pcall(function()
		Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()
	end)
	if not Rayfield then
		warn("[QBAIM] Rayfield failed to load; running with the built-in HUD only")
		return
	end

	local w = Rayfield:CreateWindow({
		Name = "TAF // QB AIMBOT",
		LoadingTitle = "THROW A FOOTBALL",
		LoadingSubtitle = "qb aimbot  -  perfect ballistics",
		KeySystem = false,
	})
	ui.window = w

	pcall(function()
		w:ChangeTheme({
			WindowColor = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 12, 18)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 22, 30)),
			}),
			ShadowColor = Color3.fromRGB(4, 6, 10),
			CornerRoundness = UDim.new(0, 16),
			ElementCornerRadius = UDim.new(0, 10),
			PillCornerRadius = UDim.new(1, 0),
			AccentColor = LOCK_COLOR,
		})
	end)

	-- AIM
	local aimTab = w:CreateTab({ Name = "AIM" })
	aimTab:CreateSection({ Name = "SOLVER" })
	reg("qb_enabled", "enabled")
	aimTab:CreateToggle({
		Name = "master",
		Description = "wraps BallController.Launch and solves every release onto the picked receiver.",
		Flag = "qb_enabled",
		Value = CFG.enabled,
		Callback = function(v)
			setEnabled(v)
			saveCfg()
		end,
	})
	reg("qb_auto", "autoTarget")
	aimTab:CreateToggle({
		Name = "auto target",
		Description = "when no receiver is manually selected, picks the most open receiver automatically. off means the receiver nearest your camera crosshair. a manual target below overrides this.",
		Flag = "qb_auto",
		Value = CFG.autoTarget,
		Callback = function(v)
			CFG.autoTarget = v
			if v then
				cycle = 0
			end
			saveCfg()
		end,
	})

	aimTab:CreateSection({ Name = "AIMBOT TARGET" })
	ui.lockDrop = aimTab:CreateDropdown({
		Name = "aimbot throws to",
		Description = "only changes which receiver the aimbot solves onto. the aimbot itself stays on: perfect release, exact speed, lead, power assist and auto throw all keep running for the receiver you pick.",
		Options = { AUTO_LABEL },
		Placeholder = AUTO_LABEL,
		Callback = function(v)
			if lockSyncing then
				return
			end
			local chosen = type(v) == "table" and v[1] or v
			if not chosen or chosen == AUTO_LABEL then
				clearLock()
				return
			end
			local rec = lockOptions[chosen]
			if not rec then
				local _, _, fresh = receiverOptions()
				rec = fresh[chosen]
			end
			if rec then
				setLock(rec)
			end
		end,
	})
	ui.lockText = aimTab:CreateText({
		Name = "lock state",
		Text = "aimbot auto target",
	})
	lockShown = nil
	aimTab:CreateText({
		Name = "target lock note",
		Text = "the aimbot stays on the whole time. this dropdown only decides who it throws to. leave it on 'auto' and the aimbot picks the most open receiver itself. F cycles the receiver while you play.",
	})
	reg("qb_perfect", "perfect")
	aimTab:CreateToggle({
		Name = "perfect release",
		Description = "forces the perfect flag and zeroes wobble and drift, the same state a perfect timing produces.",
		Flag = "qb_perfect",
		Value = CFG.perfect,
		Callback = function(v)
			CFG.perfect = v
			saveCfg()
		end,
	})
	reg("qb_ideal", "idealSpeed")
	aimTab:CreateToggle({
		Name = "exact speed",
		Description = "replaces the launch velocity with ThrowConfig.idealSpeed, so the ball lands on the catch point.",
		Flag = "qb_ideal",
		Value = CFG.idealSpeed,
		Callback = function(v)
			CFG.idealSpeed = v
			saveCfg()
		end,
	})
	reg("qb_snap", "snap")
	aimTab:CreateToggle({
		Name = "aim snap",
		Description = "also feeds the pick into ThrowController.SetAimTargets and widens the game's own assist cone.",
		Flag = "qb_snap",
		Value = CFG.snap,
		Callback = function(v)
			CFG.snap = v
			if CFG.enabled then
				if v then
					installSnap()
					widenAssist()
				else
					removeSnap()
					restoreAssist()
				end
			end
			saveCfg()
		end,
	})
	reg("qb_lead", "lead")
	aimTab:CreateToggle({
		Name = "predict movement",
		Description = "leads running receivers with the game's own three-pass solve.",
		Flag = "qb_lead",
		Value = CFG.lead,
		Callback = function(v)
			CFG.lead = v
			saveCfg()
		end,
	})

	aimTab:CreateSection({ Name = "POWER" })
	reg("qb_powerassist", "powerAssist")
	aimTab:CreateToggle({
		Name = "power assist",
		Description = "sets ThrowController.PowerAssist to 1, the controller's own ideal-speed assist.",
		Flag = "qb_powerassist",
		Value = CFG.powerAssist,
		Callback = function(v)
			CFG.powerAssist = v
			applyPower()
			saveCfg()
		end,
	})
	reg("qb_powerboost", "powerBoost")
	aimTab:CreateToggle({
		Name = "rank override",
		Description = "reports accuracy 12 and power 99 to the throw controller. off by default; stronger than a real rank.",
		Flag = "qb_powerboost",
		Value = CFG.powerBoost,
		Callback = function(v)
			CFG.powerBoost = v
			applyPower()
			saveCfg()
		end,
	})
	reg("qb_cap", "speedCap")
	aimTab:CreateSlider({
		Name = "speed cap",
		Description = "hard ceiling on solved throw speed. 110 is the game's own maximum.",
		Range = { 62, 130 },
		Increment = 1,
		Value = CFG.speedCap,
		Suffix = " studs/s",
		Flag = "qb_cap",
		Callback = function(v)
			CFG.speedCap = v
			saveCfg()
		end,
	})

	aimTab:CreateSection({ Name = "FILTER" })
	reg("qb_range", "maxDistance")
	aimTab:CreateSlider({
		Name = "max distance",
		Description = "longest throw the solver will aim. 300 is about the range limit of a 110 studs/s throw.",
		Range = { 40, 320 },
		Increment = 5,
		Value = CFG.maxDistance,
		Suffix = " st",
		Flag = "qb_range",
		Callback = function(v)
			CFG.maxDistance = v
			saveCfg()
		end,
	})
	reg("qb_gap", "minGap")
	aimTab:CreateSlider({
		Name = "open threshold",
		Description = "separation, in studs, that counts as open. below this a receiver is marked cut.",
		Range = { 0, 20 },
		Increment = 0.5,
		Value = CFG.minGap,
		Suffix = " st",
		Flag = "qb_gap",
		Callback = function(v)
			CFG.minGap = v
			saveCfg()
		end,
	})
	reg("qb_angle", "assistAngle")
	aimTab:CreateSlider({
		Name = "assist cone",
		Description = "how wide the game's own snap cone is while aim snap is on.",
		Range = { 12, 90 },
		Increment = 1,
		Value = CFG.assistAngle,
		Suffix = " deg",
		Flag = "qb_angle",
		Callback = function(v)
			CFG.assistAngle = v
			if assistOrig then
				TCfg.AssistAngle = v
			end
			saveCfg()
		end,
	})

	-- TARGETS
	local visTab = w:CreateTab({ Name = "TARGETS" })
	visTab:CreateSection({ Name = "REAL PLAYERS" })
	visTab:CreateText({
		Name = "real player note",
		Text = "Home.Receivers is the game's AI receiver list. human players can exist only in GameRigs.All or as characters, so these options read them directly. known opponents are coverage, not targets.",
	})
	reg("qb_playeresp", "playerEsp")
	visTab:CreateToggle({
		Name = "real player esp",
		Description = "labels every other real player in the match. green same side, red other side, white unknown side.",
		Flag = "qb_playeresp",
		Value = CFG.playerEsp,
		Callback = function(v)
			CFG.playerEsp = v
			saveCfg()
		end,
	})
	reg("qb_playertargets", "playerTargets")
	visTab:CreateToggle({
		Name = "real player targets",
		Description = "adds real players to the throw list and lock dropdown. known opponents are excluded and counted as coverage.",
		Flag = "qb_playertargets",
		Value = CFG.playerTargets,
		Callback = function(v)
			CFG.playerTargets = v
			saveCfg()
		end,
	})
	reg("qb_playercover", "playerCoverage")
	visTab:CreateToggle({
		Name = "real player coverage",
		Description = "counts real players marked as the other side as coverage (pass rushers within 10 studs of you are ignored). turn off if the game's side labels are inverted and every receiver looks covered.",
		Flag = "qb_playercover",
		Value = CFG.playerCoverage,
		Callback = function(v)
			CFG.playerCoverage = v
			saveCfg()
		end,
	})

	visTab:CreateSection({ Name = "OVERLAY" })
	reg("qb_esp", "esp")
	visTab:CreateToggle({
		Name = "receiver markers",
		Flag = "qb_esp",
		Value = CFG.esp,
		Callback = function(v)
			CFG.esp = v
			if not v then
				clearVisuals()
			end
			saveCfg()
		end,
	})
	reg("qb_ring", "ring")
	visTab:CreateToggle({
		Name = "catch ring",
		Flag = "qb_ring",
		Value = CFG.ring,
		Callback = function(v)
			CFG.ring = v
			saveCfg()
		end,
	})
	reg("qb_labels", "labels")
	visTab:CreateToggle({
		Name = "labels",
		Flag = "qb_labels",
		Value = CFG.labels,
		Callback = function(v)
			CFG.labels = v
			saveCfg()
		end,
	})
	reg("qb_arc", "arc")
	visTab:CreateToggle({
		Name = "flight arc",
		Description = "draws the solved trajectory and a landing marker.",
		Flag = "qb_arc",
		Value = CFG.arc,
		Callback = function(v)
			CFG.arc = v
			if not v then
				for _, p in ipairs(arcPool) do
					p.Transparency = 1
				end
			end
			saveCfg()
		end,
	})
	reg("qb_defline", "defLines")
	visTab:CreateToggle({
		Name = "nearest defender",
		Description = "line from the catch point to the closest defender.",
		Flag = "qb_defline",
		Value = CFG.defLines,
		Callback = function(v)
			CFG.defLines = v
			saveCfg()
		end,
	})
	reg("qb_hud", "hud")
	visTab:CreateToggle({
		Name = "hud",
		Flag = "qb_hud",
		Value = CFG.hud,
		Callback = function(v)
			CFG.hud = v
			saveCfg()
		end,
	})

	-- AUTO
	local autoTab = w:CreateTab({ Name = "AUTO" })
	autoTab:CreateSection({ Name = "THROW" })
	reg("qb_autothrow", "autoThrow")
	autoTab:CreateToggle({
		Name = "auto throw",
		Description = "clicks your own throw button to charge and release when a receiver is open. needs the Roblox window focused.",
		Flag = "qb_autothrow",
		Value = CFG.autoThrow,
		Callback = function(v)
			CFG.autoThrow = v
			autoAt = 0
			saveCfg()
		end,
	})
	reg("qb_safecatch", "safeCatch")
	autoTab:CreateToggle({
		Name = "safe catch",
		Description = "never forces a throw into coverage. auto play waits for separation instead of releasing a covered pass after the hold timer. this avoids the throw, it does not change the game's catch roll.",
		Flag = "qb_safecatch",
		Value = CFG.safeCatch,
		Callback = function(v)
			CFG.safeCatch = v
			autoAt = 0
			saveCfg()
		end,
	})
	reg("qb_delay", "autoDelay")
	autoTab:CreateSlider({
		Name = "hold time",
		Description = "how long the throw charges before the release click. the solver makes the result independent of the charge.",
		Range = { 0.15, 1.2 },
		Increment = 0.05,
		Value = CFG.autoDelay,
		Suffix = " s",
		Flag = "qb_delay",
		Callback = function(v)
			CFG.autoDelay = v
			saveCfg()
		end,
	})
	reg("qb_respectui", "respectUi")
	autoTab:CreateToggle({
		Name = "respect open menus",
		Description = "stops auto throw while the game reports a UI panel open.",
		Flag = "qb_respectui",
		Value = CFG.respectUi,
		Callback = function(v)
			CFG.respectUi = v
			saveCfg()
		end,
	})
	reg("qb_wait", "holdWait")
	autoTab:CreateSlider({
		Name = "wait for open",
		Description = "seconds auto play holds the ball for a receiver to separate before releasing into coverage.",
		Range = { 0.5, 6 },
		Increment = 0.1,
		Value = CFG.holdWait,
		Suffix = " s",
		Flag = "qb_wait",
		Callback = function(v)
			CFG.holdWait = v
			saveCfg()
		end,
	})
	autoTab:CreateButton({
		Name = "throw now",
		Description = "one click: starts the charge if idle, releases it if already charging.",
		Callback = function()
			releaseNow()
		end,
	})
	autoTab:CreateText({
		Name = "target pick note",
		Text = "the aimbot stays on. pick a receiver in AIM -> AIMBOT TARGET, or press F / cycle target to move the lock. 'back to auto pick' lets the aimbot choose again.",
	})
	autoTab:CreateButton({
		Name = "cycle target",
		Description = "moves the lock to the next receiver in the list. same as F.",
		Callback = function()
			nextLock()
		end,
	})
	autoTab:CreateButton({
		Name = "back to auto pick",
		Description = "clears the lock and lets the aimbot choose again.",
		Callback = function()
			clearLock()
		end,
	})

	autoTab:CreateSection({ Name = "AUTO PLAY" })
	autoTab:CreateText({
		Name = "auto play note",
		Text = "auto play queues through the game's own play state machine, so it respects the lobby, tutorial and match flow. while a match is live it throws even if auto throw is off. auto rebirth only fires when money covers the next cost.",
	})
	reg("qb_play", "autoPlay")
	autoTab:CreateToggle({
		Name = "auto play",
		Description = "queues a new match whenever you are not already in one, then plays it with the aimbot.",
		Flag = "qb_play",
		Value = CFG.autoPlay,
		Callback = function(v)
			CFG.autoPlay = v
			playAt = 0
			if v then
				autoAt = 0
			end
			saveCfg()
		end,
	})
	reg("qb_play_delay", "playDelay")
	autoTab:CreateSlider({
		Name = "queue retry",
		Description = "seconds between attempts when the game reports that a match cannot start yet.",
		Range = { 2, 30 },
		Increment = 1,
		Value = CFG.playDelay,
		Suffix = " s",
		Flag = "qb_play_delay",
		Callback = function(v)
			CFG.playDelay = v
			saveCfg()
		end,
	})
	reg("qb_rebirth", "autoRebirth")
	autoTab:CreateToggle({
		Name = "auto rebirth",
		Description = "takes the next rebirth as soon as the money covers it, through the Rebirth panel request.",
		Flag = "qb_rebirth",
		Value = CFG.autoRebirth,
		Callback = function(v)
			CFG.autoRebirth = v
			rebirthAt = 0
			saveCfg()
		end,
	})
	reg("qb_rebirth_delay", "rebirthDelay")
	autoTab:CreateSlider({
		Name = "rebirth check",
		Description = "seconds between affordability checks. the server still validates every request.",
		Range = { 3, 60 },
		Increment = 1,
		Value = CFG.rebirthDelay,
		Suffix = " s",
		Flag = "qb_rebirth_delay",
		Callback = function(v)
			CFG.rebirthDelay = v
			saveCfg()
		end,
	})
	ui.farm = autoTab:CreateText({ Name = "farm state", Text = farmText() })
	autoTab:CreateButton({
		Name = "start match now",
		Description = "one queue attempt through ModeController.StartGame.",
		Callback = function()
			startMatch()
		end,
	})
	autoTab:CreateButton({
		Name = "rebirth now",
		Description = "one RebirthPanel request, even if auto rebirth is off.",
		Callback = function()
			requestRebirth()
		end,
	})

	-- BYPASS
	local acTab = w:CreateTab({ Name = "BYPASS" })
	acTab:CreateSection({ Name = "MOVE GUARD" })
	ui.acState = acTab:CreateText({ Name = "layers", Text = ac.stateText() })
	ui.acCover = acTab:CreateText({ Name = "coverage", Text = ac.coverageText() })
	reg("qb_ac_closure", "closure")
	acTab:CreateToggle({
		Name = "closure hook",
		Description = "detaches MoveGuard._check, the exact closure its 0.25s loop calls. client-side only.",
		Flag = "qb_ac_closure",
		Value = CFG.closure,
		Callback = function(v)
			CFG.closure = v
			if v then
				if not ac.installClosure() then
					ac.notify("closure layer unavailable - guard table not found")
				end
			else
				ac.removeClosure()
			end
			saveCfg()
		end,
	})
	reg("qb_ac_block", "block")
	acTab:CreateToggle({
		Name = "block AntiCheatGuard",
		Description = "namecall hook drops the report remote. reports still show in LOG, they just never leave.",
		Flag = "qb_ac_block",
		Value = CFG.block,
		Callback = function(v)
			CFG.block = v
			if v then
				ac.installNamecall()
			end
			saveCfg()
		end,
	})
	reg("qb_ac_index", "index")
	acTab:CreateToggle({
		Name = "index spoof",
		Description = "caps WalkSpeed, JumpPower, JumpHeight and Gravity reads made by game code.",
		Flag = "qb_ac_index",
		Value = CFG.index,
		Callback = function(v)
			CFG.index = v
			if v then
				ac.installIndex()
			else
				ac.removeIndex()
			end
			saveCfg()
		end,
	})

	acTab:CreateSection({ Name = "ANIMATION GUARDS" })
	reg("qb_ac_anim", "anim")
	acTab:CreateToggle({
		Name = "AnimGuard whitelist",
		Description = "AnimWhitelist.allowed answers true, so the client stops policing other players' tracks.",
		Flag = "qb_ac_anim",
		Value = CFG.anim,
		Callback = function(v)
			CFG.anim = v
			if v then
				if not ac.installAnim() then
					ac.notify("AnimWhitelist not found - animation layer unavailable")
				end
			else
				ac.removeAnim()
			end
			saveCfg()
		end,
	})
	reg("qb_ac_tracks", "animTracks")
	acTab:CreateToggle({
		Name = "animation track cap",
		Description = "stubs AnimTrackGuard.Prune, the 16-track limiter. visual only, no report channel.",
		Flag = "qb_ac_tracks",
		Value = CFG.animTracks,
		Callback = function(v)
			CFG.animTracks = v
			if v then
				if not ac.installTrackGuard() then
					ac.notify("AnimTrackGuard not found - track layer unavailable")
				end
			else
				ac.removeTrackGuard()
			end
			saveCfg()
		end,
	})

	acTab:CreateSection({ Name = "FALLBACKS  (replicated attributes)" })
	acTab:CreateText({
		Name = "fallback note",
		Text = "these write attributes the server can see. only needed if the closure or namecall layers fail.",
	})
	reg("qb_ac_admin", "admin")
	acTab:CreateToggle({
		Name = "ACAdmin attribute",
		Description = "MoveGuard returns before checking anything. replicated - the server can read it.",
		Flag = "qb_ac_admin",
		Value = CFG.admin,
		Callback = function(v)
			CFG.admin = v
			ac.applyAdmin(v)
			saveCfg()
		end,
	})
	reg("qb_ac_inflate", "inflate")
	acTab:CreateToggle({
		Name = "attribute inflation",
		Description = "forces ACWalk, ACWalkCap and the jump limits high. replicated.",
		Flag = "qb_ac_inflate",
		Value = CFG.inflate,
		Callback = function(v)
			CFG.inflate = v
			ac.applyInflate(v)
			saveCfg()
		end,
	})

	acTab:CreateSection({ Name = "TOOLS" })
	acTab:CreateButton({
		Name = "arm all client-side layers",
		Description = "closure + block + index + AnimGuard. no replicated attributes touched.",
		Callback = function()
			CFG.closure = true
			CFG.block = true
			CFG.index = true
			CFG.anim = true
			ac.installClosure()
			ac.installNamecall()
			ac.installIndex()
			ac.installAnim()
			for _, flag in ipairs({ "qb_ac_closure", "qb_ac_block", "qb_ac_index", "qb_ac_anim" }) do
				pcall(function()
					w:Set(flag, true)
				end)
			end
			saveCfg()
			ac.notify("client-side layers armed: closure + block + index + AnimGuard")
		end,
	})
	acTab:CreateButton({
		Name = "probe guard",
		Description = "re-finds MoveGuard and reports which layers are attached.",
		Callback = function()
			ac.refreshRemote()
			local source = ac.findGuard()
			ac.notify(string.format(
				"guard %s | closure %s | remote %s | namecall %s",
				tostring(source), ac.closure and "attached" or "detached",
				ac.remote and "found" or "missing",
				ac.namecallHook and "hooked" or "none"
			))
		end,
	})
	acTab:CreateButton({
		Name = "panic  (P)",
		Description = "removes the aim hook, every bypass layer and restores the modified values.",
		Callback = function()
			if _G.SlimQbAim and _G.SlimQbAim.panic then
				_G.SlimQbAim.panic()
			end
		end,
	})

	acTab:CreateSection({ Name = "LOG" })
	ui.acCounters = acTab:CreateText({ Name = "counters", Text = "reports 0  |  blocked 0" })
	ui.acLogText = acTab:CreateText({ Name = "events", Text = "-" })
	acTab:CreateButton({
		Name = "clear log",
		Callback = function()
			ac.events = {}
		end,
	})
	acTab:CreateText({
		Name = "honesty",
		Text = "a server-side kick cannot be cancelled by a client hook. these layers stop client reports and client reads.",
	})

	-- MOVE
	local moveTab = w:CreateTab({ Name = "MOVE" })
	moveTab:CreateSection({ Name = "SPEED" })
	moveTab:CreateText({
		Name = "speed note",
		Text = "DriveExtras rewrites WalkSpeed to 18 every frame. root step moves the root part instead.",
	})
	reg("qb_step", "rootStep")
	moveTab:CreateToggle({
		Name = "root step",
		Description = "HumanoidRootPart.CFrame movement along your input direction.",
		Flag = "qb_step",
		Value = CFG.rootStep,
		Callback = function(v)
			CFG.rootStep = v
			saveCfg()
		end,
	})
	reg("qb_step_extra", "stepExtra")
	moveTab:CreateSlider({
		Name = "extra studs per second",
		Range = { 0, 60 },
		Increment = 1,
		Value = CFG.stepExtra,
		Suffix = " studs",
		Flag = "qb_step_extra",
		Callback = function(v)
			CFG.stepExtra = v
			saveCfg()
		end,
	})
	reg("qb_ground", "groundOnly")
	moveTab:CreateToggle({
		Name = "ground only",
		Description = "stop stepping while airborne. keeps movement closer to normal physics.",
		Flag = "qb_ground",
		Value = CFG.groundOnly,
		Callback = function(v)
			CFG.groundOnly = v
			saveCfg()
		end,
	})

	moveTab:CreateSection({ Name = "SPRINT" })
	moveTab:CreateText({
		Name = "sprint note",
		Text = "sprint writes WalkSpeed at Camera+4, after DriveExtras and the walk override, so the speed sticks and no stamina is spent. needs closure, ACAdmin or inflation or MoveGuard clamps it.",
	})
	reg("qb_infsprint", "infSprint")
	moveTab:CreateToggle({
		Name = "infinite sprint",
		Description = "hold LeftShift to sprint at the slider speed. the game's stamina is never checked.",
		Flag = "qb_infsprint",
		Value = CFG.infSprint,
		Callback = function(v)
			CFG.infSprint = v
			ac.applySprint(ac.sprintEnabled())
			saveCfg()
		end,
	})
	reg("qb_autosprint", "autoSprint")
	moveTab:CreateToggle({
		Name = "auto sprint",
		Description = "sprint whenever you are moving, no LeftShift needed.",
		Flag = "qb_autosprint",
		Value = CFG.autoSprint,
		Callback = function(v)
			CFG.autoSprint = v
			ac.applySprint(ac.sprintEnabled())
			saveCfg()
		end,
	})
	reg("qb_sprint_value", "sprintSpeed")
	moveTab:CreateSlider({
		Name = "sprint speed",
		Range = { 18, 80 },
		Increment = 1,
		Value = CFG.sprintSpeed,
		Suffix = " ws",
		Flag = "qb_sprint_value",
		Callback = function(v)
			CFG.sprintSpeed = v
			saveCfg()
		end,
	})

	moveTab:CreateSection({ Name = "DIRECT SPEED" })
	moveTab:CreateText({
		Name = "direct speed note",
		Text = "writes WalkSpeed after the controller's own write. needs closure, ACAdmin or inflation or MoveGuard clamps it.",
	})
	reg("qb_walkspeed", "walkSpeed")
	moveTab:CreateToggle({
		Name = "walk speed override",
		Description = "physics movement at the chosen WalkSpeed instead of root stepping.",
		Flag = "qb_walkspeed",
		Value = CFG.walkSpeed,
		Callback = function(v)
			CFG.walkSpeed = v
			ac.applyWalkSpeed(v)
			saveCfg()
		end,
	})
	reg("qb_ws_value", "walkSpeedValue")
	moveTab:CreateSlider({
		Name = "walk speed",
		Range = { 18, 150 },
		Increment = 1,
		Value = CFG.walkSpeedValue,
		Suffix = " ws",
		Flag = "qb_ws_value",
		Callback = function(v)
			CFG.walkSpeedValue = v
			saveCfg()
		end,
	})

	moveTab:CreateSection({ Name = "JUMP" })
	reg("qb_infjump", "infJump")
	moveTab:CreateToggle({
		Name = "infinite jump",
		Flag = "qb_infjump",
		Value = CFG.infJump,
		Callback = function(v)
			CFG.infJump = v
			saveCfg()
		end,
	})
	reg("qb_jump", "customJump")
	moveTab:CreateToggle({
		Name = "custom jump height",
		Description = "writes JumpHeight. needs closure, ACAdmin or inflation to survive the guard.",
		Flag = "qb_jump",
		Value = CFG.customJump,
		Callback = function(v)
			CFG.customJump = v
			ac.applyJump(v)
			saveCfg()
		end,
	})
	reg("qb_jump_height", "jumpHeight")
	moveTab:CreateSlider({
		Name = "jump height",
		Range = { 7, 60 },
		Increment = 1,
		Value = CFG.jumpHeight,
		Suffix = " studs",
		Flag = "qb_jump_height",
		Callback = function(v)
			CFG.jumpHeight = v
			if CFG.customJump then
				ac.applyJump(true)
			end
			saveCfg()
		end,
	})

	moveTab:CreateSection({ Name = "GRAVITY" })
	reg("qb_gravity", "lowGravity")
	moveTab:CreateToggle({
		Name = "low gravity",
		Description = "writes Workspace.Gravity. needs closure, ACAdmin or inflation to survive the guard.",
		Flag = "qb_gravity",
		Value = CFG.lowGravity,
		Callback = function(v)
			CFG.lowGravity = v
			ac.applyGravity(v)
			saveCfg()
		end,
	})
	reg("qb_gravity_value", "gravity")
	moveTab:CreateSlider({
		Name = "workspace gravity",
		Range = { 20, 300 },
		Increment = 10,
		Value = CFG.gravity,
		Suffix = " g",
		Flag = "qb_gravity_value",
		Callback = function(v)
			CFG.gravity = v
			if CFG.lowGravity then
				ac.applyGravity(true)
			end
			saveCfg()
		end,
	})

	-- INFO
	local infoTab = w:CreateTab({ Name = "INFO" })
	ui.status = infoTab:CreateText({ Name = "state", Text = "starting" })
	infoTab:CreateButton({
		Name = "print probe",
		Callback = function()
			local api = _G.SlimQbAim
			if api and api.probe then
				print("[QBAIM]\n" .. api.probe())
			end
		end,
	})
	infoTab:CreateButton({
		Name = "probe catch system",
		Description = "prints the ball, throw, rig and receiver fields, read-only. paste the console output back to see whether the catch can be hooked on the client.",
		Callback = function()
			local api = _G.SlimQbAim
			if api and api.catchProbe then
				print("[QBAIM catch]\n" .. api.catchProbe())
			end
		end,
	})
	infoTab:CreateButton({
		Name = "probe real players",
		Description = "prints the live Players, GameRigs.All, Home.Receivers, Away.Covers and the throwable list. read-only. paste the console output if a real player still does not appear.",
		Callback = function()
			local api = _G.SlimQbAim
			if api and api.playerProbe then
				print("[QBAIM players]\n" .. api.playerProbe())
			end
		end,
	})
	infoTab:CreateButton({
		Name = "reset stats",
		Callback = function()
			stats.throws = 0
			stats.aimed = 0
			stats.auto = 0
			stats.missed = 0
		end,
	})
	infoTab:CreateButton({
		Name = "panic  (P)",
		Description = "removes every hook, restores the controller fields and clears the overlay.",
		Callback = function()
			if _G.SlimQbAim and _G.SlimQbAim.panic then
				_G.SlimQbAim.panic()
			end
		end,
	})
	infoTab:CreateButton({
		Name = "unload",
		Callback = function()
			if _G.SlimQbAim and _G.SlimQbAim.stop then
				_G.SlimQbAim.stop()
			end
		end,
	})

	return true
end

--// status --------------------------------------------------------------------

local function keyDump(tbl, filter, max)
	if type(tbl) ~= "table" then
		return "nil"
	end
	local rows = {}
	local f = filter and filter:lower() or nil
	for k, v in pairs(tbl) do
		local name = tostring(k)
		if not f or name:lower():find(f, 1, true) then
			rows[#rows + 1] = name .. "=" .. typeof(v)
		end
	end
	table.sort(rows)
	max = max or 120
	if #rows > max then
		local kept = {}
		for i = 1, max do
			kept[i] = rows[i]
		end
		kept[#kept + 1] = "..." .. tostring(#rows - max) .. " more"
		rows = kept
	end
	return table.concat(rows, ", ")
end

-- read-only dump: no hook, no write. used to find the catch controller before
-- touching anything. if the catch is resolved on the server there is nothing
-- here to hook, and that is worth knowing before writing a fake catch path.
local function catchProbe()
	local recs = GR and GR.Home and GR.Home.Receivers
	local r = type(recs) == "table" and recs[1] or nil
	local rows = {
		"ballController: " .. keyDump(BC),
		"throwController: " .. keyDump(TC),
		"gameRigs: " .. keyDump(GR),
		"gameRigs.Home: " .. keyDump(GR and GR.Home),
		"receiver[1]: " .. keyDump(r),
		"ball catch/drop: " .. keyDump(BC, "catch") .. " | " .. keyDump(BC, "drop"),
		"throw catch/drop: " .. keyDump(TC, "catch") .. " | " .. keyDump(TC, "drop"),
		"rigs catch/drop: " .. keyDump(GR, "catch") .. " | " .. keyDump(GR, "drop"),
		"receiver catch/hand/drop: "
			.. keyDump(r, "catch") .. " | "
			.. keyDump(r, "hand") .. " | "
			.. keyDump(r, "drop"),
	}
	return table.concat(rows, "\n")
end

local function playerProbe()
	local side = localSide()
	local rows = {
		"place=" .. tostring(game.PlaceId),
		"localSide=" .. tostring(side),
		"players=" .. tostring(#Players:GetPlayers()),
	}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP then
			local ch = p.Character
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			rows[#rows + 1] = string.format(
				"player %s | display %s | team %s | char %s | root %s | side %s | pos %s",
				p.Name,
				p.DisplayName,
				p.Team and p.Team.Name or "nil",
				ch and ch.Name or "nil",
				root and root.Name or "nil",
				root and (rigSideOfRoot(root) or "nil") or "nil",
				root and string.format("%.0f,%.0f,%.0f", root.Position.X, root.Position.Y, root.Position.Z)
					or "nil"
			)
		end
	end
	local all = GR and GR.All
	if type(all) == "table" then
		local n = 0
		for _ in pairs(all) do
			n = n + 1
		end
		rows[#rows + 1] = "GR.All entries=" .. tostring(n)
		for i, r in ipairs(all) do
			if i > 20 then
				rows[#rows + 1] = "..."
				break
			end
			if type(r) == "table" then
				local root = rootOfRig(r)
				rows[#rows + 1] = string.format(
					"all[%d] name=%s side=%s slot=%s job=%s root=%s pass=%s pos=%s",
					i,
					tostring(r.Name),
					tostring(r.Side),
					tostring(r.Slot),
					tostring(r.Job),
					root and tostring(root.Parent and root.Parent.Name) or "nil",
					typeof(r.PassSpot) == "Vector3" and "yes" or "no",
					root and string.format("%.0f,%.0f,%.0f", root.Position.X, root.Position.Y, root.Position.Z)
						or tostring(r.Pos)
				)
			end
		end
	else
		rows[#rows + 1] = "GR.All=nil"
	end
	local recs = GR and GR.Home and GR.Home.Receivers
	if type(recs) == "table" then
		rows[#rows + 1] = "Home.Receivers=" .. tostring(#recs)
		for i = 1, math.min(#recs, 12) do
			local r = recs[i]
			if type(r) == "table" then
				rows[#rows + 1] = string.format(
					"home[%d] name=%s slot=%s job=%s root=%s pass=%s",
					i,
					tostring(r.Name),
					tostring(r.Slot),
					tostring(r.Job),
					rootOfRig(r) and "yes" or "no",
					typeof(r.PassSpot) == "Vector3" and "yes" or "no"
				)
			end
		end
	else
		rows[#rows + 1] = "Home.Receivers=nil"
	end
	local covers = GR and GR.Away and GR.Away.Covers
	rows[#rows + 1] = "Away.Covers=" .. tostring(type(covers) == "table" and #covers or 0)
	local pool = receiverRigs(side)
	rows[#rows + 1] = "throwable records=" .. tostring(#pool)
	for i = 1, math.min(#pool, 16) do
		local r = pool[i]
		rows[#rows + 1] = string.format(
			"pool[%d] name=%s slot=%s job=%s real=%s unknown=%s",
			i,
			tostring(r.Name),
			tostring(r.Slot),
			tostring(r.Job),
			tostring(r.Player ~= nil),
			tostring(r.__unknown == true)
		)
	end
	return table.concat(rows, "\n")
end

local function probe()
	local e = pick
	local rows = {
		"place=" .. tostring(game.PlaceId),
		"throwController=" .. tostring(TC ~= nil),
		"ballController=" .. tostring(BC ~= nil),
		"throwConfig=" .. tostring(TCfg ~= nil),
		"launchHook=" .. tostring(hooks.launch == true),
		"snap=" .. tostring(hooks.snap == true),
		"powerAssist=" .. tostring(hooks.powerSaved == true),
		"rankOverride=" .. tostring(hooks.rankSaved == true),
		"receivers=" .. tostring(#targetList),
		"pick=" .. (e and (e.name .. " " .. string.format("%.1f st", e.dist)) or "nil"),
		"throws=" .. tostring(stats.throws),
		"aimed=" .. tostring(stats.aimed),
		"auto=" .. tostring(stats.auto),
		"plays=" .. tostring(stats.plays),
		"rebirths=" .. tostring(stats.rebirths),
		"lastPlay=" .. tostring(stats.lastPlay or "nil"),
		"lastRebirth=" .. tostring(stats.lastRebirth or "nil"),
		"farm=" .. farmText(),
		"skipped=" .. tostring(stats.missed),
		"last=" .. (stats.lastName and (stats.lastName .. " |v| " .. string.format("%.1f", stats.lastVel and stats.lastVel.Magnitude or 0)) or "nil"),
		ac.probe(),
	}
	return table.concat(rows, "\n")
end

--// boot ----------------------------------------------------------------------

buildHud()
ensureMarkers()

local bootCfg = {}
for k, v in pairs(CFG) do
	bootCfg[k] = v
end

setEnabled(CFG.enabled)
buildUI()

-- Rayfield replays its own saved flags while creating elements, which fires the
-- callbacks and can silently override the values we just loaded. put the boot
-- snapshot back, then push it into the UI so the controls match.
for k, v in pairs(bootCfg) do
	CFG[k] = v
end
syncUi()
setEnabled(CFG.enabled)
ac.installBypass()
ac.applyBypassAll()

local function panic()
	CFG.enabled = false
	CFG.autoThrow = false
	CFG.autoPlay = false
	CFG.autoRebirth = false
	CFG.esp = false
	CFG.arc = false
	CFG.defLines = false
	CFG.snap = false
	CFG.closure = false
	CFG.block = false
	CFG.index = false
	CFG.anim = false
	CFG.animTracks = false
	CFG.admin = false
	CFG.inflate = false
	CFG.rootStep = false
	CFG.infJump = false
	CFG.customJump = false
	CFG.lowGravity = false
	CFG.walkSpeed = false
	CFG.infSprint = false
	CFG.autoSprint = false
	restoreAll()
	ac.stopBypass()
	clearVisuals()
	syncUi()
	saveCfg()
	print("[QBAIM] panic - aim hook and bypass removed, controller fields restored")
end

local function shutdown()
	if dead then
		return
	end
	dead = true
	ac.stopBypass()
	if ac.jumpConn then
		pcall(function()
			ac.jumpConn:Disconnect()
		end)
		ac.jumpConn = nil
	end
	pcall(function()
		RunService:UnbindFromRenderStep("SlimQbAcWalkSpeed")
	end)
	restoreAll()
	clearVisuals()
	if ui.window then
		pcall(function()
			ui.window:Unload()
		end)
	end
	if hudGui then
		hudGui:Destroy()
	end
	if fxFolder then
		fxFolder:Destroy()
	end
	if inputConn then
		pcall(function()
			inputConn:Disconnect()
		end)
		inputConn = nil
	end
	pcall(function()
		RunService:UnbindFromRenderStep(TAG)
	end)
	saveCfg()
	_G.SlimQbAim = nil
	print("[QBAIM] unloaded")
end

_G.SlimQbAim = {
	cfg = CFG,
	stats = stats,
	pick = function()
		return pick
	end,
	list = function()
		return targetList
	end,
	probe = probe,
	catchProbe = catchProbe,
	playerProbe = playerProbe,
	throw = releaseNow,
	cycle = function(n)
		clearLock()
		cycle = tonumber(n) or 0
	end,
	lock = function(name)
		for _, rec in ipairs(receiverRecords()) do
			if tostring(rec.name) == tostring(name) or tostring(rec.slot) == tostring(name) then
				setLock(rec)
				return true
			end
		end
		return false
	end,
	unlock = clearLock,
	next = nextLock,
	locked = function()
		return lockName, lockSlot
	end,
	panic = panic,
	stop = shutdown,
	apply = function()
		setEnabled(CFG.enabled)
	end,
	play = startMatch,
	rebirth = requestRebirth,
	farm = farmText,
	sprint = function(on)
		CFG.infSprint = on ~= false
		ac.applySprint(ac.sprintEnabled())
		syncUi()
		saveCfg()
	end,
	autoSprint = function(on)
		CFG.autoSprint = on ~= false
		ac.applySprint(ac.sprintEnabled())
		syncUi()
		saveCfg()
	end,
	ac = {
		state = ac.stateText,
		probe = ac.probe,
		start = ac.installBypass,
		stop = ac.stopBypass,
		arm = ac.applyBypassAll,
	},
}

--// input ---------------------------------------------------------------------

inputConn = UserInputService.InputBegan:Connect(function(input, gpe)
	if dead or gpe then
		return
	end
	local kc = input.KeyCode
	if kc == Enum.KeyCode.RightShift then
		setEnabled(not CFG.enabled)
		syncUi()
	elseif kc == Enum.KeyCode.G then
		CFG.autoTarget = not CFG.autoTarget
		if CFG.autoTarget then
			cycle = 0
		end
		syncUi()
		saveCfg()
	elseif kc == Enum.KeyCode.F then
		nextLock()
	elseif kc == Enum.KeyCode.H then
		CFG.esp = not CFG.esp
		CFG.arc = CFG.esp
		if not CFG.esp then
			clearVisuals()
		end
		syncUi()
		saveCfg()
	elseif kc == Enum.KeyCode.T then
		CFG.autoThrow = not CFG.autoThrow
		autoAt = 0
		syncUi()
		saveCfg()
	elseif kc == Enum.KeyCode.E then
		releaseNow()
	elseif kc == Enum.KeyCode.P then
		panic()
	end
end)

--// loop ----------------------------------------------------------------------

RunService:BindToRenderStep(TAG, Enum.RenderPriority.Camera.Value + 2, function()
	if dead then
		return
	end
	local now = os.clock()
	if now - lastBuild >= 0.05 then
		lastBuild = now
		build(now)
	end
	if CFG.enabled then
		drawVisuals()
		drawRealEsp()
		drawArc()
		drawDefLine()
		autoFarmStep(now)
		autoThrowStep(now, CFG.autoPlay)
	else
		clearVisuals()
	end
	updateHud(now)

	if ui.status and now - lastStatus >= 0.4 then
		lastStatus = now
		pcall(function()
			ui.status:Set(string.format(
				"%s\nreceivers %d  |  humans %d\n%s",
				statusLine,
				#targetList,
				math.max(0, #Players:GetPlayers() - 1),
				pick and (pick.name .. (manualPick and "  locked" or "") .. "  " .. string.format("%.0f st", pick.dist)) or "no target"
			))
		end)
		if ui.farm then
			pcall(function()
				ui.farm:Set(farmText())
			end)
		end
		if ui.lockText then
			pcall(function()
				if lockSlot ~= nil or lockName ~= nil then
					ui.lockText:Set(
						(manualPick and "locked: " or "waiting: ")
						.. tostring(lockName or ("slot " .. tostring(lockSlot)))
						.. (manualPick and "" or "  (auto pick for now)")
					)
				else
					ui.lockText:Set("aimbot auto target")
				end
			end)
		end
	end
end)

print("[QBAIM] loaded - RightShift on/off | F cycle | G auto | H visuals | T auto throw | E throw | P panic")
end

--// embedded suite: taf_bypass  (from taf_bypass.luau) =========================
Hub.SUITE.taf_bypass = function()
--[[
	TAF // AC BYPASS -- place 125942529011157

	the guard, from MoveGuard source
	  every 0.25s it reads LocalPlayer:GetAttribute("ACAdmin"); true means return.
	  then, per value, if actual is more than 0.5 above the allowed value for 0.6s:
	    WalkSpeed   allowed = max(Humanoid.ACWalk, Workspace.ACWalkCap)
	    JumpPower   allowed = Humanoid.ACJumpPower
	    JumpHeight  allowed = Humanoid.ACJumpHeight
	    Gravity     allowed = Workspace.ACGravity, tolerance 1
	  it fires ReplicatedStorage.AntiCheatGuard:FireServer(name, actual, allowed)
	  and clamps the value back to allowed.

	the five techniques, in the order they are layered here
	  1. closure hook   MoveGuard exposes _check, the exact closure its loop calls.
	                    hookfunction on it makes the whole guard a no-op. client-only.
	  2. registry scan  if the module path is gone, the guard table is found by
	                    walking getregistry() for CHECK=0.25 / HOLD=0.6.
	  3. index hook     __index on the Instance metatable caps WalkSpeed, JumpPower,
	                    JumpHeight and Gravity reads made by game code.
	  4. namecall hook  __namecall drops AntiCheatGuard before it leaves the client.
	  5. root step      HumanoidRootPart.CFrame movement, because DriveExtras holds
	                    Humanoid.WalkSpeed at GameConfig.QBWalkSpeed (18) every frame.

	the other half of this game's client anti-cheat
	  TAF_Shared.Client.AnimGuard stops other players' animation tracks that are
	  not in AnimWhitelist. allowed() is a plain table field that the guard calls
	  on every track, so replacing it disables the check without touching any
	  replicated attribute and without a hook.
	  TAF_Shared.Client.AnimTrackGuard prunes any player above 16 playing tracks;
	  its Prune is also called through the module table, so it can be swapped.

	the attribute layers are optional fallbacks, off by default
	  ACAdmin and attribute inflation both write attributes that REPLICATE to the
	  server. they work, but they are visible on the server and the other layers
	  are not. turn them on if the closure/namecall layers ever fail.

	MOVEMENT
	  DriveExtras rewrites WalkSpeed to 18 every frame, so a plain set loses.
	  root step moves the root part and leaves WalkSpeed alone.
	  direct speed rewrites WalkSpeed on RenderStep at Camera+3, which lands
	  after the controller's own write and holds. it needs guard coverage.

	a server-side kick cannot be cancelled by any client hook. layers here only
	stop what the client reports and what client code reads.

	_G.TafAcBypass exports cfg/state/probe/panic/stop/testReport/armAll.
--]]

if game.PlaceId ~= 125942529011157 then
	warn("[TAF-AC] loaded outside place 125942529011157 (this is " .. tostring(game.PlaceId) .. ")")
end

local prev = _G.TafAcBypass
if prev and prev.stop then
	pcall(prev.stop)
end

local DEFAULTS = {
	closure = true,
	block = true,
	index = true,
	admin = false,
	inflate = false,
	rootStep = false,
	groundOnly = true,
	stepExtra = 20,
	infJump = false,
	customJump = false,
	jumpHeight = 20,
	lowGravity = false,
	gravity = 80,
	spoofWalk = 18,
	spoofJumpPower = 50,
	spoofJumpHeight = 7.2,
	spoofGravity = 196.2,
	anim = true,
	animTracks = false,
	walkSpeed = false,
	walkSpeedValue = 30,
}

local CFG = {}
for key, value in pairs(DEFAULTS) do
	CFG[key] = value
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LP = Players.LocalPlayer

local dead = false
local ui = {}
local events = {}
local logDirty = false
local lastEventAt = 0

local reportsSeen = 0
local reportsBlocked = 0
local closureHits = 0
local indexReads = 0
local animAllowedCalls = 0
local animTrackBlocks = 0
local defensePending = false

local whitelist = nil
local whitelistAllowedOriginal = nil
local whitelistHooked = false
local trackGuard = nil
local trackGuardPruneOriginal = nil
local trackGuardHooked = false
local walkSpeedBound = false

local acRemote = nil
local indexTarget = nil
local guardTable = nil
local guardSource = nil
local guardCheckOriginal = nil
local closureHooked = false

local saved = {
	admin = false,
	adminValue = nil,
	humanoid = nil,
	attrs = nil,
	jump = nil,
	jumpHumanoid = nil,
	gravity = nil,
	walkSpeed = nil,
	walkHumanoid = nil,
}

--// cfg file --------------------------------------------------------------------

local CFG_FILE = "slimhub-taf-acbypass.cfg"
local savedCfg = ""

local function saveCfg()
	if not writefile then return end
	local parts = {}
	for k, v in pairs(CFG) do
		local t = type(v)
		if t == "boolean" or t == "number" then
			table.insert(parts, k .. "=" .. tostring(v))
		end
	end
	table.sort(parts)
	local blob = table.concat(parts, "\n")
	if blob == savedCfg then return end
	savedCfg = blob
	pcall(writefile, CFG_FILE, blob)
end

local function loadCfg()
	if not (isfile and readfile and isfile(CFG_FILE)) then return end
	local ok, data = pcall(readfile, CFG_FILE)
	if not ok or type(data) ~= "string" then return end
	for line in string.gmatch(data, "[^%r%n]+") do
		local k, v = string.match(line, "^([%w_]+)=(.*)$")
		if k and DEFAULTS[k] ~= nil then
			if v == "true" then
				CFG[k] = true
			elseif v == "false" then
				CFG[k] = false
			elseif tonumber(v) then
				CFG[k] = tonumber(v)
			end
		end
	end
end

if prev and type(prev.cfg) == "table" then
	for k, v in pairs(prev.cfg) do
		if DEFAULTS[k] ~= nil then
			CFG[k] = v
		end
	end
else
	pcall(loadCfg)
end

--// log -------------------------------------------------------------------------

local function pushEvent(text, force)
	if dead then return end
	local now = os.clock()
	if not force and now - lastEventAt < 0.05 then return end
	lastEventAt = now
	table.insert(events, 1, os.date("%H:%M:%S") .. "  " .. text)
	while #events > 60 do
		table.remove(events)
	end
	logDirty = true
end

local function notify(text)
	print("[TAF-AC] " .. tostring(text))
	if ui.window and ui.window.Notify then
		pcall(function()
			ui.window:Notify({ title = "TAF // AC BYPASS", content = tostring(text), duration = 3 })
		end)
	end
	pushEvent(tostring(text), true)
end

--// guard discovery -------------------------------------------------------------

local function currentHumanoid()
	local character = LP.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function refreshAcRemote()
	local candidate = ReplicatedStorage:FindFirstChild("AntiCheatGuard")
	if candidate and candidate:IsA("BaseRemoteEvent") then
		acRemote = candidate
	else
		acRemote = nil
	end
end

local function guardTableFromRegistry()
	local ok, registry = pcall(getregistry)
	if not ok or type(registry) ~= "table" then return nil end
	for _, value in pairs(registry) do
		if type(value) == "table"
			and rawget(value, "CHECK") == 0.25
			and rawget(value, "HOLD") == 0.6
			and type(rawget(value, "_check")) == "function"
		then
			return value
		end
	end
	return nil
end

local function findGuard()
	local playerScripts = LP:FindFirstChild("PlayerScripts")
	local controllers = playerScripts and playerScripts:FindFirstChild("Controllers")
	local module = controllers and controllers:FindFirstChild("MoveGuard")
	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" and type(result._check) == "function" then
			guardTable = result
			guardSource = "module"
			return "module"
		end
	end
	local found = guardTableFromRegistry()
	if found then
		guardTable = found
		guardSource = "registry"
		return "registry"
	end
	guardTable = nil
	guardSource = nil
	return nil
end

--// layer 1: closure hook -------------------------------------------------------

local function installClosure()
	if dead then return false end
	if closureHooked then return true end
	if not guardTable or type(guardTable._check) ~= "function" then
		if not findGuard() then return false end
	end
	local ok, original = pcall(hookfunction, guardTable._check, function()
		closureHits = closureHits + 1
	end)
	if ok and original then
		guardCheckOriginal = original
		closureHooked = true
		pushEvent("closure attached via " .. tostring(guardSource), true)
		return true
	end
	return false
end

local function removeClosure()
	if not closureHooked then return end
	pcall(hookfunction, guardTable._check, guardCheckOriginal)
	guardCheckOriginal = nil
	closureHooked = false
end

--// layer 2: index hook ---------------------------------------------------------

local mt = getrawmetatable(game)
local mtReadonly = true
if type(isreadonly) == "function" then
	local ok, value = pcall(isreadonly, mt)
	if ok then
		mtReadonly = value
	end
end

local indexOld = nil
local indexHook = nil

local function writeMetatable(fn)
	if not mt then return false end
	local ok = pcall(function()
		setreadonly(mt, false)
		fn()
		setreadonly(mt, mtReadonly)
	end)
	if not ok then
		pcall(function() setreadonly(mt, mtReadonly) end)
	end
	return ok
end

local function installIndex()
	if not mt or indexHook then return indexHook ~= nil end
	indexOld = mt.__index
	if not indexOld then return false end
	indexHook = newcclosure(function(self, key)
		local value = indexOld(self, key)
		if dead or checkcaller() or type(key) ~= "string" then
			return value
		end
		local target = indexTarget
		if self == target then
			if key == "WalkSpeed" then
				indexReads = indexReads + 1
				if CFG.index then
					return math.min(value, CFG.spoofWalk)
				end
			elseif key == "JumpPower" then
				indexReads = indexReads + 1
				if CFG.index then
					return math.min(value, CFG.spoofJumpPower)
				end
			elseif key == "JumpHeight" then
				indexReads = indexReads + 1
				if CFG.index then
					return math.min(value, CFG.spoofJumpHeight)
				end
			end
		elseif self == Workspace and key == "Gravity" and CFG.lowGravity then
			indexReads = indexReads + 1
			if CFG.index then
				return math.max(value, CFG.spoofGravity or value)
			end
		end
		return value
	end, "taf_ac_index")
	local ok = writeMetatable(function()
		mt.__index = indexHook
	end)
	if not ok then
		indexHook = nil
		indexOld = nil
	end
	return ok
end

local function removeIndex()
	if not mt or not indexHook then return end
	writeMetatable(function()
		if mt.__index == indexHook then
			mt.__index = indexOld
		end
	end)
	indexHook = nil
	indexOld = nil
end

--// layer 3: namecall hook / remote block ---------------------------------------

local namecallOld = nil
local namecallHook = nil

local function previewArgs(...)
	local count = select("#", ...)
	local parts = {}
	for i = 1, math.min(count, 4) do
		local value = select(i, ...)
		local ok, text = pcall(function()
			if typeof(value) == "Instance" then
				return value:GetFullName()
			end
			return tostring(value)
		end)
		text = ok and text or "?"
		if #text > 40 then
			text = string.sub(text, 1, 37) .. "..."
		end
		table.insert(parts, text)
	end
	return table.concat(parts, ", ")
end

local function handleReport(...)
	reportsSeen = reportsSeen + 1
	pushEvent("REPORT  " .. previewArgs(...), true)
	if CFG.block then
		reportsBlocked = reportsBlocked + 1
		return true
	end
	if not (CFG.closure or CFG.admin or CFG.inflate) then
		defensePending = true
	end
	return false
end

local function installNamecall()
	if not mt or namecallHook then return namecallHook ~= nil end
	namecallOld = mt.__namecall
	if not namecallOld then return false end
	namecallHook = newcclosure(function(self, ...)
		if not dead and not checkcaller() then
			local ok, method = pcall(getnamecallmethod)
			if ok and (method == "FireServer" or method == "InvokeServer") then
				local isGuard = self == acRemote
				if not isGuard and typeof(self) == "Instance" and self.Name == "AntiCheatGuard" then
					isGuard = self:IsA("BaseRemoteEvent")
				end
				if isGuard then
					if handleReport(...) then
						return nil
					end
				end
			end
		end
		return namecallOld(self, ...)
	end, "taf_ac_namecall")
	local ok = writeMetatable(function()
		mt.__namecall = namecallHook
	end)
	if not ok then
		namecallHook = nil
		namecallOld = nil
	end
	return ok
end

local function removeNamecall()
	if not mt or not namecallHook then return end
	writeMetatable(function()
		if mt.__namecall == namecallHook then
			mt.__namecall = namecallOld
		end
	end)
	namecallHook = nil
	namecallOld = nil
end

--// attribute fallbacks ---------------------------------------------------------

local function applyAdmin(on)
	if on then
		if not saved.admin then
			saved.admin = true
			saved.adminValue = LP:GetAttribute("ACAdmin")
		end
		LP:SetAttribute("ACAdmin", true)
	else
		if saved.admin then
			LP:SetAttribute("ACAdmin", saved.adminValue)
			saved.admin = false
			saved.adminValue = nil
		else
			LP:SetAttribute("ACAdmin", nil)
		end
	end
end

local function applyInflate(on)
	local humanoid = currentHumanoid()
	if on then
		if humanoid then
			if not saved.attrs then
				-- snapshot once: workspace attributes are already inflated on a respawn
				saved.attrs = {
					walk = humanoid:GetAttribute("ACWalk"),
					jumpPower = humanoid:GetAttribute("ACJumpPower"),
					jumpHeight = humanoid:GetAttribute("ACJumpHeight"),
					cap = Workspace:GetAttribute("ACWalkCap"),
					gravity = Workspace:GetAttribute("ACGravity"),
				}
				saved.humanoid = humanoid
			elseif saved.humanoid ~= humanoid then
				-- new character: re-snapshot only the humanoid's own values
				saved.humanoid = humanoid
				saved.attrs.walk = humanoid:GetAttribute("ACWalk")
				saved.attrs.jumpPower = humanoid:GetAttribute("ACJumpPower")
				saved.attrs.jumpHeight = humanoid:GetAttribute("ACJumpHeight")
			end
			humanoid:SetAttribute("ACWalk", 999)
			humanoid:SetAttribute("ACJumpPower", 999)
			humanoid:SetAttribute("ACJumpHeight", 999)
		end
		Workspace:SetAttribute("ACWalkCap", 999)
		if CFG.lowGravity then
			Workspace:SetAttribute("ACGravity", Workspace.Gravity)
		end
	else
		local original = saved.attrs
		if original then
			local target = saved.humanoid or humanoid
			if target then
				target:SetAttribute("ACWalk", original.walk)
				target:SetAttribute("ACJumpPower", original.jumpPower)
				target:SetAttribute("ACJumpHeight", original.jumpHeight)
			end
			Workspace:SetAttribute("ACWalkCap", original.cap)
			Workspace:SetAttribute("ACGravity", original.gravity)
			saved.attrs = nil
			saved.humanoid = nil
		end
	end
end

local function applyJump(on)
	local humanoid = currentHumanoid()
	if not humanoid then return end
	if on then
		if not saved.jump or saved.jumpHumanoid ~= humanoid then
			saved.jump = {
				use = humanoid.UseJumpPower,
				power = humanoid.JumpPower,
				height = humanoid.JumpHeight,
			}
			saved.jumpHumanoid = humanoid
		end
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = CFG.jumpHeight
	else
		local original = saved.jump
		if original then
			local target = saved.jumpHumanoid or humanoid
			target.UseJumpPower = original.use
			target.JumpPower = original.power
			target.JumpHeight = original.height
			saved.jump = nil
			saved.jumpHumanoid = nil
		end
	end
end

local function applyGravity(on)
	if on then
		if not saved.gravity then
			saved.gravity = Workspace.Gravity
			CFG.spoofGravity = saved.gravity
		end
		Workspace.Gravity = CFG.gravity
		if CFG.inflate then
			Workspace:SetAttribute("ACGravity", CFG.gravity)
		end
	else
		if saved.gravity then
			Workspace.Gravity = saved.gravity
			if CFG.inflate then
				Workspace:SetAttribute("ACGravity", saved.gravity)
			end
			saved.gravity = nil
		end
	end
end

--// animation guards ------------------------------------------------------------

local whitelistHook = nil
local trackGuardHook = nil

local function installAnim()
	if whitelistHooked then return true end
	local ok, module = pcall(function()
		return require(ReplicatedStorage.Shared.AnimWhitelist)
	end)
	if not (ok and type(module) == "table" and type(module.allowed) == "function") then
		return false
	end
	whitelist = module
	whitelistAllowedOriginal = module.allowed
	whitelistHook = function(...)
		animAllowedCalls = animAllowedCalls + 1
		if dead then
			return whitelistAllowedOriginal(...)
		end
		return true
	end
	module.allowed = whitelistHook
	whitelistHooked = true
	pushEvent("AnimGuard whitelist detached", true)
	return true
end

local function removeAnim()
	if not whitelistHooked or not whitelist then return end
	pcall(function()
		if whitelist.allowed == whitelistHook then
			whitelist.allowed = whitelistAllowedOriginal
		end
	end)
	whitelistHooked = false
	whitelistAllowedOriginal = nil
	whitelistHook = nil
end

local function installTrackGuard()
	if trackGuardHooked then return true end
	local ok, module = pcall(function()
		return require(ReplicatedStorage.TAF_Shared.Client.AnimTrackGuard)
	end)
	if not (ok and type(module) == "table" and type(module.Prune) == "function") then
		return false
	end
	trackGuard = module
	trackGuardPruneOriginal = module.Prune
	trackGuardHook = function()
		animTrackBlocks = animTrackBlocks + 1
		return 0
	end
	module.Prune = trackGuardHook
	trackGuardHooked = true
	return true
end

local function removeTrackGuard()
	if not trackGuardHooked or not trackGuard then return end
	pcall(function()
		if trackGuard.Prune == trackGuardHook then
			trackGuard.Prune = trackGuardPruneOriginal
		end
	end)
	trackGuardHooked = false
	trackGuardPruneOriginal = nil
	trackGuardHook = nil
end

--// direct walk speed -----------------------------------------------------------

local function applyWalkSpeed(on)
	local humanoid = currentHumanoid()
	if on then
		if humanoid and saved.walkHumanoid ~= humanoid then
			saved.walkHumanoid = humanoid
			saved.walkSpeed = humanoid.WalkSpeed
		end
		if not walkSpeedBound then
			RunService:BindToRenderStep("SlimTafWalkSpeed", Enum.RenderPriority.Camera.Value + 3, function()
				if dead or not CFG.walkSpeed then return end
				local hum = currentHumanoid()
				if not hum then return end
				if saved.walkHumanoid ~= hum then
					saved.walkHumanoid = hum
					saved.walkSpeed = hum.WalkSpeed
				end
				hum.WalkSpeed = CFG.walkSpeedValue
			end)
			walkSpeedBound = true
		end
	else
		if walkSpeedBound then
			pcall(function() RunService:UnbindFromRenderStep("SlimTafWalkSpeed") end)
			walkSpeedBound = false
		end
		local target = saved.walkHumanoid or humanoid
		if target and saved.walkSpeed then
			target.WalkSpeed = saved.walkSpeed
		end
		saved.walkHumanoid = nil
		saved.walkSpeed = nil
	end
end

--// layer 4: root step ----------------------------------------------------------

local function stepTick(dt)
	local humanoid = currentHumanoid()
	local character = LP.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) then return end
	if humanoid.SeatPart then return end
	if CFG.groundOnly and humanoid.FloorMaterial == Enum.Material.Air then return end
	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.05 then return end
	root.CFrame = root.CFrame + direction.Unit * (CFG.stepExtra * math.min(dt, 0.1))
end

--// jump ------------------------------------------------------------------------

local jumpConn = UserInputService.JumpRequest:Connect(function()
	if dead or not CFG.infJump then return end
	local humanoid = currentHumanoid()
	if humanoid and humanoid.Health > 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end)

--// panic / shutdown ------------------------------------------------------------

local function restoreEverything()
	applyAdmin(false)
	applyInflate(false)
	applyJump(false)
	applyGravity(false)
end

local function shutdown()
	if dead then return end
	dead = true
	if ui.loopConn then pcall(function() ui.loopConn:Disconnect() end) end
	if ui.keyConn then pcall(function() ui.keyConn:Disconnect() end) end
	if jumpConn then pcall(function() jumpConn:Disconnect() end) end
	applyWalkSpeed(false)
	removeAnim()
	removeTrackGuard()
	removeNamecall()
	removeIndex()
	removeClosure()
	restoreEverything()
	if ui.window then pcall(function() ui.window:Unload() end) end
	_G.TafAcBypass = { cfg = CFG }
	print("[TAF-AC] unloaded")
end

local panic

panic = function()
	if dead then return end
	CFG.closure = false
	CFG.block = false
	CFG.index = false
	CFG.admin = false
	CFG.inflate = false
	CFG.rootStep = false
	CFG.infJump = false
	CFG.customJump = false
	CFG.lowGravity = false
	CFG.anim = false
	CFG.animTracks = false
	CFG.walkSpeed = false
	restoreEverything()
	applyWalkSpeed(false)
	removeAnim()
	removeTrackGuard()
	removeClosure()
	removeIndex()
	removeNamecall()
	if ui.window then
		for _, flag in ipairs({
			"taf_closure", "taf_block", "taf_index", "taf_admin",
			"taf_inflate", "taf_step", "taf_infjump", "taf_jump", "taf_gravity",
			"taf_anim", "taf_animtracks", "taf_walkspeed",
		}) do
			pcall(function() ui.window:Set(flag, false) end)
		end
	end
	pushEvent("PANIC  hooks removed, attributes restored", true)
	print("[TAF-AC] panic")
end

--// UI --------------------------------------------------------------------------

local Rayfield
pcall(function()
	Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)

local function stateText()
	local parts = {
		"closure " .. (closureHooked and "ON" or "off"),
		"block " .. (namecallHook and (CFG.block and "ON" or "watch") or "off"),
		"index " .. (indexHook and (CFG.index and "ON" or "watch") or "off"),
		"admin " .. (CFG.admin and "on" or "off"),
		"inflate " .. (CFG.inflate and "on" or "off"),
	}
	return table.concat(parts, "  |  ")
end

local function coverageText()
	local covered = closureHooked or CFG.admin or CFG.inflate
	if covered then
		return "guard coverage: yes (" .. (closureHooked and "closure" or (CFG.admin and "ACAdmin" or "inflation")) .. ")"
	end
	return "guard coverage: NO - MoveGuard will clamp and report"
end

local function buildUI()
	if not Rayfield then
		warn("[TAF-AC] Rayfield failed to load")
		return
	end

	-- CFG is the source of truth. Rayfield replays its saved flags while the
	-- elements are created, and that can fire callbacks which mutate CFG.
	-- snapshot here, restore after the window is built.
	local desired = {}
	for key, value in pairs(CFG) do
		desired[key] = value
	end

	local window = Rayfield:CreateWindow({
		Name = "TAF // AC BYPASS",
		LoadingTitle = "THROW A FOOTBALL",
		LoadingSubtitle = "MoveGuard  -  five layers",
		KeySystem = false,
	})
	ui.window = window

	pcall(function()
		window:ChangeTheme({
			WindowColor = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(8, 14, 10)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 26, 18)),
			}),
			ShadowColor = Color3.fromRGB(4, 8, 5),
			CornerRoundness = UDim.new(0, 16),
			ElementCornerRadius = UDim.new(0, 10),
			PillCornerRadius = UDim.new(1, 0),
			AccentColor = Color3.fromRGB(120, 230, 140),
		})
	end)

	-- BYPASS
	local bypassTab = window:CreateTab({ Name = "BYPASS" })
	ui.stateText = bypassTab:CreateText({ Name = "layers", Text = stateText() })
	ui.coverText = bypassTab:CreateText({ Name = "coverage", Text = coverageText() })

	bypassTab:CreateToggle({
		Name = "closure hook",
		Description = "detaches MoveGuard._check, the exact closure its 0.25s loop calls. client-side only, nothing replicates.",
		Flag = "taf_closure",
		Value = CFG.closure,
		Callback = function(v)
			CFG.closure = v
			if v then
				if not installClosure() then
					notify("closure layer unavailable - guard table not found")
				end
			else
				removeClosure()
			end
		end,
	})
	bypassTab:CreateToggle({
		Name = "block AntiCheatGuard",
		Description = "namecall hook drops the report remote. reports still show in LOG, just never leave.",
		Flag = "taf_block",
		Value = CFG.block,
		Callback = function(v)
			CFG.block = v
			if v then
				installNamecall()
			end
		end,
	})
	bypassTab:CreateToggle({
		Name = "index spoof",
		Description = "caps WalkSpeed, JumpPower, JumpHeight and Gravity reads made by game code at the legitimate values.",
		Flag = "taf_index",
		Value = CFG.index,
		Callback = function(v)
			CFG.index = v
			if v then
				installIndex()
			end
		end,
	})

	bypassTab:CreateSection({ Name = "ANIMATION GUARDS" })
	bypassTab:CreateToggle({
		Name = "AnimGuard whitelist",
		Description = "AnimWhitelist.allowed answers true, so the client stops policing other players' animation tracks. table field only.",
		Flag = "taf_anim",
		Value = CFG.anim,
		Callback = function(v)
			CFG.anim = v
			if v then
				if not installAnim() then
					notify("AnimWhitelist not found - animation layer unavailable")
				end
			else
				removeAnim()
			end
		end,
	})
	bypassTab:CreateToggle({
		Name = "animation track cap",
		Description = "stubs AnimTrackGuard.Prune, the 16-track limiter. visual only, no report channel.",
		Flag = "taf_animtracks",
		Value = CFG.animTracks,
		Callback = function(v)
			CFG.animTracks = v
			if v then
				if not installTrackGuard() then
					notify("AnimTrackGuard not found - track layer unavailable")
				end
			else
				removeTrackGuard()
			end
		end,
	})

	bypassTab:CreateSection({ Name = "FALLBACKS  (replicated attributes)" })
	bypassTab:CreateText({
		Name = "fallback note",
		Text = "these write attributes the server can see. only needed if the closure or namecall layers fail.",
	})
	bypassTab:CreateToggle({
		Name = "ACAdmin attribute",
		Description = "MoveGuard returns before checking anything. replicated - the server can read it.",
		Flag = "taf_admin",
		Value = CFG.admin,
		Callback = function(v)
			CFG.admin = v
			applyAdmin(v)
		end,
	})
	bypassTab:CreateToggle({
		Name = "attribute inflation",
		Description = "forces ACWalk, ACWalkCap and the jump limits high so the guard sees nothing. replicated.",
		Flag = "taf_inflate",
		Value = CFG.inflate,
		Callback = function(v)
			CFG.inflate = v
			applyInflate(v)
		end,
	})

	bypassTab:CreateSection({ Name = "TOOLS" })
	bypassTab:CreateButton({
		Name = "arm all client-side layers",
		Description = "closure + block + index + AnimGuard. no replicated attributes touched.",
		Callback = function()
			CFG.closure = true
			CFG.block = true
			CFG.index = true
			CFG.anim = true
			installClosure()
			installNamecall()
			installIndex()
			installAnim()
			for _, flag in ipairs({ "taf_closure", "taf_block", "taf_index", "taf_anim" }) do
				pcall(function() window:Set(flag, true) end)
			end
			notify("client-side layers armed: closure + block + index + AnimGuard")
		end,
	})
	bypassTab:CreateButton({
		Name = "probe guard",
		Description = "re-finds MoveGuard and reports which layers are attached.",
		Callback = function()
			refreshAcRemote()
			local source = findGuard()
			notify(string.format(
				"guard %s | closure %s | remote %s | block %s",
				tostring(source),
				closureHooked and "attached" or "detached",
				acRemote and "found" or "missing",
				namecallHook and "hooked" or "none"
			))
		end,
	})

	-- MOVEMENT
	local moveTab = window:CreateTab({ Name = "MOVEMENT" })
	moveTab:CreateSection({ Name = "SPEED" })
	moveTab:CreateText({
		Name = "speed note",
		Text = "DriveExtras rewrites Humanoid.WalkSpeed to 18 every frame. root step moves the root part instead and leaves WalkSpeed at 18.",
	})
	moveTab:CreateToggle({
		Name = "root step",
		Description = "HumanoidRootPart.CFrame movement along your input direction.",
		Flag = "taf_step",
		Value = CFG.rootStep,
		Callback = function(v) CFG.rootStep = v end,
	})
	moveTab:CreateSlider({
		Name = "extra studs per second",
		Range = { 0, 60 },
		Increment = 1,
		Value = CFG.stepExtra,
		Suffix = " studs",
		Flag = "taf_stepextra",
		Callback = function(v) CFG.stepExtra = v end,
	})
	moveTab:CreateToggle({
		Name = "ground only",
		Description = "stop stepping while airborne. keeps movement closer to normal physics.",
		Flag = "taf_groundonly",
		Value = CFG.groundOnly,
		Callback = function(v) CFG.groundOnly = v end,
	})

	moveTab:CreateSection({ Name = "DIRECT SPEED" })
	moveTab:CreateText({
		Name = "direct speed note",
		Text = "writes Humanoid.WalkSpeed on RenderStep, after the controller's own write. needs closure, ACAdmin or inflation or MoveGuard clamps it back.",
	})
	moveTab:CreateToggle({
		Name = "walk speed override",
		Description = "physics movement at the chosen WalkSpeed instead of root stepping.",
		Flag = "taf_walkspeed",
		Value = CFG.walkSpeed,
		Callback = function(v)
			CFG.walkSpeed = v
			applyWalkSpeed(v)
		end,
	})
	moveTab:CreateSlider({
		Name = "walk speed",
		Range = { 18, 150 },
		Increment = 1,
		Value = CFG.walkSpeedValue,
		Suffix = " ws",
		Flag = "taf_walkspeedvalue",
		Callback = function(v) CFG.walkSpeedValue = v end,
	})

	moveTab:CreateSection({ Name = "JUMP" })
	moveTab:CreateToggle({
		Name = "infinite jump",
		Flag = "taf_infjump",
		Value = CFG.infJump,
		Callback = function(v) CFG.infJump = v end,
	})
	moveTab:CreateToggle({
		Name = "custom jump height",
		Description = "writes JumpHeight. needs closure, ACAdmin or inflation to survive the guard.",
		Flag = "taf_jump",
		Value = CFG.customJump,
		Callback = function(v)
			CFG.customJump = v
			applyJump(v)
		end,
	})
	moveTab:CreateSlider({
		Name = "jump height",
		Range = { 7, 60 },
		Increment = 1,
		Value = CFG.jumpHeight,
		Suffix = " studs",
		Flag = "taf_jumpheight",
		Callback = function(v)
			CFG.jumpHeight = v
			if CFG.customJump then
				applyJump(true)
			end
		end,
	})

	moveTab:CreateSection({ Name = "GRAVITY" })
	moveTab:CreateToggle({
		Name = "low gravity",
		Description = "writes Workspace.Gravity. needs closure, ACAdmin or inflation to survive the guard.",
		Flag = "taf_gravity",
		Value = CFG.lowGravity,
		Callback = function(v)
			CFG.lowGravity = v
			applyGravity(v)
		end,
	})
	moveTab:CreateSlider({
		Name = "workspace gravity",
		Range = { 20, 300 },
		Increment = 10,
		Value = CFG.gravity,
		Suffix = " g",
		Flag = "taf_gravityvalue",
		Callback = function(v)
			CFG.gravity = v
			if CFG.lowGravity then
				applyGravity(true)
			end
		end,
	})

	-- LOG
	local logTab = window:CreateTab({ Name = "LOG" })
	ui.reportText = logTab:CreateText({ Name = "counters", Text = "reports 0  |  blocked 0" })
	ui.logText = logTab:CreateText({ Name = "events", Text = "-" })
	logTab:CreateButton({
		Name = "clear log",
		Callback = function()
			events = {}
			logDirty = true
		end,
	})
	logTab:CreateButton({
		Name = "panic  (P)",
		Description = "removes every hook and restores ACAdmin, attributes, jump and gravity.",
		Callback = function() panic() end,
	})
	logTab:CreateButton({
		Name = "unload",
		Callback = function() shutdown() end,
	})
	logTab:CreateText({
		Name = "honesty",
		Text = "a server-side kick cannot be cancelled by any client hook. these layers stop client reports and client reads.",
	})
	logTab:CreateText({
		Name = "keys",
		Text = "P = panic   |   re-running replaces this panel",
	})

	-- Rayfield restores its own stale flag values on a new window; push cfg back.
	for key, value in pairs(desired) do
		CFG[key] = value
	end
	local sync = {
		taf_closure = CFG.closure,
		taf_block = CFG.block,
		taf_index = CFG.index,
		taf_admin = CFG.admin,
		taf_inflate = CFG.inflate,
		taf_step = CFG.rootStep,
		taf_stepextra = CFG.stepExtra,
		taf_groundonly = CFG.groundOnly,
		taf_infjump = CFG.infJump,
		taf_jump = CFG.customJump,
		taf_jumpheight = CFG.jumpHeight,
		taf_gravity = CFG.lowGravity,
		taf_gravityvalue = CFG.gravity,
		taf_anim = CFG.anim,
		taf_animtracks = CFG.animTracks,
		taf_walkspeed = CFG.walkSpeed,
		taf_walkspeedvalue = CFG.walkSpeedValue,
	}
	for flag, value in pairs(sync) do
		pcall(function() window:Set(flag, value) end)
	end
	-- the stale callbacks may have applied side effects; normalise them to CFG
	if CFG.admin then applyAdmin(true) else applyAdmin(false) end
	if CFG.inflate then applyInflate(true) else applyInflate(false) end
	if CFG.customJump then applyJump(true) else applyJump(false) end
	if CFG.lowGravity then applyGravity(true) else applyGravity(false) end
	if CFG.walkSpeed then applyWalkSpeed(true) else applyWalkSpeed(false) end
	if CFG.anim then installAnim() else removeAnim() end
	if CFG.animTracks then installTrackGuard() else removeTrackGuard() end
	if CFG.closure then installClosure() else removeClosure() end
	if CFG.index then installIndex() else removeIndex() end
end

--// loop ------------------------------------------------------------------------

local lastApply = 0
local lastSync = 0
local lastSave = 0
local lastGuardCheck = 0
local lastRemoteCheck = 0

local function tick(dt)
	if dead then return end
	local now = os.clock()

	if now - lastRemoteCheck > 3 then
		lastRemoteCheck = now
		refreshAcRemote()
	end

	indexTarget = currentHumanoid()

	if now - lastGuardCheck > 2 then
		lastGuardCheck = now
		if CFG.closure and not closureHooked then installClosure() end
		if CFG.anim and not whitelistHooked then installAnim() end
		if CFG.animTracks and not trackGuardHooked then installTrackGuard() end
		if CFG.walkSpeed and not walkSpeedBound then applyWalkSpeed(true) end
	end

	if now - lastApply > 0.5 then
		lastApply = now
		if CFG.admin then
			LP:SetAttribute("ACAdmin", true)
		end
		if CFG.inflate then
			applyInflate(true)
		end
		if CFG.customJump then
			local humanoid = currentHumanoid()
			if humanoid then
				humanoid.UseJumpPower = false
				humanoid.JumpHeight = CFG.jumpHeight
			end
		end
		if CFG.lowGravity then
			Workspace.Gravity = CFG.gravity
			if CFG.inflate then
				Workspace:SetAttribute("ACGravity", CFG.gravity)
			end
		end
	end

	if defensePending then
		defensePending = false
		CFG.admin = true
		CFG.inflate = true
		applyAdmin(true)
		applyInflate(true)
		if ui.window then
			pcall(function() ui.window:Set("taf_admin", true) end)
			pcall(function() ui.window:Set("taf_inflate", true) end)
		end
		notify("a report escaped - ACAdmin + inflation armed as cover")
	end

	if CFG.rootStep then
		pcall(stepTick, dt)
	end

	if now - lastSync > 0.4 then
		lastSync = now
		if ui.stateText then
			pcall(function() ui.stateText:Set(stateText()) end)
		end
		if ui.coverText then
			pcall(function() ui.coverText:Set(coverageText()) end)
		end
		if ui.reportText then
			pcall(function()
				ui.reportText:Set(string.format(
					"reports %d  |  blocked %d\nclosure %d  |  index %d  |  anim whitelist %d  |  track prunes %d",
					reportsSeen, reportsBlocked, closureHits, indexReads, animAllowedCalls, animTrackBlocks
				))
			end)
		end
		if logDirty then
			logDirty = false
			if ui.logText then
				local text = #events > 0 and table.concat(events, "\n") or "-"
				pcall(function() ui.logText:Set(text) end)
			end
		end
	end

	if now - lastSave > 4 then
		lastSave = now
		pcall(saveCfg)
	end
end

--// start -----------------------------------------------------------------------

refreshAcRemote()
findGuard()
indexTarget = currentHumanoid()

if CFG.closure then installClosure() end
-- always install: even with blocking off it is the report watcher
installNamecall()
if CFG.index then installIndex() end
if CFG.anim then installAnim() end
if CFG.animTracks then installTrackGuard() end
if CFG.walkSpeed then applyWalkSpeed(true) end
if CFG.admin then applyAdmin(true) end
if CFG.inflate then applyInflate(true) end
if CFG.customJump then applyJump(true) end
if CFG.lowGravity then applyGravity(true) end

buildUI()

if ui.window then
	ui.keyConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.P then
			panic()
		end
	end)
end

ui.loopConn = RunService.Heartbeat:Connect(function(dt)
	local ok, err = pcall(tick, dt)
	if not ok then
		warn("[TAF-AC] tick error: " .. tostring(err))
	end
end)

_G.TafAcBypass = {
	cfg = CFG,
	window = ui.window,
	stop = shutdown,
	panic = panic,
	state = function()
		return string.format(
			"closure=%s(%d) block=%s index=%s(%d) anim=%s(%d) tracks=%s admin=%s inflate=%s speed=%s reports=%d blocked=%d guard=%s",
			tostring(closureHooked), closureHits, tostring(namecallHook ~= nil), tostring(indexHook ~= nil),
			indexReads, tostring(whitelistHooked), animAllowedCalls, tostring(trackGuardHooked),
			tostring(CFG.admin), tostring(CFG.inflate), tostring(walkSpeedBound),
			reportsSeen, reportsBlocked, tostring(guardSource)
		)
	end,
	probe = function()
		refreshAcRemote()
		local source = findGuard()
		local humanoid = currentHumanoid()
		return {
			guardSource = source,
			closureHooked = closureHooked,
			closureHits = closureHits,
			namecall = namecallHook ~= nil,
			index = indexHook ~= nil,
			indexReads = indexReads,
			anim = whitelistHooked,
			animCalls = animAllowedCalls,
			animTracks = trackGuardHooked,
			trackBlocks = animTrackBlocks,
			walkSpeed = walkSpeedBound,
			remote = acRemote ~= nil,
			admin = LP:GetAttribute("ACAdmin"),
			acWalk = humanoid and humanoid:GetAttribute("ACWalk"),
			cap = Workspace:GetAttribute("ACWalkCap"),
			gravityAttr = Workspace:GetAttribute("ACGravity"),
			gravity = Workspace.Gravity,
			reportsSeen = reportsSeen,
			reportsBlocked = reportsBlocked,
		}
	end,
	testReport = function(...)
		local before = reportsSeen
		local swallowed = handleReport(...)
		return swallowed, reportsSeen > before
	end,
	armAll = function()
		CFG.closure = true
		CFG.block = true
		CFG.index = true
		CFG.anim = true
		installClosure()
		installNamecall()
		installIndex()
		installAnim()
	end,
}

_G.SlimTafBypass = _G.TafAcBypass

pushEvent("panel loaded", true)
pcall(saveCfg)

print("[TAF-AC] loaded - closure, index, namecall, root step")
end

--// embedded suite: physbox  (from physbox.luau) =========================
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
		-- full-power spammer: a charged straight is the one punch guard
		-- can't save you from - read their charge off the action and slip
		-- those too, old-school: whole animation, no cooldown, no gates
		local charged = (opp.action.chargeNow or 0) >= 0.5
		if wantDodge and (me.guardBroken or heavy or charged) then
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
	fight:CreateToggle({ name = "auto-dodge", description = "slip + step out of the strike lane when their punch starts - ducks hooks, backs off kicks, slips full-power charged punches, always on when guard broken", flag = "dodge", value = CFG.dodge, callback = function(v) CFG.dodge = v end })
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

--// embedded suite: tps  (from tps.luau) =========================
Hub.SUITE.tps = function()
-- TPS: Street Soccer | STREET - auto shot, auto tackle, auto GK save, auto pass, powers, ball ESP
-- places 335760407 + 75703135112691 | Rayfield Gen2 | replace-not-stack via _G.TpsStreetPanel
-- rides only official paths: fires the game's own FE remotes (Kick / Tackle / Save / AutoPass /
-- Powers / Settings) with the exact argument patterns its Backpack.Module client sends.
-- never touches Net.Claim, never fires server->client events (WinR/WinB, GKEvent*, BombA...).

local prev = _G.TpsStreetPanel
local CFG = (prev and prev.cfg) or {}
-- defaults merge: keeps saved settings across reloads, fills in fields added later
for k, v in pairs({
	autoShot = true,
	shotRange = 7,
	forcePower = false,
	autoTackle = false,
	tackleRange = 11,
	autoGK = false,
	gkRange = 12,
	autoPass = false,
	passRange = 60,
	ballESP = true,
	goalBeacons = true,
	cooldown = 0.9,
}) do
	if CFG[k] == nil then
		CFG[k] = v
	end
end
if prev and prev.stop then
	pcall(prev.stop)
end
_G.TpsStreetPanel = { cfg = CFG }

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LP = Players.LocalPlayer

-- the card-name literal the game's own client hardcodes into every kick/tackle/save/pass remote
local CARD = "Rock'n'roll Star"

--// locators -------------------------------------------------------------------

-- ball scan mirrors the game's own (Backpack.Module v1.SpecialKick + PlayerScripts.Col):
-- parts named TPS / PSoccerBall under Workspace.Practice, Workspace.TPSSystem or Workspace itself.
-- nearest one to us wins.
local function findBall()
	local best, bestD = nil, math.huge
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local function consider(c)
		if c:IsA("BasePart") and (c.Name == "TPS" or c.Name == "PSoccerBall") then
			local d = hrp and (c.Position - hrp.Position).Magnitude or 0
			if d < bestD then
				best, bestD = c, d
			end
		end
	end
	for _, rootName in ipairs({ "Practice", "TPSSystem" }) do
		local root = Workspace:FindFirstChild(rootName)
		if root then
			for _, c in ipairs(root:GetChildren()) do
				consider(c)
			end
		end
	end
	if not best then
		for _, c in ipairs(Workspace:GetChildren()) do
			consider(c)
		end
	end
	return best, bestD
end

local function goalCenter(model)
	if not model then
		return nil
	end
	if model:IsA("BasePart") then
		return model.Position
	end
	if model:IsA("Model") then
		local ok, cf = pcall(function()
			return model:GetBoundingBox()
		end)
		if ok and cf then
			return cf.Position
		end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				return d.Position
			end
		end
	end
	return nil
end

-- which net we attack: blue team scores on RedGoal, red team on BlueGoal
local function attackGoal()
	local tc = LP.TeamColor
	if tc == BrickColor.new("Bright blue") then
		return Workspace:FindFirstChild("RedGoal")
	elseif tc == BrickColor.new("Bright red") then
		return Workspace:FindFirstChild("BlueGoal")
	end
	return nil
end

local function amKeeper()
	local pg = LP:FindFirstChild("PlayerGui")
	if not pg then
		return false
	end
	local r, b = pg:FindFirstChild("RedGK"), pg:FindFirstChild("BlueGK")
	return (r and r.Value == true) or (b and b.Value == true)
end

local function activated()
	local pg = LP:FindFirstChild("PlayerGui")
	local av = pg and pg:FindFirstChild("Activate")
	return av == nil or av.Value ~= false
end

local function nearestTeammate()
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil, nil
	end
	local best, bestD, bestName = nil, math.huge, nil
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP and p.TeamColor == LP.TeamColor then
			local phrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if phrp then
				local d = (phrp.Position - hrp.Position).Magnitude
				if d < bestD then
					best, bestD, bestName = p, d, p.Name
				end
			end
		end
	end
	return bestName, bestD
end

-- nearest OTHER player's character to a point (opponents and teammates both count,
-- like a real challenger for the ball)
local function nearestOtherTo(pos)
	local best, bestD = nil, math.huge
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP then
			local phrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if phrp then
				local d = (phrp.Position - pos).Magnitude
				if d < bestD then
					best, bestD = p, d
				end
			end
		end
	end
	return best, bestD
end

--// official-path remote wrappers ----------------------------------------------
-- every call below is a line-for-line copy of what the game's own Backpack.Module /
-- PowersModule clients fire, same args in the same order. gates mirror theirs too.

local function ballValid(ball)
	-- Kick2Hit / TackleHit / SaveHit part checks
	return ball ~= nil
		and ball.Locked ~= true
		and ball.Anchored ~= true
		and ball.Parent ~= nil
		and not ball.Parent:IsA("Accessory")
		and ball.Parent:FindFirstChild("Humanoid") == nil
end

local function remotePaths()
	local FE = Workspace:FindFirstChild("FE")
	local sys = FE and FE:FindFirstChild("System")
	local kickFolder = FE and FE:FindFirstChild("Kick")
	local powers = FE and FE:FindFirstChild("Powers")
	local bp = LP:FindFirstChild("Backpack")
	if not (sys and kickFolder and powers and bp) then
		return nil
	end
	return {
		sys = sys,
		kickFolder = kickFolder,
		powers = powers,
		bp = bp,
		altName = sys:FindFirstChild("ALTNameA"),
		kick = sys:FindFirstChild("Kick"),
		tackle = sys:FindFirstChild("Tackle"),
		save = sys:FindFirstChild("Save"),
		autoPass = sys:FindFirstChild("AutoPass"),
		remote = kickFolder:FindFirstChild("RemoteEvent"),
		remote1 = kickFolder:FindFirstChild("RemoteEvent1"),
		remote2 = kickFolder:FindFirstChild("RemoteEvent2"),
	}
end

-- Kick2Hit replica: full charge values + the exact FE.System.Kick argument run
local function fireKick(ball)
	local R = remotePaths()
	if not R or not ballValid(ball) then
		return false
	end
	local bp = R.bp
	if CFG.forcePower and bp:FindFirstChild("PowerActive") and bp.PowerActive.Value ~= true then
		bp.PowerActive.Value = true
	end
	-- the game's own charge tops out here (Backpack.Module v1.Kick: i = 70)
	bp.Speed.Value = 70
	bp.Angle.Value = Vector3.new(4000000, 70 * 35 / 2, 4000000)
	local Value_2 = bp.Speed.Value
	local Value_3 = bp.Angle.Value
	local Value_4 = bp.PowerActive.Value
	local Value_5 = bp.Ground.Value
	local Value_6 = bp.Curving.Value
	R.remote:FireServer(ball)
	R.kick:FireServer(LP.UserId, ball, Value_2, Value_3, Value_4, Value_5, Value_6, CARD, R.altName.Value, "power=95/100")
	if bp.PowerActive.Value == true then
		if ball.Name ~= "Bomb" then
			bp.PowerActive.Value = false
			local pg = LP:FindFirstChild("PlayerGui")
			local start = pg and pg:FindFirstChild("Start")
			local pw = start and start:FindFirstChild("PowerShot")
			local timer = pw and pw:FindFirstChild("Timer")
			if timer then
				timer.Disabled = false
			end
		end
		local fv = bp:FindFirstChild("FValue")
		if R.remote1 and fv then
			R.remote1:FireServer(ball, fv.Value)
		end
	end
	return true
end

-- TackleHit replica
local function fireTackle(ball)
	local R = remotePaths()
	if not R or not ballValid(ball) then
		return false
	end
	R.remote:FireServer(ball)
	R.tackle:FireServer(LP.UserId, ball, CARD, R.altName.Value, "power=95/100")
	return true
end

-- SaveHit replica (keeper catch)
local function fireSave(ball)
	local R = remotePaths()
	if not R or not ballValid(ball) then
		return false
	end
	R.remote2:FireServer(ball)
	R.save:FireServer(LP.UserId, ball, CARD, R.altName.Value, "power=95/100")
	return true
end

-- PassHit replica: target name + my-HRP-to-their-HRP distance, exactly as the game computes it
local function firePass(ball, targetName)
	local R = remotePaths()
	if not R or not ballValid(ball) or not targetName then
		return false
	end
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local target = Players:FindFirstChild(targetName)
	local thrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not (hrp and thrp) then
		return false
	end
	local dist = (hrp.Position - thrp.Position).Magnitude
	R.remote:FireServer(ball)
	R.autoPass:FireServer(LP.UserId, ball, targetName, dist, R.bp.Ground.Value, CARD, R.altName.Value, "power=95/100")
	return true
end

-- PowersModule replica: power id + the game's own count gate
local POWER_IDS = { bomb = 1, wall = 2, spike = 3, burn = 4, supercurve = 5 }
local function firePower(id)
	local R = remotePaths()
	if not R then
		return false
	end
	local data = ReplicatedStorage:FindFirstChild("Data")
	local mine = data and data:FindFirstChild(LP.Name)
	local count = mine and mine:FindFirstChild(id)
	if count and count.Value < 1 then
		return false, "no " .. id .. "s left"
	end
	R.powers.Power:FireServer(POWER_IDS[id])
	return true
end

--// visuals --------------------------------------------------------------------

local espHL, espBall
local beaconR, beaconB
local distStat

local function clearESP()
	if espHL then
		pcall(function() espHL:Destroy() end)
	end
	espHL, espBall = nil, nil
end

local function clearBeacons()
	if beaconR then
		pcall(function() beaconR:Destroy() end)
	end
	if beaconB then
		pcall(function() beaconB:Destroy() end)
	end
	beaconR, beaconB = nil, nil
end

local function makeBeacon(name, color)
	local h = Instance.new("Highlight")
	h.Name = name
	h.FillColor = color
	h.FillTransparency = 0.6
	h.OutlineColor = color
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	return h
end

local function updateVisuals(ball)
	if CFG.ballESP and ball then
		if ball ~= espBall or not espHL or not espHL.Parent then
			clearESP()
			espHL = Instance.new("Highlight")
			espHL.Name = "TpsStreetBallESP"
			espHL.FillColor = Color3.fromRGB(255, 170, 0)
			espHL.FillTransparency = 0.35
			espHL.OutlineColor = Color3.fromRGB(255, 255, 255)
			espHL.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			espHL.Adornee = ball
			espHL.Parent = Workspace
			espBall = ball
		end
	elseif espHL then
		clearESP()
	end

	if CFG.goalBeacons then
		if not beaconR or not beaconR.Parent then
			beaconR = makeBeacon("TpsStreetBeaconR", Color3.fromRGB(255, 60, 60))
			beaconR.Parent = Workspace
		end
		if not beaconB or not beaconB.Parent then
			beaconB = makeBeacon("TpsStreetBeaconB", Color3.fromRGB(60, 120, 255))
			beaconB.Parent = Workspace
		end
		local r, b = Workspace:FindFirstChild("RedGoal"), Workspace:FindFirstChild("BlueGoal")
		if beaconR.Adornee ~= r then
			beaconR.Adornee = r
		end
		if beaconB.Adornee ~= b then
			beaconB.Adornee = b
		end
	else
		clearBeacons()
	end
end

--// main loop ------------------------------------------------------------------

local dead = false
local lastAct = { kick = 0, tackle = 0, save = 0, pass = 0 }
local lastAny = 0
local lastErrAt = 0
local loopConn
local keyConn

local function aimAtGoal()
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local gp = goalCenter(attackGoal())
	if not gp then
		return
	end
	local flat = Vector3.new(gp.X - hrp.Position.X, 0, gp.Z - hrp.Position.Z)
	if flat.Magnitude > 1 then
		hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat.Unit)
	end
end

local function step()
	if dead then
		return
	end
	local now = os.clock()
	local ball, ballDist = findBall()
	updateVisuals(ball)
	if distStat then
		pcall(function() distStat:Set(math.floor(ballDist or 0)) end)
	end
	if not ball or not activated() then
		return
	end
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not char:FindFirstChild("Humanoid") or char.Humanoid.Health == 0 then
		return
	end
	local keeper = amKeeper()

	-- keeper: auto save when the ball closes in (SaveHit's own keeper gate)
	if CFG.autoGK and keeper and ballDist <= CFG.gkRange then
		if now - lastAct.save >= CFG.cooldown and now - lastAny >= 0.3 then
			if fireSave(ball) then
				lastAct.save, lastAny = now, now
			end
		end
		return
	end

	-- field player: shot > tackle > pass, one action at a time
	if CFG.autoShot and not keeper and ballDist <= CFG.shotRange then
		if now - lastAct.kick >= CFG.cooldown and now - lastAny >= 0.3 then
			aimAtGoal()
			if fireKick(ball) then
				lastAct.kick, lastAny = now, now
			end
		end
		return
	end

	if CFG.autoTackle and not keeper and ballDist <= CFG.tackleRange then
		local other, otherD = nearestOtherTo(ball.Position)
		-- steal it off whoever is closer to it than we are
		if other and otherD < ballDist and now - lastAct.tackle >= CFG.cooldown + 0.3 and now - lastAny >= 0.3 then
			if fireTackle(ball) then
				lastAct.tackle, lastAny = now, now
			end
		end
		return
	end

	if CFG.autoPass and not keeper and ballDist <= CFG.shotRange then
		local name, d = nearestTeammate()
		if name and d and d <= CFG.passRange and d > 5 then
			if now - lastAct.pass >= CFG.cooldown and now - lastAny >= 0.3 then
				if firePass(ball, name) then
					lastAct.pass, lastAny = now, now
				end
			end
		end
	end
end

loopConn = RunService.Heartbeat:Connect(function()
	local ok, err = pcall(step)
	if not ok and os.clock() - lastErrAt > 5 then
		lastErrAt = os.clock()
		warn("[Street] loop error: " .. tostring(err))
	end
end)

--// lifecycle ------------------------------------------------------------------

local FLAGS = { "autoshot", "forcethepower", "autotackle", "autogk", "autopass", "ballesp", "goalbeacons" }

local function panic()
	CFG.autoShot = false
	CFG.forcePower = false
	CFG.autoTackle = false
	CFG.autoGK = false
	CFG.autoPass = false
	CFG.ballESP = false
	CFG.goalBeacons = false
	clearESP()
	clearBeacons()
	if window then
		for _, f in ipairs(FLAGS) do
			pcall(function() window:Set(f, false) end)
		end
	end
	print("[Street] panic: hands off - everything off")
end

local window

local function shutdown()
	if dead then
		return
	end
	dead = true
	if loopConn then
		loopConn:Disconnect()
		loopConn = nil
	end
	if keyConn then
		keyConn:Disconnect()
		keyConn = nil
	end
	clearESP()
	clearBeacons()
	if window then
		pcall(function() window:Unload() end)
	end
	_G.TpsStreetPanel = nil
	print("[Street] unloaded")
end

keyConn = UserInputService.InputBegan:Connect(function(i, gp)
	if gp then
		return
	end
	if i.KeyCode == Enum.KeyCode.P then
		panic()
	end
end)

--// UI -------------------------------------------------------------------------

local Rayfield
pcall(function() Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))() end)

local function buildUI()
	if not Rayfield then
		return
	end
	local w = Rayfield:CreateWindow({
		Name = "TPS STREET SOCCER | STREET",
		LoadingTitle = "STREET",
		LoadingSubtitle = "auto shot, tackle, GK, ball ESP",
		KeySystem = false,
	})
	window = w
	local play = w:CreateTab({ name = "PLAY" })
	local view = w:CreateTab({ name = "VIEW" })
	local sys = w:CreateTab({ name = "SYS" })

	play:CreateToggle({ name = "auto shot", description = "ball in range -> face their net and let it rip at the game's own full charge (Speed 70). keeper? it stays off, exactly like the game's own kick gate", flag = "autoshot", value = CFG.autoShot, callback = function(v) CFG.autoShot = v end })
	play:CreateSlider({ name = "shot range", description = "studs from you to the ball before the auto shot fires - keep it inside a real stride", flag = "shotrange", range = { 3, 15 }, increment = .5, value = CFG.shotRange, suffix = " st", callback = function(v) CFG.shotRange = v end })
	play:CreateToggle({ name = "force power shot", description = "arm the power shot on every kick (sets the game's own PowerActive flag first) - off by default so you burn it only when you want", flag = "forcethepower", value = CFG.forcePower, callback = function(v) CFG.forcePower = v end })
	play:CreateSlider({ name = "action cooldown", description = "seconds between same-type actions, keeps the rhythm human", flag = "cooldown", range = { .3, 3 }, increment = .1, value = CFG.cooldown, suffix = " s", callback = function(v) CFG.cooldown = v end })

	play:CreateSection({ name = "DEFENSE" })
	play:CreateToggle({ name = "auto tackle", description = "an opponent closer to the ball than you inside range -> strip it with the game's own tackle remote", flag = "autotackle", value = CFG.autoTackle, callback = function(v) CFG.autoTackle = v end })
	play:CreateSlider({ name = "tackle range", description = "studs to the ball before tackles trigger", flag = "tacklerange", range = { 4, 20 }, increment = .5, value = CFG.tackleRange, suffix = " st", callback = function(v) CFG.tackleRange = v end })
	play:CreateToggle({ name = "auto GK save", description = "you're in goal and the ball closes in -> keeper catch via the game's own save remote (SaveHit)", flag = "autogk", value = CFG.autoGK, callback = function(v) CFG.autoGK = v end })
	play:CreateSlider({ name = "GK range", description = "studs to the ball before the save fires", flag = "gkrange", range = { 4, 25 }, increment = .5, value = CFG.gkRange, suffix = " st", callback = function(v) CFG.gkRange = v end })
	play:CreateToggle({ name = "auto pass", description = "ball at your feet and a teammate open -> quick pass through the game's own AutoPass remote, target + distance computed the way PassHit does", flag = "autopass", value = CFG.autoPass, callback = function(v) CFG.autoPass = v end })
	play:CreateSlider({ name = "pass range", description = "max teammate distance for a pass", flag = "passrange", range = { 10, 120 }, increment = 5, value = CFG.passRange, suffix = " st", callback = function(v) CFG.passRange = v end })

	play:CreateSection({ name = "POWERS" })
	play:CreateButton({ name = "drop bomb", description = "the game's own power remote (id 1), only while you have one", callback = function() local ok, why = firePower("bomb") if not ok then print("[Street] " .. (why or "no path")) end end })
	play:CreateButton({ name = "raise wall", description = "power remote (id 2)", callback = function() local ok, why = firePower("wall") if not ok then print("[Street] " .. (why or "no path")) end end })
	play:CreateButton({ name = "throw spikes", description = "power remote (id 3)", callback = function() local ok, why = firePower("spike") if not ok then print("[Street] " .. (why or "no path")) end end })
	play:CreateButton({ name = "set burn", description = "power remote (id 4)", callback = function() local ok, why = firePower("burn") if not ok then print("[Street] " .. (why or "no path")) end end })
	play:CreateButton({ name = "super curve", description = "power remote (id 5) - arms it if you carry one", callback = function() local ok, why = firePower("supercurve") if not ok then print("[Street] " .. (why or "no path")) end end })

	view:CreateToggle({ name = "ball ESP", description = "orange glow on the live ball - re-locks the moment it respawns", flag = "ballesp", value = CFG.ballESP, callback = function(v) CFG.ballESP = v if not v then clearESP() end end })
	view:CreateToggle({ name = "goal beacons", description = "red + blue glow on both nets", flag = "goalbeacons", value = CFG.goalBeacons, callback = function(v) CFG.goalBeacons = v if not v then clearBeacons() end end })
	distStat = view:CreateStat({ name = "ball distance", value = 0, suffix = " st" })

	sys:CreateButton({ name = "panic (P)", description = "everything off, hands back to you", callback = panic })
	sys:CreateButton({ name = "unload panel", description = "tear everything down", callback = shutdown })
end

buildUI()

_G.TpsStreetPanel = {
	cfg = CFG,
	window = window,
	stop = shutdown,
	panic = panic,
	ball = findBall,
	goal = attackGoal,
	keeper = amKeeper,
	fireKick = fireKick,
	fireTackle = fireTackle,
	fireSave = fireSave,
	firePass = firePass,
	firePower = firePower,
	state = function()
		local ball, d = findBall()
		return {
			place = game.PlaceId,
			team = tostring(LP.TeamColor),
			keeper = amKeeper(),
			ball = ball and ball.Name .. "@" .. tostring(ball.Position) or nil,
			ballDist = d,
			attackGoal = goalCenter(attackGoal()) and tostring(goalCenter(attackGoal())) or nil,
			paths = remotePaths() ~= nil,
		}
	end,
}

print("[Street] panel loaded - auto shot, tackles, GK saves, passes, powers, ball ESP | paths "
	.. (remotePaths() and "ok" or "missing (lobby place?)"))
end

--// embedded suite: track  (from track.luau) =========================
Hub.SUITE.track = function()
-- Track & Field Legends | auto race + auto field timing
-- place 82886081053523 | Rayfield Gen2 | replace-not-stack via _G.TrackFieldPanel
--
-- fires only the game's own remotes with its own argument shapes:
--   RaceJoin("solo"|"ranked", eventId) starts a race/field comp
--   RaceInput({ raceId, t, up }) grades race notes against server time
--   FieldInput({ compId, t, up }) grades field notes against server time
-- race notes come from the game's shared RaceRules.buildPlan; field notes from
-- FieldRules.plan. every scheduled timestamp is the note's own server target,
-- so the server sees err = 0 and grades Perfect.
--
-- auto-rejoin is opt-in. race and field auto-join never run at the same time:
-- auto race owns the loop while it is on.

local prev = _G.TrackFieldPanel
local CFG = (prev and prev.cfg) or {}
for k, v in pairs({
	autoRace = false,
	autoField = false,
	autoRejoin = true,
	joinMode = "solo",
	raceEvent = "100m",
	fieldEvent = "LJ",
	startOffset = 0.002,
	dipOffset = 0.19,
	autoTrain = false,
}) do
	if CFG[k] == nil then CFG[k] = v end
end
if prev and prev.stop then pcall(prev.stop) end
_G.TrackFieldPanel = { cfg = CFG }

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
local RaceUpdate = Remotes and Remotes:FindFirstChild("RaceUpdate")
local RaceJoin = Remotes and Remotes:FindFirstChild("RaceJoin")
local RaceInput = Remotes and Remotes:FindFirstChild("RaceInput")
local FieldUpdate = Remotes and Remotes:FindFirstChild("FieldUpdate")
local FieldInput = Remotes and Remotes:FindFirstChild("FieldInput")
local Training = Remotes and Remotes:FindFirstChild("Training")

local Shared = ReplicatedStorage:FindFirstChild("Shared")
local RaceRules, FieldRules
if Shared then
	local ok1, m1 = pcall(function()
		return require(Shared:WaitForChild("RaceRules", 5))
	end)
	if ok1 then RaceRules = m1 end
	local ok2, m2 = pcall(function()
		return require(Shared:WaitForChild("FieldRules", 5))
	end)
	if ok2 then FieldRules = m2 end
end

if not (RaceRules and FieldRules and RaceUpdate and RaceJoin and RaceInput and FieldUpdate and FieldInput) then
	warn("[TRACK] Track & Field remotes not found in place " .. tostring(game.PlaceId))
	_G.TrackFieldPanel = { cfg = CFG }
	return
end

local dead = false
local function srvNow()
	return workspace:GetServerTimeNow()
end

local function at(t, fn)
	local d = t - srvNow()
	if d <= 0 then
		task.spawn(fn)
	else
		task.delay(d, fn)
	end
end

local stats = _G.TrackFieldStats or {}
_G.TrackFieldStats = stats
for k, v in pairs({
	races = 0,
	raceGrades = 0,
	racePerfect = 0,
	fieldAttempts = 0,
	fieldGrades = 0,
	fieldPerfect = 0,
	lastTime = 0,
	lastPlace = 0,
	lastReaction = 0,
	lastStartGrade = "",
}) do
	if stats[k] == nil then stats[k] = v end
end

local race = { id = nil, event = nil, points = nil, lane = nil, gunAt = nil, startAt = nil, skip = nil, speed = nil, plan = nil, token = 0 }
local field = { comp = nil, event = nil, slot = nil, board = nil, bar = nil, plan = nil, token = 0 }
local lastRaceJoin = 0
local lastFieldJoin = 0
local lastFieldEnd = 0

local statusRace = "idle"
local statusField = "idle"
local ui = {}
local shutdown

local function notify(text)
	print("[TRACK] " .. tostring(text))
	if ui.window and ui.window.Notify then
		pcall(function()
			ui.window:Notify({ title = "TRACK", content = tostring(text), duration = 4 })
		end)
	end
end

--// race -----------------------------------------------------------------------

local function raceFire(t, up)
	if race.id and not dead then
		pcall(function()
			RaceInput:FireServer({ raceId = race.id, t = t, up = up })
		end)
	end
end

local function clearRace()
	race.token = race.token + 1
	race.id = nil
	race.event = nil
	race.points = nil
	race.lane = nil
	race.gunAt = nil
	race.startAt = nil
	race.plan = nil
end

local function scheduleStart()
	local token = race.token
	local t = (race.gunAt or srvNow()) + (tonumber(CFG.startOffset) or 0.002)
	statusRace = string.format("set  gun + %.3f", t - race.gunAt)
	at(t, function()
		if dead or token ~= race.token then return end
		raceFire(t, false)
		statusRace = string.format("start pressed  %.3f", t - race.gunAt)
	end)
end

local function buildRacePlan()
	local token = race.token
	local tries = 0
	local function go()
		if dead or token ~= race.token then return end
		if race.plan then return end
		if not (race.startAt and race.event and race.points) then
			tries = tries + 1
			if tries < 40 then
				task.delay(0.1, go)
			end
			return
		end
		local ok, plan = pcall(RaceRules.buildPlan, race.event, race.startAt, race.points, race.gunAt, race.skip, race.speed)
		if not ok or type(plan) ~= "table" then
			warn("[TRACK] buildPlan failed: " .. tostring(plan))
			return
		end
		race.plan = plan
		statusRace = string.format("%d race notes", #plan)
		for _, n in ipairs(plan) do
			local t = n.target
			at(t, function()
				if dead or token ~= race.token then return end
				raceFire(t, false)
			end)
			if n.kind == "slide" and n.endAt then
				local e = n.endAt
				at(e, function()
					if dead or token ~= race.token then return end
					raceFire(e, true)
				end)
			end
		end
	end
	go()
end

local function onRaceMessage(m)
	if type(m) ~= "table" then return end
	local typ = m.type

	if typ == "Lineup" then
		local mine
		for _, l in ipairs(m.lanes or {}) do
			if l.userId == LP.UserId then
				mine = l
				break
			end
		end
		if not mine then return end
		race.token = race.token + 1
		race.id = m.raceId
		race.event = m.event
		race.skip = m.skip
		race.speed = m.speed
		race.points = mine.points
		race.lane = mine.lane
		race.gunAt = nil
		race.startAt = nil
		race.plan = nil
		stats.races = stats.races + 1
		statusRace = string.format("lineup  %s  lane %s", tostring(race.event), tostring(race.lane))
		return
	end

	if not race.id then return end
	if m.raceId and m.raceId ~= race.id then return end

	if typ == "Set" then
		race.gunAt = m.gunAt
		if race.gunAt then scheduleStart() end
	elseif typ == "Gun" then
		if not race.gunAt then
			race.gunAt = m.gunAt
			if race.gunAt then scheduleStart() end
		end
	elseif typ == "Start" then
		race.startAt = m.startAt
		stats.lastReaction = m.reaction or 0
		stats.lastStartGrade = tostring(m.grade or "")
		buildRacePlan()
	elseif typ == "Dip" then
		local token = race.token
		local t = (m.target or srvNow()) + (tonumber(CFG.dipOffset) or 0)
		at(t, function()
			if dead or token ~= race.token then return end
			raceFire(t, false)
			statusRace = "dip"
		end)
	elseif typ == "Graded" then
		if m.grade then
			stats.raceGrades = stats.raceGrades + 1
			if m.grade == "Perfect" then stats.racePerfect = stats.racePerfect + 1 end
			statusRace = string.format("%s  %s", tostring(m.role or "note"), tostring(m.grade))
		end
	elseif typ == "Finish" then
		if race.lane == nil or m.lane == race.lane then
			stats.lastTime = m.time or 0
			stats.lastPlace = m.place or 0
		end
	elseif typ == "End" then
		if m.raceId == race.id then
			clearRace()
			statusRace = "ended"
		end
	end
end

--// field ----------------------------------------------------------------------

local function fieldFire(comp, t, up)
	if comp and not dead then
		pcall(function()
			FieldInput:FireServer({ compId = comp, t = t, up = up })
		end)
	end
end

local function fieldSlotOf(m)
	local athletes = m.athletes
	if type(athletes) ~= "table" then return nil end
	for k, v in pairs(athletes) do
		if type(v) == "table" then
			local uid = v.userId or (type(v.info) == "table" and v.info.userId)
			if uid == LP.UserId then
				return v.slot or (type(v.info) == "table" and v.info.slot) or k
			end
		end
	end
	return nil
end

local function clearField()
	field.token = field.token + 1
	field.comp = nil
	field.event = nil
	field.slot = nil
	field.board = nil
	field.bar = nil
	field.plan = nil
end

local function buildFieldPlan(m, token, comp)
	local eventId = field.event
	local points = m.points
	local startAt = m.startAt
	if not (eventId and points and startAt) then return end
	local bar = m.bar or field.bar
	local ok, plan = pcall(FieldRules.plan, eventId, points, startAt, { board = field.board, bar = bar })
	if not ok or type(plan) ~= "table" or type(plan.notes) ~= "table" then
		warn("[TRACK] FieldRules.plan failed: " .. tostring(plan))
		return
	end
	field.plan = plan
	stats.fieldAttempts = stats.fieldAttempts + 1
	statusField = string.format("%s  %d notes", eventId, #plan.notes)
	for _, n in ipairs(plan.notes) do
		local t = n.target
		at(t, function()
			if dead or token ~= field.token then return end
			fieldFire(comp, t, false)
		end)
		if n.kind == "slide" and n.endAt then
			local e = n.endAt
			at(e, function()
				if dead or token ~= field.token then return end
				fieldFire(comp, e, true)
			end)
		end
	end
end

local function onFieldMessage(m)
	if type(m) ~= "table" then return end
	local typ = m.type

	if typ == "FLineup" then
		if m.replay == true then return end
		local slot = fieldSlotOf(m)
		if not slot then return end
		field.token = field.token + 1
		field.comp = m.compId
		field.event = m.event
		field.slot = slot
		field.board = m.board
		field.bar = m.bar
		field.plan = nil
		statusField = string.format("comp %s  %s  slot %s", tostring(m.compId), tostring(m.event), tostring(slot))
		return
	end

	if not field.comp then return end
	if m.compId and m.compId ~= field.comp then return end

	if typ == "FAttempt" then
		if field.slot ~= nil and m.slot ~= nil and tostring(m.slot) ~= tostring(field.slot) then return end
		if m.human == false then return end
		field.token = field.token + 1
		local token = field.token
		buildFieldPlan(m, token, field.comp)
	elseif typ == "FGraded" then
		if m.grade then
			stats.fieldGrades = stats.fieldGrades + 1
			if m.grade == "Perfect" then stats.fieldPerfect = stats.fieldPerfect + 1 end
			statusField = string.format("%s  %s", tostring(m.role or "note"), tostring(m.grade))
		end
	elseif typ == "FEnd" then
		if m.compId == field.comp then
			clearField()
			lastFieldEnd = os.clock()
			statusField = "ended"
		end
	end
end

--// joining --------------------------------------------------------------------

local function fireJoin(kind)
	if dead or not RaceJoin then return end
	if kind == "field" then
		RaceJoin:FireServer(CFG.joinMode, CFG.fieldEvent)
		statusField = "joining " .. tostring(CFG.fieldEvent)
	else
		RaceJoin:FireServer(CFG.joinMode, CFG.raceEvent)
		statusRace = "joining " .. tostring(CFG.raceEvent)
	end
end

local function leaveNow()
	if dead or not RaceJoin then return end
	pcall(function()
		if field.comp and FieldInput then
			FieldInput:FireServer({ retire = true, compId = field.comp })
		end
	end)
	pcall(function() RaceJoin:FireServer("leave") end)
	pcall(function() RaceJoin:FireServer("watch", nil) end)
	clearRace()
	clearField()
	statusRace = "left"
	statusField = "left"
end

local function joinRace(force)
	if dead or not RaceJoin then return end
	local nowC = os.clock()
	if nowC - lastRaceJoin < 1.0 then return end
	lastRaceJoin = nowC
	if force and LP:GetAttribute("InRace") == true then
		leaveNow()
		task.delay(1.2, function()
			if not dead then fireJoin("race") end
		end)
	else
		fireJoin("race")
	end
end

local function joinField(force)
	if dead or not RaceJoin then return end
	local nowC = os.clock()
	if nowC - lastFieldJoin < 1.0 then return end
	lastFieldJoin = nowC
	if force and LP:GetAttribute("InRace") == true then
		leaveNow()
		task.delay(1.2, function()
			if not dead then fireJoin("field") end
		end)
	else
		fireJoin("field")
	end
end

--// engine loop ----------------------------------------------------------------

task.spawn(function()
	while not dead do
		task.wait(2)
		if not dead then
			if CFG.autoRace and CFG.autoRejoin and not race.id then
				local inRace = LP:GetAttribute("InRace") == true
				if inRace and os.clock() - lastRaceJoin > 10 then
					joinRace(true)
				elseif not inRace then
					joinRace(false)
				end
			elseif CFG.autoField and not CFG.autoRace and CFG.autoRejoin and not field.comp then
				if os.clock() - lastFieldEnd > 6 then
					joinField(LP:GetAttribute("InRace") == true)
				end
			end
		end
	end
end)

local function panic()
	CFG.autoRace = false
	CFG.autoField = false
	CFG.autoRejoin = false
	CFG.autoTrain = false
	race.token = race.token + 1
	field.token = field.token + 1
	if Training then
		pcall(function() Training:FireServer("auto", false) end)
	end
	for _, flag in ipairs({ "tf_autoRace", "tf_autoField", "tf_autoRejoin", "tf_autoTrain" }) do
		if ui.window then
			pcall(function() ui.window:Set(flag, false) end)
		end
	end
	statusRace = "panic - hands off"
	statusField = "panic - hands off"
	print("[TRACK] panic: auto race/field/rejoin/train off")
end

--// ui -------------------------------------------------------------------------

local Rayfield
pcall(function()
	Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)

local function buildUI()
	if not Rayfield then return end
	local w = Rayfield:CreateWindow({
		Name = "TRACK // LEGENDS",
		LoadingTitle = "TRACK & FIELD",
		LoadingSubtitle = "auto race + auto field  -  server-time notes",
		KeySystem = false,
	})
	ui.window = w
	pcall(function()
		w:ChangeTheme({
			WindowColor = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(8, 12, 20)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 30, 46)),
			},
			ShadowColor = Color3.fromRGB(2, 4, 10),
			CornerRoundness = UDim.new(0, 16),
			ElementCornerRadius = UDim.new(0, 10),
			PillCornerRadius = UDim.new(1, 0),
			ElementGradient = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(16, 26, 42)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 38, 58)),
			},
			ElementStrokeGradient = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 229, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 46, 156)),
			},
			ElementStroke = Color3.fromRGB(40, 70, 100),
			ElementStrokeHover = Color3.fromRGB(0, 229, 255),
			AccentColor = Color3.fromRGB(0, 229, 255),
			AccentStroke = Color3.fromRGB(122, 252, 255),
			AccentGlow = 0.55,
			SliderProgress = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 46, 156)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 229, 255)),
			},
			SliderBackground = Color3.fromRGB(18, 30, 46),
			SliderBackgroundHover = Color3.fromRGB(28, 44, 64),
			SliderHandle = Color3.fromRGB(255, 255, 255),
			SliderStroke = Color3.fromRGB(122, 252, 255),
			ToggleTrack = Color3.fromRGB(10, 16, 26),
			ToggleTrackTransparency = 0.7,
			ToggleKnobOff = Color3.fromRGB(130, 140, 160),
			ContentColor = Color3.fromRGB(236, 242, 255),
			TitlingColor = Color3.fromRGB(255, 255, 255),
			ElementTextHoverColor = Color3.fromRGB(0, 229, 255),
			StatBackground = Color3.fromRGB(12, 22, 36),
			TabBackground = ColorSequence.new(Color3.fromRGB(22, 38, 58), Color3.fromRGB(12, 20, 32)),
			TabStroke = ColorSequence.new(Color3.fromRGB(0, 229, 255), Color3.fromRGB(255, 46, 156)),
			TabColor = Color3.fromRGB(240, 245, 255),
			FieldGlow = Color3.fromRGB(0, 229, 255),
			DropdownHighlight = Color3.fromRGB(0, 229, 255),
		})
	end)

	local raceTab = w:CreateTab({ name = "RACE" })
	local fieldTab = w:CreateTab({ name = "FIELD" })
	local sysTab = w:CreateTab({ name = "SYS" })

	ui.raceCard = raceTab:CreateText({ name = "race  |  idle", text = "no lineup yet" })
	raceTab:CreateToggle({
		name = "auto race",
		description = "watch RaceUpdate, press the start at gun + offset, then fire every RaceRules note at its exact server target and the dip at the calibrated offset. auto-rejoin is controlled on SYS.",
		flag = "tf_autoRace",
		value = CFG.autoRace,
		callback = function(v)
			CFG.autoRace = v
			if v then
				joinRace(LP:GetAttribute("InRace") == true)
			end
		end,
	})
	local raceOptions = {}
	if type(RaceRules.EVENTS) == "table" then
		for k in pairs(RaceRules.EVENTS) do
			table.insert(raceOptions, tostring(k))
		end
	else
		for _, k in ipairs({ "100m", "i60m", "200m", "400m", "800m", "1500m", "110mH", "400mH", "i60mH", "300m", "4x100m", "4x400m", "i4x200m", "i4x400m" }) do
			table.insert(raceOptions, k)
		end
	end
	table.sort(raceOptions)
	local raceDefault = CFG.raceEvent
	local hasRaceDefault = false
	for _, k in ipairs(raceOptions) do
		if k == raceDefault then hasRaceDefault = true end
	end
	if not hasRaceDefault and raceOptions[1] then
		raceDefault = raceOptions[1]
		CFG.raceEvent = raceDefault
	end
	raceTab:CreateDropdown({
		name = "race event",
		description = "any race the solo/ranked board offers. relays use the same plan and the same server targets.",
		flag = "tf_raceEvent",
		options = raceOptions,
		value = raceDefault,
		callback = function(v)
			CFG.raceEvent = tostring(v)
		end,
	})
	raceTab:CreateDropdown({
		name = "join mode",
		description = "solo is the quiet heat. ranked is the trophy heat. both are the game's own RaceJoin paths.",
		flag = "tf_joinMode",
		options = { "solo", "ranked" },
		value = CFG.joinMode,
		callback = function(v)
			CFG.joinMode = tostring(v)
		end,
	})
	raceTab:CreateButton({
		name = "join race now",
		description = "leave any stuck results/watch state, then fire RaceJoin with the selected mode and event.",
		callback = function()
			joinRace(true)
		end,
	})
	raceTab:CreateButton({
		name = "leave race / comp",
		description = "retire the field comp if one is live, then RaceJoin leave + watch nil to clear InRace.",
		callback = leaveNow,
	})
	raceTab:CreateSlider({
		name = "start offset",
		description = "seconds after the gun for the start press. 0.002 is the server's perfect reaction window.",
		flag = "tf_startOffset",
		range = { 0, 0.05 },
		increment = 0.001,
		value = CFG.startOffset,
		suffix = " s",
		callback = function(v)
			CFG.startOffset = v
		end,
	})
	raceTab:CreateSlider({
		name = "dip offset",
		description = "seconds added to the Dip target. the shipped client target and the grading target differ by about 0.19s.",
		flag = "tf_dipOffset",
		range = { 0, 0.4 },
		increment = 0.005,
		value = CFG.dipOffset,
		suffix = " s",
		callback = function(v)
			CFG.dipOffset = v
		end,
	})
	raceTab:CreateSection({ name = "SESSION" })
	ui.statRaces = raceTab:CreateStat({ name = "races", value = stats.races })
	ui.statRacePerfect = raceTab:CreateStat({ name = "perfect notes", value = stats.racePerfect })
	ui.statReaction = raceTab:CreateStat({ name = "reaction", value = math.floor((stats.lastReaction or 0) * 1000) / 1000, suffix = " s" })
	ui.statTime = raceTab:CreateStat({ name = "last time", value = stats.lastTime or 0, suffix = " s" })

	ui.fieldCard = fieldTab:CreateText({ name = "field  |  idle", text = "no comp yet" })
	fieldTab:CreateToggle({
		name = "auto field",
		description = "scan FLineup for your own slot, then only accept FAttempt for that slot and that comp. every FieldRules note fires at its server target, slides release at endAt.",
		flag = "tf_autoField",
		value = CFG.autoField,
		callback = function(v)
			CFG.autoField = v
			if v then
				joinField(LP:GetAttribute("InRace") == true)
			end
		end,
	})
	local fieldOptions = { "LJ", "TJ", "HJ", "PV", "SP", "DT", "HT", "JT", "iLJ", "iTJ", "iHJ", "iPV", "iSP", "iWT" }
	local fieldDefault = CFG.fieldEvent
	local hasFieldDefault = false
	for _, k in ipairs(fieldOptions) do
		if k == fieldDefault then hasFieldDefault = true end
	end
	if not hasFieldDefault then
		fieldDefault = fieldOptions[1]
		CFG.fieldEvent = fieldDefault
	end
	fieldTab:CreateDropdown({
		name = "field event",
		description = "jumps, throws and indoor variants. the game's FieldRules decides the approach, notes and slide windows.",
		flag = "tf_fieldEvent",
		options = fieldOptions,
		value = fieldDefault,
		callback = function(v)
			CFG.fieldEvent = tostring(v)
		end,
	})
	fieldTab:CreateButton({
		name = "join field now",
		description = "RaceJoin solo/ranked with the selected field event, then wait for the FLineup that contains your userId.",
		callback = function()
			joinField(true)
		end,
	})
	fieldTab:CreateSection({ name = "SESSION" })
	ui.statFieldAttempts = fieldTab:CreateStat({ name = "attempts", value = stats.fieldAttempts })
	ui.statFieldPerfect = fieldTab:CreateStat({ name = "perfect notes", value = stats.fieldPerfect })

	sysTab:CreateToggle({
		name = "auto rejoin",
		description = "after End/FEnd, clear the results state and join the next selected race or field event. race owns the loop whenever auto race is on.",
		flag = "tf_autoRejoin",
		value = CFG.autoRejoin,
		callback = function(v)
			CFG.autoRejoin = v
		end,
	})
	sysTab:CreateToggle({
		name = "auto training (pass)",
		description = "the game gates Training auto behind the AUTO-TRAIN pass. without it this toggle refuses and points you at SHOP > PASSES.",
		flag = "tf_autoTrain",
		value = CFG.autoTrain,
		callback = function(v)
			if v and LP:GetAttribute("Pass_autotrain") ~= true then
				CFG.autoTrain = false
				if ui.window then pcall(function() ui.window:Set("tf_autoTrain", false) end) end
				notify("AUTO-TRAIN is a game pass: SHOP > PASSES")
				return
			end
			CFG.autoTrain = v
			if Training then
				pcall(function() Training:FireServer("auto", v) end)
			end
		end,
	})
	sysTab:CreateButton({ name = "panic (P)", description = "kill auto race, field, rejoin and training; stop every pending note.", callback = panic })
	sysTab:CreateButton({ name = "unload panel", description = "tear everything down and keep your settings.", callback = function()
		if shutdown then shutdown() end
	end })

	local keyConn
	keyConn = UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.P then
			panic()
		end
	end)
	ui.keyConn = keyConn
end

local function syncUI()
	if ui.raceCard then
		pcall(function()
			ui.raceCard:SetTitle("race  |  " .. (race.id and tostring(race.event) or "idle"))
			ui.raceCard:Set(statusRace)
		end)
	end
	if ui.fieldCard then
		pcall(function()
			ui.fieldCard:SetTitle("field  |  " .. (field.comp and tostring(field.event) or "idle"))
			ui.fieldCard:Set(statusField)
		end)
	end
	if ui.statRaces then pcall(function() ui.statRaces:Set(stats.races) end) end
	if ui.statRacePerfect then pcall(function() ui.statRacePerfect:Set(stats.racePerfect) end) end
	if ui.statReaction then pcall(function() ui.statReaction:Set(math.floor((stats.lastReaction or 0) * 1000) / 1000) end) end
	if ui.statTime then pcall(function() ui.statTime:Set(math.floor((stats.lastTime or 0) * 100) / 100) end) end
	if ui.statFieldAttempts then pcall(function() ui.statFieldAttempts:Set(stats.fieldAttempts) end) end
	if ui.statFieldPerfect then pcall(function() ui.statFieldPerfect:Set(stats.fieldPerfect) end) end
end

local lastSync = 0
local syncConn = RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now - lastSync >= 0.25 then
		lastSync = now
		pcall(syncUI)
	end
end)

local raceConn = RaceUpdate.OnClientEvent:Connect(onRaceMessage)
local fieldConn = FieldUpdate.OnClientEvent:Connect(onFieldMessage)

shutdown = function()
	if dead then return end
	dead = true
	clearRace()
	clearField()
	if raceConn then pcall(function() raceConn:Disconnect() end) end
	if fieldConn then pcall(function() fieldConn:Disconnect() end) end
	if syncConn then pcall(function() syncConn:Disconnect() end) end
	if ui.keyConn then pcall(function() ui.keyConn:Disconnect() end) end
	if ui.window then pcall(function() ui.window:Unload() end) end
	if Training and CFG.autoTrain then
		pcall(function() Training:FireServer("auto", false) end)
	end
	_G.TrackFieldPanel = { cfg = CFG }
	print("[TRACK] unloaded")
end

buildUI()
-- a saved auto-train toggle must not stay on when the pass is not owned
if CFG.autoTrain and LP:GetAttribute("Pass_autotrain") ~= true then
	CFG.autoTrain = false
	if ui.window then pcall(function() ui.window:Set("tf_autoTrain", false) end) end
	notify("AUTO-TRAIN is a game pass: SHOP > PASSES")
end
_G.TrackFieldPanel = {
	cfg = CFG,
	window = ui.window,
	stop = shutdown,
	panic = panic,
	joinRace = joinRace,
	joinField = joinField,
	leave = leaveNow,
	race = race,
	field = field,
	stats = stats,
}

print(string.format("[TRACK] panel loaded - auto race/field, dip %.3f, start %.3f | %s", CFG.dipOffset, CFG.startOffset, CFG.joinMode))
end

--// embedded suite: rss  (from rss.luau) =========================
Hub.SUITE.rss = function()
-- Realistic Street Soccer | STREET - auto shot (the game's own curve + kick anims),
-- auto pass, auto tackle, auto header, auto GK dive, auto grab, auto crossover,
-- ball ESP, goal beacons
-- place 14315258385 | Rayfield Gen2 | replace-not-stack via _G.RssStreetPanel
-- rides only official paths: fires the game's own Remotes (ShootTheBaII / Pass / Action /
-- the attribute grab remote) with the exact argument patterns its StarterCharacterScripts
-- controller sends, and gates on the same Bools/states its own clients check.
-- never touches Remotes.Tackle or Remotes.ShootTheBall (never fired by the PC client -
-- decoy names), never fires GKHitbox / MatchAborted style server->client events.

local prev = _G.RssStreetPanel
local CFG = (prev and prev.cfg) or {}
-- defaults merge: keeps saved settings across reloads, fills in fields added later
for k, v in pairs({
	autoPlay = false,
	autoTeam = false,
	autoShot = true,
	shotRange = 8,
	shotGoalRange = 90,
	shotPower = 85,
	shotCurve = 0,
	curveComp = 0,
	powerMode = false,
	autoPass = false,
	passRange = 60,
	autoTackle = false,
	tackleRange = 8,
	autoHeader = false,
	autoCrossover = false,
	crossoverRange = 9,
	autoGrab = true,
	autoGK = false,
	gkRange = 16,
	ballESP = true,
	goalBeacons = true,
	playerESP = false,
	cooldown = 0.9,
}) do
	if CFG[k] == nil then
		CFG[k] = v
	end
end
if prev and prev.stop then
	pcall(prev.stop)
end
-- the game's own curve is a direction, not a magnitude: the bend amount is the
-- game's, so this flag is just on or off (an older build stored studs here)
CFG.shotCurve = (tonumber(CFG.shotCurve) or 0) > 0.5 and 1 or 0
_G.RssStreetPanel = { cfg = CFG }

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local LP = Players.LocalPlayer

-- the game's own shared ball library: getBall / teamOf / state come straight from it
local BallContext
pcall(function()
	BallContext = require(ReplicatedStorage:WaitForChild("BallContext"))
end)

--// locators -------------------------------------------------------------------

-- getBall replica (non-tutorial: the single Workspace ball part)
local function findBall()
	if BallContext then
		local ok, b = pcall(BallContext.getBall, LP)
		if ok and b then
			return b
		end
	end
	return Workspace:FindFirstChild("ball")
end

local function myBools(char)
	return char and char:FindFirstChild("Bools")
end

-- BallContext.state replica: round states live in workspace.Bools.<name>.Value
local function state(name)
	local f = Workspace:FindFirstChild("Bools")
	local v = f and f:FindFirstChild(name)
	return v and v.Value == true or false
end

-- absolute server time - every schedule in this panel runs off the server's
-- clock, so a lag spike or a long frame never drifts a cooldown
local function nowT()
	return workspace:GetServerTimeNow()
end

-- the game's own round flags - when this changes the round turned over, and
-- the generation token cancels whatever was still scheduled for the old one
local function roundSignature()
	local b = Workspace:FindFirstChild("Bools")
	local function v(n)
		local x = b and b:FindFirstChild(n)
		return x and tostring(x.Value) or "-"
	end
	return table.concat({
		v("Kickoff"),
		v("Intermission"),
		v("Cutscene"),
		v("freezeplay"),
		v("startgame"),
		v("homeGoals"),
		v("awayGoals"),
	}, "|")
end

local HOME = BrickColor.new(141) -- BallContext.HOME
local AWAY = BrickColor.new(23) -- BallContext.AWAY

local function amPlaying()
	-- Fans / neutral never act; only the two field teams do
	local tc = LP.TeamColor
	return tc == HOME or tc == AWAY
end

local function teamColor()
	return LP.TeamColor
end

-- team 23 (Away) scores on HomeGoal, team 141 (Home) on AwayGoal (mobile ShootScript)
local function attackGoal()
	if teamColor() == AWAY then
		return Workspace:FindFirstChild("HomeGoal")
	elseif teamColor() == HOME then
		return Workspace:FindFirstChild("AwayGoal")
	end
	return nil
end

local function ownGoal()
	if teamColor() == HOME then
		return Workspace:FindFirstChild("HomeGoal")
	elseif teamColor() == AWAY then
		return Workspace:FindFirstChild("AwayGoal")
	end
	return nil
end

local function goalCenter(model)
	if not model then
		return nil
	end
	if model:IsA("BasePart") then
		return model.Position
	end
	local ok, cf = pcall(function()
		return model:GetBoundingBox()
	end)
	if ok and cf then
		return cf.Position
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			return d.Position
		end
	end
	return nil
end

-- the designated keepers, straight from the game's own round bools
local function keeperBool()
	local f = Workspace:FindFirstChild("Bools")
	return f and f:FindFirstChild("HPG"), f and f:FindFirstChild("APG")
end

local function amKeeper()
	local hpg, apg = keeperBool()
	return (hpg and hpg.Value == LP) or (apg and apg.Value == LP)
end

local function enemyKeeperChar()
	local hpg, apg = keeperBool()
	local kp
	if teamColor() == HOME then
		kp = apg and apg.Value
	else
		kp = hpg and hpg.Value
	end
	return kp and kp.Character or nil
end

-- the game's own target set for aiming (mobile ShootScript uses Goal.Targets)
local function goalTargets(goalModel)
	local t = goalModel and goalModel:FindFirstChild("Targets")
	if not t then
		return {}
	end
	local out = {}
	for _, c in ipairs(t:GetChildren()) do
		if c:IsA("BasePart") then
			table.insert(out, c)
		end
	end
	return out
end

-- FindClosestPlayer replica (StarterCharacterScripts controller): closest teammate
-- to a point 190 studs ahead of the camera, keepers and self excluded, FieldBots included
local function findClosestTeammate()
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local cam = Workspace:FindFirstChild("Camera") or Workspace.CurrentCamera
	if not (hrp and cam) then
		return nil, nil
	end
	local probe = hrp.Position + cam.CFrame.LookVector * 190
	local best, bestD = nil, math.huge
	local hpg, apg = keeperBool()
	for _, p in ipairs(Players:GetPlayers()) do
		local phrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if
			phrp
			and p ~= LP
			and p.TeamColor == teamColor()
			and p ~= (hpg and hpg.Value)
			and p ~= (apg and apg.Value)
		then
			local d = (phrp.Position - probe).Magnitude
			if d < bestD then
				best, bestD = p, d
			end
		end
	end
	local fieldBots = Workspace:FindFirstChild("FieldBots")
	if fieldBots then
		for _, bot in ipairs(fieldBots:GetChildren()) do
			local bb = bot:FindFirstChild("BotBools")
			local bhrp = bot:FindFirstChild("HumanoidRootPart")
			if bb and bhrp and bb:FindFirstChild("TeamColor") and bb.TeamColor.Value == teamColor() then
				local d = (bhrp.Position - probe).Magnitude
				if d < bestD then
					best, bestD = bot, d
				end
			end
		end
	end
	return best, bestD
end

local function nearestOpponentTo(pos)
	local best, bestD = nil, math.huge
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP and p.TeamColor ~= teamColor() and p.TeamColor ~= BrickColor.new("White") then
			local phrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if phrp then
				local d = (phrp.Position - pos).Magnitude
				if d < bestD then
					best, bestD = p, d
				end
			end
		end
	end
	return best, bestD
end

-- nearest opponent standing in the carry path (players and enemy FieldBots),
-- in front of us along dir and inside range - the one a crossover would beat
local function defenderAhead(hrp, dir, range)
	local best, bestD = nil, math.huge
	local function consider(phrp)
		if not phrp then
			return
		end
		local rel = Vector3.new(phrp.Position.X - hrp.Position.X, 0, phrp.Position.Z - hrp.Position.Z)
		local d = rel.Magnitude
		if d > 0.5 and d < range and rel.Unit:Dot(dir) > 0.5 and d < bestD then
			best, bestD = phrp, d
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP and p.TeamColor ~= teamColor() and p.TeamColor ~= BrickColor.new("White") then
			consider(p.Character and p.Character:FindFirstChild("HumanoidRootPart"))
		end
	end
	local fieldBots = Workspace:FindFirstChild("FieldBots")
	if fieldBots then
		for _, bot in ipairs(fieldBots:GetChildren()) do
			local bb = bot:FindFirstChild("BotBools")
			local bhrp = bot:FindFirstChild("HumanoidRootPart")
			if bb and bhrp and bb:FindFirstChild("TeamColor") and bb.TeamColor.Value ~= teamColor() then
				consider(bhrp)
			end
		end
	end
	return best, bestD
end

-- a pressing defender: one closing on us fast while we carry, mid-tackle lunge
-- (their own Tackling flag - exactly what the game's E-key raises), or standing in
-- our stride. any direction - presses come from behind and the side too
local function findPress(hrp, range)
	local best
	local myVel = hrp.AssemblyLinearVelocity
	local flatVel = Vector3.new(myVel.X, 0, myVel.Z)
	local mySpeed = flatVel.Magnitude
	local function consider(phrp)
		if not phrp then
			return
		end
		local rel = Vector3.new(phrp.Position.X - hrp.Position.X, 0, phrp.Position.Z - hrp.Position.Z)
		local d = rel.Magnitude
		if d < 0.5 or d > range then
			return
		end
		local unit = rel.Unit
		local relVel = phrp.AssemblyLinearVelocity - myVel
		local closing = -Vector3.new(relVel.X, 0, relVel.Z):Dot(unit) -- + = gap shrinking
		-- their committed tackle lunge is the strongest press signal there is
		local holder = phrp.Parent
		local pb = holder and (holder:FindFirstChild("Bools") or holder:FindFirstChild("BotBools"))
		local tackleFlag = pb and pb:FindFirstChild("Tackling")
		local lunging = tackleFlag ~= nil and tackleFlag.Value == true
		local score
		if lunging then
			score = 100 + (range - d) -- they've committed: beat it now
		elseif closing > 8 then
			score = closing * 2 + (range - d) -- sprinting onto us: it's a press
		elseif mySpeed > 6 and unit:Dot(flatVel.Unit) > 0.6 and d <= range * 0.8 then
			score = range - d -- parked in our stride as we run at them
		else
			return
		end
		if not best or score > best.score then
			best = { hrp = phrp, dist = d, closing = closing, lunging = lunging, score = score }
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP and p.TeamColor ~= teamColor() and p.TeamColor ~= BrickColor.new("White") then
			consider(p.Character and p.Character:FindFirstChild("HumanoidRootPart"))
		end
	end
	local fieldBots = Workspace:FindFirstChild("FieldBots")
	if fieldBots then
		for _, bot in ipairs(fieldBots:GetChildren()) do
			local bb = bot:FindFirstChild("BotBools")
			local bhrp = bot:FindFirstChild("HumanoidRootPart")
			if bb and bhrp and bb:FindFirstChild("TeamColor") and bb.TeamColor.Value ~= teamColor() then
				consider(bhrp)
			end
		end
	end
	return best
end

-- entity helpers that work for both players and FieldBots (the game's own teamOf does the same)
local function entChar(ent)
	if not ent then
		return nil
	end
	if ent:IsA("Player") then
		return ent.Character
	end
	if ent:IsA("Model") then
		return ent
	end
	return nil
end

local function entTeam(ent)
	if not ent then
		return nil
	end
	if BallContext then
		local ok, t = pcall(BallContext.teamOf, ent)
		if ok and t then
			return t
		end
	end
	if ent:IsA("Player") then
		return ent.TeamColor
	end
	local bb = ent:FindFirstChild("BotBools")
	local tc = bb and bb:FindFirstChild("TeamColor")
	return tc and tc.Value or nil
end

--// official-path remote wrappers ----------------------------------------------
-- every call below is a copy of what the game's own StarterCharacterScripts
-- controller fires, same args in the same order, gated the same way it gates them.

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")

local function remotePaths()
	if not Remotes then
		return nil
	end
	local shoot = Remotes:FindFirstChild("ShootTheBaII") -- capital i's: the PC client's remote
	local pass = Remotes:FindFirstChild("Pass")
	local action = Remotes:FindFirstChild("Action")
	if not (shoot and pass and action) then
		return nil
	end
	-- the grab remote is found by attribute exactly like the controller finds it
	local grab
	for _, v in ipairs(Remotes:GetChildren()) do
		if v:IsA("RemoteEvent") and v:GetAttribute("Attribute") then
			grab = v
		end
	end
	-- the game's own team pick: its role-select buttons fire exactly this one
	local teamChange = Remotes:FindFirstChild("TeamChange")
	return { shoot = shoot, pass = pass, action = action, grab = grab, teamChange = teamChange }
end

-- join a field side the way the game does it: its own MenuV2 role-select
-- buttons fire Remotes.TeamChange with the side colour and the role, and they
-- only offer a side that is under three players and not a full step behind.
-- BrickColor 141 is the home side, 23 the away side.
local function joinFieldTeam()
	local R = remotePaths()
	if not R or not R.teamChange then
		return false
	end
	local b = Workspace:FindFirstChild("Bools")
	local home = b and b:FindFirstChild("homePlrCount")
	local away = b and b:FindFirstChild("awayPlrCount")
	local hc = home and home.Value or 0
	local ac = away and away.Value or 0
	local homeOk = hc ~= 3 and hc <= ac + 1
	local awayOk = ac ~= 3 and ac <= hc + 1
	local color
	if homeOk and (not awayOk or hc <= ac) then
		color = BrickColor.new(141)
	elseif awayOk then
		color = BrickColor.new(23)
	else
		return false
	end
	if state("Cutscene") or state("freezeplay") or state("Intermission") then
		return false
	end
	if LP:GetAttribute("InTutorial") == true then
		return false
	end
	R.teamChange:FireServer(color, "Player")
	return true
end

local function ballValid(ball)
	return ball ~= nil and ball.Parent ~= nil and not ball.Anchored
end

-- i possess the ball: welded at my feet with me as creator (the controller's own shot gate)
local function possessing(ball)
	local weld = ball and ball:FindFirstChild("playerWeld")
	local creator = ball and ball:FindFirstChild("creator")
	return weld ~= nil and creator ~= nil and creator.Value == LP
end

local function booleansClean(char)
	local b = myBools(char)
	if not b then
		return false
	end
	local t, d, k = b:FindFirstChild("Tackled"), b:FindFirstChild("Debounce"), b:FindFirstChild("Tackling")
	return (t and t.Value ~= true) and (d and d.Value ~= true) and (k and k.Value ~= true)
end

--// shot animation + curve (the controller's own kick anims and curve physics) ---

-- round generation token: a new round bumps it, so work scheduled for the
-- previous one is dropped instead of firing into the next round
local roundGen = 0

-- the game's own curve: its client sets Character.Bools.Curve.Value to
-- "Left"/"Right" while the shot is aimed and sends that string in the shoot
-- remote's 7th argument - the server bends the ball that way. the ball itself
-- is server-simulated (a client-side velocity write does not move it), so the
-- game's own curve is the only thing that bends it.
local CURVE_CHARGE_GATE = 0.7 -- the game's own charged-shot threshold

-- what the last shot actually sent, so a curve can be checked against the
-- ball's own path after the fact
local lastShot = nil

local shootTrackCache = {}

local function getShootTrack(char, name)
	local perChar = shootTrackCache[char]
	if not perChar then
		perChar = {}
		shootTrackCache[char] = perChar
	end
	local track = perChar[name]
	if not track then
		local anims = ReplicatedStorage:FindFirstChild("Animations")
		local anim = anims and anims:FindFirstChild(name)
		local human = char and char:FindFirstChildOfClass("Humanoid")
		local animator = human and human:FindFirstChildOfClass("Animator")
		local loader = animator or human
		if anim and loader then
			track = loader:LoadAnimation(anim)
			perChar[name] = track
		end
	end
	return track
end

-- the controller plays its kick right before the shot fires: RShoot on a quick
-- release, the direction variants on charged shots, RPowerShoot on powershots -
-- all at its Action4 priority
local function playShootAnim(char, aimDir, hold, power)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and aimDir) then
		return
	end
	local name = "RShoot"
	if power then
		name = "RPowerShoot"
	elseif hold and hold > 0.5 then
		-- aim angle in the character's object space picks the variant
		local obj = hrp.CFrame:VectorToObjectSpace(aimDir)
		local ang = math.deg(math.atan2(obj.X, -obj.Z))
		if ang <= -135 or ang >= 135 then
			name = "RShootBackward"
		elseif ang <= -40 then
			name = "RShootLeft"
		else
			name = "RShoot2"
		end
	end
	local chosen = getShootTrack(char, name)
	for _, n in ipairs({ "RShoot", "RShoot2", "RShootLeft", "RShootBackward", "RPowerShoot" }) do
		local t = getShootTrack(char, n)
		if t and t ~= chosen and t.IsPlaying then
			pcall(function()
				t:Stop()
			end)
		end
	end
	if chosen then
		chosen.Priority = Enum.AnimationPriority.Action4
		chosen:Play()
	end
end

-- solve a shot: aim direction, charge seconds, curve side + side sign. `bend` is
-- studs of sideways travel the curve engine will add, and the aim is offset the
-- other way so the ball still lands on the corner once it has bent
local function solveShot(ball, target, bend, powerPct)
	if not (ball and target) then
		return nil
	end
	local flat = Vector3.new(target.X - ball.Position.X, 0, target.Z - ball.Position.Z)
	if flat.Magnitude < 2 then
		return nil
	end
	local dir = flat.Unit
	local hold = math.clamp((powerPct or 85) / 100, 0.15, 1)
	local curve, side = "None", 0
	if (bend or 0) > 0.5 then
		-- swing at the keeper's side of the line; the aim leans away so the
		-- bend lands back on the target
		local right = CFrame.lookAt(Vector3.zero, dir).RightVector
		local keeper = enemyKeeperChar()
		local khrp = keeper and keeper:FindFirstChild("HumanoidRootPart")
		side = 1
		if khrp then
			local lat = Vector3.new(
				khrp.Position.X - ball.Position.X,
				0,
				khrp.Position.Z - ball.Position.Z
			):Dot(right)
			side = lat >= 0 and 1 or -1
		end
		curve = side > 0 and "Right" or "Left"
		if hold < CURVE_CHARGE_GATE then
			curve = "None" -- the game only bends a charged shot
		else
			-- the game's curve pushes the ball sideways on its way to the goal,
			-- so the aim leans back by the compensation amount to keep the shot
			-- on the corner the panel aimed at
			local travel = CFG.curveComp or 0
			if travel > 0 then
				local aimPoint = target - right * (side * travel)
				local flat2 = Vector3.new(aimPoint.X - ball.Position.X, 0, aimPoint.Z - ball.Position.Z)
				if flat2.Magnitude > 2 then
					dir = flat2.Unit
				end
			end
		end
	end
	return dir, hold, curve, side
end

-- shot replica (controller mouserelease PC form): aim unit, ball CFrame, charge
-- seconds, aim again, false, false, curve side, nil, powershot flag - with the
-- controller's own kick animation. the curve side is the game's own: its
-- client sets Character.Bools.Curve.Value while the shot is aimed and sends
-- that string here, and the server bends the ball that way.
local function fireShot(ball, aimDir, hold, curve, side)
	local R = remotePaths()
	if not R or not ballValid(ball) then
		return false
	end
	local char = LP.Character
	if not char then
		return false
	end
	hold = math.clamp(hold or 0.85, 0.01, 1)
	local curveArg = (curve == "Left" or curve == "Right") and curve or "None"
	playShootAnim(char, aimDir, hold)
	local bools = myBools(char)
	local flag = bools and bools:FindFirstChild("Curve")
	if flag then
		flag.Value = curveArg
	end
	R.shoot:FireServer(aimDir, ball.CFrame, hold, aimDir, false, false, curveArg, nil, false)
	if flag then
		flag.Value = "None"
	end
	lastShot = { curve = curveArg, hold = hold, at = nowT() }
	return true
end

-- full power shot replica (controller charged powershot path, power 1)
local function firePowerShot(ball, aimDir)
	local R = remotePaths()
	if not R or not ballValid(ball) then
		return false
	end
	local char = LP.Character
	local head = char and char:FindFirstChild("Head")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (head and hrp) then
		return false
	end
	local cf = CFrame.new(ball.Position.X, head.CFrame.Y, ball.Position.Z)
	R.shoot:FireServer(aimDir - Vector3.new(0, 0.11, 0), cf, 1, hrp.CFrame.LookVector * 2000, false, true)
	return true
end

-- pass replica (controller pass(): FindClosestPlayer + ball CFrame)
local function firePass(ball)
	local R = remotePaths()
	if not R or not ballValid(ball) then
		return false
	end
	local target = findClosestTeammate()
	if not target then
		return false
	end
	R.pass:FireServer(target, ball.CFrame)
	return true
end

-- tackle replica (controller E-key path: Action "TackIe", capital i as the game spells it)
local function fireTackle()
	local R = remotePaths()
	if not R then
		return false
	end
	R.action:FireServer("TackIe")
	return true
end

-- header replica (controller headerOld: BicycleKick while a pass is inbound, else Header)
local function fireHeader(ball)
	local R = remotePaths()
	if not R then
		return false
	end
	if ball and ball:FindFirstChild("PassBV") then
		R.action:FireServer("BicycleKick")
	else
		R.action:FireServer("Header")
	end
	return true
end

-- deke replica (controller deke() / Q-key Dribble): the game's own dribble-skill
-- action - the server plays whichever skill you have equipped (crossover, ronaldo
-- chop, elastico, stepover...), the client just fires "Deke" under these exact gates
local function fireDeke(ball)
	local R = remotePaths()
	if not R or not ballValid(ball) then
		return false
	end
	local char = LP.Character
	local b = myBools(char)
	if not (char and b) then
		return false
	end
	local iframe = b:FindFirstChild("iframe")
	local ddelay = b:FindFirstChild("dribbleDebounce")
	local headerFlag = b:FindFirstChild("Header")
	local lb = char:FindFirstChild("LocalBool")
	local charging = lb and lb:FindFirstChild("PowerShoot")
	if
		possessing(ball)
		and booleansClean(char)
		and not (iframe and iframe.Value == true)
		and not (ddelay and ddelay.Value == true)
		and not (headerFlag and headerFlag.Value == true)
		and not (charging and charging.Value == true)
		and state("FreeKick") == false
		and not state("Penalty")
		and not amKeeper()
	then
		R.action:FireServer("Deke")
		return true
	end
	return false
end

-- dive replica (controller rightdive/leftdive/frontdive): the Action remote plus the
-- exact client physics the game applies - BodyVelocity 35 studs/s for 0.8s + keeper gyro
local function fireDive(side)
	local R = remotePaths()
	if not R then
		return false
	end
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end
	local human = char:FindFirstChild("Humanoid")
	if human then
		human:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end
	R.action:FireServer(side, hrp.CFrame)
	local bv = Instance.new("BodyVelocity")
	bv.Parent = hrp
	if side == "LeftDive" then
		bv.Velocity = hrp.CFrame.RightVector * -35
	elseif side == "FrontDive" then
		bv.Velocity = hrp.CFrame.LookVector * 35
	else
		bv.Velocity = hrp.CFrame.RightVector * 35
	end
	bv.MaxForce = Vector3.new(4000000, 0, 4000000)
	Debris:AddItem(bv, 0.8)
	TweenService:Create(bv, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		Velocity = bv.Velocity * 0.1,
	}):Play()
	local gyro = Instance.new("BodyGyro")
	gyro.Name = "GKGyro"
	gyro.Parent = hrp
	gyro.P = 950000
	gyro.MaxTorque = Vector3.new(0, 100000, 0)
	gyro.CFrame = hrp.CFrame
	Debris:AddItem(gyro, 0.8)
	task.delay(1, function()
		if human and human.Parent then
			human:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end
	end)
	return true
end

-- grab replica (controller ball-touch path): the attribute remote + GrabTick, exactly
-- how the game's own client picks up an incoming pass
local function fireGrab(ball, dist)
	local R = remotePaths()
	if not R or not R.grab or not ballValid(ball) then
		return false
	end
	local char = LP.Character
	local b = myBools(char)
	local gt = b and b:FindFirstChild("GrabTick")
	if gt then
		gt.Value = tick()
	end
	R.grab:FireServer(dist)
	return true
end

--// aim -------------------------------------------------------------------------

-- pick the goal target farthest from the enemy keeper (else the nearest opponent)
local function bestTarget()
	local goal = attackGoal()
	local targets = goalTargets(goal)
	if #targets == 0 then
		return goalCenter(goal)
	end
	local keeper = enemyKeeperChar()
	local keeperHrp = keeper and keeper:FindFirstChild("HumanoidRootPart")
	local refPos
	if keeperHrp then
		refPos = keeperHrp.Position
	else
		local ball = findBall()
		local opp, _ = nearestOpponentTo(ball and ball.Position or (goalCenter(goal) or Vector3.zero))
		refPos = opp and opp.Character and opp.Character:FindFirstChild("HumanoidRootPart")
			and opp.Character.HumanoidRootPart.Position
			or nil
	end
	local best, bestD = nil, -1
	for _, t in ipairs(targets) do
		local d = refPos and (refPos - t.Position).Magnitude or 0
		if d > bestD then
			best, bestD = t, d
		end
	end
	return best and best.Position or goalCenter(goal)
end

-- mobile ShootScript aim math: unit from the ball to the chosen target
local function aimDir(ball)
	local tp = bestTarget()
	if not tp then
		return nil
	end
	local delta = tp - ball.Position
	if delta.Magnitude < 0.5 then
		return nil
	end
	return delta.Unit
end

-- face a point flat on the ground, like the game's own movement does
local function face(char, pos)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not pos then
		return
	end
	local flat = Vector3.new(pos.X - hrp.Position.X, 0, pos.Z - hrp.Position.Z)
	if flat.Magnitude > 1 then
		hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat.Unit)
	end
end

--// visuals --------------------------------------------------------------------

local espHL, espBall
local beaconAtk, beaconOwn
local playerHLs = {}
local distStat, speedStat

local function clearESP()
	if espHL then
		pcall(function()
			espHL:Destroy()
		end)
	end
	espHL, espBall = nil, nil
end

local function clearBeacons()
	for _, b in ipairs({ beaconAtk, beaconOwn }) do
		if b then
			pcall(function()
				b:Destroy()
			end)
		end
	end
	beaconAtk, beaconOwn = nil, nil
end

local function clearPlayerESP()
	for _, h in pairs(playerHLs) do
		pcall(function()
			h:Destroy()
		end)
	end
	playerHLs = {}
end

local function makeBeacon(name, color)
	local h = Instance.new("Highlight")
	h.Name = name
	h.FillColor = color
	h.FillTransparency = 0.6
	h.OutlineColor = color
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	return h
end

local function updateVisuals(ball)
	if CFG.ballESP and ball then
		if ball ~= espBall or not espHL or not espHL.Parent then
			clearESP()
			espHL = Instance.new("Highlight")
			espHL.Name = "RssStreetBallESP"
			espHL.FillColor = Color3.fromRGB(255, 170, 0)
			espHL.FillTransparency = 0.35
			espHL.OutlineColor = Color3.fromRGB(255, 255, 255)
			espHL.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			espHL.Adornee = ball
			espHL.Parent = Workspace
			espBall = ball
		end
	elseif espHL then
		clearESP()
	end

	if CFG.goalBeacons then
		if not beaconAtk or not beaconAtk.Parent then
			beaconAtk = makeBeacon("RssStreetBeaconAtk", Color3.fromRGB(60, 255, 90))
			beaconAtk.Parent = Workspace
		end
		if not beaconOwn or not beaconOwn.Parent then
			beaconOwn = makeBeacon("RssStreetBeaconOwn", Color3.fromRGB(255, 60, 60))
			beaconOwn.Parent = Workspace
		end
		local a, o = attackGoal(), ownGoal()
		if beaconAtk.Adornee ~= a then
			beaconAtk.Adornee = a
		end
		if beaconOwn.Adornee ~= o then
			beaconOwn.Adornee = o
		end
	else
		clearBeacons()
	end

	if CFG.playerESP then
		local seen = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LP and p.Character then
				seen[p] = true
				local h = playerHLs[p]
				if not h or not h.Parent then
					h = Instance.new("Highlight")
					h.Name = "RssStreetPlayerESP"
					h.FillTransparency = 0.55
					h.DepthMode = Enum.HighlightDepthMode.Occluded
					h.Adornee = p.Character
					h.Parent = Workspace
					playerHLs[p] = h
				end
				local mate = p.TeamColor == teamColor()
				h.FillColor = mate and Color3.fromRGB(60, 255, 90) or Color3.fromRGB(255, 60, 60)
				h.OutlineColor = h.FillColor
				h.Enabled = p.TeamColor == HOME or p.TeamColor == AWAY
			end
		end
		for p, h in pairs(playerHLs) do
			if not seen[p] or not p.Character then
				pcall(function()
					h:Destroy()
				end)
				playerHLs[p] = nil
			end
		end
	else
		clearPlayerESP()
	end
end

--// auto play movement ---------------------------------------------------------
-- plain Humanoid:MoveTo walking - the same motion WASD produces, no remote involved.

local lastMoveTarget, lastMoveAt = nil, 0
local veerUntil, veerPos = 0, nil

local function moveTo(char, pos)
	local humanoid = char and char:FindFirstChild("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (humanoid and hrp and pos) then
		return
	end
	local flat = Vector3.new(pos.X, hrp.Position.Y, pos.Z)
	if not lastMoveTarget or (flat - lastMoveTarget).Magnitude > 1.5 or nowT() - lastMoveAt > 1 then
		lastMoveTarget = flat
		lastMoveAt = nowT()
		humanoid:MoveTo(flat)
	end
end

local function moveUnlocked()
	-- the game freezes players during cutscenes and celebrations; don't fight it
	return not state("Cutscene") and not state("freezeplay")
end

local function keeperAutoMove(char, ball)
	local goalPos = goalCenter(ownGoal())
	if not goalPos then
		return
	end
	-- hold the line: stand a few studs off our goal center, on the ball's line
	local dir = ball.Position - goalPos
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude > 1 then
		moveTo(char, goalPos + flat.Unit * 4)
	end
end

local function fieldAutoMove(char, ball, ballDist, iHaveBall)
	local goalPos = goalCenter(attackGoal())
	local weld = ball:FindFirstChild("playerWeld")
	local creator = ball:FindFirstChild("creator")
	local holder = creator and creator.Value

	if iHaveBall and goalPos then
		-- fresh off a crossover: cut past the defender's shoulder before resuming
		if nowT() < veerUntil and veerPos then
			moveTo(char, veerPos)
			return
		end
		-- carry: drive straight at the corner we're going to hit
		moveTo(char, bestTarget() or goalPos)
		return
	end

	if weld and holder and holder ~= LP then
		local holderTeam = entTeam(holder)
		local holderChar = entChar(holder)
		local holderHrp = holderChar and holderChar:FindFirstChild("HumanoidRootPart")
		if holderTeam ~= teamColor() then
			-- hunt the carrier
			if holderHrp then
				moveTo(char, holderHrp.Position)
			end
		elseif goalPos and holderHrp then
			-- support run: get open ahead of the pass, toward their net
			local dir = goalPos - holderHrp.Position
			local flat = Vector3.new(dir.X, 0, dir.Z)
			if flat.Magnitude > 8 then
				moveTo(char, holderHrp.Position + flat.Unit * 12)
			end
		end
		return
	end

	-- free ball or incoming pass: intercept with a small lead on its ground velocity
	local vel = ball.AssemblyLinearVelocity
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	if flatVel.Magnitude > 1 then
		local lead = math.clamp(ballDist / 24, 0.05, 0.6)
		moveTo(char, ball.Position + flatVel * lead)
	else
		moveTo(char, ball.Position)
	end
end

--// main loop ------------------------------------------------------------------

local dead = false
local lastAct = { shot = 0, pass = 0, tackle = 0, header = 0, grab = 0, dive = 0, deke = 0, team = 0 }
local lastAny = 0
local lastErrAt = 0
local lastRoundSig = nil
local lastSigAt = 0
local loopConn
local keyConn

local function predictedCross(ball, goalPos)
	-- where the ball will be when it reaches our goal depth, flat-projected
	local v = ball.AssemblyLinearVelocity
	if v.Magnitude < 1 then
		return ball.Position, v.Magnitude
	end
	local toGoal = goalPos - ball.Position
	local flat = Vector3.new(toGoal.X, 0, toGoal.Z)
	local t = flat.Magnitude / math.max(Vector3.new(v.X, 0, v.Z).Magnitude, 1)
	t = math.clamp(t, 0.05, 1.2)
	return ball.Position + v * t, v.Magnitude
end

local function step()
	if dead then
		return
	end
	local now = nowT()
	-- the round turned over: bump the generation token, so anything the old
	-- round still had scheduled is dropped instead of firing into the new one
	if now - lastSigAt >= 0.25 then
		lastSigAt = now
		local sig = roundSignature()
		if sig ~= lastRoundSig then
			lastRoundSig = sig
			roundGen = roundGen + 1
			lastAny = now
		end
	end
	local ball = findBall()
	local ballDist
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and ball then
		ballDist = (ball.Position - hrp.Position).Magnitude
	end
	updateVisuals(ball)
	if distStat and ballDist then
		pcall(function()
			distStat:Set(math.floor(ballDist))
		end)
	end
	if speedStat and ball then
		pcall(function()
			speedStat:Set(math.floor(ball.AssemblyLinearVelocity.Magnitude))
		end)
	end
	if not (ball and hrp and ballDist) then
		return
	end
	if not char:FindFirstChild("Humanoid") or char.Humanoid.Health == 0 then
		return
	end
	if not amPlaying() then
		-- the action layer is dead while we sit on the fans side - the game's
		-- own team pick puts us back on a field side when it is asked to
		if CFG.autoTeam and now - lastAct.team >= 5 then
			if joinFieldTeam() then
				lastAct.team = now
			end
		end
		return -- Fans / neutral: hands off
	end
	local keeper = amKeeper()
	local b = myBools(char)

	-- keeper: auto dive when a live shot closes on our net (dive path's own gates)
	if keeper then
		if CFG.autoPlay and moveUnlocked() then
			keeperAutoMove(char, ball)
		end
		if (CFG.autoGK or CFG.autoPlay) and ball.creator and ball.creator.Value ~= LP and not state("Penalty") then
			local goalPos = goalCenter(ownGoal())
			local v = ball.AssemblyLinearVelocity
			local speed = v.Magnitude
			local toGoal = goalPos and (goalPos - ball.Position) or Vector3.zero
			local closing = speed > 18 and toGoal.Magnitude > 1 and v:Dot(toGoal.Unit) > 0.5
			if closing and ballDist <= CFG.gkRange and now - lastAct.dive >= 1 and now - lastAny >= 0.3 then
				face(char, ball.Position) -- keepers track the ball, like real play
				local cross, _ = predictedCross(ball, goalPos or ball.Position)
				local myLateral = (hrp.Position - ball.Position):Dot(hrp.CFrame.RightVector)
				local crossLateral = (cross - ball.Position):Dot(hrp.CFrame.RightVector)
				local diff = crossLateral - myLateral
				local side
				if math.abs(diff) > 2 then
					side = diff > 0 and "RightDive" or "LeftDive"
				elseif ballDist < 8 and speed > 25 then
					side = "FrontDive"
				end
				if side and fireDive(side) then
					lastAct.dive, lastAny = now, now
				end
			end
		end
		return
	end

	-- field player: shot > header > grab > tackle > pass, one action at a time
	local iHaveBall = possessing(ball)

	if CFG.autoPlay and moveUnlocked() then
		fieldAutoMove(char, ball, ballDist, iHaveBall)
	end

	-- auto crossover: a defender presses while we carry - sprinting onto us, lunging
	-- a tackle (their own Tackling flag), or parked in our stride -> the game's own
	-- Deke action, then a cut away from the press toward their net
	if (CFG.autoCrossover or CFG.autoPlay) and iHaveBall then
		local press = findPress(hrp, CFG.crossoverRange)
		if press then
			local goalPos = goalCenter(attackGoal())
			local goalDist = goalPos and (goalPos - ball.Position).Magnitude or math.huge
			-- a committed lunge gets beaten right away; a closing sprint only while
			-- we're still driving out - once we're in range we just shoot instead
			if
				(press.lunging or goalDist > CFG.shotGoalRange)
				and booleansClean(char)
				and state("FreeKick") == false
				and not state("Penalty")
				and not state("Kickoff")
				and now - lastAct.deke >= 4 -- the game's own deke cooldown
				and now - lastAny >= 0.3
				and fireDeke(ball)
			then
				lastAct.deke, lastAny = now, now
				-- cut away from the presser's approach, weighted toward their net
				local away = Vector3.new(
					hrp.Position.X - press.hrp.Position.X,
					0,
					hrp.Position.Z - press.hrp.Position.Z
				)
				away = away.Magnitude > 0.5 and away.Unit or Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
				local goalDir
				if goalPos then
					goalDir = Vector3.new(goalPos.X - hrp.Position.X, 0, goalPos.Z - hrp.Position.Z)
					goalDir = goalDir.Magnitude > 1 and goalDir.Unit or nil
				end
				local escape = goalDir and (away + goalDir * 1.3).Unit or away
				veerPos = hrp.Position + escape * 9
				veerUntil = now + 0.8
				lastMoveTarget = nil
			end
		end
	end

	if (CFG.autoShot or CFG.autoPlay) and iHaveBall and ballDist <= CFG.shotRange then
		local goalPos = goalCenter(attackGoal())
		local goalDist = goalPos and (goalPos - ball.Position).Magnitude or math.huge
		local powerFlag = char:FindFirstChild("LocalBool")
		local charging = powerFlag and powerFlag:FindFirstChild("PowerShoot")
		if
			goalDist <= CFG.shotGoalRange
			and booleansClean(char)
			and state("FreeKick") == false
			and not state("Penalty")
			and not state("Kickoff")
			and not (charging and charging.Value == true)
			and now - lastAct.shot >= CFG.cooldown
			and now - lastAny >= 0.3
		then
			local dir = aimDir(ball)
			if dir then
				if CFG.powerMode then
					local sdir, _, _, side = solveShot(ball, bestTarget(), CFG.shotCurve, CFG.shotPower)
					sdir = sdir or aimDir(ball)
					if sdir then
						face(char, ball.Position + sdir * 10) -- LookVector feeds the power shot's 4th arg
						playShootAnim(char, sdir, 1, true)
						if firePowerShot(ball, sdir) then
							lastAct.shot, lastAny = now, now
						end
					end
				else
					local sdir, hold, curve, side = solveShot(ball, bestTarget(), CFG.shotCurve, CFG.shotPower)
					if sdir then
						face(char, ball.Position + sdir * 10) -- the kick anim reads facing
						if fireShot(ball, sdir, hold, curve, side) then
							lastAct.shot, lastAny = now, now
						end
					end
				end
			end
		end
		return
	end

	-- auto header: the game's own signals - header flag up, ball above 5.5 studs,
	-- someone else's ball, clean bools, not a restart
	if CFG.autoHeader and not iHaveBall then
		local headerFlag = b and b:FindFirstChild("Header")
		if
			headerFlag
			and headerFlag.Value == true
			and ball.Position.Y >= 5.5
			and ballDist <= 6.5
			and ball.creator
			and ball.creator.Value ~= LP
			and booleansClean(char)
			and not state("Penalty")
			and not state("Kickoff")
			and now - lastAct.header >= 3
			and now - lastAny >= 0.3
		then
			if fireHeader(ball) then
				lastAct.header, lastAny = now, now
			end
		end
	end

	-- auto grab: the game's own touch-grab for incoming passes (PassBV on the ball)
	if (CFG.autoGrab or CFG.autoPlay) and not iHaveBall then
		if
			ball:FindFirstChild("PassBV")
			and not ball:FindFirstChild("playerWeld")
			and ballDist <= 4.5
			and state("cantGrab") == false
			and not state("Penalty")
			and now - lastAct.grab >= 0.2
			and now - lastAny >= 0.1
		then
			if fireGrab(ball, ballDist) then
				lastAct.grab, lastAny = now, now
			end
		end
	end

	-- auto tackle: strip an opponent in possession, through the game's own action
	if (CFG.autoTackle or CFG.autoPlay) and not iHaveBall then
		local weld = ball:FindFirstChild("playerWeld")
		local creator = ball:FindFirstChild("creator")
		local holder = creator and creator.Value
		if
			weld
			and holder
			and holder ~= LP
			and entTeam(holder) ~= teamColor()
			and ballDist <= CFG.tackleRange
			and booleansClean(char)
			and not state("Penalty")
			and not state("Kickoff")
			and now - lastAct.tackle >= CFG.cooldown + 0.3
			and now - lastAny >= 0.3
		then
			if fireTackle() then
				lastAct.tackle, lastAny = now, now
			end
		end
		return
	end

	-- auto pass: ball at our feet and a teammate open ahead of the camera
	if CFG.autoPass and iHaveBall then
		local target, _ = findClosestTeammate()
		local thrp = target
			and (target:IsA("Player") and target.Character or target):FindFirstChild("HumanoidRootPart")
		if
			target
			and thrp
			and booleansClean(char)
			and (thrp.Position - hrp.Position).Magnitude <= CFG.passRange
			and (thrp.Position - hrp.Position).Magnitude > 5
			and now - lastAct.pass >= CFG.cooldown
			and now - lastAny >= 0.3
		then
			if firePass(ball) then
				lastAct.pass, lastAny = now, now
			end
		end
	end
end

loopConn = RunService.Heartbeat:Connect(function()
	local ok, err = pcall(step)
	if not ok and nowT() - lastErrAt > 5 then
		lastErrAt = nowT()
		warn("[RSS] loop error: " .. tostring(err))
	end
end)

--// lifecycle ------------------------------------------------------------------

local FLAGS = {
	"autoplay",
	"autoteam",
	"autoshot",
	"powershot",
	"autopass",
	"autotackle",
	"autoheader",
	"autocrossover",
	"autograb",
	"autogk",
	"ballesp",
	"goalbeacons",
	"playeresp",
}

local function panic()
	CFG.autoPlay = false
	CFG.autoTeam = false
	CFG.autoShot = false
	CFG.powerMode = false
	CFG.autoPass = false
	CFG.autoTackle = false
	CFG.autoHeader = false
	CFG.autoCrossover = false
	CFG.autoGrab = false
	CFG.autoGK = false
	CFG.ballESP = false
	CFG.goalBeacons = false
	CFG.playerESP = false
	clearESP()
	clearBeacons()
	clearPlayerESP()
	if window then
		for _, f in ipairs(FLAGS) do
			pcall(function()
				window:Set(f, false)
			end)
		end
	end
	print("[RSS] panic: hands off - everything off")
end

local window

local function shutdown()
	if dead then
		return
	end
	dead = true
	if loopConn then
		loopConn:Disconnect()
		loopConn = nil
	end
	if keyConn then
		keyConn:Disconnect()
		keyConn = nil
	end
	clearESP()
	clearBeacons()
	clearPlayerESP()
	if window then
		pcall(function()
			window:Unload()
		end)
	end
	_G.RssStreetPanel = nil
	print("[RSS] unloaded")
end

keyConn = UserInputService.InputBegan:Connect(function(i, gp)
	if gp then
		return
	end
	if i.KeyCode == Enum.KeyCode.P then
		panic()
	end
end)

--// UI -------------------------------------------------------------------------

local Rayfield
pcall(function()
	Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)

local function buildUI()
	if not Rayfield then
		return
	end
	local w = Rayfield:CreateWindow({
		Name = "RSS // STREET",
		LoadingTitle = "RSS STREET",
		LoadingSubtitle = "neon curve engine - shots, passing, defense, ESP",
		KeySystem = false,
	})
	window = w
	pcall(function()
		w:ChangeTheme({
			WindowColor = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 8, 22)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(26, 14, 52)),
			},
			ShadowColor = Color3.fromRGB(4, 2, 12),
			CornerRoundness = UDim.new(0, 16),
			ElementCornerRadius = UDim.new(0, 10),
			PillCornerRadius = UDim.new(1, 0),
			ElementGradient = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(22, 16, 44)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 20, 58)),
			},
			ElementStrokeGradient = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(94, 68, 190)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 229, 255)),
			},
			ElementStroke = Color3.fromRGB(70, 50, 140),
			ElementStrokeHover = Color3.fromRGB(0, 229, 255),
			AccentColor = Color3.fromRGB(0, 229, 255),
			AccentStroke = Color3.fromRGB(122, 252, 255),
			AccentGlow = 0.55,
			SliderProgress = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 46, 156)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 229, 255)),
			},
			SliderBackground = Color3.fromRGB(26, 18, 50),
			SliderBackgroundHover = Color3.fromRGB(36, 26, 70),
			SliderHandle = Color3.fromRGB(255, 255, 255),
			SliderStroke = Color3.fromRGB(122, 252, 255),
			ToggleTrack = Color3.fromRGB(14, 10, 30),
			ToggleTrackTransparency = 0.75,
			ToggleKnobOff = Color3.fromRGB(130, 120, 170),
			ContentColor = Color3.fromRGB(236, 232, 255),
			TitlingColor = Color3.fromRGB(255, 255, 255),
			ElementTextHoverColor = Color3.fromRGB(0, 229, 255),
			StatBackground = Color3.fromRGB(16, 12, 34),
			TabBackground = ColorSequence.new(Color3.fromRGB(28, 20, 56), Color3.fromRGB(18, 12, 38)),
			TabStroke = ColorSequence.new(Color3.fromRGB(0, 229, 255), Color3.fromRGB(120, 60, 220)),
			TabColor = Color3.fromRGB(240, 238, 255),
			FieldGlow = Color3.fromRGB(0, 229, 255),
			DropdownHighlight = Color3.fromRGB(0, 229, 255),
		})
	end)
	local play = w:CreateTab({ name = "◈ PLAY" })
	local view = w:CreateTab({ name = "◉ VIEW" })
	local sys = w:CreateTab({ name = "⚙ SYS" })

	play:CreateToggle({
		name = "auto play",
		description = "full autopilot - chases loose balls and incoming passes, carries the ball at their net, beats pressing defenders with the equipped dribble skill, and lets the shot fly in range, hunts opposing carriers, makes support runs off teammates, holds the goal line when you're keeper - plain walking plus the game's own remotes, nothing else",
		flag = "autoplay",
		value = CFG.autoPlay,
		callback = function(v)
			CFG.autoPlay = v
			lastMoveTarget = nil
		end,
	})
	play:CreateToggle({
		name = "auto team pick",
		description = "when the game parks you on the fans side - between rounds, or after a goal - pick yourself back onto a field side through the game's own team remote, with the same side limit the game's own role select uses. off by default: it never takes a slot you did not ask for",
		flag = "autoteam",
		value = CFG.autoTeam,
		callback = function(v)
			CFG.autoTeam = v
		end,
	})
	play:CreateToggle({
		name = "auto shot",
		description = "ball at your feet -> aim at the corner of their net and let it fly through the game's own ShootTheBaII remote, the exact charged form its controller sends - with its own kick animation, your power setting behind it and your curve bending around the keeper",
		flag = "autoshot",
		value = CFG.autoShot,
		callback = function(v)
			CFG.autoShot = v
		end,
	})
	play:CreateToggle({
		name = "power shot mode",
		description = "auto shot uses the controller's fully charged powershot form (power 1) instead of the quick tap",
		flag = "powershot",
		value = CFG.powerMode,
		callback = function(v)
			CFG.powerMode = v
		end,
	})
	play:CreateSlider({
		name = "shot range",
		description = "studs from you to the ball before the auto shot fires - keep it inside a real stride",
		flag = "shotrange",
		range = { 3, 15 },
		increment = 0.5,
		value = CFG.shotRange,
		suffix = " st",
		callback = function(v)
			CFG.shotRange = v
		end,
	})
	play:CreateSlider({
		name = "shot power",
		description = "charge behind the auto shot, 1-100 - the hold time its controller sends; 85 is its quick tap, 100 the full 1 second charge",
		flag = "shotpower",
		range = { 1, 100 },
		increment = 1,
		value = CFG.shotPower,
		suffix = " pwr",
		callback = function(v)
			CFG.shotPower = v
		end,
	})
	play:CreateToggle({
		name = "shot curve",
		description = "the game's own bend: the shot is sent with the curve side the game expects ('Left'/'Right' in the shoot remote) so the server curves it around the keeper - it needs a charged shot, so keep the power at 70 or more",
		flag = "shotcurve",
		value = CFG.shotCurve == 1,
		callback = function(v)
			CFG.shotCurve = v and 1 or 0
		end,
	})
	play:CreateSlider({
		name = "curve compensation",
		description = "studs the aim leans back by, so a bent shot still lands on the corner the panel aimed at - 0 leaves the raw bend, raise it if the shot is sailing wide of the corner",
		flag = "curvecomp",
		range = { 0, 12 },
		increment = 0.5,
		value = CFG.curveComp,
		suffix = " st",
		callback = function(v)
			CFG.curveComp = v
		end,
	})
	play:CreateSlider({
		name = "shot release distance",
		description = "max ball-to-net distance before the shot lets fly - the carry drives at the net until inside this",
		flag = "shotgoalrange",
		range = { 20, 140 },
		increment = 5,
		value = CFG.shotGoalRange,
		suffix = " st",
		callback = function(v)
			CFG.shotGoalRange = v
		end,
	})
	play:CreateSlider({
		name = "action cooldown",
		description = "seconds between same-type actions, keeps the rhythm human",
		flag = "cooldown",
		range = { 0.3, 3 },
		increment = 0.1,
		value = CFG.cooldown,
		suffix = " s",
		callback = function(v)
			CFG.cooldown = v
		end,
	})

	play:CreateSection({ name = "SKILLS" })
	play:CreateToggle({
		name = "auto crossover",
		description = "carrying the ball and a defender presses - sprinting onto you, lunging a tackle, or parked in your stride -> the game's own Deke action (your equipped dribble skill) then a cut away from the press toward their net - the exact Action the controller's Q-key sends, same 4 second cooldown",
		flag = "autocrossover",
		value = CFG.autoCrossover,
		callback = function(v)
			CFG.autoCrossover = v
		end,
	})
	play:CreateSlider({
		name = "crossover range",
		description = "studs to a pressing defender before the crossover triggers",
		flag = "crossoverrange",
		range = { 4, 15 },
		increment = 0.5,
		value = CFG.crossoverRange,
		suffix = " st",
		callback = function(v)
			CFG.crossoverRange = v
		end,
	})

	play:CreateSection({ name = "TEAM PLAY" })
	play:CreateToggle({
		name = "auto pass",
		description = "ball at your feet and a teammate open ahead of the camera -> the game's own Pass remote with the teammate its FindClosestPlayer picks",
		flag = "autopass",
		value = CFG.autoPass,
		callback = function(v)
			CFG.autoPass = v
		end,
	})
	play:CreateSlider({
		name = "pass range",
		description = "max teammate distance for a pass",
		flag = "passrange",
		range = { 10, 120 },
		increment = 5,
		value = CFG.passRange,
		suffix = " st",
		callback = function(v)
			CFG.passRange = v
		end,
	})
	play:CreateToggle({
		name = "auto header",
		description = "the game's own header signals line up (header flag + ball above 5.5 studs) -> Header, or BicycleKick on an incoming pass, exactly like the controller's spacebar path",
		flag = "autoheader",
		value = CFG.autoHeader,
		callback = function(v)
			CFG.autoHeader = v
		end,
	})
	play:CreateToggle({
		name = "auto grab",
		description = "a pass is coming in (PassBV on the ball) and it's within reach -> pick it up through the game's own attribute grab remote, GrabTick and all",
		flag = "autograb",
		value = CFG.autoGrab,
		callback = function(v)
			CFG.autoGrab = v
		end,
	})

	play:CreateSection({ name = "DEFENSE" })
	play:CreateToggle({
		name = "auto tackle",
		description = "an opponent carries the ball inside range -> strip it with the game's own tackle action (the real TackIe action, not the decoy remote)",
		flag = "autotackle",
		value = CFG.autoTackle,
		callback = function(v)
			CFG.autoTackle = v
		end,
	})
	play:CreateSlider({
		name = "tackle range",
		description = "studs to the ball before tackles trigger",
		flag = "tacklerange",
		range = { 4, 15 },
		increment = 0.5,
		value = CFG.tackleRange,
		suffix = " st",
		callback = function(v)
			CFG.tackleRange = v
		end,
	})
	play:CreateToggle({
		name = "auto GK dive",
		description = "you're in goal and a shot closes on the net -> read its crossing point and dive left / right / front through the game's own dive action, with the same 35-stud lunge the game applies",
		flag = "autogk",
		value = CFG.autoGK,
		callback = function(v)
			CFG.autoGK = v
		end,
	})
	play:CreateSlider({
		name = "GK range",
		description = "studs to the ball before dives trigger",
		flag = "gkrange",
		range = { 6, 30 },
		increment = 1,
		value = CFG.gkRange,
		suffix = " st",
		callback = function(v)
			CFG.gkRange = v
		end,
	})

	view:CreateToggle({
		name = "ball ESP",
		description = "orange glow on the live ball - re-locks the moment it respawns",
		flag = "ballesp",
		value = CFG.ballESP,
		callback = function(v)
			CFG.ballESP = v
			if not v then
				clearESP()
			end
		end,
	})
	view:CreateToggle({
		name = "goal beacons",
		description = "green glow on the net you attack, red on your own",
		flag = "goalbeacons",
		value = CFG.goalBeacons,
		callback = function(v)
			CFG.goalBeacons = v
			if not v then
				clearBeacons()
			end
		end,
	})
	view:CreateToggle({
		name = "player ESP",
		description = "teammates green, opponents red",
		flag = "playeresp",
		value = CFG.playerESP,
		callback = function(v)
			CFG.playerESP = v
			if not v then
				clearPlayerESP()
			end
		end,
	})
	distStat = view:CreateStat({ name = "ball distance", value = 0, suffix = " st" })
	speedStat = view:CreateStat({ name = "ball speed", value = 0, suffix = " sps" })

	sys:CreateButton({ name = "panic (P)", description = "everything off, hands back to you", callback = panic })
	sys:CreateButton({ name = "unload panel", description = "tear everything down", callback = shutdown })
end

buildUI()

_G.RssStreetPanel = {
	cfg = CFG,
	window = window,
	stop = shutdown,
	panic = panic,
	ball = findBall,
	attackGoal = attackGoal,
	ownGoal = ownGoal,
	keeper = amKeeper,
	playing = amPlaying,
	bestTarget = bestTarget,
	fireShot = fireShot,
	solveShot = solveShot,
	firePowerShot = firePowerShot,
	firePass = firePass,
	fireTackle = fireTackle,
	fireHeader = fireHeader,
	fireDive = fireDive,
	fireGrab = fireGrab,
	fireDeke = fireDeke,
	defenderAhead = defenderAhead,
	findPress = findPress,
	joinFieldTeam = joinFieldTeam,
	now = nowT,
	curveState = function()
		return {
			gen = roundGen,
			signature = lastRoundSig,
			chargeGate = CURVE_CHARGE_GATE,
			curve = CFG.shotCurve,
			compensation = CFG.curveComp,
			lastShot = lastShot,
		}
	end,
	state = function()
		local ball = findBall()
		local char = LP.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		return {
			place = game.PlaceId,
			team = tostring(teamColor()),
			playing = amPlaying(),
			keeper = amKeeper(),
			ball = ball and ball.Name .. "@" .. tostring(ball.Position) or nil,
			ballDist = ball and hrp and (ball.Position - hrp.Position).Magnitude or nil,
			possession = ball and possessing(ball) or false,
			autoPlay = CFG.autoPlay,
			autoCrossover = CFG.autoCrossover,
			shotPower = CFG.shotPower,
			shotCurve = CFG.shotCurve,
			attackGoal = goalCenter(attackGoal()) and tostring(goalCenter(attackGoal())) or nil,
			paths = remotePaths() ~= nil,
		}
	end,
}

print("[RSS] panel loaded - auto play, curve shots, pass, tackle, header, GK dive, grab, crossover, ESP | paths "
	.. (remotePaths() and "ok" or "missing")
	.. (amPlaying() and (amKeeper() and " | keeper" or " | field") or " | spectating (join Home/Away)"))
end

--// embedded suite: mma  (from mma.luau) =========================
Hub.SUITE.mma = function()
-- Realistic Ragdoll MMA | max-mode fight panel
-- place 124780003623150 | Rayfield Gen2 | replace-not-stack via _G.RagdollMmaPanel
--
-- AUTO | full match is one switch: every fight and ground auto is treated as
-- on. off, the individual toggles go back to being the only thing that runs.
--
-- RAGE | the same client-owned simulation is also the cheat surface. power scales
-- every strike the game resolves, koHP is the head-health threshold its own KO
-- branch reads, stamina and stun are fields the sim writes every frame. the tab
-- edits those values live: damage multiplier, one-punch threshold, super armour,
-- endless stamina, faster hands, a frozen opponent, plus instant knockout and
-- instant win buttons that call the match's own knockdown and stoppage paths.
--
-- this game is a client-authoritative boxing sim: damage, contact and knockdowns are
-- all resolved on the client from its own Match/Fighter state. so there is nothing to
-- spoof over the wire -- the panel drives the game's own methods:
--   Match:playerStrike(move)        strike, using Match:aim() (camera raycast -> zone)
--   Match:playerShoot()             takedown shot (0.3s later resolveContact -> drive)
--   Match:sprawlPress()             clinch press, works as attacker and defender
--   Match:groundMash()              ground mash / sub escape / sub finish
--   Match:groundStrikeInput(move)   ground and pound (jab/cross/lhook/rhook)
--   Match:groundOption(index)        index into Match:groundMenu(player), 1-based
--   Match:debugMove                 camera-relative movement hook read by readMovement
--   Touch.block                     guard state read by readMovement
--   match.camYaw / camPitch         the game's own aim state (also turns the fighter)
--
-- STYLE | the collectible styles live in the server profile and the fight sim
-- reads the equipped slot on both clients. this panel never grants one:
-- "equip best owned" / "equip selected" call the same Styles equip remote the
-- game's style menu uses, and the change lands on the next fight.
--
-- swapping the live Fighter's style object is intentionally NOT offered. the
-- game's AntiCheat snapshots player.fstyle at the bell; a live edit is reverted
-- within 0.5s and the fight is nerfed to 30% power / 40% speed for the rest of
-- the bout. in PvP the opponent's client also throws your strikes with the
-- style id the server gave it, so a local edit cannot change the damage another
-- player takes. only the server equip does that.
--
-- nothing here invents remotes, writes career data, or fires fake server events.

local prev = _G.RagdollMmaPanel
local CFG = (prev and prev.cfg) or {}
for k, v in pairs({
	autoMaster = false,
	retreatStamina = 24,
	finishPush = true,
	autoFight = false,
	autoAim = true,
	aimZone = "head",
	autoBlock = true,
	autoCounter = true,
	autoTakedown = false,
	takedownStamina = 40,
	autoGround = true,
	autoSub = true,
	autoSprawl = true,
	pressRate = 12,
	autoSkip = true,
	autoQueue = false,
	autoContinue = true,
	queueDelay = 6,
	autoBest = false,
	autoExec = false,
	aggro = 60,
	staminaFloor = 20,
	strikeStyle = "smart",
	safeKicks = true,
	adaptive = true,
	acBypass = true,
	fightStyle = "best owned",
	spinCount = 10,
	spinStopRare = true,
	rageMode = false,
	rageBoost = false,
	rageDamage = 8,
	rageOnePunch = false,
	rageGod = false,
	rageStamina = false,
	rageSpeed = false,
	rageSpeedValue = 1.6,
	rageFreeze = false,
	hud = true,
	hudBars = true,
	hudNames = true,
	hudAlerts = true,
	logSize = 6,
}) do
	if CFG[k] == nil then CFG[k] = v end
end
-- settings survive a teleport: the loader re-runs the panel on the next join, so
-- the switches people actually keep are written next to the script and read
-- back on load. every executor names its folder differently, so it is
-- best-effort and never fatal.
local CFG_FILE = "slimhub-mma.cfg"

local function loadCfg()
	if not (isfile and readfile and isfile(CFG_FILE)) then return end
	local ok, data = pcall(readfile, CFG_FILE)
	if not ok or type(data) ~= "string" then return end
	for line in string.gmatch(data, "[^\r\n]+") do
		local k, v = string.match(line, "^([%w_]+)=(.*)$")
		if k and CFG[k] ~= nil then
			if v == "true" then
				CFG[k] = true
			elseif v == "false" then
				CFG[k] = false
			elseif tonumber(v) then
				CFG[k] = tonumber(v)
			else
				CFG[k] = v
			end
		end
	end
end

local savedCfg = ""
local function saveCfg()
	if not writefile then return end
	local parts = {}
	for k, v in pairs(CFG) do
		local t = type(v)
		if t == "boolean" or t == "number" or t == "string" then
			table.insert(parts, k .. "=" .. tostring(v))
		end
	end
	table.sort(parts)
	local blob = table.concat(parts, "\n")
	if blob == savedCfg then return end
	savedCfg = blob
	pcall(writefile, CFG_FILE, blob)
end

-- a panel replacing an older build still has to pick up the saved file: the old
-- cfg has no autoQueue key, so treat that as a fresh load instead of letting the
-- in-memory table overwrite the file with defaults.
if not prev or (type(prev.cfg) == "table" and prev.cfg.autoQueue == nil) then
	pcall(loadCfg)
end

if prev and prev.stop then
	pcall(prev.stop)
end
_G.RagdollMmaPanel = { cfg = CFG }

-- master switch: with autoMaster on, every auto below behaves as if its own
-- toggle were on, so one switch plays a whole match. the individual toggles
-- keep their own state and take over again the moment the master goes off.
local function autoOn(key)
	if CFG.autoMaster then return true end
	return CFG[key] == true
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local ROFC = ReplicatedStorage:FindFirstChild("ROFC")
if not ROFC then
	-- auto-exec loads us the moment the join starts, often before ROFC has
	-- replicated. sit on it instead of bailing with a half-built panel.
	local deadline = os.clock() + 40
	while os.clock() < deadline do
		task.wait(0.5)
		ROFC = ReplicatedStorage:FindFirstChild("ROFC")
		if ROFC then break end
	end
end
if not ROFC then
	warn("[MMA] ROFC modules not found in place " .. tostring(game.PlaceId))
	_G.RagdollMmaPanel = { cfg = CFG }
	return
end

local function tryRequire(name)
	local m = ROFC:FindFirstChild(name)
	if not m then return nil end
	local ok, mod = pcall(require, m)
	if ok then return mod end
	return nil
end

local Match, Touch, Config, Util, Cinema
local modDeadline = os.clock() + 20
repeat
	Match = tryRequire("Match")
	Touch = tryRequire("Touch")
	Config = tryRequire("Config")
	Util = tryRequire("Util")
	Cinema = tryRequire("Cinema")
	if Match and Touch and Config and Util then break end
	task.wait(0.5)
until os.clock() > modDeadline

if not (Match and Touch and Config and Util) then
	warn("[MMA] required modules missing (Match/Touch/Config/Util)")
	_G.RagdollMmaPanel = { cfg = CFG }
	return
end

-- styles are optional: a missing module only disables the STYLE tab's actions.
local Styles = tryRequire("Styles")

local Remotes = ReplicatedStorage:FindFirstChild("ROFCRemotes")
local GetCareer = Remotes and Remotes:FindFirstChild("GetCareer")
local GetProfile = Remotes and Remotes:FindFirstChild("GetProfile")
local StylesRemote = Remotes and Remotes:FindFirstChild("Styles")

local dead = false
local ui = {}
local status = "idle  |  no match"
local match = nil
local nextScan = 0
local lastState = {}

local function now()
	return os.clock()
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

--// opponent read / adaptive counter -------------------------------------------
-- the game exposes the opponent's live fighter table, so its habits can be read
-- without guessing: strikes actually thrown, guard time, shot attempts, distance
-- and whether it is walking in or backing out. the counter only shifts the same
-- settings the FIGHT tab uses; nothing here writes the server profile.

local TUNE = {}
local READ = {
	t0 = 0, time = 0, punches = 0, kicks = 0, knees = 0, shots = 0,
	blockT = 0, closeT = 0, farT = 0, fwdT = 0, backT = 0, moveT = 0,
	lastSeen = setmetatable({}, { __mode = "k" }),
	lastShot = false, lastT = 0, lastClass = 0,
	lastOPos = nil, lastPPos = nil, incoming = false,
	read = "unknown", candidate = "unknown", candidateT = 0,
	counter = "", style = "", prior = "", confidence = 0, changedAt = 0,
}

local function clearTune()
	for k in pairs(TUNE) do TUNE[k] = nil end
end

local function resetAdapt()
	clearTune()
	local t = now()
	READ.t0 = t
	READ.time = 0
	READ.punches = 0
	READ.kicks = 0
	READ.knees = 0
	READ.shots = 0
	READ.blockT = 0
	READ.closeT = 0
	READ.farT = 0
	READ.fwdT = 0
	READ.backT = 0
	READ.moveT = 0
	READ.lastSeen = setmetatable({}, { __mode = "k" })
	READ.lastShot = false
	READ.lastT = t
	READ.lastClass = 0
	READ.lastOPos = nil
	READ.lastPPos = nil
	READ.incoming = false
	READ.read = "unknown"
	READ.candidate = "unknown"
	READ.candidateT = 0
	READ.counter = ""
	READ.style = ""
	READ.prior = ""
	READ.confidence = 0
	READ.changedAt = 0
end

local function fmtTime(t)
	if Util and Util.formatTime then
		local ok, s = pcall(Util.formatTime, t)
		if ok then return s end
	end
	return string.format("%d:%02d", math.max(0, math.floor(t)) // 60, math.max(0, math.floor(t)) % 60)
end

--// session stats ---------------------------------------------------------------

local stats = _G.RagdollMmaStats or {}
_G.RagdollMmaStats = stats
for k, v in pairs({
	fights = 0, wins = 0, losses = 0, koWins = 0, koLosses = 0,
	strikes = 0, landed = 0, damage = 0, takedowns = 0, tdConceded = 0, knockdowns = 0, subs = 0,
}) do
	if stats[k] == nil then stats[k] = v end
end

local log = {}
local function pushLog(text)
	table.insert(log, 1, os.date("%H:%M:%S") .. "  " .. text)
	while #log > math.max(3, CFG.logSize) do
		table.remove(log)
	end
end

local function resetRead()
	resetAdapt()
	pushLog("opponent read reset")
end

local notify = function(text)
	print("[MMA] " .. tostring(text))
end

--// anti-cheat shield --------------------------------------------------------------
-- place version 107 added ReplicatedStorage.ROFC.AntiCheat. the client only
-- attaches it to ranked PvP bouts: at the bell it snapshots player.power,
-- speedMul, strikeSpeed, chin, toughness and fstyle.mods, then every 0.5 s it
-- restores anything that moved and cuts that fighter to 0.4x speed and 0.3x
-- power for the rest of the fight. the auto fighter, safe kicks and the read
-- never write those fields, so they are unaffected; RAGE is. this shield keeps
-- the checker off matches that start while it is on, and strips it from a match
-- already running. client-side only: a server-side check can still reject or
-- nerf a boosted fighter.

local AntiCheat = tryRequire("AntiCheat")
local acAttachOriginal = AntiCheat and AntiCheat.attach
local acShieldOn = false
local acKilled = 0
local acChecked = setmetatable({}, { __mode = "k" })

-- Real's debug.getupvalue returns (value, name), while stock Luau returns
-- (name, value). accept either shape so the snapshot lookup works in both.
local function acUpvalue(f, i)
	local ok, a, b = pcall(debug.getupvalue, f, i)
	if not ok then return nil end
	if type(a) == "string" and b ~= nil then return a, b end
	return (type(b) == "string" and b or nil), a
end

local function acFindSnapshot(f, depth)
	if type(f) ~= "function" or depth < 0 then return nil end
	if not (debug and debug.getupvalue) then return nil end
	for i = 1, 32 do
		local _, v = acUpvalue(f, i)
		if type(v) == "table" and type(v.refs) == "table" and type(v.power) == "number" and type(v.speedMul) == "number" then
			return v
		end
		if depth > 0 and type(v) == "function" then
			local sub = acFindSnapshot(v, depth - 1)
			if sub then return sub end
		end
	end
	return nil
end

local function acKillHeartbeat(m)
	if not (getconnections and debug and debug.info) then return 0, nil end
	local ok, conns = pcall(getconnections, RunService.Heartbeat)
	if not ok or type(conns) ~= "table" then return 0, nil end
	local n, snap = 0, nil
	for _, c in ipairs(conns) do
		local f = c.Function
		local src = nil
		if f then
			local ok2, s = pcall(debug.info, f, "s")
			if ok2 then src = tostring(s) end
		end
		if src and string.find(src, "AntiCheat", 1, true) then
			local bound = m == nil or not debug.getupvalue
			if not bound then
				for i = 1, 24 do
					local _, v = acUpvalue(f, i)
					if v == m then
						bound = true
						break
					end
				end
			end
			if bound then
				snap = snap or acFindSnapshot(f, 2)
				pcall(function() c:Disconnect() end)
				n = n + 1
			end
		end
	end
	return n, snap
end

local function acCleanMatch(m)
	if not m or acChecked[m] then return false end
	acChecked[m] = true
	-- read the checker's own nerf snapshot before the wrappers go away. its
	-- power/speedMul are the values it wrote (base * 0.3 / 0.4), so dividing
	-- them recovers the real base even when the old panel already restored the
	-- live fighter fields and a blind divide would inflate the fighter.
	local snap = acFindSnapshot(rawget(m, "netSend"), 2)
		or acFindSnapshot(rawget(m, "onNet"), 2)
		or acFindSnapshot(rawget(m, "netDriveRemote"), 2)
	local killed, hs = acKillHeartbeat(m)
	acKilled = acKilled + killed
	snap = snap or hs
	local cleaned = killed > 0
	for _, key in ipairs({ "netSend", "onNet", "netDriveRemote" }) do
		local raw = rawget(m, key)
		if raw then
			local ok, src = pcall(debug.info, raw, "s")
			if ok and string.find(tostring(src), "AntiCheat", 1, true) then
				rawset(m, key, nil)
				cleaned = true
			end
		end
	end
	if m.acMe and m.player then
		local p = m.player
		if snap then
			p.power = snap.power / 0.3
			p.speedMul = snap.speedMul / 0.4
		else
			p.power = (tonumber(p.power) or 1) / 0.3
			p.speedMul = (tonumber(p.speedMul) or 1) / 0.4
		end
		m.acMe = nil
		cleaned = true
	end
	if m.acTold then
		m.acTold = nil
		cleaned = true
	end
	return cleaned
end

local function acEnsure()
	if not AntiCheat then
		AntiCheat = tryRequire("AntiCheat")
		acAttachOriginal = AntiCheat and AntiCheat.attach or nil
	end
	return AntiCheat ~= nil and type(acAttachOriginal) == "function"
end

local function setAcShield(on)
	CFG.acBypass = on and true or false
	if on then
		if not acEnsure() then
			acShieldOn = false
			return false, "anti-cheat module not found"
		end
		AntiCheat.attach = function() end
		acShieldOn = true
		if match then acCleanMatch(match) end
		pushLog("anti-cheat shield on  |  ranked pvp checker skipped")
	else
		if AntiCheat and type(acAttachOriginal) == "function" then
			AntiCheat.attach = acAttachOriginal
			pushLog("anti-cheat shield off  |  next match is checked")
		end
		acShieldOn = false
	end
	return true
end

local function acStatusText()
	if not AntiCheat or type(acAttachOriginal) ~= "function" then return "checker not present  |  shield idle" end
	if acShieldOn then return "checker found  |  shield on  |  new ranked matches skip it" end
	return "checker found  |  shield off  |  ranked matches use it"
end

pcall(setAcShield, CFG.acBypass)

--// styles ----------------------------------------------------------------------
-- ROFC.Styles is the read-only catalogue; ROFCRemotes.Styles is the server-owned
-- profile (get/equip/spin). owned styles are ranked by the game's own letter
-- grades, so "best" means the highest total, not a value this panel invents.

local GRADE_SCORE = {
	["SS+"] = 14, SS = 13, ["S+"] = 12, S = 11,
	["A+"] = 10, A = 9, ["B+"] = 8, B = 7,
	["C+"] = 6, C = 5, ["D+"] = 4, D = 3,
	["E+"] = 2, E = 1, F = 0,
}
local GRADE_KEYS = {
	"STRIKING", "POWER", "SPEED", "DEFENCE", "KICKS",
	"WRESTLING", "TD DEFENCE", "GROUND", "SUBS", "CHIN",
}
local RARITY_RANK = {
	SECRET = 6, GODLY = 5, UNIQUE = 4, ADMIN = 3,
	LEGENDARY = 2, RARE = 1, BYFL = 0,
}

local styleState = nil
local styleStateAt = 0
local styleError = nil
local styleBusy = false
local spinBusy = false
local spinStop = false
local styleOptionIds = {}
local stylesTriedAt = 0

local function stylesModule()
	if Styles then return Styles end
	if now() - stylesTriedAt < 5 then return nil end
	stylesTriedAt = now()
	Styles = tryRequire("Styles")
	return Styles
end

local function stylesRemoteFn()
	if StylesRemote and StylesRemote.Parent then return StylesRemote end
	local r = ReplicatedStorage:FindFirstChild("ROFCRemotes")
	StylesRemote = r and r:FindFirstChild("Styles") or nil
	return StylesRemote
end

local function styleScore(style)
	local grades = type(style) == "table" and style.grades or nil
	if type(grades) ~= "table" then return 0 end
	local total = 0
	for _, key in ipairs(GRADE_KEYS) do
		local grade = string.upper(tostring(grades[key] or ""))
		total = total + (GRADE_SCORE[grade] or 0)
	end
	return total
end

local function styleById(id)
	if type(id) ~= "string" then return nil end
	local mod = stylesModule()
	if not mod then return nil end
	local style = mod.BY_ID and mod.BY_ID[id]
	if style then return style end
	if type(mod.get) == "function" then
		local ok, got = pcall(mod.get, id)
		if ok then return got end
	end
	return nil
end

local function refreshStyleState()
	local remote = stylesRemoteFn()
	if not remote then
		styleError = "Styles remote not found"
		return nil
	end
	local ok, res = pcall(function() return remote:InvokeServer("get") end)
	if ok and type(res) == "table" and type(res.state) == "table" then
		styleState = res.state
		styleStateAt = now()
		styleError = nil
		return styleState
	end
	styleError = ok and "Styles get returned no state" or tostring(res)
	return nil
end

local function ownedStyles()
	local state = styleState
	if type(state) ~= "table" then return {} end
	local slots = type(state.sl) == "table" and state.sl or {}
	local count = math.max(tonumber(state.n) or 0, #slots)
	local out = {}
	for i = 1, count do
		local id = slots[i]
		if type(id) == "string" and id ~= "" then
			local style = styleById(id)
			out[#out + 1] = {
				id = id,
				index = i,
				name = (style and style.name) or id,
				rarity = (style and style.rarity) or "?",
				score = styleScore(style),
				style = style,
			}
		end
	end
	table.sort(out, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		local ar = RARITY_RANK[a.rarity] or 0
		local br = RARITY_RANK[b.rarity] or 0
		if ar ~= br then return ar > br end
		return a.index < b.index
	end)
	return out
end

local function equippedStyle()
	local state = styleState
	if type(state) ~= "table" then return nil, nil end
	local slots = type(state.sl) == "table" and state.sl or {}
	local index = tonumber(state.eq) or 1
	local id = slots[index]
	if type(id) ~= "string" or id == "" then return nil, nil end
	return styleById(id), id
end

local function buildStyleOptions()
	styleOptionIds = {}
	local options = { "best owned" }
	if type(styleState) ~= "table" then return options end
	for _, row in ipairs(ownedStyles()) do
		local label = row.name .. "  (" .. row.id .. ")"
		if styleOptionIds[label] then
			label = row.name .. "  [slot " .. tostring(row.index) .. "]"
		end
		styleOptionIds[label] = row.id
		options[#options + 1] = label
	end
	return options
end

local function styleEntryForChoice(choice)
	local list = ownedStyles()
	choice = tostring(choice or "best owned")
	if choice == "best owned" then return list[1] end
	local wantId = styleOptionIds[choice] or choice
	for _, row in ipairs(list) do
		if row.id == wantId
			or string.upper(row.name) == string.upper(choice)
			or string.upper(row.id) == string.upper(choice)
		then
			return row
		end
	end
	return nil
end

local function styleSummary()
	local list = ownedStyles()
	local eq, eqId = equippedStyle()
	local bits = {}
	if type(styleState) == "table" then
		bits[#bits + 1] = tostring(#list) .. " owned"
		bits[#bits + 1] = "equipped " .. tostring(eq and eq.name or eqId or "none")
		if list[1] then
			bits[#bits + 1] = "best " .. list[1].name .. " (" .. list[1].rarity .. ")"
		end
		local mods = eq and eq.mods
		if type(mods) == "table" then
			bits[#bits + 1] = string.format(
				"punch x%.2f  jab x%.2f  kick x%.2f  taken x%.2f",
				tonumber(mods.punch) or 1,
				tonumber(mods.jab) or 1,
				tonumber(mods.kick) or 1,
				tonumber(mods.taken) or 1
			)
		end
	else
		bits[#bits + 1] = styleError or "press scan styles"
	end
	return table.concat(bits, "  |  ")
end

local function spinCounts()
	local state = styleState
	if type(state) ~= "table" then return 0, 0, 0 end
	return tonumber(state.sp) or 0, tonumber(state.lk) or 0, tonumber(state.p) or 0
end

local function spinSummary()
	local sp, lk, pity = spinCounts()
	local bits = {
		tostring(sp) .. " normal",
		tostring(lk) .. " lucky",
		"pity " .. tostring(pity),
	}
	local mod = stylesModule()
	local odds = mod and mod.ODDS
	local lucky = type(odds) == "table" and odds.lucky or nil
	if type(lucky) == "table" then
		bits[#bits + 1] = string.format(
			"lucky odds  rare %.1f  leg %.1f  god %.1f  sec %.1f",
			tonumber(lucky.RARE) or 0,
			tonumber(lucky.LEGENDARY) or 0,
			tonumber(lucky.GODLY) or 0,
			tonumber(lucky.SECRET) or 0
		)
	end
	return table.concat(bits, "  |  ")
end

local function updateStyleCard()
	if ui.styleCard then
		pcall(function()
			local list = ownedStyles()
			ui.styleCard:SetTitle("styles  |  " .. (type(styleState) == "table" and (tostring(#list) .. " owned") or "not loaded"))
			ui.styleCard:Set(styleSummary())
		end)
	end
	if ui.spinCard then
		pcall(function()
			local sp, lk = spinCounts()
			ui.spinCard:SetTitle(string.format("spins  |  %d normal  |  %d lucky", sp, lk))
			ui.spinCard:Set(spinSummary())
		end)
	end
end

local function refreshStyleDropdown()
	if not ui.styleDrop then return end
	local options = buildStyleOptions()
	local want = tostring(CFG.fightStyle or "best owned")
	local found = want == "best owned"
	if not found then
		for label, id in pairs(styleOptionIds) do
			if label == want
				or id == want
				or string.upper(label) == string.upper(want)
				or string.upper(id) == string.upper(want)
			then
				want = label
				found = true
				break
			end
		end
	end
	if not found then want = "best owned" end
	CFG.fightStyle = want
	pcall(function() ui.styleDrop:Refresh(options) end)
	pcall(function() ui.styleDrop:Set(want, true) end)
end

-- the game's style menu equips by slot index; the style id is kept as a
-- fallback so a server that keys the same remote by id still accepts the call.
local function equipStyleEntry(entry, silent)
	if type(entry) ~= "table" then
		if not silent then notify("that style is not owned by this profile") end
		return false, "not owned"
	end
	local remote = stylesRemoteFn()
	if not remote then
		if not silent then notify("Styles remote not found") end
		return false, "no remote"
	end
	local ok, res = pcall(function() return remote:InvokeServer("equip", entry.index) end)
	if not ok then
		ok, res = pcall(function() return remote:InvokeServer("equip", entry.id) end)
	end
	if not ok then
		styleError = tostring(res)
		if not silent then notify("equip failed: " .. tostring(res)) end
		updateStyleCard()
		return false, styleError
	end
	local hadState = type(res) == "table" and type(res.state) == "table"
	if hadState then
		styleState = res.state
		styleStateAt = now()
		styleError = nil
	elseif type(res) == "table" and (res.err or res.need) then
		styleError = tostring(res.err or res.need)
		if not silent then notify("equip refused: " .. styleError) end
		updateStyleCard()
		return false, styleError
	end
	if not hadState then pcall(refreshStyleState) end
	refreshStyleDropdown()
	updateStyleCard()
	if not silent then
		notify("equipped " .. tostring(entry.name or entry.id) .. "  |  next fight uses it")
		pushLog("equipped " .. tostring(entry.name or entry.id))
	end
	return true, nil
end

local function equipSelected(silent)
	if styleBusy then return false end
	styleBusy = true
	task.spawn(function()
		local fresh = refreshStyleState()
		local entry
		local ok, err = false, styleError
		if fresh then
			refreshStyleDropdown()
			entry = styleEntryForChoice(CFG.fightStyle)
			ok, err = equipStyleEntry(entry, true)
		end
		styleBusy = false
		refreshStyleDropdown()
		updateStyleCard()
		if not silent then
			if ok and entry then
				notify("equipped " .. tostring(entry.name or entry.id) .. "  |  next fight uses it")
				pushLog("equipped " .. tostring(entry.name or entry.id))
			elseif fresh then
				notify("equip failed: " .. tostring(err or "unknown"))
			else
				notify("style list refresh failed: " .. tostring(styleError or "unknown"))
			end
		end
	end)
	return true
end

local function scanStyles()
	if styleBusy then return end
	styleBusy = true
	task.spawn(function()
		local fresh = refreshStyleState()
		if not fresh then
			styleBusy = false
			notify("style scan failed: " .. tostring(styleError or "unknown"))
			updateStyleCard()
			return
		end
		local list = ownedStyles()
		local eq, eqId = equippedStyle()
		local rows = {}
		for _, entry in ipairs(list) do
			rows[#rows + 1] = string.format(
				"%s [%s %s] score %d slot %d",
				entry.name, entry.rarity, entry.id, entry.score, entry.index
			)
		end
		print("[MMA styles] owned " .. tostring(#list) .. ": " .. table.concat(rows, " | "))
		print("[MMA styles] equipped: " .. tostring(eq and eq.name or eqId or "none")
			.. "  |  best: " .. (list[1] and (list[1].name .. " " .. tostring(list[1].score)) or "none"))
		notify("styles scanned: " .. tostring(#list) .. " owned, best "
			.. (list[1] and (list[1].name .. " (" .. list[1].rarity .. ")") or "none"))
		styleBusy = false
		refreshStyleDropdown()
		updateStyleCard()
	end)
end

local function equipBestOwned()
	if styleBusy then return end
	styleBusy = true
	task.spawn(function()
		local fresh = refreshStyleState()
		if not fresh then
			styleBusy = false
			notify("style list refresh failed: " .. tostring(styleError or "unknown"))
			updateStyleCard()
			return
		end
		local list = ownedStyles()
		if #list == 0 then
			styleBusy = false
			notify("no owned styles found")
			updateStyleCard()
			return
		end
		local best = list[1]
		local state = styleState
		if type(state) == "table" and (tonumber(state.eq) or 1) == best.index then
			styleBusy = false
			notify("best owned already equipped: " .. best.name .. " (" .. best.rarity .. ")")
			updateStyleCard()
			return
		end
		local ok, err = equipStyleEntry(best, true)
		styleBusy = false
		refreshStyleDropdown()
		updateStyleCard()
		if ok then
			notify("equipped best owned: " .. best.name .. " (" .. best.rarity .. ", score " .. tostring(best.score) .. ")  |  next fight uses it")
			pushLog("equipped style " .. best.name)
		else
			notify("equip failed: " .. tostring(err))
		end
	end)
end

local function spinOnce(lucky)
	local remote = stylesRemoteFn()
	if not remote then
		styleError = "Styles remote not found"
		return nil, styleError
	end
	local ok, res = pcall(function()
		return remote:InvokeServer("spin", { lucky = lucky and true or false })
	end)
	if not ok then return nil, tostring(res) end
	if type(res) ~= "table" then return nil, "spin returned " .. type(res) end
	if type(res.state) == "table" then
		styleState = res.state
		styleStateAt = now()
		styleError = nil
	end
	if res.err then return nil, tostring(res.err) end
	if res.need then
		if res.need == "lucky" then return nil, "no lucky spins" end
		if res.need == "spins" then return nil, "no normal spins" end
		return nil, tostring(res.need)
	end
	local style = res.style
	local info = style and styleById(style) or nil
	return { info = info, id = style }, nil
end

local function spinMany(lucky, count)
	if spinBusy then
		notify("a spin run is already active")
		return false
	end
	spinBusy = true
	spinStop = false
	task.spawn(function()
		refreshStyleState()
		local sp, lk = spinCounts()
		local have = lucky and lk or sp
		if have < 1 then
			spinBusy = false
			updateStyleCard()
			notify(lucky and "no lucky spins - the game's style shop sells them" or "no normal spins - win career or hard fights to earn more")
			return
		end
		local want = math.clamp(tonumber(count) or 1, 1, have)
		local got = 0
		for i = 1, want do
			if spinStop or dead then break end
			local res, err = spinOnce(lucky)
			if not res and err == "slow" then
				task.wait(1)
				res, err = spinOnce(lucky)
			end
			if not res then
				notify("spin stopped: " .. tostring(err))
				break
			end
			got = got + 1
			local info = res.info
			local name = info and info.name or tostring(res.id or "?")
			local rarity = info and info.rarity or "?"
			local line = string.format(
				"%s %d/%d: %s (%s)",
				lucky and "lucky" or "normal", i, want, name, rarity
			)
			print("[MMA spins] " .. line)
			pushLog(line)
			if rarity == "GODLY" or rarity == "SECRET" or rarity == "UNIQUE" or rarity == "ADMIN" then
				notify("SPIN HIT: " .. name .. " (" .. rarity .. ")")
			end
			updateStyleCard()
			if CFG.spinStopRare and (rarity == "GODLY" or rarity == "SECRET") then
				notify("stopped on " .. rarity .. ": " .. name)
				break
			end
			if i < want then task.wait(0.2) end
		end
		local sp2, lk2 = spinCounts()
		spinBusy = false
		if dead then return end
		refreshStyleState()
		refreshStyleDropdown()
		updateStyleCard()
		notify(string.format("spin run done: %d spun  |  %d normal, %d lucky left", got, sp2, lk2))
	end)
	return true
end

local function stopSpins()
	if not spinBusy then
		notify("no spin run active")
		return
	end
	spinStop = true
	notify("stopping after the current spin")
end

--// ranked automation -----------------------------------------------------------
-- the ranked screen is the game's own UI. its buttons only carry Activated
-- listeners, and firesignal is a silent no-op in this executor, so the listener
-- itself is called: that is exactly the function a real click runs, which keeps
-- the queue, the ticket and the RR result inside the game's own flow.

local function onScreen(d)
	local p = d
	while p and p ~= game do
		if p:IsA("ScreenGui") and not p.Enabled then return false end
		if p:IsA("GuiObject") and not p.Visible then return false end
		p = p.Parent
	end
	return true
end

local function buttons()
	local pg = LP:FindFirstChild("PlayerGui")
	local root = pg and (pg:FindFirstChild("ROFC_UI") or pg)
	local out = {}
	if not root then return out end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("GuiButton") and onScreen(d) then
			table.insert(out, d)
		end
	end
	return out
end

local function labelOf(b)
	if b:IsA("TextButton") and b.Text ~= "" then return b.Text end
	for _, c in ipairs(b:GetDescendants()) do
		if c:IsA("TextLabel") and c.Text ~= "" then return c.Text end
	end
	return ""
end

local function press(b)
	for _, sig in ipairs({ b.Activated, b.MouseButton1Click }) do
		local ok, conns = pcall(getconnections, sig)
		if ok and type(conns) == "table" then
			for _, c in ipairs(conns) do
				if c.Function then
					local okc, err = pcall(c.Function)
					return okc, err
				end
			end
		end
	end
	return false, "no click handler"
end

local function findButton(names, texts)
	local list = buttons()
	for _, b in ipairs(list) do
		for _, n in ipairs(names) do
			if b.Name == n then return b end
		end
	end
	for _, b in ipairs(list) do
		local t = string.upper(labelOf(b))
		for _, s in ipairs(texts) do
			if t:find(s, 1, true) then return b end
		end
	end
	return nil
end

local QUEUE_NAMES = { "Btn_PLAYAGAIN", "Btn_PlayAgain", "Btn_FINDMATCH", "Btn_FindMatch", "Btn_Queue", "Btn_QUEUE" }
local QUEUE_TEXT = { "PLAY AGAIN", "FIND MATCH", "FIND A MATCH" }
local RANKED_PLAY_NAMES = { "Btn_PLAY", "Btn_Play" }
local RANKED_PLAY_TEXT = { "PLAY" }
local CANCEL_NAMES = { "Btn_CANCEL", "Btn_CancelQueue", "Btn_Cancel" }
local CONTINUE_NAMES = { "Btn_CONTINUE", "Btn_Continue" }
local CONTINUE_TEXT = { "CONTINUE" }
local RANKED_NAMES = { "Btn_RANKED", "Btn_Ranked", "Btn_RANKEDMODE" }
local RANKED_TEXT = { "RANKED" }

local queue = { last = "idle  |  auto queue off", nextTry = 0, nextNav = 0, pressedAt = 0, tries = 0, rankedAt = 0, endedAt = 0 }

local function queueTick()
	if dead or not CFG.autoQueue then
		queue.last = "idle  |  auto queue off"
		return
	end
	local t = now()
	if t < queue.nextTry then return end
	queue.nextTry = t + 0.5

	-- a live match needs nothing from us
	if match and not match.closed and match.state ~= "ended" and not match.finish then
		queue.pressedAt, queue.endedAt, queue.rankedAt = 0, 0, 0
		queue.last = "in match  |  round " .. tostring(match.round or 1)
		return
	end

	-- result screens: one press moves on to the ranked screen
	if CFG.autoContinue then
		local cont = findButton(CONTINUE_NAMES, CONTINUE_TEXT)
		if cont then
			local ok = press(cont)
			queue.pressedAt, queue.endedAt = 0, 0
			queue.last = ok and "result screen  |  continue" or "result screen  |  continue failed"
			queue.nextTry = t + 1.2
			return
		end
	end

	-- the match object outlives the bell. if no screen answers for it inside 8s,
	-- drop it so the panel can capture the next one instead of sitting on a corpse.
	if match then
		local ended = match.closed or match.finish ~= nil or match.state == "ended"
		if ended then
			if queue.endedAt == 0 then queue.endedAt = t end
			if t - queue.endedAt > 8 then
				match = nil
				queue.endedAt, queue.pressedAt = 0, 0
				queue.last = "match ended  |  released"
				pushLog("queue released the ended match")
				queue.nextTry = t + 1
				return
			end
		else
			queue.endedAt = 0
		end
	end

	-- cancel a queue that never found a match, then try again
	if queue.pressedAt > 0 and t - queue.pressedAt > 30 then
		local cancel = findButton(CANCEL_NAMES, { "CANCEL" })
		if cancel then
			pcall(press, cancel)
			queue.last = "queue timed out  |  cancelled"
		else
			queue.last = "queue timed out  |  retrying"
		end
		queue.pressedAt, queue.rankedAt = 0, 0
		queue.nextTry = t + 2
		return
	end

	local rankedUp = findButton({ "Btn_BACKTOLOBBY", "Btn_TabOVERVIEW" }, { "BACK TO LOBBY", "OVERVIEW" })
	if not rankedUp then queue.rankedAt = 0 end

	-- a press that left us on the ranked screen with no CANCEL button did not
	-- start a search (the screen builds its state a beat after it mounts)
	if queue.pressedAt > 0 and rankedUp and t - queue.pressedAt > 4 then
		if not findButton(CANCEL_NAMES, { "CANCEL" }) then
			queue.pressedAt, queue.rankedAt = 0, 0
			queue.last = "queue did not start  |  repress"
			queue.nextTry = t + 0.5
			return
		end
	end

	local play = findButton(QUEUE_NAMES, QUEUE_TEXT)
	if not play and rankedUp then
		-- the ranked screen's own PLAY is the queue button; the lobby's PLAY
		-- starts a casual bout, so it only counts once the ranked tabs are up
		if queue.rankedAt == 0 then
			queue.rankedAt = t
			queue.last = "ranked screen  |  settling"
			return
		end
		if t - queue.rankedAt >= 1.2 then
			play = findButton(RANKED_PLAY_NAMES, RANKED_PLAY_TEXT)
		else
			queue.last = "ranked screen  |  settling"
			return
		end
	end
	if play then
		local ok, err = press(play)
		queue.tries = queue.tries + 1
		queue.pressedAt = ok and t or 0
		queue.last = ok and ("queued  |  try " .. queue.tries) or ("queue press failed  |  " .. tostring(err))
		pushLog("queue press " .. (ok and "sent" or "failed"))
		queue.nextTry = t + (tonumber(CFG.queueDelay) or 6)
		return
	end

	-- not on the ranked screen: open it from the lobby
	if t >= queue.nextNav then
		local nav = findButton(RANKED_NAMES, RANKED_TEXT)
		if nav then
			queue.nextNav = t + 3
			local ok = press(nav)
			queue.last = ok and "opening ranked" or "ranked button failed"
			return
		end
	end
	queue.last = "idle  |  no ranked screen"
end

--// best config -----------------------------------------------------------------
-- one preset that plays the whole match: pressure without gassing, head hunting,
-- ground and submissions on. it bends a little around the opponent's style so a
-- wrestler is fought at range and a kicker is crowded instead. it does not touch
-- the style: that is a server-owned equip and is handled in the STYLE tab.

local BEST = {
	autoMaster = true,
	aimZone = "head",
	strikeStyle = "smart",
	safeKicks = true,
	adaptive = true,
	aggro = 72,
	staminaFloor = 16,
	retreatStamina = 30,
	finishPush = true,
	pressRate = 14,
	takedownStamina = 45,
	autoSkip = true,
	autoFight = true,
	autoAim = true,
	autoBlock = true,
	autoCounter = true,
	autoTakedown = true,
	autoGround = true,
	autoSub = true,
	autoSprawl = true,
}

local GRAPPLERS = { wrestler = true, grappler = true, blackbelt = true, aikido = true, kravmaga = true, silat = true, bokh = true, shaolin = true, suikendo = true }
local KICKERS = { muaythai = true, kickboxer = true, tkdmaster = true, capoeira = true, savate = true, dragon = true }
local SLUGGERS = { power = true, slugger = true, brawler = true, onepunch = true }

local function tuneTo(m)
	local style = m and tostring(m.oppStyle or "") or ""
	if GRAPPLERS[style] then
		CFG.aggro = 55
		CFG.retreatStamina = 34
		CFG.takedownStamina = 60
	elseif KICKERS[style] then
		CFG.aggro = 82
	elseif SLUGGERS[style] then
		CFG.aggro = 58
		CFG.staminaFloor = 24
	end
	local o = m and m.opp
	local maxSt = o and tonumber(o.maxStamina)
	if maxSt and maxSt < 70 then
		CFG.aggro = math.max(CFG.aggro, 80)
		CFG.staminaFloor = math.min(CFG.staminaFloor, 12)
	end
	return style
end

local function pushFlags()
	if not ui.window then return end
	pcall(function()
		ui.window:Set("mma_autoMaster", CFG.autoMaster)
		ui.window:Set("mma_aimZone", CFG.aimZone)
		ui.window:Set("mma_strikeStyle", CFG.strikeStyle)
		ui.window:Set("mma_safeKicks", CFG.safeKicks)
		ui.window:Set("mma_adaptive", CFG.adaptive)
		ui.window:Set("mma_aggro", CFG.aggro)
		ui.window:Set("mma_staminaFloor", CFG.staminaFloor)
		ui.window:Set("mma_retreatStamina", CFG.retreatStamina)
		ui.window:Set("mma_finishPush", CFG.finishPush)
		ui.window:Set("mma_pressRate", CFG.pressRate)
		ui.window:Set("mma_takedownStamina", CFG.takedownStamina)
		ui.window:Set("mma_autoSkip", CFG.autoSkip)
		ui.window:Set("mma_autoFight", CFG.autoFight)
		ui.window:Set("mma_autoAim", CFG.autoAim)
		ui.window:Set("mma_autoBlock", CFG.autoBlock)
		ui.window:Set("mma_autoCounter", CFG.autoCounter)
		ui.window:Set("mma_autoTakedown", CFG.autoTakedown)
		ui.window:Set("mma_autoGround", CFG.autoGround)
		ui.window:Set("mma_autoSub", CFG.autoSub)
		ui.window:Set("mma_autoSprawl", CFG.autoSprawl)
		ui.window:Set("mma_fightStyle", CFG.fightStyle)
		ui.window:Set("mma_spinCount", CFG.spinCount)
		ui.window:Set("mma_spinStopRare", CFG.spinStopRare)
	end)
end

local function applyBestCfg(reason)
	for k, v in pairs(BEST) do CFG[k] = v end
	clearTune()
	READ.counter = ""
	READ.style = ""
	local style = tuneTo(match)
	pushFlags()
	local text = "best cfg  |  " .. (reason or "manual") .. (style ~= "" and ("  |  vs " .. style) or "")
	pushLog(text)
	if ui.bestText then
		pcall(function() ui.bestText:Set(text) end)
	end
end

--// auto exec -------------------------------------------------------------------
-- queue_on_teleport runs source after the next server join. pointing it at the
-- loader means every teleport, including the game's own matchmaking hops, comes
-- back with the hub already loaded and the saved cfg already restored.

local LOADER = 'loadstring(game:HttpGet("https://raw.githubusercontent.com/yougyougo017-png/rugball/main/slimhub-loader.luau"))()'
-- marker the loader reads to drop duplicate auto-exec runs (two panels can load
-- in one server). a manual execute of the loader never carries it.
local ARMED = 'getgenv().SLIMHUB_AUTOEXEC = true; ' .. LOADER

local function armAutoExec()
	if not CFG.autoExec then return end
	local enqueue = queue_on_teleport or queueonteleport
	if not enqueue then return end
	local genv = (getgenv and getgenv()) or _G
	if genv.SLIMHUB_ARMED == game.JobId then return end
	local ok = pcall(enqueue, ARMED)
	if ok then
		genv.SLIMHUB_ARMED = game.JobId
		pushLog("auto exec armed  |  next join")
	end
end

--// match capture ---------------------------------------------------------------

local function isMatch(v)
	if type(v) ~= "table" then return false end
	local ok, mt = pcall(getmetatable, v)
	return ok and mt == Match and rawget(v, "player") ~= nil
end

-- the game keeps every live Match in a RenderStepped closure upvalue; walking those
-- upvalues is cheap and exact, and it catches a panel loaded mid-fight.
local function scanForMatch()
	if filtergc then
		local ok, found = pcall(filtergc, "table", { Metatable = Match }, true)
		if ok and isMatch(found) and not found.closed and not found.finish and found.state ~= "ended" then return found end
		local okAll, all = pcall(filtergc, "table", { Metatable = Match }, false)
		if okAll and type(all) == "table" then
			for _, v in ipairs(all) do
				if isMatch(v) and not v.closed and not v.finish and v.state ~= "ended" then
					if v.state == "fight" or v.controls then return v end
				end
			end
		end
	end
	for _, sig in ipairs({ RunService.RenderStepped, RunService.Heartbeat, RunService.Stepped }) do
		local ok, conns = pcall(getconnections, sig)
		if ok and type(conns) == "table" then
			for _, c in ipairs(conns) do
				local f = c.Function
				if f then
					for i = 1, 16 do
						local oku, a, b = pcall(debug.getupvalue, f, i)
						if not oku then break end
						if a == nil and b == nil then break end
						if isMatch(a) and not a.finish and a.state ~= "ended" then return a end
						if isMatch(b) and not b.finish and b.state ~= "ended" then return b end
					end
				end
			end
		end
	end
	return nil
end

local function resetWatch()
	lastState = { thrown = 0, landed = 0, damage = 0, td = 0, tdP = 0, kdO = 0, kdP = 0, finished = false, round = 0 }
end

local function adopt(m)
	if match == m and not m.closed then return end
	match = m
	if CFG.acBypass and not acShieldOn then pcall(setAcShield, true) end
	if acShieldOn then pcall(acCleanMatch, m) end
	resetWatch()
	resetAdapt()
	if m.finish then lastState.finished = true end
	status = "match captured"
	pushLog("match captured (round " .. tostring(m.round) .. ", " .. tostring(m.rounds) .. " rounds)")
	notify("match captured")
	if not styleState or now() - styleStateAt > 60 then
		task.spawn(function()
			pcall(refreshStyleState)
			pcall(updateStyleCard)
		end)
	end
	if CFG.autoBest then
		pcall(applyBestCfg, "match start")
	end
end

local oldNew = Match.new
local hookNew = function(cfg)
	local m = oldNew(cfg)
	if isMatch(m) then
		task.defer(adopt, m)
	end
	return m
end
Match.new = hookNew

--// aim -------------------------------------------------------------------------

local function aimPoint(m, zone)
	local o = m.opp
	if not o or not o.rig then return nil end
	local ok, p = pcall(function()
		if zone == "body" then
			return o.rig:point("body")
		elseif zone == "legs" then
			return o.rig.bones.ShinL.world.Position
		end
		return o.rig:point("head")
	end)
	if ok then return p end
	return nil
end

-- camYaw/camPitch are the game's own camera state: step() feeds them into the camera
-- and into player.yaw, and Match:aim() raycasts along the resulting camera CFrame.
local function aimAt(m, zone)
	local tgt = aimPoint(m, zone)
	local camPos = m.camPos
	if not tgt or not camPos then return end
	local d = tgt - camPos
	local horiz = flat(d).Magnitude
	if horiz < 0.25 then return end
	local yaw = Util.yawOf(d)
	if Util.dampAngle then
		m.camYaw = Util.dampAngle(m.camYaw, yaw, 14, 1 / 60)
	else
		m.camYaw = yaw
	end
	m.camPitch = Util.clamp(math.atan2(d.Y, horiz), -1.3, 0.75)
end

-- exact-aim frame for the strike itself: aim() reads CurrentCamera.CFrame, so write it
-- once right before the call (the game rewrites the camera every RenderStepped anyway).
local function strikeAt(m, move, zone)
	local tgt = aimPoint(m, zone)
	local cam = workspace.CurrentCamera
	if tgt and cam then
		local pos = cam.CFrame.Position
		local d = tgt - pos
		if flat(d).Magnitude > 0.2 then
			cam.CFrame = CFrame.lookAt(pos, tgt)
		end
	end
	local ok, res = pcall(m.playerStrike, m, move)
	return ok and res
end

--// fighter helpers -------------------------------------------------------------

local function strikeDef(move)
	local s = Config.Strikes
	return s and s[move]
end

local function canThrow(f, move)
	if not f or f.down or f.rig.ragdolled or f.mode ~= "fight" then return false end
	if f.shot or f.clinch then return false end
	if (f.slipT or -1) >= 0 then return false end
	if (f.bodyHurtT or 0) > 0.3 then return false end
	if f.time < (f.shotRecover or -1) then return false end
	if f.stamina < math.max(1, CFG.staminaFloor) then return false end
	local def = strikeDef(move)
	if not def then return false end
	if f.stamina < def.stamina then return false end
	if def.kind == "knee" and f.stamina < 8 then return false end
	local ok, striking = pcall(function() return f:isStriking() end)
	if ok and striking then return false end
	return true
end

-- the game measures reach from the root as arm reach plus a body allowance; its
-- own AI uses d.reach + 0.75 * s + reachBonus. anything inside that is punch
-- range, whatever the swing looks like.
local function armReach(f)
	if not f then return 0 end
	local d = f.d
	local base = (d and tonumber(d.reach)) or 2.27
	return base + 0.75 * (tonumber(f.s) or 1) + (tonumber(f.reachBonus) or 0)
end

local function effStyle()
	return TUNE.strikeStyle or CFG.strikeStyle
end

local function effAim()
	return TUNE.aimZone or CFG.aimZone
end

local function effFinishPush()
	if TUNE.finishPush ~= nil then return TUNE.finishPush end
	return CFG.finishPush
end

local function effRetreat()
	return tonumber(TUNE.retreatStamina) or CFG.retreatStamina
end

local function strikePhase(st)
	local def = st and (st.def or strikeDef(st.kind))
	if not def then return nil end
	local speed = math.max(0.1, tonumber(st.speed) or 1)
	local t = tonumber(st.t) or 0
	local windup = (def.windup or 0.1) / speed
	local extend = (def.extend or 0.12) / speed
	local hold = (def.hold or 0.05) / speed
	local retract = (def.retract or 0.2) / speed
	if t < windup then return "windup" end
	if t < windup + extend then return "extend" end
	if t < windup + extend + hold then return "hold" end
	if t < windup + extend + hold + retract then return "retract" end
	return "done"
end

-- Fighter sets blockAmt to 0 while isStriking(), so a kick started inside the
-- opponent's punch range is a free counter for them. only kick when they cannot
-- answer with a punch: their leg strike is out (canStart refuses every punch
-- while strikes.leg exists), their body is hurt enough to lose the action, or
-- they are outside arm reach and have to step in first.
local function kickWindow(m, dist)
	local o = m and m.opp
	if not o then return false end
	if o.down or (o.rig and o.rig.ragdolled) or o.mode ~= "fight" then return false end
	if o.shot or o.clinch then return true end
	if (tonumber(o.bodyHurtT) or 0) > 0.3 then return true end
	local strikes = o.strikes
	if type(strikes) == "table" then
		local leg = strikes.leg
		if leg then
			local phase = strikePhase(leg)
			if phase == "hold" or phase == "retract" or phase == "done" then return true end
			return false
		end
	end
	return dist > armReach(o) + 0.4 * (tonumber(o.s) or 1)
end

local function pickStrike(m, dist, reach, threat)
	local o = m.opp
	local p = m.player
	local style = effStyle()
	local stamina = p.stamina
	local safeKick = true
	if CFG.safeKicks then
		safeKick = (not threat) and kickWindow(m, dist)
	end
	local canKick = safeKick and dist <= reach * 1.30

	-- a shot or a clinch locks the opponent out of starting a strike, so this is
	-- the cleanest counter window in the game: knee the level change or kick the
	-- committed body.
	if o.shot or o.clinch then
		if canKick then
			if dist <= reach * 0.95 and stamina >= 20 then return "knee" end
			if stamina >= 8 then return "rkick" end
		end
		return nil
	end

	if style == "jab" then
		if dist <= reach then return "jab" end
		return nil
	end

	local rocked = (o.rockedT or 0) > 0
	local gas = o.stamina < 30

	if style == "smart" then
		if stamina < 26 then
			if dist <= reach then return "jab" end
			return nil
		end
		if rocked then
			if stamina >= 11 and canKick and dist > reach * 0.55 then return "rkick" end
			if dist <= reach and stamina >= 4.6 then return "rhook" end
			if dist <= reach then return "jab" end
			return nil
		end
		if dist > reach * 0.82 then
			if canKick and stamina >= 8 and math.random() < 0.45 then return "rkick" end
			if canKick and stamina >= 6.5 and math.random() < 0.5 then return "lkick" end
			if dist <= reach then return "jab" end
			return nil
		end
		if gas and stamina >= 6.5 and canKick and dist > reach * 0.5 then return "lkick" end
		if dist < reach * 0.45 and stamina >= 20 and canKick and math.random() < 0.35 then return "knee" end
		local pool = { "jab", "cross", "jab", "cross", "lhook", "rhook", "jab", "cross" }
		return pool[math.random(1, #pool)]
	end

	if style == "power" then
		if dist > reach then return nil end
		if stamina < 5 then return "jab" end
		local pool = { "cross", "rhook", "lhook", "cross" }
		return pool[math.random(1, #pool)]
	end

	if style == "kicks" then
		if stamina >= 8 and canKick and dist > reach * 0.7 then
			local pool = { "lkick", "rkick", "lkick", "jab" }
			return pool[math.random(1, #pool)]
		end
		if dist <= reach then
			local pool = { "jab", "cross", "jab" }
			return pool[math.random(1, #pool)]
		end
		return nil
	end

	if style == "combo" then
		if dist > reach then return nil end
		local pool = { "jab", "cross", "jab", "cross", "lhook", "rhook" }
		return pool[math.random(1, #pool)]
	end

	if dist <= reach then return "jab" end
	return nil
end

-- any opponent strike in windup or extend, with the opponent close enough to matter.
local function incomingStrike(m)
	local o = m.opp
	local p = m.player
	if not o or not p then return false, nil end
	local dist = flat(o.pos - p.pos).Magnitude
	local reach = (p.d and p.d.reach or 2.27) + 1.4 * (p.s or 1)
	if dist > reach then return false, nil end
	local ok, strikes = pcall(function() return o.strikes end)
	if not ok or type(strikes) ~= "table" then return false, nil end
	for limb, st in pairs(strikes) do
		local def = st.def or strikeDef(st.kind)
		local speed = st.speed or 1
		if def then
			local windup = (def.windup or 0.1) / math.max(0.1, speed)
			local extend = (def.extend or 0.12) / math.max(0.1, speed)
			if st.t < windup + extend + 0.02 then
				return true, limb
			end
		end
	end
	return false, nil
end

-- seconds until the opponent's next live strike reaches its extend phase.
-- 0 means one is extending right now, nil means nothing is coming.
local function strikeImpactIn(m)
	local o = m and m.opp
	if not o then return nil end
	local ok, strikes = pcall(function() return o.strikes end)
	if not ok or type(strikes) ~= "table" then return nil end
	local best = nil
	for _, st in pairs(strikes) do
		if type(st) == "table" then
			local def = st.def or strikeDef(st.kind)
			if def then
				local speed = math.max(0.1, tonumber(st.speed) or 1)
				local windup = (def.windup or 0.1) / speed
				local extend = (def.extend or 0.12) / speed
				local t = tonumber(st.t) or 0
				local left = nil
				if t < windup then
					left = windup - t
				elseif t < windup + extend + 0.02 then
					left = 0
				end
				if left and (best == nil or left < best) then
					best = left
				end
			end
		end
	end
	return best
end

--// adaptive counter ------------------------------------------------------------
-- classify the opponent's habits from the live fighter table. these are the same
-- numbers the FIGHT tab exposes: dist is root-to-root, reach is the game's own
-- arm reach, and moveInput is the world-space stick the sim actually walks with.

local function classifyStats(s)
	local t = math.max(0.1, tonumber(s.time) or 0)
	local strikes = (tonumber(s.punches) or 0) + (tonumber(s.kicks) or 0) + (tonumber(s.knees) or 0)
	local kickShare = strikes > 0 and ((tonumber(s.kicks) or 0) + (tonumber(s.knees) or 0)) / strikes or 0
	local blockFrac = (tonumber(s.blockT) or 0) / t
	local closeFrac = (tonumber(s.closeT) or 0) / t
	local farFrac = (tonumber(s.farT) or 0) / t
	local moveT = math.max(0.1, tonumber(s.moveT) or 0)
	local fwdFrac = (tonumber(s.fwdT) or 0) / moveT
	local backFrac = (tonumber(s.backT) or 0) / moveT
	local rate = strikes / t
	local shots = tonumber(s.shots) or 0
	local conf = math.min(1, t / 8) * 0.55 + math.min(1, strikes / 10) * 0.3 + math.min(1, shots / 2) * 0.15

	if shots >= 2 then
		return "wrestler", math.min(1, 0.65 + shots * 0.1)
	end
	if t >= 2.5 and strikes >= 3 and kickShare >= 0.35 then
		return "kicker", math.min(1, 0.55 + kickShare * 0.4)
	end
	if t >= 4 and strikes >= 3 and blockFrac >= 0.42 then
		return "guard", math.min(1, 0.55 + blockFrac * 0.4)
	end
	if t >= 4 and moveT >= 1.5 and fwdFrac >= 0.55 then
		return "pressure", math.min(1, 0.55 + fwdFrac * 0.35)
	end
	if t >= 4 and (backFrac >= 0.5 or (farFrac >= 0.5 and fwdFrac < 0.3)) then
		return "outfighter", math.min(1, 0.55 + math.max(backFrac, farFrac) * 0.35)
	end
	if strikes >= 5 and kickShare <= 0.2 then
		return "boxer", math.min(1, 0.55 + (1 - kickShare) * 0.3)
	end
	if t >= 6 and rate < 0.3 and fwdFrac < 0.35 then
		return "passive", math.min(1, 0.5 + (1 - math.min(1, rate / 0.3)) * 0.35)
	end
	return "unknown", math.min(1, conf)
end

local COUNTERS = {
	kicker = {
		label = "crowd the kick, box the body, shoot the planted leg",
		aggro = 82, range = 0.62, strikeStyle = "combo", aimZone = "body",
		takedown = true, takedownStamina = 28, finishPush = true,
		counterShot = "kick", ground = "sub",
	},
	boxer = {
		label = "stay off the pocket, kick the lead leg, reset",
		strikeStyle = "kicks", aimZone = "legs", takedown = false,
		finishPush = false, counterShot = "none", ground = "escape",
	},
	guard = {
		label = "break the guard low, change levels, then shoot",
		aggro = 68, range = 0.8, strikeStyle = "smart", aimZone = "legs",
		takedown = true, takedownStamina = 32, finishPush = true,
		counterShot = "guard", ground = "sub",
	},
	wrestler = {
		label = "keep it long, sprawl, knee the shot, do not follow down",
		strikeStyle = "kicks", aimZone = "head", takedown = false,
		takedownStamina = 80, finishPush = false, counterShot = "none",
		ground = "escape",
	},
	pressure = {
		label = "circle, jab the entry, shoot the step-in",
		aggro = 56, range = 0.9, strikeStyle = "combo", aimZone = "head",
		takedown = true, takedownStamina = 40, finishPush = true,
		counterShot = "pressure", ground = "sub",
	},
	outfighter = {
		label = "cut the cage, close, kick the body",
		aggro = 90, range = 0.85, strikeStyle = "smart", aimZone = "body",
		takedown = true, takedownStamina = 36, finishPush = true,
		counterShot = "none", ground = "sub",
	},
	passive = {
		label = "lead, kick the body and legs, force the grapple",
		aggro = 84, range = 0.88, strikeStyle = "combo", aimZone = "body",
		takedown = true, takedownStamina = 34, finishPush = true,
		counterShot = "guard", ground = "sub",
	},
}

local function applyCounter(kind)
	clearTune()
	local c = COUNTERS[kind]
	if not c then
		READ.counter = ""
		READ.style = ""
		return
	end
	READ.style = c.strikeStyle or ""
	if not CFG.adaptive then
		READ.counter = "read only  |  adaptive is off"
		return
	end
	for k, v in pairs(c) do
		if k ~= "label" then TUNE[k] = v end
	end
	READ.counter = c.label
end

local function setAdaptive(on)
	CFG.adaptive = on and true or false
	if CFG.adaptive then
		applyCounter(READ.read)
	else
		clearTune()
		READ.counter = "adaptive off"
	end
end

local function adaptTick(m)
	if not m or m.closed then return end
	local p, o = m.player, m.opp
	if not (p and o) then return end
	if m.state ~= "fight" or m.finish then return end
	if p.down or o.down or p.rig.ragdolled or o.rig.ragdolled then return end

	local t = now()
	local dt = t - (READ.lastT or t)
	if dt <= 0 then return end
	dt = math.min(dt, 0.25)
	READ.lastT = t
	READ.time = READ.time + dt

	if READ.prior == "" and m.oppStyle then
		local s = tostring(m.oppStyle)
		if GRAPPLERS[s] then
			READ.prior = "wrestler"
		elseif KICKERS[s] then
			READ.prior = "kicker"
		elseif SLUGGERS[s] then
			READ.prior = "pressure"
		end
	end

	local strikes = o.strikes
	if type(strikes) == "table" then
		for _, st in pairs(strikes) do
			if type(st) == "table" and not READ.lastSeen[st] then
				READ.lastSeen[st] = true
				local def = st.def or strikeDef(st.kind)
				local kind = def and def.kind or nil
				if kind == "kick" then
					READ.kicks = READ.kicks + 1
				elseif kind == "knee" then
					READ.knees = READ.knees + 1
				else
					READ.punches = READ.punches + 1
				end
			end
		end
	end

	local shot = o.shot ~= nil and o.shot ~= false
	if shot and not READ.lastShot then READ.shots = READ.shots + 1 end
	READ.lastShot = shot

	if (tonumber(o.blockAmt) or 0) > 0.45 then READ.blockT = READ.blockT + dt end

	local theirReach = armReach(o)
	local dist = flat(o.pos - p.pos).Magnitude
	if dist < theirReach * 0.8 then
		READ.closeT = READ.closeT + dt
	elseif dist > theirReach * 1.15 then
		READ.farT = READ.farT + dt
	end

	-- use the positions the sim actually moved, not the input vector: a fighter
	-- can be pushed, slid or clinched, and moveInput's space is not guaranteed.
	READ.incoming = false
	if READ.lastOPos then
		local step = flat(o.pos - READ.lastOPos)
		local speed = step.Magnitude / dt
		if speed > 0.6 then
			READ.moveT = READ.moveT + dt
			local toUs = flat(p.pos - o.pos)
			if toUs.Magnitude > 0.05 then
				local dot = step.Unit:Dot(toUs.Unit)
				if dot > 0.35 then
					READ.fwdT = READ.fwdT + dt
					READ.incoming = true
				elseif dot < -0.35 then
					READ.backT = READ.backT + dt
				end
			end
		end
	end
	READ.lastOPos = o.pos
	READ.lastPPos = p.pos

	if READ.time < 2.5 then return end
	if t - (READ.lastClass or 0) < 0.5 then return end
	READ.lastClass = t

	local kind, conf = classifyStats(READ)
	READ.confidence = math.floor((conf or 0) * 100 + 0.5)
	if kind == "unknown" then return end

	if kind == READ.read then
		READ.candidate = kind
		READ.candidateT = t
		return
	end
	if kind ~= READ.candidate then
		READ.candidate = kind
		READ.candidateT = t
		return
	end
	if t - READ.candidateT < 1.6 then return end

	READ.read = kind
	READ.changedAt = t
	applyCounter(kind)
	pushLog("opponent read: " .. string.upper(kind) .. "  |  " .. tostring(READ.counter))
end

local function readSummary()
	if not match then return "no match captured" end
	local t = math.max(0.1, READ.time)
	local strikes = READ.punches + READ.kicks + READ.knees
	local kickPct = strikes > 0 and math.floor((READ.kicks + READ.knees) / strikes * 100 + 0.5) or 0
	local blockPct = math.floor(READ.blockT / t * 100 + 0.5)
	local fwdPct = READ.moveT > 0.1 and math.floor(READ.fwdT / READ.moveT * 100 + 0.5) or 0
	local lines = {
		string.format("%s  |  %ds  |  %d strikes  |  %d%% kick", string.upper(READ.read), math.floor(READ.time), strikes, kickPct),
		string.format("guard %d%%  |  forward %d%%  |  shots %d  |  confidence %d%%", blockPct, fwdPct, READ.shots, READ.confidence),
	}
	if READ.read == "unknown" and READ.prior ~= "" then
		table.insert(lines, "prior from server style: " .. READ.prior)
	end
	if READ.counter ~= "" then
		table.insert(lines, "counter: " .. READ.counter)
	end
	if TUNE.takedown == true and not autoOn("autoTakedown") then
		table.insert(lines, "takedowns off  |  auto takedown is off")
	end
	return table.concat(lines, "\n")
end

--// ground menu handling --------------------------------------------------------

local POS_RANK = { guard = 1, half = 2, side = 3, mount = 4, back = 5 }
local SUB_PREF = { rnc = 6, armbar = 5, armtri = 5, americana = 4, kimura = 3, triangle = 4, gArmbar = 4, bKimura = 3 }

local function menuOf(m, f)
	local ok, menu = pcall(function() return m:groundMenu(f) end)
	if ok and type(menu) == "table" then return menu end
	return nil
end

-- score one menu entry. sub options win when stamina allows; passes climb the position
-- ladder; the bottom player prefers a sweep and then standing up.
local function scoreOption(entry, isTop, gnd)
	local action = entry[1]
	local target = entry[2]
	local groundMode = TUNE.ground
	if action == "sub" then
		if groundMode == "escape" then return -1 end
		if not autoOn("autoSub") then return -1 end
		return 60 + (SUB_PREF[target] or 1) * 5
	end
	if action == "pass" then
		if not isTop then return -1 end
		return 30 + (POS_RANK[target] or 0) * 12 + (target == "back" and 8 or 0)
	end
	if action == "esc" then return groundMode == "escape" and 200 or 90 end
	if action == "up" then return 25 + (gnd and gnd.pos == "back" and 20 or 0) end
	if action == "rev" then return groundMode == "escape" and 70 or 45 end
	if action == "subrev" then return 80 end
	if action == "stand" then return 18 end
	return 5
end

local function bestOption(m, f, gnd)
	local menu = menuOf(m, f)
	if not menu then return nil end
	local isTop = gnd.top == f
	local bestIndex, bestScore, bestAction
	for i, entry in ipairs(menu) do
		if type(entry) == "table" then
			local s = scoreOption(entry, isTop, gnd)
			if s > (bestScore or -1) then
				bestIndex, bestScore, bestAction = i, s, entry[1]
			end
		end
	end
	return bestIndex, bestScore, bestAction
end

--// automation ------------------------------------------------------------------

local nextMoveClear = 0
local lastTry = 0
local lastGroundStrike = 0
local lastGroundOpt = 0
local lastSprawl = 0
local lastSkip = 0
local lastTakedown = 0
local counterSpent = false
-- guard posture: the game ramps blockAmt at damp 16, so a reactive block is
-- already too late for a 1.3x-speed jab; and blockHold past 1.5 s drops the
-- block roll from 0.78 to 0.23, so the guard has to be reset between strikes.
local guardHeld = 0
local guardPulse = 0
local guardT = 0
local function setMove(vec)
	match.debugMove = vec
	nextMoveClear = now() + 0.25
end

local function setBlock(on)
	if Touch.block ~= on then
		Touch.block = on
	end
end

local function fightTick(m)
	local p, o = m.player, m.opp
	if not (p and o and p.rig and o.rig) then return end
	if m.state ~= "fight" or m.finish or not m.controls then return end
	if p.down or o.down or p.rig.ragdolled or o.rig.ragdolled then return end
	if m.gnd or m.drive then return end

	if autoOn("autoAim") then
		aimAt(m, effAim())
	end

	local delta = flat(o.pos - p.pos)
	local dist = delta.Magnitude
	local reach = (p.d and p.d.reach or 2.27) + 0.75 * (p.s or 1) + (tonumber(p.reachBonus) or 0)

	-- read the fight: are they hurt enough to press, or are we too tired to trade
	local headHp = (o.hp and o.hp.head) or 100
	local hurt = (o.rockedT or 0) > 0 or headHp < 26 or o.stamina < 20
	local gassed = p.stamina < math.max(6, effRetreat())
	local finishPush = effFinishPush()
	local pressing = finishPush and hurt and not gassed

	local aggro = tonumber(TUNE.aggro) or CFG.aggro
	local want = reach * (0.60 + 0.55 * (aggro / 100))
	if effStyle() == "kicks" then
		-- stand where the legs reach and the arms do not; safeKicks then has a
		-- band it can actually use instead of kicking in the pocket. if the
		-- opponent out-ranges the kick, fall back to boxing range rather than
		-- standing outside both.
		local kickWant = math.max(want, armReach(o) + 0.55 * (o.s or 1))
		if kickWant <= reach * 1.28 then
			want = kickWant
		end
	end
	-- the adaptive counter's own range wins in the neutral state, then the
	-- finish/retreat states take over so a hurt or gassed read cannot trap us
	if tonumber(TUNE.range) then
		want = reach * TUNE.range
	end
	if pressing then
		want = reach * 0.52          -- walk onto the finish instead of trading at range
	end
	if gassed then
		want = reach * 1.55          -- back out and breathe, let them walk onto a counter
	end

	local fwd, side = 0, 0
	if dist > want + 0.05 then
		fwd = -1
	elseif dist < want * 0.6 then
		fwd = 0.8
	end
	-- small orbit so the AI cannot just line us up, and so we stay off the fence
	local t = now()
	side = math.sin(t * 1.3) * (gassed and 0.55 or 0.25)
	setMove(Vector3.new(side, 0, fwd))

	local threat = incomingStrike(m)
	if autoOn("autoBlock") then
		local tnow = now()
		local dt = math.max(0, math.min(0.1, tnow - (guardT > 0 and guardT or tnow)))
		guardT = tnow

		-- hold the guard before the strike instead of after it: inside their
		-- arm reach a fast jab winds up in two frames, and blockAmt only
		-- counts above 0.55, which takes about three frames to ramp.
		local pocket = dist <= armReach(o) + 0.6 * (tonumber(o.s) or 1)
		local ready = o.mode == "fight" and not o.down and not o.shot and not o.clinch
			and (tonumber(o.stamina) or 100) >= 8
		local impact = strikeImpactIn(m)

		if guardPulse > 0 then
			if impact == 0 then
				-- a strike reached its extend while the guard was down: abort
				-- the reset and start ramping blockAmt for the next one.
				guardPulse = 0
				setBlock(true)
				guardHeld = 0.9
			else
				guardPulse = guardPulse - 1
				setBlock(false)
				guardHeld = 0
			end
		elseif guardHeld >= 1.25 and (impact == nil or impact > 0.13) then
			-- the game punishes a held guard: blockHold past 1.5 s drags the
			-- block roll from 0.78 toward 0.23. three ticks below the 0.55
			-- threshold reset it, so only drop it when nothing is landing.
			guardPulse = 3
			setBlock(false)
			guardHeld = 0
		else
			local up = (not pressing) and ((threat ~= false) or (pocket and ready))
			setBlock(up)
			if up then
				guardHeld = guardHeld + dt
			else
				guardHeld = 0
			end
		end
	else
		guardHeld, guardPulse, guardT = 0, 0, 0
	end

	local allowStrike = pressing or (not autoOn("autoBlock")) or (not threat) or (not autoOn("autoCounter"))
	if allowStrike and not gassed and dist <= reach * 1.30 and now() - lastTry > 0.09 then
		local move = pickStrike(m, dist, reach, threat)
		if move and canThrow(p, move) then
			lastTry = now()
			local zone = move == "knee" and "head" or effAim()
			strikeAt(m, move, zone)
		end
	end

	-- the read may suggest a takedown, but it must never turn one on: shooting is
	-- the user's switch. adaptive can only veto it (boxer/wrestler counters).
	local tdOn = autoOn("autoTakedown")
	if TUNE.takedown == false then tdOn = false end
	local tdStam = tonumber(TUNE.takedownStamina) or CFG.takedownStamina
	local tdGap = TUNE.counterShot and 0.9 or 0.75
	if tdOn and now() - lastTakedown > tdGap and p.stamina >= tdStam then
		local ok, can = pcall(function() return m:canShoot(p) end)
		local shootRange = 3.4 * ((p.s or 1) + (o.s or 1)) / 2
		local incomingStep = READ.incoming == true
		local counterWindow = false
		if TUNE.counterShot == "kick" then
			local leg = type(o.strikes) == "table" and o.strikes.leg or nil
			local phase = leg and strikePhase(leg) or nil
			counterWindow = (phase == "hold" or phase == "retract") and not o.shot
		elseif TUNE.counterShot == "guard" then
			counterWindow = (tonumber(o.blockAmt) or 0) > 0.45 and not o.shot
		elseif TUNE.counterShot == "pressure" then
			counterWindow = incomingStep and dist <= shootRange and not o.shot
		end
		if not counterWindow then counterSpent = false end
		local pressured = (o.rockedT or 0) > 0 or o.stamina < 35 or (o.hp.head < 35)
			or (counterWindow and not counterSpent) or math.random() < 0.02
		if ok and can and pressured and dist <= shootRange * 0.92 then
			local ok2 = pcall(m.playerShoot, m)
			if ok2 then
				lastTakedown = now()
				if counterWindow then counterSpent = true end
				pushLog("takedown shot at " .. string.format("%.1fm", dist))
			end
		end
	end
end

local function groundTick(m)
	local p = m.player
	local gnd = m.gnd
	if not (p and gnd) or m.finish then return end
	if not m.controls then return end

	local inSub = gnd.c and gnd.c.kind == "sub"
	local top = gnd.top == p
	local bottom = gnd.bottom == p
	if not (top or bottom) then return end
	pcall(function() m.debugMove = nil end)

	-- submission: we are either finishing one or defending one
	if inSub then
		if gnd.c.by == p then
			if now() - lastSprawl > 1 / math.max(1, CFG.pressRate) then
				lastSprawl = now()
				pcall(m.groundMash, m)
			end
		elseif gnd.c.vs == p then
			if now() - lastGroundOpt > 0.45 then
				lastGroundOpt = now()
				local menu = menuOf(m, p)
				local escIndex
				if menu then
					for i, entry in ipairs(menu) do
						if type(entry) == "table" and entry[1] == "esc" then escIndex = i break end
					end
				end
				if escIndex then pcall(m.groundOption, m, escIndex) end
			end
			if now() - lastSprawl > 1 / math.max(1, CFG.pressRate) then
				lastSprawl = now()
				pcall(m.groundMash, m)
			end
		end
		return
	end

	if not autoOn("autoGround") then return end

	-- top: ground and pound, and climb / submit when the moment is right
	if top then
		local staminaOk = p.stamina > 28
		if now() - lastGroundOpt > 0.5 then
			local index, score, action = bestOption(m, p, gnd)
			local shouldMove = index ~= nil and staminaOk
				and ((action == "sub" and p.stamina > 40)
					or (action == "pass" and (score or 0) >= 54 and math.random() < 0.35))
			if shouldMove then
				lastGroundOpt = now()
				pcall(m.groundOption, m, index)
			end
		end
		if gnd.pos ~= "back" and not gnd.trans and now() - lastGroundStrike > 0.24 then
			lastGroundStrike = now()
			local moves = { "jab", "cross", "lhook", "rhook" }
			pcall(m.groundStrikeInput, m, moves[math.random(1, #moves)])
		end
		return
	end

	-- bottom: escape the position, take the sweep, or attack from the guard
	if bottom then
		if now() - lastGroundOpt > 0.55 then
			local index, _, action = bestOption(m, p, gnd)
			local fire = false
			if index then
				if action == "rev" and p.stamina > 34 then
					fire = true
				elseif action == "sub" and autoOn("autoSub") and p.stamina > 34 and math.random() < 0.45 then
					fire = true
				elseif action == "up" and math.random() < 0.6 then
					fire = true
				end
			end
			if fire then
				lastGroundOpt = now()
				pcall(m.groundOption, m, index)
			end
		end
		if now() - lastSprawl > 1 / math.max(1, CFG.pressRate) then
			lastSprawl = now()
			pcall(m.groundMash, m)
		end
	end
end

local function driveTick(m)
	local drv = m.drive
	if not drv or m.finish then return end
	local p = m.player
	if drv.att ~= p and drv.def ~= p then return end
	if not autoOn("autoSprawl") then return end
	local gap = 1 / math.max(1, CFG.pressRate)
	if now() - lastSprawl >= gap then
		lastSprawl = now()
		pcall(m.sprawlPress, m)
	end
end

local function skipTick()
	if not autoOn("autoSkip") then return end
	if match and match.finish then return end
	if now() - lastSkip < 0.35 then return end
	if Cinema and Cinema.skippable then
		lastSkip = now()
		pcall(Cinema.requestSkip)
	end
end

--// rage ------------------------------------------------------------------------
-- the match is simulated on this client, so the fighter's own numbers are the
-- lever. power is the first term in every strike formula, koHP is the head
-- health the KO branch compares against, stamina and stun are written by the sim
-- every frame. every base value is remembered the first time a fighter is touched
-- and put back by restoreRage, so switching the tab off leaves a normal match.

local rageSaved = setmetatable({}, { __mode = "k" })
local lastOppHead = setmetatable({}, { __mode = "k" })

local function rageOn(key)
	if CFG.rageMode then return true end
	return CFG[key] == true
end

local function rememberFighter(f)
	local base = rageSaved[f]
	if base then return base end
	base = {
		power = f.power,
		speedMul = f.speedMul,
		strikeSpeed = f.strikeSpeed,
		koHP = f.koHP,
	}
	rageSaved[f] = base
	return base
end

local function restoreRage()
	for f, base in pairs(rageSaved) do
		if f then
			pcall(function()
				f.power = base.power
				f.speedMul = base.speedMul
				f.strikeSpeed = base.strikeSpeed
				f.koHP = base.koHP
			end)
		end
		rageSaved[f] = nil
	end
end

local function rageTick(m)
	if not m or m.closed or m.state ~= "fight" or m.finish then return end
	local p, o = m.player, m.opp
	if not (p and o) then return end

	local mult = math.clamp(tonumber(CFG.rageDamage) or 1, 1, 50)
	local wantSpeed = math.clamp(tonumber(CFG.rageSpeedValue) or 1.6, 1, 3)
	local boost = rageOn("rageBoost")
	local god = rageOn("rageGod")
	local endless = god or rageOn("rageStamina")
	local fast = god or rageOn("rageSpeed")
	local punch = rageOn("rageOnePunch")
	local freeze = rageOn("rageFreeze")

	local pb = rememberFighter(p)
	local ob = rememberFighter(o)

	p.power = (pb.power or 1) * (boost and mult or 1)
	p.speedMul = (pb.speedMul or 1) * (fast and wantSpeed or 1)
	p.strikeSpeed = (pb.strikeSpeed or 1) * (fast and wantSpeed or 1)
	o.koHP = punch and 100 or ob.koHP

	if punch then
		-- the sim rewrites koHP every frame, so the threshold alone is not enough:
		-- the first head damage we see is a landed strike, so hand that straight to
		-- the game's own knockdown path.
		local before = lastOppHead[o]
		if before and o.hp.head < before then
			o.hp.head = 0
			o.knockdowns = math.max(3, o.knockdowns or 0)
			pcall(function()
				m:knockdown(p, o, { kind = "straight", zone = "head", dmg = 10 }, nil)
			end)
			pushLog("rage  |  one punch")
		end
		lastOppHead[o] = o.hp.head
	end

	if freeze then
		o.power = 0
		o.speedMul = (ob.speedMul or 1) * 0.25
		o.strikeSpeed = (ob.strikeSpeed or 1) * 0.25
		o.stamina = 0
	else
		o.power = ob.power
		o.speedMul = ob.speedMul
		o.strikeSpeed = ob.strikeSpeed
	end

	if endless then
		p.stamina = p.maxStamina or 100
	end

	if god then
		if p.hp then
			for k in pairs(p.hp) do
				p.hp[k] = 100
			end
		end
		p.stun = 0
		p.rockedT = 0
	end
end

local function instantKO()
	local m = match
	if not m or m.closed or m.state ~= "fight" or m.finish then
		return false, "no live match"
	end
	local p, o = m.player, m.opp
	if not (p and o) then
		return false, "no fighters"
	end
	pcall(function()
		o.hp.head = 0
		o.knockdowns = math.max(3, o.knockdowns or 0)
	end)
	local ok, err = pcall(function()
		m:knockdown(p, o, { kind = "straight", zone = "head", dmg = 10 }, nil)
	end)
	if ok then
		pushLog("rage  |  instant knockdown")
	end
	return ok, err
end

local function instantWin()
	local m = match
	if not m or m.closed or m.state ~= "fight" or m.finish then
		return false, "no live match"
	end
	-- the fifth argument is the game's own "call it anyway" bypass: it skips the
	-- ranked guard that otherwise only lets doctor, corner and tko stoppages through.
	local ok, err = pcall(function()
		m:stoppage(m.player, "KO", "Punch", "ko", true)
	end)
	if not ok or not m.finish then
		pcall(function()
			m:stoppage(m.player, "TKO", "Punches", "tko", true)
		end)
	end
	if m.finish then
		pushLog("rage  |  stoppage forced")
		return true
	end
	return false, err or "stoppage refused"
end

--// log watchers ----------------------------------------------------------------

local function statFor(m, f)
	local ok, s = pcall(function() return m:statsFor(f) end)
	if ok and type(s) == "table" then return s end
	return nil
end

local function sumStat(m, f, key)
	local total = 0
	if type(m.stats) == "table" and f and f.side then
		for _, r in pairs(m.stats) do
			local s = type(r) == "table" and r[f.side]
			if type(s) == "table" and type(s[key]) == "number" then
				total = total + s[key]
			end
		end
	end
	return total
end

local function watch(m)
	local p = m.player
	local o = m.opp
	if not (p and o) then return end
	local ps = statFor(m, p)
	local os_ = statFor(m, o)

	if ps then
		if (ps.landed or 0) > (lastState.landed or 0) then
			lastState.landed = ps.landed
		end
		if (ps.thrown or 0) > (lastState.thrown or 0) then
			lastState.thrown = ps.thrown
		end
		if (ps.damage or 0) > (lastState.damage or 0) then
			lastState.damage = ps.damage
		end
		if (ps.takedowns or 0) > (lastState.tdP or 0) then
			lastState.tdP = ps.takedowns
			stats.takedowns = stats.takedowns + 1
			pushLog("takedown completed")
		end
	end
	if os_ then
		if (os_.takedowns or 0) > (lastState.td or 0) then
			lastState.td = os_.takedowns
			stats.tdConceded = (stats.tdConceded or 0) + 1
			pushLog("opponent completed a takedown")
		end
	end

	if (m.round or 0) > (lastState.round or 0) then
		lastState.round = m.round
		pushLog("round " .. tostring(m.round) .. " started")
	end

	if (o.knockdowns or 0) > (lastState.kdO or 0) then
		lastState.kdO = o.knockdowns
		stats.knockdowns = stats.knockdowns + 1
		pushLog("knockdown scored  #" .. tostring(o.knockdowns))
	end
	if (p.knockdowns or 0) > (lastState.kdP or 0) then
		lastState.kdP = p.knockdowns
		pushLog("you were dropped  #" .. tostring(p.knockdowns))
	end

	if m.finish and not lastState.finished then
		lastState.finished = true
		local f = m.finish
		local won = f.winner == p
		stats.fights = stats.fights + 1
		if won then
			stats.wins = stats.wins + 1
			if f.kind == "sub" then
				stats.subs = (stats.subs or 0) + 1
			elseif f.kind ~= "decision" then
				stats.koWins = stats.koWins + 1
			end
		elseif f.winner == o then
			stats.losses = stats.losses + 1
			if f.kind ~= "decision" and f.kind ~= "sub" then stats.koLosses = stats.koLosses + 1 end
		end
		stats.strikes = stats.strikes + sumStat(m, p, "thrown")
		stats.landed = stats.landed + sumStat(m, p, "landed")
		stats.damage = stats.damage + math.floor(sumStat(m, p, "damage"))
		pushLog(string.format(
			"fight over: %s  (%s)",
			won and "WIN" or (f.winner == o and "LOSS" or "DRAW"),
			tostring(f.method or f.kind)
		))
	end
end

--// HUD -------------------------------------------------------------------------

local drawings = {}
local hud = {}

local function newDrawing(cls)
	local ok, d = pcall(function()
		local obj = Drawing.new(cls)
		return obj
	end)
	if ok and d then
		table.insert(drawings, d)
		return d
	end
	return nil
end

local function buildHud()
	if #drawings > 0 then return end
	local function mk(cls)
		local d = newDrawing(cls)
		if d then
			d.Visible = false
			if d.Thickness ~= nil then pcall(function() d.Thickness = 1 end) end
			if d.Font ~= nil then pcall(function() d.Font = 2 end) end
			if d.Center ~= nil then pcall(function() d.Center = true end) end
		end
		return d
	end
	for _, key in ipairs({ "player", "opp" }) do
		hud[key] = {
			box = mk("Square"),
			hpBg = mk("Square"),
			hpFill = mk("Square"),
			bodyBg = mk("Square"),
			bodyFill = mk("Square"),
			stBg = mk("Square"),
			stFill = mk("Square"),
			name = mk("Text"),
			status = mk("Text"),
		}
	end
	hud.card = {
		bg = mk("Square"),
		hpBg = mk("Square"),
		hpFill = mk("Square"),
		stBg = mk("Square"),
		stFill = mk("Square"),
		name = mk("Text"),
		info = mk("Text"),
	}
end

local function clearHud()
	for _, d in ipairs(drawings) do
		pcall(function()
			d.Visible = false
			d:Remove()
		end)
	end
	drawings = {}
	hud = {}
end

local function hideFighter(h)
	if not h then return end
	for _, key in ipairs({ "box", "hpBg", "hpFill", "bodyBg", "bodyFill", "stBg", "stFill", "name", "status" }) do
		local d = h[key]
		if d then d.Visible = false end
	end
end

local function drawFighter(m, f, h, label, color)
	if not h then return end
	if not f or not f.rig then hideFighter(h) return end
	local cam = workspace.CurrentCamera
	local ok, head = pcall(function() return f.rig:point("head") end)
	if not ok or not head then hideFighter(h) return end
	local feet = f.pos
	local hPos, onScreen = cam:WorldToViewportPoint(head + Vector3.new(0, 0.28 * (f.s or 1), 0))
	local fPos = cam:WorldToViewportPoint(feet)
	if not onScreen or hPos.Z <= 0 or fPos.Z <= 0 then
		hideFighter(h)
		return
	end
	local vp = cam.ViewportSize
	if hPos.X < -50 or hPos.X > vp.X + 50 or hPos.Y < -50 or hPos.Y > vp.Y + 50 then
		hideFighter(h)
		return
	end
	local height = math.clamp(math.abs(fPos.Y - hPos.Y), 30, 480)
	local width = math.clamp(height * 0.34, 26, 190)

	local x = hPos.X - width / 2
	local top = hPos.Y - 34
	local barW = width
	local barH = 4

	-- thin silhouette box
	if h.box then
		h.box.Visible = true
		h.box.Color = color
		h.box.Transparency = 0.75
		h.box.Thickness = 1
		h.box.Filled = false
		h.box.Size = Vector2.new(width, height)
		h.box.Position = Vector2.new(x, hPos.Y)
	end

	if not CFG.hudBars then
		if h.hpBg then h.hpBg.Visible = false end
		if h.hpFill then h.hpFill.Visible = false end
		if h.bodyBg then h.bodyBg.Visible = false end
		if h.bodyFill then h.bodyFill.Visible = false end
		if h.stBg then h.stBg.Visible = false end
		if h.stFill then h.stFill.Visible = false end
	end

	-- head + body health, stacked
	local hpHead = math.clamp((f.hp and f.hp.head or 100) / 100, 0, 1)
	local hpBody = math.clamp((f.hp and f.hp.body or 100) / 100, 0, 1)
	local bars = {
		{ h.hpBg, h.hpFill, top, hpHead, Color3.fromRGB(255, 84, 84) },
		{ h.bodyBg, h.bodyFill, top + barH + 2, hpBody, Color3.fromRGB(255, 176, 74) },
	}
	for _, b in ipairs(bars) do
		local bg, fill, y, frac, col = b[1], b[2], b[3], b[4], b[5]
		if bg and fill and CFG.hudBars then
			bg.Visible = true
			bg.Color = Color3.fromRGB(12, 12, 16)
			bg.Transparency = 0.35
			bg.Filled = true
			bg.Size = Vector2.new(barW, barH)
			bg.Position = Vector2.new(x, y)
			bg.Thickness = 1
			fill.Visible = true
			fill.Color = col:Lerp(Color3.fromRGB(60, 220, 120), frac)
			fill.Transparency = 0.1
			fill.Filled = true
			fill.Size = Vector2.new(math.max(1, barW * frac), barH)
			fill.Position = Vector2.new(x, y)
			fill.Thickness = 1
		end
	end

	-- stamina
	local stFrac = math.clamp((f.stamina or 100) / math.max(1, f.maxStamina or 100), 0, 1)
	if h.stBg and h.stFill and CFG.hudBars then
		local sy = top + (barH + 2) * 2
		h.stBg.Visible = true
		h.stBg.Color = Color3.fromRGB(12, 12, 16)
		h.stBg.Transparency = 0.35
		h.stBg.Filled = true
		h.stBg.Size = Vector2.new(barW, 3)
		h.stBg.Position = Vector2.new(x, sy)
		h.stBg.Thickness = 1
		h.stFill.Visible = true
		h.stFill.Color = Color3.fromRGB(64, 200, 255)
		h.stFill.Transparency = 0.12
		h.stFill.Filled = true
		h.stFill.Size = Vector2.new(math.max(1, barW * stFrac), 3)
		h.stFill.Position = Vector2.new(x, sy)
		h.stFill.Thickness = 1
	end

	if h.name then
		if CFG.hudNames then
			local dist = ""
			if match and match.player and match.opp then
				dist = string.format("  %dm", math.floor(flat(f.pos - match.player.pos).Magnitude))
			end
			h.name.Visible = true
			h.name.Center = true
			h.name.Size = 13
			h.name.Outline = true
			h.name.Color = color
			h.name.Position = Vector2.new(hPos.X, top - 17)
			h.name.Text = label .. dist
			h.name.Transparency = 1
		else
			h.name.Visible = false
		end
	end

	if h.status then
		local bits = {}
		if (f.rockedT or 0) > 0 then table.insert(bits, "ROCKED") end
		if (f.stun or 0) > 55 then table.insert(bits, "STUN") end
		if f.down then table.insert(bits, "DOWN") end
		if (f.bodyHurtT or 0) > 0 then table.insert(bits, "BODY") end
		if CFG.hudAlerts and #bits == 0 and f ~= (match and match.player) then
			local threat = incomingStrike(match)
			if threat then table.insert(bits, "STRIKE") end
		end
		if #bits > 0 then
			h.status.Visible = true
			h.status.Center = true
			h.status.Size = 11
			h.status.Outline = true
			h.status.Color = Color3.fromRGB(255, 90, 90)
			h.status.Position = Vector2.new(hPos.X, top + (barH + 2) * 2 + 6)
			h.status.Text = table.concat(bits, " ")
			h.status.Transparency = 1
		else
			h.status.Visible = false
		end
	end
end

local lastHud = 0
local function fighterLabel(m, f, isPlayer)
	local prof = isPlayer and m.profile or m.oppProfile
	if type(prof) == "table" then
		local first = tostring(prof.first or "")
		local last = tostring(prof.last or "")
		local name = (first .. " " .. last):gsub("^%s+", ""):gsub("%s+$", "")
		if #name > 0 then return name end
	end
	if f and f.name and f.name ~= "Fighter" then return f.name end
	return isPlayer and "YOU" or "OPPONENT"
end

local function hideCard()
	local c = hud.card
	if not c then return end
	for _, d in pairs(c) do
		if d then d.Visible = false end
	end
end

-- the local fighter's head is usually off-screen (first person / over the
-- shoulder), so their own readout gets a fixed card in the lower-left corner.
local function drawCard(m)
	local c = hud.card
	if not c or not c.bg or not m.player then return end
	local w, h = 236, 62
	local x, y = 20, 96
	local p = m.player
	local hp = math.clamp((p.hp and p.hp.head or 100) / 100, 0, 1)
	local st = math.clamp((p.stamina or 100) / math.max(1, p.maxStamina or 100), 0, 1)

	c.bg.Visible = true
	c.bg.Color = Color3.fromRGB(10, 12, 16)
	c.bg.Transparency = 0.45
	c.bg.Filled = true
	c.bg.Thickness = 1
	c.bg.Size = Vector2.new(w, h)
	c.bg.Position = Vector2.new(x, y)

	if c.name then
		c.name.Visible = true
		c.name.Center = false
		c.name.Size = 13
		c.name.Outline = true
		c.name.Color = Color3.fromRGB(90, 220, 255)
		c.name.Position = Vector2.new(x + 10, y + 6)
		c.name.Text = fighterLabel(m, p, true)
		c.name.Transparency = 1
	end

	if c.info then
		c.info.Visible = true
		c.info.Center = false
		c.info.Size = 12
		c.info.Outline = true
		c.info.Color = Color3.fromRGB(230, 232, 240)
		c.info.Position = Vector2.new(x + 10, y + 24)
		c.info.Text = string.format(
			"R%s  %s   HP %d%%   ST %d%%",
			tostring(m.round or 1), fmtTime(m.clock or 0), math.floor(hp * 100), math.floor(st * 100)
		)
		c.info.Transparency = 1
	end

	local function bar(bg, fill, by, bh, frac, col)
		if not (bg and fill) then return end
		if not CFG.hudBars then
			bg.Visible = false
			fill.Visible = false
			return
		end
		bg.Visible = true
		bg.Color = Color3.fromRGB(30, 34, 42)
		bg.Transparency = 0.25
		bg.Filled = true
		bg.Thickness = 1
		bg.Size = Vector2.new(w - 20, bh)
		bg.Position = Vector2.new(x + 10, by)
		fill.Visible = true
		fill.Color = col
		fill.Transparency = 0.1
		fill.Filled = true
		fill.Thickness = 1
		fill.Size = Vector2.new(math.max(1, (w - 20) * frac), bh)
		fill.Position = Vector2.new(x + 10, by)
	end
	bar(c.hpBg, c.hpFill, y + 42, 5, hp, Color3.fromRGB(255, 84, 84):Lerp(Color3.fromRGB(60, 220, 120), hp))
	bar(c.stBg, c.stFill, y + 51, 4, st, Color3.fromRGB(64, 200, 255))
end

local function hudTick()
	if not CFG.hud or not match or not match.player or not match.opp then
		if hud.player then
			hideFighter(hud.player)
			hideFighter(hud.opp)
		end
		hideCard()
		return
	end
	if match.finish or match.state ~= "fight" then
		hideFighter(hud.player)
		hideFighter(hud.opp)
		hideCard()
		return
	end
	if now() - lastHud < 1 / 45 then return end
	lastHud = now()
	if #drawings == 0 then buildHud() end
	if #drawings == 0 then return end
	drawFighter(match, match.player, hud.player, fighterLabel(match, match.player, true), Color3.fromRGB(90, 220, 255))
	drawFighter(match, match.opp, hud.opp, fighterLabel(match, match.opp, false), Color3.fromRGB(255, 96, 96))
	drawCard(match)
end

--// career ---------------------------------------------------------------------

local careerText

local function refreshCareer()
	if not (GetCareer and careerText) then return end
	local ok, c = pcall(function() return GetCareer:InvokeServer() end)
	if not ok or type(c) ~= "table" then
		pcall(function() careerText:Set("career unavailable") end)
		return
	end
	local lines = {}
	local function add(k, v) table.insert(lines, string.format("%-10s %s", k, tostring(v))) end
	add("division", c.div or "?")
	add("record", string.format("%d-%d-%d", c.wins or 0, c.losses or 0, c.draws or 0))
	add("streak", c.streak or 0)
	add("next", c.nextOpp or "-")
	add("last", c.lastOpp or "-")
	add("fight", string.format("#%s of %s", tostring(c.fightNo or "?"), tostring(c.recs or "?")))
	add("belts", type(c.belts) == "table" and #c.belts or 0)
	add("defenses", c.defenses or 0)
	add("ko wins", c.koWins or 0)
	add("moves", c.moves or 0)
	pcall(function() careerText:Set(table.concat(lines, "\n")) end)
end

--// UI --------------------------------------------------------------------------

local Rayfield
pcall(function()
	Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)

local function notifyToWindow(text)
	print("[MMA] " .. tostring(text))
	if ui.window and ui.window.Notify then
		pcall(function()
			ui.window:Notify({ title = "MMA", content = tostring(text), duration = 4 })
		end)
	end
end
notify = notifyToWindow

local function buildUI()
	if not Rayfield then return end
	local w = Rayfield:CreateWindow({
		Name = "RAGDOLL MMA // MAX",
		LoadingTitle = "REALISTIC RAGDOLL MMA",
		LoadingSubtitle = "auto fight  -  ground game  -  live HUD",
		KeySystem = false,
	})
	ui.window = w
	pcall(function()
		w:ChangeTheme({
			WindowColor = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(14, 8, 10)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(34, 14, 18)),
			}),
			ShadowColor = Color3.fromRGB(5, 2, 4),
			CornerRoundness = UDim.new(0, 16),
			ElementCornerRadius = UDim.new(0, 10),
			PillCornerRadius = UDim.new(1, 0),
			ElementGradient = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 14, 18)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(46, 20, 26)),
			}),
			ElementStrokeGradient = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 64, 88)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 186, 84)),
			}),
			ElementStroke = Color3.fromRGB(84, 34, 44),
			ElementStrokeHover = Color3.fromRGB(255, 78, 96),
			AccentColor = Color3.fromRGB(255, 74, 92),
			AccentStroke = Color3.fromRGB(255, 200, 120),
			AccentGlow = 0.55,
			SliderProgress = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 186, 84)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 64, 88)),
			}),
			SliderBackground = Color3.fromRGB(34, 16, 20),
			SliderBackgroundHover = Color3.fromRGB(48, 22, 28),
			SliderHandle = Color3.fromRGB(255, 255, 255),
			SliderStroke = Color3.fromRGB(255, 200, 120),
			ToggleTrack = Color3.fromRGB(24, 10, 14),
			ToggleTrackTransparency = 0.65,
			ToggleKnobOff = Color3.fromRGB(150, 130, 134),
			ContentColor = Color3.fromRGB(246, 238, 240),
			TitlingColor = Color3.fromRGB(255, 255, 255),
			ElementTextHoverColor = Color3.fromRGB(255, 112, 128),
			StatBackground = Color3.fromRGB(28, 12, 16),
			TabBackground = ColorSequence.new(Color3.fromRGB(48, 20, 26), Color3.fromRGB(24, 10, 14)),
			TabStroke = ColorSequence.new(Color3.fromRGB(255, 64, 88), Color3.fromRGB(255, 186, 84)),
			TabColor = Color3.fromRGB(255, 244, 246),
			FieldGlow = Color3.fromRGB(255, 74, 92),
			DropdownHighlight = Color3.fromRGB(255, 74, 92),
		})
	end)

	local fightTab = w:CreateTab({ name = "FIGHT" })
	local styleTab = w:CreateTab({ name = "STYLE" })
	local rageTab = w:CreateTab({ name = "RAGE" })
	local groundTab = w:CreateTab({ name = "GROUND" })
	local rankedTab = w:CreateTab({ name = "RANKED" })
	local hudTab = w:CreateTab({ name = "HUD" })
	local careerTab = w:CreateTab({ name = "CAREER" })
	local sysTab = w:CreateTab({ name = "SYS" })

	-- FIGHT
	ui.card = fightTab:CreateText({ name = "state  |  idle", text = "no match captured" })
	fightTab:CreateToggle({
		name = "AUTO  |  full match",
		description = "one switch for the whole fight: aim, block, counters, strikes, takedowns, ground, submissions, sprawl and skip all behave as on. individual toggles keep their own state and take over again the moment this goes off.",
		flag = "mma_autoMaster",
		value = CFG.autoMaster,
		callback = function(v) CFG.autoMaster = v end,
	})
	fightTab:CreateSlider({
		name = "retreat stamina",
		description = "below this stamina the fighter stops trading, backs out to kicking range and waits to recover instead of standing in the pocket.",
		flag = "mma_retreatStamina",
		range = { 8, 50 },
		increment = 1,
		value = CFG.retreatStamina,
		suffix = "%",
		callback = function(v) CFG.retreatStamina = v end,
	})
	fightTab:CreateToggle({
		name = "finish push",
		description = "when the opponent is rocked, head-hurt or gassed, close onto short range and throw through the guard instead of trading at distance.",
		flag = "mma_finishPush",
		value = CFG.finishPush,
		callback = function(v) CFG.finishPush = v end,
	})
	fightTab:CreateToggle({
		name = "auto fight",
		description = "picks a strike from range and stamina, holds the right distance, and fires it with Match:playerStrike. everything is the game's own strike path.",
		flag = "mma_autoFight",
		value = CFG.autoFight,
		callback = function(v) CFG.autoFight = v end,
	})
	fightTab:CreateToggle({
		name = "auto aim",
		description = "drives match.camYaw/camPitch onto the selected zone. the game feeds those into the camera and into player.yaw, so the strike ray really lands where you aim.",
		flag = "mma_autoAim",
		value = CFG.autoAim,
		callback = function(v) CFG.autoAim = v end,
	})
	fightTab:CreateDropdown({
		name = "aim zone",
		description = "head does the most damage, body drains stamina, legs break the base. all three are real hit zones on the rig.",
		flag = "mma_aimZone",
		options = { "head", "body", "legs" },
		value = CFG.aimZone,
		callback = function(v) CFG.aimZone = tostring(v) end,
	})
	fightTab:CreateDropdown({
		name = "strike style",
		description = "smart reacts to range, gas and rocked state; power spends stamina on hooks and crosses; kicks fights at range; combo is a steady boxing rhythm. safe kicks still applies when it is on.",
		flag = "mma_strikeStyle",
		options = { "smart", "combo", "power", "kicks", "jab" },
		value = CFG.strikeStyle,
		callback = function(v) CFG.strikeStyle = tostring(v) end,
	})
	fightTab:CreateToggle({
		name = "safe kicks",
		description = "only starts a kick when the opponent cannot answer with a punch: outside their arm reach, already mid-kick, or hurt. the game zeroes your guard while you strike, so a kick thrown inside their punch range is a free counter.",
		flag = "mma_safeKicks",
		value = CFG.safeKicks,
		callback = function(v) CFG.safeKicks = v end,
	})
	fightTab:CreateSection({ name = "OPPONENT READ  |  LIVE  |  COUNTER" })
	ui.readCard = fightTab:CreateText({ name = "read  |  unknown", text = "no match captured" })
	fightTab:CreateToggle({
		name = "adaptive counter",
		description = "watches the opponent's real strikes, guard time, movement and takedown attempts, labels their playstyle, and shifts range, aim, strike style and takedown timing to counter it. it only changes this panel's own settings; the server profile is never written. turn it off to keep the readout but fight with your own slider values.",
		flag = "mma_adaptive",
		value = CFG.adaptive,
		callback = function(v) setAdaptive(v) end,
	})
	fightTab:CreateButton({
		name = "reset opponent read",
		description = "clears the sampled strikes, guard time and movement and starts reading this opponent again. the adaptive settings drop back to your slider values until a new read is confirmed.",
		callback = function()
			clearTune()
			resetRead()
		end,
	})
	fightTab:CreateSlider({
		name = "aggression",
		description = "how far in the auto fighter steps. low keeps a kicking range, high crowds the opponent.",
		flag = "mma_aggro",
		range = { 0, 100 },
		increment = 5,
		value = CFG.aggro,
		suffix = "%",
		callback = function(v) CFG.aggro = v end,
	})
	fightTab:CreateSlider({
		name = "stamina floor",
		description = "never start a strike below this stamina. keeps you from being gassed when the round turns.",
		flag = "mma_staminaFloor",
		range = { 5, 60 },
		increment = 1,
		value = CFG.staminaFloor,
		suffix = "%",
		callback = function(v) CFG.staminaFloor = v end,
	})
	fightTab:CreateToggle({
		name = "auto block",
		description = "holds Touch.block (the game's own guard) while the opponent is inside punching range, through every windup and extend, and drops it for three ticks between strikes to reset the game's guard fatigue. a reactive block is too late for 1.3x-speed hands.",
		flag = "mma_autoBlock",
		value = CFG.autoBlock,
		callback = function(v) CFG.autoBlock = v end,
	})
	fightTab:CreateToggle({
		name = "auto counter",
		description = "stops throwing while a strike is incoming, so the guard is never dropped mid-exchange.",
		flag = "mma_autoCounter",
		value = CFG.autoCounter,
		callback = function(v) CFG.autoCounter = v end,
	})
	fightTab:CreateToggle({
		name = "auto takedown",
		description = "shoots when the opponent is rocked, hurt or gassed and you are inside shooting range. the game resolves it into its own drive contest.",
		flag = "mma_autoTakedown",
		value = CFG.autoTakedown,
		callback = function(v) CFG.autoTakedown = v end,
	})
	fightTab:CreateSlider({
		name = "takedown stamina",
		description = "minimum stamina before an automatic shot.",
		flag = "mma_takedownStamina",
		range = { 10, 80 },
		increment = 5,
		value = CFG.takedownStamina,
		suffix = "%",
		callback = function(v) CFG.takedownStamina = v end,
	})
	fightTab:CreateToggle({
		name = "auto skip",
		description = "calls Cinema.requestSkip through every skippable walkout and round break, until the result appears.",
		flag = "mma_autoSkip",
		value = CFG.autoSkip,
		callback = function(v) CFG.autoSkip = v end,
	})

	-- STYLE
	ui.styleCard = styleTab:CreateText({ name = "styles  |  not loaded", text = "press scan styles" })
	styleTab:CreateButton({
		name = "scan styles (owned)",
		description = "one Styles:get invoke. prints every owned style with its slot, rarity and the sum of the game's ten letter grades, then names the best one. read-only.",
		callback = function() scanStyles() end,
	})
	styleTab:CreateButton({
		name = "equip best owned",
		description = "calls the same Styles:equip remote the game's style menu calls, switching your equipped slot to the highest-graded style you already own. it does not grant or roll anything. the change lands on the next fight.",
		callback = function() equipBestOwned() end,
	})
	styleTab:CreateSection({ name = "EQUIP  |  SERVER PROFILE  |  REAL" })
	local styleOptions = buildStyleOptions()
	local styleValue = tostring(CFG.fightStyle or "best owned")
	if styleValue ~= "best owned" and not styleOptionIds[styleValue] then
		-- the owned list is filled by the scan just after build; the saved
		-- choice is re-resolved then instead of being thrown away here.
		styleValue = "best owned"
	end
	ui.styleDrop = styleTab:CreateDropdown({
		name = "style to equip",
		description = "only styles this profile owns. the list fills in after a scan; 'best owned' follows the game's grade ranking.",
		flag = "mma_fightStyle",
		options = styleOptions,
		value = styleValue,
		callback = function(v) CFG.fightStyle = tostring(v) end,
	})
	styleTab:CreateButton({
		name = "equip selected style",
		description = "calls Styles:equip for the selected owned slot. this is a real profile change: both clients build the next fight from it. finish the current fight first; it lands on the next one.",
		callback = function() equipSelected() end,
	})
	styleTab:CreateSection({ name = "SPINS  |  SERVER PROFILE  |  FAST" })
	ui.spinCard = styleTab:CreateText({ name = "spins  |  not loaded", text = "press scan styles" })
	styleTab:CreateSlider({
		name = "spin count",
		description = "how many spins one click runs. the run stops when your spins run out or you press stop.",
		flag = "mma_spinCount",
		range = { 1, 100 },
		increment = 1,
		value = CFG.spinCount,
		suffix = "x",
		callback = function(v) CFG.spinCount = v end,
	})
	styleTab:CreateToggle({
		name = "stop on godly / secret",
		description = "ends a bulk run when a GODLY or SECRET style appears.",
		flag = "mma_spinStopRare",
		value = CFG.spinStopRare,
		callback = function(v) CFG.spinStopRare = v end,
	})
	styleTab:CreateButton({
		name = "FAST SPIN  |  normal  (skip reel)",
		description = "calls the game's own Styles:spin in a loop. it skips the client reel, not the server roll: the style is added to your real profile with the game's own odds. it cannot add spins.",
		callback = function() spinMany(false, CFG.spinCount) end,
	})
	styleTab:CreateButton({
		name = "FAST SPIN  |  lucky  (skip reel)",
		description = "same as normal, but spends lucky spins for the better GODLY / SECRET odds. you must already own the lucky spins; the profile is server-owned.",
		callback = function() spinMany(true, CFG.spinCount) end,
	})
	styleTab:CreateButton({
		name = "stop spinning",
		description = "stops the current bulk spin after the spin in flight.",
		callback = function() stopSpins() end,
	})
	styleTab:CreateText({
		name = "spin note",
		text = "fast spin resolves the server roll from this panel and prints the result, so the reel never plays. close and reopen the game's own STYLES screen to see new slots there. if your style slots are full, the game replaces one; buy more slots in the style shop to keep more. this does not grant spins or luck.",
	})
	styleTab:CreateText({
		name = "why a live style edit does nothing",
		text = "the game builds each fighter from the equipped style on the server. in PvP your opponent's client throws and resolves your strikes with the style id the server gave it, so changing your local Fighter cannot change the damage that player takes. the game's AntiCheat also snapshots player.fstyle at the bell and reverts a live edit within 0.5s, then cuts power to 30% and speed to 40% for the rest of the fight. equip on the server instead.",
	})

	-- RAGE
	ui.rageCard = rageTab:CreateText({ name = "rage  |  off", text = "no rage layers active" })
	rageTab:CreateToggle({
		name = "RAGE MODE  |  everything on",
		description = "one switch for the whole hacker stack: damage multiplier, one punch, super armour, endless stamina, faster hands and a frozen opponent. it also turns auto fight and auto aim on so the match plays itself.",
		flag = "mma_rageMode",
		value = CFG.rageMode,
		callback = function(v)
			CFG.rageMode = v
			if v then
				CFG.autoFight = true
				CFG.autoAim = true
				if ui.window then
					pcall(function() ui.window:Set("mma_autoFight", true) end)
					pcall(function() ui.window:Set("mma_autoAim", true) end)
				end
			end
		end,
	})
	rageTab:CreateToggle({
		name = "damage boost",
		description = "applies the damage multiplier to everything this fighter throws. off by default so the panel can sit loaded without changing a normal match.",
		flag = "mma_rageBoost",
		value = CFG.rageBoost,
		callback = function(v) CFG.rageBoost = v end,
	})
	rageTab:CreateSlider({
		name = "damage multiplier",
		description = "scales the fighter's power, which is the first term in every strike the game resolves. 8x turns a clean head shot from chip damage into a knockout in a couple of touches.",
		flag = "mma_rageDamage",
		range = { 1, 50 },
		increment = 1,
		value = CFG.rageDamage,
		suffix = "x",
		callback = function(v) CFG.rageDamage = v end,
	})
	rageTab:CreateToggle({
		name = "one punch",
		description = "the first time the opponent's head takes damage they are handed to the game's own knockdown path: one clean head shot drops them and the referee waves it off a moment later.",
		flag = "mma_rageOnePunch",
		value = CFG.rageOnePunch,
		callback = function(v) CFG.rageOnePunch = v end,
	})
	rageTab:CreateToggle({
		name = "super armour",
		description = "writes head, body and limb health back to full and clears stun every frame. the fight still plays, it just cannot hurt you.",
		flag = "mma_rageGod",
		value = CFG.rageGod,
		callback = function(v) CFG.rageGod = v end,
	})
	rageTab:CreateToggle({
		name = "endless stamina",
		description = "pins the stamina bar at full every frame, so fatigue never builds and every throw comes off a fresh tank.",
		flag = "mma_rageStamina",
		value = CFG.rageStamina,
		callback = function(v) CFG.rageStamina = v end,
	})
	rageTab:CreateToggle({
		name = "fast hands",
		description = "scales movement and strike animation speed by the hand speed slider. strikes come out before the opponent's guard reads them.",
		flag = "mma_rageSpeed",
		value = CFG.rageSpeed,
		callback = function(v) CFG.rageSpeed = v end,
	})
	rageTab:CreateSlider({
		name = "hand speed",
		description = "how much faster the fighter moves and throws while fast hands is on.",
		flag = "mma_rageSpeedValue",
		range = { 1, 3 },
		increment = 0.1,
		value = CFG.rageSpeedValue,
		suffix = "x",
		callback = function(v) CFG.rageSpeedValue = v end,
	})
	rageTab:CreateToggle({
		name = "freeze opponent",
		description = "drops the opponent's power to zero and slows their movement and strikes. their own AI and animations keep running, they just cannot hurt or catch you.",
		flag = "mma_rageFreeze",
		value = CFG.rageFreeze,
		callback = function(v) CFG.rageFreeze = v end,
	})
	rageTab:CreateSection({ name = "ANTI-CHEAT  |  RANKED PVP" })
	ui.acCard = rageTab:CreateText({ name = "anti-cheat  |  on", text = acStatusText() })
	rageTab:CreateToggle({
		name = "anti-cheat shield",
		description = "place version 107 added a client-side checker to ranked PvP: at the bell it snapshots power, speed, strike speed, chin, toughness and style mods, restores anything that changes, and cuts you to 40% speed and 30% power for the rest of the fight. auto fight, safe kicks and the opponent read never write those fields; rage does. this keeps the checker off matches that start while it is on and strips it from the match already running. client-side only: the server can still reject or nerf a boosted fighter, and a match already cleaned cannot be re-checked if you turn this off mid-fight.",
		flag = "mma_acBypass",
		value = CFG.acBypass,
		callback = function(v)
			local ok, err = setAcShield(v)
			if not ok then notify("anti-cheat shield: " .. tostring(err)) end
			if ui.acCard then pcall(function() ui.acCard:Set(acStatusText()) end) end
		end,
	})
	rageTab:CreateSection({ name = "INSTANT FINISH" })
	rageTab:CreateButton({
		name = "instant knockout",
		description = "zeros the opponent's head health and hands them to Match:knockdown. the game plays its own fall, TKO call and result screen about two seconds later.",
		callback = function()
			local ok, err = instantKO()
			notify(ok and "instant knockout sent" or ("no knockout: " .. tostring(err)))
		end,
	})
	rageTab:CreateButton({
		name = "instant win",
		description = "ends the bout through the match's own stoppage path with you as the winner, so the finish record and result flow are the game's own. the call stays on this client and opens the result screen right away.",
		callback = function()
			local ok, err = instantWin()
			notify(ok and "stoppage sent" or ("no stoppage: " .. tostring(err)))
		end,
	})
	rageTab:CreateButton({
		name = "restore normal fight",
		description = "switches every rage layer off, then puts back every fighter value the panel touched. use it when you want the current match to play honestly again.",
		callback = function()
			CFG.rageMode = false
			CFG.rageBoost = false
			CFG.rageOnePunch = false
			CFG.rageGod = false
			CFG.rageStamina = false
			CFG.rageSpeed = false
			CFG.rageFreeze = false
			if ui.window then
				for _, flag in ipairs({ "mma_rageMode", "mma_rageBoost", "mma_rageOnePunch", "mma_rageGod", "mma_rageStamina", "mma_rageSpeed", "mma_rageFreeze" }) do
					pcall(function() ui.window:Set(flag, false) end)
				end
			end
			restoreRage()
			notify("rage off, fighter values restored")
		end,
	})

	-- RANKED
	ui.queueCard = rankedTab:CreateText({ name = "queue  |  idle", text = "auto queue off" })
	rankedTab:CreateToggle({
		name = "auto queue",
		description = "presses the game's own PLAY AGAIN / FIND MATCH button whenever there is no fight, so a ranked bout starts by itself. the press runs the game's real click listener, ticket and RR result included.",
		flag = "mma_autoQueue",
		value = CFG.autoQueue,
		callback = function(v)
			CFG.autoQueue = v
			queue.nextTry = 0
			queue.tries = 0
			queue.pressedAt = 0
		end,
	})
	rankedTab:CreateToggle({
		name = "auto continue",
		description = "presses CONTINUE on the result and rank-up screens so the queue loop can start the next fight.",
		flag = "mma_autoContinue",
		value = CFG.autoContinue,
		callback = function(v) CFG.autoContinue = v end,
	})
	rankedTab:CreateSlider({
		name = "queue delay",
		description = "seconds to wait after a queue press before trying again. the game takes a few seconds to hand back an opponent, so very low values just double-press.",
		flag = "mma_queueDelay",
		range = { 2, 20 },
		increment = 1,
		value = CFG.queueDelay,
		suffix = "s",
		callback = function(v) CFG.queueDelay = v end,
	})
	rankedTab:CreateSection({ name = "AUTO EXEC" })
	rankedTab:CreateToggle({
		name = "auto execute on join",
		description = "queues the SLIMHUB loader to run after the next server join, so every new lobby comes back with the hub and this panel already loaded. needs an executor with queue_on_teleport (Real has it). the switch and your cfg are written to slimhub-mma.cfg, so it re-arms itself on every join.",
		flag = "mma_autoExec",
		value = CFG.autoExec,
		callback = function(v)
			CFG.autoExec = v
			armAutoExec()
		end,
	})
	rankedTab:CreateSection({ name = "BEST CFG" })
	rankedTab:CreateToggle({
		name = "auto best cfg",
		description = "the moment a match is captured (including one already running when the panel loads) the winning preset is written into every fight setting and the master switch is turned on. this is the auto-execute part: it re-arms the whole panel for you on every ranked join. it leaves the server-equipped style alone.",
		flag = "mma_autoBest",
		value = CFG.autoBest,
		callback = function(v)
			CFG.autoBest = v
			if v then applyBestCfg("toggled on") end
		end,
	})
	rankedTab:CreateButton({
		name = "apply best cfg now",
		description = "writes the preset once, without leaving it armed for later matches.",
		callback = function() applyBestCfg("manual") end,
	})
	ui.bestText = rankedTab:CreateText({ name = "preset", text = "head  |  smart  |  aggro 72  |  master on" })

	-- GROUND
	ui.groundCard = groundTab:CreateText({ name = "ground  |  idle", text = "no match captured" })
	groundTab:CreateToggle({
		name = "auto ground",
		description = "plays the game's own ground menu: passes up the position ladder on top, sweeps or stands on the bottom, and mashes the position.",
		flag = "mma_autoGround",
		value = CFG.autoGround,
		callback = function(v) CFG.autoGround = v end,
	})
	groundTab:CreateToggle({
		name = "auto submissions",
		description = "takes a submission entry from the menu when stamina allows, and mashes to finish one you already have.",
		flag = "mma_autoSub",
		value = CFG.autoSub,
		callback = function(v) CFG.autoSub = v end,
	})
	groundTab:CreateToggle({
		name = "auto sprawl",
		description = "spams Match:sprawlPress during a shot or a drive. it is the same press the defender and the attacker both use.",
		flag = "mma_autoSprawl",
		value = CFG.autoSprawl,
		callback = function(v) CFG.autoSprawl = v end,
	})
	groundTab:CreateSlider({
		name = "press rate",
		description = "presses per second for mashing and sprawling. the game rate-limits these on its own, so going past ~14 rarely helps and burns stamina.",
		flag = "mma_pressRate",
		range = { 4, 20 },
		increment = 1,
		value = CFG.pressRate,
		suffix = "/s",
		callback = function(v) CFG.pressRate = v end,
	})

	-- HUD
	hudTab:CreateToggle({
		name = "overlay hud",
		description = "draws health and stamina over both fighters using the live Fighter state.",
		flag = "mma_hud",
		value = CFG.hud,
		callback = function(v) CFG.hud = v end,
	})
	hudTab:CreateToggle({
		name = "health bars",
		description = "head and body health plus stamina for each fighter.",
		flag = "mma_hudBars",
		value = CFG.hudBars,
		callback = function(v) CFG.hudBars = v end,
	})
	hudTab:CreateToggle({
		name = "names + distance",
		description = "fighter labels and range in metres.",
		flag = "mma_hudNames",
		value = CFG.hudNames,
		callback = function(v) CFG.hudNames = v end,
	})
	hudTab:CreateToggle({
		name = "strike alerts",
		description = "flags a fighter in windup, and shows rocked, stun, down and body states.",
		flag = "mma_hudAlerts",
		value = CFG.hudAlerts,
		callback = function(v) CFG.hudAlerts = v end,
	})
	hudTab:CreateSection({ name = "SESSION" })
	ui.sFights = hudTab:CreateStat({ name = "fights", value = stats.fights })
	ui.sWins = hudTab:CreateStat({ name = "wins", value = stats.wins })
	ui.sLosses = hudTab:CreateStat({ name = "losses", value = stats.losses })
	ui.sLanded = hudTab:CreateStat({ name = "landed", value = stats.landed })
	ui.sThrown = hudTab:CreateStat({ name = "strikes", value = stats.strikes })
	ui.sDamage = hudTab:CreateStat({ name = "damage", value = stats.damage })
	ui.sTd = hudTab:CreateStat({ name = "takedowns", value = stats.takedowns })
	ui.sSubs = hudTab:CreateStat({ name = "subs", value = stats.subs })
	ui.sAcc = hudTab:CreateStat({ name = "accuracy", value = 0, suffix = "%" })
	-- session log
	ui.logText = hudTab:CreateText({ name = "log", text = "-" })

	-- CAREER
	careerText = careerTab:CreateText({ name = "career", text = "press refresh" })
	careerTab:CreateButton({
		name = "refresh career",
		description = "one GetCareer invoke, read-only.",
		callback = function()
			refreshCareer()
		end,
	})
	careerTab:CreateSection({ name = "INFO" })
	careerTab:CreateText({
		name = "how it works",
		text = "this panel never writes career data. results, saves and rank changes stay with the game's own onEnd handler.",
	})

	-- SYS
	sysTab:CreateButton({
		name = "panic (P)",
		description = "kill every automation flag, clear movement and guard, leave the match running.",
		callback = function()
			if ui.panic then ui.panic() end
		end,
	})
	sysTab:CreateButton({
		name = "unload panel",
		description = "tear down drawings, hooks, connections and the window. settings are kept.",
		callback = function()
			if ui.shutdown then ui.shutdown() end
		end,
	})
	sysTab:CreateSection({ name = "STATE" })
	ui.diag = sysTab:CreateText({ name = "diag", text = "match: none" })
end

--// loop ------------------------------------------------------------------------

local function panic()
	if dead then return end
	CFG.autoFight = false
	CFG.autoAim = false
	CFG.autoBlock = false
	CFG.autoCounter = false
	CFG.autoTakedown = false
	CFG.autoGround = false
	CFG.autoSub = false
	CFG.autoSprawl = false
	CFG.autoQueue = false
	CFG.autoBest = false
	CFG.autoContinue = false
	CFG.rageMode = false
	CFG.rageBoost = false
	CFG.rageOnePunch = false
	CFG.rageGod = false
	CFG.rageStamina = false
	CFG.rageSpeed = false
	CFG.rageFreeze = false
	CFG.acBypass = false
	spinStop = true
	restoreRage()
	pcall(setAcShield, false)
	if match then
		pcall(function()
			match.debugMove = nil
		end)
	end
	pcall(function() Touch.block = false end)
	for _, flag in ipairs({ "mma_autoFight", "mma_autoAim", "mma_autoBlock", "mma_autoCounter", "mma_autoTakedown", "mma_autoGround", "mma_autoSub", "mma_autoSprawl", "mma_autoQueue", "mma_autoBest", "mma_autoContinue", "mma_rageMode", "mma_rageBoost", "mma_rageOnePunch", "mma_rageGod", "mma_rageStamina", "mma_rageSpeed", "mma_rageFreeze", "mma_acBypass" }) do
		if ui.window then pcall(function() ui.window:Set(flag, false) end) end
	end
	status = "panic  |  automation off"
	pushLog("panic")
end
ui.panic = panic

local shutdown
shutdown = function()
	if dead then return end
	dead = true
	spinStop = true
	restoreRage()
	if AntiCheat and type(acAttachOriginal) == "function" then
		pcall(function() AntiCheat.attach = acAttachOriginal end)
	end
	acShieldOn = false
	if match then
		pcall(function() match.debugMove = nil end)
	end
	pcall(function() Touch.block = false end)
	if Match.new == hookNew then
		Match.new = oldNew
	end
	clearHud()
	if ui.keyConn then pcall(function() ui.keyConn:Disconnect() end) end
	if ui.loopConn then pcall(function() ui.loopConn:Disconnect() end) end
	if ui.window then pcall(function() ui.window:Unload() end) end
	_G.RagdollMmaPanel = { cfg = CFG }
	_G.RagdollMmaStats = stats
	print("[MMA] unloaded")
end
ui.shutdown = shutdown

local function syncUI()
	if ui.card then
		pcall(function()
			ui.card:SetTitle("state  |  " .. (match and ("round " .. tostring(match.round or 1)) or "idle"))
			ui.card:Set(status)
		end)
	end
	if ui.readCard then
		pcall(function()
			local txt = readSummary()
			ui.readCard:SetTitle("read  |  " .. (match and string.upper(READ.read) or "idle"))
			ui.readCard:Set(txt)
		end)
	end
	if ui.groundCard then
		pcall(function()
			local g = match and match.gnd			local txt = "no match captured"
			if match then
				if match.drive then
					txt = "drive  |  " .. (match.drive.att == match.player and "attacking" or "defending")
				elseif g then
					txt = string.format("ground  |  %s  |  %s", tostring(g.pos), g.top == match.player and "top" or "bottom")
				else
					txt = "standing"
				end
			end
			ui.groundCard:SetTitle("ground  |  " .. (g and tostring(g.pos) or (match and "standing" or "idle")))
			ui.groundCard:Set(txt)
		end)
	end
	if ui.queueCard then
		pcall(function()
			local txt = queue.last
			if queue.tries > 0 then
				txt = txt .. "  |  tries " .. queue.tries
			end
			ui.queueCard:Set(txt)
		end)
	end
	if ui.rageCard then
		pcall(function()
			local bits = {}
			if CFG.rageMode then bits[#bits + 1] = "MASTER" end
			if rageOn("rageBoost") then bits[#bits + 1] = tostring(CFG.rageDamage) .. "x power" end
			if rageOn("rageOnePunch") then bits[#bits + 1] = "one punch" end
			if rageOn("rageGod") then bits[#bits + 1] = "armour" end
			if rageOn("rageStamina") then bits[#bits + 1] = "endless stamina" end
			if rageOn("rageSpeed") then bits[#bits + 1] = tostring(CFG.rageSpeedValue) .. "x hands" end
			if rageOn("rageFreeze") then bits[#bits + 1] = "opponent frozen" end
			local txt = #bits > 0 and table.concat(bits, "  |  ") or "no rage layers active"
			if match and match.opp and match.opp.hp and not match.finish then
				txt = txt .. string.format("   |   opponent head %d", math.floor(match.opp.hp.head))
			end
			ui.rageCard:SetTitle("rage  |  " .. (CFG.rageMode and "MASTER" or (#bits > 0 and "custom" or "off")))
			ui.rageCard:Set(txt)
		end)
	end
	if ui.acCard then
		pcall(function()
			ui.acCard:SetTitle("anti-cheat  |  " .. (CFG.acBypass and "on" or "off"))
			ui.acCard:Set(acStatusText())
		end)
	end
	if ui.sFights then pcall(function() ui.sFights:Set(stats.fights) end) end
	if ui.sWins then pcall(function() ui.sWins:Set(stats.wins) end) end
	if ui.sLosses then pcall(function() ui.sLosses:Set(stats.losses) end) end
	if ui.sLanded then pcall(function() ui.sLanded:Set(stats.landed) end) end
	if ui.sThrown then pcall(function() ui.sThrown:Set(stats.strikes) end) end
	if ui.sDamage then pcall(function() ui.sDamage:Set(stats.damage) end) end
	if ui.sTd then pcall(function() ui.sTd:Set(stats.takedowns) end) end
	if ui.sSubs then pcall(function() ui.sSubs:Set(stats.subs) end) end
	if ui.sAcc then
		pcall(function()
			local acc = stats.strikes > 0 and math.floor(stats.landed / stats.strikes * 100) or 0
			ui.sAcc:Set(acc)
		end)
	end
	if ui.logText then
		pcall(function() ui.logText:Set(#log > 0 and table.concat(log, "\n") or "-") end)
	end
	if ui.diag then
		pcall(function()
			ui.diag:Set(string.format(
				"match: %s\nround: %s   clock: %s\ncontrols: %s   gnd: %s   drive: %s",
				match and "captured" or "none",
				match and tostring(match.round) or "-",
				match and fmtTime(match.clock or 0) or "-",
				match and tostring(match.controls) or "-",
				match and tostring(match.gnd ~= nil) or "-",
				match and tostring(match.drive ~= nil) or "-"
			))
		end)
	end
	updateStyleCard()
end

local lastSync = 0
local lastHudWarn = 0
local lastSave = 0

local function tick()
	if dead then return end
	if not match or match.closed then
		match = nil
		if now() >= nextScan then
			nextScan = now() + 1
			local found = scanForMatch()
			if found then
				adopt(found)
			else
				status = "idle  |  no match"
			end
		end
	end

	local m = match
	if m and not m.closed then
		-- clear our movement hook once the match stops needing it
		if nextMoveClear > 0 and now() > nextMoveClear then
			pcall(function() m.debugMove = nil end)
			nextMoveClear = 0
		end
		if m.state == "fight" and not m.finish and m.controls then
			status = string.format("round %s  |  %s  |  %s hp", tostring(m.round or 1), fmtTime(m.clock or 0), math.floor((m.player and m.player.hp.head) or 0))
		elseif m.finish then
			status = "fight over  |  " .. tostring(m.finish.method or m.finish.kind)
		else
			status = "match  |  " .. tostring(m.state) .. (m.controls and "" or "  |  waiting")
		end
		pcall(watch, m)
		pcall(adaptTick, m)
		pcall(rageTick, m)
		if autoOn("autoFight") then pcall(fightTick, m) end
		pcall(groundTick, m)
		pcall(driveTick, m)
		if not CFG.autoFight and not CFG.autoGround and not CFG.autoSprawl then
			pcall(function()
				if m.debugMove then m.debugMove = nil end
			end)
		end
		if not CFG.autoBlock then
			pcall(function() Touch.block = false end)
		end
	end
	pcall(skipTick)
	pcall(queueTick)
	local okHud, hudErr = pcall(hudTick)
	if not okHud and now() - lastHudWarn > 5 then
		lastHudWarn = now()
		warn("[MMA] hud error: " .. tostring(hudErr))
	end
	local t = now()
	if t - lastSync > 0.3 then
		lastSync = t
		pcall(syncUI)
	end
	if t - lastSave > 4 then
		lastSave = t
		pcall(saveCfg)
	end
end

buildUI()
if ui.window then
	local conn
	conn = UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.P then
			panic()
		end
	end)
	ui.keyConn = conn
end
ui.loopConn = RunService.Heartbeat:Connect(function()
	local ok, err = pcall(tick)
	if not ok then
		warn("[MMA] tick error: " .. tostring(err))
	end
end)
resetWatch()
refreshCareer()
pushLog("panel loaded")
pcall(armAutoExec)
pcall(saveCfg)
task.spawn(function()
	pcall(refreshStyleState)
	pcall(refreshStyleDropdown)
	pcall(updateStyleCard)
end)

_G.RagdollMmaPanel = {
	cfg = CFG,
	window = ui.window,
	stop = shutdown,
	panic = panic,
	stats = stats,
	hud = hud,
	drawings = drawings,
	getMatch = function() return match end,
	scan = scanForMatch,
	aim = aimAt,
	applyBest = applyBestCfg,
	queue = queue,
	strike = function(move)
		if match then return strikeAt(match, move or "jab", effAim()) end
		return false
	end,
	adaptive = {
		get = function()
			return {
				read = READ.read,
				confidence = READ.confidence,
				counter = READ.counter,
				style = READ.style,
				time = READ.time,
				punches = READ.punches,
				kicks = READ.kicks,
				knees = READ.knees,
				shots = READ.shots,
				blockT = READ.blockT,
				fwdT = READ.fwdT,
				backT = READ.backT,
				closeT = READ.closeT,
				farT = READ.farT,
				styleOverride = TUNE.strikeStyle,
				aimZone = effAim(),
				takedown = TUNE.takedown,
				counterShot = TUNE.counterShot,
				takedownStamina = TUNE.takedownStamina,
			}
		end,
		set = setAdaptive,
		reset = function()
			clearTune()
			resetRead()
		end,
		classify = function(s) return classifyStats(s) end,
	},
	antiCheat = {
		get = function()
			return {
				enabled = acShieldOn,
				module = AntiCheat ~= nil,
				patched = AntiCheat ~= nil and type(acAttachOriginal) == "function" and AntiCheat.attach ~= acAttachOriginal,
				killed = acKilled,
				checked = match ~= nil and acChecked[match] == true,
				cfg = CFG.acBypass,
			}
		end,
		set = setAcShield,
		clean = function() return acCleanMatch(match) end,
	},
	combat = {
		kickWindow = function(dist, opp)
			local o = opp or (match and match.opp)
			if not o then return false end
			if not dist then
				if not match or not match.player then return false end
				dist = flat(match.opp.pos - match.player.pos).Magnitude
			end
			return kickWindow({ opp = o }, dist)
		end,
		pick = function()
			if not match or not match.player or not match.opp then return nil end
			local p = match.player
			local dist = flat(match.opp.pos - p.pos).Magnitude
			local reach = (p.d and p.d.reach or 2.27) + 0.75 * (p.s or 1) + (tonumber(p.reachBonus) or 0)
			return pickStrike(match, dist, reach, incomingStrike(match))
		end,
	},
	instantKO = instantKO,
	instantWin = instantWin,
	restoreRage = restoreRage,
	styles = {
		scan = scanStyles,
		equipBest = equipBestOwned,
		equipSelected = equipSelected,
		resolve = styleEntryForChoice,
		spin = spinMany,
		stopSpin = stopSpins,
		spins = function()
			local sp, lk, pity = spinCounts()
			return { normal = sp, lucky = lk, pity = pity }
		end,
		state = function() return styleState end,
	},
	raging = function()
		return CFG.rageMode
	end,
}
end

--// embedded suite: carsoccer  (from carsoccer.luau) =========================
Hub.SUITE.carsoccer = function()
-- CarSoccer | PILOT - client-sim autopilot, ball path ESP, speed/boost readout
-- place 101880234193261 | Rayfield Gen2 | replace-not-stack via _G.CarSoccer

local prev = _G.CarSoccer
local CFG = (prev and prev.cfg) or {
	pilot = false,
	mode = "striker", -- striker | defender | chase
	smartBoost = true,
	autoJump = true,
	offset = 158,
	steerGain = 3,
	look = 0.45,
	path = true,
	goals = true,
	pathLen = 1.5,
}
if prev and prev.stop then
	pcall(prev.stop)
end
_G.CarSoccer = { cfg = CFG }

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local Sim = RS:WaitForChild("Shared"):WaitForChild("Sim")
local Const = require(Sim:WaitForChild("Const"))
local ArenaGeom = require(Sim:WaitForChild("ArenaGeom"))
local Protocol = require(RS.Shared:WaitForChild("Net"):WaitForChild("Protocol"))
local MatchSession
do
	local holder = LP:WaitForChild("PlayerScripts"):FindFirstChild("Client")
	if holder then
		local m = holder:FindFirstChild("MatchSession")
		if m then
			local ok, res = pcall(require, m)
			if ok then MatchSession = res end
		end
	end
end

local GRAV = Const.GRAVITY_Z or -650
local BALL_REST = Const.BALL_REST_Z or 93.15
local GOAL_Y = (ArenaGeom.EXTENT_Y or 5120) - 24
local MOUTH_Z = (ArenaGeom.MOUTH_HEIGHT or 640) / 2
local SUPERSONIC = Const.SUPERSONIC_START_SPEED or 2200

--// state -----------------------------------------------------------------------
local session, mySide, window
local hbConn, renderConn, keyConn
local jumpUntil, lastErrAt, lastStatAt = 0, 0, 0
local dead = false

local speedStat, boostStat

--// helpers --------------------------------------------------------------------
local function ballOf(match)
	local b = match.ball
	if b == nil and type(match.world) == "table" then
		b = match.world.ball
	end
	if b == nil then
		for k, v in pairs(match) do
			if k == "ball" and type(v) == "table" then
				b = v
				break
			end
		end
	end
	if type(b) == "table" then
		local body = b.body
		if body and body.pos and body.vel then
			return body
		end
		if b.pos and b.vel then
			return b
		end
	end
	return nil
end

-- ball position t seconds ahead: gravity, floor bounce, no drag (visual grade)
local function ballAt(body, t)
	local px, py, pz = body.pos.x, body.pos.y, body.pos.z
	local vx, vy, vz = body.vel.x, body.vel.y, body.vel.z
	local acc = 0
	while acc < t do
		local dt = math.min(0.05, t - acc)
		vz = vz + GRAV * dt
		px = px + vx * dt
		py = py + vy * dt
		pz = pz + vz * dt
		if pz < BALL_REST and vz < 0 then
			pz = BALL_REST
			vz = -vz * 0.6
			vx = vx * 0.9
			vy = vy * 0.9
		end
		acc = acc + dt
	end
	return px, py, pz
end

local function oops(err)
	local now = os.clock()
	if now - lastErrAt > 5 then
		lastErrAt = now
		warn("[CarPilot] " .. tostring(err))
	end
end

--// pilot ----------------------------------------------------------------------
-- math adapted from the game's own Sim.AimPilot controller
local function pilot(car, match, ctrl)
	if car.isDemoed then
		return
	end
	local body = car.body
	local pos = body.pos

	-- flat forward + speeds
	local fx, fy = body.fwd.x, body.fwd.y
	local fl = math.sqrt(fx * fx + fy * fy)
	if fl < 1e-5 then
		fx, fy = 0, 1
	else
		fx, fy = fx / fl, fy / fl
	end
	local fwdSpeed = body.vel.x * fx + body.vel.y * fy
	local speed = math.sqrt(body.vel.x ^ 2 + body.vel.y ^ 2 + body.vel.z ^ 2)

	local ball = ballOf(match)
	if not ball then
		return
	end

	-- remember which half we defend (kickoff spawns sit on own half)
	local my = mySide
	if match.phase ~= "play" and math.abs(pos.y) > 1000 then
		my = pos.y > 0 and 1 or -1
		mySide = my
	elseif not my then
		my = pos.y >= 0 and 1 or -1
		mySide = my
	end

	-- predicted ball at intercept time
	local dBall = math.sqrt((pos.x - ball.pos.x) ^ 2 + (pos.y - ball.pos.y) ^ 2)
	local tLook = math.clamp(dBall / math.max(math.abs(fwdSpeed), 700), 0.1, CFG.look)
	local bx, by, bz = ballAt(ball, tLook)

	-- contact point + drive direction per mode
	local dirx, diry, contactX, contactY, swing = 0, -my, 0, 0, false
	if CFG.mode == "striker" then
		local gx = math.clamp(bx * 0.25, -350, 350)
		local dxx, dyy = gx - bx, -my * GOAL_Y - by
		local dl = math.sqrt(dxx * dxx + dyy * dyy)
		if dl < 1 then
			dxx, dyy, dl = 0, -my, 1
		end
		dirx, diry = dxx / dl, dyy / dl
		contactX = bx - dirx * CFG.offset
		contactY = by - diry * CFG.offset
		swing = true
	elseif CFG.mode == "defender" then
		local dxx, dyy = bx, by - my * GOAL_Y
		local dl = math.sqrt(dxx * dxx + dyy * dyy)
		if dl < 1 then
			dxx, dyy, dl = 0, -my, 1
		end
		dirx, diry = dxx / dl, dyy / dl
		local park = math.min(700, dl * 0.5)
		contactX = dirx * park
		contactY = my * GOAL_Y + diry * park
	else -- chase: straight at the ball from whichever side we are on
		local dxx, dyy = pos.x - bx, pos.y - by
		local dl = math.sqrt(dxx * dxx + dyy * dyy)
		if dl < 1 then
			dxx, dyy, dl = 0, -my, 1
		end
		dirx, diry = dxx / dl, dyy / dl
		contactX = bx
		contactY = by
	end

	local relX, relY = pos.x - contactX, pos.y - contactY
	local along = relX * dirx + relY * diry

	-- aim point with the game bot's lead, swing wide around the ball if wrong side
	local lead = math.clamp(math.max(fwdSpeed, 0) * 0.45 + 300, 350, 1100)
	local aimX = contactX + dirx * math.min(along + lead, 220)
	local aimY = contactY + diry * math.min(along + lead, 220)
	if swing and along > 60 and dBall < 800 then
		local perpx, perpy = -diry, dirx
		local side = (relX * perpx + relY * perpy >= 0) and 1 or -1
		aimX = bx + perpx * side * 420 - dirx * 200
		aimY = by + perpy * side * 420 - diry * 200
	end

	-- signed angle from forward to aim (AimPilot convention)
	local toX, toY = aimX - pos.x, aimY - pos.y
	local ang = math.atan2(toX * -fy + toY * fx, toX * fx + toY * fy)

	ctrl.steer = math.clamp(ang * CFG.steerGain, -1, 1)
	ctrl.throttle = 1
	ctrl.pitch, ctrl.yaw, ctrl.roll = 0, 0, 0
	ctrl.boost = CFG.smartBoost
		and math.abs(ang) < 0.6
		and speed < SUPERSONIC - 50
		and (car.boost or 0) > 4
		and dBall > 250
	ctrl.handbrake = math.abs(ang) > 1.9 and speed > 500 and car.isOnGround

	-- wrong side and jammed against the ball: back out and swing
	if swing and along > 60 and dBall < 420 and fwdSpeed > 700 then
		ctrl.throttle = -1
		ctrl.boost = false
		ctrl.handbrake = car.isOnGround == true
	end

	-- auto jump for a hanging ball over the hood
	local now = os.clock()
	if CFG.autoJump and car.isOnGround and bz - pos.z > 130 and dBall < 400 and (ball.vel.z or 0) < 60 then
		jumpUntil = now + 0.18
	end
	ctrl.jump = now < jumpUntil
end

--// hooks -----------------------------------------------------------------------
-- the tick loop does: input -> controlsOf(own) -> Protocol.quantize(controls) -> prediction step.
-- we ride quantize and overwrite our controls right before the game reads them -
-- the same surface the game's own AimPilot bot drives.

local origQuantize, quantizeHook
local origNew, newHook, origDestroy, destroyHook

local function adoptSession(s)
	session = s
	mySide = nil
	print("[CarPilot] match session captured - pilot armed")
end

quantizeHook = function(c, ...)
	if session ~= nil and CFG.pilot and not dead then
		local ok, err = pcall(function()
			local match = session.match
			local own = session.own
			if match ~= nil and own ~= nil and match.phase == "play" then
				local entry = match.cars[own]
				if entry ~= nil and entry.car ~= nil and rawequal(c, entry.car.controls) then
					pilot(entry.car, match, c)
				end
			end
		end)
		if not ok then
			oops(err)
		end
	end
	return origQuantize(c, ...)
end
origQuantize = Protocol.quantize
Protocol.quantize = quantizeHook

if MatchSession then
	newHook = function(...)
		local s = origNew(...)
		if type(s) == "table" and s.match ~= nil and s.own ~= nil then
			adoptSession(s)
		end
		return s
	end
	origNew = MatchSession.new
	MatchSession.new = newHook

	destroyHook = function(self, ...)
		if self == session then
			session = nil
		end
		return origDestroy(self, ...)
	end
	origDestroy = MatchSession.destroy
	MatchSession.destroy = destroyHook
end

-- registry fallback for sessions created before we loaded
local function scanForSession()
	if session ~= nil or MatchSession == nil then
		return
	end
	local reg = getreg()
	for _, v in ipairs(reg) do
		if type(v) == "table" then
			local mt = getmetatable(v)
			if mt == MatchSession or (type(mt) == "table" and rawget(mt, "__index") == MatchSession) then
				if type(v.match) == "table" and v.own ~= nil then
					adoptSession(v)
					return
				end
			end
		end
	end
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

local function drawESP()
	if not (CFG.path or CFG.goals) or dead or not drawingOK then
		hideAll()
		return
	end
	local s = session
	local match = s and s.match
	if not match or not s.own then
		hideAll()
		return
	end
	local ball = ballOf(match)
	local cam = workspace.CurrentCamera
	if not ball or not cam then
		hideAll()
		return
	end
	local used = 0

	if CFG.path then
		local n = 18
		local pvx, pvy = nil, nil
		local p0 = cam:WorldToViewportPoint(Vector3.new(ball.pos.x, ball.pos.y, ball.pos.z))
		if p0.Z > 0 then
			pvx, pvy = p0.X, p0.Y
		end
		for i = 1, n do
			local x, y, z = ballAt(ball, CFG.pathLen * i / n)
			local v = cam:WorldToViewportPoint(Vector3.new(x, y, z))
			if v.Z > 0 and pvx then
				used += 1
				local ln = seg(used)
				ln.From = Vector2.new(pvx, pvy)
				ln.To = Vector2.new(v.X, v.Y)
				local k = i / n
				ln.Color = Color3.new(1, 1 - k * 0.8, 0.15)
				ln.Visible = true
			end
			if v.Z > 0 then
				pvx, pvy = v.X, v.Y
			else
				pvx = nil
			end
		end
	end

	if CFG.goals then
		local my = mySide or 1
		local marks = {
			{ 0, -my * GOAL_Y, MOUTH_Z, Color3.fromRGB(255, 70, 70) }, -- enemy mouth
			{ 0, my * GOAL_Y, MOUTH_Z, Color3.fromRGB(90, 255, 120) }, -- own mouth
		}
		for _, g in ipairs(marks) do
			local v = cam:WorldToViewportPoint(Vector3.new(g[1], g[2], g[3]))
			if v.Z > 0 then
				for _, d in ipairs({ { -16, -16, 16, 16 }, { -16, 16, 16, -16 } }) do
					used += 1
					local ln = seg(used)
					ln.From = Vector2.new(v.X + d[1], v.Y + d[2])
					ln.To = Vector2.new(v.X + d[3], v.Y + d[4])
					ln.Color = g[4]
					ln.Visible = true
				end
			end
		end
	end

	for i = used + 1, #segs do
		segs[i].Visible = false
	end
end

local function updateStats()
	local now = os.clock()
	if now - lastStatAt < 0.2 then
		return
	end
	lastStatAt = now
	local spd, bst = 0, 0
	local s = session
	if s and s.match and s.own then
		local entry = s.match.cars[s.own]
		local car = entry and entry.car
		if car and car.body then
			local v = car.body.vel
			spd = math.floor(math.sqrt(v.x ^ 2 + v.y ^ 2 + v.z ^ 2) + 0.5)
			bst = math.floor((car.boost or 0) + 0.5)
		end
	end
	if speedStat then
		pcall(function() speedStat:Set(spd) end)
	end
	if boostStat then
		pcall(function() boostStat:Set(bst) end)
	end
end

--// lifecycle ------------------------------------------------------------------
local function panic()
	CFG.pilot = false
	CFG.path = false
	CFG.goals = false
	if window then
		for _, f in ipairs({ "pilot", "path", "goals" }) do
			pcall(function() window:Set(f, false) end)
		end
	end
	print("[CarPilot] panic: pilot + visuals off")
end

local function shutdown()
	if dead then
		return
	end
	dead = true
	if hbConn then hbConn:Disconnect() hbConn = nil end
	if renderConn then renderConn:Disconnect() renderConn = nil end
	if keyConn then keyConn:Disconnect() keyConn = nil end
	for _, s in ipairs(segs) do
		pcall(function() s:Remove() end)
	end
	if Protocol.quantize == quantizeHook then
		Protocol.quantize = origQuantize
	end
	if MatchSession then
		if MatchSession.new == newHook then
			MatchSession.new = origNew
		end
		if MatchSession.destroy == destroyHook then
			MatchSession.destroy = origDestroy
		end
	end
	session = nil
	if window then
		pcall(function() window:Unload() end)
	end
	_G.CarSoccer = nil
	print("[CarPilot] unloaded")
end

keyConn = UserInputService.InputBegan:Connect(function(i, gp)
	if gp then return end
	if i.KeyCode == Enum.KeyCode.P then
		panic()
	end
end)

local scanClock = 0
hbConn = RunService.Heartbeat:Connect(function(dt)
	if dead then return end
	if session ~= nil and (session.match == nil or session.own == nil) then
		session = nil
	end
	scanClock += dt
	if scanClock > 1.5 and session == nil then
		scanClock = 0
		pcall(scanForSession)
	end
end)

renderConn = RunService.RenderStepped:Connect(function()
	if dead then return end
	drawESP()
	updateStats()
end)

--// UI -------------------------------------------------------------------------
local Rayfield
pcall(function() Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))() end)

local function buildUI()
	if not Rayfield then return end
	local w = Rayfield:CreateWindow({
		Name = "CARSOCCER | PILOT",
		LoadingTitle = "CAR PILOT",
		LoadingSubtitle = "client-sim autopilot",
		KeySystem = false,
	})
	window = w
	local drive = w:CreateTab({ name = "DRIVE" })
	local view = w:CreateTab({ name = "VIEW" })
	local sys = w:CreateTab({ name = "SYS" })

	drive:CreateToggle({ name = "autopilot", description = "drives the car through the live controls channel - the same one the game bot uses", flag = "pilot", value = CFG.pilot, callback = function(v) CFG.pilot = v end })
	drive:CreateDropdown({ name = "style", options = { "striker", "defender", "chase" }, value = CFG.mode, flag = "mode", callback = function(v) CFG.mode = v end })
	drive:CreateToggle({ name = "smart boost", description = "boost only when lined up and below supersonic", flag = "sboost", value = CFG.smartBoost, callback = function(v) CFG.smartBoost = v end })
	drive:CreateToggle({ name = "auto jump", description = "pop the ball when it hangs over the hood", flag = "ajump", value = CFG.autoJump, callback = function(v) CFG.autoJump = v end })
	drive:CreateSlider({ name = "contact offset", description = "studs behind the ball the pilot aims at", range = { 80, 320 }, increment = 10, value = CFG.offset, suffix = " st", callback = function(v) CFG.offset = v end })
	drive:CreateSlider({ name = "steer gain", description = "steering aggression toward the aim point", range = { 1.5, 5 }, increment = .1, value = CFG.steerGain, callback = function(v) CFG.steerGain = v end })
	drive:CreateSlider({ name = "ball look-ahead", description = "seconds of ball travel the pilot plans against", range = { .15, 1 }, increment = .05, value = CFG.look, suffix = " s", callback = function(v) CFG.look = v end })

	speedStat = drive:CreateStat({ name = "speed", value = 0, suffix = " u/s" })
	boostStat = drive:CreateStat({ name = "boost", value = 0, suffix = "" })

	view:CreateToggle({ name = "ball path", description = "predicted ball line - yellow now, red later", flag = "path", value = CFG.path, callback = function(v) CFG.path = v end })
	view:CreateToggle({ name = "goal markers", description = "crosshair on both mouths - red is the one you score in", flag = "goals", value = CFG.goals, callback = function(v) CFG.goals = v end })
	view:CreateSlider({ name = "path length", range = { .5, 3 }, increment = .25, value = CFG.pathLen, suffix = " s", callback = function(v) CFG.pathLen = v end })

	sys:CreateButton({ name = "panic (P)", description = "autopilot + visuals off, body untouched", callback = panic })
	sys:CreateButton({ name = "unload panel", description = "tear everything down", callback = shutdown })
end

buildUI()

_G.CarSoccer = { cfg = CFG, stop = shutdown, panic = panic }

local status = (MatchSession and "hooks armed - waiting for a match" or "MatchSession not found - pilot disabled")
	.. (drawingOK and "" or " | Drawing unavailable - ESP off")
print("[CarPilot] panel loaded - autopilot, ball path ESP, speed readout | " .. status)
end

--// embedded suite: skyview  (from skyview.luau) =========================
Hub.SUITE.skyview = function()
--[[
	SKYVIEW UTILITY -- FD6 - The Skyview Experience
	place 131576717722076 | Rayfield Gen2 | replace-not-stack via _G.SkyviewPanel

	what it does
	  players  : esp (name, distance, health bar, box, tracer), player list, teleport
	  movement : walk speed, jump power, infinite jump, noclip
	  visuals  : fullbright, no fog, fov
	  misc     : rejoin, panic (P), unload

	nothing here fires remotes or writes game state. it reads the character and
	the camera, and moves your own humanoid.

	_G exports
	  _G.SkyviewPanel.cfg      live config table
	  _G.SkyviewPanel.stop     unload
	  _G.SkyviewPanel.panic    turn every feature off
	  _G.SkyviewPanel.esp      esp pool (workspace drawings)
--]]

local prev = _G.SkyviewPanel
local CFG = (prev and prev.cfg) or {}
for k, v in pairs({
	esp = false,
	espName = true,
	espDistance = true,
	espHealth = true,
	espBox = true,
	espTracer = true,
	customSpeed = false,
	walkSpeed = 32,
	customJump = false,
	jumpPower = 90,
	infiniteJump = false,
	noclip = false,
	fullbright = false,
	noFog = false,
	fovOn = false,
	fov = 70,
}) do
	if CFG[k] == nil then CFG[k] = v end
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local LP = Players.LocalPlayer

-- replace-not-stack: a re-run has to take the previous copy down first
if prev and prev.stop then
	pcall(prev.stop)
end

--// cfg file --------------------------------------------------------------------
-- switches survive an executor restart. best-effort, never fatal.

local CFG_FILE = "slimhub-skyview.cfg"

local function loadCfg()
	if not (isfile and readfile and isfile(CFG_FILE)) then return end
	local ok, data = pcall(readfile, CFG_FILE)
	if not ok or type(data) ~= "string" then return end
	for line in string.gmatch(data, "[^\r\n]+") do
		local k, v = string.match(line, "^([%w_]+)=(.*)$")
		if k and CFG[k] ~= nil then
			if v == "true" then
				CFG[k] = true
			elseif v == "false" then
				CFG[k] = false
			elseif tonumber(v) then
				CFG[k] = tonumber(v)
			end
		end
	end
end

local savedCfg = ""
local function saveCfg()
	if not writefile then return end
	local parts = {}
	for k, v in pairs(CFG) do
		local t = type(v)
		if t == "boolean" or t == "number" then
			table.insert(parts, k .. "=" .. tostring(v))
		end
	end
	table.sort(parts)
	local blob = table.concat(parts, "\n")
	if blob == savedCfg then return end
	savedCfg = blob
	pcall(writefile, CFG_FILE, blob)
end

if not prev then
	pcall(loadCfg)
end

--// state -----------------------------------------------------------------------

local dead = false
local ui = {}
local status = "idle"
local log = {}
local selectedPlayer = nil
local originalFov = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or 70

local function now()
	return os.clock()
end

local function pushLog(text)
	table.insert(log, 1, os.date("%H:%M:%S") .. "  " .. text)
	while #log > 8 do
		table.remove(log)
	end
end

local function notify(text)
	print("[SKYVIEW] " .. tostring(text))
	if ui.window and ui.window.Notify then
		pcall(function()
			ui.window:Notify({ title = "SKYVIEW", content = tostring(text), duration = 3 })
		end)
	end
	pushLog(tostring(text))
end

--// drawing pool ----------------------------------------------------------------

local drawings = {}

local function newDrawing(cls)
	local ok, d = pcall(function()
		return Drawing.new(cls)
	end)
	if ok and d then
		table.insert(drawings, d)
		return d
	end
	return nil
end

local function removeDrawing(d)
	if not d then return end
	pcall(function()
		d.Visible = false
		d:Remove()
	end)
end

local function clearDrawings()
	for _, d in ipairs(drawings) do
		pcall(function()
			d.Visible = false
			d:Remove()
		end)
	end
	drawings = {}
end

--// esp -------------------------------------------------------------------------

local espCache = {}

local function espFor(plr)
	local e = espCache[plr]
	if e then return e end
	e = {}
	e.box = newDrawing("Square")
	e.hpBg = newDrawing("Square")
	e.hpFill = newDrawing("Square")
	e.tracer = newDrawing("Line")
	e.name = newDrawing("Text")
	e.dist = newDrawing("Text")

	if e.box then
		e.box.Thickness = 1
		e.box.Filled = false
		e.box.Color = Color3.fromRGB(120, 215, 255)
		e.box.Transparency = 0.45
	end
	if e.hpBg then
		e.hpBg.Thickness = 1
		e.hpBg.Filled = true
		e.hpBg.Color = Color3.fromRGB(15, 15, 18)
		e.hpBg.Transparency = 0.35
	end
	if e.hpFill then
		e.hpFill.Thickness = 1
		e.hpFill.Filled = true
		e.hpFill.Color = Color3.fromRGB(90, 230, 120)
	end
	if e.tracer then
		e.tracer.Thickness = 1
		e.tracer.Transparency = 0.55
		e.tracer.Color = Color3.fromRGB(120, 215, 255)
	end
	if e.name then
		e.name.Size = 13
		e.name.Center = true
		e.name.Outline = true
		e.name.OutlineColor = Color3.fromRGB(0, 0, 0)
		e.name.Font = 2
		e.name.Color = Color3.fromRGB(255, 255, 255)
	end
	if e.dist then
		e.dist.Size = 11
		e.dist.Center = true
		e.dist.Outline = true
		e.dist.OutlineColor = Color3.fromRGB(0, 0, 0)
		e.dist.Font = 2
		e.dist.Color = Color3.fromRGB(200, 210, 220)
	end

	espCache[plr] = e
	return e
end

local function hideEsp(e)
	if not e then return end
	for _, key in ipairs({ "box", "hpBg", "hpFill", "tracer", "name", "dist" }) do
		local d = e[key]
		if d then d.Visible = false end
	end
end

local function dropEsp(plr)
	local e = espCache[plr]
	if not e then return end
	for _, key in ipairs({ "box", "hpBg", "hpFill", "tracer", "name", "dist" }) do
		removeDrawing(e[key])
	end
	espCache[plr] = nil
end

local function hpColor(frac)
	if frac > 0.6 then return Color3.fromRGB(90, 230, 120) end
	if frac > 0.3 then return Color3.fromRGB(250, 210, 80) end
	return Color3.fromRGB(240, 80, 80)
end

local function espTick()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	local myChar = LP.Character
	local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
	local myPos = myRoot and myRoot.Position or Vector3.zero

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == LP then continue end
		local e = espFor(plr)
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local head = char and char:FindFirstChild("Head")

		if CFG.esp and char and hum and hrp and head and hum.Health > 0 then
			local headScreen, headOn = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 0.75, 0))
			local feetScreen, feetOn = cam:WorldToViewportPoint(hrp.Position - Vector3.new(0, 2.7, 0))
			local visible = headOn and feetOn and headScreen.Z > 0 and feetScreen.Z > 0
			if visible then
				if headScreen.X < -120 or headScreen.X > vp.X + 120 or headScreen.Y < -120 or headScreen.Y > vp.Y + 120 then
					visible = false
				end
			end

			if visible then
				local height = math.clamp(math.abs(feetScreen.Y - headScreen.Y), 26, 420)
				local width = math.clamp(height * 0.42, 18, 220)
				local left = headScreen.X - width / 2
				local top = headScreen.Y
				local bottom = top + height

				if e.box then
					e.box.Visible = CFG.espBox
					e.box.Size = Vector2.new(width, height)
					e.box.Position = Vector2.new(left, top)
				end

				if e.hpBg and e.hpFill then
					local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
					local barH = height * frac
					e.hpBg.Visible = CFG.espHealth
					e.hpBg.Size = Vector2.new(3, height)
					e.hpBg.Position = Vector2.new(left - 8, top)
					e.hpFill.Visible = CFG.espHealth and frac > 0
					e.hpFill.Size = Vector2.new(3, barH)
					e.hpFill.Position = Vector2.new(left - 8, bottom - barH)
					e.hpFill.Color = hpColor(frac)
				end

				if e.name then
					e.name.Visible = CFG.espName
					e.name.Text = plr.Name
					e.name.Position = Vector2.new(headScreen.X, top - 20)
				end
				if e.dist then
					e.dist.Visible = CFG.espDistance
					e.dist.Text = string.format("%d studs", math.floor((hrp.Position - myPos).Magnitude))
					e.dist.Position = Vector2.new(headScreen.X, top - 7)
				end
				if e.tracer then
					e.tracer.Visible = CFG.espTracer
					e.tracer.From = Vector2.new(vp.X / 2, vp.Y)
					e.tracer.To = Vector2.new(headScreen.X, top + height * 0.5)
				end
			else
				hideEsp(e)
			end
		else
			hideEsp(e)
		end
	end
end

--// movement --------------------------------------------------------------------

local noclipSaved = {}

local function saveNoclipParts(char)
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") and noclipSaved[part] == nil then
			noclipSaved[part] = part.CanCollide
		end
	end
end

local function restoreNoclip()
	for part, value in pairs(noclipSaved) do
		if part.Parent then
			pcall(function() part.CanCollide = value end)
		end
	end
	noclipSaved = {}
end

local function movementTick()
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	if CFG.customSpeed then
		if hum.WalkSpeed ~= CFG.walkSpeed then
			hum.WalkSpeed = CFG.walkSpeed
		end
	end
	if CFG.customJump then
		if not hum.UseJumpPower then
			hum.UseJumpPower = true
		end
		if hum.JumpPower ~= CFG.jumpPower then
			hum.JumpPower = CFG.jumpPower
		end
	end

	if CFG.noclip then
		saveNoclipParts(char)
		for part in pairs(noclipSaved) do
			if part.Parent and part.CanCollide then
				part.CanCollide = false
			end
		end
	elseif next(noclipSaved) ~= nil then
		restoreNoclip()
	end

	if CFG.fovOn then
		local cam = workspace.CurrentCamera
		if cam and cam.FieldOfView ~= CFG.fov then
			cam.FieldOfView = CFG.fov
		end
	end
end

local jumpConn = UserInputService.JumpRequest:Connect(function()
	if dead or not CFG.infiniteJump then return end
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	if hum:GetState() ~= Enum.HumanoidStateType.Jumping and hum:GetState() ~= Enum.HumanoidStateType.Freefall then
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end)

--// visuals ---------------------------------------------------------------------

local lightSaved = nil

local function applyFullbright()
	if lightSaved then return end
	lightSaved = {
		Brightness = Lighting.Brightness,
		ClockTime = Lighting.ClockTime,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		GlobalShadows = Lighting.GlobalShadows,
		EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
		EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
	}
	Lighting.Brightness = 3
	Lighting.ClockTime = 14
	Lighting.Ambient = Color3.fromRGB(170, 170, 170)
	Lighting.OutdoorAmbient = Color3.fromRGB(170, 170, 170)
	Lighting.GlobalShadows = false
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
end

local function restoreFullbright()
	if not lightSaved then return end
	for k, v in pairs(lightSaved) do
		pcall(function() Lighting[k] = v end)
	end
	lightSaved = nil
end

local fogSaved = nil

local function applyNoFog()
	if fogSaved then return end
	fogSaved = {
		FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart,
	}
	Lighting.FogEnd = 100000
	Lighting.FogStart = 100000
end

local function restoreNoFog()
	if not fogSaved then return end
	for k, v in pairs(fogSaved) do
		pcall(function() Lighting[k] = v end)
	end
	fogSaved = nil
end

local function restoreVisuals()
	restoreFullbright()
	restoreNoFog()
	if workspace.CurrentCamera then
		workspace.CurrentCamera.FieldOfView = originalFov
	end
end

--// action helpers --------------------------------------------------------------

local function playerNames()
	local names = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP then
			table.insert(names, p.Name)
		end
	end
	table.sort(names)
	return names
end

local function teleportTo(name)
	local target = name and Players:FindFirstChild(name)
	local char = target and target.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local myChar = LP.Character
	local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
	if not (hrp and myHrp) then
		return false, "no target"
	end
	myHrp.CFrame = hrp.CFrame * CFrame.new(0, 0, 3)
	return true
end

local function rejoin()
	notify("rejoining")
	pcall(function()
		TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
	end)
end

local function setEsp(on)
	CFG.esp = on
	if not on then
		for _, e in pairs(espCache) do hideEsp(e) end
	end
end

--// panic / shutdown ------------------------------------------------------------

local removingConn
local panic

local function shutdown()
	if dead then return end
	dead = true
	if jumpConn then pcall(function() jumpConn:Disconnect() end) end
	if ui.loopConn then pcall(function() ui.loopConn:Disconnect() end) end
	if ui.keyConn then pcall(function() ui.keyConn:Disconnect() end) end
	if removingConn then pcall(function() removingConn:Disconnect() end) end
	restoreNoclip()
	restoreVisuals()
	clearDrawings()
	espCache = {}
	if ui.window then pcall(function() ui.window:Unload() end) end
	_G.SkyviewPanel = { cfg = CFG }
	print("[SKYVIEW] unloaded")
end

panic = function()
	if dead then return end
	CFG.esp = false
	CFG.customSpeed = false
	CFG.customJump = false
	CFG.infiniteJump = false
	CFG.noclip = false
	CFG.fullbright = false
	CFG.noFog = false
	CFG.fovOn = false
	restoreNoclip()
	restoreVisuals()
	for _, e in pairs(espCache) do hideEsp(e) end
	if ui.window then
		for _, flag in ipairs({
			"sky_esp", "sky_speed", "sky_jump", "sky_infjump", "sky_noclip",
			"sky_fullbright", "sky_nofog", "sky_fovon",
		}) do
			pcall(function() ui.window:Set(flag, false) end)
		end
	end
	status = "panic  |  everything off"
	pushLog("panic")
	print("[SKYVIEW] panic")
end

--// UI --------------------------------------------------------------------------

local Rayfield
pcall(function()
	Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)

local function buildUI()
	if not Rayfield then
		warn("[SKYVIEW] Rayfield failed to load")
		return
	end

	local w = Rayfield:CreateWindow({
		Name = "SKYVIEW // UTILITY",
		LoadingTitle = "FD6 - THE SKYVIEW EXPERIENCE",
		LoadingSubtitle = "esp  -  teleport  -  movement",
		KeySystem = false,
	})
	ui.window = w

	pcall(function()
		w:ChangeTheme({
			WindowColor = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 12, 18)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 24, 34)),
			}),
			ShadowColor = Color3.fromRGB(4, 6, 10),
			CornerRoundness = UDim.new(0, 16),
			ElementCornerRadius = UDim.new(0, 10),
			PillCornerRadius = UDim.new(1, 0),
			AccentColor = Color3.fromRGB(120, 215, 255),
		})
	end)

	-- PLAYERS
	local playersTab = w:CreateTab({ Name = "PLAYERS" })
	playersTab:CreateSection({ Name = "ESP" })
	playersTab:CreateToggle({
		Name = "player esp",
		Description = "draws every other player through walls with name, distance, health and a tracer.",
		Flag = "sky_esp",
		Value = CFG.esp,
		Callback = function(v)
			setEsp(v)
		end,
	})
	playersTab:CreateToggle({
		Name = "names",
		Flag = "sky_espname",
		Value = CFG.espName,
		Callback = function(v) CFG.espName = v end,
	})
	playersTab:CreateToggle({
		Name = "distance",
		Flag = "sky_espdist",
		Value = CFG.espDistance,
		Callback = function(v) CFG.espDistance = v end,
	})
	playersTab:CreateToggle({
		Name = "health bar",
		Flag = "sky_esphealth",
		Value = CFG.espHealth,
		Callback = function(v) CFG.espHealth = v end,
	})
	playersTab:CreateToggle({
		Name = "box",
		Flag = "sky_espbox",
		Value = CFG.espBox,
		Callback = function(v) CFG.espBox = v end,
	})
	playersTab:CreateToggle({
		Name = "tracer",
		Flag = "sky_esptracer",
		Value = CFG.espTracer,
		Callback = function(v) CFG.espTracer = v end,
	})

	playersTab:CreateSection({ Name = "TELEPORT" })
	ui.playerDrop = playersTab:CreateDropdown({
		Name = "player",
		Description = "pick who to stand next to.",
		Options = playerNames(),
		Placeholder = "nobody picked",
		Flag = "sky_target",
		Callback = function(v)
			selectedPlayer = v
		end,
	})
	playersTab:CreateButton({
		Name = "refresh player list",
		Callback = function()
			if ui.playerDrop then
				pcall(function() ui.playerDrop:Refresh(playerNames()) end)
				notify("player list refreshed")
			end
		end,
	})
	playersTab:CreateButton({
		Name = "teleport to player",
		Callback = function()
			if not selectedPlayer then
				notify("pick a player first")
				return
			end
			local ok, err = teleportTo(selectedPlayer)
			notify(ok and ("teleported to " .. selectedPlayer) or ("teleport failed: " .. tostring(err)))
		end,
	})

	-- MOVEMENT
	local moveTab = w:CreateTab({ Name = "MOVEMENT" })
	moveTab:CreateSection({ Name = "SPEED" })
	moveTab:CreateToggle({
		Name = "custom walk speed",
		Description = "holds your walk speed against the game's sprint script.",
		Flag = "sky_speed",
		Value = CFG.customSpeed,
		Callback = function(v) CFG.customSpeed = v end,
	})
	moveTab:CreateSlider({
		Name = "walk speed",
		Range = { 16, 120 },
		Increment = 1,
		Value = CFG.walkSpeed,
		Suffix = " ws",
		Flag = "sky_walkspeed",
		Callback = function(v) CFG.walkSpeed = v end,
	})

	moveTab:CreateSection({ Name = "JUMP" })
	moveTab:CreateToggle({
		Name = "custom jump power",
		Flag = "sky_jump",
		Value = CFG.customJump,
		Callback = function(v) CFG.customJump = v end,
	})
	moveTab:CreateSlider({
		Name = "jump power",
		Range = { 50, 250 },
		Increment = 5,
		Value = CFG.jumpPower,
		Suffix = " jp",
		Flag = "sky_jumppower",
		Callback = function(v) CFG.jumpPower = v end,
	})
	moveTab:CreateToggle({
		Name = "infinite jump",
		Description = "every jump request re-enters the jumping state, so you can keep climbing.",
		Flag = "sky_infjump",
		Value = CFG.infiniteJump,
		Callback = function(v) CFG.infiniteJump = v end,
	})

	moveTab:CreateSection({ Name = "COLLISION" })
	moveTab:CreateToggle({
		Name = "noclip",
		Description = "turns collision off on your own character only, and puts it back when you switch off.",
		Flag = "sky_noclip",
		Value = CFG.noclip,
		Callback = function(v)
			CFG.noclip = v
			if not v then restoreNoclip() end
		end,
	})

	-- VISUALS
	local visTab = w:CreateTab({ Name = "VISUALS" })
	visTab:CreateToggle({
		Name = "fullbright",
		Description = "max brightness, no shadows, daylight clock. restores the exact original values on off.",
		Flag = "sky_fullbright",
		Value = CFG.fullbright,
		Callback = function(v)
			CFG.fullbright = v
			if v then applyFullbright() else restoreFullbright() end
		end,
	})
	visTab:CreateToggle({
		Name = "no fog",
		Flag = "sky_nofog",
		Value = CFG.noFog,
		Callback = function(v)
			CFG.noFog = v
			if v then applyNoFog() else restoreNoFog() end
		end,
	})
	visTab:CreateToggle({
		Name = "custom fov",
		Description = "holds your field of view against the game's own camera.",
		Flag = "sky_fovon",
		Value = CFG.fovOn,
		Callback = function(v) CFG.fovOn = v end,
	})
	visTab:CreateSlider({
		Name = "field of view",
		Range = { 70, 120 },
		Increment = 1,
		Value = CFG.fov,
		Suffix = " fov",
		Flag = "sky_fov",
		Callback = function(v)
			CFG.fov = v
		end,
	})

	-- MISC
	local miscTab = w:CreateTab({ Name = "MISC" })
	ui.card = miscTab:CreateText({ Name = "state", Text = "starting" })
	miscTab:CreateButton({
		Name = "rejoin server",
		Callback = function() rejoin() end,
	})
	miscTab:CreateButton({
		Name = "panic  (P)",
		Description = "turns every feature off and restores lighting, collision and fov.",
		Callback = function() panic() end,
	})
	miscTab:CreateButton({
		Name = "unload",
		Callback = function() shutdown() end,
	})
	miscTab:CreateText({
		Name = "keys",
		Text = "P = panic   |   the panel replaces itself instead of stacking.",
	})
	ui.logText = miscTab:CreateText({ Name = "log", Text = "-" })
end

--// loop ------------------------------------------------------------------------

local lastSync = 0
local lastSave = 0

local function tick()
	if dead then return end
	movementTick()
	if CFG.esp then
		pcall(espTick)
	else
		for _, e in pairs(espCache) do hideEsp(e) end
	end

	local t = now()
	if t - lastSync > 0.4 then
		lastSync = t
		local char = LP.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		status = string.format(
			"%d players  |  esp %s  |  ws %s  |  jp %s  |  noclip %s",
			#Players:GetPlayers(),
			CFG.esp and "on" or "off",
			hum and tostring(math.floor(hum.WalkSpeed)) or "-",
			hum and tostring(math.floor(hum.JumpPower)) or "-",
			CFG.noclip and "on" or "off"
		)
		if ui.card then pcall(function() ui.card:Set(status) end) end
		if ui.logText then pcall(function() ui.logText:Set(#log > 0 and table.concat(log, "\n") or "-") end) end
	end
	if t - lastSave > 4 then
		lastSave = t
		pcall(saveCfg)
	end
end

buildUI()

if ui.window then
	local conn
	conn = UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.P then
			panic()
		end
	end)
	ui.keyConn = conn
end

ui.loopConn = RunService.Heartbeat:Connect(function()
	local ok, err = pcall(tick)
	if not ok then
		warn("[SKYVIEW] tick error: " .. tostring(err))
	end
end)

removingConn = Players.PlayerRemoving:Connect(function(plr)
	dropEsp(plr)
end)

pushLog("panel loaded")
pcall(saveCfg)

_G.SkyviewPanel = {
	cfg = CFG,
	window = ui.window,
	esp = espCache,
	stop = shutdown,
	panic = panic,
	teleport = teleportTo,
}

print("[SKYVIEW] panel loaded - esp, teleport, movement")
end

--// embedded suite: superhero  (from superhero.luau) =========================
Hub.SUITE.superhero = function()
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
local TweenService = game:GetService("TweenService")
local VirtualInputManager
pcall(function()
	VirtualInputManager = game:GetService("VirtualInputManager")
end)
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
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and visible(d) then
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
			local txt = d:IsA("TextButton") and (d.Text or "") or ""
			if not string.match(txt, "^%s*[%d,%.]+%s*$") then
				buttons[#buttons + 1] = d
			end
		elseif d:IsA("TextLabel") and visible(d) then
			local txt = d.Text or ""
			if string.find(txt, "+", 1, true)
				and d.AbsoluteSize.X <= 80 and d.AbsoluteSize.Y <= 80 then
				buttons[#buttons + 1] = d
			end
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
			if dx > 0 and dx < 700 and dy <= tolerance then
				local score = dx
				local plusText = false
				if btn:IsA("TextLabel") then
					plusText = true
				elseif btn:IsA("TextButton") then
					plusText = string.find(tostring(btn.Text or ""), "+", 1, true) ~= nil
				end
				if plusText then
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
	if not btn or not btn:IsA("GuiButton") then return false end
	if type(firesignal) ~= "function" then return false end
	return pcall(firesignal, btn.MouseButton1Click)
end

local function panelCovers(x, y)
	local s = ownScreen
	if not s or not s.Enabled then return false end
	local p = s:FindFirstChild("Main")
	if not p then return false end
	local pos = p.AbsolutePosition
	local size = p.AbsoluteSize
	return x >= pos.X and x <= pos.X + size.X
		and y >= pos.Y and y <= pos.Y + size.Y
end

local function virtualClick(btn)
	if not VirtualInputManager then return false end
	local x, y = center(btn)
	local hide = panelCovers(x, y)
	if hide then
		ownScreen.Enabled = false
		task.wait(0.05)
	end
	local ok = pcall(function()
		VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
		task.wait(0.03)
		VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
	end)
	if hide and ownScreen then
		ownScreen.Enabled = true
	end
	return ok
end

local function clickButton(btn)
	if not btn then return false end
	if CFG.clickMethod == "signal" then return signal(btn) end
	if CFG.clickMethod == "virtual" then return virtualClick(btn) end
	-- auto: a real mouse event hits MouseButton1Click, Activated and
	-- InputBegan alike. signal only works when the game used that event.
	if virtualClick(btn) then return true end
	return signal(btn)
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
	local function bestIn(class)
		local best = nil
		local bestSize = nil
		for _, btn in ipairs(guiObjects(class)) do
			local txt
			if btn:IsA("TextButton") or btn:IsA("TextLabel") then
				txt = string.lower(btn.Text or "")
			else
				txt = string.lower(btn.Name or "")
			end
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
	local btn = bestIn("TextButton")
	if btn then return btn end
	btn = bestIn("ImageButton")
	if btn then return btn end
	-- some menus draw the roll control as a plain row/label with an
	-- InputBegan handler. clicking its centre still works.
	return bestIn("TextLabel")
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

local function safeText(obj)
	if not obj then return "" end
	if obj:IsA("TextButton") or obj:IsA("TextLabel") then
		return obj.Text or ""
	end
	return ""
end

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
					d:GetFullName(), safeText(d), math.floor(x), math.floor(y),
					math.floor(d.AbsoluteSize.X), math.floor(d.AbsoluteSize.Y))
			end
		end
		for _, stat in ipairs(STATS) do
			local btn = findPlus(stat)
			if btn then
				lines[#lines + 1] = "PLUS " .. stat .. " -> " .. btn:GetFullName() .. "  text=" .. safeText(btn)
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

local startX = math.max(18, vp.X / scale - W - 18)
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
	"auto sends a real mouse click first, then falls back to firesignal. pick signal if your executor blocks virtual input, or virtual to force a real click.",
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
print("[SUPERHERO] panel is docked right - drag it by the title bar if it covers the game menu")
end

--// embedded suite: criminal  (from criminal.luau) =========================
Hub.SUITE.criminal = function()
--[[
	CRIMINAL SIMULATOR -- heist panel
	place 83048653078891 (root) / universe 10769851460 / live sub-place 73251213967624
	Rayfield Gen2 | replace-not-stack via _G.CriminalPanel

	what it does
	  loot    : esp with display name, value, weight and distance, value/range filters,
	            nearest and highest-value teleports, best-effort grab + truck loading,
	            a one-shot haul that grabs every matching item in range and releases
	            it at the nearest truck cargo zone, plus an auto haul loop and a max
	            item limit.
	  world   : npc esp (residents / guards / police) with optional detail tags, a live
	            npc details window (health, distance, state, gender, outfit, home, spot)
	            and a full npc attribute dump, auto knockout with the game's own Punch
	            remote, auto escape to the hideout on nearby police, auto door opening,
	            prompt sniper for the game's own "Rob ..." and "Open" proximity prompts,
	            travel buttons for truck, sell box, chop shop, hideout, shop computer
	            and job board, plus a stealth / anti-detect section that fires the
	            game's own Sneak remote near npcs, reads the game's Sight<userId>
	            attribute and draws estimated npc sight cones. it silences walking
	            noise; it does not make you invisible to server-side sight or cameras.
	  players : esp, player list, teleport.
	  movement: walk speed, speed guard (safe cap + ramp), infinite stamina, jump power,
	            infinite jump, noclip, client-side fly.
	  visuals : fullbright, no fog, fov.
	  status  : cash, level, objective, quota, day/night, debt, difficulty, carried loot.
	  misc    : max mode preset, rejoin, panic (P), unload.

	what is verified live
	  - loot attributes (Value / Weight / DisplayName / HeldBy) and the game's LootGrab
	    remote work when the character is next to the loot and facing it.
	  - enabled proximity prompts can be fired from any distance (a mailbox at 94 m
	    spawned a loot cluster). disabled prompts stay inert.
	  - walk speed sticks when the game's own write is immediately overwritten with a
	    property-changed hook. the speed guard caps at the game's own sprint speed
	    (about 60) and ramps changes instead of snapping.
	  - infinite stamina uses the SprintClient's own God check: setting the local
	    God attribute keeps u70 full. a 0.75 s sprint held the bar at 100% with it on
	    and dropped to 89.5% with it off. it is local only and does not grant real
	    god mode.
	  - long direct cframe jumps can be pulled back by the server; stepTeleport moves in
	    small steps to make the trip survivable. still best-effort.

	what is not promised
	  - no cash/quota grant. the server owns the economy; this panel only uses the
	    game's own interaction paths.
	  - grabbing hidden/room loot, selling, and truck delivery depend on the game's
	    current container state. failures are reported, not hidden.

	_G exports
	  _G.CriminalPanel.cfg      live config table
	  _G.CriminalPanel.stop     unload
	  _G.CriminalPanel.panic    turn every feature off
	  _G.CriminalPanel.teleport step teleport helper
--]]

local prev = _G.CriminalPanel
local CFG = (prev and prev.cfg) or {}
for k, v in pairs({
	lootEsp = false,
	lootMinValue = 0,
	lootRadius = 0,
	lootMaxLabels = 90,
	lootHideHeld = true,
	lootOnlyLiftable = true,
	maxStrength = false,
	autoGrab = false,
	autoLoad = false,
	grabRadius = 500,
	haulRadius = 250,
	haulLimit = 0,
	autoHaul = false,
	autoHaulDelay = 30,
	autoKnockout = false,
	knockoutRadius = 25,
	knockoutPunches = 6,
	autoEscape = false,
	autoEscapeRadius = 60,
	autoDoors = false,
	autoDoorsRadius = 60,
	antiDetect = false,
	antiDetectRadius = 45,
	sightCones = false,
	sightConeRange = 55,
	sightWarn = true,
	fly = false,
	flySpeed = 80,
	npcEsp = false,
	npcResidents = true,
	npcGuards = true,
	npcPolice = true,
	npcName = true,
	npcDistance = true,
	npcHealth = true,
	npcBox = true,
	npcTags = false,
	npcDetails = false,
	autoRob = false,
	playerEsp = false,
	playerEspName = true,
	playerEspDistance = true,
	playerEspHealth = true,
	playerEspBox = true,
	playerEspTracer = true,
	customSpeed = false,
	walkSpeed = 60,
	speedGuard = true,
	speedCap = 60,
	speedNoCap = false,
	infiniteStamina = false,
	customJump = false,
	jumpPower = 120,
	infiniteJump = false,
	noclip = false,
	fullbright = false,
	noFog = false,
	fovOn = false,
	fov = 70,
}) do
	if CFG[k] == nil then CFG[k] = v end
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 20)

-- replace-not-stack: a re-run takes the previous copy down first
if prev and prev.stop then
	pcall(prev.stop)
end

--// cfg file --------------------------------------------------------------------

local CFG_FILE = "slimhub-criminal.cfg"

local function loadCfg()
	if not (isfile and readfile and isfile(CFG_FILE)) then return end
	local ok, data = pcall(readfile, CFG_FILE)
	if not ok or type(data) ~= "string" then return end
	for line in string.gmatch(data, "[^\r\n]+") do
		local k, v = string.match(line, "^([%w_]+)=(.*)$")
		if k and CFG[k] ~= nil then
			if v == "true" then
				CFG[k] = true
			elseif v == "false" then
				CFG[k] = false
			elseif tonumber(v) then
				CFG[k] = tonumber(v)
			end
		end
	end
end

local savedCfg = ""
local function saveCfg()
	if not writefile then return end
	local parts = {}
	for k, v in pairs(CFG) do
		local t = type(v)
		if t == "boolean" or t == "number" then
			table.insert(parts, k .. "=" .. tostring(v))
		end
	end
	table.sort(parts)
	local blob = table.concat(parts, "\n")
	if blob == savedCfg then return end
	savedCfg = blob
	pcall(writefile, CFG_FILE, blob)
end

if not prev then
	pcall(loadCfg)
end

--// state -----------------------------------------------------------------------

local dead = false
local ui = {}
local log = {}
local selectedPlayer = nil
local selectedNpc = nil
local npcOptions = {}
local originalFov = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or 70
local promptCooldown = setmetatable({}, { __mode = "k" })
local failedGrabAt = setmetatable({}, { __mode = "k" })
local grabbing = false
local lastGrabNotice = 0
local hauling = false
local haulStop = false
local lastAutoHaulAt = 0
local knockoutBusy = false
local knockoutStop = false
local knockoutCurrent = nil
local lastKnockoutNotice = 0
local failedKnockAt = setmetatable({}, { __mode = "k" })
local escaping = false
-- one table keeps the main chunk under luau's 200-local register limit.
local stealth = {
	owned = false,
	auto = false,
	lastNear = 0,
	lastSent = 0,
	lastScan = 0,
	lastSightNotice = 0,
	frame = 0,
	cones = {},
}

local function now()
	return os.clock()
end

local function comma(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then out = out:sub(2) end
	return out
end

local function money(n)
	return "$" .. comma(n)
end

local function pushLog(text)
	table.insert(log, 1, os.date("%H:%M:%S") .. "  " .. tostring(text))
	while #log > 8 do
		table.remove(log)
	end
end

local function notify(text)
	print("[CRIMINAL] " .. tostring(text))
	if ui.window and ui.window.Notify then
		pcall(function()
			ui.window:Notify({ title = "CRIMINAL", content = tostring(text), duration = 3 })
		end)
	end
	pushLog(text)
end

local function charRoot()
	local char = LP.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function charHumanoid()
	local char = LP.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function partOf(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst end
	if inst:IsA("Model") then
		return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

--// drawing pool ----------------------------------------------------------------

local drawings = {}
local drawingBroken = false

local function newDrawing(cls)
	if drawingBroken then return nil end
	local ok, d = pcall(function()
		return Drawing.new(cls)
	end)
	if ok and d then
		table.insert(drawings, d)
		return d
	end
	drawingBroken = true
	warn("[CRIMINAL] Drawing API unavailable")
	return nil
end

local function removeDrawing(d)
	if not d then return end
	pcall(function()
		d.Visible = false
		d:Remove()
	end)
end

local function clearDrawings()
	for _, d in ipairs(drawings) do
		pcall(function()
			d.Visible = false
			d:Remove()
		end)
	end
	drawings = {}
end

local function newSquare(filled, color, transparency, thickness)
	local d = newDrawing("Square")
	if not d then return nil end
	d.Filled = filled and true or false
	d.Color = color or Color3.fromRGB(255, 255, 255)
	d.Transparency = transparency or 0.4
	d.Thickness = thickness or 1
	return d
end

local function newText(size, center, outline)
	local d = newDrawing("Text")
	if not d then return nil end
	d.Size = size or 13
	d.Center = center and true or false
	d.Outline = outline ~= false
	d.OutlineColor = Color3.fromRGB(0, 0, 0)
	d.Font = 2
	d.Color = Color3.fromRGB(255, 255, 255)
	return d
end

local function newLine(color, transparency, thickness)
	local d = newDrawing("Line")
	if not d then return nil end
	d.Color = color or Color3.fromRGB(120, 215, 255)
	d.Transparency = transparency or 0.5
	d.Thickness = thickness or 1
	return d
end

--// loot -----------------------------------------------------------------------

local lootPool = {}
local lootList = {}
local lootScanAt = 0
local lootFrame = 0

local function lootColor(value)
	if value >= 600 then return Color3.fromRGB(255, 205, 90) end
	if value >= 300 then return Color3.fromRGB(120, 215, 255) end
	if value >= 100 then return Color3.fromRGB(120, 240, 140) end
	return Color3.fromRGB(210, 210, 220)
end

local function newLootEsp(model)
	local e = { model = model }
	e.dot = newSquare(true, Color3.fromRGB(210, 210, 220), 0.05, 1)
	e.label = newText(12, false, true)
	if e.label then
		e.label.Font = 2
	end
	return e
end

local function hideLootEsp(e)
	if not e then return end
	if e.dot then e.dot.Visible = false end
	if e.label then e.label.Visible = false end
end

local function dropLootEsp(model)
	local e = lootPool[model]
	if not e then return end
	removeDrawing(e.dot)
	removeDrawing(e.label)
	lootPool[model] = nil
end

local function heldByMe(item)
	local h = item:GetAttribute("HeldBy")
	return h ~= nil and tostring(h) == tostring(LP.UserId)
end

-- max strength: the game's Lifter upgrade caps at level 2 and the heaviest
-- loot in the catalog is weight 3, so level 2 lifts everything. Strong Back
-- is the gamepass that stops heavy loot slowing you; the game's own
-- SprintClient reads both attributes. Setting them locally only changes the
-- client - the server still owns the real purchase and can reject a grab.
local strength = {
	baseLifter = nil,
	baseStrong = nil,
	bumpedLifter = false,
	setStrong = false,
	lastCheck = 0,
}

function strength.apply()
	if dead or not CFG.maxStrength then return end
	local lifter = tonumber(LP:GetAttribute("Shop_Lifter")) or 0
	if lifter < 2 then
		if not strength.bumpedLifter then
			strength.baseLifter = LP:GetAttribute("Shop_Lifter")
		end
		pcall(function() LP:SetAttribute("Shop_Lifter", 2) end)
		strength.bumpedLifter = true
	end
	local strong = tonumber(LP:GetAttribute("Shop_StrongBack")) or 0
	if strong < 1 then
		if not strength.setStrong then
			strength.baseStrong = LP:GetAttribute("Shop_StrongBack")
		end
		pcall(function() LP:SetAttribute("Shop_StrongBack", 1) end)
		strength.setStrong = true
	end
end

function strength.restore()
	if strength.bumpedLifter and (tonumber(LP:GetAttribute("Shop_Lifter")) or 0) == 2 then
		pcall(function() LP:SetAttribute("Shop_Lifter", strength.baseLifter) end)
	end
	if strength.setStrong and (tonumber(LP:GetAttribute("Shop_StrongBack")) or 0) == 1 then
		pcall(function() LP:SetAttribute("Shop_StrongBack", strength.baseStrong) end)
	end
	strength.baseLifter = nil
	strength.baseStrong = nil
	strength.bumpedLifter = false
	strength.setStrong = false
end

function strength.set(on)
	if dead then return CFG.maxStrength end
	CFG.maxStrength = on and true or false
	if CFG.maxStrength then
		strength.apply()
	else
		strength.restore()
	end
	return CFG.maxStrength
end

function strength.tick()
	if not CFG.maxStrength then return end
	local t = os.clock()
	if t - strength.lastCheck < 1 then return end
	strength.lastCheck = t
	strength.apply()
end

local function liftable(item)
	if CFG.maxStrength then return true end
	local w = tonumber(item:GetAttribute("Weight")) or 1
	if item:GetAttribute("AnyoneLifts") == true then return true end
	if w < 2 then return true end
	local lifter = tonumber(LP:GetAttribute("Shop_Lifter")) or 0
	return lifter >= (w - 1)
end

local function refreshLoot(force)
	local t = now()
	if not force and t - lootScanAt < 0.15 then return lootList end
	lootScanAt = t

	lootList = {}
	local loot = workspace:FindFirstChild("Loot")
	local root = charRoot()
	if not loot or not root then return lootList end

	local myPos = root.Position
	local minValue = tonumber(CFG.lootMinValue) or 0
	local radius = tonumber(CFG.lootRadius) or 0

	for _, m in ipairs(loot:GetChildren()) do
		if m:IsA("Model") then
			local value = tonumber(m:GetAttribute("Value"))
			if value and value >= minValue then
				local part = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
				if part and part.Parent then
					local held = m:GetAttribute("HeldBy")
					local heldMe = held ~= nil and tostring(held) == tostring(LP.UserId)
					local keep = true
					if CFG.lootHideHeld and held ~= nil and not heldMe then keep = false end
					if keep and CFG.lootOnlyLiftable and not liftable(m) then keep = false end
					if keep then
						local d = (part.Position - myPos).Magnitude
						if radius <= 0 or d <= radius then
							lootList[#lootList + 1] = {
								model = m,
								part = part,
								name = tostring(m:GetAttribute("DisplayName") or m.Name),
								value = value,
								weight = tonumber(m:GetAttribute("Weight")) or 1,
								held = held,
								heldMe = heldMe,
								dist = d,
							}
						end
					end
				end
			end
		end
	end

	table.sort(lootList, function(a, b)
		return a.dist < b.dist
	end)
	return lootList
end

local function renderLoot()
	lootFrame = lootFrame + 1
	local frame = lootFrame
	local cam = workspace.CurrentCamera
	local root = charRoot()
	if not cam or not root then
		for _, e in pairs(lootPool) do hideLootEsp(e) end
		return
	end

	local list = refreshLoot(false)
	local maxLabels = math.clamp(tonumber(CFG.lootMaxLabels) or 90, 1, 300)
	local vp = cam.ViewportSize

	for i = 1, math.min(#list, maxLabels) do
		local item = list[i]
		if item.part.Parent then
			local sp, on = cam:WorldToViewportPoint(item.part.Position + Vector3.new(0, 0.8, 0))
			if on and sp.Z > 0 and sp.X > -20 and sp.X < vp.X - 10 and sp.Y > -20 and sp.Y < vp.Y + 20 then
				local e = lootPool[item.model]
				if not e then
					e = newLootEsp(item.model)
					lootPool[item.model] = e
				end
				if e.dot and e.label then
					local color = lootColor(item.value)
					if item.heldMe then color = Color3.fromRGB(120, 240, 140) end
					if item.held and not item.heldMe then color = Color3.fromRGB(150, 150, 150) end

					e.dot.Visible = true
					e.dot.Size = Vector2.new(7, 7)
					e.dot.Position = Vector2.new(sp.X - 3, sp.Y - 3)
					e.dot.Color = color
					e.dot.Transparency = item.held and not item.heldMe and 0.55 or 0.05

					local prefix = ""
					if item.heldMe then prefix = "[held] " elseif item.held then prefix = "[taken] " end
					e.label.Visible = true
					e.label.Text = string.format("%s%s  %s  %dw  %dm", prefix, item.name, money(item.value), item.weight, math.floor(item.dist))
					e.label.Position = Vector2.new(sp.X + 9, sp.Y - 7)
					e.label.Color = color
					e.label.Transparency = item.held and not item.heldMe and 0.5 or 0
				end
				e.usedFrame = frame
			end
		end
	end

	for model, e in pairs(lootPool) do
		if not model.Parent then
			dropLootEsp(model)
		elseif e.usedFrame ~= frame then
			hideLootEsp(e)
		end
	end
	lootFrame = frame
end

local function bestLoot(mode, maxDist)
	local list = refreshLoot(true)
	local best, bestScore = nil, nil
	for _, item in ipairs(list) do
		if not item.held and item.model.Parent then
			if maxDist <= 0 or item.dist <= maxDist then
				local score = (mode == "value") and item.value or -item.dist
				if best == nil or score > bestScore then
					best = item
					bestScore = score
				end
			end
		end
	end
	return best
end

local function findHeldLoot()
	local loot = workspace:FindFirstChild("Loot")
	if not loot then return nil end
	for _, m in ipairs(loot:GetChildren()) do
		if m:IsA("Model") and heldByMe(m) then return m end
	end
	return nil
end

--// step teleport --------------------------------------------------------------

local function stepTeleport(target)
	local root = charRoot()
	if not root then return false, "no character" end
	local from = root.Position
	local delta = target - from
	local dist = delta.Magnitude
	if dist < 9 then
		root.CFrame = CFrame.new(target + Vector3.new(0, 2, 0))
		return true
	end

	local steps = math.clamp(math.ceil(dist / 24), 1, 90)
	local step = delta / steps
	for _ = 1, steps do
		local r = charRoot()
		if not r then return false, "character lost" end
		r.CFrame = CFrame.new(r.Position + step)
		task.wait(0.03)
	end
	local r = charRoot()
	if r then r.CFrame = CFrame.new(target + Vector3.new(0, 2, 0)) end
	return true
end

local function grabStand(item, part, root)
	-- pick a point that is close to the item but has a real line of sight to it.
	-- the old code always stood on the player's side, which is the wrong side of
	-- a wall for loot inside a house. try the player side first, then a ring.
	local pos = part.Position
	local dirs = {}
	local away = root.Position - pos
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude > 0.1 then
		table.insert(dirs, away.Unit)
	end
	for _, d in ipairs({
		Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
		Vector3.new(0.707, 0, 0.707), Vector3.new(-0.707, 0, 0.707),
		Vector3.new(0.707, 0, -0.707), Vector3.new(-0.707, 0, -0.707),
	}) do
		table.insert(dirs, d)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LP.Character }

	local fallback = pos + Vector3.new(0, 0, 3)
	for _, dir in ipairs(dirs) do
		for _, dist in ipairs({ 3, 4 }) do
			local stand = pos + dir.Unit * dist
			local from = stand + Vector3.new(0, 2.5, 0)
			local hit = workspace:Raycast(from, pos - from, params)
			local clear = hit == nil or hit.Instance == part or hit.Instance:IsDescendantOf(item)
			if clear then
				return stand
			end
			if dir == dirs[1] and dist == 3 then
				fallback = stand
			end
		end
	end
	return fallback
end

local function faceAndGrab(item)
	if grabbing then return false, "grab already running" end
	if not item or not item.Parent then return false, "loot gone" end
	if item:GetAttribute("HeldBy") then return false, "already held" end
	if not Remotes or not Remotes:FindFirstChild("LootGrab") then return false, "remotes not found" end

	grabbing = true
	local part = partOf(item)
	local root = charRoot()
	if not part or not root then
		grabbing = false
		return false, "no loot part / character"
	end

	local stand = grabStand(item, part, root)
	local ok, err = stepTeleport(stand)
	if not ok then
		grabbing = false
		return false, tostring(err)
	end

	root = charRoot()
	if not root then
		grabbing = false
		return false, "character lost"
	end
	root.CFrame = CFrame.lookAt(root.Position, part.Position)

	local cam = workspace.CurrentCamera
	local oldType, oldCF = nil, nil
	if cam then
		oldType, oldCF = cam.CameraType, cam.CFrame
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CFrame.lookAt(cam.CFrame.Position, part.Position)
	end

	-- a long step teleport reaches the client immediately but the server only
	-- sees the new position after it replicates. firing at 0.1 s was rejected
	-- for every item. give the position time to land, then retry once.
	task.wait(0.5)

	local function tryGrab()
		if not part.Parent then return false end
		local r = charRoot()
		if r then r.CFrame = CFrame.lookAt(r.Position, part.Position) end
		if cam then cam.CFrame = CFrame.lookAt(cam.CFrame.Position, part.Position) end
		local fireOk = pcall(function() Remotes.LootGrab:FireServer(item) end)
		if not fireOk then return false end
		task.wait(0.6)
		local held = item:GetAttribute("HeldBy")
		return held ~= nil and tostring(held) == tostring(LP.UserId)
	end

	local grabbed = tryGrab()
	if not grabbed and not dead then
		task.wait(0.25)
		grabbed = tryGrab()
	end

	if cam then
		pcall(function()
			cam.CameraType = oldType
			cam.CFrame = oldCF
		end)
	end
	grabbing = false
	if grabbed then return true end
	root = charRoot()
	local d = root and (root.Position - part.Position).Magnitude or 0
	return false, string.format("server rejected the grab at %.1fm (hidden / room / line of sight)", d)
end

local function findCargoZone()
	local root = charRoot()
	local myPos = root and root.Position or Vector3.zero
	local best, bestDist = nil, 1e9
	for _, truck in ipairs(CollectionService:GetTagged("TravelTruck")) do
		local zone = truck:FindFirstChild("CargoZone", true)
		local part = partOf(zone)
		if part then
			local d = (part.Position - myPos).Magnitude
			if d < bestDist then
				best, bestDist = part, d
			end
		end
	end
	if best then return best end
	local town = workspace:FindFirstChild("Town")
	local truck = town and town:FindFirstChild("Truck")
	local zone = truck and truck:FindFirstChild("CargoZone", true)
	return partOf(zone)
end

local function deliverHeld()
	local held = findHeldLoot()
	if not held then return false, "not carrying anything" end
	local cargo = findCargoZone()
	if not cargo then return false, "no truck cargo zone" end
	local ok, err = stepTeleport(cargo.Position)
	if not ok then return false, tostring(err) end
	task.wait(0.55)
	if Remotes and Remotes:FindFirstChild("LootRelease") then
		pcall(function() Remotes.LootRelease:FireServer() end)
	end
	task.wait(0.7)
	local h = held:GetAttribute("HeldBy")
	if h == nil then return true end
	-- the server may not have registered the cargo-zone position yet; one retry
	-- is cheap and stops a good grab from being logged as a failed delivery.
	if Remotes and Remotes:FindFirstChild("LootRelease") then
		pcall(function() Remotes.LootRelease:FireServer() end)
	end
	task.wait(0.5)
	h = held:GetAttribute("HeldBy")
	if h == nil then return true end
	return false, "release did not clear HeldBy"
end

local function dropHeld()
	local held = findHeldLoot()
	if not held then return false, "not carrying anything" end
	if Remotes then Remotes.LootRelease:FireServer() end
	task.wait(0.4)
	return held:GetAttribute("HeldBy") == nil, "release did not clear HeldBy"
end

--// haul to truck --------------------------------------------------------------

local function haulTargets(radius)
	local rows = {}
	local loot = workspace:FindFirstChild("Loot")
	local root = charRoot()
	if not loot or not root then return rows end
	local myPos = root.Position
	local minValue = math.max(1, tonumber(CFG.lootMinValue) or 0)
	radius = math.clamp(tonumber(radius) or tonumber(CFG.haulRadius) or 250, 25, 2000)
	for _, m in ipairs(loot:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("HeldBy") == nil then
			local value = tonumber(m:GetAttribute("Value"))
			local part = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
			if value and value >= minValue and part and part.Parent and liftable(m) then
				local d = (part.Position - myPos).Magnitude
				if d <= radius then
					rows[#rows + 1] = {
						model = m,
						name = tostring(m:GetAttribute("DisplayName") or m.Name),
						value = value,
						dist = d,
					}
				end
			end
		end
	end
	table.sort(rows, function(a, b) return a.dist < b.dist end)
	return rows
end

local function refreshHaulInfo()
	if not ui.haulInfo then return end
	local radius = math.clamp(tonumber(CFG.haulRadius) or 250, 25, 2000)
	local count = #haulTargets(radius)
	local extra = ""
	if CFG.autoHaul then
		local delay = math.clamp(tonumber(CFG.autoHaulDelay) or 30, 10, 300)
		local remain = math.max(0, math.ceil(delay - (now() - lastAutoHaulAt)))
		extra = string.format("  |  auto haul in %ds", remain)
	end
	pcall(function()
		ui.haulInfo:Set(string.format("idle  |  %d items within %dm%s", count, math.floor(radius), extra))
	end)
end

local function haulAll(limit)
	if dead then return end
	if hauling then notify("a haul is already running - use stop haul") return end
	if grabbing then notify("a grab is already running - try again in a moment") return end
	local radius = math.clamp(tonumber(CFG.haulRadius) or 250, 25, 2000)
	local targets = haulTargets(radius)
	if limit and limit > 0 then
		while #targets > limit do table.remove(targets) end
	end
	if #targets == 0 then
		notify(string.format("no unheld liftable loot within %dm", math.floor(radius)))
		refreshHaulInfo()
		return
	end

	hauling = true
	haulStop = false
	local total = #targets
	local released, failed, skipped = 0, 0, 0
	local lastErr = nil

	local function status(prefix)
		if not ui.haulInfo then return end
		local done = math.min(released + failed + skipped, total)
		pcall(function()
			ui.haulInfo:Set(string.format(
				"%s  |  %d/%d  |  released %d  |  failed %d  |  skipped %d",
				prefix, done, total, released, failed, skipped
			))
		end)
	end

	notify(string.format("haul: %d items within %dm - starting", total, math.floor(radius)))
	status("hauling")

	-- clear anything already in hand before the run
	local held = findHeldLoot()
	if held then
		local ok, err = deliverHeld()
		if not ok then
			dropHeld()
			if findHeldLoot() then
				hauling = false
				notify("haul aborted: still holding " .. tostring(held:GetAttribute("DisplayName") or held.Name) .. " (" .. tostring(err) .. ")")
				status("idle")
				return
			end
		end
	end

	for i, item in ipairs(targets) do
		if haulStop or dead then break end
		local hum = charHumanoid()
		if not hum or hum.Health <= 0 then
			haulStop = true
			lastErr = "character died"
			break
		end
		if item.model.Parent and item.model:GetAttribute("HeldBy") == nil then
			local callOk, grabbed, grabErr = pcall(faceAndGrab, item.model)
			if not callOk then
				grabbed, grabErr = false, tostring(grabbed)
			end
			if grabbed then
				local dOk, delivered, deliverErr = pcall(deliverHeld)
				if not dOk then
					delivered, deliverErr = false, tostring(delivered)
				end
				if not delivered then
					task.wait(0.3)
					local rOk, retried, retryErr = pcall(deliverHeld)
					if not rOk then
						retried, retryErr = false, tostring(retried)
					end
					if not retried then deliverErr = retryErr or deliverErr end
					delivered = retried and true or false
				end
				if delivered then
					released = released + 1
				else
					failed = failed + 1
					lastErr = string.format("%s: %s", item.name, tostring(deliverErr))
					if findHeldLoot() then
						dropHeld()
						if findHeldLoot() then
							haulStop = true
							lastErr = "still holding " .. item.name .. " - haul stopped"
						else
							released = released + 1
							failed = failed - 1
						end
					end
				end
			else
				failed = failed + 1
				lastErr = string.format("%s: %s", item.name, tostring(grabErr))
			end
		else
			skipped = skipped + 1
		end
		status(haulStop and "stopping" or "hauling")
		if i % 10 == 0 then
			notify(string.format("haul %d/%d - %d released, %d failed", i, total, released, failed))
		end
		task.wait(0.12)
	end

	hauling = false
	local prefix = haulStop and "stopped" or "done"
	local msg = string.format("haul %s: %d released, %d failed, %d skipped", prefix, released, failed, skipped)
	if lastErr then msg = msg .. " - " .. lastErr end
	if not dead then notify(msg) end
	if ui.haulInfo then
		pcall(function()
			ui.haulInfo:Set(string.format(
				"%s  |  released %d  |  failed %d  |  skipped %d",
				prefix, released, failed, skipped
			))
		end)
	end
	return released, failed, skipped
end

--// humanoid esp ---------------------------------------------------------------

local function drawHumanoidEsp(e, cam, vp, hum, root, head, color, nameText, opts)
	if not (e.box and e.hpBg and e.hpFill and e.name and e.dist) then return false end
	opts = opts or {}
	local headScreen, headOn = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 0.75, 0))
	local feetScreen, feetOn = cam:WorldToViewportPoint(root.Position - Vector3.new(0, 2.7, 0))
	local visible = headOn and feetOn and headScreen.Z > 0 and feetScreen.Z > 0
	if visible then
		if headScreen.X < -120 or headScreen.X > vp.X + 120 or headScreen.Y < -120 or headScreen.Y > vp.Y + 120 then
			visible = false
		end
	end
	if not visible then return false end

	local height = math.clamp(math.abs(feetScreen.Y - headScreen.Y), 26, 420)
	local width = math.clamp(height * 0.42, 18, 220)
	local left = headScreen.X - width / 2
	local top = headScreen.Y
	local bottom = top + height

	e.box.Visible = opts.box ~= false
	e.box.Size = Vector2.new(width, height)
	e.box.Position = Vector2.new(left, top)
	e.box.Color = color

	local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
	e.hpBg.Visible = opts.health ~= false
	e.hpBg.Size = Vector2.new(3, height)
	e.hpBg.Position = Vector2.new(left - 8, top)
	e.hpFill.Visible = opts.health ~= false and frac > 0
	e.hpFill.Size = Vector2.new(3, height * frac)
	e.hpFill.Position = Vector2.new(left - 8, bottom - height * frac)
	e.hpFill.Color = frac > 0.6 and Color3.fromRGB(90, 230, 120) or (frac > 0.3 and Color3.fromRGB(250, 210, 80) or Color3.fromRGB(240, 80, 80))

	e.name.Visible = opts.name ~= false
	e.name.Text = nameText or ""
	e.name.Position = Vector2.new(headScreen.X, top - 20)
	e.name.Color = color

	e.dist.Visible = opts.distance ~= false
	e.dist.Text = opts.distanceText or ""
	e.dist.Position = Vector2.new(headScreen.X, top - 7)

	if e.tracer then
		e.tracer.Visible = opts.tracer == true
		e.tracer.From = Vector2.new(vp.X / 2, vp.Y)
		e.tracer.To = Vector2.new(headScreen.X, top + height * 0.5)
		e.tracer.Color = color
	end
	return true
end

local function newHumanoidEsp(includeTracer)
	local e = {}
	e.box = newSquare(false, Color3.fromRGB(255, 255, 255), 0.45, 1)
	e.hpBg = newSquare(true, Color3.fromRGB(15, 15, 18), 0.35, 1)
	e.hpFill = newSquare(true, Color3.fromRGB(90, 230, 120), 0, 1)
	e.name = newText(13, true, true)
	e.dist = newText(11, true, true)
	if includeTracer then e.tracer = newLine(Color3.fromRGB(255, 196, 92), 0.55, 1) end
	return e
end

local function hideHumanoidEsp(e)
	if not e then return end
	for _, key in ipairs({ "box", "hpBg", "hpFill", "name", "dist", "tracer" }) do
		local d = e[key]
		if d then d.Visible = false end
	end
end

local function dropHumanoidEsp(pool, key)
	local e = pool[key]
	if not e then return end
	for _, name in ipairs({ "box", "hpBg", "hpFill", "name", "dist", "tracer" }) do
		removeDrawing(e[name])
	end
	pool[key] = nil
end

--// player esp -----------------------------------------------------------------

local playerPool = {}
local playerFrame = 0

local function playerEspFor(plr)
	local e = playerPool[plr]
	if e then return e end
	e = newHumanoidEsp(true)
	playerPool[plr] = e
	return e
end

local function playerEspTick()
	playerFrame = playerFrame + 1
	local frame = playerFrame
	local cam = workspace.CurrentCamera
	local myRoot = charRoot()
	if not cam or not myRoot then return end
	local vp = cam.ViewportSize
	local myPos = myRoot.Position

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == LP then continue end
		local e = playerEspFor(plr)
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local head = char and char:FindFirstChild("Head")
		if CFG.playerEsp and hum and root and head and hum.Health > 0 then
			local ok = drawHumanoidEsp(e, cam, vp, hum, root, head, Color3.fromRGB(120, 215, 255), plr.Name, {
				box = CFG.playerEspBox,
				health = CFG.playerEspHealth,
				name = CFG.playerEspName,
				distance = CFG.playerEspDistance,
				distanceText = string.format("%d studs", math.floor((root.Position - myPos).Magnitude)),
				tracer = CFG.playerEspTracer,
			})
			if ok then e.lastFrame = frame end
		end
		if not e.lastFrame or e.lastFrame ~= frame then hideHumanoidEsp(e) end
	end
end

--// npc esp --------------------------------------------------------------------

local npcPool = {}
local npcFrame = 0

local function npcColor(group)
	if group == "Guards" then return Color3.fromRGB(255, 170, 70) end
	if group == "Police" then return Color3.fromRGB(90, 160, 255) end
	return Color3.fromRGB(215, 215, 225)
end

local function npcEnabled(group)
	if group == "Npcs" then return CFG.npcResidents end
	if group == "Guards" then return CFG.npcGuards end
	if group == "Police" then return CFG.npcPolice end
	return false
end

local function esc(text)
	return (tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function hexColor(c)
	return string.format("#%02X%02X%02X",
		math.floor(math.clamp(c.R, 0, 1) * 255 + 0.5),
		math.floor(math.clamp(c.G, 0, 1) * 255 + 0.5),
		math.floor(math.clamp(c.B, 0, 1) * 255 + 0.5))
end

local function npcExtra(model)
	local parts = {}
	local function add(key, prefix)
		local v = model:GetAttribute(key)
		if v ~= nil and tostring(v) ~= "" then
			parts[#parts + 1] = (prefix and (prefix .. " ") or "") .. tostring(v)
		end
	end
	add("Gender")
	add("Outfit")
	add("Home", "home")
	add("Spot", "spot")
	add("Pose", "pose")
	add("Station", "station")
	return table.concat(parts, " - ")
end

local function npcEspFor(model)
	local e = npcPool[model]
	if e then return e end
	e = newHumanoidEsp(false)
	npcPool[model] = e
	return e
end

local function npcEspTick()
	npcFrame = npcFrame + 1
	local frame = npcFrame
	local cam = workspace.CurrentCamera
	local myRoot = charRoot()
	if not cam or not myRoot then return end
	if not CFG.npcEsp then
		for _, e in pairs(npcPool) do hideHumanoidEsp(e) end
		return
	end

	local vp = cam.ViewportSize
	local myPos = myRoot.Position

	for _, group in ipairs({ "Npcs", "Guards", "Police" }) do
		local folder = workspace:FindFirstChild(group)
		if folder and npcEnabled(group) then
			for _, model in ipairs(folder:GetChildren()) do
				if model:IsA("Model") then
					local hum = model:FindFirstChildOfClass("Humanoid")
					local root = model:FindFirstChild("HumanoidRootPart") or (hum and hum.RootPart)
					local head = model:FindFirstChild("Head") or root
					if hum and root and head and hum.Health > 0 then
						local dist = (root.Position - myPos).Magnitude
						if dist <= 400 then
							local e = npcEspFor(model)
							local label = model.Name
							if CFG.npcTags then
								local st = model:GetAttribute("State")
								if st ~= nil then label = label .. " [" .. tostring(st) .. "]" end
								local extra = npcExtra(model)
								if extra ~= "" then label = label .. "  " .. extra end
							end
							local ok = drawHumanoidEsp(e, cam, vp, hum, root, head, npcColor(group), label, {
								box = CFG.npcBox,
								health = CFG.npcHealth,
								name = CFG.npcName,
								distance = CFG.npcDistance,
								distanceText = string.format("%d studs", math.floor(dist)),
							})
							if ok then e.lastFrame = frame end
						end
					end
				end
			end
		end
	end

	for model, e in pairs(npcPool) do
		if not model.Parent then
			dropHumanoidEsp(npcPool, model)
		elseif not e.lastFrame or e.lastFrame ~= frame then
			hideHumanoidEsp(e)
		end
	end
end

--// movement -------------------------------------------------------------------

local noclipSaved = {}
local speedConn = nil
local speedHook = nil
local jumpConn = nil
local baseWalk = nil
local baseJump = nil
local baseUseJumpPower = nil
local speedNow = nil
local applyingSpeed = false
local staminaGodOwned = nil
local staminaGodCharges = nil

local function speedTarget()
	local target = tonumber(CFG.walkSpeed) or 60
	if CFG.speedGuard and not CFG.speedNoCap then
		local cap = tonumber(CFG.speedCap) or 60
		if cap > 0 and target > cap then target = cap end
	end
	return target
end

local function stopSpeed()
	if speedConn then
		pcall(function() speedConn:Disconnect() end)
		speedConn = nil
	end
	if speedHook then
		pcall(function() speedHook:Disconnect() end)
		speedHook = nil
	end
	speedNow = nil
end

local function applySpeed(hum)
	if not speedNow then return end
	if math.abs(hum.WalkSpeed - speedNow) <= 0.05 then return end
	applyingSpeed = true
	hum.WalkSpeed = speedNow
	applyingSpeed = false
end

local function startSpeed()
	stopSpeed()
	local hum = charHumanoid()
	if not hum then return end
	if baseWalk == nil then baseWalk = hum.WalkSpeed end
	speedNow = hum.WalkSpeed
	-- the game's SprintClient writes WalkSpeed from RenderStepped every frame.
	-- react to that write immediately (the property hook is what actually holds
	-- the value), while the heartbeat only advances the ramp.
	speedHook = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if dead or not CFG.customSpeed or applyingSpeed then return end
		applySpeed(hum)
	end)
	speedConn = RunService.Heartbeat:Connect(function(dt)
		if dead or not CFG.customSpeed then return end
		local h = charHumanoid()
		if not h then return end
		local want = speedTarget()
		if CFG.speedGuard then
			-- ramp instead of snapping: a sudden 16 -> 120 jump is the easiest
			-- thing for a position-based check to notice.
			local alpha = math.clamp((dt or 0) * 8, 0, 1)
			speedNow = (speedNow or h.WalkSpeed) + (want - (speedNow or h.WalkSpeed)) * alpha
			if math.abs(speedNow - want) < 0.5 then speedNow = want end
		else
			speedNow = want
		end
		applySpeed(h)
	end)
end

local function stopJump()
	if jumpConn then
		pcall(function() jumpConn:Disconnect() end)
		jumpConn = nil
	end
end

local function startJump()
	stopJump()
	local hum = charHumanoid()
	if not hum then return end
	if baseJump == nil then baseJump = hum.JumpPower end
	if baseUseJumpPower == nil then baseUseJumpPower = hum.UseJumpPower end
	hum.UseJumpPower = true
	hum.JumpPower = CFG.jumpPower
	jumpConn = hum:GetPropertyChangedSignal("JumpPower"):Connect(function()
		if dead or not CFG.customJump then return end
		if math.abs(hum.JumpPower - CFG.jumpPower) > 0.5 then
			hum.JumpPower = CFG.jumpPower
		end
		if not hum.UseJumpPower then hum.UseJumpPower = true end
	end)
end

local flyBody = nil
local flyGyro = nil
local flyConn = nil

local function stopFly()
	if flyConn then
		pcall(function() flyConn:Disconnect() end)
		flyConn = nil
	end
	if flyBody then
		pcall(function() flyBody:Destroy() end)
		flyBody = nil
	end
	if flyGyro then
		pcall(function() flyGyro:Destroy() end)
		flyGyro = nil
	end
end

local function startFly()
	stopFly()
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local body = Instance.new("BodyVelocity")
	body.Name = "SlimhubFly"
	body.MaxForce = Vector3.new(1e9, 1e9, 1e9)
	body.Velocity = Vector3.zero
	body.P = 12500
	body.Parent = hrp
	local gyro = Instance.new("BodyGyro")
	gyro.Name = "SlimhubFlyGyro"
	gyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
	gyro.P = 3000
	gyro.D = 50
	gyro.CFrame = hrp.CFrame
	gyro.Parent = hrp
	flyBody = body
	flyGyro = gyro

	flyConn = RunService.RenderStepped:Connect(function()
		if dead or not CFG.fly then return end
		local root = charRoot()
		local cam = workspace.CurrentCamera
		if not root or not cam or not flyBody or not flyGyro then return end
		local speed = math.clamp(tonumber(CFG.flySpeed) or 80, 10, 300)
		local dir = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - Vector3.new(0, 1, 0) end
		if dir.Magnitude > 0.01 then
			flyBody.Velocity = dir.Unit * speed
		else
			flyBody.Velocity = Vector3.zero
		end
		flyGyro.CFrame = CFrame.new(root.Position, root.Position + cam.CFrame.LookVector)
	end)
end

local function flyTick()
	if CFG.fly and not flyBody then
		startFly()
	elseif not CFG.fly and flyBody then
		stopFly()
	end
end

local function staminaBar()
	local gui = LP:FindFirstChildOfClass("PlayerGui")
	local hud = gui and gui:FindFirstChild("HUD")
	return hud and hud:FindFirstChild("StaminaBar")
end

local function restoreStamina()
	if staminaGodOwned == nil then return end
	-- only undo our local God flag. if the server spent a God charge while this
	-- was on, leave the real one alone.
	local charges = tonumber(LP:GetAttribute("GodCharges")) or 0
	local granted = staminaGodCharges ~= nil and charges < staminaGodCharges
	if not granted then
		if staminaGodOwned == "nil" then
			LP:SetAttribute("God", nil)
		else
			LP:SetAttribute("God", staminaGodOwned)
		end
	end
	staminaGodOwned = nil
	staminaGodCharges = nil
end

local function staminaTick()
	if not CFG.infiniteStamina then
		if staminaGodOwned ~= nil then restoreStamina() end
		return
	end
	if staminaGodOwned == nil then
		local current = LP:GetAttribute("God")
		staminaGodOwned = (current == nil) and "nil" or current
		staminaGodCharges = tonumber(LP:GetAttribute("GodCharges")) or 0
	end
	-- SprintClient checks this attribute every frame. when it is true the
	-- game's own code refills u70 and skips the 22/s drain + Breathing(true).
	if LP:GetAttribute("God") ~= true then
		LP:SetAttribute("God", true)
	end
	local bar = staminaBar()
	local fill = bar and bar:FindFirstChild("Fill")
	if fill then
		fill.Size = UDim2.fromScale(1, 1)
	end
end

local function saveNoclipParts(char)
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") and noclipSaved[part] == nil then
			noclipSaved[part] = part.CanCollide
		end
	end
end

local function restoreNoclip()
	for part, value in pairs(noclipSaved) do
		if part.Parent then
			pcall(function() part.CanCollide = value end)
		end
	end
	noclipSaved = {}
end

local function restoreMovement()
	local hum = charHumanoid()
	if not hum then return end
	if baseWalk then hum.WalkSpeed = baseWalk end
	if baseJump then
		hum.UseJumpPower = true
		hum.JumpPower = baseJump
	end
	if baseUseJumpPower ~= nil then hum.UseJumpPower = baseUseJumpPower end
	baseWalk = nil
	baseJump = nil
	baseUseJumpPower = nil
end

local function movementTick()
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	staminaTick()
	flyTick()
	if CFG.customSpeed and not speedConn then startSpeed() end
	if CFG.customJump then
		if not jumpConn then startJump() end
		if not hum.UseJumpPower then hum.UseJumpPower = true end
	end

	if CFG.noclip then
		saveNoclipParts(char)
		for part in pairs(noclipSaved) do
			if part.Parent and part.CanCollide then
				part.CanCollide = false
			end
		end
	elseif next(noclipSaved) ~= nil then
		restoreNoclip()
	end

	if CFG.fovOn then
		local cam = workspace.CurrentCamera
		if cam and cam.FieldOfView ~= CFG.fov then
			cam.FieldOfView = CFG.fov
		end
	end
end

local jumpRequestConn = UserInputService.JumpRequest:Connect(function()
	if dead or not CFG.infiniteJump then return end
	local hum = charHumanoid()
	if not hum then return end
	local state = hum:GetState()
	if state ~= Enum.HumanoidStateType.Jumping and state ~= Enum.HumanoidStateType.Freefall then
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end)

--// visuals --------------------------------------------------------------------

local lightSaved = nil

local function applyFullbright()
	if lightSaved then return end
	lightSaved = {
		Brightness = Lighting.Brightness,
		ClockTime = Lighting.ClockTime,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		GlobalShadows = Lighting.GlobalShadows,
		EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
		EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
	}
	Lighting.Brightness = 3
	Lighting.ClockTime = 14
	Lighting.Ambient = Color3.fromRGB(170, 170, 170)
	Lighting.OutdoorAmbient = Color3.fromRGB(170, 170, 170)
	Lighting.GlobalShadows = false
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
end

local function restoreFullbright()
	if not lightSaved then return end
	for k, v in pairs(lightSaved) do
		pcall(function() Lighting[k] = v end)
	end
	lightSaved = nil
end

local fogSaved = nil

local function applyNoFog()
	if fogSaved then return end
	fogSaved = {
		FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart,
	}
	Lighting.FogEnd = 100000
	Lighting.FogStart = 100000
end

local function restoreNoFog()
	if not fogSaved then return end
	for k, v in pairs(fogSaved) do
		pcall(function() Lighting[k] = v end)
	end
	fogSaved = nil
end

local function restoreVisuals()
	restoreFullbright()
	restoreNoFog()
	if workspace.CurrentCamera then
		workspace.CurrentCamera.FieldOfView = originalFov
	end
end

--// prompts --------------------------------------------------------------------

local promptCache = {}
local promptScanAt = 0

local function allPrompts()
	local t = now()
	if #promptCache > 0 and t - promptScanAt < 8 then return promptCache end
	promptScanAt = t
	promptCache = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			promptCache[#promptCache + 1] = d
		end
	end
	return promptCache
end

local function promptPart(prompt)
	local part = prompt.Parent
	while part and not part:IsA("BasePart") do
		part = part.Parent
	end
	return part
end

local function isRobPrompt(p)
	local a = p.ActionText:lower()
	return a:find("rob") ~= nil or a:find("steal") ~= nil or a == "pickpocket"
end

local function isOpenPrompt(p)
	local a = p.ActionText
	return a == "Open" or a == "Climb Through"
end

local function isHomePrompt(p)
	return p.ActionText == "Head Home"
end

local function isSellPrompt(p)
	return p.ActionText:lower():find("sell") ~= nil
end

local function fireMatching(matchFn, cooldown, label)
	if not fireproximityprompt then return 0, 0, "executor has no fireproximityprompt" end
	local fired, skipped = 0, 0
	local t = now()
	for _, prompt in ipairs(allPrompts()) do
		if prompt.Parent and prompt.Enabled and matchFn(prompt) then
			local last = promptCooldown[prompt] or 0
			if cooldown <= 0 or (t - last) >= cooldown then
				promptCooldown[prompt] = t
				local ok = pcall(function() fireproximityprompt(prompt) end)
				if ok then fired = fired + 1 else skipped = skipped + 1 end
				task.wait(0.04)
			else
				skipped = skipped + 1
			end
		end
	end
	if fired > 0 then pushLog(string.format("%s: %d fired", label or "prompts", fired)) end
	return fired, skipped, nil
end

local function fireNearbyMatching(matchFn, radius, cooldown, label)
	if not fireproximityprompt then return 0, 0, "executor has no fireproximityprompt" end
	local root = charRoot()
	if not root then return 0, 0, "no character" end
	local myPos = root.Position
	radius = math.clamp(tonumber(radius) or 60, 5, 300)
	local fired, skipped = 0, 0
	local t = now()
	for _, prompt in ipairs(allPrompts()) do
		if prompt.Parent and prompt.Enabled and matchFn(prompt) then
			local part = promptPart(prompt)
			if part and (part.Position - myPos).Magnitude <= radius then
				local last = promptCooldown[prompt] or 0
				if cooldown <= 0 or (t - last) >= cooldown then
					promptCooldown[prompt] = t
					if pcall(function() fireproximityprompt(prompt) end) then
						fired = fired + 1
					else
						skipped = skipped + 1
					end
					task.wait(0.04)
				else
					skipped = skipped + 1
				end
			end
		end
	end
	if fired > 0 then pushLog(string.format("%s: %d fired", label or "prompts", fired)) end
	return fired, skipped, nil
end

local function fireNearest(matchFn, label)
	if not fireproximityprompt then return false, "executor has no fireproximityprompt" end
	local root = charRoot()
	if not root then return false, "no character" end
	local best, bestDist = nil, 1e9
	for _, prompt in ipairs(allPrompts()) do
		if prompt.Parent and prompt.Enabled and matchFn(prompt) then
			local part = promptPart(prompt)
			if part then
				local d = (part.Position - root.Position).Magnitude
				if d < bestDist then
					best, bestDist = prompt, d
				end
			end
		end
	end
	if not best then return false, "no matching enabled prompt" end
	local ok = pcall(function() fireproximityprompt(best) end)
	if ok then
		pushLog(string.format("%s: %s", label or "prompt", best:GetFullName()))
		return true
	end
	return false, "fire failed"
end

--// world targets --------------------------------------------------------------

local function nearestTagPart(tag, childName)
	local root = charRoot()
	local myPos = root and root.Position or Vector3.zero
	local best, bestDist = nil, 1e9
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		local part
		if childName then
			part = partOf(inst:FindFirstChild(childName, true))
		else
			part = partOf(inst)
		end
		if part then
			local d = (part.Position - myPos).Magnitude
			if d < bestDist then
				best, bestDist = part, d
			end
		end
	end
	return best, bestDist
end

local function findSellBox()
	local hideout = workspace:FindFirstChild("Hideout")
	return partOf(hideout and hideout:FindFirstChild("SellBox", true))
end

local function findSellLever()
	local hideout = workspace:FindFirstChild("Hideout")
	return partOf(hideout and hideout:FindFirstChild("SellLever", true))
end

local function findHideout()
	local hideout = workspace:FindFirstChild("Hideout")
	if not hideout then return nil end
	local truck = hideout:FindFirstChild("Truck")
	local zone = truck and truck:FindFirstChild("CargoZone", true)
	local part = partOf(zone)
	if part then return part end
	return partOf(hideout:FindFirstChild("SellBox", true))
end

local function findJobBoard()
	local town = workspace:FindFirstChild("Town")
	local truck = town and town:FindFirstChild("Truck")
	local board = truck and truck:FindFirstChild("JobBoard", true)
	local part = partOf(board)
	if part then return part end
	for _, prompt in ipairs(allPrompts()) do
		if prompt.Enabled and (prompt.ActionText == "Read" or prompt.ActionText == "Head Home") then
			local p = promptPart(prompt)
			if p then return p end
		end
	end
	return nil
end

local function findShopComputer()
	local part = nearestTagPart("ShopComputer")
	return part
end

local function teleportTo(part, label, offset)
	if not part then
		notify(label .. ": not found in this map")
		return false
	end
	local target = part.Position
	if offset then target = target + offset end
	local ok, err = stepTeleport(target)
	if ok then
		notify("teleported to " .. label)
	else
		notify("teleport failed: " .. tostring(err))
	end
	return ok
end

--// status --------------------------------------------------------------------

local objectives = nil
pcall(function()
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local mod = shared and shared:FindFirstChild("Objectives")
	if mod then objectives = require(mod) end
end)

local function objectiveTitle(id)
	if objectives and objectives[id] then
		return tostring(objectives[id].title or ("Objective " .. tostring(id)))
	end
	return "Objective " .. tostring(id)
end

local function statusText()
	local cash = LP:GetAttribute("Cash") or 0
	local level = LP:GetAttribute("Level") or 0
	local xp = LP:GetAttribute("XP") or 0
	local objId = LP:GetAttribute("Objective")
	local quota = ReplicatedStorage:GetAttribute("QuotaProgress") or 0
	local target = ReplicatedStorage:GetAttribute("QuotaTarget") or 0
	local day = ReplicatedStorage:GetAttribute("Day") or 0
	local night = ReplicatedStorage:GetAttribute("NightActive")
	local debt = ReplicatedStorage:GetAttribute("DebtLeft") or 0
	local diff = ReplicatedStorage:GetAttribute("Difficulty") or "?"
	local mode = ReplicatedStorage:GetAttribute("Mode") or "?"
	local held = findHeldLoot()
	local cargo = findCargoZone()
	local root = charRoot()
	local heldText = "nothing"
	if held then
		heldText = string.format("%s (%s)", tostring(held:GetAttribute("DisplayName") or held.Name), money(held:GetAttribute("Value") or 0))
	end
	local cargoText = "not found"
	if cargo and root then
		cargoText = string.format("%dm", math.floor((cargo.Position - root.Position).Magnitude))
	end
	return table.concat({
		"cash        " .. money(cash),
		"level       " .. tostring(level) .. "   xp " .. comma(xp),
		"objective   " .. objectiveTitle(objId) .. "  [" .. tostring(objId) .. "]",
		"quota       " .. tostring(quota) .. " / " .. tostring(target),
		"day         " .. tostring(day) .. "   " .. (night and "night" or "day"),
		"debt        " .. money(debt),
		"difficulty  " .. tostring(diff) .. "   " .. tostring(mode),
		"carrying    " .. heldText,
		"lifter      " .. tostring(LP:GetAttribute("Shop_Lifter") or 0) .. " / 2" .. (CFG.maxStrength and "  MAX" or ""),
		"truck       " .. cargoText,
	}, "\n")
end

--// player / npc lists ---------------------------------------------------------

local function playerNames()
	local names = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP then table.insert(names, p.Name) end
	end
	table.sort(names)
	return names
end

local function scanNpcs()
	local options = {}
	local map = {}
	for _, group in ipairs({ "Npcs", "Guards", "Police" }) do
		local folder = workspace:FindFirstChild(group)
		if folder then
			local i = 0
			for _, model in ipairs(folder:GetChildren()) do
				if model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") then
					i = i + 1
					local label = string.format("%s / %s [%d]", group, model.Name, i)
					options[#options + 1] = label
					map[label] = model
				end
			end
		end
	end
	table.sort(options)
	npcOptions = map
	return options
end

--// npc details window ----------------------------------------------------------

local npcDetailGui = nil
local npcDetailFrame = nil
local npcDetailList = nil
local npcDetailTitle = nil
local npcDetailStatus = nil
local npcDetailRows = {}
local npcDetailConn = nil
local npcDetailAt = 0

local function npcState(model, hum)
	local state = model:GetAttribute("State")
	if state == nil and hum then state = hum:GetState() end
	local s = state ~= nil and tostring(state) or "?"
	return (s:gsub("Enum%.HumanoidStateType%.", ""))
end

local function npcSummary(model, group, index, myPos)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") or (hum and hum.RootPart)
	local dist = root and math.floor((root.Position - myPos).Magnitude) or -1
	local hp = hum and math.max(0, math.ceil(hum.Health)) or 0
	local maxHp = hum and math.max(1, math.ceil(hum.MaxHealth)) or 1
	return {
		model = model,
		group = group,
		index = index,
		name = model.Name,
		dist = dist,
		hp = hp,
		maxHp = maxHp,
		state = npcState(model, hum),
		tags = npcExtra(model),
		dead = not hum or hum.Health <= 0,
	}
end

local function collectNpcs()
	local rows = {}
	local myRoot = charRoot()
	local myPos = myRoot and myRoot.Position or Vector3.new()
	for _, group in ipairs({ "Npcs", "Guards", "Police" }) do
		local folder = workspace:FindFirstChild(group)
		if folder then
			local i = 0
			for _, model in ipairs(folder:GetChildren()) do
				if model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") then
					i = i + 1
					rows[#rows + 1] = npcSummary(model, group, i, myPos)
				end
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.dist ~= b.dist then return a.dist < b.dist end
		if a.group ~= b.group then return a.group < b.group end
		return a.index < b.index
	end)
	return rows
end

local function npcRowText(r)
	local color = hexColor(npcColor(r.group))
	local hpText = r.dead and "DEAD" or (r.hp .. "/" .. r.maxHp .. " hp")
	local hpColor = r.dead and "#ff8080" or "#9fe8a8"
	local line1 = '<font color="' .. color .. '">[' .. r.group .. ']</font> '
		.. '<b>' .. esc(r.name) .. " #" .. r.index .. "</b>  "
		.. '<font color="' .. hpColor .. '">' .. hpText .. "</font>  "
		.. '<font color="#c9c9d4">' .. r.dist .. "m</font>  "
		.. '<font color="#ffd88a">' .. esc(r.state) .. "</font>"
	local line2 = '<font color="#9a9aa8">'
		.. (r.tags ~= "" and esc(r.tags) or "no extra attributes") .. "</font>"
	return line1 .. "\n" .. line2
end

local function npcDetailTeardown()
	if npcDetailConn then pcall(function() npcDetailConn:Disconnect() end) end
	npcDetailConn = nil
	if npcDetailGui then pcall(function() npcDetailGui:Destroy() end) end
	npcDetailGui = nil
	npcDetailFrame = nil
	npcDetailList = nil
	npcDetailTitle = nil
	npcDetailStatus = nil
	npcDetailRows = {}
	npcDetailAt = 0
end

local function npcDetailBuild()
	if npcDetailFrame or dead then return end
	local parent = nil
	local ok, hui = pcall(function() return gethui and gethui() or nil end)
	if ok and hui then parent = hui end
	if not parent then
		ok, parent = pcall(function() return game:GetService("CoreGui") end)
	end
	if not ok or not parent then
		parent = LP:FindFirstChildOfClass("PlayerGui")
	end
	if not parent then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CriminalNpcDetails"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 90
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	if not pcall(function() gui.Parent = parent end) then
		pcall(function() gui.Parent = LP:FindFirstChildOfClass("PlayerGui") end)
	end

	local frame = Instance.new("Frame")
	frame.Name = "Window"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -18, 0, 92)
	frame.Size = UDim2.new(0, 560, 0, 430)
	frame.BackgroundColor3 = Color3.fromRGB(14, 12, 16)
	frame.BackgroundTransparency = 0.06
	frame.BorderSizePixel = 0
	frame.Active = true
	frame.ClipsDescendants = true
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 196, 92)
	stroke.Transparency = 0.65
	stroke.Thickness = 1
	stroke.Parent = frame

	local title = Instance.new("TextButton")
	title.Name = "Title"
	title.BackgroundColor3 = Color3.fromRGB(24, 20, 18)
	title.BackgroundTransparency = 0.02
	title.BorderSizePixel = 0
	title.AutoButtonColor = false
	title.Position = UDim2.new(0, 0, 0, 0)
	title.Size = UDim2.new(1, 0, 0, 30)
	title.Font = Enum.Font.GothamBold
	title.Text = "NPC DETAILS"
	title.TextColor3 = Color3.fromRGB(255, 196, 92)
	title.TextSize = 13
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame

	local titlePad = Instance.new("UIPadding")
	titlePad.PaddingLeft = UDim.new(0, 10)
	titlePad.Parent = title

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -6, 0, 6)
	close.Size = UDim2.new(0, 22, 0, 18)
	close.BackgroundColor3 = Color3.fromRGB(48, 32, 32)
	close.BorderSizePixel = 0
	close.Font = Enum.Font.GothamBold
	close.Text = "X"
	close.TextColor3 = Color3.fromRGB(255, 170, 170)
	close.TextSize = 11
	close.Parent = title

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 5)
	closeCorner.Parent = close

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Position = UDim2.new(0, 10, 0, 30)
	status.Size = UDim2.new(1, -20, 0, 18)
	status.Font = Enum.Font.Code
	status.Text = "scanning"
	status.TextColor3 = Color3.fromRGB(150, 150, 165)
	status.TextSize = 11
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Parent = frame

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Position = UDim2.new(0, 8, 0, 50)
	list.Size = UDim2.new(1, -16, 1, -58)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = Color3.fromRGB(255, 196, 92)
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ClipsDescendants = true
	list.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	npcDetailGui = gui
	npcDetailFrame = frame
	npcDetailList = list
	npcDetailTitle = title
	npcDetailStatus = status
	npcDetailRows = {}
	npcDetailAt = 0

	local dragging = false
	local dragStart = nil
	local startPos = nil
	title.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	npcDetailConn = UserInputService.InputChanged:Connect(function(input)
		if not dragging or not npcDetailFrame then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local delta = input.Position - dragStart
			frame.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)

	close.MouseButton1Click:Connect(function()
		CFG.npcDetails = false
		npcDetailTeardown()
		if ui.window then pcall(function() ui.window:Set("crim_npcdetails", false) end) end
		pcall(saveCfg)
	end)
end

local function npcDetailRow(i)
	local row = npcDetailRows[i]
	if row and row.Parent then return row end
	row = Instance.new("TextLabel")
	row.Name = "Row" .. i
	row.BackgroundColor3 = Color3.fromRGB(22, 19, 24)
	row.BackgroundTransparency = (i % 2 == 0) and 0.35 or 0.6
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, -6, 0, 34)
	row.Font = Enum.Font.Code
	row.Text = ""
	row.TextColor3 = Color3.fromRGB(235, 235, 240)
	row.TextSize = 12
	row.TextWrapped = false
	row.TextTruncate = Enum.TextTruncate.AtEnd
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.TextYAlignment = Enum.TextYAlignment.Top
	row.RichText = true
	row.LayoutOrder = i
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 1)
	pad.Parent = row
	row.Parent = npcDetailList
	npcDetailRows[i] = row
	return row
end

local function npcDetailTick()
	if dead or not CFG.npcDetails then return end
	if not npcDetailFrame then npcDetailBuild() end
	if not npcDetailFrame then return end
	local t = now()
	if t - npcDetailAt < 0.75 then return end
	npcDetailAt = t

	local rows = collectNpcs()
	local counts = { Npcs = 0, Guards = 0, Police = 0 }
	local alive = 0
	for _, r in ipairs(rows) do
		counts[r.group] = (counts[r.group] or 0) + 1
		if not r.dead then alive = alive + 1 end
	end
	if npcDetailTitle then
		npcDetailTitle.Text = string.format("NPC DETAILS  -  %d npcs  (%d alive)", #rows, alive)
	end
	if npcDetailStatus then
		npcDetailStatus.Text = string.format(
			"%d residents  |  %d guards  |  %d police  |  nearest %s",
			counts.Npcs or 0, counts.Guards or 0, counts.Police or 0,
			rows[1] and (rows[1].name .. " @ " .. rows[1].dist .. "m") or "-"
		)
	end
	for i, r in ipairs(rows) do
		local row = npcDetailRow(i)
		row.Text = npcRowText(r)
		row.Visible = true
	end
	for i = #rows + 1, #npcDetailRows do
		local row = npcDetailRows[i]
		if row then row.Visible = false end
	end
	return #rows
end

local function npcDetailDump()
	local rows = collectNpcs()
	local lines = {
		string.format("npc dump  place %d  %s", game.PlaceId, os.date("%Y-%m-%d %H:%M:%S")),
	}
	for _, r in ipairs(rows) do
		local attrs = {}
		for k, v in pairs(r.model:GetAttributes()) do
			attrs[#attrs + 1] = tostring(k) .. "=" .. tostring(v)
		end
		table.sort(attrs)
		local root = r.model:FindFirstChild("HumanoidRootPart")
		local pos = root
			and string.format("%.0f, %.0f, %.0f", root.Position.X, root.Position.Y, root.Position.Z)
			or "?"
		lines[#lines + 1] = string.format(
			"[%s] %s #%d  %s  %dm  %s  pos %s  { %s }",
			r.group, r.name, r.index,
			r.dead and "DEAD" or string.format("%d/%d hp", r.hp, r.maxHp),
			r.dist, r.state, pos, table.concat(attrs, ", ")
		)
	end
	local text = table.concat(lines, "\n")
	print("[CRIMINAL] npc dump\n" .. text)
	local saved = false
	if writefile then
		saved = pcall(writefile, "slimhub-npc-details.txt", text)
	end
	notify(string.format("dumped %d npcs%s", #rows,
		saved and " to slimhub-npc-details.txt" or " to console"))
	return #rows
end

--// auto knockout --------------------------------------------------------------

local function npcKnockedOut(model)
	if not model or not model.Parent then return true end
	local untilAt = tonumber(model:GetAttribute("KnockedOutUntil")) or 0
	return untilAt > workspace:GetServerTimeNow()
end

local function knockoutTargets(radius)
	local rows = {}
	local root = charRoot()
	if not root then return rows end
	local myPos = root.Position
	radius = math.clamp(tonumber(radius) or 25, 5, 200)
	local groups = { "Npcs", "Guards", "Police" }
	if workspace:FindFirstChild("Dogs") then table.insert(groups, "Dogs") end
	for _, group in ipairs(groups) do
		local folder = workspace:FindFirstChild(group)
		if folder then
			for _, model in ipairs(folder:GetChildren()) do
				if model:IsA("Model") then
					local hum = model:FindFirstChildOfClass("Humanoid")
					local part = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or partOf(model)
					if hum and part and hum.Health > 0 and not npcKnockedOut(model) then
						local d = (part.Position - myPos).Magnitude
						if d <= radius then
							rows[#rows + 1] = {
								model = model,
								part = part,
								group = group,
								name = tostring(model:GetAttribute("DisplayName") or model.Name),
								dist = d,
								hp = hum.Health,
							}
						end
					end
				end
			end
		end
	end
	table.sort(rows, function(a, b) return a.dist < b.dist end)
	return rows
end

--// stealth / anti-detect --------------------------------------------------------

function stealth.serverSneaking()
	local char = LP.Character
	return char ~= nil and char:GetAttribute("Sneaking") == true
end

function stealth.sendSneak(on, auto)
	if dead then return false, "panel unloaded" end
	on = on and true or false
	auto = auto and true or false
	local scripts = LP:FindFirstChild("PlayerScripts")
	local sc = scripts and scripts:FindFirstChild("SprintClient")
	local toggle = sc and sc:FindFirstChild("Toggle")

	-- preferred: use the game's own Toggle bindable. SprintClient then updates
	-- its internal state and fires the real Sneak remote itself, so it cannot
	-- immediately fight us with the old state.
	if toggle and toggle:IsA("BindableEvent") then
		local isOn = sc:GetAttribute("Sneak") == true
		if isOn ~= on then
			toggle:Fire("Sneak")
			stealth.owned = on
			stealth.auto = on and auto or false
			stealth.lastSent = now()
			return true
		end
		if on then
			if not stealth.serverSneaking() then
				stealth.owned = true
				stealth.auto = auto
			elseif stealth.owned and auto then
				stealth.auto = true
			end
		else
			stealth.owned = false
			stealth.auto = false
			if stealth.serverSneaking() then
				local remote = Remotes and Remotes:FindFirstChild("Sneak")
				if remote then pcall(function() remote:FireServer(false) end) end
				pcall(function() sc:SetAttribute("Crouching", false) end)
			end
		end
		stealth.lastSent = now()
		return true
	end

	-- fallback: direct remote (works, but SprintClient may fight the state if
	-- its own internal toggle disagrees).
	local remote = Remotes and Remotes:FindFirstChild("Sneak")
	if not remote then return false, "sneak remote not found" end
	if on and not stealth.serverSneaking() then
		stealth.owned = true
		stealth.auto = auto
	end
	pcall(function() remote:FireServer(on) end)
	if sc then
		pcall(function() sc:SetAttribute("Crouching", on) end)
	end
	stealth.lastSent = now()
	if not on then
		stealth.owned = false
		stealth.auto = false
	end
	return true
end

function stealth.currentSight()
	local uid = tostring(LP.UserId)
	local root = charRoot()
	if not root then return 0, nil, nil end
	local myPos = root.Position
	local best, bestModel, bestDist = 0, nil, nil
	for _, folderName in ipairs({ "Npcs", "Guards", "Police", "Dogs" }) do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			for _, model in ipairs(folder:GetChildren()) do
				if model:IsA("Model") then
					local v = tonumber(model:GetAttribute("Sight" .. uid))
					if v and v > best then
						local hum = model:FindFirstChildOfClass("Humanoid")
						local part = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
						if part and (not hum or hum.Health > 0) then
							best = v
							bestModel = model
							bestDist = (part.Position - myPos).Magnitude
						end
					end
				end
			end
		end
	end
	return best, bestModel, bestDist
end

-- the game's own crouch makes no walking noise (loading tip). This only fires
-- the game's Sneak remote while a live npc is close or already noticing you.
-- it does not hide you from server-side sight checks or cameras.
function stealth.sneakTick()
	if dead then return end
	if not CFG.antiDetect then
		if stealth.auto and now() - stealth.lastSent > 0.5 then
			stealth.sendSneak(false)
		end
		return
	end
	if now() - stealth.lastScan < 0.2 then return end
	stealth.lastScan = now()

	local radius = math.clamp(tonumber(CFG.antiDetectRadius) or 45, 5, 200)
	local near = knockoutTargets(radius)[1]
	local sight = stealth.currentSight()
	local threatened = near ~= nil or sight > 0.01
	if threatened then
		stealth.lastNear = now()
		if not stealth.serverSneaking() and now() - stealth.lastSent > 0.8 then
			stealth.sendSneak(true, true)
		end
	elseif stealth.owned and now() - stealth.lastNear > 2 then
		stealth.sendSneak(false)
	end
end

function stealth.coneFor(model)
	local e = stealth.cones[model]
	if e then return e end
	e = {
		left = newLine(Color3.fromRGB(110, 220, 140), 0.6, 1.5),
		right = newLine(Color3.fromRGB(110, 220, 140), 0.6, 1.5),
	}
	stealth.cones[model] = e
	return e
end

function stealth.hideCone(e)
	if not e then return end
	if e.left then e.left.Visible = false end
	if e.right then e.right.Visible = false end
end

function stealth.dropCone(model)
	local e = stealth.cones[model]
	if not e then return end
	removeDrawing(e.left)
	removeDrawing(e.right)
	stealth.cones[model] = nil
end

function stealth.project(cam, p)
	local v, onScreen = cam:WorldToViewportPoint(p)
	if not onScreen or v.Z <= 0 then return nil end
	return Vector2.new(v.X, v.Y)
end

function stealth.yaw(v, a)
	local c, s = math.cos(a), math.sin(a)
	return Vector3.new(v.X * c - v.Z * s, 0, v.X * s + v.Z * c)
end

function stealth.sightConeTick()
	stealth.frame = stealth.frame + 1
	local frame = stealth.frame
	if not CFG.sightCones then
		for _, e in pairs(stealth.cones) do stealth.hideCone(e) end
		return
	end
	local cam = workspace.CurrentCamera
	local root = charRoot()
	if not cam or not root then return end
	local myPos = root.Position
	local uid = tostring(LP.UserId)
	local range = math.clamp(tonumber(CFG.sightConeRange) or 55, 10, 200)
	local half = math.rad(35)

	for _, group in ipairs({ "Npcs", "Guards", "Police" }) do
		local folder = workspace:FindFirstChild(group)
		if folder and npcEnabled(group) then
			for _, model in ipairs(folder:GetChildren()) do
				if model:IsA("Model") then
					local hum = model:FindFirstChildOfClass("Humanoid")
					local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
					local head = model:FindFirstChild("Head") or hrp
					if hum and hrp and head and hum.Health > 0 then
						local dist = (hrp.Position - myPos).Magnitude
						if dist <= 220 then
							local e = stealth.coneFor(model)
							local look = head.CFrame.LookVector
							local flat = Vector3.new(look.X, 0, look.Z)
							if flat.Magnitude < 0.1 then
								look = hrp.CFrame.LookVector
								flat = Vector3.new(look.X, 0, look.Z)
							end
							if flat.Magnitude < 0.1 then flat = Vector3.new(0, 0, 1) end
							flat = flat.Unit
							local origin = head.Position
							local p0 = stealth.project(cam, origin)
							local pl = stealth.project(cam, origin + stealth.yaw(flat, -half) * range)
							local pr = stealth.project(cam, origin + stealth.yaw(flat, half) * range)
							local sight = tonumber(model:GetAttribute("Sight" .. uid)) or 0
							local color = sight >= 0.5 and Color3.fromRGB(255, 70, 70)
								or (sight > 0.01 and Color3.fromRGB(255, 205, 90)
								or Color3.fromRGB(110, 220, 140))
							if p0 and pl and pr then
								e.left.From, e.left.To = p0, pl
								e.right.From, e.right.To = p0, pr
								e.left.Color, e.right.Color = color, color
								e.left.Transparency, e.right.Transparency = 0.55, 0.55
								e.left.Thickness, e.right.Thickness = 1.5, 1.5
								e.left.Visible, e.right.Visible = true, true
								e.lastFrame = frame
							else
								stealth.hideCone(e)
							end
						end
					end
				end
			end
		end
	end

	for model, e in pairs(stealth.cones) do
		if not model.Parent then
			stealth.dropCone(model)
		elseif not e.lastFrame or e.lastFrame ~= frame then
			stealth.hideCone(e)
		end
	end
end

function stealth.toggleSneakNow()
	if stealth.serverSneaking() then
		local ok, err = stealth.sendSneak(false)
		if ok then notify("sneak off") else notify("sneak: " .. tostring(err)) end
		return
	end
	local ok, err = stealth.sendSneak(true)
	if ok then
		notify("sneak on - footsteps silent")
	else
		notify("sneak: " .. tostring(err))
	end
end

local function knockoutStand(model, part)
	local rootPart = model:FindFirstChild("HumanoidRootPart") or part
	local pos = part.Position
	local npcPos = rootPart.Position
	local look = rootPart.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.1 then look = Vector3.new(0, 0, 1) end
	look = look.Unit
	local dirs = {
		-look,
		Vector3.new(-look.Z, 0, look.X),
		Vector3.new(look.Z, 0, -look.X),
		look,
	}
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LP.Character }
	local fallback = nil
	for _, dir in ipairs(dirs) do
		for _, dist in ipairs({ 2.8, 3.8 }) do
			local stand = Vector3.new(npcPos.X + dir.X * dist, npcPos.Y - 2, npcPos.Z + dir.Z * dist)
			local from = Vector3.new(stand.X, npcPos.Y + 1.2, stand.Z)
			local hit = workspace:Raycast(from, pos - from, params)
			local clear = hit == nil or hit.Instance == part or hit.Instance:IsDescendantOf(model)
			if clear then return stand end
			if not fallback then fallback = stand end
		end
	end
	return fallback or Vector3.new(pos.X, npcPos.Y - 2, pos.Z + 3)
end

local function punchCount()
	local char = LP.Character
	local v = char and char:GetAttribute("Punches")
	return tonumber(v) or 0
end

local function punchClear(model, torso, from)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LP.Character }
	local hit = workspace:Raycast(from, torso.Position - from, params)
	if hit == nil then return false end
	local inst = hit.Instance
	return inst == torso or inst:IsDescendantOf(model)
end

local function knockoutNpc(model, silent, manual)
	if dead then return false, "panel unloaded" end
	if not model or not model.Parent then return false, "npc gone" end
	if knockoutBusy then return false, "knockout already running" end
	if escaping then return false, "escape in progress" end
	if hauling or grabbing then return false, "finish the current action first" end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false, "npc already down" end
	if npcKnockedOut(model) then return false, "npc already knocked out" end
	if not Remotes or not Remotes:FindFirstChild("Punch") then return false, "punch remote not found" end
	manual = manual ~= false

	knockoutBusy = true
	knockoutStop = false
	knockoutCurrent = model
	pcall(function()
		local h = charHumanoid()
		if h then h:UnequipTools() end
	end)
	local ok = false
	local reason = "not enough punches"
	local punches = 0
	local cam = workspace.CurrentCamera
	local oldType = cam and cam.CameraType or nil
	local oldCF = cam and cam.CFrame or nil
	local function restoreCam()
		if not cam then return end
		pcall(function()
			cam.CameraType = oldType
			cam.CFrame = oldCF
		end)
	end

	local callOk, callErr = pcall(function()
		local torso = model:FindFirstChild("UpperTorso")
			or model:FindFirstChild("Torso")
			or model:FindFirstChild("HumanoidRootPart")
			or partOf(model)
		if not torso then reason = "npc has no body part" return end
		local root = charRoot()
		if not root then reason = "character lost" return end

		-- auto mode never teleports: the game rubber-bands a long jump back
		-- within about 0.7 s, and a punch sent from the old position is
		-- rejected. only act when the npc is already in punch range.
		local dist = (root.Position - torso.Position).Magnitude
		if dist > 9.5 then
			if not manual then
				reason = string.format("out of punch range (%.0fm)", dist)
				return
			end
			local stand = knockoutStand(model, torso)
			local tOk, tErr = stepTeleport(stand)
			if not tOk then reason = tostring(tErr) return end
			task.wait(0.5)
			if dead or knockoutStop then reason = "stopped" return end
			root = charRoot()
			if not root then reason = "character lost" return end
		end

		local aim = nil
		pcall(function()
			aim = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MeleeAim"))
		end)

		local maxPunches = math.clamp(tonumber(CFG.knockoutPunches) or 6, 1, 10)
		local rejected = 0
		local lastPunches = punchCount()
		for _ = 1, maxPunches do
			if dead or knockoutStop then reason = "stopped" break end
			local h = model:FindFirstChildOfClass("Humanoid")
			if not h or h.Health <= 0 then ok = true reason = "dead" break end
			if npcKnockedOut(model) then ok = true reason = "knocked out" break end
			local r = charRoot()
			if not r then reason = "character lost" break end
			torso = model:FindFirstChild("UpperTorso")
				or model:FindFirstChild("Torso")
				or model:FindFirstChild("HumanoidRootPart")
				or partOf(model)
			if not torso then reason = "npc lost its body parts" break end
			r.CFrame = CFrame.lookAt(r.Position, torso.Position)
			if cam then
				cam.CameraType = Enum.CameraType.Scriptable
				cam.CFrame = CFrame.lookAt(r.Position + Vector3.new(0, 2, 0), torso.Position)
			end
			if not punchClear(model, torso, cam and cam.CFrame.Position or r.Position + Vector3.new(0, 2, 0)) then
				reason = "no clear line of sight"
				break
			end
			local targetPart = torso
			if aim then
				local aOk, aimed = pcall(aim.target, 9, { players = true })
				if aOk and aimed and aimed:IsDescendantOf(model) then
					targetPart = aimed
				end
			end
			local pOk = pcall(function() Remotes.Punch:FireServer(targetPart) end)
			punches = punches + 1
			if not pOk then reason = "punch remote failed" break end
			task.wait(0.55)
			local nowPunches = punchCount()
			if nowPunches <= lastPunches then
				rejected = rejected + 1
			else
				rejected = 0
			end
			lastPunches = nowPunches
			-- the server ignores punches from a stale position. two ignored
			-- swings in a row means retrying just alerts the npc for nothing.
			if rejected >= 2 then
				reason = "server rejected the punch (range / line of sight)"
				break
			end
		end
		if not ok then
			if npcKnockedOut(model) then ok = true reason = "knocked out" end
			local h = model:FindFirstChildOfClass("Humanoid")
			if h and h.Health <= 0 then ok = true reason = "dead" end
		end
	end)
	if not callOk then reason = tostring(callErr) end
	restoreCam()
	knockoutBusy = false
	knockoutCurrent = nil
	if not ok then failedKnockAt[model] = now() end
	if not silent then
		local name = tostring(model:GetAttribute("DisplayName") or model.Name)
		if ok then
			notify(string.format("knockout: %s down after %d punch%s (%s)", name, punches, punches == 1 and "" or "es", reason))
		elseif now() - lastKnockoutNotice > 6 then
			lastKnockoutNotice = now()
			notify("knockout failed on " .. name .. ": " .. tostring(reason))
		end
	end
	return ok, reason, punches
end

local function knockoutNearest()
	if hauling or grabbing then return false, "finish the current action first" end
	local targets = knockoutTargets(tonumber(CFG.knockoutRadius) or 25)
	if #targets == 0 then return false, "no npc in range" end
	return knockoutNpc(targets[1].model, false, true)
end

local function autoKnockoutStep()
	if dead or not CFG.autoKnockout or knockoutBusy or escaping then return end
	if hauling or grabbing then return end
	local radius = math.clamp(tonumber(CFG.knockoutRadius) or 25, 5, 200)
	local targets = knockoutTargets(radius)
	local pick = nil
	for _, target in ipairs(targets) do
		local failedAt = failedKnockAt[target.model]
		if not failedAt or now() - failedAt > 20 then
			pick = target
			break
		end
	end
	if not pick then return end
	knockoutNpc(pick.model, true, false)
end

--// auto escape ----------------------------------------------------------------

local function policeNear(radius)
	local root = charRoot()
	if not root then return nil end
	local folder = workspace:FindFirstChild("Police")
	if not folder then return nil end
	radius = math.clamp(tonumber(radius) or 60, 10, 300)
	local best, bestDist = nil, nil
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") then
			local hum = model:FindFirstChildOfClass("Humanoid")
			local part = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
			if hum and hum.Health > 0 and part then
				local d = (part.Position - root.Position).Magnitude
				if d <= radius and (not bestDist or d < bestDist) then
					best, bestDist = model, d
				end
			end
		end
	end
	return best, bestDist
end

local function escapeToHideout()
	local target = findHideout()
	if not target then return false, "hideout not found" end
	haulStop = true
	local ok, err = stepTeleport(target.Position)
	if ok then
		notify("escaped to the hideout")
	else
		notify("escape failed: " .. tostring(err))
	end
	return ok
end

--// sell now ------------------------------------------------------------------

local function sellNow()
	if findHeldLoot() then
		return false, "still holding loot - load it into the truck first"
	end
	local target = findSellLever() or findSellBox()
	if not target then return false, "sell box / lever not found" end
	local ok, err = stepTeleport(target.Position)
	if not ok then return false, tostring(err) end
	task.wait(0.8)
	return fireNearest(isSellPrompt, "sell")
end

--// teleport to selected -------------------------------------------------------

local function teleportToPlayer(name)
	local target = name and Players:FindFirstChild(name)
	local char = target and target.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false, "no target" end
	local ok, err = stepTeleport(hrp.Position)
	if ok then notify("teleported to " .. name) else notify("teleport failed: " .. tostring(err)) end
	return ok
end

--// auto loops -----------------------------------------------------------------

local function autoGrabStep()
	if grabbing or dead or not CFG.autoGrab then return end
	if hauling then return end

	local held = findHeldLoot()
	if held then
		if CFG.autoLoad then
			local ok, err = deliverHeld()
			if ok then
				notify("loaded " .. tostring(held:GetAttribute("DisplayName") or held.Name) .. " into the truck")
			elseif now() - lastGrabNotice > 8 then
				lastGrabNotice = now()
				notify("auto load: " .. tostring(err))
			end
		elseif now() - lastGrabNotice > 8 then
			lastGrabNotice = now()
			notify("auto grab is holding an item; turn on auto load or drop it")
		end
		return
	end

	local target = bestLoot("nearest", tonumber(CFG.grabRadius) or 0)
	if not target then return end
	if failedGrabAt[target.model] and now() - failedGrabAt[target.model] < 25 then return end

	local ok, err = faceAndGrab(target.model)
	if ok then
		notify(string.format("grabbed %s (%s)", target.name, money(target.value)))
		if CFG.autoLoad then
			local delivered, derr = deliverHeld()
			if delivered then
				notify("loaded " .. target.name .. " into the truck")
			elseif now() - lastGrabNotice > 8 then
				lastGrabNotice = now()
				notify("auto load: " .. tostring(derr))
			end
		end
	else
		failedGrabAt[target.model] = now()
		if now() - lastGrabNotice > 8 then
			lastGrabNotice = now()
			notify(string.format("grab failed on %s: %s", target.name, tostring(err)))
		end
	end
end

local function rejoin()
	notify("rejoining")
	pcall(function()
		TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
	end)
end

--// max mode preset -------------------------------------------------------------

local function maxMode()
	if dead then return end
	CFG.lootEsp = true
	CFG.maxStrength = true
	CFG.autoGrab = true
	CFG.autoLoad = true
	CFG.autoHaul = true
	CFG.autoHaulDelay = 20
	CFG.haulRadius = 250
	CFG.haulLimit = 25
	CFG.autoKnockout = true
	CFG.knockoutRadius = 20
	CFG.knockoutPunches = 6
	CFG.autoEscape = true
	CFG.autoEscapeRadius = 50
	CFG.autoDoors = true
	CFG.autoDoorsRadius = 60
	CFG.antiDetect = true
	CFG.antiDetectRadius = 50
	CFG.sightCones = true
	CFG.sightConeRange = 55
	CFG.sightWarn = true
	CFG.customSpeed = true
	CFG.walkSpeed = 60
	CFG.speedGuard = true
	CFG.speedNoCap = false
	CFG.infiniteStamina = true
	CFG.noclip = true
	CFG.fullbright = true
	CFG.noFog = true
	CFG.fovOn = true
	CFG.fov = 90

	if ui.window then
		for _, flag in ipairs({
			"crim_lootesp", "crim_maxstrength", "crim_autograb", "crim_autoload",
			"crim_autohaul", "crim_autoknock", "crim_autoescape", "crim_autodoors",
			"crim_antidetect", "crim_sightcones", "crim_sightwarn",
			"crim_speed", "crim_infstam", "crim_noclip",
			"crim_fullbright", "crim_nofog", "crim_fovon",
		}) do
			pcall(function() ui.window:Set(flag, true) end)
		end
		for flag, value in pairs({
			crim_haulradius = 250,
			crim_haullimit = 25,
			crim_autohauldelay = 20,
			crim_knockradius = 20,
			crim_knockpunches = 6,
			crim_escaperadius = 50,
			crim_doorradius = 60,
			crim_antidetectradius = 50,
			crim_sightrange = 55,
			crim_ws = 60,
			crim_fov = 90,
		}) do
			pcall(function() ui.window:Set(flag, value) end)
		end
	end

	pcall(startSpeed)
	pcall(strength.apply)
	pcall(applyFullbright)
	pcall(applyNoFog)
	pcall(staminaTick)
	local cam = workspace.CurrentCamera
	if cam then cam.FieldOfView = 90 end
	notify("MAX MODE: loot esp, max strength, auto grab/load, auto haul (25 max, 250m), auto knockout, auto escape, auto doors, anti-detect sneak + sight cones, speed 60, stamina, noclip, fullbright, no fog, fov 90. fly stays as-is.")
end

--// panic / shutdown ------------------------------------------------------------

local function hideEverything()
	for _, e in pairs(lootPool) do hideLootEsp(e) end
	for _, e in pairs(playerPool) do hideHumanoidEsp(e) end
	for _, e in pairs(npcPool) do hideHumanoidEsp(e) end
end

local panic

local function shutdown()
	if dead then return end
	if stealth.owned then stealth.sendSneak(false) end
	dead = true
	haulStop = true
	knockoutStop = true
	stopFly()
	stopSpeed()
	stopJump()
	restoreMovement()
	restoreStamina()
	pcall(strength.restore)
	if jumpRequestConn then pcall(function() jumpRequestConn:Disconnect() end) end
	if ui.loopConn then pcall(function() ui.loopConn:Disconnect() end) end
	if ui.keyConn then pcall(function() ui.keyConn:Disconnect() end) end
	if ui.charConn then pcall(function() ui.charConn:Disconnect() end) end
	if ui.removeConn then pcall(function() ui.removeConn:Disconnect() end) end
	restoreNoclip()
	restoreVisuals()
	clearDrawings()
	stealth.cones = {}
	npcDetailTeardown()
	lootPool = {}
	playerPool = {}
	npcPool = {}
	if ui.window then pcall(function() ui.window:Unload() end) end
	_G.CriminalPanel = { cfg = CFG }
	print("[CRIMINAL] unloaded")
end

panic = function()
	if dead then return end
	haulStop = true
	knockoutStop = true
	CFG.lootEsp = false
	CFG.maxStrength = false
	CFG.autoGrab = false
	CFG.autoLoad = false
	CFG.autoHaul = false
	CFG.autoKnockout = false
	CFG.autoEscape = false
	CFG.autoDoors = false
	CFG.antiDetect = false
	CFG.sightCones = false
	CFG.sightWarn = false
	if stealth.owned then stealth.sendSneak(false) end
	for _, e in pairs(stealth.cones) do stealth.hideCone(e) end
	CFG.fly = false
	CFG.autoRob = false
	CFG.npcEsp = false
	CFG.npcTags = false
	CFG.npcDetails = false
	CFG.playerEsp = false
	CFG.customSpeed = false
	CFG.speedNoCap = false
	CFG.infiniteStamina = false
	CFG.customJump = false
	CFG.infiniteJump = false
	CFG.noclip = false
	CFG.fullbright = false
	CFG.noFog = false
	CFG.fovOn = false
	stopFly()
	stopSpeed()
	stopJump()
	restoreMovement()
	restoreStamina()
	pcall(strength.restore)
	restoreNoclip()
	restoreVisuals()
	hideEverything()
	npcDetailTeardown()
	if ui.window then
		for _, flag in ipairs({
			"crim_lootesp", "crim_maxstrength", "crim_autograb", "crim_autoload", "crim_autorb",
			"crim_autohaul", "crim_autoknock", "crim_autoescape", "crim_autodoors",
			"crim_antidetect", "crim_sightcones", "crim_sightwarn",
			"crim_npcesp", "crim_npctags", "crim_npcdetails", "crim_pesp",
			"crim_speed", "crim_infstam",
			"crim_speednocap", "crim_jump",
			"crim_infjump", "crim_noclip", "crim_fullbright", "crim_nofog", "crim_fovon",
			"crim_fly",
		}) do
			pcall(function() ui.window:Set(flag, false) end)
		end
	end
	pushLog("panic")
	print("[CRIMINAL] panic")
end

--// UI --------------------------------------------------------------------------

local Rayfield
pcall(function()
	Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)

local function buildUI()
	if not Rayfield then
		warn("[CRIMINAL] Rayfield failed to load")
		return
	end

	local w = Rayfield:CreateWindow({
		Name = "CRIMINAL // SIMULATOR",
		LoadingTitle = "CRIMINAL SIMULATOR // HEIST PANEL",
		LoadingSubtitle = "loot esp  -  prompt sniper  -  movement",
		KeySystem = false,
	})
	ui.window = w

	pcall(function()
		w:ChangeTheme({
			WindowColor = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(12, 10, 14)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 20, 18)),
			}),
			ShadowColor = Color3.fromRGB(6, 5, 4),
			CornerRoundness = UDim.new(0, 16),
			ElementCornerRadius = UDim.new(0, 10),
			PillCornerRadius = UDim.new(1, 0),
			AccentColor = Color3.fromRGB(255, 196, 92),
		})
	end)

	-- LOOT
	local lootTab = w:CreateTab({ Name = "LOOT" })
	lootTab:CreateSection({ Name = "LOOT ESP" })
	lootTab:CreateToggle({
		Name = "loot esp",
		Description = "draws stealable loot through walls with display name, value, weight and distance.",
		Flag = "crim_lootesp",
		Value = CFG.lootEsp,
		Callback = function(v)
			CFG.lootEsp = v
			if not v then
				for _, e in pairs(lootPool) do hideLootEsp(e) end
			end
		end,
	})
	lootTab:CreateSlider({
		Name = "minimum value",
		Range = { 0, 1000 },
		Increment = 25,
		Value = CFG.lootMinValue,
		Suffix = " $",
		Flag = "crim_lootmin",
		Callback = function(v) CFG.lootMinValue = v end,
	})
	lootTab:CreateSlider({
		Name = "range",
		Description = "0 = no limit.",
		Range = { 0, 600 },
		Increment = 25,
		Value = CFG.lootRadius,
		Suffix = " m",
		Flag = "crim_lootradius",
		Callback = function(v) CFG.lootRadius = v end,
	})
	lootTab:CreateSlider({
		Name = "max labels",
		Range = { 20, 300 },
		Increment = 10,
		Value = CFG.lootMaxLabels,
		Flag = "crim_lootmax",
		Callback = function(v) CFG.lootMaxLabels = v end,
	})
	lootTab:CreateToggle({
		Name = "hide held loot",
		Description = "hides loot carried by other players. your own held item stays visible.",
		Flag = "crim_loothide",
		Value = CFG.lootHideHeld,
		Callback = function(v) CFG.lootHideHeld = v end,
	})
	lootTab:CreateToggle({
		Name = "only liftable",
		Description = "hides weight-2+ loot until your Shop_Lifter is high enough.",
		Flag = "crim_lootlift",
		Value = CFG.lootOnlyLiftable,
		Callback = function(v) CFG.lootOnlyLiftable = v end,
	})
	lootTab:CreateToggle({
		Name = "max strength",
		Description = "locks local Lifter to 2 (the game's max, enough for every weight-3 item) and turns on Strong Back locally so heavy loot no longer slows you. client-side only: the server still owns the real upgrade and can reject a grab if your actual Lifter is too low.",
		Flag = "crim_maxstrength",
		Value = CFG.maxStrength,
		Callback = function(v) strength.set(v) end,
	})

	lootTab:CreateSection({ Name = "GRAB  (BEST EFFORT)" })
	ui.lootInfo = lootTab:CreateText({ Name = "loot", Text = "scanning" })
	lootTab:CreateButton({
		Name = "grab nearest loot",
		Description = "steps to the item, faces it, then fires the game's own LootGrab remote.",
		Callback = function()
			if hauling then notify("stop the haul first") return end
			local target = bestLoot("nearest", tonumber(CFG.grabRadius) or 0)
			if not target then
				notify("no matching loot in range")
				return
			end
			local ok, err = faceAndGrab(target.model)
			if ok then
				notify(string.format("grabbed %s (%s)", target.name, money(target.value)))
			else
				notify("grab failed: " .. tostring(err))
			end
		end,
	})
	lootTab:CreateButton({
		Name = "grab highest value",
		Description = "same as grab nearest, but picks the most valuable matching item.",
		Callback = function()
			if hauling then notify("stop the haul first") return end
			local target = bestLoot("value", tonumber(CFG.grabRadius) or 0)
			if not target then
				notify("no matching loot in range")
				return
			end
			local ok, err = faceAndGrab(target.model)
			if ok then
				notify(string.format("grabbed %s (%s)", target.name, money(target.value)))
			else
				notify("grab failed: " .. tostring(err))
			end
		end,
	})
	lootTab:CreateToggle({
		Name = "auto grab",
		Description = "repeats grab nearest inside the search radius. hidden or room-locked loot can still be rejected by the server.",
		Flag = "crim_autograb",
		Value = CFG.autoGrab,
		Callback = function(v) CFG.autoGrab = v end,
	})
	lootTab:CreateToggle({
		Name = "auto load truck",
		Description = "after each grab, steps to the nearest truck cargo zone and fires LootRelease.",
		Flag = "crim_autoload",
		Value = CFG.autoLoad,
		Callback = function(v) CFG.autoLoad = v end,
	})
	lootTab:CreateSlider({
		Name = "auto-grab search radius",
		Range = { 25, 500 },
		Increment = 25,
		Value = CFG.grabRadius,
		Suffix = " m",
		Flag = "crim_grabradius",
		Callback = function(v) CFG.grabRadius = v end,
	})
	lootTab:CreateButton({
		Name = "drop held item",
		Callback = function()
			if hauling then notify("stop the haul first") return end
			local ok, err = dropHeld()
			notify(ok and "dropped held item" or ("drop failed: " .. tostring(err)))
		end,
	})
	lootTab:CreateButton({
		Name = "load held item into truck",
		Description = "steps to the cargo zone and releases. the game decides whether it counts toward the quota.",
		Callback = function()
			if hauling then notify("stop the haul first") return end
			local ok, err = deliverHeld()
			notify(ok and "released at the truck cargo zone" or ("load failed: " .. tostring(err)))
		end,
	})

	lootTab:CreateSection({ Name = "HAUL TO TRUCK" })
	lootTab:CreateText({
		Name = "haul note",
		Text = "one-shot run: steps to each unheld liftable item within the haul radius, grabs it with the game's LootGrab, then releases at the nearest truck cargo zone. it uses the min value filter. room-locked loot and police can still stop it; the game decides whether each release counts toward quota.",
	})
	lootTab:CreateSlider({
		Name = "haul radius",
		Description = "how far from you the haul will look. 250 m covers most of one town block.",
		Range = { 25, 2000 },
		Increment = 25,
		Value = CFG.haulRadius,
		Suffix = " m",
		Flag = "crim_haulradius",
		Callback = function(v)
			CFG.haulRadius = v
			refreshHaulInfo()
		end,
	})
	lootTab:CreateSlider({
		Name = "haul max items",
		Description = "0 = every matching item. 25 is a good quick run.",
		Range = { 0, 100 },
		Increment = 5,
		Value = CFG.haulLimit,
		Suffix = " items",
		Flag = "crim_haullimit",
		Callback = function(v) CFG.haulLimit = v end,
	})
	lootTab:CreateToggle({
		Name = "auto haul loop",
		Description = "repeats the haul while it has targets. stops when panic, unload, death or stop haul is used.",
		Flag = "crim_autohaul",
		Value = CFG.autoHaul,
		Callback = function(v) CFG.autoHaul = v end,
	})
	lootTab:CreateSlider({
		Name = "auto haul delay",
		Description = "wait between automatic hauls.",
		Range = { 10, 300 },
		Increment = 5,
		Value = CFG.autoHaulDelay,
		Suffix = " s",
		Flag = "crim_autohauldelay",
		Callback = function(v) CFG.autoHaulDelay = v end,
	})
	lootTab:CreateButton({
		Name = "haul all items to truck",
		Description = "teleports to each matching item, grabs it, teleports to the nearest truck and releases. stop haul aborts after the current item.",
		Callback = function()
			task.spawn(function()
				local limit = tonumber(CFG.haulLimit) or 0
				local ok, err = pcall(haulAll, limit > 0 and limit or nil)
				if not ok then notify("haul error: " .. tostring(err)) end
			end)
		end,
	})
	lootTab:CreateButton({
		Name = "stop haul",
		Callback = function()
			if not hauling then
				notify("no haul running")
				return
			end
			haulStop = true
			notify("stopping haul after the current item")
		end,
	})
	ui.haulInfo = lootTab:CreateText({ Name = "haul status", Text = "idle" })
	refreshHaulInfo()

	lootTab:CreateText({
		Name = "note",
		Text = "grab works by stepping next to the loot and facing it. hidden containers and locked rooms are server-side; failures are reported.",
	})

	-- WORLD
	local worldTab = w:CreateTab({ Name = "WORLD" })
	worldTab:CreateSection({ Name = "NPC ESP" })
	worldTab:CreateToggle({
		Name = "npc esp",
		Description = "residents, guards and police with box, name, distance and health.",
		Flag = "crim_npcesp",
		Value = CFG.npcEsp,
		Callback = function(v)
			CFG.npcEsp = v
			if not v then
				for _, e in pairs(npcPool) do hideHumanoidEsp(e) end
			end
		end,
	})
	worldTab:CreateToggle({
		Name = "residents  [Npcs]",
		Flag = "crim_npcres",
		Value = CFG.npcResidents,
		Callback = function(v) CFG.npcResidents = v end,
	})
	worldTab:CreateToggle({
		Name = "guards  [Guards]",
		Flag = "crim_npcguard",
		Value = CFG.npcGuards,
		Callback = function(v) CFG.npcGuards = v end,
	})
	worldTab:CreateToggle({
		Name = "police  [Police]",
		Flag = "crim_npcpol",
		Value = CFG.npcPolice,
		Callback = function(v) CFG.npcPolice = v end,
	})
	worldTab:CreateToggle({
		Name = "names",
		Flag = "crim_npcname",
		Value = CFG.npcName,
		Callback = function(v) CFG.npcName = v end,
	})
	worldTab:CreateToggle({
		Name = "distance",
		Flag = "crim_npcdist",
		Value = CFG.npcDistance,
		Callback = function(v) CFG.npcDistance = v end,
	})
	worldTab:CreateToggle({
		Name = "health bar",
		Flag = "crim_npchp",
		Value = CFG.npcHealth,
		Callback = function(v) CFG.npcHealth = v end,
	})
	worldTab:CreateToggle({
		Name = "box",
		Flag = "crim_npcbox",
		Value = CFG.npcBox,
		Callback = function(v) CFG.npcBox = v end,
	})
	worldTab:CreateToggle({
		Name = "detail tags",
		Description = "adds state, gender, outfit, home and spot to each npc label. off by default to keep the screen clean.",
		Flag = "crim_npctags",
		Value = CFG.npcTags,
		Callback = function(v) CFG.npcTags = v end,
	})
	ui.npcInfo = worldTab:CreateText({ Name = "npc counts", Text = "-" })
	ui.npcDrop = worldTab:CreateDropdown({
		Name = "npc",
		Description = "pick an npc to stand next to.",
		Options = scanNpcs(),
		Placeholder = "nobody picked",
		Flag = "crim_npc",
		Callback = function(v)
			selectedNpc = npcOptions[v]
		end,
	})
	worldTab:CreateButton({
		Name = "refresh npc list",
		Callback = function()
			local options = scanNpcs()
			if ui.npcDrop then pcall(function() ui.npcDrop:Refresh(options) end) end
			notify("npc list refreshed")
		end,
	})
	worldTab:CreateButton({
		Name = "teleport to npc",
		Callback = function()
			if not selectedNpc or not selectedNpc.Parent then
				notify("pick a live npc first")
				return
			end
			local part = partOf(selectedNpc)
			if part then
				teleportTo(part, selectedNpc.Name, Vector3.new(0, 0, 4))
			else
				notify("npc has no part")
			end
		end,
	})

	worldTab:CreateSection({ Name = "NPC DETAILS" })
	worldTab:CreateToggle({
		Name = "npc details window",
		Description = "draggable list of every resident, guard and police: health, distance, state, gender, outfit, home and spot. updates live and sorts by nearest.",
		Flag = "crim_npcdetails",
		Value = CFG.npcDetails,
		Callback = function(v)
			CFG.npcDetails = v
			if v then
				pcall(npcDetailBuild)
				npcDetailAt = 0
				pcall(npcDetailTick)
			else
				npcDetailTeardown()
			end
			pcall(saveCfg)
		end,
	})
	worldTab:CreateButton({
		Name = "dump all npc details",
		Description = "prints every npc with its full attribute list to the console and slimhub-npc-details.txt in the workspace folder.",
		Callback = function()
			pcall(npcDetailDump)
		end,
	})
	worldTab:CreateText({
		Name = "npc details note",
		Text = "details come from the model's own attributes and humanoid. state = the game's routine/post value. nothing is invented.",
	})

	worldTab:CreateSection({ Name = "AUTO KNOCKOUT  (PUNCH)" })
	worldTab:CreateText({
		Name = "knockout note",
		Text = "uses the game's own Punch remote and stops early if the server ignores two swings. auto mode only punches an npc already within punch range (about 9 m) with a clear line of sight - it does not teleport, because the game pulls a long jump back before the punch lands. the manual button can step to the target once, but is still best effort. guards and police can react. pauses while a grab or haul is running.",
	})
	worldTab:CreateToggle({
		Name = "auto knockout nearby",
		Flag = "crim_autoknock",
		Value = CFG.autoKnockout,
		Callback = function(v) CFG.autoKnockout = v end,
	})
	worldTab:CreateSlider({
		Name = "knockout radius",
		Range = { 5, 200 },
		Increment = 5,
		Value = CFG.knockoutRadius,
		Suffix = " m",
		Flag = "crim_knockradius",
		Callback = function(v) CFG.knockoutRadius = v end,
	})
	worldTab:CreateSlider({
		Name = "max punches",
		Range = { 1, 10 },
		Increment = 1,
		Value = CFG.knockoutPunches,
		Suffix = " hits",
		Flag = "crim_knockpunches",
		Callback = function(v) CFG.knockoutPunches = v end,
	})
	worldTab:CreateButton({
		Name = "knock out nearest  (best effort)",
		Description = "steps to the nearest npc in range and punches until it goes down or the server rejects two swings.",
		Callback = function()
			task.spawn(function()
				local ok, err = knockoutNearest()
				if not ok then notify("knockout: " .. tostring(err)) end
			end)
		end,
	})
	ui.knockInfo = worldTab:CreateText({ Name = "knockout status", Text = "off" })

	worldTab:CreateSection({ Name = "AUTO ESCAPE" })
	worldTab:CreateToggle({
		Name = "auto escape on police",
		Description = "when a live police officer is inside the radius, stops the haul and teleports to the hideout. best effort; a teleport can still be seen or pulled back.",
		Flag = "crim_autoescape",
		Value = CFG.autoEscape,
		Callback = function(v) CFG.autoEscape = v end,
	})
	worldTab:CreateSlider({
		Name = "escape radius",
		Range = { 20, 300 },
		Increment = 10,
		Value = CFG.autoEscapeRadius,
		Suffix = " m",
		Flag = "crim_escaperadius",
		Callback = function(v) CFG.autoEscapeRadius = v end,
	})
	worldTab:CreateButton({
		Name = "escape to hideout now",
		Callback = function()
			local ok, err = escapeToHideout()
			if not ok then notify("escape: " .. tostring(err)) end
		end,
	})
	ui.escapeInfo = worldTab:CreateText({ Name = "escape status", Text = "off" })

	worldTab:CreateSection({ Name = "STEALTH / ANTI-DETECT" })
	worldTab:CreateText({
		Name = "stealth note",
		Text = "auto sneak uses the game's own Sneak remote. the game's own loading tip says crouching makes no walking noise, so this silences footsteps while a live npc is close. it does not make you invisible: server-side sight checks and cameras can still see you. sight cones are a rough 70-degree guess from each npc's head, not the server's exact check.",
	})
	worldTab:CreateToggle({
		Name = "anti-detect  (auto sneak)",
		Description = "fires the game's Sneak remote near live npcs and stands you back up after 2 s clear. no cash, no invisibility.",
		Flag = "crim_antidetect",
		Value = CFG.antiDetect,
		Callback = function(v)
			CFG.antiDetect = v
			if not v and stealth.auto then stealth.sendSneak(false) end
		end,
	})
	worldTab:CreateSlider({
		Name = "anti-detect radius",
		Range = { 5, 120 },
		Increment = 5,
		Value = CFG.antiDetectRadius,
		Suffix = " m",
		Flag = "crim_antidetectradius",
		Callback = function(v) CFG.antiDetectRadius = v end,
	})
	worldTab:CreateToggle({
		Name = "show npc sight cones",
		Description = "draws an estimated view wedge from each npc's head. green = clear, yellow = noticing, red = high sight.",
		Flag = "crim_sightcones",
		Value = CFG.sightCones,
		Callback = function(v)
			CFG.sightCones = v
			if not v then
				for _, e in pairs(stealth.cones) do stealth.hideCone(e) end
			end
		end,
	})
	worldTab:CreateSlider({
		Name = "sight cone length",
		Range = { 15, 150 },
		Increment = 5,
		Value = CFG.sightConeRange,
		Suffix = " m",
		Flag = "crim_sightrange",
		Callback = function(v) CFG.sightConeRange = v end,
	})
	worldTab:CreateToggle({
		Name = "sight warning",
		Description = "reads the game's own Sight<userId> attribute and warns when an npc is noticing you.",
		Flag = "crim_sightwarn",
		Value = CFG.sightWarn,
		Callback = function(v) CFG.sightWarn = v end,
	})
	worldTab:CreateButton({
		Name = "sneak / stand now",
		Description = "toggles the game's own Sneak remote once. auto-detect can re-enable it while an npc is still close.",
		Callback = function() stealth.toggleSneakNow() end,
	})
	ui.sightInfo = worldTab:CreateText({ Name = "stealth status", Text = "off" })

	worldTab:CreateSection({ Name = "PROMPT SNIPER" })
	worldTab:CreateText({
		Name = "how it works",
		Text = "enabled proximity prompts can be fired from any distance. this uses the game's own prompts, not remotes.",
	})
	worldTab:CreateButton({
		Name = "rob all containers now",
		Description = "fires every enabled Rob Items / Rob Mailbox / Steal prompt once.",
		Callback = function()
			local fired, skipped, err = fireMatching(isRobPrompt, 0, "rob sweep")
			if err then notify(err) else notify(string.format("rob sweep: %d fired, %d skipped", fired, skipped)) end
		end,
	})
	worldTab:CreateButton({
		Name = "open doors now",
		Description = "fires every enabled Open / Climb Through prompt once.",
		Callback = function()
			local fired, skipped, err = fireMatching(isOpenPrompt, 0, "door sweep")
			if err then notify(err) else notify(string.format("door sweep: %d fired, %d skipped", fired, skipped)) end
		end,
	})
	worldTab:CreateButton({
		Name = "send truck home",
		Description = "fires the nearest enabled Head Home prompt.",
		Callback = function()
			local ok, err = fireNearest(isHomePrompt, "head home")
			notify(ok and "fired Head Home" or ("head home failed: " .. tostring(err)))
		end,
	})
	worldTab:CreateButton({
		Name = "fire nearest sell prompt",
		Description = "fires the nearest enabled prompt with Sell in the action text.",
		Callback = function()
			local ok, err = fireNearest(isSellPrompt, "sell")
			notify(ok and "fired sell prompt" or ("sell failed: " .. tostring(err)))
		end,
	})
	worldTab:CreateToggle({
		Name = "auto rob containers",
		Description = "sweeps enabled Rob prompts every few seconds with a per-prompt cooldown.",
		Flag = "crim_autorb",
		Value = CFG.autoRob,
		Callback = function(v) CFG.autoRob = v end,
	})
	worldTab:CreateToggle({
		Name = "auto open nearby doors",
		Description = "fires enabled Open / Climb Through prompts around you with a per-prompt cooldown. helps with loot inside houses.",
		Flag = "crim_autodoors",
		Value = CFG.autoDoors,
		Callback = function(v) CFG.autoDoors = v end,
	})
	worldTab:CreateSlider({
		Name = "door sweep radius",
		Range = { 15, 150 },
		Increment = 5,
		Value = CFG.autoDoorsRadius,
		Suffix = " m",
		Flag = "crim_doorradius",
		Callback = function(v) CFG.autoDoorsRadius = v end,
	})
	ui.promptInfo = worldTab:CreateText({ Name = "last sweep", Text = "-" })

	worldTab:CreateSection({ Name = "TRAVEL" })
	worldTab:CreateButton({
		Name = "truck cargo zone",
		Callback = function() teleportTo(findCargoZone(), "truck cargo") end,
	})
	worldTab:CreateButton({
		Name = "sell box  (truck must be home)",
		Callback = function() teleportTo(findSellBox(), "sell box", Vector3.new(0, 3, 0)) end,
	})
	worldTab:CreateButton({
		Name = "sell lever  (truck must be home)",
		Callback = function() teleportTo(findSellLever(), "sell lever", Vector3.new(0, 3, 0)) end,
	})
	worldTab:CreateButton({
		Name = "sell now  (truck must be home)",
		Description = "teleports to the hideout sell lever/box and fires the game's own Sell prompt. send the truck home first if it is out.",
		Callback = function()
			task.spawn(function()
				local ok, err = sellNow()
				notify(ok and "fired the sell prompt" or ("sell failed: " .. tostring(err)))
			end)
		end,
	})
	worldTab:CreateButton({
		Name = "chop shop",
		Callback = function() teleportTo((nearestTagPart("ChopShop")), "chop shop") end,
	})
	worldTab:CreateButton({
		Name = "hideout",
		Callback = function() teleportTo(findHideout(), "hideout") end,
	})
	worldTab:CreateButton({
		Name = "shop computer",
		Callback = function() teleportTo(findShopComputer(), "shop computer", Vector3.new(0, 2, 4)) end,
	})
	worldTab:CreateButton({
		Name = "job board",
		Callback = function() teleportTo(findJobBoard(), "job board", Vector3.new(0, 2, 4)) end,
	})

	-- PLAYERS
	local playersTab = w:CreateTab({ Name = "PLAYERS" })
	playersTab:CreateSection({ Name = "ESP" })
	playersTab:CreateToggle({
		Name = "player esp",
		Description = "box, name, distance, health and tracer for every other player.",
		Flag = "crim_pesp",
		Value = CFG.playerEsp,
		Callback = function(v)
			CFG.playerEsp = v
			if not v then
				for _, e in pairs(playerPool) do hideHumanoidEsp(e) end
			end
		end,
	})
	playersTab:CreateToggle({
		Name = "names",
		Flag = "crim_pname",
		Value = CFG.playerEspName,
		Callback = function(v) CFG.playerEspName = v end,
	})
	playersTab:CreateToggle({
		Name = "distance",
		Flag = "crim_pdist",
		Value = CFG.playerEspDistance,
		Callback = function(v) CFG.playerEspDistance = v end,
	})
	playersTab:CreateToggle({
		Name = "health bar",
		Flag = "crim_php",
		Value = CFG.playerEspHealth,
		Callback = function(v) CFG.playerEspHealth = v end,
	})
	playersTab:CreateToggle({
		Name = "box",
		Flag = "crim_pbox",
		Value = CFG.playerEspBox,
		Callback = function(v) CFG.playerEspBox = v end,
	})
	playersTab:CreateToggle({
		Name = "tracer",
		Flag = "crim_ptracer",
		Value = CFG.playerEspTracer,
		Callback = function(v) CFG.playerEspTracer = v end,
	})
	playersTab:CreateSection({ Name = "TELEPORT" })
	ui.playerDrop = playersTab:CreateDropdown({
		Name = "player",
		Options = playerNames(),
		Placeholder = "nobody picked",
		Flag = "crim_target",
		Callback = function(v) selectedPlayer = v end,
	})
	playersTab:CreateButton({
		Name = "refresh player list",
		Callback = function()
			if ui.playerDrop then pcall(function() ui.playerDrop:Refresh(playerNames()) end) end
			notify("player list refreshed")
		end,
	})
	playersTab:CreateButton({
		Name = "teleport to player",
		Callback = function()
			if not selectedPlayer then
				notify("pick a player first")
				return
			end
			teleportToPlayer(selectedPlayer)
		end,
	})

	-- MOVEMENT
	local moveTab = w:CreateTab({ Name = "MOVEMENT" })
	moveTab:CreateSection({ Name = "SPEED" })
	moveTab:CreateToggle({
		Name = "custom walk speed",
		Description = "holds your walk speed against the game's own writes. the speed guard decides how high it actually goes.",
		Flag = "crim_speed",
		Value = CFG.customSpeed,
		Callback = function(v)
			CFG.customSpeed = v
			if v then
				startSpeed()
			else
				stopSpeed()
				local hum = charHumanoid()
				if hum and baseWalk then hum.WalkSpeed = baseWalk end
				baseWalk = nil
			end
		end,
	})
	moveTab:CreateToggle({
		Name = "speed guard (anti-cheat)",
		Description = "caps at the safe speed below and ramps changes instead of snapping. leave this on for normal play.",
		Flag = "crim_speedguard",
		Value = CFG.speedGuard,
		Callback = function(v)
			CFG.speedGuard = v
			local hum = charHumanoid()
			if hum then speedNow = hum.WalkSpeed end
		end,
	})
	moveTab:CreateSlider({
		Name = "safe speed cap",
		Description = "the game's own sprint speed is about 60 ws.",
		Range = { 16, 100 },
		Increment = 1,
		Value = CFG.speedCap,
		Suffix = " ws",
		Flag = "crim_speedcap",
		Callback = function(v) CFG.speedCap = v end,
	})
	moveTab:CreateToggle({
		Name = "ignore safe cap",
		Description = "lets the slider go above the cap. server movement checks can pull you back or kick you; that part cannot be fully bypassed.",
		Flag = "crim_speednocap",
		Value = CFG.speedNoCap,
		Callback = function(v) CFG.speedNoCap = v end,
	})
	moveTab:CreateSlider({
		Name = "walk speed",
		Range = { 16, 200 },
		Increment = 1,
		Value = CFG.walkSpeed,
		Suffix = " ws",
		Flag = "crim_ws",
		Callback = function(v) CFG.walkSpeed = v end,
	})
	ui.speedInfo = moveTab:CreateText({ Name = "speed status", Text = "..." })
	moveTab:CreateSection({ Name = "JUMP" })
	moveTab:CreateToggle({
		Name = "custom jump power",
		Flag = "crim_jump",
		Value = CFG.customJump,
		Callback = function(v)
			CFG.customJump = v
			if v then
				startJump()
			else
				stopJump()
				local hum = charHumanoid()
				if hum and baseJump then hum.JumpPower = baseJump end
				baseJump = nil
			end
		end,
	})
	moveTab:CreateSlider({
		Name = "jump power",
		Range = { 50, 250 },
		Increment = 5,
		Value = CFG.jumpPower,
		Suffix = " jp",
		Flag = "crim_jp",
		Callback = function(v)
			CFG.jumpPower = v
			local hum = charHumanoid()
			if CFG.customJump and hum then hum.JumpPower = v end
		end,
	})
	moveTab:CreateToggle({
		Name = "infinite jump",
		Description = "every jump request re-enters the jumping state.",
		Flag = "crim_infjump",
		Value = CFG.infiniteJump,
		Callback = function(v) CFG.infiniteJump = v end,
	})
	moveTab:CreateSection({ Name = "STAMINA" })
	moveTab:CreateToggle({
		Name = "infinite stamina",
		Description = "keeps the sprint stamina bar full and stops the winded state. uses the game's own zero-drain path; it does not make you invincible.",
		Flag = "crim_infstam",
		Value = CFG.infiniteStamina,
		Callback = function(v)
			CFG.infiniteStamina = v
			if not v then restoreStamina() end
		end,
	})
	moveTab:CreateSection({ Name = "COLLISION" })
	moveTab:CreateToggle({
		Name = "noclip",
		Description = "turns collision off on your own character parts only.",
		Flag = "crim_noclip",
		Value = CFG.noclip,
		Callback = function(v)
			CFG.noclip = v
			if not v then restoreNoclip() end
		end,
	})

	moveTab:CreateSection({ Name = "FLY  (CLIENT-SIDE)" })
	moveTab:CreateToggle({
		Name = "fly",
		Description = "client-side body velocity. WASD moves, Space goes up, LeftControl goes down. the server can still pull or kick a flying character; that part is not promised.",
		Flag = "crim_fly",
		Value = CFG.fly,
		Callback = function(v)
			CFG.fly = v
			if v then startFly() else stopFly() end
		end,
	})
	moveTab:CreateSlider({
		Name = "fly speed",
		Range = { 10, 300 },
		Increment = 10,
		Value = CFG.flySpeed,
		Suffix = " ws",
		Flag = "crim_flyspeed",
		Callback = function(v) CFG.flySpeed = v end,
	})
	ui.flyInfo = moveTab:CreateText({ Name = "fly status", Text = "off" })

	-- VISUALS (kept inside MOVEMENT so the tab bar stays five wide)
	local visTab = moveTab
	moveTab:CreateSection({ Name = "VISUALS" })
	visTab:CreateToggle({
		Name = "fullbright",
		Description = "max brightness, no shadows, daylight clock. restores the original values on off.",
		Flag = "crim_fullbright",
		Value = CFG.fullbright,
		Callback = function(v)
			CFG.fullbright = v
			if v then applyFullbright() else restoreFullbright() end
		end,
	})
	visTab:CreateToggle({
		Name = "no fog",
		Flag = "crim_nofog",
		Value = CFG.noFog,
		Callback = function(v)
			CFG.noFog = v
			if v then applyNoFog() else restoreNoFog() end
		end,
	})
	visTab:CreateToggle({
		Name = "custom fov",
		Flag = "crim_fovon",
		Value = CFG.fovOn,
		Callback = function(v) CFG.fovOn = v end,
	})
	visTab:CreateSlider({
		Name = "field of view",
		Range = { 70, 120 },
		Increment = 1,
		Value = CFG.fov,
		Suffix = " fov",
		Flag = "crim_fov",
		Callback = function(v) CFG.fov = v end,
	})

	-- STATUS
	local statusTab = w:CreateTab({ Name = "STATUS" })
	statusTab:CreateSection({ Name = "LIVE" })
	ui.status = statusTab:CreateText({ Name = "state", Text = "starting" })
	statusTab:CreateButton({
		Name = "refresh",
		Callback = function()
			if ui.status then pcall(function() ui.status:Set(statusText()) end) end
			notify("status refreshed")
		end,
	})
	statusTab:CreateSection({ Name = "PRESETS" })
	statusTab:CreateButton({
		Name = "MAX MODE  (loot + haul + knockout + escape)",
		Description = "enables loot esp, auto grab/load, auto haul (25 items, 250 m), auto knockout, auto escape, auto doors, 60 ws strength, infinite stamina, noclip, fullbright, no fog and 90 fov.",
		Callback = function() maxMode() end,
	})
	statusTab:CreateText({
		Name = "max mode note",
		Text = "max mode is a stack of the same best-effort features. it does not grant cash or quota, and fly is left off because it fights the teleport haul. press P to turn everything off.",
	})
	statusTab:CreateSection({ Name = "SESSION" })
	statusTab:CreateButton({
		Name = "rejoin server",
		Callback = function() rejoin() end,
	})
	statusTab:CreateButton({
		Name = "panic  (P)",
		Description = "turns every feature off, restores lighting, collision and fov.",
		Callback = function() panic() end,
	})
	statusTab:CreateButton({
		Name = "unload",
		Callback = function() shutdown() end,
	})
	statusTab:CreateText({
		Name = "keys",
		Text = "P = panic   |   the panel replaces itself instead of stacking.",
	})
	ui.logText = statusTab:CreateText({ Name = "log", Text = "-" })
end

--// loop ------------------------------------------------------------------------

local lastSync = 0
local lastSave = 0
local lastHaulSync = 0

local function tick()
	if dead then return end
	movementTick()

	if CFG.lootEsp then
		pcall(renderLoot)
	else
		for _, e in pairs(lootPool) do hideLootEsp(e) end
	end

	if CFG.playerEsp then
		pcall(playerEspTick)
	else
		for _, e in pairs(playerPool) do hideHumanoidEsp(e) end
	end

	if CFG.npcEsp then
		pcall(npcEspTick)
	else
		for _, e in pairs(npcPool) do hideHumanoidEsp(e) end
	end

	pcall(stealth.sneakTick)
	pcall(stealth.sightConeTick)
	pcall(strength.tick)

	if CFG.npcDetails then
		pcall(npcDetailTick)
	elseif npcDetailFrame then
		npcDetailTeardown()
	end

	local t = now()
	if t - lastSync > 0.5 then
		lastSync = t
		local text = statusText()
		if ui.status then pcall(function() ui.status:Set(text) end) end
		if ui.lootInfo then
			local carried = findHeldLoot()
			local near = lootList[1]
			pcall(function()
				ui.lootInfo:Set(string.format(
					"%d loot shown  |  nearest %s  |  holding %s",
					#lootList,
					near and (near.name .. " " .. money(near.value) .. " @ " .. math.floor(near.dist) .. "m") or "-",
					carried and (tostring(carried:GetAttribute("DisplayName") or carried.Name)) or "nothing"
				))
			end)
		end
		if ui.npcInfo then
			local counts = {}
			for _, group in ipairs({ "Npcs", "Guards", "Police" }) do
				local folder = workspace:FindFirstChild(group)
				local alive = 0
				if folder then
					for _, model in ipairs(folder:GetChildren()) do
						local hum = model:FindFirstChildOfClass("Humanoid")
						if hum and hum.Health > 0 then alive = alive + 1 end
					end
				end
				counts[#counts + 1] = string.format("%s %d", group, alive)
			end
			pcall(function() ui.npcInfo:Set(table.concat(counts, "  |  ")) end)
		end
		if ui.speedInfo then
			local hum = charHumanoid()
			local mode = (CFG.speedGuard and not CFG.speedNoCap)
				and ("guard cap " .. math.floor((tonumber(CFG.speedCap) or 60) + 0.5))
				or "guard off"
			pcall(function()
				ui.speedInfo:Set(string.format(
					"slider %d ws  |  %s  |  actual %d ws",
					math.floor((tonumber(CFG.walkSpeed) or 60) + 0.5),
					mode,
					hum and math.floor(hum.WalkSpeed + 0.5) or 0
				))
			end)
		end
		if ui.knockInfo then
			local targets = knockoutTargets(tonumber(CFG.knockoutRadius) or 25)
			local near = targets[1]
			local mode = "off"
			if knockoutBusy then
				mode = "working"
			elseif CFG.autoKnockout then
				mode = "armed"
			end
			pcall(function()
				ui.knockInfo:Set(string.format(
					"%s  |  %d npc in range  |  nearest %s",
					mode,
					#targets,
					near and (near.name .. " @ " .. math.floor(near.dist) .. "m") or "-"
				))
			end)
		end
		if ui.escapeInfo then
			local police, dist = policeNear(tonumber(CFG.autoEscapeRadius) or 60)
			pcall(function()
				ui.escapeInfo:Set(CFG.autoEscape
					and (police and string.format("ARMED - police %.0fm", dist) or "armed - no police in range")
					or "off")
			end)
		end
		if ui.sightInfo then
			local sight, sightModel, sightDist = stealth.currentSight()
			local text
			if not CFG.sightWarn then
				text = "warning off"
			elseif sight <= 0 then
				text = "clear - no npc has noticed you"
			else
				text = string.format(
					"%d%% noticed by %s @ %dm",
					math.floor(sight * 100 + 0.5),
					sightModel and tostring(sightModel:GetAttribute("DisplayName") or sightModel.Name) or "npc",
					math.floor((sightDist or 0) + 0.5)
				)
			end
			if CFG.antiDetect then
				text = text .. "  |  sneak " .. (stealth.serverSneaking() and "ON" or "waiting")
			end
			pcall(function() ui.sightInfo:Set(text) end)
			if CFG.sightWarn and sight >= 0.85 and now() - stealth.lastSightNotice > 8 then
				stealth.lastSightNotice = now()
				notify(string.format(
					"spotted %d%% by %s @ %dm - break line of sight",
					math.floor(sight * 100 + 0.5),
					sightModel and tostring(sightModel:GetAttribute("DisplayName") or sightModel.Name) or "npc",
					math.floor((sightDist or 0) + 0.5)
				))
			end
		end
		if ui.flyInfo then
			pcall(function()
				ui.flyInfo:Set(CFG.fly
					and string.format("on  |  %d ws", math.floor((tonumber(CFG.flySpeed) or 80) + 0.5))
					or "off")
			end)
		end
		if ui.logText then pcall(function() ui.logText:Set(#log > 0 and table.concat(log, "\n") or "-") end) end
	end
	if t - lastSave > 4 then
		lastSave = t
		pcall(saveCfg)
	end
	if not hauling and t - lastHaulSync > 5 then
		lastHaulSync = t
		pcall(refreshHaulInfo)
	end
end

buildUI()

if CFG.npcDetails then
	pcall(npcDetailBuild)
end

if CFG.maxStrength then
	pcall(strength.apply)
end

if ui.window then
	local conn = UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		if UserInputService:GetFocusedTextBox() then return end
		if input.KeyCode == Enum.KeyCode.P then
			panic()
		end
	end)
	ui.keyConn = conn
end

ui.loopConn = RunService.Heartbeat:Connect(function()
	local ok, err = pcall(tick)
	if not ok then
		warn("[CRIMINAL] tick error: " .. tostring(err))
	end
end)

ui.charConn = LP.CharacterAdded:Connect(function()
	stopFly()
	stopSpeed()
	jumpConn = nil
	baseWalk = nil
	baseJump = nil
	baseUseJumpPower = nil
	noclipSaved = {}
	stealth.owned = false
	stealth.auto = false
	stealth.lastNear = 0
	stealth.lastSent = 0
	stealth.lastScan = 0
	task.wait(0.5)
	if CFG.customSpeed then startSpeed() end
	if CFG.customJump then startJump() end
	if CFG.infiniteStamina then staminaTick() end
	if CFG.maxStrength then strength.apply() end
	if CFG.fly then startFly() end
	if not hauling then pcall(refreshHaulInfo) end
end)

ui.removeConn = Players.PlayerRemoving:Connect(function(plr)
	dropHumanoidEsp(playerPool, plr)
end)

task.spawn(function()
	while not dead do
		if CFG.autoRob then
			local fired, skipped = fireMatching(isRobPrompt, 22, "auto rob")
			if fired > 0 and ui.promptInfo then
				pcall(function() ui.promptInfo:Set(string.format("auto rob: %d fired, %d cooling down", fired, skipped)) end)
			end
		end
		if CFG.autoDoors then
			local fired, skipped = fireNearbyMatching(
				isOpenPrompt,
				tonumber(CFG.autoDoorsRadius) or 60,
				8,
				"auto doors"
			)
			if fired > 0 and ui.promptInfo then
				pcall(function() ui.promptInfo:Set(string.format("auto doors: %d fired, %d cooling down", fired, skipped)) end)
			end
		end
		task.wait(3)
	end
end)

task.spawn(function()
	while not dead do
		if CFG.autoGrab then
			local ok, err = pcall(autoGrabStep)
			if not ok then warn("[CRIMINAL] auto grab error: " .. tostring(err)) end
		end
		task.wait(1.2)
	end
end)

task.spawn(function()
	while not dead do
		if CFG.autoHaul and not hauling and not grabbing and not knockoutBusy and not escaping then
			local delay = math.clamp(tonumber(CFG.autoHaulDelay) or 30, 10, 300)
			if now() - lastAutoHaulAt >= delay then
				local radius = math.clamp(tonumber(CFG.haulRadius) or 250, 25, 2000)
				if #haulTargets(radius) > 0 then
					lastAutoHaulAt = now()
					local limit = tonumber(CFG.haulLimit) or 0
					local ok, err = pcall(haulAll, limit > 0 and limit or nil)
					if not ok then notify("auto haul error: " .. tostring(err)) end
				else
					lastAutoHaulAt = now()
				end
			end
		end
		task.wait(1)
	end
end)

task.spawn(function()
	while not dead do
		if CFG.autoKnockout then
			local ok, err = pcall(autoKnockoutStep)
			if not ok then warn("[CRIMINAL] auto knockout error: " .. tostring(err)) end
		end
		task.wait(0.9)
	end
end)

task.spawn(function()
	while not dead do
		if CFG.autoEscape and not escaping then
			if hauling or grabbing then
				haulStop = true
			else
				local police, dist = policeNear(tonumber(CFG.autoEscapeRadius) or 60)
				if police then
					escaping = true
					knockoutStop = true
					local waited = 0
					while knockoutBusy and waited < 1.5 and not dead do
						task.wait(0.1)
						waited = waited + 0.1
					end
					notify(string.format("police %.0fm - escaping to hideout", dist or 0))
					pcall(escapeToHideout)
					task.wait(2)
					escaping = false
				end
			end
		end
		task.wait(0.7)
	end
end)

pushLog("panel loaded")
pcall(saveCfg)

_G.CriminalPanel = {
	cfg = CFG,
	window = ui.window,
	loot = lootPool,
	players = playerPool,
	npcs = npcPool,
	lootList = function() return lootList end,
	status = statusText,
	prompts = allPrompts,
	grab = faceAndGrab,
	deliver = deliverHeld,
	drop = dropHeld,
	haul = haulAll,
	haulCount = function() return #haulTargets(tonumber(CFG.haulRadius) or 250) end,
	knockout = knockoutNpc,
	knockoutNearest = knockoutNearest,
	knockoutCount = function() return #knockoutTargets(tonumber(CFG.knockoutRadius) or 25) end,
	escape = escapeToHideout,
	sell = sellNow,
	antiDetect = function(on)
		CFG.antiDetect = on and true or false
		if not CFG.antiDetect and stealth.auto then stealth.sendSneak(false) end
		return CFG.antiDetect
	end,
	sneak = stealth.sendSneak,
	sneakNow = stealth.toggleSneakNow,
	sight = stealth.currentSight,
	sightConeCount = function()
		local n = 0
		for _, e in pairs(stealth.cones) do
			if e.left and e.left.Visible then n = n + 1 end
		end
		return n
	end,
	maxMode = maxMode,
	maxStrength = strength.set,
	lifter = function() return tonumber(LP:GetAttribute("Shop_Lifter")) or 0 end,
	flyOn = startFly,
	flyOff = stopFly,
	stop = shutdown,
	panic = panic,
	teleport = stepTeleport,
	stamina = staminaTick,
	speedTarget = speedTarget,
	npcDetails = npcDetailTick,
	npcDump = npcDetailDump,
}

print("[CRIMINAL] panel loaded - loot esp, haul to truck, auto knockout, auto escape, anti-detect sneak/sight, fly, npc details, prompt sniper, stamina, speed guard, movement")
end

--// dispatch -------------------------------------------------------------------

local place = game.PlaceId
local wired = Hub.GAMES[place]
if not wired then
	local universe = tonumber(game.GameId)
	local chain = universe and Hub.UNIVERSE[universe] or nil
	if chain then
		wired = { place = place, label = "UNIVERSE " .. tostring(universe), suites = chain }
	end
end

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