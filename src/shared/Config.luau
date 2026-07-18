--!strict
-- Config.luau
-- Zentrale Stelle fuer alle globalen Tuning-Zahlen von MiniCity.
-- Per-Item-Katalogwerte (Preis, Einkommen, Einwohner, Footprint) leben datengetrieben
-- in Items.luau; hier stehen die globalen Zahlen und die Unlock-Schwellen.

local Config = {}

-- Plot / Grid
Config.PlotSize = 128 -- Studs Kantenlaenge eines Plots
Config.PlotCount = 6 -- Grundstuecke pro Server
Config.CellSize = 4 -- Studs pro Rasterzelle
Config.GridCells = Config.PlotSize // Config.CellSize -- 32x32 Zellen pro Plot
Config.PlotSurfaceY = 0.6 -- Welthoehe der Plot-Oberflaeche (Gebaeude sitzen hier auf)
Config.PlotColumns = 3 -- Anordnung der Plots: 3 Spalten x 2 Reihen
Config.PlotGap = 32 -- Luecke zwischen zwei Plots in Studs

-- Oekonomie
Config.StartingCash = 500
Config.IncomeTickInterval = 10 -- Sekunden zwischen Einkommens-Ticks
Config.RefundRatio = 0.5 -- Rueckerstattung beim Abriss

-- Anti-Missbrauch
Config.RateLimit = 5 -- max. Platz-/Abriss-Aktionen pro Sekunde und Spieler

-- Unlock-Schwellen (Einwohnerzahl). Items.luau referenziert diese Werte.
Config.Unlocks = {
	Strasse = 0,
	Wohnhaus = 0,
	Geschaeft = 10,
	Hochhaus = 25,
	Autobahn = 50,
	Flughafen = 100,
}

-- Persistenz
Config.DataVersion = 1
Config.SaveInterval = 120 -- Sekunden zwischen Autosaves
Config.DataStoreName = "MiniCity"
Config.DataKeyPrefix = "city_v1_"

return Config
