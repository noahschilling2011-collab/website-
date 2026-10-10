--!strict
-- PropFxController: client-side animation of every PropFx prop (contract: design/PROPFX_CONTRACT.md).
--   * Registry from CollectionService tag "PropFx" (+ legacy "ClusterFan"); the tag signals also cover
--     streaming, so a prop that streams in registers again and captures its home pose again.
--   * The server only writes FxState / FxUntil (or a linked station's OccupiedBy); everything that moves,
--     glows, steams or burns here is local to this client.
--   * LOD from the camera, rebuilt every 0.5 s: < 60 studs every frame, 60–120 studs at 10 Hz, beyond
--     (or > 24 studs above/below) the prop is put back to its home pose once and sleeps.
--   * CFrames of one frame go out in a single workspace:BulkMoveTo(parts, cframes, FireCFrameChanged).
--   * staffops: rack faults (CompanyOps faults mirrored by StaffEvents onto the GPU blade + rack door:
--     FxState "broken", FaultSlot, FaultUntil): the blade blinks red, the door LEDs blink red with a
--     "R3 · FAULT" banner, and a local beacon with a label "Rack R3 · fault · capacity −1" and the
--     economy's repair estimate sits on the rack. All client-only, active-set LOD like every prop.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ops = require(ReplicatedStorage.Shared.CompanyOps)

local Controller = {}
local TAG = "PropFx"
local LEGACY_FAN = "ClusterFan"
local NEAR, FAR, VERTICAL = 60, 120, 24
local MID_STEP = 0.1 -- 10 Hz between NEAR and FAR
local STATE_STEP = 0.1 -- state attributes are re-read at most 10x per second per prop
local SCAN_STEP = 0.5
local HINGE_TIME, SLIDE_TIME = 0.45, 0.8
local PAPER_EVERY = 1.6
local BREATH_PERIOD, BREATH_DEPTH = 3.2, 0.35
local BROKEN_TEXT = "FAULT · IT NOTIFIED"
local FAULT_RED = Color3.fromRGB(235, 52, 44)
local FAULT_DIM = Color3.fromRGB(96, 20, 18)
local FAULT_BLINK = 2 -- Hz
local MOTION = { spin = true, belt = true, slider = true, hinge = true, arm = true }
local AXES: { [string]: Vector3 } = { x = Vector3.xAxis, y = Vector3.yAxis, z = Vector3.zAxis }
local DEFAULT_RATE: { [string]: number } = { spin = 6, belt = 3, blink = 2, flow = 0.8, slider = 0, ticker = 60 }

type Moving = { part: BasePart, home: CFrame, rel: CFrame, link: number }
type Look = { part: BasePart, color: Color3, material: Enum.Material, transparency: number, show: number? }
export type Prop = {
	root: Instance,
	kinds: { [string]: boolean },
	office: Instance?,
	pivot: CFrame, -- home pivot (Model root) / home CFrame of the root part (Part root)
	position: Vector3,
	moving: { Moving },
	glow: { Look },
	show: { Look },
	breathe: Look?,
	emitters: { ParticleEmitter },
	fires: { Fire },
	gui: SurfaceGui?,
	ticker: TextLabel?,
	leds: { Frame },
	axis: Vector3,
	rate: number,
	travel: number,
	hinge: Vector3,
	idle: string,
	color: Color3,
	text: string?,
	station: string?,
	stationModel: Instance?,
	gate: string?,
	meeting: string?,
	joints: { CFrame }?,
	outPart: BasePart?,
	-- runtime
	angle: number,
	phase: number,
	alpha: number,
	working: boolean,
	broken: boolean,
	effects: boolean?, -- last applied on/off state of emitters/fires/show parts
	glowOn: boolean?,
	overlay: Frame?,
	sheet: BasePart?,
	sheetStart: number,
	nextSheet: number,
	active: boolean,
	near: boolean,
	nextAt: number,
	stateAt: number,
	lastAt: number,
	ledAt: number,
	moved: boolean,
	fault: any?, -- staffops: client-only rack fault effects while broken (beacon, label, banner, colours)
}

local props: { [Instance]: Prop } = {}
local activeList: { Prop } = {}
local stationMaps: { [Instance]: { map: { [string]: Instance }, builtAt: number } } = setmetatable({}, { __mode = "k" }) :: any
local scanClock = 0
local sheetsFolder: Folder? = nil

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function num(v: any, default: number): number
	return if typeof(v) == "number" and v == v then v else default
end

local function lookOf(p: BasePart, show: number?): Look
	return { part = p, color = p.Color, material = p.Material, transparency = p.Transparency, show = show }
end

-- WorkstationId -> station model for one office (one descendants pass, rebuilt at most every 10 s while
-- a lookup fails: stations may still be streaming in).
local function stationModel(office: Instance, id: string, now: number): Instance?
	local entry = stationMaps[office]
	if entry and entry.map[id] and entry.map[id].Parent then
		return entry.map[id]
	end
	if entry and now - entry.builtAt < 10 then
		return nil
	end
	local map: { [string]: Instance } = {}
	for _, d in office:GetDescendants() do
		if d:IsA("Model") then
			local wid = d:GetAttribute("WorkstationId")
			if typeof(wid) == "string" then
				map[wid] = d
			end
		end
	end
	stationMaps[office] = { map = map, builtAt = now }
	return map[id]
end

local function liftMoving(office: Instance): boolean
	local lift = office:FindFirstChild("Lift")
	local cabin = if lift then lift:FindFirstChild("LiftCabin") else nil
	return cabin ~= nil and cabin:GetAttribute("LiftState") == "MOVING"
end

-- Working rule of the contract: broken > FxUntil / FxState / station occupant / gate > idle.
function Controller.state(p: Prop, now: number): (boolean, boolean)
	local root = p.root
	local state = root:GetAttribute("FxState")
	if state == "broken" then
		return false, true
	end
	local untilTime = root:GetAttribute("FxUntil")
	local working = (typeof(untilTime) == "number" and untilTime > now) or state == "working"
	if not working and p.station then
		if not (p.stationModel and p.stationModel.Parent) and p.office then
			p.stationModel = stationModel(p.office, p.station, now)
		end
		working = p.stationModel ~= nil and p.stationModel:GetAttribute("OccupiedBy") ~= nil
	end
	if not working and p.gate and p.office then
		local office = p.office
		if p.gate == "Training" then
			working = office:GetAttribute("Training") == true
		elseif p.gate == "Hour" then
			local h = office:GetAttribute("CompanyHour")
			working = typeof(h) == "number" and h >= 8 and h < 18
		elseif p.gate == "Lift" then
			working = liftMoving(office)
		elseif p.gate == "Meeting" then
			local untilMeeting = office:GetAttribute("MeetingUntil")
			working = office:GetAttribute("MeetingRoom") == p.meeting and typeof(untilMeeting) == "number" and untilMeeting > now
		end
	end
	if working and p.breathe then
		working = p.breathe.part:GetAttribute("Lit") == true
	end
	return working, false
end

-- Home CFrame of a part: the pose captured now, unless a legacy home attribute (FanHome / BeltHome /
-- SpinBase, world space from build time) sits on the same spot - then the part may have been caught
-- mid-animation by an older server and the legacy home is the true rest pose.
local function homeOf(part: BasePart): CFrame
	for _, name in { "FanHome", "BeltHome", "SpinBase" } do
		local legacy = part:GetAttribute(name)
		if typeof(legacy) == "CFrame" and (legacy.Position - part.Position).Magnitude < 0.6 then
			return legacy
		end
	end
	return part.CFrame
end

local function parseKinds(root: Instance): { [string]: boolean }
	local kinds: { [string]: boolean } = {}
	local fx = root:GetAttribute("Fx")
	if typeof(fx) == "string" then
		for kind in string.gmatch(fx, "[%a]+") do
			kinds[kind] = true
		end
	elseif CollectionService:HasTag(root, LEGACY_FAN) then
		kinds.spin = true
	end
	return kinds
end

function Controller.register(root: Instance): Prop?
	if props[root] then
		return props[root]
	end
	if not (root:IsA("BasePart") or root:IsA("Model")) then
		return nil
	end
	local kinds = parseKinds(root)
	if next(kinds) == nil then
		return nil
	end
	local legacyFan = root:GetAttribute("Fx") == nil and CollectionService:HasTag(root, LEGACY_FAN)
	local motion = false
	for kind in kinds do
		if MOTION[kind] then
			motion = true
		end
	end
	local first = next(kinds) :: string
	local axisName = root:GetAttribute("FxAxis")
	local pivot: CFrame
	if root:IsA("BasePart") then
		pivot = homeOf(root)
	else
		pivot = (root :: Model):GetPivot()
	end
	local hinge = root:GetAttribute("FxHinge")
	local color = root:GetAttribute("FxColor")
	local text = root:GetAttribute("FxText")
	local station = root:GetAttribute("FxStation")
	local gate = root:GetAttribute("FxGate")
	local meeting = root:GetAttribute("FxMeeting")
	local idle = root:GetAttribute("FxIdle")
	local p: Prop = {
		root = root,
		kinds = kinds,
		office = root:FindFirstAncestor("Office"),
		pivot = pivot,
		position = pivot.Position,
		moving = {},
		glow = {},
		show = {},
		breathe = nil,
		emitters = {},
		fires = {},
		gui = nil,
		ticker = nil,
		leds = {},
		axis = AXES[if typeof(axisName) == "string" then axisName else (if legacyFan then "z" else "y")] or Vector3.yAxis,
		rate = num(root:GetAttribute("FxRate"), if legacyFan then 8 else (DEFAULT_RATE[first] or 1)),
		travel = num(root:GetAttribute("FxTravel"), 0),
		hinge = if typeof(hinge) == "Vector3" then hinge else Vector3.zero,
		idle = if typeof(idle) == "string" then idle else "off",
		color = if typeof(color) == "Color3" then color else Color3.fromRGB(120, 220, 140),
		text = if typeof(text) == "string" then text else nil,
		station = if typeof(station) == "string" and station ~= "" then station else nil,
		stationModel = nil,
		gate = if typeof(gate) == "string" then gate elseif legacyFan then "Training" else nil,
		meeting = if typeof(meeting) == "string" then meeting else nil,
		joints = nil,
		outPart = nil,
		angle = 0,
		phase = 0,
		alpha = 0,
		working = false,
		broken = false,
		effects = nil,
		glowOn = nil,
		overlay = nil,
		sheet = nil,
		sheetStart = 0,
		nextSheet = 0,
		active = false,
		near = false,
		nextAt = 0,
		stateAt = 0,
		lastAt = 0,
		ledAt = 0,
		moved = false,
		fault = nil,
	}
	-- parts: the root part itself plus descendants
	local parts: { BasePart } = {}
	if root:IsA("BasePart") then
		table.insert(parts, root)
	end
	local flagged = false
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			if d:GetAttribute("FxMove") == true then
				flagged = true
			end
		elseif d:IsA("ParticleEmitter") then
			table.insert(p.emitters, d)
		elseif d:IsA("Fire") then
			table.insert(p.fires, d)
		elseif d:IsA("SurfaceGui") and not p.gui then
			p.gui = d
		elseif d:IsA("Frame") and string.match(d.Name, "^LED%d+$") then
			table.insert(p.leds, d)
		end
	end
	if root:IsA("Model") and kinds.arm then
		local joints: { CFrame } = {}
		for k = 1, 3 do
			local j = root:GetAttribute("FxJoint" .. k)
			joints[k] = if typeof(j) == "CFrame" then j else CFrame.identity
		end
		p.joints = joints
	end
	for _, part in parts do
		local isRoot = (part :: any) == root
		if motion then
			local moves
			if root:IsA("BasePart") then
				moves = true -- a Part root moves rigidly with its children
			elseif kinds.arm then
				moves = typeof(part:GetAttribute("FxLink")) == "number"
			else
				moves = (not flagged) or part:GetAttribute("FxMove") == true
			end
			if moves then
				local home = if isRoot then pivot else part.CFrame
				table.insert(p.moving, { part = part, home = home, rel = pivot:Inverse() * home, link = num(part:GetAttribute("FxLink"), 0) })
			end
		end
		if part:GetAttribute("FxGlow") == true then
			table.insert(p.glow, lookOf(part))
		end
		local show = part:GetAttribute("FxShow")
		if typeof(show) == "number" then
			table.insert(p.show, lookOf(part, show))
		end
		if part:GetAttribute("FxOut") == true then
			p.outPart = part
		end
	end
	if kinds.blink and #p.glow == 0 and root:IsA("BasePart") then
		table.insert(p.glow, lookOf(root))
	end
	if kinds.flow and #p.show == 0 and root:IsA("BasePart") and p.travel == 0 then
		table.insert(p.show, lookOf(root, 0.5))
	end
	if kinds.breathe and root:IsA("BasePart") then
		p.breathe = lookOf(root)
	end
	if kinds.ticker and p.gui then
		local label = p.gui:FindFirstChildWhichIsA("TextLabel")
		p.ticker = label
	end
	if not p.outPart then
		if root:IsA("BasePart") then
			p.outPart = root
		else
			p.outPart = (root :: Model).PrimaryPart or root:FindFirstChildWhichIsA("BasePart", true)
		end
	end
	props[root] = p
	return p
end

local function destroySheet(p: Prop)
	if p.sheet then
		p.sheet:Destroy()
		p.sheet = nil
	end
end

local function setOverlay(p: Prop, text: string?, broken: boolean)
	if p.overlay then
		p.overlay:Destroy()
		p.overlay = nil
	end
	if not text or not p.gui then
		return
	end
	local frame = Instance.new("Frame")
	frame.Name = "FxOverlay"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = if broken then Color3.fromRGB(70, 18, 18) else Color3.fromRGB(16, 40, 24)
	frame.BackgroundTransparency = 0.15
	frame.ZIndex = 10
	local label = Instance.new("TextLabel")
	label.Name = "FxText"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.BuilderSansBold
	label.TextColor3 = if broken then Color3.fromRGB(255, 120, 110) else Color3.fromRGB(150, 240, 170)
	label.ZIndex = 11
	label.Parent = frame
	frame.Parent = p.gui
	p.overlay = frame
end

-- Property effects that follow the on/off state (emitters, fires, show parts, screen overlay).
local function applyEffects(p: Prop, on: boolean)
	if p.effects == on then
		return
	end
	p.effects = on
	for _, e in p.emitters do
		if e.Parent then
			e.Enabled = on
		end
	end
	for _, f in p.fires do
		if f.Parent then
			f.Enabled = on
		end
	end
	if not on then
		for _, look in p.show do
			if look.part.Parent then
				look.part.Transparency = look.transparency
			end
		end
	end
	if p.kinds.screen then
		if p.broken then
			setOverlay(p, BROKEN_TEXT, true)
		elseif on and p.text then
			setOverlay(p, p.text, false)
		else
			setOverlay(p, nil, false)
		end
	end
end

local function setGlow(p: Prop, on: boolean)
	if p.glowOn == on then
		return
	end
	p.glowOn = on
	for _, look in p.glow do
		local part = look.part
		if part.Parent then
			part.Color = if on then p.color else look.color
			part.Material = if on then Enum.Material.Neon else look.material
		end
	end
end

local function localFolder(): Folder
	local folder = sheetsFolder
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = "PropFxLocal"
		f.Parent = workspace
		sheetsFolder = f
		folder = f
	end
	return folder :: Folder
end

-- Rack fault label text: "Rack R3 · fault · capacity −1" and the economy's repair estimate (FaultUntil).
function Controller.faultText(slot: number?, untilTime: number?, now: number): (string, string)
	local units = Ops.FAULT.units
	local title = string.format("Rack R%s · fault · capacity −%d", if slot then tostring(slot) else "?", units)
	local sub
	if typeof(untilTime) == "number" then
		local left = math.max(0, math.floor(untilTime - now + 0.5))
		if left >= 90 then
			sub = string.format("Repair · back in ~%d min", math.floor(left / 60 + 0.5))
		elseif left > 0 then
			sub = string.format("Repair · back in ~%d s", left)
		else
			sub = "Repair · finishing"
		end
	else
		sub = "IT notified"
	end
	return title, sub
end

-- Beacon + label on top of a broken GPU blade's rack (blade front face = -Z, rack body behind it).
local function faultBeacon(blade: BasePart): (Part, BillboardGui, TextLabel, TextLabel, PointLight)
	local beacon = Instance.new("Part")
	beacon.Name = "RackFaultBeacon"
	beacon.Shape = Enum.PartType.Ball
	beacon.Size = Vector3.new(0.5, 0.5, 0.5)
	beacon.Anchored = true
	beacon.CanCollide = false
	beacon.CanTouch = false
	beacon.CanQuery = false
	beacon.CastShadow = false
	beacon.Material = Enum.Material.Neon
	beacon.Color = FAULT_RED
	beacon.CFrame = blade.CFrame * CFrame.new(0, blade.Size.Y / 2 + 1.75, 1.94)
	local light = Instance.new("PointLight")
	light.Color = FAULT_RED
	light.Range = 10
	light.Brightness = 2
	light.Shadows = false
	light.Parent = beacon
	local gui = Instance.new("BillboardGui")
	gui.Name = "RackFaultLabel"
	gui.Size = UDim2.fromOffset(240, 52)
	gui.StudsOffset = Vector3.new(0, 1.4, 0)
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	local frame = Instance.new("Frame")
	frame.Name = "Card"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(40, 12, 12)
	frame.BackgroundTransparency = 0.12
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = FAULT_RED
	stroke.Thickness = 2
	stroke.Parent = frame
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 10, 0, 5)
	title.Size = UDim2.new(1, -20, 0, 22)
	title.Font = Enum.Font.BuilderSansBold
	title.TextSize = 16
	title.TextColor3 = Color3.fromRGB(255, 214, 208)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Parent = frame
	local sub = Instance.new("TextLabel")
	sub.Name = "Status"
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.new(0, 10, 0, 27)
	sub.Size = UDim2.new(1, -20, 0, 20)
	sub.Font = Enum.Font.BuilderSans
	sub.TextSize = 14
	sub.TextColor3 = Color3.fromRGB(255, 160, 150)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	sub.Parent = frame
	gui.Parent = beacon
	beacon.Parent = localFolder()
	return beacon, gui, title, sub, light
