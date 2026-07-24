--[[
	RequestRouter
	Bindet die Client-Remotes an GarageRequests. Jede Verbindung laeuft durch
	dieselbe Schleuse: Drosselung, Profil vorhanden, Ergebnis melden, Welt neu
	zeichnen. Kein Handler bekommt Rohdaten ungeprueft weitergereicht.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local GarageRequests = require(script.Parent.GarageRequests)
local Snapshot = require(script.Parent.Snapshot)

local RequestRouter = {}

local REQUEST_COOLDOWN = 0.15

local function throttled(garage, player: Player, key: string): boolean
	local now = os.clock()
	local perPlayer = garage._cooldowns[player.UserId]
	if not perPlayer then
		perPlayer = {}
		garage._cooldowns[player.UserId] = perPlayer
	end
	if now - (perPlayer[key] or 0) < REQUEST_COOLDOWN then
		return true
	end
	perPlayer[key] = now
	return false
end

local function bind(garage, name: string, handler)
	Remotes.Get(name).OnServerEvent:Connect(function(player, ...)
		if throttled(garage, player, name) then
			return
		end
		local data = garage.Services.DataService:Get(player)
		if not data then
			return
		end
		local ok, message = handler(player, data, ...)
		if message then
			garage.Services.EconomyService:Notify(player, message, ok and "good" or "bad")
		end
		if ok then
			garage:Refresh(player, data)
		end
	end)
end

function RequestRouter.Bind(garage)
	local services = garage.Services

	bind(garage, "RequestBuyPart", function(player, data, carIndex, slotId)
		return GarageRequests.BuyPart(services, player, data, carIndex, slotId)
	end)
	bind(garage, "RequestBuyCar", function(player, data, carId)
		return GarageRequests.BuyCar(services, player, data, carId)
	end)
	bind(garage, "RequestUpgradeGarage", function(player, data)
		return GarageRequests.UpgradeGarage(services, player, data)
	end)
	bind(garage, "RequestSellLoosePart", function(player, data, uid)
		return GarageRequests.SellLoosePart(services, player, data, uid)
	end)
	bind(garage, "RequestInstallLoosePart", function(player, data, uid, carIndex)
		return GarageRequests.InstallLoosePart(services, player, data, uid, carIndex)
	end)

	Remotes.Get("GetSnapshot").OnServerInvoke = function(player)
		local data = services.DataService:Wait(player, 20)
		if not data then
			return nil
		end
		return Snapshot.Build(player, data, {
			rate = services.EconomyService:GetRate(player, data),
			passes = services.MonetizationService:GetOwnership(player),
		})
	end
end

return RequestRouter
