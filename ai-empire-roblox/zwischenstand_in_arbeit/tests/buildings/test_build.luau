--!nocheck
-- Package "buildings" · build contracts on the REAL generators and services (no doubles):
--   tier 0  garage stage: rooms, no lift / basement / data hall / ramp, roll-up door on the CampusDoor
--           contract (DoorService opens and closes it), SignAnchor with the company name, car spot,
--           construction site with the site board, LiftService treats the building as liftless
--   tier 1  no guest house (byte-identical HQ is checked by agents/buildings/cmp_dumps.py)
--   tier 2+ guest house: 12 guest rooms (bed, wardrobe, TV, desk, en-suite cubicle door + fixtures),
--           reception post (OpsIndex 13) and housekeeping post (OpsIndex 14) with job points and their
--           operations staff, 20 breakfast seats, 10 workshop seats, guest access class, stair (no lift)
-- Prints part / light counts (tier 0 office, guest house = tier 2 minus tier 1 in the annex box).
-- Run: python3 tests/buildings/mkharness.py && tools/luau tests/buildings/test_build.luau [-a neg|all]
local M = require("../../harness/mock")
local args = { ... }
local NEG = args[1] == "neg"
local ALL = args[1] == "all"
if NEG then
	M.loadTree(require("./gen_negb/manifest"), require("./gen_negb/sources"))
else
	M.loadTree(require("./gen_build/manifest"), require("./gen_build/sources"))