end
Controller.faultBeacon = faultBeacon

-- "R3 · FAULT" banner across the top of the rack door's surface (above the LED column).
local function faultBanner(gui: SurfaceGui, slot: number?): Frame
	local banner = Instance.new("Frame")
	banner.Name = "FxFault"
	banner.Size = UDim2.new(1, 0, 0, 78)
	banner.BackgroundColor3 = Color3.fromRGB(70, 16, 16)
	banner.BackgroundTransparency = 0.05
	banner.BorderSizePixel = 0
	banner.ZIndex = 10
	local label = Instance.new("TextLabel")
	label.Name = "FxText"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = string.format("R%s · FAULT", if slot then tostring(slot) else "?")
	label.TextScaled = true
	label.TextWrapped = false
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = label
	label.Font = Enum.Font.BuilderSansBold
	label.TextColor3 = Color3.fromRGB(255, 120, 110)
	label.ZIndex = 11
	label.Parent = banner
	banner.Parent = gui
	return banner
end
Controller.faultBanner = faultBanner

-- Turns the fault effects off and restores the blade colour / LED colours.
function Controller.clearFault(p: Prop)
	local f: any = p.fault
	if not f then
		return
	end
	p.fault = nil
	if f.beacon then
		f.beacon:Destroy()
	end
	if f.banner then
		f.banner:Destroy()
	end
	if p.breathe and p.breathe.part.Parent then
		p.breathe.part.Color = p.breathe.color
		p.breathe.part.Material = p.breathe.material
	end
	for led, color in f.leds do
		if led.Parent then
			led.BackgroundColor3 = color
		end
	end
