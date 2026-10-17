--!strict
-- Circulation core of the headquarters: the lift shaft with a framed portal at every stop, the
-- physical lift cabin, the landing door sets, the switchback stair (smooth invisible ramps under
-- stone treads), the riser closure and the roof head house. Geometry only: LiftService drives the
-- cabin and landing doors, the wall planner (BuildingLayout) supplies the stair room walls and door.
-- Everything is built in building-local studs through ctx.cf, so the core works on every plot.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Plan = require(ReplicatedStorage.Shared.Config.BuildingPlan)
local P = require(ReplicatedStorage.Shared.Config.ArchPalette)

local CoreDesign = {}

export type Context = {
	office: Model,
	cf: CFrame,
	tier: number,
	floors: number,
	owner: number,
	accent: Color3,
	company: string,
	folders: { [string]: Instance },
}
export type Result = {
	landings: { [number]: Model },
	cabin: Model,
	guide: Part,
}

local COLOR, MAT = P.color, P.material

-- Shaft: 0.5 thick walls centred on the SHAFT outline.
local SH = Plan.SHAFT
local WALL = 0.5
local FZ1, FZ2 = SH.z1 - WALL / 2, SH.z1 + WALL / 2 -- front wall 53.75..54.25
local BZ1, BZ2 = SH.z2 - WALL / 2, SH.z2 + WALL / 2 -- back wall 67.75..68.25
local SXO, SXI = SH.x2 + WALL / 2, SH.x2 - WALL / 2 -- side walls |x| 6.75..7.25
local PIT_DEPTH = 4
local SHAFT_TOP = 13 -- shaft walls end at roof + 13 (head house slab top), cap above
local HEAD_HOUSE = 12 -- head house walls are 12 high, its roof slab sits on them

-- Landing doors: two leaves just in front of the shaft wall, parking behind the portal cladding.
local DOOR = Plan.LIFT_DOOR
local LEAF_W, LEAF_T, LEAF_SLIDE = 3.05, 0.3, 3.0
local LEAF_Z = FZ1 - LEAF_T / 2 -- 53.6
local LEAF_LIFT = 0.01 -- leaves run on the sill, whose top is 0.01 proud of the slab
local SILL_DEPTH = 0.17 -- sill bottom below the floor line
local PORTAL_FRONT = LEAF_Z - LEAF_T / 2 -- 53.45: cladding/jamb back face (leaves slide behind it)

-- Cabin (built resting at level 0). See SPEC §4.
local CB = Plan.CABIN
local CAB_Z = (CB.z1 + CB.z2) / 2 -- 60.8
local CAB_LEAF_Z = 54.97 -- cabin leaves z 54.82..55.12, front wall pieces behind them
local CAB_FRONT1, CAB_FRONT2 = 55.13, 55.28 -- front wall pieces (inside the leaves)
local CAB_BACK = 66.66 -- back wall inner face; oak/mirror lining in front of it
local CAB_SIDE = 5.86 -- side wall inner face (|x|); oak lining in front of it
local CAB_DOOR_H = DOOR.height
local CAB_CEIL = CB.height -- 10.4: ceiling bottom

-- Stair
local ST = Plan.STAIR_LAYOUT
local STEPS = 16
local RAMP_T = 0.4 -- invisible ramp thickness (perpendicular)
local WAIST = 1 -- vertical thickness of the visible stair waist (soffit slab)
local RAIL_H = 3.2 -- handrail height above the walking line

-- ---------------------------------------------------------------------------------------------
-- Part helpers (ArchKit is written in parallel; the core keeps its own tiny kit)

