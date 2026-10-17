--!nocheck
-- Metro package: MetroBuilder (Port Meridian) through the real CityBuilder.build in the mock.
--   VIP markers (BusinessLounge, VipLimoStand, two Helipads + HelipadExit), apron (ShuttleStand, ApronDoor, parked
--   aircraft on stand 2, stand 1 hull space free, towers 75 studs off the runway), landmark (Persistent, lit crown),
--   skyline towers (Atomic, cheap), client-life hooks (MetroSignal / MetroNightGlow / MetroWheel), budgets
--   (parts, lights, decoration flags, Persistent parts), travel flow (Fly home check-ins, kiosks, meetings,
--   arrival point, boundary walls), signage (districts, generic ads, no brand names, English), determinism.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_metro && tools/luau tests/metro/test_build.luau [-a .gen_dir]
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
local BASE_PARTS = 781 -- Port Meridian parts before the metro package (world dump of agents/stable/src_p2_base_0805)
local BUDGET = 4500

local function body()
	local Vector3, Enum, typeof = G.Vector3, G.Enum, G.typeof
	local game = M.game
	local RS = game.ReplicatedStorage
	local Plan = M.require(RS.Shared.Config.MetroPlan)
	local City = M.require(RS.Shared.Config.CityPlan)
	local Builder = M.require(game.ServerScriptService.Server.Services.CityBuilder)
	local CS = game:GetService("CollectionService")
	local world = Builder.build("Port Meridian · $1.5k return")
	local pm = world:FindFirstChild("PortMeridian")
	check("PortMeridian model", pm ~= nil and pm:GetAttribute("City") == "Port Meridian")
	local all = pm:GetDescendants()
	local parts = {}
	for _, d in all do if d:IsA("BasePart") then table.insert(parts, d) end end
	print(string.format("Port Meridian: %d parts (+%d over the pre-metro city), real lights abroad %d", #parts, #parts - BASE_PARTS, Builder.lights.abroad or 0))
	check("part budget: <= +4,500 over the pre-metro city", #parts - BASE_PARTS <= BUDGET, #parts)
	check("real lights in Port Meridian <= 40 (zone budget)", (Builder.lights.abroad or 0) <= 40, Builder.lights.abroad)
	local badFlags, unanch = 0, 0
	for _, p in parts do
		if not p.CanCollide and (p.CanQuery or p.CanTouch) then badFlags += 1 end
		if not p.Anchored then unanch += 1 end
	end
	check("decoration parts never touch / query; everything anchored", badFlags == 0 and unanch == 0, badFlags .. " / " .. unanch)
	local thin = {}
	for _, p in parts do if math.min(p.Size.X, p.Size.Y, p.Size.Z) < 0.005 or math.max(p.Size.X, p.Size.Y, p.Size.Z) > 2048 then table.insert(thin, p.Name .. tostring(p.Size)) end end
	check("no negative / clamped part sizes", #thin == 0, table.concat(thin, ","))
	local function find(name, class)
		local out = {}
		for _, d in all do if d.Name == name and (class == nil or d:IsA(class)) then table.insert(out, d) end end
		return out
	end
	local blocks = pm:FindFirstChild("CityBlocks")
	------------------------------------------------------------------ VIP
	local lounge = find("BusinessLounge", "Model")[1]
	local seats = 0
	if lounge then for _, d in lounge:GetDescendants() do if d:IsA("Seat") then seats += 1 end end end
	local t = City.ABROAD.terminal
	local lp = lounge and lounge:GetBoundingBox().Position
	check("BusinessLounge: Atomic model inside the arrival terminal, >= 8 seats", lounge and lounge.ModelStreamingMode == Enum.ModelStreamingMode.Atomic and seats >= 8 and lp.X > t.x1 and lp.X < t.x2 and lp.Z > t.z1 and lp.Z < t.z2, seats)
	local stand = find("VipLimoStand", "BasePart")
	local sp = stand[1]
	check("VipLimoStand: one marker part (Purpose VIP, abroad, invisible, no collision) at MetroPlan.VIP_LIMO.stand",
		#stand == 1 and sp:GetAttribute("Purpose") == "VIP" and sp:GetAttribute("Zone") == "abroad" and sp.Transparency == 1 and not sp.CanCollide
		and (sp.Position - Plan.VIP_LIMO.stand.Position).Magnitude < 0.2 and sp.CFrame.LookVector:Dot(Plan.VIP_LIMO.stand.LookVector) > 0.99, #stand)
	local pads = find("Helipad", "BasePart")
	local vip, airport
	for _, p in pads do if p:GetAttribute("Purpose") == "VIP" then vip = p elseif p:GetAttribute("Purpose") == "VIPAirport" then airport = p end end
	check("two Helipad markers: Purpose VIP + VIPAirport", #pads == 2 and vip ~= nil and airport ~= nil, #pads)
	check("VIP helipad on the Meridian Grand Hotel roof (top = roof deck)", vip and math.abs(vip.Position.Y + vip.Size.Y / 2 - (Plan.HOTEL_ROOF + 1)) < 0.01 and vip.CanCollide and vip:IsDescendantOf(pm:FindFirstChild("Hotel_intl_hotel")))
	check("airport helipad at street level beside the terminal", airport and math.abs(airport.Position.Y + airport.Size.Y / 2 - (City.GROUND + 1)) < 0.01 and airport.Position.X > t.x2 + 50)
	local roofTop = nil
	for _, d in pm:FindFirstChild("Hotel_intl_hotel"):GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide and d.Name ~= "Volume" and math.abs(d.Position.X - vip.Position.X) < d.Size.X / 2 and math.abs(d.Position.Z - vip.Position.Z) < d.Size.Z / 2 and d ~= vip and d.Position.Y < vip.Position.Y then
			local top = d.Position.Y + d.Size.Y / 2
			if not roofTop or top > roofTop then roofTop = top end
		end
	end
	check("hotel helipad deck rests on the hotel roof (no gap)", roofTop and math.abs(roofTop - Plan.HOTEL_ROOF) < 0.05, roofTop)
	check("HelipadExit marker on the hotel roof", #find("HelipadExit") == 1 and find("HelipadExit")[1]:GetAttribute("To") == "intl_hotel")
	------------------------------------------------------------------ apron (flight request #7)
	local AP = Plan.APRON
	local G0 = City.GROUND
	local ss = find("ShuttleStand", "BasePart")
	local s1 = ss[1]
	check("ShuttleStand: one invisible, non-colliding marker at MetroPlan.APRON.stand (Stand PM1)", #ss == 1 and s1.Transparency == 1 and not s1.CanCollide and (s1.Position - AP.stand.Position).Magnitude < 0.01
		and s1.CFrame.LookVector:Dot(AP.stand.LookVector) > 0.999 and s1:GetAttribute("Stand") == "PM1", #ss)
	local ad = find("ApronDoor", "BasePart")
	local d = AP.door
	local adp = ad[1]
	check("ApronDoor: one marker in the hall's east wall, facing the apron", #ad == 1 and adp.Transparency == 1 and not adp.CanCollide and math.abs(adp.Position.X - (t.x2 - 0.75)) < 0.01
		and adp.Position.Z > d.z1 and adp.Position.Z < d.z2 and adp.CFrame.LookVector.X > 0.99 and math.abs(adp.Size.X - (d.z2 - d.z1)) < 0.01, #ad)
	-- the opening is free (wall cut + lintel above 12 studs): no collidable part inside the door box (3 studs either side of the wall)
	local blockDoor = {}
	for _, p in parts do
		if p.CanCollide and p.Transparency < 1 then
			local hx, hy, hz = p.Size.X / 2, p.Size.Y / 2, p.Size.Z / 2
			if math.abs(p.Position.X - t.x2) < hx + 3 and p.Position.Z + hz > d.z1 + 0.2 and p.Position.Z - hz < d.z2 - 0.2 and p.Position.Y + hy > G0 + 0.6 and p.Position.Y - hy < G0 + 11.5 then table.insert(blockDoor, p.Name) end
		end
	end
	check("ApronDoor opening free (12 wide, 11.5 high)", #blockDoor == 0, table.concat(blockDoor, ","))
	local plane = nil
	for _, m in find("ParkedAircraft", "Model") do plane = m end
	check("parked aircraft on stand 2 of the apron (off the runway)", plane and (plane:GetPivot().Position - AP.stand2.Position).Magnitude < 0.01 and plane:GetAttribute("Stand") == "PM2" and plane:GetPivot().Position.Z > City.ABROAD.runway.z2)
	-- stand 1 hull (AircraftModel "320" at scale 1.8, measured bands: fuselage / tailplane |side| <= 20 from 60 ahead of
	-- the pivot to 66 behind, inner wings |side| <= 35 from 25 ahead to 57 behind, outer wings to 57 from 18 ahead to
	-- 17 behind; fin top 42) free of every visible part above the apron (the stand faces west: ahead = -x, side = z)
	local hull = {}
	local st = AP.stand
	local bands = { { -60, 66, 20 }, { -25, 57, 35 }, { -18, 17, 57 } }
	for _, p in parts do
		if p.Transparency < 1 and not (plane and p:IsDescendantOf(plane)) then
			local hx, hy, hz = p.Size.X / 2, p.Size.Y / 2, p.Size.Z / 2
			local ex = math.abs(p.CFrame.RightVector.X) * hx + math.abs(p.CFrame.UpVector.X) * hy + math.abs(p.CFrame.LookVector.X) * hz
			local ez = math.abs(p.CFrame.RightVector.Z) * hx + math.abs(p.CFrame.UpVector.Z) * hy + math.abs(p.CFrame.LookVector.Z) * hz
			local ey = math.abs(p.CFrame.RightVector.Y) * hx + math.abs(p.CFrame.UpVector.Y) * hy + math.abs(p.CFrame.LookVector.Y) * hz
			if p.Position.Y + ey > G0 + 0.6 and p.Position.Y - ey < G0 + 42 then
				for _, b in bands do
					if p.Position.X + ex > st.X + b[1] and p.Position.X - ex < st.X + b[2] and p.Position.Z + ez > st.Z - b[3] and p.Position.Z - ez < st.Z + b[3] then table.insert(hull, p.Name); break end
				end
			end
		end
	end
	check("stand 1 free for the shuttle (nothing visible inside its hull box)", #hull == 0, table.concat(hull, ",", 1, math.min(8, #hull)))
	-- runway strip: no building part within 75 studs of the runway centreline outside the hall (CityPlan terminal)
	local rc = (City.ABROAD.runway.z1 + City.ABROAD.runway.z2) / 2
	local strip = {}
	for _, p in blocks and blocks:GetDescendants() or {} do
		if p:IsA("BasePart") and p.Position.Z - p.Size.Z / 2 < rc + 75 then table.insert(strip, p:GetFullName()) end
	end
	check("airport-district towers keep 75 studs off the runway centreline", #strip == 0, table.concat(strip, ",", 1, math.min(4, #strip)))
	------------------------------------------------------------------ landmark + skyline
	local spire = find("MeridianSpire", "Model")[1]
	local sparts, stop = 0, 0
	if spire then for _, d in spire:GetDescendants() do if d:IsA("BasePart") then sparts += 1; stop = math.max(stop, d.Position.Y + d.Size.Y / 2) end end end
	check("Meridian Spire: Persistent, <= 90 parts, 520+ studs with the mast", spire and spire.ModelStreamingMode == Enum.ModelStreamingMode.Persistent and sparts <= 90 and stop - City.GROUND >= 520, sparts .. " parts, top " .. (stop - City.GROUND))
	local spireLights = 0
	if spire then for _, d in spire:GetDescendants() do if d:IsA("PointLight") then spireLights += 1 end end end
	check("spire crown lit (real light + neon)", spireLights >= 1)
	local persistent, pparts = {}, 0
	for _, d in pm:GetDescendants() do
		if d:IsA("Model") and d.ModelStreamingMode == Enum.ModelStreamingMode.Persistent then table.insert(persistent, d.Name); for _, x in d:GetDescendants() do if x:IsA("BasePart") then pparts += 1 end end end
	end
	check("Persistent only for the landmark", #persistent == 1 and pparts <= 90, table.concat(persistent, ","))
	local nt, maxp, badMode = 0, 0, 0
	for _, m in blocks:GetChildren() do
		nt += 1
		if m.ModelStreamingMode ~= Enum.ModelStreamingMode.Atomic then badMode += 1 end
		local n = 0
		for _, d in m:GetDescendants() do if d:IsA("BasePart") then n += 1 end end
		maxp = math.max(maxp, n)
	end
	check("background towers: one Atomic model per lot, <= 22 parts each", nt == #Plan.LOTS and badMode == 0 and maxp <= 22, nt .. " towers, max " .. maxp .. " parts")
	------------------------------------------------------------------ client hooks
	local sig = CS:GetTagged("MetroSignal")
	local sigOk = 0
	for _, p in sig do if typeof(p:GetAttribute("Junction")) == "number" and (p:GetAttribute("Axis") == "x" or p:GetAttribute("Axis") == "z") then sigOk += 1 end end
	check("signal lamps tagged MetroSignal (8 per junction)", #sig == #Plan.portMeridian().junctions * 8 and sigOk == #sig, #sig)
	local glow = CS:GetTagged("MetroNightGlow")
	local gOk = 0
	for _, p in glow do if typeof(p:GetAttribute("GlowColor")) == "Color3" then gOk += 1 end end
	check("night glow parts tagged (GlowColor)", #glow >= 100 and gOk == #glow, #glow)
	local wheel = CS:GetTagged("MetroWheel")[1]
	local wp = 0
	if wheel then for _, d in wheel:GetDescendants() do if d:GetAttribute("WheelAngle") then wp += 1 end end end
	check("Harbour Wheel tagged MetroWheel with Hub + 52 moving parts", wheel and typeof(wheel:GetAttribute("Hub")) == "Vector3" and wp == 52, wp)
	------------------------------------------------------------------ travel flow, prompts, walls
	local fly, meet, nav = 0, {}, 0
	for _, d in pm:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			if d:GetAttribute("FlightTo") == "home" then fly += 1 end
			if d:GetAttribute("CityAction") == "meeting" then meet[d:GetAttribute("ClientId")] = true end
			if d:GetAttribute("CityAction") == "navigate" then nav += 1 end
			if d:GetAttribute("Public") ~= true then fly = -99 end
		end
	end
	local nm = 0
	for _ in meet do nm += 1 end
	check("check-in 'Fly home' x2, 4 tower meetings, GPS kiosks, all prompts Public", fly == #City.ABROAD.checkin and nm == 4 and nav >= 3, fly .. " / " .. nm .. " / " .. nav)
	local arr = City.ABROAD.arrival.Position
	local floor = false
	for _, p in parts do
		if p.CanCollide and math.abs(p.Position.X - arr.X) < p.Size.X / 2 and math.abs(p.Position.Z - arr.Z) < p.Size.Z / 2 then
			local top = p.Position.Y + p.Size.Y / 2
			if top <= arr.Y and top > arr.Y - 4 then floor = true end
		end
	end
	check("arrival point inside the terminal above its floor", floor and arr.X > t.x1 and arr.X < t.x2 and arr.Z > t.z1 and arr.Z < t.z2)
	local walls = find("BoundaryWall", "BasePart")
	local wOk = 0
	for _, w in walls do if w.Transparency == 1 and w.CanCollide then wOk += 1 end end
	check("4 invisible boundary walls", #walls == 4 and wOk == 4, #walls)
	------------------------------------------------------------------ signage
	local texts = {}
	for _, d in pm:GetDescendants() do if d:IsA("TextLabel") then table.insert(texts, d.Text) end end
	local joined = string.upper(table.concat(texts, "\n"))
	local missing = {}
	for _, n in { "FINANCIAL DISTRICT", "HARBOUR QUARTER", "EXCHANGE QUARTER", "PARKSIDE", "AIRPORT DISTRICT", "BUSINESS LOUNGE", "VIP CHAUFFEUR SERVICE", "METRO", "BUS", "MERIDIAN SPIRE", "MERIDIAN GRAND HOTEL", "WELCOME TO PORT MERIDIAN", "HARBOUR WHEEL" } do
		if not string.find(joined, n, 1, true) then table.insert(missing, n) end
	end
	check("district / landmark / VIP signs present", #missing == 0, table.concat(missing, ","))
	local brands = {}
	for _, b in { "AIRBUS", "BOEING", "EMIRATES", "LUFTHANSA", "STARBUCKS", "COCA", "PEPSI", "MCDONALD", "HILTON", "MARRIOTT", "ROLEX", "UBER", "APPLE", "GOOGLE", "AMAZON", "NIKE", "TESLA", "SAMSUNG", "FERRARI", "VISA", "DISNEY", "FERRIS" } do
		if string.find(joined, b, 1, true) then table.insert(brands, b) end
	end
	check("no real brand names on signs", #brands == 0, table.concat(brands, ","))
	local nonEnglish = {}
	for _, s in texts do
		local clean = string.gsub(string.gsub(string.gsub(string.gsub(string.gsub(s, "·", ""), "É", ""), "►", ""), "◄", ""), "–", "")
		if string.find(clean, "[^%w%s%p]") then table.insert(nonEnglish, s) end
	end
	check("sign text plain English (ASCII + · É ► ◄ –)", #nonEnglish == 0, table.concat(nonEnglish, " | "))
	local ads = find("Billboard", "BasePart")
	check("generic billboards (>= 6)", #ads >= 6, #ads)
	check("bus shelters x4, metro entrance, district gateway signs x7", #find("ShelterRoof") == 4 and #find("MetroEntrance", "Model") == 1 and #find("DistrictSign") == #Plan.DISTRICT_SIGNS and #Plan.DISTRICT_SIGNS == 7)
	-- district names readable: a horizontal panel >= 12 x 4.5 studs, both faces lettered (two lines of ~2-stud letters)
	local signOk = 0
	for _, p in find("DistrictSign", "BasePart") do
		local guis = 0
		for _, g in p:GetChildren() do if g:IsA("SurfaceGui") then guis += 1 end end
		if p.Size.X >= 12 and p.Size.Y >= 4.5 and guis == 2 then signOk += 1 end
	end
	check("district signs: 14 x 5 name panels lettered on both faces", signOk == 7, signOk)
	check("no meta units in sign text", not string.find(joined, "STUDS", 1, true))
	-- lounge seats face into the room (sofas towards the coffee table, LookVector away from their backrest)
	local badSeat = 0
	for _, d in lounge:GetDescendants() do
		if d:IsA("Seat") and d.Name == "Sofa" then
			local back
			for _, b in lounge:GetDescendants() do if b.Name == "SofaBack" and (b.Position - d.Position).Magnitude < 3 then back = b end end
			if not back or (back.Position - d.Position):Dot(d.CFrame.LookVector) > 0 then badSeat += 1 end
		end
	end
	check("lounge sofas seat players facing the coffee table (backrest behind)", badSeat == 0 and #find("Sofa", "Seat") == 3, badSeat)
	-- waterfront greenery and furniture
	check("harbour quarter: promenade trees in planters, beds with flowers, bollards, food carts, sculpture, splash fountains",
		#find("TreePlanter") >= #Plan.PROM_TREES and #find("BedFlowers") == #Plan.BEDS * 2 and #find("Bollard") == #Plan.BOLLARDS and #find("CartBody") == #Plan.CARTS
		and #find("SculptureSail") == 2 and #find("SplashBasin") == 2 and #find("PromenadeBand") >= 50,
		#find("TreePlanter") .. "/" .. #find("BedFlowers") .. "/" .. #find("Bollard") .. "/" .. #find("PromenadeBand"))
	check("green verges between the towers (lawn + trees)", #find("Verge") == #Plan.VERGES and #Plan.VERGES >= 30)
	local steps = find("SpireStep", "BasePart")
	check("steps up to the spire plinth door", #steps == 2 and steps[1].CanCollide)
	check("marina with yachts, harbour cruiser, lighthouse", #find("Hull") >= 10 and #find("CruiserHull") == 1 and #find("LighthouseTower") == 1, #find("Hull"))
	check("boulevard: 3 fountains, globe, 16 median flags, pavilions x8", #find("FountainRim") == 3 and #find("Globe") == 1 and #find("Pavilion" .. "Core") == 8)
	------------------------------------------------------------------ determinism
	local function hash(root)
		local h, n = 0, 0
		for _, d in root:GetDescendants() do if d:IsA("BasePart") then n += 1; h += d.Position.X * 0.37 + d.Position.Y * 1.3 + d.Position.Z * 0.011 + d.Size.Magnitude end end
		return h, n
	end
	local h1, n1 = hash(pm)
	local world2 = Builder.build("Port Meridian · $1.5k return")
	local h2, n2 = hash(world2:FindFirstChild("PortMeridian"))
	check("deterministic: a second build is identical", n1 == n2 and math.abs(h1 - h2) < 1e-3, n1 .. "/" .. n2)
end

local ok, err = M.runMain(body, { timeout = 300, maxSteps = 5000000 })
if not ok then print("ERROR " .. tostring(err)); failc += 1 end
print(string.format("metro_build: %d passed, %d failed", pass, failc))
