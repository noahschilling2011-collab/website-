--[[
	CarBuilder v2

	Gleiche oeffentliche API wie v1:
		CarBuilder.Build(carState, carIndex, ownerUserId, cframe, parent, options)
		-> { model, body, prompts, slotParts, anchors, billboard, carIndex }

	Was v1 noch fehlte: eine Silhouette. Ein Auto erkennt man nicht an
	Einzelteilen, sondern an der Linie von der Nase ueber die Frontscheibe
	zum Heck. v1 hatte zwei gestapelte Kisten - alles was jetzt dazukommt,
	arbeitet an dieser Linie:

		Motorhaube    faellt nach vorn ab
		Frontscheibe  liegt schraeg, nicht senkrecht
		Seitenscheibe schliesst das Dach zur Karosserie
		Heckscheibe   faellt nach hinten ab
		Heckdeckel    faellt nach hinten ab
		Kotfluegel    ueber jedem Rad, damit die Raeder dazugehoeren
		Kuehlergrill, Splitter, Diffusor, Leuchtenband, Spiegel, Auspuff

	KEINE WedgeParts mehr. In v1 hingen Front- und Heckscheibe an
	WedgePart-Ausrichtung, und die beiden waren ausserdem vertauscht (die
	"Windshield" sass hinten). Schraege Flaechen sind jetzt duenne Quader mit
	ausgerechnetem Winkel - das laesst sich nachrechnen statt ausprobieren.

	Teilezahl: rund 63 pro Auto (v1: 51). Gegenfinanziert ueber die Speichen,
	die von vier auf zwei bis drei pro Rad runtergehen - die sieht bei einem
	stehenden Auto ohnehin niemand.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.CarCatalog)
local Config = require(Shared.Config)
local PartCatalog = require(Shared.PartCatalog)
local Util = require(Shared.Util)

local CarBuilder = {}

local GHOST_COLOR = Color3.fromRGB(220, 70, 70)
local GLASS_COLOR = Color3.fromRGB(24, 28, 38)
local CHROME = Color3.fromRGB(206, 212, 224)
local NEAR_BLACK = Color3.fromRGB(16, 17, 21)

-- Front zeigt nach -Z, Heck nach +Z.
local RAKE_FRONT = 2.4 -- Laenge, ueber die die Frontscheibe faellt
local RAKE_REAR = 2.0

local function makePart(name, size, cframe, color, parent, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = true
	p.CastShadow = false
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

--[[
	Schraege Flaeche zwischen zwei Punkten der YZ-Ebene. X bleibt die Breite.

	Die lokale Z-Achse eines Parts zeigt nach CFrame.Angles(a, 0, 0) auf
	(0, -sin a, cos a). Gewuenscht ist (0, dy, dz)/len, also a = -atan2(dy, dz).
	Damit steht der Winkel fest und muss nicht geraten werden.
]]
local function slab(parent, name, cframe, width, thickness, fromY, fromZ, toY, toZ, color, material, transparency)
	local dy, dz = toY - fromY, toZ - fromZ
	local length = math.sqrt(dy * dy + dz * dz)
	if length < 0.05 then
		return nil
	end
	local angle = -math.atan2(dy, dz)
	return makePart(
		name,
		Vector3.new(width, thickness, length),
		cframe * CFrame.new(0, (fromY + toY) / 2, (fromZ + toZ) / 2) * CFrame.Angles(angle, 0, 0),
		color,
		parent,
		material,
		transparency
	)
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

local function buildBillboard(model, body, height)
	local anchor = makePart("Label", Vector3.new(0.2, 0.2, 0.2), body.CFrame * CFrame.new(0, height, 0), CHROME, model)
	anchor.Transparency = 1
	anchor.CanQuery = false

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(9, 2.4)
	gui.MaxDistance = 90
	gui.Parent = anchor

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.55)
	title.Font = Enum.Font.Michroma
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextStrokeTransparency = 0.35
	title.Parent = gui

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromScale(0, 0.56)
	sub.Size = UDim2.fromScale(1, 0.44)
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(140, 235, 170)
	sub.TextStrokeTransparency = 0.45
	sub.Parent = gui

	return { part = anchor, title = title, sub = sub }
end

-- Alles, was die Silhouette macht -----------------------------------------
local function buildShell(model, cf, def, bodyY, bodyColor, bodyMaterial, paintTier)
	local halfLen = def.bodySize.Z / 2
	local halfWide = def.bodySize.X / 2
	local bodyTop = bodyY + def.bodySize.Y / 2
	local bodyBottom = bodyY - def.bodySize.Y / 2
	local roofTop = def.roofOffset.Y + def.roofSize.Y / 2
	local roofFront = def.roofOffset.Z - def.roofSize.Z / 2
	local roofBack = def.roofOffset.Z + def.roofSize.Z / 2
	local dark = bodyColor:Lerp(Color3.new(0, 0, 0), 0.55)
	local glassTop = math.max(roofTop - 0.25, bodyTop + 0.25)

	-- Glasflaechen. Frontscheibe faellt nach VORN (-Z) ab, Heckscheibe nach
	-- hinten - in v1 war das vertauscht.
	slab(
		model,
		"Windshield",
		cf,
		def.roofSize.X - 0.15,
		0.16,
		bodyTop,
		roofFront - RAKE_FRONT,
		glassTop,
		roofFront,
		GLASS_COLOR,
		Enum.Material.Glass,
		0.32
	)
	slab(
		model,
		"RearGlass",
		cf,
		def.roofSize.X - 0.15,
		0.16,
		glassTop,
		roofBack,
		bodyTop,
		roofBack + RAKE_REAR,
		GLASS_COLOR,
		Enum.Material.Glass,
		0.32
	)
	-- Seitenscheiben schliessen das Dach an die Karosserie an. Ohne sie
	-- schwebt das Dach ueber einer Luecke.
	for _, side in { -1, 1 } do
		makePart(
			"SideGlass",
			Vector3.new(0.14, glassTop - bodyTop, def.roofSize.Z),
			cf * CFrame.new(side * (def.roofSize.X / 2 - 0.05), (bodyTop + glassTop) / 2, def.roofOffset.Z),
			GLASS_COLOR,
			model,
			Enum.Material.Glass,
			0.32
		)
	end

	-- Haube und Heckdeckel: leichter Abfall nach aussen.
	slab(
		model,
		"Hood",
		cf,
		def.bodySize.X - 0.3,
		0.35,
		bodyTop - 0.1,
		roofFront - RAKE_FRONT,
		bodyTop - 0.55,
		-halfLen + 0.3,
		bodyColor,
		bodyMaterial
	)
	slab(
		model,
		"Deck",
		cf,
		def.bodySize.X - 0.3,
		0.35,
		bodyTop - 0.1,
		roofBack + RAKE_REAR,
		bodyTop - 0.4,
		halfLen - 0.3,
		bodyColor,
		bodyMaterial
	)

	-- Schweller
	for _, side in { -1, 1 } do
		makePart(
			"Sill",
			Vector3.new(0.5, 0.7, def.bodySize.Z * 0.66),
			cf * CFrame.new(side * (halfWide - 0.05), bodyBottom + 0.2, 0),
			dark,
			model
		)
	end

	-- Kotfluegel ueber jedem Rad plus dunkler Radkasten dahinter.
	local wheelDia = PartCatalog.GetSlot("tires").size.Y
	for _, xSide in { -1, 1 } do
		for _, zSide in { -1, 1 } do
			makePart(
				"Fender",
				Vector3.new(0.55, 1.0, wheelDia + 1.9),
				cf * CFrame.new(xSide * (def.track - 0.15), bodyY + 0.45, zSide * def.wheelbase),
				dark,
				model,
				Enum.Material.SmoothPlastic
			)
		end
		makePart(
			"WheelWell",
			Vector3.new(0.35, 2.0, wheelDia + 0.8),
			cf * CFrame.new(xSide * (halfWide - 0.25), bodyY, -def.wheelbase),
			NEAR_BLACK,
			model
		)
	end

	-- Nase: Grill, Splitter, Scheinwerfer, Leuchtenband hinten.
	makePart(
		"Grille",
		Vector3.new(def.bodySize.X * 0.46, 0.9, 0.35),
		cf * CFrame.new(0, bodyY + 0.05, -(halfLen + 0.1)),
		NEAR_BLACK,
		model,
		Enum.Material.DiamondPlate
	)
	for i = -1, 1 do
		makePart(
			"GrilleSlat",
			Vector3.new(def.bodySize.X * 0.44, 0.12, 0.42),
			cf * CFrame.new(0, bodyY + 0.05 + i * 0.28, -(halfLen + 0.13)),
			dark,
			model,
			Enum.Material.Metal
		)
	end
	makePart(
		"Splitter",
		Vector3.new(def.bodySize.X + 0.4, 0.28, 1.8),
		cf * CFrame.new(0, bodyBottom - 0.15, -(halfLen - 0.6)),
		NEAR_BLACK,
		model
	)
	makePart(
		"Diffuser",
		Vector3.new(def.bodySize.X + 0.2, 0.3, 1.6),
		cf * CFrame.new(0, bodyBottom - 0.12, halfLen - 0.6),
		NEAR_BLACK,
		model,
		Enum.Material.DiamondPlate
	)
	for _, side in { -1, 1 } do
		makePart(
			"Headlight",
			Vector3.new(1.6, 0.5, 0.3),
			cf * CFrame.new(side * (halfWide - 1.05), bodyTop - 0.4, -(halfLen + 0.08)),
			Color3.fromRGB(255, 248, 216),
			model,
			Enum.Material.Neon
		)
	end
	-- Durchgehendes Leuchtenband statt zwei Punkten: das ist der Unterschied
	-- zwischen "alt" und "neu" an einem Autoheck.
	makePart(
		"TailBar",
		Vector3.new(def.bodySize.X * 0.82, 0.34, 0.26),
		cf * CFrame.new(0, bodyTop - 0.4, halfLen + 0.08),
		Color3.fromRGB(240, 40, 52),
		model,
		Enum.Material.Neon
	)

	-- Aussenspiegel. Zwei Teile pro Seite, und das Auto liest sich sofort
	-- als Auto statt als Kiste.
	for _, side in { -1, 1 } do
		makePart(
			"MirrorArm",
			Vector3.new(0.6, 0.16, 0.16),
			cf * CFrame.new(side * (halfWide + 0.3), bodyTop + 0.05, roofFront + 0.4),
			dark,
			model
		)
		makePart(
			"MirrorHead",
			Vector3.new(0.28, 0.42, 0.55),
			cf * CFrame.new(side * (halfWide + 0.62), bodyTop + 0.12, roofFront + 0.4),
			paintTier >= 3 and CHROME or dark,
			model,
			paintTier >= 3 and Enum.Material.Metal or Enum.Material.SmoothPlastic
		)
	end

	-- Auspuff, immer vorhanden. Die Turbo-Stufe legt spaeter noch welche nach.
	for _, side in { -1, 1 } do
		local pipe = makePart(
			"Tailpipe",
			Vector3.new(0.85, 0.62, 0.62),
			cf * CFrame.new(side * 1.3, bodyBottom - 0.05, halfLen + 0.25) * CFrame.Angles(0, math.rad(90), 0),
			CHROME,
			model,
			Enum.Material.Metal
		)
		pipe.Shape = Enum.PartType.Cylinder
	end

	return bodyTop, halfLen
end

-- Rad mit Felge. Speichenzahl bewusst niedrig: an einem stehenden Auto
-- kostet jede weitere Speiche Parts und bringt nichts.
local function buildWheel(model, cf, def, xSign, zSign, tier, tierDef)
	local wheelSize = PartCatalog.GetSlot("tires").size
	local width = wheelSize.X + (tier and (tier - 1) * 0.22 or 0)
	local diameter = wheelSize.Y + (tier and (tier - 1) * 0.18 or 0)

	local wheel = makePart(
		"Wheel",
		Vector3.new(width, diameter, diameter),
		cf * CFrame.new(xSign * def.track, diameter / 2, zSign * def.wheelbase),
		tierDef and tierDef.color or GHOST_COLOR,
		model,
		Enum.Material.Rubber,
		tierDef and 0 or 0.65
	)
	wheel.Shape = Enum.PartType.Cylinder
	if not tierDef then
		return wheel, {}
	end

	local extras = {}
	local rimColor = if tier >= 4
		then Color3.fromRGB(120, 240, 255)
		elseif tier == 3 then CHROME
		else Color3.fromRGB(150, 155, 165)
	local rim = makePart(
		"Rim",
		Vector3.new(width * 0.46, diameter * 0.64, diameter * 0.64),
		wheel.CFrame * CFrame.new(xSign * width * 0.32, 0, 0),
		rimColor,
		model,
		if tier >= 4 then Enum.Material.Neon else Enum.Material.Metal
	)
	rim.Shape = Enum.PartType.Cylinder
	table.insert(extras, rim)

	if tier >= 2 then
		local spokes = tier >= 4 and 3 or 2
		for i = 0, spokes - 1 do
			table.insert(
				extras,
				makePart(
					"Spoke",
					Vector3.new(width * 0.42, diameter * 0.58, 0.3),
					wheel.CFrame * CFrame.new(xSign * width * 0.33, 0, 0) * CFrame.Angles(math.rad(i * 180 / spokes), 0, 0),
					rimColor,
					model,
					Enum.Material.Metal
				)
			)
		end
	end
	-- Bremsscheibe: dunkler Ring hinter der Felge, sichtbar nur bei den
	-- breiten Stufen - genau da, wo man hinschaut.
	if tier >= 3 then
		local disc = makePart(
			"Brake",
			Vector3.new(width * 0.3, diameter * 0.5, diameter * 0.5),
			wheel.CFrame * CFrame.new(xSign * width * 0.1, 0, 0),
			Color3.fromRGB(58, 60, 66),
			model,
			Enum.Material.Metal
		)
		disc.Shape = Enum.PartType.Cylinder
		table.insert(extras, disc)
	end

	return wheel, extras
end

local function buildEngine(model, slotDef, tier, tierDef, mount)
	local parts = {}
	local main = makePart(
		slotDef.displayName,
		slotDef.size,
		mount,
		tierDef and tierDef.color or GHOST_COLOR,
		model,
		tierDef and Enum.Material.Metal or Enum.Material.ForceField,
		tierDef and 0 or 0.6
	)
	if not tierDef then
		return main, parts
	end
	if tier >= 2 then
		for _, side in { -1, 1 } do
			table.insert(
				parts,
				makePart(
					"ValveCover",
					Vector3.new(0.7, 0.4, slotDef.size.Z * 0.8),
					mount * CFrame.new(side * 0.85, slotDef.size.Y / 2 + 0.2, 0),
					tierDef.color:Lerp(Color3.new(1, 1, 1), 0.25),
					model,
					Enum.Material.Metal
				)
			)
		end
	end
	if tier >= 3 then
		local horn = makePart(
			"Intake",
			Vector3.new(1.5, 1.5, 1.5),
			mount * CFrame.new(0, slotDef.size.Y / 2 + 0.85, 0) * CFrame.Angles(0, 0, math.rad(90)),
			CHROME,
			model,
			Enum.Material.Metal
		)
		horn.Shape = Enum.PartType.Cylinder
		table.insert(parts, horn)
	end
	if tier >= 4 then
		for _, side in { -1, 1 } do
			table.insert(
				parts,
				makePart(
					"Intercooler",
					Vector3.new(0.5, 0.9, 1.8),
					mount * CFrame.new(side * 1.9, 0.1, 0),
					tierDef.color,
					model,
					Enum.Material.Neon
				)
			)
		end
	end
	return main, parts
end

local function buildTurbo(model, slotDef, tier, tierDef, mount)
	local parts = {}
	local width = slotDef.size.X + (tierDef and (tier - 1) * 0.35 or 0)
	local main = makePart(
		slotDef.displayName,
		Vector3.new(width, slotDef.size.Y, slotDef.size.Z),
		mount,
		tierDef and tierDef.color or GHOST_COLOR,
		model,
		tierDef and Enum.Material.Metal or Enum.Material.ForceField,
		tierDef and 0 or 0.6
	)
	if not tierDef then
		return main, parts
	end
	for _, side in { -1, 1 } do
		table.insert(
			parts,
			makePart(
				"WingMount",
				Vector3.new(0.35, 0.9, 0.5),
				mount * CFrame.new(side * (width / 2 - 0.6), -0.6, 0),
				tierDef.color:Lerp(Color3.new(0, 0, 0), 0.3),
				model,
				Enum.Material.Metal
			)
		)
	end
	if tier >= 3 then
		table.insert(
			parts,
			makePart(
				"WingUpper",
				Vector3.new(width * 0.9, slotDef.size.Y * 0.8, slotDef.size.Z * 0.7),
				mount * CFrame.new(0, 0.9, -0.15),
				tierDef.color,
				model,
				tier >= 4 and Enum.Material.Neon or Enum.Material.Metal
			)
		)
	end
	return main, parts
end

function CarBuilder.Build(carState, carIndex: number, ownerUserId: number, cframe: CFrame, parent: Instance, options)
	local def = CarCatalog.Get(carState.carId) or CarCatalog.Get(CarCatalog.STARTER)
	local model = Instance.new("Model")
	model.Name = ("Car%d_%d"):format(carIndex, ownerUserId)
	model:SetAttribute("OwnerUserId", ownerUserId)
	model:SetAttribute("CarIndex", carIndex)
	model.Parent = parent

	-- Lack ---------------------------------------------------------------
	local paintPart = carState.parts.paint
	local paintTier = paintPart and paintPart.tier or 0
	local bodyColor = def.baseColor
	local paintSlot = PartCatalog.GetSlot("paint")
	local exclusivePaint = false
	if paintPart then
		local tierDef = PartCatalog.GetTier("paint", paintTier)
		if tierDef then
			bodyColor = tierDef.color
		end
		-- exclusivePaint kommt aus Config.REBIRTH_UNLOCKS und wird vom Aufrufer
		-- durchgereicht; rebirths bleibt als Rueckfallweg fuer Aufrufer, die
		-- die Freischaltungen nicht kennen (DerelictService baut ohne options).
		local rebirths = (options and options.rebirths) or 0
		local unlocked = (options and options.exclusivePaint)
			or rebirths >= Config.REBIRTH_PAINT_AT
		if unlocked and paintTier >= PartCatalog.TierCount("paint") then
			bodyColor = paintSlot.rebirthColor
			exclusivePaint = true
		end
	end

	local bodyMaterial, bodyReflectance = Enum.Material.CorrodedMetal, 0
	if exclusivePaint then
		bodyMaterial = Enum.Material.Neon
	elseif paintTier >= 4 then
		bodyMaterial, bodyReflectance = Enum.Material.Foil, 0.4
	elseif paintTier == 3 then
		bodyMaterial, bodyReflectance = Enum.Material.Metal, 0.15
	elseif paintTier >= 1 then
		bodyMaterial = Enum.Material.SmoothPlastic
	end

	local bodyY = 1.2
	local body = makePart("Body", def.bodySize, cframe * CFrame.new(0, bodyY, 0), bodyColor, model, bodyMaterial)
	body.Reflectance = bodyReflectance
	body.CanCollide = true
	body.CastShadow = true
	model.PrimaryPart = body

	makePart(
		"Roof",
		def.roofSize,
		cframe * CFrame.new(def.roofOffset.X, def.roofOffset.Y, def.roofOffset.Z),
		bodyColor:Lerp(Color3.new(0, 0, 0), 0.25),
		model,
		bodyMaterial
	)

	local bodyTop, halfLen = buildShell(model, cframe, def, bodyY, bodyColor, bodyMaterial, paintTier)

	if paintTier >= 4 then
		for _, side in { -1, 1 } do
			makePart(
				"Underglow",
				Vector3.new(0.4, 0.2, def.bodySize.Z * 0.8),
				cframe * CFrame.new(side * (def.bodySize.X / 2 - 0.4), 0.25, 0),
				exclusivePaint and paintSlot.rebirthColor or bodyColor,
				model,
				Enum.Material.Neon
			)
		end
	end

	local prompts, slotParts = {}, {}
	local anchors = { paint = body }

	if paintPart then
		tagPart(body, "paint", paintPart, ownerUserId, carIndex)
		prompts.paint = addStealPrompt(body, "paint", paintPart, ownerUserId, carIndex)
		slotParts.paint = { body }
	end

	-- Reifen ---------------------------------------------------------------
	local tirePart = carState.parts.tires
	local tireTier = tirePart and tirePart.tier or nil
	local tireDef = tirePart and PartCatalog.GetTier("tires", tirePart.tier)
	local wheels = {}
	for _, xSign in { -1, 1 } do
		for _, zSign in { -1, 1 } do
			local wheel, extras = buildWheel(model, cframe, def, xSign, zSign, tireTier, tireDef)
			table.insert(wheels, wheel)
			for _, extra in extras do
				table.insert(wheels, extra)
			end
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

	-- Motor und Turbo ------------------------------------------------------
	for _, slotId in { "engine", "turbo" } do
		local slotDef = PartCatalog.GetSlot(slotId)
		local statePart = carState.parts[slotId]
		local tier = statePart and statePart.tier or nil
		local tierDef = statePart and PartCatalog.GetTier(slotId, statePart.tier)
		local offset = if slotDef.mount == "spoiler"
			then Vector3.new(0, bodyTop + slotDef.size.Y / 2 + 0.25, halfLen - slotDef.size.Z / 2 - 0.4)
			else Vector3.new(0, bodyTop + slotDef.size.Y / 2 - 0.2, -(halfLen - slotDef.size.Z / 2 - 0.7))
		local mount = cframe * CFrame.new(offset)

		local main, extras
		if slotDef.mount == "spoiler" then
			main, extras = buildTurbo(model, slotDef, tier, tierDef, mount)
		else
			main, extras = buildEngine(model, slotDef, tier, tierDef, mount)
		end

		anchors[slotId] = main
		if statePart then
			tagPart(main, slotId, statePart, ownerUserId, carIndex)
			for _, extra in extras do
				tagPart(extra, slotId, statePart, ownerUserId, carIndex)
			end
			prompts[slotId] = addStealPrompt(main, slotId, statePart, ownerUserId, carIndex)
			local group = { main }
			for _, extra in extras do
				table.insert(group, extra)
			end
			slotParts[slotId] = group
		end
	end

	local billboard = buildBillboard(model, body, def.bodySize.Y / 2 + 4.2)
	billboard.title.Text = def.displayName
	billboard.sub.Text = Util.FormatRate(0)

	return {
		model = model,
		body = body,
		prompts = prompts,
		slotParts = slotParts,
		anchors = anchors,
		billboard = billboard,
		carIndex = carIndex,
	}
end

return CarBuilder
