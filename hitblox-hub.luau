--[[
    HitBlox Hub
    Rayfield Gen2 menu for HITBLOX ([UPD 2] HITBLOX / HitBlox Multiplayer).

    Everything here drives the game's own client-side modules instead of firing
    invented remotes:

        Agent:fireGun / Combat.agentShoot   -> shooting (client-side raycast)
        NPC.canSeeAgent                     -> guard vision
        Agent.hurt                          -> incoming damage
        Agent.wantedSpeed                    -> movement speed
        Agent:dumpBody                      -> body hiding (same result, no walk)
        Mission:complete / Mission:finish   -> objectives
        Boot.quick / Config.Acts            -> campaign and side-quest helper
        SaveResult                          -> contract payout (client-trusted fields)

    Re-running tears the previous copy down through STATE.onCleanup, so hooks
    and Drawing objects do not stack.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Hitblox = ReplicatedStorage:FindFirstChild("Hitblox")
if not Hitblox then
    return warn("[HitBlox] Join HITBLOX before running this script.")
end

local function requireModule(name)
    local module = Hitblox:FindFirstChild(name)
    if not module then
        warn(("[HitBlox] missing module: %s"):format(name))
        return nil
    end

    local ok, result = pcall(require, module)
    if not ok then
        warn(("[HitBlox] %s failed to load: %s"):format(name, tostring(result)))
        return nil
    end

    return result
end

local Game = requireModule("Game")
local Config = requireModule("Config")
local Agent = requireModule("Agent")
local NPC = requireModule("NPC")
local Cam = requireModule("Cam")
local World = requireModule("World")
local Audio = requireModule("Audio")

if not (Game and Config and Agent and NPC) then
    return warn("[HitBlox] core modules unavailable, aborting.")
end

-- Re-running tears the previous copy down before new hooks go in, so two
-- panels and two hook sets never stack. getgenv().HitBloxHub is set by the
-- previous copy, whether it came from the standalone loader or the mega hub.
local previousHub = getgenv and getgenv().HitBloxHub
if type(previousHub) == "table" and type(previousHub.unload) == "function" then
    pcall(previousHub.unload)
end

-- Rayfield Gen2 ---------------------------------------------------------------

local loaded, Rayfield = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)

if not loaded or not Rayfield then
    return warn("[HitBlox] Rayfield failed to load: " .. tostring(Rayfield))
end

-- State -----------------------------------------------------------------------

-- os.time() lets the cooldown survive a hub reload in the same process. The
-- server's cooldown is wall-clock, so this is closer than os.clock().
local savedPayoutNextAt = (getgenv and getgenv().HitBloxPayoutNextAt) or 0

local state = {
    -- combat
    aimbot = false,
    autoFire = true,
    aimHeld = false,
    fov = 140,
    maxDistance = 350,
    hitPart = "Head",
    preferTarget = true,
    targetsOnly = false,
    avoidCivilians = true,
    avoidPolice = true,
    requireLos = true,
    noSpread = false,
    noRecoil = false,
    infAmmo = false,
    instantReload = false,

    -- visuals
    esp = false,
    espAll = true,
    espRange = 300,
    espChams = true,
    espNames = true,
    espRole = true,
    espDistance = true,
    espHealth = false,
    colorTarget = Color3.fromRGB(255, 64, 64),
    colorHostile = Color3.fromRGB(255, 160, 60),
    colorCivilian = Color3.fromRGB(120, 220, 140),
    colorCrew = Color3.fromRGB(120, 180, 255),

    -- stealth / defence
    undetectable = false,
    godmode = false,
    autoHideBodies = true,
    hideRange = 30,

    -- movement
    speedOn = false,
    speed = 16,
    jumpOn = false,
    jump = 50,
    noclip = false,

    -- contract payout
    autoPayout = false,
    payoutBusy = false,
    payoutLastAt = 0,
    payoutNextAt = savedPayoutNextAt,
    payoutTotal = 0,
    payoutCount = 0,
    payoutCash = nil,
    payoutNote = "ready",

    -- contract loop
    autoLoop = false,
    autoLoopMission = "Museum",
    autoLoopDelay = 3,
    autoLoopComplete = true,
    autoLoopCycles = 0,
    autoLoopNote = "off",
    autoLoopNextAt = 0,
    autoLoopBusy = false,

    -- campaign / quest helper
    campaignGuide = false,
    campaignPlay = false,
    campaignMission = "Maple",
    campaignSkipDone = true,
    campaignIncludeSide = true,
    campaignDelay = 3,
    campaignNote = "off",
    campaignGuideNote = "off",
    campaignIndex = 0,
    campaignTotal = 0,
    campaignCurrent = nil,

    dead = false,
}

local original = {}
local ui = {}
local espRecords = {}
local fovCircle = nil
local spreadBackup = {}

-- Helpers ---------------------------------------------------------------------

local function currentAgent()
    return Game.agent
end

local function currentMission()
    return Game.mission
end

local function aimPart(npc)
    local actor = npc and npc.actor
    local model = actor and actor.model
    if not model then
        return nil
    end

    local wanted = state.hitPart == "Torso" and "UpperTorso" or "Head"
    return model:FindFirstChild(wanted)
        or model:FindFirstChild("Head")
        or model:FindFirstChild("UpperTorso")
end

local function isCivilian(npc)
    local role = string.lower(tostring(npc.role or ""))
    return role == "civilian" or role == "bystander" or role == "staff"
end

local function isPolice(npc)
    local role = string.lower(tostring(npc.role or ""))
    return role:find("police") ~= nil or role:find("deputy") ~= nil
end

local function roleColor(npc)
    if npc.isTarget then
        return state.colorTarget
    end

    local role = string.lower(tostring(npc.role or ""))
    if role:find("guard") or role:find("police") or role:find("enforcer")
        or role:find("security") or role:find("patrol") or role:find("agent") then
        return state.colorHostile
    end
    if role:find("crew") then
        return state.colorCrew
    end
    if npc.armed then
        return state.colorHostile
    end
    return state.colorCivilian
end

-- Hooks -----------------------------------------------------------------------

local function installHooks()
    if Agent and Agent.hurt and not original.hurt then
        original.hurt = Agent.hurt
        Agent.hurt = function(self, amount, direction)
            if state.godmode then
                return
            end
            return original.hurt(self, amount, direction)
        end
    end

    if Agent and Agent.wantedSpeed and not original.wantedSpeed then
        original.wantedSpeed = Agent.wantedSpeed
        Agent.wantedSpeed = function(self, running)
            if state.speedOn then
                return state.speed
            end
            return original.wantedSpeed(self, running)
        end
    end

    if NPC and NPC.canSeeAgent and not original.canSeeAgent then
        original.canSeeAgent = NPC.canSeeAgent
        NPC.canSeeAgent = function(self, ...)
            if state.undetectable then
                return false, 0
            end
            return original.canSeeAgent(self, ...)
        end
    end

    if Cam and Cam.kick and not original.kick then
        original.kick = Cam.kick
        Cam.kick = function(...)
            if state.noRecoil then
                return
            end
            return original.kick(...)
        end
    end

    if Cam and Cam.shake and not original.shake then
        original.shake = Cam.shake
        Cam.shake = function(...)
            if state.noRecoil then
                return
            end
            return original.shake(...)
        end
    end
end

local function restoreHooks()
    if original.hurt then
        Agent.hurt = original.hurt
        original.hurt = nil
    end
    if original.wantedSpeed then
        Agent.wantedSpeed = original.wantedSpeed
        original.wantedSpeed = nil
    end
    if original.canSeeAgent then
        NPC.canSeeAgent = original.canSeeAgent
        original.canSeeAgent = nil
    end
    if Cam and original.kick then
        Cam.kick = original.kick
        original.kick = nil
    end
    if Cam and original.shake then
        Cam.shake = original.shake
        original.shake = nil
    end
end

installHooks()

-- Spread ----------------------------------------------------------------------

local function setSpreadZero(enabled)
    if not Config or not Config.Items then
        return
    end

    for id, def in pairs(Config.Items) do
        if def.kind == "gun" and type(def.spread) == "number" then
            if enabled then
                if spreadBackup[id] == nil then
                    spreadBackup[id] = def.spread
                end
                def.spread = 0
            elseif spreadBackup[id] ~= nil then
                def.spread = spreadBackup[id]
                spreadBackup[id] = nil
            end
        end
    end
end

-- Aim -------------------------------------------------------------------------

local function findTarget()
    local camera = workspace.CurrentCamera
    local agent = currentAgent()
    if not camera or not agent or not agent.alive then
        return nil
    end

    local origin = camera.CFrame.Position
    local look = camera.CFrame.LookVector
    local cutoff = math.cos(math.rad(state.fov * 0.5))
    local best, bestScore = nil, math.huge

    for _, npc in ipairs(NPC.all) do
        local wanted = Game.mission and Game.mission.wanted
        local allowed = npc.alive
            and not npc.ko
            and (not state.targetsOnly or npc.isTarget)
            and (not state.avoidCivilians or npc.isTarget or not isCivilian(npc))
            and (not state.avoidPolice or npc.isTarget or wanted or not isPolice(npc))

        if allowed then
            local part = aimPart(npc)
            if part then
                local delta = part.Position - origin
                local distance = delta.Magnitude
                if distance > 1 and distance <= state.maxDistance then
                    local dot = look:Dot(delta.Unit)
                    if dot >= cutoff then
                        local score = math.acos(math.clamp(dot, -1, 1))
                        if state.preferTarget and npc.isTarget then
                            score = score - 10
                        end
                        if score < bestScore then
                            best, bestScore = npc, score
                        end
                    end
                end
            end
        end
    end

    return best
end

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.IgnoreWater = true
losParams.RespectCanCollide = false

local function hasLineOfSight(npc, part)
    if not state.requireLos then
        return true
    end

    local camera = workspace.CurrentCamera
    if not camera then
        return false
    end

    local ignore = { part.Parent }
    local agent = currentAgent()
    if agent and agent.actor then
        table.insert(ignore, agent.actor.model)
    end

    losParams.FilterDescendantsInstances = ignore

    local origin = camera.CFrame.Position
    return workspace:Raycast(origin, part.Position - origin, losParams) == nil
end

-- Returns the held gun, or switches to the first gun in the inventory. Slot 0
-- means nothing held, and a held coin/lockpick also can't shoot, so both need
-- the same fix before Agent:fireGun will do anything.
local function equippedGun(agent)
    local item = agent:current()
    if item then
        local def = Config.Items[item.id]
        if def and def.kind == "gun" then
            return item, def
        end
    end

    for index, entry in ipairs(agent.inv or {}) do
        local def = Config.Items[entry.id]
        if def and def.kind == "gun" then
            if agent.slot ~= index then
                pcall(agent.select, agent, index)
            end

            local held = agent:current()
            local heldDef = held and Config.Items[held.id]
            if heldDef and heldDef.kind == "gun" then
                return held, heldDef
            end

            return nil
        end
    end

    return nil
end

local function fireAt(npc)
    local agent = currentAgent()
    if not agent or not agent.alive or agent.hidden or agent.busy or agent.dragging then
        return false
    end

    local item, def = equippedGun(agent)
    if not item or not def then
        return false
    end

    if agent.reloading or os.clock() < (agent.nextShot or 0) then
        return false
    end

    if (item.mag or 0) <= 0 then
        if state.infAmmo then
            item.mag = def.mag
        else
            return false
        end
    end

    local part = aimPart(npc)
    if not part then
        return false
    end

    if not hasLineOfSight(npc, part) then
        return false
    end

    -- Silent aim: the game's shot is cast from workspace.CurrentCamera, so point
    -- the camera at the target for the duration of the call and put it straight
    -- back. The frame is never rendered in between, so nothing visibly moves.
    local camera = workspace.CurrentCamera
    local restore = camera.CFrame
    camera.CFrame = CFrame.lookAt(restore.Position, part.Position)

    local ok = pcall(agent.fireGun, agent, item, def)

    camera.CFrame = restore

    return ok
end

-- FOV circle ------------------------------------------------------------------

local function ensureCircle()
    if fovCircle or typeof(Drawing) ~= "table" then
        return fovCircle
    end

    local ok, circle = pcall(function()
        local newCircle = Drawing.new("Circle")
        newCircle.Thickness = 1.5
        newCircle.NumSides = 64
        newCircle.Filled = false
        newCircle.Visible = false
        newCircle.Color = Color3.fromRGB(255, 255, 255)
        newCircle.Transparency = 1
        return newCircle
    end)

    if ok then
        fovCircle = circle
    end

    return fovCircle
end

local function fovRadiusPixels()
    local camera = workspace.CurrentCamera
    if not camera then
        return 0
    end

    local halfFov = math.tan(math.rad(state.fov * 0.5))
    local halfCam = math.tan(math.rad(camera.FieldOfView * 0.5))
    return halfFov / halfCam * (camera.ViewportSize.Y * 0.5)
end

-- ESP -------------------------------------------------------------------------

local function destroyEspRecord(model)
    local record = espRecords[model]
    if not record then
        return
    end

    if record.highlight then
        record.highlight:Destroy()
    end
    if record.billboard then
        record.billboard:Destroy()
    end

    espRecords[model] = nil
end

local function clearEsp()
    for model in pairs(espRecords) do
        destroyEspRecord(model)
    end
end

local function createEspRecord(npc, model)
    local record = {}
    local color = roleColor(npc)

    local highlight = Instance.new("Highlight")
    highlight.Name = "HitBloxEsp"
    highlight.Adornee = model
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = color
    highlight.FillTransparency = 0.78
    highlight.OutlineColor = color
    highlight.OutlineTransparency = 0
    highlight.Parent = model
    record.highlight = highlight

    local anchor = model:FindFirstChild("Head") or model:FindFirstChild("UpperTorso")
    if anchor then
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "HitBloxEspTag"
        billboard.AlwaysOnTop = true
        billboard.LightInfluence = 0
        billboard.MaxDistance = 1200
        billboard.Size = UDim2.fromOffset(260, 44)
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.3, 0)

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 14
        label.TextWrapped = true
        label.TextColor3 = color
        label.TextStrokeColor3 = Color3.new(0, 0, 0)
        label.TextStrokeTransparency = 0
        label.RichText = true
        label.Parent = billboard

        billboard.Parent = anchor
        record.billboard = billboard
        record.label = label
    end

    espRecords[model] = record
    return record
