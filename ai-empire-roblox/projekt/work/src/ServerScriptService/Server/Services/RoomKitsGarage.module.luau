--!strict
-- RoomKitsGarage: furniture, work stations and activities of the garage stage (plan tier 0) - the
-- converted garage where the founder starts with the first team. Runs after InteriorDesign (room
-- models, the WC / founder-corner walls and their doors, floors, ceilings, cameras) and the exterior
-- (shell, garage door, porch canopy, sign, car spot). Everything sits INSIDE ctx.rooms[id].
--
-- Garage lab (Plan.GARAGE_LAB x 60..112, z -118..-78): server corner with the GPU blades (lit per owned
-- GPU by PlotService), tea kitchen with the coffee machine, meeting table, whiteboard, data wall, five
-- team desks in two rows, workbench with a 3D printer, sofa corner, the assistant's desk by the side
-- door (G0_ASSIST), the glazed founder corner (G0_FOUNDER, founder-only desk) and the WC. Applicants
-- wait on the porch benches outside (G0_PORCH, Waiting activities, public).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Plan = require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Departments = require(ReplicatedStorage.Shared.Config.DepartmentConfig)
local A = require(ReplicatedStorage.Shared.Config.ArchPalette)
local Kit = require(script.Parent.ArchKit)

local C, M = A.color, A.material
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local DETAIL: Kit.Opts = { detail = true }
local Y = Kit.FINISH -- finished floor (level 0)

local Garage = {}

type Ctx = { office: Model, cf: CFrame, tier: number, owner: number, accent: Color3, company: string, folders: { [string]: Instance }, rooms: { [string]: Model } }

local function fit(ctx: Ctx, id: string): Model
	local room = ctx.rooms[id]
	if not room then
		local r = Plan.room(ctx.tier, id)
		local created = Kit.model(ctx.folders.Rooms, id, true)
		created:SetAttribute("RoomId", id)
		if r then
			created:SetAttribute("RoomName", r.name)
			created:SetAttribute("RoomKind", r.kind)
			created:SetAttribute("Level", r.level)
			created:SetAttribute("AccessClass", r.access)
		end
		ctx.rooms[id] = created
		room = created
	end
	return Kit.model(room :: Model, "FitOut")
end

local function deptInfo(dept: string): (string, string?, string, string)
	if dept == "executive" then
		return "empire", nil, "any", "founder"
	end
	local d = (Departments.DEPARTMENTS :: any)[dept]
	if d then
		return d.app or "market", d.section, d.role or "any", d.screen or dept
	end
	return "market", nil, "any", dept
end

-- Computer work station (contract SPEC §5) with the department's app prompt and screen.
local function desk(ctx: Ctx, parent: Model, id: string, dept: string, at: CFrame, variant: string, access: string, room: string): Model
	local app, section, role, screen = deptInfo(dept)
	local m = Kit.station(parent, ctx.cf, id, dept, role, at, 0, variant, ctx.owner, ctx.accent, app, section, access, room)
	local disp = m:FindFirstChild("DisplayContent")
	if disp then
		disp:SetAttribute("LiveScreen", screen)
	end
	return m
end

-- Activity point at building-local (x, z), facing (fx, fz).
local function activity(ctx: Ctx, parent: Model, id: string, kind: string, dept: string, x: number, z: number, fx: number, fz: number, access: string, room: string, seat: Seat?, extra: { [string]: any }?): Model
	local p = V3(x, Y + 2.8, z)
	local f = V3(fx, Y + 2.8, fz)
	return Kit.activity(parent, ctx.cf, id, kind, dept, if kind == "Service" then "support" else "any", Kit.facing(p, f), 0, ctx.owner, seat, {
		roomAccess = access,
		homeRoom = room,
		facing = f,
		meetingRoom = extra and extra.meetingRoom,
		attributes = extra and extra.attributes,
	})
end

