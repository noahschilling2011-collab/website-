--[[
	PartVisual
	Das sichtbare Objekt fuer ein Teil, das gerade niemandem gehoert - getragen
	oder auf dem Boden. Nur Aussehen; wem es gehoert, steht im Profil.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartCatalog = require(ReplicatedStorage:WaitForChild("Shared").PartCatalog)

local PartVisual = {}

function PartVisual.Build(part): Part
	local slotDef = PartCatalog.GetSlot(part.slotId)
	local tierDef = PartCatalog.GetTier(part.slotId, part.tier)

	local instance = Instance.new("Part")
	instance.Name = "StolenPart"
	instance.Size = Vector3.new(
		math.min(slotDef.size.X, 3),
		math.min(slotDef.size.Y, 2),
		math.min(slotDef.size.Z, 3)
	)
	instance.Color = tierDef and tierDef.color or Color3.fromRGB(200, 200, 200)
	instance.Material = Enum.Material.Metal
	instance.CanCollide = false
	instance.Massless = true
	instance:SetAttribute("PartUid", part.uid)

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(7, 1.6)
	gui.StudsOffset = Vector3.new(0, 2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	gui.Parent = instance

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 220, 120)
	label.TextStrokeTransparency = 0.4
	label.Text = tierDef and tierDef.name or part.slotId
	label.Parent = gui

	return instance
end

return PartVisual
