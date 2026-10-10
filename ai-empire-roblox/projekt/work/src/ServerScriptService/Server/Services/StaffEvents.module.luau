--!strict
-- StaffEvents (staffops): visible company flows that are more than one task at one station. Run by
-- StaffService (helpers injected with bind(), like StaffJobs); ANIMATION ONLY - money, output, faults and
-- graduations are decided by CompanyOps / EmpireService, these flows only show them.
--  * First day: a new hire (auto-HR, agency or interview) arrives from the street (or the visitor lounge),
--    checks in at the reception (badge printer) and walks to the new desk.
--  * Rack faults (CompanyOps.faults, user request 23): the faulty data-hall blade gets FxState "broken" plus
--    FaultSlot / FaultUntil (the economy's own repair estimate) for the client (PropFxController: red LEDs,
--    beacon, "Rack R3 · fault · capacity -1"). IT Support (or an engineer where IT may not enter / there is no
--    IT post) walks to the rack with a laptop and repairs it in a pose loop until the ECONOMY clears the fault;
--    someone who arrives after the fix still does a short closing step.
--  * Apprentices (CORE_SPEC 11.1, user request 18): the Training Lead leads a tour group of first-day
--    apprentices past 4-6 rooms (stop in front of the door, "present" pose, Task "Tour:<room id>" for the
--    talk lines), runs one training session a day in a meeting room (apprentices seated, the trainer
--    standing at the head of the table), and coaches apprentices at their desks; apprentices otherwise
--    practise at their own desk or sit next to a senior colleague (shadowing).
-- Cheap: one office pass per second for faults and the academy, no per-frame work, one attribute write per
-- state change. Every walk goes through StaffJobs.moveTo (movers cap, bounded navigation).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Collection = game:GetService("CollectionService")
local Config = require(ReplicatedStorage.Shared.Config.EmployeeConfig)
local Plan = require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Layout = require(ReplicatedStorage.Shared.BuildingLayout)
local Ops = require(ReplicatedStorage.Shared.CompanyOps)
local Workstations = require(script.Parent.WorkstationService)
local Nav = require(script.Parent.EmployeeNavigation)
local Jobs = require(script.Parent.StaffJobs)

local Events = {}
type Api = {
	now: () -> number,
	hour: () -> number,
	state: (e: any, name: string) -> (),
	jitter: (e: any, max: number) -> number,
	begin: (e: any, def: any, w: any) -> (),
}
local api: Api = {
	now = function(): number
		return 0
	end,
	hour = function(): number
		return 12
	end,
	state = function(_e: any, _name: string) end,
	jitter = function(_e: any, _max: number): number
		return 0
	end,
	begin = function(_e: any, _def: any, _w: any) end,
}
function Events.bind(a: Api)
	api = a
end

Events.WORK_STATE = { researcher = "RESEARCH", engineer = "WORKING", curator = "DATA_REVIEW", marketer = "MARKETING" }
Events.REPAIR_POSES = {
	{ pose = "inspect", item = "laptop" },
	{ pose = "typeStand", item = "laptop" },
	{ pose = "plug", item = "" },
	{ pose = "reach", item = "blade" },
	{ pose = "typeStand", item = "laptop" },
} :: { { pose: string, item: string } }
Events.CLOSE_SECONDS = 4 -- closing step after the economy cleared a fault (log the fix, close the rack)
Events.REPAIR_RETRY = 20 -- a fault nobody could reach is offered again after this many seconds
Events.GATHER_SECONDS = 45 -- a tour stop / training session starts at the latest this long after the call
Events.BADGE_SECONDS = 5

-- Per office state that must survive a staff rebuild (records are recreated, the office model stays).
type Memory = { toured: { [number]: boolean }, sessionDay: number?, pending: { [number]: any } }
local memory: { [Instance]: Memory } = setmetatable({}, { __mode = "k" }) :: any
local function mem(office: Instance): Memory
	local m = memory[office]
	if not m then
		m = { toured = {}, sessionDay = nil, pending = {} }
		memory[office] = m
	end
	return m
end
Events.memory = mem

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
local function face(e: any, point: Vector3?)
	if not point or not e.root.Parent or e.humanoid.SeatPart then
		return
	end
	e.root.Anchored = false
	e.humanoid.AutoRotate = false
	local d = Vector3.new(point.X - e.root.Position.X, 0, point.Z - e.root.Position.Z)
	if d.Magnitude > 0.2 then
		e.root.CFrame = CFrame.lookAt(e.root.Position, e.root.Position + d)
	end
	e.root.Anchored = true
end
local function setTask(e: any, id: string, state: string?)
	e.task = { id = id, state = state or e.state }
	e.model:SetAttribute("Task", id)
end
-- Normal life again: StaffService picks the next task (selectTask / StaffJobs.next) on the next tick.
local function done(e: any, delay: number?)
	e.event = nil
	Workstations.setItem(e, nil)
	Workstations.setPose(e, nil)
	if e.root.Parent and not e.humanoid.SeatPart then
		e.root.Anchored = false
	end
	api.state(e, "SELECT_TASK")
	e.next = api.now() + (delay or 1)
