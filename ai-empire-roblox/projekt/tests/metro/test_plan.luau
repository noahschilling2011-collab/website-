--!nocheck
-- Metro package: MetroPlan layout + networks (pure data, no instances).
--   lots inside the city, off roads / sidewalks / reserved areas, no overlaps, skyline below the landmark;
--   walk graphs connected, never inside a building and never on the asphalt except at crossings, node heights =
--   surface heights; crossings carry a junction; lanes inside the carriageway; signal phases never conflict;
--   benches / spots / VIP markers / helipads where they belong; far skyline outside the walls and off the sea;
--   districts cover the city.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_metro && tools/luau tests/metro/test_plan.luau [-a .gen_dir]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_metro")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
M.loadTree(manifest, sources)
M.quiet = true
local G = M.G
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local function body()
	local Vector3 = G.Vector3
	local RS = M.game.ReplicatedStorage
	local Plan = M.require(RS.Shared.Config.MetroPlan)
	local City = M.require(RS.Shared.Config.CityPlan)
	local A = City.ABROAD
	local R = A.rect
	local function ov(a, b) return a.x1 < b.x2 and a.x2 > b.x1 and a.z1 < b.z2 and a.z2 > b.z1 end
	local function inside(r, x, z, m) m = m or 0; return x > r.x1 + m and x < r.x2 - m and z > r.z1 + m and z < r.z2 - m end
	local function lotRect(l) return { x1 = l.x - l.w / 2, x2 = l.x + l.w / 2, z1 = l.z - l.d / 2, z2 = l.z + l.d / 2 } end
	local function bRect(b, pad, withParking)
		local c1 = b.frame:PointToWorldSpace(Vector3.new(-b.width / 2 - pad, 0, (if withParking then -City.OFFICE.parkingDepth else 0) - pad))
		local c2 = b.frame:PointToWorldSpace(Vector3.new(b.width / 2 + pad, 0, b.depth + pad))
		return { x1 = math.min(c1.X, c2.X), x2 = math.max(c1.X, c2.X), z1 = math.min(c1.Z, c2.Z), z2 = math.max(c1.Z, c2.Z), id = b.id }
	end

	------------------------------------------------------------------ lots
	check("85+ background lots", #Plan.LOTS >= 70, #Plan.LOTS)
	local roadRects = {}
	for _, r in Plan.ROADS do table.insert(roadRects, { rect = Plan.roadRect(r, true), id = r.id }) end
	local reserved = {
		{ x1 = -102, x2 = 102, z1 = 7760, z2 = 8360, id = "boulevard strip" },
		{ x1 = 446, x2 = 694, z1 = 7810, z2 = 8044, id = "park" },
		{ x1 = A.plaza.x1, x2 = A.plaza.x2, z1 = A.plaza.z1, z2 = A.plaza.z2, id = "plaza" },
		{ x1 = A.terminal.x1, x2 = A.terminal.x2, z1 = A.terminal.z1, z2 = A.terminal.z2, id = "terminal" },
		{ x1 = A.runway.x1, x2 = A.runway.x2, z1 = A.runway.z1, z2 = A.runway.z2 + 20, id = "runway+apron" },
		{ x1 = R.x1, x2 = R.x2, z1 = 8504, z2 = R.z2, id = "spire plaza / harbour walk / promenade" },
		{ x1 = Plan.HELIPADS.airport.cf.X - 40, x2 = Plan.HELIPADS.airport.cf.X + 40, z1 = Plan.HELIPADS.airport.cf.Z - 40, z2 = 7694, id = "airport helipad + VIP terminal" },
	}
	for _, b in City.BUILDINGS do if b.zone == "abroad" then table.insert(reserved, bRect(b, 4, true)) end end
	local badRoad, badRes, badOv, badRect = {}, {}, 0, {}
	for i, l in Plan.LOTS do
		local r = lotRect(l)
		if not (r.x1 >= R.x1 + 4 and r.x2 <= R.x2 - 4 and r.z1 >= R.z1 and r.z2 <= R.z2) then table.insert(badRect, l.id) end
		for _, rr in roadRects do if ov(r, rr.rect) then table.insert(badRoad, l.id .. "/" .. rr.id) end end
		for _, rr in reserved do if ov(r, rr) then table.insert(badRes, l.id .. "/" .. rr.id) end end
		for j = i + 1, #Plan.LOTS do if ov(r, lotRect(Plan.LOTS[j])) then badOv += 1 end end
	end
	check("lots inside the city rect", #badRect == 0, table.concat(badRect, ","))
	check("lots off every road and sidewalk", #badRoad == 0, table.concat(badRoad, ","))
	check("lots off reserved areas (boulevard, park, plaza, terminal, runway, waterfront, helipad, client towers)", #badRes == 0, table.concat(badRes, ","))
	check("lots never overlap", badOv == 0, badOv)
	local styles, crowns, maxH = {}, {}, 0
	for _, l in Plan.LOTS do styles[l.style] = true; crowns[l.crown] = true; maxH = math.max(maxH, l.h + (if l.crown == "spire" then 75 else 20)) end
	local ns, nc = 0, 0
	for _ in styles do ns += 1 end
	for _ in crowns do nc += 1 end
	check("varied silhouettes: >= 7 styles, >= 5 crowns", ns >= 7 and nc >= 5, ns .. " / " .. nc)
	check("the Meridian Spire stays the tallest (landmark + mast > every tower + crown)", Plan.LANDMARK.height + Plan.LANDMARK.mast > maxH + 60, maxH)
	local tall = 0
	for _, l in Plan.LOTS do if l.h >= 200 then tall += 1 end end
	check("dense core: >= 10 towers of 200+ studs", tall >= 10, tall)

	------------------------------------------------------------------ walk graphs
	local function flatSeg(a, b, x, z)
		local dx, dz = b.X - a.X, b.Z - a.Z
		local l2 = dx * dx + dz * dz
		local t = if l2 > 0 then math.clamp(((x - a.X) * dx + (z - a.Z) * dz) / l2, 0, 1) else 0
		return math.sqrt((x - (a.X + dx * t)) ^ 2 + (z - (a.Z + dz * t)) ^ 2)
	end
	local function graphChecks(name, net, solids, asphalt, surfaceOk)
		-- connectivity
		local seen, stack = { [1] = true }, { 1 }
		while #stack > 0 do
			local n = table.remove(stack)
			for _, eid in net.nodes[n].links do
				local e = net.edges[eid]
				local o = if e.a == n then e.b else e.a
				if not seen[o] then seen[o] = true; table.insert(stack, o) end
			end
		end
		local reached = 0
		for _ in seen do reached += 1 end
		check(name .. ": walk graph connected", reached == #net.nodes, reached .. "/" .. #net.nodes)
		local inSolid, onRoad, crossNoJ, badY = {}, {}, 0, {}
		for _, e in net.edges do
			local a, b = net.nodes[e.a].p, net.nodes[e.b].p
			local portalEnd = net.nodes[e.a].portal or net.nodes[e.b].portal
			if e.junction == nil and e.axis ~= nil then crossNoJ += 1 end
			for k = 0, 10 do
				local p = a:Lerp(b, k / 10)
				-- the outer half-width band too (walkers walk up to `half` beside the centre line)
				for _, s in solids do
					if inside(s, p.X, p.Z, if portalEnd then 1.5 else -0.5) then table.insert(inSolid, string.format("%s@%.0f,%.0f", s.id, p.X, p.Z)); break end
				end
				if not e.junction then
					for _, r in asphalt do
						if inside(r, p.X, p.Z, 0.3) then table.insert(onRoad, string.format("%s@%.0f,%.0f", r.id, p.X, p.Z)); break end
					end
				end
			end
		end
		for _, n in net.nodes do
			if not surfaceOk(n.p) then table.insert(badY, string.format("%.0f,%.0f y=%.2f", n.p.X, n.p.Z, n.p.Y)) end
		end
		check(name .. ": no walk edge inside a building", #inSolid == 0, #inSolid .. " " .. table.concat(inSolid, " ", 1, math.min(6, #inSolid)))
		check(name .. ": no walk edge on the asphalt except crossings", #onRoad == 0, #onRoad .. " " .. table.concat(onRoad, " ", 1, math.min(6, #onRoad)))
		check(name .. ": crossings carry a junction", crossNoJ == 0, crossNoJ)
		check(name .. ": node heights are surface heights", #badY == 0, #badY .. " " .. table.concat(badY, " ", 1, math.min(5, #badY)))
		local nCross = 0
		for _, e in net.edges do if e.junction then nCross += 1 end end
		check(name .. ": zebra crossings at the junctions", nCross >= #net.junctions * 2, nCross)
	end
	local pm = Plan.portMeridian()
	local solids = {}
	for _, l in Plan.LOTS do local r = lotRect(l); r.id = l.id; table.insert(solids, r) end
	for _, b in City.BUILDINGS do if b.zone == "abroad" then table.insert(solids, bRect(b, 0, false)) end end
	table.insert(solids, { x1 = A.terminal.x1, x2 = A.terminal.x2, z1 = A.terminal.z1, z2 = A.terminal.z2, id = "terminal" })
	local L = Plan.LANDMARK
	table.insert(solids, { x1 = L.x - L.size / 2, x2 = L.x + L.size / 2, z1 = L.z - L.size / 2, z2 = L.z + L.size / 2, id = "spire" })
	for _, pv in Plan.PAVILIONS do table.insert(solids, { x1 = math.min(pv.side * 70, pv.side * 96), x2 = math.max(pv.side * 70, pv.side * 96), z1 = pv.z1, z2 = pv.z2, id = "pavilion" }) end
	local asphalt = {}
	for _, r in Plan.ROADS do
		local rr = Plan.roadRect(r)
		if r.median > 0 then
			-- two carriageways beside the kerbed median (the median itself is walkable)
			for _, sd in { -1, 1 } do
				local lo, hi = sd * r.median / 2, sd * r.width / 2
				local q = if r.axis == "z" then { x1 = r.c + math.min(lo, hi), x2 = r.c + math.max(lo, hi), z1 = rr.z1, z2 = rr.z2 } else { x1 = rr.x1, x2 = rr.x2, z1 = r.c + math.min(lo, hi), z2 = r.c + math.max(lo, hi) }
				q.id = r.id; table.insert(asphalt, q)
			end
		else
			rr.id = r.id; table.insert(asphalt, rr)
		end
	end
	for _, rr in { Plan.VIP_LIMO.layby, Plan.TAXI_RANK } do table.insert(asphalt, { x1 = rr.x1, x2 = rr.x2, z1 = rr.z1, z2 = rr.z2, id = "layby" }) end
	local tops = { City.WALK_TOP, Plan.PLAZA_TOP, Plan.MEDIAN_TOP, Plan.PARK_TOP, Plan.PAVE_TOP, Plan.PLINTH_TOP }
	graphChecks("Port Meridian", pm, solids, asphalt, function(p)
		for _, t in tops do if math.abs(p.Y - t) < 0.01 then return true end end
		return false
	end)
	check("Port Meridian: 300+ nodes, 9 signalled junctions, 16 lanes", #pm.nodes >= 300 and #pm.junctions == 9 and #pm.lanes == 16 and pm.signals, #pm.nodes .. " " .. #pm.junctions .. " " .. #pm.lanes)
	local idle, portals = {}, 0
	for _, n in pm.nodes do if n.idle then idle[n.idle] = (idle[n.idle] or 0) + 1 end; if n.portal then portals += 1 end end
	check("Port Meridian idle spots: benches, shop fronts, bus stops, views", (idle.bench or 0) >= 30 and (idle.shop or 0) >= 12 and (idle.bus or 0) == 4 and (idle.view or 0) >= 6, (idle.bench or 0) .. "/" .. (idle.shop or 0) .. "/" .. (idle.bus or 0) .. "/" .. (idle.view or 0))
	check("Port Meridian door portals (terminal, towers, hotel, spire, pavilions)", portals >= 16, portals)
	local dt = Plan.downtown()
	local dsolids = {}
	for _, b in City.BUILDINGS do if b.zone == "downtown" then table.insert(dsolids, bRect(b, 0, false)) end end
	local dasphalt = {}
	for _, r in City.ROADS do local rr = City.roadRect(r); rr.id = r.id; table.insert(dasphalt, rr) end
	graphChecks("Business City", dt, dsolids, dasphalt, function(p) return math.abs(p.Y - City.WALK_TOP) < 0.01 or math.abs(p.Y - (City.GROUND + 0.3)) < 0.01 end)
	check("Business City: unsignalled, 16+ door portals", not dt.signals and #dt.junctions >= 12, #dt.junctions)

	------------------------------------------------------------------ lanes + signals
	local badLane = 0
	for _, net in { pm, dt } do
		for _, l in net.lanes do
			local r = l.road
			if math.abs(l.off) > r.width / 2 - 2 or math.abs(l.off) < r.median / 2 + 1.5 then badLane += 1 end
		end
	end
	check("lanes inside the carriageway, clear of the median", badLane == 0, badLane)
	local rightHand = 0
	for _, l in pm.lanes do
		local h = Plan.laneHeading(l)
		local right = Vector3.new(-h.Z, 0, h.X)
		local off = Plan.lanePoint(l, 0, 0) - Plan.lanePoint(l, 0, 0)
		local centre = if l.road.axis == "x" then Vector3.new(0, 0, l.road.c) else Vector3.new(l.road.c, 0, 0)
		local p = Plan.lanePoint(l, 0, 0)
		local side = if l.road.axis == "x" then Vector3.new(0, 0, p.Z - centre.Z) else Vector3.new(p.X - centre.X, 0, 0)
		if side:Dot(right) > 0 then rightHand += 1 end
		local _ = off
	end
	check("right-hand traffic on every lane", rightHand == #pm.lanes, rightHand)
	local conflicts, greenX, greenZ = 0, 0, 0
	for _, j in pm.junctions do
		for t = 0, Plan.CYCLE - 0.05, 0.05 do
			local gx, gz = Plan.green(j, "x", 1000 + t), Plan.green(j, "z", 1000 + t)
			if gx and gz then conflicts += 1 end
			if j.id == 1 and gx then greenX += 0.05 end
			if j.id == 1 and gz then greenZ += 0.05 end
		end
	end
	check("signals: never green on both axes", conflicts == 0, conflicts)
	check("signals: 11.5 s green per axis and cycle", math.abs(greenX - Plan.GREEN) < 0.2 and math.abs(greenZ - Plan.GREEN) < 0.2, greenX .. " / " .. greenZ)

	------------------------------------------------------------------ spots, VIP, helipads, far skyline, districts
	local badBench = {}
	for _, s in Plan.BENCHES do
		local seat = Vector3.new(s.x, 0, s.z) - s.face * 1.6
		for _, q in { Vector3.new(s.x, 0, s.z), seat } do
			for _, r in asphalt do if inside(r, q.X, q.Z, -1) then table.insert(badBench, string.format("%.0f,%.0f/%s", q.X, q.Z, r.id)) end end
			for _, r in solids do if inside(r, q.X, q.Z, -1) then table.insert(badBench, string.format("%.0f,%.0f/%s", q.X, q.Z, r.id)) end end
		end
	end
	check("benches (spot + seat) off the roads and buildings", #badBench == 0, table.concat(badBench, " "))
	local st = Plan.VIP_LIMO.stand.Position
	local lay = Plan.VIP_LIMO.layby
	check("VIP limo stand inside its lay-by on Arrivals Drive (north kerb)", inside(lay, st.X, st.Z) and lay.z2 == Plan.road("pm_arrivals").c - 16, st)
	local hotel = City.building("intl_hotel")
	local hp = Plan.HELIPADS.hotel
	local hr = bRect(hotel, 0, false)
	check("hotel helipad on the hotel roof (Purpose VIP)", hp.purpose == "VIP" and inside(hr, hp.cf.X, hp.cf.Z, hp.size / 2) and math.abs(hp.cf.Y - Plan.HOTEL_ROOF - 1) < 1e-6, hp.cf)
	local ap = Plan.HELIPADS.airport
	check("airport helipad beside the arrival terminal (Purpose VIPAirport)", ap.purpose == "VIPAirport" and ap.cf.X - ap.size / 2 > A.terminal.x2 + 50 and math.abs(ap.cf.Y - City.GROUND - 1) < 1e-6)
	local badFar = 0
	for _, f in Plan.FAR do
		local r = { x1 = f.x - f.w / 2, x2 = f.x + f.w / 2, z1 = f.z - f.d / 2, z2 = f.z + f.d / 2 }
		if ov(r, { x1 = R.x1 - 8, x2 = R.x2 + 8, z1 = R.z1 - 8, z2 = R.z2 + 8 }) then badFar += 1 end
		if r.z2 > Plan.SEA.z1 and r.z1 < Plan.SEA.z2 then badFar += 1 end
	end
	check("far skyline outside the walls and off the sea", badFar == 0 and #Plan.FAR > 150, badFar .. " / " .. #Plan.FAR)
	-- far shells keep off the client road continuations (+ sidewalks + 6) and the tunnel gates
	local onRoad = {}
	for _, f in Plan.FAR do
		local r = { x1 = f.x - f.w / 2, x2 = f.x + f.w / 2, z1 = f.z - f.d / 2, z2 = f.z + f.d / 2 }
		for _, rd in Plan.ROADS do
			if rd.beyond then
				local hw = rd.width / 2 + rd.walk + 6
				for _, sd in { -1, 1 } do
					local xa, xb = if sd < 0 then rd.a1 - rd.beyond - 60 else rd.a2, if sd < 0 then rd.a1 else rd.a2 + rd.beyond + 60
					if ov(r, { x1 = xa, x2 = xb, z1 = rd.c - hw, z2 = rd.c + hw }) then table.insert(onRoad, string.format("%.0f,%.0f/%s", f.x, f.z, rd.id)) end
				end
			end
		end
	end
	check("far shells never stand on a road continuation", #onRoad == 0, table.concat(onRoad, " "))
	-- every through street ends in a tunnel gate at both walls (no invisible wall mid-street)
	local gates = 0
	for _, t in Plan.TUNNELS do
		local r = t.road
		if t.x == (if t.side < 0 then r.a1 else r.a2) and t.z1 < r.c - r.width / 2 - r.walk and t.z2 > r.c + r.width / 2 + r.walk and t.mouth >= 14 and t.height > t.mouth + 10 then gates += 1 end
	end
	local through = 0
	for _, r in Plan.ROADS do if r.beyond then through += 2 end end
	check("tunnel gates at all " .. through .. " street ends (spanning road + sidewalks)", gates == through and through == 6, gates)
	local holes = 0
	for x = R.x1 + 1, R.x2 - 1, 20 do for z = R.z1 + 1, R.z2 - 1, 20 do if not Plan.districtAt(x, z) then holes += 1 end end end
	check("named districts cover the whole city", holes == 0 and #Plan.DISTRICTS >= 4, holes)
	check("regions: Port Meridian and downtown, nothing on the campus / airport (terminal check-in z 2461, car park z 2421)", Plan.regionAt(Vector3.new(0, 0, 8000)) == "metro" and Plan.regionAt(Vector3.new(0, 0, 1500)) == "downtown" and Plan.regionAt(Vector3.new(0, 0, 0)) == nil and Plan.regionAt(Vector3.new(0, 0, 2800)) == nil
		and Plan.regionAt(Vector3.new(0, 0, 2461)) == nil and Plan.regionAt(Vector3.new(0, 0, 2421)) == nil)
	------------------------------------------------------------------ furniture vs fountains / pool; skyline height
	local wet = {}
	local function seatBox(sp) local seat = Vector3.new(sp.x, 0, sp.z) - sp.face * 1.6; return seat end
	for _, sp in Plan.BENCHES do
		if math.abs(sp.x) < 12 then
			local seat = seatBox(sp)
			local right = Vector3.new(-sp.face.Z, 0, sp.face.X)
			for _, k in { -3.2, 0, 3.2 } do
				local q = seat + right * k
				for _, fz in Plan.FOUNTAINS do if (q - Vector3.new(0, 0, fz)).Magnitude < 10.6 then table.insert(wet, string.format("%.0f,%.0f fountain", q.X, q.Z)) end end
				if math.abs(q.X) < 9.6 and q.Z > 8249.4 and q.Z < 8302.6 then table.insert(wet, string.format("%.0f,%.0f pool", q.X, q.Z)) end
				if math.abs(q.X) < 4 and q.Z > 7935.4 and q.Z < 7944.6 then table.insert(wet, string.format("%.0f,%.0f globe", q.X, q.Z)) end
			end
		end
	end
	check("median benches clear of the fountains, the globe plinth and the reflecting pool", #wet == 0, table.concat(wet, " "))
	local hs = {}
	for _, l in Plan.LOTS do table.insert(hs, l.h) end
	table.sort(hs)
	local n200, n300 = 0, 0
	for _, h in hs do if h >= 200 then n200 += 1 end; if h >= 300 then n300 += 1 end end
	check("taller skyline: median tower >= 180 studs, >= 40 towers of 200+, >= 6 of 300+", hs[math.floor(#hs / 2)] >= 180 and n200 >= 40 and n300 >= 6, hs[math.floor(#hs / 2)] .. " / " .. n200 .. " / " .. n300)
	check("greenery: lawn verges + verge trees, promenade tree row every <= 40 studs, bed trees, bollards", #Plan.VERGES >= 30 and #Plan.VERGE_TREES >= 100 and #Plan.PROM_TREES >= 30 and #Plan.BED_TREES >= 20 and #Plan.BOLLARDS >= 50,
		#Plan.VERGES .. "/" .. #Plan.VERGE_TREES .. "/" .. #Plan.PROM_TREES .. "/" .. #Plan.BED_TREES .. "/" .. #Plan.BOLLARDS)
end

local ok, err = M.runMain(body, { timeout = 120, maxSteps = 5000000 })
if not ok then print("ERROR " .. tostring(err)); failc += 1 end
print(string.format("metro_plan: %d passed, %d failed", pass, failc))
