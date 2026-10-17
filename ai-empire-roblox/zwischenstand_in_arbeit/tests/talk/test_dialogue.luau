--!nocheck
-- Talk package: the pure Dialogue module (ReplicatedStorage.Shared.Dialogue) in the headless mock.
-- Every hired role x activity state and every operations job (incl. the new hotel/housekeeping/cleaner
-- jobs) x owner/visitor: non-empty, placeholder-free lines; numbers in the answers equal the real state
-- (Format of the session values); option flow (2..4 chips, bye last, follow-ups, paging); directions
-- (left/right/level); visitor answers never leak cash; determinism + variety per day; tone from seed;
-- what the building has: "What does your team do?" (desk room, department, head count, the role's effect
-- from EmpireConfig.ROLES.desc), "What's this room for?" for every non-hidden room of tiers 1-4 (only
-- circulation stays unexplained), the floor-by-floor tour, desks in use, lunch phases, menu boost times.
-- Prints one sample conversation per job.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_talk && tools/luau tests/talk/test_dialogue.luau [-a .gen_dir] [-a --quiet]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. ((args[1] and args[1] ~= "--quiet") and args[1] or ".gen_talk")
local QUIET = args[1] == "--quiet" or args[2] == "--quiet"
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local say = print
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; say("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end

local function body()
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local Dialogue = M.require(RS.Shared.Dialogue)
	local Format = M.require(RS.Shared.Format)
	local EmployeeConfig = M.require(RS.Shared.Config.EmployeeConfig)
	local EmpireConfig = M.require(RS.Shared.Config.EmpireConfig)
	local CampusConfig = M.require(RS.Shared.Config.CampusConfig)
	local Plan = M.require(RS.Shared.Config.BuildingPlan)
	local EmpireMath = M.require(RS.Shared.EmpireMath)
	local Template = M.require(Server.Lib.Template)
	local OWNER = 4242

	------------------------------------------------------------------ A. job kinds + public rule
	local expectKind = { Reception = "reception", Security = "security", Facilities = "facilities", ["IT Support"] = "it", Barista = "barista", Chef = "chef",
		["Kitchen Team"] = "kitchen", ["Cafe Host"] = "host", Fleet = "fleet", ["Hotel Reception"] = "hotel", Housekeeping = "housekeeping", Cleaner = "cleaner",
		Mechanic = "fleet", Mailroom = "mailroom", ["Campus Operations"] = "ops" }
	for job, kind in expectKind do check("kind " .. job, Dialogue.kind("support", job) == kind, Dialogue.kind("support", job)) end
	for _, job in EmployeeConfig.OPERATIONS_JOBS do check("every ops job has a known kind: " .. job, Dialogue.kind("support", job) ~= "ops", Dialogue.kind("support", job)) end
	local publicJobs = { Reception = true, Security = true, Barista = true, Chef = true, ["Cafe Host"] = true, ["Hotel Reception"] = true }
	for job in expectKind do check("public rule " .. job, Dialogue.isPublicJob(job) == (publicJobs[job] == true)) end
	for _, role in EmpireConfig.ROLES do check("hired role kind " .. role.id, Dialogue.kind(role.id, role.name) == role.id) end
	check("isPublicJob(nil) false", Dialogue.isPublicJob(nil) == false)

	------------------------------------------------------------------ B. formatting helpers
	check("clock 8.25", Dialogue.clock(8.25) == "8:15", Dialogue.clock(8.25))
	check("clock 12.999 rolls over", Dialogue.clock(12.9999) == "13:00", Dialogue.clock(12.9999))
	check("clock 7.75", Dialogue.clock(7.75) == "7:45")
	check("spoken 45", Dialogue.spoken(45) == "45 seconds", Dialogue.spoken(45))
	check("spoken 130", Dialogue.spoken(130) == "2 min 10 s", Dialogue.spoken(130))
	check("spoken 180", Dialogue.spoken(180) == "3 min")
	check("spoken 4800", Dialogue.spoken(4800) == "1 h 20 min", Dialogue.spoken(4800))
	check("initials", Dialogue.initials("Maya Weber") == "MW" and Dialogue.initials("Kofi") == "K")
	local lo, hi = Dialogue.lunchWindow()
	check("lunch window from personalities", math.abs(lo - 11.75) < 1e-9 and math.abs(hi - (11.75 + 105 / 60)) < 1e-9, lo .. " " .. hi)

	------------------------------------------------------------------ C. realistic owner session → facts
	local d = Template.new()
	d.company = { name = "Nimbus Labs", logo = "N", color = "cyan", spec = "general", reputation = 10, foundedAt = 0 }
	d.money = 123456
	d.empire.office = 2
	d.empire.employees = { researcher = 3, engineer = 2, curator = 1, marketer = 2 }
	EmpireMath.syncProfiles(d.empire, OWNER)
	d.empire.staffProfiles.researcher[1].k = 4; d.empire.staffProfiles.researcher[1].w = 1.2
	d.empire.researchJob = { id = "pipeline", elapsed = 10, seconds = 35 }
	d.empire.points = 88.4
	d.empire.applicants = { { id = "a1", st = "new" }, { id = "a2", st = "new" }, { id = "a3", st = "invited" } }
	d.empire.history = {}
	for i = 1, 12 do d.empire.history[i] = { profit = if i <= 6 then 600 else 900 } end
	d.data = { general = { tokens = 3e9, quality = 0.6 }, code = { tokens = 1e9, quality = 0.8 } }
	d.gpus = { consumer = 2 }
	d.models = {
		m1 = { id = "m1", name = "Nimbus-1", status = "live", overall = 61.4, stats = {} },
		m2 = { id = "m2", name = "Nimbus-2", status = "trained", overall = 70.25, stats = {} },
		m3 = { id = "m3", name = "Nimbus-3", status = "training", overall = 0, stats = {} },
	}
	d.modelOrder = { "m1", "m2", "m3" }
	d.training = { modelId = "m3", workTotal = 1000, workDone = 250, cost = 0, expected = 60, qualityMod = 1, eventRolled = false, epoch = 0, loss = {}, log = {} }
	d.stats.modelsTrained = 2; d.stats.modelsReleased = 1
	local live = { users = 4321, revenue = 12.5, cost = 4.25, perModel = {}, npcUsers = {}, campus = { passes = { { id = 1 }, { id = 2 } } } }
	local f = Dialogue.facts(d, live)
	check("facts cash", f.cash == 123456)
	check("facts profit/min", math.abs(f.profitPerMin - (12.5 - 4.25) * 60) < 1e-9)
	check("facts trend", f.trendRecent == 900 and f.trendDelta == 300, tostring(f.trendRecent) .. " " .. tostring(f.trendDelta))
	check("facts live/best", f.live == 1 and f.best and f.best.name == "Nimbus-2" and f.best.overall == 70.25)
	check("facts training", f.training and f.training.model == "Nimbus-3" and math.abs(f.training.progress - 0.25) < 1e-9 and type(f.training.eta) == "number" and f.training.eta > 0)
	local rate = EmpireMath.trainingRate(d.gpus, 1000, d.empire)
	check("facts training eta = remaining / EmpireMath.trainingRate", math.abs(f.training.eta - 750 / rate) < 1e-6, f.training.eta)
	check("facts staff/cap", f.staff == 8 and f.cap == EmpireConfig.OFFICES[2].staff)
	check("facts applicants", f.applicantsOpen == 2 and f.applicantsWaiting == 1)
	check("facts research", f.research and f.research.name == "Parallel Training" and math.abs(f.research.progress - 10 / 35) < 1e-9 and f.research.left == 25)
	check("facts data", f.tokens == 4e9 and math.abs(f.quality - 0.65) < 1e-9)
	check("facts hardware", f.vram == 24 and f.slots == 2)
	local empty = Template.new(); empty.company = d.company
	local fe = Dialogue.facts(empty, { users = 0, revenue = 0, cost = 0 })
	check("facts on a fresh save", fe.live == 0 and fe.best == nil and fe.training == nil and fe.staff == 0 and fe.research == nil and fe.nextResearch and fe.nextResearch.name == EmpireConfig.RESEARCH[1].name)
	local fz = Dialogue.facts({}, nil)
	check("facts tolerate missing tables", fz.cash == 0 and fz.live == 0 and fz.staff == 0)

	------------------------------------------------------------------ D. lines for every role/job x state
	local TIER = 2
	local function placesFor(viewer, kind, level)
		return Dialogue.places(TIER, Dialogue.placeIds(viewer, kind), level)
	end
	local bld = { floors = Plan.floors(TIER), rooms = 0, cameras = 0, restrooms = 0, stops = #Plan.liftStops(TIER), publicRooms = {} }
	for _, r in Plan.rooms(TIER) do if not r.hidden then bld.rooms += 1; if r.camera then bld.cameras += 1 end; if r.kind == "wc" or r.kind == "restrooms" or r.kind == "showers" then bld.restrooms += 1 end; if r.access == "public" then table.insert(bld.publicRooms, r.name) end end end
	local menu = {}; for _, s in CampusConfig.SNACKS do table.insert(menu, { name = s.name, price = s.price, seconds = s.seconds }) end
	local function ctx(viewer, kind, extra)
		local c = { viewer = viewer, viewerName = if viewer == "owner" then "Noah Founder" else "Guest Player", day = 7, hour = 10.5, tier = TIER, facts = f,
			company = "Nimbus Labs", ownerName = "Noah Founder", building = bld, visitorsNow = 2, visitorsToday = 5, talksToday = 3, menu = menu, dining = 53,
			desks = 143, passes = 2, places = placesFor(viewer, kind, 0) }
		for k, v in extra or {} do c[k] = v end
		return c
	end
	local function subj(roleId, job, extra)
		local s = { name = "Maya Weber", roleId = roleId, job = job, seed = 12345, index = 1, activity = "WORKING", task = nil, room = "Data Studio", level = "1", levelNumber = 1 }
		for k, v in extra or {} do s[k] = v end
		return s
	end
	local function bad(text)
		return type(text) ~= "string" or #text < 8 or has(text, "{") or has(text, "}") or has(text, "nil") or has(text, "nan") or has(text, "inf") or has(text, "  ")
	end
	local totalLines, totalAnswers = 0, 0
	-- walk the whole option tree (BFS over asked-sets is overkill: ask every offered chip in order)
	local function walk(lines, label)
		local asked = {}
		local opts = lines.options
		local steps, ok = 0, true
		check(label .. ": first options 2..4", #opts >= 2 and #opts <= 4, #opts)
		check(label .. ": bye is last", opts[#opts].id == "bye")
		while true do
			steps += 1
			if steps > 30 then ok = false; break end
			local pickOpt = opts[1]
			if pickOpt.id == "where:more" and opts[2] and opts[2].id ~= "bye" then pickOpt = opts[1] end
			local answer, nextOpts = Dialogue.step(lines, asked, pickOpt.id)
			if not answer then ok = false; break end
			totalAnswers += 1
			if bad(answer.text) then ok = false; say("   bad answer", label, pickOpt.id, answer.text) end
			if answer.close then break end
			if #nextOpts < 1 or #nextOpts > 4 or nextOpts[#nextOpts].id ~= "bye" then ok = false; say("   bad options", label, #nextOpts); break end
			opts = nextOpts
		end
		check(label .. ": option walk ends with bye, every answer clean", ok)
	end
	local OWNER_STATES = {
		researcher = { { "WORKING", "RunExperiment" }, { "RESEARCH", "UseWhiteboard" }, { "MODEL_REVIEW", "AnalyzeModel" }, { "RESEARCH", "ArchitectureStudy" } },
		engineer = { { "WORKING", "WriteCode" }, { "MONITOR_TRAINING", "MonitorTraining" }, { "SERVER_CHECK", "InspectServer" }, { "MODEL_REVIEW", "ReviewModel" }, { "SERVER_CHECK", "InspectHardware" } },
		curator = { { "DATA_REVIEW", "CleanDataset" }, { "DATA_REVIEW", "CheckQuality" }, { "DATA_REVIEW", "MonitorPipeline" } },
		marketer = { { "MARKETING", "AnalyzeMarket" }, { "MARKETING", "PlanLaunch" }, { "MARKETING", "CheckCustomers" } },
	}
	local COMMON_STATES = { { "LUNCH", "Lunch" }, { "COFFEE_BREAK", "Coffee" }, { "COFFEE_BREAK", "RoofBreak" }, { "MEETING", "TeamMeeting" }, { "MEETING", "ModelReviewMeeting" },
		{ "TALKING", "DiscussWork" }, { "WALKING", "Lunch" }, { "WALKING", "WriteCode" }, { "ELEVATOR", nil }, { "WAIT_AT_DESK", nil }, { "ARRIVING", nil }, { "SOMETHING_NEW", "FutureJobStep" } }
	for roleId, states in OWNER_STATES do
		local all = table.clone(states); for _, s in COMMON_STATES do table.insert(all, s) end
		for _, st in all do
			for _, seed in { 3, 12345, 99 } do
				local s = subj(roleId, EmployeeConfig.ROLES[roleId], { activity = st[1], task = st[2], seed = seed, skill = 4, wage = 0.42 })
				local lines = Dialogue.lines(s, ctx("owner", roleId))
				totalLines += 1
				local label = roleId .. "/" .. st[1] .. "/" .. tostring(st[2]) .. "/" .. seed
				check(label .. ": greeting", not bad(lines.greeting), lines.greeting)
				check(label .. ": work answer", not bad(lines.answers.work.text), lines.answers.work.text)
				if seed == 12345 then walk(lines, label) end
			end
		end
	end
	local OPS_JOBS = table.clone(EmployeeConfig.OPERATIONS_JOBS)
	for _, j in { "Hotel Reception", "Housekeeping", "Cleaner", "Mailroom", "Campus Operations" } do table.insert(OPS_JOBS, j) end
	local OPS_STATES = { { "WORKING", "CampusOperations" }, { "WORKING", nil }, { "COFFEE_BREAK", "Coffee" }, { "LUNCH", "Lunch" }, { "WALKING", "CampusOperations" }, { "WORKING", "ServeLunch" } }
	for _, job in OPS_JOBS do
		local kind = Dialogue.kind("support", job)
		for _, st in OPS_STATES do
			for _, viewer in { "owner", "visitor" } do
				if viewer == "visitor" and not Dialogue.isPublicKind(kind) then continue end
				local s = subj("support", job, { activity = st[1], task = st[2], room = "Reception Hall", level = "G", levelNumber = 0 })
				local lines = Dialogue.lines(s, ctx(viewer, kind))
				totalLines += 1
				local label = job .. "/" .. viewer .. "/" .. st[1] .. "/" .. tostring(st[2])
				check(label .. ": greeting", not bad(lines.greeting), lines.greeting)
				check(label .. ": kind", lines.kind == kind)
				walk(lines, label)
			end
		end
	end

	------------------------------------------------------------------ E. numbers equal the real state
	local function owner(roleId, extraS, extraC, kindOverride)
		local job = if EmployeeConfig.ROLES[roleId] then EmployeeConfig.ROLES[roleId] else roleId
		local rid = if EmployeeConfig.ROLES[roleId] and roleId ~= "support" then roleId else "support"
		local s = subj(rid, job, extraS)
		return Dialogue.lines(s, ctx("owner", kindOverride or Dialogue.kind(rid, job), extraC)), s
	end
	local L = owner("researcher", { skill = 4, wage = 0.25 * 1.2 })
	local comp = L.answers.company.text
	check("company: cash", has(comp, Format.money(123456)), comp)
	check("company: profit trend rising +300", has(comp, "rising") and has(comp, Format.money(900)) and has(comp, Format.money(300)), comp)
	check("company: live/users/best", has(comp, "1 model live") and has(comp, Format.compact(4321)) and has(comp, "Nimbus-2") and has(comp, string.format("%.1f", 70.25)), comp)
	local research = L.answers.research.text
	check("research: name/percent/left", has(research, "Parallel Training") and has(research, Format.percent(10 / 35, 0)) and has(research, Dialogue.spoken(25)), research)
	local you = L.answers.you.text
	check("you: skill + wage", has(you, "4 out of 5") and has(you, string.format("$%.2f", 0.3)) and has(you, Format.money(0.3 * 1200)), you)
	local p = EmployeeConfig.personalityFromSeed(12345)
	local day = L.answers.day.text
	check("day: start/finish/lunch from the personality seed", has(day, Dialogue.clock(p.start)) and has(day, Dialogue.clock(p.finish)) and has(day, Dialogue.clock(p.lunch)) and has(day, Dialogue.clock(10.5)), day)
	local LE = owner("engineer", { task = "MonitorTraining", activity = "MONITOR_TRAINING" })
	check("engineer training: percent + eta + vram", has(LE.answers.training.text, "Nimbus-3") and has(LE.answers.training.text, "25%") and has(LE.answers.training.text, Dialogue.spoken(f.training.eta)) and has(LE.answers.training.text, "24 GB"), LE.answers.training.text)
	check("engineer work (MonitorTraining) cites progress", has(LE.answers.work.text, "25%"), LE.answers.work.text)
	local LC = owner("curator", { task = "CleanDataset", activity = "DATA_REVIEW" })
	check("curator data: tokens/quality/curators", has(LC.answers.data.text, Format.tokens(4e9)) and has(LC.answers.data.text, "65%") and has(LC.answers.data.text, "1 curator"), LC.answers.data.text)
	local LM = owner("marketer", { task = "AnalyzeMarket", activity = "MARKETING" })
	check("marketer market: users/revenue/cost", has(LM.answers.market.text, Format.compact(4321)) and has(LM.answers.market.text, Format.money(12.5 * 60)) and has(LM.answers.market.text, Format.money(4.25 * 60)), LM.answers.market.text)
	check("work answer names the room + level", has(LM.answers.work.text, "Data Studio (1)"), LM.answers.work.text)
	local LR = owner("Reception")
	check("reception visitors: now/today/applicants", has(LR.answers.visitors.text, "2 visitors in the building") and has(LR.answers.visitors.text, "5 visitors so far today") and has(LR.answers.visitors.text, "1 candidate") and has(LR.answers.visitors.text, "2 new applications"), LR.answers.visitors.text)
	check("reception work: conversations today", has(LR.answers.work.text, "3 conversations"), LR.answers.work.text)
	local LB = owner("Barista")
	for _, s in CampusConfig.SNACKS do check("menu lists " .. s.name, has(LB.answers.menu.text, s.name .. " " .. Format.money(s.price)), LB.answers.menu.text) end
	check("lunch: window + seats, no invented count", has(LB.answers.lunch.text, "11:45") and has(LB.answers.lunch.text, "13:30") and has(LB.answers.lunch.text, "53 seats") and not has(LB.answers.lunch.text, "served"), LB.answers.lunch.text)
	if EmployeeConfig.LUNCH_SERVICE then
		check("lunch: the kitchen's service hours from EmployeeConfig.LUNCH_SERVICE", has(LB.answers.lunch.text, "serves lunch from " .. Dialogue.clock(EmployeeConfig.LUNCH_SERVICE[1]) .. " to " .. Dialogue.clock(EmployeeConfig.LUNCH_SERVICE[2])), LB.answers.lunch.text)
	end
	local LP = owner("Barista", { pose = "pour" })
	check("ops work reflects the visible Pose, then the post text", string.sub(LP.answers.work.text, 1, 17) == "Pulling a coffee " and has(LP.answers.work.text, "offee") and has(LP.answers.work.text, "Data Studio (1)"), LP.answers.work.text)
	local LP2 = owner("Barista", { pose = "unknownPose" })
	check("unknown Pose falls back to the post text", string.sub(LP2.answers.work.text, 1, 7) ~= "Pulling" and has(LP2.answers.work.text, "offee") and has(LP2.answers.work.text, "Data Studio (1)"), LP2.answers.work.text)
	local LB2 = owner("Chef", nil, { lunches = 17 })
	check("lunch: served count when reported", has(LB2.answers.lunch.text, "17 lunches served today"), LB2.answers.lunch.text)
	local LS = owner("Security")
	check("security access: public rooms + guest cards", has(LS.answers.access.text, "the Reception Hall") and has(LS.answers.access.text, "the House Kitchen Café") and has(LS.answers.access.text, " and the ") and has(LS.answers.access.text, "2 guest cards"), LS.answers.access.text)
	check("security cameras: room + count", has(LS.answers.cameras.text, "Campus Security") and has(LS.answers.cameras.text, "pavilion") and has(LS.answers.cameras.text, tostring(bld.cameras) .. " rooms"), LS.answers.cameras.text)
	local LI = owner("IT Support", nil, { faults = { count = 2, rooms = { "Data Studio", "Model Lab" } } })
	check("IT faults: count + rooms", has(LI.answers.faults.text, "2 open faults") and has(LI.answers.faults.text, "Data Studio, Model Lab"), LI.answers.faults.text)
	local LI0 = owner("IT Support", nil, { faults = { count = 0, rooms = {} } })
	check("IT faults: none open", has(LI0.answers.faults.text, "No open faults"), LI0.answers.faults.text)
	local LIn = owner("IT Support")
	check("IT faults: no fault system → generic, no count claim", not string.find(LIn.answers.faults.text, "%d") and has(LIn.answers.faults.text, "No ticket system"), LIn.answers.faults.text)
	check("IT hardware: desks + gpus", has(LIn.answers.hardware.text, "143 computer desks") and has(LIn.answers.hardware.text, "2 GPU slots"), LIn.answers.hardware.text)
	local LF = owner("Facilities")
	check("facilities building: floors/rooms/stops", has(LF.answers.building.text, tostring(bld.floors) .. " floors") and has(LF.answers.building.text, tostring(bld.rooms) .. " rooms") and has(LF.answers.building.text, tostring(bld.stops) .. " stops"), LF.answers.building.text)
	local LFl = owner("Fleet", nil, { cars = { owned = { "Founder's Hatch", "Studio Cargo" }, ready = "Founder's Hatch" } })
	check("fleet cars: names", has(LFl.answers.cars.text, "2 company cars") and has(LFl.answers.cars.text, "Studio Cargo"), LFl.answers.cars.text)
	local LH = owner("Hotel Reception")
	check("hotel placeholder until the hotel exists", has(LH.answers.rooms.text, "isn't taking guests yet"), LH.answers.rooms.text)
	local LH2 = owner("Hotel Reception", nil, { hotel = { guests = 3, rooms = 10 } })
	check("hotel guests when reported", has(LH2.answers.rooms.text, "3 guests") and has(LH2.answers.rooms.text, "7 rooms free"), LH2.answers.rooms.text)
	local LHk = owner("Housekeeping")
	check("housekeeping: no guests yet → washrooms, not the hotel line", has(LHk.answers.clean.text, "No hotel guests yet") and has(LHk.answers.clean.text, tostring(bld.restrooms) .. " washrooms") and LHk.answers.clean.text ~= LHk.answers.rooms.text, LHk.answers.clean.text)
	local LHk2 = owner("Housekeeping", nil, { hotel = { guests = 4, rooms = 10 } })
	check("housekeeping: guest rooms when the hotel reports guests", has(LHk2.answers.clean.text, "4 guest rooms"), LHk2.answers.clean.text)
	local LRw = owner("researcher", { task = nil, activity = "RESEARCH" })
	check("hired role without a task id still cites its numbers", has(LRw.answers.work.text, "Parallel Training"), LRw.answers.work.text)
	local LCl = owner("Cleaner")
	check("cleaner: washrooms from the plan", has(LCl.answers.clean.text, tostring(bld.restrooms) .. " washrooms"), LCl.answers.clean.text)
	local LOps = owner("Reception", { shiftStart = 7.5, shiftEnd = 16 })
	check("ops shift when the rig reports one", has(LOps.answers.day.text, "7:30") and has(LOps.answers.day.text, "16:00"), LOps.answers.day.text)
	local LEmpty = Dialogue.lines(subj("engineer", "ML Engineer"), ctx("owner", "engineer", { facts = fe }))
	check("fresh company: nothing training / no gpu", has(LEmpty.answers.training.text, "Nothing is training") and has(LEmpty.answers.training.text, "haven't installed a GPU"), LEmpty.answers.training.text)
	check("fresh company: no model yet", has(LEmpty.answers.company.text, "haven't released a model"), LEmpty.answers.company.text)

	------------------------------------------------------------------ F. directions + paging
	local LRo = owner("Reception")
	local asked = {}
	local a1, o1 = Dialogue.step(LRo, asked, "where")
	check("where → place chips (2 + more + bye)", a1 and #o1 == 4 and o1[1].id == "where:G_CAFE" and o1[2].id == "where:F_BOARDROOM" and o1[3].id == "where:more" and o1[4].id == "bye", #o1)
	local hasMore = false; for _, o in o1 do if o.id == "where:more" then hasMore = true end end
	check("6 places → paging chip", hasMore)
	local a2, o2 = Dialogue.step(LRo, asked, "where:more")
	check("page 2 lists the next places", a2 and o2[1].id == "where:F_OFFICE" and o2[2].id == "where:B1_DATAHALL" and o2[3].id == "where:more2" and o2[#o2].id == "bye", o2[1] and o2[1].id)
	local a3, o3 = Dialogue.step(LRo, asked, "where:more2")
	check("last page shows the rest (gym, roof)", a3 and #o3 == 3 and o3[1].id == "where:P0_GYM" and o3[2].id == "where:R_TERRACE" and o3[3].id == "bye", #o3)
	local a4, o4 = Dialogue.step(LRo, asked, "where:R_TERRACE")
	check("a place answer returns to the remaining topics", a4 and has(a4.text, "roof") and o4[1].id ~= "where" and o4[#o4].id == "bye")
	local LR3 = Dialogue.lines(subj("support", "Reception"), ctx("visitor", "reception"))
	local _, o5 = Dialogue.step(LR3, {}, "where")
	check("3 places fit one page (no paging chip)", #o5 == 4 and o5[3].id == "where:G_VISITOR" and o5[4].id == "bye", #o5)
	local cafe = Dialogue.places(TIER, { "G_CAFE" }, 0)[1]
	check("café: ground floor, on the LEFT entering from the street, same floor", has(cafe.text, "ground floor (G)") and has(cafe.text, "on the left") and has(cafe.text, "on this floor"), cafe.text)
	local lounge = Dialogue.places(TIER, { "G_VISITOR" }, 0)[1]
	check("visitor lounge: on the RIGHT", has(lounge.text, "on the right") and has(lounge.text, "at the front"), lounge.text)
	local board = Dialogue.places(TIER, { "F_BOARDROOM" }, 0)[1]
	local fl = Plan.founderLevel(TIER)
	check("boardroom: founder level label + lift hint", has(board.text, "level " .. Plan.levelLabel(TIER, fl)) and has(board.text, "Take the lift"), board.text)
	local gym = Dialogue.places(TIER, { "P0_GYM" }, 0)[1]
	check("gym: pavilion", has(gym.text, "pavilion"), gym.text)
	local roof = Dialogue.places(TIER, { "R_TERRACE" }, 0)[1]
	check("roof terrace: R", has(roof.text, "roof (R)"), roof.text)
	check("hidden rooms are never offered", #Dialogue.places(TIER, { "P1_SECRET", "P1_PASSAGE", "G_CAFE" }, 0) == 1)
	for _, kind in { "reception", "security", "hotel", "host", "barista", "chef" } do
		for _, pl in Dialogue.places(TIER, Dialogue.placeIds("visitor", kind), 0) do check("visitor place is public: " .. kind .. " " .. pl.id, pl.access == "public") end
	end
	-- right/left sanity against the plan geometry: café centre x > 0, lounge centre x < 0
	local rc, rl = Plan.room(TIER, "G_CAFE"), Plan.room(TIER, "G_VISITOR")
	check("geometry: café east (+X), lounge west (-X)", (rc.x1 + rc.x2) / 2 > 0 and (rl.x1 + rl.x2) / 2 < 0)

	------------------------------------------------------------------ G. visitors: public facts only
	local cashText = Format.money(123456)
	for _, job in { "Reception", "Security", "Barista", "Cafe Host", "Chef", "Hotel Reception" } do
		local kind = Dialogue.kind("support", job)
		local lines = Dialogue.lines(subj("support", job), ctx("visitor", kind))
		local leak = has(lines.greeting, cashText)
		for _, a in lines.answers do if has(a.text, cashText) or has(a.text, "a minute") then leak = true end end
		check("visitor view leaks no cash/profit: " .. job, not leak)
		check("visitor greeting introduces the person: " .. job, has(lines.greeting, "I'm Maya") and has(lines.greeting, "Nimbus Labs"), lines.greeting)
		check("visitor bye chip", lines.options[#lines.options].text == "Thanks, bye!")
	end
	local LV = Dialogue.lines(subj("support", "Reception"), ctx("visitor", "reception"))
	check("visitor about: founder + staff + live", has(LV.answers.about.text, "Noah Founder") and has(LV.answers.about.text, "8 specialists") and has(LV.answers.about.text, "1 model live"), LV.answers.about.text)
	check("visitor visitors: count today", has(LV.answers.visitors.text, "5 visitors today"), LV.answers.visitors.text)
	local LVs = Dialogue.lines(subj("support", "Security"), ctx("visitor", "security"))
	check("visitor access: guest card from the founder", has(LVs.answers.access.text, "guest card from Noah Founder"), LVs.answers.access.text)

	------------------------------------------------------------------ H. determinism, variety, tone
	local A = Dialogue.lines(subj("engineer", "ML Engineer"), ctx("owner", "engineer"))
	local B = Dialogue.lines(subj("engineer", "ML Engineer"), ctx("owner", "engineer"))
	check("deterministic for the same person/day/state", A.greeting == B.greeting and A.answers.company.text == B.answers.company.text)
	local greetings = {}
	for dday = 1, 12 do greetings[Dialogue.lines(subj("engineer", "ML Engineer"), ctx("owner", "engineer", { day = dday })).greeting] = true end
	local n = 0; for _ in greetings do n += 1 end
	check("greeting varies over days", n >= 2, n)
	local tones = { confident = 0, calm = 0, shy = 0 }
	for seed = 0, 299 do tones[Dialogue.tone(seed)] += 1 end
	check("all three tones occur", tones.confident > 0 and tones.calm > 0 and tones.shy > 0)
	check("tone follows personality.social", Dialogue.tone(80) == "confident" and Dialogue.tone(10) == "shy" and Dialogue.tone(50) == "calm")
	local shy = Dialogue.lines(subj("engineer", "ML Engineer", { seed = 10 }), ctx("owner", "engineer"))
	local bold = Dialogue.lines(subj("engineer", "ML Engineer", { seed = 80 }), ctx("owner", "engineer"))
	check("tone changes the farewell", shy.farewell ~= bold.farewell, shy.farewell .. " | " .. bold.farewell)

	------------------------------------------------------------------ J. what the building has: team / room / tour
	local ROLE_WORD = { researcher = "AI researcher", engineer = "ML engineer", curator = "data curator", marketer = "growth manager" }
	for _, role in EmpireConfig.ROLES do
		local desk = { room = "Data Operations", level = "1", dept = "data", desks = 8, busy = 5 }
		local L = Dialogue.lines(subj(role.id, role.name, { desk = desk }), ctx("owner", role.id))
		local t = L.answers.team and L.answers.team.text
		check("team topic exists: " .. role.id, t ~= nil)
		check("team: desk room + level, no redundant department: " .. role.id, has(t, "My desk is in the Data Operations (1).") and not has(t, "part of Data Operations"), t)
		check("team: desks in that room + in use: " .. role.id, has(t, "8 desks in there, 5 in use right now."), t)
		local n = f.roles[role.id]
		check("team: head count of the role: " .. role.id, if n == 1 then has(t, "I'm our only " .. ROLE_WORD[role.id]) else has(t, Format.int(n) .. " " .. ROLE_WORD[role.id] .. "s"), t)
		local gain = string.match(role.desc, "^(.-) per employee")
		check("team: the role's real effect from EmpireConfig.ROLES.desc: " .. role.id, gain ~= nil and has(t, "Each of us adds " .. gain), t)
		check("team answer clean: " .. role.id, not bad(t), t)
	end
	local Lc = Dialogue.lines(subj("curator", "Data Curator", { desk = { room = "Pipeline Lab", level = "1", dept = "data", desks = 4, busy = 9 } }), ctx("owner", "curator"))
	check("team: other department name is added; busy clamped to desks", has(Lc.answers.team.text, "Pipeline Lab (1), part of Data Operations.") and has(Lc.answers.team.text, "4 desks in there, 4 in use"), Lc.answers.team.text)
	check("team: the rest of the desc (curator)", has(Lc.answers.team.text, "(improves with research)"), Lc.answers.team.text)
	local Ln = Dialogue.lines(subj("researcher", "AI Researcher"), ctx("owner", "researcher"))
	check("team without a desk claims no desk", not has(Ln.answers.team.text, "My desk") and has(Ln.answers.team.text, "Each of us adds"), Ln.answers.team.text)
	-- room topic: offered only with a purpose; facts from the plan room
	local noRoom = Dialogue.lines(subj("support", "Barista"), ctx("owner", "barista"))
	check("no room kind → no room topic", noRoom.answers.room == nil)
	local stair = Dialogue.lines(subj("support", "Barista", { roomKind = "stair", room = "Stairs" }), ctx("owner", "barista"))
	check("circulation (stairs) → no room topic", stair.answers.room == nil)
	local cafeL = Dialogue.lines(subj("support", "Cafe Host", { roomKind = "cafe", room = "House Kitchen Café", roomAccess = "public" }), ctx("visitor", "host"))
	local ct = cafeL.answers.room and cafeL.answers.room.text
	check("room: café purpose + seats + door sign", has(ct, "This is the House Kitchen Café.") and has(ct, "speed boost") and has(ct, "53 seats") and has(ct, Plan.CLASS_LABEL.public), ct)
	local teamRoom = Dialogue.lines(subj("marketer", "Growth Manager", { roomKind = "team", room = "Growth Team", roomDept = "growth", roomDesks = 10, roomBusy = 3, roomCamera = true }), ctx("owner", "marketer"))
	local tr = teamRoom.answers.room.text
	check("room: department room → department name + purpose + desks + camera", has(tr, "part of Product & Growth") and has(tr, "users and API customers") and has(tr, "10 desks in here, 3 in use right now.") and has(tr, "security cameras"), tr)
	local focusRoom = Dialogue.lines(subj("researcher", "AI Researcher", { roomKind = "focus", room = "Focus Room 1", roomDept = "research", roomDesks = 1, roomBusy = 1 }), ctx("owner", "researcher"))
	check("room: focus room names its department", has(focusRoom.answers.room.text, "Focus Room 1, a focus room of AI Research") and has(focusRoom.answers.room.text, "1 desk in here, 1 in use"), focusRoom.answers.room.text)
	local hall = Dialogue.lines(subj("engineer", "ML Engineer", { roomKind = "datahall", room = "Data Hall", roomAccess = "compute" }), ctx("owner", "engineer"))
	check("room: data hall + compute door sign", has(hall.answers.room.text, "GPU racks") and has(hall.answers.room.text, Plan.CLASS_LABEL.compute), hall.answers.room.text)
	-- every room of every tier: explained rooms read cleanly; only circulation stays unexplained
	local CIRCULATION = { stair = true, spine = true, pavilion_corridor = true, service_passage = true, b1_lobby = true, roof_lobby = true, liftpit = true }
	local explained, unexplained = 0, {}
	for tier = 1, 4 do
		for _, r in Plan.rooms(tier) do
			-- (buildings package) guest house rooms (r.annex) are new kinds: their purpose lines are requested
			-- from the talk package (design/requests/buildings.md); until then they are not part of this check
			if not r.hidden and not (r :: any).annex then
				local sub = subj("support", "Facilities", { roomKind = r.kind, room = r.name, roomDept = r.dept, roomAccess = r.access, roomCamera = r.camera == true, roomDesks = r.desks, roomBusy = 0 })
				if Dialogue.explainsRoom(sub) then
					explained += 1
					local L = Dialogue.lines(sub, ctx("owner", "facilities"))
					local text = L.answers.room and L.answers.room.text
					if bad(text) or not has(text, r.name) then check("room text for " .. r.id, false, text) end
				else
					unexplained[r.kind] = true
				end
			end
		end
	end
	local onlyCirculation = true
	for kind in unexplained do if not CIRCULATION[kind] then onlyCirculation = false; say("   unexplained room kind " .. kind) end end
	check("every room kind except circulation has a purpose", onlyCirculation)
	check("rooms explained over tiers 1-4", explained > 300, explained)
	-- tour: floor by floor from the plan
	local guide = Dialogue.floorGuide(4)
	local labels = 0
	for _, level in Plan.levels(4) do if has(guide, Plan.levelLabel(4, level) .. " ") then labels += 1 end end
	check("floor guide (tier 4) names every level", labels == #Plan.levels(4) and has(guide, "B1 garage, data hall") and has(guide, "6 founder suite") and has(guide, "R roof terrace"), guide)
	local LT = Dialogue.lines(subj("support", "Reception"), ctx("owner", "reception", { desksBusy = 61 }))
	local tour = LT.answers.tour.text
	check("tour (owner): floors, guide, desks in use, visitor rooms", has(tour, Format.int(Plan.floors(TIER)) .. " floors") and has(tour, Dialogue.floorGuide(TIER)) and has(tour, "143 computer desks in total, 61 in use right now.") and has(tour, "Visitors may use the "), tour)
	local LTv = Dialogue.lines(subj("support", "Reception"), ctx("visitor", "reception", { desksBusy = 61 }))
	check("tour (visitor): public rooms, no desk numbers", has(LTv.answers.tour.text, "As a visitor you're welcome in the ") and not has(LTv.answers.tour.text, "desk"), LTv.answers.tour.text)
	local LFb = owner("Facilities", nil, { desksBusy = 40 })
	check("building: desks in use", has(LFb.answers.building.text, "143 computer desks, 40 in use right now."), LFb.answers.building.text)
	-- lunch phases from the live staff record
	local function lunchAt(phase) return Dialogue.lines(subj("engineer", "ML Engineer", { activity = "LUNCH", task = "Lunch", lunch = phase }), ctx("owner", "engineer")).answers.work.text end
	check("lunch phase queue", has(lunchAt("queue"), "lunch queue"), lunchAt("queue"))
	check("lunch phase toSeat", has(lunchAt("toSeat"), "looking for a seat"))
	check("lunch phase return", has(lunchAt("return"), "tray back"))
	check("lunch phase eat", has(lunchAt("eat"), "café"))
	-- menu: the special's real speed-boost time from CampusConfig.SNACKS
	local special = CampusConfig.SNACKS[(7 % #CampusConfig.SNACKS) + 1]
	check("menu: boost time of today's pick", has(LB.answers.menu.text, "for " .. Dialogue.spoken(special.seconds)), LB.answers.menu.text)
	-- variety: several templates per topic, stable within a day
	local function distinct(fn)
		local seen, n = {}, 0
		for dday = 1, 40 do local t = fn(dday); if not seen[t] then seen[t] = true; n += 1 end end
		return n
	end
	check("variety: barista work answer", distinct(function(dd) return Dialogue.lines(subj("support", "Barista"), ctx("owner", "barista", { day = dd })).answers.work.text end) >= 2)
	check("variety: company answer", distinct(function(dd) return Dialogue.lines(subj("engineer", "ML Engineer"), ctx("owner", "engineer", { day = dd })).answers.company.text end) >= 3)
	check("variety: day answer", distinct(function(dd) return Dialogue.lines(subj("engineer", "ML Engineer"), ctx("owner", "engineer", { day = dd })).answers.day.text end) >= 3)
	check("variety: about-me answer", distinct(function(dd) return Dialogue.lines(subj("engineer", "ML Engineer", { skill = 4, wage = 0.35 }), ctx("owner", "engineer", { day = dd })).answers.you.text end) == 2)
	check("variety: farewell", distinct(function(dd) return Dialogue.lines(subj("engineer", "ML Engineer"), ctx("owner", "engineer", { day = dd })).farewell end) == 2)
	check("variety: menu", distinct(function(dd) return Dialogue.lines(subj("support", "Chef"), ctx("owner", "chef", { day = dd })).answers.menu.text end) >= 2)
	local owners = true
	for seed = 0, 60 do
		for dd = 1, 6 do
			local fw = Dialogue.lines(subj("engineer", "ML Engineer", { seed = seed }), ctx("owner", "engineer", { day = dd })).farewell
			if not has(fw, "Noah") then owners = false end
		end
	end
	check("every owner farewell names the founder", owners)

	------------------------------------------------------------------ I. sample conversations
	if not QUIET then
		local function sample(job, roleId, viewer, extraS)
			local kind = Dialogue.kind(roleId, job)
			local lines = Dialogue.lines(subj(roleId, job, extraS), ctx(viewer, kind, { lunches = if kind == "chef" then 17 else nil }))
			say(string.format("--- %s (%s, %s view)", job, kind, viewer))
			say("  NPC: " .. lines.greeting)
			local askedS, opts = {}, lines.options
			for _ = 1, 3 do
				local o = opts[1]
				if o.id == "bye" then break end
				local a, nx = Dialogue.step(lines, askedS, o.id)
				say("  You: " .. o.text)
				say("  NPC: " .. a.text)
				if a.close then break end
				opts = nx
			end
		end
		for _, role in EmpireConfig.ROLES do sample(role.name, role.id, "owner", { skill = 4, wage = role.wage }) end
		for _, job in OPS_JOBS do sample(job, "support", "owner", { room = "Reception Hall", level = "G", levelNumber = 0 }) end
		for _, job in { "Reception", "Security", "Barista", "Chef", "Cafe Host", "Hotel Reception" } do sample(job, "support", "visitor", { room = "Reception Hall", level = "G", levelNumber = 0 }) end
	end
	say(string.format("dialogue: %d line sets, %d answers walked", totalLines, totalAnswers))
end
setfenv(body, M.envFor(nil))
local ok, err = M.runMain(body, { timeout = 60 })
if not ok then say("ERROR: " .. tostring(err)); failc += 1 end
say(string.format("talk dialogue tests: %d passed, %d failed", pass, failc))
if failc > 0 then error("talk dialogue tests failed", 0) end
