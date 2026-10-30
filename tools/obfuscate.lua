-- allison-obf v1 -- custom Lua/Luau obfuscator
-- usage: lua obfuscate.lua <input.lua> [output.lua]
--
-- Layers (all custom, all reversible by a determined reader -- this only
-- raises the cost of reading, it cannot make reversing impossible):
--   1. comment strip (keeps a leading --!strict line)
--   2. local renamer (___ + Il1 alphabet, declaration-driven, member-safe)
--   3. per-string caesar crypt (decimal escapes, runtime decoder)
--   4. integer split (N -> (N+K)-K)
--   5. dead-code junk (never-executed if-false blocks)
-- Limits: no [[ ]] long strings, don't name locals the same as table
-- keys you index with dot, input must already run where output will run
-- (Luau type annotations are passed through untouched).

local function readAll(p)
	local f = assert(io.open(p, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

local function writeAll(p, s)
	local f = assert(io.open(p, "wb"))
	f:write(s)
	f:close()
end

local inPath = ...
if not inPath then
	print("usage: lua obfuscate.lua <input.lua> [output.lua]")
	os.exit(1)
end
local outPath = select(2, ...) or (inPath .. ".obf.lua")

math.randomseed(os.time() + #inPath)

local CS1, CS2 = string.char(1), string.char(2)

local src = readAll(inPath)
src = src:gsub("\r\n", "\n")

local strict = src:match("^%-%-!strict[^\n]*\n") or ""

-- 1. stash string literals with a hand scanner (no quantified groups).
local bank = {}
local function stashAll(s)
	local out, i, n = {}, 1, #s
	while i <= n do
		local c = s:sub(i, i)
		if c == '"' or c == "'" then
			local j, buf = i + 1, {}
			local closed = false
			while j <= n do
				local d = s:sub(j, j)
				if d == "\\" then
					if j >= n then
						break
					end
					buf[#buf + 1] = d .. s:sub(j + 1, j + 1)
					j = j + 2
				elseif d == c then
					closed = true
					break
				elseif d == "\n" then
					break
				else
					buf[#buf + 1] = d
					j = j + 1
				end
			end
			if closed then
				bank[#bank + 1] = table.concat(buf)
				out[#out + 1] = CS1 .. string.rep("~", #bank) .. CS2
				i = j + 1
			else
				out[#out + 1] = c
				i = i + 1
			end
		else
			out[#out + 1] = c
			i = i + 1
		end
	end
	return table.concat(out)
end
src = stashAll(src)

-- 2. strip comments.
src = src:gsub("%-%-%[%[.-%]%]", "")
src = src:gsub("%-%-[^\n]*", "")

-- 3. integer split (padded so start-of-string matches; skips floats/hex/members).
src = " " .. src
local ints = 0
src = src:gsub("([^%w_%.:])(%d+)(%f[^%w%.])", function(pre, n)
	local k = math.random(1, 200)
	ints = ints + 1
	return pre .. "(" .. (tonumber(n) + k) .. "-" .. k .. ")"
end)
src = src:sub(2)

-- 4. collect declared locals, then rename (never touches .member / :method).
local kw = {
	["local"] = 1, ["function"] = 1, ["for"] = 1, ["in"] = 1, ["if"] = 1,
	["then"] = 1, ["else"] = 1, ["elseif"] = 1, ["end"] = 1, ["do"] = 1,
	["while"] = 1, ["repeat"] = 1, ["until"] = 1, ["return"] = 1,
	["break"] = 1, ["true"] = 1, ["false"] = 1, ["nil"] = 1,
	["and"] = 1, ["or"] = 1, ["not"] = 1,
}
local declared, order = {}, {}
local function add(n)
	if n and n ~= "_" and n ~= "_G" and not kw[n] and not declared[n] then
		declared[n] = true
		order[#order + 1] = n
	end
end
for n in src:gmatch("local%s+function%s+([A-Za-z_][%w_]*)") do add(n) end
for n in src:gmatch("local%s+([A-Za-z_][%w_]*)") do add(n) end
for n in src:gmatch("for%s+([A-Za-z_][%w_]*)%s*=") do add(n) end
for a, b in src:gmatch("for%s+([A-Za-z_][%w_]*)%s*,%s*([A-Za-z_][%w_]*)%s+in") do
	add(a)
	add(b)
end
for ps in src:gmatch("function[^%(]*%(([^)]*)%)") do
	for pm in (ps .. ","):gmatch("([^,]+),") do
		add(pm:match("^%s*([A-Za-z_][%w_]*)"))
	end
end

local alpha = { "I", "l", "1" }
local function fresh()
	local n
	repeat
		n = "___"
		for _ = 1, 6 do
			n = n .. alpha[math.random(1, 3)]
		end
	until not src:find(n, 1, true)
	return n
end
local map = {}
for _, n in ipairs(order) do
	map[n] = fresh()
end
src = " " .. src .. " "
for _, n in ipairs(order) do
	local r = map[n]
	src = src:gsub("([^%.:%w_])" .. n .. "(%f[^%w_])", "%1" .. r .. "%2")
end
src = src:sub(2, -2)

-- 5. runtime decoder first (fresh names can't collide: checked above),
-- then restore every string encrypted, then dead-code junk.
local dec = fresh()
local head = {}
head[#head + 1] = "local " .. dec .. "=function(s,k) local t={} for i=1,#s do t[i]=string.char((string.byte(s,i)-k)%256) end return table.concat(t) end"

local strs = 0
src = src:gsub(CS1 .. "(~+)" .. CS2, function(t)
	local raw = bank[#t]
	if raw == nil then
		error("obfuscator: placeholder without bank entry")
	end
	local k = math.random(1, 250)
	local enc = {}
	for i = 1, #raw do
		enc[#enc + 1] = "\\" .. ((string.byte(raw, i) + k) % 256)
	end
	strs = strs + 1
	return dec .. '("' .. table.concat(enc) .. '",' .. k .. ")"
end)

for _ = 1, 3 do
	local j = fresh()
	head[#head + 1] = "if false then local " .. j .. "=(" .. math.random(2, 9) .. "*" .. math.random(11, 99) .. ") end"
end

local out = strict
	.. "-- obfuscated with allison-obf v1 | locals:" .. #order .. " strings:" .. strs .. " ints:" .. ints .. "\n"
	.. table.concat(head, "\n")
	.. "\n"
	.. src
writeAll(outPath, out)
print("wrote " .. outPath .. " locals=" .. #order .. " strings=" .. strs .. " ints=" .. ints)