end
-- Free for an event: awake, on duty, not walking/eating/talking/riding, not already in an event.
function Events.free(e: any): boolean
	return not e.dead
		and e.root.Parent ~= nil
		and e.lod ~= "sleep"
		and not e.talkHold
		and e.event == nil
		and e.lunch == nil
		and e.onDuty == true
		and e.state ~= "OFF_DUTY"
		and e.state ~= "LEAVING"
		and e.state ~= "ARRIVING"
		and e.state ~= "INACTIVE"
		and not e.forced
		and not Nav.liftBusy(e)
end
local function stop(e: any, c: any)
	-- leaves whatever it was doing (job step, desk, walk) without moving
	Jobs.abort(e, c)
	Nav.cancel(e)
	Workstations.release(e)
	e.pendingWalk = nil
	e.walkTask = nil
	e.next = math.huge
end
local function local_(e: any, p: Vector3): Vector3
	return e.cf:PointToObjectSpace(p)
end
local function floorPoint(e: any, p: Vector3): Vector3?
	-- the same spot at root height on its plan level (building-local Y = level Y + 3)
	local l = local_(e, p)
	local level = Plan.levelAt(e.tier, l.Y)
	if level == nil then
		return nil
	end
	return e.cf * Vector3.new(l.X, Plan.levelY(level) + 3, l.Z)
end

---------------------------------------------------------------------------------------------
-- First day
---------------------------------------------------------------------------------------------
-- Check-in point in front of reception (post 1): beside the receptionist's greeting spot, facing it.
local function checkIn(c: any): (Vector3?, Vector3?, string?)
	if c.tier < 1 then
		return nil, nil, nil
	end
	for _, w in Workstations.scan(c.office).byKind.Service or {} do
		if w.model:GetAttribute("OpsIndex") == 1 then
			local g = w.model:GetAttribute("JobPoint_greet")
			local f = w.model:GetAttribute("JobFace_greet")
			local prop = w.model:GetAttribute("JobProp_printer")
			if typeof(g) == "Vector3" and typeof(f) == "Vector3" then
				local d = Vector3.new(f.X - g.X, 0, f.Z - g.Z)
				if d.Magnitude > 0.1 then
					return g + d.Unit * 2.6, g, if typeof(prop) == "string" then prop else nil
				end
			end
			local facing = w.model:GetAttribute("FacingPosition")
			if typeof(facing) == "Vector3" then
				local d = Vector3.new(facing.X - w.position.X, 0, facing.Z - w.position.Z)
				if d.Magnitude > 0.1 then
					return w.position + d.Unit * 5, w.position, if typeof(prop) == "string" then prop else nil
				end
			end
		end
	end
	return nil, nil, nil
end
-- A new hire arrives (from: where they appear; nil = where they stand). Reception first, then the desk.
function Events.arrive(e: any, c: any, from: CFrame?)
	stop(e, c)
	if from and e.root.Parent then
		e.model:PivotTo(from)
	end
	e.root.Anchored = false
	e.humanoid.EvaluateStateMachine = true
	e.model:SetAttribute("OffDuty", false)
	e.firstDay = true
	setTask(e, "FirstDay", "ARRIVING")
	api.state(e, "ARRIVING")
	local point, receptionist, prop = checkIn(c)
	e.event = { kind = "arrive", phase = "reception", since = api.now() }
	if not point then
		Events.toDesk(e, c)
		return
	end
	local ev = e.event
	Jobs.moveTo(e, c, point, nil, function(ok: boolean)
		if e.event ~= ev then
			return
		end
		if not ok then
			Events.toDesk(e, c)
			return
		end
		face(e, receptionist)
		api.state(e, "ARRIVING")
		Workstations.setPose(e, "reach")
		if prop then
			Workstations.useProp(c.office, prop, 4)
		end
		ev.phase = "badge"
		ev.untilTime = api.now() + Events.BADGE_SECONDS
		ev.itemAt = api.now() + 1.5
	end, true)
end
-- After the badge (or without a reception): the normal walk to the home desk.
function Events.toDesk(e: any, c: any)
	e.event = nil
	Workstations.setItem(e, nil)
	Workstations.setPose(e, nil)
	if e.root.Parent then
		e.root.Anchored = false
	end
	local def = (Config.TASKS[e.role] or Config.TASKS.support)[1]
	local home = Workstations.scan(e.office).byId[e.home] or Workstations.choose(e, def)
	e.next = api.now()
	api.state(e, "SELECT_TASK")
	api.begin(e, def, home)
	if e.task then
		e.model:SetAttribute("Task", e.task.id)
	end
