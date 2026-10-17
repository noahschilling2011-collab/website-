--!strict
-- Server side of model pricing (CORE_SPEC 7.7, 8.1 "Pricing"): the Recommended release price and auto-price.
-- The math is Shared/PricingMath (the Lab app runs the same code for its preview); this module only gathers
-- the live inputs (rivals exactly as MarketService passes them) and schedules the work.
--
-- Auto-price: every ModelConfig.PRICING.autoPeriod seconds of a session, each live model whose
-- model.release.auto is not false gets the forecast-best menu price over autoHorizon seconds.
--   * AIModelService.tick -> PricingService.tick only schedules: it queues the models of a due cycle and starts a
--     job from a SNAPSHOT of the inputs (own markets, rivals, stage, capacity), so the result depends only on
--     the state at that moment. The first cycle runs PRICING.autoFirst (150) seconds after the company starts
--     ticking (founding, or the login of a founded company), then every autoPeriod: the design bot's phase.
--   * A Heartbeat worker (PricingService.frame) advances the jobs of the whole server a few market ticks per
--     frame within PRICING.frameBudget seconds of CPU, so frames stay flat even with 12 full companies.
--   * A finished job applies its price (only if the model is still live and on auto) and writes a one-line
--     reason to session.live.pricing[modelId] and the company news feed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ModelConfig = require(ReplicatedStorage.Shared.Config.ModelConfig)
local PricingMath = require(ReplicatedStorage.Shared.PricingMath)
local ModelMath = require(ReplicatedStorage.Shared.ModelMath)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(script.Parent.Parent.Lib.ServerTypes)
local SessionService = require(script.Parent.SessionService)
local NPCService = require(script.Parent.NPCService)
local CompanyOps = require(ReplicatedStorage.Shared.CompanyOps)

type Session = ServerTypes.Session
type ModelData = Types.ModelData

type Job = {
	modelId: string,
	product: PricingMath.Product, -- id, stats and size when the job started
	target: string,
	ctx: PricingMath.Context,
	market: any, -- copy of the model's market when the job started
	index: number, -- PricingMath.MENU entry of `run`
	run: PricingMath.Run?, -- forecast of that menu price in progress
	best: PricingMath.Choice,
}

type State = {
	due: number, -- seconds since the last auto-price cycle started
	queue: { string }, -- model ids still to evaluate in this cycle
	auto: { [string]: boolean }, -- last seen auto flag per live model (a switch to "on" re-prices at once)
	job: Job?, -- forecast in progress
}

local PricingService = {}

local P = ModelConfig.PRICING
local states: { [any]: State } = setmetatable({}, { __mode = "k" }) :: any
-- sessions with a job, in the order their jobs started (the worker serves them round-robin)
local active: { any } = {}
local cursor = 1

-- counters for tests and the admin panel
PricingService.stats = { jobs = 0, runs = 0, ticks = 0, applied = 0 }

local function stateOf(session: Session): State
	local state = states[session]
	if not state then
		-- first cycle PRICING.autoFirst seconds after the company starts ticking (CORE_SPEC 9: the first live
		-- model, released at ~1.3 min, is re-priced at 2.5 min), then every autoPeriod. Sessions that start
		-- together share the phase; the Heartbeat worker spreads their jobs over frames anyway.
		local first = math.clamp(tonumber((P :: any).autoFirst) or 150, 0, P.autoPeriod)
		state = { due = P.autoPeriod - first, queue = {}, auto = {} }
		states[session] = state
	end
	return state
end

-- NPC lab models count as full rivals; MarketService passes {} as the static NPC list while they run.
local function npcModels(): any?
	return if #NPCService.sessions > 0 then {} else nil
end

