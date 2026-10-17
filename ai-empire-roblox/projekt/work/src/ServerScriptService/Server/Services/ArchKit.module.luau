--!strict
-- ArchKit: the shared architecture + furniture library of the headquarters generators.
-- Full reference: docs/ArchKit.md. Conventions in short:
--   * Every builder takes (parent, cf, ...): cf = building (plot) CFrame; positions are
--     building-local CFrames `at` (world = cf * at). `at` sits at FLOOR level: pass the top of the
--     floor finish (level Y + Kit.FINISH when Kit.floor was used).
--   * Front = local -Z of `at`. A seat's sitter looks along -Z; cabinets, shelves, screens and boards
--     show their face towards -Z. Desks: the user sits on the -Z side and looks towards +Z.
--   * Anchor: free-standing furniture is centred on `at`; wall units and wall-mounted items take `at`
--     on the wall SURFACE (back at local z = 0, the body extends towards -Z).
--   * Only ArchPalette colours/materials. Everything Anchored. Small decorative parts never collide,
--     touch, query or cast shadows. All variation is deterministic (Kit.hash / Kit.rand / Kit.pick).
local Collection = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local A = require(ReplicatedStorage.Shared.Config.ArchPalette)
local Plan = require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Layout = require(ReplicatedStorage.Shared.BuildingLayout)

type DoorDef = Layout.DoorDef
type Wall = Layout.Wall
type Room = Plan.Room

local Kit = {}
Kit.A = A
Kit.C = A.color
Kit.M = A.material
Kit.FINISH = 0.1 -- thickness of Kit.floor finishes (finished floor = level Y + 0.1)
Kit.CEILING = 13 -- suspended ceiling underside above level Y
Kit.PANEL_PITCH = 4 -- batten grid of "panel" walls and flush doors (building-local multiples)
-- Budget switch: when true, doors drop hinges/kick plates/vision strips, glass walls drop mullions and
-- panel walls drop battens (flush doors keep theirs). Set once before building (default false).
Kit.LEAN = false
Kit.stats = { parts = 0, lights = 0 }

local C = A.color
local M = A.material
local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local PI = math.pi

export type Opts = {
	detail: boolean?, -- non-colliding, non-touch, non-query, no shadow
	transparency: number?,
	shape: Enum.PartType?,
	castShadow: boolean?,
	canCollide: boolean?,
	canTouch: boolean?,
	canQuery: boolean?,
	reflectance: number?,
}
export type Rect = { x1: number, x2: number, z1: number, z2: number }

local DETAIL: Opts = { detail = true }
local GLASS: Opts = { transparency = A.glassTransparency, castShadow = false }
local GLASS_DOOR: Opts = { transparency = A.glassTransparencyDoor, castShadow = false }

---------------------------------------------------------------------------------------------
-- Determinism
---------------------------------------------------------------------------------------------
local TWO32 = 4294967296
local function mul32(a: number, b: number): number
	local ah, al = a // 65536, a % 65536
	return ((ah * b) % 65536 * 65536 + al * b) % TWO32
end
local function norm(seed: number): number
	return math.floor(seed) % TWO32
end

-- FNV-1a 32 bit: same string -> same number on every server.
function Kit.hash(s: string): number
	local h = 2166136261
	for i = 1, #s do
		h = mul32(bit32.bxor(h, string.byte(s, i)), 16777619)
	end
	return h
end

-- Deterministic float in [0, 1) for (seed, i).
function Kit.rand(seed: number, i: number): number
	local h = bit32.bxor(norm(seed), mul32(norm(i) + 1, 0x9E3779B1))
	h = mul32(bit32.bxor(h, bit32.rshift(h, 15)), 0x85EBCA6B)
	h = mul32(bit32.bxor(h, bit32.rshift(h, 13)), 0xC2B2AE35)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / TWO32
end

function Kit.range(seed: number, i: number, lo: number, hi: number): number
	return lo + (hi - lo) * Kit.rand(seed, i)
end

function Kit.pick<T>(list: { T }, seed: number): T
	return list[norm(seed) % #list + 1]
end

---------------------------------------------------------------------------------------------
-- Placement helpers
---------------------------------------------------------------------------------------------
local FRONT_YAW: { [string]: number } = { S = 0, N = PI, E = -PI / 2, W = PI / 2 }

-- CFrame at (x, y, z) whose front (-Z) faces "N" (+Z), "S" (-Z), "E" (+X), "W" (-X) or a yaw in degrees.
function Kit.place(x: number, y: number, z: number, front: (string | number)?): CFrame
	local yaw = 0
	if type(front) == "string" then
		yaw = FRONT_YAW[front] or 0
	elseif type(front) == "number" then
		yaw = math.rad(front)
	end
	return CF(x, y, z) * ANG(0, yaw, 0)
end

-- CFrame at pos whose front (-Z) looks horizontally towards `toward` (both building-local).
function Kit.facing(pos: Vector3, toward: Vector3): CFrame
	local target = V3(toward.X, pos.Y, toward.Z)
	if (target - pos).Magnitude < 1e-3 then
		return CF(pos)
	end
	return CFrame.lookAt(pos, target)
end

function Kit.levelY(level: number): number
	return Plan.levelY(level)
end

function Kit.model(parent: Instance, name: string, atomic: boolean?): Model
	local m = Instance.new("Model")
	m.Name = name
	if atomic then
		m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end
	m.Parent = parent
	return m
end

function Kit.resetStats()
	Kit.stats.parts = 0
	Kit.stats.lights = 0
end

---------------------------------------------------------------------------------------------
-- Primitives
---------------------------------------------------------------------------------------------
local function setup(p: BasePart, parent: Instance, cf: CFrame, name: string, size: Vector3, at: CFrame, color: Color3, material: Enum.Material?, opts: Opts?)
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf * at
	p.Color = color
	p.Material = material or M.smooth
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts then
		if opts.detail then
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.CastShadow = false
		end
		if opts.canCollide ~= nil then
			p.CanCollide = opts.canCollide
		end
		if opts.canTouch ~= nil then
			p.CanTouch = opts.canTouch
		end
		if opts.canQuery ~= nil then
			p.CanQuery = opts.canQuery
		end
		if opts.castShadow ~= nil then
			p.CastShadow = opts.castShadow
		end
		if opts.transparency then
			p.Transparency = opts.transparency
		end
		if opts.reflectance then
			p.Reflectance = opts.reflectance
		end
	end
	Kit.stats.parts += 1
	p.Parent = parent
end

-- Box (or opts.shape) part at cf * at.
function Kit.part(parent: Instance, cf: CFrame, name: string, size: Vector3, at: CFrame, color: Color3, material: Enum.Material?, opts: Opts?): Part
	local p = Instance.new("Part")
	if opts and opts.shape then
		p.Shape = opts.shape
	end
	setup(p, parent, cf, name, size, at, color, material, opts)
	return p
end

local AXIS_ROT: { [string]: CFrame } = {
	x = CFrame.identity,
	y = ANG(0, 0, PI / 2),
	z = ANG(0, PI / 2, 0),
}
-- Cylinder whose length runs along the local axis ("x" | "y" | "z") of `at`.
function Kit.cylinder(parent: Instance, cf: CFrame, name: string, axis: string, length: number, diameter: number, at: CFrame, color: Color3, material: Enum.Material?, opts: Opts?): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	setup(p, parent, cf, name, V3(length, diameter, diameter), at * (AXIS_ROT[axis] or CFrame.identity), color, material, opts)
	return p
end

function Kit.ball(parent: Instance, cf: CFrame, name: string, diameter: number, at: CFrame, color: Color3, material: Enum.Material?, opts: Opts?): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	setup(p, parent, cf, name, V3(diameter, diameter, diameter), at, color, material, opts)
	return p
end

-- WedgePart: full bottom face, vertical face at +Z, slope falling towards -Z.
function Kit.wedge(parent: Instance, cf: CFrame, name: string, size: Vector3, at: CFrame, color: Color3, material: Enum.Material?, opts: Opts?): WedgePart
	local p = Instance.new("WedgePart")
	setup(p, parent, cf, name, size, at, color, material, opts)
	return p
end

-- Seat part (CanTouch stays true unless opts.canTouch == false).
function Kit.seat(parent: Instance, cf: CFrame, name: string, size: Vector3, at: CFrame, color: Color3, material: Enum.Material?, opts: Opts?): Seat
	local p = Instance.new("Seat")
	if opts and opts.shape then
		p.Shape = opts.shape
	end
	setup(p, parent, cf, name, size, at, color, material, opts)
	return p
end

export type TextOpts = {
	face: Enum.NormalId?,
	color: Color3?,
	font: Enum.Font?,
	light: number?, -- LightInfluence (default 0.25)
	maxDistance: number?, -- default 80
	align: string?, -- "left" | "center" | "right"
	valign: string?, -- "top" | "center" | "bottom"
	size: number?, -- TextSize in px (default: TextScaled)
	name: string?, -- TextLabel name (default "Label")
	guiName: string?, -- SurfaceGui name (default "SurfaceGui")
	pps: number?, -- PixelsPerStud (default 50)
	pad: number?, -- padding as a fraction of the face (default 0.06)
	wrap: boolean?,
}
-- SurfaceGui (PixelsPerStud sizing) with one TextLabel covering the face.
function Kit.text(part: BasePart, text: string, opts: TextOpts?): TextLabel
	local o: TextOpts = opts or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = o.guiName or "SurfaceGui"
	gui.Face = o.face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = o.pps or 50
	gui.LightInfluence = o.light or 0.25
	gui.MaxDistance = o.maxDistance or 80
	gui.Parent = part
	local pad = o.pad or 0.06
	local label = Instance.new("TextLabel")
	label.Name = o.name or "Label"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(pad, pad)
	label.Size = UDim2.fromScale(1 - 2 * pad, 1 - 2 * pad)
	label.Text = text
	label.TextColor3 = o.color or C.white
	label.Font = o.font or Enum.Font.BuilderSansBold
	label.TextWrapped = o.wrap ~= false
	if o.size then
		label.TextSize = o.size
	else
		label.TextScaled = true
	end
	label.TextXAlignment = if o.align == "left" then Enum.TextXAlignment.Left elseif o.align == "right" then Enum.TextXAlignment.Right else Enum.TextXAlignment.Center
	label.TextYAlignment = if o.valign == "top" then Enum.TextYAlignment.Top elseif o.valign == "bottom" then Enum.TextYAlignment.Bottom else Enum.TextYAlignment.Center
	label.Parent = gui
	return label
end

-- Light object on a part. `mood` = ArchPalette.mood key (colour/range/brightness) or a Color3.
function Kit.light(part: BasePart, kind: string, mood: (string | Color3)?, range: number?, brightness: number?, face: Enum.NormalId?): Light
	local color, r, b = C.lightNeutral, 16, 0.7
	if typeof(mood) == "Color3" then
		color = mood
	elseif type(mood) == "string" then
		local m = (A.mood :: any)[mood]
		if m then
			color, r, b = m.color, m.range, m.brightness
		end
	end
	local light: Light
	if kind == "surface" then
		local s = Instance.new("SurfaceLight")
		s.Face = face or Enum.NormalId.Bottom
		s.Angle = 110
		s.Range = range or r
		light = s
	elseif kind == "spot" then
		local s = Instance.new("SpotLight")
		s.Face = face or Enum.NormalId.Bottom
		s.Angle = 70
		s.Range = range or r
		light = s
	else
		local s = Instance.new("PointLight")
		s.Range = range or r
		light = s
	end
	light.Color = color
	light.Brightness = brightness or b
	light.Shadows = false
	light.Parent = part
	Kit.stats.lights += 1
	return light
end

---------------------------------------------------------------------------------------------
-- PropFx (design/PROPFX_CONTRACT.md): animated props are tagged at build time; the client
-- (PropFxController) animates them locally, the server only writes FxState / FxUntil.
---------------------------------------------------------------------------------------------
Kit.FX_TAG = "PropFx"
-- Tags `inst` as a PropFx root: `kinds` = comma-separated Fx kinds ("steam,blink"), `attrs` = static
-- contract attributes (FxAxis, FxRate, FxTravel, FxHinge, FxIdle, FxStation, FxGate, PropId, ...).
function Kit.fx(inst: Instance, kinds: string, attrs: { [string]: any }?): Instance
	inst:SetAttribute("Fx", kinds)
	if attrs then
		for k, v in attrs do
			inst:SetAttribute(k, v)
		end
	end
	Collection:AddTag(inst, Kit.FX_TAG)
	return inst
end

-- Atomic prop model whose pivot is `cf * at` (motion kinds of a Model root use the pivot frame).
function Kit.propModel(parent: Instance, cf: CFrame, name: string, at: CFrame): Model
	local m = Instance.new("Model")
	m.Name = name
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	m.WorldPivot = cf * at
	m.Parent = parent
	return m
end

-- Disabled steam emitter (the client toggles it while the prop works).
function Kit.steamEmitter(part: BasePart, name: string?, rate: number?, size: number?): ParticleEmitter
	local steam = Instance.new("ParticleEmitter")
	steam.Name = name or "Steam"
	steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	steam.Rate = rate or 4
	steam.Lifetime = NumberRange.new(0.8, 1.6)
	steam.Speed = NumberRange.new(0.8, 1.5)
	steam.SpreadAngle = Vector2.new(10, 10)
	steam.EmissionDirection = Enum.NormalId.Top
	local s = size or 0.4
	steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, s * 0.5), NumberSequenceKeypoint.new(1, s * 2) })
	steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	steam.Color = ColorSequence.new(C.white)
	steam.LightEmission = 0.1
	steam.Enabled = false
	steam.Parent = part
	return steam
end

-- Disabled flame on a burner part (Roblox clamps Fire.Size to 2..30).
function Kit.flame(part: BasePart, size: number?): Fire
	local fire = Instance.new("Fire")
	fire.Size = math.max(size or 2, 2)
	fire.Heat = 1
	fire.Color = Color3.fromRGB(70, 120, 255)
	fire.SecondaryColor = Color3.fromRGB(255, 160, 60)
	fire.Enabled = false
	fire.Parent = part
	return fire
end

---------------------------------------------------------------------------------------------
-- OfficeKit-compatible contracts: screen, prompt, action, station, activity, node
---------------------------------------------------------------------------------------------
-- Live screen part (front face = -Z of `at`); SurfaceGui "Desktop" with Header/Body/Footer + ProgressTrack/Fill.
function Kit.screen(parent: Instance, cf: CFrame, name: string, size: Vector3, at: CFrame, kind: string, accent: Color3): Part
	local screen = Kit.part(parent, cf, name, size, at, C.screen, M.smooth, { canCollide = false, canTouch = false, castShadow = false })
	screen:SetAttribute("LiveScreen", kind)
	Collection:AddTag(screen, "CompanyScreen")
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Desktop"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(800, 480)
	gui.LightInfluence = 0.15
	gui.MaxDistance = 120
	gui.Parent = screen
	local function text(n: string, x: number, y: number, w: number, h: number, ts: number, color: Color3): TextLabel
		local t = Instance.new("TextLabel")
		t.Name = n
		t.Position = UDim2.fromOffset(x, y)
		t.Size = UDim2.fromOffset(w, h)
		t.BackgroundTransparency = 1
		t.Text = ""
		t.TextSize = ts
		t.TextColor3 = color
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextYAlignment = Enum.TextYAlignment.Top
		t.Font = Enum.Font.BuilderSans
		t.TextWrapped = true
		t.Parent = gui
		return t
	end
	text("Header", 40, 30, 720, 50, 32, accent).Font = Enum.Font.BuilderSansBold
	text("Body", 40, 105, 720, 280, 27, C.white)
	text("Footer", 40, 416, 720, 40, 20, C.sageLight)
	local bar = Instance.new("Frame")
	bar.Name = "ProgressTrack"
	bar.Position = UDim2.fromOffset(40, 390)
	bar.Size = UDim2.fromOffset(720, 8)
	bar.BackgroundColor3 = C.metalSoft
	bar.BorderSizePixel = 0
	bar.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = accent
	fill.BorderSizePixel = 0
	fill.Parent = bar
	return screen
end

-- Owner prompt: opens the Computer app (App/Section) for the founder only.
function Kit.prompt(part: Instance, objectText: string, owner: number, app: string?, section: string?): ProximityPrompt
	local q = Instance.new("ProximityPrompt")
	q.ObjectText = objectText
	q.ActionText = "Open"
	q.MaxActivationDistance = 10
	q.RequiresLineOfSight = true
	q.HoldDuration = 0
	q:SetAttribute("OwnerUserId", owner)
	if app then
		q:SetAttribute("App", app)
	end
	if section then
		q:SetAttribute("Section", section)
	end
	q.Parent = part
	return q
end

export type ActionOpts = {
	ownerOnly: boolean?, -- attribute OwnerOnly=true (server checks the owner)
	actionText: string?, -- default "Use"
	maxDistance: number?, -- default 8
	holdDuration: number?, -- default 0
	requiresLineOfSight: boolean?, -- default false
	ownerUserId: number?, -- hidden prompt: OwnerUserId=<id> INSTEAD of Public=true
	attributes: { [string]: any }?,
	name: string?,
}
-- Public facility prompt (CampusAction / Value / Public=true).
function Kit.action(part: Instance, actionId: string, objectText: string, value: any?, opts: ActionOpts?): ProximityPrompt
	local o: ActionOpts = opts or {}
	local q = Instance.new("ProximityPrompt")
	if o.name then
		q.Name = o.name
	end
	q.ActionText = o.actionText or "Use"
	q.ObjectText = objectText
	q.MaxActivationDistance = o.maxDistance or 8
	q.HoldDuration = o.holdDuration or 0
	q.RequiresLineOfSight = o.requiresLineOfSight == true
	q:SetAttribute("CampusAction", actionId)
	if value ~= nil then
		q:SetAttribute("Value", value)
	end
	if o.ownerUserId then
		q:SetAttribute("OwnerUserId", o.ownerUserId)
	else
		q:SetAttribute("Public", true)
	end
	if o.ownerOnly then
		q:SetAttribute("OwnerOnly", true)
	end
	if o.attributes then
		for k, v in o.attributes do
			q:SetAttribute(k, v)
		end
	end
	q.Parent = part
	return q
end

---------------------------------------------------------------------------------------------
-- Seating
---------------------------------------------------------------------------------------------
export type ChairOpts = {
	lite: boolean?, -- no casters (5 parts)
	arms: boolean?, -- add two armrests
	color: Color3?,
	name: string?, -- Seat name (default "Seat")
	canTouch: boolean?, -- default true; workstation chairs pass false
	seatY: number?, -- seat cushion centre height (default 2.0)
}
-- Office swivel chair, footprint 2.4 x 2.4, sitter faces -Z. Returns the Seat.
function Kit.officeChair(parent: Instance, cf: CFrame, at: CFrame, seed: number?, opts: ChairOpts?): Seat
	local o: ChairOpts = opts or {}
	local s = seed or 0
	local fabric = o.color or Kit.pick({ C.fabricCharcoal, C.fabric, C.fabricBlue, C.fabricSand }, s)
	local sy = o.seatY or 2.0
	local seat = Kit.seat(parent, cf, o.name or "Seat", V3(2.3, 0.45, 2.2), at * CF(0, sy, -0.05), fabric, M.fabric, if o.canTouch == false then { canTouch = false } else nil)
	Kit.part(parent, cf, "ChairBack", V3(2.2, 2.3, 0.3), at * CF(0, sy + 1.33, 1.12) * ANG(math.rad(8), 0, 0), fabric, M.fabric)
	local stemLen = sy - 0.225 - 0.3
	Kit.cylinder(parent, cf, "ChairStem", "y", stemLen, 0.28, at * CF(0, 0.3 + stemLen / 2, 0), C.metal, M.metal, DETAIL)
	for _, yaw in { math.rad(36), math.rad(-36) } do
		Kit.part(parent, cf, "ChairBase", V3(2.3, 0.16, 0.28), at * CF(0, 0.3, 0) * ANG(0, yaw, 0), C.metal, M.metal, DETAIL)
		if not o.lite then
			for _, e in { -1.05, 1.05 } do
				Kit.ball(parent, cf, "Caster", 0.32, at * CF(e * math.cos(yaw), 0.16, -e * math.sin(yaw)), C.metalSoft, M.rubber, DETAIL)
			end
		end
	end
	if o.arms then
		for _, x in { -1.25, 1.25 } do
			Kit.part(parent, cf, "ArmRest", V3(0.22, 0.95, 1.2), at * CF(x, sy + 0.6, 0.15), C.metal, M.metal, DETAIL)
		end
	end
	return seat
end

-- Meeting/visitor chair on four legs, footprint 2.1 x 2.0, sitter faces -Z. Returns the Seat.
function Kit.meetingChair(parent: Instance, cf: CFrame, at: CFrame, seed: number?, opts: ChairOpts?): Seat
	local o: ChairOpts = opts or {}
	local s = seed or 0
	local cover = o.color or Kit.pick({ C.leather, C.fabric, C.fabricSand, C.fabricCharcoal, C.fabricBlue }, s)
	local wood = Kit.rand(s, 3) < 0.5
	local seat = Kit.seat(parent, cf, o.name or "Seat", V3(2.1, 0.35, 2.0), at * CF(0, 1.85, 0), cover, if cover == C.leather then M.leather else M.fabric, if o.canTouch == false then { canTouch = false } else nil)
	Kit.part(parent, cf, "ChairBack", V3(2.0, 1.8, 0.22), at * CF(0, 2.95, 0.92) * ANG(math.rad(6), 0, 0), cover, if cover == C.leather then M.leather else M.fabric)
	for _, x in { -0.85, 0.85 } do
		for _, z in { -0.8, 0.8 } do
			Kit.part(parent, cf, "ChairLeg", V3(0.16, 1.68, 0.16), at * CF(x, 0.84, z), if wood then C.oakDark else C.metal, if wood then M.wood else M.metal, DETAIL)
		end
	end
	return seat
end

-- Upholstered lounge armchair, footprint 3.0 x 2.9, sitter faces -Z. Returns the Seat.
function Kit.loungeChair(parent: Instance, cf: CFrame, at: CFrame, seed: number?, opts: ChairOpts?): Seat
	local o: ChairOpts = opts or {}
	local s = seed or 0
	local cover = o.color or Kit.pick({ C.fabricSand, C.sage, C.fabricBlue, C.leather, C.fabricCharcoal }, s)
	local mat = if cover == C.leather then M.leather else M.fabric
	Kit.part(parent, cf, "ChairBase", V3(3.0, 1.0, 2.9), at * CF(0, 0.7, 0), cover, mat)
	local seat = Kit.seat(parent, cf, o.name or "Seat", V3(2.2, 0.45, 2.3), at * CF(0, 1.42, -0.3), cover, mat, if o.canTouch == false then { canTouch = false } else nil)
	Kit.part(parent, cf, "ChairBack", V3(3.0, 1.9, 0.6), at * CF(0, 2.15, 1.15), cover, mat)
	for _, x in { -1.3, 1.3 } do
		Kit.part(parent, cf, "ArmRest", V3(0.4, 1.0, 2.3), at * CF(x, 1.7, -0.3), cover, mat)
	end
	local legColor = if Kit.rand(s, 5) < 0.5 then C.oakDark else C.metal
	for _, z in { -1.1, 1.1 } do
		Kit.part(parent, cf, "ChairLeg", V3(2.6, 0.2, 0.2), at * CF(0, 0.1, z), legColor, if legColor == C.metal then M.metal else M.wood, DETAIL)
	end
	return seat
end

