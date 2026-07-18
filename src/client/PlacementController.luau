--!strict
-- PlacementController.luau
-- Ghost-Preview folgt Maus/Touch (gruen = gueltig, rot = ungueltig),
-- R oder Drehen-Knopf = 90 Grad drehen, Klick/Tap = platzieren.
-- Abriss-Modus: eigenes Gebaeude anklicken -> Server-Abriss.
--
-- Der Client schickt nur Zell-Koordinaten. Fuer die Ghost-Farbe spiegelt er die
-- Server-Regeln (Belegung, Strassenanschluss, Geld) lokal aus den Zell-Attributen
-- der replizierten Gebaeude-Modelle — die Autoritaet bleibt beim Server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("MiniCity")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local placeItem = Remotes.PlaceItem()
local demolishItem = Remotes.DemolishItem()

local GHOST_GREEN = Color3.fromRGB(80, 220, 90)
local GHOST_RED = Color3.fromRGB(220, 80, 80)

local ORTHO_DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local PlacementController = {}
PlacementController.__index = PlacementController

local function cellKey(x: number, z: number): string
	return x .. "_" .. z
end

-- ----------------------------------------------------------------------------
-- Konstruktion
-- ----------------------------------------------------------------------------

function PlacementController.create(deps)
	local self = setmetatable({}, PlacementController)
	self.hud = deps.hud
	self.menu = deps.menu

	self.mode = "none" -- "none" | "build" | "demolish"
	self.itemId = nil :: string?
	self.rot = 0
	self.ghost = nil :: Model?
	self.ghostParts = {} :: { BasePart }
	self.lastCell = nil :: { x: number, z: number }?
	self.lastState = nil -- letzter StateSync (fuer den Geld-Check der Vorschau)

	-- Lokaler Spiegel der Belegungs-/Strassen-Map des eigenen Plots
	self.occ = {} :: { [string]: boolean }
	self.road = {} :: { [string]: boolean }
	self.gridDirty = true
	self.watchedFolder = nil :: Folder?

	self.ghostFolder = Instance.new("Folder")
	self.ghostFolder.Name = "MiniCityGhost"
	self.ghostFolder.Parent = workspace

	-- Plots existieren ab Server-Start; einmalig cachen
	self.plotsFolder = workspace:WaitForChild("Plots")
	self.plates = {} :: { BasePart }
	for _, child in self.plotsFolder:GetChildren() do
		if child.Name == "PlotPlate" and child:IsA("BasePart") then
			table.insert(self.plates, child)
		end
	end

	RunService.RenderStepped:Connect(function()
		self:onRender()
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		self:onInput(input, gameProcessed)
	end)

	return self
end

-- ----------------------------------------------------------------------------
-- Eigener Plot / Grid-Spiegel
-- ----------------------------------------------------------------------------

function PlacementController:ownPlate(): BasePart?
	for _, plate in self.plates do
		if plate:GetAttribute("OwnerUserId") == player.UserId then
			return plate
		end
	end
	return nil
end

function PlacementController:ownBuildingsFolder(): Folder?
	local plate = self:ownPlate()
	if not plate then
		return nil
	end
	local idx = plate:GetAttribute("PlotIndex")
	local folder = self.plotsFolder:FindFirstChild("Buildings_" .. tostring(idx))
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

function PlacementController:watchFolder(folder: Folder)
	if self.watchedFolder == folder then
		return
	end
	self.watchedFolder = folder
	self.gridDirty = true
	folder.ChildAdded:Connect(function()
		self.gridDirty = true
	end)
	folder.ChildRemoved:Connect(function()
		self.gridDirty = true
	end)
end

