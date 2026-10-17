--!strict
-- ItineraryMath (package "itinerary", LOGIC_BRIEF 24): pure maths and texts of the founder's business trip.
-- Nothing here creates instances or moves money. Used by ItineraryService (server: the state machine, the
-- assistant's booking call, the phone calendar) and ItineraryController (client: banner, beacon, client NPCs).
--   * which economy trips need the founder (needsFounder): pilot visits (kind "sign") of a field rep abroad
--     (Port Meridian, incl. the frontier clients) and in the region (Business City + City Hotel); never the founder's
--     own city trips, check-in visits or client teams hosted at the guest house;
--   * who travels with him (travellers): the REAL field rep (+ engineer) of that trip - the same rule as
--     DriverService / PhoneMath / ShuttleService / JetService (k-th field rep for the k-th non-founder trip, the m-th
--     travelling engineer of CompanyOps.presence for the m-th region / abroad pilot);
--   * the plan (plan): pick-up, the booked flight (the next shuttle departure he can still reach from the FlightPlan
--     timetable, or the company jet's JetPlan timeline), arrival, limousine, meeting, hotel, the pre-booked return
--     (the first departure home after the economic trip ends) and the ride home - every time a server clock
--     (workspace:GetServerTimeNow()) the phone turns into its company day and hour (PhoneMath.atClock);
--   * texts: the assistant's call (callText), the banner lines (banner), the calendar items (calendarItems) and
--     the travel desk's messages - every number comes from the plan / real game state;
--   * places: the meeting table and chairs of a client office (meetingSpot, from CityPlan.layout), gate / stand /
--     hotel reception points, area tests for the positional checks of the state machine.
-- The ECONOMIC trip keeps its CORE_SPEC clock (CompanyOps): the itinerary only shows and guides, it never moves
-- `back`, never charges and never blocks the economy.
local Shared = script.Parent
local Ops = require(Shared.CompanyOps)
local PhoneMath = require(Shared.PhoneMath)
local FP = require(Shared.FlightPlan)
local CityPlan = require(Shared.Config.CityPlan)
local EmpireConfig = require(Shared.Config.EmpireConfig)
local CampusMath = require(Shared.CampusMath)
local okJet, JetPlan = pcall(function(): any return require(Shared.JetPlan) end)

local IM = {}
IM.COUNTDOWN = 10 -- seconds of the auto-trip countdown (setting "Join business trips automatically")
IM.OFFER_TTL = 600 -- an unanswered offer stays valid this long (and never after the trip ended)
IM.QUEUE_MIN_LEFT = 300 -- a second trip is offered later only while this many seconds of it remain
IM.MEETING_TALK = 20 -- seconds the client team talks after the founder joined, then the hotel step
IM.WALK_GATE = 40 -- seconds from the departures kerb through security to gate A1 (plan estimate)
IM.WALK_PM = 12 -- seconds from the arrivals hall / jet airstair to the limousine stand (plan estimate)
IM.LIMO_SECS = 50 -- seconds of the limousine to a client tower (plan estimate when no ride is known)
IM.SELF_AIRPORT = 180 -- seconds to City Airport without a driver (plan estimate: walk / own car)
IM.RIDE_HOME = 110 -- seconds of the ride City Airport -> HQ (plan estimate)
IM.HOTEL_AFTER = 120 -- the hotel step after the meeting (plan estimate)
IM.JET_WAIT = 90 -- the company jet: wait at most this long for a clear runway, else the shuttle
IM.MAX_COMPANIONS = 2 -- the car has two seats in the back (DriverService.MAX_PASSENGERS)
IM.ARRIVE_RADIUS = 45 -- "at the client office": within this many studs of its door / lobby / meeting room
IM.HOTEL_RADIUS = 70
IM.AIRPORT_MARGIN = 24 -- City Airport terminal rect margin (the departures kerb is 17 studs in front of it)
IM.GATE_EARLY = 15 -- a timed pick-up brings him to the gate this many seconds after the boarding opened ...
IM.PICKUP_SLACK = 45 -- ... when the car called at once would bring him there more than this many seconds earlier
IM.SCHEDULE_MIN = 30 -- the car is only called later when that call is at least this many seconds away
IM.DEBOARD_WAIT = 20 -- seconds the colleagues need to walk off the shuttle (ShuttlePassengers) before the car is called
IM.MEETING_ROOM = 30 -- the client team stays at the table while the founder is within this many studs of it ...
IM.MEETING_LINGER = 240 -- ... and at most this many seconds after the meeting step ended
IM.STEPS = {
	abroad = { "pickup", "airport", "flight", "limo", "meeting", "hotel", "return" },
	region = { "pickup", "meeting", "hotel", "return" },
} :: { [string]: { string } }
IM.STEP_TITLE = {
	pickup = "Driver", airport = "Airport", flight = "Flight", limo = "Limousine", meeting = "Meeting", hotel = "Hotel",
	["return"] = "Return", home = "Home",
} :: { [string]: string }
IM.ROLE_TEAM = { marketer = "Growth & Sales", engineer = "Engineering", researcher = "Research", curator = "Data" } :: { [string]: string }

export type Person = { name: string, role: string, seed: number? }
export type DriverInfo = {
	name: string?, -- the company driver's name (DriverService.DRIVERS[1] with the owner id)
	eta: number?, -- seconds until the car waits at the pick-up
	ride: number?, -- seconds of the ride itself
	pickupAt: string?, -- "the HQ entrance" (DrivePlan.atName)
	self: boolean?, -- no company car for this leg (garage stage, too far, every car out ...)
	reason: string?, -- DriverService error code when self
	queued: boolean?, -- every car is out: the next free one (eta counts it in)
	night: boolean?, -- 22:00-06:00: the driver is on call in the drivers' room
}
export type PlanInput = {
	tier: string, -- "abroad" | "region"
	client: string, -- catalogue client name ("Helix Research")
	clientId: string?,
	now: number, -- server clock
	backAt: number, -- server clock when the economic trip ends (CompanyOps trip.back)
	from: string?, -- "home" (default) | "abroad" (the founder is already in Port Meridian)
	jet: boolean?, -- the company jet is booked instead of the shuttle
	captain: string?,
	companions: { Person }?,
	ahead: boolean?, -- the companions already left in a company car (DriverService field ride) / flew ahead
	aheadBy: string?, -- "car" (a field car took them to the airport / the office) | "air" (already flying to Port Meridian)
	driver: DriverInfo?,
	hotels: { city: string?, abroad: string? }?,
	joinAt: number?, -- from = "abroad": server clock when the companions (flying out from home) are at the tower
	joinFlight: string?, -- ... and how they come ("PM 101" / "company jet")
	schedule: boolean?, -- false: the car is called already (no timed pick-up)
}
export type Plan = {
	tier: string,
	client: string,
	clientId: string?,
	city: string, -- "Port Meridian" | "Business City"
	from: string,
	how: string, -- "shuttle" | "jet" | "car" (region) | "limo" (already abroad)
	flight: string?, -- "PM 101"
	airportAt: number?,
	departs: number?, -- outbound departure (pushback)
	boardEnd: number?,
	arrives: number?, -- placed in Port Meridian
	meetingAt: number,
	hotel: string,
	hotelAt: number,
	backAt: number,
	returnFlight: string?, -- "PM 102" / "company jet"
	returnAt: number?, -- return departure (abroad) / ride home (region)
	homeAt: number?,
	companions: { Person },
	ahead: boolean, -- the companions went ahead (meet him at the gate / the office)
	aheadBy: string?, -- "car" | "air" (see PlanInput)
	driver: DriverInfo?,
	captain: string?,
	pickupAt: number?, -- when the car waits at the pick-up
	requestAt: number?, -- a timed pick-up: when the car is called (nil = at once)
	joinAt: number?, -- from = "abroad": when the companions arrive at the tower (PlanInput.joinAt)
	joinFlight: string?,
}

------------------------------------------------------------------------------------------------ trips
-- The trip key the services share (DriverService / JetService / ShuttleService): client..":"..left
function IM.tripKey(trip: any): string
	if typeof(trip) ~= "table" then return "" end
	return tostring(trip.client) .. ":" .. tostring(trip.left)
end
-- A valid key string from a remote payload / call data ("helix:12345")
function IM.validKey(key: any): string?
	if typeof(key) ~= "string" or #key > 48 then return nil end
	if not string.match(key, "^[%w_]+:%-?%d+$") then return nil end
	return key
end
-- Does this tripList entry need the founder? Pilot visits of a field rep abroad / in the region (CORE_SPEC 3.2:
-- the founder sells city clients himself; check-ins and hosted visits stay staff work).
function IM.needsFounder(trip: any): (boolean, string?)
	if typeof(trip) ~= "table" or trip.founder == true or trip.hosted == true or trip.kind ~= "sign" then return false, nil end
	local c = Ops.client(trip.client)
	if not c then return false, nil end
	if c.trip == "abroad" or c.trip == "region" then return true, c.trip end
	return false, nil
end
function IM.findTrip(e: any, key: string): any
	local deals = if typeof(e) == "table" then e.deals else nil
	if typeof(deals) ~= "table" or typeof(deals.tripList) ~= "table" then return nil end
	for _, t in deals.tripList do
		if typeof(t) == "table" and IM.tripKey(t) == key then return t end
	end
	return nil
end
-- seconds of the economic trip still to go (play seconds run 1:1 with the server clock while online)
function IM.left(e: any, trip: any): number
	local seconds = if typeof(e) == "table" then tonumber(e.seconds) or 0 else 0
	return (tonumber(trip and trip.back) or 0) - seconds
end
local function profileOf(e: any, role: string, i: number): any
	local list = if typeof(e.staffProfiles) == "table" then e.staffProfiles[role] else nil
	local p = if typeof(list) == "table" then list[i] else nil
	return if typeof(p) == "table" and typeof(p.n) == "string" and p.n ~= "" then p else nil
end
-- The people who travel on `trip`: the field rep, then the engineer (CompanyOps.presence "trip"), at most
-- MAX_COMPANIONS. Same rule as DriverService.tripTravellers / PhoneMath.travellers.
function IM.travellers(e: any, trip: any): { Person }
	local out: { Person } = {}
	if typeof(e) ~= "table" or typeof(trip) ~= "table" then return out end
	local deals = e.deals
	if typeof(deals) ~= "table" or typeof(deals.tripList) ~= "table" then return out end
	local away: { any } = {}
	local okP, presence = pcall(Ops.presence, e, "engineer")
	if okP and typeof(presence) == "table" then
		for i, st in presence do
			if st == "trip" then
				local p = profileOf(e, "engineer", i)
				if p then table.insert(away, p) end
			end
		end
	end
	local reps = Ops.fieldReps(e)
	local k, m = 0, 0
	for _, t in deals.tripList do
		if typeof(t) ~= "table" or t.founder == true then continue end
		k += 1
		local c = Ops.client(t.client)
		local engIndex: number? = nil
		if c and c.trip ~= "city" and not t.hosted and t.kind == "sign" then
			m += 1
			engIndex = m
		end
		if t == trip or IM.tripKey(t) == IM.tripKey(trip) then
			local rep = if k <= reps then profileOf(e, "marketer", k) else nil
			if rep then table.insert(out, { name = rep.n, role = "marketer", seed = tonumber(rep.s) }) end
			if engIndex and away[engIndex] and (tonumber(t.crew) or 0) >= 2 and #out < IM.MAX_COMPANIONS then
				local p = away[engIndex]
				table.insert(out, { name = p.n, role = "engineer", seed = tonumber(p.s) })
			end
			break
		end
	end
	return out
end
function IM.firstName(name: string?): string
	if typeof(name) ~= "string" or name == "" then return "" end
	return string.match(name, "^(%S+)") or name
end
-- "Mia from Growth & Sales and Leo from Engineering" / "Mia from Growth & Sales" / ""
function IM.whoText(people: { Person }): string
	local parts: { string } = {}
	for _, p in people do table.insert(parts, IM.firstName(p.name) .. " from " .. (IM.ROLE_TEAM[p.role] or "the team")) end
	if #parts == 0 then return "" end
	if #parts == 1 then return parts[1] end
	return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]
end
-- "Mia and Leo" / "Mia" / "your team"
function IM.namesText(people: { Person }): string
	local parts: { string } = {}
	for _, p in people do table.insert(parts, IM.firstName(p.name)) end
	if #parts == 0 then return "your team" end
	if #parts == 1 then return parts[1] end
	return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]
