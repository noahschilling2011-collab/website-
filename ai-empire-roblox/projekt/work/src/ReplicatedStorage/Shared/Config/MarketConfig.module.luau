--!strict
-- KI-Markt: Nutzersegmente, NPC-Konkurrenz, Preisgrenzen, Reichweite und Reputation.
-- Die Formeln stehen in Shared/MarketMath.

export type SegmentDef = {
	id: string,
	label: string,
	pool: number, -- erreichbare Nutzer im Segment
	priceKind: "sub" | "api", -- welcher Preis zählt: Monatsabo oder API-Preis
	sens: number, -- Preisempfindlichkeit
	outside: number, -- Nutzen der Option "nutze keins davon"
	tokensPerUser: number, -- Verbrauch pro Nutzer und Spielmonat
	marketingScale: number, -- $-Betrag, bei dem Marketing ~63% seiner Maximalwirkung erreicht
	enterprise: boolean?,
	weights: { [string]: number }, -- was das Segment an einem Modell schätzt (Summe = 1)
}

export type NPCModelDef = {
	id: string,
	company: string,
	name: string,
	rgb: { number },
	subPrice: number,
	apiPrice: number,
	stats: { [string]: number },
}

local MarketConfig = {}

MarketConfig.SEGMENTS = {
	{
		id = "developers",
		label = "Developers",
		pool = 2.5e5, -- CORE_SPEC 3.1 (x POOL_SCALE)
		priceKind = "api",
		sens = 0.8,
		outside = -0.6,
		tokensPerUser = 3e6,
		marketingScale = 15_000,
		weights = { coding = 0.45, reasoning = 0.25, speed = 0.1, reliability = 0.2 },
	},
	{
		id = "students",
		label = "Students",
		pool = 3.75e5,
		priceKind = "sub",
		sens = 1.6,
		outside = -0.3,
		tokensPerUser = 3e5,
		marketingScale = 30_000,
		weights = { knowledge = 0.3, math = 0.25, reasoning = 0.2, creativity = 0.15, speed = 0.1 },
	},
	{
		id = "businesses",
		label = "Businesses",
		pool = 6e4,
		priceKind = "api",
		sens = 0.35,
		outside = -0.4,
		tokensPerUser = 1.2e7,
		marketingScale = 40_000,
		enterprise = true,
		weights = { reliability = 0.35, knowledge = 0.2, reasoning = 0.2, coding = 0.15, speed = 0.1 },
	},
	{
		id = "consumers",
		label = "General",
		pool = 7e5,
		priceKind = "sub",
		sens = 1.1,
		outside = 0.2,
		tokensPerUser = 1.5e5,
		marketingScale = 80_000,
		weights = { creativity = 0.35, knowledge = 0.35, speed = 0.1, reasoning = 0.2 },
	},
} :: { SegmentDef }

-- Release-Ziel: ein Segment oder "general" (verteilt, schwächer pro Segment)
MarketConfig.TARGETS = { "developers", "students", "businesses", "general" } :: { string }

MarketConfig.SUB_PRICES = { 0, 5, 10, 20 } :: { number } -- $ pro Spielmonat
MarketConfig.API_PRICE = { min = 0.2, max = 20, step = 0.1, default = 2 } -- $ pro 1M Tokens
MarketConfig.MARKETING = { max = 250_000, step = 500 }

-- Nutzen = (Fit - FIT_CENTER) / FIT_SCALE - sens * Preis / PRICE_NORM
MarketConfig.FIT_CENTER = 50
MarketConfig.FIT_SCALE = 30
-- fit soft cap (MarketMath.fit): above `at` a stat point counts only `slope`
MarketConfig.FIT_SOFT = { at = 75, slope = 0.35 }
MarketConfig.PRICE_NORM = { sub = 10, api = 5 }

MarketConfig.REACH = {
	base = 0.01, -- Bekanntheit einer unbekannten Firma
	repScale = 0.3, -- + so viel bei Reputation 100
	max = 0.9,
	hypeMax = 0.5, -- Marketing-Obergrenze im Zielsegment
	hypeTau = 600, -- Sekunden, bis Marketing-Hype auf ~37% abgeklungen ist
	targetFactor = 1,
	generalFactor = 0.45,
	spillFactor = 0.12, -- Streuwirkung auf Nicht-Zielsegmente
	organicShare = 0.6, -- Mundpropaganda wächst Richtung organicShare * Marktanteil
	organicRate = 1 / 240,
}

