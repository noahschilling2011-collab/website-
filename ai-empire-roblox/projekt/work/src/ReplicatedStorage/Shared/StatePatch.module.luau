--!strict
-- Delta encoding for State snapshots (server SessionService -> client StateController).
--
-- The server keeps, per player, a private copy ("shadow") of what it last sent. diff() walks the
-- current state against that shadow, returns only what changed (down to single numbers) and brings
-- the shadow up to date in the same pass. The client applies the patch copy-on-write onto its last
-- state, so StateController.snapshot is always a complete snapshot and no UI code has to know.
-- Why a leaf diff and not per-field signatures: measured on a mature save, the heavy fields
-- (data.models, data.empire.projects, live.marketplace, live.studio) all change every second
-- (user counts, visitors, revenue totals), so whole-field omission would save almost nothing.
--
-- Patch node (only string keys, so it survives Roblox remote serialisation unchanged):
--   s = { [key] = value }   set: scalars or whole new subtrees
--   p = { [key] = Patch }   nested changes
--   d = { key, ... }        deleted keys (dictionaries only)
--   n = number              arrays only: the new length; keys in s/p are tostring(index)

local StatePatch = {}

export type Patch = {
	s: { [string]: any }?,
	p: { [string]: Patch }?,
	d: { string }?,
	n: number?,
}

-- Optional "lazy" spec for diff(): a tree mirroring the state; `true` marks a key whose value is not
-- compared on this pass (the caller runs a pass without the spec now and then to catch up).
-- "*" matches any key (array index or dictionary key).
export type Lazy = { [string]: any }

-- An array whose changed values exceed this share of all its values is sent whole: logs that shift
-- (empire.history, invoices, sorted offer lists after an insert) change every element, where
-- per-index entries would only add key overhead. Arrays where only a few fields per element change
-- (user counts in live.marketplace.offers) stay per-index patches.
StatePatch.WHOLE_ARRAY_SHARE = 0.5

-- Deep copy; also returns the number of scalar values copied
local function copyCount(value: any): (any, number)
	if type(value) ~= "table" then
		return value, 1
	end
	local out = {}
	local count = 0
	for k, v in value do
		local c, n = copyCount(v)
		out[k] = c
		count += n
	end
	return out, math.max(1, count)
end

function StatePatch.copy(value: any): any
	return (copyCount(value))
end

local function keyOf(key: any): string
	return if type(key) == "string" then key else tostring(key)
end

local function addSet(node: Patch?, key: string, value: any): Patch
	local patch: Patch = node or {}
	local s: { [string]: any } = patch.s or {}
	patch.s = s
	s[key] = value
	return patch
end

local function addNested(node: Patch?, key: string, sub: Patch): Patch
	local patch: Patch = node or {}
	local p: { [string]: Patch } = patch.p or {}
	patch.p = p
	p[key] = sub
	return patch
end

local diffTable: (shadow: { [any]: any }, cur: { [any]: any }, lazy: Lazy?) -> (Patch?, boolean, number, number)

