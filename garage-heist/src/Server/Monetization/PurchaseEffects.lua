--[[
	PurchaseEffects
	Was ein Developer Product konkret tut. Jede Funktion gibt true zurueck,
	wenn sie sauber durchgelaufen ist - nur dann wird der Receipt als
	verarbeitet abgehakt.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)

local GarageRequests = require(script.Parent.Parent.Garage.GarageRequests)

local PurchaseEffects = {}

-- Bewusst so gewaehlt, dass auch das groesste Paket den Loop nicht ersetzt:
-- das teuerste Garagen-Upgrade kostet 260k, der Supersportler 75k.
PurchaseEffects.CASH_AMOUNTS = {
	CashSmall = 5000,
	CashMedium = 30000,
	CashLarge = 150000,
}

function PurchaseEffects.GrantCash(services, player: Player, data, key: string): boolean
	local amount = PurchaseEffects.CASH_AMOUNTS[key]
	if not amount then
		return false
	end
	data.cash += amount
	services.EconomyService:Push(player, true)
	services.EconomyService:Notify(player, ("Cash-Paket gutgeschrieben: %s"):format(Util.FormatCash(amount)), "good")
	return true
end

function PurchaseEffects.InstantRepair(services, player: Player, data, target): boolean
	if not target then
		services.EconomyService:Notify(player, "Keine laufende Reparatur - Kauf nicht angewendet.", "bad")
		return false
	end
	local ok = GarageRequests.FinishRepairNow(services, player, data, target.carIndex, target.slotId)
	if not ok then
		services.EconomyService:Notify(player, "Die Reparatur ist schon fertig.", "bad")
		return false
	end
	services.EconomyService:Notify(player, "Reparatur uebersprungen.", "good")
	return true
end

function PurchaseEffects.HeistRadar(services, player: Player, data): boolean
	-- Die Ladung liegt im Profil, nicht im Serverspeicher: wer nach dem Kauf
	-- rausfliegt, bekommt sie beim naechsten Fenster trotzdem.
	services.HeistService:GrantRadar(player, data)
	return true
end

return PurchaseEffects
