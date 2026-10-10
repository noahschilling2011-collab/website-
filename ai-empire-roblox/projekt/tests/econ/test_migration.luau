--!nocheck
-- econ package: save migration DATA_VERSION 5 -> 6 (CORE_SPEC 2.4) and the Appendix A cleaners on the real
-- Template: old tier k -> stage k + 1 (same building through Plan.OFFICE_TIER_OFFSET = 1), saves without a
-- company -> the garage, idempotent, newer saves refused, malformed new fields repaired, old fields
-- (contracts) kept, the lease-auction fields (customers, businessRevenue) emptied (corefix), one live model
-- per product line within the stage's slots (corefix), staff caps of the new stage table, profiles intact.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_econ && tools/luau tests/econ/test_migration.luau [-a .gen_dir]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_econ")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local C = require("./common")
local check = C.check

local function deepcopy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in v do out[k] = deepcopy(x) end
	return out
end

local function body()
	local R = C.load(M)
	local Template, EmpireMath, EmpireConfig, Plan, GameConfig, Ops = R.Template, R.EmpireMath, R.EmpireConfig, R.Plan, R.GameConfig, R.Ops
	check("DATA_VERSION 6", GameConfig.DATA_VERSION == 6)
	check("START_MONEY 10,000 (new saves)", GameConfig.START_MONEY == 10000 and Template.new().money == 10000)
	check("5 office stages", #EmpireConfig.OFFICES == 5 and EmpireConfig.OFFICES[1].name == "Garage Lab")
	check("stage prices 0 / 27k / 100k / 380k / 1.9M", EmpireConfig.OFFICES[2].price == 27000 and EmpireConfig.OFFICES[3].price == 100000 and EmpireConfig.OFFICES[4].price == 380000 and EmpireConfig.OFFICES[5].price == 1900000)
	check("staff caps 5 / 24 / 64 / 128 / 240", EmpireConfig.OFFICES[1].staff == 5 and EmpireConfig.OFFICES[2].staff == 24 and EmpireConfig.OFFICES[5].staff == 240)
	check("Plan.OFFICE_TIER_OFFSET = 1", Plan.OFFICE_TIER_OFFSET == 1)
	check("office 1 builds plan tier 0 (garage), office 5 plan tier 4", Plan.tierForOffice(1) == 0 and Plan.tierForOffice(5) == 4 and Plan.officeForTier(0) == 1 and Plan.officeForTier(4) == 5)
	check("garage stage: 5 staff, 3 lit blades", Plan.GARAGE_STAGE.staff == 5 and Plan.GARAGE_STAGE.blades == 3 and Plan.GARAGE_STAGE.staff == EmpireConfig.OFFICES[1].staff)
	check("new save starts in the garage", Template.new().empire.office == 1)

	-- a version-5 save as the old code wrote it (old tier index 1..4, old EmpireMath.new fields only)
	local OLD_STAFF = { 24, 64, 128, 240 }
	local function oldSave(tier, founded)
		local d = Template.new()
		d.version = 5
		local e = d.empire
		for _, k in { "calendar", "deals", "labLevel", "jet", "hr", "saveMode", "nightShift", "apprentices", "unpaidLeave", "ledger" } do e[k] = nil end
		d.trainings = nil
		e.office = tier
		if founded then
			d.company = { name = "Old Co " .. tier, logo = "O", color = "cyan", spec = "general", foundedAt = 1, reputation = 40 }
			local per = OLD_STAFF[tier] // 4
			for _, r in EmpireConfig.ROLES do e.employees[r.id] = per end
			EmpireMath.syncProfiles(e, 77)
		end
		e.contracts = { helpdesk = 19000, code = 19001 }
		e.customers = { { id = "pixel", name = "Pixel Games" } }
		e.businessRevenue = 12.5
		e.contractsCompleted = 9
		e.research.pipeline = true
		d.money = 123456
		return d
	end
	for tier = 1, 4 do
		local raw = oldSave(tier, true)
		local profiles = deepcopy(raw.empire.staffProfiles)
		local d, err = Template.migrate(raw)
		check("v5 tier " .. tier .. " migrates", d ~= nil and err == nil, err)
		local e = d.empire
		check("v5 tier " .. tier .. " -> stage " .. (tier + 1), e.office == tier + 1, e.office)
		check("v5 tier " .. tier .. ": same building (plan tier " .. tier .. ")", Plan.tierForOffice(e.office) == tier)
		check("v5 tier " .. tier .. ": version 6", d.version == 6)
		check("v5 tier " .. tier .. ": staff kept (" .. OLD_STAFF[tier] .. ")", EmpireMath.staff(e) == OLD_STAFF[tier], EmpireMath.staff(e))
		local same = true
		for role, list in profiles do
			for i, p in list do local q = e.staffProfiles[role][i]; same = same and q and q.n == p.n and q.s == p.s and q.k == p.k and q.w == p.w end
		end
		check("v5 tier " .. tier .. ": staff profiles unchanged (no new profile fields)", same)
		check("v5 tier " .. tier .. ": old contracts kept; lease customers/businessRevenue emptied (2.4)", e.contracts.helpdesk == 19000 and #e.customers == 0 and e.businessRevenue == 0, #e.customers)
		check("v5 tier " .. tier .. ": progress kept", d.money == 123456 and e.contractsCompleted == 9 and e.research.pipeline == true)
		check("v5 tier " .. tier .. ": new fields have defaults", typeof(e.calendar) == "table" and e.calendar.day == 1 and typeof(e.deals) == "table" and typeof(e.deals.accounts) == "table"
			and e.labLevel == 0 and e.jet == false and e.hr.auto == true and e.hr.budget == 0.40 and e.saveMode == "auto" and C.count(e.nightShift) == 0
			and C.count(e.apprentices) == 0 and e.unpaidLeave == 0 and C.count(e.ledger) == 0 and typeof(d.trainings) == "table")
		-- idempotent: migrating the result again changes nothing
		local again = Template.migrate(deepcopy(d))
		check("v5 tier " .. tier .. ": idempotent (stage stays " .. (tier + 1) .. ")", again.empire.office == tier + 1 and EmpireMath.staff(again.empire) == OLD_STAFF[tier])
	end
	do
		local d = Template.migrate(oldSave(1, false))
		check("v5 save without a company -> the garage (stage 1)", d.empire.office == 1)
		local d2 = Template.migrate(oldSave(3, false))
		check("never-founded save at any tier -> stage 1", d2.empire.office == 1)
	end
	do
		local raw = oldSave(4, true)
		raw.empire.office = "garbage"
		local d = Template.migrate(raw)
		check("malformed office in a v5 save -> stage 2 (old tier 1)", d.empire.office == 2)
		local raw2 = oldSave(4, true)
		raw2.empire.office = 99
		check("office 99 in a v5 save -> clamped to stage 5", Template.migrate(raw2).empire.office == 5)
		local raw3 = oldSave(2, true)
		raw3.empire = "broken"
		local d3, err3 = Template.migrate(raw3)
		check("MIGRATIONS[5] nil guard: broken empire -> fresh empire", d3 ~= nil and err3 == nil and d3.empire.office == 1, err3)
		local v6 = Template.new()
		v6.empire.office = 5
		check("v6 save: clamp 1..#OFFICES keeps stage 5 (was 1..4)", Template.migrate(v6).empire.office == 5)
		v6.empire.office = 0
		check("v6 office 0 -> 1", Template.migrate(v6).empire.office == 1)
		local newer = Template.new()
		newer.version = 7
		local nd, nerr = Template.migrate(newer)
		check("a newer save is refused (never overwritten)", nd == nil and type(nerr) == "string")
		local v0 = { money = 50 }
		local d0 = Template.migrate(v0)
		check("a version-0 fragment migrates to a v6 garage save", d0 ~= nil and d0.version == 6 and d0.empire.office == 1)
	end

	------------------------------------------------------------------ Appendix A cleaners (malformed v6 fields)
	do
		local raw = Template.new()
		raw.company = { name = "Bad Co", logo = "B", color = "cyan", spec = "general", foundedAt = 1, reputation = 1 }
		local e = raw.empire
		e.office = 3
		e.employees = { researcher = 3, engineer = 2 }
		EmpireMath.syncProfiles(e, 5)
		local seedA = e.staffProfiles.researcher[1].s
		e.calendar = { day = -4, index = 0 / 0 }
		e.deals = {
			accounts = { helpdesk = { expires = 5000, since = 10, founder = true }, bogus = { expires = 1 }, paper = "x", code = { expires = 0 / 0 } },
			trust = { helpdesk = 0.5, bogus = 0.3, paper = -1, code = math.huge, study = 7 },
			tripList = {},
			news = {},
			signed = -3, lost = 0 / 0, nights = math.huge, trips = "7", reserved = 2, pilots = 1, hosted = 0, flights = 0, jetFlights = 0,
			skip = { atlas = true, nope = true, ledger = "yes" },
			pinned = "unknown",
		}
		for i = 1, 30 do table.insert(e.deals.tripList, { client = if i % 3 == 0 then "nope" else "helpdesk", kind = if i % 5 == 0 then "fly" else "sign", back = i * 10, founder = true, crew = 9 }) end
		table.insert(e.deals.tripList, 1, "garbage")
		for i = 1, 70 do table.insert(e.deals.news, if i % 10 == 0 then 42 else string.rep("n", 300)) end
		e.labLevel = 77
		e.jet = "yes"
		e.hr = { auto = "maybe", budget = 0.3 }
		e.saveMode = "always"
		e.nightShift = { research = true, data = "true", nonsense = true, [5] = true }
		e.apprentices = { [tostring(seedA)] = { day = 3.7 }, ["123"] = { day = 1 }, [tostring(seedA + 1)] = "x" }
		e.unpaidLeave = 1e9
		e.ledger = {}
		for day = 1, 12 do
			local entry = { i = {}, o = {} }
			for k = 1, 30 do entry.i["cat" .. k] = k end
			entry.o.wages = 0 / 0
			entry.o.ok = 5
			entry.o[string.rep("x", 40)] = 1
			e.ledger[tostring(day)] = entry
		end
		e.ledger.abc = { i = {}, o = {} }
		raw.trainings = { ["2"] = { modelId = "m" }, ["1"] = { modelId = "x" }, ["9"] = {}, foo = 1, ["3"] = "bad" }
		raw.models = {
			a = { id = "a", status = "live", market = { age = 500, users = {}, organic = {}, hype = {} }, release = { target = "general" }, replacedBy = "zzz" },
			b = { id = "b", status = "retired", market = { age = 10, vage = -4, users = {}, organic = {}, hype = {} }, release = { auto = false }, replacedBy = "a" },
		}
		raw.modelOrder = { "a", "b" }
		local d, err = Template.migrate(raw)
		check("malformed v6 save migrates", d ~= nil, err)
		local de = d.empire
		check("calendar day >= 1, bad index dropped", de.calendar.day == 1 and de.calendar.index == nil)
		local dl = de.deals
		check("accounts: only catalogue ids with a finite term", dl.accounts.helpdesk ~= nil and dl.accounts.bogus == nil and dl.accounts.paper == nil and dl.accounts.code == nil)
		check("trust: catalogue ids, finite, > 0", dl.trust.helpdesk == 0.5 and dl.trust.bogus == nil and dl.trust.paper == nil and dl.trust.code == nil and dl.trust.study == 2)
		check("tripList <= 16 valid entries", #dl.tripList <= 16 and #dl.tripList > 0, #dl.tripList)
		local validTrips = true
		for _, t in dl.tripList do validTrips = validTrips and Ops.client(t.client) ~= nil and (t.kind == "sign" or t.kind == "renew") and t.crew <= 2 end
		check("trip entries well-formed (client, kind, crew clamped)", validTrips)
		check("news <= 40 strings <= NEWS_CHARS (80) bytes", #dl.news == 40 and #dl.news[1] <= Ops.NEWS_CHARS and type(dl.news[40]) == "string")
		check("deal counters finite >= 0", dl.signed == 0 and dl.lost == 0 and dl.nights == 0 and dl.trips == 7 and dl.reserved == 2)
		check("skip: catalogue ids with true only", dl.skip.atlas == true and dl.skip.nope == nil and dl.skip.ledger == nil)
		check("unknown pinned client dropped", dl.pinned == nil)
		check("labLevel clamped 0..10", de.labLevel == 10)
		check("jet boolean", de.jet == false)
		check("hr: budget in {0.25, 0.40, 0.55}, auto boolean", de.hr.budget == 0.40 and de.hr.auto == true)
		check("saveMode auto|off", de.saveMode == "auto")
		check("nightShift: department ids with true only", de.nightShift.research == true and de.nightShift.data == nil and de.nightShift.nonsense == nil and C.count(de.nightShift) == 1)
		check("apprentices: existing profile seeds only, integer day", de.apprentices[tostring(seedA)] and de.apprentices[tostring(seedA)].day == 3 and de.apprentices["123"] == nil and C.count(de.apprentices) == 1)
		check("unpaidLeave 0..staff", de.unpaidLeave == 5, de.unpaidLeave)
		local days = C.count(de.ledger)
		local okLedger = days == 7 and de.ledger["12"] ~= nil and de.ledger["5"] == nil and de.ledger.abc == nil
		for _, entry in de.ledger do
			-- 30 income lines 1..30: the 15 largest stay, the rest (1 + ... + 15 = 120) merge into "other"
			okLedger = okLedger and C.count(entry.i) == Ops.LEDGER_CATEGORIES and entry.i.cat30 == 30 and entry.i.cat16 == 16 and entry.i.cat15 == nil and entry.i.other == 120
				and entry.o.wages == nil and entry.o.ok == 5 and C.count(entry.o) == 1
		end
		check("ledger: newest 7 days, <= LEDGER_CATEGORIES finite categories (extras in 'other'), short names", okLedger, days)
		check("trainings: string keys '2'..'4' with tables only", d.trainings["2"] ~= nil and d.trainings["1"] == nil and d.trainings["9"] == nil and d.trainings.foo == nil and d.trainings["3"] == nil)
		check("model.market.vage: old live model = age", d.models.a.market.vage == 500)
		check("model.market.vage: negative -> age", d.models.b.market.vage == 10)
		check("model.replacedBy: unknown id dropped, valid kept", d.models.a.replacedBy == nil and d.models.b.replacedBy == "a")
		check("model.release.auto default true, false kept", d.models.a.release.auto == true and d.models.b.release.auto == false)
		-- a good save survives the cleaners unchanged
		local good = Template.new()
		good.company = { name = "Good", logo = "G", color = "cyan", spec = "general", foundedAt = 1, reputation = 1 }
		good.empire.office = 4
		good.empire.calendar = { day = 9, index = 1416666 }
		Ops.news(Ops.ensure(good.empire), "hello")
		good.empire.deals.accounts.helix = { expires = 99999, since = 50, founder = nil }
		good.empire.deals.trust.delta = 0.6
		good.empire.labLevel = 4
		good.empire.jet = true
		good.empire.hr = { auto = false, budget = 0.55 }
		good.empire.saveMode = "off"
		good.empire.ledger = { ["9"] = { i = { market = 100, b2b = 50 }, o = { wages = 70 } } }
		local g = Template.migrate(deepcopy(good))
		local ge = g.empire
		check("valid v6 fields survive unchanged", ge.calendar.day == 9 and ge.calendar.index == 1416666 and ge.deals.accounts.helix.expires == 99999 and ge.deals.trust.delta == 0.6
			and ge.labLevel == 4 and ge.jet == true and ge.hr.auto == false and ge.hr.budget == 0.55 and ge.saveMode == "off" and ge.ledger["9"].i.b2b == 50 and #ge.deals.news == 1)
	end
	-- corefix: v5 saves could run several live models in one line (clones) and more lines than the new stage
	-- allows: one live model per line (best overall; users x MIGRATE + organic move over, replacedBy), lines
	-- beyond PRODUCT_SLOTS go back to "trained" (fewest users first)
	do
		local raw = oldSave(1, true)
		local function mk(id, target, overall, users)
			return { id = id, name = "M" .. id, version = 1, status = "live", overall = overall, stats = {}, sizeId = "s500m",
				release = { target = target, subPrice = 5, apiPrice = 1 }, market = { age = 100, users = { consumers = users, developers = users / 10 }, organic = { consumers = 0.01 }, hype = {} } }
		end
		raw.models = { a = mk("a", "general", 50, 1000), b = mk("b", "general", 60, 400), c = mk("c", "developers", 40, 300), d = mk("d", "students", 45, 200) }
		raw.modelOrder = { "a", "b", "c", "d" }
		local d = Template.migrate(raw)
		local live, lines = 0, {}
		for _, m in d.models do if m.status == "live" then live += 1; lines[R.ModelMath.lineOf(m.release.target)] = (lines[R.ModelMath.lineOf(m.release.target)] or 0) + 1 end end
		check("lines: stage 2 keeps PRODUCT_SLOTS[2] = 2 live lines, one model each", live == 2 and lines.consumers == 1 and C.count(lines) == 2, live)
		check("lines: the better clone stays, the other retires into it", d.models.b.status == "live" and d.models.a.status == "retired" and d.models.a.replacedBy == "b")
		check("lines: users x 0.9 and word of mouth move to the kept model", math.abs(d.models.b.market.users.consumers - (400 + 1000 * 0.9)) < 1e-6 and math.abs(d.models.b.market.organic.consumers - 0.02) < 1e-9 and C.count(d.models.a.market.users) == 0)
		check("lines: the line with the fewest users goes back to 'trained' (release kept)", d.models.d.status == "trained" and d.models.d.release ~= nil and d.models.c.status == "live")
		check("lines: a new line is refused afterwards (LINE_LIMIT), the migrated save is consistent", R.ModelMath.releaseCheck(d, "d", "students").err == "LINE_LIMIT")
		-- NEGATIVE: the unmigrated save had 4 live models and 3 lines on a 2-slot stage
		local n0 = 0
		for _, m in raw.models do if m.status == "live" then n0 += 1 end end
		check("negative: the same models without the migration break the rule (3 lines > 2 slots)", (function() local x = oldSave(1, true); x.version = 6; x.empire.office = 2; x.models = { a = mk("a", "general", 50, 1), b = mk("b", "general", 60, 1), c = mk("c", "developers", 40, 1), d = mk("d", "students", 45, 1) }; x.modelOrder = { "a", "b", "c", "d" }; local y = Template.migrate(x); local _, n = R.ModelMath.liveLines(y); return n == 3 end)())
	end
	-- NEGATIVE: the old clamp (1..4) would have broken migrated stage-5 saves; prove the check detects it
	do
		local v6 = Template.new()
		v6.empire.office = 5
		local oldClamp = math.clamp(math.floor(v6.empire.office), 1, 4)
		check("negative: the old 1..4 clamp would demote stage 5", oldClamp == 4 and Template.migrate(v6).empire.office == 5)
	end
end
local ok, err = M.runMain(body, { timeout = 100000, maxSteps = 50000000 })
if not ok then C.fail += 1; print("ERROR " .. tostring(err)) end
C.summary("econ migration tests")
