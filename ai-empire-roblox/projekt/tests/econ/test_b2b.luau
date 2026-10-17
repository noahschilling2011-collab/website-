--!nocheck
-- econ package: the B2B pipeline of CompanyOps.step (CORE_SPEC 3.2 / 3.5 / 11.2) on the real modules:
-- scripted first CloudDesk pilot (founder, any hour), departure window, cash margin, trust visits, signing
-- (pilot fee, reputation, contractsCompleted, retainer + B2B serving flows, compute reservation), check-in
-- renewals, the three loss reasons, field reps + account limit, founder accounts, hosted pilots at the
-- guest house, abroad flights / company jet, pin / skip, news log and live.ops for the visuals.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_econ && tools/luau tests/econ/test_b2b.luau [-a .gen_dir]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_econ")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local C = require("./common")
local check, near = C.check, C.near

local function body()
	local R = C.load(M)
	local Ops = R.Ops
	local Economy = M.require(R.Server.Services.EconomyService)
	local function run(s, seconds, clockFn)
		for i = 1, seconds do C.step(s, Economy, clockFn(i)) end
	end
	local function fixed(clock) return function() return clock end end
	local NIGHT, DAY10 = C.clockAt(22), C.clockAt(10)

	------------------------------------------------------------------ scripted first pilot
	local d = C.company({ stage = 1, money = 20000, models = { { stats = { reliability = 30, creativity = 12, coding = 12 } } } })
	local e = d.empire
	local s = C.session(d)
	C.step(s, Economy, NIGHT)
	local dl = e.deals
	check("founder leaves for CloudDesk at night (scripted first pilot)", #dl.tripList == 1 and dl.tripList[1].client == "helpdesk" and dl.tripList[1].founder == true, #dl.tripList)
	check("city trip: back after 240 s", dl.tripList[1] and near(dl.tripList[1].back - e.seconds, 240, 1e-6))
	check("trip cost $80 booked as trips", C.ledger(e, "o", "trips") == 80)
	check("news: founder drives", string.find(dl.news[1], "founder drives to CloudDesk: pilot", 1, true) ~= nil, dl.news[1])
	check("news is stamped with day and hour", string.match(dl.news[1], "^day %d+ %d%d:%d%d: ") ~= nil, dl.news[1])
	check("live.ops lists the trip for the visuals", s.live.ops.travelling == 1 and s.live.ops.trips[1].client == "helpdesk" and s.live.ops.trips[1].tier == "city" and s.live.ops.trips[1].founder == true)
	run(s, 238, fixed(NIGHT))
	check("still on the road after 239 s", #dl.tripList == 1 and e.contractsCompleted == 0)
	local money0, rep0 = d.money, d.company.reputation
	run(s, 2, fixed(NIGHT))
	check("CloudDesk signed on the first visit", dl.accounts.helpdesk ~= nil and dl.signed == 1, C.count(dl.accounts))
	check("contractsCompleted +1 (garage gate, quest)", e.contractsCompleted == 1)
	check("pilot fee = 1 day of retainer ($9,000) as revenue 'pilot'", C.ledger(e, "i", "pilot") == 9000)
	check("pilot fee counts toward totalRevenue", d.stats.totalRevenue >= 9000)
	check("reputation +1.5", near(d.company.reputation - rep0, 1.5, 1e-9))
	check("news: signed with pilot and retainer", string.find(table.concat(dl.news, "|"), "signed CloudDesk: pilot $9,000, $9,000/day", 1, true) ~= nil)
	check("account term 6 days", near(dl.accounts.helpdesk.expires - e.seconds, 6 * 1200, 1.01))
	check("trust bar cleared after signing", dl.trust.helpdesk == nil)
	local b0 = C.ledger(e, "i", "b2b")
	run(s, 1200, fixed(NIGHT))
	check("retainer $9,000 per game day (category b2b)", math.abs(C.ledger(e, "i", "b2b") - b0 - 9000) <= 2, C.ledger(e, "i", "b2b") - b0)
	check("B2B serving cost booked (b2bserve)", C.ledger(e, "o", "b2bserve") > 0)
	check("compute reserved = tokens / 100", near(dl.reserved, 0.4, 1e-9), dl.reserved)
	check("no second founder trip at night", #dl.tripList == 0)
	check("live.ops: 1 account of 2 founder slots", s.live.ops.accounts == 1 and s.live.ops.limit == 2)

	------------------------------------------------------------------ departure window + founder city clients
	d.models["model-1"].stats.creativity = 31
	C.step(s, Economy, C.clockAt(7.9))
	check("no departure before 08:00", #dl.tripList == 0)
	C.step(s, Economy, C.clockAt(15.1))
	check("no departure after 15:00", #dl.tripList == 0)
	C.step(s, Economy, C.clockAt(9))
	check("founder leaves for Paper Studio at 09:00", #dl.tripList == 1 and dl.tripList[1].client == "paper")
	check("renew trips don't count against the account limit", true)
	run(s, 240, fixed(C.clockAt(9)))
	check("Paper Studio visit: trust 0.5 + 0.025 x 1 = 52 % (no sign yet)", dl.accounts.paper == nil and near(dl.trust.paper, 0.525, 1e-9), dl.trust.paper)
	check("news: visited with trust", string.find(table.concat(dl.news, "|"), "visited Paper Studio: trust 52%", 1, true) ~= nil)
	run(s, 240, fixed(C.clockAt(9)))
	check("second visit signs (trust >= 1)", dl.accounts.paper ~= nil and dl.signed == 2, dl.trust.paper)
	d.models["model-1"].stats.coding = 40
	run(s, 30, fixed(C.clockAt(9)))
	check("founder holds at most 2 accounts (no ByteWorks trip)", #dl.tripList == 0 and dl.accounts.code == nil)

	------------------------------------------------------------------ renewal
	dl.accounts.helpdesk.expires = e.seconds + 0.6 * 1200
	C.step(s, Economy, C.clockAt(9))
	check("check-in trip when the term ends within trip + 0.5 days", #dl.tripList == 1 and dl.tripList[1].kind == "renew" and dl.accounts.helpdesk.renewing == true)
	local exp0 = dl.accounts.helpdesk.expires
	run(s, 240, fixed(C.clockAt(9)))
	check("renewed for 6 more days", near(dl.accounts.helpdesk.expires - exp0, 6 * 1200, 1e-6) and dl.accounts.helpdesk.renewing == nil, dl.accounts.helpdesk.expires - exp0)
	check("news: renewed", string.find(table.concat(dl.news, "|"), "renewed CloudDesk for 6 days", 1, true) ~= nil)
	-- the account does not lapse while the check-in trip is under way
	dl.accounts.helpdesk.expires = e.seconds + 100
	C.step(s, Economy, C.clockAt(9))
	run(s, 150, fixed(C.clockAt(9)))
	check("no lapse during the check-in trip", dl.accounts.helpdesk ~= nil and dl.lost == 0)
	run(s, 100, fixed(C.clockAt(9)))

	------------------------------------------------------------------ losses
	dl.accounts.paper.expires = e.seconds - 1
	dl.accounts.paper.renewing = nil
	C.step(s, Economy, NIGHT)
	check("lost: term ended without a check-in", dl.accounts.paper == nil and dl.lost == 1 and string.find(dl.news[1], "lost Paper Studio (no check-in before the term ended)", 1, true) ~= nil, dl.news[1])
	d.models["model-1"].stats.reliability = 10
	C.step(s, Economy, NIGHT)
	check("lost: no live model meets the need (with numbers)", dl.accounts.helpdesk == nil and string.find(dl.news[1], "needs reliability 24, best live 10", 1, true) ~= nil, dl.news[1])
	d.models["model-1"].stats.reliability = 30
	dl.accounts.helpdesk = { expires = e.seconds + 5000, since = e.seconds, founder = true }
	d.gpus = {}
	local capBefore = Ops.tokenCap(d)
	C.step(s, Economy, NIGHT)
	check("lost: not enough server capacity", capBefore < 40 and dl.accounts.helpdesk == nil and string.find(dl.news[1], "not enough server capacity", 1, true) ~= nil, dl.news[1])
	check("reservation released", dl.reserved == 0)

	------------------------------------------------------------------ cash margin
	do
		local x = C.company({ stage = 1, money = 579, models = { { stats = { reliability = 30 } } } })
		local xs = C.session(x)
		C.step(xs, Economy, NIGHT)
		check("no trip while cash < cost + $500", #x.empire.deals.tripList == 0)
		x.money = 700
		C.step(xs, Economy, NIGHT)
		check("trip once cash covers it", #x.empire.deals.tripList == 1)
	end

	------------------------------------------------------------------ field reps, region pilots, hosted pilots
	do
		local x = C.company({ stage = 3, money = 1e6, staff = { marketer = 10, engineer = 10 }, skill = 3, gpus = { laptop = 1, workstation = 6 },
			models = { { stats = { reliability = 60, creativity = 60, coding = 60, math = 60, reasoning = 60, knowledge = 60 } } } })
		local xe = x.empire
		local xs = C.session(x)
		xe.deals.signed = 3 -- not the first client any more
		check("stage 3: 3 field reps, 2 + 2 x 3 = 7 accounts (slots 7)", Ops.fieldReps(xe) == 3 and Ops.accountLimit(xe) == 7)
		C.step(xs, Economy, DAY10)
		local reps, founder = 0, 0
		for _, t in xe.deals.tripList do if t.founder then founder += 1 else reps += 1 end end
		check("each free field rep starts one trip", reps == 3, reps)
		check("the founder takes a city client", founder == 1)
		local first = nil
		for _, t in xe.deals.tripList do if not t.founder then first = first or t end end
		check("reps pick the highest retainer first (Atlas Search $36k)", first and first.client == "atlas", first and first.client)
		check("region pilot crew 2, City Hotel night", first and first.crew == 2 and xe.deals.nights >= 2)
		check("travelling engineer counts as absent", Ops.travellers(xe).engineer >= 1)
		local presence = Ops.presence(xe, "engineer")
		local trips = 0
		for _, st in presence do if st == "trip" then trips += 1 end end
		check("presence marks travelling engineers", trips == Ops.travellers(xe).engineer, trips)
		check("pilots counter for hosting", xe.deals.pilots == 3)
		-- the 4th region pilot (pilots = 3 -> odd) is hosted at the guest house
		local hostedBefore = xe.deals.hosted
		xe.deals.tripList = {}
		xe.deals.pilots = 1
		C.step(xs, Economy, DAY10)
		local hosted = nil
		for _, t in xe.deals.tripList do if t.hosted then hosted = t end end
		check("every second region pilot is hosted at the guest house (pilots 1, 2, 3 -> hosted, travels, hosted)", hosted ~= nil and xe.deals.hosted == hostedBefore + 2 and xe.deals.pilots == 4, xe.deals.hosted - hostedBefore)
		check("hosted: crew stays home, 1 day", hosted and hosted.crew == 0 and near(hosted.back - xe.seconds, 1200, 1e-6))
		check("HotelGuests = 7 + 2 per hosted team", Ops.hotelGuests(xe) == 7 + 2 * Ops.hostedInHouse(xe) and Ops.hostedInHouse(xe) >= 1)
		check("hosted travellers are not absent", (function() local n = 0; for _, t in xe.deals.tripList do if t.hosted then n += 1 end end; return n >= 1 end)())
		-- pin + skip
		xe.deals.tripList = {}
		xe.deals.pinned = "ledger"
		xe.deals.skip.atlas = true
		C.step(xs, Economy, DAY10)
		local clients = {}
		for _, t in xe.deals.tripList do clients[t.client] = true end
		check("pinned client first", clients.ledger == true)
		check("skipped client never visited", clients.atlas == nil)
		-- account limit: with 7 accounts nobody starts a sign trip
		xe.deals.tripList = {}
		xe.deals.skip = {}
		xe.deals.pinned = nil
		local ids = { "helpdesk", "paper", "code", "pixel", "study", "north", "civic" }
		for _, id in ids do xe.deals.accounts[id] = { expires = xe.seconds + 5000, since = xe.seconds, founder = false } end
		C.step(xs, Economy, DAY10)
		local signs = 0
		for _, t in xe.deals.tripList do if t.kind == "sign" then signs += 1 end end
		check("account limit reached: no new pilots", signs == 0, signs)
	end

	------------------------------------------------------------------ abroad: flights and the jet
	do
		local x = C.company({ stage = 4, money = 1e6, staff = { marketer = 10 }, skill = 3, gpus = { laptop = 1, accelerator = 10 },
			models = { { stats = { math = 72, reliability = 70, creativity = 70, coding = 70, reasoning = 70, knowledge = 70 } } } })
		local xe = x.empire
		local xs = C.session(x)
		xe.deals.signed = 5
		C.step(xs, Economy, DAY10)
		local helix = nil
		for _, t in xe.deals.tripList do if t.client == "helix" then helix = t end end
		check("stage 4 abroad pilot to Helix Research", helix ~= nil)
		check("flights: 2 travellers, 2 nights each", xe.deals.flights == 2 and xe.deals.nights >= 4, xe.deals.flights)
		check("abroad trip 2 days", helix and near(helix.back - xe.seconds, 2400, 1e-6))
		local x2 = C.company({ stage = 4, money = 1e6, staff = { marketer = 10 }, skill = 3, gpus = { laptop = 1, accelerator = 10 },
			models = { { stats = { math = 72, reliability = 70, creativity = 70, coding = 70, reasoning = 70, knowledge = 70 } } } })
		x2.empire.jet = true
		x2.empire.deals.signed = 5
		local xs2 = C.session(x2)
		C.step(xs2, Economy, DAY10)
		local hj = nil
		for _, t in x2.empire.deals.tripList do if t.client == "helix" then hj = t end end
		check("with the jet: jet flight, 1.5 days", hj and near(hj.back - x2.empire.seconds, 1800, 1e-6) and x2.empire.deals.jetFlights == 1 and x2.empire.deals.flights == 0)
		check("news names the company jet", string.find(table.concat(x2.empire.deals.news, "|"), "jet + 1 night", 1, true) ~= nil)
		-- region clients need stage >= 3, abroad stage >= 4
		local y = C.company({ stage = 3, models = { { base = 99 } } })
		check("abroad needs stage 4", not Ops.eligible(y.empire, y, Ops.client("helix")))
		local z = C.company({ stage = 2, models = { { base = 99 } } })
		check("region needs stage 3", not Ops.eligible(z.empire, z, Ops.client("creative")) and Ops.eligible(z.empire, z, Ops.client("civic")))
	end

	------------------------------------------------------------------ watched == unwatched (same input, same money)
	do
		local function play(report)
			local x = C.company({ stage = 2, money = 50000, staff = { researcher = 4, engineer = 4, curator = 4, marketer = 4 }, models = { { base = 45 } } })
			local xs = C.session(x)
			for i = 1, 3000 do
				if report then R.Workforce.set(x.empire, { researcher = i % 7, engineer = 0, curator = 99, marketer = 1 }) end
				C.step(xs, Economy, (i * 1.0) % 1200 + 1.7e9)
			end
			return x.money, x.empire.deals.signed, R.Workforce.count(x.empire, "engineer")
		end
		local m1, s1, o1 = play(false)
		local m2, s2, o2 = play(true)
		check("watched == unwatched: same money, deals and output", m1 == m2 and s1 == s2 and o1 == o2, m1 .. " vs " .. m2)
	end
end
local ok, err = M.runMain(body, { timeout = 100000, maxSteps = 50000000 })
if not ok then C.fail += 1; print("ERROR " .. tostring(err)) end
C.summary("econ b2b tests")
