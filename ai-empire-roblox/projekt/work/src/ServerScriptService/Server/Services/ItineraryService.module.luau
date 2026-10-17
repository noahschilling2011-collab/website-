--!strict
-- ItineraryService (package "itinerary", LOGIC_BRIEF 24): the founder's business trip. When the economy starts a pilot
-- visit that needs the founder (a field rep's trip abroad - Port Meridian, incl. the frontier clients - or in the region:
-- ItineraryMath.needsFounder), the assistant rings the company phone with the real plan (client, city, the booked
-- shuttle from the FlightPlan timetable or the company jet, the Meridian Grand / City Hotel, the REAL field rep (+
-- engineer) of that trip, the driver - honest when there is none). "Go" (call, banner or TripAction) starts the
-- itinerary; "Not this time" lets the staff travel alone (the economy is the same either way). With the phone setting
-- "Join business trips automatically" (empire.prefs.autoTrips, default off) the trip starts by itself after a
-- COUNTDOWN-second banner with Cancel.
-- State machine per founder (memory only, nothing saved):
--   abroad: pickup (DriverService car to the City Airport departures kerb, the companions in the back) -> airport
--     (company booking ShuttleService.book: no ticket, no check-in; GPS beacon to gate A1 - or our jet,
--     JetService.fly without fuel: CompanyOps charges the trip) -> flight -> limo (DriverService VIP limousine from the
--     stand to the client tower) -> meeting (the client team waits in the meeting room; "Start meeting" is CityService's
--     prompt -> EmpireService.joinMeeting -> trip.joined = +0.15 trust on that visit) -> hotel (room booked: an owner-only
--     "Check in" prompt at the reception, or a hotel provider) -> return (limousine to Port Meridian Airport, company
--     booking home / our jet; pre-booked for the end of the visit, "Fly home now" any time; the companions stay while
--     the visit runs) -> home (the driver from the arrivals kerb back to the HQ).
--   region: pickup (car to the client's Business City office) -> meeting -> hotel (City Hotel) -> return (car home).
-- A free company car is called at a time (sub "scheduled", ItineraryMath.plan requestAt) so he reaches gate A1 shortly
-- after the boarding opened instead of waiting there; "Call car now" calls it at once. After a landing the colleagues
-- walk off the aircraft first (sub "deboard", DEBOARD_WAIT s) before the limousine / the driver is called.
-- Every step is optional: leaving the route, a cancelled car (GPS / beacon instead), dying / respawning, leaving the
-- game or cancelling never touches the economy trip (its CORE_SPEC clock runs on) and never charges anything: no
-- Economy call in this file, the rides and bookings are free, the jet flies without `pay`. Two trips at once: the second
-- is queued and offered when the founder is free (if enough of it is left). A trip that ends while he travels: before
-- the flight the itinerary stops, abroad the return starts.
-- The remote TripAction is bound by DriverService (it owns action = "ride"); every other action is registered with
-- DriverService.onTripAction(action, handler) in init() - never Remote.bind("TripAction", ...) here (it would replace the
-- drivers' handler): go | cancel | leave | status | retry (each its own per-player rate limit in DriverService).
-- Published (written on change only, never per frame):
--   * Notify "ITINERARY" to the founder: the banner (title, line, timer, buttons, progress, beacon target) or {closed};
--   * Player attribute "Itinerary" = the current state (nil = none);
--   * ReplicatedStorage.CompanyItinerary/Itin_<userId> while an itinerary runs: attributes Owner, Company, Tier, State,
--     ClientKey (CityPlan office id), With (the companions walk with the founder now), ShowAt (server time from which
--     they may be shown), MeetingOn (the client team waits in the meeting room; it stays until the founder left the
--     room), SeatSet (which chairs that team takes when two founders visit the same client), Joined; children
--     Companion<i> (the real field rep / engineer) and, from the meeting on, Client<i> (the client team) - rig templates
--     the clients pose (ItineraryController).
--   * holds(userId, tripKey) for ShuttleService (and DriverService / JetService, requests drivers.md #1, guests_jet.md
--     #2): the founder will take this trip's travellers on his own flight - no other leg flies them.
--   * phone: the call (PhoneService.ring kind "itinerary"), calendar items "itin:<seq>:<step>", travel-desk messages.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Prompts = game:GetService("ProximityPromptService")

local Shared = ReplicatedStorage.Shared
local IM = require(Shared.ItineraryMath)
local Ops = require(Shared.CompanyOps)
local Drive = require(Shared.DrivePlan)
local FP = require(Shared.FlightPlan)
local CityPlan = require(Shared.Config.CityPlan)
local CampusMath = require(Shared.CampusMath)
local Remote = require(script.Parent.Parent.Lib.Remote)
local Session = require(script.Parent.SessionService)
local Rig = require(script.Parent.EmployeeRigDesign)
local Plot = require(script.Parent.PlotService)
local City = require(script.Parent.CityService)
local Shuttle = require(script.Parent.ShuttleService)
local Phone = require(script.Parent.PhoneService)
local Driver = require(script.Parent.DriverService)

local ItineraryService = {}
ItineraryService.SCAN = 1 -- seconds between two looks at every company's trips
ItineraryService.STEP = 0.25 -- seconds between two steps of the running itineraries (positional checks)
ItineraryService.RETRY = 3 -- seconds before a refused car request (cooldown / loading) is tried again
ItineraryService.SELF_GIVE_UP = 600 -- a "find your own way" leg is followed this long
ItineraryService.HOME_RADIUS = 70 -- "back at the HQ": within this many studs of the plot
ItineraryService.PROMPT_RANGE = 16
ItineraryService.OFFER_DELAY = 1.5 -- a new trip is offered this long after it started (the field car has left by then)
ItineraryService.AUTO_RETRY = 2 -- seconds between quiet car requests while the founder walks to a pick-up point
ItineraryService.GO_GAP = 2 -- seconds between two started itineraries of one founder (Go / Cancel spam: no folder churn)
ItineraryService.TRIP_CACHE = 0.5 -- seconds a looked-up economy trip is reused by the steps
ItineraryService.STATUS_POLL = 1 -- seconds between two looks at the booked car (DriverService.status; onArrive is immediate)
ItineraryService.PUBLISH_IDLE = 1 -- seconds between two looks at a view that only changes with time (state changes publish at once)
ItineraryService.JET_JOIN_GUESS = 240 -- he started in Port Meridian, the jet has not left with the staff yet: estimate

type Person = IM.Person
type Offer = { key: string, tier: string, client: any, plan: IM.Plan, at: number, countdownEnd: number?, callId: string?, seq: number }
type Rec = {
	s: any, player: Player, ready: boolean, seen: { [string]: boolean }, offer: Offer?, it: any?, queue: { string }, seq: number,
	lastSig: string, lastState: string?, declined: { [string]: boolean }, fresh: { [string]: number }, goAt: number?,
}
local recs: { [number]: Rec } = {}
ItineraryService._recs = recs
local root: Folder? = nil
local promptFolder: Folder? = nil
local Jet: any = nil -- JetService (package guests_jet), optional
local hotelProvider: ((Player, { [string]: any }) -> { [string]: any }?)? = nil
local scanAcc, stepAcc = 0, 0
local promptAt: { [number]: number } = {}

local function now(): number return workspace:GetServerTimeNow() end
local function rootOf(player: Player): (Model?, BasePart?)
	local character = player.Character
	local r = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if character and r and r:IsA("BasePart") then return character, r end
	return nil, nil
end
local function posOf(player: Player): Vector3?
	local _, r = rootOf(player)
	return if r then r.Position else nil
end
-- where the founder stands - nil while a car / flight holds his character (anchored below the road / the stand)
local function standingAt(player: Player): Vector3?
	local _, r = rootOf(player)
	if not r or r.Anchored then return nil end
	return r.Position
end
local function setAttr(inst: Instance, name: string, value: any)
	if inst:GetAttribute(name) ~= value then inst:SetAttribute(name, value) end
end
local function notify(player: Player, kind: string, payload: any)
	pcall(function() Remote.fire(player, "Notify", kind, payload) end)
end
local function notice(player: Player, text: string)
	notify(player, "CAMPUS_NOTICE", { text = text })
end
local function empireOf(s: any): any
	if not s or typeof(s.data) ~= "table" or not s.data.company then return nil end
	local e = s.data.empire
	return if typeof(e) == "table" then e else nil
end
local function message(s: any, title: string, text: string, tone: string?, from: string?)
	pcall(Phone.message, s, { from = from or "Travel desk", title = title, text = text, tone = tone or "info" })
end
local function hotels(): { city: string, abroad: string }
	return { city = if CityPlan.CITY_HOTEL then CityPlan.CITY_HOTEL.name else "City Hotel", abroad = if CityPlan.INTL_HOTEL then CityPlan.INTL_HOTEL.name else "Meridian Grand Hotel" }
end
local function plotIndex(player: Player): number?
	local p = Plot.get(player)
	return if p and typeof(p.index) == "number" then p.index else nil
end
local function zone(player: Player): string
	local st = City.state(player)
	return if st == "abroad" then "abroad" elseif st == "flying" then "flying" else "home"
end
local function companyName(s: any): string
	local c = if s and typeof(s.data) == "table" then s.data.company else nil
	return if typeof(c) == "table" and typeof(c.name) == "string" then c.name else "Company"
end
local function jetModule(): any
	if Jet ~= nil then return if Jet == false then nil else Jet end
	local mod = script.Parent:FindFirstChild("JetService")
	if mod and mod:IsA("ModuleScript") then
		local ok, res = pcall(require, mod)
		if ok and typeof(res) == "table" and typeof(res.fly) == "function" and typeof(res.available) == "function" then Jet = res; return res end
	end
	Jet = false
	return nil
end
local function captainName(userId: number): string?
	local J = jetModule()
	if J and typeof(J.PILOTS) == "table" and typeof(J.PILOTS[1]) == "number" then return CampusMath.staffName(J.PILOTS[1], userId) end
	return nil
end
local function driverName(userId: number, index: number?): string
	local list = (Driver :: any).DRIVERS
	local i = index or 1
	local n = if typeof(list) == "table" and typeof(list[i]) == "number" then list[i] elseif typeof(list) == "table" and typeof(list[1]) == "number" then list[1] else 9301
	return CampusMath.staffName(n, userId)
end
-- the company driver who would take the booking now: the first one without a ride (DriverService publishes the paid
-- drivers and each ride's Driver index in ReplicatedStorage.CompanyDrivers/Drivers_<userId>)
local function freeDriverName(player: Player): string
	local cd = ReplicatedStorage:FindFirstChild("CompanyDrivers")
	local f = if cd then cd:FindFirstChild("Drivers_" .. player.UserId) else nil
	if not f then return driverName(player.UserId, 1) end
	local count = tonumber(f:GetAttribute("Drivers")) or 1
	local busy: { [number]: boolean } = {}
	for _, r in f:GetChildren() do
		local d = r:GetAttribute("Driver")
		if typeof(d) == "number" and d > 0 then busy[d] = true end
	end
	for i = 1, math.max(1, count) do
		if not busy[i] then
			local name = f:GetAttribute("DriverName" .. i)
			return if typeof(name) == "string" then name else driverName(player.UserId, i)
		end
	end
	return driverName(player.UserId, 1)
end
local function recOf(s: any): Rec?
	if not s or not s.player then return nil end
	local rec = recs[s.player.UserId]
	if rec and rec.s == s then return rec end
	return nil
end

------------------------------------------------------------------------------------------------ rigs
-- NPC rig template (no tag, no prompt, no Humanoid, not in workspace = no physics), cloned and posed by the clients
local function template(parent: Instance, owner: number, index: number, role: string, profile: any, name: string, badge: string): Model?
	local temp = Instance.new("Folder")
	local ok, res = pcall(function(): Model
		local m = Rig.build(temp, owner, index, role, CFrame.new(), profile)
		m:RemoveTag("CompanyEmployee")
		local hum = m:FindFirstChildOfClass("Humanoid")
		if hum then hum:Destroy() end
		for _, d in m:GetDescendants() do
			if d:IsA("ProximityPrompt") then d:Destroy()
			elseif d:IsA("BasePart") then d.Anchored = d.Name == "HumanoidRootPart"; d.CanCollide = false; d.CanTouch = false; d.CanQuery = false
			elseif d:IsA("TextLabel") and d.Parent and d.Parent.Name == "EmployeeBadge" then d.Text = badge end
		end
		m.Name = name
		m.Parent = parent
		return m
	end)
	temp:Destroy()
	if not ok then warn("[Itinerary] building a rig failed: " .. tostring(res)); return nil end
	return res
end
local function buildFolder(it: any)
	local r = root
	if not r then return end
	local player: Player = it.player
	local old = r:FindFirstChild("Itin_" .. player.UserId)
	if old then old:Destroy() end
	local f = Instance.new("Folder")
	f.Name = "Itin_" .. player.UserId
	f:SetAttribute("Owner", player.UserId)
	f:SetAttribute("Company", companyName(it.s))
	f:SetAttribute("Tier", it.tier)
	f:SetAttribute("ClientKey", it.office or "")
	f:SetAttribute("Client", it.client.name)
	local company = companyName(it.s)
	for i, p in it.companions do
		local m = template(f, player.UserId, 790 + i, p.role, { n = p.name, s = p.seed }, "Companion" .. i, p.name .. "\n" .. company)
		if m then m:SetAttribute("CompanionName", p.name) end
	end
	f.Parent = r
	it.folder = f
end
-- the client team's templates: built when the meeting step starts (a cancelled trip never replicates them)
local function buildClients(it: any)
	local f: Folder? = it.folder
	if not f or f:FindFirstChild("Client1") then return end
	local player: Player = it.player
	for i, g in IM.clientTeam(it.key, player.UserId, it.client.name) do
		local m = template(f, player.UserId, 9790 + i, g.role, { n = g.name, s = g.seed }, "Client" .. i, g.badge)
		if m then m:SetAttribute("GuestName", g.name) end
	end
end

------------------------------------------------------------------------------------------------ view
-- the economy's trip of this itinerary (looked up at most every TRIP_CACHE s: the step runs 4x per second)
local function tripOf(it: any): any
	local t = now()
	if it.tripAt and t - it.tripAt < ItineraryService.TRIP_CACHE and t >= it.tripAt then return it.trip end
	local e = empireOf(it.s)
	it.trip = if e then IM.findTrip(e, it.key) else nil
	it.tripAt = t
	return it.trip
end
local function tripOver(it: any): boolean
	local trip = tripOf(it)
	return trip == nil or IM.left(empireOf(it.s), trip) <= 0
end
local function snapOf(rec: Rec): IM.Snap?
	local it = rec.it
	if it then
		return { state = it.state, sub = it.sub, tier = it.tier, client = it.client.name, plan = it.plan, companions = it.companions, carry = it.carry,
			together = it.together, stay = it.stay, driver = it.driver, eta = it.eta, flight = it.flight, departs = it.departs, boardEnd = it.boardEnd,
			arrives = it.arrives, gate = it.gate, room = it.room, checkedIn = it.checkedIn, joined = it.joinedAt ~= nil, over = it.over, countdownEnd = nil,
			reason = it.reason, joinAt = it.joinAt, pickupAt = if it.sub == "scheduled" then it.pickupAt else nil, deboardUntil = it.deboardUntil }
	end
	local o = rec.offer
	if o then
		return { state = if o.countdownEnd then "countdown" else "offer", sub = nil, tier = o.tier, client = o.client.name, plan = o.plan, companions = o.plan.companions,
			carry = true, together = true, driver = if o.plan.driver then o.plan.driver.name else nil, flight = o.plan.flight, departs = o.plan.departs,
			countdownEnd = o.countdownEnd, joinAt = o.plan.joinAt }
	end
	return nil
end
-- the beacon the founder's client draws (a point + label) for the current step
local function targetOf(it: any): { [string]: any }?
	local st, sub = it.state, it.sub
	if st == "pickup" and (sub == "self" or sub == "own") then
		local p = if it.tier == "abroad" then Drive.place("airport_departures") else Drive.clientPlace(it.client.name)
		return if p then { pos = p.door.Position, label = if it.tier == "abroad" then "City Airport" else it.client.name } else nil
	elseif st == "airport" and sub == "gate" then
		return { pos = IM.gatePoint("out"), label = "Gate " .. (it.gate or "A1") .. " · " .. (it.flight or "shuttle") }
	elseif st == "limo" then
		if sub == "self" then
			local p = Drive.clientPlace(it.client.name)
			return if p then { pos = p.door.Position, label = it.client.name } else nil
		end
		if sub ~= "riding" then
			local stand = Drive.place("pm_limo")
			return if stand then { pos = stand.door.Position, label = "VIP limousine" } else nil
		end
	elseif st == "meeting" and not it.joinedAt then
		local spot = IM.meetingSpot(it.office or it.client.name)
		return if spot then { pos = spot.table.Position, label = "Start meeting · " .. it.client.name } else nil
	elseif st == "hotel" and not it.checkedIn then
		if it.roomDoor then return { pos = (it.roomDoor :: CFrame).Position, label = it.room or "Your room" } end
		local rc = IM.reception(it.tier)
		return if rc then { pos = rc.Position, label = "Check in · " .. it.plan.hotel } else nil
	elseif st == "return" and it.tier == "abroad" then
		if sub == "gate" then return { pos = IM.gatePoint("back"), label = "Boarding · " .. (it.flight or "flight home") } end
		if sub == "self" then
			local p = Drive.place("pm_airport")
			return if p then { pos = p.door.Position, label = "Port Meridian Airport" } else nil
		end
	end
	return nil
end
local function viewOf(rec: Rec): { [string]: any }
	local snap = snapOf(rec)
	local e = empireOf(rec.s)
	if not snap or not e then return { closed = true } end
	local t = now()
	local b = IM.banner(snap, e, t)
	local it = rec.it
	local buttons: { { id: string, text: string } } = {}
	for _, id in b.buttons do table.insert(buttons, { id = id, text = IM.buttonText(id, snap.tier, snap.state) }) end
	local names: { string } = {}
	for _, p in snap.companions do table.insert(names, IM.firstName(p.name)) end
	return { seq = if it then it.seq elseif rec.offer then rec.offer.seq else 0, state = snap.state, phase = snap.sub, tier = snap.tier, client = snap.client,
		title = b.title, line = b.sub, action = b.action, timerLabel = b.timerLabel, timerAt = b.timerAt, buttons = buttons, icon = b.icon, step = b.step, steps = b.steps,
		stepName = b.stepName,
		target = if it then targetOf(it) else nil, countdownEnd = snap.countdownEnd, companions = names,
		key = if it then it.key elseif rec.offer then rec.offer.key else nil }
end
-- What the view depends on, from the raw state (no texts built): the view is only built and sent when this changes.
-- Clock texts depend on the company day and on whether it is past 08:00 ("05:10 tonight"), timers on what is still
-- ahead - those go in as flags.
local function n0(x: number?): number return if x then math.floor(x) else -1 end
local function signature(rec: Rec, t: number): string
	local e = empireOf(rec.s)
	local clock = if e then Ops.day(e) .. (if Ops.hour(t) % 24 >= 8 then "d" else "n") else "-"
	local it = rec.it
	if it then
		local plan = it.plan
		local flags = (if it.carry then "c" else "") .. (if it.together then "t" else "") .. (if it.stay then "s" else "") .. (if it.checkedIn then "k" else "")
			.. (if it.joinedAt then "j" else "") .. (if it.over then "o" else "") .. (if it.roomDoor then "r" else "")
			.. (if it.boardEnd and it.boardEnd > t then "B" else "") .. (if it.eta and it.eta > t then "E" else "") .. (if it.joinAt and it.joinAt > t then "J" else "")
			.. (if it.deboardUntil and it.deboardUntil > t then "D" else "")
		return "i" .. it.seq .. "|" .. it.state .. "|" .. tostring(it.sub) .. "|" .. tostring(it.reason) .. "|" .. tostring(it.driver) .. "|" .. n0(it.eta)
			.. "|" .. tostring(it.flight) .. "|" .. n0(it.departs) .. "|" .. n0(it.boardEnd) .. "|" .. n0(it.arrives) .. "|" .. tostring(it.gate) .. "|" .. tostring(it.room)
			.. "|" .. flags .. "|" .. n0(plan.returnAt) .. "|" .. n0(it.pickupAt) .. "|" .. n0(it.deboardUntil) .. "|" .. n0(it.joinAt) .. "|" .. clock
	end
	local o = rec.offer
	if o then
		return "o" .. o.seq .. "|" .. n0(o.countdownEnd) .. "|" .. tostring(o.plan.flight) .. "|" .. n0(o.plan.departs) .. "|" .. clock
	end
	return "closed"
end
ItineraryService._signature = signature
local function publish(rec: Rec)
	local player = rec.player
	local sig = signature(rec, now())
	if sig ~= rec.lastSig then
		rec.lastSig = sig
		notify(player, "ITINERARY", viewOf(rec))
	end
	local state = if rec.it then rec.it.state elseif rec.offer then (if rec.offer.countdownEnd then "countdown" else "offer") else nil
	if state ~= rec.lastState then
		rec.lastState = state
		pcall(function() player:SetAttribute("Itinerary", state) end)
	end
	local it = rec.it
	local f = if it then it.folder else nil
	if it and f then
		setAttr(f, "State", it.state)
		setAttr(f, "With", it.with == true)
		setAttr(f, "ShowAt", math.floor((it.showAt or 0) * 10 + 0.5) / 10)
		setAttr(f, "MeetingOn", it.meetingOn == true)
		setAttr(f, "SeatSet", it.seatSet or 1)
		setAttr(f, "Joined", it.joinedAt ~= nil)
	end
end
ItineraryService.view = function(player: Player): { [string]: any }
	local rec = recs[player.UserId]
	return if rec then viewOf(rec) else { closed = true }
end

------------------------------------------------------------------------------------------------ calendar
local function calendar(it: any)
	local e = empireOf(it.s)
	if not e then return end
	for _, item in IM.calendarItems(it.plan, it.seq, e, now()) do
		pcall(Phone.addCalendarItem, it.s, item)
		if not table.find(it.calKeys, item.key) then table.insert(it.calKeys, item.key) end
	end
end
local function clearCalendar(it: any)
	for _, key in it.calKeys do pcall(Phone.removeCalendarItem, it.s, key) end
	table.clear(it.calKeys)
end

------------------------------------------------------------------------------------------------ plan
-- Every company car is out: when the first one is back in the garage (the plans DriverService publishes on each ride
-- folder) + the driver's walk + the way to the pick-up. nil when nothing can be read (the call then says "as soon as
-- it's back" instead of a made-up time).
local function queuedEta(player: Player, pickupId: string, plot: number?): number?
	local cd = ReplicatedStorage:FindFirstChild("CompanyDrivers")
	local f = if cd then cd:FindFirstChild("Drivers_" .. player.UserId) else nil
	if not f then return nil end
	local t = now()
	local soonest = math.huge
	for _, r in f:GetChildren() do
		local d = r:GetAttribute("Driver")
		if typeof(d) ~= "number" or d <= 0 then continue end
		local okD, segs = pcall(Drive.decode, r:GetAttribute("Plan"), plot)
		if not okD or typeof(segs) ~= "table" or #segs == 0 then continue end
		local okE, endAt = pcall(Drive.segEnd, segs[#segs], plot)
		if not okE or typeof(endAt) ~= "number" or endAt ~= endAt then continue end
		-- a founder ride still coming / waiting has no ride leg in its plan yet: its longest wait + a ride on top
		local st = r:GetAttribute("State")
		if st == "coming" or st == "waiting" then endAt += Drive.WAIT + Drive.BOARD_DELAY + 120 end
		soonest = math.min(soonest, endAt)
	end
	if soonest == math.huge then return nil end
	local okL, leg = pcall(function(): any return Drive.leg("hq_garage", pickupId, plot) end)
	local come = if okL and leg then leg.dur else 30
	return math.max(0, soonest - t) + Drive.walkAt(math.max(t, soonest)) + come
end
ItineraryService._queuedEta = queuedEta
-- what the company car can do for the founder right now (honest call text; the real ETA comes with the request)
local function driverInfo(rec: Rec, tier: string, client: any): IM.DriverInfo
	local player = rec.player
	local e = empireOf(rec.s)
	if zone(player) ~= "home" then return { self = true, reason = "ABROAD" } end
	if not e or Drive.drivers(e) <= 0 then return { self = true, reason = "NO_DRIVER" } end
	local plot = plotIndex(player)
	local p = posOf(player)
	local pickup = if p then Drive.nearestPickup(p, "home", plot) else nil
	if not pickup then return { self = true, reason = "TOO_FAR" } end
	local free = Driver.free(player)
	local dest = if tier == "region" then Drive.clientPlace(client.name) else Drive.place("airport_departures")
	local t = now()
	local eta: number? = nil
	local okA, legA = pcall(function(): any return Drive.leg("hq_garage", pickup.id, plot) end)
	if okA and legA then eta = Drive.walkAt(t) + legA.dur end
	local ride: number? = nil
	if dest then
		local destId: string = dest.id
		local okB, legB = pcall(function(): any return Drive.leg(pickup.id, destId, plot) end)
		if okB and legB then ride = legB.dur end
	end
	local queued = free == 0
	return { name = if queued then nil else freeDriverName(player), eta = if queued then queuedEta(player, pickup.id, plot) else eta, ride = ride,
		pickupAt = Drive.atName(pickup), queued = queued, night = not Drive.onPost(t), self = false }
end
-- is a DriverService field car (Kind "field") carrying these people right now? (they then go ahead on their own)
local function fieldCarries(player: Player, people: { Person }): boolean
	local cd = ReplicatedStorage:FindFirstChild("CompanyDrivers")
	local df = if cd then cd:FindFirstChild("Drivers_" .. player.UserId) else nil
	if not df or #people == 0 then return false end
	for _, r in df:GetChildren() do
		if r:GetAttribute("Kind") ~= "field" then continue end
		for _, m in r:GetChildren() do
			local n = m:GetAttribute("CompanionName")
			for _, p in people do if p.name == n then return true end end
		end
	end
	return false
end
-- is the company jet flying (or about to fly) these people out as a field-staff trip?
local function jetTookStaff(player: Player, people: { Person }): boolean
	local J = jetModule()
	if not J or #people == 0 then return false end
	local ok, avail, why, info = pcall(function() return J.available(player) end)
	if not ok or avail == true or why ~= "JET_BUSY" or typeof(info) ~= "table" or info.purpose ~= "staff" or typeof(info.staff) ~= "table" then return false end
	for _, n in info.staff do
		for _, p in people do if p.name == n then return true end end
	end
	return false
end
-- did the travellers of trip `key` already fly out (a shuttle leg of the field-staff rule, or the company jet)?
local function flownAhead(player: Player, key: string): boolean
	local okF, res = pcall(Shuttle.flownAhead, player, key)
	if okF and res == true then return true end
	local J = jetModule()
	if J and typeof(J.staffOf) == "function" then
		local okS, staff = pcall(J.staffOf, player)
		local st = if okS and typeof(staff) == "table" then staff[key] else nil
		if typeof(st) == "table" and (st.state == "out" or st.state == "abroad" or st.state == "wait_back") then return true end
	end
	return false
end
local function jetUsable(player: Player, e: any): boolean
	if not e or e.jet ~= true then return false end
	local J = jetModule()
	if not J then return false end
	local ok, res = pcall(J.available, player)
	return ok and res == true
end
-- He starts in Port Meridian: the companions still fly out from home (ShuttleService's field-staff rule / the company
-- jet's staff flight). When are they at the tower? -> (server time, "PM 101" | "company jet") or nil (already there /
-- nothing flies them: they are simply with him)
local function joinTime(rec: Rec, key: string, companions: { Person }): (number?, string?)
	if #companions == 0 then return nil, nil end
	local player = rec.player
	local e = empireOf(rec.s)
	local t = now()
	local after = IM.WALK_PM + IM.LIMO_SECS
	if e and e.jet == true then
		local J = jetModule()
		if not J or typeof(J.staffOf) ~= "function" then return nil, nil end
		local okS, staff = pcall(J.staffOf, player)
		local st = if okS and typeof(staff) == "table" then staff[key] else nil
		if typeof(st) ~= "table" or (st.state ~= "wait_out" and st.state ~= "out") then return nil, nil end
		if st.state == "out" and typeof(J.status) == "function" then
			local okT, status = pcall(J.status, player)
			if okT and typeof(status) == "table" and typeof(status.arriveAt) == "number" and status.arriveAt > t then return status.arriveAt + after, "company jet" end
		end
		return t + ItineraryService.JET_JOIN_GUESS, "company jet"
	end
	local okE, enabled = pcall(Shuttle.enabled)
	if not okE or enabled ~= true then return nil, nil end
	local okL, dir, cycle = pcall(Shuttle.travellersLeg, player, key)
	local legStart: number
	if okL and dir == "out" and typeof(cycle) == "number" then
		legStart = FP.legStart("out", cycle)
	elseif okL and dir ~= nil then
		return nil, nil
	else
		-- the field-staff rule picks travellers when a boarding starts: an open boarding is too late for them
		local c, ls = FP.nextLeg("out", t)
		if ls < t then ls = FP.legStart("out", c + 1) end
		legStart = ls
	end
	local at = legStart + FP.leg("out").phases.deboarding.t0 + after
	if at <= t then return nil, nil end
	return at, FP.leg("out").flight
end
local function buildPlan(rec: Rec, trip: any, tier: string, driver: IM.DriverInfo?): IM.Plan
	local s = rec.s
	local e = empireOf(s)
	local c = Ops.client(trip.client)
	local from = if zone(rec.player) == "abroad" then "abroad" else "home"
	local jet = tier == "abroad" and from == "home" and jetUsable(rec.player, e)
	local t = now()
	local companions = IM.travellers(e, trip)
	local key = IM.tripKey(trip)
	local aheadBy: string? = nil
	local joinAt, joinFlight = nil, nil
	if from == "home" then
		if tier == "abroad" and (flownAhead(rec.player, key) or jetTookStaff(rec.player, companions)) then aheadBy = "air"
		elseif fieldCarries(rec.player, companions) then aheadBy = "car" end
	elseif tier == "abroad" then
		joinAt, joinFlight = joinTime(rec, key, companions)
	end
	return IM.plan({ tier = tier, client = c.name, clientId = c.id, now = t, backAt = t + IM.left(e, trip), from = from, jet = jet,
		captain = if jet then captainName(rec.player.UserId) else nil, companions = companions, ahead = aheadBy ~= nil, aheadBy = aheadBy,
		driver = if from == "home" then (driver or driverInfo(rec, tier, c)) else nil, hotels = hotels(), joinAt = joinAt, joinFlight = joinFlight })
end

------------------------------------------------------------------------------------------------ offers
local function dropOffer(rec: Rec)
	rec.offer = nil
	publish(rec)
end
local function makeOffer(rec: Rec, key: string, trip: any, tier: string)
	local s = rec.s
	local e = empireOf(s)
	if not e then return end
	local c = Ops.client(trip.client)
	local plan = buildPlan(rec, trip, tier, nil)
	local auto = Phone.setting(s, "autoTrips") == true
	local t = now()
	rec.seq += 1
	local offer: Offer = { key = key, tier = tier, client = c, plan = plan, at = t, countdownEnd = if auto then t + IM.COUNTDOWN else nil, callId = nil, seq = rec.seq }
	rec.offer = offer
	local title, text = IM.callText(plan, e, t, auto)
	if auto then
		message(s, title, text, "info", "Assistant")
	else
		local names: { string } = {}
		for _, p in plan.companions do table.insert(names, IM.firstName(p.name)) end
		local ok, id = pcall(Phone.ring, s, { from = "Assistant", title = title, text = text, kind = "itinerary", accept = "Go", decline = "Not this time",
			data = { key = key, client = c.id, tier = tier, rep = names[1], engineer = names[2] } })
		if ok and typeof(id) == "string" then offer.callId = id end
	end
	publish(rec)
end
local function declineOffer(rec: Rec, key: string?): { [string]: any }
	local o = rec.offer
	local e = empireOf(rec.s)
	local trip = if e and key then IM.findTrip(e, key) elseif e and o then IM.findTrip(e, o.key) else nil
	local people: { Person } = if o then o.plan.companions elseif trip then IM.travellers(e, trip) else {}
	if o and (key == nil or o.key == key) then
		rec.declined[o.key] = true
		dropOffer(rec)
	elseif key then
		rec.declined[key] = true
		local i = table.find(rec.queue, key)
		if i then table.remove(rec.queue, i) end
	end
	return { ok = true, text = IM.declineText(people) }
end

------------------------------------------------------------------------------------------------ steps
local finish: (it: any, reason: string, text: string?) -> ()
local startLimo: (it: any) -> ()
local startMeeting: (it: any) -> ()
local startHotel: (it: any) -> ()
local startReturn: (it: any, why: string) -> ()
local startHome: (it: any, ready: boolean?) -> ()
local toAirport: (it: any) -> ()
local toGateHome: (it: any) -> ()
local onRideArrive: (it: any, rideId: string, placeId: string) -> ()

-- at the client's office: its door / lobby / meeting room (CityPlan) or the kerb where the car drops him (DrivePlan;
-- the Port Meridian towers stand back from the boulevard)
local function atClient(it: any, p: Vector3): boolean
	if IM.atOffice(p, it.office) then return true end
	local place = Drive.clientPlace(it.client.name)
	return place ~= nil and CityPlan.flat(p, place.door.Position) <= IM.ARRIVE_RADIUS and math.abs(p.Y - place.door.Position.Y) < 16
end
-- the companions walk with him (client followers) from now + delay; never before they arrived (joinAt: he started in
-- Port Meridian and they fly out after him)
local function setWith(it: any, on: boolean, delay: number?)
	local t = now()
	it.with = on
	it.showAt = t + (delay or 0)
	if on and it.joinAt and it.joinAt > it.showAt then it.showAt = it.joinAt end
end
local function guide(it: any, dest: string)
	if it.guided == dest then return end
	it.guided = dest
	pcall(City.guide, it.player, dest)
end
-- the companions' visible state after a car dropped them with the founder: DriveController shows them standing at the
-- door for DROP_PAUSE s, then the follower takes over
local function afterDrop(): number
	return (tonumber((Driver :: any).DROP_PAUSE) or 4) + 0.5
end
-- Book the company car for this leg. Returns true when a car (or a queued one) is booked; on refusal the leg turns
-- into "find your own way" (sub "self") with a GPS route at home / a beacon abroad, or a retry after RETRY s.
local function requestRide(it: any, to: string): boolean
	local player: Player = it.player
	local passengers: { Person }? = if it.carry and not it.stay and #it.companions > 0 then it.companions else nil
	local res = Driver.request(player, { to = to, purpose = "itinerary", passengers = passengers,
		onArrive = function(rideId: string, placeId: string) onRideArrive(it, rideId, placeId) end })
	it.rideTo = to
	if res.ok then
		it.rideId = res.rideId
		it.statusAt = 0
		it.selfSince = nil
		it.autoRetryAt = nil
		it.reason = nil
		it.sub = if res.queued then "queued" else "coming"
		it.eta = now() + (tonumber(res.eta) or 0)
		if typeof(res.driver) == "string" then it.driver = res.driver elseif res.queued then it.driver = nil end
		it.retryAt = nil
		return true
	end
	it.rideId = nil
	local err = res.err
	if err == "COOLDOWN" or err == "LOADING" then
		it.sub = "retry"
		it.retryAt = now() + ItineraryService.RETRY
		return false
	end
	if err == "ALREADY_RIDING" then it.sub = "own" else it.sub = "self" end
	it.reason = err
	it.selfSince = it.selfSince or now()
	-- walking towards a pick-up point (inside an office, the hotel lobby ...): asked again quietly every AUTO_RETRY s
	it.autoRetryAt = if err == "TOO_FAR" then now() + ItineraryService.AUTO_RETRY else nil
	return false
end
local function cancelOpenRide(it: any, evenRiding: boolean?)
	local rid = it.rideId
	if not rid then return end
	it.rideId = nil
	local ok, st = pcall(Driver.status, it.player)
	if not ok or typeof(st) ~= "table" then return end
	if st.state == "none" then return end
	if st.state == "riding" and not evenRiding then return end
	if st.rideId == rid or (string.sub(rid, 1, 7) == "queued:" and typeof(st.rideId) == "string") then pcall(Driver.cancel, st.rideId) end
end
local function removePrompt(it: any)
	local p = it.prompt
	it.prompt = nil
	if p then p:Destroy() end
end
local function makePrompt(it: any)
	removePrompt(it)
	local pf = promptFolder
	local rc = IM.reception(it.tier)
	if not pf or not rc then return end
	local player: Player = it.player
	local part = Instance.new("Part")
	part.Name = "ItinRoom_" .. player.UserId
	part.Size = Vector3.new(1, 1, 1)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.CFrame = rc
	local q = Instance.new("ProximityPrompt")
	q.Name = "RoomPrompt"
	q.ActionText = "Check in"
	q.ObjectText = "Your room · " .. it.plan.hotel
	q.MaxActivationDistance = 10
	q.HoldDuration = 0.5
	q.RequiresLineOfSight = false
	q:SetAttribute("OwnerUserId", player.UserId) -- WorldController shows owner prompts only to the owner
	q:SetAttribute("ItinAction", "checkin")
	q.Parent = part
	part.Parent = pf
	it.prompt = part
end

-- the company car / the limousine dropped the founder at `placeId`
onRideArrive = function(it: any, rideId: string, placeId: string)
	local rec = recs[it.player.UserId]
	if not rec or rec.it ~= it then return end
	if it.rideTo ~= placeId then return end
	it.rideId = nil
	it.arrivedAt = placeId
	if it.state == "pickup" then
		if it.tier == "abroad" then toAirport(it) else startMeeting(it) end
	elseif it.state == "limo" then
		startMeeting(it)
	elseif it.state == "hotel" then
		it.sub = "arrived"
		setWith(it, it.together and not it.stay, afterDrop())
		publish(rec)
	elseif it.state == "return" then
		if it.tier == "abroad" then toGateHome(it) else finish(it, "home", "Back at the HQ. " .. it.client.name .. " report will follow from the team.") end
	elseif it.state == "home" then
		finish(it, "home", "Welcome back at the HQ.")
	end
end

-- shuttle / jet out of City Airport (the founder is at the airport)
local function bookShuttle(it: any, to: string): boolean
	local carry = it.together and not it.stay and #it.companions > 0
	local ok, res = pcall(Shuttle.book, it.s, { to = to, companions = if carry then it.companions else nil, trip = if carry then it.key else nil })
	if not ok or typeof(res) ~= "table" or not res.ok then
		local err = if ok and typeof(res) == "table" then res.err else "SERVER_ERROR"
		it.reason = err
		return false
	end
	it.booking = true
	local refunded = tonumber(res.refunded) or 0
	if refunded > 0 then
		message(it.s, "Ticket refunded", "Your seat is a company booking now, so I refunded the counter ticket you bought (" .. Ops.money(refunded) .. ").", "good")
	end
	it.flight = res.flight
	it.departs = res.departs
	it.boardEnd = res.boardingEnds
	it.gate = res.gate
	local dir = if to == "abroad" then "out" else "back"
	local _, _, _, arrives = IM.shuttleLeg(dir, now())
	it.arrives = arrives
	return true
end
local function tryJet(it: any, to: string): string
	local J = jetModule()
	local e = empireOf(it.s)
	if not J or not e or e.jet ~= true then return "NO_JET" end
	local carry = it.together and not it.stay and #it.companions > 0
	local ok, res = pcall(J.fly, it.player, { to = to, companions = if carry then it.companions else nil,
		onArrive = function(_flightId: string, _dest: string)
			local rec = recs[it.player.UserId]
			if rec and rec.it == it then it.jetLanded = true end
		end })
	if not ok or typeof(res) ~= "table" then return "SERVER_ERROR" end
	if res.ok then
		if to == "home" and carry then pcall(Shuttle.travellersHome, it.player, it.key) end
		it.jetFlight = res.flightId
		it.flight = "company jet"
		it.departs = res.departAt
		it.arrives = res.arriveAt
		it.boardEnd = nil
		return "ok"
	end
	if res.err == "RUNWAY_BUSY" and typeof(res.eta) == "number" and res.eta <= IM.JET_WAIT then
		it.retryAt = now() + res.eta
		return "wait"
	end
	return tostring(res.err)
end
local JET_FALLBACK: { [string]: string } = {
	JET_BUSY = "our jet is flying right now", JET_RETURNING = "our jet is on its way home", JET_ABROAD = "our jet waits in Port Meridian",
	PM_STANDS_FULL = "both jet stands in Port Meridian are taken", RUNWAY_BUSY = "the runway is busy for a while", NO_JET = "our jet is not available",
}
toAirport = function(it: any)
	local rec = recs[it.player.UserId]
	if not rec or rec.it ~= it then return end
	cancelOpenRide(it)
	it.state = "airport"
	it.sub = "gate"
	it.guided = nil
	-- from here the companions travel with him unless they already flew out (then they meet him in Port Meridian)
	it.together = it.together and not flownAhead(it.player, it.key)
	it.carry = it.together
	setWith(it, it.together, if it.arrivedAt == "airport_departures" then afterDrop() else 0)
	if it.jet then
		local r = tryJet(it, "abroad")
		if r == "ok" then
			it.state = "flight"
			it.sub = "jet"
			setWith(it, false)
			it.plan.departs, it.plan.arrives = it.departs, it.arrives
			calendar(it)
			publish(rec)
			return
		elseif r == "wait" then
			it.sub = "jetwait"
			publish(rec)
			return
		end
		it.jet = false
		it.plan.how = "shuttle"
		if bookShuttle(it, "abroad") then
			it.plan.flight, it.plan.departs, it.plan.boardEnd, it.plan.arrives = it.flight, it.departs, it.boardEnd, it.arrives
			message(it.s, "Flight changed", "Sorry - " .. (JET_FALLBACK[r] or "our jet is not available") .. ". I booked you on the shuttle " .. tostring(it.flight) .. " "
				.. IM.atText(empireOf(it.s), now(), it.departs) .. " instead (company booking, gate " .. tostring(it.gate) .. ").", "warn")
			calendar(it)
			publish(rec)
			return
		end
	elseif bookShuttle(it, "abroad") then
		it.plan.flight, it.plan.departs, it.plan.boardEnd, it.plan.arrives = it.flight, it.departs, it.boardEnd, it.arrives
		calendar(it)
		publish(rec)
		return
	end
	finish(it, "noflight", "No flight to Port Meridian can be booked right now (" .. tostring(it.reason) .. "). " .. IM.namesText(it.companions) .. " travel without you.")
end

-- the plan follows the real booking: the car's ETA (and a queued car) -> flight, meeting, hotel, return, calendar
local function refit(it: any)
	local d = it.plan.driver
	if not d or not it.rideId or not it.eta or it.state ~= "pickup" then return end
	d.self = false
	d.queued = it.sub == "queued"
	d.eta = math.max(0, it.eta - now())
	if typeof(it.driver) == "string" then d.name = it.driver elseif d.queued then d.name = nil end
	local fresh = IM.plan({ tier = it.tier, client = it.client.name, clientId = it.client.id, now = now(), backAt = it.plan.backAt, from = it.plan.from,
		jet = it.jet, captain = it.plan.captain, companions = it.companions, ahead = it.plan.ahead, aheadBy = it.plan.aheadBy, driver = d, hotels = hotels(),
		schedule = false })
	it.plan = fresh
	it.flight, it.departs, it.boardEnd, it.arrives = fresh.flight, fresh.departs, fresh.boardEnd, fresh.arrives
	it.pickupAt = fresh.pickupAt
	if #it.calKeys > 0 then calendar(it) end
end
-- force: call the car now (Call car now, a respawn) even when the plan has a timed pick-up
local function startPickup(it: any, force: boolean?)
	local rec = recs[it.player.UserId]
	if not rec or rec.it ~= it then return end
	it.state = "pickup"
	it.guided = nil
	it.arrivedAt = nil
	setWith(it, false)
	local p = standingAt(it.player)
	if it.tier == "abroad" then
		if p and IM.inAirport(p) then toAirport(it); return end
	elseif p and atClient(it, p) then
		startMeeting(it); return
	end
	-- a timed pick-up: the car is called at requestAt (the founder keeps working meanwhile)
	if not force and it.requestAt and it.requestAt > now() + 1 then
		cancelOpenRide(it, true)
		it.sub = "scheduled"
		it.reason = nil
		publish(rec)
		return
	end
	it.requestAt = nil
	local dest = if it.tier == "abroad" then "airport_departures" else (Drive.clientPlace(it.client.name) or { id = it.office }).id
	if not requestRide(it, dest) and (it.sub == "self" or it.sub == "own") then
		guide(it, if it.tier == "abroad" then "airport" else it.office)
	end
	refit(it)
	publish(rec)
end

startLimo = function(it: any)
	local rec = recs[it.player.UserId]
	if not rec or rec.it ~= it then return end
	it.state = "limo"
	it.guided = nil
	it.arrivedAt = nil
	it.deboardUntil = nil
	setWith(it, false)
	local p = standingAt(it.player)
	if p and atClient(it, p) then startMeeting(it); return end
	local place = Drive.clientPlace(it.client.name)
	if not place then startMeeting(it); return end
	requestRide(it, place.id)
	if it.sub == "self" or it.sub == "own" then setWith(it, it.together and not it.stay, 0) end
	publish(rec)
end

-- the chairs of this client team: two founders at the same client at once never share them (IM.seatsFor)
local function seatSetFor(it: any): number
	local used: { [number]: boolean } = {}
	for _, r in recs do
		local o = r.it
		if o and o ~= it and o.meetingOn and o.office == it.office and o.seatSet then used[o.seatSet] = true end
	end
	local k = 1
	while used[k] do k += 1 end
	return k
end
startMeeting = function(it: any)
	local rec = recs[it.player.UserId]
	if not rec or rec.it ~= it then return end
	cancelOpenRide(it)
	it.state = "meeting"
	it.sub = nil
	it.guided = nil
	it.deboardUntil = nil
	if not it.meetingOn then it.seatSet = seatSetFor(it) end
	it.meetingOn = true
	it.meetingEnded = nil
	it.spot = it.spot or IM.meetingSpot(it.office or it.client.name)
	buildClients(it)
	-- the team is at the office with him (came along in the car, met him there - or lands later: joinAt)
	setWith(it, true, if it.arrivedAt and it.carry then afterDrop() else 0)
	if not (it.joinAt and it.joinAt > now()) then
		it.together = true -- from the meeting on they are with him (also when they came on their own)
		it.carry = true
	end
	local trip = tripOf(it)
	if trip and trip.joined == true then it.joinedAt = now() end
	publish(rec)
end

startHotel = function(it: any)
	local rec = recs[it.player.UserId]
	if not rec or rec.it ~= it then return end
	it.state = "hotel"
	it.sub = nil
	it.guided = nil
	if it.meetingOn then it.meetingEnded = it.meetingEnded or now() end
	it.arrivedAt = nil
	it.room = nil
	it.roomDoor = nil
	-- a hotel provider (the Meridian Grand rebuild, GRANDHOTEL_SPEC 18.6) takes over the room; else the own marker
	local provider = hotelProvider
	local handled = false
	if provider then
		local ok, res = pcall(provider, it.player, { clientName = it.client.name, companions = it.companions, returnAt = it.plan.returnAt, tier = it.tier })
		if ok and typeof(res) == "table" and res.ok == true then
			handled = true
			local name = if typeof(res.name) == "string" then res.name else nil
			local room = if typeof(res.room) == "string" or typeof(res.room) == "number" then tostring(res.room) else nil
			it.room = if name and room then name .. " " .. room elseif name then name elseif room then "Room " .. room else nil
			if typeof(res.door) == "CFrame" then it.roomDoor = res.door end
		elseif not ok then
			warn("[Itinerary] hotel provider failed: " .. tostring(res))
		end
	end
	if not handled then makePrompt(it) end
	setWith(it, it.together and not it.stay, 0)
	local p = standingAt(it.player)
	if not (p and IM.atHotel(p, it.tier)) then
		requestRide(it, if it.tier == "abroad" then "pm_hotel" else "city_hotel")
		if it.sub == "coming" or it.sub == "queued" then setWith(it, false) end
	end
	publish(rec)
end

startReturn = function(it: any, why: string)
	local rec = recs[it.player.UserId]
	if not rec or rec.it ~= it then return end
	cancelOpenRide(it)
	removePrompt(it)
	local e = empireOf(it.s)
	local over = tripOver(it)
	it.over = over or it.over
	it.stay = not over and #it.companions > 0
	it.state = "return"
	it.sub = nil
	it.guided = nil
	if it.meetingOn then it.meetingEnded = it.meetingEnded or now() end
	it.arrivedAt = nil
	it.deboardUntil = nil
	it.early = why == "early"
	local names = IM.namesText(it.companions)
	if why == "over" then
		message(it.s, "The visit is over", "The " .. it.client.name .. " visit is over. " .. (if it.tier == "abroad" then "The limousine takes you to Port Meridian Airport; your flight home is booked." else "Your car takes you back to the HQ."), "info")
	elseif it.stay then
		local trip = tripOf(it)
		local back = if trip and e then IM.clockText(e, now(), now() + IM.left(e, trip)) else ""
		message(it.s, if it.tier == "abroad" then "Flying home" else "Going home", "Okay. " .. names .. (if #it.companions == 1 then " stays" else " stay") .. " until the visit ends"
			.. (if back ~= "" then " (" .. back .. ")" else "") .. (if it.tier == "abroad" then " and fly" else " and come") .. " home after that.", "info")
	end
	setWith(it, not it.stay and it.together, 0)
	if it.tier == "abroad" then
		local p = standingAt(it.player)
		if p and IM.inPMAirport(p) then toGateHome(it); return end
		requestRide(it, "pm_airport")
		it.sub = if it.sub == "coming" or it.sub == "queued" then "limo" else it.sub
	else
		requestRide(it, "hq_entrance")
		if it.sub == "self" or it.sub == "own" then guide(it, "home") end
	end
	publish(rec)
end

toGateHome = function(it: any)
	local rec = recs[it.player.UserId]
	if not rec or rec.it ~= it then return end
	cancelOpenRide(it)
	it.state = "return"
	it.sub = "gate"
	setWith(it, not it.stay and it.together, if it.arrivedAt == "pm_airport" then afterDrop() else 0)
	local e = empireOf(it.s)
	if e and e.jet == true then
		local r = tryJet(it, "home")
		if r == "ok" then
			it.sub = "flight"
			setWith(it, false)
			publish(rec)
			return
		end
	end
	if not bookShuttle(it, "home") then
		finish(it, "noflight", "No flight home can be booked right now (" .. tostring(it.reason) .. "): check in at the Port Meridian Airport counters - your way back is free.")
		return
	end
	it.plan.returnFlight, it.plan.returnAt = it.flight, it.departs
	calendar(it)
	publish(rec)
end

-- back at City Airport. ready = the colleagues are off the aircraft (after DEBOARD_WAIT s): the driver is called
startHome = function(it: any, ready: boolean?)
	local rec = recs[it.player.UserId]
	if not rec or rec.it ~= it then return end
	it.state = "home"
	it.guided = nil
	it.arrivedAt = nil
	local withThem = it.together and not it.stay and #it.companions > 0
	if not ready and withThem then
		it.sub = "deboard"
		it.deboardUntil = now() + IM.DEBOARD_WAIT
		setWith(it, false)
		message(it.s, "Back at City Airport", "Welcome back! " .. (if it.over then "The " .. it.client.name .. " visit is over. " else "")
			.. IM.namesText(it.companions) .. (if #it.companions == 1 then " is" else " are") .. " getting off the plane - then the car takes you all back to the HQ.", "good")
		it.homeMessage = true
		publish(rec)
		return
	end
	it.sub = nil
	it.deboardUntil = nil
	setWith(it, withThem, 0)
	requestRide(it, "hq_entrance")
	if it.sub == "self" or it.sub == "own" then
		guide(it, "home")
		finish(it, "home", "Welcome back! No company car is free right now - the GPS shows the way to the HQ.")
		return
	end
	-- the car is coming: the colleagues wait at the kerb with the car (DriveController), not behind him
	setWith(it, false)
	if not it.homeMessage then
		local driver = IM.firstName(it.driver)
		message(it.s, "Back at City Airport", "Welcome back! " .. (if it.over then "The " .. it.client.name .. " visit is over. " else "")
			.. (if it.sub == "queued" then "Every company car is out - the next free one picks you up at the arrivals kerb."
				else (if driver ~= "" then driver else "Your driver") .. " picks you up at the arrivals kerb and takes you back to the HQ."), "good")
		it.homeMessage = true
	end
	publish(rec)
end

finish = function(it: any, reason: string, text: string?)
	local player: Player = it.player
	local rec = recs[player.UserId]
	if not rec or rec.it ~= it then return end
	rec.it = nil
	if reason ~= "home" then cancelOpenRide(it) end
	-- an unused company booking of this trip goes (nothing to refund: it was free); a ticket he paid for himself only
	-- loses the trip + the companions (Shuttle.unbook)
	local okB, b = pcall(Shuttle.booking, player)
	if okB and typeof(b) == "table" and (b.trip == it.key or (b.prepaid and b.trip == nil and it.booking)) and City.state(player) ~= "flying" then
		pcall(Shuttle.unbook, player)
	end
	removePrompt(it)
	clearCalendar(it)
	local f = it.folder
	it.folder = nil
	if f then f:Destroy() end
	if text then
		notice(player, text)
		message(it.s, if reason == "home" then "Trip finished" else "Trip ended", text, if reason == "home" then "good" else "info")
	end
	rec.lastSig = ""
	publish(rec)
end

------------------------------------------------------------------------------------------------ go
local function newIt(rec: Rec, key: string, trip: any, tier: string, plan: IM.Plan): any
	local c = Ops.client(trip.client)
	rec.seq += 1
	local player = rec.player
	local companions = plan.companions
	-- carry: the companions ride in the founder's car (not when a field car already took them);
	-- together: they fly with him (not when they already flew out on the field-staff shuttle leg / the jet)
	local ahead = flownAhead(player, key)
	local carry = not fieldCarries(player, companions) and not ahead and plan.from == "home"
	-- he starts in Port Meridian: they are with him once they landed (joinAt) or right away when nothing flies them
	local together = not ahead and (plan.from == "home" or plan.joinAt == nil)
	return { rec = rec, s = rec.s, player = player, seq = rec.seq, key = key, tier = tier, client = c, office = IM.officeId(c.name), plan = plan,
		companions = companions, carry = carry, together = together, stay = false, over = false, state = "booked", sub = nil, character = player.Character,
		rideId = nil, rideTo = nil, arrivedAt = nil, retryAt = nil, eta = nil, jet = plan.how == "jet", flight = plan.flight, departs = plan.departs,
		boardEnd = plan.boardEnd, arrives = plan.arrives, gate = nil, joinedAt = nil, checkedIn = false, room = nil, roomDoor = nil, prompt = nil,
		folder = nil, with = false, showAt = 0, meetingOn = false, guided = nil, calKeys = {}, started = now(), driver = if plan.driver then plan.driver.name else nil,
		reason = nil, early = false, booking = false, jetFlight = nil, jetLanded = false, selfSince = nil, missed = 0,
		requestAt = plan.requestAt, pickupAt = plan.pickupAt, joinAt = plan.joinAt, deboardUntil = nil, seatSet = nil, spot = nil, meetingEnded = nil,
		homeMessage = false }
end
-- The assistant's call is answered once the trip runs (Go on the banner / countdown): PhoneService.endCall(session, id)
-- when the phone package has it (design/requests/phone.md); until then a late answer of that call is handled in phoneHook.
local function endCall(rec: Rec, o: Offer?)
	local id = if o then o.callId else nil
	local fn = (Phone :: any).endCall
	if id and typeof(fn) == "function" then pcall(fn, rec.s, id) end
end
local function go(rec: Rec, key: string?, how: string): { [string]: any }
	local s = rec.s
	local e = empireOf(s)
	if not e then return { ok = false, err = "NO_COMPANY" } end
	local o = rec.offer
	local k = key or (if o then o.key else nil)
	if not k then return { ok = false, err = "NO_TRIP", text = "There is no trip to join right now." } end
	if rec.it then
		if rec.it.key == k then return { ok = true, text = "You're already on your way to " .. rec.it.client.name .. "." } end
		return { ok = false, err = "ALREADY_TRAVELLING", text = "You're already on a business trip." }
	end
	local trip = IM.findTrip(e, k)
	local need, tier = IM.needsFounder(trip)
	if not trip or not need or not tier or IM.left(e, trip) <= 0 then
		if o and o.key == k then dropOffer(rec) end
		return { ok = false, err = "TRIP_OVER", text = "That visit is already over." }
	end
	local where: string = zone(rec.player)
	local fromAbroad = where == "abroad"
	if where == "flying" then return { ok = false, err = "FLYING", text = "You're in the air - I'll ask again when you've landed." } end
	local t0 = now()
	if rec.goAt and t0 - rec.goAt < ItineraryService.GO_GAP and t0 >= rec.goAt then return { ok = false, err = "RATE_LIMIT", text = "One moment please." } end
	if tier == "region" and fromAbroad then return { ok = false, err = "ABROAD", text = "You're in Port Meridian - this meeting is in Business City." } end
	local offered = if o and o.key == k then o else nil
	if offered then rec.offer = nil end
	local i = table.find(rec.queue, k)
	if i then table.remove(rec.queue, i) end
	rec.goAt = t0
	local plan = buildPlan(rec, trip, tier, nil)
	local it = newIt(rec, k, trip, tier, plan)
	rec.it = it
	buildFolder(it)
	endCall(rec, offered)
	if tier == "abroad" and fromAbroad then
		startLimo(it)
	else
		startPickup(it) -- (the real ETA of the booked car goes into the plan: refit)
	end
	if rec.it ~= it then return { ok = true, text = "Trip started." } end
	calendar(it)
	publish(rec)
	local t = now()
	local driver = IM.firstName(it.driver)
	local first = if it.state == "pickup" then (
			if it.sub == "self" or it.sub == "own" then IM.driverText({ self = true, reason = it.reason }, tier)
			elseif it.sub == "scheduled" and it.pickupAt then (if driver ~= "" then driver else "Your driver") .. " picks you up " .. IM.atText(e, t, it.pickupAt) .. "."
			elseif it.sub == "queued" then "Every car is out: the next free one picks you up" .. (if it.eta and it.eta > t + 1 then " in about " .. IM.mmss(it.eta - t) else " as soon as it's back") .. "."
			else (if driver ~= "" then driver .. " brings the car round." else "Your car is on its way."))
		elseif it.state == "limo" then "The VIP limousine is on its way." else "Have a good trip!"
	if how == "auto" then message(s, "On your way to " .. it.client.name, first, "info") end
	return { ok = true, text = "Booked - have a good trip! " .. first }
end
ItineraryService._go = go

------------------------------------------------------------------------------------------------ the loop
local function onNewTrip(rec: Rec, key: string, trip: any, tier: string)
	local busy = rec.it ~= nil or rec.offer ~= nil or zone(rec.player) == "flying" or (tier == "region" and zone(rec.player) ~= "home")
	if busy then
		if not table.find(rec.queue, key) and not (rec.it and rec.it.key == key) and not (rec.offer and rec.offer.key == key) then table.insert(rec.queue, key) end
		return
	end
	makeOffer(rec, key, trip, tier)
end
local function scan(rec: Rec)
	local e = empireOf(rec.s)
	if not e then return end
	local deals = e.deals
	local list = if typeof(deals) == "table" and typeof(deals.tripList) == "table" then deals.tripList else {}
	local current: { [string]: any } = {}
	for _, t in list do
		if IM.needsFounder(t) then current[IM.tripKey(t)] = t end
	end
	if not rec.ready then
		-- first look after loading: trips already under way stay staff work
		rec.ready = true
		for k in current do rec.seen[k] = true end
		return
	end
	local t0 = now()
	for k in current do
		if not rec.seen[k] and not rec.fresh[k] then rec.fresh[k] = t0 end
	end
	-- a new trip is looked at OFFER_DELAY s after it started: DriverService's field car (if any) has left by then, so the
	-- call names the free driver and says honestly whether the team rides along
	for k, at in rec.fresh do
		local t = current[k]
		if not t then rec.fresh[k] = nil; continue end
		if t0 - at < ItineraryService.OFFER_DELAY then continue end
		rec.fresh[k] = nil
		rec.seen[k] = true
		local _, tier = IM.needsFounder(t)
		if tier then onNewTrip(rec, k, t, tier) end
	end
	for k in rec.seen do if not current[k] then rec.seen[k] = nil; rec.declined[k] = nil end end
	-- a queued trip is offered once the founder is free (if it still runs long enough)
	if not rec.it and not rec.offer and #rec.queue > 0 and zone(rec.player) ~= "flying" then
		local keep: { string } = {}
		local offered = false
		for _, k in rec.queue do
			local t = current[k]
			if offered then
				table.insert(keep, k)
			elseif t and not rec.declined[k] and IM.left(e, t) >= IM.QUEUE_MIN_LEFT then
				local _, tier = IM.needsFounder(t)
				if tier and tier == "region" and zone(rec.player) ~= "home" then
					table.insert(keep, k) -- a Business City meeting waits until he is back home
				elseif tier then
					makeOffer(rec, k, t, tier)
					offered = true
				end
			end
		end
		rec.queue = keep
	end
end

local function stepOffer(rec: Rec, t: number)
	local o = rec.offer
	if not o then return end
	local e = empireOf(rec.s)
	local trip = if e then IM.findTrip(e, o.key) else nil
	if not trip or IM.left(e, trip) <= 0 or t - o.at > IM.OFFER_TTL then dropOffer(rec); return end
	if o.countdownEnd and t >= o.countdownEnd then
		local res = go(rec, o.key, "auto")
		if not res.ok then
			if rec.offer == o then dropOffer(rec) end
			if typeof(res.text) == "string" then notice(rec.player, res.text) end
		end
	end
end

local function stepIt(rec: Rec, it: any, t: number)
	local player = rec.player
	local e = empireOf(rec.s)
	if not e then return end
	-- what the published state is made of before this step (a change below is published at once)
	local was = it.state .. "|" .. tostring(it.sub)
	local wasJoined, wasMeeting, wasWith, wasShow, wasEta, wasFlight, wasArr = it.joinedAt, it.meetingOn, it.with, it.showAt, it.eta, it.flight, it.arrives
	-- respawn: CityService puts a new character at home
	if player.Character ~= it.character then
		it.character = player.Character
		if zone(player) == "home" then
			if it.state == "pickup" or it.state == "airport" then
				-- the car he rode in drives on with the colleagues (DriverService: a ride whose rider respawned ends its
				-- leg): they wait for him at the airport / the office; his new car comes for him alone
				local carried = it.state == "pickup" and it.sub == "riding" and it.carry and #it.companions > 0
				if carried then it.carry = false end
				it.rideId = nil
				notice(player, "You're back at the HQ - your trip to " .. it.client.name .. " is still on." .. (if carried then " " .. IM.namesText(it.companions)
					.. (if #it.companions == 1 then " rides" else " ride") .. " on and" .. (if #it.companions == 1 then " waits" else " wait") .. " for you there." else ""))
				startPickup(it)
				return
			elseif it.state == "home" or (it.tier == "region" and it.state == "return") then
				finish(it, "home", "Welcome back at the HQ.")
				return
			else
				finish(it, "respawn", "You're back at the HQ. The " .. it.client.name .. " visit continues without you - " .. IM.namesText(it.companions) .. " will report.")
				return
			end
		end
	end
	local p = standingAt(player)
	local where = zone(player)
	-- the economic trip ended while the founder travels
	if not it.over and tripOver(it) then
		it.over = true
		if it.state == "pickup" or it.state == "airport" then
			finish(it, "over", "The " .. it.client.name .. " visit is over - no need to travel any more.")
			return
		elseif it.state == "limo" or it.state == "meeting" or it.state == "hotel" then
			startReturn(it, "over")
			return
		end
	end
	-- he started in Port Meridian: from joinAt on the colleagues are with him (they landed and came to the tower)
	if it.joinAt and t >= it.joinAt then
		it.joinAt = nil
		it.together = true
		it.carry = true
		publish(rec)
	end
	-- the client team stays at the table until he left the meeting room (or MEETING_LINGER s after the meeting step)
	if it.meetingOn and it.state ~= "meeting" then
		local spot = it.spot
		local tp = if spot then spot.table.Position else nil
		if not tp or not p or CityPlan.flat(p, tp) > IM.MEETING_ROOM or math.abs(p.Y - tp.Y) > 14 or t - (it.meetingEnded or t) > IM.MEETING_LINGER then
			it.meetingOn = false
		end
	end
	-- the meeting can be joined at any step (CityService prompt / DealAction): the itinerary follows
	if not it.joinedAt then
		local trip = tripOf(it)
		if trip and trip.joined == true then
			it.joinedAt = t
			publish(rec)
		end
	end
	-- a refused request is tried again
	if it.retryAt and t >= it.retryAt then
		it.retryAt = nil
		if it.state == "pickup" then startPickup(it); return
		elseif it.state == "limo" then startLimo(it); return
		elseif it.state == "airport" then toAirport(it); return
		elseif it.state == "hotel" then requestRide(it, if it.tier == "abroad" then "pm_hotel" else "city_hotel")
		elseif it.state == "return" then startReturn(it, "retry"); return
		elseif it.state == "home" then startHome(it); return end
	end
	-- walking to a pick-up point: the car is asked for again quietly
	if it.autoRetryAt and t >= it.autoRetryAt and not it.rideId and it.rideTo and where ~= "flying" then
		it.autoRetryAt = nil
		if requestRide(it, it.rideTo) then
			if it.state == "hotel" or it.state == "limo" or it.state == "return" then setWith(it, false) end
			publish(rec)
		end
	end
	-- nobody found the way for a long time: the itinerary lets go (no harm: the economy trip runs on)
	if (it.sub == "self" or it.sub == "own") and it.selfSince and t - it.selfSince > ItineraryService.SELF_GIVE_UP
		and (it.state == "home" or (it.state == "return" and it.tier == "region")) then
		finish(it, "home", "Have a good day!")
		return
	end
	-- the booked car: follow its state (coming / waiting / riding); gone without the founder -> find his own way
	if it.rideId and where ~= "flying" and t >= (it.statusAt or 0) then
		it.statusAt = t + ItineraryService.STATUS_POLL
		local ok, st = pcall(Driver.status, player)
		if ok and typeof(st) == "table" then
			local state = st.state
			if state == "none" then
				it.rideId = nil
				if it.state == "pickup" or it.state == "limo" or (it.state == "return" and it.sub ~= "gate") or it.state == "home" or it.state == "hotel" then
					it.sub = "self"
					it.selfSince = t
					if it.state == "pickup" then guide(it, if it.tier == "abroad" then "airport" else it.office)
					elseif it.state == "return" and it.tier ~= "abroad" or it.state == "home" then guide(it, "home") end
					if it.state ~= "hotel" then setWith(it, it.together and not it.stay and it.state ~= "pickup", 0) end
					notice(player, "Your car has left. " .. (if where == "abroad" then "Follow the beacon." else "Follow the GPS - or press Call car."))
				end
			elseif state == "coming" or state == "waiting" or state == "riding" or state == "queued" then
				if typeof(st.rideId) == "string" then it.rideId = st.rideId end
				local sub = if state == "queued" then "queued" elseif state == "riding" then "riding" elseif state == "waiting" then "waiting" else "coming"
				if it.state == "return" and it.tier == "abroad" and (sub == "coming" or sub == "queued") then sub = "limo" end
				if sub ~= it.sub then
					it.sub = sub
					if typeof(st.eta) == "number" then it.eta = t + st.eta end
				elseif typeof(st.eta) == "number" and state ~= "riding" and math.abs((it.eta or 0) - (t + st.eta)) > 4 then
					it.eta = t + st.eta
				end
				if typeof(st.driverName) == "string" then it.driver = st.driverName end
			end
		end
	end
	local s = it.state
	if s == "pickup" then
		if p and it.tier == "abroad" and where == "home" and IM.inAirport(p) then toAirport(it); return end
		if p and it.tier == "region" and atClient(it, p) then startMeeting(it); return end
		-- the timed pick-up: the car is called now
		if it.sub == "scheduled" and (not it.requestAt or t >= it.requestAt) then startPickup(it, true); return end
		if (it.sub == "self" or it.sub == "own") and it.selfSince and t - it.selfSince > ItineraryService.SELF_GIVE_UP then
			finish(it, "late", "You didn't make it to " .. (if it.tier == "abroad" then "City Airport" else it.client.name) .. " - " .. IM.namesText(it.companions) .. " travel without you.")
			return
		end
	elseif s == "airport" then
		if where == "flying" then
			local trip: any = City.trips[player.UserId]
			it.state = "flight"
			it.sub = if trip and trip.kind == "jet" then "jet" else "shuttle"
			setWith(it, false)
			if trip and typeof(trip.leg) == "string" then
				local cycle = tonumber(string.match(trip.leg, ":(%-?%d+)$"))
				if cycle then it.arrives = FP.legStart("out", cycle) + FP.leg("out").phases.deboarding.t0 end
			end
			publish(rec)
			return
		elseif where == "abroad" then
			startLimo(it); return
		elseif it.sub == "gate" and it.boardEnd and t > it.boardEnd + 1 then
			-- missed the leg: the company booking is valid for the next one
			local flight, departs, boardEnd, arrives = IM.shuttleLeg("out", t)
			it.missed += 1
			it.flight, it.departs, it.boardEnd, it.arrives = flight, departs, boardEnd, arrives
			it.plan.flight, it.plan.departs, it.plan.boardEnd, it.plan.arrives = flight, departs, boardEnd, arrives
			message(rec.s, "Booking moved", "You missed the shuttle - your company booking moves to " .. flight .. " " .. IM.atText(e, t, departs) .. " (gate " .. tostring(it.gate) .. ").", "warn")
			calendar(it)
		end
		-- he left the airport before boarding: the booking stays, the beacon too
	elseif s == "flight" then
		if where == "abroad" and it.sub ~= "home" then
			local withThem = it.together and not it.stay and #it.companions > 0
			message(rec.s, "Arrived in Port Meridian", "Welcome to Port Meridian! " .. (if it.over then "The visit is already over - your flight home is booked."
				else "The VIP limousine is waiting at the stand next to the arrivals hall - it takes you" .. (if withThem then " all" else "") .. " to " .. it.client.name .. "."), "good")
			if it.over then
				setWith(it, withThem, 0)
				startReturn(it, "over")
			elseif withThem then
				-- the colleagues walk off the aircraft first (ShuttlePassengers / the jet's airstair), then the limousine
				it.state = "limo"
				it.sub = "deboard"
				it.guided = nil
				it.deboardUntil = t + IM.DEBOARD_WAIT
				setWith(it, false)
				publish(rec)
			else
				startLimo(it)
			end
			return
		elseif where == "home" and not (City.trips[player.UserId]) and it.jetFlight == nil then
			-- the flight ended without him (respawn handled above; a dropped ride)
			startPickup(it)
			return
		end
	elseif s == "limo" then
		if p and atClient(it, p) then startMeeting(it); return end
		if it.sub == "deboard" and t >= (it.deboardUntil or 0) then startLimo(it); return end
		if it.sub == "self" and p and IM.inPMAirport(p) and not it.retryAt and it.selfSince and t - it.selfSince > 20 then
			it.selfSince = t
			startLimo(it)
			return
		end
	elseif s == "meeting" then
		if it.joinedAt and t - it.joinedAt >= IM.MEETING_TALK then startHotel(it); return end
	elseif s == "hotel" then
		if p and it.sub ~= "riding" and it.sub ~= "arrived" and IM.atHotel(p, it.tier) and it.rideId == nil then it.sub = "arrived" end
	elseif s == "return" then
		if it.tier == "abroad" then
			if (it.sub == "limo" or it.sub == "self" or it.sub == "own" or it.sub == "coming" or it.sub == "queued" or it.sub == "waiting" or it.sub == nil) and p and where == "abroad" and IM.inPMAirport(p) then
				toGateHome(it); return
			end
			if it.sub == "gate" and where == "flying" then
				it.sub = "flight"
				setWith(it, false)
				local trip: any = City.trips[player.UserId]
				if trip and typeof(trip.leg) == "string" then
					local cycle = tonumber(string.match(trip.leg, ":(%-?%d+)$"))
					if cycle then it.arrives = FP.legStart("back", cycle) + FP.leg("back").phases.deboarding.t0 end
				end
				publish(rec)
				return
			end
			if it.sub == "gate" and it.boardEnd and t > it.boardEnd + 1 and where == "abroad" then
				local flight, departs, boardEnd, arrives = IM.shuttleLeg("back", t)
				it.flight, it.departs, it.boardEnd, it.arrives = flight, departs, boardEnd, arrives
				it.plan.returnFlight, it.plan.returnAt = flight, departs
				calendar(it)
			end
			if it.sub == "flight" and where == "home" then startHome(it); return end
		else
			if p and it.sub ~= "riding" then
				local idx = plotIndex(player)
				local info = if idx then CityPlan.plots()[idx] else nil
				if info and CityPlan.inRect(info.rect, p.X, p.Z, ItineraryService.HOME_RADIUS) and it.rideId == nil then finish(it, "home", "Back at the HQ."); return end
			end
		end
	elseif s == "home" then
		if it.sub == "deboard" and t >= (it.deboardUntil or 0) then startHome(it, true); return end
		if p and it.sub ~= "riding" and it.rideId == nil then
			local idx = plotIndex(player)
			local info = if idx then CityPlan.plots()[idx] else nil
			if info and CityPlan.inRect(info.rect, p.X, p.Z, ItineraryService.HOME_RADIUS) then finish(it, "home", "Welcome back at the HQ."); return end
		end
	end
	-- something changed this step: published now; else the view only moves with time (timers, "tonight"): once a second
	local changed = rec.it == it and (it.state .. "|" .. tostring(it.sub) ~= was or it.joinedAt ~= wasJoined or it.meetingOn ~= wasMeeting or it.with ~= wasWith
		or it.showAt ~= wasShow or it.eta ~= wasEta or it.flight ~= wasFlight or it.arrives ~= wasArr)
	if changed or t >= (it.pubAt or 0) then
		it.pubAt = t + ItineraryService.PUBLISH_IDLE
		publish(rec)
	end
end

------------------------------------------------------------------------------------------------ player actions
local function cancel(rec: Rec): { [string]: any }
	if rec.offer then return declineOffer(rec, nil) end
	local it = rec.it
	if not it then return { ok = false, err = "NO_TRIP" } end
	local abroad = zone(rec.player) == "abroad"
	finish(it, "cancelled", "Trip cancelled. " .. IM.namesText(it.companions) .. " carry on without you."
		.. (if abroad then " Your way home is free: check in at Port Meridian Airport." else ""))
	return { ok = true }
end
local function leave(rec: Rec): { [string]: any }
	local it = rec.it
	if not it then return { ok = false, err = "NO_TRIP" } end
	local s = it.state
	if s == "limo" or s == "meeting" or s == "hotel" then
		startReturn(it, "early")
		return { ok = true }
	elseif s == "flight" then
		return { ok = false, err = "FLYING", text = "You're in the air." }
	elseif s == "return" or s == "home" then
		return { ok = true }
	end
	return cancel(rec)
end
local function retry(rec: Rec): { [string]: any }
	local it = rec.it
	if not it then return { ok = false, err = "NO_TRIP" } end
	if it.rideId then return { ok = false, err = "ALREADY_RIDING" } end
	if it.state == "pickup" then startPickup(it, true)
	elseif it.state == "limo" then startLimo(it)
	elseif it.state == "return" and it.sub ~= "gate" and it.sub ~= "flight" then startReturn(it, "retry")
	elseif it.state == "home" then startHome(it)
	else return { ok = false, err = "BAD_INPUT" } end
	return { ok = it.rideId ~= nil, err = if it.rideId then nil else it.reason }
end
ItineraryService.cancel = function(player: Player): { [string]: any }
	local rec = recs[player.UserId]
	return if rec then cancel(rec) else { ok = false, err = "NO_TRIP" }
end
ItineraryService.leave = function(player: Player): { [string]: any }
	local rec = recs[player.UserId]
	return if rec then leave(rec) else { ok = false, err = "NO_TRIP" }
end
ItineraryService.go = function(player: Player, key: string?): { [string]: any }
	local rec = recs[player.UserId]
	return if rec then go(rec, key, "api") else { ok = false, err = "LOADING" }
end
-- TripAction {action = go | cancel | leave | status | retry, key?} (registered with DriverService.onTripAction)
local function tripAction(s: any, p: any): { [string]: any }
	local rec = recOf(s)
	if not rec then return { ok = false, err = "LOADING" } end
	local action = p.action
	if p.key ~= nil and IM.validKey(p.key) == nil then return { ok = false, err = "BAD_INPUT" } end
	local key = IM.validKey(p.key)
	if action == "go" then return go(rec, key, "banner")
	elseif action == "cancel" then return cancel(rec)
	elseif action == "leave" then return leave(rec)
	elseif action == "retry" then return retry(rec)
	elseif action == "status" then
		local v = viewOf(rec)
		return { ok = true, view = v, state = v.state or "none" }
	end
	return { ok = false, err = "BAD_INPUT" }
end
ItineraryService._tripAction = tripAction
-- PhoneService.onAction("itinerary"): the founder answered the assistant's call
local function phoneHook(s: any, payload: any): { [string]: any }
	local rec = recOf(s)
	if not rec then return { ok = false, err = "LOADING" } end
	local data = if typeof(payload) == "table" and typeof(payload.data) == "table" then payload.data else {}
	local key = IM.validKey(data.key)
	if payload.answer == "accept" then
		local res = go(rec, key, "phone")
		if not res.ok and typeof(res.text) == "string" then return { ok = true, text = res.text } end
		return res
	end
	-- a late "Not this time" on a call whose trip already runs (Go on the banner / the countdown): nothing changes
	local it = rec.it
	if it and (key == nil or it.key == key) then
		return { ok = true, text = "You're already on your way to " .. it.client.name .. " - use Cancel trip in the banner if you'd rather stay." }
	end
	return declineOffer(rec, key)
end
ItineraryService._phoneHook = phoneHook

------------------------------------------------------------------------------------------------ public
-- The hotel's room for the hotel step (GRANDHOTEL_SPEC 18.6): fn(player, {clientName, companions, returnAt, tier}) ->
-- {ok = true, room?, name?, door: CFrame?} | nil. nil clears it. Called in a pcall; a failure keeps the own marker.
function ItineraryService.setHotelProvider(fn: ((Player, { [string]: any }) -> { [string]: any }?)?)
	hotelProvider = fn
end
-- A read-only copy of the founder's itinerary (tests, other packages)
function ItineraryService.state(player: Player): { [string]: any }?
	local rec = recs[player.UserId]
	if not rec then return nil end
	local it = rec.it
	if it then
		return { state = it.state, sub = it.sub, key = it.key, tier = it.tier, client = it.client.name, carry = it.carry, stay = it.stay, over = it.over,
			with = it.with, showAt = it.showAt, meetingOn = it.meetingOn, joined = it.joinedAt ~= nil, checkedIn = it.checkedIn, rideId = it.rideId,
			flight = it.flight, departs = it.departs, boardEnd = it.boardEnd, arrives = it.arrives, jet = it.jet, room = it.room, companions = it.companions,
			plan = it.plan, seq = it.seq, calKeys = table.clone(it.calKeys), reason = it.reason, queue = table.clone(rec.queue), together = it.together,
			requestAt = it.requestAt, pickupAt = it.pickupAt, joinAt = it.joinAt, deboardUntil = it.deboardUntil, seatSet = it.seatSet, eta = it.eta,
			driver = it.driver }
	end
	local o = rec.offer
	if o then return { state = if o.countdownEnd then "countdown" else "offer", key = o.key, tier = o.tier, client = o.client.name, plan = o.plan, callId = o.callId,
		countdownEnd = o.countdownEnd, queue = table.clone(rec.queue) } end
	return { state = "none", queue = table.clone(rec.queue) }
end
-- For DriverService (design/requests/drivers.md, itinerary section): the founder travels on this trip himself
-- (its field rep + engineer ride in his car) / the assistant's offer for it is still open (ask again in a moment).
-- tripKey = client..":"..left (the key the services share).
function ItineraryService.claims(userId: number, tripKey: string): boolean
	local rec = recs[userId]
	return rec ~= nil and rec.it ~= nil and rec.it.key == tripKey
end
function ItineraryService.pending(userId: number, tripKey: string): boolean
	local rec = recs[userId]
	if not rec or not rec.ready then return false end
	if rec.fresh[tripKey] ~= nil then return true end
	if rec.offer ~= nil then return rec.offer.key == tripKey end
	-- a new trip the scan has not looked at yet: it is offered OFFER_DELAY s after it started (unless he is busy)
	if rec.it ~= nil or rec.seen[tripKey] or zone(rec.player) == "flying" then return false end
	local e = empireOf(rec.s)
	local need, tier = IM.needsFounder(if e then IM.findTrip(e, tripKey) else nil)
	return need == true and (tier == "abroad" or zone(rec.player) == "home")
end
-- For DriverService (requests/itinerary.md #1): the founder's own car carries this trip's travellers now / brings them
-- home (no field ride out, no field ride back) - he said Go, they ride with him and do not stay behind.
function ItineraryService.carries(userId: number, tripKey: string): boolean
	local rec = recs[userId]
	local it = if rec then rec.it else nil
	return it ~= nil and it.key == tripKey and it.carry == true and not it.stay and #it.companions > 0
end
-- For ShuttleService (and DriverService / JetService, requests drivers.md #1 / guests_jet.md #2): the founder will take
-- the travellers of trip `tripKey` on his OWN flight, so no other leg may fly them: his offer for it is being prepared
-- or is open (he is at home and the trip is abroad), he said Go and they travel with him (until they boarded with him),
-- or they fly home with him (abroad, also when the visit ends first). Not while the trip waits in the queue, not when
-- he started in Port Meridian (they fly out on their own), not when they stay because he flew home early.
function ItineraryService.holds(userId: number, tripKey: string): boolean
	local rec = recs[userId]
	if not rec or not rec.ready then return false end
	local it = rec.it
	if it then
		return it.key == tripKey and it.tier == "abroad" and it.together == true and not it.stay and #it.companions > 0 and it.state ~= "home"
	end
	if zone(rec.player) ~= "home" then return false end
	local o = rec.offer
	if o then return o.key == tripKey and o.tier == "abroad" and o.plan.from == "home" and #o.plan.companions > 0 end
	-- a new trip the scan has not offered yet (it is offered OFFER_DELAY s after it started)
	if rec.seen[tripKey] and not rec.fresh[tripKey] then return false end
	local e = empireOf(rec.s)
	local need, tier = IM.needsFounder(if e then IM.findTrip(e, tripKey) else nil)
	return need == true and tier == "abroad"
end
-- One line for the assistant's briefing (AssistantService), nil when there is no trip
function ItineraryService.summary(s: any): string?
	local rec = recOf(s)
	local e = empireOf(s)
	if not rec or not e then return nil end
	local t = now()
	local it = rec.it
	if it then
		local p = it.plan
		local parts = { "to " .. it.client.name .. " (" .. p.city .. ")" }
		if p.tier == "abroad" and it.flight and it.departs and (it.state == "pickup" or it.state == "airport") then table.insert(parts, tostring(it.flight) .. " " .. IM.clockText(e, t, it.departs)) end
		table.insert(parts, p.hotel)
		if p.returnAt then table.insert(parts, "back " .. IM.clockText(e, t, p.returnAt)) end
		local step = IM.STEP_TITLE[it.state] or it.state
		return "You're on the way " .. table.concat(parts, ", ") .. " · now: " .. string.lower(step)
	end
	local o = rec.offer
	if o then
		return o.client.name .. " wants to meet you in " .. o.plan.city .. (if o.countdownEnd then ": the trip starts by itself in a moment." else ": answer my call or press Go.")
	end
	return nil
end

------------------------------------------------------------------------------------------------ prompts
local function onPrompt(q: ProximityPrompt, player: Player)
	if q:GetAttribute("ItinAction") ~= "checkin" or q:GetAttribute("OwnerUserId") ~= player.UserId then return end
	local t = now()
	if (promptAt[player.UserId] or 0) > t then return end
	promptAt[player.UserId] = t + 1
	local rec = recs[player.UserId]
	local it = if rec then rec.it else nil
	if not rec or not it or it.state ~= "hotel" or it.prompt ~= q.Parent then return end
	local part = q.Parent
	local p = posOf(player)
	if not part or not part:IsA("BasePart") or not p or (p - part.Position).Magnitude > ItineraryService.PROMPT_RANGE then return end
	it.checkedIn = true
	removePrompt(it)
	setWith(it, false)
	notice(player, "Checked in at the " .. it.plan.hotel .. ". Your room is ready - and " .. IM.namesText(it.companions) .. " checked in too.")
	publish(rec)
end

------------------------------------------------------------------------------------------------ lifecycle
function ItineraryService.init()
	local old = ReplicatedStorage:FindFirstChild("CompanyItinerary")
	if old then old:Destroy() end
	local f = Instance.new("Folder")
	f.Name = "CompanyItinerary"
	f.Parent = ReplicatedStorage
	root = f
	local oldPrompts = workspace:FindFirstChild("ItineraryPrompts")
	if oldPrompts then oldPrompts:Destroy() end
	local pf = Instance.new("Folder")
	pf.Name = "ItineraryPrompts"
	pf.Parent = workspace
	promptFolder = pf
	table.clear(recs)
	table.clear(promptAt)
	scanAcc, stepAcc = 0, 0
	Jet = nil
	-- the phone: this package rings with its own booking (no built-in trip call), the call answer comes here
	Phone.BUILTIN_TRIP_CALLS = false
	Phone.onAction("itinerary", phoneHook)
	-- TripAction belongs to DriverService (action "ride"); the itinerary's actions are registered there
	for _, action in { "go", "cancel", "leave", "status", "retry" } do Driver.onTripAction(action, tripAction) end
	Prompts.PromptTriggered:Connect(onPrompt)
	City.onMeeting(function(player: Player, _clientId: string)
		local rec = recs[player.UserId]
		if rec and rec.it and rec.it.state == "meeting" then
			stepIt(rec, rec.it, now())
		end
	end)
	Session.onLoaded(function(s: any)
		local player: Player? = s.player
		if not player then return end
		recs[player.UserId] = { s = s, player = player, ready = false, seen = {}, offer = nil, it = nil, queue = {}, seq = 0, lastSig = "", lastState = nil, declined = {}, fresh = {} }
	end)
	Session.onClosing(function(s: any)
		local player: Player? = s.player
		if not player then return end
		local rec = recs[player.UserId]
		if rec and rec.s == s then
			if rec.it then
				local it = rec.it
				rec.it = nil
				removePrompt(it)
				local fo = it.folder
				it.folder = nil
				if fo then fo:Destroy() end
			end
			recs[player.UserId] = nil
		end
		promptAt[player.UserId] = nil
	end)
end

function ItineraryService.tick(dt: number)
	if not root then return end
	scanAcc += dt
	stepAcc += dt
	local doScan = scanAcc >= ItineraryService.SCAN
	if doScan then scanAcc = 0 end
	local doStep = stepAcc >= ItineraryService.STEP
	if doStep then stepAcc = 0 end
	if not doScan and not doStep then return end
	local t = now()
	for uid, rec in recs do
		local s = rec.s
		if s.closed or not rec.player.Parent then continue end
		if doScan then
			local ok, err = pcall(function() scan(rec) end)
			if not ok then warn("[Itinerary] scan: " .. tostring(err)) end
		end
		if doStep then
			local ok, err = pcall(function()
				if rec.offer then stepOffer(rec, t) end
				local it = rec.it
				if it then stepIt(rec, it, t) end
			end)
			if not ok then warn("[Itinerary] step " .. tostring(uid) .. ": " .. tostring(err)) end
		end
	end
end

return ItineraryService