end
-- Interview hire: the new employee takes over from the visitor rig (RecruitingService), or a hire made
-- while the person is off duty arrives through reception at the next shift start. `hold`: the candidate
-- is still walking out to the speed gates; the rig stays hidden until Events.handover (at most HOLD_SECONDS).
local HOLD_SECONDS = 120
function Events.expect(office: Instance, seed: number, from: CFrame?, hold: boolean?)
	mem(office).pending[seed] = { from = from, at = api.now(), hold = if hold then true else nil }
end
-- The visitor rig is gone at `from`: a held arrival starts there (a hire that is off duty by now, or
-- whose hold ran out, is left alone and arrives normally).
function Events.handover(office: Instance, seed: number, from: CFrame?)
	local m = memory[office]
	local p = if m then m.pending[seed] else nil
	if p and p.hold then
		p.hold = nil
		p.from = from
	end
end
function Events.held(office: Instance, seed: number): boolean
	local m = memory[office]
	local p = if m then m.pending[seed] else nil
	return p ~= nil and p.hold == true and api.now() - p.at < HOLD_SECONDS
end
function Events.claim(office: Instance, seed: number): any
	local m = memory[office]
	local p = if m then m.pending[seed] else nil
	if p then
		m.pending[seed] = nil
	end
	return p
end
function Events.pending(office: Instance, seed: number): boolean
	local m = memory[office]
	return m ~= nil and m.pending[seed] ~= nil
end

---------------------------------------------------------------------------------------------
-- Rack faults
---------------------------------------------------------------------------------------------
-- The rack door / LED prop of a blade (PropFx "leds" within a stud of the blade), cached per office.
local function doorOf(c: any, blade: BasePart): Instance?
	c.rackDoors = c.rackDoors or {}
	local cached = c.rackDoors[blade]
	if cached ~= nil then
		return if cached then cached else nil
	end
	local best, dist = nil, 1.2
	for _, root in Collection:GetTagged("PropFx") do
		if root:IsA("BasePart") and root:IsDescendantOf(c.office) then
			local fx = root:GetAttribute("Fx")
			if typeof(fx) == "string" and string.find(fx, "leds", 1, true) then
				local d = (root.Position - blade.Position).Magnitude
				if d < dist then
					best, dist = root, d
				end
			end
		end
	end
	c.rackDoors[blade] = best or false
	return best
end
-- Stand point in front of a blade (racks face their aisle with -Z, StaffAssignment/ArchKit.serverRack).
function Events.rackPoint(e: any, blade: BasePart): (Vector3?, Vector3)
	local look = blade.CFrame.LookVector
	local dir = Vector3.new(look.X, 0, look.Z)
	if dir.Magnitude < 0.1 then
		dir = Vector3.new(0, 0, -1)
	end
	local p = floorPoint(e, blade.Position + dir.Unit * 1.7)
	return p, blade.Position
end
local function bladeAt(c: any, slot: number): BasePart?
	local blades = c.office:FindFirstChild("Blades")
	local b = if blades then blades:GetChildren()[slot] else nil
	return if b and b:IsA("BasePart") then b else nil
end
-- Mirrors the economy's fault list onto the blades: FxState "broken" + FaultSlot + FaultUntil (server time
-- of the economy's own repair estimate: remaining work / repair rate, rate = 1/60 s with IT on duty, else
-- 1/300 s). Writes only when something changes (FaultUntil when the estimate moves by more than 3 s).
function Events.syncRacks(c: any, s: any, clock: number): { [number]: any }
	local e = s.data.empire
	local want: { [number]: any } = {}
	for _, f in Ops.faults(e) do
		want[f.slot] = f
	end
	c.brokenBlades = c.brokenBlades or {}
	local rate = if Ops.itOnDuty(e, clock) then 1 / Ops.FAULT.it else 1 / Ops.FAULT.alone
	local now = workspace:GetServerTimeNow()
	local still: { [BasePart]: boolean } = {}
	local doors: { [Instance]: boolean } = {}
	for slot, f in want do
		local blade = bladeAt(c, slot)
		if not blade then
			continue
		end
		still[blade] = true
		if blade:GetAttribute("FxState") ~= "broken" then
			blade:SetAttribute("FaultSlot", slot)
			blade:SetAttribute("FxState", "broken")
		end
		local eta = math.floor(now + math.max(0, tonumber(f.left) or 0) / rate + 0.5)
		local cur = blade:GetAttribute("FaultUntil")
		if typeof(cur) ~= "number" or math.abs(cur - eta) > 3 then
			blade:SetAttribute("FaultUntil", eta)
		end
		local door = doorOf(c, blade)
		if door then
			doors[door] = true
			if door:GetAttribute("FxState") ~= "broken" then
				door:SetAttribute("FaultSlot", slot)
				door:SetAttribute("FxState", "broken")
			end
		end
		c.brokenBlades[blade] = door or false
	end
	for blade, door in c.brokenBlades do
		if not still[blade] then
			c.brokenBlades[blade] = nil
			if blade.Parent then
				blade:SetAttribute("FxState", "idle")
				blade:SetAttribute("FaultSlot", nil)
				blade:SetAttribute("FaultUntil", nil)
			end
			if door and not doors[door] and door.Parent then
				door:SetAttribute("FxState", "idle")
				door:SetAttribute("FaultSlot", nil)
			end
		end
	end
	return want
