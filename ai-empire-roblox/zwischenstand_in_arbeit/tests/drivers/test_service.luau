--!nocheck
-- drivers package: DriverService in the headless mock with a controlled server clock (real PlotService,
-- CityService state, PhoneService, VehicleService, EmployeeRigDesign; HQ generator / doors stubbed).
--   published folders + rig templates (driver uniform with cap, chauffeur with gloves), drivers == CompanyOps' paid
--   drivers for stages 1..5 (+ announcement on an upgrade), ride lifecycle (request -> car comes -> waits ->
--   board -> ride -> drop-off at the door -> back to the garage -> driver free), the held character (anchored,
--   below the car, moved once per second, streamed ahead), onArrive callback / listener / BindableEvent exactly
--   once, garage barrier through Doors.requestNPC, the founder's own car borrowed and given back, cancel in every
--   state, wait expiry, player leaves mid-ride, respawn mid-ride, queueing with one driver (honest ETA, starts by
--   itself), abroad limousine, field rides (city self-drive + parked until the trip ends, abroad with chauffeur /
--   self-drive, hosted guests, founder trips stay data, trips under way at join stay data), phone hook answers for
--   every state + the destination sheet, remote validation and limits, no per-tick writes.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_drivers && cd tests/drivers && ../../tools/luau test_service.luau -a .gen_drivers
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_drivers")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
for path, src in require("../world/stubs") do sources[path] = src end
M.loadTree(manifest, sources)
M.quiet = true
local G = M.G
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local makeFixture = require("../world/fixture")
local function body()
	local Instance, Vector3, CFrame, Enum = G.Instance, G.Vector3, G.CFrame, G.Enum
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local S = Server.Services
	local F = makeFixture(M, G)
	local Remote = M.require(Server.Lib.Remote)
	local Session = M.require(S.SessionService)
	local CityPlan = M.require(RS.Shared.Config.CityPlan)
	local Drive = M.require(RS.Shared.DrivePlan)
	local Ops = M.require(RS.Shared.CompanyOps)
	-- controlled server clock
	local T = 1.7e9
	M.IMPL.Workspace.methods.GetServerTimeNow = function() return T end
	if M.classInfo("Workspace").methods then M.classInfo("Workspace").methods.GetServerTimeNow = function() return T end end
	check("server clock patched", game.Workspace:GetServerTimeNow() == T)
	-- HQ generator + doors stubbed (PlotService runs for real); the stub office carries the garage barrier door
	local Design = M.require(S.HeadquartersDesign)
	Design.build = function(cf, session, accent)
		local m = Instance.new("Model"); m.Name = "Office"
		m:SetAttribute("OfficeTier", Design.tierFor(session)); m:SetAttribute("OwnerUserId", session.userId)
		local door = Instance.new("Model"); door.Name = "Door_SITE_BARRIER"; door:SetAttribute("DoorId", "SITE_BARRIER"); door.Parent = m
		return m
	end
	Design.staff = function() end
	local Doors = M.require(S.DoorService)
	local npcCalls = {}
	Doors.register = function() end; Doors.unregister = function() end
	Doors.find = function(office, id) return office:FindFirstChild("Door_" .. id) end
	Doors.requestNPC = function(npc, door) table.insert(npcCalls, { npc = npc, door = door, t = T }); return true end
	local Lift = M.require(S.LiftService); Lift.attach = function() end; Lift.detach = function() end
	local Plot = M.require(S.PlotService)
	local City = M.require(S.CityService)
	local Phone = M.require(S.PhoneService)
	local Vehicles = M.require(S.VehicleService)
	local Driver = M.require(S.DriverService)
	Plot.init()
	Driver.init()
	-- the functional checks below call the remote back to back: generous per-action buckets here, the real limits
	-- are checked at the end
	local LIMITS = { write = table.clone(Driver.LIMITS.write), read = table.clone(Driver.LIMITS.read), other = table.clone(Driver.LIMITS.other) }
	for k in LIMITS do Driver.LIMITS[k] = { 1e6, 1e6 } end

	local function advance(seconds, step)
		step = step or 0.25
		local left = seconds
		while left > 1e-9 do
			local d = math.min(step, left)
			T += d
			Driver.tick(d)
			left -= d
		end
	end
	local function notices(p)
		local out = {}
		for _, f in Remote.fired do
			if f.player == p and f.name == "Notify" and f.args[1] == "CAMPUS_NOTICE" then table.insert(out, f.args[2].text) end
		end
		return out
	end
	local function lastNotice(p)
		local n = notices(p)
		return n[#n] or ""
	end
	local function sheets(p)
		local out = {}
		for _, f in Remote.fired do if f.player == p and f.name == "Notify" and f.args[1] == "DRIVE_SHEET" then table.insert(out, f.args[2]) end end
		return out
	end
	local function newPlayer(id, name, stage, cf)
		local p = F.player(id, name, cf or CFrame.new(0, 27.5, 0))
		local s = F.session(p, 500000)
		s.data.empire.office = stage
		table.insert(Session.sessions, s)
		for _, fn in Session.loaded do fn(s) end
		return p, s
	end
	local function close(p, s)
		p.Parent = nil
		s.closed = true
		for _, fn in Session.closing do fn(s) end
		local i = table.find(Session.sessions, s)
		if i then table.remove(Session.sessions, i) end
	end
	local function hqPoint(p, local3)
		local plot = Plot.get(p)
		return plot.cframe:PointToWorldSpace(local3)
	end
	local function standAt(p, pos)
		p.root.CFrame = CFrame.new(pos)
	end
	local act = Remote.binds.TripAction

	------------------------------------------------------------------ published root
	local root = RS:FindFirstChild("CompanyDrivers")
	check("ReplicatedStorage.CompanyDrivers published", root ~= nil and root:IsA("Folder") and root:FindFirstChild("Limo") ~= nil)
	local chauffeur = root and root:FindFirstChild("Chauffeur")
	local function rigInfo(m)
		local parts, prompts, names = 0, 0, {}
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then parts += 1; names[d.Name] = d end
			if d:IsA("ProximityPrompt") then prompts += 1 end
		end
		return parts, prompts, names
	end
	if chauffeur then
		local parts, prompts, names = rigInfo(chauffeur)
		check("chauffeur: cap with band and visor, tie, jacket, white gloves", names.DriverCap and names.CapBand and names.CapVisor and names.Tie and names.Blazer
			and names.Hand and names.Hand.Color == G.Color3.fromRGB(238, 238, 234))
		check("chauffeur rig within the part budget, no talk prompt, not an employee", parts <= 22 and prompts == 0 and not chauffeur:HasTag("CompanyEmployee"), parts)
		check("chauffeur role", chauffeur:GetAttribute("Role") == "Chauffeur")
	else
		check("chauffeur template", false)
	end
	check("TripAction bound with company gate, outer spam limit and per-action limits", act ~= nil and Remote.limits.TripAction.company == true and Remote.limits.TripAction.burst <= 40
		and LIMITS.write[1] <= 8 and LIMITS.write[2] <= 3 and LIMITS.read[1] >= LIMITS.write[1] and LIMITS.other[1] <= 10)
	check("phone driver hook registered", Phone.hasAction("driver"))

	------------------------------------------------------------------ drivers == CompanyOps' paid drivers, stages 1..5
	local Economy = { applyFlow = function() end, spend = function() return true end, grant = function() end }
	local stagePlayers = {}
	for stage = 1, 5 do
		local p, s = newPlayer(6000 + stage, "Stage" .. stage, stage)
		stagePlayers[stage] = { p = p, s = s }
	end
	M.settle(1)
	advance(1.1)
	for stage = 1, 5 do
		local sp = stagePlayers[stage]
		local folder = root:FindFirstChild("Drivers_" .. sp.p.UserId)
		Ops.step(sp.s, 1, Economy, 9 * 90)
		local paid = sp.s.live.ops and sp.s.live.ops.drivers
		local templates = 0
		local capped = true
		if folder then
			for _, ch in folder:GetChildren() do
				if ch:IsA("Model") and string.match(ch.Name, "^Driver%d$") then
					templates += 1
					local _, prompts, names = rigInfo(ch)
					if not (names.DriverCap and names.Tie and prompts == 0 and ch:GetAttribute("Role") == "Driver") then capped = false end
				end
			end
		end
		check("stage " .. stage .. ": published drivers == CompanyOps paid (" .. tostring(paid) .. ")", folder and folder:GetAttribute("Drivers") == paid and templates == paid,
			folder and tostring(folder:GetAttribute("Drivers")) .. "/" .. templates)
		check("stage " .. stage .. ": driver templates wear the uniform with cap", capped)
		local free, why = Driver.free(sp.p)
		check("stage " .. stage .. ": free() = " .. tostring(paid), free == paid and (paid > 0 or why == "NO_DRIVER"), tostring(free) .. " " .. tostring(why))
	end
	local f2 = root:FindFirstChild("Drivers_" .. stagePlayers[2].p.UserId)
	check("driver names published", typeof(f2:GetAttribute("DriverName1")) == "string" and #f2:GetAttribute("DriverName1") > 3 and f2:GetAttribute("DriverName2") == nil)
	check("company folder: plot, tier, livery", f2:GetAttribute("Plot") == Plot.get(stagePlayers[2].p).index and f2:GetAttribute("Tier") == 1 and G.typeof(f2:GetAttribute("Livery")) == "Color3", tostring(f2:GetAttribute("Plot")) .. " " .. tostring(f2:GetAttribute("Tier")) .. " " .. G.typeof(f2:GetAttribute("Livery")))
	-- garage stage: the phone says why there is no driver
	local h1 = Driver.phoneHook(stagePlayers[1].s, {})
	check("phone (garage): 'Your first driver joins at the Founder Headquarters'", h1.ok and string.find(h1.text, "Your first driver joins at the Founder Headquarters", 1, true) ~= nil, h1.text)
	check("phone (garage): no destination sheet", h1.sheet == false and #sheets(stagePlayers[1].p) == 0)
	local viaPhone = Phone._act(stagePlayers[1].s, { action = "call", contact = "driver" })
	check("PhoneService routes the Driver contact to the hook", viaPhone.ok and viaPhone.contact == "driver" and viaPhone.soon ~= true and string.find(viaPhone.text, "Founder Headquarters", 1, true) ~= nil, viaPhone.text)
	local r1 = Driver.request(stagePlayers[1].p, { to = "airport_departures" })
	check("garage: request refused NO_DRIVER", not r1.ok and r1.err == "NO_DRIVER", r1.err)
	-- upgrade 1 -> 2: the first driver joins (announced)
	stagePlayers[1].s.data.empire.office = 2
	Plot.refresh(stagePlayers[1].s)
	advance(1.1)
	local f1 = root:FindFirstChild("Drivers_" .. stagePlayers[1].p.UserId)
	check("upgrade to stage 2: one driver template", f1:GetAttribute("Drivers") == 1 and f1:FindFirstChild("Driver1") ~= nil)
	check("upgrade announced on the phone/notice", string.find(lastNotice(stagePlayers[1].p), "first company driver", 1, true) ~= nil, lastNotice(stagePlayers[1].p))
	for stage = 1, 5 do close(stagePlayers[stage].p, stagePlayers[stage].s) end
	advance(1.1)
	check("closed sessions: company folders removed", #root:GetChildren() == 2, #root:GetChildren())

	------------------------------------------------------------------ the main ride (stage 2, one driver)
	local p, s = newPlayer(7001, "Ava", 2)
	M.settle(1)
	advance(1.1)
	local plot = Plot.get(p)
	local cf = plot.cframe
	local folder = root:FindFirstChild("Drivers_7001")
	check("Ava's company folder", folder ~= nil and folder:GetAttribute("Drivers") == 1)
	-- phone when the driver is free: text + sheet
	standAt(p, hqPoint(p, Vector3.new(0, 3, -60)))
	local hf = Driver.phoneHook(s, {})
	check("phone (free): the driver answers 'Where to?'", hf.ok and string.find(hf.text, "Where to?", 1, true) ~= nil, hf.text)
	local sh = sheets(p)[#sheets(p)]
	check("destination sheet sent (Notify DRIVE_SHEET)", sh ~= nil and sh.canBook == true and sh.pickup == "hq_entrance" and sh.zone == "home")
	local hasAirport, hasHQ, hasClient = false, false, false
	if sh then
		for _, it in sh.places do
			if it.id == "airport_departures" and it.title == "To the airport" and it.eta > 30 then hasAirport = true end
			if it.id == "hq_entrance" then hasHQ = true end
			if it.id == "clouddesk" then hasClient = true end
		end
	end
	check("sheet: 'To the airport' with an ETA, client buildings, no 'Back to HQ' at the HQ", hasAirport and hasClient and not hasHQ)
	-- request
	T += 10
	local res = Driver.request(p, { to = "airport_departures", purpose = "itinerary", onArrive = function(id, place) end })
	check("request ok", res.ok and typeof(res.rideId) == "string" and res.pickup == "hq_entrance" and res.to == "airport_departures" and not res.queued, res.err)
	local legA = Drive.leg("hq_garage", "hq_entrance", plot.index)
	local legB = Drive.leg("hq_entrance", "airport_departures", plot.index)
	check("honest ETA = driver walk + garage -> entrance", math.abs(res.eta - math.ceil(Drive.walkAt(T) + legA.dur)) <= 1, res.eta)
	check("arrive ETA adds the ride", math.abs(res.arriveEta - math.ceil(Drive.walkAt(T) + legA.dur + Drive.BOARD_DELAY + legB.dur)) <= 2, res.arriveEta)
	local rideId = res.rideId
	local rf = folder:FindFirstChild("Ride_1")
	check("ride folder published", rf ~= nil and rf:GetAttribute("Id") == rideId and rf:GetAttribute("Kind") == "founder" and rf:GetAttribute("Driver") == 1
		and rf:GetAttribute("State") == "coming" and rf:GetAttribute("Rider") == 7001 and rf:GetAttribute("Look") == "fleet")
	local segs = Drive.decode(rf:GetAttribute("Plan"), plot.index)
	check("plan: one leg garage -> entrance after the walk", segs and #segs == 1 and segs[1].from == "hq_garage" and segs[1].to == "hq_entrance" and math.abs(segs[1].t0 - (T + Drive.walkAt(T))) < 0.01 and segs[1].who == "D")
	check("DriveRide player attribute", p:GetAttribute("DriveRide") == rideId)
	check("free() = 0 while the only driver is out", (Driver.free(p)) == 0)
	local again = Driver.request(p, { to = "clouddesk" })
	check("second request while riding: ALREADY_RIDING", not again.ok and again.err == "ALREADY_RIDING", again.err)
	local st = Driver.status(p)
	check("status coming with ETA", st.state == "coming" and st.eta and st.eta > 0 and st.rideId == rideId)
	-- phone while coming
	local hc = Driver.phoneHook(s, {})
	check("phone (coming): on the way to the HQ entrance", string.find(hc.text, "is on the way to the HQ entrance", 1, true) ~= nil, hc.text)
	-- no per-tick writes while nothing changes
	local writes = 0
	local conn = rf.AttributeChanged:Connect(function() writes += 1 end)
	local pw = p.attrWrites
	advance(2)
	check("no ride attribute writes per tick", writes == 0, writes)
	check("no player attribute writes per tick", p.attrWrites == pw)
	-- garage barrier: the proxy asks DoorService while the car passes the ramp head
	table.clear(npcCalls)
	local arriveAt = segs[1].t0 + legA.dur
	advance(arriveAt - T - 0.1)
	check("barrier opened through Doors.requestNPC (driver proxy in the office)", #npcCalls >= 1 and npcCalls[1].npc.Name == "DriverProxy"
		and npcCalls[1].npc:GetAttribute("RoleId") == "support" and npcCalls[1].npc.Parent == plot.office and npcCalls[1].door.Name == "Door_SITE_BARRIER", #npcCalls)
	check("barrier requests are spaced (>= 1 s) and bounded", #npcCalls <= 7, #npcCalls)
	check("still coming just before the arrival", rf:GetAttribute("State") == "coming")
	advance(0.5)
	check("car waits at the pick-up", rf:GetAttribute("State") == "waiting" and math.abs(rf:GetAttribute("WaitUntil") - (T + Drive.WAIT)) < 0.6)
	local prompts = game.Workspace:FindFirstChild("DrivePrompts")
	local promptPart = prompts and prompts:FindFirstChild("DrivePrompt_7001")
	local prompt = promptPart and promptPart:FindFirstChild("DrivePrompt")
	check("owner-only 'Get in' prompt at the waiting car", prompt and prompt.ActionText == "Get in" and prompt:GetAttribute("OwnerUserId") == 7001 and prompt:GetAttribute("RideId") == rideId)
	check("waiting notice", string.find(lastNotice(p), "is waiting for you at the HQ entrance", 1, true) ~= nil, lastNotice(p))
	local hw = Driver.phoneHook(s, {})
	check("phone (waiting)", string.find(hw.text, "is waiting for you at the HQ entrance", 1, true) ~= nil, hw.text)
	-- boarding: too far, then beside the car
	standAt(p, hqPoint(p, Vector3.new(0, 3, -60)))
	local b1 = act(s, { action = "ride", op = "board" })
	check("board from far away refused TOO_FAR", not b1.ok and b1.err == "TOO_FAR", b1.err)
	local carCF = Drive.endCF(legA)
	standAt(p, carCF * Vector3.new(6, 3, 2))
	local b2 = act(s, { action = "ride", op = "board" })
	check("board beside the car", b2.ok, b2.err)
	check("riding", rf:GetAttribute("State") == "riding" and promptPart.Parent == nil)
	segs = Drive.decode(rf:GetAttribute("Plan"), plot.index)
	check("plan: entrance -> airport with the founder, back to the garage", segs and #segs == 3 and segs[2].from == "hq_entrance" and segs[2].to == "airport_departures"
		and segs[2].who == "D,R" and math.abs(segs[2].t0 - (T + Drive.BOARD_DELAY)) < 0.01 and segs[3].to == "hq_garage" and segs[3].who == "D")
	check("character held: anchored, name hidden", p.root.Anchored == true and p.humanoid.DisplayDistanceType == Enum.HumanoidDisplayDistanceType.None)
	check("held below the road under the car", math.abs(p.root.Position.Y - (CityPlan.GROUND - Driver.HOLD_DEPTH)) < 0.5 and Drive.flat(p.root.Position, carCF.Position) < 1)
	local hr = Driver.phoneHook(s, {})
	check("phone (riding): 'on the way to City Airport (departures)'", string.find(hr.text, "on the way to City Airport (departures)", 1, true) ~= nil, hr.text)
	-- the hold follows the car once per second
	local pw2 = p.attrWrites
	advance(Drive.BOARD_DELAY + legB.dur / 2)
	local pose = Drive.pose(segs, plot.index, T)
	check("hold follows the car (<= 1 s behind)", pose and Drive.flat(p.root.Position, pose.cf.Position) < Drive.SPEED.road * 1.1 + 1, pose and Drive.flat(p.root.Position, pose.cf.Position))
	check("no player attribute writes during the ride", p.attrWrites == pw2)
	local streamedBefore = #p.streamed
	local arrivedCount, listenerCount, eventCount = 0, 0, 0
	local cbArgs, lArgs = nil, nil
	-- (the request's onArrive was a no-op closure: re-request below checks the callback; here listener + event)
	local disconnect = Driver.onArrive(function(pl, id, place) listenerCount += 1; lArgs = { pl, id, place } end)
	local evConn = Driver.arrived.Event:Connect(function(pl, id, place) eventCount += 1 end)
	local rideEnd = segs[2].t0 + legB.dur
	advance(rideEnd - T - 1)
	check("destination streamed before the drop-off", #p.streamed > streamedBefore and (p.streamed[#p.streamed].pos - Drive.place("airport_departures").door.Position).Magnitude < 0.01)
	check("not dropped before the car stops", p.root.Anchored == true and listenerCount == 0)
	advance(1 + Driver.ALIGHT + 0.3)
	local door = Drive.place("airport_departures").door
	check("founder placed at the departures door", (p.root.Position - door.Position).Magnitude < 0.6, p.root.Position)
	check("released: unanchored, name tag back", p.root.Anchored == false and p.humanoid.DisplayDistanceType ~= Enum.HumanoidDisplayDistanceType.None)
	check("onArrive listener + BindableEvent once with (player, rideId, place)", listenerCount == 1 and eventCount == 1 and lArgs[1] == p and lArgs[2] == rideId and lArgs[3] == "airport_departures")
	check("returning", rf:GetAttribute("State") == "returning" and p:GetAttribute("DriveRide") == nil)
	segs = Drive.decode(rf:GetAttribute("Plan"), plot.index)
	check("the founder is out of the car at the kerb (seat emptied)", segs and segs[2].who == "D")
	advance(5)
	check("listener not fired twice", listenerCount == 1 and eventCount == 1)
	check("the driver is still busy while driving back", (Driver.free(p)) == 0)
	local backEnd = segs[3].t0 + Drive.leg("airport_departures", "hq_garage", plot.index).dur
	advance(backEnd - T + 0.5)
	check("back in the garage: ride removed, driver free", rf.Parent == nil and (Driver.free(p)) == 1)
	disconnect()

	------------------------------------------------------------------ per-request onArrive callback, from Business City back to the HQ
	local cd = Drive.place("clouddesk")
	standAt(p, cd.door.Position)
	T += 5
	local cbCount, cbId, cbPlace = 0, nil, nil
	local rb = Driver.request(p, { to = "hq_entrance", passengers = { { name = "Mia Chen", role = "marketer", seed = 1111 } }, onArrive = function(id, place) cbCount += 1; cbId = id; cbPlace = place end })
	check("request from CloudDesk back to the HQ", rb.ok and rb.pickup == "clouddesk" and rb.to == "hq_entrance", rb.err)
	local rf2 = folder:FindFirstChild("Ride_2")
	check("companion template in the ride folder", rf2 and rf2:FindFirstChild("C1") and rf2.C1:GetAttribute("CompanionName") == "Mia Chen" and rf2:GetAttribute("Companions") == 1)
	local sg2 = Drive.decode(rf2:GetAttribute("Plan"), plot.index)
	local legC = Drive.leg("hq_garage", "clouddesk", plot.index)
	advance(sg2[1].t0 + legC.dur - T + 0.3)
	standAt(p, Drive.endCF(legC) * Vector3.new(5, 3, 2))
	check("board at CloudDesk", act(s, { action = "ride", op = "board" }).ok)
	sg2 = Drive.decode(rf2:GetAttribute("Plan"), plot.index)
	check("companion rides along (D,R,C1)", sg2[2].who == "D,R,C1")
	check("drop-off at the HQ uses the inbound lane, then back via the drop side", sg2[3].from == "hq_entrance" and sg2[3].side == "drop")
	advance(sg2[2].t0 + Drive.leg("clouddesk", "hq_entrance", plot.index).dur - T + Driver.ALIGHT + 0.3)
	local alight = cf * Drive.HQ.alight
	check("dropped at the HQ alight point", (p.root.Position - alight.Position).Magnitude < 0.6, p.root.Position)
	check("per-request onArrive once with (rideId, 'hq_entrance')", cbCount == 1 and cbId == rb.rideId and cbPlace == "hq_entrance")
	sg2 = Drive.decode(rf2:GetAttribute("Plan"), plot.index)
	-- the companion gets out with him: off the next leg (the client shows her standing at the door while the car waits)
	check("companion out of the car too (founder off the ride leg, companion only up to the door)", sg2[2].who == "D,,C1" and sg2[3].who == "D" and rf2:GetAttribute("Rider") == 0, sg2[2].who)
	advance(Drive.planEnd(sg2, plot.index) - T + 0.5)
	check("ride 2 done", rf2.Parent == nil)

	------------------------------------------------------------------ cancel in every state
	local atHQ = hqPoint(p, Vector3.new(0, 3, -60))
	standAt(p, atHQ)
	T += 5
	local c1 = Driver.request(p, { to = "airport_departures" })
	check("cancel request 1 ok", c1.ok)
	local ok1 = Driver.cancel(c1.rideId)
	check("cancel while the driver walks to the car: ride gone at once", ok1 and folder:FindFirstChild("Ride_3") == nil and (Driver.free(p)) == 1 and p:GetAttribute("DriveRide") == nil)
	T += 5
	local c2 = Driver.request(p, { to = "airport_departures" })
	advance(Drive.walkAt(T) + 4)
	local ok2 = Driver.cancel(c2.rideId)
	local rf4 = folder:FindFirstChild("Ride_4")
	local sg4 = rf4 and Drive.decode(rf4:GetAttribute("Plan"), plot.index)
	check("cancel on the way: car turns back after reaching the pick-up", ok2 and rf4 and rf4:GetAttribute("State") == "returning" and sg4 and #sg4 == 2 and sg4[2].from == "hq_entrance" and sg4[2].to == "hq_garage")
	local ok2b, why2b = Driver.cancel(c2.rideId)
	check("returning car cannot be cancelled", not ok2b and why2b == "RETURNING")
	advance(Drive.planEnd(sg4, plot.index) - T + 0.5)
	check("ride 4 done", rf4.Parent == nil)
	T += 5
	local c3 = Driver.request(p, { to = "airport_departures" })
	local rf5 = folder:FindFirstChild("Ride_5")
	advance(Drive.walkAt(T) + legA.dur + 1)
	check("ride 5 waiting", rf5:GetAttribute("State") == "waiting")
	local ok3 = act(s, { action = "ride", op = "cancel" })
	check("cancel while waiting (remote): car turns back, prompt removed", ok3.ok and rf5:GetAttribute("State") == "returning" and game.Workspace.DrivePrompts:FindFirstChild("DrivePrompt_7001") == nil)
	advance(Drive.planEnd(Drive.decode(rf5:GetAttribute("Plan"), plot.index), plot.index) - T + 0.5)
	T += 5
	local c4 = Driver.request(p, { to = "clouddesk" })
	local rf6 = folder:FindFirstChild("Ride_6")
	advance(Drive.walkAt(T) + legA.dur + 1)
	standAt(p, Drive.endCF(legA) * Vector3.new(5, 3, 2))
	check("board ride 6", act(s, { action = "ride", op = "board" }).ok)
	local legCD = Drive.leg("hq_entrance", "clouddesk", plot.index)
	advance(Drive.BOARD_DELAY + legCD.dur * 0.55)
	local sg6 = Drive.decode(rf6:GetAttribute("Plan"), plot.index)
	local carNow = Drive.pose(sg6, plot.index, T)
	local cbBefore = listenerCount
	local ok4 = Driver.cancel(c4.rideId)
	check("cancel mid-ride: ok", ok4)
	check("let out beside the road near the car", not p.root.Anchored and not CityPlan.onRoad(p.root.Position, 0) and Drive.flat(p.root.Position, carNow.cf.Position) < 62,
		tostring(p.root.Position) .. " car " .. tostring(carNow.cf.Position))
	sg6 = Drive.decode(rf6:GetAttribute("Plan"), plot.index)
	check("car drives on empty (founder removed from the seats)", rf6:GetAttribute("State") == "returning" and sg6[2].who == "D" and sg6[3].to == "hq_garage")
	advance(Drive.planEnd(sg6, plot.index) - T + 0.5)
	check("cancelled ride: no arrival fired", listenerCount == cbBefore and rf6.Parent == nil)

	------------------------------------------------------------------ waiting too long
	standAt(p, atHQ)
	T += 5
	local w1 = Driver.request(p, { to = "airport_departures" })
	local rf7 = folder:FindFirstChild("Ride_7")
	advance(Drive.walkAt(T) + legA.dur + 1)
	advance(Drive.WAIT + 0.5)
	check("unboarded car drives back after WAIT (+ notice)", rf7:GetAttribute("State") == "returning" and string.find(lastNotice(p), "drove back", 1, true) ~= nil, lastNotice(p))
	advance(Drive.planEnd(Drive.decode(rf7:GetAttribute("Plan"), plot.index), plot.index) - T + 0.5)
	check("ride 7 done", rf7.Parent == nil)
	local _ = w1

	------------------------------------------------------------------ respawn mid-ride
	T += 5
	local rs1 = Driver.request(p, { to = "airport_departures" })
	local rf8 = folder:FindFirstChild("Ride_8")
	advance(Drive.walkAt(T) + legA.dur + 1)
	standAt(p, Drive.endCF(legA) * Vector3.new(5, 3, 2))
	act(s, { action = "ride", op = "board" })
	advance(5)
	local newChar = F.respawn(p, CFrame.new(0, 27.5, 0))
	advance(0.5)
	check("respawn mid-ride: the car goes on without him", rf8:GetAttribute("State") == "returning" and not string.find(Drive.decode(rf8:GetAttribute("Plan"), plot.index)[2].who, "R", 1, true))
	check("the new character is not touched", p.root.Anchored == false and p.Character == newChar)
	advance(Drive.planEnd(Drive.decode(rf8:GetAttribute("Plan"), plot.index), plot.index) - T + 0.5)
	check("ride 8 done", rf8.Parent == nil)
	local _r = rs1

	------------------------------------------------------------------ the founder's own car is borrowed and given back
	local spawnRes = Vehicles.spawn(s, {})
	check("founder's car spawned in the garage", spawnRes.ok and Vehicles.cars[7001] ~= nil, spawnRes.err)
	check("parked on site", Vehicles.parkedOnSite(p) == "compact")
	standAt(p, atHQ)
	T += 5
	local own = Driver.request(p, { to = "airport_departures" })
	local rf9 = folder:FindFirstChild("Ride_9")
	check("the chauffeur takes the founder's own car (look = compact, physical car stowed)", own.ok and rf9:GetAttribute("Look") == "compact" and Vehicles.cars[7001] == nil)
	local okc = Driver.cancel(own.rideId)
	check("cancel before leaving gives the car back at once", okc and Vehicles.cars[7001] ~= nil)

	------------------------------------------------------------------ queueing with one driver (a field ride takes the driver)
	-- an abroad pilot trip appears: the free chauffeur takes the field rep to the airport
	local e = s.data.empire
	e.employees.marketer = 2
	e.staffProfiles = e.staffProfiles or {}
	e.staffProfiles.marketer = { { n = "Leo Park", s = 2222 }, { n = "Ida Moss", s = 3333 } }
	local okReps = Ops.fieldReps(e)
	e.deals.tripList = {}
	advance(1.1) -- first look after loading has happened already (company existed): trips seen = {}
	if Vehicles.cars[7001] then Vehicles.cars[7001].model:Destroy() end
	advance(0.3)
	table.insert(e.deals.tripList, { client = "helix", kind = "sign", back = e.seconds + 2400, founder = false, hosted = false, crew = 1, left = e.seconds })
	advance(1.1)
	local field = nil
	for _, ch in folder:GetChildren() do if ch:GetAttribute("Kind") == "field" then field = ch end end
	check("field ride for the abroad trip (reps " .. tostring(okReps) .. ")", field ~= nil)
	local fsegs = field and Drive.decode(field:GetAttribute("Plan"), plot.index)
	check("chauffeur takes the rep: garage -> entrance -> departures -> garage", fsegs and #fsegs == 3 and fsegs[1].who == "D" and fsegs[2].to == "airport_departures" and fsegs[2].who == "D,C1"
		and field:GetAttribute("Driver") == 1, field and field:GetAttribute("Plan"))
	check("rep template named after the real profile", field and field:FindFirstChild("C1") and field.C1:GetAttribute("CompanionName") == "Leo Park")
	local hb = Driver.phoneHook(s, {})
	check("phone (all busy): says who is out and when the next car is free", string.find(hb.text, "driving field staff", 1, true) ~= nil and string.find(hb.text, "Next free car", 1, true) ~= nil, hb.text)
	standAt(p, atHQ)
	T += 5
	local qres = Driver.request(p, { to = "airport_departures" })
	local fieldEnd = Drive.planEnd(Drive.decode(field:GetAttribute("Plan"), plot.index), plot.index)
	local expectEta = fieldEnd - T + Drive.walkAt(fieldEnd) + legA.dur
	check("queued with an honest ETA", qres.ok and qres.queued and math.abs(qres.eta - expectEta) <= 2, tostring(qres.eta) .. " vs " .. expectEta)
	local qs = Driver.status(p)
	check("status queued", qs.state == "queued" and qs.rideId == "queued:7001")
	check("queued booking published for the HUD (DriveQueue = expected arrival)", math.abs((p:GetAttribute("DriveQueue") or 0) - (T + qres.eta)) <= 1 and p:GetAttribute("DriveQueueTo") == "City Airport (departures)")
	local hq2 = Driver.phoneHook(s, {})
	check("phone (queued)", string.find(hq2.text, "Booked: the next free car", 1, true) ~= nil, hq2.text)
	local cq = Driver.cancel("queued:7001")
	check("cancel a queued booking (dropped, HUD cleared)", cq == true and Driver.status(p).state ~= "queued" and p:GetAttribute("DriveQueue") == nil and p:GetAttribute("DriveQueueTo") == nil)
	check("cancel a queued booking twice", Driver.cancel("queued:7001") == false)
	T += 5
	qres = Driver.request(p, { to = "airport_departures" })
	check("booked again after the cancel", qres.ok and qres.queued and p:GetAttribute("DriveQueue") ~= nil, qres.err)
	check("simultaneous rides <= drivers", (function() local n = 0; for _, ch in folder:GetChildren() do if ch:IsA("Folder") and (ch:GetAttribute("Driver") or 0) > 0 then n += 1 end end; return n end)() <= 1)
	local queuedAt = T
	advance(fieldEnd - T + 0.6)
	local qride = nil
	for _, ch in folder:GetChildren() do if ch:GetAttribute("Kind") == "founder" then qride = ch end end
	check("queued ride starts by itself when the driver is back", qride ~= nil and field.Parent == nil and string.find(lastNotice(p), "is free now", 1, true) ~= nil, lastNotice(p))
	check("booking cleared from the HUD when the ride starts", p:GetAttribute("DriveQueue") == nil and p:GetAttribute("DriveQueueTo") == nil)
	local qsegs = qride and Drive.decode(qride:GetAttribute("Plan"), plot.index)
	local actualWait = qsegs and (qsegs[1].t0 + legA.dur - queuedAt)
	check("the car is at the pick-up when the ETA said", actualWait and math.abs(actualWait - qres.eta) <= 2, tostring(actualWait) .. " vs " .. tostring(qres.eta))
	if qride then Driver.cancel(qride:GetAttribute("Id")) end
	advance(1)

	------------------------------------------------------------------ field rides: abroad return, city self-drive, return, hosted guests, founder trips
	advance(0.5)
	-- the abroad trip ends (the rep lands at City Airport): the free chauffeur fetches him at arrivals
	table.remove(e.deals.tripList, 1)
	advance(1.1)
	local fetch = nil
	for _, ch in folder:GetChildren() do
		local sg = Drive.decode(ch:GetAttribute("Plan") or "", plot.index)
		if ch:GetAttribute("Kind") == "field" and sg and #sg == 3 and sg[1].to == "airport_arrivals" and sg[2].who == "D,C1" and sg[2].to == "hq_entrance" then fetch = ch end
	end
	check("abroad trip over: the chauffeur fetches the rep at arrivals", fetch ~= nil and fetch.C1:GetAttribute("CompanionName") == "Leo Park")
	if fetch then advance(Drive.planEnd(Drive.decode(fetch:GetAttribute("Plan"), plot.index), plot.index) - T + 0.5) end
	check("fetch ride done", fetch == nil or fetch.Parent == nil)
	local cityTrip = { client = "helpdesk", kind = "renew", back = e.seconds + 240, founder = false, hosted = false, crew = 1, left = e.seconds + 1 }
	table.insert(e.deals.tripList, cityTrip)
	table.insert(e.deals.tripList, { client = "paper", kind = "sign", back = e.seconds + 240, founder = true, hosted = false, crew = 1, left = e.seconds + 1 })
	advance(1.1)
	local cityRide, founderData = nil, 0
	for _, ch in folder:GetChildren() do
		if ch:GetAttribute("Kind") == "field" and ch:GetAttribute("To") == "clouddesk" then cityRide = ch end
	end
	local csegs = cityRide and Drive.decode(cityRide:GetAttribute("Plan"), plot.index)
	-- user request 22: the company driver takes the field rep to the client (no self-driving rep parked for the visit)
	check("city trip: the free company driver takes the rep (garage -> entrance -> client -> garage, D,C1)", csegs and #csegs == 3 and csegs[1].to == "hq_entrance"
		and csegs[2].from == "hq_entrance" and csegs[2].to == "clouddesk" and csegs[2].who == "D,C1" and csegs[3].who == "D" and cityRide:GetAttribute("Driver") == 1
		and cityRide:GetAttribute("Until") == nil, cityRide and cityRide:GetAttribute("Plan"))
	check("founder trips stay data (no car)", (function() local n = 0; for _, ch in folder:GetChildren() do if ch:GetAttribute("To") == "paperstudio" then n += 1 end end; return n end)() == founderData)
	-- the trip ends after the drop-off: the free driver fetches the rep from the client
	if csegs then advance(Drive.planEnd(csegs, plot.index) - T + 0.5) end
	check("city ride done after the drop-off (car back in the garage)", cityRide == nil or cityRide.Parent == nil)
	for i = #e.deals.tripList, 1, -1 do if e.deals.tripList[i] == cityTrip then table.remove(e.deals.tripList, i) end end
	advance(1.1)
	local backRide = nil
	for _, ch in folder:GetChildren() do
		local sg = Drive.decode(ch:GetAttribute("Plan") or "", plot.index)
		if ch:GetAttribute("Kind") == "field" and sg and #sg == 3 and sg[1].to == "clouddesk" and sg[2].from == "clouddesk" and sg[2].to == "hq_entrance" and sg[2].who == "D,C1" then backRide = ch end
	end
	check("trip over: the driver fetches the rep from the client", backRide ~= nil)
	if backRide then advance(Drive.planEnd(Drive.decode(backRide:GetAttribute("Plan"), plot.index), plot.index) - T + 0.5) end
	-- a city trip that ends while the rep is still on his way there: the same car brings him straight back
	local shortTrip = { client = "helpdesk", kind = "renew", back = e.seconds + 240, founder = false, hosted = false, crew = 1, left = e.seconds + 3 }
	table.insert(e.deals.tripList, shortTrip)
	advance(1.1)
	local outRide = nil
	for _, ch in folder:GetChildren() do if ch:GetAttribute("Kind") == "field" and ch:GetAttribute("To") == "clouddesk" then outRide = ch end end
	local osegs = outRide and Drive.decode(outRide:GetAttribute("Plan"), plot.index)
	if osegs then advance(osegs[2].t0 + Drive.segLeg(osegs[2], plot.index).dur * 0.5 - T) end
	for i = #e.deals.tripList, 1, -1 do if e.deals.tripList[i] == shortTrip then table.remove(e.deals.tripList, i) end end
	advance(1.1)
	local reps = 0
	for _, ch in folder:GetChildren() do if ch:IsA("Folder") and ch:FindFirstChild("C1") and ch:GetAttribute("Kind") == "field" then reps += 1 end end
	osegs = outRide and Drive.decode(outRide:GetAttribute("Plan"), plot.index)
	check("trip ended on the way: no second car, the rep rides on to the client and straight back", reps == 1 and osegs and #osegs == 4 and osegs[3].from == "clouddesk"
		and osegs[3].to == "hq_entrance" and osegs[3].who == "D,C1" and osegs[4].side == "drop", outRide and outRide:GetAttribute("Plan"))
	if osegs then advance(Drive.planEnd(osegs, plot.index) - T + 0.5) end
	-- hosted guests with a free chauffeur (abroad trip ended long ago -> driver free)
	advance(400)
	table.insert(e.deals.tripList, { client = "ledger", kind = "sign", back = e.seconds + 1200, founder = false, hosted = true, crew = 0, left = e.seconds + 2 })
	advance(1.1)
	local guest = nil
	for _, ch in folder:GetChildren() do if ch:GetAttribute("Kind") == "guest" then guest = ch end end
	check("guest-house visit: the chauffeur fetches the client team", guest and guest:FindFirstChild("G1") and guest:FindFirstChild("G2") and guest:GetAttribute("Driver") == 1)
	local gsegs = guest and Drive.decode(guest:GetAttribute("Plan"), plot.index)
	check("guests ride to the HQ entrance (D,G1,G2)", gsegs and gsegs[2].to == "hq_entrance" and gsegs[2].who == "D,G1,G2" and gsegs[3].side == "drop")

	------------------------------------------------------------------ trips under way at join stay data
	local p2, s2 = newPlayer(7002, "Ben", 3)
	s2.data.empire.employees.marketer = 1
	s2.data.empire.staffProfiles = { marketer = { { n = "Kai Lund", s = 4444 } } }
	s2.data.empire.deals.tripList = { { client = "helpdesk", kind = "sign", back = 1e9, founder = false, hosted = false, crew = 1, left = 5 } }
	M.settle(1)
	advance(1.1)
	local f7002 = root:FindFirstChild("Drivers_7002")
	local rides7002 = 0
	for _, ch in f7002:GetChildren() do if ch:IsA("Folder") then rides7002 += 1 end end
	check("trips already under way at join: no car", rides7002 == 0)

	------------------------------------------------------------------ player leaves mid-ride
	standAt(p2, hqPoint(p2, Vector3.new(0, 3, -60)))
	T += 5
	local lv = Driver.request(p2, { to = "airport_departures" })
	check("Ben's request", lv.ok, lv.err)
	local legA2 = Drive.leg("hq_garage", "hq_entrance", Plot.get(p2).index)
	advance(Drive.walkAt(T) + legA2.dur + 1)
	standAt(p2, Drive.endCF(legA2) * Vector3.new(5, 3, 2))
	check("Ben boards", act(s2, { action = "ride", op = "board" }).ok)
	advance(3)
	local okLeave = pcall(function() close(p2, s2) end)
	advance(2)
	check("player leaves mid-ride: no error, company folder + ride gone", okLeave and root:FindFirstChild("Drivers_7002") == nil)

	------------------------------------------------------------------ abroad: the VIP limousine
	local p3, s3 = newPlayer(7003, "Cleo", 1)
	M.settle(1)
	advance(1.1)
	City.trips[7003] = { player = p3, state = "abroad", to = "abroad", releaseAt = math.huge }
	local stand = Drive.place("pm_limo")
	standAt(p3, stand.door.Position)
	local fl, flWhy = Driver.free(p3)
	check("abroad: the limousine service is available even at the garage stage", fl == Driver.LIMO_FLEET + 1 and flWhy == nil, fl)
	local hab = Driver.phoneHook(s3, {})
	check("phone (abroad): VIP limousine", string.find(hab.text, "VIP limousine", 1, true) ~= nil, hab.text)
	local shAb = sheets(p3)[#sheets(p3)]
	local hasHotel = false
	for _, it in shAb.places do if it.id == "pm_hotel" and string.find(it.title, "Limo to", 1, true) then hasHotel = true end end
	check("abroad sheet: Limo to Meridian Grand", hasHotel and shAb.zone == "abroad" and shAb.pickup == "pm_limo")
	local homeAbroad = Driver.request(p3, { to = "airport_departures" })
	check("abroad -> home place needs a flight", not homeAbroad.ok and homeAbroad.err == "FLIGHT_REQUIRED", homeAbroad.err)
	T += 5
	local lim = Driver.request(p3, { to = "pm_hotel" })
	check("limo request", lim.ok and lim.eta == 0 and lim.pickup == "pm_limo", lim.err)
	local lf = root.Limo:FindFirstChild("Ride_1")
	check("limo ride published in the Limo folder, waiting at the stand at once", lf and lf:GetAttribute("Kind") == "limo" and lf:GetAttribute("Look") == "limo" and lf:GetAttribute("State") == "waiting"
		and lf:GetAttribute("Zone") == "abroad" and lf:GetAttribute("Plan") == "")
	standAt(p3, stand.stop * Vector3.new(5, 3, 4))
	check("board the limo", act(s3, { action = "ride", op = "board" }).ok)
	local lsegs = Drive.decode(lf:GetAttribute("Plan"))
	check("limo plan: stand -> Meridian Grand -> the service's garage", lsegs and #lsegs == 2 and lsegs[1].from == "pm_limo" and lsegs[1].to == "pm_hotel" and lsegs[1].who == "D,R" and lsegs[2].to == "pm_depot")
	check("bay 1 held by the booked limousine", root.Limo:GetAttribute("Stand") == "held" and root.Limo:GetAttribute("StandRide") == lim.rideId)
	advance(lsegs[1].t0 + Driver.LIMO_CLEAR + 0.5 - T)
	local repo = nil
	for _, ch in root.Limo:GetChildren() do if ch:GetAttribute("Purpose") == "reposition" then repo = ch end end
	local rsegs = repo and Drive.decode(repo:GetAttribute("Plan"))
	check("the stand car pulled away: the next limousine moves up from the garage", repo and rsegs and rsegs[1].from == "pm_depot" and rsegs[1].to == "pm_limo"
		and root.Limo:GetAttribute("StandRide") == repo:GetAttribute("Id") and repo:GetAttribute("Rider") == 0)
	advance(lsegs[1].t0 + Drive.leg("pm_limo", "pm_hotel").dur - T + Driver.ALIGHT + 0.3)
	check("dropped at the Meridian Grand door", (p3.root.Position - Drive.place("pm_hotel").door.Position).Magnitude < 0.6 and not p3.root.Anchored)
	advance(math.max(Drive.planEnd(Drive.decode(lf:GetAttribute("Plan")), nil), rsegs and Drive.planEnd(rsegs, nil) or 0) - T + 0.5)
	check("limo back in the garage: ride removed; the moved-up limousine waits at the stand (idle)", lf.Parent == nil and (repo == nil or repo.Parent == nil)
		and root.Limo:GetAttribute("Stand") == "idle" and #root.Limo:GetChildren() == 0)
	City.trips[7003] = { player = p3, state = "flying", to = "home", releaseAt = math.huge }
	local nSheets = #sheets(p3)
	local hfly = Driver.phoneHook(s3, {})
	check("phone (flying)", string.find(hfly.text, "on a flight", 1, true) ~= nil and hfly.sheet == false and #sheets(p3) == nSheets, hfly.text)
	check("flying: request refused", Driver.request(p3, { to = "pm_hotel" }).err == "FLYING")
	City.trips[7003] = nil
	local homeLimo = Driver.request(p3, { to = "pm_hotel" })
	check("at home: Port Meridian needs a flight / garage has no driver", not homeLimo.ok and (homeLimo.err == "NO_DRIVER" or homeLimo.err == "FLIGHT_REQUIRED"), homeLimo.err)

	------------------------------------------------------------------ remote validation
	standAt(p, atHQ)
	advance(500) -- everything back home
	T += 5
	check("unknown action BAD_INPUT", act(s, { action = "fly" }).err == "BAD_INPUT")
	check("ride without op BAD_INPUT", act(s, { action = "ride" }).err == "BAD_INPUT")
	check("request with a number BAD_INPUT", act(s, { action = "ride", op = "request", to = 5 }).err == "BAD_INPUT")
	local unk = act(s, { action = "ride", op = "request", to = "moon_base" })
	check("unknown place BAD_PLACE + text", unk.err == "BAD_PLACE" and typeof(unk.text) == "string")
	check("garage is not a destination", act(s, { action = "ride", op = "request", to = "hq_garage" }).err == "BAD_PLACE")
	check("long id BAD_INPUT", act(s, { action = "ride", op = "request", to = string.rep("x", 60) }).err == "BAD_INPUT")
	check("already there", act(s, { action = "ride", op = "request", to = "hq_entrance" }).err == "ALREADY_THERE")
	standAt(p, Vector3.new(600, 30, 1250))
	local far = act(s, { action = "ride", op = "request", to = "airport_departures" })
	check("too far from any pick-up + text", far.err == "TOO_FAR" and string.find(far.text, "pick-up point", 1, true) ~= nil, far.err)
	standAt(p, atHQ)
	local okReq = act(s, { action = "ride", op = "request", to = "clouddesk" })
	check("remote request ok", okReq.ok, okReq.err)
	check("board without a waiting car NOT_WAITING", act(s, { action = "ride", op = "board" }).err == "NOT_WAITING")
	check("cancel someone else's ride NO_RIDE", act(s, { action = "ride", op = "cancel", rideId = "drive:9999:1" }).err == "NO_RIDE")
	check("status via remote", act(s, { action = "ride", op = "status" }).state == "coming")
	local pl = act(s, { action = "ride", op = "places" })
	check("places via remote", pl.ok and #pl.places > 10)
	check("cancel own ride via remote", act(s, { action = "ride", op = "cancel" }).ok)
	local cool = act(s, { action = "ride", op = "request", to = "clouddesk" })
	check("request again within REQUEST_GAP: COOLDOWN", cool.err == "COOLDOWN", cool.err)
	-- itinerary hook for other TripAction actions
	local got = nil
	Driver.onTripAction("go", function(_s, payload) got = payload; return { ok = true, routed = true } end)
	Driver.onTripAction("ride", function() return { ok = true, hijacked = true } end)
	local routed = act(s, { action = "go", x = 1 })
	check("other actions go to the registered handler", routed.ok and routed.routed and got and got.x == 1)
	check("'ride' cannot be taken over", act(s, { action = "ride", op = "status" }).hijacked == nil)
	-- places API
	local pls = Driver.places("home", p)
	local hasHq, hasGarage = false, false
	for _, it in pls do if it.id == "hq_entrance" then hasHq = true end; if it.id == "hq_garage" then hasGarage = true end end
	check("places(home, player): HQ entrance, no garage", hasHq and not hasGarage)
	check("places(abroad): 7 places (the limousine garage is not one)", #Driver.places("abroad") == 7, #Driver.places("abroad"))
	-- per-action rate limits (real numbers): bookings / cancels share one bucket, status polls have their own, so a
	-- polling HUD never blocks a booking; itinerary actions have their own bucket each
	for k, v in LIMITS do Driver.LIMITS[k] = v end
	Driver._resetLimits()
	local limited, okReads = 0, 0
	for _ = 1, LIMITS.write[1] + 4 do
		local r = act(s, { action = "ride", op = "cancel", rideId = "drive:0:0" })
		if r.err == "RATE_LIMIT" then limited += 1 end
	end
	for _ = 1, LIMITS.read[1] do
		if act(s, { action = "ride", op = "status" }).err ~= "RATE_LIMIT" then okReads += 1 end
	end
	local goOk = act(s, { action = "go", x = 2 }).ok
	check("rate limit: write ops limited after the burst, status polls still answered, other actions separate", limited >= 3 and okReads == LIMITS.read[1] and goOk == true,
		limited .. " limited / " .. okReads .. " reads")
	conn:Disconnect(); evConn:Disconnect()
	local _x = cbArgs
end
local ok, err = M.runMain(body, { timeout = 900, maxSteps = 8000000 })
if not ok then failc += 1; print("CRASH " .. tostring(err)) end
print(string.format("drivers_service: %d passed, %d failed", pass, failc))
