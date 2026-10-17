--!strict
-- Visible jobs of the campus staff, run by StaffService (which injects its helpers through bind()):
--  * Operations staff (role "support") loop through EmployeeConfig.JOBS[<job title>] steps at and around
--    their post: short direct hops inside the room (Humanoid:MoveTo, counted as movers), the bounded
--    navigation for other rooms, then the step runs in place on a timer. Each step costs one Pose / Holding
--    write on the rig (only when it changes) and at most one FxUntil write on a prop.
--  * Lunch for employees: queue at the café servery, the kitchen team hands out a plate (else self-service
--    after a short wait), eat at the reserved LunchSeat (meal on the table, client-rendered), return the
--    tray to the trolley by the kitchen door. The whole flow keeps the state LUNCH (WALKING while walking),
--    so the break cap and the economic weights (EmployeeConfig.productive) are unchanged.
--  * Operations staff never leave for coffee; they take a short break in place, one per job title at a time.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Collection = game:GetService("CollectionService")
local Config = require(ReplicatedStorage.Shared.Config.EmployeeConfig)
local Plan = require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Workstations = require(script.Parent.WorkstationService)
local Nav = require(script.Parent.EmployeeNavigation)

local Jobs = {}
-- staffops: special job steps handled elsewhere (step.special = name), e.g. the Training Lead's "coach"
-- step (StaffEvents): handler(e, c, step, time) -> started (false = skip the step).
Jobs.handlers = {} :: { [string]: (e: any, c: any, step: any, time: number) -> boolean }
-- the campus day of the ONE visible clock (CORE_SPEC 6): LunchesServed resets with the shown day
local function campusDay(): number
	return math.floor(workspace:GetServerTimeNow() / 1200)
end
type Api = {
	now: () -> number,
	hour: () -> number,
	state: (e: any, name: string) -> (),
	jitter: (e: any, max: number) -> number,
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
}
local HOP_REACH = 1.1 -- horizontal distance at which a hop target counts as reached
local SERVE_SECONDS = 2.5
local SELF_SERVE_AFTER = 6
local TRAYS_TO_COLLECT = 3
local PENDING_MAX = 30 -- seconds a cross-room walk may wait for a free slot under the movers cap

function Jobs.bind(a: Api)
	api = a
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
local function span(e: any, range: { number }?): number
	local r = range or { 4, 6 }
	return r[1] + api.jitter(e, r[2] - r[1])
end
local function setState(e: any, name: string)
	if e.state ~= name then
		api.state(e, name)
	end
end

-- Faces `point` (world) and anchors the root: the employee works in place.
local function face(e: any, point: Vector3?)
	if not e.root.Parent then
		return
	end
	e.root.Anchored = false
	e.humanoid.AutoRotate = false
	if point then
		local delta = Vector3.new(point.X - e.root.Position.X, 0, point.Z - e.root.Position.Z)
		if delta.Magnitude > 0.2 then
			e.root.CFrame = CFrame.lookAt(e.root.Position, e.root.Position + delta)
		end
	end
	e.root.Anchored = true
end

local function stand(e: any)
	if e.humanoid.Parent and e.humanoid.Sit then
		e.humanoid.Sit = false
	end
	if e.root.Parent then
		e.root.Anchored = false
	end
	e.humanoid.AutoRotate = true
end

local function roomId(e: any, p: Vector3): string?
	local l = e.cf:PointToObjectSpace(p)
	local room = Plan.roomAt(e.tier, l)
	return if room then room.id else nil
end

-- Same room (or both within 8 studs on the same level): direct hops; otherwise the navigation.
local function sameRoom(e: any, a: Vector3, b: Vector3): boolean
	if math.abs(a.Y - b.Y) > 4 then
		return false
	end
	local ra, rb = roomId(e, a), roomId(e, b)
	if ra and ra == rb then
		return true
	end
	return flat(a, b) < 8
end

