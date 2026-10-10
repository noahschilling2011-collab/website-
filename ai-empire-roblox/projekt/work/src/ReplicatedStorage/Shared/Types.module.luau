--!strict
-- Zentrale Datentypen. Alles, was gespeichert oder an den Client geschickt wird, ist hier beschrieben.
-- Regel für gespeicherte Daten: nur string-Keys in Dictionaries, Arrays lückenlos (DataStore = JSON).

export type Stats = { [string]: number }

export type DataStock = { tokens: number, quality: number }

export type DataSummary = { total: number, quality: number, shares: { [string]: number } }

export type Fleet = { throughput: number, vram: number, costPerWork: number, slotsUsed: number }

export type MarketState = {
	age: number, -- Sekunden seit Release (nur Online-Zeit)
	users: { [string]: number }, -- Nutzer pro Segment
	organic: { [string]: number }, -- Mundpropaganda-Reichweite pro Segment
	hype: { [string]: number }, -- Marketing-Reichweite pro Segment beim Launch
	revenueTotal: number,
	peakUsers: number,
	vage: number?, -- Sekunden seit der letzten Version (Release oder Refinement): Alterung (CORE_SPEC 7.3)
}

export type ReleaseConfig = {
	subPrice: number,
	apiPrice: number,
	marketing: number,
	target: string,
	releasedAt: number,
	auto: boolean?, -- auto-price (default on; a manual price switches it off, CORE_SPEC 7.7)
}

export type ModelStatus = "training" | "trained" | "live" | "retired"

export type ModelData = {
	id: string,
	name: string,
	version: number,
	sizeId: string,
	focusId: string,
	status: ModelStatus,
	createdAt: number,
	trainedAt: number?,
	stats: Stats,
	overall: number,
	trainCost: number,
	iterations: number?,
	dataUsed: DataSummary,
	release: ReleaseConfig?,
	market: MarketState?,
	replacedBy: string?, -- retired by a new version of the same product line (CORE_SPEC 7.2)
}

export type TrainingEventState = {
	id: string,
	pending: boolean,
	expiresAt: number, -- workspace:GetServerTimeNow()-Zeit; beim Laden neu gesetzt
	outcome: string?, -- gewählte Option bzw. Ergebnis, für die Anzeige
}

export type TrainingState = {
	modelId: string,
	refinement: boolean?,
	baseStats: Stats?,
	resumeLive: boolean?,
	workTotal: number,
	workDone: number,
	cost: number,
	expected: number, -- erwarteter Overall (für die Loss-Kurve)
	qualityMod: number,
	eventRolled: boolean,
	event: TrainingEventState?,
	epoch: number, -- zuletzt gemeldete Epoche (Log-Zeilen)
	loss: { number },
	log: { string },
}

export type Company = {
	name: string,
	logo: string,
	color: string,
	spec: string,
	foundedAt: number,
	reputation: number,
}

export type PlayerStats = {
	totalRevenue: number,
	totalCost: number,
	modelsTrained: number,
	modelsReleased: number,
	peakUsers: number,
	bestOverall: number,
}

export type PlayerData = {
	empire: any,
	version: number,
	company: Company?,
	money: number,
	data: { [string]: DataStock },
	gpus: { [string]: number },
	models: { [string]: ModelData },
	modelOrder: { string },
	training: TrainingState?,
	lastScrapeAt: number,
	stats: PlayerStats,
	trainings: any?, -- DATA_VERSION 6: reserved for training slots 2..4 ("2".."4"; empty in v1)
	shop: any?, -- Robux shop records (ShopService; receipts/order are never replicated)
}

-- Laufzeitwerte (nicht gespeichert), die mit jedem Snapshot an den Client gehen
export type LiveModelResult = { users: number, revenue: number, cost: number }

export type LiveInfo = {
	admin: boolean?,
 workforce: any?,
	campus: any?,
	empire: any?,
	marketplace: any?,
	studio: any?,
	arena: any?,
	rankings: any?,
	shop: any?,
	ops: any?, -- CompanyOps.step summary: B2B, trips, posts, cost per minute of each category (lazy)
	compute: any?, -- {units, reserved, faults = {{slot, gpu, since}}} (EmpireService)
	capacity: number?, -- serving capacity in 500M-model users (MarketMath.tick)
	waitlist: number?, -- users waiting for capacity (lazy)
	load: number?, -- serving load in 500M-model users (lazy)
	demand: number?, -- target users before the capacity limit
	pricing: any?, -- models package: {[modelId] = {note, at}} when auto-price changed a price
	users: number,
	revenue: number, -- $ pro Sekunde
	cost: number, -- $ pro Sekunde
	perModel: { [string]: LiveModelResult },
	npcUsers: { [string]: number },
}

export type Snapshot = {
	seq: number?, -- Replikations-Zähler (SessionService); fehlt bei alten/Test-Snapshots
	saveEnabled: boolean,
	serverTime: number,
	data: PlayerData,
	live: LiveInfo,
}

-- Regelmäßiges State-Update: nur Änderungen seit Snapshot `base` (StatePatch-Format, Wurzel = {data, live}).
-- Der Client (StateController) setzt daraus wieder einen vollständigen Snapshot zusammen.
export type StateDelta = {
	seq: number,
	base: number,
	saveEnabled: boolean,
	serverTime: number,
	patch: { [string]: any },
}

export type ActionResult = { ok: boolean, err: string?, [string]: any }

return {}
