--[[
	TheftOps
	Besitzwechsel von Teilen - der heikelste Teil des Spiels, deshalb an einer
	Stelle.

	Ablauf beim Klauen von einem Spieler:
	  1. Take        Teil wird im Opferprofil als `inTransit` markiert. Es
	                 zaehlt nicht mehr zur Rate, ist aber nicht weg.
	  2a. Commit     Dieb liefert ab -> Teil wird beim Opfer entfernt, das
	                 Opfer bekommt die Versicherung.
	  2b. Clear      Fenster vorbei, Dieb gerempelt oder raus -> Markierung
	                 weg, Teil ist wieder normal in Betrieb.

	Damit kann ein Teil weder verschwinden noch doppelt existieren.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local Server = script.Parent.Parent
local GarageRequests = require(Server.Garage.GarageRequests)
local ProfileOps = require(Server.Data.ProfileOps)
local StealTarget = require(Server.Heist.StealTarget)

local TheftOps = {}

function TheftOps.Take(garage, victim: Player, thief: Player, carIndex: number, slotId: string)
	local data = garage.Services.DataService:Get(victim)
	if not data then
		return nil
	end
	local part = ProfileOps.GetPart(data, carIndex, slotId)
	if not part or part.inTransit then
		return nil
	end
	part.inTransit = thief.UserId
	garage:Refresh(victim, data)
	return ProfileOps.ClonePart(part)
end

function TheftOps.Commit(garage, victim: Player, uid: string): boolean
	local data = garage.Services.DataService:Get(victim)
	if not data then
		return false
	end
	local carIndex, slotId, part = ProfileOps.FindPartByUid(data, uid)
	if not part then
		return false
	end
	local payout = math.floor(ProfileOps.PartValue(part) * Config.INSURANCE_RATE)
	ProfileOps.RemovePart(data, carIndex, slotId)
	data.stats.partsLost += 1
	if payout > 0 then
		garage.Services.EconomyService:AddCash(victim, payout, "Heist")
		garage.Services.EconomyService:Notify(
			victim,
			("Teil weg - Versicherung zahlt %s."):format(Util.FormatCash(payout)),
			"cash"
		)
	end
	garage:Refresh(victim, data)
	return true
end

function TheftOps.Clear(garage, victim: Player, uid: string): boolean
	local data = garage.Services.DataService:Get(victim)
	if not data then
		return false
	end
	local _, _, part = ProfileOps.FindPartByUid(data, uid)
	if not part or not part.inTransit then
		return false
	end
	part.inTransit = nil
	garage:Refresh(victim, data)
	return true
end

-- Abgabe in der eigenen Garage. Ist das Opfer nicht mehr da, geht der Dieb
-- leer aus: sonst gaebe es das Teil zweimal, weil beim Opfer beim naechsten
-- Laden die Transit-Markierung faellt.
function TheftOps.Deposit(garage, thief: Player, part, target)
	local data = garage.Services.DataService:Get(thief)
	if not data then
		return false, "Profil nicht geladen."
	end
	if StealTarget.IsPlayer(target) then
		local victim = target.player
		if not victim.Parent or not TheftOps.Commit(garage, victim, part.uid) then
			return false, "Der Besitzer ist weg - das Teil loest sich in Luft auf."
		end
	end

	ProfileOps.RollDailyStats(data)
	data.stats.stolenToday += 1
	data.stats.totalStolen += 1
	local ok, message = GarageRequests.DepositStolenPart(garage.Services, thief, data, part)
	garage.Services.TelemetryService:Funnel(thief, "firstLoot")
	garage.Services.TelemetryService:Award(thief, "FirstSteal")
	garage:Refresh(thief, data)
	return ok, message
end

return TheftOps
