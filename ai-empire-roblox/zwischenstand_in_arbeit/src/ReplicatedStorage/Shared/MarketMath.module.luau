--!strict
-- Reine Markt-Simulation: keine Roblox-APIs. Server (Wahrheit), Client (Launch-Prognose)
-- und Tests rechnen mit demselben Code.
--
-- CORE_SPEC 3.1: per segment a nested logit: each company's live models form one nest (NEST_LAMBDA),
-- a model loses LINE_PENALTY outside its product line and ages (AGE); reach is per company and capped by
-- the office stage (STAGE_REACH, opts.reachCap); serving capacity (opts.capacity) creates a waitlist.
-- Pro Segment wählen Nutzer per Softmax zwischen allen Modellen + "keins davon".
-- Ein Spielermodell erreicht nur den Teil des Segments, der es kennt (Reichweite):
--   Reichweite = Firmen-Basis (Reputation) + Marketing-Hype (klingt ab) + Mundpropaganda (wächst mit Marktanteil)
--   Zielnutzer = Pool * Reichweite * Marktanteil; echte Nutzer laufen dem Zielwert hinterher.

local Config = script.Parent.Config
local MarketConfig = require(Config.MarketConfig)
local ModelConfig = require(Config.ModelConfig)
local CompanyConfig = require(Config.CompanyConfig)
local GameConfig = require(Config.GameConfig)
local Types = require(script.Parent.Types)

type Stats = Types.Stats
type MarketState = Types.MarketState
type SegmentDef = MarketConfig.SegmentDef

export type LiveEntry = {
	id: string,
	stats: Stats,
	sizeId: string,
	subPrice: number,
	apiPrice: number,
	market: MarketState, -- wird von tick() fortgeschrieben
	target: string?, -- release target = product line (player models; nil = no line penalty)
	player: boolean?, -- rival entries: true = another player's company (PLAYER_RIVAL_WEIGHT), else an NPC lab
	company: number?, -- rival entries: owner user id (one nest per company)
}

local MarketMath = {}

function MarketMath.fit(stats: Stats, segment: SegmentDef): number
	local fit = 0
	for statId, weight in segment.weights do
		fit += weight * (stats[statId] or 0)
	end
	-- soft cap (CORE_SPEC 3.1): above FIT_SOFT.at a point of fit counts only FIT_SOFT.slope
	local soft = MarketConfig.FIT_SOFT
	if soft and fit > soft.at then fit = soft.at + (fit - soft.at) * soft.slope end
	return fit
end

function MarketMath.utility(stats: Stats, subPrice: number, apiPrice: number, segment: SegmentDef): number
	local price = if segment.priceKind == "api"
		then apiPrice / MarketConfig.PRICE_NORM.api
		else subPrice / MarketConfig.PRICE_NORM.sub
	return (MarketMath.fit(stats, segment) - MarketConfig.FIT_CENTER) / MarketConfig.FIT_SCALE - segment.sens * price
end

function MarketMath.baseReach(reputation: number): number
	local R = MarketConfig.REACH
	return R.base + R.repScale * math.clamp(reputation, 0, 100) / 100
end

function MarketMath.initialHype(target: string, marketing: number): { [string]: number }
	local R = MarketConfig.REACH
	local hype: { [string]: number } = {}
	for _, segment in MarketConfig.SEGMENTS do
		local factor = if target == segment.id
			then R.targetFactor
			elseif target == "general" then R.generalFactor
			else R.spillFactor
		hype[segment.id] = factor * R.hypeMax * (1 - math.exp(-marketing / segment.marketingScale))
	end
	return hype
end

function MarketMath.newMarketState(target: string, marketing: number): MarketState
	return {
		age = 0,
		users = {},
		organic = {},
		hype = MarketMath.initialHype(target, marketing),
		revenueTotal = 0,
		peakUsers = 0,
	}
end

function MarketMath.totalUsers(state: MarketState): number
	local total = 0
	for _, users in state.users do
		total += users
	end
	return total
end

-- Ageing: a model loses up to AGE.maxFit fit points over AGE.full seconds since its last version
-- (release or refinement). market.vage is the version age; market.age keeps driving hype decay.
function MarketMath.agePenalty(vage: number): number
	local A = MarketConfig.AGE
	if not A then return 0 end
	return A.maxFit * math.clamp(vage / A.full, 0, 1) / MarketConfig.FIT_SCALE
end
-- Product lines: a live player model is a product of ONE line (its release target). In the other
-- segments it is still offered, at LINE_PENALTY utility less (specialists beat clones).
function MarketMath.lineOf(target: string?): string
	local map = MarketConfig.LINE_OF or {}
	return map[target or "general"] or "consumers"
