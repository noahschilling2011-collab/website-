--[[
	DoorController
	Das Garagentor ist kein Deko-Objekt: es geht auf, wenn der Besitzer davor
	steht, und waehrend des Klau-Fensters fuer alle. Sonst bleibt es zu und man
	kommt nicht rein.
]]

local Players = game:GetService("Players")

local PlotBuilder = require(script.Parent.PlotBuilder)

local DoorController = {}

local OWNER_OPEN_DISTANCE = 26

local function ownerIsNear(plot, userId: number): boolean
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	return (root.Position - plot.doorClosedCFrame.Position).Magnitude < OWNER_OPEN_DISTANCE
end

-- `isPlotOpen(plotIndex)` kommt vom HeistService und beruecksichtigt den
-- Garage-Lock-Gamepass.
function DoorController.Tick(plots, plotOwner, isPlotOpen)
	for index, plot in plots do
		local open = isPlotOpen(index)
		if not open then
			local ownerId = plotOwner[index]
			open = ownerId ~= nil and ownerIsNear(plot, ownerId)
		end
		PlotBuilder.SetDoor(plot, open)
	end
end

return DoorController
