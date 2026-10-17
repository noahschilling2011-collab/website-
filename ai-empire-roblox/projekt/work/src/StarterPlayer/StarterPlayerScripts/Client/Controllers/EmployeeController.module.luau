--!strict
-- Local procedural Motor6D poses and held items; never moves an employee's world position.
-- Honest limits: the rigs are R6 with exactly six joints (two shoulders, two hips, Neck, RootJoint).
-- There are NO elbows and NO wrists, so stirring, chopping, wiping or writing read as whole-arm swings
-- and circles from the shoulder; no animation asset ids are used (none may be invented).
-- Pose source, in order: the rig's `Pose` attribute (job steps, written once per step by the server),
-- else a pose derived from Activity / WorkstationType / sitting (no extra network traffic).
-- Held items come from the rig's `Holding` attribute and are client-only parts welded to the right
-- arm (the mop cart to the root); the founder assistant's server cup (EmployeeCup) is left alone.
local RunService = game:GetService("RunService")
local Collection = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config.EmployeeConfig)
local Controller = {}

type Cache = {
	joints: { [string]: Motor6D },
	parts: { BasePart },
	next: number,
	hidden: boolean,
	holding: string?,
	items: { BasePart },
	meal: { BasePart },
	mealAt: Vector3?,
}
local employees: { [Model]: Cache } = {}
local WORK_STATES: { [string]: boolean } = { WORKING = true, DATA_REVIEW = true, MARKETING = true, MONITOR_TRAINING = true, MODEL_REVIEW = true, RESEARCH = true, SERVER_CHECK = true }
-- Standing poses derived from the station kind (no Pose attribute needed).
local STATION_POSE: { [string]: string } = { Whiteboard = "write", LabBench = "inspect", ServerRack = "reach", Pipeline = "scan", Pickup = "reach" }
local SEATED: { [string]: boolean } = { type = true, cycle = true, row = true, relax = true, eat = true }
local LOOK_LIMIT = math.rad(70) -- head turn towards a conversation partner

local function add(m: Instance)
	if not m:IsA("Model") then
		return
	end
	local joints: { [string]: Motor6D } = {}
	local parts: { BasePart } = {}
	for _, p in m:GetDescendants() do
		if p:IsA("Motor6D") then
			joints[p.Name] = p
		elseif p:IsA("BasePart") then
			table.insert(parts, p)
		end
	end
	employees[m] = { joints = joints, parts = parts, next = 0, hidden = false, holding = nil, items = {}, meal = {}, mealAt = nil }
end

local A = CFrame.Angles
-- Arm angles: x > 0 swings the arm forward/up (1.57 = horizontal, 2.7 = above the head); z moves it out
-- to the side (right arm +z, left arm -z). Hips: x = pi/2 is sitting. Neck: x < 0 looks down, y turns.
local function arms(lx: number, rx: number, lz: number?, rz: number?): (CFrame, CFrame)
	return A(lx, 0, -(lz or 0.04)), A(rx, 0, rz or 0.04)
end

