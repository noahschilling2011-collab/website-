--!nocheck
-- econ package: replication budget of the new company state (CORE_SPEC 11.8) on the real code:
--  (a) full snapshot growth of the DATA_VERSION 6 fields of a mature company after 4 game days of the real
--      economy (EmpireService.tick + MarketService.tick: B2B pipeline, ledger, news) <= 6 KB, with the parts
--      deals / ledger / rest; and the same at every list cap (worst case, reported);
--  (b) delta bytes of the new fields per player per second with the real SessionService.LAZY spec
--      (StatePatch.diff each second, full compare every 5 s) for 12 companies <= 0.5 KB/s; the marketplace
--      offers' new vage field (corefix: LAZY) adds <= 0.1 KB/s, and would add > 0.5 KB/s without LAZY.
--  (c) corefix: the per-part budgets of 11.8 at every list cap: deals <= 3 KB, ledger <= 2.5 KB (replicated).
-- Sizes are the JSON proxy of tests/net (mock encoder). The whole-snapshot bandwidth with 12 players is
-- tests/net/test_e2e.luau (run_all "net_e2e").
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_econ && tools/luau tests/econ/test_net.luau [-a .gen_dir]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_econ")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local C = require("./common")
local check = C.check
local F = require("../net/mature")

local NEW_EMPIRE = { "calendar", "deals", "labLevel", "jet", "hr", "saveMode", "nightShift", "apprentices", "unpaidLeave", "ledger" }
local NEW_LIVE = { "ops", "compute", "capacity", "waitlist", "load", "demand" }

