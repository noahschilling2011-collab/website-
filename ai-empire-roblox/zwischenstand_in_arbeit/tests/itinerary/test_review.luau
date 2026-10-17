--!nocheck
-- itinerary package: the independent reviewer's adversarial scenarios (agents/review_itinerary/test_adv.luau), adopted
-- as regression tests of the review round - every reported failure is a check here (race, offerwait, cabin, paidticket,
-- garage, stalecall, abroadstart, two, perf, midnight) next to the scenarios that already passed (leave, respawn, spam,
-- endflight, stage5, cabinctl, rigcost), plus the spec gaps (together, jettogether: strict when the drivers / jet
-- patches of design/requests/itinerary.md #1 / #2 are in the tree - agents/itinerary/sandboxes.sh), the timed pick-up
-- (timed) and the back-direction hold (overhold). One scenario per run, on the REAL server modules (common.luau).
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_itinerary && cd tests/itinerary &&
--      ../../tools/luau test_review.luau -a .gen_itinerary <scenario>
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_itinerary")
local SCENARIO = args[2] or "leave"
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
for path, src in require("../../tests/world/stubs") do sources[path] = src end
M.loadTree(manifest, sources)
M.quiet = true
local G = M.G
local pass, failc = 0, 0
local VERBOSE = os.getenv and os.getenv("REVIEW_VERBOSE") == "1"
local function check(name, ok, detail)
	if ok then pass += 1; if VERBOSE then print("ok    [" .. SCENARIO .. "] " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
	else failc += 1; print("FAIL  [" .. SCENARIO .. "] " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end
local function info(name, detail) if VERBOSE then print("info  [" .. SCENARIO .. "] " .. name .. "  -- " .. tostring(detail)) end end
local function has(text, part) return typeof(text) == "string" and string.find(text, part, 1, true) ~= nil end
local Common = require("./common")

local function body()
	local Vector3, CFrame = G.Vector3, G.CFrame
	local opts = {}
	-- 23:50 company time: night 18:00-08:00 runs in 300 s -> 5h50 after 18:00 = 125 s after offset 900
	if SCENARIO == "midnight" then opts.start = 1416666 * 1200 + 1025 end
	local X = Common(M, G, opts)
	local IM, RS = X.IM, X.RS
	local function st(p) return X.state(p) or {} end
	local function waitState(p, state, max) return X.waitFor(function() return st(p).state == state end, max or 300) end
	local function itinCalls(s)
		local out = {}
		for _, c in X.Phone.calls(s) do if c.kind == "itinerary" then table.insert(out, c) end end
		return out
	end
	local function accept(s)
		local c = itinCalls(s)[1]
		if not c then return { ok = false, err = "no call" } end
		return X.Phone._act(s, { action = "call", id = c.id, answer = "accept" })
	end
	local function itinCal(s)
		local n, list = 0, {}
		for _, it in X.Phone._state(s).calendar do
			if string.sub(it.key, 1, 5) == "itin:" then n += 1; table.insert(list, it) end
		end
		return n, list
	end
	local function folderOf(p) return RS.CompanyItinerary:FindFirstChild("Itin_" .. p.UserId) end
	local function atHQ(p) X.standAt(p, X.hqPoint(p, Vector3.new(0, 3, -60))) end
	local function newFounder(id, name, stage)
		local p, s = X.newPlayer(id, name, stage or 4)
		X.advance(1.5)
		atHQ(p)
		X.advance(1.1)
		return p, s
	end
	local function newTrip(p, s, client, o)
		local trip = X.addTrip(s, client, o)
		X.advance(3.5)
		return trip, IM.tripKey(trip)
	end
	local function waitCar(p, max)
		return X.waitFor(function() local rf = X.rideFolder(p); return rf ~= nil and rf:GetAttribute("State") == "waiting" end, max or 240)
	end
	local function rideAndBoard(p, s, max)
		if not waitCar(p, max) then return false, "no waiting car" end
		return X.boardCar(p, s)
	end
	local function founderRides(p)
		local n = 0
		local root = RS:FindFirstChild("CompanyDrivers")
		if not root then return 0 end
		for _, f in root:GetChildren() do
			for _, r in f:GetChildren() do
				if r:GetAttribute("Rider") == p.UserId or (r:GetAttribute("Kind") == "founder" and f.Name == "Drivers_" .. p.UserId) then n += 1 end
			end
		end
		return n
	end
	-- to the City Airport gate on the company car, then the shuttle; returns once flying (with our jet - JetService
	-- holds the staff for him, design/requests/itinerary.md #2 - he goes from the kerb straight into the air)
	local function toFlight(p, s)
		local okB = rideAndBoard(p, s)
		if not okB then return false, "car" end
		if not X.waitFor(function() return st(p).state == "airport" or st(p).state == "flight" end, 260) then return false, "airport " .. tostring(st(p).state) end
		if st(p).state == "flight" then return true end
		X.standAt(p, X.FP.HOME_GATES[1] + Vector3.new(2, 0, 3))
		if not waitState(p, "flight", 500) then return false, "flight " .. tostring(st(p).state) end
		return true
	end
	local errors0 = M.stats.errors

	if SCENARIO == "leave" then
		-- (1) leave the game while riding in the company car to the airport
		local p, s = newFounder(8101, "Lea", 4)
		local trip, key = newTrip(p, s, "helix")
		check("offer", st(p).state == "offer")
		accept(s)
		check("riding after boarding", (rideAndBoard(p, s)))
		X.advance(3)
		local rf = X.rideFolder(p)
		check("car is riding with him", rf ~= nil and rf:GetAttribute("State") == "riding", rf and rf:GetAttribute("State"))
		X.close(p, s)
		X.advance(2)
		check("left mid-ride: itinerary record gone", X.Itin.state(p) == nil)
		check("left mid-ride: published folder gone", folderOf(p) == nil)
		check("left mid-ride: prompt folder clean", M.game.Workspace.ItineraryPrompts:FindFirstChild("ItinRoom_" .. p.UserId) == nil)
		check("left mid-ride: shuttle booking gone", X.Shuttle.booking(p) == nil)
		X.advance(200, 0.5)
		check("ticks after leaving mid-ride: no errors", M.stats.errors == errors0, M.stats.errors - errors0)
		-- (1b) the same founder joins again with the trip still running in his save: no offer (staff work), no stale attribute
		local p1, s1 = X.newPlayer(8101, "Lea", 4)
		table.insert(s1.data.empire.deals.tripList, { client = trip.client, kind = "sign", back = trip.back, founder = false, hosted = false, crew = 2, left = trip.left })
		X.advance(5)
		check("re-join: trip under way stays staff work (no new call)", #itinCalls(s1) == 0 and st(p1).state == "none")
		check("re-join: TripAction go for the running trip still possible", X.act(s1, { action = "go", key = key }).ok == true, st(p1).state)
		X.Itin.cancel(p1)
		X.advance(1)
		-- (2) leave the game during the shuttle flight
		local p2, s2 = newFounder(8102, "Max", 4)
		newTrip(p2, s2, "helix")
		accept(s2)
		local okF, why = toFlight(p2, s2)
		check("flying on the company booking", okF, why)
		local nCal = itinCal(s2)
		info("calendar items in the phone state while flying", nCal)
		X.close(p2, s2)
		X.advance(3)
		check("left mid-flight: record + folder gone", X.Itin.state(p2) == nil and folderOf(p2) == nil)
		check("left mid-flight: City trip gone", X.City.trips[p2.UserId] == nil)
		X.advance(400, 0.5)
		check("ticks after leaving mid-flight: no errors", M.stats.errors == errors0, M.stats.errors - errors0)
		check("no Economy call", #X.econCalls == 0, #X.econCalls)

	elseif SCENARIO == "respawn" then
		-- (1) respawn in the shuttle cabin: the shuttle leg is dropped, the itinerary must end cleanly
		local p, s = newFounder(8201, "Ria", 4)
		newTrip(p, s, "helix")
		accept(s)
		local okF, why = toFlight(p, s)
		check("flying", okF, why)
		X.F.respawn(p, CFrame.new(X.hqPoint(p, Vector3.new(0, 3, -60))))
		X.advance(1.5)
		check("respawn mid-flight: City state home", X.City.state(p) == "home", X.City.state(p))
		check("respawn mid-flight: itinerary ended", st(p).state == "none", st(p).state .. "/" .. tostring(st(p).sub))
		check("respawn mid-flight: calendar cleared", (itinCal(s)) == 0, (itinCal(s)))
		check("respawn mid-flight: attribute cleared", p:GetAttribute("Itinerary") == nil, p:GetAttribute("Itinerary"))
		-- (2) respawn while riding in the car to the airport: exactly one car again (no leaked second ride)
		local p2, s2 = newFounder(8202, "Sol", 4)
		newTrip(p2, s2, "helix")
		accept(s2)
		check("car riding (2)", (rideAndBoard(p2, s2)))
		X.advance(2)
		X.F.respawn(p2, CFrame.new(X.hqPoint(p2, Vector3.new(0, 3, -60))))
		X.advance(4)
		check("respawn mid-ride: trip still on (pickup)", st(p2).state == "pickup", st(p2).state)
		X.advance(5)
		-- (the car he rode in may drive on with the colleagues - DriverService ends that leg - his new car is for him)
		local mine, withThem = 0, 0
		local names2 = {}
		for _, person in st(p2).companions or {} do names2[person.name] = true end
		for _, f in RS.CompanyDrivers:GetChildren() do
			for _, r in f:GetChildren() do
				if r:GetAttribute("Rider") == p2.UserId or (r:GetAttribute("Kind") == "founder" and f.Name == "Drivers_" .. p2.UserId and r:GetAttribute("State") ~= "riding" and r:GetAttribute("State") ~= "returning") then mine += 1 end
				for _, m in r:GetChildren() do if names2[m:GetAttribute("CompanionName") or ""] then withThem += 1; break end end
			end
		end
		check("respawn mid-ride: at most one car for the founder", mine <= 1, mine)
		check("respawn mid-ride: the colleagues sit in at most one car", withThem <= 1, withThem)
		info("respawn mid-ride: sub", tostring(st(p2).sub) .. " rideId=" .. tostring(st(p2).rideId))
		X.Itin.cancel(p2)
		X.advance(2)
		check("no Economy call", #X.econCalls == 0, #X.econCalls)
		check("no background errors", M.stats.errors == errors0, M.stats.errors - errors0)

	elseif SCENARIO == "spam" then
		local p, s = newFounder(8301, "Sam", 4)
		local _, key = newTrip(p, s, "helix")
		local limited, oks = 0, 0
		for i = 1, 60 do
			local r = X.act(s, { action = if i % 2 == 1 then "go" else "cancel", key = if i % 2 == 1 then key else nil })
			if r.err == "RATE_LIMIT" then limited += 1 elseif r.ok then oks += 1 end
			X.advance(0.05, 0.05)
		end
		info("go/cancel x60 (test limits = 1e6): ok answers", oks)
		X.advance(6)
		local rides = founderRides(p)
		check("after go/cancel spam: at most one ride folder of his", rides <= 1, rides)
		local n = itinCal(s)
		check("after go/cancel spam: <= 5 itinerary calendar items", n <= 5, n)
		check("after go/cancel spam: <= 1 published folder", (function()
			local c = 0
			for _, f in RS.CompanyItinerary:GetChildren() do if f:GetAttribute("Owner") == p.UserId then c += 1 end end
			return c <= 1
		end)())
		-- with the real per-action limits
		X.Driver.LIMITS.other = { 8, 3 }
		local p2, s2 = newFounder(8302, "Tom", 4)
		local _, k2 = newTrip(p2, s2, "helix")
		local lim2 = 0
		for i = 1, 40 do
			local r = X.act(s2, { action = "go", key = k2 })
			if r.err == "RATE_LIMIT" then lim2 += 1 end
		end
		info("go spam RATE_LIMIT answers (limiter created earlier with test limits)", lim2)
		-- junk payloads
		local junk = { { action = "go", key = "helix:1.5" }, { action = "go", key = "../x:1" }, { action = 5 }, { action = "go", key = { 1 } },
			{ action = "status", key = string.rep("a", 47) .. ":" }, { action = "retry", key = "x:1" } }
		local crashed = false
		for _, pl in junk do
			local ok, r = pcall(X.act, s2, pl)
			if not ok or typeof(r) ~= "table" then crashed = true end
		end
		check("junk payloads answered without errors", not crashed)
		-- the same phone call accepted twice
		local p3, s3 = newFounder(8303, "Uli", 4)
		newTrip(p3, s3, "helix")
		local c = itinCalls(s3)[1]
		local r1 = X.Phone._act(s3, { action = "call", id = c.id, answer = "accept" })
		local r2 = X.Phone._act(s3, { action = "call", id = c.id, answer = "accept" })
		check("call accepted twice: second refused", r1.ok == true and r2.ok == false, tostring(r2.err))
		check("no Economy call", #X.econCalls == 0, #X.econCalls)
		check("no background errors", M.stats.errors == errors0, M.stats.errors - errors0)

	elseif SCENARIO == "two" then
		-- two founders, same client tower, same time
		local pa, sa = newFounder(8401, "Ann", 4)
		local pb, sb = newFounder(8402, "Ben", 4)
		X.addTrip(sa, "helix"); X.addTrip(sb, "helix")
		X.advance(3.5)
		check("two offers", st(pa).state == "offer" and st(pb).state == "offer")
		accept(sa); accept(sb)
		check("both pickups", st(pa).state == "pickup" and st(pb).state == "pickup")
		local fa, fb = folderOf(pa), folderOf(pb)
		check("separate folders", fa ~= nil and fb ~= nil and fa ~= fb)
		-- interleaved: both board their own car, both walk to gate A1
		check("both cars waiting", waitCar(pa) and waitCar(pb))
		local ba = X.boardCar(pa, sa)
		local bb = X.boardCar(pb, sb)
		check("both boarded", ba and bb)
		check("both at the airport", X.waitFor(function() return st(pa).state == "airport" and st(pb).state == "airport" end, 300), st(pa).state .. " " .. st(pb).state)
		X.standAt(pa, X.FP.HOME_GATES[1] + Vector3.new(2, 0, 3))
		X.standAt(pb, X.FP.HOME_GATES[1] + Vector3.new(-2, 0, 3))
		check("both flying", X.waitFor(function() return st(pa).state == "flight" and st(pb).state == "flight" end, 500), st(pa).state .. " " .. st(pb).state)
		check("both landed -> limo", waitState(pa, "limo", 700) and waitState(pb, "limo", 60))
		X.standAt(pa, X.Drive.clientPlace("Helix Research").door.Position)
		X.standAt(pb, X.Drive.clientPlace("Helix Research").door.Position + Vector3.new(4, 0, 0))
		X.advance(1)
		check("both at the meeting", st(pa).state == "meeting" and st(pb).state == "meeting", st(pa).state .. " " .. st(pb).state)
		local ka, kb = folderOf(pa):GetAttribute("ClientKey"), folderOf(pb):GetAttribute("ClientKey")
		local sa, sb = folderOf(pa):GetAttribute("SeatSet"), folderOf(pb):GetAttribute("SeatSet")
		local spotA = IM.meetingSpot(ka)
		local seatsA, seatsB = IM.seatsFor(spotA, sa), IM.seatsFor(IM.meetingSpot(kb), sb)
		local clash = false
		for _, x in seatsA do for _, y in seatsB do if (x.Position - y.Position).Magnitude < 1 then clash = true end end end
		check("same client, same room: different seat sets", ka == kb and sa ~= sb and (sa == 1 or sb == 1), tostring(sa) .. "/" .. tostring(sb))
		check("two client teams in one meeting room get distinct chairs", #seatsA == 2 and #seatsB == 2 and not clash)
		-- the Start meeting prompt: one press per founder, each his own trip
		local q = X.meetingPrompt(IM.officeId("Helix Research"))
		X.standAt(pa, q.Parent.Position + Vector3.new(0, 0, -4)); X.firePrompt(q, pa)
		check("A joined, B not yet", st(pa).joined == true and st(pb).joined == false)
		X.standAt(pb, q.Parent.Position + Vector3.new(1, 0, -4)); X.firePrompt(q, pb)
		check("B joined", st(pb).joined == true)
		check("check-in prompts are per owner", (function()
			X.waitFor(function() return st(pa).state == "hotel" and st(pb).state == "hotel" end, 40)
			local a = M.game.Workspace.ItineraryPrompts:FindFirstChild("ItinRoom_" .. pa.UserId)
			local b = M.game.Workspace.ItineraryPrompts:FindFirstChild("ItinRoom_" .. pb.UserId)
			return a ~= nil and b ~= nil and a.RoomPrompt:GetAttribute("OwnerUserId") == pa.UserId and b.RoomPrompt:GetAttribute("OwnerUserId") == pb.UserId
		end)())
		-- B presses A's prompt: refused
		local a = M.game.Workspace.ItineraryPrompts:FindFirstChild("ItinRoom_" .. pa.UserId)
		if a then
			X.standAt(pb, a.Position + Vector3.new(0, 0, -3))
			X.firePrompt(a.RoomPrompt, pb)
			check("B cannot check A in", st(pa).checkedIn == false)
		end
		check("no Economy call", #X.econCalls == 0, #X.econCalls)
		check("no background errors", M.stats.errors == errors0, M.stats.errors - errors0)

	elseif SCENARIO == "garage" then
		-- stage 1 (garage, no driver): abroad trip on foot (the honest texts), cancel at the airport
		local p, s = newFounder(8501, "Gus", 1)
		check("garage: no driver", X.Drive.drivers(s.data.empire) == 0)
		newTrip(p, s, "helix")
		local c = itinCalls(s)[1] or {}
		check("garage: call says no driver", has(c.text, "We don't have a company driver yet"), c.text)
		-- stage 3 (ONE driver): the region trip's field car takes the only driver before the call
		local p3, s3 = newFounder(8503, "Ida", 3)
		check("stage 3: one driver", X.Drive.drivers(s3.data.empire) == 1, X.Drive.drivers(s3.data.empire))
		newTrip(p3, s3, "creative")
		local c3 = itinCalls(s3)[1] or {}
		info("stage 3 region call text", c3.text)
		check("queued car: the call names a real ETA (not 'about 0:00')", not has(c3.text, "about 0:00"), c3.text)
		local plan3 = st(p3).plan or {}
		local d3 = plan3.driver or {}
		if d3.queued then
			-- (today: DriverService's field car took the only driver before the call - drivers request #1)
			check("queued car: an honest estimate or none (never a made-up 0:00)", has(c3.text, "in about ") or has(c3.text, "picks you up at the HQ entrance."), c3.text)
			check("queued: the estimate comes from the published ride plans (first car back + the way to him)", typeof(d3.eta) == "number" and d3.eta > 30, tostring(d3.eta))
			check("queued: no driver named in the call (he is out)", d3.name == nil and not has(c3.text, "Your driver"), c3.text)
		else
			-- (with drivers request #1 the field car waits for his answer: the only driver is free for him and them)
			check("free driver: named, the colleagues come along in his car", d3.name ~= nil and has(c3.text, "Your driver") and (has(c3.text, "come along") or has(c3.text, "comes along")), c3.text)
		end
		local okGo = accept(s3)
		info("stage 3 go result", okGo.text)
		check("go text for a queued car: the next free car, no driver who is out", st(p3).sub ~= "queued" or (has(okGo.text, "the next free one picks you up") and not has(okGo.text, "brings the car round")), okGo.text)
		local v = X.lastView(p3) or {}
		info("stage 3 banner after go", tostring(v.title) .. " | " .. tostring(v.line) .. " | " .. tostring(v.timerLabel) .. " " .. tostring(v.timerAt and math.floor(v.timerAt - X.T)))
		local n3, list3 = itinCal(s3)
		local okOrder = true
		table.sort(list3, function(a, b) return (a.at or 0) < (b.at or 0) end)
		info("stage 3 calendar", n3)
		for _, it in list3 do info("  cal", it.key .. " at+" .. math.floor((it.at or 0) - X.T) .. " " .. it.title .. " | " .. tostring(it.detail)) end
		local pickupAt, meetingAt
		for _, it in list3 do
			if has(it.key, ":pickup") then pickupAt = it.at end
			if has(it.key, ":meeting") then meetingAt = it.at end
		end
		check("queued: calendar meeting time after the queued car's ETA", pickupAt and meetingAt and meetingAt - X.T >= ((v.timerAt or X.T) - X.T), tostring(meetingAt and meetingAt - X.T) .. " vs car " .. tostring(v.timerAt and v.timerAt - X.T))
		X.Itin.cancel(p3)
		X.advance(1)
		-- stage 3, the only driver already out with another trip's field rep (a city visit - nothing for the founder):
		-- the region call must queue honestly (verify2b: with drivers request #1 in the tree the case above gets the free
		-- driver, so the queued ETA is exercised here)
		local p4, s4 = newFounder(8504, "Jo", 3)
		X.addTrip(s4, "pixel")
		X.advance(2)
		check("stage 3: the city visit's field car took the only driver", (X.Driver.free(p4)) == 0, (X.Driver.free(p4)))
		newTrip(p4, s4, "creative")
		local c4 = itinCalls(s4)[1] or {}
		local d4 = (st(p4).plan or {}).driver or {}
		check("busy driver: the call queues the car", d4.queued == true, c4.text)
		check("busy driver: an honest estimate (never a made-up 0:00)", has(c4.text, "in about ") and not has(c4.text, "about 0:00"), c4.text)
		check("busy driver: the estimate comes from the published ride plans", typeof(d4.eta) == "number" and d4.eta > 30, tostring(d4.eta))
		check("busy driver: no driver named in the call (he is out)", d4.name == nil and not has(c4.text, "Your driver"), c4.text)
		X.Itin.cancel(p4)
		X.advance(1)
		check("no Economy call", #X.econCalls == 0, #X.econCalls)
		check("no background errors", M.stats.errors == errors0, M.stats.errors - errors0)

	elseif SCENARIO == "stage5" then
		-- stage 5 with the jet (STAFF_FRESH default): the shuttle when the staff jet already left, our jet when JetService
		-- holds the staff for him (itinerary.md #2); the ride home
		local p, s = newFounder(8601, "Vea", 5)
		s.data.empire.jet = true
		X.advance(2)
		local cash0 = s.data.money
		newTrip(p, s, "science")
		local c = itinCalls(s)[1] or {}
		info("stage5 call", c.text)
		local plan = st(p).plan or {}
		check("stage5: plan is shuttle or jet", plan.how == "shuttle" or plan.how == "jet", plan.how)
		accept(s)
		local okF, why = toFlight(p, s)
		check("stage5: in the air", okF, why)
		check("stage5: landed", waitState(p, "limo", 700))
		check("stage5: no money moved", #X.econCalls == 0 and s.data.money == cash0, #X.econCalls)
		-- leave abroad straight away: the return
		local r = X.act(s, { action = "leave" })
		check("stage5: Fly home now from the limo step", r.ok == true and st(p).state == "return")
		X.standAt(p, X.FP.PM_GATES[1] + Vector3.new(0, 0, -30))
		local okG = X.waitFor(function() return st(p).sub == "gate" or st(p).sub == "flight" end, 200)
		check("stage5: at the PM gate / jet", okG, tostring(st(p).sub))
		info("stage5 return flight", tostring(st(p).flight))
		X.standAt(p, X.FP.PM_GATES[1] + Vector3.new(2, 0, 2))
		local okH = X.waitFor(function() return st(p).state == "home" or st(p).state == "none" end, 900)
		check("stage5: back home", okH, st(p).state .. "/" .. tostring(st(p).sub))
		local v = X.lastView(p) or {}
		info("stage5 home banner", tostring(v.title) .. " | " .. tostring(v.line))
		info("stage5 home position", tostring(p.root.Position))
		X.Itin.cancel(p)
		X.advance(1)
		check("no Economy call", #X.econCalls == 0, #X.econCalls)
		check("no background errors", M.stats.errors == errors0, M.stats.errors - errors0)

	elseif SCENARIO == "midnight" then
		local p, s = newFounder(8701, "Nia", 4)
		local e = s.data.empire
		local d0, h0 = X.PhoneMath.now(e, X.T)
		info("company day/hour at start", tostring(d0) .. " / " .. tostring(h0))
		newTrip(p, s, "helix")
		local c = itinCalls(s)[1] or {}
		info("midnight call", c.text)
		check("night: the driver is on call - or (better) picks him up at a time for the morning shuttle", has(c.text, "on call tonight") or has(c.text, "picks you up at the HQ entrance "), c.text)
		local pl = st(p).plan or {}
		check("night: no idling at the gate for hours (timed pick-up for the first morning shuttle)", pl.requestAt ~= nil and pl.departs - pl.pickupAt < 300,
			pl.departs and pl.pickupAt and (pl.departs - pl.pickupAt))
		check("call leaves the return to the calendar", not has(c.text, "Return"))
		accept(s)
		local n, list = itinCal(s)
		table.sort(list, function(a, b) return (a.at or 0) < (b.at or 0) end)
		local order = {}
		for _, it in list do table.insert(order, (string.match(it.key, ":(%a+)$"))) end
		info("calendar order by time", table.concat(order, ","))
		check("calendar order pickup<flight<meeting<hotel<return", table.concat(order, ",") == "pickup,flight,meeting,hotel,return", table.concat(order, ","))
		for _, it in list do info("  cal", it.key .. " " .. it.title .. " | " .. tostring(it.detail) .. " | " .. IM.clockText(e, X.T, it.at)) end
		-- the phone shows each item at its company day + hour: they must not go backwards
		local prev = nil
		local mono = true
		for _, it in list do
			local d, h = X.PhoneMath.atClock(e, X.T, it.at)
			local v = d * 100 + ((h - 8) % 24)
			if prev and v < prev then mono = false end
			prev = v
		end
		check("phone day/hour of the items never go backwards across midnight", mono)
		-- night times read forward: "night of Day 11 · 05:10", never "Day 11 · 05:10" next to "Day 11 · 23:58"
		local badNight = false
		for _, it in list do
			local d, h = X.PhoneMath.atClock(e, X.T, it.at)
			local text = IM.clockText(e, X.T, it.at)
			if h % 24 < 8 and not (has(text, "night of Day") or has(text, "tonight") or not has(text, "Day")) then badNight = true end
			if h % 24 < 8 and has(text, "Day " .. d .. " ·") and not has(text, "night of") then badNight = true end
			for _, part in { it.title or "", it.detail or "" } do
				if string.match(part, "Day %d+ · 0[0-7]:") and not has(part, "night of Day") then badNight = true end
			end
		end
		check("calendar: hours after midnight never read as the morning of that day", not badNight)
		X.Itin.cancel(p)
		X.advance(1)
		check("no background errors", M.stats.errors == errors0, M.stats.errors - errors0)

	elseif SCENARIO == "endflight" then
		-- the economic trip ends while the founder is in the air
		local p, s = newFounder(8801, "Ola", 4)
		local trip = newTrip(p, s, "helix")
		accept(s)
		local companions0 = st(p).companions or {}
		local okF, why = toFlight(p, s)
		check("flying", okF, why)
		local list = s.data.empire.deals.tripList
		table.remove(list, table.find(list, trip))
		X.advance(1)
		check("still in the flight after the trip ended", st(p).state == "flight", st(p).state)
		check("landed -> return (visit over)", X.waitFor(function() return st(p).state == "return" end, 700), st(p).state)
		check("over flag + companions fly home with him", st(p).over == true and st(p).stay == false)
		local v = X.lastView(p) or {}
		info("endflight banner", tostring(v.title) .. " | " .. tostring(v.line))
		X.standAt(p, X.FP.PM_GATES[1] + Vector3.new(0, 0, -30))
		check("to the PM gate", X.waitFor(function() return st(p).sub == "gate" end, 200), tostring(st(p).sub))
		local bkh = X.Shuttle.booking(p)
		check("the colleagues fly home with him (company booking home)", bkh ~= nil and bkh.to == "home" and bkh.companions ~= nil and #bkh.companions == 2)
		X.standAt(p, X.FP.PM_GATES[1] + Vector3.new(2, 0, 2))
		check("flight home", X.waitFor(function() return st(p).sub == "flight" end, 500), tostring(st(p).sub))
		check("landed at City Airport: the colleagues walk off first (deboard), then the car", X.waitFor(function() return st(p).state == "home" end, 600)
			and st(p).sub == "deboard" and X.rideFolder(p) == nil)
		check("then the driver is called", X.waitFor(function() return X.rideFolder(p) ~= nil end, IM.DEBOARD_WAIT + 5))
		local names = {}
		for _, person in companions0 do names[person.name] = true end
		check("fixture: two colleagues watched", #companions0 == 2)
		local again = false
		X.onTick = function()
			local pax = RS.Shuttle:FindFirstChild("Passengers")
			if pax then for _, m in pax:GetChildren() do if names[m:GetAttribute("PassengerName")] and m:GetAttribute("CompanionOf") == nil then again = true end end end
		end
		X.advance(2 * X.FP.interval() + 30, 1)
		X.onTick = nil
		check("the shuttle does not fly them home a second time (two more cycles watched)", not again)
		check("no Economy call", #X.econCalls == 0, #X.econCalls)
		check("no background errors", M.stats.errors == errors0, M.stats.errors - errors0)

	elseif SCENARIO == "overhold" then
		-- the visit ends while he is in Port Meridian but away from the airport (no booking home yet): the next return
		-- leg must not fly his colleagues home without him (ItineraryService.holds, back direction of the field-staff rule)
		local p, s = newFounder(8811, "Oda", 4)
		local trip = newTrip(p, s, "helix")
		accept(s)
		local companions0 = st(p).companions or {}
		local okF, why = toFlight(p, s)
		check("flying", okF, why)
		check("landed -> limo step", waitState(p, "limo", 700), st(p).state)
		local rc = IM.reception("abroad")
		check("fixture: hotel reception", rc ~= nil)
		if rc then X.standAt(p, rc.Position + Vector3.new(0, 0, 4)) end
		X.advance(1)
		local list = s.data.empire.deals.tripList
		table.remove(list, table.find(list, trip))
		X.advance(1.5)
		check("visit over -> return, the colleagues go home with him", st(p).state == "return" and st(p).over == true and st(p).stay == false, st(p).state)
		local names0 = {}
		for _, person in companions0 do names0[person.name] = true end
		local sawBack, flewBack, bookedMeanwhile = false, false, false
		local legAtStart = (RS.Shuttle:FindFirstChild("Passengers") and RS.Shuttle.Passengers:GetAttribute("Leg")) or ""
		X.onTick = function()
			if X.Shuttle.booking(p) ~= nil then bookedMeanwhile = true end
			local pax = RS.Shuttle:FindFirstChild("Passengers")
			local leg = if pax then pax:GetAttribute("Leg") else nil
			if typeof(leg) == "string" and leg ~= legAtStart and string.sub(leg, 1, 5) == "back:" then
				sawBack = true
				for _, m in pax:GetChildren() do if names0[m:GetAttribute("PassengerName")] and m:GetAttribute("CompanionOf") == nil then flewBack = true end end
			end
		end
		X.waitFor(function() return sawBack end, 2 * X.FP.interval() + 60)
		X.onTick = nil
		check("fixture: two colleagues, a return leg boarded while he was in town without a booking", #companions0 == 2 and sawBack and not bookedMeanwhile,
			tostring(sawBack) .. "/" .. tostring(bookedMeanwhile))
		check("that return leg did not fly them home without him", not flewBack)
		check("... they still fly home with him (company booking home at the PM gate)", (function()
			X.standAt(p, X.FP.PM_GATES[1] + Vector3.new(0, 0, -30))
			if not X.waitFor(function() return st(p).sub == "gate" end, 200) then return false end
			local bk = X.Shuttle.booking(p)
			return bk ~= nil and bk.to == "home" and bk.companions ~= nil and #bk.companions == 2
		end)())
		check("no Economy call", #X.econCalls == 0, #X.econCalls)
		check("no background errors", M.stats.errors == errors0, M.stats.errors - errors0)

	elseif SCENARIO == "paidticket" then
		-- he bought a ticket at the counter before the call; then cancels the itinerary at the airport
		local p, s = newFounder(8901, "Pia", 4)
		local cash0 = s.data.money
		X.standAt(p, X.CityPlan.AIRPORT.checkin[1])
		local tk = X.Shuttle.ticket(s, "abroad")
		check("paid ticket", tk.ok == true and (tk.price or 0) > 0, tk.err)
		local _, key = newTrip(p, s, "helix")
		accept(s)
		X.advance(1)
		check("at the airport -> airport step", st(p).state == "airport", st(p).state)
		local bk = X.Shuttle.booking(p)
		local paid = tk.price or 0
		check("the counter ticket becomes the company booking (prepaid, the trip, the colleagues)", bk and bk.prepaid == true and bk.price == 0 and bk.trip == key)
		check("... and its price is refunded (he never pays for a seat the company books)", s.data.money == cash0, tostring(cash0 - s.data.money))
		local refundMsg = false
		for _, m in X.Phone._state(s).messages do if m.title == "Ticket refunded" then refundMsg = true end end
		check("message: ticket refunded", refundMsg)
		local spends, grants, other = 0, 0, 0
		for _, ec in X.econCalls do
			if ec.fn == "spend" and ec.args[1] == paid then spends += 1 elseif ec.fn == "grant" and ec.args[1] == paid then grants += 1 else other += 1 end
		end
		check("money: exactly the ticket and its refund (the existing refund path), nothing else", spends == 1 and grants == 1 and other == 0, spends .. "/" .. grants .. "/" .. other)
		X.Itin.cancel(p)
		X.advance(1)
		local bk2 = X.Shuttle.booking(p)
		check("after cancel: the (now free) company booking is gone, nothing held", bk2 == nil and not X.Itin.holds(p.UserId, key))
		check("after cancel: no money moved in either direction", s.data.money == cash0)
		-- a paid ticket the itinerary never booked over (cancel before the airport): it stays his, untouched
		local p2, s2 = newFounder(8902, "Quin", 4)
		X.standAt(p2, X.CityPlan.AIRPORT.checkin[1])
		local tk2 = X.Shuttle.ticket(s2, "abroad")
		atHQ(p2)
		local _, key2 = newTrip(p2, s2, "helix")
		accept(s2)
		X.Itin.cancel(p2)
		X.advance(1)
		local bk3 = X.Shuttle.booking(p2)
		check("a paid ticket the trip never used: still his, price kept, no trip / colleagues on it", tk2.ok and bk3 ~= nil and bk3.price == tk2.price and bk3.prepaid == false
			and bk3.trip == nil and (bk3.companions == nil or #bk3.companions == 0), bk3 and bk3.trip)
		local _ = key2

	elseif SCENARIO == "cabin" then
		-- are the companions visible in the shuttle cabin (ShuttleService Passengers) on the founder's company booking?
		local p, s = newFounder(9001, "Rae", 4)
		local trip, key = newTrip(p, s, "helix")
		local people = IM.travellers(s.data.empire, trip)
		accept(s)
		local seen = {}
		X.onTick = function()
			local sf = RS:FindFirstChild("Shuttle") or RS:FindFirstChild("CompanyShuttle")
			if not sf then
				for _, c in RS:GetChildren() do if c:FindFirstChild("Passengers") then sf = c end end
			end
			local pax = sf and sf:FindFirstChild("Passengers")
			if pax then for _, m in pax:GetChildren() do seen[m:GetAttribute("PassengerName") or ""] = true end end
		end
		local okF, why = toFlight(p, s)
		check("flying", okF, why)
		X.advance(30, 0.5)
		X.onTick = nil
		for _, person in people do
			check("companion " .. person.name .. " visible as a shuttle passenger", seen[person.name] == true)
		end
		local _ = key

	elseif SCENARIO == "cabinctl" then
		-- control: the founder declines; the field staff fly the public shuttle as passengers (ShuttleService rule)
		local p, s = newFounder(9002, "Sky", 4)
		local trip = newTrip(p, s, "helix")
		local people = IM.travellers(s.data.empire, trip)
		local c = itinCalls(s)[1]
		X.Phone._act(s, { action = "call", id = c.id, answer = "decline" })
		local seen = {}
		X.onTick = function()
			local pax = RS.Shuttle:FindFirstChild("Passengers")
			if pax then for _, m in pax:GetChildren() do seen[m:GetAttribute("PassengerName") or ""] = true end end
		end
		X.advance(900, 0.5)
		X.onTick = nil
		for _, person in people do check("control: " .. person.name .. " is a shuttle passenger without the founder", seen[person.name] == true) end

	elseif SCENARIO == "race" then
		-- the founder says Go at once but a shuttle boarding starts before he reaches City Airport (car wait + ride):
		-- does the field-staff rule fly his companions ahead although the plan says they travel with him?
		local p, s = newFounder(9201, "Ray", 4)
		-- start the trip just before an out-leg boarding begins
		local wait = X.FP.boardingIn("out", X.T)
		if wait > 20 then X.advance(wait - 15, 0.5) end
		local trip, key = newTrip(p, s, "helix")
		local c = itinCalls(s)[1] or {}
		info("race call", c.text)
		accept(s)
		local stA = st(p)
		info("race after go: carry/together", tostring(stA.carry) .. " sub=" .. tostring(stA.sub))
		X.advance(30, 0.5) -- boarding of the next out leg has started meanwhile
		local ahead = X.Shuttle.flownAhead(p, key)
		info("flownAhead right after the next boarding started", ahead)
		-- now he gets to the airport (car or on foot)
		local okB = rideAndBoard(p, s, 200)
		info("rode the car", okB)
		local okA = waitState(p, "airport", 300)
		if not okA then X.standAt(p, X.CityPlan.AIRPORT.checkin[1]); X.advance(2) end
		local bk = X.Shuttle.booking(p)
		info("booking companions", bk and bk.companions and #bk.companions)
		check("the companions the call promised still fly with him (not flown ahead on an earlier leg)", not X.Shuttle.flownAhead(p, key) and bk ~= nil and bk.companions ~= nil and #bk.companions == 2,
			"flownAhead=" .. tostring(X.Shuttle.flownAhead(p, key)) .. " bookingCompanions=" .. tostring(bk and bk.companions and #bk.companions))
		local v = X.lastView(p) or {}
		check("race banner at the airport: they wait at the gate (true now)", has(v.line, "wait at the gate"), v.line)
		local seen = {}
		X.onTick = function()
			local pax = RS.Shuttle:FindFirstChild("Passengers")
			if pax then for _, m in pax:GetChildren() do if m:GetAttribute("CompanionOf") == p.UserId then seen[m:GetAttribute("PassengerName")] = true end end end
		end
		X.standAt(p, X.FP.HOME_GATES[1] + Vector3.new(2, 0, 3))
		check("boards", waitState(p, "flight", 500))
		X.advance(1)
		X.onTick = nil
		local n = 0
		for _ in seen do n += 1 end
		check("both colleagues on his leg (Passengers, CompanionOf)", n == 2, n)
		local msgs = {}
		for _, m in X.Phone._state(s).messages or {} do table.insert(msgs, tostring(m.title) .. ": " .. tostring(m.text)) end
		info("race last phone message", msgs[#msgs])
		check("no Economy call", #X.econCalls == 0, #X.econCalls)
		check("no background errors", M.stats.errors == errors0, M.stats.errors - errors0)

	elseif SCENARIO == "offerwait" then
		-- the founder answers the call 3 minutes late: what does the plan / banner say, who travels with him?
		local p, s = newFounder(9301, "Oda", 4)
		local trip, key = newTrip(p, s, "helix")
		local c = itinCalls(s)[1] or {}
		info("offerwait call", c.text)
		X.advance(180, 0.5)
		local ahead = X.Shuttle.flownAhead(p, key)
		info("flownAhead after 3 min of an open offer", ahead)
		local r = accept(s)
		info("offerwait go", r.text or r.err)
		local stA = st(p)
		info("offerwait plan.ahead/aheadBy/carry", tostring(stA.plan and stA.plan.ahead) .. "/" .. tostring(stA.plan and stA.plan.aheadBy) .. "/" .. tostring(stA.carry))
		check("open offer holds the companions (they do not fly ahead while the founder is still deciding)", not ahead, "flownAhead=" .. tostring(ahead))
		check("Go after 3 min: they travel with him (together, not 'already flying')", stA.together == true and (stA.plan and stA.plan.aheadBy) ~= "air")
		local v = X.lastView(p) or {}
		info("offerwait banner", tostring(v.title) .. " | " .. tostring(v.line))
		X.Itin.cancel(p)
		X.advance(1)
		check("no background errors", M.stats.errors == errors0, M.stats.errors - errors0)

	elseif SCENARIO == "rigcost" then
		-- go/cancel spam with the REAL per-action limits: how many replicated rig instances does one player churn per second?
		X.Driver.LIMITS.other = { 8, 3 }
		X.Driver.LIMITS.write = { 6, 2 }
		X.Driver.LIMITS.read = { 12, 4 }
		local p, s = newFounder(9401, "Rik", 4)
		local _, key = newTrip(p, s, "helix")
		local goes, limited, created = 0, 0, 0
		local T0 = X.T
		while X.T - T0 < 20 do
			local r = X.act(s, { action = "go", key = key })
			if r.ok and st(p).state ~= "none" and st(p).state ~= "offer" then
				goes += 1
				local f = folderOf(p)
				if f then created += #f:GetDescendants() + 1 end
			elseif r.err == "RATE_LIMIT" then limited += 1 end
			local c = X.act(s, { action = "cancel" })
			if c.err == "RATE_LIMIT" then limited += 1 end
			X.advance(0.1, 0.1)
		end
		info("go accepted in 20 s (real limits)", goes)
		info("RATE_LIMIT answers", limited)
		info("replicated instances created in 20 s by one player (rig folders)", created)
		info("instances per folder", goes > 0 and math.floor(created / goes) or 0)
		check("go/cancel spam is throttled to <= 1 new folder per 2 s", goes <= 10, goes)
		check("a Go replicates only the companions (the client team from the meeting on): <= 110 instances", goes == 0 or created / goes <= 110, goes > 0 and math.floor(created / goes) or 0)
		check("no background errors", M.stats.errors == errors0, M.stats.errors - errors0)

	elseif SCENARIO == "abroadstart" then
		-- the founder is already in Port Meridian when the trip starts: the companions still have to fly out from home.
		local p, s = newFounder(9501, "Abe", 4)
		local bk = X.Shuttle.book(s, { to = "abroad" })
		X.standAt(p, X.FP.HOME_GATES[1] + Vector3.new(2, 0, 3))
		check("flown to Port Meridian", X.waitFor(function() return X.City.state(p) == "abroad" end, 900))
		X.advance(3)
		local trip, key = newTrip(p, s, "helix")
		local c = itinCalls(s)[1] or {}
		info("abroadstart call", c.text)
		accept(s)
		X.standAt(p, X.Drive.clientPlace("Helix Research").door.Position)
		X.advance(1)
		check("meeting", st(p).state == "meeting", st(p).state)
		local f = folderOf(p)
		local function shown() return f:GetAttribute("With") == true and X.T >= (f:GetAttribute("ShowAt") or 0) end
		local joinAt = st(p).joinAt
		check("the call says when they land and join him", has(c.text, "fly out on PM 101 and join you at the tower"), c.text)
		check("a join time from the shuttle timetable", typeof(joinAt) == "number" and joinAt > X.T, joinAt and joinAt - X.T)
		check("companions are not shown at the meeting before they could have arrived (no double presence)", not shown() and st(p).together == false,
			"With=" .. tostring(f:GetAttribute("With")) .. " ShowAt-T=" .. tostring((f:GetAttribute("ShowAt") or 0) - X.T))
		local v = X.lastView(p) or {}
		check("banner: when they arrive, not 'with you'", has(v.line, "arrive") and not has(v.line, "with you"), v.line)
		check("they are not held for his flight (they fly out on their own)", X.Itin.holds(p.UserId, key) == false)
		local flewAt = nil
		X.onTick = function() if not flewAt and X.Shuttle.flownAhead(p, key) then flewAt = X.T end end
		X.waitFor(function() return shown() end, (joinAt or X.T) - X.T + 5, 0.5)
		X.onTick = nil
		check("they flew out on the field-staff shuttle leg before they were shown", flewAt ~= nil and flewAt < X.T, flewAt)
		check("shown with him once landed + at the tower (joinAt)", shown() and st(p).together == true and X.T >= (joinAt or 0) - 0.5)
		local v2 = X.lastView(p) or {}
		check("banner: now with you", has(v2.line, "with you"), v2.line)
		check("no background errors", M.stats.errors == errors0, M.stats.errors - errors0)

	elseif SCENARIO == "stalecall" then
		-- Go on the banner while the assistant's call still rings; then the founder answers the stale call "Not this time"
		local p, s = newFounder(9601, "Sia", 4)
		local _, key = newTrip(p, s, "helix")
		local c = itinCalls(s)[1]
		local r = X.act(s, { action = "go", key = key })
		check("banner go ok", r.ok == true, r.err)
		local stillRinging = false
		for _, cc in X.Phone.calls(s) do if cc.id == c.id and (cc.state == "ringing" or cc.status == "ringing" or cc.answered == nil) then stillRinging = true end end
		info("call entry after banner go", (function() for _, cc in X.Phone.calls(s) do if cc.id == c.id then local t = {} for k, v in cc do if typeof(v) ~= "table" then table.insert(t, k .. "=" .. tostring(v)) end end return table.concat(t, " ") end end return "gone" end)())
		local d = X.Phone._act(s, { action = "call", id = c.id, answer = "decline" })
		info("stale call declined -> answer", tostring(d.ok) .. " " .. tostring(d.text or d.err))
		X.advance(1)
		local stt = st(p).state
		info("itinerary state after the stale decline", stt)
		check("a stale 'Not this time' does not claim the team travels alone while the trip runs", not (d.ok and typeof(d.text) == "string" and string.find(d.text, "without you", 1, true) and stt ~= "none"),
			tostring(d.text) .. " / state " .. tostring(stt))
		check("... it says he is on his way and the trip keeps running", has(d.text, "already on your way") and stt == "pickup", d.text)
		-- when the phone package adds Phone.endCall (design/requests/phone.md), Go ends the ringing call
		local p2, s2 = newFounder(9602, "Tim", 4)
		local _, key2 = newTrip(p2, s2, "helix")
		local c2 = itinCalls(s2)[1]
		local ended = nil
		X.Phone.endCall = function(ss, id) if ss == s2 then ended = id end end
		X.act(s2, { action = "go", key = key2 })
		X.Phone.endCall = nil
		check("Go on the banner ends the assistant's call (Phone.endCall when present)", c2 ~= nil and ended == c2.id, tostring(ended))
		check("no background errors", M.stats.errors == errors0, M.stats.errors - errors0)

	elseif SCENARIO == "together" then
		-- brief 24 headline: "the driver comes and brings you there - with an employee". It needs DriverService to hold
		-- the trip's field car while the founder is asked / takes them (design/requests/itinerary.md #1, a patch in
		-- agents/itinerary/sb_drivers). With that patch in the tree this scenario is strict; without it, it checks the
		-- honest fallback (the call says they went ahead; they still fly with him).
		local drvSrc = sources["ServerScriptService/Server/Services/DriverService.module.luau"] or ""
		local patched = string.find(drvSrc, 'itinAsk("carries"', 1, true) ~= nil
		info("DriverService honours ItineraryService.pending / carries", patched)
		local function fieldCarriesThem(p0, names)
			local df = RS.CompanyDrivers:FindFirstChild("Drivers_" .. p0.UserId)
			if not df then return false end
			for _, r in df:GetChildren() do
				if r:GetAttribute("Kind") == "field" then
					for _, m in r:GetChildren() do if names[m:GetAttribute("CompanionName") or ""] then return true end end
				end
			end
			return false
		end
		for _, case in { { id = 9801, stage = 4, client = "helix" }, { id = 9802, stage = 3, client = "creative" } } do
			local p, s = newFounder(case.id, "Tog" .. case.stage, case.stage)
			local trip, key = newTrip(p, s, case.client)
			local people = IM.travellers(s.data.empire, trip)
			local names = {}
			for _, person in people do names[person.name] = true end
			local c = itinCalls(s)[1] or {}
			check("stage " .. case.stage .. ": fixture has colleagues", #people >= 1, #people)
			if patched then
				check("stage " .. case.stage .. ": no field car left before the call", not fieldCarriesThem(p, names))
				check("stage " .. case.stage .. ": the call says they travel with him", has(c.text, "travel with you") or has(c.text, "travels with you") or has(c.text, "come along") or has(c.text, "comes along"), c.text)
			else
				check("stage " .. case.stage .. ": without the drivers patch the call is honest about the field car", fieldCarriesThem(p, names) == has(c.text, "went ahead"), c.text)
			end
			accept(s)
			if st(p).sub == "scheduled" then X.act(s, { action = "retry" }) end
			X.advance(2)
			local rf = X.rideFolder(p)
			local inCar = rf ~= nil and rf:FindFirstChild("C1") ~= nil
			if patched then
				check("stage " .. case.stage .. ": the driver comes with the colleague(s) in the founder's car", st(p).carry == true and inCar, tostring(st(p).carry) .. " / C1 " .. tostring(inCar))
				X.advance(5)
				check("stage " .. case.stage .. ": and no field car takes them meanwhile", not fieldCarriesThem(p, names))
			else
				check("stage " .. case.stage .. ": carry follows the field car", st(p).carry == not fieldCarriesThem(p, names) or st(p).carry == inCar)
			end
			check("stage " .. case.stage .. ": they travel with him (together)", st(p).together == true)
			X.Itin.cancel(p)
			X.advance(X.Itin.GO_GAP + 1)
		end
		check("no Economy call", #X.econCalls == 0, #X.econCalls)
		check("no background errors", M.stats.errors == errors0, M.stats.errors - errors0)

	elseif SCENARIO == "jettogether" then
		-- "they board ... the company jet together": needs JetService to keep a fresh staff trip waiting while the founder
		-- is asked / takes them (design/requests/itinerary.md #2, a patch in agents/itinerary/sb_jet). Strict with the
		-- patch in the tree, else the honest fallback (the call says they already fly out; he takes the shuttle).
		local jetSrc = sources["ServerScriptService/Server/Services/JetService.module.luau"] or ""
		local patched = string.find(jetSrc, "itinHolds", 1, true) ~= nil
		local p, s = newFounder(9851, "Jen", 5)
		s.data.empire.jet = true
		X.advance(2)
		local trip, key = newTrip(p, s, "helix")
		local c = itinCalls(s)[1] or {}
		local plan = st(p).plan or {}
		local okA, why, infoA = X.Jet.available(p)
		-- (without the drivers patch, #1, the field car has taken them to the airport: they wait at our jet)
		local drvPatched = string.find(sources["ServerScriptService/Server/Services/DriverService.module.luau"] or "", 'itinAsk("carries"', 1, true) ~= nil
		if patched then
			check("the staff jet waits while he is asked", okA == true, tostring(why))
			check("the call books our jet and says they travel with him", plan.how == "jet" and has(c.text, "our jet") and not has(c.text, "already fly out")
				and (has(c.text, "travel with you") or has(c.text, "travels with you") or (not drvPatched and has(c.text, "wait at our jet"))), c.text)
			accept(s)
			if st(p).sub == "scheduled" then X.act(s, { action = "retry" }) end
			local okB = rideAndBoard(p, s, 240)
			check("rode to the airport", okB)
			check("jet flight with him", X.waitFor(function() return st(p).state == "flight" and st(p).sub == "jet" end, 300), tostring(st(p).state) .. "/" .. tostring(st(p).sub))
			local staff = X.Jet.staffOf(p)
			local entry = staff and staff[key]
			check("the trip's staff flew with him (JetService marks them out with his flight)", entry ~= nil and entry.state ~= "wait_out", entry and entry.state)
			local _, why2, info2 = X.Jet.available(p)
			check("no second staff flight", not (why2 == "JET_BUSY" and typeof(info2) == "table" and info2.purpose == "staff"))
		else
			check("without the jet patch: the staff jet already flies them, the call is honest", (okA == false and why == "JET_BUSY" and typeof(infoA) == "table" and infoA.purpose == "staff") == (has(c.text, "already fly out")), c.text)
			check("... and he gets the shuttle", plan.how == "shuttle" or plan.how == "jet")
		end
		local _ = trip
		check("no Economy call", #X.econCalls == 0, #X.econCalls)
		check("no background errors", M.stats.errors == errors0, M.stats.errors - errors0)

	elseif SCENARIO == "timed" then
		-- UX (review): a timed pick-up instead of idling at gate A1 - the trip starts right after a boarding closed
		local function afterBoarding(p0)
			local _, ls, _, be = X.FP.nextLeg("out", X.T)
			if ls > X.T then X.advance(math.max(0, be - X.T) + 6, 0.5) else X.advance(be - X.T + 6, 0.5) end
		end
		local p, s = newFounder(9701, "Tia", 4)
		afterBoarding(p)
		local _, key = newTrip(p, s, "helix")
		local c = itinCalls(s)[1] or {}
		local plan = st(p).plan or {}
		check("plan: a timed pick-up", plan.requestAt ~= nil and plan.requestAt > X.T + 30, plan.requestAt and plan.requestAt - X.T)
		check("call names the pick-up time", has(c.text, "picks you up at the HQ entrance " .. IM.atText(s.data.empire, X.T, plan.pickupAt)), c.text)
		local r = accept(s)
		check("Go: scheduled, no car yet, the colleagues held", st(p).sub == "scheduled" and X.rideFolder(p) == nil and X.Itin.holds(p.UserId, key) == true)
		check("Go text names the pick-up", has(r.text, "picks you up"), r.text)
		local cal = X.calendarKeys(s)
		local pick = cal["itin:" .. st(p).seq .. ":pickup"]
		check("calendar pick-up at the timed pick-up", pick ~= nil and math.abs(pick.at - st(p).pickupAt) < 1)
		local dep0 = st(p).departs
		X.waitFor(function() return X.rideFolder(p) ~= nil end, st(p).requestAt - X.T + 3)
		check("the car is called at requestAt by itself", X.rideFolder(p) ~= nil and st(p).sub ~= "scheduled")
		check("... for the same flight", st(p).departs == dep0, tostring(st(p).departs) .. " vs " .. tostring(dep0))
		check("he reaches the gate shortly after the boarding opened (no long wait)", (st(p).boardEnd or 0) - ((st(p).plan.airportAt or 0) + IM.WALK_GATE) >= 30)
		X.Itin.cancel(p)
		X.advance(X.Itin.GO_GAP + 1)
		-- Call car now
		local p2, s2 = newFounder(9702, "Udo", 4)
		afterBoarding(p2)
		local _, key2 = newTrip(p2, s2, "helix")
		X.act(s2, { action = "go", key = key2 })
		check("scheduled (2)", st(p2).sub == "scheduled")
		local v = X.lastView(p2) or {}
		check("banner: Call car now + timer to the pick-up", v.buttons and v.buttons[1] and v.buttons[1].text == "Call car now" and v.timerLabel == "Pick-up in")
		local rr = X.act(s2, { action = "retry" })
		check("Call car now books the car at once", rr.ok == true and X.rideFolder(p2) ~= nil and st(p2).sub ~= "scheduled", tostring(rr.err))
		-- respawn while scheduled: still scheduled (no car at once)
		local p3, s3 = newFounder(9703, "Vic", 4)
		afterBoarding(p3)
		local _, key3 = newTrip(p3, s3, "helix")
		X.act(s3, { action = "go", key = key3 })
		X.F.respawn(p3, CFrame.new(X.hqPoint(p3, Vector3.new(0, 3, -60))))
		X.advance(1)
		check("respawn while waiting for the timed pick-up: still scheduled", st(p3).state == "pickup" and st(p3).sub == "scheduled" and X.rideFolder(p3) == nil)
		check("no Economy call", #X.econCalls == 0, #X.econCalls)
		check("no background errors", M.stats.errors == errors0, M.stats.errors - errors0)

	elseif SCENARIO == "perf" then
		-- 12 founders on itineraries; server cost of ItineraryService.tick vs DriverService.tick in the mock + Notify volume
		local ps = {}
		for i = 1, 12 do
			local p, s = X.newPlayer(9100 + i, "P" .. i, 4)
			table.insert(ps, { p, s })
		end
		X.advance(1.5)
		for _, ps1 in ps do atHQ(ps1[1]) end
		X.advance(1.1)
		for i, ps1 in ps do X.addTrip(ps1[2], if i % 2 == 0 then "helix" else "creative") end
		X.advance(3.5)
		for _, ps1 in ps do accept(ps1[2]) end
		X.advance(2)
		-- the booked car is looked at once per second per founder (DriverService.status), not on every step
		local statusCalls = 0
		local realStatus = X.Driver.status
		X.Driver.status = function(...) statusCalls += 1; return realStatus(...) end
		-- three rounds of 60 server seconds; the cheapest round of each service counts (other processes share the CPU)
		local msI, msD, itinNotify = math.huge, math.huge, 0
		for round = 1, 3 do
			local fired0 = #X.Remote.fired
			local tI, tD = 0, 0
			for i = 1, 240 do
				X.T += 0.25
				local a = os.clock(); X.Itin.tick(0.25); tI += os.clock() - a
				local b = os.clock(); X.Driver.tick(0.25); tD += os.clock() - b
				X.City.tick(0.25); X.Jet.tick(0.25)
				for _, ps1 in ps do ps1[2].data.empire.seconds += 0.25 end
			end
			local n = 0
			for i = fired0 + 1, #X.Remote.fired do
				local f = X.Remote.fired[i]
				if f.name == "Notify" and f.args[1] == "ITINERARY" then n += 1 end
			end
			if round == 1 then itinNotify = n end
			msI, msD = math.min(msI, tI * 1000 / 60), math.min(msD, tD * 1000 / 60)
		end
		X.Driver.status = realStatus
		print(string.format("perf  ItineraryService.tick %.2f ms / server s (12 founders), DriverService.tick %.2f ms / server s, ITINERARY notifies %d / min", msI, msD, itinNotify))
		check("ITINERARY notify rate <= 1/s per founder", itinNotify <= 12 * 60, itinNotify)
		check("DriverService.status at most once per second per founder", statusCalls <= 12 * 180 * 1.1, statusCalls)
		check("ItineraryService.tick no more than 4x DriverService (the pre-fix code: 7-10x) or under 1 ms per server second", msI <= math.max(1.0, 4 * msD), string.format("%.2f vs %.2f", msI, msD))
	end
end

local ok, err = M.runMain(body, { timeout = 6000, maxSteps = 80000000 })
if not ok then failc += 1; print("CRASH " .. tostring(err)) end

if M.stats.errors > 0 then failc += 1; print("FAIL  background thread errors: " .. M.stats.errors) end
print(string.format("itinerary_review_%s: %d passed, %d failed", SCENARIO, pass, failc))
