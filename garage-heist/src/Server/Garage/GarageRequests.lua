--[[
	GarageRequests
	Jede Aktion, die der Client anfragen kann. Reihenfolge ist immer gleich:
	Profil da? Gehoert ihm das? Ist der Wunsch ueberhaupt gueltig? Reicht das
	Geld? Erst dann wird etwas veraendert.

	Gibt (ok, meldung) zurueck. Das Rendern uebernimmt der GarageService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.CarCatalog)
local Config = require(Shared.Config)
local PartCatalog = require(Shared.PartCatalog)
local Util = require(Shared.Util)

local ProfileOps = require(script.Parent.Parent.Data.ProfileOps)

local GarageRequests = {}

local function validCarIndex(data, carIndex): boolean
	if type(carIndex) ~= "number" or carIndex % 1 ~= 0 then
		return false
	end
	return data.cars[carIndex] ~= nil
end

function GarageRequests.BuyPart(services, player: Player, data, carIndex, slotId)
	if not validCarIndex(data, carIndex) then
		return false, "Dieses Auto gehoert dir nicht."
	end
	if type(slotId) ~= "string" or not PartCatalog.IsValidSlot(slotId) then
		return false, "Unbekannter Teile-Slot."
	end
	local key = ProfileOps.RepairKey(carIndex, slotId)
	if data.repairs[key] then
		return false, "Da wird gerade schon geschraubt."
	end

	local nextTier = ProfileOps.CurrentTier(data, carIndex, slotId) + 1
	local tierDef = PartCatalog.GetTier(slotId, nextTier)
	if not tierDef then
		return false, "Hoechste Stufe ist schon verbaut."
	end
	if not services.EconomyService:TrySpend(player, tierDef.cost) then
		return false, ("Zu wenig Cash: %s noetig."):format(Util.FormatCash(tierDef.cost))
	end

	ProfileOps.StartRepair(data, carIndex, slotId, nextTier, os.time() + tierDef.time)
	return true, ("%s wird eingebaut (%ds)."):format(tierDef.name, tierDef.time)
end

-- Wird nur nach einem bestaetigten Robux-Kauf aufgerufen.
function GarageRequests.FinishRepairNow(services, player: Player, data, carIndex, slotId): boolean
	if not validCarIndex(data, carIndex) or not PartCatalog.IsValidSlot(slotId) then
		return false
	end
	local repair = data.repairs[ProfileOps.RepairKey(carIndex, slotId)]
	if not repair then
		return false
	end
	repair.endsAt = os.time()
	return true
end

function GarageRequests.BuyCar(services, player: Player, data, carId)
	if type(carId) ~= "string" or not CarCatalog.IsValid(carId) then
		return false, "Dieses Auto gibt es nicht."
	end
	local carDef = CarCatalog.Get(carId)
	local slots = ProfileOps.CarSlots(data)
	if #data.cars >= slots then
		return false, ("Kein Stellplatz frei (%d/%d). Erst die Garage ausbauen."):format(#data.cars, slots)
	end
	if carDef.cost > 0 and not services.EconomyService:TrySpend(player, carDef.cost) then
		return false, ("Zu wenig Cash: %s noetig."):format(Util.FormatCash(carDef.cost))
	end
	table.insert(data.cars, { carId = carId, parts = {} })
	return true, ("%s steht in der Garage."):format(carDef.displayName)
end

function GarageRequests.UpgradeGarage(services, player: Player, data)
	local _, level = ProfileOps.GarageLevelDef(data)
	local nextDef = Config.GARAGE_LEVELS[level + 1]
	if not nextDef then
		return false, "Die Garage ist voll ausgebaut."
	end
	if not services.EconomyService:TrySpend(player, nextDef.cost) then
		return false, ("Zu wenig Cash: %s noetig."):format(Util.FormatCash(nextDef.cost))
	end
	data.garageLevel = level + 1
	return true, ("Garage ausgebaut: %s (x%.2f Rate)."):format(nextDef.label, nextDef.rateMult)
end

function GarageRequests.SellLoosePart(services, player: Player, data, uid)
	if type(uid) ~= "string" then
		return false, "Ungueltiges Teil."
	end
	local part = data.looseParts[uid]
	if not part then
		return false, "Das Teil liegt nicht in deiner Garage."
	end
	local value = math.floor(PartCatalog.GetValue(part.slotId, part.tier) * Config.SELL_REFUND)
	ProfileOps.TakeLoosePart(data, uid)
	services.EconomyService:AddCash(player, value)
	return true, ("Verkauft fuer %s."):format(Util.FormatCash(value))
end

function GarageRequests.InstallLoosePart(services, player: Player, data, uid, carIndex)
	if type(uid) ~= "string" then
		return false, "Ungueltiges Teil."
	end
	local part = data.looseParts[uid]
	if not part then
		return false, "Das Teil liegt nicht in deiner Garage."
	end
	if carIndex == nil then
		carIndex = ProfileOps.FindEmptySlot(data, part.slotId)
	end
	if not validCarIndex(data, carIndex) then
		return false, "Kein passendes Auto."
	end
	if ProfileOps.GetPart(data, carIndex, part.slotId) then
		return false, "Der Platz ist belegt. Erst das alte Teil ersetzen."
	end
	if data.repairs[ProfileOps.RepairKey(carIndex, part.slotId)] then
		return false, "An dem Platz wird gerade geschraubt."
	end

	ProfileOps.TakeLoosePart(data, uid)
	ProfileOps.SetPart(data, carIndex, part.slotId, {
		uid = part.uid,
		slotId = part.slotId,
		tier = part.tier,
		originalOwner = part.originalOwner,
	})
	local tierDef = PartCatalog.GetTier(part.slotId, part.tier)
	return true, ("%s eingebaut."):format(tierDef and tierDef.name or part.slotId)
end

-- Abgeliefertes Diebesgut: passt es in einen freien Slot, wird es eingebaut,
-- sonst liegt es lose in der Garage und kann verkauft werden.
function GarageRequests.DepositStolenPart(services, player: Player, data, part)
	ProfileOps.AddLoosePart(data, part)
	local carIndex = ProfileOps.FindEmptySlot(data, part.slotId)
	if carIndex then
		local ok, message = GarageRequests.InstallLoosePart(services, player, data, part.uid, carIndex)
		if ok then
			return true, message
		end
	end
	local tierDef = PartCatalog.GetTier(part.slotId, part.tier)
	return true, ("%s liegt jetzt in deiner Garage (kein freier Platz)."):format(tierDef and tierDef.name or part.slotId)
end

return GarageRequests