-- Joint transforms for one frame. `pose` (optional) overrides the activity-derived posture; `talking`
-- (rig attribute TalkingTo, TalkService) adds the conversation gesture, `lookYaw` (radians, from TalkFace)
-- turns the head towards the player (clamped by the caller).
function Controller.pose(activity: string, sitting: boolean, walking: boolean, time: number, seed: number, holdingCup: boolean?, pose: string?, talking: boolean?, lookYaw: number?): { [string]: CFrame }
	local t = time + seed * 0.013
	local sway = math.sin(t * 5.3)
	local fidget = math.sin(t * 0.67) * math.sin(t * 0.13)
	local swing = if walking then 0.52 * sway else 0
	local typing = WORK_STATES[activity] == true and activity ~= "SERVER_CHECK" and sitting
	local left = if typing then 1.16 + 0.07 * math.sin(t * 8.3) else -swing
	local right = if typing then 1.2 + 0.06 * math.sin(t * 9.1 + 1.2) else swing
	if typing and math.sin(t * 0.31) > 0.83 then
		left = 0.4
		right = 0.7
	end -- short pauses, not a permanent typing loop
	local lz, rz = 0.04, 0.04
	local hipL = if sitting then math.pi / 2 else swing
	local hipR = if sitting then math.pi / 2 else -swing
	local neckX, neckY = if typing then -0.1 else 0.03 * fidget, 0.11 * fidget
	local lean, bob = if typing then 0.045 else 0.012 * fidget, if walking then 0.035 * math.cos(t * 10.6) else 0
	if activity == "COFFEE_BREAK" or activity == "LUNCH" then
		right = if math.sin(t * 0.7) > 0.7 then 1.9 else 1.1
	end
	if holdingCup and math.sin(t * 0.53) > 0.88 then
		right = 1.9
	end
	if activity == "MEETING" or activity == "TALKING" then
		right = 0.6 + 0.35 * math.sin(t * 1.7)
		left = 0.2 + 0.12 * math.sin(t * 1.2)
	end
	if activity == "SERVER_CHECK" and not pose then
		right = 1.05 + 0.15 * math.sin(t * 0.8)
	end
	if activity == "RESEARCH" and not sitting and not pose then
		right = 1.5 + 0.13 * math.sin(t * 2.4)
	end
	if pose then
		-- job poses (walking legs keep their swing; arm poses replace the arm swing)
		local w = math.sin
		if pose == "type" then
			left, right = 1.16 + 0.07 * w(t * 8.3), 1.2 + 0.06 * w(t * 9.1 + 1.2)
			neckX = -0.1
		elseif pose == "typeStand" then
			left, right = 1.3 + 0.05 * w(t * 8.3), 1.35 + 0.05 * w(t * 9.1 + 1.2)
			neckX = -0.18
		elseif pose == "stir" then
			right, rz = 1.15 + 0.15 * w(t * 4.2), 0.04 + 0.16 * math.cos(t * 4.2)
			left = 0.9
			neckX = -0.25
		elseif pose == "pour" then
			right, left = 1.35 + 0.04 * w(t * 1.3), 0.85
			rz = 0.12
			neckX = -0.2
		elseif pose == "plate" or pose == "carry" then
			local dip = if pose == "plate" then 0.12 * w(t * 2.2) else 0
			left, right = 1.4 + dip, 1.4 + dip
			lz, rz = 0.18, 0.18
			neckX = -0.15
		elseif pose == "chop" then
			right = 1.0 + 0.3 * math.abs(w(t * 9))
			left = 0.95
			neckX = -0.3
		elseif pose == "wash" then
			left, right = 1.0 + 0.12 * w(t * 6), 1.0 + 0.12 * w(t * 6 + math.pi)
			lz, rz = 0.1 + 0.1 * math.cos(t * 6), 0.1 + 0.1 * math.cos(t * 6 + math.pi)
			neckX = -0.3
		elseif pose == "wipe" then
			right, rz = 1.05, 0.05 + 0.35 * w(t * 3.1)
			left = 0.3
			lean, neckX = -0.12, -0.25
		elseif pose == "push" then
			left, right = 1.2, 1.2
			lz, rz = 0.12, 0.12
		elseif pose == "write" then
			right, rz = 1.85 + 0.1 * w(t * 5.0), 0.1 + 0.08 * math.cos(t * 5.0)
			left = 0.1
			neckY = 0.05 * w(t * 0.8)
		elseif pose == "reach" or pose == "plug" then
			right = (if pose == "plug" then 1.15 else 1.6) + 0.06 * w(t * 1.6)
			left = 0.25
			lean = if pose == "plug" then -0.15 else 0
			neckX = if pose == "plug" then -0.3 else -0.08
		elseif pose == "inspect" then
			right, left = 0.9 + 0.08 * w(t * 1.1), 0.5
			neckX, neckY = -0.28, 0.25 * w(t * 0.5)
		elseif pose == "scan" then
			left, right = -0.35, -0.35 -- hands behind the back
			lz, rz = -0.2, -0.2
			neckY = 0.6 * w(t * 0.55)
		elseif pose == "greet" then
			right, rz = 2.7, 0.2 + 0.25 * w(t * 7)
			left = 0
			neckX = 0.05
		elseif pose == "sort" then
			right, rz = 1.25 + 0.2 * w(t * 2.6), 0.1 + 0.25 * w(t * 1.3)
			left = 1.0 + 0.15 * w(t * 2.6 + 1.5)
			neckX = -0.12
		elseif pose == "run" then
			local s = w(t * 11)
			left, right = -0.9 * s, 0.9 * s
			hipL, hipR = 0.8 * s, -0.8 * s
			bob = 0.12 * math.abs(math.cos(t * 11))
		elseif pose == "cycle" then
			local s = w(t * 6)
			hipL, hipR = math.pi / 2 - 0.35 + 0.35 * s, math.pi / 2 - 0.35 - 0.35 * s
			left, right = 1.25, 1.25
			lean = -0.15
		elseif pose == "row" then
			local s = 0.5 + 0.5 * w(t * 2.4)
			hipL = math.pi / 2 - 0.45 * s
			hipR = hipL
			left, right = 1.55 - 0.85 * s, 1.55 - 0.85 * s
			lean = 0.18 * s - 0.12
		elseif pose == "lift" then
			left = 0.15 + 1.3 * math.max(0, w(t * 2.2 + math.pi))
			right = 0.15 + 1.3 * math.max(0, w(t * 2.2))
		elseif pose == "relax" then
			left, right = 0.25, 0.25
			lz, rz = 0.15, 0.15
			neckX, bob = -0.05, 0.02 * w(t * 1.2)
		elseif pose == "eat" then
			right = if w(t * 0.9) > 0.6 then 1.9 else 1.05
			left = 0.9
			neckX = -0.12
		elseif pose == "phone" then
			right, rz = 2.6, 0.5
			left = 0.15
			neckY = 0.15 * w(t * 0.4)
		elseif pose == "present" then
			-- staffops: the Training Lead explains a room / presents at the head of the table (open hand
			-- towards the room, the other hand gesturing, the head turning to the listeners)
			right, rz = 1.35 + 0.18 * w(t * 1.6), 0.55 + 0.1 * w(t * 0.9)
			left = 0.45 + 0.25 * math.max(0, w(t * 1.3 + 2))
			neckY = 0.35 * w(t * 0.45)
		elseif pose == "shower" then
			left, right = 2.6 + 0.1 * w(t * 4), 2.6 + 0.1 * w(t * 4 + 1)
			lz, rz = 0.35, 0.35
			neckX = 0.15
		end
		if SEATED[pose] and not sitting and pose ~= "type" then
			-- a seated pose on a standing rig keeps the legs straight
			if pose ~= "cycle" and pose ~= "row" then
				hipL, hipR = 0, 0
			end
		end
		if walking and pose ~= "run" then
			hipL, hipR = swing, -swing
		end
	end
	if talking then
		-- in a conversation: talking gesture (unless typing at a seated desk) and the head turned to the player
		if not (sitting and (typing or pose == "type")) then
			right, left = 0.6 + 0.35 * math.sin(t * 1.7), 0.2 + 0.12 * math.sin(t * 1.2)
			lz, rz = 0.04, 0.04
		end
		if lookYaw then
			neckX, neckY = 0, lookYaw
		end
	end
	local leftArm, rightArm = arms(left, right, lz, rz)
	return {
		["Left Shoulder"] = leftArm,
		["Right Shoulder"] = rightArm,
		["Left Hip"] = A(hipL, 0, 0),
		["Right Hip"] = A(hipR, 0, 0),
		Neck = A(neckX, neckY, 0),
		RootJoint = CFrame.new(0, bob, 0) * A(lean, 0, 0),
	}
