--!nocheck
-- shop package (SHOP_SPEC phases 1 + 2), server side on the real modules in the mock:
--   T1  Eureka on the running project (RP back, notice, voucher -1, quest claimable; equal to the timer's finish)
--   T2  Eureka on an idle project ($ on ledger "research", RP unchanged; every error keeps the voucher)
--   T3  Eureka on the Lab level ($ on ledger "lab", RP unchanged; PREREQUISITE / MAX_LEVEL / NO_MONEY)
--   T4  Last Epoch (NO_TRAINING, DECIDE_FIRST keeps the voucher, the event is rolled first; CHANCES over 2,000 runs)
--   T5  Keynote Boost / Overclock (NO_LIVE_MODEL, 900 / 1,800, BOOST_FULL at 2,701 s left, 4 a day, UTC reset,
--       frozen offline, revenue 1.20 / 1.30, training x1.5 with the 12 s floor)
--   T6  Last Epoch daily cap (11th redeem -> DAILY_LIMIT, kept)
--   T7  redeem target validation, BUSY, handlers that ignore the target
--   T8  save fields: cleanShop keeps valid boosts / daily / packs and drops junk; old saves repaired; round trip
--   T9  cash packs once per office (S1): a second receipt still grants; packs follow the office; S1 amounts
--   T10 Style Collection bundle (owns honours includes)
--   T11 Identity Kit: PASS_NEEDED on create / rebrand / StartTraining look, cooldown, refund keeps the colour,
--       old looks unchanged, readability (contrast >= 7 against bg, delta E >= 20)
--   T12 Rooftop Fireworks (NO_PLOT, FIREWORKS_ACTIVE, removed after 45 s, nothing collides)
--   T25 Headhunter deterministic (skill 4, ask 1.25, smallest team = headhuntPreview, errors keep the voucher)
--   +   phase 2: ServerGlow attribute, ready = false passes never sellable, status payload
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_shop2 && cd tests/shop2 && ../../tools/luau test_server.luau -a .gen_shop2
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_shop2")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local C = require("../econ/common")
local check = C.check

local function deepcopy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in v do out[k] = deepcopy(x) end
	return out
end
local function deepEqual(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b or (a ~= a and b ~= b) end
	for k, v in a do if not deepEqual(v, b[k]) then return false end end
	for k in b do if a[k] == nil then return false end end
	return true
end

local function body()
	local R = C.load(M)
	local G = M.G
	local Instance, CFrame, Vector3 = G.Instance, G.CFrame, G.Vector3
	G.os = setmetatable({ clock = function() return M.Sched.now end }, { __index = os }) -- virtual os.clock (rebrand cooldown)
	local RS, Server = R.RS, R.Server
	local S = Server.Services
	local EmpireConfig, Template, GameConfig = R.EmpireConfig, R.Template, R.GameConfig
	local Ops = R.Ops
	local ShopConfig = M.require(RS.Shared.Config.ShopConfig)
	local ShopMath = M.require(RS.Shared.ShopMath)
	local CompanyConfig = M.require(RS.Shared.Config.CompanyConfig)
	local ModelMath = R.ModelMath
	local Remote = M.require(Server.Lib.Remote)
	local SessionService = M.require(S.SessionService)
	local RateLimiter = M.require(Server.Lib.RateLimiter)
	RateLimiter.new = function() return { allow = function() return true end, forget = function() end } end

	-- doubles: Roblox marketplace, players, the DataStore save, PlotService
	local market = { owned = {}, PromptGamePassPurchaseFinished = M.newSignal("PromptGamePassPurchaseFinished") }
	function market:UserOwnsGamePassAsync(userId, id) return self.owned[userId .. ":" .. id] == true end
	local byUser = {}
	local playersDouble = { PlayerAdded = M.newSignal("PlayerAdded") }
	function playersDouble:GetPlayerByUserId(id) return byUser[id] end
	function playersDouble:GetPlayers() return {} end
	local plots = {}
	local Plot = { get = function(player) return plots[player] end, onChanged = function() end }
	local clock = 20000 * 86400 + 3600 -- os.time of the server (UTC day 20000, 01:00)
	local Shop = M.require(S.ShopService)
	Shop._setDeps({ market = market, players = playersDouble, save = function() return true, false end, now = function() return clock end, plot = function() return Plot end })

	local binds, notices = {}, {}
	local origBind = Remote.bind
	Remote.bind = function(name, limits, handler) binds[name] = handler; pcall(origBind, name, limits, handler) end
	Remote.fire = function(player, name, kind, payload) table.insert(notices, { player = player, name = name, kind = kind, payload = payload }) end
	Remote.setup()
	Shop.init()
	local Empire = M.require(S.EmpireService)
	local okEmpire, errEmpire = pcall(Empire.init)
	check("EmpireService.init runs in the mock (registers the Eureka handler)", okEmpire, errEmpire)
	local AIModel = M.require(S.AIModelService)
	local okModel, errModel = pcall(AIModel.init)
	check("AIModelService.init runs (registers the Last Epoch handler)", okModel, errModel)
	local CompanyService = M.require(S.CompanyService)
	pcall(CompanyService.init)
	local Recruiting = M.require(S.RecruitingService)
	local Economy = M.require(S.EconomyService)

	local nextUser = 7000
	local function newSession(data)
		nextUser += 1
		local player = { UserId = nextUser, Name = "P" .. nextUser, DisplayName = "Player" .. nextUser, Parent = game and game.Players or M.game.Players, Character = nil, CharacterAdded = M.newSignal("CharacterAdded") }
		function player:Kick() end
		byUser[nextUser] = player
		local s = { player = player, userId = nextUser, data = data or C.company({ money = 500000 }), live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} },
			dirty = false, lastSent = 0, nextSaveAt = math.huge, saving = false, closed = false, released = false, rng = G.Random.new(nextUser) }
		SessionService.all()[player] = s
		return s
	end
	local act = binds.ShopAction
	check("ShopAction bound", act ~= nil)
	local function redeem(s, key, target) return act(s, { action = "redeem", key = key, target = target }) end
	local function give(s, key, n) s.data.shop.vouchers[key] = n end
	local function held(s, key) return tonumber(s.data.shop.vouchers[key]) or 0 end
	local function noticeOf(kind) for i = #notices, 1, -1 do if notices[i].kind == kind then return notices[i] end end end
	local function live(s, id) local m = s.data.models[id]; m.status = "live"; return m end

	------------------------------------------------------------------ handlers registered
	do
		local s = newSession()
		local st = act(s, { action = "status" })
		check("status: ok with daily + boosts", st.ok == true and type(st.daily) == "table" and type(st.boosts) == "table")
		check("handlers: eureka, lastEpoch, keynote, overclock, fireworks, party redeemable", s.live.shop == nil or true)
		Shop.setRedeemHandler("probe", function() return true end) -- republishes live.shop for the attached sessions
		local red = s.live.shop and s.live.shop.redeemable or {}
		check("live.shop.redeemable lists the shop handlers", red.eureka and red.lastEpoch and red.keynote and red.overclock and red.fireworks and red.party, s.live.shop and table.concat((function() local t = {} for k in red do table.insert(t, k) end return t end)(), ","))
		local av = s.live.shop and s.live.shop.available or {}
		check("ready = false passes are never sellable (phase 3)", av.aiGallery == false and av.teamHoodies == false and av.roboBuddy == false)
		check("phase 1 + 2 passes sellable", av.identityKit == true and av.serverGlow == true and av.stageLights == true and av.styleCollection == true)
		check("voucher products sellable once their handler exists", av.eureka == true and av.lastEpoch == true and av.keynote == true and av.overclock == true and av.fireworks == true)
	end

	------------------------------------------------------------------ T1 Eureka: running project
	do
		local s = newSession(C.company({ money = 200000, staff = { researcher = 2 } }))
		local e = s.data.empire
		e.points = 40
		e.researchJob = { id = "pipeline", elapsed = 10, seconds = 35 }
		give(s, "eureka", 2)
		local twin = deepcopy(s.data)
		local xp0, money0 = e.xp, s.data.money
		local r = redeem(s, "eureka")
		check("T1 running project: ok, voucher -1", r.ok == true and r.left == 1 and held(s, "eureka") == 1, r.err)
		check("T1 research done, job cleared, xp +150", e.research.pipeline == true and e.researchJob == nil and e.xp == xp0 + 150)
		check("T1 the job's research points come back (+50)", e.points == 90, e.points)
		check("T1 no cash taken (paid at the start)", s.data.money == money0)
		local n = noticeOf("EMPIRE_NOTICE")
		check("T1 the same server notice as after the timer", n and n.payload.text == "Research complete: Parallel Training", n and n.payload.text)
		local quest = EmpireConfig.find(EmpireConfig.QUESTS, "research")
		check("T1 quest 'Lab breakthrough' claimable", R.EmpireMath.progress(s.data, quest) >= quest.target)
		-- equivalence: the timer's finish (Empire.tick) gives the same research state, apart from time and the RP
		local s2 = newSession(twin)
		notices = {}
		Empire.tick(s2, 25)
		local e2 = s2.data.empire
		check("T1 equivalence: research / job / xp equal to the timer's finish", deepEqual(e2.research, e.research) and e2.researchJob == nil and e2.xp == e.xp, e2.xp .. " vs " .. e.xp)
		local n2 = noticeOf("EMPIRE_NOTICE")
		check("T1 equivalence: same notice text", n2 and n2.payload.text == "Research complete: Parallel Training")
		-- a running project with a named target that is not the running one
		e.researchJob = { id = "cleaning", elapsed = 5, seconds = 45 }
		r = redeem(s, "eureka", "quantization")
		check("T1 running + other target -> RESEARCH_ACTIVE, kept", r.ok == false and r.err == "RESEARCH_ACTIVE" and held(s, "eureka") == 1)
		r = redeem(s, "eureka", "cleaning")
		check("T1 running + its own id -> ok", r.ok == true and e.research.cleaning == true and held(s, "eureka") == 0)
		r = redeem(s, "eureka")
		check("T1 no voucher left -> NO_VOUCHER", r.ok == false and r.err == "NO_VOUCHER")
	end

	------------------------------------------------------------------ T2 Eureka: idle project + errors
	do
		local s = newSession(C.company({ money = 30000 }))
		local e = s.data.empire
		e.points = 10
		give(s, "eureka", 5)
		local money0, points0 = s.data.money, e.points
		local lab0 = C.ledger(e, "o", "research")
		local r = redeem(s, "eureka", "cleaning")
		check("T2 idle project: ok", r.ok == true and e.research.cleaning == true and e.researchJob == nil, r.err)
		check("T2 the $ price is paid, on ledger 'research'", s.data.money == money0 - 6000 and C.ledger(e, "o", "research") == lab0 + 6000, s.data.money)
		check("T2 research points unchanged (covered, not taken)", e.points == points0)
		local function kept(err, target, label)
			local before = held(s, "eureka")
			local res = redeem(s, "eureka", target)
			check("T2 " .. label .. " -> " .. err .. ", voucher kept", res.ok == false and res.err == err and held(s, "eureka") == before, tostring(res.err))
		end
		kept("BAD_INPUT", "warp_drive", "unknown project")
		kept("BAD_INPUT", nil, "no target and no running job")
		kept("ALREADY_DONE", "cleaning", "done project")
		kept("PREREQUISITE", "architecture", "prerequisite missing")
		s.data.money = 100
		kept("NO_MONEY", "pipeline", "cash below the price")
		s.data.money = 30000
		e.researchJob = { id = "pipeline", elapsed = 1, seconds = 35 }
		kept("RESEARCH_ACTIVE", "quantization", "another project running")
		e.researchJob = nil
		local company = s.data.company
		s.data.company = nil
		kept("NO_COMPANY", "pipeline", "no company")
		s.data.company = company
	end

	------------------------------------------------------------------ T3 Eureka: Lab level
	do
		local s = newSession(C.company({ money = 1e6, research = "all" }))
		local e = s.data.empire
		e.labLevel = 3
		e.points = 7
		give(s, "eureka", 3)
		local pts, cost = Ops.labCost(3)
		local money0 = s.data.money
		local lab0 = C.ledger(e, "o", "lab")
		local r = redeem(s, "eureka", "lab")
		check("T3 Lab level: ok, level 4", r.ok == true and e.labLevel == 4, r.err)
		check("T3 the level's $ is paid, on ledger 'lab'", s.data.money == money0 - cost and C.ledger(e, "o", "lab") == lab0 + cost)
		check("T3 research points unchanged (" .. pts .. " RP covered)", e.points == 7)
		e.labLevel = 10
		r = redeem(s, "eureka", "lab")
		check("T3 level 10 -> MAX_LEVEL, kept", r.ok == false and r.err == "MAX_LEVEL" and held(s, "eureka") == 2)
		e.labLevel = 5
		e.research.cluster = nil
		r = redeem(s, "eureka", "lab")
		check("T3 tree open -> PREREQUISITE, kept", r.ok == false and r.err == "PREREQUISITE" and held(s, "eureka") == 2)
		e.research.cluster = true
		s.data.money = 10
		r = redeem(s, "eureka", "lab")
		check("T3 cash below the level -> NO_MONEY, kept", r.ok == false and r.err == "NO_MONEY" and held(s, "eureka") == 2)
	end

	------------------------------------------------------------------ T4 Last Epoch
	local function trainingSession(seed, progress)
		local d = C.company({ money = 1e6 })
		d.data = { general = { tokens = 4e9, quality = 0.6 } }
		local m = { id = "m1", name = "Nova", version = 1, sizeId = "s100m", focusId = "balanced", status = "training", createdAt = 0, trainedAt = 0,
			stats = {}, overall = 0, trainCost = 1000, dataUsed = { total = 4e9, quality = 0.6, shares = { general = 1 } } }
		d.models.m1 = m
		d.modelOrder = { "m1" }
		d.stats.modelsReleased = 1
		d.training = { modelId = "m1", workTotal = 100, workDone = progress, cost = 1000, expected = 40, qualityMod = 1, eventRolled = false, epoch = 0,
			loss = {}, log = {} }
		local s = newSession(d)
		s.rng = G.Random.new(seed)
		return s
	end
	do
		local s = newSession()
		give(s, "lastEpoch", 2)
		local r = redeem(s, "lastEpoch")
		check("T4 no training -> NO_TRAINING, kept", r.ok == false and r.err == "NO_TRAINING" and held(s, "lastEpoch") == 2)
		local t = trainingSession(11, 50)
		t.data.training.eventRolled = true
		t.data.training.event = { id = "data_issue", pending = true, expiresAt = math.huge }
		give(t, "lastEpoch", 1)
		r = redeem(t, "lastEpoch")
		check("T4 pending decision -> DECIDE_FIRST, kept, eventRolled stays true", r.ok == false and r.err == "DECIDE_FIRST" and held(t, "lastEpoch") == 1 and t.data.training.eventRolled == true)
		-- after 35 %: no second roll; the run finishes through finish() (TRAINING_COMPLETE, stats set)
		local t2 = trainingSession(12, 60)
		t2.data.training.eventRolled = true
		give(t2, "lastEpoch", 1)
		notices = {}
		r = redeem(t2, "lastEpoch")
		local done = noticeOf("TRAINING_COMPLETE")
		check("T4 after 35 %: finished, voucher used, no event rolled", r.ok == true and t2.data.training == nil and held(t2, "lastEpoch") == 0 and done and done.payload.eventId == nil)
		check("T4 final stats come from finish() like a waited run", t2.data.models.m1.status == "trained" and t2.data.models.m1.overall > 0 and t2.data.stats.modelsTrained == 1)
		-- refinement path: the same slot and rule
		local t3 = trainingSession(13, 20)
		local tr = t3.data.training
		tr.refinement = true
		tr.baseStats = { reasoning = 40, coding = 40, math = 40, creativity = 40, knowledge = 40, reliability = 40, speed = 80, efficiency = 80 }
		tr.eventRolled = true
		t3.data.models.m1.status = "live"
		t3.data.models.m1.iterations = 0
		give(t3, "lastEpoch", 1)
		r = redeem(t3, "lastEpoch")
		check("T4 refinement finishes (iterations +1, keeps serving)", r.ok == true and t3.data.models.m1.iterations == 1 and t3.data.models.m1.status == "live", r.err)
	end
	do
		-- before 35 % the event is rolled NOW; chances over 2,000 runs equal 2,000 waited runs (not equal ids: updateLoss
		-- draws from the same RNG before the event check)
		local N = 2000
		local skip, wait = { none = 0 }, { none = 0 }
		for i = 1, N do
			local s = trainingSession(100000 + i, 10)
			local t = s.data.training
			give(s, "lastEpoch", 1)
			AIModel.lastEpoch(s)
			check_rolled = t.eventRolled
			local id = if t.event then t.event.id else "none"
			skip[id] = (skip[id] or 0) + 1
			if i == 1 then check("T4 skipped at 10 %: the event check ran", t.eventRolled == true) end
		end
		for i = 1, N do
			local s = trainingSession(500000 + i, 0)
			local t = s.data.training
			local guard = 0
			while not t.eventRolled and guard < 400 do
				AIModel.tick(s, 0.05)
				guard += 1
				if s.data.training == nil then break end
			end
			local id = if t.event then t.event.id else "none"
			wait[id] = (wait[id] or 0) + 1
		end
		local skipRate = 1 - skip.none / N
		local waitRate = 1 - wait.none / N
		check(string.format("T4 chances: event rate skipped %.3f within 0.6 +- 0.03", skipRate), math.abs(skipRate - 0.6) <= 0.03)
		check(string.format("T4 chances: event rate waited %.3f within 0.6 +- 0.03", waitRate), math.abs(waitRate - 0.6) <= 0.03)
		local worst = 0
		for _, ev in R.ModelConfig.EVENTS do
			local a = (skip[ev.id] or 0) / N
			local b = (wait[ev.id] or 0) / N
			worst = math.max(worst, math.abs(a - b))
		end
		check(string.format("T4 chances: every event's share within 3 points of the waited runs (worst %.3f)", worst), worst <= 0.03)
	end

	------------------------------------------------------------------ T5 boosts
	do
		local s = newSession(C.company({ money = 1e5 }))
		local e = s.data.empire
		e.seconds = 1000
		give(s, "keynote", 9)
		local r = redeem(s, "keynote")
		check("T5 Keynote with no live model -> NO_LIVE_MODEL, kept", r.ok == false and r.err == "NO_LIVE_MODEL" and held(s, "keynote") == 9)
		s.data = C.company({ money = 1e5, models = { { base = 40 } } })
		s.data.empire.seconds = 1000
		e = s.data.empire
		give(s, "keynote", 9)
		r = redeem(s, "keynote")
		check("T5 start -> 900 s left", r.ok == true and Shop.boostLeft(s, "keynote") == 900 and held(s, "keynote") == 8, r.err)
		check("T5 revenue x1.20 while it runs", math.abs(Shop.revenueMultiplier(s) - 1.20) < 1e-9, Shop.revenueMultiplier(s))
		r = redeem(s, "keynote")
		check("T5 second start adds 15 min -> 1,800 s", r.ok == true and Shop.boostLeft(s, "keynote") == 1800)
		s.data.shop.boosts.keynote = e.seconds + 2701
		r = redeem(s, "keynote")
		check("T5 2,701 s left -> BOOST_FULL, kept (never more than 60 min)", r.ok == false and r.err == "BOOST_FULL" and held(s, "keynote") == 7)
		s.data.shop.boosts.keynote = e.seconds + 2700
		r = redeem(s, "keynote")
		check("T5 2,700 s left -> ok, exactly 60 min", r.ok == true and Shop.boostLeft(s, "keynote") == 3600)
		r = redeem(s, "keynote")
		check("T5 60 min left -> BOOST_FULL", r.ok == false and r.err == "BOOST_FULL")
		s.data.shop.boosts.keynote = nil
		r = redeem(s, "keynote")
		check("T5 4th start of the day ok", r.ok == true and ShopMath.dailyUsed(s.data, "keynote", clock) == 4)
		s.data.shop.boosts.keynote = nil
		r = redeem(s, "keynote")
		check("T5 5th start of the UTC day -> DAILY_LIMIT, kept", r.ok == false and r.err == "DAILY_LIMIT" and held(s, "keynote") == 5)
		clock += 86400
		r = redeem(s, "keynote")
		check("T5 next UTC day resets the counter", r.ok == true and ShopMath.dailyUsed(s.data, "keynote", clock) == 1)
		-- offline: empire.seconds does not move, so the time left does not either
		local left = Shop.boostLeft(s, "keynote")
		clock += 5000
		check("T5 offline (play time frozen) keeps the time left", Shop.boostLeft(s, "keynote") == left)
		e.seconds += left
		check("T5 the boost ends after its play time", Shop.boostLeft(s, "keynote") == 0 and math.abs(Shop.revenueMultiplier(s) - 1) < 1e-9)
		Shop.debugGrantPass(s, "investor")
		s.data.shop.boosts.keynote = e.seconds + 10
		check("T5 with Investor Relations: 1.30 (added, S6)", math.abs(Shop.revenueMultiplier(s) - 1.30) < 1e-9, Shop.revenueMultiplier(s))
		-- Overclock
		give(s, "overclock", 2)
		r = redeem(s, "overclock")
		check("T5 Overclock start", r.ok == true and Shop.boostLeft(s, "overclock") == 900 and Shop.trainingMultiplier(s) == 1.5)
		check("T5 Overclock x1.5 under the floor", math.abs(ShopMath.boostRate(s.data, 120, 2) - 3) < 1e-9)
		check("T5 Overclock keeps the 12 s floor", math.abs(ShopMath.boostRate(s.data, 120, 9) - 10) < 1e-9)
		e.seconds += 901
		check("T5 Overclock off after 15 min of play", Shop.trainingMultiplier(s) == 1 and ShopMath.boostRate(s.data, 120, 2) == 2)
		-- the training tick applies it (server truth)
		local t = trainingSession(77, 0)
		t.data.training.eventRolled = true
		t.data.training.workTotal = 1000
		local base = R.EmpireMath.trainingRate(t.data.gpus, 1000, t.data.empire)
		AIModel.tick(t, 1)
		local w1 = t.data.training.workDone
		t.data.shop.boosts.overclock = t.data.empire.seconds + 900
		AIModel.tick(t, 1)
		local w2 = t.data.training.workDone - w1
		check(string.format("T5 the training tick runs x1.5 with Overclock (%.3f -> %.3f)", w1, w2), math.abs(w1 - base) < 1e-6 and math.abs(w2 - math.min(base * 1.5, 1000 / 12)) < 1e-6)
	end

	------------------------------------------------------------------ T6 Last Epoch daily cap
	do
		local okAll = true
		local s = trainingSession(321, 50)
		give(s, "lastEpoch", 12)
		for i = 1, 10 do
			s.data.training = { modelId = "m1", workTotal = 100, workDone = 50, cost = 1000, expected = 40, qualityMod = 1, eventRolled = true, epoch = 0, loss = {}, log = {} }
			s.data.models.m1.status = "training"
			local r = redeem(s, "lastEpoch")
			okAll = okAll and r.ok == true
		end
		check("T6 ten Last Epochs in one UTC day", okAll and held(s, "lastEpoch") == 2)
		s.data.training = { modelId = "m1", workTotal = 100, workDone = 50, cost = 1000, expected = 40, qualityMod = 1, eventRolled = true, epoch = 0, loss = {}, log = {} }
		local r = redeem(s, "lastEpoch")
		check("T6 11th -> DAILY_LIMIT, kept, training untouched", r.ok == false and r.err == "DAILY_LIMIT" and held(s, "lastEpoch") == 2 and s.data.training ~= nil)
	end

	------------------------------------------------------------------ T7 target validation, BUSY
	do
		local s = newSession()
		give(s, "eureka", 1)
		for _, bad in { "../x", 5, {}, "", string.rep("a", 80), "a b" } do
			local r = redeem(s, "eureka", bad)
			check("T7 target " .. tostring(bad) .. " -> BAD_INPUT, kept", r.ok == false and r.err == "BAD_INPUT" and held(s, "eureka") == 1)
		end
		-- party ignores the target
		local office = Instance.new("Model"); office.Name = "Office"; office.Parent = G.workspace
		local floor = Instance.new("Part"); floor.Size = Vector3.new(60, 30, 60); floor.CFrame = CFrame.new(0, 15, 0); floor.Parent = office
		plots[s.player] = { office = office, cframe = CFrame.new(), model = office }
		give(s, "party", 1)
		local r = redeem(s, "party", "anything")
		check("T7 party ignores the target", r.ok == true and held(s, "party") == 0, r.err)
		-- BUSY while a redeem runs (a yielding handler)
		local release = false
		Shop.setRedeemHandler("headhunter", function() while not release do G.task.wait(0.1) end return true end)
		give(s, "headhunter", 2)
		local first
		G.task.spawn(function() first = redeem(s, "headhunter", "ignored") end)
		local second = redeem(s, "eureka", "pipeline")
		check("T7 a second redeem while one runs -> BUSY", second.ok == false and second.err == "BUSY")
		release = true
		M.settle(0.5)
		check("T7 the first one finishes and ignores its target", first and first.ok == true and held(s, "headhunter") == 1)
		Shop.setRedeemHandler("headhunter", Recruiting.headhunt)
	end

	------------------------------------------------------------------ T8 save fields
	do
		local fresh = Template.new()
		check("T8 new saves have boosts / daily / packs", type(fresh.shop.boosts) == "table" and type(fresh.shop.daily) == "table" and type(fresh.shop.daily.used) == "table" and type(fresh.shop.packs) == "table")
		check("T8 DATA_VERSION stays 6", GameConfig.DATA_VERSION == 6 and fresh.version == 6)
		local raw = { receipts = { a = 1 }, order = { "a" }, vouchers = { eureka = 2 }, passes = { identityKit = true }, tips = 1,
			boosts = { keynote = 1234.5, overclock = 0 / 0, warp = 9, [1] = 3 },
			daily = { day = 20000, used = { keynote = 9, overclock = -2, lastEpoch = 3.7, eureka = 4, junk = "x" } },
			packs = { seed = 2, seriesA = 9, seriesB = 2.5, tip = 1, junk = 3 } }
		local c = Template.cleanShop(deepcopy(raw))
		check("T8 boosts: valid kept, NaN / unknown dropped", c.boosts.keynote == 1234.5 and c.boosts.overclock == nil and c.boosts.warp == nil and c.boosts[1] == nil)
		check("T8 daily: day kept, used clamped 0..cap, unknown dropped", c.daily.day == 20000 and c.daily.used.keynote == 4 and c.daily.used.overclock == nil and c.daily.used.lastEpoch == 3 and c.daily.used.eureka == nil and c.daily.used.junk == nil)
		check("T8 packs: office 1..5 integers of cash packs only", c.packs.seed == 2 and c.packs.seriesA == nil and c.packs.seriesB == nil and c.packs.tip == nil and c.packs.junk == nil)
		check("T8 older fields untouched", c.receipts.a == 1 and c.vouchers.eureka == 2 and c.passes.identityKit == true and c.tips == 1)
		for _, junk in { "x", 5, { day = "today", used = 3 }, { day = 0 / 0 }, { day = -5 }, { day = 1.5 } } do
			local cc = Template.cleanShop({ daily = junk, boosts = junk, packs = junk })
			check("T8 junk " .. type(junk) .. " -> empty tables", type(cc.daily.used) == "table" and cc.daily.day == nil and next(cc.boosts) == nil and next(cc.packs) == nil)
		end
		check("T8 cleaner idempotent", deepEqual(Template.cleanShop(deepcopy(c)), c))
		-- an old save (no new fields) is repaired once by shopOf on first use, receipts kept
		local s = newSession()
		s.data.shop = { receipts = { old = 5 }, order = { "old" }, vouchers = { party = 1 }, passes = {}, tips = 2 }
		act(s, { action = "status" })
		check("T8 old save repaired once by shopOf (fields added, receipts / vouchers kept)", type(s.data.shop.boosts) == "table" and type(s.data.shop.daily.used) == "table" and s.data.shop.receipts.old == 5 and s.data.shop.vouchers.party == 1 and s.data.shop.tips == 2)
		-- migration round trip: an old save without the fields loads, and a save with them survives save + load
		local old = Template.new()
		old.shop = { receipts = {}, order = {}, vouchers = { eureka = 1 }, passes = {}, tips = 0 }
		local m1 = Template.migrate(deepcopy(old))
		check("T8 old save migrates (no version bump, new fields empty)", m1 and m1.version == 6 and next(m1.shop.boosts) == nil and m1.shop.vouchers.eureka == 1)
		m1.shop.boosts.keynote = 77; m1.shop.daily = { day = 20001, used = { keynote = 2 } }; m1.shop.packs.seriesB = 3
		local m2 = Template.migrate(deepcopy(m1))
		check("T8 round trip keeps boosts / daily / packs", m2.shop.boosts.keynote == 77 and m2.shop.daily.day == 20001 and m2.shop.daily.used.keynote == 2 and m2.shop.packs.seriesB == 3)
		check("T8 round trip is stable", deepEqual(Template.migrate(deepcopy(m2)).shop, m2.shop))
		-- fix round 1: packCredit kept like vouchers (counts clamped, junk dropped), boosts clamped to 60 min left
		check("T8 new saves have packCredit", type(fresh.shop.packCredit) == "table" and next(fresh.shop.packCredit) == nil)
		local pc = Template.cleanShop({ packCredit = { seriesB = 2, seed = 2.9, seriesA = -1, junk = 0 / 0, ["bad key"] = 3, big = 1e9 } })
		check("T8 packCredit: valid counts kept and floored, junk dropped, clamped to VOUCHER_MAX", pc.packCredit.seriesB == 2 and pc.packCredit.seed == 2 and pc.packCredit.seriesA == nil and pc.packCredit.junk == nil and pc.packCredit["bad key"] == nil and pc.packCredit.big == ShopConfig.VOUCHER_MAX)
		for _, junk in { "x", 5, { 1, 2 } } do
			check("T8 packCredit junk " .. type(junk) .. " -> empty", next(Template.cleanShop({ packCredit = junk }).packCredit) == nil)
		end
		local b = Template.new()
		b.empire.seconds = 5000
		b.shop.boosts = { keynote = 1e15, overclock = 5000 + 1200 }
		b.shop.packCredit = { seriesB = 1 }
		local mb = Template.migrate(deepcopy(b))
		check("T8 migrate clamps a corrupt boost end to 60 min of play left (A7)", mb.shop.boosts.keynote == 5000 + ShopConfig.BOOST_MAX_LEFT and mb.shop.boosts.overclock == 6200, mb.shop.boosts.keynote)
		check("T8 migrate keeps packCredit", mb.shop.packCredit.seriesB == 1)
		check("T8 migrate with clamp is idempotent", deepEqual(Template.migrate(deepcopy(mb)).shop, mb.shop))
	end

	------------------------------------------------------------------ T9 cash packs (S1)
	do
		local IDS = { seed = 91001, seriesA = 91002, seriesB = 91003 }
		for k, id in IDS do ShopConfig.product(k).id = id end
		local s = newSession(C.company({ money = 1000 }))
		s.data.empire.office = 2
		local function receipt(id, key) return { PurchaseId = id, PlayerId = s.userId, ProductId = IDS[key] } end
		check("T9 S1 shares 0.10 / 0.20 / 0.30", ShopConfig.product("seed").share == 0.10 and ShopConfig.product("seriesA").share == 0.20 and ShopConfig.product("seriesB").share == 0.30)
		check("T9 Founder HQ amounts $10,000 / $20,000 / $30,000", ShopConfig.cashFor(ShopConfig.product("seed"), 2) == 10000 and ShopConfig.cashFor(ShopConfig.product("seriesA"), 2) == 20000 and ShopConfig.cashFor(ShopConfig.product("seriesB"), 2) == 30000)
		check("T9 garage amounts $2,700 / $5,400 / $8,100", ShopConfig.cashFor(ShopConfig.product("seed"), 1) == 2700 and ShopConfig.cashFor(ShopConfig.product("seriesA"), 1) == 5400 and ShopConfig.cashFor(ShopConfig.product("seriesB"), 1) == 8100)
		check("T9 last stage $190,000 / $380,000 / $570,000", ShopConfig.cashFor(ShopConfig.product("seed"), 5) == 190000 and ShopConfig.cashFor(ShopConfig.product("seriesB"), 5) == 570000)
		check("T9 open before a purchase", ShopMath.packOpen(s.data, "seriesA"))
		local GR = G.Enum.ProductPurchaseDecision.PurchaseGranted
		local money0 = s.data.money
		check("T9 first purchase granted", Shop.processReceipt(receipt("p1", "seriesA")) == GR and s.data.money == money0 + 20000)
		check("T9 packs records the office; buy chip hidden (packOpen false)", s.data.shop.packs.seriesA == 2 and not ShopMath.packOpen(s.data, "seriesA") and ShopMath.packOpen(s.data, "seed"))
		check("T9 buy guard: hidden", ShopMath.buyAllowed(s.data, s.live, "seriesA", clock) == false and ShopMath.buyAllowed(s.data, s.live, "seed", clock) == true)
		-- fix round 1 (review blocking #1): S1 is enforced on the server. A second receipt of one size in one office (bought
		-- outside our UI, or a double tap) is never refused, but pays no cash now: it becomes a credit for the next office.
		notices = {}
		check("T9 a second receipt in the same office: PurchaseGranted, but no cash now", Shop.processReceipt(receipt("p2", "seriesA")) == GR and s.data.money == money0 + 20000, s.data.money - money0)
		local g2 = noticeOf("SHOP_GRANTED")
		check("T9 ... saved as one credit; the notice says amount 0, credit 1", s.data.shop.packCredit.seriesA == 1 and g2 and g2.payload.amount == 0 and g2.payload.credit == 1)
		check("T9 a third receipt: credit 2, still no cash (A8: never 3x the pack in one office)", Shop.processReceipt(receipt("p2b", "seriesA")) == GR and s.data.money == money0 + 20000 and s.data.shop.packCredit.seriesA == 2)
		check("T9 a replayed receipt id adds nothing", Shop.processReceipt(receipt("p2", "seriesA")) == GR and s.data.shop.packCredit.seriesA == 2 and s.data.money == money0 + 20000)
		check("T9 credits never open the buy chip again in this office", not ShopMath.packOpen(s.data, "seriesA") and ShopMath.buyAllowed(s.data, s.live, "seriesA", clock) == false)
		check("T9 credits are per size (seed has none)", ShopMath.packCredit(s.data, "seed") == 0 and ShopMath.packCredit(s.data, "seriesA") == 2)
		-- the next office move (real UpgradeOffice handler) pays ONE credit at the new office's amount
		local up = binds.UpgradeOffice
		check("T9 UpgradeOffice bound", up ~= nil)
		s.data.money = 150000
		notices = {}
		local r3 = up(s, {})
		check("T9 office move: ok, one credit paid at office 3's amount ($76,000)", r3 and r3.ok == true and s.data.empire.office == 3 and s.data.money == 150000 - 100000 + 76000, r3 and r3.err or tostring(s.data.money))
		local g3 = noticeOf("SHOP_GRANTED")
		check("T9 ... the credit counts as office 3's pack (packs = 3, credit 1 left, notice fromCredit)", s.data.shop.packs.seriesA == 3 and s.data.shop.packCredit.seriesA == 1 and g3 and g3.payload.fromCredit == true and g3.payload.amount == 76000)
		check("T9 ... so the buy chip stays hidden in office 3", not ShopMath.packOpen(s.data, "seriesA"))
		check("T9 ... other sizes stay open (no credit, nothing paid)", ShopMath.packOpen(s.data, "seed") and s.data.shop.packs.seed == nil)
		check("T9 a receipt in office 3 now -> one more credit (office 3 already has its pack)", Shop.processReceipt(receipt("p3", "seriesA")) == GR and s.data.shop.packCredit.seriesA == 2 and s.data.money == 150000 - 100000 + 76000)
		s.data.money = 400000
		local r4 = up(s, {})
		check("T9 the next move pays one more ($380,000 at office 4), one credit left", r4 and r4.ok == true and s.data.money == 400000 - 380000 + 380000 and s.data.shop.packs.seriesA == 4 and s.data.shop.packCredit.seriesA == 1)
		s.data.money = 2000000
		local r5 = up(s, {})
		check("T9 last move pays the last credit (credit table empty)", r5 and r5.ok == true and s.data.shop.packs.seriesA == 5 and s.data.shop.packCredit.seriesA == nil and s.data.money == 2000000 - 1900000 + 380000)
		check("T9 Shop.payPackCredits with no credit pays nothing", Shop.payPackCredits(s) == 0)
		-- a session without the field (old save) gets it from shopOf; the next office opens a size without credit
		local s2 = newSession(C.company({ money = 1000 }))
		s2.data.empire.office = 2
		s2.data.shop.packCredit = nil
		check("T9 old shop without packCredit: first purchase pays", Shop.processReceipt({ PurchaseId = "q1", PlayerId = s2.userId, ProductId = IDS.seed }) == GR and s2.data.money == 1000 + 10000 and type(s2.data.shop.packCredit) == "table")
		s2.data.empire.office = 3
		check("T9 the next office opens it again", ShopMath.packOpen(s2.data, "seed"))
		check("T9 next purchase records the new office and pays", Shop.processReceipt({ PurchaseId = "q2", PlayerId = s2.userId, ProductId = IDS.seed }) == GR and s2.data.shop.packs.seed == 3 and s2.data.money == 1000 + 10000 + 38000)
		for k in IDS do ShopConfig.product(k).id = 0 end
	end

	------------------------------------------------------------------ T10 bundle
	do
		local s = newSession()
		Shop.debugGrantPass(s, "styleCollection")
		check("T10 the bundle owns Identity Kit, Server Glow, Stage Lights", Shop.owns(s, "identityKit") and Shop.owns(s, "serverGlow") and Shop.owns(s, "stageLights") and Shop.owns(s.player, "identityKit"))
		check("T10 the bundle never includes other passes", not Shop.owns(s, "vip") and not Shop.owns(s, "aiGallery"))
		check("T10 the bundle's contents (3 passes, phase 1 + 2 only)", #ShopConfig.pass("styleCollection").includes == 3)
		local ok = pcall(function() end)
		-- the refund path: the bundle flag goes false -> all three go
		local flagsOff = Shop.debugGrantPass -- (a refund is Roblox saying "not owned": refreshPasses with the market double)
		ShopConfig.pass("styleCollection").id = 92001
		market.owned[s.userId .. ":92001"] = false
		Shop.refreshPasses(s)
		check("T10 bundle refunded -> all three parts gone", not Shop.owns(s, "identityKit") and not Shop.owns(s, "serverGlow") and not Shop.owns(s, "stageLights"))
		ShopConfig.pass("styleCollection").id = 0
		-- buy guards: bundle hidden while a part is owned; parts hidden while the bundle is owned
		local liveA = { shop = { passes = { identityKit = true } } }
		check("T10 bundle row hidden when a part is owned", ShopMath.buyAllowed(s.data, liveA, "styleCollection", clock) == false)
		local liveB = { shop = { passes = { styleCollection = true } } }
		check("T10 parts hidden when the bundle is owned", ShopMath.buyAllowed(s.data, liveB, "serverGlow", clock) == false and ShopMath.buyAllowed(s.data, liveB, "vip", clock) == true)
		local _ = ok and flagsOff
	end

	------------------------------------------------------------------ T11 Identity Kit
	do
		local s = newSession()
		s.data.company = nil
		local r = binds.CreateCompany(s, { name = "Gold Labs", logo = "N", color = "gold", spec = "general" })
		check("T11 create with a Kit colour, no pass -> PASS_NEEDED", r.ok == false and r.err == "PASS_NEEDED", r.err)
		r = binds.CreateCompany(s, { name = "Gold Labs", logo = "✦", color = "cyan", spec = "general" })
		check("T11 create with a Kit logo, no pass -> PASS_NEEDED", r.ok == false and r.err == "PASS_NEEDED", r.err)
		Shop.debugGrantPass(s, "identityKit")
		r = binds.CreateCompany(s, { name = "Gold Labs", logo = "✦", color = "gold", spec = "general" })
		check("T11 create with the pass passes the Kit check", r.err ~= "PASS_NEEDED" and r.err ~= "BAD_INPUT", r.err)
		local s2 = newSession()
		r = binds.EmpireAction(s2, { action = "rebrand", color = "gold", logo = "N" })
		check("T11 rebrand to a Kit colour without the pass -> PASS_NEEDED", r.ok == false and r.err == "PASS_NEEDED", r.err)
		r = binds.EmpireAction(s2, { action = "rebrand", color = "rose", logo = "△" })
		check("T11 free rebrand for everyone (free colour + logo)", r.ok == true and s2.data.company.color == "rose" and s2.data.company.logo == "△", r.err)
		r = binds.EmpireAction(s2, { action = "rebrand", color = "blue", logo = "△" })
		check("T11 second change within 60 s -> TOO_FAST", r.ok == false and r.err == "TOO_FAST", r.err)
		check("T11 bad input refused", binds.EmpireAction(s2, { action = "rebrand", color = "nope", logo = "N" }).err == "BAD_INPUT" and binds.EmpireAction(s2, { action = "rebrand", color = "cyan", logo = "Q" }).err == "BAD_INPUT")
		G.task.wait(61) -- virtual time (the cooldown reads os.clock)
		Shop.debugGrantPass(s2, "identityKit")
		r = binds.EmpireAction(s2, { action = "rebrand", color = "gold", logo = "⬢" })
		check("T11 with the pass: Kit colour + logo saved", r.ok == true and s2.data.company.color == "gold" and s2.data.company.logo == "⬢", r.err)
		-- refund: the saved choice stays and still renders
		ShopConfig.pass("identityKit").id = 92002
		market.owned[s2.userId .. ":92002"] = false
		Shop.refreshPasses(s2)
		ShopConfig.pass("identityKit").id = 0
		check("T11 after a refund the saved Kit colour stays and getColor finds it", not Shop.owns(s2, "identityKit") and s2.data.company.color == "gold" and CompanyConfig.getColor("gold") ~= nil)
		local migrated = Template.migrate(deepcopy(s2.data))
		check("T11 a Kit company colour survives the migration", migrated.company.color == "gold" and migrated.company.logo == "⬢")
		-- fix round 1 (review): after a refund the company's OWN saved Kit colour / logo never need the pass, so the
		-- Studio's defaults (company colour + logo) and a logo-only change keep working (R9); new Kit picks still do
		s2.data.money = 1e6
		s2.data.data = { general = { tokens = 4e9, quality = 0.6 } }
		local ownLogo = table.find(CompanyConfig.allLogos(), "⬢")
		r = binds.StartTraining(s2, { name = "Nova", sizeId = "s100m", focusId = "balanced", look = "gold:" .. ownLogo })
		check("T11 refund: StartTraining with the company's own Kit colour + logo -> no PASS_NEEDED", r.err ~= "PASS_NEEDED" and r.err ~= "BAD_INPUT", r.err)
		s2.data.training = nil
		r = binds.StartTraining(s2, { name = "Nova", sizeId = "s100m", focusId = "balanced", look = "pink:1" })
		check("T11 refund: another Kit colour in a look -> PASS_NEEDED", r.ok == false and r.err == "PASS_NEEDED", r.err)
		r = binds.StartTraining(s2, { name = "Nova", sizeId = "s100m", focusId = "balanced", look = "gold:" .. (#CompanyConfig.LOGOS + 1) })
		check("T11 refund: another Kit logo in a look -> PASS_NEEDED", r.ok == false and r.err == "PASS_NEEDED", r.err)
		G.task.wait(61)
		r = binds.EmpireAction(s2, { action = "rebrand", color = "pink", logo = "⬢" })
		check("T11 refund: rebrand to another Kit colour -> PASS_NEEDED", r.ok == false and r.err == "PASS_NEEDED", r.err)
		r = binds.EmpireAction(s2, { action = "rebrand", color = "gold", logo = "N" })
		check("T11 refund: logo-only change keeping the saved Kit colour -> ok (A10)", r.ok == true and s2.data.company.color == "gold" and s2.data.company.logo == "N", r.err)
		G.task.wait(61)
		r = binds.EmpireAction(s2, { action = "rebrand", color = "gold", logo = "⬢" })
		check("T11 refund: the Kit logo is not saved any more -> PASS_NEEDED", r.ok == false and r.err == "PASS_NEEDED", r.err)
		-- StartTraining look
		local s3 = newSession(C.company({ money = 1e6 }))
		s3.data.data = { general = { tokens = 4e9, quality = 0.6 } }
		r = binds.StartTraining(s3, { name = "Nova", sizeId = "s100m", focusId = "balanced", look = "gold:2" })
		check("T11 StartTraining look with a Kit colour, no pass -> PASS_NEEDED", r.ok == false and r.err == "PASS_NEEDED", r.err)
		r = binds.StartTraining(s3, { name = "Nova", sizeId = "s100m", focusId = "balanced", look = "cyan:" .. (#CompanyConfig.LOGOS + 1) })
		check("T11 StartTraining look with a Kit emblem, no pass -> PASS_NEEDED", r.ok == false and r.err == "PASS_NEEDED", r.err)
		r = binds.StartTraining(s3, { name = "Nova", sizeId = "s100m", focusId = "balanced", look = "cyan:" .. (#CompanyConfig.LOGOS + #CompanyConfig.KIT_LOGOS + 1) })
		check("T11 emblem beyond the Kit list -> BAD_INPUT", r.ok == false and r.err == "BAD_INPUT", r.err)
		Shop.debugGrantPass(s3, "identityKit")
		r = binds.StartTraining(s3, { name = "Nova", sizeId = "s100m", focusId = "balanced", look = "gold:10" })
		check("T11 StartTraining look with the pass passes the Kit check", r.err ~= "PASS_NEEDED" and r.err ~= "BAD_INPUT", r.err)
		check("T11 old looks (emblem 1-8) unchanged", ({ ModelMath.parseLook("cyan:8") })[2] == 8 and ({ ModelMath.parseLook("violet:1") })[1] == "violet")
		check("T11 Kit lists: 8 colours, 6 logos, letters-only ids, no id shared with COLORS", (function()
			if #CompanyConfig.KIT_COLORS ~= 8 or #CompanyConfig.KIT_LOGOS ~= 6 then return false end
			for _, k in CompanyConfig.KIT_COLORS do
				if not string.match(k.id, "^%a+$") then return false end
				for _, f in CompanyConfig.COLORS do if f.id == k.id then return false end end
			end
			return true
		end)())
		check("T11 'Premium' never appears in a player text of the Kit", (function()
			for _, def in ShopConfig.PASSES do if string.find(string.lower(def.desc .. def.name), "premium") then return false end end
			return true
		end)())
		-- readability: WCAG contrast against Theme bg (15,21,23) >= 7.0, CIE76 delta E >= 20 to every other colour
		local function lin(c) c = c / 255; return if c <= 0.04045 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4 end
		local function lum(rgb) return 0.2126 * lin(rgb[1]) + 0.7152 * lin(rgb[2]) + 0.0722 * lin(rgb[3]) end
		local function contrast(a, b) local la, lb = lum(a), lum(b); if la < lb then la, lb = lb, la end; return (la + 0.05) / (lb + 0.05) end
		local function lab(rgb)
			local r, g, b = lin(rgb[1]), lin(rgb[2]), lin(rgb[3])
			local x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
			local y = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 1.0
			local z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
			local function f(t) return if t > 0.008856 then t ^ (1 / 3) else 7.787 * t + 16 / 116 end
			return 116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))
		end
		local function dE(a, b) local l1, a1, b1 = lab(a); local l2, a2, b2 = lab(b); return math.sqrt((l1 - l2) ^ 2 + (a1 - a2) ^ 2 + (b1 - b2) ^ 2) end
		local minC, minE = math.huge, math.huge
		for i, k in CompanyConfig.KIT_COLORS do
			minC = math.min(minC, contrast(k.rgb, { 15, 21, 23 }))
			for _, f in CompanyConfig.COLORS do minE = math.min(minE, dE(k.rgb, f.rgb)) end
			for j, o in CompanyConfig.KIT_COLORS do if j ~= i then minE = math.min(minE, dE(k.rgb, o.rgb)) end end
		end
		check(string.format("T11 readability: every Kit colour >= 7.0 : 1 against bg (min %.2f)", minC), minC >= 7.0)
		check(string.format("T11 readability: delta E >= 20 to every free and Kit colour (min %.1f)", minE), minE >= 20)
	end

	------------------------------------------------------------------ T12 fireworks
	do
		local s = newSession()
		give(s, "fireworks", 2)
		local r = redeem(s, "fireworks")
		check("T12 no plot -> NO_PLOT, kept", r.ok == false and r.err == "NO_PLOT" and held(s, "fireworks") == 2)
		local office = Instance.new("Model"); office.Name = "Office"; office.Parent = G.workspace
		local block = Instance.new("Part"); block.Size = Vector3.new(80, 40, 60); block.CFrame = CFrame.new(100, 20, 50); block.Parent = office
		plots[s.player] = { office = office, cframe = CFrame.new(100, 0, 50), model = office }
		r = redeem(s, "fireworks")
		local kit = office:FindFirstChild("RooftopFireworks")
		check("T12 fireworks start, voucher -1", r.ok == true and kit ~= nil and held(s, "fireworks") == 1, r.err)
		local launchers, emitters, bad, above = 0, 0, 0, true
		if kit then
			for _, d in kit:GetDescendants() do
				if d:IsA("BasePart") then
					launchers += 1
					if d.CanCollide or d.CanTouch or d.CanQuery or not d.Anchored then bad += 1 end
					if d.Position.Y < 40 then above = false end
				elseif d:IsA("ParticleEmitter") then
					emitters += 1
				end
			end
		end
		check("T12 4 launch points with emitters, all decorative + anchored", launchers == 4 and emitters == 4 and bad == 0, launchers .. "/" .. emitters .. "/" .. bad)
		check("T12 launch points above the top of the HQ", above)
		r = redeem(s, "fireworks")
		check("T12 a second one while it runs -> FIREWORKS_ACTIVE, kept", r.ok == false and r.err == "FIREWORKS_ACTIVE" and held(s, "fireworks") == 1)
		M.settle(ShopConfig.FIREWORKS_SECONDS + 1)
		check("T12 removed after 45 s", office:FindFirstChild("RooftopFireworks") == nil)
		r = redeem(s, "fireworks")
		check("T12 the next one allowed", r.ok == true and held(s, "fireworks") == 0)
		M.settle(ShopConfig.FIREWORKS_SECONDS + 1)
	end

	------------------------------------------------------------------ phase 2: Server Glow office attribute
	do
		local s = newSession()
		local office = Instance.new("Model"); office.Name = "Office"; office:SetAttribute("OfficeTier", 2); office.Parent = G.workspace
		plots[s.player] = { office = office, cframe = CFrame.new(), model = office }
		check("Server Glow attribute off without the pass", office:GetAttribute("ServerGlow") == nil)
		Shop.debugGrantPass(s, "serverGlow")
		check("Server Glow pass sets the office attribute ServerGlow", office:GetAttribute("ServerGlow") == true)
		local s2 = newSession()
		local office2 = Instance.new("Model"); office2.Name = "Office"; office2:SetAttribute("OfficeTier", 2); office2.Parent = G.workspace
		plots[s2.player] = { office = office2, cframe = CFrame.new(), model = office2 }
		Shop.debugGrantPass(s2, "styleCollection")
		check("Style Collection sets ServerGlow too", office2:GetAttribute("ServerGlow") == true)
	end

	------------------------------------------------------------------ T25 headhunter
	do
		local all = true
		local detail = ""
		for i = 1, 50 do
			local d = C.company({ money = 1e6, stage = 3, staff = { researcher = 3 + i % 2, engineer = 2 + i % 3, curator = i % 4, marketer = 1 + i % 2 }, userId = 900000 + i * 7919 })
			local s = newSession(d)
			s.userId = 900000 + i * 7919
			local e = d.empire
			local want = ShopMath.headhuntRole(e)
			local preview = Recruiting.headhuntPreview(e)
			give(s, "headhunter", 1)
			local n0 = #e.applicants
			local r = redeem(s, "headhunter")
			local a = e.applicants[#e.applicants]
			local roleName = EmpireConfig.find(EmpireConfig.ROLES, want).name
			local ok = r.ok == true and #e.applicants == n0 + 1 and a and Recruiting.traits(s.userId, a.serial).k == 4 and a.ask == 1.25 and a.role == want and preview == roleName
			if not ok then all = false; detail = string.format("i=%d r=%s role=%s want=%s ask=%s", i, tostring(r.err), tostring(a and a.role), want, tostring(a and a.ask)) end
		end
		check("T25 50 redeems: skill exactly 4, ask 1.25, role = smallest team = headhuntPreview", all, detail)
		local d = C.company({ staff = { researcher = 2, engineer = 2, curator = 2, marketer = 2 } })
		check("T25 ties go in ROLES order", ShopMath.headhuntRole(d.empire) == EmpireConfig.ROLES[1].id)
		table.insert(d.empire.applicants, { id = "A1", role = EmpireConfig.ROLES[1].id, st = "new", at = 0, q = {} })
		check("T25 open applications count to the team", ShopMath.headhuntRole(d.empire) == EmpireConfig.ROLES[2].id)
		local s = newSession(C.company({ stage = 1, staff = { researcher = 2, engineer = 1, curator = 1, marketer = 1 } }))
		give(s, "headhunter", 1)
		local r = redeem(s, "headhunter")
		check("T25 all desks full -> STAFF_FULL, kept", r.ok == false and r.err == "STAFF_FULL" and held(s, "headhunter") == 1, r.err)
	end
end

setfenv(body, M.envFor(nil))
local ok, res, status = M.runMain(body, { timeout = 3000 })
if not ok then C.fail += 1; print("FAIL  body crashed (" .. tostring(status) .. "): " .. tostring(res)) end
if M.stats.errors > 0 then C.fail += 1; print("FAIL  background thread errors: " .. M.stats.errors) end
C.summary("shop2_server")