end
-- Who repairs: IT Support where the rack is inside IT's access classes, else an engineer.
local function canReach(c: any, e: any, blade: BasePart): Vector3?
	local p = Events.rackPoint(e, blade)
	if not p then
		return nil
	end
	if not Plan.employeeAllowed(e.role, c.tier, local_(e, p)) then
		return nil
	end
	return p
end
local function pickWorker(c: any, blade: BasePart): (any, Vector3?)
	local engineer, ep, edist = nil, nil, math.huge
	for _, e in c.all do
		if not Events.free(e) or e.apprentice then
			continue
		end
		if e.role == "support" and e.model:GetAttribute("Role") == "IT Support" then
			local p = canReach(c, e, blade)
			if p then
				return e, p
			end
		elseif e.role == "engineer" then
			local p = canReach(c, e, blade)
			if p then
				local d = flat(e.root.Position, p) + math.abs(e.root.Position.Y - p.Y) * 4
				if d < edist then
					engineer, ep, edist = e, p, d
				end
			end
		end
	end
	return engineer, ep
end
local function startRepair(e: any, c: any, slot: number, blade: BasePart, point: Vector3)
	stop(e, c)
	local ev: any = { kind = "repair", slot = slot, blade = blade, phase = "go", since = api.now(), step = 0, cleared = false }
	e.event = ev
	c.repairs[slot] = e
	setTask(e, "RackRepair", "SERVER_CHECK")
	Workstations.setItem(e, "laptop")
	Workstations.setPose(e, nil)
	api.state(e, "WALKING")
	Jobs.moveTo(e, c, point, nil, function(ok: boolean)
		if e.event ~= ev then
			return
		end
		if not ok then
			c.repairs[slot] = nil
			c.repairRetry[slot] = api.now() + Events.REPAIR_RETRY
			done(e)
			return
		end
		face(e, blade.Position)
		api.state(e, "SERVER_CHECK")
		ev.phase = if ev.cleared then "close" else "repair"
		ev.stepAt = api.now()
		ev.untilTime = if ev.cleared then api.now() + Events.CLOSE_SECONDS else nil
		if ev.cleared then
			Workstations.setPose(e, "typeStand")
			Workstations.setItem(e, "laptop")
		end
	end, true)
end
-- One pass per second: blade states, cleared faults, new repairs.
function Events.rackTick(c: any, s: any, clock: number)
	c.repairs = c.repairs or {}
	c.repairRetry = c.repairRetry or {}
	local want = Events.syncRacks(c, s, clock)
	for slot, e in c.repairs do
		local ev = e.event
		if not ev or ev.kind ~= "repair" or ev.slot ~= slot or not c.recordsSet[e] then
			c.repairs[slot] = nil
		elseif not want[slot] and not ev.cleared then
			-- the ECONOMY fixed it: finish the animation (now, or right after arriving)
			ev.cleared = true
			if ev.phase == "repair" then
				ev.phase = "close"
				ev.untilTime = api.now() + Events.CLOSE_SECONDS
				Workstations.setPose(e, "typeStand")
				Workstations.setItem(e, "laptop")
			end
		end
	end
	for slot in want do
		if c.repairs[slot] or (c.repairRetry[slot] or 0) > api.now() then
			continue
		end
		local blade = bladeAt(c, slot)
		if blade then
			local worker, point = pickWorker(c, blade)
			if worker and point then
				startRepair(worker, c, slot, blade, point)
			end
		end
	end
	for slot in c.repairRetry do
		if not want[slot] then
			c.repairRetry[slot] = nil
		end
	end
end

---------------------------------------------------------------------------------------------
-- Apprentices: tour, training session, shadowing; the Training Lead
---------------------------------------------------------------------------------------------
local TOUR_KINDS: { [string]: number } = {
	-- room kind -> priority (lower first); department rooms of the group come first anyway
	cafe = 2,
	hr = 3,
	datalab = 4,
	architecture = 4,
	control = 4,
	evaluation = 5,
	lab = 5,
	launch = 5,
	studio = 6,
	support = 6,
	platform = 6,
	team = 7,
	showroom = 8,
	gym = 8,
	boardroom = 9,
	datahall = 9,
}
-- Door stop of a room: a point in the corridor in front of its first usable door + the look-in point.
local function doorStop(c: any, roomId: string): (Vector3?, Vector3?)
	for _, d in Layout.doors(c.tier) do
		if d.room == roomId and not d.exterior and not d.hidden then
			local base = Vector3.new(d.x, Plan.levelY(d.level) + 3, d.z)
			local out = base - d.inward * 4
			local into = base + d.inward * 3
			return c.cf * out, c.cf * into
		end
	end
	return nil, nil
