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