local function block(parent: Instance, cf: CFrame, name: string, size: Vector3, at: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf * at
	p.Anchored = true
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Axis-aligned block between two building-local corners.
local function box(parent: Instance, cf: CFrame, name: string, x1: number, x2: number, y1: number, y2: number, z1: number, z2: number, color: Color3, material: Enum.Material): Part
	return block(parent, cf, name, Vector3.new(x2 - x1, y2 - y1, z2 - z1), CFrame.new((x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2), color, material)
end

-- Rotation about X that lays a block's local Z along the (dy, dz) direction; returns the angle
-- and the block's local up vector (0, ny, nz) (always pointing upwards).
local function pitch(dy: number, dz: number): (number, number, number, number)
	if dz < 0 then
		dy, dz = -dy, -dz
	end
	local a = -math.atan2(dy, dz)
	return a, math.cos(a), math.sin(a), math.sqrt(dy * dy + dz * dz)
end

-- Inclined block across x1..x2 whose TOP face runs exactly from (yA, zA) to (yB, zB).
local function slopeTop(parent: Instance, cf: CFrame, name: string, x1: number, x2: number, yA: number, zA: number, yB: number, zB: number, t: number, color: Color3, material: Enum.Material): Part
	local a, ny, nz, len = pitch(yB - yA, zB - zA)
	local at = CFrame.new((x1 + x2) / 2, (yA + yB) / 2 - ny * t / 2, (zA + zB) / 2 - nz * t / 2) * CFrame.Angles(a, 0, 0)
	return block(parent, cf, name, Vector3.new(x2 - x1, t, len), at, color, material)
end

-- Inclined block whose centre line runs from (yA, zA) to (yB, zB) (handrails).
local function slopeBeam(parent: Instance, cf: CFrame, name: string, x1: number, x2: number, yA: number, zA: number, yB: number, zB: number, h: number, color: Color3, material: Enum.Material): Part
	local a, _, _, len = pitch(yB - yA, zB - zA)
	local at = CFrame.new((x1 + x2) / 2, (yA + yB) / 2, (zA + zB) / 2) * CFrame.Angles(a, 0, 0)
	return block(parent, cf, name, Vector3.new(x2 - x1, h, len), at, color, material)
end

-- Decorative part: never collides, never blocks rays or touches.
local function detail(p: BasePart)
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
end

-- Invisible helper part (markers, guide, nodes).
local function ghost(p: BasePart)
	detail(p)
	p.Transparency = 1
	p.CastShadow = false
end

local function shaftPart(p: Instance)
	p:SetAttribute("LiftShaft", true)
end

local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function surface(part: BasePart, name: string, canvas: Vector2, light: number, maxDistance: number): SurfaceGui
	local g = Instance.new("SurfaceGui")
	g.Name = name
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	g.CanvasSize = canvas
	g.LightInfluence = light
	g.MaxDistance = maxDistance
	g.Parent = part
	return g
end

-- TextLabel positioned in scale coordinates of its SurfaceGui.
local function label(parent: Instance, name: string, text: string, x: number, y: number, w: number, h: number, color: Color3, font: Enum.Font, align: Enum.TextXAlignment): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromScale(x, y)
	t.Size = UDim2.fromScale(w, h)
	t.Text = text
	t.TextScaled = true
	t.TextWrapped = true
	t.TextColor3 = color
	t.Font = font
	t.TextXAlignment = align
	t.Parent = parent
	return t
end

local function prompt(part: BasePart, action: string, distance: number, campusAction: string, value: number?): ProximityPrompt
	local q = Instance.new("ProximityPrompt")
	q.ActionText = action
	q.ObjectText = "Lift"
	q.MaxActivationDistance = distance
	q.RequiresLineOfSight = false
	q.HoldDuration = 0
	q:SetAttribute("CampusAction", campusAction)
	q:SetAttribute("Public", true)
	if value ~= nil then
		q:SetAttribute("Value", value)
	end
	q.Parent = part
	return q
end

-- Level / Arrow / Status display used by the landing indicators and the cabin display.
local function display(part: BasePart, canvas: Vector2, level: string, status: string, accent: Color3, maxDistance: number)
	local g = surface(part, "Display", canvas, 0.1, maxDistance)
	label(g, "Level", level, 0.03, 0.06, 0.25, 0.88, COLOR.white, Enum.Font.BuilderSansBold, Enum.TextXAlignment.Center)
	label(g, "Arrow", "", 0.29, 0.14, 0.14, 0.72, accent, Enum.Font.BuilderSansBold, Enum.TextXAlignment.Center)
	label(g, "Status", status, 0.45, 0.2, 0.52, 0.6, COLOR.lightNeutral, Enum.Font.BuilderSansMedium, Enum.TextXAlignment.Left)
end

local function folderFor(ctx: Context, name: string): Instance
	local f = ctx.folders[name] or ctx.office:FindFirstChild(name)
	if f then
		return f
	end
	local made = Instance.new("Folder")
	made.Name = name
	made.Parent = ctx.office
	return made
end

-- ---------------------------------------------------------------------------------------------
-- Lift shaft: walls from the pit floor to roof + 13, door openings at every stop, pit, cap.

local function buildShaft(parent: Instance, cf: CFrame, tier: number)
	local m = model(parent, "LiftShaft")
	local roofY = Plan.levelY(Plan.roofLevel(tier))
	local pit = Plan.levelY(-1) - PIT_DEPTH
	local bottom, top = pit - 1, roofY + SHAFT_TOP
	local function add(p: Part)
		shaftPart(p)
	end
	add(box(m, cf, "ShaftBack", -SXO, SXO, bottom, top, BZ1, BZ2, COLOR.concrete, MAT.concrete))
	add(box(m, cf, "ShaftSide", -SXO, -SXI, bottom, top, FZ2, BZ1, COLOR.interior, MAT.plaster))
	add(box(m, cf, "ShaftSide", SXI, SXO, bottom, top, FZ2, BZ1, COLOR.interior, MAT.plaster))
	-- front wall: full-height piers beside the door line, spandrels between the openings
	add(box(m, cf, "ShaftFront", -SXO, DOOR.x1, bottom, top, FZ1, FZ2, COLOR.stone, MAT.stone))
	add(box(m, cf, "ShaftFront", DOOR.x2, SXO, bottom, top, FZ1, FZ2, COLOR.stone, MAT.stone))
	local below = bottom
	for _, stop in Plan.liftStops(tier) do
		add(box(m, cf, "ShaftSpandrel", DOOR.x1, DOOR.x2, below, stop.y - SILL_DEPTH, FZ1, FZ2, COLOR.stone, MAT.stone))
		below = stop.y + DOOR.height
	end
	add(box(m, cf, "ShaftSpandrel", DOOR.x1, DOOR.x2, below, top, FZ1, FZ2, COLOR.stone, MAT.stone))
	add(box(m, cf, "LiftPit", -SXI, SXI, bottom, pit, FZ2, BZ1, COLOR.concrete, MAT.concrete))
	for _, x in { -3.2, 3.2 } do
		local buffer = box(m, cf, "PitBuffer", x - 0.5, x + 0.5, pit, pit + 1.2, CAB_Z - 0.5, CAB_Z + 0.5, COLOR.metal, MAT.metal)
		add(buffer)
	end
	add(box(m, cf, "ShaftCap", -SXO - 0.25, SXO + 0.25, top, top + 0.5, FZ1 - 0.25, BZ2 + 0.25, COLOR.metal, MAT.metal))
end

-- Roof head house: roof slab over the lobby / stair / machine room / riser cluster, coping, and the
-- riser's back wall (the wall planner builds every other head house wall).
local function buildHeadHouse(parent: Instance, cf: CFrame, tier: number)
	local m = model(parent, "HeadHouse")
	local roofY = Plan.levelY(Plan.roofLevel(tier))
	local y1, y2 = roofY + HEAD_HOUSE, roofY + SHAFT_TOP
	local X, Z1, Z2 = 23, 41, 81 -- outline x -22..22, z 42..80 plus a small overhang
	local function add(p: Part)
		shaftPart(p)
	end
	-- the shaft passes through the slab up to its cap
	add(box(m, cf, "HeadHouseRoof", -X, X, y1, y2, Z1, FZ1, COLOR.concrete, MAT.concrete))
	add(box(m, cf, "HeadHouseRoof", -X, X, y1, y2, BZ2, Z2, COLOR.concrete, MAT.concrete))
	add(box(m, cf, "HeadHouseRoof", -X, -SXO, y1, y2, FZ1, BZ2, COLOR.concrete, MAT.concrete))
	add(box(m, cf, "HeadHouseRoof", SXO, X, y1, y2, FZ1, BZ2, COLOR.concrete, MAT.concrete))
	local c, lo, hi = 0.3, y1 - 0.3, y2 + 0.25
	add(box(m, cf, "HeadHouseCoping", -X - c, X + c, lo, hi, Z1 - c, Z1, COLOR.metal, MAT.metal))
	add(box(m, cf, "HeadHouseCoping", -X - c, X + c, lo, hi, Z2, Z2 + c, COLOR.metal, MAT.metal))
	add(box(m, cf, "HeadHouseCoping", -X - c, -X, lo, hi, Z1, Z2, COLOR.metal, MAT.metal))
	add(box(m, cf, "HeadHouseCoping", X, X + c, lo, hi, Z1, Z2, COLOR.metal, MAT.metal))
	local r = Plan.RISER
	add(box(m, cf, "RiserBackWall", r.x1 - 0.5, r.x2 + 0.5, roofY, y1, r.z2 - 0.5, r.z2 + 0.5, COLOR.stone, MAT.stone))
end

-- Portal around the landing doors: stone cladding hides the parked leaves, dark metal jambs + head.
local function buildPortal(parent: Instance, cf: CFrame, tier: number, level: number)
	local m = model(parent, "LiftPortal_" .. level)
	local y = Plan.levelY(level)
	local front, jambFront = 53.1, 52.95
	local j = 0.4
	for _, s in { -1, 1 } do
		local clad = box(m, cf, "PortalCladding", math.min(s * (DOOR.x2 + j), s * (SXO + 0.25)), math.max(s * (DOOR.x2 + j), s * (SXO + 0.25)), y, y + DOOR.height + 0.5, front, PORTAL_FRONT, COLOR.stoneDeep, MAT.marble)
		shaftPart(clad)
		local jamb = box(m, cf, "PortalJamb", math.min(s * DOOR.x2, s * (DOOR.x2 + j)), math.max(s * DOOR.x2, s * (DOOR.x2 + j)), y, y + DOOR.height, jambFront, PORTAL_FRONT, COLOR.metal, MAT.metal)
		shaftPart(jamb)
	end
	local head = box(m, cf, "PortalHead", DOOR.x1 - j, DOOR.x2 + j, y + DOOR.height, y + DOOR.height + 0.5, jambFront, PORTAL_FRONT, COLOR.metal, MAT.metal)
	shaftPart(head)
	local g = surface(head, "LevelNumber", Vector2.new(680, 50), 0.4, 60)
	label(g, "Label", Plan.levelLabel(tier, level), 0.4, 0.12, 0.2, 0.76, COLOR.brass, Enum.Font.BuilderSansBold, Enum.TextXAlignment.Center)
end

-- ---------------------------------------------------------------------------------------------
-- Landing door sets (Lift folder)

local function buildLanding(parent: Instance, cf: CFrame, tier: number, level: number, accent: Color3): Model
	local y = Plan.levelY(level)
	local m = Instance.new("Model")
	m.Name = "Landing_" .. level
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	m:SetAttribute("LiftStop", level)
	m:SetAttribute("LevelLabel", Plan.levelLabel(tier, level))
	m.Parent = parent
	for _, s in { -1, 1 } do
		local closed = CFrame.new(s * LEAF_W / 2, y + LEAF_LIFT + DOOR.height / 2, LEAF_Z)
		local open = CFrame.new(s * (LEAF_W / 2 + LEAF_SLIDE), y + LEAF_LIFT + DOOR.height / 2, LEAF_Z)
		local leaf = block(m, cf, if s < 0 then "DoorL" else "DoorR", Vector3.new(LEAF_W, DOOR.height, LEAF_T), closed, COLOR.metalSoft, MAT.metal)
		leaf:SetAttribute("ClosedCFrame", cf * closed)
		leaf:SetAttribute("OpenCFrame", cf * open)
		shaftPart(leaf)
	end
	-- threshold plate through the wall opening, stopping 0.1 short of the cabin
	local sill = box(m, cf, "Sill", DOOR.x1, DOOR.x2, y - SILL_DEPTH, y + LEAF_LIFT, 53.4, CB.z1 - 0.1, COLOR.metalSoft, MAT.metal)
	shaftPart(sill)
	-- call button on the right-hand portal cladding
	local button = block(m, cf, "CallButton", Vector3.new(0.62, 1.1, 0.1), CFrame.new(4.6, y + 3.6, 53.05), COLOR.metal, MAT.metal)
	button.CanCollide = false
	button.CanTouch = false
	local ring = block(m, cf, "CallRing", Vector3.new(0.06, 0.42, 0.42), CFrame.new(4.6, y + 3.75, 52.97) * CFrame.Angles(0, math.pi / 2, 0), COLOR.lightWarm, MAT.neon)
	ring.Shape = Enum.PartType.Cylinder
	detail(ring)
	local q = prompt(button, "Call lift", 7, "liftCall", level)
	q.Name = "CallPrompt"
	-- floor indicator above the portal, facing the lobby (-Z)
	local indicator = block(m, cf, "Indicator", Vector3.new(4.8, 1.2, 0.55), CFrame.new(0, y + 11.2, FZ1 - 0.275), COLOR.screen, MAT.smooth)
	detail(indicator)
	display(indicator, Vector2.new(480, 120), Plan.levelLabel(tier, level), Plan.floorTitle(tier, level), accent, 80)
	-- queue marker for NPCs and a brass floor plate in front of the doors
	local wait = block(m, cf, "WaitMarker", Vector3.new(1, 1, 1), CFrame.new(Plan.liftWaitPoint(level, 1)), COLOR.white, MAT.smooth)
	ghost(wait)
	wait:SetAttribute("LiftStop", level)
	local plate = box(m, cf, "FloorMarker", -2.4, 2.4, y, y + 0.06, 51.9, 52.5, COLOR.brass, MAT.metal)
	detail(plate)
	return m
end

-- ---------------------------------------------------------------------------------------------
-- Lift cabin (built at level 0; LiftService unanchors and welds it to CabinFloor)

local function buildCabin(parent: Instance, cf: CFrame, tier: number, accent: Color3, company: string): Model
	local cabin = Instance.new("Model")
	cabin.Name = "LiftCabin"
	cabin.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	cabin:SetAttribute("CurrentLevel", 0)
	cabin.Parent = parent
	local y = Plan.levelY(0)
	local x1, x2, z1, z2 = CB.x1, CB.x2, CB.z1, CB.z2
	local metal, oak = COLOR.metal, COLOR.oak
	local function add(name: string, ax: number, bx: number, ay: number, by: number, az: number, bz: number, color: Color3, material: Enum.Material, decorative: boolean?): Part
		local p = box(cabin, cf, name, ax, bx, y + ay, y + by, az, bz, color, material)
		if decorative then
			detail(p)
		end
		return p
	end
	local floor = add("CabinFloor", x1, x2, -0.5, 0, z1, z2, COLOR.stoneDeep, MAT.marble)
	cabin.PrimaryPart = floor
	add("CabinFloorInlay", -4.6, 4.6, 0, 0.05, 56.6, 65.2, COLOR.oakLight, MAT.wood, true)
	add("CabinThreshold", DOOR.x1, DOOR.x2, 0, 0.05, z1, 55.4, COLOR.metalSoft, MAT.metal, true)
	-- shell: front pieces beside the door (the leaves park in front of them), sides, back, roof
	add("CabinFront", x1, DOOR.x1, 0, CAB_DOOR_H, CAB_FRONT1, CAB_FRONT2, oak, MAT.wood)
	add("CabinFront", DOOR.x2, x2, 0, CAB_DOOR_H, CAB_FRONT1, CAB_FRONT2, oak, MAT.wood)
	add("CabinTransom", x1, x2, CAB_DOOR_H, CAB_CEIL, CAB_LEAF_Z - LEAF_T / 2, CAB_FRONT2, metal, MAT.metal)
	add("CabinSide", x1, -CAB_SIDE, 0, CAB_CEIL, CAB_FRONT2, CAB_BACK, metal, MAT.metal)
	add("CabinSide", CAB_SIDE, x2, 0, CAB_CEIL, CAB_FRONT2, CAB_BACK, metal, MAT.metal)
	add("CabinBack", x1, x2, 0, CAB_CEIL, CAB_BACK, z2, metal, MAT.metal)
	add("CabinCeiling", x1, x2, CAB_CEIL, CAB_CEIL + 0.4, z1, z2, COLOR.white, MAT.smooth)
	-- interior: oak panelling with dark metal joints, satin steel panel on the back wall
	local lin = CAB_SIDE - 0.08 -- 5.78: oak face
	add("CabinPanelling", x1 + 0.14, -lin, 0, CAB_CEIL, CAB_FRONT2, CAB_BACK - 0.07, oak, MAT.wood, true)
	add("CabinPanelling", lin, x2 - 0.14, 0, CAB_CEIL, CAB_FRONT2, CAB_BACK - 0.07, oak, MAT.wood, true)
	add("CabinPanelling", -lin, lin, 0, CAB_CEIL, CAB_BACK - 0.07, CAB_BACK, oak, MAT.wood, true)
	add("CabinSatinPanel", -3.6, 3.6, 3.9, 9.5, CAB_BACK - 0.12, CAB_BACK - 0.07, COLOR.glassDeep, MAT.metal, true)
	for _, s in { -1, 1 } do
		for _, z in { 59.1, 62.9 } do
			add("CabinJoint", math.min(s * lin, s * (lin - 0.05)), math.max(s * lin, s * (lin - 0.05)), 0.35, CAB_CEIL, z - 0.06, z + 0.06, metal, MAT.metal, true)
		end
		add("CabinSkirting", math.min(s * lin, s * (lin - 0.06)), math.max(s * lin, s * (lin - 0.06)), 0, 0.35, CAB_FRONT2, CAB_BACK - 0.13, metal, MAT.metal, true)
	end
	add("CabinSkirting", -(lin - 0.06), lin - 0.06, 0, 0.35, CAB_BACK - 0.13, CAB_BACK - 0.07, metal, MAT.metal, true)
	-- handrails (outside the 11 x 11 clear floor: |x| >= 5.52, z <= 66.43)
	local railY1, railY2 = RAIL_H - 0.06, RAIL_H + 0.06
	add("CabinHandrail", -4.8, 4.8, railY1, railY2, 66.43, 66.53, oak, MAT.wood, true)
	for _, x in { -3.5, 3.5 } do
		add("CabinRailBracket", x - 0.05, x + 0.05, railY1 + 0.01, railY2 - 0.01, 66.53, CAB_BACK - 0.07, metal, MAT.metal, true)
	end
	for _, s in { -1, 1 } do
		add("CabinHandrail", math.min(s * 5.52, s * 5.62), math.max(s * 5.52, s * 5.62), railY1, railY2, 57, 65.5, oak, MAT.wood, true)
		for _, z in { 58, 64.5 } do
			add("CabinRailBracket", math.min(s * 5.62, s * lin), math.max(s * 5.62, s * lin), railY1 + 0.01, railY2 - 0.01, z - 0.05, z + 0.05, metal, MAT.metal, true)
		end
	end
	-- recessed light panel
	add("CabinLightTrim", -3.7, 3.7, CAB_CEIL - 0.06, CAB_CEIL, 57.2, 64.6, metal, MAT.metal, true)
	local light = add("CabinLight", -3.5, 3.5, CAB_CEIL - 0.07, CAB_CEIL, 57.4, 64.4, COLOR.lightWarm, MAT.neon, true)
	local lamp = Instance.new("SurfaceLight")
	lamp.Face = Enum.NormalId.Bottom
	lamp.Angle = 120
	lamp.Range = 12
	lamp.Brightness = 1.1
	lamp.Color = COLOR.lightWarm
	lamp.Shadows = false
	lamp.Parent = light
	-- door leaves on the cabin front
	for _, s in { -1, 1 } do
		local closed = CFrame.new(s * LEAF_W / 2, y + CAB_DOOR_H / 2, CAB_LEAF_Z)
		local open = CFrame.new(s * (LEAF_W / 2 + LEAF_SLIDE), y + CAB_DOOR_H / 2, CAB_LEAF_Z)
		local leaf = block(cabin, cf, if s < 0 then "CabinDoorL" else "CabinDoorR", Vector3.new(LEAF_W, CAB_DOOR_H, LEAF_T), closed, COLOR.metalSoft, MAT.metal)
		leaf:SetAttribute("ClosedOffset", floor.CFrame:ToObjectSpace(cf * closed))
		leaf:SetAttribute("OpenOffset", floor.CFrame:ToObjectSpace(cf * open))
	end
	-- floor strip display in the transom, facing the riders (+Z)
	local turn = CFrame.Angles(0, math.pi, 0)
	local screen = block(cabin, cf, "CabinDisplay", Vector3.new(3.2, 0.34, 0.06), CFrame.new(0, y + CAB_DOOR_H + 0.2, CAB_FRONT2 + 0.03) * turn, COLOR.screen, MAT.smooth)
	detail(screen)
	display(screen, Vector2.new(640, 68), Plan.levelLabel(tier, 0), Plan.levelName(tier, 0), accent, 40)
	-- button column beside the door (riders' right when facing the doors)
	local px1, px2, py1, py2 = 4.3, 5.5, 2.4, 7.2
	local panel = block(cabin, cf, "CabinPanel", Vector3.new(px2 - px1, py2 - py1, 0.08), CFrame.new((px1 + px2) / 2, y + (py1 + py2) / 2, CAB_FRONT2 + 0.04) * turn, metal, MAT.metal)
	panel.CanCollide = false
	panel.CanTouch = false
	local q = prompt(panel, "Choose floor", 6, "liftPanel", nil)
	q.Name = "PanelPrompt"
	local g = surface(panel, "Buttons", Vector2.new(240, 960), 0.2, 30)
	label(g, "Company", company, 0.06, 0.02, 0.88, 0.06, COLOR.brass, Enum.Font.BuilderSansBold, Enum.TextXAlignment.Center)
	label(g, "Title", "LIFT · " .. Plan.CABIN.capacity .. " persons", 0.06, 0.085, 0.88, 0.04, COLOR.lightNeutral, Enum.Font.BuilderSans, Enum.TextXAlignment.Center)
	local stops = Plan.liftStops(tier)
	local cells: { { text: string, level: number?, door: string? } } = { { text = "<>", door = "open" }, { text = "><", door = "close" } }
	for _, stop in stops do
		table.insert(cells, { text = stop.label, level = stop.level })
	end
	local rows = math.ceil(#cells / 2)
	local pitchY = math.min(0.5, (py2 - py1 - 1.1) / rows)
	for k, cell in cells do
		local row, col = (k - 1) // 2, (k - 1) % 2
		local cx = px1 + 0.3 + 0.6 * col - 0.1 -- button centre (world x grows to the riders' right)
		local cy = py1 + 0.3 + pitchY * (row + 0.5)
		local b = block(cabin, cf, "CabinButton", Vector3.new(0.24, 0.24, 0.05), CFrame.new(cx, y + cy, CAB_FRONT2 + 0.105) * turn, if cell.door then COLOR.metalSoft else COLOR.brass, MAT.metal)
		detail(b)
		if cell.level ~= nil then
			b:SetAttribute("LiftStop", cell.level)
		else
			b:SetAttribute("DoorButton", cell.door)
		end
		local u = (cx + 0.16 - px1) / (px2 - px1)
		local v = (py2 - (cy + 0.14)) / (py2 - py1)
		label(g, "Key", cell.text, u, v, 0.18, 0.28 / (py2 - py1), COLOR.white, Enum.Font.BuilderSansBold, Enum.TextXAlignment.Left)
	end
	return cabin
end

-- ---------------------------------------------------------------------------------------------
-- Switchback stair (Core folder)

-- One flight rising from (yA, zA) to (yB, zB) over x1..x2: an invisible smooth ramp whose top face
-- passes exactly through both end points, 16 stone treads with their nosings on the walking line,
-- a dark nosing per step, the plastered waist below and wall-mounted oak rails on both sides.
local function buildFlight(m: Model, cf: CFrame, x1: number, x2: number, yA: number, zA: number, yB: number, zB: number, onFloor: boolean, rails: { { number } }): Part
	local dir = if zB > zA then 1 else -1
	local rise = (yB - yA) / STEPS
	local going = math.abs(zB - zA) / STEPS
	local ramp = slopeTop(m, cf, "StairRamp", x1, x2, yA, zA, yB, zB, RAMP_T, COLOR.stone, MAT.stone)
	ramp.Transparency = 1
	ramp.CanTouch = false
	ramp.CastShadow = false
	ramp:SetAttribute("StairRamp", true)
	local function nosing(z: number, top: number)
		local n = box(m, cf, "StairNosing", x1, x2, top - 0.1, top + 0.015, math.min(z - dir * 0.02, z + dir * 0.16), math.max(z - dir * 0.02, z + dir * 0.16), COLOR.metal, MAT.metal)
		detail(n)
	end
	for i = 0, STEPS - 1 do
		local top = yA + rise * i
		local za, zb = zA + dir * going * i, zA + dir * going * (i + 1)
		-- tread 0 is flush with the landing it leaves; on a solid floor (B1) the floor already shows
		if i > 0 or not onFloor then
			local t = box(m, cf, "StairTread", x1, x2, top - rise - 0.45, top, math.min(za, zb), math.max(za, zb), COLOR.stone, MAT.stone)
			detail(t)
		end
		if i > 0 then
			nosing(za, top)
		end
	end
	nosing(zB, yB) -- the arrival landing's edge is the last nosing
	local waist = WAIST * going / math.sqrt(going * going + rise * rise)
	slopeTop(m, cf, "StairSoffit", x1, x2, yA - rise, zA, yB - rise, zB, waist, COLOR.interior, MAT.plaster)
	-- rails follow the walking line at RAIL_H
	local function lineY(z: number): number
		return yA + (z - zA) * (yB - yA) / (zB - zA)
	end
	local zs, ze = zA + dir * 0.6, zB - dir * 0.6
	for _, r in rails do
		local rail = slopeBeam(m, cf, "StairHandrail", r[1], r[2], lineY(zs) + RAIL_H, zs, lineY(ze) + RAIL_H, ze, 0.2, COLOR.oak, MAT.wood)
		detail(rail)
	end
	return ramp
end

local function buildStairLevel(parent: Instance, cf: CFrame, level: number): Model
	local m = model(parent, "Stair_" .. level)
	local y0, y1 = Plan.levelY(level), Plan.levelY(level + 1)
	local mid = y0 + (y1 - y0) / 2
	local A, B, dv = ST.flightA, ST.flightB, ST.divider
	local rw = 0.25 -- rail projection from its wall
	buildFlight(m, cf, A.x1, A.x2, y0, A.z1, mid, A.z2, level < 0, { { A.x1, A.x1 + rw }, { dv.x1 - rw, dv.x1 } })
	buildFlight(m, cf, B.x1, B.x2, mid, B.z2, y1, B.z1, false, { { dv.x2, dv.x2 + rw }, { B.x2 - rw, B.x2 } })
	box(m, cf, "StairLanding", ST.inner.x1, ST.inner.x2, mid - 1, mid, ST.midLanding.z1, ST.midLanding.z2, COLOR.stone, MAT.stone)
	-- wall light on the divider end over the mid landing
	local fixture = box(m, cf, "StairLight", dv.x1 + 0.05, dv.x2 - 0.05, mid + 6.2, mid + 7.6, ST.midLanding.z1, ST.midLanding.z1 + 0.12, COLOR.lightWarm, MAT.neon)
	detail(fixture)
	local lamp = Instance.new("PointLight")
	lamp.Range = 20
	lamp.Brightness = 0.9
	lamp.Color = COLOR.lightWarm
	lamp.Shadows = false
	lamp.Parent = fixture
	return m
end

-- Shared stair pieces: the full-height divider, the lining that makes the shaft side flush with the
-- stair room walls, level signs facing the stair door, and the guard over the top flight.
local function buildStairCore(parent: Instance, cf: CFrame, tier: number, accent: Color3)
	local m = model(parent, "StairCore")
	local roof = Plan.roofLevel(tier)
	local base, top = Plan.levelY(-1), Plan.levelY(roof) + HEAD_HOUSE
	local dv = ST.divider
	box(m, cf, "StairDivider", dv.x1, dv.x2, base, top, ST.flightA.z1, ST.flightA.z2, COLOR.interior, MAT.plaster)
	box(m, cf, "StairLining", ST.inner.x2, -SXO, base, top, ST.inner.z1, SH.z2, COLOR.interior, MAT.plaster)
	for level = -1, roof do
		local y = Plan.levelY(level)
		local z = ST.flightA.z1
		local sign = box(m, cf, "StairSign_" .. level, dv.x1 - 1, dv.x2 + 1, y + 7, y + 10.2, z - 0.12, z, COLOR.metal, MAT.metal)
		detail(sign)
		local g = surface(sign, "Sign", Vector2.new(260, 320), 0.3, 70)
		label(g, "Level", Plan.levelLabel(tier, level), 0.08, 0.04, 0.84, 0.56, COLOR.white, Enum.Font.BuilderSansBold, Enum.TextXAlignment.Center)
		local bar = Instance.new("Frame")
		bar.Name = "Accent"
		bar.BackgroundColor3 = accent
		bar.BorderSizePixel = 0
		bar.Position = UDim2.fromScale(0.3, 0.62)
		bar.Size = UDim2.fromScale(0.4, 0.015)
		bar.Parent = g
		label(g, "Title", Plan.levelName(tier, level), 0.08, 0.66, 0.84, 0.28, COLOR.lightNeutral, Enum.Font.BuilderSansMedium, Enum.TextXAlignment.Center)
	end
	-- roof: the flight below ends here, so the void over flight A gets a glass guard on the slab edge
	local roofY = Plan.levelY(roof)
	local z = ST.flightA.z1
	local glass = box(m, cf, "StairGuardGlass", ST.flightA.x1, ST.flightA.x2, roofY, roofY + 3.5, z - 0.2, z - 0.08, COLOR.glass, MAT.glass)
	glass.Transparency = P.railTransparency
	box(m, cf, "StairGuardRail", ST.flightA.x1, ST.flightA.x2, roofY + 3.5, roofY + 3.7, z - 0.22, z - 0.06, COLOR.metal, MAT.metal)
end

-- ---------------------------------------------------------------------------------------------
-- Navigation nodes (lift queue point and stair door per level)

local function node(parent: Instance, cf: CFrame, name: string, x: number, y: number, z: number, kind: string, level: number): Part
	local p = block(parent, cf, name, Vector3.new(0.2, 0.2, 0.2), CFrame.new(x, y, z), COLOR.white, MAT.smooth)
	ghost(p)
	p:SetAttribute("NavigationNode", kind)
	p:SetAttribute("Floor", level)
	CollectionService:AddTag(p, "NavigationNode")
	return p
end

-- ---------------------------------------------------------------------------------------------

function CoreDesign.build(ctx: Context): Result
	local cf, tier = ctx.cf, ctx.tier
	local roof = Plan.roofLevel(tier)
	local coreFolder = folderFor(ctx, "Core")
	local liftFolder = folderFor(ctx, "Lift")
	local navFolder = folderFor(ctx, "Navigation")

	buildShaft(coreFolder, cf, tier)
	buildHeadHouse(coreFolder, cf, tier)
	local landings: { [number]: Model } = {}
	for _, stop in Plan.liftStops(tier) do
		buildPortal(coreFolder, cf, tier, stop.level)
		landings[stop.level] = buildLanding(liftFolder, cf, tier, stop.level, ctx.accent)
	end

	local guide = block(liftFolder, cf, "LiftGuide", Vector3.new(1, 1, 1), CFrame.new(0, Plan.levelY(-1), CAB_Z), COLOR.white, MAT.smooth)
	ghost(guide)
	local cabin = buildCabin(liftFolder, cf, tier, ctx.accent, ctx.company)

	local stairs = model(coreFolder, "Stair")
	for level = -1, roof - 1 do
		buildStairLevel(stairs, cf, level)
	end
	buildStairCore(stairs, cf, tier, ctx.accent)

	for level = -1, roof do
		local y = Plan.levelY(level) + 2.8
		local w = Plan.liftWaitPoint(level, 1)
		local s = Plan.stairEntry(level)
		node(navFolder, cf, string.format("L%d_LiftWait", level), w.X, y, w.Z, "Elevator", level)
		node(navFolder, cf, string.format("L%d_Stair", level), s.X, y, s.Z, "Stairs", level)
	end

	return { landings = landings, cabin = cabin, guide = guide }
end

return CoreDesign
