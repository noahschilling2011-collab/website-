--!strict
-- RoomKitsWork: furniture, fixtures, workstations, activities, screens and prompts of the work floors and
-- the founder level (SPEC §11): team rooms, studios, labs, control rooms, meeting rooms, pantries, lounges,
-- focus/phone/print rooms, restrooms, the boardroom, the founder suite and the terraces.
-- Walls, doors, floors, ceilings, lights, nameplates, cameras and access volumes come from InteriorDesign;
-- this module only adds a "FitOut" model inside ctx.rooms[room.id] (WC cubicle doors go to Office.Doors).
--
-- Every room is laid out in its own frame: origin = centre of the entry wall at finished-floor height,
-- local +Z points into the room, X runs along the entry wall (W wide) and Z spans the depth D. Kits place
-- furniture in that frame, so mirrored east/west rooms and every plot orientation come out the same.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Plan = require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Layout = require(ReplicatedStorage.Shared.BuildingLayout)
local Departments = require(ReplicatedStorage.Shared.Config.DepartmentConfig)
local Kit = require(script.Parent.ArchKit)

local Work = {}

local C, M, A = Kit.C, Kit.M, Kit.A
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local RAD = math.rad
local DETAIL: Kit.Opts = { detail = true }
local GLASS: Kit.Opts = { transparency = A.glassTransparency, castShadow = false }

local ENTRY = 6 -- free band along the entry wall (door swing + circulation)
local CR = 2.5 -- chair zone beyond the user edge of a desk (chair incl. its back)
local AISLE = 4 -- aisle between two chair rows
local WALL_AISLE = 3.6 -- aisle between a chair row and a wall
local FACADE_GAP = 2 -- furniture keeps this distance from glazed facades
local EPS = 0.01
local STRIP = 1.8 -- depth of the wall furniture along a feature wall (credenza, boards)

-- Desk pitch along a row and depth of the desk top per ArchKit station variant.
local DESK: { [string]: { p: number, dd: number, cr: number } } = {
	bench = { p = 7, dd = 3.4, cr = CR },
	ldesk = { p = 7, dd = 3.4, cr = 2.9 }, -- the return + pedestal reach 4.5 behind the desk centre
	standing = { p = 6, dd = 3.0, cr = CR },
	dual = { p = 8, dd = 3.6, cr = CR },
	lab = { p = 7, dd = 3.4, cr = CR },
	trading = { p = 13, dd = 3.3, cr = CR },
}

-- Desk monitors show the department screen, except where the room kind has its own screen kind.
local KIND_SCREEN: { [string]: string } = { support = "customers", studio = "product", platform = "platform", hr = "hr" }

-- Yaw (degrees) so that a piece's FRONT (-Z) faces a room direction: F = towards the entry wall (-z),
-- B = towards the back wall (+z), L = -x, R = +x.
local FRONT: { [string]: number } = { F = 0, B = 180, L = 90, R = -90 }
-- Yaw so that a desk user LOOKS towards a room direction (ArchKit desks: user at -Z looking +Z).
local LOOK: { [string]: number } = { B = 0, F = 180, R = 90, L = -90 }
-- Yaw of wall-mounted pieces (front towards the room) per wall side.
local WALL_YAW: { [string]: number } = { back = 0, front = 180, left = -90, right = 90 }
local INSET: { [string]: number } = { solid = 0.5, panel = 0.5, glass = 0.2, barrier = 0.15, fence = 0.25, facade = 0.6, open = 0 }
local INWARD: { [string]: Vector3 } = { S = V3(0, 0, 1), N = V3(0, 0, -1), W = V3(1, 0, 0), E = V3(-1, 0, 0) }

type Rect = { x1: number, x2: number, z1: number, z2: number }
type Box = { x1: number, x2: number, z1: number, z2: number, name: string }
type DoorL = { x: number, z: number, w: number, side: string, id: string, kind: string }
type R = {
	ctx: any,
	room: Plan.Room,
	tier: number,
	model: Model,
	cf: CFrame,
	rf: CFrame,
	W: number,
	D: number,
	level: number,
	seed: number,
	style: number,
	owner: number,
	accent: Color3,
	dept: string,
	access: string,
	face: string,
	sideFace: { [string]: string },
	side: { [string]: string },
	inner: { [string]: number },
	zEnd: number,
	doorX: number,
	doors: { DoorL },
	keep: { Box },
	boxes: { Box },
	desks: number,
	acts: number,
	issues: { string },
}

---------------------------------------------------------------------------------------------
-- Room frame, wall finishes and doors
---------------------------------------------------------------------------------------------
local function dirFace(d: Vector3): string
	if d.X > 0.5 then
		return "E"
	elseif d.X < -0.5 then
		return "W"
	elseif d.Z > 0.5 then
		return "N"
	end
	return "S"
end

local function faceLine(room: Plan.Room, face: string): (string, number, number, number)
	if face == "N" then
		return "x", room.z2, room.x1, room.x2
	elseif face == "S" then
		return "x", room.z1, room.x1, room.x2
	elseif face == "E" then
		return "z", room.x2, room.z1, room.z2
	end
	return "z", room.x1, room.z1, room.z2
end

-- Envelope lines (facades built by the exterior generator) at this level.
local function envelope(tier: number, level: number, axis: string, c: number): boolean
	if level >= Plan.roofLevel(tier) or level < 0 then
		return false
	end
	local m = Plan.MAIN
	if axis == "z" then
		return math.abs(c - m.x1) < EPS or math.abs(c - m.x2) < EPS
	end
	local front = if level == Plan.founderLevel(tier) then Plan.FOUNDER_FRONT_Z else m.z1
	if math.abs(c - front) < EPS or math.abs(c - m.z1) < EPS then
		return true
	end
	return math.abs(c - m.z2) < EPS and level >= 2
end

-- Finish of the wall at point `a` of a room face: facade | solid | glass | panel | fence | barrier | open.
local function finishAt(tier: number, room: Plan.Room, face: string, a: number): string
	local axis, c = faceLine(room, face)
	if envelope(tier, room.level, axis, c) then
		return "facade"
	end
	if room.open then
		for _, f in room.open do
			if f == face then
				return "open"
			end
		end
	end
	for _, w in Layout.walls(tier, room.level) do
		if w.axis == axis and math.abs(w.c - c) < EPS and a > w.a1 - EPS and a < w.a2 + EPS then
			return w.finish
		end
	end
	-- the lift shaft / riser walls are built by the core generator
	local s, r = Plan.SHAFT, Plan.RISER
	if axis == "z" and (math.abs(c - s.x1) < EPS or math.abs(c - s.x2) < EPS) and a > s.z1 - EPS and a < r.z2 + EPS then
		return "solid"
	end
	if axis == "x" and math.abs(c - s.z1) < EPS and a > s.x1 - EPS and a < s.x2 + EPS then
		return "solid"
	end
	return "open"
end

local function majorityFinish(tier: number, room: Plan.Room, face: string): string
	local _, _, a1, a2 = faceLine(room, face)
	local count: { [string]: number } = {}
	local best, bestN = "open", -1
	for i = 1, 7 do
		local f = finishAt(tier, room, face, a1 + (a2 - a1) * (i - 0.5) / 7)
		count[f] = (count[f] or 0) + 1
	end
	for _, f in { "solid", "panel", "facade", "glass", "fence", "barrier", "open" } do
		if (count[f] or 0) > bestN then
			best, bestN = f, count[f] or 0
		end
	end
	return best
end

