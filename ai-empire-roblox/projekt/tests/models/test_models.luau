--!nocheck
-- Models package, server side (CORE_SPEC 7, 11.6): product lines and slots per stage, successor migration
-- (90 % of users, replacedBy, old one retired), LINE_LIMIT, ageing (vage), refinement (limit, cost, additive
-- gain, stays live, stat cap), Lab-level effect on new models, MODEL_LIMIT = non-retired models (+ bounded
-- pruning), Recommended price and auto-price (menus, determinism, server = client forecast, manual price =
-- auto off), plus negative checks. Real modules in the mock (AIModelService, PricingService, MarketService,
-- NPCService, ...); the econ package's CORE_SPEC patches are overlaid only where work/src lacks them (load.luau).
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_models && cd tests/models && ../../tools/luau test_models.luau -a [.gen_models] [overlay|plain]
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_models")
local MODE = args[2] or "overlay"
local L = require("./load")(GEN, { overlay = MODE ~= "plain" })
local M = L.M
local P = print
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; P("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end
local function near(a, b, eps) return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (eps or 1e-6) * math.max(1, math.abs(b)) end
local function count(t) local n = 0; for _ in t or {} do n += 1 end; return n end
local function deepcopy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in v do out[k] = deepcopy(x) end
	return out
end
P(string.format("econ overlay: %d CORE_SPEC patches applied in memory (%s mode)", L.applied, MODE))

local function body()
	local G, game = M.G, M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local S = Server.Services
	local RateLimiter = M.require(Server.Lib.RateLimiter)
	RateLimiter.new = function() return { allow = function() return true end, forget = function() end } end
	local Remote = M.require(Server.Lib.Remote)
	local handlers = {}
	local origBind = Remote.bind
	Remote.bind = function(name, limits, handler) handlers[name] = handler; return origBind(name, limits, handler) end
	local fired = {}
	Remote.fire = function(player, name, kind, payload) table.insert(fired, { player = player, kind = kind, payload = payload }) end
	local Template = M.require(Server.Lib.Template)
	local SessionService = M.require(S.SessionService)
	local AIM = M.require(S.AIModelService)
	local Pricing = M.require(S.PricingService)
	local Market = M.require(S.MarketService)
	local NPC = M.require(S.NPCService)
	local ModelMath = M.require(RS.Shared.ModelMath)
	local ModelConfig = M.require(RS.Shared.Config.ModelConfig)
	local MarketConfig = M.require(RS.Shared.Config.MarketConfig)
	local MarketMath = M.require(RS.Shared.MarketMath)
	local PricingMath = M.require(RS.Shared.PricingMath)
	local EmpireMath = M.require(RS.Shared.EmpireMath)
	local GameConfig = M.require(RS.Shared.Config.GameConfig)
	Remote.setup()
	AIM.init()
	Market.init()

	local LINES = { "general", "students", "developers", "businesses" }
	local SLOTS = MarketConfig.PRODUCT_SLOTS
	check("MarketConfig.PRODUCT_SLOTS = {1,2,3,4,4}", SLOTS and table.concat(SLOTS, ",") == "1,2,3,4,4", SLOTS and table.concat(SLOTS, ","))

	local nextUid = 7000
	local function newSession(opt)
		opt = opt or {}
		nextUid += 1
		local uid = opt.userId or nextUid
		local player = { Name = "P" .. uid, DisplayName = "P" .. uid, UserId = uid, Parent = game.Players }
		local d = Template.new()
		d.company = { name = "Co" .. uid, logo = "N", color = "cyan", spec = "general", reputation = opt.reputation or 30, foundedAt = 0 }
		d.empire.office = opt.office or 3
		d.money = opt.money or 1e6
		d.gpus = opt.gpus or { workstation = 4 }
		d.data = { general = { tokens = 6e9, quality = 0.8 }, code = { tokens = 4e9, quality = 0.8 }, math = { tokens = 2e9, quality = 0.8 } }
		local s = { player = player, userId = uid, data = d, live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} },
			dirty = false, lastSent = 0, nextSaveAt = math.huge, saving = false, closed = false, released = false, rng = G.Random.new(opt.seed or 7) }
		if opt.register ~= false then SessionService.all()[player] = s end
		return s
	end
	local function unregister(s) SessionService.all()[s.player] = nil end
	local serial = 0
	local function addModel(s, opt)
		opt = opt or {}
		serial += 1
		local id = opt.id or ("m" .. serial)
		local stats = opt.stats or { reasoning = 60, coding = 60, math = 60, creativity = 60, knowledge = 60, reliability = 60, speed = 76, efficiency = 74 }
		local m = { id = id, name = opt.name or "Nova", version = opt.version or 1, sizeId = opt.sizeId or "s1b", focusId = "balanced",
			status = opt.status or "trained", createdAt = 0, trainedAt = 0, stats = table.clone(stats), overall = ModelMath.overall(stats),
			trainCost = 1000, iterations = opt.iterations, dataUsed = opt.dataUsed or { total = 1e9, quality = 0.8, shares = { general = 1 } } }
		s.data.models[id] = m
		table.insert(s.data.modelOrder, id)
		return m
	end
	local function release(s, m, target, extra)
		local payload = { modelId = m.id, target = target, marketing = 0, auto = false, subPrice = 5, apiPrice = 2 }
		for k, v in extra or {} do payload[k] = v end
		return handlers.ReleaseModel(s, payload)
	end
	-- remote calls that may yield (text filter) run in a coroutine, like the simulator does
	local function call(name, s, payload)
		local r
		local co = coroutine.create(function() r = handlers[name](s, payload or {}) end)
		local ok, err = coroutine.resume(co)
		if not ok then error(name .. ": " .. tostring(err)) end
		local waited = 0
		while coroutine.status(co) ~= "dead" and waited < 10 do M.settle(0.25); waited += 0.25 end
		return r or { ok = false, err = "YIELD" }
	end

	------------------------------------------------------------------ 1. lines and slots per stage
	for stage = 1, 5 do
		local s = newSession({ office = stage, register = false })
		local okCount = 0
		for i, target in LINES do
			local m = addModel(s)
			local before = s.data.money
			local r = release(s, m, target, { marketing = 1000 })
			if r.ok then okCount += 1 end
			if i <= SLOTS[stage] then
				check(`stage {stage}: line {i} ({target}) opens`, r.ok == true, r.err)
			else
				check(`stage {stage}: line {i} -> LINE_LIMIT`, r.ok == false and r.err == "LINE_LIMIT", r.err)
				check(`stage {stage}: LINE_LIMIT spends nothing and keeps the model trained`, s.data.money == before and m.status == "trained" and m.release == nil)
			end
		end
		local _, lines = ModelMath.liveLines(s.data)
		check(`stage {stage}: {SLOTS[stage]} live lines`, okCount == SLOTS[stage] and lines == SLOTS[stage], lines)
		check(`stage {stage}: productSlots`, ModelMath.productSlots(stage) == SLOTS[stage])
	end
	check("productSlots clamps out-of-range stages", ModelMath.productSlots(0) == SLOTS[1] and ModelMath.productSlots(99) == SLOTS[#SLOTS] and ModelMath.productSlots(nil) == SLOTS[1])
	check("lineOf maps targets to segments", ModelMath.lineOf("general") == "consumers" and ModelMath.lineOf("students") == "students" and ModelMath.lineOf("developers") == "developers" and ModelMath.lineOf("businesses") == "businesses" and ModelMath.lineOf(nil) == "consumers")
	check("ModelConfig.LINES mirrors MarketConfig.LINE_OF", (function()
		for _, line in ModelConfig.LINES do if MarketConfig.LINE_OF and MarketConfig.LINE_OF[line.target] ~= line.segment then return false end end
		return #ModelConfig.LINES == 4
	end)())

	------------------------------------------------------------------ 2. successor: 90 % of users, replacedBy, old retired
	do
		local s = newSession({ office = 2, register = false })
		s.data.empire.deals = s.data.empire.deals or { news = {} }
		s.data.empire.deals.news = s.data.empire.deals.news or {}
		local a = addModel(s, { name = "Nova" })
		check("release A into Consumer Chat", release(s, a, "general").ok)
		a.market.users = { consumers = 10000, students = 2000, developers = 500, businesses = 100 }
		a.market.organic = { consumers = 0.05, students = 0.01 }
		a.market.vage = 900
		local b = addModel(s, { name = "Nova", version = 2 })
		table.clear(fired)
		local r = release(s, b, "general")
		check("successor release ok", r.ok == true, r.err)
		check("successor: predecessor retired", a.status == "retired")
		check("successor: replacedBy = new id", a.replacedBy == b.id)
		check("successor: predecessor users moved (not counted twice)", count(a.market.users) == 0 and count(a.market.organic) == 0)
		check("successor: 90 % of each segment's users", near(b.market.users.consumers, 9000) and near(b.market.users.students, 1800) and near(b.market.users.developers, 450) and near(b.market.users.businesses, 90),
			b.market.users.consumers)
		check("successor: word of mouth carried over", near(b.market.organic.consumers, 0.05) and near(b.market.organic.students, 0.01))
		check("successor: version age 0", b.market.vage == 0)
		check("successor: result names the predecessor", r.replacedId == a.id)
		local note = fired[#fired]
		check("successor: MODEL_LIVE notify with replacedId", note and note.kind == "MODEL_LIVE" and note.payload.replacedId == a.id and note.payload.modelId == b.id)
		check("successor: line version 2", ModelMath.lineVersion(s.data, b.id) == 2 and ModelMath.lineVersion(s.data, a.id) == 1)
		check("successor: news line", typeof(s.data.empire.deals.news[1]) == "string" and string.find(s.data.empire.deals.news[1], "replaces Nova v1", 1, true) ~= nil, s.data.empire.deals.news[1])
		local _, lines = ModelMath.liveLines(s.data)
		check("successor: still one live line", lines == 1)
		local c = addModel(s, { name = "Atlas" })
		check("third version of the line", release(s, c, "general").ok and ModelMath.lineVersion(s.data, c.id) == 3 and b.replacedBy == c.id)
		-- negative: another line does not retire the live model
		local d = addModel(s, { name = "Coder" })
		check("second line at stage 2 opens", release(s, d, "developers").ok and c.status == "live" and c.replacedBy == nil)
		local e = addModel(s, { name = "Study" })
		local r3 = release(s, e, "students")
		check("third line at stage 2 -> LINE_LIMIT", r3.ok == false and r3.err == "LINE_LIMIT" and c.status == "live" and d.status == "live")
		check("releaseCheck agrees (UI)", ModelMath.releaseCheck(s.data, e.id, "students").ok == false and ModelMath.releaseCheck(s.data, e.id, "general").replaced[1] == c)
		-- old save: two live models in one line -> both retire, users summed x 0.9
		local s2 = newSession({ office = 5, register = false })
		local x = addModel(s2); local y = addModel(s2)
		for _, m in { x, y } do
			m.status = "live"; m.release = { subPrice = 5, apiPrice = 2, marketing = 0, target = "general", releasedAt = 0 }
			m.market = MarketMath.newMarketState("general", 0); m.market.users = { consumers = 1000 }
		end
		local z = addModel(s2)
		check("old save: release into a doubled line", release(s2, z, "general").ok and x.status == "retired" and y.status == "retired" and x.replacedBy == z.id and y.replacedBy == z.id and near(z.market.users.consumers, 1800))
		-- negative input checks
		local w = addModel(s2)
		check("bad target -> BAD_INPUT", handlers.ReleaseModel(s2, { modelId = w.id, target = "aliens", marketing = 0, auto = false, subPrice = 5, apiPrice = 2 }).err == "BAD_INPUT")
		check("manual release without prices -> BAD_INPUT", handlers.ReleaseModel(s2, { modelId = w.id, target = "students", marketing = 0, auto = false }).err == "BAD_INPUT")
		check("auto must be a boolean", handlers.ReleaseModel(s2, { modelId = w.id, target = "students", marketing = 0, auto = "yes", subPrice = 5, apiPrice = 2 }).err == "BAD_INPUT")
		check("live model cannot be released again", release(s2, z, "students").err == "BAD_MODEL")
		s2.data.money = 100
		local r4 = release(s2, w, "students", { marketing = 5000 })
		check("marketing above cash -> NO_MONEY, nothing changes", r4.err == "NO_MONEY" and w.status == "trained" and s2.data.money == 100)
		s2.data.money = -500
		check("free release works in debt (as before)", release(s2, w, "students").ok and s2.data.money == -500)
	end

	------------------------------------------------------------------ 3. ageing
	check("ageFit(0) = 0", ModelMath.ageFit(0) == 0)
	check("ageFit(1800) = 4 fit points", near(ModelMath.ageFit(1800), 4))
	check("ageFit(3600) = 8 = AGE.maxFit", near(ModelMath.ageFit(3600), 8))
	check("ageFit capped after 3 game days", near(ModelMath.ageFit(99999), 8))
	do
		local s = newSession({ office = 2 })
		local m = addModel(s)
		release(s, m, "general")
		check("vage = 0 at release", m.market.vage == 0)
		for _ = 1, 30 do Market.tick(s, 1) end
		check("vage counts while live (30 s)", near(m.market.vage, 30, 1e-3), m.market.vage)
		check("versionAge reads vage", near(ModelMath.versionAge(m), 30, 1e-3))
		local old = addModel(s, { status = "live" })
		old.release = { subPrice = 5, apiPrice = 2, marketing = 0, target = "general", releasedAt = 0 }
		old.market = MarketMath.newMarketState("general", 0); old.market.age = 500
		check("older live model without vage: versionAge = age", ModelMath.versionAge(old) == 500)
		s.data.models[old.id] = nil; table.remove(s.data.modelOrder, table.find(s.data.modelOrder, old.id))
		-- refinement resets vage (checked in 4)
		unregister(s)
	end

	------------------------------------------------------------------ 4. refinement: limit, cost, gain, stays live, cap
	do
		local s = newSession({ office = 3 })
		local m = addModel(s, { sizeId = "s500m", dataUsed = { total = 1e9, quality = 0.8, shares = { general = 1 } } })
		check("refine model goes live", release(s, m, "general").ok)
		m.market.users = { consumers = 5000 }
		m.market.vage = 1234
		local size = ModelConfig.getSize("s500m")
		local q = ModelMath.dataSummary(s.data.data).quality
		for run = 0, 2 do
			local plan = ModelMath.plan(size, ModelMath.fleet(s.data.gpus), ModelMath.dataSummary(s.data.data))
			local expectCost = math.floor(plan.cost * (1 + 0.5 * run))
			local base = table.clone(m.stats)
			local before = s.data.money
			local r = handlers.ImproveModel(s, { modelId = m.id })
			check(`refine {run + 1}: ok`, r.ok == true, r.err)
			check(`refine {run + 1}: cost = plan x {1 + 0.5 * run}`, before - s.data.money == expectCost, (before - s.data.money) .. " vs " .. expectCost)
			check(`refine {run + 1}: model stays live`, m.status == "live")
			check(`refine {run + 1}: log says serving continues`, string.find(s.data.training.log[1], "Serving continues with the current version", 1, true) ~= nil, s.data.training.log[1])
			check(`refine {run + 1}: work scaled too`, near(s.data.training.workTotal, plan.work * (1 + 0.5 * run)))
			Market.tick(s, 1)
			check(`refine {run + 1}: still serving users while refining`, (m.market.users.consumers or 0) > 1000 and s.live.perModel[m.id] ~= nil)
			AIM.finishNow(s)
			local gain = (1 + 4 * q) * 1 / math.sqrt(1 + run)
			local okGain = true
			for _, stat in ModelConfig.STATS do
				if stat.weight > 0 and stat.id ~= "reliability" then
					local want = math.min(99, math.round((base[stat.id] + gain) * 10) / 10)
					if not near(m.stats[stat.id], want, 1e-9) then okGain = false; P("   ", stat.id, m.stats[stat.id], want) end
				end
			end
			check(`refine {run + 1}: additive gain (1+4q)/sqrt({1 + run})`, okGain)
			check(`refine {run + 1}: iterations {run + 1}, version {run + 2}, vage reset`, m.iterations == run + 1 and m.version == run + 2 and m.market.vage == 0 and m.status == "live")
			ModelMath.addTokens(s.data.data, "general", 2e8, 0.8)
			m.market.vage = 100
		end
		local before = s.data.money
		local r = handlers.ImproveModel(s, { modelId = m.id })
		check("refine 4 -> REFINE_LIMIT", r.ok == false and r.err == "REFINE_LIMIT", r.err)
		check("REFINE_LIMIT spends nothing, no training", s.data.money == before and s.data.training == nil)
		check("refinePlan (UI) agrees", ModelMath.refinePlan(m, { cost = 100, work = 10 }).err == "REFINE_LIMIT" and ModelMath.refinePlan({ iterations = 1 }, { cost = 100, work = 10 }).cost == 150)
		-- stat cap on refinement
		local hi = addModel(s, { sizeId = "s500m", stats = { reasoning = 98, coding = 97.5, math = 99, creativity = 90, knowledge = 98.9, reliability = 95, speed = 84, efficiency = 82 } })
		ModelMath.addTokens(s.data.data, "general", 2e8, 0.8)
		check("refine near the cap ok", handlers.ImproveModel(s, { modelId = hi.id }).ok)
		check("trained model being refined shows status training", hi.status == "training")
		AIM.finishNow(s)
		local maxStat = 0
		for _, stat in ModelConfig.STATS do if stat.weight > 0 then maxStat = math.max(maxStat, hi.stats[stat.id]) end end
		check("refinement caps every core stat at 99", maxStat <= 99 and hi.stats.reasoning == 99 and hi.stats.coding == 99, maxStat)
		check("overall <= 99", hi.overall <= 99 and hi.status == "trained")
		check("capStats", (function() local st, ov = ModelMath.capStats({ reasoning = 120, coding = 50, math = 99.5, creativity = 1, knowledge = 100, reliability = 140, speed = 150 }); return st.reasoning == 99 and st.math == 99 and st.knowledge == 99 and st.reliability == 99 and st.speed == 150 and ov <= 99 end)())
		-- retired while refining stays retired
		local r2 = addModel(s, { sizeId = "s500m" })
		release(s, r2, "students")
		ModelMath.addTokens(s.data.data, "general", 2e8, 0.8)
		check("refine a live model", handlers.ImproveModel(s, { modelId = r2.id }).ok and r2.status == "live")
		check("retire it while refining", handlers.RetireModel(s, { modelId = r2.id }).ok)
		AIM.finishNow(s)
		check("finish keeps a retired model retired", r2.status == "retired")
		-- old save: refinement that paused serving goes live again when its line is free
		local o = addModel(s, { sizeId = "s500m" })
		release(s, o, "developers")
		o.status = "training"
		s.data.training = { modelId = o.id, refinement = true, resumeLive = true, baseStats = table.clone(o.stats), workTotal = 1e9, workDone = 0, cost = 1, expected = 50, qualityMod = 1, eventRolled = true, epoch = 0, loss = { 3 }, log = {} }
		AIM.tick(s, 1)
		check("old paused refinement serves again (line free)", o.status == "live")
		s.data.training = nil
		unregister(s)
	end

	------------------------------------------------------------------ 5. Lab levels reach new models (+1 core stat per level)
	do
		local function trainOnce(labLevel)
			local s = newSession({ office = 3, register = false, seed = 99 })
			s.data.empire.labLevel = labLevel
			s.data.gpus = { workstation = 4 }
			local r = call("StartTraining", s, { name = "Lab", sizeId = "s500m", focusId = "balanced", recipeId = "steady" })
			if not r.ok then return nil, r.err end
			AIM.finishNow(s)
			return s.data.models[r.modelId]
		end
		local m0, e0 = trainOnce(0)
		local m3, e3 = trainOnce(3)
		check("train with Lab level 0 and 3", m0 ~= nil and m3 ~= nil, tostring(e0) .. "/" .. tostring(e3))
		if m0 and m3 then
			local okLab = true
			for _, stat in ModelConfig.STATS do
				if stat.weight > 0 and m3.stats[stat.id] < 99 then
					if not near(m3.stats[stat.id] - m0.stats[stat.id], 3, 1e-6) then okLab = false; P("   lab", stat.id, m0.stats[stat.id], m3.stats[stat.id]) end
				end
			end
			check("Lab level 3 = +3 on every core stat of a new model", okLab)
			check("bonuses.core counts labLevel", near(EmpireMath.bonuses({ research = {}, employees = {}, office = 3, labLevel = 2, staffProfiles = {}, infrastructure = { cooling = 1, trainingShare = 0.7 } }).core
				- EmpireMath.bonuses({ research = {}, employees = {}, office = 3, labLevel = 0, staffProfiles = {}, infrastructure = { cooling = 1, trainingShare = 0.7 } }).core, 2))
		end
		-- new models are capped too, even with a huge core bonus
		local s = newSession({ office = 5, register = false, seed = 5 })
		s.data.empire.labLevel = 10
		s.data.empire.research = { architecture = true, frontier = true, alignment = true }
		s.data.gpus = { datacenter = 2 }
		s.data.data = { general = { tokens = 5e10, quality = 1 }, code = { tokens = 5e10, quality = 1 }, math = { tokens = 5e10, quality = 1 } }
		local r = call("StartTraining", s, { name = "Max", sizeId = "s7b", focusId = "coding", recipeId = "steady" })
		check("7B training with every bonus", r.ok == true, r.err)
		if r.ok then
			AIM.finishNow(s)
			local m = s.data.models[r.modelId]
			local maxStat = 0
			for _, stat in ModelConfig.STATS do if stat.weight > 0 then maxStat = math.max(maxStat, m.stats[stat.id]) end end
			check("new model: every core stat <= 99", maxStat <= 99 and maxStat >= 98, maxStat)
			check("new model: overall <= 99", m.overall <= 99)
		end
	end

	------------------------------------------------------------------ 6. MODEL_LIMIT counts non-retired models; bounded pruning
	do
		local limit = GameConfig.MODEL_LIMIT or 80
		check("GameConfig.MODEL_LIMIT = 80", limit == 80, GameConfig.MODEL_LIMIT)
		local s = newSession({ office = 3, register = false })
		for i = 1, 79 do addModel(s, { status = "trained" }) end
		for i = 1, 30 do addModel(s, { status = "retired" }) end
		local r = call("StartTraining", s, { name = "Next", sizeId = "s100m", focusId = "balanced" })
		check("79 active + 30 retired: training allowed", r.ok == true, r.err)
		AIM.finishNow(s)
		local r2 = call("StartTraining", s, { name = "Again", sizeId = "s100m", focusId = "balanced" })
		check("80 active -> MODEL_LIMIT", r2.ok == false and r2.err == "MODEL_LIMIT", r2.err)
		check("activeModels counts non-retired", ModelMath.activeModels(s.data) == 80)
		-- pruning: 100 retired, keep 80; protected: studio source and the running training; chains re-linked
		local p = newSession({ office = 3, register = false })
		local ids = {}
		for i = 1, 100 do ids[i] = addModel(p, { status = "retired", id = "r" .. i }).id end
		local liveM = addModel(p, { id = "liveX" }); release(p, liveM, "general")
		p.data.models.r30.replacedBy = "r10"; p.data.models.r10.replacedBy = "r11"; p.data.models.r11.replacedBy = "r40"
		p.data.models.r50.replacedBy = "r12"; p.data.models.r12.replacedBy = "liveX"
		p.data.empire.projects = { pj = { id = "pj", sourceId = "r1" } }
		local r3 = call("StartTraining", p, { name = "Fresh", sizeId = "s100m", focusId = "balanced" })
		check("training after 100 retired", r3.ok == true, r3.err)
		local retired = 0
		for _, id in p.data.modelOrder do if p.data.models[id] and p.data.models[id].status == "retired" then retired += 1 end end
		check("pruned to RETIRED_KEEP retired models", retired == ModelConfig.RETIRED_KEEP, retired)
		check("studio source kept", p.data.models.r1 ~= nil)
		check("oldest unprotected removed (r2..r21)", p.data.models.r2 == nil and p.data.models.r21 == nil and p.data.models.r22 ~= nil)
		check("chain re-linked around removed models", p.data.models.r30.replacedBy == "r40" and p.data.models.r50.replacedBy == "liveX", tostring(p.data.models.r30.replacedBy) .. "/" .. tostring(p.data.models.r50.replacedBy))
		check("modelOrder matches models", (function()
			local n = 0
			for _, id in p.data.modelOrder do if not p.data.models[id] then return false end; n += 1 end
			return n == count(p.data.models)
		end)())
		check("live model and new training untouched", p.data.models.liveX.status == "live" and p.data.models[r3.modelId] ~= nil)
	end

	------------------------------------------------------------------ 7. version numbers never repeat after a refinement
	do
		local s = newSession({ office = 3, register = false })
		local r = call("StartTraining", s, { name = "Nova", sizeId = "s100m", focusId = "balanced" })
		AIM.finishNow(s)
		local first = s.data.models[r.modelId]
		ModelMath.addTokens(s.data.data, "general", 2e8, 0.8)
		handlers.ImproveModel(s, { modelId = first.id }); AIM.finishNow(s)
		check("refined Nova v1 -> v2", first.version == 2)
		local r2 = call("StartTraining", s, { name = "nova", sizeId = "s100m", focusId = "balanced" })
		check("next Nova is v3 (not a second v2)", r2.ok and s.data.models[r2.modelId].version == 3)
		AIM.finishNow(s)
	end

	------------------------------------------------------------------ 8. Recommended price: menu, determinism, server = client
	NPC.init()
	local world = newSession({ office = 3, reputation = 40, userId = 7801 })
	local rival = newSession({ office = 3, reputation = 50, userId = 7802 })
	do
		local rm = addModel(rival, { stats = { reasoning = 66, coding = 70, math = 60, creativity = 55, knowledge = 60, reliability = 64, speed = 76, efficiency = 74 } })
		release(rival, rm, "developers")
		rm.market.vage = 2000
		local dev = addModel(world, { name = "Coder" })
		release(world, dev, "developers", { subPrice = 10, apiPrice = 3 })
		for _ = 1, 20 do Market.tick(world, 5); Market.tick(rival, 5) end
	end
	local cand = addModel(world, { name = "Chat", stats = { reasoning = 62, coding = 50, math = 50, creativity = 70, knowledge = 68, reliability = 60, speed = 76, efficiency = 74 } })
	do
		local c1 = Pricing.recommend(world, cand, "general", 5000)
		local c2 = Pricing.recommend(world, cand, "general", 5000)
		check("recommended: deterministic", c1.sub == c2.sub and c1.api == c2.api and c1.profit == c2.profit)
		check("recommended: on the menu", table.find({ 5, 10 }, c1.sub) ~= nil and table.find({ 1, 2, 3, 4 }, c1.api) ~= nil, c1.sub .. "/" .. c1.api)
		-- brute force over the menu with the same context
		local ctx = Pricing.context(world)
		local market = PricingMath.releaseMarket("general", 5000, ModelMath.releaseCheck(world.data, cand.id, "general").replaced)
		local bestV, bestP = -math.huge, nil
		for _, sub in ModelConfig.PRICING.subs do
			for _, api in ModelConfig.PRICING.apis do
				local e = { id = cand.id, stats = cand.stats, sizeId = cand.sizeId, subPrice = sub, apiPrice = api, market = PricingMath.cloneMarket(market), target = "general" }
				local v = PricingMath.profit(ctx, e, ModelConfig.PRICING.releaseHorizon)
				if v > bestV then bestV = v; bestP = { sub, api } end
			end
		end
		check("recommended = brute-force best over 30 min", bestP[1] == c1.sub and bestP[2] == c1.api and near(bestV, c1.profit, 1e-9))
		check("rivals: NPC labs + the other company, flagged", (function()
			local npc, players = 0, 0
			for _, e in ctx.rivals do if e.player then players += 1 else npc += 1 end end
			return npc >= 3 and players == 1 and ctx.rivals[1].company <= ctx.rivals[#ctx.rivals].company
		end)())
		check("context: stage, capacity and reach cap from CompanyOps", ctx.opts.stage == 3 and type(ctx.opts.capacity) == "number" and type(ctx.opts.reachCap) == "number", tostring(ctx.opts.capacity))
		-- the client computes the same price from the replicated offers (with target/npc/vage, request 1)
		local offers = {}
		for _, sess in { world, rival, table.unpack(NPC.sessions) } do
			for _, id in sess.data.modelOrder do
				local m = sess.data.models[id]
				if m.status == "live" and m.release then
					table.insert(offers, { providerId = sess.userId, id = id, stats = m.stats, sub = m.release.subPrice, api = m.release.apiPrice, overall = m.overall,
						target = m.release.target, npc = sess.isNPC == true, vage = m.market.vage })
				end
			end
		end
		table.sort(offers, function(a, b) return a.overall > b.overall end) -- the server's offer order, not ours
		local own = {}
		for id in world.data.models do own[id] = true end
		local clientCtx = PricingMath.context(world.data, PricingMath.rivalsFromOffers(offers, own), {})
		local cc = PricingMath.recommend(clientCtx, world.data, cand, "general", 5000)
		check("client forecast = server forecast (same price, same profit)", cc.sub == c1.sub and cc.api == c1.api and cc.profit == c1.profit, cc.profit .. " vs " .. c1.profit)
		-- release with auto: the server applies exactly the Recommended price
		local money = world.data.money
		local r = call("ReleaseModel", world, { modelId = cand.id, target = "general", marketing = 5000 })
		check("release (auto default): ok", r.ok == true, r.err)
		check("release (auto): Recommended price applied", cand.release.subPrice == c1.sub and cand.release.apiPrice == c1.api and r.subPrice == c1.sub)
		check("release (auto): release.auto = true", cand.release.auto == true)
		check("release (auto): marketing paid", world.data.money == money - 5000)
		check("recommendedMarketing: <= $5,000 above the reserve", PricingMath.recommendedMarketing(1e6, 10) == 5000 and PricingMath.recommendedMarketing(4000, 10) == 2500 and PricingMath.recommendedMarketing(1000, 10) == 0 and PricingMath.recommendedMarketing(20000, 100) == 5000 and PricingMath.recommendedMarketing(14000, 100) == 2000)
		local manual = addModel(world, { name = "Study" })
		local r2 = release(world, manual, "students", { subPrice = 20, apiPrice = 7.5 })
		check("manual release keeps the player's price, auto off", r2.ok and manual.release.subPrice == 20 and manual.release.apiPrice == 7.5 and manual.release.auto == false)
	end

	------------------------------------------------------------------ 9. auto-price: every 300 s, snapshot jobs, frame worker
	do
		local St = Pricing.stats
		-- one simulation second: AIModelService.tick schedules; the Heartbeat worker (Pricing.frame) does the work
		local function tick(n, noWork)
			for _ = 1, n do
				M.Sched.now += 1
				AIM.tick(world, 1)
				if not noWork then Pricing.frame(10) end
			end
		end
		local dev, chat, study
		for _, id in world.data.modelOrder do
			local m = world.data.models[id]
			if m.status == "live" then
				if m.name == "Coder" then dev = m elseif m.name == "Chat" then chat = m elseif m.name == "Study" then study = m end
			end
		end
		dev.release.auto = true
		dev.release.subPrice, dev.release.apiPrice = 20, 9 -- off the menu: auto-price must move it
		-- determinism of one forecast: same state -> same choice; the real market state is untouched
		local snapshot = deepcopy(dev.market)
		local a = PricingMath.best(Pricing.context(world), dev, "developers", PricingMath.cloneMarket(dev.market), ModelConfig.PRICING.autoHorizon)
		local b = PricingMath.best(Pricing.context(world), dev, "developers", PricingMath.cloneMarket(dev.market), ModelConfig.PRICING.autoHorizon)
		check("auto-price forecast deterministic", a.sub == b.sub and a.api == b.api and a.profit == b.profit)
		check("forecast never touches the real market state", dev.market.users.developers == snapshot.users.developers and dev.market.vage == snapshot.vage and dev.market.age == snapshot.age)
		local ctxA = Pricing.context(world)
		Market.tick(world, 5)
		check("context is a snapshot (own markets copied)", (function()
			for _, e in ctxA.own do if e.id == dev.id then return e.market ~= dev.market and e.market.users ~= dev.market.users end end
			return false
		end)())
		local cc = PricingMath.best(Pricing.context(world), chat, "general", PricingMath.cloneMarket(chat.market), ModelConfig.PRICING.autoHorizon)
		-- first cycle PRICING.autoFirst (150) s after the company starts ticking (corefix: the design bot's phase,
		-- CORE_SPEC 9; the econ build ran it at 15-44 s, before the first release of a new company)
		local runs0 = St.runs
		local firstAt = nil
		local jobsFor = {}
		for t = 1, 180 do
			M.Sched.now += 1
			AIM.tick(world, 1)
			local job = Pricing.job(world)
			if job then jobsFor[job.modelId] = true; if not firstAt then firstAt = t end end
			Pricing.frame(10)
		end
		check("first auto-price cycle 150 s after the first tick (PRICING.autoFirst)", ModelConfig.PRICING.autoFirst == 150 and firstAt ~= nil and firstAt >= 149 and firstAt <= 151, firstAt)
		check("a cycle prices each auto model once (8 menu prices each)", St.runs - runs0 == 2 * #PricingMath.MENU, St.runs - runs0)
		check("manual-price model is skipped", jobsFor[dev.id] and jobsFor[chat.id] and not jobsFor[study.id])
		check("auto-price applied the forecast-best price", dev.release.subPrice == a.sub and dev.release.apiPrice == a.api, dev.release.subPrice .. "/" .. dev.release.apiPrice .. " vs " .. a.sub .. "/" .. a.api)
		check("auto-price: chat at its forecast-best price", chat.release.subPrice == cc.sub and chat.release.apiPrice == cc.api)
		local note = world.live.pricing and world.live.pricing[dev.id]
		check("auto-price wrote a one-line reason", note ~= nil and type(note.note) == "string" and #note.note > 10 and #note.note <= 120, note and note.note)
		check("reason names the line", note ~= nil and string.find(note.note, "Developer API", 1, true) ~= nil, note and note.note)
		-- no further work until the next 300 s cycle
		local e1 = St.runs
		tick(200)
		check("no forecast between cycles", St.runs == e1)
		tick(120)
		check("next cycle after 300 s", St.runs == e1 + 2 * #PricingMath.MENU, St.runs - e1)
		-- the worker: a job runs over several frames, each within the CPU budget, and its result depends only on
		-- the snapshot taken when it started (the real market keeps ticking in between)
		do
			dev.release.subPrice, dev.release.apiPrice = 20, 9
			AIM.setAutoPrice(world, dev.id, false); tick(1, true)
			AIM.setAutoPrice(world, dev.id, true); tick(1, true)
			local job = Pricing.job(world)
			check("worker: job started from the tick", job ~= nil and job.modelId == dev.id)
			local expect = PricingMath.best(job.ctx, job.product, job.target, job.market, ModelConfig.PRICING.autoHorizon)
			local frames, ticks, times = 0, 0, {}
			local budget = ModelConfig.PRICING.frameBudget
			while Pricing.job(world) and frames < 5000 do
				local t0 = os.clock()
				ticks += Pricing.frame()
				table.insert(times, os.clock() - t0)
				frames += 1
				Market.tick(world, 1) -- the live market moves on between frames
			end
			check("worker: one job takes several frames", frames >= 2 and ticks == #PricingMath.MENU * math.floor(ModelConfig.PRICING.autoHorizon / ModelConfig.PRICING.step), frames .. " frames, " .. ticks .. " ticks")
			check("worker: result = synchronous forecast of the snapshot", dev.release.subPrice == expect.sub and dev.release.apiPrice == expect.api, dev.release.subPrice .. "/" .. dev.release.apiPrice .. " vs " .. expect.sub .. "/" .. expect.api)
			check("worker: idle frame does nothing", Pricing.frame() == 0)
		end
		-- two companies share the worker round-robin; a closed session's job is dropped
		do
			local other = newSession({ office = 3, userId = 7803 })
			local om = addModel(other, { name = "Other" })
			release(other, om, "businesses", { auto = true })
			om.release.subPrice, om.release.apiPrice = 20, 9
			AIM.setAutoPrice(world, dev.id, false); AIM.setAutoPrice(other, om.id, false)
			M.Sched.now += 1; AIM.tick(world, 1); AIM.tick(other, 1)
			AIM.setAutoPrice(world, dev.id, true); AIM.setAutoPrice(other, om.id, true)
			M.Sched.now += 1; AIM.tick(world, 1); AIM.tick(other, 1)
			local jw, jo = Pricing.job(world), Pricing.job(other)
			check("two companies: both jobs started", jw ~= nil and jo ~= nil)
			local doneW, doneO, frames = nil, nil, 0
			while (Pricing.job(world) or Pricing.job(other)) and frames < 5000 do
				frames += 1
				Pricing.frame(0) -- budget 0: exactly one market tick per frame, jobs served round-robin
				if not Pricing.job(world) and not doneW then doneW = frames end
				if not Pricing.job(other) and not doneO then doneO = frames end
			end
			check("two companies: served round-robin (both finish together)", doneW ~= nil and doneO ~= nil and math.abs(doneW - doneO) <= 1, tostring(doneW) .. "/" .. tostring(doneO))
			check("two companies: other company re-priced", om.release.apiPrice <= 4)
			AIM.setAutoPrice(other, om.id, false); M.Sched.now += 1; AIM.tick(other, 1)
			AIM.setAutoPrice(other, om.id, true); M.Sched.now += 1; AIM.tick(other, 1)
			check("closing session: job exists", Pricing.job(other) ~= nil)
			other.closed = true
			Pricing.frame(10)
			check("closed session: job dropped", Pricing.job(other) == nil)
			unregister(other)
			tick(3)
		end
		-- manual price -> auto off, auto-price leaves it alone
		local r = handlers.UpdatePricing(world, { modelId = dev.id, subPrice = 20, apiPrice = 9 })
		check("manual price: ok and auto off", r.ok and dev.release.auto == false and dev.release.apiPrice == 9)
		tick(320)
		check("auto-price never overrides a manual price", dev.release.subPrice == 20 and dev.release.apiPrice == 9)
		-- switching auto on re-prices right away (a job starts on the next tick)
		local r2 = AIM.setAutoPrice(world, dev.id, true)
		tick(1, true)
		local job = Pricing.job(world)
		check("setAutoPrice(true): job starts on the next tick", r2.ok and dev.release.auto == true and job ~= nil and job.modelId == dev.id)
		tick(2)
		check("setAutoPrice(true): re-priced within a few ticks", dev.release.apiPrice <= 4 and Pricing.job(world) == nil)
		-- switching to manual while a job runs cancels it
		AIM.setAutoPrice(world, chat.id, true); tick(1, true)
		Pricing.frame(0)
		local subBefore, apiBefore = chat.release.subPrice, chat.release.apiPrice
		handlers.UpdatePricing(world, { modelId = chat.id, subPrice = 20, apiPrice = 7 })
		tick(2)
		check("manual price during a job wins", chat.release.subPrice == 20 and chat.release.apiPrice == 7 and Pricing.job(world) == nil, subBefore .. "/" .. apiBefore)
		local r3 = handlers.UpdatePricing(world, { modelId = dev.id, auto = false })
		check("UpdatePricing {auto=false} toggles only", r3.ok and dev.release.auto == false and dev.release.apiPrice <= 4)
		tick(1)
		dev.release.auto = true -- e.g. flipped by EmpireAction
		tick(1, true)
		check("auto flag flipped elsewhere (EmpireAction) is noticed", Pricing.job(world) ~= nil and Pricing.job(world).modelId == dev.id)
		tick(2)
		check("UpdatePricing {auto='x'} -> BAD_INPUT", handlers.UpdatePricing(world, { modelId = dev.id, auto = "x" }).err == "BAD_INPUT")
		check("setAutoPrice on a trained model -> BAD_MODEL", AIM.setAutoPrice(world, addModel(world).id, true).err == "BAD_MODEL")
		check("setAutoPrice with unknown id -> BAD_MODEL", AIM.setAutoPrice(world, "nope", true).err == "BAD_MODEL" and AIM.setAutoPrice(world, 5, true).err == "BAD_MODEL")
		check("explain text", PricingMath.explain("general", 5, 2, 10, 2, 97, 100) == "Servers 97 % full → Consumer Chat price raised to $10", PricingMath.explain("general", 5, 2, 10, 2, 97, 100))
		check("explain text: API line lowered", PricingMath.explain("developers", 5, 3, 5, 1, 10, 100) == "Developer API price lowered to $1 per 1M tokens to win more users", PricingMath.explain("developers", 5, 3, 5, 1, 10, 100))
	end

	------------------------------------------------------------------ 10. forecast step 15 s picks what 5 s picks; cost with a full server
	do
		local LINES4 = { "general", "students", "developers", "businesses" }
		local full = {}
		for i = 1, 11 do
			local s = newSession({ office = 5, reputation = 30 + i * 3, userId = 7900 + i })
			s.data.gpus = { datacenter = 4 }
			for j, t in LINES4 do
				local m = addModel(s, { name = "R" .. j, sizeId = "s3b", stats = { reasoning = 55 + i, coding = 50 + j * 4, math = 58, creativity = 60 + (i % 3) * 4, knowledge = 62, reliability = 64, speed = 64, efficiency = 62 } })
				release(s, m, t, { subPrice = (i % 2 == 0) and 10 or 5, apiPrice = 1 + (i + j) % 4 })
				m.market.vage = 300 * i
			end
			table.insert(full, s)
		end
		for _ = 1, 12 do for _, s in full do Market.tick(s, 5) end; Market.tick(world, 5) end
		local agree, total = 0, 0
		local step = ModelConfig.PRICING.step
		local probes = { world, full[2], full[5], full[9] }
		for _, s in probes do
			for _, id in s.data.modelOrder do
				local m = s.data.models[id]
				if m.status == "live" and m.release then
					local ctx = Pricing.context(s)
					ModelConfig.PRICING.step = 5
					local c5 = PricingMath.best(ctx, m, m.release.target, PricingMath.cloneMarket(m.market), ModelConfig.PRICING.autoHorizon)
					ModelConfig.PRICING.step = 15
					local c15 = PricingMath.best(ctx, m, m.release.target, PricingMath.cloneMarket(m.market), ModelConfig.PRICING.autoHorizon)
					total += 1
					if c5.sub == c15.sub and c5.api == c15.api then agree += 1 else P(string.format("   step differs: %s %s 5s=%d/%d 15s=%d/%d", s.data.company.name, m.release.target, c5.sub, c5.api, c15.sub, c15.api)) end
				end
			end
		end
		ModelConfig.PRICING.step = step
		P(string.format("step 15 s vs 5 s: same menu price for %d of %d live models", agree, total))
		check("forecast step 15 s picks the 5 s price (>= 90 % of models)", agree >= math.ceil(total * 0.9), agree .. "/" .. total)
		local ctx = Pricing.context(world)
		local dev
		for _, id in world.data.modelOrder do local m = world.data.models[id]; if m.status == "live" then dev = m; break end end
		local t0 = os.clock()
		PricingMath.tryPrice(ctx, dev, dev.release.target, dev.market, 5, 2, ModelConfig.PRICING.autoHorizon)
		local tStep = os.clock() - t0
		local succ = addModel(world, { name = "Chat", version = 9 })
		t0 = os.clock()
		Pricing.recommend(world, succ, "general", 0)
		local tRec = os.clock() - t0
		P(string.format("perf (12 companies, %d rival models): one auto-price step %.1f ms; Recommended %.0f ms CPU (spread over frames at release)",
			#ctx.rivals, tStep * 1000, tRec * 1000))
		check("one menu price (60 market ticks) < 100 ms with 12 full companies", tStep < 0.1, tStep)
		-- the worker keeps every frame within its CPU budget on a full server (a single market tick is the unit)
		do
			dev.release.auto = false; M.Sched.now += 1; AIM.tick(world, 1)
			dev.release.auto = true; M.Sched.now += 1; AIM.tick(world, 1)
			local worst, frames = 0, 0
			local times = {}
			while Pricing.job(world) and frames < 20000 do
				local t0 = os.clock()
				Pricing.frame()
				local dt = os.clock() - t0
				worst = math.max(worst, dt)
				frames += 1
				table.insert(times, dt)
			end
			local tick1 = tStep / 60
			table.sort(times)
			local median = times[math.max(1, math.ceil(#times * 0.5))] or 0
			P(string.format("worker on a full server (wall clock, shared machine): %d frames for one auto-price job, median %.2f ms, worst %.2f ms (budget %.1f ms, one market tick %.2f ms)",
				frames, median * 1000, worst * 1000, ModelConfig.PRICING.frameBudget * 1000, tick1 * 1000))
			check("full server: one job spread over many frames", frames >= 10, frames)
			-- the budget rule itself, deterministic: a fake clock that advances 1/4096 s (~0.24 ms, the measured cost of
			-- one tick with 12 full companies; exact in binary) per market tick -> every frame stops at the first tick
			-- that reaches the budget
			do
				local fake = 0
				local realOs = M.G.os
				local realTick = MarketMath.tick
				M.G.os = setmetatable({ clock = function() return fake end }, { __index = realOs })
				local unit = 1 / 4096
				MarketMath.tick = function(...) fake += unit; return realTick(...) end
				dev.release.auto = false; M.Sched.now += 1; AIM.tick(world, 1)
				dev.release.auto = true; M.Sched.now += 1; AIM.tick(world, 1)
				local want = math.ceil(ModelConfig.PRICING.frameBudget / unit)
				local okFrames, n, last = true, 0, 0
				while Pricing.job(world) and n < 20000 do
					last = Pricing.frame()
					n += 1
					if Pricing.job(world) and last ~= want then okFrames = false end
				end
				M.G.os = realOs
				MarketMath.tick = realTick
				check(string.format("worker budget rule: %d market ticks (= %.2f ms) per frame until the job is done", want, want * unit * 1000), okFrames and n > 1 and last >= 1 and last <= want, n .. " frames, last " .. last)
			end
		end
		local c
		-- corefix: the slicer's own pauses are counted and timed IN THIS RUN (a separately timed run made the
		-- check flaky under machine load): yields >= half of (CPU used inside the slices / releaseBudget)
		local realSlicer = PricingMath.slicer
		local yields, sliceCpu, sliceMax = 0, 0, 0
		PricingMath.slicer = function(budget, yieldFn)
			local mark = os.clock()
			local inner = realSlicer(budget, function()
				local used = os.clock() - mark
				sliceCpu += used
				sliceMax = math.max(sliceMax, used)
				yields += 1
				yieldFn()
				mark = os.clock()
			end)
			return inner
		end
		local co = coroutine.create(function() c = handlers.ReleaseModel(world, { modelId = succ.id, target = "general", marketing = 0 }) end)
		coroutine.resume(co)
		local yielded = coroutine.status(co) ~= "dead"
		local frames = 0
		while coroutine.status(co) ~= "dead" and frames < 400 do M.settle(1 / 60); frames += 1 end
		PricingMath.slicer = realSlicer
		check("release with Recommended price in a full server (successor)", c ~= nil and c.ok == true and succ.status == "live" and succ.release.auto == true, c and c.err)
		local want = math.max(2, math.floor(sliceCpu / ModelConfig.PRICING.releaseBudget * 0.5))
		local spreadDetail = string.format("%d yields over %d frames, want >= %d (%.0f ms in slices, longest %.1f ms; separate run %.0f ms)", yields, frames, want, sliceCpu * 1000, sliceMax * 1000, tRec * 1000)
		P("   release spread: " .. spreadDetail)
		check("Recommended at release is spread over frames (CPU budget per frame)", yielded and yields >= want and frames >= yields, spreadDetail)
	end
end

setfenv(body, M.envFor(nil))
local ok, res = M.runMain(body, { timeout = 600 })
if not ok then failc += 1; P("FAIL  body crashed: " .. tostring(res)) end
if M.stats.errors > 0 then failc += 1; P("FAIL  background errors: " .. M.stats.errors) end
P(string.format("models: %d passed, %d failed", pass, failc))
