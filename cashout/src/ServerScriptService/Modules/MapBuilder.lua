--[[
	MapBuilder.lua

	Baut die komplette Map aus Parts. Keine externen Modelle, keine Asset-Ids.
	Grau, beschriftet, funktional -- der Job ist Spielbarkeit, nicht Optik.

	Layout: Terminals links, Bank rechts, dazwischen ~150 Studs offener Boden.
	Dieser Weg ist die eigentliche Kostenstelle des Spiels.

	Andere Services holen sich Terminals und Bank ueber die Getter hier, statt
	Workspace zu durchsuchen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared:WaitForChild("Assets"))
local Balance = require(Shared:WaitForChild("Balance"))

local MapBuilder = {}

local terminals: { [string]: any } = {}
local terminalOrder: { any } = {}
local bank: any = nil
local built = false

local COLOR_GROUND = Color3.fromRGB(58, 62, 68)
local COLOR_STRUCTURE = Color3.fromRGB(96, 100, 108)
local COLOR_TERMINAL = Color3.fromRGB(70, 150, 175)
local COLOR_BANK = Color3.fromRGB(80, 160, 110)

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

--[[
	Schrifttafel ueber einem Part. Rein informativ.
]]
local function addLabel(adornee: BasePart, title: string, subtitle: string, height: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(220, 56)
	billboard.StudsOffset = Vector3.new(0, height, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 200
	billboard.Adornee = adornee
	billboard.Parent = adornee

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0.6, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = Color3.fromRGB(240, 244, 248)
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
	Ohne Id bleibt die nackte Flaeche stehen -- das ist gewollt.
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

local function buildGround(root: Instance)
	local size = Balance.Map.GroundSize
	local ground = newPart(
		"Ground",
		size,
		Vector3.new(0, Balance.Map.GroundY - size.Y / 2, 0),
		COLOR_GROUND,
		root
	)
	ground.Material = Enum.Material.Concrete

	-- Schmaler Streifen als Wegmarkierung zwischen Terminals und Bank.
	local lane = newPart(
		"Lane",
		Vector3.new(math.abs(Balance.Map.BankPosition.X - Balance.Map.TerminalAnchorX), 0.2, 10),
		Vector3.new((Balance.Map.BankPosition.X + Balance.Map.TerminalAnchorX) / 2, Balance.Map.GroundY + 0.1, 0),
		Color3.fromRGB(78, 82, 90),
		root
	)
	lane.CanCollide = false
end

local function buildSpawn(root: Instance)
	local spawnPoint = Instance.new("SpawnLocation")
	spawnPoint.Name = "CashoutSpawn"
	spawnPoint.Size = Vector3.new(12, 1, 12)
	spawnPoint.Position = Balance.Map.SpawnPosition + Vector3.new(0, Balance.Map.GroundY + 0.5, 0)
	spawnPoint.Anchored = true
	spawnPoint.CanCollide = true
	spawnPoint.Color = COLOR_STRUCTURE
	spawnPoint.Material = Enum.Material.Metal
	spawnPoint.Neutral = true
	spawnPoint.Duration = 0
	spawnPoint.TopSurface = Enum.SurfaceType.Smooth
	spawnPoint.Parent = root
end

local function buildTerminals(root: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Terminals"
	folder.Parent = root

	local count = Balance.Map.TerminalCount
	local size = Balance.Map.TerminalSize

	for index = 1, count do
		local id = "T" .. index
		local z = (index - (count + 1) / 2) * Balance.Map.TerminalSpacingZ
		local basePosition = Vector3.new(Balance.Map.TerminalAnchorX, Balance.Map.GroundY, z)

		local model = Instance.new("Model")
		model.Name = "Terminal" .. index
		model.Parent = folder

		local pillar = newPart(
			"Pillar",
			Vector3.new(size.X, size.Y, size.Z),
			basePosition + Vector3.new(0, size.Y / 2, 0),
			COLOR_STRUCTURE,
			model
		)

		local screen = newPart(
			"Screen",
			Vector3.new(0.6, 3, 3.6),
			basePosition + Vector3.new(size.X / 2 + 0.3, size.Y - 2, 0),
			COLOR_TERMINAL,
			model
		)
		screen.Material = Enum.Material.Neon
		screen.CanCollide = false
		addDecal(screen, Assets.Images.TerminalScreen, Enum.NormalId.Right)

		model.PrimaryPart = pillar
		model:SetAttribute("TerminalId", id)

		addLabel(pillar, "TERMINAL " .. index, "Deals ansehen", size.Y / 2 + 1.5)
		local prompt = addPrompt(pillar, "Deals ansehen", "Terminal " .. index, Balance.Map.TerminalPromptDistance)

		local terminal = {
			Id = id,
			Index = index,
			Model = model,
			Part = pillar,
			Position = pillar.Position,
			Prompt = prompt,
		}
		terminals[id] = terminal
		table.insert(terminalOrder, terminal)
	end
end

local function buildBank(root: Instance)
	local model = Instance.new("Model")
	model.Name = "Bank"
	model.Parent = root

	local size = Balance.Map.BankSize
	local base = Balance.Map.BankPosition + Vector3.new(0, Balance.Map.GroundY, 0)

	local building = newPart("Building", size, base + Vector3.new(0, size.Y / 2, 0), COLOR_STRUCTURE, model)

	local counter = newPart(
		"Counter",
		Vector3.new(3, 5, 10),
		base + Vector3.new(-size.X / 2 - 1.5, 2.5, 0),
		COLOR_BANK,
		model
	)
	counter.Material = Enum.Material.Neon
	addDecal(counter, Assets.Images.BankSign, Enum.NormalId.Left)

	-- Bodenmarkierung zeigt, wo man stehen bleiben muss.
	local pad = newPart(
		"Pad",
		Vector3.new(Balance.Bank.Radius, 0.2, Balance.Bank.Radius),
		base + Vector3.new(-size.X / 2 - 6, 0.1, 0),
		COLOR_BANK,
		model
	)
	pad.CanCollide = false
	pad.Transparency = 0.5

	model.PrimaryPart = counter

	addLabel(counter, "BANK", "Einzahlen: " .. Balance.Bank.DepositSeconds .. " s", 4)
	local prompt = addPrompt(counter, "Einzahlen", "Bank", Balance.Bank.PromptDistance)

	bank = {
		Model = model,
		Part = counter,
		Position = counter.Position,
		Prompt = prompt,
	}
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
	-- genau auf unserem Boden und wuerden flimmern bzw. den Spieler woanders
	-- einsetzen. Nur diese beiden, nichts sonst aus Workspace.
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

	buildGround(root)
	buildSpawn(root)
	buildTerminals(root)
	buildBank(root)
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

return MapBuilder
