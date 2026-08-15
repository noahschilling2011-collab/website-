--[[
	Assets.lua

	Bild-/Decal-Ids. Alle Felder sind absichtlich leer -- hier ist keine
	rbxassetid erfunden worden. Was an welche Stelle gehoert, steht in
	ASSETS_TODO.md.

	Sounds stehen nicht hier, sondern in SoundCatalog.lua (Dokument 5).

	Der Code prueft vor jeder Verwendung auf "" und ueberspringt das Asset
	dann. Eine Id eintragen genuegt, es ist keine Code-Aenderung noetig.
]]

local Assets = {}

Assets.Images = {
	-- Server, MapBuilder: Decal auf der Leuchtflaeche eines Terminals.
	TerminalScreen = "",
	-- Server, MapBuilder: Decal am Bank-Tresen.
	BankSign = "",
}

return Assets
