--!strict
-- The headquarters' single material palette. Generators never invent ad-hoc colours: large
-- surfaces stay material-true (stone, oak, plaster, metal, glass); the company colour only tints
-- signage, a few accent surfaces and screens.
local P = {}

local rgb = Color3.fromRGB

P.color = {
	stone = rgb(216, 212, 201), -- warm light natural stone (facade, plinth, floors)
	stoneDeep = rgb(190, 184, 171), -- shadowed stone, reveals, copings
	stonePave = rgb(184, 180, 170), -- outdoor paving
	interior = rgb(239, 236, 228), -- light interior plaster
	plasterShade = rgb(226, 222, 212),
	metal = rgb(38, 43, 47), -- dark metal profiles, mullions, frames
	metalSoft = rgb(66, 72, 77),
	oak = rgb(151, 111, 76), -- warm oak
	oakLight = rgb(178, 140, 101),
	oakDark = rgb(112, 81, 56),
	sage = rgb(104, 126, 111), -- calm sage green
	sageLight = rgb(150, 168, 152),
	blue = rgb(94, 136, 162), -- subtle technical blue
	blueSoft = rgb(158, 186, 202),
	glass = rgb(196, 219, 228), -- light, slightly cool glass
	glassDeep = rgb(150, 182, 196),
	concrete = rgb(176, 175, 170),
	asphalt = rgb(58, 61, 63),
	carpet = rgb(126, 131, 128),
	carpetWarm = rgb(150, 138, 122),
	fabric = rgb(112, 132, 118),
	fabricSand = rgb(198, 184, 160),
	fabricCharcoal = rgb(70, 74, 78),
	fabricBlue = rgb(98, 118, 136),
	leather = rgb(120, 86, 62),
	white = rgb(246, 244, 239),
	screen = rgb(22, 27, 31),
	brass = rgb(178, 150, 98),
	terracotta = rgb(170, 110, 84),
	foliage = rgb(80, 112, 76),
	foliageLight = rgb(112, 142, 96),
	grass = rgb(104, 134, 94),
	soil = rgb(70, 60, 47),
	water = rgb(118, 166, 178),
	lightWarm = rgb(255, 234, 204),
	lightNeutral = rgb(246, 244, 236),
	lightCool = rgb(226, 238, 248),
	lightSecret = rgb(176, 196, 255),
	statusGood = rgb(120, 190, 150),
	statusBad = rgb(214, 104, 92),
	statusBusy = rgb(226, 186, 110),
}

P.material = {
	stone = Enum.Material.Limestone,
	pave = Enum.Material.Pavement,
	plaster = Enum.Material.Plaster,
	metal = Enum.Material.Metal,
	wood = Enum.Material.Wood,
	planks = Enum.Material.WoodPlanks,
	glass = Enum.Material.Glass,
	concrete = Enum.Material.Concrete,
	carpet = Enum.Material.Carpet,
	fabric = Enum.Material.Fabric,
	leather = Enum.Material.Leather,
	tile = Enum.Material.CeramicTiles,
	marble = Enum.Material.Marble,
	slate = Enum.Material.Slate,
	rubber = Enum.Material.Rubber,
	asphalt = Enum.Material.Asphalt,
	grass = Enum.Material.Grass,
	leafy = Enum.Material.LeafyGrass,
	smooth = Enum.Material.SmoothPlastic,
	neon = Enum.Material.Neon,
}

-- Tested-in-code defaults (verify in Studio): glass stays readable without milky stacking.
P.glassTransparency = 0.62 -- facade and partitions
P.glassTransparencyDoor = 0.55
P.railTransparency = 0.5

-- Light moods per room (BuildingPlan room.mood)
P.mood = {
	warm = { color = P.color.lightWarm, brightness = 0.75, range = 18 },
	neutral = { color = P.color.lightNeutral, brightness = 0.7, range = 18 },
	cool = { color = P.color.lightCool, brightness = 0.7, range = 18 },
	tech = { color = P.color.lightCool, brightness = 0.6, range = 16 },
	founder = { color = rgb(255, 226, 190), brightness = 0.7, range = 20 },
	secret = { color = P.color.lightSecret, brightness = 0.5, range = 16 },
	wellness = { color = rgb(255, 230, 200), brightness = 0.6, range = 18 },
}

-- Department accent tints for identity panels (desaturated so they read as material, not toy colour)
P.department = {
	data = rgb(105, 140, 153),
	engineering = rgb(108, 133, 123),
	design = rgb(147, 137, 107),
	training = rgb(96, 128, 150),
	research = rgb(126, 121, 149),
	evaluation = rgb(129, 149, 115),
	growth = rgb(168, 133, 109),
	deployment = rgb(160, 128, 104),
	operations = rgb(120, 126, 120),
	compute = rgb(90, 118, 140),
	executive = rgb(150, 120, 88),
}

return P