end
local function allowedAll(c: any, group: { any }, p: Vector3): boolean
	local l = c.cf:PointToObjectSpace(p)
	for _, e in group do
		if not Plan.employeeAllowed(e.role, c.tier, l) then
			return false
		end
	end
	return true
end
-- 4-6 stops: the group's own departments first, then the café, HR, labs ...; ordered as a walk.
function Events.tourStops(c: any, lead: any, group: { any }): { any }
	local depts: { [string]: boolean } = {}
	local reg = Workstations.scan(c.office)
	for _, e in group do
		local w = reg.byId[e.home]
		if w and typeof(w.department) == "string" then
			depts[w.department] = true
		end
	end
	local everyone = table.clone(group)
	table.insert(everyone, lead)
	local candidates = {}
	for _, r in Plan.rooms(c.tier) do
		if r.hidden or r.outdoor then
			continue
		end
		local prio = TOUR_KINDS[r.kind]
		if r.dept and depts[r.dept] and r.desks and r.desks > 1 then
			prio = 1
		end
		if not prio then
			continue
		end
		if not Plan.roleAllows(lead.role, r.access) then
			continue
		end
		local p, look = doorStop(c, r.id)
		if p and look and allowedAll(c, everyone, p) then
			table.insert(candidates, { room = r, point = p, look = look, prio = prio })
		end
	end
	table.sort(candidates, function(a: any, b: any): boolean
		if a.prio ~= b.prio then
			return a.prio < b.prio
		end
		return tostring(a.room.id) < tostring(b.room.id)
	end)
	local A = Config.APPRENTICE
	local seed = if group[1] then group[1].personality.seed else 0
	local want = A.tourStops[1] + seed % (A.tourStops[2] - A.tourStops[1] + 1)
	local picked = {}
	local kinds: { [string]: boolean } = {}
	for _, cand in candidates do
		if #picked >= want then
			break
		end
		local k = if cand.prio == 1 then "dept:" .. tostring(cand.room.dept) else cand.room.kind
		if not kinds[k] then
			kinds[k] = true
			table.insert(picked, cand)
		end
	end
	-- walking order: nearest next stop from the trainer, a level change counts as 80 studs
	local ordered = {}
	local here = lead.root.Position
	while #picked > 0 do
		local bi, bd = 1, math.huge
		for i, cand in picked do
			local d = flat(here, cand.point) + math.abs(here.Y - cand.point.Y) / Plan.FLOOR_HEIGHT * 80
			if d < bd then
				bi, bd = i, d
			end
		end
		local cand = table.remove(picked, bi) :: any
		table.insert(ordered, cand)
		here = cand.point
	end
	return ordered
end
local function trainer(c: any): any
	for _, e in c.all do
		if e.role == "support" and e.model:GetAttribute("Role") == "Training Lead" and not e.dead then
			return e
		end
	end
	return nil
end
Events.trainer = trainer
-- Group members walk to a point next to the trainer's stop point (behind him, in a short row).
local function memberPoint(c: any, group: { any }, stopPoint: Vector3, look: Vector3, k: number): Vector3
	local dir = Vector3.new(look.X - stopPoint.X, 0, look.Z - stopPoint.Z)
	if dir.Magnitude < 0.1 then
		return stopPoint
	end
	dir = dir.Unit
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local n = #group
	local p = stopPoint - dir * 2.4 + right * ((k - (n + 1) / 2) * 1.9)
	if allowedAll(c, group, p) then
		return p
	end
	return stopPoint - dir * 2.0
end
local function endTour(c: any, completed: boolean)
	local t = c.tour
	if not t then
		return
	end
	c.tour = nil
	local m = mem(c.office)
	for _, e in t.group do
		if e.event == t.ev then
			if completed then
				m.toured[e.personality.seed] = true
			end
			done(e, 1 + api.jitter(e, 3))
		end
	end
	if t.lead and t.lead.event == t.ev then
		done(t.lead, 2)
	end
end
local function tourStop(c: any)
	local t = c.tour
	local stopDef = t.stops[t.index]
	if not stopDef then
		endTour(c, true)
		return
	end
	t.phase = "walk"
	t.arrived = {}
	t.callAt = api.now()
	local ev = t.ev
	setTask(t.lead, "ApprenticeTour", "WALKING")
	Workstations.setPose(t.lead, nil)
	Jobs.moveTo(t.lead, c, stopDef.point, nil, function(ok: boolean)
		if c.tour ~= t or t.lead.event ~= ev then
			return
		end
		t.arrived[t.lead] = true
		if ok then
			face(t.lead, stopDef.look)
		end
		api.state(t.lead, "WORKING")
	end, true)
	for k, e in t.group do
		if e.event ~= ev or e.talkHold then
			continue -- a member in a conversation catches up at the next stop
		end
		local p = memberPoint(c, t.group, stopDef.point, stopDef.look, k)
		setTask(e, "ApprenticeTour", "WALKING")
		Workstations.setPose(e, nil)
		Jobs.moveTo(e, c, p, nil, function(_ok: boolean)
			if c.tour ~= t or e.event ~= ev then
				return
			end
			t.arrived[e] = true
			face(e, stopDef.point)
			api.state(e, "WORKING")
		end, true)
	end
