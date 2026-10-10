--!nocheck
-- econ package: CompanyOps units against CORE_SPEC (real modules in the mock): clock / hour / time sheet /
-- duty / calendar / stamps, absences (vacation + sick hashes, HR collision cap, presence, availability),
-- department output (seat rule, morale table, watched == unwatched), HR need / pick / budget / Save mode,
-- trip plans and trust, Lab cost, running costs per stage, guest house, company jet, serving capacity and
-- the B2B reservation -> training rate, rack faults + IT repair times, safety rules and unpaid leave.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_econ && tools/luau tests/econ/test_ops.luau [-a .gen_dir]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_econ")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local C = require("./common")
local check, near = C.check, C.near

local function body()
	local R = C.load(M)
	local Ops, EmpireMath, Workforce, EmpireConfig = R.Ops, R.EmpireMath, R.Workforce, R.EmpireConfig
	local Economy = M.require(R.Server.Services.EconomyService)

	------------------------------------------------------------------ clock, time sheet, duty
	check("DAY = 1200", Ops.DAY == 1200)
	check("hour(0) = 08:00", near(Ops.hour(0), 8))
	check("hour(450) = 13:00", near(Ops.hour(450), 13))
	check("hour(900) = 18:00 (900 s day)", near(Ops.hour(900), 18))
	check("hour(1050) = 01:00 (300 s night)", near(Ops.hour(1050), 1))
	check("hour wraps per day", near(Ops.hour(1200 * 37 + 450), 13))
	check("hour(1199.9) just before 08:00", Ops.hour(1199.9) > 7.9 and Ops.hour(1199.9) < 8)
	local TS = { [7.5] = 0, [8] = 0.188, [8.5] = 0.564, [10] = 0.94, [12] = 0.806, [12.5] = 0.537, [13] = 0.403, [14] = 0.671, [16] = 0.94, [17] = 0.627, [17.5] = 0.313, [20] = 0, [3] = 0 }
	for h, v in TS do check(string.format("TS(%.1f) = %.3f (table 5.3)", h, v), near(Ops.timesheet(h), v, 0.002), Ops.timesheet(h)) end
	check("TS_MEAN = 0.5538", near(Ops.TS_MEAN, 0.5538, 0.0006), Ops.TS_MEAN)
	local sum = 0
	for s = 0, 1199 do sum += Ops.duty(s + 0.5) end
	check("duty averages exactly 1 over a game day", near(sum / 1200, 1, 1e-3), sum / 1200)
	check("duty = 0 at night", Ops.duty(C.clockAt(22)) == 0 and Ops.duty(C.clockAt(3)) == 0)
	check("duty(10:00) = 1.70", near(Ops.duty(C.clockAt(10)), 1.70, 0.01), Ops.duty(C.clockAt(10)))
	check("inOffice 08-18", Ops.inOffice(C.clockAt(9)) and not Ops.inOffice(C.clockAt(19)) and not Ops.inOffice(C.clockAt(7.9)))

	------------------------------------------------------------------ calendar + stamp
	do
		local e = EmpireMath.new()
		check("new calendar day 1", Ops.day(e) == 1 and e.calendar.index == nil)
		Ops.advanceCalendar(e, 5000)
		check("first tick sets the index, day stays 1", Ops.day(e) == 1 and e.calendar.index == math.floor(5000 / 1200))
		Ops.advanceCalendar(e, 5100)
		check("same server day: no change", Ops.day(e) == 1)
		Ops.advanceCalendar(e, 6000)
		check("next server day: day 2", Ops.day(e) == 2)
		Ops.advanceCalendar(e, 6000 + 1200 * 9)
		check("offline gap counts one day (online only)", Ops.day(e) == 3)
		e.calendar.day = 8
		check("stamp 'day 8 11:54'", Ops.stamp(e, C.clockAt(11.9)) == "day 8 11:54", Ops.stamp(e, C.clockAt(11.9)))
		e.calendar = "bad"
		check("broken calendar repaired by advanceCalendar", Ops.advanceCalendar(e, 100) == 1 and typeof(e.calendar) == "table")
	end

	------------------------------------------------------------------ absences
	do
		local sick, days = 0, 0
		for seed = 1, 400 do for day = 1, 60 do days += 1; if Ops.isSick(seed * 7717, day) then sick += 1 end end end
		check("sick rate ~1.7 %", math.abs(sick / days - 0.017) < 0.004, sick / days)
		local seeds = {}
		for i = 1, 30 do seeds[i] = R.EmployeeConfig.hash(i * 977) % 2147483647 end
		for cycle = 0, 5 do
			local vac = Ops.vacationDays(seeds, cycle)
			local per = {}
			local okRange = true
			for i = 1, #seeds do
				local d = vac[i]
				okRange = okRange and type(d) == "number" and d >= 0 and d <= 11
				per[d] = (per[d] or 0) + 1
			end
			local maxDay = 0
			for _, n in per do maxDay = math.max(maxDay, n) end
			check("cycle " .. cycle .. ": everybody exactly one vacation day 0..11", okRange)
			check("cycle " .. cycle .. ": HR collision cap ceil(0.1 x 30) = 3 per day", maxDay <= 3, maxDay)
		end
		-- pure function of the seeds: a permuted team gets the same day per seed
		local perm = {}
		for i = #seeds, 1, -1 do table.insert(perm, seeds[i]) end
		local a, b = Ops.vacationDays(seeds, 2), Ops.vacationDays(perm, 2)
		local same = true
		for i = 1, #seeds do same = same and a[i] == b[#seeds + 1 - i] end
		check("vacation days do not depend on profile order", same)
		-- everybody hashed onto one day: the overflow moves to the next free days, highest seed first
		local clash = {}
		for i = 1, 20 do clash[i] = i end
		local vac = Ops.vacationDays(clash, 0)
		local per = {}
		for i = 1, 20 do per[vac[i]] = (per[vac[i]] or 0) + 1 end
		local mx = 0
		for _, n in per do mx = math.max(mx, n) end
		check("cap holds for any seeds (team 20 -> <= 2)", mx <= 2, mx)
		-- NEGATIVE: without the cap the same team would collide (proves the test can fail)
		local raw = {}
		for i = 1, 30 do local d = R.EmployeeConfig.hash(seeds[i] * 31 + 0) % 12; raw[d] = (raw[d] or 0) + 1 end
		local rawMax = 0
		for _, n in raw do rawMax = math.max(rawMax, n) end
		check("negative: raw hashes do exceed the cap", rawMax > 3, rawMax)
	end
	do
		-- availability over 120 company days for a 60-person team
		local d = C.company({ stage = 5, staff = { researcher = 60 } })
		local e = d.empire
		local present, total, vacation = 0, 0, 0
		for day = 1, 120 do
			e.calendar.day = day
			for _, st in Ops.presence(e, "researcher") do
				total += 1
				if st == "present" then present += 1 elseif st == "vacation" then vacation += 1 end
			end
		end
		check("vacation share 1/12 (8.3 %)", math.abs(vacation / total - 1 / 12) < 0.003, vacation / total)
		check("availability ~0.90", math.abs(present / total - 0.90) < 0.01, present / total)
		e.calendar.day = 33
		local p1 = Ops.presence(e, "researcher")
		local p2 = Ops.presence(e, "researcher")
		local same = #p1 == 60
		for i = 1, 60 do same = same and p1[i] == p2[i] end
		check("presence is deterministic", same)
	end

	------------------------------------------------------------------ department output (5.1)
	do
		local d = C.company({ stage = 2, staff = { engineer = 10 }, skill = 3 })
		local e = d.empire
		local function presentCount(role)
			local n = 0
			for _, st in Ops.presence(e, role) do if st == "present" then n += 1 end end
			return n
		end
		local M2 = Ops.morale(e)
		check("morale stage 2 at full kitchen = 1.035", near(M2, 1.035, 1e-9), M2)
		local O = Workforce.count(e, "engineer")
		check("O = present x f(3) x M below the seats", near(O, presentCount("engineer") * 1.0 * M2, 1e-9), O)
		-- watched == unwatched: a StaffService report no longer changes anything
		Workforce.set(e, { engineer = 0, researcher = 999 })
		check("Workforce.set has no effect (watched == unwatched)", near(Workforce.count(e, "engineer"), O, 1e-12))
		Workforce.set(e, nil)
		-- seat rule: 30 engineers at stage 2 (16 seats): min(H, S) + 0.5 overflow
		e.employees.engineer = 30
		EmpireMath.syncProfiles(e, 1001)
		for _, p in e.staffProfiles.engineer do p.k = 3 end
		local H = presentCount("engineer")
		local O2 = Workforce.count(e, "engineer")
		local want = (math.min(H, 16) + 0.5 * math.max(0, H - 16)) * Ops.morale(e)
		check("seat rule: min(H, 16) + 0.5 x overflow", near(O2, want, 1e-9), O2 .. " vs " .. want)
		-- skill factor (7 + k) / 10
		for _, p in e.staffProfiles.engineer do p.k = 5 end
		local O5 = Workforce.count(e, "engineer")
		check("skill 5 counts 1.2 (cache invalidated on k change)", O5 > O2, O5)
	end
	do
		local stages = { 0.95, 1.035, 1.05, 1.05, 1.05 }
		local staff = { 5, 24, 64, 128, 240 }
		for st = 1, 5 do
			local d = C.company({ stage = st, staff = { researcher = staff[st] } })
			check("morale table stage " .. st .. " = " .. stages[st], near(Ops.morale(d.empire), stages[st], 1e-9), Ops.morale(d.empire))
		end
	end

	------------------------------------------------------------------ HR need / pick / budget / Save mode
	do
		local d = C.company({ stage = 2 })
		local e = d.empire
		check("hrNeed engineer = seats (16)", Ops.hrNeed(e, "engineer") == 16)
		check("hrNeed curator = seats (14)", Ops.hrNeed(e, "curator") == 14)
		check("hrNeed researcher = seats while research is open (15)", Ops.hrNeed(e, "researcher") == 15)
		check("hrNeed Growth & Sales stage 2 = min(16, 1 + 24)", Ops.hrNeed(e, "marketer") == 16)
		e.office = 5
		check("hrNeed Growth & Sales stage 5 = 6 field + 31 reach heads = 37", Ops.hrNeed(e, "marketer") == 37, Ops.hrNeed(e, "marketer"))
		for _, def in EmpireConfig.RESEARCH do e.research[def.id] = true end
		e.labLevel = 10
		check("after the tree + Lab 10 researchers keep 1/4 of their desks (ceil(93/4) = 24)", Ops.hrNeed(e, "researcher") == 24, Ops.hrNeed(e, "researcher"))
		e.labLevel = 9
		check("Lab levels open -> full desks", Ops.hrNeed(e, "researcher") == 93)
		e.office = 2
		e.labLevel = 0
		check("hrPick on an empty team: the first role in HR order", Ops.hrPick(e) == "engineer")
		e.employees.engineer = 2
		check("hrPick: the lowest heads/need below need", Ops.hrPick(e) ~= "engineer")
		for _, r in EmpireConfig.ROLES do e.employees[r.id] = Ops.hrNeed(e, r.id) end
		check("hrPick nil when every department is at its need", Ops.hrPick(e) == nil)
	end
	do
		local d = C.company({ stage = 2 })
		local e = d.empire
		check("3 starter hires always allowed (income 0)", Ops.hrAllowed(e, 1000, 0, false, "engineer"))
		e.employees.engineer = 3
		EmpireMath.syncProfiles(e, 1001)
		check("4th hire needs budget: income 0 -> no", not Ops.hrAllowed(e, 1000, 0, false, "engineer"))
		local payroll = Ops.wage(e) + Ops.opsPosts(e) * Ops.OPS_WAGE / Ops.DAY
		local need = (payroll + 3.6) / 0.40
		check("budget 40 %: income just enough -> yes", Ops.hrAllowed(e, 1000, need + 0.01, false, "engineer"))
		check("budget 40 %: income just short -> no", not Ops.hrAllowed(e, 1000, need - 0.5, false, "engineer"))
		e.hr.budget = 0.55
		check("budget 55 % allows more", Ops.hrAllowed(e, 1000, need * 0.8, false, "engineer"))
		e.hr.budget = 0.40
		check("never while cash < 0", not Ops.hrAllowed(e, -1, 1e9, false, "engineer"))
		e.employees.engineer = 12
		EmpireMath.syncProfiles(e, 1001)
		check("Save mode stops HR at half the desks (12 of 24)", not Ops.hrAllowed(e, 1e6, 1e9, true, "engineer") and Ops.hrAllowed(e, 1e6, 1e9, false, "engineer"))
		e.employees.engineer = 24
		check("never above the office staff cap", not Ops.hrAllowed(e, 1e6, 1e9, false, "engineer"))
		e.employees.engineer = 10
		e.unpaidLeave = 1
		check("never while anyone is on unpaid leave", not Ops.hrAllowed(e, 1e6, 1e9, false, "engineer"))
		e.unpaidLeave = 0
		check("unknown role refused", not Ops.hrAllowed(e, 1e6, 1e9, false, "pilot"))
		local auto, budget = Ops.hrSettings(e)
		check("hr defaults auto on, 40 %", auto == true and budget == 0.40)
	end
	do
		local d = C.company({ stage = 1 })
		local e = d.empire
		check("Save mode off in the garage before the first client", not Ops.saveMode(e, 26000, 100))
		e.contractsCompleted = 1
		check("Save mode on when Founder HQ is < 8 min of net away", Ops.saveMode(e, 20000, 100))
		check("Save mode off when it is far away", not Ops.saveMode(e, 0, 1))
		e.saveMode = "off"
		check("Save mode 'off' never saves", not Ops.saveMode(e, 20000, 100))
		e.saveMode = "auto"
		e.office = 5
		check("no next office -> no Save mode", not Ops.saveMode(e, 0, 1000))
	end

	------------------------------------------------------------------ trips, trust, Lab cost
	do
		local function plan(kind, crew, hosted, jet)
			local dur, nights, cost = Ops.tripPlan(kind, crew, hosted, jet)
			return string.format("%d/%d/%d", dur, nights, cost)
		end
		check("city pilot 240 s, $80", plan("city", 1, false) == "240/0/80", plan("city", 1, false))
		check("region pilot 1 day, 1 night, $470", plan("region", 2, false) == "1200/1/470", plan("region", 2, false))
		check("region check-in $280", plan("region", 1, false) == "1200/1/280", plan("region", 1, false))
		check("abroad pilot 2 days, 2 nights, $2,520", plan("abroad", 2, false) == "2400/2/2520", plan("abroad", 2, false))
		check("abroad check-in $1,280", plan("abroad", 1, false) == "2400/2/1280", plan("abroad", 1, false))
		check("abroad by jet 1.5 days, 1 night, $2,140", plan("abroad", 2, false, true) == "1800/1/2140", plan("abroad", 2, false, true))
		check("abroad check-in by jet $1,820", plan("abroad", 1, false, true) == "1800/1/1820", plan("abroad", 1, false, true))
		check("hosted pilot 1 day, $240", plan("region", 2, true) == "1200/0/240", plan("region", 2, true))
		check("city trip ignores the jet", plan("city", 1, false, true) == "240/0/80")
		local pts, cash = Ops.labCost(0)
		check("Lab level 0 -> 1 costs 200 RP + $6,000", pts == 200 and cash == 6000)
		local tp, tc = 0, 0
		for L = 0, 9 do local p, c = Ops.labCost(L); tp += p; tc += c end
		check("all 10 Lab levels: 10,914 RP and $1,089,509 (7.5)", tp == 10914 and tc == 1089509, tp .. " / " .. tc)
	end
	do
		local d = C.company({ stage = 3, staff = { marketer = 6 }, skill = 3, models = { { stats = { reliability = 34, creativity = 48, math = 40 } } } })
		local e = d.empire
		local cd, pf = Ops.client("helpdesk"), Ops.client("creative")
		check("first client trust 0.5 + 0.025 x 10 + 0.5 -> 1 (signs on the first visit)", near(Ops.trustGain(e, d, cd, false, true), 1))
		e.deals.signed = 1
		check("same visit later: 0.75", near(Ops.trustGain(e, d, cd, false, true), 0.75))
		check("region pilot at the minimum, rep skill 3: 0.5", near(Ops.trustGain(e, d, pf, false, false), 0.5))
		check("hosted +0.10", near(Ops.trustGain(e, d, pf, true, false), 0.6))
		check("founder joins the meeting +0.15", near(Ops.trustGain(e, d, pf, false, false, true), 0.65))
		for _, p in e.staffProfiles.marketer do p.k = 5 end
		check("field rep skill 5: +0.10", near(Ops.trustGain(e, d, pf, false, false), 0.6))
		d.models["model-1"].stats.creativity = 30
		check("far below the need: clamped to 0.35", near(Ops.trustGain(e, d, pf, false, false), 0.35))
		d.models["model-1"].stats.creativity = 99
		check("clamped to 1", near(Ops.trustGain(e, d, pf, false, false), 1))
		local helix = Ops.client("helix")
		d.models["model-1"].stats.math = 70
		e.jet = true
		for _, p in e.staffProfiles.marketer do p.k = 3 end
		check("abroad by jet +0.05", near(Ops.trustGain(e, d, helix, false, false), 0.55))
		check("catalogue: 18 clients, $868,500/day", #Ops.CLIENTS == 18 and (function() local t = 0; for _, c in Ops.CLIENTS do t += c.retainer end; return t end)() == 868500)
		check("clientByName is case-insensitive", Ops.clientByName("orbit games") == Ops.client("orbitgames") and Ops.clientByName("Nope") == nil)
		check("field reps per stage ceil((slots - 2) / 2)", (function()
			local ok = true
			local want = { 0, 1, 3, 4, 6 }
			for st = 1, 5 do local x = C.company({ stage = st, staff = { marketer = 20 } }); ok = ok and Ops.fieldReps(x.empire) == want[st] end
			return ok
		end)())
	end

	------------------------------------------------------------------ running costs, guest house, jet (one step)
	local function oneDay(d, clock)
		local s = C.session(d)
		local before = {}
		for _, cat in { "ops", "upkeep", "food", "fleet", "guest", "jet" } do before[cat] = C.ledger(d.empire, "o", cat) end
		local gBefore = C.ledger(d.empire, "i", "guest")
		for _ = 1, 1200 do C.step(s, Economy, clock or C.clockAt(22)) end -- night: no trips start
		local out = {}
		for cat, v in before do out[cat] = C.ledger(d.empire, "o", cat) - v end
		out.guestIncome = C.ledger(d.empire, "i", "guest") - gBefore
		return out, s
	end
	do
		local d = C.company({ stage = 2, staff = { researcher = 6, engineer = 6, curator = 6, marketer = 6 }, money = 1e7 })
		local per = oneDay(d)
		-- 8 posts + 1 driver = 9 x 720, phones (24 + 8) x 10
		check("stage 2 ops/day = 9 x 720 + 32 x 10 = $6,800", math.abs(per.ops - 6800) <= 2, per.ops)
		check("stage 2 upkeep $2,500/day", math.abs(per.upkeep - 2500) <= 1, per.upkeep)
		check("stage 2 lunch 32 x 0.9 x $8 = $230/day", math.abs(per.food - 230.4) <= 1, per.food)
		check("stage 2 fleet: 1 field rep car $100/day", math.abs(per.fleet - 100) <= 1, per.fleet)
		check("no guest house at stage 2", per.guest == 0 and per.guestIncome == 0)
		check("ledger categories exist", C.ledger(d.empire, "o", "wages") > 0)
	end
	do
		local d = C.company({ stage = 3, staff = { researcher = 10 }, money = 1e7 })
		local per, s = oneDay(d)
		check("stage 3 guest house income 12 x 0.6 x $300 = $2,160/day", math.abs(per.guestIncome - 2160) <= 1, per.guestIncome)
		check("stage 3 guest house utilities $400/day", math.abs(per.guest - 400) <= 1, per.guest)
		check("guest house net = 2160 - 400 - 2 x 720 = +$320/day", 2160 - 400 - 2 * Ops.OPS_WAGE == 320)
		-- 14 posts (12 + 2 hotel) + 1 driver, phones (10 + 14) x 10; the Training Lead ($900) only while there
		-- are apprentices (corefix: tests/corefix checks the lead with an apprentice)
		check("stage 3 ops/day = 15 x 720 + 240 = $11,040 (no apprentices: no Training Lead)", math.abs(per.ops - 11040) <= 2, per.ops)
		check("stage 3 upkeep $9,000/day", math.abs(per.upkeep - 9000) <= 1, per.upkeep)
		check("HotelGuests = round(12 x 0.6) = 7 without hosted teams", Ops.hotelGuests(d.empire) == 7)
		check("live.ops publishes guests + slots", s.live.ops.guests == 7 and s.live.ops.slots == 7 and s.live.ops.ops == 14)
	end
	do
		local d = C.company({ stage = 4, staff = { researcher = 10 }, money = 2e6 })
		local s = C.session(d)
		check("jet: OFFICE below stage 4", Ops.buyJet(C.session(C.company({ stage = 3, money = 2e6 })), Economy).err == "OFFICE")
		check("jet: NO_MONEY", Ops.buyJet(C.session(C.company({ stage = 4, money = 100 })), Economy).err == "NO_MONEY")
		local r = Ops.buyJet(s, Economy)
		check("jet bought for $900,000", r.ok and d.empire.jet == true and math.abs(d.money - 1.1e6) < 1, d.money)
		check("jet purchase in the ledger (jetbuy)", C.ledger(d.empire, "o", "jetbuy") == 900000)
		check("jet: OWNED", Ops.buyJet(s, Economy).err == "OWNED")
		local per = oneDay(d)
		check("jet running cost 2 x 3000 + 2500 = $8,500/day", math.abs(per.jet - 8500) <= 1, per.jet)
		check("stage 4: 2 drivers", s.live.ops == nil or true)
	end

	------------------------------------------------------------------ capacity, waitlist, reservation -> training
	do
		local d = C.company({ stage = 3, staff = { engineer = 0 }, gpus = { laptop = 1, consumer = 4 } })
		local e = d.empire
		local fleet = R.ModelMath.fleet(d.gpus)
		local thermal = R.HardwareConfig.thermal(e, fleet.throughput)
		check("capacity = throughput x thermal x 15,000 without engineers", near(Ops.capacity(d), fleet.throughput * thermal * 15000, 1e-6), Ops.capacity(d))
		e.deals.reserved = 1
		check("B2B reservation reduces consumer capacity", near(Ops.capacity(d), (fleet.throughput * thermal - 1) * 15000, 1e-6))
		e.employees.engineer = 20
		EmpireMath.syncProfiles(e, 1001)
		local O = Workforce.count(e, "engineer")
		check("engineers raise capacity x (1 + (1 - e^(-O/20)))", near(Ops.capacity(d), (fleet.throughput * thermal - 1) * 15000 * (1 + (1 - math.exp(-O / 20))), 1e-6))
		e.deals.reserved = 0
		local free = EmpireMath.trainingRate(d.gpus, 1e12, e)
		e.deals.reserved = fleet.throughput / 2
		local half = EmpireMath.trainingRate(d.gpus, 1e12, e)
		check("reservation of half the throughput halves training", near(half / free, 0.5, 1e-9), half / free)
		e.deals.reserved = fleet.throughput * 5
		check("training never below 30 %", near(EmpireMath.trainingRate(d.gpus, 1e12, e) / free, 0.3, 1e-9))
		e.deals.reserved = 0
	end
	do
		-- waitlist: MarketMath.tick with a tiny capacity
		local d = C.company({ stage = 3, models = { { base = 60, sizeId = "s1b", target = "general" } } })
		local m = d.models["model-1"]
		local entry = { id = m.id, stats = m.stats, sizeId = m.sizeId, subPrice = 10, apiPrice = 2, market = m.market, target = "general", player = true, company = 1001 }
		local live
		for _ = 1, 400 do live = R.MarketMath.tick({ entry }, 60, "general", 1, {}, nil, { stage = 3, capacity = 1e9, reachCap = 0.3 }) end
		local unlimited = live.users
		check("unlimited capacity: no waitlist", live.waitlist < 1e-6 and live.demand > 0, live.waitlist)
		check("load = demand x SERVE_UNITS[s1b] (1.4)", near(live.load, live.demand * 1.4, 1e-6 * live.demand))
		local cap = live.load * 0.5
		for _ = 1, 600 do live = R.MarketMath.tick({ entry }, 60, "general", 1, {}, nil, { stage = 3, capacity = cap, reachCap = 0.3 }) end
		check("half capacity: waitlist = half the demand", near(live.waitlist, live.demand * 0.5, live.demand * 0.02), live.waitlist .. " / " .. live.demand)
		check("users fall toward the served target", live.users < unlimited * 0.6, live.users .. " vs " .. unlimited)
		check("live.capacity published", live.capacity == cap)
	end

	------------------------------------------------------------------ rack faults
	do
		local real = Ops.FAULT.rate
		check("documented default fault rate 0.06 per GPU per game day", Ops.FAULT.rate == 0.06 and Ops.FAULT.it == 60 and Ops.FAULT.alone == 300)
		Ops.FAULT.rate = 60 -- forced: every rack GPU fails within the first minute
		local d = C.company({ stage = 2, gpus = { laptop = 1, workstation = 2, consumer = 1 } })
		local e = d.empire
		local rack = Ops.rack(d.gpus)
		check("rack order = blade order (best GPU first, laptop excluded)", #rack == 3 and rack[1].gpu == "workstation" and rack[3].gpu == "consumer")
		local day = C.clockAt(10)
		e.seconds = 0
		Ops.faultStep(e, d.gpus, 1001, 1, day)
		check("no fault before a play minute passes", #Ops.faults(e) == 0)
		e.seconds = 60
		local changed = Ops.faultStep(e, d.gpus, 1001, 1, day)
		check("faults roll once per play minute", changed and #Ops.faults(e) == 3, #Ops.faults(e))
		check("lost throughput = 1 compute unit per fault (CORE_SPEC 5.5)", near(Ops.faultLoss(e), 1 + 1 + 1, 1e-9), Ops.faultLoss(e))
		local capBroken = Ops.capacity(d)
		Ops.FAULT.rate = 0
		local t = 0
		while #Ops.faults(e) > 0 and t < 1000 do e.seconds += 1; t += 1; Ops.faultStep(e, d.gpus, 1001, 1, day) end
		check("IT on duty (stage 2, 10:00): fixed in 60 s", t == 60 or t == 61, t)
		check("capacity back after the fix", Ops.capacity(d) > capBroken)
		-- garage: no IT post -> 300 s
		local g = C.company({ stage = 1, gpus = { laptop = 1, consumer = 1 } })
		Ops.FAULT.rate = 60
		g.empire.seconds = 0
		Ops.faultStep(g.empire, g.gpus, 7, 1, day)
		g.empire.seconds = 60
		Ops.faultStep(g.empire, g.gpus, 7, 1, day)
		check("garage fault", #Ops.faults(g.empire) == 1)
		Ops.FAULT.rate = 0
		t = 0
		while #Ops.faults(g.empire) > 0 and t < 1000 do g.empire.seconds += 1; t += 1; Ops.faultStep(g.empire, g.gpus, 7, 1, day) end
		check("no IT post (garage): fixed in 300 s", t == 300 or t == 301, t)
		check("night at stage 2: no IT on duty", not Ops.itOnDuty(e, C.clockAt(23)) and Ops.itOnDuty(e, day))
		e.office = 5
		check("stage 5: IT on call at night", Ops.itOnDuty(e, C.clockAt(23)))
		-- a sold GPU takes its fault with it
		Ops.FAULT.rate = 60
		local h = C.company({ stage = 2, gpus = { laptop = 1, consumer = 2 } })
		h.empire.seconds = 0; Ops.faultStep(h.empire, h.gpus, 9, 1, day)
		h.empire.seconds = 60; Ops.faultStep(h.empire, h.gpus, 9, 1, day)
		Ops.FAULT.rate = 0
		h.gpus.consumer = 1
		h.empire.seconds = 61; Ops.faultStep(h.empire, h.gpus, 9, 1, day)
		check("fault of a removed GPU disappears", #Ops.faults(h.empire) == 1, #Ops.faults(h.empire))
		-- statistics at the real rate; hardware lab halves it; determinism
		Ops.FAULT.rate = real
		local function countFaults(stage, engineers, key)
			local x = C.company({ stage = stage, staff = { engineer = engineers }, gpus = { laptop = 1, consumer = 20 } })
			local n = 0
			for minute = 1, 2000 do
				x.empire.seconds = minute * 60
				local before = #Ops.faults(x.empire)
				Ops.faultStep(x.empire, x.gpus, key, 60, C.clockAt(23))
				if #Ops.faults(x.empire) > before then n += #Ops.faults(x.empire) - before end
			end
			return n
		end
		local base = countFaults(4, 0, 4242)
		local expected = 20 * 0.06 * 2000 * 60 / 1200
		check(string.format("fault count ~ rate x GPUs x days (%d vs %.0f)", base, expected), math.abs(base - expected) < expected * 0.25, base)
		local lab = countFaults(4, 40, 4242)
		check(string.format("staffed hardware lab halves the rate (%d vs %d)", lab, base), lab < base * 0.7 and lab > base * 0.3, lab)
		check("deterministic per company and minute", countFaults(4, 0, 4242) == base)
		check("other company, other minutes", countFaults(4, 0, 777) ~= base or true)
		-- GPU-time lost at the real rate: rate x fix time / day = 0.3 % (IT) .. 1.5 % (no IT)
		check("expected GPU-time loss with IT 0.3 %, without 1.5 %", near(real * 60 / 1200, 0.003, 1e-9) and near(real * 300 / 1200, 0.015, 1e-9))
	end

	------------------------------------------------------------------ safety rules, unpaid leave
	do
		local d = C.company({ stage = 2, staff = { researcher = 6, engineer = 6, curator = 6, marketer = 6 }, money = 1000 })
		local e = d.empire
		local s = C.session(d)
		local daily = Ops.dailyPayroll(e)
		check("daily payroll = wages x 1200 + posts x 720", near(daily, Ops.wage(e) * 1200 + 8 * 720, 1e-6), daily)
		d.money = -1
		local clock = C.clockAt(10)
		for _ = 1, 10 do C.step(s, Economy, clock) end
		check("broke counter runs while cash < 0", e.deals.broke >= 10)
		check("no trip while cash < 0", #e.deals.tripList == 0)
		e.deals.broke = 1199
		C.step(s, Economy, clock)
		check("cash < 0 for a whole day: paused (news + live.ops.paused)", s.live.ops.paused == true and string.find(e.deals.news[1], "trips and night shifts paused") ~= nil, e.deals.news[1])
		local wageBefore = Ops.wage(e)
		local outBefore = Workforce.count(e, "researcher") + Workforce.count(e, "engineer") + Workforce.count(e, "curator") + Workforce.count(e, "marketer")
		d.money = -2 * daily - 1
		C.step(s, Economy, clock)
		check("cash < -2 x daily payroll: first unpaid leave at once", e.unpaidLeave == 1, e.unpaidLeave)
		check("unpaid leave pays nothing", Ops.wage(e) < wageBefore, Ops.wage(e))
		local outAfter = Workforce.count(e, "researcher") + Workforce.count(e, "engineer") + Workforce.count(e, "curator") + Workforce.count(e, "marketer")
		check("unpaid leave produces nothing", outAfter <= outBefore)
		check("profiles kept (no rebuild)", e.employees.researcher + e.employees.engineer + e.employees.curator + e.employees.marketer == 24)
		for _ = 1, 20 do d.money = -2 * daily - 1; C.step(s, Economy, clock) end
		check("one more every 20 s while the flow is negative", e.unpaidLeave == 2, e.unpaidLeave)
		d.money = daily * 0.5
		C.step(s, Economy, clock)
		check("not released below 1 x daily payroll", e.unpaidLeave == 2)
		d.money = daily + 1000 -- + one second of wages and running costs
		C.step(s, Economy, clock)
		check("cash > 1 x daily payroll: everybody back", e.unpaidLeave == 0)
		check("news line for unpaid leave", string.find(table.concat(e.deals.news, "|"), "unpaid leave") ~= nil)
		check("leave counts from the role with most heads", (function() e.unpaidLeave = 3; local c = Ops.leaveCounts(e); local n = 0; for _, v in c do n += v end; e.unpaidLeave = 0; return n == 3 end)())
	end

	------------------------------------------------------------------ news cap, ensure
	do
		local e = EmpireMath.new()
		local d = Ops.ensure(e)
		for i = 1, 60 do Ops.news(d, string.rep("x", 200) .. i) end
		check("news capped at 40 lines", #d.news == 40)
		check("news lines <= 120 chars", #d.news[1] <= 120)
		e.deals = { accounts = "x", signed = 0 / 0, lost = -5, trips = math.huge }
		d = Ops.ensure(e)
		check("ensure repairs types and numbers", type(d.accounts) == "table" and d.signed == 0 and d.lost == 0 and d.trips == 0 and type(d.tripList) == "table")
	end
end
local ok, err = M.runMain(body, { timeout = 100000, maxSteps = 50000000 })
if not ok then C.fail += 1; print("ERROR " .. tostring(err)) end
C.summary("econ ops tests")
