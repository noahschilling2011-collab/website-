--[[
	ProfileOps
	Reine Datenoperationen auf einem Profil. Keine Instances, keine Remotes,
	keine Zeitschleifen - dadurch kann sowohl die Online-Logik (GarageService)
	als auch die Offline-Abrechnung (EconomyService) exakt dasselbe rechnen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local CarCatalog = require(Shared.CarCatalog)
local Config = require(Shared.Config)
local PartCatalog = require(Shared.PartCatalog)
local Util = require(Shared.Util)

local ProfileOps = {}

function ProfileOps.RepairKey(carIndex: number, slotId: string): string
	return tostring(carIndex) .. ":" .. slotId
end

function ProfileOps.GarageLevelDef(data)
	local level = math.clamp(data.garageLevel or 1, 1, #Config.GARAGE_LEVELS)
	return Config.GARAGE_LEVELS[level], level
end

-- Cash pro Sekunde ohne Gamepass-Multiplikator.
function ProfileOps.ComputeBaseRate(data): number
	local levelDef = ProfileOps.GarageLevelDef(data)
	local total = 0
	for _, car in data.cars do
		local carDef = CarCatalog.Get(car.carId)
		if carDef then
			local carSum = 0
			for slotId, part in car.parts do
				carSum += PartCatalog.GetRate(slotId, part.tier)
			end
			total += carSum * carDef.rateMult
		end
	end
	return total * levelDef.rateMult
end

-- Summe aller Teile- und Autokosten. Basis fuer "teuerste Garage".
function ProfileOps.GarageValue(data): number
	local total = 0
	for _, car in data.cars do
		local carDef = CarCatalog.Get(car.carId)
		if carDef then
			total += carDef.cost
		end
		for slotId, part in car.parts do
			total += PartCatalog.GetValue(slotId, part.tier)
		end
	end
	for _, part in data.looseParts do
		total += PartCatalog.GetValue(part.slotId, part.tier)
	end
	local _, level = ProfileOps.GarageLevelDef(data)
	for i = 1, level do
		total += Config.GARAGE_LEVELS[i].cost
	end
	return total
end

function ProfileOps.GetPart(data, carIndex: number, slotId: string)
	local car = data.cars[carIndex]
	return car and car.parts[slotId] or nil
end

function ProfileOps.CurrentTier(data, carIndex: number, slotId: string): number
	local part = ProfileOps.GetPart(data, carIndex, slotId)
	return part and part.tier or 0
end

function ProfileOps.SetPart(data, carIndex: number, slotId: string, part)
	local car = data.cars[carIndex]
	if not car then
		return false
	end
	car.parts[slotId] = part
	return true
end

function ProfileOps.RemovePart(data, carIndex: number, slotId: string)
	local car = data.cars[carIndex]
	if not car then
		return nil
	end
	local part = car.parts[slotId]
	car.parts[slotId] = nil
	return part
end

function ProfileOps.NewPart(slotId: string, tier: number, originalOwner: number)
	return {
		uid = Util.NewUid(),
		slotId = slotId,
		tier = tier,
		originalOwner = originalOwner,
	}
end

function ProfileOps.AddLoosePart(data, part)
	data.looseParts[part.uid] = {
		uid = part.uid,
		slotId = part.slotId,
		tier = part.tier,
		originalOwner = part.originalOwner,
	}
end

function ProfileOps.TakeLoosePart(data, uid: string)
	local part = data.looseParts[uid]
	data.looseParts[uid] = nil
	return part
end

-- Erstes Auto, dessen Slot `slotId` frei ist (und nicht in Reparatur).
function ProfileOps.FindEmptySlot(data, slotId: string): number?
	for index in data.cars do
		if not ProfileOps.GetPart(data, index, slotId) and not data.repairs[ProfileOps.RepairKey(index, slotId)] then
			return index
		end
	end
	return nil
end

function ProfileOps.StartRepair(data, carIndex: number, slotId: string, tier: number, endsAt: number)
	data.repairs[ProfileOps.RepairKey(carIndex, slotId)] = {
		tier = tier,
		endsAt = endsAt,
		carIndex = carIndex,
		slotId = slotId,
	}
end

-- Reparatur abschliessen: altes Teil faellt weg, neues wird eingebaut.
function ProfileOps.FinishRepair(data, carIndex: number, slotId: string, ownerUserId: number)
	local key = ProfileOps.RepairKey(carIndex, slotId)
	local repair = data.repairs[key]
	if not repair then
		return nil
	end
	data.repairs[key] = nil
	local part = ProfileOps.NewPart(slotId, repair.tier, ownerUserId)
	ProfileOps.SetPart(data, carIndex, slotId, part)
	return part
end

-- Alle Reparaturen, die bis `until` fertig sind - aufsteigend nach Endzeit.
function ProfileOps.RepairsDueBefore(data, untilTime: number)
	local due = {}
	for _, repair in data.repairs do
		if repair.endsAt <= untilTime then
			table.insert(due, repair)
		end
	end
	table.sort(due, function(a, b)
		return a.endsAt < b.endsAt
	end)
	return due
end

function ProfileOps.CarSlots(data): number
	local levelDef = ProfileOps.GarageLevelDef(data)
	return levelDef.carSlots
end

-- Setzt den Tageszaehler zurueck, wenn ein neuer UTC-Tag begonnen hat.
function ProfileOps.RollDailyStats(data)
	local today = Util.UtcDay()
	if data.stats.stolenDay ~= today then
		data.stats.stolenDay = today
		data.stats.stolenToday = 0
	end
end

return ProfileOps
