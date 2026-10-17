--!strict
-- Technische Konstanten: Speichern, Takt, Limits.
-- Balancing (Preise, Formeln, Markt) liegt in den anderen Config-Modulen.

local GameConfig = {
	DATA_VERSION = 6, -- 6: garage stage inserted as office 1 (Template MIGRATIONS[5]: office index +1)
	DATASTORE_NAME = "AIEmpire_Player_v1",
	KEY_PREFIX = "u_",

	AUTOSAVE_SECONDS = 90,
	SESSION_LOCK_TIMEOUT = 180, -- ein fremder Lock, der älter ist, gilt als tot (Server abgestürzt)
	LOAD_ATTEMPTS = 6,
	LOAD_RETRY_SECONDS = 4,
	SAVE_ATTEMPTS = 3,

	TICK_SECONDS = 1, -- Simulationstakt für Training und Markt
	-- State-Updates sind Deltas (nur geänderte Werte). Die Simulation tickt 1x/s, Geld und Training
	-- rechnet der Client dazwischen hoch -> 2/s reicht; nach einer Spieler-Aktion schneller.
	REPLICATE_SECONDS = 0.5, -- frühestens so oft geht ein State-Update an einen Client
	REPLICATE_URGENT_SECONDS = 0.1, -- nach einem Remote-Aufruf des Spielers (Antwort fühlt sich sofort an)
	REPLICATE_LAZY_SECONDS = 5, -- Nebenzähler (Besucher, Umsatzsummen, Nutzer fremder Angebote): so oft abgeglichen

	START_MONEY = 10_000, -- CORE_SPEC 2.4: garage start (new saves only)
	COMPANY_NAME_MIN = 3,
	COMPANY_NAME_MAX = 24,
	MODEL_NAME_MIN = 2,
	MODEL_NAME_MAX = 20,

	-- 1 Spielmonat = 60 echte Minuten. Abo- und API-Preise gelten pro Spielmonat.
	GAME_MONTH_SECONDS = 3600,
	-- Model slots: at most this many non-retired models per company (AIModelService, CORE_SPEC 7.2)
	MODEL_LIMIT = 80,

	-- UserIds, die außerhalb von Studio Debug-Befehle nutzen dürfen. Für Live-Server leer lassen.
	DEV_USER_IDS = {} :: { number },
}

return table.freeze(GameConfig)
