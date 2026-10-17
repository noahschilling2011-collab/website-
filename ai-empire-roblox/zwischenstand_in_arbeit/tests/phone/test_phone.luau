--!nocheck
-- phone package, server + shared maths on the REAL modules (work/src in the mock):
--   PhoneMath: time formatting, company-log -> message mapping (also for the texts the real CompanyOps.step
--   writes), absences ("Mia is sick today"), rack faults, hires, goals, merge / unread badges, the calendar
--   from tripList / accounts / shuttle / extra items, call texts, the model system prompt and demo replies.
--   PhoneService: built-in calls (first client, pilot trip abroad, affordable office; baseline, missed calls),
--   answers + the itinerary hook, contacts (assistant briefing, reception, IT, driver + hook), settings,
--   calendar items / messages of other packages, the AI chat with a fake TextGenerator (success, context
--   token, error -> demo fallback + breaker, per-player and global limits, filter failure, long input, models
--   that are not released), the real TextGenerator class in the mock, and the remote's validation / limits.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_phone && cd tests/phone && ../../tools/luau test_phone.luau -a .gen_phone
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_phone")
local M = require("../../harness/mock")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local C = require("./common")
local check, near = C.check, C.near

local function body()
	local R = C.load(M)
	local PM, Ops = R.PhoneMath, R.Ops
	local Server = R.Server
	local Economy = M.require(Server.Services.EconomyService)

	------------------------------------------------------------------ time
	check("clock 08:00", PM.clock(8) == "08:00", PM.clock(8))
	check("clock 13:30", PM.clock(13.5) == "13:30", PM.clock(13.5))
	check("clock 23:59 (no rounding up to 24:00)", PM.clock(23.9999) == "23:59", PM.clock(23.9999))
	check("company day starts at 08:00 (minute 0)", PM.dayMinute(8) == 0 and PM.dayMinute(7.5) == 1410, PM.dayMinute(7.5))
	check("02:00 sorts after 23:00 of the same company day", PM.order(5, 2) > PM.order(5, 23) and PM.order(6, 9) > PM.order(5, 2))
	local e0 = { calendar = { day = 8 }, seconds = 1000 }
	local c10 = C.clockAt(10)
	check("status text Day 8 · 10:00", PM.statusText(e0, c10) == "Day 8 · 10:00", PM.statusText(e0, c10))
	local d1, h1 = PM.atPlay(e0, c10, 1000 + 1200)
	check("a deadline one game day ahead = next company day, same hour", d1 == 9 and near(h1, 10, 1e-6), tostring(d1) .. " " .. tostring(h1))
	local d2, h2 = PM.atPlay(e0, c10, 1000 + 450)
	check("+450 s from 10:00 = 15:00 same day", d2 == 8 and near(h2, 15, 1e-6), tostring(d2) .. " " .. tostring(h2))
	local d3 = PM.atPlay(e0, c10, 500)
	check("a past deadline maps to now", d3 == 8)
	check("when(): same day only the time, other day with the day", PM.when(8, 10.5, 8) == "10:30" and PM.when(9, 10.5, 8) == "Day 9 · 10:30")

	------------------------------------------------------------------ company log -> messages
	local dd, hh, tt = PM.parseNews("day 8 11:54: signed CloudDesk: pilot $9,000, $9,000/day")
	check("parseNews: stamp and text", dd == 8 and near(hh, 11.9, 1e-6) and tt == "signed CloudDesk: pilot $9,000, $9,000/day")
	local function cls(text) return { PM.classify(text) } end
	local cases = {
		{ "signed CloudDesk: pilot $9,000, $9,000/day", "Sales", "Signed CloudDesk", "good" },
		{ "lost Paper Studio (no check-in before the term ended)", "Sales", "Lost Paper Studio", "bad" },
		{ "visited Paper Studio: trust 52%", "Sales", "Back from Paper Studio", "info" },
		{ "renewed CloudDesk for 6 days", "Sales", "Renewed CloudDesk", "good" },
		{ "founder drives to CloudDesk: pilot, $80", "Travel desk", "You're visiting CloudDesk", "info" },
		{ "rep to Helix Research: pilot, flight + 2 nights, $2,520", "Travel desk", "Trip to Helix Research", "info" },
		{ "hosting Ledger Finance at the guest house: pilot, $240", "Guest house", "Hosting Ledger Finance", "info" },
		{ "HR hired Mia Chen (AI Researcher, fee $1,000)", "HR", "Welcome Mia Chen", "good" },
		{ "apprentice Leo Park graduated (skill 3, full wage)", "HR", "Leo Park graduated", "good" },
		{ "moved into the Startup Campus", "Company", "Moved into the Startup Campus", "good" },
		{ "Lab level 3: +1 core stat on future models", "Lab", "Lab level 3", "good" },
		{ "Save mode on: saving for the Startup Campus", "Finance", "Save mode on", "warn" },
		{ "Save mode off", "Finance", "Save mode off", "info" },
		{ "bought the company jet (2 pilots, $8,500/day)", "Company", "Company jet bought", "good" },
		{ "founder joined the Helix Research meeting (+15% trust)", "Sales", "You joined Helix Research", "good" },
		{ "cash below $0 for a whole day: trips and night shifts paused", "Finance", "Cash warning", "bad" },
		{ "cash recovered: everybody is back from unpaid leave", "Finance", "Cash recovered", "good" },
		{ "Nova v2 replaces Nova v1 (Consumer Chat, 90% of users move)", "Product", "Nova v2 is live", "good" },
		{ "Coder v1 launched as Developer API", "Product", "Coder v1 is live", "good" },
		{ "Nova v2: Servers 97 % full → Consumer Chat price raised to $10", "Pricing", "Nova v2", "info" },
	}
	for _, case in cases do
		local r = cls(case[1])
		check("classify: " .. case[1], r[1] == case[2] and r[2] == case[3] and r[4] == case[4], table.concat({ tostring(r[1]), tostring(r[2]), tostring(r[4]) }, " | "))
	end
	local r = cls("something brand new happened in the company today and it is long")
	check("classify: unknown text -> Company message, title shortened", r[1] == "Company" and #r[2] <= 42 and r[3] == "Something brand new happened in the company today and it is long", r[2])
	local msgs = PM.newsMessages({ news = { "day 3 10:00: renewed CloudDesk for 6 days", "day 3 10:00: signed Paper Studio: pilot $9,000, $9,000/day", "day 2 17:00: Save mode off", 42 } })
	check("newsMessages: one message per string line", #msgs == 3)
	local merged = PM.merge({ msgs })
	check("merge: newest first, same minute keeps the log order", merged[1].title == "Renewed CloudDesk" and merged[2].title == "Signed Paper Studio" and merged[3].title == "Save mode off")
	check("merge: cap", #PM.merge({ msgs }, 2) == 2)
	local read = { [merged[1].key] = true }
	check("unread count", PM.unread(merged, read) == 2)
	check("merge: one message per key", #PM.merge({ msgs, msgs }) == 3)

	-- the texts the REAL CompanyOps.step writes all map to a known sender (no "Company" fallback)
	local d = C.company({ stage = 1, money = 20000, models = { { stats = { reliability = 30, creativity = 31 } } } })
	local s = C.session(d)
	for i = 1, 245 do C.step(s, Economy, C.clockAt(22)) end
	for i = 1, 500 do C.step(s, Economy, C.clockAt(9)) end
	local real = PM.newsMessages(d.empire.deals)
	local unknown = {}
	for _, m in real do if m.from == "Company" then table.insert(unknown, m.title) end end
	check("real company log produced lines", #real >= 3, #real)
	check("every real company-log line has a known sender", #unknown == 0, table.concat(unknown, " / "))
	check("real log: the first signing is a Sales message", C.find(real, function(m) return m.title == "Signed CloudDesk" and m.from == "Sales" end) ~= nil)
	check("real log: stamps parsed (day >= 1)", C.find(real, function(m) return m.day < 1 end) == nil)

	------------------------------------------------------------------ absences
	local big = C.company({ stage = 3, staff = { researcher = 20, engineer = 20, curator = 20, marketer = 20 } })
	local be = big.empire
	local sickDay, quietDay = nil, nil
	for day = 1, 60 do
		be.calendar.day = day
		local sick, vac, trip, leave = PM.absences(be)
		if #sick == 1 and not sickDay then sickDay = day end
		if #sick == 0 and #vac == 0 and leave == 0 and not quietDay then quietDay = day end
	end
	check("found a day with exactly one sick colleague", sickDay ~= nil)
	if sickDay then
		be.calendar.day = sickDay
		local m = PM.absenceMessage(be)
		local sick = PM.absences(be)
		local name = string.match(sick[1], "^(.-) %(")
		check("absence message: 'Mia is sick today' with the real profile name", m and m.title == name .. " is sick today" and m.from == "HR", m and m.title)
		local found = false
		for _, role in R.EmpireConfig.ROLES do
			for i, state in Ops.presence(be, role.id) do
				if state == "sick" and be.staffProfiles[role.id][i].n == name then found = true end
			end
		end
		check("the sick name is the profile CompanyOps.presence marks sick", found)
		check("absence message key is per company day", m and m.key == "absence:" .. sickDay)
	end
	if quietDay then
		be.calendar.day = quietDay
		check("nobody absent -> no absence message", PM.absenceMessage(be) == nil)
	else
		check("found a day without absences (80 staff, 60 days)", true)
	end
	local tiny = C.company({ stage = 1 })
	check("no staff -> no absence message", PM.absenceMessage(tiny.empire) == nil)
	check("no staff -> no today line", PM.todayLine(tiny.empire, { ops = { travelling = 0 } }) == nil)
	check("today line counts trips under way", PM.todayLine(tiny.empire, { ops = { travelling = 2 } }) == "Today: 2 trips under way", PM.todayLine(tiny.empire, { ops = { travelling = 2 } }))

	------------------------------------------------------------------ faults, hires, goals
	local fe = PM.faultEvents({}, { { slot = 3, gpu = "workstation", since = 120 } }, true, 4, 10)
	check("new rack fault -> IT desk message with slot, GPU name and the 60 s fix", #fe == 1 and fe[1].title == "Rack fault in slot 3" and string.find(fe[1].body, "Workstation", 1, true) ~= nil and string.find(fe[1].body, "60 s", 1, true) ~= nil, fe[1] and fe[1].body)
	local fe2 = PM.faultEvents({}, { { slot = 1, gpu = "workstation", since = 5 } }, false, 4, 10)
	check("fault without IT on duty says 5 min", string.find(fe2[1].body, "5 min", 1, true) ~= nil, fe2[1].body)
	local fx = PM.faultEvents({ { slot = 3, gpu = "workstation", since = 120 } }, {}, true, 4, 11)
	check("fixed fault -> 'Slot 3 fixed'", #fx == 1 and fx[1].title == "Slot 3 fixed" and fx[1].tone == "good")
	check("unchanged faults -> no message", #PM.faultEvents({ { slot = 3, gpu = "workstation", since = 120 } }, { { slot = 3, gpu = "workstation", since = 120 } }, true, 4, 11) == 0)
	local before = { ["researcher:11"] = "Ava Stone", ["engineer:12"] = "Ben Ray" }
	local now = { ["researcher:11"] = "Ava Stone", ["marketer:13"] = "Mia Chen", ["curator:14"] = "Leo Park" }
	local se = PM.staffEvents(before, now, { ["Leo Park"] = true }, 3, 9)
	local welcome = C.find(se, function(m) return m.title == "Welcome Mia Chen" end)
	check("new hire -> HR welcome with the role name", welcome and string.find(welcome.body, "Growth & Sales", 1, true) ~= nil)
	check("hire already announced in the log -> no second welcome", C.find(se, function(m) return m.title == "Welcome Leo Park" end) == nil)
	check("leaver -> 'Ben Ray left'", C.find(se, function(m) return m.title == "Ben Ray left" end) ~= nil)
	check("announcedHires reads 'HR hired' lines", PM.announcedHires({ news = { "day 2 09:00: HR hired Mia Chen (Growth & Sales, fee $1,200)" } })["Mia Chen"] == true)
	check("staffIndex keys role:seed", C.count(PM.staffIndex(big.empire)) == 80)
	local g = PM.goalEvent({ id = "train", text = "Train your first AI" }, { id = "release", text = "Release it" }, 1, 9)
	check("goal moved on -> 'Goal reached' with the next goal", g and g.title == "Goal reached: Train your first AI" and string.find(g.body, "Release it", 1, true) ~= nil)
	check("same goal -> no message", PM.goalEvent({ id = "train", text = "x" }, { id = "train", text = "x" }, 1, 9) == nil)
	check("no previous goal -> no message", PM.goalEvent(nil, { id = "train" }, 1, 9) == nil)
	local gp, frac = PM.goalProgress({ id = "office2", text = "Founder Headquarters $27,000", have = 12300, need = 27000, etaMinutes = 5.2 })
	check("goal progress money + ETA", gp == "$12,300 / $27,000 · ~6 min" and near(frac, 12300 / 27000, 1e-9), gp)
	check("goal progress ready", (PM.goalProgress({ id = "office3", have = 200000, need = 100000, etaMinutes = 0 })) == "$100,000 / $100,000 · ready")
	check("goal progress client trust", (PM.goalProgress({ id = "client", have = 50, need = 100 })) == "trust 50 %")

	------------------------------------------------------------------ calendar
	local cd = C.company({ stage = 4, money = 1e6, gpus = { datacenter = 1 }, staff = { marketer = 6, engineer = 6 }, models = { { stats = { math = 75 } } } })
	local cs = C.session(cd)
	C.step(cs, Economy, C.clockAt(10))
	local ce = cd.empire
	check("fixture: reps left for Helix (abroad), Ledger (hosted) and StudySpark (city)", #ce.deals.tripList == 3, #ce.deals.tripList)
	ce.deals.accounts.code = { expires = ce.seconds + 3 * 1200, since = 0 }
	local cal = PM.calendar(cd, cs.live, C.clockAt(10), { { key = "flight1", title = "Your flight PM 101", at = C.clockAt(14.5), kind = "flight" } },
		{ at = C.clockAt(11), flight = "PM 101", airline = "Meridian Air" }, { city = "City Hotel", abroad = "Meridian Grand Hotel" })
	local helix = C.find(cal, function(it) return string.find(it.title, "Helix Research", 1, true) ~= nil end)
	check("calendar: Helix trip with the hotel and the return day", helix and helix.now == true and string.find(helix.detail, "Meridian Grand Hotel", 1, true) ~= nil and string.find(helix.detail, "back Day", 1, true) ~= nil, helix and helix.detail)
	check("calendar: rep + engineer travel abroad", helix and string.find(helix.title, "Field rep + engineer", 1, true) ~= nil, helix and helix.title)
	local hosted = C.find(cal, function(it) return string.find(it.title, "guest house", 1, true) ~= nil end)
	check("calendar: hosted client team at the guest house", hosted ~= nil)
	local renew = C.find(cal, function(it) return it.key == "renew:code" end)
	check("calendar: ByteWorks check-in visit due with the retainer", renew and string.find(renew.detail, "$13,500/day", 1, true) ~= nil and string.find(renew.title, "ByteWorks", 1, true) ~= nil, renew and renew.detail)
	-- city trip: 0.2 days (240 s) -> check-in leaves (0.2 + 0.5) days before the end
	local dueDay, dueHour = PM.atPlay(ce, C.clockAt(10), ce.seconds + 3 * 1200 - 0.7 * 1200)
	check("calendar: check-in due = expires - (trip + 0.5) days", renew and renew.day == dueDay and near(renew.hour, dueHour, 1e-6))
	check("calendar: next shuttle listed", C.find(cal, function(it) return it.kind == "flight" and string.find(it.title, "Shuttle PM 101", 1, true) ~= nil end) ~= nil)
	check("calendar: item of another package listed", C.find(cal, function(it) return it.key == "item:flight1" end) ~= nil)
	check("calendar: trips under way come first", cal[1].now == true)
	local orderOk = true
	for i = 2, #cal do if not cal[i].now and not cal[i - 1].now and cal[i].order < cal[i - 1].order then orderOk = false end end
	check("calendar: upcoming items sorted by time", orderOk)
	local empty = PM.calendar(C.company({ stage = 1 }), { ops = {} }, C.clockAt(10), nil, nil, nil)
	check("calendar of a fresh garage company is empty", #empty == 0)
	check("day line before 15:00", PM.dayLine(ce, C.clockAt(10)) == "Office open until 18:00 · trips leave 08:00-15:00", PM.dayLine(ce, C.clockAt(10)))
	check("day line at night", string.find(PM.dayLine(ce, C.clockAt(22)), "^Night") ~= nil)

	------------------------------------------------------------------ call texts
	local t1, x1 = PM.firstClientCall("CloudDesk", 9000, { id = "office2", text = "Founder Headquarters $27,000" })
	check("first client call text: pilot fee, retainer, next goal", t1 == "First client signed!" and string.find(x1, "$9,000", 1, true) ~= nil and string.find(x1, "Founder Headquarters", 1, true) ~= nil, x1)
	local t2, x2 = PM.tripCall({ client = "Helix Research", tier = "abroad", rep = "Mia", engineer = "Leo", backDay = 9, backHour = 10.5, today = 8, hotel = "Meridian Grand Hotel", jet = false, flight = "PM 101 at 14:30" })
	check("trip call (abroad): request-24 itinerary text with real names, flight, hotel, return",
		t2 == "Helix Research wants to meet" and string.find(x2, "Port Meridian", 1, true) and string.find(x2, "Mia from Growth & Sales", 1, true) and string.find(x2, "Leo from Engineering", 1, true)
			and string.find(x2, "PM 101 at 14:30", 1, true) and string.find(x2, "2 nights at the Meridian Grand Hotel", 1, true) and string.find(x2, "on Day 9 · 10:30", 1, true), x2)
	local _, x3 = PM.tripCall({ client = "Helix Research", tier = "abroad", backDay = 8, backHour = 16, today = 8, hotel = "Meridian Grand Hotel", jet = true })
	check("trip call with the jet: 1 night, no names -> generic travellers", string.find(x3, "company jet", 1, true) and string.find(x3, "1 night", 1, true) and string.find(x3, "A field rep", 1, true) and string.find(x3, "at 16:00", 1, true), x3)
	local _, x4 = PM.tripCall({ client = "Ledger Finance", tier = "region", rep = "Mia", backDay = 9, backHour = 10, today = 8, hotel = "City Hotel", jet = false })
	check("trip call (region): City Hotel night", string.find(x4, "Business City", 1, true) and string.find(x4, "1 night at the City Hotel", 1, true), x4)
	local t5, x5 = PM.officeCall("Founder Headquarters", 27000)
	check("office call text", t5 == "We can move!" and string.find(x5, "$27,000", 1, true) ~= nil)

	------------------------------------------------------------------ model chat maths
	local weak = { id = "w1", name = "Pebble", version = 1, sizeId = "s100m", focusId = "balanced", status = "live", overall = 31,
		stats = { reasoning = 30, coding = 22, math = 25, creativity = 35, knowledge = 33, reliability = 38, speed = 90, efficiency = 90 }, release = { target = "general" } }
	local strong = { id = "s1", name = "Atlas", version = 3, sizeId = "s3b", focusId = "coding", status = "live", overall = 82,
		stats = { reasoning = 80, coding = 91, math = 78, creativity = 70, knowledge = 81, reliability = 84, speed = 60, efficiency = 58 }, release = { target = "developers" } }
	local p1, temp1, topP1, seed1 = PM.systemPrompt(weak, "Nimbus Labs")
	check("system prompt: name, version, company, size, overall", string.find(p1, "Pebble v1", 1, true) and string.find(p1, "Nimbus Labs", 1, true) and string.find(p1, "Size 100M", 1, true) and string.find(p1, "Overall score 31", 1, true), p1)
	check("system prompt: real core stats", string.find(p1, "Coding 22", 1, true) and string.find(p1, "Reliability 38", 1, true))
	check("system prompt: weak model answers like a weak model", string.find(p1, "tiny early model", 1, true) and string.find(p1, "weak at reasoning, coding, math", 1, true), p1)
	check("system prompt: product line", string.find(p1, "Consumer Chat", 1, true) ~= nil)
	local p2, temp2 = PM.systemPrompt(strong, "Nimbus Labs")
	check("system prompt: strong coding model -> frontier + technical tone, no weakness", string.find(p2, "excellent frontier model", 1, true) and string.find(p2, "technical", 1, true) and not string.find(p2, "weak at", 1, true), p2)
	check("temperature by focus (coding 0.4, balanced 0.7), TopP 0.9", near(temp2, 0.4) and near(temp1, 0.7) and near(topP1, 0.9))
	check("seed deterministic per model", seed1 == select(4, PM.systemPrompt(weak, "Nimbus Labs")) and seed1 ~= select(4, PM.systemPrompt(strong, "Nimbus Labs")))
	check("system prompt asks for short, all-ages replies", string.find(p1, "under 80 words", 1, true) and string.find(p1, "suitable for all ages", 1, true))
	check("intent: math", PM.intent("what is 12 * 7") == "math" and PM.intent("12x7") == "math")
	check("intent: code / joke / story / who / greet / thanks / fact / other", PM.intent("write a lua script") == "code" and PM.intent("tell me a joke") == "joke" and PM.intent("write a poem") == "story"
		and PM.intent("who are you?") == "who" and PM.intent("hello") == "greet" and PM.intent("thanks!") == "thanks" and PM.intent("why is the sky blue") == "fact" and PM.intent("banana") == "other")
	local a = PM.demoReply(strong, "Nimbus Labs", "what is 12 * 7", 1)
	check("demo: strong math model computes correctly", string.find(a, "= 84", 1, true) ~= nil, a)
	local b = PM.demoReply(weak, "Nimbus Labs", "what is 12 * 7", 1)
	check("demo: weak math model gets it wrong and says its real math score", not string.find(b, " 84?", 1, true) and string.find(b, "math score is only 25", 1, true) ~= nil, b)
	check("demo: deterministic", PM.demoReply(weak, "Nimbus Labs", "what is 12 * 7", 1) == b)
	local who = PM.demoReply(strong, "Nimbus Labs", "who are you", 2)
	check("demo 'who': real size, focus, company, overall, best and worst stat", string.find(who, "Atlas v3", 1, true) and string.find(who, "3B coding", 1, true) and string.find(who, "Nimbus Labs", 1, true)
		and string.find(who, "overall score is 82", 1, true) and string.find(who, "coding (91)", 1, true) and string.find(who, "creativity (70)", 1, true), who)
	local code1 = PM.demoReply(weak, "Nimbus Labs", "write some code", 1)
	check("demo: weak coder admits it (real coding stat)", string.find(code1, "coding 22", 1, true) ~= nil, code1)
	check("demo: strong coder shows Luau", string.find(PM.demoReply(strong, "Nimbus Labs", "write some code", 1), "local", 1, true) ~= nil)
	check("demo: never claims to be real AI in fallback 'other'", string.find(PM.demoReply(strong, "Nimbus Labs", "banana", 1), "demo mode", 1, true) ~= nil)
	check("sum parser divide by zero -> nil", PM.sum("5 / 0") == nil)
	local list = PM.chatModels({ modelOrder = { "w1", "s1", "t1" }, models = { w1 = weak, s1 = strong, t1 = { id = "t1", name = "Draft", status = "trained", overall = 99 } } })
	check("chat models: released only, strongest live first", #list == 2 and list[1].id == "s1" and list[2].id == "w1")
	check("model line", PM.modelLine(strong) == "Atlas v3 · 3B · Coding · Developer API · 82 overall", PM.modelLine(strong))

	------------------------------------------------------------------ PhoneService
	local Remote = M.require(Server.Lib.Remote)
	local Session = M.require(Server.Services.SessionService)
	local Phone = M.require(Server.Services.PhoneService)
	Remote.setup()
	local notes = {}
	Remote.fire = function(player, name, kind, payload) if name == "Notify" then table.insert(notes, { player = player, kind = kind, payload = payload }) end end
	local CLOCK, T = C.clockAt(10), 1000
	local MODE, FILTER = "ok", function(text) return text end
	local gens = {}
	Phone._seams({
		clock = function() return CLOCK end,
		now = function() return T end,
		filter = function(text, uid) return FILTER(text, uid) end,
		generator = function(prompt, temperature, topP, seed)
			local g = { prompt = prompt, temperature = temperature, topP = topP, seed = seed, calls = {} }
			function g:GenerateTextAsync(req)
				table.insert(self.calls, req)
				if MODE == "error" then error("TextGenerator: experience is not eligible (test double)") end
				if MODE == "empty" then return { GeneratedText = "   " } end
				return { GeneratedText = "  Hi, I'm the real model (" .. #self.calls .. ")  ", ContextToken = "ctx" .. #self.calls, Model = "test" }
			end
			table.insert(gens, g)
			return g
		end,
	})
	Phone.init()
	local function lastNote(kind) for i = #notes, 1, -1 do if notes[i].kind == kind then return notes[i] end end return nil end
	local function callCount(kind) local n = 0 for _, x in notes do if x.kind == kind then n += 1 end end return n end

	-- first client: baseline, founder trip (no call), signing -> call
	local fd = C.company({ stage = 1, money = 20000, models = { { stats = { reliability = 30 } } } })
	local fs = C.session(fd, 2001)
	Phone.scan(fs)
	check("first scan only takes the baseline (no call)", callCount("PHONE_CALL") == 0)
	C.step(fs, Economy, C.clockAt(22))
	Phone.scan(fs)
	check("founder's own city trip -> no call", callCount("PHONE_CALL") == 0)
	for i = 1, 240 do C.step(fs, Economy, C.clockAt(22)) end
	check("fixture: CloudDesk signed", fd.empire.deals.signed == 1)
	Phone.scan(fs)
	local n1 = lastNote("PHONE_CALL")
	check("first signed client -> the assistant calls", n1 and n1.payload.title == "First client signed!" and n1.payload.from == "Assistant" and n1.payload.state == "ringing" and string.find(n1.payload.text, "CloudDesk", 1, true) ~= nil, n1 and n1.payload.title)
	check("call goes to the company's own player", n1 and n1.player == fs.player)
	Phone.scan(fs)
	check("no second first-client call", callCount("PHONE_CALL") == 1)
	CLOCK += 26
	local upd0 = callCount("PHONE_UPDATE")
	Phone.scan(fs)
	check("unanswered call is missed after 25 s", Phone.calls(fs)[1].state == "missed")
	local mu = lastNote("PHONE_UPDATE")
	check("the server tells the phone the call was missed (PHONE_UPDATE calls with the call)", callCount("PHONE_UPDATE") == upd0 + 1 and mu.payload.what == "calls" and mu.payload.call.id == n1.payload.id and mu.payload.call.state == "missed", mu and mu.payload.what)
	Phone.scan(fs)
	check("the missed notice is sent once", callCount("PHONE_UPDATE") == upd0 + 1)
	local ans = Phone._act(fs, { action = "call", id = n1.payload.id, answer = "accept" })
	check("a missed call can still be answered (call back)", ans.ok == true and ans.call.state == "accepted")
	check("answered twice -> NO_CALL", Phone._act(fs, { action = "call", id = n1.payload.id, answer = "accept" }).err == "NO_CALL")
	check("unknown call id -> NO_CALL", Phone._act(fs, { action = "call", id = "c999", answer = "accept" }).err == "NO_CALL")
	check("bad call id / answer -> BAD_INPUT", Phone._act(fs, { action = "call", id = "c1;drop", answer = "accept" }).err == "BAD_INPUT" and Phone._act(fs, { action = "call", id = "c1", answer = "maybe" }).err == "BAD_INPUT")

	-- trip abroad -> itinerary call (names, hotel, flight); hosted / city trips -> no call
	CLOCK = C.clockAt(10)
	local td = C.company({ stage = 4, money = 1e6, gpus = { datacenter = 1 }, staff = { marketer = 6, engineer = 6 }, models = { { stats = { math = 75 } } } })
	local ts = C.session(td, 2002)
	Phone.scan(ts)
	local before = callCount("PHONE_CALL")
	C.step(ts, Economy, CLOCK)
	Phone.scan(ts)
	check("exactly one call for the three new trips (abroad yes; hosted + city no)", callCount("PHONE_CALL") == before + 1, callCount("PHONE_CALL") - before)
	local tc = lastNote("PHONE_CALL")
	local te = td.empire
	local rep = string.match(te.staffProfiles.marketer[1].n, "^(%S+)")
	local engName
	for i, st in R.Ops.presence(te, "engineer") do if st == "trip" then engName = string.match(te.staffProfiles.engineer[i].n, "^(%S+)") end end
	check("trip call: itinerary kind, client and Port Meridian", tc and tc.payload.kind == "itinerary" and tc.payload.title == "Helix Research wants to meet" and string.find(tc.payload.text, "Port Meridian", 1, true) ~= nil, tc and tc.payload.text)
	check("trip call names the real field rep and the travelling engineer", tc and string.find(tc.payload.text, rep .. " from Growth & Sales", 1, true) ~= nil and engName ~= nil and string.find(tc.payload.text, engName .. " from Engineering", 1, true) ~= nil, tc and tc.payload.text)
	check("trip call names the international hotel (CityPlan) and the next shuttle", tc and string.find(tc.payload.text, "Meridian Grand Hotel", 1, true) ~= nil and string.find(tc.payload.text, "shuttle PM 101 at", 1, true) ~= nil, tc and tc.payload.text)
	check("trip call buttons", tc and tc.payload.accept == "Join the trip" and tc.payload.decline == "Not this time")
	local acc = Phone._act(ts, { action = "call", id = tc.payload.id, answer = "accept" })
	check("accept without the itinerary package -> honest 'travel desk opens soon'", acc.ok == true and acc.soon == true and string.find(acc.text, "travel desk opens soon", 1, true) ~= nil and string.find(acc.text, rep, 1, true) ~= nil, acc.text)
	-- with the hook of the later itinerary package
	local hooked = nil
	Phone.onAction("itinerary", function(sess, payload) hooked = { s = sess, p = payload }; return { ok = true, text = "Booked.", started = true } end)
	check("hasAction", Phone.hasAction("itinerary"))
	local cid = Phone.ring(ts, { title = "Helix Research wants to meet", text = "x", kind = "itinerary", data = { client = "helix" } })
	local acc2 = Phone._act(ts, { action = "call", id = cid, answer = "accept" })
	check("accept with a registered hook -> the hook runs with the trip data", hooked and hooked.s == ts and hooked.p.answer == "accept" and hooked.p.data.client == "helix" and acc2.started == true and acc2.text == "Booked.")
	local cid2 = Phone.ring(ts, { title = "t", text = "x", kind = "itinerary", data = { client = "helix" } })
	Phone._act(ts, { action = "call", id = cid2, answer = "decline" })
	check("decline is passed to the hook too", hooked.p.answer == "decline")
	Phone.onAction("itinerary", function() error("boom") end)
	local cid3 = Phone.ring(ts, { title = "t", text = "x", kind = "itinerary" })
	check("a failing hook -> SERVER_ERROR, no crash", Phone._act(ts, { action = "call", id = cid3, answer = "accept" }).err == "SERVER_ERROR")
	local ringing = 0
	local c1 = Phone.ring(ts, { title = "a", text = "a" })
	Phone.ring(ts, { title = "b", text = "b" })
	for _, c in Phone.calls(ts) do if c.state == "ringing" then ringing += 1 end end
	check("a new call turns the ringing one into a missed call", ringing == 1 and C.find(Phone.calls(ts), function(c) return c.id == c1 end).state == "missed")
	for i = 1, 30 do Phone.ring(ts, { title = "spam", text = "x" }) end
	check("call log capped at 20", #Phone.calls(ts) == 20)

	-- office affordable -> call once; already affordable at baseline -> no call
	local od = C.company({ stage = 1, money = 1000, models = { { stats = { reliability = 30 } } } })
	od.stats.modelsTrained, od.stats.modelsReleased, od.empire.contractsCompleted = 1, 1, 1
	local os_ = C.session(od, 2003)
	Phone.scan(os_)
	od.money = 200000
	Phone.scan(os_)
	local oc = lastNote("PHONE_CALL")
	check("enough cash for the next office -> 'We can move!' that opens the Company app", oc and oc.player == os_.player and oc.payload.kind == "office" and oc.payload.open == "empire" and string.find(oc.payload.text, "Founder Headquarters", 1, true) ~= nil, oc and oc.payload.text)
	check("the office call opens Company on the Office tab it names", oc and oc.payload.section == "office" and string.find(oc.payload.text, "Company → Office ", 1, true) ~= nil and oc.payload.accept == "Open Office", oc and (tostring(oc.payload.section) .. " / " .. oc.payload.text))
	local nb = callCount("PHONE_CALL")
	Phone.scan(os_)
	check("office call only once", callCount("PHONE_CALL") == nb)
	local rich = C.company({ stage = 1, money = 200000, models = { { stats = { reliability = 30 } } } })
	rich.stats.modelsTrained, rich.stats.modelsReleased, rich.empire.contractsCompleted = 1, 1, 1
	local rs = C.session(rich, 2004)
	Phone.scan(rs); Phone.scan(rs)
	check("affordable already at the baseline -> no call", callCount("PHONE_CALL") == nb)

	-- contacts
	local gd = C.company({ stage = 1, gpus = {} })
	local gs = C.session(gd, 2005)
	local recG = Phone._act(gs, { action = "call", contact = "reception" })
	check("reception in the garage: honest 'no reception yet'", recG.ok and string.find(recG.text, "no reception yet", 1, true) ~= nil, recG.text)
	local sd = C.company({ stage = 3, money = 1e5, gpus = { workstation = 3 } })
	sd.empire.applicants = { { st = "new" }, { st = "new" }, { st = "waiting" } }
	local ss = C.session(sd, 2006)
	local rec = Phone._act(ss, { action = "call", contact = "reception" })
	check("reception: real application counts and guest house rooms", string.find(rec.text, "2 applications are open, 1 candidate is waiting", 1, true) ~= nil and string.find(rec.text, "of 12 rooms", 1, true) ~= nil, rec.text)
	local it = Phone._act(ss, { action = "call", contact = "it" })
	check("IT desk: all rack GPUs running, on duty at 10:00", string.find(it.text, "All 3 rack GPUs are running. IT is on duty.", 1, true) ~= nil, it.text)
	local itG = Phone._act(gs, { action = "call", contact = "it" })
	check("IT desk in the garage: no rack GPUs yet", string.find(itG.text, "No rack GPUs", 1, true) ~= nil, itG.text)
	local drvG = Phone._act(gs, { action = "call", contact = "driver" })
	check("driver in the garage: starts at the Founder HQ", drvG.ok and drvG.soon and string.find(drvG.text, "Founder Headquarters", 1, true) ~= nil, drvG.text)
	local drv = Phone._act(ss, { action = "call", contact = "driver" })
	check("driver at stage 3: on the payroll ($720/day), rides coming soon", string.find(drv.text, "$720/day", 1, true) ~= nil and string.find(drv.text, "coming soon", 1, true) ~= nil, drv.text)
	Phone.onAction("driver", function(sess, payload) return { ok = true, text = "Your driver is on the way.", eta = 30 } end)
	local drvH = Phone._act(ss, { action = "call", contact = "driver" })
	check("driver hook of the later package answers", drvH.text == "Your driver is on the way." and drvH.eta == 30 and drvH.contact == "driver")
	local na = #notes
	local asst = Phone._act(ss, { action = "call", contact = "assistant" })
	local an = lastNote("ASSISTANT_OPEN")
	check("assistant contact opens her briefing (Notify ASSISTANT_OPEN with the real briefing)", asst.ok == true and #notes > na and an and an.player == ss.player and typeof(an.payload.sections) == "table" and typeof(an.payload.name) == "string", asst.err)
	check("unknown contact -> BAD_INPUT", Phone._act(ss, { action = "call", contact = "pizza" }).err == "BAD_INPUT")

	-- settings
	-- integrate (phone request 1): EmpireMath.new / Template now give every save empire.prefs = {autoTrips = false},
	-- so the default company saves the setting; the session-only fallback is tested with prefs removed
	check("new saves carry empire.prefs = {autoTrips = false} (phone request 1)", typeof(sd.empire.prefs) == "table" and sd.empire.prefs.autoTrips == false)
	local savedPrefs = sd.empire.prefs
	sd.empire.prefs = nil
	local st0 = Phone._act(ss, { action = "inbox" })
	check("setting default: join trips automatically = off", st0.settings.autoTrips == false and st0.saved == false)
	local st1 = Phone._act(ss, { action = "setting", key = "autoTrips", value = true })
	check("setting stored for the session (save without empire.prefs)", st1.ok and st1.settings.autoTrips == true and st1.saved == false and Phone.setting(ss, "autoTrips") == true)
	sd.empire.prefs = savedPrefs
	local st2 = Phone._act(ss, { action = "setting", key = "autoTrips", value = false })
	check("with empire.prefs the setting is saved there", st2.saved == true and sd.empire.prefs.autoTrips == false and Phone.setting(ss, "autoTrips") == false)
	check("bad setting key / value -> BAD_INPUT", Phone._act(ss, { action = "setting", key = "money", value = true }).err == "BAD_INPUT" and Phone._act(ss, { action = "setting", key = "autoTrips", value = "yes" }).err == "BAD_INPUT")

	-- calendar items and messages of other packages
	local un = callCount("PHONE_UPDATE")
	check("addCalendarItem", Phone.addCalendarItem(ss, { key = "itin1", title = "Flight PM 101", at = CLOCK + 300, kind = "flight" }) == true and callCount("PHONE_UPDATE") == un + 1)
	local cu = lastNote("PHONE_UPDATE")
	check("PHONE_UPDATE carries the new calendar item (no refetch needed)", cu.payload.what == "calendar" and cu.payload.item and cu.payload.item.key == "itin1" and cu.payload.item.title == "Flight PM 101" and cu.payload.item.at == CLOCK + 300)
	Phone.addCalendarItem(ss, { key = "itin1", title = "Flight PM 102", at = CLOCK + 300 })
	local calr = Phone._act(ss, { action = "calendar" })
	check("same key replaces the item", #calr.items == 1 and calr.items[1].title == "Flight PM 102")
	check("item without key/title refused", Phone.addCalendarItem(ss, { title = "x" }) == false)
	for i = 1, 30 do Phone.addCalendarItem(ss, { key = "k" .. i, title = "t" .. i, day = 3, hour = 9 }) end
	check("calendar items capped at 24", #Phone._act(ss, { action = "calendar" }).items == 24)
	Phone.removeCalendarItem(ss, "k30")
	check("removeCalendarItem", #Phone._act(ss, { action = "calendar" }).items == 23)
	check("PHONE_UPDATE names the removed item", lastNote("PHONE_UPDATE").payload.removed == "k30")
	Phone.message(ss, { from = "Travel desk", title = "Your driver is waiting", text = "At the main entrance." })
	local mm = lastNote("PHONE_UPDATE")
	check("PHONE_UPDATE carries the new message", mm.payload.what == "messages" and mm.payload.message and mm.payload.message.title == "Your driver is waiting" and mm.payload.message.body == "At the main entrance.")
	local inbox = Phone._act(ss, { action = "inbox" })
	check("message of another package in the inbox", inbox.messages[1] and inbox.messages[1].title == "Your driver is waiting" and inbox.messages[1].from == "Travel desk")
	check("inbox lists the call log and whether hooks exist", typeof(inbox.calls) == "table" and inbox.hooks.driver == true)
	check("read calls marks missed calls seen", Phone._act(ts, { action = "read", what = "calls" }).ok and C.find(Phone.calls(ts), function(c) return not c.seen end) == nil)
	check("read: bad 'what' -> BAD_INPUT", Phone._act(ts, { action = "read", what = "everything" }).err == "BAD_INPUT")

	------------------------------------------------------------------ AI chat (fake TextGenerator)
	local md = C.company({ stage = 2, money = 50000, models = {
		{ id = "nova", name = "Nova", version = 2, sizeId = "s1b", stats = { reasoning = 63, coding = 55, math = 54, creativity = 71, knowledge = 66, reliability = 60, speed = 76, efficiency = 74 } },
		{ id = "draft", name = "Draft", status = "trained", base = 50 },
	} })
	local ms = C.session(md, 2007)
	local money0, ledger0 = md.money, C.count(md.empire.ledger)
	local res1 = Phone._act(ms, { action = "chat", modelId = "nova", text = "  Hello   there " })
	check("chat: TextGenerator reply returned trimmed, labelled 'AI reply'", res1.ok and res1.source == "ai" and res1.reply == "Hi, I'm the real model (1)" and res1.label == "AI reply", res1.reply or res1.err)
	local g1 = gens[#gens]
	check("chat: request keys UserPrompt (cleaned text) + MaxTokens 200, no ContextToken at first", g1.calls[1].UserPrompt == "Hello there" and g1.calls[1].MaxTokens == 200 and g1.calls[1].ContextToken == nil)
	check("chat: system prompt from the model's real data", string.find(g1.prompt, "Nova v2", 1, true) and string.find(g1.prompt, "Nimbus Labs", 1, true) and string.find(g1.prompt, "Creativity 71", 1, true) and string.find(g1.prompt, "Size 1B", 1, true), g1.prompt)
	check("chat: the shown user text is the filtered text", res1.user == "Hello there")
	local cd2 = Phone._act(ms, { action = "chat", modelId = "nova", text = "again" })
	check("chat: 1 request per 4 s per player", cd2.err == "CHAT_COOLDOWN" and cd2.wait == 4, cd2.err)
	T += 4
	local res2 = Phone._act(ms, { action = "chat", modelId = "nova", text = "again" })
	check("chat: second turn sends the ContextToken of the first reply", res2.ok and g1.calls[2].ContextToken == "ctx1" and #gens == 1, #gens)
	-- 10 per minute
	local limited = nil
	for i = 3, 11 do
		T += 4.1
		local rr = Phone._act(ms, { action = "chat", modelId = "nova", text = "msg " .. i })
		if not rr.ok then limited = rr; break end
	end
	check("chat: at most 10 requests per minute per player", limited and limited.err == "CHAT_COOLDOWN" and #Phone._state(ms).times == 10, limited and limited.err)
	T += 60
	-- error -> demo fallback + breaker
	MODE = "error"
	local calls0 = #g1.calls
	local res3 = Phone._act(ms, { action = "chat", modelId = "nova", text = "who are you" })
	check("chat: TextGenerator error -> demo reply labelled 'Demo reply (offline)'", res3.ok and res3.source == "demo" and res3.reason == "error" and res3.label == "Demo reply (offline)" and string.find(res3.reply, "Nova v2", 1, true) ~= nil, res3.reply)
	check("chat: the demo reply uses the model's real stats", string.find(res3.reply, "overall score is " .. math.floor(md.models.nova.overall), 1, true) ~= nil, res3.reply)
	T += 5
	local res4 = Phone._act(ms, { action = "chat", modelId = "nova", text = "tell me a joke" })
	check("chat: breaker -> demo 'offline' without calling TextGenerator again", res4.ok and res4.source == "demo" and res4.reason == "offline" and #g1.calls == calls0 + 1)
	MODE = "ok"
	T += 31
	local res5 = Phone._act(ms, { action = "chat", modelId = "nova", text = "hello" })
	check("chat: after the breaker time TextGenerator is used again", res5.ok and res5.source == "ai", res5.reason)
	MODE = "empty"
	T += 5
	local res6 = Phone._act(ms, { action = "chat", modelId = "nova", text = "hello" })
	check("chat: empty generated text -> demo", res6.source == "demo" and res6.reason == "empty")
	MODE = "ok"
	Phone._reset()
	-- filter
	T += 5
	FILTER = function() return nil end
	local gc = #g1.calls
	local f1 = Phone._act(ms, { action = "chat", modelId = "nova", text = "hello" })
	check("chat: filter unavailable -> FILTER_DOWN, nothing sent", f1.err == "FILTER_DOWN" and #g1.calls == gc)
	T += 5
	FILTER = function(text) return string.rep("#", #text) end
	local f2 = Phone._act(ms, { action = "chat", modelId = "nova", text = "badword" })
	local up = g1.calls[#g1.calls].UserPrompt
	check("chat: the model gets and the player sees the filtered text", f2.ok and f2.user == "#######" and string.sub(up, -7) == "#######" and not string.find(up, "badword", 1, true), up)
	FILTER = function(text) return text end
	-- input validation
	T += 5
	check("chat: 201 characters -> TOO_LONG", Phone._act(ms, { action = "chat", modelId = "nova", text = string.rep("a", 201) }).err == "TOO_LONG")
	check("chat: 200 characters accepted", Phone._act(ms, { action = "chat", modelId = "nova", text = string.rep("a", 200) }).ok == true)
	T += 5
	check("chat: empty / whitespace -> BAD_INPUT", Phone._act(ms, { action = "chat", modelId = "nova", text = "   " }).err == "BAD_INPUT")
	check("chat: control characters -> BAD_INPUT", Phone._act(ms, { action = "chat", modelId = "nova", text = "hi\0there" }).err == "BAD_INPUT")
	check("chat: non-string -> BAD_INPUT", Phone._act(ms, { action = "chat", modelId = "nova", text = { 1 } }).err == "BAD_INPUT")
	check("chat: model not released -> NO_MODEL", Phone._act(ms, { action = "chat", modelId = "draft", text = "hi" }).err == "NO_MODEL")
	check("chat: unknown model -> NO_MODEL", Phone._act(ms, { action = "chat", modelId = "ghost", text = "hi" }).err == "NO_MODEL")
	check("chat: bad model id -> BAD_INPUT", Phone._act(ms, { action = "chat", modelId = "../x", text = "hi" }).err == "BAD_INPUT")
	-- global budget (all players together)
	Phone._reset()
	local busy = nil
	for i = 1, 100 do
		local u = C.session(md, 5000 + i)
		local rr = Phone._act(u, { action = "chat", modelId = "nova", text = "hi " .. i })
		if rr.ok and rr.reason == "busy" then busy = i; break end
	end
	check("chat: the server keeps below 100 TextGenerator requests per minute (91st -> demo 'busy')", busy == 91, busy)
	Phone._reset()
	-- memory only, no economy
	local cs2 = Phone._state(ms).chat.nova
	check("chat: history kept in memory, capped", cs2 and #cs2.turns <= 20 and #cs2.turns > 0)
	check("chat: reset clears the conversation", Phone._act(ms, { action = "chat", modelId = "nova", reset = true }).reset == true and Phone._state(ms).chat.nova == nil)
	check("chat: no economic effect (money and ledger unchanged)", md.money == money0 and C.count(md.empire.ledger) == ledger0)
	check("chat: nothing saved in the player data", md.empire.chat == nil and md.empire.phone == nil)

	-- the real TextGenerator class in the mock (property names checked against the API dump)
	Phone._seams({ generator = nil })
	local ok, gen = pcall(function()
		local g = Instance.new("TextGenerator")
		g.SystemPrompt = "x"; g.Temperature = 0.7; g.TopP = 0.9; g.Seed = 5
		return g
	end)
	check("TextGenerator exists with SystemPrompt / Temperature / TopP / Seed (API dump)", ok and gen.ClassName == "TextGenerator", gen)

	------------------------------------------------------------------ review round 1: breakers per player, context, recap
	do
	Phone._reset()
	local BAD = {}
	local ERRTEXT = "TextGenerator: request blocked (test double)"
	local tg = {}
	Phone._seams({
		generator = function(prompt, temperature, topP, seed)
			local g = { prompt = prompt, calls = {} }
			function g:GenerateTextAsync(req)
				table.insert(self.calls, req)
				if BAD[req.UserPrompt] or BAD[string.match(req.UserPrompt, "The player now says: (.*)$") or ""] then error(ERRTEXT) end
				return { GeneratedText = "ok " .. #self.calls, ContextToken = "tok" .. #self.calls }
			end
			table.insert(tg, g)
			return g
		end,
	})
	local spec = { { id = "nova", name = "Nova", version = 2, sizeId = "s1b", stats = { reasoning = 63, coding = 55, math = 54, creativity = 71, knowledge = 66, reliability = 60, speed = 76, efficiency = 74 } } }
	local att = C.session(C.company({ stage = 2, models = spec }), 3101)
	local vic = C.session(C.company({ stage = 2, models = spec }), 3102)
	local third = C.session(C.company({ stage = 2, models = spec }), 3103)
	BAD["blocked text"] = true
	T += 100
	local a1 = Phone._act(att, { action = "chat", modelId = "nova", text = "blocked text" })
	check("breaker: a refused prompt -> labelled demo for that player", a1.ok and a1.source == "demo" and a1.reason == "error" and a1.label == PM.DEMO_LABEL)
	T += 5
	local v1 = Phone._act(vic, { action = "chat", modelId = "nova", text = "hello" })
	check("breaker: another player 5 s later still gets the AI (one player's error never switches it off for everybody)", v1.ok and v1.source == "ai", tostring(v1.source) .. "/" .. tostring(v1.reason))
	local a2 = Phone._act(att, { action = "chat", modelId = "nova", text = "a normal question" })
	check("breaker: the failing player himself gets demo replies for a while (no TextGenerator call)", a2.ok and a2.source == "demo" and a2.reason == "offline")
	T += Phone.PLAYER_BREAKER_BASE + 1
	local a3 = Phone._act(att, { action = "chat", modelId = "nova", text = "a normal question" })
	check("breaker: after his pause the player gets the AI again", a3.ok and a3.source == "ai", tostring(a3.source) .. "/" .. tostring(a3.reason))
	-- sustained: the attacker re-sends a refused prompt whenever he may; the victim asks every 6.5 s for 30 min
	Phone._reset()
	local aiN, demoN, t0 = 0, 0, T
	while T - t0 < 1800 do
		Phone._act(att, { action = "chat", modelId = "nova", text = "blocked text" })
		local rv = Phone._act(vic, { action = "chat", modelId = "nova", text = "hi " .. math.floor(T) })
		if rv.ok then if rv.source == "ai" then aiN += 1 else demoN += 1 end end
		T += 6.5
	end
	check("breaker: 30 min of refused prompts by one player -> the other player only ever gets AI replies", aiN > 200 and demoN == 0, aiN .. " ai / " .. demoN .. " demo")
	-- the global breaker: request errors of 2 different players within 60 s (no success between)
	Phone._reset()
	T += 100
	BAD["bad b"] = true
	Phone._act(att, { action = "chat", modelId = "nova", text = "blocked text" })
	T += 10
	Phone._act(vic, { action = "chat", modelId = "nova", text = "bad b" })
	T += 5
	local g3 = Phone._act(third, { action = "chat", modelId = "nova", text = "hello" })
	check("global breaker: errors of 2 different players within 60 s -> everybody gets the offline demo", g3.ok and g3.source == "demo" and g3.reason == "offline", tostring(g3.reason))
	T += Phone.BREAKER_BASE + 1
	check("global breaker: closes again after BREAKER_BASE s", Phone._act(third, { action = "chat", modelId = "nova", text = "hello again" }).source == "ai")
	Phone._reset()
	T += 100
	Phone._act(att, { action = "chat", modelId = "nova", text = "blocked text" })
	T += 5
	Phone._act(third, { action = "chat", modelId = "nova", text = "fine" }) -- a success in between
	T += 5
	Phone._act(vic, { action = "chat", modelId = "nova", text = "bad b" })
	T += 5
	local fourth = C.session(C.company({ stage = 2, models = spec }), 3104)
	check("global breaker: a success clears the error log (A fails, C succeeds, B fails -> D still gets the AI)", Phone._act(fourth, { action = "chat", modelId = "nova", text = "hello" }).source == "ai")
	Phone._reset()
	T += 100
	ERRTEXT = "TextGenerator is not available for this experience (test double)"
	BAD["any"] = true
	Phone._act(att, { action = "chat", modelId = "nova", text = "any" })
	T += 5
	check("global breaker: 'not available' errors open it at once (TextGenerator does not work here)", Phone._act(fourth, { action = "chat", modelId = "nova", text = "hi there" }).reason == "offline")
	ERRTEXT = "TextGenerator: request blocked (test double)"
	BAD = {}
	Phone._reset()
	T += 100
	local fresh = C.session(C.company({ stage = 2, models = spec }), 3105)
	Phone._seams({ generator = function() error("Unable to create an Instance of type \"TextGenerator\"") end })
	Phone._act(fresh, { action = "chat", modelId = "nova", text = "hi" })
	T += 5
	local others = Phone._act(fourth, { action = "chat", modelId = "nova", text = "hi you" })
	check("global breaker: a generator that cannot be created opens it at once", others.reason == "offline", tostring(others.reason))
	Phone._reset()
	-- recap and context token
	Phone._seams({
		generator = function(prompt)
			local g = { prompt = prompt, calls = {} }
			function g:GenerateTextAsync(req)
				table.insert(self.calls, req)
				if BAD[string.match(req.UserPrompt, "The player now says: (.*)$") or req.UserPrompt] then error(ERRTEXT) end
				return { GeneratedText = "answer " .. #self.calls, ContextToken = "tok" .. #self.calls }
			end
			table.insert(tg, g)
			return g
		end,
	})
	local rd = C.company({ stage = 2, models = spec })
	local rs2 = C.session(rd, 3106)
	T += 100
	Phone._act(rs2, { action = "chat", modelId = "nova", text = "my name is Mia" })
	local gA = tg[#tg]
	T += 5
	Phone._act(rs2, { action = "chat", modelId = "nova", text = "what is my name" })
	check("context: the second request sends the ContextToken and only the new text", gA.calls[2].ContextToken == "tok1" and gA.calls[2].UserPrompt == "what is my name")
	BAD["boom"] = true
	T += 5
	Phone._act(rs2, { action = "chat", modelId = "nova", text = "boom" })
	Phone._reset()
	T += 5
	Phone._act(rs2, { action = "chat", modelId = "nova", text = "still there?" })
	local last = gA.calls[#gA.calls]
	check("recap: after an error (token lost) the last turns travel inside UserPrompt", last.ContextToken == nil and string.find(last.UserPrompt, "Earlier in this chat:", 1, true) ~= nil
		and string.find(last.UserPrompt, "Player: my name is Mia", 1, true) ~= nil and string.find(last.UserPrompt, "You: answer 1", 1, true) ~= nil
		and string.sub(last.UserPrompt, -#"The player now says: still there?") == "The player now says: still there?", last.UserPrompt)
	check("recap: the offline demo reply is not presented as something the model said", not string.find(last.UserPrompt, "You: " .. PM.demoReply(rd.models.nova, "Nimbus Labs", "boom", 3), 1, true)
		and select(2, string.gsub(last.UserPrompt, "\nYou: ", "")) == 2, last.UserPrompt)
	check("recap: the server remembers the turns it re-sends (memory only)", #Phone._state(rs2).chat.nova.turns >= 6)
	-- the model changes (new overall): new generator, new system prompt, no old token, fresh conversation
	local nGen = #tg
	rd.models.nova.overall += 7
	T += 5
	Phone._act(rs2, { action = "chat", modelId = "nova", text = "new me?" })
	local gB = tg[#tg]
	check("context: a changed model gets a new generator without the old ContextToken or old turns", #tg == nGen + 1 and gB.calls[1].ContextToken == nil and gB.calls[1].UserPrompt == "new me?"
		and string.find(gB.prompt, "Overall score " .. math.floor(rd.models.nova.overall), 1, true) ~= nil, gB.calls[1].UserPrompt)
	check("context: the old conversation is gone on the server too", #Phone._state(rs2).chat.nova.turns == 2)
	BAD = {}
	Phone._reset()
	-- recap maths
	local turns = {}
	for i = 1, 10 do table.insert(turns, { who = if i % 2 == 1 then "you" else "ai", text = "t" .. i }) end
	table.insert(turns, { who = "demo", text = "demo words" })
	local rp = PM.recapPrompt(turns, "now")
	check("recapPrompt: the last 6 real turns, no demo replies, then the new text", string.find(rp, "Player: t5\nYou: t6", 1, true) ~= nil and not string.find(rp, "t4", 1, true) and not string.find(rp, "demo words", 1, true)
		and string.sub(rp, -#"The player now says: now") == "The player now says: now", rp)
	check("recapPrompt: no history -> the text alone", PM.recapPrompt({}, "hi") == "hi")
	local longTurns = {}
	for i = 1, 6 do table.insert(longTurns, { who = "you", text = string.rep("x", 500) }) end
	check("recapPrompt: capped at CHAT_RECAP_CHARS (input limits)", #PM.recapPrompt(longTurns, "q") <= PM.CHAT_RECAP_CHARS + 120, #PM.recapPrompt(longTurns, "q"))
	end

	------------------------------------------------------------------ review round 1: news cap, play-clock anchor, calendar items
	do
	local many = {}
	for i = 1, 40 do table.insert(many, string.format("day 9 %02d:%02d: renewed CloudDesk for %d days", 8 + math.floor(i / 60), i % 60, i)) end
	local nm = PM.newsMessages({ news = many })
	check("news: the phone shows the newest 20 log lines (CORE_SPEC: deals.news <= 40, phone 20)", #nm == PM.NEWS_SHOWN and PM.NEWS_SHOWN == 20 and nm[1].key == "news:" .. many[1] and nm[20].key == "news:" .. many[20])
	check("anchor: a snapshot within the 1 Hz step keeps the old anchor", PM.anchor(5000, 6000.6, 1000, 2) == 5000 and PM.anchor(5000, 6001.4, 1001.9, 2) == 5000)
	check("anchor: a real jump (offline time) moves it", PM.anchor(5000, 9000, 1000, 2) == 8000 and PM.anchor(nil, 6000, 1000) == 5000)
	local eA = { calendar = { day = 9 }, seconds = 1000 }
	local base = C.clockAt(22.5, 3)
	local seen = {}
	for k = 0, 19 do
		-- the server's play clock steps once per second, the client clock runs smoothly in between
		local clock = base + k * 0.25
		eA.seconds = 1000 + math.floor(k * 0.25)
		local off = PM.anchor(base - 1000, clock, eA.seconds)
		local d, h = PM.atPlay(eA, clock, 1000 + 60, off)
		seen[d .. " " .. PM.clock(h)] = true
	end
	check("anchor: a deadline converted with the anchor does not jitter while the play clock steps", C.count(seen) == 1, C.count(seen))
	local seenLive = {}
	for k = 0, 19 do
		local clock = base + k * 0.25
		eA.seconds = 1000 + math.floor(k * 0.25)
		local d, h = PM.atPlay(eA, clock, 1000 + 60)
		seenLive[d .. " " .. PM.clock(h)] = true
	end
	check("anchor: (the live-clock conversion it replaces does jitter at night)", C.count(seenLive) > 1, C.count(seenLive))
	-- day + hour of other packages = what the status bar shows at that moment
	local e13 = { calendar = { day = 13 }, seconds = 0, deals = {} }
	local c7 = C.clockAt(7, 19) + 0.01 -- 07:00 at the end of the night: company day 13 still (it turns at 08:00)
	check("calendar items: the status bar reads 'Day 13 · 07:00' at that moment", PM.statusText(e13, c7) == "Day 13 · 07:00", PM.statusText(e13, c7))
	local ci = PM.calendar({ empire = e13 }, {}, C.clockAt(10, 19), { { key = "a", title = "By clock", at = c7 }, { key = "b", title = "By day", day = 13, hour = 7 }, { key = "c", title = "Meeting", day = 13, hour = 9 } }, nil, nil)
	local byClock, byDay = C.find(ci, function(x) return x.key == "item:a" end), C.find(ci, function(x) return x.key == "item:b" end)
	check("calendar items: {day = 13, hour = 7} is the same moment as `at` = that clock (documented rule)", byClock and byDay and byClock.day == byDay.day and byClock.order == byDay.order and byDay.day == 13, byClock and (byClock.day .. " vs " .. byDay.day))
	check("calendar items: so it sorts after {day = 13, hour = 9}", ci[#ci].title ~= "Meeting" and ci[1].title == "Meeting", ci[1].title)
	end

	------------------------------------------------------------------ review round 1: public shuttle, field staff reports
	do
	local shuttleSpec = { at = C.clockAt(11), flight = "PM 101", airline = "Meridian Air" }
	local gar = C.company({ stage = 1 })
	check("shuttle: not in a garage company's calendar (Port Meridian does not matter yet)", #PM.calendar(gar, { ops = {} }, C.clockAt(10), {}, shuttleSpec, nil) == 0 and not PM.abroadRelevant(gar.empire))
	local st4 = C.company({ stage = 4 })
	local cal4 = PM.calendar(st4, { ops = {} }, C.clockAt(10), {}, shuttleSpec, nil)
	check("shuttle: listed once abroad clients are possible, as a public timetable entry", #cal4 == 1 and cal4[1].public == true and string.find(cal4[1].detail, "Public shuttle timetable", 1, true) ~= nil, cal4[1] and cal4[1].detail)
	gar.empire.deals.accounts = { helix = { expires = 99999, since = 0 } }
	check("shuttle: an abroad client also makes it relevant", PM.abroadRelevant(gar.empire))
	-- arrivals
	local ad = C.company({ stage = 4, money = 1e6, gpus = { datacenter = 1 }, staff = { marketer = 6, engineer = 6 }, models = { { stats = { math = 75 } } } })
	local as = C.session(ad, 3107)
	C.step(as, Economy, C.clockAt(10))
	local ae = ad.empire
	local helixTrip, hostedTrip, cityTrip
	for _, t in ae.deals.tripList do
		local c = Ops.client(t.client)
		if c.trip == "abroad" then helixTrip = t elseif t.hosted then hostedTrip = t elseif c.trip == "city" then cityTrip = t end
	end
	check("fixture: an abroad trip, a hosted visit and a city trip", helixTrip and hostedTrip and cityTrip)
	local L = 50000
	check("arrival: abroad without the jet = when the shuttle lands (timetable function)", PM.arrivalAt(ae, helixTrip, L, function(x) return x + 333 end) == L + 333)
	check("arrival: abroad fallback without a timetable", PM.arrivalAt(ae, helixTrip, L, nil) == L + PM.ARRIVE.abroad * Ops.DAY)
	ae.jet = true
	check("arrival: with the company jet a short hop", PM.arrivalAt(ae, helixTrip, L, function(x) return x + 333 end) == L + PM.ARRIVE.jet * Ops.DAY)
	ae.jet = false
	check("arrival: no report for client teams at the guest house or city trips", PM.arrivalAt(ae, hostedTrip, L) == nil and PM.arrivalAt(ae, cityTrip, L) == nil)
	local rep2, eng2 = PM.travellers(ae, helixTrip)
	local am = PM.arrivalMessage(ae, helixTrip, C.clockAt(11), C.clockAt(12), { city = "City Hotel", abroad = "Meridian Grand Hotel" })
	check("arrival: 'Arrived in Port Meridian' from the travel desk with the real names and the hotel",
		am and am.title == "Arrived in Port Meridian" and am.from == "Travel desk" and rep2 and eng2 and string.find(am.body, rep2 .. " and " .. eng2 .. " landed in Port Meridian", 1, true) ~= nil
			and string.find(am.body, "checked in at the Meridian Grand Hotel", 1, true) ~= nil and string.find(am.body, "pilot meeting at Helix Research", 1, true) ~= nil and string.find(am.body, "Back Day", 1, true) ~= nil, am and am.body)
	check("arrival: one key per trip, stamped at the arrival time", am and am.key == "arrived:helix:" .. tostring(helixTrip.left) and am.day == ae.calendar.day and math.abs(am.hour - 11) < 1e-6)
	end

	------------------------------------------------------------------ remote validation through Remote.bind
	local folder = game.ReplicatedStorage:FindFirstChild("Remotes")
	local fn = folder and folder:FindFirstChild("PhoneAction")
	check("PhoneAction remote exists and is bound", fn ~= nil and fn.OnServerInvoke ~= nil)
	local player = { UserId = 2010, Name = "P" }
	local nocompany = C.session(R.Template.new(), 2010)
	nocompany.player = player
	Remote.setSessionProvider(function(p) return if p == player then nocompany else nil end)
	check("remote: no company -> NO_COMPANY", fn.OnServerInvoke(player, { action = "inbox" }).err == "NO_COMPANY")
	nocompany.data.company = { name = "X", logo = "X", color = "cyan", spec = "general", foundedAt = 0, reputation = 0 }
	check("remote: unknown action -> BAD_INPUT", fn.OnServerInvoke(player, { action = "hack" }).err == "BAD_INPUT")
	check("remote: non-table payload handled", fn.OnServerInvoke(player, "inbox").err == "BAD_INPUT")
	local limitedHit = false
	for i = 1, 20 do if fn.OnServerInvoke(player, { action = "inbox" }).err == "RATE_LIMIT" then limitedHit = true end end
	check("remote: rate limited (burst 8)", limitedHit)
end

setfenv(body, M.envFor(nil))
local ok, res = M.runMain(body, { timeout = 900 })
if not ok then C.fail += 1; print("FAIL  body crashed: " .. tostring(res)) end
if M.stats.errors > 0 then C.fail += 1; print("FAIL  background errors: " .. M.stats.errors) end
C.summary("phone")
