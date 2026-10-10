--!strict
-- RoomKitsPavilion: furniture, fixtures, activities, screens and prompts of the wellness pavilion
-- (level 0), the founder services wing (level 1: campus security, founder archive, shelf passage,
-- hidden research lab, prototype lab, model vault), the roof (lobby, terrace, plant zone, solar
-- array, lift machine room) and the pavilion roof garden.
-- Walls, doors (incl. the bookcase, flush and vault doors), floors, ceilings, lights, nameplates,
-- cameras and access volumes come from InteriorDesign; this module only furnishes, and puts
-- everything into ctx.rooms[room.id] (WC cubicle doors go to Office.Doors, SPEC §3).
-- Fixture contracts (FacilityService): SPEC §6, FixtureKey based. Everything is building-local
-- through ctx.cf, so the pavilion works on every plot orientation.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Collection = game:GetService("CollectionService")
local Plan = require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Kit = require(script.Parent.ArchKit)

type Room = Plan.Room
-- Per-room build context. y = slab top of the level, fy = top of the floor finish (furniture
-- base indoors; outdoor rooms stand on the slab/paving: fy = y).
type B = {
	ctx: any,
	cf: CFrame,
	room: Room,
	m: Model,
	y: number,
	fy: number,
	owner: number,
	accent: Color3,
	seed: number,
}

local C = Kit.C
local M = Kit.M
local A = Kit.A
local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local PI = math.pi
local RAD = math.rad
local DETAIL: Kit.Opts = { detail = true }
local GLASS: Kit.Opts = { transparency = A.glassTransparency, castShadow = false }
local FROSTED: Kit.Opts = { transparency = 0.35, castShadow = false } -- privacy glass (showers)
local WATER: Kit.Opts = { detail = true, transparency = 1 } -- fixture water: hidden until used

local Pavilion = {}
local BUILD: { [string]: (B) -> () } = {}

---------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------
local function roomModel(ctx: any, room: Room): Model
	local existing = ctx.rooms[room.id]
	if existing then
		return existing
	end
	-- InteriorDesign normally creates the room models; keep the contract if it did not.
	local m = Kit.model(ctx.folders.Rooms, room.id, true)
	m:SetAttribute("RoomId", room.id)
	m:SetAttribute("RoomName", room.name)
	m:SetAttribute("RoomKind", room.kind)
	m:SetAttribute("Level", room.level)
	m:SetAttribute("AccessClass", room.access)
	ctx.rooms[room.id] = m
	return m
end

local function at(b: B, x: number, z: number, front: (string | number)?): CFrame
	return Kit.place(x, b.fy, z, front)
end

-- Text on one face; `size` = TextSize in px (nil = scaled to the face).
local function label(part: BasePart, text: string, color: Color3?, size: number?, face: Enum.NormalId?, align: string?): TextLabel
	return Kit.text(part, text, { color = color or C.white, size = size, face = face, align = align, light = 0.4, maxDistance = 60 })
end

-- Lounge activity (SPEC §10) around an existing Seat; `stand` = building-local standing point.
local function lounge(b: B, seat: Seat, index: number, department: string, stand: Vector3)
	local seatLocal = b.cf:ToObjectSpace(seat.CFrame)
	Kit.activity(b.m, b.cf, b.room.id .. "_Lounge" .. index, "Lounge", department, "any", CF(stand.X, b.fy + 2.8, stand.Z), b.room.level, b.owner, seat, {
		roomAccess = b.room.access,
		homeRoom = b.room.id,
		facing = seatLocal.Position,
	})
end

