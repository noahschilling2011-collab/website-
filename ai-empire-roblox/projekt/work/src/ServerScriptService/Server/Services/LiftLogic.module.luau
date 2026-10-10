--!strict
-- Pure lift controller (no Roblox instances): collective SCAN scheduling, the door state machine,
-- the trapezoidal motion profile and NPC tickets. LiftService feeds it observations every tick
-- (servo position, door zone, riders, waiting players, per-ticket NPC positions) and applies the
-- outputs (servo TargetPosition = car.cmd, door alpha = car.door, events). Positions are servo
-- studs along the shaft (car.heights[level]); times are seconds of the caller's clock.
--
-- States: IDLE -> MOVING -> DOORS_OPENING -> DOORS_OPEN -> DOORS_CLOSING -> (REOPENING) -> next
-- stop or IDLE; OUT_OF_SERVICE after a repeated stall (recovers on its own after RECOVER_TIME).
-- Doors only open when the cabin is settled at the stop; calls never move a landing door alone.
local Logic = {}

Logic.ACCEL = 6 -- studs/s^2
Logic.VMAX = 10 -- studs/s
Logic.DOOR_TIME = 0.8 -- seconds for a full open or close
Logic.DWELL = 3.5 -- minimum time the doors stay fully open
Logic.HOLD_AFTER = 1.5 -- remaining dwell once a blocked doorway clears
Logic.ARRIVE_TOL = 0.1 -- studs between servo position and stop
Logic.SETTLE = 0.2 -- seconds the cabin must stay within ARRIVE_TOL
Logic.LAG = 2.5 -- the profile waits when the servo falls this far behind
Logic.STALL_LAG = 1.5
Logic.STALL_TIME = 5
Logic.RECOVER_TIME = 10
Logic.WAIT_TIMEOUT = 45 -- NPC waiting longer than this fails (falls back to the stairs)
Logic.BOARD_TIMEOUT = 8 -- an admitted NPC must be inside within this time
Logic.EXIT_TIMEOUT = 10
Logic.RIDE_GRACE = 1.5 -- a rider seen outside the cabin for this long has left
Logic.RESERVED = 2 -- slots kept free for players waiting in the lift lobby

export type Ticket = {
	state: string, -- waiting | board | riding | exit | done | failed
	fromLevel: number,
	toLevel: number,
	target: Vector3?, -- written by LiftService
	created: number,
	since: number, -- time of the last state change
	slot: number?, -- cabin slot while boarding/riding/exiting
	waitSlot: number, -- queue position at the wait point
	skip: number, -- car.visit during which this waiting ticket does not count as demand here
	near: boolean, -- observations written by LiftService before each step
	inside: boolean,
	zone: boolean,
	alive: boolean,
	away: number,
	misses: number, -- admitted but did not make it into the cabin
	reason: string?,
}

export type Car = {
	levels: { number },
	heights: { [number]: number },
	capacity: number,
	state: string,
	level: number, -- served/parked level (nearest level while moving)
	target: number?,
	direction: number,
	hall: { [number]: boolean },
	car: { [number]: boolean },
	tickets: { Ticket },
	door: number, -- 0 closed .. 1 open
	dwell: number,
	cmd: number, -- commanded servo position (TargetPosition)
	vel: number, -- profile velocity
	position: number, -- last observed servo position
	settle: number,
	visit: number, -- increments on every departure
	full: boolean,
	stall: number,
	stalls: number,
	recover: number,
	reason: string?,
	events: { string },
	now: number,
}

export type Input = { position: number, occupied: boolean, riders: number, playersWaiting: boolean }

local function sign(x: number): number
	return if x > 0 then 1 elseif x < 0 then -1 else 0
end

local function emit(car: Car, event: string)
	table.insert(car.events, event)
end

function Logic.new(levels: { number }, heights: { [number]: number }, startLevel: number, capacity: number, position: number?): Car
	local sorted = table.clone(levels)
	table.sort(sorted, function(a, b)
		return heights[a] < heights[b]
	end)
	local here = position or heights[startLevel]
	return {
		levels = sorted, heights = heights, capacity = capacity, state = "IDLE", level = startLevel, target = nil,
		direction = 0, hall = {}, car = {}, tickets = {}, door = 0, dwell = 0, cmd = here, vel = 0, position = here,
		settle = 0, visit = 0, full = false, stall = 0, stalls = 0, recover = 0, reason = nil, events = {}, now = 0,
	}