---------------------------------------------------------------------------------------------
-- Movement
---------------------------------------------------------------------------------------------
-- Walks to `target` (world, root height) through `via`, then calls done(ok). Same room: direct hops
-- (Humanoid:MoveTo, no path job) - only used for job points whose straight lines were checked on the
-- real geometry (tests/life/test_routes.py); other rooms, or `pathed` (café tables in the way): Nav.go
-- (state WALKING while the route runs). With the office's movers cap reached, a same-room hop is
-- skipped and the step runs where the employee stands.
function Jobs.moveTo(e: any, c: any, target: Vector3, via: { Vector3 }?, done: (boolean) -> (), pathed: boolean?)
	local time = api.now()
	local here = e.root.Position
	local hops: { Vector3 } = via or {}
	if pathed and flat(here, target) < HOP_REACH then
		done(true)
		return
	end
	if not pathed and sameRoom(e, here, target) then
		if flat(here, target) < HOP_REACH and #hops == 0 then
			done(true)
			return
		end
		if c.moving >= Config.moverCap(e.role) then
			done(false)
			return
		end
		local points: { Vector3 } = table.clone(hops)
		table.insert(points, target)
		stand(e)
		c.moving += 1
		e.humanoid.WalkSpeed = e.personality.walkSpeed
		e.hop = { points = points, i = 1, done = done, deadline = time + flat(here, points[1]) / e.personality.walkSpeed + 4 }
		e.humanoid:MoveTo(points[1])
		return
	end
	if c.moving >= Config.moverCap(e.role) then
		-- office movers cap reached: wait in place and start the walk when a slot frees up (Jobs.tick)
		e.pendingMove = { target = target, via = via, done = done, pathed = pathed, since = time }
		return
	end
	stand(e)
	local resume = e.state
	setState(e, "WALKING")
	c.moving += 1
	Nav.go(e, target, time, function(ok: boolean)
		if e.dead or not e.model.Parent then
			return
		end
		if e.state == "WALKING" then
			setState(e, if resume == "WALKING" then "WORKING" else resume)
		end
		done(ok)
	end)
end

-- Starts a walk that waited for the movers cap (gives up after PENDING_MAX seconds: done(false)).
local function pendingTick(e: any, c: any, time: number)
	local m = e.pendingMove
	if c.moving < Config.moverCap(e.role) then
		e.pendingMove = nil
		Jobs.moveTo(e, c, m.target, m.via, m.done, m.pathed)
	elseif time - m.since > PENDING_MAX then
		e.pendingMove = nil
		m.done(false)
	end
end

-- A conversation (TalkService via Staff.hold) pauses a hop in place; resume walks on (fresh deadline).
function Jobs.pause(e: any)
	if e.hop and e.humanoid.Parent and e.root.Parent then
		e.humanoid:MoveTo(e.root.Position)
	end
end
function Jobs.resume(e: any, time: number)
	local h = e.hop
	if h and e.humanoid.Parent and e.root.Parent then
		local p = h.points[h.i]
		h.deadline = time + flat(e.root.Position, p) / e.personality.walkSpeed + 4
		e.humanoid:MoveTo(p)
	end
	if e.pendingMove then
		e.pendingMove.since = time
	end
end

-- Hop progress (called every Staff tick while e.hop is set).
function Jobs.hopTick(e: any, time: number)
	local h = e.hop
	if not h then
		return
	end
	local p = h.points[h.i]
	if flat(e.root.Position, p) < HOP_REACH or time > h.deadline then
		if h.i < #h.points then
			h.i += 1
			h.deadline = time + flat(e.root.Position, h.points[h.i]) / e.personality.walkSpeed + 4
			e.humanoid:MoveTo(h.points[h.i])
		else
			e.hop = nil
			if e.humanoid.Parent then
				e.humanoid:MoveTo(e.root.Position)
			end
			h.done(true)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Operations jobs
---------------------------------------------------------------------------------------------
local function post(e: any): any
	return Workstations.scan(e.office).byId[e.home]
end

-- Job point `name` of the employee's post: stand (world), look-at, PropId, pose override.
function Jobs.point(e: any, name: string?): (Vector3?, Vector3?, string?, string?)
	local w = post(e)
	if not w then
		return nil, nil, nil, nil
	end
	if not name then
		local facing = w.model:GetAttribute("FacingPosition")
		return w.position, if typeof(facing) == "Vector3" then facing else nil, nil, nil
	end
	local m = w.model
	local p = m:GetAttribute("JobPoint_" .. name)
	if typeof(p) ~= "Vector3" then
		return nil, nil, nil, nil
	end
	local f = m:GetAttribute("JobFace_" .. name)
	local prop = m:GetAttribute("JobProp_" .. name)
	local pose = m:GetAttribute("JobPose_" .. name)
	return p, if typeof(f) == "Vector3" then f else nil, if typeof(prop) == "string" then prop else nil, if typeof(pose) == "string" then pose else nil
