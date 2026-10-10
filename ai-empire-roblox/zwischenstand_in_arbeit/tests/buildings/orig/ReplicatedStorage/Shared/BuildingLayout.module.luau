--!strict
-- Derived geometry from BuildingPlan: unique interior wall segments with door openings, a flat
-- door list, circulation rectangles (corridors, galleries, lobbies) and slab outlines/holes.
-- Two rooms sharing a boundary produce ONE wall; the envelope and the lift shaft are excluded
-- because the facade and the core generator build them.
local Plan = require(script.Parent.Config.BuildingPlan)
local Layout = {}

export type Opening = { a1: number, a2: number, door: any }
export type Wall = {
	level: number,
	axis: string, -- "x": runs along X at constant z = c ; "z": runs along Z at constant x = c
	c: number,
	a1: number,
	a2: number,
	finish: string, -- solid | glass | panel | fence | barrier (3.6-high glass badge line)
	height: number,
	plus: string?, -- room id on the +c side
	minus: string?, -- room id on the -c side
	openings: { Opening },
}
export type DoorDef = {
	id: string,
	level: number,
	room: string,
	kind: string,
	access: string,
	axis: string,
	x: number,
	z: number,
	w: number,
	h: number,
	inward: Vector3, -- building-local unit vector pointing into the secured room
	exterior: boolean,
	hidden: boolean,
	builder: string, -- "interior" (wall planner) or "exterior" (facade generator)
	swing: string?, -- "out" = leaf swings to the -inward side
}

-- Room kinds whose corridor-facing walls are glazed partitions.
Layout.GLASS_KINDS = {
	team = true, architecture = true, datalab = true, control = true, evaluation = true, launch = true,
	support = true, studio = true, platform = true, lab = true, hwlab = true, meeting = true, focus = true,
	phone = true, first_ai = true, showroom = true, project_meeting = true, boardroom = true, hr = true,
	fleet = true, b1_lobby = true, roof_lobby = true, garden_lobby = true, gym = true, recovery = true,
	cafe = true, compute = true, mailroom = true,
}

local EPS = 0.01

local function roofLevel(tier: number): number
	return Plan.roofLevel(tier)
end

-- Is the line (axis, c) over span [a1,a2] part of the building envelope at this level?
local function envelope(tier: number, level: number, axis: string, c: number, a1: number, a2: number): boolean
	if level == roofLevel(tier) then
		return false -- the roof only has a parapet; head houses build their own walls
	end
	local m = Plan.MAIN
	if level == -1 then
		local g = Plan.GARAGE
		if axis == "z" and (math.abs(c - g.x1) < EPS or math.abs(c - g.x2) < EPS) then
			return true
		end
		if axis == "x" and (math.abs(c - g.z1) < EPS or math.abs(c - g.z2) < EPS) then
			return true
		end
		return false
	end
	local pv = Plan.PAVILION
	if axis == "z" and (math.abs(c - m.x1) < EPS or math.abs(c - m.x2) < EPS) then
		return true -- side facades (main block and pavilion)
	end
	if axis == "x" then
		local front = if level == Plan.founderLevel(tier) then Plan.FOUNDER_FRONT_Z else m.z1
		if math.abs(c - front) < EPS or math.abs(c - m.z1) < EPS then
			return true
		end
		if math.abs(c - m.z2) < EPS then
			return level >= 2 -- levels 0/1: interior link wall to the pavilion
		end
		if level <= 1 and math.abs(c - pv.z2) < EPS then
			return true
		end
	end
	return false
end

local function onShaft(axis: string, c: number, a1: number, a2: number): boolean
	local s = Plan.SHAFT
	if axis == "z" and (math.abs(c - s.x1) < EPS or math.abs(c - s.x2) < EPS) then
		return a1 >= s.z1 - EPS and a2 <= s.z2 + EPS
	end
	if axis == "x" and (math.abs(c - s.z1) < EPS or math.abs(c - s.z2) < EPS) then
		return a1 >= s.x1 - EPS and a2 <= s.x2 + EPS
	end
	return false
end

local function faceLine(r: any, face: string): (string, number, number, number, number)
	-- returns axis, c, a1, a2, side (+1 when the room lies on the +c side of the line)
	if face == "N" then
		return "x", r.z2, r.x1, r.x2, -1
	elseif face == "S" then
		return "x", r.z1, r.x1, r.x2, 1
	elseif face == "E" then
		return "z", r.x2, r.z1, r.z2, -1
	end
	return "z", r.x1, r.z1, r.z2, 1
end

