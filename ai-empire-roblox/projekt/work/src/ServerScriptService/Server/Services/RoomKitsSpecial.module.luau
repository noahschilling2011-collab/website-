--!strict
-- RoomKitsSpecial: fit-out of the ground floor and B1 (SPEC §10-§12): reception hall, staff atrium,
-- visitor lounge, showroom, project room, compute operations, First AI studio, IT desk, House Kitchen
-- café, kitchen, deliveries, mailroom, underground garage, data hall and the technical rooms, plus
-- the twelve operations posts. InteriorDesign owns walls, doors, floors, ceilings, nameplates and
-- cameras; everything here goes into a "Fitout" model inside ctx.rooms[room.id] (the fridge door goes
-- to Office.Doors, rack blades to Office.Blades). Building-local coordinates through ctx.cf.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Collection = game:GetService("CollectionService")
local Plan = require(ReplicatedStorage.Shared.Config.BuildingPlan)
local CampusConfig = require(ReplicatedStorage.Shared.Config.CampusConfig)
local Kit = require(script.Parent.ArchKit)

type Room = Plan.Room
type Shared = { blade: number, lunch: number }
type R = {
	ctx: any,
	room: Room,
	m: Model, -- the room's Fitout model
	cf: CFrame,
	y: number, -- finished floor (level Y + Kit.FINISH)
	ceil: number, -- suspended ceiling underside (level Y + 13)
	level: number,
	owner: number,
	accent: Color3,
	seed: number,
	s: Shared,
}

local Special = {}
local C, M = Kit.C, Kit.M
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local PI = math.pi
local DETAIL: Kit.Opts = { detail = true }
local GLASS: Kit.Opts = { transparency = Kit.A.glassTransparency, castShadow = false }
local GLASS_DECOR: Kit.Opts = { transparency = Kit.A.glassTransparency, castShadow = false, canCollide = false, canTouch = false, canQuery = false }

---------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------
local function box(r: R, name: string, size: Vector3, lcf: CFrame, color: Color3, mat: Enum.Material?, opts: Kit.Opts?): Part
	return Kit.part(r.m, r.cf, name, size, lcf, color, mat, opts)
end

local function cyl(r: R, name: string, axis: string, len: number, dia: number, lcf: CFrame, color: Color3, mat: Enum.Material?, opts: Kit.Opts?): Part
	return Kit.cylinder(r.m, r.cf, name, axis, len, dia, lcf, color, mat, opts)
end

-- Floor-level frame at (x, z); front (-Z) faces "N"/"S"/"E"/"W" or a yaw in degrees.
local function at(r: R, x: number, z: number, front: (string | number)?): CFrame
	return Kit.place(x, r.y, z, front)
end

-- Point h above the finished floor (no rotation).
local function pt(r: R, x: number, h: number, z: number): CFrame
	return CF(x, r.y + h, z)
end

-- Yaw (degrees) whose front (-Z) points along (dx, dz).
local function yawTo(dx: number, dz: number): number
	return math.deg(math.atan2(-dx, -dz))
end

local function label(part: BasePart, text: string, opts: Kit.TextOpts?): TextLabel
	return Kit.text(part, text, opts)
end

-- Thin sign plate (front = -Z of lcf) with one text label; decorative unless solid == true.
local function plate(r: R, name: string, w: number, h: number, lcf: CFrame, text: string, bg: Color3, fg: Color3?, solid: boolean?): Part
	local p = box(r, name, V3(w, h, 0.12), lcf, bg, if bg == C.brass or bg == C.metal then M.metal else M.smooth, if solid then nil else DETAIL)
	label(p, text, { color = fg or C.white, light = 0.3, maxDistance = 70 })
	return p
end

-- Sign hung from the ceiling (building-local height `top`) by two rods, readable from both sides.
local function hanging(r: R, name: string, w: number, h: number, lcf: CFrame, top: number, text: string, bg: Color3, fg: Color3?): Part
	local p = plate(r, name, w, h, lcf, text, bg, fg)
	label(p, text, { face = Enum.NormalId.Back, color = fg or C.white, light = 0.3, maxDistance = 70, guiName = "SurfaceGuiBack" })
	local rise = top - (lcf.Position.Y + h / 2)
	if rise > 0.05 then
		for _, sx in { -1, 1 } do
			box(r, "HangerRod", V3(0.08, rise, 0.08), lcf * CF(sx * (w / 2 - 0.4), h / 2 + rise / 2, 0), C.metal, M.metal, DETAIL)
		end
	end
	return p
end

-- Soft stripe pattern (UIGradient) on one face: perforated tiles, grilles, battery cells.
local function stripes(part: BasePart, face: Enum.NormalId, a: Color3, b: Color3, count: number, rotation: number)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Pattern"
	gui.Face = face
	gui.CanvasSize = Vector2.new(400, 400)
	gui.LightInfluence = 0.6
	gui.MaxDistance = 90
	gui.Parent = part
	local f = Instance.new("Frame")
	f.Name = "Field"
	f.Size = UDim2.fromScale(1, 1)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = C.white
	f.Parent = gui
	local g = Instance.new("UIGradient")
	local keys: { ColorSequenceKeypoint } = {}
	local n = math.clamp(count, 2, 20)
	for k = 0, n - 1 do
		table.insert(keys, ColorSequenceKeypoint.new(k / (n - 1), if k % 2 == 0 then a else b))
	end
	g.Color = ColorSequence.new(keys)
	g.Rotation = rotation
	g.Parent = f
end

-- Interaction point (SPEC §5/§10). stand / facing: building-local X/Z (Y ignored).
local function activity(r: R, id: string, kind: string, dept: string, stand: Vector3, facing: Vector3?, seat: Seat?, meeting: string?, extra: { [string]: any }?): Model
	return Kit.activity(r.m, r.cf, id, kind, dept, if kind == "Service" then "support" else "any", CF(stand.X, r.y + 2.8, stand.Z), r.level, r.owner, seat, {
		roomAccess = r.room.access,
		homeRoom = r.room.id,
		facing = if facing then V3(facing.X, r.y + 2.8, facing.Z) else nil,
		meetingRoom = meeting,
		attributes = extra,
	})
end

-- Job point of an operations post (PROPFX_CONTRACT §9): building-local stand / look-at X/Z, optional PropId.
type JobPoint = { name: string, stand: Vector3, face: Vector3, prop: string?, pose: string? }
local function jp(name: string, stand: Vector3, face: Vector3, prop: string?, pose: string?): JobPoint
	return { name = name, stand = stand, face = face, prop = prop, pose = pose }
end

-- Operations staff post OperationsStation<i> (Service, operations, support, OpsIndex = i). Job points
-- become world-space attributes JobPoint_<name> / JobFace_<name> / JobProp_<name> on the post.
local function opsPost(r: R, i: number, stand: Vector3, facing: Vector3, seat: Seat?, points: { JobPoint }?, levelY: number?): Model
	local post = activity(r, "OperationsStation" .. i, "Service", "operations", stand, facing, seat, nil, { OpsIndex = i })
	local y = (levelY or r.y) + 2.8
	local list: { JobPoint } = points or {}
	for _, p in list do
		post:SetAttribute("JobPoint_" .. p.name, r.cf:PointToWorldSpace(V3(p.stand.X, y, p.stand.Z)))
		post:SetAttribute("JobFace_" .. p.name, r.cf:PointToWorldSpace(V3(p.face.X, y, p.face.Z)))
		if p.prop then
			post:SetAttribute("JobProp_" .. p.name, p.prop)
		end
		if p.pose then
			post:SetAttribute("JobPose_" .. p.name, p.pose) -- overrides the job step's pose at this point
		end
	end
	return post
end

-- PropFx root (design/PROPFX_CONTRACT.md).
local function fx(inst: Instance, kinds: string, attrs: { [string]: any }?): Instance
	return Kit.fx(inst, kinds, attrs)
end

-- NPC-controlled swivel chair for a seated operations post.
local function opsChair(r: R, lcf: CFrame, seed: number): Seat
	return Kit.officeChair(r.m, r.cf, lcf, seed, { lite = true, arms = true, canTouch = false })
end

-- Café chair on a pedestal (4 parts), sitter faces -Z of lcf.
local function cafeChair(r: R, lcf: CFrame, seed: number): Seat
	local cover = Kit.pick({ C.oak, C.oakLight, C.fabricSand, C.sage, C.leather, C.oakDark }, seed)
	local mat = if cover == C.leather then M.leather elseif cover == C.fabricSand or cover == C.sage then M.fabric else M.wood
	local seat = Kit.seat(r.m, r.cf, "Seat", V3(1.9, 0.3, 1.8), lcf * CF(0, 1.85, 0), cover, mat)
	box(r, "ChairBack", V3(1.9, 1.6, 0.2), lcf * CF(0, 2.8, 0.82) * ANG(math.rad(6), 0, 0), cover, mat)
	cyl(r, "ChairStem", "y", 1.65, 0.24, lcf * CF(0, 0.88, 0), C.metal, M.metal, DETAIL)
	cyl(r, "ChairFoot", "y", 0.08, 1.4, lcf * CF(0, 0.04, 0), C.metal, M.metal, DETAIL)
	return seat
end