end

local function lunchService(c: any): boolean
	local h = api.hour()
	return (h >= Config.LUNCH_SERVICE[1] and h < Config.LUNCH_SERVICE[2]) or #(c.lunchQueue or {}) > 0
end

local function title(e: any): string
	local t = e.model:GetAttribute("Role")
	return if typeof(t) == "string" then t else "Campus Operations"
end

-- Keeps (or takes back) the employee's own post reservation without moving anybody.
local function holdPost(e: any): boolean
	local w = post(e)
	if not w then
		return false
	end
	if e.station == w then
		return true
	end
	if e.station then
		Workstations.release(e)
	end
	return Workstations.reserve(w, e)
end

-- Starts the work part of a step where the employee now stands.
local function work(e: any, step: any, faceAt: Vector3?, prop: string?, pose: string?, time: number)
	face(e, faceAt)
	local seconds = span(e, step.seconds)
	Workstations.setPose(e, pose or step.pose)
	if step.item ~= nil then
		Workstations.setItem(e, if step.item then step.item else nil)
	end
	if prop then
		Workstations.useProp(e.office, prop, seconds)
	end
	setState(e, "WORKING")
	e.next = time + seconds
end

local function sitAtPost(e: any, step: any, time: number)
	local w = post(e)
	if not w then
		return
	end
	if w.seat and e.station == w then
		e.humanoid.AutoRotate = false
		e.root.Anchored = false
		w.seat:Sit(e.humanoid)
		e.root.Anchored = true
	else
		local facing = w.model:GetAttribute("FacingPosition")
		face(e, if typeof(facing) == "Vector3" then facing else nil)
	end
	Workstations.setPose(e, step.pose)
	if step.item ~= nil then
		Workstations.setItem(e, if step.item then step.item else nil)
	end
	setState(e, "WORKING")
	e.next = time + span(e, step.seconds)
end

