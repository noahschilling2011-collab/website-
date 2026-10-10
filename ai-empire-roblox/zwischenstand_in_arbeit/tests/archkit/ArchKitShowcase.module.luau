--!strict
-- Throwaway ArchKit showcase for the offline harness (NOT part of the game).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Plan = require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Kit = require(script.Parent.ArchKit)
local C = Kit.C
local V3 = Vector3.new
local S = {}

local function def(id: string, kind: string, axis: string, x: number, z: number, w: number, h: number, inward: Vector3, access: string?, extra: { [string]: any }?): any
	local d: any = { id = id, level = 0, room = "T_" .. id, kind = kind, access = access or "staff", axis = axis, x = x, z = z, w = w, h = h, inward = inward, exterior = false, hidden = kind == "flush" or kind == "bookcase", builder = "interior" }
	if extra then
		for k, v in extra do
			d[k] = v
		end
	end
	return d
end

local function seg(axis: string, c: number, a1: number, a2: number, finish: string, height: number, defs: { any }): any
	local openings = {}
	for _, d in defs do
		local da = if axis == "x" then d.x else d.z
		table.insert(openings, { a1 = da - d.w / 2, a2 = da + d.w / 2, door = d })
	end
	table.sort(openings, function(a, b)
		return a.a1 < b.a1
	end)
	return { level = 0, axis = axis, c = c, a1 = a1, a2 = a2, finish = finish, height = height, openings = openings }
end

