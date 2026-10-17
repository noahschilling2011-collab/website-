--!strict
-- Shared helpers of the Lab and Market apps (models package, CORE_SPEC 7): product lines, Lab level,
-- serving capacity, auto-price and robust remote calls. No Instances are built here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local ModelConfig = require(Shared.Config.ModelConfig)
local EmpireConfig = require(Shared.Config.EmpireConfig)
local ModelMath = require(Shared.ModelMath)
local PricingMath = require(Shared.PricingMath)
local Format = require(Shared.Format)
local Types = require(Shared.Types)

local Client = script.Parent.Parent.Parent
local ActionController = require(Client.Controllers.ActionController)
local Toast = require(script.Parent.Parent.Toast)

type ModelData = Types.ModelData
type PlayerData = Types.PlayerData

local ModelsUI = {}

-- Texts for the models error codes, used only while ActionController has none of its own.
local MESSAGES: { [string]: string } = {
	LINE_LIMIT = "All product lines of this office are taken. Release a new version into a live line, or move to a bigger office for another line.",
	REFINE_LIMIT = "This model was already refined 3 times. Train a new version instead.",
	MODEL_LIMIT = "Your company reached the limit of 80 active models. Retire old models first.",
	MAX_LEVEL = "The Lab is at its highest level.",
	PREREQUISITE = "Finish the whole research tree first.",
	NO_POINTS = "Not enough research points. Hire researchers to generate more.",
	NO_MONEY = "Not enough money.",
	UNAVAILABLE = "This needs the next server update.",
}

function ModelsUI.message(err: string?): string
	local text = ActionController.message(err)
	if text == "Something went wrong." and err and MESSAGES[err] then
		return MESSAGES[err]
	end
	return text
end

function ModelsUI.hasRemote(name: string): boolean
	return table.find(Net.FUNCTIONS, name) ~= nil
end

-- ActionController.call with the models texts. Never waits for a remote the server does not have.
function ModelsUI.call(name: string, payload: { [string]: any }): (boolean, { [string]: any })
	if not ModelsUI.hasRemote(name) then
		Toast.show("error", MESSAGES.UNAVAILABLE)
		return false, { ok = false, err = "UNAVAILABLE" }
	end
	local ok, result = ActionController.call(name, payload, true)
	if not ok and result.err ~= "BUSY" then
		Toast.show("error", ModelsUI.message(result.err))
	end
	return ok, result
end

-- Auto-price on/off (CORE_SPEC 7.7): EmpireAction {action="autoPrice"}; until the server has EmpireAction,
-- UpdatePricing {modelId, auto} is the same switch.
function ModelsUI.setAutoPrice(modelId: string, on: boolean): boolean
	if ModelsUI.hasRemote("EmpireAction") then
		return (ModelsUI.call("EmpireAction", { action = "autoPrice", model = modelId, modelId = modelId, on = on }))
	end
	return (ModelsUI.call("UpdatePricing", { modelId = modelId, auto = on }))
end

---------------------------------------------------------------------------- lines

function ModelsUI.lineLabel(target: string?): string
	local line = ModelConfig.getLine(target)
	return if line then line.label else "Model"
end

