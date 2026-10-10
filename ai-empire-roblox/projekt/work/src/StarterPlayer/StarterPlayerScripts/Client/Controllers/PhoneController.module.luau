--!strict
-- Company phone, client side (package "phone"). Builds the phone's view model from REAL state and feeds
-- UI/Screens/Phone:
--   * messages: the company log (the newest PhoneMath.NEWS_SHOWN lines of empire.deals.news) plus events derived
--     from snapshot changes (PhoneMath): who is sick / on vacation today, rack faults and fixes
--     (live.compute.faults), new hires / leavers, goals reached (EmpireMath.nextGoal), the field staff's
--     "arrived, checked in at the hotel" reports (tripList + the FlightPlan timetable); messages other packages
--     send through PhoneService.message. Read state lives in this session (everything that happened before you
--     joined counts as read; nothing runs offline).
--   * calls: the call log of PhoneService (Notify PHONE_CALL + PhoneAction inbox), answers through the remote; a
--     ringing call older than its ring time counts as missed here too (the server also sends PHONE_UPDATE)
--   * calendar: PhoneMath.calendar from tripList / accounts / the shuttle timetable + items of other packages;
--     play-second deadlines are converted with ONE anchor per session (PhoneMath.anchor), so times do not jitter
--   * map: the city's GPS destinations (CityPlan) -> TravelController.guide; finance (ledger of today and
--     yesterday, EmpireApp's own ledger helpers) and team (staff, desks, today's absences) with deep links into
--     the Company app
--   * AI chat: PhoneAction chat (server-side TextGenerator or labelled demo replies), history and the typed draft
--     in memory only
-- The remote is used only for actions (chat, answers, contacts, settings) and for refetches; PHONE_UPDATE carries
-- the new message / calendar item / call state, other refetches are coalesced and retried after RATE_LIMIT.
-- Badges update from snapshot changes. Keyboard P / gamepad Y open the phone, gamepad B goes back. The phone hides
-- while the Computer or the intro is open and closes when a talk / interview / assistant / lift / flight panel opens.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Ops = require(Shared.CompanyOps)
local PhoneMath = require(Shared.PhoneMath)
local EmpireMath = require(Shared.EmpireMath)
local EmpireConfig = require(Shared.Config.EmpireConfig)
local Types = require(Shared.Types)
local State = require(script.Parent.StateController)
local Action = require(script.Parent.ActionController)
local UI = script.Parent.Parent.UI
local Toast = require(UI.Toast)
local Phone = require(UI.Screens.Phone)
local Computer = require(UI.Screens.Computer)
local HUD = require(UI.Screens.HUD)
local Screens = require(UI.Phone.PhoneScreens)

type Message = PhoneMath.Message
type Snapshot = Types.Snapshot
type View = Screens.View

local Controller = {}

-- ScreenGuis in the middle of the screen that close the phone when they appear
Controller.PANELS = { TalkPanel = true, PeopleInterview = true, PeopleAssistant = true, CampusLift = true, CampusSecurity = true,
	FlightChoice = true, ShuttleRide = true, HeliRide = true }
Controller.CHAT_TURNS = 40 -- turns kept per model on the client (memory only)
Controller.FETCH_DELAY = 0.3 -- PHONE_UPDATE refetches within this time are coalesced into one
Controller.FETCH_RETRIES = 3

local MESSAGES: { [string]: string } = {
	CHAT_COOLDOWN = "Wait a moment before your next message.",
	FILTER_DOWN = "The chat filter is unavailable right now. Try again in a moment.",
	TOO_LONG = "That message is too long (200 characters at most).",
	NO_MODEL = "Only released models can chat.",
	NO_CALL = "This call has ended.",
}
function Controller.message(err: string?): string
	return if err and MESSAGES[err] then MESSAGES[err] else Action.message(err)
end

