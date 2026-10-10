--!strict
-- Exterior generator: the structure (slabs, atrium edges, columns, skylight), the facade envelope with
-- its exterior doors, the entrance portal and canopy, the garage shell and ramp, the foundations and the
-- landscaped site (arrival plaza, campus arcade, rear garden, service yard). Concept: a readable stone
-- plinth, a main body of stone bands and fins with oak sun screens, a glazed lantern over the double-height
-- reception hall and a set-back glass founder storey under a thin floating roof.
-- Everything is building-local (`ctx.cf * CFrame.new(...)`), so it works on every plot orientation.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Plan = require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Layout = require(ReplicatedStorage.Shared.BuildingLayout)
local A = require(ReplicatedStorage.Shared.Config.ArchPalette)
local CampusConfig = require(ReplicatedStorage.Shared.Config.CampusConfig)
local Kit = require(script.Parent.ArchKit)
local HotelKit = require(script.Parent.RoomKitsHotel) -- built lettering of the guest-house signs

type Opts = Kit.Opts
type Rect = { x1: number, x2: number, z1: number, z2: number }
-- A facade line: axis "x" runs along X at z = c, axis "z" runs along Z at x = c. `out` is the outward
-- normal sign; facade coordinates are (a along the line, y, d = distance outward from the line).
-- Holes are door openings in (a, y) space (stored as Rect x = a, z = y).
type Face = { id: string, axis: string, c: number, out: number, model: Model, holes: { Rect } }
type Seg = { a1: number, a2: number, t: string }
type Vert = { f: Face, name: string, a: number, w: number, d1: number, d2: number, color: Color3, mat: Enum.Material, opts: Opts?, spans: { { number } } }
type StoreyOpts = {
	tier: number,
	level: number,
	grid: number, -- mullion grid offset (positions offset + k * pitch)
	pitch: number?,
	skip: { number }?, -- positions hidden by pilasters / fins
	skipW: number?,
	mullionW: number?,
	transom: number?, -- transom height (y) over glass segments
	vy1: number?, -- vertical span used for mullions (lets them merge through bands)
	vy2: number?,
	louvres: boolean?, -- horizontal oak louvres over glass segments
}

local Exterior = {}

local C = A.color
local M = A.material
local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local PI = math.pi

local DETAIL: Opts = { detail = true }
local GLASS: Opts = { transparency = A.glassTransparency, castShadow = false }
local RAIL_GLASS: Opts = { transparency = A.railTransparency, castShadow = false }
local WATER: Opts = { transparency = 0.3, castShadow = false, canCollide = false, canQuery = false, canTouch = false }

-- Room kinds that get a solid stone panel ("solid") or a high strip window ("slot") instead of full glazing.
local TREAT: { [string]: string } = {
	sauna = "solid", vault = "solid", secret_lab = "solid", archive = "solid", ups = "solid", plant = "solid", machine = "solid",
	founder_bath = "slot", restrooms = "slot", showers = "slot", wc = "slot", kitchen_boh = "slot", delivery = "slot",
	compute = "slot", security = "slot", prototype = "slot",
	hotel_pantry = "slot", hotel_service = "slot",
}

-- Building CFrame of the build in progress (builds never yield, so module state is safe).
local B: CFrame = CFrame.identity
local verts: { Vert } = {}
local vindex: { [string]: Vert } = {}

