--!strict
-- RoomKitsHotel: the company guest house (hotel annex, Plan.hasHotel). Runs after InteriorDesign (room
-- models, walls, interior doors, floors, ceilings, nameplates, cameras, access volumes) and the exterior
-- (facade, entrance and terrace doors, roof). Builds the switchback stair and furnishes every room:
--   lobby: two-station reception counter (fluted oak, stone ledge, brass plate) with the receptionist
--          (operations post 13 "Hotel Reception": seated, job points greet / printer with the key-card
--          printer PropFx), walnut back wall with the company name and "GUEST HOUSE" in brass,
--          backlit key-cubby grid, live reception screen, lounge (sofa + 2 armchairs = Waiting seats)
--          before a sheer curtain, pendants, concierge desk, luggage trolley, an art screen on the
--          entrance axis, artwork, plants, rugs;
--   breakfast room: buffet (food, sneeze guard, menu board) with a coffee machine (Coffee activities),
--          3 tables x 4 + 8 window-bar Dining seats;
--   pantry, housekeeping (operations post 14 "Housekeeping": cart + job points room1..room4 in the
--          ground-floor guest rooms), front office;
--   workshop room: 10 Meeting seats (MeetingRoom "HotelWorkshop"), whiteboard, screen;
--   12 guest rooms (bed, bedside tables, framed print, desk + chair, wardrobe, TV with a welcome page,
--          drapes and a sheer at the window (west rooms: framing the French window), en-suite with toilet,
--          basin and shower behind a cubicle door; FixtureKey contract), suite 208 with a lounge corner.
-- Seats for guests are "Waiting" (lobby) / "Dining" / "Meeting" activities in guest-class rooms: staff
-- never take them (clearance), the later guest NPCs can. Everything sits INSIDE ctx.rooms[id].
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Plan = require(ReplicatedStorage.Shared.Config.BuildingPlan)
local A = require(ReplicatedStorage.Shared.Config.ArchPalette)
local Kit = require(script.Parent.ArchKit)

local C, M = A.color, A.material
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local PI = math.pi
local DETAIL: Kit.Opts = { detail = true }
local GLASS: Kit.Opts = { transparency = A.glassTransparency, castShadow = false }
local WATER: Kit.Opts = { detail = true, transparency = 1 }
local FIN = Kit.FINISH

local Hotel = {}

