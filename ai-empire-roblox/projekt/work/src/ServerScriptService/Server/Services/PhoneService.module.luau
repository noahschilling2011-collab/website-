--!strict
-- Company phone, server side (package "phone"). The phone's messages and calendar come from the replicated
-- snapshot (PhoneMath on the client); this service only does what needs the server:
--   * calls: the assistant rings the founder for important moments (the first signed client, a pilot trip in
--     the region / abroad, enough cash for the next office) -> Notify "PHONE_CALL"; a call log per session
--     (memory only). Other packages ring the phone with PhoneService.ring(session, spec).
--   * hooks for later packages: PhoneService.onAction("itinerary" | "driver" | ..., handler). Until the itinerary
--     package registers "itinerary", accepting a trip call answers honestly "The travel desk opens soon".
--   * extra calendar items and messages from other packages (addCalendarItem / message) -> Notify "PHONE_UPDATE"
--   * contacts: the assistant (opens her existing briefing panel through the Notify ASSISTANT_OPEN the client
--     already handles), the driver hook, reception and the IT desk (answers from real state)
--   * settings: "Join business trips automatically" (default off). Saved in empire.prefs when the econ owner adds
--     that field (request design/requests/phone.md); until then per session only.
--   * AI chat with the player's own released models (user request 16): Roblox TextGenerator on the server,
--     system prompt from the model's real data (PhoneMath.systemPrompt), input checked (Guard) and filtered
--     (TextService) first, per-player limits (1 request / 4 s, 10 / min), a global budget below 100 / min, a
--     breaker after errors, and an honest offline demo reply (PhoneMath.demoReply, labelled "Demo reply (offline)")
--     whenever TextGenerator is unavailable, busy or failing. History stays in memory (never saved), no economic
--     effect (CORE_SPEC 11.6).
-- Remote PhoneAction {action = inbox | read | calendar | chat | call | setting, ...}.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage.Shared
local Ops = require(Shared.CompanyOps)
local PhoneMath = require(Shared.PhoneMath)
local EmpireMath = require(Shared.EmpireMath)
local EmpireConfig = require(Shared.Config.EmpireConfig)
local Lib = script.Parent.Parent.Lib
local Remote = require(Lib.Remote)
local Guard = require(Lib.Guard)
local Session = require(script.Parent.SessionService)

local Phone = {}

Phone.SCAN_EVERY = 1 -- seconds between two looks at every company (calls)
Phone.BREAKER_BASE = 30 -- seconds without TextGenerator after the first error (doubles, at most BREAKER_MAX)
Phone.BREAKER_MAX = 600
Phone.CONTACTS = { assistant = true, driver = true, reception = true, it = true } :: { [string]: boolean }
Phone.SETTINGS = { autoTrips = true } :: { [string]: boolean }
-- The built-in assistant call for a new region / abroad pilot trip. The itinerary package sets this to false when it
-- rings with its own booking (PhoneService.ring with kind "itinerary").
Phone.BUILTIN_TRIP_CALLS = true

export type Hook = (session: any, payload: { [string]: any }) -> { [string]: any }?
type Call = {
	id: string,
	from: string,
	title: string,
	text: string,
	kind: string, -- "info" | "itinerary" | "office" | ...
	at: number, -- server clock when it rang
	day: number,
	hour: number,
	state: string, -- "ringing" | "accepted" | "declined" | "missed"
	accept: string, -- button labels
	decline: string,
	open: string?, -- Computer app the client opens on accept
	section: string?,
	seen: boolean, -- a missed call the player has looked at
	data: any?, -- what the hook gets (trip details)
}
type ChatState = { gen: any?, sig: string, token: string?, turns: { any }, n: number }
type State = {
	calls: { Call },
	seq: number,
	settings: { [string]: any },
	messages: { any },
	calendar: { any },
	chat: { [string]: ChatState },
	times: { number },
	busy: boolean,
	seen: { ready: boolean, signed: number, trips: { [string]: boolean }, offices: { [string]: boolean } },
}

local states: { [any]: State } = setmetatable({}, { __mode = "k" }) :: any
local hooks: { [string]: Hook } = {}
local globalTimes: { number } = {}
local breaker = { until_ = 0, fails = 0 }

-- seams for headless tests: generator factory, input filter, clocks
local function defaultGenerator(prompt: string, temperature: number, topP: number, seed: number): any
	local g = Instance.new("TextGenerator")
	g.SystemPrompt = prompt
	g.Temperature = temperature
	g.TopP = topP
	g.Seed = seed
	return g
