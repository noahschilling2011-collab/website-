--[[
	Balance.lua

	ALLE Zahlen des Spiels. Wenn hier eine Zahl fehlt, gehoert sie hierher --
	nirgendwo sonst im Code darf ein Gameplay-Wert hardcodiert stehen.

	Reines Datenmodul: kein Require-Nebeneffekt ausser dem Aufbau der
	Nachschlagetabelle TierById am Ende der Datei.
]]

local Balance = {}

-- ---------------------------------------------------------------- Spieler --

Balance.Player = {
	StartCash = 0,
	StartBanked = 0,
	StartHeat = 0,

	-- Wird nach einem Stun wiederhergestellt. Beide Sprungwerte, weil je nach
	-- Humanoid.UseJumpPower nur einer von beiden wirkt.
	WalkSpeed = 16,
	JumpPower = 50,
	JumpHeight = 7.2,
}

-- ------------------------------------------------------------------- Heat --

Balance.Heat = {
	Min = 0,
	Max = 100,

	-- Zerfall: -1 alle 3 s (= -20/min), laeuft immer, auch waehrend eines Deals.
	DecayAmount = 1,
	DecayInterval = 3,

	-- Razzia-Check: p = (Heat/Max)^Exponent * Scale
	--   Heat 20 -> 1,00 % pro Check
	--   Heat 50 -> 6,25 % pro Check
	--   Heat 80 -> 16,00 % pro Check
	RaidCheckInterval = 15,
	RaidChanceScale = 0.25,
	RaidChanceExponent = 2,

	-- Treffer: Cash * 0.4 bleibt uebrig (60 % weg).
	RaidCashKeptFraction = 0.4,
	RaidHeatLoss = 35,
	RaidStunSeconds = 3,

	-- Nur Anzeige: ab wann die Heat-Leiste warnt bzw. rot pulst.
	WarnAt = 55,
	DangerAt = 75,
}

-- ------------------------------------------------------------------ Deals --

Balance.Deals = {
	OffersPerTerminal = 3,

	-- Ein Terminal behaelt seine drei Karten fuer diese Zeit. Erneutes
	-- Ansprechen liefert dieselben Karten zurueck -- das verhindert
	-- Reroll-Spam. Wer andere Karten will, laeuft zu einem anderen Terminal.
	OfferLifetimeSeconds = 30,

	Tiers = {
		{
			Id = "Small",
			Label = "Klein",
			MinPayout = 40,
			MaxPayout = 80,
			Heat = 1,
			Duration = 6,
			MinHeatToOffer = 0,
		},
		{
			Id = "Medium",
			Label = "Mittel",
			MinPayout = 120,
			MaxPayout = 220,
			Heat = 6,
			Duration = 10,
			MinHeatToOffer = 0,
		},
		{
			Id = "Large",
			Label = "Gross",
			MinPayout = 300,
			MaxPayout = 600,
			Heat = 16,
			Duration = 16,
			MinHeatToOffer = 0,
		},
		{
			Id = "Extreme",
			Label = "Extrem",
			MinPayout = 900,
			MaxPayout = 1600,
			Heat = 30,
			Duration = 22,
			MinHeatToOffer = 50,
		},
	},

	-- Gewichte fuer die Ziehung der drei Karten. Hoeher = haeufiger im Angebot.
	TierWeights = {
		Small = 4,
		Medium = 4,
		Large = 2,
		Extreme = 1,
	},
}

-- ----------------------------------------------------------- Taetigkeiten --

Balance.Activity = {
	-- Takt, in dem der Server waehrend Deal und Einzahlung prueft, ob der
	-- Spieler noch am Platz steht.
	CheckInterval = 0.25,
}

-- ------------------------------------------------------------------- Bank --

Balance.Bank = {
	DepositSeconds = 8,
	HeatRelief = 20,
	-- Serverseitiger Distanzcheck (mit Toleranz ueber der Prompt-Reichweite).
	Radius = 16,
	PromptDistance = 12,
}

-- -------------------------------------------------------------------- Map --

Balance.Map = {
	GroundSize = Vector3.new(340, 4, 240),
	GroundY = 0,

	-- Terminals stehen links, die Bank rechts. Der Abstand ist der Preis fuers
	-- Einzahlen: ~150 Studs = ~9,4 s Laufzeit pro Richtung bei WalkSpeed 16,
	-- also ~19 s hin und zurueck plus 8 s Einzahlen.
	TerminalCount = 5,
	TerminalAnchorX = -75,
	TerminalSpacingZ = 30,
	TerminalSize = Vector3.new(4, 7, 4),
	TerminalRadius = 16, -- serverseitiger Distanzcheck (Toleranz eingerechnet)
	TerminalPromptDistance = 12,

	BankPosition = Vector3.new(75, 0, 0),
	BankSize = Vector3.new(24, 12, 16),

	SpawnPosition = Vector3.new(-20, 0, 0),
}

-- ------------------------------------------------------------------ Runde --
-- Phase 2. Steht schon hier, damit spaeter nichts ausserhalb von Balance
-- getunt werden muss.

Balance.Round = {
	DurationSeconds = 600,
	IntermissionSeconds = 20,
	MinPlayers = 1,
}

Balance.Meta = {
	-- Auszahlung am Rundenende: floor(Banked / CashPerCoin) + WinnerBonus fuer Platz 1.
	CashPerCoin = 100,
	WinnerBonus = 25,
}

-- ------------------------------------------------------------- Netzwerk/UI --

Balance.Net = {
	-- Pro Spieler und Sekunde. Alles darueber wird ignoriert.
	MaxRequestsPerSecond = 4,
	-- Wie oft der Spieler hoechstens eine Rate-Limit-Warnung bekommt.
	RateWarnCooldown = 5,
	-- Takt, in dem sich geaenderte Spielerwerte zum Client replizieren.
	StateReplicateInterval = 0.2,
	-- Wie lange eine Toast-Meldung im HUD steht.
	NotifyDuration = 3.5,
}

-- ------------------------------------------------------------ Abgeleitetes --

-- Tier-Nachschlag nach Id, damit der Katalog nur noch den Namen nennen muss.
Balance.Deals.TierById = {}
for _, tier in ipairs(Balance.Deals.Tiers) do
	Balance.Deals.TierById[tier.Id] = tier
end

--[[
	Razzia-Wahrscheinlichkeit pro Check. Wird vom Server fuer den Wurf und vom
	Client nur zur Anzeige benutzt -- die Formel steht damit genau einmal.
]]
function Balance.RaidChance(heat: number): number
	local h = math.clamp(heat, Balance.Heat.Min, Balance.Heat.Max) / Balance.Heat.Max
	return (h ^ Balance.Heat.RaidChanceExponent) * Balance.Heat.RaidChanceScale
end

return Balance