-- Wellness activity (employees' wellness break, EmployeeConfig): `stand` = building-local floor point,
-- `facing` = look-at point; extra = JobPose / JobItem / UseProp / StandCFrame (world) attributes.
local function wellness(b: B, id: string, stand: Vector3, facing: Vector3, seat: Seat?, extra: { [string]: any }): Model
	return Kit.activity(b.m, b.cf, b.room.id .. "_" .. id, "Wellness", "wellness", "any", CF(stand.X, b.fy + 2.8, stand.Z), b.room.level, b.owner, seat, {
		roomAccess = b.room.access,
		homeRoom = b.room.id,
		facing = V3(facing.X, b.fy + 2.8, facing.Z),
		attributes = extra,
	})
end

-- PropFx root (design/PROPFX_CONTRACT.md).
local function fx(inst: Instance, kinds: string, attrs: { [string]: any }?): Instance
	return Kit.fx(inst, kinds, attrs)
end

-- Wall sconce look: brass back plate + warm diffuser (Neon, no light object).
local function sconce(b: B, wall: CFrame, y: number)
	Kit.part(b.m, b.cf, "SconcePlate", V3(0.5, 1.0, 0.08), wall * CF(0, y, -0.04), C.brass, M.metal, DETAIL)
	Kit.part(b.m, b.cf, "SconceGlow", V3(0.32, 0.72, 0.1), wall * CF(0, y, -0.13), C.lightWarm, M.neon, DETAIL)
end

-- Small round side table (detail top + post).
local function sideTable(b: B, x: number, z: number, y: number)
	Kit.cylinder(b.m, b.cf, "SideTableTop", "y", 0.12, 1.3, CF(x, y + 1.6, z), C.oakDark, M.wood, DETAIL)
	Kit.cylinder(b.m, b.cf, "SideTablePost", "y", 1.55, 0.25, CF(x, y + 0.78, z), C.metal, M.metal, DETAIL)
end

-- Raised planter with ornamental grass clumps (box, soil, tufts). `at` centre, length along local X.
local function grassPlanter(b: B, base: CFrame, w: number, d: number, seed: number, h: number?)
	local H = h or 1.8
	local box = Kit.pick({ C.stoneDeep, C.oakDark, C.concrete }, seed)
	Kit.part(b.m, b.cf, "PlanterBox", V3(w, H, d), base * CF(0, H / 2, 0), box, if box == C.oakDark then M.wood else M.stone)
	Kit.part(b.m, b.cf, "Soil", V3(w - 0.4, 0.1, d - 0.4), base * CF(0, H + 0.05, 0), C.soil, M.grass, DETAIL)
	local n = math.clamp(math.floor(w / 2.2), 2, 6)
	for i = 1, n do
		local x = -w / 2 + (i - 0.5) * w / n + Kit.range(seed, i, -0.3, 0.3)
		local th = Kit.range(seed, i + 10, 1.6, 2.6)
		local dia = Kit.range(seed, i + 20, 0.9, math.min(1.6, d - 0.5))
		Kit.cylinder(b.m, b.cf, "Grass", "y", th, dia, base * CF(x, H + th / 2, Kit.range(seed, i + 30, -0.2, 0.2)), if i % 2 == 0 then C.foliageLight else C.sageLight, M.leafy, DETAIL)
	end
end

-- Building-local AABB of a door leaf over its closed and open pivot (to keep furniture clear of a
-- sliding bookcase). Returns nil when the door is not built yet.
local function leafBounds(ctx: any, doorId: string): (Vector3?, Vector3?)
	local door = ctx.folders.Doors:FindFirstChild("Door_" .. doorId)
	local leaf = if door then door:FindFirstChild("Leaf1") else nil
	if not leaf or not leaf:IsA("Model") then
		return nil, nil
	end
	local closed, open = leaf:GetAttribute("ClosedPivot"), leaf:GetAttribute("OpenPivot")
	if typeof(closed) ~= "CFrame" or typeof(open) ~= "CFrame" then
		return nil, nil
	end
	local delta = open * closed:Inverse()
	local lo, hi = V3(math.huge, math.huge, math.huge), V3(-math.huge, -math.huge, -math.huge)
	for _, p in leaf:GetDescendants() do
		if p:IsA("BasePart") then
			for _, world in { p.CFrame, delta * p.CFrame } do
				local l = ctx.cf:ToObjectSpace(world)
				local s = p.Size / 2
				for _, k in { V3(1, 1, 1), V3(1, 1, -1), V3(1, -1, 1), V3(1, -1, -1), V3(-1, 1, 1), V3(-1, 1, -1), V3(-1, -1, 1), V3(-1, -1, -1) } do
					local c = l:PointToWorldSpace(s * k)
					lo, hi = lo:Min(c), hi:Max(c)
				end
			end
		end
	end
	return lo, hi
end

---------------------------------------------------------------------------------------------
-- Level 0 · wellness pavilion
---------------------------------------------------------------------------------------------
local function waterDispenser(b: B, wall: CFrame)
	local unit = Kit.part(b.m, b.cf, "WaterDispenser", V3(1.4, 3.6, 1.2), wall * CF(0, 1.8, -0.62), C.white, M.smooth)
	local stream = Kit.part(unit, b.cf, "DispenserStream", V3(0.1, 0.65, 0.1), wall * CF(0, 2.4, -1.28), C.water, M.glass, WATER)
	stream:SetAttribute("FxShow", 0.35)
	fx(unit, "flow", { FxSeconds = 3, PropId = "WellnessWater" })
	Kit.action(unit, "prop", "Water point", "WellnessWater", { actionText = "Drink", maxDistance = 6 })
	Kit.cylinder(b.m, b.cf, "WaterBottle", "y", 1.5, 1.0, wall * CF(0, 4.35, -0.6), C.water, M.glass, { detail = true, transparency = 0.35 })
	Kit.part(b.m, b.cf, "DispenserTap", V3(0.5, 0.3, 0.2), wall * CF(0, 2.8, -1.25), C.metalSoft, M.metal, DETAIL)
	Kit.part(b.m, b.cf, "DripTray", V3(0.9, 0.1, 0.5), wall * CF(0, 2.0, -1.3), C.metal, M.metal, DETAIL)
	Kit.part(b.m, b.cf, "CupHolder", V3(0.35, 1.2, 0.35), wall * CF(1.0, 4.0, -0.11), C.metalSoft, M.metal, DETAIL)
end

local function corridorWellness(b: B)
	local s = b.seed
	local S = 80.5 -- link wall surface (z = 80, 1.0 thick); floor-standing units stand 0.07 off (skirting)
	local N = 93.5 -- solid room walls on z = 94 (restrooms, showers)
	-- benches with art above, plants, a water point and the timetable board along the link wall
	for i, x in { -74, -18, 20, 63 } do
		Kit.bench(b.m, b.cf, at(b, x, S + 1.0, "N"), 6, s + i)
		Kit.artwork(b.m, b.cf, at(b, x, S, "N"), 5, 3.2, s + i * 7, { y = 6.8 })
	end
	local xs, sizes = { -80, -66, -53, -38, -4, 36, 53, 79.5 }, { "l", "m", "s", "m", "l", "m", "s", "l" }
	for i, x in xs do
		Kit.plant(b.m, b.cf, CF(x, b.fy, S + 1.95), sizes[i], s + i * 3)
	end
	waterDispenser(b, at(b, -58.5, S + 0.07, "N"))
	local board = Kit.part(b.m, b.cf, "WellnessTimetable", V3(6, 4.4, 0.15), at(b, -30, S, "N") * CF(0, 5.6, -0.08), C.sage, M.smooth)
	Kit.part(b.m, b.cf, "TimetableFrame", V3(6.3, 4.7, 0.08), at(b, -30, S, "N") * CF(0, 5.6, -0.02), C.oakDark, M.wood, DETAIL)
	Kit.text(board, "WELLNESS TIMETABLE\n07:30  Morning mobility · studio\n12:30  Lunchtime spin · 18 min\n17:30  Stretch & breathe\nSauna  daily from 16:00 · recovery lounge open all day", {
		color = C.white,
		align = "left",
		valign = "top",
		size = 15,
		font = Enum.Font.BuilderSans,
		light = 0.4,
	})
	-- art on the solid restroom / shower walls (glass walls stay clear)
	Kit.artwork(b.m, b.cf, at(b, -0.5, N, "S"), 4, 3, s + 31)
	Kit.artwork(b.m, b.cf, at(b, 31, N, "S"), 5, 3.4, s + 37)
	Kit.artwork(b.m, b.cf, at(b, 51, N, "S"), 4, 3, s + 41)
end

-- Treadmill: runner faces local -Z (console end); the belt stripes (PropFx belt, client-side) slide
-- along local Z while a player's session runs (FacilityService) or an employee runs (Wellness station).
local function treadmill(b: B, base: CFrame, i: number)
	local m, cf = b.m, b.cf
	Kit.part(m, cf, "TreadmillDeck", V3(3.4, 0.5, 7.0), base * CF(0, 0.25, 0.6), C.metal, M.metal)
	Kit.part(m, cf, "TreadmillHood", V3(3.4, 0.8, 1.2), base * CF(0, 0.4, -3.5), C.metalSoft, M.metal)
	Kit.part(m, cf, "TreadmillBelt", V3(2.6, 0.08, 6.6), base * CF(0, 0.54, 0.6), C.fabricCharcoal, M.rubber)
	local station = wellness(b, "Treadmill" .. i, (base * CF(0, 0, 5.6)).Position, (base * CF(0, 0, -3)).Position, nil, {
		JobPose = "run",
		StandCFrame = cf * base * CF(0, 0.58 + 2.8, 0.9),
	})
	local belt = Kit.propModel(m, cf, "TreadmillBeltStripes", base * CF(0, 0.595, 0.6))
	for k, dz in { -2.4, -0.8, 0.8, 2.4 } do
		local stripe = Kit.part(belt, cf, "BeltStripe", V3(2.4, 0.05, 0.15), base * CF(0, 0.595, 0.6 + dz), C.metalSoft, M.smooth, DETAIL)
		stripe:SetAttribute("BeltHome", stripe.CFrame)
		stripe:SetAttribute("BeltMachine", i)
		stripe:SetAttribute("StripeIndex", k)
	end
	-- the stripes run towards the runner's back (+Z) and wrap every 1.6 studs
	fx(belt, "belt", { FxAxis = "z", FxRate = 3, FxTravel = 1.6, FxStation = station.Name, Machine = i })
	for _, x in { -1.55, 1.55 } do
		Kit.part(m, cf, "TreadmillUpright", V3(0.25, 4.1, 0.25), base * CF(x, 2.85, -3.3), C.metal, M.metal)
		Kit.part(m, cf, "TreadmillRail", V3(0.18, 0.18, 2.4), base * CF(x, 4.0, -2.1), C.metalSoft, M.metal, DETAIL)
	end
	local control = Kit.part(m, cf, "TreadmillControl", V3(2.8, 1.1, 0.35), base * CF(0, 4.95, -3.35) * ANG(RAD(-25), 0, 0), C.screen, M.smooth)
	label(control, "READY · 18 SEC", C.statusGood, 16, Enum.NormalId.Back)
	Kit.action(control, "workout", "Treadmill · start session", i, { actionText = "Use", maxDistance = 8 })
end

-- Exercise bike: rider faces local -Z; the flywheel spins about its own axle (local X).
local function exerciseBike(b: B, base: CFrame, machine: number)
	local m, cf = b.m, b.cf
	Kit.part(m, cf, "BikeFrame", V3(0.5, 0.35, 4.6), base * CF(0, 0.175, 0), C.metal, M.metal)
	for _, z in { -2.1, 2.1 } do
		Kit.part(m, cf, "BikeFoot", V3(2.2, 0.3, 0.5), base * CF(0, 0.15, z), C.metal, M.metal)
	end
	local fly = Kit.cylinder(m, cf, "BikeFlywheel", "x", 0.45, 1.8, base * CF(0, 1.25, -1.0), C.metalSoft, M.metal, { canCollide = false })
	fly:SetAttribute("SpinBase", fly.CFrame)
	fly:SetAttribute("BikeMachine", machine)
	Kit.part(m, cf, "BikeStem", V3(0.3, 3.6, 0.3), base * CF(0, 2.3, -2.12), C.metal, M.metal)
	local bars = Kit.part(m, cf, "BikeHandlebars", V3(2.2, 0.22, 0.5), base * CF(0, 4.2, -2.0), C.metal, M.metal)
	Kit.action(bars, "workout", "Exercise bike · start session", machine, { actionText = "Use", maxDistance = 8 })
	Kit.part(m, cf, "BikeConsole", V3(0.9, 0.6, 0.12), base * CF(0, 4.65, -2.05) * ANG(RAD(-20), 0, 0), C.screen, M.smooth, DETAIL)
	Kit.part(m, cf, "BikeSeatPost", V3(0.3, 2.2, 0.3), base * CF(0, 1.45, 1.0), C.metal, M.metal)
	local seat = Kit.seat(m, cf, "BikeSeat", V3(1.4, 0.35, 1.6), base * CF(0, 2.72, 1.0), C.fabricCharcoal, M.fabric)
	local station = wellness(b, "Bike" .. machine, (base * CF(0, 0, 4.0)).Position, (base * CF(0, 0, -3)).Position, seat, { JobPose = "cycle" })
	fx(fly, "spin", { FxAxis = "x", FxRate = 9, FxStation = station.Name, Machine = machine })
end

-- Rowing machine: rower faces local -Z (flywheel end). The fan wheel spins (PropFx) while rowing; the
-- seat never moves (seated characters are welded to it).
local function rower(b: B, base: CFrame, seed: number, machine: number)
	local m, cf = b.m, b.cf
	Kit.part(m, cf, "RowerRail", V3(0.5, 0.35, 7.0), base * CF(0, 0.55, 0.6), C.metalSoft, M.metal)
	Kit.part(m, cf, "RowerHousing", V3(1.4, 1.8, 0.15), base * CF(0, 0.95, -3.75), C.metal, M.metal)
	local fan = Kit.cylinder(m, cf, "RowerFlywheel", "x", 1.0, 1.6, base * CF(0, 0.95, -2.8), C.metal, M.metal, { canCollide = false })
	for _, z in { -2.9, 3.8 } do
		Kit.part(m, cf, "RowerFoot", V3(1.8, 0.35, 0.4), base * CF(0, 0.175, z), C.metal, M.metal)
	end
	Kit.part(m, cf, "RowerFootrest", V3(1.6, 0.15, 0.8), base * CF(0, 0.8, -1.7) * ANG(RAD(-30), 0, 0), C.fabricCharcoal, M.rubber, DETAIL)
	Kit.part(m, cf, "RowerHandle", V3(1.6, 0.12, 0.12), base * CF(0, 1.4, -2.15), C.metal, M.metal, DETAIL)
	Kit.part(m, cf, "RowerMonitorArm", V3(0.15, 0.7, 0.15), base * CF(0, 2.1, -2.9), C.metal, M.metal, DETAIL)
	local monitor = Kit.part(m, cf, "RowerMonitor", V3(0.8, 0.6, 0.1), base * CF(0, 2.6, -2.9) * ANG(RAD(-20), 0, 0), C.screen, M.smooth, DETAIL)
	local seat = Kit.seat(m, cf, "RowerSeat", V3(1.2, 0.3, 1.2), base * CF(0, 0.92, 1.2), Kit.pick({ C.fabricCharcoal, C.fabricBlue }, seed), M.fabric)
	local station = wellness(b, "Rower" .. machine, (base * CF(0, 0, 5.6)).Position, (base * CF(0, 0, -3)).Position, seat, { JobPose = "row" })
	fx(fan, "spin", { FxAxis = "x", FxRate = 7, FxStation = station.Name, Machine = machine })
	Kit.action(monitor, "workout", "Rowing machine · start session", machine, { actionText = "Use", maxDistance = 8 })
end

BUILD.gym = function(b: B)
	local s = b.seed
	local E = -36.5 -- east wall surface (solid, shared with recovery and sauna)
	-- cardio row facing the west glazing: three treadmills, two bikes
	for i, z in { 106, 112, 118 } do
		treadmill(b, at(b, -74.5, z, "W"), i)
	end
	for i, z in { 126, 131 } do
		exerciseBike(b, at(b, -75.5, z, "W"), 3 + i)
	end
	for i, z in { 137, 141.5 } do
		rower(b, at(b, -75, z, "W"), s + i, 5 + i)
	end
	-- functional zone: squat rack on a timber platform, plyo boxes, medicine balls
	Kit.part(b.m, b.cf, "LiftPlatform", V3(8, 0.1, 8), CF(-56, b.fy + 0.05, 113), C.oakDark, M.planks, DETAIL)
	for _, p in { V3(-2.0, 0, -2.2), V3(2.0, 0, -2.2), V3(-2.0, 0, 2.2), V3(2.0, 0, 2.2) } do
		Kit.part(b.m, b.cf, "RackPost", V3(0.3, 7.5, 0.3), CF(-56 + p.X, b.fy + 3.75, 113 + p.Z), C.metal, M.metal)
	end
	for _, x in { -2.0, 2.0 } do
		Kit.part(b.m, b.cf, "RackBeam", V3(0.3, 0.3, 4.7), CF(-56 + x, b.fy + 7.35, 113), C.metal, M.metal)
		Kit.part(b.m, b.cf, "SafetyBar", V3(0.2, 0.2, 4.4), CF(-56 + x, b.fy + 2.6, 113), C.metalSoft, M.metal, DETAIL)
	end
	Kit.cylinder(b.m, b.cf, "Barbell", "x", 7.2, 0.2, CF(-56, b.fy + 4.8, 110.95), C.metalSoft, M.metal, DETAIL)
	for _, x in { -2.9, 2.9 } do
		Kit.cylinder(b.m, b.cf, "BarbellPlate", "x", 0.35, 1.7, CF(-56 + x, b.fy + 4.8, 110.95), C.fabricCharcoal, M.rubber, DETAIL)
	end
	for i, h in { 1.5, 2.0, 2.5 } do
		Kit.part(b.m, b.cf, "PlyoBox", V3(2.4, h, 2.0), CF(-60 + (i - 1) * 3.5, b.fy + h / 2, 131), C.oakLight, M.wood)
	end
	for k = 1, 3 do
		Kit.ball(b.m, b.cf, "MedicineBall", 1.0, CF(-50.2 + (k - 1) * 1.2, b.fy + 0.5, 131.4), Kit.pick({ C.terracotta, C.fabricBlue, C.sage }, s + k), M.rubber, DETAIL)
	end
	-- free weights in front of a satin metal mirror wall
	local wall = at(b, E, 125, "W")
	Kit.part(b.m, b.cf, "MirrorWall", V3(26, 7.84, 0.1), wall * CF(0, 4.53, -0.05), C.glass, M.metal)
	for _, y in { 0.53, 8.53 } do
		Kit.part(b.m, b.cf, "MirrorTrim", V3(26.2, 0.16, 0.14), wall * CF(0, y, -0.07), C.metal, M.metal, DETAIL)
	end
	local board = Kit.part(b.m, b.cf, "GymBoard", V3(18, 2.8, 0.15), wall * CF(0, 10.7, -0.08), C.sage, M.smooth)
	label(board, "MOVE · RESET · BUILD — 18 seconds of exercise", C.white, nil)
	-- dumbbell rack: two tiers, the upper one set back
	local rack = at(b, E - 1.3, 125, "W")
	for _, x in { -6.85, 6.85 } do
		Kit.part(b.m, b.cf, "RackEnd", V3(0.3, 3.0, 2.2), rack * CF(x, 1.5, 0), C.metal, M.metal)
	end
	local tier = Kit.part(b.m, b.cf, "RackTier", V3(13.4, 0.15, 1.0), rack * CF(0, 1.4, -0.5), C.metalSoft, M.metal)
	Kit.part(b.m, b.cf, "RackTier", V3(13.4, 0.15, 1.0), rack * CF(0, 2.6, 0.5), C.metalSoft, M.metal)
	for k = 1, 6 do
		local x = -6.6 + (k - 0.5) * 2.2
		Kit.cylinder(b.m, b.cf, "Dumbbell", "z", 1.0, 0.42 + k * 0.04, rack * CF(x, 1.72 + k * 0.02, -0.5), C.metal, M.metal, DETAIL)
		Kit.cylinder(b.m, b.cf, "Dumbbell", "z", 1.0, 0.36 + k * 0.03, rack * CF(x, 2.9 + k * 0.015, 0.5), C.fabricCharcoal, M.rubber, DETAIL)
	end
	for k = 1, 3 do
		Kit.ball(b.m, b.cf, "Kettlebell", 0.8 + k * 0.12, rack * CF(-4 + k * 2.2, 0.4 + k * 0.06, -2.2), C.metal, M.metal, DETAIL)
	end
	-- free weights: players start a set at the rack (machine 8), employees lift on a wellness break
	Kit.action(tier, "workout", "Free weights · start set", 8, { actionText = "Lift", maxDistance = 8 })
	wellness(b, "Weights", V3(-41.2, 0, 121), V3(-36.5, 0, 121), nil, { JobPose = "lift", JobItem = "dumbbell" })
	Kit.part(b.m, b.cf, "WeightsMat", V3(12, 0.05, 28), CF(-43.5, b.fy + 0.025, 125), C.fabricCharcoal, M.rubber, DETAIL)
	Kit.part(b.m, b.cf, "WeightBenchPad", V3(4.4, 0.4, 1.4), CF(-45.5, b.fy + 1.5, 125), C.fabricCharcoal, M.leather)
	for _, x in { -47.2, -43.8 } do
		Kit.part(b.m, b.cf, "WeightBenchLeg", V3(0.3, 1.3, 1.2), CF(x, b.fy + 0.65, 125), C.metal, M.metal)
	end
	-- stretching mats facing the garden glazing, foam rollers
	for i, x in { -64, -58.5, -53, -47.5 } do
		Kit.part(b.m, b.cf, "ExerciseMat", V3(2.4, 0.06, 6), CF(x, b.fy + 0.03, 151), Kit.pick({ C.sage, C.fabricBlue, C.fabricCharcoal, C.sageLight }, s + i), M.rubber, DETAIL)
		if i % 2 == 1 then
			Kit.cylinder(b.m, b.cf, "FoamRoller", "x", 2.0, 0.6, CF(x, b.fy + 0.3, 154.6), C.fabricBlue, M.rubber, DETAIL)
		end
	end
	-- towel station by the entrance, plants
	Kit.sideboard(b.m, b.cf, at(b, -44, 94.2, "N"), 6, s)
	for k = 1, 3 do
		Kit.cylinder(b.m, b.cf, "RolledTowel", "z", 1.3, 0.55, at(b, -44, 94.2, "N") * CF(-1.0 + k * 0.6 - 0.6, 3.1, -0.8), C.white, M.fabric, DETAIL)
	end
	Kit.plant(b.m, b.cf, CF(-79.3, b.fy, 157.4), "l", s + 3)
	Kit.plant(b.m, b.cf, CF(-38.6, b.fy, 157.4), "l", s + 5)
	Kit.plant(b.m, b.cf, CF(-38.7, b.fy, 97), "m", s + 7)
end

-- Chaise lounger: sitter faces local -Z (foot end), reclined backrest at +Z.
local function chaise(b: B, base: CFrame, seed: number): Seat
	local cover = Kit.pick({ C.fabricSand, C.sageLight, C.white, C.fabric }, seed)
	Kit.part(b.m, b.cf, "LoungerBase", V3(2.4, 0.8, 5.6), base * CF(0, 0.6, 0), cover, M.fabric)
	Kit.part(b.m, b.cf, "LoungerRunner", V3(2.2, 0.2, 5.2), base * CF(0, 0.1, 0), C.oakDark, M.wood, DETAIL)
	local seat = Kit.seat(b.m, b.cf, "Seat", V3(2.2, 0.35, 3.4), base * CF(0, 1.17, -0.9), cover, M.fabric)
	Kit.part(b.m, b.cf, "LoungerBack", V3(2.2, 0.4, 2.6), base * CF(0, 1.85, 1.65) * ANG(RAD(-35), 0, 0), cover, M.fabric)
	Kit.part(b.m, b.cf, "LoungerPillow", V3(1.6, 0.35, 0.8), base * CF(0, 2.55, 2.0) * ANG(RAD(-35), 0, 0), C.white, M.fabric, DETAIL)
	return seat
end

BUILD.recovery = function(b: B)
	local s = b.seed
	-- west: sofa group around a low table
	local sofa = Kit.sofa(b.m, b.cf, at(b, -33.93, 106, "E"), 8, s, { color = C.sage })
	Kit.coffeeTable(b.m, b.cf, at(b, -29.6, 106, "E"), s + 1, 4, 2.2)
	Kit.loungeChair(b.m, b.cf, Kit.facing(V3(-27.2, b.fy, 110.6), V3(-30, b.fy, 106)), s + 2, { color = C.fabricSand })
	Kit.part(b.m, b.cf, "Magazines", V3(1.2, 0.12, 1.5), CF(-29.6, b.fy + 1.46, 105.2) * ANG(0, 0.3, 0), C.white, M.smooth, DETAIL)
	Kit.floorLamp(b.m, b.cf, at(b, -34.4, 112.8, "S"), s + 4, { light = true, mood = "warm" })
	Kit.rug(b.m, b.cf, CF(-30.5, b.fy, 106), 9, 11, s + 5)
	-- calm wall feature: stone panel with a water sheet into a stone trough
	local fw = at(b, -30, 127.5, "S")
	Kit.part(b.m, b.cf, "WaterWallStone", V3(8.5, 8.95, 0.35), fw * CF(0, 4.925, -0.175), C.stoneDeep, M.stone)
	local sheet = Kit.part(b.m, b.cf, "WaterSheet", V3(7.6, 7.6, 0.05), fw * CF(0, 5.2, -0.4), C.water, M.glass, { detail = true, transparency = 0.45 })
	sheet:SetAttribute("FxShow", 0.45)
	fx(sheet, "flow", { FxIdle = "on", FxRate = 0.6 })
	Kit.part(b.m, b.cf, "WaterSpout", V3(7.8, 0.2, 0.3), fw * CF(0, 9.05, -0.45), C.brass, M.metal, DETAIL)
	Kit.part(b.m, b.cf, "WaterTrough", V3(8.5, 0.9, 1.3), fw * CF(0, 0.45, -0.72), C.stone, M.stone)
	Kit.part(b.m, b.cf, "TroughWater", V3(8.1, 0.05, 1.0), fw * CF(0, 0.9, -0.72), C.water, M.glass, { detail = true, transparency = 0.3 })
	-- two recliners facing the water wall
	local recliners = {
		Kit.loungeChair(b.m, b.cf, at(b, -32, 120.5, "N"), s + 6, { color = C.fabricSand }),
		Kit.loungeChair(b.m, b.cf, at(b, -27.6, 120.5, "N"), s + 7, { color = C.fabricSand }),
	}
	sideTable(b, -29.8, 120.8, b.fy)
	-- east: three chaise loungers along the wall, side tables, plants, soft lamp
	local loungers: { Seat } = {}
	for i, z in { 100.5, 107, 113.5 } do
		table.insert(loungers, chaise(b, at(b, -10.4, z, "W"), s + 10 + i))
	end
	sideTable(b, -8.6, 103.75, b.fy)
	sideTable(b, -8.6, 110.25, b.fy)
	Kit.floorLamp(b.m, b.cf, at(b, -8.2, 118.6, "W"), s + 8)
	Kit.plant(b.m, b.cf, CF(-9, b.fy, 124.6), "l", s + 9)
	Kit.plant(b.m, b.cf, CF(-16.4, b.fy, 125.8), "m", s + 11)
	Kit.plant(b.m, b.cf, CF(-34.4, b.fy, 96.4), "m", s + 12)
	-- staff break points (aisle x -24..-18 to the sauna door stays free)
	lounge(b, recliners[2], 1, "lounge", V3(-24.6, 0, 120.5))
	lounge(b, sofa[1], 2, "lounge", V3(-30.9, 0, 101.9))
	lounge(b, loungers[1], 3, "lounge", V3(-15.0, 0, 100.5))
	lounge(b, loungers[3], 4, "lounge", V3(-15.0, 0, 113.5))
end

BUILD.sauna = function(b: B)
	local s = b.seed
	local cedar, cedarDark = C.oakLight, C.oak
	-- cedar cladding inside (west, east, north liner in front of the facade, south around the door)
	local Y = 12.8
	Kit.part(b.m, b.cf, "CedarCladding", V3(0.15, Y, 30.1), CF(-35.365, b.fy + Y / 2, 143.6), cedar, M.planks)
	Kit.part(b.m, b.cf, "CedarCladding", V3(0.15, Y, 30.1), CF(-6.635, b.fy + Y / 2, 143.6), cedar, M.planks)
	Kit.part(b.m, b.cf, "CedarCladding", V3(28.7, Y, 0.15), CF(-21, b.fy + Y / 2, 158.68), cedar, M.planks)
	Kit.part(b.m, b.cf, "CedarCladding", V3(11.9, Y, 0.15), CF(-29.45, b.fy + Y / 2, 128.635), cedar, M.planks)
	Kit.part(b.m, b.cf, "CedarCladding", V3(11.9, Y, 0.15), CF(-12.55, b.fy + Y / 2, 128.635), cedar, M.planks)
	-- two-tier bench along the north liner, single tier along both side walls
	-- (tiers 1.5 apart: the lower bench is the step up to the upper one; sitters face the stove)
	Kit.part(b.m, b.cf, "BenchUpperBody", V3(27, 2.8, 2.4), CF(-21, b.fy + 1.4, 157.3), cedarDark, M.wood)
	Kit.part(b.m, b.cf, "BenchLowerBody", V3(27, 1.3, 2.2), CF(-21, b.fy + 0.65, 155.0), cedarDark, M.wood)
	local lower: { [number]: Seat } = {}
	for k = 1, 7 do
		local x = -34.5 + (k - 0.5) * 27 / 7
		Kit.seat(b.m, b.cf, "SaunaBench", V3(27 / 7 - 0.06, 0.2, 2.4), CF(x, b.fy + 2.9, 157.3), cedar, M.planks)
		lower[k] = Kit.seat(b.m, b.cf, "SaunaBench", V3(27 / 7 - 0.06, 0.2, 2.2), CF(x, b.fy + 1.4, 155.0), cedar, M.planks)
	end
	-- three lower bench places for employees on a wellness break (the stove steams while they relax)
	for _, k in { 2, 4, 6 } do
		local x = -34.5 + (k - 0.5) * 27 / 7
		wellness(b, "Sauna" .. k, V3(x, 0, 152.6), V3(x, 0, 150), lower[k], { JobPose = "relax", UseProp = "SaunaHeater" })
	end
	for _, side in { -1, 1 } do
		local x = -21 + side * 13.19
		Kit.part(b.m, b.cf, "BenchSideBody", V3(2.2, 1.3, 17.8), CF(x, b.fy + 0.65, 145.0), cedarDark, M.wood)
		for k = 1, 5 do
			local z = 136.1 + (k - 0.5) * 17.8 / 5
			Kit.seat(b.m, b.cf, "SaunaBench", V3(17.8 / 5 - 0.06, 0.2, 2.2), CF(x, b.fy + 1.4, z) * ANG(0, side * PI / 2, 0), cedar, M.planks)
		end
	end
	-- central stove on a stone plinth inside a cedar guard rail
	Kit.part(b.m, b.cf, "StovePlinth", V3(4.4, 0.4, 4.4), CF(-21, b.fy + 0.2, 142.5), C.stoneDeep, M.stone)
	local heater = Kit.part(b.m, b.cf, "SaunaHeater", V3(3, 3.2, 3), CF(-21, b.fy + 2.0, 142.5), C.metal, M.metal)
	fx(heater, "steam", { FxSeconds = 20, PropId = "SaunaHeater" })
	for k = 1, 8 do
		local a = k * 2 * PI / 8
		Kit.ball(b.m, b.cf, "SaunaStone", Kit.range(s, k, 0.7, 1.0), CF(-21 + math.cos(a) * 0.8, b.fy + 3.75, 142.5 + math.sin(a) * 0.8), C.stoneDeep, M.slate, DETAIL)
	end
	local steam = Instance.new("ParticleEmitter")
	steam.Name = "Steam"
	steam.Enabled = false
	steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	steam.Color = ColorSequence.new(C.white)
	steam.Size = NumberSequence.new(2.5)
	steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.65), NumberSequenceKeypoint.new(1, 1) })
	steam.Rate = 7
	steam.Lifetime = NumberRange.new(1.5, 3)
	steam.Speed = NumberRange.new(1, 2)
	steam.Parent = heater
	Kit.action(heater, "sauna", "Sauna · add steam and relax", nil, { actionText = "Use", maxDistance = 8 })
	for _, p in { { -24, 139.5 }, { -18, 139.5 }, { -24, 145.5 }, { -18, 145.5 } } do
		Kit.part(b.m, b.cf, "GuardPost", V3(0.3, 3.0, 0.3), CF(p[1], b.fy + 1.5, p[2]), cedarDark, M.wood)
	end
	for _, r in { { -21, 139.5, 6, 0.2 }, { -21, 145.5, 6, 0.2 }, { -24, 142.5, 0.2, 6 }, { -18, 142.5, 0.2, 6 } } do
		Kit.part(b.m, b.cf, "GuardRail", V3(r[3], 0.25, r[4]), CF(r[1], b.fy + 2.6, r[2]), cedar, M.wood)
	end
	-- bucket and ladle, towel shelf by the door, hourglass on the east wall
	Kit.cylinder(b.m, b.cf, "SaunaBucket", "y", 0.8, 0.9, CF(-17.2, b.fy + 0.4, 139.2), cedarDark, M.wood, DETAIL)
	Kit.part(b.m, b.cf, "Ladle", V3(0.1, 0.1, 1.6), CF(-17.2, b.fy + 0.9, 139.6) * ANG(RAD(-30), 0, 0), cedar, M.wood, DETAIL)
	local shelf = at(b, -29.5, 128.71, "N")
	Kit.part(b.m, b.cf, "TowelShelf", V3(6, 0.15, 1.3), shelf * CF(0, 5.0, -0.65), cedarDark, M.wood)
	for k = 1, 4 do
		Kit.cylinder(b.m, b.cf, "SaunaTowel", "z", 1.1, 0.6, shelf * CF(-2.25 + (k - 1) * 1.5, 5.38, -0.65), C.white, M.fabric, DETAIL)
	end
	Kit.part(b.m, b.cf, "Hourglass", V3(0.4, 1.0, 0.3), CF(-6.75, b.fy + 5.2, 136), cedarDark, M.wood, DETAIL)
