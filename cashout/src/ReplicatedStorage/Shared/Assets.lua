--[[
	Assets.lua

	Sammelstelle fuer Asset-Ids. Alle Felder sind absichtlich leer -- hier
	steht keine erfundene rbxassetid. Was an welche Stelle gehoert, steht in
	ASSETS_TODO.md.

	Der Code prueft vor jeder Verwendung auf "" und ueberspringt das Asset
	dann. Eine Id eintragen genuegt also, es ist keine Code-Aenderung noetig.
]]

local Assets = {}

Assets.Sounds = {
	-- Client, RoundHud: Deal erfolgreich abgeschlossen.
	DealComplete = "",
	-- Client, RoundHud: Einzahlung durch, Cash ist sicher.
	DepositComplete = "",
	-- Client, RoundHud: Razzia-Treffer, spielt zum roten Blitz.
	RaidSiren = "",
	-- Client, RoundHud: Warnung (zu weit weg, beschaeftigt, Rate-Limit).
	Warning = "",
}

Assets.Images = {
	-- Server, MapBuilder: Decal auf der Leuchtflaeche eines Terminals.
	TerminalScreen = "",
	-- Server, MapBuilder: Decal auf dem Bank-Tresen.
	BankSign = "",
}

return Assets
