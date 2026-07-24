--[[
	Snapshot
	Baut aus einem Profil das Paket, das der Client zum Anzeigen bekommt.
	Reine Lesefunktion - hier wird nichts veraendert und nichts entschieden.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.CarCatalog)
local Config = require(Shared.Config)
local PartCatalog = require(Shared.PartCatalog)

local ProfileOps = require(script.Parent.Parent.Data.ProfileOps)

local Snapshot = {}

local function partEntry(data, carIndex: number, slotId: string, ownerUserId: number)
	local slotDef = PartCatalog.GetSlot(slotId)
	local part = ProfileOps.GetPart(data, carIndex, slotId)
	local repair = data.repairs[ProfileOps.RepairKey(carIndex, slotId)]
	local tier = part and part.tier or 0
	local tierDef = part and PartCatalog.GetTier(slotId, tier)
	local nextTier = repair and (repair.tier + 1) or (tier + 1)
	local nextDef = PartCatalog.GetTier(slotId, nextTier)

	return {
		slotId = slotId,
		slotName = slotDef.displayName,
		tier = tier,
		tierName = tierDef and tierDef.name or "leer",
		rate = part and PartCatalog.GetRate(slotId, tier) or 0,
		stolen = part ~= nil and part.originalOwner ~= ownerUserId,
		repair = repair and { endsAt = repair.endsAt, tier = repair.tier } or nil,
		nextTier = nextDef and nextTier or nil,
		nextName = nextDef and nextDef.name or nil,
		nextCost = nextDef and nextDef.cost or nil,
		nextTime = nextDef and nextDef.time or nil,
		nextRate = nextDef and nextDef.rate or nil,
	}
end

function Snapshot.Build(player: Player, data, extra)
	extra = extra or {}
	local levelDef, level = ProfileOps.GarageLevelDef(data)
	local nextLevelDef = Config.GARAGE_LEVELS[level + 1]

	local cars = {}
	for carIndex, car in data.cars do
		local carDef = CarCatalog.Get(car.carId)
		local parts = {}
		for _, slotId in PartCatalog.SlotOrder do
			table.insert(parts, partEntry(data, carIndex, slotId, player.UserId))
		end
		table.insert(cars, {
			carIndex = carIndex,
			carId = car.carId,
			displayName = carDef and carDef.displayName or car.carId,
			rateMult = carDef and carDef.rateMult or 1,
			parts = parts,
		})
	end

	local loose = {}
	for uid, part in data.looseParts do
		local slotDef = PartCatalog.GetSlot(part.slotId)
		local tierDef = PartCatalog.GetTier(part.slotId, part.tier)
		table.insert(loose, {
			uid = uid,
			slotId = part.slotId,
			slotName = slotDef and slotDef.displayName or part.slotId,
			tier = part.tier,
			tierName = tierDef and tierDef.name or "?",
			sellValue = math.floor(PartCatalog.GetValue(part.slotId, part.tier) * Config.SELL_REFUND),
			installCarIndex = ProfileOps.FindEmptySlot(data, part.slotId),
		})
	end
	table.sort(loose, function(a, b)
		return a.sellValue > b.sellValue
	end)

	local shopCars = {}
	for _, carId in CarCatalog.Order do
		local carDef = CarCatalog.Get(carId)
		table.insert(shopCars, {
			carId = carId,
			displayName = carDef.displayName,
			cost = carDef.cost,
			rateMult = carDef.rateMult,
		})
	end

	return {
		cash = math.floor(data.cash),
		pile = math.floor(data.pile),
		rate = extra.rate or ProfileOps.ComputeBaseRate(data),
		garage = {
			level = level,
			label = levelDef.label,
			rateMult = levelDef.rateMult,
			carSlots = levelDef.carSlots,
			nextCost = nextLevelDef and nextLevelDef.cost or nil,
			nextLabel = nextLevelDef and nextLevelDef.label or nil,
			nextRateMult = nextLevelDef and nextLevelDef.rateMult or nil,
			nextCarSlots = nextLevelDef and nextLevelDef.carSlots or nil,
		},
		cars = cars,
		looseParts = loose,
		shopCars = shopCars,
		stats = {
			stolenToday = data.stats.stolenToday,
			totalStolen = data.stats.totalStolen,
			partsLost = data.stats.partsLost,
			garageValue = ProfileOps.GarageValue(data),
		},
		passes = extra.passes or {},
	}
end

return Snapshot
