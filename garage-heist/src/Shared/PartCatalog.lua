--[[
	PartCatalog
	Vier Slots, je vier Stufen. Kosten, Reparaturzeit, Cash/Sekunde und wie das
	Teil am Auto aussieht. Der Server rechnet ausschliesslich mit diesen Werten.
]]

local PartCatalog = {}

PartCatalog.SlotOrder = { "engine", "tires", "paint", "turbo" }

PartCatalog.Slots = {
	engine = {
		displayName = "Motor",
		mount = "hood", -- sitzt sichtbar auf der Motorhaube
		size = Vector3.new(2.8, 1.1, 2.0),
		tiers = {
			{ name = "Rostiger Reihenvierer", cost = 150, time = 6, rate = 0.6, color = Color3.fromRGB(105, 95, 88) },
			{ name = "Ueberholter V6", cost = 900, time = 20, rate = 2.2, color = Color3.fromRGB(70, 120, 160) },
			{ name = "Big Block V8", cost = 5200, time = 60, rate = 7.5, color = Color3.fromRGB(190, 120, 40) },
			{ name = "Prototyp-Hybrid", cost = 28000, time = 180, rate = 24, color = Color3.fromRGB(120, 230, 190) },
		},
	},
	tires = {
		displayName = "Reifen",
		mount = "wheels", -- vier Raeder statt eines Teils
		size = Vector3.new(0.9, 2.2, 2.2),
		tiers = {
			{ name = "Notrad-Satz", cost = 100, time = 6, rate = 0.4, color = Color3.fromRGB(45, 45, 48) },
			{ name = "Allwetter", cost = 700, time = 18, rate = 1.6, color = Color3.fromRGB(30, 30, 34) },
			{ name = "Semi-Slicks", cost = 4200, time = 55, rate = 5.5, color = Color3.fromRGB(24, 24, 28) },
			{ name = "Renn-Slicks", cost = 22000, time = 170, rate = 18, color = Color3.fromRGB(16, 16, 20) },
		},
	},
	paint = {
		displayName = "Lack",
		mount = "body", -- faerbt die Karosserie
		size = Vector3.new(1.4, 1.4, 1.4),
		tiers = {
			{ name = "Grundierung", cost = 120, time = 6, rate = 0.5, color = Color3.fromRGB(150, 150, 155) },
			{ name = "Zweischicht", cost = 800, time = 18, rate = 1.8, color = Color3.fromRGB(200, 60, 60) },
			{ name = "Perleffekt", cost = 4600, time = 55, rate = 6.0, color = Color3.fromRGB(60, 90, 220) },
			{ name = "Chrom-Wrap", cost = 25000, time = 175, rate = 20, color = Color3.fromRGB(235, 235, 240) },
		},
	},
	turbo = {
		displayName = "Turbo",
		mount = "spoiler", -- Fluegel am Heck
		size = Vector3.new(3.2, 0.4, 0.9),
		tiers = {
			{ name = "Gebrauchtlader", cost = 200, time = 8, rate = 0.9, color = Color3.fromRGB(120, 120, 128) },
			{ name = "Twin-Scroll", cost = 1200, time = 24, rate = 3.0, color = Color3.fromRGB(200, 170, 60) },
			{ name = "Kompressor", cost = 6800, time = 70, rate = 9.5, color = Color3.fromRGB(230, 110, 30) },
			{ name = "Anti-Lag-Kit", cost = 36000, time = 200, rate = 30, color = Color3.fromRGB(240, 60, 90) },
		},
	},
}

function PartCatalog.GetSlot(slotId)
	return PartCatalog.Slots[slotId]
end

function PartCatalog.GetTier(slotId, tier)
	local slot = PartCatalog.Slots[slotId]
	if not slot then
		return nil
	end
	return slot.tiers[tier]
end

-- Wert eines Teils = Summe aller Stufenkosten bis einschliesslich `tier`.
-- Gebraucht fuer Leaderboard ("teuerste Garage") und Verkaufserloes.
function PartCatalog.GetValue(slotId, tier)
	local slot = PartCatalog.Slots[slotId]
	if not slot then
		return 0
	end
	local total = 0
	for i = 1, math.min(tier, #slot.tiers) do
		total += slot.tiers[i].cost
	end
	return total
end

function PartCatalog.GetRate(slotId, tier)
	local def = PartCatalog.GetTier(slotId, tier)
	return def and def.rate or 0
end

function PartCatalog.IsValidSlot(slotId)
	return PartCatalog.Slots[slotId] ~= nil
end

return PartCatalog
