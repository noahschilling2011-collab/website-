--[[
	GarageRequests
	Jede Aktion, die der Client anfragen kann. Reihenfolge ist immer gleich:
	Profil da? Gehoert ihm das? Ist der Wunsch ueberhaupt gueltig? Reicht das
	Geld? Erst dann wird etwas veraendert.

	Gibt (ok, meldung) zurueck. Das Rendern uebernimmt der GarageService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

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

	local purchase = ProfileOps.NextPurchase(data, carIndex, slotId)
	if not purchase then
		return false, "Hoechste Stufe ist schon verbaut."
	end
	-- Muss VOR TrySpend stehen: ein gesperrter Eintrag hat keinen Preis.
	if purchase.kind == "locked" then
		return false,
			("Prototypen gibt's nicht im Handel. %s holst du dir im Klau-Fenster aus einer fremden Box."):format(
				purchase.name
			)
	end
	if not services.EconomyService:TrySpend(player, purchase.cost, "Part") then
		return false, ("Zu wenig Cash: %s noetig."):format(Util.FormatCash(purchase.cost))
	end

	ProfileOps.StartRepair(data, carIndex, slotId, purchase, os.time() + purchase.time)
	services.EffectService:LocalSound(player, "purchase")
	services.TelemetryService:Funnel(player, "firstPart")
	return true, ("%s wird eingebaut (%ds)."):format(purchase.name, purchase.time)
end

--[[
	Ein Schlag im Reparatur-Minispiel.

	Der Client meldet, wo der Marker aus seiner Sicht stand. Der Server rechnet
	die Position aus derselben Formel noch einmal aus und nimmt die Meldung nur
	an, wenn sie innerhalb von REPAIR_LATENCY_TOLERANCE dazu passt - sonst
	rechnet er mit seinem eigenen Wert. Ein manipulierter Client kann damit
	hoechstens so gut sein wie jemand, der perfekt spielt.

	Die harte Grenze ist die Rundenzahl: nach REPAIR_MINIGAME_ROUNDS Schlaegen
	ist Schluss, egal wie sie ausgingen. Maximal erreichbar sind also
	ROUNDS * (HIT_REDUCTION + PERFECT_BONUS) der Restzeit - nie 0.

	Gibt (ok, meldung) NICHT im ueblichen Sinn zurueck: bei 3 Schlaegen pro
	Reparatur waere ein Toast je Schlag Laerm. Rueckgabe ist (ok, nil).
]]
function GarageRequests.RepairTick(services, player: Player, data, carIndex, slotId, claimedPos)
	if not validCarIndex(data, carIndex) or type(slotId) ~= "string" or not PartCatalog.IsValidSlot(slotId) then
		return false
	end
	local repair = data.repairs[ProfileOps.RepairKey(carIndex, slotId)]
	if not repair then
		return false
	end
	if (repair.hits or 0) >= Config.REPAIR_MINIGAME_ROUNDS then
		return false
	end

	-- Nah genug an der eigenen Werkbank? Ohne das spielt man es quer ueber die
	-- Karte, waehrend man in einer fremden Garage steht.
	local view = services.GarageService.views[player.UserId]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not view or not root then
		return false
	end
	if (view.plot.workbench.Position - (root :: BasePart).Position).Magnitude > Config.REPAIR_MINIGAME_RANGE then
		return false
	end

	local serverPos = Util.RepairMarker(Workspace:GetServerTimeNow(), Config.REPAIR_SWEEP)
	local position = serverPos
	local claimed = tonumber(claimedPos)
	if claimed and claimed == claimed and math.abs(claimed - serverPos) <= Config.REPAIR_LATENCY_TOLERANCE then
		position = math.clamp(claimed, 0, 1)
	end

	repair.hits = (repair.hits or 0) + 1

	local offset = math.abs(position - 0.5)
	local reduction = 0
	if offset <= Config.REPAIR_PERFECT_HALF then
		reduction = Config.REPAIR_HIT_REDUCTION + Config.REPAIR_PERFECT_BONUS
	elseif offset <= Config.REPAIR_ZONE_HALF then
		reduction = Config.REPAIR_HIT_REDUCTION
	end
	if reduction <= 0 then
		return false
	end

	local remaining = math.max(0, repair.endsAt - os.time())
	repair.endsAt -= remaining * reduction
	services.EffectService:LocalSound(player, "purchase")
	return true
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
	if carDef.cost > 0 and not services.EconomyService:TrySpend(player, carDef.cost, "Car") then
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
	if not services.EconomyService:TrySpend(player, nextDef.cost, "Garage") then
		return false, ("Zu wenig Cash: %s noetig."):format(Util.FormatCash(nextDef.cost))
	end
	data.garageLevel = level + 1
	return true, ("Garage ausgebaut: %s (x%.2f Rate)."):format(nextDef.label, nextDef.rateMult)
end

-- Rebirth: alles auf Anfang, dafuer dauerhaft mehr Rate.
function GarageRequests.Rebirth(services, player: Player, data)
	local ok, reason = ProfileOps.CanRebirth(data)
	if not ok then
		return false, reason
	end
	local count = ProfileOps.Rebirth(data)
	services.TelemetryService:Award(player, "FirstRebirth")
	return true, ("Rebirth %d. Dauerhaft +%d%% Rate."):format(count, math.floor(Config.REBIRTH_MULT * count * 100))
end

function GarageRequests.SellLoosePart(services, player: Player, data, uid)
	if type(uid) ~= "string" then
		return false, "Ungueltiges Teil."
	end
	local part = data.looseParts[uid]
	if not part then
		return false, "Das Teil liegt nicht in deiner Garage."
	end
	local value = math.floor(ProfileOps.PartValue(part) * Config.SELL_REFUND)
	ProfileOps.TakeLoosePart(data, uid)
	services.EconomyService:AddCash(player, value, "Heist")
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
	ProfileOps.SetPart(data, carIndex, part.slotId, ProfileOps.ClonePart(part))
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