end
local function defaultFilter(text: string, userId: number): string?
	local ok, result = pcall(function(): any
		local filtered = TextService:FilterStringAsync(text, userId, Enum.TextFilterContext.PrivateChat)
		return filtered:GetNonChatStringForUserAsync(userId)
	end)
	if ok and typeof(result) == "string" then return result end
	-- ungeprüft (as TextFilter): an unpublished Studio place may not reach the filter; only the player sees it there
	if RunService:IsStudio() then return text end
	return nil
end
local seams = {
	generator = defaultGenerator,
	filter = defaultFilter,
	now = function(): number return os.clock() end, -- rate limits, breaker
	clock = function(): number return workspace:GetServerTimeNow() end, -- company time
}
function Phone._seams(opt: { [string]: any })
	for k, v in opt do (seams :: any)[k] = v end
end
function Phone._reset()
	table.clear(globalTimes)
	breaker.until_ = 0
	breaker.fails = 0
end

local function stateOf(s: any): State
	local st = states[s]
	if not st then
		st = { calls = {}, seq = 0, settings = { autoTrips = false }, messages = {}, calendar = {}, chat = {}, times = {}, busy = false,
			seen = { ready = false, signed = 0, trips = {}, offices = {} } }
		states[s] = st
	end
	return st :: State
end
Phone._state = stateOf

local function fire(s: any, kind: string, payload: any)
	if s.player then Remote.fire(s.player, "Notify", kind, payload) end
end

local function firstName(name: any): string?
	if typeof(name) ~= "string" then return nil end
	local text: string = name
	local first: string? = string.match(text, "^(%S+)")
	return first
end

local function callPayload(c: Call): { [string]: any }
	return { id = c.id, from = c.from, title = c.title, text = c.text, kind = c.kind, at = c.at, day = c.day, hour = c.hour, state = c.state,
		accept = c.accept, decline = c.decline, open = c.open, section = c.section, seen = c.seen, ring = PhoneMath.CALL_RING }
end

------------------------------------------------------------------------------------------------ public API
-- Register what accepting a call / pressing a contact does for `kind` ("itinerary", "driver", ...).
-- handler(session, {call?, answer?, contact?, data?}) -> result table (ok, text, ...) or nil
function Phone.onAction(kind: string, handler: Hook)
	hooks[kind] = handler
end
function Phone.hasAction(kind: string): boolean
	return hooks[kind] ~= nil
end

-- Ring the founder's phone. spec = {from?, title, text, kind?, accept?, decline?, open?, section?, data?}.
-- A call that is still ringing becomes "missed". Returns the call id.
function Phone.ring(s: any, spec: { [string]: any }): string
	local st = stateOf(s)
	local clock = seams.clock()
	st.seq += 1
	local day, hour = PhoneMath.now(s.data.empire, clock)
	for _, c in st.calls do if c.state == "ringing" then c.state = "missed" end end
	local c: Call = {
		id = "c" .. st.seq,
		from = if typeof(spec.from) == "string" then spec.from else "Assistant",
		title = tostring(spec.title or "Call"),
		text = tostring(spec.text or ""),
		kind = if typeof(spec.kind) == "string" then spec.kind else "info",
		at = clock,
		day = day,
		hour = hour,
		state = "ringing",
		accept = if typeof(spec.accept) == "string" then spec.accept else "Accept",
		decline = if typeof(spec.decline) == "string" then spec.decline else "Decline",
		open = if typeof(spec.open) == "string" then spec.open else nil,
		section = if typeof(spec.section) == "string" then spec.section else nil,
		seen = false,
		data = spec.data,
	}
	table.insert(st.calls, 1, c)
	while #st.calls > PhoneMath.CALLS_MAX do table.remove(st.calls) end
	fire(s, "PHONE_CALL", callPayload(c))
	return c.id
end

-- A message from another package into the phone inbox: {from, title, text, tone?}
function Phone.message(s: any, msg: { [string]: any })
	local st = stateOf(s)
	st.seq += 1
	local day, hour = PhoneMath.now(s.data.empire, seams.clock())
	table.insert(st.messages, 1, { id = "m" .. st.seq, from = tostring(msg.from or "Company"), title = tostring(msg.title or ""), body = tostring(msg.text or ""),
		tone = if typeof(msg.tone) == "string" then msg.tone else "info", day = day, hour = hour })
	while #st.messages > PhoneMath.INBOX_MAX do table.remove(st.messages) end
	fire(s, "PHONE_UPDATE", { what = "messages" })
