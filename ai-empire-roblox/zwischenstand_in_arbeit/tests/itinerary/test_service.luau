--!nocheck
-- itinerary package: ItineraryService on the REAL server modules (DriverService, ShuttleService, CityService + the
-- built world, JetService, PhoneService, EmpireService, PlotService, CompanyOps) with a controlled server clock
-- (tests/itinerary/common.luau). One scenario per run:
--   abroad  the whole abroad trip by shuttle: the assistant's call (real colleagues, flight, hotel, driver), Go, the
--           car with the companions, company booking (prepaid, no money), gate -> flight -> Port Meridian arrival
--           message -> VIP limousine -> meeting room -> the REAL "Start meeting" prompt -> EmpireService.joinMeeting ->
--           trip.joined -> +0.15 trust in CompanyOps.step -> hotel (car from the tower, check-in prompt) -> Fly home
--           now (the colleagues stay) -> limousine -> gate -> flight home -> driver -> HQ; calendar items added and
--           removed, published folder / attribute / banner per step, no Notify spam, no money moved, economy untouched
--   jet     the same with the company jet (JetService.fly without pay), jet busy -> shuttle fallback message,
--           runway busy -> wait, jet owned but away -> the call books the shuttle
--   region  pilot in Business City: car to the client office, meeting, City Hotel, Go home now, car home
--   offer   decline by phone / by banner, autoTrips countdown -> Cancel, countdown -> starts by itself, Go by
--           TripAction, offer expires, offer of a trip that ends, built-in phone trip call suppressed
--   edge    two trips (queue + offered later), founder already abroad (limousine only, region trip queued), trip
--           ends during the pick-up / abroad, no driver yet (honest text, GPS, positional airport check), the
--           company booking never runs out of seats, respawn during pick-up / abroad, hotel provider ok / failing
--   remote  TripAction validation + per-action rate limit, leave the game mid-trip, assistant briefing row
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_itinerary && cd tests/itinerary && ../../tools/luau test_service.luau -a .gen_itinerary abroad
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_itinerary")
local SCENARIO = args[2] or "abroad"
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
for path, src in require("../world/stubs") do sources[path] = src end
M.loadTree(manifest, sources)
M.quiet = true
local G = M.G
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  [" .. SCENARIO .. "] " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end
local function has(text, part) return typeof(text) == "string" and string.find(text, part, 1, true) ~= nil end
local Common = require("./common")

