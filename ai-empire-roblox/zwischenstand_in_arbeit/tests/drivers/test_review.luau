--!nocheck
-- drivers package, review round 1: the reviewer's adversarial server scenarios (agents/review_drivers/sb2/tests/drivers/
-- rv_service.luau, R1-R8, adapted to the intended fixes) + one check per functional issue of the review:
--   1/2 limousine door delay (car stays drawn / "let me out" leaves no ghost: the stand car simply stays idle),
--   3 one booking per bay (second booking waits for the next car, honest ETA, no two cars at one pose), the limousine
--     fleet (garage in the east tunnel, LIMO_FLEET at once, FIFO queue), pm_limo is a pick-up only,
--   4 the limousine from the shuttle arrival point, zone-specific TOO_FAR text,
--   5 honest sheet without a pick-up point (no ETAs, "Walk to ... first (N studs)"),
--   6 a ride in one city never blocks the other (auto-cancel with a notice),
--   7 a trip ending mid-travel never shows the rep in two cars (same car turns round / deferred back ride),
--   8 field rides only with a free company driver (request 22), back ride retried, else data,
--   9 the leg cache keeps a full server's HQ legs (no clear-all thrash),
--  11 per-action rate limits, 12 queued bookings follow the founder / dropped with a notice,
--  13 a founder leaving mid-ride: the car finishes its leg in a detached folder, 14 "let me out" avoids props,
--   working hours (request 2): night walk + honest ETA.
-- Run: cd tests/drivers && ../../tools/luau test_review.luau -a .gen_drivers
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_drivers")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
for path, src in require("../world/stubs") do sources[path] = src end
M.loadTree(manifest, sources)
M.quiet = true
local G = M.G
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end
local function info(s) print("INFO  " .. s) end

