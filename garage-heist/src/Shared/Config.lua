--[[
	Config
	Jede Zahl, an der man drehen kann, steht hier. Sonst nirgends.
]]

local Config = {}

-- Wirtschaft ---------------------------------------------------------------
Config.START_CASH = 250 -- reicht fuer das billigste Teil (Reifen T1 = 100) plus Puffer
Config.OFFLINE_CAP_SECONDS = 8 * 60 * 60 -- Deckel fuer Offline-Einnahmen
-- Offline zaehlt nur anteilig: 8h weg gegen 4h Kassendeckel waeren sonst ein
-- Anreiz, das Spiel zu schliessen.
Config.OFFLINE_RATE = 0.6
Config.PILE_CAP_SECONDS = 4 * 60 * 60 -- so lange laeuft der Kassen-Stapel online voll, dann stoppt er
Config.ACCRUAL_TICK = 1 -- Sekunden zwischen Einkommens-Ticks
Config.CASH_PUSH_INTERVAL = 1 -- Sekunden zwischen Cash-Updates an den Client

-- Drosselung der Client-Anfragen (Sekunden). Gilt fuer jedes Remote.
Config.COLLECT_COOLDOWN = 0.3
Config.CLAIM_COOLDOWN = 1
Config.DROP_COOLDOWN = 0.5
Config.PROMPT_COOLDOWN = 1.5
Config.SELL_REFUND = 0.5 -- Anteil des Teilewerts beim Verkauf loser Teile
-- Beklautwerden soll wehtun, aber nicht bestrafen: das Opfer bekommt einen
-- Teil des Werts sofort als Cash - erst wenn das Teil wirklich abgeliefert ist.
Config.INSURANCE_RATE = 0.25

-- Zwischenstufen ("Feinabstimmung") ---------------------------------------
-- Zwischen zwei Tiers liegen zwei kleine Kaeufe. Sie sind KEIN Extra, sondern
-- eine Ratenzahlung: der anschliessende Tier-Sprung wird um das bereits
-- gezahlte guenstiger. Damit wird der Kauftakt dichter, ohne dass die Kurve
-- laenger wird.
Config.SUBTIER_COUNT = 2
Config.SUBTIER_RATE_BONUS = 0.12 -- +12 % Rate je Zwischenstufe
Config.SUBTIER_COST_SHARE = 0.35 -- Anteil des naechsten Tier-Preises je Stufe
Config.SUBTIER_TIME_SHARE = 0.5 -- Reparaturzeit im Verhaeltnis zur Tier-Zeit
Config.SUBTIER_MIN_TIME = 4
Config.SUBTIER_TOP_COST_MULT = 2.5 -- auf der hoechsten Stufe gibt es keinen Sprung mehr

-- Rebirth ------------------------------------------------------------------
Config.REBIRTH_MULT = 0.25 -- +25 % Rate je Rebirth, dauerhaft
Config.REBIRTH_EXTRA_SLOT_AT = 1 -- ab diesem Rebirth ein zusaetzlicher Stellplatz
Config.REBIRTH_PAINT_AT = 3 -- ab hier exklusiver Lack

-- Speichern ----------------------------------------------------------------
Config.AUTOSAVE_INTERVAL = 60
Config.DATASTORE_NAME = "GarageHeist_Profiles_v1"
Config.SESSION_LOCK_TIMEOUT = 90 -- danach gilt ein Lock als verwaist
Config.LOAD_ATTEMPTS = 6
Config.RETRY_BASE_WAIT = 2
-- Harte Obergrenze ueber ALLE Versuche zusammen. Danach wird gekickt statt den
-- Spieler minutenlang vor einer leeren Oberflaeche warten zu lassen.
Config.LOAD_TOTAL_BUDGET = 45

