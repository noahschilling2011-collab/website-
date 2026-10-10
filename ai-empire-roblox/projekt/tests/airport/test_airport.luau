--!nocheck
-- Airport package: City Airport as built by CityBuilder -> AirportBuilder in the headless mock.
--   * budgets: terminal interior <= 3,500 parts, airport exterior (without the parked aircraft) <= 222 + 1,500,
--     real lights <= 40 in the airport zone; decor flags (non-colliding parts never touch/query, no shadow)
--   * the existing contracts: four check-in counters (CityAction checkin, FlightTo abroad, CheckinTo, Public,
--     ticket text), the GPS kiosk home, arrival point on a floor, gate CFrames free
--   * markers: Model "BusinessLounge" (tag + Purpose) inside CityPlan.AIRPORT.lounge, part "CrewRoom"
--     (Purpose CrewRoom) at CityPlan.AIRPORT.crewRoom, part "CompanyJetStand" (Purpose CompanyJet) at
--     CityPlan.AIRPORT.companyJetStand on a paved, collidable surface clear of the hangar walls and the jet
--   * stands: a ParkedAircraft pivoted at every CityPlan.AIRPORT.standCFrames[i]; its jet bridge cab floor at
--     the DoorL1 sill height and its open side 0.4-1.0 studs off the door; the bridge starts at the gate door
--     in the apron facade, which is open (no collidable part in the doorway)
--   * shuttle stand (CityPlan.AIRPORT.shuttleStand): no ground vehicle in the sweep of the pushback / nose-first
--     taxi-in of the client-animated shuttle (checked against the real parked aircraft hull)
--   * walkability (1-stud grid, agent radius 1.0, body band floor+0.6..+5): from the forecourt through each
--     departure door to every check-in counter, through every security lane to every gate desk and gate door,
--     the lounge, the crew room, every staff post (AirportPost) and the arrivals exit
--   * CityPlan.taxiRoute: every point on a collidable paved top (apron / taxiway / runway)
--   * signage: departure boards, CHECK-IN A-D, GATE A1-A3, BUSINESS LOUNGE; no real brand names
--   * the map does not end behind the runway: fence, trees, Persistent horizon (coast + hills + sea)
--   * map edge: no slit between the city / harbour and the horizon backdrop (|x| = 1150 seams, z = 3800), one
--     water level, a ragged shore beyond the quay line
--   * seats: CityPlan.AIRPORT.seats = the built SeatPads (one per pad, on its top); gate rows keep the desk lane
--     free; table chairs are slabs on posts; thin per-seat armrests
--   * CityPlan.AIRPORT.walk: nodes / edges on reachable floor, never across queue belts or posts, connected,
--     covering doors, desks, lanes, gates, lounge, shops, food court, reclaim; board nodes at the bridge doors
--   * flight information = FlightPlan (one shuttle: only its flight numbers, no fixed clock times, no static
--     BOARDING), boards tagged FlightInfoBoard, only the shuttle gate shows a flight, welcome sign landside
--   * reviewer items: radar / beacon FxFar, tray stacks clear of the islands, lowered catering box in the
--     shuttle staging box, GSE parking and equipment road lines on the apron
--   * determinism: a second build yields the same parts at the same places
-- Run: tests/airport/run.sh   (or: tools/luau tests/airport/test_airport.luau -a .gen_airport)
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_airport")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
M.loadTree(manifest, sources)
M.quiet = true
local G = M.G
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local Vector3 = G.Vector3
local function aabb(d)
	local cf, h = d.CFrame, d.Size / 2
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local ex = math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z
	local ey = math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z
	local ez = math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z
	return cf.X - ex, cf.X + ex, cf.Y - ey, cf.Y + ey, cf.Z - ez, cf.Z + ez
end
local function inside(d, p, m)
	local l = d.CFrame:PointToObjectSpace(p)
	local h = d.Size / 2 + Vector3.new(m or 0, m or 0, m or 0)
	return math.abs(l.X) <= h.X and math.abs(l.Y) <= h.Y and math.abs(l.Z) <= h.Z
end

