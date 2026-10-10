--!nocheck
-- Flight package: ShuttleService + CityService in the headless mock with a controlled server clock.
-- Timetable publishing, pilots (templates, uniform, crew state), tickets (spend once, refusals), boarding
-- rules (gate, phase, vehicle, auto-board at the end of boarding, missed departure), the ride (hold under the
-- stand, stream before every move, mid-cruise move, arrival pivot, state), rebuild mid-flight (real
-- PlotService), two players, no per-tick player writes, return flight, refunds (respawn / leave mid-flight,
-- unused ticket), legacy flight using a held ticket, VIP helicopter (abroad only, pad distance, fee vs limo
-- pass, shop errors, busy, arrival, refund), shuttle switched off.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_flight && tools/luau tests/flight/test_shuttle.luau [-a .gen_dir]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_flight")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
for path, src in require("../world/stubs") do sources[path] = src end
M.loadTree(manifest, sources)
M.quiet = true
local G = M.G
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end
local function near(a, b, tol) return (a - b).Magnitude <= (tol or 0.01) end

local function body()
	local Instance, Vector3, CFrame, Enum = G.Instance, G.Vector3, G.CFrame, G.Enum
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local S = Server.Services
	local F = require("../world/fixture")(M, G)
	local Remote = M.require(Server.Lib.Remote)
	local Session = M.require(S.SessionService)
	local Shop = M.require(S.ShopService)
	local CityPlan = M.require(RS.Shared.Config.CityPlan)
	local FP = M.require(RS.Shared.FlightPlan)
	-- controlled server clock
	local T = 1.7e9
	local function setTime(t) T = t end
	M.IMPL.Workspace.methods.GetServerTimeNow = function() return T end
	if M.classInfo("Workspace").methods then M.classInfo("Workspace").methods.GetServerTimeNow = function() return T end end
	check("server clock patched", game.Workspace:GetServerTimeNow() == T)
	-- HQ generator stubbed (PlotService runs for real)
	local Design = M.require(S.HeadquartersDesign)
	local builds = 0
	Design.build = function(cf, session, accent)
		builds += 1
		local m = Instance.new("Model"); m.Name = "Office"; m:SetAttribute("OfficeTier", session.data.empire.office); m:SetAttribute("OwnerUserId", session.userId)
		return m
	end
	Design.staff = function() end
	local Doors = M.require(S.DoorService); Doors.register = function() end; Doors.unregister = function() end
	local Lift = M.require(S.LiftService); Lift.attach = function() end; Lift.detach = function() end
	local Plot = M.require(S.PlotService)
	local City = M.require(S.CityService)
	local Shuttle = M.require(S.ShuttleService)
	-- start the server in the middle of a cruise (so nothing is boarding at start-up)
	local I = FP.interval()
	local function legStart(dir, k) return FP.legStart(dir, k) end
	local K = math.floor((T - FP.CONFIG.epoch) / I) + 1
	local out, back = FP.leg("out"), FP.leg("back")
	setTime(legStart("out", K - 1) + out.phases.cruise.t0 + 3)
	Plot.init()
	City.init()
	local folder = RS:FindFirstChild("Shuttle")
	check("ReplicatedStorage.Shuttle published", folder ~= nil and folder:IsA("Folder"))
	check("timetable attributes", folder:GetAttribute("Enabled") == true and folder:GetAttribute("Interval") == I and folder:GetAttribute("Kind") == "320"
		and folder:GetAttribute("Scale") == FP.CONFIG.scale and folder:GetAttribute("Phase") == "cruise" and folder:GetAttribute("Leg") == "out")
	check("next departures published", math.abs(folder:GetAttribute("NextOut") - (legStart("out", K) + out.phases.pushback.t0)) < 1e-6
		and folder:GetAttribute("NextBack") == legStart("back", K - 1) + back.phases.pushback.t0, folder:GetAttribute("NextBack"))

	------------------------------------------------------------------ pilots
	local crew = folder:FindFirstChild("Crew")
	local cap = crew and crew:FindFirstChild("Captain"); local fo = crew and crew:FindFirstChild("FirstOfficer")
	check("two pilot templates", cap ~= nil and fo ~= nil)
	local capName = folder:GetAttribute("CaptainName"); local foName = folder:GetAttribute("FirstOfficerName")
	check("pilots have names", typeof(capName) == "string" and #capName > 3 and typeof(foName) == "string" and #foName > 3 and capName ~= foName, tostring(capName) .. "/" .. tostring(foName))
	local function info(m)
		local parts, prompts, capPart, tie, blazer = 0, 0, false, false, false
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then parts += 1; if d.Name == "PilotCap" then capPart = true end; if d.Name == "Tie" then tie = true end; if d.Name == "Blazer" then blazer = true end end
			if d:IsA("ProximityPrompt") then prompts += 1 end
		end
		return parts, prompts, capPart, tie, blazer
	end
	local parts, prompts, capPart, tie, blazer = info(cap)
	check("captain wears the pilot uniform (cap, tie, jacket)", capPart and tie and blazer, string.format("cap=%s tie=%s blazer=%s", tostring(capPart), tostring(tie), tostring(blazer)))
	check("pilot rig within the rig part budget, no talk prompt", parts <= 22 and prompts == 0, parts)
	check("templates are not employees (no CompanyEmployee tag)", not cap:HasTag("CompanyEmployee") and not fo:HasTag("CompanyEmployee"))
	check("pilot Role attribute", cap:GetAttribute("Role") == "Pilot" and cap:GetAttribute("CrewRole") == "Captain" and fo:GetAttribute("CrewRole") == "First Officer")
	local badgeText
	for _, d in cap:GetDescendants() do if d:IsA("TextLabel") and d.Parent and d.Parent.Name == "EmployeeBadge" then badgeText = d.Text end end
	check("badge reads Captain <name>", badgeText ~= nil and string.find(badgeText, "Captain " .. capName, 1, true) == 1, badgeText)
	local gates = game.Workspace:FindFirstChild("ShuttleGates")
	local homePrompt = gates and gates:FindFirstChild("GateBoardHome") and gates.GateBoardHome:FindFirstChild("BoardPrompt")
	check("board prompts at both gates", homePrompt ~= nil and homePrompt:GetAttribute("CityAction") == "board" and gates:FindFirstChild("GateBoardAbroad") ~= nil)
	check("board prompts are Public (WorldController shows them to everyone)", homePrompt and homePrompt:GetAttribute("Public") == true and gates.GateBoardAbroad.BoardPrompt:GetAttribute("Public") == true)
	check("home board prompt at gate A" .. CityPlan.AIRPORT.shuttleStand .. " (within the boarding radius)", homePrompt and (gates.GateBoardHome.Position - FP.HOME_GATES[1]).Magnitude < FP.GATE_RADIUS, homePrompt and gates.GateBoardHome.Position)

	------------------------------------------------------------------ players
	local act = Remote.binds.TravelAction
	local TICKET = CityPlan.TRAVEL.ticket
	local counter = CityPlan.AIRPORT.checkin[2]
	local atCounter = CFrame.new(counter.X, 27.5, counter.Z - 6)
	local gatePos = FP.HOME_GATES[1]
	local atGate = CFrame.new(gatePos.X + 3, 27.5, gatePos.Z + 4)
	local function newPlayer(id, name, money)
		local p = F.player(id, name, CFrame.new(0, 27.5, 0))
		local s = F.session(p, money)
		table.insert(Session.sessions, s)
		for _, fn in Session.loaded do fn(s) end
		return p, s
	end
	local p1, s1 = newPlayer(5001, "Ava", 500)
	local p2, s2 = newPlayer(5002, "Ben", TICKET * 3)
	local p3, s3 = newPlayer(5003, "Cleo", TICKET * 3)
	M.settle(1)
	local plot1 = Plot.get(p1)
	local function call(s, payload) return act(s, payload) end
	-- a company with an abroad pilot trip in progress (field staff on the shuttle, user request 20): a stage-4
	-- office, two Growth & Sales heads (the first is the field rep of the first trip); no character, no plot
	local pf = F.player(5009, "Fiona", CFrame.new(0, 27.5, 0))
	local sf = F.session(pf, 100000)
	sf.data.company.name = "Helix Partners"
	local ef = sf.data.empire
	ef.office = 4
	ef.employees = ef.employees or {}
	ef.employees.marketer = 2; ef.employees.engineer = 0
	ef.staffProfiles = { marketer = { { n = "Mia Chen", s = 1111 }, { n = "Leo Park", s = 2222 } } }
	ef.deals = ef.deals or {}
	ef.deals.tripList = { { client = "helix", kind = "sign", back = 1e12, founder = false, hosted = false, crew = 2, left = 4242 } }
	table.insert(Session.sessions, sf)

	------------------------------------------------------------------ publish / crew state
	local walkStart = out.phases.boarding.t1 - FP.CREW_SEATED - FP.CREW_WALK
	setTime(legStart("out", K) + 1); City.tick(0.1)
	check("boarding published", folder:GetAttribute("Phase") == "boarding" and folder:GetAttribute("Flight") == FP.CONFIG.flights.out and folder:GetAttribute("From") == "home")
	check("crew still leaving after the last arrival", folder:GetAttribute("CrewState") == "leaving")
	-- field staff on this leg
	local pax = folder:FindFirstChild("Passengers")
	local mia = pax and pax:FindFirstChild("Passenger1")
	check("field staff published at the start of boarding (Passengers, leg key)", pax ~= nil and pax:GetAttribute("Leg") == "out:" .. K and #pax:GetChildren() == 1, pax and #pax:GetChildren())
	check("the field rep of the abroad trip flies out (name, company)", mia ~= nil and mia:GetAttribute("PassengerName") == "Mia Chen" and mia:GetAttribute("Company") == "Helix Partners")
	check("passenger rig is a template (no tag, no prompt, no collision, only the root anchored)", mia ~= nil and (function()
		if mia:HasTag("CompanyEmployee") then return false end
		for _, d in mia:GetDescendants() do
			if d:IsA("ProximityPrompt") then return false end
			if d:IsA("BasePart") and (d.CanCollide or d.CanTouch or (d.Anchored ~= (d.Name == "HumanoidRootPart"))) then return false end
		end
		return true end)())
	setTime(legStart("out", K) + 3); City.tick(0.1)
	check("passengers built once per leg (not re-published every tick)", folder:FindFirstChild("Passengers") == pax)
	setTime(legStart("out", K) + walkStart - 1); City.tick(0.1)
	check("crew in the crew room", folder:GetAttribute("CrewState") == "crewroom")
	setTime(legStart("out", K) + walkStart + 1); City.tick(0.1)
	check("crew walking to the aircraft", folder:GetAttribute("CrewState") == "walking")
	setTime(legStart("out", K) + out.phases.boarding.t1 - 1); City.tick(0.1)
	check("crew in the cockpit before departure", folder:GetAttribute("CrewState") == "cockpit")

	------------------------------------------------------------------ tickets
	setTime(legStart("out", K) + 2); City.tick(0.1)
	local r = call(s1, { action = "ticket", to = "abroad" })
	check("ticket away from the counter refused", r.ok == false and r.err == "NOT_AT_CHECKIN", r.err)
	check("bad ticket destination refused", call(s1, { action = "ticket", to = "moon" }).err == "BAD_INPUT")
	check("home ticket at home refused", call(s1, { action = "ticket", to = "home" }).err == "NOT_ABROAD")
	p1.Character:PivotTo(atCounter)
	r = call(s1, { action = "ticket", to = "abroad" })
	check("no money: NO_MONEY, nothing spent", r.err == "NO_MONEY" and s1.data.money == 500 and Shuttle.tickets[p1.UserId] == nil, r.err)
	s1.data.money = TICKET + 100
	local cost0 = s1.data.stats.totalCost
	r = call(s1, { action = "ticket", to = "abroad" })
	check("ticket sold at the counter", r.ok == true and r.price == TICKET and r.flight == FP.CONFIG.flights.out and r.gate == "A" .. CityPlan.AIRPORT.shuttleStand, r.err)
	check("ticket paid once (Economy.spend)", s1.data.money == 100 and s1.data.stats.totalCost == cost0 + TICKET)
	-- P&L ledger line "travel" (design/requests/econ.md #4): the purchase is a cost, a refund an income
	local function travelLine(s, side)
		local total = 0
		local led = s.data.empire and s.data.empire.ledger
		if typeof(led) == "table" then for _, e in led do if typeof(e) == "table" and typeof(e[side]) == "table" then total += e[side].travel or 0 end end end
		return total
	end
	check("ticket booked on the P&L line travel", travelLine(s1, "o") == TICKET, travelLine(s1, "o"))
	local _, ls, dep, be = FP.nextLeg("out", T)
	check("ticket names the current boarding leg", r.boardingStarts == ls and r.departs == dep and r.boardingEnds == be and ls == legStart("out", K))
	r = call(s1, { action = "ticket", to = "abroad" })
	check("second check-in: same ticket, no second charge", r.ok == true and r.held == true and r.price == 0 and s1.data.money == 100)
	check("status reports the ticket and the shuttle", (function() local st = call(s1, { action = "status" }); return st.ok and st.shuttle == true and st.ticketTo == "abroad" and st.state == "home" and st.ticket == TICKET end)())
	p2.Character:PivotTo(atCounter); check("player 2 ticket", call(s2, { action = "ticket", to = "abroad" }).ok == true)
	p3.Character:PivotTo(atCounter); check("player 3 ticket", call(s3, { action = "ticket", to = "abroad" }).ok == true)

	------------------------------------------------------------------ boarding rules
	local np, ns = newPlayer(5009, "Noticket", 0)
	np.Character:PivotTo(atGate)
	check("board without ticket refused", call(ns, { action = "board" }).err == "NO_TICKET")
	r = call(s1, { action = "board" })
	check("board away from the gate refused", r.err == "NOT_AT_GATE", r.err)
	p1.Character:PivotTo(atGate)
	local seat = Instance.new("Seat"); seat.Parent = game.Workspace
	local seatGetter = function(self) return self[M.KEY].props.SeatPart end
	M.IMPL.Humanoid.get.SeatPart = seatGetter; M.classInfo("Humanoid").get.SeatPart = seatGetter
	p1.humanoid[M.KEY].props.SeatPart = seat
	check("seated passengers must stand up first", call(s1, { action = "board" }).err == "LEAVE_VEHICLE")
	p1.humanoid[M.KEY].props.SeatPart = nil
	setTime(legStart("out", K) - 30); City.tick(0.1)
	r = call(s1, { action = "board" })
	check("board before boarding refused with the boarding time", r.err == "NOT_BOARDING" and r.boardingStarts == legStart("out", K), r.err)
	setTime(legStart("out", K) + 5); City.tick(0.1)
	local streams0 = #p1.streamed
	r = call(s1, { action = "board" })
	check("boarding accepted during boarding", r.ok == true and r.flight == FP.CONFIG.flights.out and r.leg == "out:" .. K, r.err)
	check("rider is flying (attribute) and away", City.state(p1) == "flying" and p1:GetAttribute("TravelState") == "flying" and City.isAway(p1))
	check("ShuttleLeg attribute for the client", p1:GetAttribute("ShuttleLeg") == "out:" .. K)
	check("character held: anchored below the departure stand", p1.root.Anchored == true and p1.root.Position.Y < CityPlan.GROUND - 20 and near(Vector3.new(p1.root.Position.X, 0, p1.root.Position.Z), Vector3.new(FP.HOLD.home.X, 0, FP.HOLD.home.Z), 0.5), tostring(p1.root.Position))
	check("name hidden while held", p1.humanoid.DisplayDistanceType == Enum.HumanoidDisplayDistanceType.None)
	M.settle(1)
	check("take-off area streamed for the ride", #p1.streamed == streams0 + 1)
	check("ticket used", Shuttle.tickets[p1.UserId] == nil)
	check("boarding twice refused", call(s1, { action = "board" }).err == "BUSY")
	check("a new ticket while flying refused", call(s1, { action = "ticket", to = "abroad" }).err == "BUSY")
	-- player 2 waits at the gate, player 3 is still shopping
	p2.Character:PivotTo(atGate * CFrame.new(4, 0, 0))
	p3.Character:PivotTo(CFrame.new(0, 27.5, 2490))
	setTime(legStart("out", K) + out.phases.doors.t0 + 0.5); City.tick(0.1)
	check("doors closed", folder:GetAttribute("Phase") == "doors")
	check("auto-boarding at the end of boarding (player at the gate)", City.state(p2) == "flying" and p2:GetAttribute("ShuttleLeg") == "out:" .. K and p2.root.Anchored)
	check("player away from the gate missed it (ticket kept)", City.state(p3) == "home" and Shuttle.tickets[p3.UserId] ~= nil and p3:GetAttribute("ShuttleLeg") == nil)
	p3.Character:PivotTo(atGate * CFrame.new(-4, 0, 0))
	r = call(s3, { action = "board" })
	check("late passenger: not boarding, told about the next departure", r.err == "NOT_BOARDING" and r.boardingStarts == legStart("out", K + 1), r.err)
	check("status names the next departure", (function() local st = call(s3, { action = "status" }); return st.nextOut == legStart("out", K + 1) + out.phases.pushback.t0 end)())

	------------------------------------------------------------------ the ride
	local writes1 = p1.attrWrites
	setTime(legStart("out", K) + out.phases.pushback.t0 + 1); City.tick(0.1)
	setTime(legStart("out", K) + out.phases.cruise.t0 + 1); City.tick(0.1)
	check("still held in the cruise", p1.root.Position.Y < CityPlan.GROUND - 20 and City.state(p1) == "flying")
	local streamsBefore = #p1.streamed
	local cr = out.phases.cruise
	setTime(legStart("out", K) + (cr.t0 + cr.t1) / 2 + 0.2); City.tick(0.1)
	M.settle(1)
	check("mid-cruise: destination streamed first", #p1.streamed == streamsBefore + 1 and near(p1.streamed[#p1.streamed].pos, FP.PM_STAND.Position, 0.01))
	check("mid-cruise: held under the Port Meridian stand", near(Vector3.new(p1.root.Position.X, 0, p1.root.Position.Z), Vector3.new(FP.HOLD.abroad.X, 0, FP.HOLD.abroad.Z), 0.5) and p1.root.Anchored, tostring(p1.root.Position))
	-- office rebuild while flying (real PlotService) must not pull the rider home
	local beforeBuilds = builds
	plot1.office:SetAttribute("OfficeTier", -1) -- force a rebuild (the stub generator does not know plan tiers)
	Plot.refresh(s1); M.settle(1)
	check("office rebuilt mid-flight", builds == beforeBuilds + 1)
	check("rebuild did NOT pull the rider home", p1.root.Position.Y < CityPlan.GROUND - 20 and City.state(p1) == "flying", tostring(p1.root.Position))
	local w0 = p1.attrWrites
	for i = 1, 200 do setTime(legStart("out", K) + cr.t1 + i * 0.05); City.tick(0.05) end
	check("no player attribute writes while nothing changes (200 ticks)", p1.attrWrites == w0, p1.attrWrites - w0)
	local money1 = s1.data.money
	setTime(legStart("out", K) + out.phases.deboarding.t0 + 0.3); City.tick(0.1)
	M.settle(1)
	check("arrival: character in the Port Meridian arrival hall", near(p1.root.Position, CityPlan.ABROAD.arrival.Position, 0.01), tostring(p1.root.Position))
	check("arrival: released, name shown again", p1.root.Anchored == false and p1.humanoid.DisplayDistanceType ~= Enum.HumanoidDisplayDistanceType.None)
	check("arrival: state abroad, ShuttleLeg cleared", City.state(p1) == "abroad" and p1:GetAttribute("TravelState") == "abroad" and p1:GetAttribute("ShuttleLeg") == nil)
	check("arrival hall streamed before the move", near(p1.streamed[#p1.streamed].pos, CityPlan.ABROAD.arrival.Position, 0.01))
	check("no refund on arrival (paid once)", s1.data.money == money1 and s1.data.stats.totalCost == cost0 + TICKET)
	check("second passenger arrived too", City.state(p2) == "abroad" and near(p2.root.Position, CityPlan.ABROAD.arrival.Position, 0.01))
	check("player attribute writes during the whole ride are few", p1.attrWrites - writes1 <= 4, p1.attrWrites - writes1)
	setTime(legStart("out", K) + out.phases.deboarding.t0 + 1); City.tick(0.1)
	check("Port Meridian turnaround: the crew stays aboard", folder:GetAttribute("CrewState") == "cockpit")
	check("rebuild while abroad still keeps the founder abroad", (function() plot1.office:SetAttribute("OfficeTier", -1); Plot.refresh(s1); M.settle(1); return builds == beforeBuilds + 2 and near(p1.root.Position, CityPlan.ABROAD.arrival.Position, 0.01) end)())

	------------------------------------------------------------------ return flight
	local pmCounter = CityPlan.ABROAD.checkin[1]
	p1.Character:PivotTo(CFrame.new(pmCounter.X, 27.5, pmCounter.Z + 6))
	local m1 = s1.data.money
	r = call(s1, { action = "ticket", to = "home" })
	check("return ticket at Port Meridian: free", r.ok == true and r.price == 0 and s1.data.money == m1 and r.flight == FP.CONFIG.flights.back, r.err)
	setTime(legStart("back", K) + 3); City.tick(0.1)
	p1.Character:PivotTo(CFrame.new(FP.PM_GATES[1].X, 27.5, FP.PM_GATES[1].Z))
	r = call(s1, { action = "board" })
	check("boarding the return flight at Port Meridian", r.ok == true and r.leg == "back:" .. K, r.err)
	check("held under the Port Meridian stand", near(Vector3.new(p1.root.Position.X, 0, p1.root.Position.Z), Vector3.new(FP.HOLD.abroad.X, 0, FP.HOLD.abroad.Z), 0.5))
	local cb = back.phases.cruise
	setTime(legStart("back", K) + (cb.t0 + cb.t1) / 2 + 0.2); City.tick(0.1); M.settle(1)
	check("return mid-cruise: held under the home stand", near(Vector3.new(p1.root.Position.X, 0, p1.root.Position.Z), Vector3.new(FP.HOLD.home.X, 0, FP.HOLD.home.Z), 0.5))
	setTime(legStart("back", K) + back.phases.deboarding.t0 + 0.2); City.tick(0.1); M.settle(1)
	check("home again: arrivals hall, state cleared", near(p1.root.Position, CityPlan.AIRPORT.arrival.Position, 0.01) and City.state(p1) == "home" and p1:GetAttribute("TravelState") == nil and p1.root.Anchored == false)
	check("home arrival: the crew leaves the aircraft", folder:GetAttribute("CrewState") == "leaving")
	local paxBack = folder:FindFirstChild("Passengers")
	check("the rep stays abroad while the trip runs (nobody on the return leg)", paxBack ~= nil and paxBack:GetAttribute("Leg") == "back:" .. K and #paxBack:GetChildren() == 0, paxBack and #paxBack:GetChildren())

	------------------------------------------------------------------ refunds: respawn / leave mid-flight, unused tickets
	local K2 = K + 1
	setTime(legStart("out", K2) + 2); City.tick(0.1)
	p3.Character:PivotTo(atGate)
	local m3 = s3.data.money; local c3 = s3.data.stats.totalCost
	check("player 3 boards the next departure with the kept ticket", call(s3, { action = "board" }).ok == true and s3.data.money == m3)
	setTime(legStart("out", K2) + out.phases.climb.t0 + 2); City.tick(0.1)
	F.respawn(p3, CFrame.new(0, 27.5, 0))
	check("respawn mid-flight: ride cancelled, state home", City.state(p3) == "home" and p3:GetAttribute("TravelState") == nil and p3:GetAttribute("ShuttleLeg") == nil)
	check("respawn mid-flight: ticket refunded", s3.data.money == m3 + TICKET and s3.data.stats.totalCost == c3 - TICKET, s3.data.money - m3)
	check("refund booked on the P&L line travel", travelLine(s3, "i") == TICKET, travelLine(s3, "i"))
	setTime(legStart("out", K2) + out.phases.deboarding.t0 + 1); City.tick(0.1); M.settle(1)
	check("cancelled rider is not pivoted at arrival", City.state(p3) == "home" and not near(p3.root.Position, CityPlan.ABROAD.arrival.Position, 1))
	-- leave mid-flight
	local p4, s4 = newPlayer(5004, "Dan", TICKET)
	local K3 = K2 + 1
	setTime(legStart("out", K3) + 2); City.tick(0.1)
	p4.Character:PivotTo(atCounter); check("player 4 ticket", call(s4, { action = "ticket", to = "abroad" }).ok == true and s4.data.money == 0)
	p4.Character:PivotTo(atGate); check("player 4 boards", call(s4, { action = "board" }).ok == true)
	for _, fn in Session.closing do fn(s4) end
	check("leaving mid-flight refunds the ticket and clears the trip", s4.data.money == TICKET and City.trips[p4.UserId] == nil)
	setTime(legStart("out", K3) + out.phases.deboarding.t0 + 1); City.tick(0.1); M.settle(1)
	check("left rider never arrives (no error)", City.trips[p4.UserId] == nil)
	-- unused ticket: respawn keeps it, leaving refunds it
	local p5, s5 = newPlayer(5005, "Eve", TICKET)
	p5.Character:PivotTo(atCounter); call(s5, { action = "ticket", to = "abroad" })
	F.respawn(p5, CFrame.new(0, 27.5, 0)); M.settle(1)
	check("unused ticket survives a respawn at home", Shuttle.tickets[p5.UserId] ~= nil and s5.data.money == 0)
	for _, fn in Session.closing do fn(s5) end
	check("unused ticket refunded when leaving", s5.data.money == TICKET and Shuttle.tickets[p5.UserId] == nil)
	-- the instant flight uses a held ticket (no double charge)
	local p6, s6 = newPlayer(5006, "Finn", TICKET)
	p6.Character:PivotTo(atCounter); call(s6, { action = "ticket", to = "abroad" })
	r = call(s6, { action = "flight", to = "abroad" })
	check("instant flight with a held shuttle ticket: no second charge", r.ok == true and r.price == 0 and s6.data.money == 0 and Shuttle.tickets[p6.UserId] == nil, r.err)
	City.tick(CityPlan.TRAVEL.flightSeconds + 0.1)
	check("instant flight still arrives", City.state(p6) == "abroad")

	------------------------------------------------------------------ VIP helicopter
	local okPads, padA, padB = Shuttle.heliInfo()
	check("helipad markers found (metro package)", okPads == true and padA ~= nil and padB ~= nil)
	City.tick(0.1)
	check("helipads published", folder:GetAttribute("HeliAvailable") == true and G.typeof(folder:GetAttribute("HeliFromPad")) == "Vector3", G.typeof(folder:GetAttribute("HeliFromPad")))
	local p7, s7 = newPlayer(5007, "Gus", 1000)
	r = call(s7, { action = "heli", to = "hotel" })
	check("helicopter only abroad", r.err == "HELI_ABROAD_ONLY", r.err)
	-- send p7 abroad with the instant flight to test (fast)
	s7.data.money = TICKET + 1000; p7.Character:PivotTo(atCounter); call(s7, { action = "flight", to = "abroad" }); City.tick(CityPlan.TRAVEL.flightSeconds + 0.1)
	check("p7 abroad", City.state(p7) == "abroad")
	check("bad helicopter destination", call(s7, { action = "heli", to = "moon" }).err == "BAD_INPUT")
	r = call(s7, { action = "heli", to = "hotel" })
	check("helicopter far from the pad refused", r.err == "NOT_AT_HELIPAD", r.err)
	p7.Character:PivotTo(CFrame.new(padA.X + 4, padA.Y + 3, padA.Z + 4))
	s7.data.money = 100
	r = call(s7, { action = "heli", to = "hotel" })
	check("no pass, no money: NO_MONEY with the fee", r.err == "NO_MONEY" and r.price == Shuttle.HELI_FEE and s7.data.money == 100, r.err)
	Shop.passes[p7.UserId] = { limo = true }
	setTime(T + 1)
	r = call(s7, { action = "heli", to = "hotel" })
	check("limo pass: free VIP transfer", r.ok == true and r.price == 0 and r.pass == true and s7.data.money == 100, r.err)
	check("rider flying, held, helicopter published", City.state(p7) == "flying" and p7.root.Anchored and folder:GetAttribute("HeliRider") == p7.UserId and folder:GetAttribute("HeliMode") == "hotel" and folder:GetAttribute("HeliStart") == T)
	local p8, s8 = newPlayer(5008, "Hana", 50000)
	s8.data.money = TICKET + 50000; p8.Character:PivotTo(atCounter); call(s8, { action = "flight", to = "abroad" }); City.tick(CityPlan.TRAVEL.flightSeconds + 0.1)
	p8.Character:PivotTo(CFrame.new(padA.X - 4, padA.Y + 3, padA.Z - 4))
	r = call(s8, { action = "heli", to = "hotel" })
	check("helicopter busy for a second passenger", r.err == "HELI_BUSY" and r.seconds > 0, r.err)
	local ride0, ride1, free = FP.heliTimes("hotel", T, padA, padB)
	setTime(ride1 - 0.5); City.tick(0.1)
	check("still flying before the landing", City.state(p7) == "flying")
	setTime(ride1 + 0.1); City.tick(0.1); M.settle(1)
	check("helicopter arrival: Meridian Grand lobby, state abroad", near(p7.root.Position, CityPlan.INTL_HOTEL.lobby.Position, 0.01) and City.state(p7) == "abroad" and p7.root.Anchored == false, tostring(p7.root.Position))
	setTime(free + 0.1)
	-- the way back from the lobby, with the fee (shop error = not owned)
	Shop.setMode("error")
	local m8 = s8.data.money
	p8.Character:PivotTo(CityPlan.INTL_HOTEL.lobby)
	r = call(s8, { action = "heli", to = "airport" })
	check("shop error counts as no pass: fee charged", r.ok == true and r.price == Shuttle.HELI_FEE and s8.data.money == m8 - Shuttle.HELI_FEE, r.err)
	Shop.setMode("ok")
	F.respawn(p8, CFrame.new(0, 27.5, 0))
	check("respawn during the helicopter ride: refunded", s8.data.money == m8 and City.state(p8) == "home")

	------------------------------------------------------------------ field staff fly home when the trip ends
	ef.deals.tripList = {}
	local KB = K3 + 1
	setTime(legStart("out", KB) + 1); City.tick(0.1)
	check("an ended trip sends nobody out again", #folder.Passengers:GetChildren() == 0)
	setTime(legStart("back", KB) + 1); City.tick(0.1)
	local home = folder.Passengers
	check("trip over: the rep flies home on the next return leg", home:GetAttribute("Leg") == "back:" .. KB and home:FindFirstChild("Passenger1") ~= nil
		and home.Passenger1:GetAttribute("PassengerName") == "Mia Chen", #home:GetChildren())
	setTime(legStart("back", KB + 1) + 1); City.tick(0.1)
	check("... and only once", #folder.Passengers:GetChildren() == 0 and next(Shuttle.flown) == nil)
	-- at most MAX_PAX per leg
	ef.deals.tripList = {}
	for i = 1, 6 do table.insert(ef.deals.tripList, { client = "helix", kind = "sign", back = 1e12, founder = false, hosted = false, crew = 1, left = 9000 + i }) end
	ef.employees.marketer = 6
	ef.staffProfiles.marketer = {}
	for i = 1, 6 do ef.staffProfiles.marketer[i] = { n = "Rep " .. i, s = 300 + i } end
	setTime(legStart("out", KB + 2) + 1); City.tick(0.1)
	check("at most MAX_PAX field staff per leg", #folder.Passengers:GetChildren() <= Shuttle.MAX_PAX and #folder.Passengers:GetChildren() >= 2, #folder.Passengers:GetChildren())
	ef.jet = true
	setTime(legStart("out", KB + 3) + 1); City.tick(0.1)
	check("a company with its own jet does not use the shuttle", #folder.Passengers:GetChildren() == 0)

	------------------------------------------------------------------ shuttle switched off
	Shuttle.setEnabled(false)
	local p9, s9 = newPlayer(5010, "Ivy", TICKET)
	p9.Character:PivotTo(atCounter)
	check("shuttle off: ticket refused", call(s9, { action = "ticket", to = "abroad" }).err == "SHUTTLE_OFF" and s9.data.money == TICKET)
	check("shuttle off: attribute for the client", folder:GetAttribute("Enabled") == false)
	r = call(s9, { action = "flight", to = "abroad" })
	check("shuttle off: the instant flight still works", r.ok == true and s9.data.money == 0, r.err)
	Shuttle.setEnabled(true)
	check("unknown action refused", call(s9, { action = "warp" }).err == "BAD_INPUT")
end

local ok, err = M.runMain(body, { timeout = 900, maxSteps = 8000000 })
if not ok then failc += 1; print("ERROR " .. tostring(err)) end
print(string.format("flight_shuttle: %d passed, %d failed", pass, failc))
if failc > 0 then error("flight_shuttle failed", 0) end
