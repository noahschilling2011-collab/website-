--!nocheck
-- Package "life" · client: PropFxController on a real headquarters (registration, home poses, working
-- rule incl. FxStation / gates, every motion kind, emitters / fires / glow / overlays, LOD + reset, one
-- BulkMoveTo per frame, legacy ClusterFan) and EmployeeController (poses, held items, meal plate).
-- Frame signals never fire in the mock, so the test drives Controller.scan / step / flush itself.
-- Run: python3 tests/life/mkharness.py && tools/luau tests/life/test_client.luau -a [tier]
local M = require("../../harness/mock")
M.loadTree(require("./gen_build/manifest"), require("./gen_build/sources"))
M.quiet = true
local G = M.G
local say = print
local args = { ... }
local TIER = tonumber(args[1]) or 2
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
local function finite(c)
	for _, v in { c:GetComponents() } do if v ~= v or v == math.huge or v == -math.huge then return false end end
	return true
end

local function body()
	local Instance, Vector3, CFrame, Color3 = G.Instance, G.Vector3, G.CFrame, G.Color3
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local Services = Server.Services
	local Client = game.StarterPlayer.StarterPlayerScripts.Client
	local Collection = game:GetService("CollectionService")
	local Template = M.require(Server.Lib.Template)
	local EmpireConfig = M.require(RS.Shared.Config.EmpireConfig)
	local Design = M.require(Services.HeadquartersDesign)
	local Rig = M.require(Services.EmployeeRigDesign)
	local PropFx = M.require(Client.Controllers.PropFxController)
	local Employee = M.require(Client.Controllers.EmployeeController)
	local OWNER = 1001
	local cf = CFrame.lookAt(Vector3.new(160, 24, 252), Vector3.new(160, 24, 0))
	local d = Template.new()
	d.company = { name = "Nimbus Labs", logo = "N", color = "cyan", spec = "general", reputation = 10, foundedAt = 0 }
	d.empire.office = M.require(RS.Shared.Config.BuildingPlan).officeForTier(TIER) -- econ: save office index of this plan tier (DATA_VERSION 6)
	local cap = EmpireConfig.OFFICES[d.empire.office].staff
	for k, role in EmpireConfig.ROLES do d.empire.employees[role.id] = math.floor(cap / #EmpireConfig.ROLES) + (if k <= cap % #EmpireConfig.ROLES then 1 else 0) end
	local session = { userId = OWNER, player = { Name = "Tester", DisplayName = "Tester", UserId = OWNER }, data = d, live = {} }
	local office = Design.build(cf, session, Color3.fromRGB(120, 154, 129))
	local plots = Instance.new("Folder"); plots.Name = "Plots"; plots.Parent = G.workspace
	local plot = Instance.new("Model"); plot.Name = "Plot_01"; plot.Parent = plots
	office.Parent = plot
	-- capture the batched CFrame writes
	local batches = {}
	local function patch(cls, name, fn) M.IMPL[cls].methods[name] = fn; M.classInfo(cls).methods[name] = fn end
	patch("Workspace", "BulkMoveTo", function(_, parts, cframes, mode)
		table.insert(batches, { n = #parts, mode = mode })
		for i, p in parts do p.CFrame = cframes[i] end
	end)
	local camera = G.workspace.CurrentCamera
	local function now() return G.workspace:GetServerTimeNow() end
	local function frames(seconds, at)
		local parts, cfs = {}, {}
		if at then camera.CFrame = cf * CFrame.new(at) end
		PropFx.scan(camera.CFrame.Position, parts, cfs)
		PropFx.flush(parts, cfs)
		local n = math.max(1, math.floor(seconds * 60))
		for _ = 1, n do
			M.Sched.now += 1 / 60
			table.clear(parts); table.clear(cfs)
			PropFx.step(now(), parts, cfs)
			PropFx.flush(parts, cfs)
		end
	end
	local function byId(id)
		for _, r in Collection:GetTagged("PropFx") do if r:IsDescendantOf(office) and r:GetAttribute("PropId") == id then return r end end
		return nil
	end

	------------------------------------------------------------------ registration
	local tagged, registered = 0, 0
	for _, tag in { "PropFx", "ClusterFan" } do
		for _, r in Collection:GetTagged(tag) do
			if r:IsDescendantOf(office) then
				if PropFx.register(r) then registered += 1 end
				if tag == "PropFx" then tagged += 1 end
			end
		end
	end
	local reg = 0
	for _ in PropFx.registry() do reg += 1 end
	check("every PropFx root registers once", reg == tagged, reg .. " vs " .. tagged)
	-- home pose captured client-side
	local lift = byId("CarLift")
	local p = PropFx.registry()[lift]
	check("car lift registered with moving parts", p and #p.moving >= 8, p and #p.moving)
	local body = lift:FindFirstChild("CarBody")
	local home = body.CFrame

	------------------------------------------------------------------ car lift: FxUntil raises, expiry lowers
	lift:SetAttribute("FxUntil", now() + 3)
	batches = {}
	frames(1.5, Vector3.new(30, -12, 60))
	check("lift active near the camera", p.active and p.near)
	check("car raised by FxTravel", math.abs((body.CFrame.Position - home.Position).Y - 2.9) < 0.05, (body.CFrame.Position - home.Position).Y)
	check("one BulkMoveTo per frame", #batches <= 91 and #batches >= 1, #batches)
	check("BulkMoveTo with FireCFrameChanged", batches[1] and batches[1].mode == G.Enum.BulkMoveMode.FireCFrameChanged)
	frames(3.0)
	check("car back home after FxUntil", (body.CFrame.Position - home.Position).Magnitude < 1e-3, (body.CFrame.Position - home.Position).Magnitude)
	check("posts never move", lift:FindFirstChild("LiftPost").CFrame.Position == lift:FindFirstChild("LiftPost").CFrame.Position)

	------------------------------------------------------------------ range: flame, steam, glow
	local range = byId("Range")
	local rp = PropFx.registry()[range]
	range:SetAttribute("FxUntil", now() + 2)
	frames(0.5, Vector3.new(63, 6, 44))
	local fires, emit = 0, 0
	for _, f in rp.fires do if f.Enabled then fires += 1 end end
	for _, e in rp.emitters do if e.Enabled then emit += 1 end end
	check("range flames on while cooking", fires == #rp.fires and fires > 0, fires)
	check("pan steams while cooking", emit == #rp.emitters and emit > 0, emit)
	check("burners glow", rp.glow[1] and rp.glow[1].part.Material == G.Enum.Material.Neon)
	frames(2.0)
	fires, emit = 0, 0
	for _, f in rp.fires do if f.Enabled then fires += 1 end end
	for _, e in rp.emitters do if e.Enabled then emit += 1 end end
	check("range off after FxUntil", fires == 0 and emit == 0)
	check("burner colour restored", rp.glow[1].part.Color == rp.glow[1].color)

	------------------------------------------------------------------ station link: treadmill belt follows OccupiedBy
	local belt = nil
	for _, r in Collection:GetTagged("PropFx") do if r:IsDescendantOf(office) and r:GetAttribute("Machine") == 1 then belt = r end end
	local bp = PropFx.registry()[belt]
	local station = office:FindFirstChild(belt:GetAttribute("FxStation"), true)
	check("treadmill station found", station ~= nil)
	local stripe = belt:FindFirstChild("BeltStripe")
	local s0 = stripe.CFrame
	frames(0.5, Vector3.new(-70, 6, 112))
	check("idle belt does not move", (stripe.CFrame.Position - s0.Position).Magnitude < 1e-6)
	station:SetAttribute("OccupiedBy", 7)
	frames(0.4)
	local moved = (stripe.CFrame.Position - s0.Position).Magnitude
	check("belt runs while the station is occupied", moved > 0.01 and moved <= 0.81, moved)
	station:SetAttribute("OccupiedBy", nil)

	------------------------------------------------------------------ gates: Training fans + blades, Lift sheave, Meeting puck
	office:SetAttribute("Training", true)
	local fan = nil
	for _, r in Collection:GetTagged("PropFx") do if r:IsDescendantOf(office) and r.Name == "ClusterFan" then fan = r; break end end
	local f0 = fan.CFrame
	frames(0.3, cf:PointToObjectSpace(fan.Position) + Vector3.new(0, 0, 4))
	check("cluster fan spins while training", (fan.CFrame.LookVector - f0.LookVector).Magnitude > 1e-3 or (fan.CFrame.RightVector - f0.RightVector).Magnitude > 1e-3)
	check("fan rotates in place", (fan.CFrame.Position - f0.Position).Magnitude < 1e-4)
	local blade = nil
	for _, r in Collection:GetTagged("PropFx") do if r:IsDescendantOf(office) and r.Name == "RackBlade" then blade = r; break end end
	blade:SetAttribute("Lit", true)
	frames(1.0, cf:PointToObjectSpace(blade.Position) + Vector3.new(4, 0, 0))
	check("lit blade breathes while training", blade.Transparency > 0.001, blade.Transparency)
	office:SetAttribute("Training", false)
	frames(0.3)
	check("blade solid again after training", blade.Transparency == 0, blade.Transparency)
	local sheave = office:FindFirstChild("Sheave", true)
	if sheave then
		local cabin = office:FindFirstChild("Lift") and office.Lift:FindFirstChild("LiftCabin")
		check("lift cabin present", cabin ~= nil)
		local sh0 = sheave.CFrame
		frames(0.3, cf:PointToObjectSpace(sheave.Position) + Vector3.new(4, 0, 0))
		check("sheave still while the lift waits", (sheave.CFrame.UpVector - sh0.UpVector).Magnitude < 1e-6)
		cabin:SetAttribute("LiftState", "MOVING")
		frames(0.4)
		check("sheave turns while the cabin moves", (sheave.CFrame.UpVector - sh0.UpVector).Magnitude > 1e-3)
		cabin:SetAttribute("LiftState", "IDLE")
	end
	local puck = nil
	for _, r in Collection:GetTagged("PropFx") do if r:IsDescendantOf(office) and r.Name == "Speakerphone" then puck = r; break end end
	if puck then
		local pp = PropFx.registry()[puck]
		frames(0.2, cf:PointToObjectSpace(puck.Position) + Vector3.new(3, 2, 0))
		check("speakerphone ring at rest colour without meeting", pp.glow[1].part.Color == pp.glow[1].color)
		office:SetAttribute("MeetingRoom", puck:GetAttribute("FxMeeting")); office:SetAttribute("MeetingUntil", now() + 60)
		frames(0.3)
		check("speakerphone ring lit during its meeting", pp.glow[1].part.Color == puck:GetAttribute("FxColor") and pp.glow[1].part.Material == G.Enum.Material.Neon)
		office:SetAttribute("MeetingUntil", now() - 1)
	end

	------------------------------------------------------------------ hinge (locker), arm, screen overlay, paper
	local lockers = byId("MailLockers")
	local lp = PropFx.registry()[lockers]
	local door = lp.moving[1].part
	local d0 = door.CFrame
	lockers:SetAttribute("FxUntil", now() + 2)
	frames(0.8, cf:PointToObjectSpace(door.Position) + Vector3.new(4, 0, 0))
	local swung = math.deg(math.acos(math.clamp(door.CFrame.LookVector:Dot(d0.LookVector), -1, 1)))
	check("locker door swings ~109°", math.abs(swung - math.deg(1.9)) < 3, swung)
	check("door swings out of the locker (-Z side)", d0:PointToObjectSpace(door.Position).Z < -0.3, d0:PointToObjectSpace(door.Position).Z)
	frames(2.5)
	check("locker closed again", (door.CFrame.Position - d0.Position).Magnitude < 1e-3)
	local arm = byId("RobotArm1")
	local ap = PropFx.registry()[arm]
	local base, fore = arm:FindFirstChild("ArmBase"), arm:FindFirstChild("ArmFore")
	local b0, fo0 = base.CFrame, fore.CFrame
	arm:SetAttribute("FxUntil", now() + 5)
	frames(2.0, cf:PointToObjectSpace(base.Position) + Vector3.new(4, 0, 0))
	check("arm base stays", (base.CFrame.Position - b0.Position).Magnitude < 1e-6)
	check("forearm moves", (fore.CFrame.Position - fo0.Position).Magnitude > 0.05, (fore.CFrame.Position - fo0.Position).Magnitude)
	local upper = arm:FindFirstChild("ArmUpper")
	local shoulder = arm:GetPivot() * arm:GetAttribute("FxJoint2") -- joints live in pivot space
	check("upper arm keeps its shoulder pivot", math.abs((upper.CFrame.Position - shoulder.Position).Magnitude - 1.2) < 0.01, (upper.CFrame.Position - shoulder.Position).Magnitude)
	frames(5)
	check("arm back home", (fore.CFrame.Position - fo0.Position).Magnitude < 1e-3)
	local ev = byId("EVCharger2")
	local ep = PropFx.registry()[ev]
	ev:SetAttribute("FxUntil", now() + 2)
	frames(0.3, cf:PointToObjectSpace(ev.Position) + Vector3.new(0, 0, 3))
	check("EV charger overlay CHARGING", ep.overlay ~= nil and ep.overlay:FindFirstChild("FxText") and ep.overlay.FxText.Text == "CHARGING")
	ev:SetAttribute("FxState", "broken")
	frames(0.3)
	check("broken overlay", ep.overlay ~= nil and string.find(ep.overlay.FxText.Text, "FAULT") ~= nil)
	ev:SetAttribute("FxState", "idle"); ev:SetAttribute("FxUntil", 0)
	frames(0.3)
	check("overlay removed when idle", ep.overlay == nil)
	local printer = byId("CardPrinter")
	local pr = PropFx.registry()[printer]
	printer:SetAttribute("FxUntil", now() + 3)
	frames(0.5, cf:PointToObjectSpace(printer.Position) + Vector3.new(0, 0, 3))
	check("printer feeds a client sheet", pr.sheet ~= nil and pr.sheet.Parent ~= nil)
	frames(3.5)
	check("sheet removed after printing", pr.sheet == nil)

	------------------------------------------------------------------ LOD + reset
	camera.CFrame = cf * CFrame.new(30, -12, 60)
	lift:SetAttribute("FxUntil", now() + 30)
	frames(1.0)
	local raised = body.CFrame.Position
	check("lift raised before leaving", (raised - home.Position).Y > 1)
	frames(0.6, Vector3.new(30, 200, 60)) -- far away
	check("prop reset to home when out of range", (body.CFrame.Position - home.Position).Magnitude < 1e-3)
	check("out-of-range prop inactive", not p.active)
	lift:SetAttribute("FxUntil", 0)
	local active, near = 0, 0
	camera.CFrame = cf * CFrame.new(-60, -12, 20) -- data hall: the busiest spot
	PropFx.scan(camera.CFrame.Position)
	for _, q in PropFx.active() do active += 1; if q.near then near += 1 end end
	check("active set bounded", active > 0 and active < 400, active)
	local t0 = os.clock()
	for _ = 1, 60 do M.Sched.now += 1 / 60; local a, b = PropFx.step(now()); PropFx.flush(a, b) end
	say(string.format("tier %d: %d props registered, data-hall active set %d (near %d), 60 frames in %.1f ms (mock Luau)", TIER, reg, active, near, (os.clock() - t0) * 1000))

	------------------------------------------------------------------ legacy ClusterFan only
	local legacy = Instance.new("Part"); legacy.Name = "OldFan"; legacy.Anchored = true; legacy.CanCollide = false
	legacy.CFrame = cf * CFrame.new(0, 3, 0); legacy:SetAttribute("FanHome", legacy.CFrame); legacy.Parent = office
	Collection:AddTag(legacy, "ClusterFan")
	local lpf = PropFx.register(legacy)
	check("legacy ClusterFan registers as spin gated by Training", lpf and lpf.kinds.spin and lpf.gate == "Training")

	------------------------------------------------------------------ EmployeeController
	local names = { "type", "typeStand", "stir", "pour", "plate", "chop", "wash", "wipe", "push", "carry", "write", "reach", "inspect", "scan", "greet", "sort", "plug", "run", "cycle", "row", "lift", "relax", "eat", "phone", "shower" }
	for _, name in names do
		for _, sitting in { false, true } do
			for _, t in { 0, 1.37, 9.9 } do
				local tr = Employee.pose("WORKING", sitting, false, 1000 + t, 4242, false, name)
				local n = 0
				for joint, c in tr do n += 1; check("pose " .. name .. " finite", finite(c), joint) end
				check("pose " .. name .. " sets 6 joints", n == 6, n)
			end
		end
	end
	local run1 = Employee.pose("COFFEE_BREAK", false, false, 1000.1, 1, false, "run")
	local run2 = Employee.pose("COFFEE_BREAK", false, false, 1000.4, 1, false, "run")
	check("run pose moves the legs", run1["Left Hip"] ~= run2["Left Hip"])
	-- conversation (talk package request): the head turns by lookYaw, the arms gesture unless typing seated
	local talk = Employee.pose("WORKING", false, false, 1000.2, 7, false, "stir", true, 0.6)
	local _, ny = talk.Neck:ToEulerAnglesXYZ()
	local talkAx = talk.Neck:ToAxisAngle()
	check("talking: neck turned towards the player", math.abs(ny - 0.6) < 1e-6 and math.abs(talkAx.Y) > 0.99, ny)
	local stirArm = Employee.pose("WORKING", false, false, 1000.2, 7, false, "stir")["Right Shoulder"]
	check("talking: gesture replaces the job pose", talk["Right Shoulder"] ~= stirArm)
	local typingTalk = Employee.pose("WORKING", true, false, 1000.2, 7, false, "type", true, -0.4)
	local typingArm = Employee.pose("WORKING", true, false, 1000.2, 7, false, "type")["Right Shoulder"]
	check("talking seated at a desk keeps typing", typingTalk["Right Shoulder"] == typingArm)
	local noTalk = Employee.pose("WORKING", false, false, 1000.2, 7, false, "stir")
	local _, ny0 = noTalk.Neck:ToEulerAnglesXYZ()
	check("not talking: no head turn", math.abs(ny0 - 0.6) > 0.1)
	check("derive: whiteboard -> write", Employee.derive("RESEARCH", false, "Whiteboard", nil) == "write")
	check("derive: lab bench -> inspect", Employee.derive("RESEARCH", false, "LabBench", nil) == "inspect")
	check("derive: seated with a meal -> eat", Employee.derive("LUNCH", true, "Dining", "meal") == "eat")
	local scratch = Instance.new("Folder"); scratch.Parent = G.workspace
	local m = Rig.build(scratch, OWNER, 5, "engineer", cf * CFrame.new(0, 3, 0))
	local cache = { joints = {}, parts = {}, next = 0, hidden = false, holding = nil, items = {}, meal = {}, mealAt = nil }
	Employee.hold(m, cache, "tray")
	local arm2 = m:FindFirstChild("Right Arm")
	check("tray rendered as client parts welded to the right arm", #cache.items == 2 and cache.items[1]:FindFirstChildOfClass("WeldConstraint").Part0 == arm2)
	check("held parts never collide / query", not cache.items[1].CanCollide and not cache.items[1].CanQuery and cache.items[1].Massless)
	Employee.hold(m, cache, "mopcart")
	check("mop cart welded to the root", #cache.items == 3 and cache.items[1]:FindFirstChildOfClass("WeldConstraint").Part0 == m.PrimaryPart)
	Employee.hold(m, cache, nil)
	check("items cleared", #cache.items == 0)
	Employee.meal(cache, cf * Vector3.new(40, 3.2, -18))
	check("meal plate on the table", #cache.meal == 2 and cache.meal[1].Anchored and (cache.meal[1].Position - cf * Vector3.new(40, 3.25, -18)).Magnitude < 0.1)
	Employee.meal(cache, nil)
	check("meal cleared", #cache.meal == 0)
end
setfenv(body, M.envFor(nil))
local ok, err = M.runMain(body, { timeout = 600 })
if not ok then say("ERROR: " .. tostring(err)); failc += 1 end
for name, n in failures do if n > 1 then say(string.format("  (%s failed %d times)", name, n)) end end
say(string.format("life client: %d passed, %d failed", pass, failc))
if failc > 0 then error("life client failed", 0) end
