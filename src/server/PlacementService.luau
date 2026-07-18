--!strict
-- PlacementService.luau
-- Server-autoritatives Platzieren und Abreissen. Validiert JEDE Aktion:
-- eigener Plot, Zellen frei, genug Geld, Item freigeschaltet, innerhalb der Grenzen,
-- Strassenanschluss. Rate-Limit 5 Aktionen/s. Client liefert nur Zell-Koordinaten;
-- der Server clamped und rechnet die Weltposition selbst.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiniCity")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))

local PlotService = require(script.Parent.PlotService)
local UnlockService = require(script.Parent.UnlockService)
local EconomyService = require(script.Parent.EconomyService)

local PlacementService = {}

local cellKey = PlotService.cellKey

-- ----------------------------------------------------------------------------
-- Rate-Limit (Token pro Spieler in gleitendem 1s-Fenster)
-- ----------------------------------------------------------------------------

local actionTimes: { [number]: { number } } = {}

local function allowAction(userId: number): boolean
	local now = os.clock()
	local times = actionTimes[userId]
	if not times then
		times = {}
		actionTimes[userId] = times
	end
	-- alte Eintraege entfernen
	local kept = {}
	for _, t in times do
		if now - t < 1 then
			table.insert(kept, t)
		end
	end
	actionTimes[userId] = kept
	if #kept >= Config.RateLimit then
		return false
	end
	table.insert(kept, now)
	return true
end

function PlacementService.clearPlayer(userId: number)
	actionTimes[userId] = nil
end

-- ----------------------------------------------------------------------------
-- Hilfsfunktionen
-- ----------------------------------------------------------------------------

-- Belegte Zellschluessel fuer einen Footprint an (cellX, cellZ) mit Dimensionen w,d.
local function footprintCells(cellX: number, cellZ: number, w: number, d: number): { string }
	local cells = {}
	for i = 0, w - 1 do
		for j = 0, d - 1 do
			table.insert(cells, cellKey(cellX + i, cellZ + j))
		end
	end
	return cells
end

-- Hat mindestens eine Footprint-Zelle einen orthogonal angrenzenden Strassen-Nachbarn?
local function hasRoadAdjacency(state, cellX: number, cellZ: number, w: number, d: number): boolean
	local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
	for i = 0, w - 1 do
		for j = 0, d - 1 do
			local cx, cz = cellX + i, cellZ + j
			for _, dir in dirs do
				local nx, nz = cx + dir[1], cz + dir[2]
				if state.roadCells[cellKey(nx, nz)] then
					return true
				end
			end
		end
	end
	return false
end

-- ----------------------------------------------------------------------------
-- Kern-Platzierung
-- ----------------------------------------------------------------------------

type PlaceOpts = {
	checkUnlock: boolean,
	checkCash: boolean,
	checkRoad: boolean,
	deduct: boolean,
}

