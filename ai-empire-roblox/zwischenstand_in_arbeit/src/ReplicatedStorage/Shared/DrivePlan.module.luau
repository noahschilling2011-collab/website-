--!strict
-- DrivePlan (package "drivers"): pure data and maths of the company chauffeur rides, the visible fleet rides and
-- the VIP limousine in Port Meridian. Shared by DriverService (server: timelines, ETAs, validation) and
-- DriveController (client: the same cars posed every frame from workspace:GetServerTimeNow()). Nothing here
-- creates instances; the same inputs give bit-identical results on server and client, so the server only
-- publishes {from, to, start time} and every client rebuilds the identical path.
--   * Places (Drive.places / Drive.place): pm_depot (the limousines' garage in the east tunnel), hq_garage (the fleet bay in B1, depot) and hq_entrance (the driveway
--     beside the visitor parking: pick-up in the outbound lane, drop-off in the inbound lane) per plot;
--     airport_departures / airport_arrivals (kerb spots in the City Airport drop-off lane, between the parked
--     taxis, cars and buses); every Business City building of CityPlan.BUILDINGS (kerb in front of the door, on
--     the building's side of the street); in Port Meridian pm_limo (MetroPlan.VIP_LIMO.stand = the limousine's
--     home), pm_airport (terminal drop-off), pm_hotel (Meridian Grand, Harbour Street) and the four client
--     towers (Meridian Boulevard kerb). Each place: stop (car pivot, ground level, LookVector = heading), drop,
--     door (where the passenger stands after getting out), explicit lane-level out / in polylines to the road.
--   * Road graphs: home = CityPlan.NODES / EDGES (district streets, Business City, Airport Road), abroad = the
--     junctions of MetroPlan.ROADS. Directed routing (right-hand traffic): a kerb stop is only approached in its
--     own direction, U-turns only at junctions (penalty Drive.UTURN), never across the boulevard median.
--     The limousine service's own garage (pm_depot) lies inside the east tunnel of Arrivals Drive (MetroPlan.TUNNELS):
--     limousines that are not waiting at the stand come from there and go back there (a road-graph spur past x 700).
--   * Path: centre-line route -> lane polyline (each road segment shifted to the right by the road's outer lane
--     offset, corners = intersections of neighbouring lane lines) -> rounded corners (fillets, Drive.FILLET)
--     -> resampled points (<= Drive.STEP) -> speed profile (class cruise speeds, corner limit sqrt(A_LAT * R),
--     ACCEL / DECEL, standing start and stop) -> time stamps. Drive.at(leg, t) poses the car (pitch on ramps).
-- Coordinates: world studs; the car pivot is the centre of the car at ground level, -Z = forward.
local Shared = script.Parent
local City = require(Shared.Config.CityPlan)
local Metro = require(Shared.Config.MetroPlan)
local Campus = require(Shared.Config.CampusConfig)
local Ops = require(Shared.CompanyOps)

local Drive = {}

-- cruise studs/s per class; "metro" = the road class abroad (Port Meridian traffic: CityLifeController's cars cruise at
-- about 30 studs/s and stop at lights, so the limousine keeps their pace on the same lanes)
Drive.SPEED = { road = 64, metro = 30, access = 18, site = 14, ramp = 9, garage = 7 } :: { [string]: number }
Drive.ACCEL = 10 -- studs/s^2
Drive.DECEL = 12
Drive.A_LAT = 10 -- corner speed limit: v = sqrt(A_LAT * R)
Drive.FILLET = 16 -- target corner radius (clamped by the free length on both sides)
Drive.STEP = 3 -- resample spacing of straight parts
Drive.UTURN = 400 -- routing penalty (studs) of a U-turn at a junction
Drive.UTURN_SWING = 10 -- a U-turn swings at most this far past its junction / turn point
Drive.WALK = 6 -- seconds the driver needs from his post to the car in B1 (he is not shown meanwhile)
Drive.WALK_NIGHT = 20 -- 22:00-06:00 the drivers are on call in the drivers' room (not at the canopy): a longer walk
Drive.POST_HOURS = { from = 6, to = 22 } -- company hours (CompanyOps.hour) the drivers wait under the entrance canopy
Drive.WAIT = 90 -- seconds a car waits at the pick-up for its passenger
Drive.BOARD_RADIUS = 18 -- a passenger gets in within this distance of the waiting car (flat), |dy| < BOARD_DY
Drive.BOARD_DY = 10
Drive.BOARD_DELAY = 2 -- seconds from "get in" to the car pulling away (doors)
Drive.PICKUP_RADIUS = { hq = 260, airport = 140, building = 90, pm = 110 } :: { [string]: number } -- nearest pick-up
Drive.LEG_CACHE = 800 -- routed legs kept (least recently used dropped first)
Drive.CAR_LENGTH = { fleet = 15, limo = 21, compact = 12, van = 15, executive = 15, sport = 13.5 } :: { [string]: number }
Drive.CAR_WIDTH = { fleet = 7.0, limo = 7.4 } :: { [string]: number } -- incl. mirrors (B1 lane: see hqPoints)
Drive.WHEELBASE = { fleet = 9.3, limo = 13, compact = 7.4, van = 9.3, executive = 9.3, sport = 8.4 } :: { [string]: number }

export type Place = {
	id: string,
	name: string, -- "City Airport (departures)"
	short: string, -- "the airport"
	zone: string, -- "home" | "abroad"
	kind: string, -- "garage" | "hq" | "airport" | "client" | "hotel" | "limo"
	stop: CFrame, -- pick-up stop: car pivot at ground level, LookVector = heading
	drop: CFrame, -- drop-off stop (the same as stop except at the HQ)
	door: CFrame, -- passenger root after getting out (ground + 3), facing where he walks
	outPts: { Vector3 }, -- from the stop to the road mouth (lane level, explicit)
	outCls: { string }, -- speed class of the segment ending at outPts[i] (i >= 2)
	inPts: { Vector3 }, -- from the road mouth to the drop stop
	inCls: { string },
	dirs: number, -- 2 = joins / leaves its road in both directions, 1 = only in its own heading
	clientId: string?, -- CityPlan client building id
	plot: number?,
	pickup: string?, -- class of PICKUP_RADIUS
}
export type Leg = {
	key: string,
	from: string,
	to: string,
	pts: { Vector3 },
	cum: { number }, -- distance along the path at pts[i]
	t: { number }, -- seconds after the leg start at pts[i]
	v: { number }, -- speed at pts[i] (studs/s)
	len: number,
	dur: number,
}

local G = City.GROUND
local RT = City.ROAD_TOP
local WT = City.WALK_TOP

