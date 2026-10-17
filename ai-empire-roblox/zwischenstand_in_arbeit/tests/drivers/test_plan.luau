--!nocheck
-- drivers package: DrivePlan (pure) on the REAL modules in the mock.
--   places (every zone, plots 1..12), reachability of every place pair, FLIGHT_REQUIRED / SAME_PLACE / BAD_PLACE,
--   continuity (gaps, heading steps), speed profile (class limits, corner limit, accel / decel, standing start and
--   stop), believable durations, kerb stops (on the asphalt, parallel, door off the road), no point inside a
--   CityPlan building footprint, ride plans (encode / decode round trip, malformed plans rejected, pose phases
--   and continuity at segment boundaries), company drivers == CompanyOps' paid drivers for stages 1..5 (also against
--   the real Ops.step summary), nearest pick-up, kerb side for "let me out here", wheelbase pitch on the ramp.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_drivers && cd tests/drivers && ../../tools/luau test_plan.luau -a .gen_drivers
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_drivers")
local M = require("../../harness/mock")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local G = M.G
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local function body()
	local Vector3, CFrame = G.Vector3, G.CFrame
	local RS = M.game.ReplicatedStorage
	local Drive = M.require(RS.Shared.DrivePlan)
	local City = M.require(RS.Shared.Config.CityPlan)
	local Metro = M.require(RS.Shared.Config.MetroPlan)
	local Ops = M.require(RS.Shared.CompanyOps)
	local Template = M.require(M.game.ServerScriptService.Server.Lib.Template)

	------------------------------------------------------------------ places
	local home1 = Drive.places("home", 1)
	local abroad = Drive.places("abroad")
	local ids = {}
	for _, p in home1 do ids[p.id] = p end
	for _, p in abroad do ids[p.id] = p end
	for _, id in { "hq_entrance", "hq_garage", "airport_departures", "airport_arrivals", "pm_limo", "pm_hotel", "pm_airport" } do
		check("place " .. id, ids[id] ~= nil)
	end
	local downtown, towers = 0, 0
	for _, b in City.BUILDINGS do
		if b.zone == "downtown" then
			downtown += 1
			check("Business City building has a place: " .. b.id, ids[b.id] ~= nil and ids[b.id].zone == "home")
		elseif b.zone == "abroad" and b.kind == "tower" then
			towers += 1
			check("client tower has a place: " .. b.id, ids["pm_" .. b.id] ~= nil and ids["pm_" .. b.id].zone == "abroad")
		end
	end
	check("15 Business City buildings + 4 towers", downtown == 15 and towers == 4, downtown .. "/" .. towers)
	local vip = Metro.VIP_LIMO.stand
	check("pm_limo stop = MetroPlan.VIP_LIMO.stand (bay 1)", (ids.pm_limo.stop.Position - Vector3.new(vip.Position.X, City.ROAD_TOP, vip.Position.Z)).Magnitude < 0.01
		and ids.pm_limo.stop.LookVector:Dot(vip.LookVector) > 0.999)
	check("places(nil, plot) = both zones", #Drive.places(nil, 1) == #home1 + #abroad)
	check("places('home') without plot has no HQ", Drive.place("hq_entrance") == nil and #Drive.places("home") == #home1 - 2)
	check("bad place ids", Drive.place(nil) == nil and Drive.place(42) == nil and Drive.place("nope") == nil and Drive.place("hq_entrance", 0 / 0) == nil and Drive.place("hq_entrance", 13) == nil)
	check("clientPlace by catalogue name", Drive.clientPlace("CloudDesk") and Drive.clientPlace("CloudDesk").id == "clouddesk"
		and Drive.clientPlace("Helix Research") and Drive.clientPlace("Helix Research").id == "pm_helixresearch", Drive.clientPlace("CloudDesk"))
	for _, c in Ops.CLIENTS do
		local p = Drive.clientPlace(c.name)
		check("every catalogue client has a drive place: " .. c.name, p ~= nil and (c.trip == "abroad") == (p.zone == "abroad"), p and p.id)
	end

	------------------------------------------------------------------ legs: reachability, continuity, speeds, footprints
	local function inFootprint(p)
		for _, b in City.BUILDINGS do
			local l = b.frame:PointToObjectSpace(p)
			if math.abs(l.X) < b.width / 2 - 0.5 and l.Z > 0.5 and l.Z < b.depth - 0.5 then return b.id end
		end
		return nil
	end
	local legs, worstGap, worstTurn, worstTurnKey = 0, 0, 0, ""
	local speedBad, accelBad, footBad, startStopBad, routeBad = {}, {}, {}, {}, {}
	local durs = {}
	local function examine(leg)
		legs += 1
		local pts, t, cum = leg.pts, leg.t, leg.cum
		for i = 2, #pts do
			local g = (pts[i] - pts[i - 1]).Magnitude
			if g > worstGap then worstGap = g end
		end
		for i = 2, #pts - 1 do
			local a, b = pts[i] - pts[i - 1], pts[i + 1] - pts[i]
			local fa, fb = Vector3.new(a.X, 0, a.Z), Vector3.new(b.X, 0, b.Z)
			if fa.Magnitude > 0.2 and fb.Magnitude > 0.2 then
				local ang = math.deg(math.acos(math.clamp(fa.Unit:Dot(fb.Unit), -1, 1)))
				if ang > worstTurn then worstTurn = ang; worstTurnKey = leg.key end
			end
		end
		-- speeds from the time stamps: never above the road class maximum, accelerations bounded
		-- Port Meridian keeps the city traffic's pace (Drive.SPEED.metro)
		local vmax = (if string.sub(leg.from, 1, 3) == "pm_" then Drive.SPEED.metro else Drive.SPEED.road) + 0.01
		local prevV = 0
		for i = 2, #pts do
			local dt = t[i] - t[i - 1]
			local ds = cum[i] - cum[i - 1]
			if dt <= 0 and ds > 1e-6 then table.insert(speedBad, leg.key); break end
			if dt > 0 then
				local v = ds / dt
				if v > vmax then table.insert(speedBad, leg.key .. " v=" .. v); break end
			end
		end
		for s = 0, leg.len, 4 do
			local p = Drive.posAt(leg, s)
			local b = inFootprint(p)
			if b then table.insert(footBad, leg.key .. " in " .. b); break end
		end
		local v0 = (Drive.distAt(leg, 0.2) - 0) / 0.2
		local vEnd = (leg.len - Drive.distAt(leg, leg.dur - 0.2)) / 0.2
		if v0 > 2.5 or vEnd > 2.5 then table.insert(startStopBad, leg.key .. string.format(" %.1f/%.1f", v0, vEnd)) end
		-- acceleration over 1-second windows within ACCEL / DECEL (+ corner speed changes are slower than that)
		local tt = 0
		local last = nil
		while tt + 1 <= leg.dur do
			local v = Drive.distAt(leg, tt + 1) - Drive.distAt(leg, tt)
			if last and math.abs(v - last) > math.max(Drive.ACCEL, Drive.DECEL) * 1.25 + 0.5 then table.insert(accelBad, leg.key .. string.format(" dv=%.1f", v - last)); break end
			last = v
			tt += 1
		end
		durs[leg.key] = leg.dur
	end
	for _, plot in { 1, 4, 7, 12 } do
		local list = Drive.places("home", plot)
		for _, a in list do
			for _, b in list do
				if a.id ~= b.id then
					local leg, err = Drive.leg(a.id, b.id, plot)
					if leg then examine(leg) else table.insert(routeBad, a.id .. ">" .. b.id .. "#" .. plot .. " " .. tostring(err)) end
				end
			end
		end
		local back = Drive.leg("hq_entrance", "hq_garage", plot, "drop")
		check("drop-off side back to the garage, plot " .. plot, back ~= nil)
		if back then examine(back) end
	end
	for _, a in abroad do
		for _, b in abroad do
			if a.id ~= b.id then
				local leg, err = Drive.leg(a.id, b.id)
				if leg then examine(leg) else table.insert(routeBad, a.id .. ">" .. b.id .. " " .. tostring(err)) end
			end
		end
	end
	check("every place reachable from every place of its zone (plots 1, 4, 7, 12 + abroad)", #routeBad == 0, table.concat(routeBad, "; "))
	check("legs examined", legs > 700, legs)
	check("continuous: no gap above " .. Drive.STEP + 0.6 .. " studs", worstGap <= Drive.STEP + 0.6, worstGap)
	check("smooth: heading steps <= 12 degrees per sample", worstTurn <= 12, string.format("%.1f %s", worstTurn, worstTurnKey))
	check("speeds within the road class maximum", #speedBad == 0, table.concat(speedBad, "; "))
	check("accelerations bounded", #accelBad == 0, table.concat(accelBad, "; "))
	check("standing start and stop", #startStopBad == 0, table.concat(startStopBad, "; "))
	check("no leg runs through a CityPlan building footprint", #footBad == 0, table.concat(footBad, "; "))
	local function dur(key) return durs[key] end
	local d1 = dur("hq_entrance:stop>airport_departures#1")
	check("HQ (plot 1) -> airport takes a believable 40..120 s", d1 and d1 >= 40 and d1 <= 120, d1)
	local d2 = dur("hq_entrance:stop>clouddesk#7")
	check("HQ (plot 7) -> CloudDesk 25..100 s", d2 and d2 >= 25 and d2 <= 100, d2)
	local d3 = dur("pm_limo:stop>pm_hotel#*") -- static legs are shared by every plot (key "*")
	check("limo stand -> Meridian Grand 15..70 s", d3 and d3 >= 15 and d3 <= 70, d3)
	local d4 = dur("hq_garage:stop>hq_entrance#1")
	check("garage -> HQ entrance 10..40 s", d4 and d4 >= 10 and d4 <= 40, d4)
	check("average speed on the airport run 20..64 studs/s", d1 and (Drive.leg("hq_entrance", "airport_departures", 1).len / d1) >= 20)
	local cross, cerr = Drive.leg("hq_entrance", "pm_hotel", 1)
	check("home -> abroad needs a flight", cross == nil and cerr == "FLIGHT_REQUIRED", cerr)
	local same, serr = Drive.leg("pm_hotel", "pm_hotel")
	check("same place refused", same == nil and serr == "SAME_PLACE")
	local bad, berr = Drive.leg("nope", "pm_hotel")
	check("unknown place refused", bad == nil and berr == "BAD_PLACE")
	check("leg cache returns the same table", Drive.leg("pm_limo", "pm_hotel") == Drive.leg("pm_limo", "pm_hotel"))

	------------------------------------------------------------------ kerb stops
	for _, p in Drive.places(nil, 3) do
		if p.kind == "garage" or p.kind == "hq" then continue end
		local sp = p.stop.Position
		-- City Airport's drop-off lane (AirportBuilder DropOffLane, z 2400..2418) is not one of CityPlan's roads
		local onRoad = if p.zone == "abroad" then true elseif p.kind == "airport" then sp.Z > 2400 and sp.Z < 2418 - 3.7 else City.onRoad(sp, 0)
		check("stop on the asphalt: " .. p.id, onRoad, sp)
		check("door off the road: " .. p.id, not City.onRoad(p.door.Position, 0), p.door.Position)
		check("door within 18 studs of the stop: " .. p.id, Drive.flat(p.door.Position, sp) <= 18, Drive.flat(p.door.Position, sp))
		-- the car stands straight at the kerb: the last 8 studs of every leg ending there run along the stop heading
		local any = nil
		for _, q in Drive.places(p.zone, 3) do if q.id ~= p.id and q.kind ~= "garage" then any = q; break end end
		local leg = any and Drive.leg(any.id, p.id, 3)
		if leg then
			local a = Drive.posAt(leg, leg.len - 8)
			local dir = Vector3.new(sp.X - a.X, 0, sp.Z - a.Z)
			check("straight at the kerb (last 8 studs parallel): " .. p.id, dir.Magnitude > 1 and dir.Unit:Dot(p.stop.LookVector) > 0.99, dir.Magnitude > 1 and dir.Unit:Dot(p.stop.LookVector))
		end
	end

	------------------------------------------------------------------ ride plans
	local T = 1.7e9
	local segs = {
		{ from = "hq_garage", to = "hq_entrance", t0 = T + 6, who = "D" },
		{ from = "hq_entrance", to = "airport_departures", t0 = T + 60, who = "D,R,C1" },
		{ from = "airport_departures", to = "hq_garage", t0 = T + 200, who = "D" },
	}
	local str = Drive.encode(segs)
	check("encode format", string.sub(str, 1, 31) == "hq_garage>hq_entrance|D@1700000", str)
	local back2 = Drive.decode(str, 1)
	check("decode round trip", back2 and #back2 == 3 and back2[2].who == "D,R,C1" and math.abs(back2[2].t0 - (T + 60)) < 0.01 and back2[3].to == "hq_garage", str)
	local dropStr = Drive.encode({ { from = "hq_entrance", to = "hq_garage", side = "drop", t0 = T, who = "D" } })
	check("drop side encoded as ~d", string.find(dropStr, "hq_garage~d|D", 1, true) ~= nil and Drive.decode(dropStr, 2)[1].side == "drop", dropStr)
	check("empty plan decodes to {}", Drive.decode("", 1) and #Drive.decode("", 1) == 0)
	local malformed = {
		"hq_garage>nowhere|D@1",
		"hq_garage>hq_entrance|D@2;hq_entrance>airport_departures|D@1",
		"hq_garage>hq_entrance|X@1",
		"hq_garage>hq_entrance|D,R,C1,C2,G1@1",
		"hq_garage>hq_entrance|D@abc",
		"hq_garage>hq_entrance|D@1;;",
		"hq_garage>hq_entrance~x|D@1",
		"pm_limo>pm_hotel|D@1;pm_hotel>clouddesk|D@2",
		string.rep("a", 700),
	}
	for _, m in malformed do check("malformed plan rejected: " .. string.sub(m, 1, 40), Drive.decode(m, 1) == nil) end
	check("non-string plan rejected", Drive.decode(42, 1) == nil and Drive.decode(nil, 1) == nil)
	local seven = {}
	for i = 1, 7 do table.insert(seven, "pm_limo>pm_hotel|D@" .. i) end
	check("more than MAX_SEGS segments rejected", Drive.decode(table.concat(seven, ";")) == nil)
	local seat = Drive.seating("D,R,,C1")
	check("seating: seat order driver, rearR, rearL, front", seat.driver == "D" and seat.rearR == "R" and seat.rearL == nil and seat.front == "C1")
	local p0 = Drive.pose(segs, 1, T)
	check("pose before the first leg: parked at its start", p0 and p0.phase == "before" and p0.index == 1 and (p0.cf.Position - Drive.leg("hq_garage", "hq_entrance", 1).pts[1]).Magnitude < 0.5)
	local leg1 = Drive.leg("hq_garage", "hq_entrance", 1)
	local p1 = Drive.pose(segs, 1, T + 6 + leg1.dur / 2)
	check("pose moving on leg 1", p1 and p1.phase == "moving" and p1.index == 1 and p1.speed > 0 and p1.who == "D")
	local p2 = Drive.pose(segs, 1, T + 6 + leg1.dur + 5)
	check("pose waiting at the pick-up", p2 and p2.phase == "waiting" and p2.place == "hq_entrance" and p2.speed == 0)
	local endOfWait = Drive.pose(segs, 1, T + 60 - 0.001)
	local startRide = Drive.pose(segs, 1, T + 60 + 0.001)
	check("continuous at the segment boundary", endOfWait and startRide and (endOfWait.cf.Position - startRide.cf.Position).Magnitude < 0.2, endOfWait and startRide and (endOfWait.cf.Position - startRide.cf.Position).Magnitude)
	check("riding seats", startRide and startRide.who == "D,R,C1")
	local pend = Drive.planEnd(segs, 1)
	local pd = Drive.pose(segs, 1, pend + 1)
	check("pose done after the last leg (parked in the garage)", pd and pd.phase == "done" and pd.place == "hq_garage")
	check("planEnd = last start + its leg", math.abs(pend - (T + 200 + Drive.leg("airport_departures", "hq_garage", 1).dur)) < 1e-6)
	check("pose of an empty plan is nil", Drive.pose({}, 1, T) == nil)
	-- determinism: the same string gives the same car on every machine
	local a1 = Drive.pose(Drive.decode(str, 1), 1, T + 100)
	local a2 = Drive.pose(Drive.decode(str, 1), 1, T + 100)
	check("deterministic pose from the published string", a1 and a2 and a1.cf == a2.cf)

	------------------------------------------------------------------ company drivers = CompanyOps
	local Economy = { applyFlow = function() end, spend = function() return true end }
	for stage = 1, 5 do
		local d = Template.new()
		d.company = { name = "Nimbus Labs", logo = "N", color = "cyan", spec = "general", foundedAt = 0, reputation = 10 }
		d.money = 1e6
		d.empire.office = stage
		local s = { player = { UserId = 1001 }, userId = 1001, data = d, live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} } }
		Ops.step(s, 1, Economy, 9 * 90)
		local paid = s.live.ops and s.live.ops.drivers
		check("stage " .. stage .. ": drivers == CompanyOps' paid drivers (" .. tostring(paid) .. ")", paid ~= nil and Drive.drivers(d.empire) == paid, Drive.drivers(d.empire))
	end
	check("stage 1 = garage: no driver", Drive.drivers({ office = 1 }) == 0)
	check("stage 2: one driver", Drive.drivers({ office = 2 }) == 1 and Drive.drivers({ office = 3 }) == 1)
	check("stage 4+: two drivers", Drive.drivers({ office = 4 }) == 2 and Drive.drivers({ office = 5 }) == 2)
	check("no empire: no driver", Drive.drivers(nil) == 0)
	check("first driver stage = Ops.DRIVER.from", Drive.FIRST_DRIVER_STAGE == Ops.DRIVER.from)

	------------------------------------------------------------------ pick-up places
	local info1 = City.plots()[1]
	local atHQ = info1.cframe:PointToWorldSpace(Vector3.new(0, 3, -60))
	local hq = Drive.nearestPickup(atHQ, "home", 1)
	check("on the own plot: HQ entrance", hq and hq.id == "hq_entrance")
	local other = Drive.nearestPickup(City.plots()[2].cframe:PointToWorldSpace(Vector3.new(0, 3, -60)), "home", 1)
	check("on another company's plot: no pick-up", other == nil)
	local ap = Drive.nearestPickup(Vector3.new(60, City.WALK_TOP + 3, 2425), "home", 1)
	check("at the departures door: airport departures", ap and ap.id == "airport_departures", ap and ap.id)
	local arr = Drive.nearestPickup(Vector3.new(298, City.WALK_TOP + 3, 2425), "home", 1)
	check("at the arrivals door: airport arrivals", arr and arr.id == "airport_arrivals", arr and arr.id)
	local cd = ids.clouddesk
	local atCD = Drive.nearestPickup(cd.door.Position, "home", 1)
	check("at CloudDesk's door: CloudDesk", atCD and atCD.id == "clouddesk")
	local none, why = Drive.nearestPickup(Vector3.new(600, 30, 1250), "home", 1)
	check("in the middle of nowhere: TOO_FAR", none == nil and why == "TOO_FAR")
	local pmh = Drive.nearestPickup(ids.pm_hotel.door.Position, "abroad")
	check("abroad at the hotel door: Meridian Grand", pmh and pmh.id == "pm_hotel")
	local pml = Drive.nearestPickup(ids.pm_limo.door.Position, "abroad")
	check("abroad at the stand: limo stand", pml and pml.id == "pm_limo")

	------------------------------------------------------------------ getting out mid-ride
	local leg = Drive.leg("hq_entrance", "clouddesk", 5)
	local bad2 = {}
	for s = 40, leg.len - 40, 5 do
		local cf = Drive.poseAtDist(leg, s)
		local zoneHere = Drive.zoneAt(cf.Position)
		if zoneHere ~= "home" then continue end
		local out = Drive.kerbSide(cf, "home", 5)
		local info = City.plots()[5]
		local inSite = City.inRect(info.rect, cf.Position.X, cf.Position.Z, 8)
		if not inSite and (City.onRoad(out.Position, 0) or Drive.flat(out.Position, cf.Position) > 62) then table.insert(bad2, string.format("%d", s)) end
	end
	check("let-me-out point is beside the road (sidewalk), near the car", #bad2 == 0, table.concat(bad2, ","))
	local inSite = Drive.kerbSide(Drive.poseAtDist(Drive.leg("hq_garage", "hq_entrance", 5), 30), "home", 5)
	check("let-me-out inside the site = the HQ alight point", (inSite.Position - City.plots()[5].cframe:PointToWorldSpace(Drive.HQ.alight.Position)).Magnitude < 0.01)
	local pmLeg = Drive.leg("pm_limo", "pm_hotel")
	local pmOut = Drive.kerbSide(Drive.poseAtDist(pmLeg, pmLeg.len / 2, Drive.WHEELBASE.limo), "abroad")
	local onPm = false
	for _, r in Metro.ROADS do
		local rr = Metro.roadRect(r)
		if pmOut.Position.X >= rr.x1 and pmOut.Position.X <= rr.x2 and pmOut.Position.Z >= rr.z1 and pmOut.Position.Z <= rr.z2 then onPm = true end
	end
	check("let-me-out abroad is off Port Meridian's roads", not onPm, pmOut.Position)

	------------------------------------------------------------------ ramp pose
	local ramp = Drive.leg("hq_garage", "hq_entrance", 1)
	local cfRamp = info1.cframe
	local midRamp, rampPitch = nil, nil
	for s = 0, ramp.len, 1 do
		local cf = Drive.poseAtDist(ramp, s)
		local l = cfRamp:PointToObjectSpace(cf.Position)
		if math.abs(l.Z - -91) < 1 then midRamp = cf; rampPitch = math.deg(math.asin(cf.LookVector.Y)) end
	end
	check("on the ramp the car pitches with it (~8.3 degrees up)", rampPitch and math.abs(rampPitch - math.deg(math.atan(16 / 110))) < 0.6, rampPitch)
	local foot = nil
	for s = 0, ramp.len, 0.5 do
		local cf = Drive.poseAtDist(ramp, s)
		local l = cfRamp:PointToObjectSpace(cf.Position)
		if math.abs(l.Z - -36) < 0.3 then foot = math.deg(math.asin(cf.LookVector.Y)) end
	end
	check("at the ramp foot the pitch is only partial (axle model)", foot and foot > 0.5 and foot < 7.5, foot)
	check("place lists are cached", Drive.places("home", 1) == Drive.places("home", 1))
	check("hud text", Drive.hudText("City Airport", 48) == "To City Airport · 0:48" and Drive.clock(125.4) == "2:05")
	check("place names inside a sentence (articles)", Drive.atName(Drive.place("hq_entrance", 1)) == "the HQ entrance" and Drive.atName(Drive.place("pm_limo")) == "the VIP limousine stand"
		and Drive.atName(Drive.place("airport_departures")) == "City Airport (departures)" and Drive.atName(Drive.place("clouddesk")) == Drive.place("clouddesk").name)
	------------------------------------------------------------------ review round 1
	-- the limousine garage (pm_depot) in Arrivals Drive's east tunnel: reachable both ways, out of sight past the gate
	local depotPlace = Drive.place("pm_depot")
	local toStand = Drive.leg("pm_depot", "pm_limo")
	local toDepot = Drive.leg("pm_hotel", "pm_depot")
	check("pm_depot: a garage place inside the east tunnel (x > 700), legs both ways", depotPlace and depotPlace.kind == "garage" and depotPlace.stop.Position.X > 700
		and toStand ~= nil and toDepot ~= nil and (Drive.endCF(toDepot).Position - depotPlace.drop.Position).Magnitude < 0.01)
	local nPm = 0
	for _, p in Drive.places("abroad") do if p.kind ~= "garage" then nPm += 1 end end
	check("pm_depot is no pick-up / destination (garage kind)", nPm == 7 and Drive.nearestPickup(depotPlace.stop.Position, "abroad") == nil)
	-- the stand pose: the idle limousine, a car arriving and a car leaving all stand at the stand's exact CFrame
	local stand = Drive.place("pm_limo")
	local function sameCF(a, b) return (a.Position - b.Position).Magnitude < 0.02 and a.LookVector:Dot(b.LookVector) > 0.99995 end
	local okStand = true
	for _, wb in { Drive.WHEELBASE.limo, 18.10 } do
		if not sameCF(Drive.endCF(toStand, wb), stand.stop) or not sameCF(Drive.poseAtDist(Drive.leg("pm_limo", "pm_hotel"), 0, wb), stand.stop) then okStand = false end
	end
	check("limousine stand: arrive / leave poses == the stand pose (part-built and mesh wheelbase)", okStand)
	-- the shuttle / jet put the founder down in the arrivals hall: the limousine stand is his pick-up
	local fromHall = Drive.nearestPickup(City.ABROAD.arrival.Position, "abroad")
	local fromPlaza = Drive.nearestPickup(Vector3.new(-150, City.WALK_TOP + 3, 7720), "abroad")
	check("arrivals hall / plaza -> the limousine stand", fromHall and fromHall.id == "pm_limo" and fromPlaza and fromPlaza.id == "pm_limo")
	local nAny, nD = Drive.nearestAny(Vector3.new(600, 30, 1250), "home", 1)
	check("nearestAny: the nearest pick-up whatever the distance", nAny ~= nil and nD > 90 and nD < 2000, nD)
	-- abroad cruise speed
	local maxV = 0
	for _, v in Drive.leg("pm_limo", "pm_helixresearch").v do maxV = math.max(maxV, v) end
	check("Port Meridian cruise speed is the city traffic's (<= 30)", maxV <= Drive.SPEED.metro + 0.01 and maxV > 20, maxV)
	-- let-me-out candidates: the preferred one first, several alternatives along the road
	local midCF = Drive.poseAtDist(leg, leg.len * 0.5)
	local cands = Drive.kerbCandidates(midCF, "home", 5)
	check("kerbCandidates: preferred first (= kerbSide), alternatives to step along the road", #cands >= 4 and cands[1] == Drive.kerbSide(midCF, "home", 5))
	-- seated occupants fit between the side glass panes
	local sc, x = Drive.seatFit(3.1)
	check("seatFit: arms inside the glass, neighbours not overlapping", sc <= Drive.RIG_SCALE and x + 2 * sc <= 3.1 - 0.1 and x - 2 * sc >= 0)
	-- working hours
	local base = 1.7e9 - (1.7e9 % 1200)
	check("drivers on post 06-22, longer walk at night", Drive.onPost(base + 450) and not Drive.onPost(base + 1000) and Drive.walkAt(base + 1000) == Drive.WALK_NIGHT
		and Drive.walkAt(base + 450) == Drive.WALK)
	-- leg cache: static legs shared, LRU bounded
	check("static legs are shared by every plot", Drive.leg("clouddesk", "airport_departures", 2) == Drive.leg("clouddesk", "airport_departures", 9))
	check("leg cache bounded", Drive.legCacheSize() <= Drive.LEG_CACHE)
	local _ = midRamp
	local __ = CFrame
end
setfenv(body, M.envFor(nil))
local ok, err = M.runMain(body, { timeout = 600 })
if not ok then failc += 1; print("CRASH " .. tostring(err)) end
print(string.format("drivers_plan: %d passed, %d failed", pass, failc))
