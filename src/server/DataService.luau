--!strict
-- DataService.luau
-- Persistenz via DataStoreService. Key: city_v1_<UserId>.
-- Gespeichert: cash, buildings = {{id, cellX, cellZ, rot}}, dataVersion.
-- Einwohner/Einkommen werden beim Laden aus den Gebaeuden neu berechnet.
-- Alle Zugriffe in pcall mit einem Retry.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiniCity")
local Config = require(Shared:WaitForChild("Config"))

local PlotService = require(script.Parent.PlotService)
local PlacementService = require(script.Parent.PlacementService)
local EconomyService = require(script.Parent.EconomyService)

local DataService = {}

local store = DataStoreService:GetDataStore(Config.DataStoreName)

local function keyFor(userId: number): string
	return Config.DataKeyPrefix .. userId
end

-- pcall mit genau einem Retry
local function withRetry(fn): (boolean, any)
	local ok, result = pcall(fn)
	if ok then
		return true, result
	end
	task.wait(1)
	ok, result = pcall(fn)
	return ok, result
end

-- ----------------------------------------------------------------------------
-- Laden
-- ----------------------------------------------------------------------------

-- Laedt die gespeicherte Stadt in den (frisch zugewiesenen) Plot-State.
function DataService.load(player: Player)
	local plot = PlotService.getPlotByOwner(player.UserId)
	if not plot or not plot.state then
		return
	end
	local state = plot.state

	local ok, data = withRetry(function()
		return store:GetAsync(keyFor(player.UserId))
	end)

	if not ok then
		warn("[MiniCity] Laden fehlgeschlagen fuer " .. player.Name .. " - starte mit leerer Stadt")
		EconomyService.refresh(player.UserId)
		return
	end

	if type(data) == "table" and type(data.buildings) == "table" then
		state.cash = tonumber(data.cash) or Config.StartingCash
		for _, b in data.buildings do
			if type(b) == "table" and type(b.id) == "string" then
				PlacementService.loadBuilding(plot, state, b.id, tonumber(b.cellX) or 0, tonumber(b.cellZ) or 0, tonumber(b.rot) or 0)
			end
		end
	end

	EconomyService.refresh(player.UserId)
end

-- ----------------------------------------------------------------------------
-- Speichern
-- ----------------------------------------------------------------------------

local function buildPayload(state)
	local buildings = {}
	for _, b in state.buildings do
		table.insert(buildings, { id = b.id, cellX = b.cellX, cellZ = b.cellZ, rot = b.rot })
	end
	return {
		cash = math.floor(state.cash),
		buildings = buildings,
		dataVersion = Config.DataVersion,
	}
end

function DataService.save(player: Player): boolean
	local state = PlotService.getState(player.UserId)
	if not state then
		return false
	end
	local payload = buildPayload(state)
	local ok = withRetry(function()
		store:SetAsync(keyFor(player.UserId), payload)
		return true
	end)
	if not ok then
		warn("[MiniCity] Speichern fehlgeschlagen fuer " .. player.Name)
	end
	return ok
end

function DataService.saveAll()
	for _, player in game:GetService("Players"):GetPlayers() do
		DataService.save(player)
	end
end

return DataService