-- An open face (room.open) stays open only towards space of the same access class; elsewhere it
-- becomes a normal wall, so e.g. the public visitor lounge never opens straight into the staff atrium.
local function openLeaks(tier: number, level: number, f: any, mid: number): boolean
	local off = -f.side * 0.5
	local y = Plan.levelY(level) + 1
	local p = if f.axis == "x" then Vector3.new(mid, y, f.c + off) else Vector3.new(f.c + off, y, mid)
	return Plan.accessAt(tier, p) ~= f.room.access
end

local doorCache: { [number]: { DoorDef } } = {}
function Layout.doors(tier: number): { DoorDef }
	local cached = doorCache[tier]
	if cached then
		return cached
	end
	local out: { DoorDef } = {}
	table.insert(out, {
		id = "G_ENTRANCE", level = 0, room = "G_LOBBY", kind = "autoslide", access = "public", axis = "x",
		x = 0, z = Plan.ENTRANCE.z, w = Plan.ENTRANCE.x2 - Plan.ENTRANCE.x1, h = 10,
		inward = Vector3.new(0, 0, 1), exterior = true, hidden = false, builder = "exterior",
	})
	for _, r in Plan.rooms(tier) do
		for i, d in r.doors do
			local axis, c, _, _, side = faceLine(r, d.face)
			local x = if axis == "x" then d.at else c
			local z = if axis == "x" then c else d.at
			local inward = if axis == "x" then Vector3.new(0, 0, side) else Vector3.new(side, 0, 0)
			if d.flip then
				inward = -inward
			end
			local exteriorLine = envelope(tier, r.level, axis, c, d.at - d.w / 2, d.at + d.w / 2)
			table.insert(out, {
				id = string.format("%s_D%d", r.id, i),
				level = r.level,
				room = r.id,
				kind = d.kind,
				access = d.access or r.access,
				axis = axis,
				x = x,
				z = z,
				w = d.w,
				h = d.h or (if d.kind == "autoslide" or d.kind == "glassdouble" then 10 else 9),
				inward = inward,
				exterior = d.exterior == true,
				hidden = d.hidden == true or r.hidden == true,
				builder = if exteriorLine then "exterior" else "interior",
				swing = d.swing,
			})
		end
	end
	doorCache[tier] = out
	return out
end

function Layout.doorsOnLevel(tier: number, level: number): { DoorDef }
	local out = {}
	for _, d in Layout.doors(tier) do
		if d.level == level then
			table.insert(out, d)
		end
	end
	return out
end

local function finishFor(r: any, otherIsRoom: boolean, other: any?): string
	if r.fence then
		return "fence"
	end
	if otherIsRoom then
		return if (r.mood == "founder" or r.mood == "secret") and r.pavilion then "panel" else "solid"
	end
	if r.pavilion and (r.mood == "founder" or r.mood == "secret") then
		return "panel"
	end
	if Layout.GLASS_KINDS[r.kind] then
		return "glass"
	end
	return "solid"
end

-- Explicit interior wall lines that no room face describes on its own.
local function extraLines(level: number): { any }
	local out = {}
	if level == 0 or level == 1 then
		table.insert(out, { axis = "x", c = Plan.MAIN.z2, a1 = Plan.MAIN.x1, a2 = Plan.MAIN.x2, finish = "solid" })
	end
	if level == 0 then
		local g = Plan.GATE_LINE
		table.insert(out, { axis = "x", c = g.z, a1 = g.x1, a2 = g.x2, finish = "barrier" })
	end
	return out
end