end

-- A calendar item of another package (itinerary: flight, hotel, meeting, driver). item = {key, title, detail?,
-- at = server clock (workspace:GetServerTimeNow()) | day + hour, kind?}. Same key replaces the old item.
function Phone.addCalendarItem(s: any, item: { [string]: any }): boolean
	if typeof(item.key) ~= "string" or typeof(item.title) ~= "string" then return false end
	local st = stateOf(s)
	for i, old in st.calendar do if old.key == item.key then table.remove(st.calendar, i); break end end
	if #st.calendar >= PhoneMath.CALENDAR_MAX then table.remove(st.calendar, 1) end
	table.insert(st.calendar, { key = item.key, title = item.title, detail = if typeof(item.detail) == "string" then item.detail else nil,
		at = if typeof(item.at) == "number" then item.at else nil, day = tonumber(item.day), hour = tonumber(item.hour), kind = if typeof(item.kind) == "string" then item.kind else nil })
	fire(s, "PHONE_UPDATE", { what = "calendar" })
	return true
end
function Phone.removeCalendarItem(s: any, key: string)
	local st = stateOf(s)
	for i, old in st.calendar do
		if old.key == key then
			table.remove(st.calendar, i)
			fire(s, "PHONE_UPDATE", { what = "calendar" })
			return
		end
	end
end

-- Player setting ("autoTrips": join business trips automatically, default false)
function Phone.setting(s: any, key: string): any
	local prefs = s.data and s.data.empire and s.data.empire.prefs
	if typeof(prefs) == "table" and prefs[key] ~= nil then return prefs[key] end
	return stateOf(s).settings[key]
end
local function settingsOf(s: any): ({ [string]: any }, boolean)
	local out: { [string]: any } = {}
	for key in Phone.SETTINGS do out[key] = Phone.setting(s, key) == true end
	local prefs = s.data and s.data.empire and s.data.empire.prefs
	return out, typeof(prefs) == "table"
end

function Phone.calls(s: any): { Call }
	return stateOf(s).calls
end

------------------------------------------------------------------------------------------------ built-in calls
local function hotelNames(): (string, string)
	local ok, City = pcall(function(): any return require(Shared.Config.CityPlan) end)
	if ok and typeof(City) == "table" then
		local city = City.CITY_HOTEL and City.CITY_HOTEL.name
		local intl = City.INTL_HOTEL and City.INTL_HOTEL.name
		return if typeof(city) == "string" then city else "City Hotel", if typeof(intl) == "string" then intl else "Meridian Grand Hotel"
	end
	return "City Hotel", "Meridian Grand Hotel"
end
Phone._hotels = hotelNames

-- "PM 101 at 14:30": the next public shuttle to Port Meridian (FlightPlan timetable), nil when unavailable
local function nextShuttle(clock: number): string?
	local ok, text = pcall(function(): any
		local FP = require(Shared.FlightPlan)
		local _, _, departure = FP.nextLeg("out", clock)
		return tostring(FP.CONFIG.flights.out) .. " at " .. PhoneMath.clock(Ops.hour(departure))
	end)
	return if ok and typeof(text) == "string" then text else nil
end

-- names of the travellers of a new pilot trip: the k-th field rep for the k-th trip of the reps, the
-- engineers CompanyOps.presence marks as travelling (same order)
local function travellers(e: any, trip: any): (string?, string?)
	local deals = e.deals
	local k, m = 0, 0
	for _, t in deals.tripList do
		if typeof(t) ~= "table" or t.founder == true then continue end
		k += 1
		local c = Ops.client(t.client)
		if c and t.kind == "sign" and not t.hosted and c.trip ~= "city" then m += 1 end
		if t == trip then break end
	end
	local reps = if typeof(e.staffProfiles) == "table" then e.staffProfiles.marketer else nil
	local rep = if typeof(reps) == "table" and k >= 1 and k <= Ops.fieldReps(e) and typeof(reps[k]) == "table" then firstName(reps[k].n) else nil
	local engineers = if typeof(e.staffProfiles) == "table" then e.staffProfiles.engineer else nil
	local away = {}
	for i, state in Ops.presence(e, "engineer") do
		if state == "trip" and typeof(engineers) == "table" and typeof(engineers[i]) == "table" then table.insert(away, firstName(engineers[i].n) or "") end
	end
	local eng = away[m]
	return rep, if eng ~= "" then eng else nil