end

-- WC: tiled pre-wall at local +Z side is the caller's; toilet faces local -Z of `base`.
local function toilet(b: B, base: CFrame, key: string)
	local m, cf = b.m, b.cf
	Kit.part(m, cf, "ToiletPedestal", V3(1.2, 1.0, 1.4), base * CF(0, 0.5, 0.35), C.white, M.smooth)
	Kit.part(m, cf, "ToiletBowl", V3(1.6, 0.5, 2.4), base * CF(0, 1.25, 0), C.white, M.smooth)
	local seat = Kit.seat(m, cf, "ToiletSeat", V3(1.5, 0.12, 2.0), base * CF(0, 1.56, 0.05), C.white, M.smooth)
	seat.Disabled = true
	seat:SetAttribute("FixtureKey", key)
	Kit.action(seat, "toilet", "Toilet", nil, { actionText = "Sit", maxDistance = 6 })
	Kit.part(m, cf, "ToiletLid", V3(1.5, 1.8, 0.1), base * CF(0, 2.5, 1.12), C.white, M.smooth, DETAIL)
	local water = Kit.part(m, cf, "ToiletWater", V3(1.0, 0.05, 1.4), base * CF(0, 1.46, -0.1), C.water, M.glass, { detail = true, transparency = 0.45 })
	water:SetAttribute("FixtureKey", key)
	fx(water, "flow", { FxAxis = "y", FxTravel = -0.35, FxRate = 3, FxSeconds = 2 })
	local flush = Kit.part(m, cf, "FlushButton", V3(0.8, 0.5, 0.06), base * CF(0, 3.1, 1.17), C.metalSoft, M.metal)
	flush:SetAttribute("FixtureKey", key)
	Kit.action(flush, "flush", "Toilet", nil, { actionText = "Flush", maxDistance = 6 })
end

BUILD.restrooms = function(b: B)
	local s = b.seed
	local room = b.room
	local laminate = Kit.pick({ C.sageLight, C.white, C.oakLight, C.blueSoft }, Kit.hash(room.id)) -- = cubicle doors
	local lamMat = if laminate == C.oakLight then M.wood else M.smooth
	-- four cubicles against the west wall: tiled pre-wall, partitions, front panels, cubicle doors
	local Z0, W, FX, DW = 118.5, 5.8, 1.5, 3.6 -- first partition, cubicle width, front line x, door width
	Kit.part(b.m, b.cf, "PreWall", V3(1.0, 4.0, 4 * W), CF(-4.93, b.fy + 2.0, Z0 + 2 * W), C.white, M.tile)
	Kit.part(b.m, b.cf, "PreWallShelf", V3(1.1, 0.12, 4 * W), CF(-4.88, b.fy + 4.06, Z0 + 2 * W), C.stone, M.marble, DETAIL)
	for k = 0, 4 do
		Kit.part(b.m, b.cf, "CubiclePartition", V3(7, 6.7, 0.15), CF(-2, b.fy + 3.85, Z0 + k * W), laminate, lamMat)
	end
	local side = (W - DW) / 2 -- front panel beside each door
	local panels = { { Z0, Z0 + side } }
	for k = 1, 3 do
		table.insert(panels, { Z0 + k * W - side, Z0 + k * W + side })
	end
	table.insert(panels, { Z0 + 4 * W - side, Z0 + 4 * W })
	for _, p in panels do
		Kit.part(b.m, b.cf, "CubicleFront", V3(0.15, 6.7, p[2] - p[1]), CF(FX, b.fy + 3.85, (p[1] + p[2]) / 2), laminate, lamMat)
	end
	for k = 1, 4 do
		local c = Z0 + (k - 0.5) * W
		local key = room.id .. "_C" .. k
		toilet(b, at(b, -3.23, c, "E"), key)
		Kit.part(b.m, b.cf, "PaperHolder", V3(0.5, 0.5, 0.3), CF(-1.6, b.fy + 2.4, Z0 + (k - 1) * W + 0.25), C.metalSoft, M.metal, DETAIL)
		local def: any = {
			id = key,
			level = room.level,
			room = room.id,
			kind = "cubicle",
			access = room.access,
			axis = "z",
			x = FX,
			z = c,
			w = DW,
			h = 7.2,
			inward = V3(-1, 0, 0),
			exterior = false,
			hidden = false,
			builder = "interior",
			thickness = 0.15,
			y = b.fy,
		}
		local door = Kit.door(b.ctx.folders.Doors, b.cf, def, b.owner)
		if door then
			door:SetAttribute("FixtureKey", key)
		end
	end
	-- vanity with three basins along the east wall, one long mirror, soap, hand dryers
	local E = 23.5 -- east wall surface (wall-hung fixtures; the towel bin stands clear of the skirting)
	Kit.part(b.m, b.cf, "VanityTop", V3(2.2, 0.25, 15), CF(E - 1.1, b.fy + 3.0, 111.5), C.stone, M.marble)
	Kit.part(b.m, b.cf, "VanityBody", V3(2.0, 1.2, 15), CF(E - 1.0, b.fy + 2.3, 111.5), C.oak, M.wood)
	Kit.part(b.m, b.cf, "WashMirror", V3(0.08, 4.4, 15), CF(E - 0.04, b.fy + 6.4, 111.5), C.glass, M.metal)
	for k, z in { 107, 111.5, 116 } do
		local key = room.id .. "_T" .. k
		Kit.part(b.m, b.cf, "Basin", V3(1.3, 0.2, 1.5), CF(E - 1.3, b.fy + 3.06, z), C.white, M.smooth, DETAIL)
		local tap = Kit.cylinder(b.m, b.cf, "Tap", "y", 0.8, 0.2, CF(E - 0.35, b.fy + 3.5, z), C.metalSoft, M.metal, { canCollide = false, castShadow = false })
		tap:SetAttribute("FixtureKey", key)
		Kit.action(tap, "tap", "Wash basin", nil, { actionText = "Wash hands", maxDistance = 6 })
		Kit.part(b.m, b.cf, "Spout", V3(0.5, 0.1, 0.12), CF(E - 0.6, b.fy + 3.85, z), C.metalSoft, M.metal, DETAIL)
		local water = Kit.part(b.m, b.cf, "TapWater", V3(0.12, 0.6, 0.12), CF(E - 0.8, b.fy + 3.5, z), C.water, M.glass, WATER)
		water:SetAttribute("FixtureKey", key)
		water:SetAttribute("FxShow", 0.5)
		fx(water, "flow", { FxSeconds = 6 })
		Kit.part(b.m, b.cf, "SoapDispenser", V3(0.35, 0.6, 0.35), CF(E - 0.3, b.fy + 3.45, z + 0.95), C.white, M.smooth, DETAIL)
	end
	for _, z in { 101.5, 121.8 } do
		local dryer = Kit.part(b.m, b.cf, "HandDryer", V3(0.9, 1.5, 1.2), CF(E - 0.45, b.fy + 4.6, z), C.white, M.smooth)
		local nozzle = Kit.part(dryer, b.cf, "DryerNozzle", V3(0.5, 0.15, 0.8), CF(E - 0.7, b.fy + 3.8, z), C.metalSoft, M.metal, DETAIL)
		local air = Kit.steamEmitter(nozzle, "WarmAir", 6, 0.2)
		air.EmissionDirection = Enum.NormalId.Bottom
		fx(dryer, "steam", { FxSeconds = 4 })
		Kit.action(dryer, "prop", "Hand dryer", nil, { actionText = "Dry hands", maxDistance = 6 })
	end
	Kit.cylinder(b.m, b.cf, "TowelBin", "y", 2.0, 1.1, CF(E - 0.8, b.fy + 1.0, 124.2), C.metalSoft, M.metal)
	-- the cleaner wipes the vanity here (Clean activity for the support staff)
	Kit.activity(b.m, b.cf, room.id .. "_Clean", "Clean", "operations", "support", CF(E - 4.2, b.fy + 2.8, 111.5), room.level, b.owner, nil, {
		roomAccess = room.access,
		homeRoom = room.id,
		facing = V3(E, b.fy + 2.8, 111.5),
		attributes = { JobPose = "wipe", JobItem = "sponge" },
	})
	-- urinals with privacy screens on the east wall
	for k = 0, 2 do
		local z = 130 + k * 3.2
		Kit.part(b.m, b.cf, "Urinal", V3(1.3, 2.2, 1.2), CF(E - 0.65, b.fy + 2.6, z), C.white, M.smooth)
		Kit.part(b.m, b.cf, "FlushValve", V3(0.15, 0.8, 0.15), CF(E - 0.12, b.fy + 4.3, z), C.metalSoft, M.metal, DETAIL)
	end
	for k = 0, 3 do
		Kit.part(b.m, b.cf, "UrinalScreen", V3(1.7, 3.2, 0.12), CF(E - 0.85, b.fy + 3.1, 128.4 + k * 3.2), laminate, lamMat)
	end
	Kit.cabinet(b.m, b.cf, at(b, -5.43, 151, "E"), 3, 6.5, s)
	Kit.plant(b.m, b.cf, CF(20.6, b.fy, 156.4), "l", s + 1)
	Kit.plant(b.m, b.cf, CF(-3.4, b.fy, 97.2), "m", s + 2)
end

