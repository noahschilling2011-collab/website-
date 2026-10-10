--!nocheck
-- corefix package: one regression check (plus a negative proof where it makes sense) per verified finding of
-- the three verifiers (sim / save_net / conformance) on the REAL modules in the mock:
--   1  auto-price phase: first cycle 150 s after the company starts ticking (CORE_SPEC 9 design bot)
--   2  trip cash rule: several reps leaving in one step never take cash below CASH_MARGIN (8.3)
--   3  rack faults take 1 compute unit per fault (5.5 / 10), not a whole Eight-GPU pod
--   4  news stamps are per company (own calendar day), also outside Ops.step (EmpireService, AIModelService)
--   5  Save mode switches write one news line, debounced (8.2)
--   6  EmpireAction autoPrice refuses a non-boolean `on` (BAD_INPUT)
--   7  ledger: uncategorised spend/grant land in "other" (P&L adds up to the change in cash); every money call
--      in the corefix-owned server files names a category
--   8  apprentices: hire path (50 % fee, skill 1, entry), Training Lead only with apprentices, graduation
--   9  garage site board: SiteGoal text on the office and the board's Body label, rewritten only on change
--  10  replication: compact deals keep what the client's CompanyOps needs (identical outputs), trust shown to 0.001,
--      marketplace vage in 30 s steps, news clipped on a UTF-8 boundary
--  11  migration: v5 lease customers / businessRevenue emptied (+ MarketService never refills them)
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_corefix && cd tests/corefix && ../../tools/luau test_corefix.luau -a .gen_corefix
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_corefix")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
local SOURCES = require(GEN .. "/sources")
M.quiet = true
local C = require("../econ/common")
local check, near = C.check, C.near