end

local function tripCall(s: any, trip: any, clock: number)
	local e = s.data.empire
	local c = Ops.client(trip.client)
	if not c then return end
	local cityHotel, intlHotel = hotelNames()
	local rep, eng = travellers(e, trip)
	local day = Ops.day(e)
	local backDay, backHour = PhoneMath.atPlay(e, clock, tonumber(trip.back) or 0)
	local title, text = PhoneMath.tripCall({
		client = c.name, tier = c.trip, rep = rep, engineer = eng, backDay = backDay, backHour = backHour, today = day,
		hotel = if c.trip == "abroad" then intlHotel else cityHotel, jet = e.jet == true, flight = if c.trip == "abroad" and e.jet ~= true then nextShuttle(clock) else nil,
	})
	Phone.ring(s, { from = "Assistant", title = title, text = text, kind = "itinerary", accept = "Join the trip", decline = "Not this time",
		data = { client = c.id, tier = c.trip, back = trip.back, rep = rep, engineer = eng } })
end

-- One look at a company: rings for the first signed client, new region / abroad pilot trips and an affordable
-- office; ringing calls older than CALL_RING become missed. The first look only takes the baseline.
function Phone.scan(s: any)
	local data = s.data
	if not data or not data.company or typeof(data.empire) ~= "table" then return end
	local e = data.empire
	local st = stateOf(s)
	local seen = st.seen
	local clock = seams.clock()
	for _, c in st.calls do
		if c.state == "ringing" and clock - c.at > PhoneMath.CALL_RING then c.state = "missed" end
	end
	local deals = if typeof(e.deals) == "table" then e.deals else nil
	local signed = if deals then tonumber(deals.signed) or 0 else 0
	local trips: { [string]: any } = {}
	if deals and typeof(deals.tripList) == "table" then
		for _, t in deals.tripList do
			if typeof(t) == "table" then trips[tostring(t.client) .. ":" .. tostring(t.back)] = t end
		end
	end
	local goal = EmpireMath.nextGoal(data, s.live)
	if not seen.ready then
		seen.ready = true
		seen.signed = signed
		for key in trips do seen.trips[key] = true end
		if goal and string.find(tostring(goal.id), "^office") and goal.etaMinutes == 0 then seen.offices[goal.id] = true end
		return
	end
	if seen.signed == 0 and signed >= 1 and deals then
		local first = nil
		for id in deals.accounts do
			local c = Ops.client(id)
			if c and (first == nil or c.first) then first = c end
		end
		if first then
			local title, text = PhoneMath.firstClientCall(first.name, first.retainer, goal)
			Phone.ring(s, { from = "Assistant", title = title, text = text, kind = "info", accept = "Great!", decline = "Later" })
		end
	end
	seen.signed = signed
	for key, t in trips do
		if not seen.trips[key] then
			seen.trips[key] = true
			local c = Ops.client(t.client)
			if Phone.BUILTIN_TRIP_CALLS and c and t.kind == "sign" and t.founder ~= true and t.hosted ~= true and c.trip ~= "city" then tripCall(s, t, clock) end
		end
	end
	for key in seen.trips do if not trips[key] then seen.trips[key] = nil end end
	if goal and string.find(tostring(goal.id), "^office") and goal.etaMinutes == 0 and not seen.offices[goal.id] then
		seen.offices[goal.id] = true
		local def = EmpireConfig.OFFICES[Ops.stageIndex(e) + 1]
		if def then
			local title, text = PhoneMath.officeCall(def.name, def.price)
			Phone.ring(s, { from = "Assistant", title = title, text = text, kind = "office", accept = "Open offices", decline = "Later", open = "empire" })
		end
	end
end