local function stationFor(e: any, kind: string): any
	local list = Workstations.scan(e.office).byKind[kind]
	if not list or #list == 0 then
		return nil
	end
	e.visitCursor = (e.visitCursor or (e.index % #list)) % #list + 1
	for k = 0, #list - 1 do
		local w = list[(e.visitCursor + k - 1) % #list + 1]
		if Workstations.available(w, e) then
			return w
		end
	end
	return nil
end

-- A desk screen goes out of order; IT walks over with a laptop and fixes it (PropFx screen overlay).
local function faultStation(e: any): any
	local here = e.root.Position
	local best, score = nil, math.huge
	for _, w in Workstations.scan(e.office).byKind.Computer or {} do
		if w.reserved or not Workstations.available(w, e) then
			continue
		end
		local d = flat(w.position, here) + math.abs(w.position.Y - here.Y) * 8 + ((w.fixedAt or -1e9) > api.now() - 600 and 1e6 or 0)
		if d < score then
			best, score = w, d
		end
	end
	return best
end
local function setFault(w: any, broken: boolean)
	local screen = w.model:FindFirstChild("DisplayContent")
	if not screen then
		return
	end
	if broken then
		screen:SetAttribute("Fx", "screen")
		Collection:AddTag(screen, "PropFx")
	end
	screen:SetAttribute("FxState", if broken then "broken" else "idle")
end

-- Ends the previous step (releases a visited station, a fault, a serving slot).
local function finishStep(e: any, c: any)
	local job = e.jobStep
	if not job then
		return
	end
	e.jobStep = nil
	if job.fault then
		setFault(job.fault, false)
		job.fault.fixedAt = api.now()
	end
	if job.visit and e.station == job.visit then
		Workstations.release(e)
	end
	if job.serve and c.server == e then
		c.server = nil
	end
	if job.breakJob then
		if c.opsBreak and c.opsBreak[job.breakJob] == e then
			c.opsBreak[job.breakJob] = nil
		end
		Workstations.setItem(e, nil)
		e.nextOpsBreak = api.now() + Config.OPS_BREAK[1] + api.jitter(e, Config.OPS_BREAK[2] - Config.OPS_BREAK[1])
	end
end

-- Next step of an operations employee (called by StaffService when the current one is over).
function Jobs.next(e: any, c: any)
	local time = api.now()
	-- the kitchen team keeps serving while the lunch service runs
	local current = e.jobStep
	if current and current.serve and lunchService(c) and c.server == e then
		e.next = time + 4
		return
	end
	finishStep(e, c)
	local job = Config.JOBS[title(e)]
	if not job then
		-- unknown job: stay at the post
		if holdPost(e) then
			sitAtPost(e, { pose = nil, seconds = { 20, 40 } }, time)
		end
		return
	end
	-- short break in place, covered: never two people with the same job title at once
	c.opsBreak = c.opsBreak or {}
	local jobTitle = title(e)
	e.nextOpsBreak = e.nextOpsBreak or (time + Config.OPS_BREAK[1] + api.jitter(e, Config.OPS_BREAK[2] - Config.OPS_BREAK[1]))
	if time >= e.nextOpsBreak and not c.opsBreak[jobTitle] and not (jobTitle == "Kitchen Team" and lunchService(c)) then
		c.opsBreak[jobTitle] = e
		e.jobStep = { breakJob = jobTitle }
		Workstations.setPose(e, "relax")
		Workstations.setItem(e, "cup")
		face(e, nil)
		setState(e, "SHORT_BREAK")
		e.next = time + span(e, Config.OPS_BREAK_SECONDS)
		return
	end
	local lunch = lunchService(c)
	e.cursor = e.cursor or 1
	for _ = 1, #job do
		local step = job[e.cursor]
		e.cursor = e.cursor % #job + 1
		if (step.when == "lunch" and not lunch) or (step.when == "open" and lunch) then
			continue
		end
		if step.every then
			e.stepCounts = e.stepCounts or {}
			local n = (e.stepCounts[step] or 0) + 1
			e.stepCounts[step] = n
			if n % step.every ~= 0 then
				continue
			end
		end
		if Jobs.run(e, c, step, time) then
			return
		end
	end
	-- nothing runnable right now: wait at the post
	if holdPost(e) then
		sitAtPost(e, { pose = nil, seconds = { 8, 14 } }, time)
	else
		e.next = time + 6
	end
end

-- Runs one step; false = skipped (missing point, nothing to do).
function Jobs.run(e: any, c: any, step: any, time: number): boolean
	if step.special then
		local handler = Jobs.handlers[step.special]
		return handler ~= nil and handler(e, c, step, time)
	end
	if step.trays then
		local trays = Workstations.scan(e.office).byKind.TrayReturn
		local rack = if trays then trays[1] else nil
		if not rack or (c.trays or 0) < TRAYS_TO_COLLECT then
			return false
		end
		e.jobStep = { step = step }
		e.next = math.huge
		Jobs.moveTo(e, c, rack.position, nil, function(ok: boolean)
			if ok then
				c.trays = 0
				local f = rack.model:GetAttribute("FacingPosition")
				work(e, step, if typeof(f) == "Vector3" then f else nil, nil, nil, api.now())
			else
				e.next = api.now() + 3
			end
		end)
		return true
	end
	if step.fault then
		local w = faultStation(e)
		if not w or not Workstations.reserve(w, e) then
			return false
		end
		setFault(w, true)
		e.jobStep = { fault = w, visit = w }
		e.next = math.huge
		if step.item ~= nil then
			Workstations.setItem(e, if step.item then step.item else nil)
		end
		Jobs.moveTo(e, c, w.position, nil, function(ok: boolean)
			if ok and e.station == w and Workstations.perform(e, api.now(), { stand = true }) then
				work(e, step, nil, nil, nil, api.now())
			else
				e.next = api.now() + 2
			end
		end)
		return true
	end
	if step.visit then
		local w = stationFor(e, step.visit)
		if not w or not Workstations.reserve(w, e) then
			return false
		end
		e.jobStep = { visit = w }
		e.next = math.huge
		if step.item ~= nil then
			Workstations.setItem(e, if step.item then step.item else nil)
		end
		Workstations.setPose(e, if step.item == "mopcart" then "push" else nil)
		Jobs.moveTo(e, c, w.position, nil, function(ok: boolean)
			if ok and e.station == w and Workstations.perform(e, api.now(), { stand = true }) then
				Workstations.setPose(e, step.pose)
				setState(e, "WORKING")
				e.next = api.now() + span(e, step.seconds)
			else
				e.next = api.now() + 2
			end
		end)
		return true
	end
	if step.route then
		local list = Workstations.scan(e.office)[if step.route == "Mop" then "mops" else step.route]
		if typeof(list) ~= "table" or #list == 0 then
			return false
		end
		holdPost(e)
		e.jobStep = { route = list, index = 1, step = step }
		e.next = math.huge
		if step.item ~= nil then
			Workstations.setItem(e, if step.item then step.item else nil)
		end
		Jobs.routeNext(e, c)
		return true
	end
	-- point step (or the post itself)
	local target, faceAt, prop, pose = Jobs.point(e, step.at)
	if step.at and not target then
		if step.optional then
			return false
		end
		target, faceAt = Jobs.point(e, nil) -- run in place at the post
	end
	if not target or not holdPost(e) then
		return false
	end
	local via: { Vector3 } = {}
	for _, name in step.via or {} do
		local p = Jobs.point(e, name)
		if p then
			table.insert(via, p)
		end
	end
	e.jobStep = { step = step, serve = step.serve }
	e.next = math.huge
	if step.item == "mopcart" then
		Workstations.setPose(e, "push")
	end
	Jobs.moveTo(e, c, target, via, function(ok: boolean)
		local now = api.now()
		if step.sit then
			sitAtPost(e, step, now)
		else
			work(e, step, faceAt, if step.prop then prop else nil, pose, now)
		end
		if step.serve and ok then
			c.server = e
			e.next = now + 4
		end
	end)
	return true
end

-- Mop route: navigate to the first point, then short hops point to point, mopping at each.
function Jobs.routeNext(e: any, c: any)
	local job = e.jobStep
	if not job or not job.route then
		return
	end
	local w = job.route[job.index]
	if not w then
		e.jobStep = nil
		e.next = api.now() + 1
		return
	end
	Workstations.setPose(e, "push")
	Jobs.moveTo(e, c, w.position, nil, function(_ok: boolean)
		local facing = w.model:GetAttribute("FacingPosition")
		face(e, if typeof(facing) == "Vector3" then facing else nil)
		Workstations.setPose(e, job.step.pose)
		setState(e, "WORKING")
		job.workUntil = api.now() + span(e, job.step.seconds)
	end)
end

---------------------------------------------------------------------------------------------
-- Lunch (employees)
---------------------------------------------------------------------------------------------
-- Plates handed out today: office attribute LunchesServed (TalkService quotes it), reset each campus day.
local function countPlate(c: any, _time: number, add: number)
	local day = campusDay()
	if c.lunchDay ~= day then
		c.lunchDay = day
		c.lunchesServed = 0
		if add == 0 then
			c.office:SetAttribute("LunchesServed", 0)
		end
	end
	if add > 0 then
		c.lunchesServed += add
		c.office:SetAttribute("LunchesServed", c.lunchesServed)
	end
end

local function queuePoint(c: any, slot: number): any
	local q = Workstations.scan(c.office).queue
	return q[math.min(slot, #q)]
end

local function leaveQueue(c: any, e: any)
	local q = c.lunchQueue
	if not q then
		return
	end
	local i = table.find(q, e)
	if i then
		table.remove(q, i)
	end
end

-- Cancels a lunch or job flow (LOD sleep, shift end, rebuild). Releases what the flow holds.
function Jobs.abort(e: any, c: any?)
	if e.hop then
		e.hop = nil
	end
	e.pendingMove = nil
	if e.lunch then
		if c then
			leaveQueue(c, e)
		end
		e.lunch = nil
		e.model:SetAttribute("TablePoint", nil)
		Workstations.setItem(e, nil)
		Workstations.setPose(e, nil)
	end
	if e.jobStep and c then
		finishStep(e, c)
	end
	e.jobStep = nil
	if c and c.server == e then
		c.server = nil
	end
end

local function lunchFail(e: any, c: any, time: number)
	Jobs.abort(e, c)
	Workstations.release(e)
	setState(e, "SELECT_TASK")
	e.lunchRetry = time + 20
	e.next = time + 5
end

-- The employee is done eating at the table: carry the tray to the return trolley (or leave it).
local function toReturn(e: any, c: any, time: number)
	local L = e.lunch
	Workstations.release(e)
	e.model:SetAttribute("TablePoint", nil)
	local racks = Workstations.scan(e.office).byKind.TrayReturn
	local rack = if racks then racks[1] else nil
	if not rack then
		Jobs.finishLunch(e, c, time, false)
		return
	end
	L.phase = "toReturn"
	Workstations.setItem(e, "tray")
	Workstations.setPose(e, "carry")
	Jobs.moveTo(e, c, rack.position, nil, function(ok: boolean)
		if not e.lunch then
			return
		end
		if not ok then
			Jobs.finishLunch(e, c, api.now(), false)
			return
		end
		local f = rack.model:GetAttribute("FacingPosition")
		face(e, if typeof(f) == "Vector3" then f else nil)
		setState(e, "LUNCH")
		Workstations.setPose(e, "reach")
		L.phase = "return"
		L.untilTime = api.now() + 2
	end, true)
end

function Jobs.finishLunch(e: any, c: any, time: number, returned: boolean)
	if returned then
		c.trays = (c.trays or 0) + 1
	end
	e.lunch = nil
	Workstations.setItem(e, nil)
	Workstations.setPose(e, nil)
	e.lastLunch = campusDay()
	if e.root.Parent then
		e.root.Anchored = false
	end
	setState(e, "SELECT_TASK")
	e.next = time + 1
end

local function toSeat(e: any, c: any)
	local L = e.lunch
	L.phase = "toSeat"
	Workstations.setPose(e, "carry")
	Jobs.moveTo(e, c, L.seat.position, nil, function(ok: boolean)
		local now = api.now()
		if not e.lunch then
			return
		end
		if not ok or e.station ~= L.seat or not Workstations.perform(e, now) then
			lunchFail(e, c, now)
			return
		end
		setState(e, "LUNCH")
		L.phase = "eat"
		L.untilTime = now + span(e, { 120, 230 })
		-- meal on the table in front of the seat (TableY = table top; default 3.2 above the floor)
		local seatPos = if L.seat.seat then L.seat.seat.Position else e.root.Position
		local facing = L.seat.model:GetAttribute("FacingPosition")
		local tableY = L.seat.model:GetAttribute("TableY")
		local toward = if typeof(facing) == "Vector3" then Vector3.new(facing.X - seatPos.X, 0, facing.Z - seatPos.Z) else Vector3.zero
		local point = seatPos + (if toward.Magnitude > 0.1 then toward.Unit * math.min(1.5, toward.Magnitude) else Vector3.zero)
		local y = if typeof(tableY) == "number" then tableY + 0.06 elseif typeof(facing) == "Vector3" then facing.Y - 2.8 + 3.21 else seatPos.Y + 1.35
		e.model:SetAttribute("TablePoint", Vector3.new(point.X, y, point.Z))
		Workstations.setItem(e, "meal")
		Workstations.setPose(e, "eat")
	end, true)
end

-- Starts lunch for employee `e` with a free Dining seat `seat` (already chosen). False = try later.
function Jobs.lunch(e: any, c: any, seat: any, def: any): boolean
	local time = api.now()
	c.lunchQueue = c.lunchQueue or {}
	local queue = Workstations.scan(e.office).queue
	if #queue > 0 and #c.lunchQueue >= #queue then
		return false -- the line is full
	end
	Nav.cancel(e)
	Workstations.release(e)
	if not Workstations.reserve(seat, e) then
		return false
	end
	e.task = def
	e.taskStarted = time
	e.model:SetAttribute("Task", def.id)
	e.next = math.huge
	e.lunch = { phase = "toQueue", seat = seat, slot = 0, waitSince = time }
	if #queue == 0 then
		-- no servery in this building: take a tray at the counter and go straight to the seat
		countPlate(c, time, 1)
		Workstations.setItem(e, "tray")
		toSeat(e, c)
		return true
	end
	table.insert(c.lunchQueue, e)
	local slot = #c.lunchQueue
	e.lunch.slot = slot
	local spot = queuePoint(c, slot)
	Jobs.moveTo(e, c, spot.position, nil, function(ok: boolean)
		local now = api.now()
		if not e.lunch then
			return
		end
		if not ok then
			lunchFail(e, c, now)
			return
		end
		local f = spot.model:GetAttribute("FacingPosition")
		face(e, if typeof(f) == "Vector3" then f else nil)
		setState(e, "LUNCH")
		e.lunch.phase = "queue"
		e.lunch.waitSince = now
	end, true)
	return true
end

-- Once per office tick: the line moves up by short hops and the front gets served.
function Jobs.officeTick(c: any)
	local time = api.now()
	if c.lunchDay ~= campusDay() then
		countPlate(c, time, 0)
	end
	local q = c.lunchQueue
	if not q or #q == 0 then
		return
	end
	for i, e in q do
		local L = e.lunch
		if L and L.phase == "queue" and not e.hop and not e.nav and not e.talkHold and L.slot ~= i then
			L.slot = i
			local spot = queuePoint(c, i)
			Jobs.moveTo(e, c, spot.position, nil, function(_ok: boolean)
				local f = spot.model:GetAttribute("FacingPosition")
				face(e, if typeof(f) == "Vector3" then f else nil)
			end)
		end
	end
	local front = q[1]
	local L = front and front.lunch
	if not L or L.phase ~= "queue" or L.slot ~= 1 or front.hop or front.nav or front.talkHold then
		return -- (a guest in conversation keeps the line waiting until the talk ends)
	end
	if not L.servedAt then
		local server = c.server
		if server and server.model.Parent and not server.hop and not server.nav and not server.talkHold and server.jobStep and server.jobStep.serve then
			L.servedAt = time + SERVE_SECONDS
			L.servedBy = server
			Workstations.setPose(server, "plate")
			Workstations.setItem(server, "plate")
			Workstations.useProp(c.office, "Servery", SERVE_SECONDS + 1)
		elseif time - L.waitSince > SELF_SERVE_AFTER then
			L.servedAt = time + 2 -- nobody behind the counter: self-service
			Workstations.setPose(front, "reach")
		end
		return
	end
	if time >= L.servedAt then
		local server = L.servedBy
		if server and server.model.Parent then
			Workstations.setItem(server, nil)
			Workstations.setPose(server, "wipe")
		end
		table.remove(q, 1)
		countPlate(c, time, 1)
		Workstations.setItem(front, "tray")
		toSeat(front, c)
	end
end

---------------------------------------------------------------------------------------------
-- Per-employee tick (hops, lunch phases, mop route, job timers)
---------------------------------------------------------------------------------------------
-- True while a flow of this module owns the employee (StaffService then skips its own task logic).
function Jobs.busy(e: any): boolean
	return e.hop ~= nil or e.pendingMove ~= nil or e.lunch ~= nil or (e.jobStep ~= nil and e.jobStep.route ~= nil)
end

function Jobs.tick(e: any, c: any, time: number)
	if e.hop then
		Jobs.hopTick(e, time)
		return
	end
	if e.pendingMove then
		pendingTick(e, c, time)
		return
	end
	local L = e.lunch
	if L then
		if L.phase == "eat" and time >= L.untilTime then
			toReturn(e, c, time)
		elseif L.phase == "return" and time >= L.untilTime then
			Jobs.finishLunch(e, c, time, true)
		end
		return
	end
	local job = e.jobStep
	if job and job.route and job.workUntil and time >= job.workUntil and not e.nav then
		job.workUntil = nil
		job.index += 1
		if job.index > #job.route then
			e.jobStep = nil
			e.next = time + 0.5
		else
			Jobs.routeNext(e, c)
		end
	end
end

-- Lunch seats: the café chairs carry the table-top height for the meal plate (TableY, world Y).
Jobs.SERVE_SECONDS = SERVE_SECONDS
return Jobs