-- Lunch seat: the Seat becomes the child of a Dining activity LunchSeat<n> (players sit by touch).
-- TableY = world height of the table top (the client puts the employee's meal plate there).
local function dining(r: R, seat: Seat, stand: Vector3, tableCentre: Vector3, top: number?)
	seat.CanTouch = true
	r.s.lunch += 1
	activity(r, "LunchSeat" .. r.s.lunch, "Dining", "kitchen", stand, tableCentre, seat, nil, { TableY = r.cf:PointToWorldSpace(Vector3.new(tableCentre.X, r.y + (top or 3.15), tableCentre.Z)).Y })
end

-- Spinning fan behind a ring; lcf = fan centre, local Z = fan axis (client spins about local Z).
local function fan(r: R, lcf: CFrame, dia: number)
	cyl(r, "FanRing", "z", 0.12, dia, lcf, C.metal, M.metal, DETAIL)
	for k = 0, 1 do
		local f = box(r, "ClusterFan", V3(dia - 0.35, 0.3, 0.06), lcf * CF(0, 0, -0.1) * ANG(0, 0, k * PI / 2), C.metalSoft, M.metal, DETAIL)
		f:SetAttribute("FanHome", f.CFrame)
		Collection:AddTag(f, "ClusterFan")
		-- cooling fans always turn slowly and speed up while the company trains
		fx(f, "spin", { FxAxis = "z", FxRate = 8, FxGate = "Training", FxIdle = "slow" })
	end
end

-- Precision air-conditioning unit (CRAH) against a wall; lcf on the wall surface, front -Z.
local function crah(r: R, lcf: CFrame, label_: string, w: number, h: number)
	box(r, "CRAHUnit", V3(w, h, 3.0), lcf * CF(0, h / 2, -1.5), C.white, M.smooth)
	local grille = box(r, "CRAHGrille", V3(w - 0.6, h * 0.42, 0.06), lcf * CF(0, 0.4 + h * 0.21, -3.03), C.metalSoft, M.metal, DETAIL)
	stripes(grille, Enum.NormalId.Front, C.metalSoft, C.screen, 18, 90)
	for _, fx in { -w / 4, w / 4 } do
		fan(r, lcf * CF(fx, h - 1.7, -3.1), math.min(2.6, w / 2 - 0.4))
	end
	local d = box(r, "CRAHDisplay", V3(1.3, 0.7, 0.05), lcf * CF(0, h * 0.6, -3.05), C.screen, M.smooth, DETAIL)
	label(d, label_, { color = C.statusGood, light = 0 })
end

-- Overhead strut with two rods up to building-local height `top` (holds trays and busways).
local function strut(r: R, x1: number, x2: number, y: number, z: number, top: number)
	box(r, "Strut", V3(x2 - x1, 0.2, 0.25), CF((x1 + x2) / 2, y, z), C.metalSoft, M.metal, DETAIL)
	local h = top - (y + 0.1)
	if h > 0.05 then
		for _, x in { x1 + 0.2, x2 - 0.2 } do
			box(r, "HangerRod", V3(0.1, h, 0.1), CF(x, y + 0.1 + h / 2, z), C.metal, M.metal, DETAIL)
		end
	end
end

---------------------------------------------------------------------------------------------
-- G · Reception hall (public, double height)
---------------------------------------------------------------------------------------------
local function lobby(r: R)
	local ctx = r.ctx
	local y = r.y
	-- Curved reception desk from segments: oak front, stone ledge, oak worktop behind.
	local cx, cz, R0 = -26, -33, 13
	local th1, th2, n = math.rad(-27), math.rad(27), 8
	local d = (th2 - th1) / n
	local function frame(th: number): CFrame
		return CF(cx, y, cz) * ANG(0, math.atan2(-math.cos(th), -math.sin(th)), 0)
	end
	local function chord(rad: number): number
		return 2 * rad * math.sin(d / 2) + 0.05
	end
	for i = 1, n do
		local f = frame(th1 + (i - 0.5) * d)
		box(r, "DeskFront", V3(chord(R0), 3.3, 0.8), f * CF(0, 1.95, -(R0 - 0.4)), C.oak, M.wood)
		box(r, "DeskKick", V3(chord(R0 - 0.3), 0.3, 0.6), f * CF(0, 0.15, -(R0 - 0.6)), C.metal, M.metal)
		box(r, "DeskLedge", V3(chord(R0 + 0.15), 0.15, 1.35), f * CF(0, 3.675, -(R0 - 0.525)), C.stone, M.marble)
		box(r, "DeskWorktop", V3(chord(R0 - 0.8), 0.2, 2.0), f * CF(0, 3.05, -(R0 - 1.8)), C.oakLight, M.wood)
		box(r, "DeskBand", V3(chord(R0 + 0.02), 0.1, 0.05), f * CF(0, 3.3, -(R0 + 0.01)), C.brass, M.metal, DETAIL)
	end
	for _, th in { th1, th2 } do
		box(r, "DeskEnd", V3(0.3, 3.6, 2.8), frame(th) * CF(0, 1.8, -(R0 - 1.4)), C.oak, M.wood)
	end
	-- visitor-facing reception display set into the desk front
	local screen = Kit.screen(r.m, r.cf, "ReceptionScreen", V3(3.2, 1.7, 0.1), frame(0) * CF(0, 1.95, -(R0 + 0.08)), "reception", r.accent)
	Kit.prompt(screen, "Reception", r.owner, "empire")
	-- card printer on the ledge (founder replaces employee cards here; receptionist 1 prints visitor
	-- badges on it: PropFx paper + slot light)
	local f2 = frame(th1 + 0.5 * d)
	local printer = box(r, "CardPrinter", V3(1.5, 0.7, 1.0), f2 * CF(0, 4.1, -(R0 - 0.62)), C.metal, M.metal)
	local slot = Kit.part(printer, r.cf, "CardSlot", V3(0.9, 0.06, 0.05), f2 * CF(0, 4.2, -(R0 - 0.1)), C.statusGood, M.neon, DETAIL)
	slot:SetAttribute("FxGlow", true)
	fx(printer, "paper,blink", { FxColor = C.statusBusy, FxRate = 3, FxSeconds = 3, PropId = "CardPrinter" })
	Kit.action(printer, "card", "Replace employee card", nil, { ownerUserId = r.owner, actionText = "Print card", maxDistance = 10 })
	-- two receptionists (operations posts 1 and 2) behind the desk: they type, stand up to greet
	-- visitors coming in through the entrance, receptionist 1 prints badges
	local entrance = V3(0, 0, -44)
	for k, th in { -0.17, 0.17 } do
		local f = frame(th)
		local seat = opsChair(r, f * CF(0, 0, -(R0 - 4.3)), r.seed + k)
		local mon = f * CF(0, 3.15, -(R0 - 1.35)) * ANG(0, PI, 0)
		box(r, "Monitor", V3(2.3, 1.4, 0.12), mon * CF(0, 1.15, 0), C.screen, M.smooth)
		box(r, "MonitorStand", V3(0.3, 0.45, 0.4), mon * CF(0, 0.22, 0.12), C.metal, M.metal, DETAIL)
		local stand = (frame(if k == 1 then -0.4 else 0.4) * CF(0, 0, -(R0 - 4.6))).Position
		local points: { JobPoint } = { jp("greet", stand, entrance) }
		if k == 1 then
			table.insert(points, jp("printer", stand, r.cf:PointToObjectSpace(printer.Position), "CardPrinter"))
		end
		opsPost(r, k, stand, (f * CF(0, 0, -R0)).Position, seat, points)
	end
	-- Free-standing stone logo wall behind the desk (PlotService writes the company name).
	local wallAt = at(r, -22.5, -33, "E")
	local sign = box(r, "ReceptionSign", V3(14, 12, 1), wallAt * CF(0, 6, 0), C.stone, M.stone)
	local t = label(sign, "WELCOME TO\n" .. ctx.company, { color = C.brass, light = 0.4, maxDistance = 140 })
	t.Position = UDim2.fromScale(0.1, 0.13)
	t.Size = UDim2.fromScale(0.8, 0.32)
	box(r, "SignShadowGap", V3(14.04, 0.25, 1.04), wallAt * CF(0, 0.125, 0), C.metal, M.metal, DETAIL)
	box(r, "SignInset", V3(11.6, 4.6, 0.06), wallAt * CF(0, 8.25, -0.53), C.stoneDeep, M.stone, DETAIL)
	box(r, "SignAccent", V3(9.0, 0.12, 0.08), wallAt * CF(0, 5.75, -0.54), r.accent, M.neon, DETAIL)
	box(r, "SignCap", V3(14.04, 0.12, 1.04), wallAt * CF(0, 12.04, 0), C.brass, M.metal, DETAIL)
	Kit.artwork(r.m, r.cf, at(r, -23, -33, "W"), 6, 4, r.seed + 3, { y = 6.2 })
	local up = box(r, "LogoUplight", V3(1.2, 0.12, 0.6), pt(r, -20.6, 0.06, -33), C.metal, M.metal, DETAIL)
	Kit.light(up, "spot", "warm", 16, 1.1, Enum.NormalId.Top)
	-- Media wall hung from the level-1 bridge above the speed gates (company live wall).
	box(r, "MediaWallFrame", V3(12.6, 7.5, 0.3), CF(0, 10.85, -24.45), C.metal, M.metal)
	box(r, "MediaWallBracket", V3(12.6, 0.9, 0.15), CF(0, 14.9, -24.22), C.metal, M.metal)
	local live = Kit.screen(r.m, r.cf, "CompanyLiveWall", V3(12, 7.0, 0.1), CF(0, 10.85, -24.66), "lobby", r.accent)
	Kit.prompt(live, "Company overview", r.owner, "empire")
	-- Building directory totem left of the entrance: static directory + live directory screen.
	local totem = at(r, -8.5, -41, "S")
	box(r, "DirectoryTotem", V3(4.8, 11.6, 1), totem * CF(0, 5.8, 0), C.stoneDeep, M.stone)
	local lines = { "HEADQUARTERS" }
	for level = Plan.roofLevel(ctx.tier), -1, -1 do
		table.insert(lines, Plan.floorTitle(ctx.tier, level))
	end
	Kit.wayfinding(r.m, r.cf, totem * CF(0, 0, -0.5), lines, { name = "BuildingDirectory", h = 0.55 })
	Kit.screen(r.m, r.cf, "DirectoryScreen", V3(4.2, 2.5, 0.1), totem * CF(0, 9.95, -0.56), "directory", r.accent)
	-- Lobby security desk beside the speed gates (operations post 3).
	local ledge, panel = Kit.receptionDesk(r.m, r.cf, at(r, 14.3, -24.25, "W"), 4.6, r.seed + 5)
	local _ = ledge
	label(panel, "SECURITY", { color = C.white, light = 0.3 })
	for _, dz in { -1.1, 1.1 } do
		box(r, "Monitor", V3(1.9, 1.2, 0.12), at(r, 15.3, -24.25 + dz, "E") * CF(0, 4.2, 0), C.screen, M.smooth)
	end
	local guard = opsChair(r, at(r, 17.7, -24.25, "W"), r.seed + 6)
	-- patrol loop through the open hall (points keep clear of the desk, benches, totem and trees)
	local patrol = { V3(18.4, 0, -28.5), V3(5, 0, -27.5), V3(-7, 0, -34.5), V3(2, 0, -40), V3(14, 0, -40.5) }
	local looks = { V3(0, 0, -24), V3(-14, 0, -33), V3(0, 0, -44), V3(14, 0, -46), V3(0, 0, -30) }
	local lobbyPoints: { JobPoint } = {}
	for i, p in patrol do
		table.insert(lobbyPoints, jp("patrol" .. i, p, looks[i]))
	end
	opsPost(r, 3, V3(18.4, 0, -21.6), V3(10, 0, -24.25), guard, lobbyPoints)
	-- Visitor waiting: tree planter ringed by benches, near the gates.
	local pc = at(r, 10.5, -33.5)
	Kit.plant(r.m, r.cf, pc, "tree", r.seed + 7)
	for k = 0, 3 do
		Kit.bench(r.m, r.cf, pc * ANG(0, k * PI / 2, 0) * CF(0, 0, -2.6), 3.6, r.seed + k, { color = C.oak })
	end
	-- Tall trees in the glazed front corners of the hall.
	for k, x in { -19.5, 19.5 } do
		local t = at(r, x, -46)
		box(r, "Planter", V3(3.2, 2.0, 3.2), t * CF(0, 1.0, 0), C.stoneDeep, M.stone)
		box(r, "Soil", V3(2.9, 0.1, 2.9), t * CF(0, 2.05, 0), C.soil, M.grass, DETAIL)
		cyl(r, "Trunk", "y", 9.5, 0.45, t * CF(0, 2.0 + 4.75, 0), C.oakDark, M.wood)
		for i, h in { 8.6, 10.4, 12.0, 13.4 } do
			local off = (i % 2) * 0.3 - 0.15
			Kit.ball(r.m, r.cf, "Canopy", 3.4 - i * 0.25, t * CF(off * k, h, -off), if i % 2 == 0 then C.foliageLight else C.foliage, M.leafy, DETAIL)
		end
	end
	local glow = box(r, "HallGlow", V3(0.4, 0.2, 0.4), CF(0, 14.8, -24.6), C.metal, M.metal, DETAIL)
	Kit.light(glow, "point", "warm", 30, 0.55)
end

---------------------------------------------------------------------------------------------
-- G · Atrium (staff side behind the gates, void up to the skylight)
---------------------------------------------------------------------------------------------
local function atrium(r: R)
	local c = at(r, 0, 10)
	-- Stone planter with a real tree and timber benches on all four sides.
	box(r, "TreePlanter", V3(8, 2.0, 8), c * CF(0, 1.0, 0), C.stoneDeep, M.stone)
	box(r, "PlanterCoping", V3(8.4, 0.2, 8.4), c * CF(0, 2.1, 0), C.stone, M.stone)
	box(r, "Soil", V3(7.4, 0.1, 7.4), c * CF(0, 2.22, 0), C.soil, M.grass, DETAIL)
	for k = 0, 3 do
		Kit.bench(r.m, r.cf, c * ANG(0, k * PI / 2, 0) * CF(0, 0, -5.0), 7.2, r.seed + k, { color = C.oak })
	end
	cyl(r, "Trunk", "y", 15, 1.3, c * CF(0, 2.2 + 7.5, 0), C.oakDark, M.wood)
	for k = 0, 2 do
		local a = k * 2 * PI / 3 + 0.4
		box(r, "Branch", V3(0.5, 6, 0.5), c * CF(math.cos(a) * 1.6, 13.5, math.sin(a) * 1.6) * ANG(0, -a, 0) * ANG(0, 0, -0.55), C.oakDark, M.wood, DETAIL)
	end
	local canopy = { { 0, 18.5, 0, 9 }, { 3, 16, 1, 7 }, { -2.6, 16.5, 2, 7 }, { 0.5, 15.5, -3, 7.5 }, { -1.5, 20.5, -1, 6 }, { 2, 19.5, 2.5, 5.5 } }
	for i, b in canopy do
		Kit.ball(r.m, r.cf, "Canopy", b[4], c * CF(b[1], b[2], b[3]), if i % 2 == 0 then C.foliageLight else C.foliage, M.leafy, DETAIL)
	end
	for k = 0, 3 do
		local a = k * PI / 2 + PI / 4
		Kit.ball(r.m, r.cf, "Shrub", 2.2, c * CF(math.cos(a) * 2.4, 2.8, math.sin(a) * 2.4), if k % 2 == 0 then C.foliage else C.foliageLight, M.leafy, DETAIL)
	end
	local up = box(r, "TreeUplight", V3(0.8, 0.15, 0.8), c * CF(2.6, 2.3, 0), C.metal, M.metal, DETAIL)
	Kit.light(up, "spot", "warm", 26, 1.0, Enum.NormalId.Top)
	-- Two lounge groups under the galleries.
	local function lounge(gx: number, gz: number, side: number, seed: number)
		Kit.rug(r.m, r.cf, at(r, gx + side * 0.7, gz), 6.4, 11.5, seed + 4)
		Kit.sofa(r.m, r.cf, at(r, gx + side * 2.7, gz, if side < 0 then "E" else "W"), 6, seed)
		Kit.loungeChair(r.m, r.cf, at(r, gx, gz - 4.6, "N"), seed + 1)
		Kit.loungeChair(r.m, r.cf, at(r, gx, gz + 4.6, "S"), seed + 2)
		Kit.coffeeTable(r.m, r.cf, at(r, gx - side * 0.2, gz), seed + 3, 2.4, 3.6)
		Kit.floorLamp(r.m, r.cf, at(r, gx + side * 3.0, gz + 4.4), seed + 5)
	end
	lounge(-17.6, -8, -1, r.seed + 20)
	lounge(17.6, 20, 1, r.seed + 30)
	-- AI journey wall hung from the gallery edge at the back, facing the gates.
	box(r, "JourneyFrame", V3(13.6, 8.0, 0.3), CF(0, 10.6, 35.55), C.metal, M.metal)
	box(r, "JourneyBracket", V3(13.6, 0.9, 0.15), CF(0, 14.9, 35.77), C.metal, M.metal)
	Kit.screen(r.m, r.cf, "AIJourneyWall", V3(13, 7.5, 0.1), CF(0, 10.6, 35.34), "journey", r.accent)
	-- LED news ticker under the journey wall (scrolls client-side; static company headlines only)
	Kit.ticker(r.m, r.cf, CF(0, r.y + 6.15, 35.42), 13, string.upper(r.ctx.company) .. "  ·  DATA  →  COMPUTE  →  DESIGN  →  TRAINING  →  EVALUATION  →  DEPLOYMENT  →  GROWTH  ·  WELCOME TO THE TEAM  ·  LUNCH IN THE HOUSE KITCHEN CAFÉ  ·  STAY CURIOUS")
	-- water cooler beside the east lounge group
	Kit.waterCooler(r.m, r.cf, at(r, 19.6, 30, "W"), { propId = "AtriumCooler" })
	Kit.plant(r.m, r.cf, at(r, -19.6, 31.5), "l", r.seed + 40)
	Kit.plant(r.m, r.cf, at(r, 19.6, -15.4), "l", r.seed + 41)
	-- the cleaner mops this loop around the tree (Mop activities, visited in MopIndex order)
	for i, p in { V3(-9, 0, -12), V3(9, 0, -12), V3(9.5, 0, 28), V3(-10, 0, 28) } do
		activity(r, "AtriumMop" .. i, "Mop", "operations", p, p + V3(0, 0, if i <= 2 then 4 else -4), nil, nil, { MopIndex = i })
	end
end

---------------------------------------------------------------------------------------------
-- G · Visitor lounge (public, open to the hall)
---------------------------------------------------------------------------------------------
local function visitorLounge(r: R)
	-- window group
	Kit.rug(r.m, r.cf, at(r, -37, -42.4), 13, 9.4, r.seed)
	Kit.sofa(r.m, r.cf, at(r, -37, -45.8, "N"), 8, r.seed + 1)
	Kit.coffeeTable(r.m, r.cf, at(r, -37, -42.0), r.seed + 2, 4.4, 2.2)
	Kit.loungeChair(r.m, r.cf, at(r, -40.5, -38.4, "S"), r.seed + 3)
	Kit.loungeChair(r.m, r.cf, at(r, -33.5, -38.4, "S"), r.seed + 4)
	for i = 1, 3 do
		box(r, "Magazine", V3(1.0, 0.05, 1.3), at(r, -38.4 + i * 0.7, -42 + (i % 2) * 0.3, 18 * i) * CF(0, 1.43 + i * 0.05, 0), Kit.pick({ C.white, C.fabricSand, C.blueSoft, C.terracotta }, r.seed + i), M.smooth, DETAIL)
	end
	Kit.floorLamp(r.m, r.cf, at(r, -42.8, -46.4, "N"), r.seed + 5)
	-- north group
	Kit.rug(r.m, r.cf, at(r, -34, -21.6), 12, 9, r.seed + 6)
	Kit.sofa(r.m, r.cf, at(r, -34, -18.1, "S"), 8, r.seed + 7)
	Kit.coffeeTable(r.m, r.cf, at(r, -34, -21.4), r.seed + 8, 4.4, 2.2)
	Kit.loungeChair(r.m, r.cf, at(r, -37.5, -24.8, "N"), r.seed + 9)
	Kit.loungeChair(r.m, r.cf, at(r, -30.5, -24.8, "N"), r.seed + 10)
	-- model showcase in the niche behind the logo wall
	local pAt = at(r, -27.6, -33, "W")
	box(r, "ShowcasePlinth", V3(3, 3.2, 3), pAt * CF(0, 1.6, 0), C.stone, M.stone)
	box(r, "ShowcaseGlass", V3(2.6, 2.6, 2.6), pAt * CF(0, 4.5, 0), C.glass, M.glass, GLASS)
	box(r, "ModelBase", V3(1.7, 0.2, 1.7), pAt * CF(0, 3.3, 0), C.metal, M.metal, DETAIL)
	box(r, "ModelCore", V3(1.0, 0.35, 1.0), pAt * CF(0, 3.58, 0), C.screen, M.metal, DETAIL)
	box(r, "ModelDie", V3(0.6, 0.12, 0.6), pAt * CF(0, 3.8, 0), r.accent, M.neon, DETAIL)
	plate(r, "ShowcaseLabel", 2.4, 0.6, pAt * CF(0, 2.4, -1.56), "OUR FIRST MODEL CHIP", C.metal, C.white)
	-- magazine sideboard and art on the west wall
	Kit.sideboard(r.m, r.cf, at(r, -49.5, -41, "E"), 4, r.seed + 11)
	Kit.artwork(r.m, r.cf, at(r, -49.5, -41, "E"), 5, 3.4, r.seed + 12, { y = 6.6 })
	Kit.plant(r.m, r.cf, at(r, -47.3, -45.8), "l", r.seed + 13)
	Kit.plant(r.m, r.cf, at(r, -47.6, -24.6), "m", r.seed + 14)
end

---------------------------------------------------------------------------------------------
-- G · Showroom & demo (public)
---------------------------------------------------------------------------------------------
local function showroom(r: R)
	local wallAt = at(r, -66, -8.5, "S")
	box(r, "ComparisonBezel", V3(16.4, 8.4, 0.15), wallAt * CF(0, 6.3, -0.075), C.metal, M.metal)
	Kit.screen(r.m, r.cf, "ModelComparisonWall", V3(16, 8, 0.1), wallAt * CF(0, 6.3, -0.2), "showroom", r.accent)
	Kit.bench(r.m, r.cf, at(r, -66, -18, "N"), 9, r.seed, { color = C.oakDark })
	-- demo kiosks: standing table, live demo screen, two stools on the visitor side (south)
	for i, p in { { -77, -38 }, { -57, -38 }, { -77, -24 }, { -57, -24 } } do
		local k = at(r, p[1], p[2], "S")
		box(r, "KioskTop", V3(4.6, 0.2, 2.4), k * CF(0, 3.8, 0), C.oakLight, M.wood)
		box(r, "KioskPedestal", V3(3.2, 3.7, 1.0), k * CF(0, 1.85, 0.3), C.white, M.smooth)
		box(r, "KioskPost", V3(0.3, 1.2, 0.3), k * CF(0, 4.5, 0.85), C.metal, M.metal, DETAIL)
		Kit.screen(r.m, r.cf, "DemoScreen", V3(3.4, 2.04, 0.1), k * CF(0, 6.0, 0.8), "showroom", r.accent)
		for _, sx in { -1.2, 1.2 } do
			Kit.stool(r.m, r.cf, k * CF(sx, 0, -2.3) * ANG(0, PI, 0), r.seed + i * 3, 3.0)
		end
	end
	-- product stage with the company's hero model
	local st = at(r, -67, -31)
	cyl(r, "ProductStage", "y", 0.5, 7, st * CF(0, 0.25, 0), C.white, M.marble)
	cyl(r, "StageRing", "y", 0.12, 7.3, st * CF(0, 0.06, 0), C.metal, M.metal, DETAIL)
	cyl(r, "ModelPedestal", "y", 2.6, 1.4, st * CF(0, 1.8, 0), C.metal, M.metal)
	Kit.ball(r.m, r.cf, "HeroModel", 3.2, st * CF(0, 4.7, 0), r.accent, M.glass, { transparency = 0.25, castShadow = false })
	Kit.ball(r.m, r.cf, "HeroCore", 1.5, st * CF(0, 4.7, 0), C.white, M.neon, DETAIL)
	-- orbit rings turn slowly around the hero model (PropFx spin, always on near the camera)
	local orbits = Kit.propModel(r.m, r.cf, "HeroOrbits", st * CF(0, 4.7, 0))
	for k = 0, 2 do
		Kit.cylinder(orbits, r.cf, "HeroOrbit", "x", 0.1, 4.6, st * CF(0, 4.7, 0) * ANG(0, k * PI / 3, 0) * ANG(0, 0, PI / 2 + 0.5), C.brass, M.metal, DETAIL)
	end
	fx(orbits, "spin", { FxAxis = "y", FxRate = 0.6, FxIdle = "on" })
	plate(r, "StageLabel", 3.0, 0.4, st * CF(0, 0.27, -3.56), "MODEL 1.0 · LIVE DEMO", C.metal, C.white)
	-- project portfolio board (founder opens the studio app)
	local pAt = at(r, -50.5, -20, "W")
	local board = box(r, "StudioPortfolio", V3(6.4, 3.8, 0.2), pAt * CF(0, 5.4, -0.1), C.white, M.smooth)
	local head = label(board, "STUDIO PORTFOLIO", { color = C.metal, light = 0.4, valign = "top" })
	head.Size = UDim2.fromScale(0.9, 0.18)
	head.Position = UDim2.fromScale(0.05, 0.04)
	for i = 0, 5 do
		local tx = -2.1 + (i % 3) * 2.1
		local ty = 4.95 - math.floor(i / 3) * 1.25
		box(r, "PortfolioTile", V3(1.8, 1.0, 0.05), pAt * CF(tx, ty, -0.22), if i % 2 == 0 then r.accent else Kit.pick({ C.oakLight, C.sageLight, C.blueSoft }, i), M.smooth, DETAIL)
	end
	Kit.prompt(board, "Company projects", r.owner, "studio")
	-- product plinths along the window
	for i, x in { -78, -70, -62 } do
		local p = at(r, x, -45.6)
		box(r, "ProductPlinth", V3(2.2, 3.4, 2.2), p * CF(0, 1.7, 0), C.white, M.smooth)
		if i == 2 then
			Kit.ball(r.m, r.cf, "ProductSphere", 1.4, p * CF(0, 4.1, 0), r.accent, M.glass, DETAIL)
		else
			box(r, "ProductDevice", V3(1.0, 1.4, 0.3), p * CF(0, 4.1, 0) * ANG(0, math.rad(25 * i), 0), C.screen, M.metal, DETAIL)
		end
	end
	Kit.plant(r.m, r.cf, at(r, -80, -10.6), "l", r.seed + 20)
	Kit.plant(r.m, r.cf, at(r, -52.4, -10.6), "l", r.seed + 21)
end

---------------------------------------------------------------------------------------------
-- G · Project room (MeetingRoom "ProjectRoom")
---------------------------------------------------------------------------------------------
local function projectRoom(r: R)
	Kit.meetingTable(r.m, r.cf, at(r, -67, 9.5, "E"), "boat", 20, 5, r.seed)
	local n = 0
	for _, side in { -1, 1 } do
		for k = 0, 4 do
			local z = 1.5 + k * 4
			local x = -67 + side * 3.75
			local seat = Kit.meetingChair(r.m, r.cf, at(r, x, z, if side < 0 then "E" else "W"), r.seed + k + (side + 1) * 7)
			n += 1
			activity(r, "ProjectMeeting" .. n, "Meeting", "evaluation", V3(x + side * 2.4, 0, z), V3(-67, 0, z), seat, "ProjectRoom")
		end
	end
	local sAt = at(r, -67, 27.5, "S")
	box(r, "ScreenBezel", V3(10.4, 6.4, 0.12), sAt * CF(0, 6.6, -0.06), C.metal, M.metal)
	local scr = Kit.screen(r.m, r.cf, "ProjectScreen", V3(10, 6, 0.1), sAt * CF(0, 6.6, -0.17), "evaluation", r.accent)
	scr:SetAttribute("MeetingRoom", "ProjectRoom")
	Kit.prompt(scr, "Project evaluation", r.owner, "lab", "evaluation")
	Kit.sideboard(r.m, r.cf, sAt, 9, r.seed + 3)
	Kit.whiteboard(r.m, r.cf, at(r, -67, -7.5, "N"), 8, "PROJECT ROOM\nGoals · risks · next evaluation", r.seed + 4)
	Kit.artwork(r.m, r.cf, at(r, -77, -7.5, "N"), 4, 3, r.seed + 5)
	Kit.artwork(r.m, r.cf, at(r, -57, -7.5, "N"), 4, 3, r.seed + 6)
	Kit.plant(r.m, r.cf, at(r, -79.8, -5.6), "l", r.seed + 7)
	Kit.plant(r.m, r.cf, at(r, -79.8, 25.4), "l", r.seed + 8)
end

---------------------------------------------------------------------------------------------
-- G · Compute operations (video wall, monitoring desks, showcase cluster behind glass)
---------------------------------------------------------------------------------------------
local function computeOps(r: R)
	local top = Plan.levelY(1) - 1 -- open services ceiling: underside of the level-1 slab
	local vw = at(r, -66, 28.5, "N")
	box(r, "VideoWallFrame", V3(24.6, 7.0, 0.2), vw * CF(0, 6.6, -0.1), C.metal, M.metal)
	local status = Kit.screen(r.m, r.cf, "ClusterStatus", V3(10, 6, 0.1), vw * CF(0, 6.6, -0.26), "compute", r.accent)
	Kit.prompt(status, "GPU cluster control", r.owner, "compute")
	status:SetAttribute("JourneyStep", 2)
	Kit.screen(r.m, r.cf, "TrainingWall", V3(6.5, 3.9, 0.1), vw * CF(-8.6, 6.6, -0.26), "training", r.accent)
	Kit.screen(r.m, r.cf, "ComputeWall", V3(6.5, 3.9, 0.1), vw * CF(8.6, 6.6, -0.26), "compute", r.accent)
	-- monitoring desks facing the video wall (operators sit on the north side)
	for i, p in { { -73, 37 }, { -62, 37 }, { -73, 46.5 }, { -62, 46.5 } } do
		local dAt = at(r, p[1], p[2], "N")
		local _, topY = Kit.desk(r.m, r.cf, dAt, "dual", r.seed + i)
		for _, sx in { -1.8, 1.8 } do
			box(r, "Monitor", V3(3.2, 1.9, 0.12), dAt * CF(sx, topY + 1.35, 0.95) * ANG(0, sx * -0.17, 0), C.screen, M.smooth)
		end
		Kit.officeChair(r.m, r.cf, dAt * CF(0, 0, -3.0) * ANG(0, PI, 0), r.seed + i, { lite = true })
	end
	-- compute supply terminal by the entrance
	local tAt = at(r, -53.2, 48, "W")
	local terminal = box(r, "ComputeTerminal", V3(2.4, 3.6, 1.2), tAt * CF(0, 1.8, 0), C.metal, M.metal)
	box(r, "TerminalScreen", V3(2.0, 1.3, 0.08), tAt * CF(0, 3.9, -0.3) * ANG(math.rad(20), 0, 0), C.screen, M.smooth, DETAIL)
	Kit.prompt(terminal, "Compute supply", r.owner, "compute")
	-- internal glass partition with an opening in front of the showcase cluster (stops under the
	-- exposed light battens of the open services ceiling)
	local gz = 58
	local pTop = r.y + 13.5
	local function glassRun(x1: number, x2: number)
		box(r, "PartitionSill", V3(x2 - x1, 0.35, 0.4), CF((x1 + x2) / 2, r.y + 0.175, gz), C.metal, M.metal)
		box(r, "PartitionGlass", V3(x2 - x1, pTop - r.y - 0.75, 0.12), CF((x1 + x2) / 2, (r.y + 0.35 + pTop - 0.4) / 2, gz), C.glass, M.glass, GLASS)
		box(r, "PartitionHead", V3(x2 - x1, 0.4, 0.4), CF((x1 + x2) / 2, pTop - 0.2, gz), C.metal, M.metal)
	end
	glassRun(-81.6, -57.2)
	glassRun(-52.8, -50.4)
	for _, x in { -75.5, -69.4, -63.3 } do
		box(r, "PartitionMullion", V3(0.15, pTop - r.y - 0.75, 0.3), CF(x, (r.y + 0.35 + pTop - 0.4) / 2, gz), C.metal, M.metal, DETAIL)
	end
	for _, x in { -57.2, -52.8 } do
		box(r, "PartitionPost", V3(0.25, pTop - r.y, 0.4), CF(x + (if x < -55 then -0.125 else 0.125), (r.y + pTop) / 2, gz), C.metal, M.metal)
	end
	box(r, "PartitionTransom", V3(4.4, pTop - r.y - 9.8, 0.12), CF(-55, (r.y + 9.4 + pTop - 0.4) / 2, gz), C.glass, M.glass, GLASS)
	box(r, "PartitionTransomRail", V3(4.4, 0.2, 0.4), CF(-55, r.y + 9.3, gz), C.metal, M.metal)
	box(r, "PartitionTransomHead", V3(4.4, 0.4, 0.4), CF(-55, pTop - 0.2, gz), C.metal, M.metal)
	plate(r, "ClusterSign", 4.0, 0.8, CF(-55, r.y + 10.4, gz - 0.12), "GPU CLUSTER", C.metal, r.accent)
	-- showcase cluster: six GPU racks, fronts towards the glass
	for i = 1, 6 do
		r.s.blade += 1
		-- racks 2 and 5 face the two ClusterRack activities (their doors open while an engineer works)
		local station = if i == 2 then "ClusterRack1" elseif i == 5 then "ClusterRack2" else nil
		Kit.serverRack(r.m, r.cf, at(r, -71 + (i - 1) * 2, 64 + 2.11, "S"), r.seed + i * 13, r.ctx.folders.Blades, { variant = "gpu", index = r.s.blade, trayY = if i % 2 == 0 then 9.4 else nil, station = station })
	end
	for _, x in { -73.0, -59.0 } do
		box(r, "RowPDU", V3(2.0, 7.5, 3.9), at(r, x, 66.16, "S") * CF(0, 3.75, 0), C.metalSoft, M.metal)
		box(r, "PDUDisplay", V3(0.9, 0.4, 0.05), at(r, x, 66.16, "S") * CF(0, 5.6, -1.97), C.statusGood, M.neon, DETAIL)
	end
	box(r, "FibreTray", V3(16, 0.35, 1.4), CF(-66, r.y + 9.575, 66.96), C.statusBusy, M.smooth)
	box(r, "PowerBusway", V3(16, 0.55, 0.5), CF(-66, r.y + 8.925, 65.0), C.screen, M.metal)
	for _, x in { -72.5, -59.5 } do
		strut(r, x - 0.4, x + 0.4, r.y + 9.3, 66.0, top)
	end
	box(r, "ClusterLightBar", V3(12, 0.12, 0.5), CF(-66, top - 0.3, 61.5), C.lightCool, M.neon, DETAIL)
	Kit.light(box(r, "ClusterLight", V3(0.3, 0.1, 0.3), CF(-66, top - 0.42, 61.5), C.metal, M.metal, DETAIL), "surface", "tech", 18, 0.7, Enum.NormalId.Bottom)
	for k, x in { -69, -63 } do
		activity(r, "ClusterRack" .. k, "ServerRack", "compute", V3(x, 0, 62.5), V3(x, 0, 66))
	end
	-- cooling unit on the back wall (fans spin while the company trains)
	crah(r, at(r, -77.5, 79.5, "S"), "CRAH G1\n19.0°C", 6, 8.6)
	plate(r, "OpsSign", 6, 1.0, CF(-66, r.y + 10.7, 28.62), "COMPUTE OPERATIONS", C.metal, r.accent)
end

---------------------------------------------------------------------------------------------
-- G · First AI studio (six onboarding desks + journey wall)
---------------------------------------------------------------------------------------------
local STEPS = { "1  Data", "2  Compute", "3  Design", "4  Training", "5  Evaluation", "6  Deployment", "7  Growth" }
local STEP_DEPT = { "data", "compute", "design", "training", "evaluation", "deployment", "growth" }

local function firstAI(r: R)
	for col, x in { -38.1, -25.9 } do
		for row, z in { 10, 19, 28 } do
			local n = (col - 1) * 3 + row
			local dept = if n <= 3 then "design" else "data"
			local app = if dept == "data" then "data" else "lab"
			-- the NPC stands on the aisle side: L-desks (stand +X) west, bench/standing desks (stand -X) east
			local variant = if col == 1 then "ldesk" else ({ "bench", "standing", "bench" })[row]
			Kit.station(r.m, r.cf, "FirstAI" .. n, dept, "any", at(r, x, z, "N"), r.level, variant, r.owner, r.accent, app, nil, r.room.access, r.room.id)
		end
	end
	local jw = at(r, -33, -15.5, "N")
	box(r, "JourneyBezel", V3(11.2, 6.9, 0.12), jw * CF(0, 6.0, -0.06), C.metal, M.metal)
	Kit.screen(r.m, r.cf, "FirstAIJourney", V3(10.8, 6.48, 0.1), jw * CF(0, 6.0, -0.17), "journey", r.accent)
	plate(r, "WelcomeSign", 13, 1.4, jw * CF(1.0, 11.0, -0.06), "BUILD YOUR FIRST AI", C.metal, r.accent)
	for i, s in STEPS do
		plate(r, "JourneyStep", 3.4, 0.85, jw * CF(-8.4, 9.6 - (i - 1) * 1.05, -0.06), s, (Kit.A.department :: any)[STEP_DEPT[i]] or C.metal, C.white)
	end
	Kit.bench(r.m, r.cf, at(r, -33, -8, "S"), 6, r.seed, { color = C.oakLight })
	Kit.plant(r.m, r.cf, at(r, -40.4, -14), "m", r.seed + 1)
	Kit.plant(r.m, r.cf, at(r, -40.4, 34.2), "m", r.seed + 2)
end

---------------------------------------------------------------------------------------------
-- G · IT service desk (operations post 6)
---------------------------------------------------------------------------------------------
local function itDesk(r: R)
	local _, panel = Kit.receptionDesk(r.m, r.cf, at(r, -32, 55, "S"), 10, r.seed)
	label(panel, "IT SERVICE DESK", { color = C.white, light = 0.3 })
	for _, dx in { -2.2, 2.2 } do
		box(r, "Monitor", V3(2.2, 1.4, 0.12), at(r, -32 + dx, 56.1, "N") * CF(0, 4.2, 0), C.screen, M.smooth)
	end
	local seat = opsChair(r, at(r, -32, 58.4, "S"), r.seed + 1)
	Kit.tvScreen(r.m, r.cf, at(r, -22.5, 66, "W"), 6, "compute", r.accent, { name = "ITStatusScreen" })
	for i, x in { -39, -34.5, -30 } do
		Kit.rackShelf(r.m, r.cf, at(r, x, 79.5, "S"), 4.2, r.seed + i)
	end
	local benchAt = at(r, -41.5, 66, "E")
	Kit.workbench(r.m, r.cf, benchAt, 6, r.seed + 4)
	-- repair laptop on the bench: its diagnostics light blinks while IT works on it
	local laptop = box(r, "RepairLaptop", V3(2.0, 0.1, 1.4), benchAt * CF(-0.6, 3.25, -1.3), C.metalSoft, M.metal, DETAIL)
	box(r, "RepairLaptopLid", V3(2.0, 1.3, 0.08), benchAt * CF(-0.6, 3.9, -0.62) * ANG(math.rad(12), 0, 0), C.metalSoft, M.metal, DETAIL)
	local diag = Kit.part(laptop, r.cf, "DiagnosticsLed", V3(0.3, 0.06, 0.06), benchAt * CF(-0.6, 3.33, -2.0), C.metalSoft, M.neon, DETAIL)
	diag:SetAttribute("FxGlow", true)
	fx(laptop, "blink", { FxColor = C.statusBusy, FxRate = 2, PropId = "ITBench" })
	-- IT support (post 6): desk, repair bench; fault calls to broken desks are dynamic (StaffJobs)
	opsPost(r, 6, V3(-29.0, 0, 58.6), V3(-32, 0, 55), seat, {
		jp("bench", V3(-37.4, 0, 66), V3(-41.5, 0, 66), "ITBench"),
	})
	for i, z in { 46.6, 49.6 } do
		Kit.meetingChair(r.m, r.cf, at(r, -39.6, z, "E"), r.seed + 10 + i)
	end
	Kit.plant(r.m, r.cf, at(r, -24.4, 46.6), "m", r.seed + 5)
	hanging(r, "ITSign", 6, 1.1, pt(r, -32, 10.8, 60.5), r.ceil, "IT SERVICE · HARDWARE · ACCESS CARDS", C.metal, C.white)
end

---------------------------------------------------------------------------------------------
-- G · House Kitchen café (public)
---------------------------------------------------------------------------------------------
local function cafe(r: R)
	local ctx = r.ctx
	-- servery counter along the back, customers on the south side
	Kit.counter(r.m, r.cf, at(r, 47, 20, "S"), 34, r.seed, { body = C.oakDark })
	for i, snack in CampusConfig.SNACKS do
		local x = 33.5 + (i - 1) * 5
		local col = Color3.fromRGB(snack.color[1], snack.color[2], snack.color[3])
		box(r, "DisplayStand", V3(3.2, 0.1, 1.9), pt(r, x, 3.7, 19.7), C.oak, M.wood, DETAIL)
		local pack = box(r, "SnackDisplay", V3(2.4, 1.6, 1.6), pt(r, x, 4.55, 19.7), col, M.smooth)
		label(pack, snack.name, { color = C.white, light = 0.3 })
		Kit.action(pack, "snack", snack.name .. " · $" .. snack.price, snack.id, { actionText = "Buy", maxDistance = 10 })
	end
	-- espresso machine on the counter, facing the barista
	local cm = pt(r, 57.5, 3.65, 20.3) * ANG(0, PI, 0)
	local machine = box(r, "KitchenCoffeeMachine", V3(3.6, 2.0, 1.6), cm * CF(0, 1.0, 0), C.metal, M.metal)
	box(r, "MachineTop", V3(3.7, 0.15, 1.7), cm * CF(0, 2.07, 0), C.metalSoft, M.metal, DETAIL)
	for _, gx in { -0.9, 0.9 } do
		cyl(r, "GroupHead", "y", 0.35, 0.45, cm * CF(gx, 1.35, -0.95), C.metalSoft, M.metal, DETAIL)
		cyl(r, "Cup", "y", 0.35, 0.35, cm * CF(gx, 0.18, -1.0), C.white, M.smooth, DETAIL)
	end
	local steam = Instance.new("ParticleEmitter")
	steam.Name = "CoffeeSteam"
	steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	steam.Rate = 3
	steam.Lifetime = NumberRange.new(0.8, 1.4)
	steam.Speed = NumberRange.new(0.8, 1.5)
	steam.Size = NumberSequence.new(0.15)
	steam.Transparency = NumberSequence.new(0.8)
	steam.Enabled = false
	steam.Parent = machine
	-- PropFx: the barista (and employees on a coffee break) brew here; players can too
	fx(machine, "steam", { FxSeconds = 5, PropId = "KitchenCoffeeMachine" })
	Kit.action(machine, "prop", "Espresso machine", "KitchenCoffeeMachine", { actionText = "Brew", maxDistance = 7 })
	-- lunch servery at the east end of the counter: hot wells under a sneeze guard, plate stack.
	-- The kitchen team serves from behind (post 9, point "servery"); the hot wells steam while serving.
	local well = box(r, "HotWell", V3(3.2, 0.35, 1.7), pt(r, 62.2, 3.82, 20.1), C.metalSoft, M.metal)
	for k = 0, 2 do
		box(r, "HotFood", V3(0.9, 0.08, 1.3), pt(r, 61.15 + k * 1.05, 4.02, 20.1), Kit.pick({ C.terracotta, C.sage, C.fabricSand }, r.seed + k), M.smooth, DETAIL)
	end
	Kit.steamEmitter(well, "Steam", 3, 0.35)
	fx(well, "steam", { FxSeconds = 4, PropId = "Servery" })
	box(r, "SneezeGuard", V3(3.4, 1.1, 0.08), pt(r, 62.2, 4.95, 19.15) * ANG(math.rad(-15), 0, 0), C.glass, M.glass, GLASS_DECOR)
	cyl(r, "PlateStack", "y", 0.6, 1.3, pt(r, 63.6, 3.95, 19.4), C.white, M.smooth, DETAIL)
	plate(r, "ServerySign", 3.4, 0.6, pt(r, 62.2, 6.6, 19.1), "LUNCH · SERVED DAILY", C.metal, C.white)
	-- back bar: kitchenette on the solid kitchen wall, pastry counter on the glazed part
	Kit.kitchenette(r.m, r.cf, at(r, 58, 27.5, "S"), 15, r.seed + 3, { fridge = false, coffeeName = "GrinderStation" })
	Kit.sideboard(r.m, r.cf, at(r, 40, 27.8, "S"), 18, r.seed + 4)
	local menu = "HOUSE KITCHEN"
	for _, s in CampusConfig.SNACKS do
		menu ..= string.format("\n%s  ·  $%d", s.name, s.price)
	end
	hanging(r, "KitchenMenu", 14, 4.4, pt(r, 40, 9.2, 26.6), r.ceil, menu, C.metal, C.white)
	local brand = box(r, "KitchenBrand", V3(12, 2.6, 0.12), pt(r, 58, 9.9, 27.44), C.metal, M.metal)
	label(brand, ctx.company .. "\nSNACK CLUB", { color = C.brass, light = 0.3, maxDistance = 90 })
	-- grab-and-go drinks fridge (Door_G_FRIDGE) beside the counter
	local fridge: any = {
		id = "G_FRIDGE", level = r.level, room = r.room.id, kind = "fridge", access = "staff", axis = "x",
		x = 27, z = 25.2, w = 5, h = 8, inward = Vector3.new(0, 0, 1), exterior = false, hidden = false,
		builder = "interior", y = r.y, depth = 2.4,
	}
	Kit.door(ctx.folders.Doors, r.cf, fridge, r.owner)
	for _, x in { 24.3, 29.7 } do
		box(r, "FridgeSurround", V3(0.3, 9, 2.6), pt(r, x, 4.5, 26.5), C.oak, M.wood)
	end
	plate(r, "FridgeSign", 5.7, 0.9, pt(r, 27, 8.55, 25.1), "COLD DRINKS", C.oakDark, C.white, true)
	box(r, "FridgeSurroundTop", V3(5.7, 0.5, 2.6), pt(r, 27, 9.25, 26.5), C.oak, M.wood)
	-- activities in front of the counter and the fridge (coffee spots leave the servery end free)
	for k = 1, 3 do
		activity(r, "SnackStation" .. k, "Snack", "kitchen", V3(31 + k * 5, 0, 16.4), V3(31 + k * 5, 0, 20), nil, nil, { JobItem = "snack" })
		activity(r, "CoffeeStation" .. k, "Coffee", "kitchen", V3(52.8 + k * 2.4, 0, 16.4), V3(57.5, 0, 20))
	end
	activity(r, "FridgeStation", "Fridge", "kitchen", V3(27, 0, 21.6), V3(27, 0, 26))
	-- lunch queue: slot 1 faces the servery, the line runs east along the counter's customer side
	for k, p in { V3(62.8, 0, 16.4), V3(65.6, 0, 14.6), V3(68.4, 0, 14.6), V3(71.2, 0, 14.6), V3(74.0, 0, 14.6), V3(76.8, 0, 14.6) } do
		activity(r, "LunchQueue" .. k, "Queue", "kitchen", p, if k == 1 then V3(62.8, 0, 20) else V3(p.X - 3, 0, p.Z), nil, nil, { QueueIndex = k })
	end
	-- tray return trolley by the kitchen door (the kitchen team takes the trays to the dish station)
	local tr = at(r, 75.5, 27.4, "S")
	box(r, "TrayRack", V3(3.0, 0.2, 1.3), tr * CF(0, 3.2, -0.65), C.metalSoft, M.metal)
	box(r, "TrayRackBase", V3(3.0, 0.2, 1.3), tr * CF(0, 1.2, -0.65), C.metalSoft, M.metal)
	for _, x in { -1.4, 1.4 } do
		box(r, "TrayRackPost", V3(0.15, 3.3, 1.2), tr * CF(x, 1.65, -0.65), C.metal, M.metal)
	end
	box(r, "TrayStack", V3(2.0, 0.4, 1.0), tr * CF(-0.3, 3.5, -0.65), C.oakLight, M.smooth, DETAIL)
	plate(r, "TraySign", 2.6, 0.5, tr * CF(0, 4.4, 0.04), "TRAYS · THANK YOU", C.metal, C.white)
	activity(r, "TrayReturn", "TrayReturn", "kitchen", V3(75.5, 0, 24.4), V3(75.5, 0, 27.4))
	-- barista (post 7): espresso machine, hand-over on the counter, grinder on the back bar, wiping
	opsPost(r, 7, V3(57.5, 0, 23.0), V3(57.5, 0, 20), nil, {
		jp("machine", V3(57.5, 0, 23.0), V3(57.5, 0, 20), "KitchenCoffeeMachine"),
		jp("hand", V3(54.0, 0, 22.8), V3(54.0, 0, 17)),
		jp("grinder", V3(60.0, 0, 23.6), V3(60.0, 0, 27.5)),
		jp("wipe", V3(50.8, 0, 22.8), V3(50.8, 0, 20)),
	})
	-- host stand by the opening from the reception hall
	local hAt = at(r, 26.4, -23, yawTo(-1, -1))
	box(r, "HostStand", V3(2.0, 3.6, 1.2), hAt * CF(0, 1.8, 0), C.oakDark, M.wood)
	box(r, "HostTop", V3(2.2, 0.12, 1.4), hAt * CF(0, 3.7, 0) * ANG(math.rad(-10), 0, 0), C.stone, M.marble)
	-- café host (post 10): greets at the stand, wipes two tables nearby
	opsPost(r, 10, V3(28.4, 0, -21.0), V3(24, 0, -26), nil, {
		jp("greet", V3(28.4, 0, -21.0), V3(22, 0, -30)),
		jp("table1", V3(35.6, 0, -19.6), V3(41, 0, -18)),
		jp("table2", V3(35.0, 0, -27.4), V3(35, 0, -33)),
	})
	-- window bar with stools along the south facade
	box(r, "WindowBar", V3(44, 0.15, 1.6), pt(r, 52, 3.55, -46.4), C.oakLight, M.wood)
	for k = 0, 4 do
		box(r, "WindowBarLeg", V3(0.2, 3.48, 1.2), pt(r, 30.6 + k * 10.7, 1.74, -46.6), C.metal, M.metal)
	end
	cyl(r, "FootRail", "x", 43.6, 0.15, pt(r, 52, 1.0, -45.7), C.metalSoft, M.metal, DETAIL)
	for i = 0, 12 do
		local x = 33 + i * 3.2
		local seat = Kit.stool(r.m, r.cf, at(r, x, -44.4, "S"), r.seed + i, 3.0)
		dining(r, seat, V3(x, 0, -41.6), V3(x, 0, -46.4), 3.625)
	end
	-- four-tops
	local tables = { { 35, -33 }, { 47.5, -33 }, { 60, -33 }, { 72.5, -33 }, { 41, -18 }, { 53.5, -18 }, { 66, -18 } }
	for ti, p in tables do
		local tx, tz = p[1], p[2]
		local seed = r.seed + ti * 31
		if Kit.rand(seed, 1) < 0.5 then
			Kit.meetingTable(r.m, r.cf, at(r, tx, tz), "round", 4.2, nil, seed)
		else
			box(r, "TableTop", V3(4.0, 0.2, 4.0), pt(r, tx, 3.05, tz), Kit.pick({ C.oak, C.oakLight, C.stone }, seed), M.wood)
			cyl(r, "TableColumn", "y", 2.9, 0.4, pt(r, tx, 1.5, tz), C.metal, M.metal)
			cyl(r, "TableFoot", "y", 0.1, 2.0, pt(r, tx, 0.05, tz), C.metal, M.metal)
		end
		for k = 0, 3 do
			local a = k * PI / 2
			local dx, dz = math.sin(a), math.cos(a)
			local seat = cafeChair(r, at(r, tx + dx * 3.2, tz + dz * 3.2, yawTo(-dx, -dz)), seed + k)
			dining(r, seat, V3(tx + dx * 5.4, 0, tz + dz * 5.4), V3(tx, 0, tz))
		end
	end
	-- long communal table with two pendants
	Kit.meetingTable(r.m, r.cf, at(r, 50, 1), "rect", 22, 4.5, r.seed + 7)
	for k = 0, 5 do
		local x = 40.6 + k * 3.75
		for _, side in { -1, 1 } do
			local z = 1 + side * 3.45
			local seat = cafeChair(r, at(r, x, z, if side > 0 then "S" else "N"), r.seed + k * 2 + side)
			dining(r, seat, V3(x, 0, 1 + side * 5.6), V3(x, 0, 1))
		end
	end
	for _, x in { 44, 56 } do
		Kit.pendant(r.m, r.cf, CF(x, r.ceil, 1), "warm", { drop = 4.6 })
	end
	-- lounge corner by the east window
	Kit.rug(r.m, r.cf, at(r, 76.5, 2), 9, 12, r.seed + 8)
	Kit.sofa(r.m, r.cf, at(r, 79.9, 2, "W"), 7, r.seed + 9)
	Kit.loungeChair(r.m, r.cf, at(r, 74.6, -2.6, "N"), r.seed + 10)
	Kit.loungeChair(r.m, r.cf, at(r, 74.6, 6.6, "S"), r.seed + 11)
	Kit.coffeeTable(r.m, r.cf, at(r, 75.9, 2), r.seed + 12, 2.4, 3.6)
	for i, p in { { 31.5, 9.5 }, { 68.5, 9.5 }, { 79.5, -45.6 }, { 24.8, 12.5 }, { 79.5, 25.2 } } do
		Kit.plant(r.m, r.cf, at(r, p[1], p[2]), "l", r.seed + 50 + i)
	end
end

---------------------------------------------------------------------------------------------
-- G · Kitchen (back of house, operations posts 8 and 9)
---------------------------------------------------------------------------------------------
local function kitchenBoh(r: R)
	local line = at(r, 66, 51.5, "S")
	box(r, "CookingBlock", V3(16, 3.0, 2.8), line * CF(0, 1.5, -1.4), C.metalSoft, M.metal)
	box(r, "HobTop", V3(16.2, 0.15, 3.0), line * CF(0, 3.075, -1.5), C.metal, M.metal)
	-- the range as one PropFx prop: burners 2 and 3 flame and glow, the pan steams while the chef cooks
	local range = Kit.propModel(r.m, r.cf, "Range", line * CF(0, 3.2, -1.6))
	for i = 0, 5 do
		local burner = Kit.cylinder(range, r.cf, "Burner", "y", 0.12, 1.1, line * CF(-6 + i * 2.4, 3.2, -1.6), C.screen, M.metal, DETAIL)
		if i == 1 or i == 2 then
			burner:SetAttribute("FxGlow", true)
			Kit.flame(burner)
		end
	end
	local pan = Kit.cylinder(range, r.cf, "Pan", "y", 0.35, 1.5, line * CF(-3.6, 3.43, -1.6), C.fabricCharcoal, M.metal, DETAIL)
	-- the handle points at the cook (front edge of the range), never into the splashback
	Kit.part(range, r.cf, "PanHandle", V3(1.2, 0.12, 0.2), line * CF(-3.6, 3.5, -2.9) * ANG(0, PI / 2, 0), C.fabricCharcoal, M.metal, DETAIL)
	Kit.steamEmitter(pan, "Steam", 5, 0.4)
	Kit.cylinder(range, r.cf, "Pot", "y", 1.0, 1.3, line * CF(-1.2, 3.75, -1.7), C.metalSoft, M.metal, DETAIL)
	fx(range, "flame,steam,blink", { FxColor = C.terracotta, FxRate = 0, FxSeconds = 8, PropId = "Range" })
	box(r, "OvenFronts", V3(15, 1.6, 0.05), line * CF(0, 1.3, -2.83), C.metal, M.metal, DETAIL)
	box(r, "Splashback", V3(16, 5.0, 0.08), line * CF(0, 5.6, -0.04), C.metalSoft, M.metal, DETAIL)
	box(r, "ExtractionHood", V3(16.4, 1.6, 3.4), line * CF(0, 9.4, -1.7), C.metalSoft, M.metal)
	box(r, "HoodDuct", V3(2.4, r.ceil - r.y - 10.2, 1.6), line * CF(0, (10.2 + r.ceil - r.y) / 2, -1.0), C.metalSoft, M.metal)
	-- prep island
	local island = at(r, 66, 39.5)
	box(r, "PrepTop", V3(10, 0.15, 3.4), island * CF(0, 3.15, 0), C.metalSoft, M.metal)
	box(r, "PrepShelf", V3(9.6, 0.1, 3.0), island * CF(0, 0.8, 0), C.metalSoft, M.metal, DETAIL)
	for _, lx in { -4.7, 4.7 } do
		for _, lz in { -1.5, 1.5 } do
			box(r, "PrepLeg", V3(0.2, 3.05, 0.2), island * CF(lx, 1.55, lz), C.metal, M.metal)
		end
	end
	for i = 0, 2 do
		box(r, "CuttingBoard", V3(1.6, 0.08, 1.1), island * CF(-3 + i * 3, 3.27, 0.4), C.oakLight, M.wood, DETAIL)
	end
	-- stainless counters with sink along the south wall
	local sc = at(r, 58.8, 28.5, "N")
	box(r, "SteelCounter", V3(15, 3.0, 2.4), sc * CF(0, 1.5, -1.2), C.metalSoft, M.metal)
	box(r, "SteelCounterTop", V3(15.2, 0.12, 2.6), sc * CF(0, 3.06, -1.3), C.metal, M.metal)
	box(r, "Sink", V3(2.4, 0.05, 1.6), sc * CF(-4, 3.13, -1.3), C.screen, M.metal, DETAIL)
	local sinkWater = box(r, "SinkWater", V3(0.15, 0.9, 0.15), sc * CF(-4, 3.6, -0.7), C.water, M.glass, { detail = true, transparency = 1 })
	sinkWater:SetAttribute("FxShow", 0.4)
	fx(sinkWater, "flow", { FxSeconds = 5, PropId = "KitchenSink" })
	-- dish station on the east side (the dishwasher steams while the kitchen team washes up)
	local dish = box(r, "DishStation", V3(3.0, 3.0, 14), pt(r, 80, 1.5, 40), C.metalSoft, M.metal)
	box(r, "DishStationTop", V3(3.2, 0.12, 14.2), pt(r, 80, 3.06, 40), C.metal, M.metal)
	Kit.steamEmitter(dish, "Steam", 6, 0.6)
	fx(dish, "steam", { FxSeconds = 6, PropId = "DishStation" })
	-- the pass by the café door: heated shelf with heat lamps; the chef plates here
	box(r, "PassShelf", V3(4.0, 0.15, 1.8), pt(r, 76, 3.55, 29.6), C.metal, M.metal)
	box(r, "PassBase", V3(3.8, 3.45, 1.6), pt(r, 76, 1.75, 29.55), C.metalSoft, M.metal)
	local lamps = box(r, "HeatLamps", V3(3.8, 0.25, 0.6), pt(r, 76, 6.4, 29.3), C.metal, M.metal, DETAIL)
	local glow = Kit.part(lamps, r.cf, "HeatLampGlow", V3(3.4, 0.05, 0.4), pt(r, 76, 6.25, 29.3), C.metalSoft, M.neon, DETAIL)
	glow:SetAttribute("FxGlow", true)
	box(r, "HeatLampRod", V3(0.12, 3.0, 0.12), pt(r, 76, 4.9, 28.62), C.metal, M.metal, DETAIL)
	fx(lamps, "blink", { FxColor = C.terracotta, FxRate = 0, FxSeconds = 6, PropId = "Pass" })
	-- shelving and the cold room door (decor)
	Kit.rackShelf(r.m, r.cf, at(r, 50.5, 45.6, "E"), 3.6, r.seed + 1)
	Kit.rackShelf(r.m, r.cf, at(r, 50.5, 49.4, "E"), 3.6, r.seed + 2)
	local cr = at(r, 53.4, 51.5, "S")
	box(r, "ColdRoomPanel", V3(3.8, 8.2, 0.25), cr * CF(0, 4.1, -0.125), C.metalSoft, M.metal)
	box(r, "ColdRoomHandle", V3(0.25, 1.6, 0.3), cr * CF(1.4, 4.0, -0.4), C.metal, M.metal, DETAIL)
	plate(r, "ColdRoomSign", 2.6, 0.8, cr * CF(0, 9.0, -0.06), "COLD ROOM · 3°C", C.blue, C.white)
	-- chef (post 8): cooks at the range, checks the ovens, plates at the pass (via the aisle east of the island)
	opsPost(r, 8, V3(63, 0, 46.4), V3(63, 0, 51), nil, {
		jp("range", V3(63, 0, 46.4), V3(63, 0, 51), "Range"),
		jp("oven", V3(69.0, 0, 46.4), V3(69.0, 0, 51)),
		jp("aisle", V3(74.2, 0, 44.0), V3(74.2, 0, 30)),
		jp("pass", V3(76.0, 0, 32.6), V3(76.0, 0, 29.6), "Pass"),
	})
	-- kitchen team (post 9): prep island, sink, dish station; at lunch it serves at the café servery
	-- (point "servery" lies in the café: reached by navigation through the kitchen door)
	opsPost(r, 9, V3(64, 0, 36.2), V3(64, 0, 39.5), nil, {
		jp("chop", V3(64, 0, 36.2), V3(64, 0, 39.5)),
		jp("sink", V3(62.8, 0, 32.6), V3(62.8, 0, 29.8), "KitchenSink"),
		jp("dishVia", V3(72.6, 0, 35.6), V3(80, 0, 40)),
		jp("dish", V3(76.6, 0, 40), V3(80, 0, 40), "DishStation"),
		jp("servery", V3(62.8, 0, 22.8), V3(62.8, 0, 20), "Servery"),
	})
end

---------------------------------------------------------------------------------------------
-- G · Deliveries & service
---------------------------------------------------------------------------------------------
local function delivery(r: R)
	for i = 0, 3 do
		Kit.rackShelf(r.m, r.cf, at(r, 54 + i * 4.8, 79.5, "S"), 4.6, r.seed + i)
	end
	-- parcel cage in the north-east corner
	local cx1, cx2, cz1, cz2 = 73.5, 81.4, 72.5, 79.4
	for _, p in { { cx1, cz1 }, { cx2, cz1 }, { cx1, cz2 } } do
		box(r, "CagePost", V3(0.2, 7, 0.2), pt(r, p[1], 3.5, p[2]), C.metal, M.metal)
	end
	box(r, "CageMesh", V3(cx2 - cx1, 6.8, 0.05), pt(r, (cx1 + cx2) / 2, 3.5, cz1), C.metalSoft, M.metal, { transparency = 0.6 })
	box(r, "CageMesh", V3(0.05, 6.8, cz2 - cz1), pt(r, cx1, 3.5, (cz1 + cz2) / 2), C.metalSoft, M.metal, { transparency = 0.6 })
	for i = 0, 2 do
		box(r, "Parcel", V3(2, 1.6, 2), pt(r, 76 + i * 1.6, 0.8 + (i % 2) * 1.6, 76.5), Kit.pick({ C.fabricSand, C.oakLight }, i), M.smooth)
	end
	-- receiving desk (standing height)
	local d = at(r, 58, 57, "N")
	box(r, "ReceivingDesk", V3(6, 0.2, 2.4), d * CF(0, 3.9, 0), C.oakLight, M.wood)
	box(r, "ReceivingBody", V3(5.6, 3.8, 1.6), d * CF(0, 1.9, 0.3), C.metalSoft, M.metal)
	box(r, "ScannerDock", V3(1.0, 0.4, 0.7), d * CF(1.8, 4.2, 0), C.screen, M.smooth, DETAIL)
	-- pallet with boxes and a platform trolley
	local p = at(r, 75, 56.5)
	box(r, "Pallet", V3(4, 0.5, 4), p * CF(0, 0.25, 0), C.oakLight, M.wood)
	for i = 0, 2 do
		box(r, "Box", V3(1.8, 1.5, 1.8), p * CF(-0.9 + (i % 2) * 1.8, 1.25 + math.floor(i / 2) * 1.5, -0.6 + math.floor(i / 2) * 0.6), Kit.pick({ C.fabricSand, C.oakLight, C.white }, i + 3), M.smooth)
	end
	local t = at(r, 67.5, 56, "E")
	box(r, "TrolleyDeck", V3(2.4, 0.3, 4), t * CF(0, 0.6, 0), C.metalSoft, M.metal)
	box(r, "TrolleyHandle", V3(2.4, 3.0, 0.15), t * CF(0, 2.2, 1.95), C.metal, M.metal)
	plate(r, "GoodsInSign", 5, 1.0, at(r, 50.6, 72, "E") * CF(0, 7.5, -0.06), "GOODS IN · SIGN FOR ALL DELIVERIES", C.metal, C.white)
	-- cleaning cart park (operations post 15, cleaner): marked bay with the mop caddy; the cleaner
	-- takes the cart out to the atrium and the restrooms (Mop / Clean activities)
	for _, e in { { 61, 70.6, 4.4, 0.2 }, { 61, 75.4, 4.4, 0.2 }, { 58.9, 73, 0.2, 5 }, { 63.1, 73, 0.2, 5 } } do
		box(r, "CartBayLine", V3(e[3], 0.05, e[4]), pt(r, e[1], 0.025, e[2]), C.statusBusy, M.smooth, DETAIL)
	end
	cyl(r, "MopBucket", "y", 1.2, 1.4, pt(r, 62.2, 0.6, 74.4), C.statusBusy, M.smooth)
	box(r, "MopHandle", V3(0.15, 4.6, 0.15), pt(r, 62.6, 2.4, 74.6) * ANG(0, 0, math.rad(10)), C.metalSoft, M.metal, DETAIL)
	opsPost(r, 15, V3(60, 0, 70.6), V3(61.5, 0, 74), nil, {
		jp("cart", V3(60, 0, 70.6), V3(61.5, 0, 74)),
	})
end

---------------------------------------------------------------------------------------------
-- G · Mailroom & lockers
---------------------------------------------------------------------------------------------
local function mailroom(r: R)
	Kit.lockers(r.m, r.cf, at(r, 22.5, 66, "E"), 12, r.seed, { propId = "MailLockers", door = 6 })
	plate(r, "LockerSign", 6, 0.8, at(r, 22.5, 66, "E") * CF(0, 7.2, -0.06), "PARCEL LOCKERS", C.metal, C.white)
	local ph = at(r, 32, 79.5, "S")
	box(r, "PigeonholeCase", V3(10, 6, 1.2), ph * CF(0, 4.5, -0.6), C.oakLight, M.wood)
	box(r, "PigeonholeBack", V3(9.6, 5.6, 0.05), ph * CF(0, 4.5, -1.22), C.oakDark, M.wood, DETAIL)
	for i = 1, 4 do
		box(r, "PigeonholeDivider", V3(0.08, 5.6, 0.05), ph * CF(-4.8 + i * 1.92, 4.5, -1.24), C.oak, M.wood, DETAIL)
		box(r, "PigeonholeShelf", V3(9.6, 0.08, 0.05), ph * CF(0, 1.7 + i * 1.12, -1.24), C.oak, M.wood, DETAIL)
	end
	for i = 0, 4 do
		box(r, "Envelope", V3(1.2, 0.5, 0.06), ph * CF(-3.8 + i * 1.92, 2.3 + (i % 3) * 1.12, -1.28), C.white, M.smooth, DETAIL)
	end
	-- sorting table and standing desk
	local s = at(r, 33, 60)
	box(r, "SortingTop", V3(7, 0.2, 3), s * CF(0, 3.8, 0), C.oakLight, M.wood)
	box(r, "SortingBody", V3(6.6, 3.7, 2.4), s * CF(0, 1.85, 0), C.white, M.smooth)
	for i = 0, 2 do
		box(r, "Parcel", V3(1.4, 1.0, 1.2), s * CF(-2 + i * 1.9, 4.4, 0.2), Kit.pick({ C.fabricSand, C.oakLight }, i), M.smooth, DETAIL)
	end
	Kit.desk(r.m, r.cf, at(r, 36, 71, "S"), "standing", r.seed + 3)
	Kit.plant(r.m, r.cf, at(r, 40.2, 46.2), "m", r.seed + 4)
	-- mail clerk (operations post 16): sorts parcels at the table, fills the parcel lockers and the
	-- pigeonholes (routes keep west of the sorting table and the standing desk)
	opsPost(r, 16, V3(33, 0, 56.8), V3(33, 0, 60), nil, {
		jp("sort", V3(33, 0, 56.8), V3(33, 0, 60)),
		jp("west", V3(27.4, 0, 57.0), V3(27.4, 0, 66)),
		jp("lockers", V3(26.8, 0, 65.2), V3(22.5, 0, 65.2), "MailLockers"),
		jp("pigeon", V3(30.5, 0, 76.4), V3(30.5, 0, 79.5)),
	})
end

---------------------------------------------------------------------------------------------
-- B1 · Data hall (the showpiece): three contained pods, network core, CRAHs, NOC, staging
---------------------------------------------------------------------------------------------
local function dataHall(r: R)
	local ctx = r.ctx
	local fy = r.y + 0.06 -- top of the raised-floor plate
	local top = Plan.levelY(0) - 1.1 -- open soffit (painted slab underside) above the hall
	-- light raised floor: one plate; the 4-stud tile joints are drawn on it (no part per line)
	local floor = box(r, "RaisedFloor", V3(71, 0.06, 127), CF(-58, r.y + 0.03, 0), C.plasterShade, M.smooth)
	local grid = Instance.new("SurfaceGui")
	grid.Name = "TileGrid"
	grid.Face = Enum.NormalId.Top
	grid.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	grid.PixelsPerStud = 8
	grid.LightInfluence = 1
	grid.MaxDistance = 120
	grid.Parent = floor
	for k = -8, 8 do -- joints every 4 studs, symmetric about the plate centre
		local line = Instance.new("Frame")
		line.Name = "JointX"
		line.BorderSizePixel = 0
		line.BackgroundColor3 = C.concrete
		line.AnchorPoint = Vector2.new(0.5, 0)
		line.Position = UDim2.fromScale(0.5 + k * 4 / 71, 0)
		line.Size = UDim2.new(0, 1, 1, 0)
		line.Parent = grid
	end
	for k = -15, 15 do
		local line = Instance.new("Frame")
		line.Name = "JointZ"
		line.BorderSizePixel = 0
		line.BackgroundColor3 = C.concrete
		line.AnchorPoint = Vector2.new(0, 0.5)
		line.Position = UDim2.fromScale(0, 0.5 + k * 4 / 127)
		line.Size = UDim2.new(1, 0, 0, 1)
		line.Parent = grid
	end
	-- One rack row (fronts on x = front, facing `face`) with PDUs, sign, fibre tray and busway.
	local rowNo = 0
	local act = 0
	local function rackRow(p: number, name: string, ax: number, side: number, face: string, zS: number, count: number, trayEnd: number, activities: boolean)
		local front = ax + side * 2.11
		for i = 1, count do
			local z = zS + 1.5 + (i - 1) * 2 + 1
			r.s.blade += 1
			local station: string? = nil
			if activities and (i == 3 or i == 8 or i == 12) then
				act += 1
				local id = "DataHallRack" .. act
				station = id
				activity(r, id, "ServerRack", "compute", V3(front + side * 1.4, 0, z), V3(ax, 0, z))
			end
			Kit.serverRack(r.m, r.cf, Kit.place(ax, fy, z, face), r.seed + p * 211 + rowNo * 37 + i, ctx.folders.Blades, { variant = "gpu", index = r.s.blade, trayY = if i % 3 == 2 then 9.4 else nil, station = station })
		end
		local zN = zS + 1.5 + count * 2 + 1.5
		for _, ez in { zS + 0.75, zN - 0.75 } do
			local pAt = Kit.place(ax, fy, ez, face)
			box(r, "RowPDU", V3(1.5, 7.5, 3.9), pAt * CF(0, 3.75, 0.05), C.metalSoft, M.metal)
			box(r, "PDUDisplay", V3(0.9, 0.35, 0.05), pAt * CF(0, 5.8, -1.92), C.statusGood, M.neon, DETAIL)
		end
		rowNo += 1
		plate(r, "RowSign", 3.6, 0.9, CF(ax, fy + 8.0, zN + 0.07) * ANG(0, PI, 0), string.format("POD %s · ROW %02d", name, rowNo), C.metal, C.white)
		-- overhead: yellow fibre tray over the cable entries, black busway with tap-off boxes
		local tx = ax - side * 0.8
		box(r, "FibreTray", V3(1.4, 0.35, trayEnd - zS), CF(tx, fy + 9.575, (zS + trayEnd) / 2), C.statusBusy, M.smooth)
		local bx = ax + side * 0.6
		box(r, "PowerBusway", V3(0.5, 0.55, zN - zS), CF(bx, fy + 8.925, (zS + zN) / 2), C.screen, M.metal)
		for k = 1, 3 do
			box(r, "TapOffBox", V3(0.6, 0.5, 0.9), CF(bx, fy + 8.4, zS + k * (zN - zS) / 4), C.metal, M.metal, DETAIL)
		end
		return zN
	end
	-- Pods A-C: two facing rows of 14 GPU racks around a contained cold aisle.
	local PODS: { { name: string, cx: number } } = { { name = "A", cx = -79.9 }, { name = "B", cx = -62.49 }, { name = "C", cx = -45.08 } }
	local zS = 0.5
	local netFront = 37.5 -- network core row fronts (facing the pods)
	local netZ = netFront + 2.11
	local trayZ = netZ + 0.8 -- cross tray over the network row's cable entries
	local zN = zS
	for p, pod in PODS do
		local name, cx = pod.name, pod.cx
		for row = 1, 2 do
			local side = if row == 1 then 1 else -1 -- +1: row west of the aisle (fronts face east)
			zN = rackRow(p, name, cx - side * 4.11, side, if row == 1 then "E" else "W", zS, 14, trayZ - 0.7, row == (p % 2) + 1)
		end
		local L = zN - zS
		local zM = (zS + zN) / 2
		-- containment: glass roof over the cold aisle, end door tracks with half-open sliding leaves
		local roofY = fy + 7.62
		box(r, "AisleRoof", V3(4.1, 0.08, L), CF(cx, roofY, zM), C.glass, M.glass, GLASS)
		for _, s in { -1, 1 } do
			box(r, "AisleRoofRail", V3(0.2, 0.3, L), CF(cx + s * 2.05, roofY, zM), C.metal, M.metal, DETAIL)
		end
		local strip = box(r, "AisleLightStrip", V3(0.4, 0.06, L - 2), CF(cx, roofY - 0.08, zM), C.lightCool, M.neon, DETAIL)
		if p ~= 2 then
			Kit.light(strip, "surface", "tech", 12, 0.6, Enum.NormalId.Bottom)
		end
		for _, ez in { zS, zN } do
			local out = if ez > zM then 1 else -1
			box(r, "AisleTrack", V3(6.4, 0.4, 0.25), CF(cx, fy + 7.4, ez + out * 0.13), C.metal, M.metal)
			for _, s in { -1, 1 } do
				box(r, "AisleSlider", V3(1.7, 7.1, 0.08), CF(cx + s * 2.25, fy + 3.6, ez + out * 0.3), C.glass, M.glass, GLASS_DECOR)
			end
		end
		plate(r, "PodSign", 3.0, 0.8, CF(cx, fy + 8.1, zN + 0.33) * ANG(0, PI, 0), "POD " .. name .. " · COLD AISLE", C.metal, ctx.accent)
		local tiles = box(r, "PerforatedTiles", V3(3.9, 0.05, L - 0.4), CF(cx, fy + 0.025, zM), C.white, M.smooth, DETAIL)
		stripes(tiles, Enum.NormalId.Top, C.white, C.concrete, 20, 0)
		for _, sz in { zS + 2.5, zM, zN - 2.5 } do
			strut(r, cx - 6.2, cx + 6.2, fy + 9.3, sz, top)
		end
	end
	-- Pod D (phase 2) in commissioning: first row installed, the rest marked on the floor.
	local dS, dN = -36.5, -5.5
	rackRow(4, "D", -79.9 - 4.11, 1, "E", dN - 19, 8, dN, false)
	plate(r, "PodSign", 4.4, 0.9, CF(-79.9, fy + 8.1, dN + 0.33) * ANG(0, PI, 0), "POD D · PHASE 2 · COMMISSIONING", C.statusBusy, C.screen)
	strut(r, -86.2, -80.4, fy + 9.3, -12, top)
	local function tape(x1: number, x2: number, z1: number, z2: number, label_: string)
		for _, e in { { (x1 + x2) / 2, z1, x2 - x1, 0.3 }, { (x1 + x2) / 2, z2, x2 - x1, 0.3 }, { x1, (z1 + z2) / 2, 0.3, z2 - z1 }, { x2, (z1 + z2) / 2, 0.3, z2 - z1 } } do
			box(r, "FloorTape", V3(e[3], 0.05, e[4]), CF(e[1], fy + 0.025, e[2]), C.statusBusy, M.smooth, DETAIL)
		end
		local fl = box(r, "FloorMarking", V3(math.min(16, x2 - x1 - 2), 2.6, 0.05), CF((x1 + x2) / 2, fy + 0.03, (z1 + z2) / 2) * ANG(PI / 2, 0, 0), C.plasterShade, M.smooth, DETAIL)
		fl.Transparency = 1
		label(fl, label_, { color = C.statusBusy, light = 0.4 })
	end
	tape(-86.2, -73.6, dS, dN, "POD D")
	tape(-68.8, -39.0, dS, dN, "POD E · RESERVED · PHASE 3")
	-- network core row (patch panels, yellow fibre), fronts towards the pods
	for i = 1, 6 do
		Kit.serverRack(r.m, r.cf, Kit.place(-68.5 + (i - 1) * 2 + 1, fy, netZ, "S"), r.seed + 900 + i, nil, { variant = "network", index = 0, trayY = 9.4, name = "NetworkRack" })
	end
	for _, x in { -69.25, -55.75 } do
		box(r, "RowPDU", V3(1.5, 7.5, 3.9), Kit.place(x, fy, netZ, "S") * CF(0, 3.75, 0.05), C.metalSoft, M.metal)
	end
	plate(r, "RowSign", 4.6, 0.9, CF(-62.5, fy + 8.0, netFront - 0.1), "NETWORK CORE · MEET-ME ROW", C.metal, C.white)
	box(r, "FibreTray", V3(48.4, 0.35, 1.4), CF(-62.6, fy + 9.575, trayZ), C.statusBusy, M.smooth)
	for _, x in { -84, -62.5, -41 } do
		strut(r, x - 0.8, x + 0.8, fy + 9.3, trayZ, top)
	end
	act += 1
	activity(r, "DataHallRack" .. act, "ServerRack", "compute", V3(-62.5, 0, netFront - 1.4), V3(-62.5, 0, netZ))
	-- CRAH units along the west and south walls
	for i, z in { -16, 4, 14, 24, 34 } do
		crah(r, Kit.place(-93.5, fy, z, "E"), string.format("CRAH %02d\n18.0°C", i), 7, 8.6)
	end
	for i, x in { -80, -62 } do
		crah(r, Kit.place(x, fy, -63.5, "N"), string.format("CRAH %02d\n18.2°C", i + 5), 7, 8.6)
	end
	-- gas fire-suppression cylinders on the north wall
	local fs = Kit.place(-60, fy, 63.5, "S")
	for _, ry in { 1.2, 4.6 } do
		box(r, "CylinderRail", V3(9.6, 0.3, 0.3), fs * CF(0, ry, -0.2), C.metal, M.metal)
	end
	for i = 0, 5 do
		cyl(r, "SuppressionCylinder", "y", 5.4, 1.15, fs * CF(-3.75 + i * 1.5, 2.8, -0.75), C.terracotta, M.metal)
	end
	cyl(r, "SuppressionManifold", "x", 9.4, 0.35, fs * CF(0, 6.3, -0.75), C.metalSoft, M.metal)
	cyl(r, "SuppressionRiser", "y", top - fy - 6.3, 0.35, fs * CF(4.7, (6.3 + top - fy) / 2, -0.75), C.metalSoft, M.metal)
	plate(r, "SuppressionSign", 4.6, 1.2, fs * CF(-1, 7.9, -0.06), "GAS SUPPRESSION\nDO NOT ENTER WHEN ALARM SOUNDS", C.statusBad, C.white)
	-- NOC kiosk at the lift-lobby entrance
	local noc = Kit.place(-30, fy, 57.5, "S")
	box(r, "NOCDesk", V3(6, 0.25, 2.4), noc * CF(0, 3.9, 0), C.oakDark, M.wood)
	box(r, "NOCPedestal", V3(5.4, 3.78, 1.6), noc * CF(0, 1.89, 0.2), C.metal, M.metal)
	for k, kind in { "compute", "training" } do
		local sx = if k == 1 then -1.55 else 1.55
		box(r, "NOCScreenPost", V3(0.25, 1.4, 0.25), noc * CF(sx, 4.7, 0.95), C.metal, M.metal, DETAIL)
		Kit.screen(r.m, r.cf, "NOCScreen", V3(3.0, 1.8, 0.1), noc * CF(sx, 6.2, 0.85) * ANG(0, sx * 0.08, 0), kind, ctx.accent)
	end
	plate(r, "NOCSign", 4.4, 0.7, noc * CF(0, 2.6, -0.62), "NOC · DATA HALL B1", C.metal, ctx.accent)
	Kit.stool(r.m, r.cf, Kit.place(-30, fy, 55.2, "N"), r.seed + 5, 3.0)
	-- staging / burn-in bench and a server cart by the garage exit
	Kit.workbench(r.m, r.cf, Kit.place(-31, fy, -63.5, "N"), 8, r.seed + 6)
	plate(r, "StagingSign", 6, 0.9, Kit.place(-31, fy, -63.5, "N") * CF(0, 7.6, -0.06), "STAGING · BURN-IN", C.metal, C.white)
	local cart = Kit.place(-38, fy, -57.5, "N")
	box(r, "ServerCart", V3(3, 0.3, 5), cart * CF(0, 1.0, 0), C.metalSoft, M.metal)
	box(r, "CartHandle", V3(3, 3.0, 0.15), cart * CF(0, 2.0, 2.45), C.metal, M.metal)
	box(r, "CartBase", V3(2.6, 0.85, 4.4), cart * CF(0, 0.43, 0), C.metal, M.metal)
	for i = 0, 1 do
		box(r, "ServerBox", V3(2.4, 1.0, 2.0), cart * CF(0, 1.65, -1.1 + i * 2.2), C.fabricSand, M.smooth)
	end
	-- engineers pick up a GPU blade here before they service a rack (EmployeeConfig task via = "Pickup")
	activity(r, "ServerCartPickup", "Pickup", "compute", V3(-35.0, 0, -57.5), V3(-38, 0, -57.5), nil, nil, { JobItem = "blade" })
	-- crated racks for pod D waiting beside the staging bench
	for i = 0, 3 do
		local crate = box(r, "RackCrate", V3(2.6, 8.2, 4.6), Kit.place(-52 + i * 3.2, fy, -58.5, "N") * CF(0, 4.1, 0), C.oakLight, M.wood)
		if i == 0 then
			label(crate, "GPU RACK · POD D", { face = Enum.NormalId.Front, color = C.metal, light = 0.5 })
		end
	end
	plate(r, "HallSign", 7, 1.2, Kit.place(-22.5, fy, 54, "W") * CF(0, 9.2, -0.06), "DATA HALL B1 · COMPUTE ENGINEERS", C.metal, ctx.accent)
end

---------------------------------------------------------------------------------------------
-- B1 · Underground garage
---------------------------------------------------------------------------------------------
local function garage(r: R)
	local y = r.y
	local top = Plan.levelY(0) - 1 -- underside of the ground slab
	local function bayLine(x: number, zc: number)
		box(r, "BayLine", V3(0.25, 0.06, 18), CF(x, y + 0.03, zc), C.white, M.smooth, DETAIL)
	end
	local function floorText(name: string, w: number, d: number, x: number, z: number, text: string, color: Color3, yawDeg: number?)
		local p = box(r, name, V3(w, d, 0.05), CF(x, y + 0.035, z) * ANG(0, math.rad(yawDeg or 0), 0) * ANG(PI / 2, 0, 0), C.asphalt, M.smooth, DETAIL)
		p.Transparency = 1
		label(p, text, { color = color, light = 0.5 })
	end
	local function column(x: number, z: number)
		box(r, "GarageColumn", V3(1.8, top - y, 1.8), CF(x, (y + top) / 2, z), C.concrete, M.concrete)
		box(r, "ColumnGuard", V3(1.95, 1.4, 1.95), CF(x, y + 0.9, z), C.statusBusy, M.smooth)
	end
	-- front row: bays 01-10 against the south wall, EV chargers on bays 01-06
	local fw = 10.6
	for k = 0, 10 do
		bayLine(-18 + k * fw, -54)
	end
	for i = 1, 10 do
		local xc = -18 + (i - 0.5) * fw
		box(r, "WheelStop", V3(5.5, 0.4, 0.7), CF(xc, y + 0.2, -61.6), C.concrete, M.concrete)
		plate(r, "BayNumber", 3.6, 1.2, Kit.place(xc, y, -63.5, "N") * CF(0, 8.2, -0.06), string.format("B1 — %02d", i), C.metal, C.white)
		if i <= 6 then
			-- EV charger as a PropFx prop: the screen shows CHARGING and the status strip blinks while
			-- fleet staff charge a car (or a player plugs in)
			local ev = Kit.place(xc + 3.4, y, -63.5, "N")
			local charger = box(r, "EVCharger", V3(1.4, 2.2, 0.6), ev * CF(0, 4.2, -0.3), C.white, M.smooth)
			local scr = Kit.part(charger, r.cf, "EVScreen", V3(0.95, 0.5, 0.05), ev * CF(0, 4.75, -0.63), C.screen, M.smooth, DETAIL)
			label(scr, "EV READY", { color = C.statusGood, light = 0 })
			local strip = Kit.part(charger, r.cf, "EVStatus", V3(0.9, 0.08, 0.05), ev * CF(0, 4.3, -0.63), C.metalSoft, M.neon, DETAIL)
			strip:SetAttribute("FxGlow", true)
			box(r, "EVCable", V3(0.2, 2.4, 0.2), ev * CF(0.45, 2.3, -0.7), C.screen, M.rubber, DETAIL)
			box(r, "EVBayPaint", V3(fw - 0.6, 0.05, 17.4), CF(xc, y + 0.025, -54), C.sage, M.smooth, DETAIL)
			fx(charger, "screen,blink", { FxText = "CHARGING", FxColor = C.statusGood, FxRate = 1, FxSeconds = 20, PropId = "EVCharger" .. i })
			Kit.action(charger, "prop", "EV charger", "EVCharger" .. i, { actionText = "Charge", maxDistance = 7 })
			if i == 2 or i == 4 then
				-- parked company EV waiting on the charger (fleet staff plug it in)
				local cx = xc - 0.6
				box(r, "FleetCarBody", V3(6.4, 1.8, 12), CF(cx, y + 2.1, -54.5), r.accent, M.smooth)
				box(r, "FleetCarRoof", V3(5.6, 1.4, 6), CF(cx, y + 3.7, -54), r.accent, M.smooth)
				box(r, "FleetCarGlass", V3(5.0, 1.0, 6.2), CF(cx, y + 3.7, -54), C.glassDeep, M.glass, { transparency = 0.3, canCollide = false, canTouch = false, canQuery = false })
				for _, wx in { -3.25, 3.25 } do
					for _, wz in { -4, 4 } do
						cyl(r, "FleetCarWheel", "x", 0.8, 2.6, CF(cx + wx, y + 1.3, -54.5 + wz), C.screen, M.rubber, DETAIL)
					end
				end
			end
		end
	end
	for k = 0, 10, 2 do
		column(-18 + k * fw, -46.2)
	end
	-- back row: bay 11 west of the pedestrian crossing, bays 12-19 east of it
	local bw = (88 - 7.5) / 8
	bayLine(-18, 26)
	bayLine(-7.5, 26)
	for k = 0, 8 do
		bayLine(7.5 + k * bw, 26)
	end
	local backBays = { -12.75 }
	for i = 1, 8 do
		table.insert(backBays, 7.5 + (i - 0.5) * bw)
	end
	for i, xc in backBays do
		box(r, "WheelStop", V3(5.5, 0.4, 0.7), CF(xc, y + 0.2, 33.6), C.concrete, M.concrete)
		floorText("BayNumber", 4, 1.5, xc, 18.9, string.format("B1 — %02d", 10 + i), C.white)
	end
	for _, x in { -18, -7.5, 7.5, 7.5 + 2 * bw, 7.5 + 4 * bw, 7.5 + 6 * bw, 88 } do
		column(x, 18.0)
	end
	-- pedestrian crossing to the lift lobby
	for k = 0, 5 do
		box(r, "ZebraStripe", V3(13, 0.05, 1.4), CF(0, y + 0.025, 18.6 + k * 3), C.white, M.smooth, DETAIL)
	end
	-- drive arrows in the aisle and on the ramp lane
	local function arrow(x: number, z: number, yawDeg: number)
		local a = CF(x, y + 0.03, z) * ANG(0, math.rad(yawDeg), 0)
		box(r, "DriveArrow", V3(0.6, 0.05, 5), a, C.white, M.smooth, DETAIL)
		for _, s in { -1, 1 } do
			box(r, "DriveArrow", V3(0.6, 0.05, 2.4), a * CF(s * 0.69, 0, -2.12 - 0.5) * ANG(0, s * math.rad(35), 0), C.white, M.smooth, DETAIL)
		end
	end
	for _, x in { 10, 40, 70 } do
		arrow(x, -24, 90)
		arrow(x, -4, -90)
	end
	arrow(97, -26, 180)
	arrow(107, -26, 0)
	-- company car pick-up bay at the spawn point (kept free of parts)
	local spawnCF = r.cf * Plan.GARAGE_SPAWN
	local sp = Plan.GARAGE_SPAWN.Position
	local marker = box(r, "GarageSpawn", V3(1, 1, 1), Plan.GARAGE_SPAWN, C.white, nil, { detail = true, transparency = 1 })
	marker:SetAttribute("SpawnCFrame", spawnCF)
	for _, e in { { sp.X, sp.Z - 9.3, 9.6, 0.3 }, { sp.X, sp.Z + 9.3, 9.6, 0.3 }, { sp.X - 4.8, sp.Z, 0.3, 18.9 }, { sp.X + 4.8, sp.Z, 0.3, 18.9 } } do
		box(r, "PickupBayLine", V3(e[3], 0.05, e[4]), CF(e[1], y + 0.025, e[2]), C.statusBusy, M.smooth, DETAIL)
	end
	local cAt = at(r, 90.3, 21, "E")
	local collect = box(r, "CarCollection", V3(2.4, 4.6, 1.0), cAt * CF(0, 2.3, 0), C.metal, M.metal)
	collect:SetAttribute("OwnerUserId", r.owner)
	label(collect, "COLLECT CAR\nCompany fleet", { color = C.white, light = 0.3 })
	Kit.action(collect, "spawnCar", "Collect selected car", nil, { ownerUserId = r.owner, actionText = "Collect", maxDistance = 10 })
	-- fleet terminal in front of the fleet office
	local fAt = at(r, 25.6, 41.6, "S")
	local terminal = box(r, "FleetTerminal", V3(2.4, 5.2, 1.0), fAt * CF(0, 2.6, 0), C.metal, M.metal)
	label(terminal, "FLEET DESK\nYour car · your keys", { color = C.white, light = 0.3 })
	Kit.prompt(terminal, "Company fleet", r.owner, "campus", "fleet")
	-- security booth on a kerbed island beside the ramp lane (operations post 4)
	local bx, bz = 85, -32
	local by = y + 0.3
	box(r, "BoothIsland", V3(8.4, 0.3, 8.4), CF(bx, y + 0.15, bz), C.concrete, M.concrete)
	box(r, "IslandKerb", V3(8.6, 0.12, 8.6), CF(bx, y + 0.06, bz), C.statusBusy, M.smooth, DETAIL)
	for _, cx in { -1, 1 } do
		for _, cz in { -1, 1 } do
			box(r, "BoothPost", V3(0.3, 8.4, 0.3), CF(bx + cx * 3.05, by + 4.2, bz + cz * 3.05), C.metal, M.metal)
		end
	end
	box(r, "BoothGlass", V3(0.15, 6, 5.8), CF(bx + 3.05, by + 4.6, bz), C.glass, M.glass, GLASS)
	box(r, "BoothGlass", V3(5.8, 6, 0.15), CF(bx, by + 4.6, bz - 3.05), C.glass, M.glass, GLASS)
	box(r, "BoothGlass", V3(5.8, 6, 0.15), CF(bx, by + 4.6, bz + 3.05), C.glass, M.glass, GLASS)
	for _, cz in { -1, 1 } do
		box(r, "BoothGlass", V3(0.15, 6, 1.0), CF(bx - 3.05, by + 4.6, bz + cz * 2.4), C.glass, M.glass, GLASS)
	end
	box(r, "BoothApron", V3(6.4, 1.6, 6.4), CF(bx, by + 0.8, bz), C.metalSoft, M.metal, { canCollide = false, canQuery = false, canTouch = false, transparency = 1 })
	box(r, "BoothRoof", V3(7.2, 0.4, 7.2), CF(bx, by + 8.6, bz), C.metal, M.metal)
	plate(r, "BoothSign", 5, 0.8, CF(bx, by + 7.9, bz - 3.2), "GARAGE SECURITY", C.metal, C.white)
	box(r, "BoothDesk", V3(1.4, 0.15, 5.4), CF(bx + 2.1, by + 3.1, bz), C.oakLight, M.wood)
	box(r, "BoothDeskBody", V3(1.2, 3.0, 5.2), CF(bx + 2.2, by + 1.5, bz), C.metalSoft, M.metal)
	box(r, "Monitor", V3(0.12, 1.2, 1.9), CF(bx + 2.5, by + 3.9, bz - 1.2), C.screen, M.smooth)
	local seat = Kit.officeChair(r.m, r.cf, CF(bx + 0.2, by, bz) * ANG(0, -PI / 2, 0), r.seed + 9, { lite = true, arms = true, canTouch = false })
	-- patrol through the aisle to the ramp foot (the guard checks the ramp up to the barrier) and back
	local route = { V3(78, 0, -32), V3(55, 0, -28), V3(20, 0, -18), V3(-8, 0, -28), V3(40, 0, -42), V3(98, 0, -42), V3(78, 0, -40) }
	local looks = { V3(60, 0, -30), V3(40, 0, -60), V3(20, 0, 10), V3(-20, 0, -40), V3(60, 0, -42), V3(98, 0, -70), V3(85, 0, -32) }
	local garagePoints: { JobPoint } = {}
	for i, p in route do
		-- point 6 is the ramp foot: the guard looks up the ramp to the street barrier
		table.insert(garagePoints, jp("patrol" .. i, p, looks[i], nil, if i == 6 then "inspect" else nil))
	end
	opsPost(r, 4, V3(bx - 2.0, 0, bz), V3(bx + 4, 0, bz), seat, garagePoints)
	-- convex mirror at the ramp foot (the ramp lands at z -36; x 92..112, z -64..-36 stays free)
	cyl(r, "MirrorPost", "y", 8.0, 0.25, CF(90.6, y + 4.0, -38.5), C.statusBusy, M.metal)
	local mAt = CF(90.6, y + 8.4, -38.5) * ANG(0, math.rad(yawTo(0.7, -1)), 0)
	cyl(r, "ConvexMirror", "z", 0.3, 2.4, mAt, C.glassDeep, M.glass, { reflectance = 0.4 })
	cyl(r, "MirrorRim", "z", 0.2, 2.7, mAt * CF(0, 0, 0.12), C.statusBusy, M.smooth, DETAIL)
	-- bike parking against the data hall wall
	for k = 0, 5 do
		box(r, "BikeStand", V3(2.6, 2.6, 0.15), CF(-20.0, y + 1.3, -28 + k * 2.2), C.metal, M.metal)
	end
	plate(r, "BikeSign", 4, 0.9, Kit.place(-21.45, y, -22.5, "E") * CF(0, 5.2, -0.06), "BIKE PARKING", C.metal, C.white)
	-- signage to the lift lobby and the street
	hanging(r, "LiftSign", 10, 1.6, CF(0, top - 2.6, 13.5), top, "↑  LIFT · RECEPTION · ALL FLOORS", C.metal, C.white)
	hanging(r, "LiftSign", 10, 1.6, CF(86.5, top - 2.6, -10) * ANG(0, -PI / 2, 0), top, "←  LIFT LOBBY · FLEET OFFICE", C.metal, C.white)
	hanging(r, "ExitSign", 8, 1.4, CF(102, top - 2.6, -28), top, "EXIT · STREET  ↓", C.statusGood, C.white)
	-- linear light fittings under the slab
	for i, z in { -54, -14, 26 } do
		local strip = box(r, "GarageLightStrip", V3(100, 0.15, 0.5), CF(35, top - 0.1, z), C.lightCool, M.neon, DETAIL)
		Kit.light(strip, "surface", "tech", 16, if i == 2 then 0.7 else 0.55, Enum.NormalId.Bottom)
	end
end

---------------------------------------------------------------------------------------------
-- B1 · Garage lift lobby
---------------------------------------------------------------------------------------------
local function b1Lobby(r: R)
	Kit.bench(r.m, r.cf, at(r, -14, 41.4, "N"), 6, r.seed, { color = C.oak })
	Kit.vending(r.m, r.cf, at(r, 13.5, 53.5, "S"), r.seed + 3, { propId = "GarageVending", prompt = "Vending machine" })
	Kit.plant(r.m, r.cf, at(r, 19.4, 42.4), "m", r.seed + 1)
	Kit.plant(r.m, r.cf, at(r, -19.4, 51.4), "l", r.seed + 2)
	Kit.wayfinding(r.m, r.cf, at(r, 21.5, 47, "W"), {
		"B1  ·  " .. Plan.levelName(r.ctx.tier, -1),
		"←  Data Hall  ·  Compute engineers",
		"←  UPS & Energy Plant  ·  Technical staff",
		"→  Fleet Office",
		"→  Workshop  ·  Goods-in & IT Storage",
		"↓  Underground Garage",
		"↑  Lift to all floors",
	}, { name = "FloorDirectory", h = 0.55 })
end

---------------------------------------------------------------------------------------------
-- B1 · UPS & battery room
---------------------------------------------------------------------------------------------
local function upsRoom(r: R)
	for i = 0, 2 do
		local u = at(r, -55 + i * 3.9, 79.5, "S")
		box(r, "UPSCabinet", V3(3.7, 7.2, 3.0), u * CF(0, 3.6, -1.5), C.plasterShade, M.metal)
		box(r, "UPSPanel", V3(3.4, 2.4, 0.05), u * CF(0, 5.4, -3.03), C.metal, M.metal, DETAIL)
		local d = box(r, "UPSDisplay", V3(1.4, 0.8, 0.05), u * CF(0, 5.6, -3.07), C.screen, M.smooth, DETAIL)
		label(d, "UPS " .. string.char(65 + i) .. "\nONLINE · 98%", { color = C.statusGood, light = 0 })
		local vent = box(r, "UPSVent", V3(3.0, 2.6, 0.05), u * CF(0, 1.8, -3.03), C.metalSoft, M.metal, DETAIL)
		stripes(vent, Enum.NormalId.Front, C.metalSoft, C.screen, 14, 90)
	end
	for k, z in { 67.6, 75.4 } do
		local b = at(r, -29.5, z, if k == 1 then "N" else "S")
		for _, sx in { -1, 1 } do
			box(r, "BatteryFrame", V3(0.2, 5.6, 2.0), b * CF(sx * 5.9, 2.8, 0), C.metal, M.metal)
		end
		for s = 0, 2 do
			local sy = 0.4 + s * 1.8
			box(r, "BatteryShelf", V3(11.8, 0.12, 2.0), b * CF(0, sy, 0), C.metalSoft, M.metal)
			local cells = box(r, "BatteryString", V3(11.2, 1.1, 1.6), b * CF(0, sy + 0.61, 0), C.fabricCharcoal, M.smooth)
			stripes(cells, Enum.NormalId.Front, C.fabricCharcoal, C.metalSoft, 20, 0)
			box(r, "BatteryTerminals", V3(11.0, 0.08, 0.2), b * CF(0, sy + 1.2, -0.6), C.terracotta, M.metal, DETAIL)
		end
	end
	local pd = at(r, -57.5, 69, "E")
	local board = box(r, "DistributionBoard", V3(5, 7, 0.8), pd * CF(0, 3.9, -0.4), C.plasterShade, M.metal)
	label(board, "MAIN LV DISTRIBUTION\nDB-B1-01", { color = C.metal, light = 0.4, valign = "top" })
	plate(r, "WarningSign", 2.6, 1.3, pd * CF(0, 8.4, -0.06), "DANGER\nHIGH VOLTAGE", C.statusBusy, C.screen)
	plate(r, "WarningSign", 3.4, 1.3, at(r, -29.5, 79.5, "S") * CF(0, 8.2, -0.06), "BATTERY ROOM\nNO NAKED FLAMES", C.statusBusy, C.screen)
	box(r, "CableTray", V3(34, 0.35, 1.4), pt(r, -40, 9.6, 72), C.metalSoft, M.metal)
	box(r, "PowerBusway", V3(34, 0.55, 0.5), pt(r, -40, 8.9, 70.8), C.screen, M.metal)
	for _, x in { -52, -28 } do
		strut(r, x - 0.4, x + 0.4, r.y + 9.32, 72, r.ceil)
	end
end

---------------------------------------------------------------------------------------------
-- B1 · Energy & plant room (operations post 11)
---------------------------------------------------------------------------------------------
local function plantRoom(r: R)
	for i = 0, 4 do
		local s = at(r, -92 + i * 2.5, 79.5, "S")
		box(r, "Switchgear", V3(2.45, 7.6, 2.6), s * CF(0, 3.8, -1.3), C.plasterShade, M.metal)
		box(r, "SwitchgearMeter", V3(1.0, 0.7, 0.05), s * CF(0, 5.8, -2.63), C.screen, M.smooth, DETAIL)
		box(r, "SwitchgearHandle", V3(0.15, 1.0, 0.15), s * CF(0.8, 3.6, -2.68), C.metal, M.metal, DETAIL)
	end
	for i = 0, 2 do
		local b = at(r, -91 + i * 3.8, 64.5, "N")
		box(r, "BatteryCabinet", V3(3.6, 6.4, 2.4), b * CF(0, 3.2, -1.2), C.fabricCharcoal, M.metal)
		box(r, "CabinetLED", V3(0.6, 0.15, 0.05), b * CF(1.2, 5.6, -2.43), C.statusGood, M.neon, DETAIL)
	end
	for i = 1, 3 do
		Kit.serverRack(r.m, r.cf, at(r, -60.5, 65.5 + i * 2, "W"), r.seed + i, nil, { variant = "network", index = 0, trayY = 9.4, name = "NetworkRack" })
	end
	box(r, "FibreTray", V3(1.4, 0.35, 8), pt(r, -59.7, 9.575, 69.5), C.statusBusy, M.smooth)
	strut(r, -61, -58.6, r.y + 9.3, 69.5, r.ceil)
	-- building management console
	local bms = at(r, -66, 79.5, "S")
	local scr = box(r, "BMSPanel", V3(4.2, 2.6, 0.2), bms * CF(0, 5.4, -0.1), C.screen, M.smooth)
	label(scr, "BMS · PLANT STATUS\nChillers OK · UPS OK · Generator standby", { color = C.statusGood, light = 0, align = "left" })
	box(r, "BMSDesk", V3(4.4, 0.2, 1.8), bms * CF(0, 3.6, -0.9), C.metalSoft, M.metal)
	box(r, "BMSDeskBody", V3(4.0, 3.5, 1.4), bms * CF(0, 1.75, -0.7), C.metal, M.metal)
	-- facilities (post 11): BMS console, switchgear round, battery cabinets
	opsPost(r, 11, V3(-66, 0, 75.6), V3(-66, 0, 79.5), nil, {
		jp("bms", V3(-66, 0, 75.6), V3(-66, 0, 79.5)),
		jp("switchgear", V3(-87, 0, 74.4), V3(-87, 0, 77)),
		jp("batteries", V3(-87.2, 0, 69.4), V3(-87.2, 0, 66.9)),
	})
	cyl(r, "ChilledWaterFlow", "x", 35, 0.9, pt(r, -76, 11.2, 71), C.blue, M.metal)
	cyl(r, "ChilledWaterReturn", "x", 35, 0.9, pt(r, -76, 11.2, 72.6), C.blueSoft, M.metal)
	for _, x in { -88, -64 } do
		strut(r, x - 0.4, x + 0.4, r.y + 10.6, 71.8, r.ceil)
	end
	plate(r, "WarningSign", 3.0, 1.3, at(r, -93.5, 70, "E") * CF(0, 8.2, -0.06), "DANGER\n11 kV SWITCHGEAR", C.statusBusy, C.screen)
	plate(r, "PlantSign", 4.6, 0.9, at(r, -84, 64.5, "N") * CF(0, 9.4, -0.06), "ENERGY & PLANT · TECHNICAL STAFF", C.metal, C.white)
end

---------------------------------------------------------------------------------------------
-- B1 · Fleet office (desk station + operations post 12)
---------------------------------------------------------------------------------------------
local function fleetOffice(r: R)
	Kit.station(r.m, r.cf, r.room.id .. "_Desk1", "operations", nil, at(r, 27.5, 61.0, "S"), r.level, "ldesk", r.owner, r.accent, "campus", "fleet", r.room.access, r.room.id)
	local dAt = at(r, 36.5, 61.0, "S")
	local _, topY = Kit.desk(r.m, r.cf, dAt, "bench", r.seed + 1)
	box(r, "Monitor", V3(3.2, 1.9, 0.12), dAt * CF(0, topY + 1.35, 0.85), C.screen, M.smooth)
	local seat = opsChair(r, dAt * CF(0, 0, -2.9) * ANG(0, PI, 0), r.seed + 2)
	-- fleet (post 12): desk, key cabinet, and charging the parked company EVs in bays 02 / 04
	-- (points "ev2" / "ev4" lie in the garage: reached by navigation through the office door)
	opsPost(r, 12, V3(39.3, 0, 57.6), V3(36.5, 0, 61), seat, {
		jp("keys", V3(25.9, 0, 49), V3(22.5, 0, 49)),
		jp("ev2", V3(2.2, 0, -60.4), V3(1.3, 0, -63.5), "EVCharger2"),
		jp("ev4", V3(23.4, 0, -60.4), V3(22.5, 0, -63.5), "EVCharger4"),
	})
	Kit.cabinet(r.m, r.cf, at(r, 22.5, 49, "E"), 3, 6, r.seed + 3)
	plate(r, "KeySign", 2.6, 0.6, at(r, 22.5, 49, "E") * CF(0, 6.6, -0.06), "FLEET KEYS", C.metal, C.white)
	Kit.tvScreen(r.m, r.cf, at(r, 22.5, 55.5, "E"), 6, "fleet", r.accent, { name = "FleetScreen" })
	Kit.loungeChair(r.m, r.cf, at(r, 42, 47.6, "W"), r.seed + 4)
	Kit.loungeChair(r.m, r.cf, at(r, 42, 51.6, "W"), r.seed + 5)
	Kit.plant(r.m, r.cf, at(r, 44.4, 62.2), "m", r.seed + 6)
end

---------------------------------------------------------------------------------------------
-- B1 · Workshop (operations post 5)
---------------------------------------------------------------------------------------------
local function workshop(r: R)
	-- two-post car lift (PropFx slider): the car rests on the arms just off the floor and is raised
	-- 2.9 studs while the mechanic inspects it; everything that moves is non-colliding
	local lift = Kit.propModel(r.m, r.cf, "CarLift", pt(r, 30, 0, 72))
	local MOVE: Kit.Opts = { canCollide = false, castShadow = true }
	local function moving(p: BasePart)
		p:SetAttribute("FxMove", true)
	end
	local liftPost: BasePart? = nil
	for _, x in { 24.5, 35.5 } do
		local post = Kit.part(lift, r.cf, "LiftPost", V3(1.2, 11, 1.2), pt(r, x, 5.5, 72), C.blue, M.metal)
		if x > 30 then
			liftPost = post
		end
		Kit.part(lift, r.cf, "LiftFoot", V3(2.2, 0.2, 2.2), pt(r, x, 0.1, 72), C.metal, M.metal)
		for _, dz in { -1, 1 } do
			moving(Kit.part(lift, r.cf, "LiftArm", V3(4.2, 0.3, 0.5), pt(r, x + (if x < 30 then 2.0 else -2.0), 1.0, 72 + dz * 2.6) * ANG(0, dz * (if x < 30 then -0.4 else 0.4), 0), C.metalSoft, M.metal, MOVE))
		end
	end
	Kit.part(lift, r.cf, "LiftCrossbar", V3(12.2, 0.6, 0.8), pt(r, 30, 11.3, 72), C.blue, M.metal)
	moving(Kit.part(lift, r.cf, "CarBody", V3(6.4, 1.8, 12), pt(r, 30, 2.1, 72), C.blueSoft, M.smooth, MOVE))
	moving(Kit.part(lift, r.cf, "CarRoof", V3(5.6, 1.4, 6), pt(r, 30, 3.7, 72.5), C.blueSoft, M.smooth, MOVE))
	moving(Kit.part(lift, r.cf, "CarGlass", V3(5.0, 1.0, 6.2), pt(r, 30, 3.7, 72.5), C.glassDeep, M.glass, { transparency = 0.3, canCollide = false, canTouch = false, canQuery = false }))
	for _, wx in { -3.25, 3.25 } do
		for _, wz in { -4, 4 } do
			moving(Kit.cylinder(lift, r.cf, "CarWheel", "x", 0.8, 2.6, pt(r, 30 + wx, 1.3, 72 + wz), C.screen, M.rubber, DETAIL))
		end
	end
	fx(lift, "slider", { FxAxis = "y", FxTravel = 2.9, FxSeconds = 14, PropId = "CarLift" })
	if liftPost then
		Kit.action(liftPost, "prop", "Car lift", "CarLift", { actionText = "Raise", maxDistance = 9 })
	end
	for _, e in { { 30, 64.9, 14, 0.25 }, { 30, 79.1, 14, 0.25 }, { 23.1, 72, 0.25, 14.2 }, { 36.9, 72, 0.25, 14.2 } } do
		box(r, "LiftBayLine", V3(e[3], 0.05, e[4]), pt(r, e[1], 0.025, e[2]), C.statusBusy, M.smooth, DETAIL)
	end
	Kit.workbench(r.m, r.cf, at(r, 54, 79.5, "S"), 8, r.seed)
	Kit.toolWall(r.m, r.cf, at(r, 61.5, 72, "W"), 6, r.seed + 1)
	Kit.rackShelf(r.m, r.cf, at(r, 61.5, 66.6, "W"), 4, r.seed + 2)
	Kit.rackShelf(r.m, r.cf, at(r, 61.5, 77.2, "W"), 4, r.seed + 3)
	-- tyres and an oil drum between the lift bay and the door route (S door x 49..59, N door x 40..46)
	for i = 0, 2 do
		cyl(r, "Tyre", "y", 0.9, 2.6, pt(r, 39.6, 0.45 + i * 0.9, 66.2), C.screen, M.rubber, DETAIL)
	end
	cyl(r, "OilDrum", "y", 3.0, 2.0, pt(r, 39.6, 1.5, 69.4), C.terracotta, M.metal)
	-- facilities / mechanic (post 5): workbench and the car on the lift
	opsPost(r, 5, V3(54, 0, 75.4), V3(54, 0, 79.5), nil, {
		jp("bench", V3(54, 0, 75.4), V3(54, 0, 79.5)),
		jp("lift", V3(38.0, 0, 74.6), V3(33, 0, 74.6), "CarLift"),
	})
end

---------------------------------------------------------------------------------------------
-- B1 · Goods-in & IT storage
---------------------------------------------------------------------------------------------
local function storage(r: R)
	for _, xc in { 72, 102 } do
		for k, z in { 67.9, 76.1 } do
			Kit.shelfRack(r.m, r.cf, at(r, xc, z, if k == 1 then "N" else "S"), 16, r.seed + xc + k)
		end
	end
	-- pallet jack and an IT delivery beside the door aisle
	local pj = at(r, 81.6, 77.4, "N")
	box(r, "PalletJackForks", V3(2.0, 0.3, 4.0), pj * CF(0, 0.25, 0), C.terracotta, M.metal)
	box(r, "PalletJackHandle", V3(0.3, 3.6, 0.3), pj * CF(0, 2.0, 1.9) * ANG(math.rad(-15), 0, 0), C.metal, M.metal)
	local itp = at(r, 81.6, 67)
	box(r, "Pallet", V3(2.6, 0.4, 3.4), itp * CF(0, 0.2, 0), C.oakLight, M.wood)
	for i = 0, 2 do
		local b = box(r, "ITBox", V3(2.2, 1.2, 1.5), itp * CF(0, 1.0 + math.floor(i / 2) * 1.2, -0.8 + (i % 2) * 1.6), C.fabricSand, M.smooth)
		if i == 0 then
			label(b, "IT · LAPTOPS", { color = C.metal, light = 0.5 })
		end
	end
	plate(r, "StorageSign", 5, 0.9, at(r, 88, 79.5, "S") * CF(0, 10.6, -0.06), "GOODS-IN & IT STORAGE", C.metal, C.white)
end

---------------------------------------------------------------------------------------------
-- B1 · Technical spine, lift pit, service passage
---------------------------------------------------------------------------------------------
local function spine(r: R)
	local x1, x2 = -93.5, 111.5
	local L = x2 - x1
	local xc = (x1 + x2) / 2
	box(r, "SpineCableTray", V3(L, 0.35, 1.6), pt(r, xc, 9.6, 86.2), C.metalSoft, M.metal)
	box(r, "SpineFibreTray", V3(L, 0.3, 0.9), pt(r, xc, 8.9, 86.9), C.statusBusy, M.smooth, DETAIL)
	cyl(r, "ChilledWaterFlow", "x", L, 0.9, pt(r, xc, 11.2, 87.0), C.blue, M.metal)
	cyl(r, "ChilledWaterReturn", "x", L, 0.9, pt(r, xc, 12.2, 86.0), C.blueSoft, M.metal)
	for x = -88, 108, 28 do
		local slab = Plan.levelY(0) - 1 - r.y
		box(r, "PipeBracket", V3(0.2, slab - 8.6, 2.8), pt(r, x, (8.6 + slab) / 2, 86.2), C.metal, M.metal, DETAIL)
	end
	for _, z in { 80.6, 87.3 } do
		box(r, "FloorEdgeLine", V3(L, 0.05, 0.25), pt(r, xc, 0.025, z), C.statusBusy, M.smooth, DETAIL)
	end
	plate(r, "SpineSign", 7, 1.0, at(r, -50, 87.5, "S") * CF(0, 6.8, -0.06), "TECHNICAL SERVICE SPINE · AUTHORISED STAFF", C.metal, C.white)
	plate(r, "SpineSign", 7, 1.0, at(r, 0, 87.5, "S") * CF(0, 6.8, -0.06), "←  ENERGY PLANT · UPS        WORKSHOP · STORAGE  →", C.metal, C.white)
	plate(r, "SpineSign", 7, 1.0, at(r, 60, 87.5, "S") * CF(0, 6.8, -0.06), "←  LIFT PIT · SERVICE PASSAGE · DATA HALL", C.metal, C.white)
end

local function liftPit(r: R)
	for _, sx in { -0.75, 0.75 } do
		box(r, "LadderRail", V3(0.15, 10, 0.15), pt(r, 3.5 + sx, 5, 68.45), C.statusBusy, M.metal)
	end
	for k = 1, 9 do
		box(r, "LadderRung", V3(1.5, 0.1, 0.1), pt(r, 3.5, k * 1.0, 68.45), C.metal, M.metal, DETAIL)
	end
	box(r, "PitHatch", V3(2.6, 2.6, 0.12), pt(r, 3.5, 11.4, 68.32), C.metalSoft, M.metal, DETAIL)
	local cb = at(r, -6.5, 73, "E")
	box(r, "LiftController", V3(3, 6, 1.4), cb * CF(0, 3.5, -0.7), C.plasterShade, M.metal)
	local d = box(r, "ControllerDisplay", V3(1.2, 0.6, 0.05), cb * CF(0, 5.4, -1.43), C.screen, M.smooth, DETAIL)
	label(d, "LIFT 1 · NORMAL", { color = C.statusGood, light = 0 })
	for k = 0, 6 do
		box(r, "HazardStripe", V3(1.4, 0.05, 0.7), pt(r, -5.4 + k * 1.8, 0.025, 69.0) * ANG(0, math.rad(35), 0), if k % 2 == 0 then C.statusBusy else C.screen, M.smooth, DETAIL)
	end
	plate(r, "PitSign", 4.4, 1.2, at(r, -6.5, 76.4, "E") * CF(0, 6.4, -0.06), "LIFT MACHINE ACCESS\nAUTHORISED PERSONNEL ONLY", C.statusBusy, C.screen)
end

local function servicePassage(r: R)
	for i, z in { 59.5, 64.5, 69.5 } do
		Kit.rackShelf(r.m, r.cf, at(r, 21.5, z, "W"), 4.4, r.seed + i)
	end
	for i, z in { 72.5, 77 } do
		Kit.rackShelf(r.m, r.cf, at(r, 7.5, z, "E"), 4.0, r.seed + 10 + i)
	end
	plate(r, "ServiceSign", 4.4, 1.1, at(r, 21.5, 57.4, "W") * CF(0, 6.6, -0.06), "SERVICE · AUTHORISED STAFF", C.statusBusy, C.screen)
	box(r, "CableTray", V3(1.4, 0.35, 25), pt(r, 19.4, 9.6, 67), C.metalSoft, M.metal)
	strut(r, 18.4, 21.4, r.y + 9.32, 67, r.ceil)
end

---------------------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------------------
local KITS: { [string]: (R) -> () } = {
	lobby = lobby,
	atrium = atrium,
	visitor_lounge = visitorLounge,
	showroom = showroom,
	project_meeting = projectRoom,
	compute = computeOps,
	first_ai = firstAI,
	itdesk = itDesk,
	cafe = cafe,
	kitchen_boh = kitchenBoh,
	delivery = delivery,
	mailroom = mailroom,
	datahall = dataHall,
	garage = garage,
	b1_lobby = b1Lobby,
	ups = upsRoom,
	plant = plantRoom,
	fleet = fleetOffice,
	workshop = workshop,
	storage = storage,
	spine = spine,
	liftpit = liftPit,
	service_passage = servicePassage,
}
-- Build order: the G showcase racks come first so PlotService lights them before the data hall.
local ORDER = { "lobby", "atrium", "visitor_lounge", "showroom", "project_meeting", "compute", "first_ai", "itdesk", "cafe", "kitchen_boh", "delivery", "mailroom", "datahall", "garage", "b1_lobby", "ups", "plant", "fleet", "workshop", "storage", "spine", "liftpit", "service_passage" }
Special.KINDS = ORDER

local function roomModel(ctx: any, room: Room): Model
	local existing = ctx.rooms[room.id]
	if existing then
		return existing
	end
	local m = Kit.model(ctx.folders.Rooms, room.id, true)
	m:SetAttribute("RoomId", room.id)
	m:SetAttribute("RoomName", room.name)
	m:SetAttribute("RoomKind", room.kind)
	m:SetAttribute("Level", room.level)
	m:SetAttribute("AccessClass", room.access)
	ctx.rooms[room.id] = m
	return m
end

function Special.build(ctx: any)
	local rank: { [string]: number } = {}
	for i, kind in ORDER do
		rank[kind] = i
	end
	local list: { Room } = {}
	for _, room in Plan.rooms(ctx.tier) do
		if KITS[room.kind] then
			table.insert(list, room)
		end
	end
	table.sort(list, function(a: Room, b: Room): boolean
		if rank[a.kind] ~= rank[b.kind] then
			return rank[a.kind] < rank[b.kind]
		end
		return a.id < b.id
	end)
	local shared: Shared = { blade = 0, lunch = 0 }
	for _, room in list do
		local fit = Kit.model(roomModel(ctx, room), "Fitout")
		local levelY = Plan.levelY(room.level)
		local r: R = {
			ctx = ctx,
			room = room,
			m = fit,
			cf = ctx.cf,
			y = levelY + Kit.FINISH,
			ceil = levelY + Kit.CEILING,
			level = room.level,
			owner = ctx.owner,
			accent = ctx.accent,
			seed = Kit.hash(room.id) % 100000,
			s = shared,
		}
		local ok, err = pcall(KITS[room.kind] :: (R) -> any, r)
		if not ok then
			warn(`[RoomKitsSpecial] {room.id} ({room.kind}) failed: {err}`)
		end
	end
end

return Special
