--[[
	Throttle
	Drosselung fuer JEDE Client->Server-Verbindung. Vorher lief nur ein Teil der
	Remotes durch den RequestRouter, der Rest hing ungebremst an OnServerEvent.

	Benutzung:
		Throttle.Connect("RequestCollect", 0.25, function(player) ... end)

	Der Handler wird nur aufgerufen, wenn der Spieler nicht zu schnell feuert.
	Zaehler werden beim Verlassen aufgeraeumt.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)

local Throttle = {}

Throttle.DEFAULT_COOLDOWN = 0.2

local stamps: { [number]: { [string]: number } } = {}

Players.PlayerRemoving:Connect(function(player)
	stamps[player.UserId] = nil
end)

-- true = zu schnell, Anfrage verwerfen.
function Throttle.Blocked(player: Player, key: string, cooldown: number?): boolean
	local now = os.clock()
	local perPlayer = stamps[player.UserId]
	if not perPlayer then
		perPlayer = {}
		stamps[player.UserId] = perPlayer
	end
	if now - (perPlayer[key] or 0) < (cooldown or Throttle.DEFAULT_COOLDOWN) then
		return true
	end
	perPlayer[key] = now
	return false
end

-- Bindet ein RemoteEvent samt Drosselung.
function Throttle.Connect(remoteName: string, cooldown: number?, handler)
	return Remotes.Get(remoteName).OnServerEvent:Connect(function(player, ...)
		if Throttle.Blocked(player, remoteName, cooldown) then
			return
		end
		handler(player, ...)
	end)
end

return Throttle
