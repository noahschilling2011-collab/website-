--!strict
-- DriveController (package "drivers", client): everything about the company chauffeurs, the fleet rides and the VIP
-- limousine that the player sees. Main.client requires it and calls init() after PhoneController.init.
--   * cars: every ride DriverService publishes (ReplicatedStorage.CompanyDrivers/*/Ride_<n>, attribute Plan) is posed
--     every frame from DrivePlan with workspace:GetServerTimeNow() - the same maths as the server, nothing moves over
--     the network. Part-built cars (company fleet sedan in the company colour, the founder's own car type, the long
--     wheelbase VIP limousine - or the imported ExecutiveLimo mesh when the owner added it, see buildCar), anchored,
--     CanCollide / CanQuery / CanTouch off, collision group "DriveCars". A ride far from the camera is not even
--     decoded (its places' area); cars only within NEAR studs (the local player's own ride always), at most MAX_CARS,
--     occupants only within SEAT_NEAR. Seated occupants are scaled (DrivePlan.seatFit) so arms stay inside the car.
--     Field reps / client guests / companions get in and out at the places between two legs: while the car waits
--     there they stand at the place's door (derived from the plan, nothing extra is sent).
--     A car that stops for good near the camera (the founder left the game, a car back in the garage) stays parked
--     until the camera is away (no car vanishing in front of a player).
--   * drivers at the HQ entrance: each company driver who is not out on a ride waits at the entrance 06:00-22:00 (rig
--     template Driver<i>, uniform with cap), within POST_NEAR; one idle fleet car stands at the depot in B1 when no
--     ride uses the garage lane; the limousine and its chauffeur wait at the Port Meridian VIP stand (bay 1) while the
--     server says the stand is idle (Limo attribute Stand).
--   * the local founder's ride: HUD "To City Airport · 0:48 · Cancel" (on the way / waiting with a "Get in" button
--     near the car / riding with a countdown) - it slides below a toast instead of hiding under it; the camera
--     follows the car (orbit; "View" switches to the back seat), the founder's own avatar is cloned onto the back
--     seat (the server holds the real character below the road).
--   * destination sheet: the phone's Driver contact makes the server send Notify DRIVE_SHEET (the phone's dial
--     screen can only show text); the sheet lists the destinations with ETAs and books with TripAction
--     {action = "ride", op = "request", to}. Touch (44 pt targets on a phone), mouse and gamepad (B closes).
--   * DriveController.liveCars(): the cars drawn this frame ({cf, length, width, speed}) for the city traffic.
-- Honest: everything shown comes from the published plan; the cars are visual only (the server validates boarding,
-- places the founder and keeps the economy).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage.Shared
local Drive = require(Shared.DrivePlan)
local Net = require(Shared.Net)
local State = require(script.Parent.StateController)
local Employee = require(script.Parent.EmployeeController)
local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Toast = require(UI.Toast)
local PhoneKit = require(UI.Phone.PhoneKit)

local C = Theme.colors
local F = Theme.font

local DriveController = {}
DriveController.NEAR = 650 -- cars are shown within this distance of the camera
DriveController.SEAT_NEAR = 240 -- occupants are shown within this distance
DriveController.POST_NEAR = 260 -- drivers waiting at the HQ entrance / the VIP stand, the idle fleet car in B1
DriveController.CULL_MARGIN = 300 -- a ride whose places' area (+ this) is beyond NEAR from the camera is not decoded
DriveController.LINGER_NEAR = 150 -- a car that stops for good stays parked while the camera is this close
DriveController.LINGER_MAX = 600
DriveController.MAX_CARS = 10
DriveController.MAX_POSTS = 8
DriveController.GROUP = "DriveCars"
DriveController.SHEET_ORDER = 45 -- above the open phone (28) and the panels (40)
DriveController.HUD_ORDER = 24
DriveController.COMPACT = 0.9 -- UI scale below which the touch targets grow to 44 pt (68 design px at 0.65)
DriveController.DIRECT = false -- test seam: write CFrames one by one instead of workspace:BulkMoveTo

-- The imported ExecutiveLimo (design/requests/drivers.md section 6, assets/vehicles/executivelimo/manifest.json):
-- numbers at the game scale 0.95, model frame = ground point on the centre line between the axles, -Z forward.
local MESH = {
	scale = 0.95,
	wheelbase = 18.10,
	length = 25.76,
	width = 7.30,
	wheelR = 1.1927,
	required = { "Body", "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR", "Door_RearL", "Door_RearR" },
	paint = { Body = true, Door_Driver = true, Door_RearL = true, Door_RearR = true, Mirror_L = true, Mirror_R = true },
	glass = { Glass = 0.45, Door_Driver_Glass = 0.45, GlassPrivacy = 0.22, Door_RearL_Glass = 0.22, Door_RearR_Glass = 0.22 },
	neon = { Ambient_LED = true, StarLights = true, Lights_Front = true, Lights_Rear = true },
	wheels = { Wheel_FL = true, Wheel_FR = true, Wheel_RL = true, Wheel_RR = true, Caliper_FL = false, Caliper_FR = false, Caliper_RL = false, Caliper_RR = false },
	steer = { Wheel_FL = true, Wheel_FR = true, Caliper_FL = true, Caliper_FR = true },
	doors = { Door_Driver = -65, Door_Driver_Glass = -65, Door_RearL = -65, Door_RearL_Glass = -65, Door_RearR = 65, Door_RearR_Glass = 65 },
	kerbDoors = { Door_RearR = true, Door_RearR_Glass = true },
	-- rig roots: x, cushion top y, z, headliner y
	seats = {
		driver = { -1.3571, 1.66, -3.7593, 4.575 },
		front = { 1.3571, 1.66, -3.7593, 4.57 },
		rearL = { -1.3571, 1.66, 8.7977, 4.787 },
		rearR = { 1.3571, 1.66, 8.7977, 4.787 },
	},
	cabinHalf = 2.97, -- inner door panels (body half width 3.32 minus the trim)
	far = 150, -- beyond this the mesh limousine hides its interior (16.9k of its 69.9k triangles; see meshLod)
	interior = { Interior_Front = true, SteeringWheel = true, Interior_Lounge = true, Interior_Bar = true, Ambient_LED = true, StarLights = true },
}
DriveController.MESH = MESH

type Seat = { model: Model, root: BasePart, joints: { [string]: Motor6D }, seed: number, code: string, seat: string, standing: boolean? }
type Wheel = { index: number, pivotRel: CFrame, steer: boolean, spin: boolean }
type Door = { index: number, pivotRel: CFrame, angle: number, kerb: boolean }
type Car = { model: Model, root: BasePart, focus: BasePart, look: string, seats: { [string]: Seat }, key: string, livery: Color3,
	parts: { BasePart }, offsets: { CFrame }, at: CFrame?, speed: number, mesh: boolean, wheels: { Wheel }, doors: { Door },
	odo: number, steer: number, lastPos: Vector3?, lastYaw: number?, door: number, company: Folder?, born: number,
	interior: { BasePart }, interiorHidden: boolean }
type RideView = {
	folder: Folder,
	company: Folder?,
	plan: string,
	segs: { Drive.Seg }?,
	plot: number?,
	car: Car?,
	pose: Drive.Pose?,
}
type Post = { model: Model, root: BasePart, joints: { [string]: Motor6D }, seed: number, at: CFrame? }
type LiveCar = { cf: CFrame, length: number, width: number, speed: number }

local player = Players.LocalPlayer
local root: Folder? = nil
local world: Folder? = nil
local views: { [Folder]: RideView } = {}
local posts: { [string]: Post } = {}
local depots: { [Folder]: Car } = {}
local ghosts: { Car } = {}
local live: { LiveCar } = {}
local idleLimo: Car? = nil
local idleChauffeur: Post? = nil
type Hud = { gui: ScreenGui, root: Frame, panel: Frame, icon: Frame, title: TextLabel, sub: TextLabel, board: TextButton, cancel: TextButton, view: TextButton,
	scale: UIScale, compact: boolean, top: number }
local hud: Hud? = nil
local sheet: { gui: ScreenGui, scale: UIScale, list: ScrollingFrame, title: TextLabel, text: TextLabel, cancel: TextButton }? = nil
local mine: RideView? = nil
local cameraMode = "orbit"
local cameraBound = false
local busy = false
local lastHudText = ""
local hiddenHead: { BasePart } = {}
local meshTemplate: Model? = nil
local meshChecked = false

------------------------------------------------------------------------------------------------ helpers
local function now(): number
	return workspace:GetServerTimeNow()
end
local function remote(): RemoteFunction?
	local ok, fn = pcall(function() return Net.getFunction("TripAction") end)
	return if ok then fn else nil
end
local function invoke(payload: { [string]: any }): { [string]: any }
	local fn = remote()
	if not fn then return { ok = false, err = "LOADING" } end
	local ok, res = pcall(function() return fn:InvokeServer(payload) end)
	if not ok or typeof(res) ~= "table" then return { ok = false, err = "SERVER_ERROR" } end
	return res
end
local MESSAGES: { [string]: string } = {
	NO_DRIVER = "Your first driver joins at the Founder Headquarters.",
	FLYING = "You're on a flight right now.",
	TOO_FAR = "Walk to a pick-up point first: your HQ entrance, the airport kerb or a client building.",
	ALREADY_THERE = "You're already there.",
	ALREADY_RIDING = "Your ride is already booked.",
	FLIGHT_REQUIRED = "That's in the other city - take a flight first.",
	COOLDOWN = "One moment please.",
	LEAVE_VEHICLE = "Leave your car first.",
	NOT_WAITING = "The car is not there yet.",
	RATE_LIMIT = "One moment please.",
	LOADING = "Still loading - try again in a moment.",
	NO_RIDE = "There is no ride to cancel.",
	RETURNING = "The car is already on its way back.",
	BAD_PLACE = "That destination isn't on the driver's list.",
}
function DriveController.message(err: any): string
	return MESSAGES[tostring(err)] or "The driver can't do that right now."
end
local function cameraPos(): Vector3
	local cam = workspace.CurrentCamera
	return if cam then cam.CFrame.Position else Vector3.zero
end
local function setGroup(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	pcall(function() p.CollisionGroup = DriveController.GROUP end)
end
local function flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

------------------------------------------------------------------------------------------------ cars (part-built)
local INK = Color3.fromRGB(28, 30, 34)
local CHROME = Color3.fromRGB(196, 200, 206)
local GLASS = Color3.fromRGB(26, 32, 40)
local LIMO_PAINT = Color3.fromRGB(14, 15, 18)
local function darker(c: Color3, f: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), f)
end
-- size table per look: width (body), length, roof height, wheelbase, wheel radius
-- w = body width (+0.4 mirrors = DrivePlan.CAR_WIDTH), h = roof height (a seated rig with a cap reaches 2.32 * scale
-- above its root, the roof underside is above 4.95), cabin = greenhouse length incl. the sloped windscreen (ws) and
-- rear window (rs) wedges. The greenhouse is GLASS_INSET narrower than the body (DrivePlan.seatFit sizes the
-- occupants to it).
local GLASS_INSET = 0.4
local SHAPES: { [string]: { w: number, l: number, h: number, wb: number, r: number, cabin: number, cabinZ: number, ws: number, rs: number } } = {
	fleet = { w = 6.6, l = 15, h = 5.4, wb = Drive.WHEELBASE.fleet, r = 1.3, cabin = 8.6, cabinZ = 0.7, ws = 2.4, rs = 2.0 },
	limo = { w = 7.0, l = 21, h = 5.4, wb = Drive.WHEELBASE.limo, r = 1.35, cabin = 13.4, cabinZ = 1.3, ws = 2.6, rs = 2.2 },
	compact = { w = 6.2, l = 12, h = 5.4, wb = Drive.WHEELBASE.compact, r = 1.2, cabin = 7.4, cabinZ = 1.2, ws = 2.4, rs = 1.0 },
	van = { w = 6.6, l = 15, h = 6.4, wb = Drive.WHEELBASE.van, r = 1.35, cabin = 5.0, cabinZ = -3.6, ws = 1.6, rs = 0.01 },
	executive = { w = 6.6, l = 15, h = 5.3, wb = Drive.WHEELBASE.executive, r = 1.35, cabin = 8.8, cabinZ = 0.8, ws = 2.6, rs = 2.4 },
	sport = { w = 6.6, l = 13.5, h = 5.1, wb = Drive.WHEELBASE.sport, r = 1.3, cabin = 7.0, cabinZ = 1.2, ws = 2.8, rs = 2.4 },
}
DriveController.SHAPES = SHAPES
DriveController.GLASS_INSET = GLASS_INSET
local function glassHalf(look: string): number
	local shape = SHAPES[look] or SHAPES.fleet
	return (shape.w - GLASS_INSET) / 2
end
DriveController.glassHalf = glassHalf

-- the imported ExecutiveLimo template (cached; nil = keep the part-built limousine exactly as before)
local function findMesh(): Model?
	if meshChecked then return meshTemplate end
	meshChecked = true
	local candidates: { Instance? } = {}
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local vehicles = if assets then assets:FindFirstChild("Vehicles") else nil
	table.insert(candidates, if vehicles then vehicles:FindFirstChild("ExecutiveLimo") else nil)
	local va = ReplicatedStorage:FindFirstChild("VehicleAssets")
	table.insert(candidates, if va then va:FindFirstChild("ExecutiveLimo") else nil)
	for _, c in candidates do
		if c and c:IsA("Model") then
			local complete = true
			for _, name in MESH.required do
				local part = c:FindFirstChild(name, true)
				if not part or not part:IsA("BasePart") then complete = false; break end
			end
			if complete then meshTemplate = c; return c end
		end
	end
	return nil
end
DriveController.findMesh = findMesh
function DriveController._resetMesh() meshChecked = false; meshTemplate = nil end -- test seam
-- wheelbase of a look as drawn (the mesh limousine is longer between the axles than the part-built one)
local function wheelbaseOf(look: string): number
	if look == "limo" and findMesh() then return MESH.wheelbase end
	return Drive.WHEELBASE[look] or Drive.WHEELBASE.fleet
end
DriveController.wheelbaseOf = wheelbaseOf
local function lengthOf(look: string): number
	if look == "limo" and findMesh() then return MESH.length end
	return Drive.CAR_LENGTH[look] or Drive.CAR_LENGTH.fleet
end

local function newCar(m: Model, rootPart: BasePart, focus: BasePart, look: string, livery: Color3, parts: { BasePart }, offsets: { CFrame }): Car
	return { model = m, root = rootPart, focus = focus, look = look, seats = {}, key = "", livery = livery, parts = parts, offsets = offsets, at = nil,
		speed = 0, mesh = false, wheels = {}, doors = {}, odo = 0, steer = 0, lastPos = nil, lastYaw = nil, door = 0, company = nil, born = 0,
		interior = {}, interiorHidden = false }
end

-- The mesh limousine: clone + ScaleTo(0.95), every part anchored / no collision, offsets from the model pivot for the
-- BulkMoveTo path, wheels (spin + steer) and the doors (hinges) from the manifest's pivots.
local function buildMeshLimo(template: Model): Car?
	local ok, res = pcall(function(): Car
		local m = template:Clone()
		m:ScaleTo(MESH.scale)
		m.Name = "DriveCar_limo"
		local pivot = m:GetPivot()
		local parts: { BasePart } = {}
		local offsets: { CFrame } = {}
		local car: Car
		local rootPart = Instance.new("Part")
		rootPart.Name = "Root"
		rootPart.Size = Vector3.new(1, 1, 1)
		rootPart.Transparency = 1
		rootPart.CFrame = pivot
		setGroup(rootPart)
		rootPart.CastShadow = false
		rootPart.Parent = m
		table.insert(parts, rootPart)
		table.insert(offsets, CFrame.new())
		local focus = Instance.new("Part")
		focus.Name = "CameraFocus"
		focus.Size = Vector3.new(0.4, 0.4, 0.4)
		focus.Transparency = 1
		focus.CFrame = pivot * CFrame.new(0, 4.5, 2)
		setGroup(focus)
		focus.CastShadow = false
		focus.Parent = m
		table.insert(parts, focus)
		table.insert(offsets, CFrame.new(0, 4.5, 2))
		car = newCar(m, rootPart, focus, "limo", LIMO_PAINT, parts, offsets)
		car.mesh = true
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d ~= rootPart and d ~= focus then
				setGroup(d)
				d.CastShadow = d.Name == "Body"
				if MESH.paint[d.Name] then d.Color = LIMO_PAINT end
				local tr = MESH.glass[d.Name]
				if tr then d.Material = Enum.Material.Glass; d.Transparency = tr end
				if MESH.neon[d.Name] then d.Material = Enum.Material.Neon end
				if d.Name == "Ambient_LED" then d.Color = Color3.fromRGB(140, 123, 255) end
				if MESH.interior[d.Name] then table.insert(car.interior, d) end
				table.insert(parts, d)
				local rest = pivot:ToObjectSpace(d.CFrame)
				table.insert(offsets, rest)
				local idx = #parts
				local spin = MESH.wheels[d.Name]
				if spin ~= nil then
					table.insert(car.wheels, { index = idx, pivotRel = pivot:ToObjectSpace(d:GetPivot()), steer = MESH.steer[d.Name] == true, spin = spin })
				end
				local angle = MESH.doors[d.Name]
				if angle then
					table.insert(car.doors, { index = idx, pivotRel = pivot:ToObjectSpace(d:GetPivot()), angle = angle, kerb = MESH.kerbDoors[d.Name] == true })
				end
			end
		end
		m.PrimaryPart = rootPart
		m:SetAttribute("Look", "limo")
		m:SetAttribute("Mesh", true)
		return car
	end)
	if not ok then warn("[Drive] ExecutiveLimo mesh failed, using the part-built limousine: " .. tostring(res)); return nil end
	return res
end

-- Triangle budget of the mesh limousine: beyond MESH.far from the camera its interior is hidden locally (written
-- only when the car crosses the distance, never per frame); the part-built limousine has nothing to hide.
local function meshLod(car: Car, dist: number)
	if not car.mesh then return end
	local hide = dist > MESH.far
	if hide == car.interiorHidden then return end
	car.interiorHidden = hide
	for _, part in car.interior do part.LocalTransparencyModifier = if hide then 1 else 0 end
end
DriveController.meshLod = meshLod
-- Builds one car (pivot = centre at ground level, -Z forward). Every part is anchored and keeps its offset from the
-- pivot; a moving car is placed with one workspace:BulkMoveTo per frame for all cars (CityLifeController's way), a
-- parked car is not touched at all.
local function buildCar(look: string, livery: Color3, company: string): Car
	if look == "limo" then
		local tpl = findMesh()
		local car = if tpl then buildMeshLimo(tpl) else nil
		if car then return car end
	end
	local shape = SHAPES[look] or SHAPES.fleet
	local limo = look == "limo"
	local body = if limo then LIMO_PAINT else livery
	local m = Instance.new("Model")
	m.Name = "DriveCar_" .. look
	local rootPart = Instance.new("Part")
	rootPart.Name = "Root"
	rootPart.Size = Vector3.new(1, 1, 1)
	rootPart.Transparency = 1
	setGroup(rootPart)
	rootPart.CastShadow = false
	rootPart.Parent = m
	m.PrimaryPart = rootPart
	local parts: { BasePart } = { rootPart }
	local offsets: { CFrame } = { CFrame.new() }
	local function part(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, wedge: boolean?): BasePart
		local p: BasePart = if wedge then Instance.new("WedgePart") else Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = offset
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if shape and p:IsA("Part") then p.Shape = shape end
		setGroup(p)
		p.CastShadow = name == "Body" or name == "Roof" or name == "Cabin"
		p.Parent = m
		table.insert(parts, p)
		table.insert(offsets, offset)
		return p
	end
	local W, L, H, R = shape.w, shape.l, shape.h, shape.r
	local wb = shape.wb
	-- lower body, sills, bumpers
	part("Underbody", Vector3.new(W - 0.6, 0.5, L - 1.4), CFrame.new(0, R * 0.55, 0), INK)
	local bodyTop = if look == "van" then 2.9 else 2.55
	part("Body", Vector3.new(W, bodyTop - R * 0.75, L - 0.6), CFrame.new(0, (bodyTop + R * 0.75) / 2, 0), body, Enum.Material.SmoothPlastic)
	part("BumperF", Vector3.new(W - 0.2, 0.7, 0.5), CFrame.new(0, R * 0.8, -L / 2 + 0.1), darker(body, 0.55))
	part("BumperR", Vector3.new(W - 0.2, 0.7, 0.5), CFrame.new(0, R * 0.8, L / 2 - 0.1), darker(body, 0.55))
	-- hood and trunk with a slight drop to the front
	if look ~= "van" then
		part("Hood", Vector3.new(W - 0.3, 0.35, 3.7), CFrame.new(0, bodyTop + 0.1, -L / 2 + 2.3) * CFrame.Angles(math.rad(-4), 0, 0), body)
		part("Trunk", Vector3.new(W - 0.3, 0.35, if limo then 2.6 else 2.2), CFrame.new(0, bodyTop + 0.08, L / 2 - 1.5), body)
	end
	-- greenhouse: tinted glass between a sloped windscreen and rear window (wedges: slope towards local -Z), roof on top
	local cabinH = H - bodyTop - 0.35
	local cabinW = W - GLASS_INSET
	local half = shape.cabin / 2
	local boxLen = shape.cabin - shape.ws - shape.rs
	local boxZ = shape.cabinZ - half + shape.ws + boxLen / 2
	local cabin = part("Cabin", Vector3.new(cabinW, cabinH, boxLen), CFrame.new(0, bodyTop + cabinH / 2, boxZ), GLASS, Enum.Material.Glass)
	cabin.Transparency = 0.22
	local wsGlass = part("Windscreen", Vector3.new(cabinW, cabinH, shape.ws), CFrame.new(0, bodyTop + cabinH / 2, shape.cabinZ - half + shape.ws / 2), GLASS, Enum.Material.Glass, nil, true)
	wsGlass.Transparency = 0.25
	if shape.rs > 0.05 then
		local rear = part("RearWindow", Vector3.new(cabinW, cabinH, shape.rs), CFrame.new(0, bodyTop + cabinH / 2, shape.cabinZ + half - shape.rs / 2) * CFrame.Angles(0, math.pi, 0),
			GLASS, Enum.Material.Glass, nil, true)
		rear.Transparency = 0.25
	end
	if look == "van" then
		part("CargoBox", Vector3.new(W - 0.2, H - bodyTop, L - shape.cabin - 1.6), CFrame.new(0, bodyTop + (H - bodyTop) / 2, shape.cabinZ + shape.cabin / 2 + (L - shape.cabin - 1.6) / 2), body)
	end
	part("Roof", Vector3.new(cabinW + 0.1, 0.32, boxLen + 0.3), CFrame.new(0, H - 0.16, boxZ), if limo then Color3.fromRGB(18, 19, 23) else body)
	for _, side in { -1, 1 } do
		part("PillarC", Vector3.new(0.3, cabinH, 0.6), CFrame.new(side * (cabinW / 2 - 0.05), bodyTop + cabinH / 2, boxZ + boxLen / 2 - 0.3), body)
		if limo then
			part("PillarB", Vector3.new(0.3, cabinH, 0.5), CFrame.new(side * (cabinW / 2 - 0.05), bodyTop + cabinH / 2, boxZ - boxLen / 2 + 3.4), Color3.fromRGB(18, 19, 23))
			part("DoorLine", Vector3.new(0.06, bodyTop - R * 0.75 - 0.3, 0.12), CFrame.new(side * (W / 2 + 0.01), (bodyTop + R * 0.75) / 2, boxZ + 1.2), Color3.fromRGB(40, 40, 46))
			part("ChromeLine", Vector3.new(0.12, 0.16, L - 2.4), CFrame.new(side * (W / 2 + 0.02), bodyTop - 0.15, 0), CHROME, Enum.Material.Metal)
		else
			part("Stripe", Vector3.new(0.1, 0.22, L - 3), CFrame.new(side * (W / 2 + 0.02), 1.65, 0), darker(body, 0.35))
		end
		-- mirrors inside the car width budget (DrivePlan.CAR_WIDTH)
		part("Mirror", Vector3.new(0.2, 0.4, 0.6), CFrame.new(side * (W / 2 + 0.1), bodyTop + 0.35, shape.cabinZ - half + shape.ws * 0.8), body)
		for _, z in { -wb / 2, wb / 2 } do
			part("Tyre", Vector3.new(0.85, R * 2, R * 2), CFrame.new(side * (W / 2 - 0.42), R, z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(22, 22, 24), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
			part("Rim", Vector3.new(0.9, R * 1.2, R * 1.2), CFrame.new(side * (W / 2 - 0.4), R, z) * CFrame.Angles(0, 0, math.rad(90)), CHROME, Enum.Material.Metal, Enum.PartType.Cylinder)
		end
		local hl = part("Headlight", Vector3.new(1.3, 0.4, 0.2), CFrame.new(side * (W / 2 - 1.1), 2.0, -L / 2 + 0.25), Color3.fromRGB(240, 240, 228), Enum.Material.Neon)
		hl.CastShadow = false
		local tl = part("TailLight", Vector3.new(1.3, 0.35, 0.2), CFrame.new(side * (W / 2 - 1.0), 2.0, L / 2 - 0.25), Color3.fromRGB(180, 30, 30), Enum.Material.Neon)
		tl.CastShadow = false
	end
	part("Grille", Vector3.new(W - 2.8, 0.55, 0.15), CFrame.new(0, 1.85, -L / 2 + 0.28), if limo then CHROME else INK, if limo then Enum.Material.Metal else nil)
	if limo then
		for _, z in { -L / 2 + 0.05, L / 2 - 0.05 } do
			part("ChromeBumper", Vector3.new(W - 0.6, 0.14, 0.12), CFrame.new(0, R * 0.8 + 0.3, z), CHROME, Enum.Material.Metal)
		end
	end
	if look == "sport" then
		part("Spoiler", Vector3.new(W, 0.2, 1.0), CFrame.new(0, bodyTop + 0.75, L / 2 - 0.9), INK)
	end
	local plate = part("Plate", Vector3.new(2.4, 0.55, 0.08), CFrame.new(0, 1.2, L / 2 + 0.02), Color3.fromRGB(226, 224, 210))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.CanvasSize = Vector2.new(240, 56)
	gui.LightInfluence = 1
	gui.MaxDistance = 60
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = if limo then "VIP" else string.upper(string.sub(company, 1, 14))
	label.TextColor3 = INK
	label.TextScaled = true
	label.Font = F.bold
	label.Parent = gui
	gui.Parent = plate
	-- camera focus (orbit camera subject) at the roof line
	local focus = part("CameraFocus", Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, H - 0.6, 0.5), INK)
	focus.Transparency = 1
	focus.CastShadow = false
	m:SetAttribute("Look", look)
	return newCar(m, rootPart, focus, look, livery, parts, offsets)
end
DriveController.buildCar = buildCar

-- the frame's CFrame batch (one BulkMoveTo for every car and occupant root)
local batchParts: { BasePart } = {}
local batchFrames: { CFrame } = {}
local function move(p: BasePart, cf: CFrame)
	if DriveController.DIRECT then p.CFrame = cf; return end
	table.insert(batchParts, p)
	table.insert(batchFrames, cf)
end
-- mesh limousine: wheel spin / steering from the distance and the heading change, the kerb-side rear door during
-- boarding / getting out (car.door 0..1)
local function meshOffsets(car: Car, cf: CFrame)
	local pos = cf.Position
	local look = cf.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	if car.lastPos then
		local ds = flatDist(pos, car.lastPos :: Vector3)
		if ds < 50 then
			car.odo += ds
			local dyaw = yaw - (car.lastYaw or yaw)
			if dyaw > math.pi then dyaw -= 2 * math.pi elseif dyaw < -math.pi then dyaw += 2 * math.pi end
			local target = if ds > 0.01 then math.clamp(math.atan(MESH.wheelbase * dyaw / ds), -math.rad(30), math.rad(30)) else car.steer
			car.steer += (target - car.steer) * 0.35
		end
	end
	car.lastPos = pos
	car.lastYaw = yaw
	local spinA = -car.odo / MESH.wheelR
	for _, w in car.wheels do
		local rot = CFrame.Angles(0, if w.steer then car.steer else 0, 0) * CFrame.Angles(if w.spin then spinA else 0, 0, 0)
		local rest = car.offsets[w.index]
		move(car.parts[w.index], cf * (w.pivotRel * rot * w.pivotRel:Inverse() * rest))
	end
	for _, d in car.doors do
		local open = if d.kerb then car.door else 0
		local rest = car.offsets[d.index]
		move(car.parts[d.index], cf * (d.pivotRel * CFrame.Angles(0, math.rad(d.angle * open), 0) * d.pivotRel:Inverse() * rest))
	end
end
local animated: { [number]: boolean } = {}
local function placeCar(car: Car, cf: CFrame)
	local changed = car.at ~= cf
	if not changed and not car.mesh then return end
	if changed then
		car.at = cf
		if car.mesh then
			table.clear(animated)
			for _, w in car.wheels do animated[w.index] = true end
			for _, d in car.doors do animated[d.index] = true end
			for i, p in car.parts do if not animated[i] then move(p, cf * car.offsets[i]) end end
		else
			for i, p in car.parts do move(p, cf * car.offsets[i]) end
		end
	end
	if car.mesh then meshOffsets(car, cf) end
end
local function flush()
	if #batchParts > 0 then
		workspace:BulkMoveTo(batchParts, batchFrames, Enum.BulkMoveMode.FireCFrameChanged)
		table.clear(batchParts)
		table.clear(batchFrames)
	end
end
DriveController.placeCar = placeCar

------------------------------------------------------------------------------------------------ occupants
local function sitTransform(joint: Motor6D, angle: number): CFrame
	local rot = joint.C0.Rotation
	return rot:Inverse() * CFrame.Angles(angle, 0, 0) * rot
end
local function cloneRig(template: Model, parent: Instance): Seat?
	local m = template:Clone()
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then hum:Destroy() end
	local r = m:FindFirstChild("HumanoidRootPart")
	if not r or not r:IsA("BasePart") then m:Destroy(); return nil end
	local joints: { [string]: Motor6D } = {}
	for _, d in m:GetDescendants() do
		if d:IsA("Motor6D") then joints[d.Name] = d
		elseif d:IsA("BasePart") then
			d.CanCollide = false; d.CanQuery = false; d.CanTouch = false
			d.CastShadow = false
		elseif d:IsA("BillboardGui") then
			d.Enabled = false
		end
	end
	r.Anchored = true
	m.Parent = parent
	local seed = m:GetAttribute("PersonalitySeed")
	return { model = m, root = r, joints = joints, seed = if typeof(seed) == "number" then seed else 1, code = "", seat = "" }
end
-- the founder on the back seat: a local clone of his own avatar (any rig type), legs bent at hips (and knees)
local function cloneAvatar(who: Player, parent: Instance): Seat?
	local character = who.Character
	if not character then return nil end
	local ok, m = pcall(function(): Model?
		local was = character.Archivable
		character.Archivable = true
		local c = character:Clone()
		character.Archivable = was
		return c
	end)
	if not ok or not m then return nil end
	local model = m :: Model
	local r = model:FindFirstChild("HumanoidRootPart")
	if not r or not r:IsA("BasePart") then model:Destroy(); return nil end
	local joints: { [string]: Motor6D } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") then
			d:Destroy()
		elseif d:IsA("Motor6D") then
			joints[d.Name] = d
		elseif d:IsA("BasePart") then
			d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.Anchored = false; d.CastShadow = false
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.EvaluateStateMachine = false
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	r.Anchored = true
	r.Transparency = 1
	model.Name = "Founder"
	model.Parent = parent
	return { model = model, root = r, joints = joints, seed = 7, code = "R", seat = "" }
end
-- seated arms: straight forward (hands on the wheel / in the lap), never swung sideways - an R6 arm hangs outside the
-- torso, so a sideways swing pokes through the door glass or into the neighbour (DrivePlan.seatFit leaves exactly
-- the arm width); torso-space rotation mapped into the joint frame
local function armTransform(joint: Motor6D, pitch: number, yaw: number): CFrame
	local rot = joint.C0.Rotation
	return rot:Inverse() * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0) * rot
end
DriveController.ARMS = { driver = { 1.25, 0 }, passenger = { 0.62, 0 } } -- pitch forward, yaw inward (rad)
local function seatArms(s: Seat)
	local a = if s.seat == "driver" then DriveController.ARMS.driver else DriveController.ARMS.passenger
	for name, j in s.joints do
		if name == "Left Shoulder" or name == "LeftShoulder" then
			j.Transform = armTransform(j, a[1], -a[2])
		elseif name == "Right Shoulder" or name == "RightShoulder" then
			j.Transform = armTransform(j, a[1], a[2])
		end
	end
end
local function poseSeat(s: Seat, t: number)
	if s.code == "R" then
		for name, j in s.joints do
			if name == "Left Hip" or name == "Right Hip" or name == "LeftHip" or name == "RightHip" then
				j.Transform = sitTransform(j, math.pi / 2)
			elseif name == "LeftKnee" or name == "RightKnee" then
				j.Transform = sitTransform(j, -math.pi / 2)
			end
		end
		seatArms(s)
		return
	end
	local pose = Employee.pose(if s.standing then "IDLE" else "MEETING", not s.standing, false, t, s.seed, nil,
		if s.standing then "scan" elseif s.seat == "driver" then "push" else "relax")
	for name, tr in pose do
		local j = s.joints[name]
		if j and j.Parent then j.Transform = tr end
	end
	if not s.standing then seatArms(s) end
end
-- template of an occupant code for a ride
local function templateFor(code: string, v: RideView): Model?
	local r = root
	if not r then return nil end
	if code == "D" then
		local d = v.folder:GetAttribute("Driver")
		local company = v.company
		if company and typeof(d) == "number" and d > 0 then
			local t = company:FindFirstChild("Driver" .. d)
			return if t and t:IsA("Model") then t else nil
		end
		local ch = r:FindFirstChild("Chauffeur")
		return if ch and ch:IsA("Model") then ch else nil
	end
	local t = v.folder:FindFirstChild(code)
	return if t and t:IsA("Model") then t else nil
end
local function riderPlayer(v: RideView): Player?
	local uid = v.folder:GetAttribute("Rider")
	if typeof(uid) ~= "number" or uid == 0 then return nil end
	return Players:GetPlayerByUserId(uid)
end
local function clearSeats(car: Car)
	for _, s in car.seats do s.model:Destroy() end
	car.seats = {}
	car.key = ""
end
-- Seat layout of a car: (rig scale, root CFrame in the car frame per seat key)
local function seatLayout(car: Car, seat: string): (number, CFrame)
	if car.mesh then
		local m = MESH.seats[seat] or MESH.seats.rearR
		local sc = math.min(Drive.RIG_SCALE, math.abs(m[1]) / 2 - 0.005, (MESH.cabinHalf - math.abs(m[1])) / 2)
		local y = math.min(m[2] + 1.5 * sc, m[4] - 0.05 - 2.32 * sc)
		return sc, CFrame.new(m[1], y, m[3])
	end
	local sc = Drive.seatFit(glassHalf(car.look))
	return sc, Drive.seatCF(seat, car.look, glassHalf(car.look))
end
DriveController.seatLayout = seatLayout
local function codesOf(who: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for code in string.gmatch(who .. ",", "([^,]*),") do if code ~= "" then out[code] = true end end
	return out
end
-- Who sits in the car and who stands at a door right now (derived from the plan, nothing extra is published):
-- moving = the leg's occupants; waiting between two legs = the people on both legs stay seated, the field reps /
-- guests / companions that leave (or join) the car stand at that place's door; before the first leg the car is
-- parked empty unless the founder just got in (limousine at the stand during the door delay).
local function seatPlan(v: RideView, pose: Drive.Pose): (string, { string }, Drive.Place?)
	local segs = v.segs or {}
	local st = v.folder:GetAttribute("State")
	if pose.phase == "before" then
		return if st == "riding" or st == "waiting" then pose.who else "", {}, nil
	end
	if pose.phase ~= "waiting" or pose.index < 1 then return pose.who, {}, nil end
	local cur = segs[pose.index]
	local nextSeg = segs[pose.index + 1]
	if not cur or not nextSeg then return pose.who, {}, nil end
	local a, b = codesOf(cur.who), codesOf(nextSeg.who)
	local seated: { string } = {}
	local standing: { string } = {}
	for i, code in string.split(cur.who, ",") do
		if code == "" then seated[i] = ""; continue end
		local stays = b[code] or code == "D" or (code == "R" and st == "riding")
		seated[i] = if stays then code else ""
		if not stays and code ~= "R" and code ~= "D" then table.insert(standing, code) end
	end
	for code in b do
		if not a[code] and code ~= "R" and code ~= "D" then table.insert(standing, code) end
	end
	table.sort(standing)
	return table.concat(seated, ","), standing, Drive.place(cur.to, v.plot)
end
DriveController.seatPlan = seatPlan
-- occupants of the car: seated (seat order) + people standing at a door (getting in / out, companions waiting for
-- the founder at the pick-up)
local function syncSeats(car: Car, v: RideView, pose: Drive.Pose, near: boolean, t: number)
	local who, standList, standPlace = seatPlan(v, pose)
	if v.folder:GetAttribute("State") == "waiting" and #standList == 0 then
		local comp = v.folder:GetAttribute("Companions")
		local n = if typeof(comp) == "number" then math.min(comp, 2) else 0
		for i = 1, n do table.insert(standList, "C" .. i) end
		if n > 0 then
			local pickupId = v.folder:GetAttribute("Pickup")
			standPlace = if typeof(pickupId) == "string" then Drive.place(pickupId, v.plot) else nil
		end
	end
	local key = if near then who .. "|" .. table.concat(standList, ",") .. "|" .. (if standPlace then standPlace.id else "") else ""
	if key ~= car.key then
		clearSeats(car)
		car.key = key
		if near then
			for seat, code in Drive.seating(who) do
				local s: Seat? = nil
				if code == "R" then
					local rp = riderPlayer(v)
					if rp then s = cloneAvatar(rp, car.model) end
				else
					local tpl = templateFor(code, v)
					if tpl then s = cloneRig(tpl, car.model) end
				end
				if s then
					s.code = code; s.seat = seat
					local sc = seatLayout(car, seat)
					if math.abs(sc - 1) > 1e-3 then pcall(function() (s :: Seat).model:ScaleTo(sc) end) end
					car.seats[seat] = s
				end
			end
			for i, code in standList do
				local tpl = templateFor(code, v)
				local s = if tpl then cloneRig(tpl, car.model) else nil
				if s then s.code = code; s.seat = "stand" .. i; s.standing = true; car.seats["stand" .. i] = s end
			end
		end
	end
	if not near then return end
	local cf = car.at or car.root.CFrame
	local shape = SHAPES[car.look] or SHAPES.fleet
	local nStand = #standList
	-- who just got out here (on the leg that ended, not on the next one): they face the door they walk to
	local gotOut: { [string]: boolean } = {}
	local segs = v.segs
	if segs and pose.phase == "waiting" and pose.index >= 1 then
		local cur, nxt = segs[pose.index], segs[pose.index + 1]
		local later = if nxt then nxt.who else ""
		if cur then
			for _, code in string.split(cur.who, ",") do
				if code ~= "" and not table.find(string.split(later, ","), code) then gotOut[code] = true end
			end
		end
	end
	for seat, s in car.seats do
		if s.standing then
			-- standing side by side at the place's door point (the pavement at a kerb, the visitor path at the HQ -
			-- never in a lane): turned towards the car while waiting to get in, towards the door after getting out
			local i = tonumber(string.sub(seat, 6)) or 1
			local at = if standPlace then standPlace.door * CFrame.new((i - (nStand + 1) / 2) * 2.4, 0, 0)
				else cf * CFrame.new(shape.w / 2 + 2.2, 3, (if car.look == "limo" then 3.8 else 2.2) + (i - 1) * 2.4)
			local p = at.Position
			if standPlace and gotOut[s.code] then
				local lv = standPlace.door.LookVector
				move(s.root, CFrame.lookAt(p, p + Vector3.new(lv.X, 0, lv.Z)))
			else
				move(s.root, CFrame.lookAt(p, Vector3.new(cf.Position.X, p.Y, cf.Position.Z)))
			end
		else
			local _, seatCF = seatLayout(car, seat)
			move(s.root, cf * seatCF)
		end
		poseSeat(s, t)
	end
end

------------------------------------------------------------------------------------------------ ride views
local function companyFolderOf(f: Folder): Folder?
	local parent = f.Parent
	if parent and parent:IsA("Folder") and string.match(parent.Name, "^Drivers_%d+") then return parent end
	return nil
end
local function liveryOf(v: RideView): Color3
	local company = v.company
	local c = if company then company:GetAttribute("Livery") else nil
	return if typeof(c) == "Color3" then c else Color3.fromRGB(24, 120, 128)
end
local function releaseCamera()
	if not cameraBound then return end
	local cam = workspace.CurrentCamera
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if cam then cam.CameraType = Enum.CameraType.Custom; if humanoid then cam.CameraSubject = humanoid end end
	cameraBound = false
	cameraMode = "orbit"
end
local function destroyCar(v: RideView)
	local car = v.car
	if car then
		if mine == v then releaseCamera() end
		car.model:Destroy()
		v.car = nil
	end
end
-- a car whose ride is over (or gone) stays parked, empty, while the camera is close and it stood still; never at the
-- limousine stand (the idle limousine takes over there) or inside the limousine garage tunnel
local function retire(v: RideView)
	local car = v.car
	if not car then return end
	if mine == v then releaseCamera() end
	-- a plan that is over leaves the car at rest at the end of its last leg (frames may have skipped the last metres)
	local segs = v.segs
	if segs and #segs > 0 then
		local look = v.folder:GetAttribute("Look")
		local last = Drive.pose(segs, v.plot, now(), wheelbaseOf(if typeof(look) == "string" then look else "fleet"))
		if last and last.phase == "done" then
			placeCar(car, last.cf)
			car.speed = 0
		end
	end
	local at = car.at
	local cam = cameraPos()
	local stand = Drive.place("pm_limo")
	local atStand = stand ~= nil and at ~= nil and flatDist(at.Position, stand.stop.Position) < 4
	local inTunnel = at ~= nil and at.Position.X > Drive.PM_DEPOT_X - 60 and at.Position.Z > 7700 and at.Position.Z < 7900
	if at and car.speed < 0.5 and not atStand and not inTunnel and (at.Position - cam).Magnitude <= DriveController.LINGER_NEAR then
		clearSeats(car)
		car.company = v.company
		car.born = os.clock()
		table.insert(ghosts, car)
		v.car = nil
		return
	end
	car.model:Destroy()
	v.car = nil
end
local function decode(v: RideView)
	local plan = v.folder:GetAttribute("Plan")
	local str = if typeof(plan) == "string" then plan else ""
	if str ~= v.plan or v.segs == nil then
		v.plan = str
		local plot = v.folder:GetAttribute("Plot")
		v.plot = if typeof(plot) == "number" and plot > 0 then plot else nil
		v.segs = Drive.decode(str, v.plot)
	end
end
-- the area of a ride's places (cheap: no routing) for the far cull
local areaCache: { [string]: { number } } = {}
local areaCount = 0
local function areaOf(v: RideView): { number }?
	local plan = v.folder:GetAttribute("Plan")
	local pickup = v.folder:GetAttribute("Pickup")
	local plot = v.folder:GetAttribute("Plot")
	local key = tostring(plan) .. "#" .. tostring(pickup) .. "#" .. tostring(plot)
	local cached = areaCache[key]
	if cached then return cached end
	local pl = if typeof(plot) == "number" and plot > 0 then plot else nil
	local box = { math.huge, -math.huge, math.huge, -math.huge }
	local function add(id: string)
		local place = Drive.place(id, pl)
		if not place then return end
		local p = place.stop.Position
		box[1] = math.min(box[1], p.X); box[2] = math.max(box[2], p.X)
		box[3] = math.min(box[3], p.Z); box[4] = math.max(box[4], p.Z)
	end
	if typeof(plan) == "string" then
		for a, b in string.gmatch(plan, "([%w_]+)>([%w_]+)") do add(a :: string); add(b :: string) end
	end
	if typeof(pickup) == "string" and pickup ~= "" then add(pickup) end
	if box[1] == math.huge then return nil end
	areaCount += 1
	if areaCount > 400 then table.clear(areaCache); areaCount = 0 end
	areaCache[key] = box
	return box
end
local function farFrom(v: RideView, cam: Vector3): boolean
	local box = areaOf(v)
	if not box then return false end
	local dx = math.max(box[1] - cam.X, 0, cam.X - box[2])
	local dz = math.max(box[3] - cam.Z, 0, cam.Z - box[4])
	return math.sqrt(dx * dx + dz * dz) > DriveController.NEAR + DriveController.CULL_MARGIN
end
DriveController.farFrom = farFrom
-- pose of a ride at time t (an empty plan while waiting = the car stands at the pick-up)
local function poseOf(v: RideView, t: number): Drive.Pose?
	decode(v)
	local segs = v.segs
	if not segs then return nil end
	local look = v.folder:GetAttribute("Look")
	local wb = wheelbaseOf(if typeof(look) == "string" then look else "fleet")
	if #segs == 0 then
		local pickup = v.folder:GetAttribute("Pickup")
		local place = if typeof(pickup) == "string" then Drive.place(pickup, v.plot) else nil
		if not place or v.folder:GetAttribute("State") ~= "waiting" then return nil end
		return { cf = place.stop, index = 0, phase = "waiting", speed = 0, who = "D", place = place.id }
	end
	local pose = Drive.pose(segs, v.plot, t, wb)
	if pose and pose.phase == "done" then
		-- an open plan (car coming / waiting for the founder) keeps the car at its end; a finished one only while a
		-- parked car's time (Until) is not up
		local st = v.folder:GetAttribute("State")
		if st == "coming" or st == "waiting" or st == "riding" then
			pose.phase = "waiting"
		else
			local untilT = v.folder:GetAttribute("Until")
			if typeof(untilT) ~= "number" or t >= untilT then return nil end
		end
	end
	-- "before": parked at the start of the first leg (the driver is still walking to it in B1 - the idle fleet car's
	-- spot -, or the founder just got into the limousine at the stand: the door delay)
	return pose
end
DriveController.poseOf = poseOf

local function isMine(v: RideView): boolean
	return v.folder:GetAttribute("Rider") == player.UserId and (v.folder:GetAttribute("Kind") == "founder" or v.folder:GetAttribute("Kind") == "limo")
end
local function collect(): { RideView }
	local out: { RideView } = {}
	local r = root
	if not r then return out end
	local seen: { [Folder]: boolean } = {}
	local function add(f: Instance)
		if f:IsA("Folder") and string.match(f.Name, "^Ride_%d+$") then
			seen[f] = true
			local v = views[f]
			if not v then
				v = { folder = f, company = companyFolderOf(f), plan = "", segs = nil, plot = nil, car = nil, pose = nil }
				views[f] = v
			end
			table.insert(out, v :: RideView)
		end
	end
	for _, ch in r:GetChildren() do
		if ch.Name == "Limo" then
			for _, f in ch:GetChildren() do add(f) end
		elseif ch:IsA("Folder") then
			for _, f in ch:GetChildren() do add(f) end
		end
	end
	for f, v in views do
		if not seen[f] then
			retire(v)
			views[f] = nil
			if mine == v then mine = nil end
		end
	end
	return out
end

------------------------------------------------------------------------------------------------ parked cars
local function stepGhosts(cam: Vector3)
	local i = 1
	local clock = os.clock()
	while i <= #ghosts do
		local g = ghosts[i]
		local at = g.at
		local gone = at == nil or (at.Position - cam).Magnitude > DriveController.LINGER_NEAR + 20 or clock - g.born > DriveController.LINGER_MAX
		if not gone and at then
			for _, lc in live do
				if flatDist(lc.cf.Position, at.Position) < 22 then gone = true; break end
			end
		end
		if gone then
			g.model:Destroy()
			table.remove(ghosts, i)
		else
			i += 1
		end
	end
end
-- a parked car with the engine off: head / tail lights dark (the ride car that replaces it is built with them on)
local function lightsOff(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "Headlight" or d.Name == "TailLight") then
			d.Material = Enum.Material.SmoothPlastic
			d.Color = if d.Name == "Headlight" then Color3.fromRGB(150, 152, 150) else Color3.fromRGB(96, 22, 24)
		end
	end
end
-- the company's idle fleet car parked at the depot in B1 (user request 23b), while no ride uses the garage lane
local function stepDepots(cam: Vector3, garageBusy: { [Folder]: boolean })
	local r = root
	local w = world
	if not r or not w then return end
	local want: { [Folder]: boolean } = {}
	for _, company in r:GetChildren() do
		if not company:IsA("Folder") or not string.match(company.Name, "^Drivers_%d+$") or company:GetAttribute("Detached") == true then continue end
		local plot = company:GetAttribute("Plot")
		local tier = company:GetAttribute("Tier")
		local drivers = company:GetAttribute("Drivers")
		if typeof(plot) ~= "number" or plot <= 0 or typeof(tier) ~= "number" or tier < 1 or typeof(drivers) ~= "number" or drivers < 1 then continue end
		if garageBusy[company :: Folder] then continue end
		local depot = Drive.place("hq_garage", plot)
		if not depot or (depot.stop.Position - cam).Magnitude > DriveController.POST_NEAR then continue end
		local blocked = false
		for _, g in ghosts do
			if g.at and flatDist(g.at.Position, depot.stop.Position) < 25 then blocked = true; break end
		end
		if blocked then continue end
		want[company :: Folder] = true
		local car = depots[company :: Folder]
		if not car then
			local livery = company:GetAttribute("Livery")
			local name = company:GetAttribute("Company")
			local built = buildCar("fleet", if typeof(livery) == "Color3" then livery else Color3.fromRGB(24, 120, 128), if typeof(name) == "string" then name else "")
			built.model.Name = "FleetCarIdle"
			lightsOff(built.model)
			built.model.Parent = w
			depots[company :: Folder] = built
			car = built
		end
		placeCar(car :: Car, depot.stop)
	end
	for company, car in depots do
		if not want[company] then car.model:Destroy(); depots[company] = nil end
	end
end
-- is this pose in the HQ's B1 garage lane (or parked at its start)?
local function inGarage(v: RideView, pose: Drive.Pose): boolean
	if not v.plot then return false end
	if pose.phase == "before" then return pose.place == "hq_garage" or (v.segs ~= nil and (v.segs :: { Drive.Seg })[1] ~= nil and (v.segs :: { Drive.Seg })[1].from == "hq_garage") end
	local cf = Drive.plotCF(v.plot)
	if not cf then return false end
	local l = cf:PointToObjectSpace(pose.cf.Position)
	return l.Y < -6 and l.Z > -45
end

------------------------------------------------------------------------------------------------ posts (drivers waiting)
local function postClear(key: string)
	local p = posts[key]
	if p then p.model:Destroy(); posts[key] = nil end
end
local function stepPosts(t: number, cam: Vector3, busyBy: { [Folder]: { [number]: boolean } })
	local r = root
	local w = world
	if not r or not w then return end
	local want: { [string]: boolean } = {}
	local n = 0
	-- working hours: under the canopy 06:00-22:00, at night on call in the drivers' room
	local onPost = Drive.onPost(t)
	for _, company in r:GetChildren() do
		if not onPost then break end
		if not company:IsA("Folder") or not string.match(company.Name, "^Drivers_%d+$") then continue end
		local plot = company:GetAttribute("Plot")
		local tier = company:GetAttribute("Tier")
		local drivers = company:GetAttribute("Drivers")
		if typeof(plot) ~= "number" or plot <= 0 or typeof(tier) ~= "number" or tier < 1 or typeof(drivers) ~= "number" then continue end
		local cf = Drive.plotCF(plot)
		if not cf then continue end
		local busyMap = busyBy[company :: Folder] or {}
		for i = 1, math.min(drivers, #Drive.HQ.post) do
			if busyMap[i] then continue end
			local at = cf * Drive.HQ.post[i]
			if (at.Position - cam).Magnitude > DriveController.POST_NEAR or n >= DriveController.MAX_POSTS then continue end
			local key = company.Name .. ":" .. i
			want[key] = true
			n += 1
			local p = posts[key]
			if not p then
				local tpl = company:FindFirstChild("Driver" .. i)
				if tpl and tpl:IsA("Model") then
					local s = cloneRig(tpl, w)
					if s then
						for _, d in s.model:GetDescendants() do if d:IsA("BillboardGui") then d.Enabled = true end end
						p = { model = s.model, root = s.root, joints = s.joints, seed = s.seed }
						posts[key] = p
					end
				end
			end
			if p then
				-- the post is static: the root moves only when it changes (the joints still animate every frame)
				if p.at ~= at then p.at = at; move(p.root, at) end
				for name, tr in Employee.pose("IDLE", false, false, t, p.seed, nil, "scan") do
					local j = p.joints[name]
					if j and j.Parent then j.Transform = tr end
				end
			end
		end
	end
	for key in posts do if not want[key] then postClear(key) end end
end
-- the limousine + chauffeur waiting at bay 1 of the VIP stand while the server says the stand is idle
local function stepStand(t: number, cam: Vector3)
	local r = root
	local w = world
	if not r or not w then return end
	local lf = r:FindFirstChild("Limo")
	local standState = if lf then lf:GetAttribute("Stand") else nil
	local stand = Drive.place("pm_limo")
	local near = stand ~= nil and (stand.stop.Position - cam).Magnitude <= DriveController.NEAR
	if not near or not stand or (standState ~= nil and standState ~= "idle") then
		if idleLimo then idleLimo.model:Destroy(); idleLimo = nil end
		if idleChauffeur then idleChauffeur.model:Destroy(); idleChauffeur = nil end
		return
	end
	if not idleLimo then
		local car = buildCar("limo", LIMO_PAINT, "VIP")
		car.model.Name = "VipLimoIdle"
		car.model.Parent = w
		idleLimo = car
	end
	local car = idleLimo :: Car
	placeCar(car, stand.stop)
	meshLod(car, (stand.stop.Position - cam).Magnitude)
	if (stand.stop.Position - cam).Magnitude <= DriveController.POST_NEAR then
		if not idleChauffeur then
			local tpl = r:FindFirstChild("Chauffeur")
			local s = if tpl and tpl:IsA("Model") then cloneRig(tpl, w) else nil
			if s then
				for _, d in s.model:GetDescendants() do if d:IsA("BillboardGui") then d.Enabled = true end end
				idleChauffeur = { model = s.model, root = s.root, joints = s.joints, seed = s.seed }
			end
		end
		local ch = idleChauffeur
		if ch then
			-- beside the rear door on the kerb side, facing the arrivals hall exit
			local width = if car.mesh then MESH.width else SHAPES.limo.w
			local at = stand.stop * CFrame.new(width / 2 + 2.4, 3, if car.mesh then 6.6 else 3.8)
			local cf = CFrame.lookAt(at.Position, at.Position + stand.stop.RightVector)
			if ch.at ~= cf then ch.at = cf; move(ch.root, cf) end
			for name, tr in Employee.pose("IDLE", false, false, t, ch.seed, nil, "scan") do
				local j = ch.joints[name]
				if j and j.Parent then j.Transform = tr end
			end
		end
	elseif idleChauffeur then
		idleChauffeur.model:Destroy()
		idleChauffeur = nil
	end
end

------------------------------------------------------------------------------------------------ HUD
local function hudScale(gui: ScreenGui): number
	local h = gui.AbsoluteSize.Y
	if h <= 0 then
		-- not laid out yet (just parented): the camera's viewport
		local cam = workspace.CurrentCamera
		h = if cam then cam.ViewportSize.Y else 0
	end
	if h <= 0 then return 1 end
	return math.clamp(h / 600, 0.62, 1.2)
end
-- Where the ride panel's top edge goes (design px inside the scaled HUD): 10 below the top, or 8 below the toast that
-- is showing (Toast lives in AIEmpire_Top at the top centre - the HUD slides below it instead of hiding under it).
function DriveController.hudTop(toastBottomPx: number?, scale: number): number
	if toastBottomPx == nil or toastBottomPx <= 0 then return 10 end
	return math.max(10, (toastBottomPx + 8) / math.max(scale, 0.1))
end
-- the toast stack's bottom edge in screen px below the top of the HUD's root frame (both are GuiObjects, so their
-- AbsolutePositions share one coordinate space whatever insets the two ScreenGuis use)
local function toastBottom(rootFrame: Frame): number?
	local pg = player:FindFirstChild("PlayerGui")
	local top = if pg then pg:FindFirstChild("AIEmpire_Top") else nil
	local holder = if top then top:FindFirstChild("Toasts", true) else nil
	if not holder or not holder:IsA("GuiObject") or not holder.Visible then return nil end
	local size = holder.AbsoluteSize
	if size.Y < 4 then return nil end
	return holder.AbsolutePosition.Y + size.Y - rootFrame.AbsolutePosition.Y
end
-- button sizes (design px); on a phone-sized screen (scale < COMPACT, down to the 0.62 floor) every touch target is
-- 72 px = 44.6 pt at 0.62
local function hudMetrics(compact: boolean): { [string]: number }
	if compact then return { h = 96, btn = 72, board = 118, view = 108, cancel = 124, gap = 8, icon = 56, title = 18, sub = 52, w = 680 } end
	return { h = 74, btn = 48, board = 104, view = 96, cancel = 104, gap = 8, icon = 46, title = 12, sub = 40, w = 620 }
end
DriveController.hudMetrics = hudMetrics
local function layoutHud(h: Hud)
	local mtr = hudMetrics(h.compact)
	h.panel.Size = UDim2.fromOffset(mtr.w, mtr.h)
	h.icon.Size = UDim2.fromOffset(mtr.icon, mtr.icon)
	h.icon.Position = UDim2.new(0, 14, 0.5, -mtr.icon / 2)
	h.title.Position = UDim2.fromOffset(mtr.icon + 26, mtr.title)
	h.sub.Position = UDim2.fromOffset(mtr.icon + 26, mtr.sub)
	h.board.Size = UDim2.fromOffset(mtr.board, mtr.btn)
	h.view.Size = UDim2.fromOffset(mtr.view, mtr.btn)
	h.cancel.Size = UDim2.fromOffset(mtr.cancel, mtr.btn)
	h.cancel.Position = UDim2.new(1, -12, 0.5, 0)
	lastHudText = "" -- re-run the text / button layout
end
local function ensureHud(): Hud?
	if hud then return hud end
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return nil end
	local gui = Instance.new("ScreenGui")
	gui.Name = "DriveHUD"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = DriveController.HUD_ORDER
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local rootFrame = Instance.new("Frame")
	rootFrame.Name = "Root"
	rootFrame.BackgroundTransparency = 1
	rootFrame.Size = UDim2.fromScale(1, 1)
	rootFrame.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = rootFrame
	local panel = Kit.panel(rootFrame, UDim2.fromOffset(620, 74), UDim2.new(0.5, 0, 0, 10))
	panel.Name = "RidePanel"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	local icon = Kit.frame(panel, UDim2.fromOffset(46, 46), UDim2.new(0, 14, 0.5, -23))
	icon.Name = "Icon"
	icon.BackgroundTransparency = 0
	icon.BackgroundColor3 = Color3.fromRGB(236, 160, 64)
	Kit.corner(icon, 23)
	local glyph = PhoneKit.glyph(icon, "driver", 28)
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	local title = Kit.text(panel, "", 19, F.bold, C.text)
	title.Name = "Title"
	title.AutomaticSize = Enum.AutomaticSize.None
	title.Size = UDim2.new(1, -330, 0, 26)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	local sub = Kit.text(panel, "", 15, F.regular, C.muted)
	sub.Name = "Sub"
	sub.AutomaticSize = Enum.AutomaticSize.None
	sub.Size = UDim2.new(1, -330, 0, 22)
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	local board = Kit.button(panel, "Get in", "primary", UDim2.fromOffset(104, 48))
	board.Name = "Board"
	board.AnchorPoint = Vector2.new(1, 0.5)
	board.Selectable = true
	local view = Kit.button(panel, "View", "secondary", UDim2.fromOffset(96, 48))
	view.Name = "View"
	view.AnchorPoint = Vector2.new(1, 0.5)
	view.Selectable = true
	local cancel = Kit.button(panel, "Cancel", "danger", UDim2.fromOffset(104, 48))
	cancel.Name = "Cancel"
	cancel.AnchorPoint = Vector2.new(1, 0.5)
	cancel.Selectable = true
	Kit.onClick(board, function()
		if busy then return end
		busy = true
		task.spawn(function()
			local res = invoke({ action = "ride", op = "board" })
			busy = false
			if not res.ok then Toast.show("error", if res.err == "TOO_FAR" then "Step closer to the car." else DriveController.message(res.err)) end
		end)
	end)
	Kit.onClick(cancel, function()
		if busy then return end
		busy = true
		task.spawn(function()
			local res = invoke({ action = "ride", op = "cancel" })
			busy = false
			if not res.ok then Toast.show("error", DriveController.message(res.err)) end
		end)
	end)
	Kit.onClick(view, function()
		cameraMode = if cameraMode == "orbit" then "inside" else "orbit"
		view.Text = if cameraMode == "orbit" then "View" else "Outside"
	end)
	gui.Parent = pg
	local h: Hud = { gui = gui, root = rootFrame, panel = panel, icon = icon, title = title, sub = sub, board = board, cancel = cancel, view = view, scale = scale,
		compact = false, top = 10 }
	layoutHud(h)
	hud = h
	return h
end
-- the HUD's scale follows the screen (checked every frame: rotation, window size)
local function rescaleHud(h: Hud)
	local sc = hudScale(h.gui)
	if sc == h.scale.Scale then return end
	h.scale.Scale = sc
	h.root.Size = UDim2.fromScale(1 / sc, 1 / sc)
	local compact = sc < DriveController.COMPACT
	if compact ~= h.compact then h.compact = compact; layoutHud(h) end
	h.top = -1 -- re-place below a toast at the new scale
end
local function closeHud()
	if hud then hud.gui:Destroy(); hud = nil end
	lastHudText = ""
end
-- the panel follows the toast stack (checked every frame: a few property reads)
local function placeHud(h: Hud)
	rescaleHud(h)
	local target = DriveController.hudTop(toastBottom(h.root), h.scale.Scale)
	if math.abs(target - h.top) > 0.5 then
		h.top = target
		Kit.tween(h.panel, 0.2, { Position = UDim2.new(0.5, 0, 0, target) })
	end
end
-- ride segment of the founder (the one with "R" on a seat that ends at To)
local function rideSeg(v: RideView): Drive.Seg?
	local segs = v.segs
	if not segs then return nil end
	local to = v.folder:GetAttribute("To")
	for _, sg in segs do
		if sg.to == to and string.find(sg.who, "R", 1, true) then return sg end
	end
	return nil
end
local function layoutButtons(h: Hud, showBoard: boolean, showView: boolean)
	local mtr = hudMetrics(h.compact)
	h.board.Visible = showBoard
	h.view.Visible = showView
	-- buttons from the right: Cancel, then View / Get in; the texts use the rest of the panel
	local x = 12 + mtr.cancel + mtr.gap
	if showView then h.view.Position = UDim2.new(1, -x, 0.5, 0); x += mtr.view + mtr.gap end
	if showBoard then h.board.Position = UDim2.new(1, -x, 0.5, 0); x += mtr.board + mtr.gap end
	local left = mtr.icon + 26
	h.title.Size = UDim2.new(1, -(left + x + 4), 0, 26)
	h.sub.Size = UDim2.new(1, -(left + x + 4), 0, 22)
end
local function updateHud(v: RideView?, t: number)
	if not v then
		-- a booked ride that waits for the first free car (DriverService publishes DriveQueue = expected arrival)
		local q = player:GetAttribute("DriveQueue")
		if typeof(q) ~= "number" then closeHud(); return end
		local h = ensureHud()
		if not h then return end
		h.gui.Enabled = sheet == nil
		placeHud(h)
		local toName = player:GetAttribute("DriveQueueTo")
		local to = if typeof(toName) == "string" then (string.gsub(toName, " %b()$", "")) else "your destination"
		local title = "Booked · next free car in about " .. Drive.clock(math.max(0, q - t))
		local sub = "Every car is out · then to " .. to
		local text = title .. "|" .. sub .. "queued"
		if text ~= lastHudText then
			lastHudText = text
			h.title.Text = title
			h.sub.Text = sub
			h.cancel.Text = "Cancel"
			layoutButtons(h, false, false)
		end
		return
	end
	local st = v.folder:GetAttribute("State")
	if st ~= "coming" and st ~= "waiting" and st ~= "riding" then closeHud(); return end
	local h = ensureHud()
	if not h then return end
	h.gui.Enabled = sheet == nil -- the destination sheet shows the same ride on top
	placeHud(h)
	local toName = v.folder:GetAttribute("ToName")
	local to = if typeof(toName) == "string" and toName ~= "" then (string.gsub(toName, " %b()$", "")) else "your destination"
	local pickupId = v.folder:GetAttribute("Pickup")
	local pickup = if typeof(pickupId) == "string" then Drive.place(pickupId, v.plot) else nil
	local title, sub = "", ""
	local showBoard, showView = false, false
	if st == "coming" then
		local segs = v.segs
		local arrive = if segs and #segs > 0 then Drive.segEnd(segs[#segs], v.plot) else t
		title = "Your driver is on the way · " .. Drive.clock(math.max(0, arrive - t))
		sub = "Pick-up: " .. (if pickup then pickup.name else "nearby") .. " · then to " .. to
	elseif st == "waiting" then
		-- short enough for a phone with the "Get in" button beside it ("Your car is at the HQ entrance")
		local where = if not pickup then "the pick-up" elseif pickup.kind == "limo" then "the stand" else (string.gsub(Drive.atName(pickup), " %b()$", ""))
		title = (if v.folder:GetAttribute("Kind") == "limo" then "Your limousine is at " else "Your car is at ") .. where
		local waitUntil = v.folder:GetAttribute("WaitUntil")
		local left = if typeof(waitUntil) == "number" then math.max(0, waitUntil - t) else 0
		local character = player.Character
		local r = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local car = v.car
		local near = r ~= nil and r:IsA("BasePart") and car ~= nil and Drive.flat(r.Position, (car.at or car.root.CFrame).Position) <= Drive.BOARD_RADIUS
		showBoard = near
		sub = (if near then "Get in" else "Walk to the car (marked)") .. " · it waits " .. Drive.clock(left) .. " more · to " .. to
	else
		local sg = rideSeg(v)
		local arrive = if sg then Drive.segEnd(sg, v.plot) else t
		title = Drive.hudText(to, math.max(0, arrive - t))
		local d = v.folder:GetAttribute("Driver")
		local company = v.company
		local name = if company and typeof(d) == "number" then company:GetAttribute("DriverName" .. d) else nil
		sub = if typeof(name) == "string" then "Driver: " .. name elseif v.folder:GetAttribute("Kind") == "limo" then "VIP limousine · Port Meridian" else "Company car"
		showView = true
	end
	local text = title .. "|" .. sub .. tostring(showBoard) .. tostring(showView)
	if text ~= lastHudText then
		lastHudText = text
		h.title.Text = title
		h.sub.Text = sub
		h.cancel.Text = if st == "riding" then "Let me out" else "Cancel"
		layoutButtons(h, showBoard, showView)
	end
end
-- "Your car" marker over the founder's waiting car (owner-only: this client draws it only for his own ride)
local marker: BillboardGui? = nil
local function updateMarker(v: RideView?)
	local car = if v then v.car else nil
	local show = v ~= nil and car ~= nil and v.folder:GetAttribute("State") == "waiting"
	if not show then
		if marker then marker:Destroy(); marker = nil end
		return
	end
	local c = car :: Car
	if marker and marker.Adornee == c.focus then return end
	if marker then marker:Destroy() end
	local b = Instance.new("BillboardGui")
	b.Name = "YourCarMarker"
	b.AlwaysOnTop = true
	b.Size = UDim2.fromOffset(150, 40)
	b.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
	b.LightInfluence = 0
	b.MaxDistance = 400
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(236, 160, 64)
	label.BackgroundTransparency = 0.05
	label.TextColor3 = Color3.fromRGB(20, 22, 26)
	label.Font = F.bold
	label.TextSize = 18
	label.Text = if c.look == "limo" then "Your limousine" else "Your car"
	label.Parent = b
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	b.Adornee = c.focus
	b.Parent = c.model
	marker = b
end

------------------------------------------------------------------------------------------------ camera
local function hideHead(car: Car, hide: boolean)
	-- "View" from the back seat: the local founder clone's head and accessories (hair, hats) would fill the screen
	for _, p in hiddenHead do if p.Parent then p.LocalTransparencyModifier = 0 end end
	table.clear(hiddenHead)
	if not hide then return end
	for _, s in car.seats do
		if s.code == "R" then
			for _, d in s.model:GetDescendants() do
				if d:IsA("BasePart") and (d.Name == "Head" or d:FindFirstAncestorOfClass("Accessory") ~= nil) then
					d.LocalTransparencyModifier = 1
					table.insert(hiddenHead, d)
				end
			end
		end
	end
end
local function insideCF(car: Car): CFrame
	if car.mesh then return CFrame.new(0, 3.95, MESH.seats.rearR[3] + 0.2) * CFrame.Angles(math.rad(-4), 0, 0) end
	local seats = Drive.seatsOf(car.look)
	local rz = (seats.rearR or CFrame.new(0, 0, 3)).Position.Z
	return CFrame.new(0, Drive.CAMERA.inside.Position.Y, rz + 0.1) * Drive.CAMERA.inside.Rotation
end
DriveController.insideCF = insideCF
local function updateCamera(v: RideView?)
	local cam = workspace.CurrentCamera
	if not cam then return end
	local riding = v ~= nil and v.car ~= nil and v.folder:GetAttribute("State") == "riding"
	if riding and v and v.car then
		local car = v.car :: Car
		if cameraMode == "inside" then
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CFrame = (car.at or car.root.CFrame) * insideCF(car)
			if #hiddenHead == 0 then hideHead(car, true) end
		else
			if #hiddenHead > 0 then hideHead(car, false) end
			if cam.CameraType ~= Enum.CameraType.Custom then cam.CameraType = Enum.CameraType.Custom end
			if cam.CameraSubject ~= car.focus then cam.CameraSubject = car.focus end
		end
		cameraBound = true
	elseif cameraBound then
		table.clear(hiddenHead)
		releaseCamera()
	end
end

------------------------------------------------------------------------------------------------ frame step
-- kerb-side rear door of the founder's mesh limousine: open while he gets in (the door delay) and gets out
local function doorOpen(v: RideView, t: number): number
	local sg = rideSeg(v)
	if not sg then return 0 end
	local function ramp(a: number, b: number): number
		if t <= a or t >= b then return 0 end
		local x = math.min(t - a, b - t, 0.6) / 0.6
		return x * x * (3 - 2 * x)
	end
	local rideEnd = Drive.segEnd(sg, v.plot)
	return math.max(ramp(sg.t0 - Drive.BOARD_DELAY, sg.t0 - 0.1), ramp(rideEnd + 0.2, rideEnd + 3.8))
end
-- One frame: pose every ride near the camera, the waiting drivers, the idle fleet cars and the stand, the HUD and the
-- camera. (Exposed for headless tests and previews: the mock never fires frame signals.)
function DriveController.step(t: number?)
	local time = t or now()
	local cam = cameraPos()
	local list = collect()
	local busyBy: { [Folder]: { [number]: boolean } } = {}
	local garageBusy: { [Folder]: boolean } = {}
	local ranked: { { v: RideView, d: number } } = {}
	mine = nil
	table.clear(live)
	for _, v in list do
		local d = v.folder:GetAttribute("Driver")
		if v.company and typeof(d) == "number" and d > 0 then
			local map = busyBy[v.company :: Folder] or {}
			map[d] = true
			busyBy[v.company :: Folder] = map
		end
		local own = isMine(v)
		if own then mine = v end
		-- a ride whose places are far from the camera is not even decoded (no routing for it on this client)
		local pose = if own or not farFrom(v, cam) then poseOf(v, time) else nil
		v.pose = pose
		if pose then
			if v.company and inGarage(v, pose) then garageBusy[v.company :: Folder] = true end
			table.insert(ranked, { v = v, d = if own then -1 else (pose.cf.Position - cam).Magnitude })
		elseif v.car then
			retire(v)
		end
	end
	table.sort(ranked, function(a, b) return a.d < b.d end)
	local w = world
	for i, item in ranked do
		local v = item.v
		local pose = v.pose :: Drive.Pose
		if (item.d > DriveController.NEAR or i > DriveController.MAX_CARS) and item.d >= 0 then
			destroyCar(v)
			continue
		end
		local look = v.folder:GetAttribute("Look")
		local lk = if typeof(look) == "string" and SHAPES[look] then look else "fleet"
		local car = v.car
		if car and car.look ~= lk then destroyCar(v); car = nil end
		if not car and w then
			local company = v.company
			local name = if company then company:GetAttribute("Company") else nil
			local newCar = buildCar(lk, liveryOf(v), if typeof(name) == "string" then name else "")
			newCar.model.Name = "DriveCar_" .. v.folder.Name
			newCar.model.Parent = w
			v.car = newCar
			car = newCar
		end
		if car then
			car.speed = pose.speed
			if car.mesh then car.door = if isMine(v) then doorOpen(v, time) else 0 end
			placeCar(car, pose.cf)
			meshLod(car, item.d)
			syncSeats(car, v, pose, item.d <= DriveController.SEAT_NEAR, time)
			table.insert(live, { cf = pose.cf, length = lengthOf(lk), width = if lk == "limo" then Drive.CAR_WIDTH.limo else Drive.CAR_WIDTH.fleet, speed = pose.speed })
		end
	end
	stepGhosts(cam)
	stepPosts(time, cam, busyBy)
	stepDepots(cam, garageBusy)
	stepStand(time, cam)
	flush()
	updateHud(mine, time)
	updateMarker(mine)
	updateCamera(mine)
end
-- The company cars drawn this frame (pivot CFrame at ground level, -Z forward; length / width in studs; speed in
-- studs/s) - for CityLifeController to treat them as leaders / obstacles (read-only, rebuilt every frame).
function DriveController.liveCars(): { LiveCar }
	return live
end

------------------------------------------------------------------------------------------------ destination sheet
local function closeSheet()
	if sheet then sheet.gui:Destroy(); sheet = nil end
end
DriveController.closeSheet = closeSheet
local function book(id: string, title: string)
	if busy then return end
	busy = true
	task.spawn(function()
		local res = invoke({ action = "ride", op = "request", to = id })
		busy = false
		if res.ok then
			closeSheet()
			pcall(function()
				local Phone = require(UI.Screens.Phone) :: any
				Phone.close()
			end)
			local where = if typeof(res.pickupAt) == "string" then res.pickupAt elseif typeof(res.pickupName) == "string" then res.pickupName else "you"
			if res.queued then
				Toast.show("info", "Booked " .. title .. ". The next free car comes to " .. where .. " in about " .. Drive.clock(tonumber(res.eta) or 0) .. ".", 6)
			else
				Toast.show("success", "Booked " .. title .. ". The car is at " .. where .. " in " .. Drive.clock(tonumber(res.eta) or 0) .. ".", 6)
			end
		else
			Toast.show("error", if typeof(res.text) == "string" then res.text else DriveController.message(res.err))
		end
	end)
end
-- payload: {title, text, state, rideId?, zone, pickup?, pickupName?, nearestName?, nearestDist?, canBook,
-- places = {{id, title, sub?, eta?}}} (eta nil = no pick-up point near the founder: the row only shows where to)
function DriveController.openSheet(payload: { [string]: any })
	closeSheet()
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "DriveSheet"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = DriveController.SHEET_ORDER
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Parent = pg
	local compact = hudScale(gui) < DriveController.COMPACT
	local tap = if compact then 72 else 48
	local rootFrame = Instance.new("Frame")
	rootFrame.Name = "Root"
	rootFrame.BackgroundTransparency = 1
	rootFrame.Size = UDim2.fromScale(1, 1)
	rootFrame.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = rootFrame
	local shade = Kit.blocker(rootFrame, C.black, 0.55)
	shade.Name = "Shade"
	Kit.onClick(shade, closeSheet)
	local panel = Kit.panel(rootFrame, UDim2.new(0, 560, 1, -24), UDim2.fromScale(0.5, 0.5))
	panel.Name = "Sheet"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	local maxH = Instance.new("UISizeConstraint")
	maxH.MaxSize = Vector2.new(560, 640)
	maxH.Parent = panel
	local headH = if compact then 80 else 64
	local head = Kit.frame(panel, UDim2.new(1, 0, 0, headH))
	head.Name = "Head"
	local icon = Kit.frame(head, UDim2.fromOffset(44, 44), UDim2.new(0, 16, 0.5, -22))
	icon.BackgroundTransparency = 0
	icon.BackgroundColor3 = Color3.fromRGB(236, 160, 64)
	Kit.corner(icon, 22)
	local glyph = PhoneKit.glyph(icon, "driver", 26)
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	local title = Kit.text(head, if typeof(payload.title) == "string" then payload.title else "Driver", 22, F.display, C.text)
	title.Name = "Title"
	title.Position = UDim2.fromOffset(72, headH / 2 - 24)
	local active = payload.state == "coming" or payload.state == "waiting" or payload.state == "riding" or payload.state == "queued"
	local headline = if payload.state == "riding" then "On the way" elseif payload.state == "waiting" then "Your car is waiting"
		elseif payload.state == "coming" then "Your car is coming" elseif payload.state == "queued" then "Booked - next free car"
		elseif typeof(payload.pickupName) == "string" then "Pick-up: " .. payload.pickupName
		elseif typeof(payload.nearestName) == "string" then "Walk to " .. payload.nearestName .. " first" else "No pick-up point nearby"
	local pick = Kit.text(head, headline, 15, F.medium, C.muted)
	pick.Name = "Pickup"
	pick.Position = UDim2.fromOffset(72, headH / 2 + 4)
	local close = Kit.button(head, "×", "ghost", UDim2.fromOffset(tap, tap))
	close.Name = "Close"
	close.TextSize = 30
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -8, 0.5, 0)
	close.Selectable = true
	Kit.onClick(close, closeSheet)
	local text = Kit.para(panel, if typeof(payload.text) == "string" then payload.text else "", 16, C.text)
	text.Name = "Status"
	text.AutomaticSize = Enum.AutomaticSize.None
	text.Position = UDim2.fromOffset(18, headH + 6)
	text.Size = UDim2.new(1, -36, 0, 44)
	text.TextWrapped = true
	text.TextTruncate = Enum.TextTruncate.AtEnd
	text.TextYAlignment = Enum.TextYAlignment.Top
	local cancelH = if compact then 72 else 52
	local cancel = Kit.button(panel, if payload.state == "riding" then "Let me out here" else "Cancel ride", "danger", UDim2.new(1, -36, 0, cancelH))
	cancel.Name = "CancelRide"
	cancel.AnchorPoint = Vector2.new(0.5, 1)
	cancel.Position = UDim2.new(0.5, 0, 1, -14)
	cancel.Visible = active
	cancel.Selectable = true
	Kit.onClick(cancel, function()
		if busy then return end
		busy = true
		task.spawn(function()
			local res = invoke({ action = "ride", op = "cancel", rideId = payload.rideId })
			busy = false
			if res.ok then closeSheet(); Toast.show("info", "Ride cancelled.") else Toast.show("error", DriveController.message(res.err)) end
		end)
	end)
	local places = if typeof(payload.places) == "table" then payload.places else {}
	local listTop = headH + 56
	local list = Kit.scroll(panel, UDim2.new(1, -20, 1, if active then -(listTop + cancelH + 24) else -(listTop + 12)), UDim2.fromOffset(10, listTop))
	list.Name = "Places"
	list.Visible = #places > 0 or not active
	if not list.Visible then panel.Size = UDim2.fromOffset(560, headH + 56 + cancelH + 28) end -- a ride to manage only: a compact card
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	local col = Kit.frame(list, UDim2.new(1, -8, 0, 0))
	col.AutomaticSize = Enum.AutomaticSize.Y
	Kit.list(col, 6)
	local first: GuiObject? = nil
	local canBook = payload.canBook == true
	for i, it in places do
		if typeof(it) ~= "table" or typeof(it.id) ~= "string" then continue end
		local row = Instance.new("TextButton")
		row.Name = "Place_" .. it.id
		row.Text = ""
		row.AutoButtonColor = canBook
		row.Size = UDim2.new(1, 0, 0, if compact then 72 else 68)
		row.LayoutOrder = i
		row.BackgroundColor3 = C.panel2
		row.BackgroundTransparency = if canBook then 0 else 0.4
		row.BorderSizePixel = 0
		row.Selectable = canBook
		Kit.corner(row, 12)
		row.Parent = col
		local hasEta = typeof(it.eta) == "number"
		local textW = if hasEta then -130 else -32
		local t1 = Kit.text(row, tostring(it.title or it.id), 19, F.bold, if canBook then C.text else C.muted)
		t1.AutomaticSize = Enum.AutomaticSize.None
		t1.Position = UDim2.fromOffset(16, 9)
		t1.Size = UDim2.new(1, textW, 0, 26)
		t1.TextTruncate = Enum.TextTruncate.AtEnd
		local t2 = Kit.text(row, tostring(it.sub or ""), 15, F.regular, C.muted)
		t2.AutomaticSize = Enum.AutomaticSize.None
		t2.Position = UDim2.fromOffset(16, 38)
		t2.Size = UDim2.new(1, textW, 0, 20)
		t2.TextTruncate = Enum.TextTruncate.AtEnd
		if hasEta then
			-- a duration from now ("in 4:55"), not a clock time
			local eta = Kit.text(row, "in " .. Drive.clock(it.eta), 19, F.bold, if canBook then C.good else C.muted)
			eta.Name = "Eta"
			eta.AutomaticSize = Enum.AutomaticSize.None
			eta.AnchorPoint = Vector2.new(1, 0)
			eta.Position = UDim2.new(1, -16, 0, 9)
			eta.Size = UDim2.fromOffset(104, 26)
			eta.TextXAlignment = Enum.TextXAlignment.Right
			local cap = Kit.text(row, "door to door", 13, F.regular, C.dim)
			cap.Name = "EtaCaption"
			cap.AutomaticSize = Enum.AutomaticSize.None
			cap.AnchorPoint = Vector2.new(1, 0)
			cap.Position = UDim2.new(1, -16, 0, 38)
			cap.Size = UDim2.fromOffset(104, 18)
			cap.TextXAlignment = Enum.TextXAlignment.Right
		end
		local id: string = it.id
		local label = tostring(it.title or id)
		if canBook then
			row.Activated:Connect(function() book(id, string.lower(string.sub(label, 1, 1)) .. string.sub(label, 2)) end)
		end
		if not first and canBook then first = row end
	end
	if #places == 0 then
		local none = Kit.para(col, "No destinations from here.", 16, C.muted)
		none.Name = "Empty"
	end
	local function rescale()
		local sc = hudScale(gui)
		scale.Scale = sc
		rootFrame.Size = UDim2.fromScale(1 / sc, 1 / sc)
	end
	rescale()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	sheet = { gui = gui, scale = scale, list = list, title = title, text = text, cancel = cancel }
	if UserInputService.GamepadEnabled then GuiService.SelectedObject = first or close end
end

------------------------------------------------------------------------------------------------ init
function DriveController.init()
	local w = Instance.new("Folder")
	w.Name = "DriveCars"
	w.Parent = workspace
	world = w
	task.spawn(function()
		local r = ReplicatedStorage:WaitForChild("CompanyDrivers", 30)
		if r and r:IsA("Folder") then root = r end
	end)
	State.onNotify(function(kind: string, payload: { [string]: any })
		if kind == "DRIVE_SHEET" and typeof(payload) == "table" then DriveController.openSheet(payload) end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if input.KeyCode == Enum.KeyCode.ButtonB and sheet then closeSheet() end
		local _ = processed
	end)
	RunService.RenderStepped:Connect(function()
		local ok, err = pcall(function() DriveController.step(nil) end)
		if not ok then warn("[Drive] " .. tostring(err)) end
	end)
end

-- test seams
function DriveController._setRoot(r: Folder?, w: Folder?)
	root = r
	world = w
end
function DriveController._views(): { [Folder]: RideView } return views end
function DriveController._posts(): { [string]: Post } return posts end
function DriveController._idle(): (Car?, Post?) return idleLimo, idleChauffeur end
function DriveController._hud(): any return hud end
function DriveController._sheet(): any return sheet end
function DriveController._ghosts(): { Car } return ghosts end
function DriveController._depots(): { [Folder]: Car } return depots end
function DriveController._marker(): BillboardGui? return marker end

return DriveController
