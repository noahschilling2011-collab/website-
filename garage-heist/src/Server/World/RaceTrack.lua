--[[
	RaceTrack
	Baut alles ausserhalb der Garagen:

	1. Eine erhoehte Rennstrecke (Stadionoval, 44 Studs hoch) rund um den
	   Garagenhof. Fahrbahn, Leitplanken, Neonkante, Stuetzpfeiler, zwei
	   Torbogen mit Schriftzug an den Enden des Hofs.
	2. Deckung im Hof: Container, Rampen, Leitplanken, Lichtmasten.

	Punkt 2 ist der eigentliche Spielbaustein. Der Hof war vorher eine
	leere Asphaltflaeche von 900 x 620 - waehrend des Klau-Fensters heisst
	das freie Sichtlinie ueber die ganze Karte und Rempeln ohne Gegenwehr.
	Container brechen die Sichtlinien, Rampen geben Hoehe. Die Flaechen
	direkt vor den Toren (z zwischen -30 und 30) bleiben frei, damit
	niemand vor der eigenen Ausfahrt haengenbleibt.

	Die Strecke selbst ist reine Kulisse: kein CanCollide, kein Gameplay.
	Die Autos darauf baut jeder Client fuer sich (TrafficController), damit
	nichts davon ueber das Netzwerk repliziert wird.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrackPath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TrackPath"))

local RaceTrack = {}

local C = {
	road = Color3.fromRGB(30, 32, 38),
	roadEdge = Color3.fromRGB(196, 200, 210),
	rail = Color3.fromRGB(88, 94, 104),
	neon = Color3.fromRGB(56, 214, 255),
	neonWarm = Color3.fromRGB(245, 166, 35),
	pillar = Color3.fromRGB(62, 66, 74),
	container = {
		Color3.fromRGB(158, 62, 54),
		Color3.fromRGB(46, 96, 128),
		Color3.fromRGB(196, 148, 44),
		Color3.fromRGB(64, 108, 78),
		Color3.fromRGB(72, 76, 86),
	},
	steel = Color3.fromRGB(126, 132, 142),
	dark = Color3.fromRGB(20, 21, 26),
}

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Color = props.Color or C.rail
	p.Material = props.Material or Enum.Material.Concrete
	p.Name = props.Name or "Part"
	p.CanCollide = if props.CanCollide ~= nil then props.CanCollide else false
	p.CastShadow = if props.CastShadow ~= nil then props.CastShadow else false
	p.Transparency = props.Transparency or 0
	p.Parent = props.Parent
	return p
end

-- Fahrbahn, Planken, Neonkante ------------------------------------------
local function buildRoad(folder)
	local width = TrackPath.ROAD_WIDTH
	for _, span in TrackPath.BuildSpans(14) do
		local cf = TrackPath.At(span.s)

		part({
			Name = "Road",
			Size = Vector3.new(width, 1.6, span.len),
			CFrame = cf,
			Color = C.road,
			Material = Enum.Material.Asphalt,
			CastShadow = true,
			Parent = folder,
		})

		for _, side in { -1, 1 } do
			part({
				Name = "Rail",
				Size = Vector3.new(1.1, 3.2, span.len),
				CFrame = cf * CFrame.new(side * (width / 2 + 0.5), 1.6, 0),
				Color = C.rail,
				Material = Enum.Material.Metal,
				Parent = folder,
			})
			-- Leuchtende Oberkante. Das ist aus dem Hof heraus das Einzige,
			-- was man von der Strecke im Detail erkennt - deshalb bekommt
			-- sie die Aufmerksamkeit und nicht die Fahrbahn.
			part({
				Name = "RailGlow",
				Size = Vector3.new(1.3, 0.35, span.len),
				CFrame = cf * CFrame.new(side * (width / 2 + 0.5), 3.35, 0),
				Color = side < 0 and C.neon or C.neonWarm,
				Material = Enum.Material.Neon,
				Parent = folder,
			})
		end

		-- Randmarkierung auf der Fahrbahn
		for _, side in { -1, 1 } do
			part({
				Name = "EdgeLine",
				Size = Vector3.new(0.9, 0.08, span.len),
				CFrame = cf * CFrame.new(side * (width / 2 - 1.6), 0.84, 0),
				Color = C.roadEdge,
				Material = Enum.Material.SmoothPlastic,
				Parent = folder,
			})
		end

		-- Unterseite: dunkler Traeger, damit die Fahrbahn von unten nicht
		-- wie ein schwebendes Brett aussieht.
		part({
			Name = "Girder",
			Size = Vector3.new(width - 4, 2.2, span.len),
			CFrame = cf * CFrame.new(0, -1.9, 0),
			Color = C.dark,
			Material = Enum.Material.Metal,
			Parent = folder,
		})
	end

	-- Mittelstriche nur auf den Geraden: auf den Boegen waeren es hundert
	-- zusaetzliche Parts fuer einen Effekt, den niemand sieht.
	local dashStep = 26
	for _, seg in TrackPath.Segments do
		if seg.kind == "line" then
			-- Direkt entlang der Geraden laufen statt den Startversatz aus
			-- BuildSpans zurueckzurechnen.
			for offset = 8, seg.len - 8, dashStep do
				local pos2 = seg.from + seg.dir * offset
				local point = Vector3.new(pos2.X, TrackPath.HEIGHT + 0.85, pos2.Y)
				local look = point + Vector3.new(seg.dir.X, 0, seg.dir.Y)
				for _, lane in { -4.75, 4.75 } do
					part({
						Name = "Dash",
						Size = Vector3.new(0.7, 0.08, 12),
						CFrame = CFrame.lookAt(point, look) * CFrame.new(lane, 0, 0),
						Color = C.roadEdge,
						Material = Enum.Material.SmoothPlastic,
						Parent = folder,
					})
				end
			end
		end
	end
end

local function buildPillars(folder)
	local step = 62
	local count = math.floor(TrackPath.LENGTH / step)
	for i = 0, count - 1 do
		local cf = TrackPath.At(i * step)
		local pos = cf.Position
		local height = TrackPath.HEIGHT - 3.2

		part({
			Name = "PillarCap",
			Size = Vector3.new(TrackPath.ROAD_WIDTH + 5, 2.4, 6),
			CFrame = cf * CFrame.new(0, -3.4, 0),
			Color = C.pillar,
			Material = Enum.Material.Concrete,
			CastShadow = true,
			Parent = folder,
		})
		part({
			Name = "Pillar",
			Size = Vector3.new(7, height, 7),
			CFrame = CFrame.new(pos.X, height / 2, pos.Z),
			Color = C.pillar,
			Material = Enum.Material.Concrete,
			CanCollide = true,
			CastShadow = true,
			Parent = folder,
		})
		part({
			Name = "PillarFoot",
			Size = Vector3.new(11, 1.6, 11),
			CFrame = CFrame.new(pos.X, 0.8, pos.Z),
			Color = C.dark,
			Material = Enum.Material.Concrete,
			Parent = folder,
		})
		-- Schmaler Leuchtstreifen die Saeule hoch. Bei Daemmerung zieht das
		-- den Blick nach oben zur Strecke.
		part({
			Name = "PillarGlow",
			Size = Vector3.new(0.5, height - 6, 0.5),
			CFrame = CFrame.new(pos.X, height / 2, pos.Z + 3.6),
			Color = C.neon,
			Material = Enum.Material.Neon,
			Parent = folder,
		})
	end
end

-- Zwei Torbogen an den Enden der Hofachse. Der Hof laeuft in X, also blickt
-- man aus dem Hof genau auf x = +/-265 - dort steht der Schriftzug.
local function buildGantries(folder)
	for _, side in { -1, 1 } do
		local x = side * TrackPath.HALF_LENGTH
		local towerHeight = TrackPath.HEIGHT + 22

		for _, zSide in { -1, 1 } do
			part({
				Name = "GantryTower",
				Size = Vector3.new(6, towerHeight, 6),
				CFrame = CFrame.new(x, towerHeight / 2, zSide * (TrackPath.ROAD_WIDTH / 2 + 6)),
				Color = C.pillar,
				Material = Enum.Material.Metal,
				CanCollide = true,
				CastShadow = true,
				Parent = folder,
			})
		end

		local beamY = TrackPath.HEIGHT + 17
		part({
			Name = "GantryBeam",
			Size = Vector3.new(6, 9, TrackPath.ROAD_WIDTH + 18),
			CFrame = CFrame.new(x, beamY, 0),
			Color = C.dark,
			Material = Enum.Material.Metal,
			CastShadow = true,
			Parent = folder,
		})
		part({
			Name = "GantryGlow",
			Size = Vector3.new(6.4, 0.6, TrackPath.ROAD_WIDTH + 18),
			CFrame = CFrame.new(x, beamY - 4.8, 0),
			Color = C.neonWarm,
			Material = Enum.Material.Neon,
			Parent = folder,
		})

		local board = part({
			Name = "GantrySign",
			Size = Vector3.new(0.4, 8, TrackPath.ROAD_WIDTH + 16),
			CFrame = CFrame.new(x - side * 3.3, beamY, 0),
			Color = C.dark,
			Material = Enum.Material.SmoothPlastic,
			Parent = folder,
		})
		local gui = Instance.new("SurfaceGui")
		-- Nach innen zum Hof: -X-Seite bei side = 1, +X-Seite bei side = -1.
		gui.Face = side > 0 and Enum.NormalId.Left or Enum.NormalId.Right
		gui.CanvasSize = Vector2.new(900, 160)
		gui.LightInfluence = 0
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.Michroma
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(245, 166, 35)
		label.Text = "GARAGE HEIST"
		label.Parent = gui
	end
end

-- Deckung im Hof --------------------------------------------------------
-- Plotmitten liegen bei x = -140, -84, -28, 28, 84, 140. Alles hier steht in
-- den Luecken dazwischen und bleibt bei |z| <= 22, damit vor jedem Tor
-- mindestens 30 Studs frei bleiben.
local CONTAINERS = {
	{ x = -112, z = -16, rot = 0, stack = 1 },
	{ x = -84, z = 14, rot = 90, stack = 1 },
	{ x = -56, z = -18, rot = 0, stack = 2 },
	{ x = -14, z = 16, rot = 90, stack = 1 },
	{ x = 14, z = -16, rot = 90, stack = 1 },
	{ x = 56, z = 18, rot = 0, stack = 2 },
	{ x = 84, z = -14, rot = 90, stack = 1 },
	{ x = 112, z = 16, rot = 0, stack = 1 },
	-- Nicht auf z = 0: seit die Werkhalle bei x = -252..-178 steht, laeuft jeder
	-- neue Spieler genau hier heraus. Auf der Achse stand die Kiste 5 Studs vor
	-- dem Ausgang und hat den Blick in den Hof zugemauert. Seitlich versetzt ist
	-- sie Deckung statt Wand.
	{ x = -168, z = -16, rot = 90, stack = 2 },
	{ x = 168, z = 0, rot = 90, stack = 2 },
}

local function buildYard(folder)
	for index, spec in CONTAINERS do
		local color = C.container[(index - 1) % #C.container + 1]
		local rotation = CFrame.Angles(0, math.rad(spec.rot), 0)
		for level = 1, spec.stack do
			local y = 5.2 + (level - 1) * 10.4
			local body = part({
				Name = "Container",
				Size = Vector3.new(28, 10, 10),
				CFrame = CFrame.new(spec.x, y, spec.z) * rotation,
				Color = level > 1 and color:Lerp(Color3.new(0, 0, 0), 0.2) or color,
				Material = Enum.Material.CorrodedMetal,
				CanCollide = true,
				CastShadow = true,
				Parent = folder,
			})
			-- Rippen laengs: ohne die ist ein Container eine bunte Kiste.
			for i = -3, 3 do
				part({
					Name = "ContainerRib",
					Size = Vector3.new(0.5, 9.4, 10.3),
					CFrame = body.CFrame * CFrame.new(i * 3.6, 0, 0),
					Color = color:Lerp(Color3.new(0, 0, 0), 0.35),
					Material = Enum.Material.Metal,
					Parent = folder,
				})
			end
		end

		-- Rampe an jeden zweiten Container: erst dadurch wird die Deckung zu
		-- einer Entscheidung ("oben rum oder aussen rum") statt zu einer Wand.
		if index % 2 == 1 then
			local ramp = Instance.new("WedgePart")
			ramp.Name = "Ramp"
			ramp.Anchored = true
			ramp.CanCollide = true
			ramp.CastShadow = false
			ramp.Size = Vector3.new(9, 10.2, 16)
			ramp.CFrame = CFrame.new(spec.x, 5.1, spec.z) * rotation * CFrame.new(0, 0, 20)
			ramp.Color = C.steel
			ramp.Material = Enum.Material.DiamondPlate
			ramp.Parent = folder
		end
	end

	-- Leitplanken quer: kurze Sichtblocker auf Huefthoehe.
	for _, spec in { { x = -28, z = 0 }, { x = 28, z = 0 }, { x = -140, z = 6 }, { x = 140, z = -6 } } do
		part({
			Name = "Barrier",
			Size = Vector3.new(16, 4, 2.4),
			CFrame = CFrame.new(spec.x, 2, spec.z),
			Color = Color3.fromRGB(178, 180, 186),
			Material = Enum.Material.Concrete,
			CanCollide = true,
			CastShadow = true,
			Parent = folder,
		})
		part({
			Name = "BarrierStripe",
			Size = Vector3.new(16.2, 0.5, 2.6),
			CFrame = CFrame.new(spec.x, 3.4, spec.z),
			Color = C.neonWarm,
			Material = Enum.Material.Neon,
			Parent = folder,
		})
	end

	-- Lichtmasten. Vier Stueck, mit echtem Licht - das ist der Unterschied
	-- zwischen "dunkler Hof" und "beleuchtetes Gelaende".
	-- Der westliche Mast stand urspruenglich bei (-196, 0). Dort steht seit
	-- diesem Stand die Werkhalle: ein 34 Studs hoher Betonmast waere mitten
	-- durch Boden, Laufweg und Dach gegangen. Die Halle bringt eigenes Licht
	-- mit, also rueckt der Mast nach draussen an den westlichen Hofrand und
	-- leuchtet dort den Weg vom Hallenausgang zu den ersten Boxen aus.
	for _, spec in { { x = -130, z = 30 }, { x = 196, z = 0 }, { x = 0, z = -40 }, { x = 0, z = 40 } } do
		part({
			Name = "MastPole",
			Size = Vector3.new(2.2, 34, 2.2),
			CFrame = CFrame.new(spec.x, 17, spec.z),
			Color = C.pillar,
			Material = Enum.Material.Metal,
			CanCollide = true,
			CastShadow = true,
			Parent = folder,
		})
		local head = part({
			Name = "MastHead",
			Size = Vector3.new(11, 1.6, 5),
			CFrame = CFrame.new(spec.x, 34.4, spec.z),
			Color = Color3.fromRGB(255, 244, 214),
			Material = Enum.Material.Neon,
			Parent = folder,
		})
		local lamp = Instance.new("SurfaceLight")
		lamp.Face = Enum.NormalId.Bottom
		lamp.Angle = 130
		lamp.Range = 90
		lamp.Brightness = 2.6
		lamp.Shadows = false
		lamp.Color = Color3.fromRGB(255, 240, 208)
		lamp.Parent = head
	end
end

function RaceTrack.Build(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "RaceTrack"
	folder.Parent = parent

	buildRoad(folder)
	buildPillars(folder)
	buildGantries(folder)

	local yard = Instance.new("Folder")
	yard.Name = "Yard"
	yard.Parent = parent
	buildYard(yard)

	return folder
end

return RaceTrack
