--!strict
-- PhoneMath (package "phone"): the pure helpers of the company phone ("Diensthandy"). No Roblox services, no
-- instances: the server (PhoneService) and the client (PhoneController, UI/Screens/Phone) call the same
-- functions with the same data, and the headless tests check them directly.
--   * time: company time from CompanyOps.hour (one game day = 1200 s, 08:00-18:00 = 900 s), company day from
--     empire.calendar, play-second deadlines (trips, accounts) converted into "Day 9 · 10:30"
--   * messages: every line of the company log (empire.deals.news, "day 8 11:54: signed CloudDesk: ...") becomes
--     one phone message with a sender (Sales, HR, Travel desk ...), plus events the phone derives from the
--     replicated state: who is sick / on vacation today (CompanyOps.presence), rack faults and their fixes
--     (live.compute.faults), new hires and leavers (staff profiles), the next goal (EmpireMath.nextGoal)
--   * calendar: trips under way and their returns, check-in visits before a contract ends, the next shuttle,
--     items other packages add through PhoneService.addCalendarItem
--   * calls: the assistant's texts for the first signed client, a pilot trip abroad / in the region and an
--     affordable office (the real names, times, hotels and prices)
--   * AI chat: the system prompt of a released model from its REAL data, and the clearly labelled offline demo
--     replies (deterministic, quality from the model's real stats) used when TextGenerator is unavailable
-- Nothing here changes money or saved data (CORE_SPEC 11.6: the model chat has no economic effect).
local Shared = script.Parent
local Config = Shared.Config
local Ops = require(Shared.CompanyOps)
local Format = require(Shared.Format)
local EmployeeConfig = require(Config.EmployeeConfig)
local EmpireConfig = require(Config.EmpireConfig)
local ModelConfig = require(Config.ModelConfig)
local HardwareConfig = require(Config.HardwareConfig)

local PhoneMath = {}

PhoneMath.INBOX_MAX = 40 -- messages kept in the phone (the newest 20 news lines + derived events)
PhoneMath.CALLS_MAX = 20 -- call log entries per session (server memory)
PhoneMath.CALL_RING = 25 -- seconds an incoming call rings before it counts as missed
PhoneMath.CALENDAR_MAX = 24 -- items other packages may add per session (PhoneService.addCalendarItem)
PhoneMath.CHAT_MAX_CHARS = 200 -- one chat message of the player (characters)
PhoneMath.CHAT_GAP = 4 -- seconds between two chat requests of one player
PhoneMath.CHAT_PER_MINUTE = 10 -- chat requests per player and minute
PhoneMath.CHAT_GLOBAL_PER_MINUTE = 90 -- the whole server stays below TextGenerator's ~100 requests per minute
PhoneMath.CHAT_MAX_TOKENS = 200 -- short replies
PhoneMath.CHAT_REPLY_CHARS = 700 -- a longer generated text is cut on a character boundary
PhoneMath.CHAT_HISTORY = 20 -- turns kept in memory per model (never saved)
PhoneMath.DEMO_LABEL = "Demo reply (offline)"
PhoneMath.AI_LABEL = "AI reply"

local DAY = Ops.DAY

------------------------------------------------------------------------------------------------ time
-- "11:54" of a visible hour (CompanyOps.hour)
function PhoneMath.clock(hour: number): string
	local h = hour % 24
	local m = math.floor((h % 1) * 60 + 1e-6)
	return string.format("%02d:%02d", math.floor(h), m)
end

-- minutes since the start of a company day (company days start at 08:00, the server day index boundary)
function PhoneMath.dayMinute(hour: number): number
	local h = hour % 24
	return math.floor(((h - 8) % 24) * 60 + 1e-6)
end

-- sort key of a moment: company day and time of that day
function PhoneMath.order(day: number, hour: number): number
	return day * 1440 + PhoneMath.dayMinute(hour)
end

-- company day and visible hour now (clock = workspace:GetServerTimeNow())
function PhoneMath.now(e: any, clock: number): (number, number)
	return Ops.day(e), Ops.hour(clock)
end

-- status bar text: "Day 8 · 11:54"
function PhoneMath.statusText(e: any, clock: number): string
	local day, hour = PhoneMath.now(e, clock)
	return Format.dayClock(day, hour)
end

-- Company day and hour of a server-clock moment `at` (the company day advances whenever the server day index
-- floor(clock / DAY) changes while the company is online: CompanyOps.advanceCalendar).
function PhoneMath.atClock(e: any, clock: number, at: number): (number, number)
	local day = Ops.day(e) + (math.floor(at / DAY) - math.floor(clock / DAY))
	return math.max(1, day), Ops.hour(at)
end

-- Company day and hour of a play-second deadline (trips `back`, accounts `expires`: empire.seconds runs while
-- the company is online, one play second per server second). Past deadlines map to now.
function PhoneMath.atPlay(e: any, clock: number, play: number): (number, number)
	local seconds = tonumber(e.seconds) or 0
	local dt = math.max(0, (tonumber(play) or seconds) - seconds)
	return PhoneMath.atClock(e, clock, clock + dt)
end

-- "10:30" today, "Day 9 · 10:30" another day
function PhoneMath.when(day: number, hour: number, today: number): string
	if day == today then return PhoneMath.clock(hour) end
	return Format.dayClock(day, hour)
end

------------------------------------------------------------------------------------------------ messages
export type Message = {
	key: string,
	from: string, -- sender shown in the list (Sales, HR, Travel desk, IT desk, Assistant ...)
	title: string,
	body: string,
	tone: string, -- "good" | "bad" | "warn" | "info"
	day: number,
	hour: number,
	order: number, -- sort key (newest first)
	source: string, -- "news" | "event" | "server"
}

-- "day 8 11:54: text" -> day, hour, text (a line without a stamp -> day 0)
function PhoneMath.parseNews(line: string): (number, number, string)
	local d, hh, mm, text = string.match(line, "^day (%d+) (%d%d):(%d%d): (.*)$")
	if d and hh and mm and text then
		return tonumber(d) or 0, (tonumber(hh) or 0) + (tonumber(mm) or 0) / 60, text
	end
	return 0, 8, line
end

local function cap(s: string): string
	return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

-- Sender, title, body and tone of one company-log text (the texts of CompanyOps.step, EmpireService,
-- AIModelService and PricingService). Unknown texts become a plain company message.
function PhoneMath.classify(text: string): (string, string, string, string)
	local a, b, c, d
	a, b = string.match(text, "^signed (.-): (.*)$")
	if a and b then return "Sales", "Signed " .. a, "New client " .. a .. ": " .. b .. ".", "good" end
	a, b = string.match(text, "^lost (.-) %((.*)%)$")
	if a and b then return "Sales", "Lost " .. a, cap(b) .. ".", "bad" end
	a, b = string.match(text, "^visited (.-): trust (%d+)%%$")
	if a and b then return "Sales", "Back from " .. a, "Trust is at " .. b .. " %. The deal signs at 100 %.", "info" end
	a, b = string.match(text, "^renewed (.-) for (%d+) days$")
	if a and b then return "Sales", "Renewed " .. a, a .. " stays a client for " .. b .. " more days.", "good" end
	a, b, c = string.match(text, "^founder drives to (.-): (.-), (.*)$")
	if a and b and c then return "Travel desk", "You're visiting " .. a, "Your car leaves now: " .. b .. " visit, " .. c .. ".", "info" end
	a, b, c, d = string.match(text, "^rep to (.-): (.-), (.-), (.*)$")
	if a and b and c and d then return "Travel desk", "Trip to " .. a, "A field rep leaves now: " .. b .. " visit, " .. c .. ", " .. d .. ".", "info" end
	a, b, c = string.match(text, "^hosting (.-) at the guest house: (.-), (.*)$")
	if a and b and c then return "Guest house", "Hosting " .. a, a .. " stays at our guest house: " .. b .. " visit, " .. c .. ".", "info" end
	a, b, c = string.match(text, "^HR hired (.-) %((.-), fee (.-)%)$")
	if a and b and c then return "HR", "Welcome " .. a, a .. " joined as " .. b .. " (hiring fee " .. c .. ").", "good" end
	a = string.match(text, "^apprentice (.-) graduated")
	if a then return "HR", a .. " graduated", a .. " finished the apprenticeship: skill 3, full wage.", "good" end
	a = string.match(text, "^moved into the (.*)$")
	if a then return "Company", "Moved into the " .. a, "Welcome to the " .. a .. ". New people start over the next minutes.", "good" end
	a = string.match(text, "^Lab level (%d+)")
	if a then return "Lab", "Lab level " .. a, cap(text) .. ".", "good" end
	if string.find(text, "^Save mode on") then return "Finance", "Save mode on", cap(text) .. ". Research and big purchases pause.", "warn" end
	if string.find(text, "^Save mode off") then return "Finance", "Save mode off", "Normal spending again.", "info" end
	if string.find(text, "^bought the company jet") then return "Company", "Company jet bought", cap(text) .. ".", "good" end
	a = string.match(text, "^founder joined the (.-) meeting")
	if a then return "Sales", "You joined " .. a, cap(text) .. ".", "good" end
	if string.find(text, "^cash recovered") then return "Finance", "Cash recovered", cap(text) .. ".", "good" end
	if string.find(text, "^cash below") then return "Finance", "Cash warning", cap(text) .. ".", "bad" end
	a, b = string.match(text, "^(.-) replaces (.-) %(")
	if a and b then return "Product", a .. " is live", cap(text) .. ".", "good" end
	a, b = string.match(text, "^(.-) launched as (.*)$")
	if a and b then return "Product", a .. " is live", a .. " launched as " .. b .. ".", "good" end
	a, b = string.match(text, "^(.- v%d+): (.*)$")
	if a and b then return "Pricing", a, cap(b) .. ".", "info" end
	local title = if #text > 40 then Ops.clip(text, 38) .. "..." else text
	return "Company", cap(title), cap(text), "info"
end

-- Messages of the replicated company log (newest first; each line keeps its own stamp)
function PhoneMath.newsMessages(deals: any): { Message }
	local out: { Message } = {}
	local news = if typeof(deals) == "table" and typeof(deals.news) == "table" then deals.news else {}
	for i, line in news do
		if typeof(line) ~= "string" then continue end
		local day, hour, text = PhoneMath.parseNews(line)
		local from, title, body, tone = PhoneMath.classify(text)
		table.insert(out, {
			key = "news:" .. line,
			from = from,
			title = title,
			body = body,
			tone = tone,
			day = day,
			hour = hour,
			order = PhoneMath.order(day, hour) - i * 1e-3, -- same minute: the log order (newest first)
			source = "news",
		})
	end
	return out
end

local function roleName(roleId: string): string
	local r = EmpireConfig.find(EmpireConfig.ROLES, roleId)
	return if r then r.name else roleId
end

local function nameList(names: { string }, max: number): string
	local shown = {}
	for i = 1, math.min(#names, max) do shown[i] = names[i] end
	local text = table.concat(shown, ", ")
	if #names > max then text ..= " and " .. (#names - max) .. " more" end
	return text
end

local function profileName(list: any, i: number): string?
	local p = if typeof(list) == "table" then list[i] else nil
	local n = if typeof(p) == "table" then p.n else nil
	return if typeof(n) == "string" and n ~= "" then n else nil
end

-- First names (or "a colleague") of everyone absent today: (sick, vacation, travelling, unpaid leave), each a
-- list of "Name (Role)". Pure function of saved data (CompanyOps.presence: hashes of the appearance seeds).
function PhoneMath.absences(e: any): ({ string }, { string }, { string }, number)
	local sick, vacation, trip = {}, {}, {}
	local leave = 0
	for _, role in EmpireConfig.ROLES do
		local list = if typeof(e.staffProfiles) == "table" then e.staffProfiles[role.id] else nil
		for i, state in Ops.presence(e, role.id) do
			if state == "present" then continue end
			local name = (profileName(list, i) or "A colleague") .. " (" .. role.name .. ")"
			if state == "sick" then table.insert(sick, name)
			elseif state == "vacation" then table.insert(vacation, name)
			elseif state == "trip" then table.insert(trip, name)
			else leave += 1 end
		end
	end
	return sick, vacation, trip, leave
end

local function firstName(entry: string): string
	return string.match(entry, "^(.-) %(") or entry
end

-- "Mia is sick today" (one message per company day; nil when everybody is at work)
function PhoneMath.absenceMessage(e: any): Message?
	local sick, vacation, trip, leave = PhoneMath.absences(e)
	if #sick == 0 and #vacation == 0 and leave == 0 then return nil end
	local day = Ops.day(e)
	local title
	if #sick == 1 then title = firstName(sick[1]) .. " is sick today"
	elseif #sick == 2 then title = firstName(sick[1]) .. " and " .. firstName(sick[2]) .. " are sick today"
	elseif #sick > 2 then title = #sick .. " colleagues are sick today"
	elseif #vacation > 0 then title = #vacation .. (if #vacation == 1 then " colleague is" else " colleagues are") .. " on vacation today"
	else title = leave .. " on unpaid leave today" end
	local parts = {}
	if #sick > 0 then table.insert(parts, "Sick (paid): " .. nameList(sick, 6) .. ".") end
	if #vacation > 0 then table.insert(parts, "Vacation: " .. nameList(vacation, 6) .. ".") end
	if #trip > 0 then table.insert(parts, "Travelling: " .. nameList(trip, 4) .. ".") end
	if leave > 0 then table.insert(parts, leave .. " on unpaid leave until cash recovers.") end
	table.insert(parts, "Their desks are free today; everyone else is at work.")
	return { key = "absence:" .. day, from = "HR", title = title, body = table.concat(parts, " "), tone = if #sick > 0 then "warn" else "info",
		day = day, hour = 8, order = PhoneMath.order(day, 8), source = "event" }
end

local function gpuLabel(id: any): string
	local def = if typeof(id) == "string" then HardwareConfig.getGPU(id) else nil
	return if def then (def :: any).label else "GPU"
end

-- Rack faults that appeared / were fixed between two live.compute.faults lists ({slot, gpu, since}).
-- itOnDuty = live.compute.it (repair takes Ops.FAULT.it s with IT on duty, Ops.FAULT.alone s without).
function PhoneMath.faultEvents(before: { any }?, now: { any }?, itOnDuty: boolean, day: number, hour: number): { Message }
	local out: { Message } = {}
	local function key(f: any): string return tostring(f.slot) .. ":" .. tostring(f.gpu) .. ":" .. tostring(f.since) end
	local old: { [string]: any } = {}
	local beforeList: { any } = before or {}
	local nowList: { any } = now or {}
	for _, f in beforeList do if typeof(f) == "table" then old[key(f)] = f end end
	local new: { [string]: any } = {}
	for _, f in nowList do if typeof(f) == "table" then new[key(f)] = f end end
	local order = PhoneMath.order(day, hour)
	for k, f in new do
		if not old[k] then
			local fix = if itOnDuty then "IT is on it: about " .. Ops.FAULT.it .. " s." else "No IT on duty: it restarts itself in about " .. math.floor(Ops.FAULT.alone / 60) .. " min."
			table.insert(out, { key = "fault:" .. k, from = "IT desk", title = "Rack fault in slot " .. tostring(f.slot),
				body = gpuLabel(f.gpu) .. " in slot " .. tostring(f.slot) .. " is down (" .. Ops.FAULT.units .. " compute unit off line). " .. fix,
				tone = "bad", day = day, hour = hour, order = order, source = "event" })
		end
	end
	for k, f in old do
		if not new[k] then
			table.insert(out, { key = "fixed:" .. k, from = "IT desk", title = "Slot " .. tostring(f.slot) .. " fixed",
				body = gpuLabel(f.gpu) .. " in slot " .. tostring(f.slot) .. " is back online.", tone = "good",
				day = day, hour = hour, order = order + 1e-4, source = "event" })
		end
	end
	table.sort(out, function(x: Message, y: Message): boolean return x.key < y.key end)
	return out
end

-- {[role..":"..seed] = "Name"} of every staff profile
function PhoneMath.staffIndex(e: any): { [string]: string }
	local out: { [string]: string } = {}
	if typeof(e.staffProfiles) ~= "table" then return out end
	for roleId, list in e.staffProfiles do
		if typeof(list) ~= "table" or typeof(roleId) ~= "string" then continue end
		for i, p in list do
			if typeof(p) == "table" and typeof(p.s) == "number" then
				out[roleId .. ":" .. tostring(p.s)] = profileName(list, i) or "A colleague"
			end
		end
	end
	return out
end

-- New hires and leavers between two staffIndex maps. `announced` = names the company log already welcomed
-- ("HR hired Mia ..."): no second message for them.
function PhoneMath.staffEvents(before: { [string]: string }, now: { [string]: string }, announced: { [string]: boolean }, day: number, hour: number): { Message }
	local out: { Message } = {}
	local order = PhoneMath.order(day, hour)
	for k, name in now do
		if before[k] == nil and not announced[name] then
			local roleId = string.match(k, "^(.-):") or ""
			table.insert(out, { key = "hire:" .. k, from = "HR", title = "Welcome " .. name, body = name .. " joined the team as " .. roleName(roleId) .. ".",
				tone = "good", day = day, hour = hour, order = order, source = "event" })
		end
	end
	for k, name in before do
		if now[k] == nil then
			local roleId = string.match(k, "^(.-):") or ""
			table.insert(out, { key = "left:" .. k .. ":" .. day, from = "HR", title = name .. " left", body = name .. " (" .. roleName(roleId) .. ") is no longer with the company.",
				tone = "info", day = day, hour = hour, order = order, source = "event" })
		end
	end
	table.sort(out, function(x: Message, y: Message): boolean return x.key < y.key end)
	return out
end

-- Names the company log welcomed ("HR hired Mia Chen (AI Researcher, fee $1,000)")
function PhoneMath.announcedHires(deals: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	local news = if typeof(deals) == "table" and typeof(deals.news) == "table" then deals.news else {}
	for _, line in news do
		if typeof(line) == "string" then
			local name = string.match(line, "HR hired (.-) %(")
			if name then out[name] = true end
		end
	end
	return out
end

-- "Goal reached" message when EmpireMath.nextGoal moves on (goal = the new goal or nil = all done)
function PhoneMath.goalEvent(before: any, goal: any, day: number, hour: number): Message?
	if typeof(before) ~= "table" or (typeof(goal) == "table" and goal.id == before.id) then return nil end
	local nextText = if typeof(goal) == "table" then " Next goal: " .. tostring(goal.text) .. "." else " Every goal is done."
	return { key = "goal:" .. tostring(before.id), from = "Assistant", title = "Goal reached: " .. tostring(before.text),
		body = "Done: " .. tostring(before.text) .. "." .. nextText, tone = "good", day = day, hour = hour,
		order = PhoneMath.order(day, hour), source = "event" }
end

-- Progress line of a goal: "$12,300 / $27,000 · ~6 min" (money goals) or "1 / 2"
function PhoneMath.goalProgress(goal: any): (string, number)
	if typeof(goal) ~= "table" then return "Every goal is done", 1 end
	local have, need = tonumber(goal.have) or 0, math.max(1, tonumber(goal.need) or 1)
	local text
	if string.find(tostring(goal.id), "^office") or goal.id == "jet" then
		text = Ops.money(math.min(have, need)) .. " / " .. Ops.money(need)
	elseif goal.id == "client" then
		text = "trust " .. math.floor(have) .. " %"
	elseif need <= 1 then
		text = if have >= need then "done" else "not done yet"
	else
		text = math.floor(have) .. " / " .. math.floor(need)
	end
	local eta = tonumber(goal.etaMinutes)
	if eta then text ..= if eta <= 0 then " · ready" else " · ~" .. math.max(1, math.ceil(eta)) .. " min" end
	return text, math.clamp(have / need, 0, 1)
end

-- newest first, at most `max`, one message per key (later lists win)
function PhoneMath.merge(lists: { { Message } }, max: number?): { Message }
	local byKey: { [string]: Message } = {}
	for _, list in lists do for _, m in list do byKey[m.key] = m end end
	local out: { Message } = {}
	for _, m in byKey do table.insert(out, m) end
	table.sort(out, function(a: Message, b: Message): boolean
		if a.order ~= b.order then return a.order > b.order end
		return a.key < b.key
	end)
	local limit = max or PhoneMath.INBOX_MAX
	while #out > limit do table.remove(out) end
	return out
end

function PhoneMath.unread(messages: { Message }, read: { [string]: boolean }): number
	local n = 0
	for _, m in messages do if not read[m.key] then n += 1 end end
	return n
end

------------------------------------------------------------------------------------------------ calendar
export type CalItem = { key: string, title: string, detail: string, day: number, hour: number, order: number, kind: string, now: boolean?, tag: string? }

local WHERE = { city = "Business City", region = "Business City", abroad = "Port Meridian" }

-- Calendar of today and the coming days from the replicated state. clock = workspace:GetServerTimeNow();
-- extra = items of PhoneService.addCalendarItem ({key, title, detail?, at = server clock, kind?});
-- shuttle = {at = server clock of the next departure to Port Meridian, flight = "PM 101", airline}?;
-- hotels = {city = "City Hotel", abroad = "Meridian Grand Hotel"}?. Returns the items (soonest first).
function PhoneMath.calendar(data: any, live: any, clock: number, extra: { any }?, shuttle: any?, hotels: any?): { CalItem }
	local e = data.empire
	local out: { CalItem } = {}
	local today = Ops.day(e)
	local nowOrder = PhoneMath.order(today, Ops.hour(clock))
	local deals = if typeof(e.deals) == "table" then e.deals else {}
	local names: { [string]: any } = {}
	local liveTrips = if typeof(live) == "table" and typeof(live.ops) == "table" and typeof(live.ops.trips) == "table" then live.ops.trips else {}
	for _, t in liveTrips do if typeof(t) == "table" and typeof(t.client) == "string" then names[t.client .. ":" .. tostring(t.back)] = t end end
	local cityHotel = if typeof(hotels) == "table" and typeof(hotels.city) == "string" then hotels.city else "City Hotel"
	local intlHotel = if typeof(hotels) == "table" and typeof(hotels.abroad) == "string" then hotels.abroad else "Meridian Grand Hotel"
	-- trips under way: away now, back at `back`
	for _, trip in (if typeof(deals.tripList) == "table" then deals.tripList else {}) do
		local c = if typeof(trip) == "table" then Ops.client(trip.client) else nil
		if not c then continue end
		local day, hour = PhoneMath.atPlay(e, clock, tonumber(trip.back) or 0)
		local info = names[c.id .. ":" .. tostring(trip.back)]
		local crew = if typeof(info) == "table" then tonumber(info.crew) or 1 else 1
		local title, detail
		if trip.hosted == true then
			title = c.name .. " team at our guest house"
			detail = Ops.HOSTED.guests .. " guests, " .. Ops.HOSTED.nights .. " nights, workshop in the boardroom · leave " .. PhoneMath.when(day, hour, today)
		else
			local who = if trip.founder == true then "You" elseif crew >= 2 then "Field rep + engineer" else "Field rep"
			local what = if trip.kind == "renew" then "check-in visit" else "pilot visit"
			local stay = if c.trip == "abroad" then (if e.jet == true then "company jet, " .. Ops.JET.nights .. " night at the " else "shuttle flight, " .. Ops.TRIPS.abroad.nights .. " nights at the ") .. intlHotel
				elseif c.trip == "region" then Ops.TRIPS.region.nights .. " night at the " .. cityHotel
				else "company car"
			title = who .. ": " .. what .. " at " .. c.name
			detail = WHERE[c.trip] .. " · " .. stay .. " · back " .. PhoneMath.when(day, hour, today)
		end
		table.insert(out, { key = "trip:" .. c.id .. ":" .. tostring(trip.back), title = title, detail = detail, day = day, hour = hour,
			order = PhoneMath.order(day, hour), kind = if c.trip == "abroad" then "flight" else "trip", now = true, tag = if trip.hosted == true then "leave" else "back" })
	end
	-- check-in visits before a contract ends (CompanyOps.step: renewals leave TRIPS.days + RENEW_LEAD_DAYS before)
	local seconds = tonumber(e.seconds) or 0
	for id, acc in (if typeof(deals.accounts) == "table" then deals.accounts else {}) do
		local c = Ops.client(id)
		if not c or typeof(acc) ~= "table" or acc.renewing == true then continue end
		local expires = tonumber(acc.expires) or 0
		local due = expires - (Ops.TRIPS[c.trip].days + Ops.RENEW_LEAD_DAYS) * DAY
		local day, hour = PhoneMath.atPlay(e, clock, due)
		local endDay, endHour = PhoneMath.atPlay(e, clock, expires)
		local overdue = due <= seconds
		table.insert(out, { key = "renew:" .. c.id, title = "Check-in visit: " .. c.name,
			detail = (if overdue then "Due now · waiting for a free seller (trips leave " .. PhoneMath.clock(Ops.DEPART.from) .. "-" .. PhoneMath.clock(Ops.DEPART.to) .. ")" else "Due " .. PhoneMath.when(day, hour, today))
				.. " · contract ends " .. PhoneMath.when(endDay, endHour, today) .. " · " .. Ops.money(c.retainer) .. "/day",
			day = day, hour = hour, order = math.max(nowOrder, PhoneMath.order(day, hour)), kind = "renewal", tag = "due" })
	end
	-- the next shuttle to Port Meridian (public timetable, FlightPlan)
	if typeof(shuttle) == "table" and typeof(shuttle.at) == "number" then
		local day, hour = PhoneMath.atClock(e, clock, shuttle.at)
		table.insert(out, { key = "shuttle:" .. tostring(math.floor(shuttle.at)), title = "Shuttle " .. tostring(shuttle.flight or "") .. " to Port Meridian",
			detail = tostring(shuttle.airline or "Meridian Air") .. " · City Airport gate · departs " .. PhoneMath.when(day, hour, today), day = day, hour = hour,
			order = PhoneMath.order(day, hour), kind = "flight" })
	end
	-- items of other packages (itinerary: flights, hotel, meetings, driver)
	local extraList: { any } = extra or {}
	for _, item in extraList do
		if typeof(item) ~= "table" or typeof(item.title) ~= "string" then continue end
		local day, hour
		if typeof(item.at) == "number" then day, hour = PhoneMath.atClock(e, clock, item.at)
		else day, hour = math.max(1, math.floor(tonumber(item.day) or today)), tonumber(item.hour) or 8 end
		table.insert(out, { key = "item:" .. tostring(item.key), title = item.title, detail = if typeof(item.detail) == "string" then item.detail else PhoneMath.when(day, hour, today),
			day = day, hour = hour, order = PhoneMath.order(day, hour), kind = if typeof(item.kind) == "string" then item.kind else "item" })
	end
	table.sort(out, function(a: CalItem, b: CalItem): boolean
		if (a.now == true) ~= (b.now == true) then return a.now == true end
		if a.order ~= b.order then return a.order < b.order end
		return a.key < b.key
	end)
	return out
end

-- one line about the working day: "Office hours 08:00-18:00 · trips leave 08:00-15:00"
function PhoneMath.dayLine(e: any, clock: number): string
	local hour = Ops.hour(clock)
	local open = Ops.inOffice(clock)
	return (if open then "Office open until 18:00" else "Night · office opens 08:00") .. " · trips leave " .. PhoneMath.clock(Ops.DEPART.from) .. "-" .. PhoneMath.clock(Ops.DEPART.to)
		.. (if open and hour >= Ops.DEPART.to then " (done today)" else "")
end

-- "Today: 2 sick · 1 on vacation · 2 travelling" (nil when everybody is at work and nobody travels)
function PhoneMath.todayLine(e: any, live: any): string?
	local sick, vacation, trip, leave = PhoneMath.absences(e)
	local travelling = if typeof(live) == "table" and typeof(live.ops) == "table" then tonumber(live.ops.travelling) or 0 else 0
	local parts = {}
	if #sick > 0 then table.insert(parts, #sick .. " sick") end
	if #vacation > 0 then table.insert(parts, #vacation .. " on vacation") end
	if leave > 0 then table.insert(parts, leave .. " on leave") end
	if travelling > 0 then table.insert(parts, travelling .. (if travelling == 1 then " trip" else " trips") .. " under way") end
	if #parts == 0 then return nil end
	local _ = trip
	return "Today: " .. table.concat(parts, " · ")
end

------------------------------------------------------------------------------------------------ calls
-- The assistant's call texts (short, real data only). Returned as (title, text).
function PhoneMath.firstClientCall(clientName: string, retainer: number, goal: any): (string, string)
	local nextText = if typeof(goal) == "table" then " Next up: " .. tostring(goal.text) .. "." else ""
	return "First client signed!", "Great news: " .. clientName .. " signed! They pay a pilot fee of " .. Ops.money(retainer * Ops.PILOT_DAYS)
		.. " and " .. Ops.money(retainer) .. " every game day from now on." .. nextText
end

export type TripCall = {
	client: string,
	tier: string, -- "region" | "abroad"
	rep: string?, -- "Mia" (Growth & Sales field rep)
	engineer: string?, -- "Leo" (ML engineer)
	backDay: number,
	backHour: number,
	today: number,
	hotel: string,
	jet: boolean,
	flight: string?, -- "PM 101 at 14:30" (next shuttle) when known
}
function PhoneMath.tripCall(t: TripCall): (string, string)
	local rep = if t.rep then t.rep .. " from Growth & Sales" else "A field rep"
	local eng = if t.engineer then t.engineer .. " from Engineering" else "an engineer"
	local back = PhoneMath.when(t.backDay, t.backHour, t.today)
	if t.tier == "abroad" then
		local how = if t.jet then "fly out on our company jet" elseif t.flight then "fly out on the shuttle " .. t.flight else "fly out on the next shuttle"
		local nights = if t.jet then Ops.JET.nights else Ops.TRIPS.abroad.nights
		return t.client .. " wants to meet", t.client .. " wants to meet in Port Meridian. " .. rep .. " and " .. eng .. " " .. how .. " and stay "
			.. nights .. (if nights == 1 then " night" else " nights") .. " at the " .. t.hotel .. ". They're back " .. (if string.find(back, "Day") then "on " .. back else "at " .. back) .. ". Do you want to join them?"
	end
	return t.client .. " wants to meet", t.client .. " wants a pilot meeting in Business City. " .. rep .. " and " .. eng .. " are driving over now and stay "
		.. Ops.TRIPS.region.nights .. " night at the " .. t.hotel .. ". They're back " .. (if string.find(back, "Day") then "on " .. back else "at " .. back) .. ". Do you want to join them?"
end

function PhoneMath.officeCall(officeName: string, price: number): (string, string)
	return "We can move!", "We have enough cash for the " .. officeName .. " (" .. Ops.money(price) .. ") and a safety reserve. Open Company → Offices when you want to move."
end

------------------------------------------------------------------------------------------------ AI chat
local function statValue(model: any, id: string): number
	local stats = if typeof(model.stats) == "table" then model.stats else {}
	return math.floor(tonumber(stats[id]) or 0)
end

-- best and worst core stat (weight > 0): (bestLabel, bestValue, worstLabel, worstValue)
function PhoneMath.bestWorst(model: any): (string, number, string, number)
	local best, bestV, worst, worstV = "Reasoning", -1, "Reasoning", 1e9
	for _, s in ModelConfig.STATS do
		if s.weight <= 0 then continue end
		local v = statValue(model, s.id)
		if v > bestV then best, bestV = s.label, v end
		if v < worstV then worst, worstV = s.label, v end
	end
	return best, math.max(0, bestV), worst, if worstV == 1e9 then 0 else worstV
end

-- "Nova v2 · 1B · Balanced · Consumer Chat · 63 overall"
function PhoneMath.modelLine(model: any): string
	local size = ModelConfig.getSize(tostring(model.sizeId))
	local focus = ModelConfig.getFocus(tostring(model.focusId))
	local line = ModelConfig.getLine(if typeof(model.release) == "table" then model.release.target else nil)
	return string.format("%s v%d · %s · %s%s · %.0f overall", tostring(model.name), math.floor(tonumber(model.version) or 1), if size then size.label else "?",
		if focus then focus.label else "Balanced", if line then " · " .. line.label else "", tonumber(model.overall) or 0)
end

-- released models of the player: live first, then retired versions; each {id, title, line, live}
function PhoneMath.chatModels(data: any): { any }
	local out = {}
	for _, id in (if typeof(data.modelOrder) == "table" then data.modelOrder else {}) do
		local m = data.models and data.models[id]
		if typeof(m) == "table" and typeof(m.release) == "table" and (m.status == "live" or m.status == "retired") then
			local size = ModelConfig.getSize(tostring(m.sizeId))
			local focus = ModelConfig.getFocus(tostring(m.focusId))
			local line = ModelConfig.getLine(m.release.target)
			table.insert(out, { id = id, title = tostring(m.name) .. " v" .. tostring(m.version), line = PhoneMath.modelLine(m), live = m.status == "live", overall = tonumber(m.overall) or 0,
				sub = (if size then size.label else "?") .. " · " .. (if focus then focus.label else "Balanced") .. (if line then " · " .. line.label else "") })
		end
	end
	table.sort(out, function(a: any, b: any): boolean
		if a.live ~= b.live then return a.live end
		if a.overall ~= b.overall then return a.overall > b.overall end
		return a.id < b.id
	end)
	return out
end

function PhoneMath.chatAllowed(model: any): boolean
	return typeof(model) == "table" and typeof(model.release) == "table" and (model.status == "live" or model.status == "retired")
end

local TONE: { [string]: string } = {
	balanced = "friendly, clear and helpful",
	coding = "concise and technical; you like short code examples",
	reasoning = "calm and careful; you think step by step",
	creative = "playful and imaginative; you enjoy wordplay",
}
local TEMPERATURE: { [string]: number } = { balanced = 0.7, coding = 0.4, reasoning = 0.5, creative = 0.9 }

-- TextGenerator settings of a model: (SystemPrompt, Temperature, TopP, Seed). Built ONLY from the model's real
-- data (name, version, size, focus, product line, overall and core stats, owner company); weak models are
-- told to answer like weak models.
function PhoneMath.systemPrompt(model: any, company: string?): (string, number, number, number)
	local size = ModelConfig.getSize(tostring(model.sizeId))
	local focusId = if TONE[tostring(model.focusId)] then tostring(model.focusId) else "balanced"
	local line = ModelConfig.getLine(if typeof(model.release) == "table" then model.release.target else nil)
	local overall = math.floor(tonumber(model.overall) or 0)
	local stats = {}
	for _, s in ModelConfig.STATS do
		if s.weight > 0 then table.insert(stats, s.label .. " " .. statValue(model, s.id)) end
	end
	local quality
	if overall < 40 then
		quality = "You are a tiny early model. Answer in one or two very simple sentences, often say you are not sure, and you sometimes make small mistakes."
	elseif overall < 60 then
		quality = "You are a decent but limited model. Keep answers short and simple; admit when something is beyond you."
	elseif overall < 80 then
		quality = "You are a capable model. Give clear, correct, short answers."
	else
		quality = "You are an excellent frontier model. Give precise, insightful, short answers."
	end
	local weak = {}
	for _, s in ModelConfig.STATS do
		if s.weight > 0 and statValue(model, s.id) < 40 then table.insert(weak, string.lower(s.label)) end
	end
	local owner = if company and company ~= "" then company else "a young AI startup"
	local prompt = string.format(
		"You are %s v%d, an AI model made by %s in the Roblox game AI Empire. Size %s, focus %s%s. Overall score %d of 100; %s. %s%s Your tone is %s. "
			.. "Stay in character as this model, keep every reply under 80 words, never claim to be a real-world product or company, and keep everything friendly and suitable for all ages.",
		tostring(model.name), math.floor(tonumber(model.version) or 1), owner, if size then size.label else "unknown", focusId,
		if line then ", released as " .. line.label else "", overall, table.concat(stats, ", "), quality,
		if #weak > 0 then " You are weak at " .. table.concat(weak, ", ") .. ": keep those answers basic." else "", TONE[focusId])
	local seed = EmployeeConfig.hash(PhoneMath.textHash(tostring(model.id))) % 2147483647
	return prompt, TEMPERATURE[focusId], 0.9, seed
end

-- small deterministic string hash (FNV-1a style, 32 bit)
function PhoneMath.textHash(s: string): number
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = (h * 16777619) % 4294967296
	end
	return h
end

local function tier(v: number): number
	return if v >= 70 then 3 elseif v >= 45 then 2 else 1
end

-- what a chat message asks for (lower-case keyword match)
function PhoneMath.intent(text: string): string
	local t = " " .. string.lower(text) .. " "
	local function has(...: string): boolean
		for _, w in { ... } do if string.find(t, w, 1, true) then return true end end
		return false
	end
	if string.match(t, "%d+%.?%d*%s*[%+%-%*x/]%s*%d+") or has("calculate", "math", "sum of", "plus", "minus", "times") then return "math" end
	if has("code", "script", "python", "lua", "function", "program", "bug") then return "code" end
	if has("joke", "funny", "laugh") then return "joke" end
	if has("poem", "story", "rhyme", "song", "haiku") then return "story" end
	if has("who are you", "what are you", "your name", "about you", "yourself", "introduce") then return "who" end
	if has("thank", "thx", "great job", "nice") then return "thanks" end
	if has(" hi ", " hey", "hello", "good morning", "hallo", " yo ") then return "greet" end
	if has("what", "why", "how", "explain", "when", "where", "?") then return "fact" end
	return "other"
end

local function pick(list: { string }, seed: number): string
	return list[(seed % #list) + 1]
end

local function numberText(n: number): string
	if math.abs(n - math.round(n)) < 1e-9 then return tostring(math.round(n)) end
	return string.format("%.2f", n)
end

-- first "a op b" of a text: (a, op, b, result) or nil
function PhoneMath.sum(text: string): (number?, string?, number?, number?)
	local a, op, b = string.match(string.lower(text), "(%-?%d+%.?%d*)%s*([%+%-%*x/])%s*(%-?%d+%.?%d*)")
	local x, y = tonumber(a), tonumber(b)
	if not (x and y and op) then return nil, nil, nil, nil end
	local r
	if op == "+" then r = x + y elseif op == "-" then r = x - y elseif op == "*" or op == "x" then r = x * y
	elseif y ~= 0 then r = x / y else return nil, nil, nil, nil end
	return x, op, y, r
end

-- Offline demo reply (always shown with the label PhoneMath.DEMO_LABEL): authored templates filled with the
-- model's REAL stats; deterministic for (model, text, turn). Better stats -> better answers.
function PhoneMath.demoReply(model: any, company: string?, text: string, turn: number): string
	local name = tostring(model.name)
	local version = math.floor(tonumber(model.version) or 1)
	local owner = if company and company ~= "" then company else "my company"
	local size = ModelConfig.getSize(tostring(model.sizeId))
	local focus = ModelConfig.getFocus(tostring(model.focusId))
	local overall = math.floor(tonumber(model.overall) or 0)
	local best, bestV, worst, worstV = PhoneMath.bestWorst(model)
	local seed = EmployeeConfig.hash(PhoneMath.textHash(tostring(model.id) .. "|" .. string.lower(text)) + turn * 7919)
	local general = tier(overall)
	local kind = PhoneMath.intent(text)
	local function low(s: string): string return if general == 1 then string.lower(s) else s end
	if kind == "greet" then
		return low(pick(if general == 3 then {
			"Hello! I'm " .. name .. " v" .. version .. " from " .. owner .. ". Ask me anything - I'm strongest at " .. string.lower(best) .. ".",
			"Hi there! " .. name .. " here, ready to help. What are we working on today?",
		} elseif general == 2 then {
			"Hi! I'm " .. name .. ". What can I do for you?",
			"Hello! " .. name .. " v" .. version .. " here. How can I help?",
		} else {
			"Hi. I am " .. name .. ". I am a small model, still learning.",
			"Hello... I am " .. name .. ". I try my best.",
		}, seed))
	elseif kind == "who" then
		return low(string.format("I'm %s v%d, a %s %s model made by %s. My overall score is %d: best at %s (%d), weakest at %s (%d).",
			name, version, if size then size.label else "small", string.lower(if focus then focus.label else "balanced"), owner, overall, string.lower(best), bestV, string.lower(worst), worstV))
	elseif kind == "math" then
		local m = statValue(model, "math")
		local a, op, b, r = PhoneMath.sum(text)
		if a and op and b and r then
			local shown = (if op == "x" then "*" else op)
			if tier(m) == 3 then return numberText(a) .. " " .. shown .. " " .. numberText(b) .. " = " .. numberText(r) .. "." end
			if tier(m) == 2 then return "That should be " .. numberText(r) .. ". (Math " .. m .. ": I'd double-check bigger sums.)" end
			local off = (seed % 3) + 1
			return "Hmm... " .. numberText(a) .. " " .. shown .. " " .. numberText(b) .. " is " .. numberText(r + (if seed % 2 == 0 then off else -off)) .. "? My math score is only " .. m .. ", please check it."
		end
		return pick(if tier(m) == 3 then { "Give me the numbers and I'll work it out step by step.", "Sure - write the sum like 12 * 7 and I'll solve it." }
			else { "Math is hard for me (math " .. m .. "). Try a small sum like 3 + 4." }, seed)
	elseif kind == "code" then
		local c = statValue(model, "coding")
		if tier(c) == 3 then
			return pick({
				"Here's a clean Luau example:\nlocal function add(a, b)\n  return a + b\nend\nprint(add(2, 3)) -- 5",
				"Sure. Loop over a list in Luau:\nfor i, item in items do\n  print(i, item)\nend",
			}, seed)
		elseif tier(c) == 2 then
			return "Something like this should work:\nprint(\"Hello from " .. name .. "\")\nI can do simple scripts (coding " .. c .. ")."
		end
		return "code... maybe print(\"hello\")? sorry, coding is not my strength yet (coding " .. c .. ")."
	elseif kind == "story" then
		local cr = statValue(model, "creativity")
		if tier(cr) == 3 then
			return pick({
				"Servers hum beneath the moon,\na garage dream becomes a tower soon.\nEvery line of data, every spark -\n" .. owner .. " lights up the dark.",
				"Once, in a tiny garage, a model woke up and asked: \"What is a customer?\" A week later it had a thousand of them - and still no idea what lunch was.",
			}, seed)
		elseif tier(cr) == 2 then
			return "Here's a short one: A little model trained all night, and by morning it could finally say hello. The end!"
		end
		return "once there was a robot. it was nice. the end. (creativity " .. cr .. ")"
	elseif kind == "joke" then
		local cr = statValue(model, "creativity")
		if tier(cr) >= 2 then
			return pick({
				"Why did the neural network go to therapy? It had too many unresolved layers.",
				"I tried to tell a joke about overfitting - but it only worked on my training data.",
				"Why was the GPU so calm? It knew how to keep its cool(ing).",
			}, seed)
		end
		return "a joke... robot walks into a bar. ouch. (creativity " .. cr .. ")"
	elseif kind == "thanks" then
		return low(pick({ "You're welcome!", "Happy to help. That's what " .. owner .. " built me for." }, seed))
	elseif kind == "fact" then
		local k = math.max(statValue(model, "knowledge"), statValue(model, "reasoning"))
		if tier(k) == 3 then
			return "Good question. In demo mode I can't look things up, so here's my approach: break it into parts, check what we know, then test the simplest explanation first."
		elseif tier(k) == 2 then
			return "I'm not completely sure. In demo mode I only have prepared answers - ask me about myself, a joke, a poem, code or a quick sum."
		end
		return "i don't know that yet. maybe my next version will. (knowledge " .. statValue(model, "knowledge") .. ")"
	end
	local r = statValue(model, "reliability")
	if tier(r) >= 2 then
		return "I'm running in demo mode right now, so my answers come from a small set of prepared replies. Try: \"who are you\", \"tell me a joke\", \"write a poem\" or \"12 * 7\"."
	end
	return "...sorry, i did not understand. (demo mode)"
end

return PhoneMath
