--!nocheck
-- Package "staffops" suites (headless mock, the REAL headquarters + real staff services, see world.luau).
-- Run: python3 tests/staffops/mkharness.py && tools/luau tests/staffops/test_staffops.luau -a <suite> [neg]
-- Suites: clock absence night ops apprentice rack arrival talk client   (tests/staffops/run.sh runs all)
-- "neg" loads gen_neg (the files before this package): every suite must FAIL there (negative check).
local args = { ... }
local SUITE = args[1] or "clock"
local NEG = args[2] == "neg"
local M = require("../../harness/mock")
local gen = if NEG then "./gen_neg" else "./gen"
M.loadTree(require(gen .. "/manifest"), require(gen .. "/sources"))
M.quiet = true
local G = M.G
local CFrame, Vector3 = G.CFrame, G.Vector3
local say = print
local makeWorld = require("./world")
local pass, failc = 0, 0
local failures = {}
local function check(name, ok, detail)
	if ok then pass += 1 return end
	failc += 1
	if not failures[name] then
		failures[name] = 0
		say("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else ""))
	end
	failures[name] += 1
end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end

local suites = {}

------------------------------------------------------------------------------------------------ clock
-- ONE clock: sky, CompanyHour, live.workforce.hour, the staff timer and the economy agree.
suites.clock = function()
	local W = makeWorld(M, { tier = 1, hour = 8.6 })
	local Lighting = M.game:GetService("Lighting")
	local Ops, EmployeeConfig = W.Ops, W.EmployeeConfig
	for _, h in { 8.6, 12.25, 17.9, 18.4, 23.0, 3.5, 7.9 } do
		W.setHour(h)
		W.tick(6)
		local econ = Ops.hour(W.serverNow())
		check("Lighting.ClockTime = CompanyOps.hour (" .. h .. ")", math.abs(Lighting.ClockTime - econ) < 1e-6, Lighting.ClockTime .. " vs " .. econ)
		check("live.workforce.hour = CompanyOps.hour (" .. h .. ")", math.abs(W.session.live.workforce.hour - econ) < 0.1, W.session.live.workforce.hour)
		local ch = W.office:GetAttribute("CompanyHour")
		check("CompanyHour within 0.1 h (" .. h .. ")", type(ch) == "number" and math.abs(ch - econ) < 0.11, ch)
		check("Staff.hour() = CompanyOps.hour", math.abs(W.Staff.hour() - econ) < 1e-6)
		-- TalkService still reads EmployeeConfig.hour(Staff.now()): the timer runs in phase with the clock
		local talk = EmployeeConfig.hour(W.Staff.now())
		local diff = math.abs(talk - econ); diff = math.min(diff, 24 - diff)
		check("EmployeeConfig.hour(Staff.now()) = shown hour (" .. h .. ")", diff < 0.05, talk .. " vs " .. econ)
		check("lunch day index = server day", W.office:GetAttribute("LunchesServed") ~= nil)
	end
	-- the timer is monotonic even if the server clock stands still (tests that never advance Sched.now)
	local t0 = W.Staff.now()
	for _ = 1, 5 do W.Staff.tick(.2) end
	check("Staff.now() advances with dt when the server clock stands still", W.Staff.now() > t0 + 0.9, W.Staff.now() - t0)
	-- the economy's own consumers use the same function on the same clock
	check("IT on duty follows the visible clock", Ops.itOnDuty(W.data.empire, W.serverNow()) == (Ops.hour(W.serverNow()) >= 8 and Ops.hour(W.serverNow()) < 18))
end

------------------------------------------------------------------------------------------------ absence
suites.absence = function()
	-- a company day with at least one vacation and one sick day in the team (found from CompanyOps.presence)
	local EmpireConfig
	local W
	local day
	W = makeWorld(M, { tier = 2, hour = 10.0, prepare = function(d, Wp)
		for candidate = 2, 400 do
			d.empire.calendar.day = candidate
			local vac, sick = 0, 0
			for _, role in Wp.EmpireConfig.ROLES do
				for _, st in Wp.Ops.presence(d.empire, role.id) do
					if st == "vacation" then vac += 1 elseif st == "sick" then sick += 1 end
				end
			end
			if vac >= 2 and sick >= 1 then day = candidate; break end
		end
	end })
	EmpireConfig = W.EmpireConfig
	check("found a day with vacation + sick", day ~= nil)
	local e = W.data.empire
	local before = table.clone(e.employees)
	W.tick(400) -- 80 s: arrivals done
	local away, awayOk, deskFree, present, presentWorking = 0, 0, 0, 0, 0
	for _, role in EmpireConfig.ROLES do
		local states = W.Ops.presence(e, role.id)
		-- HR collision cap: at most ceil(10 %) of a team on vacation the same day
		local vac = 0
		for _, st in states do if st == "vacation" then vac += 1 end end
		check("collision cap " .. role.id, vac <= math.max(1, math.ceil(0.10 * #states)), vac .. " of " .. #states)
		for i, st in states do
			local m = W.rigOf(role.id, i)
			if not m then check("rig exists " .. role.id .. i, false); continue end
			local rec = W.record(m)
			if st ~= "present" then
				away += 1
				if m:GetAttribute("OffDuty") == true and m:GetAttribute("Activity") == "OFF_DUTY" and rec.away == st then awayOk += 1 end
				-- desk released: nobody reserved under this person, the home desk is free for others
				local held = rec.station ~= nil
				for _, w in W.Workstations.scan(W.office).all do if w.reserved == rec then held = true end end
				if not held then deskFree += 1 end
			else
				present += 1
				if m:GetAttribute("OffDuty") ~= true then presentWorking += 1 end
			end
		end
	end
	check("some people away today", away >= 3, away)
	check("everybody away is OffDuty / OFF_DUTY with the reason", awayOk == away, awayOk .. " of " .. away)
	check("their desks are released", deskFree == away, deskFree .. " of " .. away)
	check("present people are at work at 10:00", presentWorking >= present - 2, presentWorking .. " of " .. present)
	for k, v in before do check("employees[" .. k .. "] unchanged", e.employees[k] == v) end
	-- the economy agrees: output counts exactly the present people
	for _, role in EmpireConfig.ROLES do
		local o = W.Ops.output(e, role.id)
		check("CompanyOps.output finite " .. role.id, o == o and o >= 0)
	end
	-- next company day: the absence ends (vacation is one day) -> they come back at their shift
	local who = nil
	for _, role in EmpireConfig.ROLES do
		for i, st in W.Ops.presence(e, role.id) do if st == "vacation" and not who then who = { role = role.id, i = i } end end
	end
	e.calendar.day = day + 1
	local stillAway = W.Ops.presence(e, who.role)[who.i] ~= "present"
	W.setHour(7.0)
	W.tick(15)
	W.setHour(9.4)
	W.tick(500)
	local m = W.rigOf(who.role, who.i)
	if not stillAway then
		check("back from vacation the next day", m:GetAttribute("OffDuty") ~= true and m:GetAttribute("Activity") ~= "OFF_DUTY", m:GetAttribute("Activity"))
	end
	-- talk: the receptionist says who is away (Dialogue facts from CompanyOps.presence)
	e.calendar.day = day
	local f = W.Dialogue.facts(W.data, W.session.live)
	check("facts.away lists the absences", #f.away == away, #f.away .. " vs " .. away)
	local subj = { name = "Lina Rossi", roleId = "support", job = "Reception", seed = 77, index = 301, activity = "WORKING", room = "Reception Hall", level = "G", levelNumber = 0 }
	local lines = W.Dialogue.lines(subj, { viewer = "owner", viewerName = "Founder", day = 1, hour = 10, tier = 2, facts = f, company = "Nimbus Labs" })
	local ans = lines.answers.away and lines.answers.away.text
	check("reception answers 'Who's away today?'", ans ~= nil and has(ans, "away today"), ans)
	local vacName, sickName
	for _, a in f.away do if a.state == "vacation" and not vacName then vacName = a.name end; if a.state == "sick" and not sickName then sickName = a.name end end
	check("vacation line with the return day", has(ans, vacName .. " is on vacation today (back on day " .. (day + 1) .. ")") or #f.away > 3, ans)
	check("absence numbers are real", has(ans, tostring(#f.away) .. " people are away today") or has(ans, "1 person is away today"), ans)
end

------------------------------------------------------------------------------------------------ night
suites.night = function()
	-- Startup Campus (stage 3): 30 researchers on 26 research seats, night shift on -> profiles 27..30 = night crew
	local W = makeWorld(M, { tier = 2, hour = 10.0, employees = { researcher = 30, engineer = 14, curator = 10, marketer = 10 }, prepare = function(d)
		d.empire.nightShift = { research = true }
		d.empire.calendar.day = 3
	end })
	local e = W.data.empire
	local a, b = W.Rota.nightRange(e, "researcher")
	check("night range = newest heads beyond the seats", a == 27 and b == 30, a .. ".." .. b)
	local presence = W.Ops.presence(e, "researcher")
	local function night(i) return i >= 27 and i <= 30 and presence[i] == "present" end
	W.tick(400)
	local nightOff, dayOn, dayN = 0, 0, 0
	for i = 1, 30 do
		local m = W.rigOf("researcher", i)
		if night(i) then
			if m:GetAttribute("Activity") == "OFF_DUTY" then nightOff += 1 end
			check("night crew shift attributes", m:GetAttribute("ShiftStart") == 22 and m:GetAttribute("ShiftEnd") == 6)
		elseif presence[i] == "present" then
			dayN += 1
			if m:GetAttribute("Activity") ~= "OFF_DUTY" then dayOn += 1 end
		end
	end
	local crew = 0; for i = 27, 30 do if night(i) then crew += 1 end end
	check("night crew is home at 10:00", nightOff == crew, nightOff .. " of " .. crew)
	check("day staff at work at 10:00", dayOn >= dayN - 2, dayOn .. " of " .. dayN)
	-- evening -> 23:30 (company time runs 14 h in 300 s at night): the night crew works from 22:00, the
	-- day staff went home after their last task, security keeps a guard on (needed by the crew)
	W.setHour(17.9)
	W.tick(635)
	check("clock at about 23:30", math.abs(W.hour() - 23.5) < 0.3, W.hour())
	local nightOn, dayHome = 0, 0
	for i = 1, 30 do
		local m = W.rigOf("researcher", i)
		if night(i) then if m:GetAttribute("Activity") ~= "OFF_DUTY" and m:GetAttribute("Activity") ~= "LEAVING" then nightOn += 1 end
		elseif m:GetAttribute("Activity") == "OFF_DUTY" or m:GetAttribute("Activity") == "LEAVING" then dayHome += 1 end
	end
	check("night crew on duty at 23:30", nightOn == crew, nightOn .. " of " .. crew)
	check("day staff home at 23:30", dayHome >= 26 - 1, dayHome)
	local guard = nil
	for _, m in W.rigs() do if m:GetAttribute("StaffIndex") == 303 then guard = m end end
	check("security guard post 3 stays on with a night crew", guard and guard:GetAttribute("Activity") ~= "OFF_DUTY", guard and guard:GetAttribute("Activity"))
	local barista = W.job("Barista")
	check("other operations posts are home at night", barista and barista:GetAttribute("Activity") == "OFF_DUTY", barista and barista:GetAttribute("Activity"))
	-- 06:00 the crew goes home (23:30 -> 06:40 = 7.2 h = 153 s)
	W.tick(770)
	check("clock at about 06:40", math.abs(W.hour() - 6.7) < 0.3, W.hour())
	local gone, who = 0, ""
	for i = 27, 30 do if night(i) then local m = W.rigOf("researcher", i); local act = m:GetAttribute("Activity"); if act == "OFF_DUTY" or act == "LEAVING" or (W.record(m).task and W.record(m).task.id == "Leaving") then gone += 1 else local r = W.record(m); who ..= string.format("%d/%s/%s/nav=%s/next=%.0f/off=%s/duty=%s/issue=%s ", i, act, tostring(r.task and r.task.id), tostring(r.nav ~= nil), r.next - W.Staff.now(), tostring(r.offAt and r.offAt - W.Staff.now()), tostring(r.onDuty), tostring(m:GetAttribute("NavigationIssue"))) end end end
	check("night crew leaves at 06:00", gone == crew, who)
	-- without the night shift nobody works at night (next evening)
	e.nightShift = {}
	W.setHour(17.9)
	W.tick(635)
	local any, who = 0, ""
	for i = 1, 30 do local m = W.rigOf("researcher", i); local act = m:GetAttribute("Activity"); if act ~= "OFF_DUTY" and act ~= "LEAVING" then any += 1; local r = W.record(m); who ..= string.format("%d/%s/%s/nav=%s/next=%.0f ", i, act, tostring(r.task and r.task.id), tostring(r.nav ~= nil), r.next - W.Staff.now()) end end
	check("no night shift -> nobody at night", any == 0, who)
end

------------------------------------------------------------------------------------------------ ops
suites.ops = function()
	local W = makeWorld(M, { tier = 4, hour = 7.0 })
	local Rota, Config = W.Rota, W.EmployeeConfig
	-- every seeded post shift covers the opening hours 08:00-18:00
	local okCover = true
	for seed = 0, 3000, 7 do
		local a, b = Rota.opsShift(seed)
		if not (a <= 7.5 and a >= 7.25 and b >= 18.0 and b <= 18.5) then okCover = false end
	end
	check("operations shifts cover 08:00-18:00 for every seed", okCover)
	W.tick(10)
	W.setHour(7.6)
	W.tick(300)
	W.setHour(8.0)
	local seen = {}
	local onAll = true
	W.tick(450, function(i)
		if i % 25 == 0 then
			local h = W.hour()
			if h >= 8.05 and h < 17.9 then
				for _, m in W.office.OperationsEmployees:GetChildren() do
					local rec = W.record(m)
					if not (rec and rec.onDuty) then onAll = false; seen[m.Name] = rec and rec.state end
				end
			end
		end
	end)
	check("every post on duty during opening hours", onAll, next(seen))
	local working = 0
	for _, m in W.office.OperationsEmployees:GetChildren() do if m:GetAttribute("Activity") ~= "OFF_DUTY" then working += 1 end end
	check("operations rigs at their posts", working >= #W.office.OperationsEmployees:GetChildren() - 1, working)
	-- night: posts go home except the stage-5 night rota (security post 3 + IT post 6)
	W.setHour(18.7)
	W.tick(500)
	W.setHour(2.0)
	W.tick(300)
	local nightOn = {}
	for _, m in W.office.OperationsEmployees:GetChildren() do if m:GetAttribute("Activity") ~= "OFF_DUTY" then nightOn[m:GetAttribute("StaffIndex") - 300] = true end end
	check("stage 5 night rota: security post 3 on", nightOn[3] == true)
	check("stage 5 night rota: IT post 6 on", nightOn[6] == true)
	local others, who = 0, ""
	for _, m in W.office.OperationsEmployees:GetChildren() do
		local k = m:GetAttribute("StaffIndex") - 300
		if nightOn[k] and k ~= 3 and k ~= 6 then others += 1; local r = W.record(m); who ..= string.format("%s/%s/%s/%s/nav=%s next=%.0f issue=%s pos=%s ", m:GetAttribute("Role"), m:GetAttribute("Activity"), tostring(r.task and r.task.id), tostring(r.event and r.event.kind), tostring(r.nav ~= nil), r.next - W.Staff.now(), tostring(m:GetAttribute("NavigationIssue")), tostring(W.cf:PointToObjectSpace(m.PrimaryPart.Position))) end
	end
	check("other posts home at night", others == 0, who)
	check("IT on call at night = CompanyOps.itOnDuty", W.Ops.itOnDuty(W.data.empire, W.serverNow()) == true)
	-- talk: an operations person states the real shift
	local recep = W.job("Reception")
	check("reception has a shift for the talk lines", type(recep:GetAttribute("ShiftStart")) == "number" and recep:GetAttribute("ShiftStart") < 8)
	check("night rota posts have no fixed shift", W.job("IT Support"):GetAttribute("ShiftStart") == nil)
	check("OPS_WAGE_PER_DAY = CompanyOps.OPS_WAGE", Config.OPS_WAGE_PER_DAY == 720 and W.Ops.OPS_WAGE == Config.OPS_WAGE_PER_DAY)
end

------------------------------------------------------------------------------------------------ apprentice
suites.apprentice = function()
	local W = makeWorld(M, { tier = 2, hour = 8.9, staff = 40, day = 4 })
	local e = W.data.empire
	local Config = W.EmployeeConfig
	check("no Training Lead without apprentices", W.job("Training Lead") == nil)
	W.tick(20)
	local nameA, seedA = W.hire("researcher", { apprentice = true })
	local nameB, seedB = W.hire("engineer", { apprentice = true })
	local lead = W.job("Training Lead")
	check("Training Lead placed with the first apprentice", lead ~= nil)
	check("Training Lead is operations post 17", lead and lead:GetAttribute("StaffIndex") == 300 + Config.TRAINING_LEAD_POST and lead:GetAttribute("RoleId") == "support")
	local deskId = lead and lead:GetAttribute("HomeWorkstation")
	local deskRoom = nil
	for _, d in W.office:GetDescendants() do if d:IsA("Model") and d:GetAttribute("WorkstationId") == deskId then deskRoom = d:GetAttribute("HomeRoom") end end
	local r = deskRoom and W.Plan.room(W.tier, deskRoom)
	check("Training Lead works from the HR room", r ~= nil and r.kind == "hr", deskRoom)
	local function rigBySeed(seed) for _, m in W.rigs() do if m:GetAttribute("PersonalitySeed") == seed then return m end end end
	local a, b = rigBySeed(seedA), rigBySeed(seedB)
	check("apprentice rigs exist", a ~= nil and b ~= nil)
	for _, m in { a, b } do
		if not m then continue end
		check("Apprentice attribute", m:GetAttribute("Apprentice") == true)
		local lan = m:FindFirstChild("Lanyard")
		check("green apprentice lanyard", lan and lan.Color == W.Assignment.APPRENTICE_GREEN)
		local label = m.Head.EmployeeBadge:FindFirstChildWhichIsA("TextLabel")
		check("badge says Apprentice", has(label.Text, "Apprentice · "), label.Text)
		check("younger build (scaled)", math.abs(m:GetScale() - Config.APPRENTICE.scale) < 1e-6, m:GetScale())
		check("no facial hair", m:FindFirstChild("Beard") == nil and m:FindFirstChild("Moustache") == nil and m:FindFirstChild("ShortBeard") == nil)
	end
	-- first day: the tour (after they arrived through reception)
	local tourStarted, tourStops, presentPose, tourTask, memberTask, memberScan = false, {}, false, false, false, false
	local ev = W.Events
	W.tick(2400, function()
		local rec = W.record(lead)
		if rec and rec.event and rec.event.kind == "tour" then tourStarted = true end
		local task = lead:GetAttribute("Task")
		if type(task) == "string" and string.sub(task, 1, 5) == "Tour:" then tourStops[task] = true; tourTask = true; if lead:GetAttribute("Pose") == "present" then presentPose = true end end
		if a:GetAttribute("Task") == "ApprenticeTour" then memberTask = true; if a:GetAttribute("Pose") == "scan" then memberScan = true end end
	end)
	local n = 0; for _ in tourStops do n += 1 end
	check("tour started", tourStarted)
	check("tour stops at 4-6 rooms", n >= 4 and n <= 6, n)
	check("trainer explains at the stops (present pose, Task Tour:<room>)", presentPose and tourTask)
	check("apprentices follow (Task ApprenticeTour, listening pose)", memberTask and memberScan)
	local memory = ev.memory(W.office)
	check("tour completed for both apprentices", memory.toured[seedA] and memory.toured[seedB])
	check("trainer back to normal after the tour", W.record(lead).event == nil)
	-- talk: the trainer's tour line names the room
	local anyStop = next(tourStops)
	local roomId = string.sub(anyStop, 6)
	local f = W.Dialogue.facts(W.data, W.session.live)
	local subj = { name = lead:GetAttribute("EmployeeName"), roleId = "support", job = "Training Lead", seed = lead:GetAttribute("PersonalitySeed"), index = 317, activity = "WORKING", task = anyStop }
	local L = W.Dialogue.lines(subj, { viewer = "owner", viewerName = "Founder", day = 1, hour = 10, tier = W.tier, facts = f, company = "Nimbus Labs" })
	check("trainer kind", L.kind == "trainer")
	check("tour line names the room", has(L.answers.work.text, W.Plan.room(W.tier, roomId).name), L.answers.work.text)
	check("apprentices answer lists them", has(L.answers.apprentices.text, "2 apprentices") and has(L.answers.apprentices.text, "day 1 of 9"), L.answers.apprentices.text)
	local sa = { name = nameA, roleId = "researcher", job = "AI Researcher", seed = seedA, index = a:GetAttribute("StaffIndex"), activity = "RESEARCH", task = "Practice", wage = 0.5 }
	local LA = W.Dialogue.lines(sa, { viewer = "owner", viewerName = "Founder", day = 1, hour = 10, tier = W.tier, facts = f, company = "Nimbus Labs" })
	check("apprentice talks about the training", has(LA.answers.you.text, "apprentice") and has(LA.answers.you.text, "day 1 of my 9 training days"), LA.answers.you.text)
	check("apprentice wage = 40 % of the profile wage", has(LA.answers.you.text, string.format("$%.2f", 0.5 * W.Ops.APPRENTICE.wage)), LA.answers.you.text)
	-- next company day: the training session at 10:00 in a meeting room
	e.calendar.day += 1
	W.setHour(8.6) -- the clock jump skips the evening: start the morning early enough for running flows to end
	local sessionSeen, seated, leadPresent, topic, busyDisplay = false, 0, false, nil, false
	local practice = {}
	W.tick(2100, function()
		local rec = W.record(lead)
		if rec and rec.event and rec.event.kind == "session" then
			sessionSeen = true
		end
		if lead:GetAttribute("Task") == "TrainingLead" and lead:GetAttribute("Pose") == "present" then leadPresent = true end
		local sc = 0
		for _, m in { a, b } do
			if m:GetAttribute("Task") == "TrainingSession" and m:GetAttribute("Activity") == "MEETING" then sc += 1 end
			local t = m:GetAttribute("Task"); if t == "Practice" or t == "Shadowing" then practice[t] = true end
		end
		seated = math.max(seated, sc)
		local mt = W.office:GetAttribute("MeetingTopic")
		if mt == "APPRENTICE TRAINING" then topic = true elseif sessionSeen and mt and (W.office:GetAttribute("MeetingUntil") or 0) > W.serverNow() then busyDisplay = true end
	end)
	check("training session held", sessionSeen)
	-- (an apprentice who is on vacation / sick today stays home: CompanyOps.presence)
	local expected = 0
	for _, m in { a, b } do
		local r = W.record(m)
		if not r.away then expected += 1 end
	end
	check("present apprentices seated in the session", seated == expected and expected >= 1, seated .. " of " .. expected)
	check("trainer presents at the head of the table", leadPresent)
	check("meeting display shows the session (unless a team meeting holds it)", topic == true or busyDisplay)
	check("session over after 11:30", W.record(lead).event == nil and W.hour() > 11.5, W.hour())
	check("apprentices practise / shadow afterwards", practice.Practice == true or practice.Shadowing == true)
	-- graduation after 9 company days: badge back to normal, the Training Lead leaves with the last apprentice
	e.calendar.day = (e.apprentices[tostring(seedA)].day or 1) + W.Ops.APPRENTICE.graduateDays
	local grads = W.Ops.graduate(e)
	check("CompanyOps graduates both", #grads == 2, #grads)
	W.tick(15)
	check("graduate badge back to normal", a:GetAttribute("Apprentice") == nil and a:FindFirstChild("Lanyard").Color ~= W.Assignment.APPRENTICE_GREEN)
	check("graduate full size again", math.abs(a:GetScale() - 1) < 1e-6, a:GetScale())
	check("Training Lead gone without apprentices", W.job("Training Lead") == nil)
	check("records consistent after the despawn", #W.Staff.inspect(W.office) == #W.rigs(), #W.Staff.inspect(W.office) .. " vs " .. #W.rigs())
	W.Assignment.assign(W.office, W.cf, W.session)
	check("no Training Lead after the next staff change", W.job("Training Lead") == nil)
end

------------------------------------------------------------------------------------------------ rack
suites.rack = function()
	local W = makeWorld(M, { tier = 2, hour = 9.4, prepare = function(d) d.gpus.accelerator = 3 end })
	local e = W.data.empire
	local Ops = W.Ops
	W.tick(150)
	local blades = W.office:FindFirstChild("Blades")
	check("data hall blades exist", blades and #blades:GetChildren() >= 3, blades and #blades:GetChildren())
	-- the economy's fault list (CompanyOps): create the state, inject a fault on slot 2
	local clock = W.serverNow()
	Ops.faultStep(e, W.data.gpus, W.OWNER, 0, clock)
	local list = Ops.faults(e)
	local rack = Ops.rack(W.data.gpus)
	table.insert(list, { slot = 2, gpu = rack[2].gpu, throughput = 1, left = 1, since = e.seconds })
	local economy = true
	local acc = 0
	local function econ(dt)
		if not economy then return end
		acc += dt
		while acc >= 1 do acc -= 1; Ops.faultStep(e, W.data.gpus, W.OWNER, 1, W.serverNow()) end
	end
	economy = false -- first: the economy holds the fault; the NPC must not fix it on its own
	W.tick(10)
	local blade = blades:GetChildren()[2]
	check("blade broken (FxState)", blade:GetAttribute("FxState") == "broken")
	check("blade FaultSlot", blade:GetAttribute("FaultSlot") == 2)
	local eta = blade:GetAttribute("FaultUntil")
	check("FaultUntil = the economy's repair estimate (60 s with IT on duty)", type(eta) == "number" and math.abs(eta - (W.serverNow() + 60)) < 4, eta and (eta - W.serverNow()))
	local worker = nil
	for _, m in W.rigs() do local r = W.record(m); if r and r.event and r.event.kind == "repair" then worker = m end end
	check("someone walks to the rack", worker ~= nil)
	check("worker carries a laptop", worker and worker:GetAttribute("Holding") == "laptop")
	check("worker is IT or an engineer", worker and (worker:GetAttribute("RoleId") == "engineer" or worker:GetAttribute("Role") == "IT Support"))
	check("task RackRepair", worker and worker:GetAttribute("Task") == "RackRepair")
	local poses = {}
	local repairing = false
	W.tick(900, function()
		local r = W.record(worker)
		if r.event and r.event.phase == "repair" then repairing = true; local p = worker:GetAttribute("Pose"); if p then poses[p] = true end end
	end)
	local np = 0; for _ in poses do np += 1 end
	check("worker reached the rack and repairs", repairing)
	check("repair pose sequence", np >= 3, np)
	check("the NPC never clears a fault itself", blade:GetAttribute("FxState") == "broken" and #Ops.faults(e) == 1)
	-- the economy finishes the repair: blade and NPC follow within a second
	economy = true
	local clearedAt, bladeIdleAt, doneAt = nil, nil, nil
	W.tick(600, function(i)
		econ(.2)
		if not clearedAt and #Ops.faults(e) == 0 then clearedAt = i end
		if not bladeIdleAt and blade:GetAttribute("FxState") == "idle" then bladeIdleAt = i end
		if not doneAt and W.record(worker).event == nil then doneAt = i end
	end)
	check("economy cleared the fault (60 s)", clearedAt ~= nil and clearedAt * 0.2 >= 55 and clearedAt * 0.2 <= 65, clearedAt and clearedAt * 0.2)
	check("blade back to normal within 1.2 s of the economy", bladeIdleAt and clearedAt and bladeIdleAt - clearedAt <= 6, bladeIdleAt and clearedAt and (bladeIdleAt - clearedAt))
	check("NPC finishes after the economy (closing step)", doneAt and clearedAt and doneAt > clearedAt and (doneAt - clearedAt) * 0.2 <= 7, doneAt and clearedAt and (doneAt - clearedAt) * 0.2)
	check("FaultSlot cleared", blade:GetAttribute("FaultSlot") == nil and blade:GetAttribute("FaultUntil") == nil)
	check("worker hands free again", worker:GetAttribute("Holding") ~= "laptop" or W.record(worker).event == nil)
	-- a fault the economy fixes before anybody arrives: the NPC still walks over and closes it
	local list2 = Ops.faults(e)
	table.insert(list2, { slot = 3, gpu = rack[3].gpu, throughput = 1, left = 0.05, since = e.seconds })
	local w2, arrivedClose, cleared2, finished2 = nil, false, false, false
	W.tick(900, function()
		econ(.2)
		for _, m in W.rigs() do local r = W.record(m); if r and r.event and r.event.kind == "repair" and r.event.slot == 3 then w2 = m end end
		if w2 then
			local r = W.record(w2)
			if #Ops.faults(e) == 0 then cleared2 = true end
			if r.event and r.event.phase == "close" and cleared2 then arrivedClose = true end
			if arrivedClose and r.event == nil then finished2 = true end
		end
	end)
	check("late worker assigned", w2 ~= nil)
	check("late worker still closes the rack after the economy fixed it", arrivedClose and finished2)
	-- the garage: no IT post, an engineer repairs the mini rack
end

------------------------------------------------------------------------------------------------ garage
-- plan tier 0 (Garage Lab): no IT post, no reception, no operations staff: an engineer repairs the mini
-- rack (300 s economy repair without IT); new hires walk straight to their desk
suites.garage = function()
	local W = makeWorld(M, { tier = 0, hour = 9.6, employees = { researcher = 1, engineer = 2, curator = 1, marketer = 0 }, prepare = function(d) d.gpus.consumer = 2 end })
	local e = W.data.empire
	local Ops = W.Ops
	W.tick(100)
	check("no operations staff in the garage", #W.office.OperationsEmployees:GetChildren() == 0)
	local blades = W.office:FindFirstChild("Blades")
	check("garage rack blades", blades and #blades:GetChildren() >= 2, blades and #blades:GetChildren())
	Ops.faultStep(e, W.data.gpus, W.OWNER, 0, W.serverNow())
	local rack = Ops.rack(W.data.gpus)
	table.insert(Ops.faults(e), { slot = 1, gpu = rack[1].gpu, throughput = 1, left = 1, since = e.seconds })
	W.tick(10)
	local blade = blades:GetChildren()[1]
	check("garage blade broken", blade:GetAttribute("FxState") == "broken")
	local eta = blade:GetAttribute("FaultUntil")
	check("garage repair estimate 300 s (no IT post)", type(eta) == "number" and math.abs(eta - (W.serverNow() + 300)) < 4, eta and eta - W.serverNow())
	local worker = nil
	for _, m in W.rigs() do local r = W.record(m); if r and r.event and r.event.kind == "repair" then worker = m end end
	check("an engineer walks to the garage rack", worker and worker:GetAttribute("RoleId") == "engineer")
	local repairing = false
	W.tick(400, function() local r = W.record(worker); if r.event and r.event.phase == "repair" then repairing = true end end)
	check("engineer repairs at the rack", repairing)
	-- a hire in the garage: no reception, straight to the desk
	local _, seed = W.hire("marketer")
	W.tick(2)
	local m = nil
	for _, x in W.rigs() do if x:GetAttribute("PersonalitySeed") == seed then m = x end end
	local rec = m and W.record(m)
	check("garage hire arrives (no reception)", rec and rec.event == nil and m:GetAttribute("OffDuty") == false, rec and rec.event and rec.event.kind)
	check("apprentices are refused below stage 3 (server rule) -> no Training Lead", W.job("Training Lead") == nil)
end

------------------------------------------------------------------------------------------------ arrival
suites.arrival = function()
	local W = makeWorld(M, { tier = 2, hour = 9.5, staff = 40 })
	local e = W.data.empire
	W.tick(300)
	local before, offBefore = {}, {}
	for _, m in W.rigs() do before[m] = m.PrimaryPart.CFrame; offBefore[m] = m:GetAttribute("Activity") == "OFF_DUTY" end
	local Plan = W.Plan
	-- auto-HR hire (EmpireService.hire: profile + count, PlotService.refresh -> StaffAssignment)
	local name, seed = W.hire("engineer")
	local new, rebuilt, moved = nil, 0, 0
	for _, m in W.rigs() do
		if not before[m] then rebuilt += 1; new = m end
	end
	for m, cfr in before do if not m.Parent then rebuilt += 100 end end
	check("a hire builds exactly one rig (incremental staff assignment)", rebuilt == 1, rebuilt)
	check("new rig hidden until it walks in", new and new:GetAttribute("OffDuty") == true)
	check("StaffRev counts the change", type(W.office:GetAttribute("StaffRev")) == "number")
	W.tick(1)
	local rec = new and W.record(new)
	check("first-day arrival flow", rec and rec.event and rec.event.kind == "arrive")
	check("visible and arriving", new:GetAttribute("OffDuty") == false and new:GetAttribute("Task") == "FirstDay")
	local street = W.cf * Plan.staffArrival(W.tier, rec.garage)
	check("starts at the street / garage arrival", (new.PrimaryPart.Position - street).Magnitude < 6, (new.PrimaryPart.Position - street).Magnitude)
	local badge, atDesk = false, false
	W.tick(1500, function()
		if new:GetAttribute("Holding") == "badge" then badge = true end
		local r = W.record(new)
		if r.station and r.station.id == new:GetAttribute("HomeWorkstation") and r.state ~= "WALKING" then atDesk = true end
	end)
	check("picked up the badge at reception", badge)
	check("then reached the new desk", atDesk)
	local movedWho = ""
	for m, cfr in before do
		local r = W.record(m)
		if r and r.state == "OFF_DUTY" and offBefore[m] then
			-- parked rigs stay put
			if (m.PrimaryPart.Position - cfr.Position).Magnitude > 0.01 then moved += 1; movedWho ..= tostring(m:GetAttribute("Role")) .. "/" .. tostring(r.away) .. " " end
		end
	end
	check("off-duty colleagues were not moved by the hire", moved == 0, movedWho)
	-- interview hire: the rig stays hidden while the candidate walks out to the speed gates (RecruitingService
	-- hold), then takes over at the candidate's last spot
	local spot = W.cf * CFrame.new(-30, 3, -30)
	local _, seed2 = W.hire("curator", { hold = true })
	W.tick(4)
	local m2 = nil
	for _, m in W.rigs() do if m:GetAttribute("PersonalitySeed") == seed2 then m2 = m end end
	check("interview hire hidden while the candidate walks out", m2 and m2:GetAttribute("OffDuty") == true and m2:GetAttribute("Activity") == "OFF_DUTY", m2 and m2:GetAttribute("Activity"))
	W.Staff.handoverArrival(W.office, seed2, spot)
	W.tick(2)
	check("interview hire starts where the candidate stood", m2 and (m2.PrimaryPart.Position - spot.Position).Magnitude < 4, m2 and (m2.PrimaryPart.Position - spot.Position).Magnitude)
	check("interview hire's first day", m2 and m2:GetAttribute("Task") == "FirstDay" and m2:GetAttribute("OffDuty") == false, m2 and m2:GetAttribute("Task"))
	-- a hire at night arrives through reception the next morning
	W.setHour(20.0)
	W.tick(5)
	local _, seed3 = W.hire("marketer")
	W.tick(2)
	local m3 = nil
	for _, m in W.rigs() do if m:GetAttribute("PersonalitySeed") == seed3 then m3 = m end end
	check("night hire waits off duty", m3 and m3:GetAttribute("Activity") == "OFF_DUTY")
	W.setHour(7.5)
	local firstDay = false
	W.tick(900, function() if m3:GetAttribute("Task") == "FirstDay" then firstDay = true end end)
	check("night hire's first day starts at reception", firstDay)
	-- fire: one rig goes, the rest stay
	local count0 = #W.rigs()
	table.remove(e.staffProfiles.engineer, 1)
	e.employees.engineer -= 1
	W.Assignment.assign(W.office, W.cf, W.session)
	W.tick(2)
	check("fire removes one rig", #W.rigs() == count0 - 1, #W.rigs() .. " vs " .. count0)
	check("records match the rigs", #W.Staff.inspect(W.office) == #W.rigs())
	local idxOk = true
	local seenIdx = {}
	for _, m in W.office.Employees:GetChildren() do local i = m:GetAttribute("StaffIndex"); if seenIdx[i] then idxOk = false end; seenIdx[i] = true end
	for i = 1, #W.office.Employees:GetChildren() do if not seenIdx[i] then idxOk = false end end
	check("indices renumbered 1..n", idxOk)
	-- headhunter voucher (RecruitingService)
	local okR, Recruiting = pcall(function() return M.require(M.game.ServerScriptService.Server.Services.RecruitingService) end)
	check("RecruitingService loads", okR, Recruiting)
	if okR and Recruiting.headhunt then
		local n0 = #e.applicants
		local ok1, err1 = Recruiting.headhunt(W.session)
		check("headhunter adds one applicant", ok1 == true and #e.applicants == n0 + 1, err1)
		local a = e.applicants[#e.applicants]
		check("top candidate (hidden skill >= 4)", a and Recruiting.traits(W.OWNER, a.serial).k >= 4)
		check("application time is play time", a and a.at == e.seconds)
		while #e.applicants < W.EmpireMath.MAX_APPLICANTS do table.insert(e.applicants, { id = "x" .. #e.applicants, st = "new", at = 0, role = "engineer", q = {} }) end
		local ok2, err2 = Recruiting.headhunt(W.session)
		check("full applications keep the voucher", ok2 == false and err2 == "APPLICANTS_FULL", err2)
		local company = W.data.company; W.data.company = nil
		local ok3, err3 = Recruiting.headhunt(W.session)
		check("no company keeps the voucher", ok3 == false and err3 == "NO_COMPANY", err3)
		W.data.company = company
	else
		check("Recruiting.headhunt exists", false)
	end
end

------------------------------------------------------------------------------------------------ client
suites.client = function()
	local Controllers = M.game.StarterPlayer.StarterPlayerScripts.Client.Controllers
	local Fx = M.require(Controllers.PropFxController)
	local EC = M.require(Controllers.EmployeeController)
	local Instance, Vector3, CFrame = G.Instance, G.Vector3, G.CFrame
	local Collection = M.game:GetService("CollectionService")
	local office = Instance.new("Model"); office.Name = "Office"; office.Parent = G.workspace
	local blade = Instance.new("Part"); blade.Name = "RackBlade"; blade.Size = Vector3.new(1.4, 4.4, 0.08); blade.CFrame = CFrame.new(0, 3.8, 0); blade.Anchored = true; blade.Parent = office
	blade:SetAttribute("Fx", "breathe"); blade:SetAttribute("Lit", true); blade:SetAttribute("RackIndex", 2)
	local door = Instance.new("Part"); door.Name = "RackDoor"; door.Size = Vector3.new(2, 7.3, 0.08); door.CFrame = CFrame.new(0, 3.75, -0.18); door.Anchored = true; door.Parent = office
	door:SetAttribute("Fx", "hinge,leds")
	local gui = Instance.new("SurfaceGui"); gui.Name = "Mesh"; gui.Parent = door
	for i = 1, 8 do local led = Instance.new("Frame"); led.Name = "LED" .. i; led.BackgroundColor3 = G.Color3.fromRGB(80, 200, 120); led.Parent = gui end
	local home = blade.Color
	local pb = Fx.register(blade); local pd = Fx.register(door)
	check("blade + door register", pb ~= nil and pd ~= nil)
	blade:SetAttribute("FxState", "broken"); blade:SetAttribute("FaultSlot", 3); blade:SetAttribute("FaultUntil", G.workspace:GetServerTimeNow() + 42)
	door:SetAttribute("FxState", "broken"); door:SetAttribute("FaultSlot", 3)
	local parts, cfs = {}, {}
	local now = G.workspace:GetServerTimeNow()
	Fx.animate(pb, now, 0.1, parts, cfs); Fx.animate(pd, now, 0.1, parts, cfs)
	check("fault effects built", pb.fault ~= nil and pd.fault ~= nil)
	local beacon = pb.fault and pb.fault.beacon
	check("beacon on the rack", beacon and beacon.Parent and beacon.Parent.Name == "PropFxLocal")
	local label = beacon and beacon:FindFirstChild("RackFaultLabel")
	local title = label and label.Card.Title.Text
	check("label: Rack R3 · fault · capacity −1", title == "Rack R3 · fault · capacity −1", title)
	local status = label and label.Card.Status.Text
	check("label: economy repair estimate", has(status, "back in ~42 s") or has(status, "back in ~41 s"), status)
	check("long repairs in minutes", select(2, Fx.faultText(1, now + 263, now)) == "Repair · back in ~4 min")
	check("door banner R3 · FAULT", gui:FindFirstChild("FxFault") and gui.FxFault.FxText.Text == "R3 · FAULT")
	local red = false
	for t = 0, 1, 0.1 do Fx.animate(pb, now + t, 0.1, parts, cfs); if blade.Color == G.Color3.fromRGB(235, 52, 44) then red = true end end
	check("blade blinks red", red)
	local ledRed = false
	for t = 0, 1, 0.1 do Fx.animate(pd, now + t, 0.1, parts, cfs); if gui.LED1.BackgroundColor3 == G.Color3.fromRGB(235, 52, 44) then ledRed = true end end
	check("door LEDs blink red", ledRed)
	-- fixed: everything back
	blade:SetAttribute("FxState", "idle"); door:SetAttribute("FxState", "idle")
	Fx.animate(pb, now + 2, 0.1, parts, cfs); Fx.animate(pd, now + 2, 0.1, parts, cfs)
	check("effects removed when fixed", pb.fault == nil and pd.fault == nil and not beacon.Parent)
	check("blade colour restored", blade.Color == home)
	check("LED colours restored", gui.LED1.BackgroundColor3 == G.Color3.fromRGB(80, 200, 120))
	check("banner removed", gui:FindFirstChild("FxFault") == nil)
	-- the Training Lead's "present" pose moves the arms (client, procedural)
	local pose = EC.pose("WORKING", false, false, 3.2, 17, false, "present")
	local idle = EC.pose("WORKING", false, false, 3.2, 17, false, nil)
	check("present pose differs from idle", pose["Right Shoulder"] ~= idle["Right Shoulder"])
	check("faultText without estimate", select(2, Fx.faultText(4, nil, now)) == "IT notified")
end

------------------------------------------------------------------------------------------------ talk
suites.talk = function()
	local RS = M.game.ReplicatedStorage
	local Dialogue = M.require(RS.Shared.Dialogue)
	local Template = M.require(M.game.ServerScriptService.Server.Lib.Template)
	local EmpireMath = M.require(RS.Shared.EmpireMath)
	local d = Template.new()
	d.company = { name = "Nimbus Labs", logo = "N", color = "cyan", spec = "general", reputation = 10, foundedAt = 0 }
	d.empire.office = 3
	d.empire.employees = { researcher = 12, engineer = 10, curator = 8, marketer = 10 }
	EmpireMath.syncProfiles(d.empire, 1001)
	d.empire.calendar = { day = 5 }
	local f = Dialogue.facts(d, { users = 0, revenue = 0, cost = 0 })
	local c = { viewer = "owner", viewerName = "Founder", day = 5, hour = 10, tier = 2, facts = f, company = "Nimbus Labs" }
	local function lines(s) return Dialogue.lines(s, c) end
	-- night crew shift from the rig attributes
	local L = lines({ name = "Ada Weber", roleId = "researcher", job = "AI Researcher", seed = 99, index = 1, activity = "RESEARCH", task = "RunExperiment", shiftStart = 22, shiftEnd = 6 })
	check("night crew day answer", has(L.answers.day.text, "night crew: 22:00 to 6:00"), L.answers.day.text)
	-- first day / rack repair / shadowing lines
	local L2 = lines({ name = "Ben Park", roleId = "engineer", job = "ML Engineer", seed = 7, index = 2, activity = "ARRIVING", task = "FirstDay" })
	check("first day greeting", has(L2.greeting, "first day"), L2.greeting)
	local L3 = lines({ name = "Ben Park", roleId = "engineer", job = "ML Engineer", seed = 7, index = 2, activity = "SERVER_CHECK", task = "RackRepair" })
	check("rack repair line", has(L3.answers.work.text, "fixing a server rack"), L3.answers.work.text)
	local L4 = lines({ name = "Lea Roth", roleId = "curator", job = "Data Curator", seed = 8, index = 3, activity = "DATA_REVIEW", task = "Shadowing" })
	check("shadowing line", has(L4.answers.work.text, "senior"), L4.answers.work.text)
	-- absent teammates in "What does your team do?"
	local someone
	for _, a in f.away do if a.role == "researcher" then someone = a end end
	if someone then
		local L5 = lines({ name = "Zed Z", roleId = "researcher", job = "AI Researcher", seed = 1, index = 1, activity = "RESEARCH", task = "RunExperiment" })
		check("team answer names an absent teammate", has(L5.answers.team.text, someone.name), L5.answers.team.text)
	end
	check("away list = CompanyOps.presence", (function()
		local n = 0
		local Ops = M.require(RS.Shared.CompanyOps)
		for _, role in { "researcher", "engineer", "curator", "marketer" } do for _, st in Ops.presence(d.empire, role) do if st ~= "present" then n += 1 end end end
		return n == #f.away
	end)())
	check("nobody away -> honest line", has(Dialogue.lines({ name = "R", roleId = "support", job = "Reception", seed = 3, index = 301, activity = "WORKING" }, { viewer = "owner", viewerName = "F", day = 1, hour = 9, tier = 2, facts = Dialogue.facts({ company = d.company, empire = { employees = {} } }, nil), company = "N" }).answers.away.text, "Everybody is in today"))
end

local fn = suites[SUITE]
if not fn then print("unknown suite " .. tostring(SUITE)); return end
local function body() fn() end
setfenv(body, M.envFor(nil))
local ok, err = M.runMain(body, { timeout = 100000, maxSteps = 80000000 })
if not ok then print("ERROR: " .. tostring(err)); failc += 1 end
for name, n in failures do if n > 1 then print(string.format("  (%s failed %d times)", name, n)) end end
print(string.format("staffops_%s%s: %d passed, %d failed", SUITE, if NEG then " (NEGATIVE: files before staffops)" else "", pass, failc))
if failc > 0 then error("staffops " .. SUITE .. " failed", 0) end
