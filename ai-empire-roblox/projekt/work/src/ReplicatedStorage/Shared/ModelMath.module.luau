--!strict
-- Reine Mathe für Modelle: keine Roblox-APIs, damit Server, Client (Vorschau) und Tests
-- exakt dieselbe Formel benutzen.

local Config = script.Parent.Config
local ModelConfig = require(Config.ModelConfig)
local HardwareConfig = require(Config.HardwareConfig)
local DataConfig = require(Config.DataConfig)
local CompanyConfig = require(Config.CompanyConfig)
local MarketConfig = require(Config.MarketConfig)
local Types = require(script.Parent.Types)

type Stats = Types.Stats
type DataStock = Types.DataStock
type DataSummary = Types.DataSummary
type Fleet = Types.Fleet
type SizeDef = ModelConfig.SizeDef
type ModelData = Types.ModelData
type PlayerData = Types.PlayerData

export type Plan = {
	ok: boolean,
	reason: string?, -- "VRAM" | "NO_DATA" | "NO_GPU"
	work: number,
	rate: number, -- Compute-Einheiten pro Sekunde (inkl. Mindestdauer)
	seconds: number,
	cost: number,
}

export type Readiness = { fill: number, quantity: number, quality: number, factor: number }

-- Release into a product line (CORE_SPEC 7.1/7.2): `replaced` = the live models of that line (normally one;
-- an old save from before product lines may hold several), `usedLines` = other live lines, `slots` = lines the
-- office allows. ok = false with err "LINE_LIMIT" when a new line would exceed the slots.
export type ReleaseCheck = {
	ok: boolean,
	err: string?,
	line: string,
	replaced: { ModelData },
	usedLines: number,
	slots: number,
}

-- Refinement plan (CORE_SPEC 7.4): runs = refinements done so far, cost/work already scaled.
export type RefinePlan = {
	ok: boolean,
	err: string?,
	runs: number,
	limit: number,
	scale: number,
	cost: number,
	work: number,
}

local ModelMath = {}

function ModelMath.fleet(gpus: { [string]: number }): Fleet
	local throughput, vram, weightedCost, slots = 0, 0, 0, 0
	for _, gpu in HardwareConfig.GPUS do
		local count = gpus[gpu.id] or 0
		if count > 0 then
			throughput += gpu.throughput * count
			vram += gpu.vram * count
			weightedCost += gpu.powerCost * gpu.throughput * count
			if not gpu.starter then
				slots += count
			end
		end
	end
	return {
		throughput = throughput,
		vram = vram,
		costPerWork = if throughput > 0 then weightedCost / throughput else 0,
		slotsUsed = slots,
	}
end

function ModelMath.dataSummary(stock: { [string]: DataStock }): DataSummary
	local total, weighted = 0, 0
	local perType: { [string]: number } = {}
	for _, dataType in DataConfig.TYPES do
		local entry = stock[dataType.id]
		local tokens = if entry then entry.tokens else 0
		perType[dataType.id] = tokens
		total += tokens
		if entry then
			weighted += entry.tokens * entry.quality
		end
	end
	local shares: { [string]: number } = {}
	for id, tokens in perType do
		shares[id] = if total > 0 then tokens / total else 0
	end
	return { total = total, quality = if total > 0 then weighted / total else 0, shares = shares }
end

-- Fügt Tokens hinzu; Qualität wird gewichtet gemittelt (billige Masse verdünnt gute Daten).
function ModelMath.addTokens(stock: { [string]: DataStock }, typeId: string, tokens: number, quality: number)
	local entry = stock[typeId]
	if entry then
		local total = entry.tokens + tokens
		entry.quality = (entry.tokens * entry.quality + tokens * quality) / total
		entry.tokens = total
	else
		stock[typeId] = { tokens = tokens, quality = quality }
	end
end