-- The west-strip rooms (door on the corridor's west side: offices and guest rooms on both floors) look
-- out through one French window this wide, centred on the room; ExteriorDesign closes the rest of the
-- west facade's glass line with render wall panels and the guest rooms frame the window with their drapes.
Hotel.WEST_WINDOW = 6

type Ctx = { office: Model, cf: CFrame, tier: number, owner: number, accent: Color3, company: string, folders: { [string]: Instance }, rooms: { [string]: Model } }
type Room = Plan.Room

local function fit(ctx: Ctx, r: Room): Model
	local room = ctx.rooms[r.id]
	if not room then
		local created = Kit.model(ctx.folders.Rooms, r.id, true)
		created:SetAttribute("RoomId", r.id)
		created:SetAttribute("RoomName", r.name)
		created:SetAttribute("RoomKind", r.kind)
		created:SetAttribute("Level", r.level)
		created:SetAttribute("AccessClass", r.access)
		ctx.rooms[r.id] = created
		room = created
	end
	return Kit.model(room :: Model, "FitOut")
end

local function floorY(r: Room): number
	return Plan.levelY(r.level) + FIN
end

-- Activity point (building-local stand point p, look-at point f; heights are taken from p.Y).
local function activity(ctx: Ctx, parent: Model, r: Room, id: string, kind: string, dept: string, p: Vector3, f: Vector3, seat: Seat?, extra: { [string]: any }?): Model
	local stand = V3(p.X, floorY(r) + 2.8, p.Z)
	local look = V3(f.X, floorY(r) + 2.8, f.Z)
	return Kit.activity(parent, ctx.cf, id, kind, dept, if kind == "Service" then "support" else "any", Kit.facing(stand, look), r.level, ctx.owner, seat, {
		roomAccess = r.access,
		homeRoom = r.id,
		facing = look,
		meetingRoom = extra and extra.meetingRoom,
		attributes = extra and extra.attributes,
	})
end

-- Operations post with job points (PROPFX_CONTRACT §9): JobPoint_<name> / JobFace_<name> / JobProp_<name>.
type JobPoint = { name: string, stand: Vector3, face: Vector3, prop: string? }
local function opsPost(ctx: Ctx, parent: Model, r: Room, i: number, stand: Vector3, face: Vector3, seat: Seat?, points: { JobPoint })
	local post = activity(ctx, parent, r, "OperationsStation" .. i, "Service", "operations", stand, face, seat, { attributes = { OpsIndex = i } })
	for _, jp in points do
		local y = Plan.levelY(jp.stand.Y) + FIN + 2.8 -- jp.stand.Y carries the level of the point
		post:SetAttribute("JobPoint_" .. jp.name, ctx.cf:PointToWorldSpace(V3(jp.stand.X, y, jp.stand.Z)))
		post:SetAttribute("JobFace_" .. jp.name, ctx.cf:PointToWorldSpace(V3(jp.face.X, y, jp.face.Z)))
		if jp.prop then
			post:SetAttribute("JobProp_" .. jp.name, jp.prop)
		end
	end
	return post
end

-- Chair (sitter faces the point `to`) with a Dining / Meeting activity. The NPC stands `stand` away from
-- the chair (building-local offset; default: 1.6 behind and 1.6 to the side).
local function seatWithActivity(ctx: Ctx, parent: Model, r: Room, id: string, kind: string, dept: string, x: number, z: number, to: Vector3, seed: number, extra: { [string]: any }?, stand: Vector3?): Seat
	local y = floorY(r)
	local seat = Kit.meetingChair(parent, ctx.cf, Kit.facing(V3(x, y, z), V3(to.X, y, to.Z)), seed)
	local back = V3(x - to.X, 0, z - to.Z)
	back = if back.Magnitude > 0.01 then back.Unit else V3(0, 0, 1)
	local side = V3(-back.Z, 0, back.X)
	local p = V3(x, y, z) + (stand or (back * 1.6 + side * 1.6))
	local a = activity(ctx, parent, r, id, kind, dept, p, to, seat, extra)
	a:SetAttribute("TablePoint", ctx.cf:PointToWorldSpace(V3(x, y, z) - back * 1.9 + V3(0, 3.2, 0)))
	return seat
end

---------------------------------------------------------------------------------------------
-- Built lettering for the house name (the parapet signs in ExteriorDesign): one part per
-- stroke, so the words read at any distance (SurfaceGui text fades out at MaxDistance) and need no
-- texture. Glyph = advance + strokes {u1, u2, v1, v2} in cap heights; only the letters the signs use.
---------------------------------------------------------------------------------------------
local SW = 0.16 -- stroke width (cap heights)
local MID1, MID2 = 0.5 - SW / 2, 0.5 + SW / 2
local GLYPHS: { [string]: { w: number, s: { { number } } } } = {
	G = { w = 0.7, s = { { 0, 0.7, 1 - SW, 1 }, { 0, SW, SW, 1 - SW }, { 0, 0.7, 0, SW }, { 0.7 - SW, 0.7, SW, 0.48 }, { 0.36, 0.7 - SW, 0.48 - SW, 0.48 } } },
	U = { w = 0.62, s = { { 0, SW, SW, 1 }, { 0.62 - SW, 0.62, SW, 1 }, { 0, 0.62, 0, SW } } },
	E = { w = 0.55, s = { { 0, SW, 0, 1 }, { SW, 0.55, 1 - SW, 1 }, { SW, 0.47, MID1, MID2 }, { SW, 0.55, 0, SW } } },
	S = { w = 0.62, s = { { 0, 0.62, 1 - SW, 1 }, { 0, SW, MID2, 1 - SW }, { 0, 0.62, MID1, MID2 }, { 0.62 - SW, 0.62, SW, MID1 }, { 0, 0.62, 0, SW } } },
	T = { w = 0.6, s = { { 0, 0.6, 1 - SW, 1 }, { 0.3 - SW / 2, 0.3 + SW / 2, 0, 1 - SW } } },
	H = { w = 0.62, s = { { 0, SW, 0, 1 }, { 0.62 - SW, 0.62, 0, 1 }, { SW, 0.62 - SW, MID1, MID2 } } },
	O = { w = 0.68, s = { { 0, SW, 0, 1 }, { 0.68 - SW, 0.68, 0, 1 }, { SW, 0.68 - SW, 1 - SW, 1 }, { SW, 0.68 - SW, 0, SW } } },
	[" "] = { w = 0.34, s = {} },
}
local GLYPH_GAP = 0.16

-- Width of `text` in studs at cap height `height`.
function Hotel.lettersWidth(text: string, height: number): number
	local w = 0
	for i = 1, #text do
		local g = GLYPHS[string.sub(text, i, i)]
		if g then
			w += g.w + (if i < #text then GLYPH_GAP else 0)
		end
	end
	return w * height
end

-- `text` on the plane of `at` (cf-local): origin = middle of the baseline, LookVector INTO the wall (the
-- viewer's direction), so +X reads left to right; strokes stand `depth` proud towards the viewer.
-- Characters without a glyph are skipped. Parts are decor (no collision/touch/query/shadow).
function Hotel.letters(parent: Instance, cf: CFrame, text: string, at: CFrame, height: number, depth: number, color: Color3, material: Enum.Material)
	local cursor = -Hotel.lettersWidth(text, height) / 2
	for i = 1, #text do
		local g = GLYPHS[string.sub(text, i, i)]
		if g then
			for _, s in g.s do
				local w, h = (s[2] - s[1]) * height, (s[4] - s[3]) * height
				local x, y = cursor + (s[1] + s[2]) / 2 * height, (s[3] + s[4]) / 2 * height
				Kit.part(parent, cf, "SignLetter", V3(w, h, depth), at * CF(x, y, depth / 2), color, material, DETAIL)
			end
			cursor += (g.w + GLYPH_GAP) * height
		end
	end
end

-- Flat GUI frame (centre x, y and size w, h as fractions of the parent), optionally rounded by a UICorner.
local function guiBlock(parent: Instance, name: string, x: number, y: number, w: number, h: number, color: Color3, radius: number?, z: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z or 1
	if radius then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(radius, 0)
		corner.Parent = f
	end
	f.Parent = parent
	return f
end

-- Folds of a sheer curtain (0 extra parts): soft vertical bands, one per `pitch` studs, on one face of the
-- curtain part (lit by the room, culled beyond `maxDistance`); the curtain's own translucency shows between them.
local function sheerPleats(part: BasePart, face: Enum.NormalId, pitch: number, maxDistance: number)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Pleats"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 10
	gui.LightInfluence = 1
	gui.MaxDistance = maxDistance
	gui.Parent = part
	local width = if face == Enum.NormalId.Left or face == Enum.NormalId.Right then part.Size.Z else part.Size.X
	local n = math.max(1, math.floor(width / pitch))
	for i = 1, n do
		local f = guiBlock(gui, "Fold" .. i, (i - 0.5) / n, 0.5, 0.42 / n, 1, C.fabricSand:Lerp(C.white, 0.2))
		f.BackgroundTransparency = 0.3
	end
end

---------------------------------------------------------------------------------------------
-- Guest rooms (room frame: u = into the room from the corridor wall, v = along the room from the
-- door end; west-strip rooms are the east layout turned by 180°)
---------------------------------------------------------------------------------------------
local function roomFrame(r: Room): (CFrame, number, number)
	local y = floorY(r)
	local door = r.doors[1]
	if door and door.face == "E" then
		-- west strip: corridor wall at x2, door end at z2
		return CF(r.x2, y, r.z2) * ANG(0, PI, 0), r.x2 - r.x1, r.z2 - r.z1
	end
	return CF(r.x1, y, r.z1), r.x2 - r.x1, r.z2 - r.z1
end

-- yaw in the room frame so that an object's front (-Z) faces the given local direction
local FACE_U, FACE_MINUS_U, FACE_V = ANG(0, -PI / 2, 0), ANG(0, PI / 2, 0), ANG(0, PI, 0)

local function bed(m: Model, cf: CFrame, at: CFrame, w: number, seed: number)
	local L = 7.6
	local cover = Kit.pick({ C.fabricSand, C.sageLight, C.blueSoft, C.white }, seed)
	Kit.part(m, cf, "BedBase", V3(w, 1.3, L - 0.4), at * CF(0, 0.65, -(L / 2 + 0.2)), C.oakDark, M.wood)
	Kit.part(m, cf, "Mattress", V3(w - 0.3, 0.9, L - 0.7), at * CF(0, 1.75, -(L / 2 + 0.25)), C.white, M.fabric)
	Kit.part(m, cf, "Duvet", V3(w - 0.1, 0.2, L * 0.6), at * CF(0, 2.28, -(L * 0.7)), cover, M.fabric, DETAIL)
	Kit.part(m, cf, "Headboard", V3(w + 0.6, 4.4, 0.35), at * CF(0, 2.2, -0.18), Kit.pick({ C.fabricCharcoal, C.fabric, C.oak }, seed + 1), M.fabric)
	for _, k in { -1, 1 } do
		Kit.part(m, cf, "Pillow", V3(w / 2 - 0.5, 0.45, 1.2), at * CF(k * w / 4, 2.42, -1.2), C.white, M.fabric, DETAIL)
	end
end

-- Rug w x d with a border (non-colliding; the colours as Kit.rug). Border 0.05 and field 0.10 high: the
-- tops are 0.05 apart, so they do not flicker at distance (Kit.rug's 0.04 / 0.05 do). Returns the field.
local function rug(m: Model, cf: CFrame, at: CFrame, w: number, d: number, seed: number, border: Color3?, field: Color3?): Part
	local bc = border or Kit.pick({ C.fabricCharcoal, C.oakDark, C.fabricBlue, C.sage }, seed)
	local fc = field or Kit.pick({ C.fabricSand, C.carpetWarm, C.sageLight, C.blueSoft }, seed + 3)
	Kit.part(m, cf, "RugBorder", V3(w, 0.05, d), at * CF(0, 0.025, 0), bc, M.fabric, DETAIL)
	return Kit.part(m, cf, "Rug", V3(w - 0.6, 0.1, d - 0.6), at * CF(0, 0.05, 0), fc, M.fabric, DETAIL)
end

-- Framed print (0 extra parts): the ArtPrint part is the paper, the picture a seeded composition of
-- SurfaceGui frames on its Front face (a landscape: field, sun disc, hill; or an abstract: block, disc,
-- bar), lit by the room (LightInfluence 1) and culled beyond 30 studs.
local PRINT_COLORS = { C.terracotta, C.sage, C.blue, C.brass, C.oakDark, C.statusBusy, C.fabricBlue, C.sageLight }
local function printArt(part: BasePart, seed: number)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Print"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 1
	gui.MaxDistance = 30
	gui.Parent = part
	-- (x, y) = centre, (w, h) as a fraction of the print; square = both relative to the print's height
	local function shape(name: string, x: number, y: number, w: number, h: number, color: Color3, round: boolean, square: boolean)
		local f = Instance.new("Frame")
		f.Name = name
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(x, y)
		f.Size = UDim2.fromScale(w, h)
		if square then
			f.SizeConstraint = Enum.SizeConstraint.RelativeYY
		end
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		if round then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = f
		end
		f.Parent = gui
	end
	local n = #PRINT_COLORS
	local i1 = 1 + seed % n
	local i2 = 1 + (i1 + 1 + seed % 3) % n
	local i3 = 1 + (i2 + 2) % n
	local c1, c2, c3 = PRINT_COLORS[i1], PRINT_COLORS[i2], PRINT_COLORS[i3]
	if Kit.rand(seed, 1) < 0.5 then
		local sx = Kit.range(seed, 2, 0.28, 0.72)
		shape("Sun", sx, 0.36, 0.44, 0.44, c2, true, true)
		shape("Hill", 1 - sx, 0.72, 0.62, 0.5, c3, true, false)
		shape("Field", 0.5, 0.86, 0.92, 0.2, c1, false, false)
	else
		shape("Block", Kit.range(seed, 3, 0.3, 0.45), 0.5, 0.36, 0.72, c1, false, false)
		shape("Disc", Kit.range(seed, 4, 0.55, 0.72), Kit.range(seed, 5, 0.38, 0.6), 0.6, 0.6, c2, true, true)
		shape("Bar", 0.5, Kit.range(seed, 6, 0.78, 0.86), 0.84, 0.07, c3, false, false)
	end
end

local function nightstand(m: Model, cf: CFrame, at: CFrame, w: number?)
	Kit.part(m, cf, "Nightstand", V3(w or 1.5, 1.9, 1.3), at * CF(0, 0.95, -0.65), C.oak, M.wood)
	Kit.cylinder(m, cf, "LampShade", "y", 0.7, 0.8, at * CF(0, 2.6, -0.65), C.lightWarm, M.neon, DETAIL)
	Kit.cylinder(m, cf, "LampFoot", "y", 0.4, 0.3, at * CF(0, 2.05, -0.65), C.brass, M.metal, DETAIL)
end

-- En-suite inside the guest room frame F: u 0.5..6.5, v 7..13.5 (a partition closes it at v 13.5 in the
-- longer rooms); a cubicle door (u 3.1..6.3) in the v = 7 partition.
local function ensuite(ctx: Ctx, m: Model, r: Room, F: CFrame, W: number)
	local cf = ctx.cf
	local H = Plan.CEILING - 0.15
	local back = 13.5
	Kit.part(m, cf, "BathPartition", V3(2.6, H, 0.3), F * CF(1.8, H / 2, 7), C.white, M.plaster)
	Kit.part(m, cf, "BathPartition", V3(0.3, H, back - 6.85), F * CF(6.5, H / 2, (6.85 + back) / 2), C.white, M.plaster)
	if W > back + 1 then
		Kit.part(m, cf, "BathPartition", V3(6.15, H, 0.3), F * CF(3.575, H / 2, back + 0.15), C.white, M.plaster)
	end
	local key = r.id .. "_BATH"
	local centre = (F * CF(4.7, 0, 7)).Position -- building-local (F is a building-local frame)
	local inward = F:VectorToWorldSpace(V3(0, 0, 1))
	local def: any = {
		id = key,
		level = r.level,
		room = r.id,
		kind = "cubicle",
		access = r.access,
		axis = if math.abs(inward.X) > 0.5 then "z" else "x",
		x = centre.X,
		z = centre.Z,
		w = 3.2,
		h = 7.2,
		inward = inward,
		exterior = false,
		hidden = false,
		builder = "interior",
		y = centre.Y,
		thickness = 0.3,
	}
	local _ = W
	local door = Kit.door(ctx.folders.Doors, cf, def :: any, ctx.owner)
	if door then
		door:SetAttribute("FixtureKey", r.id .. "_T")
	end
	-- the partition over the cubicle opening (the door frame takes u 3.1..6.3)
	Kit.part(m, cf, "BathPartitionHead", V3(3.2, H - 7.2, 0.3), F * CF(4.7, 7.2 + (H - 7.2) / 2, 7), C.white, M.plaster)
	-- toilet against the back wall
	local tb = F * CF(2.3, 0, back) -- wall surface, front towards -v (into the bathroom)
	Kit.part(m, cf, "ToiletBowl", V3(1.5, 1.4, 2.2), tb * CF(0, 0.7, -1.3), C.white, M.smooth)
	Kit.part(m, cf, "ToiletTank", V3(1.9, 2.2, 0.7), tb * CF(0, 2.4, -0.35), C.white, M.smooth)
	local seat = Kit.seat(m, cf, "ToiletSeat", V3(1.5, 0.2, 1.8), tb * CF(0, 1.5, -1.4), C.white, M.smooth, { canTouch = false })
	seat.Disabled = true
	seat:SetAttribute("FixtureKey", r.id .. "_T")
	Kit.action(seat, "toilet", "Toilet", nil, { actionText = "Use", maxDistance = 6 })
	local flush = Kit.part(m, cf, "FlushButton", V3(0.6, 0.35, 0.08), tb * CF(0, 3.0, -0.74), C.metalSoft, M.metal, { canCollide = false, canTouch = false })
	flush:SetAttribute("FixtureKey", r.id .. "_T")
	Kit.action(flush, "flush", "Flush", nil, { actionText = "Flush", maxDistance = 6 })
	local tw = Kit.part(m, cf, "ToiletWater", V3(1.0, 0.05, 1.2), tb * CF(0, 1.32, -1.45), C.water, M.smooth, { detail = true, transparency = 0.25 })
	tw:SetAttribute("FixtureKey", r.id .. "_T")
	Kit.fx(tw, "flow", { FxAxis = "y", FxTravel = -0.3, FxRate = 3, FxSeconds = 2 })
	-- basin on the corridor-side wall
	local bb = F * CF(0.5, 0, 9.6) * FACE_U
	Kit.part(m, cf, "VanityTop", V3(2.6, 0.25, 1.5), bb * CF(0, 2.85, -0.75), C.stone, M.marble)
	Kit.part(m, cf, "Basin", V3(1.5, 0.3, 1.1), bb * CF(0, 3.1, -0.8), C.white, M.smooth, DETAIL)
	local tap = Kit.part(m, cf, "Tap", V3(0.2, 0.7, 0.5), bb * CF(0, 3.55, -0.3), C.metalSoft, M.metal, { canCollide = false })
	tap:SetAttribute("FixtureKey", r.id .. "_B")
	Kit.action(tap, "tap", "Tap", nil, { actionText = "Wash hands", maxDistance = 6 })
	local water = Kit.part(m, cf, "TapWater", V3(0.15, 0.55, 0.15), bb * CF(0, 3.25, -0.55), C.water, M.smooth, WATER)
	water:SetAttribute("FixtureKey", r.id .. "_B")
	water:SetAttribute("FxShow", 0.5)
	Kit.fx(water, "flow", { FxSeconds = 6 })
	Kit.part(m, cf, "Mirror", V3(2.4, 3.0, 0.08), bb * CF(0, 5.6, -0.05), C.glassDeep, M.glass, { detail = true, reflectance = 0.25 })
	-- shower in the corner behind a glass screen
	local su, sv = 5.3, back - 1.45
	Kit.part(m, cf, "ShowerTray", V3(1.9, 0.08, 2.8), F * CF(su, 0.04, sv), C.metalSoft, M.slate, DETAIL)
	Kit.part(m, cf, "ShowerScreen", V3(1.9, 7.2, 0.12), F * CF(su, 3.7, back - 2.9), C.glass, M.glass, GLASS)
	local head = Kit.cylinder(m, cf, "ShowerHead", "y", 0.15, 1.1, F * CF(su, 8.0, back - 0.7), C.metalSoft, M.metal, { canCollide = false, castShadow = false })
	head:SetAttribute("FixtureKey", r.id .. "_S")
	Kit.action(head, "shower", "Shower", nil, { actionText = "Start / stop", maxDistance = 8 })
	local sw = Kit.part(m, cf, "ShowerWater", V3(1.0, 7.6, 1.0), F * CF(su, 4.1, back - 0.9), C.water, M.glass, WATER)
	sw:SetAttribute("FixtureKey", r.id .. "_S")
	sw:SetAttribute("FxShow", 0.5)
	Kit.fx(sw, "flow", { FxSeconds = 15 })
end

-- Drapes either side of every room window over a white sheer: one warm rust-sand fabric for the whole house,
-- so each window reads as a curtained guest room (a light drape vanishes against the sheer). Centre plane
-- CURTAIN_U inside the window wall (u = D), 0.15 thick; the desk and the window-side nightstand keep clear
-- of it. West rooms (Hotel.WEST_WINDOW wide French window centred on the room, wall panels outside the
-- rest of the glass): the drapes cover the wall from the side walls to 1.5 inside the window opening and
-- the sheer spans the opening. East rooms (full-height glazing): drapes at both window ends, sheer across.
local CURTAIN_U = 0.2
local CURTAIN_COLOR = C.terracotta:Lerp(C.fabricSand, 0.35)

local function guestRoom(ctx: Ctx, r: Room)
	local m = fit(ctx, r)
	local cf = ctx.cf
	local F, D, W = roomFrame(r)
	local seed = Kit.hash(r.id)
	local suite = r.vip == true
	ensuite(ctx, m, r, F, W)
	local wallEnd = W - 0.5 -- far end wall (headboard)
	-- bed against the far wall, nightstands either side
	local bw = if suite then 7 else 6
	local bu = 12
	bed(m, cf, F * CF(bu, 0, wallEnd), bw, seed)
	nightstand(m, cf, F * CF(bu - bw / 2 - 1.1, 0, wallEnd)) -- 0.05 clear of the headboard
	-- window-side nightstand between the headboard end and the curtain's inner face (CURTAIN_U - 0.075),
	-- >= 0.05 clear of the headboard; in the 17-deep west rooms it narrows to keep >= 0.1 clear of both
	local hbEnd, curtainIn = bu + bw / 2 + 0.3, D - CURTAIN_U - 0.075
	nightstand(m, cf, F * CF(math.min(bu + bw / 2 + 1.1, (hbEnd + curtainIn) / 2), 0, wallEnd), math.min(1.5, curtainIn - hbEnd - 0.2))
	rug(m, cf, F * CF(bu, 0, wallEnd - 6.4), bw + 2, 4.5, seed + 2)
	-- the guest's point in the room (for the later hotel-guest NPCs): at the foot of the bed, facing it.
	-- Its own kind "GuestBed": no employee job or break looks for it, guest clearance only.
	local gp = (F * CF(10.6, 0, 4.4)).Position
	local gf = (F * CF(bu, 0, wallEnd - 4)).Position
	local number = tonumber(string.match(r.name, "(%d+)$"))
	activity(ctx, m, r, r.id .. "_Guest", "GuestBed", "hotel", V3(gp.X, 0, gp.Z), V3(gf.X, 0, gf.Z), nil, {
		attributes = { GuestRoom = r.id, RoomNumber = number, Suite = suite },
	})
	-- framed print over the headboard: paper-coloured print with a seeded picture (SurfaceGui frames)
	local art = F * CF(bu, 0, wallEnd)
	Kit.part(m, cf, "ArtFrame", V3(bw - 1.2, 2.6, 0.1), art * CF(0, 6.6, -0.05), Kit.pick({ C.white, C.oakDark, C.metal }, seed + 11), M.smooth, DETAIL)
	local artPrint = Kit.part(m, cf, "ArtPrint", V3(bw - 2.0, 1.8, 0.04), art * CF(0, 6.6, -0.12), Kit.pick({ C.white, C.fabricSand }, seed + 12), M.smooth, DETAIL)
	printArt(artPrint, seed + 12)
	-- wardrobe and TV on the door-end wall (the TV shows the house's welcome page), writing desk at the window.
	-- The set is a dark screen (SmoothPlastic): the page is self-lit (LightInfluence 0) and culled beyond
	-- 40 studs, so from outside the facade a room TV stays dark instead of a glowing slab.
	Kit.cabinet(m, cf, F * CF(8.8, 0, 0.5) * FACE_V, 3.6, 7.5, seed + 3).Name = "Wardrobe"
	local tvAt = F * CF(12.6, 0, 0.5) * FACE_V
	Kit.part(m, cf, "TVBracket", V3(0.6, 0.6, 0.3), tvAt * CF(0, 5.6, -0.15), C.metal, M.metal, DETAIL)
	local tv = Kit.part(m, cf, "TV", V3(3.6, 2.1, 0.15), tvAt * CF(0, 5.6, -0.38), C.screen, M.smooth, { canCollide = false, castShadow = false })
	local page = Instance.new("SurfaceGui")
	page.Name = "WelcomePage"
	page.Face = Enum.NormalId.Front
	page.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	page.PixelsPerStud = 60
	page.LightInfluence = 0
	page.MaxDistance = 40
	page.Parent = tv
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = C.fabricBlue
	bg.BackgroundTransparency = 0
	bg.BorderSizePixel = 0
	bg.Parent = page
	for i, line in { "WELCOME", ctx.company .. " Guest House", r.name } do
		local t = Instance.new("TextLabel")
		t.Name = "Line" .. i
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromScale(0.08, if i == 1 then 0.14 else 0.34 + (i - 1) * 0.16)
		t.Size = UDim2.fromScale(0.84, if i == 1 then 0.3 else 0.14)
		t.Text = line
		t.TextScaled = true
		t.TextColor3 = if i == 1 then C.lightWarm else C.white
		t.Font = if i == 1 then Enum.Font.BuilderSansExtraBold else Enum.Font.BuilderSans
		t.Parent = bg
	end
	local du = D - 1.6 -- desk u D-2.6..D-0.6: clear of the curtain (D-0.275..D-0.125)
	Kit.part(m, cf, "WritingDesk", V3(2.0, 0.2, 4.0), F * CF(du, 3.0, 3.2), C.oak, M.wood)
	for _, dv in { 1.4, 5.0 } do
		Kit.part(m, cf, "DeskLeg", V3(1.8, 2.9, 0.2), F * CF(du, 1.45, dv), C.metal, M.metal)
	end
	Kit.meetingChair(m, cf, F * CF(du - 2.2, 0, 3.2) * FACE_U, seed + 4)
	Kit.part(m, cf, "DeskLamp", V3(0.4, 1.2, 0.4), F * CF(du + 0.3, 3.7, 1.8), C.brass, M.metal, DETAIL)
	-- drapes 0.04 off the skirting of the side walls (faces at v 0.5 and W - 0.5) and a translucent white
	-- sheer between the glass (u = D) and the drapes. West rooms (French window v W/2 -+ WEST_WINDOW/2):
	-- each drape from the side wall to 1.5 inside the opening, the sheer across the opening; full glazing:
	-- 3.2-wide drapes drawn to both window ends (about 2.4 of each in front of the glass), sheer across
	local westWindow = r.doors[1] ~= nil and r.doors[1].face == "E"
	local drapeW = if westWindow then W / 2 - Hotel.WEST_WINDOW / 2 + 1.5 - 0.6 else 3.2
	local sheerW = if westWindow then Hotel.WEST_WINDOW + 0.4 else W - 1.2
	for _, cv in { 0.6 + drapeW / 2, W - 0.6 - drapeW / 2 } do
		Kit.part(m, cf, "Curtain", V3(0.15, 11.6, drapeW), F * CF(D - CURTAIN_U, 6.0, cv), CURTAIN_COLOR, M.fabric, DETAIL)
	end
	local windowSheer = Kit.part(m, cf, "WindowSheer", V3(0.05, 11.6, sheerW), F * CF(D - 0.06, 6.0, W / 2), C.white, M.fabric, { detail = true, transparency = 0.45 })
	sheerPleats(windowSheer, Enum.NormalId.Left, 0.8, 40) -- folds on the room side (-u)
	if W > 16 then
		-- bigger rooms: armchair corner at the window between desk and bed; the suite: sofa and two chairs
		local lv = (6.5 + W - 8.6) / 2
		if suite then
			-- sofa under the window facing two armchairs with a side table between them
			Kit.sofa(m, cf, F * CF(D - 2.0, 0, lv) * FACE_MINUS_U, 7, seed + 6)
			Kit.loungeChair(m, cf, F * CF(8.6, 0, lv - 2.2) * FACE_U, seed + 7)
			Kit.loungeChair(m, cf, F * CF(8.6, 0, lv + 2.2) * FACE_U, seed + 8)
			Kit.coffeeTable(m, cf, F * CF(D - 1.6, 0, lv + 5.4), seed + 9, 1.8, 1.8)
		else
			Kit.loungeChair(m, cf, F * CF(D - 2.2, 0, lv) * FACE_MINUS_U, seed + 6)
			Kit.coffeeTable(m, cf, F * CF(D - 2.0, 0, lv + 3.0), seed + 9, 1.8, 1.8)
			Kit.floorLamp(m, cf, F * CF(D - 1.4, 0, lv - 2.6), seed + 10)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Ground floor: lobby, breakfast, pantry, housekeeping, office
---------------------------------------------------------------------------------------------
-- Two-line SurfaceGui sign (title over subtitle) on one face of `part`; LightInfluence 0 = self-lit.
-- Text boards get 100 pixels per stud whatever their size (the subtitle line is only 0.26 of the face
-- height, so it needs the resolution), capped at 1000 px along the face's longer side.
local function signText(part: BasePart, face: Enum.NormalId, title: string, subtitle: string?, titleColor: Color3, subColor: Color3, maxDistance: number, name: string?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = name or "Sign"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	local s = part.Size
	local faceLong = if face == Enum.NormalId.Left or face == Enum.NormalId.Right then math.max(s.Y, s.Z) elseif face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then math.max(s.X, s.Z) else math.max(s.X, s.Y)
	gui.PixelsPerStud = math.min(100, math.floor(1000 / faceLong))
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance
	gui.Parent = part
	local function label(n: string, text: string, y0: number, h: number, color: Color3, font: Enum.Font)
		local t = Instance.new("TextLabel")
		t.Name = n
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromScale(0.06, y0)
		t.Size = UDim2.fromScale(0.88, h)
		t.Text = text
		t.TextScaled = true
		t.TextWrapped = true
		t.TextColor3 = color
		t.Font = font
		t.Parent = gui
	end
	if subtitle then
		label("Label", title, 0.1, 0.52, titleColor, Enum.Font.BuilderSansExtraBold)
		label("Sub", subtitle, 0.64, 0.26, subColor, Enum.Font.BuilderSansMedium)
	else
		label("Label", title, 0.14, 0.72, titleColor, Enum.Font.BuilderSansExtraBold)
	end
end

-- Glass globe pendant hanging from the ceiling (13.0 above the floor) at building-local (x, z).
local function globePendant(m: Model, cf: CFrame, x: number, y: number, z: number, drop: number): Part
	Kit.cylinder(m, cf, "PendantCable", "y", drop, 0.06, CF(x, y + 13 - drop / 2, z), C.metal, M.metal, DETAIL)
	return Kit.ball(m, cf, "PendantGlobe", 1.1, CF(x, y + 13 - drop - 0.6, z), C.lightWarm, M.neon, DETAIL)
end

-- Reception counter along z1..z2 at x = -108.7 (front, facing the entrance in +X): oak front with
-- dark oak fluting either side of a brass name plate, stone transaction ledge with an LED strip, stone
-- end returns, a lower work top behind it (x -112.3..-109.7, starting 1.3 behind the south end so the
-- receptionist's hops keep their clearance). Every part name starts with "Reception" (tests/buildings:
-- the negative hop through the desk names it).
local function receptionCounter(m: Model, cf: CFrame, y: number, z1: number, z2: number): Part
	local L, zc = z2 - z1, (z1 + z2) / 2
	Kit.part(m, cf, "ReceptionFront", V3(0.9, 3.42, L - 0.6), CF(-109.25, y + 0.3 + 1.71, zc), C.oak, M.wood)
	Kit.part(m, cf, "ReceptionKick", V3(0.5, 0.3, L - 0.8), CF(-109.35, y + 0.15, zc), C.metal, M.metal)
	local k = 0
	while 2.1 + k * 0.75 <= L / 2 - 0.55 do
		for _, side in { -1, 1 } do
			Kit.part(m, cf, "ReceptionFlute", V3(0.1, 3.1, 0.34), CF(-108.75, y + 2.0, zc + side * (2.1 + k * 0.75)), C.oakDark, M.wood, DETAIL)
		end
		k += 1
	end
	for _, ez in { z1 + 0.15, z2 - 0.15 } do
		Kit.part(m, cf, "ReceptionEnd", V3(1.5, 3.72, 0.3), CF(-109.25, y + 1.86, ez), C.stone, M.marble)
	end
	local ledge = Kit.part(m, cf, "ReceptionLedge", V3(1.6, 0.18, L + 0.2), CF(-109.3, y + 3.81, zc), C.stoneDeep, M.marble)
	Kit.part(m, cf, "ReceptionGlow", V3(0.06, 0.06, L - 0.8), CF(-108.62, y + 3.66, zc), C.lightWarm, M.neon, DETAIL)
	local wz1 = z1 + 1.3
	Kit.part(m, cf, "ReceptionWorktop", V3(2.6, 0.25, z2 - wz1), CF(-111.0, y + 3.025, (wz1 + z2) / 2), C.oakLight, M.wood)
	for _, lz in { wz1 + 0.3, z2 - 0.3 } do
		Kit.part(m, cf, "ReceptionLeg", V3(2.2, 2.9, 0.25), CF(-111.1, y + 1.45, lz), C.oakLight, M.wood)
	end
	local panel = Kit.part(m, cf, "ReceptionPanel", V3(0.06, 1.0, 3.4), CF(-108.72, y + 2.15, zc), C.brass, M.metal, DETAIL)
	Kit.text(panel, "RECEPTION", { face = Enum.NormalId.Right, color = C.oakDark, light = 0.6, maxDistance = 70, pad = 0.14 })
	return ledge
end

-- Staff-side monitor on the work top (screen faces -X, towards the receptionist) with a lit page.
local function staffMonitor(m: Model, cf: CFrame, y: number, z: number, title: string)
	local screen = Kit.part(m, cf, "StaffMonitor", V3(0.1, 1.25, 2.0), CF(-110.35, y + 4.05, z), C.screen, M.smooth, { canCollide = false, castShadow = false })
	Kit.part(m, cf, "MonitorStand", V3(0.5, 0.8, 0.3), CF(-110.2, y + 3.4, z), C.metal, M.metal, DETAIL)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Page"
	gui.Face = Enum.NormalId.Left
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.MaxDistance = 40
	gui.Parent = screen
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = C.fabricBlue
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local t = Instance.new("TextLabel")
	t.Name = "Label"
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromScale(0.08, 0.1)
	t.Size = UDim2.fromScale(0.84, 0.3)
	t.Text = title
	t.TextScaled = true
	t.TextColor3 = C.white
	t.Font = Enum.Font.BuilderSansBold
	t.Parent = bg
end

-- Bellman's luggage trolley (long axis along z): carpeted deck on casters, brass uprights and hanging
-- rail, two suitcases and a garment bag. The deck collides; the rest is decor.
local function luggageTrolley(m: Model, cf: CFrame, x: number, y: number, z: number)
	Kit.part(m, cf, "TrolleyDeck", V3(2.0, 0.3, 3.6), CF(x, y + 0.65, z), C.brass, M.metal)
	Kit.part(m, cf, "TrolleyCarpet", V3(1.8, 0.06, 3.4), CF(x, y + 0.83, z), C.terracotta, M.fabric, DETAIL)
	for _, dx in { -0.75, 0.75 } do
		for _, dz in { -1.45, 1.45 } do
			Kit.cylinder(m, cf, "TrolleyWheel", "x", 0.2, 0.5, CF(x + dx, y + 0.25, z + dz), C.metal, M.rubber, DETAIL)
		end
	end
	for _, dz in { -1.65, 1.65 } do
		Kit.cylinder(m, cf, "TrolleyPost", "y", 5.1, 0.16, CF(x, y + 0.8 + 2.55, z + dz), C.brass, M.metal, DETAIL)
	end
	Kit.cylinder(m, cf, "TrolleyRail", "z", 3.46, 0.16, CF(x, y + 5.85, z), C.brass, M.metal, DETAIL)
	Kit.part(m, cf, "Suitcase", V3(1.0, 2.3, 1.5), CF(x - 0.3, y + 2.0, z - 0.8), C.blue, M.smooth, DETAIL)
	Kit.part(m, cf, "Suitcase", V3(0.8, 1.6, 1.2), CF(x + 0.45, y + 1.65, z + 0.9), C.fabricCharcoal, M.smooth, DETAIL)
	Kit.part(m, cf, "GarmentBag", V3(0.25, 3.2, 1.3), CF(x + 0.1, y + 4.15, z + 0.5), C.sage, M.fabric, DETAIL)
end

-- Key-cubby grid on the +X face of the rack panel (0 extra parts): four cubbies per row, each backlit
-- (self-lit GUI, LightInfluence 0) with its room number; a brass key tag hangs in about half of them. The
-- panel's own brass shows as the grid between the cubbies.
local function keyGrid(part: BasePart, numbers: { number }, seed: number)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "KeyGrid"
	gui.Face = Enum.NormalId.Right
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.LightInfluence = 0
	gui.MaxDistance = 60
	gui.Parent = part
	local cols = 4
	local rows = math.max(1, math.ceil(#numbers / cols))
	local cw, ch = 0.94 / cols, 0.92 / rows
	for i, n in numbers do
		local col, row = (i - 1) % cols, (i - 1) // cols
		local cell = guiBlock(gui, "Cubby" .. n, 0.03 + (col + 0.5) * cw, 0.04 + (row + 0.5) * ch, cw - 0.025, ch - 0.04, C.lightWarm)
		local t = Instance.new("TextLabel")
		t.Name = "Number"
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromScale(0.08, 0.06)
		t.Size = UDim2.fromScale(0.84, 0.4)
		t.Text = tostring(n)
		t.TextScaled = true
		t.TextColor3 = C.oakDark
		t.Font = Enum.Font.BuilderSansBold
		t.ZIndex = 2
		t.Parent = cell
		if Kit.rand(seed, i) < 0.55 then
			guiBlock(cell, "KeyTag", 0.5, 0.72, 0.26, 0.4, C.brass, 0.3, 2)
		end
	end
end

-- Tall abstract composition for the lobby art screen (0 extra parts: SurfaceGui frames on the canvas, lit
-- by the room): a terracotta arch, a warm sun disc, a blue block, an oak line and a brass bar on warm
-- paper. Sizes are fractions of the 2.9 x 8.0 canvas (a disc of d studs is d / 2.9 wide, d / 8 high).
local function screenArt(part: BasePart, face: Enum.NormalId)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Print"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 1
	gui.MaxDistance = 60
	gui.Parent = part
	guiBlock(gui, "Arch", 0.44, 0.56, 0.62, 0.5, C.terracotta, 0.5, 1)
	guiBlock(gui, "Sun", 0.64, 0.22, 1.3 / 2.9, 1.3 / 8, C.statusBusy, 0.5, 2)
	guiBlock(gui, "Block", 0.68, 0.74, 0.4, 0.17, C.fabricBlue, nil, 3)
	guiBlock(gui, "Line", 0.2, 0.46, 0.02, 0.56, C.oakDark, nil, 4)
	guiBlock(gui, "Bar", 0.5, 0.9, 0.8, 0.012, C.brass, nil, 5)
end

local function lobby(ctx: Ctx, r: Room)
	local m = fit(ctx, r)
	local cf = ctx.cf
	local y = floorY(r)
	local seed = Kit.hash(r.id)
	-- reception counter on the west side facing the entrance (east), two stations. Its south end stays
	-- clear so the receptionist's direct hops (StaffJobs: seat -> greet -> printer -> seat, straight
	-- Humanoid:MoveTo lines inside the room) pass it with >= 1.0 stud (tests/life/test_routes.py,
	-- tests/buildings/test_geometry.py, tests/hotelpolish). Built first: the counter is what a hop
	-- through the desk hits.
	local CZ1, CZ2 = 95.0, 103.4
	receptionCounter(m, cf, y, CZ1, CZ2)
	local screen = Kit.screen(m, cf, "ReceptionScreen", V3(2.4, 1.4, 0.1), Kit.place(-109.4, y, 102.0, "E") * CF(0, 4.75, 0) * ANG(math.rad(-10), 0, 0), "reception", ctx.accent)
	Kit.prompt(screen, "Guest house reception", ctx.owner, "empire")
	Kit.part(m, cf, "ScreenStand", V3(0.3, 0.3, 0.6), CF(-109.4, y + 4.05, 102.0), C.metal, M.metal, DETAIL)
	-- key-card printer on the south end of the work top (Hotel Reception job point "printer")
	local printer = Kit.part(m, cf, "KeyCardPrinter", V3(1.2, 0.6, 0.9), CF(-111.4, y + 3.45, 97.45), C.metal, M.metal)
	local slot = Kit.part(printer, cf, "CardSlot", V3(0.06, 0.06, 0.7), CF(-110.78, y + 3.55, 97.45), C.statusGood, M.neon, DETAIL)
	slot:SetAttribute("FxGlow", true)
	Kit.fx(printer, "paper,blink", { FxColor = C.statusBusy, FxRate = 3, FxSeconds = 3, PropId = "HotelKeyPrinter" })
	Kit.action(printer, "prop", "Key-card printer", nil, { actionText = "Print", maxDistance = 8 })
	staffMonitor(m, cf, y, 98.9, "RESERVATIONS")
	staffMonitor(m, cf, y, 101.7, "KEY CARDS")
	-- desk bell (a brass dome on the ledge) and flowers
	Kit.ball(m, cf, "DeskBell", 0.5, CF(-108.95, y + 4.0, 96.6), C.brass, M.metal, DETAIL)
	Kit.cylinder(m, cf, "Vase", "y", 0.9, 0.4, CF(-109.5, y + 4.35, 100.1), C.white, M.smooth, DETAIL)
	Kit.ball(m, cf, "Flowers", 0.95, CF(-109.5, y + 5.0, 100.1), C.terracotta, M.fabric, DETAIL)
	-- the receptionist (operations post 13), seated behind the counter; a second station beside it
	local chair = Kit.officeChair(m, cf, Kit.place(-113.4, y, 98.4, "E"), seed + 1, { lite = true, arms = true, canTouch = false })
	opsPost(ctx, m, r, 13, V3(-113.8, 0, 95.6), V3(-108, 0, 98.4), chair, {
		{ name = "greet", stand = V3(-105.6, 0, 90.6), face = V3(-99, 0, 90) },
		{ name = "printer", stand = V3(-113.9, 0, 96.0), face = V3(-111.4, 0, 97.45), prop = "HotelKeyPrinter" },
	})
	Kit.officeChair(m, cf, Kit.place(-113.4, y, 101.7, "E"), seed + 9, { lite = true, arms = true, canTouch = false })
	-- back wall in front of the corridor glazing: walnut panel washed by an LED cove, the house sign
	-- (company name as a self-lit SurfaceGui line on a clear carrier over a brass rule and the words
	-- "GUEST HOUSE"), key-cubby rack
	Kit.part(m, cf, "ReceptionBackWall", V3(0.3, 12.85, 10.4), CF(-115.65, y + 6.425, 98.2), C.oakDark, M.wood)
	Kit.part(m, cf, "WallWashCove", V3(0.5, 0.15, 10.4), CF(-115.25, y + 12.7, 98.2), C.metal, M.metal, DETAIL)
	Kit.part(m, cf, "WallWash", V3(0.06, 0.05, 10.0), CF(-115.05, y + 12.6, 98.2), C.lightWarm, M.neon, DETAIL)
	local sign = Kit.part(m, cf, "LobbyHouseSign", V3(0.05, 1.7, 9.2), CF(-115.45, y + 10.75, 98.2), C.lightWarm, M.smooth, { detail = true, transparency = 1 })
	signText(sign, Enum.NormalId.Right, string.upper(ctx.company), nil, C.lightWarm, C.brass, 90)
	Kit.part(m, cf, "SignRule", V3(0.06, 0.07, 8.6), CF(-115.47, y + 9.75, 98.2), C.brass, M.metal, DETAIL)
	-- "GUEST HOUSE" in brass under the rule: one SurfaceGui line on a clear carrier (seen from inside the
	-- lobby only, so it needs no built letters), lit by the wall wash with a dark oak outline
	local word = Kit.part(m, cf, "LobbyHouseWord", V3(0.05, 1.5, 9.4), CF(-115.45, y + 8.85, 98.2), C.brass, M.smooth, { detail = true, transparency = 1 })
	local wordLabel = Kit.text(word, "GUEST HOUSE", { face = Enum.NormalId.Right, color = C.brass, light = 0.6, font = Enum.Font.BuilderSansBold, maxDistance = 90, pad = 0.04, pps = 100 })
	wordLabel.TextStrokeColor3 = C.oakDark
	wordLabel.TextStrokeTransparency = 0.55
	-- key-cubby rack: a brass grid of backlit cubbies, one per guest room with its number, a key tag in the
	-- free rooms' cubbies (one SurfaceGui on the rack panel)
	Kit.part(m, cf, "KeyRackFrame", V3(0.3, 2.5, 3.3), CF(-115.35, y + 6.1, 95.3), C.oakDark, M.wood, DETAIL)
	local rack = Kit.part(m, cf, "KeyRack", V3(0.3, 2.2, 3.0), CF(-115.25, y + 6.1, 95.3), C.brass, M.metal, DETAIL)
	local numbers: { number } = {}
	for _, g in Plan.rooms(ctx.tier) do
		local n = if g.annex == "hotel" and g.kind == "guestroom" then tonumber(string.match(g.name, "(%d+)$")) else nil
		if n then
			table.insert(numbers, n)
		end
	end
	table.sort(numbers)
	keyGrid(rack, numbers, seed + 13)
	for _, pz in { 97.7, 100.0, 102.3 } do
		local globe = globePendant(m, cf, -110.0, y, pz, 3.4)
		if pz == 100.0 then
			Kit.light(globe, "point", C.lightWarm, 16, 0.9)
		end
	end
	-- lounge at the south facade (guests wait here: Waiting activities); sofa with its back to the glass,
	-- armchairs either side of a stone coffee table, side table lamp, floor lamp, drum pendant
	rug(m, cf, CF(-107.8, y, 80.4), 13, 7.2, seed + 2)
	-- sheer curtain on a ceiling track inside the south glass behind the lounge: the Campus Arcade's back
	-- wall stands 3.4 studs outside it, so the seating looks at soft fabric instead of grey wall
	local sheer = Kit.part(m, cf, "SheerCurtain", V3(13.5, 12.7, 0.1), CF(-108.95, y + 6.45, 76.15), C.fabricSand:Lerp(C.white, 0.5), M.fabric, { detail = true, transparency = 0.4 })
	sheerPleats(sheer, Enum.NormalId.Back, 0.75, 50)
	Kit.part(m, cf, "CurtainTrack", V3(13.7, 0.12, 0.2), CF(-108.95, y + 12.84, 76.2), C.metal, M.metal, DETAIL)
	-- cream sofa with a matching pair of leather armchairs
	local seats = Kit.sofa(m, cf, Kit.place(-107.8, y, 78.0, "N"), 7.2, seed + 3, { color = C.fabricSand })
	for i, s in seats do
		local lp = cf:PointToObjectSpace(s.Position)
		activity(ctx, m, r, string.format("%s_Wait%d", r.id, i), "Waiting", "visitor", V3(lp.X, 0, lp.Z + 2.2), V3(lp.X, 0, lp.Z - 2), s)
	end
	Kit.part(m, cf, "CoffeeTable", V3(3.6, 0.2, 1.6), CF(-107.8, y + 1.3, 82.6), C.stoneDeep, M.marble)
	Kit.part(m, cf, "CoffeeTableBase", V3(2.6, 1.2, 0.9), CF(-107.8, y + 0.6, 82.6), C.oakDark, M.wood)
	Kit.part(m, cf, "Books", V3(1.0, 0.3, 0.7), CF(-108.7, y + 1.55, 82.5), C.blue, M.smooth, DETAIL)
	Kit.cylinder(m, cf, "Bowl", "y", 0.3, 0.9, CF(-106.9, y + 1.55, 82.7), C.brass, M.metal, DETAIL)
	for k, side in { -1, 1 } do
		local x = -107.8 + side * 5.8
		local chairSeat = Kit.loungeChair(m, cf, Kit.place(x, y, 81.2, if side < 0 then "E" else "W"), seed + 5, { color = C.leather })
		activity(ctx, m, r, string.format("%s_Wait%d", r.id, #seats + k), "Waiting", "visitor", V3(x - side * 2.2, 0, 81.2), V3(x, 0, 81.2), chairSeat)
	end
	-- side table (top y + 1.96) with a table lamp: brass stem standing on the top, shade on the stem
	Kit.cylinder(m, cf, "SideTable", "y", 0.12, 1.3, CF(-101.9, y + 1.9, 77.6), C.oakDark, M.wood)
	Kit.cylinder(m, cf, "SideTableStem", "y", 1.8, 0.25, CF(-101.9, y + 0.95, 77.6), C.metal, M.metal, DETAIL)
	Kit.cylinder(m, cf, "TableLampStem", "y", 0.6, 0.15, CF(-101.9, y + 2.26, 77.6), C.brass, M.metal, DETAIL)
	Kit.cylinder(m, cf, "TableLampShade", "y", 0.9, 0.9, CF(-101.9, y + 2.95, 77.6), C.lightWarm, M.neon, DETAIL)
	Kit.floorLamp(m, cf, CF(-114.6, y, 77.8), seed + 8)
	Kit.cylinder(m, cf, "PendantCable", "y", 3.4, 0.06, CF(-107.8, y + 11.3, 81.0), C.metal, M.metal, DETAIL)
	Kit.cylinder(m, cf, "DrumShade", "y", 1.1, 3.4, CF(-107.8, y + 9.05, 81.0), C.fabricSand, M.fabric, DETAIL)
	Kit.cylinder(m, cf, "DrumDiffuser", "y", 0.05, 3.0, CF(-107.8, y + 8.5, 81.0), C.lightWarm, M.neon, DETAIL)
	Kit.plant(m, cf, CF(-99.95, y, 77.7), "l", seed + 6) -- foliage clear of both facade glass lines
	-- north-east: concierge / travel desk under an artwork, luggage trolley parked by the door
	Kit.artwork(m, cf, Kit.place(-103.4, y, 103.5, "S"), 5.6, 3.6, seed + 10, { y = 7.2 })
	Kit.part(m, cf, "ConciergeDesk", V3(2.6, 3.5, 1.1), CF(-103.4, y + 1.75, 101.75), C.oak, M.wood)
	Kit.part(m, cf, "ConciergeTop", V3(2.9, 0.15, 1.4), CF(-103.4, y + 3.6, 101.7) * ANG(math.rad(-8), 0, 0), C.stoneDeep, M.marble)
	Kit.part(m, cf, "ConciergeTablet", V3(1.1, 0.06, 0.75), CF(-103.6, y + 3.72, 101.6) * ANG(math.rad(-8), 0, 0), C.screen, M.smooth, DETAIL)
	local plate = Kit.part(m, cf, "ConciergeSign", V3(2.2, 0.75, 0.06), CF(-103.4, y + 2.6, 101.17), C.brass, M.metal, DETAIL)
	signText(plate, Enum.NormalId.Front, "CONCIERGE", "City · Airport · Port Meridian", C.oakDark, C.oakDark, 50)
	Kit.part(m, cf, "BrochureRack", V3(1.0, 3.0, 0.5), CF(-101.4, y + 1.5, 101.9), C.oakDark, M.wood, DETAIL)
	for k, col in { C.terracotta, C.blue } do
		Kit.part(m, cf, "Brochure", V3(0.7, 0.8, 0.06), CF(-101.4, y + 0.6 + k * 1.0, 101.62) * ANG(math.rad(-12), 0, 0), col, M.smooth, DETAIL)
	end
	luggageTrolley(m, cf, -100.4, y, 96.7)
	Kit.plant(m, cf, CF(-99.6, y, 101.75), "l", seed + 7) -- planter and foliage clear of the north wall
	-- focal piece on the entrance axis (the first thing seen from the door): a free-standing oak-framed art
	-- screen in front of the corridor glass between door D2 and the back wall, a plant in front of it
	Kit.part(m, cf, "ArtScreenFrame", V3(0.12, 8.6, 3.5), CF(-115.74, y + 4.3, 91.05), C.oakDark, M.wood, DETAIL)
	local screenCanvas = Kit.part(m, cf, "ArtScreen", V3(0.04, 8.0, 2.9), CF(-115.66, y + 4.3, 91.05), C.fabricSand:Lerp(C.white, 0.6), M.fabric, DETAIL)
	screenArt(screenCanvas, Enum.NormalId.Right)
	Kit.plant(m, cf, CF(-114.3, y, 91.4), "m", seed + 11)
	-- door mat inside the entrance, a large rug on the walk from the door to the counter and the corridor
	-- (overlays at least 0.05 apart: no flicker at distance)
	Kit.part(m, cf, "EntranceMat", V3(2.6, 0.06, 6.6), CF(-99.7, y + 0.03, 90), C.fabricCharcoal, M.fabric, DETAIL)
	rug(m, cf, CF(-107.6, y, 89.9), 11, 8.4, seed, C.oakDark, C.carpetWarm)
end

local function breakfast(ctx: Ctx, r: Room)
	local m = fit(ctx, r)
	local cf = ctx.cf
	local y = floorY(r)
	local seed = Kit.hash(r.id)
	-- buffet along the north wall (west of the pantry door) with the coffee machine: juice and milk,
	-- a chafing dish, bread basket, fruit bowl, plates and cups under a sneeze guard and a menu board
	Kit.counter(m, cf, Kit.place(-110, y, 137.6, "S"), 9, seed, nil)
	local top = y + 3.65
	for k, x in { -112.6, -110.4, -108.2 } do
		Kit.part(m, cf, "BuffetTray", V3(1.8, 0.25, 1.2), CF(x, y + 3.78, 137.4), Kit.pick({ C.white, C.terracotta, C.sageLight }, seed + k), M.smooth, DETAIL)
	end
	Kit.cylinder(m, cf, "Juice", "y", 1.0, 0.5, CF(-114.05, top + 0.5, 137.0), C.statusBusy, M.glass, DETAIL)
	Kit.cylinder(m, cf, "Milk", "y", 1.0, 0.5, CF(-114.05, top + 0.5, 138.0), C.white, M.smooth, DETAIL)
	Kit.cylinder(m, cf, "ChafingDish", "x", 1.6, 0.9, CF(-112.6, top + 0.3, 137.4), C.metalSoft, M.metal, DETAIL)
	Kit.part(m, cf, "BreadBasket", V3(1.4, 0.4, 0.9), CF(-110.4, top + 0.45, 137.4), C.oak, M.wood, DETAIL)
	for k = -1, 1 do
		Kit.ball(m, cf, "BreadRoll", 0.5, CF(-110.4 + k * 0.42, top + 0.72, 137.4 + k * 0.08), C.oakLight, M.smooth, DETAIL)
	end
	Kit.cylinder(m, cf, "FruitBowl", "y", 0.35, 1.3, CF(-108.2, top + 0.42, 137.4), C.white, M.smooth, DETAIL)
	for k, col in { C.statusBad, C.statusBusy, C.statusGood, C.terracotta } do
		local a = k * PI / 2
		Kit.ball(m, cf, "Fruit", 0.45, CF(-108.2 + math.cos(a) * 0.3, top + 0.72, 137.4 + math.sin(a) * 0.3), col, M.smooth, DETAIL)
	end
	Kit.cylinder(m, cf, "PlateStack", "y", 0.45, 0.85, CF(-106.6, top + 0.22, 136.85), C.white, M.smooth, DETAIL)
	Kit.cylinder(m, cf, "CupStack", "y", 0.7, 0.45, CF(-105.85, top + 0.35, 137.1), C.white, M.smooth, DETAIL)
	Kit.part(m, cf, "SneezeGuard", V3(6.6, 0.08, 1.0), CF(-110.4, top + 1.85, 136.75) * ANG(math.rad(-20), 0, 0), C.glass, M.glass, { detail = true, transparency = 0.6 })
	for _, x in { -113.6, -107.2 } do
		Kit.part(m, cf, "GuardPost", V3(0.12, 1.75, 0.12), CF(x, top + 0.9, 137.15), C.metal, M.metal, DETAIL)
	end
	local menu = Kit.part(m, cf, "MenuBoard", V3(4.6, 1.5, 0.1), CF(-110.2, y + 7.4, 139.45), C.metal, M.metal, DETAIL)
	signText(menu, Enum.NormalId.Front, "BREAKFAST", "Daily 8:00 – 10:30 · coffee all day", C.lightWarm, C.white, 50)
	for _, x in { -112.6, -108.2 } do
		globePendant(m, cf, x, y, 137.2, 3.6)
	end
	local machineAt = CF(-106.6, y + 4.35, 137.9)
	local coffee = Kit.part(m, cf, "PantryCoffee", V3(1.0, 1.4, 1.0), machineAt, C.metal, M.metal)
	local brew = Kit.part(coffee, cf, "BrewLight", V3(0.3, 0.08, 0.04), machineAt * CF(0, 0.45, -0.52), C.metalSoft, M.neon, DETAIL)
	brew:SetAttribute("FxGlow", true)
	Kit.steamEmitter(coffee, "CoffeeSteam", 4, 0.25)
	Kit.fx(coffee, "steam,blink", { FxColor = C.statusBusy, FxRate = 2, FxSeconds = 5 })
	Kit.action(coffee, "prop", "Coffee machine", nil, { actionText = "Brew", maxDistance = 6 })
	for i, x in { -107.4, -105.6 } do
		activity(ctx, m, r, string.format("%s_Coffee%d", r.id, i), "Coffee", "kitchen", V3(x, 0, 134.6), V3(-106.6, 0, 137.9))
	end
	-- three tables with four seats (NPCs step in from the outer side of each chair) and a window bar
	-- with eight stools along the east facade: 20 Dining seats (TablePoint = where the plate goes)
	local n = 0
	local tx = -109.5
	for _, tz in { 109, 118.5, 128 } do
		Kit.meetingTable(m, cf, CF(tx, y, tz), "rect", 5, 3, seed + n)
		Kit.cylinder(m, cf, "BudVase", "y", 0.6, 0.3, CF(tx + 0.9, y + 3.45, tz), C.white, M.glass, DETAIL)
		Kit.ball(m, cf, "Bloom", 0.45, CF(tx + 0.9, y + 3.9, tz), Kit.pick({ C.terracotta, C.statusBusy, C.sageLight }, seed + n + 7), M.fabric, DETAIL)
		for _, dz in { -2.4, 2.4 } do
			for _, dx in { -1.25, 1.25 } do
				n += 1
				seatWithActivity(ctx, m, r, string.format("%s_Dining%d", r.id, n), "Dining", "kitchen", tx + dx, tz + dz, V3(tx + dx, y, tz), seed + 20 + n, nil, V3(if dx < 0 then -2.65 else 2.65, 0, 0))
			end
		end
	end
	Kit.part(m, cf, "WindowBar", V3(1.8, 0.2, 28), CF(-99.1, y + 3.5, 121), C.oak, M.wood) -- z 107..135 (plant corner free)
	for _, z in { 107.5, 120.5, 133.5 } do
		Kit.part(m, cf, "WindowBarLeg", V3(0.3, 3.4, 0.3), CF(-99.1, y + 1.7, z), C.metal, M.metal)
	end
	for k = 0, 7 do
		local z = 107.5 + k * (26 / 7)
		n += 1
		local stool = Kit.stool(m, cf, Kit.place(-101.3, y, z, "E"), seed + 40 + k, 3.0)
		local a = activity(ctx, m, r, string.format("%s_Dining%d", r.id, n), "Dining", "kitchen", V3(-103.3, 0, z), V3(-99.1, 0, z), stool)
		a:SetAttribute("TablePoint", cf:PointToWorldSpace(V3(-99.4, y + 3.7, z)))
	end
	Kit.artwork(m, cf, Kit.place(-107, y, 104.5, "N"), 6, 3.6, seed + 3, { y = 6.2 })
	Kit.plant(m, cf, CF(-99.5, y, 105.65), "m", seed + 4) -- foliage clear of the wall, the glass and the bar
	Kit.plant(m, cf, CF(-114.4, y, 106.0), "m", seed + 5)
end

local function pantry(ctx: Ctx, r: Room)
	local m = fit(ctx, r)
	local cf = ctx.cf
	local y = floorY(r)
	local seed = Kit.hash(r.id)
	Kit.kitchenette(m, cf, Kit.place(-108, y, 151.5, "S"), 12, seed, { coffeeName = "PrepCoffee" })
	Kit.part(m, cf, "PrepTable", V3(6, 0.2, 2.4), CF(-108.5, y + 3.0, 145.5), C.metalSoft, M.metal)
	for _, x in { -111.2, -105.8 } do
		Kit.part(m, cf, "PrepTableLeg", V3(0.2, 2.9, 2.2), CF(x, y + 1.45, 145.5), C.metal, M.metal)
	end
	Kit.part(m, cf, "Dishwasher", V3(2.4, 3.0, 2.2), CF(-99.4, y + 1.5, 149.5), C.metalSoft, M.metal)
	Kit.part(m, cf, "ServiceTrolley", V3(2.0, 3.2, 3.0), CF(-113.6, y + 1.6, 141.9), C.metal, M.metal)
end

local function housekeeping(ctx: Ctx, r: Room)
	local m = fit(ctx, r)
	local cf = ctx.cf
	local y = floorY(r)
	local seed = Kit.hash(r.id)
	for k, z in { 156, 163 } do
		Kit.rackShelf(m, cf, Kit.place(-98, y, z, "W"), 6, seed + k)
		for s = 0, 2 do
			Kit.part(m, cf, "LinenStack", V3(1.2, 0.9, 4.6), CF(-99.2, y + 1.5 + s * 1.9, z), C.white, M.fabric, DETAIL)
		end
	end
	for k, x in { -112, -108.6 } do
		Kit.part(m, cf, "WashingMachine", V3(2.8, 3.4, 2.6), CF(x, y + 1.7, 170.1), C.white, M.smooth)
		local led = Kit.part(m, cf, "WasherLight", V3(0.5, 0.15, 0.06), CF(x, y + 3.0, 168.77), C.statusGood, M.neon, DETAIL)
		Kit.fx(led, "blink", { FxColor = C.statusGood, FxRate = 1, FxIdle = "slow", PropId = "HotelWasher" .. k })
	end
	-- the housekeeping cart (job point "cart") and the housekeeper's post (operations post 14)
	Kit.part(m, cf, "HousekeepingCart", V3(2.2, 3.4, 4.0), CF(-107.4, y + 1.7, 157.8), C.metalSoft, M.metal)
	Kit.part(m, cf, "CartLinen", V3(1.8, 0.8, 3.4), CF(-107.4, y + 3.8, 157.8), C.white, M.fabric, DETAIL)
	local points: { JobPoint } = { { name = "cart", stand = V3(-109.8, 0, 157.8), face = V3(-107.4, 0, 157.8) } }
	-- room1..room4: beside the bed in the four ground-floor guest rooms
	local k = 0
	for _, g in Plan.roomsOnLevel(ctx.tier, 0) do
		if g.kind == "guestroom" and k < 4 then
			k += 1
			local F = roomFrame(g)
			local p = (F * CF(12, 0, 4.2)).Position -- at the foot of the bed
			local f = (F * CF(12, 0, 8)).Position
			table.insert(points, { name = "room" .. k, stand = V3(p.X, 0, p.Z), face = V3(f.X, 0, f.Z) })
		end
	end
	opsPost(ctx, m, r, 14, V3(-109.2, 0, 164.0), V3(-107.4, 0, 158.4), nil, points)
end

local function office(ctx: Ctx, r: Room)
	local m = fit(ctx, r)
	local cf = ctx.cf
	local y = floorY(r)
	local seed = Kit.hash(r.id)
	-- desk with its back to the south wall (the clerk faces the door), safe, luggage shelf on the facade
	Kit.desk(m, cf, Kit.place(-134.5, y, 106.2, "N"), "bench", seed)
	Kit.officeChair(m, cf, Kit.place(-134.5, y, 109.1, "S"), seed + 1, { lite = true })
	Kit.part(m, cf, "Safe", V3(2.2, 3.0, 2.2), CF(-139.6, y + 1.5, 104.4), C.metal, M.metal)
	Kit.rackShelf(m, cf, Kit.place(-141, y, 111.6, "E"), 6, seed + 3)
	for k = 0, 2 do
		Kit.part(m, cf, "Suitcase", V3(1.0, 2.2, 1.6), CF(-140.1, y + 1.2, 109.6 + k * 2), Kit.pick({ C.blue, C.terracotta, C.fabricCharcoal }, seed + k), M.smooth, DETAIL)
	end
end

local function corridor(ctx: Ctx, r: Room)
	local m = fit(ctx, r)
	local cf = ctx.cf
	local y = floorY(r)
	-- runner, wall sconces (Neon, no light objects), fire extinguisher and an exit sign
	Kit.part(m, cf, "Runner", V3(3.6, 0.04, r.z2 - r.z1 - 4), CF(-120, y + 0.02, (r.z1 + r.z2) / 2), C.carpetWarm, M.carpet, DETAIL)
	for z = r.z1 + 12, r.z2 - 6, 16 do
		Kit.part(m, cf, "Sconce", V3(0.2, 0.9, 0.5), CF(-123.4, y + 7.4, z), C.lightWarm, M.neon, DETAIL)
		Kit.part(m, cf, "Sconce", V3(0.2, 0.9, 0.5), CF(-116.6, y + 7.4, z + 8), C.lightWarm, M.neon, DETAIL)
	end
	Kit.cylinder(m, cf, "FireExtinguisher", "y", 1.6, 0.6, CF(-123.2, y + 0.9, r.z2 - 2.2), C.statusBad, M.smooth, DETAIL)
	if r.level == 0 then
		local sign = Kit.part(m, cf, "ExitSign", V3(2.4, 0.8, 0.12), CF(-120, y + 11, r.z2 - 0.2), C.statusGood, M.neon, DETAIL)
		Kit.text(sign, "EXIT · TERRACE", { face = Enum.NormalId.Front, color = C.white, maxDistance = 50, pad = 0.08 })
	end
	Kit.plant(m, cf, CF(-117.6, y, r.z2 - 1.6), "m", Kit.hash(r.id))
end

---------------------------------------------------------------------------------------------
-- Level 1: workshop room
---------------------------------------------------------------------------------------------
local function workshop(ctx: Ctx, r: Room)
	local m = fit(ctx, r)
	local cf = ctx.cf
	local y = floorY(r)
	local seed = Kit.hash(r.id)
	local cx, cz = -107.5, 90
	Kit.meetingTable(m, cf, CF(cx, y, cz) * ANG(0, PI / 2, 0), "boat", 15, 4.0, seed)
	local n = 0
	local centre = V3(cx, y, cz)
	for _, side in { -1, 1 } do
		for _, z in { 84.6, 88.2, 91.8, 95.4 } do
			n += 1
			seatWithActivity(ctx, m, r, string.format("%s_Meet%d", r.id, n), "Meeting", "growth", cx + side * 3.4, z, V3(cx, y, z), seed + n, { meetingRoom = "HotelWorkshop" }, V3(side * 2.4, 0, 1.6))
		end
	end
	for _, e in { -1, 1 } do
		n += 1
		seatWithActivity(ctx, m, r, string.format("%s_Meet%d", r.id, n), "Meeting", "growth", cx, cz + e * 9.6, centre, seed + n, { meetingRoom = "HotelWorkshop" }, V3(2.6, 0, e * 0.8))
	end
	Kit.whiteboard(m, cf, Kit.place(-111, y, 103.5, "S"), 7, "CUSTOMER WORKSHOP\n- goals\n- data we need\n- pilot plan", seed + 20, { y = 5.6 })
	Kit.tvScreen(m, cf, Kit.place(-102.4, y, 103.5, "S"), 6, "meeting", ctx.accent, { y = 6.0, name = "WorkshopScreen" })
	Kit.plant(m, cf, CF(-99.8, y, 77.8), "l", seed + 22)
	Kit.plant(m, cf, CF(-114.6, y, 77.8), "m", seed + 23)
end

---------------------------------------------------------------------------------------------
-- Stair (both storeys, built with the ground-floor stair room)
---------------------------------------------------------------------------------------------
local function pitch(dy: number, dz: number): (number, number, number, number)
	if dz < 0 then
		dy, dz = -dy, -dz
	end
	local a = -math.atan2(dy, dz)
	return a, math.cos(a), math.sin(a), math.sqrt(dy * dy + dz * dz)
end

-- Inclined part across x1..x2 whose top face runs from (yA, zA) to (yB, zB).
local function slopeTop(m: Model, cf: CFrame, name: string, x1: number, x2: number, yA: number, zA: number, yB: number, zB: number, t: number, color: Color3, mat: Enum.Material, opts: Kit.Opts?): Part
	local a, ny, nz, len = pitch(yB - yA, zB - zA)
	local at = CF((x1 + x2) / 2, (yA + yB) / 2 - ny * t / 2, (zA + zB) / 2 - nz * t / 2) * ANG(a, 0, 0)
	return Kit.part(m, cf, name, V3(x2 - x1, t, len), at, color, mat, opts)
end

local function flight(m: Model, cf: CFrame, x1: number, x2: number, yA: number, zA: number, yB: number, zB: number)
	local steps = 12
	-- invisible smooth ramp (what Humanoids and pathfinding walk on) under visual treads
	local ramp = slopeTop(m, cf, "StairRamp", x1, x2, yA, zA, yB, zB, 0.4, C.stone, M.stone)
	ramp.Transparency = 1
	ramp.CanTouch = false
	ramp.CastShadow = false
	ramp:SetAttribute("StairRamp", true)
	local dir = if zB > zA then 1 else -1
	local rise = (yB - yA) / steps
	local going = math.abs(zB - zA) / steps
	for i = 1, steps - 1 do
		local top = yA + rise * i
		local za, zb = zA + dir * going * i, zA + dir * going * (i + 1)
		Kit.part(m, cf, "StairTread", V3(x2 - x1, rise + 0.3, going), CF((x1 + x2) / 2, top - (rise + 0.3) / 2, (za + zb) / 2), C.stone, M.stone, DETAIL)
	end
	slopeTop(m, cf, "StairSoffit", x1, x2, yA - rise, zA, yB - rise, zB, 0.8, C.interior, M.plaster, DETAIL)
	-- wall-side handrail along the walking line
	local a, _, _, len = pitch(yB - yA, zB - zA)
	local hx = if x1 < -136 then x1 + 0.2 else x2 - 0.2
	Kit.part(m, cf, "StairHandrail", V3(0.2, 0.2, len - 1.2), CF(hx, (yA + yB) / 2 + 3.2, (zA + zB) / 2) * ANG(a, 0, 0), C.oak, M.wood, DETAIL)
end

local function stair(ctx: Ctx, r: Room)
	if r.level ~= 0 then
		return
	end
	local m = fit(ctx, r)
	local cf = ctx.cf
	local L = Plan.HOTEL_STAIR_LAYOUT
	local y0, y1 = Plan.levelY(0), Plan.levelY(1)
	local mid = (y0 + y1) / 2
	local Af, Bf, dv = L.flightA, L.flightB, L.divider
	flight(m, cf, Af.x1, Af.x2, y0, Af.z1, mid, Af.z2)
	flight(m, cf, Bf.x1, Bf.x2, mid, Bf.z2, y1, Bf.z1)
	Kit.part(m, cf, "StairLanding", V3(L.inner.x2 - L.inner.x1, 1, L.midLanding.z2 - L.midLanding.z1), CF((L.inner.x1 + L.inner.x2) / 2, mid - 0.5, (L.midLanding.z1 + L.midLanding.z2) / 2), C.stone, M.stone)
	-- divider wall between the flights (to the roof slab), guard over the flight-A void on level 1
	Kit.part(m, cf, "StairDivider", V3(dv.x2 - dv.x1, Plan.HOTEL.roofY - 1, Af.z2 - Af.z1), CF((dv.x1 + dv.x2) / 2, (Plan.HOTEL.roofY - 1) / 2, (Af.z1 + Af.z2) / 2), C.interior, M.plaster)
	local gz = Af.z1 - 0.15
	Kit.part(m, cf, "StairGuardGlass", V3(dv.x1 - L.inner.x1, 3.5, 0.12), CF((L.inner.x1 + dv.x1) / 2, y1 + 1.75, gz), C.glass, M.glass, { transparency = A.railTransparency, castShadow = false })
	Kit.part(m, cf, "StairGuardRail", V3(dv.x1 - L.inner.x1, 0.2, 0.2), CF((L.inner.x1 + dv.x1) / 2, y1 + 3.6, gz), C.metal, M.metal)
	-- level signs on the divider end facing the front landing, one light over the mid landing
	for level = 0, 1 do
		local sign = Kit.part(m, cf, "StairSign", V3(2.2, 2.6, 0.12), CF((dv.x1 + dv.x2) / 2, Plan.levelY(level) + 8.4, Af.z1 - 0.07), C.metal, M.metal, DETAIL)
		Kit.text(sign, if level == 0 then "G\nLobby · Breakfast" else "1\nRooms · Workshop", { face = Enum.NormalId.Front, color = C.white, maxDistance = 50, pad = 0.1 })
	end
	local lamp = Kit.part(m, cf, "StairLight", V3(0.5, 1.4, 0.12), CF((dv.x1 + dv.x2) / 2, mid + 6.8, L.midLanding.z1 + 0.07), C.lightWarm, M.neon, DETAIL)
	Kit.light(lamp, "point", C.lightWarm, 20, 0.9)
end

---------------------------------------------------------------------------------------------
-- Entry point
---------------------------------------------------------------------------------------------
local KITS: { [string]: (Ctx, Room) -> () } = {
	hotel_lobby = lobby,
	hotel_breakfast = breakfast,
	hotel_pantry = pantry,
	hotel_service = housekeeping,
	hotel_office = office,
	hotel_corridor = corridor,
	hotel_workshop = workshop,
	hotel_stair = stair,
	guestroom = guestRoom,
}

function Hotel.build(ctx: any)
	if not Plan.hasHotel(ctx.tier) then
		return
	end
	for _, r in Plan.rooms(ctx.tier) do
		local kit = if r.annex == "hotel" then KITS[r.kind] else nil
		if kit then
			local ok, err = pcall(function(): any
				kit(ctx :: Ctx, r)
				return nil
			end)
			if not ok then
				warn(`[RoomKitsHotel] {r.id} ({r.kind}) failed: {err}`)
			end
		end
	end
end

return Hotel