-- state of this session
local read: { [string]: boolean } = {}
local events: { [string]: Message } = {}
local newsList: { Message } = {}
local newsSig = ""
local serverMessages: { Message } = {}
local messages: { Message } = {}
local calls: { any } = {}
local results: { [string]: any } = {}
local dial: { [string]: any } = {}
local extraCalendar: { any } = {}
local settings = { autoTrips = false, popups = true, saved = false }
local hooks = { itinerary = false, driver = false }
local chats: { [string]: any } = {}
local prev: { [string]: any } = { ready = false }
local fetched = false
local lastSnapshot: Snapshot? = nil
local shuttleCache: { at: number, value: any } = { at = -math.huge, value = nil }
local currentView: View? = nil
local anchor: number? = nil -- play-clock anchor: server clock minus empire.seconds (PhoneMath.anchor)
local arrivals: { [string]: number | boolean } = {} -- trip key -> server clock of the arrival report (false = none)
local pending: { [string]: boolean } = {} -- coalesced refetches ("inbox" | "calendar")

-- direct remote call (own pcall: a waiting chat reply must not block answers through ActionController's lock)
local function invoke(payload: { [string]: any }): (boolean, { [string]: any })
	local ok, result = pcall(function(): any
		return Net.getFunction("PhoneAction"):InvokeServer(payload)
	end)
	if not ok or typeof(result) ~= "table" then return false, { ok = false, err = "NETWORK" } end
	return result.ok == true, result
end
Controller._invoke = invoke

local function serverMessage(m: any): Message
	local day, hour = tonumber(m.day) or 0, tonumber(m.hour) or 8
	return { key = "srv:" .. tostring(m.id), from = tostring(m.from), title = tostring(m.title), body = tostring(m.body), tone = tostring(m.tone or "info"),
		day = day, hour = hour, order = PhoneMath.order(day, hour), source = "server" }
end

local hotelCache: { [string]: string }? = nil
local function hotels(): { [string]: string }?
	if hotelCache then return hotelCache end
	local ok, City = pcall(function(): any return require(Shared.Config.CityPlan) end)
	if ok and typeof(City) == "table" and City.CITY_HOTEL and City.INTL_HOTEL then
		hotelCache = { city = tostring(City.CITY_HOTEL.name), abroad = tostring(City.INTL_HOTEL.name) }
	end
	return hotelCache
end

-- the next shuttle to Port Meridian (public FlightPlan timetable), refreshed every 10 s
local function shuttle(clock: number): any
	if clock - shuttleCache.at < 10 then return shuttleCache.value end
	shuttleCache.at = clock
	local ok, value = pcall(function(): any
		local FP = require(Shared.FlightPlan)
		local _, _, departure = FP.nextLeg("out", clock)
		return { at = departure, flight = FP.CONFIG.flights.out, airline = FP.CONFIG.airline }
	end)
	shuttleCache.value = if ok then value else nil
	return shuttleCache.value
end

-- When the shuttle that carries the field staff of a trip that left at `leftClock` lands in Port Meridian:
-- ShuttleService seats them on the first out leg whose boarding starts after the trip left.
local function shuttleArrive(leftClock: number): number?
	local ok, t = pcall(function(): any
		local FP = require(Shared.FlightPlan)
		local k, start = FP.nextLeg("out", leftClock)
		if start < leftClock then start = FP.legStart("out", k + 1) end
		return start + FP.leg("out").phases.deboarding.t0
	end)
	return if ok and typeof(t) == "number" then t else nil
end
Controller._shuttleArrive = shuttleArrive

-- GPS destinations of the city (CityPlan; the driving GPS panel's choice plus Port Meridian), built once
local placeCache: { any }? = nil
local function places(): { any }
	if placeCache then return placeCache end
	local out = {}
	local ok, City = pcall(function(): any return require(Shared.Config.CityPlan) end)
	if ok and typeof(City) == "table" and typeof(City.DESTINATION_LIST) == "table" then
		for _, d in City.DESTINATION_LIST do
			if typeof(d) ~= "table" or typeof(d.id) ~= "string" then continue end
			if d.zone ~= "abroad" and d.kind == "landmark" and d.zone ~= "downtown" then continue end
			table.insert(out, { id = d.id, name = tostring(d.name), kind = tostring(d.kind), abroad = d.zone == "abroad" })
		end
	end
	placeCache = out
	return out
end

local function travel(): any
	local ok, T = pcall(function(): any return require(script.Parent.TravelController) end)
	return if ok and typeof(T) == "table" then T else nil
end

-- EmpireApp's ledger helpers (same numbers and labels as Company -> Money)
local function empireApp(): any
	local ok, App = pcall(function(): any return require(UI.Apps.EmpireApp) end)
	return if ok and typeof(App) == "table" and typeof(App.ledgerDay) == "function" then App else nil
end

------------------------------------------------------------------------------------------------ view
-- a ringing call older than its ring time is a missed call (also without the server's PHONE_UPDATE)
local function expireCalls(clock: number)
	for _, c in calls do
		if c.state == "ringing" and typeof(c.at) == "number" and clock - c.at > (tonumber(c.ring) or PhoneMath.CALL_RING) then c.state = "missed" end
	end
end

local function missedCount(): number
	local n = 0
	for _, c in calls do if (c.state == "missed" and c.seen ~= true) or c.state == "ringing" then n += 1 end end
	return n
end

-- The Next goal in the HUD's own words (Screens/HUD.describe: the same title as the HUD card);
-- EmpireMath.nextGoal when the HUD wording is unavailable. nil = every goal reached.
local function goalView(snapshot: Snapshot): any
	local ok, d = pcall(HUD.describe, snapshot)
	if ok and typeof(d) == "table" and typeof(d.title) == "string" then
		if d.id == "done" then return nil end
		return { caption = if typeof(d.caption) == "string" then d.caption else "Next goal", text = d.title }
	end
	local goal = EmpireMath.nextGoal(snapshot.data, snapshot.live)
	if not goal then return nil end
	return { caption = "Next goal", text = tostring(goal.text) }
end
Controller._goalView = goalView

local function financeView(snapshot: Snapshot): any
	local data = snapshot.data
	local e = data.empire
	local ledger = if typeof(e.ledger) == "table" then e.ledger else {}
	local day = Ops.day(e)
	local App = empireApp()
	local function dayOf(d: number): ({ any }, { any }, number, number)
		if App then return App.ledgerDay(ledger[tostring(d)]) end
		return {}, {}, 0, 0
	end
	local income, costs, inTotal, outTotal = dayOf(day)
	local _, _, yIn, yOut = dayOf(day - 1)
	local function top(list: { any }, cost: boolean): { any }
		local out = {}
		for i = 1, math.min(3, #list) do
			local cat = tostring(list[i].cat)
			table.insert(out, { label = if App then App.categoryLabel(cat, cost) else cat, value = tonumber(list[i].value) or 0 })
		end
		return out
	end
	return { cash = tonumber(data.money) or 0, day = day, inTotal = inTotal, outTotal = outTotal, net = inTotal - outTotal,
		yesterday = if ledger[tostring(day - 1)] ~= nil then yIn - yOut else nil, income = top(income, false), costs = top(costs, true), ok = App ~= nil }
end
Controller._financeView = financeView

-- "Today: 2 sick · ..." and the absence counts need CompanyOps.presence of every role: only when the day, the
-- team or the trips change
local todayCache = { sig = "", line = nil :: string?, sick = 0, vacation = 0, trip = 0, leave = 0 }
local function today(e: any, live: any)
	local travelling = if typeof(live.ops) == "table" then tonumber(live.ops.travelling) or 0 else 0
	local tsig = tostring(prev.absence) .. ":" .. travelling
	if tsig == todayCache.sig then return end
	todayCache.sig = tsig
	todayCache.line = PhoneMath.todayLine(e, live)
	local sick, vacation, trip, leave = PhoneMath.absences(e)
	todayCache.sick, todayCache.vacation, todayCache.trip, todayCache.leave = #sick, #vacation, #trip, leave
end

local function teamView(e: any): any
	local roles = {}
	for _, r in EmpireConfig.ROLES do
		table.insert(roles, { id = r.id, name = r.name, count = if typeof(e.employees) == "table" then tonumber(e.employees[r.id]) or 0 else 0 })
	end
	local office = EmpireConfig.OFFICES[tonumber(e.office) or 1]
	local apprentices, night, applications = 0, 0, 0
	if typeof(e.apprentices) == "table" then for _ in e.apprentices do apprentices += 1 end end
	if typeof(e.nightShift) == "table" then for _, on in e.nightShift do if on == true then night += 1 end end end
	if typeof(e.applicants) == "table" then for _, a in e.applicants do if typeof(a) == "table" and a.st == "new" then applications += 1 end end end
	return { staff = if typeof(e.employees) == "table" then EmpireMath.staff(e) else 0, desks = if office then office.staff else 0, office = if office then office.name else "",
		roles = roles, apprentices = apprentices, night = night, applications = applications, ops = Ops.opsPosts(e),
		sick = todayCache.sick, vacation = todayCache.vacation, trip = todayCache.trip, leave = todayCache.leave }
end

local function placesView(e: any): any
	local mine: { [string]: boolean } = {}
	local deals = if typeof(e.deals) == "table" then e.deals else {}
	for id in (if typeof(deals.accounts) == "table" then deals.accounts else {}) do
		local c = Ops.client(id)
		if c then mine[c.name] = true end
	end
	for _, t in (if typeof(deals.tripList) == "table" then deals.tripList else {}) do
		local c = if typeof(t) == "table" then Ops.client(t.client) else nil
		if c then mine[c.name] = true end
	end
	local out = {}
	for _, p in places() do
		table.insert(out, { id = p.id, name = p.name, kind = p.kind, abroad = p.abroad, mine = mine[p.name] == true })
	end
	local T = travel()
	local active = false
	if T and typeof(T.active) == "function" then
		local ok, a = pcall(T.active)
		active = ok and a == true
	end
	return { list = out, active = active, gps = T ~= nil }
end

-- full = the phone is (being) opened: calendar, apps and chat models are rebuilt; closed, the badges are enough
local function buildView(snapshot: Snapshot, full: boolean): View
	local data = snapshot.data
	local e = data.empire
	local live = snapshot.live
	local clock = workspace:GetServerTimeNow()
	local day, hour = PhoneMath.now(e, clock)
	local phones = Ops.heads(e) + Ops.opsPosts(e)
	local old = currentView
	expireCalls(clock)
	local calendar: { any } = if full or not old then PhoneMath.calendar(data, live, clock, extraCalendar, shuttle(clock), hotels(), anchor) else old.calendar
	local models: { any } = if full or not old then PhoneMath.chatModels(data) else old.models
	today(e, live)
	local nextItem = nil
	for _, item in calendar do
		if item.public ~= true then nextItem = item; break end
	end
	return {
		company = if data.company then data.company.name else "",
		status = PhoneMath.clock(hour),
		dayText = "Day " .. day,
		today = day,
		dayLine = PhoneMath.dayLine(e, clock),
		todayLine = todayCache.line,
		staff = Ops.heads(e),
		goal = goalView(snapshot),
		messages = messages,
		read = read,
		unread = PhoneMath.unread(messages, read),
		calls = calls,
		missed = missedCount(),
		results = results,
		dial = dial,
		calendar = calendar,
		nextItem = nextItem,
		models = models,
		chats = chats,
		settings = { autoTrips = settings.autoTrips, popups = settings.popups, saved = settings.saved },
		phones = phones,
		phoneCost = string.format("%d phone%s × %s per game day = %s/day (team and operations staff).", phones, if phones == 1 then "" else "s", Ops.money(Ops.PHONE), Ops.money(phones * Ops.PHONE)),
		stage = Ops.stageIndex(e),
		hooks = { itinerary = hooks.itinerary, driver = hooks.driver },
		finance = if full or not old then financeView(snapshot) else old.finance,
		team = if full or not old then teamView(e) else old.team,
		places = if full or not old then placesView(e) else old.places,
	}
end

local function publish(full: boolean?)
	local snapshot = lastSnapshot
	if not snapshot or not snapshot.data.company then return end
	local v = buildView(snapshot, full == true or Phone.isOpen())
	currentView = v
	Phone.setView(v)
end
Controller.publish = publish

function Controller.view(): View?
	return currentView
end

------------------------------------------------------------------------------------------------ server data
local function remerge()
	local derived: { Message } = {}
	for _, m in events do table.insert(derived, m) end
	messages = PhoneMath.merge({ newsList, derived, serverMessages })
end

local fetchInbox: (attempt: number?) -> ()
local fetchCalendar: (attempt: number?) -> ()

-- RATE_LIMIT / NETWORK: try again a little later (the newest items must not stay missing)
local function retry(kind: string, attempt: number, err: any)
	if (err == "RATE_LIMIT" or err == "NETWORK") and attempt < Controller.FETCH_RETRIES then
		task.delay(1 + attempt, function()
			if kind == "calendar" then fetchCalendar(attempt + 1) else fetchInbox(attempt + 1) end
		end)
	end
end

fetchInbox = function(attempt: number?)
	local n = attempt or 0
	task.spawn(function()
		local ok, res = invoke({ action = "inbox" })
		if not ok then retry("inbox", n, res.err); return end
		if typeof(res.calls) == "table" then
			local known: { [string]: any } = {}
			for _, c in calls do known[tostring(c.id)] = c end
			calls = res.calls
			for _, c in calls do
				local local_ = known[tostring(c.id)]
				if local_ and local_.seen == true then c.seen = true end
			end
		end
		if typeof(res.messages) == "table" then
			serverMessages = {}
			for _, m in res.messages do if typeof(m) == "table" then table.insert(serverMessages, serverMessage(m)) end end
		end
		if typeof(res.settings) == "table" then settings.autoTrips = res.settings.autoTrips == true end
		settings.saved = res.saved == true
		if typeof(res.hooks) == "table" then
			hooks.itinerary = res.hooks.itinerary == true
			hooks.driver = res.hooks.driver == true
		end
		remerge()
		publish()
	end)
end

fetchCalendar = function(attempt: number?)
	local n = attempt or 0
	task.spawn(function()
		local ok, res = invoke({ action = "calendar" })
		if ok and typeof(res.items) == "table" then
			extraCalendar = res.items
			publish()
		elseif not ok then
			retry("calendar", n, res.err)
		end
	end)
end

-- one refetch per kind for every burst of PHONE_UPDATE notifications
local function schedule(kind: string)
	if pending[kind] then return end
	pending[kind] = true
	task.delay(Controller.FETCH_DELAY, function()
		pending[kind] = false
		if kind == "calendar" then fetchCalendar(0) else fetchInbox(0) end
	end)
end
Controller._schedule = schedule

local function copyFaults(list: any): { any }
	local out = {}
	if typeof(list) == "table" then for _, f in list do if typeof(f) == "table" then table.insert(out, { slot = f.slot, gpu = f.gpu, since = f.since }) end end end
	return out
end

-- field staff reports: one "Arrived in ..." message per region / abroad trip once its travellers arrive
local function arrivalsOf(e: any, deals: any, clock: number)
	local offset = anchor or clock - (tonumber(e.seconds) or 0)
	local present: { [string]: boolean } = {}
	for _, t in (if typeof(deals.tripList) == "table" then deals.tripList else {}) do
		if typeof(t) ~= "table" then continue end
		local key = tostring(t.client) .. ":" .. tostring(t.left)
		present[key] = true
		local at = arrivals[key]
		if at == nil then
			at = PhoneMath.arrivalAt(e, t, (tonumber(t.left) or 0) + offset, shuttleArrive) or false
			arrivals[key] = at
		end
		if typeof(at) == "number" and clock >= at and at < (tonumber(t.back) or 0) + offset and not events["arrived:" .. key] then
			local m = PhoneMath.arrivalMessage(e, t, at, clock, hotels(), offset)
			if m then
				events[m.key] = m
				if not prev.ready then read[m.key] = true end -- arrived before this session
			end
		end
	end
	for key in arrivals do if not present[key] then arrivals[key] = nil end end
end

local function process(snapshot: Snapshot)
	lastSnapshot = snapshot
	local data = snapshot.data
	if not data.company then return end
	local e = data.empire
	local live = snapshot.live
	local clock = workspace:GetServerTimeNow()
	local day, hour = PhoneMath.now(e, clock)
	anchor = PhoneMath.anchor(anchor, if typeof(snapshot.serverTime) == "number" then snapshot.serverTime else clock, tonumber(e.seconds) or 0)
	-- company log
	local deals = if typeof(e.deals) == "table" then e.deals else {}
	local news = if typeof(deals.news) == "table" then deals.news else {}
	local sig = tostring(news[1]) .. "#" .. #news
	if sig ~= newsSig then
		newsSig = sig
		newsList = PhoneMath.newsMessages(deals)
	end
	-- absences (one message per company day; recomputed when the day or the team changes)
	local heads = Ops.heads(e)
	local absenceSig = tostring(day) .. ":" .. heads .. ":" .. tostring(e.unpaidLeave)
	if prev.absence ~= absenceSig then
		prev.absence = absenceSig
		local m = PhoneMath.absenceMessage(e)
		if m then events[m.key] = m else events["absence:" .. day] = nil end
	end
	-- hires and leavers
	local staffSig = 0
	if typeof(e.staffProfiles) == "table" then for _, list in e.staffProfiles do if typeof(list) == "table" then staffSig += #list end end end
	if prev.staffSig ~= staffSig then
		local index = PhoneMath.staffIndex(e)
		if prev.ready and prev.staff then
			for _, m in PhoneMath.staffEvents(prev.staff, index, PhoneMath.announcedHires(deals), day, hour) do events[m.key] = m end
		end
		prev.staff = index
		prev.staffSig = staffSig
	end
	-- rack faults
	local compute = if typeof(live.compute) == "table" then live.compute else nil
	local faults = copyFaults(compute and compute.faults)
	if prev.ready then
		for _, m in PhoneMath.faultEvents(prev.faults, faults, compute ~= nil and compute.it == true, day, hour) do events[m.key] = m end
	end
	prev.faults = faults
	-- goals
	local goal = EmpireMath.nextGoal(data, live)
	local goalLite = if goal then { id = goal.id, text = goal.text } else nil
	if prev.ready then
		local m = PhoneMath.goalEvent(prev.goal, goal, day, hour)
		if m then events[m.key] = m end
	end
	prev.goal = goalLite
	-- field staff: arrived, checked in
	arrivalsOf(e, deals, clock)
	-- first snapshot of the session: what already happened counts as read (today's absences stay new)
	if not prev.ready then
		prev.ready = true
		for _, m in newsList do read[m.key] = true end
	end
	remerge()
	if not fetched then
		fetched = true
		fetchInbox()
		fetchCalendar()
	end
	publish()
end
Controller._process = process

------------------------------------------------------------------------------------------------ actions (deps)
local function upsertCall(call: any)
	for i, c in calls do
		if c.id == call.id then
			if c.seen == true then call.seen = true end
			calls[i] = call
			return
		end
	end
	for _, c in calls do if c.state == "ringing" then c.state = "missed" end end
	table.insert(calls, 1, call)
	while #calls > PhoneMath.CALLS_MAX do table.remove(calls) end
end

local function markRead(keys: { string })
	local changed = false
	for _, k in keys do
		if not read[k] then read[k] = true; changed = true end
	end
	if changed then task.defer(publish) end
end

local function readCalls()
	local changed = false
	for _, c in calls do
		if c.state == "missed" and c.seen ~= true then c.seen = true; changed = true end
	end
	if changed then
		task.defer(publish)
		task.spawn(invoke, { action = "read", what = "calls" })
	end
end

local function openComputer(app: string, section: string?)
	Phone.close()
	Computer.open(app, section)
end

local function answer(id: string, how: string)
	local key = tostring(id)
	if results[key] and results[key].pending then return end
	results[key] = { pending = true }
	publish()
	task.spawn(function()
		local ok, res = invoke({ action = "call", id = id, answer = how })
		if typeof(res.call) == "table" then upsertCall(res.call) end
		if ok then
			local call = res.call or {}
			results[key] = { text = if typeof(res.text) == "string" then res.text elseif how == "accept" then "Call ended." else "Call declined.", soon = res.soon == true }
			if how == "accept" and typeof(call.open) == "string" then
				openComputer(call.open, if typeof(call.section) == "string" then call.section else nil)
			end
		else
			results[key] = { text = Controller.message(res.err) }
		end
		publish()
	end)
end

local function dialContact(contact: string)
	if contact == "assistant" then
		task.spawn(function()
			local ok, res = invoke({ action = "call", contact = "assistant" })
			if ok then Phone.close() else Toast.show("error", Controller.message(res.err)) end
		end)
		return
	end
	dial[contact] = { pending = true }
	publish()
	task.spawn(function()
		local ok, res = invoke({ action = "call", contact = contact })
		dial[contact] = { text = if ok and typeof(res.text) == "string" then res.text else Controller.message(res.err), soon = res.soon == true }
		publish()
	end)
end

local function setSetting(key: string, value: boolean)
	if key == "popups" then
		settings.popups = value
		publish()
		return
	end
	task.spawn(function()
		local ok, res = invoke({ action = "setting", key = key, value = value })
		if ok and typeof(res.settings) == "table" then
			settings.autoTrips = res.settings.autoTrips == true
			settings.saved = res.saved == true
		elseif not ok then
			Toast.show("error", Controller.message(res.err))
		end
		publish()
	end)
end

local function chatOf(modelId: string): any
	local chat = chats[modelId]
	if not chat then
		chat = { turns = {}, waiting = false, last = -math.huge, seq = 0, draft = nil }
		chats[modelId] = chat
	end
	return chat
end

-- every turn gets a stable id (the thread keys its bubbles by turn, so trimming old turns never mixes sides)
local function push(chat: any, turn: any)
	chat.seq += 1
	turn.id = chat.seq
	table.insert(chat.turns, turn)
	while #chat.turns > Controller.CHAT_TURNS do table.remove(chat.turns, 1) end
end

local function sendChat(modelId: string, text: string)
	local chat = chatOf(modelId)
	if chat.waiting then return end
	local clean = string.match(text, "^%s*(.-)%s*$") or ""
	if clean == "" then return end
	chat.draft = nil
	local now = os.clock()
	if now - chat.last < PhoneMath.CHAT_GAP then
		push(chat, { who = "system", text = string.format("Wait %d s before your next message.", math.ceil(PhoneMath.CHAT_GAP - (now - chat.last))) })
		publish()
		return
	end
	chat.last = now
	local mine: { [string]: any } = { who = "you", text = clean, pending = true }
	push(chat, mine)
	chat.waiting = true
	publish()
	task.spawn(function()
		local ok, res = invoke({ action = "chat", modelId = modelId, text = clean })
		chat.waiting = false
		mine.pending = nil
		if ok and typeof(res.reply) == "string" then
			if typeof(res.user) == "string" then mine.text = res.user end -- the filtered text
			push(chat, { who = "model", text = res.reply, label = tostring(res.label or PhoneMath.DEMO_LABEL), source = tostring(res.source or "demo") })
		else
			mine.failed = true
			local why = Controller.message(res.err)
			if res.err == "CHAT_COOLDOWN" and typeof(res.wait) == "number" then why = string.format("Wait %d s before your next message.", res.wait) end
			push(chat, { who = "system", text = why })
		end
		publish()
	end)
end

local function resetChat(modelId: string)
	local draft = chats[modelId] and chats[modelId].draft
	chats[modelId] = nil
	if draft then chatOf(modelId).draft = draft end
	publish()
	task.spawn(invoke, { action = "chat", modelId = modelId, reset = true })
end

-- the typed, unsent text of a thread (memory only): survives a call, navigation and closing the phone
local function setDraft(modelId: string, text: string)
	local chat = chatOf(modelId)
	chat.draft = if text ~= "" then text else nil
end

-- GPS route to a city destination ("home" = the own HQ, "" = clear the route)
local function guide(id: string)
	Phone.close()
	local T = travel()
	if not T then
		Toast.show("error", "The GPS is not available right now.")
		return
	end
	if id == "" then
		T.clear()
		Toast.show("info", "Route cleared.", 3)
	else
		T.guide(id)
	end
end

local deps: Screens.Deps = {
	markRead = markRead,
	readCalls = readCalls,
	answer = answer,
	dial = dialContact,
	setSetting = setSetting,
	sendChat = sendChat,
	resetChat = resetChat,
	setDraft = setDraft,
	guide = guide,
	openComputer = openComputer,
	close = function() Phone.close() end,
	refresh = function() publish(true) end,
}
Controller.deps = deps

------------------------------------------------------------------------------------------------ public client API
-- Open the phone (optionally on a screen: "messages" | "calls" | "calendar" | "contacts" | "chat" | "map" |
-- "finance" | "team" | "settings").
function Controller.open(screen: string?, arg: any?)
	Phone.open(screen, arg)
end
-- Open the chat with one of the player's released models (other UIs, e.g. a "Chat" button in the Market app).
function Controller.openChat(modelId: string)
	Controller.open("thread", modelId)
end

------------------------------------------------------------------------------------------------ notifications
local function addServerMessage(m: any)
	for _, x in serverMessages do if x.key == "srv:" .. tostring(m.id) then return end end
	table.insert(serverMessages, 1, serverMessage(m))
	while #serverMessages > PhoneMath.INBOX_MAX do table.remove(serverMessages) end
	remerge()
	publish()
end

local function upsertItem(item: any)
	for i, x in extraCalendar do
		if x.key == item.key then table.remove(extraCalendar, i); break end
	end
	table.insert(extraCalendar, item)
	publish()
end

local function removeItem(key: string)
	for i, x in extraCalendar do
		if x.key == key then
			table.remove(extraCalendar, i)
			publish()
			return
		end
	end
end

local function onNotify(kind: string, payload: { [string]: any })
	if kind == "PHONE_CALL" and typeof(payload.id) == "string" then
		upsertCall(payload)
		publish()
		if Phone.isHidden() then
			Toast.show("info", tostring(payload.from) .. " called: " .. tostring(payload.title) .. ". Open your phone to call back.", 6)
		elseif settings.popups then
			Phone.incoming(payload) -- banner (phone closed), call screen or a call strip over the open phone
		end
	elseif kind == "PHONE_UPDATE" then
		local what = payload.what
		if what == "messages" and typeof(payload.message) == "table" then
			addServerMessage(payload.message)
		elseif what == "calendar" and typeof(payload.item) == "table" and typeof(payload.item.key) == "string" then
			upsertItem(payload.item)
		elseif what == "calendar" and typeof(payload.removed) == "string" then
			removeItem(payload.removed)
		elseif what == "calls" and typeof(payload.call) == "table" and typeof(payload.call.id) == "string" then
			upsertCall(payload.call)
			publish()
		else
			schedule(if what == "calendar" then "calendar" else "inbox")
		end
	end
end
Controller._onNotify = onNotify

------------------------------------------------------------------------------------------------ visibility + input
local function hudHidden(pg: Instance): boolean?
	local hud = pg:FindFirstChild("AIEmpire_HUD")
	local root = hud and hud:FindFirstChild("Root")
	local frame = root and root:FindFirstChild("HUD")
	if frame and frame:IsA("GuiObject") then return not frame.Visible end
	return nil
end

local function updateHidden(pg: Instance)
	local snapshot = State.snapshot
	local company = snapshot ~= nil and snapshot.data.company ~= nil
	local hud = hudHidden(pg)
	Phone.setHidden(not company or hud == true or Computer.isOpen())
end
Controller._updateHidden = updateHidden

function Controller.init()
	local player = Players.LocalPlayer
	local pg = player:WaitForChild("PlayerGui")
	Phone.mount(pg, deps)
	Phone.setHidden(true)
	State.onChange(function(snapshot: Snapshot)
		process(snapshot)
		updateHidden(pg)
	end)
	State.onNotify(onNotify)
	-- a talk / interview / assistant / lift / flight panel closes the phone (they sit in the middle of the screen)
	pg.ChildAdded:Connect(function(child: Instance)
		if Controller.PANELS[child.Name] then Phone.close() end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if input.KeyCode == Enum.KeyCode.ButtonB and Phone.isOpen() then
			Phone.back()
		elseif processed then
			return
		elseif input.KeyCode == Enum.KeyCode.P or input.KeyCode == Enum.KeyCode.ButtonY then
			if not Phone.isHidden() then
				Phone.toggle()
			end
		end
	end)
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(0.25)
			updateHidden(pg)
			tick += 1
			if tick % 4 == 0 and Phone.isOpen() then publish() end -- status bar clock once per second
		end
	end)
end

return Controller
