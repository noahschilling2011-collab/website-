--!strict
-- Server door controller for every CampusDoor model (contract: SPEC §3).
--
-- Each door runs one small state machine:
--   closed → opening → open (HoldOpen timer, extended by new requests and an occupied doorway)
--          → closing → closed
-- Leaves are animated with leaf:PivotTo(ClosedPivot:Lerp(OpenPivot, eased alpha)). A door that is
-- asked again while it moves simply continues/reverses its single animation, so repeated triggers
-- never start competing tweens. Leaf parts stop colliding as soon as a door starts to open and only
-- collide again when the doorway Sensor is empty at the moment the leaves are shut; somebody stepping
-- into a closing doorway reopens it.
--
-- Access: the protected side (SecureNormal) can always leave — locked doors, founder rooms, the
-- bookcase, the vault and the hidden lab can never trap anybody. Entry from the other side asks the
-- authorizer (FacilityService: founder, company card, guest card → BuildingPlan.playerAllows) or,
-- for employees, BuildingPlan.roleAllows. Hidden doors (flush, bookcase, vault) never open for NPCs.
-- Automatic doors (AutoOpen: entrance, badge speed gates, garage gate) open by themselves for an
-- authorized person approaching from outside and for anybody approaching from the protected side;
-- a denied approach turns the reader red and notifies the player (throttled).
--
-- Cost: idle doors cost nothing. tick() only visits doors that are moving, open, flashing a reader
-- light or waiting for their doorway to clear, plus the few automatic doors (polled 5×/s). The
-- Heartbeat connection exists only while at least one door is animating.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Plan = require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Layout = require(ReplicatedStorage.Shared.BuildingLayout)
local Palette = require(ReplicatedStorage.Shared.Config.ArchPalette)
local Sound = require(script.Parent.CampusSoundService)

local Doors = {}

local TAG = "CampusDoor"
local REQUEST_RANGE = 10 -- player prompt requests
local NPC_RANGE = 8 -- employee requests
local AUTO_RANGE = 7 -- automatic doors: approach distance (gates 14, speed gate lanes 3.5)
local LIGHT_SECONDS = 1.5
local AUTO_POLL = 0.2
local SWEEP_SECONDS = 3
local REOPEN_HOLD = 2.5 -- hold after an obstruction reopened a closing door
local OCCUPIED_HOLD = 0.8 -- an occupied doorway keeps the timer at least this high
local DENY_COOLDOWN = 4 -- seconds between "access denied" notices for one player at automatic doors
local DEFAULT_DURATION = 0.6
local DURATION: { [string]: number } = { vault = 1.4, bookcase = 1.1, gate = 1.0, speedgate = 0.45 }
local DEFAULT_HOLD: { [string]: number } = { speedgate = 2 }
local DEFAULT_APPROACH: { [string]: number } = { gate = 14, speedgate = 3.5 }
local HIDDEN_KINDS: { [string]: boolean } = { flush = true, bookcase = true, vault = true }
local FEEDBACK: { [string]: Color3 } = {
	good = Palette.color.statusGood,
	bad = Palette.color.statusBad,
	busy = Palette.color.statusBusy,
}

type Leaf = { model: Model, closed: CFrame, open: CFrame }
type Light = { part: BasePart, neutral: Color3 }
type Record = {
	model: Model,
	office: Model,
	id: string,
	kind: string,
	access: string,
	normal: Vector3, -- world unit vector into the protected side; zero = unknown (both sides may leave)
	centre: Vector3, -- doorway centre (closed leaves)
	reach: number, -- quick-reject radius for sensor tests
	auto: boolean,
	approach: number,
	hold: number,
	hidden: boolean,
	duration: number,
	fixture: string?,
	leaves: { Leaf },
	solid: { BasePart }, -- leaf parts that collide while the door is shut
	sensor: BasePart?,
	lights: { Light },
	soundPart: BasePart?,
	state: string, -- closed | opening | open | closing
	progress: number, -- 0 = closed .. 1 = open
	timer: number,
	locked: boolean,
	forced: boolean, -- manual close (cubicle toggle): do not reopen for occupancy
	pendingSolid: boolean, -- shut, but leaves stay non-colliding until the doorway is clear
	collidable: boolean,
	lightTimer: number,
	lastUser: string?,
	written: string?,
}
type Registry = { doors: { [Model]: Record }, byId: { [string]: Record }, toilets: { [string]: Seat }? }
type PlayerRoot = { player: Player, root: BasePart }
type NpcRoot = { npc: Model, root: BasePart }
export type DoorInfo = { id: string, kind: string, state: string, access: string, lastUser: string? }