-- Sofa of `length` (default 7), depth 3.0, sitter faces -Z. One Seat per ~3 studs; returns the Seats.
function Kit.sofa(parent: Instance, cf: CFrame, at: CFrame, length: number?, seed: number?, opts: ChairOpts?): { Seat }
	local o: ChairOpts = opts or {}
	local L = math.max(length or 7, 4)
	local s = seed or 0
	local cover = o.color or Kit.pick({ C.fabricSand, C.sage, C.fabricBlue, C.fabricCharcoal, C.leather }, s)
	local mat = if cover == C.leather then M.leather else M.fabric
	Kit.part(parent, cf, "SofaBase", V3(L, 1.0, 3.0), at * CF(0, 0.7, 0), cover, mat)
	Kit.part(parent, cf, "SofaBack", V3(L, 1.9, 0.65), at * CF(0, 2.15, 1.175), cover, mat)
	for _, x in { -1, 1 } do
		Kit.part(parent, cf, "SofaArm", V3(0.5, 1.0, 2.35), at * CF(x * (L / 2 - 0.25), 1.7, -0.325), cover, mat)
	end
	local inner = L - 1.0
	local n = math.max(1, math.floor(inner / 3 + 0.5))
	local w = inner / n
	local seats: { Seat } = {}
	for i = 1, n do
		local x = -inner / 2 + (i - 0.5) * w
		table.insert(seats, Kit.seat(parent, cf, o.name or "Seat", V3(w - 0.06, 0.45, 2.35), at * CF(x, 1.425, -0.325), cover, mat, if o.canTouch == false then { canTouch = false } else nil))
	end
	local legColor = if Kit.rand(s, 7) < 0.5 then C.oakDark else C.metal
	for _, z in { -1.2, 1.2 } do
		Kit.part(parent, cf, "SofaLeg", V3(L - 0.6, 0.2, 0.2), at * CF(0, 0.1, z), legColor, if legColor == C.metal then M.metal else M.wood, DETAIL)
	end
	return seats
end

-- Round stool; seat top at `height` (default 3.0 = bar stool, 2.2 = low). Sitter faces -Z.
function Kit.stool(parent: Instance, cf: CFrame, at: CFrame, seed: number?, height: number?, opts: ChairOpts?): Seat
	local o: ChairOpts = opts or {}
	local s = seed or 0
	local h = height or 3.0
	local top = o.color or Kit.pick({ C.oak, C.leather, C.fabricCharcoal, C.oakLight }, s)
	local sopts: Opts = { shape = Enum.PartType.Cylinder }
	if o.canTouch == false then
		sopts.canTouch = false
	end
	local seat = Kit.seat(parent, cf, o.name or "Seat", V3(0.3, 1.5, 1.5), at * CF(0, h - 0.15, 0) * ANG(0, 0, PI / 2), top, if top == C.leather then M.leather else M.wood, sopts)
	Kit.cylinder(parent, cf, "StoolPost", "y", h - 0.4, 0.22, at * CF(0, 0.1 + (h - 0.4) / 2, 0), C.metal, M.metal, DETAIL)
	Kit.cylinder(parent, cf, "StoolBase", "y", 0.1, 1.3, at * CF(0, 0.05, 0), C.metal, M.metal)
	return seat
end

-- Bench of `length` (default 6), depth 1.6, seat top 1.75. One Seat per ~3 studs; returns the Seats.
function Kit.bench(parent: Instance, cf: CFrame, at: CFrame, length: number?, seed: number?, opts: ChairOpts?): { Seat }
	local o: ChairOpts = opts or {}
	local L = math.max(length or 6, 2)
	local s = seed or 0
	local top = o.color or Kit.pick({ C.oak, C.oakLight, C.oakDark }, s)
	local n = math.max(1, math.floor(L / 3))
	local w = L / n
	local seats: { Seat } = {}
	for i = 1, n do
		table.insert(seats, Kit.seat(parent, cf, o.name or "Seat", V3(w - 0.05, 0.3, 1.6), at * CF(-L / 2 + (i - 0.5) * w, 1.6, 0), top, M.wood, if o.canTouch == false then { canTouch = false } else nil))
	end
	for _, x in { -1, 1 } do
		Kit.part(parent, cf, "BenchLeg", V3(0.3, 1.45, 1.4), at * CF(x * (L / 2 - 0.5), 0.725, 0), C.metal, M.metal)
	end
	return seats
end

---------------------------------------------------------------------------------------------
-- Desks and tables
---------------------------------------------------------------------------------------------
-- Desk variants: user side at -Z. Returns (top part, top surface height above `at`).
local DESK_TOP: { [string]: number } = { bench = 3.15, ldesk = 3.15, standing = 4.15, dual = 3.15, trading = 3.15, lab = 3.2 }
Kit.DESK_VARIANTS = { "bench", "ldesk", "standing", "dual", "trading", "lab" }

local function woodOrPaint(color: Color3): Enum.Material
	return if color == C.white or color == C.plasterShade then M.smooth else M.wood
end

function Kit.desk(parent: Instance, cf: CFrame, at: CFrame, variant: string?, seed: number?, tint: Color3?): (Part, number)
	local v = variant or "bench"
	local s = seed or 0
	local top: Part
	if v == "ldesk" then
		local c = Kit.pick({ C.oak, C.oakLight, C.white }, s)
		top = Kit.part(parent, cf, "DeskTop", V3(7, 0.3, 3.4), at * CF(0, 3.0, 0), c, woodOrPaint(c))
		Kit.part(parent, cf, "DeskReturn", V3(1.6, 0.3, 2.8), at * CF(2.7, 3.0, -3.1), c, woodOrPaint(c))
		for _, x in { -3.2, 3.2 } do
			Kit.part(parent, cf, "DeskLeg", V3(0.25, 2.85, 3.0), at * CF(x, 1.425, 0), C.metal, M.metal)
		end
		Kit.part(parent, cf, "DeskPedestal", V3(1.5, 2.85, 2.6), at * CF(2.7, 1.425, -3.1), tint or C.plasterShade, M.smooth)
	elseif v == "standing" then
		local c = Kit.pick({ C.oakLight, C.white, C.oak }, s)
		top = Kit.part(parent, cf, "DeskTop", V3(6, 0.25, 3.0), at * CF(0, 4.025, 0), c, woodOrPaint(c))
		for _, x in { -2.4, 2.4 } do
			Kit.part(parent, cf, "DeskColumn", V3(0.4, 3.7, 0.5), at * CF(x, 2.05, 0), C.metal, M.metal)
			Kit.part(parent, cf, "DeskFoot", V3(0.45, 0.2, 2.8), at * CF(x, 0.1, 0), C.metal, M.metal)
		end
	elseif v == "dual" then
		local c = Kit.pick({ C.oakDark, C.oak, C.metalSoft }, s)
		top = Kit.part(parent, cf, "DeskTop", V3(8, 0.3, 3.6), at * CF(0, 3.0, 0), c, if c == C.metalSoft then M.smooth else M.wood)
		for _, x in { -3.7, 3.7 } do
			Kit.part(parent, cf, "DeskLeg", V3(0.25, 2.85, 3.2), at * CF(x, 1.425, 0), C.metal, M.metal)
		end
		Kit.part(parent, cf, "ModestyPanel", V3(7.15, 1.2, 0.1), at * CF(0, 2.25, 1.55), tint or C.metalSoft, M.smooth, DETAIL)
		Kit.part(parent, cf, "PCTower", V3(1.0, 2.1, 2.2), at * CF(2.7, 1.05, 0.3), C.metal, M.metal)
	elseif v == "trading" then
		local c = Kit.pick({ C.oakDark, C.metalSoft }, s)
		local mat = if c == C.metalSoft then M.smooth else M.wood
		top = Kit.part(parent, cf, "DeskTop", V3(5, 0.3, 3.2), at * CF(0, 3.0, 0), c, mat)
		Kit.part(parent, cf, "DeskFascia", V3(5, 2.85, 0.15), at * CF(0, 1.425, 1.5), tint or C.metal, M.metal)
		local phi = 0.42
		for _, sgn in { -1, 1 } do
			local wing = at * CF(sgn * (2.5 + 1.8 * math.cos(phi)), 0, -1.8 * math.sin(phi)) * ANG(0, sgn * phi, 0)
			Kit.part(parent, cf, "DeskWing", V3(3.6, 0.3, 3.2), wing * CF(0, 2.99, 0), c, mat)
			Kit.part(parent, cf, "DeskFascia", V3(3.6, 2.85, 0.15), wing * CF(0, 1.415, 1.5), tint or C.metal, M.metal)
		end
	elseif v == "lab" then
		for _, x in { -2.4, 2.4 } do
			Kit.part(parent, cf, "LabCabinet", V3(2.0, 2.95, 3.0), at * CF(x, 1.475, 0.1), C.white, M.smooth)
		end
		top = Kit.part(parent, cf, "DeskTop", V3(7, 0.25, 3.4), at * CF(0, 3.075, 0), C.metalSoft, M.slate)
		for _, x in { -3.2, 3.2 } do
			Kit.part(parent, cf, "ShelfPost", V3(0.15, 3.0, 0.15), at * CF(x, 4.7, 1.6), C.metal, M.metal, DETAIL)
		end
		Kit.part(parent, cf, "ReagentShelf", V3(6.6, 0.12, 0.7), at * CF(0, 5.9, 1.35), C.white, M.smooth)
	else
		v = "bench"
		local c = Kit.pick({ C.oakLight, C.white, C.oak }, s)
		top = Kit.part(parent, cf, "DeskTop", V3(7, 0.3, 3.4), at * CF(0, 3.0, 0), c, woodOrPaint(c))
		for _, x in { -3.2, 3.2 } do
			Kit.part(parent, cf, "DeskLeg", V3(0.25, 2.85, 3.0), at * CF(x, 1.425, 0), C.metal, M.metal)
		end
		Kit.part(parent, cf, "ModestyPanel", V3(6.15, 1.2, 0.1), at * CF(0, 2.25, 1.45), C.metalSoft, M.smooth, DETAIL)
		Kit.part(parent, cf, "PrivacyScreen", V3(7, 1.2, 0.15), at * CF(0, 3.75, 1.62), tint or C.fabric, M.fabric)
	end
	return top, DESK_TOP[v] or 3.15
end

-- Meeting table: shape "rect" | "round" | "boat"; top surface 3.15. Returns the top.
function Kit.meetingTable(parent: Instance, cf: CFrame, at: CFrame, shape: string?, length: number?, width: number?, seed: number?): Part
	local s = seed or 0
	local L = length or 10
	local W = width or 4.5
	local c = Kit.pick({ C.oak, C.oakLight, C.white, C.oakDark }, s)
	local mat = woodOrPaint(c)
	if shape == "round" then
		local top = Kit.cylinder(parent, cf, "TableTop", "y", 0.25, L, at * CF(0, 3.025, 0), c, mat)
		Kit.cylinder(parent, cf, "TableColumn", "y", 2.7, 0.8, at * CF(0, 1.55, 0), C.metal, M.metal)
		Kit.cylinder(parent, cf, "TableFoot", "y", 0.2, math.max(1.6, L * 0.45), at * CF(0, 0.1, 0), C.metal, M.metal)
		return top
	end
	local core = if shape == "boat" then math.max(L - W, 1) else L
	local top = Kit.part(parent, cf, "TableTop", V3(core, 0.25, W), at * CF(0, 3.025, 0), c, mat)
	if shape == "boat" then
		for _, x in { -1, 1 } do
			Kit.cylinder(parent, cf, "TableEnd", "y", 0.25, W, at * CF(x * core / 2, 3.015, 0), c, mat)
		end
	end
	local pedestals: { number } = if L > 16 then { -1, 0, 1 } else { -1, 1 }
	for _, k in pedestals do
		Kit.part(parent, cf, "TablePedestal", V3(0.4, 2.88, W * 0.6), at * CF(k * (L / 2 - 1.6), 1.44, 0), C.metal, M.metal)
	end
	Kit.part(parent, cf, "PowerHub", V3(1.2, 0.04, 0.6), at * CF(0, 3.17, 0), C.metal, M.metal, DETAIL)
	return top
end

-- Coffee table (round or rectangular by seed), top 1.4. Returns the top.
function Kit.coffeeTable(parent: Instance, cf: CFrame, at: CFrame, seed: number?, w: number?, d: number?): Part
	local s = seed or 0
	local W, D = w or 4, d or 2.4
	local c = Kit.pick({ C.oak, C.stone, C.oakDark, C.white }, s)
	local mat = if c == C.stone then M.marble elseif c == C.white then M.smooth else M.wood
	if Kit.rand(s, 11) < 0.4 then
		local top = Kit.cylinder(parent, cf, "TableTop", "y", 0.2, math.max(W, D), at * CF(0, 1.3, 0), c, mat)
		Kit.cylinder(parent, cf, "TableBase", "y", 1.2, 0.8, at * CF(0, 0.6, 0), C.metal, M.metal)
		return top
	end
	local top = Kit.part(parent, cf, "TableTop", V3(W, 0.2, D), at * CF(0, 1.3, 0), c, mat)
	for _, x in { -1, 1 } do
		Kit.part(parent, cf, "TableLeg", V3(0.15, 1.2, D - 0.3), at * CF(x * (W / 2 - 0.3), 0.6, 0), C.metal, M.metal)
	end
	return top
end

---------------------------------------------------------------------------------------------
-- Storage (wall units: `at` on the wall surface, body towards -Z)
---------------------------------------------------------------------------------------------
-- Low sideboard, depth 1.6, height 2.82.
function Kit.sideboard(parent: Instance, cf: CFrame, at: CFrame, length: number?, seed: number?): Part
	local s = seed or 0
	local L = length or 6
	local body = Kit.pick({ C.oak, C.oakDark, C.white, C.sage }, s)
	local b = Kit.part(parent, cf, "Sideboard", V3(L, 2.4, 1.6), at * CF(0, 1.5, -0.8), body, woodOrPaint(body))
	Kit.part(parent, cf, "Plinth", V3(L - 0.3, 0.3, 1.3), at * CF(0, 0.15, -0.75), C.metal, M.metal)
	Kit.part(parent, cf, "SideboardTop", V3(L + 0.1, 0.12, 1.7), at * CF(0, 2.76, -0.85), C.stone, M.marble)
	local doors = math.max(2, math.floor(L / 2))
	for i = 1, doors - 1 do
		Kit.part(parent, cf, "Groove", V3(0.04, 2.2, 0.02), at * CF(-L / 2 + i * L / doors, 1.5, -1.61), C.metal, M.smooth, DETAIL)
	end
	if Kit.rand(s, 2) < 0.6 then
		Kit.cylinder(parent, cf, "Vase", "y", 1.2, 0.6, at * CF(L * 0.25, 3.42, -0.8), Kit.pick({ C.terracotta, C.white, C.sageLight }, s), M.smooth, DETAIL)
	end
	if Kit.rand(s, 3) < 0.6 then
		Kit.part(parent, cf, "Books", V3(1.2, 0.35, 0.9), at * CF(-L * 0.25, 2.995, -0.8), Kit.pick({ C.oakDark, C.blue, C.fabricSand }, s + 1), M.smooth, DETAIL)
	end
	return b
end

-- Cabinet w x h, depth 1.6, two doors with handles.
function Kit.cabinet(parent: Instance, cf: CFrame, at: CFrame, w: number?, h: number?, seed: number?): Part
	local s = seed or 0
	local W, H = w or 3, h or 6.5
	local c = Kit.pick({ C.white, C.oakLight, C.plasterShade, C.oak }, s)
	local body = Kit.part(parent, cf, "Cabinet", V3(W, H - 0.25, 1.6), at * CF(0, 0.25 + (H - 0.25) / 2, -0.8), c, woodOrPaint(c))
	Kit.part(parent, cf, "Plinth", V3(W - 0.2, 0.25, 1.4), at * CF(0, 0.125, -0.75), C.metal, M.metal)
	local hy = math.min(H - 0.6, 3.6)
	if W >= 2 then
		Kit.part(parent, cf, "Groove", V3(0.04, H - 0.5, 0.02), at * CF(0, 0.25 + (H - 0.25) / 2, -1.61), C.metal, M.smooth, DETAIL)
		for _, x in { -0.25, 0.25 } do
			Kit.part(parent, cf, "Handle", V3(0.08, 0.8, 0.1), at * CF(x, hy, -1.65), C.metalSoft, M.metal, DETAIL)
		end
	else
		Kit.part(parent, cf, "Handle", V3(0.08, 0.8, 0.1), at * CF(W / 2 - 0.25, hy, -1.65), C.metalSoft, M.metal, DETAIL)
	end
	return body
end

export type LockerOpts = { propId: string?, prompt: string?, door: number? }
-- Bank of n lockers (1.5 wide each, 6.5 high, depth 1.6) in an Atomic "LockerBank" model whose pivot is
-- `at`. PropFx hinge: one door (opts.door, default by seed) swings open while the prop works (a player
-- prompt "prop" when opts.prompt is given, or an NPC job through opts.propId). Returns the door parts.
function Kit.lockers(parent: Instance, cf: CFrame, at: CFrame, n: number?, seed: number?, opts: LockerOpts?): { Part }
	local o: LockerOpts = opts or {}
	local s = seed or 0
	local count = math.max(1, n or 6)
	local W = count * 1.5
	local bank = Kit.propModel(parent, cf, "LockerBank", at)
	Kit.part(bank, cf, "LockerBody", V3(W, 6.2, 1.6), at * CF(0, 3.4, -0.8), C.plasterShade, M.metal)
	Kit.part(bank, cf, "Plinth", V3(W - 0.2, 0.3, 1.4), at * CF(0, 0.15, -0.75), C.metal, M.metal)
	local front = Kit.pick({ C.sage, C.blueSoft, C.oakLight, C.white }, s)
	local doors: { Part } = {}
	local open = math.clamp(o.door or (norm(s) % count + 1), 1, count)
	local openX = 0
	for i = 1, count do
		local x = -W / 2 + (i - 0.5) * 1.5
		local door = Kit.part(bank, cf, "LockerDoor", V3(1.42, 6.0, 0.06), at * CF(x, 3.4, -1.63), front, if front == C.oakLight then M.wood else M.metal, DETAIL)
		local handle = Kit.part(bank, cf, "LockerHandle", V3(0.1, 0.6, 0.08), at * CF(x + 0.5, 3.6, -1.7), C.metal, M.metal, DETAIL)
		table.insert(doors, door)
		if i == open then
			door:SetAttribute("FxMove", true)
			handle:SetAttribute("FxMove", true)
			openX = x
		end
	end
	-- hinge on the door's left edge (pivot space); a positive angle swings the free edge out (-Z)
	Kit.fx(bank, "hinge", { FxAxis = "y", FxTravel = 1.9, FxHinge = V3(openX - 0.71, 3.4, -1.63), FxSeconds = 4, PropId = o.propId })
	if o.prompt then
		Kit.action(doors[open], "prop", o.prompt, o.propId, { actionText = "Open", maxDistance = 6 })
	end
	return doors
end

local BOOK_COLORS = { C.leather, C.oakDark, C.sage, C.blue, C.terracotta, C.fabricSand, C.fabricCharcoal, C.white, C.brass, C.fabricBlue, C.sageLight }

-- Fill one shelf row [x1, x2] at floor height y (clear height rowH) with books in one or two
-- clusters (spines face -Z of `at`, backs near the wall at zFront); an optional lying stack sits in
-- the gap. Returns the number of parts made.
local function bookRow(parent: Instance, cf: CFrame, at: CFrame, x1: number, x2: number, y: number, rowH: number, zFront: number, seed: number, maxBooks: number): number
	local avail = x2 - x1
	local widths: { number } = {}
	local total = 0
	for i = 1, maxBooks do
		local w = Kit.range(seed, i, 0.3, 0.55)
		if total + w > avail * 0.8 then
			break
		end
		table.insert(widths, w)
		total += w + 0.02
	end
	local n = #widths
	local free = avail - total
	local split = if free > 1.6 and n >= 4 then math.floor(n / 2 + Kit.range(seed, 40, -1, 1) + 0.5) else n
	local made = 0
	local function book(x: number, w: number, i: number, lean: number)
		local h = math.min(rowH - 0.12, Kit.range(seed, i + 50, 0.85, 1.35))
		Kit.part(parent, cf, "Book", V3(w, h, Kit.range(seed, i + 30, 0.8, 0.98)), at * CF(x + w / 2, y + h / 2, zFront - 0.48) * ANG(0, 0, lean), Kit.pick(BOOK_COLORS, seed + i * 7), M.smooth, DETAIL)
		made += 1
	end
	local x = x1 + Kit.range(seed, 41, 0.05, math.min(0.6, free * 0.2))
	for i = 1, split do
		book(x, widths[i], i, 0)
		x += widths[i] + 0.02
	end
	local gapStart = x
	if split < n then
		local rest = 0
		for i = split + 1, n do
			rest += widths[i] + 0.02
		end
		x = x2 - Kit.range(seed, 42, 0.05, math.min(0.6, free * 0.2)) - rest
		local gapEnd = x
		if gapEnd - gapStart > 1.3 and Kit.rand(seed, 43) < 0.6 then
			local w = math.min(1.0, gapEnd - gapStart - 0.3)
			Kit.part(parent, cf, "Books", V3(w, 0.42, 0.85), at * CF((gapStart + gapEnd) / 2, y + 0.21, zFront - 0.5), Kit.pick(BOOK_COLORS, seed + 3), M.smooth, DETAIL)
			made += 1
		end
		for i = split + 1, n do
			book(x, widths[i], i, if i == split + 1 and Kit.rand(seed, 44) < 0.4 then 0.16 else 0)
			x += widths[i] + 0.02
		end
	end
	return made
end

export type ShelfOpts = { books: number?, color: Color3? }
-- Bookshelf w x h (default 6 x 8), depth 1.3, filled with books (opts.books = max books per row, default 8).
function Kit.bookshelf(parent: Instance, cf: CFrame, at: CFrame, w: number?, h: number?, seed: number?, opts: ShelfOpts?): Part
	local o: ShelfOpts = opts or {}
	local s = seed or 0
	local W, H = w or 6, h or 8
	local c = o.color or Kit.pick({ C.oakDark, C.oak, C.white, C.metal }, s)
	local mat = if c == C.white then M.smooth elseif c == C.metal then M.metal else M.wood
	local back = Kit.part(parent, cf, "ShelfBack", V3(W, H, 0.1), at * CF(0, H / 2, -0.05), c, mat)
	for _, x in { -1, 1 } do
		Kit.part(parent, cf, "ShelfSide", V3(0.15, H, 1.2), at * CF(x * (W / 2 - 0.075), H / 2, -0.7), c, mat)
	end
	Kit.part(parent, cf, "ShelfTop", V3(W - 0.3, 0.15, 1.2), at * CF(0, H - 0.075, -0.7), c, mat)
	Kit.part(parent, cf, "ShelfPlinth", V3(W - 0.3, 0.35, 1.2), at * CF(0, 0.175, -0.7), c, mat)
	local rows = math.max(1, math.floor((H - 0.5) / 1.6))
	local rowH = (H - 0.5 - (rows - 1) * 0.1) / rows
	for r = 1, rows do
		local y = 0.35 + (r - 1) * (rowH + 0.1)
		if r > 1 then
			Kit.part(parent, cf, "Shelf", V3(W - 0.3, 0.1, 1.15), at * CF(0, y - 0.05, -0.68), c, mat)
		end
		bookRow(parent, cf, at, -W / 2 + 0.15, W / 2 - 0.15, y, rowH, -0.1, s + r * 101, o.books or 8)
	end
	return back
end

