--!strict
-- Items.luau
-- Kompletter Katalog der Fertiggebaeude, datengetrieben inkl. Model-Builder.
-- Neues Item = neuer Eintrag in Items.List, kein neuer Code an anderer Stelle.
--
-- Jeder Eintrag:
--   id              eindeutiger String
--   name            Anzeigename
--   footprint       {w, d} in Zellen (Breite entlang X, Tiefe entlang Z) bei rot=0
--   price           Kaufpreis
--   income          Einkommen pro Tick
--   residents       Einwohner
--   isRoad          true = zaehlt als Strassenanschluss und braucht selbst keinen
--   unlockPop       ab wievielen Einwohnern freigeschaltet
--   build()         baut das Model (zentriert auf XZ=0, Boden bei y=0), PrimaryPart gesetzt

local Config = require(script.Parent.Config)

local CELL = Config.CellSize

local Items = {}

-- ----------------------------------------------------------------------------
-- Bau-Helfer
-- ----------------------------------------------------------------------------

local function newPart(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function newWedge(parent: Instance, size: Vector3, cf: CFrame, color: Color3): WedgePart
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.CanCollide = true
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = Enum.Material.SmoothPlastic
	w.Parent = parent
	return w
end

-- Erzeugt ein Model mit unsichtbarem Anker als PrimaryPart im Ursprung (0,0,0).
-- Der Anker markiert den Footprint-Mittelpunkt auf Bodenhoehe; PivotTo rotiert
-- das gesamte Model sauber um diesen Punkt.
local function newModel(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Anchored = true
	anchor.CFrame = CFrame.new(0, 0, 0)
	anchor.Parent = model
	model.PrimaryPart = anchor
	return model
end

-- Farben
local C_ROAD = Color3.fromRGB(55, 55, 60)
local C_LINE = Color3.fromRGB(240, 200, 40)
local C_HOUSE = Color3.fromRGB(214, 170, 120)
local C_ROOF = Color3.fromRGB(150, 60, 45)
local C_SHOP = Color3.fromRGB(90, 160, 200)
local C_SIGN = Color3.fromRGB(230, 70, 70)
local C_TOWER = Color3.fromRGB(120, 130, 145)
local C_GLASS = Color3.fromRGB(140, 205, 235)
local C_HWY = Color3.fromRGB(45, 45, 50)
local C_RAIL = Color3.fromRGB(200, 200, 205)
local C_TERMINAL = Color3.fromRGB(210, 210, 220)
local C_PLANE = Color3.fromRGB(235, 235, 240)
local C_STRIP = Color3.fromRGB(70, 70, 75)
local C_GRASS = Color3.fromRGB(110, 170, 90)
local C_TRUNK = Color3.fromRGB(100, 70, 45)
local C_LEAF = Color3.fromRGB(70, 150, 70)
local C_UBLUE = Color3.fromRGB(0, 90, 170)
local C_FACTORY = Color3.fromRGB(160, 150, 140)
local C_ROOFDARK = Color3.fromRGB(90, 95, 100)
local C_BRICK = Color3.fromRGB(150, 80, 60)

-- ----------------------------------------------------------------------------
-- Model-Builder pro Item
-- ----------------------------------------------------------------------------

local function buildRoad(): Model
	local m = newModel("Strasse")
	newPart(m, Vector3.new(CELL, 0.4, CELL), CFrame.new(0, 0.2, 0), C_ROAD)
	newPart(m, Vector3.new(0.6, 0.42, CELL), CFrame.new(0, 0.21, 0), C_LINE)
	return m
end

local function buildHouse(): Model
	local m = newModel("Wohnhaus")
	-- Baukoerper 8x8 Footprint -> 6x6 Grundriss, 5 hoch
	newPart(m, Vector3.new(6, 5, 6), CFrame.new(0, 2.5, 0), C_HOUSE)
	-- Prismendach (Giebel) aus zwei Keilen, Firstlinie entlang X.
	-- WedgePart: die hohe Kante liegt auf der lokalen +Z-Seite; beide Keile
	-- drehen ihre hohe Kante zur Hausmitte (z=0), damit ein First entsteht.
	newWedge(m, Vector3.new(6, 2.5, 3), CFrame.new(0, 6.25, 1.5) * CFrame.Angles(0, math.pi, 0), C_ROOF)
	newWedge(m, Vector3.new(6, 2.5, 3), CFrame.new(0, 6.25, -1.5), C_ROOF)
	-- Tuer
	newPart(m, Vector3.new(1.2, 2, 0.2), CFrame.new(0, 1, 3.0), Color3.fromRGB(90, 55, 35))
	return m
end

local function buildShop(): Model
	local m = newModel("Geschaeft")
	-- Flache Box 6x6, 3 hoch
	newPart(m, Vector3.new(6, 3, 6), CFrame.new(0, 1.5, 0), C_SHOP)
	-- Schild-Part vorne oben
	newPart(m, Vector3.new(5, 1.4, 0.4), CFrame.new(0, 3.7, 3.0), C_SIGN, Enum.Material.Neon)
	-- Schaufenster
	newPart(m, Vector3.new(4.5, 1.6, 0.2), CFrame.new(0, 1.3, 3.05), C_GLASS, Enum.Material.Glass)
	return m
end

local function buildTower(): Model
	local m = newModel("Hochhaus")
	-- Drei gestapelte Boxen, ~25 Studs hoch
	local levels = {
		{ size = Vector3.new(10, 8, 10), y = 4 },
		{ size = Vector3.new(9, 8, 9), y = 12 },
		{ size = Vector3.new(8, 8, 8), y = 20 },
	}
	for _, lvl in levels do
		newPart(m, lvl.size, CFrame.new(0, lvl.y, 0), C_TOWER)
		-- Fenster-Streifen (Glas-Baender) rund um jede Etage
		for _, band in { -2, 0, 2 } do
			newPart(m, Vector3.new(lvl.size.X + 0.1, 1.2, lvl.size.Z + 0.1), CFrame.new(0, lvl.y + band, 0), C_GLASS, Enum.Material.Glass)
		end
	end
	return m
end

local function buildHighway(): Model
	local m = newModel("Autobahn")
	-- Footprint 1x2 -> 4 breit, 8 lang
	newPart(m, Vector3.new(CELL, 0.5, CELL * 2), CFrame.new(0, 0.25, 0), C_HWY)
	-- Gestrichelter Mittelstreifen
	for _, z in { -2.4, 0, 2.4 } do
		newPart(m, Vector3.new(0.4, 0.52, 1.4), CFrame.new(0, 0.26, z), C_LINE)
	end
	-- Leitplanken links/rechts
	newPart(m, Vector3.new(0.3, 0.8, CELL * 2), CFrame.new(-1.85, 0.65, 0), C_RAIL)
	newPart(m, Vector3.new(0.3, 0.8, CELL * 2), CFrame.new(1.85, 0.65, 0), C_RAIL)
	return m
end

local function buildAirport(): Model
	local m = newModel("Flughafen")
	-- Footprint 8x5 -> 32 breit (X), 20 tief (Z)
	-- Landebahn (Asphaltstreifen)
	newPart(m, Vector3.new(28, 0.4, 7), CFrame.new(0, 0.2, -4), C_STRIP)
	-- Gestrichelte Mittellinie der Landebahn
	for i = -3, 3 do
		newPart(m, Vector3.new(2, 0.42, 0.5), CFrame.new(i * 4, 0.21, -4), Color3.fromRGB(230, 230, 230))
	end
	-- Mini-Terminal
	newPart(m, Vector3.new(9, 4, 6), CFrame.new(-9, 2, 6.5), C_TERMINAL)
	newPart(m, Vector3.new(9.2, 0.4, 6.2), CFrame.new(-9, 4.2, 6.5), Color3.fromRGB(120, 130, 150))
	newPart(m, Vector3.new(1, 3, 1), CFrame.new(-13, 5.5, 6.5), Color3.fromRGB(120, 130, 150)) -- Tower
	-- Statisches Flugzeug (~6 Parts)
	local px, pz = 6, -4
	newPart(m, Vector3.new(2, 2, 12), CFrame.new(px, 2, pz), C_PLANE) -- Rumpf
	newPart(m, Vector3.new(12, 0.4, 3), CFrame.new(px, 2, pz), C_PLANE) -- Tragflaechen
	newPart(m, Vector3.new(5, 0.3, 1.6), CFrame.new(px, 2.4, pz - 5), C_PLANE) -- Hoehenleitwerk
	newPart(m, Vector3.new(0.4, 2.4, 2), CFrame.new(px, 3, pz - 5), C_PLANE) -- Seitenleitwerk
	newPart(m, Vector3.new(1.6, 1.6, 2), CFrame.new(px, 2, pz + 6), Color3.fromRGB(120, 205, 235)) -- Nase/Cockpit
	newPart(m, Vector3.new(1, 1, 2), CFrame.new(px, 1, pz + 2), Color3.fromRGB(60, 60, 65)) -- Fahrwerk
	return m
end

local function buildPark(): Model
	local m = newModel("Park")
	-- Rasenflaeche (1x1 Zelle)
	newPart(m, Vector3.new(CELL, 0.3, CELL), CFrame.new(0, 0.15, 0), C_GRASS, Enum.Material.Grass)
	-- Zwei Baeume: Stamm + Kugelkrone
	for _, pos in { Vector3.new(-1, 0, -0.8), Vector3.new(1.1, 0, 0.9) } do
		newPart(m, Vector3.new(0.4, 1.6, 0.4), CFrame.new(pos.X, 1.1, pos.Z), C_TRUNK)
		local crown = newPart(m, Vector3.new(1.6, 1.6, 1.6), CFrame.new(pos.X, 2.6, pos.Z), C_LEAF)
		crown.Shape = Enum.PartType.Ball
	end
	-- Parkbank
	newPart(m, Vector3.new(1.2, 0.5, 0.4), CFrame.new(0.2, 0.55, -0.9), Color3.fromRGB(140, 100, 60))
	return m
end

local function buildSubway(): Model
	local m = newModel("UBahnStation")
	-- Footprint 2x1 -> 8 breit (X), 4 tief (Z). Dunkler Vorplatz
	newPart(m, Vector3.new(8, 0.3, 4), CFrame.new(0, 0.15, 0), C_ROAD)
	-- Treppenabgang: dunkler Schacht mit Gelaendern
	newPart(m, Vector3.new(3, 0.4, 2), CFrame.new(-2, 0.35, 0), Color3.fromRGB(20, 20, 24))
	newPart(m, Vector3.new(3, 0.7, 0.2), CFrame.new(-2, 0.75, 1.05), C_RAIL)
	newPart(m, Vector3.new(3, 0.7, 0.2), CFrame.new(-2, 0.75, -1.05), C_RAIL)
	-- Eingangshaeuschen mit flachem Dach
	newPart(m, Vector3.new(3.4, 2.6, 3.4), CFrame.new(1.8, 1.6, 0), C_TERMINAL)
	newPart(m, Vector3.new(3.8, 0.3, 3.8), CFrame.new(1.8, 3.05, 0), Color3.fromRGB(120, 130, 150))
	-- Blaues U-Schild auf Mast
	newPart(m, Vector3.new(0.2, 2.6, 0.2), CFrame.new(-3.2, 1.6, 1.5), C_RAIL)
	local sign = newPart(m, Vector3.new(1.4, 1.4, 0.3), CFrame.new(-3.2, 3.4, 1.5), C_UBLUE, Enum.Material.Neon)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Text = "U"
		lbl.TextColor3 = Color3.new(1, 1, 1)
		lbl.TextScaled = true
		lbl.Font = Enum.Font.GothamBold
		lbl.Parent = gui
		gui.Parent = sign
	end
	return m
end

local function buildFactory(): Model
	local m = newModel("Fabrik")
	-- Footprint 3x2 -> 12 breit (X), 8 tief (Z). Halle
	newPart(m, Vector3.new(11, 5, 7), CFrame.new(0, 2.5, 0), C_FACTORY)
	-- Sheddach (Saegezahn) aus drei Keilen, Zaehne entlang X
	for i = -1, 1 do
		newWedge(m, Vector3.new(7, 1.8, 3.6), CFrame.new(i * 3.6, 5.9, 0) * CFrame.Angles(0, math.pi / 2, 0), C_ROOFDARK)
	end
	-- Schornstein + Lueftung
	newPart(m, Vector3.new(1, 6, 1), CFrame.new(4.5, 8, 2.5), C_BRICK)
	newPart(m, Vector3.new(1.4, 0.8, 1.4), CFrame.new(-4, 5.4, -2), C_RAIL)
	-- Tor
	newPart(m, Vector3.new(3, 2.6, 0.2), CFrame.new(0, 1.3, 3.55), Color3.fromRGB(70, 70, 75))
	return m
end

-- ----------------------------------------------------------------------------
-- Katalog
-- ----------------------------------------------------------------------------

Items.List = {
	{ id = "road", name = "Strasse", footprint = { w = 1, d = 1 }, price = 10, income = 0, residents = 0, isRoad = true, unlockPop = Config.Unlocks.Strasse, build = buildRoad },
	{ id = "house", name = "Wohnhaus", footprint = { w = 2, d = 2 }, price = 100, income = 5, residents = 4, isRoad = false, unlockPop = Config.Unlocks.Wohnhaus, build = buildHouse },
	{ id = "park", name = "Park", footprint = { w = 1, d = 1 }, price = 75, income = 0, residents = 2, isRoad = false, unlockPop = Config.Unlocks.Park, build = buildPark },
	{ id = "shop", name = "Geschaeft", footprint = { w = 2, d = 2 }, price = 250, income = 15, residents = 0, isRoad = false, unlockPop = Config.Unlocks.Geschaeft, build = buildShop },
	{ id = "tower", name = "Hochhaus", footprint = { w = 3, d = 3 }, price = 1000, income = 30, residents = 20, isRoad = false, unlockPop = Config.Unlocks.Hochhaus, build = buildTower },
	{ id = "subway", name = "U-Bahn-Station", footprint = { w = 2, d = 1 }, price = 750, income = 25, residents = 0, isRoad = false, unlockPop = Config.Unlocks.UBahn, build = buildSubway },
	{ id = "highway", name = "Autobahn", footprint = { w = 1, d = 2 }, price = 150, income = 0, residents = 0, isRoad = true, unlockPop = Config.Unlocks.Autobahn, build = buildHighway },
	{ id = "factory", name = "Fabrik", footprint = { w = 3, d = 2 }, price = 2000, income = 70, residents = 0, isRoad = false, unlockPop = Config.Unlocks.Fabrik, build = buildFactory },
	{ id = "airport", name = "Flughafen", footprint = { w = 8, d = 5 }, price = 10000, income = 250, residents = 0, isRoad = false, unlockPop = Config.Unlocks.Flughafen, build = buildAirport },
}

-- Schneller Zugriff per id
Items.ById = {}
for _, item in Items.List do
	Items.ById[item.id] = item
end

function Items.get(id: string)
	return Items.ById[id]
end

-- Footprint-Dimensionen unter Beruecksichtigung der Rotation (0..3 = 0/90/180/270 Grad).
-- Bei 90/270 Grad tauschen Breite und Tiefe.
function Items.footprintFor(item, rot: number): (number, number)
	local w, d = item.footprint.w, item.footprint.d
	if rot % 2 == 1 then
		return d, w
	end
	return w, d
end

return Items