-- Klau-Fenster -------------------------------------------------------------
-- Takt: 3,5 Minuten Zyklus mit 75s offenem Fenster = rund ein Drittel Spielzeit
-- im Heist statt vorher einem Achtel. Das erste Fenster faellt in die erste
-- Session, nicht daneben.
Config.HEIST_INTERVAL = 210
Config.HEIST_WINDOW = 75
Config.HEIST_FIRST_DELAY = 45
Config.HEIST_WARN_AT = { 45, 15, 5 } -- Vorwarnungen in Sekunden vor Fensteroeffnung
Config.HEIST_PULSE_AT = 15 -- ab hier pulsiert die HUD-Anzeige
Config.DISMOUNT_TIME = 4 -- Sekunden Abmontieren
Config.DISMOUNT_MAX_DISTANCE = 16 -- bricht ab, wenn der Dieb weiter weg ist
Config.TACKLE_RANGE = 12
Config.TACKLE_COOLDOWN = 4
Config.TACKLE_SHAKE = 1.6 -- Staerke des Kamera-Wacklers beim Treffer
Config.CARRY_WALKSPEED = 12
Config.NORMAL_WALKSPEED = 16
Config.DROPPED_PART_PICKUP_DISTANCE = 8
Config.GARAGE_LOCK_WINDOW = 20 -- Gamepass: eigenes Tor faellt nach 20s wieder zu

-- Leerstand-Garagen --------------------------------------------------------
-- Freie Plots werden waehrend des Fensters zu Zielen, damit der Heist auch bei
-- einem einzigen Spieler im Server stattfindet.
Config.DERELICT_VALUE_MULT = 0.6 -- Leerstand-Teile bringen weniger als geklaute Spielerteile
Config.DERELICT_MIN_PARTS = 1
Config.DERELICT_MAX_PARTS = 4
Config.DERELICT_MAX_TIER = 3 -- nie T4, damit Neulinge nicht sofort das Endgame abgreifen
-- Ab welchem Median-Garagenwert der anwesenden Spieler welche Stufe auftaucht.
Config.DERELICT_TIER_STEPS = { 0, 8000, 40000 }

-- Plots --------------------------------------------------------------------
Config.PLOT_COUNT = 12
Config.PLOT_WIDTH = 46
Config.PLOT_DEPTH = 54
Config.PLOT_HEIGHT = 18
Config.PLOTS_PER_ROW = 6
Config.PLOT_GAP = 10
Config.ROW_GAP = 110
Config.BASE_HEIGHT = 0

-- Garagen-Stufen -----------------------------------------------------------
Config.GARAGE_LEVELS = {
	{ cost = 0, rateMult = 1.00, carSlots = 1, label = "Blechbude" },
	{ cost = 2500, rateMult = 1.15, carSlots = 2, label = "Werkstatt" },
	{ cost = 14000, rateMult = 1.35, carSlots = 2, label = "Tuning-Shop" },
	{ cost = 65000, rateMult = 1.60, carSlots = 3, label = "Rennstall" },
	{ cost = 260000, rateMult = 2.00, carSlots = 4, label = "Werk" },
}

-- Monetarisierung ----------------------------------------------------------
Config.VIP_RATE_MULT = 2.0
-- Bewusst so gewaehlt, dass auch das groesste Paket den Loop nicht ersetzt:
-- das teuerste Garagen-Upgrade kostet 260k, der Supersportler 75k.
Config.CASH_PACKS = {
	CashSmall = 5000,
	CashMedium = 30000,
	CashLarge = 150000,
}
Config.RADAR_TOP_COUNT = 5

-- Daily Reward -------------------------------------------------------------
Config.DAILY_REWARDS = { 250, 500, 900, 1500, 2600, 4200, 8000 }

-- Badges -------------------------------------------------------------------
-- Platzhalter. Im Creator Dashboard anlegen und hier eintragen, siehe
-- docs/SETUP.md. Solange 0 drinsteht, wird kein Badge vergeben.
Config.BADGE_IDS = {
	FirstSteal = 0, -- erstes abgeliefertes Diebesgut
	Rich = 0, -- 100.000 Cash auf dem Konto
	FirstRebirth = 0, -- erster Rebirth
}
Config.BADGE_RICH_AT = 100000

-- Leaderboard --------------------------------------------------------------
Config.LEADERBOARD_REFRESH = 5

return Config
