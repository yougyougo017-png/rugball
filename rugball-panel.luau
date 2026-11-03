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

	This script also unbinds AutoTackle / AutoBlock / QBAim and deletes their
	huds and esp folders on load, so the old scripts can stay installed but idle.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

--// config --------------------------------------------------------------------

local CFG = {
	-- aim / throw
	aim         = true,
	autoThrow   = false,
	teamOnly    = true,
	maxDist     = 195,    -- ball range is 226.875
	fov         = 42,     -- degrees off the crosshair
	hoverPick   = true,
	hoverRelease = 1.2,
	passType    = "Bullet",
	chargePad   = 0.09,

	-- tackle
	tackle      = true,
	pursue      = false,
	tackleRange = 7.5,
	diveRange   = 12.0,
	tackleHold  = 0.55,
	tackleCd    = 1.15,

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

	-- steering
	steerGain   = 1.0,
	steerHz     = 12.5,
	steerDead   = 0.12,
}

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

local PlayContext = LocalPlayer:WaitForChild("PlayContext", 10)
local Tackle = PlayContext and PlayContext:WaitForChild("Tackle", 10)
local Dive = PlayContext and PlayContext:WaitForChild("Dive", 10)
local Steer = PlayContext and PlayContext:WaitForChild("Steer", 10)
if not (PlayContext and Tackle and Dive and Steer) then
	warn("[Slim] PlayContext not found - are you in a match?")
	return
end

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
local hoverLostAt = 0
local currentEntry = nil
local trackers = {}         -- [Model] = {pos, t, vel}

local pressing = false
local pressToken = 0
local nextTackle = 0
local nextDive = 0
local nextBlock = 0

local steerTarget = Vector2.zero
local steerVec = Vector2.zero
local lastSteer = 0

local stickyThreat = nil
local mode = "auto"
local tackleStatus = nil

local stats = { shots = 0, lastCharge = 0 }

local espFolder = Instance.new("Folder")
espFolder.Name = "SlimEsp"
espFolder.Parent = Workspace

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

local function passType()
	if not BallThrowConfig then return CFG.passType end
	return CFG.passType
end

local function flightTime(distance)
	local cfg = BallThrowConfig
	if not cfg then return 0.75 end
	local p = cfg.PassTypes[passType()] or cfg.PassTypes.Lob
	return math.clamp(p.BaseFlightTime + distance * p.DistanceFlightTime, p.BaseFlightTime, cfg.MaxFlightTime)
end

local function predict(origin, targetPos, vel)
	-- doThrow waits windup + release before firing, so lead by that as well
	local lead = BallThrowConfig and (BallThrowConfig.WindupTime + BallThrowConfig.ReleaseDelay) or 0.3
	local point = targetPos
	for _ = 1, 3 do
		local t = flightTime((point - origin).Magnitude) + lead
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

-- no fov / range gate: the manual picker has to reach deep men
local function entryFor(rig, origin, now, cam, allRigs)
	if not rig or not rig.PrimaryPart or not origin then return nil end
	local pos = chestOf(rig)
	local vel = trackVelocity(rig, pos, now)
	local point = predict(origin, pos, vel)
	local offset = point - cam.CFrame.Position
	local angle = math.deg(math.acos(math.clamp(cam.CFrame.LookVector:Dot(offset.Unit), -1, 1)))
	local dist = (point - origin).Magnitude
	local gap = allRigs and defenderGap(rig, pos, allRigs) or math.huge
	-- shallow men are penalised: a 6-stud check-down is not a throw
	local shallow = math.max(0, 55 - dist)
	return {
		rig = rig,
		point = point,
		angle = angle,
		dist = dist,
		vel = vel,
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

local throwing = false
local lastThrow = 0

local function doThrow(entry)
	if not (BallThrowConfig and RugballThrow) then return end
	local origin = throwOrigin()
	if not origin or not entry then return end
	if not canThrow() and not hasBall() then
		mode = "need the ball"
		return
	end

	local cfg = BallThrowConfig
	local dist = (entry.point - origin).Magnitude
	local charge = math.clamp((dist - cfg.InitialChargeDistance) / cfg.ChargeDistancePerSecond, 0.04, 1.6) + CFG.chargePad + (math.random() - 0.5) * 0.04
	local pass = passType()

	task.wait(cfg.WindupTime)
	task.wait(cfg.ReleaseDelay)
	RugballThrow:FireServer(entry.point, charge, pass)

	stats.shots = stats.shots + 1
	stats.lastCharge = charge
	mode = string.format("threw %.0fst c=%.2f", dist, charge)
end

local function requestThrow()
	if throwing then return false end
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
	task.spawn(function()
		local ok, err = pcall(doThrow, snapshot)
		if not ok then mode = "err: " .. tostring(err):sub(1, 40) end
		throwing = false
	end)
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

	return { hl = hl, box = box, beam = beam, tag = tag, text = text, rig = nil, lastText = 0 }
end

local aimMark = newMark("Aim", COLORS.aim)
local carrierMark = newMark("Carrier", COLORS.carrier)
local threatMark = newMark("Threat", COLORS.threat)

local function markOff(m)
	if not m or not m.rig then return end
	m.rig = nil
	m.hl.Adornee = nil
	m.box.Adornee = nil
	m.tag.Adornee = nil
	m.tag.Enabled = false
	m.beam.Transparency = 1
end

local function markTo(m, rig, text, origin, now)
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
		if token == pressToken then
			action:Fire(false)
			pressing = false
		end
	end)
	return true