end

function Logic.nearestLevel(car: Car, position: number): number
	local best, bestD = car.level, math.huge
	for _, level in car.levels do
		local d = math.abs(car.heights[level] - position)
		if d < bestD then
			best, bestD = level, d
		end
	end
	return best
end

function Logic.drain(car: Car): { string }
	local list = car.events
	car.events = {}
	return list
end

local function setState(car: Car, t: Ticket, state: string, reason: string?)
	t.state = state
	t.since = car.now
	if state == "waiting" or state == "done" or state == "failed" then
		t.slot = nil
	end
	if reason then
		t.reason = reason
	end
end

---------------------------------------------------------------------------- demand / SCAN

-- A waiting NPC "presses the button" only once it stands in the lift lobby (t.near): the cabin
-- never shuttles between floors for employees that are still walking to the lift.
function Logic.demand(car: Car, level: number): boolean
	if car.hall[level] or car.car[level] then
		return true
	end
	for _, t in car.tickets do
		if t.state == "waiting" and t.fromLevel == level and t.skip ~= car.visit and t.near then
			return true
		end
		if (t.state == "board" or t.state == "riding") and t.toLevel == level then
			return true
		end
	end
	return false
end

local function nearestPending(car: Car, from: number, dir: number, minDist: number): number?
	local best, bestD = nil, math.huge
	for _, level in car.levels do
		local d = (car.heights[level] - from) * dir
		if d > minDist and d < bestD and Logic.demand(car, level) then
			best, bestD = level, d
		end
	end
	return best
end

-- Next stop from a standing position: keep the travel direction while calls lie ahead, else reverse.
local function choose(car: Car, from: number): (number?, number)
	local dir = car.direction
	if dir ~= 0 then
		local ahead = nearestPending(car, from, dir, 0.05)
		if ahead then
			return ahead, dir
		end
		local back = nearestPending(car, from, -dir, 0.05)
		if back then
			return back, -dir
		end
		return nil, 0
	end
	local up, down = nearestPending(car, from, 1, 0.05), nearestPending(car, from, -1, 0.05)
	if up and down then
		if car.heights[up] - from <= from - car.heights[down] then
			return up, 1
		end
		return down, -1
	end
	if up then
		return up, 1
	elseif down then
		return down, -1
	end
	return nil, 0
end

-- Direction shown on the indicators: travel direction, or the direction of the next departure.
function Logic.arrow(car: Car): number
	if car.state == "MOVING" then
		return car.direction
	elseif car.state == "IDLE" or car.state == "OUT_OF_SERVICE" then
		return 0
	end
	local _, dir = choose(car, car.heights[car.level])
	return dir
end

function Logic.doorPhase(car: Car): string
	local s = car.state
	if s == "DOORS_OPENING" or s == "REOPENING" then
		return "opening"
	elseif s == "DOORS_OPEN" then
		return "open"
	elseif s == "DOORS_CLOSING" then
		return "closing"
	end
	return "closed"
end

---------------------------------------------------------------------------- calls

-- kind: "hall" (landing button) or "car" (cabin panel). Returns ok plus what happened:
-- queued | dup | open | opening | reopen, or an error code (BAD_LEVEL, OUT_OF_SERVICE).
function Logic.call(car: Car, kind: string, level: number): (boolean, string)
	if car.heights[level] == nil then
		return false, "BAD_LEVEL"
	end
	if car.state == "OUT_OF_SERVICE" then
		return false, "OUT_OF_SERVICE"
	end
	if car.state ~= "MOVING" and car.level == level then
		local s = car.state
		if s == "DOORS_OPEN" then
			car.dwell = math.max(car.dwell, Logic.DWELL)
			return true, "open"
		elseif s == "DOORS_OPENING" or s == "REOPENING" then
			return true, "opening"
		elseif s == "DOORS_CLOSING" then
			car.state = "REOPENING"
			emit(car, "reopen")
			return true, "reopen"
		end
		-- IDLE: keep the call; the next step opens once the cabin is level with the stop
	end
	local set = if kind == "car" then car.car else car.hall
	if set[level] then
		return true, "dup"
	end
	set[level] = true
	return true, "queued"
