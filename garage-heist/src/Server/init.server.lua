--[[
	Garage Heist - Server-Bootstrap

	Startreihenfolge ist Absicht:
	- DataService laeuft ZULETZT los, damit alle anderen Services schon an
	  ProfileLoaded haengen, bevor das erste Profil geladen wird.
	- GarageService vor HeistService, weil der Heist die Plots braucht.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

Remotes.Init()

-- Abenddaemmerung: passt zum Thema und kaschiert die einfache Geometrie.
local function setupLighting()
	Lighting.Technology = Enum.Technology.Future
	Lighting.ClockTime = 18.5
	Lighting.Brightness = 2
	Lighting.ExposureCompensation = 0.15
	Lighting.OutdoorAmbient = Color3.fromRGB(70, 70, 90)
	Lighting.Ambient = Color3.fromRGB(45, 45, 60)
	Lighting.GlobalShadows = true
	Lighting.FogEnd = 900

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

setupLighting()

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
for _, name in START_ORDER do
	services[name] = require(script.Services[name])
end

for _, name in START_ORDER do
	local service = services[name]
	if service.Init then
		service:Init(services)
	end
end

-- Boden und Notfall-Spawn. Die eigentlichen Spawnpunkte liegen in den Garagen,
-- hierher faellt nur, wer beitritt bevor sein Profil geladen ist.
local ground = Instance.new("Part")
ground.Name = "Ground"
ground.Anchored = true
ground.Size = Vector3.new(900, 2, 620)
ground.CFrame = CFrame.new(0, -1, 0)
ground.Color = Color3.fromRGB(58, 60, 64)
ground.Material = Enum.Material.Asphalt
ground.TopSurface = Enum.SurfaceType.Smooth
ground.Parent = Workspace

local spawnPad = Instance.new("SpawnLocation")
spawnPad.Name = "LobbySpawn"
spawnPad.Anchored = true
spawnPad.Size = Vector3.new(12, 1, 12)
spawnPad.CFrame = CFrame.new(0, 0.5, 26)
spawnPad.Color = Color3.fromRGB(90, 200, 130)
spawnPad.Material = Enum.Material.Neon
spawnPad.Duration = 0
spawnPad.Parent = Workspace

for _, name in START_ORDER do
	local service = services[name]
	if service.Start then
		local ok, err = pcall(function()
			service:Start()
		end)
		if not ok then
			warn(("[Bootstrap] %s:Start() ist gescheitert: %s"):format(name, tostring(err)))
		end
	end
end

print("[Garage Heist] Server bereit.")