local function body()
	local R = C.load(M)
	local game = M.game
	local S = R.Server.Services
	local Ops = R.Ops
	local Remote = M.require(R.Server.Lib.Remote)
	Remote.setup()
	local SessionService = M.require(S.SessionService)
	local StatePatch = M.require(R.RS.Shared.StatePatch)
	local MarketService = M.require(S.MarketService)
	local EmpireService = M.require(S.EmpireService)
	local AIModelService = M.require(S.AIModelService)
	SessionService.init()
	local sessions = SessionService.all()
	local function json(v) return #M.JSON.encode(v) end
	local function newView(s)
		local e = {}
		for _, k in NEW_EMPIRE do e[k] = s.data.empire[k] end
		local live = {}
		for _, k in NEW_LIVE do live[k] = s.live[k] end
		return { data = { empire = e, trainings = s.data.trainings }, live = live }
	end
	local function strip(s)
		local d = table.clone(s.data)
		d.empire = table.clone(d.empire)
		for _, k in NEW_EMPIRE do d.empire[k] = nil end
		d.trainings = nil
		d.shop = nil
		local live = table.clone(s.live)
		for _, k in NEW_LIVE do live[k] = nil end
		return { data = d, live = live }
	end
	-- what the client gets (SessionService.replicatedData: shop receipts stripped, news trimmed to 20)
	local function full(s)
		local d = table.clone(SessionService.replicatedData(s.data))
		d.shop = nil
		return { data = d, live = s.live }
	end
	local function sentDeals(s) return SessionService.replicatedData(s.data).empire.deals end
	local function sentLedger(s) return SessionService.replicatedData(s.data).empire.ledger end
	local players = {}
	for i = 1, 12 do
		local uid = 3000 + i
		local data = F.build(M, { userId = uid, live = 4, seed = i, name = "Company " .. i })
		data.empire.office = 5
		data.money = 5e6
		for _, id in data.modelOrder do
			local m = data.models[id]
			if m.status == "live" then for _, st in R.ModelConfig.STATS do m.stats[st.id] = math.max(m.stats[st.id] or 0, 92) end end
		end
		local player = { UserId = uid, Name = "P" .. i, DisplayName = "Player " .. i, Parent = game.Players }
		local s = C.session(data, uid)
		s.player = player
		s.lastSent, s.nextSaveAt, s.saving, s.released = 0, math.huge, false, false
		sessions[player] = s
		table.insert(players, s)
	end
	local function simulate()
		M.Sched.now += 1 -- the visible server clock (workspace:GetServerTimeNow) advances with the simulation
		MarketService.tickGlobal(1)
		for _, s in players do
			AIModelService.tick(s, 1)
			MarketService.tick(s, 1)
			EmpireService.tick(s, 1)
		end
	end
	-- (a) 4 game days of the real economy for company 1 (the others run along)
	local probe = players[1]
	for _ = 1, 4 * 1200 do
		M.Sched.now += 1
		MarketService.tickGlobal(1)
		AIModelService.tick(probe, 1)
		MarketService.tick(probe, 1)
		EmpireService.tick(probe, 1)
	end
	local e = probe.data.empire
	check("the real pipeline ran (accounts signed, news written)", C.count(e.deals.accounts) >= 4 and #e.deals.news >= 10, C.count(e.deals.accounts))
	local growth = json(full(probe)) - json(strip(probe))
	local deals, ledger = json(sentDeals(probe)), json(sentLedger(probe))
	check("news: 40 lines saved, newest 20 replicated", #e.deals.news == 40 and #sentDeals(probe).news == 20 and sentDeals(probe).news[1] == e.deals.news[1])
	check("replicatedData never modifies the save", #probe.data.empire.deals.news == 40)
	local liveNew = 0
	for _, k in NEW_LIVE do liveNew += json(probe.live[k] or 0) end
	local rest = growth - deals - ledger
	local persistentRest = 0
	for _, k in NEW_EMPIRE do if k ~= "deals" and k ~= "ledger" then persistentRest += json(e[k]) end end
	persistentRest += json(probe.data.trainings)
	check(string.format("other new persistent fields < 0.5 KB (%.2f KB)", persistentRest / 1024), persistentRest < 512)
	print(string.format("  after 4 game days: snapshot growth %.2f KB (deals %.2f KB: %d accounts, %d trips, %d news saved; ledger %.2f KB, %d days; live.ops %.2f KB; rest %.2f KB)",
		growth / 1024, deals / 1024, C.count(e.deals.accounts), #e.deals.tripList, #e.deals.news, ledger / 1024, C.count(e.ledger), json(probe.live.ops) / 1024, rest / 1024))
	check(string.format("full snapshot growth <= 6 KB (%.2f KB)", growth / 1024), growth <= 6 * 1024)
	check(string.format("deals <= 3 KB (%.2f KB)", deals / 1024), deals <= 3 * 1024)
	check(string.format("ledger <= 2.5 KB (%.2f KB)", ledger / 1024), ledger <= 2.5 * 1024)
	-- worst case: every list at its cap (14 accounts at stage 5, every field rep + the founder travelling,
	-- 40 news lines of the maximum length, 7 ledger days with LEDGER_CATEGORIES lines per side, 8-digit values)
	local function worst(lineLength)
		local w = C.company({ stage = 5 })
		local we = w.empire
		local d = Ops.ensure(we)
		for k = 1, 14 do local c = Ops.CLIENTS[k + 4]; d.accounts[c.id] = { expires = 123456, since = 98765, founder = k <= 2 or nil, renewing = k % 3 == 0 or nil } end
		for k = 1, 4 do d.trust[Ops.CLIENTS[k].id] = 0.123456 end
		for k = 1, 7 do table.insert(d.tripList, { client = Ops.CLIENTS[k + 10].id, kind = "sign", back = 123456, founder = false, hosted = k % 2 == 0, crew = 2, left = 120000 }) end
		local line = "field rep leaves for Nova Infrastructure pilot (flight, 2 nights, $2,520) and more and more text"
		for k = 1, 40 do Ops.news(d, string.sub(line .. string.rep(".", 120), 1, lineLength - 14) .. k) end
		local incomes = { "market", "b2b", "pilot", "studio", "guest", "api", "quest", "daily", "retail", "travel", "gpusale", "admin", "debug", "refund", "bonus" }
		local costs = { "wages", "ops", "upkeep", "food", "fleet", "trips", "guest", "b2bserve", "jet", "market", "hire", "office", "lab", "jetbuy", "research" }
		for day = 1, 7 do
			local entry = { i = { other = 12345678 }, o = { other = 12345678 } }
			for _, cat in incomes do entry.i[cat] = 12345678 end
			for _, cat in costs do entry.o[cat] = 12345678 end
			we.ledger[tostring(day + 20)] = entry
		end
		we.calendar = { day = 27, index = 1416700 }
		local sent = SessionService.replicatedData(w).empire
		return json(sent.deals), json(sent.ledger), C.count(sent.ledger)
	end
	local wd, wl, wdays = worst(86)
	print(string.format("  worst case (14 accounts, 7 trips, 40 news of 86 chars, 7 ledger days x 2 x 16 lines, %d days replicated): deals %.2f KB, ledger %.2f KB", wdays, wd / 1024, wl / 1024))
	check(string.format("11.8 worst case deals <= 3 KB (%.2f KB)", wd / 1024), wd <= 3 * 1024)
	check(string.format("11.8 worst case ledger <= 2.5 KB (%.2f KB, %d of 7 days replicated)", wl / 1024, wdays), wl <= 2.5 * 1024 and wdays == Ops.LEDGER_SHOWN)
	local cd, cl = worst(140)
	print(string.format("  absolute caps (news texts of 140 chars, clipped to %d bytes): deals %.2f KB, ledger %.2f KB", Ops.NEWS_CHARS, cd / 1024, cl / 1024))
	check(string.format("11.8 absolute caps: deals <= 3 KB (%.2f KB), ledger <= 2.5 KB (%.2f KB)", cd / 1024, cl / 1024), cd <= 3 * 1024 and cl <= 2.5 * 1024)
	check(string.format("11.8 absolute caps: new persistent fields <= 6 KB incl. the rest (%.2f KB)", (cd + cl + 512) / 1024), cd + cl + 512 <= 6 * 1024)

	-- (b) deltas of the new fields, 12 companies, the real SessionService.LAZY spec (full compare every 5 s)
	local LAZY = SessionService.LAZY
	check("SessionService.LAZY exported (deals.news/trust/broke, ledger, live.ops, offers users + vage)", LAZY.data.empire.deals.news and LAZY.data.empire.deals.broke and LAZY.data.empire.ledger and LAZY.live.ops and LAZY.live.marketplace.offers["*"].vage == true)
	local shadows = {}
	for _, s in players do shadows[s] = StatePatch.copy(newView(s)) end
	local bytes, sends = 0, 0
	local SECONDS = 120
	for t = 1, SECONDS do
		simulate()
		for _, s in players do
			local lazy = t % 5 ~= 0 -- full compare every 5 s (REPLICATE_LAZY_SECONDS)
			for _ = 1, 2 do -- 2 sends per second (REPLICATE_SECONDS 0.5)
				local patch = StatePatch.diff(shadows[s], newView(s), if lazy then LAZY else nil)
				if patch then bytes += json(patch); sends += 1 end
				lazy = true
			end
		end
	end
	local perPlayer = bytes / 12 / SECONDS / 1024
	print(string.format("  deltas of the new fields: %.3f KB/s per player (%d patches in %d s for 12 companies)", perPlayer, sends, SECONDS))
	check(string.format("new-field deltas <= 0.5 KB/s per player (%.3f)", perPlayer), perPlayer <= 0.5)
	-- marketplace offers (every live model of the server, shown to every player): cost of the new vage field
	local byUser = {}
	for _, s in players do byUser[s.userId] = s end
	-- withVage: true = the offers as sent, false = without vage, "raw" = the econ build (raw per-second vage)
	local function offersView(s, withVage)
		local market = s.live.marketplace
		local offers = {}
		for i, o in (market and market.offers) or {} do
			local c = table.clone(o)
			if not withVage then c.vage = nil end
			if withVage == "raw" then
				local owner = byUser[o.providerId]
				local m = owner and owner.data.models[o.id]
				c.vage = m and m.market.vage
			end
			offers[i] = c
		end
		return { live = { marketplace = { offers = offers } } }
	end
	local function offerBytes(withVage, lazySpec, seconds)
		local sh = {}
		for _, s in players do sh[s] = StatePatch.copy(offersView(s, withVage)) end
		local total = 0
		for t = 1, seconds do
			simulate()
			for _, s in players do
				local lazy = t % 5 ~= 0
				for _ = 1, 2 do
					local patch = StatePatch.diff(sh[s], offersView(s, withVage), if lazy then lazySpec else nil)
					if patch then total += json(patch) end
					lazy = true
				end
			end
		end
		return total / 12 / seconds / 1024
	end
	local nOffers = #(players[1].live.marketplace and players[1].live.marketplace.offers or {})
	local withV = offerBytes(true, LAZY, 60)
	local without = offerBytes(false, LAZY, 60)
	print(string.format("  marketplace offers (%d offers): %.3f KB/s per player with vage, %.3f without -> vage costs %.3f KB/s", nOffers, withV, without, withV - without))
	check(string.format("offers carry vage for every live model (%d offers)", nOffers), nOffers >= 12 and players[1].live.marketplace.offers[1].vage ~= nil)
	check(string.format("vage on the offers (30 s steps, LAZY) costs <= 0.05 KB/s per player (%.3f)", withV - without), withV - without <= 0.05)
	check(string.format("all new deltas incl. vage <= 0.5 KB/s per player (%.3f)", perPlayer + withV - without), perPlayer + withV - without <= 0.5)
	-- NEGATIVE: the econ build (raw per-second vage, not LAZY) pays every change of every offer
	local noVageLazy = StatePatch.copy(LAZY)
	noVageLazy.live.marketplace.offers["*"].vage = nil
	local eagerV = offerBytes("raw", noVageLazy, 30)
	print(string.format("  negative: raw vage, not LAZY (econ build) -> %.3f KB/s per player for the offers", eagerV))
	check(string.format("negative: the econ build's raw vage costs > 0.5 KB/s more (%.3f vs %.3f)", eagerV, without), eagerV - without > 0.5)
	-- NEGATIVE: without the LAZY spec the same run costs more (the spec matters)
	local shadows2 = {}
	for _, s in players do shadows2[s] = StatePatch.copy(newView(s)) end
	local eager = 0
	for _ = 1, 30 do
		simulate()
		for _, s in players do local p = StatePatch.diff(shadows2[s], newView(s), nil); if p then eager += json(p) end end
	end
	check("negative: eager compare sends more than LAZY", eager / 30 > bytes / SECONDS / 2, string.format("%.0f vs %.0f B/s", eager / 30, bytes / SECONDS))
end
local ok, err = M.runMain(body, { timeout = 100000, maxSteps = 500000000 })
if not ok then C.fail += 1; print("ERROR " .. tostring(err)) end
C.summary("econ net tests")