function ModelMath.copyStock(stock: { [string]: DataStock }): { [string]: DataStock }
	local copy: { [string]: DataStock } = {}
	for id, entry in stock do
		copy[id] = { tokens = entry.tokens, quality = entry.quality }
	end
	return copy
end

function ModelMath.readiness(size: SizeDef, data: DataSummary): Readiness
	local D = ModelConfig.DATA
	local fill = math.min(D.maxFill, data.total / size.dataNeed)
	local quantity = 1 - math.exp(-D.quantityK * fill)
	local quality = D.qualityBase + D.qualityK * data.quality
	return { fill = fill, quantity = quantity, quality = quality, factor = quantity * quality }
end

function ModelMath.recipeFactor(size: SizeDef,data: DataSummary,id: string): number
	local recipe=ModelConfig.getRecipe(id) or ModelConfig.RECIPES[1]
	local enough=data.total>=size.dataNeed*.5 and data.quality>=.6
	return recipe.quality*(if id=="deep" and not enough then .68 else 1)
end
function ModelMath.plan(size: SizeDef, fleet: Fleet, data: DataSummary,recipeId: string?): Plan
	local T = ModelConfig.TRAINING
	local recipe=ModelConfig.getRecipe(recipeId or "steady") or ModelConfig.RECIPES[1]
	local work=size.work*recipe.work
	local reason: string? = nil
	if fleet.throughput <= 0 then
		reason = "NO_GPU"
	elseif fleet.vram < size.vram then
		reason = "VRAM"
	elseif data.total < T.minTokens then
		reason = "NO_DATA"
	end
	local rate = if fleet.throughput > 0 then math.min(fleet.throughput, work / T.minSeconds) else 0
	return {
		ok = reason == nil,
		reason = reason,
		work = work,
		rate = rate,
		seconds = if rate > 0 then work / rate else 0,
		cost = math.floor(work * fleet.costPerWork),
	}
end

-- Trainingsrate während eines laufenden Trainings (GPU-Käufe beschleunigen sofort)
function ModelMath.trainingRate(fleet: Fleet, workTotal: number): number
	return math.min(fleet.throughput, workTotal / ModelConfig.TRAINING.minSeconds)
end

function ModelMath.overall(stats: Stats): number
	local sum, weightSum = 0, 0
	for _, stat in ModelConfig.STATS do
		if stat.weight > 0 then
			sum += (stats[stat.id] or 0) * stat.weight
			weightSum += stat.weight
		end
	end
	return math.round(sum / weightSum * 10) / 10
end

-- noise(n) liefert einen Wert in [-n, n]. nil = keine Streuung (Vorschau, Erwartungswert).
function ModelMath.computeStats(
	sizeId: string,
	focusId: string,
	data: DataSummary,
	specId: string,
	qualityMod: number,
	noise: ((number) -> number)?
): (Stats, number)
	local size = ModelConfig.getSize(sizeId)
	local focus = ModelConfig.getFocus(focusId)
	assert(size and focus, "computeStats: unbekannte Größe oder Fokus")
	local spec = CompanyConfig.getSpec(specId)
	local bonus = if spec and spec.statBonus then spec.statBonus else {}
	local D = ModelConfig.DATA
	local core = size.potential * (D.floor + (1 - D.floor) * ModelMath.readiness(size, data).factor) * qualityMod

	local stats: Stats = {}
	for _, stat in ModelConfig.STATS do
		local id = stat.id
		local value: number
		if id == "speed" then
			value = size.speed
		elseif id == "efficiency" then
			value = size.efficiency
		else
			local affinity: number
			if id == "reliability" then
				affinity = ModelConfig.RELIABILITY.base + ModelConfig.RELIABILITY.quality * data.quality
			else
				local coeffs = ModelConfig.AFFINITY[id]
				affinity = coeffs.base or 1
				for typeId, k in coeffs do
					if typeId ~= "base" then
						affinity += k * (data.shares[typeId] or 0)
					end
				end
			end
			value = core * affinity * (focus.mult[id] or 1)
		end
		value += bonus[id] or 0
		if noise then
			value += noise(ModelConfig.TRAINING.noise)
		end
		stats[id] = if id == "speed" or id == "efficiency" or id == "reliability" then math.clamp(math.round(value * 10) / 10, 1, 99) else math.max(1, math.round(value * 10) / 10)
	end
	return stats, ModelMath.overall(stats)