end

-- Derived pose when the server sent none: standing at a whiteboard writes, at a lab bench inspects...
function Controller.derive(activity: string, sitting: boolean, stationType: string?, holding: string?): string?
	if sitting then
		if holding == "meal" then
			return "eat"
		end
		return nil
	end
	if WORK_STATES[activity] and stationType and STATION_POSE[stationType] then
		return STATION_POSE[stationType]
	end
	return nil
end

-- Held item recipes: parts in the hand's frame (Right Arm, hand at y = -1) or the root (mop cart).
type Piece = { size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, cylinder: boolean? }
local rgb = Color3.fromRGB
local UPRIGHT = A(0, 0, math.pi / 2) -- cylinder axis (local X) turned to vertical
local ITEMS: { [string]: { Piece } } = {
	cup = { { size = Vector3.new(0.7, 0.5, 0.5), offset = CFrame.new(0, -0.8, -0.55) * UPRIGHT, color = rgb(232, 228, 214), cylinder = true } },
	snack = { { size = Vector3.new(0.8, 0.3, 0.5), offset = CFrame.new(0, -0.95, -0.5), color = rgb(175, 141, 91) } },
	plate = {
		{ size = Vector3.new(0.1, 1.4, 1.4), offset = CFrame.new(0, -1.05, -0.75) * UPRIGHT, color = rgb(246, 246, 240), cylinder = true },
		{ size = Vector3.new(0.6, 0.25, 0.5), offset = CFrame.new(0, -0.9, -0.75), color = rgb(196, 120, 72) },
	},
	tray = {
		{ size = Vector3.new(2.2, 0.12, 1.5), offset = CFrame.new(-0.45, -1.05, -0.95), color = rgb(198, 168, 120), material = Enum.Material.Wood },
		{ size = Vector3.new(0.1, 1.1, 1.1), offset = CFrame.new(-0.45, -0.95, -0.95) * UPRIGHT, color = rgb(246, 246, 240), cylinder = true },
	},
	pan = { { size = Vector3.new(0.25, 1.2, 1.2), offset = CFrame.new(0, -1.05, -0.9) * UPRIGHT, color = rgb(52, 52, 56), material = Enum.Material.Metal, cylinder = true } },
	spatula = { { size = Vector3.new(0.1, 0.1, 1.2), offset = CFrame.new(0, -1.0, -0.6), color = rgb(60, 60, 64) } },
	knife = { { size = Vector3.new(0.06, 0.12, 1.0), offset = CFrame.new(0, -1.0, -0.55), color = rgb(200, 202, 206), material = Enum.Material.Metal } },
	sponge = { { size = Vector3.new(0.5, 0.3, 0.4), offset = CFrame.new(0, -1.08, -0.2), color = rgb(236, 206, 72) } },
	laptop = { { size = Vector3.new(1.6, 0.1, 1.1), offset = CFrame.new(0, -1.0, -0.6), color = rgb(150, 152, 156), material = Enum.Material.Metal } },
	blade = { { size = Vector3.new(0.3, 1.6, 1.2), offset = CFrame.new(0, -1.25, -0.45), color = rgb(40, 44, 50), material = Enum.Material.Metal } },
	parcel = { { size = Vector3.new(1.2, 0.8, 1.0), offset = CFrame.new(0, -1.05, -0.7), color = rgb(196, 160, 112) } },
	marker = { { size = Vector3.new(0.12, 0.5, 0.12), offset = CFrame.new(0, -1.1, -0.15), color = rgb(40, 90, 170) } },
	badge = { { size = Vector3.new(0.6, 0.05, 0.4), offset = CFrame.new(0, -1.05, -0.3), color = rgb(240, 240, 236) } },
	dumbbell = { { size = Vector3.new(1.0, 0.4, 0.4), offset = CFrame.new(0, -1.05, 0), color = rgb(52, 52, 56), material = Enum.Material.Metal, cylinder = true } },
	keys = { { size = Vector3.new(0.3, 0.1, 0.3), offset = CFrame.new(0, -1.05, -0.2), color = rgb(212, 180, 96), material = Enum.Material.Metal } },
	-- company phone (phone request 4): shown while the "phone" pose runs (calls), dark body + lit screen
	phone = {
		{ size = Vector3.new(0.3, 0.6, 0.08), offset = CFrame.new(0, -1.05, -0.42), color = rgb(20, 22, 24) },
		{ size = Vector3.new(0.26, 0.5, 0.01), offset = CFrame.new(0, -1.05, -0.465), color = rgb(96, 176, 232), material = Enum.Material.Neon },
	},
}
-- Mop cart in front of the torso, on the floor (root frame: floor is ~3 studs below the root).
local CART: { Piece } = {
	{ size = Vector3.new(2.0, 0.3, 2.6), offset = CFrame.new(0, -2.4, -2.6), color = rgb(46, 92, 160) },
	{ size = Vector3.new(1.2, 1.1, 1.2), offset = CFrame.new(0, -1.75, -2.9) * UPRIGHT, color = rgb(232, 186, 50), cylinder = true },
	{ size = Vector3.new(0.12, 2.4, 0.12), offset = CFrame.new(0.6, -1.5, -1.5) * A(0.35, 0, 0), color = rgb(150, 152, 156), material = Enum.Material.Metal },
}

