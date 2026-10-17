--!nocheck
-- guests_jet: hotel guests + terminal passengers (GuestPlan maths and the real GuestController in the mock).
-- Hotel: guest count = min(HotelGuests, HotelRooms, cap), everybody in the house at night and invisible (in the
-- rooms), breakfast 08:00-10:00, check-out 10:00-12:00 / check-in 13:30-17:30 with suitcases, evening lounge, unique
-- seats, unique rooms, deterministic per plot + day, every walk only crosses room boundaries through doors
-- (BuildingPlan room rects + doors, tiers 2-4), every node on a floor of its level.
-- Terminals: counts, caps, timing against the FlightPlan timetable (nobody boards before boarding opens or after
-- the doors close, arrivals only after the deboarding starts), unique gate seats.
-- Client: figures for the visible actors of the nearest plot (world = CampusCFrame * local), luggage parts, one
-- BulkMoveTo per step, night = nobody, cap 12, far camera = everything unparented, terminal passengers <= 40.
-- Guest count changes (fix round, review_guests_jet S8): a slot's day never depends on N; hosted client teams
-- (slots above CompanyOps' 7) breakfast together, hold the workshop upstairs, sit in the lobby at night; a live change
-- 7 -> 9 -> 7 (GuestController) moves nobody, the new guests come in from the street with suitcases, the leaving
-- ones finish their walk and check out - no figure jumps, pops in mid-building or vanishes in view.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_gj && cd tests/guests_jet && ../../tools/luau test_guests.luau -a .gen_gj
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_gj")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
M.loadTree(manifest, sources)
M.quiet = true
local G = M.G
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local function body()
	local Instance, Vector3, CFrame = G.Instance, G.Vector3, G.CFrame
	local game = M.game
	local RS = game.ReplicatedStorage
	local GP = M.require(RS.Shared.GuestPlan)
	local FP = M.require(RS.Shared.FlightPlan)
	local Plan = M.require(RS.Shared.Config.BuildingPlan)
	local Ops = M.require(RS.Shared.CompanyOps)
	local sOf = GP.sOfHour

	------------------------------------------------------------------ counts
	check("guestCount = HotelGuests (7 of 12 rooms)", GP.guestCount(7, 12) == 7)
	check("guestCount capped by the rooms (15 guests, 12 rooms)", GP.guestCount(15, 12) == 12)
	check("guestCount capped by HotelRooms (20 guests, 8 rooms)", GP.guestCount(20, 8) == 8)
	check("guestCount: no attribute -> 0 guests", GP.guestCount(nil, 12) == 0 and GP.guestCount(3, nil) == 3)
	check("hotel rooms = Plan.HOTEL_ROOMS", #GP.HOTEL_ROOMS == Plan.HOTEL_ROOMS and GP.HOTEL_CAP == Plan.HOTEL_ROOMS)
	check("CompanyOps' guests fit the rooms at the default occupancy", GP.guestCount(Ops.hotelGuests({ deals = { tripList = {} } }), Ops.GUEST.rooms) == math.floor(Ops.GUEST.rooms * Ops.GUEST.occupancy + 0.5))

	------------------------------------------------------------------ schedules
	local SEED, N = 4242, 12
	local function visibleAt(seed, n, d, s)
		local out = {}
		for g = 1, n do
			for _, a in GP.slotDay(seed, g, d, n) do
				local mode, cf, hint, carry = GP.sample(a, s)
				if mode ~= "hidden" then table.insert(out, { a = a, mode = mode, cf = cf, hint = hint, carry = carry, g = g }) end
			end
		end
		return out
	end
	local nightEmpty, inHouseNight, breakfast, lunchEat, evening, lateLounge, seatClash, total = true, true, 0, 0, 0, 0, 0, 0
	for d = 500, 509 do
		if #visibleAt(SEED, N, d, sOf(3.0)) ~= 0 then nightEmpty = false end
		if GP.inHouse(SEED, N, d, sOf(3.0)) ~= N or GP.inHouse(SEED, N, d, sOf(23.5)) ~= N then inHouseNight = false end
		for _, v in visibleAt(SEED, N, d, sOf(8.9)) do if v.mode == "sit" and v.hint == "eat" then breakfast += 1 end end
		for _, v in visibleAt(SEED, N, d, sOf(13.0)) do if v.hint == "eat" then lunchEat += 1 end end
		for _, v in visibleAt(SEED, N, d, sOf(20.0)) do if v.mode == "sit" and v.hint == "relax" then evening += 1 end end
		for _, v in visibleAt(SEED, N, d, sOf(2.0)) do lateLounge += 1 end
		for h = 8, 23.9, 0.1 do
			local seen = {}
			for _, v in visibleAt(SEED, N, d, sOf(h)) do
				if v.mode == "sit" then
					total += 1
					local k = string.format("%.1f,%.1f,%.1f", v.cf.X, v.cf.Y, v.cf.Z)
					if seen[k] then seatClash += 1 end
					seen[k] = true
				end
			end
		end
	end
	check("night (03:00): nobody visible - all guests in their rooms", nightEmpty)
	check("in the house at night = N guests (one per room)", inHouseNight)
	check("breakfast at 08:54: guests eating in the breakfast room", breakfast >= 10, breakfast)
	check("no breakfast at 13:00", lunchEat == 0, lunchEat)
	check("evening (20:00): guests in the lobby / at the window bar", evening >= 10, evening)
	check("02:00: nobody in the lounge (gone to bed)", lateLounge == 0, lateLounge)
	check("never two guests on the same seat (10 days x 160 samples)", seatClash == 0 and total > 500, seatClash .. "/" .. total)
	-- turnovers: check-out with the suitcase in the morning, arrival with the suitcase in the afternoon
	local outs, ins, badOut, badIn, suitcaseWalks, plainWalks = 0, 0, 0, 0, 0, 0
	for d = 500, 529 do
		for g = 1, N do
			for _, a in GP.slotDay(SEED, g, d, N) do
				for _, s in a.segs do
					if s.pose == "checkout" then outs += 1; if s.t0 < sOf(10.0) or s.t0 > sOf(12.0) then badOut += 1 end end
					if s.pose == "checkin" then ins += 1; if s.t0 < sOf(13.5) or s.t0 > sOf(17.5) then badIn += 1 end end
					if s.kind == "walk" then if s.carry == "suitcase" then suitcaseWalks += 1 else plainWalks += 1 end end
				end
				if a.role == "leave" then
					local last = a.segs[#a.segs]
					check("leaving guest ends in the street with the suitcase (" .. a.id .. ")", last.kind == "walk" and last.carry == "suitcase"
						and (last.path[#last.path] - GP.HOTEL_GRAPH.p.street).Magnitude < 0.1)
				end
			end
		end
	end
	check("30 days: guests check out 10:00-12:00 at the desk", outs > 20 and badOut == 0, outs .. " / bad " .. badOut)
	check("30 days: new guests check in 13:30-17:30", ins == outs and badIn == 0, ins .. " / bad " .. badIn)
	check("suitcases only on arrival / departure walks", suitcaseWalks == outs * 2 + ins * 2 and plainWalks > suitcaseWalks, suitcaseWalks .. "/" .. plainWalks)
	-- rooms
	local rooms = {}
	for g = 1, N do rooms[GP.roomOf(SEED, g)] = true end
	local nr = 0; for _ in rooms do nr += 1 end
	check("every guest slot has its own room", nr == N)
	local endsAtDoor = true
	for g = 1, N do
		for _, a in GP.slotDay(SEED, g, 505, N) do
			local door = GP.HOTEL_ROOMS[GP.roomOf(SEED, g)].door
			for j, s in a.segs do
				local nxt = a.segs[j + 1]
				if s.kind == "walk" and (not nxt or nxt.t0 > s.t1 + 0.01) then
					local e = s.path[#s.path]
					if (e - door).Magnitude > 0.1 and (e - GP.HOTEL_GRAPH.p.street).Magnitude > 0.1 and not (GP.isHosted(g) and (e - GP.WORKSHOP.tail[1]).Magnitude < 0.1) then endsAtDoor = false end
				end
			end
		end
	end
	check("guests disappear only at their room door, the workshop door (hosted team) or in the street", endsAtDoor)
	-- determinism
	local function ser(list)
		local t = {}
		for _, a in list do for _, s in a.segs do table.insert(t, string.format("%s%.3f%.3f%s", s.kind, s.t0, s.t1, tostring(s.carry))) end end
		return table.concat(t, "|")
	end
	check("deterministic per plot + day", ser(GP.slotDay(SEED, 3, 600)) == ser(GP.slotDay(SEED, 3, 600)))
	local diffPlot, diffDay = 0, 0
	for g = 1, N do
		if ser(GP.slotDay(SEED, g, 600)) ~= ser(GP.slotDay(SEED + 1, g, 600)) then diffPlot += 1 end
		if ser(GP.slotDay(SEED, g, 600)) ~= ser(GP.slotDay(SEED, g, 601)) then diffDay += 1 end
	end
	check("another plot / another day: different plans", diffPlot >= 10 and diffDay >= 10, diffPlot .. "/" .. diffDay)

	------------------------------------------------------------------ guest count changes / hosted teams
	-- frames of the visible guests of slots 1..n at day-time t (key = slot:actor)
	local function framesAt(seed, n, d, sec)
		GP.clearPlans() -- from scratch for every guest count (the day-plan cache must not hide an n-dependence)
		local out = {}
		for g = 1, n do
			for _, a in GP.slotDay(seed, g, d, n) do
				local mode, cf = GP.sample(a, sec)
				if mode ~= "hidden" and cf then out[g .. ":" .. a.id] = cf.Position end
			end
		end
		return out
	end
	local moved, compared = 0, 0
	for _, seed in { 7, 8101, 99991, 31337, SEED } do
		for d = 700, 705 do
			for h = 8, 23.5, 0.25 do
				local a7, a9, a12 = framesAt(seed, 7, d, sOf(h)), framesAt(seed, 9, d, sOf(h)), framesAt(seed, 12, d, sOf(h))
				for k, p in a7 do
					compared += 1
					if not a9[k] or (a9[k] - p).Magnitude > 1e-6 or not a12[k] or (a12[k] - p).Magnitude > 1e-6 then moved += 1 end
				end
				-- and the other way round: a slot 1..7 figure visible with 9 / 12 guests is visible with 7 (nobody pops)
				for _, other in { a9, a12 } do
					for k in other do
						local g = tonumber(string.match(k, "^(%d+):"))
						if g and g <= 7 and not a7[k] then moved += 1 end
					end
				end
				-- slots 1..9 the same with 9 and 12 guests
				for k, p in a9 do
					if not a12[k] or (a12[k] - p).Magnitude > 1e-6 then moved += 1 end
				end
			end
		end
	end
	check("a slot's day does not depend on the guest count (7 / 9 / 12): nobody moves when a team checks in or out", moved == 0 and compared > 1000, moved .. "/" .. compared)
	check("hosted slots: above CompanyOps' ordinary occupancy (7), teams of 2", GP.BASE_GUESTS == 7 and GP.TEAM == 2 and not GP.isHosted(7) and GP.isHosted(8) and GP.isHosted(9))
	-- the hosted team's day
	local hb, hw, he, hBad, wsDoor = 0, 0, 0, 0, GP.WORKSHOP.tail[1]
	for d = 700, 709 do
		for g = 8, 9 do
			local acts = GP.slotDay(SEED, g, d)
			if #acts ~= 1 or acts[1].role ~= "hosted" then hBad += 1 end
			local a = acts[1]
			local m10 = GP.sample(a, sOf(12.0))
			if m10 == "hidden" then hw += 1 end
			for j, sg in a.segs do
				if sg.pose == "eat" and sg.t0 >= sOf(8.0) and sg.t0 <= sOf(9.0) then hb += 1 end
				if sg.kind == "walk" and (sg.path[#sg.path] - wsDoor).Magnitude < 0.1 then
					if sg.t1 < sOf(8.9) or sg.t1 > sOf(10.6) then hBad += 1 end
					local nxt = a.segs[j + 1]
					if not nxt or nxt.t0 < sOf(16.3) then hBad += 1 end
				end
				if sg.pose == "relax" and sg.t0 >= sOf(18.0) then he += 1 end
			end
		end
	end
	check("hosted team: breakfast together from 08:00, in the workshop room upstairs by 10:36 until ~16:30", hb == 20 and hw == 20 and hBad == 0, hb .. "/" .. hw .. "/" .. hBad)
	check("hosted team: in the lobby / at the window bar on most evenings", he >= 10, he)
	-- live arrival (GuestPlan.joinActors): from the street with the suitcase, check-in, room; later outings start at
	-- the room door or the street, never mid-building
	local street = GP.HOTEL_GRAPH.p.street
	local function doorOf(seed, g) return GP.HOTEL_ROOMS[GP.roomOf(seed, g)].door end
	local joinBad, joinN, startsBad, firstFrames = 0, 0, 0, 0
	for _, seed in { 7, SEED, 31337 } do
		for _, h in { 9.5, 12.0, 15.0, 19.0, 21.0 } do
			for g = 8, 9 do
				local acts = GP.joinActors(seed, g, 702, sOf(h), g - 7)
				joinN += 1
				local arr = acts[1]
				local s1, s2, s3 = arr.segs[1], arr.segs[2], arr.segs[3]
				if not (s1 and s1.kind == "walk" and s1.carry == "suitcase" and (s1.path[1] - street).Magnitude < 0.1 and math.abs(s1.t0 - (sOf(h) + (g - 8) * 2.5)) < 1e-6) then joinBad += 1 end
				if not (s2 and s2.pose == "checkin" and s3 and s3.kind == "walk" and (s3.path[#s3.path] - doorOf(seed, g)).Magnitude < 0.1) then joinBad += 1 end
				local mode, cf = GP.sample(arr, sOf(h) + (g - 8) * 2.5 + 0.01)
				if mode == "walk" and (cf.Position - street).Magnitude < 1 then firstFrames += 1 end
				for i = 2, #acts do
					local a = acts[i]
					local f = a.segs[1]
					if f.t0 < s3.t1 then startsBad += 1 end
					local p0 = if f.kind == "walk" then f.path[1] else f.at.Position
					if (p0 - doorOf(seed, g)).Magnitude > 0.1 and (p0 - street).Magnitude > 0.1 and (p0 - GP.WORKSHOP.tail[1]).Magnitude > 0.1 then startsBad += 1 end
				end
			end
		end
	end
	check("live arrival: comes in from the street with the suitcase (team 2.5 s apart), checks in, goes to the room", joinBad == 0 and firstFrames == joinN, joinBad .. " / first frames at the street " .. firstFrames .. "/" .. joinN)
	check("live arrival: the rest of the day starts after the arrival, at the room door / the street (no pop-in mid-building)", startsBad == 0, startsBad)
	-- live departure (GuestPlan.leaveActors): a visible guest keeps the current walk / visit (same actor id), then
	-- checks out with the suitcase; a guest in the room comes out; nobody vanishes in view
	local leaveBad, leaveN, vanish = 0, 0, 0
	for _, seed in { 7, SEED, 31337 } do
		for h = 8.0, 23.4, 0.35 do
			for g = 1, 9 do
				local d, sec = 703, sOf(h)
				local base = GP.slotDay(seed, g, d)
				local acts = GP.leaveActors(seed, g, d, sec)
				leaveN += 1
				-- whoever is visible at the change stays visible (same id, same frame)
				for _, a in base do
					local mode, cf = GP.sample(a, sec)
					if mode ~= "hidden" then
						local kept = false
						for _, b in acts do if b.id == a.id then local m2, c2 = GP.sample(b, sec); if m2 ~= "hidden" and (c2.Position - cf.Position).Magnitude < 1e-6 then kept = true end end end
						if not kept then leaveBad += 1 end
					end
				end
				-- every actor of the departure disappears only at a door or the street, the last walk ends in the street
				for _, a in acts do
					for j, sg in a.segs do
						local nxt = a.segs[j + 1]
						if sg.kind == "walk" and (not nxt or nxt.t0 > sg.t1 + 0.01) then
							local e = sg.path[#sg.path]
							if (e - doorOf(seed, g)).Magnitude > 0.1 and (e - street).Magnitude > 0.1 and (e - GP.WORKSHOP.tail[1]).Magnitude > 0.1 then vanish += 1 end
						end
					end
					if a.role == "leave" and string.find(a.id, "leave") then
						local last = a.segs[#a.segs]
						if not (last.kind == "walk" and last.carry == "suitcase" and (last.path[#last.path] - street).Magnitude < 0.1) or a.segs[1].t0 < sec then leaveBad += 1 end
					end
				end
			end
		end
	end
	check("live departure: the guests in view finish their walk (same actor), then check out with the suitcase into the street", leaveBad == 0 and leaveN > 300, leaveBad .. "/" .. leaveN)
	check("live departure: figures disappear only at a door or in the street", vanish == 0, vanish)

	------------------------------------------------------------------ walls (BuildingPlan rooms + doors)
	local walks = GP.hotelWalksForTests()
	check("hotel walks for the tests", #walks >= 80, #walks)
	for _, tier in { 2, 3, 4 } do
		local rooms = {}
		for _, r in Plan.rooms(tier) do if r.annex == "hotel" then table.insert(rooms, r) end end
		check("tier " .. tier .. ": the guest house has its rooms", #rooms >= 22, #rooms)
		local function roomAt(p)
			local lv = if p.Y > 12 then 1 else 0
			for _, r in rooms do
				if r.level == lv and p.X > r.x1 and p.X < r.x2 and p.Z > r.z1 and p.Z < r.z2 then return r end
			end
			return nil
		end
		local function throughDoor(r, c)
			if not r then return false end
			for _, dd in r.doors or {} do
				local plane, along
				if dd.face == "E" then plane, along = math.abs(c.X - r.x2), c.Z
				elseif dd.face == "W" then plane, along = math.abs(c.X - r.x1), c.Z
				elseif dd.face == "N" then plane, along = math.abs(c.Z - r.z2), c.X
				else plane, along = math.abs(c.Z - r.z1), c.X end
				if plane < 1.2 and math.abs(along - dd.at) <= dd.w / 2 - 0.25 then return true end
			end
			return false
		end
		local bad, crossings = {}, 0
		for _, w in walks do
			local prevRoom, prevP = nil, nil
			local started = false
			for i = 2, #w.path do
				local a, b = w.path[i - 1], w.path[i]
				local n = math.max(1, math.ceil((b - a).Magnitude / 0.25))
				for k = 0, n do
					local p = a:Lerp(b, k / n)
					local r = roomAt(p)
					local inside = Plan.inHotel(p)
					if not started then started = true; prevRoom = r; prevP = p
					elseif r ~= nil or not inside then
						local cur = if inside then r else nil
						if cur ~= prevRoom then
							crossings += 1
							local c = (p + prevP) / 2
							local stair = cur and prevRoom and string.find(cur.id, "STAIR") and string.find(prevRoom.id, "STAIR")
							if not stair and not throughDoor(cur, c) and not throughDoor(prevRoom, c) then
								table.insert(bad, w.name .. " " .. tostring(prevRoom and prevRoom.id) .. "->" .. tostring(cur and cur.id) .. " at " .. tostring(c))
							end
							prevRoom = cur
						end
						prevP = p
					end
				end
			end
		end
		check("tier " .. tier .. ": every walk crosses room boundaries only through doors (" .. crossings .. " crossings)", #bad == 0 and crossings > 100, bad[1])
	end
	-- nodes on their floors (level 0 at 0.15, level 1 at 16.15, stair nodes on the flights)
	local bad = 0
	for name, p in GP.HOTEL_GRAPH.p do
		if not string.find(name, "^st") and not (math.abs(p.Y - 0.15) < 0.01 or math.abs(p.Y - 16.15) < 0.01) then bad += 1 end
		if (name == "street" or name == "path" or name == "doorOut") and Plan.inHotel(p) then bad += 1 end
		if string.find(name, "^c[01]_") and not Plan.inHotel(p) then bad += 1 end
	end
	check("graph nodes on the floors, corridor nodes inside the house, the street outside", bad == 0, bad)

	------------------------------------------------------------------ terminals
	local I = FP.interval()
	local outLeg, backLeg = FP.leg("out"), FP.leg("back")
	local early, late, nDep, seatDup, lateArr, earlyArr, pmLate, pmEarly, sitting = 0, 0, 0, 0, 0, 0, 0, 0, 0
	for k = 20, 25 do
		local B0 = FP.legStart("out", k) + outLeg.phases.boarding.t0
		local B1 = FP.legStart("out", k) + outLeg.phases.boarding.t1
		local seen = {}
		local deps = GP.homeDepartures(k)
		nDep += #deps
		for _, a in deps do
			local last = a.segs[#a.segs]
			if last.t1 > B1 + 0.01 then late += 1 end
			for _, s in a.segs do
				if s.kind == "walk" and s.path[#s.path].Z > 2527 and s.t0 < B0 - 0.01 then early += 1 end -- the jet-bridge walk
				if s.kind == "sit" then
					sitting += 1
					local key = tostring(s.at.Position)
					if seen[key] then seatDup += 1 end
					seen[key] = true
				end
			end
		end
		local D0 = FP.legStart("back", k) + backLeg.phases.deboarding.t0
		for _, a in GP.homeArrivals(k) do
			if a.segs[1].t0 < D0 then earlyArr += 1 end
			local last = a.segs[#a.segs]
			if (last.path[#last.path] - GP.HOME_GRAPH.p.doorArr).Magnitude > 0.1 or last.carry ~= "trolley" then lateArr += 1 end
		end
		local PB0 = FP.legStart("back", k) + backLeg.phases.boarding.t0
		local PB1 = FP.legStart("back", k) + backLeg.phases.boarding.t1
		for _, a in GP.pmDepartures(k) do
			local last = a.segs[#a.segs]
			if last.t1 > PB1 + 0.01 then pmLate += 1 end
			if last.t0 < PB0 then pmEarly += 1 end
		end
		local PD0 = FP.legStart("out", k) + outLeg.phases.deboarding.t0
		for _, a in GP.pmArrivals(k) do if a.segs[1].t0 < PD0 then pmEarly += 1 end end
	end
	check("City Airport: 14 departing passengers per out leg", nDep == 6 * GP.HOME_DEPARTURES)
	check("nobody walks to the jet bridge before boarding opens (FlightPlan boarding phase)", early == 0, early)
	check("everybody has boarded before the doors close", late == 0, late)
	check("departing passengers wait on gate A1 seats, no seat used twice in a cycle", sitting >= 6 * 10 and seatDup == 0, sitting .. " / dup " .. seatDup)
	check("arrivals appear after the shuttle's deboarding starts and leave by the arrivals door with a trolley", earlyArr == 0 and lateArr == 0, earlyArr .. "/" .. lateArr)
	check("Port Meridian: departures up the airstair inside the boarding window, arrivals after the deboarding", pmLate == 0 and pmEarly == 0, pmLate .. "/" .. pmEarly)
	local maxHome, maxPm, boardingVisible = 0, 0, 0
	local base = FP.legStart("out", 30)
	for t = base, base + I, 3 do
		local nh, np = 0, 0
		for _, a in GP.terminalActors("home", t) do if GP.sample(a, t) ~= "hidden" then nh += 1 end end
		for _, a in GP.terminalActors("pm", t) do if GP.sample(a, t) ~= "hidden" then np += 1 end end
		maxHome = math.max(maxHome, nh); maxPm = math.max(maxPm, np)
	end
	for _, a in GP.terminalActors("home", base + 20) do if GP.sample(a, base + 20) ~= "hidden" then boardingVisible += 1 end end
	check("City Airport: <= 40 passengers at any time (cap)", maxHome <= 40 and maxHome >= 8, maxHome)
	check("Port Meridian: <= 40 passengers at any time (cap)", maxPm <= 40 and maxPm >= 5, maxPm)
	check("City Airport during boarding: passengers at the gate", boardingVisible >= 6, boardingVisible)
	check("terminal regions: City Airport hall and Port Meridian hall + apron", GP.terminalAt(Vector3.new(0, 30, 2480)) == "home" and GP.terminalAt(Vector3.new(0, 30, 7650)) == "pm"
		and GP.terminalAt(Vector3.new(230, 30, 7680)) == "pm" and GP.terminalAt(Vector3.new(0, 30, 0)) == nil and GP.terminalAt(Vector3.new(0, 120, 2480)) == nil)

	------------------------------------------------------------------ client
	local T = 1.7e9
	local function patch(cls, name, fn) M.IMPL[cls].methods[name] = fn; local ci = M.classInfo(cls); if ci.methods then ci.methods[name] = fn end end
	patch("Workspace", "GetServerTimeNow", function() return T end)
	local bulkCalls = 0
	patch("Workspace", "BulkMoveTo", function(self, parts, cframes) bulkCalls += 1; for i, p in parts do p.CFrame = cframes[i] end end)
	local Client = game.StarterPlayer.StarterPlayerScripts.Client
	local GC = M.require(Client.Controllers.GuestController)
	local plots = Instance.new("Folder"); plots.Name = "Plots"; plots.Parent = game.Workspace
	local plot = Instance.new("Model"); plot.Name = "Plot_01"; plot.Parent = plots
	local office = Instance.new("Model"); office.Name = "Office"
	local CF = CFrame.new(300, 24, -200) * CFrame.Angles(0, math.rad(90), 0)
	office:SetAttribute("CampusCFrame", CF); office:SetAttribute("OfficeTier", 3); office:SetAttribute("HotelRooms", 12); office:SetAttribute("HotelGuests", 7)
	office:SetAttribute("OwnerUserId", 4242)
	office.Parent = plot
	local camera = game.Workspace.CurrentCamera
	local cam = (CF * CFrame.new(-90, 20, 120)).Position
	local d0 = math.floor(T / Ops.DAY) + 3
	local function at(h) T = d0 * Ops.DAY + sOf(h) end
	local function run(h, steps)
		at(h)
		for _ = 1, steps or 2 do GC.update(cam, 0.6, T) end
	end
	run(8.9)
	local st = GC.stats()
	check("client: the plot's guest house found", st.plots == 1 and GC.plots()[1].n == 7 and GC.plots()[1].seed == 4242)
	local expect = #visibleAt(4242, 7, d0, sOf(8.9))
	check("client: one figure per visible guest (08:54)", st.guests == expect and expect > 0, st.guests .. " vs " .. expect)
	local f = GC.folder()
	check("client: figures parented under workspace.GuestLife", f ~= nil and f.Parent == game.Workspace and #f:GetChildren() == expect)
	-- world = CampusCFrame * local
	local okPos, n = true, 0
	for key, a in GC.active() do
		if a.fig then
			n += 1
			local mode, cf = GP.sample(a.actor, GC.dayTime(T))
			if (a.fig.pos - (CF * cf).Position).Magnitude > 0.01 then okPos = false end
			local torso = a.fig.parts[1]
			if mode == "walk" and (torso.Position - (CF * cf).Position).Magnitude > 3.5 then okPos = false end
		end
	end
	check("client: positions = CampusCFrame * GuestPlan local frame", okPos and n > 0)
	local b0 = bulkCalls
	GC.update(cam, 0.6, T)
	check("client: one BulkMoveTo per step", bulkCalls == b0 + 1)
	-- the afternoon: arrivals with suitcases
	local suit = false
	for h = 13.5, 17.5, 0.05 do
		at(h); GC.update(cam, 0.6, T)
		for _, a in GC.active() do if a.fig and a.fig.carry == "suitcase" and a.fig.case[1].Parent == a.fig.model then suit = true end end
		if suit then break end
	end
	check("client: an arriving / leaving guest pulls a suitcase (luggage parts parented)", suit)
	run(3.0)
	check("client: night - nobody visible", GC.stats().guests == 0 and #GC.folder():GetChildren() == 0)
	office:SetAttribute("HotelGuests", 15); run(8.9)
	check("client: 15 guests -> 12 (one per room)", GC.plots()[1].n == 12)
	office:SetAttribute("HotelGuests", 0); run(8.9)
	check("client: 0 guests -> no plot, nothing shown", GC.stats().plots == 0 and GC.stats().guests == 0)
	office:SetAttribute("HotelGuests", 7)
	office:SetAttribute("OfficeTier", 1); run(8.9)
	check("client: no guest house below Plan.HOTEL_MIN_TIER", GC.stats().plots == 0)
	office:SetAttribute("OfficeTier", 3); run(8.9)
	cam = Vector3.new(0, 30, -3000); GC.update(cam, 0.6, T)
	check("client: far away -> everything unparented, no active figures", GC.folder().Parent == nil and next(GC.active()) == nil)
	-- a hosted client team checks in (7 -> 9) and out (9 -> 7) in the evening while the camera watches the lobby
	office:SetAttribute("HotelGuests", 7)
	cam = (CF * CFrame.new(-90, 20, 120)).Position
	local seed = 4242
	local dT = d0 + 2
	T = dT * Ops.DAY + sOf(18.9)
	for _ = 1, 3 do GC.update(cam, 0.6, T) end
	local function figs()
		local out = {}
		for key, a in GC.active() do if a.fig then out[key] = a.fig.pos end end
		return out
	end
	local streetW = (CF * GP.HOTEL_GRAPH.p.street)
	local function nearDoorOrStreet(p)
		if (p - streetW).Magnitude < 2 then return true end
		for _, r in GP.HOTEL_ROOMS do if (p - CF * r.door).Magnitude < 2 then return true end end
		return (p - CF * GP.WORKSHOP.tail[1]).Magnitude < 2
	end
	local jumps, popIns, vanished, frames, seenNew = 0, 0, 0, 0, 0
	local prev = figs()
	local function stepWatch(dt)
		T += dt
		GC.update(cam, dt, T)
		local cur = figs()
		frames += 1
		for k, p in cur do
			local q = prev[k]
			if q then
				if (p - q).Magnitude > GP.GUEST_SPEED * dt + 0.6 then jumps += 1 end
			elseif not nearDoorOrStreet(p) then popIns += 1
			else seenNew += 1 end
		end
		for k, q in prev do if not cur[k] and not nearDoorOrStreet(q) then vanished += 1 end end
		prev = cur
	end
	for _ = 1, 20 do stepWatch(0.5) end
	office:SetAttribute("HotelGuests", 9)
	for _ = 1, 160 do stepWatch(0.5) end
	local teamIn = 0
	for key in GC.active() do if string.find(key, ":g[89]:") then teamIn += 1 end end
	office:SetAttribute("HotelGuests", 7)
	for _ = 1, 200 do stepWatch(0.5) end
	check("client: team check-in 7 -> 9 and check-out 9 -> 7 in the evening: no figure jumps (" .. frames .. " frames)", jumps == 0, jumps)
	check("client: new figures appear only at the street / a door, none vanishes in view", popIns == 0 and vanished == 0 and seenNew >= 2, popIns .. "/" .. vanished .. "/" .. seenNew)
	check("client: the team's actors are active after the check-in", teamIn >= 2, teamIn)
	office:SetAttribute("HotelGuests", 7)
	-- terminal
	local B0 = FP.legStart("out", math.floor((T - FP.CONFIG.epoch) / I) + 1) + outLeg.phases.boarding.t0
	T = B0 + 20
	cam = Vector3.new(-170, 32, 2505)
	GC.update(cam, 0.6, T); GC.update(cam, 0.6, T)
	st = GC.stats()
	check("client: City Airport terminal active during boarding", st.terminal == "home" and st.passengers >= 6 and st.passengers <= 40, st.terminal .. " " .. st.passengers)
	local bags = 0
	for _, a in GC.active() do if a.fig and (a.fig.carry == "bag" or a.fig.carry == "suitcase") then bags += 1 end end
	check("client: passengers carry luggage", bags >= 4, bags)
	cam = Vector3.new(60, 32, 7655)
	local PB0 = FP.legStart("back", math.floor((T - FP.CONFIG.epoch) / I)) + backLeg.phases.boarding.t0
	T = PB0 - 5
	GC.update(cam, 0.6, T); GC.update(cam, 0.6, T)
	st = GC.stats()
	check("client: Port Meridian terminal passengers", st.terminal == "pm" and st.passengers >= 4 and st.passengers <= 40, st.terminal .. " " .. st.passengers)
	check("client: figure pool stays small (<= 64)", #GC.pool() <= 64, #GC.pool())
	local parts = 0
	for _, fig in GC.pool() do for _, p in fig.model:GetChildren() do if p:IsA("BasePart") then parts += 1 end end end
	check("client: <= 18 parts per figure", parts <= #GC.pool() * 18, parts)
end

local ok, err = xpcall(body, debug.traceback)
if not ok then failc += 1; print("ERROR " .. tostring(err)) end
print(string.format("guests_jet_guests: %d passed, %d failed", pass, failc))
if failc > 0 then error(string.format("%d checks failed", failc), 0) end
