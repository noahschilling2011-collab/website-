--[[
	Garage Heist - Server-Bootstrap

	Startreihenfolge ist Absicht:
	- DataService laeuft ZULETZT los, damit alle anderen Services schon an
	  ProfileLoaded haengen, bevor das erste Profil geladen wird.
	- GarageService vor HeistService, weil der Heist die Plots braucht.

	Grundregel dieser Datei: KEIN Schritt darf die restlichen mitreissen. Die
	Welt (Boden, Spawn, Garagen) entsteht hier zur Laufzeit - stirbt der
	Bootstrap vorher an einer Kleinigkeit, sieht der Spieler gar nichts mehr.
	Deshalb laeuft jeder Abschnitt in einem eigenen pcall und meldet sich
	einzeln in der Konsole.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local function step(label: string, fn)
	local ok, err = pcall(fn)
	if not ok then
		warn(("[Garage Heist] %s ist gescheitert: %s"):format(label, tostring(err)))
	end
	return ok
end

step("Remotes anlegen", function()
	Remotes.Init()
end)

-- Abenddaemmerung: passt zum Thema und kaschiert die einfache Geometrie.
--
-- Lighting.Technology wird hier BEWUSST NICHT gesetzt: die Eigenschaft ist
-- nicht skriptbar. Sie steht in der Place-Datei (GarageHeist.rbxlx) bzw. in
-- default.project.json und laesst sich in Studio unter Lighting > Technology
-- auf "Future" stellen. Jede einzelne Zuweisung haengt zusaetzlich in einem
-- eigenen pcall, damit eine kuenftige Roblox-Aenderung nicht wieder das ganze
-- Spiel lahmlegt.
local function setupLighting()
	local values = {
		ClockTime = 18.5,
		Brightness = 2,
		ExposureCompensation = 0.15,
		OutdoorAmbient = Color3.fromRGB(70, 70, 90),
		Ambient = Color3.fromRGB(45, 45, 60),
		GlobalShadows = true,
		FogEnd = 900,
	}
	for property, value in values do
		local ok = pcall(function()
			(Lighting :: any)[property] = value
		end)
		if not ok then
			warn(("[Garage Heist] Lighting.%s liess sich nicht setzen (uebersprungen)."):format(property))
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.35
	atmosphere.Offset = 0.2
	atmosphere.Haze = 1.4
	atmosphere.Color = Color3.fromRGB(190, 180, 175)
	atmosphere.Decay = Color3.fromRGB(105, 95, 110)
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.5
	bloom.Size = 20
	bloom.Threshold = 1.1
	bloom.Parent = Lighting

	local correction = Instance.new("ColorCorrectionEffect")
	correction.Contrast = 0.1
	correction.Saturation = -0.05
	correction.TintColor = Color3.fromRGB(255, 246, 240)
	correction.Parent = Lighting
end

-- Boden und Notfall-Spawn. Die eigentlichen Spawnpunkte liegen in den Garagen,
-- hierher faellt nur, wer beitritt bevor sein Profil geladen ist.
local function buildWorld()
	local ground = Instance.new("Part")
	ground.Name = "Ground"
	ground.Anchored = true
	ground.Size = Vector3.new(900, 2, 620)
	-- Oberkante bei -0,05 statt 0: Baseplate, Ground und jeder Garagenboden
	-- lagen exakt koplanar auf y = 0 und haben bei jeder Kamerabewegung
	-- geflimmert (Z-Fighting).
	ground.CFrame = CFrame.new(0, -1.05, 0)
	ground.Color = Color3.fromRGB(38, 40, 45)
	ground.Material = Enum.Material.Asphalt
	ground.TopSurface = Enum.SurfaceType.Smooth
	ground.Parent = Workspace

	-- Erst jetzt weg: scheitert die Zeile darueber, steht wenigstens noch die
	-- Grundplatte aus der Place-Datei und niemand faellt ins Leere.
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "LobbySpawn"
	spawnPad.Anchored = true
	spawnPad.Size = Vector3.new(12, 1, 12)
	spawnPad.CFrame = CFrame.new(0, 0.5, 26)
	spawnPad.Color = Color3.fromRGB(90, 200, 130)
	spawnPad.Material = Enum.Material.Neon
	spawnPad.Duration = 0
	spawnPad.Parent = Workspace
end

-- Zuerst der Boden: wer beitritt, bevor der Rest steht, faellt sonst ins Leere.
step("Welt bauen", buildWorld)
step("Lighting einstellen", setupLighting)

local START_ORDER = {
	"TelemetryService",
	"EffectService",
	"MonetizationService",
	"EconomyService",
	"GarageService",
	"DerelictService",
	"HeistService",
	"DailyRewardService",
	"LeaderboardService",
	"DataService",
}

local services = {}
local loaded = {}
for _, name in START_ORDER do
	local ok, module = pcall(function()
		return require(script.Services[name])
	end)
	if ok then
		services[name] = module
		table.insert(loaded, name)
	else
		warn(("[Garage Heist] %s liess sich nicht laden: %s"):format(name, tostring(module)))
	end
end

for _, name in loaded do
	local service = services[name]
	if service.Init then
		step(name .. ":Init()", function()
			service:Init(services)
		end)
	end
end

for _, name in loaded do
	local service = services[name]
	if service.Start then
		step(name .. ":Start()", function()
			service:Start()
		end)
	end
end

-- Sichtbarer Beweis, dass die Welt steht. Fehlt diese Zeile in der Konsole,
-- ist der Bootstrap vorher gestorben und die Zeile darueber sagt, woran.
local plotCount = 0
local garages = Workspace:FindFirstChild("Garages")
if garages then
	plotCount = #garages:GetChildren()
end
print(("[Garage Heist] Server bereit: %d/%d Services, %d Garagen gebaut."):format(
	#loaded,
	#START_ORDER,
	plotCount
))
