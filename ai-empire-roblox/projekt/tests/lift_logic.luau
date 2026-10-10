-- Pure scheduler/state-machine tests for LiftLogic. Run: tools/luau tests/lift_logic.luau
local Logic = require("../work/src/ServerScriptService/Server/Services/LiftLogic.module")

local LEVELS = { -1, 0, 1, 2, 3, 4, 5, 6, 7 }
local function heights(): { [number]: number }
	local h = {}
	for _, l in LEVELS do
		h[l] = (if l < 0 then -16 else l * 16) + 16
	end
	return h
end

local passed, failed = 0, 0
local function check(cond: boolean, name: string)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name)
	end
end

-- World: emulates the PrismaticConstraint servo (first-order follow, speed cap) and observers.
type World = { car: any, now: number, pos: number, stuck: boolean, input: any, log: { string }, maxV: number, maxA: number, lastCmd: number, lastV: number }
local DT = 0.05
local function world(start: number?, opts: any?): World
	local h = heights()
	local level = start or 0
	local car = Logic.new(LEVELS, h, level, 6, (opts and opts.position) or h[level])
	return { car = car, now = 0, pos = car.position, stuck = false, input = { occupied = false, riders = 0, playersWaiting = false }, log = {}, maxV = 0, maxA = 0, lastCmd = car.cmd, lastV = 0 }
end
local function step(w: World)
	w.now += DT
	local input = { position = w.pos, occupied = w.input.occupied, riders = w.input.riders, playersWaiting = w.input.playersWaiting }
	Logic.step(w.car, DT, w.now, input)
	for _, e in Logic.drain(w.car) do
		table.insert(w.log, string.format("%.2f %s %s", w.now, e, tostring(w.car.level)))
	end
	local v = (w.car.cmd - w.lastCmd) / DT
	w.maxV = math.max(w.maxV, math.abs(v))
	w.maxA = math.max(w.maxA, math.abs(v - w.lastV) / DT)
	w.lastCmd, w.lastV = w.car.cmd, v
	if not w.stuck then
		local err = w.car.cmd - w.pos
		local move = math.clamp(err * math.min(1, 30 * DT), -11 * DT, 11 * DT)
		w.pos += move
	end
end
local function run(w: World, seconds: number, until_: ((World) -> boolean)?): boolean
	local t = 0
	while t < seconds do
		step(w)
		t += DT
		if until_ and until_(w) then
			return true
		end
	end
	return false
end
local function stateIs(s: string, level: number?): (World) -> boolean
	return function(w: World)
		return w.car.state == s and (level == nil or w.car.level == level)
	end
end
local function count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end
local function events(w: World, name: string): { string }
	local out = {}
	for _, line in w.log do
		if string.find(line, " " .. name .. " ", 1, true) then
			table.insert(out, line)
		end
	end
	return out
end