end
M.quiet = true
local G = M.G
local say = print
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; say("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local function body()
	local Instance, Vector3, CFrame, Color3 = G.Instance, G.Vector3, G.CFrame, G.Color3
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local Services = Server.Services
	local Collection = game:GetService("CollectionService")
	local RunService = game:GetService("RunService")
	local Plan = M.require(RS.Shared.Config.BuildingPlan)
	local Layout = M.require(RS.Shared.BuildingLayout)
	local EmpireConfig = M.require(RS.Shared.Config.EmpireConfig)
	local EmpireMath = M.require(RS.Shared.EmpireMath)
	local Template = M.require(Server.Lib.Template)
	local Design = M.require(Services.HeadquartersDesign)
	local Doors = M.require(Services.DoorService)
	local Lift = M.require(Services.LiftService)
	local Nav = M.require(Services.EmployeeNavigation)
	local Rig = M.require(Services.EmployeeRigDesign)
	local OWNER = 1001
	local plots = Instance.new("Folder"); plots.Name = "Plots"; plots.Parent = G.workspace
	local players = {}
	Doors._setPlayerSource(function() return players end)
	Doors.setAuthorizer(function(player) return player.UserId == OWNER end)
	Doors.init()

	local function build(tier, n)
		local cf = CFrame.lookAt(Vector3.new(160 + n * 700, 24, 252), Vector3.new(160 + n * 700, 24, 0))
		local d = Template.new()
		d.company = { name = "Nimbus Labs", logo = "N", color = "cyan", spec = "general", reputation = 10, foundedAt = 0 }
		local cap
		if tier == 0 then
			d.empire.office = 1; cap = if Plan.GARAGE_STAGE then Plan.GARAGE_STAGE.staff else 5
		else
			d.empire.office = Plan.officeForTier(tier); cap = EmpireConfig.OFFICES[d.empire.office].staff -- econ: DATA_VERSION 6 office offset
		end
		for k, role in EmpireConfig.ROLES do d.empire.employees[role.id] = math.floor(cap / #EmpireConfig.ROLES) + (if k <= cap % #EmpireConfig.ROLES then 1 else 0) end
		EmpireMath.syncProfiles(d.empire, OWNER)
		local player = { UserId = OWNER, Name = "Founder", DisplayName = "Founder", Character = nil, FindFirstChildOfClass = function() return nil end }
		local session = { userId = OWNER, player = player, data = d, live = { users = 0, revenue = 0, cost = 0 }, closed = false, planTier = if tier == 0 then 0 else nil }
		local w0 = M.stats.warnings
		local office = Design.build(cf, session, Color3.fromRGB(120, 154, 129))
		local plot = Instance.new("Model"); plot.Name = "Plot_0" .. n; plot.Parent = plots
		office.Parent = plot
		return office, cf, M.stats.warnings - w0
	end
	local function count(root, box, cf)
		local parts, lights = 0, 0
		for _, x in root:GetDescendants() do
			local inBox = true
			if box then
				local p = if x:IsA("BasePart") then x.Position elseif x:IsA("Light") and x.Parent and x.Parent:IsA("BasePart") then x.Parent.Position else nil
				if p == nil then inBox = false else
					local lp = cf:PointToObjectSpace(p)
					inBox = lp.X >= box.x1 and lp.X <= box.x2 and lp.Z >= box.z1 and lp.Z <= box.z2
				end
			end
			if inBox then
				if x:IsA("BasePart") then parts += 1 elseif x:IsA("Light") then lights += 1 end
			end
		end
		return parts, lights
	end
	local function stations(office)
		local out = {}
		for _, m in office:GetDescendants() do
			if m:IsA("Model") and m:GetAttribute("WorkstationId") ~= nil then table.insert(out, m) end
		end
		return out
	end
	local function heartbeat(seconds)
		local t = 0
		while t < seconds - 1e-9 do M.fire(RunService.Heartbeat, 0.05); Doors.tick(0.05); t += 0.05 end
	end
	local function near(a, b, eps) return (a.Position - b.Position).Magnitude <= (eps or 0.05) and (a.LookVector - b.LookVector).Magnitude <= 0.01 end

	--------------------------------------------------------------------------------------------- tier 0
	local okT0, errT0 = pcall(function()
	local office0, cf0, warn0 = build(0, 0)
	check("t0: OfficeTier 0 + GarageStage", office0:GetAttribute("OfficeTier") == 0 and office0:GetAttribute("GarageStage") == true, office0:GetAttribute("OfficeTier"))
	check("t0: no warnings while building", warn0 == 0, warn0)
	local roomNames = {}
	for _, r in office0.Rooms:GetChildren() do roomNames[r.Name] = true end
	for _, id in { "G0_LAB", "G0_WC", "G0_FOUNDER", "G0_ASSIST", "G0_PORCH" } do check("t0: room " .. id, roomNames[id] == true) end
	local hq = 0
	for name in roomNames do if not string.match(name, "^G0_") then hq += 1 end end
	check("t0: no HQ rooms (no basement, data hall, lobby ...)", hq == 0, hq)
	local forbidden = { Lift = 0, LiftShaft = 0, HeadHouse = 0, GarageRamp = 0, StairCore = 0, CampusArcade = 0, ConstructionSite = 0 }
	for _, x in office0:GetDescendants() do if forbidden[x.Name] ~= nil then forbidden[x.Name] += 1 end end
	local liftFolder = office0:FindFirstChild("Lift")
	check("t0: no lift (empty Lift folder, no shaft, no head house)", (liftFolder == nil or #liftFolder:GetChildren() == 0) and forbidden.LiftShaft == 0 and forbidden.HeadHouse == 0, forbidden.LiftShaft)
	check("t0: no garage ramp, no HQ stair core", forbidden.GarageRamp == 0 and forbidden.StairCore == 0)
	check("t0: campus arcade kept", forbidden.CampusArcade == 1, forbidden.CampusArcade)
	check("t0: construction site", forbidden.ConstructionSite == 1, forbidden.ConstructionSite)
	local boardOk, hoardingOk = false, false
	for _, x in office0:GetDescendants() do
		if x:IsA("TextLabel") then
			if x.Text == "FUTURE HEADQUARTERS" then boardOk = true end
			if string.find(x.Text, "FUTURE HOME OF NIMBUS LABS", 1, true) then hoardingOk = true end
		end
	end
	check("t0: site board 'FUTURE HEADQUARTERS'", boardOk)
	check("t0: hoarding names the company", hoardingOk)
	local sign = office0:FindFirstChild("SignAnchor")
	local label = sign and sign:FindFirstChild("Label", true)
	check("t0: SignAnchor (direct child) with the company name", label ~= nil and label.Text == "Nimbus Labs", label and label.Text)
	if sign then
		local lp = cf0:PointToObjectSpace(sign.Position)
		check("t0: sign hangs over the garage door", lp.X > 94 and lp.X < 110 and lp.Z < -118 and lp.Z > -121, string.format("%.1f,%.1f", lp.X, lp.Z))
	end
	local spawnMarker = office0:FindFirstChild("GarageSpawn", true)
	check("t0: company car spot (GarageSpawn.SpawnCFrame)", spawnMarker ~= nil and typeof(spawnMarker:GetAttribute("SpawnCFrame")) == "CFrame")
	-- the parked company van stands beside the car spot: no part of it inside the largest car's footprint
	-- (CampusConfig cars up to 7.4 x 15) around the spawn, all on the driveway, only its body collides
	local van = office0:FindFirstChild("CompanyVan", true)
	check("t0: company van parked in front of the garage", van ~= nil)
	if van and spawnMarker then
		local sp = cf0:ToObjectSpace(spawnMarker:GetAttribute("SpawnCFrame"))
		local clash, offDrive, collide = 0, 0, 0
		for _, x in van:GetDescendants() do
			if x:IsA("BasePart") then
				local lp = cf0:PointToObjectSpace(x.Position)
				local o = sp:PointToObjectSpace(lp)
				local half = x.Size / 2
				if math.abs(o.X) < 3.7 + half.X and math.abs(o.Z) < 7.5 + half.Z then clash += 1 end
				if lp.X < 92 or lp.X > 112 or lp.Z > Plan.GARAGE_LAB.z1 - 1 then offDrive += 1 end
				if x.CanCollide then collide += 1 end
			end
		end
		check("t0: van keeps the car spot free", clash == 0, clash)
		check("t0: van stands on the driveway", offDrive == 0, offDrive)
		check("t0: only the van body collides (chassis, body, cargo box, cab)", collide == 4, collide)
	end
	local blades = office0:FindFirstChild("Blades", true)
	local nb = 0
	if blades then for _, b in blades:GetChildren() do if b:IsA("BasePart") or b:IsA("Model") then nb += 1 end end end
	check("t0: RackBlades in the server corner", nb == Plan.GARAGE_STAGE.blades, nb)
	local kinds = {}
	for _, m in stations(office0) do local k = m:GetAttribute("WorkstationType"); kinds[k] = (kinds[k] or 0) + 1 end
	check("t0: 7 desks (5 team + founder + assistant)", kinds.Computer == 7, kinds.Computer)
	check("t0: coffee corner (2 Coffee)", kinds.Coffee == 2, kinds.Coffee)
	check("t0: 4 porch Waiting seats", kinds.Waiting == 4, kinds.Waiting)
	check("t0: no operations posts", (kinds.Service or 0) == 0, kinds.Service)
	check("t0: no operations staff", #office0.OperationsEmployees:GetChildren() == 0, #office0.OperationsEmployees:GetChildren())
	check("t0: 5 employees placed", #office0.Employees:GetChildren() == Plan.GARAGE_STAGE.staff, #office0.Employees:GetChildren())
	local onDesk = 0
	for _, e in office0.Employees:GetChildren() do if string.match(e:GetAttribute("HomeWorkstation") or "", "^G0_LAB_") then onDesk += 1 end end
	check("t0: every employee has a G0_LAB desk", onDesk == Plan.GARAGE_STAGE.staff, onDesk)
	local wc = office0.Rooms:FindFirstChild("G0_WC")
	local fixtures = {}
	if wc then for _, x in wc:GetDescendants() do local k = x:GetAttribute("FixtureKey"); if k then fixtures[x.Name] = k end end end
	check("t0: WC fixtures (toilet, flush, tap)", fixtures.ToiletSeat ~= nil and fixtures.Tap ~= nil, fixtures.ToiletSeat)
	-- roll-up door on the CampusDoor contract
	local door = office0.Doors:FindFirstChild("Door_G0_ROLLUP")
	local leaf = door and door:FindFirstChild("Leaf1")
	check("t0: roll-up door model", door ~= nil and leaf ~= nil)
	check("t0: roll-up door tagged CampusDoor", door ~= nil and Collection:HasTag(door, "CampusDoor"))
	check("t0: roll-up door pivots", leaf ~= nil and typeof(leaf:GetAttribute("ClosedPivot")) == "CFrame" and typeof(leaf:GetAttribute("OpenPivot")) == "CFrame")
	Doors.register(office0)
	local defs = 0
	for _, dd in Layout.doors(0) do if dd.level == 0 then defs += 1 end end
	local listed = Doors.inspect(office0)
	local ids = {}
	for _, li in listed do table.insert(ids, tostring(li.id or li.DoorId or li.name)) end
	table.sort(ids)
	check("t0: DoorService lists every planned door + the roll-up door + the WC cubicle", #listed == defs + 2, #listed .. " vs " .. defs .. "+2: " .. table.concat(ids, ","))
	check("t0: DoorService finds G0_ROLLUP", Doors.find(office0, "G0_ROLLUP") == door)
	if door and leaf then
		local c = Instance.new("Model"); c.Name = "Founder"
		local root = Instance.new("Part"); root.Name = "HumanoidRootPart"; root.Anchored = true; root.Size = Vector3.new(2, 2, 1); root.Parent = c
		Instance.new("Humanoid").Parent = c; c.PrimaryPart = root; c.Parent = G.workspace
		root.CFrame = cf0 * CFrame.new(108, 3, -121.5)
		local founder = { UserId = OWNER, Name = "Founder", Character = c }
		local stranger = { UserId = 7, Name = "Stranger", Character = c }
		players = { founder }
		local okS = Doors.request(stranger, door, "out")
		check("t0: roll-up door refuses strangers", okS == false)
		local ok, why = Doors.request(founder, door, "out")
		check("t0: founder opens the roll-up door", ok == true, why)
		heartbeat(2)
		check("t0: roll-up door fully open (leaf at OpenPivot)", Doors.state(door) == "open" and near(leaf:GetPivot(), leaf:GetAttribute("OpenPivot")), Doors.state(door))
		root.CFrame = cf0 * CFrame.new(102, 3, -140) -- walk away
		heartbeat(12)
		check("t0: roll-up door closes after HoldOpen", Doors.state(door) == "closed" and near(leaf:GetPivot(), leaf:GetAttribute("ClosedPivot")), Doors.state(door))
		players = {}
	end
	-- no lift in the garage: LiftService does not fail or warn
	local lw = M.stats.warnings
	check("t0: LiftService.attach -> false", Lift.attach(office0) == false)
	local info = Lift.inspect(office0)
	check("t0: LiftService.inspect reports 'none', not 'failed'", info.none == true and info.failed == false)
	check("t0: no lift warning", M.stats.warnings == lw, M.stats.warnings - lw)
	check("t0: Plan.liftStops(0) empty", #Plan.liftStops(0) == 0)
	local p0, l0 = count(office0)
	say(string.format("tier 0 garage stage: %d parts, %d lights (whole office incl. site, arcade, garden, yard, rigs)", p0, l0))
	check("t0: part budget (< 4000)", p0 < 4000, p0)

	end)
	check("t0: section ran without errors", okT0, errT0)
	--------------------------------------------------------------------------------------------- tier 1
	local office1, cf1, warn1 = build(1, 1)
	check("t1: no warnings", warn1 == 0, warn1)
	check("t1: no guest house", office1:GetAttribute("HotelRooms") == nil and office1.Rooms:FindFirstChild("H0_LOBBY") == nil and office1:FindFirstChild("GuestHouseGrounds", true) == nil)
	check("t1: lift attaches", Lift.attach(office1) == true)
	local H = Plan.HOTEL or { x1 = -141, x2 = -98, z1 = 76, z2 = 172 }
	local BOX = { x1 = H.x1 - 2, x2 = H.x2 + 12, z1 = H.z1 - 4, z2 = H.z2 + 3 }
	local p1box, l1box = count(office1, BOX, cf1)
	-- operations posts: the guest-house posts 13/14 are silently optional where the tier has no guest house
	local Assign = M.require(Services.StaffAssignment)
	local function assignOps(office, cf, tier)
		local w0 = M.stats.warnings
		Assign.assign(office, cf, { userId = OWNER, data = { empire = { office = tier, employees = {} } } })
		return M.stats.warnings - w0
	end
	check("t1: missing guest-house posts 13/14 do not warn (no guest house at tier 1)", assignOps(office1, cf1, 1) == 0)
	local EmployeeConfig = M.require(RS.Shared.Config.EmployeeConfig)
	-- staffops: OPERATIONS_JOBS[17] "Training Lead" has no post (placed only while there are apprentices);
	-- 18 / 19 = the stage-5 night rota (placed only in plan tier 4)
	-- integrate (staffops request 10, CORE_SPEC 5.5): plan tier 1 = stage 2 staffs only the posts the economy pays
	-- there (EmployeeConfig.POST_FROM_STAGE): 1, 3, 5, 6, 7, 8, 9, 12 = 8 = CompanyOps.STAGES[2].ops
	local postFrom = EmployeeConfig.POST_FROM_STAGE or {}
	local paid1 = 0
	for i = 1, 16 do if i ~= 13 and i ~= 14 and Plan.officeForTier(1) >= (postFrom[i] or 2) then paid1 += 1 end end
	local Ops1 = M.require(RS.Shared.CompanyOps)
	check("t1: exactly the operations posts paid at stage 2 are staffed (8 = CompanyOps.STAGES[2].ops)", #office1.OperationsEmployees:GetChildren() == paid1 and paid1 == Ops1.STAGES[2].ops, #office1.OperationsEmployees:GetChildren() .. " / " .. paid1)

	--------------------------------------------------------------------------------------------- tier 2+
	local tiers = if ALL then { 2, 3, 4 } else { 2 }
	for n, tier in tiers do
		local okT, errT = pcall(function()
		local office, cf, w = build(tier, 1 + n)
		local T = "t" .. tier .. ": "
		check(T .. "no warnings", w == 0, w)
		check(T .. "HotelRooms = 12", office:GetAttribute("HotelRooms") == Plan.HOTEL_ROOMS, office:GetAttribute("HotelRooms"))
		local guestrooms, beds, wardrobes, tvs, desks, cubicles, fixturesOk, vip = 0, 0, 0, 0, 0, 0, 0, 0
		for _, r in Plan.rooms(tier) do
			if r.kind == "guestroom" then
				guestrooms += 1
				if r.vip then vip += 1 end
				local m = office.Rooms:FindFirstChild(r.id)
				local names = {}
				if m then for _, x in m:GetDescendants() do names[x.Name] = (names[x.Name] or 0) + 1 end end
				if (names.Mattress or 0) >= 1 then beds += 1 end
				if (names.Wardrobe or 0) + (names.WardrobeBody or 0) >= 1 then wardrobes += 1 end
				if (names.TV or 0) >= 1 then tvs += 1 end
				if (names.WritingDesk or 0) + (names.DeskTop or 0) >= 1 then desks += 1 end
				local cub = office.Doors:FindFirstChild("Door_" .. r.id .. "_BATH", true)
				if cub and cub:GetAttribute("DoorKind") == "cubicle" then cubicles += 1 end
				local keys = {}
				if m then for _, x in m:GetDescendants() do local k = x:GetAttribute("FixtureKey"); if k then keys[k] = true end end end
				if keys[r.id .. "_T"] and keys[r.id .. "_B"] and keys[r.id .. "_S"] then fixturesOk += 1 end
			end
		end
		check(T .. "12 guest rooms in the plan (1 suite)", guestrooms == 12 and vip == 1, guestrooms .. "/" .. vip)
		check(T .. "every guest room has a bed", beds == 12, beds)
		check(T .. "every guest room has a wardrobe", wardrobes == 12, wardrobes)
		check(T .. "every guest room has a TV", tvs == 12, tvs)
		check(T .. "every guest room has a writing desk", desks == 12, desks)
		check(T .. "12 en-suite cubicle doors", cubicles == 12, cubicles)
		check(T .. "12 en-suites with toilet, basin and shower fixtures", fixturesOk == 12, fixturesOk)
		local posts, dining, workshop, coffee = {}, 0, 0, 0
		for _, m in stations(office) do
			local kind, room = m:GetAttribute("WorkstationType"), m:GetAttribute("HomeRoom")
			local i = m:GetAttribute("OpsIndex")
			if kind == "Service" and (i == 13 or i == 14) then posts[i] = m end
			if kind == "Dining" and room == "H0_BREAKFAST" then dining += 1 end
			if kind == "Meeting" and m:GetAttribute("MeetingRoom") == "HotelWorkshop" then workshop += 1 end
			if kind == "Coffee" and room == "H0_BREAKFAST" then coffee += 1 end
		end
		local function jobPoints(m)
			local n = 0
			if m then for k in m:GetAttributes() do if string.match(k, "^JobPoint_") then n += 1 end end end
			return n
		end
		check(T .. "reception post OpsIndex 13 in the lobby", posts[13] ~= nil and posts[13]:GetAttribute("HomeRoom") == "H0_LOBBY", posts[13] and posts[13]:GetAttribute("HomeRoom"))
		check(T .. "housekeeping post OpsIndex 14 in the linen room", posts[14] ~= nil and posts[14]:GetAttribute("HomeRoom") == "H0_LINEN", posts[14] and posts[14]:GetAttribute("HomeRoom"))
		check(T .. "reception job points", jobPoints(posts[13]) >= 2, jobPoints(posts[13]))
		check(T .. "housekeeping job points (cart + rooms)", jobPoints(posts[14]) >= 5, jobPoints(posts[14]))
		local opsAt = {}
		for _, e in office.OperationsEmployees:GetChildren() do
			local hw = e:GetAttribute("HomeWorkstation")
			for i, p in posts do if hw == p:GetAttribute("WorkstationId") then opsAt[i] = true end end
		end
		check(T .. "receptionist and housekeeper placed at their posts", opsAt[13] == true and opsAt[14] == true)
		check(T .. "20 breakfast seats", dining == 20, dining)
		check(T .. "10 workshop seats (MeetingRoom HotelWorkshop)", workshop == 10, workshop)
		check(T .. "breakfast coffee station", coffee >= 1, coffee)
		-- access + circulation
		local lobby = Plan.room(tier, "H0_LOBBY")
		check(T .. "guest rooms are class 'guest'", Plan.accessAt(tier, Vector3.new(-136, Plan.levelY(0) + 3, 130)) == "guest", Plan.accessAt(tier, Vector3.new(-136, 3, 130)))
		check(T .. "lobby is public", lobby ~= nil and lobby.access == "public")
		check(T .. "support staff may enter the guest house", Plan.roleAllows("support", "guest") == true)
		check(T .. "hotel guests: public + guest only", Plan.roleAllows("guest", "guest") and Plan.roleAllows("guest", "public") and not Plan.roleAllows("guest", "staff"))
		check(T .. "class label 'Hotel guests'", Plan.CLASS_LABEL.guest == "Hotel guests")
		check(T .. "annex detected", Plan.annexAt(tier, Vector3.new(-120, 3, 130)) == "hotel" and Plan.annexAt(tier, Vector3.new(0, 3, 0)) == nil)
		local sp = Plan.stairEntryFor("hotel", 1)
		check(T .. "hotel stair entry on level 1 inside the guest house", sp ~= nil and Plan.inHotel(sp) and math.abs(sp.Y - (Plan.levelY(1) + 3)) < 0.01)
		-- the HQ lift (wait points, landing models) never stands in the guest house
		local liftInHotel = 0
		for _, s in Plan.liftStops(tier) do
			for slot = 1, 6 do if Plan.inHotel(Plan.liftWaitPoint(s.level, slot)) then liftInHotel += 1 end end
		end
		for _, x in office.Lift:GetDescendants() do
			if x:IsA("BasePart") and Plan.inHotel(cf:PointToObjectSpace(x.Position)) then liftInHotel += 1 end
		end
		check(T .. "HQ lift wait points and landings never inside the guest house", liftInHotel == 0 and #office.Lift:GetChildren() > 0, liftInHotel)
		local stairs = office.Rooms:FindFirstChild("H0_STAIR") and office.Rooms:FindFirstChild("H1_STAIR")
		check(T .. "guest house stair rooms", stairs ~= nil)
		-- every annex door of the plan has a model and DoorService knows it
		Doors.register(office)
		local missing = {}
		for _, dd in Layout.doors(tier) do
			if dd.annex == "hotel" and not dd.exterior and dd.kind ~= "opening" and Doors.find(office, dd.id) == nil then table.insert(missing, dd.id) end
		end
		check(T .. "every interior guest-house door is registered", #missing == 0, table.concat(missing, ","))
		local ext = 0
		for _, dd in Layout.doors(tier) do if dd.annex == "hotel" and dd.exterior and Doors.find(office, dd.id) ~= nil then ext += 1 end end
		check(T .. "guest-house entrance doors (lobby E + corridor N)", ext == 2, ext)
		check(T .. "lift still attaches with the annex", Lift.attach(office) == true)
		local p2box, l2box = count(office, BOX, cf)
		local hp, hl = p2box - p1box, l2box - l1box
		say(string.format("tier %d guest house: %d parts, %d lights (annex box, minus tier 1's site parts there)", tier, hp, hl))
		check(T .. "guest house part budget 1800..2600", hp >= 1800 and hp <= 2600, hp)
		check(T .. "guest house lights <= 16", hl <= 16, hl)
		-- navigation: an employee going into the guest house never asks for the lift (one walked path via
		-- the guest-house stair), the same lift-loving employee takes the lift inside the HQ
		local rig = Rig.build(office.Employees, OWNER, 900 + tier, "support", cf * CFrame.new(0, Plan.levelY(0) + 3, -14))
		local e = { model = rig, root = rig.PrimaryPart, humanoid = rig:FindFirstChildOfClass("Humanoid"), index = 1, role = "support", tier = tier, cf = cf, office = office,
			personality = { walkSpeed = 10, stairs = 0.1 }, state = "WAITING", now = 0, sequence = 0 }
		local hqRoom
		for _, r in Plan.rooms(tier) do if r.level == 1 and r.access == "staff" and not r.annex and not r.nowalls then hqRoom = r; break end end
		local cb = function() end
		Nav.go(e, cf * Vector3.new(-136, Plan.levelY(1) + 3, 110), 0, cb)
		check(T .. "route into the guest house upstairs uses the stairs", e.nav ~= nil and e.nav.mode == "stairs" and e.nav.annex == true, e.nav and e.nav.mode)
		if hqRoom then
			Nav.go(e, cf * Vector3.new((hqRoom.x1 + hqRoom.x2) / 2, Plan.levelY(1) + 3, (hqRoom.z1 + hqRoom.z2) / 2), 0, cb)
			check(T .. "the same employee takes the lift inside the HQ", e.nav ~= nil and e.nav.mode == "lift" and e.nav.annex == nil, e.nav and e.nav.mode)
		end
		Nav.cancel(e)
		rig:Destroy()
		if tier == 2 then
			-- with the guest house built, a missing guest-house post is a real defect: one warning
			for _, m in office:GetDescendants() do
				if m:IsA("Model") and m:GetAttribute("OpsIndex") == 14 then m:Destroy() end
			end
			check(T .. "missing housekeeping post warns once when the guest house exists", assignOps(office, cf, tier) == 1)
			local placed14 = false
			for _, x in office.OperationsEmployees:GetChildren() do if x:GetAttribute("HomeWorkstation") == "OperationsStation14" then placed14 = true end end
			check(T .. "no housekeeper without a post", not placed14)
		end
		end)
		check("t" .. tier .. ": section ran without errors", okT, errT)
	end
end
setfenv(body, M.envFor(nil))
local ok, err = M.runMain(body, { timeout = 1800 })
if not ok then say("ERROR: " .. tostring(err)); failc += 1 end
say(string.format("buildings build tests%s: %d passed, %d failed", if NEG then " (NEGATIVE: original files)" else "", pass, failc))
if failc > 0 then error("buildings build tests failed", 0) end
