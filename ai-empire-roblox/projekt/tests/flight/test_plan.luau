--!nocheck
-- Flight package: FlightPlan maths (pure, deterministic) - timetable and phases, departure lookup, continuous
-- poses along the real CityPlan geometry (stand = the airport package's stand frame, ground tracks on the
-- apron/taxiways/runway, take-off and landing on the runways, altitude, bank and pitch limits, gear), crew
-- state, VIP helicopter plan, ambient traffic (deterministic, never on the runway while the shuttle uses it).
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_flight && tools/luau tests/flight/test_plan.luau [-a .gen_dir]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_flight")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
M.loadTree(manifest, sources)
M.quiet = true
local G = M.G
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local function body()
	local Vector3, CFrame = G.Vector3, G.CFrame
	local RS = M.game.ReplicatedStorage
	local FP = M.require(RS.Shared.FlightPlan)
	local CityPlan = M.require(RS.Shared.Config.CityPlan)
	local A, B = CityPlan.AIRPORT, CityPlan.ABROAD
	local C = FP.CONFIG
	local I = FP.interval()
	check("interval >= the configured interval", I >= C.interval and I == math.floor(I), I)
	for _, dir in { "out", "back" } do
		local leg = FP.leg(dir)
		check(dir .. ": leg fills half the cycle", math.abs(leg.duration - I / 2) < 1e-6, leg.duration)
		check(dir .. ": boarding >= minimum", leg.boarding >= C.minBoarding - 1e-6, leg.boarding)
		local t = 0
		local okOrder, okPos = true, true
		for _, name in FP.PHASES do
			local ph = leg.phases[name]
			if not ph then okOrder = false break end
			if math.abs(ph.t0 - t) > 1e-6 then okOrder = false end
			if ph.t1 <= ph.t0 then okPos = false end
			t = ph.t1
		end
		check(dir .. ": all 11 phases, in order, contiguous", okOrder)
		check(dir .. ": every phase lasts > 0 s", okPos)
		check(dir .. ": flight time 1-3 min (pushback -> arrival)", FP.flightTime(dir) > 60 and FP.flightTime(dir) < 200, FP.flightTime(dir))
	end
	-- timetable lookup
	local t0 = 1.7e9
	local k = math.floor((t0 - C.epoch) / I)
	local s0 = FP.legStart("out", k)
	check("legStart(out) = epoch + k*interval", s0 == C.epoch + k * I)
	check("legStart(back) = out + interval/2", FP.legStart("back", k) == s0 + I / 2)
	local st = FP.at(s0 + 1)
	check("at(): boarding of leg out at its start", st.dir == "out" and st.cycle == k and st.phase == "boarding" and math.abs(st.tau - 1) < 1e-6)
	local a1, a2 = FP.at(s0 + 77.7), FP.at(s0 + 77.7)
	check("at() is deterministic", a1.phase == a2.phase and a1.tau == a2.tau and a1.cycle == a2.cycle)
	local outLeg = FP.leg("out")
	st = FP.at(s0 + outLeg.phases.cruise.t0 + 0.5)
	check("at(): cruise phase with phase window", st.phase == "cruise" and math.abs(st.phaseStart - (s0 + outLeg.phases.cruise.t0)) < 1e-6 and math.abs(st.phaseEnd - (s0 + outLeg.phases.cruise.t1)) < 1e-6)
	st = FP.at(s0 + I / 2 + 0.5)
	check("at(): the return leg follows", st.dir == "back" and st.phase == "boarding")
	local kk, ls, dep, be = FP.nextLeg("out", s0 + 3)
	check("nextLeg during boarding = this leg", kk == k and ls == s0 and dep == s0 + outLeg.phases.pushback.t0 and be == s0 + outLeg.phases.boarding.t1)
	kk, ls = FP.nextLeg("out", s0 + outLeg.phases.boarding.t1 + 0.1)
	check("nextLeg after boarding = next cycle (missed it)", kk == k + 1 and ls == s0 + I)
	kk, ls = FP.nextLeg("back", s0 + 3)
	check("nextLeg(back) from the out leg = same cycle", kk == k and ls == s0 + I / 2)
	-- poses
	local stand = A.standCFrames[A.shuttleStand]
	local p0 = FP.legPose(outLeg, 0)
	check("parked at the airport package's stand frame (jet bridge meets the door)", (p0.cf.Position - stand.Position).Magnitude < 1e-6 and p0.cf.LookVector:Dot(stand.LookVector) > 0.9999)
	check("engines off and gear down while boarding", p0.engines == false and p0.gearDown and p0.onGround)
	local backLeg = FP.leg("back")
	local pEnd = FP.legPose(outLeg, outLeg.duration)
	check("out leg ends at the Port Meridian stand", (pEnd.cf.Position - FP.PM_STAND.Position).Magnitude < 0.01 and pEnd.cf.LookVector:Dot(FP.PM_STAND.LookVector) > 0.999)
	local bEnd = FP.legPose(backLeg, backLeg.duration)
	check("return leg ends nose-in at the home stand", (bEnd.cf.Position - stand.Position).Magnitude < 0.01 and bEnd.cf.LookVector:Dot(stand.LookVector) > 0.999, bEnd.cf.Position)
	check("return leg starts where the out leg ended", (FP.legPose(backLeg, 0).cf.Position - pEnd.cf.Position).Magnitude < 0.01)
	local function inRect(p, r, m) return p.X >= r.x1 - m and p.X <= r.x2 + m and p.Z >= r.z1 - m and p.Z <= r.z2 + m end
	local homePaved = { A.apron, A.taxiway, A.runway, { x1 = A.connectors[1] - 25, x2 = A.connectors[1] + 25, z1 = A.taxiway.z2 - 5, z2 = A.runway.z1 + 5 }, { x1 = A.connectors[2] - 25, x2 = A.connectors[2] + 25, z1 = A.taxiway.z2 - 5, z2 = A.runway.z1 + 5 } }
	for _, dir in { "out", "back" } do
		local leg = FP.leg(dir)
		local dt = 0.05
		local prev, maxJump, maxBank, maxPitch, maxAlt, minAirAlt = nil, 0, 0, 0, 0, math.huge
		local offPaved, offPM, cruiseGear, liftoff, touchdown = 0, 0, 0, nil, nil
		local tt = 0
		while tt <= leg.duration do
			local p = FP.legPose(leg, tt)
			local pos = p.cf.Position
			if prev then
				local jump = (pos - prev.cf.Position).Magnitude - math.max(p.speed, prev.speed) * dt
				if jump > maxJump then maxJump = jump end
				if prev.onGround and not p.onGround and not liftoff then liftoff = prev.cf.Position end
				if not prev.onGround and p.onGround and not touchdown then touchdown = pos end
			end
			local look = p.cf.LookVector
			maxPitch = math.max(maxPitch, math.deg(math.asin(math.clamp(look.Y, -1, 1))))
			local right = p.cf.RightVector
			maxBank = math.max(maxBank, math.deg(math.asin(math.clamp(math.abs(right.Y), 0, 1))))
			if p.onGround then
				if pos.Z < 5000 then
					local ok = false
					for _, r in homePaved do if inRect(pos, r, 2) then ok = true end end
					if not ok then offPaved += 1 end
					if math.abs(pos.Y - A.apronTop) > 0.01 then offPaved += 1 end
				else
					if not inRect(pos, B.runway, 12) then offPM += 1 end
				end
			else
				maxAlt = math.max(maxAlt, p.altitude)
				if p.phase == "cruise" then minAirAlt = math.min(minAirAlt, p.altitude) end
				if p.altitude < -0.3 then offPaved += 1 end -- never below the ground while airborne
				if p.phase == "cruise" and p.gearDown then cruiseGear += 1 end
			end
			prev = p; tt += dt
		end
		check(dir .. ": continuous motion (no jumps between samples)", maxJump < 0.6, maxJump)
		check(dir .. ": ground movement only on the home apron/taxiways/runway at apron height", offPaved == 0, offPaved)
		check(dir .. ": ground movement at Port Meridian on its runway", offPM == 0, offPM)
		check(dir .. ": bank <= " .. math.deg(C.maxBank) + 1 .. " deg", maxBank <= math.deg(C.maxBank) + 1, maxBank)
		check(dir .. ": pitch <= 20 deg", maxPitch <= 20.5, maxPitch)
		check(dir .. ": climbs to cruise height (>= 600)", maxAlt >= 600, maxAlt)
		check(dir .. ": cruise >= 300 studs above ground", minAirAlt >= 300, minAirAlt)
		check(dir .. ": gear retracted in the cruise", cruiseGear == 0, cruiseGear)
		local depRunway = if dir == "out" then A.runway else B.runway
		local arrRunway = if dir == "out" then B.runway else A.runway
		check(dir .. ": lift-off over the departure runway", liftoff ~= nil and inRect(liftoff, depRunway, 0), liftoff)
		check(dir .. ": touchdown on the arrival runway", touchdown ~= nil and inRect(touchdown, arrRunway, 0), touchdown)
		-- rotation: nose up at the end of the take-off roll
		local tko = leg.phases.takeoff
		local pr = FP.legPose(leg, tko.t1 - 0.05)
		local rot = math.deg(math.asin(pr.cf.LookVector.Y))
		check(dir .. ": rotation ~8 deg at lift-off", rot > 6 and rot < 9, rot)
		local pm = FP.legPose(leg, (tko.t0 + tko.t1) / 2)
		check(dir .. ": take-off roll accelerating, wheels on the runway", pm.onGround and pm.speed > 20 and pm.speed < C.liftoff + 1, pm.speed)
		local pc = FP.legPose(leg, (leg.phases.cruise.t0 + leg.phases.cruise.t1) / 2)
		check(dir .. ": cruise over the sea between the cities", pc.cf.Position.Z > A.runway.z2 + 200 and pc.cf.Position.Z < B.rect.z1 - 200, pc.cf.Position)
	end
	-- pushback reverses: the nose points away from the direction of motion
	local ph = outLeg.phases.pushback
	local pa, pb = FP.legPose(outLeg, ph.t0 + 5), FP.legPose(outLeg, ph.t0 + 5.1)
	check("pushback moves tail first", (pb.cf.Position - pa.cf.Position):Dot(pa.cf.LookVector) < 0)
	-- crew
	local walkStart = outLeg.phases.boarding.t1 - FP.CREW_SEATED - FP.CREW_WALK
	st = FP.at(s0 + 2); check("crew still walking away from the previous arrival at the start of boarding", FP.crewState(st) == "leaving")
	st = FP.at(s0 + FP.CREW_LEAVE - C.deboarding + 0.5); check("crew waits in the crew room", FP.crewState(st) == "crewroom" and walkStart > FP.CREW_LEAVE - C.deboarding)
	local ws, since = FP.crewTimes(FP.at(s0 + walkStart + 1))
	check("crew walks to the aircraft in the last part of boarding", ws == "walking" and math.abs(since - 1) < 1e-6)
	st = FP.at(s0 + outLeg.phases.boarding.t1 - 1); check("crew seated before the doors close", FP.crewState(st) == "cockpit")
	for _, dir in { "out", "back" } do
		local lg = FP.leg(dir)
		check(dir .. ": walk-in starts after the walk-out ended", lg.phases.boarding.t1 - FP.CREW_SEATED - FP.CREW_WALK >= FP.CREW_LEAVE - C.deboarding, lg.phases.boarding.t1)
	end
	st = FP.at(s0 + outLeg.phases.cruise.t0 + 1); check("crew in the cockpit in flight", FP.crewState(st) == "cockpit")
	st = FP.at(s0 + outLeg.phases.deboarding.t0 + 1); check("crew leaves after arrival", FP.crewState(st) == "leaving")
	-- helicopter
	local pa1, pb1 = Vector3.new(310, CityPlan.GROUND + 1, 7648), Vector3.new(0, CityPlan.GROUND + 127, 8408)
	local h = FP.heliPlan(pa1, pb1)
	check("helicopter plan 20-60 s", h.duration > 20 and h.duration < 60, h.duration)
	local c0 = FP.heliPose(h, 0); local c1 = FP.heliPose(h, h.duration)
	check("helicopter starts on pad A and ends on pad B", (c0.Position - pa1).Magnitude < 0.01 and (c1.Position - pb1).Magnitude < 0.01)
	local maxY, jumps, prevP = 0, 0, nil
	for x = 0, h.duration, 0.05 do
		local cf = FP.heliPose(h, x)
		maxY = math.max(maxY, cf.Position.Y)
		if prevP and (cf.Position - prevP).Magnitude > C.heliSpeed * 0.05 + 0.6 then jumps += 1 end
		prevP = cf.Position
	end
	check("helicopter cruises above the roof pad", maxY >= pb1.Y + C.heliCruise - 1, maxY)
	check("helicopter moves continuously", jumps == 0, jumps)
	local _, rotorStart = FP.heliPose(h, 0); local _, rotorMid = FP.heliPose(h, h.duration / 2)
	check("rotor spools up", rotorStart == 0 and rotorMid == 1)
	local r0, r1, free = FP.heliTimes("hotel", 100, pa1, pb1)
	check("to the hotel: ride first, then the ferry back", r0 == 100 and r1 > r0 and free > r1)
	local q0, q1 = FP.heliTimes("airport", 100, pa1, pb1)
	check("to the airport: ferry first, then the ride", q0 > 100 and q1 > q0)
	local _, _, carrying = FP.heliAt("airport", 100, 101, pa1, pb1)
	check("no passenger during the pick-up ferry", carrying == false)
	-- ambient traffic
	local e1, e2 = FP.ambient(k), FP.ambient(k)
	check("ambient events deterministic", #e1 == #e2 and #e1 >= 2 and e1[1].id == e2[1].id and e1[1].t0 == e2[1].t0)
	local slots = FP.ambientSlots()
	check("at least one runway slot per cycle", #slots >= 1, #slots)
	local clash, skyLow = 0, 0
	for c = k, k + 20 do
		for _, e in FP.ambient(c) do
			if e.kind == "sky" then
				local p = FP.ambientPose(e, e.t0 + e.duration / 2)
				if not p or p.altitude < 2300 then skyLow += 1 end
			else
				for x = e.t0, e.t0 + e.duration, 1 do
					local sst = FP.at(x)
					local p = FP.ambientPose(e, x)
					local onRunway = p and p.cf.Position.Z > A.runway.z1 - 30 and p.cf.Position.Z < A.runway.z2 + 30 and (p.onGround or p.altitude < 120)
					local shuttleRunway = (sst.dir == "out" and (sst.phase == "takeoff")) or (sst.dir == "back" and sst.phase == "landing")
					if onRunway and shuttleRunway then clash += 1 end
				end
			end
		end
	end
	check("ambient runway traffic never shares the runway with the shuttle (20 cycles)", clash == 0, clash)
	check("sky crossings stay high", skyLow == 0, skyLow)
	-- reset() rebuilds after a config change
	local old = C.interval
	C.interval = 900; FP.reset()
	check("config change: new interval after reset()", FP.interval() == 900)
	C.interval = old; FP.reset()
	check("config restored", FP.interval() == I)
end

local ok, err = M.runMain(body, { timeout = 300, maxSteps = 5000000 })
if not ok then failc += 1; print("ERROR " .. tostring(err)) end
print(string.format("flight_plan: %d passed, %d failed", pass, failc))
if failc > 0 then error("flight_plan failed", 0) end