---------------------------------------------------------------- 1 basic ride + profile limits
do
	local w = world(0)
	local ok, how = Logic.call(w.car, "hall", 3)
	check(ok and how == "queued", "hall call queued")
	check(run(w, 20, stateIs("DOORS_OPEN", 3)), "arrives and opens at 3")
	check(math.abs(w.pos - heights()[3]) <= Logic.ARRIVE_TOL + 1e-6, "servo at stop when doors open")
	check(w.maxV <= Logic.VMAX + 1e-6, "profile never exceeds vmax (" .. w.maxV .. ")")
	check(w.maxA <= Logic.ACCEL * 1.25, "profile acceleration bounded (" .. w.maxA .. ")")
	check(w.car.hall[3] == nil, "hall call cleared on opening")
	check(run(w, 10, stateIs("IDLE", 3)), "closes and idles at 3")
	check(w.car.door == 0, "doors fully closed when idle")
	local opened = events(w, "doorsOpening")
	check(#opened == 1, "doors opened exactly once")
end

---------------------------------------------------------------- 2 dedupe
do
	local w = world(0)
	Logic.call(w.car, "hall", 4)
	local ok, how = Logic.call(w.car, "hall", 4)
	check(ok and how == "dup", "repeated hall call is a no-op")
	Logic.call(w.car, "car", 4)
	local _, how2 = Logic.call(w.car, "car", 4)
	check(how2 == "dup", "repeated car call is a no-op")
	check(count(w.car.hall) == 1 and count(w.car.car) == 1, "sets keep one entry per level")
	local bad, err = Logic.call(w.car, "hall", 12)
	check(not bad and err == "BAD_LEVEL", "unknown level rejected")
	run(w, 25, stateIs("IDLE", 4))
	check(#events(w, "doorsOpening") == 1, "one stop at 4 for both calls")
end

---------------------------------------------------------------- 3 concurrent calls, collective SCAN
do
	local w = world(0)
	Logic.call(w.car, "car", 5)
	run(w, 0.5)
	Logic.call(w.car, "hall", 2) -- ahead, reachable: served on the way up
	Logic.call(w.car, "hall", -1) -- behind: served after reversing
	local order = {}
	for _ = 1, 2000 do
		step(w)
		if w.car.state == "DOORS_OPENING" and order[#order] ~= w.car.level then
			table.insert(order, w.car.level)
		end
		if #order == 3 then
			break
		end
	end
	check(table.concat(order, ",") == "2,5,-1", "SCAN order 2,5,-1 (got " .. table.concat(order, ",") .. ")")
end

---------------------------------------------------------------- 4 direction reversal + unreachable stop
do
	local w = world(0)
	Logic.call(w.car, "car", 4)
	run(w, 3.5) -- moving fast past level 1
	check(w.car.state == "MOVING" and w.car.direction == 1, "moving up")
	Logic.call(w.car, "hall", 1) -- behind now
	local order = {}
	for _ = 1, 2000 do
		step(w)
		if w.car.state == "DOORS_OPENING" and order[#order] ~= w.car.level then
			table.insert(order, w.car.level)
		end
		if #order == 2 then
			break
		end
	end
	check(table.concat(order, ",") == "4,1", "passes 1, serves 4 then reverses to 1 (got " .. table.concat(order, ",") .. ")")
end

---------------------------------------------------------------- 5 call at the current level
do
	local w = world(2)
	run(w, 0.5)
	local ok, how = Logic.call(w.car, "hall", 2)
	check(ok and how == "queued", "idle at level: call kept")
	check(run(w, 2, stateIs("DOORS_OPEN", 2)), "idle + closed + call here -> opens")
	w.car.dwell = 0.5
	local _, how2 = Logic.call(w.car, "car", 2)
	check(how2 == "open" and w.car.dwell >= Logic.DWELL and count(w.car.car) == 0, "doors open: call extends dwell, no queue entry")
	run(w, 10, stateIs("DOORS_CLOSING"))
	run(w, 0.2)
	local _, how3 = Logic.call(w.car, "hall", 2)
	check(how3 == "reopen" and w.car.state == "REOPENING", "doors closing: call reopens")
	check(run(w, 2, stateIs("DOORS_OPEN", 2)), "reopened fully")
	check(run(w, 10, stateIs("IDLE", 2)), "then closes again")
end

---------------------------------------------------------------- 6 overload hold
do
	local w = world(0)
	Logic.call(w.car, "hall", 0)
	Logic.call(w.car, "car", 3)
	run(w, 2, stateIs("DOORS_OPEN", 0))
	w.input.riders = 7
	run(w, 15)
	check(w.car.state == "DOORS_OPEN" and w.car.full, "overloaded: doors stay open, FULL")
	check(w.car.level == 0 and w.car.car[3], "overloaded: no departure")
	w.input.riders = 6
	check(run(w, 6, stateIs("MOVING")), "departs once the load is back to capacity")
end

---------------------------------------------------------------- 7 door obstruction while closing
do
	local w = world(1)
	Logic.call(w.car, "hall", 1)
	run(w, 10, stateIs("DOORS_CLOSING"))
	run(w, 0.3)
	w.input.occupied = true
	run(w, 0.1)
	check(w.car.state == "REOPENING", "occupied door zone reopens")
	run(w, 5)
	check(w.car.state == "DOORS_OPEN", "held open while the zone is occupied")
	w.input.occupied = false
	local t0 = w.now
	run(w, 5, stateIs("DOORS_CLOSING"))
	check(math.abs((w.now - t0) - Logic.HOLD_AFTER) < 0.11, "closes HOLD_AFTER seconds after the zone clears")
	check(run(w, 2, stateIs("IDLE", 1)), "closed afterwards")
end

---------------------------------------------------------------- 8 NPC fairness: slots reserved for waiting players
local function admitted(w: World): number
	local n = 0
	for _, t in w.car.tickets do
		if t.state == "board" then
			n += 1
		end
	end
	return n
end
do
	local w = world(0)
	local tickets = {}
	for i = 1, 4 do
		local t = Logic.addTicket(w.car, 0, 3, w.now)
		assert(t)
		t.near = true
		tickets[i] = t
	end
	w.input.riders = 3
	w.input.playersWaiting = true
	run(w, 2, stateIs("DOORS_OPEN", 0))
	run(w, 0.1)
	check(admitted(w) == 1, "player waiting: only 1 of 4 NPCs boards with 3 riders (got " .. admitted(w) .. ")")
	check(tickets[1].state == "board" and tickets[2].state == "waiting", "FIFO admission")
	check(tickets[1].waitSlot == 1 and tickets[4].waitSlot == 4, "distinct wait slots")
end
do
	local w = world(0)
	for _ = 1, 4 do
		local t = Logic.addTicket(w.car, 0, 3, w.now)
		assert(t)
		t.near = true
	end
	w.input.riders = 3
	run(w, 2, stateIs("DOORS_OPEN", 0))
	run(w, 0.1)
	check(admitted(w) == 3, "no player waiting: 3 NPCs fill the free slots (got " .. admitted(w) .. ")")
end

---------------------------------------------------------------- 9 NPC full journey + direction filter
do
	local w = world(0)
	local up = Logic.addTicket(w.car, 0, 3, w.now)
	local down = Logic.addTicket(w.car, 0, -1, w.now)
	assert(up and down)
	up.near, down.near = true, true
	check(run(w, 3, stateIs("DOORS_OPEN", 0)), "NPC demand opens the idle cabin")
	run(w, 0.1)
	check(up.state == "board" and down.state == "waiting", "first boarder sets direction, opposite NPC waits")
	check(up.slot == 1, "cabin slot assigned")
	run(w, 1)
	up.inside = true
	up.zone = true -- just past the cabin doors
	run(w, 0.5)
	check(up.state == "board" and w.car.state == "DOORS_OPEN", "still boarding while in the doorway")
	up.zone = false
	run(w, 0.1)
	check(up.state == "riding", "inside and clear of the doorway -> riding")
	check(run(w, 12, stateIs("MOVING")), "departs with the rider")
	check(w.car.target == 3, "rider destination is the target")
	check(down.skip == w.car.visit - 1, "opposite NPC skipped for that visit")
	check(run(w, 20, stateIs("DOORS_OPEN", 3)), "arrives at 3")
	run(w, 0.1)
	check(up.state == "exit", "riding -> exit at destination")
	run(w, 6)
	check(w.car.state == "DOORS_OPEN", "exiting NPC still inside holds doors")
	up.inside = false
	up.zone = false
	run(w, 0.1)
	check(up.state == "done", "exit -> done once outside")
	check(table.find(w.car.tickets, up) == nil, "done ticket released")
	-- the waiting down-ticket brings the cabin back
	check(run(w, 30, stateIs("DOORS_OPEN", 0)), "cabin returns for the waiting NPC")
	run(w, 0.1)
	check(down.state == "board", "second NPC boards on the next visit")
end

---------------------------------------------------------------- 10 ticket timeout, board misses
do
	local w = world(0)
	local t = Logic.addTicket(w.car, 3, 0, w.now)
	assert(t)
	t.near = false -- still walking to the lift: no call yet
	local far = Logic.addTicket(w.car, 5, 1, w.now)
	assert(far)
	run(w, 10)
	check(w.car.state == "IDLE" and w.car.level == 0 and #events(w, "depart") == 0, "no shuttling for NPCs not yet at the lift")
	far.near = true
	check(run(w, 15, stateIs("DOORS_OPEN", 5)), "NPC in the lobby calls the cabin")
	run(w, Logic.WAIT_TIMEOUT + 1 - w.now)
	check(t.state == "failed" and t.reason == "timeout", "waiting > 45 s -> failed")
	check(table.find(w.car.tickets, t) == nil, "failed ticket released")
end
do
	local w = world(0)
	local t = Logic.addTicket(w.car, 0, 2, w.now)
	assert(t)
	t.near = true -- near but never gets inside
	run(w, 40, function(x)
		return t.state == "failed"
	end)
	check(t.state == "failed" and t.reason == "could not board", "two missed boardings -> failed")
	check(w.now < Logic.WAIT_TIMEOUT, "fails before the wait timeout")
end

---------------------------------------------------------------- 11 cancel mid-ride (detach)
do
	local w = world(0)
	local t = Logic.addTicket(w.car, 0, 5, w.now)
	assert(t)
	t.near = true
	run(w, 3, stateIs("DOORS_OPEN", 0))
	run(w, 0.5)
	t.inside = true
	run(w, 12, stateIs("MOVING"))
	run(w, 1)
	Logic.cancel(w.car, t, "detached")
	check(t.state == "failed" and t.reason == "detached", "cancel marks failed")
	check(#w.car.tickets == 0, "cancelled ticket removed")
	check(run(w, 20, stateIs("IDLE")), "cabin stops at its committed target and idles")
	check(#events(w, "doorsOpening") == 1, "no doors opened without demand")
end

---------------------------------------------------------------- 12 doors open only when level with the stop
do
	local w = world(0, { position = heights()[0] - 2 })
	w.stuck = true
	Logic.call(w.car, "hall", 0)
	run(w, 3)
	check(w.car.state == "IDLE" and w.car.door == 0, "misaligned cabin keeps doors shut")
	w.stuck = false
	check(run(w, 3, stateIs("DOORS_OPEN", 0)), "opens once settled at the stop")
end

---------------------------------------------------------------- 13 stall -> back to a stop -> out of service -> recovery
do
	local w = world(0)
	Logic.call(w.car, "car", 4)
	run(w, 2)
	w.stuck = true
	run(w, Logic.STALL_TIME + 1)
	check(#events(w, "stall") == 1, "stall detected")
	check(w.car.target == 0 and w.car.car[0] == true, "returns to the stop behind with a call to open there")
	run(w, Logic.STALL_TIME + 1)
	check(w.car.state == "OUT_OF_SERVICE", "second stall -> out of service")
	local ok, err = Logic.call(w.car, "hall", 2)
	check(not ok and err == "OUT_OF_SERVICE", "calls refused while out of service")
	check(Logic.addTicket(w.car, 0, 2, w.now) == nil, "no NPC tickets while out of service")
	w.stuck = false
	run(w, Logic.RECOVER_TIME + 0.2)
	check(w.car.state ~= "OUT_OF_SERVICE", "recovers after RECOVER_TIME")
	check(run(w, 5, stateIs("IDLE")) or w.car.state == "IDLE", "idles at nearest stop")
end

---------------------------------------------------------------- 14 arrow / door phase helpers
do
	local w = world(0)
	Logic.call(w.car, "hall", 0)
	Logic.call(w.car, "car", 2)
	run(w, 2, stateIs("DOORS_OPEN", 0))
	check(Logic.arrow(w.car) == 1 and Logic.doorPhase(w.car) == "open", "open at G heading up")
	run(w, 10, stateIs("MOVING"))
	check(Logic.arrow(w.car) == 1, "arrow up while moving")
end

print(string.format("lift_logic: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("lift_logic tests failed")
end
