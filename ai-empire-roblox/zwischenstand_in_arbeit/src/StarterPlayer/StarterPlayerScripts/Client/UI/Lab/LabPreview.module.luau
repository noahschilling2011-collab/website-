--!strict
-- Model Studio maths (LAB_SPEC 5.2): every number the Studio shows, from the game's own pure functions on the
-- real snapshot state. No Instances, no services except the ReplicatedStorage lookup of the shared modules,
-- so tests (tests/lab) can compare each value with the real server handlers.
--   estimate   = the exact pipeline of AIModelService.startTraining (plan, stats, boost, cap, rate) + the lock
--                the server would answer first (its check order)
--   dataPlan   = the casual economy bot's planData rule (agents/corefix/sim.luau) on a copy of the data
--   rank/stars = the planned line's market (live rivals, or the static NPC list while no marketplace exists)
--   refineCheck mirrors AIModelService.improveModel in its order

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local ModelConfig = require(Shared.Config.ModelConfig)
local MarketConfig = require(Shared.Config.MarketConfig)
local DataConfig = require(Shared.Config.DataConfig)
local CompanyConfig = require(Shared.Config.CompanyConfig)
local ModelMath = require(Shared.ModelMath)
local EmpireMath = require(Shared.EmpireMath)
local MarketMath = require(Shared.MarketMath)
local Format = require(Shared.Format)
local Types = require(Shared.Types)

type PlayerData = Types.PlayerData
type ModelData = Types.ModelData
type Stats = Types.Stats
type DataStock = Types.DataStock

export type Sel = { sizeId: string, focusId: string, recipeId: string }

