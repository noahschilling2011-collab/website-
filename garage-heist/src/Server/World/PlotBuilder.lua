--[[
	PlotBuilder
	Baut eine Garage aus Parts. Alles, was hier entsteht, hat eine Funktion:
	Tor (geht auf), Kasse (Cash abholen), Werkbank (Menue), Abgabe-Pad
	(geklaute Teile abliefern), Schild (Name + Wert). Keine Deko ohne Wirkung.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local PlotBuilder = {}

local WALL_HEIGHT = Config.PLOT_HEIGHT
local WALL_THICK = 2
local DOOR_WIDTH = 26
local DOOR_HEIGHT = 13

local function makePart(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = props.Material or Enum.Material.Concrete
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Color = props.Color or Color3.fromRGB(120, 120, 125)
	p.Name = props.Name or "Part"
	if props.CanCollide ~= nil then
		p.CanCollide = props.CanCollide
	end
	if props.Transparency then
		p.Transparency = props.Transparency
	end
	p.Parent = props.Parent
	return p
end

local function makeSign(parent, cframe, size)
	local board = makePart({
		Name = "Sign",
		Size = size,
		CFrame = cframe,
		Color = Color3.fromRGB(30, 30, 34),
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(600, 200)
	gui.LightInfluence = 0
	gui.Parent = board

	local function label(name, posScale, sizeScale, textSize, color)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0, posScale)
		l.Size = UDim2.fromScale(1, sizeScale)
		l.Font = Enum.Font.GothamBold
		l.TextScaled = true
		l.TextColor3 = color
		l.Text = ""
		l.Parent = gui
		return l
	end

	return {
		board = board,
		name = label("NameLabel", 0.02, 0.42, 40, Color3.fromRGB(255, 255, 255)),
		value = label("ValueLabel", 0.46, 0.28, 28, Color3.fromRGB(120, 230, 160)),
		rate = label("RateLabel", 0.72, 0.26, 24, Color3.fromRGB(200, 200, 210)),
	}
end

local function makePad(parent, cframe, size, color, name, promptText, promptObject)
	local pad = makePart({
		Name = name,
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = parent,
	})
	if promptText then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = promptText
		prompt.ObjectText = promptObject or ""
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = pad
	end
	return pad
end

-- Weltposition eines Plots. Reihe 0 schaut nach +Z, Reihe 1 nach -Z.
function PlotBuilder.GetPlotCFrame(index: number): CFrame
	local zeroBased = index - 1
	local row = math.floor(zeroBased / Config.PLOTS_PER_ROW)
	local column = zeroBased % Config.PLOTS_PER_ROW
	local totalWidth = Config.PLOTS_PER_ROW * (Config.PLOT_WIDTH + Config.PLOT_GAP)
	local x = -totalWidth / 2 + (Config.PLOT_WIDTH + Config.PLOT_GAP) * (column + 0.5)
	local z = (row == 0) and -(Config.ROW_GAP / 2 + Config.PLOT_DEPTH / 2)
		or (Config.ROW_GAP / 2 + Config.PLOT_DEPTH / 2)
	local rotation = (row == 0) and CFrame.identity or CFrame.Angles(0, math.pi, 0)
	return CFrame.new(x, Config.BASE_HEIGHT, z) * rotation
end

function PlotBuilder.Build(index: number, parent: Instance)
	local base = PlotBuilder.GetPlotCFrame(index)
	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("PlotIndex", index)
	model.Parent = parent

	local halfWidth = Config.PLOT_WIDTH / 2
	local halfDepth = Config.PLOT_DEPTH / 2

	local floor = makePart({
		Name = "Floor",
		Size = Vector3.new(Config.PLOT_WIDTH, 1, Config.PLOT_DEPTH),
		CFrame = base * CFrame.new(0, -0.5, 0),
		Color = Color3.fromRGB(70, 70, 76),
		Material = Enum.Material.Slate,
		Parent = model,
	})
	model.PrimaryPart = floor

	makePart({
		Name = "BackWall",
		Size = Vector3.new(Config.PLOT_WIDTH, WALL_HEIGHT, WALL_THICK),
		CFrame = base * CFrame.new(0, WALL_HEIGHT / 2, -halfDepth),
		Parent = model,
	})
	for _, side in { -1, 1 } do
		makePart({
			Name = "SideWall",
			Size = Vector3.new(WALL_THICK, WALL_HEIGHT, Config.PLOT_DEPTH),
			CFrame = base * CFrame.new(side * halfWidth, WALL_HEIGHT / 2, 0),
			Parent = model,
		})
	end

	-- Front mit Toroeffnung: zwei Pfeiler plus Sturz.
	local pillarWidth = (Config.PLOT_WIDTH - DOOR_WIDTH) / 2
	for _, side in { -1, 1 } do
		makePart({
			Name = "FrontPillar",
			Size = Vector3.new(pillarWidth, WALL_HEIGHT, WALL_THICK),
			CFrame = base * CFrame.new(side * (halfWidth - pillarWidth / 2), WALL_HEIGHT / 2, halfDepth),
			Parent = model,
		})
	end
	makePart({
		Name = "Lintel",
		Size = Vector3.new(DOOR_WIDTH, WALL_HEIGHT - DOOR_HEIGHT, WALL_THICK),
		CFrame = base * CFrame.new(0, DOOR_HEIGHT + (WALL_HEIGHT - DOOR_HEIGHT) / 2, halfDepth),
		Parent = model,
	})

	local doorClosed = base * CFrame.new(0, DOOR_HEIGHT / 2, halfDepth)
	local door = makePart({
		Name = "Door",
		Size = Vector3.new(DOOR_WIDTH, DOOR_HEIGHT, 1),
		CFrame = doorClosed,
		Color = Color3.fromRGB(160, 90, 40),
		Material = Enum.Material.DiamondPlate,
		Parent = model,
	})
	-- Offen = zusammengerollt unter dem Sturz, nicht durchs Dach geschoben.
	local doorOpen = base * CFrame.new(0, DOOR_HEIGHT - 0.4, halfDepth)

	local sign = makeSign(model, base * CFrame.new(0, DOOR_HEIGHT + 2.4, halfDepth + 1.2), Vector3.new(24, 6, 0.4))

	local register = makePad(
		model,
		base * CFrame.new(-halfWidth + 5, 1.5, halfDepth - 6),
		Vector3.new(4, 3, 4),
		Color3.fromRGB(90, 220, 120),
		"CashRegister",
		"Kasse leeren",
		"Garagenkasse"
	)
	register.CanCollide = true

	local workbench = makePad(
		model,
		base * CFrame.new(halfWidth - 5, 1.5, halfDepth - 6),
		Vector3.new(4, 3, 6),
		Color3.fromRGB(230, 170, 60),
		"Workbench",
		"Werkstatt oeffnen",
		"Werkbank"
	)
	workbench.CanCollide = true
	workbench:SetAttribute("PlotIndex", index)
	register:SetAttribute("PlotIndex", index)

	local lootBay = makePad(
		model,
		base * CFrame.new(0, 0.15, halfDepth - 5),
		Vector3.new(12, 0.3, 6),
		Color3.fromRGB(80, 160, 255),
		"LootBay",
		nil,
		nil
	)

	local carPads = {}
	local padLocal = {
		CFrame.new(-11.5, 0, -13),
		CFrame.new(11.5, 0, -13),
		CFrame.new(-11.5, 0, 5),
		CFrame.new(11.5, 0, 5),
	}
	for i, offset in padLocal do
		local padCFrame = base * offset
		makePart({
			Name = "CarPad" .. i,
			Size = Vector3.new(8, 0.2, 14),
			CFrame = padCFrame * CFrame.new(0, 0.1, 0),
			Color = Color3.fromRGB(52, 52, 58),
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = model,
		})
		carPads[i] = padCFrame
	end

	return {
		index = index,
		model = model,
		cframe = base,
		floor = floor,
		door = door,
		doorClosedCFrame = doorClosed,
		doorOpenCFrame = doorOpen,
		doorIsOpen = false,
		sign = sign,
		register = register,
		workbench = workbench,
		lootBay = lootBay,
		carPads = carPads,
		spawnCFrame = base * CFrame.new(0, 3, halfDepth - 14),
	}
end

function PlotBuilder.SetDoor(plot, open: boolean)
	if plot.doorIsOpen == open then
		return
	end
	plot.doorIsOpen = open
	local goalCFrame = open and plot.doorOpenCFrame or plot.doorClosedCFrame
	local goalSize = open and Vector3.new(DOOR_WIDTH, 0.8, 1) or Vector3.new(DOOR_WIDTH, DOOR_HEIGHT, 1)
	local tween = TweenService:Create(
		plot.door,
		TweenInfo.new(0.9, Enum.EasingStyle.Quad),
		{ CFrame = goalCFrame, Size = goalSize }
	)
	tween:Play()
end

return PlotBuilder
