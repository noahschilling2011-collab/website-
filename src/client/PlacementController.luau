--!strict
-- PlacementController.luau
-- Ghost-Preview folgt Maus/Touch (gruen = gueltig, rot = ungueltig),
-- R = 90 Grad drehen, Klick/Tap = platzieren. Abriss-Modus: eigenes Gebaeude
-- anklicken -> Server-Abriss. Der Client schickt nur Zell-Koordinaten.

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

local PlacementController = {}
PlacementController.__index = PlacementController

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

	self.ghostFolder = Instance.new("Folder")
	self.ghostFolder.Name = "MiniCityGhost"
	self.ghostFolder.Parent = workspace

	-- Plate-Raycast-Filter (nur eigene/fremde Plot-Platten)
	self.plotsFolder = workspace:WaitForChild("Plots")

	RunService.RenderStepped:Connect(function()
		self:onRender()
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		self:onInput(input, gameProcessed)
	end)

	return self
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
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			if d.Name ~= "Anchor" then
				d.Transparency = 0.5
				table.insert(self.ghostParts, d)
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

-- ----------------------------------------------------------------------------
-- Raycast-Helfer
-- ----------------------------------------------------------------------------

-- Sucht die Plot-Platte unter dem Zeiger. Gibt (plate, worldPosition) zurueck.
function PlacementController:raycastPlate(): (BasePart?, Vector3?)
	local plates = {}
	for _, c in self.plotsFolder:GetChildren() do
		if c.Name == "PlotPlate" then
			table.insert(plates, c)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = plates
	local ray = mouse.UnitRay
	local result = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
	if result then
		return result.Instance, result.Position
	end
	return nil, nil
end

-- Berechnet die Eck-Zelle aus einer Weltposition auf der eigenen Platte.
function PlacementController:cellFromWorld(plate: BasePart, worldPos: Vector3, w: number, d: number): (number, number)
	local cornerX = plate.Position.X - Config.PlotSize / 2
	local cornerZ = plate.Position.Z - Config.PlotSize / 2
	local rawX = (worldPos.X - cornerX) / Config.CellSize
	local rawZ = (worldPos.Z - cornerZ) / Config.CellSize
	local cellX = math.clamp(math.floor(rawX - w / 2), 0, Config.GridCells - w)
	local cellZ = math.clamp(math.floor(rawZ - d / 2), 0, Config.GridCells - d)
	return cellX, cellZ
end

-- Lokale Ueberlappungspruefung gegen bereits gebaute Modelle auf dem eigenen Plot.
function PlacementController:cellsFreeLocally(plate: BasePart, cellX: number, cellZ: number, w: number, d: number): boolean
	local idx = plate:GetAttribute("PlotIndex")
	local folder = self.plotsFolder:FindFirstChild("Buildings_" .. tostring(idx))
	if not folder then
		return true
	end
	local cornerX = plate.Position.X - Config.PlotSize / 2
	local cornerZ = plate.Position.Z - Config.PlotSize / 2
	local centerX = cornerX + (cellX + w / 2) * Config.CellSize
	local centerZ = cornerZ + (cellZ + d / 2) * Config.CellSize
	local region = CFrame.new(centerX, Config.PlotSurfaceY + 10, centerZ)
	local size = Vector3.new(w * Config.CellSize - 0.4, 30, d * Config.CellSize - 0.4)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local parts = workspace:GetPartBoundsInBox(region, size, params)
	return #parts == 0
end

-- ----------------------------------------------------------------------------
-- Render / Ghost-Update
-- ----------------------------------------------------------------------------

function PlacementController:setGhostColor(color: Color3)
	for _, p in self.ghostParts do
		p.Color = color
	end
end

function PlacementController:onRender()
	if self.mode ~= "build" or not self.ghost or not self.itemId then
		return
	end
	local item = Items.get(self.itemId)
	local w, d = Items.footprintFor(item, self.rot)

	local plate, worldPos = self:raycastPlate()
	local ownerOk = plate ~= nil and plate:GetAttribute("OwnerUserId") == player.UserId
	if not plate or not worldPos or not ownerOk then
		-- Ghost verstecken, wenn nicht ueber eigenem Plot
		for _, p in self.ghostParts do
			p.Transparency = 1
		end
		self.lastCell = nil
		return
	end

	for _, p in self.ghostParts do
		p.Transparency = 0.5
	end

	local cellX, cellZ = self:cellFromWorld(plate, worldPos, w, d)
	self.lastCell = { x = cellX, z = cellZ }

	local cornerX = plate.Position.X - Config.PlotSize / 2
	local cornerZ = plate.Position.Z - Config.PlotSize / 2
	local centerX = cornerX + (cellX + w / 2) * Config.CellSize
	local centerZ = cornerZ + (cellZ + d / 2) * Config.CellSize
	self.ghost:PivotTo(CFrame.new(centerX, Config.PlotSurfaceY, centerZ) * CFrame.Angles(0, self.rot * math.pi / 2, 0))

	local free = self:cellsFreeLocally(plate, cellX, cellZ, w, d)
	self:setGhostColor(free and GHOST_GREEN or GHOST_RED)
end

-- ----------------------------------------------------------------------------
-- Eingabe
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
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local ownFolder = self.plotsFolder:FindFirstChild("Buildings_" .. tostring(self:ownPlotIndex()))
	if not ownFolder then
		return
	end
	params.FilterDescendantsInstances = { ownFolder }
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

function PlacementController:ownPlotIndex(): number?
	for _, c in self.plotsFolder:GetChildren() do
		if c.Name == "PlotPlate" and c:GetAttribute("OwnerUserId") == player.UserId then
			return c:GetAttribute("PlotIndex")
		end
	end
	return nil
end

function PlacementController:onInput(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.R and self.mode == "build" then
		self.rot = (self.rot + 1) % 4
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