end
function MarketMath.playerUtility(entry: any, segment: any): number
	local u = MarketMath.utility(entry.stats, entry.subPrice, entry.apiPrice, segment)
	if entry.target ~= nil and MarketMath.lineOf(entry.target) ~= segment.id then u -= (MarketConfig.LINE_PENALTY or 0) end
	local m = entry.market
	return u - MarketMath.agePenalty(if m then (m.vage or m.age or 0) else 0)
end

-- Ein Simulationsschritt für alle Live-Modelle eines Spielers. Mutiert entry.market.
-- CORE_SPEC market: the player's live models form ONE nest (nested logit, NEST_LAMBDA); reach (reputation +
-- hype + word of mouth) is computed per company and segment and capped by the office stage (STAGE_REACH);
-- other players count only PLAYER_RIVAL_WEIGHT of one average company (rivals with .player = true);
-- NPC labs are full rivals; serving capacity (opts.capacity users) caps the company's users (waitlist).
function MarketMath.tick(models: { LiveEntry }, reputation: number, specId: string, dt: number, rivals: { LiveEntry }?, npcModels: any?, opts: any?): Types.LiveInfo
	local R = MarketConfig.REACH
	local npcList = npcModels or MarketConfig.NPC_MODELS
	local spec = CompanyConfig.getSpec(specId)
	local serveMult = if spec and spec.serveCostMult then spec.serveCostMult else 1
	local enterpriseMult = if spec and spec.enterpriseRevenueMult then spec.enterpriseRevenueMult else 1
	local base = MarketMath.baseReach(reputation)
	-- a bigger headquarters is a better-known brand: + BRAND_REACH[stage] base reach
	if opts and opts.stage and MarketConfig.BRAND_REACH then base += MarketConfig.BRAND_REACH[opts.stage] or 0 end
	local month = GameConfig.GAME_MONTH_SECONDS
	local stage = if opts and opts.stage then opts.stage else #(MarketConfig.STAGE_REACH or { 1 })
	local reachMax = math.min(R.max, if MarketConfig.STAGE_REACH then MarketConfig.STAGE_REACH[stage] or R.max else R.max)
	if opts and opts.reachCap then reachMax = math.min(reachMax, opts.reachCap) end
	local lambda = MarketConfig.NEST_LAMBDA or 1
	local poolScale = MarketConfig.POOL_SCALE or 1
	local capacity = if opts and opts.capacity then opts.capacity else math.huge
	local playerWeight = MarketConfig.PLAYER_RIVAL_WEIGHT or 0

	local result: any = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {}, capacity = capacity, waitlist = 0, demand = 0, load = 0 }
	for _, model in models do
		model.market.age += dt
		local m: any = model.market
		m.vage = (m.vage or (m.age - dt)) + dt
		result.perModel[model.id] = { users = 0, revenue = 0, cost = 0 }
	end
	-- other players grouped per company (best model per segment counts), NPC rivals separately
	local playerGroups: { [any]: { any } } = {}
	local nCompanies = 0
	local npcRivals = {}
	for _, entry in (rivals or {}) :: { LiveEntry } do
		if (entry :: any).player then
			local key = (entry :: any).company or entry.id
			if not playerGroups[key] then playerGroups[key] = {}; nCompanies += 1 end
			table.insert(playerGroups[key], entry)
		else
			table.insert(npcRivals, entry)
		end
	end

	local plans = {}
	local totalTarget = 0
	local totalLoad = 0
	for _, segment in MarketConfig.SEGMENTS do
		local pool = segment.pool * poolScale
		local u: { [string]: number } = {}
		local umax = -math.huge
		for _, model in models do
			local value = MarketMath.playerUtility(model, segment)
			u[model.id] = value
			umax = math.max(umax, value)
		end
		local pivot = math.max(segment.outside, umax)
		local npcU = {}
		for _, entry in npcList do local x = MarketMath.utility(entry.stats, entry.subPrice, entry.apiPrice, segment); npcU[entry.id] = x; pivot = math.max(pivot, x) end
		local rivU = {}
		for i, entry in npcRivals do local x = MarketMath.utility(entry.stats, entry.subPrice, entry.apiPrice, segment); rivU[i] = x; pivot = math.max(pivot, x) end
		local groupU = {}
		for key, list in playerGroups do
			local best = -math.huge
			for _, entry in list do best = math.max(best, MarketMath.playerUtility(entry, segment)) end
			groupU[key] = best
			pivot = math.max(pivot, best)
		end
		local denominator = math.exp(segment.outside - pivot)
		for _, x in rivU do denominator += math.exp(x - pivot) end
		if nCompanies > 0 and playerWeight > 0 then
			for _, x in groupU do denominator += playerWeight / nCompanies * math.exp(x - pivot) end
		end
		local npcWeight: { [string]: number } = {}
		for _, npc in npcList do
			local w = math.exp(npcU[npc.id] - pivot)
			npcWeight[npc.id] = w
			denominator += w
		end
		-- company nest: inclusive value IV = umax + lambda * ln(sum exp((u - umax) / lambda))
		local within: { [string]: number } = {}
		local nestSum = 0
		for _, model in models do
			local w = math.exp((u[model.id] - umax) / lambda)
			within[model.id] = w
			nestSum += w
		end
		local nestWeight = if nestSum > 0 then math.exp(umax - pivot + lambda * math.log(nestSum)) else 0
		denominator += nestWeight
		local nestShare = nestWeight / denominator

		for _, npc in npcList do
			local users = pool * MarketConfig.NPC_REACH * npcWeight[npc.id] / denominator
			result.npcUsers[npc.id] = (result.npcUsers[npc.id] or 0) + users
		end

		-- company reach in this segment: strongest live hype (launches do not stack) + word of mouth
		local hype, organicSum = 0, 0
		for _, model in models do
			local state = model.market
			hype = math.max(hype, (state.hype[segment.id] or 0) * math.exp(-state.age / R.hypeTau))
			organicSum += state.organic[segment.id] or 0
		end
		local reach = math.clamp(base + hype + organicSum, 0, reachMax)
		local seg = { segment = segment, targets = {} }
		for _, model in models do
			local share = nestShare * within[model.id] / nestSum
			local state = model.market
			local organic = state.organic[segment.id] or 0
			organic += (R.organicShare * share - organic) * math.min(1, R.organicRate * dt)
			state.organic[segment.id] = organic
			local target = pool * reach * share
			seg.targets[model.id] = target
			totalTarget += target
			-- compute per user grows with model size (SERVE_UNITS: 500M model = 1)
			totalLoad += target * ((MarketConfig.SERVE_UNITS or {})[model.sizeId] or 1)
		end
		table.insert(plans, seg)
	end
	-- serving capacity (in 500M-model user equivalents): the company serves at most `capacity`; the rest wait
	local served = if totalLoad > capacity then capacity / totalLoad else 1
	result.demand = totalTarget
	result.load = totalLoad
	result.waitlist = totalTarget * (1 - served)
	for _, seg in plans do
		local segment = seg.segment
		for _, model in models do
			local target = seg.targets[model.id] * served
			local state = model.market
			local users = state.users[segment.id] or 0
			local tau = if target > users then MarketConfig.USERS.riseTau else MarketConfig.USERS.fallTau
			users += (target - users) * (1 - math.exp(-dt / tau))
			state.users[segment.id] = users

			local size = ModelConfig.getSize(model.sizeId)
			local millionTokens = users * segment.tokensPerUser / 1e6
			local revenue = if segment.priceKind == "api"
				then millionTokens * model.apiPrice * (if segment.enterprise then enterpriseMult else 1)
				else users * model.subPrice
			local cost = millionTokens * (if size then size.serveCost else 0) * serveMult

			local perModel = result.perModel[model.id]
			perModel.users += users
			perModel.revenue += revenue / month
			perModel.cost += cost / month
		end
	end

	for _, model in models do
		local perModel = result.perModel[model.id]
		model.market.peakUsers = math.max(model.market.peakUsers, perModel.users)
		model.market.revenueTotal += perModel.revenue * dt
		result.users += perModel.users
		result.revenue += perModel.revenue
		result.cost += perModel.cost
	end
	return result