------------------------------------------------------------------------------------------------ contacts
local function contactText(s: any, contact: string): (string, string)
	local e = s.data.empire
	local stage = Ops.stageIndex(e)
	local clock = seams.clock()
	if contact == "reception" then
		if stage < 2 then return "Reception", "The Garage Lab has no reception yet. The front desk opens at the Founder Headquarters." end
		local open, waiting = 0, 0
		if typeof(e.applicants) == "table" then
			for _, a in e.applicants do if typeof(a) == "table" then if a.st == "new" then open += 1 else waiting += 1 end end end
		end
		local text = string.format("Front desk here. %d application%s open, %d candidate%s in the visitor lounge.", open, if open == 1 then " is" else "s are",
			waiting, if waiting == 1 then " is waiting" else "s are waiting")
		if Ops.stage(e).guest then text ..= string.format(" Guest house: %d of %d rooms taken.", math.min(Ops.GUEST.rooms, Ops.hotelGuests(e)), Ops.GUEST.rooms) end
		return "Reception", text
	elseif contact == "it" then
		-- the replicated summary (EmpireService: live.compute.faults from Ops.faults) = what the player sees
		local compute = s.live and s.live.compute
		local faults: { any } = if typeof(compute) == "table" and typeof(compute.faults) == "table" then compute.faults else Ops.faults(e)
		local rack = Ops.rack(s.data.gpus)
		local duty = Ops.itOnDuty(e, clock)
		if #rack == 0 then return "IT desk", "No rack GPUs installed yet. Buy one in Compute and it shows up in the server rack." end
		if #faults == 0 then
			return "IT desk", string.format("All %d rack GPU%s running.%s", #rack, if #rack == 1 then " is" else "s are",
				if stage < 2 then " The garage has no IT post: a fault restarts itself after about " .. math.floor(Ops.FAULT.alone / 60) .. " min." elseif duty then " IT is on duty." else " IT is off duty until 08:00.")
		end
		local slots = {}
		for _, f in faults do table.insert(slots, tostring(f.slot)) end
		return "IT desk", string.format("%d rack fault%s (slot %s). %s", #faults, if #faults == 1 then "" else "s", table.concat(slots, ", "),
			if duty then "We're fixing it: about " .. Ops.FAULT.it .. " s per fault." else "Nobody from IT is on duty: about " .. math.floor(Ops.FAULT.alone / 60) .. " min per fault.")
	elseif contact == "driver" then
		if stage < Ops.DRIVER.from then return "Driver", "Company drivers start at the Founder Headquarters. In the garage you drive yourself." end
		local drivers = if stage >= Ops.DRIVER.more then 2 else 1
		return "Driver", string.format("Your %s on the payroll (%s/day each). Rides to the airport and to clients are coming soon.",
			if drivers == 1 then "driver is" else drivers .. " drivers are", Ops.money(Ops.DRIVER.wage))
	end
	return "Phone", ""
end

local function openAssistant(s: any): boolean
	local ok, payload = pcall(function(): any
		local Assistant = require(script.Parent.AssistantService)
		return Assistant.payload(s)
	end)
	if ok and typeof(payload) == "table" then
		fire(s, "ASSISTANT_OPEN", payload)
		return true
	end
	warn("[Phone] assistant briefing unavailable: " .. tostring(payload))
	return false
end

local function runHook(kind: string, s: any, payload: { [string]: any }): { [string]: any }?
	local hook = hooks[kind]
	if not hook then return nil end
	local ok, result = pcall(hook, s, payload)
	if not ok then
		warn("[Phone] hook " .. kind .. " failed: " .. tostring(result))
		return { ok = false, err = "SERVER_ERROR" }
	end
	return if typeof(result) == "table" then result else { ok = true }
end

local function answer(s: any, id: string, how: string): { [string]: any }
	local st = stateOf(s)
	local call: Call? = nil
	for _, c in st.calls do if c.id == id then call = c end end
	if not call then return { ok = false, err = "NO_CALL" } end
	local c = call :: Call
	if c.state ~= "ringing" and c.state ~= "missed" then return { ok = false, err = "NO_CALL" } end
	c.state = if how == "accept" then "accepted" else "declined"
	c.seen = true
	local result: { [string]: any } = { ok = true }
	local hooked = runHook(c.kind, s, { call = callPayload(c), answer = how, data = c.data })
	if hooked then
		result = hooked
	elseif c.kind == "itinerary" then
		local d = c.data or {}
		local team = if d.rep and d.engineer then d.rep .. " and " .. d.engineer elseif d.rep then d.rep else "The team"
		result = { ok = true, soon = how == "accept", text = if how == "accept" then "The travel desk opens soon. " .. team .. " travel alone this time; you'll get their report here."
			else "Okay. " .. team .. " travel without you; you'll get their report here." }
	end
	result.call = callPayload(c)
	return result
end

