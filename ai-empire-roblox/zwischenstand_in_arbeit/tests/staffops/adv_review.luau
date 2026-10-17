--!nocheck
-- Reviewer (review_staffops) adversarial scenarios against the staffops package, using the package's own
-- world harness (tests/staffops/world.luau = REAL HQ + real staff services, mock clock).
-- Copy of the round-1 reviewer suites (agents/review_staffops/sb_so/tests/review_adv/test_adv.luau), paths adapted.
-- Run: tools/luau tests/staffops/adv_review.luau -a <suite>  (after python3 tests/staffops/mkharness.py)
local args = { ... }
local SUITE = args[1] or "midnight"
local realClock = os.clock
local M = require("../../harness/mock")
local GENDIR = args[2] or "./gen"
M.loadTree(require(GENDIR .. "/manifest"), require(GENDIR .. "/sources"))
M.quiet = true
local G = M.G
local makeWorld = require("./world")
local pass, failc = 0, 0
local failures = {}
local notes = {}
local function check(name, ok, detail)
	if ok then pass += 1 return end
	failc += 1
	if not failures[name] then
		failures[name] = 0
		print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else ""))
	end
	failures[name] += 1
end
local function note(s) table.insert(notes, s); print("NOTE  " .. s) end
local suites = {}

local function errorsNow() return M.stats.errors or 0 end

------------------------------------------------------------------------------------------- midnight
-- stage 3 with a research night crew; clock wraps over midnight; economy calendar advances at 08:00;
-- 06:00-08:00 workday switch must not flip who is away at 08:00; a big server-clock jump mid-flow.
suites.midnight = function()
	local W = makeWorld(M, { tier = 2, hour = 20.5, employees = { researcher = 30, engineer = 14, curator = 10, marketer = 10 }, prepare = function(d)
		d.empire.nightShift = { research = true }
		d.empire.calendar.day = 5
	end })
	local e = W.data.empire
	local Ops, Rota = W.Ops, W.Rota
	local err0 = errorsNow()
	-- emulate the economy's calendar on every tick (EmpireService: Ops.advanceCalendar)
	local function econ() Ops.advanceCalendar(e, W.serverNow()) end
	econ()
	local a, b = Rota.nightRange(e, "researcher")
	local crew = {}
	for i = a, b do crew[i] = true end
	W.tick(200, econ)
	local function crewOn()
		local on, total = 0, 0
		local pres = Rota.presence(e, Rota.workday(e, W.hour()), "researcher")
		for i in crew do
			if pres[i] == "present" then
				total += 1
				local m = W.rigOf("researcher", i)
				local act = m:GetAttribute("Activity")
				if act ~= "OFF_DUTY" and act ~= "LEAVING" then on += 1 end
			end
		end
		return on, total
	end
	-- 21:50 -> crew still home
	W.setHour(21.8); W.tick(10, econ)
	local on, total = crewOn()
	check("night crew home at 21:50", on == 0, on .. "/" .. total)
	-- through midnight: sample at 23:30, 00:20, 03:00, 05:40
	local samples = {}
	for _, h in { 23.5, 0.33, 3.0, 5.66 } do
		local target = W.secondsOf(h); local guard = 0
		while math.abs((W.serverNow() % 1200) - target) > 0.3 and guard < 5000 do W.tick(1, econ); guard += 1 end
		local o, t = crewOn()
		samples[h] = o .. "/" .. t
		check("night crew on duty at " .. h, o == t and t > 0, o .. "/" .. t)
	end
	-- 06:00..08:00: the crew leaves; consistency of "away" between 07:00 (workday = day+1) and 08:30 (saved day+1)
	local dayBefore = Ops.day(e)
	local function awaySet()
		local s = {}
		for _, rec in W.Staff.inspect(W.office) do if rec.away then s[rec.role .. ":" .. rec.index] = rec.away end end
		return s
	end
	while W.hour() < 7.0 or W.hour() > 7.1 do W.tick(1, econ) end
	W.tick(15, econ)
	local o7 = crewOn()
	check("night crew gone at ~07:05", o7 == 0, o7)
	local at7 = awaySet()
	while not (W.hour() >= 8.5 and W.hour() < 9) do W.tick(1, econ) end
	W.tick(15, econ)
	check("economy calendar advanced at 08:00", Ops.day(e) == dayBefore + 1, Ops.day(e) .. " vs " .. dayBefore)
	local at85 = awaySet()
	local same = true
	for k, v in at7 do if at85[k] ~= v then same = false end end
	for k, v in at85 do if at7[k] ~= v then same = false end end
	check("who is away does not flip at 08:00 (06:00 workday switch = saved day after 08:00)", same)
	-- Dialogue "Who's away today?" at 07:15 vs the rota (receptionist is on duty from 07:15)
	local f = W.Dialogue.facts(W.data, W.session.live)
	check("Dialogue.facts day = saved day", f.day == Ops.day(e))
	-- server-clock jump of 2.5 company days in one step (e.g. a long server hitch / time skew)
	M.Sched.now += 3000
	W.tick(400, econ)
	local stuck = 0
	for _, rec in W.Staff.inspect(W.office) do if rec.event and rec.event ~= "repair" then stuck += 1 end end
	check("no NPC stuck in an event after a clock jump", stuck == 0, stuck)
	check("no background thread errors", errorsNow() == err0, errorsNow() - err0)
