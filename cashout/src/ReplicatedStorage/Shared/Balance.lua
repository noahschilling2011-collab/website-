--[[
	Balance.lua  (CASHOUT v2)

	ALLE Zahlen des Spiels. Wenn hier eine Zahl fehlt, gehoert sie hierher --
	nirgendwo sonst im Code darf ein Gameplay-Wert hardcodiert stehen.

	Werte aus dem Dokument sind unveraendert uebernommen. Werte, die das
	Dokument nicht nennt, die der Code aber braucht, sind mit
	"NICHT SPEZIFIZIERT" markiert und stehen so in der Rueckmeldung.

	Reines Datenmodul: kein Require-Nebeneffekt ausser den abgeleiteten
	Nachschlagetabellen am Ende der Datei.
]]

local Balance = {}

-- ---------------------------------------------------------------- Spieler --

Balance.Player = {
	StartCash = 0,
	StartBanked = 0,
	StartHeat = 0,

	-- Wird nach einem Stun (Phase 2) wiederhergestellt. Beide Sprungwerte,
	-- weil je nach Humanoid.UseJumpPower nur einer von beiden wirkt.
	WalkSpeed = 16,
	JumpPower = 50,
	JumpHeight = 7.2,
}

-- --------------------------------------------------------------- Auftraege --

Balance.Orders = {
	-- NICHT SPEZIFIZIERT: Anzahl der Karten pro Terminal. Aus v1 uebernommen,
	-- v2 aendert nur, was nach der Auswahl passiert.
	OffersPerTerminal = 3,

	-- Dokument 1.1: "Karte am Terminal waehlen (1 s)" / "2 s Interaktion".
	AcceptSeconds = 1,
	DeliverSeconds = 2,

	-- NICHT SPEZIFIZIERT: Toleranz der serverseitigen Distanzchecks und
	-- Reichweite der ProximityPrompts.
	InteractRadius = 16,
	PromptDistance = 12,

	-- NICHT SPEZIFIZIERT: Wie oft der Server waehrend einer Interaktion
	-- prueft, ob der Spieler noch am Platz steht. Gilt auch fuer die Bank.
	CheckInterval = 0.25,

	-- NICHT SPEZIFIZIERT: Gueltigkeit der drei Karten an einem Terminal.
	-- Erneutes Ansprechen liefert innerhalb dieser Zeit dieselben Karten --
	-- verhindert Reroll-Spam, ohne dass Warten bestraft wird.
	OfferLifetimeSeconds = 30,

	Tiers = {
		{
			Id = "Small",
			Label = "Klein",
			MinPayout = 60,
			MaxPayout = 110,
			-- Klein gibt bewusst null Heat: das Werkzeug zum Weiterverdienen
			-- waehrend des Abkuehlens, nicht die schlechtere Version von Gross.
			Heat = 0,
			MinDistance = 40,
			MaxDistance = 70,
			MinHeatToOffer = 0,
			-- NICHT SPEZIFIZIERT: Stufenfarbe (Paket, Karte). Bewusst ausserhalb
			-- des gebundenen Farbcodes aus 4.2 -- kein Gruen, Gold, Rot, Weiss,
			-- Cyan.
			Color = Color3.fromRGB(150, 170, 190),
		},
		{
			Id = "Medium",
			Label = "Mittel",
			MinPayout = 150,
			MaxPayout = 250,
			Heat = 5,
			MinDistance = 90,
			MaxDistance = 140,
			MinHeatToOffer = 0,
			Color = Color3.fromRGB(90, 140, 220),
		},
		{
			Id = "Large",
			Label = "Gross",
			MinPayout = 320,
			MaxPayout = 560,
			Heat = 14,
			MinDistance = 160,
			MaxDistance = 230,
			MinHeatToOffer = 0,
			Color = Color3.fromRGB(170, 110, 230),
		},
		{
			Id = "Extreme",
			Label = "Extrem",
			MinPayout = 800,
			MaxPayout = 1400,
			Heat = 26,
			MinDistance = 260,
			MaxDistance = 340,
			MinHeatToOffer = 50,
			Color = Color3.fromRGB(240, 90, 200),
		},
	},

	--[[
		NICHT SPEZIFIZIERT: konkrete Gewichte.
		Dokument 4.4 sagt nur "Die Terminals mit den besseren Karten liegen
		weiter von der Bank weg". Ein Profil pro Terminal-Rang, Rang 1 = das
		banknaechste, Rang 5 = das entfernteste. Gewicht 0 = Stufe kommt an
		diesem Terminal nie vor.
	]]
	TerminalProfiles = {
		{ Small = 6, Medium = 3, Large = 1, Extreme = 0 },
		{ Small = 5, Medium = 4, Large = 2, Extreme = 0 },
		{ Small = 3, Medium = 4, Large = 3, Extreme = 1 },
		{ Small = 2, Medium = 3, Large = 4, Extreme = 2 },
		{ Small = 1, Medium = 2, Large = 5, Extreme = 3 },
	},
}

-- ------------------------------------------------------------------- Heat --

Balance.Heat = {
	Min = 0,
	Max = 100,

	-- Zerfall -1 pro 5 s und NUR ausserhalb eines laufenden Auftrags.
	-- Wer durchgehend arbeitet, kuehlt nicht ab.
	DecayAmount = 1,
	DecayInterval = 5,

	-- Razzia (Phase 2). p = (Heat/Max)^Exponent * Scale, Check alle 10 s.
	--   Heat 30 -> 0,9 % · Heat 50 -> 4,4 % · Heat 80 -> 17,9 % · Heat 100 -> 35 %
	RaidCheckInterval = 10,
	RaidChanceScale = 0.35,
	RaidChanceExponent = 3,

	-- Fluchtfenster (Phase 2).
	RaidRingRadius = 40,
	RaidRingSeconds = 5,
	RaidCashKeptFraction = 0.35,
	RaidHeatLossCaught = 40,
	RaidHeatLossEscaped = 15,
	RaidStunSeconds = 3,

	-- Schwellen der Weltreaktion aus 4.3 (Phase 4).
	AmbientCalmUntil = 30,
	AmbientTenseUntil = 60,
	AmbientHighUntil = 85,
}