local wallCache: { [string]: { Wall } } = {}
function Layout.walls(tier: number, level: number): { Wall }
	local key = tier .. ":" .. level
	local cached = wallCache[key]
	if cached then
		return cached
	end
	local isRoof = level == roofLevel(tier)
	-- 1. faces
	type Face = { axis: string, c: number, a1: number, a2: number, side: number, room: any, open: boolean, finish: string? }
	local faces: { Face } = {}
	for _, r in Plan.roomsOnLevel(tier, level) do
		if r.nowalls or (r.outdoor and not r.fence) then
			continue
		end
		local openFaces = {}
		local openList = r.open
		if openList then
			for _, f in openList do
				openFaces[f] = true
			end
		end
		for _, face in { "N", "S", "E", "W" } do
			local axis, c, a1, a2, side = faceLine(r, face)
			if envelope(tier, level, axis, c, a1, a2) or onShaft(axis, c, a1, a2) then
				continue
			end
			if isRoof and r.fence and (math.abs(c - Plan.MAIN.x1) < EPS or math.abs(c - Plan.MAIN.x2) < EPS or math.abs(c - Plan.MAIN.z2) < EPS) then
				continue -- fenced roof zones end at the parapet
			end
			table.insert(faces, { axis = axis, c = c, a1 = a1, a2 = a2, side = side, room = r, open = openFaces[face] == true })
		end
	end
	for _, line in extraLines(level) do
		table.insert(faces, { axis = line.axis, c = line.c, a1 = line.a1, a2 = line.a2, side = 0, room = nil, open = false, finish = line.finish })
	end
	-- 2. group by line
	local groups: { [string]: { Face } } = {}
	local order: { string } = {}
	for _, f in faces do
		local k = f.axis .. string.format("%.2f", f.c)
		if not groups[k] then
			groups[k] = {}
			table.insert(order, k)
		end
		table.insert(groups[k], f)
	end
	table.sort(order)
	local doors = Layout.doorsOnLevel(tier, level)
	local out: { Wall } = {}
	for _, k in order do
		local list = groups[k]
		local axis, c = list[1].axis, list[1].c
		local cuts: { number } = {}
		for _, f in list do
			table.insert(cuts, f.a1)
			table.insert(cuts, f.a2)
			if f.open then
				-- an open face is judged per neighbouring room (see openLeaks): cut at their edges
				for _, r in Plan.roomsOnLevel(tier, level) do
					table.insert(cuts, if axis == "z" then r.z1 else r.x1)
					table.insert(cuts, if axis == "z" then r.z2 else r.x2)
				end
			end
		end
		local sh = Plan.SHAFT
		if axis == "z" then
			table.insert(cuts, sh.z1)
			table.insert(cuts, sh.z2)
		else
			table.insert(cuts, sh.x1)
			table.insert(cuts, sh.x2)
		end
		table.sort(cuts)
		local current: Wall? = nil
		for i = 1, #cuts - 1 do
			local s1, s2 = cuts[i], cuts[i + 1]
			if s2 - s1 < EPS then
				continue
			end
			local mid = (s1 + s2) / 2
			if onShaft(axis, c, mid - EPS, mid + EPS) then
				-- the core generator builds the lift shaft walls; clip shared faces there
				if current then
					table.insert(out, current)
					current = nil
				end
				continue
			end
			local plus, minus = nil, nil
			local anyWall, explicit = false, false
			local explicitFinish: string? = nil
			for _, f in list do
				if mid > f.a1 and mid < f.a2 then
					if not f.open or openLeaks(tier, level, f, mid) then
						anyWall = true
					end
					if f.room == nil then
						explicit = true
						explicitFinish = f.finish
					elseif f.side > 0 then
						plus = f.room
					else
						minus = f.room
					end
				end
			end
			if not anyWall then
				if current then
					table.insert(out, current)
					current = nil
				end
				continue
			end
			local finish
			if plus and minus then
				local a, b = plus :: any, minus :: any
				if a.fence and not b.fence then
					finish = finishFor(b, true, a)
				elseif b.fence and not a.fence then
					finish = finishFor(a, true, b)
				else
					finish = finishFor(a, not (a.fence and b.fence), b)
				end
			elseif plus or minus then
				finish = finishFor((plus or minus) :: any, explicit, nil)
			else
				finish = explicitFinish or "solid"
			end
			if explicitFinish == "barrier" then
				finish = "barrier"
			end
			local height = Plan.FLOOR_HEIGHT - Plan.SLAB
			if isRoof then
				height = if finish == "fence" then 6 else 12
			elseif finish == "fence" then
				height = 6
			elseif finish == "barrier" then
				height = 3.6
			end
			local plusId = if plus then (plus :: any).id else nil
			local minusId = if minus then (minus :: any).id else nil
			if current and current.finish == finish and current.plus == plusId and current.minus == minusId and math.abs(current.a2 - s1) < EPS then
				current.a2 = s2
			else
				if current then
					table.insert(out, current)
				end
				current = { level = level, axis = axis, c = c, a1 = s1, a2 = s2, finish = finish, height = height, plus = plusId, minus = minusId, openings = {} }
			end
		end
		if current then
			table.insert(out, current)
		end
	end
	-- 3. openings: doors lying on a wall line within the segment span
	for _, w in out do
		for _, d in doors do
			if d.builder ~= "interior" or d.axis ~= w.axis then
				continue
			end
			local dc = if d.axis == "x" then d.z else d.x
			local da = if d.axis == "x" then d.x else d.z
			if math.abs(dc - w.c) < EPS and da > w.a1 - EPS and da < w.a2 + EPS then
				table.insert(w.openings, { a1 = math.max(w.a1, da - d.w / 2), a2 = math.min(w.a2, da + d.w / 2), door = d })
			end
		end
		table.sort(w.openings, function(a, b)
			return a.a1 < b.a1
		end)
	end
	wallCache[key] = out
	return out
end