------------------------------------------------------------------------------------------------ small maths
local function flat(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end
Drive.flat = flat
local function dir2(a: Vector3, b: Vector3): (number, number)
	local dx, dz = b.X - a.X, b.Z - a.Z
	local l = math.sqrt(dx * dx + dz * dz)
	if l < 1e-9 then return 0, -1 end
	return dx / l, dz / l
end
-- right-hand normal of a heading (x, z): (-z, x)
local function lookCF(p: Vector3, hx: number, hz: number): CFrame
	return CFrame.lookAt(p, p + Vector3.new(hx, 0, hz))
end

-- Lane centre of a two-way road: the middle of the right-hand half. (The outer lane of the 48 / 50 wide district
-- roads would brush the Founder Square props beside the East Ring Road.)
function Drive.laneOff(width: number): number
	return width / 4
end

------------------------------------------------------------------------------------------------ graphs
type Edge = { a: string, b: string, off: number, len: number }
type Graph = { nodes: { [string]: Vector3 }, edges: { Edge }, adj: { [string]: { { to: string, e: number } } }, ids: { string } }

local function laneOffHome(axis: string, c: number, a1: number, a2: number): number
	local lo, hi = math.min(a1, a2), math.max(a1, a2)
	local best: number? = nil
	for _, list in { City.ROADS, City.DISTRICT_ROADS } do
		for _, r in list do
			if r.axis == axis and math.abs(r.c - c) < 1 and r.a2 > lo - 30 and r.a1 < hi + 30 then
				local off = Drive.laneOff(r.width)
				if best == nil or off < best then best = off end
			end
		end
	end
	return best or 10
end
local function metroOff(r: any): number
	return r.median / 2 + (r.lanes - 0.5) * (r.width - r.median) / 2 / r.lanes
end
local function finish(g: Graph): Graph
	for id in g.nodes do
		table.insert(g.ids, id)
		g.adj[id] = {}
	end
	table.sort(g.ids)
	for i, e in g.edges do
		e.len = flat(g.nodes[e.a], g.nodes[e.b])
		table.insert(g.adj[e.a], { to = e.b, e = i })
		table.insert(g.adj[e.b], { to = e.a, e = i })
	end
	for _, list in g.adj do table.sort(list, function(p, q) return p.to < q.to end) end
	return g
end
-- the limousine garage (pm_depot): inside Arrivals Drive's east tunnel, 90 studs past the gate (x = a2 = 700)
local arrivalsRoad = Metro.road("pm_arrivals")
Drive.PM_DEPOT_X = (if arrivalsRoad then arrivalsRoad.a2 else 700) + 90
Drive.TURN_POINTS = { ap_turn_e = Vector3.new(420, 0, 2380), ap_turn_w = Vector3.new(-420, 0, 2380) } :: { [string]: Vector3 }
local homeGraph: Graph? = nil
local function home(): Graph
	local cached = homeGraph
	if cached then return cached end
	local g: Graph = { nodes = {}, edges = {}, adj = {}, ids = {} }
	for id, p in City.NODES do g.nodes[id] = Vector3.new(p.X, RT, p.Z) end
	for _, e in City.EDGES do
		local a, b = City.NODES[e[1]], City.NODES[e[2]]
		local off = if math.abs(a.Z - b.Z) < 0.5 then laneOffHome("x", a.Z, a.X, b.X) else laneOffHome("z", a.X, a.Z, b.Z)
		table.insert(g.edges, { a = e[1], b = e[2], off = off, len = 0 })
	end
	-- turnaround points on Airport Road (40 wide): a car leaving the airport kerbs eastbound may U-turn there
	-- instead of circling the whole ring road (CityPlan's graph itself is unchanged)
	for id, p in Drive.TURN_POINTS do
		for i, e in g.edges do
			local a, b = g.nodes[e.a], g.nodes[e.b]
			local onX = math.abs(a.Z - p.Z) < 0.5 and math.abs(b.Z - p.Z) < 0.5 and p.X > math.min(a.X, b.X) + 1 and p.X < math.max(a.X, b.X) - 1
			local onZ = math.abs(a.X - p.X) < 0.5 and math.abs(b.X - p.X) < 0.5 and p.Z > math.min(a.Z, b.Z) + 1 and p.Z < math.max(a.Z, b.Z) - 1
			if onX or onZ then
				g.nodes[id] = Vector3.new(p.X, RT, p.Z)
				table.remove(g.edges, i)
				table.insert(g.edges, { a = e.a, b = id, off = e.off, len = 0 })
				table.insert(g.edges, { a = id, b = e.b, off = e.off, len = 0 })
				break
			end
		end
	end
	homeGraph = finish(g)
	return homeGraph :: Graph
end
local abroadGraph: Graph? = nil
local function abroad(): Graph
	local cached = abroadGraph
	if cached then return cached end
	local g: Graph = { nodes = {}, edges = {}, adj = {}, ids = {} }
	local xs: { any }, zs: { any } = {}, {}
	for _, r in Metro.ROADS do if r.axis == "x" then table.insert(xs, r) else table.insert(zs, r) end end
	local function key(x: number, z: number): string return "pm_" .. math.floor(x) .. "_" .. math.floor(z) end
	-- junctions = every x-road / z-road crossing inside both spans
	for _, rx in xs do
		for _, rz in zs do
			if rz.c >= rx.a1 and rz.c <= rx.a2 and rx.c >= rz.a1 - 1 and rx.c <= rz.a2 + 1 then g.nodes[key(rz.c, rx.c)] = Vector3.new(rz.c, RT, rx.c) end
		end
	end
	local function along(r: any)
		local list: { number } = {}
		local others: { any } = if r.axis == "x" then zs else xs
		for _, o in others do
			local at = o.c
			if g.nodes[if r.axis == "x" then key(at, r.c) else key(r.c, at)] then table.insert(list, at) end
		end
		table.sort(list)
		for i = 2, #list do
			local a = if r.axis == "x" then key(list[i - 1], r.c) else key(r.c, list[i - 1])
			local b = if r.axis == "x" then key(list[i], r.c) else key(r.c, list[i])
			table.insert(g.edges, { a = a, b = b, off = metroOff(r), len = 0 })
		end
	end
	for _, r in Metro.ROADS do along(r) end
	-- the limousine garage spur: Arrivals Drive on into its east tunnel (the client-only road continuation, MetroPlan
	-- `beyond`) to the depot; a dead end, so no other route ever uses it (U-turn penalty)
	local arr = arrivalsRoad
	if arr then
		local lastX: number? = nil
		for _, rz in zs do
			if g.nodes[key(rz.c, arr.c)] and (lastX == nil or rz.c > (lastX :: number)) then lastX = rz.c end
		end
		if lastX then
			g.nodes.pm_depot_end = Vector3.new(Drive.PM_DEPOT_X + 20, RT, arr.c)
			table.insert(g.edges, { a = key(lastX :: number, arr.c), b = "pm_depot_end", off = metroOff(arr), len = 0 })
		end
	end
	abroadGraph = finish(g)
	return abroadGraph :: Graph
end
function Drive.graph(zone: string): Graph
	return if zone == "abroad" then abroad() else home()
end

-- nearest edge of graph g to p: (edge index, projected point, t along a->b, distance)
local function snap(g: Graph, p: Vector3): (number, Vector3, number, number)
	local best, bq, bt, bd = 0, p, 0, math.huge
	for i, e in g.edges do
		local a, b = g.nodes[e.a], g.nodes[e.b]
		local dx, dz = b.X - a.X, b.Z - a.Z
		local l2 = dx * dx + dz * dz
		local t = if l2 > 0 then math.clamp(((p.X - a.X) * dx + (p.Z - a.Z) * dz) / l2, 0, 1) else 0
		local q = Vector3.new(a.X + dx * t, RT, a.Z + dz * t)
		local d = flat(p, q)
		if d < bd - 1e-9 then best, bq, bt, bd = i, q, t, d end
	end
	return best, bq, bt, bd
end

------------------------------------------------------------------------------------------------ places
local placeCache: { [string]: Place } = {}
local listCache: { [string]: { Place } } = {}

local function mk(id: string, name: string, short: string, zone: string, kind: string, stop: CFrame, drop: CFrame, door: CFrame,
	outPts: { Vector3 }, outCls: { string }, inPts: { Vector3 }, inCls: { string }, dirs: number): Place
	return { id = id, name = name, short = short, zone = zone, kind = kind, stop = stop, drop = drop, door = door, outPts = outPts, outCls = outCls,
		inPts = inPts, inCls = inCls, dirs = dirs }
end
local function cls(n: number, c: string): { string }
	local out: { string } = {}
	for i = 1, n do out[i] = c end
	return out
end

-- HQ (plot-local coordinates; plan tier >= 1: B1 garage with the ramp x 92..112, driveway to the avenue).
-- Outbound lane x = 107.5, inbound x = 98.5 (the B1 drive arrows), clear of the convex mirror arm (x <= 94.6 at
-- z -38.5), the pick-up bay of the founder's own car (x 95.2..104.8, z -7.3..11.3) and the garage wall (x 112).
Drive.HQ = {
	depot = Vector3.new(107.4, -16, 56), -- fleet car parked deep in B1, nose towards the ramp
	park = Vector3.new(107.4, -16, 44),
	stop = Vector3.new(107.5, 0.1, -162), -- pick-up: outbound lane, beside the visitor parking
	drop = Vector3.new(98.5, 0.1, -168), -- drop-off: inbound lane
	-- drivers wait under the entrance canopy beside its east column (x 17, z -63), facing the forecourt and turned a
	-- little towards the drive to the pick-up (players walking up or coming out of the doors see them from the front)
	post = { CFrame.lookAt(Vector3.new(19, 3.12, -59.5), Vector3.new(26, 3.12, -79.5)), CFrame.lookAt(Vector3.new(23.5, 3.12, -61.5), Vector3.new(30.5, 3.12, -81.5)) },
	board = Vector3.new(90, 3.1, -162), -- where the founder walks to (visitor parking edge, left of the car)
	alight = CFrame.lookAt(Vector3.new(92.5, 3.1, -168), Vector3.new(77, 3.1, -140)), -- after the drop-off: towards the visitor path
}
local function hqPoints(cf: CFrame): ({ Vector3 }, { string }, { Vector3 }, { string }, { Vector3 }, { string }, { Vector3 }, { string })
	local function w(x: number, y: number, z: number): Vector3 return cf:PointToWorldSpace(Vector3.new(x, y, z)) end
	-- garage -> stop -> mouth (outbound) ; mouth -> drop -> park (inbound) ; stop -> U-turn -> inbound (cancel)
	local gOut = { w(107.4, -16, 56), w(107.4, -16, -30), w(107.4, -16, -36), w(107.4, 0, -146), w(107.5, 0.1, -150), w(107.5, 0.1, -162) }
	local gOutCls = { "", "garage", "garage", "ramp", "site", "site" }
	local sOut = { w(107.5, 0.1, -162), w(107.5, 0.1, -205), w(107.5, 0.1, -217) }
	local sOutCls = { "", "site", "site" }
	local mIn = { w(98.5, 0.1, -217), w(98.5, 0.1, -205), w(98.5, 0.1, -168) }
	local mInCls = { "", "site", "site" }
	-- back to the depot side (x 107.4) gently over the whole ramp (4.6 degrees): a lane change inside B1 would swing
	-- the car's corner into the garage wall (x 112) or into the founder's car in the pick-up bay (spawn x 100, at most
	-- 7.4 wide -> x <= 103.7); the fleet car is 7.0 wide (Drive.CAR_WIDTH), so x 107.4 leaves 0.2 / 1.1 studs
	local dPark = { w(98.5, 0.1, -168), w(98.5, 0.1, -150), w(98.5, 0, -146), w(107.4, -16, -36), w(107.4, -16, 44) }
	local dParkCls = { "", "site", "site", "ramp", "garage" }
	return gOut, gOutCls, sOut, sOutCls, mIn, mInCls, dPark, dParkCls
end
local function hqUturn(cf: CFrame): ({ Vector3 }, { string })
	local function w(x: number, y: number, z: number): Vector3 return cf:PointToWorldSpace(Vector3.new(x, y, z)) end
	-- a left U-turn over the visitor parking (x 70..92 is asphalt), back into the inbound lane before the ramp
	return { w(107.5, 0.1, -162), w(107.5, 0.1, -196), w(89.5, 0.1, -196), w(89.5, 0.1, -176), w(98.5, 0.1, -152), w(98.5, 0, -146),
		w(107.4, -16, -36), w(107.4, -16, 44) },
		{ "", "site", "site", "site", "site", "site", "ramp", "garage" }
end

local function plotCF(plot: number): CFrame?
	local info = City.plots()[plot]
	return if info then info.cframe else nil
end
Drive.plotCF = plotCF

local function hqPlaces(plot: number): (Place?, Place?)
	local cf = plotCF(plot)
	if not cf then return nil, nil end
	local gOut, gOutCls, sOut, sOutCls, mIn, mInCls, dPark, dParkCls = hqPoints(cf)
	local fwd = cf.LookVector -- plot frame: LookVector (= local -Z) points to the avenue = outbound heading
	local look = -fwd -- inbound heading (into the site)
	local stopCF = CFrame.lookAt(cf:PointToWorldSpace(Drive.HQ.stop), cf:PointToWorldSpace(Drive.HQ.stop) + fwd)
	local dropCF = CFrame.lookAt(cf:PointToWorldSpace(Drive.HQ.drop), cf:PointToWorldSpace(Drive.HQ.drop) + look)
	local depotCF = CFrame.lookAt(cf:PointToWorldSpace(Drive.HQ.depot), cf:PointToWorldSpace(Drive.HQ.depot) + fwd)
	local parkCF = CFrame.lookAt(cf:PointToWorldSpace(Drive.HQ.park), cf:PointToWorldSpace(Drive.HQ.park) + look)
	local garage = mk("hq_garage", "HQ garage", "the garage", "home", "garage", depotCF, parkCF, cf * CFrame.new(Drive.HQ.board),
		gOut, gOutCls, dPark, dParkCls, 2)
	garage.plot = plot
	local hq = mk("hq_entrance", "HQ entrance", "the HQ", "home", "hq", stopCF, dropCF, cf * Drive.HQ.alight, sOut, sOutCls, mIn, mInCls, 2)
	hq.plot = plot
	hq.pickup = "hq"
	return garage, hq
end

local function kerbPlace(id: string, name: string, short: string, zone: string, kind: string, stopP: Vector3, hx: number, hz: number,
	approach: { Vector3 }, depart: { Vector3 }, door: CFrame, pickup: string): Place
	local stop = lookCF(stopP, hx, hz)
	local inPts = table.clone(approach)
	table.insert(inPts, stopP)
	local outPts = { stopP }
	for _, p in depart do table.insert(outPts, p) end
	local p = mk(id, name, short, zone, kind, stop, stop, door, outPts, cls(#outPts, "access"), inPts, cls(#inPts, "access"), 1)
	p.pickup = pickup
	return p
end

local function airportPlaces(): { Place }
	local out: { Place } = {}
	-- departures: between the parked car (x 23.7..36.3) and the taxi (x 103.7..116.3) at the kerb (z 2413.5),
	-- 66 studs from the central departure door; approached from Airport Road eastbound, leaves eastbound. The car
	-- pulls in past the parked car and stands straight at the kerb (a car still angled at the stop would touch the
	-- bollard row at z 2419.4)
	table.insert(out, kerbPlace("airport_departures", "City Airport (departures)", "the airport", "home", "airport", Vector3.new(66, RT, 2413.5), 1, 0,
		{ Vector3.new(10, RT, 2390), Vector3.new(36, RT, 2400), Vector3.new(54, RT, 2413.5) },
		{ Vector3.new(90, RT, 2406.5), Vector3.new(130, RT, 2398), Vector3.new(175, RT, 2391), Vector3.new(200, RT, 2390) },
		CFrame.lookAt(Vector3.new(66, WT + 3, 2421.5), Vector3.new(66, WT + 3, 2440)), "airport"))
	-- arrivals: east of the buses (x <= 257) and the arrivals-exit zebra (x 264..276); the arrivals door is x 270.
	-- The car merges into the kerb after the zebra and stops straight at x 300 (between the bollards at 291 / 306)
	table.insert(out, kerbPlace("airport_arrivals", "City Airport (arrivals)", "the airport arrivals", "home", "airport", Vector3.new(300, RT, 2413.5), 1, 0,
		{ Vector3.new(200, RT, 2390), Vector3.new(262, RT, 2400), Vector3.new(288, RT, 2413.5) },
		{ Vector3.new(318, RT, 2411), Vector3.new(340, RT, 2402), Vector3.new(366, RT, 2393), Vector3.new(396, RT, 2390) },
		CFrame.lookAt(Vector3.new(298, WT + 3, 2421.5), Vector3.new(272, WT + 3, 2440)), "airport"))
	return out
end

local function roadOf(axis: string, c: number): any
	for _, r in City.ROADS do if r.axis == axis and math.abs(r.c - c) < 1 then return r end end
	return nil
end
local function buildingPlaces(): { Place }
	local out: { Place } = {}
	for _, b in City.BUILDINGS do
		if b.zone ~= "downtown" then continue end
		local f = b.frame
		local look = f.LookVector -- towards the street
		local setback = City.OFFICE.setback
		local c = f.Position + look * setback -- street centre in front of the door
		local axis = if math.abs(look.Z) > 0.5 then "x" else "z"
		local road = roadOf(axis, if axis == "x" then c.Z else c.X)
		local width = if road then road.width else 40
		local walk = if road then road.walk else 8
		local laneOff = Drive.laneOff(width)
		local kerbOff = width / 2 - 4.6
		local rx, rz = -look.X, -look.Z -- towards the building (the car's right side)
		local hx, hz = rz, -rx -- heading whose right-hand side faces the building
		local function at(lat: number, lon: number): Vector3 return Vector3.new(c.X + rx * lat + hx * lon, RT, c.Z + rz * lat + hz * lon) end
		local doorP = Vector3.new(c.X + rx * (width / 2 + walk / 2), WT + 3, c.Z + rz * (width / 2 + walk / 2))
		local kind = if b.kind == "hotel" then "hotel" else "client"
		local p = kerbPlace(b.id, b.name, b.name, "home", kind, at(kerbOff, 0), hx, hz, { at(laneOff, -45) }, { at(laneOff, 40) },
			CFrame.lookAt(doorP, doorP + Vector3.new(rx, 0, rz)), "building")
		p.clientId = b.clientId
		table.insert(out, p)
	end
	return out
end

local function metroPlaces(): { Place }
	local out: { Place } = {}
	local PT = Metro.PLAZA_TOP
	-- the VIP limousine stand (bay 1 of the lay-by, cars face west); bay 2 holds the decorative limousine
	-- (x 118.5..137.5), so the limo pulls out into Arrivals Drive's westbound lane (z 7776) before passing it. The
	-- last / first 16 studs at the stand are straight along the kerb, so a car that arrives or leaves stands exactly
	-- at the stand's pose (the idle limousine, a waiting ride and a departing one are drawn at the same CFrame)
	local stand = Metro.VIP_LIMO.stand
	local sp = stand.Position
	local limo = kerbPlace("pm_limo", "VIP limousine stand", "the limousine stand", "abroad", "limo", Vector3.new(sp.X, RT, sp.Z), stand.LookVector.X, stand.LookVector.Z,
		{ Vector3.new(262, RT, 7776), Vector3.new(222, RT, 7772), Vector3.new(206, RT, 7764.5), Vector3.new(sp.X + 16, RT, sp.Z) },
		{ Vector3.new(sp.X - 12, RT, sp.Z), Vector3.new(150, RT, 7767.5), Vector3.new(130, RT, 7774), Vector3.new(100, RT, 7776), Vector3.new(80, RT, 7776) },
		CFrame.lookAt(Vector3.new(sp.X - 2, PT + 3, 7751.5), Vector3.new(sp.X - 2, PT + 3, 7700)), "pm")
	table.insert(out, limo)
	-- the limousine garage inside Arrivals Drive's east tunnel: out in the westbound lane, back in the eastbound lane
	if arrivalsRoad then
		local off = metroOff(arrivalsRoad)
		local x = Drive.PM_DEPOT_X
		local outP = Vector3.new(x, RT, arrivalsRoad.c - off)
		local inP = Vector3.new(x, RT, arrivalsRoad.c + off)
		table.insert(out, mk("pm_depot", "Limousine garage", "the limousine garage", "abroad", "garage", lookCF(outP, -1, 0), lookCF(inP, 1, 0), lookCF(outP, -1, 0),
			{ outP, Vector3.new(x - 40, RT, outP.Z) }, { "road", "road" }, { Vector3.new(x - 40, RT, inP.Z), inP }, { "road", "road" }, 1))
	end
	-- Port Meridian Airport: terminal drop-off on Arrivals Drive (westbound kerb, west of the boulevard junction)
	table.insert(out, kerbPlace("pm_airport", "Port Meridian Airport", "the airport", "abroad", "airport", Vector3.new(-75, RT, 7772.6), -1, 0,
		{ Vector3.new(-40, RT, 7776), Vector3.new(-62, RT, 7772.6) }, { Vector3.new(-100, RT, 7776), Vector3.new(-130, RT, 7776) },
		CFrame.lookAt(Vector3.new(-80, PT + 3, 7757), Vector3.new(-80, PT + 3, 7700)), "pm"))
	-- Meridian Grand Hotel: Harbour Street eastbound kerb, east of the boulevard junction (x -52..52)
	local hotel = City.INTL_HOTEL
	table.insert(out, kerbPlace("pm_hotel", if hotel then hotel.name else "Meridian Grand Hotel", "the Meridian Grand", "abroad", "hotel", Vector3.new(70, RT, 8347.4), 1, 0,
		{ Vector3.new(38, RT, 8344), Vector3.new(58, RT, 8347.4) }, { Vector3.new(110, RT, 8344) },
		CFrame.lookAt(Vector3.new(66, WT + 3, 8356.5), Vector3.new(30, WT + 3, 8380)), "pm"))
	-- client towers on Meridian Boulevard (outer lane 45 from the axis, kerb 52, sidewalk to 64)
	local boulevard = Metro.road("pm_boulevard")
	local half = if boulevard then boulevard.width / 2 else 52
	local walkW = if boulevard then boulevard.walk else 12
	local lane = if boulevard then metroOff(boulevard) else 45
	for _, b in City.BUILDINGS do
		if b.zone ~= "abroad" or b.kind ~= "tower" then continue end
		local f = b.frame
		local look = f.LookVector
		local c = Vector3.new(0, G, f.Position.Z) -- boulevard axis in front of the tower
		local rx, rz = -look.X, -look.Z
		local hx, hz = rz, -rx
		local function at(lat: number, lon: number): Vector3 return Vector3.new(c.X + rx * lat + hx * lon, RT, c.Z + rz * lat + hz * lon) end
		local doorP = Vector3.new(c.X + rx * (half + walkW / 2), WT + 3, c.Z)
		local p = kerbPlace("pm_" .. b.id, b.name, b.name, "abroad", "client", at(half - 4.6, 0), hx, hz, { at(lane, -45) }, { at(lane, 40) },
			CFrame.lookAt(doorP, doorP + Vector3.new(rx, 0, rz)), "pm")
		p.clientId = b.clientId
		table.insert(out, p)
	end
	return out
end

local staticList: { Place }? = nil
local function statics(): { Place }
	local cached = staticList
	if cached then return cached end
	local list: { Place } = {}
	for _, p in airportPlaces() do table.insert(list, p) end
	for _, p in buildingPlaces() do table.insert(list, p) end
	for _, p in metroPlaces() do table.insert(list, p) end
	for _, p in list do placeCache[p.id] = p end
	staticList = list
	return list
end

-- One place by id; hq_garage / hq_entrance need the plot index (1..12).
function Drive.place(id: any, plot: number?): Place?
	if typeof(id) ~= "string" then return nil end
	if id == "hq_garage" or id == "hq_entrance" then
		if typeof(plot) ~= "number" or plot ~= plot then return nil end
		local key = id .. "#" .. math.floor(plot)
		local cached = placeCache[key]
		if cached then return cached end
		local g, h = hqPlaces(math.floor(plot))
		if not g or not h then return nil end
		placeCache["hq_garage#" .. math.floor(plot)] = g
		placeCache["hq_entrance#" .. math.floor(plot)] = h
		return if id == "hq_garage" then g else h
	end
	statics()
	return placeCache[id]
end
-- Every place of a zone ("home" | "abroad" | nil = both) in a fixed order; the HQ places only with a plot.
function Drive.places(zone: string?, plot: number?): { Place }
	local key = tostring(zone) .. "#" .. tostring(plot)
	local cached = listCache[key]
	if cached then return cached end
	local out: { Place } = {}
	if (zone == nil or zone == "home") and plot then
		local g, h = Drive.place("hq_garage", plot), Drive.place("hq_entrance", plot)
		if g and h then table.insert(out, h); table.insert(out, g) end
	end
	for _, p in statics() do
		if zone == nil or p.zone == zone then table.insert(out, p) end
	end
	listCache[key] = out
	return out
end
-- Place of a CityPlan client building / catalogue client (by CityPlan id, display name, contract or business id).
function Drive.clientPlace(key: any): Place?
	local d = City.clientOffice(key)
	if not d then return nil end
	return Drive.place(if d.zone == "abroad" then "pm_" .. d.id else d.id)
end
-- Zone of a world position: "home" (district, Business City, airport) | "abroad" | nil
function Drive.zoneAt(p: Vector3): string?
	local z = City.zoneAt(p)
	if z == nil or z == "harbour" then return nil end
	return if z == "abroad" then "abroad" else "home"
end
-- Port Meridian's arrivals hall and plaza (where the shuttle and the company jet put the founder down): the VIP
-- limousine stand by the hall is the pick-up for anyone in there (the hall is up to ~260 studs from the stand)
Drive.PM_STAND_AREA = { City.ABROAD.terminal, City.ABROAD.plaza } :: { any }
-- The pick-up place nearest to a standing position (own plot -> HQ entrance; Port Meridian arrivals hall / plaza ->
-- the limousine stand), or nil, "TOO_FAR".
function Drive.nearestPickup(p: Vector3, zone: string, plot: number?): (Place?, string?)
	if zone == "home" and plot then
		local info = City.plots()[plot]
		if info and City.inRect(info.rect, p.X, p.Z, 40) then return Drive.place("hq_entrance", plot), nil end
	end
	if zone == "abroad" then
		for _, rect in Drive.PM_STAND_AREA do
			if City.inRect(rect, p.X, p.Z, 12) then return Drive.place("pm_limo"), nil end
		end
	end
	local best: Place? = nil
	local bestD = math.huge
	for _, place in Drive.places(zone, plot) do
		if place.kind == "garage" then continue end
		local r = Drive.PICKUP_RADIUS[place.pickup or "building"] or 90
		local d = math.min(flat(p, place.door.Position), flat(p, place.stop.Position))
		if d <= r and d < bestD then best, bestD = place, d end
	end
	if best then return best, nil end
	return nil, "TOO_FAR"
end
-- The pick-up place nearest to a position whatever the distance (for "walk to ... first"), and that distance.
function Drive.nearestAny(p: Vector3, zone: string, plot: number?): (Place?, number)
	local best: Place? = nil
	local bestD = math.huge
	for _, place in Drive.places(zone, plot) do
		if place.kind == "garage" then continue end
		local d = math.min(flat(p, place.door.Position), flat(p, place.stop.Position))
		if d < bestD then best, bestD = place, d end
	end
	return best, bestD
end

------------------------------------------------------------------------------------------------ routing
type Ctrl = { pts: { Vector3 }, offs: { number }, cls: { string } } -- segment i = pts[i] -> pts[i+1]

local function addPts(c: Ctrl, pts: { Vector3 }, classes: { string }, from: number?)
	for i = from or 1, #pts do
		if #c.pts > 0 then
			table.insert(c.offs, 0)
			table.insert(c.cls, classes[i] ~= "" and classes[i] or "access")
		end
		table.insert(c.pts, pts[i])
	end
end
local function addRoad(c: Ctrl, p: Vector3, off: number)
	table.insert(c.offs, off)
	table.insert(c.cls, "road")
	table.insert(c.pts, p)
end

-- Directed shortest path on graph g from point S (on edge sEdge, param sT) to point E (on edge eEdge, param eT).
-- sDir / eDir: +1 = travel a->b, -1 = b->a, 0 = either. Returns the node list between S and E and the start /
-- end travel directions, or nil. Dijkstra over states (node, previous node) with a binary heap ordered by (cost,
-- state key) - a strict total order, so the server and every client find the identical route - and parent links
-- instead of copied paths.
type Search = { nodes: { string }, sd: number, ed: number }
type HState = { node: string, prev: string, cost: number, parent: HState?, sd: number, key: string }
local function hless(a: HState, b: HState): boolean
	if a.cost ~= b.cost then return a.cost < b.cost end
	return a.key < b.key
end
local function hpush(h: { HState }, st: HState)
	table.insert(h, st)
	local i = #h
	while i > 1 do
		local up = i // 2
		if hless(h[i], h[up]) then
			h[i], h[up] = h[up], h[i]
			i = up
		else
			break
		end
	end
end
local function hpop(h: { HState }): HState
	local top = h[1]
	local last = table.remove(h) :: HState
	local n = #h
	if n > 0 then
		h[1] = last
		local i = 1
		while true do
			local l, r = 2 * i, 2 * i + 1
			local m = i
			if l <= n and hless(h[l], h[m]) then m = l end
			if r <= n and hless(h[r], h[m]) then m = r end
			if m == i then break end
			h[i], h[m] = h[m], h[i]
			i = m
		end
	end
	return top
end
local function pathOf(st: HState): { string }
	local rev: { string } = {}
	local cur: HState? = st
	while cur do
		table.insert(rev, cur.node)
		cur = cur.parent
	end
	local out: { string } = table.create(#rev)
	for i = #rev, 1, -1 do table.insert(out, rev[i]) end
	return out
end
local function search(g: Graph, sEdge: number, sT: number, sDir: number, eEdge: number, eT: number, eDir: number): Search?
	local se, ee = g.edges[sEdge], g.edges[eEdge]
	local best: Search? = nil
	local bestState: HState? = nil
	local bestSd, bestEd = 0, 0
	local bestCost = math.huge
	-- same edge, E ahead of S in an allowed direction: drive straight there
	if sEdge == eEdge then
		for _, d in { 1, -1 } do
			if (sDir == 0 or sDir == d) and (eDir == 0 or eDir == d) and ((d == 1 and eT >= sT) or (d == -1 and eT <= sT)) then
				local cost = math.abs(eT - sT) * se.len
				if cost < bestCost then bestCost = cost; best = { nodes = {}, sd = d, ed = d }; bestState = nil end
			end
		end
	end
	-- U-turns at a node cost Drive.UTURN
	local open: { HState } = {}
	for _, d in { 1, -1 } do
		if sDir == 0 or sDir == d then
			local node = if d == 1 then se.b else se.a
			local prev = if d == 1 then se.a else se.b
			local cost = (if d == 1 then (1 - sT) else sT) * se.len
			hpush(open, { node = node, prev = prev, cost = cost, parent = nil, sd = d, key = node .. ">" .. prev })
		end
	end
	local done: { [string]: boolean } = {}
	while #open > 0 do
		local st = hpop(open)
		if st.cost >= bestCost then break end
		if done[st.key] then continue end
		done[st.key] = true
		-- reached the start node of E's edge in an allowed direction?
		for _, d in { 1, -1 } do
			if eDir == 0 or eDir == d then
				local entry = if d == 1 then ee.a else ee.b
				local other = if d == 1 then ee.b else ee.a
				if st.node == entry then
					local extra = (if d == 1 then eT else (1 - eT)) * ee.len
					if st.prev == other then extra += Drive.UTURN end
					local total = st.cost + extra
					if total < bestCost then bestCost = total; best = nil; bestState = st; bestSd = st.sd; bestEd = d end
				end
			end
		end
		for _, n in g.adj[st.node] do
			local key = n.to .. ">" .. st.node
			if done[key] then continue end
			local cost = st.cost + g.edges[n.e].len + (if n.to == st.prev then Drive.UTURN else 0)
			hpush(open, { node = n.to, prev = st.node, cost = cost, parent = st, sd = st.sd, key = key })
		end
	end
	if bestState then return { nodes = pathOf(bestState), sd = bestSd, ed = bestEd } end
	return best
end

local function edgeBetween(g: Graph, a: string, b: string): Edge?
	for _, n in g.adj[a] do if n.to == b then return g.edges[n.e] end end
	return nil
end

-- Control polyline of the network part: from the out mouth of `from` to the in mouth of `to`.
local function networkCtrl(c: Ctrl, g: Graph, from: Place, to: Place): string?
	local mOut = from.outPts[#from.outPts]
	local mIn = to.inPts[1]
	local sEdge, sQ, sT = snap(g, mOut)
	local eEdge, eQ, eT = snap(g, mIn)
	if sEdge == 0 or eEdge == 0 then return "NO_ROUTE" end
	local function dirOf(place: Place, edge: Edge, a: Vector3, b: Vector3): number
		if place.dirs ~= 1 then return 0 end
		local hx, hz = dir2(a, b)
		local ex, ez = dir2(g.nodes[edge.a], g.nodes[edge.b])
		return if hx * ex + hz * ez >= 0 then 1 else -1
	end
	local se, ee = g.edges[sEdge], g.edges[eEdge]
	local n = #from.outPts
	local sDir = dirOf(from, se, from.outPts[math.max(1, n - 1)], from.outPts[n])
	local eDir = dirOf(to, ee, to.inPts[1], to.inPts[math.min(#to.inPts, 2)])
	local r = search(g, sEdge, sT, sDir, eEdge, eT, eDir)
	if not r then return "NO_ROUTE" end
	-- both mouths on the same lane line at the same point (kerbs of one road): connect them directly
	if #r.nodes == 0 and flat(sQ, eQ) < 2 then return nil end
	-- mouth -> S (perpendicular stub, offset 0), S -> nodes -> E along the lanes, E -> mouth (stub)
	addPts(c, { sQ }, { "access" })
	local prevNode: string? = nil
	for i, id in r.nodes do
		local e: Edge? = if i == 1 then se else edgeBetween(g, prevNode :: string, id)
		addRoad(c, g.nodes[id], if e then e.off else 10)
		prevNode = id
	end
	addRoad(c, eQ, ee.off)
	return nil
end

------------------------------------------------------------------------------------------------ lane polyline + fillets
type Sample = { p: Vector3, r: number, c: string }

local function corner(pts: { Vector3 }, offs: { number }, classes: { string }): ({ Vector3 }, { string })
	local n = #pts
	local L: { Vector3 } = {}
	local LC: { string } = {} -- class of the segment ending at L[i]
	local function push(p: Vector3, c: string)
		local last = L[#L]
		if last and (last - p).Magnitude < 0.05 then return end
		table.insert(L, p)
		table.insert(LC, c)
	end
	local dx, dz, rx, rz = {}, {}, {}, {}
	for i = 1, n - 1 do
		local x, z = dir2(pts[i], pts[i + 1])
		dx[i], dz[i], rx[i], rz[i] = x, z, -z, x
	end
	push(pts[1] + Vector3.new(rx[1] * offs[1], 0, rz[1] * offs[1]), classes[1])
	for k = 2, n - 1 do
		local a, b = k - 1, k
		local o1, o2 = offs[a], offs[b]
		local v = pts[k]
		local ax, az = v.X + rx[a] * o1, v.Z + rz[a] * o1
		local bx, bz = v.X + rx[b] * o2, v.Z + rz[b] * o2
		local cross = dx[a] * dz[b] - dz[a] * dx[b]
		local dot = dx[a] * dx[b] + dz[a] * dz[b]
		local cl = classes[a]
		if math.abs(cross) > 0.03 then
			-- intersection of the two lane lines
			local wx, wz = bx - ax, bz - az
			local t = (wx * dz[b] - wz * dx[b]) / cross
			local px, pz = ax + dx[a] * t, az + dz[a] * t
			local lim = 3 * math.max(math.abs(o1), math.abs(o2)) + 8
			if math.abs(px - v.X) + math.abs(pz - v.Z) > 2 * lim then px, pz = (ax + bx) / 2, (az + bz) / 2 end
			push(Vector3.new(px, v.Y, pz), cl)
		elseif dot > 0 then
			if math.abs(o1 - o2) < 0.1 then
				push(Vector3.new(ax, v.Y, az), cl)
			else -- lane change on a straight
				local l = 2 * math.abs(o1 - o2) + 4
				push(Vector3.new(ax - dx[a] * l, v.Y, az - dz[a] * l), cl)
				push(Vector3.new(bx + dx[a] * l, v.Y, bz + dz[a] * l), classes[b])
			end
		else -- U-turn at this vertex: swing across in front of it (at most Drive.UTURN_SWING past the junction, so a
			-- U-turn across the wide boulevard stays inside the cross street instead of cutting into the plaza beyond)
			local u = math.clamp((math.abs(o1) + math.abs(o2)) / 2, 6, Drive.UTURN_SWING)
			push(Vector3.new(ax + dx[a] * u, v.Y, az + dz[a] * u), cl)
			push(Vector3.new(bx + dx[a] * u, v.Y, bz + dz[a] * u), classes[b])
		end
	end
	push(pts[n] + Vector3.new(rx[n - 1] * offs[n - 1], 0, rz[n - 1] * offs[n - 1]), classes[n - 1])
	-- drop collinear interior points
	local out: { Vector3 } = { L[1] }
	local oc: { string } = { LC[1] }
	for i = 2, #L - 1 do
		local p0, p1, p2 = out[#out], L[i], L[i + 1]
		local x1, z1 = dir2(p0, p1)
		local x2, z2 = dir2(p1, p2)
		if math.abs(x1 * z2 - z1 * x2) < 0.004 and x1 * x2 + z1 * z2 > 0 and LC[i] == LC[i + 1] and math.abs((p1.Y - p0.Y) / math.max(flat(p0, p1), 0.01) - (p2.Y - p1.Y) / math.max(flat(p1, p2), 0.01)) < 0.01 then
			continue
		end
		table.insert(out, p1)
		table.insert(oc, LC[i])
	end
	table.insert(out, L[#L])
	table.insert(oc, LC[#LC])
	return out, oc
end

local function slower(a: string, b: string): string
	return if (Drive.SPEED[a] or 99) <= (Drive.SPEED[b] or 99) then a else b
end

local function fillet(L: { Vector3 }, LC: { string }): { Sample }
	local n = #L
	local out: { Sample } = {}
	local function addStraight(a: Vector3, b: Vector3, c: string, includeEnd: boolean)
		local len = (b - a).Magnitude
		local steps = math.max(1, math.ceil(len / Drive.STEP))
		local last = out[#out]
		if not last or (last.p - a).Magnitude > 0.05 then table.insert(out, { p = a, r = math.huge, c = c }) end
		for i = 1, steps - 1 do table.insert(out, { p = a:Lerp(b, i / steps), r = math.huge, c = c }) end
		if includeEnd then table.insert(out, { p = b, r = math.huge, c = c }) end
	end
	-- tangent points of every interior corner
	type Arc = { t1: Vector3, t2: Vector3, r: number, cx: number, cz: number, a1: number, sweep: number, ok: boolean }
	local arcs: { [number]: Arc } = {}
	for k = 2, n - 1 do
		local p0, p1, p2 = L[k - 1], L[k], L[k + 1]
		local x1, z1 = dir2(p0, p1)
		local x2, z2 = dir2(p1, p2)
		local dot = math.clamp(x1 * x2 + z1 * z2, -1, 1)
		local theta = math.acos(dot)
		if theta < math.rad(1) then continue end
		local tn = math.tan(theta / 2)
		local inLen, outLen = flat(p0, p1), flat(p1, p2)
		local availIn = if k - 1 == 1 then inLen * 0.9 else inLen * 0.5
		local availOut = if k + 1 == n then outLen * 0.9 else outLen * 0.5
		local T = math.min(Drive.FILLET * tn, availIn, availOut)
		local R = T / tn
		local t1 = Vector3.new(p1.X - x1 * T, 0, p1.Z - z1 * T)
		local t2 = Vector3.new(p1.X + x2 * T, 0, p1.Z + z2 * T)
		-- y on the straights at the tangent points
		local y1 = p1.Y + (p0.Y - p1.Y) * (T / math.max(inLen, 1e-6))
		local y2 = p1.Y + (p2.Y - p1.Y) * (T / math.max(outLen, 1e-6))
		t1 = Vector3.new(t1.X, y1, t1.Z)
		t2 = Vector3.new(t2.X, y2, t2.Z)
		local side = if x1 * z2 - z1 * x2 > 0 then 1 else -1 -- +1: turning towards the right-hand normal
		local nx, nz = -z1 * side, x1 * side
		local cx, cz = t1.X + nx * R, t1.Z + nz * R
		local a1 = math.atan2(t1.Z - cz, t1.X - cx)
		local a2 = math.atan2(t2.Z - cz, t2.X - cx)
		local sweep = a2 - a1
		if side > 0 then
			while sweep < 0 do sweep += 2 * math.pi end
		else
			while sweep > 0 do sweep -= 2 * math.pi end
		end
		arcs[k] = { t1 = t1, t2 = t2, r = R, cx = cx, cz = cz, a1 = a1, sweep = sweep, ok = R > 0.05 }
	end
	local cur = L[1]
	for k = 2, n do
		local c = LC[k]
		local arc = arcs[k]
		if k == n then
			addStraight(cur, L[n], c, true)
		elseif arc and arc.ok then
			addStraight(cur, arc.t1, c, false)
			local steps = math.max(2, math.ceil(math.abs(arc.sweep) / math.rad(7)))
			local cc = slower(c, LC[k + 1])
			for i = 0, steps do
				local a = arc.a1 + arc.sweep * i / steps
				local y = arc.t1.Y + (arc.t2.Y - arc.t1.Y) * i / steps
				table.insert(out, { p = Vector3.new(arc.cx + arc.r * math.cos(a), y, arc.cz + arc.r * math.sin(a)), r = arc.r, c = cc })
			end
			cur = arc.t2
		else
			addStraight(cur, L[k], c, false)
			cur = L[k]
		end
	end
	return out
end

-- speed profile + time stamps
local function profile(samples: { Sample }, key: string, from: string, to: string): Leg
	local n = #samples
	local pts: { Vector3 } = {}
	local cum: { number } = {}
	local vmax: { number } = {}
	local s = 0
	for i, smp in samples do
		if i > 1 then s += (smp.p - samples[i - 1].p).Magnitude end
		pts[i] = smp.p
		cum[i] = s
		local cruise = Drive.SPEED[smp.c] or Drive.SPEED.access
		vmax[i] = math.min(cruise, math.sqrt(Drive.A_LAT * math.min(smp.r, 1e6)))
	end
	local v: { number } = table.create(n, 0)
	v[1] = 0
	for i = 2, n do v[i] = math.min(vmax[i], math.sqrt(v[i - 1] ^ 2 + 2 * Drive.ACCEL * (cum[i] - cum[i - 1]))) end
	v[n] = 0
	for i = n - 1, 1, -1 do v[i] = math.min(v[i], math.sqrt(v[i + 1] ^ 2 + 2 * Drive.DECEL * (cum[i + 1] - cum[i]))) end
	v[1] = 0
	local t: { number } = table.create(n, 0)
	for i = 2, n do
		local ds = cum[i] - cum[i - 1]
		t[i] = t[i - 1] + ds / math.max((v[i] + v[i - 1]) / 2, 0.6)
	end
	return { key = key, from = from, to = to, pts = pts, cum = cum, t = t, v = v, len = s, dur = t[n] }
end

-- Leg cache: legs between static places (airport, Business City, Port Meridian) are shared by every plot; a leg
-- with an HQ end is kept per plot. Least recently used legs are dropped (half at a time) above Drive.LEG_CACHE.
local legCache: { [string]: Leg } = {}
local legUsed: { [string]: number } = {}
local legCount = 0
local legTick = 0
local function cachePut(key: string, leg: Leg)
	if legCache[key] == nil then legCount += 1 end
	legCache[key] = leg
	legTick += 1
	legUsed[key] = legTick
	if legCount > Drive.LEG_CACHE then
		local keys: { string } = {}
		for k in legCache do table.insert(keys, k) end
		table.sort(keys, function(a, b) return (legUsed[a] or 0) < (legUsed[b] or 0) end)
		local drop = #keys // 2
		for i = 1, drop do
			legCache[keys[i]] = nil
			legUsed[keys[i]] = nil
		end
		legCount = #keys - drop
	end
end
function Drive.legCacheSize(): number
	return legCount
end

-- Leg between two places. `fromSide` = "drop" when the car stands at the drop-off stop of `from` (only the HQ
-- entrance has a separate drop-off; a car there can only go back to the garage).
function Drive.leg(fromId: string, toId: string, plot: number?, fromSide: string?): (Leg?, string?)
	local side = if fromSide == "drop" then "drop" else "stop"
	local perPlot = string.sub(fromId, 1, 3) == "hq_" or string.sub(toId, 1, 3) == "hq_"
	local key = fromId .. ":" .. side .. ">" .. toId .. "#" .. (if perPlot then tostring(plot) else "*")
	local cached = legCache[key]
	if cached then
		legTick += 1
		legUsed[key] = legTick
		return cached, nil
	end
	if fromId == toId then return nil, "SAME_PLACE" end
	local from, to = Drive.place(fromId, plot), Drive.place(toId, plot)
	if not from or not to then return nil, "BAD_PLACE" end
	if from.zone ~= to.zone then return nil, "FLIGHT_REQUIRED" end
	local c: Ctrl = { pts = {}, offs = {}, cls = {} }
	local cf = if plot then plotCF(plot) else nil
	if fromId == "hq_garage" and toId == "hq_entrance" and cf then
		local gOut, gOutCls = hqPoints(cf)
		addPts(c, gOut, gOutCls)
	elseif fromId == "hq_entrance" and toId == "hq_garage" and cf then
		if side == "drop" then
			local _, _, _, _, _, _, dPark, dParkCls = hqPoints(cf)
			addPts(c, dPark, dParkCls)
		else
			local pts, classes = hqUturn(cf)
			addPts(c, pts, classes)
		end
	else
		if side == "drop" and from.kind == "hq" then return nil, "BAD_PLACE" end
		local g = Drive.graph(from.zone)
		if fromId == "hq_garage" and cf then
			-- the garage exit runs through the HQ pick-up position and on to the mouth
			local gOut, gOutCls, sOut, sOutCls = hqPoints(cf)
			addPts(c, gOut, gOutCls)
			addPts(c, sOut, sOutCls, 2)
		else
			addPts(c, from.outPts, from.outCls)
		end
		local err = networkCtrl(c, g, from, to)
		if err then return nil, err end
		if toId == "hq_garage" and cf then
			local _, _, _, _, mIn, mInCls, dPark, dParkCls = hqPoints(cf)
			addPts(c, mIn, mInCls)
			addPts(c, dPark, dParkCls, 2)
		else
			addPts(c, to.inPts, to.inCls)
		end
	end
	-- drop zero-length control segments (a mouth exactly on a road line etc.)
	local pts: { Vector3 } = { c.pts[1] }
	local offs: { number } = {}
	local classes: { string } = {}
	for i = 2, #c.pts do
		if (c.pts[i] - pts[#pts]).Magnitude > 0.05 then
			table.insert(pts, c.pts[i])
			table.insert(offs, c.offs[i - 1])
			table.insert(classes, c.cls[i - 1])
		end
	end
	if #pts < 2 then return nil, "NO_ROUTE" end
	if from.zone == "abroad" then
		-- Port Meridian: the road class keeps the city traffic's pace
		for i, cl in classes do if cl == "road" then classes[i] = "metro" end end
	end
	local L, LC = corner(pts, offs, classes)
	local leg = profile(fillet(L, LC), key, fromId, toId)
	cachePut(key, leg)
	return leg, nil
end

------------------------------------------------------------------------------------------------ playback
local function bsearch(arr: { number }, x: number): number
	local lo, hi = 1, #arr
	if x <= arr[1] then return 1 end
	if x >= arr[hi] then return hi - 1 end
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if arr[mid] <= x then lo = mid else hi = mid end
	end
	return lo
end
-- Position at distance s along the leg.
function Drive.posAt(leg: Leg, s: number): Vector3
	local n = #leg.pts
	if n == 1 then return leg.pts[1] end
	local x = math.clamp(s, 0, leg.len)
	local i = bsearch(leg.cum, x)
	local a, b = leg.cum[i], leg.cum[i + 1]
	local f = if b > a then (x - a) / (b - a) else 0
	return leg.pts[i]:Lerp(leg.pts[i + 1], f)
end
-- Distance along the leg after `t` seconds (constant acceleration inside each sample interval, so a car really
-- starts from a standstill and rolls to a stop).
function Drive.distAt(leg: Leg, t: number): number
	local n = #leg.t
	if t <= 0 or n < 2 then return 0 end
	if t >= leg.dur then return leg.len end
	local i = bsearch(leg.t, t)
	local t0, t1 = leg.t[i], leg.t[i + 1]
	local ds = leg.cum[i + 1] - leg.cum[i]
	local dt = t1 - t0
	if dt <= 0 then return leg.cum[i + 1] end
	local tau = t - t0
	local v0, v1 = leg.v[i], leg.v[i + 1]
	if math.abs((v0 + v1) / 2 * dt - ds) < 1e-6 * math.max(1, ds) then
		local a = (v1 - v0) / dt
		return leg.cum[i] + v0 * tau + 0.5 * a * tau * tau
	end
	return leg.cum[i] + ds * tau / dt -- crawling interval (minimum speed clamp): uniform
end
-- Car pivot CFrame at distance s along the leg for a car with wheelbase `wb`: the pivot stays on the path in plan
-- view, its height is the mean of the two axle points and the body points from the rear axle to the front axle, so
-- the car pitches with a ramp only as far as both axles really are on it (no bumper digging into the floor where
-- the ramp meets the garage).
function Drive.poseAtDist(leg: Leg, s: number, wb: number?): CFrame
	local half = (wb or Drive.WHEELBASE.fleet) / 2
	local p = Drive.posAt(leg, s)
	local a = Drive.posAt(leg, s - half)
	local b = Drive.posAt(leg, s + half)
	local d = b - a
	if d.Magnitude < 1e-3 then
		local n = #leg.pts
		d = if n >= 2 then leg.pts[n] - leg.pts[n - 1] else Vector3.new(0, 0, -1)
		if d.Magnitude < 1e-3 then d = Vector3.new(0, 0, -1) end
	end
	local q = Vector3.new(p.X, (a.Y + b.Y) / 2, p.Z)
	return CFrame.lookAt(q, q + d.Unit)
end
-- Car pivot CFrame (+ speed, distance) `t` seconds after the leg started.
function Drive.at(leg: Leg, t: number, wb: number?): (CFrame, number, number)
	local s = Drive.distAt(leg, t)
	local speed = 0
	if t > 0 and t < leg.dur then
		local s2 = Drive.distAt(leg, t + 0.1)
		speed = (s2 - s) / 0.1
	end
	return Drive.poseAtDist(leg, s, wb), speed, s
end
-- Pose at the very end of a leg (where the car stops).
function Drive.endCF(leg: Leg, wb: number?): CFrame
	return Drive.poseAtDist(leg, leg.len, wb)
end

------------------------------------------------------------------------------------------------ seats + looks
-- Seat offsets in the car frame (pivot = centre at ground level, -Z forward, +X right). R6 rigs sit with the
-- root 1.5 above the seat surface (EmployeeController.pose hips at pi/2); the head (with a driver's cap) reaches
-- 2.32 above the root, under the cars' roofs (DriveController SHAPES, roof underside >= 4.95).
Drive.SEATS = {
	fleet = { driver = CFrame.new(-1.55, 2.6, -0.6), front = CFrame.new(1.55, 2.6, -0.6), rearL = CFrame.new(-1.55, 2.6, 3.0), rearR = CFrame.new(1.55, 2.6, 3.0) },
	limo = { driver = CFrame.new(-1.6, 2.6, -2.6), front = CFrame.new(1.6, 2.6, -2.6), rearL = CFrame.new(-1.6, 2.6, 4.4), rearR = CFrame.new(1.6, 2.6, 4.4) },
} :: { [string]: { [string]: CFrame } }
-- "View" camera on the back seat: the middle of the rear bench, between the two rear occupants' heads (DriveController
-- uses the rear seat z of the car's own seat table; the local founder clone's head is hidden in this view)
Drive.CAMERA = {
	chase = CFrame.new(0, 9, 26) * CFrame.Angles(math.rad(-14), 0, 0),
	inside = CFrame.new(0, 3.75, 3.1) * CFrame.Angles(math.rad(-4), 0, 0),
} :: { [string]: CFrame }
-- Seated occupants are scaled down (Model:ScaleTo): an R6 rig is 4 studs wide over the arms, so at full size two
-- people side by side and the side glass cannot both be cleared. Drive.seatFit(glassHalf) -> (scale, x): the largest
-- scale <= RIG_SCALE whose outer arm stays inside the glass (half width glassHalf), x = 2 * scale (the inner arms of
-- two neighbours just touch). The root stands 1.5 * scale above the cushion (Drive.SEAT_SURFACE).
Drive.RIG_SCALE = 0.8
Drive.SEAT_SURFACE = 1.1
function Drive.seatFit(glassHalf: number): (number, number)
	-- 0.12 studs of margin for gloves / cuffs that stand a little proud of the R6 arm box
	local sc = math.min(Drive.RIG_SCALE, (glassHalf - 0.12) / 4)
	return sc, 2 * sc + 0.01
end
-- Rig root of a seated occupant in the car frame (seat key of Drive.SEATS, the car's look, its glass half width).
function Drive.seatCF(seat: string, look: string, glassHalf: number): CFrame
	local base = Drive.SEATS[if look == "limo" then "limo" else "fleet"][seat] or CFrame.new()
	local sc, x = Drive.seatFit(glassHalf)
	local side = if base.Position.X < 0 then -1 else 1
	return CFrame.new(side * x, Drive.SEAT_SURFACE + 1.5 * sc, base.Position.Z) * base.Rotation
end
-- Look of the car a ride uses: the founder's own company car when the driver takes it from the pick-up bay,
-- else the fleet sedan (company colour) / the VIP limousine abroad.
function Drive.look(id: any): string
	if typeof(id) == "string" and (id == "limo" or Drive.CAR_LENGTH[id] ~= nil) then return id end
	return "fleet"
end
function Drive.seatsOf(look: string): { [string]: CFrame }
	return Drive.SEATS[if look == "limo" then "limo" else "fleet"]
end

------------------------------------------------------------------------------------------------ ride plans
-- A ride is a short list of legs ("segments") with server start times; the car stands at the end of a segment until
-- the next one starts (waiting at the pick-up, at the destination). DriverService publishes it ONCE per change as a
-- string attribute (Drive.encode) and every client poses the car from it (Drive.pose), so nothing moves over the
-- network per frame. who = the occupants in seat order (Drive.SEAT_ORDER), comma separated: "D" the driver
-- (template Driver<i> / Chauffeur), "R" the rider (the founder: a stand-in of his character), "C1".."C3" companions,
-- "G1"/"G2" client guests (templates in the ride folder), "" an empty seat.
export type Seg = { from: string, to: string, side: string?, t0: number, who: string }
Drive.SEAT_ORDER = { "driver", "rearR", "rearL", "front" } :: { string }
Drive.MAX_SEGS = 6
Drive.OCCUPANTS = { D = true, R = true, C1 = true, C2 = true, C3 = true, G1 = true, G2 = true } :: { [string]: boolean }

local function validWho(who: string): boolean
	if #who > 24 then return false end
	local n = 0
	for code in string.gmatch(who .. ",", "([^,]*),") do
		n += 1
		if code ~= "" and not Drive.OCCUPANTS[code] then return false end
	end
	return n <= #Drive.SEAT_ORDER
end
-- "hq_garage>hq_entrance|D@1700000000.25;hq_entrance>airport_departures|D,R@1700000031.50" (side "drop" = "~d")
function Drive.encode(segs: { Seg }): string
	local parts: { string } = {}
	for _, sg in segs do
		table.insert(parts, string.format("%s>%s%s|%s@%.2f", sg.from, sg.to, if sg.side == "drop" then "~d" else "", sg.who, sg.t0))
	end
	return table.concat(parts, ";")
end
-- Parse + validate (places exist for this plot, legs route, start times rise); nil for anything malformed.
function Drive.decode(str: any, plot: number?): { Seg }?
	if typeof(str) ~= "string" or #str > 600 then return nil end
	if str == "" then return {} end
	local out: { Seg } = {}
	local last = -math.huge
	for item in string.gmatch(str .. ";", "([^;]*);") do
		local from, to, drop, who, t = string.match(item, "^([%w_]+)>([%w_]+)(~?d?)|([%w,]*)@([%d%.%-]+)$")
		local t0 = tonumber(t)
		if not from or not to or not t0 or t0 ~= t0 or not validWho(who :: string) then return nil end
		if drop ~= "" and drop ~= "~d" then return nil end
		if t0 < last then return nil end
		last = t0
		local side = if drop == "~d" then "drop" else nil
		if not Drive.leg(from :: string, to :: string, plot, side) then return nil end
		table.insert(out, { from = from :: string, to = to :: string, side = side, t0 = t0, who = who :: string })
		if #out > Drive.MAX_SEGS then return nil end
	end
	return out
end
-- Seats of a who string: {driver = "D", rearR = "R", ...} (empty seats left out).
function Drive.seating(who: string): { [string]: string }
	local out: { [string]: string } = {}
	local i = 0
	for code in string.gmatch(who .. ",", "([^,]*),") do
		i += 1
		local seat = Drive.SEAT_ORDER[i]
		if seat and code ~= "" then out[seat] = code end
	end
	return out
end
function Drive.segLeg(sg: Seg, plot: number?): Leg?
	local leg = Drive.leg(sg.from, sg.to, plot, sg.side)
	return leg
end
-- Server time when segment i ends (its leg's duration after its start).
function Drive.segEnd(sg: Seg, plot: number?): number
	local leg = Drive.segLeg(sg, plot)
	return sg.t0 + (if leg then leg.dur else 0)
end
-- When the last segment ends (the car is parked again), or nil for an empty plan.
function Drive.planEnd(segs: { Seg }, plot: number?): number?
	local n = #segs
	if n == 0 then return nil end
	return Drive.segEnd(segs[n], plot)
end
export type Pose = { cf: CFrame, index: number, phase: string, speed: number, who: string, place: string }
-- Where the car of a plan is at server time t: phase "before" (driver walking to the car: parked at the start of
-- segment 1), "moving" (segment `index` running), "waiting" (standing at the end of segment `index` until the next
-- starts), "done" (after the last segment). place = the place the car stands at / drives to. wb = wheelbase.
function Drive.pose(segs: { Seg }, plot: number?, t: number, wb: number?): Pose?
	local n = #segs
	if n == 0 then return nil end
	local first = segs[1]
	if t < first.t0 then
		local leg = Drive.segLeg(first, plot)
		if not leg then return nil end
		return { cf = Drive.poseAtDist(leg, 0, wb), index = 1, phase = "before", speed = 0, who = first.who, place = first.from }
	end
	for i = n, 1, -1 do
		local sg = segs[i]
		if t >= sg.t0 then
			local leg = Drive.segLeg(sg, plot)
			if not leg then return nil end
			local tau = t - sg.t0
			if tau < leg.dur then
				local cf, speed = Drive.at(leg, tau, wb)
				return { cf = cf, index = i, phase = "moving", speed = speed, who = sg.who, place = sg.to }
			end
			return { cf = Drive.endCF(leg, wb), index = i, phase = if i == n then "done" else "waiting", speed = 0, who = sg.who, place = sg.to }
		end
	end
	return nil
end

------------------------------------------------------------------------------------------------ company drivers
-- Company drivers on the payroll: exactly CompanyOps' rule (Ops.step pays (posts + drivers) x OPS_WAGE with
-- drivers = 2 from Ops.DRIVER.more, 1 from Ops.DRIVER.from, else 0). No company (or no empire) = 0.
function Drive.drivers(e: any): number
	if typeof(e) ~= "table" then return 0 end
	local stage = Ops.stageIndex(e)
	return if stage >= Ops.DRIVER.more then 2 elseif stage >= Ops.DRIVER.from then 1 else 0
end
Drive.FIRST_DRIVER_STAGE = Ops.DRIVER.from
-- Working hours (user request 2): CompanyOps pays the drivers a fixed daily wage for an on-call chauffeur service
-- around the clock. 06:00-22:00 (company clock, CompanyOps.hour of the server time) they wait under the entrance
-- canopy; at night they are on call in the drivers' room, so a car needs Drive.WALK_NIGHT instead of Drive.WALK.
function Drive.onPost(clock: number): boolean
	local h = Ops.hour(clock)
	return h >= Drive.POST_HOURS.from and h < Drive.POST_HOURS.to
end
function Drive.walkAt(clock: number): number
	return if Drive.onPost(clock) then Drive.WALK else Drive.WALK_NIGHT
end

------------------------------------------------------------------------------------------------ getting out
local function onAnyRoad(zone: string, x: number, z: number, m: number): boolean
	if zone == "abroad" then
		for _, r in Metro.ROADS do
			local rr = Metro.roadRect(r)
			if x >= rr.x1 - m and x <= rr.x2 + m and z >= rr.z1 - m and z <= rr.z2 + m then return true end
		end
		return false
	end
	return City.onRoad(Vector3.new(x, 0, z), m)
end
-- Where a passenger may stand after getting out of a car at pose cf in the middle of a ride ("let me out here"):
-- off the asphalt on the car's right (kerb) side, on the sidewalk (WALK_TOP + 3), facing the car's heading; then the
-- other side, then stepping along the road (16 studs at a time). Inside a plot site (driveway / ramp / garage) only
-- the HQ's own alight point. In order of preference; DriverService takes the first one that is free of props
-- (workspace:GetPartBoundsInBox - this module is pure and does not see the world).
function Drive.kerbCandidates(cf: CFrame, zone: string, plot: number?): { CFrame }
	local p = cf.Position
	if zone == "home" and plot then
		local info = City.plots()[plot]
		if info and City.inRect(info.rect, p.X, p.Z, 8) then
			return { info.cframe * Drive.HQ.alight }
		end
	end
	local f = cf.LookVector
	local fx, fz = f.X, f.Z
	local fl = math.sqrt(fx * fx + fz * fz)
	if fl < 1e-6 then fx, fz, fl = 0, -1, 1 end
	fx, fz = fx / fl, fz / fl
	local rx, rz = -fz, fx -- right-hand side (kerb side in right-hand traffic)
	local out: { CFrame } = {}
	for _, along in { 0, -16, 16, -32, 32, -48, 48 } do
		local bx, bz = p.X + fx * along, p.Z + fz * along
		for _, side in { 1, -1 } do
			local d = 4
			while d <= 30 and onAnyRoad(zone, bx + rx * side * d, bz + rz * side * d, 0) do d += 1 end
			if d <= 30 then
				local q = Vector3.new(bx + rx * side * (d + 2.5), WT + 3, bz + rz * side * (d + 2.5))
				table.insert(out, CFrame.lookAt(q, q + Vector3.new(fx, 0, fz)))
			end
		end
	end
	if #out == 0 then
		local q = Vector3.new(p.X + rx * 6, WT + 3, p.Z + rz * 6)
		table.insert(out, CFrame.lookAt(q, q + Vector3.new(fx, 0, fz)))
	end
	return out
end
-- The preferred spot of Drive.kerbCandidates.
function Drive.kerbSide(cf: CFrame, zone: string, plot: number?): CFrame
	return Drive.kerbCandidates(cf, zone, plot)[1]
end

------------------------------------------------------------------------------------------------ texts
function Drive.clock(seconds: number): string
	local s = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", s // 60, s % 60)
end
-- A place's name inside a sentence: "waiting for you at the HQ entrance", "... at City Airport (departures)"
function Drive.atName(place: Place): string
	return if place.kind == "hq" or place.kind == "limo" or place.kind == "garage" then "the " .. place.name else place.name
end
-- "To City Airport · 0:48"
function Drive.hudText(placeName: string, seconds: number): string
	return "To " .. placeName .. " · " .. Drive.clock(seconds)
end
-- Name of the stage where the first driver joins (EmpireConfig.OFFICES[from].name is read by the caller).
Drive.CAMPUS_STREET_Y = Campus.STREET_Y

return Drive