MarketConfig.USERS = { riseTau = 40, fallTau = 120 } -- Sekunden bis ~63% des Zielwerts

MarketConfig.REPUTATION = { userScale = 5e5, userPart = 60, qualityPart = 0.4, rate = 1 / 300 }

MarketConfig.NPC_REACH = 0.8

-- Phase 1: statische Konkurrenz. später (Phase 5): NPC-Firmen mit Strategie und eigenen Releases
MarketConfig.NPC_MODELS = {
	{
		id = "npc_nc3",
		company = "NeuralCore",
		name = "NC-3",
		rgb = { 239, 68, 68 },
		subPrice = 20,
		apiPrice = 6,
		stats = { reasoning = 62, coding = 60, math = 58, creativity = 60, knowledge = 66, reliability = 68, speed = 70 },
	},
	{
		id = "npc_titan",
		company = "Titan Intelligence",
		name = "Titan Code 2",
		rgb = { 245, 158, 11 },
		subPrice = 10,
		apiPrice = 3,
		stats = { reasoning = 58, coding = 72, math = 60, creativity = 40, knowledge = 52, reliability = 62, speed = 76 },
	},
	{
		id = "npc_orion",
		company = "Orion AI",
		name = "Orion Edu",
		rgb = { 16, 185, 129 },
		subPrice = 5,
		apiPrice = 1.5,
		stats = { reasoning = 54, coding = 44, math = 62, creativity = 48, knowledge = 62, reliability = 58, speed = 78 },
	},
	{
		id = "npc_muse",
		company = "BlueMind",
		name = "Blue Muse",
		rgb = { 59, 130, 246 },
		subPrice = 0,
		apiPrice = 2,
		stats = { reasoning = 50, coding = 38, math = 36, creativity = 66, knowledge = 58, reliability = 54, speed = 80 },
	},
	{
		id = "npc_vlite",
		company = "Vector Labs",
		name = "Vector Lite",
		rgb = { 148, 163, 184 },
		subPrice = 0,
		apiPrice = 0.4,
		stats = { reasoning = 44, coding = 42, math = 40, creativity = 46, knowledge = 48, reliability = 50, speed = 92 },
	},
} :: { NPCModelDef }

-- CORE_SPEC 3.1 / 7.1 / 11.6: company nest, product lines, ageing, stage reach, serving capacity
MarketConfig.POOL_SCALE = 1.5 -- every segment pool x this
MarketConfig.NEST_LAMBDA = 0.05 -- one company = one nest: a clone adds ~4 %, a specialist per line pays
MarketConfig.LINE_PENALTY = 0.6 -- utility lost in segments outside the model's product line (~18 fit points)
-- release target -> product line (segment the model is built for)
MarketConfig.LINE_OF = { developers = "developers", students = "students", businesses = "businesses", general = "consumers" } :: { [string]: string }
-- live product lines per office stage (Garage .. Global AI HQ)
MarketConfig.PRODUCT_SLOTS = { 1, 2, 3, 4, 4 } :: { number }
MarketConfig.MIGRATE = 0.9 -- share of users (per segment) a new version takes over from its predecessor
MarketConfig.AGE = { maxFit = 8, full = 3600 } -- a model loses up to 8 fit points over 3600 s since its last version
-- market reach cap per office stage and the brand reach a bigger HQ adds to the base reach
MarketConfig.STAGE_REACH = { 0.25, 0.25, 0.30, 0.40, 0.55 } :: { number }
MarketConfig.BRAND_REACH = { 0, 0.02, 0.05, 0.09, 0.15 } :: { number }
-- all other player companies together weigh this much of ONE company in a segment
MarketConfig.PLAYER_RIVAL_WEIGHT = 0.15
-- compute per served user by model size (500M model = 1); capacity in CompanyOps.capacity
MarketConfig.SERVE_UNITS = { s100m = 0.5, s500m = 1, s1b = 1.4, s3b = 2.2, s7b = 3 } :: { [string]: number }

function MarketConfig.isTarget(id: string): boolean
	return table.find(MarketConfig.TARGETS, id) ~= nil
end

function MarketConfig.isSubPrice(price: number): boolean
	return table.find(MarketConfig.SUB_PRICES, price) ~= nil
end

return MarketConfig
