--!strict
-- Client-Einstieg: UI aufbauen, Welt verbinden, Zustand vom Server abholen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

if not game:IsLoaded() then
	game.Loaded:Wait()
end
ReplicatedStorage:WaitForChild("Shared")

local Client = script.Parent
local CompanyConfig = require(ReplicatedStorage.Shared.Config.CompanyConfig)
local StateController = require(Client.Controllers.StateController)
local WorldController = require(Client.Controllers.WorldController)
local CampusController=require(Client.Controllers.CampusController)
local SecurityController=require(Client.Controllers.SecurityController)
local EmployeeController=require(Client.Controllers.EmployeeController)
local JourneyController=require(Client.Controllers.JourneyController)
local BuildingEffectsController=require(Client.Controllers.BuildingEffectsController)
local PeopleController=require(Client.Controllers.PeopleController)
local PropFxController=require(Client.Controllers.PropFxController)
local TalkController=require(Client.Controllers.TalkController)
local TravelController=require(Client.Controllers.TravelController)
local CityLifeController=require(Client.Controllers.CityLifeController)
local PhoneController=require(Client.Controllers.PhoneController)
-- round 2b (pre-wired stubs: drivers, guests_jet, itinerary packages replace them)
local DriveController=require(Client.Controllers.DriveController)
local GuestController=require(Client.Controllers.GuestController)
local JetController=require(Client.Controllers.JetController)
local ItineraryController=require(Client.Controllers.ItineraryController)
local Theme = require(Client.UI.Theme)
local UIRoot = require(Client.UI.UIRoot)
local Toast = require(Client.UI.Toast)
local HUD = require(Client.UI.Screens.HUD)
local Computer = require(Client.UI.Screens.Computer)
local Intro = require(Client.UI.Screens.Intro)
local DebugPanel = require(Client.UI.DebugPanel)
local AdminPanel=require(Client.UI.AdminPanel)

-- Platz für das eigene HUD oben rechts: Spielerliste und Rucksack braucht das Spiel nicht
for _, coreType in { Enum.CoreGuiType.PlayerList } do
	pcall(function()
		StarterGui:SetCoreGuiEnabled(coreType, false)
	end)
end

local hud, dimLayer, overlay, introLayer, top = UIRoot.init()
Toast.mount(top)
AdminPanel.mount(top)

local devAllowed = DebugPanel.allowed()
HUD.mount(hud, devAllowed, DebugPanel.toggle)
HUD.setHidden(true)
Computer.mount(overlay, dimLayer)
Intro.mount(introLayer, {
	onFinish = function()
		HUD.setHidden(false)
	end,
	onReopen = function()
		Computer.close()
		HUD.setHidden(true)
	end,
})
if devAllowed then
	DebugPanel.mount(top)
end

-- Firmenfarbe = Akzentfarbe der gesamten UI
StateController.onChange(function(snapshot)
	local company = snapshot.data.company
	if company then
		local def = CompanyConfig.getColor(company.color)
		if def then
			Theme.setAccent(Theme.rgb(def.rgb))
		end
	end
end)

WorldController.init(function(appId,section)
	Computer.open(appId,section)
end)
CampusController.init()
SecurityController.init()
EmployeeController.init()
JourneyController.init()
BuildingEffectsController.init()
PropFxController.init()
TalkController.init()
TravelController.init()
CityLifeController.init()
PhoneController.init()
DriveController.init()
GuestController.init()
JetController.init()
ItineraryController.init()
-- Bewerbungsgespräche + Assistentin der Gründerin (öffnet bei Bedarf den Firmen-Computer)
PeopleController.init(function(appId,section)
	Computer.open(appId,section)
end)
StateController.init()
