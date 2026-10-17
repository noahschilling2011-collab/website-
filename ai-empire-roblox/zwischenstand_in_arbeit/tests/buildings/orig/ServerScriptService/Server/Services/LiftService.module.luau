--!strict
-- One physical, multi-passenger lift per headquarters (geometry: CoreDesign, SPEC §4).
--
-- Transport and trade-offs:
--  * The cabin is a real assembly: every cabin part is welded to CabinFloor (door leaves through
--    a Weld whose C0 slides them), the floor rides a PrismaticConstraint servo on the anchored
--    LiftGuide and the server owns its physics. Riders stand on the floor and are carried by the
--    engine: no PivotTo, no anchoring, no WalkSpeed/JumpPower changes, so players and NPCs can walk
--    in and out, ride together and leave at any open stop. Cost: a client sees the server-owned
--    cabin with replication delay, so fast moves can jitter; vmax 10 studs/s and 6 studs/s² keep
--    that small, and the passenger box tolerates the lag (y -4..10 above the floor).
--  * TargetPosition follows a trapezoidal profile computed at the service tick (~20 Hz). Servo
--    Speed = vmax + 1 and a moderate LinearResponsiveness smooth the 20 Hz steps; arrival means
--    CurrentPosition within 0.1 stud for 0.2 s, and only then can doors open.
--  * Collision groups: LiftCabin never collides with LiftShaft (shaft walls, landing doors, sills,
--    pit, head house). Safety net: attach also moves any other collidable Default-group part that
--    intrudes into the swept cabin volume into LiftShaft (warned once), so a mis-built slab edge
--    cannot jam the cabin; characters still collide with those parts.
--  * Scheduling, door state machine and NPC tickets live in the pure, unit-tested LiftLogic:
--    collective SCAN over deduplicated hall/car call sets, door zone safety (never closes on
--    anyone), overload hold, FIFO NPC boarding that keeps 2 slots for players waiting in the lobby.
--  * NPCs are never moved by this service: a ticket exposes a target the navigation walks to.
--  * Emergency evacuation is the only teleport: detach (before an office rebuild) and a cabin
--    declared out of service after repeated stalls move player riders to the nearest landing exit.
--  * Rights: calls need authorize(player, ownerId); opening the doors at the current stop is always
--    allowed for riders (egress), and arriving cabins always open, so nobody can be trapped.
--  * tick() is self-healing: it attaches built offices it does not know yet (Plot.all, required
--    lazily because PlotService requires this module), forgets destroyed offices, and never errors.
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Plan = require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Logic = require(script.Parent.LiftLogic)
local Sound = require(script.Parent.CampusSoundService)
local Remote = require(script.Parent.Parent.Lib.Remote)

local Lift = {}

local CABIN_GROUP, SHAFT_GROUP = "LiftCabin", "LiftShaft"
local DOOR_ZONE = { x1 = -4.5, x2 = 4.5, z1 = 51.5, z2 = 57.5 } -- building-local, y level-1..level+7
local LOBBY = { x1 = -22, x2 = 22, z1 = 36, z2 = 54 } -- y level-2..level+10
local INSIDE_HALF, INSIDE_LOW, INSIDE_HIGH = 5.6, -4, 10 -- cabin-local, relative to the floor top
local LANDING_RANGE = 14 -- remote hall calls: max distance from a landing
local NEAR_RANGE = 18 -- NPC counts as waiting at the landing within this radius
local RIDER_MASS = 30 -- generous per-rider mass for the servo force
local LIGHT = PhysicalProperties.new(0.1, 0.5, 0, 1, 1)
local ARROWS: { [number]: string } = { [1] = "▲", [-1] = "▼", [0] = "•" }

type Labels = { level: TextLabel?, arrow: TextLabel?, status: TextLabel? }
type Landing = {
	level: number,
	doorL: BasePart,
	doorR: BasePart,
	closedL: CFrame,
	openL: CFrame,
	closedR: CFrame,
	openR: CFrame,
	labels: Labels,
	sound: BasePart,
}
type Leaf = { part: BasePart, weld: Weld?, closed: CFrame, open: CFrame }
type Record = {
	office: Instance,
	cabin: Model,
	floor: BasePart,
	guide: BasePart,
	display: BasePart?,
	prismatic: PrismaticConstraint,
	att0: Attachment,
	att1: Attachment,
	joints: { Instance },
	leaves: { Leaf },
	cabinParts: { BasePart },
	landings: { [number]: Landing },
	labels: Labels,
	cf: CFrame,
	topRel: CFrame,
	ownerId: number,
	tier: number,
	car: Logic.Car,
	tickets: { [Logic.Ticket]: Model },
	tweens: { Tween },
	doorLanding: number?,
	lastDoor: number,
	lastTarget: number,
	texts: { [Instance]: string },
	ownerSet: boolean,
	parented: boolean,
	displayClock: number,
	riders: number,
	lastLevel: number?,
	lastState: string?,
}
type Person = { player: Player, character: Model, root: BasePart }
type Wanted = { rec: Record, level: number, expires: number }

local records: { [Instance]: Record } = {}
local failed: { [Instance]: boolean } = {}
local ticketHome: { [Logic.Ticket]: Record } = {}
local wanted: { [Player]: Wanted } = {} -- destination chosen at a landing, sent as car call on boarding
local warned: { [string]: boolean } = {}
local authorize: (Player, number) -> boolean = function(_player: Player, _owner: number): boolean
	return false
end
local now, sweepClock, healClock = 0, 0, 0
local groupsReady, initialized = false, false

local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn("[Lift] " .. message)
end

local function notify(player: Player, kind: string, payload: { [string]: any })
	pcall(Remote.fire, player, "Notify", kind, payload)
