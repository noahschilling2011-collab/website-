--!strict
-- KI-Modelle: Training starten und fortschreiben, Trainings-Events, Release, Preise, Retire.
--
-- CORE_SPEC 7 (models package):
--   * product lines: the release target is the line; one live model per line. Releasing into a line that has
--     a live model makes the new model its next version: it takes over ModelConfig.MIGRATE of the users and the
--     word of mouth, the old one retires with replacedBy = new id. A new line beyond MarketConfig.PRODUCT_SLOTS
--     of the office returns LINE_LIMIT.
--   * ageing: model.market.vage (seconds since the last version) is 0 at release and after a refinement;
--     MarketMath.tick advances it while the model is live.
--   * refinement: at most ModelConfig.REFINE.limit runs (REFINE_LIMIT), cost x (1 + 0.5 * runs), additive
--     gain, every core stat <= 99; a live model keeps serving with its current version meanwhile.
--   * MODEL_LIMIT counts non-retired models only; old retired models beyond RETIRED_KEEP are pruned.
--   * pricing: Recommended release price and auto-price (model.release.auto) via PricingService.
--
-- Ablauf eines Trainings:
--   StartTraining prüft Name/Größe/Fokus, plant mit ModelMath (GPU, VRAM, Daten, Kosten) und zieht
--   die Kosten ab. tick() schreibt jede Sekunde Arbeit fort (GPU-Käufe beschleunigen sofort).
--   Bei eventAt (35 %) wird einmal ein Event gewürfelt. Entscheidungs-Events pausieren das Training,
--   bis der Spieler wählt oder der Timer abläuft (dann gilt die Default-Wahl).
--   Am Ende berechnet computeStats die Stats aus den Daten vom Trainingsstart (Daten werden nicht verbraucht).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ModelConfig = require(ReplicatedStorage.Shared.Config.ModelConfig)
local MarketConfig = require(ReplicatedStorage.Shared.Config.MarketConfig)
local ModelMath = require(ReplicatedStorage.Shared.ModelMath)
local EmpireMath = require(ReplicatedStorage.Shared.EmpireMath)
local PricingMath = require(ReplicatedStorage.Shared.PricingMath)
local Format = require(ReplicatedStorage.Shared.Format)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(script.Parent.Parent.Lib.ServerTypes)
local Guard = require(script.Parent.Parent.Lib.Guard)
local TextFilter = require(script.Parent.Parent.Lib.TextFilter)
local Remote = require(script.Parent.Parent.Lib.Remote)
local SessionService = require(script.Parent.SessionService)
local EconomyService = require(script.Parent.EconomyService)
local PlotService = require(script.Parent.PlotService)
local PricingService = require(script.Parent.PricingService)
local CompanyOps = require(ReplicatedStorage.Shared.CompanyOps)
local ShopMath = require(ReplicatedStorage.Shared.ShopMath) -- shop package: Overclock (SHOP_SPEC 3.3)
local CompanyConfig = require(ReplicatedStorage.Shared.Config.CompanyConfig)

type Session = ServerTypes.Session
type TrainingState = Types.TrainingState
type EventDef = ModelConfig.EventDef
type ChoiceDef = ModelConfig.ChoiceDef

local T = ModelConfig.TRAINING
local EPOCHS = 10
local MODEL_LIMIT_DEFAULT = 80 -- used only until GameConfig.MODEL_LIMIT exists (econ package)

local function modelLimit(): number
	local limit = (GameConfig :: any).MODEL_LIMIT
	return if typeof(limit) == "number" then limit else MODEL_LIMIT_DEFAULT
end

local AIModelService = {}

local function addLog(training: TrainingState, line: string)
	table.insert(training.log, line)
	while #training.log > T.logLines do
		table.remove(training.log, 1)
	end
end

local function specOf(session: Session): string
	local company = session.data.company
	return if company then company.spec else "general"
end

-- "Nova" -> Version 1, zweites "Nova" -> Version 2 (Anzeige "Nova v2"); the rule lives in ModelMath.nextVersion,
-- which the Lab's Model Studio shows before the start ("Becomes Nova v2")
local function versionFor(data: Types.PlayerData, name: string): number
	return ModelMath.nextVersion(data, name)
end

