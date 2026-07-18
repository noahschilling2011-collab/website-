-- Main.server.luau
-- Einstiegspunkt Server: initialisiert Plots, verdrahtet Remotes, verwaltet
-- Join/Leave, Persistenz-Autosave und den Einkommens-Tick.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiniCity")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local modules = script.Parent
local PlotService = require(modules.PlotService)
local PlacementService = require(modules.PlacementService)
local EconomyService = require(modules.EconomyService)
local DataService = require(modules.DataService)

-- Welt aufbauen
PlotService.init()
EconomyService.start()

-- Remotes verdrahten
local placeItem = Remotes.PlaceItem()
local demolishItem = Remotes.DemolishItem()

placeItem.OnServerInvoke = function(player, itemId, cellX, cellZ, rot)
	return PlacementService.handlePlace(player, itemId, cellX, cellZ, rot)
end

demolishItem.OnServerInvoke = function(player, guid)
	return PlacementService.handleDemolish(player, guid)
end

-- ----------------------------------------------------------------------------
-- Join / Leave
-- ----------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	EconomyService.setupLeaderstats(player)

	local plot = PlotService.assign(player)
	if not plot then
		warn("[MiniCity] Kein freier Plot fuer " .. player.Name)
		return
	end

	-- Character am eigenen Plot spawnen (auch bei Respawn)
	player.CharacterAdded:Connect(function()
		task.defer(function()
			PlotService.spawnPlayer(player)
		end)
	end)
	if player.Character then
		PlotService.spawnPlayer(player)
	end

	-- Gespeicherte Stadt laden (baut Gebaeude wieder auf + refresh)
	DataService.load(player)

	-- Sync-Burst nach dem Join: RemoteEvents puffern nicht — feuert der erste
	-- StateSync, bevor die Client-Skripte lauschen, waere die UI sonst bis zum
	-- naechsten Einkommens-Tick leer.
	task.spawn(function()
		for _ = 1, 6 do
			task.wait(1)
			if player.Parent == nil then
				return
			end
			EconomyService.sync(player.UserId)
		end
	end)
end

local function onPlayerRemoving(player: Player)
	-- Snapshot synchron ziehen und den Plot sofort freigeben; erst danach
	-- (yieldend) speichern. So kann ein schneller Rejoin nie mit einem noch
	-- belegten Plot oder einem halb freigegebenen Zustand kollidieren.
	local userId = player.UserId
	local payload = DataService.snapshot(player)
	PlotService.release(player)
	PlacementService.clearPlayer(userId)
	if payload then
		DataService.savePayload(userId, payload)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Falls Spieler bereits vor dem Skript da waren
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- ----------------------------------------------------------------------------
-- Autosave + Shutdown
-- ----------------------------------------------------------------------------

task.spawn(function()
	while true do
		task.wait(Config.SaveInterval)
		DataService.saveAll()
	end
end)

game:BindToClose(function()
	DataService.saveAll()
	task.wait(2)
end)
