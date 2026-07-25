--[[
	CarBuilder (Visual-Rewrite)

	Gleiche oeffentliche API:
		CarBuilder.Build(carState, carIndex, ownerUserId, cframe, parent, options)
		-> { model, body, prompts, slotParts, anchors, billboard, carIndex }

	Kernaenderung gegenueber vorher: die Stufe eines Teils ist AM AUTO
	ablesbar, nicht nur im Menue. Vorher waren T1 und T4 dieselbe Kiste in
	einer anderen Farbe - der Spieler zahlt 36.000 fuer den Anti-Lag-Kit und
	sieht nichts. Jetzt waechst mit jeder Stufe Geometrie dazu:

		Motor  T1..T4  flacher Deckel -> Haubenausschnitt -> Kompressor mit
		               Ansaugtrichter -> zusaetzliche Ladeluftkuehler
		Reifen T1..T4  Stahlfelge -> Felge mit Speichen -> breiterer Reifen
		               -> Neonfelge
		Turbo  T1..T4  Lippe -> Fluegel -> Doppelfluegel mit Stuetzen ->
		               Neon-Fluegel
		Lack   T1..T4  matt -> lackiert -> Metallic -> Chrom + Underglow

	Fehlende Teile bleiben durchsichtige Platzhalter: auf einen Blick sieht
	man, was der Karre fehlt. Das war vorher schon richtig.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.CarCatalog)
local Config = require(Shared.Config)
local PartCatalog = require(Shared.PartCatalog)
local Util = require(Shared.Util)

local CarBuilder = {}

local GHOST_COLOR = Color3.fromRGB(220, 70, 70)
local GLASS_COLOR = Color3.fromRGB(28, 32, 42)
local CHROME = Color3.fromRGB(206, 212, 224)

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

local function makeWedge(name, size, cframe, color, parent, material, transparency)
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.CanCollide = false
	w.CastShadow = false
	w.Size = size
	w.CFrame = cframe
	w.Color = color
	w.Material = material or Enum.Material.SmoothPlastic
	w.Transparency = transparency or 0
	w.Parent = parent
	return w
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

-- Das Schild haengt jetzt IM Modell. Vorher lag es daneben und musste
-- ueberall extra zerstoert werden - eine Leak-Quelle bei jedem Rebuild.
local function buildBillboard(model, body, height)
	local attachment = Instance.new("Part")
	attachment.Name = "Label"
	attachment.Anchored = true
	attachment.CanCollide = false
	attachment.CanQuery = false
	attachment.CastShadow = false
	attachment.Transparency = 1
	attachment.Size = Vector3.new(0.2, 0.2, 0.2)
	attachment.CFrame = body.CFrame * CFrame.new(0, height, 0)
	attachment.Parent = model

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(9, 2.4)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 90
	gui.Parent = attachment

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

	return { part = attachment, title = title, sub = sub }
end

-- Karosserie-Details, die es vorher gar nicht gab: Scheiben, Schweller,
-- Stossfaenger, Scheinwerfer. Kosten sechs Parts und machen aus zwei Kisten
-- ein Auto.
local function buildBodyDetails(model, cframe, carDef, bodyY, bodyColor)
	local halfLength = carDef.bodySize.Z / 2
	local bodyTop = bodyY + carDef.bodySize.Y / 2
	local dark = bodyColor:Lerp(Color3.new(0, 0, 0), 0.55)

	-- Schweller: dunkler Streifen unten laengs. Setzt das Auto optisch auf
	-- die Raeder statt es schweben zu lassen.
	for _, side in { -1, 1 } do
		makePart(
			"Sill",
			Vector3.new(0.5, 0.7, carDef.bodySize.Z * 0.72),
			cframe * CFrame.new(side * (carDef.bodySize.X / 2 - 0.1), bodyY - carDef.bodySize.Y / 2 + 0.15, 0),
			dark,
			model,
			Enum.Material.SmoothPlastic
		)
	end

	-- Stossfaenger vorn und hinten
	for _, z in { -1, 1 } do
		makePart(
			"Bumper",
			Vector3.new(carDef.bodySize.X + 0.2, 0.9, 0.8),
			cframe * CFrame.new(0, bodyY - 0.3, z * (halfLength - 0.3)),
			dark,
			model,
			Enum.Material.SmoothPlastic
		)
	end

	-- Scheiben: Front- und Heckscheibe als Keile am Dach.
	local roofY = carDef.roofOffset.Y
	local roofHalf = carDef.roofSize.Z / 2
	makeWedge(
		"Windshield",
		Vector3.new(carDef.roofSize.X - 0.2, carDef.roofSize.Y, 1.8),
		cframe
			* CFrame.new(carDef.roofOffset.X, roofY - 0.1, carDef.roofOffset.Z + roofHalf + 0.85)
			* CFrame.Angles(0, math.pi, 0),
		GLASS_COLOR,
		model,
		Enum.Material.Glass,
		0.35
	)
	makeWedge(
		"RearGlass",
		Vector3.new(carDef.roofSize.X - 0.2, carDef.roofSize.Y, 1.6),
		cframe * CFrame.new(carDef.roofOffset.X, roofY - 0.1, carDef.roofOffset.Z - roofHalf - 0.75),
		GLASS_COLOR,
		model,
		Enum.Material.Glass,
		0.35
	)

	-- Scheinwerfer vorn (Motor sitzt hinten in diesem Modell: -Z ist vorn)
	for _, side in { -1, 1 } do
		makePart(
			"Headlight",
			Vector3.new(1.5, 0.6, 0.3),
			cframe * CFrame.new(side * (carDef.bodySize.X / 2 - 1.1), bodyY + 0.15, -(halfLength + 0.05)),
			Color3.fromRGB(255, 246, 214),
			model,
			Enum.Material.Neon
		)
		makePart(
			"Taillight",
			Vector3.new(1.5, 0.45, 0.3),
			cframe * CFrame.new(side * (carDef.bodySize.X / 2 - 1.1), bodyY + 0.2, halfLength + 0.05),
			Color3.fromRGB(235, 45, 55),
			model,
			Enum.Material.Neon
		)
	end

	return bodyTop, halfLength
end

-- Rad inkl. Felge. Die Felge waechst mit der Reifenstufe - das ist der
-- billigste sichtbare Fortschritt im ganzen Spiel.
local function buildWheel(model, cframe, carDef, xSign, zSign, tier, tierDef)
	local wheelSize = PartCatalog.GetSlot("tires").size
	local width = wheelSize.X + (tier and (tier - 1) * 0.22 or 0)
	local diameter = wheelSize.Y + (tier and (tier - 1) * 0.18 or 0)

	local wheel = makePart(
		"Wheel",
		Vector3.new(width, diameter, diameter),
		cframe * CFrame.new(xSign * carDef.track, diameter / 2, zSign * carDef.wheelbase),
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
	-- Felge: hell, leicht nach aussen versetzt.
	local rimColor = if tier >= 4 then Color3.fromRGB(120, 240, 255) elseif tier == 3 then CHROME else Color3.fromRGB(
		150,
		155,
		165
	)
	local rim = makePart(
		"Rim",
		Vector3.new(width * 0.45, diameter * 0.62, diameter * 0.62),
		wheel.CFrame * CFrame.new(xSign * width * 0.32, 0, 0),
		rimColor,
		model,
		if tier >= 4 then Enum.Material.Neon else Enum.Material.Metal
	)
	rim.Shape = Enum.PartType.Cylinder
	table.insert(extras, rim)

	-- Ab T2 Speichen. Vier duenne Balken reichen, um die Felge zu lesen.
	if tier >= 2 then
		for i = 0, 3 do
			local spoke = makePart(
				"Spoke",
				Vector3.new(width * 0.42, diameter * 0.56, 0.28),
				wheel.CFrame
					* CFrame.new(xSign * width * 0.33, 0, 0)
					* CFrame.Angles(math.rad(i * 45), 0, 0),
				rimColor,
				model,
				Enum.Material.Metal
			)
			table.insert(extras, spoke)
		end
	end

	return wheel, extras
end

-- Motoraufbau auf der Haube. Waechst mit der Stufe.
local function buildEngine(model, cframe, slotDef, tier, tierDef, mountCFrame)
	local parts = {}
	local main = makePart(
		slotDef.displayName,
		slotDef.size,
		mountCFrame,
		tierDef and tierDef.color or GHOST_COLOR,
		model,
		tierDef and Enum.Material.Metal or Enum.Material.ForceField,
		tierDef and 0 or 0.6
	)
	if not tierDef then
		return main, parts
	end

	-- T2+: Ventildeckel laengs
	if tier >= 2 then
		for _, side in { -1, 1 } do
			table.insert(
				parts,
				makePart(
					"ValveCover",
					Vector3.new(0.7, 0.4, slotDef.size.Z * 0.8),
					mountCFrame * CFrame.new(side * 0.85, slotDef.size.Y / 2 + 0.2, 0),
					tierDef.color:Lerp(Color3.new(1, 1, 1), 0.25),
					model,
					Enum.Material.Metal
				)
			)
		end
	end
	-- T3+: Ansaugtrichter mittig, deutlich sichtbar ueber der Haube
	if tier >= 3 then
		local horn = makePart(
			"Intake",
			Vector3.new(1.5, 1.5, 1.5),
			mountCFrame * CFrame.new(0, slotDef.size.Y / 2 + 0.85, 0),
			CHROME,
			model,
			Enum.Material.Metal
		)
		horn.Shape = Enum.PartType.Cylinder
		horn.CFrame = mountCFrame * CFrame.new(0, slotDef.size.Y / 2 + 0.85, 0) * CFrame.Angles(0, 0, math.rad(90))
		table.insert(parts, horn)
	end
	-- T4: Ladeluftkuehler links und rechts, leuchtend
	if tier >= 4 then
		for _, side in { -1, 1 } do
			table.insert(
				parts,
				makePart(
					"Intercooler",
					Vector3.new(0.5, 0.9, 1.8),
					mountCFrame * CFrame.new(side * 1.9, 0.1, 0),
					tierDef.color,
					model,
					Enum.Material.Neon
				)
			)
		end
	end
	return main, parts
end

-- Heckfluegel. Ab T3 doppelstoeckig, ab T4 leuchtend.
local function buildTurbo(model, cframe, slotDef, tier, tierDef, mountCFrame)
	local parts = {}
	local width = slotDef.size.X + (tierDef and (tier - 1) * 0.35 or 0)
	local main = makePart(
		slotDef.displayName,
		Vector3.new(width, slotDef.size.Y, slotDef.size.Z),
		mountCFrame,
		tierDef and tierDef.color or GHOST_COLOR,
		model,
		tierDef and Enum.Material.Metal or Enum.Material.ForceField,
		tierDef and 0 or 0.6
	)
	if not tierDef then
		return main, parts
	end

	-- Stuetzen: ohne sie schwebt der Fluegel.
	for _, side in { -1, 1 } do
		table.insert(
			parts,
			makePart(
				"WingMount",
				Vector3.new(0.35, 0.9, 0.5),
				mountCFrame * CFrame.new(side * (width / 2 - 0.6), -0.6, 0),
				tierDef.color:Lerp(Color3.new(0, 0, 0), 0.3),
				model,
				Enum.Material.Metal
			)
		)
	end
	-- T3+: zweites Element darueber
	if tier >= 3 then
		table.insert(
			parts,
			makePart(
				"WingUpper",
				Vector3.new(width * 0.9, slotDef.size.Y * 0.8, slotDef.size.Z * 0.7),
				mountCFrame * CFrame.new(0, 0.9, -0.15),
				tierDef.color,
				model,
				tier >= 4 and Enum.Material.Neon or Enum.Material.Metal
			)
		)
	end
	-- T4: Auspuffendrohre. Das ist der "das Ding ist fertig"-Marker.
	if tier >= 4 then
		for _, side in { -1, 1 } do
			local pipe = makePart(
				"Exhaust",
				Vector3.new(1.2, 0.8, 0.8),
				mountCFrame * CFrame.new(side * 1.6, -2.1, 0.6) * CFrame.Angles(0, 0, math.rad(90)),
				CHROME,
				model,
				Enum.Material.Metal
			)
			pipe.Shape = Enum.PartType.Cylinder
			table.insert(parts, pipe)
		end
	end
	return main, parts
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

	-- Lack --------------------------------------------------------------
	local paintPart = carState.parts.paint
	local paintTier = paintPart and paintPart.tier or 0
	local bodyColor = carDef.baseColor
	local paintSlot = PartCatalog.GetSlot("paint")
	local exclusivePaint = false
	if paintPart then
		local tierDef = PartCatalog.GetTier("paint", paintTier)
		if tierDef then
			bodyColor = tierDef.color
		end
		local rebirths = (options and options.rebirths) or 0
		if rebirths >= Config.REBIRTH_PAINT_AT and paintTier >= PartCatalog.TierCount("paint") then
			bodyColor = paintSlot.rebirthColor
			exclusivePaint = true
		end
	end

	-- Material nach Lackstufe. Rost -> Lack -> Metallic -> Chrom.
	local bodyMaterial = Enum.Material.CorrodedMetal
	local bodyReflectance = 0
	if exclusivePaint then
		bodyMaterial = Enum.Material.Neon
	elseif paintTier >= 4 then
		bodyMaterial = Enum.Material.Foil
		bodyReflectance = 0.4
	elseif paintTier == 3 then
		bodyMaterial = Enum.Material.Metal
		bodyReflectance = 0.15
	elseif paintTier >= 1 then
		bodyMaterial = Enum.Material.SmoothPlastic
	end

	local bodyY = 1.2
	local body = makePart("Body", carDef.bodySize, cframe * CFrame.new(0, bodyY, 0), bodyColor, model, bodyMaterial)
	body.Reflectance = bodyReflectance
	body.CanCollide = true
	body.CastShadow = true
	model.PrimaryPart = body

	makePart(
		"Roof",
		carDef.roofSize,
		cframe * CFrame.new(carDef.roofOffset.X, carDef.roofOffset.Y, carDef.roofOffset.Z),
		bodyColor:Lerp(Color3.new(0, 0, 0), 0.25),
		model,
		bodyMaterial
	)

	local bodyTop, halfLength = buildBodyDetails(model, cframe, carDef, bodyY, bodyColor)

	-- Underglow ab der hoechsten Lackstufe.
	if paintTier >= 4 then
		for _, side in { -1, 1 } do
			makePart(
				"Underglow",
				Vector3.new(0.4, 0.2, carDef.bodySize.Z * 0.8),
				cframe * CFrame.new(side * (carDef.bodySize.X / 2 - 0.4), 0.25, 0),
				exclusivePaint and paintSlot.rebirthColor or bodyColor,
				model,
				Enum.Material.Neon
			)
		end
	end

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
	local tireTier = tirePart and tirePart.tier or nil
	local tireDef = tirePart and PartCatalog.GetTier("tires", tirePart.tier)
	local wheels = {}
	for _, xSign in { -1, 1 } do
		for _, zSign in { -1, 1 } do
			local wheel, extras = buildWheel(model, cframe, carDef, xSign, zSign, tireTier, tireDef)
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

	-- Motor und Turbo ----------------------------------------------------
	for _, slotId in { "engine", "turbo" } do
		local slotDef = PartCatalog.GetSlot(slotId)
		local statePart = carState.parts[slotId]
		local tier = statePart and statePart.tier or nil
		local tierDef = statePart and PartCatalog.GetTier(slotId, statePart.tier)
		local offset
		if slotDef.mount == "spoiler" then
			offset = Vector3.new(0, bodyTop + slotDef.size.Y / 2 + 0.25, halfLength - slotDef.size.Z / 2 - 0.4)
		else
			offset = Vector3.new(0, bodyTop + slotDef.size.Y / 2 - 0.2, -(halfLength - slotDef.size.Z / 2 - 0.7))
		end
		local mountCFrame = cframe * CFrame.new(offset)

		local main, extras
		if slotDef.mount == "spoiler" then
			main, extras = buildTurbo(model, cframe, slotDef, tier, tierDef, mountCFrame)
		else
			main, extras = buildEngine(model, cframe, slotDef, tier, tierDef, mountCFrame)
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

	local billboard = buildBillboard(model, body, carDef.bodySize.Y / 2 + 4.2)
	billboard.title.Text = carDef.displayName
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
