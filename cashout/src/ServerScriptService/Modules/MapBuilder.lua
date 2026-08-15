--[[
	MapBuilder.lua

	Baut die Map aus Parts. Keine externen Modelle, keine Asset-Ids.
	Seit Phase 4 Nachtstadt statt Baseplate (Dokument 4.1): dunkle, nasse
	Grundflaeche, kaum Umgebungslicht, alles Wichtige leuchtet selbst. Das
	Grundlicht wird hier gesetzt und repliziert; die Heat-Reaktion aus 4.3 ist
	clientseitig und steht in UI/Atmosphere.lua.

	Geometrie nach 4.4: Bank zentral und hoch, fuenf Terminals ringfoermig am
	Rand, das beste am weitesten weg. Die Ringradien stehen in Balance.Map --
	Rang 5 liegt bei 144 Studs, das sind die 18 s Bank-Rundweg.

	Uebergabepunkte entstehen zur Laufzeit (OrderService) und werden hier nur
	gebaut und wieder abgeraeumt, damit alles Geometrische an einer Stelle
	bleibt.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared:WaitForChild("Assets"))
local Balance = require(Shared:WaitForChild("Balance"))

local MapBuilder = {}

local terminals: { [string]: any } = {}
local terminalOrder: { any } = {}
local bank: any = nil
local deliveryFolder: Folder? = nil
local raidFolder: Folder? = nil
local beam: BasePart? = nil
local built = false

local COLOR_GROUND = Color3.fromRGB(52, 56, 62)
local COLOR_STRUCTURE = Color3.fromRGB(96, 100, 108)
local COLOR_TERMINAL = Color3.fromRGB(120, 128, 140)
-- Gold ist laut 4.2 fuer Banked reserviert -- die Bank traegt es zu Recht.
local COLOR_BANK = Color3.fromRGB(255, 200, 60)
-- Cyan ist laut 4.2 der eigene Uebergabepunkt.
local COLOR_DELIVERY = Color3.fromRGB(80, 220, 235)
-- Rot ist laut 4.2 ausschliesslich Gefahr. Der Sperrkreis ist der erste Ort im
-- Spiel, an dem es ueberhaupt auftauchen darf.
local COLOR_DANGER = Color3.fromRGB(255, 60, 60)

-- ------------------------------------------------------------------ intern --

local function newPart(name: string, size: Vector3, position: Vector3, color: Color3, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function addLabel(adornee: BasePart, title: string, subtitle: string, height: number, color: Color3)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(240, 56)
	billboard.StudsOffset = Vector3.new(0, height, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 400
	billboard.Adornee = adornee
	billboard.Parent = adornee

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0.6, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = color
	titleLabel.TextStrokeTransparency = 0.4
	titleLabel.Text = title
	titleLabel.Parent = billboard

	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "Subtitle"
	subLabel.Position = UDim2.new(0, 0, 0.6, 0)
	subLabel.Size = UDim2.new(1, 0, 0.4, 0)
	subLabel.BackgroundTransparency = 1
	subLabel.Font = Enum.Font.Gotham
	subLabel.TextScaled = true
	subLabel.TextColor3 = Color3.fromRGB(184, 192, 200)
	subLabel.TextStrokeTransparency = 0.6
	subLabel.Text = subtitle
	subLabel.Parent = billboard
end

--[[
	Decal nur anlegen, wenn in Assets.lua wirklich eine Id steht.
]]
local function addDecal(part: BasePart, assetId: string, face: Enum.NormalId)
	if assetId == "" then
		return
	end
	local decal = Instance.new("Decal")
	decal.Texture = assetId
	decal.Face = face
	decal.Parent = part
end

local function addPrompt(part: BasePart, actionText: string, objectText: string, maxDistance: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = maxDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	return prompt
end

-- -------------------------------------------------------------------- Bauen --

--[[
	Nachtstadt nach 4.1. Wenig Umgebungslicht, damit die Farbcodes aus 4.2
	tragen -- alles Wichtige im Spiel ist Neon und leuchtet selbst.
]]
local function setupLighting()
	Lighting.ClockTime = 0
	Lighting.Brightness = 1
	Lighting.Ambient = Color3.fromRGB(24, 26, 34)
	Lighting.OutdoorAmbient = Color3.fromRGB(28, 30, 40)
	Lighting.EnvironmentDiffuseScale = 0.2
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
	Lighting.FogEnd = 600
	Lighting.FogStart = 120
	Lighting.FogColor = Color3.fromRGB(14, 16, 22)

	local existing = Lighting:FindFirstChild("CashoutAtmosphere")
	if existing then
		existing:Destroy()
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "CashoutAtmosphere"
	atmosphere.Density = 0.42
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(70, 78, 96)
	atmosphere.Decay = Color3.fromRGB(30, 34, 46)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.6
	atmosphere.Parent = Lighting
end

local function buildGround(root: Instance)
	local size = Balance.Map.GroundSize
	local ground = newPart(
		"Ground",
		size,
		Vector3.new(0, Balance.Map.GroundY - size.Y / 2, 0),
		COLOR_GROUND,
		root
	)
	-- Nass: der Boden spiegelt, was leuchtet. Das ist der ganze Regen-Effekt
	-- aus 4.1 -- ohne Partikel, die auf schwacher Hardware nichts kosten sollen.
	ground.Material = Enum.Material.Slate
	ground.Reflectance = 0.25
end

--[[
	Deckungen nach 4.4: einzeln stehende Bloecke auf einer Spirale, mit
	Mindestabstand zu allem, was man ansprechen kann. Einzelne Bloecke, damit
	im 40-Studs-Radius einer Razzia keine Sackgasse entstehen kann.
]]
local function buildCover(root: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Cover"
	folder.Parent = root

	local size = Balance.Map.CoverSize
	local count = Balance.Map.CoverCount
	local minRadius = Balance.Map.CoverMinRadius
	local maxRadius = Balance.Map.CoverMaxRadius
	local clearance = Balance.Map.CoverClearance
	-- Goldener Winkel: verteilt gleichmaessig, ohne Muster und ohne Zufall.
	local goldenAngle = math.pi * (3 - math.sqrt(5))

	local avoid = { Balance.Map.BankPosition, Balance.Map.SpawnPosition }
	for _, terminal in ipairs(terminalOrder) do
		table.insert(avoid, terminal.Position)
	end

	local placed = 0
	for index = 1, count * 3 do
		if placed >= count then
			break
		end

		local t = (index - 0.5) / (count * 3)
		local radius = minRadius + (maxRadius - minRadius) * math.sqrt(t)
		local angle = index * goldenAngle
		local position = Vector3.new(math.cos(angle) * radius, Balance.Map.GroundY, math.sin(angle) * radius)

		local tooClose = false
		for _, other in ipairs(avoid) do
			local flat = Vector3.new(position.X - other.X, 0, position.Z - other.Z)
			if flat.Magnitude < clearance then
				tooClose = true
				break
			end
		end

		if not tooClose then
			local block = newPart(
				"Cover" .. placed,
				size,
				position + Vector3.new(0, size.Y / 2, 0),
				COLOR_STRUCTURE,
				folder
			)
			block.Material = Enum.Material.Brick
			table.insert(avoid, position)
			placed += 1
		end
	end
end

local function buildSpawn(root: Instance)
	local spawnPoint = Instance.new("SpawnLocation")
	spawnPoint.Name = "CashoutSpawn"
	spawnPoint.Size = Balance.Map.SpawnSize
	spawnPoint.Position = Balance.Map.SpawnPosition
		+ Vector3.new(0, Balance.Map.GroundY + Balance.Map.SpawnSize.Y / 2, 0)
	spawnPoint.Anchored = true
	spawnPoint.CanCollide = true
	spawnPoint.Color = COLOR_STRUCTURE
	spawnPoint.Material = Enum.Material.Metal
	spawnPoint.Neutral = true
	spawnPoint.Duration = 0
	spawnPoint.TopSurface = Enum.SurfaceType.Smooth
	spawnPoint.Parent = root
end

local function buildBank(root: Instance)
	local model = Instance.new("Model")
	model.Name = "Bank"
	model.Parent = root

	local base = Balance.Map.BankPosition + Vector3.new(0, Balance.Map.GroundY, 0)

	local plinthSize = Balance.Map.BankPlinthSize
	local plinth = newPart("Plinth", plinthSize, base + Vector3.new(0, plinthSize.Y / 2, 0), COLOR_STRUCTURE, model)
	plinth.Material = Enum.Material.Metal

	local towerSize = Balance.Map.BankTowerSize
	local tower = newPart(
		"Tower",
		towerSize,
		base + Vector3.new(0, plinthSize.Y + towerSize.Y / 2, 0),
		COLOR_BANK,
		model
	)
	tower.Material = Enum.Material.Neon

	local counterSize = Balance.Map.BankCounterSize
	local counter = newPart(
		"Counter",
		counterSize,
		base + Balance.Map.BankCounterOffset,
		COLOR_BANK,
		model
	)
	counter.Material = Enum.Material.Neon
	addDecal(counter, Assets.Images.BankSign, Enum.NormalId.Front)

	model.PrimaryPart = counter

	addLabel(tower, "BANK", "Einzahlen: " .. Balance.Bank.DepositSeconds .. " s", towerSize.Y / 2 + 6, COLOR_BANK)
	local prompt = addPrompt(counter, "Einzahlen", "Bank", Balance.Bank.PromptDistance)
	prompt.Enabled = false

	bank = {
		Model = model,
		Part = counter,
		Position = counter.Position,
		Prompt = prompt,
	}
end

local function buildTerminals(root: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Terminals"
	folder.Parent = root

	local radii = Balance.Map.TerminalRadii
	local count = #radii
	local size = Balance.Map.TerminalSize
	local startAngle = math.rad(Balance.Map.TerminalStartAngleDegrees)

	for rank = 1, count do
		local id = "T" .. rank
		local angle = startAngle + (rank - 1) * (2 * math.pi / count)
		local radius = radii[rank]
		local basePosition = Balance.Map.BankPosition
			+ Vector3.new(math.cos(angle) * radius, Balance.Map.GroundY, math.sin(angle) * radius)

		local model = Instance.new("Model")
		model.Name = "Terminal" .. rank
		model.Parent = folder

		local pillar = newPart(
			"Pillar",
			size,
			basePosition + Vector3.new(0, size.Y / 2, 0),
			COLOR_STRUCTURE,
			model
		)

		local screen = newPart(
			"Screen",
			Vector3.new(size.X + 0.4, 3.2, 0.6),
			basePosition + Vector3.new(0, size.Y - 2, size.Z / 2 + 0.3),
			COLOR_TERMINAL,
			model
		)
		screen.Material = Enum.Material.Neon
		screen.CanCollide = false
		addDecal(screen, Assets.Images.TerminalScreen, Enum.NormalId.Front)

		model.PrimaryPart = pillar
		model:SetAttribute("TerminalId", id)

		addLabel(
			pillar,
			"TERMINAL " .. rank,
			string.format("%d Studs zur Bank", math.floor(radius + 0.5)),
			size.Y / 2 + 2,
			Color3.fromRGB(230, 236, 242)
		)
		local prompt = addPrompt(pillar, "Auftraege ansehen", "Terminal " .. rank, Balance.Orders.PromptDistance)
		prompt.Enabled = false

		local terminal = {
			Id = id,
			Rank = rank,
			Radius = radius,
			Model = model,
			Part = pillar,
			Position = pillar.Position,
			Prompt = prompt,
		}
		terminals[id] = terminal
		table.insert(terminalOrder, terminal)
	end
end

--[[
	Baut die Map. Idempotent -- ein zweiter Aufruf tut nichts.
]]
function MapBuilder.Start()
	if built then
		return
	end
	built = true

	local existing = workspace:FindFirstChild("CashoutMap")
	if existing then
		existing:Destroy()
	end

	-- Die Studio-Vorlage bringt Baseplate und SpawnLocation mit. Beide liegen
	-- genau auf unserem Boden. Nur diese beiden, nichts sonst aus Workspace.
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate:Destroy()
	end
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end

	local root = Instance.new("Folder")
	root.Name = "CashoutMap"
	root.Parent = workspace

	deliveryFolder = Instance.new("Folder")
	deliveryFolder.Name = "DeliveryPoints"
	deliveryFolder.Parent = root

	raidFolder = Instance.new("Folder")
	raidFolder.Name = "RaidRings"
	raidFolder.Parent = root

	setupLighting()
	buildGround(root)
	buildSpawn(root)
	buildBank(root)
	buildTerminals(root)
	buildCover(root)

	-- Einzahl-Beam (Dokument 5): steht immer, ist nur meistens unsichtbar.
	local beamSize = Balance.Map.BeamSize
	beam = newPart(
		"DepositBeam",
		beamSize,
		Balance.Map.BankPosition + Vector3.new(0, Balance.Map.GroundY + beamSize.Y / 2, 0),
		Color3.fromRGB(255, 255, 255),
		root
	)
	beam.Material = Enum.Material.Neon
	beam.CanCollide = false
	beam.CanQuery = false
	beam.Transparency = 1
end

--[[
	Weisse Saeule von der Bank in den Himmel, solange irgendjemand einzahlt.
	Weiss ist laut 4.2 genau dafuer reserviert -- gleichzeitig Anzeige,
	Belohnung und PvP-Einladung.
]]
function MapBuilder.SetDepositBeam(visible: boolean)
	if beam then
		beam.Transparency = if visible then Balance.Map.BeamTransparency else 1
	end
end

-- ------------------------------------------------------- Uebergabepunkte --

--[[
	Baut einen Uebergabepunkt an einer Position. Der Prompt bleibt aus, bis
	OrderService ihn freigibt -- damit kann niemand fremde Punkte ausloesen,
	bevor die Besitzpruefung greift.

	Rueckgabe: das Model. Prompt haengt an model.PrimaryPart.
]]
function MapBuilder.CreateDeliveryPoint(position: Vector3, label: string, tierColor: Color3)
	assert(deliveryFolder, "MapBuilder.Start() zuerst aufrufen")

	local model = Instance.new("Model")
	model.Name = "DeliveryPoint"
	model.Parent = deliveryFolder

	local padSize = Balance.Map.DeliveryPadSize
	local pad = newPart(
		"Pad",
		padSize,
		Vector3.new(position.X, Balance.Map.GroundY + padSize.Y / 2, position.Z),
		COLOR_DELIVERY,
		model
	)
	pad.CanCollide = false
	pad.Transparency = 0.35
	pad.Material = Enum.Material.Neon

	local pillarSize = Balance.Map.DeliveryPillarSize
	local pillar = newPart(
		"Pillar",
		pillarSize,
		Vector3.new(position.X, Balance.Map.GroundY + pillarSize.Y / 2, position.Z),
		tierColor,
		model
	)
	pillar.CanCollide = false
	pillar.Transparency = 0.25
	pillar.Material = Enum.Material.Neon

	model.PrimaryPart = pad

	addLabel(pillar, "UEBERGABE", label, pillarSize.Y / 2 + 2, COLOR_DELIVERY)

	local prompt = addPrompt(pad, "Uebergeben", "Uebergabepunkt", Balance.Orders.PromptDistance)
	prompt.Enabled = false

	return {
		Model = model,
		Part = pad,
		Position = pad.Position,
		Prompt = prompt,
	}
end

--[[
	Loescht alle Uebergabepunkte. Wird beim Rundenwechsel aufgerufen, damit
	kein Punkt eine Runde ueberlebt -- auch keiner, dessen Besitzer den Server
	verlassen hat.
]]
function MapBuilder.ClearDeliveryPoints()
	if not deliveryFolder then
		return
	end
	for _, child in ipairs(deliveryFolder:GetChildren()) do
		child:Destroy()
	end
end

-- ------------------------------------------------------------- Sperrkreis --

--[[
	Baut den Sperrkreis einer Razzia an einer Position.

	Zwei flache Zylinder uebereinander:
	  Zone  -- steht still auf Balance.Heat.RaidRingRadius und markiert die
	           Grenze, die der Spieler ueberqueren muss.
	  Timer -- schrumpft in Balance.Heat.RaidRingSeconds linear auf null und
	           ist damit die ablesbare Restzeit (Dokument 5: hier darf nichts
	           easen).

	Ohne die stehende Zone waere der Kreis nicht spielbar: der schrumpfende
	Zylinder sagt WANN, aber nicht WOHIN.
]]
function MapBuilder.CreateRaidRing(position: Vector3)
	assert(raidFolder, "MapBuilder.Start() zuerst aufrufen")

	local model = Instance.new("Model")
	model.Name = "RaidRing"
	model.Parent = raidFolder

	local diameter = Balance.Heat.RaidRingRadius * 2
	local center = Vector3.new(position.X, Balance.Map.GroundY + Balance.Map.RaidRingHeight / 2, position.Z)

	-- Zylinder liegen in Roblox entlang X; Orientation kippt die Achse nach oben.
	local zone = newPart(
		"Zone",
		Vector3.new(Balance.Map.RaidRingHeight, diameter, diameter),
		center,
		COLOR_DANGER,
		model
	)
	zone.Shape = Enum.PartType.Cylinder
	zone.Orientation = Vector3.new(0, 0, 90)
	zone.Material = Enum.Material.Neon
	zone.Transparency = Balance.Map.RaidZoneTransparency
	zone.CanCollide = false
	zone.CanQuery = false

	local timer = newPart(
		"Timer",
		Vector3.new(Balance.Map.RaidRingHeight * 1.2, diameter, diameter),
		center,
		COLOR_DANGER,
		model
	)
	timer.Shape = Enum.PartType.Cylinder
	timer.Orientation = Vector3.new(0, 0, 90)
	timer.Material = Enum.Material.Neon
	timer.Transparency = Balance.Map.RaidTimerTransparency
	timer.CanCollide = false
	timer.CanQuery = false

	model.PrimaryPart = zone

	return {
		Model = model,
		Zone = zone,
		Timer = timer,
		Position = center,
	}
end

function MapBuilder.ClearRaidRings()
	if not raidFolder then
		return
	end
	for _, child in ipairs(raidFolder:GetChildren()) do
		child:Destroy()
	end
end

function MapBuilder.GetTerminal(id: string)
	return terminals[id]
end

function MapBuilder.GetTerminals()
	return terminalOrder
end

function MapBuilder.GetBank()
	return bank
end

--[[
	Prompts an Terminals und Bank zusammen schalten. Ausserhalb der Runde ist
	die Map still.
]]
function MapBuilder.SetWorldPromptsEnabled(enabled: boolean)
	for _, terminal in ipairs(terminalOrder) do
		terminal.Prompt.Enabled = enabled
	end
	if bank then
		bank.Prompt.Enabled = enabled
	end
end

return MapBuilder