end

---------------------------------------------------------------------------- NPC tickets

function Logic.addTicket(car: Car, fromLevel: number, toLevel: number, now: number): Ticket?
	if car.heights[fromLevel] == nil or car.heights[toLevel] == nil or fromLevel == toLevel or car.state == "OUT_OF_SERVICE" then
		return nil
	end
	local used: { [number]: boolean } = {}
	for _, t in car.tickets do
		if t.fromLevel == fromLevel and (t.state == "waiting" or t.state == "board") then
			used[t.waitSlot] = true
		end
	end
	local slot = 1
	while used[slot] do
		slot += 1
	end
	local t: Ticket = {
		state = "waiting", fromLevel = fromLevel, toLevel = toLevel, target = nil, created = now, since = now,
		slot = nil, waitSlot = slot, skip = -1, near = false, inside = false, zone = false, alive = true, away = 0, misses = 0, reason = nil,
	}
	table.insert(car.tickets, t)
	return t
end

function Logic.cancel(car: Car, t: Ticket, reason: string?)
	if t.state ~= "done" and t.state ~= "failed" then
		setState(car, t, "failed", reason or "cancelled")
	end
	local index = table.find(car.tickets, t)
	if index then
		table.remove(car.tickets, index)
	end
end

local function freeSlot(car: Car): number
	local used: { [number]: boolean } = {}
	for _, t in car.tickets do
		if t.slot then
			used[t.slot] = true
		end
	end
	for slot = 1, car.capacity do
		if not used[slot] then
			return slot
		end
	end
	return 1
end

-- Direction the cabin is committed to by its riders (0 = free, the first boarder decides).
local function boardDirection(car: Car): number
	local level = car.level
	local up, down = false, false
	local function note(l: number)
		if car.heights[l] > car.heights[level] then
			up = true
		elseif car.heights[l] < car.heights[level] then
			down = true
		end
	end
	for l in car.car do
		note(l)
	end
	for _, t in car.tickets do
		if t.state == "board" or t.state == "riding" then
			note(t.toLevel)
		end
	end
	if car.direction > 0 and up then
		return 1
	elseif car.direction < 0 and down then
		return -1
	elseif up then
		return 1
	elseif down then
		return -1
	end
	return 0
end

local function freeSlots(car: Car, input: Input): number
	local boarding = 0
	for _, t in car.tickets do
		if t.state == "board" and not t.inside then
			boarding += 1
		end
	end
	local reserve = if input.playersWaiting then Logic.RESERVED else 0
	return car.capacity - input.riders - boarding - reserve
end

local function admissible(car: Car, t: Ticket, dir: number, free: number): boolean
	return t.state == "waiting" and t.fromLevel == car.level and t.near and free > 0
		and (dir == 0 or sign(car.heights[t.toLevel] - car.heights[car.level]) == dir)
end

-- Doors fully open: riders for this level step out, waiting NPCs board in FIFO order while slots
-- remain (players waiting in the lobby keep RESERVED slots free).
local function admit(car: Car, input: Input)
	for _, t in car.tickets do
		if t.state == "riding" and t.toLevel == car.level then
			setState(car, t, "exit")
		end
	end
	local dir = boardDirection(car)
	local free = freeSlots(car, input)
	for _, t in car.tickets do
		if free <= 0 then
			break
		end
		if admissible(car, t, dir, free) then
			setState(car, t, "board")
			t.slot = freeSlot(car)
			free -= 1
			if dir == 0 then
				dir = sign(car.heights[t.toLevel] - car.heights[car.level])
			end
		end
	end
end

local function holding(car: Car): boolean
	for _, t in car.tickets do
		if t.state == "board" and t.fromLevel == car.level then
			return true
		elseif t.state == "exit" and (t.inside or t.zone) then
			return true
		end
	end
	return false
end

