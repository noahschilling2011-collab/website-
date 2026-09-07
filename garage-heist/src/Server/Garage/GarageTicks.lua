--[[
	GarageTicks
	Die drei periodischen Schleifen der Garage, aus dem GarageService
	ausgelagert: fertige Reparaturen einbauen, Tore auf/zu, Reparaturbalken
	nachziehen.

	Jede Schleife liest den Zustand frisch aus dem Profil - hier wird nichts
	zwischengespeichert.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PartCatalog = require(Shared.PartCatalog)

local Server = script.Parent.Parent
local ProfileOps = require(Server.Data.ProfileOps)
local RepairView = require(Server.Garage.RepairView)
local DoorController = require(Server.World.DoorController)

local GarageTicks = {}

local REPAIR_STEP = 1
local DOOR_STEP = 0.5
local BAR_STEP = 0.25

-- Fertige Reparaturen einbauen. Laeuft erst, wenn die Offline-Abrechnung
-- durch ist - sonst wuerde ein offline fertiggewordenes Teil doppelt zaehlen.
local function repairTick(garage)
	local now = os.time()
	garage.Services.DataService:ForEachProfile(function(player, data)
		if not garage.Services.EconomyService:IsSettled(player) then
			return
		end
		local due = ProfileOps.RepairsDueBefore(data, now)
		if #due == 0 then
			return
		end
		for _, repair in due do
			local part = ProfileOps.FinishRepair(data, repair.carIndex, repair.slotId, player.UserId)
			if part then
				local tierDef = PartCatalog.GetTier(part.slotId, part.tier)
				garage.Services.EconomyService:Notify(
					player,
					("%s ist eingebaut."):format(tierDef and tierDef.name or part.slotId),
					"good"
				)
				garage.Services.EffectService:LocalSound(player, "repairDone")
			end
		end
		garage:Refresh(player, data)
	end)
end

function GarageTicks.Start(garage)
	task.spawn(function()
		while true do
			task.wait(REPAIR_STEP)
			repairTick(garage)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(DOOR_STEP)
			DoorController.Tick(garage.plots, garage.plotOwner, function(index)
				return garage.Services.HeistService:IsPlotOpen(index)
			end)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(BAR_STEP)
			garage.Services.DataService:ForEachProfile(function(player, data)
				local view = garage.views[player.UserId]
				if view then
					RepairView.Tick(view, data)
				end
			end)
		end
	end)
end

return GarageTicks
