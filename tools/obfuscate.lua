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

local args = { ... }
local envelope = true
if args[1] == "--raw" then
	envelope = false
	table.remove(args, 1)
end
local inPath = args[1]
if not inPath then
	print("usage: lua obfuscate.lua [--raw] <input.lua> [output.lua]")
	os.exit(1)
end
local outPath = args[2] or (inPath .. ".obf.lua")

math.randomseed(os.time() + #inPath)

local CS1, CS2 = string.char(1), string.char(2)

local src = readAll(inPath)
src = src:gsub("\r\n", "\n")

local strict = src:match("^%-%-!strict[^\n]*\n") or ""

local bank = {}
local escmap = {
	n = "\n", t = "\t", r = "\r", a = "\a", b = "\b", f = "\f", v = "\v",
	["\\"] = "\\", ['"'] = '"', ["'"] = "'",
}
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
					local e = s:sub(j + 1, j + 1)
					if e == "\n" then
						j = j + 2
					elseif escmap[e] then
						buf[#buf + 1] = escmap[e]
						j = j + 2
					elseif e:match("%d") then
						local k = j + 1
						while k <= j + 3 and s:sub(k, k):match("%d") do
							k = k + 1
						end
						buf[#buf + 1] = string.char(tonumber(s:sub(j + 1, k - 1), 10) % 256)
						j = k
					else
						buf[#buf + 1] = e
						j = j + 2
					end
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

src = src:gsub("%-%-%[%[.-%]%]", "")
src = src:gsub("%-%-[^\n]*", "")

src = " " .. src
local ints = 0
src = src:gsub("([^%w_%.:])(%d+)(%f[^%w%.])", function(pre, n)
	local k = math.random(1, 200)
	ints = ints + 1
	return pre .. "(" .. (tonumber(n) + k) .. "-" .. k .. ")"
end)
src = src:sub(2)

local kw = {
	["local"] = true, ["function"] = true, ["for"] = true, ["in"] = true,
	["if"] = true, ["then"] = true, ["else"] = true, ["elseif"] = true,
	["end"] = true, ["do"] = true, ["while"] = true, ["repeat"] = true,
	["until"] = true, ["return"] = true, ["break"] = true, ["true"] = true,
	["false"] = true, ["nil"] = true, ["and"] = true, ["or"] = true,
	["not"] = true,
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

local function esc3(b)
	return string.format("\\%03d", b)
end

local head = {}
local strs = 0
if not envelope then
	local dec = fresh()
	head[#head + 1] = "local " .. dec .. "=function(s,k) local t={} for i=1,#s do t[i]=string.char((string.byte(s,i)-k)%256) end return table.concat(t) end"
	src = src:gsub(CS1 .. "(~+)" .. CS2, function(t)
		local raw = bank[#t]
		if raw == nil then
			error("obfuscator: placeholder without matching bank entry")
		end
		local k = math.random(1, 250)
		local enc = {}
		for i = 1, #raw do
			enc[#enc + 1] = esc3((string.byte(raw, i) + k) % 256)
		end
		strs = strs + 1
		return dec .. '("' .. table.concat(enc) .. '",' .. k .. ")"
	end)
end

for _ = 1, 3 do
	local j = fresh()
	head[#head + 1] = "if false then local " .. j .. "=(" .. math.random(2, 9) .. "*" .. math.random(11, 99) .. ") end"
end

if envelope then
	for i = 1, #bank do
		strs = strs + 1
	end
	local function reliteral(s)
		local o = {}
		for i = 1, #s do
			local b = string.byte(s, i)
			if b == 34 then
				o[#o + 1] = '\\"'
			elseif b == 92 then
				o[#o + 1] = "\\\\"
			elseif b < 32 or b > 126 then
				o[#o + 1] = string.format("\\%03d", b)
			else
				o[#o + 1] = string.char(b)
			end
		end
		return '"' .. table.concat(o) .. '"'
	end
	src = src:gsub(CS1 .. "(~+)" .. CS2, function(t)
		local e = bank[#t]
		if e == nil then
			error("obfuscator: placeholder without matching bank entry")
		end
		return reliteral(e)
	end)
	local inner = strict .. table.concat(head, "\n") .. "\n" .. src
	local k0 = math.random(1, 250)
	local step = math.random(1, 100)
	local kx = math.random(200, 2000)
	local sx = math.random(200, 2000)
	local sum = 0
	for i = 1, #inner do
		sum = (sum + string.byte(inner, i)) % 4294967296
	end
	local nk, ns, nd, nt, nc, nh, nl = fresh(), fresh(), fresh(), fresh(), fresh(), fresh(), fresh()
	local chunks, CH = {}, 4000
	for i = 1, #inner, CH do
		local part = {}
		local stop = math.min(i + CH - 1, #inner)
		for j = i, stop do
			part[#part + 1] = esc3((string.byte(inner, j) + k0 + j * step) % 256)
		end
		chunks[#chunks + 1] = '"' .. table.concat(part) .. '"'
	end
	local out = "-- obfuscated with allison-obf v2 (envelope) | locals:" .. #order .. " strings:" .. strs .. " ints:" .. ints .. "\n"
		.. "local " .. nk .. "=(" .. (k0 + kx) .. "-" .. kx .. ")\n"
		.. "local " .. ns .. "=(" .. (step + sx) .. "-" .. sx .. ")\n"
		.. "local " .. nd .. "=" .. table.concat(chunks, "..") .. "\n"
		.. "local " .. nt .. "={} for " .. nl .. "=1,#" .. nd .. " do " .. nt .. "[" .. nl .. "]=string.char((string.byte(" .. nd .. "," .. nl .. ")-" .. nk .. "-" .. nl .. "*" .. ns .. ")%256) end\n"
		.. "local " .. nc .. "=table.concat(" .. nt .. ")\n"
		.. "if #" .. nc .. "~=" .. #inner .. " then error(\"bad payload\") end\n"
		.. "local " .. nh .. "=0 for " .. nl .. "=1,#" .. nc .. " do " .. nh .. "=(" .. nh .. "+string.byte(" .. nc .. "," .. nl .. "))%4294967296 end\n"
		.. "if " .. nh .. "~=" .. sum .. " then error(\"bad payload\") end\n"
		.. "assert((loadstring or load)(" .. nc .. "))()"
	writeAll(outPath, out)
	print("wrote " .. outPath .. " mode=envelope locals=" .. #order .. " strings=" .. strs .. " ints=" .. ints .. " bytes=" .. #inner)
else
	local out = strict
		.. "-- obfuscated with allison-obf v1 | locals:" .. #order .. " strings:" .. strs .. " ints:" .. ints .. "\n"
		.. table.concat(head, "\n")
		.. "\n"
		.. src
	writeAll(outPath, out)
	print("wrote " .. outPath .. " mode=raw locals=" .. #order .. " strings=" .. strs .. " ints=" .. ints)
end
