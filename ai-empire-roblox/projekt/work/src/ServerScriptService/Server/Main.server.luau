--!strict
-- Server-Einstieg. Reihenfolge ist wichtig:
--   1. Remotes anlegen (Client wartet darauf)
--   2. Speichern prüfen, Welt bauen, Services binden ihre Remotes
--   3. SessionService zuletzt: ab dann werden Spieler geladen
-- Danach ein einziger Heartbeat-Takt für Training, Markt, Autosave und State-Versand.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Server = script.Parent
local Remote = require(Server.Lib.Remote)
local Services = Server.Services
local SaveService = require(Services.SaveService)
local SessionService = require(Services.SessionService)
local PlotService = require(Services.PlotService)
local CompanyService = require(Services.CompanyService)
local DatasetService = require(Services.DatasetService)
local ComputeService = require(Services.ComputeService)
local AIModelService = require(Services.AIModelService)
local MarketService = require(Services.MarketService)
local DebugService = require(Services.DebugService)

local EmpireService = require(Services.EmpireService)
local CampusService = require(Services.CampusService)

local NPCService=require(Services.NPCService)
local StudioService=require(Services.StudioService)
local ArenaService=require(Services.ArenaService)
local LeaderboardService=require(Services.LeaderboardService)

local DoorService=require(Services.DoorService)
local LiftService=require(Services.LiftService)
local FacilityService=require(Services.FacilityService)
local VehicleService=require(Services.VehicleService)
local AdminService=require(Services.AdminService)
local StaffService=require(Services.StaffService)
local BuildingStateService=require(Services.BuildingStateService)
local RecruitingService=require(Services.RecruitingService)
local AssistantService=require(Services.AssistantService)
local TalkService=require(Services.TalkService)
local ShopService=require(Services.ShopService)
local CityService=require(Services.CityService)
local PhoneService=require(Services.PhoneService)

local MAX_STEP = 5 -- nach einem Server-Hänger nicht mehr als 5 s auf einmal simulieren

Remote.setup()
SaveService.init()
PlotService.init()
CompanyService.init()
DatasetService.init()
ComputeService.init()
AIModelService.init()
MarketService.init()
DebugService.init()
EmpireService.init()
CampusService.init()
CityService.init() -- shared business city, airport and the international city (built once per server)
NPCService.init()
StudioService.init()
ArenaService.init()
LeaderboardService.init()
DoorService.init() -- vor FacilityService: Facility setzt den Tür-Authorizer und initialisiert den Lift
FacilityService.init()
VehicleService.init()
AdminService.init()
StaffService.init()
RecruitingService.init() -- Bewerbungen & Gespräche (vor SessionService: onLoaded repariert Staff-Profile)
AssistantService.init()
TalkService.init() -- talk to anyone (employees, ops staff, visitors)
ShopService.init() -- Robux receipts/game passes (before SessionService: receipts wait for the session)
PhoneService.init() -- company phone: calls, messages, calendar, AI chat
SessionService.init()

-- Ein Fehler bei einem Spieler darf den Takt der anderen nicht stoppen
local function safely(label: string, fn: () -> ())
	local ok, err = pcall(fn :: () -> any)
	if not ok then
		warn(`[Tick] {label}: {err}`)
	end
end

local function simulate(step: number)
	safely("NPC companies",function() NPCService.tick(step) end)
	safely("Shared market",function() MarketService.tickGlobal(step) end)
	for _, session in SessionService.all() do
		if not session.closed then
			safely("Training " .. session.player.Name, function()
				AIModelService.tick(session, step)
			end)
			safely("Markt " .. session.player.Name, function()
				MarketService.tick(session, step)
			end)
			safely("Empire " .. session.player.Name, function()
				StudioService.tick(session,step)
				EmpireService.tick(session, step)
				FacilityService.economyTick(session,step)
			end)
			safely("Recruiting " .. session.player.Name, function()
				RecruitingService.tick(session, step)
			end)
		end
	end
	StudioService.refresh()
	LeaderboardService.tick(step)
	CampusService.tick(step)
end

local accumulator = 0
local arenaAccumulator=0
local campusAccumulator=0
RunService.Heartbeat:Connect(function(dt: number)
	accumulator += dt
	campusAccumulator+=dt
	if campusAccumulator>=.05 then
		local campusStep=math.min(campusAccumulator,.25);campusAccumulator=0
		safely("Campus doors",function()DoorService.tick(campusStep)end)
		safely("Campus lift",function()LiftService.tick(campusStep)end)
		safely("Campus access",function()FacilityService.tick(campusStep)end)
		safely("Campus employees",function()StaffService.tick(campusStep)end)
		safely("Campus visitors",function()RecruitingService.campusTick(campusStep)end)
		safely("Founder assistant",function()AssistantService.tick(campusStep)end)
  safely("Company displays",function()BuildingStateService.tick(campusStep)end)
		safely("Company cars",function()VehicleService.tick(campusStep)end)
		safely("World travel",function()CityService.tick(campusStep)end)
	end
	arenaAccumulator+=dt
	if arenaAccumulator>=.1 then
		local arenaStep=math.min(arenaAccumulator,.5);arenaAccumulator=0
		safely("Arena animation",function() ArenaService.tick(arenaStep) end)
	end
	if accumulator >= GameConfig.TICK_SECONDS then
		local step = math.min(accumulator, MAX_STEP)
		accumulator = 0
		simulate(step)
		SessionService.autosave(os.clock())
	end
	SessionService.flush(os.clock())
end)

print(`[AI Empire] Server bereit (Speichern: {if SaveService.enabled then "AN" else "AUS"})`)