end

local function ensureGroups()
	if groupsReady then
		return
	end
	groupsReady = true
	for _, name in { CABIN_GROUP, SHAFT_GROUP } do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(CABIN_GROUP, SHAFT_GROUP, false)
	end)
end

---------------------------------------------------------------------------- geometry helpers

local function rootOf(model: Instance?): BasePart?
	if not model or not model:IsA("Model") then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return model.PrimaryPart
end

local function aliveModel(model: Instance): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function cabinFrame(rec: Record): CFrame
	return rec.floor.CFrame * rec.topRel
end

local function insideFrame(frame: CFrame, p: Vector3): boolean
	local v = frame:PointToObjectSpace(p)
	return math.abs(v.X) < INSIDE_HALF and math.abs(v.Z) < INSIDE_HALF and v.Y > INSIDE_LOW and v.Y < INSIDE_HIGH
end

local function inBox(v: Vector3, box: { x1: number, x2: number, z1: number, z2: number }, level: number, low: number, high: number): boolean
	local y = Plan.levelY(level)
	return v.X >= box.x1 and v.X <= box.x2 and v.Z >= box.z1 and v.Z <= box.z2 and v.Y >= y + low and v.Y <= y + high
end

local function child(parent: Instance?, name: string): BasePart?
	local p = if parent then parent:FindFirstChild(name, true) else nil
	return if p and p:IsA("BasePart") then p else nil
end

local function cframeAttr(inst: Instance, name: string): CFrame?
	local v = inst:GetAttribute(name)
	return if typeof(v) == "CFrame" then v else nil
end

local function labelsOf(part: Instance?): Labels
	local gui = if part then part:FindFirstChild("Display") else nil
	local function label(name: string): TextLabel?
		local l = if gui then gui:FindFirstChild(name, true) else nil
		return if l and l:IsA("TextLabel") then l else nil
	end
	return { level = label("Level"), arrow = label("Arrow"), status = label("Status") }
end

local function findLanding(folder: Instance, level: number): Instance?
	for _, c in folder:GetChildren() do
		if c:GetAttribute("LiftStop") == level and c:FindFirstChild("DoorL") then
			return c
		end
	end
	return folder:FindFirstChild("Landing_" .. level)
end

-- Parts tagged LiftShaft never collide with the cabin.
local function claimShaft(office: Instance)
	local roots: { Instance } = {}
	for _, name in { "Core", "Lift", "Structure" } do
		local f = office:FindFirstChild(name)
		if f then
			table.insert(roots, f)
		end
	end
	if #roots == 0 then
		roots = { office }
	end
	for _, root in roots do
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("LiftShaft") == true then
				d.CollisionGroup = SHAFT_GROUP
			end
		end
	end
end