local function placeInternal(plot, state, itemId: string, cellX: number, cellZ: number, rot: number, opts: PlaceOpts): (boolean, string?)
	local item = Items.get(itemId)
	if not item then
		return false, "Unbekanntes Item"
	end

	rot = math.floor(rot) % 4
	local w, d = Items.footprintFor(item, rot)

	if w > Config.GridCells or d > Config.GridCells then
		return false, "Passt nicht in den Plot"
	end

	-- Server clamped die Eck-Zelle, damit der Footprint immer in den Grenzen liegt
	cellX = math.clamp(math.floor(cellX), 0, Config.GridCells - w)
	cellZ = math.clamp(math.floor(cellZ), 0, Config.GridCells - d)

	local cells = footprintCells(cellX, cellZ, w, d)

	-- Zellen frei?
	for _, key in cells do
		if state.occupancy[key] then
			return false, "Zelle belegt"
		end
	end

	-- Freigeschaltet?
	if opts.checkUnlock and not UnlockService.isUnlocked(itemId, state.population) then
		return false, "Item nicht freigeschaltet"
	end

	-- Genug Geld?
	if opts.checkCash and state.cash < item.price then
		return false, "Zu wenig Geld"
	end

	-- Strassenanschluss (nur Nicht-Strassen)?
	if opts.checkRoad and not item.isRoad and not hasRoadAdjacency(state, cellX, cellZ, w, d) then
		return false, "Kein Strassenanschluss"
	end

	-- Model bauen und platzieren. Attribute vor dem Parenting setzen, damit der
	-- Client sie ab ChildAdded vollstaendig sieht (Grid-Spiegel der Ghost-Vorschau).
	local guid = HttpService:GenerateGUID(false)
	local model = item.build()
	model:SetAttribute("BuildingGuid", guid)
	model:SetAttribute("ItemId", itemId)
	model:SetAttribute("OwnerUserId", state.ownerUserId)
	model:SetAttribute("CellX", cellX)
	model:SetAttribute("CellZ", cellZ)
	model:SetAttribute("Rot", rot)
	model:SetAttribute("IsRoad", item.isRoad)

	local center = PlotService.cellsToWorldCenter(plot, cellX, cellZ, w, d)
	model:PivotTo(CFrame.new(center) * CFrame.Angles(0, rot * math.pi / 2, 0))
	model.Parent = plot.buildingsFolder

	-- Zustand aktualisieren
	for _, key in cells do
		state.occupancy[key] = guid
		if item.isRoad then
			state.roadCells[key] = true
		end
	end
	state.buildings[guid] = {
		id = itemId,
		cellX = cellX,
		cellZ = cellZ,
		rot = rot,
		cells = cells,
		isRoad = item.isRoad,
		model = model,
	}

	if opts.deduct then
		state.cash -= item.price
	end

	return true
end

-- ----------------------------------------------------------------------------
-- Oeffentliche Handler
-- ----------------------------------------------------------------------------

-- Echte endliche Zahl (NaN/inf wuerden CFrame und den DataStore-Save korrumpieren)
local function isFiniteNumber(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function PlacementService.handlePlace(player: Player, itemId: any, cellX: any, cellZ: any, rot: any): (boolean, string?)
	if type(itemId) ~= "string" or not isFiniteNumber(cellX) or not isFiniteNumber(cellZ) or not isFiniteNumber(rot) then
		return false, "Ungueltige Eingabe"
	end
	if not allowAction(player.UserId) then
		return false, "Zu schnell"
	end
	local plot = PlotService.getPlotByOwner(player.UserId)
	if not plot or not plot.state then
		return false, "Kein Plot"
	end
	local ok, err = placeInternal(plot, plot.state, itemId, cellX, cellZ, rot, {
		checkUnlock = true,
		checkCash = true,
		checkRoad = true,
		deduct = true,
	})
	if ok then
		EconomyService.refresh(player.UserId)
	end
	return ok, err
end

function PlacementService.handleDemolish(player: Player, guid: any): (boolean, string?)
	if type(guid) ~= "string" then
		return false, "Ungueltige Eingabe"
	end
	if not allowAction(player.UserId) then
		return false, "Zu schnell"
	end
	local plot = PlotService.getPlotByOwner(player.UserId)
	if not plot or not plot.state then
		return false, "Kein Plot"
	end
	local state = plot.state
	local building = state.buildings[guid]
	if not building then
		return false, "Gebaeude nicht gefunden"
	end

	local item = Items.get(building.id)
	if item then
		state.cash += math.floor(item.price * Config.RefundRatio)
	end

	for _, key in building.cells do
		state.occupancy[key] = nil
		if building.isRoad then
			state.roadCells[key] = nil
		end
	end
	if building.model then
		building.model:Destroy()
	end
	state.buildings[guid] = nil

	EconomyService.refresh(player.UserId)
	return true
end

-- Vertrauenswuerdiges Platzieren beim Laden gespeicherter Staedte (keine Checks/Abzug).
function PlacementService.loadBuilding(plot, state, itemId: string, cellX: number, cellZ: number, rot: number): boolean
	local ok = placeInternal(plot, state, itemId, cellX, cellZ, rot, {
		checkUnlock = false,
		checkCash = false,
		checkRoad = false,
		deduct = false,
	})
	return ok
end

return PlacementService
