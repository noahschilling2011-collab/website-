--[[
	CarBuilder
	Baut ein Auto als Deko-Modell: keine VehicleSeats, keine Motoren, keine
	Physik. Verbaute Teile sind sichtbar, fehlende Teile als durchsichtiger
	Platzhalter - man sieht auf einen Blick, was der Karre fehlt.

	Jedes verbaute Teil traegt ein ProximityPrompt zum Abmontieren. Das ist
	standardmaessig aus und wird nur vom HeistService eingeschaltet.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.CarCatalog)
local Config = require(Shared.Config)
local PartCatalog = require(Shared.PartCatalog)
local Util = require(Shared.Util)

local CarBuilder = {}

local GHOST_COLOR = Color3.fromRGB(220, 70, 70)

local function makePart(name, size, cframe, color, parent, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function tagPart(instance, slotId, part, ownerUserId, carIndex)
	instance:SetAttribute("SlotId", slotId)
	instance:SetAttribute("CarIndex", carIndex)
	instance:SetAttribute("OwnerUserId", ownerUserId)
	if part then
		instance:SetAttribute("PartUid", part.uid)
		instance:SetAttribute("Tier", part.tier)
	end
end

local function addStealPrompt(anchor, slotId, part, ownerUserId, carIndex)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StealPrompt"
	prompt.ActionText = "Abmontieren"
	local tierDef = PartCatalog.GetTier(slotId, part.tier)
	prompt.ObjectText = tierDef and tierDef.name or slotId
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = anchor
	tagPart(prompt, slotId, part, ownerUserId, carIndex)
	return prompt
end

local function buildBillboard(parent, height)
	local attachment = Instance.new("Part")
	attachment.Name = "Label"
	attachment.Anchored = true
	attachment.CanCollide = false
	attachment.Transparency = 1
	attachment.Size = Vector3.new(0.2, 0.2, 0.2)
	attachment.CFrame = parent.CFrame * CFrame.new(0, height, 0)
	attachment.Parent = parent.Parent

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(9, 2.2)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 90
	gui.Parent = attachment

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.55)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextStrokeTransparency = 0.4
	title.Parent = gui

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromScale(0, 0.55)
	sub.Size = UDim2.fromScale(1, 0.45)
	sub.Font = Enum.Font.Gotham
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(140, 235, 170)
	sub.TextStrokeTransparency = 0.5
	sub.Parent = gui

	return { part = attachment, title = title, sub = sub }
end

-- carState = { carId = "...", parts = { [slotId] = part } }
-- options.rebirths schaltet ab Config.REBIRTH_PAINT_AT den exklusiven Lack frei.
function CarBuilder.Build(carState, carIndex: number, ownerUserId: number, cframe: CFrame, parent: Instance, options)
	local carDef = CarCatalog.Get(carState.carId) or CarCatalog.Get(CarCatalog.STARTER)
	local model = Instance.new("Model")
	model.Name = ("Car%d_%d"):format(carIndex, ownerUserId)
	model:SetAttribute("OwnerUserId", ownerUserId)
	model:SetAttribute("CarIndex", carIndex)
	model.Parent = parent

	local paintPart = carState.parts.paint
	local bodyColor = carDef.baseColor
	local paintSlot = PartCatalog.GetSlot("paint")
	local exclusivePaint = false
	if paintPart then
		local tierDef = PartCatalog.GetTier("paint", paintPart.tier)
		if tierDef then
			bodyColor = tierDef.color
		end
		local rebirths = (options and options.rebirths) or 0
		if rebirths >= Config.REBIRTH_PAINT_AT and paintPart.tier >= PartCatalog.TierCount("paint") then
			bodyColor = paintSlot.rebirthColor
			exclusivePaint = true
		end
	end

	local bodyY = 1.2
	local body = makePart(
		"Body",
		carDef.bodySize,
		cframe * CFrame.new(0, bodyY, 0),
		bodyColor,
		model,
		exclusivePaint and Enum.Material.Neon or (paintPart and Enum.Material.Metal or Enum.Material.CorrodedMetal)
	)
	body.CanCollide = true
	model.PrimaryPart = body

	makePart(
		"Roof",
		carDef.roofSize,
		cframe * CFrame.new(carDef.roofOffset.X, carDef.roofOffset.Y, carDef.roofOffset.Z),
		bodyColor:Lerp(Color3.new(0, 0, 0), 0.25),
		model,
		Enum.Material.SmoothPlastic
	)

	local prompts = {}
	local slotParts = {}
	local anchors = { paint = body }

	if paintPart then
		tagPart(body, "paint", paintPart, ownerUserId, carIndex)
		prompts.paint = addStealPrompt(body, "paint", paintPart, ownerUserId, carIndex)
		slotParts.paint = { body }
	end

	-- Reifen -------------------------------------------------------------
	local tirePart = carState.parts.tires
	local tireDef = tirePart and PartCatalog.GetTier("tires", tirePart.tier)
	local wheelColor = tireDef and tireDef.color or GHOST_COLOR
	local wheelSize = PartCatalog.GetSlot("tires").size
	local wheels = {}
	for _, xSign in { -1, 1 } do
		for _, zSign in { -1, 1 } do
			local wheel = makePart(
				"Wheel",
				wheelSize,
				cframe * CFrame.new(xSign * carDef.track, wheelSize.Y / 2, zSign * carDef.wheelbase),
				wheelColor,
				model,
				Enum.Material.Rubber,
				tirePart and 0 or 0.65
			)
			wheel.Shape = Enum.PartType.Cylinder
			table.insert(wheels, wheel)
		end
	end
	anchors.tires = wheels[1]
	if tirePart then
		for _, wheel in wheels do
			tagPart(wheel, "tires", tirePart, ownerUserId, carIndex)
		end
		prompts.tires = addStealPrompt(wheels[1], "tires", tirePart, ownerUserId, carIndex)
		slotParts.tires = wheels
	end

	-- Motor und Turbo ----------------------------------------------------
	-- Die Position haengt an der Karosserie, nicht an festen Zahlen: sonst
	-- steckt der Motor im Supersportler im Blech statt auf der Haube.
	local bodyTop = bodyY + carDef.bodySize.Y / 2
	local halfLength = carDef.bodySize.Z / 2
	for _, slotId in { "engine", "turbo" } do
		local slotDef = PartCatalog.GetSlot(slotId)
		local statePart = carState.parts[slotId]
		local tier = statePart and PartCatalog.GetTier(slotId, statePart.tier)
		local offset
		if slotDef.mount == "spoiler" then
			offset = Vector3.new(0, bodyTop + slotDef.size.Y / 2 + 0.25, halfLength - slotDef.size.Z / 2 - 0.4)
		else
			offset = Vector3.new(0, bodyTop + slotDef.size.Y / 2 - 0.2, -(halfLength - slotDef.size.Z / 2 - 0.7))
		end
		local instance = makePart(
			slotDef.displayName,
			slotDef.size,
			cframe * CFrame.new(offset),
			tier and tier.color or GHOST_COLOR,
			model,
			statePart and Enum.Material.Metal or Enum.Material.ForceField,
			statePart and 0 or 0.6
		)
		anchors[slotId] = instance
		if statePart then
			tagPart(instance, slotId, statePart, ownerUserId, carIndex)
			prompts[slotId] = addStealPrompt(instance, slotId, statePart, ownerUserId, carIndex)
			slotParts[slotId] = { instance }
		end
	end

	local billboard = buildBillboard(body, carDef.bodySize.Y / 2 + 3.6)
	billboard.title.Text = carDef.displayName
	billboard.sub.Text = Util.FormatRate(0)

	return {
		model = model,
		body = body,
		prompts = prompts,
		slotParts = slotParts,
		-- Ankerpunkte fuer den Reparatur-Balken. Existieren auch fuer leere
		-- Slots, weil dort der Platzhalter steht.
		anchors = anchors,
		billboard = billboard,
		carIndex = carIndex,
	}
end

return CarBuilder