-- Seat activity: stand `d` studs in front of the seat (the sitter's view direction), face the seat.
local function seatActivity(ctx: Ctx, parent: Model, id: string, kind: string, dept: string, seat: Seat, d: number, access: string, room: string, extra: { [string]: any }?): Model
	local lp = ctx.cf:ToObjectSpace(seat.CFrame)
	local front = lp.LookVector
	local p = lp.Position + V3(front.X, 0, front.Z).Unit * d
	return activity(ctx, parent, id, kind, dept, p.X, p.Z, lp.Position.X, lp.Position.Z, access, room, seat, extra)
end

---------------------------------------------------------------------------------------------
-- Garage lab
---------------------------------------------------------------------------------------------
-- Mini GPU rack: one cabinet with stacked blade units. Each RackBlade goes into Office.Blades
-- (PlotService lights one per owned GPU; the lit blades breathe while the company trains).
local function gpuRack(ctx: Ctx, m: Model, at: CFrame, stationId: string)
	local n = Plan.GARAGE_STAGE.blades
	Kit.part(m, ctx.cf, "GarageRack", V3(2.6, 7.0, 2.4), at * CF(0, 3.5, -1.2), C.screen, M.metal)
	Kit.part(m, ctx.cf, "RackTop", V3(2.7, 0.15, 2.5), at * CF(0, 7.07, -1.2), C.metal, M.metal, DETAIL)
	local blades = ctx.folders.Blades
	for i = 1, n do
		local blade = Kit.part(blades, ctx.cf, "RackBlade", V3(2.0, 0.6, 0.08), at * CF(0, 1.0 + (i - 1) * 0.85, -2.44), A.department.compute, M.metal, DETAIL)
		blade:SetAttribute("RackIndex", i)
		blade:SetAttribute("RackVariant", "gpu")
		Kit.fx(blade, "breathe", { FxGate = "Training" })
	end
	local door = Kit.part(m, ctx.cf, "RackDoor", V3(2.6, 6.8, 0.08), at * CF(0, 3.5, -2.52), C.metal, M.metal, { detail = true, transparency = 0.45 })
	Kit.fx(door, "hinge", { FxAxis = "y", FxTravel = 1.6, FxHinge = V3(-1.3, 0, 0), FxStation = stationId })
	-- network switch and a small UPS on a shelf beside the rack
	Kit.part(m, ctx.cf, "NetShelf", V3(2.2, 0.15, 1.6), at * CF(2.6, 3.6, -0.8), C.metalSoft, M.metal)
	local switch = Kit.part(m, ctx.cf, "NetworkSwitch", V3(2.0, 0.35, 1.2), at * CF(2.6, 3.86, -0.8), C.screen, M.metal, DETAIL)
	Kit.fx(switch, "blink", { FxColor = C.statusGood, FxRate = 1.5, FxIdle = "on" })
	Kit.part(m, ctx.cf, "UPSBox", V3(1.4, 2.2, 1.6), at * CF(2.6, 1.1, -0.8), C.metalSoft, M.metal)
end

local function furnishLab(ctx: Ctx)
	local m = fit(ctx, "G0_LAB")
	local cf = ctx.cf
	local seed = Kit.hash("G0_LAB")
	local ACC, ROOM = "staff", "G0_LAB"

	-- server corner on the north wall (engineers inspect the rack: ServerRack activity)
	local rackAt = Kit.place(77, Y, -78, "S")
	activity(ctx, m, "G0_LAB_Rack1", "ServerRack", "compute", 77, -82.6, 77, -78, ACC, ROOM)
	gpuRack(ctx, m, rackAt, "G0_LAB_Rack1")

	-- tea kitchen with the coffee machine (PantryCoffee: WorkstationService brews here)
	local kitchen = Kit.kitchenette(m, cf, Kit.place(84, Y, -78, "S"), 10, seed + 1)
	local coffee = cf:PointToObjectSpace(kitchen.coffee.Position)
	for i, x in { coffee.X - 0.9, coffee.X + 1.2 } do
		activity(ctx, m, "G0_LAB_Coffee" .. i, "Coffee", "kitchen", x, -82.4, coffee.X, coffee.Z, ACC, ROOM)
	end
	Kit.cylinder(m, cf, "PizzaBox", "y", 0.35, 2.4, CF(81.2, Y + 3.33, -79.2), C.white, M.smooth, DETAIL)

	-- whiteboard on the WC's east wall (roadmap of a startup)
	Kit.whiteboard(m, cf, Kit.place(69.5, Y, -83, "E"), 5, "ROADMAP\n1  first model\n2  first customers\n3  hire the team\n4  move into the HQ", seed + 2, { y = 5.2 })
	activity(ctx, m, "G0_LAB_Board", "Whiteboard", "research", 72.6, -83, 69.5, -83, ACC, ROOM)

	-- meeting table (model reviews, stand-ups)
	local tableAt = CF(84, Y, -89.5)
	Kit.meetingTable(m, cf, tableAt, "round", 4.6, nil, seed + 3)
	for i, a in { 0, 90, 180, 270 } do
		local r = math.rad(a)
		local ox, oz = math.sin(r), -math.cos(r) -- outward from the table centre
		local cx, cz = 84 + ox * 3.4, -89.5 + oz * 3.4
		local seat = Kit.meetingChair(m, cf, Kit.facing(V3(cx, Y, cz), V3(84, Y, -89.5)), seed + 10 + i)
		-- stand behind the chair, a little to its side (like the HQ meeting rooms)
		local sx, sz = -oz, ox
		activity(ctx, m, "G0_LAB_Meet" .. i, "Meeting", "evaluation", cx + ox * 1.6 + sx * 1.7, cz + oz * 1.6 + sz * 1.7, 84, -89.5, ACC, ROOM, seat, { meetingRoom = "GarageTable" })
	end
	Kit.part(m, cf, "Laptop", V3(2.0, 0.1, 1.4), CF(83.4, Y + 3.2, -88.8) * ANG(0, 0.3, 0), C.metalSoft, M.metal, DETAIL)

	-- data wall on the west wall (curators watch the pipeline here)
	Kit.tvScreen(m, cf, Kit.place(60, Y, -96, "E"), 7, "data", ctx.accent, { y = 6.2, name = "DataWall" })
	activity(ctx, m, "G0_LAB_Pipeline", "Pipeline", "data", 63.4, -96, 60, -96, ACC, ROOM)

	-- five team desks in two rows (founder desk: founder corner; assistant: G0_ASSIST)
	local deskX = { 68, 76, 84, 72, 80 } -- row 1 (users face north), row 2 (users face south)
	local deskDept = { "data", "engineering", "research", "growth", "training" }
	for n = 1, 5 do
		local row1 = n <= 3
		desk(ctx, m, "G0_LAB_Desk" .. n, deskDept[n], Kit.place(deskX[n], Y, if row1 then -106 else -102, if row1 then "S" else "N"), "bench", ACC, ROOM)
	end

	-- workbench with a 3D printer on the east wall (researchers run experiments here)
	Kit.workbench(m, cf, Kit.place(112, Y, -102, "W"), 10, seed + 4)
	Kit.printer3d(m, cf, Kit.place(110.6, Y + 3.2, -99.4, "W"), seed + 5, { propId = "GaragePrinter", prompt = "3D printer", station = "G0_LAB_Bench" })
	Kit.part(m, cf, "PrototypeBoard", V3(1.6, 0.15, 1.2), CF(110.4, Y + 3.28, -104.6), C.sage, M.smooth, DETAIL)
	activity(ctx, m, "G0_LAB_Bench", "LabBench", "research", 107.4, -102, 112, -102, ACC, ROOM)
	for k = 0, 1 do
		Kit.part(m, cf, "HardwareCrate", V3(2.4, 1.8, 1.8), CF(110.6, Y + 0.9 + k * 1.8, -95.4), if k == 0 then C.oakLight else C.oak, M.wood)
	end

	-- table tennis inside the up-and-over door (the garage startup's break corner), 4.5 studs clear of
	-- the door and of the workbench station
	local tt = CF(101, Y, -110)
	Kit.part(m, cf, "PingPongTop", V3(9, 0.25, 5), tt * CF(0, 2.6, 0), C.sage, M.smooth)
	Kit.part(m, cf, "PingPongLine", V3(9, 0.02, 0.08), tt * CF(0, 2.735, 0), C.white, M.smooth, DETAIL)
	Kit.part(m, cf, "PingPongNet", V3(0.06, 0.5, 5.4), tt * CF(0, 2.98, 0), C.white, M.fabric, { detail = true, transparency = 0.3 })
	for _, dx in { -3.6, 3.6 } do
		Kit.part(m, cf, "PingPongFrame", V3(0.25, 2.45, 4.2), tt * CF(dx, 1.225, 0), C.metal, M.metal)
	end
	for k, dx in { -2.2, 2.6 } do
		Kit.cylinder(m, cf, "Paddle", "y", 0.06, 0.9, tt * CF(dx, 2.76, (k - 1.5) * 2.4), if k == 1 then C.statusBad else C.screen, M.smooth, DETAIL)
	end
	Kit.ball(m, cf, "PingPongBall", 0.2, tt * CF(1.1, 2.83, -0.6), C.white, M.smooth, DETAIL)

	-- sofa corner by the west window (open towards the room: 3.6 studs in front of the sofa)
	Kit.rug(m, cf, CF(66.2, Y, -114), 10, 7, seed + 6)
	local sofaSeats = Kit.sofa(m, cf, Kit.place(61.6, Y, -114, "E"), 7, seed + 7)
	for i, s in sofaSeats do
		seatActivity(ctx, m, "G0_LAB_Sofa" .. i, "Lounge", "lounge", s, 2.4, ACC, ROOM)
	end
	Kit.coffeeTable(m, cf, CF(68.4, Y, -114.4), seed + 8, 3.0, 2.2)
	Kit.floorLamp(m, cf, CF(61.4, Y, -117.0), seed + 10)
	Kit.plant(m, cf, CF(61.6, Y, -102.6), "l", seed + 11)

	-- shelf with books and boxes between the kitchen and the founder corner
	Kit.bookshelf(m, cf, Kit.place(93.5, Y, -78, "S"), 7, 8, seed + 12, { books = 3 })
	-- string lights along the north wall (Neon bulbs, no light objects)
	for k = 0, 7 do
		Kit.ball(m, cf, "StringLight", 0.35, CF(62 + k * 4.5, Y + 11.6 - (k % 2) * 0.3, -78.6), C.lightWarm, M.neon, DETAIL)
	end
	Kit.plant(m, cf, CF(91.2, Y, -116.4), "m", seed + 13)
end

local function furnishAssistant(ctx: Ctx)
	local m = fit(ctx, "G0_ASSIST")
	-- the assistant's desk faces the side door (role assistant: founder clearance, staff can't sit here)
	desk(ctx, m, "G0_ASSIST_Desk1", "operations", Kit.place(88, Y, -113, "E"), "bench", "founder", "G0_ASSIST")
	Kit.plant(m, ctx.cf, CF(84.2, Y, -116.6), "s", Kit.hash("G0_ASSIST"))
end

local function furnishFounder(ctx: Ctx)
	local m = fit(ctx, "G0_FOUNDER")
	local cf = ctx.cf
	local seed = Kit.hash("G0_FOUNDER")
	local deskAt = Kit.place(106, Y, -86, "E")
	local d = desk(ctx, m, "G0_FOUNDER_Desk1", "executive", deskAt, "ldesk", "founder", "G0_FOUNDER")
	d:SetAttribute("Role", "founder") -- the founder's own desk: no employee takes it
	local term = Kit.part(m, cf, "FounderTerminal", V3(1.8, 1.2, 0.15), deskAt * CF(-2.4, 3.8, 0.9) * ANG(0, math.rad(-15), 0), C.screen, M.smooth, { canCollide = false })
	Kit.action(term, "ownerComputer", "Founder computer · whole company", "empire", { ownerOnly = true, actionText = "Open", maxDistance = 8 })
	local tablet = Kit.part(m, cf, "FounderCameraTablet", V3(1.2, 0.08, 1.6), deskAt * CF(2.3, 3.2, -0.3) * ANG(0, math.rad(20), 0), C.metal, M.smooth, { canCollide = false })
	Kit.action(tablet, "security", "Security cameras", nil, { ownerOnly = true, actionText = "View", maxDistance = 8 })
	Kit.sideboard(m, cf, Kit.place(105, Y, -78, "S"), 6, seed + 1)
	Kit.loungeChair(m, cf, Kit.place(100.4, Y, -80.4, -135), seed + 2)
	Kit.plant(m, cf, CF(110.6, Y, -79.6), "m", seed + 3)
	Kit.rug(m, cf, CF(105, Y, -86), 8, 7, seed + 4)
end

local function furnishWc(ctx: Ctx)
	local m = fit(ctx, "G0_WC")
	local cf = ctx.cf
	local key = "G0_WC_T"
	-- toilet against the west wall, basin with mirror on the north wall (FixtureKey contract)
	local base = Kit.place(60, Y, -81.5, "E")
	Kit.part(m, cf, "ToiletBowl", V3(1.5, 1.4, 2.2), base * CF(0, 0.7, -1.3), C.white, M.smooth)
	Kit.part(m, cf, "ToiletTank", V3(1.9, 2.2, 0.7), base * CF(0, 2.4, -0.35), C.white, M.smooth)
	local seat = Kit.seat(m, cf, "ToiletSeat", V3(1.5, 0.2, 1.8), base * CF(0, 1.5, -1.4), C.white, M.smooth, { canTouch = false })
	seat.Disabled = true
	seat:SetAttribute("FixtureKey", key)
	Kit.action(seat, "toilet", "Toilet", nil, { actionText = "Use", maxDistance = 6 })
	local flush = Kit.part(m, cf, "FlushButton", V3(0.6, 0.35, 0.08), base * CF(0, 3.0, -0.74), C.metalSoft, M.metal, { canCollide = false, canTouch = false })
	flush:SetAttribute("FixtureKey", key)
	Kit.action(flush, "flush", "Flush", nil, { actionText = "Flush", maxDistance = 6 })
	local water = Kit.part(m, cf, "ToiletWater", V3(1.0, 0.05, 1.2), base * CF(0, 1.32, -1.45), C.water, M.smooth, { detail = true, transparency = 0.25 })
	water:SetAttribute("FixtureKey", key)
	Kit.fx(water, "flow", { FxAxis = "y", FxTravel = -0.3, FxRate = 3, FxSeconds = 2 })
	local wall = Kit.place(65.5, Y, -78, "S")
	Kit.part(m, cf, "VanityTop", V3(3.6, 0.25, 1.8), wall * CF(0, 2.85, -0.9), C.stone, M.marble)
	Kit.part(m, cf, "Basin", V3(1.6, 0.35, 1.3), wall * CF(0, 3.1, -0.95), C.white, M.smooth)
	local tap = Kit.part(m, cf, "Tap", V3(0.2, 0.7, 0.5), wall * CF(0, 3.55, -0.35), C.metalSoft, M.metal, { canCollide = false })
	tap:SetAttribute("FixtureKey", "G0_WC_B")
	Kit.action(tap, "tap", "Tap", nil, { actionText = "Wash hands", maxDistance = 6 })
	local tapWater = Kit.part(m, cf, "TapWater", V3(0.15, 0.55, 0.15), wall * CF(0, 3.25, -0.6), C.water, M.smooth, { detail = true, transparency = 1 })
	tapWater:SetAttribute("FixtureKey", "G0_WC_B")
	tapWater:SetAttribute("FxShow", 0.5)
	Kit.fx(tapWater, "flow", { FxSeconds = 6 })
	Kit.part(m, cf, "Mirror", V3(3.2, 3.2, 0.08), wall * CF(0, 5.6, -0.05), C.glassDeep, M.glass, { detail = true, reflectance = 0.25 })
end

local function furnishPorch(ctx: Ctx)
	local m = fit(ctx, "G0_PORCH")
	local cf = ctx.cf
	local seed = Kit.hash("G0_PORCH")
	local y = 0.12 -- porch paving
	-- two benches against the facade: applicants wait here for their interview (Waiting activities,
	-- public; staff never use them)
	local k = 0
	for i, x in { 69, 86.5 } do
		local seats = Kit.bench(m, cf, Kit.place(x, y, -120.4, "S"), 6, seed + i)
		for _, s in seats do
			k += 1
			local lp = cf:ToObjectSpace(s.CFrame).Position
			Kit.activity(m, cf, "G0_PORCH_Wait" .. k, "Waiting", "visitor", "any", Kit.facing(V3(lp.X, y + 2.8, -122.4), V3(lp.X, y + 2.8, -130)), 0, ctx.owner, s, {
				roomAccess = "public",
				homeRoom = "G0_PORCH",
				facing = V3(lp.X, y + 2.8, -130),
			})
		end
	end
	for i, x in { 73.2, 80.8 } do
		Kit.plant(m, cf, CF(x, y, -120.6), "m", seed + 10 + i)
	end
	Kit.part(m, cf, "Doormat", V3(4.4, 0.05, 2.2), CF(77, y + 0.025, -120.4), C.fabricCharcoal, M.fabric, DETAIL)
end

function Garage.build(ctx: any)
	if ctx.tier >= 1 then
		return
	end
	for _, step in { furnishLab, furnishAssistant, furnishFounder, furnishWc, furnishPorch } do
		local ok, err = pcall(function(): any
			step(ctx :: Ctx)
			return nil
		end)
		if not ok then
			warn(`[RoomKitsGarage] {err}`)
		end
	end
end

return Garage