BUILD.showers = function(b: B)
	local s = b.seed
	local room = b.room
	-- tiled wet wall along the north side (also screens the facade), four stalls in front of it
	Kit.part(b.m, b.cf, "WetWall", V3(32.86, 12.9, 1.5), CF(41, b.fy + 6.45, 157.75), C.white, M.tile)
	for k = 0, 4 do
		Kit.part(b.m, b.cf, "ShowerDivider", V3(0.2, 7.7, 5.6), CF(29 + k * 6, b.fy + 4.15, 154.2), C.glass, M.glass, FROSTED)
	end
	for k = 1, 4 do
		local x1 = 29 + (k - 1) * 6
		local sx = x1 + 3
		local key = room.id .. "_S" .. k
		Kit.part(b.m, b.cf, "ShowerScreen", V3(2.6, 7.7, 0.2), CF(x1 + 1.4, b.fy + 4.15, 151.5), C.glass, M.glass, FROSTED)
		Kit.part(b.m, b.cf, "ShowerTray", V3(5.6, 0.06, 5.4), CF(sx, b.fy + 0.03, 154.2), C.metalSoft, M.slate, DETAIL)
		local head = Kit.cylinder(b.m, b.cf, "ShowerHead", "y", 0.15, 1.3, CF(sx, b.fy + 8.2, 155.9), C.metalSoft, M.metal, { canCollide = false, castShadow = false })
		head:SetAttribute("FixtureKey", key)
		Kit.action(head, "shower", "Shower", nil, { actionText = "Start / stop", maxDistance = 10 })
		Kit.part(b.m, b.cf, "ShowerArm", V3(0.15, 0.15, 1.2), CF(sx, b.fy + 8.35, 156.45), C.metalSoft, M.metal, DETAIL)
		Kit.part(b.m, b.cf, "ShowerValve", V3(0.6, 0.6, 0.2), CF(sx + 1.6, b.fy + 4.2, 156.9), C.metalSoft, M.metal, DETAIL)
		local water = Kit.part(b.m, b.cf, "ShowerWater", V3(1.2, 7.8, 1.2), CF(sx, b.fy + 4.2, 155.9), C.water, M.glass, WATER)
		water:SetAttribute("FixtureKey", key)
		water:SetAttribute("FxShow", 0.5)
		-- stalls 1 and 3 double as wellness-break showers for employees (water runs while occupied)
		local station: string? = nil
		if k == 1 or k == 3 then
			station = wellness(b, "Shower" .. k, V3(sx + 0.6, 0, 154.2), V3(sx, 0, 156.9), nil, { JobPose = "shower" }).Name
		end
		fx(water, "flow", { FxSeconds = 15, FxStation = station })
	end
	-- two locker rows with changing benches (players sit by walking into them)
	Kit.lockers(b.m, b.cf, at(b, 24.57, 111.5, "E"), 10, s, { prompt = "Locker" })
	Kit.lockers(b.m, b.cf, at(b, 57.43, 111.5, "W"), 10, s + 1, { prompt = "Locker" })
	Kit.bench(b.m, b.cf, at(b, 29.9, 111.5, "W"), 12, s + 2)
	Kit.bench(b.m, b.cf, at(b, 52.1, 111.5, "E"), 12, s + 3)
	-- mirror counter with stools on the west wall, towel shelving on the east wall
	Kit.part(b.m, b.cf, "MirrorCounterTop", V3(2.0, 0.25, 12), CF(25.5, b.fy + 3.0, 132), C.stone, M.marble)
	Kit.part(b.m, b.cf, "MirrorCounterBody", V3(1.8, 1.0, 12), CF(25.4, b.fy + 2.4, 132), C.oak, M.wood)
	Kit.part(b.m, b.cf, "CounterMirror", V3(0.08, 4.0, 12), CF(24.54, b.fy + 6.2, 132), C.glass, M.metal)
	Kit.part(b.m, b.cf, "HairDryer", V3(0.5, 0.4, 0.9), CF(25.6, b.fy + 3.32, 128.6), C.white, M.smooth, DETAIL)
	for i, z in { 129, 135 } do
		Kit.stool(b.m, b.cf, CF(28.3, b.fy, z), s + i, 2.2)
	end
	Kit.rackShelf(b.m, b.cf, at(b, 57.43, 141, "W"), 4, s + 4)
	for k = 1, 3 do
		Kit.cylinder(b.m, b.cf, "FoldedTowels", "z", 1.2, 0.5, at(b, 57.43, 141, "W") * CF(-1.2 + k * 0.8 - 0.8, 2.89, -0.8), C.white, M.fabric, DETAIL)
	end
	Kit.plant(b.m, b.cf, CF(26.6, b.fy, 97.2), "m", s + 5)
	Kit.plant(b.m, b.cf, CF(55.4, b.fy, 97.2), "m", s + 6)
end

BUILD.garden_lobby = function(b: B)
	local s = b.seed
	local W = 58.5 -- west wall surface; the path x 65..75 between both garden doors stays free
	local rail = at(b, W, 145, "E")
	Kit.part(b.m, b.cf, "CoatRail", V3(10, 0.5, 0.15), rail * CF(0, 6.2, -0.08), C.oak, M.wood)
	for k = 1, 7 do
		Kit.cylinder(b.m, b.cf, "CoatHook", "z", 0.45, 0.14, rail * CF(-4.5 + (k - 1) * 1.5, 6.0, -0.35), C.brass, M.metal, DETAIL)
	end
	for k, x in { -3, 0, 4.5 } do
		Kit.part(b.m, b.cf, "Coat", V3(1.4, 3.0, 0.45), rail * CF(x, 4.45, -0.45), Kit.pick({ C.fabricCharcoal, C.fabricSand, C.fabricBlue, C.sage }, s + k), M.fabric, DETAIL)
	end
	Kit.bench(b.m, b.cf, at(b, W + 0.9, 145, "E"), 9, s)
	Kit.part(b.m, b.cf, "BootTray", V3(1.4, 0.12, 4), CF(W + 0.8, b.fy + 0.06, 152.2), C.metal, M.rubber, DETAIL)
	Kit.cylinder(b.m, b.cf, "UmbrellaStand", "y", 2.0, 1.1, CF(61.4, b.fy + 1.0, 155.6), C.metal, M.metal)
	for k = 1, 2 do
		Kit.cylinder(b.m, b.cf, "Umbrella", "y", 3.0, 0.25, CF(61.4 + (k - 1.5) * 0.35, b.fy + 2.3, 155.6) * ANG(0, 0, (k - 1.5) * 0.2), Kit.pick({ C.fabricBlue, C.fabricCharcoal, C.sage }, s + k), M.fabric, DETAIL)
	end
	Kit.part(b.m, b.cf, "DoorMat", V3(8, 0.05, 3), CF(70, b.fy + 0.025, 157.3), C.fabricCharcoal, M.fabric, DETAIL)
	-- a small waiting spot, art, garden-side planting
	Kit.loungeChair(b.m, b.cf, at(b, 61.2, 112, "E"), s + 2)
	Kit.loungeChair(b.m, b.cf, at(b, 61.2, 119, "E"), s + 3)
	sideTable(b, 60.4, 115.5, b.fy)
	Kit.artwork(b.m, b.cf, at(b, W, 128, "E"), 5, 3.5, s + 4)
	Kit.plant(b.m, b.cf, CF(78.4, b.fy, 108), "tree", s + 5)
	Kit.plant(b.m, b.cf, CF(78.4, b.fy, 136), "tree", s + 6)
	Kit.plant(b.m, b.cf, CF(78.8, b.fy, 122), "l", s + 7)
	Kit.plant(b.m, b.cf, CF(78.8, b.fy, 150), "l", s + 8)
	Kit.plant(b.m, b.cf, CF(60.4, b.fy, 97.2), "m", s + 9)
end

---------------------------------------------------------------------------------------------
-- Level 1 · founder services
---------------------------------------------------------------------------------------------
local function corridorFounder(b: B)
	local s = b.seed
	local S = 80.5 -- plaster link wall: lined with oak panelling like the panel walls opposite
	local N = 93.44 -- panel wall battens on z = 94
	local P = Kit.PANEL_PITCH
	for _, run in { { -81.5, -49.2 }, { -42.8, 42.8 }, { 49.2, 81.5 } } do
		local x1, x2 = run[1], run[2]
		Kit.part(b.m, b.cf, "OakPanelling", V3(x2 - x1, 12.55, 0.08), CF((x1 + x2) / 2, b.y + 0.45 + 12.55 / 2, S + 0.04), C.oakLight, M.wood)
		for k = math.ceil((x1 + 0.3) / P), math.floor((x2 - 0.3) / P) do
			Kit.part(b.m, b.cf, "Batten", V3(0.2, 12.55, 0.06), CF(k * P, b.y + 0.45 + 12.55 / 2, S + 0.11), C.oakDark, M.wood, DETAIL)
		end
	end
	-- soft wall-light look (no light objects); nothing in front of the flush panel x 29..35
	for _, x in { -74, -58, -34, -18, 18, 34, 58, 74 } do
		sconce(b, at(b, x, S + 0.14, "N"), 7.6)
	end
	for _, x in { -74, -50, -34, -6, 14, 50, 63, 77 } do
		sconce(b, at(b, x, N, "S"), 7.6)
	end
	-- console table under art, flanked by sconces
	local ct = at(b, -26, S + 0.14, "N")
	Kit.part(b.m, b.cf, "ConsoleTop", V3(6, 0.2, 1.4), ct * CF(0, 3.0, -0.75), C.oakDark, M.wood)
	Kit.part(b.m, b.cf, "ConsoleShelf", V3(5.6, 0.12, 1.2), ct * CF(0, 0.9, -0.7), C.oakDark, M.wood)
	for _, x in { -2.8, 2.8 } do
		Kit.part(b.m, b.cf, "ConsoleLeg", V3(0.18, 2.9, 1.2), ct * CF(x, 1.45, -0.7), C.brass, M.metal)
	end
	Kit.cylinder(b.m, b.cf, "Vase", "y", 1.4, 0.6, ct * CF(-1.8, 3.8, -0.75), C.terracotta, M.smooth, DETAIL)
	Kit.part(b.m, b.cf, "Books", V3(1.3, 0.4, 0.9), ct * CF(1.4, 3.3, -0.75), C.leather, M.smooth, DETAIL)
	Kit.part(b.m, b.cf, "BoxFile", V3(1.6, 0.9, 1.0), ct * CF(0, 1.41, -0.7), C.fabricSand, M.smooth, DETAIL)
	for i, x in { -26, -66, 26, 66 } do
		Kit.artwork(b.m, b.cf, at(b, x, S + 0.14, "N"), if x == -26 then 4.5 else 5, 3.2, s + i * 11, { y = if x == -26 then 7.4 else 6.8 })
	end
	Kit.artwork(b.m, b.cf, at(b, -30, N, "S"), 4.5, 3.2, s + 71)
	Kit.artwork(b.m, b.cf, at(b, 70, N, "S"), 4, 3, s + 73)
	for i, p in { V3(-79.8, 0, 91.4), V3(79.8, 0, 91.4), V3(21.4, 0, 81.8), V3(30.6, 0, 81.8) } do
		Kit.plant(b.m, b.cf, CF(p.X, b.fy, p.Z), if i <= 2 then "l" else "m", s + i * 5)
	end
end

BUILD.pavilion_corridor = function(b: B)
	if b.room.level == 0 then
		corridorWellness(b)
	else
		corridorFounder(b)
	end
end

local CHANNELS = { "01 · ENTRY", "02 · RECEPTION", "03 · ATRIUM", "04 · CAFÉ", "05 · GARAGE", "06 · DATA HALL", "07 · WORK FLOORS", "08 · PAVILION", "09 · ROOF TERRACE" }

BUILD.security = function(b: B)
	local s = b.seed
	local E = -42.57 -- panel wall shared with the archive (surface -42.5 + battens)
	-- camera wall: 3 x 3 monitors on a steel frame; each opens the live camera views (founder)
	local wall = at(b, E, 127, "W")
	Kit.part(b.m, b.cf, "VideoWallFrame", V3(16.2, 9.4, 0.3), wall * CF(0, 7.9, -0.15), C.metal, M.metal)
	for r = 0, 2 do
		for c = 0, 2 do
			local idx = r * 3 + c + 1
			local mon = Kit.part(b.m, b.cf, "SecurityMonitor", V3(5.0, 2.8, 0.12), wall * CF((c - 1) * 5.15, 7.9 + (1 - r) * 2.95, -0.36), C.screen, M.smooth, { canCollide = false, castShadow = false })
			local t = label(mon, CHANNELS[idx], C.white, 20, nil, "left")
			t.TextYAlignment = Enum.TextYAlignment.Top
			local live = t:Clone()
			live.Name = "Status"
			live.Text = "● LIVE · camera view"
			live.TextColor3 = C.statusGood
			live.TextSize = 14
			live.TextYAlignment = Enum.TextYAlignment.Bottom
			live.Parent = t.Parent
			Kit.action(mon, "security", "Live campus cameras", nil, { ownerOnly = true, actionText = "View", maxDistance = 12 })
		end
	end
	Kit.tvScreen(b.m, b.cf, at(b, E, 109, "W"), 6.4, "security", b.accent, { y = 6.95, name = "SecurityStatus" })
	local map = Kit.part(b.m, b.cf, "CampusLevels", V3(6.4, 5.2, 0.12), at(b, E, 145.5, "W") * CF(0, 6.95, -0.06), C.metal, M.metal)
	local lines = { "CAMPUS LEVELS" }
	for level = Plan.roofLevel(b.ctx.tier), -1, -1 do
		table.insert(lines, Plan.floorTitle(b.ctx.tier, level))
	end
	Kit.text(map, table.concat(lines, "\n"), { color = C.white, align = "left", valign = "top", size = 13, font = Enum.Font.BuilderSans, light = 0.4 })
	-- curved console desk (three segments facing the operator), control surface, monitors, chair
	local chair = V3(-58, b.fy, 127)
	for k, a in { -40, 0, 40 } do
		local p = chair + V3(math.cos(RAD(a)) * 3.9, 0, math.sin(RAD(a)) * 3.9)
		local seg = Kit.facing(p, chair)
		Kit.part(b.m, b.cf, "ConsoleDesk", V3(3.4, 0.2, 2.2), seg * CF(0, 3.05, 0), C.oakDark, M.wood)
		Kit.part(b.m, b.cf, "ConsoleFascia", V3(3.4, 2.95, 0.15), seg * CF(0, 1.475, 1.0), C.metal, M.metal)
		local mon = Kit.part(b.m, b.cf, "ConsoleMonitor", V3(2.6, 1.5, 0.12), seg * CF(0, 3.9, 0.7), C.screen, M.smooth, DETAIL)
		label(mon, if k == 2 then "LIVE VIEW · ALL CHANNELS" else (if k == 1 then "ACCESS LOG" else "FACILITY STATUS"), if k == 2 then b.accent else C.sageLight, 14)
		if k == 2 then
			local console = Kit.part(b.m, b.cf, "SecurityConsole", V3(2.2, 0.12, 0.9), seg * CF(0, 3.22, -0.3) * ANG(RAD(8), 0, 0), C.metalSoft, M.metal)
			label(console, "CAMERA CONTROL", C.white, 12, Enum.NormalId.Top)
			Kit.action(console, "security", "Camera control · all channels", nil, { ownerOnly = true, actionText = "Open", maxDistance = 8 })
		end
	end
	Kit.officeChair(b.m, b.cf, at(b, chair.X, chair.Z, "E"), s, { arms = true, name = "SecuritySeat" })
	-- key cabinet and lockers on the south wall, briefing table by the glazing, plants
	local key = at(b, -52, 94.5, "N")
	Kit.part(b.m, b.cf, "KeyCabinet", V3(2.4, 3.0, 0.5), key * CF(0, 5.5, -0.25), C.metalSoft, M.metal)
	Kit.part(b.m, b.cf, "KeyCabinetGlass", V3(2.2, 2.8, 0.05), key * CF(0, 5.5, -0.53), C.glass, M.glass, { detail = true, transparency = A.glassTransparencyDoor })
	for _, y in { 6.1, 5.0 } do
		Kit.part(b.m, b.cf, "KeyTags", V3(1.8, 0.4, 0.05), key * CF(0, y, -0.5), C.brass, M.metal, DETAIL)
	end
	Kit.lockers(b.m, b.cf, at(b, -75.5, 94.57, "N"), 6, s + 1)
	-- camera recorders (network racks) in the corner, supervisor standing desk behind the console
	for i, x in { -46.4, -48.6 } do
		Kit.serverRack(b.m, b.cf, at(b, x, 96.6, "N"), s + 30 + i, b.m, { variant = "network", index = i, name = "RecorderRack" })
	end
	Kit.desk(b.m, b.cf, at(b, -67, 119, "W"), "standing", s + 7)
	for i, z in { 117.6, 120.4 } do
		local mon = Kit.part(b.m, b.cf, "SupervisorMonitor", V3(2.4, 1.4, 0.12), Kit.place(-66.0, b.fy + 4.87, z, "W"), C.screen, M.smooth, DETAIL)
		label(mon, if i == 1 then "PATROL ROUTES" else "VISITOR LOG", C.sageLight, 13)
	end
	Kit.stool(b.m, b.cf, CF(-69.6, b.fy, 119), s + 8, 3.2)
	local centre = V3(-70, b.fy, 150)
	Kit.meetingTable(b.m, b.cf, CF(centre), "round", 4.5, nil, s + 2)
	for i, a in { 90, 210, 330 } do
		Kit.meetingChair(b.m, b.cf, Kit.facing(centre + V3(math.cos(RAD(a)) * 3.4, 0, -math.sin(RAD(a)) * 3.4), centre), s + 3 + i)
	end
	Kit.plant(b.m, b.cf, CF(-80, b.fy, 157.4), "l", s + 4)
	Kit.plant(b.m, b.cf, CF(-44.4, b.fy, 157.4), "m", s + 5)
	Kit.plant(b.m, b.cf, CF(-44.6, b.fy, 96.6), "m", s + 6)
