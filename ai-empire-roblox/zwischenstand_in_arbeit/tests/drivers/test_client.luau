--!nocheck
-- drivers package, client side: DriveController on the REAL published state of DriverService (client_setup.luau).
--   cars posed exactly from the published plan (every frame = DrivePlan.pose), all parts anchored / no collision /
--   no query / no touch / collision group, part budget, LOD (far camera = no car, own ride always), the driver at the
--   HQ entrance only while he is not out, occupants on the right seats (driver at the wheel, founder clone on the
--   rear right seat, companions), the HUD for every state ("Your driver is on the way · 0:21", "Your car is waiting",
--   "To City Airport (departures) · 0:48" + Let me out), Get in only near the car, the camera follows the car while
--   riding and returns to the character, the destination sheet from the phone hook (rows, ETAs, booking through
--   the remote, closing), the limousine waiting at the Port Meridian stand and leaving it free while a ride stands
--   there, touch sizes on an iPhone-sized screen.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_drivers && cd tests/drivers && ../../tools/luau test_client.luau -a .gen_drivers
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_drivers")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local G = M.G
local setup = require("./client_setup")
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local function body()
	local Vector3, CFrame, Enum = G.Vector3, G.CFrame, G.Enum
	local ctx = setup(M, { stage = 2, vw = 1280, vh = 720, insets = { top = 58, right = 0, bottom = 0, left = 0 } })
	local Drive, C, Driver = ctx.Drive, ctx.Controller, ctx.Driver
	local game = M.game
	local cars = game.Workspace:FindFirstChild("DriveCars")
	check("client folder workspace.DriveCars", cars ~= nil)
	ctx.tick(1.1) -- first scan: company folder + driver template
	local plot = ctx.plot
	local entrance = ctx.hq(Vector3.new(0, 3, -60))
	ctx.stand(entrance)
	ctx.camera(entrance + Vector3.new(0, 12, -30), entrance)
	ctx.frame()
	local function postCount()
		local n = 0
		for _ in C._posts() do n += 1 end
		return n
	end
	check("the idle driver waits at the HQ entrance", postCount() == 1)
	local post
	for _, p in C._posts() do post = p end
	local postAt = plot.cframe * Drive.HQ.post[1]
	check("driver post position and uniform", post and (post.root.Position - postAt.Position).Magnitude < 0.01 and post.model:FindFirstChild("DriverCap") ~= nil)
	-- far camera: no driver shown
	ctx.camera(entrance + Vector3.new(0, 400, -900), entrance)
	ctx.frame()
	check("far away: the waiting driver is not drawn (LOD)", postCount() == 0)
	ctx.camera(entrance + Vector3.new(0, 12, -30), entrance)

	------------------------------------------------------------------ request -> coming
	local res = ctx.call({ action = "ride", op = "request", to = "airport_departures" })
	check("booked through the remote", res.ok, res.err)
	ctx.frame()
	check("the driver leaves his post", postCount() == 0)
	local function carModels()
		local out = {}
		for _, m in cars:GetChildren() do if string.match(m.Name, "^DriveCar_") then table.insert(out, m) end end
		return out
	end
	-- while the driver walks to it the car stands parked at the depot in B1 (where the idle fleet car stood), empty
	local parked = carModels()[1]
	local depotCF = Drive.place("hq_garage", plot.index).stop
	check("while the driver walks to it: the car stands parked at the depot, empty, idle car gone",
		#carModels() == 1 and parked.Root.CFrame.Position:FuzzyEq(depotCF.Position, 1e-3) and parked:FindFirstChildWhichIsA("Model") == nil and next(C._depots()) == nil,
		#carModels())
	local hud = C._hud()
	check("HUD shows 'Your driver is on the way'", hud and string.find(hud.title.Text, "Your driver is on the way · ", 1, true) == 1, hud and hud.title.Text)
	check("HUD sub names the pick-up and the destination", hud and string.find(hud.sub.Text, "Pick-up: HQ entrance", 1, true) ~= nil and string.find(hud.sub.Text, "City Airport", 1, true) ~= nil, hud and hud.sub.Text)
	check("HUD: Cancel, no Get in yet", hud and hud.cancel.Visible and hud.cancel.Text == "Cancel" and not hud.board.Visible)
	local folder = game.ReplicatedStorage.CompanyDrivers:FindFirstChild("Drivers_4242")
	local rf = folder:FindFirstChild("Ride_1")
	local segs = Drive.decode(rf:GetAttribute("Plan"), plot.index)
	local legA = Drive.leg("hq_garage", "hq_entrance", plot.index)
	ctx.tick(Drive.walkAt(ctx.T.now) + legA.dur * 0.5)
	ctx.camera(plot.cframe:PointToWorldSpace(Vector3.new(130, 20, -120)), entrance)
	ctx.frame()
	local list = carModels()
	check("the car is on its way", #list == 1)
	local car = list[1]
	local want = Drive.pose(segs, plot.index, ctx.T.now, Drive.WHEELBASE.fleet)
	local rootPart = car and car:FindFirstChild("Root")
	check("car pivot = DrivePlan.pose of the published plan", rootPart and want and (rootPart.CFrame.Position - want.cf.Position).Magnitude < 1e-6 and rootPart.CFrame.LookVector:Dot(want.cf.LookVector) > 0.9999)
	local parts, bad = 0, {}
	for _, p in car:GetDescendants() do
		if p:IsA("BasePart") and not p:FindFirstAncestorOfClass("Model").Parent:IsA("Model") or (p:IsA("BasePart") and p.Parent == car) then
			if p.Parent == car then
				parts += 1
				if not p.Anchored or p.CanCollide or p.CanQuery or p.CanTouch then table.insert(bad, p.Name) end
			end
		end
	end
	check("car parts: anchored, no collision / query / touch", #bad == 0, table.concat(bad, ","))
	check("car part budget <= 60", parts > 20 and parts <= 60, parts)
	check("car in the company colour", car:FindFirstChild("Body") and car.Body.Color == folder:GetAttribute("Livery"))
	local driverSeat = nil
	for _, m in car:GetChildren() do if m:IsA("Model") then driverSeat = m end end
	check("the driver sits at the wheel", driverSeat and driverSeat:FindFirstChild("DriverCap") ~= nil
		and (driverSeat.HumanoidRootPart.Position - (rootPart.CFrame * select(2, C.seatLayout({ mesh = false, look = "fleet" }, "driver"))).Position).Magnitude < 1e-6
		and math.abs(driverSeat:GetScale() - (Drive.seatFit(C.glassHalf("fleet")))) < 1e-6)
	-- every part of the car follows the root exactly (offset placement)
	local body = car:FindFirstChild("Body")
	check("body placed relative to the pivot", body and math.abs(rootPart.CFrame:PointToObjectSpace(body.Position).X) < 1e-6)

	------------------------------------------------------------------ waiting
	ctx.tick(segs[1].t0 + legA.dur - ctx.T.now + 0.5)
	ctx.frame()
	hud = C._hud()
	check("HUD: waiting at the HQ entrance + walk to the car", hud and hud.title.Text == "Your car is at the HQ entrance" and string.find(hud.sub.Text, "Walk to the car", 1, true) == 1, hud and (hud.title.Text .. " | " .. hud.sub.Text))
	check("no Get in from far away", hud and not hud.board.Visible)
	local carCF = Drive.endCF(legA)
	ctx.stand((carCF * CFrame.new(6, 3, 2)).Position)
	ctx.frame()
	check("Get in appears beside the car", hud and hud.board.Visible and string.find(hud.sub.Text, "Get in", 1, true) == 1, hud and (tostring(hud.board.Visible) .. " " .. hud.sub.Text .. " " .. tostring(ctx.player.Character.HumanoidRootPart.Position) .. " car " .. tostring(carCF.Position)))
	-- press it (the button handler books through the remote)
	M.fire(hud.board.Activated)
	M.settle(0.2)
	check("boarded through the HUD button", rf:GetAttribute("State") == "riding")
	segs = Drive.decode(rf:GetAttribute("Plan"), plot.index)
	ctx.tick(Drive.BOARD_DELAY + 3)
	ctx.frame()
	car = carModels()[1]
	local founder = car and car:FindFirstChild("Founder")
	check("the founder (his own avatar) sits on the rear right seat", founder and (founder.HumanoidRootPart.Position - (car.Root.CFrame * Drive.seatCF("rearR", "fleet", C.glassHalf("fleet"))).Position).Magnitude < 1e-6)
	check("the founder clone has no talk prompt / scripts and hips bent", founder and founder:FindFirstChildWhichIsA("ProximityPrompt", true) == nil
		and founder.Torso:FindFirstChild("Left Hip") and founder.Torso["Left Hip"].Transform ~= CFrame.new())
	local cam = game.Workspace.CurrentCamera
	check("camera follows the car (orbit around the roof focus)", cam.CameraSubject == car:FindFirstChild("CameraFocus") and cam.CameraType == Enum.CameraType.Custom)
	hud = C._hud()
	local legB = Drive.leg("hq_entrance", "airport_departures", plot.index)
	local left = segs[2].t0 + legB.dur - ctx.T.now
	check("HUD: To City Airport · m:ss counting down", hud and hud.title.Text == Drive.hudText("City Airport", left), hud and hud.title.Text)
	check("HUD while riding: Let me out + View, no Get in", hud and hud.cancel.Text == "Let me out" and hud.view.Visible and not hud.board.Visible)
	check("HUD names the driver", hud and string.find(hud.sub.Text, "Driver: " .. folder:GetAttribute("DriverName1"), 1, true) == 1, hud and hud.sub.Text)
	M.fire(hud.view.Activated)
	ctx.frame()
	check("View switches to the back seat (scripted camera inside the car)", cam.CameraType == Enum.CameraType.Scriptable
		and (cam.CFrame.Position - (car.Root.CFrame * C.insideCF({ mesh = false, look = "fleet" })).Position).Magnitude < 1e-6
		and founder.Head.LocalTransparencyModifier == 1)
	M.fire(hud.view.Activated)
	ctx.frame()
	-- the own ride is drawn even with the camera far away
	ctx.camera(entrance + Vector3.new(3000, 800, 0), entrance)
	ctx.frame()
	check("own ride always drawn (no LOD)", #carModels() == 1)
	-- other company: far rides are not drawn
	ctx.camera(entrance + Vector3.new(0, 12, -30), entrance)
	-- arrive
	ctx.tick(segs[2].t0 + legB.dur - ctx.T.now + Driver.ALIGHT + 0.3)
	ctx.frame()
	check("after the drop-off: HUD gone, camera back on the character", C._hud() == nil and cam.CameraSubject == ctx.player.humanoid and cam.CameraType == Enum.CameraType.Custom)
	ctx.camera(Drive.place("airport_departures").door.Position + Vector3.new(0, 10, -30), Drive.place("airport_departures").door.Position)
	ctx.frame()
	car = carModels()[1]
	check("the car stands at the kerb without the founder", car and car:FindFirstChild("Founder") == nil)
	ctx.tick(Drive.planEnd(Drive.decode(rf:GetAttribute("Plan"), plot.index), plot.index) - ctx.T.now + 0.5)
	ctx.camera(entrance + Vector3.new(0, 12, -30), entrance)
	ctx.frame()
	-- (a car that stopped for good near the camera stays parked where it stopped - here in B1 - until the camera leaves)
	local lastSegs = Drive.decode(rf:GetAttribute("Plan") or "", plot.index)
	local parkPos = Drive.place("hq_garage", plot.index).drop.Position
	local leftCar = carModels()[1]
	check("back in the garage: the car is parked in B1 (or gone), driver at his post again", postCount() == 1
		and (leftCar == nil or (leftCar.Root.Position - parkPos).Magnitude < 1), #carModels() .. " cars, " .. postCount() .. " posts")
	local _ = lastSegs

	------------------------------------------------------------------ the destination sheet from the phone hook
	ctx.stand(entrance)
	ctx.T.now += 5
	local h = Driver.phoneHook(ctx.session, {})
	M.settle(0.2)
	local sheet = C._sheet()
	check("phone hook opens the destination sheet", sheet ~= nil and sheet.gui.Parent == ctx.playerGui and sheet.gui.DisplayOrder > 28)
	local rows = {}
	if sheet then for _, r in sheet.list:GetDescendants() do if r:IsA("TextButton") and string.match(r.Name, "^Place_") then rows[r.Name] = r end end end
	check("sheet rows: airport + Business City buildings", rows.Place_airport_departures ~= nil and rows.Place_clouddesk ~= nil)
	local etaLabel = rows.Place_airport_departures and rows.Place_airport_departures:FindFirstChild("Eta")
	check("rows show the ETA as a duration ('in m:ss')", etaLabel and string.match(etaLabel.Text, "^in %d+:%d%d$") ~= nil, etaLabel and etaLabel.Text)
	check("sheet status text = the phone's answer", sheet and sheet.text.Text == h.text)
	-- book CloudDesk from the sheet
	M.fire(rows.Place_clouddesk.Activated)
	M.settle(0.3)
	check("booking from the sheet closes it and starts the ride", C._sheet() == nil and folder:FindFirstChild("Ride_2") ~= nil and folder.Ride_2:GetAttribute("To") == "clouddesk")
	-- sheet while a ride is open: cancel button
	Driver.phoneHook(ctx.session, {})
	M.settle(0.2)
	sheet = C._sheet()
	check("sheet with an open ride offers Cancel ride", sheet and sheet.cancel.Visible and sheet.cancel.Text == "Cancel ride")
	M.fire(sheet.cancel.Activated)
	M.settle(0.3)
	check("Cancel ride from the sheet", C._sheet() == nil and (folder:FindFirstChild("Ride_2") == nil or folder.Ride_2:GetAttribute("State") == "returning"))
	ctx.tick(200)
	-- close with the X
	Driver.phoneHook(ctx.session, {})
	M.settle(0.2)
	local closeBtn = C._sheet() and C._sheet().gui:FindFirstChild("Close", true)
	if closeBtn then M.fire(closeBtn.Activated) end
	check("X closes the sheet", C._sheet() == nil)

	------------------------------------------------------------------ Port Meridian: the limousine at the stand
	local stand = Drive.place("pm_limo")
	ctx.camera(stand.stop.Position + Vector3.new(30, 15, -40), stand.stop.Position)
	ctx.frame()
	local limo, chauffeur = C._idle()
	check("the VIP limousine waits at bay 1 with its chauffeur", limo and limo.model.Parent == cars and (limo.root.Position - stand.stop.Position).Magnitude < 1e-6 and chauffeur ~= nil)
	check("limo is long (21 studs) and black", limo and limo.model:FindFirstChild("Body") and limo.model.Body.Size.Z > 19 and limo.model.Body.Color == G.Color3.fromRGB(14, 15, 18))
	ctx.City.trips[4242] = { player = ctx.player, state = "abroad", to = "abroad", releaseAt = math.huge }
	ctx.stand(stand.door.Position)
	ctx.T.now += 5
	local lr = ctx.call({ action = "ride", op = "request", to = "pm_hotel" })
	check("limo booked", lr.ok, lr.err)
	ctx.frame()
	local idle = C._idle()
	check("the idle limo makes room for the booked one", idle == nil)
	local booked = 0
	for _, m in cars:GetChildren() do if string.match(m.Name, "^DriveCar_") and m:GetAttribute("Look") == "limo" then booked += 1 end end
	check("the booked limousine waits at the stand", booked == 1)
	hud = C._hud()
	check("HUD abroad: waiting at the VIP limousine stand", hud and hud.title.Text == "Your limousine is at the stand", hud and hud.title.Text)
	-- companions (itinerary passengers) wait on the pavement at the pick-up's door point, never in a lane
	local okCancel = Driver.cancel(lr.rideId)
	ctx.tick(0.5)
	ctx.T.now += 5
	local cr = Driver.request(ctx.player, { to = "pm_hotel", purpose = "itinerary", passengers = { { name = "Mia Roth", role = "engineer", seed = 11 }, { name = "Leo Park", seed = 12 } } })
	check("limo with two passengers booked (the first one cancelled)", okCancel and cr.ok, cr.err)
	ctx.frame()
	local standers, standOk = 0, true
	for _, v in C._views() do
		local car = v.car
		if car and v.folder:GetAttribute("Id") == cr.rideId then
			local carPos = (car.at or car.root.CFrame).Position
			for seat, st in car.seats do
				if st.standing then
					standers += 1
					local pos = st.root.Position
					local toCar = Vector3.new(carPos.X - pos.X, 0, carPos.Z - pos.Z)
					local side = math.abs(stand.stop:PointToObjectSpace(pos).X)
					if (pos - stand.door.Position).Magnitude > 2.5 or side < Drive.CAR_WIDTH.limo / 2 + 1 or st.root.CFrame.LookVector:Dot(toCar.Unit) < 0.9 then
						standOk = false
						print("  " .. seat .. " at " .. tostring(pos) .. " side " .. side)
					end
				end
			end
		end
	end
	check("both companions stand on the pavement beside the door point, turned to the car", standers == 2 and standOk, standers)
	Driver.cancel(cr.rideId)
	ctx.City.trips[4242] = nil

	------------------------------------------------------------------ iPhone-sized screen: readable, touchable
	local ctx2 = nil
	local _ = ctx2
	local phone = ctx.GuiDump
	phone.setViewport(ctx.playerGui, 844, 390, { top = 58, right = 47, bottom = 21, left = 47 })
	M.settle(0.2)
	Driver.phoneHook(ctx.session, {})
	M.settle(0.2)
	sheet = C._sheet()
	local s = sheet and sheet.scale.Scale or 0
	check("sheet scale on 844x390 keeps text >= 12 px and rows >= 44 px", s * 19 >= 12 and s * 68 >= 44, s)
end
local ok, err = M.runMain(body, { timeout = 900, maxSteps = 8000000 })
if not ok then failc += 1; print("CRASH " .. tostring(err)) end
print(string.format("drivers_client: %d passed, %d failed", pass, failc))