end

-- One fault step of a broken blade / rack door (active props only).
function Controller.fault(p: Prop, now: number)
	local root = p.root
	local f: any = p.fault
	if not f then
		f = { leds = {}, on = nil, textAt = 0 }
		p.fault = f
		local slot = root:GetAttribute("FaultSlot")
		if p.kinds.breathe and root:IsA("BasePart") then
			f.beacon, f.gui, f.title, f.sub, f.light = faultBeacon(root)
		end
		if p.kinds.leds then
			for _, led in p.leds do
				f.leds[led] = led.BackgroundColor3
			end
			if p.gui then
				f.banner = faultBanner(p.gui, if typeof(slot) == "number" then slot else nil)
			end
		end
	end
	local on = math.floor(now * FAULT_BLINK * 2) % 2 == 0
	if f.on ~= on then
		f.on = on
		if p.breathe and p.breathe.part.Parent then
			p.breathe.part.Color = if on then FAULT_RED else FAULT_DIM
			p.breathe.part.Material = if on then Enum.Material.Neon else p.breathe.material
		end
		for led in f.leds do
			if led.Parent then
				led.BackgroundColor3 = if on then FAULT_RED else FAULT_DIM
			end
		end
		if f.light then
			f.light.Enabled = on
		end
		if f.beacon then
			f.beacon.Color = if on then FAULT_RED else FAULT_DIM
		end
	end
	if f.title and now >= f.textAt then
		f.textAt = now + 0.5
		local slot = root:GetAttribute("FaultSlot")
		local untilTime = root:GetAttribute("FaultUntil")
		local title, sub = Controller.faultText(if typeof(slot) == "number" then slot else nil, if typeof(untilTime) == "number" then untilTime else nil, now)
		f.title.Text = title
		f.sub.Text = sub
	end