end

local BOOK_SPINES = { C.leather, C.oakDark, C.sage, C.blue, C.terracotta, C.fabricSand, C.fabricCharcoal, C.white, C.brass, C.fabricBlue, C.sageLight }

-- One 7-wide built-in shelving bay against a wall surface at z = zWall (room on -Z): carcass
-- 0.44 deep in front of the wall battens, five rows like the bookcase door (it stands on the slab,
-- level Y), books 0.28 deep in one or two clusters per row.
local function builtInBay(b: B, x: number, zWall: number, seed: number)
	local base = b.y
	local d = 0.44
	local zc = zWall - 0.06 - d / 2
	local zBook = zWall - 0.06 - 0.04 - 0.14
	local wood = C.oakDark
	for _, sx in { -1, 1 } do
		Kit.part(b.m, b.cf, "BayStile", V3(0.15, 8.55, d), CF(x + sx * 3.425, base + 0.03 + 4.275, zc), wood, M.wood)
	end
	Kit.part(b.m, b.cf, "BayTop", V3(6.7, 0.15, d), CF(x, base + 8.505, zc), wood, M.wood)
	Kit.part(b.m, b.cf, "BayPlinth", V3(6.7, 0.4, d), CF(x, base + 0.23, zc), wood, M.wood)
	Kit.part(b.m, b.cf, "BayBack", V3(6.7, 8.15, 0.05), CF(x, base + 4.43, zWall - 0.085), wood, M.wood, DETAIL)
	for r = 1, 5 do
		local y = base + 0.43 + (r - 1) * 1.62
		if r > 1 then
			Kit.part(b.m, b.cf, "BayShelf", V3(6.7, 0.1, d), CF(x, y - 0.05, zc), wood, M.wood)
		end
		local cursor = x - 3.25 + Kit.range(seed, r, 0.05, 0.9)
		local stop = x + 3.25
		local gapAt = math.floor(Kit.range(seed, r + 10, 3, 6))
		for k = 1, 7 do
			local w = Kit.range(seed, r * 20 + k, 0.35, 0.6)
			if k == gapAt then
				cursor += Kit.range(seed, r * 20 + k + 9, 0.6, 1.4)
			end
			if cursor + w > stop - 0.05 then
				break
			end
			local h = Kit.range(seed, r * 40 + k, 0.85, 1.35)
			Kit.part(b.m, b.cf, "Book", V3(w, h, 0.28), CF(cursor + w / 2, y + h / 2, zBook), Kit.pick(BOOK_SPINES, seed + r * 7 + k), M.smooth, DETAIL)
			cursor += w + 0.02
		end
	end
end

local BINDERS = { C.oakDark, C.blue, C.white, C.fabricSand, C.sage, C.fabricCharcoal, C.leather }

-- Double-sided archive stack (centred, long axis local X), binder groups on four levels.
local function archiveStack(b: B, base: CFrame, L: number, seed: number, tag: string)
	local H, D = 7.6, 2.6
	for _, x in { -1, 1 } do
		Kit.part(b.m, b.cf, "StackEnd", V3(0.2, H, D), base * CF(x * (L / 2 - 0.1), H / 2, 0), C.oakDark, M.wood)
	end
	Kit.part(b.m, b.cf, "StackTop", V3(L, 0.15, D), base * CF(0, H - 0.075, 0), C.oakDark, M.wood)
	Kit.part(b.m, b.cf, "StackPlinth", V3(L - 0.4, 0.3, D - 0.2), base * CF(0, 0.15, 0), C.oakDark, M.wood)
	Kit.part(b.m, b.cf, "StackSpine", V3(L - 0.4, H - 0.45, 0.08), base * CF(0, H / 2, 0), C.oak, M.wood)
	for k = 1, 3 do
		Kit.part(b.m, b.cf, "StackShelf", V3(L - 0.4, 0.08, D), base * CF(0, 0.3 + k * 1.8, 0), C.oak, M.wood)
	end
	for k = 0, 3 do
		local y = 0.34 + k * 1.8
		for _, side in { -1, 1 } do
			local x = -L / 2 + 0.3
			local i = 0
			while i < 3 do
				local n = k * 20 + (side + 1) * 5 + i
				local w = Kit.range(seed, n, 2.0, 3.8)
				if x + w > L / 2 - 0.3 then
					break
				end
				local h = Kit.range(seed, n + 100, 1.25, 1.5)
				Kit.part(b.m, b.cf, "Binders", V3(w, h, 1.05), base * CF(x + w / 2, y + h / 2, side * 0.6), Kit.pick(BINDERS, seed + n * 3), M.smooth, DETAIL)
				x += w + Kit.range(seed, n + 200, 0.2, 1.1)
				i += 1
			end
		end
	end
	local plate = Kit.part(b.m, b.cf, "StackLabel", V3(0.05, 0.8, 1.4), base * CF(L / 2 + 0.025, 5.8, 0), C.brass, M.metal, DETAIL)
	label(plate, tag, C.metal, 14, Enum.NormalId.Right)
end

BUILD.archive = function(b: B)
	local s = b.seed
	local ctx = b.ctx
	-- continuous built-in shelving on the north wall left and right of the bookcase door: same
	-- rows, heights and dark oak as the door's shelving unit, shallow so the bookcase reads as one
	-- more bay; kept in front of the measured leaf (closed and slid open)
	local face = 125.5
	local lo = leafBounds(ctx, "P1_ARCHIVE_D2")
	local zWall = if lo and lo.Z < face - 0.05 then lo.Z - 0.03 else face
	for i, x in { -32, -25, -11, -4 } do
		builtInBay(b, x, zWall, s + i * 23)
	end
	Kit.part(b.m, b.cf, "ShelfCornice", V3(35, 0.42, 0.56), CF(-18, b.y + 8.79, zWall - 0.34), C.oakDark, M.wood)
	-- west: three double-sided stacks off the west wall (aisles 4.4)
	for i, z in { 102.5, 109.5, 116.5 } do
		archiveStack(b, at(b, -34.4, z, "S"), 14, s + i * 17, ({ "A – F", "G – O", "P – Z" })[i])
	end
	-- east: reading table, model history screen, plan chests, printer on a sideboard
	Kit.tvScreen(b.m, b.cf, at(b, 5.43, 110, "W"), 8, "history", b.accent, { y = 6.4, name = "ModelHistory" })
	Kit.meetingTable(b.m, b.cf, at(b, -2.6, 110, "E"), "rect", 8, 4, s + 5)
	Kit.meetingChair(b.m, b.cf, at(b, -6.4, 110, "E"), s + 6, { name = "ArchiveSeat" })
	Kit.part(b.m, b.cf, "OpenBinder", V3(1.8, 0.1, 1.4), CF(-3.4, b.fy + 3.2, 109.4) * ANG(0, 0.2, 0), C.white, M.smooth, DETAIL)
	Kit.part(b.m, b.cf, "BinderStack", V3(1.2, 0.6, 1.0), CF(-1.5, b.fy + 3.45, 113), C.oakDark, M.smooth, DETAIL)
	Kit.cylinder(b.m, b.cf, "LampFoot", "y", 0.1, 0.7, CF(-1.6, b.fy + 3.2, 106.6), C.brass, M.metal, DETAIL)
	Kit.part(b.m, b.cf, "LampArm", V3(0.1, 1.6, 0.1), CF(-1.6, b.fy + 4.0, 106.6), C.brass, M.metal, DETAIL)
	Kit.part(b.m, b.cf, "LampHead", V3(0.9, 0.3, 0.5), CF(-2.0, b.fy + 4.85, 106.6), C.brass, M.metal, DETAIL)
	for k, z in { 117.6, 121.8 } do
		local pc = at(b, 5.43, z, "W")
		Kit.part(b.m, b.cf, "PlanChest", V3(4, 3.0, 2.6), pc * CF(0, 1.5, -1.3), C.oak, M.wood)
		for _, y in { 0.8, 1.6, 2.4 } do
			Kit.part(b.m, b.cf, "DrawerLine", V3(3.8, 0.05, 0.05), pc * CF(0, y, -2.62), C.oakDark, M.smooth, DETAIL)
		end
		if k == 1 then
			Kit.part(b.m, b.cf, "Drawings", V3(2.6, 0.06, 1.8), pc * CF(0.2, 3.03, -1.3), C.white, M.smooth, DETAIL)
		end
	end
	local sb = at(b, 0, 94.57, "N")
	Kit.sideboard(b.m, b.cf, sb, 6, s + 7)
	local printer = Kit.part(b.m, b.cf, "ReportPrinter", V3(2.2, 1.0, 1.6), sb * CF(-1.2, 3.33, -0.85), C.metalSoft, M.metal)
	fx(printer, "paper", { FxSeconds = 3 })
	Kit.part(b.m, b.cf, "PrinterTray", V3(1.6, 0.06, 0.7), sb * CF(-1.2, 3.4, -1.85), C.white, M.smooth, DETAIL)
	Kit.action(printer, "report", "Print company report", nil, { ownerOnly = true, actionText = "Print", maxDistance = 8 })
	Kit.plant(b.m, b.cf, CF(3.5, b.fy, 97.8), "m", s + 8)
	Kit.floorLamp(b.m, b.cf, at(b, -7.6, 114.6, "E"), s + 9)
end

BUILD.secret_passage = function(b: B)
	-- narrow service-like passage behind the shelving wall; the bookcase pocket (x -14.5..-7.5,
	-- south side) stays free, so everything sits on the north wall (surface z = 129.5)
	local N = 129.43 -- north wall surface (z = 130) + battens
	Kit.part(b.m, b.cf, "AccentStrip", V3(15, 0.08, 0.06), CF(-14.5, b.y + 0.52, N - 0.03), C.blue, M.neon, DETAIL)
	Kit.cylinder(b.m, b.cf, "CableConduit", "x", 15, 0.35, CF(-14.5, b.fy + 12.0, N - 0.25), C.metalSoft, M.metal, DETAIL)
	for _, x in { -20, -14.5, -9 } do
		Kit.part(b.m, b.cf, "ConduitClip", V3(0.15, 0.5, 0.3), CF(x, b.fy + 12.0, N - 0.15), C.metal, M.metal, DETAIL)
	end
	Kit.part(b.m, b.cf, "JunctionBox", V3(0.9, 0.9, 0.45), CF(-8.2, b.fy + 11.0, N - 0.23), C.metal, M.metal, DETAIL)
	-- framed blueprint (a schematic in white lines on blue)
	local bp = at(b, -11.2, N, "S")
	Kit.part(b.m, b.cf, "BlueprintFrame", V3(4.4, 3.2, 0.1), bp * CF(0, 5.6, -0.05), C.oakDark, M.wood, DETAIL)
	Kit.part(b.m, b.cf, "Blueprint", V3(4.0, 2.8, 0.05), bp * CF(0, 5.6, -0.12), C.blue, M.smooth, DETAIL)
	for _, l in { { 0, 6.6, 3.2, 0.04 }, { 0, 4.6, 3.2, 0.04 }, { -1.6, 5.6, 0.04, 2.0 }, { 1.6, 5.6, 0.04, 2.0 }, { -0.4, 5.6, 0.04, 2.0 }, { 0.6, 5.2, 2.0, 0.04 } } do
		Kit.part(b.m, b.cf, "BlueprintLine", V3(math.max(l[3], 0.06), math.max(l[4], 0.06), 0.05), bp * CF(l[1], l[2], -0.15), C.white, M.smooth, DETAIL)
	end
	Kit.cylinder(b.m, b.cf, "BlueprintRing", "z", 0.05, 0.9, bp * CF(1.0, 6.0, -0.15), C.blueSoft, M.smooth, DETAIL)
	-- lit way-back plate on the west wall beside the bookcase (its inner prompt is the exit)
	local plate = at(b, -21.93, 127.9, "E")
	Kit.part(b.m, b.cf, "ExitPlate", V3(0.6, 0.9, 0.06), plate * CF(0, 4.0, -0.03), C.metalSoft, M.metal, DETAIL)
	Kit.cylinder(b.m, b.cf, "ExitRing", "z", 0.05, 0.36, plate * CF(0, 4.1, -0.08), C.statusGood, M.neon, DETAIL)
end

