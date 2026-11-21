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

-- Settings --------------------------------------------------------------------

local settingsTab = Window:CreateTab({ name = "Settings" })

local statusClock = 0

local function panic()
    for _, key in ipairs({
        "aimbot", "noSpread", "noRecoil", "infAmmo", "instantReload",
        "esp", "undetectable", "godmode", "autoHideBodies", "autoPayout",
        "speedOn", "jumpOn", "noclip",
    }) do
        state[key] = false
        local element = ui[key]
        if element then
            pcall(function()
                element:Set(false, true)
            end)
        end
    end

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
        version = "1.2.1",
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

    if state.autoPayout and not state.payoutBusy and payoutReadyIn() <= 0
        and not (mission and mission.running) then
        collectPayout(false)
    end
end)

Window:Notify({
    title = "HitBlox loaded",
    content = "Combat, visuals, stealth and contract tools are ready.",
})

return true