-- Every live model of every other company (players with a company, NPC labs), flagged as MarketService.entry
-- does (target, player, company). Ordered by (user id, model id) - the same order PricingMath.rivalsFromOffers
-- gives the client, so both sides sum the market in the same order and pick the same price.
function PricingService.rivals(session: Session): { PricingMath.Entry }
	local sessions: { any } = {}
	for _, other in SessionService.all() do
		if other ~= session and not other.closed and other.data.company then
			table.insert(sessions, other)
		end
	end
	for _, npc in NPCService.sessions do
		table.insert(sessions, npc)
	end
	local list: { PricingMath.Entry } = {}
	for _, other in sessions do
		local data = other.data
		for _, id in data.modelOrder do
			local model = data.models[id]
			if model and model.status == "live" and model.release and model.market then
				table.insert(list, PricingMath.rivalEntry(model, other.isNPC == true, other.userId))
			end
		end
	end
	PricingMath.sortRivals(list)
	return list
end

function PricingService.context(session: Session): PricingMath.Context
	return PricingMath.context(session.data, PricingService.rivals(session), npcModels())
end

-- Recommended (sub, api) for releasing `model` into `target` with `marketing` (CORE_SPEC 7.7).
-- spread = true yields a frame whenever PRICING.releaseBudget of CPU is used (the caller must re-check its state
-- afterwards); the inputs are a snapshot, so the price does not depend on how the work was spread.
function PricingService.recommend(session: Session, model: ModelData, target: string, marketing: number, spread: boolean?): PricingMath.Choice
	local pause = if spread then PricingMath.slicer(P.releaseBudget, function()
		task.wait()
	end) else nil
	local product: PricingMath.Product = { id = model.id, stats = table.clone(model.stats), sizeId = model.sizeId }
	local ctx = PricingService.context(session)
	local check = ModelMath.releaseCheck(session.data, model.id, target)
	local market = PricingMath.releaseMarket(target, marketing, check.replaced)
	return PricingMath.best(ctx, product, target, market, P.releaseHorizon, pause)
end

-- Re-price this model on the next tick (auto switched on, or a fresh release).
function PricingService.schedule(session: Session, modelId: string)
	local state = stateOf(session)
	if not table.find(state.queue, modelId) then
		table.insert(state.queue, 1, modelId)
	end
end

-- one stamped line in this company's news feed (CompanyOps.post: own calendar day, visible hour)
local function news(session: Session, text: string)
	local e = session.data.empire
	if typeof(e) == "table" then
		CompanyOps.post(e, text)
	end
end

-- Applies the result of a finished forecast. Returns true on a price change.
local function apply(session: Session, model: ModelData, choice: PricingMath.Choice): boolean
	local release = model.release
	if not release or choice.profit == -math.huge or (choice.sub == release.subPrice and choice.api == release.apiPrice) then
		return false
	end
	local live: any = session.live
	local note = PricingMath.explain(release.target, release.subPrice, release.apiPrice, choice.sub, choice.api, tonumber(live.load), tonumber(live.capacity))
	release.subPrice = choice.sub
	release.apiPrice = choice.api
	if typeof(live.pricing) ~= "table" then
		live.pricing = {}
	end
	live.pricing[model.id] = { note = note, at = os.time() }
	news(session, `{model.name} v{model.version}: {note}`)
	SessionService.markDirty(session)
	return true
end

local function autoOn(model: ModelData?): boolean
	return model ~= nil and model.status == "live" and model.release ~= nil and model.market ~= nil and (model.release :: any).auto ~= false
end

-- Whole auto-price forecast for one live model at once (tests, admin tools); the tick runs it as a job.
function PricingService.evaluate(session: Session, model: ModelData): boolean
	if not autoOn(model) then
		return false
	end
	local release = model.release :: Types.ReleaseConfig
	local choice = PricingMath.best(PricingService.context(session), model, release.target, PricingMath.cloneMarket(model.market), P.autoHorizon)
	return apply(session, model, choice)
end

-- Forecast job of `session` in progress (tests).
function PricingService.job(session: Session): any
	local state = states[session]
	return if state then state.job else nil
end

local function startJob(session: Session, state: State, model: ModelData)
	local release = model.release :: Types.ReleaseConfig
	state.job = {
		modelId = model.id,
		product = { id = model.id, stats = table.clone(model.stats), sizeId = model.sizeId },
		target = release.target,
		ctx = PricingService.context(session),
		market = PricingMath.cloneMarket(model.market),
		index = 0,
		run = nil,
		best = { sub = release.subPrice, api = release.apiPrice, profit = -math.huge },
	}
	PricingService.stats.jobs += 1
	if not table.find(active, session) then
		table.insert(active, session)
	end