BUILD.secret_lab = function(b: B)
	local s = b.seed
	local room = b.room
	local W = -41.43 -- west panel wall surface + battens
	-- research wall: confidential roadmap board + live research wall screen (owner prompt)
	Kit.whiteboard(b.m, b.cf, at(b, W, 139.5, "E"), 10, "NEXT-GEN MODEL · INTERNAL\n• eval gates: reasoning · safety · cost\n• checkpoint 7 → red-team review\n• compute plan for the next training run\n• partner preview only after sign-off", s, { y = 6.3, name = "ResearchBoard" })
	local wallScreen = Kit.tvScreen(b.m, b.cf, at(b, W, 151, "E"), 9, "secretlab", b.accent, { y = 6.8, name = "ResearchWall" })
	Kit.prompt(wallScreen, "Research wall", b.owner, "empire", "research")
	-- two private research workstations facing the wall
	for i, z in { 141, 151 } do
		Kit.station(b.m, b.cf, room.id .. "_Desk" .. i, "research", "researcher", at(b, -30, z, "E"), room.level, "lab", b.owner, b.accent, "empire", "research", room.access, room.id)
	end
	-- dashboard monitors by the entrance wall
	for i, x in { -36, -30 } do
		Kit.tvScreen(b.m, b.cf, at(b, x, 130.57, "N"), 4.5, if i == 1 then "research" else "evaluation", b.accent, { y = 6.2, name = "LabMonitor" })
	end
	-- strategy table
	local centre = V3(-17, b.fy, 150)
	Kit.rug(b.m, b.cf, CF(centre), 9, 9, s + 1)
	Kit.meetingTable(b.m, b.cf, CF(centre), "round", 4.6, nil, s + 2)
	for i, a in { 0, 120, 240 } do
		Kit.meetingChair(b.m, b.cf, Kit.facing(centre + V3(math.cos(RAD(a + 30)) * 3.4, 0, math.sin(RAD(a + 30)) * 3.4), centre), s + 3 + i)
	end
	-- model checkpoints in a glass case: drives on two shelves, label on the plinth
	Kit.part(b.m, b.cf, "CasePlinth", V3(4.2, 3.0, 2.6), CF(-3, b.fy + 1.5, 146), C.stone, M.stone)
	Kit.part(b.m, b.cf, "CaseGlass", V3(4.0, 2.4, 2.4), CF(-3, b.fy + 4.2, 146), C.glass, M.glass, GLASS)
	Kit.part(b.m, b.cf, "CaseGlow", V3(4.0, 0.06, 0.08), CF(-3, b.fy + 3.03, 144.75), C.blueSoft, M.neon, DETAIL)
	for k, y in { 3.0, 4.15 } do
		Kit.part(b.m, b.cf, "CaseShelf", V3(3.4, 0.08, 1.8), CF(-3, b.fy + y + 0.04, 146), C.metal, M.metal, DETAIL)
		for j = 1, 3 do
			Kit.part(b.m, b.cf, "CheckpointDrive", V3(0.7, 0.28, 1.0), CF(-4.1 + (j - 1) * 1.1, b.fy + y + 0.22, 146 + (k - 1.5) * 0.3), C.metalSoft, M.metal, DETAIL)
		end
	end
	local plate = Kit.part(b.m, b.cf, "CaseLabel", V3(2.8, 0.5, 0.05), CF(-3, b.fy + 2.4, 144.68), C.brass, M.metal, DETAIL)
	label(plate, "MODEL CHECKPOINTS · INTERNAL", C.metal, 12)
	-- locked cabinets on the east wall (keypads)
	for i, z in { 135.5, 138.5, 141.5 } do
		local cab = at(b, 5.43, z, "W")
		Kit.cabinet(b.m, b.cf, cab, 3, 6.5, s + 10 + i)
		Kit.part(b.m, b.cf, "Keypad", V3(0.3, 0.45, 0.05), cab * CF(-0.9, 4.6, -1.63), C.metal, M.metal, DETAIL)
		Kit.part(b.m, b.cf, "KeypadLed", V3(0.14, 0.06, 0.05), cab * CF(-0.9, 4.78, -1.67), C.statusBad, M.neon, DETAIL)
	end
	-- private report terminal (kiosk) and the founder's lab computer on a sideboard
	local kiosk = at(b, 2.2, 132.3, "N")
	Kit.part(b.m, b.cf, "TerminalPedestal", V3(1.2, 3.4, 1.0), kiosk * CF(0, 1.7, 0), C.metal, M.metal)
	local terminal = Kit.part(b.m, b.cf, "ReportTerminal", V3(2.2, 1.4, 0.3), kiosk * CF(0, 4.1, -0.3) * ANG(RAD(15), 0, 0), C.screen, M.smooth)
	label(terminal, "PRIVATE REPORTS", b.accent, 16)
	Kit.action(terminal, "report", "Print private report", nil, { ownerOnly = true, actionText = "Print", maxDistance = 8 })
	local sb = at(b, 5.43, 155.5, "W")
	Kit.sideboard(b.m, b.cf, sb, 5, s + 20)
	local pc = Kit.part(b.m, b.cf, "LabComputer", V3(2.8, 1.7, 0.15), sb * CF(0, 4.05, -0.7), C.screen, M.smooth)
	label(pc, "LAB · PRIVATE", b.accent, 16)
	Kit.part(b.m, b.cf, "MonitorStand", V3(0.3, 0.6, 0.45), sb * CF(0, 3.12, -0.6), C.metal, M.metal, DETAIL)
	Kit.action(pc, "ownerComputer", "Private lab computer", "lab", { ownerOnly = true, actionText = "Open", maxDistance = 8 })
	-- calm, tasteful way-back cue beside the passage opening (the bookcase prompt is the exit)
	local cue = at(b, -13.3, 130.57, "N")
	local cuePlate = Kit.part(b.m, b.cf, "ArchivePlate", V3(0.9, 1.3, 0.06), cue * CF(0, 4.2, -0.03), C.metalSoft, M.metal, DETAIL)
	Kit.cylinder(b.m, b.cf, "ArchiveRing", "z", 0.05, 0.5, cue * CF(0, 4.45, -0.08), C.statusGood, M.neon, DETAIL)
	Kit.text(cuePlate, "ARCHIVE", { color = C.white, size = 12, valign = "bottom", light = 0.5, maxDistance = 30 })
	Kit.plant(b.m, b.cf, CF(-1, b.fy, 157.6), "m", s + 21)
end

-- Small articulated robot arm standing on `base` (top surface), scaled by k: an Atomic PropFx "arm"
-- model (PROPFX_CONTRACT §3): parts carry FxLink (1 turret, 2 upper arm, 3 forearm + gripper) and the
-- model FxJoint1..3 (home joint frames in pivot space; joint 1 turns about local Y, 2 and 3 about local Z).
local function robotArm(b: B, base: CFrame, k: number, propId: string): Model
	local m = Kit.propModel(b.m, b.cf, "RobotArm", base)
	local function link(p: BasePart, n: number)
		p:SetAttribute("FxLink", n)
	end
	Kit.cylinder(m, b.cf, "ArmBase", "y", 0.4 * k, 1.4 * k, base * CF(0, 0.2 * k, 0), C.metal, M.metal, DETAIL)
	link(Kit.cylinder(m, b.cf, "ArmTurret", "y", 0.9 * k, 0.9 * k, base * CF(0, 0.85 * k, 0), C.white, M.smooth, DETAIL), 1)
	local shoulderLocal = CF(0, 1.3 * k, 0) * ANG(0, 0, RAD(-35))
	local shoulder = base * shoulderLocal
	link(Kit.part(m, b.cf, "ArmUpper", V3(0.45, 2.4, 0.45) * k, shoulder * CF(0, 1.2 * k, 0), C.white, M.smooth, DETAIL), 2)
	local elbowLocal = shoulderLocal * CF(0, 2.4 * k, 0) * ANG(0, 0, RAD(100))
	local elbow = base * elbowLocal
	link(Kit.ball(m, b.cf, "ArmJoint", 0.6 * k, elbow, C.metal, M.metal, DETAIL), 2)
	link(Kit.part(m, b.cf, "ArmFore", V3(0.35, 2.0, 0.35) * k, elbow * CF(0, 1.0 * k, 0), C.white, M.smooth, DETAIL), 3)
	local wrist = elbow * CF(0, 2.0 * k, 0)
	link(Kit.cylinder(m, b.cf, "ArmWrist", "y", 0.35 * k, 0.45 * k, wrist, C.metal, M.metal, DETAIL), 3)
	for _, x in { -0.16, 0.16 } do
		link(Kit.part(m, b.cf, "ArmFinger", V3(0.08, 0.5, 0.2) * k, wrist * CF(x * k, 0.4 * k, 0), C.metal, M.metal, DETAIL), 3)
	end
	fx(m, "arm", { FxJoint1 = CFrame.identity, FxJoint2 = shoulderLocal, FxJoint3 = elbowLocal, FxSeconds = 12, PropId = propId })
	return m
end

-- Island lab bench (centred, long axis local X), slate top at 3.2.
local function labIsland(b: B, base: CFrame, L: number)
	Kit.part(b.m, b.cf, "IslandTop", V3(L, 0.25, 3.6), base * CF(0, 3.075, 0), C.metalSoft, M.slate)
	for _, x in { -1, 1 } do
		Kit.part(b.m, b.cf, "IslandCabinet", V3(2.4, 2.95, 3.2), base * CF(x * (L / 2 - 1.3), 1.475, 0), C.white, M.smooth)
	end
end

BUILD.prototype = function(b: B)
	local s = b.seed
	local room = b.room
	local W = 6.57 -- west panel wall surface + battens
	-- project wall: large prototype screen over the special project workstation, roadmap board
	Kit.tvScreen(b.m, b.cf, at(b, W, 124, "E"), 12, "prototype", b.accent, { y = 8.0, name = "PrototypeScreen" })
	Kit.station(b.m, b.cf, room.id .. "_Desk1", "research", "researcher", at(b, 13, 124, "E"), room.level, "lab", b.owner, b.accent, "lab", nil, room.access, room.id)
	Kit.whiteboard(b.m, b.cf, at(b, W, 144, "E"), 9, "PROJECT ROADMAP\nQ1  prototype v0 · bench validation\nQ2  robotics + model integration\nQ3  safety review · partner pilots\nQ4  launch decision", s, { name = "RoadmapBoard" })
	-- south wall benches: GPU boards + scope, test rig + instrument (flush door x 29..35 stays free)
	local wb1 = at(b, 15, 94.57, "N")
	Kit.workbench(b.m, b.cf, wb1, 12, s + 1)
	local desk = room.id .. "_Desk1"
	for k = 1, 3 do
		local x = -3.5 + (k - 1) * 3.5
		Kit.part(b.m, b.cf, "GpuBoard", V3(2.2, 0.08, 1.2), wb1 * CF(x, 3.24, -1.5), C.sage, M.smooth, DETAIL)
		Kit.part(b.m, b.cf, "Heatsink", V3(1.5, 0.45, 1.0), wb1 * CF(x, 3.5, -1.5), C.metalSoft, M.metal, DETAIL)
		-- board fans idle slowly and spin up while the project desk is staffed
		local boardFan = Kit.cylinder(b.m, b.cf, "BoardFan", "y", 0.08, 0.8, wb1 * CF(x, 3.77, -1.5), C.metal, M.metal, DETAIL)
		fx(boardFan, "spin", { FxAxis = "x", FxRate = 14, FxIdle = "slow", FxStation = desk })
	end
	Kit.part(b.m, b.cf, "Scope", V3(1.6, 1.1, 1.2), wb1 * CF(4.6, 3.75, -1.2), C.white, M.smooth, DETAIL)
	Kit.part(b.m, b.cf, "ScopeScreen", V3(1.0, 0.6, 0.05), wb1 * CF(4.4, 3.8, -1.82), C.screen, M.smooth, DETAIL)
	local wb2 = at(b, 47, 94.57, "N")
	Kit.workbench(b.m, b.cf, wb2, 10, s + 2)
	for _, p in { { -1.5, -0.9 }, { 1.5, -0.9 }, { -1.5, -2.3 }, { 1.5, -2.3 } } do
		Kit.part(b.m, b.cf, "RigPost", V3(0.12, 2.2, 0.12), wb2 * CF(p[1], 4.3, p[2]), C.metalSoft, M.metal, DETAIL)
	end
	for _, z in { -0.9, -2.3 } do
		Kit.part(b.m, b.cf, "RigRail", V3(3.1, 0.12, 0.12), wb2 * CF(0, 5.4, z), C.metalSoft, M.metal, DETAIL)
	end
	Kit.part(b.m, b.cf, "DeviceUnderTest", V3(1.4, 0.8, 1.0), wb2 * CF(0, 3.6, -1.6), C.white, M.smooth, DETAIL)
	local probe = Kit.part(b.m, b.cf, "RigProbe", V3(0.1, 1.2, 0.1), wb2 * CF(0.3, 4.6, -1.6), C.metal, M.metal, DETAIL)
	-- the probe taps the device under test (oscillating slider) while the test rig runs
	fx(probe, "slider", { FxAxis = "y", FxTravel = -0.35, FxRate = 1.4, FxSeconds = 10, PropId = "TestRig" })
	Kit.action(probe, "prop", "Test rig · run test", "TestRig", { ownerOnly = true, actionText = "Run", maxDistance = 8 })
	Kit.cylinder(b.m, b.cf, "RigCable", "x", 2.2, 0.15, wb2 * CF(1.8, 3.3, -0.5), C.fabricCharcoal, M.rubber, DETAIL)
	Kit.part(b.m, b.cf, "Instrument", V3(1.6, 1.1, 1.2), wb2 * CF(3.4, 3.75, -1.2), C.white, M.smooth, DETAIL)
	Kit.part(b.m, b.cf, "InstrumentScreen", V3(1.0, 0.6, 0.05), wb2 * CF(3.2, 3.8, -1.82), C.screen, M.smooth, DETAIL)
	-- island A: small robot arm + controller; island B: open GPU test chassis + device prototype
	labIsland(b, at(b, 32, 128, "S"), 12)
	labIsland(b, at(b, 32, 142, "S"), 12)
	robotArm(b, CF(29, b.fy + 3.2, 128), 1, "RobotArm1")
	local controller = Kit.part(b.m, b.cf, "ArmController", V3(1.6, 1.0, 1.2), CF(34.5, b.fy + 3.7, 128), C.metal, M.metal, DETAIL)
	Kit.action(controller, "prop", "Robot arm · run program", "RobotArm1", { ownerOnly = true, actionText = "Run", maxDistance = 8 })
	Kit.cylinder(b.m, b.cf, "EStop", "y", 0.2, 0.45, CF(34.5, b.fy + 4.3, 127.7), C.statusBad, M.smooth, DETAIL)
	Kit.part(b.m, b.cf, "TestChassis", V3(3.0, 0.7, 2.2), CF(29, b.fy + 3.55, 142), C.metal, M.metal, DETAIL)
	for k = 1, 4 do
		Kit.part(b.m, b.cf, "GpuCard", V3(0.2, 1.0, 1.8), CF(28.0 + (k - 1) * 0.65, b.fy + 4.4, 142), C.sage, M.smooth, DETAIL)
	end
	Kit.part(b.m, b.cf, "LaptopBase", V3(2.2, 0.1, 1.5), CF(33, b.fy + 3.25, 141.6), C.metalSoft, M.metal, DETAIL)
	Kit.part(b.m, b.cf, "LaptopLid", V3(2.2, 1.4, 0.08), CF(33, b.fy + 3.95, 142.35) * ANG(RAD(10), 0, 0), C.metalSoft, M.metal, DETAIL)
	Kit.cylinder(b.m, b.cf, "PrototypeDevice", "y", 0.3, 1.2, CF(36, b.fy + 3.35, 142), C.white, M.smooth, DETAIL)
	for i, p in { { 28.5, 124.6 }, { 35.5, 124.6 }, { 28.5, 138.6 }, { 35.5, 138.6 } } do
		Kit.stool(b.m, b.cf, CF(p[1], b.fy, p[2]), s + 3 + i, 3.0)
	end
	-- robot test cell: mesh enclosure (open towards the lab), arm on a pedestal, part fixture table
	local mesh: Kit.Opts = { transparency = 0.55, castShadow = false }
	Kit.part(b.m, b.cf, "CellMesh", V3(10, 6, 0.1), CF(47, b.fy + 3.2, 112), C.metalSoft, M.metal, mesh)
	Kit.part(b.m, b.cf, "CellMesh", V3(10, 6, 0.1), CF(47, b.fy + 3.2, 102), C.metalSoft, M.metal, mesh)
	Kit.part(b.m, b.cf, "CellMesh", V3(0.1, 6, 10), CF(52, b.fy + 3.2, 107), C.metalSoft, M.metal, mesh)
	Kit.part(b.m, b.cf, "CellMesh", V3(0.1, 6, 3.2), CF(42, b.fy + 3.2, 103.6), C.metalSoft, M.metal, mesh)
	Kit.part(b.m, b.cf, "CellMesh", V3(0.1, 6, 3.2), CF(42, b.fy + 3.2, 110.4), C.metalSoft, M.metal, mesh)
	for _, p in { V3(42, 0, 102), V3(52, 0, 102), V3(42, 0, 112), V3(52, 0, 112), V3(42, 0, 105.2), V3(42, 0, 108.8) } do
		Kit.part(b.m, b.cf, "CellPost", V3(0.3, 6.4, 0.3), CF(p.X, b.fy + 3.2, p.Z), C.statusBusy, M.metal)
	end
	Kit.part(b.m, b.cf, "ArmPedestal", V3(1.6, 2.4, 1.6), CF(48.5, b.fy + 1.2, 106), C.metal, M.metal)
	robotArm(b, CF(48.5, b.fy + 2.4, 106), 1.5, "RobotArm2")
	local fixture = Kit.part(b.m, b.cf, "FixtureTable", V3(5, 0.25, 2), CF(47.5, b.fy + 3.0, 110.4), C.metalSoft, M.slate)
	Kit.action(fixture, "prop", "Robot test cell · start cycle", "RobotArm2", { ownerOnly = true, actionText = "Start", maxDistance = 9 })
	Kit.part(b.m, b.cf, "FixtureTableBase", V3(4.4, 2.85, 1.6), CF(47.5, b.fy + 1.45, 110.4), C.metal, M.metal)
	local cellSign = Kit.part(b.m, b.cf, "CellSign", V3(0.06, 0.8, 2.4), CF(41.92, b.fy + 6.0, 103.6), C.statusBusy, M.smooth, DETAIL)
	label(cellSign, "ROBOT TEST CELL", C.metal, 14, Enum.NormalId.Left)
	-- storage shelving on the east wall north of the vault door
	Kit.rackShelf(b.m, b.cf, at(b, 57.43, 139, "W"), 4, s + 8)
	Kit.rackShelf(b.m, b.cf, at(b, 57.43, 144, "W"), 4, s + 9)
	-- sofa corner by the north glazing
	Kit.rug(b.m, b.cf, CF(48, b.fy, 152.6), 13, 10, s + 10)
	Kit.sofa(b.m, b.cf, at(b, 48, 156.8, "S"), 8, s + 11)
	Kit.coffeeTable(b.m, b.cf, at(b, 48, 151.8, "S"), s + 12, 4, 2.4)
	Kit.loungeChair(b.m, b.cf, Kit.facing(V3(42.2, b.fy, 151.4), V3(48, b.fy, 152)), s + 13)
	Kit.loungeChair(b.m, b.cf, Kit.facing(V3(53.8, b.fy, 151.4), V3(48, b.fy, 152)), s + 14)
	Kit.floorLamp(b.m, b.cf, at(b, 42.6, 157.4, "S"), s + 15)
	Kit.plant(b.m, b.cf, CF(55.2, b.fy, 156.8), "l", s + 16)
	Kit.plant(b.m, b.cf, CF(9.4, b.fy, 156.8), "l", s + 17)
	Kit.plant(b.m, b.cf, CF(55.4, b.fy, 97.6), "m", s + 18)
