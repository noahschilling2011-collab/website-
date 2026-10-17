--!strict
-- KI-Modelle: Größen, Trainingsfokus, Stats und die Stellschrauben der Leistungsformel.
-- Die Formel selbst steht in Shared/ModelMath.

export type SizeDef = {
	id: string,
	label: string,
	potential: number, -- Obergrenze der Kern-Intelligenz bei perfekten Daten (Phase-1-Architektur)
	dataNeed: number, -- Tokens, ab denen die Daten "satt" sind (Füllgrad 1.0)
	work: number, -- Rechenarbeit in Compute-Einheiten
	vram: number, -- benötigter Grafikspeicher (GB, über alle GPUs summiert)
	serveCost: number, -- Inferenzkosten in $ pro 1M Tokens (Cloud)
	speed: number,
	efficiency: number,
}

export type FocusDef = { id: string, label: string, mult: { [string]: number } }
export type StatDef = { id: string, label: string, weight: number }

export type ChoiceDef = {
	id: string,
	label: string,
	desc: string,
	timeMult: number?, -- Multiplikator auf die RESTLICHE Arbeit
	quality: number?, -- Multiplikator auf die Modellqualität
	costFactor: number?, -- Zusatzkosten als Anteil der Trainingskosten
	gamble: number?, -- Wahrscheinlichkeit, dass "quality" tatsächlich greift
}

export type EventDef = {
	id: string,
	title: string,
	text: string,
	weight: number,
	choices: { ChoiceDef }?, -- vorhanden = Entscheidungs-Event, Training pausiert bis zur Wahl
	default: string?, -- Wahl bei Timeout
	timeMult: number?, -- Sofort-Effekt bei Events ohne Wahl
	quality: number?,
}

local ModelConfig = {}

-- Phase 1: vier Größen. 7B+ kommen mit Research/Infrastruktur (Phase 2/4) als neue Einträge hier.
ModelConfig.SIZES = {
	{
		id = "s100m",
		label = "100M",
		potential = 46,
		dataNeed = 1.5e9,
		work = 40,
		vram = 4,
		serveCost = 0.04,
		speed = 94,
		efficiency = 92,
	},
	{
		id = "s500m",
		label = "500M",
		potential = 57,
		dataNeed = 5e9,
		work = 150,
		vram = 12,
		serveCost = 0.15,
		speed = 84,
		efficiency = 82,
	},
	{
		id = "s1b",
		label = "1B",
		potential = 63,
		dataNeed = 1e10,
		work = 320,
		vram = 24,
		serveCost = 0.3,
		speed = 76,
		efficiency = 74,
	},
	{
		id = "s3b",
		label = "3B",
		potential = 71,
		dataNeed = 2.5e10,
		work = 900,
		vram = 64,
		serveCost = 0.8,
		speed = 64,
		efficiency = 62,
	},
	{ id="s7b", label="7B", potential=83, dataNeed=5e10, work=1600, vram=128, serveCost=1.25, speed=56, efficiency=52 },
} :: { SizeDef }

ModelConfig.FOCUSES = {
	{ id = "balanced", label = "Balanced", mult = {} },
	{
		id = "coding",
		label = "Coding",
		mult = { coding = 1.18, reasoning = 1.04, creativity = 0.88, knowledge = 0.94 },
	},
	{
		id = "reasoning",
		label = "Reasoning",
		mult = { reasoning = 1.16, math = 1.1, creativity = 0.9, coding = 0.96 },
	},
	{
		id = "creative",
		label = "Creative",
		mult = { creativity = 1.2, knowledge = 1.04, math = 0.86, coding = 0.88 },
	},
} :: { FocusDef }

-- weight = Anteil am Overall-Score. Speed/Efficiency zählen nicht ins Overall,
-- sie wirken über Markt (Speed) und Kosten (Efficiency = Spiegel der Inferenzkosten).
ModelConfig.STATS = {
	{ id = "reasoning", label = "Reasoning", weight = 0.22 },
	{ id = "coding", label = "Coding", weight = 0.17 },
	{ id = "math", label = "Math", weight = 0.14 },
	{ id = "creativity", label = "Creativity", weight = 0.14 },
	{ id = "knowledge", label = "Knowledge", weight = 0.17 },
	{ id = "reliability", label = "Reliability", weight = 0.16 },
	{ id = "speed", label = "Speed", weight = 0 },
	{ id = "efficiency", label = "Efficiency", weight = 0 },
} :: { StatDef }

