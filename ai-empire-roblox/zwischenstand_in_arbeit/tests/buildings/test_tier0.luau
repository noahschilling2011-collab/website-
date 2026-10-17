--!nocheck
-- Package "buildings" · tier 0 (garage stage) runtime on the REAL generated garage (HeadquartersDesign.build
-- with session.planTier = 0, StaffAssignment + the real StaffService/Recruiting/Assistant; Door/Lift/Plot/
-- Session doubles, straight paths, Humanoid:MoveTo simulated step by step):
--   * the team sits at the G0_LAB desks, nobody is sent to operations posts, no warnings
--   * staff stay inside the garage / on its forecourt and never call the lift
--   * the assistant takes the G0_ASSIST desk and fetches coffee from the garage coffee corner
--   * applicants wait on the porch benches (G0_PORCH), several at once on distinct seats, a hire walks off
-- Run: python3 tests/buildings/mkharness.py && tools/luau tests/buildings/test_tier0.luau [-a neg]
local M = require("../../harness/mock")
local args = { ... }
local NEG = args[1] == "neg"
local REQ = args[1] == "req" -- the requested StaffService change applied (gen_req, design/requests/buildings.md)
local VERBOSE = args[1] == "-v" or args[2] == "-v"
if NEG then
	M.loadTree(require("./gen_neg/manifest"), require("./gen_neg/sources"))
elseif REQ then
	M.loadTree(require("./gen_req/manifest"), require("./gen_req/sources"))
else
	M.loadTree(require("./gen/manifest"), require("./gen/sources"))