end

------------------------------------------------------------------------------------------- empty
-- stage 2 HQ with nobody hired, a rack fault, an apprentice entry for a seed nobody has (stale save), and
-- the talk facts of an empty company.
suites.empty = function()
	local W = makeWorld(M, { tier = 1, hour = 10.0, employees = { researcher = 0, engineer = 0, curator = 0, marketer = 0 }, prepare = function(d)
		d.gpus.consumer = 2
	end })
	local e, Ops = W.data.empire, W.Ops
	local err0 = errorsNow()
	W.tick(50)
	check("no hired rigs", #W.office.Employees:GetChildren() == 0, #W.office.Employees:GetChildren())
	local snap = W.Rota.compute(e, W.hour())
	check("rota of an empty company", snap.apprenticeCount == 0 and next(snap.away) == nil)
	Ops.faultStep(e, W.data.gpus, W.OWNER, 0, W.serverNow())
	local rack = Ops.rack(W.data.gpus)
	table.insert(Ops.faults(e), { slot = 1, gpu = rack[1].gpu, throughput = 1, left = 1, since = 0 })
	W.tick(30)
	local blades = W.office:FindFirstChild("Blades")
	local blade = blades and blades:GetChildren()[1]
	check("blade broken with nobody to repair", blade and blade:GetAttribute("FxState") == "broken")
	local worker = nil
	for _, m in W.rigs() do local r = W.record(m); if r and r.event and r.event.kind == "repair" then worker = m end end
	note("empty stage-2 company, fault at 10:00: repair walker = " .. tostring(worker and (worker:GetAttribute("Role") or worker:GetAttribute("RoleId"))))
	local it = W.job("IT Support")
	if it then
		local p = W.Events.rackPoint(W.record(it), blade)
		note("IT Support may enter the rack point: " .. tostring(p and W.Plan.employeeAllowed("support", W.tier, W.cf:PointToObjectSpace(p))))
	end
	-- stale apprentice entry (seed not on the team): Training Lead must not flicker / be paid for nobody
	e.apprentices = { ["123456"] = { day = Ops.day(e) } }
	W.Assignment.assign(W.office, W.cf, W.session)
	local leadAfterAssign = W.job("Training Lead") ~= nil
	W.tick(15)
	local leadAfterRota = W.job("Training Lead") ~= nil
	note("stale apprentice seed at stage 2: TL after assign=" .. tostring(leadAfterAssign) .. ", after rota=" .. tostring(leadAfterRota) .. ", economy pays TL=" .. tostring(Ops.stageIndex(e) >= Ops.TRAINING_LEAD.from and Ops.apprenticeCount(e) > 0))
	check("Training Lead rig agrees between StaffAssignment and the rota", leadAfterAssign == leadAfterRota, tostring(leadAfterAssign) .. " vs " .. tostring(leadAfterRota))
	local f = W.Dialogue.facts(W.data, W.session.live)
	check("facts of an empty company", f.apprenticeCount == 0 and #f.away == 0)
	check("no background thread errors", errorsNow() == err0, errorsNow() - err0)
end

------------------------------------------------------------------------------------------- many
-- stage 5 at full staff + 6 apprentices + night shifts everywhere + 4 simultaneous rack faults: one worker
-- per fault, one Training Lead, cost of the per-office passes.
suites.many = function()
	local W = makeWorld(M, { tier = 4, hour = 9.2, prepare = function(d)
		d.gpus.accelerator = 10
		d.empire.nightShift = { research = true, engineering = true, data = true, growth = true }
	end })
	local e, Ops, Rota = W.data.empire, W.Ops, W.Rota
	local err0 = errorsNow()
	local staffN = 0; for _, n in e.employees do staffN += n end
	note("stage 5 staff = " .. staffN .. ", rigs = " .. #W.rigs())
	W.tick(60)
	-- apprentices: 6 new hires
	for _, role in { "researcher", "engineer", "curator", "marketer", "researcher", "engineer" } do W.hire(role, { apprentice = true }) end
	W.tick(10)
	local leads = 0
	for _, m in W.rigs() do if m:GetAttribute("Role") == "Training Lead" then leads += 1 end end
	check("exactly one Training Lead", leads == 1, leads)
	-- cost: Rota.compute (every 2 s per office) and Staff.tick (every frame, work every 0.2 s)
	local t0 = realClock()
	for _ = 1, 50 do Rota.compute(e, W.hour()) end
	local rotaMs = (realClock() - t0) / 50 * 1000
	note(string.format("Rota.compute at stage 5 (%d staff, 6 apprentices, night shifts): %.2f ms per call (mock interpreter)", staffN, rotaMs))
	-- 4 faults
	Ops.faultStep(e, W.data.gpus, W.OWNER, 0, W.serverNow())
	local rack = Ops.rack(W.data.gpus)
	local blades = W.office:FindFirstChild("Blades")
	note("stage 5 blades in the building = " .. (blades and #blades:GetChildren() or 0) .. ", owned rack GPUs = " .. #rack)
	for _, slot in { 1, 4, 7, 10 } do table.insert(Ops.faults(e), { slot = slot, gpu = rack[slot].gpu, throughput = 1, left = 1, since = 0 }) end
	local t1 = realClock()
	W.tick(50)
	local tickMs = (realClock() - t1) / 50 * 1000
	note(string.format("Staff.tick + mock movement at stage 5 with 4 faults: %.2f ms per 0.2 s tick (mock)", tickMs))
	local workers, double = {}, false
	W.tick(300, function()
		for _, m in W.rigs() do
			local r = W.record(m)
			if r and r.event and r.event.kind == "repair" then
				if workers[r.event.slot] and workers[r.event.slot] ~= m then double = true end
				workers[r.event.slot] = m
			end
		end
	end)
	local nw = 0; for _ in workers do nw += 1 end
	check("a worker for every fault", nw == 4, nw)
	check("never two workers on one fault", not double)
	local roles = {}
	for _, m in workers do local k = m:GetAttribute("Role") or m:GetAttribute("RoleId"); roles[k] = (roles[k] or 0) + 1 end
	local rs = ""; for k, v in roles do rs ..= k .. "=" .. v .. " " end
	note("stage 5 repair walkers by role: " .. rs)
	-- attribute churn: count attribute writes on blades during 100 ticks with stable faults
	local writes = 0
	for _, b in blades:GetChildren() do
		b.AttributeChanged:Connect(function() writes += 1 end)
	end
	W.tick(100)
	check("blade attributes are not rewritten while faults are stable", writes <= 4, writes)
	check("no background thread errors", errorsNow() == err0, errorsNow() - err0)
end

------------------------------------------------------------------------------------------- nightfault
-- stage 5 at 23:00: the economy repairs at IT speed (IT on call), who walks?
suites.nightfault = function()
	local W = makeWorld(M, { tier = 4, hour = 22.8, prepare = function(d) d.gpus.accelerator = 4 end })
	local e, Ops = W.data.empire, W.Ops
	W.tick(300)
	Ops.faultStep(e, W.data.gpus, W.OWNER, 0, W.serverNow())
	local rack = Ops.rack(W.data.gpus)
	table.insert(Ops.faults(e), { slot = 2, gpu = rack[2].gpu, throughput = 1, left = 1, since = 0 })
	W.tick(60)
	local worker = nil
	for _, m in W.rigs() do local r = W.record(m); if r and r.event and r.event.kind == "repair" then worker = m end end
	local blade = W.office.Blades:GetChildren()[2]
	local eta = blade:GetAttribute("FaultUntil")
	note(string.format("stage 5 night fault at %.1f h: economy IT on duty=%s, label ETA=%.0f s, walker=%s", W.hour(), tostring(Ops.itOnDuty(e, W.serverNow())), (eta or 0) - W.serverNow(), tostring(worker and (worker:GetAttribute("Role") or worker:GetAttribute("RoleId")))))
	check("someone visibly repairs the night fault the economy fixes at IT speed", worker ~= nil)
	-- stage 3 at night (no IT on duty, no night crew): nobody, label must say 5 min
	local W2 = makeWorld(M, { tier = 2, hour = 23.0, prepare = function(d) d.gpus.accelerator = 3 end })
	W2.tick(200)
	Ops.faultStep(W2.data.empire, W2.data.gpus, W2.OWNER, 0, W2.serverNow())
	local rack2 = Ops.rack(W2.data.gpus)
	table.insert(Ops.faults(W2.data.empire), { slot = 1, gpu = rack2[1].gpu, throughput = 1, left = 1, since = 0 })
	W2.tick(20)
	local b2 = W2.office.Blades:GetChildren()[1]
	local eta2 = (b2:GetAttribute("FaultUntil") or 0) - W2.serverNow()
	check("stage 3 night estimate = 300 s (no IT)", math.abs(eta2 - 300) < 5, eta2)
	-- crossing 08:00 the estimate must shrink to the IT speed (economy rate changes)
	while not (W2.hour() >= 8.05 and W2.hour() < 9) do W2.tick(1) end
	W2.tick(10)
	local f = Ops.faults(W2.data.empire)[1]
	local eta3 = (b2:GetAttribute("FaultUntil") or 0) - W2.serverNow()
	check("label estimate follows the economy at 08:00", f == nil or math.abs(eta3 - f.left * 60) < 5, tostring(eta3) .. " vs " .. tostring(f and f.left * 60))
end

------------------------------------------------------------------------------------------- leave
-- the owner leaves mid-action: a running repair, an apprentice tour, an interview hire on hold; session
-- closes, then the plot is released (office destroyed).
suites.leave = function()
	local W = makeWorld(M, { tier = 2, hour = 8.9, staff = 40, day = 4, prepare = function(d) d.gpus.accelerator = 3 end })
	local e, Ops = W.data.empire, W.Ops
	local err0 = errorsNow()
	W.tick(20)
	W.hire("researcher", { apprentice = true })
	W.hire("curator", { hold = true })
	Ops.faultStep(e, W.data.gpus, W.OWNER, 0, W.serverNow())
	local rack = Ops.rack(W.data.gpus)
	table.insert(Ops.faults(e), { slot = 2, gpu = rack[2].gpu, throughput = 1, left = 1, since = 0 })
	local tour, repair = false, false
	for _ = 1, 600 do
		W.tick(1)
		for _, m in W.rigs() do local r = W.record(m); if r and r.event then if r.event.kind == "tour" then tour = true elseif r.event.kind == "repair" then repair = true end end end
		if tour and repair then break end
	end
	check("tour and repair running before the leave", tour and repair, tostring(tour) .. "/" .. tostring(repair))
	-- session closing (SessionService.onClosing callbacks) then Plot.release
	W.session.closed = true
	for _, fn in W.SessionStub.closing do fn(W.session) end
	local rigs = W.rigs()
	local leftRecords = 0
	for _, m in rigs do if W.record(m) then leftRecords += 1 end end
	check("all staff records dropped on session close", leftRecords == 0, leftRecords)
	W.SessionStub.sessions = {}
	W.PlotStub.plots[1].owner = nil
	W.office:Destroy()
	W.PlotStub.plots[1].office = nil
	W.tick(50)
	-- late callbacks after the office is gone
	W.Staff.handoverArrival(W.office, 1, nil)
	W.Staff.expectArrival(W.office, 2, nil, true)
	W.tick(5)
	check("no background thread errors after the owner left", errorsNow() == err0, errorsNow() - err0)
end

------------------------------------------------------------------------------------------- spam
-- hire/fire spam in a single tick (HireEmployee spam), apprentice hire+fire churn, Training Lead count.
suites.spam = function()
	local W = makeWorld(M, { tier = 2, hour = 10.0, staff = 30 })
	local e, Ops = W.data.empire, W.Ops
	local err0 = errorsNow()
	W.tick(100)
	local rev0 = W.office:GetAttribute("StaffRev")
	local before = {}
	for _, m in W.rigs() do before[m] = true end
	local seeds = {}
	for i = 1, 12 do local _, s = W.hire(({ "researcher", "engineer", "curator", "marketer" })[i % 4 + 1]); table.insert(seeds, s) end
	local new = 0
	for _, m in W.rigs() do if not before[m] then new += 1 end end
	check("12 hires in one tick -> 12 new rigs, nothing rebuilt", new == 12, new)
	check("StaffRev +12", W.office:GetAttribute("StaffRev") == rev0 + 12, tostring(W.office:GetAttribute("StaffRev")) .. " vs " .. tostring(rev0))
	local maxMoving = 0
	W.tick(400, function()
		local moving = 0
		for _, m in W.rigs() do local r = W.record(m); if r and (r.nav or r.hop) then moving += 1 end end
		maxMoving = math.max(maxMoving, moving)
	end)
	check("movers cap respected during the hire wave", maxMoving <= W.EmployeeConfig.MAX_MOVING_PER_OFFICE, maxMoving)
	local arrived = 0
	for _, s in seeds do for _, m in W.rigs() do if m:GetAttribute("PersonalitySeed") == s and m:GetAttribute("OffDuty") == false then arrived += 1 end end end
	check("all 12 hires arrived", arrived == 12, arrived)
	check("records = rigs", #W.Staff.inspect(W.office) == #W.rigs(), #W.Staff.inspect(W.office) .. " vs " .. #W.rigs())
	-- apprentice hire + immediate fire churn (EmpireService.fire removes the profile + apprentices entry)
	local maxLeads = 0
	for _ = 1, 5 do
		local _, s = W.hire("engineer", { apprentice = true })
		W.tick(2)
		local leads = 0; for _, m in W.rigs() do if m:GetAttribute("Role") == "Training Lead" then leads += 1 end end
		maxLeads = math.max(maxLeads, leads)
		-- fire the newest engineer (the apprentice)
		local list = e.staffProfiles.engineer
		local gone = table.remove(list)
		e.employees.engineer -= 1
		e.apprentices[tostring(gone.s)] = nil
		W.Assignment.assign(W.office, W.cf, W.session)
		W.tick(2)
	end
	check("never more than one Training Lead during churn", maxLeads <= 1, maxLeads)
	W.tick(15)
	check("Training Lead gone after the churn", W.job("Training Lead") == nil)
	local pend = 0
	for _ in W.Events.memory(W.office).pending do pend += 1 end
	note("pending first-day arrivals left in memory after hire/fire churn: " .. pend)
	check("records = rigs after churn", #W.Staff.inspect(W.office) == #W.rigs(), #W.Staff.inspect(W.office) .. " vs " .. #W.rigs())
	check("no background thread errors", errorsNow() == err0, errorsNow() - err0)
end

------------------------------------------------------------------------------------------- beacon
-- client fault beacon placement against the real rack geometry (garage cabinet vs HQ rack)
suites.beacon = function()
	local Fx = M.require(M.game.StarterPlayer.StarterPlayerScripts.Client.Controllers.PropFxController)
	local function inside(p, part)
		local l = part.CFrame:PointToObjectSpace(p)
		local h = part.Size / 2
		return math.abs(l.X) < h.X and math.abs(l.Y) < h.Y and math.abs(l.Z) < h.Z
	end
	for _, tier in { 0, 2 } do
		local W = makeWorld(M, { tier = tier, hour = 10, employees = { researcher = 1, engineer = 1, curator = 1, marketer = 1 } })
		local blades = W.office:FindFirstChild("Blades")
		local blade = blades:GetChildren()[1]
		local beacon, gui = Fx.faultBeacon(blade)
		local labelPos = beacon.Position + gui.StudsOffset
		local hitBeacon, hitLabel = nil, nil
		for _, p in W.office:GetDescendants() do
			if p:IsA("BasePart") and p ~= blade and p.Transparency < 0.3 and (p.Name == "GarageRack" or p.Name == "ServerRack" or p.Name == "RackTop") then
				if inside(beacon.Position, p) then hitBeacon = p.Name end
				if inside(labelPos, p) then hitLabel = p.Name end
			end
		end
		note(string.format("tier %d: beacon inside %s, label anchor inside %s (AlwaysOnTop=%s)", tier, tostring(hitBeacon), tostring(hitLabel), tostring(gui.AlwaysOnTop)))
		check("tier " .. tier .. ": fault beacon is not buried in the rack body", hitBeacon == nil, hitBeacon)
		check("tier " .. tier .. ": fault label is not buried in the rack body", hitLabel == nil, hitLabel)
		if tier == 0 and #blades:GetChildren() >= 2 then
			local b2 = blades:GetChildren()[2]
			local beacon2 = Fx.faultBeacon(b2)
			note(string.format("garage: two faulty blades -> labels %.2f studs apart vertically (label 52 px tall)", math.abs(beacon2.Position.Y - beacon.Position.Y)))
		end
	end
end

------------------------------------------------------------------------------------------- many2
-- stage 5: simultaneous double assignment, why workers swap, blade writes with the economy running
suites.many2 = function()
	local W = makeWorld(M, { tier = 4, hour = 9.2, prepare = function(d) d.gpus.accelerator = 10 end })
	local e, Ops = W.data.empire, W.Ops
	W.tick(60)
	Ops.faultStep(e, W.data.gpus, W.OWNER, 0, W.serverNow())
	local rack = Ops.rack(W.data.gpus)
	for _, slot in { 1, 4, 7, 10 } do table.insert(Ops.faults(e), { slot = slot, gpu = rack[slot].gpu, throughput = 1, left = 3, since = 0 }) end
	local acc = 0
	local function econ(dt) acc += dt; while acc >= 1 do acc -= 1; Ops.faultStep(e, W.data.gpus, W.OWNER, 1, W.serverNow()) end end
	local simul, swaps, last = 0, 0, {}
	local reasons = {}
	local writes = 0
	local blades = W.office.Blades
	W.tick(100, function() econ(.2) end)
	for _, b in blades:GetChildren() do b.AttributeChanged:Connect(function(n) writes += 1 end) end
	W.tick(300, function()
		econ(.2)
		local now = {}
		for _, m in W.rigs() do
			local r = W.record(m)
			if r and r.event and r.event.kind == "repair" then
				local s = r.event.slot
				if now[s] then simul += 1 end
				now[s] = m
			end
		end
		for s, m in now do
			if last[s] and last[s] ~= m then
				swaps += 1
				local r = W.record(last[s])
				reasons[#reasons + 1] = string.format("slot %d: %s -> %s (old: state=%s lod=%s duty=%s nav=%s)", s, last[s].Name, m.Name, tostring(r and r.state), tostring(r and r.lod), tostring(r and r.onDuty), tostring(r and r.nav ~= nil))
			end
			last[s] = m
		end
		for s, m in last do if not now[s] then
			local r = W.record(m)
			if r and not reasons["end" .. s] then reasons["end" .. s] = true; reasons[#reasons + 1] = string.format("slot %d worker %s left the repair: state=%s event=%s faults=%d", s, m.Name, tostring(r.state), tostring(r.event and r.event.kind), #Ops.faults(e)) end
			last[s] = nil
		end end
	end)
	check("no two workers on the same fault at the same time", simul == 0, simul)
	note("repair worker swaps during 60 s: " .. swaps)
	for i, r in ipairs(reasons) do if i <= 8 then note(r) end end
	note("blade attribute writes in 60 s with the economy running (4 faults, 3 min of work each): " .. writes)
end

------------------------------------------------------------------------------------------- perf
-- Staff.tick cost at stage 5 full staff, 10:00, no faults / apprentices (compare with the gen_neg tree)
suites.perf = function()
	local W = makeWorld(M, { tier = 4, hour = 9.9 })
	W.tick(150)
	local t0 = realClock()
	for _ = 1, 100 do M.Sched.now += .2; W.LiftStub.clock += .2; W.Staff.tick(.2) end
	note(string.format("Staff.tick only (no movement sim) at stage 5: %.2f ms per 0.2 s tick (mock)", (realClock() - t0) * 10))
end

------------------------------------------------------------------------------------------- colour
-- client: a blade registered while unlit, lit later by PlotService (server Color change), then a fault
-- blinks and clears: the blade must show the CURRENT server colour again, not the colour at registration.
suites.colour = function()
	local Fx = M.require(M.game.StarterPlayer.StarterPlayerScripts.Client.Controllers.PropFxController)
	local Color3 = G.Color3
	local office = G.Instance.new("Model"); office.Name = "Office"; office.Parent = G.workspace
	local blades = G.Instance.new("Folder"); blades.Name = "Blades"; blades.Parent = office
	local blade = G.Instance.new("Part"); blade.Name = "RackBlade"; blade.Size = G.Vector3.new(1.4, 4.4, 0.08); blade.Anchored = true; blade.Parent = blades
	local UNLIT, LIT = Color3.fromRGB(39, 46, 43), Color3.fromRGB(60, 200, 220)
	blade.Color = UNLIT
	blade:SetAttribute("Fx", "breathe"); blade:SetAttribute("FxGate", "Training")
	local p = Fx.register(blade)
	check("blade registered as a PropFx prop", p ~= nil)
	if not p then return end
	-- the player buys a GPU: PlotService lights the blade (server writes)
	blade:SetAttribute("Lit", true); blade.Color = LIT
	-- economy fault -> broken -> cleared
	blade:SetAttribute("FxState", "broken")
	local now = 100
	local parts, cfs = {}, {}
	for i = 1, 20 do now += 0.1; Fx.animate(p, now, 0.1, parts, cfs) end
	blade:SetAttribute("FxState", "idle")
	for i = 1, 20 do now += 0.1; Fx.animate(p, now, 0.1, parts, cfs) end
	check("blade colour after the fault = current server colour (lit)", blade.Color == LIT, tostring(blade.Color) .. " (unlit=" .. tostring(UNLIT) .. ")")
end

------------------------------------------------------------------------------------------- crew2150
suites.crew2150 = function()
	local W = makeWorld(M, { tier = 2, hour = 20.5, employees = { researcher = 30, engineer = 14, curator = 10, marketer = 10 }, prepare = function(d)
		d.empire.nightShift = { research = true }
	end })
	W.tick(60)
	local Rota = W.Rota
	local a, b = Rota.nightRange(W.data.empire, "researcher")
	local on = 0
	for i = a, b do local m = W.rigOf("researcher", i); local act = m:GetAttribute("Activity"); if act ~= "OFF_DUTY" and act ~= "LEAVING" then on += 1 end end
	check("night crew home at " .. string.format("%.2f", W.hour()), on == 0, on)
end

------------------------------------------------------------------------------------------- tlfirst
-- the Training Lead is re-created whenever a new apprentice batch starts: does the (same-named) trainer
-- run the new-hire "first day" (badge at reception) every time?
suites.tlfirst = function()
	local W = makeWorld(M, { tier = 2, hour = 10.0, staff = 30, day = 4 })
	W.tick(50)
	local firstTasks = {}
	local names = {}
	for round = 1, 2 do
		local _, seed = W.hire("researcher", { apprentice = true })
		local lead = W.job("Training Lead")
		names[round] = lead and lead:GetAttribute("EmployeeName")
		local saw = false
		W.tick(40, function() if lead and lead:GetAttribute("Task") == "FirstDay" then saw = true end end)
		firstTasks[round] = saw
		-- the apprentice leaves (fired) -> trainer gone
		local list = W.data.empire.staffProfiles.researcher
		for i = #list, 1, -1 do if list[i].s == seed then table.remove(list, i) end end
		W.data.empire.employees.researcher -= 1
		W.data.empire.apprentices[tostring(seed)] = nil
		W.Assignment.assign(W.office, W.cf, W.session)
		W.tick(15)
	end
	note("Training Lead names per batch: " .. tostring(names[1]) .. " / " .. tostring(names[2]) .. "; FirstDay task seen: " .. tostring(firstTasks[1]) .. " / " .. tostring(firstTasks[2]))
	check("the returning Training Lead does not run a new-hire first day again", not firstTasks[2])
end

local fn = suites[SUITE]
if not fn then print("unknown suite " .. tostring(SUITE)); return end
local function body() fn() end
setfenv(body, M.envFor(nil))
local ok, err = M.runMain(body, { timeout = 100000, maxSteps = 120000000 })
if not ok then print("ERROR: " .. tostring(err)); failc += 1 end
print(string.format("review_adv_%s: %d passed, %d failed", SUITE, pass, failc))