-- Datenmix -> Stat: base + Summe(Anteil des Datentyps * Faktor)
ModelConfig.AFFINITY = {
	reasoning = { base = 0.85, code = 0.35, math = 0.35 },
	coding = { base = 0.75, code = 0.9 },
	math = { base = 0.75, math = 0.9 },
	creativity = { base = 0.8, general = 0.4 },
	knowledge = { base = 0.8, general = 0.4 },
} :: { [string]: { [string]: number } }

-- Reliability hängt an der Datenqualität, nicht am Mix
ModelConfig.RELIABILITY = { base = 0.7, quality = 0.5 }

-- Datenwirkung: quantity = 1 - e^(-quantityK * Füllgrad), quality = qualityBase + qualityK * Q
-- Kern = potential * (floor + (1 - floor) * quantity * quality). Füllgrad ist bei maxFill gedeckelt:
-- mehr Masse bringt dann nichts mehr, schlechte Qualität zieht aber weiter runter.
ModelConfig.DATA = {
	quantityK = 1.6,
	qualityBase = 0.55,
	qualityK = 0.45,
	floor = 0.45,
	maxFill = 2,
}

ModelConfig.TRAINING = {
	minSeconds = 12,
	minTokens = 1e8, -- darunter kein Training
	eventAt = 0.35, -- ab diesem Fortschritt wird einmal ein Event gewürfelt
	eventChance = 0.6,
	decisionTimeout = 25, -- Sekunden, danach greift die Default-Wahl
	noise = 2.5, -- ± Streuung pro Stat
	lossStart = 4.2,
	lossPoints = 48, -- so viele Loss-Werte merkt sich der Graph
	logLines = 6,
}

-- Annotation statt Cast, damit die verschachtelten Choice-Tabellen korrekt typgeprüft werden
local EVENTS: { EventDef } = {
	{
		id = "data_issue",
		title = "DATA ISSUE DETECTED",
		text = "Duplicate shards found in the training set.",
		weight = 3,
		choices = {
			{ id = "clean", label = "Clean it", desc = "+20% remaining time, +15% cost", timeMult = 1.2, costFactor = 0.15 } :: ChoiceDef,
			{ id = "ignore", label = "Ignore", desc = "-6% model quality", quality = 0.94 } :: ChoiceDef,
		},
		default = "ignore",
	},
	{
		id = "instability",
		title = "TRAINING INSTABILITY",
		text = "Loss spike detected.",
		weight = 3,
		choices = {
			{ id = "rollback", label = "Roll back", desc = "+25% remaining time", timeMult = 1.25 } :: ChoiceDef,
			{ id = "push", label = "Push through", desc = "50% chance: -10% quality", quality = 0.9, gamble = 0.5 } :: ChoiceDef,
		},
		default = "rollback",
	},
	{ id = "gpu_failure", title = "GPU FAILURE", text = "A GPU crashed. Shard restarted.", weight = 2, timeMult = 1.15 },
	{
		id = "breakthrough",
		title = "BREAKTHROUGH",
		text = "Better learning-rate schedule found.",
		weight = 2,
		quality = 1.05,
	},
	{
		id = "optimization",
		title = "OPTIMIZATION FOUND",
		text = "Kernel fusion speeds up training.",
		weight = 2,
		timeMult = 0.8,
	},
}
ModelConfig.EVENTS = EVENTS

-- Product lines (CORE_SPEC 7.1): the release target is the product line. One live model per line; a release
-- into a line that already has a live model is its next version. The market side (MarketConfig.LINE_OF,
-- PRODUCT_SLOTS, LINE_PENALTY, MarketMath.lineOf) owns the numbers; this table only names the lines for the
-- UI, in display order. `segment` mirrors MarketConfig.LINE_OF and is used only when that table is missing.
export type LineDef = { target: string, segment: string, label: string, short: string }
ModelConfig.LINES = {
	{ target = "general", segment = "consumers", label = "Consumer Chat", short = "Chat" },
	{ target = "students", segment = "students", label = "Study App", short = "Study" },
	{ target = "developers", segment = "developers", label = "Developer API", short = "Dev API" },
	{ target = "businesses", segment = "businesses", label = "Business API", short = "Business" },
} :: { LineDef }