local function body()
	local R = C.load(M)
	local game = M.game
	local S = R.Server.Services
	local Ops, EmpireConfig, ModelConfig = R.Ops, R.EmpireConfig, R.ModelConfig
	local Remote = M.require(R.Server.Lib.Remote)
	local binds = {}
	local origBind = Remote.bind
	Remote.bind = function(name, limits, handler) binds[name] = { handler = handler, limits = limits }; origBind(name, limits, handler) end
	Remote.setup()
	local SessionService = M.require(S.SessionService)
	local Economy = M.require(S.EconomyService)
	local PlotService = M.require(S.PlotService)
	local EmpireService = M.require(S.EmpireService)
	local MarketService = M.require(S.MarketService)
	local AIModelService = M.require(S.AIModelService)
	local Pricing = M.require(S.PricingService)
	local Workforce = R.Workforce
	SessionService.init()
	EmpireService.init()
	AIModelService.init()
	local sessions = SessionService.all()
	local function add(data, uid)
		local player = { UserId = uid, Name = "P" .. uid, DisplayName = "Player " .. uid, Parent = game.Players }
		local s = C.session(data, uid)
		s.player = player
		s.lastSent, s.nextSaveAt, s.saving, s.released = 0, math.huge, false, false
		sessions[player] = s
		return s
	end
	local function call(name, s, payload) return binds[name].handler(s, payload or {}) end
	local function newsWith(e, needle)
		local n = 0
		for _, line in e.deals.news do if string.find(line, needle, 1, true) then n += 1 end end
		return n
	end

	------------------------------------------------------------------ 1. auto-price phase
	do
		local p = add(C.company({ stage = 1, money = 20000, models = { { base = 40 } } }), 2101)
		local m = p.data.models["model-1"]
		m.release.auto = true
		local first = nil
		for t = 1, 400 do
			M.Sched.now += 1
			Pricing.tick(p, 1)
			if Pricing.job(p) and not first then first = t end
			Pricing.flush(p)
		end
		check("1 auto-price: PRICING.autoFirst = 150, period 300", ModelConfig.PRICING.autoFirst == 150 and ModelConfig.PRICING.autoPeriod == 300)
		check("1 auto-price: first cycle 150 s after the company's first tick (design bot phase)", first == 150, first)
		local old = 15 + 2101 % 30
		check("1 negative: the econ build started it at " .. old .. " s (before a new company's first release at ~80 s)", old < 80 and first ~= old)
		-- second cycle 300 s later
		local q = add(C.company({ stage = 1, money = 20000, models = { { base = 40 } } }), 2102)
		q.data.models["model-1"].release.auto = true
		local starts = {}
		for t = 1, 760 do
			M.Sched.now += 1
			Pricing.tick(q, 1)
			if Pricing.job(q) then table.insert(starts, t) end
			Pricing.flush(q)
		end
		check("1 auto-price: cycles at 150, 450, 750 s", #starts == 3 and starts[1] == 150 and starts[2] == 450 and starts[3] == 750, table.concat(starts, ","))
	end

	------------------------------------------------------------------ 2. trip cash rule with several free reps
	do
		local function stage4(cash)
			local d = C.company({ stage = 4, money = cash, staff = { marketer = 8 }, skill = 3, gpus = { laptop = 1, accelerator = 10 },
				models = { { stats = { math = 72, reliability = 70, creativity = 70, coding = 70, reasoning = 70, knowledge = 70 } } } })
			d.empire.deals.signed = 5 -- not the scripted first pilot
			d.empire.contractsCompleted = 5
			return d
		end
		for _, cash in { 3100, 4000, 6000 } do
			local d = stage4(cash)
			local s = C.session(d, 2110)
			check("2 setup: 4 field reps at stage 4", Ops.fieldReps(d.empire) == 4)
			C.step(s, Economy, C.clockAt(10), 1)
			local spent, trips = 0, #d.empire.deals.tripList
			for _, t in d.empire.deals.tripList do
				local c = Ops.client(t.client)
				local _, _, cost = Ops.tripPlan(c.trip, t.crew, t.hosted, false)
				spent += cost
			end
			check(string.format("2 cash $%d: %d trips ($%d) never take cash below CASH_MARGIN (cash after %.0f)", cash, trips, spent, d.money), trips >= 1 and d.money >= Ops.CASH_MARGIN - 50 and spent <= cash - Ops.CASH_MARGIN, d.money)
		end
		-- NEGATIVE: every candidate trip alone passes the old stale check, together they overdraw
		local d = stage4(3100)
		local s = C.session(d, 2111)
		C.step(s, Economy, C.clockAt(10), 1)
		local _, _, abroad = Ops.tripPlan("abroad", 2, false, false)
		local _, _, region = Ops.tripPlan("region", 2, false, false)
		check("2 negative: the stale check let helix + 3 region pilots go ($" .. (abroad + 3 * region) .. " > $3,100 - margin)", abroad + 3 * region > 3100 - Ops.CASH_MARGIN and abroad <= 3100 - Ops.CASH_MARGIN and #d.empire.deals.tripList == 1)
	end

	------------------------------------------------------------------ 3. rack fault = 1 compute unit
	do
		local d = C.company({ stage = 5, gpus = { laptop = 1, superpod = 2 } })
		local e = d.empire
		local cap0 = Ops.capacity(d)
		local rate = Ops.FAULT.rate
		Ops.FAULT.rate = 60 -- every rack GPU fails at the next play minute
		e.seconds = 0
		Ops.faultStep(e, d.gpus, 1001, 1, C.clockAt(10))
		e.seconds = 60
		Ops.faultStep(e, d.gpus, 1001, 1, C.clockAt(10))
		Ops.FAULT.rate = rate
		local nf = #Ops.faults(e)
		local loss = Ops.faultLoss(e)
		check("3 rack fault: 1 compute unit off line per fault (2 pods, " .. nf .. " faults)", nf == 2 and near(loss, 2 * Ops.FAULT.units, 1e-9) and Ops.FAULT.units == 1, loss)
		local cap1 = Ops.capacity(d)
		check(string.format("3 capacity drop per fault is small (%.2f %% for 2 faults on 400 units)", (1 - cap1 / cap0) * 100), cap1 < cap0 and cap1 / cap0 > 0.99)
		local rack, whole = Ops.rack(d.gpus), 0
		for _, f in Ops.faults(e) do whole += rack[f.slot].throughput end
		check(string.format("3 negative: the econ build took the whole pods off line (%d of 400 units)", whole), whole == 400 and loss < whole / 100)
	end

	------------------------------------------------------------------ 4. news stamps per company
	do
		local a = add(C.company({ stage = 1, money = 40000, models = { { base = 40 } } }), 2120)
		local b = add(C.company({ stage = 2, money = 40000, models = { { base = 40 } } }), 2121)
		a.data.empire.calendar = { day = 3, index = math.floor(C.clockAt(10) / 1200) }
		b.data.empire.calendar = { day = 40, index = math.floor(C.clockAt(10) / 1200) }
		C.step(a, Economy, C.clockAt(10), 1)
		C.step(b, Economy, C.clockAt(10), 1) -- B ticks last
		a.data.empire.contractsCompleted = 1
		local r = call("UpgradeOffice", a)
		local line = a.data.empire.deals.news[1]
		check("4 UpgradeOffice news carries company A's own day (day 3), not B's (day 40)", r.ok and string.find(line, "^day 3 ") ~= nil and string.find(line, "moved into the Founder Headquarters", 1, true) ~= nil, line)
		Ops.post(b.data.empire, "hello from B")
		check("4 Ops.post stamps company B with day 40", string.find(b.data.empire.deals.news[1], "^day 40 %d%d:%d%d: hello from B") ~= nil, b.data.empire.deals.news[1])
		-- a fresh company before any Ops.step: never a line starting with ": "
		local f = add(C.company({ stage = 1 }), 2122)
		Ops.post(f.data.empire, "first line")
		check("4 fresh company: stamped 'day 1 hh:mm: ...' (no bare ': ')", string.find(f.data.empire.deals.news[1], "^day 1 %d%d:%d%d: first line") ~= nil, f.data.empire.deals.news[1])
		-- model release news (AIModelService) is stamped too
		local g = add(C.company({ stage = 2, money = 50000 }), 2123)
		g.data.empire.calendar = { day = 7, index = 0 }
		local m = { id = "rel1", name = "Nova", version = 1, sizeId = "s500m", focusId = "balanced", status = "trained", stats = {}, overall = 40, iterations = 0,
			createdAt = 0, trainedAt = 0, trainCost = 0, dataUsed = { total = 0, quality = 0.5 } }
		for _, st in ModelConfig.STATS do m.stats[st.id] = 40 end
		g.data.models.rel1 = m
		table.insert(g.data.modelOrder, "rel1")
		local rr = call("ReleaseModel", g, { modelId = "rel1", target = "general", marketing = 0, auto = false, subPrice = 10, apiPrice = 2 })
		check("4 release news stamped with the company's day (AIModelService)", rr.ok and string.find(g.data.empire.deals.news[1], "^day 7 %d%d:%d%d: Nova v1 launched") ~= nil, g.data.empire.deals.news[1] .. " " .. tostring(rr.err))
	end

	------------------------------------------------------------------ 5. Save mode news, debounced
	do
		local sv = add(C.company({ stage = 2, money = 0, models = { { base = 50 } } }), 2130)
		sv.data.empire.hr.auto = false
		local function tickAt(money, revenue)
			sv.data.money = money
			sv.live.revenue = revenue
			sv.live.cost = 0
			M.Sched.now += 1
			EmpireService.tick(sv, 1)
		end
		for _ = 1, 5 do tickAt(0, 100) end
		local e = sv.data.empire
		check("5 setup: not saving with no cash", sv.live.ops.saveMode == false)
		for _ = 1, 19 do tickAt(95000, 100) end
		check("5 Save mode on, no news before it held 20 s", sv.live.ops.saveMode == true and newsWith(e, "Save mode") == 0)
		tickAt(95000, 100)
		check("5 one news line once it held 20 s: 'Save mode on: saving for the Startup Campus'", newsWith(e, "Save mode on: saving for the Startup Campus") == 1, e.deals.news[1])
		for _ = 1, 10 do tickAt(0, 100) end
		for _ = 1, 30 do tickAt(95000, 100) end
		check("5 debounce: a 10 s dip writes nothing", newsWith(e, "Save mode") == 1)
		for _ = 1, 25 do tickAt(0, 100) end
		check("5 'Save mode off' after it held 20 s", newsWith(e, "Save mode off") == 1 and newsWith(e, "Save mode") == 2)
	end

	------------------------------------------------------------------ 6. autoPrice refuses non-boolean on
	do
		local s = add(C.company({ stage = 2, models = { { base = 50 } } }), 2140)
		local m = s.data.models["model-1"]
		m.release.auto = true
		local r = call("EmpireAction", s, { action = "autoPrice", model = m.id, on = "yes" })
		check("6 autoPrice on='yes' -> BAD_INPUT, auto stays on", r.ok == false and r.err == "BAD_INPUT" and m.release.auto == true, r.err)
		local r2 = call("EmpireAction", s, { action = "autoPrice", model = m.id, on = false })
		check("6 autoPrice on=false still works", r2.ok and m.release.auto == false)
	end

	------------------------------------------------------------------ 7. ledger adds up; categories in owned files
	do
		local s = add(C.company({ stage = 2, money = 100000 }), 2150)
		local e = s.data.empire
		local m0 = s.data.money
		Economy.spend(s, 1234)            -- uncategorised (other packages' call sites)
		Economy.grant(s, 999)
		Economy.spend(s, 500, "studio")
		Economy.applyFlow(s, 70.5, 20.25, "market")
		Economy.applyFlow(s, 0.5, 0, "b2b")
		local inc, out = 0, 0
		for _, entry in e.ledger do
			for _, v in entry.i do inc += v end
			for _, v in entry.o do out += v end
		end
		check("7 ledger income - costs = change in cash (within $1 of carried cents)", math.abs((inc - out) - (s.data.money - m0)) <= 1.01, string.format("%.2f vs %.2f", inc - out, s.data.money - m0))
		check("7 uncategorised spend/grant -> 'other'", e.ledger["1"].o.other == 1234 and e.ledger["1"].i.other == 999)
		-- every EconomyService money call in the corefix-owned server files names a category
		local OWNED = { "AIModelService", "EmpireService", "StudioService", "ComputeService", "DatasetService", "MarketService", "AdminService", "DebugService", "CompanyService", "PricingService" }
		local missing = {}
		for _, name in OWNED do
			local src = string.gsub(SOURCES["ServerScriptService/Server/Services/" .. name .. ".module.luau"] or "", "%-%-[^\n]*", "") -- code only
			for call in string.gmatch(src, "Economy%a*%.spend%b()") do
				local inner = string.sub(call, string.find(call, "(", 1, true) + 1, -2)
				local _, commas = string.gsub(inner, ",", ",")
				if commas < 2 and not string.find(inner, "^%s*[%w_]+%s*,%s*0%s*$") then table.insert(missing, name .. ": " .. call) end
			end
			for call in string.gmatch(src, "Economy%a*%.grant%b()") do
				local inner = string.sub(call, string.find(call, "(", 1, true) + 1, -2)
				local _, commas = string.gsub(inner, ",", ",")
				if commas < 2 then table.insert(missing, name .. ": " .. call) end
			end
		end
		check("7 every spend/grant in the owned server files names a ledger category", #missing == 0, table.concat(missing, " | "))
		-- information only: call sites in files of other packages (filed in design/requests/corefix.md)
		local foreign = {}
		for _, name in { "FacilityService", "RecruitingService", "VehicleService", "AssistantService", "ShopService" } do
			local src = string.gsub(SOURCES["ServerScriptService/Server/Services/" .. name .. ".module.luau"] or "", "%-%-[^\n]*", "")
			for call in string.gmatch(src, "Economy%a*%.spend%b()") do local _, n = string.gsub(call, ",", ","); if n < 2 then table.insert(foreign, name) end end
			for call in string.gmatch(src, "Economy%a*%.grant%b()") do local _, n = string.gsub(call, ",", ","); if n < 2 then table.insert(foreign, name) end end
		end
		print("  info: uncategorised money calls in other packages' files (booked as 'other'): " .. #foreign)
	end

	------------------------------------------------------------------ 8. apprentices + Training Lead
	do
		local s = add(C.company({ stage = 3, money = 100000, staff = { engineer = 4 } }), 2160)
		local e = s.data.empire
		local role = EmpireConfig.find(EmpireConfig.ROLES, "engineer")
		local m0 = s.data.money
		local r = call("HireEmployee", s, { roleId = "engineer", apprentice = true })
		local list = e.staffProfiles.engineer
		local p = list[#list]
		check("8 apprentice hire: half the agency fee", r.ok and near(m0 - s.data.money, math.floor(role.price * Ops.APPRENTICE.fee), 1e-6), m0 - s.data.money)
		check("8 apprentice: profile skill 1, wage factor 1, entry in empire.apprentices (no new profile field)", p.k == 1 and p.w == 1 and e.apprentices[tostring(p.s)] ~= nil and e.apprentices[tostring(p.s)].day == Ops.day(e))
		local k0 = Ops.apprentice(e, p.s, Ops.day(e))
		local k3 = Ops.apprentice(e, p.s, Ops.day(e) + 3)
		local k9 = Ops.apprentice(e, p.s, Ops.day(e) + 9)
		check("8 apprentice skill 1 -> 2 after 3 days, regular after 9", k0 == 1 and k3 == 2 and k9 == nil)
		-- Training Lead $900/day only while apprentices exist
		local function opsPerMinute(d)
			local x = C.session(d, 2161)
			C.step(x, Economy, C.clockAt(10), 1)
			return x.live.ops.opsCost
		end
		local withA = opsPerMinute(s.data)
		local saved = e.apprentices
		e.apprentices = {}
		local without = opsPerMinute(s.data)
		e.apprentices = saved
		check(string.format("8 Training Lead charged only with apprentices: +$%d/min (900/day = 45/min)", withA - without), math.abs((withA - without) - 45) <= 1)
		check("8 negative: apprentice at stage 2 -> OFFICE", call("HireEmployee", add(C.company({ stage = 2, money = 1e5 }), 2162), { roleId = "engineer", apprentice = true }).err == "OFFICE")
		check("8 negative: apprentice = 'yes' -> BAD_INPUT", call("HireEmployee", s, { roleId = "engineer", apprentice = "yes" }).err == "BAD_INPUT")
		-- graduation after 9 company days
		e.calendar.day = Ops.day(e) + 9
		s.live.revenue, s.live.cost = 0, 0
		EmpireService.tick(s, 1)
		check("8 graduation: skill 3, entry removed, news line", p.k == Ops.APPRENTICE.endSkill and e.apprentices[tostring(p.s)] == nil and newsWith(e, "graduated") == 1)
	end

	------------------------------------------------------------------ 9. garage site board
	do
		local s = add(C.company({ stage = 1, money = 12345, models = { { base = 40 } } }), 2170)
		s.data.empire.hr.auto = false
		local office = M.G.Instance.new("Model")
		office.Name = "Office"
		local board = M.G.Instance.new("Part"); board.Name = "SiteBoard"; board.Parent = office
		local gui = M.G.Instance.new("SurfaceGui"); gui.Parent = board
		local title = M.G.Instance.new("TextLabel"); title.Name = "Title"; title.Text = "FUTURE HEADQUARTERS"; title.Parent = gui
		local bodyLabel = M.G.Instance.new("TextLabel"); bodyLabel.Name = "Body"; bodyLabel.Text = "static"; bodyLabel.Parent = gui
		local writes = 0
		bodyLabel:GetPropertyChangedSignal("Text"):Connect(function() writes += 1 end)
		local realGet = PlotService.get
		PlotService.get = function(player) if player == s.player then return { office = office } end return realGet(player) end
		local function tick(money)
			s.data.money = money
			s.live.revenue, s.live.cost = 0, 0
			EmpireService.tick(s, 1)
			M.settle(0.05)
		end
		tick(12345)
		local goal = EmpireService.siteGoal(s.data)
		check("9 site board text: company, first client, money / $27,000", goal ~= nil and string.find(goal, "Future HQ of Nimbus Labs", 1, true) and string.find(goal, "First client: not yet", 1, true) and string.find(goal, "$12,000 / $27,000", 1, true), goal)
		check("9 SiteGoal attribute and the board's Body label carry it", office:GetAttribute("SiteGoal") == goal and bodyLabel.Text == goal and title.Text == "FUTURE HEADQUARTERS")
		local w0 = writes
		tick(12800)
		check("9 rewritten only when the shown text changes (same $1,000 step)", writes == w0)
		s.data.empire.contractsCompleted = 1
		tick(13100)
		check("9 first client signed + next $1,000 -> one rewrite", writes == w0 + 1 and string.find(bodyLabel.Text, "First client: signed", 1, true) and string.find(bodyLabel.Text, "$13,000", 1, true))
		s.data.empire.office = 2
		tick(13100)
		check("9 no site goal after leaving the garage (attribute cleared)", EmpireService.siteGoal(s.data) == nil and office:GetAttribute("SiteGoal") == nil)
		PlotService.get = realGet
	end

	------------------------------------------------------------------ 10. replication: compact deals, trust, vage, UTF-8
	do
		local d = C.company({ stage = 4, money = 1e6, staff = { researcher = 20, engineer = 30, curator = 10, marketer = 20 }, skill = 3, gpus = { laptop = 1, accelerator = 10 },
			models = { { stats = { math = 72, reliability = 70, creativity = 70, coding = 70, reasoning = 70, knowledge = 70 } } } })
		d.empire.deals.signed = 3
		local s = C.session(d, 2180)
		for k = 1, 1200 do C.step(s, Economy, C.clockAt(8 + (k % 900) / 90), 1) end
		local e = d.empire
		check("10 setup: trips with travelling engineers and accounts", #e.deals.tripList > 0 and C.count(e.deals.accounts) > 0, #e.deals.tripList)
		local sent = SessionService.replicatedData(d).empire
		local okCompact = true
		for _, acc in sent.deals.accounts do okCompact = okCompact and acc.since == nil and acc.founder == nil and acc.expires ~= nil end
		for _, t in sent.deals.tripList do okCompact = okCompact and t.left == nil and t.crew == nil and t.client ~= nil and t.kind ~= nil and t.back ~= nil end
		check("10 replicated accounts {expires, renewing?}, trips {client, kind, back, founder?, hosted?}", okCompact)
		check("10 the save keeps the full entries", (function() for _, acc in e.deals.accounts do if acc.since == nil then return false end end return true end)())
		local same = true
		for _, r in EmpireConfig.ROLES do
			local a, b = Workforce.count(e, r.id), Workforce.count(sent, r.id)
			same = same and near(a, b, 1e-9)
		end
		check("10 client CompanyOps on the replicated view = server outputs (presence, travellers)", same and Ops.travellers(e).engineer == Ops.travellers(sent).engineer and Ops.hotelGuests(e) == Ops.hotelGuests(sent))
		local trustOk, nTrust = true, 0
		e.deals.trust.helpdesk = 0.61234567
		for id, t in sent.deals.trust do nTrust += 1; trustOk = trustOk and math.abs(t * 1000 - math.floor(t * 1000 + 0.5)) < 1e-6 and math.abs(t - e.deals.trust[id]) <= 0.0005 + 1e-9 end
		local sent2 = SessionService.replicatedData(d).empire
		check("10 trust replicated to 0.001, exact in the save", trustOk and sent2.deals.trust.helpdesk == 0.612 and e.deals.trust.helpdesk == 0.61234567, nTrust)
		-- marketplace offers: vage in whole 30 s steps
		local o = add(C.company({ stage = 2, models = { { base = 50 } } }), 2181)
		o.data.models["model-1"].market.vage = 89.7
		MarketService.tickGlobal(1)
		local offer
		for _, x in MarketService.offers do if x.providerId == 2181 then offer = x end end
		check("10 offers: vage in 30 s steps (89.7 -> 60)", offer and offer.vage == 60 and MarketService.OFFER_AGE_STEP == 30, offer and offer.vage)
		-- UTF-8 safe news clipping
		local line = string.rep("a", Ops.NEWS_CHARS - 1) .. "→ tail"
		local clipped = Ops.clip(line, Ops.NEWS_CHARS)
		check("10 Ops.clip never splits a multi-byte character", #clipped == Ops.NEWS_CHARS - 1 and utf8.len(clipped) ~= nil)
		check("10 negative: a byte cut (string.sub) would leave invalid UTF-8", utf8.len(string.sub(line, 1, Ops.NEWS_CHARS)) == nil)
		local dd = Ops.newDeals()
		Ops.news(dd, string.rep("é", 60), "day 2 10:00")
		check("10 news lines <= NEWS_CHARS bytes and valid UTF-8", #dd.news[1] <= Ops.NEWS_CHARS and utf8.len(dd.news[1]) ~= nil)
	end

	------------------------------------------------------------------ 11. migration: lease customers emptied for good
	do
		local raw = R.Template.new()
		raw.version = 5
		raw.company = { name = "Old", logo = "O", color = "cyan", spec = "general", foundedAt = 1, reputation = 30 }
		raw.empire.office = 2
		raw.empire.customers = { { id = "pixel", name = "Pixel Games", price = 900, remaining = 3000 }, { id = "civic", name = "Civic", price = 900, remaining = 100 } }
		raw.empire.businessRevenue = 0.75
		for _, k in { "calendar", "deals", "labLevel", "jet", "hr", "saveMode", "nightShift", "apprentices", "unpaidLeave", "ledger" } do raw.empire[k] = nil end
		local d = R.Template.migrate(raw)
		check("11 v5 -> v6: lease customers and businessRevenue emptied (CORE_SPEC 2.4)", #d.empire.customers == 0 and d.empire.businessRevenue == 0)
		local s = add(d, 2190)
		for _ = 1, 30 do MarketService.tickGlobal(1); MarketService.tick(s, 1) end
		check("11 30 s of MarketService ticks never refill them", #d.empire.customers == 0 and d.empire.businessRevenue == 0)
		-- a v6 save written by the econ build (stale fields) is cleaned on load too
		local v6 = R.Template.new()
		v6.empire.customers = { { id = "x" } }
		v6.empire.businessRevenue = 3
		local c6 = R.Template.migrate(v6)
		check("11 v6 cleaner empties stale lease fields", #c6.empire.customers == 0 and c6.empire.businessRevenue == 0)
	end
end
local ok, err = M.runMain(body, { timeout = 100000, maxSteps = 500000000 })
if not ok then C.fail += 1; print("ERROR " .. tostring(err)) end
if M.stats and M.stats.errors and M.stats.errors > 0 then C.fail += 1; print("FAIL  background errors: " .. M.stats.errors) end
C.summary("corefix server tests")