end
local function startTour(c: any, lead: any, group: { any })
	local stops = Events.tourStops(c, lead, group)
	if #stops == 0 then
		local m = mem(c.office)
		for _, e in group do
			m.toured[e.personality.seed] = true -- nothing to show in this building: count it as done
		end
		return
	end
	local ev = { kind = "tour" }
	c.tour = { lead = lead, group = group, stops = stops, index = 1, ev = ev }
	stop(lead, c)
	lead.event = ev
	for _, e in group do
		stop(e, c)
		e.event = ev
	end
	tourStop(c)
end
local function tourTick(c: any)
	local t = c.tour
	if not t then
		return
	end
	local now = api.now()
	if not t.lead.event or t.lead.event ~= t.ev or not c.recordsSet[t.lead] then
		endTour(c, false)
		return
	end
	if t.lead.talkHold then
		-- the founder talks to the trainer: the tour waits (the stop timer is pushed back)
		t.callAt = now
		t.untilTime = if t.untilTime then t.untilTime + 1 else nil
		return
	end
	local members = 0
	for _, e in t.group do
		if e.event == t.ev then
			members += 1
		end
	end
	if members == 0 then
		endTour(c, false)
		return
	end
	if t.phase == "walk" then
		local all = t.arrived[t.lead] == true
		if all then
			for _, e in t.group do
				if e.event == t.ev and not t.arrived[e] then
					all = false
				end
			end
		end
		if all or (t.arrived[t.lead] and now - t.callAt > Events.GATHER_SECONDS) or now - t.callAt > Events.GATHER_SECONDS * 2 then
			local stopDef = t.stops[t.index]
			t.phase = "explain"
			local A = Config.APPRENTICE
			t.untilTime = now + A.stopSeconds[1] + api.jitter(t.lead, A.stopSeconds[2] - A.stopSeconds[1])
			setTask(t.lead, "Tour:" .. tostring(stopDef.room.id), "WORKING")
			Workstations.setPose(t.lead, "present")
			for _, e in t.group do
				if e.event == t.ev then
					setTask(e, "ApprenticeTour", "WORKING")
					Workstations.setPose(e, "scan")
				end
			end
		end
	elseif t.phase == "explain" and now >= (t.untilTime or 0) then
		t.index += 1
		tourStop(c)
	end
end
-- Meeting room for the training session: free seats for the group + the trainer, close to the trainer.
local function sessionRoom(c: any, lead: any, group: { any }): (any, { any })
	local here = lead.root.Position
	local best, seats, score = nil, {}, math.huge
	for _, r in Workstations.scan(c.office).meetings do
		local open = {}
		for _, w in r.seats do
			if w.model.Parent and not w.reserved and not (w.seat and w.seat.Occupant) and Workstations.allowed(w, lead) then
				local ok = true
				for _, e in group do
					if not Workstations.allowed(w, e) then
						ok = false
						break
					end
				end
				if ok then
					table.insert(open, w)
				end
			end
		end
		if #open < #group + 1 or #open == 0 then
			continue
		end
		local p = open[1].position
		local d = flat(here, p) + math.abs(here.Y - p.Y) / Plan.FLOOR_HEIGHT * 80
		if d < score then
			best, seats, score = r, open, d
		end
	end
	return best, seats
end
local function endSession(c: any)
	local t = c.lesson
	if not t then
		return
	end
	c.lesson = nil
	for _, e in t.group do
		if e.event == t.ev then
			Workstations.release(e)
			done(e, 1 + api.jitter(e, 4))
		end
	end
	if t.lead.event == t.ev then
		Workstations.release(t.lead)
		done(t.lead, 2)
	end
	if c.office:GetAttribute("MeetingTopic") == "APPRENTICE TRAINING" then
		c.office:SetAttribute("MeetingUntil", 0)
	end
end
local function seatWalk(e: any, c: any, w: any, ev: any, stand: boolean, onSeat: () -> ())
	if not Workstations.reserve(w, e) then
		return false
	end
	Jobs.moveTo(e, c, w.position, nil, function(ok: boolean)
		if e.event ~= ev then
			return
		end
		if ok and e.station == w and Workstations.perform(e, api.now(), if stand then { stand = true } else nil) then
			onSeat()
		else
			api.state(e, "WAIT_AT_DESK")
		end
	end, true)
	return true