-- Circulation rectangles (main block, levels 0..founder) on a 2-stud grid, greedily merged.
local circCache: { [string]: { any } } = {}
function Layout.circulation(tier: number, level: number): { any }
	local key = tier .. ":" .. level
	local cached = circCache[key]
	if cached then
		return cached
	end
	local out = {}
	if level < 0 or level >= roofLevel(tier) then
		circCache[key] = out
		return out
	end
	local m = Plan.MAIN
	local z0 = if level == Plan.founderLevel(tier) then Plan.FOUNDER_FRONT_Z else m.z1
	local G = 2
	local nx = math.floor((m.x2 - m.x1) / G)
	local nz = math.floor((m.z2 - z0) / G)
	local blocked: { [number]: boolean } = {}
	local function block(x1: number, x2: number, z1: number, z2: number)
		for ix = 0, nx - 1 do
			local cx = m.x1 + ix * G + G / 2
			if cx >= x1 and cx <= x2 then
				for iz = 0, nz - 1 do
					local cz = z0 + iz * G + G / 2
					if cz >= z1 and cz <= z2 then
						blocked[iz * nx + ix] = true
					end
				end
			end
		end
	end
	for _, r in Plan.roomsOnLevel(tier, level) do
		if not r.pavilion then
			block(r.x1, r.x2, r.z1, r.z2)
		end
	end
	local s = Plan.SHAFT
	block(s.x1, s.x2, s.z1, s.z2)
	block(Plan.RISER.x1, Plan.RISER.x2, Plan.RISER.z1, Plan.RISER.z2)
	if level >= 1 then
		local a = Plan.ATRIUM
		block(a.x1, a.x2, a.z1, a.z2)
	end
	if level == 0 then
		local p = Plan.PORTAL
		block(p.x1, p.x2, p.z1 - 1, p.z2)
	end
	if level == 1 then
		local v = Plan.LOBBY_VOID
		block(v.x1, v.x2, v.z1, v.z2)
	end
	local used: { [number]: boolean } = {}
	for iz = 0, nz - 1 do
		for ix = 0, nx - 1 do
			local id = iz * nx + ix
			if not blocked[id] and not used[id] then
				local w = 0
				while ix + w < nx and not blocked[iz * nx + ix + w] and not used[iz * nx + ix + w] do
					w += 1
				end
				local h = 1
				local grow = true
				while grow and iz + h < nz do
					for k = 0, w - 1 do
						local cell = (iz + h) * nx + ix + k
						if blocked[cell] or used[cell] then
							grow = false
							break
						end
					end
					if grow then
						h += 1
					end
				end
				for dz = 0, h - 1 do
					for k = 0, w - 1 do
						used[(iz + dz) * nx + ix + k] = true
					end
				end
				table.insert(out, { x1 = m.x1 + ix * G, x2 = m.x1 + (ix + w) * G, z1 = z0 + iz * G, z2 = z0 + (iz + h) * G })
			end
		end
	end
	circCache[key] = out
	return out
end

-- Slab outline rectangles (top at levelY) and holes for this level.
function Layout.slabs(tier: number, level: number): ({ any }, { any })
	local m, g, pv = Plan.MAIN, Plan.GARAGE, Plan.PAVILION
	local rects, holes = {}, {}
	local roof = roofLevel(tier)
	if level == -1 then
		table.insert(rects, { x1 = g.x1, x2 = g.x2, z1 = g.z1, z2 = g.z2 })
	elseif level == 0 then
		table.insert(rects, { x1 = g.x1, x2 = g.x2, z1 = g.z1, z2 = g.z2 })
		table.insert(rects, { x1 = pv.x1, x2 = pv.x2, z1 = g.z2, z2 = pv.z2 })
	elseif level == roof then
		table.insert(rects, { x1 = m.x1, x2 = m.x2, z1 = Plan.FOUNDER_FRONT_Z, z2 = m.z2 })
	else
		table.insert(rects, { x1 = m.x1, x2 = m.x2, z1 = m.z1, z2 = m.z2 })
	end
	if level == 1 or level == 2 then
		table.insert(rects, { x1 = pv.x1, x2 = pv.x2, z1 = pv.z1, z2 = pv.z2 })
	end
	local s = Plan.SHAFT
	table.insert(holes, { x1 = s.x1, x2 = s.x2, z1 = s.z1, z2 = s.z2, kind = "shaft" })
	if level >= 0 then
		local st = Plan.STAIR_LAYOUT
		table.insert(holes, { x1 = st.inner.x1, x2 = st.inner.x2, z1 = st.flightA.z1, z2 = st.inner.z2, kind = "stair" })
	end
	if level >= 1 then
		local a = Plan.ATRIUM
		table.insert(holes, { x1 = a.x1, x2 = a.x2, z1 = a.z1, z2 = a.z2, kind = if level == roof then "skylight" else "atrium" })
	end
	if level == 1 then
		local v = Plan.LOBBY_VOID
		table.insert(holes, { x1 = v.x1, x2 = v.x2, z1 = v.z1, z2 = v.z2, kind = "lobbyvoid" })
	end
	return rects, holes
end

return Layout