end

local espClock = 0

local function espStep(dt)
    if not state.esp then
        if next(espRecords) ~= nil then
            clearEsp()
        end
        return
    end

    espClock = espClock + dt
    if espClock < 0.15 then
        return
    end
    espClock = 0

    local agent = currentAgent()
    local origin = agent and agent.actor and agent.actor.root.Position
        or workspace.CurrentCamera.CFrame.Position
    local visible = {}

    for _, npc in ipairs(NPC.all) do
        local model = npc.actor and npc.actor.model
        local show = model and (state.espAll or npc.isTarget) and (npc.alive or npc.wounded)
        local distance = 0

        if show then
            distance = math.floor((model:GetPivot().Position - origin).Magnitude + 0.5)
            if distance > state.espRange then
                show = false
            end
        end

        if show then
            visible[model] = true
            local record = espRecords[model] or createEspRecord(npc, model)
            local color = roleColor(npc)

            if record.highlight then
                record.highlight.Enabled = state.espChams
                record.highlight.FillColor = color
                record.highlight.OutlineColor = color
            end

            if record.label then
                local parts = {}

                if state.espNames then
                    table.insert(parts, npc.name or "?")
                end
                if state.espRole then
                    table.insert(parts, npc.role or "?")
                end
                if state.espDistance then
                    table.insert(parts, ("%dm"):format(distance))
                end

                local text = table.concat(parts, "  ")
                if state.espHealth then
                    text = ("%s\n<color=#ffffff>HP %d</color>"):format(
                        text,
                        math.max(0, math.floor(npc.hp or 0))
                    )
                end

                record.label.Text = text
                record.label.TextColor3 = color
            end
        end
    end

    for model in pairs(espRecords) do
        if not visible[model] then
            destroyEspRecord(model)
        end
    end
end

-- Body hiding -----------------------------------------------------------------

local hideClock = 0
local bodiesHidden = 0

local function findContainer(position)
    if not World then
        return nil
    end

    local best, bestDistance = nil, math.huge

    for _, container in ipairs(World.containers or {}) do
        local stored = container.stored or 0
        local capacity = container.capacity or 0

        if stored < capacity and container.pos then
            local distance = (container.pos - position).Magnitude
            if distance < bestDistance then
                best, bestDistance = container, distance
            end
        end
    end

    return best
end

local function hideBody(body, container)
    local actor = body.actor
    local model = actor and actor.model

    if not model or not model.Parent then
        return false
    end

    -- Same result as Agent:dumpBody, minus the walk to the closet: the container
    -- stores the body, guards stop seeing it, and the mission gets the credit.
    body.hidden = true
    container.stored = (container.stored or 0) + 1
    bodiesHidden = bodiesHidden + 1

    if container.animate then
        pcall(container.animate, 70)
    end

    if Audio and container.pos then
        pcall(Audio.play, "Slider", container.pos, 0.7)
    end

    task.delay(0.55, function()
        if not model.Parent then
            return
        end

        for _, part in ipairs(model:GetDescendants()) do
            if part:IsA("BasePart") then
                part.Anchored = true
                part.CanCollide = false
                part.CanQuery = false
                part.Transparency = 1
            elseif part:IsA("Decal") then
                part.Transparency = 1
            end
        end

        for _, name in ipairs({ "Shirt", "Pants" }) do
            local clothing = model:FindFirstChild(name)
            if clothing then
                clothing:Destroy()
            end
        end

        local position = container.pos or model:GetPivot().Position
        pcall(function()
            model:PivotTo(CFrame.new(position + Vector3.new(0, -60, 0)))
        end)

        task.delay(0.35, function()
            if container.animate then
                pcall(container.animate, 0)
            end
        end)

        if Audio and container.pos then
            pcall(Audio.play, "BodyFall", container.pos, 0.5)
        end

        local mission = currentMission()
        if mission and body.npc and body.npc.body == body then
            pcall(mission.bodyHidden, mission, body)
        end
    end)

    return true
