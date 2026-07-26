--[[
	FencePad
	Der Hehler: ein Abgabepunkt mitten im Hof.

	Wer hier abliefert, bekommt sofort Config.FENCE_RATE des Teilewerts als
	Cash - kann es aber nicht einbauen. Wer bis nach Hause traegt, bekommt das
	Teil selbst. Das ist die Entscheidung: sicheres Geld jetzt gegen echten
	Fortschritt spaeter, und sie faellt genau dann, wenn es wehtut - mit einem
	Prototyp in der Hand und einem Verfolger im Nacken.

	Absichtlich in der Hofmitte (Config.FENCE_POSITION), also auf dem Weg von
	niemandem und in Reichweite von allen. Der Umweg ist der Preis.

	Das Modul baut nur die Geometrie und gibt den Prompt zurueck; wer daran
	haengt, entscheidet der Bootstrap.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local FencePad = {}

local C = {
	deck = Color3.fromRGB(26, 28, 34),
	edge = Color3.fromRGB(255, 45, 85),
	post = Color3.fromRGB(96, 100, 110),
	steel = Color3.fromRGB(126, 132, 142),
}

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Color = props.Color or C.post
	p.Material = props.Material or Enum.Material.Metal
	p.Name = props.Name or "Part"
	p.CanCollide = if props.CanCollide ~= nil then props.CanCollide else false
	p.CastShadow = if props.CastShadow ~= nil then props.CastShadow else false
	p.Parent = props.Parent
	return p
end

function FencePad.Build(parent: Instance)
	local origin = Config.FENCE_POSITION
	local model = Instance.new("Model")
	model.Name = "FencePad"
	model.Parent = parent

	-- Plattform. Flach genug, dass sie im Klau-Fenster niemanden aufhaelt.
	local deck = part({
		Name = "Deck",
		Size = Vector3.new(16, 0.6, 16),
		CFrame = CFrame.new(origin + Vector3.new(0, 0.3, 0)),
		Color = C.deck,
		Material = Enum.Material.DiamondPlate,
		CanCollide = true,
		Parent = model,
	})
	for _, spec in
		{
			{ Vector3.new(17, 0.3, 1), Vector3.new(0, 0, 8.2) },
			{ Vector3.new(17, 0.3, 1), Vector3.new(0, 0, -8.2) },
			{ Vector3.new(1, 0.3, 17), Vector3.new(8.2, 0, 0) },
			{ Vector3.new(1, 0.3, 17), Vector3.new(-8.2, 0, 0) },
		}
	do
		part({
			Name = "Edge",
			Size = spec[1],
			CFrame = CFrame.new(origin + spec[2] + Vector3.new(0, 0.5, 0)),
			Color = C.edge,
			Material = Enum.Material.Neon,
			Parent = model,
		})
	end

	-- Bude: vier Pfosten, ein Dach, ein Tresen. Reicht, damit es nach etwas
	-- aussieht und nicht nach einem zweiten Abgabe-Pad.
	for _, spec in { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } do
		part({
			Name = "Post",
			Size = Vector3.new(0.8, 9, 0.8),
			CFrame = CFrame.new(origin + Vector3.new(spec[1] * 7, 4.5, spec[2] * 7)),
			CanCollide = true,
			CastShadow = true,
			Parent = model,
		})
	end
	part({
		Name = "Roof",
		Size = Vector3.new(17, 0.8, 17),
		CFrame = CFrame.new(origin + Vector3.new(0, 9.4, 0)),
		Color = C.deck,
		CastShadow = true,
		Parent = model,
	})
	local counter = part({
		Name = "Counter",
		Size = Vector3.new(11, 3.4, 2.4),
		CFrame = CFrame.new(origin + Vector3.new(0, 2.3, -5)),
		Color = C.steel,
		CanCollide = true,
		Parent = model,
	})

	local sign = part({
		Name = "Sign",
		Size = Vector3.new(12, 3, 0.4),
		CFrame = CFrame.new(origin + Vector3.new(0, 7.4, -6.4)),
		Color = C.deck,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.CanvasSize = Vector2.new(500, 130)
	gui.LightInfluence = 0
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Michroma
	label.TextScaled = true
	label.TextColor3 = C.edge
	label.Text = "HEHLER"
	label.Parent = gui

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FencePrompt"
	prompt.ActionText = "Verticken"
	prompt.ObjectText = "Hehler"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(16, 3)
	billboard.StudsOffset = Vector3.new(0, 7, 0)
	billboard.MaxDistance = 220
	billboard.Parent = deck
	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.Size = UDim2.fromScale(1, 1)
	hint.Font = Enum.Font.GothamBold
	hint.TextScaled = true
	hint.TextColor3 = C.edge
	hint.TextStrokeTransparency = 0.4
	-- Der Kurs steht dran, sonst ist die Entscheidung ein Blindflug.
	hint.Text = ("HEHLER - %d%% sofort, dafuer weg"):format(math.floor(Config.FENCE_RATE * 100))
	hint.Parent = billboard

	return { model = model, prompt = prompt, deck = deck, hint = hint }
end

return FencePad
