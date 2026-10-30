--!strict
-- Allison Lua loader | private repo jatosm/loader
--
-- Executor usage (repo is private, so the FIRST fetch needs a token):
--   loadstring(game:HttpGet("https://<TOKEN>@raw.githubusercontent.com/jatosm/loader/main/loader.lua"))()
-- Use a fine-grained PAT with contents:read on jatosm/loader only.
-- For later fetches you can set it once instead:
--   _G.ALLISON_TOKEN = "github_pat_..."
--
-- What it does:
--   1. Downloads smallest-pixel-7.ttf (public URL, no auth needed),
--      caches it via writefile, exposes Font via _G.ALLISON_FONT.
--   2. Downloads CONFIG.PayloadPath raw from this repo and runs it.

local CONFIG = {
	Repo = "jatosm/loader",
	Branch = "main",
	PayloadPath = "menu.lua", -- push your main script under this path, or change it here
	FontUrl = "https://raw.githubusercontent.com/britzl/gbrausers/master/assets/font/smallest_pixel-7.ttf",
	FontFile = "smallest-pixel-7.ttf",
	Timeout = 6,
}

local G: any = _G
local shared: any = (type(G.getgenv) == "function" and G.getgenv()) or G
local TOKEN = shared.ALLISON_TOKEN
if type(TOKEN) ~= "string" or TOKEN == "" then
	TOKEN = nil
end

local synTbl = G.syn
local httpTbl = G.http
local fluxusTbl = G.fluxus
local httpRequest = (synTbl and synTbl.request)
	or (httpTbl and httpTbl.request)
	or G.http_request
	or (fluxusTbl and fluxusTbl.request)
	or G.request

local function fetch(url: string, useAuth: boolean): string
	if type(httpRequest) == "function" then
		local opts: any = { Url = url, Method = "GET", Timeout = CONFIG.Timeout }
		if useAuth and TOKEN then
			opts.Headers = { Authorization = "token " .. TOKEN }
		end
		local response = httpRequest(opts)
		if type(response) == "string" then
			return response
		end
		if type(response) ~= "table" then
			error("executor request returned no response table", 0)
		end
		local status = tonumber(response.StatusCode or response.Status or response.status_code)
		if status and (status < 200 or status >= 300) then
			error("HTTP " .. tostring(status) .. " for " .. url, 0)
		end
		local body = response.Body or response.body
		if type(body) ~= "string" then
			error("executor request returned no body for " .. url, 0)
		end
		return body
	end
	-- game:HttpGet sends no headers, so private files 404 here.
	return game:HttpGet(url)
end

local function rawUrl(path: string): string
	return "https://raw.githubusercontent.com/" .. CONFIG.Repo .. "/" .. CONFIG.Branch .. "/" .. path
end

print("[Allison] loader start; repo=" .. CONFIG.Repo)

-- 1. Font (public URL, no auth needed).
local fontAsset: string? = nil
do
	local isfileFn = G.isfile
	local writefileFn = G.writefile
	local getcustomassetFn = G.getcustomasset
	local cached = type(isfileFn) == "function" and isfileFn(CONFIG.FontFile)
	print("[Allison] font cached=" .. tostring(cached == true))
	if not cached then
		if type(writefileFn) ~= "function" then
			warn("[Allison] writefile missing, skipping font download")
		else
			local ok, body = pcall(fetch, CONFIG.FontUrl, false)
			if ok and type(body) == "string" and #body > 1000 then
				print("[Allison] font downloaded bytes=" .. tostring(#body))
				pcall(writefileFn, CONFIG.FontFile, body)
			else
				warn("[Allison] font download failed: " .. tostring(body))
			end
		end
	end
	if type(getcustomassetFn) == "function" then
		local okAsset, asset = pcall(getcustomassetFn, CONFIG.FontFile)
		if okAsset and type(asset) == "string" then
			fontAsset = asset
			local okFont, f = pcall(Font.new, asset, Enum.FontWeight.Regular)
			if okFont and typeof(f) == "Font" then
				shared.ALLISON_FONT = f
				print("[Allison] custom font ready for HOME/Aimbot/Visuals/Misc")
			else
				warn("[Allison] Font.new failed: " .. tostring(f))
			end
		else
			warn("[Allison] getcustomasset failed: " .. tostring(asset))
		end
	else
		warn("[Allison] getcustomasset missing (non-executor?), font unavailable")
	end
end

-- 2. Payload: download raw and run it.
if CONFIG.PayloadPath == "" then
	warn("[Allison] no PayloadPath set, nothing to run")
else
	local url = rawUrl(CONFIG.PayloadPath)
	print("[Allison] fetching payload: " .. CONFIG.PayloadPath)
	local ok, body = pcall(fetch, url, true)
	if not ok or type(body) ~= "string" or #body < 10 then
		warn("[Allison] payload download failed (private repo needs _G.ALLISON_TOKEN or token in URL): " .. tostring(body))
	else
		local fn, loadErr = loadstring(body)
		if type(fn) ~= "function" then
			warn("[Allison] loadstring failed: " .. tostring(loadErr))
		else
			print("[Allison] running payload (" .. tostring(#body) .. " bytes)")
			local okRun, runErr = pcall(fn)
			if not okRun then
				warn("[Allison] payload error: " .. tostring(runErr))
			else
				print("[Allison] payload finished")
			end
		end
	end
end

return {
	Font = shared.ALLISON_FONT,
	FontAsset = fontAsset,
}
