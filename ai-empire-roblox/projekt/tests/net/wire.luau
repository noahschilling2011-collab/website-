--!nocheck
-- Test helpers for the net package.
-- wire(v): what a RemoteEvent delivers: a deep copy (the receiver never shares tables with the
--   sender). Also records every table Roblox could not transmit faithfully: dictionaries with
--   non-string keys and arrays with holes or extra keys (Roblox drops/mangles those).
-- equal(a, b, skip): deep equality; returns nil or the first differing path. skip = lazy spec
--   (StatePatch.Lazy shape) of keys to ignore.
local W = {}

W.problems = {}

local function wire(v, path)
	if type(v) ~= "table" then
		if type(v) == "function" or type(v) == "thread" then table.insert(W.problems, path .. ": " .. type(v)) end
		return v
	end
	local n = #v
	local out = {}
	if n > 0 then
		local count = 0
		for k in v do count += 1 end
		if count ~= n then table.insert(W.problems, path .. ": mixed/holey array (" .. count .. " keys, #=" .. n .. ")") end
		for i = 1, n do out[i] = wire(v[i], path .. "[" .. i .. "]") end
		return out
	end
	for k, x in v do
		if type(k) ~= "string" then table.insert(W.problems, path .. ": non-string key " .. tostring(k)) end
		out[k] = wire(x, path .. "." .. tostring(k))
	end
	return out
end
function W.wire(v) return wire(v, "") end

local function equal(a, b, path, skip)
	if type(a) ~= "table" or type(b) ~= "table" then
		if a == b or (a ~= a and b ~= b) then return nil end
		return path .. " (" .. tostring(a) .. " vs " .. tostring(b) .. ")"
	end
	local any = if skip then skip["*"] else nil
	for k, x in a do
		local sk = if skip then (skip[k] or any) else nil
		if sk ~= true then
			local d = equal(x, b[k], path .. "." .. tostring(k), if type(sk) == "table" then sk else nil)
			if d then return d end
		end
	end
	for k, x in b do
		if a[k] == nil then
			local sk = if skip then (skip[k] or any) else nil
			if sk ~= true then return path .. "." .. tostring(k) .. " (missing left)" end
		end
	end
	return nil
end
function W.equal(a, b, skip) return equal(a, b, "", skip) end

-- does the patch touch this path? (path = { "data", "empire", "staffProfiles" })
function W.touches(patch, path)
	local node = patch
	for i, key in path do
		if type(node) ~= "table" then return false end
		if node.s and node.s[key] ~= nil then return true end
		if node.d then for _, k in node.d do if k == key then return true end end end
		local nxt = node.p and node.p[key]
		if nxt == nil then return false end
		node = nxt
		if i == #path then return true end
	end
	return false
end

return W