end
M.quiet = true
local G = M.G
local say = print
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; say("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local function body()
	-- staffops (ONE clock, CORE_SPEC 6): staff follow the server clock (CompanyOps.hour of
	-- workspace:GetServerTimeNow() = 1.7e9 + Sched.now, 16:53 at Sched.now 0); start the company day at
	-- 08:36 as before (the old private StaffService timer started at 54 s).
	M.Sched.now += 454
	local Instance, Vector3, CFrame, Enum, Color3 = G.Instance, G.Vector3, G.CFrame, G.Enum, G.Color3
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local Services = Server.Services
	local Plan = M.require(RS.Shared.Config.BuildingPlan)
	local EmpireMath = M.require(RS.Shared.EmpireMath)
	local Template = M.require(Server.Lib.Template)
	local Remote = M.require(Server.Lib.Remote)
	local Design = M.require(Services.HeadquartersDesign)
	local Staff = M.require(Services.StaffService)
	local Workstations = M.require(Services.WorkstationService)
	local Recruiting = M.require(Services.RecruitingService)
	local Assistant = M.require(Services.AssistantService)
	local SessionStub = M.require(Services.SessionService)
	local PlotStub = M.require(Services.PlotService)
	local LiftStub = M.require(Services.LiftService)
	local OWNER = 1001
	local cf = CFrame.lookAt(Vector3.new(160, 24, 252), Vector3.new(160, 24, 0)) -- a real plot frame
	local d = Template.new()
	d.company = { name = "Nimbus Labs", logo = "N", color = "cyan", spec = "general", reputation = 10, foundedAt = 0 }
	d.empire.office = 1; d.money = 1e6
	d.empire.employees = { researcher = 1, engineer = 1, curator = 1, marketer = 1 } -- 4 of 5 garage seats
	EmpireMath.syncProfiles(d.empire, OWNER)
	local char = Instance.new("Model"); char.Name = "Founder"
	local hrp = Instance.new("Part"); hrp.Name = "HumanoidRootPart"; hrp.Anchored = true; hrp.Parent = char; char.PrimaryPart = hrp; char.Parent = G.workspace
	local player = { UserId = OWNER, Name = "Founder", DisplayName = "Founder", Character = char, CharacterAdded = M.newSignal("CharacterAdded"), FindFirstChildOfClass = function() return nil end }
	local session = { userId = OWNER, player = player, data = d, live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} }, closed = false, planTier = 0 }
	hrp.CFrame = cf * CFrame.new(105, 3, -86) -- founder corner of the garage
	local warn0 = M.stats.warnings
	local office = Design.build(cf, session, Color3.fromRGB(120, 154, 129))
	local plots = Instance.new("Folder"); plots.Name = "Plots"; plots.Parent = G.workspace
	local plot = Instance.new("Model"); plot.Name = "Plot_01"; plot.Parent = plots
	office.Parent = plot
	SessionStub.sessions = { session }
	PlotStub.plots = { { model = plot, office = office, owner = player, cframe = cf, index = 1 } }
	check("garage stage built (OfficeTier 0)", office:GetAttribute("OfficeTier") == 0, office:GetAttribute("OfficeTier"))
	check("GarageStage attribute", office:GetAttribute("GarageStage") == true)
	local function patch(cls, name, fn) M.IMPL[cls].methods[name] = fn; M.classInfo(cls).methods[name] = fn end
	patch("PathfindingService", "CreatePath", function(_, params)
		local fake = { Status = Enum.PathStatus.NoPath, _points = {}, Blocked = M.newSignal("Blocked"), params = params }
		function fake.ComputeAsync(self, start, target)
			local pts = {}; local n = math.max(1, math.ceil((target - start).Magnitude / 4))
			for i = 0, n do table.insert(pts, start:Lerp(target, i / n)) end
			self.Status = Enum.PathStatus.Success; self._points = pts
		end
		function fake.GetWaypoints(self) local out = {}; for _, p in self._points do table.insert(out, { Position = p, Action = Enum.PathWaypointAction.Walk }) end; return out end
		return fake
	end)
	local moveTarget = {}
	patch("Humanoid", "MoveTo", function(self, pos) moveTarget[self] = pos end)
	LiftStub.scripted = true
	local liftCalls = 0
	for _, fname in { "request", "call", "hallCall", "ticket" } do
		local f = LiftStub[fname]
		if typeof(f) == "function" then LiftStub[fname] = function(...) liftCalls += 1; return f(...) end end
	end
	Staff.init()
	local reg = Workstations.scan(office)
	-- station inventory of the garage ---------------------------------------------------------------
	local function countKind(kind, room)
		local n = 0
		for _, w in reg.byKind[kind] or {} do if room == nil or w.room == room then n += 1 end end
		return n
	end
	check("6 garage desks (5 team + founder)", countKind("Computer", "G0_LAB") == 5 and countKind("Computer", "G0_FOUNDER") == 1, countKind("Computer", "G0_LAB") .. "+" .. countKind("Computer", "G0_FOUNDER"))
	check("assistant desk at the garage door", countKind("Computer", "G0_ASSIST") == 1, countKind("Computer", "G0_ASSIST"))
	check("coffee corner: 2 Coffee stations in the lab", countKind("Coffee", "G0_LAB") == 2, countKind("Coffee", "G0_LAB"))
	check("server corner: ServerRack station", countKind("ServerRack") >= 1)
	check("meeting table: 4 seats", reg.meetings.GarageTable ~= nil and #reg.meetings.GarageTable.seats == 4)
	check("porch: 4 Waiting seats", countKind("Waiting", "G0_PORCH") == 4, countKind("Waiting", "G0_PORCH"))
	check("no operations posts in the garage", countKind("Service") == 0, countKind("Service"))
	local blades = 0
	for _, x in office:GetDescendants() do if x.Name == "RackBlade" or x:GetAttribute("RackBlade") ~= nil then blades += 1 end end
	check("6 RackBlades in the server corner", blades == Plan.GARAGE_STAGE.blades, blades)
	-- staff --------------------------------------------------------------------------------------------
	local rigs = office.Employees:GetChildren()
	check("4 employees spawned", #rigs == 4, #rigs)
	check("no operations staff at tier 0", #office.OperationsEmployees:GetChildren() == 0, #office.OperationsEmployees:GetChildren())
	local homes, distinct = 0, {}
	for _, m in rigs do
		local id = m:GetAttribute("HomeWorkstation")
		local w = if typeof(id) == "string" then reg.byId[id] else nil
		if w and w.room == "G0_LAB" then homes += 1; distinct[w.id] = true end
	end
	local nd = 0; for _ in distinct do nd += 1 end
	check("every employee's home desk is a G0_LAB desk", homes == #rigs and nd == #rigs, homes .. "/" .. nd)
	check("no warnings while building and placing staff", M.stats.warnings == warn0, M.stats.warnings - warn0)
	local function moveAll()
		for hum, goal in moveTarget do
			local root = hum.Parent and hum.Parent.PrimaryPart
			if root and not root.Anchored and hum.Parent.Parent then
				local here = root.Position; local delta = goal - here
				local flat = Vector3.new(delta.X, 0, delta.Z); local len = hum.WalkSpeed * .2
				local mv = if flat.Magnitude > len then flat.Unit * len else flat
				local y = here.Y + (if math.abs(delta.Y) > 4 then delta.Y * math.min(1, len / math.max(flat.Magnitude, len)) else 0)
				root.CFrame = CFrame.new(Vector3.new(here.X + mv.X, y, here.Z + mv.Z))
			end
		end
	end
	local outside, maxY, coffeeUse, deskUse, insideSamples = 0, -1e9, 0, 0, 0
	local minY, minAt = 1e9, ""
	local kinds = {}
	local function sample()
		for _, m in office.Employees:GetChildren() do
			local root = m.PrimaryPart
			if root then
				local lp = cf:PointToObjectSpace(root.Position)
				maxY = math.max(maxY, lp.Y)
				if lp.Y < minY then minY = lp.Y; minAt = m.Name .. " " .. tostring(m:GetAttribute("OffDuty")) .. " " .. tostring((Staff.recordOf(m) or {}).state) end
				local s = Plan.SITE
				if lp.X < s.x1 or lp.X > s.x2 or lp.Z < s.z1 or lp.Z > s.z2 then outside += 1 end
				if Plan.inGarageLab and Plan.inGarageLab(lp) then insideSamples += 1 end
				local rec = Staff.recordOf(m)
				local st = rec and rec.station
				if st and st.kind == "Coffee" and st.room == "G0_LAB" then coffeeUse += 1 end
				if st and st.kind == "Computer" and st.room == "G0_LAB" then deskUse += 1 end
				if st then kinds[st.kind .. "@" .. tostring(st.room)] = (kinds[st.kind .. "@" .. tostring(st.room)] or 0) + 1 end
			end
		end
	end
	local function step(n, hook)
		for i = 1, n do
			LiftStub.clock += .2
			M.Sched.now += .2
			moveAll()
			Staff.tick(.2)
			Recruiting.campusTick(.2)
			Assistant.tick(.2)
			if i % 10 == 0 then sample() end
			if hook and hook() then return true end
		end
		return false
	end
	step(3000)
	if VERBOSE then for k, n in kinds do say("  station use " .. k .. " x" .. n) end end
	check("staff work at the G0_LAB desks", deskUse > 0, deskUse)
	check("staff take coffee breaks in the garage coffee corner", coffeeUse > 0, coffeeUse)
	check("staff stay on the site", outside == 0, outside)
	check("staff stay on the ground floor (no upper storeys)", maxY < 8, maxY)
	-- Off-duty / arriving car commuters use StaffService.commute = Plan.GARAGE_ARRIVAL (B1, y -13): the garage
	-- stage has no B1, so they would wait inside the ground. Fixed by the requested StaffService change
	-- (Plan.staffArrival(tier, byCar) + the plan tier from OfficeTier); checked on gen_req ("req" mode).
	if REQ then
		check("no employee below the ground floor (car commuters arrive at the visitor bays)", minY > -2, string.format("%.1f %s", minY, minAt))
	else
		say(string.format("INFO lowest employee root %.1f (%s): needs the StaffService request (run with -a req)", minY, minAt))
	end
	check("staff spend their day inside the garage", insideSamples > 0, insideSamples)
	check("nobody calls a lift at tier 0", liftCalls == 0 and #(LiftStub.tickets or {}) == 0, liftCalls)
	-- assistant ----------------------------------------------------------------------------------------
	local rec = Assistant.recordFor(session)
	check("assistant placed in the garage", rec ~= nil and rec.model.Parent ~= nil)
	check("assistant uses the G0_ASSIST desk", rec and rec.e.station and rec.e.station.id == "G0_ASSIST_Desk1", rec and rec.e.station and rec.e.station.id)
	local ok = Assistant._act(session, { action = "coffee" })
	check("coffee ordered", ok.ok, ok.err)
	check("assistant walks to the garage coffee corner", rec and rec.coffeeStation and rec.coffeeStation.room == "G0_LAB", rec and rec.coffeeStation and rec.coffeeStation.room)
	check("garage coffee machine found (PantryCoffee)", rec and rec.machine ~= nil and rec.machine.Name == "PantryCoffee")
	local delivered = step(1200, function()
		for _, f in Remote.fired do if f.args[1] == "ASSISTANT_NOTICE" and string.find(f.args[2].text, "Here's your coffee") then return true end end
		return false
	end)
	check("coffee delivered in the garage", delivered, rec and rec.state)
	-- applicants ---------------------------------------------------------------------------------------
	local a = Recruiting.generate(d.empire, OWNER, 0); table.insert(d.empire.applicants, a)
	check("invite", Recruiting._act(session, { action = "invite", id = a.id }).ok)
	local v = Recruiting.visit(session, a.id)
	check("visitor spawned", v ~= nil)
	local seated = v ~= nil and step(900, function() return v.phase == "waiting" and v.seated end)
	local spotRoom = if v and v.spot and v.spot.w then v.spot.w.room elseif v and v.spot and v.spot.seat and string.find(v.spot.seat:GetFullName(), "G0_PORCH") then "G0_PORCH" else nil
	check("applicant waits on a porch bench (G0_PORCH Waiting seat)", seated and spotRoom == "G0_PORCH" and v.spot.w and v.spot.w.kind == "Waiting", v and v.phase)
	if v and v.e and v.e.root then
		local lp = cf:PointToObjectSpace(v.e.root.Position)
		say(string.format("applicant waits at local (%.1f, %.1f, %.1f)", lp.X, lp.Y, lp.Z))
		check("waiting spot is in front of the garage, not in the old HQ lounge", lp.X > 60 and lp.X < 95 and lp.Z < -115 and lp.Z > -130, string.format("%.1f,%.1f", lp.X, lp.Z))
	end
	for _ = 1, 3 do local x = Recruiting.generate(d.empire, OWNER, 0); table.insert(d.empire.applicants, x); Recruiting._act(session, { action = "invite", id = x.id }) end
	step(900, function()
		for _, x in d.empire.applicants do local vv = Recruiting.visit(session, x.id); if not vv or not vv.seated then return false end end
		return true
	end)
	local seatedCount, seats = 0, {}
	for _, x in d.empire.applicants do local vv = Recruiting.visit(session, x.id); if vv and vv.seated and vv.spot then seatedCount += 1; seats[vv.spot.key] = true end end
	local ns = 0; for _ in seats do ns += 1 end
	check("four applicants seated on four different porch seats", seatedCount == 4 and ns == 4, seatedCount .. "/" .. ns)
	-- hire the first one: walks off towards the road and despawns
	if v then
		a.st = "interviewing"
		local idx
		for i, x in d.empire.applicants do if x.id == a.id then idx = i end end
		local res = Recruiting._act(session, { action = "hire", id = a.id })
		check("hire accepted", res.ok and res.accepted, res.err)
		local gone = step(900, function() return Recruiting.visit(session, a.id) == nil or v.model.Parent == nil end)
		check("hired applicant leaves the porch and despawns", gone, v.phase)
		local _ = idx
	end
	check("no warnings during the garage day", M.stats.warnings == warn0, M.stats.warnings - warn0)
end
setfenv(body, M.envFor(nil))
local ok, err = M.runMain(body, { timeout = 900 })
if not ok then say("ERROR: " .. tostring(err)); failc += 1 end
say(string.format("buildings tier0 runtime%s: %d passed, %d failed", if NEG then " (NEGATIVE: original files)" elseif REQ then " (with the requested StaffService change)" else "", pass, failc))
if failc > 0 then error("buildings tier0 runtime tests failed", 0) end
