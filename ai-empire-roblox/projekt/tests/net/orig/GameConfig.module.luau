--!strict
-- Technische Konstanten: Speichern, Takt, Limits.
-- Balancing (Preise, Formeln, Markt) liegt in den anderen Config-Modulen.

local GameConfig = {
	DATA_VERSION = 5,
	DATASTORE_NAME = "AIEmpire_Player_v1",
	KEY_PREFIX = "u_",

	AUTOSAVE_SECONDS = 90,
	SESSION_LOCK_TIMEOUT = 180, -- ein fremder Lock, der älter ist, gilt als tot (Server abgestürzt)
	LOAD_ATTEMPTS = 6,
	LOAD_RETRY_SECONDS = 4,
	SAVE_ATTEMPTS = 3,

	TICK_SECONDS = 1, -- Simulationstakt für Training und Markt
	REPLICATE_SECONDS = 0.25, -- frühestens so oft geht ein State-Update an einen Client

	START_MONEY = 25_000,
	COMPANY_NAME_MIN = 3,
	COMPANY_NAME_MAX = 24,
	MODEL_NAME_MIN = 2,
	MODEL_NAME_MAX = 20,

	-- 1 Spielmonat = 60 echte Minuten. Abo- und API-Preise gelten pro Spielmonat.
	GAME_MONTH_SECONDS = 3600,

	-- UserIds, die außerhalb von Studio Debug-Befehle nutzen dürfen. Für Live-Server leer lassen.
	DEV_USER_IDS = {} :: { number },
}

return table.freeze(GameConfig)