-- Safety net: anything collidable left inside the cabin's travel volume joins LiftShaft.
local function clearSweep(rec: Record, low: number, high: number)
	local c = Plan.CABIN
	local lo, hi = Plan.levelY(low) - 0.45, Plan.levelY(high) + c.height - 0.15
	local size = Vector3.new(c.x2 - c.x1 - 0.3, hi - lo, c.z2 - c.z1 - 0.3)
	local center = rec.cf * CFrame.new((c.x1 + c.x2) / 2, (lo + hi) / 2, (c.z1 + c.z2) / 2)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { rec.office }
	local ok, hits = pcall(function(): { BasePart }
		return workspace:GetPartBoundsInBox(center, size, params)
	end)
	if not ok or type(hits) ~= "table" then
		return
	end
	local moved: { string } = {}
	for _, p in hits do
		if p.CanCollide and p.CollisionGroup == "Default" and not p:IsDescendantOf(rec.cabin) and p ~= rec.guide then
			p.CollisionGroup = SHAFT_GROUP
			table.insert(moved, p:GetFullName())
		end
	end
	if #moved > 0 then
		warnOnce("sweep" .. rec.ownerId, string.format("%d part(s) intruded into the lift shaft and no longer collide with the cabin: %s", #moved, table.concat(moved, ", ", 1, math.min(#moved, 5))))
	end
end

---------------------------------------------------------------------------- attach / detach

local function build(office: Instance): (Record?, string?)
	local folder = office:FindFirstChild("Lift")
	if not folder then
		return nil, "Lift folder missing"
	end
	local guide = folder:FindFirstChild("LiftGuide")
	local cabin = folder:FindFirstChild("LiftCabin")
	if not guide or not guide:IsA("BasePart") then
		return nil, "LiftGuide missing"
	end
	if not cabin or not cabin:IsA("Model") then
		return nil, "LiftCabin missing"
	end
	local floor = cabin:FindFirstChild("CabinFloor")
	if not floor or not floor:IsA("BasePart") then
		return nil, "CabinFloor missing"
	end
	local cf, tier, ownerId = office:GetAttribute("CampusCFrame"), office:GetAttribute("OfficeTier"), office:GetAttribute("OwnerUserId")
	if typeof(cf) ~= "CFrame" or typeof(tier) ~= "number" or typeof(ownerId) ~= "number" then
		return nil, "office attributes CampusCFrame/OfficeTier/OwnerUserId missing"
	end
	local leaves: { Leaf } = {}
	for _, name in { "CabinDoorL", "CabinDoorR" } do
		local leaf = child(cabin, name)
		local closed = if leaf then cframeAttr(leaf, "ClosedOffset") else nil
		local opened = if leaf then cframeAttr(leaf, "OpenOffset") else nil
		if not leaf or not closed or not opened then
			return nil, name .. " missing or without ClosedOffset/OpenOffset"
		end
		table.insert(leaves, { part = leaf, weld = nil, closed = closed, open = opened })
	end
	local stops = Plan.liftStops(tier)
	local landings: { [number]: Landing } = {}
	for _, stop in stops do
		local model = findLanding(folder, stop.level)
		local doorL, doorR = child(model, "DoorL"), child(model, "DoorR")
		if not model or not doorL or not doorR then
			return nil, "Landing_" .. stop.level .. " or its doors missing"
		end
		local closedL, openL = cframeAttr(doorL, "ClosedCFrame"), cframeAttr(doorL, "OpenCFrame")
		local closedR, openR = cframeAttr(doorR, "ClosedCFrame"), cframeAttr(doorR, "OpenCFrame")
		if not closedL or not openL or not closedR or not openR then
			return nil, "Landing_" .. stop.level .. " doors without ClosedCFrame/OpenCFrame"
		end
		local indicator = child(model, "Indicator")
		landings[stop.level] = {
			level = stop.level, doorL = doorL, doorR = doorR, closedL = closedL, openL = openL, closedR = closedR,
			openR = openR, labels = labelsOf(indicator), sound = indicator or doorL,
		}
	end

	-- Everything is present: take over the physics.
	ensureGroups()
	claimShaft(office)
	local oldAttachment = guide:FindFirstChild("LiftGuideAttachment")
	if oldAttachment then
		oldAttachment:Destroy()
	end
	local parts: { BasePart } = {}
	local isLeaf: { [BasePart]: boolean } = { [leaves[1].part] = true, [leaves[2].part] = true }
	for _, d in cabin:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		elseif d.Name == "LiftWeld" or d.Name == "LiftLeafWeld" or d.Name == "LiftPrismatic" or d.Name == "LiftFloorAttachment" then
			d:Destroy() -- leftovers of an earlier attach
		elseif d:IsA("WeldConstraint") then
			local p0, p1 = d.Part0, d.Part1
			if (p0 and not p0:IsDescendantOf(cabin)) or (p1 and not p1:IsDescendantOf(cabin)) then
				d:Destroy() -- would pin the cabin to the building
			end
		elseif d:IsA("JointInstance") then
			local p0, p1 = d.Part0, d.Part1
			if (p0 and not p0:IsDescendantOf(cabin)) or (p1 and not p1:IsDescendantOf(cabin)) then
				d:Destroy()
			end
		end
	end
	local joints: { Instance } = {}
	for _, p in parts do
		p.CollisionGroup = CABIN_GROUP
		p.CustomPhysicalProperties = LIGHT
		if p ~= floor and not isLeaf[p] then
			local w = Instance.new("WeldConstraint")
			w.Name = "LiftWeld"
			w.Part0 = floor
			w.Part1 = p
			w.Parent = p
			table.insert(joints, w)
		end
	end
	for _, leaf in leaves do
		local w = Instance.new("Weld")
		w.Name = "LiftLeafWeld"
		w.Part0 = floor
		w.Part1 = leaf.part
		w.C0 = leaf.closed
		w.C1 = CFrame.identity
		w.Parent = leaf.part
		leaf.weld = w
		leaf.part.CanCollide = true
		table.insert(joints, w)
	end

	-- Vertical prismatic axis (attachment X axis = building up); Attachment1 at the floor top centre.
	local up, look = cf.UpVector, cf.LookVector
	local lu = floor.CFrame:VectorToObjectSpace(up)
	local half = 0.5 * (math.abs(lu.X) * floor.Size.X + math.abs(lu.Y) * floor.Size.Y + math.abs(lu.Z) * floor.Size.Z)
	local top = floor.Position + up * half
	local disp = (top - guide.Position):Dot(up)
	local att0 = Instance.new("Attachment")
	att0.Name = "LiftGuideAttachment"
	att0.CFrame = guide.CFrame:ToObjectSpace(CFrame.fromMatrix(top - up * disp, up, look))
	att0.Parent = guide
	local att1 = Instance.new("Attachment")
	att1.Name = "LiftFloorAttachment"
	att1.CFrame = floor.CFrame:ToObjectSpace(CFrame.fromMatrix(top, up, look))
	att1.Parent = floor
	local topY = cf:PointToObjectSpace(top).Y
	local heights: { [number]: number } = {}
	local levels: { number } = {}
	local start, startD = stops[1].level, math.huge
	for _, stop in stops do
		heights[stop.level] = disp + (Plan.levelY(stop.level) - topY)
		table.insert(levels, stop.level)
		local d = math.abs(Plan.levelY(stop.level) - topY)
		if d < startD then
			start, startD = stop.level, d
		end
	end
	local low, high = stops[1].level, stops[#stops].level
	local prismatic = Instance.new("PrismaticConstraint")
	prismatic.Name = "LiftPrismatic"
	prismatic.Attachment0 = att0
	prismatic.Attachment1 = att1
	prismatic.ActuatorType = Enum.ActuatorType.Servo
	prismatic.LimitsEnabled = true
	prismatic.LowerLimit = heights[low] - 0.5
	prismatic.UpperLimit = heights[high] + 0.5
	prismatic.Speed = Logic.VMAX + 1
	prismatic.LinearResponsiveness = 40
	prismatic.ServoMaxForce = 1e6
	prismatic.TargetPosition = disp
	prismatic.Parent = floor
	for _, p in parts do
		p.Anchored = false
	end
	local mass = 0
	pcall(function()
		mass = floor.AssemblyMass
	end)
	if mass <= 0 then
		for _, p in parts do
			pcall(function()
				mass += p:GetMass()
			end)
		end
	end
	prismatic.ServoMaxForce = math.max(2e4, (mass + Plan.CABIN.capacity * RIDER_MASS) * workspace.Gravity * 4)

	local rec: Record = {
		office = office, cabin = cabin, floor = floor, guide = guide, display = child(cabin, "CabinDisplay"),
		prismatic = prismatic, att0 = att0, att1 = att1, joints = joints, leaves = leaves, cabinParts = parts,
		landings = landings, labels = labelsOf(child(cabin, "CabinDisplay")), cf = cf,
		topRel = floor.CFrame:ToObjectSpace(CFrame.new(top) * cf.Rotation), ownerId = ownerId, tier = tier,
		car = Logic.new(levels, heights, start, Plan.CABIN.capacity, disp), tickets = {}, tweens = {},
		doorLanding = nil, lastDoor = 0, lastTarget = disp, texts = {}, ownerSet = false,
		parented = office.Parent ~= nil, displayClock = math.huge, riders = 0, lastLevel = nil, lastState = nil,
	}
	for _, landing in landings do
		landing.doorL.CFrame = landing.closedL
		landing.doorR.CFrame = landing.closedR
		landing.doorL.CanCollide = true
		landing.doorR.CanCollide = true
	end
	if floor:IsDescendantOf(workspace) then
		rec.ownerSet = pcall(function()
			floor:SetNetworkOwner(nil)
		end)
	end
	clearSweep(rec, low, high)
	return rec, nil
end

function Lift.attach(office: Instance): boolean
	if typeof(office) ~= "Instance" then
		return false
	end
	if records[office] then
		return true
	end
	local ok, rec, reason = pcall(build, office)
	if ok and rec then
		records[office] = rec
		failed[office] = nil
		return true
	end
	failed[office] = true
	pcall(function() -- tell people at the landings instead of leaving stale texts
		local folder = office:FindFirstChild("Lift")
		if folder then
			for _, d in folder:GetDescendants() do
				if d:IsA("TextLabel") and d.Name == "Status" then
					d.Text = "Out of service"
				end
			end
		end
	end)
	local owner = office:GetAttribute("OwnerUserId")
	warnOnce("attach" .. tostring(owner) .. tostring(reason or rec), "lift not attached for office of " .. tostring(owner) .. ": " .. tostring(if ok then reason else rec))
	return false
end

local function stopTweens(rec: Record)
	for _, tween in rec.tweens do
		pcall(function()
			tween:Cancel()
		end)
	end
	table.clear(rec.tweens)
end

local function forget(rec: Record, reason: string)
	if records[rec.office] == rec then
		records[rec.office] = nil
	end
	stopTweens(rec)
	for t in rec.tickets do
		Logic.cancel(rec.car, t, reason)
		ticketHome[t] = nil
		t.target = nil
	end
	table.clear(rec.tickets)
	for player, w in wanted do
		if w.rec == rec then
			wanted[player] = nil
		end
	end
end

-- Emergency evacuation (rebuild or out-of-service cabin): the only place that teleports anyone.
local function evacuate(rec: Record)
	local level = Logic.nearestLevel(rec.car, rec.car.position)
	local frame = cabinFrame(rec)
	local slot = 0
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = rootOf(character)
		if character and root and insideFrame(frame, root.Position) then
			slot += 1
			character:PivotTo(rec.cf * CFrame.new(Plan.liftExitPoint(level, slot)))
		end
	end
end

-- Leave the cabin anchored where it is and remove our constraints, so a later attach starts clean.
local function release(rec: Record)
	for _, p in rec.cabinParts do
		if p.Parent then
			p.Anchored = true
		end
	end
	rec.prismatic:Destroy()
	rec.att0:Destroy()
	rec.att1:Destroy()
	for _, j in rec.joints do
		j:Destroy()
	end
end

function Lift.detach(office: Instance)
	failed[office] = nil
	local rec = records[office]
	if not rec then
		return
	end
	pcall(evacuate, rec)
	forget(rec, "detached")
	pcall(release, rec)
end

---------------------------------------------------------------------------- doors, displays, sounds

local function tweenTo(rec: Record, door: BasePart, goal: CFrame, seconds: number)
	if seconds <= 0.02 then
		door.CFrame = goal
		return
	end
	local ok, tween = pcall(function(): Tween
		return TweenService:Create(door, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { CFrame = goal })
	end)
	if ok and tween then
		tween:Play()
		table.insert(rec.tweens, tween)
	else
		door.CFrame = goal
	end
end

local function shutLanding(rec: Record, level: number)
	local landing = rec.landings[level]
	if landing then
		landing.doorL.CFrame = landing.closedL
		landing.doorR.CFrame = landing.closedR
		landing.doorL.CanCollide = true
		landing.doorR.CanCollide = true
	end
end

-- Landing doors follow the cabin doors; they only ever move at the stop where the cabin stands.
local function moveLanding(rec: Record, opening: boolean)
	local level = rec.car.level
	local landing = rec.landings[level]
	stopTweens(rec)
	if rec.doorLanding and rec.doorLanding ~= level then
		shutLanding(rec, rec.doorLanding)
	end
	if not landing then
		return
	end
	rec.doorLanding = level
	local seconds = Logic.DOOR_TIME * (if opening then 1 - rec.car.door else rec.car.door)
	landing.doorL.CanCollide = false
	landing.doorR.CanCollide = false
	tweenTo(rec, landing.doorL, if opening then landing.openL else landing.closedL, seconds)
	tweenTo(rec, landing.doorR, if opening then landing.openR else landing.closedR, seconds)
end

local function leavesCollide(rec: Record, on: boolean)
	for _, leaf in rec.leaves do
		leaf.part.CanCollide = on
	end
end

local function play(part: Instance?, key: string)
	if part then
		pcall(Sound.play, part, key)
	end
end

local function onEvent(rec: Record, event: string)
	local landing = rec.landings[rec.car.level]
	if event == "doorsOpening" or event == "reopen" then
		leavesCollide(rec, false)
		moveLanding(rec, true)
		play(if landing then landing.doorL else nil, "liftDoor")
	elseif event == "doorsClosing" then
		moveLanding(rec, false)
		play(if landing then landing.doorL else nil, "liftDoor")
	elseif event == "closed" then
		stopTweens(rec)
		shutLanding(rec, rec.doorLanding or rec.car.level)
		rec.doorLanding = nil
		leavesCollide(rec, true)
	elseif event == "arrive" then
		play(if landing then landing.sound else nil, "liftChime")
		play(rec.display, "liftChime")
	elseif event == "stall" then
		warnOnce("stall" .. rec.ownerId, "cabin stalled for office of " .. rec.ownerId .. "; returning to the previous stop")
	elseif event == "outOfService" then
		warn("[Lift] cabin out of service for office of " .. rec.ownerId .. " (" .. tostring(rec.car.reason) .. "); evacuating riders")
		pcall(evacuate, rec) -- its tickets are failed now and get released after this step
	end
end

local function setText(rec: Record, label: TextLabel?, text: string)
	if label and rec.texts[label] ~= text then
		rec.texts[label] = text
		label.Text = text
	end
end

local function title(rec: Record, level: number): string
	return Plan.levelLabel(rec.tier, level) .. " · " .. Plan.levelName(rec.tier, level)
end

local function npcWaiting(car: Logic.Car, level: number): boolean
	for _, t in car.tickets do
		if t.state == "waiting" and t.fromLevel == level then
			return true
		end
	end
	return false
end

local function displays(rec: Record)
	local car = rec.car
	local moving = car.state == "MOVING"
	local shown = if moving then Logic.nearestLevel(car, car.position) else car.level
	local label = Plan.levelLabel(rec.tier, shown)
	local arrow = ARROWS[Logic.arrow(car)] or "•"
	local phase = Logic.doorPhase(car)
	local status
	if car.state == "OUT_OF_SERVICE" then
		status = "Out of service"
	elseif car.full then
		status = "FULL – please step out"
	elseif phase == "closing" then
		status = "Doors closing"
	elseif moving and car.target then
		status = title(rec, car.target)
	else
		status = title(rec, car.level)
	end
	setText(rec, rec.labels.level, label)
	setText(rec, rec.labels.arrow, arrow)
	setText(rec, rec.labels.status, status)
	for level, landing in rec.landings do
		local s
		if car.state == "OUT_OF_SERVICE" then
			s = "Out of service"
		elseif not moving and car.level == level and phase ~= "closed" then
			s = if car.full then "FULL" elseif phase == "closing" then "Doors closing" else title(rec, level)
		elseif car.hall[level] or npcWaiting(car, level) then
			s = "Lift called"
		else
			s = title(rec, level)
		end
		setText(rec, landing.labels.level, label)
		setText(rec, landing.labels.arrow, arrow)
		setText(rec, landing.labels.status, s)
	end
end

---------------------------------------------------------------------------- NPC targets

local function targetFor(rec: Record, t: Logic.Ticket, npc: Model?): Vector3?
	local s = t.state
	if s == "waiting" then
		return rec.cf:PointToWorldSpace(Plan.liftWaitPoint(t.fromLevel, t.waitSlot))
	elseif s ~= "board" and s ~= "riding" and s ~= "exit" then
		return nil
	end
	local frame = cabinFrame(rec)
	local slot = Plan.liftCabinSlot(t.slot or 1)
	local root = rootOf(npc)
	local v = if root then rec.cf:PointToObjectSpace(root.Position) else nil
	if s == "board" then
		if root and insideFrame(frame, root.Position) then
			return frame:PointToWorldSpace(slot)
		elseif v and math.abs(v.X) <= 2 and v.Z >= 49.5 then
			return frame:PointToWorldSpace(Vector3.new(0, 3, -2.5)) -- straight through the doorway
		end
		return rec.cf:PointToWorldSpace(Vector3.new(0, Plan.levelY(t.fromLevel) + 3, 50.5)) -- line up in front
	elseif s == "riding" then
		return frame:PointToWorldSpace(slot)
	end
	if v and v.Z > 52.5 then
		return rec.cf:PointToWorldSpace(Vector3.new(0, Plan.levelY(t.toLevel) + 3, 51)) -- out through the doorway
	end
	return rec.cf:PointToWorldSpace(Plan.liftExitPoint(t.toLevel, t.slot or 1))
end

---------------------------------------------------------------------------- tick

local function eachNPC(rec: Record, fn: (Model, BasePart) -> ())
	for _, name in { "Employees", "OperationsEmployees", "Visitors", "Assistant" } do
		local folder = rec.office:FindFirstChild(name)
		if folder then
			for _, npc in folder:GetChildren() do
				local root = rootOf(npc)
				if root and npc:IsA("Model") and aliveModel(npc) then
					fn(npc, root)
				end
			end
		end
	end
end

local function step(rec: Record, dt: number, people: { Person })
	if rec.floor.Parent == nil or (rec.parented and rec.office.Parent == nil) then
		return -- being torn down; the sweep forgets it
	end
	local car = rec.car
	local frame = cabinFrame(rec)
	local level = car.level
	local s = car.state
	local doorsBusy = s == "DOORS_OPENING" or s == "DOORS_OPEN" or s == "DOORS_CLOSING" or s == "REOPENING"
	local occupied, riders, waiting = false, 0, false
	local function observe(root: BasePart, isPlayer: boolean)
		local p = root.Position
		local inside = insideFrame(frame, p)
		if inside then
			riders += 1
		end
		local v = rec.cf:PointToObjectSpace(p)
		if doorsBusy and inBox(v, DOOR_ZONE, level, -1, 7) then
			occupied = true
		end
		if isPlayer and not inside and inBox(v, LOBBY, level, -2, 10) then
			waiting = true
		end
	end
	for _, person in people do
		observe(person.root, true)
	end
	if doorsBusy or next(rec.tickets) ~= nil then
		eachNPC(rec, function(_npc: Model, root: BasePart)
			observe(root, false)
		end)
	end
	rec.riders = riders
	for t, npc in rec.tickets do
		local root = rootOf(npc)
		local alive = npc.Parent ~= nil and root ~= nil and aliveModel(npc) and npc:IsDescendantOf(rec.office)
		t.alive = alive
		if alive and root then
			local p = root.Position
			local v = rec.cf:PointToObjectSpace(p)
			local y = Plan.levelY(t.fromLevel)
			t.inside = insideFrame(frame, p)
			t.zone = inBox(v, DOOR_ZONE, level, -1, 7)
			t.near = Vector3.new(v.X, 0, v.Z - Plan.LIFT_DOOR.z).Magnitude <= NEAR_RANGE and v.Y >= y - 2 and v.Y <= y + 8
		end
	end

	Logic.step(car, dt, now, { position = rec.prismatic.CurrentPosition, occupied = occupied, riders = riders, playersWaiting = waiting })

	if car.cmd ~= rec.lastTarget then
		rec.lastTarget = car.cmd
		rec.prismatic.TargetPosition = car.cmd
	end
	if car.door ~= rec.lastDoor then
		rec.lastDoor = car.door
		for _, leaf in rec.leaves do
			if leaf.weld then
				leaf.weld.C0 = leaf.closed:Lerp(leaf.open, car.door)
			end
		end
	end
	local events = Logic.drain(car)
	for _, event in events do
		onEvent(rec, event)
	end
	for t, npc in rec.tickets do
		if t.state == "done" or t.state == "failed" then
			rec.tickets[t] = nil
			ticketHome[t] = nil
			t.target = nil
		else
			t.target = targetFor(rec, t, npc)
		end
	end
	-- destination picked at a landing becomes a car call once its player is aboard
	if car.state ~= "MOVING" then
		for player, w in wanted do
			if w.rec == rec then
				local root = rootOf(player.Character)
				if root and insideFrame(frame, root.Position) then
					wanted[player] = nil
					Lift.carCall(player, rec.office, w.level)
				end
			end
		end
	end
	rec.displayClock += dt
	if rec.displayClock >= 0.2 or #events > 0 then
		rec.displayClock = 0
		displays(rec)
	end
	if rec.lastLevel ~= car.level then
		rec.lastLevel = car.level
		rec.cabin:SetAttribute("CurrentLevel", car.level)
	end
	if rec.lastState ~= car.state then
		rec.lastState = car.state
		rec.cabin:SetAttribute("LiftState", car.state)
	end
end

local function geometricPosition(rec: Record): number
	return (rec.att1.WorldCFrame.Position - rec.att0.WorldCFrame.Position):Dot(rec.att0.WorldAxis)
end

local function sweep()
	for office, rec in records do
		if office.Parent ~= nil then
			rec.parented = true
		end
		local gone = (rec.parented and office.Parent == nil) or rec.floor.Parent == nil or not rec.floor:IsDescendantOf(office)
			or rec.guide.Parent == nil or rec.prismatic.Parent == nil
		if gone then
			forget(rec, "office removed")
		else
			if not rec.ownerSet and rec.floor:IsDescendantOf(workspace) then
				rec.ownerSet = pcall(function()
					rec.floor:SetNetworkOwner(nil)
				end)
			end
			-- diagnostics: the servo reading must agree with the cabin's real position
			local geometric = geometricPosition(rec)
			if math.abs(geometric - rec.prismatic.CurrentPosition) > 1.5 and rec.prismatic.Active then
				warnOnce("position" .. rec.ownerId, string.format("servo CurrentPosition %.2f disagrees with the cabin geometry %.2f", rec.prismatic.CurrentPosition, geometric))
			end
		end
	end
	for office in failed do
		if office.Parent == nil then
			failed[office] = nil
		end
	end
	for player, w in wanted do
		if player.Parent == nil or w.expires < now or records[w.rec.office] ~= w.rec then
			wanted[player] = nil
		end
	end
	for t, rec in ticketHome do
		if records[rec.office] ~= rec then
			ticketHome[t] = nil
			if t.state ~= "done" then
				t.state = "failed"
			end
			t.target = nil
		end
	end
end

local function heal()
	local ok, plot = pcall(function(): any
		return require(script.Parent.PlotService) :: any
	end)
	if not ok or type(plot) ~= "table" or type(plot.all) ~= "function" then
		return
	end
	local okAll, list = pcall(plot.all)
	if not okAll or type(list) ~= "table" then
		return
	end
	for _, p in list do
		local office = if type(p) == "table" then p.office else nil
		if typeof(office) == "Instance" and office.Parent ~= nil and not records[office] and not failed[office] then
			Lift.attach(office)
		end
	end
end

function Lift.tick(dt: number)
	if type(dt) ~= "number" or dt ~= dt or dt <= 0 then
		return
	end
	dt = math.min(dt, 0.25)
	now += dt
	sweepClock += dt
	healClock += dt
	if sweepClock >= 1 then
		sweepClock = 0
		pcall(sweep)
	end
	if healClock >= 2 then
		healClock = 0
		pcall(heal)
	end
	local people: { Person } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = rootOf(character)
		if character and root and aliveModel(character) then
			table.insert(people, { player = player, character = character :: Model, root = root })
		end
	end
	for _, rec in records do
		local ok, err = pcall(function(): any
			step(rec, dt, people)
			return nil
		end)
		if not ok then
			warnOnce("step" .. rec.ownerId .. tostring(err), "tick failed for office of " .. rec.ownerId .. ": " .. tostring(err))
		end
	end
end

function Lift.init(check: (Player, number) -> boolean)
	authorize = check
	ensureGroups()
	if not initialized then
		initialized = true
		Players.PlayerRemoving:Connect(function(player: Player)
			wanted[player] = nil
		end)
	end
end

---------------------------------------------------------------------------- calls (players)

local function recordFor(office: Instance?): Record?
	if typeof(office) ~= "Instance" then
		return nil
	end
	local rec = records[office]
	if not rec and not failed[office] and office.Parent ~= nil and Lift.attach(office) then
		rec = records[office]
	end
	return rec
end

local function validLevel(rec: Record, level: any): boolean
	return type(level) == "number" and level == math.floor(level) and rec.car.heights[level] ~= nil
end

local function callError(err: string): string
	return if err == "OUT_OF_SERVICE" then "LIFT_OUT_OF_SERVICE" elseif err == "BAD_LEVEL" then "BAD_INPUT" else err
end

local function floorAllowed(rec: Record, player: Player, level: number): boolean
	local class = Plan.accessAt(rec.tier, Plan.liftExitPoint(level, 1))
	return Plan.playerAllows(player.UserId == rec.ownerId, authorize(player, rec.ownerId), class)
end

local function passenger(rec: Record, player: Player): boolean
	local root = rootOf(player.Character)
	return root ~= nil and insideFrame(cabinFrame(rec), root.Position)
end

local function hall(player: Player, office: Instance, level: number, quiet: boolean): (boolean, string?)
	local rec = recordFor(office)
	if not rec then
		return false, "LIFT_OUT_OF_SERVICE"
	end
	if not validLevel(rec, level) then
		return false, "BAD_INPUT"
	end
	if not authorize(player, rec.ownerId) then
		return false, "CARD_REQUIRED"
	end
	local ok, how = Logic.call(rec.car, "hall", level)
	if not ok then
		return false, callError(how)
	end
	if not quiet then
		notify(player, "LIFT_CALLED", { level = level, label = Plan.levelLabel(rec.tier, level), state = how })
	end
	return true, nil
end

-- Landing call button. Gives its own feedback (Notify LIFT_CALLED) on success.
function Lift.hallCall(player: Player, office: Instance, level: number): (boolean, string?)
	return hall(player, office, level, false)
end

-- Cabin panel. Opening the doors at the current stop is always allowed (egress).
function Lift.carCall(player: Player, office: Instance, level: number): (boolean, string?)
	local rec = recordFor(office)
	if not rec then
		return false, "LIFT_OUT_OF_SERVICE"
	end
	if not validLevel(rec, level) then
		return false, "BAD_INPUT"
	end
	if not passenger(rec, player) then
		return false, "LIFT_NOT_PASSENGER"
	end
	local car = rec.car
	if not (level == car.level and car.state ~= "MOVING") then
		if not authorize(player, rec.ownerId) then
			return false, "CARD_REQUIRED"
		end
		if not floorAllowed(rec, player, level) then
			return false, "LIFT_FLOOR_LOCKED"
		end
	end
	local ok, how = Logic.call(car, "car", level)
	if not ok then
		return false, callError(how)
	end
	return true, nil
end

function Lift.panel(player: Player, office: Instance): { [string]: any }
	local rec = recordFor(office)
	if not rec then
		local owner = if typeof(office) == "Instance" then office:GetAttribute("OwnerUserId") else nil
		return { ownerId = owner, current = 0, passenger = false, outOfService = true, stops = {} }
	end
	local car = rec.car
	local inside = passenger(rec, player)
	local card = authorize(player, rec.ownerId)
	local stops = {}
	for _, stop in Plan.liftStops(rec.tier) do
		local here = inside and stop.level == car.level and car.state ~= "MOVING"
		table.insert(stops, {
			level = stop.level, label = stop.label, name = stop.name,
			allowed = here or (card and floorAllowed(rec, player, stop.level)),
		})
	end
	return {
		ownerId = rec.ownerId, current = car.level, passenger = inside, state = car.state,
		outOfService = car.state == "OUT_OF_SERVICE", stops = stops,
	}
end

function Lift.isPassenger(office: Instance, character: Model?): boolean
	local rec = records[office]
	local root = rootOf(character)
	return rec ~= nil and root ~= nil and insideFrame(cabinFrame(rec), root.Position)
end

-- Accepts a character (or a Player for older callers).
function Lift.riding(who: Instance?): boolean
	local character: Instance? = who
	if who and who:IsA("Player") then
		character = who.Character
	end
	local root = rootOf(character)
	if not root then
		return false
	end
	for _, rec in records do
		if insideFrame(cabinFrame(rec), root.Position) then
			return true
		end
	end
	return false
end

-- RemoteFunction "UseCampusLift" {ownerId, floor}: car call for riders of that owner's cabin,
-- otherwise a hall call at the landing the player stands at (the floor is remembered and sent as
-- a car call when the player boards).
function Lift.remote(session: any, payload: any): { [string]: any }
	local player = if type(session) == "table" then session.player else nil
	if typeof(player) ~= "Instance" or not player:IsA("Player") or type(payload) ~= "table" then
		return { ok = false, err = "BAD_INPUT" }
	end
	local ownerId, floor = payload.ownerId, payload.floor
	if type(ownerId) ~= "number" or type(floor) ~= "number" or ownerId ~= math.floor(ownerId) or floor ~= math.floor(floor) then
		return { ok = false, err = "BAD_INPUT" }
	end
	local rec: Record? = nil
	for _, r in records do
		if r.ownerId == ownerId then
			rec = r
			break
		end
	end
	if not rec then
		for office in failed do
			if office:GetAttribute("OwnerUserId") == ownerId then
				return { ok = false, err = "LIFT_OUT_OF_SERVICE" }
			end
		end
		return { ok = false, err = "PLAYER_OFFLINE" }
	end
	if not validLevel(rec, floor) then
		return { ok = false, err = "BAD_INPUT" }
	end
	local character = player.Character
	local root = rootOf(character)
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not root or not humanoid then
		return { ok = false, err = "LOADING" }
	end
	if humanoid.SeatPart then
		return { ok = false, err = "LIFT_SEATED" }
	end
	if passenger(rec, player) then
		local ok, err = Lift.carCall(player, rec.office, floor)
		return { ok = ok, err = err, kind = "car", level = floor }
	end
	local best: Landing? = nil
	local bestD = LANDING_RANGE
	for _, landing in rec.landings do
		local d = (root.Position - (landing.closedL.Position + landing.closedR.Position) / 2).Magnitude
		if d <= bestD then
			best, bestD = landing, d
		end
	end
	if not best then
		return { ok = false, err = "LIFT_NO_LANDING" }
	end
	local ok, err = hall(player, rec.office, best.level, true)
	if not ok then
		return { ok = false, err = err }
	end
	if floor ~= best.level then
		wanted[player] = { rec = rec, level = floor, expires = now + 60 }
	end
	return { ok = true, kind = "hall", level = best.level, floor = floor }
end

---------------------------------------------------------------------------- NPC tickets

-- Ticket for an employee NPC; nil when the lift is unavailable or the destination is not allowed.
-- The NPC walks to ticket.target: wait point (waiting), doorway then a cabin slot (board), stays
-- (riding), exit point (exit); "done" = continue the route, "failed" = take the stairs.
function Lift.npcCall(office: Instance, npc: Model, fromLevel: number, toLevel: number): Logic.Ticket?
	local rec = recordFor(office)
	if not rec or typeof(npc) ~= "Instance" or not npc:IsA("Model") or not npc:IsDescendantOf(rec.office) then
		return nil
	end
	if not rootOf(npc) or not aliveModel(npc) then
		return nil
	end
	if not validLevel(rec, fromLevel) or not validLevel(rec, toLevel) or fromLevel == toLevel then
		return nil
	end
	local role = npc:GetAttribute("RoleId")
	if not Plan.employeeAllowed(if type(role) == "string" then role else "support", rec.tier, Plan.liftExitPoint(toLevel, 1)) then
		return nil
	end
	for t, other in rec.tickets do
		if other == npc then
			if t.fromLevel == fromLevel and t.toLevel == toLevel and t.state ~= "done" and t.state ~= "failed" then
				return t
			end
			rec.tickets[t] = nil
			ticketHome[t] = nil
			Logic.cancel(rec.car, t, "replaced")
			t.target = nil
		end
	end
	local t = Logic.addTicket(rec.car, fromLevel, toLevel, now)
	if not t then
		return nil
	end
	rec.tickets[t] = npc
	ticketHome[t] = rec
	t.target = targetFor(rec, t, npc)
	return t
end

function Lift.npcTicket(ticket: Logic.Ticket): Logic.Ticket
	local rec = ticketHome[ticket]
	if not rec then
		if ticket.state ~= "done" and ticket.state ~= "failed" then
			ticket.state = "failed"
		end
		ticket.target = nil
		return ticket
	end
	ticket.target = targetFor(rec, ticket, rec.tickets[ticket])
	return ticket
end

function Lift.npcCancel(ticket: Logic.Ticket)
	local rec = ticketHome[ticket]
	ticketHome[ticket] = nil
	if rec then
		rec.tickets[ticket] = nil
		Logic.cancel(rec.car, ticket, "cancelled")
	end
	ticket.target = nil
end

-- Deprecated teleport-era entry point: always declines, so old callers fall back to the stairs.
function Lift.requestEmployee(_office: Instance, _cf: CFrame, _npc: Model, _source: number, _destination: number): boolean
	return false
end

---------------------------------------------------------------------------- diagnostics

function Lift.inspect(office: Instance): { [string]: any }
	local rec = records[office]
	if not rec then
		return { attached = false, failed = failed[office] == true }
	end
	local car = rec.car
	local hallCalls, carCalls = {}, {}
	for level in car.hall do
		table.insert(hallCalls, level)
	end
	for level in car.car do
		table.insert(carCalls, level)
	end
	table.sort(hallCalls)
	table.sort(carCalls)
	local states: { [string]: number } = {}
	for _, t in car.tickets do
		states[t.state] = (states[t.state] or 0) + 1
	end
	return {
		attached = true, state = car.state, level = car.level, label = Plan.levelLabel(rec.tier, car.level),
		target = car.target, direction = car.direction, door = Logic.doorPhase(car), doorAlpha = car.door,
		position = car.position, geometric = geometricPosition(rec), command = car.cmd, velocity = car.vel, queue = { hall = hallCalls, car = carCalls },
		riders = rec.riders, capacity = car.capacity, full = car.full, tickets = #car.tickets, ticketStates = states,
		reason = car.reason, networkOwner = if rec.ownerSet then "server" else "pending",
	}
end

return Lift