end

local function releaseAction()
	pressToken = pressToken + 1
	if pressing then
		pressing = false
		pcall(function() Tackle:Fire(false) end)
		pcall(function() Dive:Fire(false) end)
	end
end

-- one writer for Steer, so pursuit and block drive can never fight
local function flatUnit(v)
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude > 1e-3 then return f.Unit end
	return nil
end

local function driveTo(worldDir)
	if worldDir then
		local cam = Workspace.CurrentCamera
		if cam then
			local r = flatUnit(cam.CFrame.RightVector)
			-- looking straight down: the up vector is what points "forward" on screen
			local l = flatUnit(cam.CFrame.LookVector) or flatUnit(cam.CFrame.UpVector)
			if r and l then
				local vx = r:Dot(worldDir)
				local vy = l:Dot(worldDir)
				if math.abs(vx) < CFG.steerDead then vx = 0 end
				if math.abs(vy) < CFG.steerDead then vy = 0 end
				steerTarget = Vector2.new(vx * CFG.steerGain, vy * CFG.steerGain)
				return
			end
		end
	end
	steerTarget = Vector2.zero
end

local function pumpSteer(now)
	if now - lastSteer < 1 / CFG.steerHz then return end
	lastSteer = now
	if (steerTarget - steerVec).Magnitude > 0.05 then
		steerVec = steerTarget
		Steer:Fire(steerVec)
	end
end

--// ui ------------------------------------------------------------------------

local Rayfield
local window
local statusBox
local tackleToggle
local blockToggle
local throwKey