local makeFixture = require("../world/fixture")
local function body()
	local Instance, Vector3, CFrame = G.Instance, G.Vector3, G.CFrame
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local S = Server.Services
	local F = makeFixture(M, G)
	local Remote = M.require(Server.Lib.Remote)
	local Session = M.require(S.SessionService)
	local CityPlan = M.require(RS.Shared.Config.CityPlan)
	local Drive = M.require(RS.Shared.DrivePlan)
	local Ops = M.require(RS.Shared.CompanyOps)
	-- daytime start (08:00 company time); the night checks set the clock themselves
	local T = 1.7e9 - (1.7e9 % 1200) + 1200 + 5
	M.IMPL.Workspace.methods.GetServerTimeNow = function() return T end
	if M.classInfo("Workspace").methods then M.classInfo("Workspace").methods.GetServerTimeNow = function() return T end end
	local blockers = {} -- GetPartBoundsInBox stub: a prop at these points
	M.IMPL.Workspace.methods.GetPartBoundsInBox = function(_, cf, size)
		for _, b in blockers do if (cf.Position - b).Magnitude < 1 then return { M.game.Workspace } end end
		return {}
	end
	if M.classInfo("Workspace").methods then M.classInfo("Workspace").methods.GetPartBoundsInBox = M.IMPL.Workspace.methods.GetPartBoundsInBox end
	local Design = M.require(S.HeadquartersDesign)
	Design.build = function(cf, session, accent)
		local m = Instance.new("Model"); m.Name = "Office"
		m:SetAttribute("OfficeTier", Design.tierFor(session)); m:SetAttribute("OwnerUserId", session.userId)
		local door = Instance.new("Model"); door.Name = "Door_SITE_BARRIER"; door:SetAttribute("DoorId", "SITE_BARRIER"); door.Parent = m
		return m
	end
	Design.staff = function() end
	local Doors = M.require(S.DoorService)
	Doors.register = function() end; Doors.unregister = function() end
	Doors.find = function(office, id) return office:FindFirstChild("Door_" .. id) end
	Doors.requestNPC = function() return true end
	local Lift = M.require(S.LiftService); Lift.attach = function() end; Lift.detach = function() end
	local Plot = M.require(S.PlotService)
	local City = M.require(S.CityService)
	local Driver = M.require(S.DriverService)
	Plot.init()
	Driver.init()
	local LIMITS = { write = table.clone(Driver.LIMITS.write), read = table.clone(Driver.LIMITS.read), other = table.clone(Driver.LIMITS.other) }
	local root = RS:FindFirstChild("CompanyDrivers")
	local act = Remote.binds.TripAction
	local warns = 0
	local origWarn = G.warn
	G.warn = function(...) warns += 1; print("WARN", ...) end

	local function advance(seconds, step)
		step = step or 0.25
		local left = seconds
		while left > 1e-9 do
			local d = math.min(step, left)
			T += d
			Driver.tick(d)
			left -= d
		end
	end
	local function newPlayer(id, name, stage, cf)
		local p = F.player(id, name, cf or CFrame.new(0, 27.5, 0))
		local s = F.session(p, 500000)
		s.data.empire.office = stage
		table.insert(Session.sessions, s)
		for _, fn in Session.loaded do fn(s) end
		return p, s
	end
	local function close(p, s)
		p.Parent = nil
		s.closed = true
		for _, fn in Session.closing do fn(s) end
		local i = table.find(Session.sessions, s)
		if i then table.remove(Session.sessions, i) end
	end
	local function notices(p)
		local out = {}
		for _, f in Remote.fired do
			if f.player == p and f.name == "Notify" and f.args[1] == "CAMPUS_NOTICE" then table.insert(out, f.args[2].text) end
		end
		return out
	end
	local function lastNotice(p) local n = notices(p); return n[#n] or "" end
	local function sheets(p)
		local out = {}
		for _, f in Remote.fired do if f.player == p and f.name == "Notify" and f.args[1] == "DRIVE_SHEET" then table.insert(out, f.args[2]) end end
		return out
	end
	local function hqPoint(p, l) return Plot.get(p).cframe:PointToWorldSpace(l) end
	local function standAt(p, pos) p.root.CFrame = CFrame.new(pos) end
	local function rides(folder)
		local out = {}
		if not folder then return out end
		for _, ch in folder:GetChildren() do if ch:IsA("Folder") and string.match(ch.Name, "^Ride_%d+$") then table.insert(out, ch) end end
		return out
	end
	local function promptsOf(uid)
		local n = 0
		for _, ch in game.Workspace.DrivePrompts:GetChildren() do if ch.Name == "DrivePrompt_" .. uid then n += 1 end end
		return n
	end
	local function abroad(p) City.trips[p.UserId] = { player = p, state = "abroad", to = "abroad", releaseAt = math.huge } end
	local function home(p) City.trips[p.UserId] = nil end
	local stand = Drive.place("pm_limo")
	local function limoBy(id)
		for _, f in root.Limo:GetChildren() do if f:GetAttribute("Id") == id then return f end end
		return nil
	end
	local function settleLimos() advance(400, 0.5); check("limousines all back (garage) and the stand idle", #root.Limo:GetChildren() == 0 and root.Limo:GetAttribute("Stand") == "idle", #root.Limo:GetChildren()) end
	for k in LIMITS do Driver.LIMITS[k] = { 1e6, 1e6 } end

	------------------------------------------------------------------ R1 spam the remote (request/cancel/board/status/places)
	do
		local p, s = newPlayer(8101, "Spam", 2)
		M.settle(1); advance(1.1)
		local folder = root:FindFirstChild("Drivers_8101")
		standAt(p, hqPoint(p, Vector3.new(0, 3, -60)))
		local ops = { "request", "cancel", "board", "status", "places", "request", "cancel" }
		local errs, maxRides, maxPrompts, maxDriverRides = 0, 0, 0, 0
		local okReq = 0
		for i = 1, 400 do
			local op = ops[(i % #ops) + 1]
			local ok, res = pcall(act, s, { action = "ride", op = op, to = if i % 3 == 0 then "clouddesk" else "airport_departures" })
			if not ok then errs += 1; print("  remote error: " .. tostring(res)) elseif op == "request" and res.ok then okReq += 1 end
			if i % 37 == 0 then
				local r = rides(folder)[1]
				if r and r:GetAttribute("State") == "waiting" then
					standAt(p, Drive.endCF(Drive.leg("hq_garage", "hq_entrance", Plot.get(p).index)) * Vector3.new(5, 3, 2))
				end
			end
			advance(0.3, 0.1)
			local list = rides(folder)
			local withDriver = 0
			for _, r in list do if (r:GetAttribute("Driver") or 0) > 0 then withDriver += 1 end end
			maxRides = math.max(maxRides, #list)
			maxDriverRides = math.max(maxDriverRides, withDriver)
			maxPrompts = math.max(maxPrompts, promptsOf(8101))
			if p.root.Anchored and not p:GetAttribute("DriveRide") then errs += 1 end
		end
		info("R1 spam: " .. okReq .. " accepted requests")
		check("R1 spam: no remote error / no stuck hold", errs == 0, errs)
		check("R1 spam: rides with a driver <= drivers (1)", maxDriverRides <= 1, maxDriverRides)
		check("R1 spam: at most one Get-in prompt", maxPrompts <= 1, maxPrompts)
		check("R1 spam: at most one ride folder at once", maxRides <= 1, maxRides)
		advance(400)
		check("R1 spam: everything cleaned up afterwards", #rides(folder) == 0 and promptsOf(8101) == 0 and not p.root.Anchored, #rides(folder))
		close(p, s); advance(1.1)
	end

	------------------------------------------------------------------ R2 stage 5: two drivers, field rides + founder + queue
	do
		local p, s = newPlayer(8201, "Five", 5)
		M.settle(1); advance(1.1)
		local folder = root:FindFirstChild("Drivers_8201")
		check("R2 stage 5: 2 drivers", folder:GetAttribute("Drivers") == 2, folder:GetAttribute("Drivers"))
		local e = s.data.empire
		e.employees.marketer = 4
		e.staffProfiles = { marketer = { { n = "Rep One", s = 1 }, { n = "Rep Two", s = 2 }, { n = "Rep Three", s = 3 } } }
		e.deals.tripList = {}
		advance(1.1)
		table.insert(e.deals.tripList, { client = "helix", kind = "sign", back = e.seconds + 2400, founder = false, hosted = false, crew = 1, left = e.seconds })
		table.insert(e.deals.tripList, { client = "frontier", kind = "sign", back = e.seconds + 2400, founder = false, hosted = false, crew = 1, left = e.seconds + 0.5 })
		advance(1.1)
		local drivers = {}
		for _, r in rides(folder) do drivers[#drivers + 1] = r:GetAttribute("Driver") end
		check("R2 two trips: both drivers take a field rep", #drivers == 2, table.concat(drivers, ","))
		-- a third trip while both drivers are out and nothing is queued: it stays data (no self-driving rep, no car
		-- without a company driver)
		table.insert(e.deals.tripList, { client = "nova", kind = "sign", back = e.seconds + 2400, founder = false, hosted = false, crew = 1, left = e.seconds + 1 })
		advance(1.1)
		local driverless = 0
		for _, r in rides(folder) do if (r:GetAttribute("Driver") or 0) == 0 then driverless += 1 end end
		check("R2 third trip with every driver busy: stays data (request 22: drivers take the reps)", #rides(folder) == 2 and driverless == 0, #rides(folder) .. "/" .. driverless)
		standAt(p, hqPoint(p, Vector3.new(0, 3, -60)))
		T += 5
		local q = Driver.request(p, { to = "airport_departures" })
		check("R2 both drivers out: founder queued", q.ok and q.queued, q.err)
		-- a fourth trip while everything is busy and a booking is queued: data as well
		table.insert(e.deals.tripList, { client = "science", kind = "sign", back = e.seconds + 2400, founder = false, hosted = false, crew = 1, left = e.seconds + 2 })
		advance(1.1)
		check("R2 fourth trip with a founder booking queued: stays data", #rides(folder) == 2, #rides(folder))
		local maxD = 0
		for _ = 1, 400 do
			advance(1, 0.25)
			local n = 0
			local used = {}
			for _, r in rides(folder) do
				local d = r:GetAttribute("Driver") or 0
				if d > 0 then n += 1; if used[d] then n += 100 end; used[d] = true end
				if d == 0 then n += 1000 end
			end
			maxD = math.max(maxD, n)
		end
		check("R2 never more busy drivers than paid, never one driver twice, never a car without a company driver", maxD <= 2, maxD)
		close(p, s); advance(1.1)
	end

	------------------------------------------------------------------ R3 trip ends mid-travel: the rep in one car only
	local function repCars(folder, plotI, name)
		local visible = 0
		for _, r in rides(folder) do
			local segs = Drive.decode(r:GetAttribute("Plan"), plotI)
			local pose = segs and Drive.pose(segs, plotI, T)
			if pose and pose.phase ~= "done" and r:FindFirstChild("C1") and r.C1:GetAttribute("CompanionName") == name then
				-- in the car = on the current leg's seats (or standing at a door between two legs)
				if string.find(pose.who, "C1", 1, true) or pose.phase == "waiting" then visible += 1 end
			end
		end
		return visible
	end
	do
		local p, s = newPlayer(8301, "Mid", 2)
		M.settle(1); advance(1.1)
		local folder = root:FindFirstChild("Drivers_8301")
		local plotI = Plot.get(p).index
		local e = s.data.empire
		e.employees.marketer = 1
		e.staffProfiles = { marketer = { { n = "Kai Lund", s = 4444 } } }
		e.deals.tripList = {}
		advance(1.1)
		-- (a) the reviewer's timing: the trip is over before the rep got in -> the car goes back without him
		table.insert(e.deals.tripList, { client = "helpdesk", kind = "renew", back = e.seconds + 4, founder = false, hosted = false, crew = 1, left = e.seconds })
		advance(1.1)
		advance(Drive.walkAt(T) + 4)
		table.remove(e.deals.tripList, 1)
		advance(1.1)
		local worst = 0
		for _ = 1, 120 do advance(1); worst = math.max(worst, repCars(folder, plotI, "Kai Lund")) end
		check("R3a trip over before boarding: the rep never shows in two cars", worst <= 1, worst)
		advance(200)
		-- (b) a hosted visit ends while the chauffeur is still bringing the client team in: the back ride waits until they
		-- got out at the HQ (no guest in two places)
		table.insert(e.deals.tripList, { client = "ledger", kind = "sign", back = e.seconds + 1200, founder = false, hosted = true, crew = 0, left = e.seconds + 7 })
		advance(1.1)
		local fetchRide = rides(folder)[1]
		local fsegs = fetchRide and Drive.decode(fetchRide:GetAttribute("Plan"), plotI)
		check("R3b guests fetched by the company driver", fsegs and fsegs[2].to == "hq_entrance" and fsegs[2].who == "D,G1,G2")
		if fsegs then advance(fsegs[2].t0 + 3 - T) end
		table.remove(e.deals.tripList, 1)
		local maxGuestCars = 0
		for _ = 1, 400 do
			advance(1)
			local n = 0
			for _, r in rides(folder) do
				local segs = Drive.decode(r:GetAttribute("Plan"), plotI)
				local pose = segs and Drive.pose(segs, plotI, T)
				if pose and pose.phase ~= "done" and (string.find(pose.who, "G1", 1, true) or (pose.phase == "waiting" and r:FindFirstChild("G1"))) then n += 1 end
			end
			maxGuestCars = math.max(maxGuestCars, n)
		end
		check("R3b hosted visit over during the fetch: the guests are never in two cars / places at once", maxGuestCars <= 1, maxGuestCars)
		close(p, s); advance(1.1)
	end

	------------------------------------------------------------------ R4 home car coming, founder flies abroad, calls the limo
	do
		local p, s = newPlayer(8401, "Fly", 4)
		M.settle(1); advance(1.1)
		standAt(p, hqPoint(p, Vector3.new(0, 3, -60)))
		T += 5
		local r = Driver.request(p, { to = "airport_departures" })
		check("R4 home ride booked", r.ok, r.err)
		City.trips[8401] = { player = p, state = "flying", to = "abroad", releaseAt = math.huge }
		advance(1)
		local folder = root:FindFirstChild("Drivers_8401")
		local homeRide = rides(folder)[1]
		check("R4 in flight: the home booking is void (car turns back / gone) + notice", (homeRide == nil or homeRide:GetAttribute("State") == "returning")
			and string.find(lastNotice(p), "cancelled", 1, true) ~= nil and p:GetAttribute("DriveRide") == nil, lastNotice(p))
		local before = #notices(p)
		advance(120)
		local waitingNotes = 0
		for i = before + 1, #notices(p) do if string.find(notices(p)[i], "waiting for you", 1, true) then waitingNotes += 1 end end
		check("R4 no 'waiting for you' notices during the flight", waitingNotes == 0, waitingNotes)
		abroad(p)
		standAt(p, stand.door.Position)
		T += 5
		local l = Driver.request(p, { to = "pm_hotel" })
		check("R4 abroad: limousine bookable", l.ok, l.err)
		local st = Driver.status(p)
		check("R4 status abroad shows the limousine ride", st.state == "waiting" and st.to == "pm_hotel", tostring(st.state) .. " " .. tostring(st.to))
		local hook = Driver.phoneHook(s, {})
		check("R4 phone abroad talks about the limousine", string.find(hook.text, "limousine", 1, true) ~= nil and string.find(hook.text, "HQ", 1, true) == nil, hook.text)
		Driver.cancel(l.rideId)
		home(p)
		close(p, s); advance(1.1)
		settleLimos()
	end

	------------------------------------------------------------------ R5 two founders at the VIP stand at once (issue 3)
	do
		local a, sa = newPlayer(8501, "Ann", 4)
		local b, sb = newPlayer(8502, "Bob", 4)
		M.settle(1); advance(1.1)
		abroad(a); abroad(b)
		standAt(a, stand.door.Position); standAt(b, stand.door.Position + Vector3.new(3, 0, 0))
		T += 5
		local ra = Driver.request(a, { to = "pm_hotel" })
		local rb = Driver.request(b, { to = "pm_helixresearch" })
		check("R5 Ann gets the limousine at bay 1 at once", ra.ok and not ra.queued and ra.eta == 0, ra.err)
		check("R5 Bob's booking waits for the next car (honest ETA > 0)", rb.ok and rb.queued and rb.eta > 0, tostring(rb.err) .. " " .. tostring(rb.eta))
		local waitingAtBay = 0
		for _, f in root.Limo:GetChildren() do if f:GetAttribute("State") == "waiting" and f:GetAttribute("Pickup") == "pm_limo" then waitingAtBay += 1 end end
		check("R5 only one limousine waits at bay 1, one Get-in prompt there", waitingAtBay == 1 and promptsOf(8501) == 1 and promptsOf(8502) == 0, waitingAtBay)
		check("R5 Bob's HUD shows the booking", typeof(b:GetAttribute("DriveQueue")) == "number" and b:GetAttribute("DriveQueueTo") ~= nil)
		check("R5 Bob's status: queued", Driver.status(b).state == "queued")
		-- Ann gets in and leaves; the next limousine moves up from the garage and is Bob's
		standAt(a, stand.stop * Vector3.new(5, 3, 4))
		check("R5 Ann boards", act(sa, { action = "ride", op = "board" }).ok)
		local bobRide, gap = nil, math.huge
		local bobEta = T + rb.eta
		local bobWaitAt = nil
		for _ = 1, 400 do
			advance(0.25)
			local poses = {}
			for _, f in root.Limo:GetChildren() do
				local segs = Drive.decode(f:GetAttribute("Plan"))
				local pose = segs and (#segs > 0 and Drive.pose(segs, nil, T, Drive.WHEELBASE.limo) or (f:GetAttribute("State") == "waiting" and { cf = stand.stop, phase = "waiting" }))
				if pose and pose.phase ~= "done" then table.insert(poses, pose.cf.Position) end
				if f:GetAttribute("Rider") == 8502 then bobRide = f end
			end
			for i = 1, #poses do for j = i + 1, #poses do gap = math.min(gap, (poses[i] - poses[j]).Magnitude) end end
			if bobRide and bobRide:GetAttribute("State") == "waiting" and not bobWaitAt then bobWaitAt = T end
			if bobWaitAt then break end
		end
		check("R5 Bob's limousine comes to bay 1 after Ann's left", bobRide ~= nil and bobWaitAt ~= nil and bobRide:GetAttribute("Pickup") == "pm_limo")
		check("R5 Bob's car arrives no later than the ETA said", bobWaitAt and bobWaitAt <= bobEta + 1, bobWaitAt and string.format("%.1f vs %.1f", bobWaitAt, bobEta))
		check("R5 two limousines never closer than a car length", gap > Drive.CAR_LENGTH.limo, string.format("%.2f", gap))
		Driver.cancel(Driver.status(b).rideId)
		settleLimos()
		-- the stand car: board, then "let me out" within the 2 s door delay -> he stands at the kerb, the car stays idle
		standAt(a, stand.door.Position)
		T += 5
		local r2 = Driver.request(a, { to = "pm_hotel" })
		standAt(a, stand.stop * Vector3.new(5, 3, 4))
		check("R5 board at the stand", act(sa, { action = "ride", op = "board" }).ok)
		advance(0.5, 0.25)
		local okc = Driver.cancel(r2.rideId)
		check("R5 cancel during the door delay: founder out at the kerb, released", okc and not a.root.Anchored and not CityPlan.onRoad(a.root.Position, 0) and a:GetAttribute("DriveRide") == nil)
		check("R5 ... the limousine never left: no ride folder (no ghost on the back seat), the stand is idle again", limoBy(r2.rideId) == nil and root.Limo:GetAttribute("Stand") == "idle")
		-- respawn during the door delay
		T += 5
		local r3 = Driver.request(a, { to = "pm_hotel" })
		standAt(a, stand.stop * Vector3.new(5, 3, 4))
		act(sa, { action = "ride", op = "board" })
		advance(0.5)
		F.respawn(a, CFrame.new(stand.door.Position))
		advance(0.5)
		check("R5 respawn during the door delay: ride gone, stand idle, new character untouched", limoBy(r3.rideId) == nil and root.Limo:GetAttribute("Stand") == "idle" and not a.root.Anchored)
		-- player leaves mid-limo-ride
		T += 5
		local r4 = Driver.request(a, { to = "pm_helixresearch" })
		standAt(a, stand.stop * Vector3.new(5, 3, 4))
		act(sa, { action = "ride", op = "board" })
		advance(6)
		local okLeave, why = pcall(close, a, sa)
		advance(1)
		local lf = limoBy(r4.rideId)
		local segs = lf and Drive.decode(lf:GetAttribute("Plan"))
		check("R5 leave mid-limo-ride: no error, rider cleared, nobody on the back seat", okLeave and lf and lf:GetAttribute("Rider") == 0 and segs and not string.find(segs[1].who, "R", 1, true), tostring(why))
		home(b)
		close(b, sb); advance(1.1)
		settleLimos()
	end

	------------------------------------------------------------------ L the limousine fleet: LIMO_FLEET from the garage, FIFO queue, pick-up only stand
	do
		local ps = {}
		for i = 1, 5 do
			local p, s = newPlayer(8550 + i, "Guest" .. i, 1)
			ps[i] = { p = p, s = s }
		end
		M.settle(1); advance(1.1)
		local hotel = Drive.place("pm_hotel")
		for i = 1, 5 do abroad(ps[i].p); standAt(ps[i].p, hotel.door.Position + Vector3.new(i * 2, 0, 0)) end
		T += 5
		local res = {}
		for i = 1, 5 do res[i] = Driver.request(ps[i].p, { to = "pm_helixresearch" }) end
		local direct, queued = 0, 0
		for i = 1, 5 do if res[i].ok and not res[i].queued then direct += 1 elseif res[i].ok and res[i].queued then queued += 1 end end
		check("L five bookings at the hotel: LIMO_FLEET cars come from the garage, the rest queue", direct == Driver.LIMO_FLEET and queued == 5 - Driver.LIMO_FLEET, direct .. "/" .. queued)
		check("L the stand car stays at the stand (bookings elsewhere use garage cars)", root.Limo:GetAttribute("Stand") == "idle")
		local first = limoBy(res[1].rideId)
		local fsegs = first and Drive.decode(first:GetAttribute("Plan"))
		check("L a garage car drives from the east tunnel", fsegs and fsegs[1].from == "pm_depot" and fsegs[1].to == "pm_hotel")
		local servedOrder = {}
		for _ = 1, 600 do
			advance(1, 0.5)
			for i = 4, 5 do
				if not servedOrder[i] and Driver.status(ps[i].p).state ~= "queued" then servedOrder[i] = T end
			end
			if servedOrder[4] and servedOrder[5] then break end
		end
		check("L queued bookings served first come, first served", servedOrder[4] and servedOrder[5] and servedOrder[4] <= servedOrder[5])
		local bad = Driver.request(ps[1].p, { to = "pm_limo" })
		check("L the limousine stand is a pick-up point only (BAD_PLACE as destination)", not bad.ok and (bad.err == "BAD_PLACE" or bad.err == "ALREADY_RIDING" or bad.err == "COOLDOWN"), bad.err)
		for i = 1, 5 do local st = Driver.status(ps[i].p); if st.rideId then Driver.cancel(st.rideId) end end
		for i = 1, 5 do home(ps[i].p); close(ps[i].p, ps[i].s) end
		advance(1.1)
		settleLimos()
	end

	------------------------------------------------------------------ N4 the limousine from the shuttle arrival point
	do
		local p, s = newPlayer(8601, "Arrive", 1)
		M.settle(1); advance(1.1)
		local pickup = Drive.nearestPickup(CityPlan.ABROAD.arrival.Position, "abroad")
		check("N4 nearestPickup(shuttle arrival) = the limousine stand", pickup and pickup.id == "pm_limo")
		abroad(p)
		standAt(p, CityPlan.ABROAD.arrival.Position)
		T += 5
		local r = Driver.request(p, { to = "pm_hotel" })
		check("N4 booking from the arrivals hall works (car at the stand)", r.ok and r.pickup == "pm_limo", r.err)
		Driver.cancel(r.rideId)
		standAt(p, Vector3.new(560, 30, 8650)) -- the far end of the waterfront
		T += 5
		local far = act(s, { action = "ride", op = "request", to = "pm_hotel" })
		check("N4 TOO_FAR abroad names Port Meridian's pick-up points, not the home city's", far.err == "TOO_FAR" and string.find(far.text, "limousine stand", 1, true) ~= nil
			and string.find(far.text, "Business City", 1, true) == nil, far.text)
		------------------------------------------------------------------ N5 honest sheet without a pick-up point
		local hook = Driver.phoneHook(s, {})
		local sh = sheets(p)[#sheets(p)]
		local anyEta = false
		if sh then for _, it in sh.places do if it.eta ~= nil then anyEta = true end end end
		check("N5 abroad, far from every pick-up: 'Walk to ... first (N studs)', not bookable, rows without ETA",
			string.find(hook.text, "Walk to ", 1, true) ~= nil and string.find(hook.text, "studs", 1, true) ~= nil and sh and sh.canBook == false and not anyEta and #sh.places > 0, hook.text)
		home(p)
		close(p, s); advance(1.1)
	end
	do
		local p, s = newPlayer(8602, "FarHome", 3)
		M.settle(1); advance(1.1)
		standAt(p, Vector3.new(600, 30, 1250))
		local hook = Driver.phoneHook(s, {})
		local sh = sheets(p)[#sheets(p)]
		local anyEta = false
		if sh then for _, it in sh.places do if it.eta ~= nil then anyEta = true end end end
		check("N5 home, far from every pick-up: honest text, not bookable, no ETAs", string.find(hook.text, "Walk to ", 1, true) ~= nil and sh and sh.canBook == false and not anyEta
			and sh.nearestName ~= nil and (sh.nearestDist or 0) > 90, hook.text)
		check("N5 ... and no 'the car is ready'", string.find(hook.text, "ready", 1, true) == nil)
		close(p, s); advance(1.1)
	end

	------------------------------------------------------------------ R6 garage stage: home refused everywhere, abroad limo works
	do
		local p, s = newPlayer(8603, "Garage", 1)
		M.settle(1); advance(1.1)
		local folder = root:FindFirstChild("Drivers_8603")
		check("R6 garage: 0 drivers, no templates", folder and folder:GetAttribute("Drivers") == 0 and folder:FindFirstChild("Driver1") == nil)
		local rr = act(s, { action = "ride", op = "request", to = "airport_departures" })
		check("R6 garage remote request refused NO_DRIVER", not rr.ok and rr.err == "NO_DRIVER", rr.err)
		local st = act(s, { action = "ride", op = "status" })
		check("R6 garage status none / NO_DRIVER", st.state == "none" and st.reason == "NO_DRIVER", tostring(st.state) .. " " .. tostring(st.reason))
		close(p, s); advance(1.1)
	end

	------------------------------------------------------------------ R7 drop-off at the HQ entrance: the founder stands off the car
	do
		local p, s = newPlayer(8701, "Home", 2)
		M.settle(1); advance(1.1)
		local cd = Drive.place("clouddesk")
		standAt(p, cd.door.Position)
		T += 5
		Driver.request(p, { to = "hq_entrance" })
		local folder = root:FindFirstChild("Drivers_8701")
		local rf = rides(folder)[1]
		local plotI = Plot.get(p).index
		local segs = Drive.decode(rf:GetAttribute("Plan"), plotI)
		advance(Drive.planEnd(segs, plotI) - T + 0.3)
		standAt(p, Drive.endCF(Drive.leg("hq_garage", "clouddesk", plotI)) * Vector3.new(5, 3, 2))
		check("R7 board at CloudDesk", act(s, { action = "ride", op = "board" }).ok)
		segs = Drive.decode(rf:GetAttribute("Plan"), plotI)
		local stopCF = Drive.endCF(Drive.leg("clouddesk", "hq_entrance", plotI))
		advance(Drive.segEnd(segs[2], plotI) - T + Driver.ALIGHT + 0.3)
		local carLocal = stopCF:PointToObjectSpace(p.root.Position)
		check("R7 founder stands clear of the car body", math.abs(carLocal.X) > Drive.CAR_WIDTH.fleet / 2 + 1 or math.abs(carLocal.Z) > 8.5, carLocal)
		close(p, s); advance(1.1)
	end

	------------------------------------------------------------------ R8 leg cache: a full server's HQ legs stay cached
	do
		local t0 = os.clock()
		local n = 0
		local legs = {}
		for plot = 1, 12 do
			for _, a in Drive.places("home", plot) do
				if a.kind == "garage" then continue end
				local leg = Drive.leg("hq_garage", a.id, plot)
				if leg then n += 1; legs[#legs + 1] = { "hq_garage", a.id, plot, leg } end
				if a.id ~= "hq_entrance" then
					local l2 = Drive.leg("hq_entrance", a.id, plot)
					if l2 then n += 1; legs[#legs + 1] = { "hq_entrance", a.id, plot, l2 } end
				end
			end
		end
		local dt = os.clock() - t0
		info(string.format("R8 %d legs (garage / entrance -> every place, 12 plots) in %.3f s = %.2f ms each (luau CLI, not Roblox)", n, dt, 1000 * dt / math.max(1, n)))
		local same = 0
		local t1 = os.clock()
		for _, l in legs do if Drive.leg(l[1], l[2], l[3]) == l[4] then same += 1 end end
		local dt2 = os.clock() - t1
		check("R8 every one of a full server's HQ legs is still cached afterwards (no clear-all thrash)", same == n and Drive.legCacheSize() >= n, same .. "/" .. n)
		check("R8 cached legs are cheap (< 5 % of the first pass)", dt2 < dt * 0.05, string.format("%.4f vs %.3f", dt2, dt))
		local a = Drive.leg("airport_departures", "clouddesk", 1)
		local b = Drive.leg("airport_departures", "clouddesk", 7)
		check("R8 static legs are shared by every plot (one table)", a ~= nil and a == b)
	end

	------------------------------------------------------------------ N12 queued booking follows the founder / dropped with a notice
	do
		local p, s = newPlayer(8801, "Queue", 2)
		M.settle(1); advance(1.1)
		local folder = root:FindFirstChild("Drivers_8801")
		standAt(p, hqPoint(p, Vector3.new(0, 3, -60)))
		T += 5
		local r1 = Driver.request(p, { to = "clouddesk" })
		check("N12 first ride", r1.ok and not r1.queued)
		T += 5
		Driver.cancel(r1.rideId) -- (driver still walking: gone)
		T += 5
		r1 = Driver.request(p, { to = "airport_departures" })
		advance(Drive.walkAt(T) + 30)
		-- the founder walks to the airport kerb meanwhile? no: book a second one from the HQ while the first car is out
		local ap = Drive.place("airport_departures")
		standAt(p, Drive.place("atlas") and Drive.place("atlas").door.Position or ap.door.Position)
		Driver.cancel(r1.rideId)
		local turning = rides(folder)[1]
		T += 5
		standAt(p, hqPoint(p, Vector3.new(0, 3, -60)))
		local q = Driver.request(p, { to = "airport_departures" })
		check("N12 booked while the driver drives back: queued", q.ok and q.queued and q.pickup == "hq_entrance", tostring(q.err) .. " " .. tostring(q.queued))
		-- he walks to CloudDesk while waiting: the car comes there
		standAt(p, Drive.place("clouddesk").door.Position)
		if turning then advance(Drive.planEnd(Drive.decode(turning:GetAttribute("Plan"), Plot.get(p).index), Plot.get(p).index) - T + 0.6) end
		advance(0.5)
		local st = Driver.status(p)
		check("N12 the queued booking is served at the pick-up where he is now", st.state == "coming" and st.pickup == "clouddesk", tostring(st.state) .. " " .. tostring(st.pickup))
		Driver.cancel(st.rideId)
		advance(300)
		-- queued, then he flies: dropped with a notice
		standAt(p, hqPoint(p, Vector3.new(0, 3, -60)))
		T += 5
		local busy = Driver.request(p, { to = "clouddesk" })
		advance(Drive.walkAt(T) + 1)
		Driver.cancel(busy.rideId)
		T += 5
		local q2 = Driver.request(p, { to = "airport_departures" })
		check("N12 queued again", q2.ok and q2.queued)
		City.trips[8801] = { player = p, state = "flying", to = "abroad", releaseAt = math.huge }
		advance(120)
		check("N12 queued booking dropped while he flies, with a notice, HUD cleared", Driver.status(p).state ~= "queued" and p:GetAttribute("DriveQueue") == nil
			and string.find(lastNotice(p), "cancelled", 1, true) ~= nil, lastNotice(p))
		City.trips[8801] = nil
		close(p, s); advance(1.1)
	end

	------------------------------------------------------------------ N13 founder leaves while his car is on the road: it finishes its leg
	do
		local p, s = newPlayer(8901, "Leaver", 2)
		M.settle(1); advance(1.1)
		local plotI = Plot.get(p).index
		standAt(p, hqPoint(p, Vector3.new(0, 3, -60)))
		T += 5
		Driver.request(p, { to = "airport_departures" })
		local legA = Drive.leg("hq_garage", "hq_entrance", plotI)
		advance(Drive.walkAt(T) + legA.dur + 1)
		standAt(p, Drive.endCF(legA) * Vector3.new(5, 3, 2))
		act(s, { action = "ride", op = "board" })
		advance(20)
		close(p, s)
		advance(0.3)
		local det = nil
		for _, ch in root:GetChildren() do if ch:GetAttribute("Detached") == true and string.match(ch.Name, "^Drivers_8901_left") then det = ch end end
		local rf = det and rides(det)[1]
		local segs = rf and Drive.decode(rf:GetAttribute("Plan"), plotI)
		check("N13 the car on the road finishes its leg (detached folder, empty, no posts)", det and rf and segs and #segs == 1 and segs[1].to == "airport_departures"
			and segs[1].who == "D" and det:GetAttribute("Drivers") == 0 and rf:GetAttribute("Rider") == 0)
		check("N13 the live company folder is gone", root:FindFirstChild("Drivers_8901") == nil)
		advance(200)
		check("N13 the detached folder goes when the leg is over", det == nil or det.Parent == nil)
	end

	------------------------------------------------------------------ N14 "let me out here" avoids props
	do
		local p, s = newPlayer(9001, "Props", 2)
		M.settle(1); advance(1.1)
		local plotI = Plot.get(p).index
		standAt(p, hqPoint(p, Vector3.new(0, 3, -60)))
		T += 5
		Driver.request(p, { to = "clouddesk" })
		local legA = Drive.leg("hq_garage", "hq_entrance", plotI)
		advance(Drive.walkAt(T) + legA.dur + 1)
		standAt(p, Drive.endCF(legA) * Vector3.new(5, 3, 2))
		act(s, { action = "ride", op = "board" })
		local folder = root:FindFirstChild("Drivers_9001")
		local rf = rides(folder)[1]
		local segs = Drive.decode(rf:GetAttribute("Plan"), plotI)
		local legB = Drive.leg("hq_entrance", "clouddesk", plotI)
		advance(Drive.BOARD_DELAY + legB.dur * 0.6)
		local pose = Drive.pose(segs, plotI, T)
		local cands = Drive.kerbCandidates(pose.cf, "home", plotI)
		blockers = { cands[1].Position }
		local okc = act(s, { action = "ride", op = "cancel" })
		blockers = {}
		info("N14 cands " .. tostring(cands[1].Position) .. " / " .. tostring(cands[2] and cands[2].Position) .. " root " .. tostring(p.root.Position) .. " ok " .. tostring(okc.ok) .. " " .. tostring(okc.err))
		check("N14 a prop on the first kerb spot: placed at the next free one", okc.ok and #cands >= 2 and (p.root.Position - cands[2].Position).Magnitude < 0.6
			and (p.root.Position - cands[1].Position).Magnitude > 1, p.root.Position)
		close(p, s); advance(1.1)
	end

	------------------------------------------------------------------ night: the drivers are on call (longer walk, honest ETA)
	do
		local p, s = newPlayer(9101, "Night", 2)
		M.settle(1); advance(1.1)
		local plotI = Plot.get(p).index
		-- 23:00 company time (CompanyOps.hour)
		local dayStart = T - (T % Ops.DAY)
		T = dayStart + 900 + (5 / 14) * 300 + Ops.DAY
		check("N-night clock is 23:00", math.abs(Ops.hour(T) - 23) < 0.05, Ops.hour(T))
		check("N-night: drivers not on post", Drive.onPost(T) == false and Drive.walkAt(T) == Drive.WALK_NIGHT)
		standAt(p, hqPoint(p, Vector3.new(0, 3, -60)))
		local r = Driver.request(p, { to = "clouddesk" })
		local legA = Drive.leg("hq_garage", "hq_entrance", plotI)
		check("N-night: ETA = night walk + drive (honest)", r.ok and math.abs(r.eta - math.ceil(Drive.WALK_NIGHT + legA.dur)) <= 1, r.eta)
		Driver.cancel(r.rideId)
		close(p, s); advance(1.1)
	end

	------------------------------------------------------------------ rate limits (real numbers)
	do
		for k, v in LIMITS do Driver.LIMITS[k] = v end
		Driver._resetLimits()
		local p, s = newPlayer(9201, "Limits", 2)
		M.settle(1); advance(1.1)
		local reads = 0
		for _ = 1, 10 do if act(s, { action = "ride", op = "status" }).err ~= "RATE_LIMIT" then reads += 1 end end
		local w1 = act(s, { action = "ride", op = "cancel" })
		check("N11 ten status polls in a row are answered and a booking op still gets through", reads == 10 and w1.err ~= "RATE_LIMIT", reads)
		close(p, s); advance(1.1)
	end

	G.warn = origWarn
	check("no warnings from DriverService during the scenarios", warns == 0, warns)
end
local ok, err = M.runMain(body, { timeout = 1800, maxSteps = 60000000 })
if not ok then failc += 1; print("CRASH " .. tostring(err)) end
print(string.format("drivers_review: %d passed, %d failed", pass, failc))