end
local function startSession(c: any, lead: any, group: { any }, untilHour: number)
	local room, seats = sessionRoom(c, lead, group)
	if not room then
		return false
	end
	-- the trainer takes the end seat farthest from the seats' centre ("head of the table")
	local centre = Vector3.zero
	for _, w in seats do
		centre += w.position
	end
	centre /= #seats
	table.sort(seats, function(a: any, b: any): boolean
		return flat(a.position, centre) > flat(b.position, centre)
	end)
	local ev = { kind = "session" }
	local t = { lead = lead, group = group, ev = ev, room = room, untilHour = untilHour, started = api.now(), seated = {} }
	c.lesson = t
	stop(lead, c)
	lead.event = ev
	setTask(lead, "TrainingLead", "MEETING")
	api.state(lead, "WALKING")
	seatWalk(lead, c, seats[1], ev, true, function()
		face(lead, centre)
		api.state(lead, "MEETING")
		setTask(lead, "TrainingLead", "MEETING")
		Workstations.setPose(lead, "present")
		t.seated[lead] = true
	end)
	local k = 2
	for _, e in group do
		stop(e, c)
		e.event = ev
		local w = seats[k]
		k += 1
		setTask(e, "TrainingSession", "MEETING")
		api.state(e, "WALKING")
		if not w or not seatWalk(e, c, w, ev, false, function()
			api.state(e, "MEETING")
			setTask(e, "TrainingSession", "MEETING")
			t.seated[e] = true
		end) then
			done(e)
		end
	end
	Events.showSession(c, t)
	return true
end
-- The room's meeting screen / speakerphone (PropFx gate "Meeting") shows the session while no other
-- meeting holds the office's meeting display; extended in 60 s steps while the session runs.
function Events.showSession(c: any, t: any)
	local now = workspace:GetServerTimeNow()
	local untilTime = tonumber(c.office:GetAttribute("MeetingUntil")) or 0
	local mine = c.office:GetAttribute("MeetingTopic") == "APPRENTICE TRAINING" and c.office:GetAttribute("MeetingRoom") == tostring(t.room.id)
	if mine and untilTime > now then
		if untilTime - now < 20 then
			c.office:SetAttribute("MeetingUntil", now + 60)
		end
	elseif untilTime < now then
		c.office:SetAttribute("MeetingTopic", "APPRENTICE TRAINING")
		c.office:SetAttribute("MeetingRoom", tostring(t.room.id))
		c.office:SetAttribute("MeetingUntil", now + 90)
	end
end
local function sessionTick(c: any, hour: number)
	local t = c.lesson
	if not t then
		return
	end
	if t.lead.event ~= t.ev or not c.recordsSet[t.lead] then
		endSession(c)
		return
	end
	local members = 0
	for _, e in t.group do
		if e.event == t.ev then
			members += 1
		end
	end
	local minimum = api.now() - t.started > 40
	if members == 0 or (minimum and (hour >= t.untilHour or hour < 8)) or api.now() - t.started > 240 then
		endSession(c)
		return
	end
	Events.showSession(c, t)
end
-- Who of the apprentices is available for a group event now.
local function availableApprentices(c: any, filter: (e: any) -> boolean): { any }
	local out = {}
	for _, e in c.all do
		if e.apprentice and Events.free(e) and filter(e) then
			table.insert(out, e)
		end
	end
	table.sort(out, function(a: any, b: any): boolean
		return a.index < b.index
	end)
	return out
end
-- One pass per second: tour / session start and progress.
function Events.academyTick(c: any, hour: number, workday: number)
	tourTick(c)
	sessionTick(c, hour)
	if c.tour or c.lesson then
		return
	end
	local lead = trainer(c)
	if not lead or not Events.free(lead) then
		return
	end
	local A = Config.APPRENTICE
	local m = mem(c.office)
	if hour >= A.tourHours[1] and hour < A.tourHours[2] then
		local group = availableApprentices(c, function(e: any): boolean
			return e.apprentice.age <= 1 and not m.toured[e.personality.seed]
		end)
		if #group > 0 then
			startTour(c, lead, group)
			return
		end
	end
	if hour >= A.trainingHours[1] and hour < A.trainingHours[2] - 0.25 and m.sessionDay ~= workday then
		local group = availableApprentices(c, function(e: any): boolean
			return e.apprentice.age >= 1 or m.toured[e.personality.seed] == true
		end)
		if #group > 0 and startSession(c, lead, group, A.trainingHours[2]) then
			m.sessionDay = workday
		end
	end
