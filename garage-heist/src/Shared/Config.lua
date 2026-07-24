--[[
	Config
	Jede Zahl, an der man drehen kann, steht hier. Sonst nirgends.
]]

local Config = {}

-- Wirtschaft ---------------------------------------------------------------
Config.START_CASH = 250 -- reicht fuer das billigste Teil (Reifen T1 = 100) plus Puffer
Config.OFFLINE_CAP_SECONDS = 8 * 60 * 60 -- Deckel fuer Offline-Einnahmen
Config.OFFLINE_RATE = 1.0 -- Offline zaehlt voll (Faktor bleibt trotzdem einstellbar)
Config.PILE_CAP_SECONDS = 2 * 60 * 60 -- so lange laeuft der Kassen-Stapel online voll, dann stoppt er
Config.ACCRUAL_TICK = 1 -- Sekunden zwischen Einkommens-Ticks
Config.CASH_PUSH_INTERVAL = 1 -- Sekunden zwischen Cash-Updates an den Client
Config.SELL_REFUND = 0.5 -- Anteil des Teilewerts beim Verkauf loser Teile

-- Speichern ----------------------------------------------------------------
Config.AUTOSAVE_INTERVAL = 60
Config.DATASTORE_NAME = "GarageHeist_Profiles_v1"
Config.SESSION_LOCK_TIMEOUT = 90 -- danach gilt ein Lock als verwaist
Config.LOAD_ATTEMPTS = 6
Config.RETRY_BASE_WAIT = 2

-- Klau-Fenster -------------------------------------------------------------
Config.HEIST_INTERVAL = 8 * 60 -- alle 8 Minuten
Config.HEIST_WINDOW = 60 -- 60 Sekunden offen
Config.HEIST_FIRST_DELAY = 150 -- erstes Fenster erst nach 2,5 Minuten Serverlaufzeit
Config.HEIST_WARN_AT = { 60, 15 } -- Vorwarnungen in Sekunden vor Fensteroeffnung
Config.DISMOUNT_TIME = 4 -- Sekunden Abmontieren
Config.DISMOUNT_MAX_DISTANCE = 16 -- bricht ab, wenn der Dieb weiter weg ist
Config.TACKLE_RANGE = 12
Config.TACKLE_COOLDOWN = 4
Config.CARRY_WALKSPEED = 12
Config.NORMAL_WALKSPEED = 16
Config.DROPPED_PART_PICKUP_DISTANCE = 8
Config.GARAGE_LOCK_WINDOW = 20 -- Gamepass: eigenes Tor faellt nach 20s wieder zu

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
Config.RADAR_TOP_COUNT = 5

-- Daily Reward -------------------------------------------------------------
Config.DAILY_REWARDS = { 250, 500, 900, 1500, 2600, 4200, 8000 }

-- Leaderboard --------------------------------------------------------------
Config.LEADERBOARD_REFRESH = 5

return Config
