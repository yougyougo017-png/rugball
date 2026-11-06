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
-- tick and subtracts it from a flat 24-25 st/s cruise. require() returns the
-- same module table the sim is already reading through, so one patched penaly
-- function is the clean channel: no force fights, no balance loss, no
-- compounding. the patch is live per tick, so the slider moves the cruise in
-- real time, the original function is kept and restored on unload, and with
-- speed off the patch just calls straight through.
local speedTypes
local origPenalty
do
	local ok, sim = pcall(require, ReplicatedFirst:WaitForChild("RigSim"))
	if ok and type(sim) == "table" and type(sim.Types) == "table"
		and type(sim.Types.speedPenalty) == "function" then
		speedTypes = sim.Types
		origPenalty = sim.Types.speedPenalty
		speedTypes.speedPenalty = function(rig)
			-- mult maps 1.0 -> no bias, 1.2 -> about +5 st/s, 1.5 -> +12.5.
			-- rush adds its own +5 even with speed off: pursuit gets real pace.
			local bias = 0
			if CFG.speed then
				bias = math.max(0, (tonumber(CFG.speedMult) or 1) - 1) * 25
			end
			if rushOn and CFG.rushSurge then
				bias = bias + 5
			end
			if bias <= 0.001 then
				return origPenalty(rig)
			end
			return origPenalty(rig) - bias
		end
	end
end

local function unpatchSpeed()
	if speedTypes and origPenalty then
		pcall(function() speedTypes.speedPenalty = origPenalty end)
		origPenalty = nil
		speedTypes = nil
	end
end

--// ui ------------------------------------------------------------------------

local Rayfield
local window
local statusBox
local tackleToggle
local blockToggle
local throwKey
local tagTarget
local modeTag
local aimCard
local chargeBar
local ballBar
local statTarget
local statCarrier
local statShots
local statPicks
local statTackles
local statAvg
local statFps
local statErr
local statUp
local leadSlider
local passDropdown
local interceptToggle
local pathToggle
local guardToggle
local autopilotToggle
local aimToggle
local autoThrowToggle
local antiFallToggle
local radarFrame
local radarCanvas
local radarDots = {}
local radarRings = {}
local lastRadar = 0
local lastPickAt = 0
local leadConn
local antiFallConn

