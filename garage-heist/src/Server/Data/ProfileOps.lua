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

local PartOps = require(script.Parent.PartOps)

local ProfileOps = {}

function ProfileOps.RepairKey(carIndex: number, slotId: string): string
	return tostring(carIndex) .. ":" .. slotId
end

function ProfileOps.GarageLevelDef(data)
	local level = math.clamp(data.garageLevel or 1, 1, #Config.GARAGE_LEVELS)
	return Config.GARAGE_LEVELS[level], level
end

-- Teil-Ebene liegt in PartOps. Die alten Namen bleiben, damit die Aufrufer
-- unveraendert bleiben.
ProfileOps.PartRate = PartOps.Rate
ProfileOps.PartValue = PartOps.Value
ProfileOps.ClonePart = PartOps.Clone
ProfileOps.FindPartByUid = PartOps.FindByUid
ProfileOps.ClearAllInTransit = PartOps.ClearAllInTransit

-- Cash pro Sekunde ohne Gamepass-Multiplikator.
function ProfileOps.ComputeBaseRate(data): number
	local levelDef = ProfileOps.GarageLevelDef(data)
	local total = 0
	for _, car in data.cars do
		local carDef = CarCatalog.Get(car.carId)
		if carDef then
			local carSum = 0
			for _, part in car.parts do
				carSum += ProfileOps.PartRate(part)
			end
			total += carSum * carDef.rateMult
		end
	end
	-- Rebirth wirkt dauerhaft und multiplikativ auf alles.
	return total * levelDef.rateMult * (1 + Config.REBIRTH_MULT * (data.rebirths or 0))
end

-- Summe aller Teile- und Autokosten. Basis fuer "teuerste Garage".
function ProfileOps.GarageValue(data): number
	local total = 0
	for _, car in data.cars do
		local carDef = CarCatalog.Get(car.carId)
		if carDef then
			total += carDef.cost
		end
		for _, part in car.parts do
			total += ProfileOps.PartValue(part)
		end
	end
	for _, part in data.looseParts do
		total += ProfileOps.PartValue(part)
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

-- Der naechste Kauf fuer diesen Slot. Die Leiter ist streng:
-- leer -> T1 -> T1 fein 1 -> T1 fein 2 -> T2 -> ... -> T4 fein 2 (Ende).
-- Gibt nil zurueck, wenn nichts mehr geht.
function ProfileOps.NextPurchase(data, carIndex: number, slotId: string)
	local part = ProfileOps.GetPart(data, carIndex, slotId)
	local tier = part and part.tier or 0
	local subTier = part and (part.subTier or 0) or 0

	if tier <= 0 then
		local def = PartCatalog.GetTier(slotId, 1)
		if not def then
			return nil
		end
		return {
			kind = "tier",
			tier = 1,
			subTier = 0,
			cost = def.cost,
			time = def.time,
			name = def.name,
		}
	end

	if subTier < Config.SUBTIER_COUNT then
		local def = PartCatalog.GetTier(slotId, tier)
		return {
			kind = "sub",
			tier = tier,
			subTier = subTier + 1,
			cost = PartCatalog.SubStepCost(slotId, tier),
			time = PartCatalog.SubStepTime(slotId, tier),
			name = ("%s - Feinabstimmung %d"):format(def.name, subTier + 1),
		}
	end

	local nextDef = PartCatalog.GetTier(slotId, tier + 1)
	if not nextDef then
		return nil
	end
	return {
		kind = "tier",
		tier = tier + 1,
		subTier = 0,
		cost = PartCatalog.TierUpgradeCost(slotId, tier, subTier),
		time = nextDef.time,
		name = nextDef.name,
	}
end

function ProfileOps.AddLoosePart(data, part)
	data.looseParts[part.uid] = ProfileOps.ClonePart(part)
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

function ProfileOps.StartRepair(data, carIndex: number, slotId: string, purchase, endsAt: number)
	data.repairs[ProfileOps.RepairKey(carIndex, slotId)] = {
		tier = purchase.tier,
		subTier = purchase.subTier,
		kind = purchase.kind,
		endsAt = endsAt,
		startedAt = os.time(),
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

	-- Feinabstimmung veraendert das vorhandene Teil, ein Tier-Sprung ersetzt es.
	local existing = ProfileOps.GetPart(data, carIndex, slotId)
	if repair.kind == "sub" and existing then
		existing.subTier = repair.subTier or ((existing.subTier or 0) + 1)
		return existing
	end

	local part = PartOps.New(slotId, repair.tier, ownerUserId, repair.subTier)
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
	local bonus = ((data.rebirths or 0) >= Config.REBIRTH_EXTRA_SLOT_AT) and 1 or 0
	return levelDef.carSlots + bonus
end

-- Rebirth ist erst moeglich, wenn die Garage voll ausgebaut ist und jedes Auto
-- auf jedem Slot die hoechste Stufe traegt.
function ProfileOps.CanRebirth(data): (boolean, string)
	local _, level = ProfileOps.GarageLevelDef(data)
	if level < #Config.GARAGE_LEVELS then
		return false, "Garage muss voll ausgebaut sein."
	end
	for carIndex in data.cars do
		for _, slotId in PartCatalog.SlotOrder do
			local part = ProfileOps.GetPart(data, carIndex, slotId)
			if not part or part.tier < PartCatalog.TierCount(slotId) then
				return false, "Alle Teile muessen auf der hoechsten Stufe sein."
			end
		end
	end
	return true, "Bereit."
end

-- Setzt den Fortschritt zurueck, behaelt Rebirth-Zaehler, Statistik und
-- alles, was mit Robux gekauft wurde (Gamepasses liegen ohnehin bei Roblox).
function ProfileOps.Rebirth(data)
	data.rebirths = (data.rebirths or 0) + 1
	data.cars = { { carId = CarCatalog.STARTER, parts = {} } }
	data.garageLevel = 1
	data.cash = Config.START_CASH
	data.pile = 0
	data.looseParts = {}
	data.repairs = {}
	return data.rebirths
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
