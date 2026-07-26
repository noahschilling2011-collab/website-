--[[
	PlotBuilder (Visual-Rewrite)

	Gleiche oeffentliche API wie vorher:
		PlotBuilder.GetPlotCFrame(index) -> CFrame
		PlotBuilder.Build(index, parent) -> plot
		PlotBuilder.SetDoor(plot, open)
	NEU:
		PlotBuilder.ApplyLevel(plot, level)  -- Garagen-Stufe sichtbar machen

	Der zurueckgegebene Tisch enthaelt weiterhin exakt:
		index, model, cframe, floor, door, doorClosedCFrame, doorOpenCFrame,
		doorIsOpen, sign{board,name,value,rate}, strip, light, register,
		workbench, lootBay, carPads, spawnCFrame
	dazu neu: trim, ceilingLights, floorPaint, doorBar, levelLabel

	Designregel hier: die Garage ist ein Innenraum, kein Karton. Boden,
	Waende und Decke haben drei verschiedene Materialien, es gibt eine
	Lichtquelle im Raum, und der Blick faellt automatisch auf die drei
	Dinge, mit denen man interagiert (Kasse, Werkbank, Abgabe-Pad).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Audio = require(Shared.Audio)
local Config = require(Shared.Config)

local PlotBuilder = {}

local CLOSED_LIGHT = Color3.fromRGB(70, 150, 255)
local OPEN_LIGHT = Color3.fromRGB(255, 45, 85)

local WALL_HEIGHT = Config.PLOT_HEIGHT
local WALL_THICK = 2
local DOOR_WIDTH = 26
local DOOR_HEIGHT = 13
local SKYLIGHT_GAP = 16 -- offener Streifen in der Decke, damit die Kamera reinschaut

-- Farbwelt. Grau bleibt Grau, aber es sind drei klar getrennte Werte statt
-- fuenf, die man nicht auseinanderhalten kann.
local C = {
	floor = Color3.fromRGB(38, 40, 46),
	floorPaint = Color3.fromRGB(196, 200, 210),
	wallLow = Color3.fromRGB(46, 49, 57),
	wallHigh = Color3.fromRGB(96, 100, 108),
	ceiling = Color3.fromRGB(30, 32, 38),
	beam = Color3.fromRGB(58, 62, 72),
	hazard = Color3.fromRGB(240, 190, 40),
	rubber = Color3.fromRGB(24, 24, 28),
	steel = Color3.fromRGB(126, 132, 142),
	deep = Color3.fromRGB(20, 21, 26),
}

-- Stufenbild: jede Garagen-Stufe hat eine eigene Akzentfarbe und mehr Licht.
-- Das ist der einzige Weg, wie ein 260k-Upgrade sich nach 260k anfuehlt.
local LEVEL_LOOK = {
	{ trim = Color3.fromRGB(150, 96, 42), light = Color3.fromRGB(255, 196, 120), brightness = 1.2, paint = 0.85 },
	{ trim = Color3.fromRGB(245, 166, 35), light = Color3.fromRGB(255, 226, 178), brightness = 1.8, paint = 0.55 },
	{ trim = Color3.fromRGB(56, 225, 255), light = Color3.fromRGB(198, 240, 255), brightness = 2.4, paint = 0.3 },
	{ trim = Color3.fromRGB(255, 68, 92), light = Color3.fromRGB(255, 235, 235), brightness = 3.0, paint = 0.12 },
	{ trim = Color3.fromRGB(190, 120, 255), light = Color3.fromRGB(255, 255, 255), brightness = 3.8, paint = 0.0 },
}

local function makePart(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = props.Material or Enum.Material.Concrete
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Color = props.Color or C.wallHigh
	p.Name = props.Name or "Part"
	p.CanCollide = if props.CanCollide ~= nil then props.CanCollide else true
	p.CastShadow = if props.CastShadow ~= nil then props.CastShadow else true
	if props.Transparency then
		p.Transparency = props.Transparency
	end
	if props.Reflectance then
		p.Reflectance = props.Reflectance
	end
	if props.Shape then
		p.Shape = props.Shape
	end
	p.Parent = props.Parent
	return p
end

-- Duenne Deko-Flaechen: nie kollidieren, nie Schatten werfen. Sonst kostet
-- die Detailarbeit Performance, ohne dass man mehr sieht.
local function decal(props): Part
	props.CanCollide = false
	props.CastShadow = false
	return makePart(props)
end

local function makeSign(parent, cframe, size)
	local board = makePart({
		Name = "Sign",
		Size = size,
		CFrame = cframe,
		Color = C.deep,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = parent,
	})

	-- Rahmen: zwei duenne Leisten oben und unten. Ohne die schwebt das
	-- Schild als schwarzes Rechteck vor der Wand.
	for _, sign in { -1, 1 } do
		decal({
			Name = "SignEdge",
			Size = Vector3.new(size.X, 0.35, size.Z + 0.1),
			CFrame = cframe * CFrame.new(0, sign * (size.Y / 2 - 0.17), 0),
			Color = C.steel,
			Material = Enum.Material.Metal,
			Parent = parent,
		})
	end

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(600, 200)
	gui.LightInfluence = 0
	gui.Parent = board

	local function label(name, posScale, sizeScale, color, font)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.04, posScale)
		l.Size = UDim2.fromScale(0.92, sizeScale)
		l.Font = font
		l.TextScaled = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = color
		l.Text = ""
		l.Parent = gui
		return l
	end

	return {
		board = board,
		name = label("NameLabel", 0.03, 0.4, Color3.fromRGB(255, 255, 255), Enum.Font.Michroma),
		value = label("ValueLabel", 0.46, 0.27, Color3.fromRGB(120, 235, 165), Enum.Font.GothamBold),
		rate = label("RateLabel", 0.72, 0.24, Color3.fromRGB(170, 178, 192), Enum.Font.Gotham),
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
		CastShadow = false,
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

-- Reifenstapel, Fass, Werkzeugwand: reine Deko, aber sie machen aus dem
-- Karton eine Werkstatt. Alles ohne Schatten und ohne Kollision.
local function buildProps(model, base, halfWidth, halfDepth)
	-- Werkzeugwand hinten mitte
	decal({
		Name = "ToolBoard",
		Size = Vector3.new(14, 7, 0.3),
		CFrame = base * CFrame.new(0, 7.5, -halfDepth + WALL_THICK / 2 + 0.3),
		Color = Color3.fromRGB(58, 44, 34),
		Material = Enum.Material.WoodPlanks,
		Parent = model,
	})
	for i = 1, 7 do
		local x = -5.6 + (i - 1) * 1.85
		decal({
			Name = "Tool",
			Size = Vector3.new(0.35, 2.2 + (i % 3) * 0.7, 0.35),
			CFrame = base * CFrame.new(x, 8.4, -halfDepth + WALL_THICK / 2 + 0.55),
			Color = C.steel,
			Material = Enum.Material.Metal,
			Parent = model,
		})
	end

	-- Reifenstapel in beiden hinteren Ecken
	for _, sign in { -1, 1 } do
		for layer = 1, 4 do
			decal({
				Name = "TyreStack",
				Size = Vector3.new(1.1, 3.4, 3.4),
				CFrame = base
					* CFrame.new(sign * (halfWidth - 4.5), 0.6 + (layer - 1) * 1.15, -halfDepth + 5)
					* CFrame.Angles(0, 0, math.rad(90)),
				Color = C.rubber,
				Material = Enum.Material.Rubber,
				Shape = Enum.PartType.Cylinder,
				Parent = model,
			})
		end
		-- Oelfass daneben
		decal({
			Name = "Barrel",
			Size = Vector3.new(3.6, 2.6, 2.6),
			CFrame = base
				* CFrame.new(sign * (halfWidth - 4.2), 1.8, -halfDepth + 10.5)
				* CFrame.Angles(0, 0, math.rad(90)),
			Color = sign < 0 and Color3.fromRGB(60, 110, 90) or Color3.fromRGB(150, 60, 48),
			Material = Enum.Material.Metal,
			Shape = Enum.PartType.Cylinder,
			Parent = model,
		})
	end

	-- Oelfleck auf dem Boden. Kostet ein Part und nimmt dem Boden das Sterile.
	decal({
		Name = "OilStain",
		Size = Vector3.new(6.5, 0.04, 4.2),
		CFrame = base * CFrame.new(-4, 0.03, -2),
		Color = Color3.fromRGB(16, 16, 20),
		Material = Enum.Material.Glass,
		Reflectance = 0.25,
		Parent = model,
	})
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

	local trim = {}
	local ceilingLights = {}
	local floorPaint = {}

	-- Boden ---------------------------------------------------------------
	local floor = makePart({
		Name = "Floor",
		Size = Vector3.new(Config.PLOT_WIDTH, 1, Config.PLOT_DEPTH),
		CFrame = base * CFrame.new(0, -0.5, 0),
		Color = C.floor,
		Material = Enum.Material.Concrete,
		Parent = model,
	})
	model.PrimaryPart = floor

	-- Warnstreifen an der Torschwelle. Einzelne Bloecke statt Textur.
	for i = 0, 8 do
		decal({
			Name = "Hazard",
			Size = Vector3.new(2.4, 0.06, 2.2),
			CFrame = base * CFrame.new(-DOOR_WIDTH / 2 + 1.4 + i * 3, 0.03, halfDepth - 1.6),
			Color = i % 2 == 0 and C.hazard or C.deep,
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
	end

	-- Mittelgang: eine helle Linie vom Tor bis zur Werkzeugwand. Fuehrt das
	-- Auge und macht die Halle laenger, als sie ist.
	table.insert(
		floorPaint,
		decal({
			Name = "CenterLine",
			Size = Vector3.new(0.7, 0.05, Config.PLOT_DEPTH - 6),
			CFrame = base * CFrame.new(0, 0.03, -1),
			Color = C.floorPaint,
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
	)

	-- Waende --------------------------------------------------------------
	local function wall(name, size, offset)
		makePart({ Name = name, Size = size, CFrame = base * offset, Color = C.wallHigh, Parent = model })
	end
	wall("BackWall", Vector3.new(Config.PLOT_WIDTH, WALL_HEIGHT, WALL_THICK), CFrame.new(0, WALL_HEIGHT / 2, -halfDepth))
	for _, side in { -1, 1 } do
		wall(
			"SideWall",
			Vector3.new(WALL_THICK, WALL_HEIGHT, Config.PLOT_DEPTH),
			CFrame.new(side * halfWidth, WALL_HEIGHT / 2, 0)
		)
	end

	-- Sockelband: unten dunkel, oben hell. Zwei Toene statt einem machen aus
	-- der Wand eine Wand.
	decal({
		Name = "Base",
		Size = Vector3.new(Config.PLOT_WIDTH - 0.4, 5, 0.4),
		CFrame = base * CFrame.new(0, 2.5, -halfDepth + WALL_THICK / 2 + 0.2),
		Color = C.wallLow,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	for _, side in { -1, 1 } do
		decal({
			Name = "Base",
			Size = Vector3.new(0.4, 5, Config.PLOT_DEPTH - 0.4),
			CFrame = base * CFrame.new(side * (halfWidth - WALL_THICK / 2 - 0.2), 2.5, 0),
			Color = C.wallLow,
			Material = Enum.Material.Metal,
			Parent = model,
		})
	end

	-- Akzentleiste auf Sockelhoehe. Faerbt sich mit der Garagen-Stufe.
	table.insert(
		trim,
		decal({
			Name = "Trim",
			Size = Vector3.new(Config.PLOT_WIDTH - 0.4, 0.35, 0.5),
			CFrame = base * CFrame.new(0, 5.2, -halfDepth + WALL_THICK / 2 + 0.25),
			Material = Enum.Material.Neon,
			Parent = model,
		})
	)
	for _, side in { -1, 1 } do
		table.insert(
			trim,
			decal({
				Name = "Trim",
				Size = Vector3.new(0.5, 0.35, Config.PLOT_DEPTH - 0.4),
				CFrame = base * CFrame.new(side * (halfWidth - WALL_THICK / 2 - 0.25), 5.2, 0),
				Material = Enum.Material.Neon,
				Parent = model,
			})
		)
	end

	-- Front mit Toroeffnung -----------------------------------------------
	local pillarWidth = (Config.PLOT_WIDTH - DOOR_WIDTH) / 2
	for _, side in { -1, 1 } do
		makePart({
			Name = "FrontPillar",
			Size = Vector3.new(pillarWidth, WALL_HEIGHT, WALL_THICK),
			CFrame = base * CFrame.new(side * (halfWidth - pillarWidth / 2), WALL_HEIGHT / 2, halfDepth),
			Color = C.wallHigh,
			Parent = model,
		})
		-- Fuehrungsschiene neben dem Tor
		decal({
			Name = "DoorRail",
			Size = Vector3.new(0.6, DOOR_HEIGHT + 0.6, 0.8),
			CFrame = base * CFrame.new(side * (DOOR_WIDTH / 2 + 0.3), DOOR_HEIGHT / 2, halfDepth - 0.6),
			Color = C.steel,
			Material = Enum.Material.Metal,
			Parent = model,
		})
	end
	makePart({
		Name = "Lintel",
		Size = Vector3.new(DOOR_WIDTH, WALL_HEIGHT - DOOR_HEIGHT, WALL_THICK),
		CFrame = base * CFrame.new(0, DOOR_HEIGHT + (WALL_HEIGHT - DOOR_HEIGHT) / 2, halfDepth),
		Color = C.wallHigh,
		Parent = model,
	})

	-- Decke ---------------------------------------------------------------
	-- Zwei Platten mit Spalt in der Mitte: der Raum ist geschlossen, die
	-- Kamera kommt trotzdem von oben rein.
	-- CanCollide = false ist Absicht: die Standard-Roblox-Kamera schiebt sich
	-- nur an Parts heran, die kollidieren. So bleibt der Blick von oben frei,
	-- die Decke wirft aber trotzdem Schatten - erst dadurch wirkt der Raum
	-- wie ein Innenraum und die Deckenlampen haben eine Aufgabe.
	local slabWidth = (Config.PLOT_WIDTH - SKYLIGHT_GAP) / 2
	for _, side in { -1, 1 } do
		makePart({
			Name = "Ceiling",
			Size = Vector3.new(slabWidth, 0.8, Config.PLOT_DEPTH),
			CFrame = base * CFrame.new(side * (SKYLIGHT_GAP / 2 + slabWidth / 2), WALL_HEIGHT - 0.4, 0),
			Color = C.ceiling,
			Material = Enum.Material.Metal,
			CanCollide = false,
			CastShadow = true,
			Parent = model,
		})
	end
	for i = 0, 4 do
		decal({
			Name = "Beam",
			Size = Vector3.new(SKYLIGHT_GAP + 1, 0.9, 1.1),
			CFrame = base * CFrame.new(0, WALL_HEIGHT - 0.5, -halfDepth + 5 + i * 11),
			Color = C.beam,
			Material = Enum.Material.Metal,
			Parent = model,
		})
	end

	-- Hallenlicht: zwei Leisten, bewusst nicht mehr. Jede Lichtquelle kostet
	-- unter Future-Lighting spuerbar Leistung, mal zwoelf Garagen.
	for i, z in { -12, 12 } do
		local bar = decal({
			Name = "CeilingLight",
			Size = Vector3.new(SKYLIGHT_GAP - 2, 0.35, 2.6),
			CFrame = base * CFrame.new(0, WALL_HEIGHT - 1.2, z),
			Color = Color3.fromRGB(255, 245, 220),
			Material = Enum.Material.Neon,
			Parent = model,
		})
		local lamp = Instance.new("SurfaceLight")
		lamp.Face = Enum.NormalId.Bottom
		lamp.Angle = 150
		lamp.Range = 46
		lamp.Brightness = 2
		lamp.Shadows = false
		lamp.Parent = bar
		ceilingLights[i] = { bar = bar, lamp = lamp }
	end

	-- Tor -----------------------------------------------------------------
	local doorClosed = base * CFrame.new(0, DOOR_HEIGHT / 2, halfDepth)
	local door = makePart({
		Name = "Door",
		Size = Vector3.new(DOOR_WIDTH, DOOR_HEIGHT, 1),
		CFrame = doorClosed,
		Color = Color3.fromRGB(150, 84, 38),
		Material = Enum.Material.DiamondPlate,
		Parent = model,
	})
	local doorOpen = base * CFrame.new(0, DOOR_HEIGHT - 0.4, halfDepth)

	-- Unterkante des Tors: dicker Gummistreifen. Faehrt mit hoch und ist das
	-- Einzige, woran man die Bewegung sofort erkennt.
	local doorBar = decal({
		Name = "DoorBar",
		Size = Vector3.new(DOOR_WIDTH, 0.9, 1.3),
		CFrame = doorClosed * CFrame.new(0, -DOOR_HEIGHT / 2 + 0.45, 0),
		Color = C.deep,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	-- Torfarbe wird von aussen gesetzt (VIP-Gold). Der Streifen bleibt dunkel,
	-- aber die Schiene zieht mit.
	local sign = makeSign(model, base * CFrame.new(0, DOOR_HEIGHT + 2.6, halfDepth + 1.2), Vector3.new(24, 6, 0.4))

	-- Nummer neben dem Tor: aus der Entfernung erkennt man seinen Platz.
	local numberBoard = decal({
		Name = "PlotNumber",
		Size = Vector3.new(4, 4, 0.3),
		CFrame = base * CFrame.new(-(DOOR_WIDTH / 2 + 4), 8, halfDepth + 1.1),
		Color = C.deep,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	local numberGui = Instance.new("SurfaceGui")
	numberGui.Face = Enum.NormalId.Front
	numberGui.CanvasSize = Vector2.new(200, 200)
	numberGui.LightInfluence = 0
	numberGui.Parent = numberBoard
	local numberLabel = Instance.new("TextLabel")
	numberLabel.BackgroundTransparency = 1
	numberLabel.Size = UDim2.fromScale(1, 1)
	numberLabel.Font = Enum.Font.Michroma
	numberLabel.TextScaled = true
	numberLabel.TextColor3 = Color3.fromRGB(230, 234, 245)
	numberLabel.Text = ("%02d"):format(index)
	numberLabel.Parent = numberGui

	-- Stufen-Plakette unter dem Schild ("Blechbude", "Werk", ...)
	local levelBoard = decal({
		Name = "LevelPlate",
		Size = Vector3.new(10, 2.2, 0.3),
		CFrame = base * CFrame.new(DOOR_WIDTH / 2 + 5, 8, halfDepth + 1.1),
		Color = C.deep,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	local levelGui = Instance.new("SurfaceGui")
	levelGui.Face = Enum.NormalId.Front
	levelGui.CanvasSize = Vector2.new(400, 90)
	levelGui.LightInfluence = 0
	levelGui.Parent = levelBoard
	local levelLabel = Instance.new("TextLabel")
	levelLabel.BackgroundTransparency = 1
	levelLabel.Size = UDim2.fromScale(1, 1)
	levelLabel.Font = Enum.Font.GothamBold
	levelLabel.TextScaled = true
	levelLabel.TextColor3 = Color3.fromRGB(245, 166, 35)
	levelLabel.Text = Config.GARAGE_LEVELS[1].label
	levelLabel.Parent = levelGui

	-- Neonleiste ueber dem Tor. Farbe = offen/zu, aus jeder Entfernung.
	local strip = decal({
		Name = "NeonStrip",
		Size = Vector3.new(DOOR_WIDTH, 0.6, 0.6),
		CFrame = base * CFrame.new(0, DOOR_HEIGHT + 0.9, halfDepth + 0.6),
		Color = CLOSED_LIGHT,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	local light = Instance.new("PointLight")
	light.Brightness = 2.5
	light.Range = 34
	light.Shadows = false
	light.Color = CLOSED_LIGHT
	light.Parent = strip

	-- Kasse ---------------------------------------------------------------
	-- Der Prompt-Part bleibt derselbe, drumherum steht jetzt ein Tresen.
	local registerCFrame = base * CFrame.new(-halfWidth + 5, 1.5, halfDepth - 6)
	decal({
		Name = "RegisterDesk",
		Size = Vector3.new(5.5, 3, 5.5),
		CFrame = registerCFrame * CFrame.new(0, -0.2, 0),
		Color = C.wallLow,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	local register = makePad(
		model,
		registerCFrame * CFrame.new(0, 1.5, 0),
		Vector3.new(5.7, 0.4, 5.7),
		Color3.fromRGB(90, 220, 120),
		"CashRegister",
		"Kasse leeren",
		"Garagenkasse"
	)
	register.CanCollide = true

	-- Werkbank ------------------------------------------------------------
	local benchCFrame = base * CFrame.new(halfWidth - 5, 1.5, halfDepth - 6)
	decal({
		Name = "BenchBody",
		Size = Vector3.new(5, 3, 7),
		CFrame = benchCFrame * CFrame.new(0, -0.2, 0),
		Color = C.wallLow,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	decal({
		Name = "BenchVice",
		Size = Vector3.new(1.2, 1.4, 1.6),
		CFrame = benchCFrame * CFrame.new(0, 2.2, -2.4),
		Color = C.steel,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	local workbench = makePad(
		model,
		benchCFrame * CFrame.new(0, 1.5, 0),
		Vector3.new(5.2, 0.4, 7.2),
		Color3.fromRGB(240, 176, 62),
		"Workbench",
		"Werkstatt oeffnen",
		"Werkbank"
	)
	workbench.CanCollide = true
	workbench:SetAttribute("PlotIndex", index)
	register:SetAttribute("PlotIndex", index)

	-- Abgabe-Pad ----------------------------------------------------------
	local lootBay = makePad(
		model,
		base * CFrame.new(0, 0.15, halfDepth - 5),
		Vector3.new(12, 0.3, 6),
		Color3.fromRGB(70, 155, 255),
		"LootBay",
		nil,
		nil
	)
	-- Rahmen aus vier Leisten. Ohne den ist das Pad ein blauer Fleck.
	for _, spec in
		{
			{ Vector3.new(13, 0.14, 0.7), CFrame.new(0, 0, 3.2) },
			{ Vector3.new(13, 0.14, 0.7), CFrame.new(0, 0, -3.2) },
			{ Vector3.new(0.7, 0.14, 7), CFrame.new(6.4, 0, 0) },
			{ Vector3.new(0.7, 0.14, 7), CFrame.new(-6.4, 0, 0) },
		}
	do
		decal({
			Name = "LootEdge",
			Size = spec[1],
			CFrame = base * CFrame.new(0, 0.1, halfDepth - 5) * spec[2],
			Color = Color3.fromRGB(150, 205, 255),
			Material = Enum.Material.Neon,
			Parent = model,
		})
	end
	local bayGui = Instance.new("BillboardGui")
	bayGui.Size = UDim2.fromScale(10, 2)
	bayGui.StudsOffset = Vector3.new(0, 3.4, 0)
	bayGui.MaxDistance = 70
	bayGui.Parent = lootBay
	local bayLabel = Instance.new("TextLabel")
	bayLabel.BackgroundTransparency = 1
	bayLabel.Size = UDim2.fromScale(1, 1)
	bayLabel.Font = Enum.Font.Michroma
	bayLabel.TextScaled = true
	bayLabel.TextColor3 = Color3.fromRGB(170, 215, 255)
	bayLabel.TextStrokeTransparency = 0.4
	bayLabel.Text = "ABGABE"
	bayLabel.Parent = bayGui

	-- Pruefstand -----------------------------------------------------------
	-- Liegt im freien Streifen zwischen Abgabe-Pad (z ab 19) und den vorderen
	-- Stellplaetzen (z bis 12). Die 10x6 passen dort ohne Ueberschneidung, und
	-- man laeuft auf dem Weg zur Werkbank ohnehin darueber.
	local dyno = makePad(
		model,
		base * CFrame.new(0, 0.15, halfDepth - 11.5),
		Vector3.new(10, 0.3, 6),
		Color3.fromRGB(255, 140, 60),
		"Dyno",
		"Leistung messen",
		"Pruefstand"
	)
	dyno:SetAttribute("PlotIndex", index)
	for _, spec in
		{
			{ Vector3.new(11, 0.14, 0.6), CFrame.new(0, 0, 3.2) },
			{ Vector3.new(11, 0.14, 0.6), CFrame.new(0, 0, -3.2) },
		}
	do
		decal({
			Name = "DynoRoller",
			Size = spec[1],
			CFrame = base * CFrame.new(0, 0.12, halfDepth - 11.5) * spec[2],
			Color = C.steel,
			Material = Enum.Material.Metal,
			Parent = model,
		})
	end
	local dynoGui = Instance.new("BillboardGui")
	dynoGui.Size = UDim2.fromScale(9, 2)
	dynoGui.StudsOffset = Vector3.new(0, 3, 0)
	dynoGui.MaxDistance = 60
	dynoGui.Parent = dyno
	local dynoLabel = Instance.new("TextLabel")
	dynoLabel.BackgroundTransparency = 1
	dynoLabel.Size = UDim2.fromScale(1, 1)
	dynoLabel.Font = Enum.Font.Michroma
	dynoLabel.TextScaled = true
	dynoLabel.TextColor3 = Color3.fromRGB(255, 170, 90)
	dynoLabel.TextStrokeTransparency = 0.4
	dynoLabel.Text = "PRUEFSTAND"
	dynoLabel.Parent = dynoGui

	-- Stellplaetze ---------------------------------------------------------
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
			Color = Color3.fromRGB(44, 46, 52),
			Material = Enum.Material.Metal,
			CanCollide = false,
			CastShadow = false,
			Parent = model,
		})
		-- Gemalter Rahmen um den Stellplatz.
		for _, spec in
			{
				{ Vector3.new(9, 0.05, 0.5), CFrame.new(0, 0, 7.2) },
				{ Vector3.new(9, 0.05, 0.5), CFrame.new(0, 0, -7.2) },
				{ Vector3.new(0.5, 0.05, 15), CFrame.new(4.5, 0, 0) },
				{ Vector3.new(0.5, 0.05, 15), CFrame.new(-4.5, 0, 0) },
			}
		do
			table.insert(
				floorPaint,
				decal({
					Name = "BayLine",
					Size = spec[1],
					CFrame = padCFrame * CFrame.new(0, 0.04, 0) * spec[2],
					Color = C.floorPaint,
					Material = Enum.Material.SmoothPlastic,
					Parent = model,
				})
			)
		end
		carPads[i] = padCFrame
	end

	buildProps(model, base, halfWidth, halfDepth)

	local plot = {
		index = index,
		model = model,
		cframe = base,
		floor = floor,
		door = door,
		doorBar = doorBar,
		doorClosedCFrame = doorClosed,
		doorOpenCFrame = doorOpen,
		doorIsOpen = false,
		sign = sign,
		strip = strip,
		light = light,
		register = register,
		workbench = workbench,
		lootBay = lootBay,
		dyno = dyno,
		dynoLabel = dynoLabel,
		carPads = carPads,
		spawnCFrame = base * CFrame.new(0, 3, halfDepth - 14),
		trim = trim,
		ceilingLights = ceilingLights,
		floorPaint = floorPaint,
		levelLabel = levelLabel,
	}

	PlotBuilder.ApplyLevel(plot, 1)
	return plot
end

-- Garagen-Stufe sichtbar machen. Ohne diesen Aufruf sieht ein 260k-Upgrade
-- genauso aus wie die Startbude - das war der groesste Designfehler vorher.
function PlotBuilder.ApplyLevel(plot, level: number)
	local look = LEVEL_LOOK[math.clamp(level or 1, 1, #LEVEL_LOOK)]
	if not look then
		return
	end
	plot.level = level
	for _, part in plot.trim do
		part.Color = look.trim
	end
	for _, entry in plot.ceilingLights do
		entry.bar.Color = look.light
		entry.lamp.Color = look.light
		entry.lamp.Brightness = look.brightness
	end
	for _, part in plot.floorPaint do
		part.Transparency = look.paint
	end
	local def = Config.GARAGE_LEVELS[level]
	if plot.levelLabel and def then
		plot.levelLabel.Text = def.label
		plot.levelLabel.TextColor3 = look.trim
	end
end

function PlotBuilder.SetDoor(plot, open: boolean)
	if plot.doorIsOpen == open then
		return
	end
	plot.doorIsOpen = open

	local lightColor = open and OPEN_LIGHT or CLOSED_LIGHT
	plot.strip.Color = lightColor
	plot.light.Color = lightColor
	Audio.PlayAt("doorOpen", plot.door.Position)

	local goalCFrame = open and plot.doorOpenCFrame or plot.doorClosedCFrame
	local goalSize = open and Vector3.new(DOOR_WIDTH, 0.8, 1) or Vector3.new(DOOR_WIDTH, DOOR_HEIGHT, 1)
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad)
	TweenService:Create(plot.door, info, { CFrame = goalCFrame, Size = goalSize }):Play()

	if plot.doorBar then
		local barGoal = open and (plot.doorOpenCFrame * CFrame.new(0, -0.2, 0))
			or (plot.doorClosedCFrame * CFrame.new(0, -DOOR_HEIGHT / 2 + 0.45, 0))
		TweenService:Create(plot.doorBar, info, { CFrame = barGoal }):Play()
	end
end

return PlotBuilder