local shutOnce = false
local shutdown
shutdown = function()
	if shutOnce then return end
	shutOnce = true
	pcall(saveCfg)
	unpatchSpeed()
	pcall(function() RunService:UnbindFromRenderStep("SlimPanel") end)
	if leadConn then pcall(function() leadConn:Disconnect() end) end
	if antiFallConn then pcall(function() antiFallConn:Disconnect() end) end
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
		tagTarget = window:CreateTag({ text = "NO TGT", color = Color3.fromRGB(70, 76, 90), order = 1 })
		modeTag = window:CreateTag({ text = "IDLE", color = Color3.fromRGB(44, 50, 62), order = 2 })
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
		aimCard = aimTab:CreateText({
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
			pcall(function() aimToggle:Set(true, true) end)
			pcall(function() autoThrowToggle:Set(true, true) end)
			pcall(function() tackleToggle:Set(true, true) end)
			pcall(function() blockToggle:Set(true, true) end)
			pcall(function() interceptToggle:Set(true, true) end)
			pcall(function() pathToggle:Set(true, true) end)
			pcall(function() guardToggle:Set(true, true) end)
			pcall(function() antiFallToggle:Set(true, true) end)
		end
		mode = v and "autopilot" or mode
	end

	pcall(function()
		autopilotToggle = aimTab:CreateToggle({
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
			if autopilotToggle then
				pcall(function() autopilotToggle:Set(CFG.autopilot, true) end)
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
	aimToggle = aimRow:CreateToggle({
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
	autoThrowToggle = aimRow:CreateToggle({
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

	leadSlider = aimTab:CreateSlider({
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
		passDropdown = aimTab:CreateDropdown({
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
		if leadSlider then pcall(function() leadSlider:Set(CFG.lead, true) end) end
		if passDropdown then pcall(function() passDropdown:Set(CFG.passType, true) end) end
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
	tackleToggle = tackleRow:CreateToggle({
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

	antiFallToggle = tackleRow:CreateToggle({
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
		description = "raises the cruise the sim drives toward",
		flag = "speed",
		value = CFG.speed,
		callback = function(v) CFG.speed = v end,
	})
	moveRow:CreateSlider({
		name = "speed mult",
		description = "1.15 = about +4 st/s | 1.5+ gets loud",
		range = { 1, 1.6 },
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

	section(tackleTab, "DEFENSE ASSIST")

	local assistRow = groupOf(tackleTab)
	pcall(function()
		interceptToggle = assistRow:CreateToggle({
			name = "ball intercept",
			flag = "intercept",
			value = CFG.intercept,
			callback = function(v) CFG.intercept = v end,
		})
	end)
	pcall(function()
		pathToggle = assistRow:CreateToggle({
			name = "pursuit pathing",
			flag = "pathing",
			value = CFG.pathing,
			callback = function(v) CFG.pathing = v end,
		})
	end)
	pcall(function()
		guardToggle = assistRow:CreateToggle({
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
			tackleToggle:Set(CFG.tackle, true)
		end,
	})

	-- block -------------------------------------------------------------------

	section(blockTab, "BLOCK")

	local blockRow = groupOf(blockTab)
	blockToggle = blockRow:CreateToggle({
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
			blockToggle:Set(CFG.block, true)
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
			if tagTarget then tagTarget:SetColor(color) end
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
		statTarget = statRow:CreateStat({
			name = "target",
			suffix = "st",
			value = 0,
			changeMode = "absolute",
		})
		statCarrier = statRow:CreateStat({
			name = "carrier",
			suffix = "st",
			value = 0,
			changeMode = "absolute",
		})
		statShots = statRow:CreateStat({
			name = "throws",
			value = 0,
			changeMode = "absolute",
		})
	end)

	-- second row: what the session has actually done
	local statRow2 = groupOf(liveTab)
	pcall(function()
		statPicks = statRow2:CreateStat({
			name = "picks",
			value = stats.picks,
			changeMode = "absolute",
		})
		statTackles = statRow2:CreateStat({
			name = "tackles",
			value = stats.tackles,
			changeMode = "absolute",
		})
		statAvg = statRow2:CreateStat({
			name = "avg",
			suffix = "st",
			value = 0,
			changeMode = "absolute",
		})
	end)

	-- reach: how much of the 226.9 st throw ceiling the current pick uses
	pcall(function()
		chargeBar = liveTab:CreateProgress({
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
		ballBar = liveTab:CreateProgress({
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

		radarFrame = Instance.new("Frame")
		radarFrame.Name = "Radar"
		radarFrame.BackgroundColor3 = Color3.fromRGB(11, 15, 20)
		radarFrame.BorderSizePixel = 0
		radarFrame.Size = UDim2.new(1, 0, 0, 200)
		radarFrame.ClipsDescendants = true
		radarFrame.Parent = page
		pcall(function() radarFrame.LayoutOrder = #liveTab.elements * 10 + 5 end)

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = radarFrame

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(52, 60, 76)
		stroke.Transparency = 0.25
		stroke.Parent = radarFrame

		radarCanvas = Instance.new("Frame")
		radarCanvas.Name = "Field"
		radarCanvas.AnchorPoint = Vector2.new(0.5, 0.5)
		radarCanvas.Position = UDim2.fromScale(0.5, 0.5)
		radarCanvas.Size = UDim2.fromOffset(184, 184)
		radarCanvas.BackgroundTransparency = 1
		radarCanvas.Parent = radarFrame

		for _, frac in ipairs({ 0.5, 1 }) do
			local ring = Instance.new("Frame")
			ring.Name = "Ring"
			ring.AnchorPoint = Vector2.new(0.5, 0.5)
			ring.Position = UDim2.fromScale(0.5, 0.5)
			ring.Size = UDim2.fromScale(frac, frac)
			ring.BackgroundTransparency = 1
			ring.Parent = radarCanvas

			local rc = Instance.new("UICorner")
			rc.CornerRadius = UDim.new(1, 0)
			rc.Parent = ring

			local rs = Instance.new("UIStroke")
			rs.Color = Color3.fromRGB(48, 58, 74)
			rs.Thickness = 1
			rs.Transparency = frac == 1 and 0.35 or 0.65
			rs.Parent = ring
			radarRings[#radarRings + 1] = ring
		end

		for i = 1, 32 do
			local dot = Instance.new("Frame")
			dot.Name = "Dot"
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Size = UDim2.fromOffset(6, 6)
			dot.BorderSizePixel = 0
			dot.Visible = false
			dot.ZIndex = 4
			dot.Parent = radarCanvas

			local dc = Instance.new("UICorner")
			dc.CornerRadius = UDim.new(1, 0)
			dc.Parent = dot

			local ds = Instance.new("UIStroke")
			ds.Color = Color3.fromRGB(6, 9, 12)
			ds.Thickness = 1
			ds.Transparency = 0.25
			ds.Parent = dot

			radarDots[i] = dot
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
		caption.Parent = radarFrame
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
		statFps = engineRow:CreateStat({
			name = "fps",
			value = 0,
			changeMode = "absolute",
		})
		statErr = engineRow:CreateStat({
			name = "frame errors",
			value = 0,
			changeMode = "absolute",
		})
	end)
	pcall(function()
		statUp = engineRow:CreateStat({
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
	statusBox = liveTab:CreateConsole({ name = "", height = 210, follow = false })

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
	if not (radarFrame and radarCanvas) then return end
	if now - lastRadar < 0.1 then return end
	lastRadar = now

	local cam = Workspace.CurrentCamera
	local look = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
	local fwd = Vector3.new(look.X, 0, look.Z)
	if fwd.Magnitude < 0.01 then fwd = Vector3.new(0, 0, -1) end
	fwd = fwd.Unit
	local right = Vector3.new(-fwd.Z, 0, fwd.X)

	local size = radarCanvas.AbsoluteSize.X
	if size <= 1 then size = 184 end
	local radius = size * 0.5 - 4
	local range = math.max(10, CFG.radarRange)
	local scale = radius / range

	local myT = myTeam()
	local n = 0

	local function place(pos, color, px)
		n = n + 1
		local dot = radarDots[n]
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

	for i = n + 1, #radarDots do
		radarDots[i].Visible = false
	end
end

-- [ and ] nudge lead five studs mid-play without opening the panel
leadConn = UserInputService.InputBegan:Connect(function(input, typing)
	if typing then return end
	if UserInputService:GetFocusedTextBox() then return end
	local k = input.KeyCode
	if k ~= Enum.KeyCode.LeftBracket and k ~= Enum.KeyCode.RightBracket then return end
	local step = (k == Enum.KeyCode.RightBracket) and 5 or -5
	CFG.lead = math.clamp(math.floor((CFG.lead or 0) + step + 0.5), 0, 100)
	if leadSlider then
		pcall(function() leadSlider:Set(CFG.lead, true) end)
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
		if now - lastPickAt > 0.35 then
			stats.picks = stats.picks + 1
			lastPickAt = now
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
		if statusBox then statusBox:Set(statusText(entry, carrierRig, blockState)) end
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
		if statFps then
			local fps = framesSince / math.max(0.05, now - lastFpsAt)
			pcall(function() statFps:Set(math.floor(fps + 0.5)) end)
		end
		if statErr then pcall(function() statErr:Set(frameErrors) end) end
		if statUp then pcall(function() statUp:Set(math.floor(now - bootAt)) end) end
		lastFpsAt = now
		framesSince = 0
		local tdist = entry and entry.dist or 0
		local cdist = 0
		if carrierRig and carrierRig.PrimaryPart then
			cdist = (carrierRig.PrimaryPart.Position - myRoot.Position).Magnitude
		end
		if statTarget then statTarget:Set(math.floor(tdist + 0.5)) end
		if statCarrier then statCarrier:Set(math.floor(cdist + 0.5)) end
		if statShots then statShots:Set(stats.shots) end
		if statPicks then statPicks:Set(stats.picks) end
		if statTackles then statTackles:Set(stats.tackles) end
		if CFG.statCard then updateStatCard() end
		if statAvg then
			local avg = stats.shots > 0 and (stats.distSum / stats.shots) or 0
			pcall(function() statAvg:Set(math.floor(avg + 0.5)) end)
		end
		if tagTarget then
			if entry then
				if lockPinned then
					tagTarget:SetText("LOCK " .. string.sub(label(entry.rig), 1, 9))
					tagTarget:SetColor(Color3.fromRGB(178, 255, 64))
				else
					tagTarget:SetText(string.format("TGT %.0f st", tdist or 0))
					tagTarget:SetColor(COLORS.aim)
				end
			else
				tagTarget:SetText("NO TGT")
				tagTarget:SetColor(Color3.fromRGB(70, 76, 90))
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
		if modeTag then
			local shown = string.upper(string.sub(mode, 1, 10))
			pcall(function() modeTag:SetText(shown) end)
		end

		-- the pick card in the aim tab
		if aimCard then
			if entry then
				local extra = ""
				if (CFG.lead or 0) > 0 then extra = string.format("  |  lead %d", CFG.lead) end
				pcall(function()
					aimCard:SetTitle(string.format("picked man  |  %s", label(entry.rig)))
					aimCard:Set(string.format(
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
					aimCard:SetTitle("picked man  |  nobody")
					aimCard:Set(CFG.aim and "auto scanning" or "aim off")
				end)
			end
		end

		-- two little bars that make the numbers mean something
		if chargeBar then
			pcall(function() chargeBar:Set(math.min(tdist, 227)) end)
		end
		if ballBar then
			local state = 0
			if hasBall() then
				state = 2
			elseif ballPart() then
				state = 1
			end
			pcall(function() ballBar:Set(state) end)
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
antiFallConn = RunService.Heartbeat:Connect(function()
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
	box = statusBox,
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