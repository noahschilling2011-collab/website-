--!strict
-- Server-interne Typen. Eigenes Modul, damit Lib und Services sich nicht gegenseitig requiren müssen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)

export type Session = {
	player: Player,
	userId: number,
	data: Types.PlayerData,
	live: Types.LiveInfo, -- Laufzeitwerte, nicht gespeichert
	dirty: boolean,
	lastSent: number,
	nextSaveAt: number,
	saving: boolean,
	closed: boolean, -- keine Änderungen/Saves mehr
	released: boolean, -- Schließen läuft bereits
	rng: Random,
	seq: number?, -- Nummer des zuletzt gesendeten State-Snapshots/-Deltas (SessionService)
	shadow: any?, -- private Kopie des zuletzt gesendeten Stands {data, live}; Basis für Deltas
	urgent: boolean?, -- Remote-Aufruf seit dem letzten Senden: schneller senden (REPLICATE_URGENT_SECONDS)
	sweptAt: number?, -- letzter Abgleich inkl. der "lazy" Zähler (REPLICATE_LAZY_SECONDS)
}

export type Payload = { [string]: any }
export type Result = { [string]: any }
export type Handler = (session: Session, payload: Payload) -> Result

return {}
