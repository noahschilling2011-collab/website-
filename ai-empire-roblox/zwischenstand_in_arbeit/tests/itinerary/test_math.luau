--!nocheck
-- itinerary package: ItineraryMath (pure) on the REAL modules in the mock.
--   trip keys + remote key validation, which trips need the founder (abroad / region pilots only), the travellers
--   (the REAL field rep + engineer: same people as PhoneMath.travellers and JetService.abroadTravellers), the plan
--   times (pick-up, the next reachable shuttle from the FlightPlan timetable, the jet timeline, limousine, meeting,
--   hotel, the first return departure after the economic trip ends, the ride home) for shuttle / jet / region /
--   already abroad / no driver, deterministic; every text (call, decline, driver honesty variants, banner of every
--   state, calendar items) shows exactly the plan's numbers in the phone's clock; meeting room seats from
--   CityPlan for every abroad / region client; area tests; the source creates no instances and moves no money.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_itinerary && cd tests/itinerary && ../../tools/luau test_math.luau -a .gen_itinerary
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_itinerary")
local M = require("../../harness/mock")
local sources = require(GEN .. "/sources")
M.loadTree(require(GEN .. "/manifest"), sources)
M.quiet = true
local G = M.G
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end
local function has(text, part) return typeof(text) == "string" and string.find(text, part, 1, true) ~= nil end