-- Baut occ/road aus den Zell-Attributen der replizierten Modelle neu auf.
function PlacementController:refreshGrid()
	local occ = {}
	local road = {}
	local folder = self.watchedFolder
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") then
				local id = m:GetAttribute("ItemId")
				local cx = m:GetAttribute("CellX")
				local cz = m:GetAttribute("CellZ")
				local rot = m:GetAttribute("Rot")
				local item = nil
				if type(id) == "string" then
					item = Items.get(id)
				end
				if item and type(cx) == "number" and type(cz) == "number" and type(rot) == "number" then
					local w, d = Items.footprintFor(item, rot)
					local isRoad = m:GetAttribute("IsRoad") == true
					for i = 0, w - 1 do
						for j = 0, d - 1 do
							local key = cellKey(cx + i, cz + j)
							occ[key] = true
							if isRoad then
								road[key] = true
							end
						end
					end
				end
			end
		end
	end
	self.occ = occ
	self.road = road
	self.gridDirty = false
end

-- Spiegelt die Server-Validierung fuer die Ghost-Farbe: Zellen frei,
-- Strassenanschluss (ausser bei Strassen/Autobahn), genug Geld.
function PlacementController:isPlacementValid(item, cellX: number, cellZ: number, w: number, d: number): boolean
	for i = 0, w - 1 do
		for j = 0, d - 1 do
			if self.occ[cellKey(cellX + i, cellZ + j)] then
				return false
			end
		end
	end
	if not item.isRoad then
		local touchesRoad = false
		for i = 0, w - 1 do
			if touchesRoad then
				break
			end
			for j = 0, d - 1 do
				if touchesRoad then
					break
				end
				for _, dir in ORTHO_DIRS do
					if self.road[cellKey(cellX + i + dir[1], cellZ + j + dir[2])] then
						touchesRoad = true
						break
					end
				end
			end
		end
		if not touchesRoad then
			return false
		end
	end
	if self.lastState and self.lastState.cash < item.price then
		return false
	end
	return true
end

-- ----------------------------------------------------------------------------
-- Modus-Wechsel
-- ----------------------------------------------------------------------------

function PlacementController:clearGhost()
	if self.ghost then
		self.ghost:Destroy()
		self.ghost = nil
	end
	self.ghostParts = {}
	self.lastCell = nil
end

function PlacementController:setItem(itemId: string)
	local item = Items.get(itemId)
	if not item then
		return
	end
	self.mode = "build"
	self.itemId = itemId
	self:clearGhost()

	local model = item.build()
	model.Name = "Ghost"
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			if descendant.Name ~= "Anchor" then
				descendant.Transparency = 0.5
				table.insert(self.ghostParts, descendant)
			end
		end
	end
	model.Parent = self.ghostFolder
	self.ghost = model

	self.menu:setActive("build", itemId)
end

function PlacementController:setDemolish()
	self.mode = "demolish"
	self.itemId = nil
	self:clearGhost()
	self.menu:setActive("demolish", nil)
end

function PlacementController:cancel()
	self.mode = "none"
	self.itemId = nil
	self:clearGhost()
	self.menu:setActive("none", nil)
end

function PlacementController:rotate()
	if self.mode == "build" then
		self.rot = (self.rot + 1) % 4
	end
end

-- Wird von Main.client bei jedem StateSync aufgerufen.
function PlacementController:onState(state)
	self.lastState = state
	-- Faellt die Einwohnerzahl (Abriss), kann das gewaehlte Item wieder gesperrt sein
	if self.mode == "build" and self.itemId then
		local stillUnlocked = false
		for _, id in state.unlockedItems or {} do
			if id == self.itemId then
				stillUnlocked = true
				break
			end
		end
		if not stillUnlocked then
			self:cancel()
		end
	end
end

-- ----------------------------------------------------------------------------
-- Raycast / Zell-Berechnung
-- ----------------------------------------------------------------------------