local function updateTickets(car: Car, dt: number)
	local now = car.now
	for i = #car.tickets, 1, -1 do
		local t = car.tickets[i]
		if not t.alive then
			setState(car, t, "failed", "gone")
		elseif t.state == "waiting" then
			if now - t.created > Logic.WAIT_TIMEOUT then
				setState(car, t, "failed", "timeout")
			end
		elseif t.state == "board" then
			local present = car.level == t.fromLevel
				and (car.state == "DOORS_OPEN" or car.state == "DOORS_CLOSING" or car.state == "REOPENING")
			if t.inside and not t.zone then -- riders stand still: only once clear of the doorway
				setState(car, t, "riding")
				t.away = 0
			elseif not present or now - t.since > Logic.BOARD_TIMEOUT then
				t.misses += 1
				if t.misses >= 2 then
					setState(car, t, "failed", "could not board")
				else
					setState(car, t, "waiting")
					t.skip = car.visit -- do not hold this visit any longer
				end
			end
		elseif t.state == "riding" then
			if t.inside then
				t.away = 0
			else
				t.away += dt
				if t.away > Logic.RIDE_GRACE then
					setState(car, t, "failed", "left cabin")
				end
			end
		elseif t.state == "exit" then
			if (not t.inside and not t.zone) or now - t.since > Logic.EXIT_TIMEOUT then
				setState(car, t, "done")
			end
		end
		if t.state == "done" or t.state == "failed" then
			table.remove(car.tickets, i)
		end
	end
end

---------------------------------------------------------------------------- motion

-- Trapezoid: accelerate to VMAX, cruise, brake so the cabin can always stop at `goal`.
local function profile(car: Car, dt: number, goal: number)
	local d = goal - car.cmd
	local dist = math.abs(d)
	if dist < 0.005 then
		car.cmd = goal
		car.vel = 0
		return
	end
	if math.abs(car.cmd - car.position) > Logic.LAG then
		car.vel = 0 -- the servo is behind; wait for it instead of running away
		return
	end
	local dir = sign(d)
	local speed = car.vel * dir
	if speed < 0 then
		speed = math.min(speed + Logic.ACCEL * dt, 0)
		car.cmd += dir * speed * dt
	else
		local previous = speed
		speed = math.min(speed + Logic.ACCEL * dt, Logic.VMAX)
		-- fastest speed that can still stop at goal with discrete steps: v^2/2a + v*dt/2 = dist
		local a = Logic.ACCEL
		local brake = a * (math.sqrt(dt * dt / 4 + 2 * dist / a) - dt / 2)
		if speed > brake then
			speed = math.max(brake, previous - Logic.ACCEL * dt)
		end
		local step = speed * dt
		if step >= dist then
			car.cmd = goal
			car.vel = 0
			return
		end
		car.cmd += dir * step
	end
	car.vel = dir * speed
end

local function settled(car: Car, dt: number, goal: number): boolean
	if car.cmd == goal and math.abs(car.position - goal) <= Logic.ARRIVE_TOL then
		car.settle += dt
	else
		car.settle = 0
	end
	return car.settle >= Logic.SETTLE - 1e-6
end

---------------------------------------------------------------------------- states

local function startOpening(car: Car)
	car.hall[car.level] = nil
	car.car[car.level] = nil
	car.state = "DOORS_OPENING"
	emit(car, "doorsOpening")
end

local function depart(car: Car, target: number, dir: number)
	car.state = "MOVING"
	car.target = target
	car.direction = dir
	car.visit += 1
	car.settle = 0
	car.stall = 0
	emit(car, "depart")
end

function Logic.outOfService(car: Car, reason: string)
	car.state = "OUT_OF_SERVICE"
	car.reason = reason
	car.recover = Logic.RECOVER_TIME
	car.target = nil
	car.vel = 0
	car.cmd = car.position
	table.clear(car.hall)
	table.clear(car.car)
	for i = #car.tickets, 1, -1 do
		setState(car, car.tickets[i], "failed", reason)
		table.remove(car.tickets, i)
	end
	emit(car, "outOfService")
end

local function idle(car: Car, dt: number, input: Input)
	local h = car.heights[car.level]
	profile(car, dt, h)
	local aligned = settled(car, dt, h)
	-- an NPC skipped earlier (full cabin, other direction) counts again once it could board
	local dir, free = boardDirection(car), freeSlots(car, input)
	for _, t in car.tickets do
		if t.skip == car.visit and admissible(car, t, dir, free) then
			t.skip = -1
		end
	end
	if Logic.demand(car, car.level) then
		if aligned then
			startOpening(car)
		end
		return
	end
	local target, nextDir = choose(car, h)
	if target then
		depart(car, target, nextDir)
	end