end

-- Scheduling only (no forecast work): called once per simulation tick from AIModelService.tick.
function PricingService.tick(session: Session, dt: number)
	local data = session.data
	if not data.company then
		return
	end
	local state = stateOf(session)
	-- a model switched back to auto is re-priced at once; forget models that are no longer live
	local seen: { [string]: boolean } = {}
	local liveIds: { string } = {}
	for _, id in data.modelOrder do
		local model = data.models[id]
		local release = if model then model.release else nil
		if model and release and model.status == "live" then
			local auto = (release :: any).auto ~= false
			seen[id] = true
			if auto then
				table.insert(liveIds, id)
				if state.auto[id] == false then
					PricingService.schedule(session, id)
				end
			end
			state.auto[id] = auto
		end
	end
	for id in state.auto do
		if not seen[id] then
			state.auto[id] = nil
		end
	end
	state.due += dt
	if state.due >= P.autoPeriod then
		state.due = state.due % P.autoPeriod
		for _, id in liveIds do
			if not table.find(state.queue, id) then
				table.insert(state.queue, id)
			end
		end
	end
	if not state.job then
		while #state.queue > 0 do
			local id = table.remove(state.queue, 1) :: string
			local model = data.models[id]
			if model and autoOn(model) then
				startJob(session, state, model)
				break
			end
		end
	end
end

-- Advances one session's job by at most `maxTicks` market ticks. Returns the ticks used and whether the job
-- is over (finished, applied or dropped).
local function advance(session: any, maxTicks: number): (number, boolean)
	local state = states[session]
	local job = if state then state.job else nil
	if not state or not job then
		return 0, true
	end
	local model = if session.closed then nil else session.data.models[job.modelId]
	if not model or not autoOn(model) then
		state.job = nil -- session gone, model retired or replaced, or switched to manual meanwhile
		return 0, true
	end
	local run: PricingMath.Run
	local current = job.run
	if current then
		run = current
	else
		job.index += 1
		local price = PricingMath.MENU[job.index]
		run = PricingMath.newRun(job.ctx, PricingMath.candidate(job.product, job.target, job.market, price.sub, price.api), P.autoHorizon)
		job.run = run
		PricingService.stats.runs += 1
	end
	local before = run.done
	local finished = PricingMath.stepRun(run, maxTicks)
	local used = run.done - before
	PricingService.stats.ticks += used
	if finished then
		job.run = nil
		local value = PricingMath.runResult(run)
		if value > job.best.profit then
			local price = PricingMath.MENU[job.index]
			job.best = { sub = price.sub, api = price.api, profit = value }
		end
		if job.index >= #PricingMath.MENU then
			state.job = nil
			if apply(session, model, job.best) then
				PricingService.stats.applied += 1
			end
			return used, true
		end
	end
	return used, false
end

-- One worker frame: market ticks for the jobs of the whole server until PRICING.frameBudget seconds of CPU are
-- used (at least one tick when any job waits). `budget` overrides the CPU budget (tests). Returns the ticks.
function PricingService.frame(budget: number?): number
	if #active == 0 then
		return 0
	end
	local limit = budget or P.frameBudget
	local start = os.clock()
	local ticks = 0
	local idle = 0
	while #active > 0 do
		if cursor > #active then
			cursor = 1
		end
		local session = active[cursor]
		local used, over = advance(session, 1)
		ticks += used
		if over then
			table.remove(active, cursor)
		else
			cursor += 1
		end
		idle = if used == 0 then idle + 1 else 0
		if (ticks > 0 and os.clock() - start >= limit) or idle > #active then
			break
		end
	end
	return ticks
end

-- Runs every pending job of `session` to the end at once (tests, admin tools).
function PricingService.flush(session: Session)
	while states[session] and states[session].job do
		advance(session, math.huge)
	end
	local index = table.find(active, session)
	if index then
		table.remove(active, index)
	end
end

function PricingService.init()
	RunService.Heartbeat:Connect(function()
		PricingService.frame()
	end)
end

return PricingService