function S.build(cf: CFrame, session: any, accent: Color3): Model
	Kit.resetStats()
	local office = Instance.new("Model")
	office.Name = "Office"
	local function folder(n: string): Folder
		local f = Instance.new("Folder")
		f.Name = n
		f.Parent = office
		return f
	end
	local fur, walls, doors, st, cams, blades = folder("Furniture"), folder("Walls"), folder("Doors"), folder("Stations"), folder("Cameras"), folder("Blades")
	local owner = 1001
	local Y = Kit.FINISH
	Kit.floor(fur, cf, { x1 = -110, x2 = 110, z1 = -110, z2 = 120 }, 0, "concrete", { inset = 0 })
	local counts: { [string]: number } = {}
	local function measure(name: string, fn: () -> ())
		local before = Kit.stats.parts
		fn()
		counts[name] = Kit.stats.parts - before
	end

	-- free-standing row 1 (z = -80)
	local x = -100
	local function nextX(step: number): number
		local v = x
		x += step
		return v
	end
	measure("officeChair", function() Kit.officeChair(fur, cf, CFrame.new(nextX(5), Y, -80), 1) end)
	measure("officeChair(arms)", function() Kit.officeChair(fur, cf, CFrame.new(nextX(5), Y, -80), 2, { arms = true }) end)
	measure("officeChair(lite)", function() Kit.officeChair(fur, cf, CFrame.new(nextX(5), Y, -80), 3, { lite = true }) end)
	measure("meetingChair", function() Kit.meetingChair(fur, cf, CFrame.new(nextX(5), Y, -80), 4) end)
	measure("loungeChair", function() Kit.loungeChair(fur, cf, CFrame.new(nextX(6), Y, -80), 5) end)
	measure("sofa(7)", function() Kit.sofa(fur, cf, CFrame.new(nextX(10), Y, -80), 7, 6) end)
	measure("stool", function() Kit.stool(fur, cf, CFrame.new(nextX(5), Y, -80), 7) end)
	measure("bench(6)", function() Kit.bench(fur, cf, CFrame.new(nextX(9), Y, -80), 6, 8) end)
	measure("coffeeTable(rect)", function() Kit.coffeeTable(fur, cf, CFrame.new(nextX(7), Y, -80), 2) end)
	measure("coffeeTable(round)", function() Kit.coffeeTable(fur, cf, CFrame.new(nextX(7), Y, -80), 1) end)
	measure("meetingTable(rect)", function()
		local tx = nextX(16)
		Kit.meetingTable(fur, cf, CFrame.new(tx, Y, -80), "rect", 10, 4.5, 1)
	end)
	-- chairs around the rect table (face the table)
	for i, cx in { -3, 0, 3 } do
		Kit.meetingChair(fur, cf, Kit.place(-100 + 5 * 5 + 6 + 10 + 7 + 7 + 9 + cx, Y, -80 - 3.4, "N"), i)
		Kit.meetingChair(fur, cf, Kit.place(-100 + 5 * 5 + 6 + 10 + 7 + 7 + 9 + cx, Y, -80 + 3.4, "S"), i + 3)
	end
	measure("meetingTable(round)", function() Kit.meetingTable(fur, cf, CFrame.new(nextX(10), Y, -80), "round", 6, 6, 2) end)
	measure("meetingTable(boat)", function() Kit.meetingTable(fur, cf, CFrame.new(nextX(18), Y, -80), "boat", 14, 5, 3) end)
	measure("desk(bench)", function() Kit.desk(fur, cf, CFrame.new(nextX(10), Y, -80), "bench", 1) end)

	-- free-standing row 2 (z = -55)
	x = -100
	measure("plant(s)", function() Kit.plant(fur, cf, CFrame.new(nextX(4), Y, -55), "s", 1) end)
	measure("plant(m)", function() Kit.plant(fur, cf, CFrame.new(nextX(5), Y, -55), "m", 2) end)
	measure("plant(l)", function() Kit.plant(fur, cf, CFrame.new(nextX(6), Y, -55), "l", 3) end)
	measure("plant(tree)", function() Kit.plant(fur, cf, CFrame.new(nextX(8), Y, -55), "tree", 4) end)
	measure("plant(xl)", function() Kit.plant(fur, cf, CFrame.new(nextX(11), Y, -55), "xl", 5) end)
	measure("planter(6x2.4)", function() Kit.planter(fur, cf, CFrame.new(nextX(9), Y, -55), 6, 2.4, 1) end)
	measure("rug(8x6)", function() Kit.rug(fur, cf, CFrame.new(nextX(10), Y, -55), 8, 6, 1) end)
	measure("floorLamp(a)", function() Kit.floorLamp(fur, cf, CFrame.new(nextX(4), Y, -55), 2) end)
	measure("floorLamp(b)", function() Kit.floorLamp(fur, cf, CFrame.new(nextX(5), Y, -55), 1) end)
	measure("pendant", function() Kit.pendant(fur, cf, CFrame.new(nextX(5), 13, -55), "warm") end)
	measure("phoneBooth", function() Kit.phoneBooth(fur, cf, CFrame.new(nextX(8), Y, -55), "Booth1", owner) end)
	measure("counter(8)", function() Kit.counter(fur, cf, CFrame.new(nextX(11), Y, -55), 8, 1) end)
	measure("receptionDesk(10)", function() Kit.receptionDesk(fur, cf, CFrame.new(nextX(13), Y, -55), 10, 1) end)
	measure("serverRack(compute)", function() Kit.serverRack(fur, cf, CFrame.new(nextX(4), Y, -55), 1, blades, { index = 1 }) end)
	measure("serverRack(gpu)", function() Kit.serverRack(fur, cf, CFrame.new(nextX(4), Y, -55), 2, blades, { variant = "gpu", index = 2, accent = accent }) end)
	measure("serverRack(network,tray)", function() Kit.serverRack(fur, cf, CFrame.new(nextX(5), Y, -55), 3, blades, { variant = "network", index = 3, trayY = 10 }) end)
	measure("shelfRack(8)", function() Kit.shelfRack(fur, cf, CFrame.new(nextX(11), Y, -55), 8, 1) end)
	measure("camera", function() Kit.camera(cams, cf, "T1", "Test cam", V3(nextX(4), 12, -55), V3(-60, 0, -70), 0, "T", false) end)

	-- backdrop wall for wall units (surface at z = -40.25, items face -Z)
	Kit.part(fur, cf, "Backdrop", V3(220, 15, 0.5), CFrame.new(0, 7.5, -40), C.interior, Kit.M.plaster)
	x = -104
	local function wallAt(step: number): CFrame
		local v = x + step / 2
		x += step
		return Kit.place(v, Y, -40.25, "S")
	end
	measure("sideboard(6)", function() Kit.sideboard(fur, cf, wallAt(8), 6, 1) end)
	measure("cabinet(3x6.5)", function() Kit.cabinet(fur, cf, wallAt(5), 3, 6.5, 1) end)
	measure("lockers(6)", function() Kit.lockers(fur, cf, wallAt(11), 6, 1) end)
	measure("bookshelf(6x8)", function() Kit.bookshelf(fur, cf, wallAt(8), 6, 8, 1) end)
	measure("rackShelf(4)", function() Kit.rackShelf(fur, cf, wallAt(6), 4, 1) end)
	measure("whiteboard(6)", function() Kit.whiteboard(fur, cf, wallAt(8), 6, "Q3 roadmap\n- eval suite\n- launch", 1) end)
	measure("pinboard(4x3)", function() Kit.pinboard(fur, cf, wallAt(6), 4, 3, 1) end)
	measure("tvScreen(6)", function() Kit.tvScreen(fur, cf, wallAt(8), 6, "lobby", accent) end)
	measure("artwork(4x3)", function() Kit.artwork(fur, cf, wallAt(6), 4, 3, 7) end)
	measure("acousticPanels(6x3)", function() Kit.acousticPanels(fur, cf, wallAt(8), 6, 3, 1) end)
	measure("signPlate", function() Kit.signPlate(fur, cf, wallAt(4), "Training Control", "Company card") end)
	measure("wayfinding(5 lines)", function() Kit.wayfinding(fur, cf, wallAt(6), { "2 · AI engineering", "← Training Control", "← Evaluation Lab", "Model Review →", "Tea Kitchen →" }) end)
	measure("toolWall(5)", function() Kit.toolWall(fur, cf, wallAt(7), 5, 1) end)
	measure("kitchenette(10)", function() Kit.kitchenette(fur, cf, wallAt(12), 10, 1) end)
	measure("workbench(6)", function() Kit.workbench(fur, cf, wallAt(8), 6, 1) end)

	-- stations row (z = -20): desks face +Z, chairs at -Z
	x = -96
	for i, v in Kit.DESK_VARIANTS do
		measure("station(" .. v .. ")", function()
			Kit.station(st, cf, "WS_" .. v, if v == "trading" then "training" else "engineering", "engineer", CFrame.new(x, Y, -20), 0, v, owner, accent, "lab", nil, "staff", "T")
		end)
		x += 16
	end
	measure("station(rotated E)", function()
		Kit.station(st, cf, "WS_rot", "data", "curator", Kit.place(x, Y, -20, "W"), 0, 1, owner, accent, "data")
	end)

	-- walls with doors (z = 10: solid, panel), (z = 40: glass + fence), (z = 70: barrier + extras)
	local north = V3(0, 0, 1)
	local south = V3(0, 0, -1)
	measure("wall(solid) + doors", function()
		Kit.wall(walls, cf, seg("x", 10, -104, 30, "solid", 15, {
			def("GLASS", "glass", "x", -96, 10, 6, 9, north),
			def("GLASSDBL", "glassdouble", "x", -84, 10, 8, 10, north),
			def("SOLID", "solid", "x", -72, 10, 6, 9, north),
			def("SECURE", "secure", "x", -60, 10, 6, 9, north),
			def("SERVICE", "service", "x", -48, 10, 6, 9, south),
			def("SERVICE10", "service", "x", -34, 10, 10, 9, north),
			def("VAULT", "vault", "x", -20, 10, 6, 9, north),
			def("AUTO", "autoslide", "x", -6, 10, 8, 10, north, "public"),
			def("CUBICLE", "cubicle", "x", 5, 10, 2.6, 7.2, north),
			def("OPEN", "opening", "x", 18, 10, 8, 9, north),
		}), 0, owner, doors)
	end)
	measure("wall(panel) + flush/bookcase", function()
		Kit.wall(walls, cf, seg("x", 10, 30, 104, "panel", 15, {
			def("FLUSH", "flush", "x", 45, 10, 6, 9, north, "founder"),
			def("BOOK", "bookcase", "x", 62, 10, 7, 9, south, "founder"),
			def("WCDOOR", "solid", "x", 80, 10, 5, 9, north),
			def("OPEN2", "opening", "x", 95, 10, 6, 9, north),
		}), 0, owner, doors)
	end)
	measure("wall(glass) + doors", function()
		Kit.wall(walls, cf, seg("x", 40, -104, 0, "glass", 15, {
			def("G_GLASS", "glass", "x", -90, 40, 6, 9, north),
			def("G_DBL", "glassdouble", "x", -70, 40, 8, 10, north),
			def("G_OPEN", "opening", "x", -50, 40, 8, 9, north),
			def("G_SEC", "secure", "x", -30, 40, 6, 9, north),
		}), 0, owner, doors)
	end)
	measure("wall(fence) + gate", function()
		Kit.wall(walls, cf, seg("x", 40, 10, 70, "fence", 6, {
			def("F_GATE", "service", "x", 40, 40, 6, 9, north, "technical"),
		}), 0, owner, doors)
	end)
	measure("wall(barrier) + 5 speedgates", function()
		local list = {}
		for i, p in { { -14, 4.5 }, { -6.75, 3 }, { -2.25, 3 }, { 2.25, 3 }, { 6.75, 3 } } do
			table.insert(list, def("SG" .. i, "speedgate", "x", p[1], 70, p[2], 9, north))
		end
		Kit.wall(walls, cf, seg("x", 70, -22, 22, "barrier", 3.6, list), 0, owner, doors)
	end)
	measure("wall(solid, z-axis) + door", function()
		Kit.wall(walls, cf, seg("z", 50, 60, 100, "solid", 15, {
			def("ZDOOR", "solid", "z", 50, 80, 6, 9, V3(-1, 0, 0)),
			def("STAIR_OUT", "solid", "z", 50, 92, 6, 9, V3(-1, 0, 0), "staff", { swing = "out" }),
			def("EXT_GLASS", "glass", "z", 50, 68, 5, 9, V3(-1, 0, 0), "staff", { exterior = true }),
		}), 0, owner, doors)
	end)
	measure("door(fridge)", function()
		Kit.door(doors, cf, def("G_FRIDGE", "fridge", "x", 80, 70, 3, 6.4, north), owner)
	end)
	measure("door(gate barrier)", function()
		Kit.door(doors, cf, def("BARRIER", "gate", "x", 80, 100, 8, 4.5, north, "staff", { variant = "barrier" }), owner)
	end)

	-- ceilings over a test room
	measure("ceiling(acoustic 20x16)", function() Kit.ceiling(fur, cf, { x1 = -100, x2 = -80, z1 = 80, z2 = 96 }, 0, "acoustic", "neutral") end)
	measure("ceiling(timber 20x16)", function() Kit.ceiling(fur, cf, { x1 = -76, x2 = -56, z1 = 80, z2 = 96 }, 0, "timber", "founder") end)
	measure("ceiling(plaster 20x16)", function() Kit.ceiling(fur, cf, { x1 = -52, x2 = -32, z1 = 80, z2 = 96 }, 0, "plaster", "warm") end)
	measure("accessVolume", function()
		Kit.accessVolume(fur, cf, (Plan.room(4, "G_COMPUTE") :: any))
	end)

	local names = {}
	for k in counts do
		table.insert(names, k)
	end
	table.sort(names)
	for _, k in names do
		print(string.format("[count] %-32s %d", k, counts[k]))
	end
	print(string.format("[count] TOTAL parts %d lights %d", Kit.stats.parts, Kit.stats.lights))
	return office
end

return S