-- Heavy warehouse pallet rack (free-standing, centred), length L x depth 3 x height 9, with boxes.
function Kit.shelfRack(parent: Instance, cf: CFrame, at: CFrame, length: number?, seed: number?): Part
	local s = seed or 0
	local L = length or 8
	local beam = Kit.pick({ C.blue, C.terracotta }, s)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			Kit.part(parent, cf, "RackPost", V3(0.25, 9, 0.25), at * CF(x * (L / 2 - 0.125), 4.5, z * 1.375), C.blue, M.metal)
		end
	end
	local first: Part? = nil
	for k, y in { 0.5, 3.5, 6.5 } do
		local deck = Kit.part(parent, cf, "RackDeck", V3(L - 0.5, 0.25, 3), at * CF(0, y, 0), beam, M.metal)
		first = first or deck
		local x = -L / 2 + 0.4
		local i = 0
		while x < L / 2 - 1.8 and i < 3 do
			local bw = Kit.range(s, k * 10 + i, 1.4, 2.4)
			local bh = Kit.range(s, k * 10 + i + 5, 1.0, 2.2)
			if x + bw > L / 2 - 0.4 then
				break
			end
			Kit.part(parent, cf, "Box", V3(bw, bh, Kit.range(s, k * 10 + i + 7, 1.6, 2.6)), at * CF(x + bw / 2, y + 0.125 + bh / 2, 0), Kit.pick({ C.fabricSand, C.oakLight, C.white }, s + k + i), M.smooth)
			x += bw + Kit.range(s, k * 10 + i + 9, 0.2, 0.8)
			i += 1
		end
	end
	return first :: Part
end

-- Light metal wire shelving (wall unit), w x 7 x depth 1.6 with bins.
function Kit.rackShelf(parent: Instance, cf: CFrame, at: CFrame, w: number?, seed: number?): Part
	local s = seed or 0
	local W = w or 4
	for _, x in { -1, 1 } do
		for _, z in { -0.1, -1.5 } do
			Kit.part(parent, cf, "ShelfPost", V3(0.12, 7, 0.12), at * CF(x * (W / 2 - 0.06), 3.5, z), C.metalSoft, M.metal)
		end
	end
	local first: Part? = nil
	for k, y in { 0.5, 2.6, 4.7, 6.8 } do
		local shelf = Kit.part(parent, cf, "WireShelf", V3(W - 0.24, 0.08, 1.5), at * CF(0, y, -0.8), C.metalSoft, M.metal)
		first = first or shelf
		if k < 4 and Kit.rand(s, k) < 0.75 then
			local bw = Kit.range(s, k + 10, 1.0, math.min(2.2, W - 0.6))
			Kit.part(parent, cf, "Bin", V3(bw, 1.0, 1.3), at * CF(Kit.range(s, k + 20, -0.3, 0.3), y + 0.54, -0.8), Kit.pick({ C.blue, C.fabricSand, C.metal, C.sage }, s + k), M.smooth, DETAIL)
		end
	end
	return first :: Part
end

---------------------------------------------------------------------------------------------
-- Walls items (wall-mounted: `at` on the wall surface at floor level, face towards -Z)
---------------------------------------------------------------------------------------------
export type WallItemOpts = { y: number?, name: string?, floor: boolean?, h: number? }

-- Whiteboard w x 4 (centre 5 above floor) with tray, optional marker text and sticky notes.
function Kit.whiteboard(parent: Instance, cf: CFrame, at: CFrame, w: number?, text: string?, seed: number?, opts: WallItemOpts?): Part
	local o: WallItemOpts = opts or {}
	local s = seed or 0
	local W = w or 6
	local y = o.y or 5
	Kit.part(parent, cf, "BoardFrame", V3(W + 0.2, 4.2, 0.1), at * CF(0, y, -0.05), C.metalSoft, M.metal)
	local board = Kit.part(parent, cf, o.name or "Whiteboard", V3(W, 4, 0.06), at * CF(0, y, -0.13), C.white, M.smooth)
	Kit.part(parent, cf, "MarkerTray", V3(W * 0.6, 0.1, 0.3), at * CF(0, y - 2.15, -0.25), C.metalSoft, M.metal, DETAIL)
	if text and text ~= "" then
		Kit.text(board, text, { color = C.blue, font = Enum.Font.GothamMedium, align = "left", valign = "top", light = 0.6, maxDistance = 60 })
	end
	local notes = math.floor(Kit.range(s, 1, 0, 4))
	for i = 1, notes do
		Kit.part(parent, cf, "StickyNote", V3(0.5, 0.5, 0.02), at * CF(W / 2 - 0.5 - (i - 1) * 0.65, y + 1.4 - Kit.range(s, i + 4, 0, 0.5), -0.17), Kit.pick({ C.fabricSand, C.sageLight, C.terracotta, C.blueSoft }, s + i), M.smooth, DETAIL)
	end
	return board
end

-- Pinboard (cork) w x h (default 4 x 3, centre 5) with pinned notes.
function Kit.pinboard(parent: Instance, cf: CFrame, at: CFrame, w: number?, h: number?, seed: number?, opts: WallItemOpts?): Part
	local o: WallItemOpts = opts or {}
	local s = seed or 0
	local W, H = w or 4, h or 3
	local y = o.y or 5
	Kit.part(parent, cf, "PinboardFrame", V3(W + 0.2, H + 0.2, 0.1), at * CF(0, y, -0.05), C.oakDark, M.wood)
	local board = Kit.part(parent, cf, o.name or "Pinboard", V3(W, H, 0.06), at * CF(0, y, -0.13), C.fabricSand, M.fabric)
	local n = 4 + math.floor(Kit.range(s, 1, 0, 3))
	for i = 1, n do
		local nx = Kit.range(s, i * 3, -W / 2 + 0.5, W / 2 - 0.5)
		local ny = Kit.range(s, i * 3 + 1, -H / 2 + 0.5, H / 2 - 0.5)
		Kit.part(parent, cf, "Note", V3(0.6, 0.8, 0.02), at * CF(nx, y + ny, -0.17 - i * 0.002) * ANG(0, 0, Kit.range(s, i * 3 + 2, -0.2, 0.2)), Kit.pick({ C.white, C.fabricSand, C.blueSoft, C.sageLight }, s + i), M.smooth, DETAIL)
	end
	return board
end

-- Wall TV / display (16:9, width w, centre 5.5) built on Kit.screen. opts.floor adds a floor stand.
function Kit.tvScreen(parent: Instance, cf: CFrame, at: CFrame, w: number?, kind: string?, accent: Color3?, opts: WallItemOpts?): Part
	local o: WallItemOpts = opts or {}
	local W = w or 6
	local H = o.h or W * 9 / 16
	local y = o.y or 5.5
	Kit.part(parent, cf, "ScreenBezel", V3(W + 0.2, H + 0.2, 0.12), at * CF(0, y, -0.06), C.metal, M.metal)
	local screen = Kit.screen(parent, cf, o.name or "WallScreen", V3(W, H, 0.1), at * CF(0, y, -0.17), kind or "lobby", accent or C.blue)
	if o.floor then
		for _, x in { -1, 1 } do
			Kit.part(parent, cf, "StandPost", V3(0.25, y + H / 2, 0.25), at * CF(x * (W / 2 - 0.6), (y + H / 2) / 2, 0.125), C.metal, M.metal)
		end
		Kit.part(parent, cf, "StandBase", V3(W, 0.15, 1.6), at * CF(0, 0.075, 0.125), C.metal, M.metal)
	end
	return screen
end

local ART_COLORS = { C.sage, C.terracotta, C.blue, C.brass, C.fabricSand, C.oakLight, C.metal, C.sageLight, C.blueSoft }

-- Framed abstract composition w x h (default 4 x 3, centre 5.5).
function Kit.artwork(parent: Instance, cf: CFrame, at: CFrame, w: number?, h: number?, seed: number?, opts: WallItemOpts?): Part
	local o: WallItemOpts = opts or {}
	local s = seed or 0
	local W, H = w or 4, h or 3
	local y = o.y or 5.5
	local frameColor = Kit.pick({ C.oakDark, C.metal, C.white, C.oak }, s)
	local frame = Kit.part(parent, cf, o.name or "ArtFrame", V3(W, H, 0.12), at * CF(0, y, -0.06), frameColor, if frameColor == C.metal then M.metal else M.wood)
	Kit.part(parent, cf, "Canvas", V3(W - 0.3, H - 0.3, 0.04), at * CF(0, y, -0.14), C.white, M.fabric, DETAIL)
	local n = 3 + math.floor(Kit.range(s, 1, 0, 2))
	local cw, ch = W - 0.6, H - 0.6
	for i = 1, n do
		local pw = Kit.range(s, i * 5, 0.2, 0.6) * cw
		local ph = Kit.range(s, i * 5 + 1, 0.2, 0.7) * ch
		local px = Kit.range(s, i * 5 + 2, -(cw - pw) / 2, (cw - pw) / 2)
		local py = Kit.range(s, i * 5 + 3, -(ch - ph) / 2, (ch - ph) / 2)
		local color = Kit.pick(ART_COLORS, s + i * 13)
		local z = -0.17 - i * 0.01
		if Kit.rand(s, i * 5 + 4) < 0.25 then
			local d = math.min(pw, ph)
			Kit.cylinder(parent, cf, "ArtDisc", "z", 0.02, d, at * CF(px, y + py, z), color, M.smooth, DETAIL)
		else
			Kit.part(parent, cf, "ArtPanel", V3(pw, ph, 0.02), at * CF(px, y + py, z), color, M.smooth, DETAIL)
		end
	end
	return frame
end

-- Felt acoustic panels covering w x h (default 6 x 3, centre 6.5). Returns the panels.
function Kit.acousticPanels(parent: Instance, cf: CFrame, at: CFrame, w: number?, h: number?, seed: number?, opts: WallItemOpts?): { Part }
	local o: WallItemOpts = opts or {}
	local s = seed or 0
	local W, H = w or 6, h or 3
	local y = o.y or 6.5
	local cols = math.clamp(math.floor(W / 2.2 + 0.5), 1, 6)
	local rows = math.clamp(math.floor(H / 2.2 + 0.5), 1, 3)
	local pw, ph = W / cols, H / rows
	local out: { Part } = {}
	for r = 1, rows do
		for c = 1, cols do
			local d = if (r + c) % 2 == 0 then 0.3 else 0.18
			local color = Kit.pick({ C.fabric, C.fabricSand, C.fabricCharcoal, C.fabricBlue, C.sageLight }, s + r * 7 + c)
			table.insert(out, Kit.part(parent, cf, "AcousticPanel", V3(pw - 0.15, ph - 0.15, d), at * CF(-W / 2 + (c - 0.5) * pw, y - H / 2 + (r - 0.5) * ph, -d / 2), color, M.fabric, DETAIL))
		end
	end
	return out
end

-- Room nameplate 3 x 1 (dark metal, white text, centre 5.6).
function Kit.signPlate(parent: Instance, cf: CFrame, at: CFrame, text: string, subtext: string?, opts: WallItemOpts?): Part
	local o: WallItemOpts = opts or {}
	local plate = Kit.part(parent, cf, o.name or "Nameplate", V3(3, 1, 0.1), at * CF(0, o.y or 5.6, -0.05), C.metal, M.metal, DETAIL)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.LightInfluence = 0.3
	gui.MaxDistance = 45
	gui.Parent = plate
	local main = Instance.new("TextLabel")
	main.Name = "Label"
	main.BackgroundTransparency = 1
	main.Position = UDim2.fromScale(0.06, if subtext then 0.1 else 0.18)
	main.Size = UDim2.fromScale(0.88, if subtext then 0.5 else 0.64)
	main.Text = text
	main.TextScaled = true
	main.TextWrapped = true
	main.TextColor3 = C.white
	main.Font = Enum.Font.BuilderSansBold
	main.TextXAlignment = Enum.TextXAlignment.Left
	main.Parent = gui
	if subtext then
		local sub = Instance.new("TextLabel")
		sub.Name = "Sub"
		sub.BackgroundTransparency = 1
		sub.Position = UDim2.fromScale(0.06, 0.62)
		sub.Size = UDim2.fromScale(0.88, 0.28)
		sub.Text = subtext
		sub.TextScaled = true
		sub.TextColor3 = C.stoneDeep
		sub.Font = Enum.Font.BuilderSans
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.Parent = gui
	end
	return plate
end