-- Line label for news and notices ("Consumer Chat").
local function lineLabel(target: string?): string
	local line = ModelConfig.getLine(target)
	return if line then line.label else "Model"
end

-- One stamped line in the company news feed (CompanyOps.post: the company's own day, the visible hour).
local function news(session: Session, text: string)
	local e = session.data.empire
	if typeof(e) == "table" then
		CompanyOps.post(e, text)
	end
end

-- A retired model keeps its history (revenueTotal, peakUsers, ages) but no per-segment state.
local function clearMarket(model: Types.ModelData)
	local market = model.market
	if market then
		market.users = {}
		market.organic = {}
		market.hype = {}
	end
end

-- Saves stay bounded although retired models no longer count toward MODEL_LIMIT: beyond RETIRED_KEEP the
-- oldest retired models are removed, except one that is training or is the source of a studio project.
-- replacedBy chains are re-linked around a removed model (StudioService follows them to the live successor).
local function pruneRetired(data: Types.PlayerData): number
	local retired: { string } = {}
	for _, id in data.modelOrder do
		local model = data.models[id]
		if model and model.status == "retired" then
			table.insert(retired, id)
		end
	end
	local excess = #retired - ModelConfig.RETIRED_KEEP
	if excess <= 0 then
		return 0
	end
	local protected: { [string]: boolean } = {}
	if data.training then
		protected[data.training.modelId] = true
	end
	local projects = if typeof(data.empire) == "table" then data.empire.projects else nil
	if typeof(projects) == "table" then
		for _, project in projects do
			if typeof(project) == "table" and typeof(project.sourceId) == "string" then
				protected[project.sourceId] = true
			end
		end
	end
	local removed: { [string]: boolean } = {}
	for _, id in retired do
		if excess <= 0 then
			break
		end
		if not protected[id] then
			removed[id] = true
			excess -= 1
		end
	end
	for _, model in data.models do
		local successor = (model :: any).replacedBy
		local hops = 0
		while typeof(successor) == "string" and removed[successor] and hops < 64 do
			local next = data.models[successor]
			successor = if next then (next :: any).replacedBy else nil
			hops += 1
		end
		if (model :: any).replacedBy ~= successor then
			(model :: any).replacedBy = successor
		end
	end
	local order: { string } = {}
	local count = 0
	for _, id in data.modelOrder do
		if removed[id] then
			data.models[id] = nil
			count += 1
		else
			table.insert(order, id)
		end
	end
	data.modelOrder = order
	return count
end

local function bestOverallExcept(data: Types.PlayerData, exceptId: string): number
	local best = 0
	for id, model in data.models do
		if id ~= exceptId and model.status ~= "training" then
			best = math.max(best, model.overall)
		end
	end
	return best
end

-- Loss-Punkte gleichmäßig über den Fortschritt (Punkt i gehört zu Fortschritt (i-1)/(N-1))
local function updateLoss(session: Session, training: TrainingState)
	local progress = training.workDone / training.workTotal
	local wanted = math.clamp(math.floor(progress * (T.lossPoints - 1)) + 1, 1, T.lossPoints)
	while #training.loss < wanted do
		local p = #training.loss / (T.lossPoints - 1)
		local value = ModelMath.lossAt(p, training.expected, session.rng:NextNumber(-0.05, 0.05))
		table.insert(training.loss, math.round(value * 1000) / 1000)
	end
end

local function logEpochs(training: TrainingState)
	local epoch = math.min(EPOCHS - 1, math.floor(training.workDone / training.workTotal * EPOCHS))
	while training.epoch < epoch do
		training.epoch += 1
		local loss = training.loss[#training.loss] or T.lossStart
		addLog(training, string.format("Epoch %d/%d  loss %.3f", training.epoch, EPOCHS, loss))
	end
end

local function stretchRemaining(training: TrainingState, timeMult: number)
	local remaining = training.workTotal - training.workDone
	training.workTotal = training.workDone + remaining * timeMult
end

-- Wendet eine Event-Wahl an. Gibt einen Fehlercode zurück oder nil.
local function applyChoice(session: Session, training: TrainingState, choice: ChoiceDef, auto: boolean): string?
	local event = training.event
	if not event or not event.pending then
		return "NO_EVENT"
	end
	if choice.costFactor then
		local extra = math.floor(training.cost * choice.costFactor)
		if not EconomyService.spend(session, extra, "training") then
			return "NO_MONEY"
		end
		training.cost += extra
	end
	if choice.timeMult then
		stretchRemaining(training, choice.timeMult)
	end
	local note = choice.desc
	if choice.quality then
		local hit = true
		if choice.gamble then
			hit = session.rng:NextNumber() < choice.gamble
		end
		if hit then
			training.qualityMod *= choice.quality
			note = if choice.gamble then "quality took a hit" else choice.desc
		else
			note = "loss recovered, no damage"
		end
		event.outcome = if hit then choice.id else choice.id .. "_lucky"
	else
		event.outcome = choice.id
	end
	event.pending = false
	addLog(training, (if auto then "Timeout -> " else "") .. choice.label .. ": " .. note)
	return nil
end

-- Timeout: Default-Wahl; falls die Geld kostet und keins da ist, die nächste kostenlose Option
local function autoResolve(session: Session, training: TrainingState, def: EventDef)
	local ordered: { ChoiceDef } = {}
	local default = if def.default then ModelConfig.getChoice(def, def.default) else nil
	if default then
		table.insert(ordered, default)
	end
	local choices = def.choices
	if choices then
		for _, choice in choices do
			if choice ~= default then
				table.insert(ordered, choice)
			end
		end
	end
	for _, choice in ordered do
		if applyChoice(session, training, choice, true) == nil then
			return
		end
	end
	local event = training.event
	if event then
		event.pending = false
		event.outcome = "skipped"
	end
end

local function rollEvent(session: Session, training: TrainingState, now: number)
	training.eventRolled = true
	local def = ModelMath.rollEvent(function()
		return session.rng:NextNumber()
	end, specOf(session))
	if not def then
		return
	end
	if def.choices then
		training.event = { id = def.id, pending = true, expiresAt = now + T.decisionTimeout, outcome = nil }
		if def.id == "instability" and #training.loss > 0 then
			training.loss[#training.loss] += 0.8 -- sichtbarer Ausschlag im Graphen
		end
		addLog(training, "[!] " .. def.title)
		Remote.fire(session.player, "Notify", "TRAINING_EVENT", { eventId = def.id })
	else
		if def.timeMult then
			stretchRemaining(training, def.timeMult)
		end
		if def.quality then
			training.qualityMod *= def.quality
		end
		training.event = { id = def.id, pending = false, expiresAt = 0, outcome = "auto" }
		addLog(training, "[*] " .. def.title .. ": " .. def.text)
	end
end

local function finish(session: Session, training: TrainingState)
	local data = session.data
	data.training = nil
	local model = data.models[training.modelId]
	if model then
		local before = model.overall -- LAB_SPEC S1: a refinement's reveal compares with the model's own old score
		local stats, overall = ModelMath.computeStats(
			model.sizeId,
			model.focusId,
			model.dataUsed,
			specOf(session),
			training.qualityMod,
			function(n: number): number
				return session.rng:NextNumber(-n, n)
			end
		)
		-- Lab levels and research reach new models through bonuses.core (EmpireMath, before the 99 cap)
		stats, overall = EmpireMath.boostStats(stats, data.empire)
		if training.refinement and training.baseStats then
			-- CORE_SPEC 7.4: additive gain per core stat, shrinking with every run, capped at 99
			local runs = math.max(0, math.floor(tonumber(model.iterations) or 0))
			local gain = ModelMath.refineGain(model.dataUsed.quality, training.qualityMod, runs)
			for _, stat in ModelConfig.STATS do
				if stat.weight > 0 and stat.id ~= "reliability" then
					stats[stat.id] = math.min(ModelConfig.STAT_CAP, math.round(((training.baseStats[stat.id] or 1) + gain) * 10) / 10)
				end
			end
			model.iterations = runs + 1
			model.version += 1
			local market: any = model.market
			if market then
				market.vage = 0 -- a refinement is a new version: the model is young again
			end
		end
		stats, overall = ModelMath.capStats(stats)
		local previousBest = bestOverallExcept(data, model.id)
		model.stats = stats
		model.overall = overall
		if model.status == "training" then
			-- a live model keeps serving while it is refined (status stays "live"); a save from before that
			-- rule paused it: it goes live again only if its line is still free
			local release = model.release
			local free = release ~= nil and model.market ~= nil and #ModelMath.releaseCheck(data, model.id, release.target).replaced == 0
			model.status = if training.resumeLive and free then "live" else "trained"
		end
		model.trainedAt = os.time()
		model.trainCost = if training.refinement then model.trainCost + training.cost else training.cost
		data.stats.bestOverall = math.max(data.stats.bestOverall, overall)
		data.stats.modelsTrained += 1
		local event = training.event
		Remote.fire(session.player, "Notify", "TRAINING_COMPLETE", {
			modelId = model.id,
			overall = overall,
			previousBest = previousBest,
			-- LAB_SPEC S1 (display only, < 100 bytes): reveal count-up, lucky roll, refinement gain, event chip
			expected = training.expected,
			refinement = training.refinement == true,
			before = if training.refinement then before else nil,
			eventId = if event then event.id else nil,
			outcome = if event then event.outcome else nil,
		})
	end
	SessionService.markDirty(session)
	PlotService.refresh(session)
end

local function trainingTick(session: Session, dt: number)
	local training = session.data.training
	if not training then
		return
	end
	local trainee = session.data.models[training.modelId]
	if not trainee then
		session.data.training = nil -- kaputter Zustand: Training ohne Modell
		SessionService.markDirty(session)
		return
	end
	if training.refinement and training.resumeLive and trainee.status == "training" then
		-- refinement started before CORE_SPEC 7.4 paused serving: the model serves again if its line is free
		local release = trainee.release
		if release and trainee.market and #ModelMath.releaseCheck(session.data, trainee.id, release.target).replaced == 0 then
			trainee.status = "live"
		end
	end

	local now = workspace:GetServerTimeNow()
	local event = training.event
	if event and event.pending then
		if now < event.expiresAt then
			return -- pausiert, wartet auf Entscheidung
		end
		local def = ModelConfig.getEvent(event.id)
		if def then
			autoResolve(session, training, def)
		else
			event.pending = false
		end
	end

	local rate = EmpireMath.trainingRate(session.data.gpus, training.workTotal, session.data.empire)
	rate = ShopMath.boostRate(session.data, training.workTotal, rate) -- Overclock x1.5 while it runs; the 12 s floor stays
	training.workDone = math.min(training.workTotal, training.workDone + rate * dt)
	updateLoss(session, training)
	if not training.eventRolled and training.workDone / training.workTotal >= T.eventAt then
		rollEvent(session, training, now)
	end
	logEpochs(training)
	SessionService.markDirty(session)

	local pending = training.event ~= nil and (training.event :: Types.TrainingEventState).pending
	if training.workDone >= training.workTotal and not pending then
		finish(session, training)
	end
end

-- Einmal pro Server-Tick für jede Session
function AIModelService.tick(session: Session, dt: number)
	trainingTick(session, dt)
	PricingService.tick(session, dt) -- auto-price scheduling; the forecasts run in PricingService's frame worker
end

-- Debug: Training sofort abschließen
function AIModelService.finishNow(session: Session): boolean
	local training = session.data.training
	if not training then
		return false
	end
	local event = training.event
	if event and event.pending then
		local def = ModelConfig.getEvent(event.id)
		if def then
			autoResolve(session, training, def)
		end
	end
	training.workDone = training.workTotal
	updateLoss(session, training)
	finish(session, training)
	return true
end

-- Last Epoch voucher (shop package, SHOP_SPEC 3.2): the running training or refinement finishes now, by the rules of
-- waiting. The run's one event check happens first if it has not come yet (same odds as at 35 %), so the chances stay
-- the same; an event that needs a decision must be decided first (DECIDE_FIRST, the voucher is kept; the one handler
-- that changes state - the roll - and still returns an error: the roll would come at 35 % anyway). The final stats
-- roll comes from finish() like after waiting: "same chances as waiting", never "same result".
function AIModelService.lastEpoch(session: Session): (boolean, string?)
	local training = session.data.training
	if not training then
		return false, "NO_TRAINING"
	end
	local event = training.event
	if event and event.pending then
		return false, "DECIDE_FIRST"
	end
	if not training.eventRolled then
		rollEvent(session, training, workspace:GetServerTimeNow())
		local rolled = training.event
		if rolled and rolled.pending then
			SessionService.markDirty(session, true)
			return false, "DECIDE_FIRST"
		end
	end
	return AIModelService.finishNow(session), nil
end

local function startTraining(session: Session, payload: ServerTypes.Payload): ServerTypes.Result
	local recipeId=if payload.recipeId==nil then "steady" else Guard.id(payload.recipeId)
	if not recipeId or not ModelConfig.getRecipe(recipeId) then return {ok=false,err="BAD_INPUT"} end
	-- LAB_SPEC 6.3 (Model Studio, cosmetic + planning only): optional look "<colorId>:<emblemIndex>" and the
	-- planned product line. Absent = nil (old clients, the economy bot); present but invalid = BAD_INPUT like
	-- recipeId, before any other check and before the name filter yields.
	local look: string? = nil
	if payload.look ~= nil then
		local colorId, emblem = ModelMath.parseLook(payload.look)
		if not colorId or not emblem then return {ok=false,err="BAD_INPUT"} end
		-- Identity Kit colours / logos (emblem > #LOGOS) need the pass (SHOP_SPEC 3.5); free looks never do, and neither
		-- does the company's own saved colour / logo (fix round 1, R9: the Studio's defaults after a refund)
		local company = session.data.company
		local ownColor = company ~= nil and company.color == colorId
		local ownLogo = company ~= nil and CompanyConfig.allLogos()[emblem] == company.logo
		if (CompanyConfig.isKitColor(colorId) and not ownColor) or (emblem > #CompanyConfig.LOGOS and not ownLogo) then
			local shopModule = script.Parent:FindFirstChild("ShopService")
			local Shop = if shopModule then (require :: any)(shopModule) else nil
			if not Shop or not Shop.owns(session, CompanyConfig.KIT_PASS) then return {ok=false,err="PASS_NEEDED"} end
		end
		look = `{colorId}:{emblem}`
	end
	local planTarget: string? = nil
	if payload.target ~= nil then
		local target = Guard.id(payload.target)
		if not target or not MarketConfig.isTarget(target) then return {ok=false,err="BAD_INPUT"} end
		planTarget = target
	end
	if session.data.training then
		return { ok = false, err = "TRAINING_ACTIVE" }
	end
	local name = Guard.text(payload.name, GameConfig.MODEL_NAME_MIN, GameConfig.MODEL_NAME_MAX)
	if not name then
		return { ok = false, err = "BAD_NAME" }
	end
	local sizeId = Guard.id(payload.sizeId)
	local focusId = Guard.id(payload.focusId)
	local size = if sizeId then ModelConfig.getSize(sizeId) else nil
	local focus = if focusId then ModelConfig.getFocus(focusId) else nil
	if not size or not focus then
		return { ok = false, err = "BAD_INPUT" }
	end

	if size.id == "s7b" and not session.data.empire.research.frontier then
		return {ok=false, err="PREREQUISITE"}
	end
	if ModelMath.activeModels(session.data) >= modelLimit() then return {ok=false, err="MODEL_LIMIT"} end
	local plan = ModelMath.plan(size, ModelMath.fleet(session.data.gpus), ModelMath.dataSummary(session.data.data),recipeId)
	if not plan.ok then
		return { ok = false, err = plan.reason }
	end
	if session.data.money < plan.cost then
		return { ok = false, err = "NO_MONEY" }
	end

	local filtered = TextFilter.forBroadcast(name, session.userId) -- yieldet
	if filtered == nil then
		return { ok = false, err = "FILTER_DOWN" }
	end
	if filtered ~= name then
		return { ok = false, err = "NAME_FILTERED" }
	end

	-- Nach dem Yield alles neu prüfen: zweite Anfrage, GPU verkauft, Geld ausgegeben, Spieler weg
	if session.closed then
		return { ok = false, err = "LOADING" }
	end
	local data = session.data
	if data.training then
		return { ok = false, err = "TRAINING_ACTIVE" }
	end
	local fleet = ModelMath.fleet(data.gpus)
	local summary = ModelMath.dataSummary(data.data)
	plan = ModelMath.plan(size, fleet, summary,recipeId)
	if not plan.ok then
		return { ok = false, err = plan.reason }
	end
	if ModelMath.activeModels(data) >= modelLimit() then return {ok=false, err="MODEL_LIMIT"} end
	if not EconomyService.spend(session, plan.cost, "training") then
		return { ok = false, err = "NO_MONEY" }
	end

	local expectedStats, expected = ModelMath.computeStats(size.id, focus.id, summary, specOf(session), ModelMath.recipeFactor(size,summary,recipeId), nil)
	expectedStats, expected = EmpireMath.boostStats(expectedStats, data.empire)
	expectedStats, expected = ModelMath.capStats(expectedStats)
	local id = HttpService:GenerateGUID(false)
	local model: Types.ModelData = {
		id = id,
		name = name,
		version = versionFor(data, name),
		sizeId = size.id,
		focusId = focus.id,
		status = "training",
		createdAt = os.time(),
		trainedAt = nil,
		stats = {},
		overall = 0,
		trainCost = plan.cost,
		dataUsed = summary,
		release = nil,
		market = nil,
	}
	-- optional per-model fields (old models have none; every reader validates them)
	local extra: any = model
	extra.look = look
	extra.plan = planTarget
	extra.recipeId = recipeId
	data.models[id] = model
	table.insert(data.modelOrder, id)
	pruneRetired(data)

	local training: TrainingState = {
		modelId = id,
		workTotal = plan.work,
		workDone = 0,
		cost = plan.cost,
		expected = expected,
		qualityMod = ModelMath.recipeFactor(size,summary,recipeId),
		eventRolled = false,
		event = nil,
		epoch = 0,
		loss = { math.round(ModelMath.lossAt(0, expected, 0) * 1000) / 1000 },
		log = {},
	}
	addLog(training, `Allocating {fleet.vram} GB VRAM for {size.label} params`)
	addLog(training, `Tokenizing {Format.tokens(summary.total)} tokens`)
	addLog(training, "Training started")
	data.training = training

	SessionService.markDirty(session)
	PlotService.refresh(session)
	return { ok = true, modelId = id }
end

local function improveModel(session: Session, payload: ServerTypes.Payload): ServerTypes.Result
	local data = session.data
	if data.training then return {ok=false,err="TRAINING_ACTIVE"} end
	local id = Guard.id(payload.modelId)
	local model = if id then data.models[id] else nil
	if not model or (model.status ~= "trained" and model.status ~= "live") then return {ok=false,err="BAD_MODEL"} end
	if (tonumber(model.iterations) or 0) >= ModelConfig.REFINE.limit then return {ok=false,err="REFINE_LIMIT"} end
	local summary = ModelMath.dataSummary(data.data)
	if summary.total < model.dataUsed.total + 1e8 then return {ok=false,err="NEW_DATA"} end
	local size = ModelConfig.getSize(model.sizeId)
	if not size then return {ok=false,err="BAD_MODEL"} end
	local plan = ModelMath.plan(size, ModelMath.fleet(data.gpus), summary)
	if not plan.ok then return {ok=false,err=plan.reason} end
	local refine = ModelMath.refinePlan(model, plan)
	if not refine.ok then return {ok=false,err=refine.err} end
	local cost = refine.cost
	if not EconomyService.spend(session,cost,"refine") then return {ok=false,err="NO_MONEY"} end
	local resume = model.status == "live"
	local base = table.clone(model.stats)
	model.dataUsed = summary
	if not resume then model.status = "training" end -- a live model keeps serving its current version
	data.training = {modelId=model.id,refinement=true,baseStats=base,resumeLive=resume,
		workTotal=refine.work,workDone=0,cost=cost,expected=math.min(ModelConfig.STAT_CAP,model.overall+5),
		qualityMod=1,eventRolled=false,event=nil,epoch=0,loss={ModelMath.lossAt(0,model.overall,0)},
		log={if resume then "Refinement: fresh data + your own checkpoint. Serving continues with the current version." else "Refinement: fresh data + your own checkpoint.",
			`Refinement {refine.runs + 1} of {refine.limit}. Every stat stays at most {ModelConfig.STAT_CAP}.`}}
	SessionService.markDirty(session)
	PlotService.refresh(session)
	return {ok=true,modelId=model.id}
end

local function resolveEvent(session: Session, payload: ServerTypes.Payload): ServerTypes.Result
	local training = session.data.training
	local event = if training then training.event else nil
	if not training or not event or not event.pending then
		return { ok = false, err = "NO_EVENT" }
	end
	local def = ModelConfig.getEvent(event.id)
	local choiceId = Guard.id(payload.choice)
	local choice = if def and choiceId then ModelConfig.getChoice(def, choiceId) else nil
	if not choice then
		return { ok = false, err = "BAD_INPUT" }
	end
	local err = applyChoice(session, training, choice, false)
	if err then
		return { ok = false, err = err }
	end
	SessionService.markDirty(session)
	return { ok = true, outcome = event.outcome }
end

local function parsePrices(payload: ServerTypes.Payload): (number?, number?)
	local sub = Guard.number(payload.subPrice, 0, 1000)
	local api = Guard.number(payload.apiPrice, MarketConfig.API_PRICE.min, MarketConfig.API_PRICE.max)
	if sub == nil or not MarketConfig.isSubPrice(sub) or api == nil then
		return nil, nil
	end
	return sub, Guard.snap(api, MarketConfig.API_PRICE.step)
end

local function modelFromPayload(session: Session, payload: ServerTypes.Payload): Types.ModelData?
	local id = Guard.id(payload.modelId)
	return if id then session.data.models[id] else nil
end

-- Release a trained model into a product line (CORE_SPEC 7.1/7.2/7.7).
-- payload: modelId, target, marketing, auto (default true), subPrice/apiPrice (needed when auto == false).
-- auto: the server picks the Recommended price (forecast-best menu price) and keeps auto-pricing the model;
-- otherwise the player's prices are used and auto-price is off for this model.
local function releaseModel(session: Session, payload: ServerTypes.Payload): ServerTypes.Result
	local model = modelFromPayload(session, payload)
	if not model or model.status ~= "trained" then
		return { ok = false, err = "BAD_MODEL" }
	end
	local auto = payload.auto ~= false
	local sub, api = parsePrices(payload)
	local marketingRaw = Guard.number(payload.marketing, 0, MarketConfig.MARKETING.max)
	local target = Guard.id(payload.target)
	if (not auto and (sub == nil or api == nil)) or marketingRaw == nil or not target or not MarketConfig.isTarget(target) then
		return { ok = false, err = "BAD_INPUT" }
	end
	if payload.auto ~= nil and typeof(payload.auto) ~= "boolean" then
		return { ok = false, err = "BAD_INPUT" }
	end
	local data = session.data
	local marketing = math.min(Guard.snap(marketingRaw, MarketConfig.MARKETING.step), MarketConfig.MARKETING.max)
	local function precheck(): string?
		if model.status ~= "trained" or data.models[model.id] ~= model then
			return "BAD_MODEL"
		end
		local check = ModelMath.releaseCheck(data, model.id, target)
		if not check.ok then
			return check.err or "LINE_LIMIT"
		end
		if marketing > 0 and data.money < marketing then -- free releases work in debt, as EconomyService.spend(0)
			return "NO_MONEY"
		end
		return nil
	end
	local err = precheck()
	if err then
		return { ok = false, err = err }
	end
	if auto then
		-- the forecast runs over a few frames (one menu price per frame): re-check everything afterwards
		local choice = PricingService.recommend(session, model, target, marketing, true)
		sub, api = choice.sub, choice.api
		if session.closed then
			return { ok = false, err = "LOADING" }
		end
		err = precheck()
		if err then
			return { ok = false, err = err }
		end
	end
	if sub == nil or api == nil then
		return { ok = false, err = "BAD_INPUT" }
	end
	if not EconomyService.spend(session, marketing, "marketing") then
		return { ok = false, err = "NO_MONEY" }
	end
	local check = ModelMath.releaseCheck(data, model.id, target)

	model.status = "live"
	local release: any = {
		subPrice = sub,
		apiPrice = api,
		marketing = marketing,
		target = target,
		releasedAt = os.time(),
		auto = auto,
	}
	model.release = release
	model.market = PricingMath.releaseMarket(target, marketing, check.replaced)
	-- one live model per line: the predecessor(s) retire, their users moved over (not wiped)
	local predecessor = check.replaced[1]
	for _, old in check.replaced do
		old.status = "retired"
		;(old :: any).replacedBy = model.id
		clearMarket(old)
	end
	data.stats.modelsReleased += 1
	data.stats.bestOverall = math.max(data.stats.bestOverall, model.overall)
	if predecessor then
		news(session, `{model.name} v{model.version} replaces {predecessor.name} v{predecessor.version} ({lineLabel(target)}, {math.floor(ModelConfig.MIGRATE * 100 + 0.5)}% of users move)`)
	else
		news(session, `{model.name} v{model.version} launched as {lineLabel(target)}`)
	end
	SessionService.markDirty(session)
	Remote.fire(session.player, "Notify", "MODEL_LIVE", {
		modelId = model.id,
		replacedId = if predecessor then predecessor.id else nil,
		line = check.line,
	})
	return { ok = true, subPrice = sub, apiPrice = api, auto = auto, replacedId = if predecessor then predecessor.id else nil }
end

-- Auto-price on/off for one live model (EmpireAction {action="autoPrice"} delegates here; UpdatePricing
-- {auto = bool} is the same switch). Switching it on re-prices the model on the next tick.
function AIModelService.setAutoPrice(session: Session, modelId: any, on: any): ServerTypes.Result
	local id = Guard.id(modelId)
	local model = if id then session.data.models[id] else nil
	local release = if model then model.release else nil
	if not model or model.status ~= "live" or not release then
		return { ok = false, err = "BAD_MODEL" }
	end
	if typeof(on) ~= "boolean" then
		return { ok = false, err = "BAD_INPUT" }
	end
	;(release :: any).auto = on
	if on then
		PricingService.schedule(session, model.id)
	end
	SessionService.markDirty(session)
	return { ok = true, auto = on }
end

-- A manual price switches auto-price off for that model (CORE_SPEC 7.7). {modelId, auto = bool} without
-- prices only toggles auto-price.
local function updatePricing(session: Session, payload: ServerTypes.Payload): ServerTypes.Result
	local model = modelFromPayload(session, payload)
	local release = if model then model.release else nil
	if not model or model.status ~= "live" or not release then
		return { ok = false, err = "BAD_MODEL" }
	end
	if payload.subPrice == nil and payload.apiPrice == nil and payload.auto ~= nil then
		return AIModelService.setAutoPrice(session, model.id, payload.auto)
	end
	local sub, api = parsePrices(payload)
	if sub == nil or api == nil then
		return { ok = false, err = "BAD_INPUT" }
	end
	release.subPrice = sub
	release.apiPrice = api
	;(release :: any).auto = false
	SessionService.markDirty(session)
	return { ok = true, auto = false }
end

local function retireModel(session: Session, payload: ServerTypes.Payload): ServerTypes.Result
	local model = modelFromPayload(session, payload)
	if not model or model.status ~= "live" then
		return { ok = false, err = "BAD_MODEL" }
	end
	model.status = "retired"
	clearMarket(model)
	SessionService.markDirty(session)
	return { ok = true }
end

-- Reviewing a server-owned benchmark records the tutorial step without changing model scores.
local function evaluateModel(session: Session,payload: ServerTypes.Payload): ServerTypes.Result
 local model=modelFromPayload(session,payload)
 if not model or model.status=="training" then return {ok=false,err="BAD_MODEL"} end
 session.data.empire.quests.journey_evaluation=true;SessionService.markDirty(session)
 return {ok=true,modelId=model.id}
end
function AIModelService.init()
 Remote.bind("EvaluateModel",{burst=2,perSecond=.5,company=true},evaluateModel)
	Remote.bind("ImproveModel", {burst=2,perSecond=0.5,company=true}, improveModel)
	Remote.bind("StartTraining", { burst = 3, perSecond = 0.5, company = true }, startTraining)
	Remote.bind("ResolveEvent", { burst = 4, perSecond = 1, company = true }, resolveEvent)
	Remote.bind("ReleaseModel", { burst = 3, perSecond = 0.5, company = true }, releaseModel)
	Remote.bind("UpdatePricing", { burst = 8, perSecond = 3, company = true }, updatePricing)
	Remote.bind("RetireModel", { burst = 3, perSecond = 0.5, company = true }, retireModel)
	PricingService.init()
	-- shop package: the Last Epoch voucher (lazy require: ShopService never requires this module)
	local shopModule = script.Parent:FindFirstChild("ShopService")
	if shopModule then
		local Shop = (require :: any)(shopModule)
		Shop.setRedeemHandler("lastEpoch", function(session: Session): (boolean, string?)
			return AIModelService.lastEpoch(session)
		end)
	end
end

return AIModelService