end

-- Double-sided archive drive rack (centred, long axis local X): cartridge groups + status strip.
local function driveRack(b: B, base: CFrame, L: number, seed: number)
	local H, D = 7.4, 2.4
	for _, x in { -1, 1 } do
		Kit.part(b.m, b.cf, "RackEnd", V3(0.25, H, D), base * CF(x * (L / 2 - 0.125), H / 2, 0), C.metal, M.metal)
	end
	Kit.part(b.m, b.cf, "RackTop", V3(L, 0.15, D), base * CF(0, H - 0.075, 0), C.metal, M.metal)
	Kit.part(b.m, b.cf, "RackSpine", V3(L - 0.5, H - 0.3, 0.08), base * CF(0, H / 2, 0), C.metalSoft, M.metal)
	for k = 0, 3 do
		local y = 0.3 + k * 1.75
		Kit.part(b.m, b.cf, "RackShelf", V3(L - 0.5, 0.08, D), base * CF(0, y, 0), C.metalSoft, M.metal)
		for _, side in { -1, 1 } do
			local n = k * 4 + (side + 1)
			local w1 = Kit.range(seed, n, L * 0.3, L * 0.45)
			local w2 = Kit.range(seed, n + 50, L * 0.25, L * 0.4)
			Kit.part(b.m, b.cf, "DriveCartridges", V3(w1, 1.2, 0.95), base * CF(-L / 2 + 0.4 + w1 / 2, y + 0.64, side * 0.6), C.screen, M.smooth, DETAIL)
			Kit.part(b.m, b.cf, "DriveCartridges", V3(w2, 1.2, 0.95), base * CF(L / 2 - 0.4 - w2 / 2, y + 0.64, side * 0.6), C.metal, M.smooth, DETAIL)
		end
	end
	for _, side in { -1, 1 } do
		Kit.part(b.m, b.cf, "RackStatus", V3(L - 0.8, 0.06, 0.05), base * CF(0, H - 0.1, side * (D / 2 + 0.025)), C.blueSoft, M.neon, DETAIL)
	end
end

BUILD.vault = function(b: B)
	local s = b.seed
	local Hh = 12.9
	-- steel liner on all four walls (vault door opening z 124..130 on the west wall stays open)
	local y = b.fy + Hh / 2
	Kit.part(b.m, b.cf, "VaultLiner", V3(0.3, Hh, 124 - 94.58), CF(58.73, y, (124 + 94.58) / 2), C.metalSoft, M.metal)
	Kit.part(b.m, b.cf, "VaultLiner", V3(0.3, Hh, 158.6 - 130), CF(58.73, y, (158.6 + 130) / 2), C.metalSoft, M.metal)
	Kit.part(b.m, b.cf, "VaultLiner", V3(80.6 - 58.88, Hh, 0.3), CF((80.6 + 58.88) / 2, y, 94.73), C.metalSoft, M.metal)
	Kit.part(b.m, b.cf, "VaultLiner", V3(0.3, Hh, 158.9 - 94.58), CF(80.75, y, (158.9 + 94.58) / 2), C.metalSoft, M.metal)
	Kit.part(b.m, b.cf, "VaultLiner", V3(80.6 - 58.88, Hh, 0.3), CF((80.6 + 58.88) / 2, y, 158.75), C.metalSoft, M.metal)
	for _, by in { 4.5, 9.0 } do
		Kit.part(b.m, b.cf, "LinerBand", V3(0.08, 0.3, 158.6 - 94.88), CF(80.56, b.fy + by, (158.6 + 94.88) / 2), C.metal, M.metal, DETAIL)
		Kit.part(b.m, b.cf, "LinerBand", V3(80.6 - 58.88, 0.3, 0.08), CF((80.6 + 58.88) / 2, b.fy + by, 158.56), C.metal, M.metal, DETAIL)
		Kit.part(b.m, b.cf, "LinerBand", V3(80.6 - 58.88, 0.3, 0.08), CF((80.6 + 58.88) / 2, b.fy + by, 94.92), C.metal, M.metal, DETAIL)
	end
	-- the model safe on the door axis
	local sf = at(b, 80.6, 127, "W")
	local safe = Kit.part(b.m, b.cf, "ModelSafe", V3(6, 8, 3), sf * CF(0, 4.25, -1.5), C.metalSoft, M.metal)
	Kit.part(b.m, b.cf, "SafePlinth", V3(6.2, 0.25, 3.2), sf * CF(0, 0.125, -1.5), C.metal, M.metal)
	Kit.part(b.m, b.cf, "SafeFront", V3(5.2, 7.0, 0.08), sf * CF(0, 4.3, -3.04), C.metal, M.metal, DETAIL)
	Kit.cylinder(b.m, b.cf, "SafeWheel", "z", 0.3, 0.7, sf * CF(1.2, 4.3, -3.22), C.stoneDeep, M.metal, DETAIL)
	for k = 0, 2 do
		Kit.part(b.m, b.cf, "SafeSpoke", V3(2.0, 0.14, 0.14), sf * CF(1.2, 4.3, -3.3) * ANG(0, 0, k * PI / 3), C.stoneDeep, M.metal, DETAIL)
	end
	Kit.part(b.m, b.cf, "SafeKeypad", V3(0.6, 0.9, 0.08), sf * CF(-1.8, 4.9, -3.12), C.metal, M.metal, DETAIL)
	Kit.part(b.m, b.cf, "SafeKeypadLed", V3(0.3, 0.08, 0.05), sf * CF(-1.8, 5.25, -3.17), C.statusBusy, M.neon, DETAIL)
	local plate = Kit.part(b.m, b.cf, "SafeLabel", V3(2.4, 0.5, 0.05), sf * CF(0, 7.35, -3.1), C.brass, M.metal, DETAIL)
	label(plate, "MODEL VAULT", C.metal, 16)
	Kit.action(safe, "modelSafe", "Open model vault", nil, { ownerOnly = true, actionText = "Open", maxDistance = 8 })
	Kit.tvScreen(b.m, b.cf, at(b, 80.6, 116.5, "W"), 6, "vault", b.accent, { y = 6.4, name = "VaultScreen" })
	-- archive drive racks north and south of the axis, a small bench facing it
	for i, z in { 101, 108, 115, 139, 146, 153 } do
		driveRack(b, at(b, 70.5, z, "S"), 11, s + i * 13)
	end
	Kit.bench(b.m, b.cf, at(b, 70.5, 134.4, "S"), 5, s + 2)
end

---------------------------------------------------------------------------------------------
-- Roof level
---------------------------------------------------------------------------------------------
BUILD.roof_lobby = function(b: B)
	local s = b.seed
	-- lift queue (x -13..13), lift portal (x -8..8, z 50..54) and the stair door swing stay clear
	Kit.bench(b.m, b.cf, at(b, 17.5, 52.4, "S"), 6, s)
	Kit.plant(b.m, b.cf, CF(-19.4, b.fy, 51.4), "l", s + 1)
	Kit.plant(b.m, b.cf, CF(19.5, b.fy, 44.6), "m", s + 2)
	Kit.wayfinding(b.m, b.cf, at(b, -21.5, 46.5, "E"), {
		"ROOF TERRACE · LIFT · STAIRS",
		"Roof terrace  ·  south doors",
		"Lift  ·  north",
		"Stairs  ·  north-west",
		"Roof plant & solar  ·  technical staff",
	}, { name = "RoofDirectory" })
end

-- Sun lounger (outdoor): oak frame, cushion Seat; sitter faces local -Z (foot end).
local function sunLounger(b: B, base: CFrame, seed: number): Seat
	Kit.part(b.m, b.cf, "LoungerFrame", V3(2.4, 0.3, 6.4), base * CF(0, 0.85, 0), C.oak, M.wood)
	for _, z in { -2.8, 2.8 } do
		Kit.part(b.m, b.cf, "LoungerLeg", V3(2.2, 0.7, 0.3), base * CF(0, 0.35, z), C.oakDark, M.wood)
	end
	local cover = Kit.pick({ C.white, C.fabricSand, C.sageLight }, seed)
	local seat = Kit.seat(b.m, b.cf, "Seat", V3(2.2, 0.3, 3.8), base * CF(0, 1.15, -1.2), cover, M.fabric)
	Kit.part(b.m, b.cf, "LoungerBack", V3(2.2, 0.35, 2.4), base * CF(0, 1.75, 2.0) * ANG(RAD(-30), 0, 0), cover, M.fabric)
	return seat
end

BUILD.roof_terrace = function(b: B)
	local s = b.seed
	local y0 = b.y
	local fd = y0 + 0.25 -- timber decks under the seating groups
	local function deck(x1: number, x2: number, z1: number, z2: number)
		Kit.part(b.m, b.cf, "TerraceDeck", V3(x2 - x1, 0.25, z2 - z1), CF((x1 + x2) / 2, y0 + 0.125, (z1 + z2) / 2), C.oakDark, M.planks)
	end
	local function on(x: number, z: number, front: (string | number)?): CFrame
		return Kit.place(x, fd, z, front)
	end
	-- Routes kept free: the 6-stud band z 36..42 in front of the lobby, x ±(16..22) beside the
	-- skylight railing, the front band z -31..-18 to the street-side parapet, side parapets.
	-- G1 west: pergola lounge
	deck(-46, -28, 4, 20)
	local sofa1 = Kit.sofa(b.m, b.cf, on(-37, 17.6, "S"), 8, s, { color = C.fabricSand })
	Kit.coffeeTable(b.m, b.cf, on(-37, 12.4, "S"), s + 1, 4, 2.4)
	for i, x in { -42.6, -31.4 } do
		Kit.loungeChair(b.m, b.cf, Kit.facing(V3(x, fd, 10), V3(-37, fd, 12.5)), s + 2 + i, { color = C.sage })
	end
	for _, p in { { -45.4, 4.6 }, { -28.6, 4.6 }, { -45.4, 19.4 }, { -28.6, 19.4 } } do
		Kit.part(b.m, b.cf, "PergolaPost", V3(0.6, 9.4, 0.6), CF(p[1], fd + 4.7, p[2]), C.oak, M.wood)
	end
	for _, z in { 4.6, 19.4 } do
		Kit.part(b.m, b.cf, "PergolaBeam", V3(18, 0.6, 0.4), CF(-37, fd + 9.7, z), C.oak, M.wood)
	end
	for k = 0, 6 do
		Kit.part(b.m, b.cf, "PergolaRafter", V3(0.3, 0.45, 16), CF(-45.2 + k * 16.4 / 6, fd + 10.2, 12), C.oakLight, M.wood, DETAIL)
	end
	Kit.pendant(b.m, b.cf, CF(-37, fd + 9.98, 12.4), "warm", { drop = 3.0 }) -- hangs from the middle rafter
	Kit.ceilingFan(b.m, b.cf, CF(-45.2 + 16.4 / 6, fd + 9.975, 12), 4) -- from the second rafter
	grassPlanter(b, Kit.place(-48.4, y0, 12, "E"), 14, 2.4, s + 5)
	grassPlanter(b, Kit.place(-37, y0, 22.6, "S"), 14, 2.4, s + 6)
	-- G2 east: lounge under a parasol
	deck(28, 46, 4, 20)
	Kit.sofa(b.m, b.cf, on(37, 17.6, "S"), 8, s + 7, { color = C.sage })
	Kit.coffeeTable(b.m, b.cf, on(37, 12.4, "S"), s + 8, 4, 2.4)
	local chairs2: { Seat } = {}
	for i, x in { 31.4, 42.6 } do
		table.insert(chairs2, Kit.loungeChair(b.m, b.cf, Kit.facing(V3(x, fd, 10), V3(37, fd, 12.5)), s + 9 + i, { color = C.fabricSand }))
	end
	Kit.cylinder(b.m, b.cf, "ParasolBase", "y", 0.3, 1.6, CF(37, fd + 0.15, 7.2), C.metal, M.metal)
	Kit.cylinder(b.m, b.cf, "ParasolPole", "y", 8.2, 0.25, CF(37, fd + 4.4, 7.2), C.metal, M.metal)
	Kit.cylinder(b.m, b.cf, "ParasolCanopy", "y", 0.25, 10, CF(37, fd + 8.6, 7.2), C.fabricSand, M.fabric, DETAIL)
	grassPlanter(b, Kit.place(48.4, y0, 12, "W"), 14, 2.4, s + 12)
	grassPlanter(b, Kit.place(37, y0, 22.6, "S"), 14, 2.4, s + 13)
	-- G3 front west: viewpoint chairs facing the street
	deck(-42, -26, -29.5, -21.5)
	local view1 = Kit.loungeChair(b.m, b.cf, on(-38, -25.2, "S"), s + 14, { color = C.fabricSand })
	Kit.loungeChair(b.m, b.cf, on(-30, -25.2, "S"), s + 15, { color = C.fabricSand })
	sideTable(b, -34, -25.2, fd)
	-- G4 front east: sun loungers
	deck(24, 48, -30, -20)
	local loungers: { Seat } = {}
	for i, x in { 27.5, 33, 38.5, 44 } do
		table.insert(loungers, sunLounger(b, on(x, -25, "S"), s + 16 + i))
	end
	for _, x in { 30.25, 41.25 } do
		sideTable(b, x, -27.6, fd)
	end
	-- side viewpoints: benches facing the parapets between planters; trees
	for side = -1, 1, 2 do
		Kit.bench(b.m, b.cf, Kit.place(side * 77.4, y0, 4, if side < 0 then "W" else "E"), 6, s + 20 + side)
		grassPlanter(b, Kit.place(side * 77.6, y0, -3.6, "S"), 5, 2.4, s + 23 + side)
		grassPlanter(b, Kit.place(side * 77.6, y0, 11.6, "S"), 5, 2.4, s + 26 + side)
		Kit.plant(b.m, b.cf, CF(side * 74, y0, 27), "tree", s + 29 + side)
	end
	Kit.plant(b.m, b.cf, CF(-47.5, y0, -25.5), "tree", s + 32)
	-- fascia sign above the lobby doors (on the transom rail, outside)
	local sign = Kit.part(b.m, b.cf, "RoofTerraceSign", V3(7.6, 1.2, 0.1), CF(0, y0 + 10.9, 41.87), C.metal, M.metal)
	label(sign, "ROOF TERRACE", C.white, nil)
	Kit.part(b.m, b.cf, "SignAccent", V3(7.6, 0.08, 0.05), CF(0, y0 + 10.34, 41.8), b.accent, M.neon, DETAIL)
	-- staff break points
	lounge(b, sofa1[1], 1, "roof", V3(-42.6, 0, 15.2))
	lounge(b, chairs2[2], 2, "roof", V3(42.6, 0, 6.4))
	lounge(b, view1, 3, "roof", V3(-38, 0, -28.9))
	lounge(b, loungers[1], 4, "roof", V3(25.0, 0, -24.2))