local function buildPiece(piece: Piece, base: BasePart, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = "HeldItem"
	if piece.cylinder then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Size = piece.size
	p.Color = piece.color
	p.Material = piece.material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	p.Anchored = false
	p.CFrame = base.CFrame * piece.offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = base
	weld.Part1 = p
	weld.Parent = p
	p.Parent = parent
	return p
end

local function clearItems(cache: Cache)
	for _, p in cache.items do
		p:Destroy()
	end
	table.clear(cache.items)
end

-- Client-only held item for `holding` (nil / unknown clears).
function Controller.hold(m: Model, cache: Cache, holding: string?)
	if cache.holding == holding then
		return
	end
	cache.holding = holding
	clearItems(cache)
	if not holding then
		return
	end
	if holding == "mopcart" then
		local root = m.PrimaryPart
		if root then
			for _, piece in CART do
				table.insert(cache.items, buildPiece(piece, root, m))
			end
		end
		return
	end
	local recipe = ITEMS[holding]
	local arm = m:FindFirstChild("Right Arm")
	if recipe and arm and arm:IsA("BasePart") then
		for _, piece in recipe do
			table.insert(cache.items, buildPiece(piece, arm, m))
		end
	end
end

-- Meal on the table in front of a seated employee (TablePoint, world space): anchored local parts.
function Controller.meal(cache: Cache, at: Vector3?)
	if cache.mealAt == at then
		return
	end
	cache.mealAt = at
	for _, p in cache.meal do
		p:Destroy()
	end
	table.clear(cache.meal)
	if not at then
		return
	end
	local folder = workspace:FindFirstChild("PropFxLocal")
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "PropFxLocal"
		f.Parent = workspace
		folder = f
	end
	for i, piece in ITEMS.plate do
		local p = Instance.new("Part")
		p.Name = "MealPlate"
		if piece.cylinder then
			p.Shape = Enum.PartType.Cylinder
		end
		p.Size = piece.size
		p.Color = piece.color
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.CFrame = CFrame.new(at + Vector3.new(0, 0.05 + (i - 1) * 0.15, 0)) * (if piece.cylinder then UPRIGHT else CFrame.identity)
		p.Parent = folder
		table.insert(cache.meal, p)
	end
end

local function drop(m: Model, cache: Cache)
	clearItems(cache)
	Controller.meal(cache, nil)
	employees[m] = nil
end

function Controller.init()
	for _, m in Collection:GetTagged("CompanyEmployee") do
		add(m)
	end
	Collection:GetInstanceAddedSignal("CompanyEmployee"):Connect(add)
	Collection:GetInstanceRemovedSignal("CompanyEmployee"):Connect(function(m)
		local cache = employees[m :: Model]
		if cache then
			drop(m :: Model, cache)
		end
	end)
	RunService.PreSimulation:Connect(function()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local time = workspace:GetServerTimeNow()
		for m, cache in employees do
			local root = m.PrimaryPart
			if not m.Parent or not root then
				drop(m, cache)
				continue
			end
			local distance = (camera.CFrame.Position - root.Position).Magnitude
			local hidden = distance > Config.FAR or m:GetAttribute("OffDuty") == true
			if hidden ~= cache.hidden then
				for _, p in cache.parts do
					if p.Parent then
						p.LocalTransparencyModifier = if hidden then 1 else 0
					end
				end
				for _, p in cache.items do
					p.LocalTransparencyModifier = if hidden then 1 else 0
				end
				cache.hidden = hidden
			end
			if hidden or time < cache.next then
				continue
			end
			cache.next = time + (if distance < Config.NEAR then 1 / 30 else 0.2)
			local activityAttr = m:GetAttribute("Activity")
			local activity: string = if typeof(activityAttr) == "string" then activityAttr else "WORKING"
			local h = m:FindFirstChildOfClass("Humanoid")
			local sitting = h ~= nil and h.SeatPart ~= nil
			local velocity = root.AssemblyLinearVelocity
			local walking = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 0.5
			local holdingAttr = m:GetAttribute("Holding")
			local holding = if typeof(holdingAttr) == "string" and holdingAttr ~= "" then string.lower(holdingAttr) else nil
			-- a call (pose "phone") shows the company phone in the hand when nothing else is held
			if holding == nil and m:GetAttribute("Pose") == "phone" then
				holding = "phone"
			end
			local serverCup = m:FindFirstChild("EmployeeCup") ~= nil
			Controller.hold(m, cache, if serverCup or holding == "meal" then nil else holding)
			local tablePoint = m:GetAttribute("TablePoint")
			Controller.meal(cache, if holding == "meal" and typeof(tablePoint) == "Vector3" then tablePoint else nil)
			local poseAttr = m:GetAttribute("Pose")
			local stationType = m:GetAttribute("WorkstationType")
			local pose = if typeof(poseAttr) == "string" and poseAttr ~= "" then poseAttr else Controller.derive(activity, sitting, if typeof(stationType) == "string" then stationType else nil, holding)
			local cup = m:GetAttribute("HoldingCup") == true or holding == "cup"
			local seedAttr = m:GetAttribute("PersonalitySeed")
			-- conversation (TalkService): look at TalkFace, clamped to +-70 degrees of the body's facing
			local talking = m:GetAttribute("TalkingTo") ~= nil
			local lookYaw: number? = nil
			local faceAttr = m:GetAttribute("TalkFace")
			if talking and typeof(faceAttr) == "Vector3" and distance < Config.NEAR then
				local d = root.CFrame:PointToObjectSpace(faceAttr)
				if d.X * d.X + d.Z * d.Z > 0.01 then
					lookYaw = math.clamp(math.atan2(-d.X, -d.Z), -LOOK_LIMIT, LOOK_LIMIT)
				end
			end
			local transforms = Controller.pose(activity, sitting, walking, time, if typeof(seedAttr) == "number" then seedAttr else 0, cup, pose, talking, lookYaw)
			for name, transform in transforms do
				local joint = cache.joints[name]
				if joint and joint.Parent then
					joint.Transform = transform
				end
			end
		end
	end)
end

return Controller