end
-- Apprentice task choice (StaffService.selectTask after lunch and breaks): sit next to a senior colleague
-- of the same role every few choices, otherwise practise at the own desk. True = a task was started.
function Events.apprenticeTask(e: any, c: any): boolean
	local A = Config.APPRENTICE
	e.choices = (e.choices or 0) + 1
	local state = Events.WORK_STATE[e.role] or "WORKING"
	local reg = Workstations.scan(e.office)
	local homeW = reg.byId[e.home]
	if e.choices % A.shadowEvery == 0 then
		local here = e.root.Position
		local best, bw, bd = nil, nil, math.huge
		for _, o in c.all do
			if o == e or o.role ~= e.role or o.apprentice or o.dead or not o.station or o.station.kind ~= "Computer" then
				continue
			end
			if (o.skillK or 0) < 3 or Config.productive(o.state) < 1 then
				continue
			end
			-- the free desk nearest to the senior's desk, in the same room
			local sw = o.station
			for _, w in reg.byKind.Computer or {} do
				if w ~= sw and w.room == sw.room and Workstations.available(w, e) and not w.reserved then
					local dd = flat(w.position, sw.position)
					if dd <= 7 then
						local score = dd + flat(here, w.position) * 0.05
						if score < bd then
							best, bw, bd = o, w, score
						end
					end
				end
			end
		end
		if best and bw then
			e.model:SetAttribute("ShadowOf", best.name)
			api.begin(e, { id = "Shadowing", type = "Computer", department = bw.department, seconds = { 50, 90 }, state = state }, bw)
			return true
		end
	end
	e.model:SetAttribute("ShadowOf", nil)
	local def = { id = "Practice", type = "Computer", department = if homeW then homeW.department else nil, seconds = { 60, 140 }, state = state }
	local w = if homeW and Workstations.available(homeW, e) then homeW else Workstations.choose(e, def)
	if not w then
		return false
	end
	api.begin(e, def, w)
	return true
end
-- Training Lead job step "coach" (StaffJobs special): stand beside an apprentice working at a desk.
local function coach(e: any, c: any, step: any, time: number): boolean
	local target, bp = nil, nil
	local here = e.root.Position
	local bd = math.huge
	for _, o in c.all do
		if o.apprentice and not o.dead and o.station and o.station.kind == "Computer" and o.humanoid.SeatPart and not o.event then
			local w = o.station
			local f = w.model:GetAttribute("FacingPosition")
			if typeof(f) ~= "Vector3" then
				continue
			end
			local back = Vector3.new(w.position.X - f.X, 0, w.position.Z - f.Z)
			if back.Magnitude < 0.1 then
				continue
			end
			local p = w.position + back.Unit * 2.2
			if not Plan.employeeAllowed(e.role, e.tier, local_(e, p)) then
				continue
			end
			local d = flat(here, p) + math.abs(here.Y - p.Y) * 6
			if d < bd then
				target, bp, bd = o, p, d
			end
		end
	end
	if not target or not bp then
		return false
	end
	Jobs.abort(e, c)
	Workstations.release(e)
	e.jobStep = { step = step }
	e.next = math.huge
	setTask(e, "Coaching", "WORKING")
	local who = target
	Jobs.moveTo(e, c, bp, nil, function(ok: boolean)
		if ok then
			face(e, who.root.Position)
		end
		Workstations.setPose(e, step.pose)
		api.state(e, "WORKING")
		e.next = api.now() + step.seconds[1] + api.jitter(e, step.seconds[2] - step.seconds[1])
	end, true)
	return true
end
Jobs.handlers.coach = coach

---------------------------------------------------------------------------------------------
-- Per-employee tick and cancel
---------------------------------------------------------------------------------------------
function Events.busy(e: any): boolean
	return e.event ~= nil
end
function Events.tick(e: any, c: any, time: number)
	local ev = e.event
	if not ev or e.talkHold then
		return
	end
	if ev.kind == "arrive" then
		if ev.phase == "badge" then
			if ev.itemAt and time >= ev.itemAt then
				ev.itemAt = nil
				Workstations.setItem(e, "badge")
			end
			if time >= (ev.untilTime or 0) then
				Events.toDesk(e, c)
			end
		elseif time - ev.since > 120 and not e.nav and not e.hop and not e.pendingMove then
			Events.toDesk(e, c) -- never stuck on the way to reception
		end
	elseif ev.kind == "repair" then
		if ev.phase == "repair" and time >= (ev.stepAt or 0) then
			ev.step = ev.step % #Events.REPAIR_POSES + 1
			local p = Events.REPAIR_POSES[ev.step]
			Workstations.setPose(e, p.pose)
			Workstations.setItem(e, if p.item ~= "" then p.item else nil)
			ev.stepAt = time + 4 + api.jitter(e, 2.5)
		elseif ev.phase == "close" and time >= (ev.untilTime or 0) then
			c.repairs[ev.slot] = nil
			done(e, 1)
		end
	end
	-- tour / session members are driven by the office pass (academyTick)
end
-- Ends this employee's part in an event (LOD sleep, shift end, rebuild). No callbacks fire afterwards
-- (every walk callback compares e.event with its own event table).
function Events.abort(e: any, c: any?)
	local ev = e.event
	if not ev then
		return
	end
	e.event = nil
	if c then
		if ev.kind == "repair" and c.repairs and c.repairs[ev.slot] == e then
			c.repairs[ev.slot] = nil
		elseif ev.kind == "tour" and c.tour and c.tour.lead == e then
			endTour(c, false)
		elseif ev.kind == "session" and c.lesson and c.lesson.lead == e then
			endSession(c)
		end
	end
	Workstations.setItem(e, nil)
	Workstations.setPose(e, nil)
	if e.firstDay and ev.kind == "arrive" then
		e.firstDay = nil
	end
end
return Events