local function newRoom(ctx: any, room: Plan.Room, parent: Model, face: string?): R
	local f = face or (if room.doors[1] then room.doors[1].face else "S")
	local inward = INWARD[f]
	local up = V3(0, 1, 0)
	local right = up:Cross(inward)
	local y = Plan.levelY(room.level) + (if room.outdoor then 0 else Kit.FINISH)
	local origin, W, D
	if f == "S" then
		origin, W, D = V3((room.x1 + room.x2) / 2, y, room.z1), room.x2 - room.x1, room.z2 - room.z1
	elseif f == "N" then
		origin, W, D = V3((room.x1 + room.x2) / 2, y, room.z2), room.x2 - room.x1, room.z2 - room.z1
	elseif f == "W" then
		origin, W, D = V3(room.x1, y, (room.z1 + room.z2) / 2), room.z2 - room.z1, room.x2 - room.x1
	else
		origin, W, D = V3(room.x2, y, (room.z1 + room.z2) / 2), room.z2 - room.z1, room.x2 - room.x1
	end
	local rf = CFrame.fromMatrix(origin, right, up, inward)
	local sideFace: { [string]: string } = { front = f, back = dirFace(inward), left = dirFace(-right), right = dirFace(right) }
	local side: { [string]: string } = {}
	for s, bf in sideFace do
		side[s] = if room.outdoor and not room.fence then "open" else majorityFinish(ctx.tier, room, bf)
	end
	if room.outdoor then
		-- terraces: the building face and the slab edge railing keep a gap like a facade
		side.front = "facade"
		side.back = "facade"
	end
	local inner = {
		front = INSET[side.front] or 0.5,
		back = D - (INSET[side.back] or 0.5),
		left = -W / 2 + (INSET[side.left] or 0.5),
		right = W / 2 - (INSET[side.right] or 0.5),
	}
	local r: R = {
		ctx = ctx,
		room = room,
		tier = ctx.tier,
		model = parent,
		cf = ctx.cf,
		rf = rf,
		W = W,
		D = D,
		level = room.level,
		seed = Kit.hash(room.id),
		style = room.style,
		owner = ctx.owner,
		accent = ctx.accent,
		dept = room.dept or "operations",
		access = room.access,
		face = f,
		sideFace = sideFace,
		side = side,
		inner = inner,
		zEnd = inner.back - (if side.back == "facade" then FACADE_GAP else 0.3),
		doorX = 0,
		doors = {},
		keep = {},
		boxes = {},
		desks = 0,
		acts = 0,
		issues = {},
	}
	-- every door on the room boundary (its own and the neighbours' doors opening into it)
	local primary = false
	for _, d in Layout.doors(ctx.tier) do
		if d.level ~= room.level then
			continue
		end
		local on
		if d.axis == "x" then
			on = (math.abs(d.z - room.z1) < EPS or math.abs(d.z - room.z2) < EPS) and d.x > room.x1 - EPS and d.x < room.x2 + EPS
		else
			on = (math.abs(d.x - room.x1) < EPS or math.abs(d.x - room.x2) < EPS) and d.z > room.z1 - EPS and d.z < room.z2 + EPS
		end
		if not on then
			continue
		end
		local p = rf:PointToObjectSpace(V3(d.x, y, d.z))
		local s = if math.abs(p.Z) < 0.1 then "front" elseif math.abs(p.Z - D) < 0.1 then "back" elseif p.X < 0 then "left" else "right"
		table.insert(r.doors, { x = p.X, z = p.Z, w = d.w, side = s, id = d.id, kind = d.kind })
		local h = d.w / 2 + 1
		local box: Box
		if s == "front" then
			box = { x1 = p.X - h, x2 = p.X + h, z1 = 0, z2 = ENTRY, name = d.id }
			if not primary then
				r.doorX = p.X
				primary = true
			end
		elseif s == "back" then
			box = { x1 = p.X - h, x2 = p.X + h, z1 = D - ENTRY, z2 = D, name = d.id }
		elseif s == "left" then
			box = { x1 = -W / 2, x2 = -W / 2 + ENTRY, z1 = p.Z - h, z2 = p.Z + h, name = d.id }
		else
			box = { x1 = W / 2 - ENTRY, x2 = W / 2, z1 = p.Z - h, z2 = p.Z + h, name = d.id }
		end
		table.insert(r.keep, box)
	end
	return r
end

-- Layout bookkeeping: every floor-standing piece claims its footprint; overlaps with door zones,
-- other pieces or the walls are collected and reported once per build.
local function overlap(a: Rect, b: Rect): boolean
	return a.x1 < b.x2 - 0.05 and b.x1 < a.x2 - 0.05 and a.z1 < b.z2 - 0.05 and b.z1 < a.z2 - 0.05
end
local function claim(R: R, name: string, x1: number, x2: number, z1: number, z2: number)
	local b: Box = { x1 = math.min(x1, x2), x2 = math.max(x1, x2), z1 = math.min(z1, z2), z2 = math.max(z1, z2), name = name }
	local i = R.inner
	if b.x1 < i.left - 0.05 or b.x2 > i.right + 0.05 or b.z1 < i.front - 0.05 or b.z2 > i.back + 0.05 then
		table.insert(R.issues, string.format("%s %s outside the room", R.room.id, name))
	end
	for _, k in R.keep do
		if overlap(b, k) then
			table.insert(R.issues, string.format("%s %s in door zone %s", R.room.id, name, k.name))
		end
	end
	for _, o in R.boxes do
		if overlap(b, o) then
			table.insert(R.issues, string.format("%s %s overlaps %s", R.room.id, name, o.name))
		end
	end
	table.insert(R.boxes, b)
end
local function free(R: R, x1: number, x2: number, z1: number, z2: number): boolean
	local b: Rect = { x1 = math.min(x1, x2), x2 = math.max(x1, x2), z1 = math.min(z1, z2), z2 = math.max(z1, z2) }
	for _, k in R.keep do
		if overlap(b, k) then
			return false
		end
	end
	for _, o in R.boxes do
		if overlap(b, o) then
			return false
		end
	end
	return true
end

---------------------------------------------------------------------------------------------
-- Placement helpers (room-local -> building-local)
---------------------------------------------------------------------------------------------
local function at(R: R, x: number, z: number, yaw: number?): CFrame
	return R.rf * CF(x, 0, z) * ANG(0, RAD(yaw or 0), 0)
end
local function pt(R: R, x: number, h: number, z: number): Vector3
	return R.rf:PointToWorldSpace(V3(x, h, z))
end
-- Room-local (x, z) at `dist` in front of a wall side at coordinate t along it.
local function wallPoint(R: R, side: string, t: number, dist: number): (number, number)
	if side == "back" then
		return t, R.inner.back - dist
	elseif side == "front" then
		return t, R.inner.front + dist
	elseif side == "left" then
		return R.inner.left + dist, t
	end
	return R.inner.right - dist, t
end
local function wallAt(R: R, side: string, t: number, off: number?): CFrame
	local x, z = wallPoint(R, side, t, off or 0)
	return at(R, x, z, WALL_YAW[side])
end
-- Footprint of a wall piece: width w along the wall, depth d from the wall face (+ offset).
local function wallClaim(R: R, name: string, side: string, t: number, w: number, d: number, off: number?)
	local o = off or 0
	local xa, za = wallPoint(R, side, t, o)
	local xb, zb = wallPoint(R, side, t, o + d)
	if side == "back" or side == "front" then
		claim(R, name, t - w / 2, t + w / 2, za, zb)
	else
		claim(R, name, xa, xb, t - w / 2, t + w / 2)
	end
end
local function opposite(side: string): string
	return if side == "left" then "right" elseif side == "right" then "left" elseif side == "front" then "back" else "front"
end
local function solidish(f: string): boolean
	return f == "solid" or f == "panel"
end
local function pick<T>(list: { T }, seed: number): T
	return Kit.pick(list, seed)
end

local function activity(R: R, kind: string, dept: string, role: string, x: number, z: number, fx: number, fz: number, seat: Seat?, extra: Kit.ActivityExtra?): Model
	R.acts += 1
	local e: Kit.ActivityExtra = extra or {}
	e.roomAccess = R.access
	e.homeRoom = R.room.id
	e.facing = pt(R, fx, 4.5, fz)
	local id = string.format("%s_%s%d", R.room.id, kind, R.acts)
	return Kit.activity(R.model, R.cf, id, kind, dept, role, CF(pt(R, x, 2.8, z)), R.level, R.owner, seat, e)
end
-- Activity standing in front of a seat (distance `d` along the sitter's view), facing the seat.
local function seatActivity(R: R, kind: string, dept: string, seat: Seat, d: number, extra: Kit.ActivityExtra?): Model
	local p = R.rf:PointToObjectSpace(R.cf:PointToObjectSpace(seat.Position))
	local look = R.rf:VectorToObjectSpace(R.cf:VectorToObjectSpace(seat.CFrame.LookVector))
	return activity(R, kind, dept, "any", p.X + look.X * d, p.Z + look.Z * d, p.X, p.Z, seat, extra)
end
local function roleOf(dept: string): string
	local d = (Departments.DEPARTMENTS :: any)[dept]
	return if d and d.role then d.role elseif dept == "compute" then "engineer" else "any"
end

---------------------------------------------------------------------------------------------
-- Workstations
---------------------------------------------------------------------------------------------
-- Decorative parts dropped (in this order) until a station meets its part budget.
local TRIM = {
	"Mouse", "ModestyPanel", "InstrumentPanel", "Flask", "Papers", "Notebook", "PhotoFrame", "Mug", "DeskPlant", "DeskPot",
	"LampHead", "LampArm", "LampFoot", "LaptopLid", "LaptopBase", "ArmRest", "PCTower", "ReagentShelf", "ShelfPost",
	"DeskFascia", "@foot", "Instrument", "@stand",
}
-- Part budget per station variant (desk + chair + monitors + keyboard).
local STATION_MAX: { [string]: number } = { bench = 10, ldesk = 11, standing = 10, dual = 10, lab = 9, trading = 12 }
-- Two crossed chair base bars -> one round foot (one part less).
local function roundFoot(m: Model): boolean
	local bars: { BasePart } = {}
	for _, d in m:GetDescendants() do
		if d.Name == "ChairBase" and d:IsA("BasePart") then
			table.insert(bars, d)
		end
	end
	if #bars ~= 2 then
		return false
	end
	local p = bars[1]
	local foot = Instance.new("Part")
	foot.Name = "ChairFoot"
	foot.Shape = Enum.PartType.Cylinder
	foot.Anchored = true
	foot.CanCollide = false
	foot.CanTouch = false
	foot.CanQuery = false
	foot.CastShadow = false
	foot.Size = V3(0.3, 1.9, 1.9)
	foot.CFrame = p.CFrame * CF(0, -0.15, 0) * ANG(0, 0, math.pi / 2)
	foot.Color = p.Color
	foot.Material = p.Material
	foot.Parent = p.Parent
	bars[1]:Destroy()
	bars[2]:Destroy()
	return true
end

-- Monitors stand directly on the desk top instead of on a stand (one part less per monitor).
local function standless(m: Model, budget: number): number
	local removed = 0
	for _, d in m:GetDescendants() do
		if removed >= budget then
			break
		end
		if d.Name == "MonitorStand" and d:IsA("BasePart") then
			local best: BasePart? = nil
			local dist = 3
			for _, s in m:GetDescendants() do
				if (s.Name == "DisplayContent" or s.Name == "SecondaryDisplay") and s:IsA("BasePart") then
					local gap = (s.Position - d.Position).Magnitude
					if gap < dist then
						best, dist = s, gap
					end
				end
			end
			if best then
				local bottom = d.Position.Y - d.Size.Y / 2
				local drop = (best.Position.Y - best.Size.Y / 2) - bottom - 0.02
				best.CFrame = best.CFrame - Vector3.new(0, drop, 0)
			end
			d:Destroy()
			removed += 1
		end
	end
	return removed
end

local function trim(m: Model, max: number)
	local parts: { BasePart } = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	local count = #parts
	local firstFascia: BasePart? = nil
	for _, p in parts do
		if p.Name == "DeskFascia" then
			firstFascia = p
			break
		end
	end
	for _, name in TRIM do
		if name == "@foot" then
			if count > max and roundFoot(m) then
				count -= 1
			end
			continue
		elseif name == "@stand" then
			if count > max then
				count -= standless(m, count - max)
			end
			continue
		end
		for i = #parts, 1, -1 do
			if count <= max then
				return
			end
			local p = parts[i]
			if p.Name == name and p.Parent and p ~= firstFascia then
				p:Destroy()
				count -= 1
			end
		end
	end
end

local function deptInfo(dept: string): (string, string?, string, string)
	if dept == "operations" then
		return "empire", "team", "support", "hr"
	elseif dept == "executive" then
		return "empire", nil, "any", "founder"
	end
	local d = (Departments.DEPARTMENTS :: any)[dept]
	if d then
		return d.app or "market", d.section, d.role or "any", d.screen or dept
	end
	return "market", nil, "any", dept
end

local function station(R: R, x: number, z: number, yaw: number, variant: string, dept: string?): Model
	R.desks += 1
	local dp = dept or R.dept
	local app, section, role, screenKind = deptInfo(dp)
	local id = R.room.id .. "_Desk" .. R.desks
	local m = Kit.station(R.model, R.cf, id, dp, role, at(R, x, z, yaw), R.level, variant, R.owner, R.accent, app, section, R.access, R.room.id)
	local disp = m:FindFirstChild("DisplayContent")
	if disp then
		disp:SetAttribute("LiveScreen", KIND_SCREEN[R.room.kind] or screenKind)
	end
	-- stand just behind the chair line, beside the chair (on the aisle, not between desk returns)
	local g = DESK[variant] or DESK.bench
	local sideX = if variant == "ldesk" then -2.0 else 2.0
	m:SetAttribute("InteractionPosition", (R.cf * at(R, x, z, yaw) * CF(sideX, 2.8, -(g.dd / 2 + g.cr) - 0.3)).Position)
	trim(m, STATION_MAX[variant] or 12)
	return m
end

-- Desk + chair footprint of a station at (x, z) whose user looks along `yaw` (0/90/180/-90 only).
local function stationClaim(R: R, x: number, z: number, yaw: number, variant: string)
	local g = DESK[variant] or DESK.bench
	local half = g.p / 2
	local a1, a2 = -g.dd / 2 - g.cr, g.dd / 2 -- along the look axis, user side negative
	local y = ((yaw % 360) + 360) % 360
	if y < 1 or y > 359 then
		claim(R, "Desk", x - half, x + half, z + a1, z + a2)
	elseif math.abs(y - 180) < 1 then
		claim(R, "Desk", x - half, x + half, z - a2, z - a1)
	elseif math.abs(y - 90) < 1 then
		claim(R, "Desk", x + a1, x + a2, z - half, z + half)
	else
		claim(R, "Desk", x - a2, x - a1, z - half, z + half)
	end
end

---------------------------------------------------------------------------------------------
-- Desk rows: candidate arrangements across a band (singles facing a wall, back-to-back pods)
---------------------------------------------------------------------------------------------
type Row = { c: number, look: number }
type RowSet = { rows: { Row }, pods: number, slack: number }
local UNIT: { [string]: { low: boolean, high: boolean } } = {
	SL = { low = false, high = true }, -- desk front towards the low edge, chairs on the high side
	SH = { low = true, high = false }, -- chairs on the low side, users look towards the high edge
	P = { low = true, high = true }, -- back-to-back pod
}
local function rowSets(lo: number, hi: number, lowEdge: string, highEdge: string, dd: number, cr: number, slackTo: string): { RowSet }
	local out: { RowSet } = {}
	local seen: { [string]: boolean } = {}
	for _, front in { "", "SL", "SH" } do
		for np = 0, 3 do
			for _, back in { "", "SH", "SL" } do
				local units: { string } = {}
				if front ~= "" then
					table.insert(units, front)
				end
				for _ = 1, np do
					table.insert(units, "P")
				end
				if back ~= "" then
					table.insert(units, back)
				end
				local key = table.concat(units, ",")
				if #units == 0 or seen[key] then
					continue
				end
				seen[key] = true
				local bad = (units[1] == "SL" and lowEdge ~= "wall") or (units[#units] == "SH" and highEdge ~= "wall")
				for i, u in units do
					if (u == "SL" and i ~= 1) or (u == "SH" and i ~= #units) then
						bad = true
					end
				end
				if bad then
					continue
				end
				local gaps: { number } = {}
				gaps[1] = if UNIT[units[1]].low then (if lowEdge == "open" then 0 else WALL_AISLE) else (if lowEdge == "open" then 0.5 else 0.4)
				for i = 2, #units do
					gaps[i] = AISLE
				end
				gaps[#units + 1] = if UNIT[units[#units]].high then (if highEdge == "open" then 0 else WALL_AISLE) else (if highEdge == "open" then 0.5 else 0.4)
				local total = 0
				for _, u in units do
					total += if u == "P" then 2 * cr + 2 * dd else cr + dd
				end
				for _, g in gaps do
					total += g
				end
				if total > hi - lo + 1e-6 then
					continue
				end
				local slack = hi - lo - total
				local spare = slack
				if #units > 1 then
					local add = math.min(1.5, spare / (#units - 1))
					for i = 2, #units do
						gaps[i] += add
					end
					spare -= add * (#units - 1)
				end
				if slackTo == "high" then
					gaps[#units + 1] += spare
				elseif slackTo == "low" then
					gaps[1] += spare
				else
					gaps[1] += spare / 2
					gaps[#units + 1] += spare / 2
				end
				local rows: { Row } = {}
				local pos = lo + gaps[1]
				for i, u in units do
					if u == "SL" then
						table.insert(rows, { c = pos + dd / 2, look = -1 })
						pos += dd + cr
					elseif u == "SH" then
						table.insert(rows, { c = pos + cr + dd / 2, look = 1 })
						pos += cr + dd
					else
						table.insert(rows, { c = pos + cr + dd / 2, look = 1 })
						table.insert(rows, { c = pos + cr + dd + dd / 2, look = -1 })
						pos += 2 * cr + 2 * dd
					end
					pos += gaps[i + 1]
				end
				table.insert(out, { rows = rows, pods = np, slack = slack })
			end
		end
	end
	return out
end

type BlockPlan = { axis: string, variant: string, k: number, rows: { Row }, along1: number, along2: number, across1: number, across2: number, fw: number }
-- Rows run along `axis` ("x": parallel to the entry wall; "z": towards the back wall) inside `rect`.
local function planBlock(rect: Rect, axis: string, n: number, variant: string, lowEdge: string, highEdge: string, slackTo: string, fw: number): BlockPlan?
	local g = DESK[variant] or DESK.bench
	local al1, al2, ac1, ac2
	if axis == "x" then
		al1, al2, ac1, ac2 = rect.x1, rect.x2, rect.z1, rect.z2
	else
		al1, al2, ac1, ac2 = rect.z1, rect.z2, rect.x1, rect.x2
	end
	local k = math.floor((al2 - al1 + 1e-6) / g.p)
	if k < 1 then
		return nil
	end
	local best: RowSet? = nil
	for _, s in rowSets(ac1, ac2, lowEdge, highEdge, g.dd, g.cr, slackTo) do
		if #s.rows * k >= n then
			if not best or #s.rows < #best.rows or (#s.rows == #best.rows and (s.pods > best.pods or (s.pods == best.pods and s.slack > best.slack))) then
				best = s
			end
		end
	end
	if not best then
		return nil
	end
	return { axis = axis, variant = variant, k = k, rows = best.rows, along1 = al1, along2 = al2, across1 = ac1, across2 = ac2, fw = fw }
end

-- Places the stations of a plan. Partial rows are pushed to `alignEnd` (-1 low / +1 high / 0 centre).
-- Returns the free rectangles left in partial rows and behind the last row (for kit furniture).
local function placeBlock(R: R, plan: BlockPlan, n: number, alignEnd: number): { Rect }
	local g = DESK[plan.variant] or DESK.bench
	local freeRects: { Rect } = {}
	local remaining = n
	local maxFoot, minFoot = -math.huge, math.huge
	local function rect(a1: number, a2: number, c1: number, c2: number): Rect
		if plan.axis == "x" then
			return { x1 = a1, x2 = a2, z1 = c1, z2 = c2 }
		end
		return { x1 = c1, x2 = c2, z1 = a1, z2 = a2 }
	end
	for _, row in plan.rows do
		local m = math.min(plan.k, remaining)
		remaining -= m
		local f1 = if row.look > 0 then row.c - g.dd / 2 - g.cr else row.c - g.dd / 2
		local f2 = if row.look > 0 then row.c + g.dd / 2 else row.c + g.dd / 2 + g.cr
		maxFoot, minFoot = math.max(maxFoot, f2), math.min(minFoot, f1)
		local span = m * g.p
		local start
		if alignEnd < 0 then
			start = plan.along1
		elseif alignEnd > 0 then
			start = plan.along2 - span
		else
			start = (plan.along1 + plan.along2) / 2 - span / 2
		end
		for j = 0, m - 1 do
			local s = start + g.p / 2 + j * g.p
			local x, z, yaw
			if plan.axis == "x" then
				x, z, yaw = s, row.c, if row.look > 0 then LOOK.B else LOOK.F
			else
				x, z, yaw = row.c, s, if row.look > 0 then LOOK.R else LOOK.L
			end
			station(R, x, z, yaw, plan.variant)
			stationClaim(R, x, z, yaw, plan.variant)
		end
		-- free part of the row
		if m < plan.k then
			if start - plan.along1 > 3 then
				table.insert(freeRects, rect(plan.along1, start - 0.3, f1, f2))
			end
			if plan.along2 - (start + span) > 3 then
				table.insert(freeRects, rect(start + span + 0.3, plan.along2, f1, f2))
			end
		end
	end
	if plan.across2 - maxFoot > WALL_AISLE + 3 then
		table.insert(freeRects, rect(plan.along1, plan.along2, maxFoot + WALL_AISLE, plan.across2))
	end
	if minFoot - plan.across1 > WALL_AISLE + 3 then
		table.insert(freeRects, rect(plan.along1, plan.along2, plan.across1, minFoot - WALL_AISLE))
	end
	return freeRects
end

-- Takes a w x d footprint out of the free rectangles (either orientation, pushed towards the back);
-- returns its centre and whether it is turned (long side along z).
local function takeFree(R: R, rects: { Rect }, w: number, d: number): (number?, number?, boolean)
	for i, r in rects do
		local rw, rd = r.x2 - r.x1, r.z2 - r.z1
		for _, turned in { false, true } do
			local fw, fd = if turned then d else w, if turned then w else d
			if fw <= rw + 1e-6 and fd <= rd + 1e-6 then
				local cx = r.x1 + fw / 2 + (rw - fw) / 2
				local cz = r.z2 - fd / 2
				if not free(R, cx - fw / 2, cx + fw / 2, cz - fd / 2, cz + fd / 2) then
					continue
				end
				-- shrink the rectangle along its longer side
				if rw - fw >= rd - fd then
					rects[i] = { x1 = r.x1, x2 = r.x1 + (rw - fw) / 2 - 0.5, z1 = r.z1, z2 = r.z2 }
					table.insert(rects, { x1 = cx + fw / 2 + 0.5, x2 = r.x2, z1 = r.z1, z2 = r.z2 })
				else
					rects[i] = { x1 = r.x1, x2 = r.x2, z1 = r.z1, z2 = cz - fd / 2 - 0.5 }
				end
				return cx, cz, turned
			end
		end
	end
	return nil, nil, false
end

---------------------------------------------------------------------------------------------
-- Shared furniture pieces (local builders on top of ArchKit)
---------------------------------------------------------------------------------------------
-- Plant size that varies by room style (small plants keep the part budget).
local function deco(R: R): string
	return if R.style % 2 == 0 then "m" else "s"
end

local function plant(R: R, x: number, z: number, size: string, n: number)
	local r = if size == "s" then 0.8 elseif size == "m" then 1.1 elseif size == "l" then 1.3 else 1.9
	if not free(R, x - r, x + r, z - r, z + r) then
		return
	end
	Kit.plant(R.model, R.cf, at(R, x, z), size, R.seed + n * 17)
	claim(R, "Plant", x - r, x + r, z - r, z + r)
end

-- Plants in the requested corners (fb: "front"/"back", lr: "left"/"right"), skipping door zones.
local function cornerPlant(R: R, fb: string, lr: string, size: string, n: number)
	local gapB = if R.side.back == "facade" then FACADE_GAP else 0.4
	local gapS = if R.side[lr] == "facade" then FACADE_GAP else 0.4
	local r = if size == "s" then 0.8 elseif size == "m" then 1.1 else 1.3
	local x = if lr == "left" then R.inner.left + gapS + r else R.inner.right - gapS - r
	local z = if fb == "back" then R.inner.back - gapB - r else R.inner.front + 0.4 + r
	plant(R, x, z, size, n)
end

local function coatRack(R: R, x: number, z: number)
	if not free(R, x - 0.8, x + 0.8, z - 0.8, z + 0.8) then
		return
	end
	local b = at(R, x, z)
	Kit.cylinder(R.model, R.cf, "CoatRackBase", "y", 0.15, 1.4, b * CF(0, 0.075, 0), C.metal, M.metal)
	Kit.cylinder(R.model, R.cf, "CoatRackPole", "y", 6.0, 0.18, b * CF(0, 3.1, 0), C.metal, M.metal)
	claim(R, "CoatRack", x - 0.8, x + 0.8, z - 0.8, z + 0.8)
end

-- Coat rack in the front corner farthest from the entry door.
local function entryCoatRack(R: R)
	local x = if R.doorX > 0 then R.inner.left + 1.2 else R.inner.right - 1.2
	coatRack(R, x, R.inner.front + 1.2)
end

local function credenza(R: R, side: string, t: number, L: number): boolean
	if solidish(R.side[side]) or R.side[side] == "glass" then
		Kit.sideboard(R.model, R.cf, wallAt(R, side, t), L, R.seed + math.floor(t * 7))
		wallClaim(R, "Credenza", side, t, L + 0.1, 1.7)
		return true
	end
	return false
end

-- Wall screen with an optional owner prompt; free-standing on a floor stand where the wall is glass/open.
local function wallScreen(R: R, side: string, t: number, w: number, kind: string, prompt: { text: string, app: string?, section: string? }?, y: number?): Part
	local mounted = solidish(R.side[side])
	local off = if mounted then 0 elseif R.side[side] == "facade" then FACADE_GAP + 1 else 1.0
	local screen = Kit.tvScreen(R.model, R.cf, wallAt(R, side, t, off), w, kind, R.accent, { y = y or 6.0, floor = not mounted, name = "WallScreen" })
	if not mounted then
		wallClaim(R, "ScreenStand", side, t, w, 1.7, off - 0.95)
	end
	if prompt then
		Kit.prompt(screen, prompt.text, R.owner, prompt.app, prompt.section)
	end
	return screen
end

-- Whiteboard on the wall (mobile stand where the wall is glass/open) + optional activity in front.
local function whiteboard(R: R, side: string, t: number, w: number, text: string, actKind: string?, dept: string?)
	local mounted = solidish(R.side[side])
	local off = if mounted then 0 elseif R.side[side] == "facade" then FACADE_GAP + 0.8 else 0.8
	local base = wallAt(R, side, t, off)
	Kit.whiteboard(R.model, R.cf, base, w, text, R.seed + math.floor(t * 3), { y = 5 })
	if not mounted then
		for _, sx in { -1, 1 } do
			Kit.part(R.model, R.cf, "BoardStand", V3(0.2, 7.2, 0.2), base * CF(sx * (w / 2 + 0.2), 3.6, -0.1), C.metalSoft, M.metal)
		end
		Kit.part(R.model, R.cf, "BoardFoot", V3(w + 0.8, 0.15, 1.8), base * CF(0, 0.075, -0.1), C.metalSoft, M.metal)
		wallClaim(R, "BoardStand", side, t, w + 0.8, 1.8, off - 0.8)
	end
	if actKind then
		local dp = dept or R.dept
		local ax, az = wallPoint(R, side, t, off + 2.6)
		local fx, fz = wallPoint(R, side, t, off)
		-- employees write on the board (Whiteboard) or read the pipeline board (Pipeline)
		local job = if actKind == "Whiteboard" then { JobPose = "write", JobItem = "marker" } else { JobPose = "scan" }
		activity(R, actKind, dp, roleOf(dp), ax, az, fx, fz, nil, { attributes = job })
	end
end

local function acoustic(R: R, side: string, t: number, w: number)
	if solidish(R.side[side]) then
		Kit.acousticPanels(R.model, R.cf, wallAt(R, side, t), math.min(w, 6.6), 2.4, R.seed + 5, { y = 8.6 })
	end
end

-- Floor lamp without a light object (rooms keep their ceiling lights).
local function floorLamp(R: R, x: number, z: number, n: number)
	if free(R, x - 0.7, x + 0.7, z - 0.7, z + 0.7) then
		Kit.floorLamp(R.model, R.cf, at(R, x, z, 0), R.seed + n)
		claim(R, "Lamp", x - 0.7, x + 0.7, z - 0.7, z + 0.7)
	end
end

-- Meeting chair on a sled frame (ArchKit chair, four legs replaced by two side runners).
local function chair(R: R, x: number, z: number, yaw: number, n: number, color: Color3?): Seat
	local base = at(R, x, z, yaw)
	local m = Instance.new("Model")
	m.Name = "Chair"
	local seat = Kit.meetingChair(m, R.cf, base, R.seed + n, if color then { color = color } else nil)
	for _, d in m:GetChildren() do
		if d.Name == "ChairLeg" then
			d:Destroy()
		end
	end
	Kit.part(m, R.cf, "ChairBase", V3(1.9, 1.68, 1.7), base * CF(0, 0.84, 0.05), seat.Color, seat.Material)
	m.Parent = R.model
	return seat
end

-- Low open shelf (wall unit) with a row of files: two parts.
local function lowShelf(R: R, side: string, t: number, w: number)
	local base = wallAt(R, side, t)
	Kit.part(R.model, R.cf, "LowShelf", V3(w, 2.8, 1.3), base * CF(0, 1.4, -0.65), pick({ C.oak, C.white, C.oakDark }, R.seed + 31), M.wood)
	Kit.part(R.model, R.cf, "Files", V3(w - 0.6, 0.9, 1.0), base * CF(0, 1.95, -0.7), pick({ C.fabricSand, C.blue, C.sage }, R.seed + 32), M.smooth, DETAIL)
	wallClaim(R, "LowShelf", side, t, w, 1.4)
end

local function lounge(R: R, x: number, z: number, yaw: number, n: number, armless: boolean?): Seat
	-- built 0.2 lower with the two floor runners removed: the upholstered base stands on the floor
	local m = Instance.new("Model")
	m.Name = "LoungeChair"
	local seat = Kit.loungeChair(m, R.cf, at(R, x, z, yaw) * CF(0, -0.2, 0), R.seed + n)
	for _, d in m:GetChildren() do
		if d.Name == "ChairLeg" or (armless and d.Name == "ArmRest") then
			d:Destroy()
		end
	end
	m.Parent = R.model
	local swap = math.abs(math.sin(RAD(yaw))) > 0.7
	local hw, hd = if swap then 1.45 else 1.5, if swap then 1.5 else 1.45
	claim(R, "LoungeChair", x - hw, x + hw, z - hd, z + hd)
	return seat
end

local function sofa(R: R, x: number, z: number, yaw: number, L: number, n: number): { Seat }
	local m = Instance.new("Model")
	m.Name = "Sofa"
	local seats = Kit.sofa(m, R.cf, at(R, x, z, yaw) * CF(0, -0.2, 0), L, R.seed + n)
	for _, d in m:GetChildren() do
		if d.Name == "SofaLeg" then
			d:Destroy()
		end
	end
	m.Parent = R.model
	return seats
end

local function coffeeTable(R: R, x: number, z: number, w: number, d: number, n: number)
	Kit.coffeeTable(R.model, R.cf, at(R, x, z, 0), R.seed + n, w, d)
	claim(R, "CoffeeTable", x - w / 2, x + w / 2, z - d / 2, z + d / 2)
end

-- Island lab bench (free-standing, front -Z of its frame) with instruments or screens on top.
local function labIsland(R: R, x: number, z: number, yaw: number, L: number, screens: boolean, printer: boolean?): Model?
	local b = at(R, x, z, yaw)
	local made: Model? = nil
	Kit.part(R.model, R.cf, "LabBenchTop", V3(L, 0.25, 3), b * CF(0, 3.075, 0), C.metalSoft, M.slate)
	for _, s in { -1, 1 } do
		Kit.part(R.model, R.cf, "LabBenchBase", V3(2.2, 2.95, 2.6), b * CF(s * (L / 2 - 1.2), 1.475, 0), C.white, M.smooth)
	end
	if screens then
		for _, s in { -1, 1 } do
			Kit.part(R.model, R.cf, "BenchMonitor", V3(2.4, 1.5, 0.12), b * CF(s * L / 4, 4.15, 0.6) * ANG(0, s * 0.2, 0), C.screen, M.smooth, DETAIL)
		end
	else
		Kit.part(R.model, R.cf, "Instrument", V3(1.6, 1.1, 1.3), b * CF(-L / 4, 3.75, 0.3), C.white, M.smooth, DETAIL)
		if printer then
			-- 3D printer (PropFx): prints while a researcher works at the bench beside it (FxStation, set by
			-- the caller), players can start it too
			made = Kit.printer3d(R.model, R.cf, b * CF(L / 4 - 0.1, 3.2, 0.2), R.seed + 7, { prompt = "3D printer", propId = R.room.id .. "_Printer3D" })
		else
			Kit.part(R.model, R.cf, "InstrumentScreen", V3(1.3, 0.9, 0.1), b * CF(L / 4, 3.7, 0.7) * ANG(RAD(-10), 0, 0), C.screen, M.smooth, DETAIL)
		end
	end
	local swap = math.abs(math.sin(RAD(yaw))) > 0.7
	local hw, hd = if swap then 1.5 else L / 2, if swap then L / 2 else 1.5
	claim(R, "LabBench", x - hw, x + hw, z - hd, z + hd)
	return made
end


-- Two LabBench activities in front of a bench whose frame is (x, z, yaw); researchers inspect there.
local function benchActivities(R: R, x: number, z: number, yaw: number, L: number, dept: string): { Model }
	local b = CF(x, 0, z) * ANG(0, RAD(yaw), 0)
	local out: { Model } = {}
	for _, s in { -1, 1 } do
		local p = (b * CF(s * L / 4, 0, -3.0)).Position
		local f = (b * CF(s * L / 4, 0, 0)).Position
		table.insert(out, activity(R, "LabBench", dept, roleOf(dept), p.X, p.Z, f.X, f.Z, nil, { attributes = { JobPose = "inspect" } }))
	end
	return out
end

-- Lab island + its two LabBench activities; the 3D printer (if any) follows the right-hand bench.
local function labBench(R: R, x: number, z: number, yaw: number, L: number, dept: string, printer: boolean)
	local made = labIsland(R, x, z, yaw, L, false, printer)
	local acts = benchActivities(R, x, z, yaw, L, dept)
	if made and acts[2] then
		made:SetAttribute("FxStation", acts[2].Name)
	end
end

---------------------------------------------------------------------------------------------
-- Room shapes
---------------------------------------------------------------------------------------------
-- Feature wall: a solid side wall (the one away from the door when both are solid).
local function featureSide(R: R, awayFromDoor: boolean?): string
	local l, r = solidish(R.side.left), solidish(R.side.right)
	if l and not r then
		return "left"
	elseif r and not l then
		return "right"
	elseif l and r then
		if awayFromDoor and math.abs(R.doorX) > 1 then
			return if R.doorX > 0 then "left" else "right"
		end
		return if R.style % 2 == 0 then "left" else "right"
	end
	return if R.side.left ~= "facade" then "left" else "right"
end

type ShapeA = { fside: string, fw: number, t1: number, t2: number, freeRects: { Rect } }
-- Deep wing room (S zones): entry band along the entry wall, a feature strip (fw deep) along one solid
-- side wall, desk rows in the rest. Big kit pieces go into the returned free rectangles.
local function shapeA(R: R, n: number, variant: string, fwPref: number, axisPref: string, axes: { string }?): ShapeA
	local fside = featureSide(R)
	local other = opposite(fside)
	local otherGap = if R.side[other] == "facade" then FACADE_GAP else 0
	local best: BlockPlan? = nil
	local bestScore = -math.huge
	local axisList: { string } = axes or { axisPref }
	local variants = { variant }
	for _, v in { "bench", "standing" } do
		if v ~= variant then
			table.insert(variants, v)
		end
	end
	for _, axis in axisList do
		-- the strip keeps a 4-stud walkway in front of the wall furniture: rows parallel to the entry wall
		-- end at it, rows towards the back have their chairs backing onto it
		local fws: { number } = { math.max(fwPref, STRIP + 4), STRIP + 4 }
		for _, fw in fws do
			for _, v in variants do
				local rect: Rect
				if fside == "left" then
					rect = { x1 = R.inner.left + fw, x2 = R.inner.right - otherGap, z1 = ENTRY, z2 = R.zEnd }
				else
					rect = { x1 = R.inner.left + otherGap, x2 = R.inner.right - fw, z1 = ENTRY, z2 = R.zEnd }
				end
				local low, high = "open", "wall"
				if axis == "z" then
					low, high = if fside == "left" then "open" else "wall", if fside == "left" then "wall" else "open"
				end
				local plan = planBlock(rect, axis, n, v, low, high, if axis == "x" then "high" else "edges", fw)
				if plan then
					local score = (if v == variant then 5000 elseif v == "bench" then 2500 else 0) + (if axis == axisPref then 2000 else 0) - #plan.rows * 300 + fw * 10
					if score > bestScore then
						best, bestScore = plan, score
					end
				end
			end
		end
	end
	local t1, t2 = ENTRY + 0.5, R.zEnd
	if not best then
		table.insert(R.issues, string.format("%s: no desk arrangement for %d desks", R.room.id, n))
		return { fside = fside, fw = fwPref, t1 = t1, t2 = t2, freeRects = {} }
	end
	local plan = best :: BlockPlan
	local align = if plan.axis == "x" then (if fside == "left" then -1 else 1) else -1
	local freeRects = placeBlock(R, plan, n, align)
	return { fside = fside, fw = plan.fw, t1 = t1, t2 = t2, freeRects = freeRects }
end

type ShapeB = { cx1: number, cx2: number, backFree: { Rect } }
-- Shallow room (I3 zones): central aisle from the door to the back wall, desks along both side walls
-- (users facing the walls), front-aligned so the back corners stay free.
local function shapeB(R: R, nL: number, nR: number, variant: string): ShapeB
	local g = DESK[variant] or DESK.bench
	local z1 = R.inner.front + 0.6
	local cx1, cx2 = R.inner.left + 0.4 + g.dd + g.cr, R.inner.right - 0.4 - g.dd - g.cr
	local backFree: { Rect } = {}
	for _, s in { "left", "right" } do
		local count = if s == "left" then nL else nR
		local x = if s == "left" then R.inner.left + 0.4 + g.dd / 2 else R.inner.right - 0.4 - g.dd / 2
		local yaw = if s == "left" then LOOK.L else LOOK.R
		for i = 1, count do
			local z = z1 + g.p / 2 + (i - 1) * g.p
			station(R, x, z, yaw, variant)
			stationClaim(R, x, z, yaw, variant)
		end
		local zEndRow = z1 + count * g.p
		local x1 = if s == "left" then R.inner.left else cx2
		local x2 = if s == "left" then cx1 else R.inner.right
		if R.inner.back - zEndRow > 3 then
			table.insert(backFree, { x1 = x1, x2 = x2, z1 = zEndRow + 0.4, z2 = R.inner.back - 0.3 })
		end
	end
	return { cx1 = cx1, cx2 = cx2, backFree = backFree }
end

local function shapeOf(R: R): string
	if R.D >= 26 and R.W >= 22 then
		return "A"
	elseif R.W <= 22 and R.D >= 28 then
		return "C"
	end
	return "B"
end

-- Variant of the desks of a room: kind first, then department + style (no 13-wide trading cockpits in rows).
local function variantFor(R: R): string
	local v = Kit.deskVariant(R.dept, R.room.kind, R.style)
	if v == "trading" then
		v = "dual"
	end
	return v
end

---------------------------------------------------------------------------------------------
-- Work room kits
---------------------------------------------------------------------------------------------
local TEAM_TEXT: { [string]: string } = {
	data = "SPRINT · DATA QUALITY\n1  dedupe web crawl\n2  label review queue\n3  tokenizer refresh",
	engineering = "SPRINT · TRAINING STACK\n1  eval harness\n2  checkpoint restore\n3  latency budget",
	design = "ARCHITECTURE NOTES\nlayers · heads · context\nmixture of experts?",
	training = "TRAINING RUNS\nloss curve review 10:00\nnext checkpoint: 6h",
	research = "OPEN QUESTIONS\nscaling laws · reasoning\nread: 3 new papers",
	evaluation = "BENCHMARK PLAN\ncoding · maths · reasoning\nsafety review Friday",
	growth = "GO-TO-MARKET\npricing · partners · launch\ncustomer calls: 4",
	deployment = "RELEASE CHECKLIST\nstaging · canary · docs\nrollback plan",
	operations = "PEOPLE & COMPANY\nonboarding · reviews\nteam offsite",
}

-- Team board (department screen + owner prompt) with a credenza, a whiteboard with its activity and,
-- for data rooms, a pipeline board, along a wall from t1 to t2. Returns the next free coordinate.
local function teamWall(R: R, side: string, t1: number, t2: number): number
	local app, section, _, screenKind = deptInfo(R.dept)
	local t = t1
	if t2 - t >= 7.5 then
		if credenza(R, side, t + 3.5, 6) then
			-- team printer on the credenza (PropFx paper + light)
			Kit.deskPrinter(R.model, R.cf, wallAt(R, side, t + 3.5) * CF(0, 2.82, -0.85), { prompt = "Team printer", propId = R.room.id .. "_Printer" })
		end
		wallScreen(R, side, t + 3.5, 6, screenKind, { text = "Team board · " .. R.room.name, app = app, section = section }, 6.3)
		t += 8
	end
	if t2 - t >= 6.5 then
		whiteboard(R, side, t + 3, 5.5, TEAM_TEXT[R.dept] or TEAM_TEXT.operations, "Whiteboard")
		t += 7
	end
	if R.dept == "data" and t2 - t >= 6.5 then
		whiteboard(R, side, t + 3, 5.5, "DATA PIPELINE\ncollect → filter → clean → tokenize", "Pipeline")
		t += 7
	end
	return t
end

local function kitTeam(R: R)
	local n = R.room.desks or 0
	local variant = variantFor(R)
	if shapeOf(R) == "A" then
		local s = shapeA(R, n, variant, 5.5, if R.style % 2 == 0 then "x" else "z", { "x", "z" })
		teamWall(R, s.fside, s.t1, s.t2)
		acoustic(R, opposite(s.fside), (s.t1 + s.t2) / 2, 8)
		cornerPlant(R, "back", opposite(s.fside), deco(R), 1)
		if n >= 10 then
			cornerPlant(R, "back", s.fside, "s", 2)
		end
		if n >= 8 then
			entryCoatRack(R)
		end
	else
		local nL = math.ceil(n / 2)
		local b = shapeB(R, nL, n - nL, variant)
		local w = R.inner.right - R.inner.left
		local app, section, _, screenKind = deptInfo(R.dept)
		wallScreen(R, "back", -3.6, 6, screenKind, { text = "Team board · " .. R.room.name, app = app, section = section })
		whiteboard(R, "back", 3.6, 5, TEAM_TEXT[R.dept] or TEAM_TEXT.operations, "Whiteboard")
		for i, r in b.backFree do
			if r.x2 - r.x1 > 3 then
				plant(R, (r.x1 + r.x2) / 2, r.z2 - 1.3, "s", i)
			end
		end
		if w > 24 then
			entryCoatRack(R)
		end
	end
end

local function kitArchitecture(R: R)
	local n = R.room.desks or 0
	local s = shapeA(R, n, if R.style % 2 == 0 then "ldesk" else "bench", 7, "x")
	local side = s.fside
	-- sketches and the design screen on the feature wall
	local app = "lab"
	local t = s.t1
	Kit.pinboard(R.model, R.cf, wallAt(R, side, t + 2.5), 4.5, 3.2, R.seed + 1, { y = 5.6 })
	wallScreen(R, side, t + 9, 6.4, "design", { text = "Design screen · model architecture", app = app }, 6.0)
	if s.t2 - (t + 13) >= 5 then
		Kit.pinboard(R.model, R.cf, wallAt(R, side, t + 15.5), 4.5, 3.2, R.seed + 2, { y = 5.6 })
	end
	-- big studio table with drawings, physical model display
	local x, z, turned = takeFree(R, s.freeRects, 9, 5)
	if x and z then
		local yaw = if turned then 90 else 0
		Kit.meetingTable(R.model, R.cf, at(R, x, z, yaw), "rect", 8, 4, R.seed + 3)
		local b = at(R, x, z, yaw)
		for i = 1, 3 do
			Kit.part(R.model, R.cf, "Drawing", V3(1.6, 0.05, 2.2), b * CF(-3 + i * 1.6, 3.165, Kit.range(R.seed, i, -0.8, 0.8)) * ANG(0, Kit.range(R.seed, i + 3, -0.3, 0.3), 0), C.white, M.smooth, DETAIL)
		end
		claim(R, "StudioTable", x - (if turned then 2.5 else 4.5), x + (if turned then 2.5 else 4.5), z - (if turned then 4.5 else 2.5), z + (if turned then 4.5 else 2.5))
	end
	local mx, mz = takeFree(R, s.freeRects, 3.6, 3.6)
	if mx and mz then
		local b = at(R, mx, mz, 0)
		Kit.part(R.model, R.cf, "ModelPlinth", V3(3, 3.2, 3), b * CF(0, 1.6, 0), C.white, M.smooth)
		for i = 1, 4 do
			local w = Kit.range(R.seed, i + 20, 0.5, 1.0)
			local h = Kit.range(R.seed, i + 30, 0.4, 1.8)
			Kit.part(R.model, R.cf, "ModelBlock", V3(w, h, Kit.range(R.seed, i + 40, 0.5, 1.0)), b * CF(-0.65 + ((i - 1) % 2) * 1.3, 3.2 + h / 2, -0.65 + math.floor((i - 1) / 2) * 1.3), pick({ C.white, C.oakLight, C.stone, C.sageLight }, R.seed + i), M.smooth, DETAIL)
		end
		claim(R, "ModelDisplay", mx - 1.5, mx + 1.5, mz - 1.5, mz + 1.5)
	end
	-- large-format plotter for the model diagrams (PropFx)
	local px, pz, pturned = takeFree(R, s.freeRects, 6, 3)
	if px and pz then
		Kit.plotter(R.model, R.cf, at(R, px, pz, if pturned then 90 else 0), 5, { propId = R.room.id .. "_Plotter" })
		claim(R, "Plotter", px - (if pturned then 1 else 2.6), px + (if pturned then 1 else 2.6), pz - (if pturned then 2.6 else 1), pz + (if pturned then 2.6 else 1))
	end
	cornerPlant(R, "back", opposite(side), deco(R), 1)
	entryCoatRack(R)
end

-- Data lab (shallow): data-quality wall of three screens at the back with the Pipeline activity, dual
-- monitor desks along the side walls, a small server shelf in a back corner.
local function dataWall(R: R, t: number, kinds: { string }, prompt: { text: string, app: string?, section: string? }?)
	local side = "back"
	local mounted = solidish(R.side.back)
	local off = if mounted then 0 elseif R.side.back == "facade" then FACADE_GAP + 0.6 else 0.6
	local base = wallAt(R, side, t, off)
	local sw, sh, gap = 4.6, 2.6, 0.15
	local total = #kinds * sw + (#kinds - 1) * gap
	Kit.part(R.model, R.cf, "ScreenWallFrame", V3(total + 0.5, sh + 0.5, 0.25), base * CF(0, 5.6, -0.125), C.metal, M.metal)
	if not mounted then
		for _, s in { -1, 1 } do
			Kit.part(R.model, R.cf, "ScreenWallLeg", V3(0.3, 4.1, 0.3), base * CF(s * (total / 2 - 0.5), 2.05, -0.125), C.metal, M.metal)
		end
		Kit.part(R.model, R.cf, "ScreenWallFoot", V3(total, 0.15, 1.4), base * CF(0, 0.075, -0.4), C.metal, M.metal)
		wallClaim(R, "ScreenWall", side, t, total + 0.5, 1.2, off - 0.1)
	end
	for i, kind in kinds do
		local s = Kit.screen(R.model, R.cf, "DataWall" .. i, V3(sw, sh, 0.1), base * CF(-total / 2 + sw / 2 + (i - 1) * (sw + gap), 5.6, -0.3), kind, R.accent)
		if prompt and i == math.ceil(#kinds / 2) then
			Kit.prompt(s, prompt.text, R.owner, prompt.app, prompt.section)
		end
	end
end

local function serverShelf(R: R, x: number, z: number, yaw: number)
	local b = at(R, x, z, yaw)
	Kit.part(R.model, R.cf, "ServerShelf", V3(2.4, 5.2, 2.2), b * CF(0, 2.6, 0), C.screen, M.metal)
	for i = 1, 3 do
		Kit.part(R.model, R.cf, "ServerUnit", V3(2.0, 0.6, 0.06), b * CF(0, 1.0 + i * 1.1, -1.12), C.metalSoft, M.metal, DETAIL)
	end
	Kit.part(R.model, R.cf, "ServerLeds", V3(0.12, 3.4, 0.04), b * CF(0.85, 2.6, -1.14), C.statusGood, M.neon, DETAIL)
	claim(R, "ServerShelf", x - 1.3, x + 1.3, z - 1.3, z + 1.3)
end

local function kitDatalab(R: R)
	local n = R.room.desks or 0
	if shapeOf(R) ~= "B" then
		local s = shapeA(R, n, "dual", 7, "x")
		teamWall(R, s.fside, s.t1, s.t2)
		return
	end
	local nL = math.ceil(n / 2)
	local b = shapeB(R, nL, n - nL, "dual")
	local dept = R.dept
	dataWall(R, 0, { "data", "data", "data" }, { text = "Data quality wall", app = "data" })
	local ax, az = wallPoint(R, "back", 0, 3.2)
	activity(R, "Pipeline", dept, roleOf(dept), ax, az, 0, R.inner.back, nil, { attributes = { JobPose = "scan" } })
	for i, r in b.backFree do
		if r.x2 - r.x1 >= 2.8 and r.z2 - r.z1 >= 2.8 then
			local x = if r.x1 < 0 then r.x1 + 1.5 else r.x2 - 1.5
			serverShelf(R, x, r.z2 - 1.4, FRONT.F)
			break
		end
	end
	cornerPlant(R, "front", if R.doorX > 0 then "left" else "right", "s", 1)
end

-- Training control: curved console rows facing a three-screen video wall on a solid side wall,
-- supervisor cockpit behind.
local function kitControl(R: R)
	local n = R.room.desks or 0
	if shapeOf(R) ~= "A" then
		local nL = math.ceil(n / 2)
		shapeB(R, nL, n - nL, "dual")
		dataWall(R, 0, { "training", "compute", "training" }, { text = "Training control wall", app = "lab" })
		return
	end
	local side = featureSide(R, true)
	local sgn = if side == "left" then 1 else -1 -- rows advance away from the wall in +x for a left wall
	local wallX = if side == "left" then R.inner.left else R.inner.right
	local farX = if side == "left" then R.inner.right - (if R.side.right == "facade" then FACADE_GAP else 0) else R.inner.left + (if R.side.left == "facade" then FACADE_GAP else 0)
	-- rows run along z between the entry band and the facade gap
	local z1 = ENTRY + 0.2
	local z2 = R.zEnd
	local L = z2 - z1
	local zc = (z1 + z2) / 2
	local Rv = 30 -- console rows lie on arcs centred beyond the video wall
	local function sagOf(count: number, p: number): number
		return Rv * (1 - math.cos((count - 1) / 2 * p / Rv))
	end
	-- aisles between console rows stay wide (turned chairs eat into them); the arc is dropped from the
	-- rear rows, then from all rows, before the viewing distance shrinks
	type Plan = { variant: string, rows: { number }, vd: number, aisle: number, arcs: number }
	local chosen: Plan? = nil
	for _, v in { "dual", "bench", "standing" } do
		local g = DESK[v]
		local k = math.floor(L / g.p)
		if k < 2 or chosen then
			continue
		end
		local rows: { number } = {}
		local left = n
		while left > 0 do
			table.insert(rows, math.min(k, left))
			left -= math.min(k, left)
		end
		for _, vd in { 5.5, 4.5, 4.0 } do
			for _, arcs in { #rows, 1, 0 } do
				for _, aisle in { 4.8, 4.4 } do
					local extent = vd + WALL_AISLE
					for i, c in rows do
						local sup = i == #rows and (c - 1) * g.p + DESK.trading.p <= L
						extent += if sup then 5.8 else g.dd + g.cr + (if i <= arcs then sagOf(c, g.p) else 0)
						if i < #rows then
							extent += aisle
						end
					end
					if not chosen and extent <= math.abs(farX - wallX) then
						chosen = { variant = v, rows = rows, vd = vd, aisle = aisle, arcs = arcs }
					end
				end
			end
		end
	end
	-- video wall
	local frameW = 3 * 6.2 + 2 * 0.15
	local base = wallAt(R, side, zc)
	Kit.part(R.model, R.cf, "VideoWallFrame", V3(frameW + 0.6, 4.2, 0.2), base * CF(0, 6.4, -0.1), C.metal, M.metal)
	for i, kind in { "training", "compute", "training" } do
		local s = Kit.screen(R.model, R.cf, "VideoWall" .. i, V3(6.2, 3.6, 0.1), base * CF(-frameW / 2 + 3.1 + (i - 1) * 6.35, 6.4, -0.25), kind, R.accent)
		if i == 2 then
			Kit.prompt(s, "Training control wall", R.owner, "lab", nil)
		end
	end
	Kit.part(R.model, R.cf, "VideoWallSill", V3(frameW + 0.6, 0.3, 0.6), base * CF(0, 4.15, -0.3), C.metal, M.metal, DETAIL)
	if not chosen then
		table.insert(R.issues, R.room.id .. ": control room rows do not fit, using rows")
		shapeA(R, n, "bench", 5.8, "x")
		return
	end
	local ch = chosen :: Plan
	local g = DESK[ch.variant]
	local look = if side == "left" then LOOK.L else LOOK.R
	local rowFront = wallX + sgn * ch.vd -- desk front edge of the current row
	for ri, count in ch.rows do
		local supervisor = ri == #ch.rows and (count - 1) * g.p + DESK.trading.p <= L
		local depth
		if supervisor then
			-- supervisor cockpit in the middle of the last row, remaining desks beside it
			local variants: { string } = {}
			local total = 0
			for i = 1, count do
				local v = if i == math.ceil(count / 2) then "trading" else ch.variant
				table.insert(variants, v)
				total += DESK[v].p
			end
			depth = 5.8
			local s = zc - total / 2
			for _, v in variants do
				local w = DESK[v].p
				local zz = s + w / 2
				local half = if v == "trading" then 1.6 else DESK[v].dd / 2
				station(R, rowFront + sgn * half, zz, look, v)
				local fx1, fx2 = rowFront, rowFront + sgn * depth
				claim(R, "Desk", math.min(fx1, fx2), math.max(fx1, fx2), zz - w / 2, zz + w / 2)
				s += w
			end
		else
			local step = if ri <= ch.arcs then g.p / Rv else 0
			for i = 1, count do
				local th = (i - (count + 1) / 2) * step
				local sag = Rv * (1 - math.cos(th))
				local zz = if step > 0 then zc + Rv * math.sin(th) else zc + (i - (count + 1) / 2) * g.p
				station(R, rowFront + sgn * (sag + g.dd / 2), zz, look - sgn * math.deg(th), ch.variant)
				local fx1, fx2 = rowFront + sgn * sag, rowFront + sgn * (sag + g.dd + g.cr)
				claim(R, "Console", math.min(fx1, fx2), math.max(fx1, fx2), zz - g.p / 2 + 0.3, zz + g.p / 2 - 0.3)
			end
			depth = g.dd + g.cr + (if step > 0 then sagOf(count, g.p) else 0)
		end
		rowFront += sgn * (depth + ch.aisle)
	end
	cornerPlant(R, "back", opposite(side), deco(R), 1)
end

local function kitEvaluation(R: R)
	local n = R.room.desks or 0
	local dept = R.dept
	if shapeOf(R) == "B" then
		local nL = math.ceil(n / 2)
		local b = shapeB(R, nL, n - nL, "dual")
		wallScreen(R, "back", 0, 7, "evaluation", { text = "Benchmark wall", app = "lab", section = "evaluation" })
		local z = math.max(ENTRY + 4.5, (b.backFree[1] and b.backFree[1].z1 or 9) - 1)
		labIsland(R, 0, z, FRONT.F, 6.4, true)
		benchActivities(R, 0, z, FRONT.F, 6.4, dept)
		return
	end
	local s = shapeA(R, n, if R.style % 2 == 0 then "dual" else "bench", 7, "x")
	local side = s.fside
	wallScreen(R, side, s.t1 + 4.5, 7, "evaluation", { text = "Benchmark wall", app = "lab", section = "evaluation" })
	whiteboard(R, side, s.t1 + 12.5, 5, "EVAL MATRIX\ncoding · maths · reasoning\nreliability · safety")
	for i = 1, 2 do
		local x, z, turned = takeFree(R, s.freeRects, 7, 6.5)
		if x and z then
			local yaw = if turned then FRONT.L else FRONT.F
			local bx, bz = x, z + (if turned then 0 else 1.6)
			if turned then
				bx = x + 1.6
			end
			labIsland(R, bx, bz, yaw, 6.4, true)
			benchActivities(R, bx, bz, yaw, 6.4, dept)
		elseif i == 1 then
			-- no free stretch: one comparison bench in the feature strip
			local tx = s.t2 - 4
			local wx, wz = wallPoint(R, side, tx, 1.6)
			labIsland(R, wx, wz, WALL_YAW[side], 6.4, true)
			benchActivities(R, wx, wz, WALL_YAW[side], 6.4, dept)
		end
	end
	cornerPlant(R, "back", opposite(side), deco(R), 1)
end

local function kitLaunch(R: R)
	local n = R.room.desks or 0
	local s = shapeA(R, n, if R.style % 2 == 0 then "standing" else "bench", 7, "x")
	local side = s.fside
	whiteboard(R, side, s.t1 + 3.2, 6, "PRICING · PLANS\nFree · Pro · Team · Enterprise\nAPI · per 1M tokens")
	wallScreen(R, side, s.t1 + 10.5, 6, "growth", { text = "Growth dashboard", app = "market" }, 6.0)
	if s.t2 - (s.t1 + 14) >= 6.5 then
		wallScreen(R, side, s.t1 + 17.5, 6, "deployment", { text = "Release control", app = "lab", section = "release" }, 6.0)
	else
		wallScreen(R, opposite(side), (s.t1 + s.t2) / 2, 6, "deployment", { text = "Release control", app = "lab", section = "release" }, 6.0)
	end
	-- war-room table (standing height) with stools
	local x, z, turned = takeFree(R, s.freeRects, 10, 6)
	if x and z then
		local yaw = if turned then 90 else 0
		local b = at(R, x, z, yaw)
		Kit.part(R.model, R.cf, "WarRoomTable", V3(8, 0.25, 3.4), b * CF(0, 3.9, 0), C.oakDark, M.wood)
		for _, sx in { -1, 1 } do
			Kit.part(R.model, R.cf, "WarRoomLeg", V3(0.4, 3.8, 2.6), b * CF(sx * 3.3, 1.9, 0), C.metal, M.metal)
		end
		Kit.part(R.model, R.cf, "LaunchPlan", V3(3, 0.05, 2), b * CF(-1.5, 4.04, 0), C.white, M.smooth, DETAIL)
		for i, sx in { -2.2, 2.2 } do
			Kit.stool(R.model, R.cf, b * CF(sx, 0, -2.6) * ANG(0, math.pi, 0), R.seed + i, 3.0)
		end
		claim(R, "WarRoomTable", x - (if turned then 3 else 5), x + (if turned then 3 else 5), z - (if turned then 5 else 3), z + (if turned then 5 else 3))
	end
	cornerPlant(R, "back", opposite(side), deco(R), 1)
	entryCoatRack(R)
end

local function headsets(R: R)
	for _, d in R.model:GetChildren() do
		if d:IsA("Model") and d:GetAttribute("WorkstationType") == "Computer" then
			local top = d:FindFirstChild("DeskTop")
			if top and top:IsA("BasePart") then
				local p = top.CFrame * CF(-1.9, top.Size.Y / 2 + 0.1, 0.4)
				local h = Instance.new("Part")
				h.Name = "Headset"
				h.Anchored = true
				h.CanCollide = false
				h.CanTouch = false
				h.CanQuery = false
				h.CastShadow = false
				h.Size = V3(0.8, 0.2, 0.7)
				h.CFrame = p
				h.Color = C.fabricCharcoal
				h.Material = M.rubber
				h.Parent = d
			end
		end
	end
end

local function softCorner(R: R, rects: { Rect })
	local x, z, turned = takeFree(R, rects, 9, 4.2)
	if not (x and z) then
		return
	end
	if turned then
		lounge(R, x, z - 2.6, FRONT.B, 1)
		lounge(R, x, z + 2.6, FRONT.F, 2)
	else
		lounge(R, x - 3, z, FRONT.R, 1)
		lounge(R, x + 3, z, FRONT.L, 2)
	end
	Kit.coffeeTable(R.model, R.cf, at(R, x, z, if turned then 90 else 0), R.seed + 4, 2.4, 1.8)
end

local function kitSupport(R: R)
	local n = R.room.desks or 0
	local shape = shapeOf(R)
	if shape == "A" then
		local s = shapeA(R, n, "bench", 7, "x")
		wallScreen(R, s.fside, s.t1 + 4.5, 7, "customers", { text = "Customer wall", app = "empire", section = "contracts" })
		whiteboard(R, s.fside, s.t1 + 12.5, 5, "SUPPORT QUEUE\nP1 · 0   P2 · 3   P3 · 11\nfirst response < 2h")
		softCorner(R, s.freeRects)
		cornerPlant(R, "back", opposite(s.fside), deco(R), 1)
		entryCoatRack(R)
	elseif shape == "C" then
		-- desks along the solid side wall (back part), soft seating at the front of the other side
		local side = if solidish(finishAt(R.tier, R.room, R.sideFace.left, 0)) then "left" else "right"
		local probeT = R.D * 0.6
		local lf = finishAt(R.tier, R.room, R.sideFace.left, (R.room.x1 + R.room.x2) / 2)
		side = if solidish(R.side.left) or solidish(lf) then "left" else "right"
		local g = DESK.bench
		local x = if side == "left" then R.inner.left + 0.4 + g.dd / 2 else R.inner.right - 0.4 - g.dd / 2
		local z0 = R.zEnd - WALL_AISLE - n * g.p
		for i = 1, n do
			local z = z0 + g.p / 2 + (i - 1) * g.p
			station(R, x, z, if side == "left" then LOOK.L else LOOK.R, "bench")
			stationClaim(R, x, z, if side == "left" then LOOK.L else LOOK.R, "bench")
		end
		local _ = probeT
		local o = opposite(side)
		local sx = if o == "left" then R.inner.left + 4.5 else R.inner.right - 4.5
		local rects: { Rect } = { { x1 = sx - 4.5, x2 = sx + 4.5, z1 = ENTRY + 0.5, z2 = ENTRY + 5.5 } }
		softCorner(R, rects)
		wallScreen(R, "back", 0, 7, "customers", { text = "Customer wall", app = "empire", section = "contracts" })
		cornerPlant(R, "back", o, deco(R), 1)
	else
		local nL = math.ceil(n / 2)
		shapeB(R, nL, n - nL, "bench")
		wallScreen(R, "back", 0, 7, "customers", { text = "Customer wall", app = "empire", section = "contracts" })
	end
	headsets(R)
end

local function deviceTable(R: R, x: number, z: number, yaw: number)
	local b = at(R, x, z, yaw)
	Kit.part(R.model, R.cf, "DeviceTable", V3(6, 0.25, 3), b * CF(0, 3.075, 0), C.oakLight, M.wood)
	for _, s in { -1, 1 } do
		Kit.part(R.model, R.cf, "TableLeg", V3(0.3, 2.95, 2.6), b * CF(s * 2.6, 1.475, 0), C.metal, M.metal)
	end
	for i = 1, 3 do
		Kit.part(R.model, R.cf, "TestPhone", V3(0.5, 0.06, 1.0), b * CF(-2.3 + i * 0.8, 3.23, -0.6) * ANG(0, Kit.range(R.seed, i, -0.3, 0.3), 0), C.screen, M.smooth, DETAIL)
	end
	Kit.part(R.model, R.cf, "TestTablet", V3(1.3, 0.06, 1.8), b * CF(1.4, 3.23, -0.3), C.metal, M.smooth, DETAIL)
	Kit.part(R.model, R.cf, "TestTabletStand", V3(1.3, 1.8, 0.08), b * CF(1.4, 4.1, 0.9) * ANG(RAD(-15), 0, 0), C.screen, M.smooth, DETAIL)
	local swap = math.abs(math.sin(RAD(yaw))) > 0.7
	claim(R, "DeviceTable", x - (if swap then 1.5 else 3), x + (if swap then 1.5 else 3), z - (if swap then 3 else 1.5), z + (if swap then 3 else 1.5))
end

local function kitStudio(R: R)
	local n = R.room.desks or 0
	if shapeOf(R) == "B" then
		local nL = math.ceil(n / 2)
		shapeB(R, nL, n - nL, "ldesk")
		wallScreen(R, "back", -3.8, 6, "product", { text = "Product board", app = "studio" })
		Kit.pinboard(R.model, R.cf, wallAt(R, "back", 3.8, if solidish(R.side.back) then 0 else 0.3), 5, 3.2, R.seed + 1, { y = 5.6 })
		deviceTable(R, 0, ENTRY + 5, 0)
		return
	end
	local s = shapeA(R, n, if R.style % 2 == 0 then "ldesk" else "bench", 7, "x")
	local side = s.fside
	Kit.pinboard(R.model, R.cf, wallAt(R, side, s.t1 + 2.6), 4.6, 3.4, R.seed + 1, { y = 5.6, name = "MoodBoard" })
	wallScreen(R, side, s.t1 + 9.5, 6.4, "product", { text = "Product board", app = "studio" })
	if s.t2 - (s.t1 + 13.5) >= 5 then
		Kit.pinboard(R.model, R.cf, wallAt(R, side, s.t1 + 16.2), 4.6, 3.4, R.seed + 2, { y = 5.6, name = "MoodBoard" })
	end
	local x, z, turned = takeFree(R, s.freeRects, 7, 5)
	if x and z then
		deviceTable(R, x, z, if turned then 90 else 0)
	end
	cornerPlant(R, "back", opposite(side), deco(R), 1)
	entryCoatRack(R)
end

local function kitPlatform(R: R)
	local n = R.room.desks or 0
	if shapeOf(R) == "B" then
		-- one row of standing desks facing the NOC wall at the back
		local g = DESK.standing
		local total = n * g.p
		local z = ENTRY + CR + g.dd / 2 + 0.1
		for i = 1, n do
			local x = -total / 2 + g.p / 2 + (i - 1) * g.p
			station(R, x, z, LOOK.B, "standing")
			stationClaim(R, x, z, LOOK.B, "standing")
		end
		dataWall(R, 0, { "platform", "platform", "platform" }, { text = "NOC wall", app = "market" })
		cornerPlant(R, "back", "left", deco(R), 1)
		return
	end
	local s = shapeA(R, n, "dual", 7, "x")
	local side = s.fside
	local base = wallAt(R, side, (s.t1 + s.t2) / 2)
	Kit.part(R.model, R.cf, "NocFrame", V3(20.6, 4.0, 0.2), base * CF(0, 6.4, -0.1), C.metal, M.metal)
	for i = 1, 3 do
		local sc = Kit.screen(R.model, R.cf, "NocWall" .. i, V3(6.6, 3.6, 0.1), base * CF(-6.75 + (i - 1) * 6.75, 6.4, -0.25), "platform", R.accent)
		if i == 2 then
			Kit.prompt(sc, "NOC wall · platform", R.owner, "market", nil)
		end
	end
	cornerPlant(R, "back", opposite(side), deco(R), 1)
end

local function kitLab(R: R)
	local n = R.room.desks or 0
	local dept = R.dept
	if shapeOf(R) == "B" then
		local nL = math.ceil(n / 2)
		local b = shapeB(R, nL, n - nL, "lab")
		local z = ENTRY + 4
		labBench(R, 0, z, FRONT.F, 6.4, dept, true)
		wallScreen(R, "back", -4, 5.6, "research", { text = "Research screen", app = "empire", section = "research" })
		whiteboard(R, "back", 4, 5, "EXPERIMENT LOG\nhypothesis · run · result", "Whiteboard")
		local _ = b
		return
	end
	local s = shapeA(R, n, "lab", 7, "x")
	local side = s.fside
	wallScreen(R, side, s.t1 + 4, 6, "research", { text = "Research screen", app = "empire", section = "research" })
	whiteboard(R, side, s.t1 + 11.5, 5.5, "EXPERIMENT LOG\nhypothesis · run · result", "Whiteboard")
	local placedBench = false
	for _ = 1, 2 do
		local x, z, turned = takeFree(R, s.freeRects, 7, 6.5)
		if x and z then
			local yaw = if turned then FRONT.L else FRONT.F
			local bx, bz = x, z
			if turned then
				bx += 1.6
			else
				bz += 1.6
			end
			labBench(R, bx, bz, yaw, 6.4, dept, not placedBench)
			placedBench = true
		end
	end
	if not placedBench and s.t2 - (s.t1 + 15) >= 7 then
		local wx, wz = wallPoint(R, side, s.t2 - 4, 1.6)
		labBench(R, wx, wz, WALL_YAW[side], 6.4, dept, true)
	end
	cornerPlant(R, "back", opposite(side), deco(R), 1)
end

-- GPU test bench: workbench against a wall with two open chassis on top.
local function gpuBench(R: R, side: string, t: number, L: number)
	local base = wallAt(R, side, t)
	Kit.workbench(R.model, R.cf, base, L, R.seed + math.floor(t))
	for _, sx in { -L / 4, L / 4 } do
		local c = base * CF(sx, 3.2, -1.4)
		Kit.part(R.model, R.cf, "ChassisTray", V3(2.2, 0.15, 1.8), c * CF(0, 0.075, 0), C.metalSoft, M.metal, DETAIL)
		for k = -1, 1, 2 do
			Kit.part(R.model, R.cf, "GPUCard", V3(1.7, 0.9, 0.18), c * CF(0, 0.6, k * 0.35), A.department.compute, M.metal, DETAIL)
		end
	end
	wallClaim(R, "GpuBench", side, t, L, 2.7)
end

local function kitHwlab(R: R)
	local n = R.room.desks or 0
	local dept = "compute"
	local nL = math.min(n, 2)
	local b = shapeB(R, nL, 0, "lab")
	-- right wall: remaining desks at the front, GPU benches behind them
	local g = DESK.lab
	local x = R.inner.right - 0.4 - g.dd / 2
	local zRow = R.inner.front + 0.6
	for i = 1, n - nL do
		local z = zRow + g.p / 2 + (i - 1) * g.p
		station(R, x, z, LOOK.R, "lab")
		stationClaim(R, x, z, LOOK.R, "lab")
	end
	local benchStart = zRow + (n - nL) * g.p + 0.6
	local benchLen = math.min(8, R.inner.back - benchStart - 0.4)
	if benchLen >= 5 then
		local t = benchStart + benchLen / 2
		gpuBench(R, "right", t, benchLen)
		Kit.toolWall(R.model, R.cf, wallAt(R, "right", t), math.min(5, benchLen - 1), R.seed + 9, { y = 8.4 })
		for k = -1, 1, 2 do
			local ax, az = wallPoint(R, "right", t + k * benchLen / 4, 4.2)
			local fx, fz = wallPoint(R, "right", t + k * benchLen / 4, 1.3)
			activity(R, "LabBench", if k < 0 then dept else "engineering", "engineer", ax, az, fx, fz)
		end
	end
	wallScreen(R, "back", (b.cx1 + 0) / 2 - 1, 6, "compute", { text = "Compute monitor", app = "compute" })
	cornerPlant(R, "front", "right", "s", 1)
end

local function interviewTable(R: R, x: number, z: number)
	if not free(R, x - 4.3, x + 4.3, z - 4.3, z + 4.3) then
		return
	end
	Kit.meetingTable(R.model, R.cf, at(R, x, z, 0), "round", 4.6, nil, R.seed + 3)
	for i = 1, 3 do
		local a = RAD(90 + (i - 1) * 120)
		local px, pz = x + math.cos(a) * 3.6, z + math.sin(a) * 3.6
		chair(R, px, pz, math.deg(math.atan2(px - x, pz - z)), 10 + i)
	end
	claim(R, "InterviewTable", x - 4.3, x + 4.3, z - 4.3, z + 4.3)
end

local function kitHr(R: R)
	local n = R.room.desks or 0
	if shapeOf(R) == "A" then
		local s = shapeA(R, n, "ldesk", 7, "x")
		wallScreen(R, s.fside, s.t1 + 4.5, 6, "hr", { text = "People & company", app = "empire", section = "team" })
		Kit.cabinet(R.model, R.cf, wallAt(R, s.fside, s.t1 + 10), 3, 6.5, R.seed + 1)
		wallClaim(R, "Cabinet", s.fside, s.t1 + 10, 3, 1.7)
		lowShelf(R, s.fside, s.t1 + 14.5, 4)
		Kit.deskPrinter(R.model, R.cf, wallAt(R, s.fside, s.t1 + 14.5) * CF(0.8, 2.8, -0.65), { prompt = "HR printer", propId = R.room.id .. "_Printer" })
		local x, z = takeFree(R, s.freeRects, 8.8, 8.8)
		if x and z then
			interviewTable(R, x, z)
		end
	else
		-- two desks along the solid side wall, the rest on the other side; interview table behind them
		local solidSide = if solidish(R.side.left) then "left" else "right"
		local nSolid = math.min(n, 2)
		local nL = if solidSide == "left" then nSolid else n - nSolid
		shapeB(R, nL, n - nL, if R.W <= 24 then "bench" else "ldesk")
		local o = opposite(solidSide)
		local ix = if o == "left" then R.inner.left + 4.6 else R.inner.right - 4.6
		interviewTable(R, ix, R.inner.back - 4.6)
		local st = if solidSide == "left" then R.inner.left + 4 else R.inner.right - 4
		wallScreen(R, "back", st, 5, "hr", { text = "People & company", app = "empire", section = "team" })
	end
	cornerPlant(R, "front", if R.doorX > 0 then "left" else "right", "s", 1)
end

-- Focus room: one desk on a solid side wall, lounge chair + floor lamp in the back corner, low shelf, plant.
local function kitFocus(R: R)
	local side = if solidish(R.side.right) and (not solidish(R.side.left) or R.style % 2 == 1) then "right" else "left"
	local g = DESK.ldesk
	local x = if side == "right" then R.inner.right - 0.4 - g.dd / 2 else R.inner.left + 0.4 + g.dd / 2
	local z = ENTRY + 0.6 + g.p / 2
	station(R, x, z, if side == "right" then LOOK.R else LOOK.L, "ldesk")
	stationClaim(R, x, z, if side == "right" then LOOK.R else LOOK.L, "ldesk")
	local o = opposite(side)
	local lx = if o == "left" then R.inner.left + 2.2 else R.inner.right - 2.2
	local lz = R.inner.back - 2.4
	lounge(R, lx, lz, if o == "left" then -150 else 150, 1, true)
	local lamp = R.style % 2 == 0 or R.level == Plan.founderLevel(R.tier)
	if lamp then
		floorLamp(R, if o == "left" then R.inner.left + 0.9 else R.inner.right - 0.9, R.inner.back - 5, 2)
	end
	local sx = if side == "right" then R.inner.right - 2.6 else R.inner.left + 2.6
	if free(R, sx - 2.1, sx + 2.1, R.inner.back - 1.5, R.inner.back) then
		lowShelf(R, "back", sx, 4)
	end
	if not lamp or R.level == Plan.founderLevel(R.tier) then
		plant(R, if o == "left" then R.inner.left + 1.0 else R.inner.right - 1.0, ENTRY + 1.6, "s", 4)
	end
end

local function kitPhone(R: R)
	local side = if solidish(finishAt(R.tier, R.room, R.sideFace.right, if R.sideFace.right == "E" or R.sideFace.right == "W" then (R.room.z1 + R.room.z2) / 2 + 6 else (R.room.x1 + R.room.x2) / 2)) then "right" else "left"
	local count = if R.D >= 30 and R.tier <= 2 then 3 else 2
	local x = if side == "right" then R.inner.right - 2.7 else R.inner.left + 2.7
	-- booths keep a 2.5-stud gap so each can be walked around
	local pitch = math.min(7.5, (R.zEnd - ENTRY - 1) / count)
	local z0 = R.zEnd - count * pitch
	for i = 1, count do
		local z = z0 + pitch / 2 + (i - 1) * pitch
		Kit.phoneBooth(R.model, R.cf, at(R, x, z, if side == "right" then FRONT.L else FRONT.R), R.room.id .. "_Booth" .. i, R.owner, R.seed + i)
		claim(R, "PhoneBooth", x - 2.5, x + 2.5, z - 2.5, z + 2.5)
	end
	local o = opposite(side)
	local lx = if o == "left" then R.inner.left + 2 else R.inner.right - 2
	lounge(R, lx, R.zEnd - 3, if o == "left" then FRONT.R else FRONT.L, 1, true)
	plant(R, lx, R.zEnd - 6.8, "s", 2)
end

local function kitPrint(R: R)
	-- supplies and paper cabinet on a solid side wall, copier free-standing facing the door
	local side = if solidish(R.side.left) then "left" elseif solidish(R.side.right) then "right" else "left"
	local probe = R.D * 0.7
	if not solidish(finishAt(R.tier, R.room, R.sideFace[side], if R.sideFace[side] == "E" or R.sideFace[side] == "W" then (R.room.z1 + R.room.z2) / 2 else (R.room.x1 + R.room.x2) / 2)) then
		side = opposite(side)
	end
	local _ = probe
	local t1 = R.zEnd - 4
	lowShelf(R, side, t1, 4.5)
	Kit.cabinet(R.model, R.cf, wallAt(R, side, t1 - 5), 3, 4.2, R.seed + 2)
	wallClaim(R, "PaperCabinet", side, t1 - 5, 3, 1.7)
	local cx, cz = 0, R.zEnd - 6
	local b = at(R, cx, cz, FRONT.F)
	-- copier as a PropFx prop: pages slide out of the front and the panel blinks while it copies
	local copier = Kit.propModel(R.model, R.cf, "CopierUnit", b)
	local body = Kit.part(copier, R.cf, "Copier", V3(4, 3.2, 3), b * CF(0, 1.6, 0), C.white, M.smooth)
	body:SetAttribute("FxOut", true)
	Kit.part(copier, R.cf, "CopierScanner", V3(3.6, 0.5, 2.6), b * CF(0, 3.45, 0.1), C.plasterShade, M.smooth)
	local panel = Kit.part(copier, R.cf, "CopierPanel", V3(1.2, 0.08, 0.7), b * CF(1.1, 3.74, -1.0), C.screen, M.smooth, DETAIL)
	panel:SetAttribute("FxGlow", true)
	Kit.part(copier, R.cf, "PaperTray", V3(3.4, 0.06, 0.02), b * CF(0, 1.2, -1.51), C.metalSoft, M.smooth, DETAIL)
	Kit.fx(copier, "paper,blink", { FxColor = C.statusGood, FxRate = 2, FxSeconds = 6, PropId = R.room.id .. "_Copier" })
	Kit.action(body, "prop", "Copier", R.room.id .. "_Copier", { actionText = "Copy", maxDistance = 7 })
	claim(R, "Copier", cx - 2, cx + 2, cz - 1.5, cz + 1.5)
	-- sorting table + recycling bin
	local tz = cz - 7
	local tb = at(R, 0, tz, 0)
	Kit.part(R.model, R.cf, "SortingTable", V3(5, 0.2, 2.4), tb * CF(0, 3.1, 0), C.oakLight, M.wood)
	for _, s in { -1, 1 } do
		Kit.part(R.model, R.cf, "TableLeg", V3(0.25, 3.0, 2.0), tb * CF(s * 2.2, 1.5, 0), C.metal, M.metal)
	end
	claim(R, "SortingTable", -2.5, 2.5, tz - 1.2, tz + 1.2)
	local o = opposite(side)
	local bx = if o == "left" then R.inner.left + 1 else R.inner.right - 1
	Kit.cylinder(R.model, R.cf, "RecyclingBin", "y", 2.2, 1.4, at(R, bx, R.zEnd - 2) * CF(0, 1.1, 0), C.sage, M.smooth)
	claim(R, "Bin", bx - 0.7, bx + 0.7, R.zEnd - 2.7, R.zEnd - 1.3)
	cornerPlant(R, "front", if R.doorX > 0 then "left" else "right", "s", 1)
end

---------------------------------------------------------------------------------------------
-- Meeting rooms, boardroom
---------------------------------------------------------------------------------------------
-- Chair at (x, z) facing the table point (tx, tz) + Meeting activity beside it.
local function meetingSeat(R: R, x: number, z: number, tx: number, tz: number, meetingId: string, dept: string, n: number, executive: boolean?, gap: number?)
	local yaw = math.deg(math.atan2(x - tx, z - tz)) -- front (-Z) towards the table
	local cfr = at(R, x, z, yaw)
	local seat
	if executive then
		local m = Instance.new("Model")
		m.Name = "ExecutiveChair"
		seat = Kit.officeChair(m, R.cf, cfr, R.seed + n, { lite = true, arms = true, color = C.leather })
		m.Parent = R.model
		trim(m, 4)
	else
		seat = chair(R, x, z, yaw, n)
	end
	-- stand beside the chair, slightly behind it
	local th = RAD(yaw)
	local backX, backZ = math.sin(th), math.cos(th)
	local sideX, sideZ = math.cos(th), -math.sin(th)
	local side = (gap or 3.4) / 2
	local ax, az = x + backX * 1.6 + sideX * side, z + backZ * 1.6 + sideZ * side
	activity(R, "Meeting", dept, "any", ax, az, tx, tz, seat, { meetingRoom = meetingId })
end

local function reviewRoom(room: Plan.Room): boolean
	local n = string.lower(room.name)
	return string.find(n, "review", 1, true) ~= nil or string.find(n, "results", 1, true) ~= nil or string.find(n, "paper", 1, true) ~= nil
end

local function kitMeeting(R: R)
	local seats = R.room.seats or 6
	local meetingId = R.room.meeting or R.room.id
	local dept = if reviewRoom(R.room) then "evaluation" else "social"
	local z1, z2 = ENTRY, R.zEnd
	local zc = (z1 + z2) / 2
	local shape = if seats <= 4 then "round" elseif seats <= 6 then "rect" else "boat"
	local perSide = math.ceil(seats / 2)
	local L = if shape == "round" then 5.5 elseif shape == "rect" then perSide * 3.4 + 1.2 else perSide * 3.3 + 3
	local Wt = if shape == "boat" then 5.5 else 4.5
	local axis = if (R.inner.right - R.inner.left) >= (z2 - z1) then "x" else "z"
	local tableAt = at(R, 0, zc, if axis == "x" then 0 else 90)
	Kit.meetingTable(R.model, R.cf, tableAt, shape, L, Wt, R.seed + 1)
	-- conference speakerphone: its ring glows while this room's meeting runs (FxGate Meeting)
	Kit.speakerphone(R.model, R.cf, tableAt * CF(if shape == "round" then 0 else math.min(1.8, L / 4), 3.15, 0), meetingId)
	local n = 0
	if shape == "round" then
		for i = 1, seats do
			local a = RAD(45 + (i - 1) * 360 / seats)
			n += 1
			meetingSeat(R, math.cos(a) * (L / 2 + 1.6), zc + math.sin(a) * (L / 2 + 1.6), 0, zc, meetingId, dept, n)
		end
		claim(R, "MeetingTable", -(L / 2 + 2.7), L / 2 + 2.7, zc - L / 2 - 2.7, zc + L / 2 + 2.7)
	else
		local span = (perSide - 1) * 3.3
		for sgn = -1, 1, 2 do
			for i = 1, perSide do
				if n >= seats then
					break
				end
				local a = -span / 2 + (i - 1) * 3.3
				n += 1
				local off = Wt / 2 + 1.5
				if axis == "x" then
					meetingSeat(R, a, zc + sgn * off, a, zc, meetingId, dept, n, false, 3.3)
				else
					meetingSeat(R, sgn * off, zc + a, 0, zc + a, meetingId, dept, n, false, 3.3)
				end
			end
		end
		local hl, hw = L / 2, Wt / 2 + 2.6
		if axis == "x" then
			claim(R, "MeetingTable", -hl, hl, zc - hw, zc + hw)
		else
			claim(R, "MeetingTable", -hw, hw, zc - hl, zc + hl)
		end
	end
	-- screen at one table end, whiteboard at the other (or beside the screen)
	local endA, endB
	if axis == "x" then
		endA, endB = "left", "right"
		if solidish(R.side.right) and not solidish(R.side.left) then
			endA, endB = "right", "left"
		end
	else
		endA, endB = "back", "front"
	end
	local tScreen = if axis == "x" then zc else 0
	local screen = wallScreen(R, endA, tScreen, 7, "meeting", nil, 6.2)
	screen:SetAttribute("MeetingRoom", meetingId)
	if axis == "x" and solidish(R.side[endA]) and seats >= 8 then
		credenza(R, endA, tScreen, 6)
	end
	if axis == "x" and solidish(R.side[endB]) then
		whiteboard(R, endB, zc, 6, "AGENDA\n1  status\n2  decisions\n3  next steps")
	elseif axis == "x" and solidish(R.side[endA]) and z2 - (tScreen + 4) >= 6.5 then
		whiteboard(R, endA, tScreen + 7.5, 5, "AGENDA\n1  status\n2  decisions\n3  next steps")
	else
		local wx = if R.doorX > 0 then R.inner.left + 4 else R.inner.right - 4
		local wz = R.zEnd - 0.8
		if free(R, wx - 3.4, wx + 3.4, wz - 1, wz + 0.8) then
			local base = at(R, wx, wz, 0)
			Kit.whiteboard(R.model, R.cf, base, 5, "AGENDA\n1  status\n2  decisions", R.seed + 4, { y = 5 })
			for _, sx in { -1, 1 } do
				Kit.part(R.model, R.cf, "BoardStand", V3(0.2, 7.2, 0.2), base * CF(sx * 2.7, 3.6, -0.1), C.metalSoft, M.metal)
			end
			Kit.part(R.model, R.cf, "BoardFoot", V3(5.8, 0.15, 1.8), base * CF(0, 0.075, -0.1), C.metalSoft, M.metal)
			claim(R, "BoardStand", wx - 3, wx + 3, wz - 1, wz + 0.8)
		end
	end
	if seats > 4 then
		cornerPlant(R, "back", if R.doorX > 0 then "left" else "right", "s", 1)
	end
end

local function kitBoardroom(R: R)
	local seats = R.room.seats or 12
	local meetingId = R.room.meeting or "Boardroom"
	local zc = (ENTRY + R.zEnd) / 2
	local perSide = math.ceil(seats / 2)
	local L = perSide * 3.5 + 4
	local Wt = 6
	Kit.meetingTable(R.model, R.cf, at(R, 0, zc, 0), "boat", L, Wt, R.seed + 1)
	Kit.speakerphone(R.model, R.cf, at(R, 2.2, zc, 0) * CF(0, 3.15, 0), meetingId)
	local n = 0
	local span = (perSide - 1) * 3.5
	for sgn = -1, 1, 2 do
		for i = 1, perSide do
			if n >= seats then
				break
			end
			n += 1
			local a = -span / 2 + (i - 1) * 3.5
			meetingSeat(R, a, zc + sgn * (Wt / 2 + 1.5), a, zc, meetingId, "executive", n, true, 3.5)
		end
	end
	claim(R, "BoardTable", -L / 2, L / 2, zc - Wt / 2 - 2.6, zc + Wt / 2 + 2.6)
	local side = featureSide(R)
	local screen = wallScreen(R, side, zc, 10, "boardroom", { text = "Boardroom screen", app = "empire", section = "board" }, 6.4)
	screen:SetAttribute("MeetingRoom", meetingId)
	credenza(R, side, zc, 9)
	Kit.artwork(R.model, R.cf, wallAt(R, side, math.min(R.zEnd - 3, zc + 9.5)), 4, 3.2, R.seed + 2, { y = 6 })
	cornerPlant(R, "back", "left", "m", 1)
	cornerPlant(R, "back", "right", "m", 2)
	Kit.pendant(R.model, R.cf, at(R, 0, zc) * CF(0, Kit.CEILING - Kit.FINISH, 0), "founder", { drop = 4 })
end

---------------------------------------------------------------------------------------------
-- Pantry, lounge
---------------------------------------------------------------------------------------------
local function kitPantry(R: R)
	local side = featureSide(R)
	local L = 12
	local t = ENTRY + 2 + L / 2
	local k = Kit.kitchenette(R.model, R.cf, wallAt(R, side, t), L, R.seed + 1)
	wallClaim(R, "Kitchenette", side, t, L, 2.4)
	-- the coffee machine sits at kitchenette-local x = -L/2 + (L-2.4) - 1, which runs along +t on this wall
	local alongSign = if side == "left" then 1 elseif side == "right" then -1 else 1
	local coffeeT = t + alongSign * (-L / 2 + (L - 2.4) - 1.0)
	for i = 1, 3 do
		local tt = coffeeT - alongSign * (i - 1) * 2.2
		local ax, az = wallPoint(R, side, tt, 2.3 + 1.7)
		local fx, fz = wallPoint(R, side, tt, 1)
		activity(R, "Coffee", "kitchen", "any", ax, az, fx, fz)
	end
	local _ = k
	-- bar table with stools
	local o = opposite(side)
	local bx = (R.inner.left + R.inner.right) / 2 + (if o == "left" then -2 else 2)
	local bz = R.zEnd - 6
	local b = at(R, bx, bz, 0)
	Kit.cylinder(R.model, R.cf, "BarTableTop", "y", 0.2, 3.4, b * CF(0, 3.6, 0), C.oak, M.wood)
	Kit.cylinder(R.model, R.cf, "BarTableColumn", "y", 3.4, 0.4, b * CF(0, 1.8, 0), C.metal, M.metal)
	Kit.cylinder(R.model, R.cf, "BarTableFoot", "y", 0.15, 2.0, b * CF(0, 0.075, 0), C.metal, M.metal)
	for i = 1, 2 do
		local a = RAD(-90 + (i - 1) * 180)
		local sx, sz = bx + math.cos(a) * 2.5, bz + math.sin(a) * 2.5
		Kit.stool(R.model, R.cf, at(R, sx, sz, math.deg(math.atan2(sx - bx, sz - bz))), R.seed + i, 3.0)
	end
	claim(R, "BarTable", bx - 3.3, bx + 3.3, bz - 3.3, bz + 3.3)
	-- bin next to the kitchenette, plants
	local bt = t - alongSign * (L / 2 + 1.2)
	local wx, wz = wallPoint(R, side, bt, 0.9)
	if free(R, wx - 0.7, wx + 0.7, wz - 0.7, wz + 0.7) then
		Kit.cylinder(R.model, R.cf, "Bin", "y", 1.8, 1.2, at(R, wx, wz) * CF(0, 0.9, 0), C.metalSoft, M.metal)
		claim(R, "Bin", wx - 0.7, wx + 0.7, wz - 0.7, wz + 0.7)
	end
	cornerPlant(R, "back", o, "s", 2)
end

local function kitLounge(R: R)
	local zc = (ENTRY + R.zEnd) / 2 + 0.5
	local cx = 0
	Kit.rug(R.model, R.cf, at(R, cx, zc, 0), 13, 9, R.seed + 1)
	local seats = sofa(R, cx, zc + 3.3, FRONT.F, 8, 2)
	claim(R, "Sofa", cx - 4, cx + 4, zc + 1.8, zc + 4.8)
	local s1 = lounge(R, cx - 5.2, zc - 0.6, FRONT.R, 3)
	local s2 = lounge(R, cx + 5.2, zc - 0.6, FRONT.L, 4)
	coffeeTable(R, cx, zc - 0.6, 3.6, 2.2, 5)
	for _, s in seats do
		seatActivity(R, "Lounge", "lounge", s, 2.2)
	end
	seatActivity(R, "Lounge", "lounge", s1, 1.9)
	seatActivity(R, "Lounge", "lounge", s2, 1.9)
	floorLamp(R, cx + 5.4, zc + 3.6, 6)
	-- bookshelf on a solid wall, plants, a standing conversation spot by the window
	local side = featureSide(R)
	Kit.bookshelf(R.model, R.cf, wallAt(R, side, zc), 6, 5, R.seed + 7, { books = 3 })
	wallClaim(R, "Bookshelf", side, zc, 6, 1.4)
	cornerPlant(R, "back", opposite(side), "l", 1)
	local tz = R.zEnd - 1.5
	local tx = if side == "left" then R.inner.right - 6 else R.inner.left + 6
	if R.D - zc < 12 then
		tz = ENTRY + 1.5
		tx = if R.doorX > 0 then R.inner.left + 5 else R.inner.right - 5
	end
	local group = R.room.id .. "_Talk"
	activity(R, "Conversation", "social", "any", tx - 1.2, tz, tx + 1.2, tz, nil, { conversationGroup = group })
	activity(R, "Conversation", "social", "any", tx + 1.2, tz, tx - 1.2, tz, nil, { conversationGroup = group })
	-- aquarium (PropFx, always on near the camera) on the far side of the back wall, clear of the
	-- standing conversation spot
	local ax = if tx > 0 then R.inner.left + 3.2 else R.inner.right - 3.2
	local az = R.zEnd - 1.3
	local clearOfTalk = math.abs(ax - tx) > 5 or math.abs(az - tz) > 2.6
	if clearOfTalk and free(R, ax - 2.3, ax + 2.3, az - 1, az + 1) then
		Kit.aquarium(R.model, R.cf, at(R, ax, az, 0), R.seed + 11)
		claim(R, "Aquarium", ax - 2.3, ax + 2.3, az - 1, az + 1)
	end
end

---------------------------------------------------------------------------------------------
-- Restrooms
---------------------------------------------------------------------------------------------
-- Toilet against a wall: `base` = wall surface frame (front towards the room).
local function toilet(R: R, base: CFrame, key: string, ownerOnly: boolean)
	Kit.part(R.model, R.cf, "ToiletBowl", V3(1.5, 1.4, 2.2), base * CF(0, 0.7, -1.3), C.white, M.smooth)
	Kit.part(R.model, R.cf, "ToiletTank", V3(1.9, 2.2, 0.7), base * CF(0, 2.4, -0.35), C.white, M.smooth)
	local seat = Kit.seat(R.model, R.cf, "ToiletSeat", V3(1.5, 0.2, 1.8), base * CF(0, 1.5, -1.4), C.white, M.smooth, { canTouch = false })
	seat.Disabled = true
	seat.Transparency = 0
	seat:SetAttribute("FixtureKey", key)
	Kit.action(seat, "toilet", "Toilet", nil, { actionText = "Use", maxDistance = 6, ownerOnly = ownerOnly })
	local flush = Kit.part(R.model, R.cf, "FlushButton", V3(0.6, 0.35, 0.08), base * CF(0, 3.0, -0.74), C.metalSoft, M.metal, { canCollide = false, canTouch = false })
	flush:SetAttribute("FixtureKey", key)
	Kit.action(flush, "flush", "Flush", nil, { actionText = "Flush", maxDistance = 6, ownerOnly = ownerOnly })
	local water = Kit.part(R.model, R.cf, "ToiletWater", V3(1.0, 0.05, 1.2), base * CF(0, 1.32, -1.45), C.water, M.smooth, { detail = true, transparency = 0.25 })
	water:SetAttribute("FixtureKey", key)
	Kit.fx(water, "flow", { FxAxis = "y", FxTravel = -0.3, FxRate = 3, FxSeconds = 2 })
end

-- Basin on a counter: `base` = wall surface frame at the basin centre.
local function basin(R: R, base: CFrame, key: string, ownerOnly: boolean)
	Kit.part(R.model, R.cf, "Basin", V3(1.6, 0.35, 1.3), base * CF(0, 3.1, -0.95), C.white, M.smooth)
	local tap = Kit.part(R.model, R.cf, "Tap", V3(0.2, 0.7, 0.5), base * CF(0, 3.55, -0.35), C.metalSoft, M.metal, { canCollide = false })
	tap:SetAttribute("FixtureKey", key)
	Kit.action(tap, "tap", "Tap", nil, { actionText = "Wash hands", maxDistance = 6, ownerOnly = ownerOnly })
	local water = Kit.part(R.model, R.cf, "TapWater", V3(0.15, 0.55, 0.15), base * CF(0, 3.25, -0.6), C.water, M.smooth, { detail = true, transparency = 1 })
	water:SetAttribute("FixtureKey", key)
	water:SetAttribute("FxShow", 0.5)
	Kit.fx(water, "flow", { FxSeconds = 6 })
end

local function kitWc(R: R)
	-- three cubicles along a solid side wall, basins along the other side
	local side = if solidish(R.side.right) then "right" else "left"
	local o = opposite(side)
	local depth = 6
	local cw = (R.inner.back - (ENTRY + 3)) / 3
	cw = math.min(cw, 5.6)
	local zStart = R.inner.back - 3 * cw
	local wallX = if side == "right" then R.inner.right else R.inner.left
	local frontX = wallX + (if side == "right" then -depth else depth)
	local sgnIn = if side == "right" then 1 else -1 -- +x local points into the cubicles for a right wall
	local doorsFolder = R.ctx.folders.Doors
	for i = 1, 3 do
		local za = zStart + (i - 1) * cw
		local zb = za + cw
		local key = R.room.id .. "_C" .. i
		-- side partition at za (the last cubicle ends at the back wall)
		Kit.part(R.model, R.cf, "CubiclePartition", V3(depth, 7.2, 0.15), at(R, (wallX + frontX) / 2, za) * CF(0, 3.6, 0), C.white, M.smooth)
		-- door opening at the +z end of the front, fixed panel at the -z end
		local ow = 3.6
		local oz2 = zb - 0.15
		local oz1 = oz2 - ow
		Kit.part(R.model, R.cf, "CubicleFront", V3(0.15, 7.2, oz1 - za - 0.075), at(R, frontX, (za + 0.075 + oz1) / 2) * CF(0, 3.6, 0), C.white, M.smooth)
		local centre = pt(R, frontX, 0, (oz1 + oz2) / 2)
		local def: any = {
			id = key,
			level = R.level,
			room = R.room.id,
			kind = "cubicle",
			access = "staff",
			axis = if math.abs(R.rf.RightVector.X) > 0.5 then "x" else "z",
			x = centre.X,
			z = centre.Z,
			w = ow,
			h = 7.2,
			inward = R.rf:VectorToWorldSpace(V3(sgnIn, 0, 0)),
			exterior = false,
			hidden = false,
			builder = "interior",
			y = centre.Y,
			thickness = 0.15,
		}
		-- for a left wall the hinge must stay at the +z end of the opening
		if side == "left" then
			def.hinge = "right"
		end
		local door = Kit.door(doorsFolder, R.cf, def :: any, R.owner)
		if door then
			door:SetAttribute("FixtureKey", key)
		end
		-- toilet against the side wall, centred in the cubicle
		local tz = (za + zb) / 2 - 0.4
		toilet(R, wallAt(R, side, tz), key, false)
		claim(R, "Cubicle" .. i, math.min(wallX, frontX), math.max(wallX, frontX), za, zb)
	end
	-- vanity with two basins on the other wall
	local vL = 7.2
	local vt = ENTRY + 2.5 + vL / 2
	local vb = wallAt(R, o, vt)
	Kit.part(R.model, R.cf, "VanityTop", V3(vL, 0.25, 2.0), vb * CF(0, 2.85, -1.0), C.stone, M.marble)
	Kit.part(R.model, R.cf, "VanityBase", V3(vL - 0.4, 2.4, 1.6), vb * CF(0, 1.5, -0.85), C.oak, M.wood)
	Kit.part(R.model, R.cf, "Mirror", V3(vL - 0.4, 3.4, 0.08), vb * CF(0, 5.6, -0.05), C.glassDeep, M.glass, { detail = true, reflectance = 0.25 })
	local alongSign = if o == "left" then 1 elseif o == "right" then -1 else 1
	for i = 1, 2 do
		basin(R, vb * CF((i - 1.5) * 3.4 * alongSign * alongSign, 0, 0), R.room.id .. "_T" .. i, false)
	end
	wallClaim(R, "Vanity", o, vt, vL, 2.1)
	local dt = math.min(R.inner.back - 2, vt + vL / 2 + 3)
	local dryer = Kit.part(R.model, R.cf, "HandDryer", V3(1.0, 1.4, 0.7), wallAt(R, o, dt) * CF(0, 4.6, -0.35), C.white, M.smooth, DETAIL)
	local air = Kit.steamEmitter(dryer, "WarmAir", 6, 0.2)
	air.EmissionDirection = Enum.NormalId.Bottom
	Kit.fx(dryer, "steam", { FxSeconds = 4 })
	Kit.action(dryer, "prop", "Hand dryer", nil, { actionText = "Dry hands", maxDistance = 6 })
	-- the cleaner wipes the vanity here (Clean activity, support staff)
	local cx, cz = wallPoint(R, o, vt, 2.1 + 1.7)
	local fx2, fz2 = wallPoint(R, o, vt, 0.5)
	activity(R, "Clean", "operations", "support", cx, cz, fx2, fz2, nil, { attributes = { JobPose = "wipe", JobItem = "sponge" } })
end

---------------------------------------------------------------------------------------------
-- Founder suite
---------------------------------------------------------------------------------------------
local function kitFounderOffice(R: R)
	-- frame: entry wall = the assistant's door (west); +x of the frame runs towards the setback facade
	local deskX, deskZ = 6, R.inner.back - 8.4
	local desk = station(R, deskX, deskZ, LOOK.F, "ldesk", "executive")
	desk:SetAttribute("Role", "founder") -- the founder's own desk: no employee takes it
	claim(R, "FounderDesk", deskX - 3.5, deskX + 3.5, deskZ - 1.7, deskZ + 4.5)
	local top = desk:FindFirstChild("DeskTop")
	local deskAt = at(R, deskX, deskZ, LOOK.F)
	local topY = if top and top:IsA("BasePart") then top.Size.Y / 2 + 3.0 else 3.15
	local term = Kit.part(R.model, R.cf, "FounderTerminal", V3(1.8, 1.2, 0.15), deskAt * CF(-2.4, topY + 0.65, 0.9) * ANG(0, RAD(-15), 0), C.screen, M.smooth, { canCollide = false })
	Kit.action(term, "ownerComputer", "Founder computer · whole company", "empire", { ownerOnly = true, actionText = "Open", maxDistance = 8 })
	local tablet = Kit.part(R.model, R.cf, "FounderCameraTablet", V3(1.2, 0.08, 1.6), deskAt * CF(2.3, topY + 0.04, -0.3) * ANG(0, RAD(20), 0), C.metal, M.smooth, { canCollide = false })
	Kit.action(tablet, "security", "Security cameras", nil, { ownerOnly = true, actionText = "View", maxDistance = 8 })
	-- visitor chairs in front of the desk
	for i, vx in { deskX - 1.8, deskX + 1.8 } do
		local vz = deskZ - 4.6
		chair(R, vx, vz, FRONT.B, 20 + i, C.leather)
		claim(R, "VisitorChair", vx - 1.05, vx + 1.05, vz - 1, vz + 1)
	end
	-- entry wall: bookshelf, history screen, founder screen over a credenza, milestones screen
	local W2 = R.W / 2
	Kit.bookshelf(R.model, R.cf, wallAt(R, "front", -W2 + 7), 8, 9, R.seed + 2, { books = 3 })
	wallClaim(R, "Bookshelf", "front", -W2 + 7, 8, 1.4)
	wallScreen(R, "front", -6.5, 5, "history", nil, 6.2)
	credenza(R, "front", 11.5, 8)
	wallScreen(R, "front", 11.5, 7, "founder", { text = "Founder screen", app = "empire" }, 6.4)
	wallScreen(R, "front", W2 - 5, 5, "milestones", { text = "Milestones", app = "empire", section = "milestones" }, 6.2)
	-- seating group on a rug
	local gx, gz = -9, 15.5
	Kit.rug(R.model, R.cf, at(R, gx, gz, 0), 13, 10, R.seed + 3)
	sofa(R, gx, gz + 4.2, FRONT.F, 8, 4)
	claim(R, "Sofa", gx - 4, gx + 4, gz + 2.7, gz + 5.7)
	lounge(R, gx - 5.6, gz - 0.3, FRONT.R, 5)
	lounge(R, gx + 5.6, gz - 0.3, FRONT.L, 6)
	coffeeTable(R, gx, gz - 0.3, 4, 2.4, 7)
	Kit.pendant(R.model, R.cf, at(R, gx, gz) * CF(0, Kit.CEILING - Kit.FINISH, 0), "founder", { drop = 3.5 })
	-- art between the library and bath doors, plants
	local doorZ: { number } = {}
	for _, d in R.doors do
		if d.side == "left" then
			table.insert(doorZ, d.z)
		end
	end
	table.sort(doorZ)
	local artZ = if #doorZ >= 2 then (doorZ[1] + doorZ[2]) / 2 else gz
	Kit.artwork(R.model, R.cf, wallAt(R, "left", artZ), 5, 3.6, R.seed + 8, { y = 6 })
	cornerPlant(R, "back", "left", "l", 1)
	cornerPlant(R, "back", "right", "l", 2)
	cornerPlant(R, "front", "right", "m", 3)
end

local function kitFounderAssist(R: R)
	-- reception desk facing the entry door, waiting chairs along the side wall
	local dx, dz = -R.W / 4, R.inner.back - 7.5
	if dx > R.doorX - 7 and dx < R.doorX + 7 then
		dx = R.doorX - 9
	end
	station(R, dx, dz, LOOK.F, "ldesk", "operations")
	claim(R, "ReceptionDesk", dx - 4, dx + 4, dz - 2.5, dz + 4.5)
	local led = at(R, dx, dz - 2.3, 0)
	Kit.part(R.model, R.cf, "ReceptionFront", V3(8, 3.6, 0.4), led * CF(0, 1.8, 0), C.oak, M.wood)
	Kit.part(R.model, R.cf, "ReceptionLedge", V3(8.4, 0.15, 1.0), led * CF(0, 3.675, -0.2), C.stone, M.marble)
	local side = if R.doorX > 0 then "left" else "right"
	local wx = if side == "right" then R.inner.right - 1.4 else R.inner.left + 1.4
	for i = 1, 3 do
		local wz = ENTRY + 1 + (i - 1) * 2.8
		chair(R, wx, wz, if side == "right" then FRONT.L else FRONT.R, i, C.fabricSand)
		claim(R, "WaitingChair", wx - 1.05, wx + 1.05, wz - 1, wz + 1)
	end
	Kit.artwork(R.model, R.cf, wallAt(R, side, ENTRY + 3.8), 4.5, 3, R.seed + 5, { y = 6.8 })
	Kit.artwork(R.model, R.cf, wallAt(R, opposite(side), (ENTRY + R.zEnd) / 2), 4, 3, R.seed + 6, { y = 6 })
	cornerPlant(R, "back", side, "l", 1)
	cornerPlant(R, "front", opposite(side), "m", 2)
end

local function kitFounderLibrary(R: R)
	local W2 = R.W / 2
	local n = 2
	for i = 1, n do
		local t = (i - 1.5) * 9
		Kit.bookshelf(R.model, R.cf, wallAt(R, "back", t), 6.2, 9, R.seed + i, { books = 3, color = C.oakDark })
		wallClaim(R, "Bookshelf", "back", t, 6.2, 1.4)
	end
	local lt = ENTRY + 2
	Kit.bookshelf(R.model, R.cf, wallAt(R, "left", lt), 5, 9, R.seed + 9, { books = 3, color = C.oakDark })
	wallClaim(R, "Bookshelf", "left", lt, 5, 1.4)
	-- reading corner
	Kit.rug(R.model, R.cf, at(R, -W2 + 7, R.inner.back - 6, 0), 7, 5, R.seed + 3)
	lounge(R, -W2 + 5.5, R.inner.back - 5.6, -130, 4)
	floorLamp(R, -W2 + 2.4, R.inner.back - 3.2, 5)
	-- sideboard with the report printer
	local st = ENTRY + 1
	Kit.sideboard(R.model, R.cf, wallAt(R, "right", st), 5, R.seed + 6)
	wallClaim(R, "Sideboard", "right", st, 5.1, 1.7)
	local printer = Kit.part(R.model, R.cf, "ReportPrinter", V3(1.6, 0.9, 1.3), wallAt(R, "right", st + 0.8) * CF(0, 2.82 + 0.45, -0.85), C.white, M.smooth, { canCollide = false })
	Kit.fx(printer, "paper", { FxSeconds = 3 })
	Kit.action(printer, "report", "Report printer", nil, { ownerOnly = true, actionText = "Print report", maxDistance = 8 })
	plant(R, R.inner.right - 1.4, R.inner.back - 2.8, "m", 7)
end

local function kitFounderBath(R: R)
	-- shower niche in the back corner away from the facade, WC beside it, basin near the door
	local sideS = if R.side.left == "facade" then "right" else "left"
	local sgn = if sideS == "left" then 1 else -1
	local wallX = if sideS == "left" then R.inner.left else R.inner.right
	local sx1 = wallX
	local sx2 = wallX + sgn * 5
	local sz1 = R.inner.back - 5
	local cx = (sx1 + sx2) / 2
	Kit.part(R.model, R.cf, "ShowerTray", V3(5, 0.15, 5), at(R, cx, (sz1 + R.inner.back) / 2) * CF(0, 0.075, 0), C.white, M.tile)
	Kit.part(R.model, R.cf, "ShowerGlass", V3(0.12, 7.6, 5), at(R, sx2, (sz1 + R.inner.back) / 2) * CF(0, 3.9, 0), C.glass, M.glass, GLASS)
	Kit.part(R.model, R.cf, "ShowerGlassFront", V3(2.4, 7.6, 0.12), at(R, wallX + sgn * 1.2, sz1) * CF(0, 3.9, 0), C.glass, M.glass, GLASS)
	local hb = wallAt(R, "back", cx)
	local head = Kit.part(R.model, R.cf, "ShowerHead", V3(0.9, 0.15, 0.9), hb * CF(0, 8.2, -0.9), C.metalSoft, M.metal, { canCollide = false })
	Kit.part(R.model, R.cf, "ShowerArm", V3(0.12, 0.12, 0.9), hb * CF(0, 8.3, -0.45), C.metalSoft, M.metal, DETAIL)
	head:SetAttribute("FixtureKey", R.room.id .. "_S1")
	Kit.action(head, "shower", "Shower", nil, { actionText = "Shower", maxDistance = 7, ownerOnly = true })
	local water = Kit.part(R.model, R.cf, "ShowerWater", V3(0.8, 7.9, 0.8), hb * CF(0, 4.2, -0.9), C.water, M.smooth, { detail = true, transparency = 1 })
	water:SetAttribute("FixtureKey", R.room.id .. "_S1")
	claim(R, "Shower", math.min(sx1, sx2), math.max(sx1, sx2), sz1, R.inner.back)
	-- toilet on the back wall next to the shower
	local tx = sx2 + sgn * 3
	toilet(R, wallAt(R, "back", tx), R.room.id .. "_W1", true)
	claim(R, "Toilet", tx - 1, tx + 1, R.inner.back - 2.5, R.inner.back)
	-- basin on the side wall near the entry
	local bt = ENTRY + 2.2
	local vb = wallAt(R, sideS, bt)
	Kit.part(R.model, R.cf, "VanityTop", V3(3.2, 0.25, 2.0), vb * CF(0, 2.85, -1.0), C.stone, M.marble)
	Kit.part(R.model, R.cf, "VanityBase", V3(2.8, 2.4, 1.6), vb * CF(0, 1.5, -0.85), C.oakDark, M.wood)
	Kit.part(R.model, R.cf, "Mirror", V3(2.8, 3.2, 0.08), vb * CF(0, 5.6, -0.05), C.glassDeep, M.glass, { detail = true, reflectance = 0.25 })
	basin(R, vb, R.room.id .. "_T1", true)
	wallClaim(R, "Vanity", sideS, bt, 3.2, 2.1)
	Kit.part(R.model, R.cf, "TowelRail", V3(2.4, 0.1, 0.25), wallAt(R, opposite(sideS), ENTRY + 3) * CF(0, 4.4, -0.2), C.brass, M.metal, DETAIL)
	Kit.part(R.model, R.cf, "Towel", V3(2.0, 1.6, 0.12), wallAt(R, opposite(sideS), ENTRY + 3) * CF(0, 3.6, -0.3), C.white, M.fabric, DETAIL)
	cornerPlant(R, "front", opposite(sideS), "s", 1)
end

---------------------------------------------------------------------------------------------
-- Terraces (founder level, outdoor)
---------------------------------------------------------------------------------------------
local function parasol(R: R, x: number, z: number)
	local b = at(R, x, z)
	Kit.cylinder(R.model, R.cf, "ParasolBase", "y", 0.3, 1.6, b * CF(0, 0.15, 0), C.stoneDeep, M.concrete)
	Kit.cylinder(R.model, R.cf, "ParasolPole", "y", 7.6, 0.2, b * CF(0, 4.0, 0), C.metal, M.metal)
	Kit.cylinder(R.model, R.cf, "ParasolCanopy", "y", 0.35, 8, b * CF(0, 7.9, 0), C.fabricSand, M.fabric, { canCollide = false, castShadow = true })
	claim(R, "Parasol", x - 0.8, x + 0.8, z - 0.8, z + 0.8)
end

local function pergola(R: R, x: number, z: number, w: number, d: number)
	local b = at(R, x, z)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Kit.part(R.model, R.cf, "PergolaPost", V3(0.5, 8.5, 0.5), b * CF(sx * (w / 2 - 0.25), 4.25, sz * (d / 2 - 0.25)), C.oakDark, M.wood)
		end
		Kit.part(R.model, R.cf, "PergolaBeam", V3(0.4, 0.6, d), b * CF(sx * (w / 2 - 0.25), 8.8, 0), C.oakDark, M.wood)
	end
	local slats = math.floor(w / 1.4)
	for i = 1, slats do
		Kit.part(R.model, R.cf, "PergolaSlat", V3(0.3, 0.4, d + 0.6), b * CF(-w / 2 + (i - 0.5) * w / slats, 9.3, 0) * ANG(0, 0, 0), C.oak, M.wood, DETAIL)
	end
	-- ceiling fan hanging from the middle slat (PropFx, turns during working hours)
	local mid = math.ceil(slats / 2)
	Kit.ceilingFan(R.model, R.cf, b * CF(-w / 2 + (mid - 0.5) * w / slats, 9.1, 0), math.min(4, d - 1))
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			claim(R, "PergolaPost", x + sx * (w / 2 - 0.25) - 0.25, x + sx * (w / 2 - 0.25) + 0.25, z + sz * (d / 2 - 0.25) - 0.25, z + sz * (d / 2 - 0.25) + 0.25)
		end
	end
end

local function kitTerrace(R: R)
	local staff = R.access ~= "founder"
	local zMid = (R.inner.front + FACADE_GAP + R.inner.back - 4) / 2
	-- planters along the railing (kept 1.5 studs off it)
	local pz = R.inner.back - 1.5 - 1.2
	local span = R.inner.right - R.inner.left - 4
	local count = math.max(2, math.floor(span / 20))
	local pitch = span / count
	for i = 1, count do
		local px = R.inner.left + 2 + (i - 0.5) * pitch
		local w = math.min(9, pitch - 4)
		if free(R, px - w / 2, px + w / 2, pz - 1.2, pz + 1.2) then
			Kit.planter(R.model, R.cf, at(R, px, pz, 0), w, 2.4, R.seed + i)
			claim(R, "Planter", px - w / 2, px + w / 2, pz - 1.2, pz + 1.2)
		end
	end
	-- seating groups: two lounge chairs facing each other across a low table + shade
	local groups = if staff then 3 else 1
	local gpitch = span / groups
	local loungeActs = 0
	for g = 1, groups do
		local gx = R.inner.left + 2 + (g - 0.5) * gpitch
		-- keep clear of door zones
		for _, k in R.keep do
			if gx + 6 > k.x1 and gx - 6 < k.x2 then
				gx = if gx < (k.x1 + k.x2) / 2 then k.x1 - 7 else k.x2 + 7
			end
		end
		local gz = zMid
		local a = lounge(R, gx - 2.9, gz, FRONT.R, g * 3, true)
		local b = lounge(R, gx + 2.9, gz, FRONT.L, g * 3 + 1, true)
		coffeeTable(R, gx, gz, 2.2, 2.2, g * 3 + 2)
		if staff and loungeActs < 2 then
			seatActivity(R, "Lounge", "roof", a, 1.6)
			loungeActs += 1
			if loungeActs < 2 then
				seatActivity(R, "Lounge", "roof", b, 1.6)
				loungeActs += 1
			end
		end
		if staff and g == 2 then
			pergola(R, gx, gz, 11, 6.5)
		else
			parasol(R, gx + 5.6, gz - 2.2)
		end
	end
	if not staff then
		-- a pair of sun loungers by the railing
		for i, lx in { R.inner.right - 8, R.inner.right - 4.5 } do
			local lz = pz - 4.6
			if free(R, lx - 1.3, lx + 1.3, lz - 3, lz + 3) then
				local b = at(R, lx, lz, FRONT.F)
				Kit.part(R.model, R.cf, "LoungerBase", V3(2.4, 1.0, 6), b * CF(0, 0.5, 0), C.oakDark, M.wood)
				Kit.seat(R.model, R.cf, "Seat", V3(2.2, 0.35, 4.4), b * CF(0, 1.17, 0.7), C.fabricSand, M.fabric)
				Kit.wedge(R.model, R.cf, "LoungerBack", V3(2.2, 1.6, 1.6), b * CF(0, 1.8, -2.2) * ANG(0, math.pi, 0), C.fabricSand, M.fabric)
				claim(R, "Lounger", lx - 1.2, lx + 1.2, lz - 3, lz + 3)
			end
			local _ = i
		end
	end
end

---------------------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------------------
local KITS: { [string]: (R) -> () } = {
	team = kitTeam,
	architecture = kitArchitecture,
	datalab = kitDatalab,
	control = kitControl,
	evaluation = kitEvaluation,
	launch = kitLaunch,
	support = kitSupport,
	studio = kitStudio,
	platform = kitPlatform,
	lab = kitLab,
	hwlab = kitHwlab,
	hr = kitHr,
	focus = kitFocus,
	phone = kitPhone,
	meeting = kitMeeting,
	pantry = kitPantry,
	lounge = kitLounge,
	print = kitPrint,
	wc = kitWc,
	boardroom = kitBoardroom,
	founder_office = kitFounderOffice,
	founder_assist = kitFounderAssist,
	founder_library = kitFounderLibrary,
	founder_bath = kitFounderBath,
	terrace = kitTerrace,
}
-- Decorative sub-parts dropped from every fit-out for the part budget.
local NOISE: { [string]: boolean } = { StickyNote = true, Groove = true, MarkerTray = true, PowerHub = true, Vase = true, Books = true, BoothFelt = true }
-- Frame overrides: rooms whose main entrance is not their own first door.
local FRAME: { [string]: string } = { founder_office = "W", terrace = "N" }
Work.KINDS = KITS

local function roomModel(ctx: any, room: Plan.Room): Model
	local m = ctx.rooms[room.id]
	if not m then
		m = Instance.new("Model")
		m.Name = room.id
		m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		m:SetAttribute("RoomId", room.id)
		m:SetAttribute("RoomName", room.name)
		m:SetAttribute("RoomKind", room.kind)
		m:SetAttribute("Level", room.level)
		m:SetAttribute("AccessClass", room.access)
		m.Parent = ctx.folders.Rooms
		ctx.rooms[room.id] = m
	end
	return m
end

function Work.build(ctx: any)
	local issues: { string } = {}
	for _, room in Plan.rooms(ctx.tier) do
		local kit = KITS[room.kind]
		if not kit then
			continue
		end
		local parent = roomModel(ctx, room)
		local fit = Instance.new("Model")
		fit.Name = "FitOut"
		fit.Parent = parent
		local R = newRoom(ctx, room, fit, FRAME[room.kind])
		local ok, err = pcall(function()
			kit(R)
		end)
		for _, d in fit:GetDescendants() do
			if NOISE[d.Name] and d:IsA("BasePart") then
				d:Destroy()
			end
		end
		if not ok then
			table.insert(issues, string.format("%s (%s) failed: %s", room.id, room.kind, tostring(err)))
		end
		if (room.desks or 0) ~= R.desks then
			table.insert(issues, string.format("%s: %d of %d desks placed", room.id, R.desks, room.desks or 0))
		end
		for _, s in R.issues do
			table.insert(issues, s)
		end
	end
	if #issues > 0 then
		warn(string.format("[RoomKitsWork] %d layout issue(s): %s", #issues, table.concat(issues, " | ", 1, math.min(#issues, 12))))
	end
end

return Work
