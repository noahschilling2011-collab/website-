--!strict
-- Company phone, client side (package "phone"). Builds the phone's view model from REAL state and feeds
-- UI/Screens/Phone:
--   * messages: the company log (empire.deals.news) plus events derived from snapshot changes (PhoneMath):
--     who is sick / on vacation today, rack faults and fixes (live.compute.faults), new hires / leavers, goals
--     reached (EmpireMath.nextGoal); messages other packages send through PhoneService.message. Read state lives
--     in this session (everything that happened before you joined counts as read; nothing runs offline).
--   * calls: the call log of PhoneService (Notify PHONE_CALL + PhoneAction inbox), answers through the remote
--   * calendar: PhoneMath.calendar from tripList / accounts / the shuttle timetable + items of other packages
--   * AI chat: PhoneAction chat (server-side TextGenerator or labelled demo replies), history in memory only
-- The remote is used only for actions (chat, answers, contacts, settings, inbox/calendar refresh); badges update
-- from snapshot changes. Keyboard P / gamepad Y open the phone, gamepad B goes back. The phone hides while the
-- Computer or the intro is open and closes when a talk / interview / assistant / lift panel opens.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Ops = require(Shared.CompanyOps)
local PhoneMath = require(Shared.PhoneMath)
local EmpireMath = require(Shared.EmpireMath)
local Types = require(Shared.Types)
local State = require(script.Parent.StateController)
local Action = require(script.Parent.ActionController)
local UI = script.Parent.Parent.UI
local Toast = require(UI.Toast)
local Phone = require(UI.Screens.Phone)
local Computer = require(UI.Screens.Computer)
local Screens = require(UI.Phone.PhoneScreens)

type Message = PhoneMath.Message
type Snapshot = Types.Snapshot
type View = Screens.View

local Controller = {}

Controller.PANELS = { TalkPanel = true, PeopleInterview = true, PeopleAssistant = true, CampusLift = true, CampusSecurity = true }
Controller.CHAT_TURNS = 40 -- turns kept per model on the client (memory only)

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

local function hotels(): { [string]: string }?
	local ok, City = pcall(function(): any return require(Shared.Config.CityPlan) end)
	if ok and typeof(City) == "table" and City.CITY_HOTEL and City.INTL_HOTEL then
		return { city = tostring(City.CITY_HOTEL.name), abroad = tostring(City.INTL_HOTEL.name) }
	end
	return nil
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

------------------------------------------------------------------------------------------------ view
local function missedCount(): number
	local n = 0
	for _, c in calls do if (c.state == "missed" and c.seen ~= true) or c.state == "ringing" then n += 1 end end
	return n
end