local offices: { [Model]: Registry } = {}
local records: { [Model]: Record } = {}
local active: { [Record]: boolean } = {}
local animating: { [Record]: boolean } = {}
local autos: { [Record]: boolean } = {}
local heartbeat: RBXScriptConnection? = nil
local authorizer: (Player, Model, Model) -> (boolean, string?) = function()
	return false, "Door offline."
end
local notifier: (Player, string) -> () = function() end
local playerSource: () -> { Player } = function()
	return Players:GetPlayers()
end
local clock = 0 -- dt-driven time (tick), used for throttling
local deniedAt: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local stamp = 0
local playerCache: { stamp: number, list: { PlayerRoot } } = { stamp = -1, list = {} }
local npcCache: { [Model]: { stamp: number, list: { NpcRoot } } } = {}
local autoClock, sweepClock = 0, 0
local warned: { [string]: boolean } = {}

local function warnOnce(key: string, text: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn("[Doors] " .. text)
end

local function snapshot(set: { [Record]: boolean }): { Record }
	local list = {}
	for rec in set do
		table.insert(list, rec)
	end
	return list
end

local function rootOf(model: Instance?): BasePart?
	if model == nil then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	if model:IsA("Model") and model.PrimaryPart then
		return model.PrimaryPart
	end
	return nil
end

-- Character roots of all players for this tick (fresh = rebuild now).
local function playerRoots(fresh: boolean?): { PlayerRoot }
	if fresh or playerCache.stamp ~= stamp then
		local list: { PlayerRoot } = {}
		for _, player in playerSource() do
			local root = rootOf(player.Character)
			if root then
				table.insert(list, { player = player, root = root })
			end
		end
		playerCache = { stamp = stamp, list = list }
	end
	return playerCache.list
end

-- Employee NPC roots of one office for this tick.
local function npcRoots(office: Model, fresh: boolean?): { NpcRoot }
	local cached = npcCache[office]
	if cached and cached.stamp == stamp and not fresh then
		return cached.list
	end
	local list: { NpcRoot } = {}
	for _, name in { "Employees", "OperationsEmployees", "Visitors", "Assistant" } do
		local folder = office:FindFirstChild(name)
		if folder then
			for _, npc in folder:GetChildren() do
				if npc:IsA("Model") then
					local root = rootOf(npc)
					if root then
						table.insert(list, { npc = npc, root = root })
					end
				end
			end
		end
	end
	npcCache[office] = { stamp = stamp, list = list }
	return list
end

local function alive(rec: Record): boolean
	return rec.model.Parent ~= nil and rec.office.Parent ~= nil and records[rec.model] == rec
end

local function drop(rec: Record)
	if records[rec.model] == rec then
		records[rec.model] = nil
	end
	active[rec] = nil
	animating[rec] = nil
	autos[rec] = nil
	local reg = offices[rec.office]
	if reg then
		if reg.doors[rec.model] == rec then
			reg.doors[rec.model] = nil
		end
		if reg.byId[rec.id] == rec then
			reg.byId[rec.id] = nil
		end
	end
end

local function stateOf(rec: Record): string
	return if rec.locked and rec.state == "closed" then "locked" else rec.state
end

local function publish(rec: Record)
	local value = stateOf(rec)
	if rec.written ~= value then
		rec.written = value
		rec.model:SetAttribute("DoorState", value)
	end
end

-- Doorway geometry -------------------------------------------------------------------------------

local function inSensor(rec: Record, p: Vector3): boolean
	local sensor = rec.sensor
	if sensor and sensor.Parent then
		local v = sensor.CFrame:PointToObjectSpace(p)
		local h = sensor.Size / 2
		return math.abs(v.X) <= h.X + 0.25 and math.abs(v.Y) <= h.Y + 0.5 and math.abs(v.Z) <= h.Z + 0.25
	end
	return (p - rec.centre).Magnitude <= 5
end

local function occupied(rec: Record, fresh: boolean?): boolean
	for _, entry in playerRoots(fresh) do
		local p = entry.root.Position
		if (p - rec.centre).Magnitude <= rec.reach and inSensor(rec, p) then
			return true
		end
	end
	for _, entry in npcRoots(rec.office, fresh) do
		local p = entry.root.Position
		if (p - rec.centre).Magnitude <= rec.reach and inSensor(rec, p) then
			return true
		end
	end
	return false
end

-- True on the protected side (or when the door's orientation is unknown: never trap anybody).
local function secureSide(rec: Record, p: Vector3): boolean
	if rec.normal.Magnitude < 0.5 then
		return true
	end
	return (p - rec.centre):Dot(rec.normal) > 0
end

-- Animation ------------------------------------------------------------------------------------

local function ease(t: number): number
	return t * t * (3 - 2 * t)
end

local function apply(rec: Record)
	local alpha = ease(rec.progress)
	for _, leaf in rec.leaves do
		if leaf.model.Parent then
			leaf.model:PivotTo(leaf.closed:Lerp(leaf.open, alpha))
		end
	end
end

local function setCollision(rec: Record, on: boolean)
	if rec.collidable == on then
		return
	end
	rec.collidable = on
	for _, part in rec.solid do
		if part.Parent then
			part.CanCollide = on
		end
	end
end

local function playSound(rec: Record)
	local part = rec.soundPart
	if part and part.Parent then
		Sound.play(part, "door")
	end
end

local animate: (number) -> ()

local function startAnimating(rec: Record)
	animating[rec] = true
	active[rec] = true
	if heartbeat == nil then
		heartbeat = RunService.Heartbeat:Connect(animate)
	end
end

local function beginOpen(rec: Record, hold: number?)
	local want = hold or rec.hold
	rec.timer = math.max(rec.timer, want)
	rec.forced = false
	if rec.state == "open" or rec.state == "opening" then
		active[rec] = true
		return -- already open or on its way: the hold was extended above
	end
	if rec.state == "closed" then
		playSound(rec)
	end
	rec.state = "opening"
	rec.pendingSolid = false
	setCollision(rec, false)
	startAnimating(rec)
	publish(rec)
end

local function beginClose(rec: Record, forced: boolean)
	if rec.state == "closed" or rec.state == "closing" then
		return
	end
	rec.state = "closing"
	rec.timer = 0
	rec.forced = forced
	startAnimating(rec)
	publish(rec)
end

local function finishClosed(rec: Record)
	rec.state = "closed"
	rec.progress = 0
	rec.forced = false
	animating[rec] = nil
	setCollision(rec, true)
	publish(rec)
end

animate = function(dt: number)
	for _, rec in snapshot(animating) do
		if not alive(rec) then
			drop(rec)
			continue
		end
		if rec.state == "opening" then
			rec.progress = math.min(1, rec.progress + dt / rec.duration)
			apply(rec)
			if rec.progress >= 1 then
				rec.state = "open"
				animating[rec] = nil
				publish(rec)
			end
		elseif rec.state == "closing" then
			rec.progress = math.max(0, rec.progress - dt / rec.duration)
			apply(rec)
			if rec.progress <= 0 then
				if not occupied(rec, true) then
					finishClosed(rec)
				elseif rec.forced then
					-- Manual cubicle close: shut visually, collide once the doorway is clear.
					rec.state = "closed"
					rec.forced = false
					rec.pendingSolid = true
					animating[rec] = nil
					publish(rec)
				else
					rec.state = "opening" -- somebody is in the doorway: reopen
					rec.timer = math.max(rec.timer, REOPEN_HOLD)
					publish(rec)
				end
			end
		else
			animating[rec] = nil
		end
	end
	if next(animating) == nil and heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

-- Reader feedback --------------------------------------------------------------------------------

local function paint(rec: Record, kind: string?)
	for _, light in rec.lights do
		if light.part.Parent then
			light.part.Color = if kind then FEEDBACK[kind] else light.neutral
		end
	end
end

local function flash(rec: Record, kind: string)
	if #rec.lights == 0 then
		return
	end
	paint(rec, kind)
	rec.lightTimer = LIGHT_SECONDS
	active[rec] = true
end

local function grant(rec: Record, who: string?)
	rec.lastUser = who
	flash(rec, "good")
	beginOpen(rec)
end

-- Registry ---------------------------------------------------------------------------------------

local function isDoor(m: Instance): boolean
	if not m:IsA("Model") then
		return false
	end
	return CollectionService:HasTag(m, TAG) or (m:GetAttribute("DoorId") ~= nil and m:GetAttribute("DoorKind") ~= nil)
end

local function boundsCentre(parts: { BasePart }): Vector3?
	if #parts == 0 then
		return nil
	end
	local lx, ly, lz = math.huge, math.huge, math.huge
	local hx, hy, hz = -math.huge, -math.huge, -math.huge
	for _, part in parts do
		local cf, s = part.CFrame, part.Size / 2
		local r, u, b = cf.RightVector, cf.UpVector, cf.LookVector
		local ex = math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(b.X) * s.Z
		local ey = math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(b.Y) * s.Z
		local ez = math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(b.Z) * s.Z
		local p = cf.Position
		lx, ly, lz = math.min(lx, p.X - ex), math.min(ly, p.Y - ey), math.min(lz, p.Z - ez)
		hx, hy, hz = math.max(hx, p.X + ex), math.max(hy, p.Y + ey), math.max(hz, p.Z + ez)
	end
	return Vector3.new((lx + hx) / 2, (ly + hy) / 2, (lz + hz) / 2)
end

local function partsOf(root: Instance?): { BasePart }
	local out: { BasePart } = {}
	if root then
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
	end
	return out
end

-- Fallback when a builder forgot SecureNormal: the plan's inward normal for this door id.
local function layoutNormal(office: Model, id: string): Vector3?
	local tier = office:GetAttribute("OfficeTier")
	local cf = office:GetAttribute("CampusCFrame")
	if typeof(tier) ~= "number" or typeof(cf) ~= "CFrame" then
		return nil
	end
	for _, d in Layout.doors(tier) do
		if d.id == id then
			return cf:VectorToWorldSpace(d.inward)
		end
	end
	return nil
end

local function add(office: Model, model: Model, reg: Registry): Record
	local rawId = model:GetAttribute("DoorId")
	local id = if rawId ~= nil then tostring(rawId) else (string.gsub(model.Name, "^Door_", ""))
	local kindAttr = model:GetAttribute("DoorKind")
	local kind = if typeof(kindAttr) == "string" then kindAttr else "solid"
	local accessAttr = model:GetAttribute("AccessClass")
	local access = if typeof(accessAttr) == "string" then accessAttr else "staff"

	local leaves: { Leaf } = {}
	local solid: { BasePart } = {}
	local leafParts: { BasePart } = {}
	for _, child in model:GetChildren() do
		if child:IsA("Model") and string.sub(child.Name, 1, 4) == "Leaf" then
			local closed, open = child:GetAttribute("ClosedPivot"), child:GetAttribute("OpenPivot")
			if typeof(closed) == "CFrame" and typeof(open) == "CFrame" then
				child:PivotTo(closed) -- registry always starts from a shut door
				table.insert(leaves, { model = child, closed = closed, open = open })
				for _, part in partsOf(child) do
					table.insert(leafParts, part)
					if part.CanCollide then
						table.insert(solid, part)
					end
				end
			else
				warnOnce(id .. child.Name, string.format("%s.%s has no ClosedPivot/OpenPivot; leaf stays static", model.Name, child.Name))
			end
		end
	end

	local sensorInst = model:FindFirstChild("Sensor")
	local sensor: BasePart? = if sensorInst and sensorInst:IsA("BasePart") then sensorInst else nil
	local centre = boundsCentre(leafParts)
		or boundsCentre(partsOf(model:FindFirstChild("Frame")))
		or (if sensor then sensor.Position else model:GetPivot().Position)

	local normalAttr = model:GetAttribute("SecureNormal")
	local normal = Vector3.zero
	if typeof(normalAttr) == "Vector3" and normalAttr.Magnitude > 0.5 then
		normal = normalAttr.Unit
	else
		local fallback = layoutNormal(office, id)
		if fallback then
			normal = fallback.Unit
		else
			warnOnce("normal" .. id, model.Name .. " has no SecureNormal; both sides are treated as egress")
		end
	end

	local lights: { Light } = {}
	for _, d in model:GetDescendants() do
		if d.Name == "ReaderLight" and d:IsA("BasePart") then
			local neutral = d:GetAttribute("NeutralColor")
			table.insert(lights, { part = d, neutral = if typeof(neutral) == "Color3" then neutral else d.Color })
		end
	end

	local reach = 6
	if sensor then
		reach = (sensor.Position - centre).Magnitude + sensor.Size.Magnitude / 2 + 1
	end
	local autoAttr = model:GetAttribute("AutoOpen")
	local holdAttr = model:GetAttribute("HoldOpen")
	local approachAttr = model:GetAttribute("ApproachRadius")
	local fixture = model:GetAttribute("FixtureKey")
	local rec: Record = {
		model = model,
		office = office,
		id = id,
		kind = kind,
		access = access,
		normal = normal,
		centre = centre,
		reach = reach,
		auto = autoAttr == true or (autoAttr == nil and kind == "autoslide"),
		approach = if typeof(approachAttr) == "number" then approachAttr else DEFAULT_APPROACH[kind] or AUTO_RANGE,
		hold = if typeof(holdAttr) == "number" and holdAttr > 0 then holdAttr else DEFAULT_HOLD[kind] or 5,
		hidden = model:GetAttribute("Hidden") == true or HIDDEN_KINDS[kind] == true,
		duration = DURATION[kind] or DEFAULT_DURATION,
		fixture = if fixture ~= nil then tostring(fixture) else nil,
		leaves = leaves,
		solid = solid,
		sensor = sensor,
		lights = lights,
		soundPart = sensor or leafParts[1],
		state = "closed",
		progress = 0,
		timer = 0,
		locked = false,
		forced = false,
		pendingSolid = false,
		collidable = true,
		lightTimer = 0,
		lastUser = nil,
		written = nil,
	}
	for _, part in solid do
		part.CanCollide = true
	end
	if reg.byId[id] and reg.byId[id].model ~= model then
		warnOnce("dup" .. id, "duplicate DoorId " .. id .. " in one office")
	end
	records[model] = rec
	reg.doors[model] = rec
	reg.byId[id] = rec
	if rec.auto then
		autos[rec] = true
	end
	publish(rec)
	return rec
end

-- Record for a door model; lazily registers doors added to an already registered office.
local function ensure(door: Instance?): Record?
	if door == nil or not door:IsA("Model") then
		return nil
	end
	local rec = records[door]
	if rec then
		if alive(rec) then
			return rec
		end
		drop(rec)
		return nil
	end
	local office = door:FindFirstAncestor("Office")
	if office and office:IsA("Model") and offices[office] and door.Parent and isDoor(door) then
		return add(office, door, offices[office])
	end
	return nil
end

local function toiletBusy(rec: Record, humanoid: Humanoid?): boolean
	local key = rec.fixture
	local reg = offices[rec.office]
	if key == nil or reg == nil then
		return false
	end
	local toilets = reg.toilets
	if toilets == nil then
		local map: { [string]: Seat } = {}
		for _, d in rec.office:GetDescendants() do
			if d.Name == "ToiletSeat" and d:IsA("Seat") and d:GetAttribute("FixtureKey") ~= nil then
				map[tostring(d:GetAttribute("FixtureKey"))] = d
			end
		end
		reg.toilets = map
		toilets = map
	end
	local seat: Seat? = (toilets :: { [string]: Seat })[key]
	if not seat or not seat.Parent then
		return false
	end
	local occupant = seat.Occupant
	return occupant ~= nil and occupant ~= humanoid
end

local function authorize(player: Player, rec: Record): (boolean, string?)
	local ok, allowed, reason = pcall(authorizer, player, rec.office, rec.model)
	if not ok then
		warnOnce("auth", "authorizer failed: " .. tostring(allowed))
		return false, "Door offline."
	end
	return allowed == true, reason
end

-- Denied approach at an automatic door: red reader + one notice per player every few seconds.
local function deny(rec: Record, player: Player, reason: string?)
	local last = deniedAt[player]
	if last and clock - last < DENY_COOLDOWN then
		return
	end
	deniedAt[player] = clock
	flash(rec, "bad")
	if not pcall(notifier, player, reason or "Access denied.") then
		warnOnce("notify", "notifier failed")
	end
end

local function autoCheck(rec: Record)
	local opened = false
	for _, entry in playerRoots() do
		local p = entry.root.Position
		if (p - rec.centre).Magnitude <= rec.approach then
			local allowed: boolean, reason: string? = secureSide(rec, p), nil
			if not allowed then
				if rec.locked then
					reason = "Locked."
				else
					allowed, reason = authorize(entry.player, rec)
				end
			end
			if allowed then
				if not opened then
					rec.lastUser = entry.player.Name
					beginOpen(rec)
					opened = true
				end
			else
				deny(rec, entry.player, reason)
			end
		end
	end
	if opened then
		return
	end
	local owner = rec.office:GetAttribute("OwnerUserId")
	for _, entry in npcRoots(rec.office) do
		local p = entry.root.Position
		if (p - rec.centre).Magnitude <= rec.approach and entry.npc:GetAttribute("OwnerUserId") == owner then
			local role = entry.npc:GetAttribute("RoleId")
			if secureSide(rec, p) or (not rec.locked and Plan.roleAllows(if typeof(role) == "string" then role else "support", rec.access)) then
				beginOpen(rec)
				return
			end
		end
	end
end

local function sweep()
	for office, reg in offices do
		if office.Parent == nil then
			Doors.unregister(office)
		else
			for model, rec in reg.doors do
				if model.Parent == nil then
					drop(rec)
				end
			end
		end
	end
end

-- Public API -----------------------------------------------------------------------------------

function Doors.init()
	autoClock, sweepClock = 0, 0
end

-- fn(player, office, door) -> (allowed, denyReason?) for entry from the non-secure side.
function Doors.setAuthorizer(fn: (Player, Model, Model) -> (boolean, string?))
	authorizer = fn
end

-- fn(player, text): shows a short notice (FacilityService → CAMPUS_NOTICE). Used for denied approaches.
function Doors.setNotifier(fn: (Player, string) -> ())
	notifier = fn
end

-- Test seam: replaces Players:GetPlayers() (the headless harness has no real players).
function Doors._setPlayerSource(fn: () -> { Player })
	playerSource = fn
end

function Doors.register(office: Model)
	if offices[office] then
		Doors.unregister(office)
	end
	local reg: Registry = { doors = {}, byId = {}, toilets = nil }
	offices[office] = reg
	local seen: { [Instance]: boolean } = {}
	local function consider(m: Instance)
		if seen[m] or not m:IsA("Model") or not isDoor(m) then
			return
		end
		seen[m] = true
		add(office, m, reg)
	end
	local folder = office:FindFirstChild("Doors")
	if folder then
		for _, m in folder:GetDescendants() do
			consider(m)
		end
	end
	-- Doors parked elsewhere in the office (e.g. an appliance door inside a room model).
	for _, m in CollectionService:GetTagged(TAG) do
		if m:IsDescendantOf(office) then
			consider(m)
		end
	end
end

function Doors.unregister(office: Model)
	local reg = offices[office]
	npcCache[office] = nil
	if reg == nil then
		return
	end
	offices[office] = nil
	for model, rec in reg.doors do
		if records[model] == rec then
			records[model] = nil
		end
		active[rec] = nil
		animating[rec] = nil
		autos[rec] = nil
	end
end

function Doors.tick(dt: number)
	stamp += 1
	clock += dt
	for _, rec in snapshot(active) do
		if not alive(rec) then
			drop(rec)
			continue
		end
		if rec.lightTimer > 0 then
			rec.lightTimer -= dt
			if rec.lightTimer <= 0 then
				rec.lightTimer = 0
				paint(rec, nil)
			end
		end
		if rec.state == "open" then
			if occupied(rec) then
				rec.timer = math.max(rec.timer, OCCUPIED_HOLD)
			end
			rec.timer -= dt
			if rec.timer <= 0 then
				beginClose(rec, false)
			end
		elseif rec.state == "closing" then
			if not rec.forced and occupied(rec) then
				beginOpen(rec, REOPEN_HOLD)
			end
		elseif rec.state == "closed" and rec.pendingSolid and not occupied(rec) then
			rec.pendingSolid = false
			setCollision(rec, true)
		end
		if rec.state == "closed" and not rec.pendingSolid and rec.lightTimer <= 0 then
			active[rec] = nil
		end
	end
	autoClock += dt
	if autoClock >= AUTO_POLL then
		autoClock = 0
		for _, rec in snapshot(autos) do
			if alive(rec) then
				autoCheck(rec)
			else
				drop(rec)
			end
		end
	end
	sweepClock += dt
	if sweepClock >= SWEEP_SECONDS then
		sweepClock = 0
		sweep()
	end
end

-- Player request (prompt). `side` is the prompt's Side attribute and only advisory: the player's
-- position relative to SecureNormal decides whether this is egress.
function Doors.request(player: Player, door: Model, side: string?): (boolean, string?)
	local _ = side
	local rec = ensure(door)
	if rec == nil then
		return false, "This door is not connected."
	end
	local character = player.Character
	local root = rootOf(character)
	if root == nil or (root.Position - rec.centre).Magnitude > REQUEST_RANGE then
		return false, "Move closer to the door."
	end
	local inside = secureSide(rec, root.Position)
	if rec.kind == "cubicle" then
		if rec.state == "open" or rec.state == "opening" then
			rec.lastUser = player.Name
			beginClose(rec, true) -- toggle shut; collision returns once the doorway is clear
			return true
		end
		if not inside then
			if rec.locked then
				flash(rec, "bad")
				return false, "Locked."
			end
			local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
			if toiletBusy(rec, humanoid) then
				flash(rec, "busy")
				return false, "Occupied"
			end
		end
		grant(rec, player.Name)
		return true
	end
	if inside then
		grant(rec, player.Name) -- egress always works
		return true
	end
	if rec.locked then
		flash(rec, "bad")
		return false, "Locked."
	end
	local ok, reason = authorize(player, rec)
	if not ok then
		flash(rec, "bad")
		return false, reason or "Access denied."
	end
	grant(rec, player.Name)
	return true
end

-- Employee request (navigation). The NPC must belong to the door's office and stand close.
function Doors.requestNPC(npc: Model, door: Model): boolean
	local rec = ensure(door)
	if rec == nil or rec.hidden then
		return false
	end
	local office = npc:FindFirstAncestor("Office")
	if office == nil or office ~= rec.office or door:FindFirstAncestor("Office") ~= office then
		return false
	end
	if npc:GetAttribute("OwnerUserId") ~= office:GetAttribute("OwnerUserId") then
		return false
	end
	local root = rootOf(npc)
	if root == nil or (root.Position - rec.centre).Magnitude > NPC_RANGE then
		return false
	end
	if not secureSide(rec, root.Position) then
		local roleAttr = npc:GetAttribute("RoleId")
		local role = if typeof(roleAttr) == "string" then roleAttr else "support"
		if rec.locked or not Plan.roleAllows(role, rec.access) then
			flash(rec, "bad")
			return false
		end
		if rec.kind == "cubicle" and toiletBusy(rec, npc:FindFirstChildOfClass("Humanoid")) then
			return false
		end
	end
	local name = npc:GetAttribute("EmployeeName")
	grant(rec, if typeof(name) == "string" then name else npc.Name)
	return true
end

function Doors.state(door: Model): string
	local rec = ensure(door)
	if rec then
		return stateOf(rec)
	end
	local attr = door:GetAttribute("DoorState")
	return if typeof(attr) == "string" then attr else "unknown"
end

function Doors.isPassable(door: Model): boolean
	local rec = ensure(door)
	return rec ~= nil and rec.state == "open"
end

function Doors.doorsNear(office: Model, position: Vector3, radius: number): { Model }
	local reg = offices[office]
	if reg == nil then
		return {}
	end
	local found: { { model: Model, d: number } } = {}
	for model, rec in reg.doors do
		local d = (rec.centre - position).Magnitude
		if d <= radius and model.Parent then
			table.insert(found, { model = model, d = d })
		end
	end
	table.sort(found, function(a, b)
		return a.d < b.d
	end)
	local out: { Model } = {}
	for _, f in found do
		table.insert(out, f.model)
	end
	return out
end

function Doors.find(office: Model, doorId: string): Model?
	local reg = offices[office]
	local rec = if reg then reg.byId[doorId] else nil
	if rec and alive(rec) then
		return rec.model
	end
	local folder = office:FindFirstChild("Doors")
	local model = if folder then folder:FindFirstChild("Door_" .. doorId, true) else nil
	if model and model:IsA("Model") and ensure(model) then
		return model
	end
	return nil
end

-- Lockdown: blocks entry from the non-secure side; egress keeps working.
function Doors.lockAll(office: Model, locked: boolean)
	local reg = offices[office]
	if reg == nil then
		return
	end
	for _, rec in reg.doors do
		rec.locked = locked
		if locked and rec.kind ~= "cubicle" and (rec.state == "open" or rec.state == "opening") then
			beginClose(rec, false)
		end
		publish(rec)
	end
end

function Doors.inspect(office: Model): { DoorInfo }
	local out: { DoorInfo } = {}
	local reg = offices[office]
	if reg then
		for _, rec in reg.doors do
			table.insert(out, { id = rec.id, kind = rec.kind, state = stateOf(rec), access = rec.access, lastUser = rec.lastUser })
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

return Doors