-- One child (value is a table). Returns: nil (unchanged) | true + value (set whole) | false + sub-patch,
-- plus changed / total scalar counts. Updates shadow[key].
local function tableChild(shadow: { [any]: any }, key: any, value: { [any]: any }, lazy: any): (boolean?, any, number, number)
	local old = shadow[key]
	-- same kind (array / dictionary; an empty table counts as a dictionary): diff in place
	if type(old) == "table" and (#old > 0) == (#value > 0) then
		local spec: Lazy? = if type(lazy) == "table" then lazy else nil
		local sub, whole, changed, total = diffTable(old, value, spec) -- old now mirrors value (except lazy keys)
		if not sub then
			return nil, nil, 0, total
		end
		if whole then
			if spec then
				shadow[key] = copyCount(value) -- the shadow must equal what was sent, lazy keys included
			end
			return true, value, changed, total
		end
		return false, sub, changed, total
	end
	local copied, count = copyCount(value)
	shadow[key] = copied
	return true, value, count, count
end

-- Returns the patch (nil = unchanged), whether the table should rather be sent whole, and the number
-- of changed / total scalar values.
diffTable = function(shadow: { [any]: any }, cur: { [any]: any }, lazy: Lazy?): (Patch?, boolean, number, number)
	local node: Patch? = nil
	local changedValues, totalValues = 0, 0
	local n = #cur
	if n > 0 then
		local childLazy = if lazy then lazy["*"] else nil
		if childLazy == true then
			return nil, false, 0, n -- the whole array is lazy
		end
		local oldN = #shadow
		for i = 1, n do
			local value = cur[i]
			if type(value) == "table" then
				local whole, payload, changed, total = tableChild(shadow, i, value, childLazy)
				changedValues += changed
				totalValues += total
				if whole then
					node = addSet(node, tostring(i), payload)
				elseif whole == false then
					node = addNested(node, tostring(i), payload)
				end
			else
				totalValues += 1
				local old = shadow[i]
				if old ~= value and (old == old or value == value) then -- NaN -> NaN counts as unchanged
					shadow[i] = value
					changedValues += 1
					node = addSet(node, tostring(i), value)
				end
			end
		end
		local i = n + 1
		while shadow[i] ~= nil do
			shadow[i] = nil
			i += 1
		end
		if not node and oldN == n then
			return nil, false, 0, totalValues
		end
		local patch: Patch = node or {}
		patch.n = n
		return patch, changedValues > totalValues * StatePatch.WHOLE_ARRAY_SHARE, changedValues, totalValues
	end
	local any = if lazy then lazy["*"] else nil
	for key, value in cur do
		local childLazy = if lazy then (lazy[key] or any) else nil
		if childLazy == true then
			totalValues += 1
		elseif type(value) == "table" then
			local whole, payload, changed, total = tableChild(shadow, key, value, childLazy)
			changedValues += changed
			totalValues += total
			if whole then
				node = addSet(node, keyOf(key), payload)
			elseif whole == false then
				node = addNested(node, keyOf(key), payload)
			end
		else
			totalValues += 1
			local old = shadow[key]
			if old ~= value and (old == old or value == value) then
				shadow[key] = value
				changedValues += 1
				node = addSet(node, keyOf(key), value)
			end
		end
	end
	for key in shadow do
		if cur[key] == nil then
			shadow[key] = nil
			local patch: Patch = node or {}
			node = patch
			local d = patch.d or {}
			patch.d = d
			table.insert(d, keyOf(key))
		end
	end
	return node, false, changedValues, totalValues
end

-- Compares cur with shadow (both dictionaries), updates shadow to mirror cur and returns what changed
-- (nil when nothing did). Values in the patch may be references into cur: serialise right away.
-- lazy (optional): keys skipped on this pass (see Lazy); they keep their last sent value meanwhile.
function StatePatch.diff(shadow: { [any]: any }, cur: { [any]: any }, lazy: Lazy?): Patch?
	local patch, whole = diffTable(shadow, cur, lazy)
	if patch and whole then -- only possible when the root itself is an array
		local s: { [string]: any } = {}
		for k, v in cur do
			s[keyOf(k)] = v
		end
		for k in shadow do
			shadow[k] = nil
		end
		for k, v in cur do
			shadow[k] = StatePatch.copy(v)
		end
		return { s = s, n = #cur }
	end
	return patch
end

-- Returns a new table = old with the patch applied. old is never modified; unchanged subtrees are
-- shared with it.
function StatePatch.apply(old: any, patch: Patch): { [any]: any }
	local out: { [any]: any } = if type(old) == "table" then table.clone(old) else {}
	local arrayMode = patch.n ~= nil
	local s = patch.s
	if s then
		for k, v in s do
			out[if arrayMode then (tonumber(k) or k) else k] = v
		end
	end
	local p = patch.p
	if p then
		for k, sub in p do
			local key: any = if arrayMode then (tonumber(k) or k) else k
			out[key] = StatePatch.apply(out[key], sub)
		end
	end
	local d = patch.d
	if d then
		for _, k in d do
			out[k] = nil
		end
	end
	local n = patch.n
	if n then
		local i = n + 1
		while out[i] ~= nil do
			out[i] = nil
			i += 1
		end
	end
	return out
end

return StatePatch