-- full = the phone is (being) opened: calendar and chat models are rebuilt; closed, the badges are enough
local todayCache = { sig = "", line = nil :: string? }
local function buildView(snapshot: Snapshot, full: boolean): View
	local data = snapshot.data
	local e = data.empire
	local live = snapshot.live
	local clock = workspace:GetServerTimeNow()
	local day, hour = PhoneMath.now(e, clock)
	local goal = EmpireMath.nextGoal(data, live)
	local goalView = nil
	if goal then
		local progress, fraction = PhoneMath.goalProgress(goal)
		goalView = { text = tostring(goal.text), progress = progress, fraction = fraction }
	end
	local phones = Ops.heads(e) + Ops.opsPosts(e)
	local old = currentView
	local calendar = if full or not old then PhoneMath.calendar(data, live, clock, extraCalendar, shuttle(clock), hotels()) else old.calendar
	local models = if full or not old then PhoneMath.chatModels(data) else old.models
	-- "Today: 2 sick · ..." needs CompanyOps.presence of every role: only when the day, the team or the trips change
	local travelling = if typeof(live.ops) == "table" then tonumber(live.ops.travelling) or 0 else 0
	local tsig = tostring(prev.absence) .. ":" .. travelling
	if tsig ~= todayCache.sig then
		todayCache.sig = tsig
		todayCache.line = PhoneMath.todayLine(e, live)
	end
	return {
		company = if data.company then data.company.name else "",
		status = PhoneMath.clock(hour),
		dayText = "Day " .. day,
		today = day,
		dayLine = PhoneMath.dayLine(e, clock),
		todayLine = todayCache.line,
		goal = goalView,
		messages = messages,
		read = read,
		unread = PhoneMath.unread(messages, read),
		calls = calls,
		missed = missedCount(),
		results = results,
		dial = dial,
		calendar = calendar,
		models = models,
		chats = chats,
		settings = { autoTrips = settings.autoTrips, popups = settings.popups, saved = settings.saved },
		phones = phones,
		phoneCost = string.format("%d phone%s × %s per game day = %s/day (team and operations staff).", phones, if phones == 1 then "" else "s", Ops.money(Ops.PHONE), Ops.money(phones * Ops.PHONE)),
		stage = Ops.stageIndex(e),
		hooks = { itinerary = hooks.itinerary, driver = hooks.driver },
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

------------------------------------------------------------------------------------------------ snapshot -> messages
local function remerge()
	local derived: { Message } = {}
	for _, m in events do table.insert(derived, m) end
	messages = PhoneMath.merge({ newsList, derived, serverMessages })
end

local function fetchInbox()
	task.spawn(function()
		local ok, res = invoke({ action = "inbox" })
		if not ok then return end
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

local function fetchCalendar()
	task.spawn(function()
		local ok, res = invoke({ action = "calendar" })
		if ok and typeof(res.items) == "table" then
			extraCalendar = res.items
			publish()
		end
	end)
end

local function copyFaults(list: any): { any }
	local out = {}
	if typeof(list) == "table" then for _, f in list do if typeof(f) == "table" then table.insert(out, { slot = f.slot, gpu = f.gpu, since = f.since }) end end end
	return out
end

local function process(snapshot: Snapshot)
	lastSnapshot = snapshot
	local data = snapshot.data
	if not data.company then return end
	local e = data.empire
	local live = snapshot.live
	local clock = workspace:GetServerTimeNow()
	local day, hour = PhoneMath.now(e, clock)
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
		if c.id == call.id then calls[i] = call; return end
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
		chat = { turns = {}, waiting = false, last = -math.huge }
		chats[modelId] = chat
	end
	return chat
end

local function push(chat: any, turn: any)
	table.insert(chat.turns, turn)
	while #chat.turns > Controller.CHAT_TURNS do table.remove(chat.turns, 1) end
end

local function sendChat(modelId: string, text: string)
	local chat = chatOf(modelId)
	if chat.waiting then return end
	local clean = string.match(text, "^%s*(.-)%s*$") or ""
	if clean == "" then return end
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
	chats[modelId] = nil
	publish()
	task.spawn(invoke, { action = "chat", modelId = modelId, reset = true })
end

local deps: Screens.Deps = {
	markRead = markRead,
	readCalls = readCalls,
	answer = answer,
	dial = dialContact,
	setSetting = setSetting,
	sendChat = sendChat,
	resetChat = resetChat,
	openComputer = openComputer,
	close = function() Phone.close() end,
	refresh = function() publish(true) end,
}
Controller.deps = deps

------------------------------------------------------------------------------------------------ public client API
-- Open the phone (optionally on a screen: "messages" | "calls" | "calendar" | "contacts" | "chat" | "settings").
function Controller.open(screen: string?, arg: any?)
	Phone.open(screen, arg)
end
-- Open the chat with one of the player's released models (other UIs, e.g. a "Chat" button in the Market app).
function Controller.openChat(modelId: string)
	Controller.open("thread", modelId)
end

------------------------------------------------------------------------------------------------ notifications
local function onNotify(kind: string, payload: { [string]: any })
	if kind == "PHONE_CALL" and typeof(payload.id) == "string" then
		upsertCall(payload)
		publish()
		if Phone.isHidden() then
			Toast.show("info", tostring(payload.from) .. " called: " .. tostring(payload.title) .. ". Open your phone to call back.", 6)
		elseif settings.popups or Phone.isOpen() then
			Phone.incoming(payload)
		end
	elseif kind == "PHONE_UPDATE" then
		if payload.what == "calendar" then fetchCalendar() else fetchInbox() end
	end
end

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
	-- a talk / interview / assistant / lift panel closes the phone (they sit in the middle of the screen)
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