-- Share of the predecessor's users (per segment) a new version of a line takes over (CORE_SPEC 7.2).
ModelConfig.MIGRATE = 0.9

-- Refinement (CORE_SPEC 7.4): at most `limit` runs per model, cost = plan.cost * (1 + costStep * runs so far),
-- additive gain per core stat = (gainBase + gainQuality * data quality) * qualityMod / sqrt(1 + runs so far).
ModelConfig.REFINE = { limit = 3, costStep = 0.5, gainBase = 1, gainQuality = 4 }

-- Every core stat (weight > 0) is capped here (CORE_SPEC 7.5; EmpireMath.boostStats caps too).
ModelConfig.STAT_CAP = 99

-- Retired models do not count toward GameConfig.MODEL_LIMIT. To keep saves bounded, the oldest retired
-- models beyond this many are pruned when a new model is created (never one a project or training needs).
ModelConfig.RETIRED_KEEP = 80

-- Release pricing (CORE_SPEC 7.7): "Recommended" = forecast-optimal price on a small menu with marketing up to
-- `marketingMax`, over `releaseHorizon` s. Auto-price (default on per model, model.release.auto) re-runs the
-- same forecast every `autoPeriod` s over `autoHorizon` s.
-- `step` = forecast tick in seconds. The simulator used 5 s; 15 s gives the same menu choice (tests/models
-- compare both) at a third of the cost - one menu price with 12 full companies on a server is 60 market ticks.
-- CPU budgets (seconds of os.clock per frame) keep server and client frames flat: auto-price jobs of the whole
-- server advance in a Heartbeat worker within `frameBudget` per frame (a full server's 5-minute cycle needs
-- well under a minute of frames); the Recommended price inside a release request yields a frame whenever
-- `releaseBudget` is used up; the Lab app's preview does the same with `clientBudget`.
ModelConfig.PRICING = {
	subs = { 5, 10 },
	apis = { 1, 2, 3, 4 },
	marketingMax = 5000,
	releaseHorizon = 1800,
	autoPeriod = 300,
	-- first auto-price cycle this many seconds after the company starts ticking (founding or login), then every
	-- autoPeriod: the phase of the validated design bot (CORE_SPEC 9, sim_final "sec % 300 == 150"), so the first
	-- live model (released at ~1.3 min) is re-priced ~1 min later instead of after 5 minutes
	autoFirst = 150,
	autoHorizon = 900,
	step = 15,
	frameBudget = 0.0015,
	releaseBudget = 0.004,
	clientBudget = 0.004,
	-- the release card's own forecast window (users and $/day shown after this many seconds)
	cardSeconds = 300,
}

function ModelConfig.getLine(target: string?): LineDef?
	for _, line in ModelConfig.LINES do
		if line.target == target then
			return line
		end
	end
	return nil
end

ModelConfig.RECIPES={
 {id="steady",label="Balanced",work=1,quality=1,desc="A measured run with stable validation. Standard time and cost."},
 {id="rapid",label="Quick pass",work=.65,quality=.9,desc="35% less compute; lower capability gain. Useful for an early prototype."},
 {id="deep",label="Deep training",work=2.4,quality=1.25,desc="2.4x compute. Higher gains with enough data; small or poor datasets can overfit."},
}
function ModelConfig.getRecipe(id: string): any
 for _,recipe in ModelConfig.RECIPES do if recipe.id==id then return recipe end end
 return nil
end
function ModelConfig.getSize(id: string): SizeDef?
	for _, size in ModelConfig.SIZES do
		if size.id == id then
			return size
		end
	end
	return nil
end

function ModelConfig.getFocus(id: string): FocusDef?
	for _, focus in ModelConfig.FOCUSES do
		if focus.id == id then
			return focus
		end
	end
	return nil
end

function ModelConfig.getEvent(id: string): EventDef?
	for _, event in ModelConfig.EVENTS do
		if event.id == id then
			return event
		end
	end
	return nil
end

function ModelConfig.getChoice(event: EventDef, choiceId: string): ChoiceDef?
	if not event.choices then
		return nil
	end
	for _, choice in event.choices do
		if choice.id == choiceId then
			return choice
		end
	end
	return nil
end

return ModelConfig
