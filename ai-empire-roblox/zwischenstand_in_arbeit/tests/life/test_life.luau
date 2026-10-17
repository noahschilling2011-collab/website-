--!nocheck
-- Package "life" · staff on the REAL headquarters (HeadquartersDesign.build + StaffAssignment + the real
-- StaffService/StaffJobs/WorkstationService; DoorService/LiftService/Plot/Session test doubles, straight
-- paths, Humanoid:MoveTo simulated step by step) for most of a company day:
--   * every operations job shows its visible steps (poses, held items, props in use)
--   * lunch: queue at the servery, a plate from the kitchen team, meal at a LunchSeat, tray returned
--   * wellness breaks, the IT fault fix, the blade pickup for rack checks
--   * budgets: no server CFrame writes on PropFx parts, rare rig/prop attribute writes, movers cap
-- Run: python3 tests/life/mkharness.py && tools/luau tests/life/test_life.luau -a [tier] [ticks]
local M = require("../../harness/mock")
M.loadTree(require("./gen/manifest"), require("./gen/sources"))
M.quiet = true
local G = M.G
local say = print
local args = { ... }
local TIER = tonumber(args[1]) or 2
local TICKS = tonumber(args[2]) or 5400
local pass, failc = 0, 0
local failures = {}
local function check(name, ok, detail)
	if ok then pass += 1 return end
	failc += 1
	if not failures[name] then
		failures[name] = 0
		say("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else ""))
	end
	failures[name] += 1
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
	local Collection = game:GetService("CollectionService")
	local Template = M.require(Server.Lib.Template)
	local EmpireConfig = M.require(RS.Shared.Config.EmpireConfig)
	local EmployeeConfig = M.require(RS.Shared.Config.EmployeeConfig)
	local Design = M.require(Services.HeadquartersDesign)
	local Staff = M.require(Services.StaffService)
	local Workstations = M.require(Services.WorkstationService)
	local SessionStub = M.require(Services.SessionService)
	local PlotStub = M.require(Services.PlotService)
	local LiftStub = M.require(Services.LiftService)
	local OWNER = 1001
	local cf = CFrame.lookAt(Vector3.new(160, 24, 252), Vector3.new(160, 24, 0))
	local d = Template.new()
	d.company = { name = "Nimbus Labs", logo = "N", color = "cyan", spec = "general", reputation = 10, foundedAt = 0 }
	d.empire.office = M.require(RS.Shared.Config.BuildingPlan).officeForTier(TIER) -- econ: save office index of this plan tier (DATA_VERSION 6)
	local cap = EmpireConfig.OFFICES[d.empire.office].staff
	for k, role in EmpireConfig.ROLES do d.empire.employees[role.id] = math.floor(cap / #EmpireConfig.ROLES) + (if k <= cap % #EmpireConfig.ROLES then 1 else 0) end
	-- staffops: people on vacation / sick (CompanyOps.presence) stay home; this suite covers every job and
	-- break kind, so it runs on a company day on which the whole team is in
	local Ops = M.require(RS.Shared.CompanyOps)
	for day = 1, 400 do
		d.empire.calendar = { day = day }
		local all = true
		for _, role in EmpireConfig.ROLES do for _, st in Ops.presence(d.empire, role.id) do if st ~= "present" then all = false end end end
		if all then break end
	end
	-- a founder standing in the atrium keeps the whole office awake (LOD full/reduced)
	local char = Instance.new("Model"); char.Name = "Founder"
	local hrp = Instance.new("Part"); hrp.Name = "HumanoidRootPart"; hrp.Anchored = true; hrp.CFrame = cf * CFrame.new(0, 3, 10); hrp.Parent = char; char.PrimaryPart = hrp; char.Parent = G.workspace
	local player = { UserId = OWNER, Name = "Founder", DisplayName = "Founder", Character = char, CharacterAdded = M.newSignal("CharacterAdded") }
	local session = { userId = OWNER, player = player, data = d, live = { users = 0, revenue = 0, cost = 0 }, closed = false }
	local office = Design.build(cf, session, Color3.fromRGB(120, 154, 129))
	local plots = Instance.new("Folder"); plots.Name = "Plots"; plots.Parent = G.workspace
	local plot = Instance.new("Model"); plot.Name = "Plot_01"; plot.Parent = plots
	office.Parent = plot
	SessionStub.sessions = { session }
	PlotStub.plots = { { model = plot, office = office, owner = player, cframe = cf, index = 1 } }
	local function patch(cls, name, fn) M.IMPL[cls].methods[name] = fn; M.classInfo(cls).methods[name] = fn end
	local computes = 0
	patch("PathfindingService", "CreatePath", function(_, params)
		local fake = { Status = Enum.PathStatus.NoPath, _points = {}, Blocked = M.newSignal("Blocked") }
		function fake.ComputeAsync(self, start, target)
			computes += 1
			local pts = {}; local n = math.max(1, math.ceil((target - start).Magnitude / 4))
			for i = 0, n do table.insert(pts, start:Lerp(target, i / n)) end
			self.Status = Enum.PathStatus.Success; self._points = pts
		end
		function fake.GetWaypoints(self) local out = {}; for _, p in self._points do table.insert(out, { Position = p }) end; return out end
		return fake
	end)
	local moveTarget = {}
	patch("Humanoid", "MoveTo", function(self, pos) moveTarget[self] = pos end)
	Staff.init()
	local rigs, ops = {}, {}
	for _, f in { office.Employees, office.OperationsEmployees } do for _, m in f:GetChildren() do table.insert(rigs, m) end end
	for _, m in office.OperationsEmployees:GetChildren() do ops[m] = m:GetAttribute("Role") end
	-- what we record: rig Pose / Holding sequences, prop FxUntil writes, server CFrame changes
	local poses, items, writes = {}, {}, { Pose = 0, Holding = 0 }
	local seenPose = {} -- [jobOrRole][pose] = true
	local seenItem = {}
	local function key(m) return ops[m] or m:GetAttribute("RoleId") end
	for _, m in rigs do
		for _, attr in { "Pose", "Holding" } do
			m:GetAttributeChangedSignal(attr):Connect(function()
				writes[attr] += 1
				local v = m:GetAttribute(attr)
				if v ~= nil then
					local tbl = if attr == "Pose" then seenPose else seenItem
					local k = key(m); tbl[k] = tbl[k] or {}; tbl[k][v] = true
				end
			end)
		end
	end
	local propWrites, propUsed = 0, {}
	local fxParts = {}
	for _, root in Collection:GetTagged("PropFx") do
		if root:IsDescendantOf(office) then
			root:GetAttributeChangedSignal("FxUntil"):Connect(function() propWrites += 1; propUsed[root:GetAttribute("PropId") or root.Name] = true end)
			if root:IsA("BasePart") then fxParts[root] = root.CFrame end
			for _, p in root:GetDescendants() do if p:IsA("BasePart") then fxParts[p] = p.CFrame end end
		end
	end
	local faultSeen, faultFixed = 0, 0
	for _, w in Workstations.scan(office).byKind.Computer or {} do
		local screen = w.model:FindFirstChild("DisplayContent")
		if screen then
			screen:GetAttributeChangedSignal("FxState"):Connect(function()
				if screen:GetAttribute("FxState") == "broken" then faultSeen += 1 else faultFixed += 1 end
			end)
		end
	end
	local lunchPhases, eaten, trays, served = {}, 0, 0, 0
	local tableOk, tableChecked = 0, 0
	for _, m in office.Employees:GetChildren() do
		m:GetAttributeChangedSignal("TablePoint"):Connect(function()
			local tp = m:GetAttribute("TablePoint")
			if tp then
				eaten += 1
				-- the plate must sit in front of the reserved seat (Seat:Sit is a no-op in the mock, so compare
				-- with the seat, not the root) and above it at table height
				local rec = Staff.recordOf(m)
				local seat = rec and rec.station and rec.station.seat
				tableChecked += 1
				if seat and (Vector3.new(tp.X, 0, tp.Z) - Vector3.new(seat.Position.X, 0, seat.Position.Z)).Magnitude <= 1.6 and tp.Y > seat.Position.Y + 0.5 and tp.Y < seat.Position.Y + 3 then tableOk += 1 end
			end
		end)
	end
	local function moveAll()
		for _, m in rigs do
			local root = m.PrimaryPart; local h = m:FindFirstChildOfClass("Humanoid"); local goal = moveTarget[h]
			if goal and root and not root.Anchored then
				local here = root.Position; local dd = goal - here; local flat = Vector3.new(dd.X, 0, dd.Z); local len = h.WalkSpeed * .2
				local mv = if flat.Magnitude > len then flat.Unit * len else flat
				local y = here.Y + (if math.abs(dd.Y) > 4 then dd.Y * math.min(1, len / math.max(flat.Magnitude, len)) else 0)
				root.CFrame = CFrame.new(here.X + mv.X, y, here.Z + mv.Z)
			end
		end
	end
	-- conversation hold (TalkService -> Staff.hold / Staff.release)
	local talkHeld, holding, opsHeld = nil, false, nil
	local refusedOffDuty = nil
	local maxMovers, maxQueue, lunchStates = 0, 0, {}
	local maxMoversAt = ""
	local t0 = os.clock()
	for i = 1, TICKS do
		LiftStub.clock += .2
		M.Sched.now += .2
		moveAll()
		Staff.tick(.2)
		if refusedOffDuty == nil and i >= 5 then
			for _, m in office.Employees:GetChildren() do
				if m:GetAttribute("Activity") == "OFF_DUTY" then refusedOffDuty = Staff.hold(m, m.PrimaryPart.Position) == false; break end
			end
		end
		if not talkHeld and i >= 1600 and i % 5 == 0 then
			for _, m in office.Employees:GetChildren() do
				local rec = Staff.recordOf(m)
				if rec and rec.nav and rec.state == "WALKING" and not rec.nav.ticket and rec.lod ~= "sleep" then
					local activity = m:GetAttribute("Activity")
					local okHold = Staff.hold(m, m.PrimaryPart.Position + Vector3.new(0, 0, -4))
					check("talk: hold accepted for a walking employee", okHold == true)
					check("talk: hold stops the route and anchors", rec.nav == nil and m.PrimaryPart.Anchored == true)
					check("talk: hold keeps the Activity", m:GetAttribute("Activity") == activity)
					talkHeld = { m = m, rec = rec, pos = m.PrimaryPart.Position, at = i, activity = activity, arrived = false }
					holding = true
					break
				end
			end
		end
		if talkHeld and i == talkHeld.at + 50 then
			check("talk: held employee stays put", (talkHeld.m.PrimaryPart.Position - talkHeld.pos).Magnitude < 0.01)
			check("talk: held employee keeps its state", talkHeld.m:GetAttribute("Activity") == talkHeld.activity)
			talkHeld.m:GetAttributeChangedSignal("Activity"):Connect(function()
				local a = talkHeld.m:GetAttribute("Activity")
				if a ~= "WALKING" and a ~= "ELEVATOR" then talkHeld.arrived = true end
			end)
			Staff.release(talkHeld.m)
			holding = false
			check("talk: release re-issues the route", talkHeld.rec.nav ~= nil and talkHeld.rec.talkHold == nil)
		end
		if not opsHeld and i >= 1000 then
			for _, m in office.OperationsEmployees:GetChildren() do
				local rec = Staff.recordOf(m)
				local h = m:FindFirstChildOfClass("Humanoid")
				if rec and rec.hop and h then
					check("talk: ops hold accepted", Staff.hold(m, m.PrimaryPart.Position) == true)
					check("talk: ops hop paused in place", moveTarget[h] ~= nil and (moveTarget[h] - m.PrimaryPart.Position).Magnitude < 0.01)
					Staff.release(m)
					check("talk: ops hop walks on after release", (moveTarget[h] - rec.hop.points[rec.hop.i]).Magnitude < 0.01)
					opsHeld = true
					break
				end
			end
		end
		if i % 25 == 0 then
			local rows = Staff.inspect(office)
			local moving = 0
			for _, r in rows do
				if r.navStage then moving += 1 end
				lunchStates[r.state] = (lunchStates[r.state] or 0) + 1
				local isHeld = holding and talkHeld and r.name == talkHeld.rec.name
				if not isHeld and r.lod ~= "sleep" and (r.state == "WALKING" or r.state == "LEAVING") and r.navStage == nil then check("no WALKING without a route", false, r.name) end
			end
			if moving > maxMovers then
				local hist = {}
				for _, r in rows do if r.navStage then local k = r.state .. ":" .. tostring(r.task); hist[k] = (hist[k] or 0) + 1 end end
				local t = {}
				for k, v in hist do table.insert(t, k .. "=" .. v) end
				table.sort(t)
				maxMoversAt = string.format("h=%.2f %s", EmployeeConfig.hour(54 + i * 0.2), table.concat(t, " "))
			end
			maxMovers = math.max(maxMovers, moving)
			local rec = Staff.recordOf(office.Employees:GetChildren()[1])
			local c = rec and rec.cache
			if c and c.lunchQueue then maxQueue = math.max(maxQueue, #c.lunchQueue) end
			if c then trays = math.max(trays, c.trays or 0) end
		end
	end
	local simSeconds = os.clock() - t0
	local minutes = TICKS * 0.2 / 60
	local function seen(k, pose) return seenPose[k] ~= nil and seenPose[k][pose] == true end
	local function held(k, item) return seenItem[k] ~= nil and seenItem[k][item] == true end
	-- integrate (staffops request 10, CORE_SPEC 5.5): an operations post is staffed only from the office stage at
	-- which the economy pays it (EmployeeConfig.POST_FROM_STAGE). Below that stage the job must NOT show up at all.
	local STAGE = d.empire.office
	local postFrom = EmployeeConfig.POST_FROM_STAGE or {}
	local function jobCheck(post, name, ok)
		if STAGE >= (postFrom[post] or 2) then check(name, ok)
		else check(name .. ": nobody (post " .. post .. " is paid from stage " .. postFrom[post] .. ", this is stage " .. STAGE .. ")", not ok) end
	end
	-- operations jobs: visible steps
	check("chef stirs at the range", seen("Chef", "stir"))
	check("chef plates at the pass", seen("Chef", "plate") and held("Chef", "plate"))
	check("barista pours with a cup", seen("Barista", "pour") and held("Barista", "cup"))
	check("barista hands over / wipes", seen("Barista", "reach") and seen("Barista", "wipe"))
	check("kitchen team chops", seen("Kitchen Team", "chop") and held("Kitchen Team", "knife"))
	check("kitchen team washes up", seen("Kitchen Team", "wash"))
	check("kitchen team serves lunch plates", seen("Kitchen Team", "plate") and held("Kitchen Team", "plate"))
	check("receptionists greet", seen("Reception", "greet"))
	check("reception prints badges", held("Reception", "badge"))
	check("security scans on patrol", seen("Security", "scan"))
	jobCheck(4, "garage guard checks the ramp", seen("Security", "inspect"))
	check("IT fixes with a laptop", held("IT Support", "laptop") and seen("IT Support", "typeStand"))
	check("a desk screen broke and got fixed", faultSeen >= 1 and faultFixed >= 1, faultSeen .. "/" .. faultFixed)
	jobCheck(15, "cleaner pushes the mop cart", seen("Cleaner", "push") and held("Cleaner", "mopcart"))
	jobCheck(15, "cleaner wipes", seen("Cleaner", "wipe"))
	jobCheck(16, "mail clerk sorts parcels", seen("Mailroom", "sort") and held("Mailroom", "parcel"))
	jobCheck(16, "mail clerk fills the lockers", seen("Mailroom", "reach"))
	check("fleet plugs in the EVs", seen("Fleet", "plug"))
	check("facilities inspect", seen("Facilities", "inspect"))
	jobCheck(10, "café host greets and wipes tables", seen("Cafe Host", "greet") and seen("Cafe Host", "wipe"))
	check("ops short breaks in place", seen("Reception", "relax") or seen("Security", "relax") or seen("Chef", "relax") or seen("Facilities", "relax"))
	-- props used by the jobs
	for _, id in { "Range", "Pass", "KitchenCoffeeMachine", "KitchenSink", "DishStation", "Servery", "CardPrinter", "MailLockers", "CarLift", "EVCharger2" } do
		if id == "MailLockers" then jobCheck(16, "prop used: " .. id, propUsed[id] == true) -- only the mail clerk uses it
		else check("prop used: " .. id, propUsed[id] == true) end
	end
	-- lunch
	check("employees ate at a table (meal + TablePoint)", eaten >= 5, eaten)
	check("meal plate beside the seat", tableOk == tableChecked, tableOk .. "/" .. tableChecked)
	check("lunch queue formed", maxQueue >= 2, maxQueue)
	check("trays went back to the trolley", trays >= 1 or held("Kitchen Team", "tray"), trays)
	local employeesWithTray = 0
	for k, v in seenItem do if not ops[k] and v.tray then employeesWithTray += 1 end end
	check("employees carried trays", employeesWithTray >= 1, employeesWithTray)
	-- talk package requests: hold / release, lunches served today
	check("talk: hold refused while off duty", refusedOffDuty == true, refusedOffDuty)
	check("talk: a walking employee was held and released", talkHeld ~= nil and not holding)
	check("talk: the released walk reached its goal", talkHeld ~= nil and talkHeld.arrived, talkHeld and talkHeld.rec.state)
	check("talk: an operations hop was paused", opsHeld == true)
	local servedToday = office:GetAttribute("LunchesServed")
	check("LunchesServed counts the plates handed out", typeof(servedToday) == "number" and servedToday > 0 and servedToday >= eaten, tostring(servedToday) .. " vs meals " .. eaten)
	-- breaks and work
	local wellness = false
	for k, v in seenPose do if not EmployeeConfig.ROLES[k] == nil then end; if v.run or v.cycle or v.row or v.lift or v.relax or v.shower then if not table.find({ "Reception", "Security", "Chef", "Facilities", "Barista", "Kitchen Team", "Cafe Host", "IT Support", "Fleet", "Cleaner", "Mailroom" }, k) then wellness = true end end end
	check("wellness break happened (gym / sauna / shower)", wellness)
	check("coffee in hand after a coffee break", held("researcher", "cup") or held("engineer", "cup") or held("curator", "cup") or held("marketer", "cup"))
	check("researchers write on whiteboards (station pose)", seen("researcher", "write") or seen("researcher", "inspect"))
	-- budgets
	local moved = 0
	for p, c in fxParts do if p.Parent and (p.CFrame.Position - c.Position).Magnitude > 1e-6 then moved += 1 end end
	check("no server CFrame writes on PropFx parts", moved == 0, moved)
	local perRigMinute = (writes.Pose + writes.Holding) / #rigs / minutes
	check("rig attribute writes stay rare (< 12 per rig per minute)", perRigMinute < 12, string.format("%.2f", perRigMinute))
	check("prop writes stay rare (< 60 per minute office-wide)", propWrites / minutes < 60, string.format("%.1f", propWrites / minutes))
	check("movers cap respected", maxMovers <= EmployeeConfig.MAX_MOVING_PER_OFFICE, maxMovers .. " at " .. maxMoversAt)
	local states = {}
	for k, v in lunchStates do table.insert(states, k .. "=" .. v) end
	table.sort(states)
	say(string.format("tier %d: %d rigs (%d ops), %.0f s company time in %.1f s, %d path computes, %d props written (%.1f/min), rig writes %.2f/rig/min, meals %d, queue max %d, trays %d, faults %d/%d",
		TIER, #rigs, (function() local n = 0; for _ in ops do n += 1 end; return n end)(), TICKS * 0.2, simSeconds, computes, propWrites, propWrites / minutes, perRigMinute, eaten, maxQueue, trays, faultSeen, faultFixed))
	say("states: " .. table.concat(states, " "))
	local opsPoses = {}
	for k, v in seenPose do if not EmployeeConfig.ROLES[k] or k == "support" then local t = {}; for pose in v do table.insert(t, pose) end; table.sort(t); table.insert(opsPoses, k .. ": " .. table.concat(t, ",")) end end
	table.sort(opsPoses)
	for _, line in opsPoses do say("  " .. line) end
end
setfenv(body, M.envFor(nil))
local ok, err = M.runMain(body, { timeout = 100000, maxSteps = 50000000 })
if not ok then say("ERROR: " .. tostring(err)); failc += 1 end
for name, n in failures do if n > 1 then say(string.format("  (%s failed %d times)", name, n)) end end
say(string.format("life staff: %d passed, %d failed", pass, failc))
if failc > 0 then error("life staff failed", 0) end