end

local function hideStep(dt, force)
    if state.dead then
        return 0
    end

    if not force then
        if not state.autoHideBodies then
            return 0
        end

        hideClock = hideClock + dt
        if hideClock < 0.5 then
            return 0
        end
        hideClock = 0
    end

    local agent = currentAgent()
    if not agent or not agent.alive or agent.hidden or agent.busy or agent.dragging then
        return 0
    end

    if not World or not agent.actor or not agent.actor.root then
        return 0
    end

    local origin = agent.actor.root.Position
    local hidden = 0

    for _, body in ipairs(World.bodies or {}) do
        local model = body.actor and body.actor.model

        if not body.hidden
            and model
            and model.Parent
            and body.time
            and os.clock() - body.time >= 0.8 then
            local torso = model:FindFirstChild("UpperTorso")
            if torso and (torso.Position - origin).Magnitude <= state.hideRange then
                local container = findContainer(torso.Position)
                if container and hideBody(body, container) then
                    hidden = hidden + 1
                end
            end
        end
    end

    return hidden
end

-- Movement --------------------------------------------------------------------

RunService.Stepped:Connect(function()
    if state.dead then
        return
    end

    local agent = currentAgent()
    if not agent or not agent.actor then
        return
    end

    local model = agent.actor.model
    local humanoid = agent.actor.hum or (model and model:FindFirstChildOfClass("Humanoid"))

    if state.noclip and model then
        for _, part in ipairs(model:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end

    if humanoid and state.jumpOn then
        humanoid.UseJumpPower = true
        humanoid.JumpPower = state.jump
    end
end)

-- Ammo ------------------------------------------------------------------------

local function ammoStep()
    local agent = currentAgent()
    if not agent then
        return
    end

    if state.instantReload and agent.reloading then
        agent.reloading = false
    end

    if not state.infAmmo then
        return
    end

    local changed = false

    for _, item in ipairs(agent.inv or {}) do
        local def = Config.Items[item.id]
        if def and def.kind == "gun" then
            if (item.mag or 0) < (def.mag or 0) then
                item.mag = def.mag
                changed = true
            end
            if (item.spare or 0) < (def.spare or 0) then
                item.spare = def.spare
                changed = true
            end
        end
    end

    if changed and agent.changed then
        agent.changed:Fire("inventory")
    end
end

-- Main loop -------------------------------------------------------------------

RunService.RenderStepped:Connect(function(dt)
    if state.dead then
        return
    end

    local circle = ensureCircle()
    if circle then
        local camera = workspace.CurrentCamera
        circle.Visible = state.aimbot and camera ~= nil and state.fov < 360
        if circle.Visible then
            circle.Position = Vector2.new(
                camera.ViewportSize.X * 0.5,
                camera.ViewportSize.Y * 0.5
            )
            circle.Radius = fovRadiusPixels()
        end
    end

    if state.aimbot then
        local target = findTarget()
        if target and (state.autoFire or state.aimHeld) then
            fireAt(target)
        end
    end

    espStep(dt)
    ammoStep()
    hideStep(dt)
end)

-- Mission actions -------------------------------------------------------------

local function completeObjectives()
    local mission = currentMission()
    if not mission or not mission.objectives then
        return false
    end

    for _, objective in ipairs(mission.objectives) do
        pcall(mission.complete, mission, objective.id)
    end

    return true
end

local function finishContract()
    local mission = currentMission()
    if not mission or not mission.running then
        return false
    end

    return pcall(mission.finish, mission, true)
end

local function clearHeat()
    local mission = currentMission()
    if not mission then
        return false
    end

    mission.wanted = false
    mission.policeAt = math.huge
    mission.wantedUntil = 0

    if mission.changed then
        mission.changed:Fire("alarm")
    end

    return true
end

local function teleportToTarget()
    local agent = currentAgent()
    if not agent or not agent.actor then
        return false
    end

    for _, npc in ipairs(NPC.all) do
        if npc.isTarget and npc.alive and npc.actor then
            local root = npc.actor.root
            agent.actor.root.CFrame = root.CFrame * CFrame.new(0, 0, 3)
            return true
        end
    end

    return false
end

local function giveItem(id)
    local agent = currentAgent()
    if not agent or not id or id == "" then
        return false
    end

    local ok = pcall(agent.addItem, agent, id, 1, nil, nil, true)
    if ok then
        pcall(agent.select, agent, #agent.inv)
    end

    return ok
end

-- UI --------------------------------------------------------------------------

local Window = Rayfield:CreateWindow({
    name = "HitBlox",
    subtitle = "Slim",
    sidebarLayout = true,
    configuration = {
        autoSave = true,
        autoLoad = true,
        fileName = "HitBloxHub",
    },
})

-- Combat ----------------------------------------------------------------------

local combatTab = Window:CreateTab({ name = "Combat" })
combatTab:CreateSection({ name = "Aim" })

ui.aimbot = combatTab:CreateToggle({
    name = "Aimbot",
    description = "Silent aim through the game's own shot pipeline.",
    value = false,
    flag = "hbAimbot",
    callback = function(value)
        state.aimbot = value
    end,
})

ui.autoFire = combatTab:CreateToggle({
    name = "Auto fire",
    description = "Shoot automatically whenever a target is in the FOV.",
    value = true,
    flag = "hbAutoFire",
    callback = function(value)
        state.autoFire = value
    end,
})

combatTab:CreateKeybind({
    name = "Aim key (hold)",
    description = "Fire only while this key is held, when auto fire is off.",
    value = Enum.KeyCode.LeftAlt,
    hold = true,
    holdThreshold = 0.05,
    callback = function(down)
        state.aimHeld = down == true
    end,
})

combatTab:CreateSlider({
    name = "FOV",
    range = { 10, 360 },
    increment = 5,
    value = 140,
    suffix = "°",
    flag = "hbFov",
    callback = function(value)
        state.fov = value
    end,
})

combatTab:CreateSlider({
    name = "Max distance",
    range = { 20, 600 },
    increment = 10,
    value = 350,
    suffix = " studs",
    flag = "hbMaxDistance",
    callback = function(value)
        state.maxDistance = value
    end,
})

combatTab:CreateDropdown({
    name = "Hitbox",
    options = { "Head", "Torso" },
    value = "Head",
    flag = "hbHitPart",
    callback = function(selected)
        state.hitPart = selected
    end,
})

combatTab:CreateToggle({
    name = "Prefer mission target",
    value = true,
    flag = "hbPreferTarget",
    callback = function(value)
        state.preferTarget = value
    end,
})

combatTab:CreateToggle({
    name = "Mission targets only",
    value = false,
    flag = "hbTargetsOnly",
    callback = function(value)
        state.targetsOnly = value
    end,
})

combatTab:CreateToggle({
    name = "Ignore civilians",
    description = "Never auto-target unarmed civilians. Mission targets always allowed.",
    value = true,
    flag = "hbAvoidCivilians",
    callback = function(value)
        state.avoidCivilians = value
    end,
})

combatTab:CreateToggle({
    name = "Ignore police unless wanted",
    description = "Stops the aimbot from gunning down police before you have heat.",
    value = true,
    flag = "hbAvoidPolice",
    callback = function(value)
        state.avoidPolice = value
    end,
})

combatTab:CreateToggle({
    name = "Require line of sight",
    description = "Hold fire when a wall is between you and the target, so ammo isn't wasted.",
    value = true,
    flag = "hbRequireLos",
    callback = function(value)
        state.requireLos = value
    end,
})

combatTab:CreateSection({ name = "Weapon" })

ui.noSpread = combatTab:CreateToggle({
    name = "No spread",
    description = "Zeroes every gun's spread value while enabled.",
    value = false,
    flag = "hbNoSpread",
    callback = function(value)
        state.noSpread = value
        setSpreadZero(value)
    end,
})

ui.noRecoil = combatTab:CreateToggle({
    name = "No recoil / shake",
    value = false,
    flag = "hbNoRecoil",
    callback = function(value)
        state.noRecoil = value
    end,
})

ui.infAmmo = combatTab:CreateToggle({
    name = "Infinite ammo",
    value = false,
    flag = "hbInfAmmo",
    callback = function(value)
        state.infAmmo = value
    end,
})

ui.instantReload = combatTab:CreateToggle({
    name = "Instant reload",
    value = false,
    flag = "hbInstantReload",
    callback = function(value)
        state.instantReload = value
    end,
})

local itemNames = {}
for id, def in pairs(Config.Items) do
    if def.kind ~= "key" and def.kind ~= "tamper" then
        table.insert(itemNames, id)
    end
end
table.sort(itemNames)

local selectedItem = itemNames[1]

combatTab:CreateDropdown({
    name = "Give item",
    options = itemNames,
    value = selectedItem,
    flag = "hbGiveItem",
    callback = function(selected)
        selectedItem = selected
    end,
})

combatTab:CreateButton({
    name = "Add selected item",
    callback = function()
        if giveItem(selectedItem) then
            Window:Notify({ title = "Item added", content = tostring(selectedItem) })
        else
            Window:Notify({ title = "Item failed", content = "Not in a mission?" })
        end
    end,
})

-- Visuals ---------------------------------------------------------------------

local visualTab = Window:CreateTab({ name = "Visuals" })

ui.esp = visualTab:CreateToggle({
    name = "Player ESP",
    description = "Highlight, name, role and distance for everyone in the mission.",
    value = false,
    flag = "hbEsp",
    callback = function(value)
        state.esp = value
        if not value then
            clearEsp()
        end
    end,
})

visualTab:CreateToggle({
    name = "Show everyone",
    description = "Off = mission targets only.",
    value = true,
    flag = "hbEspAll",
    callback = function(value)
        state.espAll = value
    end,
})

visualTab:CreateSlider({
    name = "ESP distance",
    range = { 50, 800 },
    increment = 25,
    value = 300,
    suffix = " studs",
    flag = "hbEspRange",
    callback = function(value)
        state.espRange = value
    end,
})

visualTab:CreateToggle({
    name = "Chams (through walls)",
    value = true,
    flag = "hbEspChams",
    callback = function(value)
        state.espChams = value
    end,
})

visualTab:CreateToggle({
    name = "Names",
    value = true,
    flag = "hbEspNames",
    callback = function(value)
        state.espNames = value
    end,
})

visualTab:CreateToggle({
    name = "Roles",
    value = true,
    flag = "hbEspRole",
    callback = function(value)
        state.espRole = value
    end,
})

visualTab:CreateToggle({
    name = "Distance",
    value = true,
    flag = "hbEspDistance",
    callback = function(value)
        state.espDistance = value
    end,
})

visualTab:CreateToggle({
    name = "Health",
    value = false,
    flag = "hbEspHealth",
    callback = function(value)
        state.espHealth = value
    end,
})

visualTab:CreateColorPicker({
    name = "Target colour",
    color = Color3.fromRGB(255, 64, 64),
    flag = "hbColorTarget",
    callback = function(color)
        state.colorTarget = color
    end,
})

visualTab:CreateColorPicker({
    name = "Hostile colour",
    color = Color3.fromRGB(255, 160, 60),
    flag = "hbColorHostile",
    callback = function(color)
        state.colorHostile = color
    end,
})

visualTab:CreateColorPicker({
    name = "Civilian colour",
    color = Color3.fromRGB(120, 220, 140),
    flag = "hbColorCivilian",
    callback = function(color)
        state.colorCivilian = color
    end,
})

visualTab:CreateColorPicker({
    name = "Crew colour",
    color = Color3.fromRGB(120, 180, 255),
    flag = "hbColorCrew",
    callback = function(color)
        state.colorCrew = color
    end,
})

-- Stealth ---------------------------------------------------------------------

local stealthTab = Window:CreateTab({ name = "Stealth" })

ui.undetectable = stealthTab:CreateToggle({
    name = "Undetectable",
    description = "Guards and cameras never see you (NPC.canSeeAgent returns false).",
    value = false,
    flag = "hbUndetectable",
    callback = function(value)
        state.undetectable = value
    end,
})

ui.godmode = stealthTab:CreateToggle({
    name = "Godmode",
    description = "Blocks all incoming damage at Agent.hurt.",
    value = false,
    flag = "hbGodmode",
    callback = function(value)
        state.godmode = value
    end,
})

ui.autoHideBodies = stealthTab:CreateToggle({
    name = "Auto hide bodies",
    description = "Hides dead bodies in the nearest container with space. No dragging, no teleport.",
    value = true,
    flag = "hbAutoHide",
    callback = function(value)
        state.autoHideBodies = value
    end,
})

stealthTab:CreateSlider({
    name = "Auto-hide range",
    description = "How close a body must be to you before it is hidden.",
    range = { 5, 120 },
    increment = 5,
    value = 30,
    suffix = " studs",
    flag = "hbHideRange",
    callback = function(value)
        state.hideRange = value
    end,
})

stealthTab:CreateButton({
    name = "Hide bodies now",
    description = "One sweep of the auto-hide range, even with auto-hide off.",
    callback = function()
        local count = hideStep(0, true)
        if count > 0 then
            Window:Notify({
                title = "Bodies",
                content = ("Hid %d bod%s."):format(count, count == 1 and "y" or "ies"),
            })
        else
            Window:Notify({ title = "Bodies", content = "No body in range with a free container." })
        end
    end,
})

-- Movement --------------------------------------------------------------------

local movementTab = Window:CreateTab({ name = "Movement" })

ui.speedOn = movementTab:CreateToggle({
    name = "Speed override",
    value = false,
    flag = "hbSpeedOn",
    callback = function(value)
        state.speedOn = value
    end,
})

movementTab:CreateSlider({
    name = "Walk speed",
    range = { 8, 120 },
    increment = 1,
    value = 16,
    flag = "hbSpeed",
    callback = function(value)
        state.speed = value
    end,
})

ui.jumpOn = movementTab:CreateToggle({
    name = "Jump power override",
    value = false,
    flag = "hbJumpOn",
    callback = function(value)
        state.jumpOn = value
    end,
})

movementTab:CreateSlider({
    name = "Jump power",
    range = { 20, 200 },
    increment = 5,
    value = 50,
    flag = "hbJump",
    callback = function(value)
        state.jump = value
    end,
})

ui.noclip = movementTab:CreateToggle({
    name = "Noclip",
    value = false,
    flag = "hbNoclip",
    callback = function(value)
        state.noclip = value
    end,
})

-- Contract --------------------------------------------------------------------

local missionTab = Window:CreateTab({ name = "Contract" })

-- SaveResult is a RemoteFunction under ReplicatedStorage.HitbloxRemotes. The
-- server trusts the result fields, so this fabricates a maximum Museum repeat
-- payout. It has a separate ~180 s global cooldown; every attempt resets it.

local PAYOUT_COOLDOWN = 190

local function payoutReadyIn()
    return math.max(0, state.payoutNextAt - os.time())
end

local function payoutRemote()
    local remotes = ReplicatedStorage:FindFirstChild("HitbloxRemotes")
    local save = remotes and remotes:FindFirstChild("SaveResult")
    if save and save:IsA("RemoteFunction") then
        return save
    end
    return nil
end

local function shortNote(value)
    local text = tostring(value or "no payout")
    if #text > 64 then
        text = text:sub(1, 61) .. "..."
    end
    return text
end

local function collectPayout(manual)
    if state.payoutBusy then
        if manual then
            Window:Notify({ title = "Payout", content = "A payout call is already running." })
        end
        return false
    end

    local remote = payoutRemote()
    if not remote then
        if manual then
            Window:Notify({ title = "Payout", content = "SaveResult not found - rejoin HITBLOX." })
        end
        return false
    end

    local left = payoutReadyIn()
    if left > 0 then
        if manual then
            Window:Notify({
                title = "Payout",
                content = ("Cooldown: %d s left. A blocked call would reset it."):format(math.ceil(left)),
            })
        end
        return false
    end

    state.payoutBusy = true
    state.payoutLastAt = os.time()
    state.payoutNextAt = state.payoutLastAt + PAYOUT_COOLDOWN
    if getgenv then
        getgenv().HitBloxPayoutNextAt = state.payoutNextAt
    end

    local ok, res = pcall(function()
        return remote:InvokeServer({
            mission = "Museum",
            disguises = 1,
            success = true,
            score = 500000,
            stars = 5,
            time = 99999,
            challenges = {},
            files = 0,
            accidents = 100,
            nonTargets = 0,
            loot = 3000,
            jobs = 100,
        })
    end)

    state.payoutBusy = false

    local pay = ok and type(res) == "table" and res.pay or nil
    local total = pay and tonumber(pay.total) or nil

    if total and total > 0 then
        state.payoutTotal = state.payoutTotal + total
        state.payoutCount = state.payoutCount + 1
        state.payoutNote = ("+$%d"):format(total)
        if pay.balance then
            state.payoutCash = tonumber(pay.balance) or state.payoutCash
        end
        if manual then
            Window:Notify({
                title = "Payout",
                content = ("Collected $%d. Cash: $%s"):format(
                    total,
                    state.payoutCash and tostring(state.payoutCash) or "?"
                ),
            })
        end
        return true
    end

    local label
    if ok and type(res) == "table" and pay and pay.lines and pay.lines[1] then
        label = pay.lines[1].label
    end
    state.payoutNote = shortNote(label or (ok and "no payout" or res))
    if manual then
        Window:Notify({ title = "Payout", content = state.payoutNote })
    end
    return false
end

-- Auto contract loop ---------------------------------------------------------
--
-- quick() is the game's own fast-start path: it builds the map, creates the
-- Agent and Mission, and runs the short intro. Finishing goes through the
-- regular results screen and SaveResult, so progress and the server's payout
-- rules still apply. No invented remotes.

local autoLoopToken = 0
local stopCampaignFromLoop = nil

local function autoLoopChoices()
    local choices = {}
    local boot = Game.boot
    for _, def in ipairs(boot and boot.missions or {}) do
        if def.id then
            table.insert(choices, def.id)
        end
    end

    if #choices == 0 then
        choices = {
            "Museum", "Bank", "Halcyon", "Tower", "Estate", "Rig",
            "Express", "Hotel", "Ranch", "Pier", "Creek", "Maple",
        }
    end

    return choices
end

local function autoLoopFind(id)
    local boot = Game.boot
    if not boot then
        return nil
    end

    if type(boot.find) == "function" then
        local ok, def = pcall(boot.find, id)
        if ok and def then
            return def
        end
    end

    for _, def in ipairs(boot.missions or {}) do
        if def.id == id then
            return def
        end
    end

    return nil
end

local function autoLoopSyncPayout()
    -- Finishing a contract calls the game's SaveResult, which starts the same
    -- server cooldown the fabricated payout uses. Keep the local timer honest
    -- so auto-payout does not waste an attempt while the loop is running.
    state.payoutNextAt = math.max(state.payoutNextAt, os.time() + PAYOUT_COOLDOWN)
    if getgenv then
        getgenv().HitBloxPayoutNextAt = state.payoutNextAt
    end
end

local function autoLoopOnce(manual)
    if manual and state.campaignPlay then
        return false, "campaign auto-play is running"
    end

    local boot = Game.boot
    if not boot or type(boot.quick) ~= "function" then
        return false, "HITBLOX boot not ready"
    end

    local mission = currentMission()
    if not (mission and mission.running) then
        local def = autoLoopFind(state.autoLoopMission)
        if not def then
            return false, ("unknown contract: %s"):format(tostring(state.autoLoopMission))
        end

        if state.autoLoop or manual then
            state.autoLoopNote = ("starting %s"):format(tostring(def.id))
        end
        local ok, err = pcall(boot.quick, def.id)
        if not ok then
            return false, ("start failed: %s"):format(tostring(err))
        end

        -- The short intro sets Game.running. Finishing before it ends would let
        -- the intro callback flip Game.running back on after the result.
        local deadline = os.clock() + 10
        while (manual or state.autoLoop) and not state.dead and not Game.running
            and os.clock() < deadline do
            task.wait(0.1)
        end

        mission = currentMission()
        if not (mission and mission.running) then
            return false, "contract did not start"
        end
    end

    if state.autoLoopComplete then
        if state.autoLoop or manual then
            state.autoLoopNote = "completing objectives"
        end
        completeObjectives()
        task.wait(0.4)
    end

    if mission.running then
        if state.autoLoop or manual then
            state.autoLoopNote = "finishing"
        end
        local ok, err = pcall(function()
            mission:finish(true)
        end)
        if not ok then
            return false, ("finish failed: %s"):format(tostring(err))
        end
    end

    autoLoopSyncPayout()
    state.autoLoopCycles = state.autoLoopCycles + 1
    -- Stopping mid-cycle must keep the stop note; only a loop that is still
    -- running (or a deliberate single run) reports the finished cycle.
    if state.autoLoop or manual then
        state.autoLoopNote = ("cycle %d done"):format(state.autoLoopCycles)
    end
    return true
end

local function stopAutoLoop(note)
    state.autoLoop = false
    autoLoopToken = autoLoopToken + 1
    state.autoLoopNextAt = 0
    if note then
        state.autoLoopNote = note
    end
end

local function startAutoLoop()
    if state.autoLoop or state.dead then
        return
    end

    if stopCampaignFromLoop then
        stopCampaignFromLoop()
    end

    if not (Game.boot and type(Game.boot.quick) == "function") then
        Window:Notify({ title = "Auto loop", content = "HITBLOX boot is not ready yet." })
        return
    end

    state.autoLoop = true
    state.autoLoopNextAt = 0
    state.autoLoopNote = "starting"
    autoLoopToken = autoLoopToken + 1
    local token = autoLoopToken

    task.spawn(function()
        while state.autoLoop and not state.dead and token == autoLoopToken do
            state.autoLoopBusy = true
            local ok, result, err = pcall(autoLoopOnce)
            state.autoLoopBusy = false
            if not state.autoLoop or state.dead or token ~= autoLoopToken then
                break
            end

            if not ok then
                state.autoLoopNote = ("error: %s"):format(tostring(result))
                task.wait(3)
            elseif result == false then
                state.autoLoopNote = tostring(err or "loop stalled")
                task.wait(3)
            else
                local delay = math.max(1, tonumber(state.autoLoopDelay) or 3)
                state.autoLoopNextAt = os.clock() + delay
                task.wait(delay)
            end
        end

        if token == autoLoopToken then
            state.autoLoop = false
            state.autoLoopNextAt = 0
        end
    end)
end

missionTab:CreateSection({ name = "Payout" })

local payoutText = missionTab:CreateText({
    name = "Payout status",
    text = "Ready - about $6,008 every 190 s",
})

missionTab:CreateButton({
    name = "Collect payout (~$6,008)",
    description = "Fabricates a max Museum result through the game's SaveResult remote. Risky; server cooldown ~180 s.",
    callback = function()
        collectPayout(true)
    end,
})

ui.autoPayout = missionTab:CreateToggle({
    name = "Auto collect payout",
    description = "Waits 190 s, then fires once between contracts. Every attempt resets the server cooldown.",
    value = false,
    flag = "hbAutoPayout",
    callback = function(value)
        state.autoPayout = value
    end,
})

local statusText = missionTab:CreateText({
    name = "Status",
    text = "Waiting for a contract...",
})

missionTab:CreateButton({
    name = "Complete all objectives",
    callback = function()
        if completeObjectives() then
            Window:Notify({ title = "Objectives", content = "All objectives marked done." })
        end
    end,
})

missionTab:CreateButton({
    name = "Finish contract now",
    description = "Ends the mission immediately and shows the result screen.",
    callback = function()
        if finishContract() then
            Window:Notify({ title = "Contract", content = "Mission finished." })
        end
    end,
})

missionTab:CreateButton({
    name = "Clear heat / police",
    callback = function()
        if clearHeat() then
            Window:Notify({ title = "Heat", content = "Police calls cleared." })
        end
    end,
})

missionTab:CreateButton({
    name = "Teleport to target",
    callback = function()
        if teleportToTarget() then
            Window:Notify({ title = "Teleport", content = "Moved to the mission target." })
        else
            Window:Notify({ title = "Teleport", content = "No living target found." })
        end
    end,
})

missionTab:CreateSection({ name = "Auto loop" })

local loopOptions = autoLoopChoices()
if not table.find(loopOptions, state.autoLoopMission) then
    state.autoLoopMission = loopOptions[1]
end

missionTab:CreateDropdown({
    name = "Loop contract",
    description = "The contract the loop starts from a clean map every cycle.",
    options = loopOptions,
    value = state.autoLoopMission,
    flag = "hbLoopMission",
    callback = function(selected)
        state.autoLoopMission = selected
    end,
})

missionTab:CreateSlider({
    name = "Loop delay",
    description = "Pause after a finished contract before the next one starts.",
    range = { 1, 30 },
    increment = 1,
    value = 3,
    suffix = " s",
    flag = "hbLoopDelay",
    callback = function(value)
        state.autoLoopDelay = value
    end,
})

missionTab:CreateToggle({
    name = "Complete objectives first",
    description = "Marks every objective done before finishing, so each cycle succeeds.",
    value = true,
    flag = "hbLoopComplete",
    callback = function(value)
        state.autoLoopComplete = value
    end,
})

local loopText = missionTab:CreateText({
    name = "Loop status",
    text = "off - choose a contract and enable the loop",
})

ui.autoLoop = missionTab:CreateToggle({
    name = "Auto contract loop",
    description = "Starts the chosen contract, completes its objectives, finishes it and repeats. Each finish uses the game's SaveResult, so leave Auto collect payout off while the loop runs - they share the same ~180 s cooldown.",
    value = false,
    flag = "hbAutoLoop",
    callback = function(value)
        if value then
            startAutoLoop()
        else
            stopAutoLoop("stopped")
        end
    end,
})

missionTab:CreateButton({
    name = "Run one contract now",
    description = "One loop cycle without enabling the loop.",
    callback = function()
        local ok, result, err = pcall(autoLoopOnce, true)
        if ok and result ~= false then
            Window:Notify({
                title = "Auto loop",
                content = ("Cycle %d done."):format(state.autoLoopCycles),
            })
        else
            Window:Notify({
                title = "Auto loop",
                content = tostring(ok and err or result),
            })
        end
    end,
})

-- Campaign / quest helper -----------------------------------------------------
--
-- The campaign order comes from Config.Acts: prequel quests, the act's
-- contracts, its finale and then the sequel quests. Missions start through
-- Boot.quick and finish through Mission:finish, exactly like the menus, so the
-- game records progress and SaveResult on its own terms.

local campaignToken = 0
local campaignPlayToggle = nil
local campaignHintFailures = {}
local campaignAtFailures = {}
local campaignGuidePart = nil
local campaignGuideBillboard = nil
local campaignGuideLabel = nil
local campaignGuideHint = nil

local function campaignEntryDef(id)
    return autoLoopFind(id)
end

local function campaignEntries(includeSide)
    local list = {}
    local seen = {}
    local acts = (Config and Config.Acts) or {}

    local function add(id, role, act, actTitle, numeral)
        if not id or seen[id] then
            return
        end

        seen[id] = true
        local def = campaignEntryDef(id)
        if not def then
            return
        end

        local side = def.kind == "Prequel" or def.kind == "Sequel" or def.kind == "Side"
        if includeSide == false and side then
            return
        end

        table.insert(list, {
            id = id,
            role = role or def.kind or "Contract",
            act = act or def.act or 0,
            actTitle = actTitle,
            numeral = numeral,
            def = def,
        })
    end

    for index, act in ipairs(acts) do
        local quests = act.quests or {}

        for _, id in ipairs(quests) do
            local def = campaignEntryDef(id)
            if def and def.kind == "Prequel" then
                add(id, "Prequel", index, act.title, act.numeral)
            end
        end

        for _, id in ipairs(act.contracts or {}) do
            add(id, "Contract", index, act.title, act.numeral)
        end

        add(act.finale, "Finale", index, act.title, act.numeral)

        for _, id in ipairs(quests) do
            local def = campaignEntryDef(id)
            if def and def.kind ~= "Prequel" then
                add(id, def.kind or "Sequel", index, act.title, act.numeral)
            end
        end
    end

    local boot = Game.boot
    for _, def in ipairs(boot and boot.quests or {}) do
        add(def.id, def.kind or "Side quest", def.act, "SIDE QUESTS", nil)
    end

    for _, def in ipairs(boot and boot.missions or {}) do
        if not seen[def.id] then
            add(def.id, def.kind or "Contract", def.act, "EXTRA CONTRACTS", nil)
        end
    end

    return list
end

local function campaignRecord(id)
    local boot = Game.boot
    local profile = boot and boot.profile or Game.profile
    local missions = profile and profile.missions
    return missions and missions[id]
end

local function campaignDone(id)
    local record = campaignRecord(id)
    return record ~= nil and record.done == true
end

local function campaignStatus(id)
    local record = campaignRecord(id)
    if not record then
        return "NEW"
    end
    if record.done then
        return ("DONE %d stars"):format(record.stars or 0)
    end
    return "STARTED"
end

local function campaignEntryById(id)
    for _, entry in ipairs(campaignEntries(true)) do
        if entry.id == id then
            return entry
        end
    end
    return nil
end

local function campaignRoadmap()
    local entries = campaignEntries(true)
    local done = 0
    for _, entry in ipairs(entries) do
        if campaignDone(entry.id) then
            done = done + 1
        end
    end

    local lines = { ("Campaign progress: %d/%d"):format(done, #entries) }
    local lastAct = nil

    for index, entry in ipairs(entries) do
        if entry.act ~= lastAct then
            lastAct = entry.act
            local numeral = entry.numeral or tostring(entry.act)
            local title = entry.actTitle or "SIDE QUESTS"
            lines[#lines + 1] = ""
            lines[#lines + 1] = ("ACT %s - %s"):format(numeral, title)
        end

        lines[#lines + 1] = ("%02d %-10s %-9s %s"):format(
            index,
            entry.id,
            entry.role,
            campaignStatus(entry.id)
        )
    end

    return table.concat(lines, "\n"), done, #entries
end

local function clearCampaignGuide()
    if campaignGuidePart then
        campaignGuidePart.Parent = nil
    end
    campaignGuidePart = nil
    campaignGuideBillboard = nil
    campaignGuideLabel = nil
    campaignGuideHint = nil
end

local function ensureCampaignGuide()
    if campaignGuidePart and campaignGuidePart.Parent then
        return
    end

    local part = Instance.new("Part")
    part.Name = "HitBloxQuestBeacon"
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    part.Size = Vector3.new(0.2, 0.2, 0.2)
    part.Transparency = 1
    part.Parent = workspace

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "HitBloxQuestBeaconGui"
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.MaxDistance = 5000
    billboard.Size = UDim2.fromOffset(380, 86)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
    billboard.Parent = part

    local label = Instance.new("TextLabel")
    label.Name = "Objective"
    label.BackgroundTransparency = 1
    label.Position = UDim2.fromOffset(0, 0)
    label.Size = UDim2.fromOffset(380, 46)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 18
    label.TextColor3 = Color3.fromRGB(255, 196, 96)
    label.TextStrokeTransparency = 0.25
    label.Text = ""
    label.Parent = billboard

    local hint = Instance.new("TextLabel")
    hint.Name = "Hint"
    hint.BackgroundTransparency = 1
    hint.Position = UDim2.fromOffset(0, 46)
    hint.Size = UDim2.fromOffset(380, 38)
    hint.Font = Enum.Font.Gotham
    hint.TextSize = 14
    hint.TextColor3 = Color3.fromRGB(235, 235, 235)
    hint.TextStrokeTransparency = 0.35
    hint.TextWrapped = true
    hint.Text = ""
    hint.Parent = billboard

    campaignGuidePart = part
    campaignGuideBillboard = billboard
    campaignGuideLabel = label
    campaignGuideHint = hint
end

local function campaignHintFor(label)
    if not label then
        return nil
    end

    local mission = currentMission()
    for _, objective in ipairs(mission and mission.objectives or {}) do
        if objective.text == label then
            local key = objective.id or objective.text
            local left = objective.left

            if type(left) == "function" and not campaignHintFailures[key] then
                local ok, result = pcall(left, mission)
                if ok then
                    left = result
                else
                    campaignHintFailures[key] = true
                    left = nil
                end
            elseif type(left) == "function" then
                left = nil
            end

            if type(left) == "string" then
                return left
            end
        end
    end

    return nil
end

local function campaignMarker()
    local mission = currentMission()
    if not (mission and mission.running) then
        return nil
    end

    local ok, position, label, kind = pcall(function()
        return mission:guideMarker()
    end)

    if ok and typeof(position) == "Vector3" then
        return position, label, kind or "story", campaignHintFor(label)
    end

    for _, objective in ipairs(mission.objectives or {}) do
        if not objective.done
            and not objective.optional
            and not objective.hidden
            and not objective.failed then
            local at = objective.at

            if type(at) == "function" then
                local key = objective.id or objective.text
                if not campaignAtFailures[key] then
                    local atOk, result = pcall(at, mission)
                    if atOk then
                        at = result
                    else
                        campaignAtFailures[key] = true
                        at = nil
                    end
                else
                    at = nil
                end
            end

            if typeof(at) == "Vector3" then
                return at, objective.text, "objective", campaignHintFor(objective.text)
            end

            if type(at) == "string" and World and World.spots then
                local spot = World.spots[at]
                if spot and spot.cf then
                    return spot.cf.Position, objective.text, "objective",
                        campaignHintFor(objective.text)
                end
            end
        end
    end

    local agent = currentAgent()
    local origin = agent and agent.actor and agent.actor.root
        and agent.actor.root.Position or nil
    local best = nil
    local bestDistance = nil

    for _, npc in ipairs(NPC.all or {}) do
        if npc.isTarget and npc.alive and npc.actor and npc.actor.root then
            local position = npc.actor.root.Position
            local distance = origin and (position - origin).Magnitude or 0
            if not bestDistance or distance < bestDistance then
                best = npc
                bestDistance = distance
            end
        end
    end

    if best then
        local name = best.name or best.role or "target"
        return best.actor.root.Position, ("Eliminate %s"):format(name), "target",
            "Eliminate all targets, then follow the exit marker."
    end

    return nil
end

local function campaignGuideStep()
    if not state.campaignGuide or state.dead then
        return
    end

    ensureCampaignGuide()

    local position, label, kind, hint = campaignMarker()
    if not position then
        campaignGuideBillboard.Enabled = false
        state.campaignGuideNote = "no active objective"
        return
    end

    campaignGuideBillboard.Enabled = true
    campaignGuidePart.CFrame = CFrame.new(position + Vector3.new(0, 0.2, 0))

    local agent = currentAgent()
    local origin = agent and agent.actor and agent.actor.root
        and agent.actor.root.Position or nil
    local distance = origin and math.floor((position - origin).Magnitude + 0.5) or 0
    local title = label or "Objective"

    campaignGuideLabel.Text = ("◆ %s   [%dm]"):format(title, distance)
    if kind == "target" then
        campaignGuideLabel.TextColor3 = Color3.fromRGB(255, 96, 96)
    elseif kind == "story" then
        campaignGuideLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    else
        campaignGuideLabel.TextColor3 = Color3.fromRGB(255, 196, 96)
    end
    campaignGuideHint.Text = hint or ""

    state.campaignGuideNote = ("guiding to %s (%dm)"):format(title, distance)
end

local function campaignObjectiveSummary()
    local mission = currentMission()
    if not (mission and mission.running) then
        return "no mission running"
    end

    local total = 0
    local done = 0
    local nextText = nil

    for _, objective in ipairs(mission.objectives or {}) do
        if not objective.optional and not objective.hidden then
            total = total + 1
            if objective.done then
                done = done + 1
            elseif not nextText then
                nextText = objective.text
            end
        end
    end

    if nextText and #nextText > 54 then
        nextText = nextText:sub(1, 51) .. "..."
    end

    local id = mission.def and mission.def.id or "mission"
    return ("%s   |   %d/%d objectives%s"):format(
        id,
        done,
        total,
        nextText and ("   |   next: " .. nextText) or "   |   exit ready"
    )
end

local function campaignStartOnly(entry)
    if not entry then
        return false, "no mission selected"
    end

    if state.autoLoop then
        return false, "stop the contract loop first"
    end

    local boot = Game.boot
    if not (boot and type(boot.quick) == "function") then
        return false, "HITBLOX boot is not ready"
    end

    local mission = currentMission()
    if mission and mission.running then
        if mission.def and mission.def.id == entry.id then
            return true
        end

        state.campaignNote = ("ending %s before %s"):format(
            tostring(mission.def and mission.def.id or "current mission"),
            entry.id
        )
        completeObjectives()
        pcall(function()
            mission:finish(true)
        end)
        task.wait(0.8)
    end

    local ok, err = pcall(boot.quick, entry.id)
    if not ok then
        return false, ("start failed: %s"):format(tostring(err))
    end

    local deadline = os.clock() + 10
    while not state.dead and not Game.running and os.clock() < deadline do
        task.wait(0.1)
    end

    mission = currentMission()
    if not (mission and mission.running) then
        return false, "mission did not start"
    end

    state.campaignNote = ("started %s"):format(entry.id)
    return true
end

local function campaignRunEntry(entry)
    local started, err = campaignStartOnly(entry)
    if not started then
        return false, err
    end

    state.campaignNote = ("completing %s"):format(entry.id)
    completeObjectives()
    task.wait(0.4)

    local mission = currentMission()
    if not (mission and mission.running) then
        return false, "mission ended before finish"
    end

    state.campaignNote = ("finishing %s"):format(entry.id)
    local ok, finishErr = pcall(function()
        mission:finish(true)
    end)
    if not ok then
        return false, ("finish failed: %s"):format(tostring(finishErr))
    end

    autoLoopSyncPayout()
    state.campaignNote = ("%s finished"):format(entry.id)
    return true
end

local function stopCampaignPlay(note)
    state.campaignPlay = false
    campaignToken = campaignToken + 1
    if note then
        state.campaignNote = note
    end
end

stopCampaignFromLoop = function()
    if not state.campaignPlay then
        return
    end

    stopCampaignPlay("stopped for contract loop")
    if campaignPlayToggle then
        pcall(function()
            campaignPlayToggle:Set(false, true)
        end)
    end
end

local function startCampaignPlay()
    if state.campaignPlay or state.dead then
        return
    end

    if state.autoLoop then
        stopAutoLoop("stopped for campaign")
        pcall(function()
            ui.autoLoop:Set(false, true)
        end)
    end

    local boot = Game.boot
    if not (boot and type(boot.quick) == "function") then
        Window:Notify({ title = "Campaign", content = "HITBLOX boot is not ready yet." })
        return
    end

    state.campaignPlay = true
    campaignToken = campaignToken + 1
    local token = campaignToken

    task.spawn(function()
        local handoffDeadline = os.clock() + 12
        while state.autoLoopBusy and not state.dead and os.clock() < handoffDeadline do
            task.wait(0.1)
        end

        local entries = campaignEntries(state.campaignIncludeSide ~= false)
        state.campaignTotal = #entries
        local index = 1

        while state.campaignPlay and not state.dead and token == campaignToken do
            local entry = nil

            while index <= #entries do
                local candidate = entries[index]
                if not (state.campaignSkipDone and campaignDone(candidate.id)) then
                    entry = candidate
                    break
                end
                index = index + 1
            end

            if not entry then
                state.campaignNote = "campaign complete"
                break
            end

            state.campaignIndex = index
            state.campaignCurrent = entry.id
            state.campaignMission = entry.id
            state.campaignNote = ("running %d/%d %s"):format(index, #entries, entry.id)

            local ok, result, err = pcall(campaignRunEntry, entry)
            local succeeded = ok and result ~= false

            if not state.campaignPlay or state.dead or token ~= campaignToken then
                break
            end

            if succeeded then
                index = index + 1
                local delay = math.max(1, tonumber(state.campaignDelay) or 3)
                task.wait(delay)
            else
                state.campaignNote = ("skipped %s: %s"):format(
                    entry.id,
                    tostring(ok and err or result)
                )
                index = index + 1
                task.wait(2)
            end
        end

        if token == campaignToken then
            state.campaignPlay = false
            if state.campaignNote ~= "campaign complete" then
                state.campaignNote = state.campaignNote .. " (stopped)"
            end
            if campaignPlayToggle then
                pcall(function()
                    campaignPlayToggle:Set(false, true)
                end)
            end
        end
    end)
end

local campaignRoadmapText = nil
local campaignSelectedText = nil
local campaignActiveText = nil
local campaignPlayText = nil
local campaignGuideClock = 0
local campaignRoadmapAt = 0

local function campaignRefreshRoadmap()
    if not campaignRoadmapText then
        return
    end

    local text = campaignRoadmap()
    campaignRoadmapAt = os.clock()
    pcall(function()
        campaignRoadmapText:Set(text)
    end)
end

local campaignTab = Window:CreateTab({ name = "Campaign" })

campaignTab:CreateSection({ name = "Roadmap" })

campaignRoadmapText = campaignTab:CreateText({
    name = "Main contracts and side quests",
    text = "Loading campaign...",
})

campaignTab:CreateButton({
    name = "Refresh progress",
    callback = function()
        campaignRefreshRoadmap()
    end,
})

campaignTab:CreateSection({ name = "Run mission" })

local campaignAll = campaignEntries(true)
local campaignOptions = {}
local campaignOptionIds = {}

for index, entry in ipairs(campaignAll) do
    local label = ("%02d %s [%s]"):format(index, entry.id, entry.role)
    campaignOptions[index] = label
    campaignOptionIds[label] = entry.id
end

if not campaignEntryById(state.campaignMission) and campaignAll[1] then
    state.campaignMission = campaignAll[1].id
end

local campaignSelectedLabel = campaignOptions[1]
for index, entry in ipairs(campaignAll) do
    if entry.id == state.campaignMission then
        campaignSelectedLabel = campaignOptions[index]
    end
end

if #campaignOptions > 0 then
    campaignTab:CreateDropdown({
        name = "Campaign mission",
        description = "Campaign order: prequel quests, contracts, finale, sequel quests.",
        options = campaignOptions,
        value = campaignSelectedLabel,
        flag = "hbCampaignMission",
        callback = function(selected)
            state.campaignMission = campaignOptionIds[selected] or selected
        end,
    })
end

campaignSelectedText = campaignTab:CreateText({
    name = "Selected",
    text = "Select a mission.",
})

campaignTab:CreateButton({
    name = "Start selected",
    description = "Starts the selected contract or side quest from its first entry point.",
    callback = function()
        task.spawn(function()
            local entry = campaignEntryById(state.campaignMission)
            local ok, result, err = pcall(campaignStartOnly, entry)
            if ok and result then
                Window:Notify({
                    title = "Campaign",
                    content = ("Started %s."):format(entry.id),
                })
            else
                Window:Notify({
                    title = "Campaign",
                    content = tostring(ok and err or result),
                })
            end
        end)
    end,
})

campaignTab:CreateButton({
    name = "Run selected now",
    description = "Starts the mission, marks its objectives and finishes it in one go.",
    callback = function()
        task.spawn(function()
            local entry = campaignEntryById(state.campaignMission)
            local ok, result, err = pcall(campaignRunEntry, entry)
            if ok and result then
                Window:Notify({
                    title = "Campaign",
                    content = ("%s completed."):format(entry.id),
                })
            else
                Window:Notify({
                    title = "Campaign",
                    content = tostring(ok and err or result),
                })
            end
            campaignRefreshRoadmap()
        end)
    end,
})

campaignTab:CreateButton({
    name = "Complete all objectives",
    callback = function()
        if completeObjectives() then
            Window:Notify({ title = "Objectives", content = "All objectives marked done." })
        end
    end,
})

campaignTab:CreateButton({
    name = "Finish current mission",
    callback = function()
        if finishContract() then
            Window:Notify({ title = "Campaign", content = "Mission finished." })
        end
    end,
})

campaignTab:CreateSection({ name = "Guide" })

ui.campaignGuide = campaignTab:CreateToggle({
    name = "Objective waypoint",
    description = "Shows an in-world beacon on the next objective or living target.",
    value = false,
    flag = "hbCampaignGuide",
    callback = function(value)
        state.campaignGuide = value
        if value then
            state.campaignGuideNote = "waiting for a mission"
        else
            state.campaignGuideNote = "off"
            clearCampaignGuide()
        end
    end,
})

campaignActiveText = campaignTab:CreateText({
    name = "Current objective",
    text = "No mission running.",
})

campaignTab:CreateSection({ name = "Auto-play" })

campaignTab:CreateToggle({
    name = "Skip completed missions",
    description = "Auto-play starts at the first mission that is not marked done.",
    value = true,
    flag = "hbCampaignSkipDone",
    callback = function(value)
        state.campaignSkipDone = value
    end,
})

campaignTab:CreateToggle({
    name = "Include side quests",
    description = "Runs the six prequel/sequel quests alongside the main campaign.",
    value = true,
    flag = "hbCampaignSide",
    callback = function(value)
        state.campaignIncludeSide = value
    end,
})

campaignTab:CreateSlider({
    name = "Mission delay",
    description = "Pause after a finished mission before auto-play loads the next one.",
    range = { 1, 30 },
    increment = 1,
    value = 3,
    suffix = " s",
    flag = "hbCampaignDelay",
    callback = function(value)
        state.campaignDelay = value
    end,
})

campaignPlayText = campaignTab:CreateText({
    name = "Auto-play status",
    text = "off - start from the first unfinished mission",
})

campaignPlayToggle = campaignTab:CreateToggle({
    name = "Auto-play whole campaign",
    description = "Starts every unfinished contract, finale and side quest in campaign order, marks the objectives and finishes each one. Leave Auto collect payout off while this runs.",
    value = false,
    flag = "hbCampaignPlay",
    callback = function(value)
        if value then
            startCampaignPlay()
        else
            stopCampaignPlay("stopped")
        end
    end,
})
ui.campaignPlay = campaignPlayToggle

campaignTab:CreateButton({
    name = "Stop auto-play",
    callback = function()
        stopCampaignPlay("stopped")
        if ui.campaignPlay then
            pcall(function()
                ui.campaignPlay:Set(false, true)
            end)
        end
    end,
})

campaignRefreshRoadmap()

-- Settings --------------------------------------------------------------------

local settingsTab = Window:CreateTab({ name = "Settings" })

local statusClock = 0

local function panic()
    for _, key in ipairs({
        "aimbot", "noSpread", "noRecoil", "infAmmo", "instantReload",
        "esp", "undetectable", "godmode", "autoHideBodies", "autoPayout",
        "autoLoop", "campaignGuide", "campaignPlay", "speedOn", "jumpOn", "noclip",
    }) do
        state[key] = false
        local element = ui[key]
        if element then
            pcall(function()
                element:Set(false, true)
            end)
        end
    end

    stopAutoLoop("panic")
    stopCampaignPlay("panic")
    clearCampaignGuide()
    clearEsp()
    setSpreadZero(false)

    if fovCircle then
        fovCircle.Visible = false
    end
end

local function unload()
    panic()
    state.dead = true
    clearEsp()
    restoreHooks()

    if fovCircle then
        pcall(function()
            fovCircle:Remove()
        end)
        fovCircle = nil
    end

    if getgenv and getgenv().HitBloxHub then
        getgenv().HitBloxHub = nil
    end

    pcall(function()
        Window:Unload()
    end)
end

-- Small read/write handle so a console can inspect or reset the hub without
-- poking at the menu.
if getgenv then
    getgenv().HitBloxHub = {
        version = "1.3.0",
        state = state,
        panic = panic,
        unload = unload,
        esp = function()
            return espRecords
        end,
        equipGun = function()
            local agent = currentAgent()
            local item = agent and equippedGun(agent)
            return item and item.id or nil
        end,
        bodiesHidden = function()
            return bodiesHidden
        end,
        hideBodies = function()
            return hideStep(0, true)
        end,
        payout = function()
            return collectPayout(true)
        end,
        payoutReadyIn = payoutReadyIn,
        startLoop = function()
            startAutoLoop()
        end,
        stopLoop = function()
            stopAutoLoop("stopped")
        end,
        runContract = function()
            return autoLoopOnce(true)
        end,
        campaign = function()
            local out = {}
            for index, entry in ipairs(campaignEntries(true)) do
                local record = campaignRecord(entry.id)
                table.insert(out, {
                    index = index,
                    id = entry.id,
                    role = entry.role,
                    act = entry.act,
                    done = record ~= nil and record.done == true,
                    stars = record and record.stars or 0,
                    plays = record and record.plays or 0,
                })
            end
            return out
        end,
        campaignStatus = function()
            return {
                playing = state.campaignPlay,
                index = state.campaignIndex,
                total = state.campaignTotal,
                current = state.campaignCurrent,
                note = state.campaignNote,
                guide = state.campaignGuide,
                guideNote = state.campaignGuideNote,
            }
        end,
        startCampaign = function()
            startCampaignPlay()
        end,
        stopCampaign = function()
            stopCampaignPlay("stopped")
        end,
        startMission = function(id)
            return campaignStartOnly(campaignEntryById(id))
        end,
        runMission = function(id)
            return campaignRunEntry(campaignEntryById(id))
        end,
        refreshCampaign = function()
            campaignRefreshRoadmap()
            return campaignRoadmap()
        end,
    }
end

settingsTab:CreateKeybind({
    name = "Panic key",
    value = Enum.KeyCode.RightControl,
    callback = function()
        panic()
    end,
})

settingsTab:CreateButton({
    name = "Panic (disable everything)",
    callback = function()
        panic()
        Window:Notify({ title = "Panic", content = "All features disabled." })
    end,
})

settingsTab:CreateButton({
    name = "Unload script",
    callback = function()
        unload()
    end,
})

-- Status ticker ---------------------------------------------------------------

RunService.Heartbeat:Connect(function(dt)
    if state.dead then
        return
    end

    campaignGuideClock = campaignGuideClock + dt
    if campaignGuideClock >= 0.15 then
        campaignGuideClock = 0
        pcall(campaignGuideStep)
    end

    statusClock = statusClock + dt
    if statusClock < 0.5 then
        return
    end
    statusClock = 0

    local agent = currentAgent()
    local mission = currentMission()
    local alive = 0
    local targets = 0

    for _, npc in ipairs(NPC.all) do
        if npc.alive then
            alive = alive + 1
            if npc.isTarget then
                targets = targets + 1
            end
        end
    end

    local parts = {}
    if agent and agent.alive then
        table.insert(parts, ("HP %d"):format(math.max(0, math.floor(agent.hp or 0))))
        local item = agent:current()
        if item then
            table.insert(parts, ("%s %d/%d"):format(
                item.label or item.id or "?",
                item.mag or 0,
                item.spare or 0
            ))
        end
    else
        table.insert(parts, "No agent")
    end

    table.insert(parts, ("NPCs %d"):format(alive))
    if targets > 0 then
        table.insert(parts, ("Targets %d"):format(targets))
    end
    if bodiesHidden > 0 then
        table.insert(parts, ("Hidden %d"):format(bodiesHidden))
    end
    if mission and mission.running then
        table.insert(parts, ("Contract %.0fs"):format(mission:elapsed()))
    end

    pcall(function()
        statusText:Set(table.concat(parts, "   |   "))
    end)

    if loopText then
        local nextIn = math.max(0, state.autoLoopNextAt - os.clock())
        local suffix = ""
        if state.autoLoop and nextIn > 0 then
            suffix = ("   |   next %d s"):format(math.ceil(nextIn))
        end
        pcall(function()
            loopText:Set(("loop %s   |   %s   |   cycles %d%s"):format(
                state.autoLoop and "ON" or "off",
                state.autoLoopNote,
                state.autoLoopCycles,
                suffix
            ))
        end)
    end

    if payoutText then
        local left = payoutReadyIn()
        local nextText
        if state.payoutBusy then
            nextText = "calling"
        elseif left > 0 then
            nextText = ("%d s"):format(math.ceil(left))
        else
            nextText = "ready"
        end

        pcall(function()
            payoutText:Set(("next %s   |   last %s   |   total $%d (%d)"):format(
                nextText,
                state.payoutNote,
                state.payoutTotal,
                state.payoutCount
            ))
        end)
    end

    if campaignSelectedText then
        local entry = campaignEntryById(state.campaignMission)
        if entry then
            pcall(function()
                campaignSelectedText:Set(("selected %s   |   %s   |   %s   |   %s"):format(
                    entry.id,
                    entry.def.title or "",
                    entry.role,
                    campaignStatus(entry.id)
                ))
            end)
        end
    end

    if campaignActiveText then
        pcall(function()
            campaignActiveText:Set(("%s   |   guide %s (%s)"):format(
                campaignObjectiveSummary(),
                state.campaignGuide and "ON" or "off",
                state.campaignGuideNote
            ))
        end)
    end

    if campaignPlayText then
        local progress = state.campaignTotal > 0
            and ("%d/%d"):format(state.campaignIndex, state.campaignTotal)
            or "-/-"
        pcall(function()
            campaignPlayText:Set(("auto-play %s   |   %s   |   current %s   |   %s"):format(
                state.campaignPlay and "ON" or "off",
                progress,
                state.campaignCurrent or "-",
                state.campaignNote
            ))
        end)
    end

    if campaignRoadmapText and os.clock() - campaignRoadmapAt >= 3 then
        campaignRefreshRoadmap()
    end

    if state.autoPayout and not state.autoLoop and not state.campaignPlay
        and not state.payoutBusy and payoutReadyIn() <= 0
        and not (mission and mission.running) then
        collectPayout(false)
    end
end)

Window:Notify({
    title = "HitBlox loaded",
    content = "Combat, visuals, stealth, contract and campaign tools are ready.",
})

return true