end

-- Simulierter Loss: fällt exponentiell Richtung eines Endwerts, der vom erwarteten Overall abhängt
function ModelMath.lossAt(progress: number, expected: number, jitter: number): number
	local final = 3.4 / (1 + math.max(0, expected) / 60)
	local p = math.clamp(progress, 0, 1)
	return final + (ModelConfig.TRAINING.lossStart - final) * math.exp(-4.5 * p) + jitter
end

---------------------------------------------------------------------------- product lines, versions, refinement

-- Line id (= market segment id) of a release target. MarketConfig.LINE_OF is the source (CORE_SPEC 11.6);
-- ModelConfig.LINES mirrors it for the UI and is only read when LINE_OF is missing.
function ModelMath.lineOf(target: string?): string
	local t = target or "general"
	local map = (MarketConfig :: any).LINE_OF
	if typeof(map) == "table" and typeof(map[t]) == "string" then
		return map[t]
	end
	local line = ModelConfig.getLine(t)
	return if line then line.segment else "consumers"
end

-- Live product lines an office stage allows (MarketConfig.PRODUCT_SLOTS, by office index). No table = no limit.
function ModelMath.productSlots(stage: number?): number
	local slots = (MarketConfig :: any).PRODUCT_SLOTS
	if typeof(slots) ~= "table" or #slots == 0 then
		return math.huge
	end
	local n = slots[math.clamp(math.floor(tonumber(stage) or 1), 1, #slots)]
	return if typeof(n) == "number" then n else math.huge
end

-- Live models per line id, each list in modelOrder (deterministic). Second result: number of live lines.
function ModelMath.liveLines(data: PlayerData): ({ [string]: { ModelData } }, number)
	local lines: { [string]: { ModelData } } = {}
	local count = 0
	for _, id in data.modelOrder do
		local model = data.models[id]
		local release = if model then model.release else nil
		if model and model.status == "live" and release then
			local line = ModelMath.lineOf(release.target)
			local list = lines[line]
			if not list then
				list = {}
				lines[line] = list
				count += 1
			end
			table.insert(list, model)
		end
	end
	return lines, count
end

-- What releasing `modelId` into `target` does: the shared rule of AIModelService.releaseModel and the Lab UI.
function ModelMath.releaseCheck(data: PlayerData, modelId: string, target: string): ReleaseCheck
	local line = ModelMath.lineOf(target)
	local replaced: { ModelData } = {}
	local others: { [string]: boolean } = {}
	local usedLines = 0
	for _, id in data.modelOrder do
		local model = data.models[id]
		local release = if model then model.release else nil
		if model and release and id ~= modelId and model.status == "live" then
			local other = ModelMath.lineOf(release.target)
			if other == line then
				table.insert(replaced, model)
			elseif not others[other] then
				others[other] = true
				usedLines += 1
			end
		end
	end
	local slots = ModelMath.productSlots(data.empire and data.empire.office)
	local ok = #replaced > 0 or usedLines < slots
	return {
		ok = ok,
		err = if ok then nil else "LINE_LIMIT",
		line = line,
		replaced = replaced,
		usedLines = usedLines,
		slots = slots,
	}
end

-- Version of a model within its product line: 1 + every model that led to it through replacedBy.
function ModelMath.lineVersion(data: PlayerData, modelId: string): number
	local predecessors: { [string]: { string } } = {}
	for id, model in data.models do
		local successor = (model :: any).replacedBy
		if typeof(successor) == "string" then
			local list = predecessors[successor]
			if not list then
				list = {}
				predecessors[successor] = list
			end
			table.insert(list, id)
		end
	end
	local seen: { [string]: boolean } = { [modelId] = true }
	local queue = { modelId }
	local count = 0
	while #queue > 0 and count < 512 do
		local id = table.remove(queue) :: string
		count += 1
		local before_: { string } = predecessors[id] or {}
		for _, before in before_ do
			if not seen[before] then
				seen[before] = true
				table.insert(queue, before)
			end
		end
	end
	return count
end

-- Models that count toward GameConfig.MODEL_LIMIT: every model that is not retired.
function ModelMath.activeModels(data: PlayerData): number
	local n = 0
	for _, model in data.models do
		if model.status ~= "retired" then
			n += 1
		end
	end
	return n
end

-- Caps every core stat (weight > 0) at ModelConfig.STAT_CAP. Mutates and returns stats with the new overall.
function ModelMath.capStats(stats: Stats): (Stats, number)
	local cap = ModelConfig.STAT_CAP
	for _, stat in ModelConfig.STATS do
		local value = stats[stat.id]
		if stat.weight > 0 and value and value > cap then
			stats[stat.id] = cap
		end
	end
	return stats, ModelMath.overall(stats)
end

-- Next refinement of `model` with the training plan of its size and today's data.
function ModelMath.refinePlan(model: ModelData, plan: Plan): RefinePlan
	local R = ModelConfig.REFINE
	local runs = math.max(0, math.floor(tonumber(model.iterations) or 0))
	local scale = 1 + R.costStep * runs
	local ok = runs < R.limit
	return {
		ok = ok,
		err = if ok then nil else "REFINE_LIMIT",
		runs = runs,
		limit = R.limit,
		scale = scale,
		cost = math.floor(plan.cost * scale),
		work = plan.work * scale,
	}
end

-- Additive gain per core stat of one refinement (CORE_SPEC 7.4); runs = refinements done before this one.
function ModelMath.refineGain(dataQuality: number, qualityMod: number, runs: number): number
	local R = ModelConfig.REFINE
	return (R.gainBase + R.gainQuality * dataQuality) * qualityMod / math.sqrt(1 + math.max(0, runs))
end

-- Seconds since the model's last version (release or refinement): market.vage, older live models market.age.
function ModelMath.versionAge(model: ModelData): number
	local market: any = model.market
	if not market then
		return 0
	end
	local vage = tonumber(market.vage) or tonumber(market.age) or 0
	return math.max(0, vage)
end

-- Fit points a model has lost to age (MarketConfig.AGE = {maxFit, full}); 0 while AGE does not exist.
function ModelMath.ageFit(vage: number): number
	local A = (MarketConfig :: any).AGE
	if typeof(A) ~= "table" or typeof(A.maxFit) ~= "number" or typeof(A.full) ~= "number" or A.full <= 0 then
		return 0
	end
	return A.maxFit * math.clamp(vage / A.full, 0, 1)
end

-- roll() liefert [0, 1). Gibt nil zurück, wenn kein Event eintritt.
function ModelMath.rollEvent(roll: () -> number, specId: string): ModelConfig.EventDef?
	if roll() > ModelConfig.TRAINING.eventChance then
		return nil
	end
	local spec = CompanyConfig.getSpec(specId)
	local breakthroughMult = if spec and spec.breakthroughMult then spec.breakthroughMult else 1
	local function weightOf(event: ModelConfig.EventDef): number
		return event.weight * (if event.id == "breakthrough" then breakthroughMult else 1)
	end
	local total = 0
	for _, event in ModelConfig.EVENTS do
		total += weightOf(event)
	end
	local r = roll() * total
	for _, event in ModelConfig.EVENTS do
		local w = weightOf(event)
		if r < w then
			return event
		end
		r -= w
	end
	return ModelConfig.EVENTS[#ModelConfig.EVENTS]
end

return ModelMath
