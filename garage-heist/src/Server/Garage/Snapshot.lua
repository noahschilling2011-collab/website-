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
	local subTier = part and (part.subTier or 0) or 0
	local tierDef = part and PartCatalog.GetTier(slotId, tier)
	-- Waehrend einer Reparatur gibt es keinen naechsten Kauf zu zeigen.
	local purchase = (not repair) and ProfileOps.NextPurchase(data, carIndex, slotId) or nil

	return {
		slotId = slotId,
		slotName = slotDef.displayName,
		tier = tier,
		subTier = subTier,
		maxSubTier = Config.SUBTIER_COUNT,
		tierName = tierDef and tierDef.name or "leer",
		rate = ProfileOps.PartRate(part),
		stolen = part ~= nil and part.originalOwner ~= ownerUserId,
		inTransit = part ~= nil and part.inTransit ~= nil,
		-- `hits` treibt das Minispiel: der Client blendet die Leiste aus, sobald
		-- die Runden aufgebraucht sind. Gezaehlt wird auf dem Server.
		repair = repair and {
			endsAt = repair.endsAt,
			tier = repair.tier,
			kind = repair.kind,
			hits = repair.hits or 0,
		} or nil,
		nextKind = purchase and purchase.kind or nil,
		nextName = purchase and purchase.name or nil,
		nextCost = purchase and purchase.cost or nil,
		nextTime = purchase and purchase.time or nil,
	}
end

function Snapshot.Build(player: Player, data, extra)
	extra = extra or {}
	local levelDef, level = ProfileOps.GarageLevelDef(data)
	local nextLevelDef = Config.GARAGE_LEVELS[level + 1]

	local canRebirth, rebirthReason = ProfileOps.CanRebirth(data)
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
			sellValue = math.floor(ProfileOps.PartValue(part) * Config.SELL_REFUND),
			installCarIndex = ProfileOps.FindEmptySlot(data, part.slotId),
		})
	end
	table.sort(loose, function(a, b)
		return a.sellValue > b.sellValue
	end)

	local carSlots = ProfileOps.CarSlots(data)
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
			carSlots = carSlots,
			nextCost = nextLevelDef and nextLevelDef.cost or nil,
			nextLabel = nextLevelDef and nextLevelDef.label or nil,
			nextRateMult = nextLevelDef and nextLevelDef.rateMult or nil,
			nextCarSlots = nextLevelDef and nextLevelDef.carSlots or nil,
		},
		cars = cars,
		rebirth = {
			count = data.rebirths or 0,
			can = canRebirth,
			reason = rebirthReason,
			bonus = Config.REBIRTH_MULT,
			-- Was der naechste Durchgang aufmacht. Ohne diese Zeile ist Rebirth
			-- ein Knopf, hinter dem nur eine groessere Zahl steht.
			nextUnlock = ProfileOps.NextUnlock(data),
		},
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