-- Wall directory: lines[1] = title, then one line per entry. Width 4 (opts.h overrides line height).
function Kit.wayfinding(parent: Instance, cf: CFrame, at: CFrame, lines: { string }, opts: WallItemOpts?): Part
	local o: WallItemOpts = opts or {}
	local n = math.max(#lines, 1)
	local lh = o.h or 0.5
	local H = 0.5 + n * lh
	local y = o.y or math.max(5.5, 1.2 + H / 2)
	local plate = Kit.part(parent, cf, o.name or "Directory", V3(4, H, 0.12), at * CF(0, y, -0.06), C.metal, M.metal)
	Kit.part(parent, cf, "DirectoryAccent", V3(4, 0.08, 0.02), at * CF(0, y + H / 2 - 0.25, -0.13), C.brass, M.metal, DETAIL)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 80
	gui.LightInfluence = 0.3
	gui.MaxDistance = 50
	gui.Parent = plate
	for i, line in lines do
		local t = Instance.new("TextLabel")
		t.Name = "Line" .. i
		t.BackgroundTransparency = 1
		t.Position = UDim2.new(0.05, 0, 0, math.floor((0.3 + (i - 1) * lh) * 80))
		t.Size = UDim2.new(0.9, 0, 0, math.floor(lh * 80 * 0.86))
		t.Text = line
		t.TextScaled = true
		t.TextColor3 = if i == 1 then C.brass else C.white
		t.Font = if i == 1 then Enum.Font.BuilderSansBold else Enum.Font.BuilderSans
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.Parent = gui
	end
	return plate
end

-- Pegboard tool wall (w x 3.5, centre 5) with hand tools.
function Kit.toolWall(parent: Instance, cf: CFrame, at: CFrame, w: number?, seed: number?, opts: WallItemOpts?): Part
	local o: WallItemOpts = opts or {}
	local s = seed or 0
	local W = w or 5
	local y = o.y or 5
	local board = Kit.part(parent, cf, o.name or "Pegboard", V3(W, 3.5, 0.1), at * CF(0, y, -0.05), C.oakLight, M.wood)
	local slots = math.max(2, math.floor(W / 1.1))
	for i = 1, slots do
		local x = -W / 2 + (i - 0.5) * W / slots
		local kind = math.floor(Kit.range(s, i, 0, 4))
		if kind == 0 then
			Kit.part(parent, cf, "ToolHandle", V3(0.15, 1.2, 0.12), at * CF(x, y - 0.2, -0.16), C.oakDark, M.wood, DETAIL)
			Kit.part(parent, cf, "ToolHead", V3(0.6, 0.22, 0.16), at * CF(x, y + 0.5, -0.18), C.metal, M.metal, DETAIL)
		elseif kind == 1 then
			Kit.part(parent, cf, "Wrench", V3(0.14, 1.1, 0.05), at * CF(x, y, -0.13) * ANG(0, 0, 0.15), C.metalSoft, M.metal, DETAIL)
		elseif kind == 2 then
			Kit.cylinder(parent, cf, "Screwdriver", "y", 1.0, 0.16, at * CF(x, y - 0.3, -0.18), C.terracotta, M.smooth, DETAIL)
		else
			Kit.part(parent, cf, "Pliers", V3(0.3, 0.9, 0.06), at * CF(x, y + 0.2, -0.13), C.metal, M.metal, DETAIL)
		end
	end
	return board
end

---------------------------------------------------------------------------------------------
-- Plants, rugs, lamps
---------------------------------------------------------------------------------------------
-- Potted plant: size "s" | "m" | "l" | "tree" | "xl" (atrium tree, ~16 high). Returns the pot.
function Kit.plant(parent: Instance, cf: CFrame, at: CFrame, size: string?, seed: number?): Part
	local s = seed or 0
	local sz = size or "m"
	local potColor = Kit.pick({ C.terracotta, C.stoneDeep, C.white, C.metal }, s)
	local potMat = if potColor == C.metal then M.metal elseif potColor == C.terracotta then M.smooth else M.concrete
	local leaf = if Kit.rand(s, 1) < 0.5 then C.foliage else C.foliageLight
	local yaw = Kit.range(s, 2, 0, 2 * PI)
	if sz == "s" then
		local pot = Kit.cylinder(parent, cf, "Planter", "y", 1.1, 1.2, at * CF(0, 0.55, 0), potColor, potMat)
		Kit.ball(parent, cf, "Foliage", 1.6, at * CF(0, 1.8, 0), leaf, M.grass, DETAIL)
		return pot
	elseif sz == "m" then
		local pot = Kit.cylinder(parent, cf, "Planter", "y", 1.6, 1.8, at * CF(0, 0.8, 0), potColor, potMat)
		Kit.cylinder(parent, cf, "Stem", "y", 1.6, 0.2, at * CF(0, 2.3, 0), C.oakDark, M.wood, DETAIL)
		Kit.ball(parent, cf, "Foliage", 2.2, at * CF(0, 3.4, 0), leaf, M.grass, DETAIL)
		Kit.ball(parent, cf, "Foliage", 1.6, at * ANG(0, yaw, 0) * CF(0.6, 2.7, 0), C.foliageLight, M.grass, DETAIL)
		return pot
	elseif sz == "l" then
		local pot = Kit.part(parent, cf, "Planter", V3(2.4, 2.0, 2.4), at * CF(0, 1.0, 0), potColor, potMat)
		Kit.cylinder(parent, cf, "Stem", "y", 3.0, 0.3, at * CF(0, 3.5, 0), C.oakDark, M.wood, DETAIL)
		Kit.ball(parent, cf, "Foliage", 2.6, at * CF(0, 5.0, 0), leaf, M.leafy, DETAIL)
		Kit.ball(parent, cf, "Foliage", 2.0, at * ANG(0, yaw, 0) * CF(0.9, 4.3, 0), C.foliageLight, M.leafy, DETAIL)
		Kit.ball(parent, cf, "Foliage", 1.8, at * ANG(0, yaw + 2.2, 0) * CF(0.7, 5.8, 0), C.foliage, M.leafy, DETAIL)
		return pot
	end
	local big = sz == "xl"
	local k = if big then 1.6 else 1
	local planter = Kit.part(parent, cf, "Planter", V3(3.6 * k, 2.2, 3.6 * k), at * CF(0, 1.1, 0), potColor, potMat)
	Kit.part(parent, cf, "Soil", V3(3.3 * k, 0.1, 3.3 * k), at * CF(0, 2.25, 0), C.soil, M.grass, DETAIL)
	local trunk = 5 * k
	Kit.cylinder(parent, cf, "Trunk", "y", trunk, 0.6 * k, at * CF(0, 2.2 + trunk / 2, 0), C.oakDark, M.wood)
	local top = 2.2 + trunk
	Kit.ball(parent, cf, "Canopy", 4.0 * k, at * CF(0, top + 0.6 * k, 0), leaf, M.leafy, DETAIL)
	Kit.ball(parent, cf, "Canopy", 3.2 * k, at * ANG(0, yaw, 0) * CF(1.4 * k, top, 0), C.foliageLight, M.leafy, DETAIL)
	Kit.ball(parent, cf, "Canopy", 3.0 * k, at * ANG(0, yaw + 2.4, 0) * CF(1.1 * k, top + 1.6 * k, 0), C.foliage, M.leafy, DETAIL)
	return planter
end

-- Built-in planter box w x d (height 1.6) with shrubs. Returns the box.
function Kit.planter(parent: Instance, cf: CFrame, at: CFrame, w: number?, d: number?, seed: number?): Part
	local s = seed or 0
	local W, D = w or 6, d or 2.4
	local c = Kit.pick({ C.stoneDeep, C.oakDark, C.concrete }, s)
	local box = Kit.part(parent, cf, "PlanterBox", V3(W, 1.6, D), at * CF(0, 0.8, 0), c, if c == C.oakDark then M.wood else M.stone)
	Kit.part(parent, cf, "Soil", V3(W - 0.4, 0.1, D - 0.4), at * CF(0, 1.65, 0), C.soil, M.grass, DETAIL)
	local n = math.clamp(math.floor(W * D / 7), 1, 6)
	for i = 1, n do
		local x = -W / 2 + (i - 0.5) * W / n
		local dia = Kit.range(s, i, 1.3, math.min(2.2, D + 0.2))
		Kit.ball(parent, cf, "Shrub", dia, at * CF(x, 1.6 + dia * 0.35, Kit.range(s, i + 9, -0.2, 0.2)), if i % 2 == 0 then C.foliage else C.foliageLight, M.leafy, DETAIL)
	end
	return box
end

-- Rug w x d with a border (thickness 0.06, non-colliding). Returns the field.
function Kit.rug(parent: Instance, cf: CFrame, at: CFrame, w: number?, d: number?, seed: number?): Part
	local s = seed or 0
	local W, D = w or 8, d or 6
	local border = Kit.pick({ C.fabricCharcoal, C.oakDark, C.fabricBlue, C.sage }, s)
	local field = Kit.pick({ C.fabricSand, C.carpetWarm, C.sageLight, C.blueSoft }, s + 3)
	Kit.part(parent, cf, "RugBorder", V3(W, 0.04, D), at * CF(0, 0.02, 0), border, M.fabric, DETAIL)
	return Kit.part(parent, cf, "Rug", V3(W - 0.6, 0.05, D - 0.6), at * CF(0, 0.025, 0), field, M.fabric, DETAIL)
end

export type LampOpts = { light: boolean?, mood: string?, drop: number? }
-- Floor lamp (straight or arc by seed), ~6.2 high. opts.light adds a PointLight. Returns the shade.
function Kit.floorLamp(parent: Instance, cf: CFrame, at: CFrame, seed: number?, opts: LampOpts?): Part
	local o: LampOpts = opts or {}
	local s = seed or 0
	local shadeColor = Kit.pick({ C.fabricSand, C.white, C.metal, C.brass }, s)
	local shade: Part
	if Kit.rand(s, 1) < 0.5 then
		Kit.cylinder(parent, cf, "LampBase", "y", 0.12, 1.2, at * CF(0, 0.06, 0), C.metal, M.metal)
		Kit.cylinder(parent, cf, "LampPole", "y", 5.0, 0.14, at * CF(0, 2.62, 0), C.metal, M.metal, DETAIL)
		shade = Kit.cylinder(parent, cf, "LampShade", "y", 1.1, 1.4, at * CF(0, 5.65, 0), shadeColor, if shadeColor == C.fabricSand then M.fabric else M.metal, DETAIL)
	else
		Kit.part(parent, cf, "LampBase", V3(1.0, 0.5, 1.0), at * CF(0, 0.25, 0.6), C.stone, M.marble)
		Kit.cylinder(parent, cf, "LampPole", "y", 6.2, 0.14, at * CF(0, 3.6, 0.6), C.metal, M.metal, DETAIL)
		Kit.part(parent, cf, "LampArm", V3(0.14, 0.14, 2.5), at * CF(0, 6.7, -0.6), C.metal, M.metal, DETAIL)
		shade = Kit.ball(parent, cf, "LampShade", 1.2, at * CF(0, 6.2, -1.7), shadeColor, M.metal, DETAIL)
	end
	if o.light then
		Kit.light(shade, "point", o.mood or "warm", 12, 0.6)
	end
	return shade
end

-- Pendant hanging from a ceiling point `at` (y = ceiling underside). Returns the diffuser part
-- (carries the light unless opts.light == false).
function Kit.pendant(parent: Instance, cf: CFrame, at: CFrame, mood: (string | Color3)?, opts: LampOpts?): Part
	local o: LampOpts = opts or {}
	local drop = o.drop or 3.5
	local glow = if typeof(mood) == "Color3" then mood elseif type(mood) == "string" and (A.mood :: any)[mood] then (A.mood :: any)[mood].color else C.lightWarm
	Kit.cylinder(parent, cf, "PendantCable", "y", drop, 0.06, at * CF(0, -drop / 2, 0), C.metal, M.metal, DETAIL)
	Kit.cylinder(parent, cf, "PendantShade", "y", 0.9, 1.6, at * CF(0, -drop - 0.45, 0), Kit.pick({ C.metal, C.brass, C.white }, math.floor(drop * 10)), M.metal, DETAIL)
	local diffuser = Kit.cylinder(parent, cf, "PendantLight", "y", 0.05, 1.3, at * CF(0, -drop - 0.925, 0), glow, M.neon, DETAIL)
	if o.light ~= false then
		Kit.light(diffuser, "surface", mood or "warm", nil, nil, Enum.NormalId.Bottom)
	end
	return diffuser
end

---------------------------------------------------------------------------------------------
-- Booths, counters, kitchen, racks, workshop
---------------------------------------------------------------------------------------------
-- Closed phone booth 5 x 5 x 9 (centred, door side -Z). Returns the Model (named id).
function Kit.phoneBooth(parent: Instance, cf: CFrame, at: CFrame, id: string, owner: number, seed: number?): Model
	local s = seed or Kit.hash(id)
	local m = Instance.new("Model")
	m.Name = id
	m:SetAttribute("PhoneBooth", true)
	m:SetAttribute("BoothId", id)
	m:SetAttribute("OwnerUserId", owner)
	local shell = Kit.pick({ C.oakLight, C.white, C.sage, C.fabricCharcoal }, s)
	local shellMat = if shell == C.oakLight then M.wood else M.smooth
	Kit.part(m, cf, "BoothFloor", V3(5, 0.15, 5), at * CF(0, 0.075, 0), C.carpet, M.carpet)
	Kit.part(m, cf, "BoothBack", V3(5, 8.7, 0.3), at * CF(0, 4.5, 2.35), shell, shellMat)
	for _, x in { -1, 1 } do
		Kit.part(m, cf, "BoothSide", V3(0.3, 8.7, 4.4), at * CF(x * 2.35, 4.5, -0.05), shell, shellMat)
	end
	Kit.part(m, cf, "BoothRoof", V3(5, 0.3, 5), at * CF(0, 9.0, 0), shell, shellMat)
	Kit.part(m, cf, "BoothHeader", V3(4.4, 0.5, 0.3), at * CF(0, 8.6, -2.35), shell, shellMat)
	Kit.part(m, cf, "BoothSidelight", V3(1.5, 8.2, 0.12), at * CF(-1.45, 4.25, -2.35), C.glass, M.glass, GLASS)
	Kit.part(m, cf, "BoothMullion", V3(0.12, 8.2, 0.2), at * CF(-0.64, 4.25, -2.35), C.metal, M.metal)
	-- Glass door leaf: fixed, walk-through (non-colliding) so players can enter and sit.
	Kit.part(m, cf, "BoothDoor", V3(2.6, 8.2, 0.12), at * CF(0.72, 4.25, -2.35), C.glass, M.glass, { transparency = A.glassTransparencyDoor, castShadow = false, canCollide = false })
	Kit.part(m, cf, "BoothHandle", V3(0.12, 1.8, 0.5), at * CF(-0.4, 4.0, -2.35), C.metalSoft, M.metal, DETAIL)
	Kit.part(m, cf, "BoothSeatBase", V3(3.6, 1.6, 1.4), at * CF(0, 0.95, 1.5), C.fabricCharcoal, M.fabric)
	local seat = Kit.seat(m, cf, "Seat", V3(3.6, 0.4, 1.5), at * CF(0, 1.95, 1.45), Kit.pick({ C.fabric, C.fabricSand, C.fabricBlue }, s + 1), M.fabric)
	seat.CanTouch = true
	Kit.part(m, cf, "BoothShelf", V3(1.4, 0.12, 1.0), at * CF(1.5, 3.2, -0.6), C.oak, M.wood)
	Kit.part(m, cf, "BoothFelt", V3(3.6, 3, 0.08), at * CF(0, 4.8, 2.16), C.fabric, M.fabric, DETAIL)
	local status = Kit.part(m, cf, "BoothStatus", V3(0.6, 0.15, 0.06), at * CF(0, 8.6, -2.53), C.statusGood, M.neon, DETAIL)
	status:SetAttribute("BoothId", id)
	m.Parent = parent
	return m
end

export type CounterOpts = { body: Color3?, top: Color3? }
-- Reception / café counter (free-standing, customers at -Z), length L x depth 2.4, top 3.65.
function Kit.counter(parent: Instance, cf: CFrame, at: CFrame, length: number?, seed: number?, opts: CounterOpts?): Part
	local o: CounterOpts = opts or {}
	local s = seed or 0
	local L = length or 8
	local body = o.body or Kit.pick({ C.oak, C.stone, C.white, C.oakDark }, s)
	local bodyMat = if body == C.stone then M.stone elseif body == C.white then M.smooth else M.wood
	Kit.part(parent, cf, "CounterKick", V3(L - 0.2, 0.3, 1.8), at * CF(0, 0.15, 0.15), C.metal, M.metal)
	Kit.part(parent, cf, "CounterBody", V3(L, 3.2, 2.0), at * CF(0, 1.9, 0.1), body, bodyMat)
	local top = Kit.part(parent, cf, "CounterTop", V3(L + 0.2, 0.15, 2.4), at * CF(0, 3.575, 0), o.top or C.stone, M.marble)
	Kit.part(parent, cf, "CounterBand", V3(L, 0.35, 0.06), at * CF(0, 3.0, -0.93), Kit.pick({ C.brass, C.oakDark, C.metal }, s + 1), M.metal, DETAIL)
	return top
end

-- Reception desk: high transaction ledge at -Z (3.8), lower work desk behind (3.15).
-- Returns (ledge top, front logo panel); give the panel a SurfaceGui (e.g. name it ReceptionSign).
function Kit.receptionDesk(parent: Instance, cf: CFrame, at: CFrame, length: number?, seed: number?): (Part, Part)
	local s = seed or 0
	local L = length or 10
	local body = Kit.pick({ C.oak, C.stone, C.white }, s)
	local bodyMat = if body == C.stone then M.stone elseif body == C.white then M.smooth else M.wood
	Kit.part(parent, cf, "ReceptionKick", V3(L - 0.2, 0.3, 0.7), at * CF(0, 0.15, -0.95), C.metal, M.metal)
	Kit.part(parent, cf, "ReceptionFront", V3(L, 3.35, 0.8), at * CF(0, 1.975, -1.0), body, bodyMat)
	local ledge = Kit.part(parent, cf, "ReceptionLedge", V3(L + 0.3, 0.15, 1.3), at * CF(0, 3.725, -1.05), C.stone, M.marble)
	Kit.part(parent, cf, "ReceptionWorktop", V3(L - 0.4, 0.25, 2.2), at * CF(0, 3.025, 0.7), C.oakLight, M.wood)
	for _, x in { -1, 1 } do
		Kit.part(parent, cf, "ReceptionLeg", V3(0.25, 2.9, 2.0), at * CF(x * (L / 2 - 0.4), 1.45, 0.75), C.metal, M.metal)
	end
	local panel = Kit.part(parent, cf, "ReceptionPanel", V3(L * 0.5, 1.6, 0.08), at * CF(0, 2.1, -1.44), Kit.pick({ C.oakDark, C.brass, C.metal }, s + 2), M.metal)
	return ledge, panel
end

export type KitchenOpts = { fridge: boolean?, coffeeName: string? }
export type Kitchenette = { counter: Part, sink: Part, tap: Part, coffee: Part, fridge: Part? }
-- Kitchenette (wall unit) of length L >= 6: base cabinets, stone counter (3.15), sink + tap,
-- tiled splash, upper cabinets, coffee machine named "PantryCoffee" (opts.coffeeName) and a fridge.
function Kit.kitchenette(parent: Instance, cf: CFrame, at: CFrame, length: number?, seed: number?, opts: KitchenOpts?): Kitchenette
	local o: KitchenOpts = opts or {}
	local s = seed or 0
	local L = math.max(length or 10, 6)
	local withFridge = o.fridge ~= false
	local fw = if withFridge then 2.4 else 0
	local Lb = L - fw
	local cx = -L / 2 + Lb / 2
	local front = Kit.pick({ C.white, C.sage, C.oakLight, C.fabricCharcoal }, s)
	local frontMat = if front == C.oakLight then M.wood else M.smooth
	Kit.part(parent, cf, "BaseCabinets", V3(Lb, 2.75, 2.1), at * CF(cx, 1.625, -1.05), front, frontMat)
	Kit.part(parent, cf, "Kick", V3(Lb, 0.25, 1.9), at * CF(cx, 0.125, -0.95), C.metal, M.metal)
	local counter = Kit.part(parent, cf, "Counter", V3(Lb, 0.15, 2.3), at * CF(cx, 3.075, -1.15), C.stone, M.marble)
	Kit.part(parent, cf, "Splash", V3(Lb, 2.45, 0.08), at * CF(cx, 4.375, -0.04), C.white, M.tile)
	Kit.part(parent, cf, "UpperCabinets", V3(Lb, 2.0, 1.2), at * CF(cx, 6.6, -0.6), front, frontMat)
	for i = 1, math.max(1, math.floor(Lb / 2.5)) do
		Kit.part(parent, cf, "Groove", V3(0.04, 1.8, 0.02), at * CF(-L / 2 + i * Lb / (math.floor(Lb / 2.5) + 1), 6.6, -1.21), C.metal, M.smooth, DETAIL)
	end
	local sx = -L / 2 + math.min(2.2, Lb * 0.3)
	local sink = Kit.part(parent, cf, "Sink", V3(1.6, 0.04, 1.2), at * CF(sx, 3.17, -1.2), C.metalSoft, M.metal, DETAIL)
	local tap = Kit.cylinder(parent, cf, "KitchenTap", "y", 0.9, 0.18, at * CF(sx, 3.6, -0.4), C.metalSoft, M.metal, DETAIL)
	Kit.part(parent, cf, "Spout", V3(0.12, 0.12, 0.6), at * CF(sx, 4.0, -0.65), C.metalSoft, M.metal, DETAIL)
	local coffeeAt = at * CF(-L / 2 + Lb - 1.0, 3.85, -0.8)
	local coffee = Kit.part(parent, cf, o.coffeeName or "PantryCoffee", V3(1.0, 1.4, 1.0), coffeeAt, C.metal, M.metal)
	if not o.coffeeName then
		-- PropFx: steam + brew light while someone brews (players: prompt; NPCs: WorkstationService.perform)
		local light = Kit.part(coffee, cf, "BrewLight", V3(0.3, 0.08, 0.04), coffeeAt * CF(0, 0.45, -0.52), C.metalSoft, M.neon, DETAIL)
		light:SetAttribute("FxGlow", true)
		Kit.cylinder(coffee, cf, "Cup", "y", 0.3, 0.28, coffeeAt * CF(0, -0.55, -0.62), C.white, M.smooth, DETAIL)
		Kit.steamEmitter(coffee, "CoffeeSteam", 4, 0.25)
		Kit.fx(coffee, "steam,blink", { FxColor = C.statusBusy, FxRate = 2, FxSeconds = 5 })
		Kit.action(coffee, "prop", "Coffee machine", nil, { actionText = "Brew", maxDistance = 6 })
	end
	local fridge: Part? = nil
	if withFridge then
		local fx = L / 2 - 1.2
		fridge = Kit.part(parent, cf, "Fridge", V3(2.4, 6.8, 2.2), at * CF(fx, 3.4, -1.1), C.white, M.smooth)
		-- lit interior behind the door (Neon, no light object) and the door leaf as a PropFx hinge
		Kit.part(parent, cf, "FridgeInterior", V3(2.1, 6.2, 0.02), at * CF(fx, 3.4, -2.215), C.lightCool, M.neon, DETAIL)
		local doorAt = at * CF(fx, 3.4, -2.29)
		local leaf = Kit.propModel(parent, cf, "FridgeDoor", doorAt)
		local slab = Kit.part(leaf, cf, "FridgeDoorSlab", V3(2.36, 6.7, 0.12), doorAt, C.white, M.smooth, { canCollide = false, castShadow = false })
		Kit.part(leaf, cf, "FridgeDoorLine", V3(2.3, 0.04, 0.02), doorAt * CF(0, 1.2, -0.07), C.metalSoft, M.smooth, DETAIL)
		Kit.part(leaf, cf, "FridgeHandle", V3(0.1, 2.0, 0.12), doorAt * CF(-0.95, 0.2, -0.12), C.metalSoft, M.metal, DETAIL)
		Kit.fx(leaf, "hinge", { FxAxis = "y", FxTravel = -1.75, FxHinge = V3(1.18, 0, 0), FxSeconds = 4 })
		Kit.action(slab, "prop", "Fridge", nil, { actionText = "Open", maxDistance = 6 })
	end
	return { counter = counter, sink = sink, tap = tap, coffee = coffee, fridge = fridge }
end

export type RackOpts = {
	variant: string?, -- "compute" (default) | "gpu" | "network"
	index: number?, -- RackIndex attribute of the RackBlade
	accent: Color3?, -- gpu blade colour (default ArchPalette.department.compute)
	trayY: number?, -- height above `at` of an overhead cable tray: adds a cable bundle up to it
	name: string?, -- body name (default "ServerRack")
	station: string?, -- WorkstationId whose occupant opens the front door (PropFx FxStation)
}
-- Data-centre rack (free-standing, centred, front -Z): 2 wide x 4 deep x 7.5 high, <= 10 parts.
-- One "RackBlade" part (attribute RackIndex) goes into `blades` (e.g. Office.Blades). Returns (body, blade).
function Kit.serverRack(parent: Instance, cf: CFrame, at: CFrame, seed: number?, blades: Instance?, opts: RackOpts?): (Part, Part)
	local o: RackOpts = opts or {}
	local s = seed or 0
	local variant = o.variant or "compute"
	local body = Kit.part(parent, cf, o.name or "ServerRack", V3(2, 7.5, 3.9), at * CF(0, 3.75, 0.05), C.screen, M.metal)
	body:SetAttribute("RackVariant", variant)
	-- equipment face behind the mesh door: blanking panels, the blade/patch block, cable managers
	Kit.part(parent, cf, "BlankingTop", V3(1.4, 1.1, 0.06), at * CF(0, 6.55, -1.88), C.metal, M.metal, DETAIL)
	Kit.part(parent, cf, "BlankingBottom", V3(1.4, 0.9, 0.06), at * CF(0, 1.05, -1.88), C.metal, M.metal, DETAIL)
	local bladeColor = if variant == "gpu" then (o.accent or A.department.compute) elseif variant == "network" then C.metal else C.metalSoft
	local blade = Kit.part(blades or parent, cf, "RackBlade", V3(1.4, 4.4, 0.08), at * CF(0, 3.8, -1.89), bladeColor, M.metal, DETAIL)
	blade:SetAttribute("RackIndex", o.index or 1)
	blade:SetAttribute("RackVariant", variant)
	if blades then
		-- lit GPU blades (PlotService sets Lit) breathe while the company trains
		Kit.fx(blade, "breathe", { FxGate = "Training" })
	end
	local bgui = Instance.new("SurfaceGui")
	bgui.Name = "Face"
	bgui.Face = Enum.NormalId.Front
	bgui.CanvasSize = Vector2.new(140, 440)
	bgui.LightInfluence = 0.4
	bgui.MaxDistance = 60
	bgui.Parent = blade
	local rows = if variant == "network" then 8 else 11
	for i = 1, rows do
		local f = Instance.new("Frame")
		f.Name = "Unit" .. i
		f.BorderSizePixel = 0
		f.Position = UDim2.fromOffset(8, 8 + (i - 1) * 39)
		f.Size = UDim2.fromOffset(124, if variant == "network" then 18 else 30)
		f.BackgroundColor3 = if variant == "network" then C.white else C.screen
		f.BackgroundTransparency = if variant == "network" then 0.55 else 0.35
		f.Parent = bgui
		if variant == "network" and i % 2 == 1 then
			local fibre = Instance.new("Frame")
			fibre.Name = "Fibre"
			fibre.BorderSizePixel = 0
			fibre.Position = UDim2.fromOffset(4, 20)
			fibre.Size = UDim2.fromOffset(116, 6)
			fibre.BackgroundColor3 = C.statusBusy
			fibre.Parent = f
		end
	end
	for _, x in { -0.86, 0.86 } do
		Kit.part(parent, cf, "CableManager", V3(0.24, 7.0, 0.2), at * CF(x, 3.75, -1.82), C.metal, M.metal, DETAIL)
	end
	-- perforated front door: dark translucent part + stripe gradient + status LED column
	local door = Kit.part(parent, cf, "RackDoor", V3(2, 7.3, 0.08), at * CF(0, 3.75, -2.07), C.metal, M.metal, { detail = true, transparency = 0.35 })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Mesh"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(200, 730)
	gui.LightInfluence = 0.5
	gui.MaxDistance = 70
	gui.Parent = door
	local mesh = Instance.new("Frame")
	mesh.Name = "Perforation"
	mesh.BorderSizePixel = 0
	mesh.Position = UDim2.fromOffset(16, 40)
	mesh.Size = UDim2.fromOffset(168, 650)
	mesh.BackgroundColor3 = C.white
	mesh.BackgroundTransparency = 0.82
	mesh.Parent = gui
	local grad = Instance.new("UIGradient")
	local keys: { ColorSequenceKeypoint } = {}
	for k = 0, 19 do
		table.insert(keys, ColorSequenceKeypoint.new(k / 19, if k % 2 == 0 then C.metalSoft else C.screen))
	end
	grad.Color = ColorSequence.new(keys)
	grad.Rotation = 90
	grad.Parent = mesh
	local leds = { C.statusGood, C.statusGood, C.statusBusy, C.statusGood, C.blueSoft, C.statusGood, C.statusGood, C.statusBusy }
	for i = 1, 8 do
		local led = Instance.new("Frame")
		led.Name = "LED" .. i
		led.BorderSizePixel = 0
		led.Position = UDim2.fromOffset(176, 120 + i * 50)
		led.Size = UDim2.fromOffset(10, 10)
		led.BackgroundColor3 = if Kit.rand(s, i) < 0.15 then C.statusBusy else leds[i]
		led.Parent = gui
	end
	-- PropFx: status LEDs flicker near the camera; the mesh door swings open (hinge on its left edge)
	-- while an engineer works at the linked ServerRack activity
	Kit.fx(door, "hinge,leds", { FxAxis = "y", FxTravel = 1.7, FxHinge = V3(-1, 0, 0), FxStation = o.station })
	-- top cable entry (brush grommet), yellow fibre for network racks, optional bundle to the tray
	Kit.part(parent, cf, "CableEntry", V3(1.0, 0.2, 1.4), at * CF(0, 7.6, 0.8), C.metal, M.rubber, DETAIL)
	if variant == "network" then
		Kit.part(parent, cf, "FibreLoom", V3(0.1, 5.6, 0.1), at * CF(-0.86, 4.1, -1.97), C.statusBusy, M.smooth, DETAIL)
	end
	if o.trayY and o.trayY > 7.8 then
		local h = o.trayY - 7.7
		Kit.cylinder(parent, cf, "CableBundle", "y", h, 0.5, at * CF(0, 7.7 + h / 2, 0.8), if variant == "network" then C.statusBusy else C.metal, M.rubber, DETAIL)
	end
	return body, blade
end

-- Workbench (wall unit) length L x depth 2.6, top 3.2, with pegboard and vise.
function Kit.workbench(parent: Instance, cf: CFrame, at: CFrame, length: number?, seed: number?): Part
	local s = seed or 0
	local L = length or 6
	local top = Kit.part(parent, cf, "BenchTop", V3(L, 0.3, 2.6), at * CF(0, 3.05, -1.3), C.oakLight, M.wood)
	for _, x in { -1, 1 } do
		Kit.part(parent, cf, "BenchFrame", V3(0.3, 2.9, 2.3), at * CF(x * (L / 2 - 0.3), 1.45, -1.3), C.metalSoft, M.metal)
	end
	Kit.part(parent, cf, "BenchShelf", V3(L - 0.6, 0.12, 2.2), at * CF(0, 0.8, -1.3), C.metalSoft, M.metal)
	Kit.part(parent, cf, "Pegboard", V3(L, 3.0, 0.1), at * CF(0, 4.8, -0.05), C.oakLight, M.wood)
	Kit.part(parent, cf, "Vise", V3(0.6, 0.5, 0.6), at * CF(L / 2 - 0.6, 3.45, -2.3), C.metal, M.metal, DETAIL)
	for i = 1, 3 do
		Kit.part(parent, cf, "Tool", V3(0.14, Kit.range(s, i, 0.8, 1.3), 0.08), at * CF(-L / 2 + i * L / 4, 4.8, -0.14), Kit.pick({ C.metal, C.terracotta, C.oakDark }, s + i), M.metal, DETAIL)
	end
	return top
end

---------------------------------------------------------------------------------------------
-- Animated props (PropFx). Every builder tags its root; parts that move never collide.
---------------------------------------------------------------------------------------------
export type PropOpts = { propId: string?, prompt: string?, station: string?, meeting: string? }

-- Vending machine (wall unit, 3 wide x 2.6 deep x 6.6 high). Selection light + display while dispensing.
function Kit.vending(parent: Instance, cf: CFrame, at: CFrame, seed: number?, opts: PropOpts?): Model
	local o: PropOpts = opts or {}
	local s = seed or 0
	local m = Kit.propModel(parent, cf, "VendingMachine", at)
	local body = Kit.part(m, cf, "VendingBody", V3(3, 6.6, 2.6), at * CF(0, 3.3, -1.3), Kit.pick({ C.fabricCharcoal, C.terracotta, C.blue }, s), M.smooth)
	Kit.part(m, cf, "VendingGlass", V3(1.9, 4.4, 0.06), at * CF(-0.4, 4.0, -2.63), C.glass, M.glass, { detail = true, transparency = 0.35 })
	local rows = Kit.part(m, cf, "ProductRows", V3(1.8, 4.2, 0.04), at * CF(-0.4, 4.0, -2.58), C.white, M.smooth, DETAIL)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Products"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(180, 420)
	gui.LightInfluence = 0.5
	gui.MaxDistance = 60
	gui.Parent = rows
	local palette = { C.terracotta, C.sage, C.blueSoft, C.brass, C.statusGood, C.white }
	for r = 0, 4 do
		for c = 0, 3 do
			local f = Instance.new("Frame")
			f.Name = "Item"
			f.BorderSizePixel = 0
			f.Position = UDim2.fromOffset(12 + c * 42, 14 + r * 80)
			f.Size = UDim2.fromOffset(30, 56)
			f.BackgroundColor3 = palette[(r * 4 + c + norm(s)) % #palette + 1]
			f.Parent = gui
		end
	end
	local panel = Kit.part(m, cf, "VendingPanel", V3(0.6, 4.4, 0.06), at * CF(1.05, 4.0, -2.63), C.blueSoft, M.neon, DETAIL)
	panel:SetAttribute("FxGlow", true)
	Kit.text(panel, "SNACKS\n&\nDRINKS", { color = C.white, light = 0, maxDistance = 50, name = "Label" })
	Kit.part(m, cf, "VendingFlap", V3(1.9, 0.7, 0.06), at * CF(-0.4, 1.2, -2.63), C.metal, M.metal, DETAIL)
	Kit.fx(m, "blink,screen", { FxColor = C.statusGood, FxRate = 4, FxText = "ENJOY!", FxSeconds = 4, PropId = o.propId })
	Kit.action(body, "prop", o.prompt or "Vending machine", o.propId, { actionText = "Dispense", maxDistance = 7 })
	return m
end

-- Water cooler (free-standing, centred on `at`): the stream runs while someone drinks.
function Kit.waterCooler(parent: Instance, cf: CFrame, at: CFrame, opts: PropOpts?): Model
	local o: PropOpts = opts or {}
	local m = Kit.propModel(parent, cf, "WaterCooler", at)
	local base = Kit.part(m, cf, "CoolerBase", V3(1.3, 3.4, 1.3), at * CF(0, 1.7, 0), C.white, M.smooth)
	Kit.cylinder(m, cf, "CoolerBottle", "y", 1.4, 1.0, at * CF(0, 4.1, 0), C.water, M.glass, { detail = true, transparency = 0.35 })
	Kit.part(m, cf, "CoolerTap", V3(0.35, 0.25, 0.2), at * CF(0, 2.9, -0.72), C.metalSoft, M.metal, DETAIL)
	local stream = Kit.part(m, cf, "CoolerStream", V3(0.1, 0.6, 0.1), at * CF(0, 2.5, -0.74), C.water, M.glass, { detail = true, transparency = 1 })
	stream:SetAttribute("FxShow", 0.35)
	Kit.part(m, cf, "CoolerTray", V3(0.8, 0.08, 0.4), at * CF(0, 2.12, -0.78), C.metal, M.metal, DETAIL)
	Kit.fx(m, "flow", { FxSeconds = 3, PropId = o.propId })
	Kit.action(base, "prop", o.prompt or "Water cooler", o.propId, { actionText = "Drink", maxDistance = 6 })
	return m
end

-- Desktop 3D printer standing on a bench top (`at` = top surface centre, front -Z): the print head
-- sweeps back and forth and the nozzle glows while it prints.
function Kit.printer3d(parent: Instance, cf: CFrame, at: CFrame, seed: number?, opts: PropOpts?): Model
	local o: PropOpts = opts or {}
	local s = seed or 0
	local m = Kit.propModel(parent, cf, "Printer3D", at)
	local base = Kit.part(m, cf, "PrinterBase", V3(2.0, 0.3, 2.0), at * CF(0, 0.15, 0), C.screen, M.metal, { canCollide = false })
	for _, x in { -0.9, 0.9 } do
		Kit.part(m, cf, "PrinterUpright", V3(0.15, 2.3, 0.15), at * CF(x, 1.45, 0.85), C.metal, M.metal, DETAIL)
	end
	Kit.part(m, cf, "PrinterBeam", V3(2.0, 0.15, 0.15), at * CF(0, 2.55, 0.85), C.metal, M.metal, DETAIL)
	Kit.part(m, cf, "PrinterBed", V3(1.6, 0.08, 1.6), at * CF(0, 0.34, 0), C.metalSoft, M.metal, DETAIL)
	Kit.cylinder(m, cf, "PrintedPart", "y", 0.5, 0.6, at * CF(0.1, 0.63, 0), Kit.pick({ C.terracotta, C.sage, C.blueSoft }, s), M.smooth, DETAIL)
	local head = Kit.part(m, cf, "PrintHead", V3(0.35, 0.35, 0.35), at * CF(-0.5, 1.25, 0), C.white, M.smooth, DETAIL)
	head:SetAttribute("FxMove", true)
	local nozzle = Kit.part(m, cf, "PrintNozzle", V3(0.12, 0.14, 0.12), at * CF(-0.5, 1.0, 0), C.metalSoft, M.neon, DETAIL)
	nozzle:SetAttribute("FxMove", true)
	nozzle:SetAttribute("FxGlow", true)
	Kit.fx(m, "slider,blink", { FxAxis = "x", FxTravel = 1.0, FxRate = 0.5, FxColor = C.statusBusy, FxSeconds = 8, PropId = o.propId, FxStation = o.station })
	if o.prompt then
		Kit.action(base, "prop", o.prompt, o.propId, { actionText = "Print", maxDistance = 7 })
	end
	return m
end

-- Large-format plotter (free-standing, length L along local X, front -Z): carriage sweeps, sheets feed out.
function Kit.plotter(parent: Instance, cf: CFrame, at: CFrame, length: number?, opts: PropOpts?): Model
	local o: PropOpts = opts or {}
	local L = length or 5
	local m = Kit.propModel(parent, cf, "Plotter", at)
	for _, sx in { -1, 1 } do
		Kit.part(m, cf, "PlotterLeg", V3(0.25, 3.0, 1.6), at * CF(sx * (L / 2 - 0.3), 1.5, 0), C.metal, M.metal)
	end
	local body = Kit.part(m, cf, "PlotterBody", V3(L, 0.9, 1.4), at * CF(0, 3.45, 0), C.screen, M.smooth)
	body:SetAttribute("FxOut", true)
	Kit.cylinder(m, cf, "PlotterRoll", "x", L - 0.8, 0.5, at * CF(0, 2.65, 0.35), C.white, M.smooth, DETAIL)
	Kit.part(m, cf, "PlotterSheet", V3(L - 1, 0.02, 1.0), at * CF(0, 2.95, -0.95) * ANG(math.rad(-35), 0, 0), C.white, M.smooth, DETAIL)
	local carriage = Kit.part(m, cf, "PlotterCarriage", V3(0.6, 0.4, 0.5), at * CF(-L / 2 + 0.8, 4.1, -0.2), C.metalSoft, M.metal, DETAIL)
	carriage:SetAttribute("FxMove", true)
	Kit.fx(m, "slider,paper", { FxAxis = "x", FxTravel = L - 1.6, FxRate = 0.25, FxSeconds = 8, PropId = o.propId })
	Kit.action(body, "prop", o.prompt or "Plotter", o.propId, { actionText = "Plot", maxDistance = 7 })
	return m
end

-- Aquarium on a cabinet (free-standing, centred, long axis local X): fish circle, bubbles rise (always on).
function Kit.aquarium(parent: Instance, cf: CFrame, at: CFrame, seed: number?): Model
	local s = seed or 0
	local m = Kit.propModel(parent, cf, "Aquarium", at)
	Kit.part(m, cf, "AquariumCabinet", V3(4.4, 2.6, 1.8), at * CF(0, 1.3, 0), C.oakDark, M.wood)
	Kit.part(m, cf, "AquariumTank", V3(4.2, 2.6, 1.6), at * CF(0, 3.9, 0), C.glass, M.glass, { transparency = 0.6, castShadow = false })
	local water = Kit.part(m, cf, "AquariumWater", V3(4.0, 2.2, 1.4), at * CF(0, 3.8, 0), C.water, M.glass, { detail = true, transparency = 0.55 })
	Kit.steamEmitter(water, "Bubbles", 3, 0.15)
	for k, x in { -0.6, 0.6 } do
		local fish = Kit.part(m, cf, "Fish", V3(0.5, 0.28, 0.14), at * CF(x, 3.6 + k * 0.5, 0) * ANG(0, PI / 2, 0), Kit.pick({ C.terracotta, C.statusBusy, C.blueSoft }, s + k), M.smooth, DETAIL)
		fish:SetAttribute("FxMove", true)
	end
	Kit.part(m, cf, "AquariumLid", V3(4.3, 0.15, 1.7), at * CF(0, 5.27, 0), C.metal, M.metal, DETAIL)
	Kit.fx(m, "spin,steam", { FxAxis = "y", FxRate = 0.7, FxIdle = "on" })
	return m
end

-- Ceiling fan hanging from `at` (mount point on the soffit/pergola): turns during working hours.
function Kit.ceilingFan(parent: Instance, cf: CFrame, at: CFrame, dia: number?): Model
	local D = dia or 5
	local m = Kit.propModel(parent, cf, "CeilingFan", at)
	Kit.part(m, cf, "FanRod", V3(0.15, 1.2, 0.15), at * CF(0, -0.6, 0), C.metal, M.metal, DETAIL)
	local hub = Kit.cylinder(m, cf, "FanHub", "y", 0.35, 0.8, at * CF(0, -1.3, 0), C.metal, M.metal, DETAIL)
	hub:SetAttribute("FxMove", true)
	for k = 0, 2 do
		local blade = Kit.part(m, cf, "FanBlade", V3(D / 2 - 0.3, 0.06, 0.6), at * CF(0, -1.3, 0) * ANG(0, k * 2 * PI / 3, 0) * CF(D / 4 + 0.15, 0, 0), C.oak, M.wood, DETAIL)
		blade:SetAttribute("FxMove", true)
	end
	Kit.fx(m, "spin", { FxAxis = "y", FxRate = 4, FxGate = "Hour", FxIdle = "slow" })
	return m
end

-- LED news ticker band (wall/bracket item, front -Z of `at`): the client scrolls the text.
function Kit.ticker(parent: Instance, cf: CFrame, at: CFrame, w: number, text: string): Part
	local band = Kit.part(parent, cf, "NewsTicker", V3(w, 0.9, 0.12), at * CF(0, 0, -0.06), C.screen, M.smooth, DETAIL)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Ticker"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.MaxDistance = 90
	gui.ClipsDescendants = true
	gui.Parent = band
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(4, 0, 1, 0)
	label.Text = text
	label.TextColor3 = C.statusBusy
	label.Font = Enum.Font.BuilderSansBold
	label.TextSize = 26
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = gui
	Kit.fx(band, "ticker", { FxRate = 60, FxIdle = "on" })
	return band
end

-- Conference speakerphone puck (on a table top `at`): the ring glows while the room's meeting runs.
function Kit.speakerphone(parent: Instance, cf: CFrame, at: CFrame, meeting: string): Part
	local puck = Kit.cylinder(parent, cf, "Speakerphone", "y", 0.25, 1.4, at * CF(0, 0.125, 0), C.screen, M.smooth, DETAIL)
	local ring = Kit.cylinder(puck, cf, "SpeakerRing", "y", 0.04, 1.1, at * CF(0, 0.27, 0), C.metalSoft, M.neon, DETAIL)
	ring:SetAttribute("FxGlow", true)
	Kit.fx(puck, "blink", { FxColor = C.statusGood, FxRate = 0, FxGate = "Meeting", FxMeeting = meeting })
	return puck
end

-- Small office printer (on a counter/credenza top `at`, front -Z): pages come out, the light blinks.
function Kit.deskPrinter(parent: Instance, cf: CFrame, at: CFrame, opts: PropOpts?): Part
	local o: PropOpts = opts or {}
	local body = Kit.part(parent, cf, "DeskPrinter", V3(1.6, 0.8, 1.3), at * CF(0, 0.4, 0), C.white, M.smooth, DETAIL)
	Kit.part(body, cf, "PrinterTray", V3(1.1, 0.04, 0.5), at * CF(0, 0.3, -0.85), C.metalSoft, M.smooth, DETAIL)
	local led = Kit.part(body, cf, "PrinterLed", V3(0.14, 0.06, 0.04), at * CF(0.55, 0.62, -0.66), C.metalSoft, M.neon, DETAIL)
	led:SetAttribute("FxGlow", true)
	Kit.fx(body, "paper,blink", { FxColor = C.statusGood, FxRate = 3, FxSeconds = 5, PropId = o.propId })
	if o.prompt then
		Kit.action(body, "prop", o.prompt, o.propId, { actionText = "Print", maxDistance = 6 })
	end
	return body
end

---------------------------------------------------------------------------------------------
-- Workstations
---------------------------------------------------------------------------------------------
local JOURNEY: { [string]: number } = { data = 1, compute = 2, design = 3, training = 4, evaluation = 5, deployment = 6, growth = 7 }

local DEPT_VARIANTS: { [string]: { string } } = {
	data = { "bench", "bench", "ldesk", "standing" },
	engineering = { "dual", "dual", "bench", "standing" },
	design = { "ldesk", "bench", "standing", "ldesk" },
	training = { "trading", "dual", "trading", "dual" },
	research = { "lab", "ldesk", "lab", "dual" },
	evaluation = { "lab", "dual", "bench", "lab" },
	growth = { "standing", "bench", "ldesk", "bench" },
	deployment = { "bench", "standing", "dual", "bench" },
	operations = { "ldesk", "bench", "ldesk", "standing" },
	compute = { "dual", "trading", "dual", "lab" },
	executive = { "ldesk", "ldesk", "ldesk", "ldesk" },
}
local KIND_VARIANT: { [string]: string } = {
	control = "trading", platform = "trading", lab = "lab", hwlab = "lab", datalab = "lab", secret_lab = "lab",
	prototype = "lab", founder_office = "ldesk", founder_assist = "ldesk", hr = "ldesk", focus = "ldesk",
}

-- Variant name for a desk: room kind first (control rooms -> trading, labs -> lab), then department+style.
function Kit.deskVariant(department: string, roomKind: string?, style: number?): string
	if roomKind and KIND_VARIANT[roomKind] then
		return KIND_VARIANT[roomKind]
	end
	local list = DEPT_VARIANTS[department] or DEPT_VARIANTS.data
	return list[(math.floor(style or 1) - 1) % #list + 1]
end

type StationGeo = { chairZ: number, monitorZ: number, ip: Vector3, extras: { Vector3 } }
local STATION: { [string]: StationGeo } = {
	bench = { chairZ = -2.9, monitorZ = 0.85, ip = V3(2.5, 2.8, -3.2), extras = { V3(-2.8, 0, -0.6), V3(2.9, 0, 0.7) } },
	ldesk = { chairZ = -2.9, monitorZ = 0.85, ip = V3(-2.5, 2.8, -3.2), extras = { V3(-2.8, 0, -0.5), V3(2.7, 0, -3.3) } },
	standing = { chairZ = -2.6, monitorZ = 0.75, ip = V3(2.3, 2.8, -2.8), extras = { V3(-2.2, 0, -0.5), V3(2.2, 0, 0.6) } },
	dual = { chairZ = -3.0, monitorZ = 0.95, ip = V3(2.6, 2.8, -3.3), extras = { V3(-3.2, 0, -0.7), V3(3.3, 0, 0.9) } },
	trading = { chairZ = -2.9, monitorZ = 0.55, ip = V3(2.6, 2.8, -3.4), extras = { V3(-1.9, 0, -0.9), V3(1.9, 0, -1.0) } },
	lab = { chairZ = -2.8, monitorZ = 0.85, ip = V3(2.5, 2.8, -3.1), extras = { V3(-2.6, 0, -0.3), V3(2.4, 5.96, 1.35) } },
}

local function monitor(parent: Instance, cf: CFrame, at: CFrame, name: string, kind: string, accent: Color3, w: number, h: number, topY: number): Part
	local screen = Kit.screen(parent, cf, name, V3(w, h, 0.15), at * CF(0, topY + 0.4 + h / 2, 0), kind, accent)
	Kit.part(parent, cf, "MonitorStand", V3(0.3, 0.55, 0.45), at * CF(0, topY + 0.275, 0.25), C.metal, M.metal, DETAIL)
	return screen
end

-- One small desk accessory at desk-local point p (p.Y = 0 means "on the desk top").
local function extra(parent: Instance, cf: CFrame, at: CFrame, kind: string, p: Vector3, topY: number, seed: number, accent: Color3)
	local y = if p.Y > 0 then p.Y else topY
	local base = at * CF(p.X, y, p.Z)
	if kind == "mug" then
		Kit.cylinder(parent, cf, "Mug", "y", 0.5, 0.42, base * CF(0, 0.25, 0), Kit.pick({ C.white, C.terracotta, C.sage, accent }, seed), M.smooth, DETAIL)
	elseif kind == "plant" then
		Kit.cylinder(parent, cf, "DeskPot", "y", 0.5, 0.55, base * CF(0, 0.25, 0), Kit.pick({ C.white, C.terracotta, C.stoneDeep }, seed), M.smooth, DETAIL)
		Kit.ball(parent, cf, "DeskPlant", 0.9, base * CF(0, 0.85, 0), C.foliageLight, M.grass, DETAIL)
	elseif kind == "notebook" then
		Kit.part(parent, cf, "Notebook", V3(1.2, 0.08, 1.6), base * CF(0, 0.04, 0) * ANG(0, Kit.range(seed, 1, -0.4, 0.4), 0), Kit.pick({ C.oakDark, C.blue, C.fabricSand }, seed), M.smooth, DETAIL)
	elseif kind == "lamp" then
		Kit.cylinder(parent, cf, "LampFoot", "y", 0.1, 0.6, base * CF(0, 0.05, 0), C.metal, M.metal, DETAIL)
		Kit.part(parent, cf, "LampArm", V3(0.1, 1.6, 0.1), base * CF(0, 0.85, 0.15) * ANG(math.rad(-15), 0, 0), C.metal, M.metal, DETAIL)
		local head = Kit.part(parent, cf, "LampHead", V3(0.45, 0.22, 0.75), base * CF(0, 1.62, -0.15), C.metal, M.metal, DETAIL)
		-- PropFx: the desk lamp lights up while somebody works at this desk (FxStation = the station)
		local id = parent:GetAttribute("WorkstationId")
		if typeof(id) == "string" then
			Kit.fx(head, "blink", { FxColor = C.lightWarm, FxRate = 0, FxStation = id })
		end
	elseif kind == "papers" then
		Kit.part(parent, cf, "Papers", V3(1.1, 0.12, 1.5), base * CF(0, 0.06, 0) * ANG(0, Kit.range(seed, 2, -0.3, 0.3), 0), C.white, M.smooth, DETAIL)
	elseif kind == "frame" then
		Kit.part(parent, cf, "PhotoFrame", V3(0.7, 0.55, 0.08), base * CF(0, 0.27, 0) * ANG(math.rad(-12), 0.4, 0), C.oakDark, M.wood, DETAIL)
	elseif kind == "laptop" then
		Kit.part(parent, cf, "LaptopBase", V3(2.2, 0.1, 1.5), base * CF(0, 0.05, 0), C.metalSoft, M.metal, DETAIL)
		Kit.part(parent, cf, "LaptopLid", V3(2.2, 1.4, 0.08), base * CF(0, 0.75, 0.74) * ANG(math.rad(10), 0, 0), C.metalSoft, M.metal, DETAIL)
	elseif kind == "flasks" then
		Kit.cylinder(parent, cf, "Flask", "y", 0.8, 0.45, base * CF(-0.3, 0.4, 0), C.glass, M.glass, { detail = true, transparency = 0.4 })
		Kit.cylinder(parent, cf, "Flask", "y", 0.6, 0.35, base * CF(0.35, 0.3, 0), C.glassDeep, M.glass, { detail = true, transparency = 0.4 })
	elseif kind == "instrument" then
		Kit.part(parent, cf, "Instrument", V3(1.4, 0.9, 1.1), base * CF(0, 0.45, 0), C.white, M.smooth, DETAIL)
		Kit.part(parent, cf, "InstrumentPanel", V3(0.9, 0.4, 0.04), base * CF(0, 0.5, -0.57), C.screen, M.smooth, DETAIL)
	end
end

local EXTRA_KINDS = { "mug", "plant", "notebook", "lamp", "papers", "frame", "laptop", "mug" }

-- Workstation (contract SPEC §5). Desk at `at` (user side -Z), chair at -Z facing +Z (towards the desk).
-- style: variant name ("bench"|"ldesk"|"standing"|"dual"|"trading"|"lab") or a number (picked by department).
function Kit.station(parent: Instance, cf: CFrame, id: string, department: string, role: string?, at: CFrame, level: number, style: (number | string)?, owner: number, accent: Color3, app: string?, section: string?, roomAccess: string?, homeRoom: string?): Model
	local variant = if type(style) == "string" then style else Kit.deskVariant(department, nil, if type(style) == "number" then style else 1)
	if not STATION[variant] then
		variant = "bench"
	end
	local g = STATION[variant]
	local seed = Kit.hash(id)
	local station = Instance.new("Model")
	station.Name = id
	station.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	station:SetAttribute("WorkstationId", id)
	station:SetAttribute("WorkstationType", "Computer")
	station:SetAttribute("WorkstationStyle", variant)
	station:SetAttribute("Department", department)
	station:SetAttribute("Role", "any")
	station:SetAttribute("PreferredRole", if role and role ~= "" then role else "any")
	station:SetAttribute("Capacity", 1)
	station:SetAttribute("Floor", level)
	station:SetAttribute("RoomAccess", roomAccess or "staff")
	if homeRoom then
		station:SetAttribute("HomeRoom", homeRoom)
	end
	station:SetAttribute("OwnerUserId", owner)
	local tint = (A.department :: any)[department] :: Color3?
	local top, topY = Kit.desk(station, cf, at, variant, seed, tint)
	station.PrimaryPart = top
	-- chair (or stool at the standing desk), facing the desk
	local chairAt = at * CF(0, 0, g.chairZ) * ANG(0, PI, 0)
	local seat: Seat
	if variant == "standing" then
		seat = Kit.stool(station, cf, chairAt, seed, 3.2, { name = "ChairSeat", canTouch = false })
	else
		seat = Kit.officeChair(station, cf, chairAt, seed, { lite = true, arms = variant == "ldesk" or variant == "trading", name = "ChairSeat", canTouch = false })
	end
	Kit.action(seat, "sit", "Chair", nil, { maxDistance = 4, actionText = "Sit" })
	station:SetAttribute("SeatPosition", seat.CFrame)
	station:SetAttribute("InteractionPosition", (cf * at * CF(g.ip)).Position)
	-- screens
	local screen: Part
	if variant == "dual" then
		screen = monitor(station, cf, at * CF(-1.8, 0, g.monitorZ) * ANG(0, -0.3, 0), "DisplayContent", department, accent, 3.4, 2.0, topY)
		monitor(station, cf, at * CF(1.8, 0, g.monitorZ) * ANG(0, 0.3, 0), "SecondaryDisplay", "secondary", accent, 3.4, 2.0, topY):SetAttribute("WorkstationId", id)
	elseif variant == "trading" then
		screen = monitor(station, cf, at * CF(0, 0, g.monitorZ), "DisplayContent", department, accent, 3.2, 1.9, topY)
		local phi = 0.42
		for _, sgn in { -1, 1 } do
			local wing = at * CF(sgn * (2.5 + 1.8 * math.cos(phi)), 0, -1.8 * math.sin(phi)) * ANG(0, sgn * phi, 0) * CF(0, 0, 0.75)
			monitor(station, cf, wing, "SecondaryDisplay", "secondary", accent, 3.0, 1.8, topY):SetAttribute("WorkstationId", id)
		end
	else
		screen = monitor(station, cf, at * CF(0, 0, g.monitorZ), "DisplayContent", department, accent, 3.4, 2.0, topY)
	end
	screen:SetAttribute("WorkstationId", id)
	screen:SetAttribute("JourneyStep", JOURNEY[department])
	if app then
		Kit.prompt(screen, "Workstation · " .. department, owner, app, section)
	end
	-- keyboard + mouse
	local kz = if variant == "trading" then -0.9 else -0.8
	Kit.part(station, cf, "Keyboard", V3(2.6, 0.1, 0.8), at * CF(0, topY + 0.05, kz), C.metal, M.smooth, DETAIL)
	Kit.part(station, cf, "Mouse", V3(0.35, 0.1, 0.6), at * CF(1.9, topY + 0.05, kz), C.white, M.smooth, DETAIL)
	-- deterministic accessories
	if variant == "lab" then
		extra(station, cf, at, "instrument", g.extras[1], topY, seed, accent)
		extra(station, cf, at, "flasks", g.extras[2], topY, seed, accent)
	else
		extra(station, cf, at, Kit.pick(EXTRA_KINDS, seed), g.extras[1], topY, seed, accent)
		if Kit.rand(seed, 9) < 0.55 then
			extra(station, cf, at, Kit.pick({ "mug", "notebook", "papers", "plant" }, seed // 7), g.extras[2], topY, seed + 1, accent)
		end
	end
	Collection:AddTag(station, "Workstation")
	station.Parent = parent
	return station
end

export type ActivityExtra = {
	roomAccess: string?,
	homeRoom: string?,
	facing: Vector3?, -- building-local point the NPC looks at (stored as world FacingPosition)
	meetingRoom: string?,
	conversationGroup: string?,
	capacity: number?,
	attributes: { [string]: any }?,
}
-- Invisible interaction point (Whiteboard, Pipeline, LabBench, ServerRack, Meeting, Conversation,
-- Coffee, Snack, Fridge, Dining, Lounge, Service...). `at` = standing point (building-local).
function Kit.activity(parent: Instance, cf: CFrame, id: string, kind: string, department: string, role: string, at: CFrame, level: number, owner: number, seat: Seat?, extraAttrs: ActivityExtra?): Model
	local x: ActivityExtra = extraAttrs or {}
	local m = Instance.new("Model")
	m.Name = id
	m:SetAttribute("WorkstationId", id)
	m:SetAttribute("WorkstationType", kind)
	m:SetAttribute("Department", department)
	m:SetAttribute("Role", role)
	m:SetAttribute("Capacity", x.capacity or 1)
	m:SetAttribute("Floor", level)
	m:SetAttribute("OwnerUserId", owner)
	m:SetAttribute("RoomAccess", x.roomAccess or "staff")
	if x.homeRoom then
		m:SetAttribute("HomeRoom", x.homeRoom)
	end
	if x.meetingRoom then
		m:SetAttribute("MeetingRoom", x.meetingRoom)
	end
	if x.conversationGroup then
		m:SetAttribute("ConversationGroup", x.conversationGroup)
	end
	if x.facing then
		m:SetAttribute("FacingPosition", cf:PointToWorldSpace(x.facing))
	end
	if x.attributes then
		for k, v in x.attributes do
			m:SetAttribute(k, v)
		end
	end
	local anchor = Kit.part(m, cf, "InteractionPoint", V3(0.2, 0.2, 0.2), at, C.white, nil, { detail = true, transparency = 1 })
	m.PrimaryPart = anchor
	m:SetAttribute("InteractionPosition", anchor.Position)
	if seat then
		seat.Parent = m
		m:SetAttribute("SeatPosition", seat.CFrame)
	end
	m.Parent = parent
	Collection:AddTag(m, "Workstation")
	return m
end

-- Navigation node at (x, y + 2.8, z) building-local (OfficeKit contract).
function Kit.node(parent: Instance, cf: CFrame, id: string, x: number, y: number, z: number, kind: string, floor: number): Part
	local p = Kit.part(parent, cf, id, V3(0.2, 0.2, 0.2), CF(x, y + 2.8, z), C.white, nil, { detail = true, transparency = 1 })
	p:SetAttribute("NavigationNode", kind)
	p:SetAttribute("Floor", floor)
	Collection:AddTag(p, "NavigationNode")
	return p
end

---------------------------------------------------------------------------------------------
-- Doors (SPEC §3)
---------------------------------------------------------------------------------------------
-- Door-local frame D: origin = opening centre on the wall line at floor level, +X along the wall,
-- +Z = def.inward (the protected side), -Z = outside. Width w along X, height h.
type Ctx = {
	model: Model,
	frame: Model,
	base: CFrame,
	def: DoorDef,
	x: any, -- def with optional extra fields
	kind: string,
	owner: number,
	w: number,
	h: number,
	t: number, -- wall thickness
	s: number, -- swing sign: +1 opens towards +Z (inward), -1 outward
	hx: number, -- hinge side of single leaves: -1 = local -X jamb, +1 = local +X jamb
	latch: number, -- jamb side that carries readers / anchors
	jw: number, -- jamb width (0 = no jambs)
	jd: number, -- jamb depth
	fz: number, -- frame centre z
	cw: number, -- clear width between jambs
	ch: number, -- clear height under the head
	sweep: number, -- sensor half-depth
	along: number, -- +1 when local +X runs along +a (building X for axis "x", Z for axis "z")
}

-- Default wall thickness per kind when def.thickness is absent (Kit.wall always passes the real one).
local DOOR_T: { [string]: number } = { glass = 0.4, glassdouble = 0.4, autoslide = 0.4, cubicle = 0.15, gate = 0.5, speedgate = 0.3 }
local DOOR_H: { [string]: number } = { autoslide = 10, glassdouble = 10, cubicle = 7.2, fridge = 6.4, gate = 4.5, speedgate = 3.4 }
local DOOR_TEXT: { [string]: string } = {
	glass = "Glass door", glassdouble = "Glass doors", solid = "Door", secure = "Secure door", service = "Service door",
	flush = "Panel", bookcase = "Book", vault = "Vault door", autoslide = "Entrance", cubicle = "Cubicle",
	fridge = "Fridge", gate = "Gate", speedgate = "Speed gate",
}
local READER_OUT: { [string]: boolean } = { glass = true, glassdouble = true, solid = true, secure = true, service = true, autoslide = true, vault = true, gate = true }
local READER_IN: { [string]: boolean } = { secure = true, service = true, vault = true, autoslide = true }
local PRIVATE_ROOMS = { "WC", "RESTROOM", "SHOWER", "BATH", "SAUNA" }

local function dp(ctx: Ctx, parent: Instance, name: string, size: Vector3, lcf: CFrame, color: Color3, mat: Enum.Material?, opts: Opts?): Part
	return Kit.part(parent, ctx.base, name, size, lcf, color, mat, opts)
end

local function frameStd(ctx: Ctx, jw: number, hh: number, color: Color3, mat: Enum.Material, threshold: boolean)
	ctx.jw = jw
	ctx.cw = ctx.w - 2 * jw
	ctx.ch = ctx.h - hh
	dp(ctx, ctx.frame, "JambL", V3(jw, ctx.h, ctx.jd), CF(-(ctx.w - jw) / 2, ctx.h / 2, ctx.fz), color, mat)
	dp(ctx, ctx.frame, "JambR", V3(jw, ctx.h, ctx.jd), CF((ctx.w - jw) / 2, ctx.h / 2, ctx.fz), color, mat)
	dp(ctx, ctx.frame, "Head", V3(ctx.cw, hh, ctx.jd), CF(0, ctx.h - hh / 2, ctx.fz), color, mat)
	if threshold then
		dp(ctx, ctx.frame, "Threshold", V3(ctx.cw, 0.05, ctx.jd - 0.04), CF(0, 0.025, ctx.fz), C.metalSoft, M.metal, DETAIL)
	end
end

local function newLeaf(ctx: Ctx, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = ctx.model
	return m
end

local function markSlab(ctx: Ctx, part: BasePart)
	local mod = Instance.new("PathfindingModifier")
	mod.PassThrough = true
	mod.Label = ctx.def.access
	mod.Parent = part
end

-- Swing leaf: hinge axis at local (hx * cw/2, 0, hingeZ); opens by `angle` towards s*Z.
local function swingPivot(ctx: Ctx, leaf: Model, hx: number, hingeZ: number, angle: number)
	local closed = ctx.base * CF(hx * ctx.cw / 2, 0, hingeZ)
	leaf.WorldPivot = closed
	leaf:SetAttribute("ClosedPivot", closed)
	leaf:SetAttribute("OpenPivot", closed * ANG(0, ctx.s * hx * angle, 0))
	leaf:SetAttribute("Motion", "swing")
end

local function slidePivot(ctx: Ctx, leaf: Model, lcf: CFrame, offset: Vector3)
	local closed = ctx.base * lcf
	leaf.WorldPivot = closed
	leaf:SetAttribute("ClosedPivot", closed)
	leaf:SetAttribute("OpenPivot", closed * CF(offset))
	leaf:SetAttribute("Motion", "slide")
end

-- Part of a swing leaf; u = distance from the hinge jamb face along the leaf, v = offset from the leaf plane zc.
local function lp(ctx: Ctx, leaf: Model, hx: number, zc: number, name: string, size: Vector3, u: number, y: number, v: number, color: Color3, mat: Enum.Material?, opts: Opts?): Part
	return dp(ctx, leaf, name, size, CF(hx * (ctx.cw / 2 - u), y, zc + v), color, mat, opts)
end

local function hinges(ctx: Ctx, leaf: Model, hx: number, hingeZ: number, ys: { number }, d: number, len: number)
	for _, y in ys do
		Kit.cylinder(leaf, ctx.base, "Hinge", "y", len, d, CF(hx * ctx.cw / 2, y, hingeZ), C.metalSoft, M.metal, DETAIL)
	end
end

-- Frameless glass leaf with patch rails and a through pull handle.
local function glassLeaf(ctx: Ctx, name: string, hx: number, lw: number): Model
	local leaf = newLeaf(ctx, name)
	local rd = 0.22
	local zc = ctx.s * (ctx.t / 2 - rd / 2)
	local g = 0.04
	local lh = ctx.ch - 0.1
	local uc = g + lw / 2
	lp(ctx, leaf, hx, zc, "BottomRail", V3(lw, 0.42, rd), uc, 0.06 + 0.21, 0, C.metal, M.metal)
	local gh = lh - 0.44
	local glass = lp(ctx, leaf, hx, zc, "Slab", V3(lw - 0.02, gh, 0.12), uc, 0.48 + gh / 2, 0, C.glass, M.glass, GLASS_DOOR)
	markSlab(ctx, glass)
	lp(ctx, leaf, hx, zc, "Pull", V3(0.12, 2.8, 0.62), g + lw - 0.4, 4.0, 0, C.metalSoft, M.metal, DETAIL)
	swingPivot(ctx, leaf, hx, ctx.s * ctx.t / 2, PI / 2)
	ctx.sweep = math.max(ctx.sweep, lw + 0.5)
	return leaf
end

-- Timber leaf with optional vision panel (slab split around the glass), kick plate, levers, hinges.
local function timberLeaf(ctx: Ctx, name: string, hx: number, lw: number, lt: number, color: Color3, mat: Enum.Material, vision: boolean): Model
	local leaf = newLeaf(ctx, name)
	local zc = ctx.s * (ctx.t / 2 - lt / 2)
	local g, y0 = 0.04, 0.06
	local lh = ctx.ch - 0.1
	local slab: Part
	if vision and lw > 2.4 and not Kit.LEAN then
		-- full-height glazed vision strip towards the latch side
		local p1 = g + lw - 1.25
		local p2 = p1 + 0.45
		slab = lp(ctx, leaf, hx, zc, "Slab", V3(p1 - g, lh, lt), (g + p1) / 2, y0 + lh / 2, 0, color, mat)
		lp(ctx, leaf, hx, zc, "SlabLatch", V3(g + lw - p2, lh, lt), (p2 + g + lw) / 2, y0 + lh / 2, 0, color, mat)
		lp(ctx, leaf, hx, zc, "VisionPanel", V3(0.45, lh, 0.06), (p1 + p2) / 2, y0 + lh / 2, 0, C.glass, M.glass, GLASS_DOOR)
	else
		slab = lp(ctx, leaf, hx, zc, "Slab", V3(lw, lh, lt), g + lw / 2, y0 + lh / 2, 0, color, mat)
	end
	markSlab(ctx, slab)
	if not Kit.LEAN then
		lp(ctx, leaf, hx, zc, "KickPlate", V3(lw - 0.3, 0.7, lt + 0.04), g + lw / 2, y0 + 0.35, 0, C.metalSoft, M.metal, DETAIL)
		hinges(ctx, leaf, hx, ctx.s * ctx.t / 2, { 1.2, ctx.ch - 1.4 }, 0.13, 0.5)
	end
	-- one through part reads as a lever on each face
	lp(ctx, leaf, hx, zc, "Lever", V3(0.65, 0.1, lt + 0.24), g + lw - 0.55, 3.4, 0, C.metalSoft, M.metal, DETAIL)
	swingPivot(ctx, leaf, hx, ctx.s * ctx.t / 2, PI / 2)
	ctx.sweep = math.max(ctx.sweep, lw + 0.5)
	return leaf
end

-- Painted metal leaf: push bar on the push side, lever on the pull side, kick plate, three hinges.
local function serviceLeaf(ctx: Ctx, name: string, hx: number, lw: number): Model
	local leaf = newLeaf(ctx, name)
	local lt = 0.2
	local zc = ctx.s * (ctx.t / 2 - lt / 2)
	local g, y0 = 0.04, 0.06
	local lh = ctx.ch - 0.1
	local slab = lp(ctx, leaf, hx, zc, "Slab", V3(lw, lh, lt), g + lw / 2, y0 + lh / 2, 0, C.metalSoft, M.metal)
	markSlab(ctx, slab)
	if not Kit.LEAN then
		lp(ctx, leaf, hx, zc, "KickPlate", V3(lw - 0.2, 0.8, lt + 0.04), g + lw / 2, y0 + 0.4, 0, C.metal, M.metal, DETAIL)
	end
	lp(ctx, leaf, hx, zc, "PushBar", V3(math.max(lw - 0.8, 0.6), 0.22, 0.25), g + lw / 2 + 0.2, 3.5, -ctx.s * (lt / 2 + 0.125), C.metal, M.metal, DETAIL)
	lp(ctx, leaf, hx, zc, "Lever", V3(0.65, 0.1, 0.12), g + lw - 0.55, 3.4, ctx.s * (lt / 2 + 0.06), C.metal, M.metal, DETAIL)
	if not Kit.LEAN then
		lp(ctx, leaf, hx, zc, "VentGrille", V3(math.min(1.6, lw - 0.6), 0.8, lt + 0.02), g + lw / 2, 1.6, 0, C.metal, M.metal, DETAIL)
		hinges(ctx, leaf, hx, ctx.s * ctx.t / 2, { 1.2, ctx.ch - 1.4 }, 0.14, 0.5)
	end
	swingPivot(ctx, leaf, hx, ctx.s * ctx.t / 2, PI / 2)
	ctx.sweep = math.max(ctx.sweep, lw + 0.5)
	return leaf
end

local function gateLeaf(ctx: Ctx, name: string, hx: number, lw: number): Model
	local leaf = newLeaf(ctx, name)
	local lt = 0.15
	local zc = ctx.s * (ctx.t / 2 - lt / 2)
	local g = 0.04
	local lh = ctx.ch - 0.3
	local slab = lp(ctx, leaf, hx, zc, "Slab", V3(lw, 0.2, lt), g + lw / 2, 0.35, 0, C.metal, M.metal)
	markSlab(ctx, slab)
	lp(ctx, leaf, hx, zc, "TopRail", V3(lw, 0.2, lt), g + lw / 2, 0.25 + lh - 0.1, 0, C.metal, M.metal)
	lp(ctx, leaf, hx, zc, "HingeStile", V3(0.15, lh - 0.4, lt), g + 0.075, 0.25 + lh / 2, 0, C.metal, M.metal)
	lp(ctx, leaf, hx, zc, "LatchStile", V3(0.15, lh - 0.4, lt), g + lw - 0.075, 0.25 + lh / 2, 0, C.metal, M.metal)
	local slats = math.max(1, math.floor((lh - 0.6) / 0.6))
	for i = 1, slats do
		local y = 0.45 + (i - 0.5) * (lh - 0.4) / slats
		dp(ctx, leaf, "Louvre", V3(lw - 0.3, 0.4, 0.05), CF(hx * (ctx.cw / 2 - g - lw / 2), y, zc) * ANG(math.rad(35), 0, 0), C.metalSoft, M.metal, DETAIL)
	end
	swingPivot(ctx, leaf, hx, ctx.s * ctx.t / 2, PI / 2)
	ctx.sweep = math.max(ctx.sweep, lw + 0.5)
	return leaf
end

type Builder = (Ctx) -> (BasePart?, BasePart?)
local BUILD: { [string]: Builder } = {}

local function isDouble(ctx: Ctx): boolean
	return ctx.cw > 6.5
end

BUILD.glass = function(ctx: Ctx)
	ctx.jd = ctx.t
	frameStd(ctx, 0.25, 0.3, C.metal, M.metal, false)
	if isDouble(ctx) then
		glassLeaf(ctx, "Leaf1", -1, ctx.cw / 2 - 0.06)
		glassLeaf(ctx, "Leaf2", 1, ctx.cw / 2 - 0.06)
		ctx.latch = 1
	else
		glassLeaf(ctx, "Leaf1", ctx.hx, ctx.cw - 0.08)
	end
	return nil, nil
end

BUILD.glassdouble = function(ctx: Ctx)
	ctx.jd = ctx.t
	frameStd(ctx, 0.25, 0.3, C.metal, M.metal, false)
	glassLeaf(ctx, "Leaf1", -1, ctx.cw / 2 - 0.06)
	glassLeaf(ctx, "Leaf2", 1, ctx.cw / 2 - 0.06)
	ctx.latch = 1
	return nil, nil
end

local function timberDoor(ctx: Ctx, color: Color3, lt: number, vision: boolean)
	if isDouble(ctx) then
		timberLeaf(ctx, "Leaf1", -1, ctx.cw / 2 - 0.06, lt, color, M.wood, vision)
		timberLeaf(ctx, "Leaf2", 1, ctx.cw / 2 - 0.06, lt, color, M.wood, vision)
		ctx.latch = 1
	else
		timberLeaf(ctx, "Leaf1", ctx.hx, ctx.cw - 0.08, lt, color, M.wood, vision)
	end
end

BUILD.solid = function(ctx: Ctx)
	ctx.jd = ctx.t
	frameStd(ctx, 0.3, 0.35, C.white, M.smooth, false)
	local vision = if ctx.x.vision ~= nil then ctx.x.vision == true else true
	if ctx.x.vision == nil then
		local room = string.upper(ctx.def.room)
		for _, key in PRIVATE_ROOMS do
			if string.find(room, key, 1, true) then
				vision = false
			end
		end
	end
	timberDoor(ctx, C.oak, 0.2, vision)
	return nil, nil
end

BUILD.secure = function(ctx: Ctx)
	ctx.jd = ctx.t
	frameStd(ctx, 0.35, 0.4, C.metal, M.metal, true)
	timberDoor(ctx, C.oakDark, 0.25, ctx.x.vision ~= false)
	return nil, nil
end

BUILD.service = function(ctx: Ctx)
	ctx.jd = ctx.t
	frameStd(ctx, 0.3, 0.35, C.metal, M.metal, true)
	if isDouble(ctx) then
		serviceLeaf(ctx, "Leaf1", -1, ctx.cw / 2 - 0.06)
		serviceLeaf(ctx, "Leaf2", 1, ctx.cw / 2 - 0.06)
		ctx.latch = 1
	else
		serviceLeaf(ctx, "Leaf1", ctx.hx, ctx.cw - 0.08)
	end
	return nil, nil
end

-- Flush door: a timber panel as thick as the wall, battens on the Kit.PANEL_PITCH grid, no frame.
BUILD.flush = function(ctx: Ctx)
	ctx.jw, ctx.jd, ctx.cw, ctx.ch = 0, ctx.t, ctx.w, ctx.h
	dp(ctx, ctx.frame, "Stop", V3(ctx.w, 0.05, ctx.t * 0.5), CF(0, ctx.h - 0.025, 0), C.oakDark, M.wood, DETAIL)
	local leaf = newLeaf(ctx, "Leaf1")
	local hx = ctx.hx
	local g = 0.05
	local lw = ctx.w - 0.1
	local lh = ctx.h - 0.1
	local slab = lp(ctx, leaf, hx, 0, "Slab", V3(lw, lh, ctx.t), g + lw / 2, 0.02 + lh / 2, 0, C.oakLight, M.wood)
	markSlab(ctx, slab)
	local da = if ctx.def.axis == "x" then ctx.def.x else ctx.def.z
	local P = Kit.PANEL_PITCH
	local top = math.min(Kit.CEILING, ctx.h - 0.1)
	for k = math.ceil((da - ctx.w / 2 + 0.3) / P), math.floor((da + ctx.w / 2 - 0.3) / P) do
		local xl = ctx.along * (k * P - da)
		for _, side in { -1, 1 } do
			dp(ctx, leaf, "Batten", V3(0.2, top - 0.45, 0.06), CF(xl, 0.45 + (top - 0.45) / 2, side * (ctx.t / 2 + 0.03)), C.oakDark, M.wood, DETAIL)
		end
	end
	for _, side in { -1, 1 } do
		lp(ctx, leaf, hx, 0, "Skirting", V3(lw, 0.45, 0.06), g + lw / 2, 0.225, side * (ctx.t / 2 + 0.03), C.oakDark, M.wood, DETAIL)
	end
	swingPivot(ctx, leaf, hx, ctx.s * ctx.t / 2, PI / 2)
	ctx.sweep = lw + 0.5
	local outP = dp(ctx, ctx.model, "PromptOut", V3(0.3, 0.3, 0.3), CF(ctx.latch * (ctx.w / 2 - 0.6), 3.6, -(ctx.t / 2 + 0.3)), C.white, nil, { detail = true, transparency = 1 })
	local inP = dp(ctx, ctx.model, "PromptIn", V3(0.35, 0.6, 0.05), CF(ctx.latch * (ctx.w / 2 + 0.4), 3.6, ctx.t / 2 + 0.085), C.metalSoft, M.metal, DETAIL)
	return outP, inP
end

-- Bookcase: shelving unit filling the opening. The books face the OUTSIDE (-Z, the unprotected room
-- such as the archive) so it reads as ordinary shelving; its back panel faces the protected side.
-- Slides by its own width along the wall (default towards local +X; def.slide = -1 reverses).
BUILD.bookcase = function(ctx: Ctx)
	ctx.jw, ctx.cw, ctx.ch = 0, ctx.w, ctx.h
	ctx.jd = ctx.t
	local w, h = ctx.w, ctx.h
	dp(ctx, ctx.frame, "Cornice", V3(w, 0.4, ctx.t), CF(0, h - 0.2, 0), C.oakDark, M.wood)
	local leaf = newLeaf(ctx, "Leaf1")
	local depth = 1.4
	local front = -(ctx.t / 2 - 0.02) -- book face, outside
	local zc = front + depth / 2
	local hb = h - 0.45
	local wood = C.oakDark
	local back = dp(ctx, leaf, "Slab", V3(w - 0.3, hb, 0.1), CF(0, 0.03 + hb / 2, front + depth - 0.05), wood, M.wood)
	markSlab(ctx, back)
	for _, x in { -1, 1 } do
		dp(ctx, leaf, "Side", V3(0.15, hb, depth), CF(x * (w / 2 - 0.075), 0.03 + hb / 2, zc), wood, M.wood)
	end
	dp(ctx, leaf, "Top", V3(w - 0.3, 0.15, depth), CF(0, 0.03 + hb - 0.075, zc), wood, M.wood)
	dp(ctx, leaf, "Plinth", V3(w - 0.3, 0.4, depth), CF(0, 0.23, zc), wood, M.wood)
	local rows = 5
	local y1, y2 = 0.43, 0.03 + hb - 0.15
	local rowH = (y2 - y1 - (rows - 1) * 0.1) / rows
	local seed = Kit.hash(ctx.def.id)
	-- unrotated shelf frame at the back panel: spines face -Z (outside)
	local shelfAt = CF(0, 0, front + depth - 0.1)
	local specialY = 0
	for r = 1, rows do
		local y = y1 + (r - 1) * (rowH + 0.1)
		if r > 1 then
			dp(ctx, leaf, "Shelf", V3(w - 0.3, 0.1, depth - 0.15), CF(0, y - 0.05, zc + 0.05), wood, M.wood)
		end
		if r == 3 then
			specialY = y
			bookRow(leaf, ctx.base, shelfAt, -w / 2 + 0.15, w / 2 - 1.2, y, rowH, -0.1, seed + r * 31, 9)
		else
			bookRow(leaf, ctx.base, shelfAt, -w / 2 + 0.15, w / 2 - 0.15, y, rowH, -0.1, seed + r * 31, 11)
		end
	end
	-- the tell: a red leather spine pulled out a little in the free slot of the middle shelf
	local sx = w / 2 - 0.7
	dp(ctx, leaf, "SpecialBook", V3(0.4, rowH - 0.2, 0.95), CF(sx, specialY + (rowH - 0.2) / 2, front + 0.45), C.terracotta, M.leather, DETAIL)
	local dir = if ctx.x.slide == -1 then -1 else 1
	slidePivot(ctx, leaf, CF(0, 0, zc), V3(dir * w, 0, 0))
	ctx.sweep = 2
	local outP = dp(ctx, ctx.model, "PromptOut", V3(0.3, 0.3, 0.3), CF(sx, specialY + 0.6, front - 0.3), C.white, nil, { detail = true, transparency = 1 })
	local inP = dp(ctx, ctx.model, "PromptIn", V3(0.3, 0.3, 0.3), CF(-sx, 3.6, front + depth + 0.3), C.white, nil, { detail = true, transparency = 1 })
	return outP, inP
end

-- Vault: thick steel leaf with spoked locking wheel, heavy hinges, swings 100 degrees.
BUILD.vault = function(ctx: Ctx)
	local lt = math.min(1.0, ctx.t)
	local zc = ctx.s * (ctx.t / 2 - lt / 2)
	ctx.jd = ctx.t
	frameStd(ctx, 0.55, 0.6, C.metal, M.metal, true)
	local leaf = newLeaf(ctx, "Leaf1")
	local hx = ctx.hx
	local g = 0.04
	local lw = ctx.cw - 0.08
	local lh = ctx.ch - 0.1
	local uc = g + lw / 2
	local slab = lp(ctx, leaf, hx, zc, "Slab", V3(lw, lh, lt), uc, 0.06 + lh / 2, 0, C.metalSoft, M.metal)
	markSlab(ctx, slab)
	local out = -ctx.s
	lp(ctx, leaf, hx, zc, "FacePlate", V3(lw - 0.9, lh - 1.2, 0.08), uc, 0.06 + lh / 2, out * (lt / 2 + 0.04), C.metal, M.metal, DETAIL)
	local wy = 0.06 + lh / 2
	local wheelZ = zc + out * (lt / 2 + 0.08 + 0.2)
	local wx = hx * (ctx.cw / 2 - uc)
	Kit.cylinder(leaf, ctx.base, "WheelHub", "z", 0.4, 0.7, CF(wx, wy, wheelZ), C.stoneDeep, M.metal, DETAIL)
	for k = 0, 2 do
		dp(ctx, leaf, "WheelSpoke", V3(2.8, 0.18, 0.18), CF(wx, wy, wheelZ) * ANG(0, 0, k * PI / 3), C.stoneDeep, M.metal, DETAIL)
	end
	lp(ctx, leaf, hx, zc, "ReleaseBar", V3(0.15, 1.6, 0.25), g + lw - 0.6, 4.0, ctx.s * (lt / 2 + 0.125), C.metal, M.metal, DETAIL)
	hinges(ctx, leaf, hx, ctx.s * ctx.t / 2, { 1.8, ctx.ch - 2.0 }, 0.5, 1.6)
	swingPivot(ctx, leaf, hx, ctx.s * ctx.t / 2, math.rad(100))
	ctx.sweep = lw + 1
	return nil, nil
end

-- Automatic sliding door: two glass leaves sliding into side pockets, operator header.
BUILD.autoslide = function(ctx: Ctx)
	local w, h = ctx.w, ctx.h
	ctx.jw, ctx.jd = 0.3, ctx.t
	ctx.cw, ctx.ch = w - 0.6, h - 0.9
	dp(ctx, ctx.frame, "JambL", V3(0.3, h, ctx.jd), CF(-(w - 0.3) / 2, h / 2, 0), C.metal, M.metal)
	dp(ctx, ctx.frame, "JambR", V3(0.3, h, ctx.jd), CF((w - 0.3) / 2, h / 2, 0), C.metal, M.metal)
	dp(ctx, ctx.frame, "Operator", V3(ctx.cw, 0.9, ctx.t), CF(0, h - 0.45, 0), C.metal, M.metal)
	dp(ctx, ctx.frame, "FloorTrack", V3(ctx.cw, 0.04, math.min(0.4, ctx.t)), CF(0, 0.02, 0), C.metalSoft, M.metal, DETAIL)
	local lw = ctx.cw / 2 - 0.02
	local lh = ctx.ch - 0.1
	for i, hx in { -1, 1 } do
		local leaf = newLeaf(ctx, "Leaf" .. i)
		local cx = hx * (ctx.cw / 2 - lw / 2)
		local inner = cx - hx * (lw / 2 - 0.075) -- meeting stile at the door centre
		local outer = cx + hx * (lw / 2 - 0.06)
		local glass = dp(ctx, leaf, "Slab", V3(lw - 0.27, lh - 0.6, 0.1), CF(cx - hx * 0.015, 0.31 + (lh - 0.6) / 2, 0), C.glass, M.glass, GLASS_DOOR)
		markSlab(ctx, glass)
		dp(ctx, leaf, "TopRail", V3(lw, 0.35, 0.2), CF(cx, 0.06 + lh - 0.175, 0), C.metal, M.metal)
		dp(ctx, leaf, "BottomRail", V3(lw, 0.25, 0.2), CF(cx, 0.185, 0), C.metal, M.metal)
		dp(ctx, leaf, "MeetStile", V3(0.15, lh - 0.6, 0.2), CF(inner, 0.31 + (lh - 0.6) / 2, 0), C.metal, M.metal, DETAIL)
		dp(ctx, leaf, "EdgeStile", V3(0.12, lh - 0.6, 0.2), CF(outer, 0.31 + (lh - 0.6) / 2, 0), C.metal, M.metal, DETAIL)
		slidePivot(ctx, leaf, CF(cx, 0, 0), V3(hx * (lw + 0.1), 0, 0))
	end
	ctx.latch = 1
	ctx.sweep = 4
	return nil, nil
end

-- WC cubicle door (light laminate, raised off the floor, headrail; no reader).
BUILD.cubicle = function(ctx: Ctx)
	ctx.jw, ctx.cw, ctx.ch = 0, ctx.w, ctx.h
	ctx.jd = 0.3
	dp(ctx, ctx.frame, "Headrail", V3(ctx.w, 0.12, 0.3), CF(0, ctx.h - 0.06, 0), C.metalSoft, M.metal)
	local leaf = newLeaf(ctx, "Leaf1")
	local hx = ctx.hx
	local lt = 0.12
	local zc = ctx.s * (ctx.t / 2 - lt / 2)
	local lw = ctx.w - 0.1
	local lh = ctx.h - 0.7
	local color = Kit.pick({ C.sageLight, C.white, C.oakLight, C.blueSoft }, Kit.hash(ctx.def.room))
	local slab = lp(ctx, leaf, hx, zc, "Slab", V3(lw, lh, lt), 0.05 + lw / 2, 0.55 + lh / 2, 0, color, if color == C.oakLight then M.wood else M.smooth)
	markSlab(ctx, slab)
	lp(ctx, leaf, hx, zc, "Indicator", V3(0.3, 0.15, 0.05), 0.05 + lw - 0.35, 3.6, -ctx.s * (lt / 2 + 0.025), C.metal, M.metal, DETAIL)
	lp(ctx, leaf, hx, zc, "Knob", V3(0.12, 0.12, lt + 0.3), 0.05 + lw - 0.35, 3.3, 0, C.metalSoft, M.metal, DETAIL)
	hinges(ctx, leaf, hx, ctx.s * ctx.t / 2, { 1.4, ctx.h - 1.2 }, 0.1, 0.4)
	swingPivot(ctx, leaf, hx, ctx.s * ctx.t / 2, PI / 2)
	ctx.sweep = lw + 0.5
	return nil, nil
end

-- Fridge appliance: carcass behind the front plane (towards +Z = inward), door swings out (-Z).
BUILD.fridge = function(ctx: Ctx)
	local w, h = ctx.w, ctx.h
	local depth = if type(ctx.x.depth) == "number" then ctx.x.depth else 2.4
	ctx.jw, ctx.cw, ctx.ch, ctx.jd = 0, w, h, depth
	ctx.s = -1
	local body = C.white
	dp(ctx, ctx.frame, "SideL", V3(0.12, h, depth), CF(-(w / 2 - 0.06), h / 2, depth / 2), body, M.smooth)
	dp(ctx, ctx.frame, "SideR", V3(0.12, h, depth), CF(w / 2 - 0.06, h / 2, depth / 2), body, M.smooth)
	dp(ctx, ctx.frame, "Top", V3(w - 0.24, 0.12, depth), CF(0, h - 0.06, depth / 2), body, M.smooth)
	dp(ctx, ctx.frame, "Bottom", V3(w - 0.24, 0.4, depth), CF(0, 0.2, depth / 2), body, M.smooth)
	dp(ctx, ctx.frame, "Back", V3(w - 0.24, h - 0.52, 0.12), CF(0, 0.4 + (h - 0.52) / 2, depth - 0.06), body, M.smooth)
	for _, y in { h * 0.38, h * 0.62 } do
		dp(ctx, ctx.frame, "FridgeShelf", V3(w - 0.24, 0.05, depth - 0.3), CF(0, y, depth / 2 + 0.1), C.glass, M.glass, { detail = true, transparency = 0.4 })
	end
	local seed = Kit.hash(ctx.def.id)
	for i = 1, 3 do
		local bx = Kit.range(seed, i, -w / 2 + 0.4, w / 2 - 0.4)
		Kit.cylinder(ctx.frame, ctx.base, "Bottle", "y", 0.9, 0.3, CF(bx, h * 0.38 + 0.47, depth * 0.55), Kit.pick({ C.sage, C.glassDeep, C.terracotta, C.white }, seed + i), M.smooth, DETAIL)
	end
	local leaf = newLeaf(ctx, "Leaf1")
	local hx = ctx.hx
	local lt = 0.25
	local slab = lp(ctx, leaf, hx, -lt / 2, "Slab", V3(w, h, lt), w / 2, h / 2, 0, body, M.smooth)
	markSlab(ctx, slab)
	lp(ctx, leaf, hx, -lt / 2, "Handle", V3(0.12, 2.2, 0.15), w - 0.25, h * 0.55, -(lt / 2 + 0.075), C.metalSoft, M.metal, DETAIL)
	lp(ctx, leaf, hx, -lt / 2, "FreezerLine", V3(w, 0.04, 0.02), w / 2, h * 0.68, -(lt / 2 + 0.01), C.metalSoft, M.smooth, DETAIL)
	swingPivot(ctx, leaf, hx, -lt, math.rad(100))
	ctx.sweep = w + 0.5
	local outP = dp(ctx, ctx.model, "PromptOut", V3(0.3, 0.3, 0.3), CF(-hx * (w / 2 - 0.25), h * 0.55, -(lt + 0.5)), C.white, nil, { detail = true, transparency = 1 })
	local inP = dp(ctx, ctx.model, "PromptIn", V3(0.3, 0.3, 0.3), CF(0, h * 0.5, depth / 2), C.white, nil, { detail = true, transparency = 1 })
	return outP, inP
end

-- Fence gate (louvred, swings inward) or, with def.variant == "barrier", a lifting barrier arm.
BUILD.gate = function(ctx: Ctx)
	if ctx.x.variant == "barrier" then
		local w = ctx.w
		local hxp = -(w / 2 - 0.45)
		ctx.h = 3.4
		ctx.jw, ctx.jd, ctx.cw, ctx.ch = 0.9, 0.9, w, ctx.h
		ctx.latch = -1
		dp(ctx, ctx.frame, "BarrierHousing", V3(0.9, 3.4, 0.9), CF(hxp, 1.7, 0), C.metal, M.metal)
		dp(ctx, ctx.frame, "BarrierRest", V3(0.3, 2.8, 0.3), CF(w / 2 - 0.15, 1.4, 0), C.metal, M.metal)
		local leaf = newLeaf(ctx, "Leaf1")
		local len = w - 1.3
		local boom = dp(ctx, leaf, "Slab", V3(len, 0.22, 0.22), CF(hxp + 0.45 + len / 2, 3.0, 0), C.white, M.smooth)
		markSlab(ctx, boom)
		for k = 1, 3 do
			dp(ctx, leaf, "Stripe", V3(0.6, 0.24, 0.24), CF(hxp + 0.45 + k * len / 4, 3.0, 0), C.terracotta, M.smooth, DETAIL)
		end
		local closed = ctx.base * CF(hxp, 3.0, 0)
		leaf.WorldPivot = closed
		leaf:SetAttribute("ClosedPivot", closed)
		leaf:SetAttribute("OpenPivot", closed * ANG(0, 0, math.rad(85)))
		leaf:SetAttribute("Motion", "lift")
		ctx.sweep = 2
		return nil, nil
	end
	ctx.jd = 0.3
	ctx.t = 0.3
	ctx.jw, ctx.cw, ctx.ch = 0.3, ctx.w - 0.6, ctx.h
	dp(ctx, ctx.frame, "JambL", V3(0.3, ctx.h, 0.3), CF(-(ctx.w - 0.3) / 2, ctx.h / 2, 0), C.metal, M.metal)
	dp(ctx, ctx.frame, "JambR", V3(0.3, ctx.h, 0.3), CF((ctx.w - 0.3) / 2, ctx.h / 2, 0), C.metal, M.metal)
	if isDouble(ctx) then
		gateLeaf(ctx, "Leaf1", -1, ctx.cw / 2 - 0.06)
		gateLeaf(ctx, "Leaf2", 1, ctx.cw / 2 - 0.06)
		ctx.latch = 1
	else
		gateLeaf(ctx, "Leaf1", ctx.hx, ctx.cw - 0.08)
	end
	return nil, nil
end

-- Badge speed gate lane: stainless cabinets on both sides, glass flaps swinging to the staff side.
BUILD.speedgate = function(ctx: Ctx)
	local w = ctx.w
	local cabW, cabH, cabD = 1.5, 3.4, 4
	ctx.jw, ctx.cw, ctx.ch, ctx.jd = 0, w, cabH, cabD
	ctx.s = 1
	-- Kit.wall tells each lane which cabinet a neighbouring lane already builds (shared pedestal)
	local widths = { [-1] = tonumber(ctx.x.cabMinus) or cabW, [1] = tonumber(ctx.x.cabPlus) or cabW }
	local skip = { [-1] = ctx.x.skipMinus == true, [1] = ctx.x.skipPlus == true }
	for _, sgn in { -1, 1 } do
		local cw = widths[sgn]
		local x = sgn * (w / 2 + cw / 2)
		if not skip[sgn] then
			dp(ctx, ctx.frame, "GateCabinet", V3(cw, cabH - 0.1, cabD), CF(x, (cabH - 0.1) / 2, 0), C.concrete, M.metal, { reflectance = 0.05 })
			dp(ctx, ctx.frame, "GateCabinetTop", V3(cw, 0.1, cabD), CF(x, cabH - 0.05, 0), C.metal, M.glass)
		end
		dp(ctx, ctx.frame, "LaneLight", V3(0.5, 0.12, 0.04), CF(sgn * (w / 2 + 0.35), cabH - 0.4, -cabD / 2 - 0.02), C.statusGood, M.neon, DETAIL)
	end
	ctx.cw = w - 0.14 -- flap hinges sit just inside the lane so open flaps rest against the cabinets
	local lw = ctx.cw / 2 - 0.04
	for i, hx in { -1, 1 } do
		local leaf = newLeaf(ctx, "Leaf" .. i)
		local flap = lp(ctx, leaf, hx, 0, "Slab", V3(lw, 2.4, 0.1), 0.04 + lw / 2, 2.1, 0, C.glass, M.glass, GLASS_DOOR)
		markSlab(ctx, flap)
		lp(ctx, leaf, hx, 0, "FlapEdge", V3(0.06, 2.4, 0.14), 0.04 + lw - 0.03, 2.1, 0, C.metalSoft, M.metal, DETAIL)
		swingPivot(ctx, leaf, hx, 0, PI / 2)
	end
	ctx.sweep = cabD / 2 + 1
	ctx.cw = w
	local rx = w / 2 + math.min(widths[1], cabW) / 2
	local function pad(name: string, z: number): Part
		local p = dp(ctx, ctx.model, name, V3(0.8, 0.1, 0.6), CF(rx, cabH + 0.05, z), C.metal, M.metal, DETAIL)
		Kit.part(p, p.CFrame, "ReaderLight", V3(0.5, 0.04, 0.1), CF(0, 0.07, if z > 0 then 0.2 else -0.2), C.statusBad, M.neon, DETAIL)
		return p
	end
	return pad("PromptOut", -cabD / 2 + 0.6), pad("PromptIn", cabD / 2 - 0.6)
end

local function reader(ctx: Ctx, side: string): Part
	local sz = if side == "out" then -1 else 1
	local width = math.clamp(ctx.jw - 0.04, 0.18, 0.3)
	local x = ctx.latch * (ctx.w - ctx.jw) / 2
	local lcf = CF(x, math.min(4.3, ctx.h - 0.8), ctx.fz + sz * (ctx.jd / 2 + 0.05)) * (if sz > 0 then ANG(0, PI, 0) else CFrame.identity)
	local r = dp(ctx, ctx.model, if side == "out" then "PromptOut" else "PromptIn", V3(width, 0.62, 0.1), lcf, C.metal, M.metal, DETAIL)
	Kit.part(r, r.CFrame, "ReaderLight", V3(width * 0.6, 0.06, 0.04), CF(0, 0.2, -0.06), C.statusBad, M.neon, DETAIL)
	return r
end

local function anchorPart(ctx: Ctx, side: string): Part
	local sz = if side == "out" then -1 else 1
	local x = ctx.latch * math.max(ctx.cw / 2 - 0.6, 0)
	return dp(ctx, ctx.model, if side == "out" then "PromptOut" else "PromptIn", V3(0.3, 0.3, 0.3), CF(x, 3.6, ctx.fz + sz * (ctx.jd / 2 + 0.35)), C.white, nil, { detail = true, transparency = 1 })
end

local function doorPrompt(ctx: Ctx, part: BasePart, side: string)
	local hidden = ctx.kind == "flush" or ctx.kind == "bookcase"
	Kit.action(part, "door", DOOR_TEXT[ctx.kind] or "Door", ctx.def.id, {
		actionText = "Open",
		maxDistance = if hidden then 6 elseif ctx.kind == "autoslide" or ctx.kind == "speedgate" then 9 else 8,
		ownerUserId = if hidden and side == "out" then ctx.owner else nil,
		attributes = { Side = side },
	})
end

-- Door model per SPEC §3. Returns nil for kind "opening". Optional extra def fields:
-- y (floor height, default Plan.levelY(level)), thickness (wall, default 0.5), hinge ("right" = +X jamb),
-- swing ("in"|"out"), vision (bool), slide (bookcase: 1 = towards local +X, default -1), depth (fridge),
-- variant ("barrier" for gate), holdOpen (seconds).
function Kit.door(parent: Instance, cf: CFrame, def: DoorDef, owner: number): Model?
	local kind = def.kind
	if kind == "opening" then
		return nil
	end
	local build = BUILD[kind]
	if not build then
		kind = "solid"
		build = BUILD.solid
	end
	local x = def :: any
	local inward = def.inward.Unit
	local up = V3(0, 1, 0)
	local right = up:Cross(inward)
	local y0 = if type(x.y) == "number" then x.y else Plan.levelY(def.level)
	local D = CFrame.fromMatrix(V3(def.x, y0, def.z), right, up, inward)
	local alongVec = if def.axis == "x" then V3(1, 0, 0) else V3(0, 0, 1)
	local model = Instance.new("Model")
	model.Name = "Door_" .. def.id
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local frame = Instance.new("Model")
	frame.Name = "Frame"
	frame.Parent = model
	local hx = if x.hinge == "right" then 1 else -1
	local h = if def.h and def.h > 0 then def.h else (DOOR_H[kind] or 9)
	if kind == "speedgate" then
		h = DOOR_H.speedgate
	end
	local ctx: Ctx = {
		model = model,
		frame = frame,
		base = cf * D,
		def = def,
		x = x,
		kind = kind,
		owner = owner,
		w = def.w,
		h = h,
		t = if type(x.thickness) == "number" then x.thickness else (DOOR_T[kind] or 1.0),
		s = if x.swing == "out" or (x.swing == nil and def.exterior) then -1 else 1,
		hx = hx,
		latch = -hx,
		jw = 0,
		jd = 0.6,
		fz = 0,
		cw = def.w,
		ch = h,
		sweep = 1,
		along = if right:Dot(alongVec) >= 0 then 1 else -1,
	}
	local outP, inP = build(ctx)
	if not outP then
		local readerOut = READER_OUT[kind] == true and def.access ~= "public" and ctx.jw > 0
		outP = if readerOut then reader(ctx, "out") else anchorPart(ctx, "out")
	end
	if not inP then
		inP = if READER_IN[kind] == true and ctx.jw > 0 then reader(ctx, "in") else anchorPart(ctx, "in")
	end
	doorPrompt(ctx, outP :: BasePart, "out")
	doorPrompt(ctx, inP :: BasePart, "in")
	local depth = ctx.t + 2 * ctx.sweep
	dp(ctx, model, "Sensor", V3(ctx.w, math.max(ctx.h, 6), depth), CF(0, math.max(ctx.h, 6) / 2, ctx.fz), C.white, nil, { detail = true, transparency = 1 })
	model:SetAttribute("DoorId", def.id)
	model:SetAttribute("DoorKind", kind)
	model:SetAttribute("AccessClass", def.access)
	model:SetAttribute("RoomId", def.room)
	model:SetAttribute("DoorOwner", owner)
	model:SetAttribute("SecureNormal", cf:VectorToWorldSpace(inward))
	model:SetAttribute("AutoOpen", kind == "autoslide" or kind == "speedgate")
	model:SetAttribute("HoldOpen", if type(x.holdOpen) == "number" then x.holdOpen else 5)
	model:SetAttribute("Hidden", def.hidden == true or kind == "flush" or kind == "bookcase")
	model:SetAttribute("Exterior", def.exterior == true)
	model:SetAttribute("DoorState", "closed")
	Collection:AddTag(model, "CampusDoor")
	model.Parent = parent
	return model
end

---------------------------------------------------------------------------------------------
-- Walls (BuildingLayout.Wall segments)
---------------------------------------------------------------------------------------------
-- Wall thickness per finish (centred on the wall line).
Kit.WALL_T = { solid = 1.0, panel = 1.0, glass = 0.4, barrier = 0.3, fence = 0.5 } :: { [string]: number }

-- Corner closing: for a level's segments (Layout.walls), returns { [Wall] = {e1, e2} } extensions
-- for Kit.wall opts.extend1/extend2. Where two perpendicular segments END at the same point
-- (an L corner), the axis-"x" segment is extended by half the other wall's thickness so the outer
-- corner is closed. T-junctions and free ends get 0.
function Kit.wallExtents(walls: { Wall }): { [Wall]: { number } }
	local out: { [Wall]: { number } } = {}
	local EPS = 0.01
	for _, w in walls do
		out[w] = { 0, 0 }
	end
	for _, w in walls do
		if w.axis ~= "x" then
			continue
		end
		for k, a in { w.a1, w.a2 } do
			-- corner point (a, w.c) in (x, z)
			for _, o in walls do
				if o.axis == "z" and math.abs(o.c - a) < EPS then
					local endsHere = math.abs(o.a1 - w.c) < EPS or math.abs(o.a2 - w.c) < EPS
					local passes = o.a1 < w.c - EPS and o.a2 > w.c + EPS
					if endsHere and not passes then
						-- is there another x segment continuing on the far side? then it is a T, not an L
						local continued = false
						for _, q in walls do
							if q ~= w and q.axis == "x" and math.abs(q.c - w.c) < EPS and ((k == 1 and math.abs(q.a2 - a) < EPS) or (k == 2 and math.abs(q.a1 - a) < EPS)) then
								continued = true
							end
						end
						if not continued then
							out[w][k] = (Kit.WALL_T[o.finish] or 1.0) / 2
						end
					end
				end
			end
		end
	end
	return out
end

export type WallOpts = {
	skirting: string?, -- "oak" (default) | "stone" | "none"
	bay: number?, -- max glass bay width (default 6)
	extend1: number?, -- extend the segment beyond a1 / a2 (corner closing)
	extend2: number?,
}

-- One wall segment from levelY to levelY + seg.height. Openings stay clear; doors are built into
-- doorsParent (once per door id). Returns the segment Model.
function Kit.wall(parent: Instance, cf: CFrame, seg: Wall, levelY: number, owner: number, doorsParent: Instance?, opts: WallOpts?): Model
	local o: WallOpts = opts or {}
	local model = Instance.new("Model")
	model.Name = string.format("Wall_%s%g_%g", seg.axis, seg.c, seg.a1)
	model:SetAttribute("Finish", seg.finish)
	local finish = seg.finish
	local H = seg.height
	local a1 = seg.a1 - (o.extend1 or 0)
	local a2 = seg.a2 + (o.extend2 or 0)
	local t = Kit.WALL_T[finish] or 1.0

	local function box(name: string, b1: number, b2: number, y1: number, y2: number, n1: number, n2: number, color: Color3, mat: Enum.Material?, popts: Opts?, rot: number?): Part?
		if b2 - b1 < 0.01 or y2 - y1 < 0.01 then
			return nil
		end
		local ca, cy, cn = (b1 + b2) / 2, levelY + (y1 + y2) / 2, seg.c + (n1 + n2) / 2
		local size, pos
		if seg.axis == "x" then
			size, pos = V3(b2 - b1, y2 - y1, n2 - n1), CF(ca, cy, cn)
			if rot then
				pos *= ANG(rot, 0, 0)
			end
		else
			size, pos = V3(n2 - n1, y2 - y1, b2 - b1), CF(cn, cy, ca)
			if rot then
				pos *= ANG(0, 0, rot)
			end
		end
		return Kit.part(model, cf, name, size, pos, color, mat, popts)
	end

	-- runs between openings: { b1, b2, leftKind, rightKind } ("" = segment end)
	type Run = { b1: number, b2: number, left: string, right: string }
	local runs: { Run } = {}
	local cursor, leftKind = a1, ""
	for _, op in seg.openings do
		local kind = if op.door then op.door.kind else "opening"
		if op.a1 > cursor + 0.01 then
			table.insert(runs, { b1 = cursor, b2 = op.a1, left = leftKind, right = kind })
		end
		cursor = math.max(cursor, op.a2)
		leftKind = kind
	end
	if a2 > cursor + 0.01 then
		table.insert(runs, { b1 = cursor, b2 = a2, left = leftKind, right = "" })
	end

	local skirtColor = if o.skirting == "stone" then C.stoneDeep elseif finish == "panel" then C.oakDark else C.oak
	local skirtMat = if o.skirting == "stone" then M.stone else M.wood
	local function skirting(b1: number, b2: number)
		if o.skirting == "none" then
			return
		end
		box("Skirting", b1, b2, 0, 0.45, t / 2, t / 2 + 0.06, skirtColor, skirtMat, DETAIL)
		box("Skirting", b1, b2, 0, 0.45, -t / 2 - 0.06, -t / 2, skirtColor, skirtMat, DETAIL)
	end
	local function battens(b1: number, b2: number, y1: number, y2: number)
		local P = Kit.PANEL_PITCH
		for k = math.ceil((b1 + 0.3) / P), math.floor((b2 - 0.3) / P) do
			local a = k * P
			box("Batten", a - 0.1, a + 0.1, y1, y2, t / 2, t / 2 + 0.06, C.oakDark, M.wood, DETAIL)
			box("Batten", a - 0.1, a + 0.1, y1, y2, -t / 2 - 0.06, -t / 2, C.oakDark, M.wood, DETAIL)
		end
	end
	local function portal(op: Layout.Opening, dh: number, color: Color3, mat: Enum.Material)
		box("Reveal", op.a1, op.a1 + 0.08, 0, dh, -t / 2 - 0.05, t / 2 + 0.05, color, mat)
		box("Reveal", op.a2 - 0.08, op.a2, 0, dh, -t / 2 - 0.05, t / 2 + 0.05, color, mat)
		box("Reveal", op.a1 + 0.08, op.a2 - 0.08, dh - 0.08, dh, -t / 2 - 0.05, t / 2 + 0.05, color, mat)
	end
	local function doorFor(op: Layout.Opening): DoorDef?
		local d = op.door
		if d and d.kind ~= "opening" then
			return d :: DoorDef
		end
		return nil
	end
	local function buildDoor(def: DoorDef)
		local target = doorsParent or parent
		if not target:FindFirstChild("Door_" .. def.id) then
			local d = def :: any
			if d.thickness == nil then
				d = table.clone(d)
				d.thickness = t -- frame depth = the thickness of the wall it sits in
			end
			Kit.door(target, cf, d :: DoorDef, owner)
		end
	end

	if finish == "glass" then
		-- one pane per run (mullions overlap it), sill per run, one metal header from the glazing top
		-- to the wall top (only its lower 0.2 shows under the ceiling), glass transoms over openings
		local gt = math.min(12.8, H - 0.2)
		local bayMax = o.bay or 6
		local function post(kind: string): number
			return if kind == "opening" then 0.2 else 0 -- door jambs frame doors; bare openings get a post
		end
		for _, r in runs do
			local len = r.b2 - r.b1
			if len <= 0.7 then
				box("Post", r.b1, r.b2, 0, gt, -0.2, 0.2, C.metal, M.metal)
				continue
			end
			local p1, p2 = post(r.left), post(r.right)
			if p1 > 0 then
				box("Post", r.b1, r.b1 + p1, 0, gt, -0.2, 0.2, C.metal, M.metal)
			end
			if p2 > 0 then
				box("Post", r.b2 - p2, r.b2, 0, gt, -0.2, 0.2, C.metal, M.metal)
			end
			local g1, g2 = r.b1 + p1, r.b2 - p2
			box("SillRail", g1, g2, 0, 0.35, -0.2, 0.2, C.metal, M.metal)
			box("Glass", g1, g2, 0.35, gt, -0.06, 0.06, C.glass, M.glass, GLASS)
			if not Kit.LEAN then
				local bays = math.max(1, math.ceil((g2 - g1) / bayMax))
				for i = 1, bays - 1 do
					local m = g1 + i * (g2 - g1) / bays
					box("Mullion", m - 0.075, m + 0.075, 0.35, gt, -0.2, 0.2, C.metal, M.metal)
				end
			end
		end
		box("Header", a1, a2, gt, H, -0.2, 0.2, C.metal, M.metal)
		for _, op in seg.openings do
			local def = doorFor(op)
			local dh = if op.door and op.door.h then op.door.h else 9
			if dh + 0.4 < gt then
				box("TransomRail", op.a1, op.a2, dh, dh + 0.2, -0.2, 0.2, C.metal, M.metal)
				box("Transom", op.a1, op.a2, dh + 0.2, gt, -0.06, 0.06, C.glass, M.glass, GLASS)
			end
			if def then
				buildDoor(def)
			end
		end
	elseif finish == "fence" then
		for _, r in runs do
			local posts = math.max(1, math.ceil((r.b2 - r.b1) / 6))
			for i = 0, posts do
				local a = r.b1 + 0.15 + i * (r.b2 - r.b1 - 0.3) / posts
				box("Post", a - 0.15, a + 0.15, 0, H - 0.15, 0.05, 0.25, C.metal, M.metal)
			end
			box("BottomRail", r.b1, r.b2, 0, 0.25, -0.22, 0.02, C.metal, M.metal)
			box("Cap", r.b1, r.b2, H - 0.15, H, -0.25, 0.25, C.metal, M.metal)
			local slats = math.max(1, math.floor((H - 0.55) / 0.55))
			local pitch = (H - 0.55) / slats
			for i = 1, slats do
				local y = 0.3 + (i - 0.5) * pitch
				box("Louvre", r.b1, r.b2, y - 0.225, y + 0.225, -0.13, -0.07, C.metalSoft, M.metal, nil, math.rad(35))
			end
		end
		for _, op in seg.openings do
			local def = doorFor(op)
			if def then
				local g = table.clone(def) :: any
				g.kind = "gate"
				g.h = H
				buildDoor(g :: DoorDef)
			end
		end
	elseif finish == "barrier" then
		-- 3.6-high glass badge line; speed-gate cabinets occupy 1.5 studs beside each lane
		local function trim(kind: string): number
			return if kind == "speedgate" then 1.5 else 0
		end
		local top = H - 0.2
		for _, r in runs do
			local b1, b2 = r.b1 + trim(r.left), r.b2 - trim(r.right)
			if b2 - b1 < 0.05 then
				continue
			end
			if b2 - b1 <= 0.6 then
				box("Post", b1, b2, 0, top, -0.15, 0.15, C.metal, M.metal)
			else
				local bays = math.max(1, math.ceil((b2 - b1 - 0.2) / 4.5))
				local bl = (b2 - b1 - 0.2 * (bays + 1)) / bays
				for i = 0, bays do
					local p = b1 + i * (bl + 0.2)
					box("Post", p, p + 0.2, 0, top, -0.15, 0.15, C.metal, M.metal)
					if i < bays then
						box("BarrierShoe", p + 0.2, p + 0.2 + bl, 0, 0.15, -0.1, 0.1, C.metal, M.metal)
						box("BarrierGlass", p + 0.2, p + 0.2 + bl, 0.15, top, -0.06, 0.06, C.glass, M.glass, GLASS)
					end
				end
			end
			box("TopRail", b1, b2, top, H, -0.15, 0.15, C.oak, M.wood)
		end
		local list = seg.openings
		for i, op in list do
			local def = doorFor(op)
			if def and def.kind == "speedgate" then
				-- neighbouring lanes closer than two cabinets share ONE pedestal (built by the lower-a lane)
				local d = table.clone(def :: any)
				local prv, nxt = list[i - 1], list[i + 1]
				local w1, w2, skip1 = 1.5, 1.5, false
				if prv and prv.door and prv.door.kind == "speedgate" and op.a1 - prv.a2 < 2.99 then
					w1, skip1 = math.max(op.a1 - prv.a2, 0.3), true
				end
				if nxt and nxt.door and nxt.door.kind == "speedgate" and nxt.a1 - op.a2 < 2.99 then
					w2 = math.max(nxt.a1 - op.a2, 0.3)
				end
				local alongVec = if seg.axis == "x" then V3(1, 0, 0) else V3(0, 0, 1)
				local plusIsA2 = V3(0, 1, 0):Cross(def.inward.Unit):Dot(alongVec) >= 0
				d.cabPlus, d.skipPlus = if plusIsA2 then w2 else w1, if plusIsA2 then false else skip1
				d.cabMinus, d.skipMinus = if plusIsA2 then w1 else w2, if plusIsA2 then skip1 else false
				buildDoor(d :: DoorDef)
			elseif def then
				buildDoor(def)
			end
		end
	else
		-- solid (plaster) or panel (timber panelling) walls
		local panel = finish == "panel"
		local core = if panel then C.oakLight else C.interior
		local coreMat = if panel then M.wood else M.plaster
		local battenTop = math.min(Kit.CEILING, H)
		for _, r in runs do
			box("Wall", r.b1, r.b2, 0, H, -t / 2, t / 2, core, coreMat)
			skirting(r.b1, r.b2)
			if panel and not Kit.LEAN then
				battens(r.b1, r.b2, 0.45, battenTop)
			end
		end
		for _, op in seg.openings do
			local def = doorFor(op)
			local dh = if op.door and op.door.h then op.door.h else 9
			if dh < H then
				box("Lintel", op.a1, op.a2, dh, H, -t / 2, t / 2, core, coreMat)
				if panel and dh < battenTop and not Kit.LEAN then
					battens(op.a1, op.a2, dh, battenTop)
				end
			end
			if def then
				buildDoor(def)
			else
				portal(op, math.min(dh, H), if panel then C.oakDark else C.oak, M.wood)
			end
		end
	end
	model.Parent = parent
	return model
end

-- Skirting strip on one face of a wall line: side = +1 on the +c face, -1 on the -c face.
-- thickness = the wall's thickness (default 1.0, solid interior wall).
function Kit.skirting(parent: Instance, cf: CFrame, axis: string, c: number, a1: number, a2: number, side: number, levelY: number, color: Color3?, thickness: number?): Part
	local n = c + side * ((thickness or 1.0) / 2 + 0.03)
	local col = color or C.oak
	if axis == "x" then
		return Kit.part(parent, cf, "Skirting", V3(a2 - a1, 0.45, 0.06), CF((a1 + a2) / 2, levelY + 0.225, n), col, M.wood, DETAIL)
	end
	return Kit.part(parent, cf, "Skirting", V3(0.06, 0.45, a2 - a1), CF(n, levelY + 0.225, (a1 + a2) / 2), col, M.wood, DETAIL)
end

---------------------------------------------------------------------------------------------
-- Floors and ceilings
---------------------------------------------------------------------------------------------
local FINISHES: { [string]: { color: Color3, mat: Enum.Material } } = {
	oak = { color = C.oak, mat = M.planks },
	oakLight = { color = C.oakLight, mat = M.planks },
	oakDark = { color = C.oakDark, mat = M.planks },
	deck = { color = C.oakDark, mat = M.planks },
	carpet = { color = C.carpet, mat = M.carpet },
	carpetWarm = { color = C.carpetWarm, mat = M.carpet },
	carpetBlue = { color = C.fabricBlue, mat = M.carpet },
	stone = { color = C.stone, mat = M.stone },
	tile = { color = C.white, mat = M.tile },
	rubber = { color = C.fabricCharcoal, mat = M.rubber },
	concrete = { color = C.concrete, mat = M.concrete },
	terrazzo = { color = C.plasterShade, mat = M.marble },
	marble = { color = C.stone, mat = M.marble },
	slate = { color = C.metalSoft, mat = M.slate },
}
Kit.FLOOR_FINISHES = FINISHES

export type SurfaceOpts = {
	inset: number?, -- shrink the rect on every side (default 0: finishes run to the wall lines, hidden inside walls)
	maxLights: number?, -- ceiling: max SurfaceLights (default 1; at most one per 400 sq studs; 0 = none)
	height: number?, -- ceiling: underside above levelY (default 13)
	name: string?,
}

-- Floor finish layer 0.1 thick on the slab (top at levelY + 0.1). Returns the part.
function Kit.floor(parent: Instance, cf: CFrame, rect: Rect, levelY: number, finish: string?, opts: SurfaceOpts?): Part?
	local o: SurfaceOpts = opts or {}
	local inset = o.inset or 0
	local x1, x2, z1, z2 = rect.x1 + inset, rect.x2 - inset, rect.z1 + inset, rect.z2 - inset
	if x2 - x1 < 0.1 or z2 - z1 < 0.1 then
		return nil
	end
	local f = FINISHES[finish or "oak"] or FINISHES.oak
	return Kit.part(parent, cf, o.name or "Floor", V3(x2 - x1, Kit.FINISH, z2 - z1), CF((x1 + x2) / 2, levelY + Kit.FINISH / 2, (z1 + z2) / 2), f.color, f.mat)
end

-- Suspended ceiling (underside levelY + 13, 0.3 thick): "acoustic" | "timber" | "plaster", with
-- integrated Neon light strips. Returns (parts carrying a SurfaceLight, all strip parts).
function Kit.ceiling(parent: Instance, cf: CFrame, rect: Rect, levelY: number, style: string?, mood: (string | Color3)?, opts: SurfaceOpts?): ({ Part }, { Part })
	local o: SurfaceOpts = opts or {}
	local inset = o.inset or 0
	local x1, x2, z1, z2 = rect.x1 + inset, rect.x2 - inset, rect.z1 + inset, rect.z2 - inset
	local W, D = x2 - x1, z2 - z1
	if W < 1 or D < 1 then
		return {}, {}
	end
	local yb = levelY + (o.height or Kit.CEILING)
	local cx, cz = (x1 + x2) / 2, (z1 + z2) / 2
	local alongX = W >= D
	local L, S = if alongX then W else D, if alongX then D else W
	-- helper: building-local CFrame from (long, short) offsets relative to the centre
	local function at(l: number, s: number, y: number): CFrame
		return if alongX then CF(cx + l, y, cz + s) else CF(cx + s, y, cz + l)
	end
	local function size(l: number, y: number, s: number): Vector3
		return if alongX then V3(l, y, s) else V3(s, y, l)
	end
	local st = style or "acoustic"
	local slatPitch = 1.5
	if st == "timber" then
		Kit.part(parent, cf, "CeilingBacking", size(L, 0.05, S), at(0, 0, yb + 0.275), C.fabricCharcoal, M.fabric)
		local n = math.max(1, math.floor(S / slatPitch))
		for i = 0, n - 1 do
			local s = -S / 2 + (i + 0.5) * (S / n)
			Kit.part(parent, cf, "CeilingSlat", size(L, 0.25, math.min(0.9, S / n - 0.3)), at(0, s, yb + 0.125), C.oakLight, M.wood)
		end
		slatPitch = S / n
	elseif st == "plaster" then
		Kit.part(parent, cf, o.name or "Ceiling", size(L, 0.3, S), at(0, 0, yb + 0.15), C.white, M.plaster)
	else
		local nl = math.max(1, math.ceil(L / 16))
		local ns = math.max(1, math.ceil(S / 16))
		local j = 0.12
		local pl, ps = (L - (nl - 1) * j) / nl, (S - (ns - 1) * j) / ns
		for i = 0, nl - 1 do
			for k = 0, ns - 1 do
				Kit.part(parent, cf, "CeilingPanel", size(pl, 0.3, ps), at(-L / 2 + pl / 2 + i * (pl + j), -S / 2 + ps / 2 + k * (ps + j), yb + 0.15), C.white, M.plaster)
			end
		end
	end
	-- light strips along the long axis
	local glow = if typeof(mood) == "Color3" then mood elseif type(mood) == "string" and (A.mood :: any)[mood] then (A.mood :: any)[mood].color else C.lightNeutral
	local rows = math.clamp(math.floor(S / 10 + 0.5), 1, 4)
	local stripLen = math.max(L - 3, 1)
	local segs = 1
	local segLen = stripLen
	local strips: { Part } = {}
	for r = 1, rows do
		local s = -S / 2 + (r - 0.5) * S / rows
		local y = yb - 0.03
		if st == "timber" then
			-- sit in the nearest gap between two slats, flush with the slat underside
			local gi = math.clamp(math.floor((s + S / 2) / slatPitch + 0.5), 1, math.max(1, math.floor(S / slatPitch) - 1))
			s = -S / 2 + gi * slatPitch
			y = yb + 0.03
		end
		for k = 0, segs - 1 do
			local l = -stripLen / 2 + segLen / 2 + k * (segLen + 1)
			table.insert(strips, Kit.part(parent, cf, "LightStrip", size(segLen, 0.06, 0.25), at(l, s, y), glow, M.neon, DETAIL))
		end
	end
	local maxL = o.maxLights or 1
	local count = if maxL <= 0 then 0 else math.min(math.clamp(math.floor(W * D / 400), 1, maxL), #strips)
	local lit: { Part } = {}
	for i = 1, count do
		local idx = math.clamp(math.floor((i - 0.5) * #strips / count) + 1, 1, #strips)
		local p = strips[idx]
		Kit.light(p, "surface", mood or "neutral", nil, nil, Enum.NormalId.Bottom)
		table.insert(lit, p)
	end
	return lit, strips
end

---------------------------------------------------------------------------------------------
-- Cameras and access volumes (SPEC §6)
---------------------------------------------------------------------------------------------
-- Security camera at building-local `position` aiming at `target`; bracket rises 1 stud to the
-- ceiling/wall mount. ViewCFrame = the body CFrame pushed 1 stud forward (world space).
function Kit.camera(parent: Instance, cf: CFrame, id: string, name: string, position: Vector3, target: Vector3, level: number, roomId: string, private: boolean): Part
	local dir = target - position
	local up = if dir.Magnitude > 1e-3 and math.abs(dir.Unit.Y) > 0.98 then V3(0, 0, 1) else V3(0, 1, 0)
	local look = if dir.Magnitude > 1e-3 then CFrame.lookAt(position, target, up) else CF(position)
	local body = Kit.part(parent, cf, "CampusCamera_" .. id, V3(0.6, 0.6, 1.2), look, C.white, M.smooth, DETAIL)
	Kit.cylinder(body, cf, "Lens", "z", 0.25, 0.42, look * CF(0, 0, -0.68), C.screen, M.glass, DETAIL)
	Kit.part(body, cf, "Bracket", V3(0.16, 0.75, 0.16), CF(position) * CF(0, 0.6, 0), C.metalSoft, M.metal, DETAIL)
	Kit.part(body, cf, "Mount", V3(0.6, 0.08, 0.6), CF(position) * CF(0, 0.96, 0), C.metalSoft, M.metal, DETAIL)
	body:SetAttribute("CameraId", id)
	body:SetAttribute("CameraName", name)
	body:SetAttribute("ViewCFrame", cf * look * CF(0, 0, -1))
	body:SetAttribute("Level", level)
	body:SetAttribute("RoomId", roomId)
	body:SetAttribute("Private", private)
	return body
end

-- Invisible PathfindingModifier volume over a restricted room (nil for public/staff rooms).
function Kit.accessVolume(parent: Instance, cf: CFrame, room: Room): Part?
	if room.access == "public" or room.access == "staff" then
		return nil
	end
	local y = Plan.levelY(room.level)
	local p = Kit.part(parent, cf, "Access_" .. room.id, V3(room.x2 - room.x1, 14, room.z2 - room.z1), CF((room.x1 + room.x2) / 2, y + 7, (room.z1 + room.z2) / 2), C.white, nil, { detail = true, transparency = 1 })
	-- Pathfinding ignores modifier parts whose CanQuery AND CanTouch are both false (reported engine
	-- behaviour, devforum 3504949). Keep CanQuery off (no raycast/prompt interference), CanTouch on.
	p.CanTouch = true
	local mod = Instance.new("PathfindingModifier")
	mod.Label = room.access
	mod.Parent = p
	p:SetAttribute("AccessClass", room.access)
	p:SetAttribute("RoomId", room.id)
	return p
end

return Kit
