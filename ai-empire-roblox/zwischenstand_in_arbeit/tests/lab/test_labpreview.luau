--!nocheck
-- Lab package: LabPreview (the Model Studio's maths) against the REAL server handlers in the mock (LAB_SPEC 9.1),
-- the recommended preset = today's numbers (economy guard), the S1 reveal payload and the server validation of
-- the new optional StartTraining fields (look, target).
-- Run: cd tests/lab && ../../tools/luau test_labpreview.luau -a .gen_lab
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_lab")
local M = require("../../harness/mock")
local setup = require("./lab_setup")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local P = print
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; P("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end
local function near(a, b, eps) return typeof(a) == "number" and typeof(b) == "number" and math.abs(a - b) <= (eps or 1e-9) end

local function deepcopy(v, seen)
	if typeof(v) ~= "table" then return v end
	seen = seen or {}
	if seen[v] then return seen[v] end
	local out = {}
	seen[v] = out
	for k, x in v do out[deepcopy(k, seen)] = deepcopy(x, seen) end
	return out
end

local function body()
	local RS = M.game.ReplicatedStorage
	local ModelConfig = M.require(RS.Shared.Config.ModelConfig)
	local MarketConfig = M.require(RS.Shared.Config.MarketConfig)
	local DataConfig = M.require(RS.Shared.Config.DataConfig)
	local ModelMath = M.require(RS.Shared.ModelMath)
	local EmpireMath = M.require(RS.Shared.EmpireMath)
	local MarketMath = M.require(RS.Shared.MarketMath)
	local PricingMath = M.require(RS.Shared.PricingMath)

	------------------------------------------------------------------ helpers per state
	local UI = setup(M, GEN, "rich")
	local function fresh(state)
		local s, d = UI.use(state)
		return UI, s, d, UI.LabPreview
	end
	-- the old LabApp creator formula (LabApp:397-407 before this package): today's numbers
	local function oldFormula(d, sizeId, focusId, recipeId)
		local size = ModelConfig.getSize(sizeId)
		local fleet = ModelMath.fleet(d.gpus)
		local summary = ModelMath.dataSummary(d.data)
		local plan = ModelMath.plan(size, fleet, summary, recipeId)
		local spec = if d.company then d.company.spec else "general"
		local stats, overall = ModelMath.computeStats(size.id, focusId, summary, spec, ModelMath.recipeFactor(size, summary, recipeId), nil)
		stats, overall = EmpireMath.boostStats(stats, d.empire)
		stats, overall = ModelMath.capStats(stats)
		local rate = EmpireMath.trainingRate(d.gpus, plan.work, d.empire)
		return overall, plan.cost, if rate > 0 then plan.work / rate else 0, stats
	end
	local ERR = { FRONTIER = "PREREQUISITE", MODEL_LIMIT = "MODEL_LIMIT", NO_GPU = "NO_GPU", VRAM = "VRAM", NO_DATA = "NO_DATA", MONEY = "NO_MONEY" }

	------------------------------------------------------------------ 1. honesty: estimate == StartTraining for every choice
	for _, state in { "rich", "starter", "hq", "fresh" } do
		local ui, s, d, LP = fresh(state)
		local base = deepcopy(d)
		local compared, mismatches, locks, lockMismatch = 0, {}, 0, {}
		for _, size in ModelConfig.SIZES do
			for _, recipe in ModelConfig.RECIPES do
				for _, focus in ModelConfig.FOCUSES do
					s.data = deepcopy(base)
					local sel = { sizeId = size.id, focusId = focus.id, recipeId = recipe.id }
					local est = LP.estimate(s.data, sel, s.data.money)
					local o, c, t = oldFormula(s.data, size.id, focus.id, recipe.id)
					if not (near(est.overall, o) and est.cost == c and near(est.seconds, t)) then
						table.insert(mismatches, `old {size.id}/{recipe.id}/{focus.id}`)
					end
					local r = ui.binds.StartTraining(s, { name = "Probe", sizeId = size.id, focusId = focus.id, recipeId = recipe.id })
					if r.ok then
						compared += 1
						local tr = s.data.training
						local model = s.data.models[r.modelId]
						local rate = EmpireMath.trainingRate(base.gpus, tr.workTotal, base.empire)
						if not (est.lock == nil and near(tr.expected, est.overall) and model.trainCost == est.cost and near(tr.workTotal, est.work) and near(tr.workTotal / rate, est.seconds)) then
							table.insert(mismatches, `{size.id}/{recipe.id}/{focus.id}: server {tr.expected}/{model.trainCost} vs {est.overall}/{est.cost} lock {tostring(est.lock)}`)
						end
					else
						locks += 1
						if ERR[est.lock or ""] ~= r.err then
							table.insert(lockMismatch, `{size.id}/{recipe.id}/{focus.id}: server {r.err} vs lock {tostring(est.lock)}`)
						end
					end
				end
			end
		end
		s.data = base
		check(`honesty {state}: estimate == StartTraining (expected, cost, work, time) for every started choice`, #mismatches == 0, table.concat(mismatches, "; "))
		check(`honesty {state}: every refused choice has the server's error as its lock`, #lockMismatch == 0, table.concat(lockMismatch, "; "))
		check(`honesty {state}: covered all 60 choices`, compared + locks == 60, compared .. "+" .. locks)
		if state == "rich" then check("honesty rich: all 60 choices start (no lock in rich)", compared == 60, compared) end
		if state == "fresh" then check("honesty fresh: every choice refused (no data / VRAM / research)", compared == 0, compared) end
	end

	------------------------------------------------------------------ 2. rich reference values (LAB_SPEC 4.4-4.6, 9.1)
	do
		local ui, s, d, LP = fresh("rich")
		local function est(size, focus, recipe) return LP.estimate(d, { sizeId = size, focusId = focus, recipeId = recipe }, d.money) end
		local e = est("s1b", "balanced", "steady")
		check("rich 1B Balanced Standard = 73.7 / $7,040 / 12 s", near(e.overall, 73.7) and e.cost == 7040 and near(e.seconds, 12), `{e.overall} {e.cost} {e.seconds}`)
		local c = est("s1b", "coding", "steady")
		check("rich 1B Coding Standard = 74.5", near(c.overall, 74.5), c.overall)
		local deep = est("s1b", "balanced", "deep")
		check("rich 1B Balanced Deep = 88.0 / $16,896 / 25.8 s", near(deep.overall, 88.0) and deep.cost == 16896 and near(deep.seconds, 25.8, 0.05), `{deep.overall} {deep.cost} {deep.seconds}`)
		check("rich 1B Coding Deep = 88.5", near(est("s1b", "coding", "deep").overall, 88.5), est("s1b", "coding", "deep").overall)
		check("rich 3B Coding Standard = 71.7", near(est("s3b", "coding", "steady").overall, 71.7), est("s3b", "coding", "steady").overall)
		local d7 = est("s7b", "coding", "deep")
		check("rich 7B Coding Deep overfits (recipe factor 0.85)", d7.overfit == true and near(d7.recipeFactor, 0.85, 1e-6), `{d7.overfit} {d7.recipeFactor} {d7.overall}`)
		local deltas = LP.deltas(d, { sizeId = "s1b", focusId = "coding", recipeId = "steady" }, "sizeId", d.money)
		check("rich size deltas vs 1B Coding: 3B = -2.8, 100M = -15.1", near(deltas.s3b.dOverall, -2.8) and near(deltas.s100m.dOverall, -15.1), `{deltas.s3b.dOverall} {deltas.s100m.dOverall}`)
		check("rich focus 1B: best fit for Developer API = coding", LP.bestFocus(d, "s1b", "steady", "developers") == "coding")
		local lo, hi = LP.range(74.5)
		check("range = overall ± TRAINING.noise (72.0-77.0)", near(lo, 72.0) and near(hi, 77.0), `{lo} {hi}`)
		local r = LP.rank(ui.push and { data = d, live = s.live, serverTime = 0 } or nil, c.stats, "developers")
		check("rank: rich Developer API with 1B Coding = #1 of 5", r.rank == 1 and r.total == 5, `{r.rank}/{r.total}`)
		local one, word = LP.stars(1, 5)
		local two, w2 = LP.stars(5, 5)
		check("stars: #1 = 5 MARKET LEADER, last = 1 CHALLENGER", one == 5 and word == "MARKET LEADER" and two == 1 and w2 == "CHALLENGER")
		local coder = d.models.coder
		local q = LP.lineQuality(coder.stats, "developers", "developers", 2700)
		check("lineQuality(Coder v2, developers, vage 2700) = fit - 6.0", near(q, MarketMath.fit(coder.stats, LP.segmentOf("developers")) - 6.0, 0.01), q)
		check("lineQuality: outside its line loses LINE_PENALTY x FIT_SCALE = 18", near(LP.lineQuality(coder.stats, "developers", "consumers", 0), MarketMath.fit(coder.stats, LP.segmentOf("general")) - 18, 1e-6))
		-- bestAffordable (reserve, Save mode cap)
		local pick = LP.bestAffordable(d, "coding", d.money, false)
		check("bestAffordable rich: 1B Deep (88.0, $16,896)", pick and pick.sizeId == "s1b" and pick.recipeId == "deep" and pick.estimate.cost == 16896, pick and (pick.sizeId .. " " .. pick.recipeId))
		local reserve = LP.reserve(d)
		local over = {}
		for money = 2000, 40000, 250 do
			local tight = LP.bestAffordable(d, "coding", money, false)
			if tight and tight.estimate.cost > money - reserve then table.insert(over, money) end
		end
		check("bestAffordable never spends more than money - reserve ($2,000..$40,000)", #over == 0, table.concat(over, ","))
		local saving = LP.bestAffordable(d, "coding", 40000, true)
		check("bestAffordable in Save mode: cost <= 30 % of the free cash", saving == nil or saving.estimate.cost <= 0.3 * (40000 - reserve), saving and saving.estimate.cost)
		-- the line SUCCESSOR button of Developer API (LAB_SPEC 8.1 step 4: BEST I CAN AFFORD failed the --ui-defaults
		-- run, so suggestions use the economy bot's rule = LabPreview.successorPick: largest size the servers carry,
		-- data plan, >= current + 3, Deep when the data is enough. With the live capacity the rich save gets 1B Deep;
		-- without capacity info 7B Deep.)
		local succ = LP.lineSuccessor(d, s.live, "developers", d.money, false)
		check("line successor rich Developer API: name Coder, focus kept, bot rule with live capacity = 1B Deep", succ and succ.target == "developers" and succ.name == "Coder" and succ.focusId == "balanced" and succ.sizeId == "s1b" and succ.recipeId == "deep", succ and `{succ.target} {succ.sizeId} {succ.recipeId}`)
		local blind = LP.lineSuccessor(d, nil, "developers", d.money, false)
		check("line successor rich without capacity info: the largest size (7B Deep after its data plan)", blind and blind.sizeId == "s7b" and blind.recipeId == "deep", blind and `{blind.sizeId} {blind.recipeId}`)
		-- the SUGGESTED tile: a free line first (Study App is free at Startup Campus), the bot's order
		local sug = LP.suggest(d, s.live, d.money, false)
		check("suggest rich: the free Study App line (new line), the bot's line order", sug and sug.kind == "newline" and sug.target == "students" and sug.model == nil, sug and `{sug.kind} {sug.target}`)
		if sug and sug.pick then
			local after = LP.estimate(LP.withStock(d, sug.pick.plan.stock), { sizeId = sug.sizeId, focusId = sug.focusId, recipeId = sug.recipeId }, nil)
			check("suggest: the promised expected value is the after-plan estimate of its own pick", near(sug.expected, after.overall, 1e-9), `{sug.expected} vs {after.overall}`)
			check("suggest: passes the bot's gate (after the plan >= current + 3)", sug.pick.plan.after >= sug.current + 3 and sug.current == sug.pick.current, `{sug.pick.plan.after} {sug.current}`)
			local pre = LP.prefillOf(sug)
			check("prefillOf carries the data plan (the Review offers it)", pre.target == "students" and pre.sizeId == sug.sizeId and pre.recipeId == sug.recipeId and (sug.pick.plan.cost == 0 or pre.plan == sug.pick.plan), pre.plan and pre.plan.cost)
		else
			check("suggest rich has a pick", false, sug and "no pick")
		end
		local sp = LP.successorPick(d, s.live, "developers", "balanced", d.money, false)
		check("successorPick keeps the bot's gate: after its data plan >= the line's current model (overall - age) + 3", sp and sp.plan.after >= sp.current + 3, sp and `{sp.plan.after} vs {sp.current}`)
		local last = LP.sameAsLast(d)
		check("sameAsLast = newest non-training model (Sage 1B balanced)", last and last.sizeId == "s1b" and last.focusId == "balanced")
		-- data plan: rich 1B Coding empty, 3B Coding 1x repos
		local p1 = LP.dataPlan(d, { sizeId = "s1b", focusId = "coding", recipeId = "steady" }, d.money)
		check("dataPlan rich 1B Coding: empty", p1.cost == 0 and #p1.order == 0, p1.cost)
		local p3 = LP.dataPlan(d, { sizeId = "s3b", focusId = "coding", recipeId = "steady" }, d.money)
		check("dataPlan rich 3B Coding: 1x Public Repos ($2,500), 71.7 -> 72.5", p3.cost == 2500 and p3.packs.repos == 1 and near(p3.before, 71.7) and near(p3.after, 72.5), `{p3.cost} {LP.planText(p3)} {p3.before} {p3.after}`)
		-- odds
		local dec, boost = LP.eventOdds("general")
		check("eventOdds general = 0.30 decisions / 0.10 breakthrough", near(dec, 0.3) and near(boost, 0.1), `{dec} {boost}`)
		check("odds text", LP.oddsText("general") == "3 in 10 runs pause for a decision · 1 in 10 get +5 %", LP.oddsText("general"))
		-- lineStatus
		local ls = LP.lineStatus(d, "developers")
		check("lineStatus Developer API = LIVE Coder v2 (line v1)", ls.kind == "LIVE" and ls.model and ls.model.id == "coder" and ls.version == 1, ls.kind)
		check("lineStatus Study App = FREE, line 3 of 3", LP.lineStatus(d, "students").kind == "FREE" and LP.lineStatus(d, "students").usedLines == 2 and LP.lineStatus(d, "students").slots == 3)
	end

	------------------------------------------------------------------ 3. garage: first model = the casual bot's start (economy guard)
	do
		local ui, s, d, LP = fresh("fresh")
		check("fresh garage: first model", LP.isFirstModel(d))
		check("fresh: best focus for Consumer Chat = creative (the bot's LINE_FOCUS.general)", LP.bestFocus(d, "s100m", "steady", "general") == "creative")
		local sel = { sizeId = "s100m", focusId = "creative", recipeId = "steady" }
		local est = LP.estimate(d, sel, d.money)
		check("fresh: lock NO_DATA (Template starts with data = {})", est.lock == "NO_DATA", est.lock)
		local plan = LP.dataPlan(d, sel, d.money)
		check("fresh data plan = 2x Web Crawl Chunk + 2x Public Repos, $7,400", plan.cost == 7400 and plan.packs.web_chunk == 2 and plan.packs.repos == 2, LP.planText(plan) .. " " .. plan.cost)
		check("fresh data plan: 4B tokens at 42.5 %, expected 18.1 -> 40.2", near(plan.tokens, 4e9) and near(plan.quality, 0.425, 1e-9) and near(plan.before, 18.1) and near(plan.after, 40.2), `{plan.tokens} {plan.quality} {plan.before} {plan.after}`)
		check("plan text", LP.planText(plan) == "2× Web Crawl Chunk + 2× Public Repos", LP.planText(plan))
		-- the casual bot's planData (agents/corefix/sim.luau:347-370), verbatim, on the same state
		local function botPlan(dd, sizeId, focus, budget, recipe)
			local function expectedFor(stock)
				local size = ModelConfig.getSize(sizeId)
				local summary = ModelMath.dataSummary(stock)
				local st, ov = ModelMath.computeStats(sizeId, focus, summary, dd.company.spec, ModelMath.recipeFactor(size, summary, recipe), nil)
				st, ov = EmpireMath.boostStats(st, dd.empire)
				return ov
			end
			local spent, stock, bought = 0, ModelMath.copyStock(dd.data), {}
			for _ = 1, 60 do
				local base = expectedFor(stock)
				local bestPack, bestGain = nil, 0
				for _, pack in DataConfig.PACKS do
					if spent + pack.price <= budget then
						local copy = ModelMath.copyStock(stock)
						ModelMath.addTokens(copy, pack.type, pack.tokens, pack.quality)
						local gain = (expectedFor(copy) - base) / pack.price
						if gain > bestGain then bestGain = gain; bestPack = pack end
					end
				end
				if not bestPack or bestGain < 0.3 / 1000 then break end
				ModelMath.addTokens(stock, bestPack.type, bestPack.tokens, bestPack.quality)
				spent += bestPack.price
				bought[bestPack.id] = (bought[bestPack.id] or 0) + 1
			end
			return spent, expectedFor(stock), bought
		end
		local reserve = math.max(1500, EmpireMath.bonuses(d.empire).wage * 120)
		local cost = ModelMath.plan(ModelConfig.getSize("s100m"), ModelMath.fleet(d.gpus), ModelMath.dataSummary(d.data), "steady").cost
		local bs, bev, bb = botPlan(d, "s100m", "creative", (d.money - reserve - cost) * 0.8, "steady")
		check("dataPlan == the bot's planData (spent, packs, expected)", bs == plan.cost and near(bev, plan.after) and bb.web_chunk == plan.packs.web_chunk and bb.repos == plan.packs.repos, `{bs} {bev}`)
		-- buy the plan through the real BuyData handler, then the estimate = 40.2 and START is allowed
		for _, id in plan.order do
			local r = ui.binds.BuyData(s, { packId = id, count = plan.packs[id] })
			check("BuyData " .. id .. " ok", r.ok == true, r.err)
		end
		local after = LP.estimate(d, sel, d.money)
		check("after the plan: expected 40.2, $1,280, 80 s, no lock", near(after.overall, 40.2) and after.cost == 1280 and near(after.seconds, 80) and after.lock == nil, `{after.overall} {after.cost} {after.seconds} {tostring(after.lock)}`)
		check("after the plan: cash $4,800 (12,200 - 7,400)", d.money == 4800, d.money)
		local snap = { data = d, live = s.live, serverTime = 0 }
		local r = LP.rank(snap, after.stats, "general")
		check("starter Consumer Chat: #6 of 6, next to beat Vector Lite (fit 50.9)", r.rank == 6 and r.total == 6 and r.next and r.next.name == "Vector Lite" and near(r.next.quality, 50.9, 0.05), `{r.rank}/{r.total} {r.next and r.next.name} {r.next and r.next.quality}`)
		-- the starter garage tiles (LAB_SPEC 4.4): 500M Needs 12 GB, 7B Needs research
		local dl = LP.deltas(d, sel, "sizeId", d.money)
		check("garage: 500M locked by VRAM, 7B by research (server order)", dl.s500m.estimate.lock == "VRAM" and dl.s7b.estimate.lock == "FRONTIER", `{tostring(dl.s500m.estimate.lock)} {tostring(dl.s7b.estimate.lock)}`)
		-- recommended launch numbers are today's functions (marketing <= $5,000 above the reserve)
		check("recommended marketing = PricingMath.recommendedMarketing (unchanged rule)", PricingMath.recommendedMarketing(4800 - 1280, EmpireMath.bonuses(d.empire).wage) == math.max(0, math.min(5000, math.floor((4800 - 1280 - 1500) / 500) * 500)))
	end

	------------------------------------------------------------------ 4. lock order == server order
	do
		local ui, s, d, LP = fresh("starter")
		d.money = 1e9
		-- 7B without frontier AND too little VRAM -> PREREQUISITE first
		local e = LP.estimate(d, { sizeId = "s7b", focusId = "balanced", recipeId = "steady" }, d.money)
		local r = ui.binds.StartTraining(s, { name = "Zed", sizeId = "s7b", focusId = "balanced", recipeId = "steady" })
		check("7B without research + low VRAM: lock FRONTIER = server PREREQUISITE", e.lock == "FRONTIER" and r.err == "PREREQUISITE", `{tostring(e.lock)} {tostring(r.err)}`)
		local e2 = LP.estimate(d, { sizeId = "s3b", focusId = "balanced", recipeId = "steady" }, d.money)
		local r2 = ui.binds.StartTraining(s, { name = "Zed", sizeId = "s3b", focusId = "balanced", recipeId = "steady" })
		check("3B in the garage: VRAM = VRAM", e2.lock == "VRAM" and r2.err == "VRAM", `{tostring(e2.lock)} {tostring(r2.err)}`)
		-- MODEL_LIMIT with 80 non-retired models
		local saved = d.models
		local many = table.clone(saved)
		for i = 1, 80 do many["x" .. i] = { id = "x" .. i, name = "X", version = i, sizeId = "s100m", focusId = "balanced", status = "trained", stats = {}, overall = 1, trainCost = 0, dataUsed = { total = 0, quality = 0, shares = {} }, createdAt = 0 } end
		d.models = many
		local e3 = LP.estimate(d, { sizeId = "s100m", focusId = "balanced", recipeId = "steady" }, d.money)
		local r3 = ui.binds.StartTraining(s, { name = "Zed", sizeId = "s100m", focusId = "balanced", recipeId = "steady" })
		check("80 active models: lock MODEL_LIMIT = server MODEL_LIMIT", e3.lock == "MODEL_LIMIT" and r3.err == "MODEL_LIMIT", `{tostring(e3.lock)} {tostring(r3.err)}`)
		d.models = saved
		d.money = 100
		local e4 = LP.estimate(d, { sizeId = "s100m", focusId = "balanced", recipeId = "steady" }, d.money)
		local r4 = ui.binds.StartTraining(s, { name = "Zed", sizeId = "s100m", focusId = "balanced", recipeId = "steady" })
		check("$100: lock MONEY = server NO_MONEY", e4.lock == "MONEY" and r4.err == "NO_MONEY", `{tostring(e4.lock)} {tostring(r4.err)}`)
		local ui2, s2, d2, LP2 = fresh("fresh")
		local e5 = LP2.estimate(d2, { sizeId = "s100m", focusId = "balanced", recipeId = "steady" }, d2.money)
		local r5 = ui2.binds.StartTraining(s2, { name = "Zed", sizeId = "s100m", focusId = "balanced", recipeId = "steady" })
		check("fresh save: lock NO_DATA = server NO_DATA", e5.lock == "NO_DATA" and r5.err == "NO_DATA", `{tostring(e5.lock)} {tostring(r5.err)}`)
		d2.gpus = {}
		local e6 = LP2.estimate(d2, { sizeId = "s100m", focusId = "balanced", recipeId = "steady" }, d2.money)
		local r6 = ui2.binds.StartTraining(s2, { name = "Zed", sizeId = "s100m", focusId = "balanced", recipeId = "steady" })
		check("no GPU: lock NO_GPU = server NO_GPU", e6.lock == "NO_GPU" and r6.err == "NO_GPU", `{tostring(e6.lock)} {tostring(r6.err)}`)
	end

	------------------------------------------------------------------ 5. versions: Studio "Becomes X vN" == server
	do
		for _, case in { { "Sage", 2 }, { "Nova", 3 }, { "Coder", 3 }, { "Zed", 1 }, { "nova", 3 } } do
			local ui, s, d, LP = fresh("rich")
			local v = LP.nextVersion(d, case[1])
			local r = ui.binds.StartTraining(s, { name = case[1], sizeId = "s100m", focusId = "balanced", recipeId = "steady" })
			local model = r.ok and d.models[r.modelId]
			check(`nextVersion("{case[1]}") = {case[2]} = server model.version`, v == case[2] and model and model.version == v, `{v} {model and model.version}`)
		end
	end

	------------------------------------------------------------------ 6. refineCheck == ImproveModel (same error, same order)
	do
		local function compare(label, prep)
			local ui, s, d, LP = fresh("rich")
			local model = d.models.study
			prep(d, model, ui, s)
			local c = LP.refineCheck(d, model, d.money)
			local r = ui.binds.ImproveModel(s, { modelId = model.id })
			check(`refineCheck {label}: {tostring(c.err)} == server {tostring(r.err)}`, (c.ok and r.ok) or (not c.ok and c.err == r.err), `{tostring(c.ok)}/{tostring(c.err)} vs {tostring(r.ok)}/{tostring(r.err)}`)
			return c
		end
		compare("training active", function(d, m, ui, s) ui.binds.StartTraining(s, { name = "Busy", sizeId = "s100m", focusId = "balanced", recipeId = "steady" }) end)
		compare("limit 3/3", function(d, m) m.iterations = 3 end)
		local c = compare("no new data", function(d, m) m.dataUsed = { total = ModelMath.dataSummary(d.data).total, quality = 0.8, shares = {} } end)
		check("refineCheck reason 'needs 100M new tokens'", c.reason == "needs 100M new tokens", c.reason)
		compare("no GPU", function(d, m) d.gpus = {} end)
		compare("no money", function(d, m) d.money = 10 end)
		local ok = compare("ok", function() end)
		check("refineCheck ok has the server's cost", ok.ok and ok.cost == 7040, ok.cost)
	end

	------------------------------------------------------------------ 7. server: optional look / target (validated, saved, old payload unchanged)
	do
		local ui, s, d = fresh("rich")
		check("parseLook valid", (function() local c, i = ModelMath.parseLook("amber:3"); return c == "amber" and i == 3 end)())
		-- shop package (round 3): emblems 9-14 are the Identity Kit logos (valid format; the pass is checked by
		-- StartTraining -> PASS_NEEDED, tests/shop2 T11), so the first invalid index is 15
		check("parseLook accepts a Kit emblem (9)", (function() local c, i = ModelMath.parseLook("amber:9"); return c == "amber" and i == 9 end)())
		for _, bad in { "amber:0", "amber:15", "purple:1", "amber:1.5", "amber", ":2", 5, true, string.rep("a", 30) .. ":1" } do
			local c = ModelMath.parseLook(bad)
			check("parseLook rejects " .. tostring(bad), c == nil)
		end
		local r = ui.binds.StartTraining(s, { name = "Lookie", sizeId = "s100m", focusId = "balanced", recipeId = "steady", look = "purple:1" })
		check("StartTraining with an invalid look -> BAD_INPUT, nothing spent", r.err == "BAD_INPUT" and d.training == nil and d.money == 186400, r.err)
		local r2 = ui.binds.StartTraining(s, { name = "Lookie", sizeId = "s100m", focusId = "balanced", recipeId = "steady", target = "aliens" })
		check("StartTraining with an invalid target -> BAD_INPUT", r2.err == "BAD_INPUT" and d.training == nil, r2.err)
		local r3 = ui.binds.StartTraining(s, { name = "Lookie", sizeId = "s100m", focusId = "balanced", recipeId = "steady", look = { 1 } })
		check("StartTraining with a table look -> BAD_INPUT", r3.err == "BAD_INPUT", r3.err)
		local r4 = ui.binds.StartTraining(s, { name = "Lookie", sizeId = "s100m", focusId = "creative", recipeId = "deep", look = "amber:2", target = "students" })
		local m = r4.ok and d.models[r4.modelId]
		check("valid look/target saved on the model (look, plan, recipeId)", m and m.look == "amber:2" and m.plan == "students" and m.recipeId == "deep", m and tostring(m.look))
		ui.AIModelService.finishNow(s)
		local ui2, s2, d2 = fresh("rich")
		local r5 = ui2.binds.StartTraining(s2, { name = "Plain", sizeId = "s100m", focusId = "balanced", recipeId = "steady" })
		local m5 = r5.ok and d2.models[r5.modelId]
		check("old payload (no look/target): ok, look and plan nil", m5 and m5.look == nil and m5.plan == nil, m5 and tostring(m5.look))
		-- save compatibility: the load path (Template.migrate + cleaners) keeps the new optional fields and leaves
		-- old models (without them) exactly as they were
		local Template = M.require(M.game.ServerScriptService.Server.Lib.Template)
		local raw = deepcopy(d)
		local oldModel = deepcopy(raw.models.coder)
		local loaded, why = Template.migrate(raw)
		local lm = loaded and loaded.models[r4.modelId]
		check("save round trip keeps look / plan / recipeId of a new model", lm and lm.look == "amber:2" and lm.plan == "students" and lm.recipeId == "deep", why or (lm and tostring(lm.look)))
		local lc = loaded and loaded.models.coder
		local same = lc ~= nil and lc.look == nil and lc.plan == nil and lc.recipeId == nil and lc.overall == oldModel.overall and lc.sizeId == oldModel.sizeId and lc.focusId == oldModel.focusId and lc.version == oldModel.version and lc.status == oldModel.status
		check("save round trip: an old model without the fields loads unchanged (no look/plan/recipeId added)", same)
		local LP7 = UI.LabPreview
		local last = LP7.sameAsLast(d2)
		check("SAME AS LAST on an old model (no recipeId saved) keeps the current plan (recipeId nil)", last and last.recipeId == nil, last and tostring(last.recipeId))
	end

	------------------------------------------------------------------ 8. S1: TRAINING_COMPLETE carries expected / refinement / before / event
	do
		local ui, s, d = fresh("rich")
		local State = M.require(M.game.StarterPlayer.StarterPlayerScripts.Client.Controllers.StateController)
		local got = {}
		State.onNotify(function(kind, payload) if kind == "TRAINING_COMPLETE" then table.insert(got, payload) end end)
		local r = ui.binds.StartTraining(s, { name = "Sage", sizeId = "s1b", focusId = "coding", recipeId = "steady" })
		local expected = d.training.expected
		ui.AIModelService.finishNow(s)
		M.settle(0.2)
		local p = got[#got]
		check("S1 new model: expected, refinement=false, before=nil, previousBest", p and near(p.expected, expected) and p.refinement == false and p.before == nil and near(p.previousBest, 61.6) and near(p.overall, d.models[r.modelId].overall), p and tostring(p.expected))
		-- refinement of the best live model: before = its old overall
		local nova = d.models.nova2
		d.data.general.tokens += 2e8
		local old = nova.overall
		local rr = ui.binds.ImproveModel(s, { modelId = "nova2" })
		check("refinement starts", rr.ok == true, rr.err)
		ui.AIModelService.finishNow(s)
		M.settle(0.2)
		local q = got[#got]
		check("S1 refinement: refinement=true, before = the model's old overall", q and q.refinement == true and near(q.before, old) and q.modelId == "nova2", q and tostring(q.before))
		-- an event outcome travels with the payload
		local ui3, s3, d3 = fresh("rich")
		local got3 = {}
		local State3 = M.require(M.game.StarterPlayer.StarterPlayerScripts.Client.Controllers.StateController)
		State3.onNotify(function(kind, payload) if kind == "TRAINING_COMPLETE" then table.insert(got3, payload) end end)
		ui3.binds.StartTraining(s3, { name = "Ev", sizeId = "s1b", focusId = "coding", recipeId = "steady" })
		d3.training.eventRolled = true
		d3.training.event = { id = "data_issue", pending = true, expiresAt = 1e12, outcome = nil }
		ui3.binds.ResolveEvent(s3, { choice = "ignore" })
		ui3.AIModelService.finishNow(s3)
		M.settle(0.2)
		local e = got3[#got3]
		check("S1 event: eventId + outcome", e and e.eventId == "data_issue" and e.outcome == "ignore", e and tostring(e.outcome))
	end

	------------------------------------------------------------------ 9. fix round 1: suggestion = the bot's line rule, ceiling, Deep reasons, spec text
	do
		-- the casual bot's line choice (agents/corefix/sim.luau tryTrain, verbatim): a free line first in ITS order,
		-- else the weakest live line (overall minus age)
		local function botLine(d)
			local LINES = { "general", "developers", "students", "businesses" }
			local lives = {}
			for _, id in d.modelOrder do local m = d.models[id]; if m and m.status == "live" then table.insert(lives, m) end end
			local function effective(m)
				if not m then return 0 end
				if not (MarketConfig.AGE and m.market) then return m.overall end
				return m.overall - MarketConfig.AGE.maxFit * math.clamp((m.market.vage or 0) / MarketConfig.AGE.full, 0, 1)
			end
			local function liveInLine(line)
				for _, m in lives do if m.release and MarketMath.lineOf(m.release.target) == MarketMath.lineOf(line) then return m end end
				return nil
			end
			local pick, current = nil, 0
			if #lives < (MarketConfig.PRODUCT_SLOTS[d.empire.office] or 1) then
				for _, line in LINES do if not liveInLine(line) then pick = line; current = 0; break end end
				local best
				for _, id in d.modelOrder do local m = d.models[id]; if m and m.status == "live" and (not best or m.overall > best.overall) then best = m end end
				if pick and best then current = math.max(0, effective(best) - 12) end
			end
			if not pick then
				local worst
				for _, m in lives do if not worst or effective(m) < effective(worst) then worst = m end end
				if worst then pick = worst.release.target; current = effective(worst) end
			end
			return pick, current
		end
		local cases = 0
		local bad = {}
		for _, state in { "rich", "full", "hq" } do
			for _, ages in { { 0, 0, 0 }, { 3600, 0, 0 }, { 0, 3600, 1800 }, { 900, 900, 3600 } } do
				for _, cash in { 9000, 60000, 186400, 2400000 } do
					local ui, s, d, LP = fresh(state)
					d.money = cash
					local i = 0
					for _, id in d.modelOrder do
						local m = d.models[id]
						if m.status == "live" and m.market then i += 1; m.market.vage = ages[(i - 1) % 3 + 1] end
					end
					local sug = LP.suggest(d, s.live, d.money, false)
					local pick, current = botLine(d)
					cases += 1
					if not sug or sug.target ~= pick or not near(sug.current, current, 1e-9) then
						table.insert(bad, `{state} {table.concat(ages, "/")} ${cash}: suggest {sug and sug.target} {sug and sug.current} vs bot {pick} {current}`)
					end
					if sug and sug.pick and not near(sug.pick.current, sug.current, 1e-9) then
						table.insert(bad, `{state}: pick.current {sug.pick.current} vs {sug.current}`)
					end
				end
			end
		end
		check(`suggest = the economy bot's line choice and gate base in {cases} states (ages x cash)`, #bad == 0, table.concat(bad, "; "))
		-- the first model has no suggestion (DESIGN NEW MODEL is its path)
		do
			local ui, s, d, LP = fresh("fresh")
			check("suggest: nil for the first model", LP.suggest(d, s.live, d.money, false) == nil)
		end
		-- ceiling: never below what the Studio shows; the old 'Max score' (size potential) was
		local below, compared = {}, 0
		for _, state in { "rich", "hq", "starter" } do
			local ui, s, d, LP = fresh(state)
			for _, size in ModelConfig.SIZES do
				for _, recipe in ModelConfig.RECIPES do
					for _, focus in ModelConfig.FOCUSES do
						local sel = { sizeId = size.id, focusId = focus.id, recipeId = recipe.id }
						local e = LP.estimate(d, sel, nil)
						local c = LP.ceiling(d, sel)
						compared += 1
						if c + 1e-9 < e.overall then table.insert(below, `{state} {size.id}/{recipe.id}/{focus.id} {c} < {e.overall}`) end
					end
				end
			end
		end
		check(`ceiling >= the shown expected value for all {compared} choices (rich, hq, starter)`, #below == 0, table.concat(below, "; "))
		do
			local ui, s, d, LP = fresh("rich")
			local sel = { sizeId = "s1b", focusId = "coding", recipeId = "deep" }
			local size = ModelConfig.getSize("s1b")
			check("rich 1B Coding Deep: ceiling >= 88.5 while the size potential is 63 (the old 'Max score' was wrong)", LP.ceiling(d, sel) >= 88.5 and size.potential == 63, LP.ceiling(d, sel))
		end
		-- Deep's reason names the condition that fails (ModelMath.recipeFactor)
		do
			local ui, s, d, LP = fresh("starter") -- 4B tokens at 42.5 %
			local sm = ModelMath.dataSummary(d.data)
			check("deepShort starter 100M: enough tokens, low quality -> 'Needs 60% quality'", LP.deepShort("s100m", sm) == "Needs 60% quality", LP.deepShort("s100m", sm))
			local ui2, s2, d2, LP2 = fresh("rich") -- 16B at 80.6 %
			local sm2 = ModelMath.dataSummary(d2.data)
			check("deepShort rich 1B: enough -> nil", LP2.deepShort("s1b", sm2) == nil)
			local need7 = ModelConfig.getSize("s7b").dataNeed * 0.5
			local want = if sm2.total < need7 then "Needs " .. M.require(RS.Shared.Format).tokens(need7) .. " data" else nil
			check("deepShort rich 7B: the data amount (half of 7B's need) when that is what fails", LP2.deepShort("s7b", sm2) == want, LP2.deepShort("s7b", sm2))
			local e7 = LP2.estimate(d2, { sizeId = "s7b", focusId = "coding", recipeId = "deep" }, nil)
			check("deepShort agrees with the overfit flag (7B Deep overfits in rich)", e7.overfit == (LP2.deepShort("s7b", sm2) ~= nil))
		end
		do
			local LP = UI.LabPreview
			check("specBonusText general = 'spec +2 each skill'", LP.specBonusText("general") == "spec +2 each skill", LP.specBonusText("general"))
			check("specBonusText coding = 'spec +6 Coding'", LP.specBonusText("coding") == "spec +6 Coding", LP.specBonusText("coding"))
			check("specBonusText efficient names a stat outside Overall", LP.specBonusText("efficient") == "spec +6 Efficiency (not in Overall)", LP.specBonusText("efficient"))
		end
	end
end

setfenv(body, M.envFor(nil))
local ok, res = M.runMain(body, { timeout = 900 })
if not ok then failc += 1; P("FAIL  body crashed: " .. tostring(res)) end
if M.stats.errors > 0 then failc += 1; P("FAIL  background errors: " .. M.stats.errors) end
P(string.format("lab_preview: %d passed, %d failed", pass, failc))