local shutOnce = false
local shutdown
shutdown = function()
	if shutOnce then return end
	shutOnce = true
	pcall(function() RunService:UnbindFromRenderStep("SlimPanel") end)
	releaseAction()
	pcall(function() Steer:Fire(Vector2.zero) end)
	_G.QBAim = nil
	_G.Slim = nil
	markOff(aimMark)
	markOff(carrierMark)
	markOff(threatMark)
	for _, v in ipairs(espFolder:GetChildren()) do
		pcall(function() v:Destroy() end)
	end
	pcall(function() espFolder:Destroy() end)
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
local function buildUI()
	local ok, res = pcall(function()
		return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
	end)
	if not ok or type(res) ~= "table" then
		warn("[Slim] Rayfield failed to load: " .. tostring(res))
		return false
	end
	Rayfield = res

	window = Rayfield:CreateWindow({
		name = "RUGBALL",
		subtitle = "slim suite",
		sidebarLayout = true,
		configuration = {
			autoSave = true,
			autoLoad = true,
			fileName = "RugballSlim",
		},
	})

	local aimTab = window:CreateTab({ name = "Aim" })
	local tackleTab = window:CreateTab({ name = "Tackle" })
	local blockTab = window:CreateTab({ name = "Block" })
	local lookTab = window:CreateTab({ name = "Look" })
	local liveTab = window:CreateTab({ name = "Live" })

	-- aim -------------------------------------------------------------------------

	aimTab:CreateDivider({ text = "targeting" })

	aimTab:CreateToggle({
		name = "aimbot",
		description = "pick the best man and drop the ball on him",
		flag = "aim",
		value = CFG.aim,
		callback = function(v) CFG.aim = v end,
	})

	aimTab:CreateToggle({
		name = "auto throw",
		description = "throw the moment you can",
		flag = "autoThrow",
		value = CFG.autoThrow,
		callback = function(v) CFG.autoThrow = v end,
	})

	aimTab:CreateToggle({
		name = "team only",
		flag = "teamOnly",
		value = CFG.teamOnly,
		callback = function(v) CFG.teamOnly = v end,
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

	aimTab:CreateDivider({ text = "throw" })

	aimTab:CreateButton({
		name = "throw to picked man",
		description = "or press E",
		callback = function()
			if not requestThrow() then
				window:Notify({ title = "RUGBALL", content = mode })
			end
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

	-- tackle ----------------------------------------------------------------------

	tackleTab:CreateDivider({ text = "tackle" })

	tackleToggle = tackleTab:CreateToggle({
		name = "auto tackle",
		description = "press the game's own tackle when the carrier is in reach",
		flag = "tackle",
		value = CFG.tackle,
		callback = function(v) CFG.tackle = v end,
	})

	tackleTab:CreateToggle({
		name = "pursue",
		description = "steer at the carrier while closing",
		flag = "pursue",
		value = CFG.pursue,
		callback = function(v) CFG.pursue = v end,
	})

	tackleTab:CreateSlider({
		name = "tackle range",
		range = { 4, 14 },
		increment = 0.5,
		value = CFG.tackleRange,
		suffix = " st",
		flag = "tackleRange",
		callback = function(v) CFG.tackleRange = v end,
	})

	tackleTab:CreateSlider({
		name = "dive range",
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

	-- block -----------------------------------------------------------------------

	blockTab:CreateDivider({ text = "block" })

	blockToggle = blockTab:CreateToggle({
		name = "auto block",
		description = "hold tackle on a rusher and drive into him",
		flag = "block",
		value = CFG.block,
		callback = function(v) CFG.block = v end,
	})

	blockTab:CreateToggle({
		name = "drive",
		flag = "drive",
		value = CFG.drive,
		callback = function(v) CFG.drive = v end,
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

	-- look ------------------------------------------------------------------------

	lookTab:CreateDivider({ text = "esp" })

	lookTab:CreateToggle({
		name = "aim target",
		flag = "espAim",
		value = CFG.espAim,
		callback = function(v) CFG.espAim = v end,
	})

	lookTab:CreateToggle({
		name = "carrier",
		flag = "espCarrier",
		value = CFG.espCarrier,
		callback = function(v) CFG.espCarrier = v end,
	})

	lookTab:CreateToggle({
		name = "block threat",
		flag = "espThreat",
		value = CFG.espThreat,
		callback = function(v) CFG.espThreat = v end,
	})

	lookTab:CreateToggle({
		name = "tracers",
		flag = "tracers",
		value = CFG.tracers,
		callback = function(v) CFG.tracers = v end,
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
		end,
	})

	lookTab:CreateDivider({ text = "panel" })

	lookTab:CreateButton({
		name = "unload",
		description = "tear the panel down and leave the game alone",
		callback = function()
			shutdown()
		end,
	})

	-- live ------------------------------------------------------------------------

	liveTab:CreateDivider({ text = "state" })
	statusBox = liveTab:CreateConsole({ name = "", height = 300, follow = false })

end

local uiOk, uiErr = pcall(buildUI)
if not uiOk then
	warn("[Slim] panel ui failed: " .. tostring(uiErr) .. " - modules running headless")
elseif not window then
	warn("[Slim] no window - modules running headless, _G.QBAim still exposed")
end

--// modules -------------------------------------------------------------------

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

	if dist <= CFG.tackleRange and now >= nextTackle then
		if press(Tackle, CFG.tackleHold + math.random() * 0.08) then
			nextTackle = now + CFG.tackleCd + math.random() * 0.12
		end
		return nil, string.format("tackle %.1f", dist)
	elseif dist <= CFG.diveRange and dist > CFG.tackleRange and now >= nextDive then
		if press(Dive, 0.12) then
			nextDive = now + CFG.tackleCd * 1.5 + math.random() * 0.12
		end
		return nil, string.format("dive %.1f", dist)
	end

	if CFG.pursue and dist > CFG.tackleRange * 0.75 then
		local flat = Vector3.new(delta.X, 0, delta.Z)
		if flat.Magnitude > 0.5 then
			return flat.Unit, string.format("chase %.1f", dist)
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
	if CFG.drive then
		local delta = threat.PrimaryPart.Position - myRoot.Position
		local flat = Vector3.new(delta.X, 0, delta.Z)
		if flat.Magnitude > 0.4 then dir = flat.Unit end
	end

	local state
	if dist <= CFG.blockEngage then
		if now >= nextBlock then
			local hold = CFG.blockHold + math.random() * 0.08
			if press(Tackle, hold) then
				nextBlock = now + hold + CFG.blockCd + math.random() * 0.12
			end
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
local lastPrune = 0

local function statusText(entry, carrierRig, threatState)
	local lines = {}
	lines[#lines + 1] = string.format("mode     %s", mode)
	if entry then
		lines[#lines + 1] = string.format("target   %s  %.0f st  %.0f deg", label(entry.rig), entry.dist, entry.angle)
	else
		lines[#lines + 1] = "target   -"
	end
	lines[#lines + 1] = string.format("carrier  %s", carrierRig and (label(carrierRig) .. "  " .. tostring(teamOf(carrierRig))) or "-")
	if tackleStatus then lines[#lines + 1] = string.format("tackle   %s", tackleStatus) end
	if threatState then lines[#lines + 1] = string.format("block    %s", threatState) end
	lines[#lines + 1] = string.format("ball     %s", hasBall() and "in hand" or (canThrow() and "ready" or "-"))
	lines[#lines + 1] = string.format("throws   %d   last c=%.2f", stats.shots, stats.lastCharge)
	lines[#lines + 1] = string.format("pick     %s", lockManual and "mouse" or "auto")
	return table.concat(lines, "\n")
end

RunService:BindToRenderStep("SlimPanel", Enum.RenderPriority.Camera.Value + 3, function()
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
	local now = os.clock()
	local origin = throwOrigin()
	local allRigs = rigs()

	if now - lastPrune > 5 then
		lastPrune = now
		for rig in pairs(trackers) do
			if not rig.Parent then trackers[rig] = nil end
		end
	end

	-- point at a man and he is the target; the auto picker takes over 1.2s later
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

	-- esp on the aim target
	if CFG.espAim and entry then
		markTo(aimMark, entry.rig, string.format("%s  %.0f st", label(entry.rig), entry.dist), myRoot.Position, now)
	else
		markOff(aimMark)
	end

	-- auto throw
	if CFG.autoThrow and entry and not throwing and (now - lastThrow) > 1.25 then
		if hasBall() or canThrow() then
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

	-- tackle first: an enemy carrier in reach owns the tackle button
	local tackleDir, tackleState = tackleTick(now, mine, myRoot, carrierRig)
	local blockDir, blockState
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

	driveTo(tackleDir or blockDir)
	pumpSteer(now)

	tackleStatus = tackleState

	if now - lastStatus > 0.1 then
		lastStatus = now
		if statusBox then statusBox:Set(statusText(entry, carrierRig, blockState)) end
	end
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
			hoverLostAt = 0
			return true
		end
		return false
	end,
	clear = function()
		locked = nil
		lockManual = false
		hoverLostAt = 0
		mode = "auto"
	end,
	throw = function() return requestThrow() end,
	cfg = CFG,
	stats = stats,
	panel = window,
	lib = Rayfield,
	box = statusBox,
	getMode = function() return mode, currentEntry end,
	stop = function() shutdown() end,
}
_G.Slim = _G.QBAim

if STATE and STATE.onCleanup then
	STATE.onCleanup(shutdown)
end

if window then
	print("[Slim] panel loaded - Rayfield Gen2 | aim, tackle, block in one window")
else
	print("[Slim] modules loaded headless - no panel window")
end