end

-- Back to the build pose: called when a prop leaves the active set or unregisters.
function Controller.reset(p: Prop, parts: { BasePart }?, cframes: { CFrame }?)
	if p.moved then
		for _, m in p.moving do
			if m.part.Parent then
				if parts and cframes then
					table.insert(parts, m.part)
					table.insert(cframes, m.home)
				else
					m.part.CFrame = m.home
				end
			end
		end
		p.moved = false
	end
	p.angle, p.phase, p.alpha = 0, 0, 0
	Controller.clearFault(p)
	p.broken = false
	p.effects = nil
	applyEffects(p, false)
	p.effects = nil
	setGlow(p, false)
	p.glowOn = nil
	if p.breathe and p.breathe.part.Parent then
		p.breathe.part.Transparency = p.breathe.transparency
	end
	if p.ticker then
		p.ticker.Position = UDim2.new()
	end
	for _, led in p.leds do
		if led.Parent then
			led.BackgroundTransparency = 0
		end
	end
	destroySheet(p)
	p.working = false
end

local function smooth(a: number): number
	return a * a * (3 - 2 * a)
end

local function sheetPart(p: Prop, now: number)
	local out = p.outPart
	if not out or not out.Parent then
		return
	end
	local folder = localFolder()
	local sheet = Instance.new("Part")
	sheet.Name = "FxSheet"
	sheet.Anchored = true
	sheet.CanCollide = false
	sheet.CanTouch = false
	sheet.CanQuery = false
	sheet.CastShadow = false
	sheet.Size = Vector3.new(math.min(out.Size.X * 0.6, 1.1), 0.02, math.min(out.Size.Z * 0.6, 1.4))
	sheet.Color = Color3.fromRGB(246, 246, 240)
	sheet.Material = Enum.Material.SmoothPlastic
	sheet.CFrame = out.CFrame * CFrame.new(0, out.Size.Y * 0.25, -out.Size.Z * 0.3)
	sheet.Parent = folder
	p.sheet = sheet
	p.sheetStart = now