local function body()
	local Vector3, CFrame, Enum = G.Vector3, G.CFrame, G.Enum
	local game = M.game
	local RS, S = game.ReplicatedStorage, game.ServerScriptService.Server.Services
	local CityPlan = M.require(RS.Shared.Config.CityPlan)
	local Builder = M.require(S.CityBuilder)
	local A = CityPlan.AIRPORT
	local GR = CityPlan.GROUND
	local F = GR + 0.5
	local T = A.terminal
	local TICKET = "Port Meridian · $1.5k return"
	local city = Builder.build(TICKET)
	local airport = city:FindFirstChild("Airport")
	check("Airport model built under WorldCity", airport ~= nil and airport:IsA("Model"))
	if not airport then return end
	local terminal = airport:FindFirstChild("Terminal")
	local interior = terminal and terminal:FindFirstChild("TerminalInterior")
	check("Terminal/TerminalInterior is an Atomic model", interior ~= nil and interior.ModelStreamingMode == Enum.ModelStreamingMode.Atomic)

	------------------------------------------------------------------ budgets + flags
	-- interior = the Atomic fit-out + the hall structure (columns, beams, security wall) inside the glass
	local structure = terminal and terminal:FindFirstChild("Structure")
	local nInterior, nExterior, nAircraft, decoBad, shadowBad, unanchored = 0, 0, 0, 0, 0, 0
	local function isAircraft(d)
		local a = d:FindFirstAncestorWhichIsA("Model")
		while a and a ~= airport do
			if a:GetAttribute("AircraftKind") then return true end
			a = a.Parent
		end
		return false
	end
	for _, d in airport:GetDescendants() do
		if d:IsA("BasePart") then
			if not d.Anchored then unanchored += 1 end
			if isAircraft(d) then nAircraft += 1
			elseif (interior and d:IsDescendantOf(interior)) or (structure and d:IsDescendantOf(structure)) then nInterior += 1
			else nExterior += 1 end
			if not d.CanCollide and (d.CanQuery or d.CanTouch) then decoBad += 1 end
			if not d.CanCollide and d.CastShadow and d.Transparency < 1 and not isAircraft(d) then shadowBad += 1 end
		end
	end
	print(string.format("  airport parts: interior %d, exterior %d, parked aircraft %d", nInterior, nExterior, nAircraft))
	check("terminal interior (fit-out + hall structure) <= 3,500 parts", nInterior <= 3500 and nInterior > 1200, nInterior)
	-- brief: exterior + apron additions <= 1,500 over the 222 parts of the old airport exterior
	check("airport exterior (without aircraft) <= 1,722 parts (old 222 + 1,500)", nExterior <= 1722 and nExterior > 800, nExterior)
	check("every airport part anchored", unanchored == 0, unanchored)
	check("decor never touches/queries", decoBad == 0, decoBad)
	check("decor casts no shadow", shadowBad == 0, shadowBad)
	local lights = 0
	for _, d in city:GetDescendants() do
		if d:IsA("Light") and d.Parent:IsA("BasePart") and CityPlan.zoneAt(d.Parent.Position) == "airport" then lights += 1 end
	end
	check("real lights in the airport zone <= 40", lights <= 40 and lights >= 20, lights)
	local scripts = 0
	for _, d in airport:GetDescendants() do if d:IsA("LuaSourceContainer") then scripts += 1 end end
	check("no scripts in the airport (client animation only via PropFx attributes)", scripts == 0, scripts)

	------------------------------------------------------------------ prompts (existing contract)
	local checkins, kiosks, notPublic = {}, 0, 0
	for _, d in airport:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			if d:GetAttribute("Public") ~= true then notPublic += 1 end
			if d:GetAttribute("CityAction") == "checkin" then table.insert(checkins, d) end
			if d:GetAttribute("CityAction") == "navigate" and d:GetAttribute("To") == "home" then kiosks += 1 end
		end
	end
	local badCheckin = 0
	for _, q in checkins do
		local c = q.Parent
		if not (q:GetAttribute("FlightTo") == "abroad" and c:GetAttribute("CheckinTo") == "abroad" and q.ObjectText == TICKET
			and q.ActionText == "Check in & fly" and q.HoldDuration == 1 and q.MaxActivationDistance >= 8 and c.CanCollide) then badCheckin += 1 end
	end
	check("four home check-in counters (CityAction/FlightTo/CheckinTo, ticket text, hold 1 s)", #checkins == #A.checkin and #checkins == 4 and badCheckin == 0, #checkins .. "/" .. badCheckin)
	local nearPlan = 0
	for _, p in A.checkin do
		for _, q in checkins do if (Vector3.new(q.Parent.Position.X, 0, q.Parent.Position.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude < 3 then nearPlan += 1; break end end
	end
	check("each counter at its CityPlan.AIRPORT.checkin point", nearPlan == 4, nearPlan)
	check("GPS kiosk 'Route to my HQ' in the terminal", kiosks >= 1, kiosks)
	check("every airport prompt Public", notPublic == 0, notPublic)

	------------------------------------------------------------------ markers
	local lounge = interior and interior:FindFirstChild("BusinessLounge")
	check("BusinessLounge model: tag + Purpose", lounge ~= nil and lounge:IsA("Model") and lounge:HasTag("BusinessLounge") and lounge:GetAttribute("Purpose") == "BusinessLounge")
	if lounge then
		local out = 0
		local L = A.lounge
		for _, d in lounge:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "LoungeSign" and d.Name ~= "LoungeSignGlow" then
				local p = d.Position
				if p.X < L.x1 - 1 or p.X > L.x2 + 1 or p.Z < L.z1 - 1 or p.Z > L.z2 + 1 then out += 1 end
			end
		end
		check("lounge contents inside CityPlan.AIRPORT.lounge", out == 0, out)
		local armchairs, bar, buffet = 0, false, false
		for _, d in lounge:GetDescendants() do
			if d.Name == "Armchair" then armchairs += 1 elseif d.Name == "LoungeBar" then bar = true elseif d.Name == "Buffet" then buffet = true end
		end
		check("lounge furnished: armchairs, bar, buffet", armchairs >= 8 and bar and buffet, armchairs)
	end
	local crew = airport:FindFirstChild("CrewRoom", true)
	local crewPart = nil
	for _, d in airport:GetDescendants() do if d:IsA("BasePart") and d.Name == "CrewRoom" then crewPart = d end end
	check("CrewRoom marker part at CityPlan.AIRPORT.crewRoom", crewPart ~= nil and crewPart:GetAttribute("Purpose") == "CrewRoom" and (crewPart.Position - A.crewRoom.Position).Magnitude < 0.01 and not crewPart.CanCollide)
	local _ = crew
	local jet = nil
	for _, d in airport:GetDescendants() do if d:IsA("BasePart") and d.Name == "CompanyJetStand" then jet = d end end
	check("CompanyJetStand marker (Purpose CompanyJet) at CityPlan.AIRPORT.companyJetStand", jet ~= nil and jet:GetAttribute("Purpose") == "CompanyJet" and (jet.Position - A.companyJetStand.Position).Magnitude < 0.01 and not jet.CanCollide and not jet.CanQuery)

	------------------------------------------------------------------ solids
	local solids = {}
	for _, root in { city } do
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") and d.CanCollide then
				local x1, x2, y1, y2, z1, z2 = aabb(d)
				table.insert(solids, { d = d, x1 = x1, x2 = x2, y1 = y1, y2 = y2, z1 = z1, z2 = z2 })
			end
		end
	end
	local function solidAt(p)
		for _, s in solids do
			if p.X >= s.x1 and p.X <= s.x2 and p.Y >= s.y1 and p.Y <= s.y2 and p.Z >= s.z1 and p.Z <= s.z2 and inside(s.d, p) then return s.d end
		end
		return nil
	end
	local function topBelow(p, maxDrop)
		local best = nil
		for _, s in solids do
			if p.X >= s.x1 and p.X <= s.x2 and p.Z >= s.z1 and p.Z <= s.z2 and s.y2 <= p.Y + 0.01 and p.Y - s.y2 <= maxDrop then
				if not best or s.y2 > best then best = s.y2 end
			end
		end
		return best
	end
	-- the company-jet stand: paved collidable top under its centre and its corners, no wall / jet inside its box
	local js = A.companyJetStand
	local paved = 0
	for _, o in { Vector3.new(0, 0, 0), Vector3.new(-20, 0, -28), Vector3.new(20, 0, -28), Vector3.new(-20, 0, 28), Vector3.new(20, 0, 28) } do
		local p = js:PointToWorldSpace(o) + Vector3.new(0, 0.5, 0)
		local t = topBelow(p, 1)
		if t and math.abs(t - A.apronTop) < 0.05 then paved += 1 end
	end
	check("company-jet stand on the paved hangar apron (5 probes)", paved == 5, paved)
	local blockers = {}
	for _, s in solids do
		local c = js:PointToObjectSpace(s.d.Position)
		if math.abs(c.X) < 22 and math.abs(c.Z) < 30 and s.y2 > A.apronTop + 0.5 and s.y1 < A.apronTop + 20 then table.insert(blockers, s.d:GetFullName()) end
	end
	check("company-jet stand box free of collidable parts", #blockers == 0, blockers[1])

	------------------------------------------------------------------ stands, aircraft, jet bridges
	local planes, bridges = {}, {}
	for _, d in airport:GetDescendants() do
		if d:IsA("Model") and d.Name == "ParkedAircraft" then planes[d:GetAttribute("Stand") or 0] = d end
		if d:IsA("Model") and string.sub(d.Name, 1, 10) == "JetBridge_" then bridges[d:GetAttribute("Stand") or 0] = d end
	end
	check("CityPlan.AIRPORT.standCFrames: one per stand", #A.standCFrames == #A.stands and #A.stands == 3)
	for i, cf in A.standCFrames do
		local plane = planes[i]
		check("stand " .. i .. ": ParkedAircraft pivoted at standCFrames[i]", plane ~= nil and (plane:GetPivot().Position - cf.Position).Magnitude < 0.01 and plane:GetAttribute("Gate") == "A" .. i)
		local b = bridges[i]
		check("stand " .. i .. ": jet bridge JetBridge_A" .. i, b ~= nil)
		if plane and b then
			local root = plane.PrimaryPart
			local att = root and root:FindFirstChild("DoorL1")
			check("stand " .. i .. ": aircraft has the DoorL1 attachment (AircraftModel contract)", att ~= nil)
			if att then
				-- DoorL1 = door centre, DoorHalf = half door height (AircraftModel contract) -> sill
				local half = att:GetAttribute("DoorHalf") or 0
				local door = root.CFrame * att.CFrame * CFrame.new(0, -half, 0)
				local cabFloor = b:FindFirstChild("CabFloor")
				local cabTop = cabFloor and (cabFloor.CFrame * CFrame.new(0, cabFloor.Size.Y / 2, 0)).Position
				check("stand " .. i .. ": cab floor at the door sill (+-0.15)", cabTop ~= nil and math.abs(cabTop.Y - door.Position.Y) <= 0.15, cabTop and (cabTop.Y - door.Position.Y))
				check("stand " .. i .. ": door opening above the cab floor (DoorHalf > 1.5)", half > 1.5, half)
				-- the cab's open side (local -Z face of CabFloor) 0.4..1.0 studs off the door point, horizontally
				if cabFloor then
					local front = (cabFloor.CFrame * CFrame.new(0, 0, -cabFloor.Size.Z / 2)).Position
					local gap = (Vector3.new(front.X, 0, front.Z) - Vector3.new(door.Position.X, 0, door.Position.Z)).Magnitude
					check("stand " .. i .. ": cab opening 0.4-1.0 studs from the aircraft door", gap >= 0.4 and gap <= 1.0, gap)
					local facing = cabFloor.CFrame.LookVector:Dot(-door.LookVector)
					check("stand " .. i .. ": cab faces the door", facing > 0.95, facing)
				end
				local ad = b:GetAttribute("AircraftDoor")
				check("stand " .. i .. ": bridge records AircraftDoor", M.typeof(ad) == "Vector3" and (ad - door.Position).Magnitude < 0.01)
				local td = b:GetAttribute("TerminalDoor")
				check("stand " .. i .. ": bridge starts at the apron facade", M.typeof(td) == "Vector3" and math.abs(td.Z - T.z2) < 0.01)
				if M.typeof(td) == "Vector3" then
					local blocked = {}
					for _, s in solids do
						if s.x2 > td.X - 2.5 and s.x1 < td.X + 2.5 and s.z2 > T.z2 - 2 and s.z1 < T.z2 + 1 and s.y2 > F + 0.6 and s.y1 < F + 7 and not s.d:IsDescendantOf(b) then
							table.insert(blocked, s.d:GetFullName())
						end
					end
					check("stand " .. i .. ": gate door in the apron facade is open", #blocked == 0, blocked[1])
				end
			end
		end
	end
	-- shuttle stand (flight.md #5): the client-animated shuttle pushes back south to the taxilane and taxis in
	-- nose-first, so no ground vehicle may stand in its sweep: south of (or under) any aircraft part with the same
	-- x range and a vertical overlap (from the real parked aircraft geometry)
	do
		local plane = planes[A.shuttleStand]
		local gse = airport:FindFirstChild("GroundVehicles", true)
		local inSweep, count, hull = {}, 0, {}
		if plane then
			for _, d in plane:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 1 then
					local x1, x2, y1, y2, z1, z2 = aabb(d)
					table.insert(hull, { x1 = x1, x2 = x2, y1 = y1, z1 = z1 })
				end
			end
		end
		if gse then
			for _, d in gse:GetDescendants() do
				-- the pushback tug's tow bar is coupled to the nose gear by design (it stays at the nose)
				if d:IsA("BasePart") and d.Name ~= "TowBar" then
					count += 1
					local x1, x2, _, y2, _, z2 = aabb(d)
					for _, h in hull do
						if x2 > h.x1 and x1 < h.x2 and z2 > h.z1 and y2 > h.y1 then
							table.insert(inSweep, d.Parent.Name .. "/" .. d.Name)
							break
						end
					end
				end
			end
		end
		check("shuttle stand A" .. A.shuttleStand .. ": no ground vehicle in the shuttle's pushback/taxi-in sweep", gse ~= nil and count > 0 and #hull > 100 and #inSweep == 0, table.concat(inSweep, ","))
	end

	------------------------------------------------------------------ terminal doors (forecourt facade)
	local shut = {}
	local doorsX = table.clone(A.entrances); table.insert(doorsX, A.arrivalsDoor)
	for _, x in doorsX do
		for _, s in solids do
			if s.x2 > x - 4 and s.x1 < x + 4 and s.z2 > T.z1 - 1 and s.z1 < T.z1 + 1.5 and s.y2 > F + 0.6 and s.y1 < F + 7 then
				table.insert(shut, "x=" .. x .. ": " .. s.d:GetFullName())
			end
		end
	end
	check("departure doors + arrivals exit open in the forecourt facade (8 wide)", #shut == 0, shut[1])

	------------------------------------------------------------------ points from CityPlan
	local badPts = {}
	for label, cf in { arrival = A.arrival, g1 = A.gates[1], g2 = A.gates[2], g3 = A.gates[3], crew = A.crewRoom } do
		local p = cf.Position
		local s = solidAt(p)
		if s then table.insert(badPts, label .. " in " .. s:GetFullName()) end
		local t = topBelow(p, 4.5)
		if not t then table.insert(badPts, label .. " has no floor") end
	end
	check("arrival, gate and crew points free and on a floor", #badPts == 0, badPts[1])
	local lp = A.loungeDoor
	check("lounge door point free", solidAt(lp) == nil, solidAt(lp) and solidAt(lp):GetFullName())

	------------------------------------------------------------------ walkability grid (terminal + forecourt strip)
	local X1, X2, Z1, Z2 = T.x1, T.x2, 2420, T.z2
	local R = 1.0
	local W, H = X2 - X1, Z2 - Z1
	local blocked = {}
	local function idx(i, j) return j * W + i end
	for _, s in solids do
		if s.y2 > F + 0.6 and s.y1 < F + 5 and s.x2 > X1 - R and s.x1 < X2 + R and s.z2 > Z1 - R and s.z1 < Z2 + R then
			local i1, i2 = math.max(0, math.floor(s.x1 - R - X1)), math.min(W - 1, math.ceil(s.x2 + R - X1) - 1)
			local j1, j2 = math.max(0, math.floor(s.z1 - R - Z1)), math.min(H - 1, math.ceil(s.z2 + R - Z1) - 1)
			for j = j1, j2 do
				local cz = Z1 + j + 0.5
				if cz >= s.z1 - R and cz <= s.z2 + R then
					for i = i1, i2 do
						local cx = X1 + i + 0.5
						if cx >= s.x1 - R and cx <= s.x2 + R then
							-- exact test for rotated parts (aabb is conservative)
							local hit = true
							if s.d.CFrame.RightVector.X < 0.999 and s.d.CFrame.RightVector.X > -0.999 then
								hit = inside(s.d, Vector3.new(cx, math.clamp(F + 2.5, s.y1, s.y2), cz), R)
							end
							if hit then blocked[idx(i, j)] = true end
						end
					end
				end
			end
		end
	end
	local function cell(x, z) return math.floor(x - X1), math.floor(z - Z1) end
	local seen = {}
	local queue = {}
	local si, sj = cell(0.5, 2423.5)
	check("walk start on the forecourt is free", not blocked[idx(si, sj)])
	seen[idx(si, sj)] = true; table.insert(queue, { si, sj })
	local head = 1
	while head <= #queue do
		local c = queue[head]; head += 1
		for _, o in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local i, j = c[1] + o[1], c[2] + o[2]
			if i >= 0 and i < W and j >= 0 and j < H then
				local k = idx(i, j)
				if not seen[k] and not blocked[k] then seen[k] = true; table.insert(queue, { i, j }) end
			end
		end
	end
	local function reach(x, z, rad)
		local r = rad or 1.5
		for dz = -r, r, 0.5 do
			for dx = -r, r, 0.5 do
				local i, j = cell(x + dx, z + dz)
				if i >= 0 and i < W and j >= 0 and j < H and seen[idx(i, j)] then return true end
			end
		end
		return false
	end
	print(string.format("  walk grid: %d of %d cells reachable", #queue, W * H))
	local targets = {}
	for _, x in A.entrances do table.insert(targets, { "inside departure door x=" .. x, x, T.z1 + 3 }) end
	table.insert(targets, { "arrivals exit (inside)", A.arrivalsDoor, T.z1 + 3 })
	for i, p in A.checkin do table.insert(targets, { "check-in counter " .. i .. " (passenger side)", p.X, p.Z - 4.5 }) end
	for i, lx in A.lanes do table.insert(targets, { "security lane " .. i .. " airside", lx - 3.4, A.security + 4 }) end
	table.insert(targets, { "arrival point", A.arrival.X, A.arrival.Z })
	table.insert(targets, { "lounge (inside)", (A.lounge.x1 + A.lounge.x2) / 2, (A.lounge.z1 + A.lounge.z2) / 2 })
	table.insert(targets, { "crew room marker", A.crewRoom.X, A.crewRoom.Z })
	for i, b in bridges do
		local td = b:GetAttribute("TerminalDoor")
		if td then table.insert(targets, { "gate A" .. i .. " door", td.X, T.z2 - 2 }) end
	end
	for _, g in A.gates do table.insert(targets, { "gate point " .. g.X, g.X, g.Z }) end
	local posts = 0
	for _, d in airport:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "AirportPost" then
			posts += 1
			table.insert(targets, { "staff post " .. tostring(d:GetAttribute("CityPost")) .. " " .. tostring(d:GetAttribute("Desk") or ""), d.Position.X, d.Position.Z })
		end
	end
	check("staff posts (AirportPost) placed", posts >= 15, posts)
	local unreached = {}
	for _, t in targets do if not reach(t[2], t[3]) then table.insert(unreached, t[1] .. string.format(" (%.1f, %.1f)", t[2], t[3])) end end
	check("walkable: forecourt -> doors -> check-in, security, gates, lounge, crew room, posts, exit (" .. #targets .. " targets)", #unreached == 0, table.concat(unreached, "; "))
	-- every prompt in the terminal is within its activation distance of a reachable cell
	local farPrompts = {}
	for _, d in airport:GetDescendants() do
		if d:IsA("ProximityPrompt") and d.Parent:IsA("BasePart") then
			local p = d.Parent.Position
			if p.Z > Z1 and p.Z < Z2 and p.X > X1 and p.X < X2 then
				if not reach(p.X, p.Z, math.min(d.MaxActivationDistance - 2, 6)) then table.insert(farPrompts, d.Parent:GetFullName()) end
			end
		end
	end
	check("every terminal prompt reachable", #farPrompts == 0, farPrompts[1])

	------------------------------------------------------------------ taxi route on pavement
	local offPave = {}
	for stand = 1, #A.stands do
		for _, e in { "west", "east" } do
			local route = CityPlan.taxiRoute(stand, e)
			for k, p in route do
				local t = topBelow(p + Vector3.new(0, 0.3, 0), 1)
				if not t then table.insert(offPave, stand .. e .. "#" .. k) end
				if k > 1 then
					local q = route[k - 1]
					for f = 0.25, 0.75, 0.25 do
						local m = q:Lerp(p, f)
						if not topBelow(m + Vector3.new(0, 0.3, 0), 1) then table.insert(offPave, stand .. e .. "#" .. k .. "@" .. f) end
					end
				end
			end
		end
	end
	check("CityPlan.taxiRoute: every point and leg on a paved top", #offPave == 0, offPave[1])

	------------------------------------------------------------------ signage
	local texts = {}
	for _, d in airport:GetDescendants() do if d:IsA("TextLabel") then table.insert(texts, d.Text) end end
	local all = table.concat(texts, "\n")
	local function has(s) return string.find(all, s, 1, true) ~= nil end
	check("departure boards", has("DEPARTURES") and has("PORT MERIDIAN"))
	check("check-in signs A-D", has("CHECK-IN   A") and has("CHECK-IN   B") and has("CHECK-IN   C") and has("CHECK-IN   D"))
	check("gate signs A1-A3", has("A1") and has("A2") and has("A3"))
	check("lounge, security, duty free, restrooms, food court, baggage reclaim signs", has("BUSINESS LOUNGE") and has("SECURITY") and has("DUTY FREE") and has("RESTROOMS") and has("FOOD COURT") and has("BAGGAGE RECLAIM"))
	check("forecourt sign CITY AIRPORT · DEPARTURES / ARRIVALS", has("CITY AIRPORT") and has("DEPARTURES") and has("ARRIVALS"))
	local brands = { "airbus", "boeing", "lufthansa", "emirates", "ryanair", "easyjet", "delta air", "united airlines", "british airways",
		"starbucks", "mcdonald", "burger king", "kfc", "subway", "apple", "samsung", "sony", "nike", "coca", "pepsi", "rolex", "chanel", "hertz", "avis", "sixt", "uber" }
	local found = {}
	local low = string.lower(all)
	for _, b in brands do if string.find(low, b, 1, true) then table.insert(found, b) end end
	check("no real brand names on any airport sign", #found == 0, table.concat(found, ","))
	local emptyText = 0
	for _, d in airport:GetDescendants() do
		if d:IsA("SurfaceGui") and (not d.Parent:IsA("BasePart") or not d:FindFirstChildWhichIsA("TextLabel")) then emptyText += 1 end
	end
	check("every SurfaceGui sits on a part and carries text", emptyText == 0, emptyText)

	------------------------------------------------------------------ end of the map
	local fence, trees, horizon = 0, 0, airport:FindFirstChild("Horizon")
	for _, d in airport:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Name == "PerimeterFence" and d.Position.Z > A.runway.z2 then fence += 1 end
			if d.Name == "TreeCanopy" and d.Position.Z > A.runway.z2 then trees += 1 end
		end
	end
	check("perimeter fence and trees south of the runway", fence >= 2 and trees >= 15, fence .. "/" .. trees)
	local hills, land = 0, 0
	if horizon then for _, d in horizon:GetDescendants() do if d.Name == "Hill" then hills += 1 elseif d.Name == "CoastLand" then land += 1 end end end
	check("Persistent horizon: coast land + hills", horizon ~= nil and horizon.ModelStreamingMode == Enum.ModelStreamingMode.Persistent and hills >= 6 and land >= 4, hills .. "/" .. land)

	------------------------------------------------------------------ map edge: no slit between the city and the backdrop
	-- every point along |x| = 1150.25 .. 1154 for z -800..3800 lies on a horizon / harbour surface (CoastLand,
	-- CoastBeach, OpenSea, Sea, Quay); across each seam (city ground | coast land, harbour Sea | open sea, z = 3800)
	-- both sides +-0.25 studs are covered (a gap wider than 0.5 studs fails); the open sea and the harbour Sea
	-- share one water level
	local surf = {}
	for _, d in city:GetDescendants() do
		if d:IsA("BasePart") then
			local n = d.Name
			if n == "CoastLand" or n == "CoastBeach" or n == "OpenSea" or n == "Sea" or n == "Quay" or n == "CityGround" then
				local x1, x2, y1, y2, z1, z2 = aabb(d)
				table.insert(surf, { d = d, x1 = x1, x2 = x2, y2 = y2, z1 = z1, z2 = z2 })
			end
		end
	end
	local function covered(x, z, names)
		for _, s in surf do
			if x >= s.x1 and x <= s.x2 and z >= s.z1 and z <= s.z2 and (not names or names[s.d.Name]) and s.y2 > GR - 4 and s.y2 <= GR + 0.7 then
				if s.d.CFrame.RightVector.X > 0.999 or inside(s.d, Vector3.new(x, s.d.Position.Y, z)) then return true end
			end
		end
		return false
	end
	local slit = {}
	for _, sx in { -1, 1 } do
		for z = -800, 3800, 2 do
			for _, ax in { 1150.25, 1152, 1153.9 } do
				if not covered(sx * ax, z) then table.insert(slit, string.format("(%.2f, %d)", sx * ax, z)) end
			end
		end
	end
	check("map edge: |x| = 1150.25..1154 covered by land / sea for z -800..3800", #slit == 0, #slit .. " e.g. " .. tostring(slit[1]))
	local seam = {}
	local cityGround = { CityGround = true }
	for _, sx in { -1, 1 } do
		for z = 801, 3199, 2 do
			if not (covered(sx * 1149.75, z, cityGround) and covered(sx * 1150.25, z, { CoastLand = true })) then table.insert(seam, string.format("ground|coast (%d, %d)", sx * 1150, z)) end
		end
		for z = 3207, 3799, 2 do
			if not (covered(sx * 1149.75, z, { Sea = true }) and covered(sx * 1150.25, z, { OpenSea = true })) then table.insert(seam, string.format("sea|open sea (%d, %d)", sx * 1150, z)) end
		end
	end
	for x = -1149, 1149, 2 do
		if not (covered(x, 3799.75, { Sea = true }) and covered(x, 3800.25, { OpenSea = true })) then table.insert(seam, string.format("z 3800 (%d)", x)) end
	end
	check("map edge seams: city ground | coast land, harbour Sea | open sea, z = 3800 (no gap > 0.5)", #seam == 0, #seam .. " e.g. " .. tostring(seam[1]))
	local seaTop, openTop = nil, nil
	for _, s in surf do
		if s.d.Name == "Sea" then seaTop = s.y2 elseif s.d.Name == "OpenSea" then openTop = openTop or s.y2; if math.abs(s.y2 - openTop) > 0.001 then openTop = -1 end end
	end
	check("open sea level = harbour Sea level (no step at the seams)", seaTop ~= nil and openTop ~= nil and math.abs(seaTop - openTop) < 0.01, tostring(seaTop) .. " / " .. tostring(openTop))
	local raggedShore = 0
	if horizon then for _, d in horizon:GetDescendants() do if d:IsA("BasePart") and d.Name == "CoastLand" and d.Position.Z > 3206 then raggedShore += 1 end end end
	check("ragged shore: headlands beyond the straight quay line", raggedShore >= 4, raggedShore)

	------------------------------------------------------------------ seats (CityPlan.AIRPORT.seatRows / seats = the built pads)
	local pads = {}
	for _, d in interior:GetDescendants() do if d:IsA("BasePart") and d.Name == "SeatPad" then table.insert(pads, d) end end
	local seatBad = {}
	for k, st in A.seats do
		local on = false
		for _, pd in pads do
			local l = pd.CFrame:PointToObjectSpace(st.p)
			if math.abs(l.X) <= pd.Size.X / 2 and math.abs(l.Z) <= pd.Size.Z / 2 and math.abs(l.Y - pd.Size.Y / 2) < 0.05 then on = true; break end
		end
		if not on then table.insert(seatBad, k) end
	end
	check("CityPlan.AIRPORT.seats: one per built seat pad, each on its pad top", #A.seats == #pads and #pads >= 200 and #seatBad == 0, #A.seats .. " seats / " .. #pads .. " pads, off " .. #seatBad)
	local laneHit = {}
	for i, b in bridges do
		local td = b:GetAttribute("TerminalDoor")
		if td then
			for _, r in A.seatRows do
				if r.gate == "A" .. i and r.x2 > td.X - 6 + 0.01 and r.x1 < td.X + 17 - 0.01 then table.insert(laneHit, "A" .. i .. " row " .. r.x1 .. ".." .. r.x2 .. " vs door " .. td.X) end
			end
		end
	end
	check("gate seat rows leave the desk + boarding lane (bridge door -6 .. +17) free", #laneHit == 0, laneHit[1])
	local blockSeats = 0
	for _, d in interior:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Chair" and d.Position.Y - d.Size.Y / 2 < F + 1.2 then blockSeats += 1 end
	end
	check("table chairs are seat slabs on a post (no solid cubes from the floor)", blockSeats == 0, blockSeats)
	local wideArm = 0
	for _, d in interior:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Armrest" and (math.min(d.Size.X, d.Size.Z) > 0.2 or math.max(d.Size.X, d.Size.Z) > 2.2) then wideArm += 1 end
	end
	check("gate armrests thin and per seat side (stop at the seat edge)", wideArm == 0, wideArm)

	------------------------------------------------------------------ terminal walk graph (CityPlan.AIRPORT.walk)
	local walk = A.walk
	check("CityPlan.AIRPORT.walk: nodes, edges, suggested crowd 20-30", walk ~= nil and #walk.nodes >= 60 and #walk.edges >= #walk.nodes - 1 and walk.walkers >= 20 and walk.walkers <= 30, walk and #walk.nodes)
	if walk then
		local belts = {}
		for _, d in interior:GetDescendants() do
			if d:IsA("BasePart") and (d.Name == "QueueBelt" or d.Name == "BoardingBelt" or d.Name == "QueuePost" or d.Name == "QueueSignPost" or d.Name == "LaneStandPost") then
				local x1, x2, _, _, z1, z2 = aabb(d)
				table.insert(belts, { d = d, x1 = x1 - 0.5, x2 = x2 + 0.5, z1 = z1 - 0.5, z2 = z2 + 0.5 })
			end
		end
		local function free(x, z)
			local i, j = cell(x, z)
			return i >= 0 and i < W and j >= 0 and j < H and seen[idx(i, j)] == true
		end
		local badNode, badEdge, crossBelt = {}, {}, {}
		for _, n in walk.nodes do
			if not free(n.p.X, n.p.Z) then table.insert(badNode, n.name .. string.format(" (%.1f, %.1f)", n.p.X, n.p.Z)) end
			if math.abs(n.p.Y - F) > 0.01 then table.insert(badNode, n.name .. " y") end
		end
		for _, e in walk.edges do
			local a, b = walk.nodes[e.a].p, walk.nodes[e.b].p
			local steps = math.max(1, math.ceil(e.len / 0.5))
			for k = 0, steps do
				local q = a:Lerp(b, k / steps)
				if not free(q.X, q.Z) then table.insert(badEdge, walk.nodes[e.a].name .. "-" .. walk.nodes[e.b].name .. string.format(" @(%.1f, %.1f)", q.X, q.Z)); break end
				local hitBelt = nil
				for _, bt in belts do if q.X > bt.x1 and q.X < bt.x2 and q.Z > bt.z1 and q.Z < bt.z2 then hitBelt = bt.d; break end end
				if hitBelt then table.insert(crossBelt, walk.nodes[e.a].name .. "-" .. walk.nodes[e.b].name .. " x " .. hitBelt.Name); break end
			end
		end
		check("walk nodes on reachable floor (walk grid, radius 1)", #badNode == 0, table.concat(badNode, "; "))
		check("walk edges on reachable floor all the way", #badEdge == 0, table.concat(badEdge, "; "))
		check("walk edges never cross queue belts / posts / signs", #crossBelt == 0, table.concat(crossBelt, "; "))
		-- connected; doors, every check-in desk group, every lane, every gate, lounge, food court, reclaim reached
		local mark, stack = { [1] = true }, { 1 }
		while #stack > 0 do
			local n = table.remove(stack)
			for _, l in walk.nodes[n].links do if not mark[l] then mark[l] = true; table.insert(stack, l) end end
		end
		local cnt = 0
		for _ in mark do cnt += 1 end
		check("walk graph connected", cnt == #walk.nodes, cnt .. "/" .. #walk.nodes)
		local need = { "door1", "door2", "door3", "doorArr", "Q1desk4", "Q2desk5", "Q3desk2", "Q4desk4", "S1egate", "S2egate", "S3egate", "S1recompose",
			"A1", "A2", "A3", "A1board", "reception", "noodle", "reclaimW", "news", "dutyE" }
		local missing = {}
		for _, nm in need do if not walk.byName[nm] then table.insert(missing, nm) end end
		check("walk graph covers doors, desks, lanes, gates, lounge, shops, food court, reclaim", #missing == 0, table.concat(missing, ","))
		local boardOff = {}
		for i, b in bridges do
			local td = b:GetAttribute("TerminalDoor")
			local nb = walk.byName["A" .. i .. "board"]
			if td and nb and math.abs(walk.nodes[nb].p.X - td.X) > 0.75 then table.insert(boardOff, "A" .. i .. string.format(" %.2f vs %.2f", walk.nodes[nb].p.X, td.X)) end
		end
		check("walk 'board' nodes line up with the jet-bridge doors", #boardOff == 0, boardOff[1])
	end

	------------------------------------------------------------------ flight information = the real shuttle (FlightPlan)
	local FP = M.require(RS.Shared.FlightPlan)
	local fout, fback = FP.CONFIG.flights.out, FP.CONFIG.flights.back
	local wrong, clock, tagged = {}, {}, 0
	for _, d in airport:GetDescendants() do
		if d:IsA("TextLabel") then
			local t = d.Text
			for num in string.gmatch(t, "PM %d+") do if num ~= fout and num ~= fback then table.insert(wrong, num) end end
			if string.find(t, "BOARDING", 1, true) and not string.find(t, "BOARDING PASS", 1, true) and not string.find(t, "BOARDING TIMES", 1, true) then table.insert(wrong, "static BOARDING: " .. string.gsub(t, "\n", " | ")) end
			if string.find(string.lower(t), "every 90", 1, true) then table.insert(wrong, "every 90 minutes") end
			if string.find(t, "%d%d:%d%d") then table.insert(clock, (string.gsub(t, "\n", " | "))) end
		end
		if d:IsA("BasePart") and d:HasTag("FlightInfoBoard") then
			tagged += 1
			if d:GetAttribute("Board") == nil or d:GetAttribute("Flight") == nil then table.insert(wrong, "untagged attrs " .. d.Name) end
		end
	end
	check("flight info: only " .. fout .. " / " .. fback .. ", no static BOARDING, no 'every 90 minutes'", #wrong == 0, wrong[1])
	check("flight info: no fixed clock times on boards and monitors", #clock == 0, clock[1])
	check("flight info boards tagged FlightInfoBoard (Board / Gate / Flight)", tagged >= 12, tagged)
	local gateWrong = {}
	for _, d in airport:GetDescendants() do
		if d:IsA("TextLabel") and d.Parent and d.Parent.Parent and (d.Parent.Parent.Name == "GateDoorSign" or d.Parent.Parent.Name == "GateSign") then
			local g = d.Parent.Parent.Parent and d.Parent.Parent.Parent.Name
			local shuttle = g == "GateA" .. A.shuttleStand
			local hasFlight = string.find(d.Text, fout, 1, true) ~= nil
			if shuttle ~= hasFlight then table.insert(gateWrong, tostring(g) .. ": " .. d.Text) end
		end
	end
	check("only the shuttle gate A" .. A.shuttleStand .. " shows a flight; the other gates read closed", #gateWrong == 0, gateWrong[1])
	local welcomeAirside = 0
	for _, d in airport:GetDescendants() do
		if d:IsA("TextLabel") and string.find(d.Text, "WELCOME TO", 1, true) then
			local p = d.Parent.Parent
			if p:IsA("BasePart") and p.Position.Z > A.security then welcomeAirside += 1 end
		end
	end
	check("'WELCOME TO BUSINESS CITY' faces arrivals (landside), not departing passengers", welcomeAirside == 0, welcomeAirside)

	------------------------------------------------------------------ misc reviewer items
	local far = 0
	for _, d in airport:GetDescendants() do
		if (d.Name == "TowerBeacon" or d.Name == "Radar") and d:HasTag("PropFx") and (d:GetAttribute("FxFar") or 0) >= 600 and (d:GetAttribute("FxVertical") or 0) >= 120 then far += 1 end
	end
	check("tower radar + beacon carry FxFar / FxVertical (visible range)", far == 2, far)
	local clips = {}
	local function boxesOf(name)
		local list = {}
		for _, d in interior:GetDescendants() do if d:IsA("BasePart") and d.Name == name then local x1, x2, y1, y2, z1, z2 = aabb(d); table.insert(list, { d = d, x1 = x1, x2 = x2, y1 = y1, y2 = y2, z1 = z1, z2 = z2 }) end end
		return list
	end
	local spines = boxesOf("IslandSpine")
	for _, nm in { "TrayStack", "DivestTable" } do
		for _, t in boxesOf(nm) do
			for _, sp in spines do
				if t.x2 > sp.x1 + 0.01 and t.x1 < sp.x2 - 0.01 and t.z2 > sp.z1 + 0.01 and t.z1 < sp.z2 - 0.01 then table.insert(clips, nm .. string.format(" x %.1f", t.x1)) end
			end
		end
	end
	check("security tray stacks / divest tables clear of the check-in island spines", #clips == 0, clips[1])
	local stagingBox = nil
	local gx1 = A.standCFrames[A.shuttleStand].Position.X
	for _, d in airport:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "CateringBox" and math.abs(d.Position.X - (gx1 + 60)) < 4 then stagingBox = d end
	end
	check("shuttle staging box: the waiting catering truck has its box lowered", stagingBox ~= nil and stagingBox.Position.Y - stagingBox.Size.Y / 2 < A.apronTop + 2.5, stagingBox and stagingBox.Position.Y)
	local gseN = 0
	for _, d in airport:GetDescendants() do
		if d:IsA("BasePart") and d.Position.X > -560 and d.Position.X < -280 and d.Position.Z > 2570 and d.Position.Z < 2696 and d.Position.Y > A.apronTop + 0.1 then gseN += 1 end
	end
	check("west apron GSE parking furnished (carts, dollies, ULDs, tugs, loaders)", gseN >= 80, gseN)
	local roadLines = 0
	for _, d in airport:GetDescendants() do if d:IsA("BasePart") and d.Name == "RoadLine" then roadLines += 1 end end
	check("equipment road lines along the facade and behind the stands", roadLines >= 8, roadLines)

	------------------------------------------------------------------ determinism
	local function signature(root)
		local n, sx, sy, sz = 0, 0, 0, 0
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then n += 1; sx += d.Position.X * (n % 7 + 1); sy += d.Size.Y; sz += d.Position.Z end
		end
		return string.format("%d:%.3f:%.3f:%.3f", n, sx, sy, sz)
	end
	local s1 = signature(airport)
	local again = Builder.build(TICKET)
	local s2 = signature(again.Airport)
	check("deterministic: a rebuild places the same parts", s1 == s2, s1 .. " vs " .. s2)
end

local ok, err = M.runMain(body, { timeout = 300, maxSteps = 4000000 })
if not ok then failc += 1; print("ERROR " .. tostring(err)) end
print(string.format("airport: %d passed, %d failed", pass, failc))
if failc > 0 then error("airport failed", 0) end
