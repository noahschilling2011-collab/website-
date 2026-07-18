--!strict
-- PlotService.luau
-- Erzeugt die 6 Plots, weist sie bei Join zu, gibt sie bei Leave frei und
-- haelt den kompletten Stadt-Zustand (CityState) je Plot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiniCity")
local Config = require(Shared:WaitForChild("Config"))

local PlotService = {}

export type CityState = {
	ownerUserId: number,
	cash: number,
	buildings: { [string]: any }, -- guid -> {id, cellX, cellZ, rot, cells, isRoad, model}
	occupancy: { [string]: string }, -- "x_z" -> guid
	roadCells: { [string]: boolean }, -- "x_z" -> true
	population: number,
	incomePerTick: number,
	unlockedItems: { string },
	saveBlocked: boolean, -- true, wenn das Laden fehlschlug: dann nie speichern
}

type Plot = {
	index: number,
	center: Vector3,
	plate: Part,
	buildingsFolder: Folder,
	signLabel: TextLabel,
	ownerUserId: number, -- 0 = frei
	state: CityState?,
}

local plots: { Plot } = {}
local playerToPlot: { [number]: number } = {} -- userId -> plot index

local plotsFolder: Folder

-- ----------------------------------------------------------------------------
-- Welt aufbauen
-- ----------------------------------------------------------------------------

local function cellKey(x: number, z: number): string
	return x .. "_" .. z
end
PlotService.cellKey = cellKey

local function plotCenter(index: number): Vector3
	local col = (index - 1) % Config.PlotColumns
	local row = (index - 1) // Config.PlotColumns
	local spacing = Config.PlotSize + Config.PlotGap
	return Vector3.new(col * spacing, 0, row * spacing)
end

function PlotService.init()
	plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = workspace

	-- Grosse Bodenflaeche unter allen Plots
	local spacing = Config.PlotSize + Config.PlotGap
	local totalW = Config.PlotColumns * spacing
	local rows = math.ceil(Config.PlotCount / Config.PlotColumns)
	local totalD = rows * spacing
	local ground = Instance.new("Part")
	ground.Name = "Ground"
	ground.Anchored = true
	ground.Size = Vector3.new(totalW + 60, 1, totalD + 60)
	ground.Position = Vector3.new((totalW - spacing) / 2, -0.5, (totalD - spacing) / 2)
	ground.Color = Color3.fromRGB(90, 120, 80)
	ground.Material = Enum.Material.Grass
	ground.TopSurface = Enum.SurfaceType.Smooth
	ground.Parent = plotsFolder

	for i = 1, Config.PlotCount do
		local center = plotCenter(i)
		local plate = Instance.new("Part")
		plate.Name = "PlotPlate"
		plate.Anchored = true
		plate.Size = Vector3.new(Config.PlotSize, Config.PlotSurfaceY, Config.PlotSize)
		plate.Position = Vector3.new(center.X, Config.PlotSurfaceY / 2, center.Z)
		plate.Color = Color3.fromRGB(120, 125, 120)
		plate.Material = Enum.Material.Concrete
		plate.TopSurface = Enum.SurfaceType.Smooth
		plate:SetAttribute("PlotIndex", i)
		plate:SetAttribute("OwnerUserId", 0)
		plate.Parent = plotsFolder

		-- Umrandung
		local border = Instance.new("SelectionBox")
		border.Adornee = plate
		border.Color3 = Color3.fromRGB(255, 220, 120)
		border.LineThickness = 0.3
		border.Transparency = 0.2
		border.Parent = plate

		-- Namensschild
		local signPart = Instance.new("Part")
		signPart.Name = "PlotSign"
		signPart.Anchored = true
		signPart.Size = Vector3.new(6, 3, 1)
		signPart.Position = Vector3.new(center.X, 2, center.Z - Config.PlotSize / 2 - 1)
		signPart.Color = Color3.fromRGB(60, 60, 70)
		signPart.Parent = plotsFolder
		local gui = Instance.new("BillboardGui")
		gui.Name = "Label"
		gui.Size = UDim2.fromScale(3, 1.2)
		gui.StudsOffset = Vector3.new(0, 3, 0)
		gui.AlwaysOnTop = true
		gui.Parent = signPart
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextStrokeTransparency = 0.4
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.Text = "Freier Plot " .. i
		label.Parent = gui

		local folder = Instance.new("Folder")
		folder.Name = "Buildings_" .. i
		folder.Parent = plotsFolder

		plots[i] = {
			index = i,
			center = center,
			plate = plate,
			buildingsFolder = folder,
			signLabel = label,
			ownerUserId = 0,
			state = nil,
		}
	end
end

-- ----------------------------------------------------------------------------
-- Zugriff
-- ----------------------------------------------------------------------------

function PlotService.getPlotByOwner(userId: number): Plot?
	local idx = playerToPlot[userId]
	if idx then
		return plots[idx]
	end
	return nil
end

function PlotService.getState(userId: number): CityState?
	local plot = PlotService.getPlotByOwner(userId)
	return plot and plot.state or nil
end

function PlotService.getCornerXZ(plot: Plot): (number, number)
	return plot.center.X - Config.PlotSize / 2, plot.center.Z - Config.PlotSize / 2
end

-- Weltmittelpunkt eines Footprints (Boden) auf Basis Eck-Zelle + Dimensionen.
function PlotService.cellsToWorldCenter(plot: Plot, cellX: number, cellZ: number, w: number, d: number): Vector3
	local cornerX, cornerZ = PlotService.getCornerXZ(plot)
	local x = cornerX + (cellX + w / 2) * Config.CellSize
	local z = cornerZ + (cellZ + d / 2) * Config.CellSize
	return Vector3.new(x, Config.PlotSurfaceY, z)
end

-- ----------------------------------------------------------------------------
-- Zuweisung / Freigabe
-- ----------------------------------------------------------------------------

function PlotService.assign(player: Player): Plot?
	for _, plot in plots do
		if plot.ownerUserId == 0 then
			plot.ownerUserId = player.UserId
			playerToPlot[player.UserId] = plot.index
			plot.plate:SetAttribute("OwnerUserId", player.UserId)
			plot.state = {
				ownerUserId = player.UserId,
				cash = Config.StartingCash,
				buildings = {},
				occupancy = {},
				roadCells = {},
				population = 0,
				incomePerTick = 0,
				unlockedItems = {},
				saveBlocked = false,
			}
			plot.signLabel.Text = player.Name .. "s Stadt"
			return plot
		end
	end
	return nil
end

function PlotService.release(player: Player)
	local plot = PlotService.getPlotByOwner(player.UserId)
	if not plot then
		return
	end
	-- Alle Gebaeude-Modelle entfernen (Plot leeren)
	plot.buildingsFolder:ClearAllChildren()
	plot.ownerUserId = 0
	plot.state = nil
	plot.plate:SetAttribute("OwnerUserId", 0)
	playerToPlot[player.UserId] = nil
	plot.signLabel.Text = "Freier Plot " .. plot.index
end

function PlotService.spawnPlayer(player: Player)
	local plot = PlotService.getPlotByOwner(player.UserId)
	if not plot then
		return
	end
	local char = player.Character or player.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if hrp then
		hrp.CFrame = CFrame.new(plot.center.X, Config.PlotSurfaceY + 6, plot.center.Z)
	end
end

return PlotService
