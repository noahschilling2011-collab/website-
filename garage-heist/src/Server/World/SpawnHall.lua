--[[
	SpawnHall
	Die grosse Werkhalle, in der neue Spieler landen.

	WICHTIG ZUR LAGE: die Halle steht NICHT in der Hofmitte, sondern am
	westlichen Ende der Hofachse bei x = -215. Zwei Gruende:

	1. Der Hof zwischen den Garagenreihen ist die Klau-Arena. Da stehen jetzt
	   Container und Rampen als Deckung - ein Gebaeude mittendrin nimmt genau
	   die Flaeche weg, die das Klau-Fenster interessant macht.
	2. Vom Hallenausgang laeuft man die Hofachse entlang. Dabei sieht man in
	   einem Schwenk: Container, beide Garagenreihen, die Strecke darueber und
	   am anderen Ende den Torbogen. Das sind die besten fuenfzehn Sekunden,
	   die das Spiel zu bieten hat, und sie passieren von allein.

	Die Halle ist KEINE Schleuse. Sie ist nach +X komplett offen, hat kein Tor
	und keine Bedingung. Wer weiterlaufen will, laeuft weiter; wer es eilig
	hat, nimmt das Warp-Pad am Ausgang.

	Drei Stationen erklaeren die Schleife in der Reihenfolge, in der man an
	ihnen vorbeikommt. Dazu ein voll ausgebautes Auto auf der Hebebuehne -
	das ist das Ziel, und es steht am Anfang, nicht am Ende.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local PartCatalog = require(Shared.PartCatalog)

local CarBuilder = require(script.Parent.CarBuilder)

local SpawnHall = {}

-- Hallenmasse. Die Rueckwand bei x = -252 haelt 13 Studs Abstand zur
-- Streckengeraden bei x = -265; kein Pfeiler und kein Torbogenfuss landet
-- innerhalb der Halle.
local CENTER_X = -215
local HALF_DEPTH = 37 -- entlang X
local HALF_WIDTH = 62 -- entlang Z
local HEIGHT = 30
local WALL = 2

SpawnHall.SPAWN_CFRAME = CFrame.new(CENTER_X - HALF_DEPTH + 9, 0.5, 0) * CFrame.Angles(0, math.rad(-90), 0)

local C = {
	floor = Color3.fromRGB(46, 48, 55),
	paint = Color3.fromRGB(204, 208, 218),
	wallLow = Color3.fromRGB(40, 43, 50),
	wallHigh = Color3.fromRGB(96, 100, 110),
	ceiling = Color3.fromRGB(28, 30, 36),
	steel = Color3.fromRGB(126, 132, 142),
	truss = Color3.fromRGB(58, 62, 72),
	accent = Color3.fromRGB(245, 166, 35),
	neon = Color3.fromRGB(56, 214, 255),
	good = Color3.fromRGB(74, 222, 128),
	heist = Color3.fromRGB(255, 45, 85),
	dark = Color3.fromRGB(18, 19, 24),
	rubber = Color3.fromRGB(24, 24, 28),
}

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Color = props.Color or C.wallHigh
	p.Material = props.Material or Enum.Material.Concrete
	p.Name = props.Name or "Part"
	p.CanCollide = if props.CanCollide ~= nil then props.CanCollide else false
	p.CastShadow = if props.CastShadow ~= nil then props.CastShadow else false
	p.Transparency = props.Transparency or 0
	if props.Shape then
		p.Shape = props.Shape
	end
	p.Parent = props.Parent
	return p
end

-- Grosse Tafel an der Wand. Zwei Zeilen, nicht mehr - wer drei Absaetze
-- schreibt, hat schon verloren.
local function board(parent, cframe, size, number, title, text, color)
	part({
		Name = "BoardFrame",
		Size = Vector3.new(size.X + 0.8, size.Y + 0.8, 0.3),
		CFrame = cframe * CFrame.new(0, 0, -0.15),
		Color = C.steel,
		Material = Enum.Material.Metal,
		Parent = parent,
	})
	local face = part({
		Name = "Board",
		Size = size,
		CFrame = cframe,
		Color = C.dark,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(700, 320)
	gui.LightInfluence = 0
	gui.Parent = face

	local num = Instance.new("TextLabel")
	num.BackgroundTransparency = 1
	num.Position = UDim2.fromScale(0.04, 0.04)
	num.Size = UDim2.fromScale(0.16, 0.34)
	num.Font = Enum.Font.Michroma
	num.TextScaled = true
	num.TextXAlignment = Enum.TextXAlignment.Left
	num.TextColor3 = color
	num.Text = number
	num.Parent = gui

	local head = Instance.new("TextLabel")
	head.BackgroundTransparency = 1
	head.Position = UDim2.fromScale(0.21, 0.04)
	head.Size = UDim2.fromScale(0.75, 0.34)
	head.Font = Enum.Font.Michroma
	head.TextScaled = true
	head.TextXAlignment = Enum.TextXAlignment.Left
	head.TextColor3 = Color3.fromRGB(245, 247, 252)
	head.Text = title
	head.Parent = gui

	local body = Instance.new("TextLabel")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromScale(0.04, 0.44)
	body.Size = UDim2.fromScale(0.92, 0.5)
	body.Font = Enum.Font.GothamBold
	body.TextScaled = true
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextColor3 = Color3.fromRGB(168, 176, 192)
	body.Text = text
	body.Parent = gui

	-- Leuchtkante unten in der Stationsfarbe.
	part({
		Name = "BoardGlow",
		Size = Vector3.new(size.X + 0.8, 0.4, 0.5),
		CFrame = cframe * CFrame.new(0, -size.Y / 2 - 0.4, 0),
		Color = color,
		Material = Enum.Material.Neon,
		Parent = parent,
	})
	return face
end

local function buildStructure(model)
	local depth = HALF_DEPTH * 2
	local width = HALF_WIDTH * 2

	part({
		Name = "Floor",
		Size = Vector3.new(depth, 1, width),
		CFrame = CFrame.new(CENTER_X, -0.5, 0),
		Color = C.floor,
		Material = Enum.Material.Concrete,
		CanCollide = true,
		Parent = model,
	})

	-- Rueckwand und beide Seitenwaende. Nach +X bleibt die Halle offen.
	part({
		Name = "BackWall",
		Size = Vector3.new(WALL, HEIGHT, width),
		CFrame = CFrame.new(CENTER_X - HALF_DEPTH, HEIGHT / 2, 0),
		Color = C.wallHigh,
		CanCollide = true,
		CastShadow = true,
		Parent = model,
	})
	for _, side in { -1, 1 } do
		part({
			Name = "SideWall",
			Size = Vector3.new(depth, HEIGHT, WALL),
			CFrame = CFrame.new(CENTER_X, HEIGHT / 2, side * HALF_WIDTH),
			Color = C.wallHigh,
			CanCollide = true,
			CastShadow = true,
			Parent = model,
		})
		part({
			Name = "WallBase",
			Size = Vector3.new(depth - 0.4, 6, 0.5),
			CFrame = CFrame.new(CENTER_X, 3, side * (HALF_WIDTH - WALL / 2 - 0.25)),
			Color = C.wallLow,
			Material = Enum.Material.Metal,
			Parent = model,
		})
	end
	-- Portalrahmen am offenen Ende, damit die Halle eine Kante hat.
	part({
		Name = "PortalBeam",
		Size = Vector3.new(3, 5, width),
		CFrame = CFrame.new(CENTER_X + HALF_DEPTH, HEIGHT - 2.5, 0),
		Color = C.truss,
		Material = Enum.Material.Metal,
		CastShadow = true,
		Parent = model,
	})

	-- Dach mit Lichtschacht in der Mitte, gleiche Loesung wie in den Garagen:
	-- CanCollide = false, damit die Kamera von oben hereinschaut, aber
	-- CastShadow = true, damit es drinnen nach Innenraum aussieht.
	local gap = 22
	local slab = (width - gap) / 2
	for _, side in { -1, 1 } do
		part({
			Name = "Ceiling",
			Size = Vector3.new(depth, 1, slab),
			CFrame = CFrame.new(CENTER_X, HEIGHT - 0.5, side * (gap / 2 + slab / 2)),
			Color = C.ceiling,
			Material = Enum.Material.Metal,
			CastShadow = true,
			Parent = model,
		})
	end

	-- Fachwerktraeger quer. Das ist das Bauteil, das eine Halle gross
	-- aussehen laesst: sichtbare Konstruktion statt glatter Decke.
	for i = 0, 5 do
		local x = CENTER_X - HALF_DEPTH + 7 + i * 12
		part({
			Name = "TrussChord",
			Size = Vector3.new(1.4, 1.4, width - 2),
			CFrame = CFrame.new(x, HEIGHT - 2, 0),
			Color = C.truss,
			Material = Enum.Material.Metal,
			Parent = model,
		})
		part({
			Name = "TrussChord",
			Size = Vector3.new(1.2, 1.2, width - 2),
			CFrame = CFrame.new(x, HEIGHT - 6, 0),
			Color = C.truss,
			Material = Enum.Material.Metal,
			Parent = model,
		})
		for d = -4, 4 do
			part({
				Name = "TrussWeb",
				Size = Vector3.new(0.7, 5, 0.7),
				CFrame = CFrame.new(x, HEIGHT - 4, d * 13) * CFrame.Angles(math.rad(d % 2 == 0 and 22 or -22), 0, 0),
				Color = C.truss,
				Material = Enum.Material.Metal,
				Parent = model,
			})
		end
	end

	-- Vier Hallenstrahler. Range grosszuegig, Shadows aus - bei zwoelf
	-- Garagen plus Strecke ist das Lichtbudget schon knapp.
	for i = 0, 3 do
		local x = CENTER_X - HALF_DEPTH + 12 + i * 17
		local bar = part({
			Name = "HallLight",
			Size = Vector3.new(3.4, 0.5, width - 26),
			CFrame = CFrame.new(x, HEIGHT - 7.5, 0),
			Color = Color3.fromRGB(255, 246, 224),
			Material = Enum.Material.Neon,
			Parent = model,
		})
		local lamp = Instance.new("SurfaceLight")
		lamp.Face = Enum.NormalId.Bottom
		lamp.Angle = 150
		lamp.Range = 60
		lamp.Brightness = 2.4
		lamp.Shadows = false
		lamp.Parent = bar
	end
end

local function buildFloorGraphics(model)
	-- Pfeilkette zum Ausgang. Wer nichts liest, folgt trotzdem den Pfeilen.
	for i = 0, 5 do
		local x = CENTER_X - 22 + i * 11
		for _, side in { -1, 1 } do
			part({
				Name = "Chevron",
				Size = Vector3.new(7, 0.06, 1.5),
				CFrame = CFrame.new(x, 0.04, side * 2.6) * CFrame.Angles(0, math.rad(side * 28), 0),
				Color = C.accent,
				Material = Enum.Material.SmoothPlastic,
				Transparency = 0.15 + i * 0.05,
				Parent = model,
			})
		end
	end
	-- Randmarkierung ringsum
	for _, side in { -1, 1 } do
		part({
			Name = "FloorLine",
			Size = Vector3.new(HALF_DEPTH * 2 - 6, 0.05, 0.6),
			CFrame = CFrame.new(CENTER_X, 0.04, side * (HALF_WIDTH - 8)),
			Color = C.paint,
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
	end
end

local function buildStations(model)
	local wallZ = -(HALF_WIDTH - WALL / 2 - 0.4)
	local facing = CFrame.Angles(0, 0, 0) -- Tafeln schauen nach +Z in die Halle

	board(
		model,
		CFrame.new(CENTER_X - 22, 11, wallZ) * facing,
		Vector3.new(21, 9.6, 0.4),
		"1",
		"TEILE EINBAUEN",
		"Motor, Reifen, Lack, Turbo. Jedes verbaute Teil bringt Cash pro Sekunde - auch wenn du offline bist.",
		C.accent
	)
	board(
		model,
		CFrame.new(CENTER_X + 2, 11, wallZ) * facing,
		Vector3.new(21, 9.6, 0.4),
		"2",
		"KASSE LEEREN",
		"Das Geld sammelt sich in deiner Garage. Hol es ab, bevor die Kasse voll ist.",
		C.good
	)
	board(
		model,
		CFrame.new(CENTER_X + 26, 11, wallZ) * facing,
		Vector3.new(21, 9.6, 0.4),
		"3",
		"KLAUEN",
		("Alle %d Minuten gehen ALLE Tore auf. Teil abmontieren, heimtragen, einbauen. Wer dich rempelt, kriegt es."):format(
			math.floor(Config.HEIST_INTERVAL / 60)
		),
		C.heist
	)

	-- Grosser Schriftzug an der Rueckwand.
	local sign = part({
		Name = "HallSign",
		Size = Vector3.new(0.4, 12, 74),
		CFrame = CFrame.new(CENTER_X - HALF_DEPTH + WALL / 2 + 0.3, 21, 0),
		Color = C.dark,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Right
	gui.CanvasSize = Vector2.new(1200, 200)
	gui.LightInfluence = 0
	gui.Parent = sign
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.68)
	title.Font = Enum.Font.Michroma
	title.TextScaled = true
	title.TextColor3 = C.accent
	title.Text = "GARAGE HEIST"
	title.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromScale(0, 0.68)
	sub.Size = UDim2.fromScale(1, 0.32)
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(150, 158, 175)
	sub.Text = "Bau auf. Pass auf. Klau zurueck."
	sub.Parent = gui
end

-- Werkstattatmosphaere an der gegenueberliegenden Wand.
local function buildProps(model)
	local wallZ = HALF_WIDTH - WALL / 2 - 0.5

	part({
		Name = "ToolBoard",
		Size = Vector3.new(30, 9, 0.4),
		CFrame = CFrame.new(CENTER_X - 12, 9, wallZ),
		Color = Color3.fromRGB(58, 44, 34),
		Material = Enum.Material.WoodPlanks,
		Parent = model,
	})
	for i = 0, 13 do
		part({
			Name = "Tool",
			Size = Vector3.new(0.45, 2.4 + (i % 4) * 0.8, 0.45),
			CFrame = CFrame.new(CENTER_X - 25.5 + i * 2.1, 10.4, wallZ - 0.5),
			Color = C.steel,
			Material = Enum.Material.Metal,
			Parent = model,
		})
	end
	-- Regal mit Reifen
	for rack = 0, 2 do
		for layer = 0, 3 do
			part({
				Name = "TyreStack",
				Size = Vector3.new(1.2, 3.6, 3.6),
				CFrame = CFrame.new(CENTER_X + 14 + rack * 6, 0.8 + layer * 1.25, wallZ - 3)
					* CFrame.Angles(0, 0, math.rad(90)),
				Color = C.rubber,
				Material = Enum.Material.Rubber,
				Shape = Enum.PartType.Cylinder,
				Parent = model,
			})
		end
	end
	for _, spec in
		{
			{ x = CENTER_X - 30, c = Color3.fromRGB(60, 110, 90) },
			{ x = CENTER_X - 25, c = Color3.fromRGB(150, 60, 48) },
		}
	do
		part({
			Name = "Barrel",
			Size = Vector3.new(4, 2.8, 2.8),
			CFrame = CFrame.new(spec.x, 2, wallZ - 3.5) * CFrame.Angles(0, 0, math.rad(90)),
			Color = spec.c,
			Material = Enum.Material.Metal,
			CanCollide = true,
			Parent = model,
		})
	end
end

-- Hebebuehne mit einem voll ausgebauten Auto. Das Ziel steht am Anfang.
local function buildShowcase(model)
	local baseCF = CFrame.new(CENTER_X + 4, 0, 26) * CFrame.Angles(0, math.rad(210), 0)

	part({
		Name = "LiftBase",
		Size = Vector3.new(20, 1.2, 20),
		CFrame = CFrame.new(CENTER_X + 4, 0.6, 26),
		Color = C.dark,
		Material = Enum.Material.DiamondPlate,
		CanCollide = true,
		Parent = model,
	})
	part({
		Name = "LiftRing",
		Size = Vector3.new(21, 0.3, 21),
		CFrame = CFrame.new(CENTER_X + 4, 1.25, 26),
		Color = C.neon,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	for _, spec in { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } do
		part({
			Name = "LiftArm",
			Size = Vector3.new(1.6, 3.4, 1.6),
			CFrame = CFrame.new(CENTER_X + 4 + spec[1] * 6, 2.9, 26 + spec[2] * 7),
			Color = C.steel,
			Material = Enum.Material.Metal,
			CanCollide = true,
			Parent = model,
		})
	end

	local demo = { carId = "supercar", parts = {} }
	for _, slotId in PartCatalog.SlotOrder do
		demo.parts[slotId] = {
			uid = "showroom_" .. slotId,
			slotId = slotId,
			tier = PartCatalog.TierCount(slotId),
			subTier = 0,
			originalOwner = 0,
		}
	end

	local refs = CarBuilder.Build(demo, 1, 0, baseCF * CFrame.new(0, 4.6, 0), model, { rebirths = 0 })
	-- Ein Showroom-Auto ist kein Klauziel: die Prompts kommen weg, sonst
	-- haengt an einem Deko-Modell ein Griff ohne Funktion.
	for _, prompt in refs.prompts do
		prompt:Destroy()
	end
	refs.billboard.title.Text = "Supersportler - voll ausgebaut"
	refs.billboard.sub.Text = "Das ist das Ziel."

	-- Vier Strahler auf das Auto.
	for _, spec in { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } do
		local can = part({
			Name = "Spot",
			Size = Vector3.new(1.8, 1.2, 1.8),
			CFrame = CFrame.new(CENTER_X + 4 + spec[1] * 9, HEIGHT - 9, 26 + spec[2] * 9),
			Color = Color3.fromRGB(255, 250, 235),
			Material = Enum.Material.Neon,
			Parent = model,
		})
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Bottom
		light.Angle = 70
		light.Range = 40
		light.Brightness = 2
		light.Shadows = false
		light.Parent = can
	end
end

-- Warp-Pad am Ausgang. Ohne das laeuft ein Spieler, der das Spiel schon
-- kennt, jedes Mal bis zu 350 Studs zu seiner Garage.
local function buildWarpPad(model)
	local pos = Vector3.new(CENTER_X + HALF_DEPTH - 8, 0, 0)

	local pad = part({
		Name = "WarpPad",
		Size = Vector3.new(12, 0.4, 12),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.2, 0)),
		Color = C.neon,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = model,
	})
	for _, spec in
		{
			{ Vector3.new(13, 0.25, 0.8), Vector3.new(0, 0, 6.4) },
			{ Vector3.new(13, 0.25, 0.8), Vector3.new(0, 0, -6.4) },
			{ Vector3.new(0.8, 0.25, 13), Vector3.new(6.4, 0, 0) },
			{ Vector3.new(0.8, 0.25, 13), Vector3.new(-6.4, 0, 0) },
		}
	do
		part({
			Name = "WarpEdge",
			Size = spec[1],
			CFrame = CFrame.new(pos + spec[2] + Vector3.new(0, 0.15, 0)),
			Color = Color3.fromRGB(180, 235, 255),
			Material = Enum.Material.Neon,
			Parent = model,
		})
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GarageWarp"
	prompt.ActionText = "Zur Garage"
	prompt.ObjectText = "Direkt hin"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(14, 3)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.MaxDistance = 160
	gui.Parent = pad
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Michroma
	label.TextScaled = true
	label.TextColor3 = C.neon
	label.TextStrokeTransparency = 0.35
	label.Text = "ZU DEINER GARAGE"
	label.Parent = gui

	return pad, prompt
end

function SpawnHall.Build(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "SpawnHall"
	model.Parent = parent

	buildStructure(model)
	buildFloorGraphics(model)
	buildStations(model)
	buildProps(model)
	buildShowcase(model)
	local pad, prompt = buildWarpPad(model)

	return { model = model, warpPad = pad, warpPrompt = prompt, spawnCFrame = SpawnHall.SPAWN_CFRAME }
end

return SpawnHall
