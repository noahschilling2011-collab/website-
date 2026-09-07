--[[
	SoundCatalog
	Alle Klaenge des Spiels an einer Stelle.

	=========================================================================
	ALLE IDs SIND LEER. Das ist Absicht: eine erfundene rbxassetid:// ist
	schlimmer als Stille, weil sie im Zweifel irgendetwas Fremdes abspielt.
	Trag die IDs aus der Roblox Creator Store Bibliothek ein - welche Zeile
	welchen Klang braucht, steht in docs/SETUP.md.
	Solange id == "" ist, passiert schlicht nichts. Kein Fehler, kein Knacken.
	=========================================================================
]]

local SoundCatalog = {}

SoundCatalog.Sounds = {
	-- Raeumlich (Server erzeugt sie an einer Weltposition)
	doorOpen = { id = "", volume = 0.6, rollOff = 90 }, -- TODO: SoundId - Rolltor faehrt hoch
	dismount = { id = "", volume = 0.5, rollOff = 45 }, -- TODO: SoundId - Ratsche/Schrauber
	deposit = { id = "", volume = 0.7, rollOff = 60 }, -- TODO: SoundId - Registrierkasse
	tackle = { id = "", volume = 0.8, rollOff = 60 }, -- TODO: SoundId - dumpfer Rempler

	-- Lokal (nur beim jeweiligen Spieler)
	countdown = { id = "", volume = 0.5 }, -- TODO: SoundId - Tick in den letzten 5 Sekunden
	windowOpen = { id = "", volume = 0.8 }, -- TODO: SoundId - Alarm/Hupe beim Oeffnen
	purchase = { id = "", volume = 0.6 }, -- TODO: SoundId - Kauf bestaetigt
	repairDone = { id = "", volume = 0.5 }, -- TODO: SoundId - Teil sitzt
}

function SoundCatalog.Get(name: string)
	local def = SoundCatalog.Sounds[name]
	if not def or def.id == "" then
		return nil
	end
	return def
end

-- Fuer docs/SETUP.md und den Startbericht: was fehlt noch?
function SoundCatalog.Missing(): { string }
	local missing = {}
	for name, def in SoundCatalog.Sounds do
		if def.id == "" then
			table.insert(missing, name)
		end
	end
	table.sort(missing)
	return missing
end

return SoundCatalog