local function body()
	local Vector3, CFrame, Instance = G.Vector3, G.CFrame, G.Instance
	local X = Common(M, G)
	local IM, Ops, FP = X.IM, X.Ops, X.FP
	local RS = X.RS

	------------------------------------------------------------------ helpers
	local function deep(t)
		if typeof(t) ~= "table" then return t end
		local o = {}
		for k, v in t do o[k] = deep(v) end
		return o
	end
	local function itinCalls(s)
		local out = {}
		for _, c in X.Phone.calls(s) do if c.kind == "itinerary" then table.insert(out, c) end end
		return out
	end
	local function messages(s)
		local out = {}
		for _, m in X.Phone._state(s).messages do table.insert(out, m) end
		return out
	end
	local function findMsg(s, part)
		for _, m in X.Phone._state(s).messages do
			if has(m.title, part) or has(m.body, part) then return m end
		end
		return nil
	end
	local function noticeHas(p, part)
		for _, n in X.notices(p) do if has(n, part) then return true end end
		return false
	end
	local function itinCal(s)
		local n, list = 0, {}
		for _, it in X.Phone._state(s).calendar do
			if string.sub(it.key, 1, 5) == "itin:" then n += 1; list[it.key] = it end
		end
		return n, list
	end
	local function folderOf(p) return RS.CompanyItinerary:FindFirstChild("Itin_" .. p.UserId) end
	local function st(p) return X.state(p) or {} end
	local function waitState(p, state, max) return X.waitFor(function() return st(p).state == state end, max or 300) end
	local function waitCar(p, max)
		return X.waitFor(function() local rf = X.rideFolder(p); return rf ~= nil and rf:GetAttribute("State") == "waiting" end, max or 240)
	end
	local function rideAndBoard(p, s, max)
		local okW = waitCar(p, max)
		if not okW then return false, "no waiting car" end
		return X.boardCar(p, s)
	end
	local function atHQ(p) X.standAt(p, X.hqPoint(p, Vector3.new(0, 3, -60))) end
	local function newFounder(id, name, stage)
		local p, s = X.newPlayer(id, name, stage or 4)
		X.advance(1.5)
		atHQ(p)
		X.advance(1.1) -- the itinerary's first look (baseline) is taken
		return p, s
	end
	-- a new pilot trip + the assistant's call (OFFER_DELAY after the scan saw it)
	local function newTrip(p, s, client, opts)
		local trip = X.addTrip(s, client, opts)
		X.advance(3.5)
		return trip, IM.tripKey(trip)
	end
	local function accept(s)
		local calls = itinCalls(s)
		local c = calls[1]
		if not c then return { ok = false, err = "no call" } end
		return X.Phone._act(s, { action = "call", id = c.id, answer = "accept" })
	end
	local function decline(s)
		local c = itinCalls(s)[1]
		if not c then return { ok = false, err = "no call" } end
		return X.Phone._act(s, { action = "call", id = c.id, answer = "decline" })
	end
	-- money of the company (cash + every ledger entry)
	local function money(s) return s.data.money, X.ledgerSum(s) end
	-- CompanyOps.step on copies of the save at the end of `trip`: trust with / without the founder's meeting
	local function trustAtEnd(s, trip, joined)
		local data = deep(s.data)
		local e = data.empire
		local d = Ops.ensure(e)
		d.trust[trip.client] = 0
		for _, t in d.tripList do if t.client == trip.client and t.left == trip.left then t.joined = joined or nil end end
		e.seconds = trip.back + 1
		local session = { userId = s.userId, player = s.player, data = data, live = deep(s.live), closed = false }
		local fake = setmetatable({}, { __index = function() return function() return true end end })
		local ok, err = pcall(Ops.step, session, 1, fake, X.T)
		if not ok then return nil, err end
		return d.trust[trip.client], d.accounts[trip.client]
	end
	local function sameList(a, b)
		if #a ~= #b then return false end
		for i, v in a do if v ~= b[i] then return false end end
		return true
	end

	------------------------------------------------------------------ wiring (every scenario)
	check("phone built-in trip calls off", X.Phone.BUILTIN_TRIP_CALLS == false)
	check("phone hook 'itinerary' registered", X.Phone.hasAction("itinerary"))
	check("TripAction bound (DriverService) and routes itinerary actions", X.act ~= nil)
	check("published root + prompt folder", RS:FindFirstChild("CompanyItinerary") ~= nil and M.game.Workspace:FindFirstChild("ItineraryPrompts") ~= nil)

	if SCENARIO == "abroad" then
		local p, s = newFounder(7101, "Ava", 4)
		-- a live model good enough for Helix Research (CompanyOps.eligible: the visit then gains trust)
		s.data.models = s.data.models or {}
		s.data.modelOrder = s.data.modelOrder or {}
		s.data.models.itin_test = { id = "itin_test", status = "live", stats = { math = 72, reasoning = 72, coding = 72, creativity = 72, knowledge = 72, reliability = 72 } }
		table.insert(s.data.modelOrder, "itin_test")
		local cash0, led0 = money(s)
		X.Phone.scan(s) -- the phone's own baseline (its built-in trip call would ring on the next scan)
		local e = s.data.empire
		local trip = X.addTrip(s, "helix")
		local key = IM.tripKey(trip)
		local back0 = trip.back
		local people = IM.travellers(e, trip)
		check("fixture: rep + engineer travel", #people == 2, #people)
		X.advance(1.05)
		check("no call before the field car left (OFFER_DELAY)", #itinCalls(s) == 0)
		check("pending() while the offer is being prepared (DriverService may hold the field car)", X.Itin.pending(p.UserId, key) == true)
		X.advance(2.5)
		X.Phone.scan(s)
		local calls = itinCalls(s)
		check("exactly one assistant call (built-in trip call suppressed)", #calls == 1, #calls)
		local call = calls[1] or {}
		local o = st(p)
		check("state offer with the plan", o.state == "offer" and o.key == key and o.plan ~= nil)
		local plan = o.plan or {}
		check("call from the assistant, kind itinerary, Go / Not this time", call.from == "Assistant" and call.accept == "Go" and call.decline == "Not this time")
		check("call data carries the trip key", typeof(call.data) == "table" and call.data.key == key)
		check("call title", call.title == "Helix Research wants to meet")
		for _, person in people do check("call names " .. IM.firstName(person.name), has(call.text, IM.firstName(person.name)), call.text) end
		check("call: booked shuttle + departure time from the plan", plan.flight ~= nil and has(call.text, plan.flight .. " " .. IM.atText(e, X.T, plan.departs)) or has(call.text, plan.flight .. " " .. IM.atText(e, X.T - 0.25, plan.departs)), call.text)
		check("call: Meridian Grand Hotel (the return is in the calendar, short call)", has(call.text, "Meridian Grand Hotel") and not has(call.text, "Return") and #call.text <= 230, call.text)
		local drv = plan.driver or {}
		check("call: the driver who is really free", drv.name ~= nil and has(call.text, "Your driver " .. IM.firstName(drv.name)) or drv.self == true, call.text)
		local v = X.lastView(p) or {}
		check("banner offer: Go / Not this time (the call's labels)", v.state == "offer" and #v.buttons == 2 and v.buttons[1].id == "go" and v.buttons[2].id == "decline"
			and v.buttons[2].text == "Not this time" and v.buttons[1].text == "Go")
		check("player attribute Itinerary = offer", p:GetAttribute("Itinerary") == "offer")
		check("no ride, no calendar before Go", X.rideFolder(p) == nil and (itinCal(s)) == 0)
		-- Go
		local res = accept(s)
		check("accept -> ok", res.ok == true, res.err)
		local a = st(p)
		check("state pickup", a.state == "pickup", a.state)
		-- the timed pick-up (no idling at gate A1): the car is called at requestAt; the plan / calendar show it
		local timed = a.sub == "scheduled"
		check("plan with a timed pick-up -> scheduled, no car yet", (plan.requestAt ~= nil) == timed and (not timed or (X.rideFolder(p) == nil and a.requestAt > X.T)), tostring(a.sub))
		if timed then
			local vs = X.lastView(p) or {}
			check("scheduled banner: Pick-up in, Call car now + Cancel trip", vs.timerLabel == "Pick-up in" and math.abs((vs.timerAt or 0) - a.pickupAt) < 1
				and #vs.buttons == 2 and vs.buttons[1].text == "Call car now" and vs.buttons[2].id == "cancel", vs.line)
			check("companions held while the car is not called yet (holds)", X.Itin.holds(p.UserId, key) == true)
			X.waitFor(function() return X.rideFolder(p) ~= nil end, a.requestAt - X.T + 3)
			a = st(p)
		end
		check("car booked for the founder", X.rideFolder(p) ~= nil and a.rideId ~= nil)
		local nCal, cal = itinCal(s)
		local seq = a.seq
		check("calendar: pickup, flight, meeting, hotel, return", nCal == 5 and cal["itin:" .. seq .. ":pickup"] and cal["itin:" .. seq .. ":flight"] and cal["itin:" .. seq .. ":meeting"]
			and cal["itin:" .. seq .. ":hotel"] and cal["itin:" .. seq .. ":return"], nCal)
		local f = folderOf(p)
		check("published folder with the companions (the client team only from the meeting on)", f ~= nil and f:FindFirstChild("Companion1") ~= nil and f:FindFirstChild("Companion2") ~= nil
			and f:FindFirstChild("Client1") == nil)
		check("folder attributes", f and f:GetAttribute("Owner") == p.UserId and f:GetAttribute("State") == "pickup" and f:GetAttribute("Tier") == "abroad"
			and f:GetAttribute("ClientKey") == IM.officeId("Helix Research"))
		check("companions: no Humanoid in the published templates", f and f.Companion1:FindFirstChildOfClass("Humanoid") == nil)
		-- the companions ride with him unless DriverService's field car already took them (then the call said so)
		check("carry xor 'went ahead' (DriverService field car, drivers.md #1)", (a.carry == true) ~= (has(call.text, "went ahead") == true), call.text)
		check("they fly with him either way (the shuttle hold)", a.together == true and X.Itin.holds(p.UserId, key) == true)
		local okB = rideAndBoard(p, s)
		check("boarded the company car", okB)
		check("state airport after the drop-off", waitState(p, "airport", 240))
		local bk = X.Shuttle.booking(p)
		check("company booking: prepaid, price 0", bk ~= nil and bk.prepaid == true and bk.price == 0 and bk.to == "abroad")
		check("company booking carries both colleagues + the trip", bk ~= nil and bk.trip == key and bk.companions ~= nil and #bk.companions == 2)
		check("airport banner: gate + flight", has((X.lastView(p) or {}).title, "Gate") and has((X.lastView(p) or {}).title, tostring(st(p).flight)))
		check("airport banner: they wait at the gate", has((X.lastView(p) or {}).line, "wait at the gate"), (X.lastView(p) or {}).line)
		local paxSeen = {}
		X.onTick = function()
			local pax = RS.Shuttle:FindFirstChild("Passengers")
			if pax then for _, m in pax:GetChildren() do paxSeen[m:GetAttribute("PassengerName") or ""] = m:GetAttribute("CompanionOf") end end
		end
		X.standAt(p, X.FP.HOME_GATES[1] + Vector3.new(2, 0, 3))
		check("boarded the shuttle -> flight", waitState(p, "flight", 420))
		X.advance(1)
		X.onTick = nil
		for _, person in people do check("on board with him: " .. IM.firstName(person.name) .. " is a passenger of his leg", paxSeen[person.name] == p.UserId) end
		check("not flown ahead on an earlier leg", X.Shuttle.flownAhead(p, key) == true and (function()
			local dir = X.Shuttle.travellersLeg(p, key)
			return dir == "out"
		end)())
		check("the companions are not shown walking while flying", folderOf(p):GetAttribute("With") == false)
		local views0 = #X.views(p)
		local sets0 = p.attrWrites
		X.advance(60, 0.5)
		check("no Notify spam while flying (published on change only)", #X.views(p) - views0 <= 2, #X.views(p) - views0)
		check("no attribute spam while flying", p.attrWrites - sets0 <= 2, p.attrWrites - sets0)
		check("landed -> limousine", waitState(p, "limo", 600))
		check("City state abroad", X.City.state(p) == "abroad")
		local arrived = findMsg(s, "Arrived in Port Meridian")
		check("message: Arrived in Port Meridian - the limousine is waiting", arrived ~= nil and has(arrived.body, "limousine is waiting"), arrived and arrived.body)
		check("limo banner", (X.lastView(p) or {}).title == "Limo · Helix Research", (X.lastView(p) or {}).title)
		check("the colleagues walk off the plane first (deboard), then the limousine is called", st(p).sub == "deboard" and X.rideFolder(p) == nil and has((X.lastView(p) or {}).line, "getting off the plane"))
		check("boarded the limousine", (rideAndBoard(p, s, 200)))
		check("at the tower -> meeting", waitState(p, "meeting", 300))
		check("folder: MeetingOn + With", folderOf(p):GetAttribute("MeetingOn") == true and folderOf(p):GetAttribute("With") == true)
		check("meeting banner + action line", (X.lastView(p) or {}).title == "Meeting · Helix Research" and (X.lastView(p) or {}).action == "Press Start meeting at the table")
		check("the client team's templates exist from the meeting on", folderOf(p):FindFirstChild("Client1") ~= nil and folderOf(p):FindFirstChild("Client2") ~= nil)
		check("seat set 1 (alone at this client)", folderOf(p):GetAttribute("SeatSet") == 1)
		-- the REAL Start meeting prompt (CityBuilder) -> CityService handler -> EmpireService.joinMeeting
		local q = X.meetingPrompt(IM.officeId("Helix Research"))
		check("CityBuilder meeting prompt exists", q ~= nil)
		if q then
			X.standAt(p, q.Parent.Position + Vector3.new(0, 0, -4))
			X.firePrompt(q, p)
		end
		check("trip.joined set by the real joinMeeting", trip.joined == true)
		check("the itinerary follows the prompt at once (CityService.onMeeting)", st(p).joined == true)
		X.advance(0.5)
		check("banner: trust +15%", has((X.lastView(p) or {}).line, "trust +15%") and (X.lastView(p) or {}).action == "Joined · trust +15%")
		check("folder Joined", folderOf(p):GetAttribute("Joined") == true)
		local c = Ops.client("helix")
		local gJ = Ops.trustGain(e, s.data, c, false, false, true)
		local gN = Ops.trustGain(e, s.data, c, false, false, false)
		check("CompanyOps: meeting adds exactly 0.15 trust", math.abs(gJ - gN - 0.15) < 1e-9, gJ - gN)
		local tJ, accJ = trustAtEnd(s, trip, true)
		local tN, accN = trustAtEnd(s, trip, false)
		check("Ops.step at the trip end: joined visit +0.15 trust", tJ ~= nil and tN ~= nil and math.abs(tJ - tN - 0.15) < 1e-6 or (accJ ~= nil and accN == nil), tostring(tJ) .. " vs " .. tostring(tN))
		check("hotel step after the talk", waitState(p, "hotel", IM.MEETING_TALK + 10))
		check("the client team stays while he is still in the meeting room", folderOf(p):GetAttribute("MeetingOn") == true)
		local prompt = M.game.Workspace.ItineraryPrompts:FindFirstChild("ItinRoom_" .. p.UserId)
		check("own check-in prompt at the reception (owner only)", prompt ~= nil and prompt.RoomPrompt:GetAttribute("OwnerUserId") == p.UserId and prompt.RoomPrompt.ActionText == "Check in")
		X.standAt(p, X.Drive.clientPlace("Helix Research").door.Position)
		X.advance(0.5)
		check("... and goes once he left the room", folderOf(p):GetAttribute("MeetingOn") == false)
		check("car from the tower to the hotel", (rideAndBoard(p, s, 120)))
		check("dropped at the hotel", X.waitFor(function() return st(p).sub == "arrived" end, 200))
		if prompt then
			X.standAt(p, prompt.Position + Vector3.new(0, 0, -40))
			X.firePrompt(prompt.RoomPrompt, p)
			check("check-in from far away refused", st(p).checkedIn == false)
			X.advance(1.2)
			X.standAt(p, prompt.Position + Vector3.new(0, 0, -3))
			X.firePrompt(prompt.RoomPrompt, p)
		end
		check("checked in, prompt gone", st(p).checkedIn == true and M.game.Workspace.ItineraryPrompts:FindFirstChild("ItinRoom_" .. p.UserId) == nil)
		check("banner: checked in", has((X.lastView(p) or {}).line, "Checked in"))
		-- Fly home now: the colleagues stay until the visit ends
		local r = X.act(s, { action = "leave" })
		check("leave -> ok, return", r.ok == true and st(p).state == "return")
		check("colleagues stay (message)", st(p).stay == true and findMsg(s, "stay until the visit ends") ~= nil)
		X.standAt(p, X.Drive.place("pm_hotel").door.Position)
		check("limousine to Port Meridian Airport", (rideAndBoard(p, s, 120)))
		check("at the gate home", X.waitFor(function() return st(p).sub == "gate" end, 200))
		local bk2 = X.Shuttle.booking(p)
		check("company booking home: prepaid, no companions (they stay)", bk2 ~= nil and bk2.prepaid == true and bk2.to == "home" and (bk2.companions == nil or #bk2.companions == 0))
		X.standAt(p, X.FP.PM_GATES[1] + Vector3.new(2, 0, 2))
		check("flight home", X.waitFor(function() return st(p).sub == "flight" end, 420))
		check("landed -> home step", waitState(p, "home", 600))
		check("message: back at City Airport with the driver", findMsg(s, "Back at City Airport") ~= nil and has(findMsg(s, "Back at City Airport").body, "picks you up"))
		check("only one 'Back at City Airport' message", (function()
			local n = 0
			for _, m in X.Phone._state(s).messages do if m.title == "Back at City Airport" then n += 1 end end
			return n == 1
		end)())
		check("driver home", (rideAndBoard(p, s, 200)))
		check("dropped at the HQ -> trip finished", waitState(p, "none", 300))
		check("message: Trip finished", findMsg(s, "Trip finished") ~= nil)
		check("calendar items removed", (itinCal(s)) == 0)
		check("folder removed, attribute cleared", folderOf(p) == nil and p:GetAttribute("Itinerary") == nil)
		check("banner closed", (X.lastView(p) or {}).closed == true)
		check("no booking left", X.Shuttle.booking(p) == nil)
		-- money + economy untouched
		local cash1, led1 = money(s)
		check("no Economy call by the whole trip", #X.econCalls == 0, #X.econCalls)
		check("cash unchanged", cash1 == cash0, tostring(cash0) .. " -> " .. tostring(cash1))
		check("ledger unchanged", led1 == led0)
		check("the economic trip keeps its clock (back unchanged)", trip.back == back0)
		check("the trip is still the economy's (in tripList)", IM.findTrip(e, key) == trip)

	elseif SCENARIO == "jet" then
		-- the founder's own jet flight: no field-staff jet flight in the way (JetService treats the trip as under way)
		local staffFresh = X.Jet.STAFF_FRESH
		X.Jet.STAFF_FRESH = -1
		local p, s = newFounder(7201, "Jun", 5)
		local e = s.data.empire
		e.jet = true
		X.advance(2)
		local okA = X.Jet.available(p)
		check("jet available at home", okA == true)
		local cash0 = s.data.money
		local trip, key = newTrip(p, s, "helix")
		local o = st(p)
		check("offer plans the jet", o.state == "offer" and o.plan and o.plan.how == "jet" and o.plan.flight == "company jet")
		local call = itinCalls(s)[1] or {}
		check("call: our jet with the captain", has(call.text, "our jet (Captain ") and #call.text <= 230, call.text)
		check("accept", accept(s).ok == true)
		check("boarded", (rideAndBoard(p, s)))
		check("jet flight started at the airport", X.waitFor(function() return st(p).state == "flight" end, 300))
		check("flight sub jet + JetService flight", st(p).sub == "jet" and X.Jet.flightOf(p) ~= nil)
		check("no shuttle booking with the jet", X.Shuttle.booking(p) == nil)
		check("landed -> limousine", waitState(p, "limo", 600))
		check("abroad", X.City.state(p) == "abroad")
		check("no money moved by the jet legs (fly without pay)", #X.econCalls == 0 and s.data.money == cash0, #X.econCalls)
		-- fly home early with the jet
		check("leave from the limousine step", X.act(s, { action = "leave" }).ok == true and st(p).state == "return")
		X.standAt(p, X.FP.PM_GATES[1] + Vector3.new(0, 0, -30))
		X.waitFor(function() return st(p).sub == "gate" or st(p).sub == "flight" end, 200)
		local okHome = X.waitFor(function() return st(p).state == "home" or st(p).state == "none" end, 700)
		check("jet home", okHome, st(p).state .. "/" .. tostring(st(p).sub))
		X.Itin.cancel(p)
		X.advance(1)
		check("cancel at home ends it", st(p).state == "none")
		check("still no money", #X.econCalls == 0 and s.data.money == cash0)
		local _ = trip
		local __ = key

		-- jet busy -> the shuttle (message), runway busy -> wait
		local p2, s2 = newFounder(7202, "Kai", 5)
		s2.data.empire.jet = true
		X.advance(2)
		local realFly = X.Jet.fly
		local mode = "busy"
		X.Jet.fly = function(player, opts)
			if mode == "busy" then return { ok = false, err = "JET_BUSY" } end
			if mode == "runway" then mode = "real"; return { ok = false, err = "RUNWAY_BUSY", eta = 5 } end
			return realFly(player, opts)
		end
		newTrip(p2, s2, "helix")
		check("jet planned", st(p2).plan and st(p2).plan.how == "jet")
		accept(s2)
		check("boarded (2)", (rideAndBoard(p2, s2)))
		check("at the airport with the shuttle instead", X.waitFor(function() return st(p2).state == "airport" end, 240))
		local fm = findMsg(s2, "Flight changed")
		check("message: jet flying -> shuttle booked", fm ~= nil and has(fm.body, "our jet is flying right now") and has(fm.body, "shuttle"), fm and fm.body)
		check("prepaid shuttle booking", X.Shuttle.booking(p2) ~= nil and X.Shuttle.booking(p2).prepaid == true)
		X.Itin.cancel(p2)
		X.advance(1)
		check("cancel drops the unused booking", X.Shuttle.booking(p2) == nil)
		local p3, s3 = newFounder(7203, "Lia", 5)
		s3.data.empire.jet = true
		X.advance(2)
		mode = "runway"
		newTrip(p3, s3, "helix")
		accept(s3)
		check("boarded (3)", (rideAndBoard(p3, s3)))
		check("runway busy -> waits for the jet", X.waitFor(function() return st(p3).sub == "jetwait" end, 240))
		check("then flies the jet", X.waitFor(function() return st(p3).state == "flight" and st(p3).sub == "jet" end, 30))
		X.Jet.fly = realFly
		-- jet owned but away: the call books the shuttle
		local p4, s4 = newFounder(7204, "Max", 5)
		s4.data.empire.jet = true
		X.advance(2)
		local realAvail = X.Jet.available
		X.Jet.available = function() return false, "JET_BUSY", {} end
		newTrip(p4, s4, "helix")
		check("jet away -> shuttle in the plan", st(p4).plan and st(p4).plan.how == "shuttle")
		check("call without 'our jet'", not has((itinCalls(s4)[1] or {}).text, "our jet"))
		X.Jet.available = realAvail
		-- the jet already flies the field staff of this trip (JetService staff flight): the shuttle, honestly
		X.Jet.STAFF_FRESH = staffFresh
		local p5, s5 = newFounder(7205, "Ned", 5)
		s5.data.empire.jet = true
		X.advance(2)
		newTrip(p5, s5, "helix")
		local c5 = itinCalls(s5)[1] or {}
		local okA5, why5, info5 = X.Jet.available(p5)
		-- with design/requests/itinerary.md #2 in the tree (JetService.pending honours ItineraryService.holds) the staff
		-- jet waits while he is asked: the call books our jet for all of them (strict: test_review jettogether)
		local jetPatched = string.find(sources["ServerScriptService/Server/Services/JetService.module.luau"] or "", "itinHolds", 1, true) ~= nil
		if jetPatched then
			check("jet patch: the staff jet waits while he is asked", okA5 == true, why5)
			check("jet patch: our jet for the founder and the colleagues", st(p5).plan and st(p5).plan.how == "jet" and st(p5).plan.aheadBy ~= "air" and has(c5.text, "our jet"), c5.text)
		else
			check("JetService flies the field staff", okA5 == false and why5 == "JET_BUSY" and info5.purpose == "staff", why5)
			check("staff jet: shuttle for the founder, colleagues fly ahead", st(p5).plan and st(p5).plan.how == "shuttle" and st(p5).plan.aheadBy == "air")
			check("call: 'already fly out and meet you in Port Meridian'", has(c5.text, "already fly out and meet you in Port Meridian") and has(c5.text, "the shuttle"), c5.text)
		end
		check("still no Economy call", #X.econCalls == 0, #X.econCalls)

	elseif SCENARIO == "region" then
		local p, s = newFounder(7301, "Rin", 4)
		local cash0 = s.data.money
		local trip, key = newTrip(p, s, "creative")
		local call = itinCalls(s)[1] or {}
		check("region call", call.title == "PixelForge wants to meet" and has(call.text, "Business City") and has(call.text, "City Hotel"), call.text)
		check("region plan: car", st(p).plan and st(p).plan.how == "car" and st(p).tier == "region")
		check("accept", accept(s).ok == true)
		local v = X.lastView(p) or {}
		check("banner: To PixelForge, 1 of 4", v.title == "To PixelForge" and v.step == 1 and v.steps == 4, v.title)
		check("boarded", (rideAndBoard(p, s, 400)))
		check("at the client office -> meeting", waitState(p, "meeting", 300))
		local q = X.meetingPrompt(IM.officeId("PixelForge"))
		check("meeting prompt of PixelForge", q ~= nil)
		if q then X.standAt(p, q.Parent.Position + Vector3.new(0, 0, -4)); X.firePrompt(q, p) end
		check("joined", trip.joined == true)
		check("hotel step", waitState(p, "hotel", 40))
		check("hotel = City Hotel", st(p).plan.hotel == (X.CityPlan.CITY_HOTEL and X.CityPlan.CITY_HOTEL.name or "City Hotel"))
		local r = X.act(s, { action = "leave" })
		check("Go home now", r.ok == true and st(p).state == "return")
		check("leave button text in region", (function()
			local vv = X.lastView(p) or {}
			for _, b in vv.buttons or {} do if b.id == "leave" then return false end end
			return true
		end)())
		local d = X.Drive.clientPlace("PixelForge")
		X.standAt(p, d.door.Position)
		check("car home", (rideAndBoard(p, s, 400)))
		check("home -> finished", waitState(p, "none", 400))
		check("no money", #X.econCalls == 0 and s.data.money == cash0)
		check("trip untouched", IM.findTrip(s.data.empire, key) == trip)
		check("hotel/leave button says 'Go home now' in the region", IM.buttonText("leave", "region") == "Go home now")

	elseif SCENARIO == "offer" then
		-- decline by phone
		local p, s = newFounder(7401, "Ola", 4)
		local trip, key = newTrip(p, s, "helix")
		check("offer", st(p).state == "offer")
		local r = decline(s)
		check("decline -> ok, 'travel without you'", r.ok == true and has(r.text, "without you"), r.text)
		check("no itinerary after decline", st(p).state == "none" and X.rideFolder(p) == nil and (itinCal(s)) == 0)
		check("banner closed", (X.lastView(p) or {}).closed == true)
		X.advance(3)
		check("declined trip is not offered again", #itinCalls(s) == 1 and st(p).state == "none")
		check("declined: the colleagues are not held for him any more", X.Itin.holds(p.UserId, key) == false)
		check("economy trip unchanged", IM.findTrip(s.data.empire, key) == trip and trip.joined == nil)
		-- decline from the banner (TripAction cancel while the offer is open)
		local trip2, key2 = newTrip(p, s, "frontier")
		check("second offer", st(p).state == "offer" and st(p).key == key2)
		check("banner cancel declines", X.act(s, { action = "cancel" }).ok == true and st(p).state == "none")
		local _ = trip2
		-- Go via TripAction with the key
		local p2, s2 = newFounder(7402, "Pia", 4)
		local _, k2 = newTrip(p2, s2, "helix")
		local rg = X.act(s2, { action = "go", key = k2 })
		check("TripAction go starts the trip", rg.ok == true and st(p2).state == "pickup", rg.err)
		if st(p2).sub == "scheduled" then
			check("timed pick-up: no car yet, Go text names the pick-up time", X.rideFolder(p2) == nil and has(rg.text, "picks you up"), rg.text)
			local rr = X.act(s2, { action = "retry" })
			check("Call car now: the car is booked at once", rr.ok == true and X.rideFolder(p2) ~= nil and st(p2).sub ~= "scheduled", tostring(rr.err))
		end
		check("go twice: already on the way", X.act(s2, { action = "go", key = k2 }).ok == true and st(p2).state == "pickup")
		X.Itin.cancel(p2)
		X.advance(1)
		check("cancel during pickup frees the car", st(p2).state == "none" and X.rideFolder(p2) == nil)
		check("cancel message names the colleagues", noticeHas(p2, "carry on without you"))
		-- autoTrips: countdown + Cancel
		local p3, s3 = newFounder(7403, "Quinn", 4)
		s3.data.empire.prefs.autoTrips = true
		local t0 = X.T
		newTrip(p3, s3, "helix")
		local c3 = st(p3)
		check("autoTrips -> countdown (no ring)", c3.state == "countdown" and #itinCalls(s3) == 0, c3.state)
		check("countdown end = 10 s after the offer", c3.countdownEnd and c3.countdownEnd - t0 > 0 and c3.countdownEnd - t0 <= 3.5 + IM.COUNTDOWN + 0.01)
		local am = findMsg(s3, "Helix Research wants to meet")
		check("assistant message with the countdown sentence", am ~= nil and has(am.body, "We leave in 10 s - tap Not this time to stay."))
		local v3 = X.lastView(p3) or {}
		check("countdown banner: Go now / Not this time + countdownEnd", v3.state == "countdown" and v3.countdownEnd == c3.countdownEnd and #v3.buttons == 2
			and v3.buttons[1].text == "Go now" and v3.buttons[2].text == "Not this time")
		X.advance(4)
		check("Cancel before the end", X.act(s3, { action = "cancel" }).ok == true and st(p3).state == "none")
		X.advance(IM.COUNTDOWN + 2)
		check("cancelled countdown never starts", st(p3).state == "none" and X.rideFolder(p3) == nil)
		-- autoTrips: countdown runs out -> starts by itself
		local p4, s4 = newFounder(7404, "Ray", 4)
		s4.data.empire.prefs.autoTrips = true
		newTrip(p4, s4, "helix")
		check("countdown (2)", st(p4).state == "countdown")
		X.advance(IM.COUNTDOWN + 1)
		check("countdown over -> pickup by itself", st(p4).state == "pickup")
		check("message: on your way", findMsg(s4, "On your way to Helix Research") ~= nil)
		X.Itin.cancel(p4)
		X.advance(1)
		-- an unanswered offer expires; an offer of a trip that ended goes
		local p5, s5 = newFounder(7405, "Sam", 4)
		newTrip(p5, s5, "helix", { duration = 5000 })
		check("offer (5)", st(p5).state == "offer")
		X.advance(IM.OFFER_TTL + 2, 1)
		check("unanswered offer expires", st(p5).state == "none")
		local p6, s6 = newFounder(7406, "Tia", 4)
		local trip6, key6 = newTrip(p6, s6, "helix")
		check("offer (6)", st(p6).state == "offer")
		table.remove(s6.data.empire.deals.tripList, table.find(s6.data.empire.deals.tripList, trip6))
		X.advance(1)
		check("offer of an ended trip goes", st(p6).state == "none")
		local late = X.act(s6, { action = "go", key = key6 })
		check("go for an ended trip: TRIP_OVER", late.ok == false and late.err == "TRIP_OVER")
		-- trips that don't need the founder never ring
		local p7, s7 = newFounder(7407, "Uma", 4)
		newTrip(p7, s7, "helpdesk")
		newTrip(p7, s7, "helix", { kind = "renew" })
		newTrip(p7, s7, "helix", { hosted = true })
		check("city / renew / hosted: no call", #itinCalls(s7) == 0 and st(p7).state == "none")
		-- a trip under way when the founder joined stays staff work
		local p8, s8 = X.newPlayer(7408, "Vic", 4)
		X.addTrip(s8, "helix")
		X.advance(5)
		check("trip under way at join: no call", #itinCalls(s8) == 0)
		check("no Economy call", #X.econCalls == 0)
		local __ = key

	elseif SCENARIO == "edge" then
		-- two trips: the second is queued and offered once the founder is free
		local p, s = newFounder(7501, "Ada", 5)
		local _, k1 = newTrip(p, s, "helix", { duration = 4000 })
		accept(s)
		check("first trip started", st(p).state == "pickup" and st(p).key == k1)
		local _, k2 = newTrip(p, s, "frontier", { duration = 4000 })
		check("second trip queued, no second call", sameList(st(p).queue or {}, { k2 }) and #itinCalls(s) == 1, #itinCalls(s))
		check("go for the second while travelling: ALREADY_TRAVELLING", X.act(s, { action = "go", key = k2 }).err == "ALREADY_TRAVELLING")
		X.Itin.cancel(p)
		X.advance(2.2)
		check("queued trip offered when free", st(p).state == "offer" and st(p).key == k2 and #itinCalls(s) == 2)
		check("its call names Orbit Systems", has((itinCalls(s)[1] or {}).title, "Orbit Systems"))
		X.act(s, { action = "cancel" })
		-- the queue skips trips with too little left
		local p1, s1 = newFounder(7502, "Bo", 5)
		newTrip(p1, s1, "helix", { duration = 4000 })
		accept(s1)
		newTrip(p1, s1, "frontier", { duration = 200 })
		X.Itin.cancel(p1)
		X.advance(2.2)
		check("queued trip with < QUEUE_MIN_LEFT left is dropped", st(p1).state == "none" and #(st(p1).queue or {}) == 0)

		-- trip ends during the pick-up
		local p2, s2 = newFounder(7503, "Cy", 4)
		local t2 = newTrip(p2, s2, "helix")
		accept(s2)
		check("pickup (ends)", st(p2).state == "pickup")
		local list = s2.data.empire.deals.tripList
		table.remove(list, table.find(list, t2))
		X.advance(1)
		check("trip over before the flight -> itinerary stops", st(p2).state == "none" and noticeHas(p2, "visit is over"))
		check("its car is cancelled", X.rideFolder(p2) == nil)

		-- no driver yet (stage 1): honest text, GPS, the airport reached on foot
		local p3, s3 = newFounder(7504, "Dee", 1)
		newTrip(p3, s3, "helix")
		local c3 = itinCalls(s3)[1] or {}
		check("no driver: honest call", has(c3.text, "We don't have a company driver yet"), c3.text)
		accept(s3)
		check("self leg, reason NO_DRIVER", st(p3).state == "pickup" and st(p3).sub == "self" and st(p3).reason == "NO_DRIVER", tostring(st(p3).sub) .. " " .. tostring(st(p3).reason))
		check("GPS guide to the airport", #X.notifies(p3, "TRAVEL_GUIDE") >= 1)
		local v3 = X.lastView(p3) or {}
		check("banner: Call car + Cancel trip", #v3.buttons == 2 and v3.buttons[1].id == "retry" and v3.buttons[2].id == "cancel")
		check("beacon target published (City Airport kerb)", type(v3.target) == "table" and v3.target.pos ~= nil and v3.target.label == "City Airport"
			and (v3.target.pos - X.Drive.place("airport_departures").door.Position).Magnitude < 0.1, v3.target and v3.target.label)
		X.standAt(p3, X.FP.HOME_GATES[1] + Vector3.new(0, 0, 10))
		X.advance(1)
		check("in the airport on foot -> airport step + booking", st(p3).state == "airport" and X.Shuttle.booking(p3) ~= nil)
		X.Itin.cancel(p3)
		X.advance(1)

		-- the company booking never runs out of seats
		local okAll = true
		local players = {}
		for i = 1, 14 do
			local pp, ss = X.newPlayer(7600 + i, "Seat" .. i, 4)
			table.insert(players, { pp, ss })
		end
		X.advance(1.5)
		for _, ps in players do
			local r = X.Shuttle.book(ps[2], { to = "abroad" })
			if not r.ok or r.prepaid ~= true then okAll = false end
		end
		check("14 company bookings on one leg: all seated, all prepaid", okAll)
		for _, ps in players do X.Shuttle.unbook(ps[1]); X.close(ps[1], ps[2]) end

		-- respawn during the pick-up: still on, a new car
		local p4, s4 = newFounder(7505, "Eli", 4)
		newTrip(p4, s4, "helix")
		accept(s4)
		check("pickup (respawn)", st(p4).state == "pickup")
		X.F.respawn(p4, CFrame.new(X.hqPoint(p4, Vector3.new(0, 3, -60))))
		X.advance(1)
		check("respawn at home during pick-up: trip still on", st(p4).state == "pickup" and noticeHas(p4, "still on"))
		X.Itin.cancel(p4)
		X.advance(1)

		-- founder already abroad: limousine only; a region trip is queued
		local p5, s5 = newFounder(7506, "Fay", 4)
		local bk = X.Shuttle.book(s5, { to = "abroad" })
		check("own company booking out", bk.ok == true)
		X.standAt(p5, X.FP.HOME_GATES[1] + Vector3.new(2, 0, 3))
		check("flown to Port Meridian", X.waitFor(function() return X.City.state(p5) == "abroad" end, 900))
		X.advance(3)
		local _, kr = newTrip(p5, s5, "creative")
		check("region trip while abroad: no call, queued", #itinCalls(s5) == 0 and table.find(st(p5).queue or {}, kr) ~= nil)
		check("go region while abroad: ABROAD", X.act(s5, { action = "go", key = kr }).err == "ABROAD")
		local t5 = newTrip(p5, s5, "helix")
		local c5 = itinCalls(s5)[1] or {}
		check("abroad call: you're already there", has(c5.text, "You're already in Port Meridian"), c5.text)
		check("plan: limousine only", st(p5).plan and st(p5).plan.how == "limo")
		accept(s5)
		check("starts with the limousine", st(p5).state == "limo")
		check("no City Airport items in the calendar", (function()
			local _, cal = itinCal(s5)
			for k in cal do if has(k, ":pickup") or has(k, ":flight") then return false end end
			return true
		end)())
		-- the visit ends while he is abroad: the return starts
		local list5 = s5.data.empire.deals.tripList
		table.remove(list5, table.find(list5, t5))
		X.advance(1)
		check("trip over abroad -> return", st(p5).state == "return" and st(p5).over == true)
		check("message: the visit is over", findMsg(s5, "The visit is over") ~= nil)
		-- respawn abroad -> home: the itinerary ends
		X.F.respawn(p5, CFrame.new(X.hqPoint(p5, Vector3.new(0, 3, -60))))
		X.City.trips[p5.UserId] = nil
		X.advance(1)
		check("respawn at home while abroad ends the itinerary", st(p5).state == "none")

		-- hotel provider: ok -> its room; failing -> the own prompt
		local provided = 0
		X.Itin.setHotelProvider(function(player, info)
			provided += 1
			if provided == 1 then return { ok = true, name = "Royal Penthouse", room = 1001 } end
			error("provider broke")
		end)
		for round = 1, 2 do
			local ph, sh = newFounder(7510 + round, "Hal" .. round, 4)
			local bkh = X.Shuttle.book(sh, { to = "abroad" })
			X.standAt(ph, X.FP.HOME_GATES[1] + Vector3.new(2, 0, 3))
			X.waitFor(function() return X.City.state(ph) == "abroad" end, 900)
			X.advance(3)
			local th = newTrip(ph, sh, "helix")
			accept(sh)
			check("provider round " .. round .. ": limo", st(ph).state == "limo" and bkh.ok == true)
			X.standAt(ph, X.Drive.clientPlace("Helix Research").door.Position)
			X.advance(1)
			check("provider round " .. round .. ": at the tower -> meeting", st(ph).state == "meeting")
			th.joined = true
			X.waitFor(function() return st(ph).state == "hotel" end, IM.MEETING_TALK + 5)
			local promptH = M.game.Workspace.ItineraryPrompts:FindFirstChild("ItinRoom_" .. ph.UserId)
			if round == 1 then
				check("provider room in the banner", st(ph).room == "Royal Penthouse 1001" and has((X.lastView(ph) or {}).title, "Royal Penthouse 1001"), st(ph).room)
				check("no own prompt with a provider", promptH == nil)
			else
				check("failing provider -> own check-in prompt", promptH ~= nil and st(ph).room == nil)
			end
			X.Itin.cancel(ph)
			X.advance(1)
		end
		X.Itin.setHotelProvider(nil)
		check("no Economy call", #X.econCalls == 0, #X.econCalls)

	elseif SCENARIO == "remote" then
		X.Driver.LIMITS.other = { 8, 3 } -- the real per-action limits (limiters are created on first use)
		local p, s = newFounder(7701, "Ivy", 4)
		check("status without a trip", X.act(s, { action = "status" }).ok == true and X.act(s, { action = "status" }).state == "none")
		check("go without a trip: NO_TRIP", X.act(s, { action = "go" }).err == "NO_TRIP")
		check("leave without a trip: NO_TRIP", X.act(s, { action = "leave" }).err == "NO_TRIP")
		check("cancel without a trip: NO_TRIP", X.act(s, { action = "cancel" }).err == "NO_TRIP")
		check("retry without a trip: NO_TRIP", X.act(s, { action = "retry" }).err == "NO_TRIP")
		for _, bad in { 12, "a b", "helix", string.rep("x", 60) .. ":1", {} } do
			check("bad key rejected: " .. tostring(bad), X.act(s, { action = "go", key = bad }).err == "BAD_INPUT")
		end
		check("unknown action", X.act(s, { action = "explode" }).err == "BAD_INPUT")
		check("missing action", X.act(s, {}).err == "BAD_INPUT")
		check("assistant summary: nothing", X.Itin.summary(s) == nil)
		local trip, key = newTrip(p, s, "helix")
		check("assistant summary: the offer", has(X.Itin.summary(s), "Helix Research wants to meet you in Port Meridian"))
		X.act(s, { action = "go", key = key })
		local sum = X.Itin.summary(s)
		check("assistant summary: on the way, hotel, return", has(sum, "to Helix Research (Port Meridian)") and has(sum, "Meridian Grand Hotel") and has(sum, "back "), sum)
		local Assistant = M.require(X.S.AssistantService)
		local okB, brief = pcall(Assistant.briefing, s)
		local found = false
		if okB and typeof(brief) == "table" then
			for _, sec in brief.sections or {} do
				for _, row in sec.rows or {} do
					local label = row.label or row[1] or row.title
					if label == "Your trip" then found = true end
				end
			end
		end
		check("assistant briefing has the 'Your trip' row", found, okB and "" or brief)
		check("claims() for DriverService", X.Itin.claims(p.UserId, key) == true and X.Itin.claims(p.UserId, "helix:1") == false)
		-- Go / Cancel spam: at most one started itinerary (one replicated folder) per GO_GAP s
		local pg, sg = newFounder(7703, "Gil", 4)
		local _, kg = newTrip(pg, sg, "helix")
		check("go (1)", X.act(sg, { action = "go", key = kg }).ok == true)
		X.act(sg, { action = "cancel" })
		local again = X.act(sg, { action = "go", key = kg })
		check("go right after a cancel: one moment please (no folder churn)", again.ok == false and again.err == "RATE_LIMIT", again.err)
		X.advance(X.Itin.GO_GAP + 0.1)
		check("go after GO_GAP s: ok", X.act(sg, { action = "go", key = kg }).ok == true)
		X.Itin.cancel(pg)
		-- per-action rate limit (DriverService.onTripAction limiter, real limits)
		local p2, s2 = newFounder(7702, "Jo", 4)
		local limited = false
		for i = 1, 30 do
			local r = X.act(s2, { action = "status" })
			if r.err == "RATE_LIMIT" then limited = true; break end
		end
		check("status spam hits the rate limit", limited)
		check("other actions keep their own budget", X.act(s2, { action = "go" }).err == "NO_TRIP")
		-- leave the game mid-trip: everything of the itinerary goes, the trip stays the economy's
		local f = folderOf(p)
		check("folder while travelling", f ~= nil)
		X.close(p, s)
		X.advance(2)
		check("left the game: folder removed", folderOf(p) == nil)
		check("left the game: no record", X.Itin.state(p) == nil)
		check("left the game: economy trip untouched", IM.findTrip(s.data.empire, key) == trip)
		X.advance(5)
		check("ticks after leaving run clean", M.stats.errors == 0, M.stats.errors)
		check("no Economy call", #X.econCalls == 0)
	else
		check("known scenario " .. SCENARIO, false)
	end
	local _ = Instance
	local __ = messages
end

local ok, err = M.runMain(body, { timeout = 6000, maxSteps = 60000000 })
if not ok then failc += 1; print("CRASH " .. tostring(err)) end
if M.stats.errors > 0 then failc += 1; print("FAIL  background thread errors: " .. M.stats.errors) end
print(string.format("itinerary_service_%s: %d passed, %d failed", SCENARIO, pass, failc))
