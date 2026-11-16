--[[
	SLIMHUB - permanent loader

	Paste this one line, anywhere, forever:

		loadstring(game:HttpGet("https://raw.githubusercontent.com/yougyougo017-png/rugball/main/slimhub-loader.luau"))()

	It fetches the current hub with a cache-buster appended, so an update is
	just "upload the new hub" - nobody re-copies a script, and the CDN cannot
	hand back yesterday's file. If the fetch or the compile fails you get one
	readable line instead of a silent nothing.
]]

local BASE = "https://raw.githubusercontent.com/yougyougo017-png/rugball/main/"
local HUB = BASE .. "rugball-mega-hub-v2.luau"

local function banner(text)
	print("[SLIMHUB] " .. text)
end

-- the panel arms one loader per server, but a double-loaded hub can queue two.
-- the queued copy carries SLIMHUB_AUTOEXEC, so this stamp only ever suppresses
-- duplicate auto-exec runs - a manual execute still reloads the hub on demand.
local genv = (getgenv and getgenv()) or _G
if genv.SLIMHUB_AUTOEXEC then
	genv.SLIMHUB_AUTOEXEC = nil
	if genv.SLIMHUB_SERVED == game.JobId then
		banner("already served this server - skipped")
		return
	end
	genv.SLIMHUB_SERVED = game.JobId
end

local function fetch(url, tries)
	local lastErr
	for attempt = 1, (tries or 3) do
		local ok, body = pcall(function()
			return game:HttpGet(url .. (url:find("?") and "&" or "?") .. "v=" .. tostring(os.time()) .. tostring(attempt))
		end)
		if ok and type(body) == "string" and #body > 1000 then
			return body
		end
		lastErr = body
		task.wait(0.4 * attempt)
	end
	return nil, lastErr
end

-- auto-exec runs the instant the join starts, when half the game has not
-- replicated yet. wait for the load, then a beat, so the suites see a real
-- ReplicatedStorage instead of bailing on the first FindFirstChild.
if not game:IsLoaded() then
	local okLoad = pcall(function() game.Loaded:Wait() end)
	if not okLoad then
		while not game:IsLoaded() do task.wait(0.2) end
	end
	task.wait(1.5)
end

banner("fetching hub")
local src, err = fetch(HUB, 3)

if not src then
	warn("[SLIMHUB] download failed - " .. tostring(err))
	warn("[SLIMHUB] open the raw url in a browser to check it is still up: " .. HUB)
	return
end

-- a host that saves with a BOM breaks the first line
if src:sub(1, 3) == "\239\187\191" then
	src = src:sub(4)
end

local chunk, compileErr = loadstring(src, "rugball-mega-hub-v2")
if not chunk then
	warn("[SLIMHUB] compile failed - " .. tostring(compileErr))
	warn("[SLIMHUB] the uploaded file is probably truncated; re-upload the hub")
	return
end

banner(string.format("running %d bytes (place %d)", #src, game.PlaceId))

local ran, runErr = pcall(chunk)
if not ran then
	warn("[SLIMHUB] runtime error - " .. tostring(runErr))
end