end

function MarketMath.reputationStep(reputation: number, totalUsers: number, bestOverall: number, dt: number): number
	local P = MarketConfig.REPUTATION
	local target = math.min(100, P.userPart * (1 - math.exp(-totalUsers / P.userScale)) + P.qualityPart * bestOverall)
	return reputation + (target - reputation) * math.min(1, P.rate * dt)
end

local function cloneEntry(entry: LiveEntry): LiveEntry
	local m = entry.market
	return {
		id = entry.id,
		stats = entry.stats,
		sizeId = entry.sizeId,
		subPrice = entry.subPrice,
		apiPrice = entry.apiPrice,
		target = entry.target,
		market = {
			age = m.age,
			vage = m.vage,
			users = table.clone(m.users),
			organic = table.clone(m.organic),
			hype = table.clone(m.hype),
			revenueTotal = m.revenueTotal,
			peakUsers = m.peakUsers,
		},
	}
end

-- Prognose für den Release-Screen: simuliert `seconds` Sekunden auf Kopien.
function MarketMath.forecast(
	candidate: LiveEntry,
	others: { LiveEntry },
	reputation: number,
	specId: string,
	seconds: number
): Types.LiveModelResult
	local list = { cloneEntry(candidate) }
	for _, other in others do
		table.insert(list, cloneEntry(other))
	end
	local result: Types.LiveModelResult = { users = 0, revenue = 0, cost = 0 }
	for _ = 1, math.max(1, math.floor(seconds / 5)) do
		result = MarketMath.tick(list, reputation, specId, 5).perModel[candidate.id]
	end
	return result
end

return MarketMath
