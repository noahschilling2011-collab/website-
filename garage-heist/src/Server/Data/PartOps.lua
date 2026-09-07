--[[
	PartOps
	Alles, was ein einzelnes Teil betrifft. Aus ProfileOps ausgelagert, damit
	beide Dateien lesbar bleiben; ProfileOps reicht die wichtigsten Funktionen
	unter den alten Namen weiter.

	Wichtig ist hier vor allem `inTransit`: ein Teil, das gerade weggetragen
	wird, bleibt im Profil des Opfers stehen und zaehlt nur nicht zur Rate.
	Erst die Abgabe in der Diebesgarage nimmt es wirklich weg. Solange es
	unterwegs ist, kann es nicht verloren gehen, wenn jemand rausfliegt.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local PartCatalog = require(Shared.PartCatalog)
local Util = require(Shared.Util)

local PartOps = {}

-- `mult` traegt den Abschlag fuer Leerstand-Beute (Config.DERELICT_VALUE_MULT).
function PartOps.Rate(part): number
	if not part or part.inTransit then
		return 0
	end
	return PartCatalog.GetRate(part.slotId, part.tier, part.subTier or 0) * (part.mult or 1)
end

function PartOps.Value(part): number
	if not part then
		return 0
	end
	return PartCatalog.GetValue(part.slotId, part.tier, part.subTier or 0) * (part.mult or 1)
end

-- Vollstaendige Kopie. Wer neue Felder ergaenzt, ergaenzt sie hier - sonst
-- gehen sie beim Ein- und Ausbauen verloren. `inTransit` wird bewusst NICHT
-- mitkopiert: die Kopie ist das getragene Teil, nicht das im Profil.
function PartOps.Clone(part)
	return {
		uid = part.uid,
		slotId = part.slotId,
		tier = part.tier,
		subTier = part.subTier or 0,
		originalOwner = part.originalOwner,
		mult = part.mult,
	}
end

function PartOps.New(slotId: string, tier: number, originalOwner: number, subTier: number?)
	return {
		uid = Util.NewUid(),
		slotId = slotId,
		tier = tier,
		subTier = subTier or 0,
		originalOwner = originalOwner,
	}
end

function PartOps.FindByUid(data, uid: string)
	for carIndex, car in data.cars do
		for slotId, part in car.parts do
			if part.uid == uid then
				return carIndex, slotId, part
			end
		end
	end
	return nil, nil, nil
end

-- Beim Laden aufrufen: ein Server-Absturz oder ein Verbindungsabbruch darf
-- kein Teil dauerhaft als "unterwegs" markiert zuruecklassen.
function PartOps.ClearAllInTransit(data)
	local cleared = 0
	for _, car in data.cars do
		for _, part in car.parts do
			if part.inTransit then
				part.inTransit = nil
				cleared += 1
			end
		end
	end
	return cleared
end

return PartOps
