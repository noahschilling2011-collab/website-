--[[
	DealCatalog.lua

	Reine Daten. Jede Karte nennt nur ihre Stufe -- Payout, Heat und Dauer
	stehen ausschliesslich in Balance.Deals.Tiers.

	Neue Karte hinzufuegen: Zeile anhaengen, Tier auf eine vorhandene Tier-Id
	setzen. Sonst nichts.
]]

local DealCatalog = {}

DealCatalog.Cards = {
	-- Klein ------------------------------------------------------------------
	{ Id = "courier", Tier = "Small", Name = "Kurierfahrt", Blurb = "Ein Umschlag, zwei Strassen weiter." },
	{ Id = "resale", Tier = "Small", Name = "Ticket-Weiterverkauf", Blurb = "Ausverkauft heisst nicht ausverkauft." },
	{ Id = "spares", Tier = "Small", Name = "Ersatzteile umleiten", Blurb = "Die Kiste stand ohnehin falsch." },
	{ Id = "nightshift", Tier = "Small", Name = "Nachtschicht-Abrechnung", Blurb = "Niemand zaehlt um vier Uhr nach." },

	-- Mittel -----------------------------------------------------------------
	{ Id = "relabel", Tier = "Medium", Name = "Container umetikettieren", Blurb = "Neues Schild, neues Ziel." },
	{ Id = "customs", Tier = "Medium", Name = "Zollformular korrigieren", Blurb = "Ein Feld, eine Null, ein Nachmittag." },
	{ Id = "pallet", Tier = "Medium", Name = "Palette ohne Papiere", Blurb = "Steht seit Dienstag da. Gehoert jetzt dir." },
	{ Id = "stock", Tier = "Medium", Name = "Lagerbestand angleichen", Blurb = "Die Inventur hatte schon immer Rundungsfehler." },

	-- Gross ------------------------------------------------------------------
	{ Id = "waybill", Tier = "Large", Name = "Frachtbrief neu ausstellen", Blurb = "Der Waggon faehrt trotzdem." },
	{ Id = "shift", Tier = "Large", Name = "Hafenschicht kaufen", Blurb = "Acht Stunden, in denen keiner hinsieht." },
	{ Id = "trucks", Tier = "Large", Name = "Zwei LKW ueber Nacht", Blurb = "Zurueck vor der Fruehschicht. Wahrscheinlich." },
	{ Id = "crane", Tier = "Large", Name = "Kranfuehrer ueberzeugen", Blurb = "Er hebt, was du sagst. Einmal." },

	-- Extrem (erst ab Heat >= 50 im Angebot) ---------------------------------
	{ Id = "terminalwide", Tier = "Extreme", Name = "Ganzer Hafenabschnitt", Blurb = "Kein Rueckweg ab hier." },
	{ Id = "quarter", Tier = "Extreme", Name = "Quartalsbilanz", Blurb = "Drei Monate in einer Nacht geradeziehen." },
	{ Id = "chain", Tier = "Extreme", Name = "Die ganze Lieferkette", Blurb = "Vom Kai bis zum Regal, alles deins." },
	{ Id = "blackfriday", Tier = "Extreme", Name = "Schwarzer Freitag", Blurb = "Einmal im Jahr sieht niemand hin. Heute." },
}

-- Nachschlag nach Id (rein abgeleitet, keine zusaetzlichen Daten).
DealCatalog.ById = {}
for _, card in ipairs(DealCatalog.Cards) do
	DealCatalog.ById[card.Id] = card
end

return DealCatalog