---------------------------------------------------------------------------------------------
-- Geometry helpers
---------------------------------------------------------------------------------------------
-- Axis-aligned box from building-local extents.
local function box(parent: Instance, name: string, x1: number, x2: number, y1: number, y2: number, z1: number, z2: number, color: Color3, mat: Enum.Material, opts: Opts?): Part?
	if x2 - x1 < 0.01 or y2 - y1 < 0.01 or z2 - z1 < 0.01 then
		return nil
	end
	return Kit.part(parent, B, name, V3(x2 - x1, y2 - y1, z2 - z1), CF((x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2), color, mat, opts)
end

local function uniq(t: { number }): { number }
	table.sort(t)
	local out: { number } = {}
	for _, v in t do
		if #out == 0 or v - out[#out] > 1e-4 then
			table.insert(out, v)
		end
	end
	return out
end

-- Rectangle minus holes, decomposed into few rectangles (grid cells merged greedily).
local function subtract(r: Rect, holes: { Rect }): { Rect }
	local xs, zs = { r.x1, r.x2 }, { r.z1, r.z2 }
	local hs: { Rect } = {}
	for _, h in holes do
		local x1, x2 = math.max(h.x1, r.x1), math.min(h.x2, r.x2)
		local z1, z2 = math.max(h.z1, r.z1), math.min(h.z2, r.z2)
		if x2 - x1 > 1e-3 and z2 - z1 > 1e-3 then
			table.insert(hs, { x1 = x1, x2 = x2, z1 = z1, z2 = z2 })
			table.insert(xs, x1)
			table.insert(xs, x2)
			table.insert(zs, z1)
			table.insert(zs, z2)
		end
	end
	if #hs == 0 then
		return { r }
	end
	xs, zs = uniq(xs), uniq(zs)
	local nx, nz = #xs - 1, #zs - 1
	local free: { { boolean } } = {}
	for i = 1, nx do
		free[i] = {}
		for j = 1, nz do
			local cx, cz = (xs[i] + xs[i + 1]) / 2, (zs[j] + zs[j + 1]) / 2
			local f = true
			for _, h in hs do
				if cx > h.x1 and cx < h.x2 and cz > h.z1 and cz < h.z2 then
					f = false
					break
				end
			end
			free[i][j] = f
		end
	end
	local out: { Rect } = {}
	for j = 1, nz do
		for i = 1, nx do
			if free[i][j] then
				local i2 = i
				while i2 + 1 <= nx and free[i2 + 1][j] do
					i2 += 1
				end
				local j2 = j
				local grow = true
				while grow and j2 + 1 <= nz do
					for k = i, i2 do
						if not free[k][j2 + 1] then
							grow = false
							break
						end
					end
					if grow then
						j2 += 1
					end
				end
				for k = i, i2 do
					for l = j, j2 do
						free[k][l] = false
					end
				end
				table.insert(out, { x1 = xs[i], x2 = xs[i2 + 1], z1 = zs[j], z2 = zs[j2 + 1] })
			end
		end
	end
	return out
end

-- (min, max) of s*u1 and s*u2: mirrors a span given as distances from the centre line.
local function sp(s: number, u1: number, u2: number): (number, number)
	local p, q = s * u1, s * u2
	if p < q then
		return p, q
	end
	return q, p
end

---------------------------------------------------------------------------------------------
-- Facade helpers
---------------------------------------------------------------------------------------------
local function newFace(id: string, model: Model, axis: string, c: number, out: number): Face
	return { id = id, axis = axis, c = c, out = out, model = model, holes = {} }
end

local function fpart(f: Face, name: string, a1: number, a2: number, y1: number, y2: number, d1: number, d2: number, color: Color3, mat: Enum.Material, opts: Opts?): Part?
	local n1, n2 = f.c + f.out * d1, f.c + f.out * d2
	if n1 > n2 then
		n1, n2 = n2, n1
	end
	if f.axis == "x" then
		return box(f.model, name, a1, a2, y1, y2, n1, n2, color, mat, opts)
	end
	return box(f.model, name, n1, n2, y1, y2, a1, a2, color, mat, opts)
end

-- Facade element that keeps every door opening of its line clear.
local function fsolid(f: Face, name: string, a1: number, a2: number, y1: number, y2: number, d1: number, d2: number, color: Color3, mat: Enum.Material, opts: Opts?)
	if a2 - a1 < 0.01 or y2 - y1 < 0.01 then
		return
	end
	for _, r in subtract({ x1 = a1, x2 = a2, z1 = y1, z2 = y2 }, f.holes) do
		if r.x2 - r.x1 >= 0.1 and r.z2 - r.z1 >= 0.1 then -- no slivers around door openings
			fpart(f, name, r.x1, r.x2, r.z1, r.z2, d1, d2, color, mat, opts)
		end
	end
end

-- Vertical element (fin, mullion, pier). Spans registered per storey are merged into one part per line.
local function vert(f: Face, name: string, a: number, w: number, d1: number, d2: number, y1: number, y2: number, color: Color3, mat: Enum.Material, opts: Opts?)
	if y2 - y1 < 0.05 then
		return
	end
	local key = string.format("%s|%s|%.3f|%.3f|%.3f|%.3f", f.id, name, a, w, d1, d2)
	local v: Vert? = vindex[key]
	if not v then
		local nv: Vert = { f = f, name = name, a = a, w = w, d1 = d1, d2 = d2, color = color, mat = mat, opts = opts, spans = {} }
		vindex[key] = nv
		table.insert(verts, nv)
		v = nv
	end
	table.insert((v :: Vert).spans, { y1, y2 })
end

local function flushVerts()
	for _, v in verts do
		table.sort(v.spans, function(p, q)
			return p[1] < q[1]
		end)
		local lo, hi = v.spans[1][1], v.spans[1][2]
		for i = 2, #v.spans do
			local s = v.spans[i]
			if s[1] <= hi + 0.05 then
				hi = math.max(hi, s[2])
			else
				fsolid(v.f, v.name, v.a - v.w / 2, v.a + v.w / 2, lo, hi, v.d1, v.d2, v.color, v.mat, v.opts)
				lo, hi = s[1], s[2]
			end
		end
		fsolid(v.f, v.name, v.a - v.w / 2, v.a + v.w / 2, lo, hi, v.d1, v.d2, v.color, v.mat, v.opts)
	end
	table.clear(verts)
	table.clear(vindex)
end

local function grid(a1: number, a2: number, offset: number, pitch: number): { number }
	local out: { number } = {}
	for k = math.ceil((a1 + 0.3 - offset) / pitch), math.floor((a2 - 0.3 - offset) / pitch) do
		table.insert(out, offset + k * pitch)
	end
	return out
end

local function hidden(a: number, list: { number }?, w: number?): boolean
	if not list then
		return false
	end
	local half = (w or 1) / 2 + 0.25
	for _, p in list do
		if math.abs(a - p) < half then
			return true
		end
	end
	return false
end

-- Facade treatment segments along [a1, a2] from the rooms behind the line (privacy reads on the outside).
local function segments(tier: number, level: number, f: Face, a1: number, a2: number): { Seg }
	local marks: { Seg } = {}
	for _, r in Plan.roomsOnLevel(tier, level) do
		local t = TREAT[r.kind]
		if t then
			local edge, r1, r2
			if f.axis == "x" then
				edge, r1, r2 = if f.out > 0 then r.z2 else r.z1, r.x1, r.x2
			else
				edge, r1, r2 = if f.out > 0 then r.x2 else r.x1, r.z1, r.z2
			end
			if math.abs(edge - f.c) < 0.01 then
				local s1, s2 = math.max(r1, a1), math.min(r2, a2)
				if s2 - s1 > 0.01 then
					table.insert(marks, { a1 = s1, a2 = s2, t = t })
				end
			end
		end
	end
	table.sort(marks, function(p, q)
		return p.a1 < q.a1
	end)
	local out: { Seg } = {}
	local cur = a1
	for _, m in marks do
		if m.a1 > cur + 0.01 then
			table.insert(out, { a1 = cur, a2 = m.a1, t = "glass" })
		end
		local s1 = math.max(m.a1, cur)
		if m.a2 > s1 + 0.01 then
			table.insert(out, { a1 = s1, a2 = m.a2, t = m.t })
			cur = m.a2
		end
	end
	if a2 > cur + 0.01 then
		table.insert(out, { a1 = cur, a2 = a2, t = "glass" })
	end
	return out
end

-- One storey of an envelope line between yb and yt: glass with mullions, or stone panels / strip windows
-- where the rooms behind need privacy. One glass layer on the line (d 0..0.2), mullions every `pitch`.
local function storey(f: Face, a1: number, a2: number, yb: number, yt: number, o: StoreyOpts)
	local pitch = o.pitch or 4
	local mw = o.mullionW or 0.15
	local vy1, vy2 = o.vy1 or yb, o.vy2 or yt
	local segs = segments(o.tier, o.level, f, a1, a2)
	for _, s in segs do
		local s1, s2 = s.a1, s.a2
		if s.t == "glass" then
			fsolid(f, "Glass", s1, s2, yb, yt, 0, 0.2, C.glass, M.glass, GLASS)
			local tr = o.transom
			if tr then
				fsolid(f, "Transom", s1, s2, tr, tr + 0.3, 0, 0.45, C.metal, M.metal, DETAIL)
			end
			if o.louvres then
				for k = 0, 2 do
					local y = yt - 3.2 + k * 1.0
					fsolid(f, "Louvre", s1, s2, y, y + 0.3, 1.85, 2.75, C.oak, M.wood, DETAIL)
				end
			end
			for _, a in grid(s1, s2, o.grid, pitch) do
				if not hidden(a, o.skip, o.skipW) then
					vert(f, "Mullion", a, mw, 0, 0.45, vy1, vy2, C.metal, M.metal, DETAIL)
				end
			end
		elseif s.t == "slot" then
			local y1, y2 = yb + (yt - yb) * 0.62, yb + (yt - yb) * 0.85
			fsolid(f, "Panel", s1, s2, yb, y1, 0, 0.9, C.stone, M.stone)
			fsolid(f, "Glass", s1, s2, y1, y2, 0, 0.2, C.glass, M.glass, GLASS)
			fsolid(f, "Panel", s1, s2, y2, yt, 0, 0.9, C.stone, M.stone)
			if o.louvres then
				for k = 0, 1 do
					local y = y1 + (y2 - y1) * (0.3 + 0.4 * k)
					fsolid(f, "Louvre", s1, s2, y - 0.15, y + 0.15, 0.85, 1.65, C.oak, M.wood, DETAIL)
				end
			end
			for _, a in grid(s1, s2, o.grid, pitch * 2) do
				if not hidden(a, o.skip, o.skipW) then
					vert(f, "Mullion", a, mw, 0.1, 0.6, y1, y2, C.metal, M.metal, DETAIL)
				end
			end
		else
			fsolid(f, "Panel", s1, s2, yb, yt, 0, 0.9, C.stone, M.stone)
		end
	end
end

-- Glass balustrade on top of a parapet/upstand (top = y + 2.6).
local function glassRail(f: Face, a1: number, a2: number, y: number, d: number)
	fsolid(f, "RailGlass", a1, a2, y, y + 2.4, d - 0.08, d + 0.08, C.glass, M.glass, RAIL_GLASS)
	fsolid(f, "RailCap", a1, a2, y + 2.4, y + 2.6, d - 0.2, d + 0.2, C.metal, M.metal)
end

-- Vertical oak sun-screen lamellas across a bay between two fins (b1 < b2 are the fin centres).
local function lamellas(f: Face, b1: number, b2: number, y1: number, y2: number)
	local c1, c2 = b1 + 0.8, b2 - 0.8
	local n = math.max(1, math.floor((c2 - c1) / 1.2 + 0.5))
	for i = 0, n do
		vert(f, "Lamella", c1 + i * (c2 - c1) / n, 0.35, 1.95, 2.6, y1, y2, C.oak, M.wood, DETAIL)
	end
end

-- Two-storey dark metal box frame in front of a bay.
local function boxFrame(f: Face, b1: number, b2: number, y1: number, y2: number)
	fsolid(f, "BoxFrame", b1 - 0.6, b1 + 0.2, y1, y2, 2.7, 3.6, C.metal, M.metal)
	fsolid(f, "BoxFrame", b2 - 0.2, b2 + 0.6, y1, y2, 2.7, 3.6, C.metal, M.metal)
	fsolid(f, "BoxFrame", b1 + 0.2, b2 - 0.2, y1, y1 + 0.8, 2.7, 3.6, C.metal, M.metal)
	fsolid(f, "BoxFrame", b1 + 0.2, b2 - 0.2, y2 - 0.8, y2, 2.7, 3.6, C.metal, M.metal)
end

-- Glass balustrade with base shoe and oak handrail along a slab edge (top 3.85 above the slab).
local function slabRail(parent: Instance, axis: string, c: number, a1: number, a2: number, y: number)
	if a2 - a1 < 0.2 then
		return
	end
	local function b(name: string, n1: number, n2: number, y1: number, y2: number, color: Color3, mat: Enum.Material, opts: Opts?)
		if axis == "x" then
			box(parent, name, a1, a2, y1, y2, c + n1, c + n2, color, mat, opts)
		else
			box(parent, name, c + n1, c + n2, y1, y2, a1, a2, color, mat, opts)
		end
	end
	b("RailShoe", -0.15, 0.15, y, y + 0.25, C.metal, M.metal)
	b("RailGlass", -0.06, 0.06, y + 0.25, y + 3.55, C.glass, M.glass, RAIL_GLASS)
	b("Handrail", -0.2, 0.2, y + 3.55, y + 3.85, C.oak, M.wood)
end

-- Metal guard rail (posts every ~8, mid and top rail) from y to y + 2.6 along a line.
local function metalRail(parent: Instance, axis: string, c: number, a1: number, a2: number, y: number)
	local function b(name: string, p1: number, p2: number, y1: number, y2: number, w: number, opts: Opts?)
		if axis == "x" then
			box(parent, name, p1, p2, y1, y2, c - w / 2, c + w / 2, C.metal, M.metal, opts)
		else
			box(parent, name, c - w / 2, c + w / 2, y1, y2, p1, p2, C.metal, M.metal, opts)
		end
	end
	b("GuardRail", a1, a2, y + 2.4, y + 2.6, 0.25)
	b("GuardRail", a1, a2, y + 1.2, y + 1.35, 0.12, DETAIL)
	local n = math.max(1, math.ceil((a2 - a1) / 8))
	for i = 0, n do
		local p = a1 + 0.15 + i * (a2 - a1 - 0.3) / n
		b("GuardPost", p - 0.15, p + 0.15, y, y + 2.4, 0.25)
	end
end

---------------------------------------------------------------------------------------------
-- Landscape helpers
---------------------------------------------------------------------------------------------
local function tree(parent: Instance, x: number, z: number, seed: number, base: number?)
	local y = base or 0.1
	local h = Kit.range(seed, 1, 7, 10)
	local d = Kit.range(seed, 2, 6, 8)
	Kit.cylinder(parent, B, "TreeTrunk", "y", h, 0.9, CF(x, y + h / 2, z), C.oakDark, M.wood)
	Kit.ball(parent, B, "TreeCanopy", d, CF(x, y + h + d * 0.15, z), if Kit.rand(seed, 3) < 0.5 then C.foliage else C.foliageLight, M.leafy, DETAIL)
	local yaw = Kit.range(seed, 4, 0, 2 * PI)
	Kit.ball(parent, B, "TreeCanopy", d * 0.72, CF(x, y + h - d * 0.1, z) * ANG(0, yaw, 0) * CF(d * 0.32, 0, 0), C.foliageLight, M.leafy, DETAIL)
	Kit.ball(parent, B, "TreeCanopy", d * 0.62, CF(x, y + h + d * 0.2, z) * ANG(0, yaw + 2.4, 0) * CF(d * 0.3, 0, 0), C.foliage, M.leafy, DETAIL)
end

-- Raised stone planting island with a lawn top, two shrubs and one tree.
local function island(parent: Instance, x1: number, x2: number, z1: number, z2: number, seed: number)
	box(parent, "PlanterIsland", x1, x2, 0, 1.3, z1, z2, C.stoneDeep, M.stone)
	box(parent, "PlanterLawn", x1 + 0.5, x2 - 0.5, 1.3, 1.42, z1 + 0.5, z2 - 0.5, C.grass, M.grass)
	local cx, cz = (x1 + x2) / 2, (z1 + z2) / 2
	local alongX = x2 - x1 >= z2 - z1
	for _, k in { -1, 1 } do
		local off = (if alongX then x2 - x1 else z2 - z1) * 0.32 * k
		local sx, sz = if alongX then cx + off else cx, if alongX then cz else cz + off
		Kit.ball(parent, B, "Shrub", Kit.range(seed, 10 + k, 2.0, 2.8), CF(sx, 2.0, sz), if k > 0 then C.foliage else C.foliageLight, M.leafy, DETAIL)
	end
	tree(parent, cx, cz, seed, 1.42)
end

local function bollard(parent: Instance, x: number, z: number, lit: boolean)
	Kit.cylinder(parent, B, "Bollard", "y", 3, 0.6, CF(x, 0.12 + 1.5, z), C.metal, M.metal)
	local glow = box(parent, "BollardLight", x - 0.22, x + 0.22, 2.4, 2.8, z - 0.32, z + 0.32, C.lightWarm, M.neon, DETAIL)
	if lit and glow then
		Kit.light(glow, "point", C.lightWarm, 12, 0.6)
	end
end

local function publicPrompt(part: Instance, objectText: string, app: string?, action: string?, value: any?): ProximityPrompt
	-- same contract as the original store terminals: public, no line of sight, 12 studs
	local q = Instance.new("ProximityPrompt")
	q.ActionText = if action then "Use" else "Open"
	q.ObjectText = objectText
	q.MaxActivationDistance = 12
	q.RequiresLineOfSight = false
	q.HoldDuration = 0
	q:SetAttribute("Public", true)
	if app then
		q:SetAttribute("App", app)
	end
	if action then
		q:SetAttribute("CampusAction", action)
		q:SetAttribute("Value", value)
	end
	q.Parent = part
	return q
end

---------------------------------------------------------------------------------------------
-- 1. Structure: slabs, atrium edges, columns, skylight
---------------------------------------------------------------------------------------------
local function structure(ctx: any)
	local tier: number = ctx.tier
	local folder: Instance = ctx.folders.Structure
	local roof = Plan.roofLevel(tier)
	local founder = Plan.founderLevel(tier)
	local RY = Plan.levelY(roof)

	local slabs = Kit.model(folder, "Slabs")
	for level = -1, roof do
		local y = Plan.levelY(level)
		local rects, holes = Layout.slabs(tier, level)
		local hs: { Rect } = {}
		for _, h in holes do
			table.insert(hs, { x1 = h.x1, x2 = h.x2, z1 = h.z1, z2 = h.z2 })
		end
		for _, r in rects do
			for _, piece in subtract({ x1 = r.x1, x2 = r.x2, z1 = r.z1, z2 = r.z2 }, hs) do
				box(slabs, "Slab", piece.x1, piece.x2, y - 1, y, piece.z1, piece.z2, C.concrete, M.concrete)
			end
		end
	end

	-- Atrium void: oak slab-edge fascias and glass balustrades on every storey up to the founder level.
	local at = Plan.ATRIUM
	local edges = Kit.model(folder, "AtriumEdges")
	local cl = 1.05 -- clearance from the corner columns
	for level = 1, founder do
		local y = Plan.levelY(level)
		box(edges, "SlabFascia", at.x1, at.x1 + 0.15, y - 1.3, y, at.z1 + 1, at.z2 - 1, C.oak, M.wood)
		box(edges, "SlabFascia", at.x2 - 0.15, at.x2, y - 1.3, y, at.z1 + 1, at.z2 - 1, C.oak, M.wood)
		box(edges, "SlabFascia", at.x1 + 1, at.x2 - 1, y - 1.3, y, at.z1, at.z1 + 0.15, C.oak, M.wood)
		box(edges, "SlabFascia", at.x1 + 1, at.x2 - 1, y - 1.3, y, at.z2 - 0.15, at.z2, C.oak, M.wood)
		slabRail(edges, "z", at.x1 - 0.3, at.z1 + cl, at.z2 - cl, y)
		slabRail(edges, "z", at.x2 + 0.3, at.z1 + cl, at.z2 - cl, y)
		slabRail(edges, "x", at.z1 - 0.3, at.x1 + cl, at.x2 - cl, y)
		slabRail(edges, "x", at.z2 + 0.3, at.x1 + cl, at.x2 - cl, y)
	end
	-- Level 1: the reception-hall void; its north edge makes the gallery bridge railed on both sides.
	local v = Plan.LOBBY_VOID
	local y1 = Plan.levelY(1)
	box(edges, "SlabFascia", v.x1 + 0.5, v.x2 - 0.5, y1 - 1.3, y1, v.z2 - 0.15, v.z2, C.oak, M.wood)
	slabRail(edges, "x", v.z2 + 0.3, v.x1 + 0.5, v.x2 - 0.5, y1)

	-- Round stone columns at the four void corners, ground floor to the roof slab.
	local cols = Kit.model(folder, "AtriumColumns")
	for _, p in { { at.x1, at.z1 }, { at.x2, at.z1 }, { at.x1, at.z2 }, { at.x2, at.z2 } } do
		Kit.cylinder(cols, B, "AtriumColumn", "y", RY - 1, 2.0, CF(p[1], (RY - 1) / 2, p[2]), C.stone, M.stone)
	end

	-- Roof skylight over the atrium: stone curb, glass, dark metal grid, guard railing around it.
	local sky = Kit.model(folder, "Skylight")
	local e = 0.6
	box(sky, "SkylightCurb", at.x1 - e, at.x2 + e, RY, RY + 1, at.z1 - e, at.z1, C.stoneDeep, M.stone)
	box(sky, "SkylightCurb", at.x1 - e, at.x2 + e, RY, RY + 1, at.z2, at.z2 + e, C.stoneDeep, M.stone)
	box(sky, "SkylightCurb", at.x1 - e, at.x1, RY, RY + 1, at.z1, at.z2, C.stoneDeep, M.stone)
	box(sky, "SkylightCurb", at.x2, at.x2 + e, RY, RY + 1, at.z1, at.z2, C.stoneDeep, M.stone)
	box(sky, "SkylightGlass", at.x1 - e, at.x2 + e, RY + 1, RY + 1.15, at.z1 - e, at.z2 + e, C.glass, M.glass, GLASS)
	for x = at.x1 + 4, at.x2 - 4, 4 do
		box(sky, "SkylightBar", x - 0.12, x + 0.12, RY + 1.15, RY + 1.4, at.z1 - e, at.z2 + e, C.metal, M.metal, DETAIL)
	end
	for z = at.z1 + 4, at.z2 - 4, 4 do
		box(sky, "SkylightBar", at.x1 - e, at.x2 + e, RY + 1.15, RY + 1.4, z - 0.12, z + 0.12, C.metal, M.metal, DETAIL)
	end
	local g = 1.0 -- just outside the curb: keeps ~5 studs clear in front of the roof lobby doors (z 42)
	slabRail(sky, "z", at.x1 - g, at.z1 - g, at.z2 + g, RY)
	slabRail(sky, "z", at.x2 + g, at.z1 - g, at.z2 + g, RY)
	slabRail(sky, "x", at.z1 - g, at.x1 - g + 0.2, at.x2 + g - 0.2, RY)
	slabRail(sky, "x", at.z2 + g, at.x1 - g + 0.2, at.x2 + g - 0.2, RY)
end

---------------------------------------------------------------------------------------------
-- 4. Facades + exterior doors
---------------------------------------------------------------------------------------------
local function facades(ctx: any)
	local tier: number = ctx.tier
	local folder: Instance = ctx.folders.Facade
	local F = Plan.founderLevel(tier)
	local R = Plan.roofLevel(tier)
	local FY, RY = Plan.levelY(F), Plan.levelY(R)

	local function model(name: string): Model
		return Kit.model(folder, name)
	end
	local front = newFace("front", model("Facade_Front"), "x", Plan.MAIN.z1, -1)
	local west = newFace("west", model("Facade_West"), "z", Plan.MAIN.x1, -1)
	local east = newFace("east", model("Facade_East"), "z", Plan.MAIN.x2, 1)
	local back = newFace("back", model("Facade_Back"), "x", Plan.MAIN.z2, 1)
	local founder = newFace("founder", model("Facade_Founder"), "x", Plan.FOUNDER_FRONT_Z, -1)
	local pwest = newFace("pwest", model("Facade_PavilionWest"), "z", Plan.PAVILION.x1, -1)
	local peast = newFace("peast", model("Facade_PavilionEast"), "z", Plan.PAVILION.x2, 1)
	local pback = newFace("pback", model("Facade_PavilionBack"), "x", Plan.PAVILION.z2, 1)
	local faces = { front, west, east, back, founder, pwest, peast, pback }

	-- Door openings first, so every element of the line keeps them clear.
	local doors = {}
	for _, d in Layout.doors(tier) do
		if d.builder == "exterior" and d.id ~= "G_ENTRANCE" and not d.annex then
			local da = if d.axis == "x" then d.x else d.z
			local dc = if d.axis == "x" then d.z else d.x
			local y = Plan.levelY(d.level)
			local host: Face? = nil
			for _, f in faces do
				if f.axis == d.axis and math.abs(f.c - dc) < 0.01 then
					table.insert(f.holes, { x1 = da - d.w / 2 - 0.6, x2 = da + d.w / 2 + 0.6, z1 = y, z2 = y + d.h + 0.6 })
					host = host or f
				end
			end
			if host then
				table.insert(doors, { def = d, face = host, a = da, y = y })
			else
				warn(`[Exterior] door {d.id} is not on a facade line`)
			end
		end
	end

	local frontGrid, sideGrid = 2, 0 -- mullion grids aligned with the interior wall lines
	---------------------------------------------------------------- front (z = -48)
	local bays = { { 66, 76 }, { 58, 66 }, { 50, 58 }, { 42, 50 }, { 34, 42 }, { 26, 34 } } -- outer -> inner
	for _, s in { -1, 1 } do
		local p1, p2 = sp(s, 76, 84.5)
		fsolid(front, "CornerPier", p1, p2, 0, FY + 1.2, 0, 2.5, C.stone, M.stone)
		p1, p2 = sp(s, 22, 23.5)
		fsolid(front, "LanternPier", p1, p2, 0, FY + 1.2, 0, 2.7, C.stone, M.stone)
		local g1, g2 = sp(s, 23.5, 76)
		-- plinth: base course, glazing with transom, pilasters on the 16-stud rhythm, cornice
		local pil = { s * 34, s * 50, s * 66 }
		fsolid(front, "BaseCourse", g1, g2, 0, 0.9, 0, 1.0, C.stoneDeep, M.stone)
		storey(front, g1, g2, 0.9, 15, { tier = tier, level = 0, grid = frontGrid, skip = pil, skipW = 2.5, transom = 10.8, vy1 = 0.9, vy2 = 15 })
		for _, a in pil do
			fsolid(front, "Pilaster", a - 1.25, a + 1.25, 0, 15, 0.2, 2.2, C.stone, M.stone)
		end
		local c1, c2 = sp(s, 23.5, 85)
		fsolid(front, "Cornice", c1, c2, 15, 16.6, 0, 3.0, C.stone, M.stone)
		-- main body: stone bands, fins every 8, recessed glass, oak lamellas, box frames
		local fins: { number } = {}
		for _, u in { 26, 34, 42, 50, 58, 66 } do
			table.insert(fins, s * u)
			vert(front, "Fin", s * u, 1, 0.2, 2.7, 16.6, FY - 2, C.stone, M.stone)
		end
		for L = 1, F - 1 do
			local yb = if L == 1 then 16.6 else 16 * L + 1
			local yt = 16 * (L + 1) - 2
			storey(front, g1, g2, yb, yt, { tier = tier, level = L, grid = frontGrid, skip = fins, skipW = 1, vy1 = if L == 1 then 15 else 16 * L - 2, vy2 = yt })
			if L >= 2 then
				fsolid(front, "Band", g1, g2, 16 * L - 2, 16 * L + 1, 0, 2.0, C.stone, M.stone)
			end
		end
		for p = 0, math.floor((F - 2) / 2) do
			local L1 = 1 + 2 * p
			local L2 = math.min(L1 + 1, F - 1)
			local y1 = if L1 == 1 then 16.6 else 16 * L1 + 1
			local y2 = 16 * (L2 + 1) - 2
			-- checkerboard of screened bays per floor pair; one framed bay per side, staggered up the facade
			local framed = if p % 2 == 0 then 1 else 4
			for k, bay in bays do
				local b1, b2 = sp(s, bay[1], bay[2])
				if k - 1 == framed and L2 > L1 then
					boxFrame(front, b1, b2, if L1 == 1 then 15 else 16 * L1 - 2, 16 * (L2 + 1) + 1)
				elseif (k - 1 + p) % 2 == 0 then
					lamellas(front, b1, b2, y1, y2)
				end
			end
		end
	end
	-- the terrace upstand of the founder storey closes the front as one long stone band
	fsolid(front, "Band", -84.5, 84.5, FY - 2, FY + 1.2, 0, 2.0, C.stone, M.stone)
	glassRail(front, -82.5, 82.5, FY + 1.2, 0.5)

	-- lantern over the double-height reception hall: one tall glass front with dark metal fins
	for _, s in { -1, 1 } do
		local l1, l2 = sp(s, 17, 22)
		fsolid(front, "BaseCourse", l1, l2, 0, 0.9, 0, 1.0, C.stoneDeep, M.stone)
		fsolid(front, "Glass", l1, l2, 0.9, 16.6, 0, 0.2, C.glass, M.glass, GLASS)
		fsolid(front, "Transom", l1, l2, 10.8, 11.1, 0, 0.45, C.metal, M.metal, DETAIL)
		for i = 0, 4 do
			vert(front, "LanternFin", s * (2 + 4 * i), 0.3, 0.2, 1.7, 16.6, FY - 2, C.metal, M.metal)
		end
	end
	fsolid(front, "Glass", -22, 22, 16.6, FY - 2, 0, 0.2, C.glass, M.glass, GLASS)
	fsolid(front, "LanternTransom", -22, 22, 16.4, 16.9, 0, 0.8, C.metal, M.metal)
	for L = 2, F - 1 do
		fsolid(front, "LanternTransom", -22, 22, 16 * L - 0.8, 16 * L - 0.2, 0.2, 0.6, C.metal, M.metal)
	end

	---------------------------------------------------------------- sides (x = -82 / 82)
	for _, f in { west, east } do
		local isWest = f == west
		fsolid(f, "CornerPier", -48, -42, 0, FY + 1.2, 0, 2.5, C.stone, M.stone)
		fsolid(f, "CornerPier", 74, 80, 0, RY + 1.2, 0, 2.5, C.stone, M.stone)
		local pil = { -24, -8, 8, 24, 40, 56 }
		fsolid(f, "BaseCourse", -42, 74, 0, 0.9, 0, 1.0, C.stoneDeep, M.stone)
		storey(f, -42, 74, 0.9, 15, { tier = tier, level = 0, grid = sideGrid, skip = pil, skipW = 2.5, transom = 10.8, vy1 = 0.9, vy2 = 15 })
		for _, a in pil do
			fsolid(f, "Pilaster", a - 1.25, a + 1.25, 0, 15, 0.2, 2.2, C.stone, M.stone)
		end
		-- one cornice from the front corner to the pavilion's back corner ties both volumes together
		fsolid(f, "Cornice", -51, 163, 15, 16.6, 0, 3.0, C.stone, M.stone)
		local fins: { number } = {}
		for a = -32, 64, 8 do
			table.insert(fins, a)
			vert(f, "Fin", a, 1, 0.2, 2.7, 16.6, FY - 2, C.stone, M.stone)
		end
		for L = 1, F - 1 do
			local yb = if L == 1 then 16.6 else 16 * L + 1
			local yt = 16 * (L + 1) - 2
			storey(f, -42, 74, yb, yt, { tier = tier, level = L, grid = sideGrid, skip = fins, skipW = 1, vy1 = if L == 1 then 15 else 16 * L - 2, vy2 = yt })
			if L >= 2 then
				fsolid(f, "Band", -42, 74, 16 * L - 2, 16 * L + 1, 0, 2.0, C.stone, M.stone)
			end
		end
		-- oak lamellas: a rhythm on the west (afternoon sun), only a few near the front on the east
		local sideBays: { { number } } = { { -42, -32 } }
		for a = -32, 56, 8 do
			table.insert(sideBays, { a, a + 8 })
		end
		table.insert(sideBays, { 64, 74 })
		for p = 0, math.floor((F - 2) / 2) do
			local L1 = 1 + 2 * p
			local L2 = math.min(L1 + 1, F - 1)
			local y1 = if L1 == 1 then 16.6 else 16 * L1 + 1
			local y2 = 16 * (L2 + 1) - 2
			for k, bay in sideBays do
				local on = if isWest then (k - 1 + p) % 3 == 0 else (k - 1 + p) % 5 == 1
				if on then
					lamellas(f, bay[1], bay[2], y1, y2)
				end
			end
		end
		-- founder floor: band (terrace upstand at the side returns), glazed storey, floating roof canopy
		fsolid(f, "Band", -42, -32, FY - 2, FY + 1.2, 0, 2.0, C.stone, M.stone)
		fsolid(f, "Band", -32, 74, FY - 2, FY + 1, 0, 2.0, C.stone, M.stone)
		storey(f, -32, 74, FY + 1, RY - 1, { tier = tier, level = F, grid = sideGrid, mullionW = 0.12 })
		fsolid(f, "CanopyPlate", -32, 74, RY - 0.6, RY, 0, 3, C.metal, M.metal)
		fsolid(f, "CanopySoffit", -32, 74, RY - 1.0, RY - 0.6, 0.2, 3, C.oak, M.wood)
		fsolid(f, "CanopyFascia", -35.3, 74, RY - 1.2, RY + 0.2, 3, 3.3, C.metal, M.metal)
		fsolid(f, "Parapet", -33, 74, RY, RY + 1.2, 0, 1.0, C.stone, M.stone)
		glassRail(f, -48.5, -32, FY + 1.2, 0.5)
		glassRail(f, -32.5, 80.5, RY + 1.2, 0.5)
	end

	---------------------------------------------------------------- founder storey (z = -32)
	fsolid(founder, "Sill", -82, 82, FY, FY + 0.3, 0, 0.45, C.metal, M.metal)
	fsolid(founder, "Glass", -82, 82, FY + 0.3, RY - 1.0, 0, 0.2, C.glass, M.glass, GLASS)
	for _, a in grid(-82, 82, frontGrid, 4) do
		vert(founder, "Mullion", a, 0.12, 0, 0.4, FY + 0.3, RY - 1.0, C.metal, M.metal, DETAIL)
	end
	for _, s in { -1, 1 } do
		local c1, c2 = sp(s, 82, 82.3)
		fpart(founder, "CornerPost", c1, c2, FY, RY - 1.0, 0, 0.3, C.metal, M.metal)
	end
	fsolid(founder, "CanopyPlate", -85, 85, RY - 0.6, RY, 0, 3, C.metal, M.metal)
	fsolid(founder, "CanopySoffit", -85, 85, RY - 1.0, RY - 0.6, 0.2, 3, C.oak, M.wood)
	fsolid(founder, "CanopyFascia", -85.3, 85.3, RY - 1.2, RY + 0.2, 3, 3.3, C.metal, M.metal)
	fsolid(founder, "Parapet", -83, 83, RY, RY + 1.2, 0, 1.0, C.stone, M.stone)
	glassRail(founder, -82.5, 82.5, RY + 1.2, 0.5)
	-- founder-level terrace floor (stone pavers, oak deck in front of the founder office)
	box(founder.model, "TerracePaving", Plan.MAIN.x1, 42, FY, FY + 0.1, Plan.MAIN.z1, Plan.FOUNDER_FRONT_Z, C.stonePave, M.pave)
	box(founder.model, "TerraceDeck", 42, Plan.MAIN.x2, FY, FY + 0.1, Plan.MAIN.z1, Plan.FOUNDER_FRONT_Z, C.oakDark, M.planks)

	---------------------------------------------------------------- back (z = 80, levels >= 2)
	for _, s in { -1, 1 } do
		local p1, p2 = sp(s, 76, 84.5)
		fsolid(back, "CornerPier", p1, p2, 30, RY + 1.2, 0, 2.5, C.stone, M.stone)
	end
	local piers = { { 0, 47 } }
	for _, pc in { { 25.5, 4 }, { 34, 3 }, { 42, 3 }, { 50, 3 }, { 58, 3 }, { 66, 3 }, { 74.25, 3.5 } } do
		table.insert(piers, { pc[1], pc[2] })
		table.insert(piers, { -pc[1], pc[2] })
	end
	for L = 2, F do
		local yb, yt = 16 * L + 1, 16 * (L + 1) - 2
		fsolid(back, "Band", -76, 76, 16 * L - 2, 16 * L + 1, 0, 2.0, C.stone, M.stone)
		fsolid(back, "Glass", -76, 76, yb, yt, 0, 0.2, C.glass, M.glass, GLASS)
		fsolid(back, "Sill", -76, 76, yb, yb + 2, 0.2, 1.4, C.stone, M.stone)
		fsolid(back, "Head", -76, 76, yb + 10, yt, 0.2, 1.4, C.stone, M.stone)
		for _, pc in piers do
			vert(back, if pc[1] == 0 then "BackCore" else "BackPier", pc[1], pc[2], 0.2, 1.4, 16 * L - 2, 16 * (L + 1) - 2, C.stone, M.stone)
		end
	end
	fsolid(back, "Band", -76, 76, RY - 2, RY + 1.2, 0, 2.0, C.stone, M.stone)
	glassRail(back, -82.5, 82.5, RY + 1.2, 0.5)

	---------------------------------------------------------------- pavilion (levels 0-1, roof garden on top)
	for _, f in { pwest, peast } do
		local pil = { 96, 112, 128, 144 }
		fsolid(f, "CornerPier", 154, 160, 0, 33.2, 0, 2.5, C.stone, M.stone)
		fsolid(f, "BaseCourse", 80, 154, 0, 0.9, 0, 1.0, C.stoneDeep, M.stone)
		storey(f, 80, 154, 0.9, 15, { tier = tier, level = 0, grid = sideGrid, skip = pil, skipW = 2.5, transom = 10.8, louvres = true, vy1 = 0.9, vy2 = 15 })
		storey(f, 80, 154, 16.6, 30, { tier = tier, level = 1, grid = sideGrid, skip = pil, skipW = 2.5, louvres = true, vy1 = 15, vy2 = 30 })
		for _, a in pil do
			fsolid(f, "Pier", a - 1.25, a + 1.25, 0, 30, 0.2, 1.9, C.stone, M.stone)
		end
		fsolid(f, "Parapet", 80, 154, 30, 33.2, 0, 2.0, C.stone, M.stone)
		glassRail(f, 80, 160.5, 33.2, 0.5)
		fpart(f, "GreenRoofEdge", 80, 158.8, 32, 32.25, -1.2, 0, C.grass, M.grass, DETAIL)
	end
	do
		local f = pback
		local pil = { -64, -48, -32, -16, 0, 16, 32, 48, 64 }
		for _, s in { -1, 1 } do
			local p1, p2 = sp(s, 76, 84.5)
			fsolid(f, "CornerPier", p1, p2, 0, 33.2, 0, 2.5, C.stone, M.stone)
		end
		fsolid(f, "BaseCourse", -76, 76, 0, 0.9, 0, 1.0, C.stoneDeep, M.stone)
		storey(f, -76, 76, 0.9, 15, { tier = tier, level = 0, grid = 0, skip = pil, skipW = 2.5, transom = 10.8, louvres = true, vy1 = 0.9, vy2 = 15 })
		storey(f, -76, 76, 16.6, 30, { tier = tier, level = 1, grid = 0, skip = pil, skipW = 2.5, louvres = true, vy1 = 15, vy2 = 30 })
		for _, a in pil do
			fsolid(f, "Pier", a - 1.25, a + 1.25, 0, 30, 0.2, 1.9, C.stone, M.stone)
		end
		fsolid(f, "Cornice", -85, 85, 15, 16.6, 0, 3.0, C.stone, M.stone)
		fsolid(f, "Parapet", -76, 76, 30, 33.2, 0, 2.0, C.stone, M.stone)
		glassRail(f, -82.5, 82.5, 33.2, 0.5)
		fpart(f, "GreenRoofEdge", -80.8, 80.8, 32, 32.25, -1.2, 0, C.grass, M.grass, DETAIL)
	end

	flushVerts()

	---------------------------------------------------------------- exterior doors with stone surrounds
	for _, entry in doors do
		local d, f = entry.def, entry.face
		local a1, a2 = entry.a - d.w / 2, entry.a + d.w / 2
		local top = entry.y + d.h
		fpart(f, "OpeningJamb", a1 - 0.6, a1, entry.y, top + 0.6, 0, 1.5, C.stoneDeep, M.stone)
		fpart(f, "OpeningJamb", a2, a2 + 0.6, entry.y, top + 0.6, 0, 1.5, C.stoneDeep, M.stone)
		fpart(f, "OpeningHead", a1, a2, top, top + 0.6, 0, 1.5, C.stoneDeep, M.stone)
		local def: any = table.clone(d)
		-- the leaves sit on the glass line of the facade (0.1 outside the plan line)
		if d.axis == "x" then
			def.z = f.c + f.out * 0.1
		else
			def.x = f.c + f.out * 0.1
		end
		def.thickness = if d.kind == "service" then 0.6 else 0.4
		Kit.door(ctx.folders.Doors, B, def, ctx.owner)
	end
end

---------------------------------------------------------------------------------------------
-- 5. Entrance: portal, glazed entrance wall + automatic door, canopy, company sign
---------------------------------------------------------------------------------------------
local function entrance(ctx: any)
	local m = Kit.model(ctx.folders.Facade, "Facade_Entrance")
	local pt = Plan.PORTAL
	local z = Plan.ENTRANCE.z
	local e1, e2 = Plan.ENTRANCE.x1, Plan.ENTRANCE.x2
	box(m, "PortalFloor", pt.x1, pt.x2, 0, 0.12, pt.z1, pt.z2, C.stone, M.marble)
	box(m, "PortalJamb", pt.x1 - 3, pt.x1, 0, 16.6, pt.z1 - 1, pt.z2, C.stone, M.stone)
	box(m, "PortalJamb", pt.x2, pt.x2 + 3, 0, 16.6, pt.z1 - 1, pt.z2, C.stone, M.stone)
	box(m, "PortalHead", pt.x1, pt.x2, 12.2, 16.6, pt.z1 - 1, pt.z1 + 0.2, C.stone, M.stone)
	box(m, "PortalSoffit", pt.x1, pt.x2, 11.9, 12.2, pt.z1 + 0.2, pt.z2, C.oak, M.wood)
	-- glazed entrance wall with the automatic doors in the middle
	for _, r in { { pt.x1, e1 }, { e2, pt.x2 } } do
		box(m, "EntranceSill", r[1], r[2], 0, 0.15, z - 0.2, z + 0.2, C.metal, M.metal)
		box(m, "EntranceGlass", r[1], r[2], 0.15, 11.9, z - 0.1, z + 0.1, C.glass, M.glass, GLASS)
		local mx = (r[1] + r[2]) / 2
		box(m, "Mullion", mx - 0.08, mx + 0.08, 0.15, 11.9, z - 0.25, z + 0.25, C.metal, M.metal, DETAIL)
	end
	box(m, "EntranceTransom", e1, e2, 10, 10.3, z - 0.2, z + 0.2, C.metal, M.metal)
	box(m, "EntranceGlass", e1, e2, 10.3, 11.9, z - 0.1, z + 0.1, C.glass, M.glass, GLASS)
	for _, d in Layout.doors(ctx.tier) do
		if d.id == "G_ENTRANCE" then
			Kit.door(ctx.folders.Doors, B, d, ctx.owner)
		end
	end
	-- card reader pedestal for staff after hours (the doors open for visitors during the day)
	box(m, "CardReaderPedestal", 8.25, 8.75, 0.12, 3.8, -46.75, -46.25, C.metal, M.metal)
	box(m, "CardReaderFace", 8.3, 8.7, 3.0, 3.6, -46.85, -46.75, C.screen, M.smooth, DETAIL)
	box(m, "ReaderLight", 8.4, 8.6, 3.45, 3.52, -46.92, -46.85, C.statusGood, M.neon, DETAIL)

	-- cantilevered canopy: dark metal deck, oak soffit with three downlights, two slender columns, rods
	local cz1, cz2 = -66, pt.z1 - 0.9
	box(m, "CanopyDeck", -20, 20, 12.8, 13.8, cz1, cz2, C.metal, M.metal)
	box(m, "CanopySoffit", -19.7, 19.7, 12.6, 12.8, cz1 + 0.3, cz2, C.oak, M.wood)
	box(m, "CanopyFascia", -20.3, 20.3, 12.4, 14.0, cz1 - 0.3, cz1, C.metal, M.metal)
	for _, s in { -1, 1 } do
		local f1, f2 = sp(s, 20, 20.3)
		box(m, "CanopyFascia", f1, f2, 12.4, 14.0, cz1, cz2, C.metal, M.metal)
		Kit.cylinder(m, B, "CanopyColumn", "y", 12.48, 0.8, CF(s * 17, 0.12 + 6.24, -63), C.metal, M.metal)
		local p1, p2 = V3(s * 14, 13.9, -64.5), V3(s * 14, 27, -49.75)
		local mid = (p1 + p2) / 2
		Kit.cylinder(m, B, "TensionRod", "z", (p2 - p1).Magnitude, 0.18, CFrame.lookAt(mid, p2), C.metalSoft, M.metal, DETAIL)
		box(m, "RodAnchor", s * 14 - 0.4, s * 14 + 0.4, 26.6, 27.4, -49.9, -49.7, C.metal, M.metal, DETAIL)
	end
	for _, x in { -10, 0, 10 } do
		local lamp = box(m, "CanopyDownlight", x - 0.45, x + 0.45, 12.55, 12.6, -58.45, -57.55, C.lightWarm, M.neon, DETAIL)
		if lamp then
			Kit.light(lamp, "spot", C.lightWarm, 14, 0.9, Enum.NormalId.Bottom)
		end
	end
	-- company sign band above the canopy, on the lantern fins (direct child of the office)
	local sign = Kit.part(ctx.office, B, "SignAnchor", V3(40, 5.5, 0.4), CF(0, 20.25, -49.9), C.metal, M.metal, { canCollide = false, castShadow = false })
	Kit.text(sign, ctx.company, { guiName = "Sign", name = "Label", font = Enum.Font.BuilderSansExtraBold, maxDistance = 260, color = C.white, light = 0.2, pps = 40, pad = 0.1 })
	local wash = box(m, "SignWash", -14, 14, 13.8, 14.05, -50.7, -50.3, C.metal, M.metal, DETAIL)
	if wash then
		Kit.light(wash, "spot", C.lightWarm, 10, 0.7, Enum.NormalId.Top)
	end
end

---------------------------------------------------------------------------------------------
-- 2. Garage shell, ramp, barrier
---------------------------------------------------------------------------------------------
local RAMP = { x1 = 92, x2 = 112, zTop = -146, zBottom = -36, drop = 16 }
local function rampY(z: number): number
	return -(z - RAMP.zTop) * RAMP.drop / (RAMP.zBottom - RAMP.zTop)
end

local function garage(ctx: any)
	local m = Kit.model(ctx.folders.Site, "GarageShell")
	local g = Plan.GARAGE
	local by = Plan.B1_Y - 1
	box(m, "GarageWall", g.x1 - 1, g.x1, by, 0, g.z1 - 1, g.z2 + 1, C.concrete, M.concrete)
	box(m, "GarageWall", g.x2, g.x2 + 1, by, 0, g.z1 - 1, g.z2 + 1, C.concrete, M.concrete)
	box(m, "GarageWall", g.x1, RAMP.x1, by, 0, g.z1 - 1, g.z1, C.concrete, M.concrete)
	box(m, "GarageWall", g.x1, g.x2, by, 0, g.z2, g.z2 + 1, C.concrete, M.concrete)
	box(m, "GarageRaft", g.x1 - 1, g.x2 + 1, -26, by, g.z1 - 1, g.z2 + 1, C.concrete, M.concrete)
	-- ramp portal: lintel under the ground slab rising into a parapet at the channel head
	box(m, "RampPortal", RAMP.x1, RAMP.x2, -2, 1.2, g.z1 - 1, g.z1, C.stone, M.stone)

	-- one smooth ramp part: top surface from (z -146, y 0) down to (z -36, y -16)
	local run = RAMP.zBottom - RAMP.zTop
	local L = math.sqrt(run * run + RAMP.drop * RAMP.drop)
	local th = math.atan2(RAMP.drop, run)
	local t = 1
	local n = V3(0, run / L, RAMP.drop / L)
	local mid = V3((RAMP.x1 + RAMP.x2) / 2, -RAMP.drop / 2, (RAMP.zTop + RAMP.zBottom) / 2)
	Kit.part(m, B, "GarageRamp", V3(RAMP.x2 - RAMP.x1, t, L), CF(mid - n * (t / 2)) * ANG(th, 0, 0), C.asphalt, M.asphalt)
	-- concrete fill under the ramp (wedge flush with its underside) and its footing outside the garage
	local hW = RAMP.drop - t * L / run
	local lenW = hW * run / RAMP.drop
	Kit.wedge(m, B, "RampFill", V3(RAMP.x2 - RAMP.x1, hW, lenW), CF((RAMP.x1 + RAMP.x2) / 2, Plan.B1_Y + hW / 2, RAMP.zTop + lenW / 2) * ANG(0, PI, 0), C.concrete, M.concrete)
	box(m, "RampFooting", RAMP.x1, RAMP.x2, -26, Plan.B1_Y, RAMP.zTop, g.z1 - 1, C.concrete, M.concrete)
	-- stone retaining walls up to +1.2 with a metal guard rail
	box(m, "RetainingWall", RAMP.x1 - 1, RAMP.x1, -26, 1.2, RAMP.zTop, g.z1 - 1, C.stone, M.stone)
	box(m, "RetainingWall", RAMP.x2, RAMP.x2 + 1, -26, 1.2, RAMP.zTop, g.z1 - 1, C.stone, M.stone)
	metalRail(m, "z", RAMP.x1 - 0.5, RAMP.zTop, g.z1 - 1, 1.2)
	metalRail(m, "z", RAMP.x2 + 0.5, RAMP.zTop, g.z1 - 1, 1.2)
	metalRail(m, "x", g.z1 - 0.5, RAMP.x1, RAMP.x2, 1.2)
	-- lane marking down the ramp
	local lane = Kit.part(m, B, "RampLaneMark", V3(0.3, 0.05, L - 4), CF(mid + n * 0.025) * ANG(th, 0, 0), C.white, M.smooth, DETAIL)
	lane.Transparency = 0.2

	-- boom barrier at the ramp head (drivers holding a card open it by approaching)
	local def: any = {
		id = "SITE_BARRIER", level = 0, room = "B1_GARAGE", kind = "gate", access = "staff", axis = "x",
		x = (RAMP.x1 + RAMP.x2) / 2, z = -140, w = RAMP.x2 - RAMP.x1, h = 4, inward = V3(0, 0, 1),
		exterior = true, hidden = false, builder = "exterior", variant = "barrier", y = rampY(-140),
	}
	local barrier = Kit.door(ctx.folders.Doors, B, def, ctx.owner)
	if barrier then
		barrier:SetAttribute("AutoOpen", true)
	end
end

---------------------------------------------------------------------------------------------
-- 3 + 6. Foundations, surfaces, arrival plaza and landscape
---------------------------------------------------------------------------------------------
local function site(ctx: any)
	local folder: Instance = ctx.folders.Site
	local s = Plan.SITE
	local fnd = Kit.model(folder, "Foundations")
	-- SITE minus the garage footprint (with its walls) and minus the ramp channel; top y = 0
	-- (y = -1 under the pavilion's ground slab)
	local hotel = Plan.hasHotel(ctx.tier)
	local hr: Rect = { x1 = Plan.HOTEL.x1, x2 = Plan.HOTEL.x2, z1 = Plan.HOTEL.z1, z2 = Plan.HOTEL.z2 }
	for _, r in {
		{ s.x1, RAMP.x1 - 1, s.z1, -65 },
		{ RAMP.x1 - 1, s.x2, s.z1, RAMP.zTop },
		{ RAMP.x2 + 1, s.x2, RAMP.zTop, 89 },
		{ s.x1, -95, -65, 89 },
		{ s.x1, -82, 89, s.z2 },
		{ 82, s.x2, 89, s.z2 },
		{ -82, 82, 160, s.z2 },
	} do
		if hotel then
			-- the guest house stands on its own ground slab: its footprint is lowered like the pavilion's
			for _, piece in subtract({ x1 = r[1], x2 = r[2], z1 = r[3], z2 = r[4] }, { hr }) do
				box(fnd, "Foundation", piece.x1, piece.x2, -26, 0, piece.z1, piece.z2, C.concrete, M.concrete)
			end
		else
			box(fnd, "Foundation", r[1], r[2], -26, 0, r[3], r[4], C.concrete, M.concrete)
		end
	end
	box(fnd, "Foundation", -82, 82, -26, -1, 89, 160, C.concrete, M.concrete)
	if hotel then
		box(fnd, "Foundation", hr.x1, hr.x2, -26, -1, hr.z1, hr.z2, C.concrete, M.concrete)
	end

	local srf = Kit.model(folder, "Surfaces")
	local function lawn(x1: number, x2: number, z1: number, z2: number)
		box(srf, "Lawn", x1, x2, 0, 0.1, z1, z2, C.grass, M.grass)
	end
	local function pave(name: string, x1: number, x2: number, z1: number, z2: number, color: Color3?, mat: Enum.Material?)
		box(srf, name, x1, x2, 0, 0.12, z1, z2, color or C.stonePave, mat or M.pave)
	end
	local function asphalt(name: string, x1: number, x2: number, z1: number, z2: number)
		box(srf, name, x1, x2, 0, 0.1, z1, z2, C.asphalt, M.asphalt)
	end
	-- front lawns either side of the arrival walk, visitor parking beside the driveway
	lawn(s.x1, -12, s.z1, -120)
	lawn(12, 70, s.z1, -120)
	lawn(70, RAMP.x1, s.z1, -200)
	lawn(70, RAMP.x1 - 1, -150, -120)
	lawn(RAMP.x2, s.x2, s.z1, RAMP.zTop)
	lawn(RAMP.x2 + 1, s.x2, RAMP.zTop, 40)
	pave("ArrivalWalk", -12, 12, s.z1, -120, C.stone, M.stone)
	asphalt("Driveway", RAMP.x1, RAMP.x2, s.z1, RAMP.zTop)
	asphalt("VisitorParking", 70, RAMP.x1, -200, -150)
	pave("VisitorPath", 74, 80, -150, -120)
	-- plaza (over foundation and over the garage roof in front of the building)
	pave("Plaza", -96, RAMP.x1 - 1, -120, -48)
	pave("Plaza", RAMP.x1 - 1, Plan.GARAGE.x2 + 1, Plan.GARAGE.z1, -48)
	-- west: lawn south of the arcade, colonnade, path to the garden, lawn behind the pavilion
	lawn(s.x1, -96, -120, -56)
	pave("ColonnadeFloor", -96, -82, -48, 72, C.stone, M.stone)
	pave("WestPath", -96, -88, 72, 184)
	if hotel then
		for _, piece in subtract({ x1 = s.x1, x2 = -96, z1 = 72, z2 = s.z2 }, { hr }) do
			lawn(piece.x1, piece.x2, piece.z1, piece.z2)
		end
	else
		lawn(s.x1, -96, 72, s.z2)
	end
	box(srf, "PlantingBed", -88, -82, 0, 0.15, 72, 160, C.soil, M.leafy)
	-- east: facade path to the service yard, green roof over the garage strip
	pave("EastPath", 82, 92, -48, 40)
	lawn(92, Plan.GARAGE.x2 + 1, -48, 40)
	box(srf, "PlantingBed", 82, 86, 0, 0.15, 89, 160, C.soil, M.leafy)

	-- walk joints (large calm pavers) and the plaza's joint grid: few long thin non-colliding parts
	local pz = Kit.model(folder, "Plaza")
	for z = s.z1 + 6, -126, 6 do
		box(pz, "PavingJoint", -12, 12, 0.12, 0.17, z - 0.06, z + 0.06, C.stoneDeep, M.stone, DETAIL)
	end
	for x = -84, 84, 12 do
		local z2 = if x <= RAMP.x1 - 1 then -120 else Plan.GARAGE.z1
		box(pz, "PavingJoint", x - 0.06, x + 0.06, 0.12, 0.17, z2, -48, C.stoneDeep, M.pave, DETAIL)
	end
	for z = -108, -60, 12 do
		box(pz, "PavingJoint", -96, if z >= Plan.GARAGE.z1 then Plan.GARAGE.x2 + 1 else RAMP.x1 - 1, 0.12, 0.17, z - 0.06, z + 0.06, C.stoneDeep, M.pave, DETAIL)
	end
	-- low planters flanking the entrance along the plinth
	for k, x in { -40, 40 } do
		Kit.planter(pz, B, Kit.place(x, 0.12, -52, 0), 12, 2.4, Kit.hash("entry") + k)
	end
	-- planting islands with benches facing the plaza
	local seed = Kit.hash("plaza")
	island(pz, -68, -52, -108, -96, seed + 1)
	island(pz, 52, 68, -108, -96, seed + 2)
	island(pz, -46, -34, -86, -76, seed + 3)
	island(pz, 34, 46, -86, -76, seed + 4)
	local benchX, benchZ, benchF = { -60, 60, -40, 40 }, { -95, -95, -87, -87 }, { "N", "N", "S", "S" }
	for i = 1, 4 do
		Kit.bench(pz, B, Kit.place(benchX[i], 0.12, benchZ[i], benchF[i]), 6, seed + 10 + i)
	end
	-- path lights along the arrival walk (six of them carry a real light)
	for i, z in { -206, -188, -170, -152, -134 } do
		for _, x in { -13.6, 13.6 } do
			bollard(pz, x, z, i % 2 == 1)
		end
	end
	-- bike racks
	box(pz, "BikeRackRail", 22, 36, 0.12, 0.3, -116.2, -115.8, C.metal, M.metal)
	for x = 23, 35, 3 do
		for _, dz in { -0.9, 0.9 } do
			box(pz, "BikeHoop", x - 0.08, x + 0.08, 0.3, 2.6, -116 + dz - 0.08, -116 + dz + 0.08, C.metal, M.metal, DETAIL)
		end
		box(pz, "BikeHoop", x - 0.08, x + 0.08, 2.6, 2.76, -116.98, -115.02, C.metal, M.metal, DETAIL)
	end
	-- company stele at the walk / plaza junction
	box(pz, "SteleBase", -22.4, -17.6, 0.1, 0.5, -125.4, -122.6, C.stoneDeep, M.stone)
	local stele = box(pz, "CompanyStele", -21.6, -18.4, 0.5, 12.5, -124.6, -123.4, C.stone, M.stone)
	if stele then
		local plate = Kit.part(stele, B, "StelePlate", V3(2.6, 6.5, 0.12), CF(-20, 8.6, -124.66), C.metal, M.metal, { castShadow = false })
		Kit.text(plate, ctx.company, { color = C.white, font = Enum.Font.BuilderSansBold, maxDistance = 120, pps = 60, pad = 0.08 })
		box(pz, "SteleAccent", -21.3, -18.7, 12.0, 12.2, -124.68, -124.6, ctx.accent, M.smooth, DETAIL)
	end
	-- visitor bays (4) with markings
	for z = -196, -156, 10 do
		box(pz, "BayLine", 72, 90, 0.1, 0.15, z - 0.12, z + 0.12, C.white, M.smooth, DETAIL)
	end
	box(pz, "BayLine", 72, 72.25, 0.1, 0.15, -196, -156, C.white, M.smooth, DETAIL)
	for z = -191, -161, 10 do
		box(pz, "WheelStop", 73, 74, 0.1, 0.4, z - 3, z + 3, C.stoneDeep, M.concrete)
	end

	-- trees: street row at the frontage, lawns, green roof planters
	local land = Kit.model(folder, "Landscape")
	local ts = Kit.hash("trees")
	local i = 0
	local function t(x: number, z: number)
		i += 1
		if hotel and x > hr.x1 - 3 and x < hr.x2 + 3 and z > hr.z1 - 3 and z < hr.z2 + 3 then
			return -- trees inside the guest house footprint are not planted (seeds of the others unchanged)
		end
		tree(land, x, z, ts + i * 17)
	end
	for _, x in { -132, -110, -88, -66, -44, -24, 24, 46, 128 } do
		t(x, -205)
		box(land, "TreeGrate", x - 2, x + 2, 0.1, 0.16, -207, -203, C.metal, M.metal, DETAIL)
	end
	for _, p in { { -38, -150 }, { -64, -172 }, { -96, -150 }, { -124, -176 }, { 36, -146 }, { 56, -172 }, { -124, -104 }, { -110, -76 },
		{ 128, -126 }, { 130, -96 }, { 126, -60 }, { 130, -24 }, { 128, 12 }, { -124, 92 }, { -112, 124 }, { -128, 150 } } do
		t(p[1], p[2])
	end
	island(land, 96, 108, -32, -22, ts + 101)
	island(land, 96, 108, 4, 14, ts + 102)
end

---------------------------------------------------------------------------------------------
-- Campus arcade: four public stores facing a colonnade west of the HQ
---------------------------------------------------------------------------------------------
local function storeUnit(parent: Instance, store: any, index: number, z1: number, z2: number, accent: Color3)
	local um = Kit.model(parent, "Store_" .. tostring(store.id))
	local zc = (z1 + z2) / 2
	local seed = Kit.hash(tostring(store.id))
	local X1, X2 = -141, -96
	local floorColor: { [string]: Color3 } = { cafe = C.oak, hardware = C.metalSoft, studio = C.oakLight, mobility = C.stone }
	local floorMat: { [string]: Enum.Material } = { cafe = M.planks, hardware = M.slate, studio = M.planks, mobility = M.stone }
	local id = tostring(store.id)
	box(um, "StoreFloor", X1, X2, 0, 0.12, z1, z2, floorColor[id] or C.stone, floorMat[id] or M.stone)
	Kit.ceiling(um, B, { x1 = X1, x2 = X2, z1 = z1, z2 = z2 }, 0, "plaster", "warm", { height = 10.6, maxLights = 1 })
	box(um, "StoreCladding", X1, X1 + 0.2, 0.12, 10.6, z1, z2, C.oakLight, M.wood)
	-- open storefront: stone lintel with the store sign, glass side lights in oak frames
	box(um, "StoreLintel", X2 - 0.6, X2 + 0.4, 9, 11, z1, z2, C.stone, M.stone)
	local sign = box(um, "StoreSign", X2 + 0.4, X2 + 0.6, 9.3, 10.7, zc - 9, zc + 9, accent, M.smooth)
	if sign then
		Kit.text(sign, string.upper(tostring(store.name)), { face = Enum.NormalId.Right, color = C.white, font = Enum.Font.BuilderSansBold, maxDistance = 140, pad = 0.12 })
	end
	for _, r in { { z1, z1 + 7 }, { z2 - 7, z2 } } do
		box(um, "StoreGlass", X2 - 0.1, X2 + 0.1, 0.12, 9, r[1], r[2], C.glass, M.glass, GLASS)
	end
	box(um, "StoreFrame", X2 - 0.25, X2 + 0.25, 0.12, 9, z1 + 7, z1 + 7.4, C.oak, M.wood)
	box(um, "StoreFrame", X2 - 0.25, X2 + 0.25, 0.12, 9, z2 - 7.4, z2 - 7, C.oak, M.wood)
	-- subtitle plaque on the back wall
	local info = box(um, "StoreInfo", X1 + 0.2, X1 + 0.35, 6.2, 8.2, zc - 6, zc + 6, C.metal, M.metal)
	if info then
		Kit.text(info, tostring(store.subtitle), { face = Enum.NormalId.Right, color = C.white, font = Enum.Font.BuilderSans, maxDistance = 60, pad = 0.12 })
	end
	-- counter (customers on the east side) with the owner-agnostic store terminal
	local cx = -124
	Kit.counter(um, B, Kit.place(cx, 0.12, zc - 2, "E"), 12, seed)
	local terminal = box(um, "StoreTerminal", cx + 0.2, cx + 0.4, 3.725, 5.3, zc - 7.6, zc - 5.6, C.screen, M.smooth)
	if terminal then
		publicPrompt(terminal, tostring(store.name), tostring(store.app))
		Kit.text(terminal, tostring(store.name), { face = Enum.NormalId.Right, color = accent, font = Enum.Font.BuilderSansBold, maxDistance = 40, pad = 0.15 })
	end
	if store.id == "cafe" then
		for n, snack in CampusConfig.SNACKS do
			local col = Color3.fromRGB(snack.color[1], snack.color[2], snack.color[3])
			local z = zc - 4.4 + (n - 1) * 2.2
			local item = box(um, "StoreSnack", cx - 0.4, cx + 0.8, 3.725, 4.925, z - 0.7, z + 0.7, col, M.smooth)
			if item then
				publicPrompt(item, snack.name .. " · $" .. tostring(snack.price), nil, "snack", snack.id)
			end
		end
		Kit.kitchenette(um, B, Kit.place(X1 + 0.2, 0.12, zc - 2, "E"), 12, seed, { fridge = false, coffeeName = "StoreCoffee" })
		for k, z in { zc - 9, zc + 8 } do
			local at = Kit.place(-106, 0.12, z, 0)
			Kit.meetingTable(um, B, at, "round", 3.6, nil, seed + k)
			Kit.stool(um, B, at * CF(-2.8, 0, 0) * ANG(0, -PI / 2, 0), seed + k, 2.2)
			Kit.stool(um, B, at * CF(2.8, 0, 0) * ANG(0, PI / 2, 0), seed + k + 1, 2.2)
		end
		Kit.tvScreen(um, B, Kit.place(X1 + 0.2, 0.12, zc + 9, "E"), 5, "cafe", accent, { y = 6.5 })
	elseif store.id == "hardware" then
		for k, x in { -136, -130 } do
			Kit.rackShelf(um, B, Kit.place(x, 0.12, z2, "S"), 5, seed + k)
			Kit.rackShelf(um, B, Kit.place(x, 0.12, z1, "N"), 5, seed + k + 5)
		end
		box(um, "DisplayPlinth", -110, -106, 0.12, 3.1, zc - 2, zc + 2, C.stone, M.stone)
		box(um, "GPUDisplay", -109.4, -106.6, 3.1, 3.7, zc - 1.2, zc + 1.2, C.metal, M.metal)
		box(um, "GPUAccent", -106.65, -106.55, 3.2, 3.6, zc - 1.0, zc + 1.0, accent, M.neon, DETAIL)
		Kit.tvScreen(um, B, Kit.place(X1 + 0.2, 0.12, zc + 8, "E"), 5, "compute", accent, { y = 6.5 })
	elseif store.id == "studio" then
		for k, z in { zc - 6, zc + 6 } do
			box(um, "DisplayTable", -114, -106, 2.6, 2.9, z - 2, z + 2, C.oak, M.wood)
			box(um, "DisplayBase", -113, -107, 0.12, 2.6, z - 1.4, z + 1.4, C.white, M.smooth)
			for j = 0, 2 do
				local x = -112.5 + j * 2.5
				box(um, "Product", x - 0.6, x + 0.6, 2.9, 3.9 + (j % 2) * 0.6, z - 0.8, z + 0.8, if (j + k) % 2 == 0 then accent else C.white, M.smooth)
			end
		end
		Kit.cabinet(um, B, Kit.place(-134, 0.12, z2, "S"), 4, 7, seed)
		Kit.tvScreen(um, B, Kit.place(X1 + 0.2, 0.12, zc + 8, "E"), 6, "product", accent, { y = 6.5 })
	else
		Kit.cabinet(um, B, Kit.place(-134, 0.12, z2, "S"), 5, 7, seed)
		Kit.loungeChair(um, B, Kit.place(-108, 0.12, zc + 7, "S"), seed)
		Kit.loungeChair(um, B, Kit.place(-108, 0.12, zc - 9, "N"), seed + 1)
		Kit.coffeeTable(um, B, Kit.place(-108, 0.12, zc - 1, 0), seed, 3, 2.4)
		Kit.tvScreen(um, B, Kit.place(X1 + 0.2, 0.12, zc + 8, "E"), 6, "fleet", accent, { y = 6.5 })
	end
	if store.id ~= "hardware" then
		Kit.rackShelf(um, B, Kit.place(-112, 0.12, z1, "N"), 6, seed + 30)
	end
	Kit.plant(um, B, Kit.place(X2 - 3, 0.12, z1 + 3, 0), "l", seed + index)
end

local function arcade(ctx: any)
	local m = Kit.model(ctx.folders.Site, "CampusArcade")
	local X1, X2 = -142, -96
	local Z0, W = -56, 32
	local n = #CampusConfig.STORES
	local Z1 = Z0 + n * W
	-- shell: party walls (projecting as stone frames), back wall, roof, stone fascia over the colonnade
	for i = 0, n do
		local z = Z0 + i * W
		box(m, "ArcadeWall", X1, X2 + 1, 0.1, 14, z - 0.6, z + 0.6, C.stone, M.stone)
	end
	box(m, "ArcadeBack", X1, X1 + 1, 0.1, 14, Z0 - 0.6, Z1 + 0.6, C.stone, M.stone)
	box(m, "ArcadeRoof", X1, X2 + 1, 13, 14, Z0 - 0.6, Z1 + 0.6, C.stoneDeep, M.stone)
	box(m, "GreenRoof", X1 + 1, X2 - 0.4, 14, 14.25, Z0, Z1, C.grass, M.grass)
	box(m, "ArcadeFascia", X2 - 0.4, X2 + 0.6, 11.8, 14.6, Z0 - 0.6, Z1 + 0.6, C.stone, M.stone)
	-- colonnade: stone columns every 8 under one continuous canopy
	for z = Z0 + 4, Z1 - 4, 8 do
		box(m, "ColonnadeColumn", -86.7, -85.3, 0.12, 11, z - 0.7, z + 0.7, C.stone, M.stone)
	end
	box(m, "ColonnadeCanopy", X2 + 0.6, -85, 11, 11.8, Z0 - 0.6, Z1 + 0.6, C.stone, M.stone)
	box(m, "ColonnadeSoffit", X2 + 0.6, -85.3, 10.8, 11, Z0 - 0.6, Z1 + 0.6, C.oak, M.wood)
	box(m, "ColonnadeFascia", -85.3, -85, 10.6, 12.0, Z0 - 0.6, Z1 + 0.6, C.metal, M.metal)
	for i, store in CampusConfig.STORES do
		local z1 = Z0 + (i - 1) * W
		storeUnit(m, store, i, z1 + 0.6, z1 + W - 0.6, ctx.accent)
	end
end

---------------------------------------------------------------------------------------------
-- Rear garden: lawn, stone paths, water basin, pergola, benches, trees
---------------------------------------------------------------------------------------------
local function garden(ctx: any)
	local m = Kit.model(ctx.folders.Site, "Garden")
	local s = Plan.SITE
	box(m, "Lawn", -96, 86, 0, 0.1, 160, s.z2, C.grass, M.grass)
	box(m, "GardenPath", -96, 86, 0, 0.14, 184, 190, C.stonePave, M.pave)
	box(m, "GardenPath", 66, 74, 0, 0.14, 160, 184, C.stonePave, M.pave)
	box(m, "GardenPath", -32, -24, 0, 0.14, 190, 200, C.stonePave, M.pave)
	-- long shallow water basin: collidable stone rim, non-colliding water surface
	local bx1, bx2, bz1, bz2 = -70, 30, 166, 178
	box(m, "BasinRim", bx1, bx2, 0.1, 1.0, bz1, bz1 + 0.8, C.stone, M.stone)
	box(m, "BasinRim", bx1, bx2, 0.1, 1.0, bz2 - 0.8, bz2, C.stone, M.stone)
	box(m, "BasinRim", bx1, bx1 + 0.8, 0.1, 1.0, bz1 + 0.8, bz2 - 0.8, C.stone, M.stone)
	box(m, "BasinRim", bx2 - 0.8, bx2, 0.1, 1.0, bz1 + 0.8, bz2 - 0.8, C.stone, M.stone)
	box(m, "BasinFloor", bx1 + 0.8, bx2 - 0.8, 0.1, 0.25, bz1 + 0.8, bz2 - 0.8, C.metalSoft, M.slate)
	box(m, "Water", bx1 + 0.8, bx2 - 0.8, 0.25, 0.7, bz1 + 0.8, bz2 - 0.8, C.water, M.glass, WATER)
	-- pergola with oak beams over a seating area
	local px1, px2, pz1, pz2 = -46, -10, 200, 216
	box(m, "PergolaFloor", px1, px2, 0, 0.14, pz1, pz2, C.stone, M.stone)
	for _, x in { px1 + 1, (px1 + px2) / 2, px2 - 1 } do
		for _, z in { pz1 + 1, pz2 - 1 } do
			box(m, "PergolaPost", x - 0.4, x + 0.4, 0.14, 9.8, z - 0.4, z + 0.4, C.oak, M.wood)
		end
	end
	for _, z in { pz1 + 1, pz2 - 1 } do
		box(m, "PergolaBeam", px1, px2, 9.0, 9.8, z - 0.4, z + 0.4, C.oak, M.wood)
	end
	for x = px1 + 1.5, px2 - 1.5, 3 do
		box(m, "PergolaRafter", x - 0.2, x + 0.2, 9.8, 10.3, pz1 - 0.5, pz2 + 0.5, C.oakDark, M.wood)
	end
	local seed = Kit.hash("garden")
	box(m, "GardenTable", -36, -20, 2.9, 3.2, 207, 209, C.oakDark, M.wood)
	for _, x in { -34, -22 } do
		box(m, "GardenTableLeg", x - 0.3, x + 0.3, 0.14, 2.9, 207.4, 208.6, C.metal, M.metal)
	end
	Kit.bench(m, B, Kit.place(-28, 0.14, 205.4, "N"), 15, seed + 1)
	Kit.bench(m, B, Kit.place(-28, 0.14, 210.6, "S"), 15, seed + 2)
	Kit.bench(m, B, Kit.place(-40, 0.14, 181.8, "S"), 6, seed + 3)
	Kit.bench(m, B, Kit.place(0, 0.14, 181.8, "S"), 6, seed + 4)
	Kit.bench(m, B, Kit.place(-92, 0.14, 150, "E"), 6, seed + 5)
	local i = 0
	local h = Plan.HOTEL
	local hotel = Plan.hasHotel(ctx.tier)
	for _, p in { { -80, 214 }, { 2, 214 }, { 24, 204 }, { 48, 216 }, { 74, 210 }, { -104, 168 }, { -118, 196 }, { -130, 218 }, { -80, 172 }, { 50, 170 } } do
		i += 1
		if hotel and p[1] > h.x1 - 3 and p[1] < h.x2 + 3 and p[2] > h.z1 - 3 and p[2] < h.z2 + 12 then
			continue -- inside the guest house footprint / its terrace
		end
		tree(m, p[1], p[2], seed + i * 23)
	end
end

---------------------------------------------------------------------------------------------
-- Service yard: asphalt, delivery bay, bin enclosure, service drive, hedge with gate to the garden
---------------------------------------------------------------------------------------------
local function yard(ctx: any)
	local m = Kit.model(ctx.folders.Site, "ServiceYard")
	local s = Plan.SITE
	box(m, "YardAsphalt", 82, 142, 0, 0.1, 40, 89, C.asphalt, M.asphalt)
	box(m, "YardAsphalt", 86, 132, 0, 0.1, 89, 160, C.asphalt, M.asphalt)
	box(m, "YardAsphalt", 88, 132, 0, 0.1, 160, 224, C.asphalt, M.asphalt)
	box(m, "ServiceDrive", 100, 120, 0, 0.1, 224, s.z2, C.asphalt, M.asphalt)
	box(m, "Lawn", 142, s.x2, 0, 0.1, 40, 89, C.grass, M.grass)
	box(m, "Lawn", 132, s.x2, 0, 0.1, 89, s.z2, C.grass, M.grass)
	box(m, "Lawn", 86, 100, 0, 0.1, 224, s.z2, C.grass, M.grass)
	box(m, "Lawn", 120, 132, 0, 0.1, 224, s.z2, C.grass, M.grass)
	box(m, "YardKerb", 131.6, 132, 0.1, 0.5, 89, 224, C.stoneDeep, M.stone)
	local ts = Kit.hash("yard")
	for k, z in { 104, 134, 164, 194 } do
		tree(m, 138.5, z, ts + k * 7)
	end
	-- delivery bay marking in front of the service door
	for _, r in { { 86, 102, 57.8, 58.1 }, { 86, 102, 73.9, 74.2 }, { 101.7, 102, 58.1, 73.9 } } do
		box(m, "BayMarking", r[1], r[2], 0.1, 0.15, r[3], r[4], C.statusBusy, M.smooth, DETAIL)
	end
	for k = 0, 3 do
		local z = 61 + k * 3.5
		box(m, "BayHatch", 90, 98, 0.1, 0.15, z - 0.15, z + 0.15, C.statusBusy, M.smooth, DETAIL)
	end
	-- bin enclosure (open towards the yard)
	box(m, "BinWall", 122, 138, 0.1, 4, 44, 44.8, C.stone, M.stone)
	box(m, "BinWall", 122, 138, 0.1, 4, 55.2, 56, C.stone, M.stone)
	box(m, "BinWall", 137.2, 138, 0.1, 4, 44.8, 55.2, C.stone, M.stone)
	for k, col in { C.sage, C.blue, C.metalSoft } do
		local z = 46.8 + (k - 1) * 3.2
		box(m, "Bin", 132, 136, 0.1, 3.4, z - 1.3, z + 1.3, col, M.smooth)
		box(m, "BinLid", 131.9, 136.1, 3.4, 3.6, z - 1.4, z + 1.4, C.metal, M.metal, DETAIL)
	end
	-- hedges: along the yard edge at z = 40 (gap for the east path) and between garden and yard
	box(m, "Hedge", 92, s.x2, 0.1, 3.2, 38.8, 40.4, C.foliage, M.leafy)
	box(m, "Hedge", 86, 88, 0.1, 5, 160, 184, C.foliage, M.leafy)
	box(m, "Hedge", 86, 88, 0.1, 5, 190, 224, C.foliage, M.leafy)
	local def: any = {
		id = "SITE_YARDGATE", level = 0, room = "SITE_YARD", kind = "gate", access = "staff", axis = "z",
		x = 87, z = 187, w = 6, h = 5, inward = V3(1, 0, 0), exterior = true, hidden = false, builder = "exterior", y = 0.1,
	}
	Kit.door(ctx.folders.Doors, B, def, ctx.owner)
end

---------------------------------------------------------------------------------------------
-- Exterior security cameras
---------------------------------------------------------------------------------------------
local function cameras(ctx: any)
	local folder: Instance = ctx.folders.Cameras
	Kit.camera(folder, B, "EXT_ENTRANCE", "Entrance & plaza", V3(19, 11.4, -65), V3(0, 2, -112), 0, "SITE_PLAZA", false)
	box(ctx.folders.Site, "CameraPole", 115.8, 116.2, 0.1, 7.6, -132.2, -131.8, C.metal, M.metal)
	Kit.camera(folder, B, "EXT_RAMP", "Garage ramp & barrier", V3(116, 6.6, -132.6), V3(102, -1, -150), 0, "SITE_RAMP", false)
	Kit.camera(folder, B, "EXT_YARD", "Service yard", V3(84.4, 11, 112), V3(112, 0, 66), 0, "SITE_YARD", false)
end

---------------------------------------------------------------------------------------------
-- Guest house (hotel annex, Plan.hasHotel): two storeys in the HQ language (stone piers, cornice and
-- parapet, glazing with oak louvres), green roof behind a glass rail, built neon "GUEST HOUSE" letters on
-- the south and west parapets, entrance canopy over the WestPath with a lit approach from the colonnade,
-- a terrace towards the garden. Rooms, walls and interior doors come from the plan pipeline
-- (InteriorDesign / RoomKitsHotel); the slabs from Layout.slabs (structure()).
---------------------------------------------------------------------------------------------
local function guestHouse(ctx: any)
	local tier: number = ctx.tier
	local h = Plan.HOTEL
	local folder: Instance = ctx.folders.Facade
	local west = newFace("hwest", Kit.model(folder, "Facade_HotelWest"), "z", h.x1, -1)
	local east = newFace("heast", Kit.model(folder, "Facade_HotelEast"), "z", h.x2, 1)
	local south = newFace("hsouth", Kit.model(folder, "Facade_HotelSouth"), "x", h.z1, -1)
	local north = newFace("hnorth", Kit.model(folder, "Facade_HotelNorth"), "x", h.z2, 1)
	local faces = { west, east, south, north }
	-- door openings first (entrance on the east side, emergency exit to the terrace)
	local doors = {}
	for _, d in Layout.doors(tier) do
		if d.builder == "exterior" and d.annex == "hotel" then
			local da = if d.axis == "x" then d.x else d.z
			local dc = if d.axis == "x" then d.z else d.x
			local y = Plan.levelY(d.level)
			for _, f in faces do
				if f.axis == d.axis and math.abs(f.c - dc) < 0.01 then
					table.insert(f.holes, { x1 = da - d.w / 2 - 0.6, x2 = da + d.w / 2 + 0.6, z1 = y, z2 = y + d.h + 0.6 })
					table.insert(doors, { def = d, face = f, a = da, y = y })
					break
				end
			end
		end
	end
	-- the west face stands 1 stud inside the site edge: its elements project at most 1.0 (no louvres)
	local function depthOf(f: Face): number
		return if f == west then 1.0 else 1.6
	end
	local spans: { [Face]: { number } } = {
		[west] = { h.z1, h.z2 },
		[east] = { h.z1, h.z2 },
		[south] = { h.x1 - 1.0, h.x2 + 1.6 },
		[north] = { h.x1 - 1.0, h.x2 + 1.6 },
	}
	-- piers on the room walls of the long sides (one window bay per guest room on the west side)
	local piers: { [Face]: { number } } = { [west] = { 102, 116, 130, 144, 158 }, [east] = { 104, 126, 148 }, [south] = {}, [north] = {} }
	for _, f in faces do
		local a1, a2 = spans[f][1], spans[f][2]
		local pil = piers[f]
		local PD = depthOf(f)
		local louvres = f ~= west
		fsolid(f, "CornerPier", a1, a1 + 3, 0, 33.2, 0, PD, C.stone, M.stone)
		fsolid(f, "CornerPier", a2 - 3, a2, 0, 33.2, 0, PD, C.stone, M.stone)
		local g1, g2 = a1 + 3, a2 - 3
		fsolid(f, "BaseCourse", g1, g2, 0, 0.9, 0, 1.0, C.stoneDeep, M.stone)
		storey(f, g1, g2, 0.9, 15, { tier = tier, level = 0, grid = 0, skip = pil, skipW = 2, transom = 10.8, louvres = louvres, vy1 = 0.9, vy2 = 15 })
		storey(f, g1, g2, 16.6, 30, { tier = tier, level = 1, grid = 0, skip = pil, skipW = 2, louvres = louvres, vy1 = 15, vy2 = 30 })
		for _, a in pil do
			fsolid(f, "Pier", a - 1, a + 1, 0, 30, 0.2, PD, C.stone, M.stone)
		end
		-- cornice band: 2.2 deep (1.0 on the west face); the short sides wrap the east corner
		local cd = if f == west then 1.0 else 2.2
		local e2 = if f.axis == "x" then 2.2 - PD else 0
		fsolid(f, "Cornice", a1, a2 + e2, 15, 16.6, 0, cd, C.stone, M.stone)
		fsolid(f, "Parapet", g1, g2, 30, 33.2, 0, PD, C.stone, M.stone)
		glassRail(f, a1, a2, 33.2, 0.5)
	end
	flushVerts()
	for _, entry in doors do
		local d, f = entry.def, entry.face
		local a1, a2 = entry.a - d.w / 2, entry.a + d.w / 2
		local top = entry.y + d.h
		fpart(f, "OpeningJamb", a1 - 0.6, a1, entry.y, top + 0.6, 0, 1.5, C.stoneDeep, M.stone)
		fpart(f, "OpeningJamb", a2, a2 + 0.6, entry.y, top + 0.6, 0, 1.5, C.stoneDeep, M.stone)
		fpart(f, "OpeningHead", a1, a2, top, top + 0.6, 0, 1.5, C.stoneDeep, M.stone)
		local def: any = table.clone(d)
		if d.axis == "x" then
			def.z = f.c + f.out * 0.1
		else
			def.x = f.c + f.out * 0.1
		end
		def.thickness = 0.4
		Kit.door(ctx.folders.Doors, B, def, ctx.owner)
	end
	-- green roof on the roof slab (Layout.slabs level 2) with two condenser units
	local roof = Kit.model(ctx.folders.Structure, "HotelRoof")
	local RY = h.roofY
	box(roof, "GreenRoof", h.x1, h.x2, RY, RY + 0.15, h.z1, h.z2, C.grass, M.grass)
	for _, z in { 112, 150 } do
		box(roof, "RoofUnit", -112, -106, RY + 0.15, RY + 2.8, z - 2.5, z + 2.5, C.metalSoft, M.metal)
		Kit.cylinder(roof, B, "RoofFan", "y", 0.2, 3.2, CF(-109, RY + 2.9, z), C.metal, M.metal, DETAIL)
	end
	-- entrance canopy: cantilevered from the facade over the apron and half the WestPath on two tension
	-- rods; dark deck, oak soffit with three downlights (the middle one a real SpotLight), a warm LED line
	-- under the fascia and the house name on its front (east). The south end stays a plain fascia: seen
	-- from the colonnade it sits right behind the blade sign, which names the house at that spot
	local grounds = Kit.model(ctx.folders.Site, "GuestHouseGrounds")
	box(grounds, "HotelApron", h.x2, -96, 0, 0.14, 82, 98, C.stone, M.stone)
	local m = east.model
	local CX = h.x2 + 8 -- canopy front edge (x -90; the WestPath is x -96..-88)
	box(m, "HotelCanopy", h.x2 + 0.2, CX, 11.2, 12.2, 82, 98, C.metal, M.metal)
	box(m, "HotelCanopySoffit", h.x2 + 0.2, CX - 0.2, 11.0, 11.2, 82.3, 97.7, C.oak, M.wood)
	local fascia = box(m, "HotelCanopyFascia", CX, CX + 0.3, 10.6, 12.6, 81.7, 98.3, C.metal, M.metal)
	if fascia then
		Kit.text(fascia, "GUEST HOUSE", { face = Enum.NormalId.Right, color = C.lightWarm, light = 0, font = Enum.Font.BuilderSansBold, maxDistance = 140, pad = 0.14, name = "GuestHouseSign" })
	end
	box(m, "HotelCanopyFascia", h.x2 + 0.2, CX, 10.6, 12.6, 81.7, 82, C.metal, M.metal)
	box(m, "HotelCanopyFascia", h.x2 + 0.2, CX, 10.6, 12.6, 98, 98.3, C.metal, M.metal)
	box(m, "HotelCanopyGlow", CX + 0.3, CX + 0.36, 10.6, 10.75, 81.7, 98.3, C.lightWarm, M.neon, DETAIL)
	box(m, "HotelCanopyGlow", h.x2 + 0.2, CX + 0.3, 10.6, 10.75, 81.64, 81.7, C.lightWarm, M.neon, DETAIL)
	for _, z in { 85, 90, 95 } do
		local lamp = box(m, "HotelCanopyLight", h.x2 + 3.6, h.x2 + 4.4, 10.95, 11.0, z - 0.4, z + 0.4, C.lightWarm, M.neon, DETAIL)
		if lamp and z == 90 then
			Kit.light(lamp, "spot", C.lightWarm, 16, 1.1, Enum.NormalId.Bottom)
		end
	end
	-- blade sign on the south-east corner pier (east face x -96.4, z 76..79) over the edge of the WestPath:
	-- dark panel with the house name on both faces (self-lit) and a warm neon outer edge. It hangs low on
	-- purpose: the colonnade soffit (y 10.8, to z 72.6) leaves only y < ~11.5 at z 78 in view from the
	-- colonnade and the plaza (y < ~10.9 from the far plaza), so a sign higher up is hidden from both; the
	-- bottom (7.8) stays above head height (the lane test checks y < 7.5).
	local blade = box(m, "BladeSign", h.x2 + 1.6, h.x2 + 6.0, 7.8, 11.0, 77.85, 78.15, C.metal, M.metal, DETAIL)
	if blade then
		Kit.text(blade, "GUEST\nHOUSE", { face = Enum.NormalId.Front, color = C.lightWarm, light = 0, font = Enum.Font.BuilderSansBold, maxDistance = 220, pad = 0.08, name = "GuestHouseSign" })
		Kit.text(blade, "GUEST\nHOUSE", { face = Enum.NormalId.Back, color = C.lightWarm, light = 0, font = Enum.Font.BuilderSansBold, maxDistance = 220, pad = 0.08, name = "GuestHouseSign", guiName = "SurfaceGuiBack" })
	end
	box(m, "BladeSignGlow", h.x2 + 6.0, h.x2 + 6.15, 7.8, 11.0, 77.8, 78.2, C.lightWarm, M.neon, DETAIL)
	for _, z in { 83, 97 } do
		local p1, p2 = V3(CX - 0.4, 12.2, z), V3(h.x2 + 0.4, 21.5, z)
		local mid = (p1 + p2) / 2
		Kit.cylinder(m, B, "TensionRod", "z", (p2 - p1).Magnitude, 0.16, CFrame.lookAt(mid, p2), C.metalSoft, M.metal, DETAIL)
	end
	-- name band of the house on the east facade between the storeys
	local band = box(m, "HouseNameBand", h.x2 + 2.2, h.x2 + 2.4, 15.2, 16.4, 108, 136, C.metal, M.metal)
	if band then
		Kit.text(band, string.upper(ctx.company) .. "  ·  GUEST HOUSE", { face = Enum.NormalId.Right, color = C.brass, light = 0, font = Enum.Font.BuilderSansBold, maxDistance = 180, pad = 0.1 })
	end
	-- the house name on the parapets: built letters standing on the coping in front of the roof rail in
	-- warm neon (self-lit at night, no Light objects), on the south side over a dark band with the company
	-- name. South: seen over the Campus Arcade from the plaza and the street; west: the district. The
	-- west letters stay inside the site edge (depth <= 1.0) and clear of the rail cap (0.3..0.7). A dark
	-- metal backing plate between the letters and the rail cap (depth `plate`..`plate` + 0.08) hides the
	-- letters' neon backs: the HQ's west floors and the garden see a plain dark panel, not mirrored text.
	local function parapetSign(f: Face, a: number, height: number, d1: number, d2: number, plate: number, company: boolean)
		local outward = if f.axis == "x" then V3(0, 0, f.out) else V3(f.out, 0, 0)
		local base = if f.axis == "x" then V3(a, 33.2, f.c + f.out * d1) else V3(f.c + f.out * d1, 33.2, a)
		HotelKit.letters(f.model, B, "GUEST HOUSE", CFrame.lookAt(base, base - outward), height, d2 - d1, C.lightWarm, M.neon)
		local w = HotelKit.lettersWidth("GUEST HOUSE", height)
		fpart(f, "SignBacking", a - w / 2 - 0.2, a + w / 2 + 0.2, 33.2, 33.2 + height + 0.25, plate, plate + 0.08, C.metal, M.metal, DETAIL)
		if company then
			local band = fpart(f, "ParapetNameBand", a - w / 2, a + w / 2, 30.9, 32.5, depthOf(f), depthOf(f) + 0.06, C.metal, M.metal, DETAIL)
			if band then
				local face = if f.axis == "x" then (if f.out < 0 then Enum.NormalId.Front else Enum.NormalId.Back) else (if f.out < 0 then Enum.NormalId.Left else Enum.NormalId.Right)
				Kit.text(band, string.upper(ctx.company), { face = face, color = C.brass, light = 0, font = Enum.Font.BuilderSansBold, maxDistance = 400, pad = 0.12, guiName = "Sign" })
			end
		end
	end
	parapetSign(south, -119.2, 4.0, 0.85, 1.3, 0.76, true)
	parapetSign(west, 124, 4.6, 0.8, 0.98, 0.71, false)
	-- west facade (rooms facing the district path): a window box under every room window, on the base
	-- course under the ground floor (front office, rooms 101-104) and standing on the cornice under the
	-- first floor (rooms 201-205), where it shows from the path: dark oak box, a row of flowers standing on
	-- its front edge (above the box top, so the path below sees them) and green foliage behind and above
	-- them. Everything stays between the glass (depth 0.2) and the site edge (depth 1.0).
	local wpiers = piers[west]
	local blooms = { C.statusBad, C.statusBusy, C.terracotta }
	for i = 1, #wpiers do
		local b1 = wpiers[i] + 1.2
		local b2 = (if i < #wpiers then wpiers[i + 1] else h.z2 - 3) - 1.2
		local zc, bloom = (b1 + b2) / 2, blooms[i % #blooms + 1]
		fsolid(west, "FlowerBox", b1, b2, 0.9, 1.9, 0.25, 0.95, C.stoneDeep, M.stone, DETAIL)
		Kit.cylinder(west.model, B, "FlowerHedge", "z", b2 - b1 - 0.4, 0.7, CF(h.x1 - 0.6, 2.05, zc), if i % 2 == 0 then C.foliage else bloom, if i % 2 == 0 then M.leafy else M.fabric, DETAIL)
		fsolid(west, "WindowBox", b1, b2, 16.6, 17.6, 0.25, 0.95, C.oakDark, M.wood, DETAIL)
		Kit.cylinder(west.model, B, "WindowBoxGreen", "z", b2 - b1 - 0.3, 0.66, CF(h.x1 - 0.55, 17.95, zc), C.foliage, M.leafy, DETAIL)
		Kit.cylinder(west.model, B, "WindowBoxBloom", "z", b2 - b1 - 0.9, 0.48, CF(h.x1 - 0.75, 17.84, zc), bloom, M.fabric, DETAIL)
	end
	-- the same window boxes round the corner on the north cornice (2.2 deep), under the first-floor rooms
	-- 205 (x -141..-124) and suite 208 (x -116..-98) that look onto the garden
	for i, span in { { -138.8, -125.0 }, { -115.0, -99.6 } } do
		local xc, bloom = (span[1] + span[2]) / 2, blooms[(i + 1) % #blooms + 1]
		fsolid(north, "WindowBox", span[1], span[2], 16.6, 17.6, 0.3, 1.0, C.oakDark, M.wood, DETAIL)
		Kit.cylinder(north.model, B, "WindowBoxGreen", "x", span[2] - span[1] - 0.3, 0.66, CF(xc, 17.95, h.z2 + 0.6), C.foliage, M.leafy, DETAIL)
		Kit.cylinder(north.model, B, "WindowBoxBloom", "x", span[2] - span[1] - 0.9, 0.48, CF(xc, 17.84, h.z2 + 0.8), bloom, M.fabric, DETAIL)
	end
	-- terrace towards the garden (emergency exit of the corridor), benches and planters, a small canopy
	-- with a wall light over the terrace door
	box(grounds, "HotelTerrace", -138, -96, 0, 0.14, h.z2, h.z2 + 9, C.stonePave, M.pave)
	local seed = Kit.hash("guesthouse")
	for k, x in { -130, -106 } do
		Kit.bench(grounds, B, Kit.place(x, 0.14, h.z2 + 6.6, "N"), 6, seed + k)
		Kit.planter(grounds, B, Kit.place(x + 6.5, 0.14, h.z2 + 6.6, 0), 3, 2.4, seed + 10 + k)
	end
	box(north.model, "TerraceCanopy", -123.5, -116.5, 10.8, 11.3, h.z2 + 0.25, h.z2 + 4.0, C.metal, M.metal)
	box(north.model, "TerraceCanopySoffit", -123.3, -116.7, 10.65, 10.8, h.z2 + 0.25, h.z2 + 3.8, C.oak, M.wood, DETAIL)
	for _, x in { -123.9, -116.1 } do
		box(north.model, "TerraceWallLight", x - 0.25, x + 0.25, 7.6, 8.6, h.z2 + 0.45, h.z2 + 0.75, C.lightWarm, M.neon, DETAIL)
	end
	-- the approach from the colonnade: stone forecourt in front of the entrance across the WestPath, bay
	-- trees beside the door, shrubs in the planting bed, three lamp posts in the bed (real lights; the
	-- guest house itself keeps its 16), a hanging sign in the colonnade pointing the way
	-- (overlays stepped by >= 0.05 so they do not flicker at distance: path 0.12, forecourt 0.18, runner 0.23)
	box(grounds, "EntranceForecourt", -96, -88, 0.12, 0.18, 80, 100, C.stone, M.stone, DETAIL)
	for k, z in { 83.2, 96.8 } do
		box(grounds, "BayTreePot", -96.95, -95.75, 0.14, 1.6, z - 0.6, z + 0.6, C.metal, M.metal)
		Kit.cylinder(grounds, B, "BayTreeStem", "y", 2.4, 0.2, CF(-96.35, 2.8, z), C.oakDark, M.wood, DETAIL)
		Kit.ball(grounds, B, "BayTreeCrown", 2.0 + k * 0.1, CF(-96.35, 4.7, z), C.foliage, M.leafy, DETAIL)
	end
	-- a terracotta runner from the forecourt to the door, brass wall lanterns on both door jambs
	box(grounds, "EntranceRunner", h.x2, CX - 0.5, 0.14, 0.23, 87.5, 92.5, C.terracotta, M.fabric, DETAIL)
	for _, z in { 85.7, 94.3 } do
		box(m, "EntranceLanternPlate", h.x2 + 1.5, h.x2 + 1.6, 6.3, 7.8, z - 0.22, z + 0.22, C.brass, M.metal, DETAIL)
		box(m, "EntranceLantern", h.x2 + 1.6, h.x2 + 2.05, 6.6, 7.5, z - 0.22, z + 0.22, C.lightWarm, M.neon, DETAIL)
	end
	-- shrubs on the bed's centre line (x -88.0..-85.0 at most): clear of the path lane and of the HQ's
	-- corner pier (x -84.5) and pavilion glazing (x -83.9)
	for k, z in { 78, 84, 99.5, 112, 118 } do
		Kit.ball(grounds, B, "BedShrub", Kit.range(seed, 40 + k, 2.2, 3.0), CF(-86.5, 1.0, z), if k % 2 == 0 then C.foliage else C.foliageLight, M.leafy, DETAIL)
	end
	local lamps = Kit.model(ctx.folders.Site, "WestPathLights")
	for _, z in { 74, 90, 106 } do
		local lx = -85.5
		Kit.cylinder(lamps, B, "LampPostBase", "y", 0.5, 0.9, CF(lx, 0.4, z), C.metal, M.metal)
		Kit.cylinder(lamps, B, "LampPost", "y", 8.6, 0.32, CF(lx, 0.65 + 4.3, z), C.metal, M.metal)
		local glow = box(lamps, "LampGlow", lx - 0.4, lx + 0.4, 8.95, 9.75, z - 0.4, z + 0.4, C.lightWarm, M.neon, DETAIL)
		if glow then
			Kit.light(glow, "point", C.lightWarm, 18, 0.85)
		end
	end
	-- the colonnade sign hangs in the east half of the colonnade, off the sightline from the colonnade and
	-- the plaza to the blade sign (rays from the walkway towards the corner pier pass west of x -92)
	local hang = box(grounds, "ColonnadeHangingSign", -91.8, -86.6, 9.0, 10.4, 57.9, 58.1, C.metal, M.metal, DETAIL)
	if hang then
		Kit.text(hang, "GUEST HOUSE  ↑", { face = Enum.NormalId.Front, color = C.lightWarm, light = 0, maxDistance = 120, pad = 0.14, name = "GuestHouseWay" })
		Kit.text(hang, "PLAZA  ·  CAMPUS STORES  ↑", { face = Enum.NormalId.Back, color = C.white, light = 0, maxDistance = 120, pad = 0.14, guiName = "SurfaceGuiBack" })
	end
	for _, x in { -91.0, -87.4 } do
		box(grounds, "HangingSignRod", x - 0.06, x + 0.06, 10.4, 10.8, 57.94, 58.06, C.metal, M.metal, DETAIL)
	end
	-- entrance camera tucked against the facade under the canopy soffit (mount on the soffit's underside)
	Kit.camera(ctx.folders.Cameras, B, "EXT_HOTEL", "Guest house entrance", V3(h.x2 + 0.8, 10.0, 97.2), V3(-95, 2, 84), 0, "H0_LOBBY", false)
end

---------------------------------------------------------------------------------------------
-- Garage stage (plan tier 0): the company starts in a converted garage beside the plaza. The future
-- HQ footprint is a fenced construction site (gravel, footings, crane, excavator, site cabins, a site
-- board), the plaza, Campus Arcade, garden and service yard stay. No B1, no ramp: the ramp strip is
-- lawn and the driveway leads to the garage's up-and-over door, where the company car is parked.
---------------------------------------------------------------------------------------------
local function garageFootprint(): Rect
	local g = Plan.GARAGE_LAB
	return { x1 = g.x1 - 1, x2 = g.x2 + 1, z1 = g.z1 - 1, z2 = g.z2 + 1 }
end

local function stageGround(ctx: any)
	local s = Plan.SITE
	local foot = garageFootprint()
	local fnd = Kit.model(ctx.folders.Site, "Foundations")
	for _, piece in subtract({ x1 = s.x1, x2 = s.x2, z1 = s.z1, z2 = s.z2 }, { foot }) do
		box(fnd, "Foundation", piece.x1, piece.x2, -26, 0, piece.z1, piece.z2, C.concrete, M.concrete)
	end
	box(fnd, "Foundation", foot.x1, foot.x2, -26, -1, foot.z1, foot.z2, C.concrete, M.concrete)
	-- the garage's ground slab (Layout.slabs, tier 0)
	local slabs = Kit.model(ctx.folders.Structure, "Slabs")
	local rects = Layout.slabs(ctx.tier, 0)
	for _, r in rects do
		box(slabs, "Slab", r.x1, r.x2, -1, 0, r.z1, r.z2, C.concrete, M.concrete)
	end

	local srf = Kit.model(ctx.folders.Site, "Surfaces")
	local cons = Plan.CONSTRUCTION
	-- one lawn layer (0.1) under everything that is not building, site, arcade, garden or yard; paths,
	-- plaza (0.12) and asphalt (0.11) lie on top of it
	for _, piece in subtract({ x1 = s.x1, x2 = s.x2, z1 = s.z1, z2 = s.z2 }, {
		foot,
		{ x1 = cons.x1, x2 = cons.x2, z1 = cons.z1, z2 = cons.z2 },
		{ x1 = -142, x2 = -96, z1 = -56.6, z2 = 72.6 }, -- Campus Arcade
		{ x1 = -96, x2 = 86, z1 = 160, z2 = s.z2 }, -- rear garden (own lawn)
		{ x1 = 82, x2 = s.x2, z1 = 40, z2 = s.z2 }, -- service yard (own surfaces)
	}) do
		box(srf, "Lawn", piece.x1, piece.x2, 0, 0.1, piece.z1, piece.z2, C.grass, M.grass)
	end
	local function pave(name: string, x1: number, x2: number, z1: number, z2: number, color: Color3?, mat: Enum.Material?)
		box(srf, name, x1, x2, 0, 0.12, z1, z2, color or C.stonePave, mat or M.pave)
	end
	local function asphalt(name: string, x1: number, x2: number, z1: number, z2: number)
		box(srf, name, x1, x2, 0, 0.11, z1, z2, C.asphalt, M.asphalt)
	end
	local g = Plan.GARAGE_LAB
	pave("ArrivalWalk", -12, 12, s.z1, -120, C.stone, M.stone)
	pave("Plaza", -96, foot.x1, -120, -48)
	pave("Plaza", -82, 82, -48, cons.z1)
	pave("Plaza", foot.x1, foot.x2, foot.z2, -48)
	pave("PorchPaving", 64, 92, -127.5, foot.z1)
	pave("VisitorPath", 74, 80, -150, -127.5)
	asphalt("Driveway", 92, 112, s.z1, foot.z1)
	asphalt("VisitorParking", 70, 92, -200, -150)
	pave("ColonnadeFloor", -96, -82, -48, 72, C.stone, M.stone)
	pave("WestPath", -96, -88, 72, 184)
	box(srf, "PlantingBed", -88, -82, 0, 0.15, 72, 160, C.soil, M.leafy)
	pave("EastPath", 82, 92, -48, 40)
	box(srf, "PlantingBed", 82, 86, 0, 0.15, 89, 160, C.soil, M.leafy)
	local _ = g

	-- plaza furniture (the HQ entrance planters flank the site hoarding now)
	local pz = Kit.model(ctx.folders.Site, "Plaza")
	for z = s.z1 + 6, -126, 6 do
		box(pz, "PavingJoint", -12, 12, 0.12, 0.17, z - 0.06, z + 0.06, C.stoneDeep, M.stone, DETAIL)
	end
	for x = -84, 48, 12 do
		box(pz, "PavingJoint", x - 0.06, x + 0.06, 0.12, 0.17, -120, -48, C.stoneDeep, M.pave, DETAIL)
	end
	for z = -108, -60, 12 do
		box(pz, "PavingJoint", -96, foot.x1, 0.12, 0.17, z - 0.06, z + 0.06, C.stoneDeep, M.pave, DETAIL)
	end
	for k, x in { -40, 40 } do
		Kit.planter(pz, B, Kit.place(x, 0.12, -52, 0), 12, 2.4, Kit.hash("entry") + k)
	end
	local seed = Kit.hash("plaza")
	island(pz, -68, -52, -108, -96, seed + 1)
	island(pz, -46, -34, -86, -76, seed + 3)
	island(pz, 34, 46, -86, -76, seed + 4)
	Kit.bench(pz, B, Kit.place(-60, 0.12, -95, "N"), 6, seed + 11)
	Kit.bench(pz, B, Kit.place(-40, 0.12, -87, "S"), 6, seed + 13)
	Kit.bench(pz, B, Kit.place(40, 0.12, -87, "S"), 6, seed + 14)
	for i, z in { -206, -188, -170, -152, -134 } do
		for _, x in { -13.6, 13.6 } do
			bollard(pz, x, z, i % 2 == 1)
		end
	end
	box(pz, "BikeRackRail", 22, 36, 0.12, 0.3, -116.2, -115.8, C.metal, M.metal)
	for x = 23, 35, 3 do
		for _, dz in { -0.9, 0.9 } do
			box(pz, "BikeHoop", x - 0.08, x + 0.08, 0.3, 2.6, -116 + dz - 0.08, -116 + dz + 0.08, C.metal, M.metal, DETAIL)
		end
		box(pz, "BikeHoop", x - 0.08, x + 0.08, 2.6, 2.76, -116.98, -115.02, C.metal, M.metal, DETAIL)
	end
	box(pz, "SteleBase", -22.4, -17.6, 0.1, 0.5, -125.4, -122.6, C.stoneDeep, M.stone)
	local stele = box(pz, "CompanyStele", -21.6, -18.4, 0.5, 12.5, -124.6, -123.4, C.stone, M.stone)
	if stele then
		local plate = Kit.part(stele, B, "StelePlate", V3(2.6, 6.5, 0.12), CF(-20, 8.6, -124.66), C.metal, M.metal, { castShadow = false })
		Kit.text(plate, ctx.company, { color = C.white, font = Enum.Font.BuilderSansBold, maxDistance = 120, pps = 60, pad = 0.08 })
		box(pz, "SteleAccent", -21.3, -18.7, 12.0, 12.2, -124.68, -124.6, ctx.accent, M.smooth, DETAIL)
	end
	for z = -196, -156, 10 do
		box(pz, "BayLine", 72, 90, 0.1, 0.15, z - 0.12, z + 0.12, C.white, M.smooth, DETAIL)
	end
	box(pz, "BayLine", 72, 72.25, 0.1, 0.15, -196, -156, C.white, M.smooth, DETAIL)
	for z = -191, -161, 10 do
		box(pz, "WheelStop", 73, 74, 0.1, 0.4, z - 3, z + 3, C.stoneDeep, M.concrete)
	end
	-- trees (same seeds as the HQ site) and the two planting islands on the east green strip
	local land = Kit.model(ctx.folders.Site, "Landscape")
	local ts = Kit.hash("trees")
	local i = 0
	local function t(x: number, z: number)
		i += 1
		tree(land, x, z, ts + i * 17)
	end
	for _, x in { -132, -110, -88, -66, -44, -24, 24, 46, 128 } do
		t(x, -205)
		box(land, "TreeGrate", x - 2, x + 2, 0.1, 0.16, -207, -203, C.metal, M.metal, DETAIL)
	end
	for _, p in { { -38, -150 }, { -64, -172 }, { -96, -150 }, { -124, -176 }, { 36, -146 }, { 56, -172 }, { -124, -104 }, { -110, -76 },
		{ 128, -126 }, { 130, -96 }, { 126, -60 }, { 130, -24 }, { 128, 12 }, { -124, 92 }, { -112, 124 }, { -128, 150 } } do
		t(p[1], p[2])
	end
	island(land, 96, 108, -32, -22, ts + 101)
	island(land, 96, 108, 4, 14, ts + 102)
end

-- The startup's company van, parked in front of the garage beside the company-car spot (static scenery:
-- anchored, only the body collides; the drivable car comes from VehicleService at GarageSpawn).
-- `at` = ground point under the van's centre, nose along its LookVector (towards the street).
local function companyVan(ctx: any, parent: Instance, at: CFrame)
	local m = Kit.model(parent, "CompanyVan", true)
	local L, W = 15, 7.4
	local function part(name: string, size: Vector3, offset: CFrame, color: Color3, mat: Enum.Material, opts: Opts?): Part
		return Kit.part(m, B, name, size, at * offset, color, mat, opts)
	end
	part("VanChassis", V3(W - 0.6, 1.0, L - 0.6), CF(0, 1.5, 0), C.metal, M.metal)
	part("VanBody", V3(W, 3.0, L - 0.4), CF(0, 3.5, 0), C.white, M.smooth)
	part("VanCargo", V3(W, 3.6, 9.6), CF(0, 6.8, 2.5), C.white, M.smooth)
	part("VanCab", V3(W - 0.3, 2.4, 3.6), CF(0, 6.2, -4.3), C.white, M.smooth)
	part("VanWindscreen", V3(W - 0.9, 2.6, 0.15), CF(0, 6.1, -6.25) * ANG(math.rad(-22), 0, 0), C.glassDeep, M.glass, { detail = true, transparency = 0.2 })
	for _, s in { -1, 1 } do
		part("VanSideWindow", V3(0.1, 1.7, 2.6), CF(s * (W / 2 - 0.1), 6.3, -4.4), C.glassDeep, M.glass, { detail = true, transparency = 0.2 })
		part("VanStripe", V3(0.06, 0.5, L - 1.2), CF(s * (W / 2 + 0.03), 4.1, 0), ctx.accent, M.smooth, DETAIL)
		local panel = part("VanLivery", V3(0.06, 2.2, 7.8), CF(s * (W / 2 + 0.03), 6.9, 2.6), ctx.accent, M.smooth, DETAIL)
		Kit.text(panel, ctx.company, { face = if s > 0 then Enum.NormalId.Right else Enum.NormalId.Left, color = C.white, font = Enum.Font.BuilderSansBold, maxDistance = 90, pad = 0.12 })
		part("VanMirror", V3(0.3, 0.7, 0.5), CF(s * (W / 2 + 0.25), 5.6, -5.6), C.metal, M.metal, DETAIL)
		part("VanHeadlight", V3(1.3, 0.55, 0.08), CF(s * 2.4, 4.0, -(L - 0.4) / 2 - 0.04), C.lightWarm, M.neon, DETAIL)
		part("VanTaillight", V3(0.9, 0.9, 0.08), CF(s * 2.9, 4.0, (L - 0.4) / 2 + 0.04), C.statusBad, M.neon, DETAIL)
		for _, z in { -4.8, 4.8 } do
			Kit.cylinder(m, B, "VanWheel", "x", 1.0, 2.6, at * CF(s * (W / 2 - 0.55), 1.3, z), C.screen, M.metal, DETAIL)
		end
	end
	part("VanBumper", V3(W, 0.7, 0.4), CF(0, 1.9, -(L - 0.4) / 2 - 0.2), C.metal, M.metal, DETAIL)
	part("VanBumper", V3(W, 0.7, 0.4), CF(0, 1.9, (L - 0.4) / 2 + 0.2), C.metal, M.metal, DETAIL)
	return m
end

-- Up-and-over garage door (CampusDoor contract, SPEC §3): Leaf1 lifts and tilts under the ceiling
-- (DoorService lerps ClosedPivot -> OpenPivot); prompts on both sides, staff access.
local function rollupDoor(ctx: any, m: Model)
	local r = Plan.GARAGE_ROLLUP
	local cx, z, H = (r.x1 + r.x2) / 2, r.z, r.height
	local W = r.x2 - r.x1
	local door = Instance.new("Model")
	door.Name = "Door_G0_ROLLUP"
	door.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local frame = Kit.model(door, "Frame")
	box(frame, "JambL", r.x1 - 0.5, r.x1, 0, H + 0.5, z - 1, z, C.metal, M.metal)
	box(frame, "JambR", r.x2, r.x2 + 0.5, 0, H + 0.5, z - 1, z, C.metal, M.metal)
	box(frame, "Head", r.x1, r.x2, H, H + 0.5, z - 1, z, C.metal, M.metal)
	for _, x in { r.x1 + 0.3, r.x2 - 0.3 } do -- ceiling tracks the panel runs into
		box(frame, "DoorTrack", x - 0.12, x + 0.12, H + 0.1, H + 0.35, z, z + 10.6, C.metalSoft, M.metal, DETAIL)
	end
	local leaf = Instance.new("Model")
	leaf.Name = "Leaf1"
	leaf.Parent = door
	local closed = B * CF(cx, 0, z - 0.55)
	local open = B * CF(cx, H + 0.45, z - 0.2) * ANG(PI / 2, 0, 0)
	leaf.WorldPivot = closed
	leaf:SetAttribute("ClosedPivot", closed)
	leaf:SetAttribute("OpenPivot", open)
	leaf:SetAttribute("Motion", "tilt")
	local local0 = CF(cx, 0, z - 0.55)
	Kit.part(leaf, B, "DoorPanel", V3(W - 0.1, H - 0.1, 0.25), local0 * CF(0, H / 2, 0), C.metalSoft, M.metal)
	for k = 1, 4 do
		Kit.part(leaf, B, "DoorRib", V3(W - 0.4, 0.14, 0.08), local0 * CF(0, k * H / 5, -0.16), C.metal, M.metal, DETAIL)
	end
	Kit.part(leaf, B, "DoorHandle", V3(1.4, 0.2, 0.2), local0 * CF(0, 1.1, -0.25), C.metal, M.metal, DETAIL)
	local function anchor(name: string, dz: number): Part
		return Kit.part(door, B, name, V3(0.4, 0.4, 0.4), CF(r.x2 - 1.5, 3.6, z + dz), C.white, nil, { detail = true, transparency = 1 })
	end
	for _, side in { "out", "in" } do
		local p = anchor(if side == "out" then "PromptOut" else "PromptIn", if side == "out" then -1.8 else 1.2)
		Kit.action(p, "door", "Garage door", "G0_ROLLUP", { actionText = "Open", maxDistance = 10, attributes = { Side = side } })
	end
	Kit.part(door, B, "Sensor", V3(W, H, 3.2), CF(cx, H / 2, z - 0.5), C.white, nil, { detail = true, transparency = 1 })
	door:SetAttribute("DoorId", "G0_ROLLUP")
	door:SetAttribute("DoorKind", "gate")
	door:SetAttribute("AccessClass", "staff")
	door:SetAttribute("RoomId", "G0_LAB")
	door:SetAttribute("DoorOwner", ctx.owner)
	door:SetAttribute("SecureNormal", B:VectorToWorldSpace(V3(0, 0, 1)))
	door:SetAttribute("AutoOpen", false)
	door:SetAttribute("HoldOpen", 8)
	door:SetAttribute("Hidden", false)
	door:SetAttribute("Exterior", true)
	door:SetAttribute("DoorState", "closed")
	CollectionService:AddTag(door, "CampusDoor")
	door.Parent = ctx.folders.Doors
	local _ = m
end

-- The converted garage: white-washed block walls on a stone plinth, a dark metal fascia, an oak-clad
-- entrance under a porch canopy, windows, a flat roof with skylights and plant, the company sign over
-- the garage door, the company car's parking spot with a key box.
local function stageGarage(ctx: any)
	local g = Plan.GARAGE_LAB
	local folder: Instance = ctx.folders.Facade
	local H = g.height -- roof slab 13..14, parapet to 15
	local south = newFace("gsouth", Kit.model(folder, "Facade_GarageSouth"), "x", g.z1, -1)
	local north = newFace("gnorth", Kit.model(folder, "Facade_GarageNorth"), "x", g.z2, 1)
	local west = newFace("gwest", Kit.model(folder, "Facade_GarageWest"), "z", g.x1, -1)
	local east = newFace("geast", Kit.model(folder, "Facade_GarageEast"), "z", g.x2, 1)
	local faces = { south, north, west, east }
	-- openings in (a, y): plan exterior door(s), the garage door, windows
	local doors = {}
	for _, d in Layout.doors(ctx.tier) do
		if d.builder == "exterior" then
			local da = if d.axis == "x" then d.x else d.z
			local dc = if d.axis == "x" then d.z else d.x
			for _, f in faces do
				if f.axis == d.axis and math.abs(f.c - dc) < 0.01 then
					table.insert(f.holes, { x1 = da - d.w / 2 - 0.4, x2 = da + d.w / 2 + 0.4, z1 = 0, z2 = d.h + 0.4 })
					table.insert(doors, { def = d, face = f, a = da })
					break
				end
			end
		end
	end
	local r = Plan.GARAGE_ROLLUP
	table.insert(south.holes, { x1 = r.x1 - 0.5, x2 = r.x2 + 0.5, z1 = 0, z2 = r.height + 0.5 })
	type Win = { f: Face, a1: number, a2: number, y1: number, y2: number }
	local windows: { Win } = {
		{ f = south, a1 = 62, a2 = 71.5, y1 = 3.4, y2 = 10 },
		{ f = south, a1 = 82.5, a2 = 91, y1 = 3.4, y2 = 10 },
		{ f = west, a1 = -116, a2 = -105, y1 = 3.4, y2 = 10 },
		{ f = west, a1 = -86.5, a2 = -82.5, y1 = 8.6, y2 = 11.4 },
		{ f = north, a1 = 70, a2 = 96, y1 = 9, y2 = 12.2 },
		{ f = north, a1 = 100, a2 = 110.5, y1 = 3.2, y2 = 11 },
		{ f = east, a1 = -92, a2 = -80, y1 = 3.2, y2 = 11 },
		{ f = east, a1 = -107, a2 = -97, y1 = 7.6, y2 = 11.6 },
	}
	for _, w in windows do
		table.insert(w.f.holes, { x1 = w.a1, x2 = w.a2, z1 = w.y1, z2 = w.y2 })
	end
	local spans: { [Face]: { number } } = {
		[south] = { g.x1 - 1, g.x2 + 1 },
		[north] = { g.x1 - 1, g.x2 + 1 },
		[west] = { g.z1, g.z2 },
		[east] = { g.z1, g.z2 },
	}
	for _, f in faces do
		local a1, a2 = spans[f][1], spans[f][2]
		fsolid(f, "Plinth", a1, a2, 0, 1.0, 0, 1.15, C.stoneDeep, M.stone)
		fsolid(f, "GarageWall", a1, a2, 1.0, 12.2, 0, 1, C.white, M.plaster)
		fsolid(f, "Fascia", a1, a2, 12.2, H + 1, 0, 1.1, C.metalSoft, M.metal)
		fsolid(f, "Coping", a1, a2, H + 1, H + 1.2, -0.1, 1.2, C.metal, M.metal)
	end
	for _, w in windows do
		local f = w.f
		fpart(f, "WindowGlass", w.a1, w.a2, w.y1, w.y2, 0.45, 0.6, C.glass, M.glass, GLASS)
		fpart(f, "WindowSill", w.a1 - 0.2, w.a2 + 0.2, w.y1 - 0.25, w.y1, 0, 1.3, C.stone, M.stone)
		fpart(f, "WindowHead", w.a1, w.a2, w.y2, w.y2 + 0.2, 0.9, 1.05, C.metal, M.metal, DETAIL)
		if w.a2 - w.a1 > 6 then
			local n = math.floor((w.a2 - w.a1) / 4)
			for k = 1, n - 1 do
				local a = w.a1 + k * (w.a2 - w.a1) / n
				fpart(f, "WindowMullion", a - 0.08, a + 0.08, w.y1, w.y2, 0.35, 0.7, C.metal, M.metal, DETAIL)
			end
		end
	end
	-- oak-clad entrance bay and the pedestrian door (plan door G0_LAB_D1)
	for _, entry in doors do
		local d, f = entry.def, entry.face
		fsolid(f, "EntranceCladding", entry.a - d.w / 2 - 2.6, entry.a + d.w / 2 + 2.6, 1.0, 12.2, 1.0, 1.2, C.oak, M.wood)
		local def: any = table.clone(d)
		if d.axis == "x" then
			def.z = f.c + f.out * 0.5
		else
			def.x = f.c + f.out * 0.5
		end
		def.thickness = 1.0
		Kit.door(ctx.folders.Doors, B, def, ctx.owner)
	end
	rollupDoor(ctx, south.model)
	-- flat roof (interior rectangle; the walls rise to the parapet around it)
	local roof = Kit.model(ctx.folders.Structure, "GarageRoof")
	box(roof, "RoofSlab", g.x1, g.x2, H - 1, H, g.z1, g.z2, C.concrete, M.concrete)
	box(roof, "RoofMembrane", g.x1, g.x2, H, H + 0.08, g.z1, g.z2, C.metalSoft, M.slate)
	for _, x in { 76, 90 } do
		box(roof, "SkylightCurb", x - 3.4, x + 3.4, H + 0.08, H + 0.7, -101.4, -94.6, C.metal, M.metal)
		box(roof, "SkylightGlass", x - 3, x + 3, H + 0.7, H + 0.85, -101, -95, C.glass, M.glass, GLASS)
	end
	box(roof, "RoofUnit", 100, 106, H + 0.08, H + 2.6, -90, -85, C.metalSoft, M.metal)
	Kit.cylinder(roof, B, "RoofFan", "y", 0.2, 3, CF(103, H + 2.7, -87.5), C.metal, M.metal, DETAIL)
	Kit.cylinder(roof, B, "VentPipe", "y", 2.4, 0.6, CF(64, H + 1.28, -82), C.metal, M.metal, DETAIL)
	for k = 0, 2 do -- a small solar array: the startup's first green power
		local x = 66 + k * 6.5
		Kit.part(roof, B, "SolarPanel", V3(6, 0.15, 4), CF(x, H + 1.1, -110) * ANG(math.rad(18), 0, 0), C.blue, M.glass, { canCollide = false, castShadow = false })
		box(roof, "SolarStand", x - 2.6, x - 2.4, H + 0.08, H + 1.2, -110.4, -109.6, C.metal, M.metal, DETAIL)
		box(roof, "SolarStand", x + 2.4, x + 2.6, H + 0.08, H + 1.2, -110.4, -109.6, C.metal, M.metal, DETAIL)
	end
	-- porch canopy over the entrance (applicants wait on the porch benches, RoomKitsGarage)
	local m = south.model
	box(m, "PorchCanopy", 65.5, 90.5, 9.6, 10.2, -126.6, g.z1 - 1, C.metal, M.metal)
	box(m, "PorchSoffit", 65.8, 90.2, 9.4, 9.6, -126.3, g.z1 - 1, C.oak, M.wood)
	for _, x in { 66.4, 89.6 } do
		box(m, "PorchPost", x - 0.25, x + 0.25, 0.12, 9.4, -126.25, -125.75, C.metal, M.metal)
	end
	local lamp = box(m, "PorchLight", 76.4, 77.6, 9.35, 9.4, -123.4, -122.6, C.lightWarm, M.neon, DETAIL)
	if lamp then
		Kit.light(lamp, "spot", C.lightWarm, 14, 0.9, Enum.NormalId.Bottom)
	end
	local plate = box(m, "HousePlate", 80.6, 82.4, 6.6, 7.6, g.z1 - 1.28, g.z1 - 1.2, C.metal, M.metal, DETAIL)
	if plate then
		Kit.text(plate, "GARAGE LAB\nNo. 1", { face = Enum.NormalId.Front, color = C.white, font = Enum.Font.BuilderSansBold, maxDistance = 40, pad = 0.08 })
	end
	-- company sign over the garage door (direct child of the office: PlotService writes the name)
	local sign = Kit.part(ctx.office, B, "SignAnchor", V3(15, 2.4, 0.3), CF((r.x1 + r.x2) / 2, 12.4, g.z1 - 1.3), C.metal, M.metal, { canCollide = false, castShadow = false })
	Kit.text(sign, ctx.company, { guiName = "Sign", name = "Label", font = Enum.Font.BuilderSansExtraBold, maxDistance = 220, color = C.white, light = 0.2, pps = 40, pad = 0.1 })
	box(m, "SignAccent", r.x1 + 0.5, r.x2 - 0.5, 11.05, 11.2, g.z1 - 1.25, g.z1 - 1.1, ctx.accent, M.neon, DETAIL)
	local wash = box(m, "SignWash", 99, 105, 10.75, 10.95, g.z1 - 1.6, g.z1 - 1.1, C.metal, M.metal, DETAIL)
	if wash then
		Kit.light(wash, "spot", C.lightWarm, 10, 0.6, Enum.NormalId.Top)
	end
	-- company car spot in front of the garage door, key box beside it (VehicleService spawns here)
	local site = Kit.model(ctx.folders.Site, "GarageForecourt")
	local spawn = Plan.GARAGE_STAGE_SPAWN
	local marker = Kit.part(site, B, "GarageSpawn", V3(1, 1, 1), spawn, C.white, nil, { detail = true, transparency = 1 })
	marker:SetAttribute("SpawnCFrame", B * spawn)
	marker:SetAttribute("PickupText", "Your car is parked in front of the garage.")
	local sp = spawn.Position
	local vp = Plan.GARAGE_STAGE_VAN.Position -- the van's bay shares the car bay's west line
	for _, e in { { sp.X, sp.Z - 9.3, 9.6, 0.3 }, { sp.X - 4.8, sp.Z, 0.3, 18.9 }, { sp.X + 4.8, sp.Z, 0.3, 18.9 }, { vp.X, vp.Z - 9.3, 9.6, 0.3 }, { vp.X - 4.8, vp.Z, 0.3, 18.9 } } do
		Kit.part(site, B, "ParkingLine", V3(e[3], 0.05, e[4]), CF(e[1], 0.135, e[2]), C.white, M.smooth, DETAIL)
	end
	local key = box(site, "CarCollection", r.x2 + 0.9, r.x2 + 2.3, 3.0, 5.4, g.z1 - 1.6, g.z1 - 1.0, C.metal, M.metal)
	if key then
		key:SetAttribute("OwnerUserId", ctx.owner)
		Kit.text(key, "CAR KEYS", { face = Enum.NormalId.Front, color = C.white, font = Enum.Font.BuilderSansBold, maxDistance = 40, pad = 0.1 })
		Kit.action(key, "spawnCar", "Collect selected car", nil, { ownerUserId = ctx.owner, actionText = "Collect", maxDistance = 10 })
	end
	companyVan(ctx, site, Plan.GARAGE_STAGE_VAN)
	flushVerts()
end

-- Fenced construction site on the future HQ footprint: hoarding with the company line, a gate, a site
-- board, gravel and footing pads, a tower crane, an excavator, stacked site cabins and materials.
local function stageConstruction(ctx: any)
	local c = Plan.CONSTRUCTION
	local m = Kit.model(ctx.folders.Site, "ConstructionSite")
	local seed = Kit.hash("construction")
	box(m, "SiteGravel", c.x1, c.x2, 0, 0.12, c.z1, c.z2, C.stoneDeep, M.slate)
	box(m, "Excavation", -66, 66, 0.12, 0.2, -34, 72, C.soil, M.slate)
	for _, x in { -50, -18, 18, 50 } do
		for _, z in { -20, 20, 60 } do
			box(m, "FootingPad", x - 1.6, x + 1.6, 0.2, 0.7, z - 1.6, z + 1.6, C.concrete, M.concrete)
			box(m, "Rebar", x - 0.5, x + 0.5, 0.7, 3.2, z - 0.5, z + 0.5, C.terracotta, M.metal, DETAIL)
		end
	end
	-- hoarding (8 high) with a gate towards the plaza; thin accent band on top
	local HH = 8
	local function panel(name: string, x1: number, x2: number, z1: number, z2: number)
		box(m, name, x1, x2, 0.12, HH, z1, z2, C.white, M.smooth)
	end
	local gate = { x1 = -8, x2 = 8 }
	panel("Hoarding", c.x1, gate.x1, c.z1, c.z1 + 0.4)
	panel("Hoarding", gate.x2, c.x2, c.z1, c.z1 + 0.4)
	panel("Hoarding", c.x1, c.x2, c.z2 - 0.4, c.z2)
	panel("Hoarding", c.x1, c.x1 + 0.4, c.z1 + 0.4, c.z2 - 0.4)
	panel("Hoarding", c.x2 - 0.4, c.x2, c.z1 + 0.4, c.z2 - 0.4)
	box(m, "HoardingBand", c.x1, c.x2, HH, HH + 0.4, c.z1 - 0.05, c.z1 + 0.45, ctx.accent, M.smooth)
	for x = c.x1 + 12, c.x2 - 12, 24 do
		if x < gate.x1 - 1 or x > gate.x2 + 1 then
			box(m, "HoardingPost", x - 0.3, x + 0.3, 0.12, HH + 0.4, c.z1 - 0.3, c.z1, C.metal, M.metal)
		end
	end
	for _, s in { -1, 1 } do
		local x1, x2 = if s < 0 then gate.x1 else 0.05, if s < 0 then -0.05 else gate.x2
		box(m, "SiteGateLeaf", x1, x2, 0.12, HH - 0.6, c.z1 + 0.05, c.z1 + 0.35, C.metal, M.metal)
		box(m, "SiteGateMesh", x1 + 0.4, x2 - 0.4, 0.8, HH - 1.2, c.z1 - 0.02, c.z1 + 0.05, C.metalSoft, M.metal, { detail = true, transparency = 0.45 })
	end
	local stripe = box(m, "HoardingGraphic", -70, -14, 2.2, 6.6, c.z1 - 0.08, c.z1 - 0.02, C.metal, M.smooth, DETAIL)
	if stripe then
		Kit.text(stripe, "FUTURE HOME OF " .. string.upper(ctx.company), { face = Enum.NormalId.Front, color = C.white, font = Enum.Font.BuilderSansExtraBold, maxDistance = 160, pad = 0.08 })
	end
	-- site board on the plaza side
	for _, x in { 26, 50 } do
		box(m, "SiteBoardPost", x - 0.35, x + 0.35, 0.12, 13, -50.35, -49.65, C.metal, M.metal)
	end
	local board = box(m, "SiteBoard", 25.5, 50.5, 3.4, 12.6, -50.9, -50.4, C.metal, M.metal)
	if board then
		local t = Kit.text(board, "FUTURE HEADQUARTERS", { face = Enum.NormalId.Front, color = C.brass, font = Enum.Font.BuilderSansExtraBold, maxDistance = 160, pad = 0.06, name = "Title" })
		t.Size = UDim2.fromScale(0.88, 0.3)
		local gui = t.Parent :: Instance
		local body = Instance.new("TextLabel")
		body.Name = "Body"
		body.BackgroundTransparency = 1
		body.Position = UDim2.fromScale(0.06, 0.42)
		body.Size = UDim2.fromScale(0.88, 0.48)
		body.Text = ctx.company .. "\nA home for the whole team: offices, labs, café, data hall.\nBuilt with your next office upgrade."
		body.TextScaled = true
		body.TextWrapped = true
		body.TextColor3 = C.white
		body.Font = Enum.Font.BuilderSans
		body.Parent = gui
		local spot = box(m, "SiteBoardLight", 37, 39, 12.6, 12.9, -51.6, -50.9, C.metal, M.metal, DETAIL)
		if spot then
			Kit.light(spot, "spot", C.lightWarm, 14, 0.8, Enum.NormalId.Bottom)
		end
	end
	-- tower crane over the future atrium
	local craneYellow = C.statusBusy
	box(m, "CraneBase", -4, 4, 0.12, 2.2, 36, 44, C.concrete, M.concrete)
	box(m, "CraneMast", -1.3, 1.3, 2.2, 66, 38.7, 41.3, craneYellow, M.metal)
	box(m, "CraneCab", -1.6, 2.4, 63, 66.4, 35.8, 38.7, C.metalSoft, M.metal)
	box(m, "CraneCabGlass", -1.4, 2.2, 64, 66, 35.6, 35.8, C.glass, M.glass, { detail = true, transparency = A.glassTransparency })
	box(m, "CraneJib", -1, 1, 66.4, 68, 41.3, 98, craneYellow, M.metal, DETAIL)
	box(m, "CraneCounterJib", -1, 1, 66.4, 68, 20, 38.7, craneYellow, M.metal, DETAIL)
	box(m, "CraneCounterweight", -1.8, 1.8, 62.5, 66.4, 21, 26, C.concrete, M.concrete, DETAIL)
	box(m, "CraneApex", -0.6, 0.6, 68, 76, 39.4, 40.6, craneYellow, M.metal, DETAIL)
	box(m, "CraneTrolley", -1.2, 1.2, 65.6, 66.4, 74, 77, C.metal, M.metal, DETAIL)
	box(m, "CraneCable", -0.08, 0.08, 30, 65.6, 75.42, 75.58, C.metal, M.metal, DETAIL)
	box(m, "CraneHook", -0.7, 0.7, 28.6, 30, 74.8, 76.2, C.metal, M.metal, DETAIL)
	box(m, "CraneWarningLight", -0.3, 0.3, 76, 76.6, 39.7, 40.3, C.statusBad, M.neon, DETAIL)
	-- excavator
	local ex = Kit.place(-34, 0.2, 6, 30)
	Kit.part(m, B, "ExcavatorTrack", V3(1.6, 1.6, 9), ex * CF(-2.6, 0.8, 0), C.metal, M.metal)
	Kit.part(m, B, "ExcavatorTrack", V3(1.6, 1.6, 9), ex * CF(2.6, 0.8, 0), C.metal, M.metal)
	Kit.part(m, B, "ExcavatorBody", V3(6, 2.6, 6.4), ex * CF(0, 3, 0.6), craneYellow, M.metal)
	Kit.part(m, B, "ExcavatorCab", V3(2.8, 3, 3), ex * CF(-1.4, 5.8, -0.6), craneYellow, M.metal)
	Kit.part(m, B, "ExcavatorGlass", V3(2.6, 2.2, 0.1), ex * CF(-1.4, 6, -2.15), C.glass, M.glass, { detail = true, transparency = A.glassTransparency })
	Kit.part(m, B, "ExcavatorBoom", V3(1.1, 1.3, 9), ex * CF(1.4, 6.2, -5.4) * ANG(math.rad(28), 0, 0), craneYellow, M.metal, DETAIL)
	Kit.part(m, B, "ExcavatorArm", V3(0.9, 1.0, 6), ex * CF(1.4, 6.0, -11.2) * ANG(math.rad(-50), 0, 0), craneYellow, M.metal, DETAIL)
	Kit.part(m, B, "ExcavatorBucket", V3(2.4, 1.6, 1.8), ex * CF(1.4, 2.2, -12.6), C.metal, M.metal, DETAIL)
	-- stacked site cabins near the plaza corner
	for k = 0, 1 do
		local y0 = 0.12 + k * 8.6
		box(m, "SiteCabin", 52, 72, y0, y0 + 8.4, -40, -32, C.white, M.smooth)
		box(m, "SiteCabinWindow", 55, 61, y0 + 3.2, y0 + 6.6, -40.08, -40, C.glass, M.glass, { detail = true, transparency = A.glassTransparency })
		box(m, "SiteCabinWindow", 64, 70, y0 + 3.2, y0 + 6.6, -40.08, -40, C.glass, M.glass, { detail = true, transparency = A.glassTransparency })
		box(m, "SiteCabinFrame", 52, 72, y0 + 8.2, y0 + 8.6, -40.1, -31.9, C.metalSoft, M.metal, DETAIL)
	end
	box(m, "SiteCabinStair", 72, 75, 0.12, 8.7, -39, -33, C.metal, M.metal, DETAIL)
	-- materials, toilet, mixer, survey stakes
	for k = 0, 2 do
		local x = -64 + k * 5
		box(m, "Pallet", x - 2, x + 2, 0.12, 0.6, 96, 100, C.oakLight, M.wood)
		box(m, "BrickStack", x - 1.7, x + 1.7, 0.6, 3.2, 96.3, 99.7, C.terracotta, M.concrete)
	end
	for k = 0, 2 do
		Kit.cylinder(m, B, "ConcretePipe", "z", 6, 3, CF(-40 + k * 3.2, 1.62, 110), C.concrete, M.concrete)
	end
	for k = 0, 3 do
		Kit.cylinder(m, B, "RebarBundle", "x", 14, 0.5, CF(34, 0.37 + k * 0.5, 104 + (k % 2) * 0.5), C.terracotta, M.metal, DETAIL)
	end
	box(m, "SkipContainer", 54, 64, 0.12, 4, 120, 126, C.metalSoft, M.metal)
	box(m, "SiteToilet", 70, 74, 0.12, 8, 140, 144, C.blue, M.smooth)
	box(m, "SiteToiletRoof", 69.8, 74.2, 8, 8.4, 139.8, 144.2, C.white, M.smooth, DETAIL)
	Kit.cylinder(m, B, "MixerDrum", "x", 4, 3, CF(-22, 3.6, 126) * ANG(0, 0, math.rad(20)), C.statusBusy, M.metal)
	box(m, "MixerStand", -24, -20, 0.12, 2.1, 125, 127, C.metal, M.metal, DETAIL)
	for k = 0, 5 do
		local x, z = -60 + k * 24, -26
		box(m, "SurveyStake", x - 0.12, x + 0.12, 0.2, 3, z - 0.12, z + 0.12, C.oakLight, M.wood, DETAIL)
	end
	box(m, "SurveyTape", -60, 60, 2.4, 2.5, -26.04, -25.96, C.statusBad, M.smooth, DETAIL)
	local _ = seed
end

local function stageCameras(ctx: any)
	local folder: Instance = ctx.folders.Cameras
	local g = Plan.GARAGE_LAB
	Kit.camera(folder, B, "EXT_GARAGE", "Garage, porch & driveway", V3(g.x2 + 1.6, 12.6, g.z1 - 1.6), V3(84, 1, -136), 0, "SITE_GARAGE", false)
	Kit.camera(folder, B, "EXT_SITE", "Construction site", V3(Plan.CONSTRUCTION.x1 + 0.6, 9.4, Plan.CONSTRUCTION.z1 - 0.6), V3(10, 0, 60), 0, "SITE_CONSTRUCTION", false)
end

local function garageStage(ctx: any)
	stageGround(ctx)
	stageGarage(ctx)
	stageConstruction(ctx)
	arcade(ctx)
	garden(ctx)
	yard(ctx)
	stageCameras(ctx)
end

function Exterior.build(ctx: any)
	B = ctx.cf
	table.clear(verts)
	table.clear(vindex)
	if ctx.tier < 1 then
		garageStage(ctx)
		return
	end
	structure(ctx)
	facades(ctx)
	entrance(ctx)
	garage(ctx)
	site(ctx)
	arcade(ctx)
	garden(ctx)
	yard(ctx)
	cameras(ctx)
	if Plan.hasHotel(ctx.tier) then
		guestHouse(ctx)
	end
end

return Exterior