end

------------------------------------------------------------------------------------------------ times
-- The shuttle leg in direction `dir` ("out" | "back") the founder can still catch when he is at the gate at `at`:
-- (flight number, departure = pushback, boarding end, arrival = deboarding start, leg start, cycle)
function IM.shuttleLeg(dir: string, at: number): (string, number, number, number, number, number)
	local cycle, legStart, departs, boardEnd = FP.nextLeg(dir, at)
	local leg = FP.leg(dir)
	return leg.flight, departs, boardEnd, legStart + leg.phases.deboarding.t0, legStart, cycle
end
-- The company jet out / back started at `start`: (departure, arrival)
function IM.jetTimes(kind: string, start: number): (number, number)
	if okJet and typeof(JetPlan) == "table" then
		local ok, dep, arr = pcall(function(): (number, number)
			local tl = JetPlan.timeline(kind, 1, 0)
			local d, a = JetPlan.times(tl, start)
			return d, a
		end)
		if ok and typeof(dep) == "number" and typeof(arr) == "number" then return dep, arr + 4 end
	end
	return start + 20, start + 164
end
-- "14:30" today, "Day 10 · 08:42" another company day (the phone's own conversion). Company days turn at 08:00, so
-- 00:00-08:00 still belongs to the day before: those hours read "05:10 tonight" (today) / "night of Day 11 · 05:10"
-- (another day) - never "Day 11 · 05:10", which a player reads as earlier than "Day 11 · 23:58".
function IM.clockText(e: any, now: number, at: number): string
	local today = Ops.day(e)
	local day, hour = PhoneMath.atClock(e, now, at)
	local h = hour % 24
	if h < 8 then
		if day == today then return PhoneMath.clock(h) .. (if Ops.hour(now) % 24 >= 8 then " tonight" else "") end
		return "night of Day " .. math.max(1, math.floor(day)) .. " · " .. PhoneMath.clock(h)
	end
	return PhoneMath.when(day, hour, today)
end
-- "at 14:30" / "on Day 10 · 08:42" / "at 05:10 tonight" / "in the night of Day 11 · 05:10"
function IM.atText(e: any, now: number, at: number): string
	local t = IM.clockText(e, now, at)
	if string.sub(t, 1, 5) == "night" then return "in the " .. t end
	return if string.find(t, "Day", 1, true) then "on " .. t else "at " .. t
end
-- "1:20" countdown of seconds
function IM.mmss(seconds: number): string
	local s = math.max(0, math.floor((if seconds == seconds then seconds else 0) + 0.5))
	return string.format("%d:%02d", s // 60, s % 60)
end

------------------------------------------------------------------------------------------------ plan
function IM.plan(input: PlanInput): Plan
	local now = input.now
	local tier = if input.tier == "region" then "region" else "abroad"
	local from = if input.from == "abroad" and tier == "abroad" then "abroad" else "home"
	local hotels: any = input.hotels or {}
	local hotel: string = if tier == "abroad" then (hotels.abroad or "Meridian Grand Hotel") else (hotels.city or "City Hotel")
	local companions: { Person } = {}
	local given: { Person } = input.companions or {}
	for _, p in given do
		if #companions >= IM.MAX_COMPANIONS then break end
		table.insert(companions, p)
	end
	local d = input.driver
	local plan: Plan = {
		tier = tier, client = input.client, clientId = input.clientId, city = if tier == "abroad" then "Port Meridian" else "Business City", from = from,
		how = "shuttle", flight = nil, airportAt = nil, departs = nil, boardEnd = nil, arrives = nil, meetingAt = now, hotel = hotel, hotelAt = now,
		backAt = input.backAt, returnFlight = nil, returnAt = nil, homeAt = nil, companions = companions, ahead = input.ahead == true,
		aheadBy = if input.ahead == true then (input.aheadBy or "car") else nil, driver = d,
		captain = input.captain, pickupAt = nil, requestAt = nil,
		joinAt = if from == "abroad" then input.joinAt else nil, joinFlight = if from == "abroad" then input.joinFlight else nil,
	}
	-- first leg: the car to the airport / the client office
	local carTo = now
	local carEta: number? = nil
	if from == "home" then
		if d and not d.self then
			carEta = d.eta or 0
			plan.pickupAt = now + (d.eta or 0)
			carTo = now + (d.eta or 0) + 2 + (d.ride or 0)
		else
			carTo = now + IM.SELF_AIRPORT
		end
	end
	if tier == "region" then
		plan.how = "car"
		plan.meetingAt = carTo
		plan.hotelAt = plan.meetingAt + IM.HOTEL_AFTER
		plan.returnAt = math.max(input.backAt, plan.hotelAt)
		plan.returnFlight = nil
		return plan
	end
	local arrivePM = now
	if from == "home" then
		if input.jet then
			plan.airportAt = carTo
			plan.how = "jet"
			plan.flight = "company jet"
			local dep, arr = IM.jetTimes("out", carTo)
			plan.departs, plan.arrives = dep, arr
			arrivePM = arr
		else
			local flight, departs, boardEnd, arrives, legStart = IM.shuttleLeg("out", carTo + IM.WALK_GATE)
			-- a timed pick-up instead of a long wait at the gate: with a free company car the car is called later, so he
			-- reaches the gate GATE_EARLY s after the boarding of the SAME flight opened (the jet leaves when he is there)
			local shift = (legStart + IM.GATE_EARLY) - (carTo + IM.WALK_GATE)
			if carEta and d and not d.queued and input.schedule ~= false and shift > IM.PICKUP_SLACK then
				plan.requestAt = now + shift
				plan.pickupAt = now + shift + carEta
				carTo += shift
			end
			plan.airportAt = carTo
			plan.flight, plan.departs, plan.boardEnd, plan.arrives = flight, departs, boardEnd, arrives
			arrivePM = arrives
		end
	else
		plan.how = "limo"
	end
	plan.meetingAt = arrivePM + IM.WALK_PM + IM.LIMO_SECS
	plan.hotelAt = plan.meetingAt + IM.HOTEL_AFTER
	-- the pre-booked return: the first departure home after the visit ends (never before the hotel step)
	local earliest = math.max(input.backAt, plan.hotelAt)
	if input.jet then
		plan.returnFlight = "company jet"
		local _, arr = IM.jetTimes("back", earliest)
		plan.returnAt, plan.homeAt = earliest, arr + IM.RIDE_HOME
	else
		local flight, departs, _, arrives = IM.shuttleLeg("back", earliest)
		plan.returnFlight, plan.returnAt, plan.homeAt = flight, departs, arrives + IM.RIDE_HOME
	end
	return plan
end

------------------------------------------------------------------------------------------------ texts
-- The driver sentence of the booking call (honest about who comes and when). at = "at 14:05" for a timed pick-up.
function IM.driverText(d: DriverInfo?, tier: string, at: string?): string
	local dest = if tier == "region" then "the office" else "City Airport"
	if not d or d.self then
		local why = if d and d.reason == "NO_DRIVER" then "We don't have a company driver yet"
			elseif d and d.reason == "TOO_FAR" then "You're too far from a pick-up point"
			elseif d and d.reason == "LEAVE_VEHICLE" then "You're in your own car"
			else "No company car can pick you up right now"
		return why .. ": the GPS shows you the way to " .. dest .. "."
	end
	local where = d.pickupAt or "the HQ entrance"
	if d.queued then
		-- every car is out: the real estimate when there is one, never a made-up "0:00"
		if typeof(d.eta) == "number" and d.eta >= 1 then return "All cars are out - the next one is at " .. where .. " in about " .. IM.mmss(d.eta) .. "." end
		return "All cars are out - the next one picks you up at " .. where .. "."
	end
	local name = IM.firstName(d.name)
	local who = if name ~= "" then "Your driver " .. name else "Your driver"
	if at then return who .. " picks you up at " .. where .. " " .. at .. "." end
	local eta = IM.mmss(d.eta or 0)
	if where ~= "the HQ entrance" then return who .. " picks you up at " .. where .. " (about " .. eta .. ")." end
	if d.night then return who .. " is on call tonight: the car is at the HQ entrance about " .. eta .. " after you say Go." end
	return who .. " is waiting at the HQ entrance."
end
-- Who travels with him (the call): one colleague with the team, two by first name; honest when they went ahead in a
-- field car, already fly out, or (he is in Port Meridian already) join him at the tower later.
function IM.teamText(plan: Plan, e: any, now: number): string
	local n = #plan.companions
	if n == 0 then return "You travel alone this time." end
	local one = n == 1
	local who = if one then IM.whoText(plan.companions) else IM.namesText(plan.companions)
	local meet = if one then " meets" else " meet"
	if plan.from == "abroad" then
		if plan.joinAt and plan.joinAt > now then
			local how = if plan.joinFlight == "company jet" then " with our jet" elseif plan.joinFlight then " on " .. plan.joinFlight else ""
			return who .. (if one then " flies" else " fly") .. " out" .. how .. " and" .. (if one then " joins" else " join") .. " you at the tower "
				.. IM.atText(e, now, plan.joinAt) .. "."
		end
		return who .. meet .. " you there."
	end
	local names = IM.namesText(plan.companions)
	if plan.ahead and plan.aheadBy == "air" and plan.tier == "abroad" then
		return names .. " already" .. (if one then " flies" else " fly") .. " out and" .. meet .. " you in Port Meridian."
	end
	if plan.ahead then
		local where = if plan.tier ~= "abroad" then " at the office." elseif plan.how == "jet" then " at our jet." else " at the gate."
		return names .. " went ahead and" .. (if one then " waits" else " wait") .. where
	end
	if plan.tier == "region" then return who .. (if one then " comes" else " come") .. " along." end
	return who .. (if one then " travels" else " travel") .. " with you."
end
-- The assistant's booking call: (title, text). plan from IM.plan; e = data.empire; auto = the countdown variant.
-- Short enough for the phone's call sheet (client, city, flight, hotel, who travels, the driver); the return flight is
-- in the calendar and the banner.
function IM.callText(plan: Plan, e: any, now: number, auto: boolean?): (string, string)
	local c = plan.client
	local title = c .. " wants to meet"
	local close = if auto then "We leave in " .. IM.COUNTDOWN .. " s - tap Not this time to stay." else "Shall we go?"
	local team = IM.teamText(plan, e, now)
	if plan.tier == "region" then
		return title, "A pilot meeting at their office in Business City; I booked the " .. plan.hotel .. ". " .. team .. " " .. IM.driverText(plan.driver, "region")
			.. " " .. close
	end
	if plan.from == "abroad" then
		return title, "You're already in Port Meridian: the VIP limousine takes you to their tower, and I booked the " .. plan.hotel .. ". " .. team .. " " .. close
	end
	local how = if plan.how == "jet" then "our jet" .. (if plan.captain then " (Captain " .. plan.captain .. ")" else "") .. " " .. IM.atText(e, now, plan.departs or now)
		else "the shuttle " .. tostring(plan.flight) .. " " .. IM.atText(e, now, plan.departs or now)
	local at = if plan.requestAt and plan.pickupAt then IM.atText(e, now, plan.pickupAt) else nil
	return title, "Meeting in Port Meridian: I booked " .. how .. " and the " .. plan.hotel .. ". " .. team .. " " .. IM.driverText(plan.driver, "abroad", at) .. " " .. close
end
-- One line for the phone message when the trip is declined
function IM.declineText(people: { Person }): string
	local n = IM.namesText(people)
	if #people == 0 then return "Okay. The team travels without you; you'll get the report here." end
	return "Okay. " .. n .. (if #people == 1 then " travels" else " travel") .. " without you; you'll get the report here."
end

------------------------------------------------------------------------------------------------ banner
export type Snap = {
	state: string, -- offer | countdown | pickup | airport | flight | limo | meeting | hotel | return | home | done
	sub: string?, -- coming | waiting | riding | queued | scheduled | self | own | gate | jet | jetwait | deboard | limo | flight | arrived
	tier: string,
	client: string,
	plan: Plan?,
	companions: { Person },
	carry: boolean?, -- companions ride with the founder (this car)
	together: boolean?, -- companions fly with him (false: they flew ahead / fly on their own)
	stay: boolean?, -- companions stay abroad (the founder flies home before the visit ended)
	driver: string?,
	eta: number?, -- server clock: the car is there / the next event
	flight: string?,
	departs: number?,
	boardEnd: number?,
	arrives: number?,
	gate: string?,
	room: string?, -- hotel provider: "Royal Penthouse 1001"
	checkedIn: boolean?,
	joined: boolean?,
	over: boolean?, -- the economic trip has ended
	countdownEnd: number?,
	reason: string?,
	joinAt: number?, -- he started in Port Meridian: the companions are at the tower from then (server clock)
	pickupAt: number?, -- a timed pick-up: the car waits at the pick-up then
	deboardUntil: number?, -- the colleagues walk off the shuttle until then; the car is called after
}
export type Banner = {
	title: string,
	sub: string,
	action: string, -- the one line the folded chip shows ("Press Start meeting at the table"), "" = none
	timerLabel: string?,
	timerAt: number?,
	buttons: { string }, -- ids: go | decline | cancel | leave | retry
	icon: string, -- PhoneKit glyph kind
	step: number,
	steps: number,
	stepName: string, -- "Airport" (IM.STEP_TITLE of the current step)
}
local function stepIndex(tier: string, state: string): (number, number)
	local list = IM.STEPS[tier] or IM.STEPS.abroad
	local idx = table.find(list, state) or (if state == "home" then #list else 0)
	return idx, #list
end
-- Banner lines for a snapshot of the founder's itinerary (pure; e for the day conversion). Every line about the
-- colleagues says where they really are: in his car (carry), flying with him (together), ahead, staying, arriving.
function IM.banner(s: Snap, e: any, now: number): Banner
	local step, steps = stepIndex(s.tier, s.state)
	local c = s.client
	local n = #s.companions
	local names = IM.namesText(s.companions)
	local are = if n == 1 then " is" else " are"
	local driver = IM.firstName(s.driver)
	local list = IM.STEPS[s.tier] or IM.STEPS.abroad
	local b: Banner = { title = "", sub = "", action = "", timerLabel = nil, timerAt = nil, buttons = {}, icon = "calendar", step = step, steps = steps,
		stepName = IM.STEP_TITLE[list[step] or s.state] or "" }
	local abroad = s.tier == "abroad"
	local together = s.together ~= false
	-- the offer's team tag: honest when they went ahead (field car), already fly out, or join him later in Port Meridian
	local pl = s.plan
	local team = if n == 0 then ""
		elseif pl and pl.ahead then " · " .. names .. (if pl.aheadBy == "air" then " fly ahead" else " went ahead")
		elseif pl and pl.joinAt and pl.joinAt > now then " · " .. names .. " join later"
		else " · with " .. names
	if s.state == "countdown" then
		b.title = "Business trip · " .. c
		b.sub = (if abroad then "Port Meridian" else "Business City") .. (if s.flight then " · " .. s.flight .. (if s.departs then " " .. IM.clockText(e, now, s.departs) else "") else "")
			.. team
		b.timerLabel, b.timerAt = "Leaving in", s.countdownEnd
		b.buttons = { "go", "decline" }
		b.icon = "assistant"
	elseif s.state == "offer" then
		b.title = "Trip offer · " .. c
		b.sub = (if abroad then "Port Meridian" else "Business City") .. (if s.flight and s.departs then " · " .. s.flight .. " " .. IM.clockText(e, now, s.departs) else "")
			.. team
		b.buttons = { "go", "decline" }
		b.icon = "assistant"
	elseif s.state == "pickup" then
		local dest = if abroad then "City Airport" else c
		local d = if s.plan then s.plan.driver else nil
		local at = if d and d.pickupAt then d.pickupAt else "the HQ entrance"
		local ride = if s.carry and n > 0 then " · " .. names .. " ride with you" elseif n > 0 then " · " .. names .. " went ahead" else ""
		b.title = "To " .. dest
		b.icon = "driver"
		if s.sub == "self" or s.sub == "own" then
			b.sub = (if s.sub == "own" then "You're on your way" elseif s.reason == "TOO_FAR" then "Walk to a pick-up point (HQ entrance, a client office) or drive"
				else "No company car: walk or drive") .. " - follow the GPS to " .. dest
			b.action = "Follow the GPS to " .. dest
			b.buttons = { "retry", "cancel" }
		elseif s.sub == "scheduled" then
			local pick = if s.pickupAt then IM.clockText(e, now, s.pickupAt) else ""
			b.sub = (if driver ~= "" then driver else "Your driver") .. " picks you up at " .. at .. (if pick ~= "" then " at " .. pick else "")
				.. (if s.flight and s.departs then " for " .. s.flight .. " (" .. IM.clockText(e, now, s.departs) .. ")" else "") .. ride
			b.action = "Pick-up at " .. (if pick ~= "" then pick else at)
			b.timerLabel, b.timerAt = "Pick-up in", s.pickupAt
			b.buttons = { "retry", "cancel" }
		elseif s.sub == "queued" then
			b.sub = "Every car is out · the next free one comes to " .. at .. ride
			b.timerLabel, b.timerAt = "Car in about", s.eta
			b.buttons = { "cancel" }
		elseif s.sub == "riding" then
			b.sub = (if driver ~= "" then driver .. " drives" else "On the way") .. (if s.carry and n > 0 then " · " .. names .. " ride with you" else "")
			b.action = "On the way to " .. dest
			b.buttons = { "cancel" }
		elseif s.sub == "waiting" then
			b.sub = (if driver ~= "" then driver else "Your car") .. " is waiting at " .. at .. ride
			b.action = "Your car is waiting - get in"
			b.buttons = { "cancel" }
		else
			b.sub = (if driver ~= "" then driver .. " brings the car round" else "Your car is coming") .. ride
			b.timerLabel, b.timerAt = "Car there in", s.eta
			b.buttons = { "cancel" }
		end
	elseif s.state == "airport" then
		b.icon = "map"
		if s.sub == "jet" or s.sub == "jetwait" then
			b.title = "Our jet is ready"
			b.sub = if s.sub == "jetwait" then "Waiting for a clear runway" else "The crew starts the engines" .. (if n > 0 and together then " · " .. names .. " board with you" else "")
			b.action = if s.sub == "jetwait" then "Waiting for a clear runway" else "Boarding our jet"
			b.buttons = { "cancel" }
		else
			b.title = "Gate " .. (s.gate or "A1") .. " · " .. (s.flight or "shuttle")
			b.sub = "Company booking: no check-in needed"
				.. (if n > 0 and together then " · " .. names .. " wait at the gate" elseif n > 0 then " · " .. names .. " flew ahead · they meet you in Port Meridian" else "")
			b.action = "Walk to gate " .. (s.gate or "A1")
			if s.boardEnd and s.boardEnd > now then b.timerLabel, b.timerAt = "Boarding ends in", s.boardEnd end
			b.buttons = { "cancel" }
		end
	elseif s.state == "flight" then
		b.title = "Flight to " .. (if s.sub == "home" then "City Airport" else "Port Meridian")
		b.sub = (s.flight or "") .. (if s.arrives then " · lands " .. IM.clockText(e, now, s.arrives) else "") .. (if n > 0 and together then " · " .. names .. " fly with you" else "")
		b.action = if s.arrives then "Lands " .. IM.clockText(e, now, s.arrives) else "In the air"
		b.icon = "map"
		b.buttons = {}
	elseif s.state == "limo" then
		b.title = "Limo · " .. c
		b.icon = "driver"
		local join = if s.joinAt and s.joinAt > now and n > 0 then " · " .. names .. " land " .. IM.clockText(e, now, s.joinAt) else ""
		if s.sub == "deboard" then
			b.sub = names .. are .. " getting off the plane - then the limousine takes you all to " .. c
			b.action = "Team getting off the plane"
			if s.deboardUntil and s.deboardUntil > now then b.timerLabel, b.timerAt = "Limousine in", s.deboardUntil end
			b.buttons = { "leave" }
		elseif s.sub == "self" then
			b.sub = (if s.reason == "TOO_FAR" then "Walk to the VIP stand by the arrivals hall - or to the " .. c .. " tower (beacon)" else "Walk to the " .. c .. " tower - follow the beacon") .. join
			b.action = "Follow the beacon to " .. c
			b.buttons = { "retry", "leave" }
		elseif s.sub == "riding" then
			b.sub = "On Meridian Boulevard" .. (if s.carry and n > 0 then " · " .. names .. " with you" else "") .. join
			b.action = "On the way to " .. c
			b.buttons = { "leave" }
		elseif s.sub == "waiting" then
			b.sub = "The VIP limousine waits at the stand by the arrivals hall" .. join
			b.action = "Get in the limousine at the stand"
			b.buttons = { "leave" }
		else
			b.sub = "The VIP limousine comes to the stand by the arrivals hall" .. join
			if s.eta and s.eta > now then b.timerLabel, b.timerAt = "Limousine in", s.eta end
			b.buttons = { "leave" }
		end
	elseif s.state == "meeting" then
		b.icon = "team"
		b.title = "Meeting · " .. c
		local team = if s.joinAt and s.joinAt > now and n > 0 then " · " .. names .. " arrive " .. IM.clockText(e, now, s.joinAt) elseif n > 0 then " · " .. names .. are .. " with you" else ""
		if s.joined then
			b.sub = "You joined in person: trust +15%. Next: " .. (if abroad then "the limousine to the hotel" else "the City Hotel")
			b.action = "Joined · trust +15%"
		else
			b.sub = "The client team waits in the meeting room - press Start meeting" .. team
			b.action = "Press Start meeting at the table"
		end
		b.buttons = { "leave" }
	elseif s.state == "hotel" then
		b.icon = "desk"
		local hotel = if s.plan then s.plan.hotel else "hotel"
		b.title = s.room or hotel
		if s.room then
			b.sub = (if s.checkedIn then "Checked in" else "Your room is booked at the " .. hotel)
		else
			b.sub = if s.checkedIn then "Checked in · your room is ready" else "Your room is booked - check in at the reception"
		end
		b.action = if s.checkedIn then "Checked in · room ready" elseif s.room then "Your room is ready" else "Check in at the reception"
		if not s.checkedIn and (s.sub == "coming" or s.sub == "queued" or s.sub == "riding" or s.sub == "waiting") then
			b.sub = if s.sub == "riding" then "On the way to the " .. hotel elseif s.sub == "waiting" then "Your car is waiting - it takes you to the " .. hotel else "Your car takes you to the " .. hotel
			b.action = if s.sub == "riding" then "On the way to the hotel" elseif s.sub == "waiting" then "Your car is waiting - get in" else "Your car is coming"
			if s.sub ~= "riding" and s.eta and s.eta > now then b.timerLabel, b.timerAt = "Car there in", s.eta end
		elseif not s.checkedIn and s.sub == "self" and s.reason == "TOO_FAR" then
			b.sub = "Step out to the street: the car picks you up at the kerb"
			b.action = "Step out to the street"
		end
		local p = s.plan
		if p and p.returnAt then
			local back = (if abroad then tostring(p.returnFlight) .. " " else "") .. IM.clockText(e, now, p.returnAt)
			b.sub ..= " · return " .. back
		end
		b.buttons = { "leave" }
	elseif s.state == "return" then
		b.icon = if s.sub == "gate" or s.sub == "flight" then "map" else "driver"
		local staying = if s.stay and n > 0 then " · " .. names .. " stay until the visit ends" else ""
		if not abroad then
			b.title = "Home to the HQ"
			b.sub = (if s.sub == "self" then "No company car - follow the GPS home" else (if driver ~= "" then driver .. " drives you home" else "Your car takes you home")) .. staying
			b.action = if s.sub == "self" then "Follow the GPS home" else "On the way home"
			b.buttons = if s.sub == "self" then { "retry", "cancel" } else { "cancel" }
		elseif s.sub == "gate" then
			b.title = "Gate · " .. (s.flight or "flight home")
			b.sub = (if s.flight == "company jet" then "Our jet waits on the VIP apron" else "Company booking to City Airport")
				.. (if s.stay and n > 0 then staying elseif n > 0 and together then " · " .. names .. " fly with you" else "")
			b.action = if s.flight == "company jet" then "Board our jet on the VIP apron" else "Walk to the gate"
			if s.boardEnd and s.boardEnd > now then b.timerLabel, b.timerAt = "Boarding ends in", s.boardEnd end
			b.buttons = { "cancel" }
		elseif s.sub == "flight" then
			b.title = "Flight to City Airport"
			b.sub = (s.flight or "") .. (if s.arrives then " · lands " .. IM.clockText(e, now, s.arrives) else "") .. (if n > 0 and together and not s.stay then " · " .. names .. " fly with you" else "")
			b.action = if s.arrives then "Lands " .. IM.clockText(e, now, s.arrives) else "In the air"
			b.buttons = {}
		else
			b.title = "Return · City Airport"
			b.sub = (if s.sub == "self" then (if s.reason == "TOO_FAR" then "Step out to the street: the limousine picks you up at the kerb" else "Walk to Port Meridian Airport - follow the beacon")
				elseif s.sub == "waiting" then "The limousine is waiting - it takes you to Port Meridian Airport"
				else "The limousine takes you to Port Meridian Airport") .. (if s.stay and n > 0 then " · " .. names .. " stay" else "")
			b.action = if s.sub == "self" then "Follow the beacon to the airport" elseif s.sub == "waiting" then "Your limousine is waiting - get in" else "Limousine to the airport"
			b.buttons = if s.sub == "self" then { "retry", "cancel" } else { "cancel" }
		end
	elseif s.state == "home" then
		b.title = "Welcome back"
		b.icon = "driver"
		if s.sub == "deboard" then
			b.sub = names .. are .. " getting off the plane - then " .. (if driver ~= "" then driver else "your driver") .. " takes you all to the HQ"
			b.action = "Team getting off the plane"
			if s.deboardUntil and s.deboardUntil > now then b.timerLabel, b.timerAt = "Car in", s.deboardUntil end
		elseif s.sub == "self" then
			b.sub = "No company car - follow the GPS to the HQ"
			b.action = "Follow the GPS to the HQ"
		elseif s.sub == "waiting" then
			b.sub = (if driver ~= "" then driver else "Your driver") .. " is waiting at the arrivals kerb"
			b.action = "Your car is waiting - get in"
		else
			b.sub = if driver ~= "" then driver .. " drives you back to the HQ" else "Your car takes you back to the HQ"
			b.action = if s.sub == "riding" then "On the way to the HQ" else ""
			if s.sub ~= "riding" and s.eta and s.eta > now then b.timerLabel, b.timerAt = "Car there in", s.eta end
		end
		b.buttons = { "cancel" }
	else
		b.title = c
		b.sub = ""
	end
	return b
end
IM.BUTTON_TEXT = { go = "Go", decline = "Not this time", cancel = "Cancel trip", leave = "Fly home now", retry = "Call car now" } :: { [string]: string }
-- One label per action everywhere (call sheet, banner, countdown): "Not this time" declines, "Go now" during the countdown
function IM.buttonText(id: string, tier: string, state: string?): string
	if id == "leave" and tier == "region" then return "Go home now" end
	if id == "go" and state == "countdown" then return "Go now" end
	return IM.BUTTON_TEXT[id] or id
end

------------------------------------------------------------------------------------------------ calendar
export type CalItem = { key: string, title: string, detail: string?, at: number, kind: string }
-- The phone calendar items of a plan: keys "itin:<seq>:<step>" (PhoneService.addCalendarItem, same key replaces)
function IM.calendarItems(plan: Plan, seq: number, e: any, now: number): { CalItem }
	local out: { CalItem } = {}
	local prefix = "itin:" .. seq .. ":"
	local names = IM.namesText(plan.companions)
	local with = if #plan.companions > 0 then " · with " .. names else ""
	-- the car only "with" them when they did not go ahead (field car / staff flight); the meeting "with" them unless
	-- they land after it starts (he started in Port Meridian: joinAt)
	local inCar = if #plan.companions == 0 then "" elseif plan.ahead then " · " .. names .. " went ahead" else with
	local atMeeting = if #plan.companions > 0 and plan.joinAt and plan.meetingAt and plan.joinAt > plan.meetingAt
		then " · " .. names .. " join " .. IM.atText(e, now, plan.joinAt) else with
	local d = plan.driver
	if plan.from == "home" then
		local dest = if plan.tier == "abroad" then "City Airport" else plan.client
		if d and not d.self then
			table.insert(out, { key = prefix .. "pickup", title = "Driver to " .. dest, detail = (if d.name then IM.firstName(d.name) .. " · " else "") .. (d.pickupAt or "the HQ entrance") .. inCar,
				at = plan.pickupAt or now, kind = "trip" })
		else
			table.insert(out, { key = prefix .. "pickup", title = "To " .. dest, detail = "On your own - the GPS shows the way" .. inCar, at = now, kind = "trip" })
		end
	end
	if plan.tier == "abroad" then
		if plan.from == "home" and plan.departs then
			local title = if plan.how == "jet" then "Company jet to Port Meridian" else "Shuttle " .. tostring(plan.flight) .. " to Port Meridian"
			table.insert(out, { key = prefix .. "flight", title = title,
				detail = (if plan.how == "jet" then "Hangar 1" else "City Airport gate A1 · company booking") .. " · lands " .. IM.clockText(e, now, plan.arrives or plan.departs),
				at = plan.departs, kind = "flight" })
		end
		table.insert(out, { key = prefix .. "meeting", title = "Meeting: " .. plan.client, detail = "Port Meridian · " .. plan.client .. " tower · VIP limousine" .. atMeeting, at = plan.meetingAt, kind = "trip" })
		table.insert(out, { key = prefix .. "hotel", title = plan.hotel, detail = "Room booked for you · check in at the reception", at = plan.hotelAt, kind = "item" })
		if plan.returnAt then
			table.insert(out, { key = prefix .. "return", title = "Return: " .. (if plan.returnFlight == "company jet" then "company jet" else "shuttle " .. tostring(plan.returnFlight)),
				detail = "Port Meridian · after the visit ends " .. IM.clockText(e, now, plan.backAt) .. " (or fly home earlier)", at = plan.returnAt, kind = "flight" })
		end
	else
		table.insert(out, { key = prefix .. "meeting", title = "Meeting: " .. plan.client, detail = "Business City · " .. plan.client .. " office" .. with, at = plan.meetingAt, kind = "trip" })
		table.insert(out, { key = prefix .. "hotel", title = plan.hotel, detail = "Room booked for you · check in at the reception", at = plan.hotelAt, kind = "item" })
		if plan.returnAt then
			table.insert(out, { key = prefix .. "return", title = "Driver back to the HQ", detail = "After the visit ends " .. IM.clockText(e, now, plan.backAt) .. " (or earlier)", at = plan.returnAt, kind = "trip" })
		end
	end
	return out
end
IM.CAL_STEPS = { "pickup", "flight", "meeting", "hotel", "return" } :: { string }

------------------------------------------------------------------------------------------------ places
-- The meeting room of a client office (CityPlan.layout: meetingTable; the chairs CityBuilder puts at x -3.5 / 0 /
-- +3.5 and z -4.9 / +4.9 around it): {table (top centre), clients = 2 seat frames on the far side facing the table,
-- near = 3 seat frames on the near side, stand = where the founder stands to press "Start meeting"}
export type MeetingSpot = { table: CFrame, clients: { CFrame }, near: { CFrame }, stand: CFrame, door: CFrame, key: string }
function IM.meetingSpot(key: any): MeetingSpot?
	local d = CityPlan.clientOffice(key)
	if not d or not d.building then return nil end
	local b = d.building :: any
	local l = CityPlan.layout(b)
	local mt = l.meetingTable
	if not mt then return nil end
	local f: CFrame = b.frame
	local seatY = 3.9 -- chair top 2.4 + 1.5 (R6 root above a seat)
	local function seat(dx: number, dz: number, faceDz: number): CFrame
		local p = Vector3.new(mt.X + dx, seatY, mt.Z + dz)
		return f * CFrame.lookAt(p, Vector3.new(mt.X + dx, seatY, mt.Z + dz + faceDz))
	end
	local clients = { seat(-3.5, 4.9, -1), seat(3.5, 4.9, -1) }
	local near = { seat(-3.5, -4.9, 1), seat(0, -4.9, 1), seat(3.5, -4.9, 1) }
	local standP = Vector3.new(mt.X, 3.5, mt.Z - 7.5)
	return { table = f * CFrame.new(mt.X, 3.2, mt.Z), clients = clients, near = near,
		stand = f * CFrame.lookAt(standP, Vector3.new(mt.X, 3.5, mt.Z)), door = d.door, key = d.id }
end
-- The chairs of client team `set` at a meeting table: 1 = the two far chairs, 2 = the outer near chairs (a second
-- founder visiting the same client at the same time), none beyond (the room is full - that team is not drawn).
function IM.seatsFor(spot: MeetingSpot, set: number?): { CFrame }
	local k = math.floor(tonumber(set) or 1)
	if k <= 1 then return spot.clients end
	if k == 2 then return { spot.near[1], spot.near[3] } end
	return {}
end
-- City Airport gate of the shuttle (A1) and Port Meridian's boarding point
function IM.gatePoint(dir: string): Vector3
	if dir == "back" then return FP.PM_GATES[1] end
	return FP.HOME_GATES[1]
end
function IM.inAirport(p: Vector3): boolean
	return CityPlan.inRect(CityPlan.AIRPORT.terminal, p.X, p.Z, IM.AIRPORT_MARGIN)
end
function IM.atGate(p: Vector3, dir: string): boolean
	local g = IM.gatePoint(dir)
	return CityPlan.flat(p, g) <= FP.GATE_RADIUS and math.abs(p.Y - g.Y) < 14
end
function IM.inPMAirport(p: Vector3): boolean
	local A = CityPlan.ABROAD
	return CityPlan.inRect(A.terminal, p.X, p.Z, 14) or CityPlan.inRect(A.plaza, p.X, p.Z, 14)
end
function IM.abroad(p: Vector3): boolean
	return CityPlan.inRect(CityPlan.ABROAD.rect, p.X, p.Z, 60)
end
-- within ARRIVE_RADIUS of the client office's door, lobby or meeting room
function IM.atOffice(p: Vector3, key: any): boolean
	local d = CityPlan.clientOffice(key)
	if not d then return false end
	local list: { any } = { d.door, d.lobby, d.meeting }
	for _, cf in list do
		if typeof(cf) == "CFrame" and CityPlan.flat(p, cf.Position) <= IM.ARRIVE_RADIUS and math.abs(p.Y - cf.Y) < 16 then return true end
	end
	return false
end
function IM.atHotel(p: Vector3, tier: string): boolean
	local h = if tier == "region" then CityPlan.CITY_HOTEL else CityPlan.INTL_HOTEL
	if not h then return false end
	local list: { any } = { h.door, h.lobby, h.reception }
	for _, cf in list do
		if typeof(cf) == "CFrame" and CityPlan.flat(p, cf.Position) <= IM.HOTEL_RADIUS and math.abs(p.Y - cf.Y) < 16 then return true end
	end
	return false
end
-- the hotel reception (fallback "Your room" prompt, GRANDHOTEL_SPEC 18.6: the reception point stays free)
function IM.reception(tier: string): CFrame?
	local h = if tier == "region" then CityPlan.CITY_HOTEL else CityPlan.INTL_HOTEL
	if not h or typeof(h.reception) ~= "CFrame" then return nil end
	return h.reception
end
-- the client office's CityPlan destination id ("helixresearch") of a catalogue client
function IM.officeId(clientName: string): string?
	local d = CityPlan.clientOffice(clientName)
	return if d then d.id else nil
end
-- the two client NPCs waiting in the meeting room: deterministic names + roles from the trip key
function IM.clientTeam(key: string, owner: number, clientName: string): { { name: string, role: string, seed: number, badge: string } }
	local h = 0
	for i = 1, #key do h = (h * 31 + string.byte(key, i)) % 100000 end
	local out = {}
	for g = 1, 2 do
		local name = CampusMath.staffName(9700 + (h + g * 13) % 280, owner)
		table.insert(out, { name = name, role = if g == 1 then "marketer" else "researcher", seed = h * 10 + g + 5, badge = name .. "\n" .. clientName })
	end
	return out
end
-- the stage name where the first company driver joins (honest "no driver yet" texts)
function IM.driverStage(): string
	local o = EmpireConfig.OFFICES[Ops.DRIVER.from]
	return if o then o.name else "the next office"
end

return IM
