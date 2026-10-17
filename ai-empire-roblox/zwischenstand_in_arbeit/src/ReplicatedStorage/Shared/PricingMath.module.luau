--!strict
-- Release forecast, "Recommended" price and auto-price (CORE_SPEC 7.7). Pure functions, no services: the
-- server (AIModelService.releaseModel, PricingService) and the client (LabApp, MarketApp) run the same code on
-- the same inputs, so the Lab shows what the server will pick. The market itself is MarketMath.tick; this
-- module only plays it forward on copies (exactly like the economy simulator's portfolioProfit):
--   profit of the WHOLE own portfolio over `seconds`, with the candidate live in its product line (it replaces
--   the line's live model), against the rivals as MarketService passes them, at the company's stage, serving
--   capacity and reach cap, valued with the company's revenue and serving multipliers.
-- Deterministic: menus are scanned in a fixed order, the first best price wins, inputs are ordered lists.

local Shared = script.Parent
local Config = Shared.Config
local MarketConfig = require(Config.MarketConfig)
local ModelConfig = require(Config.ModelConfig)
local MarketMath = require(Shared.MarketMath)
local ModelMath = require(Shared.ModelMath)
local EmpireMath = require(Shared.EmpireMath)
local Types = require(Shared.Types)

type ModelData = Types.ModelData
type PlayerData = Types.PlayerData
type MarketState = Types.MarketState
type LiveModelResult = Types.LiveModelResult

-- One product as MarketMath.tick sees it (MarketMath.LiveEntry + the release target; rivals also carry
-- `player` and `company` like MarketService.entry).
export type Entry = {
	id: string,
	stats: Types.Stats,
	sizeId: string,
	subPrice: number,
	apiPrice: number,
	market: any,
	target: string?,
	player: boolean?,
	company: any?,
}

export type Context = {
	own: { Entry }, -- every live model of the company (real market states; copied before each run)
	rivals: { Entry }, -- NPC labs and other companies (never mutated)
	npcModels: any?, -- as MarketService: {} while NPC labs run as sessions, nil = static MarketConfig.NPC_MODELS
	reputation: number,
	spec: string,
	opts: any, -- MarketMath.tick opts: stage, capacity, reachCap
	revenueMult: number,
	servingMult: number,
}

export type Choice = { sub: number, api: number, profit: number }

-- What a forecast needs to know about the priced model (a ModelData fits).
export type Product = { id: string, stats: Types.Stats, sizeId: string }

local PricingMath = {}

-- CompanyOps (econ package) provides serving capacity and the reach cap. Looked up lazily so this module also
-- loads in a tree without it (then the market runs uncapped, as MarketService does without it).
local opsModule: any = nil
local function companyOps(): any
	if opsModule == nil then
		local found = Shared:FindFirstChild("CompanyOps")
		if found and found:IsA("ModuleScript") then
			local ok, result = pcall(require, found)
			opsModule = if ok then result else false
		else
			return nil -- not there (yet): look again next time
		end
	end
	return if opsModule then opsModule else nil
end

local function emptyMarket(age: number?, vage: number?): any
	return { age = age or 0, vage = vage, users = {}, organic = {}, hype = {}, revenueTotal = 0, peakUsers = 0 }
end

function PricingMath.cloneMarket(m: any): any
	if typeof(m) ~= "table" then
		return emptyMarket(0, 0)
	end
	return {
		age = tonumber(m.age) or 0,
		vage = m.vage,
		users = if typeof(m.users) == "table" then table.clone(m.users) else {},
		organic = if typeof(m.organic) == "table" then table.clone(m.organic) else {},
		hype = if typeof(m.hype) == "table" then table.clone(m.hype) else {},
		revenueTotal = 0,
		peakUsers = 0,
	}
end

-- Entry of a live model (its real market state unless `market` is given).
function PricingMath.entry(model: ModelData, market: any?): Entry
	local release = model.release
	return {
		id = model.id,
		stats = model.stats,
		sizeId = model.sizeId,
		subPrice = if release then release.subPrice else 0,
		apiPrice = if release then release.apiPrice else MarketConfig.API_PRICE.default,
		market = market or model.market,
		target = if release then release.target else nil,
	}
end

-- Rival entry from a live model of another session (server side), flagged like MarketService.entry.
function PricingMath.rivalEntry(model: ModelData, isNPC: boolean, company: any): Entry
	local release = model.release
	local market: any = model.market
	return {
		id = model.id,
		stats = model.stats,
		sizeId = model.sizeId,
		subPrice = if release then release.subPrice else 0,
		apiPrice = if release then release.apiPrice else MarketConfig.API_PRICE.default,
		-- only the version age is read from a rival's market; a light copy keeps the real state untouched
		market = emptyMarket(if market then market.age else 0, if market then market.vage else nil),
		target = if release then release.target else nil,
		player = not isNPC,
		company = company,
	}
end

-- Canonical rival order: (company id, model id). Server and client sort the same way (floating-point sums of
-- the market depend on the order), so both pick the same price.
function PricingMath.sortRivals(list: { Entry })
	table.sort(list, function(a: Entry, b: Entry): boolean
		local ca, cb = tonumber(a.company) or 0, tonumber(b.company) or 0
		if ca ~= cb then
			return ca < cb
		end
		return a.id < b.id
	end)
end

-- Rival entries from the replicated marketplace offers (client side). Offers carry target/npc/vage once the
-- econ package adds them (design/requests/models.md 1); before that NPC = negative provider id.
function PricingMath.rivalsFromOffers(offers: any, own: { [string]: any }): { Entry }
	local list: { Entry } = {}
	if typeof(offers) ~= "table" then
		return list
	end
	for _, offer in offers do
		if typeof(offer) == "table" and typeof(offer.id) == "string" and own[offer.id] == nil and typeof(offer.stats) == "table" then
			local provider = tonumber(offer.providerId) or 0
			local npc = if typeof(offer.npc) == "boolean" then offer.npc else provider < 0
			table.insert(list, {
				id = offer.id,
				stats = offer.stats,
				sizeId = if typeof(offer.sizeId) == "string" then offer.sizeId else "s500m",
				subPrice = tonumber(offer.sub) or 0,
				apiPrice = tonumber(offer.api) or MarketConfig.API_PRICE.default,
				market = emptyMarket(0, tonumber(offer.vage)),
				target = if typeof(offer.target) == "string" then offer.target else nil,
				player = not npc,
				company = provider,
			})
		end
	end
	PricingMath.sortRivals(list)
	return list
end

-- The forecast context of a company. `rivals` from PricingService.rivals (server) or rivalsFromOffers (client).
function PricingMath.context(data: PlayerData, rivals: { Entry }, npcModels: any?): Context
	local e = data.empire
	local company = data.company
	local bonuses = EmpireMath.bonuses(e)
	-- exactly the opts MarketService.tick passes (stage clamped to the stage table, reach cap fallback REACH.max)
	local stageReach = (MarketConfig :: any).STAGE_REACH
	local stages = if typeof(stageReach) == "table" and #stageReach > 0 then #stageReach else 1
	local stage = math.clamp(math.floor(tonumber(e.office) or 1), 1, stages)
	local opts: any = { stage = stage }
	local ops = companyOps()
	if ops and typeof(ops.capacity) == "function" and typeof(ops.reachCap) == "function" then
		opts.capacity = ops.capacity(data)
		opts.reachCap = ops.reachCap(data, (if typeof(stageReach) == "table" then stageReach[stage] else nil) or MarketConfig.REACH.max)
	end
	-- own markets are copied: a context is a snapshot, so a forecast that runs over several frames depends only
	-- on the state when it started
	local own: { Entry } = {}
	for _, id in data.modelOrder do
		local model = data.models[id]
		if model and model.status == "live" and model.release and model.market then
			table.insert(own, PricingMath.entry(model, PricingMath.cloneMarket(model.market)))
		end
	end
	return {
		own = own,
		rivals = rivals,
		npcModels = npcModels,
		reputation = if company then company.reputation else 0,
		spec = if company then company.spec else "general",
		opts = opts,
		revenueMult = tonumber(bonuses.revenue) or 1,
		servingMult = tonumber(bonuses.serving) or 1,
	}
end

-- Market state of a model at release: launch hype from marketing, version age 0 and, when the line already
-- has a live model, the predecessor's users x ModelConfig.MIGRATE per segment plus its word of mouth
-- (CORE_SPEC 7.2). AIModelService.releaseModel uses exactly this, and so does the forecast.
function PricingMath.releaseMarket(target: string, marketing: number, replaced: { ModelData }): MarketState
	local market: any = MarketMath.newMarketState(target, marketing)
	market.vage = 0
	for _, old in replaced do
		local om: any = old.market
		if typeof(om) == "table" then
			if typeof(om.users) == "table" then
				for segment, n in om.users do
					if typeof(n) == "number" and n == n and n > 0 and n < math.huge then
						market.users[segment] = (market.users[segment] or 0) + n * ModelConfig.MIGRATE
					end
				end
			end
			if typeof(om.organic) == "table" then
				for segment, o in om.organic do
					if typeof(o) == "number" and o == o and o > 0 and o < math.huge then
						market.organic[segment] = (market.organic[segment] or 0) + o
					end
				end
			end
		end
	end
	return market
end

-- A forecast in progress (one candidate, one price): the market list, the steps done and the profit so far.
-- PricingService advances runs a few market ticks per frame; PricingMath.profit runs one to the end.
export type Run = {
	ctx: Context,
	list: { Entry },
	candidateId: string,
	steps: number, -- market ticks in total
	done: number, -- market ticks done
	total: number, -- profit so far ($)
	last: any, -- last MarketMath.tick result
}

-- Starts a forecast: the candidate replaces its own entry and every live model of its line; the other own lines
-- run on copies of their (snapshot) market states. candidate.market is advanced in place.
function PricingMath.newRun(ctx: Context, candidate: Entry, seconds: number): Run
	local line = ModelMath.lineOf(candidate.target)
	local list: { Entry } = { candidate }
	for _, entry in ctx.own do
		if entry.id ~= candidate.id and ModelMath.lineOf(entry.target) ~= line then
			table.insert(list, {
				id = entry.id,
				stats = entry.stats,
				sizeId = entry.sizeId,
				subPrice = entry.subPrice,
				apiPrice = entry.apiPrice,
				market = PricingMath.cloneMarket(entry.market),
				target = entry.target,
			})
		end
	end
	return {
		ctx = ctx,
		list = list,
		candidateId = candidate.id,
		steps = math.max(1, math.floor(seconds / ModelConfig.PRICING.step)),
		done = 0,
		total = 0,
		last = nil,
	}
end

-- Advances a run by at most `maxTicks` market ticks of PRICING.step seconds. Returns true when it is finished.
function PricingMath.stepRun(run: Run, maxTicks: number): boolean
	local ctx = run.ctx
	local step = ModelConfig.PRICING.step
	local tick: any = MarketMath.tick -- 7th argument (opts) exists in the CORE_SPEC market tick
	local stop = math.min(run.steps, run.done + math.max(1, math.floor(maxTicks)))
	while run.done < stop do
		local last = tick(run.list, ctx.reputation, ctx.spec, step, ctx.rivals, ctx.npcModels, ctx.opts)
		run.total += (last.revenue * ctx.revenueMult - last.cost * ctx.servingMult) * step
		run.last = last
		run.done += 1
	end
	return run.done >= run.steps
end

-- Total profit ($) of the own portfolio over the run, the candidate's result in the last step (per second) and
-- the last full MarketMath result (capacity, load, waitlist ...).
function PricingMath.runResult(run: Run): (number, LiveModelResult, any)
	local last = run.last
	local mine: LiveModelResult = (last and last.perModel[run.candidateId]) or { users = 0, revenue = 0, cost = 0 }
	return run.total, mine, last
end

-- Plays the market forward: total profit ($) of the own portfolio over `seconds` with `candidate` live, the
-- candidate's result in the last step (per second) and the last full MarketMath result (capacity, waitlist ...).
-- pause (optional) runs after every market tick (use PricingMath.slicer to yield only when a frame budget is
-- used up). The result does not depend on where the forecast pauses.
function PricingMath.profit(ctx: Context, candidate: Entry, seconds: number, pause: (() -> ())?): (number, LiveModelResult, any)
	local run = PricingMath.newRun(ctx, candidate, seconds)
	while not PricingMath.stepRun(run, 1) do
		if pause then
			pause()
		end
	end
	return PricingMath.runResult(run)
end

-- A pause function for long forecasts: calls `yield` (e.g. task.wait) whenever `budget` seconds of CPU time
-- have passed since the last yield, so one frame never spends more than about `budget` on the forecast.
function PricingMath.slicer(budget: number, yield: () -> ()): () -> ()
	local start = os.clock()
	return function()
		if os.clock() - start >= budget then
			yield()
			start = os.clock()
		end
	end
end

-- The price menu in scan order (subs outer, apis inner): ties keep the earlier entry.
PricingMath.MENU = {} :: { { sub: number, api: number } }
for _, sub in ModelConfig.PRICING.subs do
	for _, api in ModelConfig.PRICING.apis do
		table.insert(PricingMath.MENU, { sub = sub, api = api })
	end
end

-- The candidate entry of `model` at one menu price, live in line `target`, on a copy of `market`.
function PricingMath.candidate(model: Product, target: string, market: any, sub: number, api: number): Entry
	return {
		id = model.id,
		stats = model.stats,
		sizeId = model.sizeId,
		subPrice = sub,
		apiPrice = api,
		market = PricingMath.cloneMarket(market),
		target = target,
	}
end

-- Forecast value of one menu price for `model` live in line `target`, starting from a copy of `market`.
function PricingMath.tryPrice(ctx: Context, model: Product, target: string, market: any, sub: number, api: number, seconds: number, pause: (() -> ())?): number
	return (PricingMath.profit(ctx, PricingMath.candidate(model, target, market, sub, api), seconds, pause))
end

-- Best price on the menu for `model` live in line `target`, starting from `market` (copied for every try), over
-- `seconds`. Ties keep the first price in menu order. `pause` (optional) runs after every market tick: the
-- server and the client pass a PricingMath.slicer to spread the work over frames.
function PricingMath.best(ctx: Context, model: Product, target: string, market: any, seconds: number, pause: (() -> ())?): Choice
	local best: Choice = { sub = PricingMath.MENU[1].sub, api = PricingMath.MENU[1].api, profit = -math.huge }
	for _, price in PricingMath.MENU do
		local value = PricingMath.tryPrice(ctx, model, target, market, price.sub, price.api, seconds, pause)
		if value > best.profit then
			best = { sub = price.sub, api = price.api, profit = value }
		end
	end
	return best
end

-- Recommended release price (CORE_SPEC 7.7): best menu price over PRICING.releaseHorizon for the release
-- market (`marketing` already chosen), the line's predecessor migrated.
function PricingMath.recommend(ctx: Context, data: PlayerData, model: ModelData, target: string, marketing: number, pause: (() -> ())?): Choice
	local check = ModelMath.releaseCheck(data, model.id, target)
	local market = PricingMath.releaseMarket(target, marketing, check.replaced)
	return PricingMath.best(ctx, model, target, market, ModelConfig.PRICING.releaseHorizon, pause)
end

-- Marketing the Recommended release pre-selects: up to PRICING.marketingMax of the cash above a reserve of
-- two minutes of payroll (at least $1,500), in MARKETING steps (the simulator's casual release rule).
function PricingMath.recommendedMarketing(money: number, wagePerSecond: number): number
	local step = MarketConfig.MARKETING.step
	local reserve = math.max(1500, wagePerSecond * 120)
	local free = math.max(0, money - reserve)
	return math.max(0, math.min(ModelConfig.PRICING.marketingMax, math.floor(free / step) * step))
end

-- The price that matters for a line: subscription for Consumer Chat / Study App, API for the API lines.
function PricingMath.lineUsesSub(target: string?): boolean
	local line = ModelMath.lineOf(target)
	for _, segment in MarketConfig.SEGMENTS do
		if segment.id == line then
			return segment.priceKind == "sub"
		end
	end
	return true
end

local function priceText(isSub: boolean, value: number): string
	if isSub then
		return if value == 0 then "free" else "$" .. tostring(value)
	end
	return string.format("$%s per 1M tokens", if value % 1 == 0 then tostring(value) else string.format("%.2f", value))
end

-- One-line reason for an automatic price change, e.g. "Servers 97 % full → Consumer Chat price raised to $10".
-- load/capacity from the last market tick (nil when unknown).
function PricingMath.explain(target: string?, oldSub: number, oldApi: number, newSub: number, newApi: number, load: number?, capacity: number?): string
	local line = ModelConfig.getLine(target)
	local name = if line then line.label else "Model"
	local isSub = PricingMath.lineUsesSub(target)
	local old, new = if isSub then oldSub else oldApi, if isSub then newSub else newApi
	if old == new then
		-- only the secondary price moved (e.g. the API price of the chat app)
		isSub = not isSub
		old, new = if isSub then oldSub else oldApi, if isSub then newSub else newApi
	end
	local full = if load and capacity and capacity > 0 and load < math.huge then load / capacity else nil
	if new > old then
		if full and full >= 0.9 then
			return string.format("Servers %d %% full → %s price raised to %s", math.floor(math.min(full, 9.99) * 100 + 0.5), name, priceText(isSub, new))
		end
		return string.format("%s price raised to %s: the forecast earns more at this price", name, priceText(isSub, new))
	end
	return string.format("%s price lowered to %s to win more users", name, priceText(isSub, new))
end

return PricingMath