end

-- Condenser unit with a top fan (two blade parts tagged ClusterFan, spinning about local Z).
local function condenser(b: B, x: number, z: number, y0: number)
	Kit.part(b.m, b.cf, "CondenserCasing", V3(5.5, 3.2, 4), CF(x, y0 + 2.0, z), C.plasterShade, M.metal)
	Kit.part(b.m, b.cf, "CondenserCoil", V3(5.0, 2.4, 0.05), CF(x, y0 + 1.9, z - 2.03), C.metalSoft, M.metal, DETAIL)
	Kit.cylinder(b.m, b.cf, "FanShroud", "y", 0.3, 3.4, CF(x, y0 + 3.75, z), C.metal, M.metal)
	for k = 0, 1 do
		local blade = Kit.part(b.m, b.cf, "FanBlade", V3(3.0, 0.5, 0.08), CF(x, y0 + 3.97, z) * ANG(-PI / 2, 0, 0) * ANG(0, 0, k * PI / 2 + 0.3), C.metalSoft, M.metal, DETAIL)
		blade:SetAttribute("FanHome", blade.CFrame)
		Collection:AddTag(blade, "ClusterFan")
		-- always-on machinery: slow idle, full speed while the company trains
		fx(blade, "spin", { FxAxis = "z", FxRate = 7, FxGate = "Training", FxIdle = "slow" })
	end
end

BUILD.roof_tech = function(b: B)
	local y0 = b.y
	-- maintenance walkway (grating, 0.25 high) from the gate to the units, the AHU and the lift
	-- machine room door; the gate swing (z 42..48) and the door area stay clear
	local function grating(x1: number, x2: number, z1: number, z2: number)
		Kit.part(b.m, b.cf, "Walkway", V3(x2 - x1, 0.25, z2 - z1), CF((x1 + x2) / 2, y0 + 0.125, (z1 + z2) / 2), C.metalSoft, M.metal)
	end
	grating(50, 54, 48.5, 71)
	grating(23, 50, 65, 69)
	grating(54, 61.6, 48.5, 51.3)
	-- two condenser groups on steel dunnage along the north parapet
	for _, g in { 36.5, 67.5 } do
		for _, z in { 73.6, 76.4 } do
			Kit.part(b.m, b.cf, "Dunnage", V3(19, 0.4, 0.4), CF(g, y0 + 0.2, z), C.metal, M.metal)
		end
		for k = -1, 1 do
			condenser(b, g + k * 6.5, 75, y0 + 0.4)
		end
		Kit.cylinder(b.m, b.cf, "RefrigerantLine", "x", 19, 0.45, CF(g, y0 + 0.23, 71.8), C.metal, M.rubber, DETAIL)
	end
	-- air handling unit with its supply duct dropping into the roof
	Kit.part(b.m, b.cf, "AhuCurb", V3(12.4, 0.3, 6.4), CF(68, y0 + 0.15, 53), C.concrete, M.concrete)
	local ahu = Kit.part(b.m, b.cf, "AirHandlingUnit", V3(12, 5, 6), CF(68, y0 + 2.8, 53), C.plasterShade, M.metal)
	label(ahu, "AHU · R1", C.metal, 22)
	Kit.part(b.m, b.cf, "SupplyDuct", V3(5.5, 2.5, 2.5), CF(59.25, y0 + 3.8, 53), C.metalSoft, M.metal)
	Kit.part(b.m, b.cf, "DuctRiser", V3(2.5, 5.05, 2.5), CF(57.25, y0 + 2.525, 53), C.metalSoft, M.metal)
	Kit.part(b.m, b.cf, "DuctCurb", V3(3.2, 0.4, 3.2), CF(57.25, y0 + 0.2, 53), C.concrete, M.concrete)
end

BUILD.roof_solar = function(b: B)
	-- Solar array: no gameplay effect (pure set dressing for the plant zone).
	local y0 = b.y
	local tilt = RAD(-22) -- north edge up, panels face south
	for _, z in { 50, 57, 64, 71 } do
		for _, half in { { -79, -57 }, { -47, -25 } } do
			local x1, x2 = half[1], half[2]
			local L, cx = x2 - x1, (x1 + x2) / 2
			local panel = Kit.part(b.m, b.cf, "SolarPanel", V3(L, 0.12, 4.2), CF(cx, y0 + 1.7, z) * ANG(tilt, 0, 0), C.screen, M.glass)
			local gui = Instance.new("SurfaceGui")
			gui.Name = "Cells"
			gui.Face = Enum.NormalId.Top
			gui.CanvasSize = Vector2.new(math.floor(L * 20), 84)
			gui.LightInfluence = 1
			gui.MaxDistance = 120
			gui.Parent = panel
			for k = 1, math.floor(L / 2) - 1 do
				local line = Instance.new("Frame")
				line.Name = "CellLine"
				line.BorderSizePixel = 0
				line.BackgroundColor3 = C.metalSoft
				line.Position = UDim2.fromOffset(k * 40, 0)
				line.Size = UDim2.fromOffset(2, 84)
				line.Parent = gui
			end
			local mid = Instance.new("Frame")
			mid.Name = "CellLine"
			mid.BorderSizePixel = 0
			mid.BackgroundColor3 = C.metalSoft
			mid.Position = UDim2.fromOffset(0, 41)
			mid.Size = UDim2.new(1, 0, 0, 2)
			mid.Parent = gui
			for _, x in { x1 + 1, x2 - 1 } do
				Kit.part(b.m, b.cf, "PanelLegFront", V3(0.2, 0.95, 0.2), CF(x, y0 + 0.475, z - 1.85), C.metalSoft, M.metal)
				Kit.part(b.m, b.cf, "PanelLegBack", V3(0.2, 2.45, 0.2), CF(x, y0 + 1.225, z + 1.85), C.metalSoft, M.metal)
			end
			Kit.part(b.m, b.cf, "PanelRail", V3(L, 0.15, 0.25), CF(cx, y0 + 0.075, z - 1.85), C.metalSoft, M.metal, DETAIL)
			Kit.part(b.m, b.cf, "PanelRail", V3(L, 0.15, 0.25), CF(cx, y0 + 0.075, z + 1.85), C.metalSoft, M.metal, DETAIL)
		end
	end
	-- maintenance walkway from the gate, inverter cabinets on the stair head-house wall
	Kit.part(b.m, b.cf, "Walkway", V3(4, 0.25, 29), CF(-52, y0 + 0.125, 63.5), C.metalSoft, M.metal)
	local inv = Kit.place(-22.5, y0, 63.5, "W")
	Kit.part(b.m, b.cf, "Inverter", V3(2.6, 3.4, 1.0), inv * CF(-1.6, 3.2, -0.5), C.white, M.smooth)
	Kit.part(b.m, b.cf, "Inverter", V3(2.6, 3.4, 1.0), inv * CF(1.6, 3.2, -0.5), C.white, M.smooth)
	Kit.part(b.m, b.cf, "CombinerBox", V3(1.6, 2.0, 0.8), inv * CF(4.6, 3.6, -0.4), C.plasterShade, M.metal)
	for _, x in { -1.6, 1.6 } do
		Kit.part(b.m, b.cf, "InverterLed", V3(0.5, 0.08, 0.05), inv * CF(x, 4.3, -1.02), C.statusGood, M.neon, DETAIL)
		Kit.cylinder(b.m, b.cf, "Conduit", "y", 1.5, 0.3, inv * CF(x, 0.75, -0.3), C.metal, M.metal, DETAIL)
	end
end

BUILD.machine = function(b: B)
	-- traction machine on its bedplate next to the shaft, controllers on the north wall
	Kit.part(b.m, b.cf, "Bedplate", V3(4.5, 1.0, 7), CF(10.5, b.fy + 0.5, 61), C.concrete, M.concrete)
	Kit.cylinder(b.m, b.cf, "TractionMotor", "z", 3, 2.4, CF(10.5, b.fy + 2.2, 63), C.blue, M.metal)
	Kit.part(b.m, b.cf, "Gearbox", V3(2.6, 2.4, 1.8), CF(10.5, b.fy + 2.2, 60.6), C.blue, M.metal)
	-- the traction sheave turns while the lift cabin moves (PropFx gate "Lift": cabin LiftState MOVING)
	local sheave = Kit.cylinder(b.m, b.cf, "Sheave", "z", 0.6, 3.2, CF(10.5, b.fy + 2.6, 59.1), C.metal, M.metal, { canCollide = false })
	Kit.part(sheave, b.cf, "SheaveMark", V3(0.3, 1.2, 0.64), CF(10.5, b.fy + 2.6, 59.1) * CF(0, 0.9, 0), C.statusBusy, M.smooth, DETAIL)
	fx(sheave, "spin", { FxAxis = "x", FxRate = 3, FxGate = "Lift" })
	Kit.part(b.m, b.cf, "Brake", V3(1.0, 0.8, 0.8), CF(10.5, b.fy + 3.7, 62), C.metal, M.metal, DETAIL)
	Kit.part(b.m, b.cf, "HoistBeam", V3(14.25, 0.6, 0.4), CF(14.375, b.fy + 11.3, 61), C.metal, M.metal, DETAIL)
	for i, x in { 10.5, 13.5, 16.5 } do
		Kit.part(b.m, b.cf, "ControllerCabinet", V3(2.6, 7.0, 1.6), CF(x, b.fy + 3.5, 78.7), C.plasterShade, M.metal)
		Kit.part(b.m, b.cf, "CabinetLed", V3(0.4, 0.08, 0.05), CF(x - 0.7, b.fy + 6.2, 77.88), if i == 2 then C.statusBusy else C.statusGood, M.neon, DETAIL)
	end
	Kit.part(b.m, b.cf, "MainSwitch", V3(0.4, 1.4, 1.0), CF(21.3, b.fy + 4.8, 73), C.metal, M.metal, DETAIL)
	Kit.signPlate(b.m, b.cf, Kit.place(22.5, b.y, 62.2, "E"), "LIFT MACHINE ROOM", "AUTHORISED STAFF", { name = "MachineRoomSign" })
end

---------------------------------------------------------------------------------------------
-- Pavilion roof garden (level 2)
---------------------------------------------------------------------------------------------
BUILD.pavilion_roof = function(b: B)
	local s = b.seed
	local y0 = b.y
	local function slab(name: string, x1: number, x2: number, z1: number, z2: number, h: number, color: Color3, mat: Enum.Material)
		Kit.part(b.m, b.cf, name, V3(x2 - x1, h, z2 - z1), CF((x1 + x2) / 2, y0 + h / 2, (z1 + z2) / 2), color, mat)
	end
	-- paved paths from both corridor doors, a cross path and a spur to the north viewing deck
	slab("RoofPath", -49, -43, 80.5, 124, 0.2, C.stonePave, M.pave)
	slab("RoofPath", 43, 49, 80.5, 124, 0.2, C.stonePave, M.pave)
	slab("RoofPath", -43, 43, 118, 124, 0.2, C.stonePave, M.pave)
	slab("RoofPath", -3, 3, 124, 150, 0.2, C.stonePave, M.pave)
	slab("ViewingDeck", -9, 9, 150, 158.5, 0.25, C.oakDark, M.planks)
	slab("NodeDeck", -30, -20, 124, 132, 0.25, C.oakDark, M.planks)
	slab("NodeDeck", 20, 30, 124, 132, 0.25, C.oakDark, M.planks)
	-- extensive green roof beds (sedum / grass), low clusters
	-- (clear of the main back facade band/piers up to z 82.5 and the parapet gravel edge at ±80.8 / 158.8)
	local beds = {
		{ -80.6, -49, 82.6, 158.6 },
		{ 49, 80.6, 82.6, 158.6 },
		{ -43, 43, 82.6, 118 },
		{ -49, -30, 124, 158.6 },
		{ -30, -20, 132, 158.6 },
		{ -20, -3, 124, 150 },
		{ -20, -9, 150, 158.6 },
		{ 30, 49, 124, 158.6 },
		{ 20, 30, 132, 158.6 },
		{ 3, 20, 124, 150 },
		{ 9, 20, 150, 158.6 },
	}
	for i, r in beds do
		local leafy = i % 2 == 0
		slab("GreenRoof", r[1], r[2], r[3], r[4], 0.3, if leafy then C.foliageLight else C.grass, if leafy then M.leafy else M.grass)
		local area = (r[2] - r[1]) * (r[4] - r[3])
		for k = 1, math.clamp(math.floor(area / 500), 1, 4) do
			local x = Kit.range(s + i, k, r[1] + 2, r[2] - 2)
			local z = Kit.range(s + i, k + 10, r[3] + 2, r[4] - 2)
			local d = Kit.range(s + i, k + 20, 1.6, 2.8)
			Kit.ball(b.m, b.cf, "Sedum", d, CF(x, y0 + 0.3 + d * 0.15, z), Kit.pick({ C.foliage, C.sage, C.terracotta, C.foliageLight }, s + i * 7 + k), M.leafy, DETAIL)
		end
	end
	-- seating: benches on the two node decks (with planters) and on the viewing deck
	local fd = y0 + 0.25
	for side = -1, 1, 2 do
		Kit.bench(b.m, b.cf, Kit.place(side * 25, fd, 130.6, "S"), 4, s + 40 + side)
		Kit.plant(b.m, b.cf, CF(side * 21.4, fd, 130.6), "l", s + 43 + side)
		Kit.plant(b.m, b.cf, CF(side * 28.6, fd, 130.6), "l", s + 46 + side)
	end
	local view: { Seat } = {}
	for i, x in { -4.5, 4.5 } do
		local seats = Kit.bench(b.m, b.cf, Kit.place(x, fd, 155.2, "N"), 6, s + 50 + i)
		table.insert(view, seats[1])
	end
	lounge(b, view[1], 1, "roof", V3(-4.5, 0, 152.4))
	lounge(b, view[2], 2, "roof", V3(4.5, 0, 152.4))
end

---------------------------------------------------------------------------------------------
-- Entry
---------------------------------------------------------------------------------------------
function Pavilion.build(ctx: any)
	local cf: CFrame = ctx.cf
	for _, room in Plan.rooms(ctx.tier) do
		local fn = BUILD[room.kind]
		if not fn then
			continue
		end
		local y = Plan.levelY(room.level)
		local b: B = {
			ctx = ctx,
			cf = cf,
			room = room,
			m = roomModel(ctx, room),
			y = y,
			fy = if room.outdoor then y else y + Kit.FINISH,
			owner = ctx.owner,
			accent = ctx.accent,
			seed = Kit.hash(room.id) + room.style,
		}
		-- one broken room must not leave the rest of the pavilion unfurnished
		local ok, err = pcall(fn :: (B) -> any, b)
		if not ok then
			warn(`[RoomKitsPavilion] {room.id} failed: {err}`)
		end
	end
end

return Pavilion