------------------------------------------------------------------------------------------------ AI chat
local function allow(times: { number }, now: number, perMinute: number): boolean
	while #times > 0 and now - times[1] >= 60 do table.remove(times, 1) end
	return #times < perMinute
end

local function chatState(st: State, model: any, company: string?): ChatState
	local sig = tostring(model.version) .. ":" .. tostring(model.overall) .. ":" .. tostring(model.status) .. ":" .. tostring(company)
	local cs = st.chat[model.id]
	if not cs or cs.sig ~= sig then
		if cs and cs.gen and typeof(cs.gen) == "Instance" then (cs.gen :: Instance):Destroy() end
		cs = { gen = nil, sig = sig, token = if cs then cs.token else nil, turns = if cs then cs.turns else {}, n = if cs then cs.n else 0 }
		st.chat[model.id] = cs :: ChatState
	end
	return cs :: ChatState
end

local function remember(cs: ChatState, who: string, text: string)
	table.insert(cs.turns, { who = who, text = text })
	while #cs.turns > PhoneMath.CHAT_HISTORY do table.remove(cs.turns, 1) end
end

-- (reply, source "ai" | "demo", reason?)
local function generate(cs: ChatState, model: any, company: string?, text: string, now: number): (string, string, string?)
	local function demo(reason: string): (string, string, string?)
		return PhoneMath.demoReply(model, company, text, cs.n), "demo", reason
	end
	if now < breaker.until_ then return demo("offline") end
	if not allow(globalTimes, now, PhoneMath.CHAT_GLOBAL_PER_MINUTE) then return demo("busy") end
	table.insert(globalTimes, now)
	local ok, result = pcall(function(): any
		if not cs.gen then
			local prompt, temperature, topP, seed = PhoneMath.systemPrompt(model, company)
			cs.gen = seams.generator(prompt, temperature, topP, seed)
		end
		local request: { [string]: any } = { UserPrompt = text, MaxTokens = PhoneMath.CHAT_MAX_TOKENS }
		if cs.token then request.ContextToken = cs.token end
		return (cs.gen :: any):GenerateTextAsync(request)
	end)
	local reply = if ok and typeof(result) == "table" then result.GeneratedText else nil
	if typeof(reply) ~= "string" or not string.match(reply, "%S") then
		breaker.fails += 1
		breaker.until_ = now + math.min(Phone.BREAKER_MAX, Phone.BREAKER_BASE * 2 ^ (breaker.fails - 1))
		if not ok then warn("[Phone] TextGenerator unavailable: " .. tostring(result)) end
		cs.token = nil
		return demo(if ok then "empty" else "error")
	end
	breaker.fails = 0
	cs.token = if typeof(result.ContextToken) == "string" then result.ContextToken else nil
	local trimmed = string.match(reply, "^%s*(.-)%s*$") or reply
	return Ops.clip(trimmed, PhoneMath.CHAT_REPLY_CHARS), "ai", nil
end