end

-- One animation step of an active prop. CFrame writes are appended to (parts, cframes).
function Controller.animate(p: Prop, now: number, dt: number, parts: { BasePart }, cframes: { CFrame })
	if now >= p.stateAt then
		p.stateAt = now + STATE_STEP
		local working, broken = Controller.state(p, now)
		if broken ~= p.broken then
			p.broken = broken
			p.effects = nil -- re-apply the screen overlay
		end
		p.working = working
	end
	local kinds = p.kinds
	if p.broken and (kinds.breathe or kinds.leds) then
		Controller.fault(p, now)
	elseif p.fault then
		Controller.clearFault(p)
	end
	local on = p.working or p.idle == "on"
	local factor = if p.working or p.idle == "on" then 1 elseif p.idle == "slow" then 0.25 else 0
	applyEffects(p, on and (kinds.steam or kinds.flame or kinds.flow or kinds.screen) ~= nil)
	-- target envelope for eased motion (hinge, slider, arm, flow bob)
	local easeTime = if kinds.hinge then HINGE_TIME else SLIDE_TIME
	local target = if on then 1 else 0
	local before = p.alpha
	if p.alpha ~= target then
		local stepA = dt / easeTime
		p.alpha = if target > p.alpha then math.min(target, p.alpha + stepA) else math.max(target, p.alpha - stepA)
	end
	p.phase += p.rate * dt * factor
	-- motion: only written when something changed this step (a stopped fan keeps its angle)
	if #p.moving > 0 then
		local transform: CFrame? = nil
		local eased = p.alpha ~= before
		if kinds.spin then
			if factor > 0 then
				p.angle = (p.angle + p.rate * dt * factor) % (2 * math.pi)
				transform = CFrame.fromAxisAngle(p.axis, p.angle)
			end
		elseif kinds.belt then
			if factor > 0 then
				local travel = if p.travel > 0 then p.travel else 1.6
				transform = CFrame.new(p.axis * ((p.phase % travel) - travel / 2))
			end
		elseif kinds.slider then
			if eased or (p.rate > 0 and p.alpha > 0) then
				local wave = if p.rate > 0 then 0.5 - 0.5 * math.cos(2 * math.pi * p.phase) else 1
				transform = CFrame.new(p.axis * (p.travel * smooth(p.alpha) * wave))
			end
		elseif kinds.hinge then
			if eased then
				local h = CFrame.new(p.hinge)
				transform = h * CFrame.fromAxisAngle(p.axis, p.travel * smooth(p.alpha)) * h:Inverse()
			end
		elseif kinds.flow and p.travel ~= 0 then
			if eased or p.alpha > 0 then
				local wave = 0.5 - 0.5 * math.cos(2 * math.pi * p.phase)
				transform = CFrame.new(p.axis * (p.travel * p.alpha * wave))
			end
		end
		if kinds.arm and p.joints then
			if eased or p.alpha > 0 then
				local j = p.joints
				local a = smooth(p.alpha)
				local t1 = j[1] * CFrame.Angles(0, 0.9 * a * math.sin(1.1 * now), 0) * j[1]:Inverse()
				local t2 = t1 * j[2] * CFrame.Angles(0, 0, 0.35 * a * math.sin(2.2 * now + 0.5)) * j[2]:Inverse()
				local t3 = t2 * j[3] * CFrame.Angles(0, 0, 0.5 * a * math.sin(2.2 * now + 1.6)) * j[3]:Inverse()
				local chain = { t1, t2, t3 }
				for _, m in p.moving do
					if m.part.Parent then
						table.insert(parts, m.part)
						table.insert(cframes, p.pivot * chain[math.clamp(m.link, 1, 3)] * m.rel)
					end
				end
				p.moved = a > 0
			end
		elseif transform then
			for _, m in p.moving do
				if m.part.Parent then
					table.insert(parts, m.part)
					table.insert(cframes, p.pivot * transform * m.rel)
				end
			end
			p.moved = transform ~= CFrame.identity
		end
	end
	-- glow / blink
	if kinds.blink or kinds.flame then
		local lit = on
		if lit and kinds.blink and p.rate > 0 then
			lit = math.floor(now * p.rate * 2) % 2 == 0
		end
		setGlow(p, lit)
	end
	-- water shimmer while visible
	if on and kinds.flow then
		for _, look in p.show do
			if look.part.Parent and look.show then
				look.part.Transparency = math.clamp(look.show + 0.08 * math.sin(now * 2 * math.pi * math.max(p.rate, 0.5)), 0, 0.95)
			end
		end
	end
	-- GPU blades breathe in one slow wave while training
	if kinds.breathe and p.breathe then
		local part = p.breathe.part
		if part.Parent then
			if p.working then
				local index = num(part:GetAttribute("RackIndex"), 1)
				local phase = (now / BREATH_PERIOD + index * 0.04) * 2 * math.pi
				part.Transparency = BREATH_DEPTH * (0.5 - 0.5 * math.cos(phase))
			elseif part.Transparency ~= p.breathe.transparency then
				part.Transparency = p.breathe.transparency
			end
		end
	end
	-- rack status LEDs flicker (always; faster while working)
	if kinds.leds and #p.leds > 0 and now >= p.ledAt and not p.fault then
		p.ledAt = now + (if p.working then 0.15 else 0.6)
		local tick = math.floor(now * 7)
		for i, led in p.leds do
			if led.Parent then
				led.BackgroundTransparency = if (tick * 31 + i * 17) % 5 == 0 then 0.65 else 0
			end
		end
	end
	-- scrolling ticker
	if kinds.ticker and p.ticker and p.gui then
		local label = p.ticker
		local canvas = label.Parent and (label.Parent :: any).AbsoluteSize or Vector2.zero
		local width = math.max(label.TextBounds.X, 300)
		local span = width + math.max(canvas.X, 200)
		label.Position = UDim2.fromOffset(math.max(canvas.X, 200) - (now * p.rate) % span, 0)
	end
	-- paper sheets out of printers / copiers
	if kinds.paper then
		if p.sheet then
			local age = now - p.sheetStart
			if age > PAPER_EVERY or not p.sheet.Parent then
				destroySheet(p)
			else
				local out = p.outPart
				if out and out.Parent then
					table.insert(parts, p.sheet)
					table.insert(cframes, out.CFrame * CFrame.new(0, out.Size.Y * 0.25, -out.Size.Z * 0.3 - math.min(age, 1) * 1.1))
				end
			end
		elseif p.working and now >= p.nextSheet then
			p.nextSheet = now + PAPER_EVERY + 0.2
			sheetPart(p, now)
		end
	end
