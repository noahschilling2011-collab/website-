--!nocheck
-- verify2b (release check of round 2b): END-TO-END business trip with TWO founders on ONE server, on the REAL server
-- modules (tests/itinerary/common.luau: ItineraryService, DriverService, JetService, ShuttleService, CityService + the
-- built world, PhoneService, EmpireService, PlotService) and the REAL company tick (EmpireService.tick ->
-- CompanyOps.step: wages, running costs, the B2B pipeline) on a controlled server clock.
--   * Ada (9101) and Ben (9102): stage-4 companies (2 company drivers each), a live model good enough for Helix
--     Research (abroad, Port Meridian); Ben owns the company jet. Every other client is skipped, so CompanyOps itself
--     starts exactly one abroad pilot visit per company (rep + engineer) - nothing is injected into tripList.
--   * the assistant calls both (the real field rep + engineer, the free driver, shuttle / "our jet"); both say Go;
--     the founder's company car takes the colleagues along (drivers.md / itinerary.md #1), City Airport: Ada gate A1 ->
--     shuttle, Ben -> our jet (with the staff, itinerary.md #2) -> Port Meridian -> VIP limousine -> client tower ->
--     the real "Start meeting" prompt (trip.joined) -> car to the Meridian Grand -> owner-only check-in ->
--     Ada: "Fly home now" (colleagues stay, ShuttleService + a field car bring them home at the visit's end);
--     Ben: stays until the visit is over, then everybody flies home on our jet -> arrivals kerb -> driver -> HQ.
--   * Ada's next pilot visit (CompanyOps again, after the first one is back): she declines ("Not this time") -> the
--     field car takes the colleagues to the airport, they travel alone; the economy trip is untouched.
--   * both pilots start at the same play second, so the two companies' trips share one trip key ("helix:<left>"):
--     every service must keep them apart per company / founder.
--   * money: every cash change goes through EconomyService and is booked by CompanyOps.step / EmpireService.tick only
--     (trip costs = CompanyOps.tripPlan; no itinerary / driver / jet / shuttle money); cash change = recorded flows
--     and = the P&L ledger's net change; no background errors, no warnings; at the end every ride, limousine, jet
--     flight, booking, passenger template, itinerary folder / prompt / calendar item is gone.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_itinerary && cd tests/verify2b &&
--      ../../tools/luau test_trip_e2e.luau -a .gen_itinerary        (E2E_VERBOSE=1 prints the timeline)
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_itinerary")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
for path, src in require("../world/stubs") do
	if not string.find(path, "Lib/Remote", 1, true) then sources[path] = src end -- the real Remote: Ada's client gets Notify
end
M.loadTree(manifest, sources)
M.quiet = true
local G = M.G
local VERBOSE = os.getenv and os.getenv("E2E_VERBOSE") == "1"
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
		if VERBOSE then print("ok    " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
	else
		failc += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else ""))
	end
end
local function has(text, part) return typeof(text) == "string" and string.find(text, part, 1, true) ~= nil end
-- every warn() of the game code is recorded (the mock counts them in M.stats.warnings)
local warnings = {}
do
	local rawWarn = G.warn
	G.warn = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		table.insert(warnings, table.concat(parts, " "))
		return rawWarn(...)
	end
end
local Common = require("../itinerary/common")
local numbers = {} -- the timeline / money figures printed at the end

local function body()
	local Vector3 = G.Vector3
	local CFrame, Instance = G.CFrame, G.Instance
	local X = Common(M, G, { realRemote = true })
	local IM, Ops, FP, RS = X.IM, X.Ops, X.FP, X.RS
	local errors0, warnings0 = M.stats.errors, M.stats.warnings

	------------------------------------------------------------------ helpers
	local function info(text) if VERBOSE then print(string.format("t=%7.1f  %s", X.T - X.T0, text)) end end
	local function st(p) return X.state(p) or {} end
	local function itinCalls(s)
		local out = {}
		for _, c in X.Phone.calls(s) do if c.kind == "itinerary" then table.insert(out, c) end end
		return out
	end
	local function answer(s, how)
		local c = itinCalls(s)[1]
		if not c then return { ok = false, err = "no call" } end
		return X.Phone._act(s, { action = "call", id = c.id, answer = how })
	end
	local function findMsg(s, part)
		for _, m in X.Phone._state(s).messages do if has(m.title, part) or has(m.body, part) then return m end end
		return nil
	end
	local function itinCal(s)
		local n = 0
		for _, it in X.Phone._state(s).calendar do if string.sub(it.key, 1, 5) == "itin:" then n += 1 end end
		return n
	end
	local function folderOf(p) return RS.CompanyItinerary:FindFirstChild("Itin_" .. p.UserId) end
	local function atHQ(p) X.standAt(p, X.hqPoint(p, Vector3.new(0, 3, -60))) end
	local function rideOf(p) return X.rideFolder(p) end
	local function carWaiting(p) local rf = rideOf(p); return rf ~= nil and rf:GetAttribute("State") == "waiting" end
	local function trips(s) return Ops.ensure(s.data.empire).tripList end
	local function fieldRides(p)
		local out = {}
		local df = RS:FindFirstChild("CompanyDrivers") and RS.CompanyDrivers:FindFirstChild("Drivers_" .. p.UserId)
		if df then for _, r in df:GetChildren() do if r:GetAttribute("Kind") == "field" then table.insert(out, r) end end end
		return out
	end
	local function fieldCarries(p, names)
		for _, r in fieldRides(p) do
			for _, m in r:GetChildren() do if names[m:GetAttribute("CompanionName") or ""] then return true end end
		end
		return false
	end
	local function namesOf(people)
		local out = {}
		for _, person in people do out[person.name] = true end
		return out
	end
	-- the meeting prompt of a client office; the founder stands at the table and presses it
	local function joinMeeting(p, clientName)
		local q = X.meetingPrompt(IM.officeId(clientName))
		if not q then return false end
		X.standAt(p, q.Parent.Position + Vector3.new(if p.UserId % 2 == 0 then 1.5 else -1.5, 0, -4))
		X.firePrompt(q, p)
		return true
	end
	local function checkIn(p)
		local prompt = M.game.Workspace.ItineraryPrompts:FindFirstChild("ItinRoom_" .. p.UserId)
		if not prompt then return false end
		X.standAt(p, prompt.Position + Vector3.new(if p.UserId % 2 == 0 then 1.5 else -1.5, 0, -3))
		X.firePrompt(prompt.RoomPrompt, p)
		return st(p).checkedIn == true
	end

	------------------------------------------------------------------ money: every EconomyService call (common.luau
	-- records them with a traceback) is attributed to the first game module above EconomyService on the stack
	local function callerOf(trace)
		for line in string.gmatch(trace, "[^\n]+") do
			local mod = string.match(line, "(ServerScriptService%.Server%.[%w%.]+)") or string.match(line, "(ReplicatedStorage%.Shared%.[%w%.]+)")
			if mod and not string.find(mod, "EconomyService", 1, true) then return (string.match(mod, "([%w]+)$")) end
		end
		return "?"
	end
	local function flowOf(c)
		if c.fn == "applyFlow" then return (c.args[1] or 0) - (c.args[2] or 0), c.args[3] or "market" end
		if c.fn == "grant" then return c.args[1] or 0, c.args[2] or "other" end
		return -(c.args[1] or 0), c.args[2] or "other" -- spend (only when it succeeded: checked below)
	end
	local function ledgerNet(s)
		local net = 0
		local led = s.data.empire.ledger
		if typeof(led) == "table" then
			for _, day in led do
				if typeof(day.i) == "table" then for _, v in day.i do net += v end end
				if typeof(day.o) == "table" then for _, v in day.o do net -= v end end
			end
		end
		return net
	end

	------------------------------------------------------------------ two founders, one server
	X.T0 = X.T
	local function founder(id, name, jet)
		local p, s = X.newPlayer(id, name, 4)
		s.econ = false -- the real company tick below advances empire.seconds (not common.luau)
		s.data.company.name = if jet then "Basalt Systems" else "Aster Labs" -- two different companies on the server
		local e = s.data.empire
		e.hr = { auto = false }
		s.data.gpus = { laptop = 1, consumer = 8 } -- token capacity 850 >= Helix Research's 520
		s.data.models.e2e = { id = "e2e", status = "live", stats = { math = 74, reasoning = 12, coding = 12, creativity = 12, knowledge = 12, reliability = 12 } }
		table.insert(s.data.modelOrder, "e2e")
		local d = Ops.ensure(e)
		for _, c in Ops.CLIENTS do if c.id ~= "helix" then d.skip[c.id] = true end end
		d.pinned = "helix"
		if jet then e.jet = true end
		return p, s
	end
	local pA, sA = founder(9101, "Ada", false)
	local pB, sB = founder(9102, "Ben", true)
	-- Ada's client (LocalPlayer): the real ItineraryController (banner, beacon, companions, client team) and
	-- DriveController (company cars, limousines) stepped with the server clock; the camera follows her
	local pgA = X.clientSetup(pA, sA)
	local Ctl = X.Ctl
	local Client = M.game.StarterPlayer.StarterPlayerScripts.Client
	local DriveCtl = M.require(Client.Controllers.DriveController)
	DriveCtl.init()
	local cam = M.game.Workspace.CurrentCamera
	if not cam then
		cam = Instance.new("Camera"); cam.Parent = M.game.Workspace
		pcall(function() M.game.Workspace.CurrentCamera = cam end)
	end
	local seenA = { followers = 0, team = 0, views = 0, banner = false }
	local function clientTick(d)
		local r = pA.root
		if r and cam then cam.CFrame = CFrame.new(r.Position + Vector3.new(0, 10, 20), r.Position) end
		X.frame(d, d)
		DriveCtl.step(X.T)
		local a, b = Ctl.counts()
		seenA.followers = math.max(seenA.followers, a)
		seenA.team = math.max(seenA.team, b)
		local nv = 0
		for _ in DriveCtl._views() do nv += 1 end
		seenA.views = math.max(seenA.views, nv)
		if pgA:FindFirstChild("ItineraryBanner") then seenA.banner = true end
	end
	X.advance(1.5)
	atHQ(pA); atHQ(pB)
	X.advance(1.1) -- the itinerary's first look (baseline: nothing under way)
	check("fixture: stage 4 = 2 company drivers each (CompanyOps.DRIVER)", X.Drive.drivers(sA.data.empire) == 2 and X.Drive.drivers(sB.data.empire) == 2)
	check("fixture: both drivers free", (X.Driver.free(pA)) == 2 and (X.Driver.free(pB)) == 2, tostring((X.Driver.free(pA))) .. "/" .. tostring((X.Driver.free(pB))))
	check("fixture: no trip yet, no offer", #trips(sA) == 0 and #trips(sB) == 0 and st(pA).state == "none" and st(pB).state == "none")
	check("fixture: Ben's jet in Hangar 1", (X.Jet.available(pB)) == true)
	check("fixture: two plots", X.Plot.get(pA) ~= nil and X.Plot.get(pB) ~= nil and X.Plot.get(pA).index ~= X.Plot.get(pB).index)

	-- the real company tick from now on (EmpireService.tick -> CompanyOps.step), every 0.25 s like the rest
	local cash0 = { [sA] = sA.data.money, [sB] = sB.data.money }
	local ledger0 = { [sA] = ledgerNet(sA), [sB] = ledgerNet(sB) }
	local seconds0 = { [sA] = sA.data.empire.seconds, [sB] = sB.data.empire.seconds }
	local calls0 = #X.econCalls
	local extraTick = nil
	local started = { [sA] = {}, [sB] = {} } -- every trip CompanyOps started (key -> trip)
	local startedAt, endedAt = { [sA] = {}, [sB] = {} }, { [sA] = {}, [sB] = {} } -- server time a trip appeared in / left tripList (per company: both keys are "helix:<left>")
	X.onTick = function(d)
		for _, s in { sA, sB } do
			if not s.closed then X.Empire.tick(s, d) end
			local now = {}
			for _, t in trips(s) do
				local k = IM.tripKey(t)
				now[k] = true
				if not started[s][k] then started[s][k] = t; startedAt[s][k] = X.T end
			end
			for k in started[s] do if not now[k] and not endedAt[s][k] then endedAt[s][k] = X.T end end
		end
		clientTick(d)
		if extraTick then extraTick(d) end
	end
	X.advance(0.25)
	local tripA, tripB = trips(sA)[1], trips(sB)[1]
	check("CompanyOps started Ada's Helix Research pilot (rep + engineer, not hosted)", #trips(sA) == 1 and tripA.client == "helix" and tripA.kind == "sign" and tripA.founder == false
		and tripA.hosted == false and tripA.crew == 2, #trips(sA))
	check("CompanyOps started Ben's Helix Research pilot", #trips(sB) == 1 and tripB.client == "helix" and tripB.kind == "sign" and tripB.hosted == false and tripB.crew == 2, #trips(sB))
	if not tripA or not tripB then return end
	local keyA, keyB = IM.tripKey(tripA), IM.tripKey(tripB)
	-- (both started at the same play second: the two companies' trips share the key "helix:<left>" - every service
	-- must key them per company / founder)
	numbers.sameTripKey = keyA == keyB
	-- no more pilots for Ben after this one (Ada gets a second one later: the decline)
	Ops.ensure(sB.data.empire).skip.helix = true
	local daysA, _, costA = Ops.tripPlan("abroad", 2, false, false)
	local daysB, _, costB = Ops.tripPlan("abroad", 2, false, true)
	check("trip lengths = CompanyOps.tripPlan (shuttle 2 days, jet 1.5 days)", math.abs(tripA.back - tripA.left - daysA) <= 1 and math.abs(tripB.back - tripB.left - daysB) <= 1,
		tostring(tripA.back - tripA.left) .. " / " .. tostring(tripB.back - tripB.left))
	local peopleA, peopleB = IM.travellers(sA.data.empire, tripA), IM.travellers(sB.data.empire, tripB)
	check("travellers: the real field rep + engineer of each trip", #peopleA == 2 and #peopleB == 2, #peopleA .. "/" .. #peopleB)
	local namesA, namesB = namesOf(peopleA), namesOf(peopleB)
	X.advance(0.75)
	check("before the call: the trips are pending (DriverService holds the field cars)", X.Itin.pending(pA.UserId, keyA) and X.Itin.pending(pB.UserId, keyB))
	check("no field car left with the colleagues before the call", not fieldCarries(pA, namesA) and not fieldCarries(pB, namesB))
	check("Ben's staff jet waits while he is asked (JetService honours holds)", (X.Jet.available(pB)) == true)
	X.advance(2.5)

	------------------------------------------------------------------ the assistant's calls
	local callA, callB = itinCalls(sA)[1] or {}, itinCalls(sB)[1] or {}
	check("one assistant call each", #itinCalls(sA) == 1 and #itinCalls(sB) == 1, #itinCalls(sA) .. "/" .. #itinCalls(sB))
	check("offers: Ada shuttle, Ben our jet", st(pA).state == "offer" and st(pA).plan.how == "shuttle" and st(pB).state == "offer" and st(pB).plan.how == "jet",
		tostring(st(pA).plan and st(pA).plan.how) .. "/" .. tostring(st(pB).plan and st(pB).plan.how))
	for _, pr in { { callA, peopleA, "Ada" }, { callB, peopleB, "Ben" } } do
		for _, person in pr[2] do check(pr[3] .. "'s call names " .. IM.firstName(person.name), has(pr[1].text, IM.firstName(person.name)), pr[1].text) end
		check(pr[3] .. "'s call: they travel with the founder", has(pr[1].text, "travel with you") or has(pr[1].text, "come along"), pr[1].text)
		check(pr[3] .. "'s call: Meridian Grand Hotel + a free driver", has(pr[1].text, "Meridian Grand Hotel") and has(pr[1].text, "Your driver "), pr[1].text)
	end
	check("Ada's call books the shuttle, Ben's our jet", has(callA.text, st(pA).plan.flight or "?") and has(callB.text, "our jet (Captain "), callA.text .. " || " .. callB.text)
	check("the two companies' calls name different colleagues (own staff)", (function()
		for n in namesA do if namesB[n] then return false end end
		return true
	end)())
	info("calls: " .. tostring(callA.text) .. " || " .. tostring(callB.text))

	------------------------------------------------------------------ Go (both)
	check("Ada: Go -> pickup", answer(sA, "accept").ok == true and st(pA).state == "pickup")
	check("Ben: Go -> pickup", answer(sB, "accept").ok == true and st(pB).state == "pickup")
	check("both: the colleagues ride in the founder's car (carry) and fly with him (together)", st(pA).carry == true and st(pA).together == true and st(pB).carry == true and st(pB).together == true)
	check("both: published itinerary folders with the companions", folderOf(pA) and folderOf(pA):FindFirstChild("Companion2") ~= nil and folderOf(pB) and folderOf(pB):FindFirstChild("Companion2") ~= nil)
	check("both: 5 calendar items", itinCal(sA) == 5 and itinCal(sB) == 5, itinCal(sA) .. "/" .. itinCal(sB))
	local tGo = X.T
	check("both cars come (a timed pick-up for the shuttle, at once for the jet)", X.waitFor(function() return carWaiting(pA) and carWaiting(pB) end, 600))
	numbers.carWait = math.floor(X.T - tGo)
	local rfA, rfB = rideOf(pA), rideOf(pB)
	check("each founder's own company car, own driver", rfA and rfB and rfA.Parent.Name == "Drivers_9101" and rfB.Parent.Name == "Drivers_9102" and rfA:GetAttribute("Kind") == "founder")
	check("the colleagues wait at the car (C1, C2 in both ride folders)", rfA and rfA:FindFirstChild("C1") ~= nil and rfA:FindFirstChild("C2") ~= nil and rfB and rfB:FindFirstChild("C2") ~= nil)
	check("one driver busy, one free per company", (X.Driver.free(pA)) == 1 and (X.Driver.free(pB)) == 1, tostring((X.Driver.free(pA))) .. "/" .. tostring((X.Driver.free(pB))))
	check("still no field car with the colleagues", not fieldCarries(pA, namesA) and not fieldCarries(pB, namesB))
	check("Ada boards", (X.boardCar(pA, sA)))
	check("Ben boards", (X.boardCar(pB, sB)))
	check("Ada at the airport (company booking), Ben in the jet", X.waitFor(function() return st(pA).state == "airport" and st(pB).state == "flight" end, 400),
		tostring(st(pA).state) .. "/" .. tostring(st(pB).state))
	numbers.driveToAirport = math.floor(X.T - tGo)
	local bk = X.Shuttle.booking(pA)
	check("Ada: prepaid company booking, price 0, with both colleagues", bk ~= nil and bk.prepaid == true and bk.price == 0 and bk.trip == keyA and bk.companions and #bk.companions == 2)
	check("Ben: our jet, no shuttle booking", st(pB).sub == "jet" and X.Jet.flightOf(pB) ~= nil and X.Shuttle.booking(pB) == nil)
	local jetFolder = RS.CompanyJets:FindFirstChild("Jet_9102")
	local jetComp = jetFolder and jetFolder:FindFirstChild("Companions")
	check("Ben's colleagues are aboard the jet (JetService companions)", jetComp ~= nil and #jetComp:GetChildren() == 2, jetComp and #jetComp:GetChildren())
	local staffB = X.Jet.staffOf(pB)[keyB]
	check("Ben's staff trip flies with him (no separate staff flight)", staffB == nil or staffB.state ~= "wait_out", staffB and staffB.state)
	-- Ada walks to gate A1 and boards the shuttle
	local paxSeen = {}
	extraTick = function()
		local pax = RS.Shuttle:FindFirstChild("Passengers")
		if pax then for _, m in pax:GetChildren() do if m:GetAttribute("CompanionOf") == pA.UserId then paxSeen[m:GetAttribute("PassengerName") or ""] = true end end end
	end
	X.standAt(pA, FP.HOME_GATES[1] + Vector3.new(2, 0, 3))
	check("Ada flies (shuttle)", X.waitFor(function() return st(pA).state == "flight" end, 600), st(pA).state)
	X.advance(1)
	extraTick = nil
	for n in namesA do check("Ada's colleague " .. IM.firstName(n) .. " is a passenger of her leg", paxSeen[n] == true) end
	numbers.takeoffA = math.floor(X.T - tGo)
	check("both flying at the same time (City state)", X.City.state(pA) == "flying" or st(pB).state ~= "flight" or X.City.state(pB) == "flying")

	------------------------------------------------------------------ Port Meridian: limousine -> meeting
	local landedB, landedA = nil, nil
	check("both landed in Port Meridian -> limo step", X.waitFor(function()
		if not landedB and st(pB).state == "limo" then landedB = X.T end
		if not landedA and st(pA).state == "limo" then landedA = X.T end
		return landedA ~= nil and landedB ~= nil
	end, 900), tostring(st(pA).state) .. "/" .. tostring(st(pB).state))
	numbers.landA, numbers.landB = math.floor((landedA or X.T) - tGo), math.floor((landedB or X.T) - tGo)
	check("both abroad", X.City.state(pA) == "abroad" and X.City.state(pB) == "abroad")
	check("arrival messages", findMsg(sA, "Arrived in Port Meridian") ~= nil and findMsg(sB, "Arrived in Port Meridian") ~= nil)
	-- each boards his limousine when it waits (two bookings at the stand: the second waits for the next car)
	local inMeeting = {}
	check("both by limousine to the Helix tower -> meeting", X.waitFor(function()
		for _, pr in { { pA, sA }, { pB, sB } } do
			local p, s = pr[1], pr[2]
			if st(p).state == "limo" and carWaiting(p) then X.boardCar(p, s) end
			if st(p).state == "meeting" then inMeeting[p] = true end
		end
		return inMeeting[pA] and inMeeting[pB]
	end, 900, 0.5), tostring(st(pA).state) .. "/" .. tostring(st(pA).sub) .. " " .. tostring(st(pB).state) .. "/" .. tostring(st(pB).sub))
	check("same client tower: two seat sets", folderOf(pA) ~= nil and folderOf(pB) ~= nil and folderOf(pA):GetAttribute("SeatSet") ~= folderOf(pB):GetAttribute("SeatSet"))
	check("Ada joins the meeting (real CityBuilder prompt -> EmpireService.joinMeeting)", joinMeeting(pA, "Helix Research") and tripA.joined == true and tripB.joined ~= true)
	check("Ben joins the meeting", joinMeeting(pB, "Helix Research") and tripB.joined == true)
	numbers.meetingA, numbers.meetingB = math.floor(X.T - tGo), math.floor(X.T - tGo)

	------------------------------------------------------------------ hotel
	check("both -> hotel step after the talk", X.waitFor(function() return st(pA).state == "hotel" and st(pB).state == "hotel" end, IM.MEETING_TALK + 20))
	local door = X.Drive.clientPlace("Helix Research").door.Position
	X.standAt(pA, door); X.standAt(pB, door + Vector3.new(4, 0, 0))
	local arrivedHotel = {}
	check("both by car to the Meridian Grand", X.waitFor(function()
		for _, pr in { { pA, sA }, { pB, sB } } do
			local p, s = pr[1], pr[2]
			if st(p).sub ~= "riding" and st(p).sub ~= "arrived" and carWaiting(p) then X.boardCar(p, s) end
			if st(p).sub == "arrived" then arrivedHotel[p] = true end
		end
		return arrivedHotel[pA] and arrivedHotel[pB]
	end, 600, 0.5), tostring(st(pA).sub) .. "/" .. tostring(st(pB).sub))
	local promptA = M.game.Workspace.ItineraryPrompts:FindFirstChild("ItinRoom_" .. pA.UserId)
	if promptA then
		X.standAt(pB, promptA.Position + Vector3.new(0, 0, -3))
		X.firePrompt(promptA.RoomPrompt, pB)
		check("Ben cannot check Ada in (owner-only prompt)", st(pA).checkedIn == false)
		X.advance(1.2)
	end
	check("Ada checks in", checkIn(pA))
	check("Ben checks in", checkIn(pB))
	numbers.hotelA = math.floor(X.T - tGo)

	------------------------------------------------------------------ Ada: Fly home now (the colleagues stay)
	check("Ada: Fly home now -> return, colleagues stay", X.act(sA, { action = "leave" }).ok == true and st(pA).state == "return" and st(pA).stay == true)
	X.standAt(pA, X.Drive.place("pm_hotel").door.Position)
	check("Ada: limousine to Port Meridian Airport -> gate", X.waitFor(function()
		if carWaiting(pA) and st(pA).sub ~= "riding" then X.boardCar(pA, sA) end
		return st(pA).sub == "gate"
	end, 500, 0.5), tostring(st(pA).sub))
	local bk2 = X.Shuttle.booking(pA)
	check("Ada: company booking home without the colleagues", bk2 ~= nil and bk2.prepaid == true and bk2.to == "home" and (bk2.companions == nil or #bk2.companions == 0))
	X.standAt(pA, FP.PM_GATES[1] + Vector3.new(2, 0, 2))
	check("Ada: flight home -> home step", X.waitFor(function() return st(pA).state == "home" end, 1200), tostring(st(pA).state) .. "/" .. tostring(st(pA).sub))
	check("Ada: driver home -> trip finished", X.waitFor(function()
		if carWaiting(pA) and st(pA).sub ~= "riding" then X.boardCar(pA, sA) end
		return st(pA).state == "none"
	end, 600, 0.5), tostring(st(pA).state) .. "/" .. tostring(st(pA).sub))
	numbers.homeA = math.floor(X.T - tGo)
	check("Ada: Trip finished message, calendar cleared, folder gone", findMsg(sA, "Trip finished") ~= nil and itinCal(sA) == 0 and folderOf(pA) == nil and pA:GetAttribute("Itinerary") == nil)
	check("Ada's first trip still runs (the colleagues stay in Port Meridian)", IM.findTrip(sA.data.empire, keyA) == tripA)
	X.advance(1)
	check("Ada's client: the banner was shown and is closed now", seenA.banner and (pgA:FindFirstChild("ItineraryBanner") == nil or not pgA.ItineraryBanner.Enabled) and Ctl.view() == nil)
	check("Ada's client: her colleagues walked with her, the client team sat at the table, her cars were drawn",
		seenA.followers >= 2 and seenA.team >= 2 and seenA.views >= 1, string.format("followers %d team %d views %d", seenA.followers, seenA.team, seenA.views))
	-- Ada's second pilot (CompanyOps: every second region / abroad pilot is hosted at the guest house): Ledger Finance
	-- comes to the HQ - nothing for the founder to travel to (no call)
	Ops.ensure(sA.data.empire).skip.ledger = nil
	local hosted = nil
	check("CompanyOps starts Ada's 2nd pilot: hosted at the guest house", X.waitFor(function()
		for _, t in trips(sA) do if t.client == "ledger" then hosted = t end end
		return hosted ~= nil
	end, 900, 0.5))
	Ops.ensure(sA.data.empire).skip.ledger = true
	X.advance(4)
	check("hosted visit: no call, no offer (ItineraryMath.needsFounder)", hosted ~= nil and hosted.hosted == true and #itinCalls(sA) == 1 and st(pA).state == "none",
		hosted and tostring(hosted.hosted) .. " calls " .. #itinCalls(sA) .. " " .. tostring(st(pA).state))

	------------------------------------------------------------------ Ben: waits at the hotel until the visit is over
	check("Ben still at the hotel (checked in)", st(pB).state == "hotel" and st(pB).checkedIn == true)
	check("Ben: the visit ends -> return with the colleagues", X.waitFor(function() return st(pB).state == "return" end, 2400, 0.5), tostring(st(pB).state))
	numbers.overB = math.floor((endedAt[sB][keyB] or X.T) - tGo)
	check("Ben: CompanyOps closed the visit (removed from tripList, trust with the meeting)", IM.findTrip(sB.data.empire, keyB) == nil
		and (Ops.ensure(sB.data.empire).trust.helix or 0) >= 0.5 + 0.15, Ops.ensure(sB.data.empire).trust.helix)
	check("Ben: the colleagues go home with him (not 'stay')", st(pB).stay == false)
	X.standAt(pB, X.Drive.place("pm_hotel").door.Position)
	check("Ben: limousine to Port Meridian Airport -> our jet home", X.waitFor(function()
		if carWaiting(pB) and st(pB).sub ~= "riding" then X.boardCar(pB, sB) end
		return st(pB).sub == "flight"
	end, 600, 0.5), tostring(st(pB).state) .. "/" .. tostring(st(pB).sub))
	check("Ben: jet flight home with the colleagues", X.Jet.flightOf(pB) ~= nil and jetFolder:FindFirstChild("Companions") ~= nil and #jetFolder.Companions:GetChildren() == 2,
		jetFolder:FindFirstChild("Companions") and #jetFolder.Companions:GetChildren())
	check("Ben: home step (deboard, then the driver)", X.waitFor(function() return st(pB).state == "home" end, 600), tostring(st(pB).state))
	check("Ben: driver home with the colleagues -> trip finished", X.waitFor(function()
		local rf = rideOf(pB)
		if rf and carWaiting(pB) and st(pB).sub ~= "riding" then
			check("Ben's car home carries the colleagues", rf:FindFirstChild("C1") ~= nil and rf:FindFirstChild("C2") ~= nil)
			X.boardCar(pB, sB)
		end
		return st(pB).state == "none"
	end, 600, 0.5), tostring(st(pB).state) .. "/" .. tostring(st(pB).sub))
	numbers.homeB = math.floor(X.T - tGo)
	check("Ben: no field car fetched the colleagues (his car brought them)", not fieldCarries(pB, namesB))
	check("Ben: Trip finished", findMsg(sB, "Trip finished") ~= nil and itinCal(sB) == 0 and folderOf(pB) == nil)

	------------------------------------------------------------------ Ada's visit ends -> her next pilot -> she declines
	local backRide = false
	extraTick = function()
		for _, r in fieldRides(pA) do
			for _, m in r:GetChildren() do if namesA[m:GetAttribute("CompanionName") or ""] and r:GetAttribute("To") == "hq_entrance" then backRide = true end end
		end
	end
	check("Ada's first visit ends (CompanyOps)", X.waitFor(function() return IM.findTrip(sA.data.empire, keyA) == nil end, 2400, 0.5))
	numbers.overA = math.floor((endedAt[sA][keyA] or X.T) - tGo)
	check("Ada: trust with the meeting booked by CompanyOps", (Ops.ensure(sA.data.empire).trust.helix or 0) >= 0.5 + 0.15, Ops.ensure(sA.data.empire).trust.helix)
	local trip2 = nil
	check("CompanyOps starts Ada's next Helix pilot (same tick or the next office hours)", X.waitFor(function()
		for _, t in trips(sA) do if t.client == "helix" and IM.tripKey(t) ~= keyA then trip2 = t end end
		return trip2 ~= nil
	end, 1300, 0.5))
	if trip2 then
		local key2 = IM.tripKey(trip2)
		Ops.ensure(sA.data.empire).skip.helix = true -- no third one
		local people2 = IM.travellers(sA.data.empire, trip2)
		local names2 = namesOf(people2)
		check("second offer to Ada", X.waitFor(function() return st(pA).state == "offer" and st(pA).key == key2 end, 30), st(pA).state)
		local r = answer(sA, "decline")
		check("Ada declines -> 'travel without you', no itinerary", r.ok == true and has(r.text, "without you") and st(pA).state == "none" and rideOf(pA) == nil, r.text)
		check("declined: the colleagues are not held for her", X.Itin.holds(pA.UserId, key2) == false and X.Itin.pending(pA.UserId, key2) == false)
		check("declined: a field car takes the colleagues to the airport", X.waitFor(function() return fieldCarries(pA, names2) end, 120))
		check("declined: the economy trip is untouched", IM.findTrip(sA.data.empire, key2) == trip2 and trip2.joined == nil)
		check("declined trip ends by itself (CompanyOps), no founder involved", X.waitFor(function() return IM.findTrip(sA.data.empire, key2) == nil end, 2700, 1), (IM.left(sA.data.empire, trip2)))
		numbers.declineStart, numbers.declineEnd = math.floor((startedAt[sA][key2] or X.T) - tGo), math.floor((endedAt[sA][key2] or X.T) - tGo)
	end
	extraTick = nil
	check("Ada's colleagues of the first visit were fetched at the arrivals kerb by a field car", backRide)

	------------------------------------------------------------------ settle: every leg of every car / plane ends
	-- (quiet = no trip, no ride, no flight, no passenger of ours for 120 s in a row: a field ride home starts only when
	-- the colleagues' shuttle has landed)
	local function busyNow()
		if #trips(sA) > 0 or #trips(sB) > 0 or X.Jet.status(pB).flying then return true end
		for _, f in RS.CompanyDrivers:GetChildren() do for _, r in f:GetChildren() do if string.sub(r.Name, 1, 5) == "Ride_" then return true end end end
		local pax = RS.Shuttle:FindFirstChild("Passengers")
		if pax then for _, m in pax:GetChildren() do
			local co = m:GetAttribute("Company")
			if co == sA.data.company.name or co == sB.data.company.name then return true end
		end end
		return false
	end
	local quiet, waited = 0, 0
	while quiet < 120 and waited < 2400 do
		X.advance(1, 0.5)
		waited += 1
		quiet = if busyNow() then 0 else quiet + 1
	end
	check("settled: 120 s without any trip, ride, flight or passenger of either company", quiet >= 120, waited)
	numbers.done = math.floor(X.T - tGo)

	------------------------------------------------------------------ cleanup
	local leftRides = {}
	for _, f in RS.CompanyDrivers:GetChildren() do
		if string.find(f.Name, "_left", 1, true) then table.insert(leftRides, f.Name) end
		for _, r in f:GetChildren() do if string.sub(r.Name, 1, 5) == "Ride_" then table.insert(leftRides, f.Name .. "/" .. r.Name .. ":" .. tostring(r:GetAttribute("State"))) end end
	end
	check("cleanup: no company car / limousine ride left", #leftRides == 0, table.concat(leftRides, ", "))
	check("cleanup: no itinerary folder, prompt or calendar item", #RS.CompanyItinerary:GetChildren() == 0 and #M.game.Workspace.ItineraryPrompts:GetChildren() == 0
		and itinCal(sA) == 0 and itinCal(sB) == 0)
	check("cleanup: no shuttle booking", X.Shuttle.booking(pA) == nil and X.Shuttle.booking(pB) == nil)
	local pax = RS.Shuttle:FindFirstChild("Passengers")
	local ours = 0
	if pax then for _, m in pax:GetChildren() do
		local co = m:GetAttribute("CompanionOf")
		if co == pA.UserId or co == pB.UserId or namesA[m:GetAttribute("PassengerName") or ""] or namesB[m:GetAttribute("PassengerName") or ""] then ours += 1 end
	end end
	check("cleanup: no shuttle passenger template of either company", ours == 0, ours)
	local js = X.Jet.status(pB)
	-- (the last flight's companion templates stay in Jet_<id>/Companions as data until the next flight; JetController
	-- draws them only while that flight runs - checked on the client below via the jet's status)
	check("cleanup: Ben's jet parked at home, no flight running", js.flying == false and js.at == "home" and jetFolder.Parent ~= nil, tostring(js.at) .. " flying=" .. tostring(js.flying))
	local staffLeft = 0
	for _, entry in X.Jet.staffOf(pB) do if entry.state ~= "done" then staffLeft += 1 end end
	check("cleanup: no staff work left for the jet", staffLeft == 0, staffLeft)
	check("cleanup: both founders at home, released (not anchored), attributes cleared", X.City.state(pA) == "home" and X.City.state(pB) == "home" and not pA.root.Anchored and not pB.root.Anchored
		and pA:GetAttribute("Itinerary") == nil and pB:GetAttribute("Itinerary") == nil and pA:GetAttribute("DriveRide") == nil and pB:GetAttribute("DriveRide") == nil
		and pB:GetAttribute("JetFlight") == nil)
	check("cleanup: all drivers free again", (X.Driver.free(pA)) == 2 and (X.Driver.free(pB)) == 2, tostring((X.Driver.free(pA))) .. "/" .. tostring((X.Driver.free(pB))))
	-- Ada's client: no NPC, car or beacon of any trip left in her world
	X.advance(3)
	local people = M.game.Workspace:FindFirstChild("ItineraryPeople")
	check("cleanup (Ada's client): no companion / client-team rig", Ctl.rigCount() == 0 and (people == nil or #people:GetChildren() == 0), Ctl.rigCount())
	check("cleanup (Ada's client): no beacon, banner closed", M.game.Workspace:FindFirstChild("ItineraryBeacon") == nil and Ctl.view() == nil)
	local nv, ng = 0, #DriveCtl._ghosts()
	local viewNames = {}
	for f in DriveCtl._views() do nv += 1; table.insert(viewNames, f:GetFullName() .. ":" .. tostring(f:GetAttribute("State")) .. ":" .. tostring(f:GetAttribute("Kind")) .. ":" .. tostring(f:GetAttribute("To"))) end
	if nv > 0 then print("views: " .. table.concat(viewNames, ", ")) end
	check("cleanup (Ada's client): no ride car / limousine drawn, no ghost car", nv == 0 and ng == 0, nv .. " views, " .. ng .. " ghosts")

	------------------------------------------------------------------ money: only CompanyOps (+ EmpireService wages) books
	local origins, bad, flows, trips_ = {}, {}, { [sA] = 0, [sB] = 0 }, { [sA] = 0, [sB] = 0 }
	local cats = {}
	for i = calls0 + 1, #X.econCalls do
		local c = X.econCalls[i]
		local who = callerOf(c.trace)
		origins[who] = (origins[who] or 0) + 1
		local amount, cat = flowOf(c)
		cats[cat] = true
		if who ~= "CompanyOps" and not (who == "EmpireService" and cat == "wages") then table.insert(bad, who .. ":" .. c.fn .. ":" .. tostring(cat)) end
		if c.fn == "spend" then table.insert(bad, "spend:" .. who .. ":" .. tostring(cat)) end
		if flows[c.s] then
			flows[c.s] += amount
			if cat == "trips" then trips_[c.s] -= amount end
		end
	end
	local originList = {}
	for k, v in origins do table.insert(originList, k .. "=" .. v) end
	table.sort(originList)
	numbers.econCalls = #X.econCalls - calls0
	numbers.origins = table.concat(originList, " ")
	check("money: every EconomyService call comes from CompanyOps.step / EmpireService wages", #bad == 0, table.concat(bad, ", "))
	check("money: no jet fuel / ticket / ride charge (no spend at all)", not cats.jetfuel and (function()
		for i = calls0 + 1, #X.econCalls do if X.econCalls[i].fn ~= "applyFlow" then return false end end
		return true
	end)())
	-- what CompanyOps.tripPlan charges for every trip it started (kind, crew, hosted, jet)
	local function plannedCost(s)
		local sum, n = 0, 0
		for _, t in started[s] do
			local c = Ops.client(t.client)
			local _, _, cost = Ops.tripPlan(c.trip, if t.hosted then 0 else t.crew, t.hosted == true, s.data.empire.jet == true)
			sum += cost; n += 1
		end
		return sum, n
	end
	local planA, nA = plannedCost(sA)
	local planB, nB = plannedCost(sB)
	check("trips CompanyOps started: Ada 3 (abroad, hosted, abroad), Ben 1 (abroad by jet)", nA == 3 and nB == 1, nA .. "/" .. nB)
	check("trip costs: Ada = 2 x shuttle trip + hosted visit, Ben = jet trip", math.abs(planA - (2 * costA + Ops.HOSTED.guests * Ops.HOSTED.nights * Ops.HOSTED.nightCost)) < 1e-6
		and math.abs(planB - costB) < 1e-6, planA .. "/" .. planB)
	for _, pr in { { sA, "Ada", planA }, { sB, "Ben", planB } } do
		local s, name, tripCost = pr[1], pr[2], pr[3]
		local dCash = s.data.money - cash0[s]
		local dLedger = ledgerNet(s) - ledger0[s]
		check("money: " .. name .. "'s cash change = the recorded flows", math.abs(dCash - flows[s]) < 1e-6 * math.max(1, math.abs(dCash)), string.format("%.2f vs %.2f", dCash, flows[s]))
		check("money: " .. name .. "'s ledger net change = cash change (whole-dollar booking)", math.abs(dLedger - dCash) <= 2 * Ops.LEDGER_CATEGORIES, string.format("%.2f vs %.2f", dLedger, dCash))
		check("money: " .. name .. "'s trip costs = CompanyOps.tripPlan", math.abs(trips_[s] - tripCost) < 1e-6, string.format("%.2f vs %.2f", trips_[s], tripCost))
		numbers[name .. "_cash"] = string.format("%+.0f", dCash)
		numbers[name .. "_trips"] = string.format("%.0f", trips_[s])
		numbers[name .. "_played"] = math.floor(s.data.empire.seconds - seconds0[s])
	end
	check("no background errors", M.stats.errors == errors0, M.stats.errors - errors0)
	check("no warnings in the log", M.stats.warnings == warnings0 and #warnings == 0, table.concat(warnings, " | "))
end

local ok, err = M.runMain(body, { timeout = 20000, maxSteps = 400000000 })
if not ok then failc += 1; print("CRASH " .. tostring(err)) end
if M.stats.errors > 0 then failc += 1; print("FAIL  background thread errors: " .. M.stats.errors) end
local keys = {}
for k in numbers do table.insert(keys, k) end
table.sort(keys)
local parts = {}
for _, k in keys do table.insert(parts, k .. "=" .. tostring(numbers[k])) end
print("e2e numbers: " .. table.concat(parts, " "))
print(string.format("trip_e2e: %d passed, %d failed", pass, failc))
