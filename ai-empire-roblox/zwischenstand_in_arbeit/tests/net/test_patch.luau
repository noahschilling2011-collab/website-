--!nocheck
-- Net package: StatePatch (delta encoding of State snapshots) — unit cases + randomized round trips.
-- Pure Luau (no mock): the module has no Roblox dependencies.
-- Run: tools/luau tests/net/test_patch.luau
local args = { ... }
-- optional: -a <path to another StatePatch build> (used for the negative check in tests/net/negative.sh)
local P = require(args[1] or "../../work/src/ReplicatedStorage/Shared/StatePatch.module")
local W = require("./wire")
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

-- server side: shadow + diff; client side: apply onto its copy (through a simulated remote)
local function stream(initial)
	local st = { cur = initial, shadow = P.copy(initial), client = W.wire(initial) }
	function st.step(lazy)
		local patch = P.diff(st.shadow, st.cur, lazy)
		if patch then st.client = P.apply(st.client, W.wire(patch)) end
		return patch
	end
	return st
end

local function body()
	-- identical -> nil
	local st = stream({ a = 1, b = { c = "x", d = { 1, 2, 3 } } })
	check("unchanged -> nil", st.step() == nil)
	-- scalar change
	st.cur.a = 2
	local p = st.step()
	check("scalar set", p and p.s and p.s.a == 2 and p.p == nil, p)
	check("scalar applied", W.equal(st.client, st.cur) == nil)
	check("shadow updated", st.step() == nil)
	-- nested change
	st.cur.b.c = "y"
	p = st.step()
	check("nested change uses p", p and p.p and p.p.b and p.p.b.s and p.p.b.s.c == "y" and p.s == nil)
	check("nested applied", W.equal(st.client, st.cur) == nil)
	-- deletion
	st.cur.a = nil
	p = st.step()
	check("deletion listed", p and p.d and p.d[1] == "a")
	check("deletion applied", st.client.a == nil and W.equal(st.client, st.cur) == nil)
	-- array append / truncate
	table.insert(st.cur.b.d, 4)
	p = st.step()
	check("array append: n + one index", p and p.p.b.p.d.n == 4 and p.p.b.p.d.s["4"] == 4)
	check("array append applied", #st.client.b.d == 4 and W.equal(st.client, st.cur) == nil)
	st.cur.b.d[4] = nil; st.cur.b.d[3] = nil
	p = st.step()
	check("array truncate: only n", p and p.p.b.p.d.n == 2 and p.p.b.p.d.s == nil)
	check("array truncate applied", #st.client.b.d == 2 and st.client.b.d[3] == nil)
	-- arrays of records: one field per element changes -> per-index nested patches
	local rows = {}
	for i = 1, 20 do rows[i] = { id = "r" .. i, name = "Row " .. i, users = i * 10, price = 5 } end
	st = stream({ list = rows })
	for i = 1, 20 do rows[i].users += 1 end
	p = st.step()
	check("few fields per element stay nested", p and p.p.list.p ~= nil and p.p.list.s == nil, p and p.p.list.s and "whole")
	check("nested rows applied", W.equal(st.client, st.cur) == nil)
	-- a shifted log (insert at the front) is sent whole
	table.insert(rows, 1, { id = "r0", name = "Row 0", users = 0, price = 1 })
	table.remove(rows)
	p = st.step()
	check("shifted log sent whole", p and p.p == nil and p.s and p.s.list ~= nil)
	check("shifted log applied", W.equal(st.client, st.cur) == nil)
	-- kind changes
	st = stream({ t = { 1, 2 }, u = { x = 1 }, v = 5, w = {}, z = { 1 } })
	st.cur.t = { x = 1 }; st.cur.u = { 7, 8 }; st.cur.v = { k = true }; st.cur.w = { 3 }; st.cur.z = {}
	st.step()
	check("array->dict, dict->array, scalar->table, empty->array, array->empty", W.equal(st.client, st.cur) == nil, W.equal(st.client, st.cur))
	st.cur.v = "s"; st.cur.u = false
	st.step()
	check("table->scalar", W.equal(st.client, st.cur) == nil)
	-- NaN stays NaN without resending
	st = stream({ x = 0 / 0 })
	check("NaN unchanged", st.step() == nil)
	-- copy-on-write on the client
	st = stream({ keep = { deep = { 1, 2 } }, change = { n = 1 } })
	local before = st.client
	local keepRef = before.keep
	st.cur.change.n = 2
	st.step()
	check("old client table untouched", before.change.n == 1)
	check("unchanged subtree shared", st.client.keep == keepRef)
	check("changed path is a new table", st.client.change ~= before.change)
	-- lazy keys: skipped on lazy passes, caught up on a full pass, structure still immediate
	local LAZY = { items = { ["*"] = { visitors = true } } }
	st = stream({ items = { a = { status = "draft", visitors = 1 } } })
	st.cur.items.a.visitors = 50
	check("lazy counter not sent", st.step(LAZY) == nil)
	st.cur.items.a.status = "published"
	p = st.step(LAZY)
	check("structural change in lazy table sent at once", p ~= nil and st.client.items.a.status == "published" and st.client.items.a.visitors == 1)
	st.cur.items.b = { status = "new", visitors = 9 }
	st.step(LAZY)
	check("new entry sent whole incl. lazy key", st.client.items.b and st.client.items.b.visitors == 9)
	st.step()
	check("full pass catches up lazy keys", W.equal(st.client, st.cur) == nil)
	-- lazy + whole-array send: the shadow must equal what was sent (value returning to an old value)
	local LZ = { list = { ["*"] = { users = true } } }
	st = stream({ list = { { id = 1, name = "a", users = 5 }, { id = 2, name = "b", users = 6 } } })
	st.cur.list[1].users = 7 -- lazy, not sent
	st.step(LZ)
	st.cur.list = { { id = 3, name = "c", users = 7 }, { id = 4, name = "d", users = 6 } } -- all else changes -> whole
	p = st.step(LZ)
	check("mostly changed array sent whole", p and p.s and p.s.list ~= nil and p.p == nil)
	check("whole send carries current lazy values", st.client.list[1].users == 7)
	st.cur.list[1].users = 5 -- back to the value the stale shadow had
	st.step()
	check("no missed update after whole send", st.client.list[1].users == 5, st.client.list[1].users)

	-- randomized round trips: nested dicts/arrays, random mutations, lazy passes, wire checks
	math.randomseed(4242) -- deterministic
	local rng = { NextInteger = function(_, a, b) return math.random(a, b) end, NextNumber = function() return math.random() end }
	local function rscalar()
		local r = rng:NextInteger(1, 5)
		if r == 1 then return rng:NextInteger(-5, 5) elseif r == 2 then return rng:NextNumber() * 1000
		elseif r == 3 then return "s" .. rng:NextInteger(1, 9) elseif r == 4 then return rng:NextInteger(0, 1) == 1 else return rng:NextNumber() end
	end
	local function rvalue(depth)
		if depth <= 0 or rng:NextNumber() < 0.45 then return rscalar() end
		if rng:NextNumber() < 0.5 then
			local t = {}
			for i = 1, rng:NextInteger(0, 6) do t[i] = rvalue(depth - 1) end
			return t
		end
		local t = {}
		for _ = 1, rng:NextInteger(0, 6) do t["k" .. rng:NextInteger(1, 8)] = rvalue(depth - 1) end
		return t
	end
	local function tables(v, out)
		if type(v) == "table" then table.insert(out, v); for _, x in v do tables(x, out) end end
		return out
	end
	local function mutate(root)
		local all = tables(root, {})
		local t = all[rng:NextInteger(1, #all)]
		local n = #t
		local r = rng:NextInteger(1, 6)
		if n > 0 then
			if r <= 2 then t[rng:NextInteger(1, n)] = rvalue(2)
			elseif r == 3 then table.insert(t, rvalue(2))
			elseif r == 4 then table.remove(t, rng:NextInteger(1, n))
			elseif r == 5 then table.insert(t, 1, rvalue(1))
			else t[n] = nil end
		else
			local key = "k" .. rng:NextInteger(1, 8)
			if r <= 3 then t[key] = rvalue(2) elseif r == 4 then t[key] = nil
			elseif r == 5 then t[key] = rscalar() else t.users = rscalar() end
		end
	end
	local FLAZY = { ["*"] = { users = true, ["*"] = { users = true } } }
	local mismatches, steps, sent, lazyHidden = 0, 0, 0, 0
	for trial = 1, 40 do
		local root = { data = rvalue(4), live = rvalue(4) }
		if type(root.data) ~= "table" then root.data = { x = root.data } end
		if type(root.live) ~= "table" then root.live = { y = root.live } end
		if #root.data > 0 then root.data = { arr = root.data } end
		if #root.live > 0 then root.live = { arr = root.live } end
		st = stream(root)
		for step = 1, 60 do
			for _ = 1, rng:NextInteger(1, 3) do mutate(root) end
			local lazyPass = step % 5 ~= 0 and trial % 2 == 0
			local patch = st.step(if lazyPass then FLAZY else nil)
			if patch then sent += 1 end
			steps += 1
			local d = W.equal(st.client, root, if lazyPass then FLAZY else nil)
			if d then mismatches += 1; if mismatches <= 3 then print("  mismatch trial " .. trial .. " step " .. step .. ": " .. d) end end
			if lazyPass and W.equal(st.client, root) then lazyHidden += 1 end
			if not lazyPass then
				local exact = W.equal(st.client, root)
				if exact then mismatches += 1; if mismatches <= 3 then print("  exact mismatch trial " .. trial .. " step " .. step .. ": " .. exact) end end
			end
		end
	end
	print(string.format("  randomized: %d steps, %d patches, %d lazy-deferred states", steps, sent, lazyHidden))
	check("randomized: client == server after every step", mismatches == 0, mismatches)
	check("randomized: lazy passes really defer some keys", lazyHidden > 0, lazyHidden)
	check("every patch/full state was remote-safe (string keys, no holey arrays)", #W.problems == 0, W.problems[1])
end
local ok, err = xpcall(body, debug.traceback)
if not ok then failc += 1; print("ERROR " .. tostring(err)) end
print(string.format("net patch tests: %d passed, %d failed", pass, failc))