end

function Controller.unregister(root: Instance)
	local p = props[root]
	if not p then
		return
	end
	props[root] = nil
	if root.Parent then
		Controller.reset(p)
	else
		destroySheet(p)
	end
end

-- LOD pass: which props are active / near the camera. Props leaving the active set are reset once.
function Controller.scan(camera: Vector3, parts: { BasePart }?, cframes: { CFrame }?)
	table.clear(activeList)
	for root, p in props do
		if not root.Parent then
			props[root] = nil
			continue
		end
		local delta = p.position - camera
		local distance = delta.Magnitude
		local active = distance < FAR and math.abs(delta.Y) < VERTICAL
		if not active and p.active then
			Controller.reset(p, parts, cframes)
		end
		p.active = active
		p.near = distance < NEAR
		if active then
			table.insert(activeList, p)
		end
	end
end

-- One frame: animate the active set (near every frame, mid-range at 10 Hz), then batch the CFrames.
function Controller.step(now: number, parts: { BasePart }?, cframes: { CFrame }?): ({ BasePart }, { CFrame })
	local outParts: { BasePart } = parts or {}
	local outFrames: { CFrame } = cframes or {}
	for _, p in activeList do
		if p.near or now >= p.nextAt then
			local dt = if p.lastAt > 0 then math.clamp(now - p.lastAt, 0, 0.5) else 0
			p.lastAt = now
			p.nextAt = now + MID_STEP
			Controller.animate(p, now, dt, outParts, outFrames)
		end
	end
	return outParts, outFrames
end

function Controller.flush(parts: { BasePart }, cframes: { CFrame })
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function Controller.registry(): { [Instance]: Prop }
	return props
end
function Controller.active(): { Prop }
	return activeList
end

function Controller.init()
	for _, tag in { TAG, LEGACY_FAN } do
		for _, inst in CollectionService:GetTagged(tag) do
			Controller.register(inst)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst: Instance)
			Controller.register(inst)
		end)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst: Instance)
			-- a prop tagged twice (PropFx + legacy ClusterFan) stays while one tag remains
			if not CollectionService:HasTag(inst, TAG) and not CollectionService:HasTag(inst, LEGACY_FAN) then
				Controller.unregister(inst)
			end
		end)
	end
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	RunService.PreRender:Connect(function(dt: number)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		table.clear(parts)
		table.clear(cframes)
		scanClock += dt
		if scanClock >= SCAN_STEP then
			scanClock = 0
			Controller.scan(camera.CFrame.Position, parts, cframes)
		end
		Controller.step(serverNow(), parts, cframes)
		Controller.flush(parts, cframes)
	end)
end

return Controller