local function body()
	local Vector3, CFrame = G.Vector3, G.CFrame
	local RS = M.game.ReplicatedStorage
	local IM = M.require(RS.Shared.ItineraryMath)
	local Ops = M.require(RS.Shared.CompanyOps)
	local FP = M.require(RS.Shared.FlightPlan)
	local PhoneMath = M.require(RS.Shared.PhoneMath)
	local CityPlan = M.require(RS.Shared.Config.CityPlan)
	local EmpireMath = M.require(RS.Shared.EmpireMath)
	local Template = M.require(M.game.ServerScriptService.Server.Lib.Template)
	local okJet, JetService = pcall(M.require, M.game.ServerScriptService.Server.Services.JetService)
	local NOW = 1416666 * 1200 + 180 -- company time 10:00

	------------------------------------------------------------------ keys
	check("tripKey client:left", IM.tripKey({ client = "helix", left = 9000 }) == "helix:9000")
	check("tripKey of nil is empty", IM.tripKey(nil) == "")
	for _, good in { "helix:9000", "creative:0", "helix:-5", "orbit_games:123" } do check("validKey accepts " .. good, IM.validKey(good) == good) end
	for _, bad in { 123, "", "helix", "helix:", ":12", "a b:1", "helix:12.5", "helix:1;x", "helix:1\n", string.rep("a", 45) .. ":1234", {} } do
		check("validKey rejects " .. tostring(bad), IM.validKey(bad) == nil)
	end

	------------------------------------------------------------------ which trips need the founder
	local function trip(client, extra)
		local t = { client = client, kind = "sign", back = 12000, founder = false, hosted = false, crew = 2, left = 9000 }
		for k, v in extra or {} do t[k] = v end
		return t
	end
	local n1, t1 = IM.needsFounder(trip("helix"))
	check("abroad pilot needs the founder", n1 == true and t1 == "abroad")
	local n2, t2 = IM.needsFounder(trip("frontier"))
	check("frontier client (Orbit Systems) needs the founder", n2 == true and t2 == "abroad")
	local n3, t3 = IM.needsFounder(trip("creative"))
	check("region pilot needs the founder", n3 == true and t3 == "region")
	check("city pilot does not (the founder sells city clients himself)", IM.needsFounder(trip("helpdesk")) == false)
	check("check-in visit (renew) does not", IM.needsFounder(trip("helix", { kind = "renew" })) == false)
	check("founder's own trip does not", IM.needsFounder(trip("helix", { founder = true })) == false)
	check("hosted guest-house visit does not", IM.needsFounder(trip("helix", { hosted = true })) == false)
	check("unknown client / garbage does not", IM.needsFounder(trip("nope")) == false and IM.needsFounder(nil) == false and IM.needsFounder("x") == false)

	------------------------------------------------------------------ travellers (the REAL field staff)
	local data = Template.new()
	local e = data.empire
	e.office = 5
	e.employees = { researcher = 4, engineer = 6, curator = 2, marketer = 5 }
	EmpireMath.syncProfiles(e, 4242)
	e.seconds = 9000
	e.deals.tripList = {
		trip("helpdesk", { left = 8000, crew = 1 }), -- city pilot (field rep 1)
		trip("helix", { left = 8500 }), -- abroad pilot: rep 2 + engineer 1
		trip("creative", { left = 8600, crew = 1 }), -- region pilot crew 1: rep 3 only
		trip("frontier", { left = 8700 }), -- abroad pilot: rep 4 + engineer
		trip("nova", { left = 8800, founder = true }), -- founder's own: skipped in the count
	}
	local reps = Ops.fieldReps(e)
	check("fixture has field reps for every trip", reps >= 4, reps)
	for i, t in e.deals.tripList do
		if t.founder then continue end
		local people = IM.travellers(e, t)
		local rep, eng = PhoneMath.travellers(e, t)
		local r1 = people[1] and IM.firstName(people[1].name) or nil
		local e1 = nil
		for _, p in people do if p.role == "engineer" then e1 = IM.firstName(p.name) end end
		check("trip " .. i .. " rep == PhoneMath.travellers", r1 == rep, tostring(r1) .. " vs " .. tostring(rep))
		check("trip " .. i .. " engineer == PhoneMath.travellers", e1 == eng, tostring(e1) .. " vs " .. tostring(eng))
		check("trip " .. i .. " at most two companions", #people <= IM.MAX_COMPANIONS)
	end
	check("crew 1 region pilot: the rep alone", #IM.travellers(e, e.deals.tripList[3]) == 1 and IM.travellers(e, e.deals.tripList[3])[1].role == "marketer")
	check("abroad pilot crew 2: rep + engineer", #IM.travellers(e, e.deals.tripList[2]) == 2)
	if okJet then
		local jt = JetService.abroadTravellers(e)
		for _, idx in { 2, 4 } do
			local t = e.deals.tripList[idx]
			local mine = IM.travellers(e, t)
			local theirs = jt[IM.tripKey(t)]
			local same = theirs ~= nil and #theirs.people == #mine
			if same then for k, p in mine do if theirs.people[k].name ~= p.name or theirs.people[k].role ~= p.role then same = false end end end
			check("trip " .. idx .. " travellers == JetService.abroadTravellers", same)
		end
	else
		check("JetService loads", false, JetService)
	end
	check("travellers of nil trip: nobody", #IM.travellers(e, nil) == 0)
	check("firstName", IM.firstName("Mia Chen") == "Mia" and IM.firstName(nil) == "" and IM.firstName("Leo") == "Leo")
	local mia, leo = { name = "Mia Chen", role = "marketer" }, { name = "Leo Park", role = "engineer" }
	check("whoText two", IM.whoText({ mia, leo }) == "Mia from Growth & Sales and Leo from Engineering", IM.whoText({ mia, leo }))
	check("whoText one / none", IM.whoText({ mia }) == "Mia from Growth & Sales" and IM.whoText({}) == "")
	check("namesText", IM.namesText({ mia, leo }) == "Mia and Leo" and IM.namesText({ mia }) == "Mia" and IM.namesText({}) == "your team")

	------------------------------------------------------------------ times
	local fl, dep, bEnd, arr, legStart = IM.shuttleLeg("out", NOW)
	local cyc2, ls2, dep2, be2 = FP.nextLeg("out", NOW)
	check("shuttleLeg out = FlightPlan.nextLeg", dep == dep2 and bEnd == be2 and legStart == ls2, { dep, dep2 })
	check("shuttleLeg out flight number", fl == FP.leg("out").flight and has(fl, "PM"), fl)
	check("shuttleLeg: boarding still open at `at`, arrival after departure", bEnd >= NOW and dep >= bEnd - 1 and arr > dep, { NOW, bEnd, dep, arr })
	check("shuttleLeg arrival = deboarding start", arr == legStart + FP.leg("out").phases.deboarding.t0)
	local flb = IM.shuttleLeg("back", NOW)
	check("return flight number differs", flb == FP.leg("back").flight and flb ~= fl, flb)
	local jd, ja = IM.jetTimes("out", NOW)
	check("jet times: departs after start, lands later", jd >= NOW and ja > jd, { jd, ja })
	check("mmss", IM.mmss(0) == "0:00" and IM.mmss(61.4) == "1:01" and IM.mmss(-5) == "0:00" and IM.mmss(0 / 0) == "0:00" and IM.mmss(3600) == "60:00")
	local ct = IM.clockText(e, NOW, NOW + 600)
	local d0, h0 = PhoneMath.atClock(e, NOW, NOW + 600)
	check("clockText = the phone's conversion", ct == PhoneMath.when(d0, h0, Ops.day(e)), ct)
	check("atText today 'at', other day 'on Day'", has(IM.atText(e, NOW, NOW + 60), "at ") and has(IM.atText(e, NOW, NOW + 1200 * 2), "on Day"),
		IM.atText(e, NOW, NOW + 1200 * 2))
	-- night hours (company days turn at 08:00): never "Day 11 · 05:12", which reads as earlier than "Day 11 · 23:58"
	local BASE = 1416666 * 1200
	local today = Ops.day(e)
	local evening, lateNight, sameNight = BASE + 960, BASE + 1100, BASE + 1140 -- 20:48, 03:20, 05:12 of the same company day
	check("fixture: night clocks", PhoneMath.clock(Ops.hour(sameNight)) == "05:12" and PhoneMath.clock(Ops.hour(evening)) == "20:48", PhoneMath.clock(Ops.hour(sameNight)))
	check("tonight's small hours read 'tonight'", IM.clockText(e, evening, sameNight) == "05:12 tonight", IM.clockText(e, evening, sameNight))
	check("already after midnight: just the time", IM.clockText(e, lateNight, sameNight) == "05:12", IM.clockText(e, lateNight, sameNight))
	check("another day's small hours: 'night of Day N'", IM.clockText(e, evening, sameNight + 1200) == "night of Day " .. (today + 1) .. " · 05:12", IM.clockText(e, evening, sameNight + 1200))
	check("atText of night times", IM.atText(e, evening, sameNight) == "at 05:12 tonight" and IM.atText(e, evening, sameNight + 1200) == "in the night of Day " .. (today + 1) .. " · 05:12")
	check("daytime of another day unchanged", IM.clockText(e, evening, BASE + 1200 + 450) == "Day " .. (today + 1) .. " · 13:00", IM.clockText(e, evening, BASE + 1200 + 450))

	------------------------------------------------------------------ plan: abroad, shuttle, company driver
	local drv = { name = "Emma Stone", eta = 20, ride = 60, pickupAt = "the HQ entrance" }
	local three = { mia, leo, { name = "Zoe Kim", role = "researcher" } }
	-- the car called at once (schedule = false: what the plan looks like once the car is booked)
	local P0 = IM.plan({ tier = "abroad", client = "Helix Research", clientId = "helix", now = NOW, backAt = NOW + 2400, companions = three, driver = drv, schedule = false })
	check("abroad plan: shuttle, Port Meridian, Meridian Grand", P0.how == "shuttle" and P0.city == "Port Meridian" and P0.hotel == "Meridian Grand Hotel" and P0.from == "home")
	check("companions capped at two", #P0.companions == 2 and P0.companions[1] == mia)
	check("car at once: pick-up = now + driver eta, no timed pick-up", P0.pickupAt == NOW + 20 and P0.requestAt == nil)
	check("car at once: at the airport = pick-up + boarding + ride", P0.airportAt == NOW + 20 + 2 + 60, P0.airportAt and P0.airportAt - NOW)
	local f2, d2, be3, a2, ls2b = IM.shuttleLeg("out", P0.airportAt + IM.WALK_GATE)
	check("booked flight = next reachable departure after the walk to the gate", P0.flight == f2 and P0.departs == d2 and P0.boardEnd == be3 and P0.arrives == a2)
	check("boarding still open when he reaches the gate", P0.boardEnd >= P0.airportAt + IM.WALK_GATE)
	-- the timed pick-up (UX): no idling at gate A1 for most of the boarding - the car is called later, the SAME flight
	local P = IM.plan({ tier = "abroad", client = "Helix Research", clientId = "helix", now = NOW, backAt = NOW + 2400, companions = three, driver = drv })
	local shift = (ls2b + IM.GATE_EARLY) - (P0.airportAt + IM.WALK_GATE)
	check("fixture: the car called at once would be early at the gate", shift > IM.PICKUP_SLACK, shift)
	check("timed pick-up: same flight as the car at once", P.flight == P0.flight and P.departs == P0.departs and P.boardEnd == P0.boardEnd and P.arrives == P0.arrives)
	check("timed pick-up: the car is called `shift` s later", P.requestAt == NOW + shift and P.pickupAt == NOW + shift + 20, P.requestAt and P.requestAt - NOW)
	check("timed pick-up: at the gate GATE_EARLY s after the boarding opened", math.abs(P.airportAt + IM.WALK_GATE - (ls2b + IM.GATE_EARLY)) < 1e-6)
	check("timed pick-up: the boarding is still open long after he is at the gate", P.boardEnd - (P.airportAt + IM.WALK_GATE) >= 45, P.boardEnd - (P.airportAt + IM.WALK_GATE))
	check("timed pick-up: the meeting / return follow the same flight", P.meetingAt == P0.meetingAt and P.returnAt == P0.returnAt)
	-- a trip that starts shortly before a boarding: the car comes at once (nothing to gain)
	local soon = ls2b - (20 + 2 + 60 + IM.WALK_GATE) + 5
	local Psoon = IM.plan({ tier = "abroad", client = "Helix Research", now = soon, backAt = soon + 2400, driver = drv })
	check("boarding about to open: no timed pick-up", Psoon.requestAt == nil and Psoon.pickupAt == soon + 20, Psoon.requestAt)
	local Pq = IM.plan({ tier = "abroad", client = "Helix Research", now = NOW, backAt = NOW + 2400, driver = { name = "Emma", eta = 20, ride = 60, queued = true } })
	check("queued car: never a timed pick-up", Pq.requestAt == nil)
	local Pjt = IM.plan({ tier = "abroad", client = "Helix Research", now = NOW, backAt = NOW + 2400, driver = drv, jet = true })
	check("jet: never a timed pick-up (the jet leaves when he is there)", Pjt.requestAt == nil and Pjt.pickupAt == NOW + 20)
	local Prt = IM.plan({ tier = "region", client = "PixelForge", now = NOW, backAt = NOW + 1200, driver = drv })
	check("region: never a timed pick-up", Prt.requestAt == nil)
	check("meeting = landing + walk + limousine", P.meetingAt == P.arrives + IM.WALK_PM + IM.LIMO_SECS)
	check("hotel after the meeting", P.hotelAt == P.meetingAt + IM.HOTEL_AFTER)
	local earliest = math.max(P.backAt, P.hotelAt)
	local rf, rdep, _, rarr = IM.shuttleLeg("back", earliest)
	check("return = first departure home after the visit ends", P.returnFlight == rf and P.returnAt == rdep and P.returnAt >= P.backAt, { P.returnAt, P.backAt })
	check("home = return landing + ride home", P.homeAt == rarr + IM.RIDE_HOME)
	check("timeline ordered", P.requestAt < P.pickupAt and P.pickupAt < P.airportAt and P.airportAt < P.departs and P.departs < P.arrives and P.arrives < P.meetingAt and P.meetingAt < P.hotelAt and P.hotelAt <= P.returnAt and P.returnAt < P.homeAt)
	local P2 = IM.plan({ tier = "abroad", client = "Helix Research", clientId = "helix", now = NOW, backAt = NOW + 2400, companions = three, driver = drv })
	local same = true
	for k, v in P do if typeof(v) ~= "table" and P2[k] ~= v then same = false end end
	check("plan is deterministic", same)
	-- late in the game the return can't be before the economic end even when the meeting is long after it
	local Pshort = IM.plan({ tier = "abroad", client = "Helix Research", now = NOW, backAt = NOW + 10, driver = drv })
	check("short trip: return never before the hotel step", Pshort.returnAt >= Pshort.hotelAt)

	-- no driver: walk / own car estimate
	local Ps = IM.plan({ tier = "abroad", client = "Helix Research", now = NOW, backAt = NOW + 2400, driver = { self = true, reason = "NO_DRIVER" } })
	check("no driver: no pick-up time, airport after SELF_AIRPORT", Ps.pickupAt == nil and Ps.airportAt == NOW + IM.SELF_AIRPORT and Ps.requestAt == nil)
	-- jet
	local Pj = IM.plan({ tier = "abroad", client = "Helix Research", now = NOW, backAt = NOW + 2400, driver = drv, jet = true, captain = "Ana Ruiz" })
	local jd2, ja2 = IM.jetTimes("out", Pj.airportAt)
	check("jet plan: our jet, JetPlan timeline", Pj.how == "jet" and Pj.flight == "company jet" and Pj.departs == jd2 and Pj.arrives == ja2)
	check("jet return: company jet right after the visit", Pj.returnFlight == "company jet" and Pj.returnAt == math.max(Pj.backAt, Pj.hotelAt))
	-- already abroad
	local Pa = IM.plan({ tier = "abroad", client = "Helix Research", now = NOW, backAt = NOW + 2400, from = "abroad" })
	check("already in Port Meridian: limousine only", Pa.how == "limo" and Pa.departs == nil and Pa.flight == nil and Pa.meetingAt == NOW + IM.WALK_PM + IM.LIMO_SECS)
	-- region
	local Pr = IM.plan({ tier = "region", client = "PixelForge", clientId = "creative", now = NOW, backAt = NOW + 1200, driver = drv, companions = { mia } })
	check("region plan: car, Business City, City Hotel", Pr.how == "car" and Pr.city == "Business City" and Pr.hotel == "City Hotel" and Pr.flight == nil)
	check("region meeting = pick-up + ride", Pr.meetingAt == NOW + 20 + 2 + 60)
	check("region return = after the visit", Pr.returnAt == math.max(NOW + 1200, Pr.hotelAt) and Pr.returnFlight == nil)
	check("region 'from abroad' input is treated as home", IM.plan({ tier = "region", client = "PixelForge", now = NOW, backAt = NOW + 600, from = "abroad" }).from == "home")
	check("hotel names follow the provider", IM.plan({ tier = "abroad", client = "X", now = NOW, backAt = NOW, hotels = { abroad = "Grand Test" } }).hotel == "Grand Test")

	------------------------------------------------------------------ driver honesty
	check("driver waiting", IM.driverText(drv, "abroad") == "Your driver Emma is waiting at the HQ entrance.", IM.driverText(drv, "abroad"))
	check("timed pick-up names the time", IM.driverText(drv, "abroad", "at 10:56") == "Your driver Emma picks you up at the HQ entrance at 10:56.", IM.driverText(drv, "abroad", "at 10:56"))
	check("no driver yet", IM.driverText({ self = true, reason = "NO_DRIVER" }, "abroad") == "We don't have a company driver yet: the GPS shows you the way to City Airport.", IM.driverText({ self = true, reason = "NO_DRIVER" }, "abroad"))
	check("too far", has(IM.driverText({ self = true, reason = "TOO_FAR" }, "region"), "too far from a pick-up point: the GPS shows you the way to the office"))
	check("own car", has(IM.driverText({ self = true, reason = "LEAVE_VEHICLE" }, "abroad"), "in your own car"))
	check("nil driver", has(IM.driverText(nil, "abroad"), "No company car can pick you up right now"))
	check("queued with real eta", IM.driverText({ name = "Emma", queued = true, eta = 125 }, "abroad") == "All cars are out - the next one is at the HQ entrance in about 2:05.", IM.driverText({ name = "Emma", queued = true, eta = 125 }, "abroad"))
	check("queued without an estimate: no made-up 0:00, no driver name", IM.driverText({ name = "Theo", queued = true }, "region") == "All cars are out - the next one picks you up at the HQ entrance."
		and not has(IM.driverText({ name = "Theo", queued = true, eta = 0 }, "region"), "0:00") and not has(IM.driverText({ name = "Theo", queued = true }, "region"), "Theo"))
	check("night on call", has(IM.driverText({ name = "Emma", night = true, eta = 40 }, "abroad"), "on call tonight") and has(IM.driverText({ name = "Emma", night = true, eta = 40 }, "abroad"), "0:40"))
	check("other pick-up point", IM.driverText({ name = "Emma", eta = 30, pickupAt = "the Helix Research tower" }, "abroad") == "Your driver Emma picks you up at the Helix Research tower (about 0:30).")

	------------------------------------------------------------------ call texts
	local title, text = IM.callText(P, e, NOW, false)
	check("call title", title == "Helix Research wants to meet")
	check("call names city, flight, departure, hotel", has(text, "Meeting in Port Meridian: I booked the shuttle " .. P.flight .. " " .. IM.atText(e, NOW, P.departs) .. " and the Meridian Grand Hotel."), text)
	check("call names the real colleagues (two: first names)", has(text, "Mia and Leo travel with you."), text)
	check("call names the driver + the timed pick-up", has(text, "Your driver Emma picks you up at the HQ entrance " .. IM.atText(e, NOW, P.pickupAt) .. "."), text)
	check("call leaves the return to the calendar (short call)", not has(text, "Return") and not has(text, P.returnFlight), text)
	check("call ends with the question", has(text, "Shall we go?") and not has(text, "We leave in"))
	local _, text0 = IM.callText(P0, e, NOW, false)
	check("car at once: 'is waiting at the HQ entrance'", has(text0, "Your driver Emma is waiting at the HQ entrance."), text0)
	local _, autoText = IM.callText(P, e, NOW, true)
	check("auto call: countdown sentence with the button's label", has(autoText, "We leave in " .. IM.COUNTDOWN .. " s - tap Not this time to stay."), autoText)
	local Pahead = IM.plan({ tier = "abroad", client = "Helix Research", now = NOW, backAt = NOW + 2400, companions = { mia, leo }, driver = drv, ahead = true })
	local _, aheadText = IM.callText(Pahead, e, NOW, false)
	check("ahead: colleagues meet him at the gate", has(aheadText, "Mia and Leo went ahead and wait at the gate."), aheadText)
	local Pair = IM.plan({ tier = "abroad", client = "Helix Research", now = NOW, backAt = NOW + 2400, companions = { mia, leo }, driver = drv, ahead = true, aheadBy = "air" })
	local _, airText = IM.callText(Pair, e, NOW, false)
	check("ahead by air: colleagues already flying, meet him in Port Meridian", has(airText, "Mia and Leo already fly out and meet you in Port Meridian."), airText)
	local Pone = IM.plan({ tier = "abroad", client = "Helix Research", now = NOW, backAt = NOW + 2400, companions = { mia }, driver = drv, ahead = true })
	local _, oneText = IM.callText(Pone, e, NOW, false)
	check("ahead alone: singular verbs", has(oneText, "Mia went ahead and waits at the gate."), oneText)
	local Pjet = IM.plan({ tier = "abroad", client = "Helix Research", now = NOW, backAt = NOW + 2400, companions = { mia, leo }, driver = drv, ahead = true, aheadBy = "car", jet = true })
	local _, jetAheadText = IM.callText(Pjet, e, NOW, false)
	check("ahead by car, our jet: they wait at our jet (no gate for the jet)", Pjet.how == "jet" and has(jetAheadText, "Mia and Leo went ahead and wait at our jet.") and not has(jetAheadText, "gate"), jetAheadText)
	local Pone2 = IM.plan({ tier = "abroad", client = "Helix Research", now = NOW, backAt = NOW + 2400, companions = { mia }, driver = drv })
	local _, one2Text = IM.callText(Pone2, e, NOW, false)
	check("one colleague: with the team (brief 24)", has(one2Text, "Mia from Growth & Sales travels with you."), one2Text)
	check("aheadBy defaults to car when ahead", Pone.aheadBy == "car" and P.aheadBy == nil)
	local _, jetText = IM.callText(Pj, e, NOW, false)
	check("jet call: our jet with the captain", has(jetText, "I booked our jet (Captain Ana Ruiz) " .. IM.atText(e, NOW, Pj.departs) .. " and the Meridian Grand Hotel."), jetText)
	local _, aloneText = IM.callText(Ps, e, NOW, false)
	check("alone + no driver: honest", has(aloneText, "You travel alone this time.") and has(aloneText, "We don't have a company driver yet"), aloneText)
	local _, abroadText = IM.callText(Pa, e, NOW, false)
	check("already abroad variant", has(abroadText, "You're already in Port Meridian") and not has(abroadText, "shuttle"), abroadText)
	local Pjoin = IM.plan({ tier = "abroad", client = "Helix Research", now = NOW, backAt = NOW + 2400, from = "abroad", companions = { mia, leo }, joinAt = NOW + 300, joinFlight = "PM 101" })
	local _, joinText = IM.callText(Pjoin, e, NOW, false)
	check("already abroad: the colleagues fly out after him (honest arrival)", has(joinText, "Mia and Leo fly out on PM 101 and join you at the tower " .. IM.atText(e, NOW, NOW + 300) .. "."), joinText)
	check("joinAt only when he starts abroad", Pjoin.joinAt == NOW + 300 and IM.plan({ tier = "abroad", client = "X", now = NOW, backAt = NOW, joinAt = NOW + 5 }).joinAt == nil)
	local _, regionText = IM.callText(Pr, e, NOW, false)
	check("region call: Business City, City Hotel (the visit end is in the calendar)", has(regionText, "A pilot meeting at their office in Business City; I booked the City Hotel.")
		and has(regionText, "Mia from Growth & Sales comes along.") and not has(regionText, "visit ends"), regionText)
	-- short enough for the phone's call sheet (~7 lines of ~36 characters at 844x390); also when every time is on
	-- another company day ("on Day 10 · 08:42") and with long staff / client names
	local NIGHTSTART = 1416666 * 1200 + 1150
	local longNames = { { name = "Valentina Rodriguez", role = "marketer" }, { name = "Maximilian Okonkwo", role = "engineer" } }
	local variants = { P, P0, Pahead, Pair, Pone, Pj, Ps, Pa, Pjoin, Pr, Pq,
		IM.plan({ tier = "abroad", client = "Nova Infrastructure", now = NIGHTSTART, backAt = NIGHTSTART + 2400, companions = longNames, driver = drv }),
		IM.plan({ tier = "abroad", client = "Nova Infrastructure", now = NIGHTSTART, backAt = NIGHTSTART + 2400, companions = { longNames[1] }, driver = { name = "Emma", queued = true, eta = 300 }, ahead = true }),
		IM.plan({ tier = "region", client = "PixelForge", now = NIGHTSTART, backAt = NIGHTSTART + 1200, companions = { longNames[1] }, driver = { name = "Emma", queued = true } }) }
	local longest, longestText, longestAuto, longestAutoText = 0, "", 0, ""
	for _, pl in variants do
		local _, t = IM.callText(pl, e, NOW, false)
		if #t > longest then longest, longestText = #t, t end
		local _, ta = IM.callText(pl, e, NOW, true)
		if #ta > longestAuto then longestAuto, longestAutoText = #ta, ta end
	end
	check("every call text <= 230 characters (call sheet)", longest <= 230, longest .. ": " .. longestText)
	check("every auto-trip message <= 270 characters (phone inbox)", longestAuto <= 270, longestAuto .. ": " .. longestAutoText)
	check("decline texts", IM.declineText({ mia, leo }) == "Okay. Mia and Leo travel without you; you'll get the report here." and IM.declineText({ mia }) == "Okay. Mia travels without you; you'll get the report here."
		and IM.declineText({}) == "Okay. The team travels without you; you'll get the report here.")

	------------------------------------------------------------------ banner of every state
	local function snap(state, extra)
		local s = { state = state, tier = "abroad", client = "Helix Research", plan = P, companions = { mia, leo } }
		for k, v in extra or {} do s[k] = v end
		return s
	end
	local function ids(b) return table.concat(b.buttons, ",") end
	local bc = IM.banner(snap("countdown", { countdownEnd = NOW + 10, flight = P.flight, departs = P.departs }), e, NOW)
	check("countdown: timer to the end, go/decline", bc.timerAt == NOW + 10 and ids(bc) == "go,decline" and has(bc.sub, "with Mia and Leo") and has(bc.sub, P.flight), bc.sub)
	local bo = IM.banner(snap("offer", { flight = P.flight, departs = P.departs }), e, NOW)
	check("offer: go/decline, no timer", ids(bo) == "go,decline" and bo.timerAt == nil and has(bo.title, "Helix Research"))
	local boa = IM.banner({ state = "offer", tier = "abroad", client = "Helix Research", plan = Pahead, companions = { mia, leo } }, e, NOW)
	local boair = IM.banner({ state = "offer", tier = "abroad", client = "Helix Research", plan = Pair, companions = { mia, leo } }, e, NOW)
	check("offer banner: honest team tag (went ahead / fly ahead, never 'with' them then)", has(boa.sub, "Mia and Leo went ahead") and has(boair.sub, "Mia and Leo fly ahead")
		and not has(boa.sub, "with Mia") and not has(boair.sub, "with Mia"), boa.sub .. " | " .. boair.sub)
	local bp = IM.banner(snap("pickup", { sub = "coming", eta = NOW + 20, driver = "Emma Stone" }), e, NOW)
	check("pickup: step 1 of 7, timer = car eta", bp.step == 1 and bp.steps == 7 and bp.timerAt == NOW + 20 and bp.stepName == "Driver", bp.step)
	local bself = IM.banner(snap("pickup", { sub = "self", reason = "NO_DRIVER" }), e, NOW)
	check("pickup self: call car + cancel, GPS", ids(bself) == "retry,cancel" and has(bself.sub, "GPS"))
	local bfar = IM.banner(snap("pickup", { sub = "self", reason = "TOO_FAR" }), e, NOW)
	check("pickup too far: names the pick-up points", has(bfar.sub, "pick-up point"))
	local ba = IM.banner(snap("airport", { sub = "gate", flight = P.flight, departs = P.departs, boardEnd = P.boardEnd }), e, NOW)
	check("airport: step 2", ba.step == 2 and ba.stepName == "Airport")
	local bf = IM.banner(snap("flight", { flight = P.flight, arrives = P.arrives }), e, NOW)
	check("flight: no buttons, landing time", #bf.buttons == 0 and has(bf.sub, IM.clockText(e, NOW, P.arrives)) and bf.step == 3)
	local bl = IM.banner(snap("limo", { sub = "riding", carry = true }), e, NOW)
	check("limo riding: step 4, colleagues with him", bl.step == 4 and has(bl.sub, "Mia and Leo with you") and ids(bl) == "leave", bl.sub)
	local bm = IM.banner(snap("meeting"), e, NOW)
	check("meeting: press Start meeting", has(bm.sub, "Start meeting") and bm.step == 5)
	local bj = IM.banner(snap("meeting", { joined = true }), e, NOW)
	check("meeting joined: trust +15%", bj.title == "Meeting · Helix Research" and has(bj.sub, "joined in person: trust +15%") and bj.action == "Joined · trust +15%", bj.title)
	check("meeting: short title + the action line for the folded chip", bm.title == "Meeting · Helix Research" and bm.action == "Press Start meeting at the table" and has(bm.sub, "Mia and Leo are with you"))
	local bmj = IM.banner(snap("meeting", { joinAt = NOW + 120 }), e, NOW)
	check("meeting while the colleagues still fly out: their arrival, not 'with you'", has(bmj.sub, "Mia and Leo arrive " .. IM.clockText(e, NOW, NOW + 120)) and not has(bmj.sub, "with you"), bmj.sub)
	local bh = IM.banner(snap("hotel"), e, NOW)
	check("hotel: return flight + time", has(bh.sub, P.returnFlight .. " " .. IM.clockText(e, NOW, P.returnAt)) and bh.step == 6, bh.sub)
	local bhr = IM.banner(snap("hotel", { room = "Royal Penthouse 1001", checkedIn = true }), e, NOW)
	check("hotel provider room", bhr.title == "Royal Penthouse 1001" and has(bhr.sub, "Checked in"), bhr.title)
	check("hotel: the action says check in", bh.action == "Check in at the reception", bh.action)
	-- honest colleague lines (review: no 'wait at the gate' after they flew ahead)
	local bat = IM.banner(snap("airport", { sub = "gate", flight = P.flight, boardEnd = NOW + 40, together = true }), e, NOW)
	check("airport, together: they wait at the gate", has(bat.sub, "Mia and Leo wait at the gate") and bat.action == "Walk to gate A1", bat.sub)
	local baf = IM.banner(snap("airport", { sub = "gate", flight = P.flight, boardEnd = NOW + 40, together = false }), e, NOW)
	check("airport, flew ahead: says so", has(baf.sub, "Mia and Leo flew ahead · they meet you in Port Meridian") and not has(baf.sub, "wait at the gate"), baf.sub)
	local bjt = IM.banner(snap("airport", { sub = "jet", together = false }), e, NOW)
	check("jet, not together: no 'board with you'", not has(bjt.sub, "board with you"))
	local bjw = IM.banner(snap("airport", { sub = "jet", together = true }), e, NOW)
	check("jet, together: 'board with you'", has(bjw.sub, "Mia and Leo board with you"))
	local bsch = IM.banner(snap("pickup", { sub = "scheduled", pickupAt = NOW + 90, flight = P.flight, departs = P.departs, driver = "Emma Stone", carry = true }), e, NOW)
	check("timed pick-up banner: who, when, which flight, Call car now", has(bsch.sub, "Emma picks you up at the HQ entrance at " .. IM.clockText(e, NOW, NOW + 90) .. " for " .. P.flight)
		and bsch.timerAt == NOW + 90 and bsch.timerLabel == "Pick-up in" and ids(bsch) == "retry,cancel", bsch.sub)
	local bdb = IM.banner(snap("limo", { sub = "deboard", deboardUntil = NOW + 15 }), e, NOW)
	check("deboard: the colleagues get off the plane, limousine timer", has(bdb.sub, "Mia and Leo are getting off the plane") and bdb.timerAt == NOW + 15, bdb.sub)
	local bwt = IM.banner(snap("pickup", { sub = "waiting", driver = "Emma Stone", carry = true }), e, NOW)
	check("pickup waiting: get in", has(bwt.sub, "Emma is waiting at the HQ entrance") and bwt.action == "Your car is waiting - get in", bwt.sub)
	local brf = IM.banner(snap("return", { sub = "flight", flight = "PM 102", arrives = NOW + 100 }), e, NOW)
	check("return flight: a flight banner (not the limousine)", brf.title == "Flight to City Airport" and #brf.buttons == 0 and has(brf.sub, "lands"), brf.title)
	-- every action line fits the folded chip
	local maxAct, maxActText = 0, ""
	for _, st0 in { { "pickup", { sub = "self" } }, { "pickup", { sub = "riding" } }, { "pickup", { sub = "scheduled", pickupAt = NOW + 30 } }, { "pickup", { sub = "waiting" } },
		{ "airport", { sub = "gate" } }, { "airport", { sub = "jetwait" } }, { "flight", { arrives = NOW + 600 } }, { "limo", { sub = "self" } }, { "limo", { sub = "riding" } },
		{ "limo", { sub = "waiting" } }, { "limo", { sub = "deboard" } }, { "meeting", {} }, { "meeting", { joined = true } }, { "hotel", {} }, { "hotel", { checkedIn = true } },
		{ "hotel", { sub = "riding" } }, { "return", { sub = "gate" } }, { "return", { sub = "self" } }, { "return", {} }, { "home", { sub = "self" } }, { "home", { sub = "deboard" } } } do
		local bb = IM.banner(snap(st0[1], st0[2]), e, NOW)
		if #bb.action > maxAct then maxAct, maxActText = #bb.action, bb.action end
	end
	check("every chip action <= 36 characters", maxAct <= 36, maxAct .. ": " .. maxActText)
	local brg = IM.banner(snap("return", { sub = "gate", flight = "PM 102", boardEnd = NOW + 30, stay = true }), e, NOW)
	check("return gate: boarding timer, colleagues stay", brg.timerAt == NOW + 30 and has(brg.sub, "stay until the visit ends") and brg.step == 7 and ids(brg) == "cancel")
	local bhm = IM.banner(snap("home", { driver = "Emma Stone" }), e, NOW)
	check("home: driver back to the HQ", bhm.title == "Welcome back" and has(bhm.sub, "Emma drives you back"))
	local brr = IM.banner({ state = "pickup", tier = "region", client = "PixelForge", companions = {}, sub = "coming", eta = NOW + 5 }, e, NOW)
	check("region pickup: 1 of 4 to the client", brr.step == 1 and brr.steps == 4 and brr.title == "To PixelForge")
	check("button texts", IM.buttonText("leave", "abroad") == "Fly home now" and IM.buttonText("leave", "region") == "Go home now" and IM.buttonText("go", "abroad") == "Go")
	check("one decline label everywhere (call sheet = banner = countdown)", IM.buttonText("decline", "abroad") == "Not this time" and IM.buttonText("decline", "abroad", "countdown") == "Not this time"
		and IM.buttonText("go", "abroad", "countdown") == "Go now" and IM.buttonText("retry", "abroad") == "Call car now")

	------------------------------------------------------------------ calendar items
	local items = IM.calendarItems(P, 3, e, NOW)
	local byKey = {}
	for _, it in items do byKey[it.key] = it end
	check("abroad calendar: 5 items with itin:<seq> keys", #items == 5 and byKey["itin:3:pickup"] and byKey["itin:3:flight"] and byKey["itin:3:meeting"] and byKey["itin:3:hotel"] and byKey["itin:3:return"])
	check("calendar times = plan times", byKey["itin:3:pickup"].at == P.pickupAt and byKey["itin:3:flight"].at == P.departs and byKey["itin:3:meeting"].at == P.meetingAt
		and byKey["itin:3:hotel"].at == P.hotelAt and byKey["itin:3:return"].at == P.returnAt)
	check("calendar flight item: lands at the plan's arrival", has(byKey["itin:3:flight"].detail, "lands " .. IM.clockText(e, NOW, P.arrives)) and byKey["itin:3:flight"].kind == "flight")
	check("calendar pickup names the driver + companions", has(byKey["itin:3:pickup"].detail, "Emma") and has(byKey["itin:3:pickup"].detail, "with Mia and Leo"))
	local ritems = IM.calendarItems(Pr, 4, e, NOW)
	check("region calendar: 4 items, no flight", #ritems == 4 and ritems[1].key == "itin:4:pickup")
	local aitems = IM.calendarItems(Pa, 5, e, NOW)
	check("already abroad calendar: no pickup / flight", #aitems == 3)
	local sitems = IM.calendarItems(Ps, 6, e, NOW)
	check("no driver calendar: 'To City Airport' on your own", sitems[1].title == "To City Airport" and has(sitems[1].detail, "On your own"))
	-- honest companion lines in the calendar too (review: "with Mia and Leo" on the car while a field car had taken them)
	local hitems = IM.calendarItems(Pahead, 7, e, NOW)
	check("calendar: they went ahead -> the car item does not claim they ride with him", has(hitems[1].detail, "Mia and Leo went ahead") and not has(hitems[1].detail, "with Mia"), hitems[1].detail)
	local Pjoin2 = IM.plan({ tier = "abroad", client = "Helix Research", now = NOW, backAt = NOW + 2400, from = "abroad", companions = { mia, leo }, joinAt = NOW + 3000, joinFlight = "PM 101" })
	local jitems = IM.calendarItems(Pjoin2, 8, e, NOW)
	local jm = nil
	for _, it in jitems do if it.key == "itin:8:meeting" then jm = it end end
	check("calendar: they land after the meeting starts -> 'join at', not 'with'", jm ~= nil and Pjoin2.meetingAt < Pjoin2.joinAt and has(jm.detail, "Mia and Leo join ") and not has(jm.detail, "with Mia"), jm and jm.detail)

	------------------------------------------------------------------ places
	for _, c in Ops.CLIENTS do
		if c.trip == "city" then continue end
		local id = IM.officeId(c.name)
		local spot = id and IM.meetingSpot(id)
		check("meeting room of " .. c.name, spot ~= nil, id)
		if spot then
			local tablePos = spot.table.Position
			local ok = #spot.clients == 2 and #spot.near == 3
			for _, cf in spot.clients do
				-- seated on the far side, facing the table
				local toTable = (tablePos - cf.Position) * Vector3.new(1, 0, 1)
				if toTable.Magnitude < 3 or toTable.Magnitude > 8 or cf.LookVector:Dot(toTable.Unit) < 0.6 then ok = false end
			end
			check("client chairs face the table: " .. c.name, ok)
			check("stand point 7.5 studs in front: " .. c.name, math.abs(CityPlan.flat(spot.stand.Position, tablePos) - 7.5) < 0.6)
			check("office area test: " .. c.name, IM.atOffice(spot.door.Position, id) and not IM.atOffice(spot.door.Position + Vector3.new(400, 0, 0), id))
		end
	end
	check("meetingSpot of an unknown key", IM.meetingSpot("nope") == nil and IM.officeId("Nope Corp") == nil)
	-- two founders at the same client: their client teams take different chairs
	local hs = IM.meetingSpot(IM.officeId("Helix Research"))
	if hs then
		local s1, s2, s3 = IM.seatsFor(hs, 1), IM.seatsFor(hs, 2), IM.seatsFor(hs, 3)
		local apart = #s1 == 2 and #s2 == 2
		for _, a in s1 do for _, b in s2 do if (a.Position - b.Position).Magnitude < 2 then apart = false end end end
		check("seat sets 1 and 2: two chairs each, never the same chair", apart)
		check("seat set 2 = the outer near chairs facing the table", s2[1] == hs.near[1] and s2[2] == hs.near[3])
		check("seat set 3+: the room is full (not drawn)", #s3 == 0 and #IM.seatsFor(hs, nil) == 2)
	end
	check("gate A1 area", IM.atGate(FP.HOME_GATES[1], "out") and not IM.atGate(FP.HOME_GATES[1] + Vector3.new(80, 0, 0), "out"))
	check("PM gate area", IM.atGate(FP.PM_GATES[1], "back") and IM.gatePoint("back") == FP.PM_GATES[1])
	local T = CityPlan.AIRPORT.terminal
	local tc = Vector3.new((T.x0 or T.minX or 0) + ((T.x1 or T.maxX or 0) - (T.x0 or T.minX or 0)) / 2, 3, (T.z0 or T.minZ or 0) + ((T.z1 or T.maxZ or 0) - (T.z0 or T.minZ or 0)) / 2)
	check("in City Airport (gate point)", IM.inAirport(FP.HOME_GATES[1]))
	check("not in City Airport (Port Meridian gate)", not IM.inAirport(FP.PM_GATES[1]))
	check("Port Meridian area", IM.abroad(FP.PM_GATES[1]) and not IM.abroad(FP.HOME_GATES[1]))
	local rcpt = IM.reception("abroad")
	check("Meridian Grand reception + area test", rcpt ~= nil and IM.atHotel(rcpt.Position, "abroad") and not IM.atHotel(rcpt.Position, "region"))
	check("City Hotel reception", IM.reception("region") ~= nil and IM.atHotel(IM.reception("region").Position, "region"))
	local team1, team2 = IM.clientTeam("helix:8500", 4242, "Helix Research"), IM.clientTeam("helix:8500", 4242, "Helix Research")
	check("client team: two people, deterministic, badges", #team1 == 2 and team1[1].name == team2[1].name and team1[1].name ~= team1[2].name and has(team1[1].badge, "Helix Research"))
	check("driver stage name", typeof(IM.driverStage()) == "string" and #IM.driverStage() > 0)

	------------------------------------------------------------------ the source: pure, no money
	local src
	for path, s in sources do if string.find(path, "ItineraryMath", 1, true) then src = s end end
	check("source found", src ~= nil)
	if src then
		check("creates no instances", not has(src, "Instance.new"))
		check("never touches the economy", not has(src, "EconomyService") and not has(src, "Economy.") and not has(src, ".cash"))
		check("strict mode", string.sub(src, 1, 8) == "--!stric")
	end
	local _ = tc
	local __ = CFrame
	local ___ = cyc2
end
setfenv(body, M.envFor(nil))
local ok, err = M.runMain(body, { timeout = 600 })
if not ok then failc += 1; print("CRASH " .. tostring(err)) end
print(string.format("itinerary_math: %d passed, %d failed", pass, failc))
