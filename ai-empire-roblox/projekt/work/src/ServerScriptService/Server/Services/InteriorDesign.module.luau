--!strict
-- InteriorDesign: the interior backbone of the headquarters. Runs after the exterior and the core and
-- before the room kits. It creates one Model per room (ctx.rooms), builds every interior wall and door
-- from the wall planner, the generic room finish (floor, suspended ceiling with integrated lights by
-- mood), nameplates, security cameras, access volumes, the circulation finishes and furniture (lift
-- lobbies, front lounges, founder reception band, corridor ends, wayfinding) and navigation nodes.
-- Everything is building-local through ctx.cf, built with ArchKit and coloured from ArchPalette only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Plan = require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Layout = require(ReplicatedStorage.Shared.BuildingLayout)
local A = require(ReplicatedStorage.Shared.Config.ArchPalette)
local Kit = require(script.Parent.ArchKit)

type Room = Plan.Room
type Wall = Layout.Wall
type DoorDef = Layout.DoorDef
type Rect = { x1: number, x2: number, z1: number, z2: number }
type Span = { a1: number, a2: number, t: number }

local C, M = A.color, A.material
local V3, CF = Vector3.new, CFrame.new
local EPS = 0.01
local FIN = Kit.FINISH
local LIGHT_BUDGET = 150 -- light objects of this module per building (tier 4 is the binding case)
local ANNEX_LIGHT_BUDGET = 13 -- guest house rooms (own budget: the HQ's grants never change because of it)
local GARAGE_CEILING = 11.5 -- garage stage: suspended ceilings of the small rooms under the 13-high roof
local SIGN_Y = 5.6 -- nameplate centre above the finished floor

local InteriorDesign = {}

---------------------------------------------------------------------------------------------
-- Finish tables (room.kind)
---------------------------------------------------------------------------------------------
local FLOOR: { [string]: string } = {
	founder_office = "oak", founder_library = "oak", founder_assist = "marble", lounge = "oak", meeting = "oak",
	boardroom = "oak", focus = "oak", hr = "oak", first_ai = "oak", showroom = "oak", visitor_lounge = "oak",
	project_meeting = "oak", recovery = "oak", archive = "oakDark", secret_passage = "oakDark",
	team = "carpet", architecture = "carpet", launch = "carpetWarm", support = "carpet", studio = "carpetWarm",
	platform = "carpetBlue", datalab = "carpet", control = "carpetBlue", evaluation = "carpetBlue", phone = "carpetWarm",
	print = "carpet", fleet = "carpet", itdesk = "carpetBlue", security = "carpetBlue",
	lab = "terrazzo", hwlab = "terrazzo", prototype = "terrazzo", mailroom = "terrazzo", secret_lab = "slate", vault = "slate",
	gym = "rubber", wc = "tile", restrooms = "tile", showers = "tile", pantry = "tile", kitchen_boh = "tile",
	founder_bath = "marble", sauna = "deck",
	lobby = "stone", atrium = "stone", b1_lobby = "stone", roof_lobby = "stone", garden_lobby = "stone",
	pavilion_corridor = "stone", cafe = "stone",
	compute = "concrete", datahall = "concrete", plant = "concrete", ups = "concrete", workshop = "concrete",
	storage = "concrete", spine = "concrete", liftpit = "concrete", service_passage = "concrete", delivery = "concrete",
	machine = "concrete",
	-- guest house and garage stage
	hotel_lobby = "stone", hotel_breakfast = "oak", hotel_workshop = "oak", hotel_corridor = "carpetWarm", guestroom = "carpetWarm",
	hotel_office = "carpet", hotel_pantry = "tile", hotel_service = "tile",
	garage_lab = "concrete", garage_wc = "tile", garage_founder = "oak",
}
-- Suspended ceiling style; "exposed" = services visible under the slab (soffit + hung battens), "none" = nothing.
local CEILING: { [string]: string } = {
	founder_office = "timber", founder_assist = "timber", founder_library = "timber", lounge = "timber", meeting = "timber",
	boardroom = "timber", project_meeting = "timber", recovery = "timber", sauna = "timber", visitor_lounge = "timber",
	cafe = "timber", garden_lobby = "timber", pavilion_corridor = "timber", archive = "timber",
	wc = "plaster", print = "plaster", restrooms = "plaster", showers = "plaster", founder_bath = "plaster", pantry = "plaster",
	kitchen_boh = "plaster", delivery = "plaster", mailroom = "plaster", plant = "plaster", ups = "plaster", workshop = "plaster",
	storage = "plaster", service_passage = "plaster", liftpit = "plaster", roof_lobby = "plaster", vault = "plaster",
	b1_lobby = "plaster", secret_passage = "plaster", fleet = "plaster", phone = "plaster",
	datahall = "exposed", garage = "exposed", compute = "exposed", machine = "exposed", spine = "exposed",
	lobby = "none", atrium = "none", stair = "none",
	hotel_lobby = "timber", hotel_breakfast = "timber", hotel_workshop = "timber", hotel_corridor = "plaster", guestroom = "plaster",
	hotel_pantry = "plaster", hotel_service = "plaster", hotel_stair = "none",
	garage_lab = "exposed", garage_wc = "plaster", garage_founder = "timber", garage_assist = "none",
}
local NO_FLOOR: { [string]: boolean } = { garage = true, stair = true, hotel_stair = true, garage_assist = true }
local COOL_KINDS: { [string]: boolean } = { datalab = true, evaluation = true, lab = true, hwlab = true, control = true, platform = true, itdesk = true, security = true }
-- Walls between these rooms (and the head house) are rarely seen: build their doors lean.
local TECH_KINDS: { [string]: boolean } = {
	plant = true, ups = true, workshop = true, storage = true, service_passage = true, liftpit = true, spine = true,
	delivery = true, kitchen_boh = true, machine = true, datahall = true,
}

---------------------------------------------------------------------------------------------
-- Build state
---------------------------------------------------------------------------------------------
type State = {
	cf: CFrame,
	tier: number,
	owner: number,
	accent: Color3,
	folders: { [string]: Instance },
	rooms: { [string]: Model },
	circ: { [number]: Model },
	occupied: { [string]: { { number } } },
	lights: { [string]: boolean },
	roomById: { [string]: Room },
	keepOut: { [number]: { Rect } }, -- furniture footprints in the circulation, per level
}

local function levelModel(folder: Instance, level: number): Model
	local name = "Level_" .. level
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("Model") then
		return existing
	end
	return Kit.model(folder, name)
end

local function area(r: Rect): number
	return (r.x2 - r.x1) * (r.z2 - r.z1)
end

local function moodOf(r: Room): string
	local mood = r.mood or "neutral"
	if mood == "neutral" and COOL_KINDS[r.kind] then
		return "cool"
	end
	return mood
end

local function ceilingStyle(r: Room): string
	return CEILING[r.kind] or "acoustic"
end

local function lightable(r: Room): boolean
	return not r.outdoor and ceilingStyle(r) ~= "none"
end

-- Underside of whatever covers the room (suspended ceiling or the slab/roof above), absolute y.
local function coverY(S: State, r: Room): number
	local y = Plan.levelY(r.level)
	local roof = r.level == Plan.roofLevel(S.tier)
	local style = ceilingStyle(r)
	if S.tier < 1 then
		-- garage stage: the roof slab's underside is at GARAGE_LAB.height - 1
		return y + (if style == "exposed" or style == "none" then Plan.GARAGE_LAB.height - Plan.SLAB else GARAGE_CEILING)
	end
	if style == "exposed" or style == "none" then
		if r.level < 0 then
			return Plan.levelY(0) - Plan.SLAB - (if r.kind == "datahall" then 0.1 else 0)
		end
		return y + (if roof then 12 else Plan.FLOOR_HEIGHT - Plan.SLAB)
	end
	if roof then
		return y + 11.7
	elseif r.kind == "sauna" then
		return y + 10.5
	end
	return y + Plan.CEILING
end

local function rectsTouch(a: Rect, b: Rect): boolean
	local ox = math.min(a.x2, b.x2) - math.max(a.x1, b.x1)
	local oz = math.min(a.z2, b.z2) - math.max(a.z1, b.z1)
	return (ox > 1 and math.abs(oz) < EPS) or (oz > 1 and math.abs(ox) < EPS)
end

-- Rect minus rect -> up to four rects.
local function subtractRect(r: Rect, h: Rect): { Rect }
	if h.x1 >= r.x2 or h.x2 <= r.x1 or h.z1 >= r.z2 or h.z2 <= r.z1 then
		return { r }
	end
	local out: { Rect } = {}
	if h.z1 > r.z1 then
		table.insert(out, { x1 = r.x1, x2 = r.x2, z1 = r.z1, z2 = h.z1 })
	end
	if h.z2 < r.z2 then
		table.insert(out, { x1 = r.x1, x2 = r.x2, z1 = h.z2, z2 = r.z2 })
	end
	local z1, z2 = math.max(r.z1, h.z1), math.min(r.z2, h.z2)
	if h.x1 > r.x1 then
		table.insert(out, { x1 = r.x1, x2 = h.x1, z1 = z1, z2 = z2 })
	end
	if h.x2 < r.x2 then
		table.insert(out, { x1 = h.x2, x2 = r.x2, z1 = z1, z2 = z2 })
	end
	return out
end

---------------------------------------------------------------------------------------------
-- Circulation zones (derived from the rectangle centre, see SPEC §11)
---------------------------------------------------------------------------------------------
local function zoneOf(S: State, level: number, r: Rect): string
	local cx, cz = (r.x1 + r.x2) / 2, (r.z1 + r.z2) / 2
	if level == 0 then
		return if math.abs(cx) < 22 and cz > 36 then "lobby" else "ground"
	end
	if level == Plan.founderLevel(S.tier) and cz < -16 then
		return "band"
	end
	if cz < -16 and math.abs(cx) <= 22 then
		return if level == 1 then "bridge" else "front"
	end
	if math.abs(cx) >= 14 and math.abs(cx) <= 22 and cz >= -16 and cz <= 54 then
		return "gallery"
	end
	if math.abs(cx) < 14 and cz >= 36 and cz <= 54 then
		return "lobby"
	end
	if math.abs(cx) >= 42 then
		return "wing"
	end
	return "cross"
end

-- Floor-finish cut-out in front of the lift doors: the landing sill, door track and the core's brass
-- floor marker (z 51.9..52.5) stay on the bare slab, flush with the cabin floor.
local LIFT_FLOOR_HOLES: { Rect } = {
	{ x1 = -3.05, x2 = 3.05, z1 = 51.9, z2 = 54 },
}

local ZONE_FLOOR: { [string]: string } = {
	ground = "stone", lobby = "stone", band = "oak", front = "oak", bridge = "oak", gallery = "oak", wing = "carpet", cross = "carpet",
}
local ZONE_MOOD: { [string]: string } = {
	ground = "warm", lobby = "neutral", band = "founder", front = "warm", bridge = "warm", gallery = "neutral", wing = "neutral", cross = "neutral",
}

local function inCirculation(S: State, level: number, x: number, z: number): boolean
	for _, r in Layout.circulation(S.tier, level) do
		if x > r.x1 and x < r.x2 and z > r.z1 and z < r.z2 then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------------------------
-- Light budget: every lit thing asks for light objects with a priority; the best ones get them.
---------------------------------------------------------------------------------------------
type LightReq = { key: string, prio: number, area: number }

local function planLights(S: State): { [string]: boolean }
	local reqs: { LightReq } = {}
	local smallLit: { [number]: { Room } } = {}
	for _, r in Plan.rooms(S.tier) do
		if r.annex or not lightable(r) then
			continue
		end
		local a = area(r)
		if a < 300 then
			-- small rooms share one light with a small neighbour (lights cast no shadows, so a light
			-- near the party wall reaches both rooms)
			local list: { Room } = smallLit[r.level] or {}
			smallLit[r.level] = list
			local shared = false
			for _, o in list do
				if rectsTouch(r, o) then
					shared = true
					break
				end
			end
			if not shared then
				table.insert(list, r)
				table.insert(reqs, { key = r.id .. "#1", prio = 70, area = a })
			end
		else
			table.insert(reqs, { key = r.id .. "#1", prio = 90, area = a })
			local short = math.min(r.x2 - r.x1, r.z2 - r.z1)
			if a >= 600 and (short >= 15 or ceilingStyle(r) == "exposed") then
				table.insert(reqs, { key = r.id .. "#2", prio = 50, area = a })
			end
		end
	end
	for level = 0, Plan.founderLevel(S.tier) do
		for i, r in Layout.circulation(S.tier, level) do
			local zone = zoneOf(S, level, r)
			local len = math.max(r.x2 - r.x1, r.z2 - r.z1)
			local prio = 40
			if zone == "lobby" or zone == "front" or zone == "band" then
				prio = 80
			elseif (zone == "wing" or zone == "ground") and len >= 24 then
				prio = 60
			elseif zone == "bridge" then
				prio = 0 -- the bridge belongs to the double-height hall: no ceiling, no light
			end
			if prio > 0 then
				table.insert(reqs, { key = string.format("C%d_%d#1", level, i), prio = prio, area = area(r) })
			end
		end
	end
	table.sort(reqs, function(a, b)
		if a.prio ~= b.prio then
			return a.prio > b.prio
		end
		if a.area ~= b.area then
			return a.area > b.area
		end
		return a.key < b.key
	end)
	local granted: { [string]: boolean } = {}
	for i = 1, math.min(#reqs, LIGHT_BUDGET) do
		granted[reqs[i].key] = true
	end
	-- guest house rooms: same rules with their own budget
	local annexReqs: { LightReq } = {}
	local annexSmall: { [number]: { Room } } = {}
	for _, r in Plan.rooms(S.tier) do
		if not r.annex or not lightable(r) then
			continue
		end
		local a = area(r)
		if a < 300 then
			local list: { Room } = annexSmall[r.level] or {}
			annexSmall[r.level] = list
			local shared = false
			for _, o in list do
				if rectsTouch(r, o) then
					shared = true
					break
				end
			end
			if not shared then
				table.insert(list, r)
				table.insert(annexReqs, { key = r.id .. "#1", prio = 70, area = a })
			end
		else
			table.insert(annexReqs, { key = r.id .. "#1", prio = 90, area = a })
			local short = math.min(r.x2 - r.x1, r.z2 - r.z1)
			if a >= 600 and short >= 15 then
				table.insert(annexReqs, { key = r.id .. "#2", prio = 50, area = a })
			end
		end
	end
	table.sort(annexReqs, function(a, b)
		if a.prio ~= b.prio then
			return a.prio > b.prio
		end
		if a.area ~= b.area then
			return a.area > b.area
		end
		return a.key < b.key
	end)
	for i = 1, math.min(#annexReqs, ANNEX_LIGHT_BUDGET) do
		granted[annexReqs[i].key] = true
	end
	return granted
end

-- Garage stage: walled rooms standing inside an open container room (WC and founder corner inside
-- the garage lab) keep their own floor and ceiling, so the container's finish leaves them out.
local function carved(S: State, r: Room, rect: Rect): { Rect }
	if S.tier >= 1 or not r.nowalls then
		return { rect }
	end
	local pieces = { rect }
	for _, o in Plan.roomsOnLevel(S.tier, r.level) do
		if o ~= r and not o.nowalls and not o.outdoor and o.x1 >= r.x1 and o.x2 <= r.x2 and o.z1 >= r.z1 and o.z2 <= r.z2 then
			local nextPieces: { Rect } = {}
			for _, piece in pieces do
				for _, q in subtractRect(piece, o) do
					table.insert(nextPieces, q)
				end
			end
			pieces = nextPieces
		end
	end
	return pieces
end

-- Light the strips of a ceiling: #1 on the first strip, #2 on the last one (when there are two).
local function lightStrips(S: State, key: string, strips: { Part }, mood: string)
	if #strips == 0 then
		return
	end
	if S.lights[key .. "#1"] then
		Kit.light(strips[1], "surface", mood, nil, nil, Enum.NormalId.Bottom)
	end
	if S.lights[key .. "#2"] and #strips >= 2 then
		Kit.light(strips[#strips], "surface", mood, nil, nil, Enum.NormalId.Bottom)
	end
end

---------------------------------------------------------------------------------------------
-- Wall faces: free spans along one face of a wall line (for nameplates, art, directories)
---------------------------------------------------------------------------------------------
local function faceKey(level: number, axis: string, c: number, side: number): string
	return string.format("%d:%s%.2f:%d", level, axis, c, side)
end

local function occupy(S: State, level: number, axis: string, c: number, side: number, a1: number, a2: number)
	local key = faceKey(level, axis, c, side)
	local list = S.occupied[key] or {}
	S.occupied[key] = list
	table.insert(list, { a1, a2 })
end

local function cutSpans(spans: { Span }, b1: number, b2: number): { Span }
	local out: { Span } = {}
	for _, s in spans do
		if b2 <= s.a1 or b1 >= s.a2 then
			table.insert(out, s)
		else
			if b1 > s.a1 then
				table.insert(out, { a1 = s.a1, a2 = b1, t = s.t })
			end
			if b2 < s.a2 then
				table.insert(out, { a1 = b2, a2 = s.a2, t = s.t })
			end
		end
	end
	return out
end

-- Free wall surface on the `side` face of line (axis, c) within [lo, hi]: wall runs minus openings
-- (± margin), perpendicular walls meeting the face, the envelope, the lift portal and occupied spans.
local function freeSpans(S: State, level: number, axis: string, c: number, side: number, lo: number, hi: number, margin: number): { Span }
	local walls = Layout.walls(S.tier, level)
	local spans: { Span } = {}
	for _, w in walls do
		if w.axis == axis and math.abs(w.c - c) < EPS and (w.finish == "solid" or w.finish == "panel" or w.finish == "glass" or w.finish == "fence") then
			local a1, a2 = math.max(w.a1, lo), math.min(w.a2, hi)
			if a2 - a1 > 0.1 then
				table.insert(spans, { a1 = a1, a2 = a2, t = Kit.WALL_T[w.finish] or 1 })
			end
		end
	end
	for _, w in walls do
		if w.axis == axis and math.abs(w.c - c) < EPS then
			for _, op in w.openings do
				spans = cutSpans(spans, op.a1 - margin, op.a2 + margin)
			end
		elseif w.axis ~= axis and w.a1 <= c + EPS and w.a2 >= c - EPS then
			local reaches = if side > 0 then w.a2 > c + 0.05 else w.a1 < c - 0.05
			if reaches then
				local t = Kit.WALL_T[w.finish] or 1
				spans = cutSpans(spans, w.c - t / 2 - 0.15, w.c + t / 2 + 0.15)
			end
		end
	end
	-- envelope lines (facades are built by the exterior; assume up to 1.5 of depth around the line)
	local env: { number } = if axis == "x" then { Plan.MAIN.x1, Plan.MAIN.x2, Plan.GARAGE.x1, Plan.GARAGE.x2 } else { Plan.MAIN.z1, Plan.MAIN.z2, Plan.FOUNDER_FRONT_Z, Plan.PAVILION.z2, Plan.GARAGE.z1, Plan.GARAGE.z2 }
	if S.tier < 1 then
		local g = Plan.GARAGE_LAB
		env = if axis == "x" then { g.x1, g.x2 } else { g.z1, g.z2 }
	elseif Plan.hasHotel(S.tier) then
		local h = Plan.HOTEL
		if axis == "x" then
			table.insert(env, h.x1)
			table.insert(env, h.x2)
		elseif c > h.x1 - 0.1 and c < h.x2 + 0.1 then
			table.insert(env, h.z1)
			table.insert(env, h.z2)
		end
	end
	for _, e in env do
		spans = cutSpans(spans, e - 1.5, e + 1.5)
	end
	-- lift shaft and its portal cladding
	local sh = Plan.SHAFT
	if axis == "x" and c > sh.z1 - 2 and c < sh.z2 + 0.5 then
		spans = cutSpans(spans, sh.x1 - 0.8, sh.x2 + 0.8)
	elseif axis == "z" and math.abs(math.abs(c) - sh.x2) < 0.6 then
		spans = cutSpans(spans, sh.z1 - 1.2, sh.z2 + 0.6)
	end
	local taken: { { number } } = S.occupied[faceKey(level, axis, c, side)] or {}
	for _, o in taken do
		spans = cutSpans(spans, o[1], o[2])
	end
	return spans
end

-- Register a furniture footprint (building-local) so navigation nodes stay off it.
local function keep(S: State, level: number, x: number, z: number, w: number, d: number)
	local list: { Rect } = S.keepOut[level] or {}
	S.keepOut[level] = list
	table.insert(list, { x1 = x - w / 2, x2 = x + w / 2, z1 = z - d / 2, z2 = z + d / 2 })
end

-- A free standing point in a circulation rectangle: its centre, else the nearest clear point along it.
local function clearPoint(S: State, level: number, r: Rect): (number, number)
	local cx, cz = (r.x1 + r.x2) / 2, (r.z1 + r.z2) / 2
	local alongX = (r.x2 - r.x1) >= (r.z2 - r.z1)
	local half = math.max(r.x2 - r.x1, r.z2 - r.z1) / 2 - 1.5
	local list: { Rect } = S.keepOut[level] or {}
	local function blocked(x: number, z: number): boolean
		for _, k in list do
			if x > k.x1 - 1.6 and x < k.x2 + 1.6 and z > k.z1 - 1.6 and z < k.z2 + 1.6 then
				return true
			end
		end
		return false
	end
	local step = 0
	while step <= half do
		for _, sgn in { 1, -1 } do
			local x = if alongX then cx + sgn * step else cx
			local z = if alongX then cz else cz + sgn * step
			if not blocked(x, z) then
				return x, z
			end
		end
		step += 1
	end
	return cx, cz
end

local function spanContaining(spans: { Span }, a1: number, a2: number): Span?
	for _, s in spans do
		if a1 >= s.a1 - EPS and a2 <= s.a2 + EPS then
			return s
		end
	end
	return nil
end

-- CFrame on a wall face at floor level, facing away from the wall (wall-item anchor).
local function faceAt(axis: string, c: number, side: number, t: number, a: number, y: number): CFrame
	local n = c + side * t / 2
	if axis == "x" then
		return Kit.place(a, y, n, if side > 0 then "N" else "S")
	end
	return Kit.place(n, y, a, if side > 0 then "E" else "W")
end

---------------------------------------------------------------------------------------------
-- 1. Room models
---------------------------------------------------------------------------------------------
local function buildRoomModels(S: State)
	for _, r in Plan.rooms(S.tier) do
		local m = S.rooms[r.id]
		if not m then
			m = Kit.model(S.folders.Rooms, r.id, true)
			S.rooms[r.id] = m
		end
		m:SetAttribute("RoomId", r.id)
		m:SetAttribute("RoomName", r.name)
		m:SetAttribute("RoomKind", r.kind)
		m:SetAttribute("Level", r.level)
		m:SetAttribute("AccessClass", r.access)
		m:SetAttribute("Hidden", r.hidden == true)
		S.roomById[r.id] = r
	end
end

---------------------------------------------------------------------------------------------
-- 2. Walls and interior doors
---------------------------------------------------------------------------------------------
local function isTechSide(S: State, id: string?): boolean
	if id == nil then
		return false
	end
	local r = S.roomById[id]
	return r ~= nil and TECH_KINDS[r.kind] == true
end

local function buildWalls(S: State, level: number)
	local segs = Layout.walls(S.tier, level)
	if #segs == 0 then
		return
	end
	local model = levelModel(S.folders.Walls, level)
	local ext = Kit.wallExtents(segs)
	local roof = level == Plan.roofLevel(S.tier)
	local y = Plan.levelY(level)
	for _, seg in segs do
		-- lean doors (no hinges/kick plates/grilles) only where nobody looks closely
		local lean = (roof and seg.finish == "solid") or (isTechSide(S, seg.plus) and (seg.minus == nil or isTechSide(S, seg.minus))) or (isTechSide(S, seg.minus) and seg.plus == nil and level < 0)
		local before = Kit.LEAN
		Kit.LEAN = before or lean
		local ok, err = pcall(function()
			local e = ext[seg] or { 0, 0 }
			Kit.wall(model, S.cf, seg, y, S.owner, S.folders.Doors, {
				extend1 = e[1],
				extend2 = e[2],
				skirting = if seg.finish == "glass" or lean then "none" else nil,
				bay = 12, -- butt-jointed partitions: a slim mullion every <= 12 studs
			})
		end)
		Kit.LEAN = before
		if not ok then
			warn(string.format("[Interior] wall %s c=%g a=%g..%g failed: %s", seg.axis, seg.c, seg.a1, seg.a2, tostring(err)))
		end
	end
end

---------------------------------------------------------------------------------------------
-- 3. Room finishes
---------------------------------------------------------------------------------------------
-- Linear batten hung under an exposed soffit (housing + neon diffuser + two hangers).
local function batten(parent: Instance, cf: CFrame, x: number, z: number, soffit: number, length: number, alongX: boolean, mood: string, lit: boolean)
	local y = soffit - 0.9
	local function size(l: number, h: number, w: number): Vector3
		return if alongX then V3(l, h, w) else V3(w, h, l)
	end
	Kit.part(parent, cf, "Batten", size(length, 0.22, 0.5), CF(x, y, z), C.metal, M.metal, { canCollide = false, canQuery = false, canTouch = false })
	local glow = (A.mood :: any)[mood] and (A.mood :: any)[mood].color or C.lightNeutral
	local diffuser = Kit.part(parent, cf, "BattenLight", size(length - 0.3, 0.05, 0.34), CF(x, y - 0.13, z), glow, M.neon, { detail = true })
	for _, k in { -1, 1 } do
		local off = k * (length / 2 - 1)
		local hx, hz = if alongX then x + off else x, if alongX then z else z + off
		Kit.part(parent, cf, "BattenHanger", V3(0.08, 0.8, 0.08), CF(hx, soffit - 0.4, hz), C.metalSoft, M.metal, { detail = true })
	end
	if lit then
		Kit.light(diffuser, "surface", mood, nil, nil, Enum.NormalId.Bottom)
	end
end

-- Timber baffle ceiling: oak slats on a 3-stud pitch over a dark felt backing with neon strips in the
-- gaps. ArchKit's "timber" style uses a 1.5 pitch (twice the parts); this keeps real timber affordable
-- in every meeting room and lounge. Returns the strip parts.
local function timberCeiling(parent: Instance, cf: CFrame, rect: Rect, levelY: number, h: number, mood: string): { Part }
	local W, D = rect.x2 - rect.x1, rect.z2 - rect.z1
	local alongX = W >= D
	local L, Sw = math.max(W, D), math.min(W, D)
	local cx, cz = (rect.x1 + rect.x2) / 2, (rect.z1 + rect.z2) / 2
	local yb = levelY + h
	local function at(l: number, s: number, y: number): CFrame
		return if alongX then CF(cx + l, y, cz + s) else CF(cx + s, y, cz + l)
	end
	local function size(l: number, y: number, w: number): Vector3
		return if alongX then V3(l, y, w) else V3(w, y, l)
	end
	Kit.part(parent, cf, "CeilingBacking", size(L, 0.05, Sw), at(0, 0, yb + 0.275), C.fabricCharcoal, M.fabric)
	local n = math.max(1, math.floor(Sw / 3))
	local pitch = Sw / n
	for i = 0, n - 1 do
		Kit.part(parent, cf, "CeilingSlat", size(L, 0.25, math.min(1.5, pitch - 0.6)), at(0, -Sw / 2 + (i + 0.5) * pitch, yb + 0.125), C.oakLight, M.wood)
	end
	local glow = (A.mood :: any)[mood] and (A.mood :: any)[mood].color or C.lightNeutral
	local rows = math.clamp(math.floor(Sw / 12 + 0.5), 1, 3)
	local strips: { Part } = {}
	for r = 1, rows do
		local gi = math.clamp(math.floor((r - 0.5) / rows * n + 0.5), 1, math.max(1, n - 1))
		table.insert(strips, Kit.part(parent, cf, "LightStrip", size(math.max(L - 3, 1), 0.06, 0.25), at(0, -Sw / 2 + gi * pitch, yb + 0.03), glow, M.neon, { detail = true }))
	end
	return strips
end

local function finishRoom(S: State, r: Room)
	if r.outdoor then
		return
	end
	local model = S.rooms[r.id]
	local cf = S.cf
	local y = Plan.levelY(r.level)
	local rect: Rect = { x1 = r.x1, x2 = r.x2, z1 = r.z1, z2 = r.z2 }
	local floor = FLOOR[r.kind]
	if floor and not NO_FLOOR[r.kind] then
		local pieces = carved(S, r, rect)
		if r.kind == "lobby" then
			pieces = subtractRect(rect, Plan.PORTAL) -- the covered entrance recess is outside
		end
		for _, p in pieces do
			Kit.floor(model, cf, p, y, floor, { name = "Floor" })
		end
	end
	local style = ceilingStyle(r)
	local mood = moodOf(r)
	if style == "none" then
		return
	elseif style == "exposed" then
		local soffit = coverY(S, r)
		if r.kind == "datahall" then
			-- dark painted soffit; the data hall kit adds trays and busways below it
			Kit.part(model, cf, "Soffit", V3(r.x2 - r.x1, 0.1, r.z2 - r.z1), CF((r.x1 + r.x2) / 2, soffit + 0.05, (r.z1 + r.z2) / 2), C.fabricCharcoal, M.plaster, { castShadow = false })
		end
		local W, D = r.x2 - r.x1, r.z2 - r.z1
		local alongX = W >= D
		local L, Sh = math.max(W, D), math.min(W, D)
		local n = if L * Sh >= 600 then 2 else 1
		local len = math.min(L - 4, if r.kind == "spine" then 40 else 30)
		for i = 1, n do
			local s = -Sh / 2 + (i - 0.5) * Sh / n
			local l = 0
			if r.kind == "spine" then
				l = (i - 1.5) * L / 2
				s = 0
			end
			local cx = (r.x1 + r.x2) / 2 + (if alongX then l else s)
			local cz = (r.z1 + r.z2) / 2 + (if alongX then s else l)
			batten(model, cf, cx, cz, soffit, len, alongX, mood, S.lights[r.id .. "#" .. i] == true)
		end
		return
	end
	local h = coverY(S, r) - y
	local strips: { Part } = {}
	for _, piece in carved(S, r, rect) do
		local pieceStrips: { Part }
		if style == "timber" then
			pieceStrips = timberCeiling(model, cf, piece, y, h, mood)
		else
			local _, kitStrips = Kit.ceiling(model, cf, piece, y, style, mood, { maxLights = 0, height = h, name = "Ceiling" })
			pieceStrips = kitStrips
		end
		for _, st in pieceStrips do
			table.insert(strips, st)
		end
	end
	lightStrips(S, r.id, strips, mood)
end

---------------------------------------------------------------------------------------------
-- 4. Nameplates and 8. room entry nodes
---------------------------------------------------------------------------------------------
local function segmentOf(S: State, d: DoorDef): Wall?
	for _, w in Layout.walls(S.tier, d.level) do
		for _, op in w.openings do
			if op.door and op.door.id == d.id then
				return w
			end
		end
	end
	return nil
end

local function subLabel(r: Room): string?
	if r.access == "staff" then
		return nil
	end
	return (Plan.CLASS_LABEL :: any)[r.access]
end

local SKIP_PLATE: { [string]: boolean } = { flush = true, bookcase = true, vault = true, speedgate = true }

local function doorFittings(S: State, d: DoorDef)
	local r = S.roomById[d.room]
	if not r or d.builder ~= "interior" then
		return
	end
	local axis = d.axis
	local c = if axis == "x" then d.z else d.x
	local da = if axis == "x" then d.x else d.z
	local roomMid = if axis == "x" then (r.z1 + r.z2) / 2 else (r.x1 + r.x2) / 2
	local side = if roomMid > c then -1 else 1 -- the corridor side = away from the room
	local y = Plan.levelY(d.level)
	local hidden = d.hidden or r.hidden == true
	if not hidden then
		local nx, nz = if axis == "x" then d.x else c + side * 2.5, if axis == "x" then c + side * 2.5 else d.z
		Kit.node(S.folders.Navigation, S.cf, "Entry_" .. d.id, nx, y + FIN, nz, "RoomEntry", d.level)
	end
	if hidden or SKIP_PLATE[d.kind] then
		return
	end
	-- doors opening into the founder's own office (library, bathroom, reception) carry no signs
	local ox, oz = if axis == "x" then d.x else c + side * 1.5, if axis == "x" then c + side * 1.5 else d.z
	local outside = Plan.roomAt(S.tier, V3(ox, y + 3, oz))
	if outside and outside.kind == "founder_office" then
		return
	end
	local seg = segmentOf(S, d)
	if not seg then
		return
	end
	local parent = S.circ[d.level] or levelModel(S.folders.Circulation, d.level)
	S.circ[d.level] = parent
	-- latch side first (local +X of the door frame), then the hinge side, else above the door
	local right = V3(0, 1, 0):Cross(d.inward.Unit)
	local alongVec = if axis == "x" then V3(1, 0, 0) else V3(0, 0, 1)
	local latch = if right:Dot(alongVec) >= 0 then 1 else -1
	local spans = freeSpans(S, d.level, axis, c, side, seg.a1 - 40, seg.a2 + 40, 0)
	local half = d.w / 2
	local a: number? = nil
	local t = Kit.WALL_T[seg.finish] or 1
	for _, dir in { latch, -latch } do
		local p1 = if dir > 0 then da + half + 0.3 else da - half - 3.6
		local s = spanContaining(spans, p1, p1 + 3.3)
		if s then
			a = p1 + 1.65
			t = s.t
			occupy(S, d.level, axis, c, side, p1 - 0.1, p1 + 3.4)
			break
		end
	end
	local sy = SIGN_Y
	if a == nil then
		if seg.height < d.h + 1.5 then
			return
		end
		a = da
		sy = d.h + 0.75
	end
	local at = faceAt(axis, c, side, t, a :: number, y + FIN)
	Kit.signPlate(parent, S.cf, at, r.name, subLabel(r), { y = sy, name = "Nameplate_" .. d.id })
end

---------------------------------------------------------------------------------------------
-- 5. Cameras
---------------------------------------------------------------------------------------------
local function roomCamera(S: State, r: Room)
	if not r.camera or (Plan.NO_CAMERA :: any)[r.kind] then
		return
	end
	local y = Plan.levelY(r.level)
	local pos, target
	if r.kind == "lobby" then
		-- under the level-1 bridge, watching the entrance
		pos, target = V3(18.5, Plan.levelY(1) - Plan.SLAB - 1, -23), V3(0, y + 4, Plan.ENTRANCE.z)
	elseif r.kind == "atrium" then
		pos, target = V3(-20.5, Plan.levelY(1) - Plan.SLAB - 1, 34), V3(12, y + 2.5, -14)
	elseif r.outdoor then
		-- roof terrace: under the head house roof overhang at its front corner
		pos, target = V3(-20.6, y + 11, 41.32), V3(70, y + 2, -15)
	else
		local top = coverY(S, r) - 1
		local inset = 1.5
		local corners = { V3(r.x1 + inset, top, r.z1 + inset), V3(r.x2 - inset, top, r.z1 + inset), V3(r.x1 + inset, top, r.z2 - inset), V3(r.x2 - inset, top, r.z2 - inset) }
		local door = r.doors[1]
		local best = 1
		if door then
			local doorPos
			if door.face == "N" or door.face == "S" then
				doorPos = V3(door.at, top, if door.face == "N" then r.z2 else r.z1)
			else
				doorPos = V3(if door.face == "E" then r.x2 else r.x1, top, door.at)
			end
			local bd = math.huge
			for i, p in corners do
				local dd = (p - doorPos).Magnitude
				if dd < bd then
					bd, best = dd, i
				end
			end
		end
		pos = corners[best]
		local opp = corners[5 - best]
		target = V3(opp.X, y + 2.5, opp.Z)
	end
	local name = r.name .. " · " .. Plan.levelLabel(S.tier, r.level)
	Kit.camera(S.folders.Cameras, S.cf, r.id, name, pos, target, r.level, r.id, r.access == "founder" or r.hidden == true)
end

---------------------------------------------------------------------------------------------
-- 7. Circulation
---------------------------------------------------------------------------------------------
local function arrowFor(forward: Vector3, dir: Vector3): string?
	local d = V3(dir.X, 0, dir.Z)
	if d.Magnitude < 1e-3 then
		return "↑"
	end
	d = d.Unit
	local f = V3(forward.X, 0, forward.Z).Unit
	local right = f:Cross(V3(0, 1, 0))
	local ahead = d:Dot(f)
	if ahead > 0.75 then
		return "↑"
	elseif ahead < -0.75 then
		return nil -- behind the viewer: not on this face
	end
	return if d:Dot(right) > 0 then "→" else "←"
end

type Dest = { text: string, dir: Vector3 }

-- Ceiling-hung double-sided sign across a corridor at (x, z): `alongX` = the plate spans X.
local function hungSign(S: State, level: number, parent: Instance, x: number, z: number, alongX: boolean, title: string, dests: { Dest }, ceil: number)
	local y = Plan.levelY(level) + FIN
	local faces: { { n: number, lines: { string } } } = {}
	local maxLines = 0
	for _, n in { 1, -1 } do
		-- the face looks along n; its viewers walk towards -n
		local normal = if alongX then V3(0, 0, n) else V3(n, 0, 0)
		local lines = { title }
		for _, dst in dests do
			local arrow = arrowFor(-normal, dst.dir)
			if arrow then
				table.insert(lines, if arrow == "→" then dst.text .. "  →" else arrow .. "  " .. dst.text)
			end
		end
		if #lines >= 2 then
			table.insert(faces, { n = n, lines = lines })
			maxLines = math.max(maxLines, #lines)
		end
	end
	if #faces == 0 then
		return
	end
	-- both faces hang from one rod: align their top edges
	local top = math.min(8.7 + 0.5 + maxLines * 0.5, ceil - 0.6)
	for _, f in faces do
		local H = 0.5 + #f.lines * 0.5
		local at = if alongX then Kit.place(x, y, z, if f.n > 0 then "N" else "S") else Kit.place(x, y, z, if f.n > 0 then "E" else "W")
		Kit.wayfinding(parent, S.cf, at, f.lines, { y = top - H / 2, name = "CorridorSign" })
	end
	local rodLen = math.max(ceil - top, 0.3)
	Kit.part(parent, S.cf, "SignHanger", V3(0.1, rodLen, 0.1), CF(x, y + ceil - rodLen / 2, z), C.metal, M.metal, { detail = true })
end

-- Floor directory pylon (stone slab with west/east plates and a title band), facing +Z (the lift).
local function directoryPylon(S: State, level: number, parent: Instance, px: number, pz: number)
	local y = Plan.levelY(level) + FIN
	local west, east = {}, {}
	local rooms = Plan.roomsOnLevel(S.tier, level)
	table.sort(rooms, function(a, b)
		local za, zb = (a.z1 + a.z2) / 2, (b.z1 + b.z2) / 2
		if math.abs(za - zb) > 0.1 then
			return za < zb
		end
		return a.id < b.id
	end)
	local pavilion = false
	local annex = false
	for _, r in rooms do
		if r.annex then
			annex = annex or (r.level == 0)
			continue -- the guest house has its own lobby and stair
		end
		if r.hidden or r.outdoor or r.kind == "atrium" or r.kind == "lobby" then
			continue
		end
		if r.pavilion then
			pavilion = pavilion or (r.level == 0)
			continue
		end
		table.insert(if (r.x1 + r.x2) / 2 < 0 then west else east, r.name)
	end
	if pavilion then
		table.insert(west, "Wellness pavilion (rear)")
		table.insert(east, "Wellness pavilion (rear)")
	end
	if annex then
		table.insert(west, "Guest house (west path)")
	end
	local W, H = 9, 10
	Kit.part(parent, S.cf, "DirectoryPylon", V3(W, H, 0.8), CF(px, y + H / 2, pz), C.stoneDeep, M.stone)
	local face = pz + 0.4
	local n = math.max(#west, #east) + 1
	local lh = if n > 13 then 0.42 else 0.5
	-- the viewer faces -Z: +X (east) is on the right
	Kit.wayfinding(parent, S.cf, Kit.place(px - 2.2, y, face, "N"), { "WEST  ←", table.unpack(west) }, { y = 5.4, h = lh, name = "FloorDirectory" })
	Kit.wayfinding(parent, S.cf, Kit.place(px + 2.2, y, face, "N"), { "EAST  →", table.unpack(east) }, { y = 5.4, h = lh, name = "FloorDirectory" })
	local band = Kit.part(parent, S.cf, "DirectoryTitle", V3(W - 0.4, 0.9, 0.1), Kit.place(px, y + 9.2, face + 0.05, "N"), C.metal, M.metal)
	Kit.text(band, Plan.floorTitle(S.tier, level), { color = C.brass, guiName = "Sign", maxDistance = 60, pps = 60 })
end

local function liftLobby(S: State, level: number, parent: Instance)
	local y = Plan.levelY(level) + FIN
	local seed = Kit.hash("lobby" .. level)
	-- bench looking into the atrium, directory facing the lift, a tall plant at the west gallery end
	-- (bench front 4 studs behind the atrium balustrade so people can step in and sit)
	Kit.bench(parent, S.cf, Kit.place(-9, y, 41.0, "S"), 6, seed)
	keep(S, level, -9, 41.0, 6, 1.6)
	directoryPylon(S, level, parent, 8.0, 37.6)
	keep(S, level, 8.0, 37.6, 9, 0.8)
	Kit.plant(parent, S.cf, CF(-19.2, y, 51.0), "l", seed + 3)
	keep(S, level, -19.2, 51.0, 2.4, 2.4)
	-- keep wall art clear of the plant's foliage
	occupy(S, level, "z", -22, 1, 48.5, 54.5)
	occupy(S, level, "x", 54, -1, -22.5, -17.5)
	if level >= 1 and level <= Plan.founderLevel(S.tier) then
		local top = Plan.levelY(level) + Plan.CEILING - 1
		Kit.camera(S.folders.Cameras, S.cf, string.format("L%d_LIFTLOBBY", level), "Lift lobby · " .. Plan.levelLabel(S.tier, level),
			V3(20.4, top, 52.6), V3(-12, Plan.levelY(level) + 2.5, 38), level, string.format("L%d_LIFTLOBBY", level), false)
	end
end

local function frontLounge(S: State, level: number, parent: Instance)
	local y = Plan.levelY(level) + FIN
	local base = Kit.hash(string.format("front%d", level))
	for g, gx in { -10.5, 10.5 } do
		local s = base + g * 101
		Kit.rug(parent, S.cf, CF(gx, y, -36.6), 13, 10, s)
		keep(S, level, gx, -35.0, 13, 7.6) -- sofa, table and armchair (the rug edge stays walkable)
		Kit.sofa(parent, S.cf, Kit.place(gx, y, -32.4, "S"), 8, s + 1)
		Kit.coffeeTable(parent, S.cf, CF(gx, y, -37.1), s + 2, 5, 2.4)
		local cx = gx + (if gx < 0 then -5.8 else 5.8)
		Kit.loungeChair(parent, S.cf, Kit.place(cx, y, -36.8, if gx < 0 then "E" else "W"), s + 3)
		Kit.plant(parent, S.cf, CF(gx + (if gx < 0 then -7 else 7), y, -44), "tree", s + 4)
		keep(S, level, gx + (if gx < 0 then -7 else 7), -44, 3.6, 3.6)
	end
	-- two conversation pairs by the glazed front
	local group = string.format("L%d_FRONT", level)
	local k = 0
	for _, pair in { { -13.8, -10.2 }, { 10.2, 13.8 } } do
		for i = 1, 2 do
			k += 1
			local x, other = pair[i], pair[3 - i]
			local p = V3(x, y, -40.5)
			Kit.activity(parent, S.cf, string.format("%s_TALK%d", group, k), "Conversation", "social", "any", Kit.facing(p, V3(other, y, -40.5)), level, S.owner, nil, {
				facing = V3(other, y, -40.5),
				conversationGroup = group,
				roomAccess = "staff",
			})
		end
	end
end

local function founderBand(S: State, level: number, parent: Instance)
	local y = Plan.levelY(level) + FIN
	local seed = Kit.hash("band" .. level)
	for i, x in { -18, 18 } do
		Kit.bench(parent, S.cf, Kit.place(x, y, -27.4, "S"), 6, seed + i)
		keep(S, level, x, -27.4, 6, 1.6)
		Kit.plant(parent, S.cf, CF(x + (if x < 0 then -11 else 11), y, -28.2), "tree", seed + i * 7)
		keep(S, level, x + (if x < 0 then -11 else 11), -28.2, 3.6, 3.6)
	end
	-- reception console with a large artwork on the founder reception wall (corridor face z = -24.5)
	local spans = freeSpans(S, level, "x", -24, -1, 22, 42, 2.5)
	local s = spanContaining(spans, 28, 36)
	if s then
		local at = faceAt("x", -24, -1, s.t, 32, y)
		Kit.sideboard(parent, S.cf, at, 7, seed + 11)
		Kit.artwork(parent, S.cf, at, 6, 3.4, seed + 12, { y = 6.8, name = "Artwork" })
		occupy(S, level, "x", -24, -1, 28, 36)
	end
end

-- Bench + plant at the front (facade) window ends of the wing corridors.
local function corridorEnds(S: State, level: number, parent: Instance, r: Rect)
	local y = Plan.levelY(level) + FIN
	local sgn = if r.x1 < 0 then -1 else 1
	local ends: { number } = {}
	if math.abs(r.z1 - Plan.MAIN.z1) < EPS and level >= 1 then
		table.insert(ends, -1)
	end
	for _, e in ends do
		local seed = Kit.hash(string.format("end%d_%d_%d", level, sgn, e))
		local zb = if e < 0 then r.z1 + 5 else r.z2 - 4.5
		local zp = if e < 0 then r.z1 + 2.1 else r.z2 - 2.1
		Kit.bench(parent, S.cf, Kit.place(sgn * 48.9, y, zb, if sgn < 0 then "E" else "W"), 5, seed)
		Kit.plant(parent, S.cf, CF(sgn * 43.4, y, zp), "s", seed + 1)
		keep(S, level, sgn * 48.9, zb, 1.6, 5)
		keep(S, level, sgn * 43.4, zp, 1.2, 1.2)
	end
end

-- Artwork on long solid corridor walls (free of doors, nameplates and fittings).
local function corridorArt(S: State, level: number, parent: Instance, maxCount: number)
	type Cand = { axis: string, c: number, side: number, a1: number, a2: number, t: number }
	local cands: { Cand } = {}
	for _, w in Layout.walls(S.tier, level) do
		if w.finish ~= "solid" and w.finish ~= "panel" then
			continue
		end
		for _, side in { 1, -1 } do
			if (if side > 0 then w.plus else w.minus) ~= nil then
				continue
			end
			for _, sp in freeSpans(S, level, w.axis, w.c, side, w.a1, w.a2, 2.8) do
				local mid = (sp.a1 + sp.a2) / 2
				local px = if w.axis == "x" then mid else w.c + side * 2
				local pz = if w.axis == "x" then w.c + side * 2 else mid
				if sp.a2 - sp.a1 >= 7 and inCirculation(S, level, px, pz) then
					table.insert(cands, { axis = w.axis, c = w.c, side = side, a1 = sp.a1, a2 = sp.a2, t = sp.t })
				end
			end
		end
	end
	table.sort(cands, function(a, b)
		local la, lb = a.a2 - a.a1, b.a2 - b.a1
		if math.abs(la - lb) > 0.01 then
			return la > lb
		end
		return a.c + a.a1 < b.c + b.a1
	end)
	local y = Plan.levelY(level) + FIN
	for i = 1, math.min(maxCount, #cands) do
		local cd = cands[i]
		local len = cd.a2 - cd.a1
		local mid = (cd.a1 + cd.a2) / 2
		local w = math.min(6, len - 2)
		local seed = Kit.hash(string.format("art%d_%s%g_%g", level, cd.axis, cd.c, mid))
		Kit.artwork(parent, S.cf, faceAt(cd.axis, cd.c, cd.side, cd.t, mid, y), w, if w >= 5 then 3.6 else 3, seed, { y = 6.0, name = "Artwork" })
		occupy(S, level, cd.axis, cd.c, cd.side, mid - w / 2, mid + w / 2)
	end
end

local function groundSigns(S: State, parent: Instance)
	local ceil = Plan.CEILING
	local X, Z = V3(1, 0, 0), V3(0, 0, 1)
	hungSign(S, 0, parent, -34, 40, false, "Ground floor", {
		{ text = "Compute Operations", dir = -X },
		{ text = "Project Room", dir = -Z },
		{ text = "IT desk · Wellness pavilion", dir = Z },
		{ text = "Lifts · Stairs · Garage B1", dir = X },
	}, ceil)
	hungSign(S, 0, parent, -46, 12, true, "Ground floor", {
		{ text = "Visitor Lounge · Reception", dir = -Z },
		{ text = "Compute · Wellness pavilion", dir = Z },
		{ text = "Lifts · Café via atrium", dir = V3(0.6, 0, 0.8) },
	}, ceil)
	hungSign(S, 0, parent, 46, 52, true, "Ground floor", {
		{ text = "Wellness pavilion", dir = Z },
		{ text = "Lifts · Mailroom · Café", dir = -Z },
	}, ceil)
end

local function buildCirculation(S: State, level: number)
	local rects = Layout.circulation(S.tier, level)
	if #rects == 0 then
		return
	end
	local parent = S.circ[level] or levelModel(S.folders.Circulation, level)
	S.circ[level] = parent
	local cf = S.cf
	local y = Plan.levelY(level)
	local founder = Plan.founderLevel(S.tier)
	for i, r in rects do
		local zone = zoneOf(S, level, r)
		-- the lift portal, landing door track and the core's brass floor marker stay on the bare slab
		local floorRects = { r }
		for _, hole in LIFT_FLOOR_HOLES do
			local nextRects: { Rect } = {}
			for _, fr in floorRects do
				for _, piece in subtractRect(fr, hole) do
					table.insert(nextRects, piece)
				end
			end
			floorRects = nextRects
		end
		for _, fr in floorRects do
			Kit.floor(parent, cf, fr, y, ZONE_FLOOR[zone] or "carpet", { name = "CorridorFloor" })
		end
		local key = string.format("C%d_%d", level, i)
		local ceilRects = { r }
		if level == 1 then
			-- the bridge over the reception hall stays open to the double-height volume
			ceilRects = subtractRect(r, { x1 = Plan.LOBBY_VOID.x1, x2 = Plan.LOBBY_VOID.x2, z1 = Plan.LOBBY_VOID.z2, z2 = Plan.ATRIUM.z1 })
		end
		local first = true
		for _, cr in ceilRects do
			local style = if zone == "front" then "acoustic" else "plaster"
			local _, strips = Kit.ceiling(parent, cf, cr, y, style, ZONE_MOOD[zone], { maxLights = 0, name = "CorridorCeiling" })
			if first then
				lightStrips(S, key, strips, ZONE_MOOD[zone] or "neutral")
				first = false
			end
		end
		if zone == "wing" and level >= 1 then
			corridorEnds(S, level, parent, r)
		end
	end
	liftLobby(S, level, parent)
	if level >= 2 and level < founder then
		frontLounge(S, level, parent)
	elseif level == founder then
		founderBand(S, level, parent)
	end
	-- one Corridor node per rectangle, placed after the furniture so it stands on free floor
	for i, r in rects do
		local nx, nz = clearPoint(S, level, r)
		Kit.node(S.folders.Navigation, cf, string.format("Corridor_L%d_%d", level, i), nx, y + FIN, nz, "Corridor", level)
	end
	if level == 0 then
		groundSigns(S, parent)
	else
		local title = Plan.levelLabel(S.tier, level) .. " · " .. Plan.levelName(S.tier, level)
		if #title > 34 then
			title = "Level " .. Plan.levelLabel(S.tier, level)
		end
		for _, sx in { -46, 46 } do
			if inCirculation(S, level, sx, 40) then
				hungSign(S, level, parent, sx, 40, true, title, {
					{ text = "Lifts · Stairs · Restrooms", dir = V3(-sx, 0, 0) },
					{ text = if level == founder then "Reception · Terrace" else "Front lounge", dir = V3(0, 0, -1) },
				}, Plan.CEILING)
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Entry point
---------------------------------------------------------------------------------------------
local function step(label: string, fn: () -> ())
	local ok, err = pcall(fn :: () -> any)
	if not ok then
		warn(string.format("[Interior] %s failed: %s", label, tostring(err)))
	end
end

function InteriorDesign.build(ctx: any)
	local S: State = {
		cf = ctx.cf,
		tier = ctx.tier,
		owner = ctx.owner,
		accent = ctx.accent,
		folders = ctx.folders,
		rooms = ctx.rooms,
		circ = {},
		occupied = {},
		lights = {},
		roomById = {},
		keepOut = {},
	}
	local tier = S.tier
	local partsBefore, lightsBefore = Kit.stats.parts, Kit.stats.lights
	buildRoomModels(S)
	S.lights = planLights(S)
	for _, level in Plan.levels(tier) do
		step("walls L" .. level, function()
			buildWalls(S, level)
		end)
	end
	for _, r in Plan.rooms(tier) do
		step("room " .. r.id, function()
			finishRoom(S, r)
			roomCamera(S, r)
			Kit.accessVolume(S.rooms[r.id], S.cf, r)
		end)
	end
	for _, d in Layout.doors(tier) do
		step("door fittings " .. d.id, function()
			doorFittings(S, d)
		end)
	end
	for _, level in Plan.levels(tier) do
		step("circulation L" .. level, function()
			buildCirculation(S, level)
		end)
	end
	-- art last: it only takes wall faces nothing else claimed
	for level = 0, Plan.founderLevel(tier) do
		local parent = S.circ[level]
		if parent then
			step("art L" .. level, function()
				corridorArt(S, level, parent, 2)
			end)
		end
	end
	ctx.office:SetAttribute("InteriorParts", Kit.stats.parts - partsBefore)
	ctx.office:SetAttribute("InteriorLights", Kit.stats.lights - lightsBefore)
end

return InteriorDesign
