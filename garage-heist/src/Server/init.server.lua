--[[
	Garage Heist - Server-Bootstrap

	Startreihenfolge ist Absicht:
	- DataService laeuft ZULETZT los, damit alle anderen Services schon an
	  ProfileLoaded haengen, bevor das erste Profil geladen wird.
	- GarageService vor HeistService, weil der Heist die Plots braucht.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

Remotes.Init()

local START_ORDER = {
	"MonetizationService",
	"EconomyService",
	"GarageService",
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