function ModelsUI.officeName(stage: number?): string
	local def = EmpireConfig.OFFICES[math.clamp(math.floor(tonumber(stage) or 1), 1, #EmpireConfig.OFFICES)]
	return if def then def.name else "Office"
end

-- First office (index) whose product slots exceed `used` lines, or nil.
function ModelsUI.officeForLines(lines: number): number?
	for stage = 1, #EmpireConfig.OFFICES do
		if ModelMath.productSlots(stage) > lines then
			return stage
		end
	end
	return nil
end

export type LineRow = {
	line: ModelConfig.LineDef,
	model: ModelData?, -- the live model of the line (first in model order)
	extra: number, -- more live models in the line (old saves from before product lines)
	version: number, -- line version of `model`
	open: boolean, -- no live model, but a free slot
}

-- One row per product line in ModelConfig.LINES order, plus used lines and slots of the office.
function ModelsUI.lines(data: PlayerData): ({ LineRow }, number, number)
	local byLine, used = ModelMath.liveLines(data)
	local slots = ModelMath.productSlots(data.empire.office)
	local rows: { LineRow } = {}
	for _, line in ModelConfig.LINES do
		local list = byLine[ModelMath.lineOf(line.target)]
		local model = if list then list[1] else nil
		table.insert(rows, {
			line = line,
			model = model,
			extra = if list then #list - 1 else 0,
			version = if model then ModelMath.lineVersion(data, model.id) else 0,
			open = model == nil and used < slots,
		})
	end
	return rows, used, slots
end

-- "age 41 min · -5 fit" (CORE_SPEC 7.3: up to -8 fit points after 3 game days)
function ModelsUI.ageText(model: ModelData): string
	local vage = ModelMath.versionAge(model)
	local fit = ModelMath.ageFit(vage)
	local minutes = math.floor(vage / 60)
	local age = if minutes < 1 then "new" else `age {minutes} min`
	return if fit >= 0.5 then `{age} · -{string.format("%.0f", fit)} fit` else age
end

-- The model this one replaced in its line (the newest predecessor), or nil.
function ModelsUI.predecessor(data: PlayerData, modelId: string): ModelData?
	local best: ModelData? = nil
	for _, id in data.modelOrder do
		local model = data.models[id]
		if model and (model :: any).replacedBy == modelId then
			best = model
		end
	end
	return best
end

-- Status line of a live model's price: auto on/off and the last automatic change (live.pricing[id].note).
function ModelsUI.autoPriceText(live: any, model: ModelData): string
	local release: any = model.release
	if not release or release.auto == false then
		return "Manual price. Switch to Auto price to use the Recommended price again."
	end
	local pricing = if typeof(live) == "table" then live.pricing else nil
	local entry = if typeof(pricing) == "table" then pricing[model.id] else nil
	if typeof(entry) == "table" and typeof(entry.note) == "string" then
		return "Auto: " .. entry.note
	end
	return `Auto price: re-checks the best menu price every {math.floor(ModelConfig.PRICING.autoPeriod / 60 + 0.5)} minutes.`
end

function ModelsUI.refineText(model: ModelData): string
	return `refined {math.floor(tonumber(model.iterations) or 0)}/{ModelConfig.REFINE.limit}`
end

---------------------------------------------------------------------------- Lab level

local opsModule: any = nil
local function companyOps(): any
	if opsModule == nil then
		local found = Shared:FindFirstChild("CompanyOps")
		if not (found and found:IsA("ModuleScript")) then
			return nil
		end
		local ok, result = pcall(require, found)
		opsModule = if ok then result else false
	end
	return if opsModule then opsModule else nil
end

export type LabInfo = {
	level: number,
	max: number,
	points: number, -- research points for the next level
	cash: number, -- dollars for the next level
	treeDone: boolean, -- the whole research tree is finished (Lab levels come after it)
	canBuy: boolean,
	reason: string, -- why not, or what the next level costs
}

-- CORE_SPEC 7.5: level L -> L+1 costs floor(200 * 1.35^L) points and $floor(6000 * 1.6^L), +1 core stat on
-- future models, max 10. The price comes from CompanyOps.labCost when the econ package provides it.
function ModelsUI.lab(data: PlayerData, money: number): LabInfo
	local e = data.empire
	local ops = companyOps()
	local max = if ops and typeof(ops.LAB_MAX) == "number" then ops.LAB_MAX else 10
	local level = math.clamp(math.floor(tonumber(e.labLevel) or 0), 0, max)
	local points, cash
	if ops and typeof(ops.labCost) == "function" then
		points, cash = ops.labCost(level)
	end
	points = tonumber(points) or math.floor(200 * 1.35 ^ level)
	cash = tonumber(cash) or math.floor(6000 * 1.6 ^ level)
	local treeDone = true
	for _, def in EmpireConfig.RESEARCH do
		if not e.research[def.id] then
			treeDone = false
		end
	end
	local reason: string
	if level >= max then
		reason = "Highest level reached"
	elseif not treeDone then
		reason = "Unlocks after the whole research tree"
	elseif (tonumber(e.points) or 0) < points then
		reason = `Needs {Format.int(points)} research points`
	elseif money < cash then
		reason = `Needs {Format.money(cash)}`
	else
		reason = `Next level: {Format.int(points)} RP + {Format.money(cash)}`
	end
	return {
		level = level,
		max = max,
		points = points,
		cash = cash,
		treeDone = treeDone,
		canBuy = level < max and treeDone and (tonumber(e.points) or 0) >= points and money >= cash,
		reason = reason,
	}
end

---------------------------------------------------------------------------- serving capacity

export type Serving = { known: boolean, capacity: number, load: number, waitlist: number, full: number, text: string }

-- From live.capacity / live.load / live.waitlist (MarketService, CORE_SPEC 3.1), when present.
function ModelsUI.serving(live: any): Serving
	local capacity = if typeof(live) == "table" then tonumber(live.capacity) else nil
	local load = if typeof(live) == "table" then tonumber(live.load) else nil
	local waitlist = if typeof(live) == "table" then tonumber(live.waitlist) else nil
	if not capacity or capacity ~= capacity or capacity == math.huge or not load then
		return { known = false, capacity = 0, load = 0, waitlist = 0, full = 0, text = "" }
	end
	local full = if capacity > 0 then load / capacity else (if load > 0 then math.huge else 0)
	local wait = math.max(0, waitlist or 0)
	local text
	if wait >= 1 then
		text = `{Format.int(wait)} waiting — buy GPUs`
	elseif full >= 0.85 then
		text = `Servers {Format.percent(math.min(full, 9.99))} full — add GPUs before the next launch`
	else
		text = `Servers {Format.percent(full)} full`
	end
	return { known = true, capacity = capacity, load = load, waitlist = wait, full = full, text = text }
end

---------------------------------------------------------------------------- business clients

-- One line about the signed business clients (CompanyOps accounts), e.g.
-- "3 business clients · $31,500/day in retainers. Your sales team signs and renews them by visits."
function ModelsUI.businessText(data: PlayerData): string
	local e: any = data.empire
	local deals = if typeof(e) == "table" then e.deals else nil
	local accounts = if typeof(deals) == "table" then deals.accounts else nil
	local ops = companyOps()
	local count, retainer = 0, 0
	if typeof(accounts) == "table" then
		for id in accounts do
			count += 1
			local client = if ops and typeof(ops.client) == "function" then ops.client(id) else nil
			if typeof(client) == "table" and typeof(client.retainer) == "number" then
				retainer += client.retainer
			end
		end
	end
	if count == 0 then
		return "No business clients yet. Your founder and the Growth & Sales field reps visit clients and sign them; a client needs a live model strong enough in its stat."
	end
	local money = if retainer > 0 then ` · {Format.money(retainer)}/day in retainers` else ""
	return `{count} business client{if count == 1 then "" else "s"}{money}. Your sales team keeps them with check-in visits.`
end

---------------------------------------------------------------------------- pricing inputs on the client

-- Forecast context from the snapshot: rivals from the replicated marketplace offers (own models excluded).
function ModelsUI.context(snapshot: Types.Snapshot): PricingMath.Context
	local data = snapshot.data
	local own: { [string]: any } = {}
	for id in data.models do
		own[id] = true
	end
	local market: any = snapshot.live.marketplace
	local offers = if typeof(market) == "table" then market.offers else nil
	local rivals = PricingMath.rivalsFromOffers(offers, own)
	local npc = false
	for _, rival in rivals do
		if rival.player == false then
			npc = true
		end
	end
	-- MarketService passes {} as the static NPC list while NPC labs run as sessions (their offers are listed)
	return PricingMath.context(data, rivals, if npc then {} else nil)
end

function ModelsUI.priceText(sub: number, api: number): string
	return (if sub == 0 then "Free" else `${sub}/month`) .. ` · {Format.price(api)} per 1M tokens`
end

return ModelsUI
