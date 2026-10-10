--!nocheck
-- LiftService against the real CoreDesign geometry inside the headless Roblox mock.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_lift && tools/luau tests/lift_service.luau
-- The mock has no physics: the test emulates the PrismaticConstraint servo (moves the cabin
-- toward TargetPosition, writes CurrentPosition), Weld.C0 on the door leaves, riders being
-- carried by the floor, and NPCs walking to ticket.target.
local M = require("../harness/mock")
local manifest = require("../harness/.gen_lift/manifest")
local sources = require("../harness/.gen_lift/sources")
M.loadTree(manifest, sources)
M.quiet = true
local KEY, G = M.KEY, M.G
local game = M.game

local passed, failed = 0, 0
local function check(cond, name)
	if cond then passed += 1 else failed += 1; print("FAIL: " .. name) end
end

local function find(path)
	local cur = game
	for seg in path:gmatch("[^%.]+") do cur = cur:FindFirstChild(seg); assert(cur, path) end
	return cur
end

local function body()
	local CFrame, Vector3, Instance, Enum, Color3 = G.CFrame, G.Vector3, G.Instance, G.Enum, G.Color3
	local workspace = G.workspace
	local Players = game:GetService("Players")
	local PhysicsService = game:GetService("PhysicsService")
	local Plan = M.require(find("ReplicatedStorage.Shared.Config.BuildingPlan"))
	local Core = M.require(find("ServerScriptService.Server.Services.CoreDesign"))
	local Lift = M.require(find("ServerScriptService.Server.Services.LiftService"))
	local Logic = M.require(find("ServerScriptService.Server.Services.LiftLogic"))

	-- rotated plot: everything must work in building-local coordinates
	local cf = CFrame.new(160, 24, 252) * CFrame.Angles(0, math.rad(180), 0)
	local tier = 4
	local office = Instance.new("Model")
	office.Name = "Office"
	office:SetAttribute("OwnerUserId", 1001)
	office:SetAttribute("OfficeTier", tier)
	office:SetAttribute("FloorCount", Plan.floors(tier))
	office:SetAttribute("CampusCFrame", cf)
	Core.build({ office = office, cf = cf, tier = tier, floors = Plan.floors(tier), owner = 1001, accent = Color3.new(0.5, 0.8, 0.7), company = "Nimbus", folders = {} })
	local plots = Instance.new("Folder"); plots.Name = "Plots"; plots.Parent = workspace
	local plot = Instance.new("Model"); plot.Name = "Plot_01"; plot.Parent = plots
	office.Parent = plot
	local employees = Instance.new("Folder"); employees.Name = "Employees"; employees.Parent = office

	-- fake players ------------------------------------------------------------------
	local fakePlayers, allowed = {}, {}
	M.classInfo("Players").methods.GetPlayers = function() return table.clone(fakePlayers) end
	local function character(name, at)
		local model = Instance.new("Model"); model.Name = name
		local root = Instance.new("Part"); root.Name = "HumanoidRootPart"; root.Size = Vector3.new(2, 2, 1); root.CFrame = CFrame.new(at); root.Parent = model
		local humanoid = Instance.new("Humanoid"); humanoid.Health = 100; humanoid.Parent = model
		model.PrimaryPart = root
		return model, root
	end
	local function newPlayer(name, userId, at, card)
		local p = M.newInstance("Player")
		p[KEY].props.Name = name
		p[KEY].props.UserId = userId
		local model, root = character(name, at)
		model.Parent = workspace
		p[KEY].props.Character = model
		p.Parent = Players
		table.insert(fakePlayers, p)
		allowed[p] = card
		return p, root
	end
	local function world(v) return cf * v end -- building-local -> world
	local function loc(p) return cf:PointToObjectSpace(p) end

	-- AABB stand-in for Workspace:GetPartBoundsInBox so the shaft safety net can be exercised
	local function aabb(c, size)
		local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, sx in { -0.5, 0.5 } do for _, sy in { -0.5, 0.5 } do for _, sz in { -0.5, 0.5 } do
			local p = c * Vector3.new(size.X * sx, size.Y * sy, size.Z * sz)
			lo, hi = lo:Min(p), hi:Max(p)
		end end end
		return lo, hi
	end
	M.classInfo("Workspace").methods.GetPartBoundsInBox = function(_, c, size, params)
		local qlo, qhi = aabb(c, size)
		local out = {}
		for _, root in params.FilterDescendantsInstances do
			for _, d in root:GetDescendants() do
				if d:IsA("BasePart") then
					local lo, hi = aabb(d.CFrame, d.Size)
					if lo.X < qhi.X and hi.X > qlo.X and lo.Y < qhi.Y and hi.Y > qlo.Y and lo.Z < qhi.Z and hi.Z > qlo.Z then table.insert(out, d) end
				end
			end
		end
		return out
	end
	local before = {}
	for _, d in office:GetDescendants() do if d:IsA("BasePart") then before[d] = d.CollisionGroup end end

	Lift.init(function(player, owner) return owner == 1001 and allowed[player] == true end)
	check(Lift.attach(office), "attach succeeds on CoreDesign geometry")
	check(Lift.attach(office), "attach is idempotent")

	local lift = office.Lift
	local cabin = lift.LiftCabin
	local floor = cabin.CabinFloor
	local prismatic = floor:FindFirstChild("LiftPrismatic")
	check(prismatic ~= nil and prismatic.ActuatorType == Enum.ActuatorType.Servo and prismatic.LimitsEnabled, "servo prismatic created")
	check(prismatic and prismatic.Attachment0.Parent == lift.LiftGuide and prismatic.Attachment1.Parent == floor, "prismatic between LiftGuide and CabinFloor")
	local up = cf.UpVector
	check(prismatic and (prismatic.Attachment0.WorldCFrame.RightVector - up).Magnitude < 1e-6, "prismatic axis is building up")
	check(prismatic and math.abs(prismatic.TargetPosition - 16) < 1e-6, "cabin at G = 16 studs above B1")
	check(prismatic and math.abs(prismatic.LowerLimit - (-0.5)) < 1e-6 and math.abs(prismatic.UpperLimit - (16 + 16 * Plan.roofLevel(tier) + 0.5)) < 1e-6, "limits from B1 to roof")
	check(prismatic and prismatic.ServoMaxForce > 2e4 and prismatic.Speed == Logic.VMAX + 1, "servo force/speed")
	local unanchored, welded, groups = true, 0, true
	for _, d in cabin:GetDescendants() do
		if d:IsA("BasePart") then
			unanchored = unanchored and not d.Anchored
			groups = groups and d.CollisionGroup == "LiftCabin"
			if d.CustomPhysicalProperties == nil then groups = false end
		elseif d.Name == "LiftWeld" then welded += 1 end
	end
	check(unanchored, "all cabin parts unanchored")
	check(groups, "all cabin parts in LiftCabin with light physical properties")
	check(welded > 20, "cabin parts welded to the floor (" .. welded .. ")")
	check(cabin.CabinDoorL:FindFirstChild("LiftLeafWeld") ~= nil and cabin.CabinDoorL.LiftLeafWeld:IsA("Weld"), "door leaves on animatable Welds")
	check(PhysicsService:CollisionGroupsAreCollidable("LiftCabin", "LiftShaft") == false, "LiftCabin never collides with LiftShaft")
	local shaftOk = true
	for _, d in office.Core:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("LiftShaft") and d.CollisionGroup ~= "LiftShaft" then shaftOk = false end
	end
	check(shaftOk and lift.Landing_3.DoorL.CollisionGroup == "LiftShaft", "LiftShaft parts in their group")
	local intruders = {}
	for d in before do
		if d.CollisionGroup == "LiftShaft" and not d:GetAttribute("LiftShaft") then table.insert(intruders, d:GetFullName()) end
	end
	check(#intruders == 0, "CoreDesign leaves the cabin's travel volume clear (" .. table.concat(intruders, ", ") .. ")")

	-- emulation ---------------------------------------------------------------------
	local riders = {} -- roots carried by the floor
	local npcs = {} -- [model] = ticket
	local stuck = false
	local function servo(dt)
		if not cabin.Parent or not prismatic.Parent then return end
		local att0, att1 = prismatic.Attachment0, prismatic.Attachment1
		local pos = (att1.WorldPosition - att0.WorldPosition):Dot(up)
		if not stuck then
			local err = prismatic.TargetPosition - pos
			local move = math.clamp(err * math.min(1, 30 * dt), -prismatic.Speed * dt, prismatic.Speed * dt)
			if move ~= 0 then
				cabin:PivotTo(cabin:GetPivot() + up * move)
				for root in riders do root.CFrame = root.CFrame + up * move end
				pos += move
			end
		end
		prismatic[KEY].props.CurrentPosition = pos
		for _, leaf in { cabin.CabinDoorL, cabin.CabinDoorR } do
			leaf.CFrame = floor.CFrame * leaf.LiftLeafWeld.C0
		end
	end
	local npcMoved = false
	local function walk(dt)
		for npc, t in npcs do
			local root = npc.HumanoidRootPart
			local info = Lift.npcTicket(t)
			local target = if info.state == "riding" then nil else info.target -- EmployeeNavigation stands still while riding
			if info.state == "riding" then riders[root] = true end
			if target then
				local d = target - root.Position
				local flat = Vector3.new(d.X, 0, d.Z)
				local stepLen = math.min(flat.Magnitude, 8 * dt)
				if stepLen > 1e-3 then
					root.CFrame = root.CFrame + flat.Unit * stepLen
				end
				-- stand on the cabin floor / landing floor
				local inCab = Lift.isPassenger(office, npc)
				if inCab then riders[root] = true else riders[root] = nil end
			end
		end
	end
	local function tick(seconds, untilFn)
		local t = 0
		while t < seconds do
			servo(0.05)
			walk(0.05)
			local before = {}
			for npc in npcs do before[npc] = npc.HumanoidRootPart.Position end
			Lift.tick(0.05)
			for npc, p in before do if (npc.HumanoidRootPart.Position - p).Magnitude > 1e-9 then npcMoved = true end end
			t += 0.05
			if untilFn and untilFn() then return true end
		end
		return false
	end
	local function state() return Lift.inspect(office) end
	local function at(stateName, level) return function() local s = state(); return s.state == stateName and (level == nil or s.level == level) end end

	-- 1. hall call by an authorized player at landing 3 ------------------------------
	local alice, aliceRoot = newPlayer("Alice", 2001, world(Vector3.new(0, Plan.levelY(3) + 3, 48)), true)
	local bob, bobRoot = newPlayer("Bob", 2002, world(Vector3.new(8, Plan.levelY(3) + 3, 46)), false)
	local ok, err = Lift.hallCall(bob, office, 3)
	check(not ok and err == "CARD_REQUIRED", "hall call without card refused")
	ok, err = Lift.hallCall(alice, office, 3)
	check(ok and err == nil, "hall call accepted")
	check(Lift.hallCall(alice, office, 3) == true and #state().queue.hall == 1, "repeated hall call deduplicated")
	local landing3 = lift.Landing_3
	check((landing3.DoorL.CFrame.Position - landing3.DoorL:GetAttribute("ClosedCFrame").Position).Magnitude < 1e-6, "landing door stays shut while the cabin is away")
	tick(2)
	check(state().state == "MOVING" and state().direction == 1, "cabin travels up")
	check(landing3.DoorL.CanCollide, "landing door still closed during travel")
	check(tick(15, at("DOORS_OPEN", 3)), "cabin arrives and opens at 3")
	check(math.abs(loc(floor.Position).Y + 0.25 - Plan.levelY(3)) < 0.11, "floor level with landing 3")
	check((landing3.DoorL.CFrame.Position - landing3.DoorL:GetAttribute("OpenCFrame").Position).Magnitude < 1e-6 and not landing3.DoorL.CanCollide, "landing 3 doors open, non-colliding")
	local leafWeld = cabin.CabinDoorL.LiftLeafWeld
	check((leafWeld.C0.Position - cabin.CabinDoorL:GetAttribute("OpenOffset").Position).Magnitude < 1e-6, "cabin leaf slid open via Weld.C0")
	local other = lift.Landing_2
	check(other.DoorL.CanCollide and (other.DoorL.CFrame.Position - other.DoorL:GetAttribute("ClosedCFrame").Position).Magnitude < 1e-6, "other landings stay closed")
	tick(0.3)
	local disp = landing3.Indicator.Display
	check(disp.Status.Text == "3 · " .. Plan.levelName(tier, 3) and disp.Level.Text == "3", "landing indicator shows level and floor name (" .. disp.Status.Text .. ")")
	check(cabin.CabinDisplay.Display.Level.Text == "3", "cabin display level")
	check(cabin:GetAttribute("CurrentLevel") == 3, "CurrentLevel attribute")

	-- 2. door zone: Alice stands in the doorway ---------------------------------------
	aliceRoot.CFrame = CFrame.new(world(Vector3.new(0, Plan.levelY(3) + 3, 54)))
	tick(8)
	check(state().state == "DOORS_OPEN", "occupied doorway keeps doors open")
	-- 3. remote from inside: Alice steps in and picks 5 -----------------------------
	aliceRoot.CFrame = CFrame.new(world(Vector3.new(-2, Plan.levelY(3) + 3, 62)))
	riders[aliceRoot] = true
	check(Lift.isPassenger(office, alice.Character) and Lift.riding(alice.Character) and Lift.riding(alice), "Alice is a passenger")
	local panel = Lift.panel(alice, office)
	check(panel.passenger and panel.current == 3 and #panel.stops == #Plan.liftStops(tier) and panel.ownerId == 1001, "panel payload")
	local allAllowed = true
	for _, s in panel.stops do allAllowed = allAllowed and s.allowed and type(s.label) == "string" and type(s.name) == "string" end
	check(allAllowed, "card holder may choose every stop")
	local bobPanel = Lift.panel(bob, office)
	check(not bobPanel.passenger and not bobPanel.stops[1].allowed, "no card: stops disabled")
	local r = Lift.remote({ player = alice }, { ownerId = 1001, floor = 5 })
	check(r.ok and r.kind == "car", "remote from inside = car call")
	check(Lift.remote({ player = alice }, { ownerId = 1001, floor = 5.5 }).err == "BAD_INPUT", "non-integer floor rejected")
	check(Lift.remote({ player = alice }, { ownerId = 1001, floor = 42 }).err == "BAD_INPUT", "unknown floor rejected")
	check(Lift.remote({ player = alice }, { ownerId = "x", floor = 1 }).err == "BAD_INPUT", "bad owner type rejected")
	check(Lift.remote({ player = alice }, { ownerId = 999, floor = 1 }).err == "PLAYER_OFFLINE", "unknown owner")
	check(Lift.carCall(bob, office, 1) == false, "non-passenger car call refused")
	check(tick(12, at("MOVING")), "departs with Alice once the doorway is clear")
	check(landing3.DoorL.CanCollide and (landing3.DoorL.CFrame.Position - landing3.DoorL:GetAttribute("ClosedCFrame").Position).Magnitude < 1e-6, "landing 3 shut and colliding after departure")
	check(cabin.CabinDoorL.CanCollide, "cabin leaves collide while travelling")
	check(tick(12, at("DOORS_OPEN", 5)), "arrives at 5")
	check(math.abs(loc(aliceRoot.Position).Y - (Plan.levelY(5) + 3)) < 0.2, "Alice was carried to 5 (no teleport needed)")

	-- 4. overload: 7 people inside -----------------------------------------------------
	local crowd = {}
	for i = 1, 6 do
		local p, root = newPlayer("Guest" .. i, 3000 + i, world(Vector3.new(-4 + (i % 3) * 3, Plan.levelY(5) + 3, 58 + (i // 3) * 3)), true)
		riders[root] = true
		crowd[i] = { p, root }
	end
	Lift.carCall(alice, office, -1)
	tick(10)
	check(state().state == "DOORS_OPEN" and state().full and state().riders == 7, "overload holds the doors (riders " .. tostring(state().riders) .. ")")
	tick(0.3)
	check(cabin.CabinDisplay.Display.Status.Text == "FULL – please step out", "cabin display FULL")
	check(lift.Landing_5.Indicator.Display.Status.Text == "FULL", "landing display FULL")
	for i = 1, 6 do
		local root = crowd[i][2]
		riders[root] = nil
		root.CFrame = CFrame.new(world(Vector3.new(-12 + i * 3, Plan.levelY(5) + 3, 40)))
	end
	check(tick(8, at("MOVING")), "leaves once the load is fine")

	-- 5. landing call with a destination (remote from the lobby) --------------------
	bob.Parent = nil
	table.remove(fakePlayers, table.find(fakePlayers, bob))
	local carol, carolRoot = newPlayer("Carol", 2003, world(Vector3.new(3, Plan.levelY(1) + 3, 47)), true)
	local rc = Lift.remote({ player = carol }, { ownerId = 1001, floor = 6 })
	check(rc.ok and rc.kind == "hall" and rc.level == 1, "remote from the lobby = hall call at that landing")
	check(Lift.remote({ player = carol }, { ownerId = 1001, floor = 6 }).ok, "second identical remote is harmless")
	check(tick(40, at("DOORS_OPEN", 1)), "cabin picks Carol up at 1 on its way down (collective)")
	check(table.find(state().queue.car, -1) ~= nil, "Alice's car call to -1 still pending")
	riders[aliceRoot] = nil
	aliceRoot.CFrame = CFrame.new(world(Vector3.new(0, Plan.levelY(1) + 3, 40))) -- Alice got off at -1 earlier; park her away
	carolRoot.CFrame = CFrame.new(world(Vector3.new(2, Plan.levelY(1) + 3, 63)))
	riders[carolRoot] = true
	tick(0.2)
	check(table.find(state().queue.car, 6) ~= nil, "remembered destination becomes a car call on boarding")
	local order = {}
	check(tick(50, function()
		local st = state()
		if st.state == "DOORS_OPENING" and order[#order] ~= st.level then table.insert(order, st.level) end
		return st.state == "DOORS_OPEN" and st.level == 6
	end), "Carol arrives at 6")
	check(table.concat(order, ",") == "-1,6", "continues down to -1 first, then reverses to 6 (" .. table.concat(order, ",") .. ")")
	check(math.abs(loc(carolRoot.Position).Y - (Plan.levelY(6) + 3)) < 0.2, "Carol carried to 6")
	riders[carolRoot] = nil
	carolRoot.CFrame = CFrame.new(world(Vector3.new(2, Plan.levelY(6) + 3, 44)))
	tick(6)

	-- 6. NPC ticket: G -> 2 -------------------------------------------------------------
	local npc, npcRoot = character("Eve", world(Vector3.new(-16, Plan.levelY(0) + 3, 40)))
	npc:SetAttribute("RoleId", "engineer")
	npc.Parent = employees
	check(Lift.npcCall(office, npc, 0, 0) == nil, "same-level ticket refused")
	local ticket = Lift.npcCall(office, npc, 0, 2)
	check(ticket and ticket.state == "waiting" and ticket.fromLevel == 0 and ticket.toLevel == 2 and ticket.target, "ticket waiting with a target")
	check(Lift.npcCall(office, npc, 0, 2) == ticket, "identical request returns the same ticket")
	local wait = loc(ticket.target)
	check(math.abs(wait.Z - 48) < 1e-6 and math.abs(wait.Y - (Plan.levelY(0) + 3)) < 1e-6, "target = wait point")
	npcs[npc] = ticket
	local seen = { [ticket.state] = true }
	local okRide = tick(60, function()
		seen[ticket.state] = true
		return ticket.state == "done" or ticket.state == "failed"
	end)
	check(okRide and ticket.state == "done", "NPC journey completes (state " .. ticket.state .. ")")
	check(seen.board and seen.riding and seen.exit, "NPC went through board/riding/exit")
	check(math.abs(loc(npcRoot.Position).Y - (Plan.levelY(2) + 3)) < 0.3, "NPC arrived on level 2")
	check(loc(npcRoot.Position).Z < 52, "NPC left the cabin")
	check(not npcMoved, "LiftService never moved the NPC")
	npcs[npc] = nil
	riders[npcRoot] = nil

	-- 7. NPC ticket timeout when the NPC never shows up ---------------------------------
	local lazy = character("Lazy", world(Vector3.new(-60, Plan.levelY(4) + 3, 0)))
	lazy:SetAttribute("RoleId", "curator")
	lazy.Parent = employees
	local lt = Lift.npcCall(office, lazy, 4, 1)
	check(lt ~= nil, "second ticket")
	tick(47)
	check(lt.state == "failed", "waiting > 45 s -> failed (" .. lt.state .. ")")
	local denied = Lift.npcCall(office, lazy, 4, -1)
	check(denied ~= nil, "curator may go to the B1 lobby (staff)")
	if denied then Lift.npcCancel(denied) end
	check(denied == nil or denied.state == "failed", "cancelled ticket failed")

	-- 8. detach mid-ride: evacuation + cleanup -------------------------------------------
	aliceRoot.CFrame = CFrame.new(world(Vector3.new(0, Plan.levelY(state().level) + 3, 40)))
	tick(1)
	Lift.hallCall(alice, office, state().level == 0 and 1 or 0)
	tick(15, function() return state().state == "DOORS_OPEN" end)
	local lvl = state().level
	aliceRoot.CFrame = CFrame.new(world(Vector3.new(-1, Plan.levelY(lvl) + 3, 62)))
	riders[aliceRoot] = true
	local target = lvl == 6 and 2 or 6
	Lift.carCall(alice, office, target)
	local ghostNpc = character("Ghost", world(Vector3.new(5, Plan.levelY(3) + 3, 46)))
	ghostNpc:SetAttribute("RoleId", "researcher")
	ghostNpc.Parent = employees
	local gt = Lift.npcCall(office, ghostNpc, 3, 0)
	tick(12, at("MOVING"))
	tick(1.5)
	check(state().state == "MOVING", "mid-ride before detach")
	Lift.detach(office)
	local a = loc(aliceRoot.Position)
	check(math.abs(a.Z - 44) < 1e-6 and math.abs((a.Y - 3) % 16) < 1e-6, "rider evacuated to a landing exit point")
	check(gt and gt.state == "failed", "tickets failed on detach")
	check(floor:FindFirstChild("LiftPrismatic") == nil and floor.Anchored, "constraints removed, cabin anchored in place")
	check(Lift.inspect(office).attached == false, "record forgotten")
	riders[aliceRoot] = nil

	-- 9. re-attach after detach, then sweep after destroy -----------------------------
	check(Lift.attach(office), "re-attach after detach works")
	local s2 = state()
	check(s2.attached and s2.state == "IDLE", "fresh record idles at the nearest level")
	tick(4)
	local parked = false
	for _, stop in Plan.liftStops(tier) do
		if math.abs(state().position - (stop.y + 16)) < 0.11 then parked = true end
	end
	check(state().state == "IDLE" and parked, "parks level with a stop")
	office:Destroy()
	tick(1.2)
	check(Lift.inspect(office).attached == false, "destroyed office dropped by the sweep")

	-- 10. stall -> out of service -> evacuation ----------------------------------------
	local office2 = Instance.new("Model"); office2.Name = "Office"
	office2:SetAttribute("OwnerUserId", 1001); office2:SetAttribute("OfficeTier", 2); office2:SetAttribute("CampusCFrame", CFrame.new(0, 0, 0))
	Core.build({ office = office2, cf = CFrame.new(0, 0, 0), tier = 2, floors = Plan.floors(2), owner = 1001, accent = Color3.new(1, 1, 1), company = "X", folders = {} })
	local structure = Instance.new("Folder"); structure.Name = "Structure"; structure.Parent = office2
	local slab = Instance.new("Part"); slab.Name = "BadSlab"; slab.Anchored = true; slab.Size = Vector3.new(40, 1, 40); slab.CFrame = CFrame.new(0, 31.5, 60); slab.Parent = structure
	local rail = Instance.new("Part"); rail.Name = "Railing"; rail.Anchored = true; rail.Size = Vector3.new(4, 4, 1); rail.CFrame = CFrame.new(0, 2, 40); rail.Parent = structure
	office2.Parent = plot
	check(Lift.attach(office2), "tier 2 attach")
	check(slab.CollisionGroup == "LiftShaft" and slab.CanCollide, "slab across the shaft moved to LiftShaft (players still collide)")
	check(rail.CollisionGroup == "Default", "parts outside the shaft untouched")
	cabin = office2.Lift.LiftCabin; floor = cabin.CabinFloor; prismatic = floor.LiftPrismatic; cf = CFrame.new(0, 0, 0); up = cf.UpVector; office = office2
	aliceRoot.CFrame = CFrame.new(1, 3, 62); riders[aliceRoot] = true
	Lift.carCall(alice, office2, Plan.roofLevel(2))
	tick(3)
	stuck = true
	tick(Logic.STALL_TIME * 2 + 1.5)
	check(state().state == "OUT_OF_SERVICE", "two stalls -> out of service (" .. state().state .. ")")
	check(loc(aliceRoot.Position).Z == 44, "stranded rider evacuated")
	check(Lift.hallCall(alice, office2, 0) == false, "calls refused while out of service")
	tick(0.3)
	check(office2.Lift.Landing_0.Indicator.Display.Status.Text == "Out of service", "indicators show Out of service")
	stuck = false
	riders[aliceRoot] = nil
	tick(Logic.RECOVER_TIME + 4)
	check(state().state == "IDLE", "recovers and parks")
	Lift.detach(office2)
end

setfenv(body, M.envFor(nil))
local ok, res = M.runMain(body, { timeout = 3000, maxSteps = 5000000 })
if not ok then print("ERROR: " .. tostring(res)); failed += 1 end
print(string.format("lift_service: %d passed, %d failed", passed, failed))
if failed > 0 then error("lift_service tests failed") end
