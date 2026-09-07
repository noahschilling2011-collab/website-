--[[
	TrafficController
	Der Verkehr auf der Rennstrecke - komplett clientseitig.

	Warum clientseitig: 22 Autos, die dauerhaft fahren, waeren serverseitig
	22 replizierte Objekte mit CFrame-Updates in jedem Frame, an jeden Spieler,
	fuer reine Kulisse. Das ist die teuerste Art, nichts zu erreichen.
	Vom Client gebaute Instanzen werden nie zum Server repliziert - der Verkehr
	kostet den Server exakt null und jeder sieht trotzdem dasselbe Bild, weil
	alle dieselbe Kurve aus TrackPath abfahren.

	Preis dieser Entscheidung: der Verkehr ist nicht synchron zwischen
	Spielern und man kann nicht mit ihm interagieren. Fuer Kulisse egal.
	Wenn du je willst, dass die Autos etwas TUN (Verfolgungsjagd, Hindernis),
	muss das auf den Server - dann aber mit deutlich weniger Autos.

	Fahrverhalten: drei Spuren, jede mit eigener Grundgeschwindigkeit.
	Innerhalb einer Spur haelt jedes Auto Abstand zum Vordermann und bremst,
	wenn es zu dicht wird. Dadurch entstehen Pulks und Luecken statt einer
	Perlenkette mit exakt gleichem Abstand.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TrackPath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TrackPath"))

local TrafficController = {}

-- Stellschraube: erste Zahl, die man runterdreht, wenn es auf Handys ruckelt.
local CARS_PER_LANE = 8
local MIN_GAP = 30 -- Studs, ab hier wird gebremst
local LANE_SPEEDS = { 74, 96, 122 } -- aussen langsam, innen schnell

local PALETTE = {
	Color3.fromRGB(232, 68, 62),
	Color3.fromRGB(58, 148, 232),
	Color3.fromRGB(245, 196, 62),
	Color3.fromRGB(238, 240, 246),
	Color3.fromRGB(52, 200, 158),
	Color3.fromRGB(178, 92, 240),
	Color3.fromRGB(38, 42, 52),
	Color3.fromRGB(255, 132, 40),
}

local function piece(model, name, size, offset, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = CFrame.new(offset)
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

-- Ein Verkehrsauto. Front zeigt nach -Z, passend zur LookVector der
-- Strecken-CFrame.
local function buildCar(color: Color3, folder: Instance)
	local model = Instance.new("Model")
	model.Name = "TrafficCar"

	local body = piece(model, "Body", Vector3.new(5, 1.7, 11.2), Vector3.new(0, 1.5, 0), color, Enum.Material.Metal)
	body.Reflectance = 0.08
	model.PrimaryPart = body

	piece(
		model,
		"Roof",
		Vector3.new(4.3, 1.5, 5.2),
		Vector3.new(0, 3, 0.7),
		color:Lerp(Color3.new(0, 0, 0), 0.35),
		Enum.Material.SmoothPlastic
	)
	piece(
		model,
		"Glass",
		Vector3.new(4.1, 1.2, 1.1),
		Vector3.new(0, 3, -2),
		Color3.fromRGB(26, 30, 40),
		Enum.Material.Glass
	)

	for _, x in { -2.6, 2.6 } do
		for _, z in { -3.4, 3.4 } do
			local wheel =
				piece(model, "Wheel", Vector3.new(0.9, 2.2, 2.2), Vector3.new(x, 1.1, z), Color3.fromRGB(20, 20, 24), Enum.Material.Rubber)
			wheel.Shape = Enum.PartType.Cylinder
		end
	end

	for _, x in { -1.6, 1.6 } do
		piece(
			model,
			"Head",
			Vector3.new(1.3, 0.5, 0.3),
			Vector3.new(x, 1.6, -5.7),
			Color3.fromRGB(255, 248, 220),
			Enum.Material.Neon
		)
		piece(
			model,
			"Tail",
			Vector3.new(1.3, 0.4, 0.3),
			Vector3.new(x, 1.7, 5.7),
			Color3.fromRGB(255, 48, 48),
			Enum.Material.Neon
		)
	end

	-- Leuchtspur hinter dem Auto. Bei Daemmerung macht das aus 22 fahrenden
	-- Kisten einen Streifen Licht, den man aus dem ganzen Hof sieht.
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(-2.1, -0.3, 5.5)
	a0.Parent = body
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(2.1, -0.3, 5.5)
	a1.Parent = body

	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.4
	trail.MinLength = 0
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Parent = body

	model.Parent = folder
	return model
end

function TrafficController.Start()
	if TrafficController._running then
		return TrafficController
	end
	TrafficController._running = true

	-- Vom Client erzeugt: existiert nur lokal, wird nie repliziert.
	local folder = Instance.new("Folder")
	folder.Name = "LocalTraffic"
	folder.Parent = Workspace

	local lanes = {}
	local paletteIndex = 0

	for laneIndex, laneOffset in TrackPath.LANES do
		local cars = {}
		local spacing = TrackPath.LENGTH / CARS_PER_LANE
		for i = 1, CARS_PER_LANE do
			paletteIndex += 1
			local color = PALETTE[(paletteIndex - 1) % #PALETTE + 1]
			local base = LANE_SPEEDS[laneIndex] or 90
			cars[i] = {
				model = buildCar(color, folder),
				-- Versatz je Spur, damit die Spuren nicht in Reih und Glied stehen.
				s = (i - 1) * spacing + laneIndex * 19,
				speed = base,
				target = base * (0.88 + math.random() * 0.26),
				offset = laneOffset,
			}
		end
		lanes[laneIndex] = cars
	end

	TrafficController._folder = folder
	TrafficController._lanes = lanes

	TrafficController._connection = RunService.Heartbeat:Connect(function(dt)
		-- Grosse dt-Werte (Tab war im Hintergrund) wuerden Autos durch den
		-- Vordermann teleportieren. Deckeln.
		local step = math.min(dt, 0.1)
		for _, cars in lanes do
			local count = #cars
			for i, car in cars do
				-- Vordermann ist der naechsthoehere Index, mit Umlauf.
				local leader = cars[i % count + 1]
				local gap = (leader.s - car.s) % TrackPath.LENGTH
				local desired = car.target
				if gap < MIN_GAP then
					desired = math.min(desired, leader.speed * (gap / MIN_GAP))
				end
				car.speed += (desired - car.speed) * math.min(1, step * 3)
				car.s = (car.s + car.speed * step) % TrackPath.LENGTH

				local base = TrackPath.At(car.s)
				-- Kurvenneigung: Vergleich mit einem Punkt vier Studs voraus.
				-- Positiv = Rechtskurve, das Auto legt sich nach innen.
				local ahead = TrackPath.At(car.s + 4)
				local turn = base.RightVector:Dot(ahead.LookVector)
				car.model:PivotTo(base * CFrame.new(car.offset, 0, 0) * CFrame.Angles(0, 0, -turn * 0.4))
			end
		end
	end)

	return TrafficController
end

-- Notausschalter. Blendet den Verkehr aus und stoppt die Schleife; ein
-- erneutes Einschalten baut ihn wieder auf.
function TrafficController.SetEnabled(enabled: boolean)
	if enabled then
		if not TrafficController._running then
			TrafficController.Start()
		elseif TrafficController._folder then
			TrafficController._folder.Parent = Workspace
		end
		return
	end
	if TrafficController._connection then
		TrafficController._connection:Disconnect()
		TrafficController._connection = nil
	end
	if TrafficController._folder then
		TrafficController._folder:Destroy()
		TrafficController._folder = nil
	end
	TrafficController._lanes = nil
	TrafficController._running = false
end

return TrafficController