-- lock = the first error StartTraining would return for this choice (TRAINING_ACTIVE and BAD_NAME are the
-- Review button's business): FRONTIER (= PREREQUISITE), MODEL_LIMIT, NO_GPU, VRAM, NO_DATA, MONEY (= NO_MONEY)
export type Estimate = {
	sizeId: string,
	focusId: string,
	recipeId: string,
	stats: Stats,
	overall: number,
	cost: number,
	work: number,
	rate: number,
	seconds: number,
	readiness: ModelMath.Readiness,
	recipeFactor: number,
	overfit: boolean,
	lock: string?,
	vramNeed: number,
	vramHave: number,
}

export type Delta = { estimate: Estimate, dOverall: number, dCost: number }

export type DataPlan = {
	packs: { [string]: number },
	order: { string }, -- pack ids in buying order (one entry per pack id)
	cost: number,
	tokens: number, -- tokens after the plan
	quality: number, -- data quality after the plan
	before: number, -- expected overall before (bot rule, boostStats)
	after: number, -- expected overall after
	stats: Stats, -- capped expected stats after the plan (what the Studio shows)
	stock: { [string]: DataStock }, -- the data after the plan (a copy)
}

export type RankEntry = { name: string, quality: number }
export type Rank = { rank: number, total: number, quality: number, next: RankEntry?, segment: string }

export type LineStatus = {
	kind: string, -- "LIVE" | "FREE" | "FULL"
	model: ModelData?,
	agedFit: number?,
	version: number?, -- line version of the live model
	usedLines: number,
	slots: number,
}

export type Preset = { sizeId: string, recipeId: string, estimate: Estimate }

export type RefineCheck = { ok: boolean, err: string?, reason: string?, cost: number?, runs: number }

export type Breakdown = {
	potential: number,
	quantity: number,
	quality: number,
	recipeFactor: number,
	focusId: string,
	spec: string,
	specBonus: number,
	core: number,
	reliabilityBonus: number,
	cap: number,
}

local LabPreview = {}

LabPreview.ERR_OF_LOCK = {
	FRONTIER = "PREREQUISITE",
	MODEL_LIMIT = "MODEL_LIMIT",
	NO_GPU = "NO_GPU",
	VRAM = "VRAM",
	NO_DATA = "NO_DATA",
	MONEY = "NO_MONEY",
} :: { [string]: string }

local function specOf(data: PlayerData): string
	local company = data.company
	return if company then company.spec else "general"
end

local function modelLimit(): number
	local limit = (GameConfig :: any).MODEL_LIMIT
	return if typeof(limit) == "number" then limit else 80
end

local function sizeIndex(sizeId: string): number
	for i, size in ModelConfig.SIZES do
		if size.id == sizeId then
			return i
		end
	end
	return 1
end

---------------------------------------------------------------------------- estimate

-- Expected result of training `sel` now (no noise, no events). `money` adds the MONEY lock.
function LabPreview.estimate(data: PlayerData, sel: Sel, money: number?): Estimate
	local size = ModelConfig.getSize(sel.sizeId) or ModelConfig.SIZES[1]
	local focus = ModelConfig.getFocus(sel.focusId) or ModelConfig.FOCUSES[1]
	local recipeId = if ModelConfig.getRecipe(sel.recipeId) then sel.recipeId else "steady"
	local fleet = ModelMath.fleet(data.gpus)
	local summary = ModelMath.dataSummary(data.data)
	local plan = ModelMath.plan(size, fleet, summary, recipeId)
	local factor = ModelMath.recipeFactor(size, summary, recipeId)
	local stats, overall = ModelMath.computeStats(size.id, focus.id, summary, specOf(data), factor, nil)
	stats, overall = EmpireMath.boostStats(stats, data.empire)
	stats, overall = ModelMath.capStats(stats)
	local rate = EmpireMath.trainingRate(data.gpus, plan.work, data.empire)
	local lock: string? = nil
	if size.id == "s7b" and not data.empire.research.frontier then
		lock = "FRONTIER"
	elseif ModelMath.activeModels(data) >= modelLimit() then
		lock = "MODEL_LIMIT"
	elseif plan.reason then
		lock = plan.reason
	elseif money ~= nil and money < plan.cost then
		lock = "MONEY"
	end
	return {
		sizeId = size.id,
		focusId = focus.id,
		recipeId = recipeId,
		stats = stats,
		overall = overall,
		cost = plan.cost,
		work = plan.work,
		rate = rate,
		seconds = if rate > 0 then plan.work / rate else 0,
		readiness = ModelMath.readiness(size, summary),
		recipeFactor = factor,
		-- Deep training on too little / too poor data: recipeFactor applied 0.68 (ModelMath.recipeFactor)
		overfit = recipeId == "deep" and factor < (ModelConfig.getRecipe("deep").quality :: number) - 1e-9,
		lock = lock,
		vramNeed = size.vram,
		vramHave = fleet.vram,
	}
end

-- "final 72.0-77.0 without events": the server adds uniform +-TRAINING.noise per stat (AIModelService.finish)
function LabPreview.range(overall: number): (number, number)
	local noise = ModelConfig.TRAINING.noise
	return math.max(1, overall - noise), math.min(ModelConfig.STAT_CAP, overall + noise)
end

-- Estimates of every option of one step against the current pick (tiles show cost and the overall difference).
function LabPreview.deltas(data: PlayerData, sel: Sel, field: string, money: number?): { [string]: Delta }
	local base = LabPreview.estimate(data, sel, money)
	local out: { [string]: Delta } = {}
	local list: { any } = if field == "sizeId" then ModelConfig.SIZES elseif field == "focusId" then ModelConfig.FOCUSES else ModelConfig.RECIPES
	for _, def in list do
		local other: Sel = { sizeId = sel.sizeId, focusId = sel.focusId, recipeId = sel.recipeId }
		if field == "sizeId" then
			other.sizeId = def.id
		elseif field == "focusId" then
			other.focusId = def.id
		else
			other.recipeId = def.id
		end
		local est = if def.id == (sel :: any)[field] then base else LabPreview.estimate(data, other, money)
		out[def.id] = { estimate = est, dOverall = math.round((est.overall - base.overall) * 10) / 10, dCost = est.cost - base.cost }
	end
	return out
end

-- Share of the size's full data effect that the data gives (0..1): the lit cores of the Model Card.
function LabPreview.dataBenefit(readiness: ModelMath.Readiness): number
	local D = ModelConfig.DATA
	local full = 1 - math.exp(-D.quantityK * D.maxFill)
	return math.clamp(readiness.quantity / full, 0, 1)
end

-- Core grid of the Model Card: 3x3 .. 7x7 by size index (100M .. 7B).
function LabPreview.cores(sizeId: string): number
	return 2 + sizeIndex(sizeId)
end

function LabPreview.litCores(sizeId: string, readiness: ModelMath.Readiness): number
	local n = LabPreview.cores(sizeId)
	return math.round(n * n * LabPreview.dataBenefit(readiness))
end

---------------------------------------------------------------------------- market

function LabPreview.segmentOf(target: string?): MarketConfig.SegmentDef
	local id = ModelMath.lineOf(target)
	for _, segment in MarketConfig.SEGMENTS do
		if segment.id == id then
			return segment
		end
	end
	return MarketConfig.SEGMENTS[1]
end

function LabPreview.segmentById(id: string): MarketConfig.SegmentDef?
	for _, segment in MarketConfig.SEGMENTS do
		if segment.id == id then
			return segment
		end
	end
	return nil
end

-- Quality of a product in a segment in fit points: MarketMath.playerUtility without the price term.
function LabPreview.lineQuality(stats: Stats, target: string?, segmentId: string, vage: number?): number
	local segment = LabPreview.segmentById(segmentId) or MarketConfig.SEGMENTS[1]
	local q = MarketMath.fit(stats, segment)
	if target ~= nil and ModelMath.lineOf(target) ~= segmentId then
		q -= (MarketConfig.LINE_PENALTY or 0) * MarketConfig.FIT_SCALE
	end
	return q - ModelMath.ageFit(vage or 0)
end

-- Focus with the highest fit in the planned line (ties: ModelConfig order). First-model default + BEST FIT tag.
function LabPreview.bestFocus(data: PlayerData, sizeId: string, recipeId: string, target: string?): string
	local segment = LabPreview.segmentOf(target)
	local best, bestFit = ModelConfig.FOCUSES[1].id, -math.huge
	for _, focus in ModelConfig.FOCUSES do
		local est = LabPreview.estimate(data, { sizeId = sizeId, focusId = focus.id, recipeId = recipeId }, nil)
		local fit = MarketMath.fit(est.stats, segment)
		if fit > bestFit + 1e-9 then
			best, bestFit = focus.id, fit
		end
	end
	return best
end

-- Rank of a new model with `stats` in the line of `target` among the rivals it would meet (quality before
-- price). Own live models in the same line are left out: the new model replaces them.
function LabPreview.rank(snapshot: Types.Snapshot, stats: Stats, target: string): Rank
	local data = snapshot.data
	local segmentId = ModelMath.lineOf(target)
	local mine = LabPreview.lineQuality(stats, target, segmentId, 0)
	local entries: { RankEntry } = {}
	local marketplace: any = snapshot.live.marketplace
	if typeof(marketplace) == "table" then
		local offers = if typeof(marketplace.offers) == "table" then marketplace.offers else {}
		for _, offer in offers do
			if typeof(offer) == "table" and typeof(offer.stats) == "table" and typeof(offer.id) == "string" and data.models[offer.id] == nil then
				local name = if typeof(offer.name) == "string" then offer.name else "Rival"
				table.insert(entries, {
					name = name,
					quality = LabPreview.lineQuality(offer.stats, if typeof(offer.target) == "string" then offer.target else nil, segmentId, tonumber(offer.vage) or 0),
				})
			end
		end
	else
		for _, npc in MarketConfig.NPC_MODELS do
			table.insert(entries, { name = npc.name, quality = LabPreview.lineQuality(npc.stats, nil, segmentId, 0) })
		end
	end
	for _, id in data.modelOrder do
		local model = data.models[id]
		local release = if model then model.release else nil
		if model and release and model.status == "live" and ModelMath.lineOf(release.target) ~= segmentId then
			table.insert(entries, {
				name = `{model.name} v{model.version}`,
				quality = LabPreview.lineQuality(model.stats, release.target, segmentId, ModelMath.versionAge(model)),
			})
		end
	end
	local better = 0
	local nextEntry: RankEntry? = nil
	for _, entry in entries do
		if entry.quality > mine then
			better += 1
			if not nextEntry or entry.quality < nextEntry.quality then
				nextEntry = entry
			end
		end
	end
	return { rank = better + 1, total = #entries + 1, quality = mine, next = nextEntry, segment = segmentId }
end

-- Stars are market-relative (LAB_SPEC 0.3): #1 = 5 "MARKET LEADER", then by the rank's position p.
function LabPreview.stars(rank: number, total: number): (number, string)
	if rank <= 1 then
		return 5, "MARKET LEADER"
	end
	local p = (rank - 1) / math.max(1, total - 1)
	if p <= 0.25 then
		return 4, "EXCELLENT"
	elseif p <= 0.5 then
		return 3, "GOOD"
	elseif p <= 0.75 then
		return 2, "OKAY"
	end
	return 1, "CHALLENGER"
end

-- What a product line looks like for a model that does not exist yet.
function LabPreview.lineStatus(data: PlayerData, target: string): LineStatus
	local check = ModelMath.releaseCheck(data, "", target)
	local model = check.replaced[1]
	if model then
		local segment = LabPreview.segmentOf(target)
		return {
			kind = "LIVE",
			model = model,
			agedFit = MarketMath.fit(model.stats, segment) - ModelMath.ageFit(ModelMath.versionAge(model)),
			version = ModelMath.lineVersion(data, model.id),
			usedLines = check.usedLines,
			slots = check.slots,
		}
	end
	return { kind = if check.ok then "FREE" else "FULL", usedLines = check.usedLines, slots = check.slots }
end

function LabPreview.nextVersion(data: PlayerData, name: string): number
	return ModelMath.nextVersion(data, name)
end

-- Launch buzz of a campaign in the line's own audience (0..REACH.hypeMax).
function LabPreview.campaignBuzz(target: string, marketing: number): number
	return MarketMath.initialHype(target, marketing)[ModelMath.lineOf(target)] or 0
end

---------------------------------------------------------------------------- data plan (the casual bot's rule)

local function expectedFor(data: PlayerData, sel: Sel, stock: { [string]: DataStock }): (number, Stats)
	local size = ModelConfig.getSize(sel.sizeId) or ModelConfig.SIZES[1]
	local summary = ModelMath.dataSummary(stock)
	local stats, overall = ModelMath.computeStats(size.id, sel.focusId, summary, specOf(data), ModelMath.recipeFactor(size, summary, sel.recipeId), nil)
	stats, overall = EmpireMath.boostStats(stats, data.empire)
	return overall, stats
end

function LabPreview.reserve(data: PlayerData): number
	return math.max(1500, (tonumber(EmpireMath.bonuses(data.empire).wage) or 0) * 120)
end

-- Data packs to buy before training `sel`: budget 0.8 x (money - reserve - training cost), greedily the pack
-- with the best expected gain per dollar, until the gain drops below 0.3 points per $1,000 (at most 60 buys).
function LabPreview.dataPlan(data: PlayerData, sel: Sel, money: number): DataPlan
	local est = LabPreview.estimate(data, sel, nil)
	local budget = 0.8 * (money - LabPreview.reserve(data) - est.cost)
	local stock = ModelMath.copyStock(data.data)
	local packs: { [string]: number } = {}
	local order: { string } = {}
	local spent = 0
	local before = expectedFor(data, sel, stock)
	for _ = 1, 60 do
		local base = expectedFor(data, sel, stock)
		local bestPack: DataConfig.PackDef? = nil
		local bestGain = 0
		for _, pack in DataConfig.PACKS do
			if spent + pack.price <= budget then
				local copy = ModelMath.copyStock(stock)
				ModelMath.addTokens(copy, pack.type, pack.tokens, pack.quality)
				local gain = (expectedFor(data, sel, copy) - base) / pack.price
				if gain > bestGain then
					bestGain = gain
					bestPack = pack
				end
			end
		end
		if not bestPack or bestGain < 0.3 / 1000 then
			break
		end
		ModelMath.addTokens(stock, bestPack.type, bestPack.tokens, bestPack.quality)
		spent += bestPack.price
		if not packs[bestPack.id] then
			table.insert(order, bestPack.id)
		end
		packs[bestPack.id] = (packs[bestPack.id] or 0) + 1
	end
	local after, stats = expectedFor(data, sel, stock)
	local capped = ModelMath.capStats(table.clone(stats))
	local summary = ModelMath.dataSummary(stock)
	return {
		packs = packs,
		order = order,
		cost = spent,
		tokens = summary.total,
		quality = summary.quality,
		before = before,
		after = after,
		stats = capped,
		stock = stock,
	}
end

-- "2× Web Crawl Chunk + 2× Public Repos"
function LabPreview.planText(plan: DataPlan): string
	local parts: { string } = {}
	for _, id in plan.order do
		local pack = DataConfig.getPack(id)
		table.insert(parts, `{plan.packs[id]}× {if pack then pack.label else id}`)
	end
	return table.concat(parts, " + ")
end

-- The data after the plan as a PlayerData view (for the estimate the Review shows after the plan).
function LabPreview.withStock(data: PlayerData, stock: { [string]: DataStock }): PlayerData
	local copy = table.clone(data)
	copy.data = stock
	return copy
end

---------------------------------------------------------------------------- presets

-- Best expected overall over every size x training plan without a lock that fits the budget
-- (cash above the reserve; Save mode: 30 % of it). Ties: the cheaper one.
function LabPreview.bestAffordable(data: PlayerData, focusId: string, money: number, saveMode: boolean): Preset?
	local free = money - LabPreview.reserve(data)
	local budget = if saveMode then 0.3 * free else free
	local best: Preset? = nil
	for _, size in ModelConfig.SIZES do
		for _, recipe in ModelConfig.RECIPES do
			local est = LabPreview.estimate(data, { sizeId = size.id, focusId = focusId, recipeId = recipe.id }, nil)
			if est.lock == nil and est.cost <= budget then
				local current = best
				if not current or est.overall > current.estimate.overall + 1e-9 or (math.abs(est.overall - current.estimate.overall) <= 1e-9 and est.cost < current.estimate.cost) then
					best = { sizeId = size.id, recipeId = recipe.id, estimate = est }
				end
			end
		end
	end
	return best
end

-- Size and focus (and the plan, when the model saved it) of the newest model that is not training.
function LabPreview.sameAsLast(data: PlayerData): { sizeId: string, focusId: string, recipeId: string? }?
	for i = #data.modelOrder, 1, -1 do
		local model = data.models[data.modelOrder[i]]
		if model and model.status ~= "training" and ModelConfig.getSize(model.sizeId) and ModelConfig.getFocus(model.focusId) then
			local recipe = (model :: any).recipeId
			return {
				sizeId = model.sizeId,
				focusId = model.focusId,
				recipeId = if typeof(recipe) == "string" and ModelConfig.getRecipe(recipe) then recipe else nil,
			}
		end
	end
	return nil
end

-- The size and plan the suggestions use (SUGGESTED tile, line SUCCESSOR buttons, "Design its successor").
-- LAB_SPEC 8.1 step 4: with BEST I CAN AFFORD as the default, the --ui-defaults economy run moved the Startup Campus
-- more than 10 % later in 2 of 12 runs (agents/lab/BALANCE.md), so the suggestions use the economy bot's rule
-- (agents/corefix/sim.luau tryTrain), step by step: from the largest size down, the first one without a lock that the
-- servers can carry (serverFits), that the cash above the reserve pays for (Save mode: 30 % of it) and that, after
-- its data plan, beats the line's current model (overall minus age) by 3 points; then Deep when the data after the
-- plan is enough (half of the size's need, 60 % quality) and the cash left above the reserve pays for it. The data
-- plan is part of the suggestion: the Review offers it as BUY DATA PLAN before START (fix round 1: the 2-tap path
-- used to train on today's data while the gate assumed the plan). BEST I CAN AFFORD stays a visible preset.
export type SuccessorPick = { sizeId: string, recipeId: string, plan: DataPlan, current: number }

local function effective(model: ModelData?): number
	if not model then
		return 0
	end
	local market: any = model.market
	local vage = if typeof(market) == "table" then tonumber(market.vage) or 0 else 0
	return model.overall - ModelMath.ageFit(vage)
end

-- Server capacity check of the bot (sim.luau fits): a bigger size in a live line needs its extra serving units
-- for the line's users, a new line its share of today's load; both within 110 % of the capacity.
function LabPreview.serverFits(data: PlayerData, live: Types.LiveInfo?, target: string): (sizeId: string) -> boolean
	local units = MarketConfig.SERVE_UNITS
	local cap = if live and typeof(live.capacity) == "number" then live.capacity else math.huge
	local load = if live and typeof(live.load) == "number" then live.load else 0
	local nLive = 0
	local lineModel: ModelData? = nil
	for _, id in data.modelOrder do
		local m = data.models[id]
		if m and m.status == "live" then
			nLive += 1
			if not lineModel and m.release and m.release.target == target then
				lineModel = m
			end
		end
	end
	local lm = lineModel
	local lineUsers = if lm and lm.market then MarketMath.totalUsers(lm.market) else 0
	return function(sizeId: string): boolean
		local uNew = units[sizeId] or 1
		if lm then
			local uOld = units[lm.sizeId] or 1
			return uNew <= uOld or load + lineUsers * (uNew - uOld) <= cap * 1.1
		end
		return load + load / math.max(1, nLive) * uNew <= cap * 1.1
	end
end

function LabPreview.successorPick(data: PlayerData, live: Types.LiveInfo?, target: string, focusId: string, money: number, saveMode: boolean): SuccessorPick?
	local lineModel: ModelData? = nil
	local best: ModelData? = nil
	for _, id in data.modelOrder do
		local m = data.models[id]
		if m and m.status == "live" then
			if not lineModel and m.release and m.release.target == target then
				lineModel = m
			end
			if not best or m.overall > best.overall then
				best = m
			end
		end
	end
	local lm = lineModel
	local current = if lm then effective(lm) elseif best then math.max(0, effective(best) - 12) else 0
	local fits = LabPreview.serverFits(data, live, target)
	local reserve = LabPreview.reserve(data)
	for k = #ModelConfig.SIZES, 1, -1 do
		local size = ModelConfig.SIZES[k]
		local sel = { sizeId = size.id, focusId = focusId, recipeId = "steady" }
		local est = LabPreview.estimate(data, sel, nil)
		if (est.lock == nil or est.lock == "MONEY") and (fits(size.id) or k == 1) then
			local okBudget = money - reserve - est.cost >= 0
			if saveMode and est.cost > (money - reserve) * 0.3 then
				okBudget = false
			end
			if okBudget then
				local plan = LabPreview.dataPlan(data, sel, money)
				if plan.after >= current + 3 then
					local enough = plan.tokens >= size.dataNeed * 0.5 and plan.quality >= 0.6
					local deep = LabPreview.estimate(LabPreview.withStock(data, plan.stock), { sizeId = size.id, focusId = focusId, recipeId = "deep" }, nil)
					local recipeId = if enough and deep.lock == nil and money - plan.cost - reserve >= deep.cost then "deep" else "steady"
					return { sizeId = size.id, recipeId = recipeId, plan = plan, current = current }
				end
			end
		end
	end
	return nil
end

-- The Lab home's SUGGESTED tile (one model to train next) = the economy bot's line choice (sim.luau tryTrain): a free
-- product line first while the office allows more lines (in SUGGEST_ORDER, the bot's order), else the live line
-- whose model is weakest (overall minus age). Focus: the live model's focus, else the best fit for the line at the
-- largest size the GPUs and servers carry. Size, plan and data plan: successorPick. The --ui-defaults economy run
-- (agents/lab/sim.luau) calls this function and buys exactly the plan the Review then offers.
export type Suggestion = {
	kind: string, -- "successor" (a live line's next version) | "newline" (a free product line)
	target: string,
	model: ModelData?, -- the line's live model (successor)
	name: string?, -- successor: the live model's name (the next version); new line: nil
	focusId: string,
	sizeId: string,
	recipeId: string,
	pick: SuccessorPick?, -- nil = no size beats `current` by 3 with the cash above the reserve yet
	expected: number, -- expected overall of the suggestion, after its data plan
	current: number, -- what it must beat by 3: the line's model after age, or the best live model - 12
}
LabPreview.SUGGEST_ORDER = { "general", "developers", "students", "businesses" }

function LabPreview.suggest(data: PlayerData, live: Types.LiveInfo?, money: number, saveMode: boolean): Suggestion?
	if LabPreview.isFirstModel(data) then
		return nil -- DESIGN NEW MODEL is the first model's path (LAB_SPEC 4.9)
	end
	local lives: { ModelData } = {}
	local best: ModelData? = nil
	for _, id in data.modelOrder do
		local m = data.models[id]
		if m and m.status == "live" and m.release then
			table.insert(lives, m)
			if not best or m.overall > best.overall then
				best = m
			end
		end
	end
	local function liveIn(target: string): ModelData?
		local line = ModelMath.lineOf(target)
		for _, m in lives do
			local release = m.release
			if release and ModelMath.lineOf(release.target) == line then
				return m
			end
		end
		return nil
	end
	local target: string? = nil
	local current = 0
	local lineModel: ModelData? = nil
	if #lives < ModelMath.productSlots(data.empire.office) then
		for _, t in LabPreview.SUGGEST_ORDER do
			if ModelConfig.getLine(t) and not liveIn(t) then
				target = t
				break
			end
		end
		if target and best then
			current = math.max(0, effective(best) - 12)
		end
	end
	if not target then
		local worst: ModelData? = nil
		for _, m in lives do
			if not worst or effective(m) < effective(worst) then
				worst = m
			end
		end
		local w = worst
		if w and w.release then
			target = w.release.target
			current = effective(w)
			lineModel = w
		end
	end
	local t = target
	if not t then
		return nil
	end
	local fleet = ModelMath.fleet(data.gpus)
	local fits = LabPreview.serverFits(data, live, t)
	local probe = "s100m"
	for k = #ModelConfig.SIZES, 1, -1 do
		local size = ModelConfig.SIZES[k]
		if size.vram <= fleet.vram and (size.id ~= "s7b" or data.empire.research.frontier) and fits(size.id) then
			probe = size.id
			break
		end
	end
	local focusId = LabPreview.bestFocus(data, probe, "steady", t)
	local lm = lineModel
	if lm and ModelConfig.getFocus(lm.focusId) then
		focusId = lm.focusId
	end
	local pick = LabPreview.successorPick(data, live, t, focusId, money, saveMode)
	local sizeId = if pick then pick.sizeId elseif lm and ModelConfig.getSize(lm.sizeId) then lm.sizeId else probe
	local recipeId = if pick then pick.recipeId else "steady"
	local sel: Sel = { sizeId = sizeId, focusId = focusId, recipeId = recipeId }
	local view = if pick and pick.plan.cost > 0 then LabPreview.withStock(data, pick.plan.stock) else data
	return {
		kind = if lm then "successor" else "newline",
		target = t,
		model = lm,
		name = if lm then lm.name else nil,
		focusId = focusId,
		sizeId = sizeId,
		recipeId = recipeId,
		pick = pick,
		expected = LabPreview.estimate(view, sel, nil).overall,
		current = current,
	}
end

-- What a line's SUCCESSOR button (and "Design its successor") prefills: the live model's name and focus, the size,
-- plan and data plan of successorPick (nil pick: the live model's size, Standard, no plan).
function LabPreview.lineSuccessor(data: PlayerData, live: Types.LiveInfo?, target: string, money: number, saveMode: boolean): Suggestion?
	local status = LabPreview.lineStatus(data, target)
	local model = status.model
	if not model then
		return nil
	end
	local focusId = if ModelConfig.getFocus(model.focusId) then model.focusId else "balanced"
	local pick = LabPreview.successorPick(data, live, target, focusId, money, saveMode)
	local sizeId = if pick then pick.sizeId elseif ModelConfig.getSize(model.sizeId) then model.sizeId else "s100m"
	local recipeId = if pick then pick.recipeId else "steady"
	local view = if pick and pick.plan.cost > 0 then LabPreview.withStock(data, pick.plan.stock) else data
	return {
		kind = "successor",
		target = target,
		model = model,
		name = model.name,
		focusId = focusId,
		sizeId = sizeId,
		recipeId = recipeId,
		pick = pick,
		expected = LabPreview.estimate(view, { sizeId = sizeId, focusId = focusId, recipeId = recipeId }, nil).overall,
		current = effective(model),
	}
end

-- Studio prefill of a suggestion (DesignSteps.show reads it; `plan` is offered on the Review as BUY DATA PLAN).
function LabPreview.prefillOf(s: Suggestion): { [string]: any }
	local pick = s.pick
	return {
		target = s.target,
		name = s.name,
		sizeId = s.sizeId,
		focusId = s.focusId,
		recipeId = s.recipeId,
		plan = if pick and pick.plan.cost > 0 then pick.plan else nil,
		current = s.current,
	}
end

---------------------------------------------------------------------------- refinement

-- The checks of AIModelService.improveModel in its order, with a short reason for the button.
function LabPreview.refineCheck(data: PlayerData, model: ModelData, money: number): RefineCheck
	local runs = math.max(0, math.floor(tonumber(model.iterations) or 0))
	local function no(err: string, reason: string, cost: number?): RefineCheck
		return { ok = false, err = err, reason = reason, cost = cost, runs = runs }
	end
	if data.training then
		return no("TRAINING_ACTIVE", "Training slot busy")
	end
	if model.status ~= "trained" and model.status ~= "live" then
		return no("BAD_MODEL", "Not available")
	end
	if runs >= ModelConfig.REFINE.limit then
		return no("REFINE_LIMIT", `Refined {runs}/{ModelConfig.REFINE.limit}`)
	end
	local summary = ModelMath.dataSummary(data.data)
	local need = model.dataUsed.total + 1e8 - summary.total
	if summary.total < model.dataUsed.total + 1e8 then
		local tokens = math.ceil(need / 1e8) * 1e8
		local text = if tokens >= 1e9 then string.format("%.1fB", tokens / 1e9) else string.format("%dM", math.floor(tokens / 1e6 + 0.5))
		return no("NEW_DATA", `needs {text} new tokens`)
	end
	local size = ModelConfig.getSize(model.sizeId)
	if not size then
		return no("BAD_MODEL", "Not available")
	end
	local plan = ModelMath.plan(size, ModelMath.fleet(data.gpus), summary)
	if not plan.ok then
		local reason = if plan.reason == "VRAM" then "needs more VRAM" elseif plan.reason == "NO_GPU" then "needs a GPU" else "needs data"
		return no(plan.reason or "NO_DATA", reason)
	end
	local refine = ModelMath.refinePlan(model, plan)
	if money < refine.cost then
		return no("NO_MONEY", "needs more cash", refine.cost)
	end
	return { ok = true, cost = refine.cost, runs = runs }
end

---------------------------------------------------------------------------- texts and odds

-- Chance that a run pauses for a decision and that it gets the breakthrough (+5 %), for a company spec.
function LabPreview.eventOdds(specId: string): (number, number)
	local spec = CompanyConfig.getSpec(specId)
	local mult = if spec and spec.breakthroughMult then spec.breakthroughMult else 1
	local total, decisions, boost = 0, 0, 0
	for _, event in ModelConfig.EVENTS do
		local w = event.weight * (if event.id == "breakthrough" then mult else 1)
		total += w
		if event.choices then
			decisions += w
		end
		if event.id == "breakthrough" then
			boost += w
		end
	end
	local chance = ModelConfig.TRAINING.eventChance
	if total <= 0 then
		return 0, 0
	end
	return chance * decisions / total, chance * boost / total
end

-- "3 in 10 runs pause for a decision · 1 in 10 get +5 %"
function LabPreview.oddsText(specId: string): string
	local decision, boost = LabPreview.eventOdds(specId)
	local breakthrough = ModelConfig.getEvent("breakthrough")
	local plus = if breakthrough and breakthrough.quality then math.floor((breakthrough.quality - 1) * 100 + 0.5) else 5
	return `{math.floor(decision * 10 + 0.5)} in 10 runs pause for a decision · {math.floor(boost * 10 + 0.5)} in 10 get +{plus} %`
end

function LabPreview.breakdown(data: PlayerData, sel: Sel): Breakdown
	local size = ModelConfig.getSize(sel.sizeId) or ModelConfig.SIZES[1]
	local summary = ModelMath.dataSummary(data.data)
	local readiness = ModelMath.readiness(size, summary)
	local spec = CompanyConfig.getSpec(specOf(data))
	local bonus = 0
	if spec and spec.statBonus then
		for _, v in spec.statBonus do
			bonus = math.max(bonus, v)
		end
	end
	local b = EmpireMath.bonuses(data.empire)
	return {
		potential = size.potential,
		quantity = readiness.quantity,
		quality = readiness.quality,
		recipeFactor = ModelMath.recipeFactor(size, summary, sel.recipeId),
		focusId = sel.focusId,
		spec = specOf(data),
		specBonus = bonus,
		core = tonumber(b.core) or 0,
		reliabilityBonus = tonumber(b.reliability) or 0,
		cap = ModelConfig.STAT_CAP,
	}
end

-- "spec +6 Coding", "spec +2 each skill", "spec +6 Efficiency (not in Overall)" (CompanyConfig statBonus by stat).
function LabPreview.specBonusText(specId: string): string
	local spec = CompanyConfig.getSpec(specId)
	local bonus: { [string]: number } = if spec and spec.statBonus then spec.statBonus else {}
	local core: { string } = {}
	for _, stat in ModelConfig.STATS do
		if stat.weight > 0 then
			table.insert(core, stat.id)
		end
	end
	local first = bonus[core[1]]
	local same = first ~= nil and first > 0
	for _, id in core do
		if bonus[id] ~= first then
			same = false
		end
	end
	if same then
		return `spec +{first} each skill`
	end
	type Part = { label: string, value: number, core: boolean }
	local parts: { Part } = {}
	for _, stat in ModelConfig.STATS do
		local v = bonus[stat.id]
		if v and v > 0 then
			table.insert(parts, { label = stat.label, value = v, core = stat.weight > 0 })
		end
	end
	if #parts == 0 then
		return "no spec bonus"
	end
	table.sort(parts, function(a: Part, b: Part): boolean
		return a.value > b.value
	end)
	local out: { string } = {}
	for i = 1, math.min(2, #parts) do
		local p = parts[i]
		table.insert(out, `+{p.value} {p.label}` .. (if p.core then "" else " (not in Overall)"))
	end
	return "spec " .. table.concat(out, ", ")
end

-- Deep's data check (ModelMath.recipeFactor: x0.68 below half of the size's data need or below 60 % quality):
-- nil when the data is enough, else the short reason for the tile ("Needs 60% quality", "Needs 750M data").
function LabPreview.deepShort(sizeId: string, summary: Types.DataSummary): string?
	local size = ModelConfig.getSize(sizeId) or ModelConfig.SIZES[1]
	local half = size.dataNeed * 0.5
	local lowData = summary.total < half
	local lowQuality = summary.quality < 0.6
	local tokens = Format.tokens
	if lowData and lowQuality then
		return `Needs {tokens(half)} at 60%`
	elseif lowQuality then
		return "Needs 60% quality"
	elseif lowData then
		return `Needs {tokens(half)} data`
	end
	return nil
end

-- Highest expected overall `sel` can reach with ideal data (the data the size can still use, maxFill x dataNeed,
-- at 100 % quality): the desktop spec sheet's "Ceiling". Searched over every mix of the data types in tenth steps
-- plus today's mix (so the ceiling is never below what the Studio shows: more data and 100 % quality only raise
-- each stat before the cap). The data mix, focus, plan, company spec, research and Lab level all count (the old
-- "Max score" printed the size's raw potential, which the bonuses exceed). Cached by its inputs (66 estimates).
local ceilingKey = ""
local ceilingValue = 0
function LabPreview.ceiling(data: PlayerData, sel: Sel): number
	local size = ModelConfig.getSize(sel.sizeId) or ModelConfig.SIZES[1]
	local total = size.dataNeed * ModelConfig.DATA.maxFill
	local types = DataConfig.TYPES
	local n = #types
	local summary = ModelMath.dataSummary(data.data)
	local bonus = EmpireMath.bonuses(data.empire)
	local shareKeys: { string } = {}
	for _, t in types do
		table.insert(shareKeys, string.format("%.4f", summary.shares[t.id] or 0))
	end
	local key = `{size.id}|{sel.focusId}|{sel.recipeId}|{specOf(data)}|{bonus.core}|{bonus.reliability}|{table.concat(shareKeys, ",")}`
	if key == ceilingKey then
		return ceilingValue
	end
	local best = 0
	local function try(weights: { number })
		local stock: { [string]: DataStock } = {}
		for i, w in weights do
			if w > 0 then
				stock[types[i].id] = { tokens = total * w, quality = 1 }
			end
		end
		local est = LabPreview.estimate(LabPreview.withStock(data, stock), sel, nil)
		if est.overall > best then
			best = est.overall
		end
	end
	-- every composition of 10 tenths over the n types
	local w = table.create(n, 0)
	local function walk(i: number, left: number)
		if i == n then
			w[i] = left / 10
			try(w)
			return
		end
		for k = 0, left do
			w[i] = k / 10
			walk(i + 1, left - k)
		end
	end
	if n > 0 then
		walk(1, 10)
	end
	-- today's mix at the ideal amount and quality
	if summary.total > 0 then
		local mix = table.create(n, 0)
		for i, t in types do
			mix[i] = summary.shares[t.id] or 0
		end
		try(mix)
	end
	ceilingKey, ceilingValue = key, best
	return best
end

-- Best non-training overall of the company (optionally without one model).
function LabPreview.bestOverall(data: PlayerData, exceptId: string?): number
	local best = 0
	for id, model in data.models do
		if id ~= exceptId and model.status ~= "training" then
			best = math.max(best, model.overall)
		end
	end
	return best
end

-- Best value of each core stat over the company's models (the white ticks on the stat bars).
function LabPreview.bestStats(data: PlayerData): Stats
	local out: Stats = {}
	for _, model in data.models do
		if model.status ~= "training" then
			for id, v in model.stats do
				if v > (out[id] or 0) then
					out[id] = v
				end
			end
		end
	end
	return out
end

-- The first model of a company: nothing trained yet and nothing but a training model in the save.
function LabPreview.isFirstModel(data: PlayerData): boolean
	if (tonumber(data.stats.modelsTrained) or 0) > 0 then
		return false
	end
	for _, model in data.models do
		if model.status ~= "training" then
			return false
		end
	end
	return true
end

return LabPreview
