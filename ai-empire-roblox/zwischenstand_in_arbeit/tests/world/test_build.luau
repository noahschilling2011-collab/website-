--!nocheck
-- World package: the built world in the headless mock (CampusService district + CityBuilder city).
-- Budgets (parts <= 10,000, real lights <= 40 per zone), decoration flags, anchoring, streaming modes
-- (interiors Atomic, skyline shells Persistent), prompts (18 meetings with the CityPlan client ids, check-in
-- counters for both directions, Public so WorldController shows them), receptionist posts, roads and the
-- three district corridors free of obstacles, destination points not inside solid parts, boundary walls.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_world && tools/luau tests/world/test_build.luau [-a .gen_dir]
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
	local Vector3, CFrame, Enum = G.Vector3, G.CFrame, G.Enum
	local game = M.game
	local RS, S = game.ReplicatedStorage, game.ServerScriptService.Server.Services
	local CityPlan = M.require(RS.Shared.Config.CityPlan)
	local Campus = M.require(S.CampusService)
	local Builder = M.require(S.CityBuilder)
	Campus.init()
	local city = Builder.build("Port Meridian · $1.5k return")
	local district = game.Workspace:FindFirstChild("TechDistrict")
	check("world + district built", city ~= nil and city.Parent == game.Workspace and district ~= nil)
	local parts, lightsByZone, unanchored, decoBad, anyLight = {}, {}, 0, 0, 0
	for _, d in city:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			if not d.Anchored then unanchored += 1 end
			if not d.CanCollide and (d.CanQuery or d.CanTouch) then decoBad += 1 end
		elseif d:IsA("Light") then
			anyLight += 1
			local z = if d.Parent:IsA("BasePart") then (CityPlan.zoneAt(d.Parent.Position) or "none") else "noparent"
			lightsByZone[z] = (lightsByZone[z] or 0) + 1
		end
	end
	-- budgets per zone (phase 2): downtown as before; City Airport rebuilt by the airport package (terminal
	-- interior <= 3,500, exterior/apron additions <= 1,500, plus the parked aircraft from AircraftModel);
	-- Port Meridian expanded by the metro package (brief: 15-20k, built once, far away and streamed out)
	local byZone, interiorParts = {}, 0
	for _, p in parts do
		local z = CityPlan.zoneAt(p.Position) or "none"
		byZone[z] = (byZone[z] or 0) + 1
	end
	local ti = city:FindFirstChild("Airport") and city.Airport:FindFirstChild("Terminal") and city.Airport.Terminal:FindFirstChild("TerminalInterior")
	if ti then for _, d in ti:GetDescendants() do if d:IsA("BasePart") then interiorParts += 1 end end end
	check("part budget downtown <= 3,000", (byZone.downtown or 0) <= 3000 and (byZone.downtown or 0) > 500, byZone.downtown)
	check("part budget airport <= 7,000 (terminal interior <= 3,500)", (byZone.airport or 0) <= 7000 and interiorParts <= 3500 and interiorParts > 500, tostring(byZone.airport) .. " / interior " .. interiorParts)
	check("part budget Port Meridian <= 20,000", (byZone.abroad or 0) <= 20000 and (byZone.abroad or 0) > 500, byZone.abroad)
	check("part budget: whole shared world <= 30,000", #parts <= 30000 and #parts > 1500, #parts)
	print(string.format("  world parts %d (downtown %d, airport %d, terminal interior %d, abroad %d), lights %d", #parts, byZone.downtown or 0, byZone.airport or 0, interiorParts, byZone.abroad or 0, anyLight))
	for z, n in lightsByZone do check("real lights in " .. z .. " <= 40", n <= 40 and z ~= "noparent" and z ~= "district", n) end
	check("every part anchored", unanchored == 0, unanchored)
	check("decorative parts: CanCollide/CanTouch/CanQuery all false", decoBad == 0, decoBad)
	local oversize = 0
	for _, p in parts do if p.Size.X > 2048 or p.Size.Y > 2048 or p.Size.Z > 2048 then oversize += 1 end end
	check("no part above the 2048-stud limit", oversize == 0)

	------------------------------------------------------------------ streaming modes
	local interiors, atomic, persistent, skylineIds = 0, 0, 0, {}
	for _, d in city:GetDescendants() do
		if d:IsA("Model") then
			if d.Name == "Interior" or d.Name == "TerminalInterior" then interiors += 1; if d.ModelStreamingMode == Enum.ModelStreamingMode.Atomic then atomic += 1 end end
			if d.ModelStreamingMode == Enum.ModelStreamingMode.Persistent then
				persistent += 1
				local b = d.Parent and d.Parent:GetAttribute("BuildingId")
				table.insert(skylineIds, b or d.Name)
			end
		end
	end
	check("every building interior is an Atomic model", interiors == 18 + 2 + 1 + 2 and atomic == interiors, atomic .. "/" .. interiors)
	local pParts = 0
	for _, d in city:GetDescendants() do
		if d:IsA("BasePart") then
			local a = d:FindFirstAncestorWhichIsA("Model")
			while a and a ~= city do if a.ModelStreamingMode == Enum.ModelStreamingMode.Persistent then pParts += 1; break end; a = a.Parent end
		end
	end
	print(string.format("  persistent models %d (%d parts), atomic interiors %d", persistent, pParts, atomic))
	-- skyline shells + the control tower + the airport horizon backdrop (+ Port Meridian landmarks)
	check("Persistent only for the skyline / horizon (<= 12 models, <= 800 parts)", persistent >= 3 and persistent <= 12 and pParts <= 800, persistent .. " models / " .. pParts .. " parts: " .. table.concat(skylineIds, ","))

	------------------------------------------------------------------ prompts / posts
	local meetings, checkHome, checkAbroad, navigate, notPublic = {}, 0, 0, 0, 0
	for _, d in city:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			if d:GetAttribute("Public") ~= true then notPublic += 1 end
			local a = d:GetAttribute("CityAction")
			if a == "meeting" then meetings[d:GetAttribute("ClientId")] = d
			elseif a == "checkin" then if d:GetAttribute("FlightTo") == "abroad" then checkHome += 1 elseif d:GetAttribute("FlightTo") == "home" then checkAbroad += 1 end
			elseif a == "navigate" then navigate += 1 end
		end
	end
	check("every prompt Public (WorldController shows it)", notPublic == 0, notPublic)
	local missing = 0
	for _, c in CityPlan.CLIENTS do
		local q = meetings[c.id]
		if not q or q.ActionText ~= "Start meeting" or q.ObjectText ~= c.name then missing += 1 end
	end
	check("a 'Start meeting' prompt per client office (ClientId = CityPlan id)", missing == 0 and #CityPlan.CLIENTS == 18, missing)
	check("check-in prompts: home counters fly abroad, abroad counters fly home", checkHome == #CityPlan.AIRPORT.checkin and checkAbroad == #CityPlan.ABROAD.checkin)
	check("GPS kiosks", navigate >= 3)
	local ticketShown = false
	for _, d in city:GetDescendants() do if d:IsA("ProximityPrompt") and d:GetAttribute("FlightTo") == "abroad" and string.find(d.ObjectText, "$1.5k", 1, true) then ticketShown = true end end
	check("home check-in shows the ticket price", ticketShown)
	local posts = 0
	for _, d in city:GetDescendants() do if d.Name == "ReceptionistPost" and d:GetAttribute("CityPost") then posts += 1 end end
	check("receptionist posts in every office/tower and both hotels", posts == 20, posts)

	------------------------------------------------------------------ obstacles on roads and corridors
	local function solidAt(p, ignoreRoads)
		-- any collidable part containing point p (oriented box test)
		local hits = {}
		for _, root in { city, district } do
			for _, d in root:GetDescendants() do
				if d:IsA("BasePart") and d.CanCollide and d.Transparency < 0.99 then
					local l = d.CFrame:PointToObjectSpace(p)
					local h = d.Size / 2
					if math.abs(l.X) <= h.X and math.abs(l.Y) <= h.Y and math.abs(l.Z) <= h.Z then table.insert(hits, d) end
				end
			end
		end
		return hits
	end
	-- obstacles: any collidable part reaching into the body band above a road / corridor surface
	local function aabb(d)
		local cf, h = d.CFrame, d.Size / 2
		local r = cf.RightVector; local u = cf.UpVector; local l = cf.LookVector
		local ex = math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z
		local ey = math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z
		local ez = math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z
		return cf.X - ex, cf.X + ex, cf.Y - ey, cf.Y + ey, cf.Z - ez, cf.Z + ez
	end
	local solids = {}
	for _, root in { city, district } do
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") and d.CanCollide and d.Transparency < 0.99 then
				local x1, x2, y1, y2, z1, z2 = aabb(d)
				table.insert(solids, { d = d, x1 = x1, x2 = x2, y1 = y1, y2 = y2, z1 = z1, z2 = z2 })
			end
		end
	end
	local function obstacles(x1, x2, z1, z2, ylo, yhi)
		local out = {}
		for _, s in solids do
			if s.x2 > x1 and s.x1 < x2 and s.z2 > z1 and s.z1 < z2 and s.y2 > ylo and s.y1 < yhi then table.insert(out, s.d:GetFullName()) end
		end
		return out
	end
	local blocked = {}
	for _, r in CityPlan.ROADS do
		local rr = CityPlan.roadRect(r)
		for _, name in obstacles(rr.x1 + 1, rr.x2 - 1, rr.z1 + 1, rr.z2 - 1, CityPlan.ROAD_TOP + 0.5, CityPlan.ROAD_TOP + 6) do table.insert(blocked, r.id .. ": " .. name) end
	end
	check("no obstacle on any city road (body band above the asphalt)", #blocked == 0, blocked[1])
	-- the roads through the three district corridors, from the boulevard asphalt (z 530, across its outer
	-- sidewalk) to the city edge, stay free: no trees, posts, lamps (sidewalk lamps beside them are fine)
	local corr = {}
	for _, r in CityPlan.ROADS do
		if r.axis == "z" and r.a1 <= 540 then
			local rr = CityPlan.roadRect(r)
			for _, name in obstacles(rr.x1 + 1, rr.x2 - 1, 530, 800, CityPlan.GROUND + 0.7, CityPlan.GROUND + 6) do table.insert(corr, r.id .. ": " .. name) end
		end
	end
	check("district corridors free of obstacles", #corr == 0, corr[1])
	local supports = 0
	for _, d in district:GetDescendants() do if d.Name == "LinkSupport" then supports += 1 end end
	check("CampusService builds a street-level support under each corridor", supports == #CityPlan.DISTRICT_LINKS)
	local directory = district:FindFirstChild("DistrictDirectory", true)
	local label = directory and directory:FindFirstChildWhichIsA("TextLabel", true)
	check("district directory points south", label ~= nil and string.find(label.Text, "SOUTH: DOWNTOWN · AIRPORT", 1, true) ~= nil)

	------------------------------------------------------------------ destination points
	local inside = {}
	for _, d in CityPlan.DESTINATION_LIST do
		for label, cf in { door = d.door, lobby = d.lobby, meeting = d.meeting } do
			if cf then
				local hits = solidAt(cf.Position)
				if #hits > 0 then table.insert(inside, d.id .. "." .. label .. " in " .. hits[1]:GetFullName()) end
			end
		end
		for i, bay in d.parking do
			local hits = solidAt(bay.Position)
			if #hits > 0 then table.insert(inside, d.id .. ".bay" .. i .. " in " .. hits[1]:GetFullName()) end
		end
	end
	for label, cf in { arrival = CityPlan.AIRPORT.arrival, abroad = CityPlan.ABROAD.arrival, g1 = CityPlan.AIRPORT.gates[1], g2 = CityPlan.AIRPORT.gates[2], g3 = CityPlan.AIRPORT.gates[3] } do
		local hits = solidAt(cf.Position)
		if #hits > 0 then table.insert(inside, label .. " in " .. hits[1]:GetFullName()) end
	end
	check("no destination point (door, lobby, meeting, bays, arrivals, gates) inside a solid part", #inside == 0, inside[1])
	-- arrival CFrames stand on a floor (a collidable top within 4 studs below)
	local function floorBelow(p)
		for _, root in { city } do
			for _, d in root:GetDescendants() do
				if d:IsA("BasePart") and d.CanCollide then
					local l = d.CFrame:PointToObjectSpace(p); local h = d.Size / 2
					if math.abs(l.X) <= h.X and math.abs(l.Z) <= h.Z and l.Y > h.Y and l.Y - h.Y < 4.5 then return true end
				end
			end
		end
		return false
	end
	check("arrival halls have a floor under the arrival point", floorBelow(CityPlan.AIRPORT.arrival.Position) and floorBelow(CityPlan.ABROAD.arrival.Position))
	local walls = 0
	for _, d in city:GetDescendants() do if d.Name == "BoundaryWall" and d.CanCollide and d.Transparency >= 1 then walls += 1 end end
	check("invisible boundary walls around Port Meridian and the south strip", walls >= 10, walls)
	-- rebuild is idempotent: a second build replaces the first
	local again = Builder.build("x")
	local count = 0; for _, d in game.Workspace:GetChildren() do if d.Name == "WorldCity" then count += 1 end end
	check("a second build replaces the first (one WorldCity)", count == 1 and again.Parent == game.Workspace)
end

local ok, err = M.runMain(body, { timeout = 120, maxSteps = 2000000 })
if not ok then failc += 1; print("ERROR " .. tostring(err)) end
print(string.format("world_build: %d passed, %d failed", pass, failc))
if failc > 0 then error("world_build failed", 0) end