function Phone.chat(s: any, modelId: string, raw: any, reset: boolean?): { [string]: any }
	local data = s.data
	local model = data.models and data.models[modelId]
	if not PhoneMath.chatAllowed(model) then return { ok = false, err = "NO_MODEL" } end
	local st = stateOf(s)
	if reset then
		local cs = st.chat[modelId]
		if cs and cs.gen and typeof(cs.gen) == "Instance" then (cs.gen :: Instance):Destroy() end
		st.chat[modelId] = nil
		return { ok = true, reset = true }
	end
	if typeof(raw) == "string" and (utf8.len(raw) or math.huge) > PhoneMath.CHAT_MAX_CHARS then return { ok = false, err = "TOO_LONG" } end
	local text = Guard.text(raw, 1, PhoneMath.CHAT_MAX_CHARS)
	if not text then return { ok = false, err = "BAD_INPUT" } end
	local now = seams.now()
	local last = st.times[#st.times]
	if st.busy or (last and now - last < PhoneMath.CHAT_GAP) then
		return { ok = false, err = "CHAT_COOLDOWN", wait = if last then math.max(1, math.ceil(PhoneMath.CHAT_GAP - (now - last))) else PhoneMath.CHAT_GAP }
	end
	if not allow(st.times, now, PhoneMath.CHAT_PER_MINUTE) then
		return { ok = false, err = "CHAT_COOLDOWN", wait = math.max(1, math.ceil(60 - (now - st.times[1]))) }
	end
	table.insert(st.times, now)
	st.busy = true
	local ok, res = pcall(function(): { [string]: any }
		local filtered = seams.filter(text, s.userId)
		if typeof(filtered) ~= "string" or not string.match(filtered, "%S") then return { ok = false, err = "FILTER_DOWN" } end
		local company = if data.company then data.company.name else nil
		local cs = chatState(st, model, company)
		cs.n += 1
		remember(cs, "you", filtered)
		local reply, source, reason = generate(cs, model, company, filtered, now)
		remember(cs, source, reply)
		return { ok = true, reply = reply, source = source, reason = reason, user = filtered, model = modelId,
			label = if source == "ai" then PhoneMath.AI_LABEL else PhoneMath.DEMO_LABEL }
	end)
	st.busy = false
	if not ok then
		warn("[Phone] chat failed: " .. tostring(res))
		return { ok = false, err = "SERVER_ERROR" }
	end
	return res
end

------------------------------------------------------------------------------------------------ remote
local ACTIONS = { inbox = true, read = true, calendar = true, chat = true, call = true, setting = true }
local function act(s: any, p: { [string]: any }): { [string]: any }
	local action = p.action
	if typeof(action) ~= "string" or not ACTIONS[action] then return { ok = false, err = "BAD_INPUT" } end
	local st = stateOf(s)
	if action == "inbox" then
		local calls = {}
		for _, c in st.calls do table.insert(calls, callPayload(c)) end
		local settings, saved = settingsOf(s)
		return { ok = true, calls = calls, messages = st.messages, settings = settings, saved = saved, hooks = { itinerary = hooks.itinerary ~= nil, driver = hooks.driver ~= nil } }
	elseif action == "read" then
		if p.what == "calls" then
			for _, c in st.calls do c.seen = true end
			return { ok = true }
		elseif p.what == "messages" then
			return { ok = true }
		end
		return { ok = false, err = "BAD_INPUT" }
	elseif action == "calendar" then
		return { ok = true, items = st.calendar }
	elseif action == "chat" then
		local modelId = Guard.id(p.modelId)
		if not modelId then return { ok = false, err = "BAD_INPUT" } end
		return Phone.chat(s, modelId, p.text, p.reset == true)
	elseif action == "call" then
		if p.id ~= nil then
			local id = Guard.id(p.id)
			if not id or (p.answer ~= "accept" and p.answer ~= "decline") then return { ok = false, err = "BAD_INPUT" } end
			return answer(s, id, p.answer)
		end
		local contact = p.contact
		if typeof(contact) ~= "string" or not Phone.CONTACTS[contact] then return { ok = false, err = "BAD_INPUT" } end
		if contact == "assistant" then
			local opened = openAssistant(s)
			return { ok = opened, contact = contact, opened = if opened then "assistant" else nil, err = if opened then nil else "SERVER_ERROR" }
		end
		local hooked = if contact == "driver" then runHook("driver", s, { contact = contact }) else nil
		if hooked then hooked.contact = contact; return hooked end
		local title, text = contactText(s, contact)
		return { ok = true, contact = contact, title = title, text = text, soon = contact == "driver" }
	elseif action == "setting" then
		local key = p.key
		if typeof(key) ~= "string" or not Phone.SETTINGS[key] or typeof(p.value) ~= "boolean" then return { ok = false, err = "BAD_INPUT" } end
		st.settings[key] = p.value
		local prefs = s.data.empire.prefs
		if typeof(prefs) == "table" then
			prefs[key] = p.value
			Session.markDirty(s)
		end
		local settings, saved = settingsOf(s)
		return { ok = true, settings = settings, saved = saved }
	end
	return { ok = false, err = "BAD_INPUT" }
end
Phone._act = act

function Phone.init()
	Remote.bind("PhoneAction", { burst = 8, perSecond = 4, company = true }, act)
	Session.onClosing(function(s: any)
		local st = states[s]
		if st then
			for _, cs in st.chat do if cs.gen and typeof(cs.gen) == "Instance" then (cs.gen :: Instance):Destroy() end end
			states[s] = nil
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Phone.SCAN_EVERY)
			for _, s in Session.all() do
				if not s.closed then
					local ok, err = pcall(Phone.scan :: (any) -> any, s)
					if not ok then warn("[Phone] scan: " .. tostring(err)) end
				end
			end
		end
	end)
end

return Phone
