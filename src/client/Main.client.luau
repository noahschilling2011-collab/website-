-- Main.client.luau
-- Einstiegspunkt Client: baut HUD + Baumenue, initialisiert den PlacementController
-- und verarbeitet StateSync (HUD-Update, Freischalt-Meldungen, Menue-Zustand).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiniCity")
local Items = require(Shared:WaitForChild("Items"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local modules = script.Parent
local HUD = require(modules.HUD)
local BuildMenuUI = require(modules.BuildMenuUI)
local PlacementController = require(modules.PlacementController)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screen = Instance.new("ScreenGui")
screen.Name = "MiniCityUI"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local hud = HUD.create(screen)

local controller
local menu = BuildMenuUI.create(screen, {
	onSelectItem = function(itemId)
		controller:setItem(itemId)
	end,
	onToggleDemolish = function()
		if controller.mode == "demolish" then
			controller:cancel()
		else
			controller:setDemolish()
		end
	end,
	onRotate = function()
		controller:rotate()
	end,
	onCancel = function()
		controller:cancel()
	end,
})

controller = PlacementController.create({ hud = hud, menu = menu })

-- ----------------------------------------------------------------------------
-- StateSync
-- ----------------------------------------------------------------------------

local prevUnlocked = nil :: { [string]: boolean }?

local function onState(state)
	hud:update(state)
	menu:update(state)
	controller:onState(state)

	-- Freischalt-Meldungen (nicht beim ersten Sync)
	local currentSet = {}
	for _, id in state.unlockedItems or {} do
		currentSet[id] = true
	end
	if prevUnlocked then
		for id in currentSet do
			if not prevUnlocked[id] then
				local item = Items.get(id)
				if item then
					hud:toast(item.name .. " freigeschaltet!")
				end
			end
		end
	end
	prevUnlocked = currentSet
end

Remotes.StateSync().OnClientEvent:Connect(onState)
