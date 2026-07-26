--[[
	InputController
	Tastenkuerzel und ProximityPrompts. Schickt ausschliesslich Absichten an den
	Server, nie Ergebnisse.

	G - Werkstatt   F - Rempeln   Q - Teil ablegen   E - Prompt (Roblox-Standard)

	Hier entstehen bewusst KEINE Touch-Knoepfe (createTouchButton = false):
	Rempeln, Ablegen und die Menues haengen auf Touch an den HUD-Knoepfen, und
	ContextActionService wuerde sonst einen zweiten Satz daneben legen.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)

local InputController = {}

function InputController.Start(ui)
	-- Werkbank in der eigenen Garage oeffnet das Menue. Der Prompt selbst
	-- macht auf dem Server nichts - er ist der Griff, nicht die Tuer.
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		local parent = prompt.Parent
		if not parent or player ~= Players.LocalPlayer then
			return
		end
		-- Nur die eigene Werkbank oeffnet das Menue.
		if parent.Name == "Workbench" and parent:GetAttribute("PlotIndex") == player:GetAttribute("PlotIndex") then
			ui.garage.SetVisible(true)
		end
	end)

	ContextActionService:BindAction("GarageHeist_Menu", function(_, state)
		if state == Enum.UserInputState.Begin then
			ui.garage.Toggle()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.G)

	ContextActionService:BindAction("GarageHeist_Tackle", function(_, state)
		if state == Enum.UserInputState.Begin then
			Remotes.Get("RequestTackle"):FireServer()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.F)

	-- Reparatur-Minispiel. Der Handler prueft selbst, ob gerade etwas laeuft -
	-- ein Druck ins Leere kostet nichts.
	ContextActionService:BindAction("GarageHeist_Repair", function(_, state)
		if state == Enum.UserInputState.Begin and ui.repairMinigame then
			ui.repairMinigame.Hit()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.R)

	ContextActionService:BindAction("GarageHeist_Drop", function(_, state)
		if state == Enum.UserInputState.Begin then
			Remotes.Get("RequestDropPart"):FireServer()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.Q)

	return InputController
end

return InputController