-- Plot-Platte unter dem Zeiger. Gibt (plate, worldPosition) zurueck.
function PlacementController:raycastPlate(): (BasePart?, Vector3?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = self.plates
	local ray = mouse.UnitRay
	local result = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
	if result then
		return result.Instance :: BasePart, result.Position
	end
	return nil, nil
end

-- Eck-Zelle aus einer Weltposition auf der eigenen Platte (Footprint zentriert).
function PlacementController:cellFromWorld(plate: BasePart, worldPos: Vector3, w: number, d: number): (number, number)
	local cornerX = plate.Position.X - Config.PlotSize / 2
	local cornerZ = plate.Position.Z - Config.PlotSize / 2
	local rawX = (worldPos.X - cornerX) / Config.CellSize
	local rawZ = (worldPos.Z - cornerZ) / Config.CellSize
	local cellX = math.clamp(math.floor(rawX - w / 2), 0, Config.GridCells - w)
	local cellZ = math.clamp(math.floor(rawZ - d / 2), 0, Config.GridCells - d)
	return cellX, cellZ
end

-- ----------------------------------------------------------------------------
-- Render / Ghost-Update
-- ----------------------------------------------------------------------------

function PlacementController:setGhostColor(color: Color3)
	for _, part in self.ghostParts do
		part.Color = color
	end
end

function PlacementController:onRender()
	if self.mode ~= "build" or not self.ghost or not self.itemId then
		return
	end
	local item = Items.get(self.itemId)
	local w, d = Items.footprintFor(item, self.rot)

	local plate, worldPos = self:raycastPlate()
	local ownPlate = plate ~= nil and plate:GetAttribute("OwnerUserId") == player.UserId
	if not plate or not worldPos or not ownPlate then
		-- Nicht ueber dem eigenen Plot: Ghost verstecken, kein Platzierungsziel
		for _, part in self.ghostParts do
			part.Transparency = 1
		end
		self.lastCell = nil
		return
	end

	local folder = self:ownBuildingsFolder()
	if folder then
		self:watchFolder(folder)
	end
	if self.gridDirty then
		self:refreshGrid()
	end

	for _, part in self.ghostParts do
		part.Transparency = 0.5
	end

	local cellX, cellZ = self:cellFromWorld(plate, worldPos, w, d)
	self.lastCell = { x = cellX, z = cellZ }

	local cornerX = plate.Position.X - Config.PlotSize / 2
	local cornerZ = plate.Position.Z - Config.PlotSize / 2
	local centerX = cornerX + (cellX + w / 2) * Config.CellSize
	local centerZ = cornerZ + (cellZ + d / 2) * Config.CellSize
	self.ghost:PivotTo(CFrame.new(centerX, Config.PlotSurfaceY, centerZ) * CFrame.Angles(0, self.rot * math.pi / 2, 0))

	local valid = self:isPlacementValid(item, cellX, cellZ, w, d)
	self:setGhostColor(valid and GHOST_GREEN or GHOST_RED)
end

-- ----------------------------------------------------------------------------
-- Aktionen
-- ----------------------------------------------------------------------------

function PlacementController:tryPlace()
	if not self.itemId or not self.lastCell then
		return
	end
	local ok, err = placeItem:InvokeServer(self.itemId, self.lastCell.x, self.lastCell.z, self.rot)
	if not ok then
		self.hud:toast(err or "Platzieren fehlgeschlagen", Color3.fromRGB(160, 60, 60))
	end
end

function PlacementController:tryDemolish()
	local folder = self:ownBuildingsFolder()
	if not folder then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local ray = mouse.UnitRay
	local result = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
	if not result then
		return
	end
	local model = result.Instance:FindFirstAncestorWhichIsA("Model")
	if not model then
		return
	end
	local guid = model:GetAttribute("BuildingGuid")
	if type(guid) ~= "string" then
		return
	end
	local ok, err = demolishItem:InvokeServer(guid)
	if not ok then
		self.hud:toast(err or "Abriss fehlgeschlagen", Color3.fromRGB(160, 60, 60))
	end
end

-- ----------------------------------------------------------------------------
-- Eingabe
-- ----------------------------------------------------------------------------

function PlacementController:onInput(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.R then
		self:rotate()
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if self.mode == "build" then
			self:tryPlace()
		elseif self.mode == "demolish" then
			self:tryDemolish()
		end
	end
end

return PlacementController