--[[
	Risikopraemie aus 1.2: payout = basePayout * (1 + Heat/100).
	Steht als Funktion hier, damit Server und Client mit derselben Formel
	rechnen und die 100 nicht zweimal im Code auftaucht.
]]
function Balance.RiskPremium(heat: number): number
	local h = math.clamp(heat, Balance.Heat.Min, Balance.Heat.Max)
	return 1 + h / Balance.Heat.Max
end

--[[
	Razzia-Wahrscheinlichkeit pro Check (Phase 2). Schon hier, weil die HeatBar
	sie in Phase 1 bereits anzeigt -- die Formel darf es nur einmal geben.
]]
function Balance.RaidChance(heat: number): number
	local h = math.clamp(heat, Balance.Heat.Min, Balance.Heat.Max) / Balance.Heat.Max
	return (h ^ Balance.Heat.RaidChanceExponent) * Balance.Heat.RaidChanceScale
end

-- ------------------------------------------------------------------- Bank --

Balance.Bank = {
	DepositSeconds = 8,
	HeatRelief = 25,

	-- NICHT SPEZIFIZIERT: Radius des Einzahlbereichs und Prompt-Reichweite.
	Radius = 18,
	PromptDistance = 14,

	-- Phase 3: im Umkreis der Bank kann kein Auftrag angenommen werden.
	NoOrderRadius = 25,
}

-- ------------------------------------------------------------------ Runde --

Balance.Round = {
	DurationSeconds = 300,
	IntermissionSeconds = 15,
	MinPlayers = 1,

	-- Letzte 60 s: alle Payouts x2.
	FinalRushSeconds = 60,
	FinalRushMultiplier = 2,

	-- NICHT SPEZIFIZIERT: Takt, in dem der Rundenzustand zum Client
	-- nachsynchronisiert wird. Der Countdown laeuft clientseitig weiter.
	StateResyncInterval = 5,
}

-- --------------------------------------------------------- Phase 3 (spaeter) --

Balance.LateJoin = {
	GraceSeconds = 60,
	MedianFactor = 0.5,
	LockoutSeconds = 45,
}

Balance.Intercept = {
	SplitFraction = 0.5,
	HeatGain = 25,
	CooldownSeconds = 45,
}

-- --------------------------------------------------------------- Netzwerk --

Balance.Net = {
	-- Dokument 7: "ein Aufruf pro Spieler und Aktion pro 0,3 s".
	ActionCooldown = 0.3,

	-- NICHT SPEZIFIZIERT.
	StateReplicateInterval = 0.2,
	NotifyDuration = 3.5,
	ThrottleWarnCooldown = 5,
}

-- -------------------------------------------------------------------- Map --
-- NICHT SPEZIFIZIERT bis auf 4.4 (Bank zentral und hoch, fuenf Terminals am
-- Rand, bessere Terminals weiter weg) und die 18 s Bank-Rundweg.
-- Alles Uebrige ist daraus gerechnet:
--   18 s Rundweg bei WalkSpeed 16 -> 144 Studs einfach zum besten Terminal.
--   Bester Uebergabepunkt liegt bis zu 340 Studs vom Terminal -> Boden muss
--   mindestens 144 + 340 = 484 Studs Halbkante haben.

Balance.Map = {
	GroundSize = Vector3.new(1000, 4, 1000),
	GroundY = 0,

	-- Uebergabepunkte werden innerhalb dieser Halbkante um den Mittelpunkt
	-- gesetzt. Kleiner als der Boden, damit niemand an der Kante steht.
	PlayableHalfExtent = 480,

	BankPosition = Vector3.new(0, 0, 0),
	BankPlinthSize = Vector3.new(40, 2, 40),
	BankTowerSize = Vector3.new(16, 54, 16),
	BankCounterSize = Vector3.new(12, 4, 2),
	BankCounterOffset = Vector3.new(0, 4, 12),

	-- Ein Radius pro Terminal-Rang, Rang 1 zuerst. Rang 5 = 144 Studs = die
	-- 18 s Rundweg aus dem Dokument.
	TerminalRadii = { 80, 96, 112, 128, 144 },
	TerminalStartAngleDegrees = 18,
	TerminalSize = Vector3.new(5, 8, 5),

	DeliveryPadSize = Vector3.new(14, 1, 14),
	DeliveryPillarSize = Vector3.new(2, 16, 2),
	-- Wie viele Richtungen der Server durchprobiert, bis ein Uebergabepunkt
	-- innerhalb der Spielflaeche liegt.
	DeliveryPlacementTries = 24,

	SpawnPosition = Vector3.new(0, 0, 34),
	SpawnSize = Vector3.new(16, 1, 16),

	-- Sichtbares Paket auf dem Ruecken, solange ein Auftrag laeuft (1.1).
	PackageSize = Vector3.new(2.6, 2.6, 1.2),
	PackageOffset = Vector3.new(0, 0.2, 1.1),
}

-- ------------------------------------------------------------ Abgeleitetes --

Balance.Orders.TierById = {}
for _, tier in ipairs(Balance.Orders.Tiers) do
	Balance.Orders.TierById[tier.Id] = tier
end

return Balance
