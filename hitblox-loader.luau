--[[
    SLIMHUB - HITBLOX loader

    Paste this one line, anywhere, forever:

        loadstring(game:HttpGet("https://raw.githubusercontent.com/yougyougo017-png/rugball/main/hitblox-loader.luau"))()

    It fetches the current HITBLOX panel with a cache-buster appended, so an
    update is just "upload hitblox-hub.luau" - this URL never changes. If the
    fetch or compile fails you get one readable line instead of a silent
    nothing.
]]

-- upload-hitblox.py replaces https://raw.githubusercontent.com/yougyougo017-png/rugball/main/ with the token account's raw
-- base URL before upload, so the published loader always points at the repo
-- that actually received the files. Do not paste this local template directly.
local BASE = "https://raw.githubusercontent.com/yougyougo017-png/rugball/main/"
local HUB = BASE .. "hitblox-hub.luau"

local function banner(text)
    print("[SLIMHUB/HITBLOX] " .. text)
end

-- Auto-exec can start before ReplicatedStorage.Hitblox replicates. Wait for
-- the place to load, then give the game a beat before checking for the folder.
if not game:IsLoaded() then
    local okLoad = pcall(function()
        game.Loaded:Wait()
    end)
    if not okLoad then
        while not game:IsLoaded() do
            task.wait(0.2)
        end
    end
    task.wait(1.5)
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local waited = 0
while not ReplicatedStorage:FindFirstChild("Hitblox") and waited < 30 do
    task.wait(0.5)
    waited = waited + 0.5
end

if not ReplicatedStorage:FindFirstChild("Hitblox") then
    warn("[SLIMHUB/HITBLOX] ReplicatedStorage.Hitblox never appeared - is this the right game?")
    return
end

local function fetch(url, tries)
    local lastErr
    for attempt = 1, (tries or 3) do
        local ok, body = pcall(function()
            return game:HttpGet(
                url
                    .. (url:find("?") and "&" or "?")
                    .. "v="
                    .. tostring(os.time())
                    .. tostring(attempt)
            )
        end)
        if ok and type(body) == "string" and #body > 1000 then
            return body
        end
        lastErr = body
        task.wait(0.4 * attempt)
    end
    return nil, lastErr
end

banner("fetching panel")
local src, err = fetch(HUB, 3)

if not src then
    warn("[SLIMHUB/HITBLOX] download failed - " .. tostring(err))
    warn("[SLIMHUB/HITBLOX] raw url: " .. HUB)
    return
end

-- A host that saves with a BOM breaks the first line.
if src:sub(1, 3) == "\239\187\191" then
    src = src:sub(4)
end

local chunk, compileErr = loadstring(src, "hitblox-hub")
if not chunk then
    warn("[SLIMHUB/HITBLOX] compile failed - " .. tostring(compileErr))
    warn("[SLIMHUB/HITBLOX] the uploaded file is probably truncated; re-upload the hub")
    return
end

banner(string.format("running %d bytes (place %d)", #src, game.PlaceId))

local ran, runErr = pcall(chunk)
if not ran then
    warn("[SLIMHUB/HITBLOX] runtime error - " .. tostring(runErr))
end
