--!nocheck
-- World package: CityPlan (pure data + maths). Road graph on the asphalt, Dijkstra routes between every
-- destination and from every campus plot, every route segment drivable, drivable() bounds, destinations
-- API (client ids match EmpireConfig.CONTRACTS and MarketService businesses), determinism.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_world && tools/luau tests/world/test_cityplan.luau [-a .gen_dir]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_world")
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
	local City = M.require(RS.Shared.Config.CityPlan)
	local EmpireConfig = M.require(RS.Shared.Config.EmpireConfig)
	local GROUND = City.GROUND

	------------------------------------------------------------------ graph
	local n = #City.NODE_IDS
	check("road graph has ~30 nodes", n >= 24 and n <= 36, n)
	check("road graph has edges", #City.EDGES >= n, #City.EDGES)
	local adj = {}
	for _, id in City.NODE_IDS do adj[id] = {} end
	local offRoad, diagonal, badRef = 0, 0, 0
	for _, e in City.EDGES do
		local a, b = City.NODES[e[1]], City.NODES[e[2]]
		if not a or not b then badRef += 1 else
			table.insert(adj[e[1]], e[2]); table.insert(adj[e[2]], e[1])
			if math.abs(a.X - b.X) > 1e-6 and math.abs(a.Z - b.Z) > 1e-6 then diagonal += 1 end
			local len = City.flat(a, b)
			for s = 0, len, 2 do
				local t = s / len
				local p = Vector3.new(a.X + (b.X - a.X) * t, GROUND, a.Z + (b.Z - a.Z) * t)
				if not City.onRoad(p, 0) then offRoad += 1; if offRoad <= 3 then print("  off road: " .. e[1] .. "-" .. e[2] .. " at " .. tostring(p)) end end
				if not City.drivable(p) then offRoad += 1 end
			end
		end
	end
	check("every edge references known nodes", badRef == 0, badRef)
	check("every edge runs along a street (axis-aligned)", diagonal == 0, diagonal)
	check("every edge sample lies on asphalt and is drivable", offRoad == 0, offRoad)
	local seen, queue = { av_w = true }, { "av_w" }
	while #queue > 0 do
		local u = table.remove(queue, 1)
		for _, w in adj[u] do if not seen[w] then seen[w] = true; table.insert(queue, w) end end
	end
	local reached = 0; for _ in seen do reached += 1 end
	check("road graph is connected", reached == n, reached .. "/" .. n)
	local used = {}; for _, e in City.EDGES do used[e[1]] = true; used[e[2]] = true end
	local unused = 0; for _, id in City.NODE_IDS do if not used[id] then unused += 1 end end
	check("no isolated node", unused == 0, unused)

	------------------------------------------------------------------ roads / parts
	local tooLong = 0
	for _, r in City.ROADS do if math.abs(r.a2 - r.a1) > 2048 then tooLong += 1 end end
	check("every new road fits one <=2048-stud part", tooLong == 0, tooLong)
	check("ring roads continue the district ring at x=+-1016", City.ROADS[1].c == -1016 and City.ROADS[2].c == 1016 and City.ROADS[1].a1 == 540)

	------------------------------------------------------------------ drivable
	local cases = {
		{ "district avenue", Vector3.new(0, 24, 0), true }, { "district old x tolerance", Vector3.new(1155, 24, 0), true },
		{ "downtown", Vector3.new(-600, 24, 1500), true }, { "airport runway", Vector3.new(0, 24, 3000), true },
		{ "south ring extension", Vector3.new(1016, 24, 2200), true }, { "past the old z limit", Vector3.new(0, 24, 900), true },
		{ "sea", Vector3.new(0, 24, 3300), false }, { "east of the district", Vector3.new(1200, 24, 0), false },
		{ "north of the district", Vector3.new(0, 24, -900), false }, { "downtown x>1150", Vector3.new(1155, 24, 1500), false },
		{ "abroad (no cars)", Vector3.new(0, 24, 8000), false }, { "between home and abroad", Vector3.new(0, 24, 5000), false },
		{ "NaN", Vector3.new(0 / 0, 24, 0), false },
	}
	for _, c in cases do check("drivable: " .. c[1], City.drivable(c[2]) == c[3], tostring(c[2])) end
	check("zoneAt downtown/airport/abroad", City.zoneAt(Vector3.new(0, 24, 1500)) == "downtown" and City.zoneAt(Vector3.new(0, 24, 2600)) == "airport" and City.zoneAt(Vector3.new(0, 24, 8000)) == "abroad")
	check("time zone: same as home (honest, Lighting is global)", City.TIME_ZONE_OFFSET == 0)

	------------------------------------------------------------------ destinations API
	local clients = City.destinations("client")
	check("18 client offices (14 downtown + 4 abroad)", #clients == 18 and #City.destinations("client", "downtown") == 14 and #City.destinations("client", "abroad") == 4, #clients)
	local ids = {}
	local dup = 0
	for _, d in City.DESTINATION_LIST do if ids[d.id] then dup += 1 end; ids[d.id] = true end
	check("destination ids unique", dup == 0, dup)
	for _, c in EmpireConfig.CONTRACTS do
		local d = City.clientOffice(c.id, "contract")
		check("contract " .. c.id .. " has an office named " .. c.name, d ~= nil and d.name == c.name and d.contract == c.id, d and d.name)
	end
	local mkt = sources["ServerScriptService/Server/Services/MarketService.module.luau"]
	local nb = 0
	for id, name in string.gmatch(mkt, '{id="(%w+)",name="([^"]+)"') do
		nb += 1
		local d = City.clientOffice(id, "business")
		check("business " .. id .. " has an office named " .. name, d ~= nil and d.name == name and d.business == id, d and d.name)
		check("business name lookup " .. name, City.clientOffice(name) == d)
	end
	-- the econ package moved the business list into CompanyOps.CLIENTS (one catalogue of 18 clients; mapped to
	-- buildings BY NAME, CORE_SPEC 11.2); MarketService keeps none any more. Either source must map completely.
	local okOps, Ops = pcall(M.require, M.game.ReplicatedStorage.Shared.CompanyOps)
	local catalogue = okOps and type(Ops) == "table" and Ops.CLIENTS or nil
	if catalogue then
		local unmapped = {}
		for _, c in catalogue do
			local d = City.clientOffice(c.name)
			if not (d and d.name == c.name and d.kind == "client") then table.insert(unmapped, c.name) end
		end
		check("CompanyOps.CLIENTS: every client name maps to its office (" .. #catalogue .. ")", #unmapped == 0 and #catalogue == 18, unmapped[1])
	end
	check("businesses parsed (MarketService list or the CompanyOps catalogue)", nb == 12 or (catalogue ~= nil and #catalogue == 18), nb)
	check("ambiguous id 'frontier': contract wins without refKind", City.clientOffice("frontier").name == "Orbit Systems" and City.clientOffice("frontier", "business").name == "Frontier Science")
	check("client id lookup (any case)", City.clientOffice("byteworks").name == "ByteWorks" and City.clientOffice("BYTEWORKS").id == "byteworks" and City.clientOffice("ByteWorks").id == "byteworks")
	check("unknown client -> nil", City.clientOffice("nobody") == nil and City.clientOffice(42) == nil and City.destination(nil) == nil)
	local badCF, noMeeting, noParking = 0, 0, 0
	local function finite(cf) for _, x in { cf:GetComponents() } do if x ~= x or math.abs(x) == math.huge then return false end end; return true end
	for _, d in City.DESTINATION_LIST do
		for _, cf in { d.door, d.lobby, d.meeting, d.reception } do if cf and not finite(cf) then badCF += 1 end end
		if d.kind == "client" then
			if not d.meeting then noMeeting += 1 end
			if d.zone == "downtown" and #d.parking ~= 4 then noParking += 1 end
			-- meeting / reception / lobby lie inside the 60 x 60 footprint; door and bays in front of it
			local f = d.building.frame
			for label, cf in { meeting = d.meeting, lobby = d.lobby, reception = d.reception } do
				local l = f:PointToObjectSpace(cf.Position)
				check(d.id .. " " .. label .. " inside the footprint", math.abs(l.X) < 30 and l.Z > 0 and l.Z < 60, tostring(l))
			end
			local ld = f:PointToObjectSpace(d.door.Position)
			check(d.id .. " door outside, in front of the entrance", math.abs(ld.X) < 5 and ld.Z < 0 and ld.Z > -18, tostring(ld))
			check(d.id .. " door faces the entrance", f:VectorToObjectSpace(d.door.LookVector).Z > 0.99)
		end
	end
	check("destination CFrames finite", badCF == 0, badCF)
	check("every client office has a meeting point", noMeeting == 0, noMeeting)
	check("every downtown office has 4 visitor bays", noParking == 0, noParking)
	check("airport points", #City.AIRPORT.checkin >= 3 and #City.AIRPORT.gates == 3 and #City.AIRPORT.carParkBays >= 4 and City.AIRPORT.arrival ~= nil)
	check("abroad points", #City.ABROAD.checkin >= 1 and City.ABROAD.arrival ~= nil and City.INTL_HOTEL ~= nil and City.INTL_HOTEL.zone == "abroad")
	check("city hotel lobby + reception", City.CITY_HOTEL ~= nil and City.CITY_HOTEL.lobby ~= nil and City.CITY_HOTEL.reception ~= nil and City.CITY_HOTEL.zone == "downtown")
	check("ticket price in a config table", type(City.TRAVEL.ticket) == "number" and City.TRAVEL.ticket > 0)

	------------------------------------------------------------------ routes
	local function segmentOk(a, b)
		local len = City.flat(a, b); local bad = 0
		for s = 0, len, 4 do
			local t = if len > 0 then s / len else 0
			if not City.drivable(Vector3.new(a.X + (b.X - a.X) * t, GROUND, a.Z + (b.Z - a.Z) * t)) then bad += 1 end
		end
		return bad == 0
	end
	local function routeOk(r)
		for i = 2, #r.points do if not segmentOk(r.points[i - 1], r.points[i]) then return false, i end end
		return true
	end
	local homeDest = {}
	for _, d in City.DESTINATION_LIST do if d.zone ~= "abroad" then table.insert(homeDest, d) end end
	local pairsOk, pairsBad, segBad, roadBad, worst = 0, 0, 0, 0, 0
	for _, a in homeDest do
		for _, b in homeDest do
			if a ~= b then
				local r, err = City.routeTo(a.drive or a.door.Position, b.id)
				if not r then pairsBad += 1; if pairsBad <= 3 then print("  no route " .. a.id .. " -> " .. b.id .. " " .. tostring(err)) end
				else
					pairsOk += 1
					local ok, at = routeOk(r); if not ok then segBad += 1; if segBad <= 3 then print("  undrivable " .. a.id .. " -> " .. b.id .. " segment " .. at) end end
					-- interior points (between the two snap points) are road nodes
					for i = 3, #r.points - 2 do if not City.onRoad(r.points[i], 1) then roadBad += 1 end end
					local direct = City.flat(a.drive or a.door.Position, b.drive or b.door.Position)
					if r.length + 1e-6 < direct then worst += 1 end
				end
			end
		end
	end
	check("route between every pair of home destinations", pairsBad == 0, pairsOk .. " ok, " .. pairsBad .. " missing")
	check("every route segment drivable (" .. pairsOk .. " routes)", segBad == 0, segBad)
	check("route corners lie on streets", roadBad == 0, roadBad)
	check("no route shorter than the straight line", worst == 0, worst)
	-- from every campus plot: from the garage pick-up bay (inside the site) and from the driveway
	local plots = City.plots()
	check("12 plots", #plots == 12)
	local plotBad, viaGate = 0, 0
	for _, p in plots do
		local garage = p.cframe:PointToWorldSpace(Vector3.new(100, -12, 2))
		for _, b in homeDest do
			local r = City.routeTo(garage, b.id)
			if not r or not routeOk(r) then plotBad += 1 else
				if City.flat(r.points[2], p.gate) < 1 and City.flat(r.points[3], p.driveway) < 1 then viaGate += 1 end
			end
		end
		local hq = City.route(City.AIRPORT.carPark.Position, garage)
		if not hq or City.flat(hq.points[#hq.points - 1], p.gate) > 1 or not routeOk(hq) then plotBad += 1 end
	end
	check("routes from all 12 garages to every destination (and back from the airport) drivable", plotBad == 0, plotBad)
	check("routes leave a plot through its barrier and driveway", viaGate == 12 * #homeDest, viaGate)
	-- known route: plot 7 (south-west) to ByteWorks runs over the west ring road and the Parkway
	local r7 = City.routeTo(plots[7].driveway, "byteworks")
	local hasRing = false; for _, id in r7.nodes do if id == "rw_1000" then hasRing = true end end
	check("plot 7 -> ByteWorks via West Ring Road + Parkway", hasRing and r7.length > 1300 and r7.length < 2100, r7.length)
	local ra, rb = City.routeTo(plots[3].driveway, "airport"), City.routeTo(plots[3].driveway, "airport")
	local same = #ra.points == #rb.points
	for i = 1, math.min(#ra.points, #rb.points) do if City.flat(ra.points[i], rb.points[i]) > 1e-9 then same = false end end
	check("routes are deterministic", same)
	local fwd, back = City.route(City.DESTINATIONS.clouddesk.drive, City.DESTINATIONS.mosaicworlds.drive), City.route(City.DESTINATIONS.mosaicworlds.drive, City.DESTINATIONS.clouddesk.drive)
	check("route length symmetric", math.abs(fwd.length - back.length) < 1e-6, fwd.length .. " vs " .. back.length)
	-- shortest: Dijkstra never loses against any single-corner (L-shaped) street path through a graph node
	local dBad = 0
	for _, a in homeDest do
		local ra2 = City.routeTo(a.drive or a.door.Position, "airport")
		local lens = {}
		for _, id in City.NODE_IDS do
			local r1, r2 = City.route(a.drive or a.door.Position, City.NODES[id]), City.route(City.NODES[id], City.AIRPORT.carPark.Position)
			if r1 and r2 and r1.length + r2.length + 1e-6 < ra2.length then dBad += 1; table.insert(lens, id) end
		end
	end
	check("Dijkstra: no via-node detour is shorter than the route", dBad == 0, dBad)
	-- abroad
	local r, err = City.routeTo(City.AIRPORT.carPark.Position, "helixresearch")
	check("home -> abroad needs a flight", r == nil and err == "FLIGHT_REQUIRED", err)
	local w = City.route(City.ABROAD.arrival.Position, City.DESTINATIONS.helixresearch.door.Position)
	check("abroad: straight walking guide", w ~= nil and #w.points == 2)
	local off, err2 = City.route(Vector3.new(0, 24, 5000), City.AIRPORT.carPark.Position)
	check("route from off the map refused", off == nil and err2 == "OFF_MAP", err2)
	check("routeTo unknown destination", select(2, City.routeTo(Vector3.new(0, 24, 0), "nowhere")) == "BAD_INPUT")
end

local ok, err = M.runMain(body, { timeout = 60 })
if not ok then failc += 1; print("ERROR " .. tostring(err)) end
print(string.format("world_cityplan: %d passed, %d failed", pass, failc))
if failc > 0 then error("world_cityplan failed", 0) end
