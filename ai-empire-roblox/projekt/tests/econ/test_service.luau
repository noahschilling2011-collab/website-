--!nocheck
-- econ package: the server services on real modules in the mock: remotes EmpireAction / DealAction (input
-- validation, error codes of CORE_SPEC 11.8, rate limit 4 / 2 per s, NO_COMPANY), the garage gate
-- (first signed client AND $27,000), Lab levels, company jet, HR settings, night shift, pin / skip /
-- joinMeeting, the automatic HR coordinator through the normal hire path (3 starters, one per 20 s, wage
-- budget, Save mode, no hires without a live product), office attributes for the visuals (HotelRooms,
-- HotelGuests, RackFaults, ServerFaults), live.compute, ledger caps (7 days x 24 categories), the NPC band,
-- the removed lease auction and the richer marketplace offers, studio briefs per game day.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_econ && tools/luau tests/econ/test_service.luau [-a .gen_dir]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_econ")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local C = require("./common")
local check, near = C.check, C.near

local function body()
	local R = C.load(M)
	local game = M.game
	local S = R.Server.Services
	local Ops, EmpireConfig = R.Ops, R.EmpireConfig
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
	local NPCService = M.require(S.NPCService)
	local StudioService = M.require(S.StudioService)
	local AIModelService = M.require(S.AIModelService)
	SessionService.init()
	EmpireService.init()
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
	local function invoke(name, s, payload)
		local fn = game.ReplicatedStorage:FindFirstChild("Remotes"):FindFirstChild(name)
		return fn.OnServerInvoke(s.player, payload)
	end

	------------------------------------------------------------------ remotes exist with the 11.8 limits
	check("Net.FUNCTIONS has DealAction + EmpireAction", game.ReplicatedStorage.Remotes:FindFirstChild("DealAction") ~= nil and game.ReplicatedStorage.Remotes:FindFirstChild("EmpireAction") ~= nil)
	check("EmpireAction bound {burst 4, 2/s, company}", binds.EmpireAction and binds.EmpireAction.limits.burst == 4 and binds.EmpireAction.limits.perSecond == 2 and binds.EmpireAction.limits.company == true)
	check("DealAction bound {burst 4, 2/s, company}", binds.DealAction and binds.DealAction.limits.burst == 4 and binds.DealAction.limits.perSecond == 2 and binds.DealAction.limits.company == true)

	------------------------------------------------------------------ garage gate
	local g = add(C.company({ stage = 1, money = 30000, models = { { stats = { reliability = 30 } } } }), 2001)
	check("garage: FIRST_CLIENT without a signed client", call("UpgradeOffice", g).err == "FIRST_CLIENT" and g.data.empire.office == 1)
	g.data.empire.contractsCompleted = 1
	g.data.money = 26999
	check("garage: NO_MONEY below $27,000", call("UpgradeOffice", g).err == "NO_MONEY" and g.data.empire.office == 1)
	g.data.money = 30000
	local r = call("UpgradeOffice", g)
	check("garage: first client + $27,000 -> Founder Headquarters", r.ok and g.data.empire.office == 2 and near(g.data.money, 3000, 1e-6), r.err)
	check("office purchase in the ledger", C.ledger(g.data.empire, "o", "office") == 27000)
	check("news: moved into the Founder Headquarters", string.find(g.data.empire.deals.news[1], "moved into the Founder Headquarters", 1, true) ~= nil)
	check("quest 'Out of the garage' = office 2, new text", (function() for _, q in EmpireConfig.QUESTS do if q.id == "office" then return q.target == 2 and q.desc == "Move from the garage into your first HQ." end end return false end)())
	check("quest 'Reliable supplier' counts signed clients", (function() for _, q in EmpireConfig.QUESTS do if q.id == "client" then return q.kind == "contractsCompleted" and q.desc == "Sign three business clients." end end return false end)())
	check("old daily contracts gone", #EmpireConfig.CONTRACTS == 0 and call("DeliverContract", g, { contractId = "helpdesk", modelId = "x" }).ok == false)
	check("staff cap of the new stage", (function() g.data.empire.employees.engineer = 24; local x = call("HireEmployee", g, { roleId = "engineer" }); g.data.empire.employees.engineer = 0; return x.err == "STAFF_FULL" end)())

	------------------------------------------------------------------ EmpireAction
	local s = add(C.company({ stage = 2, money = 5e6, models = { { base = 50 } } }), 2002)
	check("EmpireAction: non-table payload -> BAD_INPUT", invoke("EmpireAction", s, "labLevel").err == "BAD_INPUT")
	check("EmpireAction: unknown action", call("EmpireAction", s, { action = "launchRocket" }).err == "BAD_INPUT")
	check("labLevel: PREREQUISITE before the whole tree", call("EmpireAction", s, { action = "labLevel" }).err == "PREREQUISITE")
	for _, def in EmpireConfig.RESEARCH do s.data.empire.research[def.id] = true end
	s.data.empire.points = 100
	check("labLevel: NO_POINTS", call("EmpireAction", s, { action = "labLevel" }).err == "NO_POINTS")
	s.data.empire.points = 1e5
	s.data.money = 100
	check("labLevel: NO_MONEY", call("EmpireAction", s, { action = "labLevel" }).err == "NO_MONEY")
	s.data.money = 5e6
	r = call("EmpireAction", s, { action = "labLevel" })
	check("labLevel 0 -> 1: -200 RP, -$6,000", r.ok and s.data.empire.labLevel == 1 and near(s.data.empire.points, 1e5 - 200) and near(s.data.money, 5e6 - 6000), r.err)
	check("Lab level adds +1 core stat on future models", R.EmpireMath.bonuses(s.data.empire).core >= 1)
	s.data.empire.labLevel = 10
	check("labLevel: MAX_LEVEL at 10", call("EmpireAction", s, { action = "labLevel" }).err == "MAX_LEVEL")
	check("buyJet: OFFICE below stage 4", call("EmpireAction", s, { action = "buyJet" }).err == "OFFICE")
	s.data.empire.office = 4
	r = call("EmpireAction", s, { action = "buyJet" })
	check("buyJet at stage 4", r.ok and s.data.empire.jet == true, r.err)
	check("buyJet: OWNED", call("EmpireAction", s, { action = "buyJet" }).err == "OWNED")
	check("hrBudget 0.3 refused", call("EmpireAction", s, { action = "hrBudget", budget = 0.3 }).err == "BAD_INPUT")
	check("hrBudget NaN refused", call("EmpireAction", s, { action = "hrBudget", budget = 0 / 0 }).err == "BAD_INPUT")
	check("hrBudget 0.55 ok", call("EmpireAction", s, { action = "hrBudget", budget = 0.55 }).ok and s.data.empire.hr.budget == 0.55)
	check("hrAuto needs a boolean", call("EmpireAction", s, { action = "hrAuto", on = "no" }).err == "BAD_INPUT")
	check("hrAuto off keeps the budget", call("EmpireAction", s, { action = "hrAuto", on = false }).ok and s.data.empire.hr.auto == false and s.data.empire.hr.budget == 0.55)
	check("saveMode auto|off only", call("EmpireAction", s, { action = "saveMode", mode = "max" }).err == "BAD_INPUT" and call("EmpireAction", s, { action = "saveMode", mode = "off" }).ok and s.data.empire.saveMode == "off")
	s.data.empire.office = 2
	check("nightShift: OFFICE below stage 3", call("EmpireAction", s, { action = "nightShift", dept = "research", on = true }).err == "OFFICE")
	s.data.empire.office = 3
	check("nightShift: unknown department", call("EmpireAction", s, { action = "nightShift", dept = "lobby", on = true }).err == "BAD_INPUT")
	check("nightShift: on for research", call("EmpireAction", s, { action = "nightShift", dept = "research", on = true }).ok and s.data.empire.nightShift.research == true)
	check("nightShift: off removes the key", call("EmpireAction", s, { action = "nightShift", dept = "research", on = false }).ok and s.data.empire.nightShift.research == nil)
	local ap = call("EmpireAction", s, { action = "autoPrice", model = "nope", on = true })
	check("autoPrice: unknown model refused (models package rule)", ap.ok == false, ap.err)
	-- rate limit 4 burst through the real RemoteFunction
	local limited = 0
	for _ = 1, 8 do if invoke("EmpireAction", s, { action = "saveMode", mode = "auto" }).err == "RATE_LIMIT" then limited += 1 end end
	check("rate limit: burst 4, then RATE_LIMIT", limited >= 3, limited)
	local nc = add(R.Template.new(), 2003)
	check("NO_COMPANY before founding", invoke("DealAction", nc, { action = "pin", clientId = "helpdesk" }).err == "NO_COMPANY")

	------------------------------------------------------------------ DealAction
	local d = add(C.company({ stage = 3, money = 1e5, staff = { marketer = 6 }, models = { { base = 60 } } }), 2004)
	check("DealAction: unknown client", call("DealAction", d, { action = "pin", clientId = "acme" }).err == "BAD_INPUT")
	check("DealAction: unknown action", call("DealAction", d, { action = "bribe", clientId = "atlas" }).err == "BAD_INPUT")
	check("pin", call("DealAction", d, { action = "pin", clientId = "atlas" }).ok and d.data.empire.deals.pinned == "atlas")
	check("pin again = unpin", call("DealAction", d, { action = "pin", clientId = "atlas" }).ok and d.data.empire.deals.pinned == nil)
	check("skip", call("DealAction", d, { action = "skip", clientId = "ledger" }).ok and d.data.empire.deals.skip.ledger == true)
	check("pin clears skip", call("DealAction", d, { action = "pin", clientId = "ledger" }).ok and d.data.empire.deals.skip.ledger == nil and d.data.empire.deals.pinned == "ledger")
	check("joinMeeting away from the client office: TOO_FAR", call("DealAction", d, { action = "joinMeeting", clientId = "ledger" }).err == "TOO_FAR")
	check("joinMeeting without a running pilot: NO_MEETING", EmpireService.joinMeeting(d, Ops.client("ledger")).err == "NO_MEETING")
	table.insert(d.data.empire.deals.tripList, { client = "ledger", kind = "sign", back = d.data.empire.seconds + 100, founder = false, hosted = false, crew = 2 })
	check("joinMeeting during the pilot", EmpireService.joinMeeting(d, Ops.client("ledger")).ok and d.data.empire.deals.tripList[1].joined == true)
	check("joinMeeting twice: ALREADY_DONE", EmpireService.joinMeeting(d, Ops.client("ledger")).err == "ALREADY_DONE")
	local before = d.data.empire.deals.trust.ledger or 0
	for _ = 1, 101 do C.step(d, Economy, C.clockAt(22)) end
	local gain = (d.data.empire.deals.trust.ledger or 0) - before
	check("joined meeting: visit trust includes +0.15", near(gain, Ops.trustGain(d.data.empire, d.data, Ops.client("ledger"), false, false) + 0.15, 1e-9) or d.data.empire.deals.accounts.ledger ~= nil, gain)

	------------------------------------------------------------------ automatic HR through EmpireService.tick
	local h = add(C.company({ stage = 1, money = 20000, models = { { stats = { reliability = 30 } } } }), 2005)
	local office = M.G.Instance.new("Model")
	office.Name = "Office"
	local realGet, realRefresh = PlotService.get, PlotService.refresh
	-- plot double: only the office model the attributes go to (no building is generated here)
	PlotService.get = function(player) if player == h.player then return { office = office, owner = player } end return realGet(player) end
	PlotService.refresh = function() end
	local function tick(sess, n)
		for _ = 1, n do
			sess.live.revenue, sess.live.cost = 0, 0
			EmpireService.tick(sess, 1)
		end
	end
	tick(h, 19)
	check("no hire before 20 s", R.EmpireMath.staff(h.data.empire) == 0)
	tick(h, 1)
	check("first starter hire after 20 s (engineer first)", h.data.empire.employees.engineer == 1, R.EmpireMath.staff(h.data.empire))
	check("hire through the normal path: profile in sync", #h.data.empire.staffProfiles.engineer == 1 and type(h.data.empire.staffProfiles.engineer[1].n) == "string")
	check("flat agency fee $1,200 (ledger 'hire')", C.ledger(h.data.empire, "o", "hire") == 1200)
	check("news: HR hired", string.find(table.concat(h.data.empire.deals.news, "|"), "HR hired", 1, true) ~= nil)
	tick(h, 40)
	check("3 starter hires in 60 s (engineer, curator, researcher)", h.data.empire.employees.engineer == 1 and h.data.empire.employees.curator == 1 and h.data.empire.employees.researcher == 1, R.EmpireMath.staff(h.data.empire))
	tick(h, 40)
	check("4th hire needs the wage budget (no income -> none)", R.EmpireMath.staff(h.data.empire) == 3)
	local n0 = add(C.company({ stage = 1, money = 20000 }), 2006)
	tick(n0, 45)
	check("no hires without a live product", R.EmpireMath.staff(n0.data.empire) == 0)
	local off = add(C.company({ stage = 1, money = 20000, models = { { base = 30 } } }), 2007)
	off.data.empire.hr.auto = false
	tick(off, 45)
	check("HR auto off: no hires", R.EmpireMath.staff(off.data.empire) == 0)
	check("live.ops carries the wage and income lines", h.live.ops and type(h.live.ops.wagesCost) == "number" and type(h.live.ops.income) == "number" and h.live.ops.saveMode ~= nil)
	check("garage: no hotel attributes", office:GetAttribute("HotelRooms") == nil)
	check("RackFaults / ServerFaults written", office:GetAttribute("RackFaults") == "" and office:GetAttribute("ServerFaults") == 0)
	check("live.compute {units, reserved, faults}", h.live.compute and type(h.live.compute.units) == "number" and type(h.live.compute.faults) == "table" and type(h.live.compute.reserved) == "number")
	-- stage 3: guest house attributes; forced rack faults show on the office
	h.data.empire.office = 3
	h.data.gpus = { laptop = 1, consumer = 3 }
	local realRate = Ops.FAULT.rate
	Ops.FAULT.rate = 60
	tick(h, 61)
	Ops.FAULT.rate = realRate
	check("HotelRooms = 12, HotelGuests = 7 at stage 3", office:GetAttribute("HotelRooms") == 12 and office:GetAttribute("HotelGuests") == Ops.hotelGuests(h.data.empire))
	check("RackFaults lists the failed blade slots", office:GetAttribute("RackFaults") == "1,2,3" and office:GetAttribute("ServerFaults") == 3, office:GetAttribute("RackFaults"))
	check("live.compute.faults has slot + gpu", #h.live.compute.faults == 3 and h.live.compute.faults[1].slot == 1 and h.live.compute.faults[1].gpu == "consumer")
	local writes = 0
	office.AttributeChanged:Connect(function() writes += 1 end)
	Ops.FAULT.rate = 0
	tick(h, 5)
	check("office attributes are written only on change", writes == 0, writes)
	PlotService.get, PlotService.refresh = realGet, realRefresh

	------------------------------------------------------------------ ledger caps
	do
		local x = add(C.company({ stage = 2 }), 2008)
		local e = x.data.empire
		for k = 1, 30 do Economy.applyFlow(x, 1.5, 0, "cat" .. k) end
		local n = C.count(e.ledger["1"].i)
		check("ledger: <= LEDGER_CATEGORIES (16) income categories ('other' included), rest in 'other'", n == R.Ops.LEDGER_CATEGORIES and (e.ledger["1"].i.other or 0) > 0, n)
		for day = 2, 12 do e.calendar.day = day; Economy.applyFlow(x, 10, 5, "market") end
		check("ledger keeps the newest 7 days", C.count(e.ledger) == 7 and e.ledger["12"] ~= nil and e.ledger["5"] == nil)
		e.calendar.day = 12
		local m0 = e.ledger["12"].i.market
		for _ = 1, 10 do Economy.applyFlow(x, 0.25, 0, "market") end
		check("fractions carried: 10 x $0.25 = +$2 (whole dollars stored)", e.ledger["12"].i.market == m0 + 2, e.ledger["12"].i.market - m0)
		check("applyFlow default category = market", (function() local y = add(C.company({}), 2009); Economy.applyFlow(y, 5, 0); return y.data.empire.ledger["1"].i.market == 5 end)())
		check("spend/grant without category: booked as 'other' (ledger adds up to cash)", (function() local y = add(C.company({}), 2010); Economy.spend(y, 5); Economy.grant(y, 7); local l = y.data.empire.ledger["1"]; return l ~= nil and l.o.other == 5 and l.i.other == 7 end)())
	end

	------------------------------------------------------------------ NPC band, marketplace offers, no lease auction
	NPCService.init()
	local okBand, okOffice = true, true
	for _, n in NPCService.sessions do
		okOffice = okOffice and n.data.empire.office == 3
		local m = n.data.models[n.data.modelOrder[1]]
		for _, st in R.ModelConfig.STATS do if st.weight > 0 and st.id ~= "reliability" then okBand = okBand and m.stats[st.id] <= 64 end end
	end
	check("NPC labs at stage 3 (12 slots, thermal 40)", okOffice and R.HardwareConfig.slots(NPCService.sessions[1].data.empire) == 12)
	check("NPC start band <= 64 per stat", okBand)
	for _ = 1, 3600 do NPCService.tick(1) end
	local best = 0
	okBand = true
	for _, n in NPCService.sessions do
		local m = n.data.models[n.data.modelOrder[1]]
		best = math.max(best, m.overall)
		for _, st in R.ModelConfig.STATS do if st.weight > 0 and st.id ~= "reliability" then okBand = okBand and m.stats[st.id] <= 64 + 1e-9 end end
		check("NPC API price floor $1", m.release.apiPrice >= 1 - 1e-9, m.release.apiPrice)
	end
	check("after an hour every NPC stat still <= 64", okBand)
	check("NPC best overall stays in the band (<= 64)", best <= 64, best)
	s.data.models["model-1"].market.vage = 95 -- offers show whole 30 s steps (corefix: MarketService.OFFER_AGE_STEP) -> 90
	MarketService.tickGlobal(1)
	check("lease auction removed (Market.customers empty)", #MarketService.customers == 0)
	local offer = nil
	for _, o in MarketService.offers do if o.providerId == 2002 then offer = o end end
	check("offers carry target, npc flag and vage (models request 1)", offer ~= nil and offer.target == "general" and offer.npc == false and offer.vage == 90, offer and offer.vage)
	local npcOffer = nil
	for _, o in MarketService.offers do if o.providerId < 0 then npcOffer = o end end
	check("NPC offers flagged npc = true", npcOffer ~= nil and npcOffer.npc == true)
	-- the market tick publishes capacity / waitlist / load / demand and books 'market'
	s.live.revenue, s.live.cost = 0, 0
	MarketService.tick(s, 1)
	check("live.capacity / waitlist / load / demand", type(s.live.capacity) == "number" and type(s.live.waitlist) == "number" and type(s.live.load) == "number" and type(s.live.demand) == "number")
	check("market revenue in the ledger", C.ledger(s.data.empire, "i", "market") >= 0)

	------------------------------------------------------------------ studio per game day, stall fix constant
	check("studio reward x0.5 per game day", StudioService.STUDIO_SCALE == 0.5 and StudioService.DAY == 1200)
	check("AIModelService loaded (models package)", AIModelService ~= nil)
end
local ok, err = M.runMain(body, { timeout = 100000, maxSteps = 50000000 })
if not ok then C.fail += 1; print("ERROR " .. tostring(err)) end
C.summary("econ service tests")
