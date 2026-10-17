--!nocheck
-- guests_jet: the company jet - JetService (server) + JetController (client) in the headless mock with a controlled
-- server clock, the real CityService world (CityBuilder: City Airport + Port Meridian) and world test stubs.
-- Server: folder iff empire.jet, two pilot templates (pilot uniform, names), available()/fly() validation (no jet,
-- bad input, not abroad, already abroad, busy, vehicle), the founder held + TravelState, onArrive callback +
-- listener, arrival placement (Port Meridian VIP stand / City Airport arrivals), PM slots (second company -> slot
-- 2, third -> PM_STANDS_FULL), owner prompt after every flight, prompt-triggered flight, respawn mid-flight (rider
-- released, jet flies on), auto ferry home, runway separation vs the shuttle, session close.
-- Timeline: continuity (no jumps), phases in order, airstair / tug / crew / companion states, pose on the ground
-- at both ends, shared hangar rules.
-- Client: own jet in the hangar (full LOD, collides parked), the decorative PrivateJet hidden locally, another
-- company's parked jet not shown at home but shown abroad, pilots in the crew corner -> cockpit, companions on
-- the airstair, the ride (camera, overlay, view button, announcements, arrival), LOD by distance, one
-- BulkMoveTo per jet per frame, the PM stand-2 airliner hidden while a jet uses slot 2, the window-side arm of seated
-- pilots / companions hidden. Seat test: real EmployeeRigDesign rigs (80 pilot, 40 companion builds) on every seat
-- vs the bizjet's cockpit skin, glazing and cabin fuselage (+ negative: the full rigs poke through).
-- Fix round (review_guests_jet): VIP helicopter inside Port Meridian does not send the jet home (S9), leave mid-flight
-- keeps the jet in the air until it has landed (and a rejoin takes it over), two founders arriving together stand
-- on different spots (S4), fuel only for prompt flights (NO_MONEY), RUNWAY_BUSY + eta instead of departing into a
-- conflict (also empty / staff flights: retried), field staff abroad trips fly the jet (out, back to Hangar 1, fetched later, merged into the founder's
-- flight, the founder's priority + STAFF_WAIT), ShuttleService carries exactly the complement, summon (the jet picks
-- the founder up), the ride view while the arrival streams (S7: camera on the parked jet, "Arrived - stepping
-- off", no countdown), the stand named in the arrival toast, JetRide below the phone, one full-LOD build per frame,
-- and the separation sweep (sep_check.luau: every scheduled flight vs the shuttle, the ambient airliners and a
-- second jet, hull distance at every altitude).
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_gj && cd tests/guests_jet && ../../tools/luau test_jet.luau -a .gen_gj
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_gj")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
for path, src in require("../world/stubs") do sources[path] = src end
M.loadTree(manifest, sources)
M.quiet = true
local G = M.G
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local function body()
	local Instance, Vector3, CFrame = G.Instance, G.Vector3, G.CFrame
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local S = Server.Services
	local Client = game.StarterPlayer.StarterPlayerScripts.Client
	local F = require("../world/fixture")(M, G)
	local Remote = M.require(Server.Lib.Remote)
	local Session = M.require(S.SessionService)
	local CityPlan = M.require(RS.Shared.Config.CityPlan)
	local FP = M.require(RS.Shared.FlightPlan)
	local JP = M.require(RS.Shared.JetPlan)
	local Ops = M.require(RS.Shared.CompanyOps)
	local T = 1.7e9
	local function patch(cls, name, fn) M.IMPL[cls].methods[name] = fn; local ci = M.classInfo(cls); if ci.methods then ci.methods[name] = fn end end
	patch("Workspace", "GetServerTimeNow", function() return T end)
	local bulk = {}
	patch("Workspace", "BulkMoveTo", function(self, parts, cframes) local m = parts[1]; if m then bulk[m] = (bulk[m] or 0) + 1 end; for i, p in parts do p.CFrame = cframes[i] end end)
	local Design = M.require(S.HeadquartersDesign); Design.build = function() local m = Instance.new("Model"); m.Name = "Office"; return m end; Design.staff = function() end
	local Plot = M.require(S.PlotService)
	Plot.get = function(player) return { index = 3, cframe = CityPlan.plots()[3].cframe, owner = player } end
	local City = M.require(S.CityService)
	local Jet = M.require(S.JetService)
	City.init()
	Jet.init()
	local root = RS:FindFirstChild("CompanyJets")
	check("ReplicatedStorage.CompanyJets published (kind / scale)", root ~= nil and root:GetAttribute("Kind") == "bizjet" and root:GetAttribute("Scale") == JP.SCALE)

	------------------------------------------------------------------ players
	local signals = {}
	local function newPlayer(id, name, jet, cf)
		local p = F.player(id, name, cf or CFrame.new(-860, 27.5, 2700))
		local rawSet = p.SetAttribute
		p.GetAttributeChangedSignal = function(_, k) signals[id] = signals[id] or {}; signals[id][k] = signals[id][k] or M.newSignal(k); return signals[id][k] end
		p.SetAttribute = function(self, k, v) rawSet(self, k, v); if signals[id] and signals[id][k] then M.fire(signals[id][k]) end end
		local s = F.session(p, 1e6)
		s.data.company.name = name .. " AI"
		s.data.empire.office = 4
		s.data.empire.jet = jet
		table.insert(Session.sessions, s)
		for _, fn in Session.loaded do fn(s) end
		return p, s
	end
	local p1, s1 = newPlayer(7101, "Ava", true)
	local p2, s2 = newPlayer(7102, "Ben", false)
	local p3, s3 = newPlayer(7103, "Cleo", true)
	M.settle(0.5)
	Jet.tick(1.1)
	local f1, f2, f3 = root:FindFirstChild("Jet_7101"), root:FindFirstChild("Jet_7102"), root:FindFirstChild("Jet_7103")
	check("a jet folder exists iff empire.jet (CompanyOps pays the pilots exactly then)", f1 ~= nil and f2 == nil and f3 ~= nil)
	check("folder attributes: owner, company, livery, at home, slot 1", f1 and f1:GetAttribute("Owner") == 7101 and f1:GetAttribute("Company") == "Ava AI"
		and G.typeof(f1:GetAttribute("Livery")) == "Color3" and f1:GetAttribute("At") == "home" and f1:GetAttribute("Slot") == 1)
	local crew = f1 and f1:FindFirstChild("Crew")
	local cap, fo = crew and crew:FindFirstChild("Captain"), crew and crew:FindFirstChild("FirstOfficer")
	check("two pilot templates = CompanyOps.JET.pilots", cap ~= nil and fo ~= nil and #crew:GetChildren() == Ops.JET.pilots)
	local function has(m, name) for _, d in m:GetDescendants() do if d.Name == name then return true end end return false end
	check("pilots wear the pilot uniform (EmployeeRigDesign pilot: cap, tie)", cap and has(cap, "PilotCap") and has(fo, "PilotCap") and has(cap, "Tie"))
	check("pilots: names, roles, no talk prompt, no employee tag", cap and typeof(cap:GetAttribute("PilotName")) == "string" and cap:GetAttribute("CrewRole") == "Captain"
		and fo:GetAttribute("CrewRole") == "First Officer" and not has(cap, "TalkPrompt") and not cap:HasTag("CompanyEmployee") and cap:GetAttribute("PilotName") ~= fo:GetAttribute("PilotName"))
	local cap3 = f3 and f3.Crew:FindFirstChild("Captain")
	check("pilot names are per company (userId seeded)", cap3 and cap3:GetAttribute("PilotName") ~= cap:GetAttribute("PilotName"))
	local prompts = game.Workspace:FindFirstChild("CompanyJetPrompts")
	local pr1 = prompts and prompts:FindFirstChild("JetPrompt_7101")
	local q1 = pr1 and pr1:FindFirstChild("JetPrompt")
	check("owner prompt 'Fly to Port Meridian' at the parked jet's airstair", q1 ~= nil and q1.ActionText == "Fly to Port Meridian" and q1:GetAttribute("OwnerUserId") == 7101
		and (pr1.Position - JP.HOME_PARK.Position).Magnitude < 30)

	------------------------------------------------------------------ validation
	local ok, reason = Jet.available(p2)
	check("available: NO_JET without a jet", ok == false and reason == "NO_JET")
	check("fly: NO_JET", Jet.fly(p2, { to = "abroad" }).err == "NO_JET")
	check("fly: BAD_INPUT", Jet.fly(p1, { to = "moon" }).err == "BAD_INPUT" and Jet.fly(p1, nil).err == "BAD_INPUT")
	check("fly home while at home: NOT_ABROAD", Jet.fly(p1, { to = "home" }).err == "NOT_ABROAD")
	local seat = Instance.new("Seat"); seat.Parent = game.Workspace
	local seatGetter = function(self) return self[M.KEY].props.SeatPart end
	M.IMPL.Humanoid.get.SeatPart = seatGetter; M.classInfo("Humanoid").get.SeatPart = seatGetter
	p1.humanoid[M.KEY].props.SeatPart = seat
	check("fly while seated in a car: LEAVE_VEHICLE", Jet.fly(p1, { to = "abroad" }).err == "LEAVE_VEHICLE")
	p1.humanoid[M.KEY].props.SeatPart = nil
	ok, reason = Jet.available(p1)
	check("available: ok at home", ok == true and reason == nil)

	------------------------------------------------------------------ fly abroad
	local arrived, listened = {}, {}
	local disconnect = Jet.onArrive(function(pl, id, dest) table.insert(listened, { pl, id, dest }) end)
	local T0 = T
	local res = Jet.fly(p1, { to = "abroad", companions = { { name = "Mia Lopez", role = "marketer", seed = 4242 }, { name = 42 }, { name = "Theo Park", role = "engineer" } },
		onArrive = function(id, dest) table.insert(arrived, { id, dest }) end })
	check("fly abroad: ok + flightId + times", res.ok == true and typeof(res.flightId) == "string" and res.departAt > T0 and res.arriveAt > res.departAt and res.doneAt >= res.arriveAt, res.err)
	check("fly abroad: slot 1 (VIP apron), destination Port Meridian", res.slot == 1 and res.to == "abroad" and res.destination == "Port Meridian")
	check("the founder: JetFlight + TravelState flying + CityService trip", p1:GetAttribute("JetFlight") == res.flightId and p1:GetAttribute("TravelState") == "flying"
		and City.state(p1) == "flying" and City.isAway(p1))
	check("the founder is held anchored below the field", p1.root.Anchored == true and p1.root.Position.Y < CityPlan.GROUND - 20)
	check("flight published once: kind / slot / delay / start / id", f1:GetAttribute("FlightId") == res.flightId and f1:GetAttribute("FlightKind") == "out"
		and f1:GetAttribute("FlightSlot") == 1 and f1:GetAttribute("FlightStart") == T0 and f1:GetAttribute("FlightDelay") == res.delay)
	local comps = f1:FindFirstChild("Companions")
	check("companions: valid entries only (2 rigs), names on them", comps and #comps:GetChildren() == 2 and f1:GetAttribute("Companions") == 2
		and comps:FindFirstChild("Companion1"):GetAttribute("CompanionName") == "Mia Lopez")
	check("no prompt while flying", prompts:FindFirstChild("JetPrompt_7101") == nil)
	check("fly again while flying: JET_BUSY", Jet.fly(p1, { to = "abroad" }).err == "JET_BUSY")
	ok, reason = Jet.available(p1)
	check("available while flying: JET_BUSY + eta", ok == false and reason == "JET_BUSY")
	local st = Jet.status(p1)
	check("status: flying, kind out, phase boarding", st.flying == true and st.kind == "out" and st.phase == "boarding")
	-- the published flight equals JetPlan's timeline
	local tl = JP.timeline("out", 1, res.delay)
	local dep, arr, done = JP.times(tl, T0)
	check("departAt / doneAt from JetPlan.times", math.abs(dep - res.departAt) < 1e-6 and math.abs(done - res.doneAt) < 1e-6 and math.abs(arr + Jet.ARRIVE_AFTER - res.arriveAt) < 1e-6)
	-- mid cruise: the hold moves under the destination field (streamed first)
	local nStream = #p1.streamed
	T = T0 + (tl.phases.cruise.t0 + tl.phases.cruise.t1) / 2 + 0.5
	Jet.tick(0.2); M.settle(1)
	check("mid cruise: destination streamed + hold moved under Port Meridian", #p1.streamed > nStream and p1.root.Position.Z > 7000 and p1.root.Position.Y < CityPlan.GROUND - 20)
	T = T0 + tl.phases.deboarding.t0 + Jet.ARRIVE_AFTER + 0.1
	Jet.tick(0.2); M.settle(1)
	local A = JP.ARRIVAL.abroad
	check("arrival: placed by the VIP limousine stand, unanchored", (p1.root.Position - A.Position).Magnitude < 0.5 and p1.root.Anchored == false)
	check("arrival: TravelState abroad, JetFlight cleared", p1:GetAttribute("TravelState") == "abroad" and City.state(p1) == "abroad" and p1:GetAttribute("JetFlight") == nil)
	check("onArrive callback (flightId, 'abroad') once", #arrived == 1 and arrived[1][1] == res.flightId and arrived[1][2] == "abroad")
	check("JetService.onArrive listener (player, flightId, destination)", #listened == 1 and listened[1][1] == p1 and listened[1][3] == "abroad")
	local MP = M.require(RS.Shared.Config.MetroPlan)
	check("arrival point next to the VIP limousine stand (<= 20 studs) on the plaza", (Vector3.new(A.X, 0, A.Z) - Vector3.new(MP.VIP_LIMO.stand.X, 0, MP.VIP_LIMO.stand.Z)).Magnitude <= 20)
	T = T0 + tl.duration + 0.1
	Jet.tick(0.2); M.settle(0.2)
	check("after the flight: At abroad, slot 1", f1:GetAttribute("At") == "abroad" and f1:GetAttribute("Slot") == 1)
	pr1 = prompts:FindFirstChild("JetPrompt_7101"); q1 = pr1 and pr1:FindFirstChild("JetPrompt")
	check("owner prompt 'Fly home' at the Port Meridian stand", q1 ~= nil and q1.ActionText == "Fly home" and (pr1.Position - JP.slot(1).cf.Position).Magnitude < 30)

	------------------------------------------------------------------ second / third company: slots
	local resB = Jet.fly(p3, { to = "abroad" })
	check("second company abroad: slot 2", resB.ok == true and resB.slot == 2, resB.err)
	local p4, s4 = newPlayer(7104, "Dan", true)
	Jet.tick(1.1)
	ok, reason = Jet.available(p4)
	check("third company: PM_STANDS_FULL (both stands taken)", ok == false and reason == "PM_STANDS_FULL")
	check("fly: PM_STANDS_FULL", Jet.fly(p4, { to = "abroad" }).err == "PM_STANDS_FULL")
	-- runway separation: the two published flights never share a field window with each other or the shuttle
	local tlB = JP.timeline("out", 2, resB.delay)
	local wB = JP.absWindows(tlB, f3:GetAttribute("FlightStart"))
	local overlapShuttle = 0
	for _, w in wB do overlapShuttle += JP.shuttleOverlap(w.field, w.a, w.b) end
	local sched, clear = JP.schedule("out", 2, f3:GetAttribute("FlightStart"), {})
	check("runway separation: delay chosen by JetPlan.schedule; clear -> no overlap with the shuttle", resB.delay == math.min(resB.delay, JP.CONFIG.maxDelay) and (not clear or overlapShuttle == 0), overlapShuttle)

	------------------------------------------------------------------ fly home
	ok, reason = Jet.available(p1)
	check("available abroad with the jet abroad", ok == true, reason)
	check("fly abroad while abroad: ALREADY_ABROAD", Jet.fly(p1, { to = "abroad" }).err == "ALREADY_ABROAD")
	local T1 = T
	local resH = Jet.fly(p1, { to = "home" })
	check("fly home: ok", resH.ok == true and resH.to == "home" and resH.destination == "City Airport", resH.err)
	local tlH = JP.timeline("back", 1, resH.delay)
	T = T1 + tlH.phases.deboarding.t0 + Jet.ARRIVE_AFTER + 0.1
	Jet.tick(0.2); M.settle(1)
	check("home arrival: City Airport arrivals, TravelState home", (p1.root.Position - CityPlan.AIRPORT.arrival.Position).Magnitude < 0.5 and p1:GetAttribute("TravelState") == nil and City.state(p1) == "home")
	local mine = {}
	for _, e in listened do if e[1] == p1 then table.insert(mine, e) end end
	check("onArrive listener: home", #mine == 2 and mine[2][3] == "home")
	T = T1 + tlH.duration + 0.1
	Jet.tick(0.2); M.settle(0.2)
	check("towed into the hangar: At home", f1:GetAttribute("At") == "home")
	check("prompt back in the hangar", prompts:FindFirstChild("JetPrompt_7101") ~= nil and prompts.JetPrompt_7101.JetPrompt.ActionText == "Fly to Port Meridian")
	disconnect()

	------------------------------------------------------------------ prompt flight, respawn mid-flight, auto ferry
	p1.Character:PivotTo(CFrame.new(prompts.JetPrompt_7101.Position + Vector3.new(0, 0, 4)))
	local PPS = game:GetService("ProximityPromptService")
	local T2 = T
	M.fire(PPS.PromptTriggered, prompts.JetPrompt_7101.JetPrompt, p1); M.settle(0.3)
	check("prompt starts the flight (owner, near)", f1:GetAttribute("FlightKind") == "out" and f1:GetAttribute("FlightStart") == T2 and p1:GetAttribute("JetFlight") ~= nil)
	local nFired = #Remote.fired
	M.fire(PPS.PromptTriggered, prompts:FindFirstChild("JetPrompt_7103") or prompts:GetChildren()[1], p2); M.settle(0.1)
	check("another player's prompt does nothing", p2:GetAttribute("JetFlight") == nil)
	local tl2 = JP.timeline("out", f1:GetAttribute("FlightSlot"), f1:GetAttribute("FlightDelay"))
	T = T2 + tl2.phases.climb.t0 + 1
	F.respawn(p1, CFrame.new(0, 27.5, 0)); M.settle(0.2)
	Jet.tick(0.2)
	check("respawn mid-flight: rider released (JetFlight cleared, home), the jet flies on", p1:GetAttribute("JetFlight") == nil and City.state(p1) == "home" and Jet.status(p1).flying == true)
	T = T2 + tl2.duration + 0.1
	Jet.tick(0.2)
	check("the empty jet parks abroad", f1:GetAttribute("At") == "abroad")
	T += JP.CONFIG.autoFerry + 0.5
	Jet.tick(0.2)
	check("auto ferry: the jet flies home by itself (founder not abroad)", f1:GetAttribute("FlightKind") == "ferry" and f1:GetAttribute("Companions") == 0)
	ok, reason = Jet.available(p1)
	check("available during the ferry: JET_RETURNING", ok == false and reason == "JET_RETURNING")
	local tlF = JP.timeline("ferry", f1:GetAttribute("FlightSlot"), f1:GetAttribute("FlightDelay"))
	T = f1:GetAttribute("FlightStart") + tlF.duration + 0.1
	Jet.tick(0.2)
	check("ferry done: home again", f1:GetAttribute("At") == "home")

	------------------------------------------------------------------ timeline maths
	for _, kind in { "out", "back", "ferry" } do
		for slot = 1, 2 do
			local tlx = JP.timeline(kind, slot, 0)
			local prev, prevPhase, jumps, order, worst = nil, nil, 0, true, 0
			local seen = {}
			local idx = {}
			for i, n in JP.PHASES do idx[n] = i end
			local tau = 0
			while tau <= tlx.duration do
				local p = JP.pose(tlx, tau)
				if prev then
					local d = (p.cf.Position - prev.cf.Position).Magnitude
					local lim = math.max(p.speed, prev.speed) * 0.1 * 1.6 + 0.6
					if d > lim then jumps += 1; worst = math.max(worst, d - lim) end
				end
				if prevPhase and p.phase ~= prevPhase and idx[p.phase] and idx[prevPhase] and idx[p.phase] < idx[prevPhase] then order = false end
				seen[p.phase] = true
				prev, prevPhase = p, p.phase
				tau += 0.1
			end
			check(kind .. slot .. ": continuous pose (no jump > speed x dt)", jumps == 0, string.format("%d jumps, worst +%.2f", jumps, worst))
			check(kind .. slot .. ": phases in order, takeoff / cruise / landing present", order and seen.takeoff and seen.cruise and seen.landing and seen.taxiin)
			local p0, p1x = JP.pose(tlx, 0), JP.pose(tlx, tlx.duration + 1)
			local startCf = if tlx.dir == "out" then JP.HOME_PARK else JP.slot(slot).cf
			check(kind .. slot .. ": starts at the departure park, ends at the arrival park", (p0.cf.Position - startCf.Position).Magnitude < 0.01 and (p1x.cf.Position - tlx.park.Position).Magnitude < 0.01)
			check(kind .. slot .. ": airstair down while boarding / deboarding, up while moving", JP.stairsDown(tlx, 1, nil) and JP.stairsDown(tlx, tlx.phases.deboarding.t0 + 1, nil) and not JP.stairsDown(tlx, tlx.phases.cruise.t0, nil))
			local gearUp = JP.pose(tlx, (tlx.phases.cruise.t0 + tlx.phases.cruise.t1) / 2)
			check(kind .. slot .. ": gear up and engines on in the cruise", gearUp.gearDown == false and gearUp.engines == true and gearUp.altitude > 150)
			if tlx.dir == "out" then
				check(kind .. slot .. ": tug at the nose during the pushback, gone in the take-off", JP.tug(tlx, tlx.phases.pushback.t0 + 2) ~= nil and JP.tug(tlx, tlx.phases.takeoff.t0) == nil)
				local s1, u1 = JP.crew(tlx, 2, nil)
				local s2c = JP.crew(tlx, JP.CONFIG.crewWalk + 0.5, nil)
				check(kind .. slot .. ": pilots walk from the corner at the start, then sit in the cockpit", s1 == "walk" and u1 > 0 and u1 < 1 and s2c == "cockpit")
				check(kind .. slot .. ": the pilots stay aboard abroad", JP.crew(tlx, tlx.duration + 5, "abroad") == "cockpit")
			else
				check(kind .. slot .. ": tow-in tug, pilots walk back to the corner after the tow-in", JP.tug(tlx, tlx.phases.towin.t0 + 2) ~= nil and JP.crew(tlx, tlx.duration + 2, "home") == "leave"
					and JP.crew(tlx, tlx.duration + JP.CONFIG.crewWalk + 1, "home") == "corner")
			end
			if kind ~= "ferry" then
				local m1 = JP.companions(tlx, tlx.phases.boarding.t1 - 5)
				local m2 = JP.companions(tlx, tlx.phases.cruise.t0)
				local m3 = JP.companions(tlx, tlx.phases.deboarding.t0 + 2)
				check(kind .. slot .. ": companions board at the end of boarding, sit, walk off at the arrival", m1 == "board" and m2 == "seated" and m3 == "deboard")
			else
				check("ferry" .. slot .. ": no companions", JP.companions(tlx, 5) == nil)
			end
		end
	end
	-- runway separation over 6 shuttle cycles: when schedule() says clear, no field window overlaps the shuttle
	local bad, n = 0, 0
	for i = 0, 120 do
		local now = 1.7e9 + i * 19
		for _, kind in { "out", "back" } do
			local d, clr = JP.schedule(kind, 1, now, {})
			if clr then
				n += 1
				for _, w in JP.absWindows(JP.timeline(kind, 1, d), now) do if JP.trafficOverlap(w.field, w.a, w.b) > 0 then bad += 1 end end
			end
		end
	end
	check("runway separation: " .. n .. " clear departures never share a field with the shuttle / the ambient airliners", bad == 0 and n > 150, bad)

	------------------------------------------------------------------ client
	T = T + JP.CONFIG.crewWalk + 5
	Jet.tick(0.2)
	local owner = p1
	local playerGui = Instance.new("Folder"); playerGui.Name = "PlayerGui"
	owner.FindFirstChild = function(_, name) if name == "PlayerGui" then return playerGui end end
	owner.WaitForChild = function(_, name) if name == "PlayerGui" then return playerGui end end
	M.IMPL.Players.get.LocalPlayer = function() return owner end; M.classInfo("Players").get.LocalPlayer = function() return owner end
	local UIRoot = M.require(Client.UI.UIRoot)
	local Toast = M.require(Client.UI.Toast)
	local hud, dim, overlay, intro, top = UIRoot.init()
	Toast.mount(top)
	local function toastHas(part)
		for _, d in top:GetDescendants() do if d:IsA("TextLabel") and string.find(d.Text, part, 1, true) then return true end end
		return false
	end
	local JC = M.require(Client.Controllers.JetController)
	JC.init()
	M.settle(0.5)
	local camera = game.Workspace.CurrentCamera
	local function look(at) camera.CFrame = CFrame.new(at + Vector3.new(0, 40, 90), at) end
	local function frame(dt) JC.step(dt or 0.2) end
	local function viewOf(uid) for f, v in JC.views() do if v.userId == uid then return v end end end
	local cf = game.Workspace:FindFirstChild("CompanyJetClient")
	look(JP.HOME_PARK.Position)
	-- p3's jet is abroad (slot 2) by now? (it flew at T1-ish) - finish its flight
	T = math.max(T, f3:GetAttribute("FlightStart") + tlB.duration + 1); Jet.tick(0.2)
	frame(0.2)
	local v1, v3 = viewOf(7101), viewOf(7103)
	check("client: views for both jets", v1 ~= nil and v3 ~= nil and v1.own == true and v3.own == false)
	local m1 = v1 and v1.model
	check("own jet built in Hangar 1 (full LOD, parked at HOME_PARK)", m1 ~= nil and m1:GetAttribute("AircraftLod") == "full" and (m1.PrimaryPart.Position - JP.HOME_PARK.Position).Magnitude < 0.05)
	local solid = 0
	if m1 then for _, d in m1:GetDescendants() do if d:IsA("BasePart") and d.CanCollide then solid += 1 end end end
	check("the parked own jet collides locally", solid > 20, solid)
	check("company name on the fin (TailName)", m1 and has(m1, "TailName"))
	check("airstair stowed in the hangar", m1 and m1:GetAttribute("AirstairDeployed") == false)
	local pj, pjHidden = JC.decor()
	local hidden, total = 0, 0
	if pj then for _, d in pj:GetDescendants() do if d:IsA("BasePart") then total += 1; if d.LocalTransparencyModifier == 1 and not d.CanCollide then hidden += 1 end end end end
	check("the airport's decorative PrivateJet hidden locally (own jet in its place)", pj ~= nil and pjHidden and total > 0 and hidden == total, hidden .. "/" .. total)
	check("other company's jet abroad shown on slot 2", v3.model ~= nil or (camera.CFrame.Position - JP.slot(2).cf.Position).Magnitude > JC.LOD_FAR)
	-- pilots in the crew corner (own only)
	local capRig = v1.crew[1]
	check("own pilots cloned in the crew corner", capRig ~= nil and (capRig.root.Position - JP.CREW.spots[1].Position).Magnitude < 0.05 and capRig.visible == true)
	-- another company's jet (a folder like JetService publishes it): parked at home -> not shown in the shared
	-- hangar; parked abroad -> shown on its stand
	local fx = Instance.new("Folder"); fx.Name = "Jet_7999"
	fx:SetAttribute("Owner", 7999); fx:SetAttribute("Company", "Zeta Labs"); fx:SetAttribute("Livery", G.Color3.fromRGB(180, 40, 40))
	fx:SetAttribute("At", "home"); fx:SetAttribute("Slot", 2)
	f3.Crew:Clone().Parent = fx
	fx.Parent = root
	M.settle(0.1); JC.sync(); frame(0.2)
	local vx = viewOf(7999)
	check("another company's jet parked at home: not shown (shared hangar)", vx ~= nil and vx.model == nil and #vx.crew == 0)
	fx:SetAttribute("At", "abroad")
	look(JP.slot(2).cf.Position); frame(0.2); frame(0.2) -- two jets reach full range at once: one full build per frame (FULL_BUILDS)
	check("another company's jet abroad: shown on its stand with the pilots in the cockpit", vx.model ~= nil and (vx.model.PrimaryPart.Position - JP.slot(2).cf.Position).Magnitude < 0.05
		and #vx.crew == 2 and vx.crew[1].visible == true and (vx.crew[1].root.Position - (JP.slot(2).cf * JP.POINTS.captain).Position).Magnitude < 0.05)
	check("parked abroad: airstair down (waiting for the founder)", vx.model and vx.model:GetAttribute("AirstairDeployed") == true)
	-- flying out of the hangar: hidden inside, shown once out of the door
	fx:SetAttribute("FlightKind", "out"); fx:SetAttribute("FlightSlot", 2); fx:SetAttribute("FlightDelay", 0); fx:SetAttribute("FlightStart", T - 2); fx:SetAttribute("FlightId", "jet:7999:1")
	look(JP.HOME_PARK.Position); frame(0.2)
	check("another company's jet boarding inside Hangar 1: not shown", vx.model == nil)
	local tlx = JP.timeline("out", 2, 0)
	fx:SetAttribute("FlightStart", T - tlx.phases.taxi.t0 - 1); frame(0.2)
	check("another company's jet taxiing on the apron: shown", vx.model ~= nil and vx.state.flying == true and not JC.inHangar(vx.state.pose.cf.Position))
	fx:SetAttribute("FlightStart", T - tlx.duration - 1); fx:SetAttribute("At", "home")
	look(JP.slot(2).cf.Position); T += 3.1; frame(0.2)
	local pm2m, pm2h = select(3, JC.decor())
	check("the stand-2 airliner hidden locally while a jet is parked on slot 2", pm2m ~= nil and pm2h == true)
	-- own flight with the ride
	look(JP.HOME_PARK.Position)
	owner.Character:PivotTo(CFrame.new(prompts.JetPrompt_7101.Position))
	local T3 = T
	local r3 = Jet.fly(p1, { to = "abroad", companions = { { name = "Mia Lopez", role = "marketer" } } })
	check("client test flight started", r3.ok == true, r3.err)
	local tl3 = JP.timeline("out", r3.slot, r3.delay)
	frame(0.2)
	check("ride: JetFlight -> ride GUI + welcome toast", JC.riding() == r3.flightId and playerGui:FindFirstChild("JetRide") ~= nil and toastHas("company jet"))
	check("ride: camera scriptable at the window seat", camera.CameraType == G.Enum.CameraType.Scriptable and (camera.CFrame.Position - (JP.HOME_PARK * JP.POINTS.cabinCamera).Position).Magnitude < 0.05)
	check("boarding at home: airstair down", v1.model:GetAttribute("AirstairDeployed") == true)
	T = T3 + 4; frame(0.2)
	local w1 = v1.crew[1]
	check("pilots walking from the corner towards the airstair", w1 and (w1.root.Position - JP.CREW.spots[1].Position).Magnitude > 1 and (w1.root.Position - (JP.HOME_PARK * JP.POINTS.captain).Position).Magnitude > 1)
	local function ltm(list) local a, n = 0, 0; for _, p in list do n += 1; a += p.LocalTransparencyModifier end; return if n > 0 then a / n else -1 end
	check("walking pilots: both arms shown", ltm(v1.crew[1].outer) == 0 and ltm(v1.crew[2].outer) == 0 and v1.crew[1].outerHidden == false)
	T = T3 + JP.CONFIG.crewWalk + 1; frame(0.2)
	check("pilots seated in the cockpit", (v1.crew[1].root.Position - (JP.HOME_PARK * JP.POINTS.captain).Position).Magnitude < 0.05)
	check("seated pilots: the window-side arm (+ hand) hidden, nothing else", v1.crew[1].outer[1].Name == "Left Arm" and #v1.crew[1].outer >= 2 and ltm(v1.crew[1].outer) == 1
		and v1.crew[2].outer[1].Name == "Right Arm" and ltm(v1.crew[2].outer) == 1 and v1.crew[1].model:FindFirstChild("Head").LocalTransparencyModifier == 0
		and v1.crew[1].model:FindFirstChild("Torso").LocalTransparencyModifier == 0)
	T = T3 + tl3.phases.boarding.t1 - 4; frame(0.2)
	local c1 = v1.comps[1]
	check("companion on the way up the airstair", c1 ~= nil and c1.visible == true)
	check("walking companion: both arms shown", c1 ~= nil and c1.outerHidden == false and ltm(c1.outer) == 0)
	T = T3 + tl3.phases.boarding.t1 + 1; frame(0.2)
	local seat1 = JP.POINTS.cabinSeats[JP.COMPANION_SEATS[1]]
	check("seated companion: the window-side arm hidden", c1.outerHidden == true and ltm(c1.outer) == 1 and c1.outer[1].Name == JC.windowArm(seat1)
		and (c1.root.Position - (JP.HOME_PARK * seat1).Position).Magnitude < 0.05)
	local btn = playerGui.JetRide:FindFirstChild("ViewButton", true)
	M.fire(btn.Activated); frame(0.2)
	check("view button: cockpit camera", JC.rideMode() == "cockpit" and (camera.CFrame.Position - (v1.model.PrimaryPart.CFrame * JP.POINTS.cockpitCamera).Position).Magnitude < 0.05)
	M.fire(btn.Activated); frame(0.2)
	check("view button: outside chase camera", JC.rideMode() == "outside" and (camera.CFrame.Position - v1.model.PrimaryPart.Position).Magnitude > 20)
	M.fire(btn.Activated)
	T = T3 + tl3.phases.pushback.t0 + 2; frame(0.2)
	check("pushback: tug at the nose", v1.tug ~= nil)
	check("captain's announcement at the pushback", toastHas("This is your captain"))
	local key = v1.mover.parts[1]
	local b0 = bulk[key] or 0
	T += 0.2; frame(0.2)
	check("one BulkMoveTo per frame for the moving jet", (bulk[key] or 0) == b0 + 1, (bulk[key] or 0) - b0)
	T = T3 + (tl3.phases.cruise.t0 + tl3.phases.cruise.t1) / 2; frame(0.2)
	local gearHidden = 0
	for _, d in v1.model:GetDescendants() do if d:IsA("BasePart") and d:GetAttribute("Gear") and d.Transparency == 1 then gearHidden += 1 end end
	check("cruise: gear retracted, airstair stowed, no collision", gearHidden > 0 and v1.model:GetAttribute("AirstairDeployed") == false and v1.colliding == false)
	check("cruise: camera follows the jet over the sea", camera.CFrame.Position.Y > CityPlan.GROUND + 150)
	Jet.tick(0.2); M.settle(1)
	T = T3 + tl3.phases.deboarding.t0 + Jet.ARRIVE_AFTER + 0.1
	Jet.tick(0.2); M.settle(1); frame(0.2)
	check("arrival: ride closed, camera back, welcome toast", JC.riding() == nil and playerGui:FindFirstChild("JetRide") == nil and camera.CameraType == G.Enum.CameraType.Custom and toastHas("Welcome to Port Meridian"))
	-- LOD
	look(Vector3.new(600, 30, 4000)); frame(0.2)
	check("medium LOD from Business City", v1.model ~= nil and v1.model:GetAttribute("AircraftLod") == "medium" and #v1.crew == 0)
	look(Vector3.new(0, 30, -9000)); frame(0.2)
	check("nothing built far away", v1.model == nil)
	------------------------------------------------------------------ seated rigs vs the bizjet's skin
	-- Every seat the client uses (cockpit: captain / first officer, cabin: the companions' club seats) with a real
	-- EmployeeRigDesign rig at the seat's root frame (jet at the origin): the visible parts (the window-side arm and
	-- its welded parts hidden, as JetController does) must not cut the cockpit side skin / windows / pillars and must
	-- stay inside the cabin fuselage (cylinder radius / axis from the model). Negative: the full rig must fail.
	do
		local Aircraft = M.require(RS.Shared.AircraftModel)
		local Rig = M.require(S.EmployeeRigDesign)
		local jm = Aircraft.build(nil, CFrame.new(), { kind = JP.KIND, scale = JP.SCALE, lod = "full", name = "SeatTest", airstair = false })
		local skins, glass, fus = {}, {}, nil
		for _, d in jm:GetDescendants() do
			if d:IsA("BasePart") then
				if d.Name == "CockpitSkin" or d.Name == "CockpitPillar" or d.Name == "WindowSurround" then table.insert(skins, d) end
				if d.Name == "CockpitSideWindow" or d.Name == "Windshield" then table.insert(glass, d) end
				if d.Name == "Fuselage" then fus = d end
			end
		end
		local function corners(p)
			local out, h = {}, p.Size / 2
			for _, a in { -1, 1 } do for _, b in { -1, 1 } do for _, c in { -1, 1 } do table.insert(out, (p.CFrame * CFrame.new(h.X * a, h.Y * b, h.Z * c)).Position) end end end
			return out
		end
		local function sep(a, b)
			-- separating axis test of two boxes (face normals + edge cross products), 0.02 stud tolerance
			local ax = { a.CFrame.RightVector, a.CFrame.UpVector, a.CFrame.LookVector, b.CFrame.RightVector, b.CFrame.UpVector, b.CFrame.LookVector }
			for i = 1, 3 do for j = 4, 6 do local c = ax[i]:Cross(ax[j]); if c.Magnitude > 1e-4 then table.insert(ax, c.Unit) end end end
			local ca, cb = corners(a), corners(b)
			for _, n in ax do
				local a1, a2, b1, b2 = math.huge, -math.huge, math.huge, -math.huge
				for _, q in ca do local d = q:Dot(n); a1 = math.min(a1, d); a2 = math.max(a2, d) end
				for _, q in cb do local d = q:Dot(n); b1 = math.min(b1, d); b2 = math.max(b2, d) end
				if a2 < b1 + 0.02 or b2 < a1 + 0.02 then return true end
			end
			return false
		end
		-- glazing: thin wedge panes (thin axis X; Roblox WedgePart = full bottom and back (+Z) faces, slope down to the
		-- front). A rig point pokes through a pane when it lies over the pane's triangle and beyond its outer face
		-- (outer = away from the cockpit's centre); touching the inner face is fine.
		local cockpitMid = (JP.POINTS.captain.Position + JP.POINTS.firstOfficer.Position) / 2 + Vector3.new(0, 1, 0)
		local function throughGlass(w, q)
			local l, h = w.CFrame:PointToObjectSpace(q), w.Size / 2
			if math.abs(l.Y) > h.Y or math.abs(l.Z) > h.Z or (l.Y + h.Y) / (2 * h.Y) > (l.Z + h.Z) / (2 * h.Z) then return false end
			local out = if w.CFrame.RightVector:Dot(w.Position - cockpitMid) >= 0 then 1 else -1
			local d = l.X * out
			return d > h.X + 0.02 and d < h.X + 1.5
		end
		local R = fus and math.min(fus.Size.Y, fus.Size.Z) / 2 or 0
		local axisY = fus and fus.Position.Y or 0
		local function hits(seat, cabin, withArm, owner, index)
			local m = Rig.build(workspace, owner, index, if cabin then "marketer" else "pilot", seat, if cabin then { n = "Seat Test", s = owner * 7919 + index } else nil)
			-- seated: the legs bent forward at the hips (EmployeeController.pose: hip transforms A(pi / 2, 0, 0); the
			-- mock does not run Motor6D transforms, so the parts below each hip are rotated here)
			local hrp = m:FindFirstChild("HumanoidRootPart")
			for _, side in { -1, 1 } do
				local hip = hrp.CFrame * CFrame.new(side * 0.5, -1, 0)
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") and d ~= hrp then
						local lp = hrp.CFrame:PointToObjectSpace(d.Position)
						if lp.Y < -0.9 and lp.X * side > 0 then d.CFrame = hip * CFrame.Angles(math.pi / 2, 0, 0) * hip:Inverse() * d.CFrame end
					end
				end
			end
			local hidden = {}
			if not withArm then
				local arm = m:FindFirstChild(JC.windowArm(seat))
				hidden[arm] = true
				for _, d in m:GetDescendants() do
					local w = if d:IsA("BasePart") then d:FindFirstChildOfClass("WeldConstraint") else nil
					if w and w.Part0 == arm then hidden[d] = true end
				end
			end
			local bad, worst = 0, nil
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 1 and not hidden[d] then
					if cabin then
						for _, q in corners(d) do
							local r = math.sqrt(q.X * q.X + (q.Y - axisY) ^ 2)
							if r > R + 0.02 then bad += 1; worst = d.Name .. string.format(" r=%.2f", r) end
						end
					else
						for _, s in skins do if not sep(d, s) then bad += 1; worst = d.Name .. " x " .. s.Name end end
						for _, q in corners(d) do for _, g in glass do if throughGlass(g, q) then bad += 1; worst = d.Name .. " through " .. g.Name end end end
					end
				end
			end
			m:Destroy()
			return bad, worst
		end
		check("seat test: bizjet cockpit skin / glass parts + fuselage found", #skins >= 8 and #glass >= 8 and fus ~= nil and R > 3)
		-- 40 owners x both pilot indexes (rig builds vary 0.92..1.06 in height and width) / 40 companion seeds
		local pts = JP.POINTS
		for _, sc in { { "captain", pts.captain }, { "first officer", pts.firstOfficer } } do
			local bad, w, worstOwner, full = 0, nil, nil, 0
			for owner = 1, 40 do
				for _, index in Jet.PILOTS do
					local n, ww = hits(sc[2], false, false, owner * 101, index)
					if n > 0 then bad += 1; w = ww; worstOwner = owner * 101 end
					if (hits(sc[2], false, true, owner * 101, index)) > 0 then full += 1 end
				end
			end
			check("cockpit (" .. sc[1] .. ", 80 pilot builds): no visible rig part cuts the side skin / pokes through the glass", bad == 0, tostring(bad) .. " builds, e.g. owner " .. tostring(worstOwner) .. ": " .. tostring(w))
			check("negative: every full " .. sc[1] .. " rig would cut the skin (the window arm)", full == 80, full)
		end
		for k = 1, Jet.MAX_COMPANIONS do
			local seat = pts.cabinSeats[JP.COMPANION_SEATS[k]]
			local bad, w, full = 0, nil, 0
			for owner = 1, 40 do
				local n, ww = hits(seat, true, false, owner * 37, 9000 + k)
				if n > 0 then bad += 1; w = ww end
				if (hits(seat, true, true, owner * 37, 9000 + k)) > 0 then full += 1 end
			end
			check("cabin seat " .. JP.COMPANION_SEATS[k] .. " (40 builds): companion inside the fuselage", bad == 0, tostring(bad) .. " builds, " .. tostring(w))
			check("negative: every full companion rig on seat " .. JP.COMPANION_SEATS[k] .. " would poke out", full == 40, full)
		end
		jm:Destroy()
	end
	-- session close drops the folder
	for _, fn in Session.closing do fn(s3) end
	check("session close: folder removed", root:FindFirstChild("Jet_7103") == nil)
	M.settle(0.2); frame(0.2)
	check("client drops the view of a removed jet", viewOf(7103) == nil)

	local function fixRound()
	------------------------------------------------------------------ fix round
	local function tickFor(seconds, step)
		local t1 = T + seconds
		while T < t1 do T += (step or 0.5); Jet.tick(step or 0.5); M.settle(0.02) end
	end
	local function closeSession(s)
		s.closed = true
		for _, fn in Session.closing do fn(s) end
		local i = table.find(Session.sessions, s); if i then table.remove(Session.sessions, i) end
	end
	local function flightEnd(f) local tlx = JP.timeline(f:GetAttribute("FlightKind"), f:GetAttribute("FlightSlot"), f:GetAttribute("FlightDelay")); return f:GetAttribute("FlightStart") + tlx.duration, tlx end
	local function finishFlight(f) local e = flightEnd(f); if T < e then tickFor(e - T + 0.6) end; M.settle(1) end
	-- p1 (the client's founder) flies home first: both Port Meridian stands free
	finishFlight(f1)
	local rH0 = Jet.fly(p1, { to = "home" })
	check("fix: p1 flies home (both stands free afterwards)", rH0.ok, rH0.err)
	finishFlight(f1)
	tickFor(2)
	check("fix: p1 and the jet at home", City.state(p1) == "home" and f1:GetAttribute("At") == "home")

	do
	-- S9: a VIP helicopter transfer inside Port Meridian (ShuttleService.heli: trip state flying, kind heli, to abroad)
	local pH, sH = newPlayer(7301, "Hal", true)
	tickFor(1.5)
	local fH = root:FindFirstChild("Jet_7301")
	local r9 = Jet.fly(pH, { to = "abroad" })
	check("S9: Hal flies abroad", r9.ok, r9.err)
	finishFlight(fH)
	check("S9: Hal abroad, his jet parked in Port Meridian", City.state(pH) == "abroad" and fH:GetAttribute("At") == "abroad")
	local trip9 = City.trips[7301]
	trip9.state = "flying"; trip9.kind = "heli"; trip9.to = "abroad"
	tickFor(60)
	check("S9: a 60 s helicopter transfer to the hotel roof does not send the jet home", fH:GetAttribute("FlightKind") ~= "ferry" and fH:GetAttribute("At") == "abroad", fH:GetAttribute("FlightKind"))
	trip9.state = "abroad"; trip9.kind = nil
	local ok9, why9 = Jet.available(pH)
	check("S9: after the transfer the jet is ready to fly him home", ok9 == true, why9)
	-- the same founder taking the shuttle home (trip to home) -> the jet ferries home
	trip9.state = "flying"; trip9.to = "home"; trip9.kind = "shuttle"
	tickFor(JP.CONFIG.autoFerry + 2)
	check("S9: the founder on a flight home -> the jet ferries home after autoFerry s", fH:GetAttribute("FlightKind") == "ferry")
	City.trips[7301] = nil; pH:SetAttribute("TravelState", nil)
	finishFlight(fH)
	check("S9: ferry done", fH:GetAttribute("At") == "home")

	end
	do
	-- leave mid-flight: the jet keeps flying for everyone, lands, and only then goes; a rejoin takes it over
	local pL, sL = newPlayer(7302, "Lia", true)
	tickFor(1.5)
	local fL = root:FindFirstChild("Jet_7302")
	local nArr = #listened
	local rL = Jet.fly(pL, { to = "abroad" })
	check("leave: Lia flies abroad", rL.ok, rL.err)
	local endL, tlL = flightEnd(fL)
	T = fL:GetAttribute("FlightStart") + (tlL.phases.cruise.t0 + tlL.phases.cruise.t1) / 2; Jet.tick(0.2); M.settle(0.6)
	closeSession(sL); M.settle(0.2)
	check("leave mid-cruise: the folder stays (everyone keeps seeing the jet), CityService trip cleared, no prompt", root:FindFirstChild("Jet_7302") == fL and fL:GetAttribute("FlightId") == rL.flightId
		and City.trips[7302] == nil and prompts:FindFirstChild("JetPrompt_7302") == nil)
	tickFor(endL - T - 2)
	check("leave: still there just before landing", root:FindFirstChild("Jet_7302") ~= nil)
	tickFor(4)
	tickFor(JP.CONFIG.autoFerry + 3)
	check("leave: dropped after the flight ended, no ferry, no onArrive", root:FindFirstChild("Jet_7302") == nil and Jet.jets[7302] == nil and #listened == nArr)
	-- rejoin while the jet is still in the air
	local pR, sR = newPlayer(7303, "Rob", true)
	tickFor(1.5)
	local fR = root:FindFirstChild("Jet_7303")
	local rR = Jet.fly(pR, { to = "abroad" })
	local endR, tlR = flightEnd(fR)
	T = fR:GetAttribute("FlightStart") + tlR.phases.climb.t0 + 2; Jet.tick(0.2)
	closeSession(sR); M.settle(0.2)
	local pR2, sR2 = newPlayer(7303, "Rob", true)
	tickFor(1.5)
	local okR, whyR, infR = Jet.available(pR2)
	check("rejoin mid-flight: the same jet, still flying (JET_BUSY + eta), founder at home", root:FindFirstChild("Jet_7303") == fR and okR == false and whyR == "JET_BUSY" and (infR.eta or 0) > 0
		and City.state(pR2) == "home" and rR.ok)
	tickFor(endR - T + 1)
	tickFor(JP.CONFIG.autoFerry + 2)
	check("rejoin: the empty jet lands abroad and ferries home for the founder", fR:GetAttribute("FlightKind") == "ferry" and fR.Parent == root)
	finishFlight(fR)
	check("rejoin: home again, prompt back", fR:GetAttribute("At") == "home" and prompts:FindFirstChild("JetPrompt_7303") ~= nil)

	end
	do
	-- S4: two founders flying at the same moment arrive on different spots
	local pA, sA = newPlayer(7304, "Ada", true)
	local pB, sB = newPlayer(7305, "Bea", true)
	tickFor(1.5)
	local rA = Jet.fly(pA, { to = "abroad" })
	local rB = Jet.fly(pB, { to = "abroad" })
	check("S4: both fly, different stands", rA.ok and rB.ok and rA.slot ~= rB.slot, tostring(rA.err) .. "/" .. tostring(rB.err))
	local endA = flightEnd(root.Jet_7304); local endB = flightEnd(root.Jet_7305)
	tickFor(math.max(endA, endB) - T + 1)
	M.settle(2)
	local dAB = (pA.root.Position - pB.root.Position).Magnitude
	local inList = 0
	for _, sp in JP.arrivalSpots("abroad") do
		if (pA.root.Position - sp.Position).Magnitude < 0.05 then inList += 1 end
		if (pB.root.Position - sp.Position).Magnitude < 0.05 then inList += 1 end
	end
	check("S4: both founders placed on arrival spots >= 2.5 studs apart", dAB >= 2.5 and inList == 2 and City.state(pA) == "abroad" and City.state(pB) == "abroad", string.format("%.2f studs, %d on spots", dAB, inList))
	local wA = JP.absWindows(JP.timeline("out", rA.slot, rA.delay), root.Jet_7304:GetAttribute("FlightStart"))
	local wB = JP.absWindows(JP.timeline("out", rB.slot, rB.delay), root.Jet_7305:GetAttribute("FlightStart"))
	local ovAB = 0
	for _, a in wA do for _, b in wB do if a.field == b.field then ovAB += math.max(0, math.min(a.b, b.b) - math.max(a.a, b.a)) end end end
	check("S4: the two jets' field windows (runways, apron) never overlap", ovAB == 0, ovAB)
	-- both fly home again (the stands are needed below)
	local rA2 = Jet.fly(pA, { to = "home" }); local rB2 = Jet.fly(pB, { to = "home" })
	check("S4: both fly home (second one scheduled around the first)", rA2.ok and rB2.ok, tostring(rA2.err) .. "/" .. tostring(rB2.err))
	finishFlight(root.Jet_7304); finishFlight(root.Jet_7305)
	closeSession(sA); closeSession(sB); tickFor(1.5)

	end
	do
	-- fuel: the owner prompt pays one leg (P&L "jet"), the API without pay nothing; not enough cash -> NO_MONEY
	local pF, sF = newPlayer(7306, "Fin", true)
	tickFor(1.5)
	local fF = root:FindFirstChild("Jet_7306")
	local prF = prompts:FindFirstChild("JetPrompt_7306")
	pF.Character:PivotTo(CFrame.new(prF.Position + Vector3.new(0, 0, 3)))
	sF.data.money = 500
	local nFiredF = #Remote.fired
	M.fire(PPS.PromptTriggered, prF.JetPrompt, pF); M.settle(0.3)
	local noMoney = false
	for i = nFiredF + 1, #Remote.fired do local e = Remote.fired[i]; if e.player == pF and string.find(tostring(e.args[2] and e.args[2].text), "fuel", 1, true) then noMoney = true end end
	check("fuel: $500 < one leg ($" .. Jet.FUEL_LEG .. ") -> no flight, NO_MONEY notice, cash unchanged", fF:GetAttribute("FlightId") == nil and noMoney and sF.data.money == 500)
	sF.data.money = 100000
	T += 2
	M.fire(PPS.PromptTriggered, prF.JetPrompt, pF); M.settle(0.3)
	local led = sF.data.empire.ledger
	local jetCost = 0
	if typeof(led) == "table" then for _, day in led do if typeof(day) == "table" and typeof(day.o) == "table" then jetCost += tonumber(day.o.jet) or 0 end end end
	check("fuel: the prompt flight pays CompanyOps.JET.fuel / 2, booked as 'jet'", fF:GetAttribute("FlightId") ~= nil and sF.data.money == 100000 - Jet.FUEL_LEG and jetCost == Jet.FUEL_LEG and Jet.FUEL_LEG == Ops.JET.fuel / 2,
		tostring(sF.data.money) .. " / ledger " .. jetCost)
	finishFlight(fF)
	local mF = sF.data.money
	local rF2 = Jet.fly(pF, { to = "home" })
	check("fuel: an API flight without pay costs nothing", rF2.ok and rF2.fuel == 0 and sF.data.money == mF)
	finishFlight(fF)

	-- RUNWAY_BUSY: no clear slot within maxDelay -> refused with an eta, nothing charged
	local saved = JP.CONFIG.maxDelay
	JP.CONFIG.maxDelay = 0
	local found = false
	for _ = 1, 200 do
		local _, clr = JP.schedule("out", 1, T, {}, 0)
		if not clr then found = true; break end
		T += 3
	end
	local m0 = sF.data.money
	local rBusy = Jet.fly(pF, { to = "abroad", pay = true })
	JP.CONFIG.maxDelay = saved
	check("RUNWAY_BUSY: no clear slot -> refused, eta given, no flight, no fuel charged", found and rBusy.ok == false and rBusy.err == "RUNWAY_BUSY" and typeof(rBusy.eta) == "number" and rBusy.eta > 0
		and sF.data.money == m0 and City.state(pF) == "home", tostring(rBusy.err))
	closeSession(sF); tickFor(1.5)

	end
	do
	-- an empty flight (here the auto ferry) never departs into a conflict either: no clear slot -> not started, tried
	-- again after Jet.RETRY s
	local pE, sE = newPlayer(7308, "Eva", true)
	tickFor(1.5)
	local fE = root:FindFirstChild("Jet_7308")
	local rE = Jet.fly(pE, { to = "abroad" })
	finishFlight(fE)
	City.trips[7308] = nil; pE:SetAttribute("TravelState", nil) -- she went home another way
	local realSchedule = JP.schedule
	JP.schedule = function(kind, slot, now, others, maxDelay) local d = realSchedule(kind, slot, now, others, maxDelay); return d, false end
	tickFor(JP.CONFIG.autoFerry + 3)
	local blocked = fE:GetAttribute("FlightKind") ~= "ferry" and fE:GetAttribute("At") == "abroad" and Jet.jets[7308].retryAt ~= nil
	JP.schedule = realSchedule
	check("empty flights: no clear slot -> the ferry waits on the stand (retry pending)", rE.ok and blocked)
	tickFor(Jet.RETRY + 1)
	check("empty flights: a clear slot again -> the ferry leaves", fE:GetAttribute("FlightKind") == "ferry")
	finishFlight(fE)
	closeSession(sE); tickFor(1.5)

	end
	do
	-- field staff: the company's abroad trips fly the jet (ShuttleService leaves them to it)
	local Shuttle = M.require(S.ShuttleService)
	local abroadClient
	for _, c in Ops.CLIENTS do if c.trip == "abroad" then abroadClient = c; break end end
	local pS, sS = newPlayer(7307, "Sam", true)
	local eS = sS.data.empire
	eS.employees = eS.employees or {}
	eS.employees.marketer = 2
	eS.staffProfiles = eS.staffProfiles or {}
	eS.staffProfiles.marketer = { { n = "Mia Lopez", s = 4242 }, { n = "Theo Park", s = 77 } }
	eS.seconds = 50000
	Ops.ensure(eS)
	local tripS = { client = abroadClient.id, kind = "renew", back = 50000 + 1800, founder = false, hosted = false, crew = 1, left = 50000 }
	table.insert(eS.deals.tripList, tripS)
	local keyS = abroadClient.id .. ":50000"
	local trav = Jet.abroadTravellers(eS)
	check("staff: the abroad trip's traveller (k-th field rep) = Mia Lopez", trav[keyS] ~= nil and trav[keyS].people[1].name == "Mia Lopez", Ops.fieldReps(eS))
	-- ShuttleService carries exactly the complement: nobody of this company while empire.jet, Mia without the jet
	local function shuttleNames(cycle)
		local names = {}
		for _, fl in Shuttle.passengersFor({ dir = "out", cycle = cycle }) do if fl.owner == 7307 then table.insert(names, fl.profile.n) end end
		return names
	end
	local withJet = shuttleNames(900001)
	eS.jet = false
	local noJet = shuttleNames(900002)
	eS.jet = true
	check("staff: ShuttleService flies nobody of a jet company, the same traveller without the jet", #withJet == 0 and #noJet == 1 and noJet[1] == "Mia Lopez", #withJet .. "/" .. #noJet)
	local mS = sS.data.money
	local nFiredS = #Remote.fired
	-- the company car (DriverService, package drivers) still brings Mia to the airport: the jet waits for her
	local DS = M.require(S.DriverService)
	local etaAsked = nil
	DS.fieldEta = function(uid, key) etaAsked = { uid, key }; if uid == 7307 and key == keyS then return 30 end; return nil end
	tickFor(1.5)
	local fS = root:FindFirstChild("Jet_7307")
	check("staff: Mia still in the company car (DriverService.fieldEta 30 s) -> the jet waits for her", fS and fS:GetAttribute("FlightId") == nil
		and etaAsked and etaAsked[1] == 7307 and etaAsked[2] == keyS and Jet.staffOf(pS)[keyS].state == "wait_out")
	tickFor(30)
	DS.fieldEta = nil
	check("staff: the trip starts -> the jet flies Mia to Port Meridian (no rider, she is the companion)", fS and fS:GetAttribute("FlightPurpose") == "staff" and fS:GetAttribute("FlightKind") == "out"
		and fS:GetAttribute("Companions") == 1 and fS.Companions:FindFirstChild("Companion1") and fS.Companions.Companion1:GetAttribute("CompanionName") == "Mia Lopez"
		and pS:GetAttribute("JetFlight") == nil and City.state(pS) == "home")
	local okS, whyS, infS = Jet.available(pS)
	check("staff: the founder sees the jet busy with the staff flight (JET_BUSY, purpose staff, names)", okS == false and whyS == "JET_BUSY" and infS.purpose == "staff" and infS.staff[1] == "Mia Lopez")
	local told = false
	for i = nFiredS + 1, #Remote.fired do local e = Remote.fired[i]; if e.player == pS and string.find(tostring(e.args[2] and e.args[2].text), "Mia Lopez", 1, true) then told = true end end
	check("staff: the founder gets a notice", told)
	finishFlight(fS)
	tickFor(1)
	check("staff: Mia abroad, the jet in Port Meridian", Jet.staffOf(pS)[keyS] and Jet.staffOf(pS)[keyS].state == "abroad" and fS:GetAttribute("At") == "abroad")
	tickFor(JP.CONFIG.autoFerry + 2)
	check("staff: the founder at home -> the jet comes back to Hangar 1 by itself", fS:GetAttribute("FlightPurpose") == "ferry")
	finishFlight(fS)
	-- the trip ends -> the jet flies out to fetch her and brings her home
	table.remove(eS.deals.tripList, table.find(eS.deals.tripList, tripS))
	tickFor(1.5)
	check("staff: the trip ended -> the jet flies to Port Meridian to fetch her (empty)", fS:GetAttribute("FlightPurpose") == "position" and fS:GetAttribute("FlightKind") == "out" and fS:GetAttribute("Companions") == 0)
	finishFlight(fS)
	tickFor(1.5)
	check("staff: ...then brings her home (back, Mia aboard, no rider)", fS:GetAttribute("FlightPurpose") == "staff" and fS:GetAttribute("FlightKind") == "back" and fS.Companions:FindFirstChild("Companion1")
		and fS.Companions.Companion1:GetAttribute("CompanionName") == "Mia Lopez")
	finishFlight(fS)
	tickFor(1.5)
	check("staff: home, trip done, nothing left to fly", fS:GetAttribute("At") == "home" and next(Jet.staffOf(pS)) == nil)
	check("staff flights move no money", sS.data.money == mS)
	-- the founder's own flight takes waiting staff along; with the founder abroad the staff wait STAFF_WAIT s
	local trip2 = { client = abroadClient.id, kind = "renew", back = 99999, founder = false, hosted = false, crew = 1, left = eS.seconds - 600 }
	table.insert(eS.deals.tripList, trip2)
	local key2 = abroadClient.id .. ":" .. trip2.left
	tickFor(1.5)
	check("staff: a trip already under way when first seen counts as abroad (no late departure)", Jet.staffOf(pS)[key2] and Jet.staffOf(pS)[key2].state == "abroad" and not (fS:GetAttribute("FlightId") ~= nil and T < flightEnd(fS)))
	pS.Character:PivotTo(CFrame.new(-860, 27.5, 2700))
	local rS1 = Jet.fly(pS, { to = "abroad" })
	check("staff: Sam flies to Port Meridian himself", rS1.ok and #rS1.staff == 0, rS1.err)
	finishFlight(fS); M.settle(1)
	table.remove(eS.deals.tripList, table.find(eS.deals.tripList, trip2))
	local nFired2 = #Remote.fired
	tickFor(1.5)
	check("staff: Mia's trip ends while Sam is abroad with the jet -> she waits for him (notice), the jet stays", Jet.staffOf(pS)[key2].state == "wait_back" and fS:GetAttribute("At") == "abroad"
		and fS:GetAttribute("FlightId") == rS1.flightId)
	local warned = false
	for i = nFired2 + 1, #Remote.fired do local e = Remote.fired[i]; if e.player == pS and string.find(tostring(e.args[2] and e.args[2].text), "home from Port Meridian", 1, true) then warned = true end end
	check("staff: the founder is told he can fly home with her", warned)
	tickFor(30)
	local rS2 = Jet.fly(pS, { to = "home" })
	check("staff: Sam flies home within STAFF_WAIT -> Mia flies with him", rS2.ok and rS2.staff[1] == "Mia Lopez" and fS.Companions:FindFirstChild("Companion1")
		and fS.Companions.Companion1:GetAttribute("CompanionName") == "Mia Lopez", rS2.err)
	finishFlight(fS); M.settle(1); tickFor(1.5)
	check("staff: both home, nothing pending", City.state(pS) == "home" and next(Jet.staffOf(pS)) == nil)
	-- STAFF_WAIT expires: the jet takes the staff home without the founder
	local trip3 = { client = abroadClient.id, kind = "renew", back = 99999, founder = false, hosted = false, crew = 1, left = eS.seconds - 700 }
	table.insert(eS.deals.tripList, trip3)
	tickFor(1.5)
	pS.Character:PivotTo(CFrame.new(-860, 27.5, 2700))
	local rS3 = Jet.fly(pS, { to = "abroad" })
	finishFlight(fS); M.settle(1)
	table.remove(eS.deals.tripList, table.find(eS.deals.tripList, trip3))
	tickFor(Jet.STAFF_WAIT + 3)
	check("staff: after STAFF_WAIT the jet flies the staff home without the founder", rS3.ok and fS:GetAttribute("FlightPurpose") == "staff" and fS:GetAttribute("FlightKind") == "back" and City.state(pS) == "abroad")
	finishFlight(fS); tickFor(1.5)
	-- summon: the founder abroad (shuttle), the jet at home -> it flies over empty and waits for him
	check("summon: setup (Sam abroad, jet home)", City.state(pS) == "abroad" and fS:GetAttribute("At") == "home")
	local okJA, whyJA = Jet.available(pS)
	local sm = Jet.summon(pS)
	check("summon: JET_AT_HOME -> the jet flies empty to Port Meridian (purpose position)", okJA == false and whyJA == "JET_AT_HOME" and sm.ok and fS:GetAttribute("FlightPurpose") == "position" and sm.arriveAt > T)
	check("summon: refused while it flies / at home / already there", Jet.summon(pS).err == "JET_BUSY" and Jet.summon(p1).err == "NOT_ABROAD")
	finishFlight(fS); tickFor(JP.CONFIG.autoFerry + 5)
	check("summon: the jet waits in Port Meridian for the founder (no ferry)", fS:GetAttribute("At") == "abroad" and fS:GetAttribute("FlightPurpose") == "position" and Jet.available(pS) == true)
	check("summon: ALREADY_THERE", Jet.summon(pS).err == "ALREADY_THERE")
	local rS4 = Jet.fly(pS, { to = "home" })
	check("summon: then he flies home with it", rS4.ok, rS4.err)
	finishFlight(fS); M.settle(1)
	check("money: no jet flight above changed Sam's cash", sS.data.money == mS)
	closeSession(sS); tickFor(1.5)

	end
	do
	------------------------------------------------------------------ fix round: client (the ride while the arrival streams)
	-- S7: streaming the arrival area takes longer than the deboarding: the ride view stays valid on the parked jet,
	-- the info line says "Arrived - stepping off" without a countdown, then the ride closes
	finishFlight(f1); tickFor(2)
	look(JP.HOME_PARK.Position)
	p1.Character:PivotTo(CFrame.new(-860, 27.5, 2700))
	local r7 = Jet.fly(p1, { to = "abroad" })
	check("S7: p1 flies abroad", r7.ok, r7.err)
	frame(0.2)
	local tl7 = JP.timeline("out", r7.slot, r7.delay)
	local st7 = f1:GetAttribute("FlightStart")
	JC.setRideMode("window")
	p1.streamHook = function() G.task.wait(7.5) end
	T = st7 + (tl7.phases.cruise.t0 + tl7.phases.cruise.t1) / 2 + 0.2; Jet.tick(0.2); frame(0.2)
	T = st7 + tl7.phases.deboarding.t0 + Jet.ARRIVE_AFTER + 0.05; Jet.tick(0.2); M.settle(0.1); frame(0.2)
	T = st7 + tl7.duration + 0.5; Jet.tick(0.2); M.settle(0.1); frame(0.2); T += 0.3; frame(0.3)
	local info7 = playerGui:FindFirstChild("JetRide") and playerGui.JetRide:FindFirstChild("Info", true)
	check("S7: after the flight ended, still riding: camera on the parked jet's window seat", JC.riding() == r7.flightId and camera.CameraType == G.Enum.CameraType.Scriptable
		and (camera.CFrame.Position - (JP.slot(r7.slot).cf * JP.POINTS.cabinCamera).Position).Magnitude < 1)
	check("S7: the info line reads 'Arrived - stepping off' without a countdown", info7 ~= nil and string.find(info7.Text, "Arrived - stepping off", 1, true) ~= nil
		and string.find(info7.Text, "arrival in", 1, true) == nil, info7 and info7.Text)
	M.settle(9); p1.streamHook = nil; frame(0.2)
	check("S7: placed -> the ride closes, camera back", JC.riding() == nil and playerGui:FindFirstChild("JetRide") == nil and camera.CameraType == G.Enum.CameraType.Custom)
	-- the arrival toast names the stand the jet uses
	f1:SetAttribute("FlightSlot", 2)
	p1:SetAttribute("JetFlight", "jet:7101:test"); JC.onFlight()
	p1:SetAttribute("TravelState", "abroad"); p1:SetAttribute("JetFlight", nil); JC.onFlight()
	check("arrival toast names the actual stand ('at Stand 2', not the VIP apron)", toastHas("Your jet waits at Stand 2") and JP.slot(1).where == "on the VIP apron")
	f1:SetAttribute("FlightSlot", r7.slot)
	-- JetRide stacks above the HUD, below the phone launcher / open phone and the toasts
	local Phone = M.require(Client.UI.Screens.Phone)
	p1:SetAttribute("JetFlight", "jet:7101:test2"); JC.onFlight()
	local ride = playerGui:FindFirstChild("JetRide")
	check("JetRide DisplayOrder above the HUD (10), below the phone (closed " .. Phone.ORDER_CLOSED .. ", open " .. Phone.ORDER_OPEN .. ") and the toasts (30)",
		ride ~= nil and ride.DisplayOrder == JC.RIDE_ORDER and ride.DisplayOrder > 10 and ride.DisplayOrder < Phone.ORDER_CLOSED and ride.DisplayOrder < Phone.ORDER_OPEN)
	p1:SetAttribute("JetFlight", nil); JC.onFlight()
	-- one full-LOD build per frame: two jets reach full range in the same frame
	local function fakeJet(id, x)
		local fj = Instance.new("Folder"); fj.Name = "Jet_" .. id
		fj:SetAttribute("Owner", id); fj:SetAttribute("Company", "Co " .. id); fj:SetAttribute("Livery", G.Color3.fromRGB(90, 90, 200))
		fj:SetAttribute("At", "abroad"); fj:SetAttribute("Slot", if x == 1 then 1 else 2)
		fj.Parent = root
		return fj
	end
	local fa, fb = fakeJet(7991, 1), fakeJet(7992, 2)
	look(Vector3.new(0, 30, -9000)); M.settle(0.1); JC.sync(); frame(0.2)
	look((JP.slot(1).cf.Position + JP.slot(2).cf.Position) / 2)
	frame(0.2)
	local va, vb = viewOf(7991), viewOf(7992)
	local function fulls() local n = 0; for _, v in JC.views() do if v.model and v.lod == "full" then n += 1 end end; return n end
	local nFull = (if va.lod == "full" then 1 else 0) + (if vb.lod == "full" then 1 else 0)
	check("LOD: jets entering full range in one frame -> one full build, the others medium first", fulls() == 1 and nFull <= 1 and va.model ~= nil and vb.model ~= nil, fulls())
	-- (the other jets parked in Port Meridian re-enter full range in the same frame: one upgrade per frame)
	local steps, worstStep, prevFull = 0, 0, fulls()
	while (va.lod ~= "full" or vb.lod ~= "full") and steps < 6 do frame(0.2); steps += 1; worstStep = math.max(worstStep, fulls() - prevFull); prevFull = fulls() end
	check("LOD: the others upgrade on the next frames, one per frame", va.lod == "full" and vb.lod == "full" and worstStep == 1 and steps <= 5, steps .. " frames, worst +" .. worstStep)
	fa:Destroy(); fb:Destroy(); M.settle(0.1); JC.sync()

	end
	------------------------------------------------------------------ fix round: separation sweep
	require("./sep_check")(M, G, check, { step = 12 })
	end
	fixRound()
end

local ok, err = xpcall(body, debug.traceback)
if not ok then failc += 1; print("ERROR " .. tostring(err)) end
print(string.format("guests_jet_jet: %d passed, %d failed", pass, failc))
if failc > 0 then error(string.format("%d checks failed", failc), 0) end