end

local function moving(car: Car, dt: number)
	local target = car.target :: number
	local dir = car.direction
	-- collective control: also serve a call ahead that we can still brake for
	local brake = car.vel * car.vel / (2 * Logic.ACCEL) + 0.3
	local nearer = nearestPending(car, car.cmd, dir, brake)
	if nearer and (car.heights[nearer] - car.cmd) * dir < (car.heights[target] - car.cmd) * dir then
		target = nearer
		car.target = nearer
	end
	local goal = car.heights[target]
	profile(car, dt, goal)
	car.level = Logic.nearestLevel(car, car.position)
	if math.abs(car.cmd - car.position) > Logic.STALL_LAG then
		car.stall += dt
	else
		car.stall = 0
	end
	if car.stall > Logic.STALL_TIME then
		car.stall = 0
		car.stalls += 1
		emit(car, "stall")
		if car.stalls >= 2 then
			Logic.outOfService(car, "stalled")
			return
		end
		-- head back towards the stop behind the cabin, starting from where it really is
		car.cmd = car.position
		car.vel = 0
		local best, bestD = Logic.nearestLevel(car, car.position), math.huge
		for _, level in car.levels do
			local d = (car.heights[level] - car.position) * -dir
			if d >= -0.05 and d < bestD then
				best, bestD = level, d
			end
		end
		car.target = best
		car.car[best] = true -- open there so the riders can get out
		car.direction = sign(car.heights[best] - car.position)
		return
	end
	if settled(car, dt, goal) then
		car.level = target
		car.target = nil
		car.vel = 0
		car.stalls = 0
		emit(car, "arrive")
		if Logic.demand(car, target) then
			startOpening(car)
		else
			car.state = "IDLE"
		end
	end
end

local function opening(car: Car, dt: number)
	car.door = math.min(1, car.door + dt / Logic.DOOR_TIME)
	if car.door >= 1 then
		car.state = "DOORS_OPEN"
		car.dwell = Logic.DWELL
		emit(car, "doorsOpen")
	end
end

local function open(car: Car, dt: number, input: Input)
	car.full = input.riders > car.capacity
	admit(car, input)
	car.dwell -= dt
	if input.occupied or car.full or holding(car) then
		car.dwell = math.max(car.dwell, Logic.HOLD_AFTER) -- never close on anyone
	end
	if car.dwell <= 0 then
		for _, t in car.tickets do
			if t.state == "waiting" and t.fromLevel == car.level and t.near then
				t.skip = car.visit -- could not board this time: wait for the next visit
			end
		end
		car.state = "DOORS_CLOSING"
		emit(car, "doorsClosing")
	end
end

local function closing(car: Car, dt: number, input: Input)
	car.full = input.riders > car.capacity
	if input.occupied or car.full or Logic.demand(car, car.level) then
		car.state = "REOPENING"
		emit(car, "reopen")
		return
	end
	car.door = math.max(0, car.door - dt / Logic.DOOR_TIME)
	if car.door <= 0 then
		emit(car, "closed")
		local target, dir = choose(car, car.heights[car.level])
		if target then
			depart(car, target, dir)
		else
			car.state = "IDLE"
		end
	end
end

function Logic.step(car: Car, dt: number, now: number, input: Input)
	car.now = now
	car.position = input.position
	updateTickets(car, dt)
	local s = car.state
	if s == "OUT_OF_SERVICE" then
		car.full = false
		car.recover -= dt
		if car.recover <= 0 then
			car.level = Logic.nearestLevel(car, car.position)
			car.cmd = car.position
			car.stalls = 0
			car.reason = nil
			car.state = "IDLE"
			emit(car, "recovered")
		end
	elseif s == "IDLE" then
		car.full = false
		idle(car, dt, input)
	elseif s == "MOVING" then
		moving(car, dt)
	elseif s == "DOORS_OPENING" or s == "REOPENING" then
		car.full = input.riders > car.capacity
		opening(car, dt)
	elseif s == "DOORS_OPEN" then
		open(car, dt, input)
	elseif s == "DOORS_CLOSING" then
		closing(car, dt, input)
	end
end

return Logic
