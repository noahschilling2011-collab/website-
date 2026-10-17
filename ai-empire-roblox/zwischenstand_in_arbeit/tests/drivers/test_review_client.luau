--!nocheck
-- drivers package, review round 1, client side: the reviewer's DriveController scenarios (agents/review_drivers/sb2/
-- tests/drivers/rv_client.luau V1-V4) + one check per client / visual issue of the review:
--   1 the limousine stays drawn during the door delay (camera on it), B the idle limousine is never drawn inside a
--     moving one (stand state from the server), 2 no founder clone after "let me out" in the door delay,
--   A seated occupants inside the car (arms within the glass / body, neighbours not overlapping),
--   C the ride HUD slides below a toast (never under it), D "Your car" marker over the waiting car (own ride only),
--   E 44 pt touch targets on an iPhone-sized screen (HUD buttons, sheet close / cancel / rows), F the back-seat view
--   hides the founder clone's head, H an idle fleet car parked in B1 (the ride car takes its exact place), a car that
--   stops for good near the camera stays parked until the camera leaves, NPC passengers standing at the door while
--   the car waits between legs (not seated, not vanishing), far rides are not decoded, no driver at the canopy at
--   night, liveCars() for the city traffic, and the ExecutiveLimo mesh path (a stand-in model with the manifest's
--   part names) incl. its wheelbase - the part-built limousine when the model is absent.
-- Run: cd tests/drivers && ../../tools/luau test_review_client.luau -a .gen_drivers
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
local function info(s) print("INFO  " .. s) end

local DEBUG_A = false
local function body()
	local Vector3, CFrame, Instance = G.Vector3, G.CFrame, G.Instance
	local ctx = setup(M, { stage = 4, vw = 1280, vh = 720, insets = { top = 58, right = 0, bottom = 0, left = 0 } })
	local Drive, C, Driver = ctx.Drive, ctx.Controller, ctx.Driver
	local Ops = M.require(M.game.ReplicatedStorage.Shared.CompanyOps)
	local game = M.game
	local cars = game.Workspace:FindFirstChild("DriveCars")
	local root = game.ReplicatedStorage.CompanyDrivers
	ctx.tick(1.1)
	local stand = Drive.place("pm_limo")
	local function limos()
		local out = {}
		for _, m in cars:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("Look") == "limo" then
				local r = m:FindFirstChild("Root")
				table.insert(out, { name = m.Name, pos = r and r.Position })
			end
		end
		return out
	end
	local function minGap(list)
		local best = math.huge
		for i = 1, #list do for j = i + 1, #list do
			if list[i].pos and list[j].pos then best = math.min(best, (list[i].pos - list[j].pos).Magnitude) end
		end end
		return best
	end
	local function count(name)
		local n = 0
		for _, d in cars:GetDescendants() do if d:IsA("Model") and d.Name == name then n += 1 end end
		return n
	end
	local cam = game.Workspace.CurrentCamera
	ctx.camera(stand.stop.Position + Vector3.new(30, 15, -40), stand.stop.Position)
	ctx.City.trips[4242] = { player = ctx.player, state = "abroad", to = "abroad", releaseAt = math.huge }

	------------------------------------------------------------------ V1 board at the stand: the 2 s door delay
	ctx.stand(stand.door.Position)
	ctx.T.now += 5
	local lr = ctx.call({ action = "ride", op = "request", to = "pm_hotel" })
	check("V1 limo booked at the stand", lr.ok, lr.err)
	ctx.frame()
	check("V1 one limo at the stand while waiting (the booked one, no idle one inside it)", #limos() == 1, #limos())
	ctx.stand(stand.stop * Vector3.new(5, 3, 4))
	local bo = ctx.call({ action = "ride", op = "board" })
	check("V1 board", bo.ok, bo.err)
	ctx.tick(0.5)
	ctx.frame()
	local mine
	for _, v in C._views() do if v.folder:GetAttribute("Id") == lr.rideId then mine = v end end
	check("V1 the booked limo (with me inside) stays drawn during the door delay", mine and mine.car ~= nil and #limos() == 1)
	check("V1 ... with me on the back seat and the camera on the car", count("Founder") == 1 and cam.CameraSubject ~= nil and cam.CameraSubject.Name == "CameraFocus",
		cam.CameraSubject and cam.CameraSubject.Name)
	ctx.tick(1.6)
	ctx.frame()
	local pull = limos()
	check("V1 pulling away: no second limo drawn inside the departing one", #pull < 2 or minGap(pull) > Drive.CAR_LENGTH.limo, string.format("%d / %.2f", #pull, minGap(pull)))
	ctx.tick(1.0)
	ctx.frame()
	check("V1 one chauffeur visible at a time (same person)", count("Chauffeur") <= 1, count("Chauffeur"))

	------------------------------------------------------------------ V2 the next limousine moves up to the stand
	local segs = Drive.decode(mine.folder:GetAttribute("Plan"))
	local worst = math.huge
	local idleBack = false
	for k = 1, 160 do
		ctx.tick(0.5)
		ctx.frame()
		local l = limos()
		if #l >= 2 then worst = math.min(worst, minGap(l)) end
		local idle = C._idle()
		if idle then idleBack = true end
	end
	check("V2 the moved-up limousine and the idle one are never drawn on top of each other", worst > Drive.CAR_LENGTH.limo, string.format("%.2f", worst))
	check("V2 the stand gets its idle limousine back", idleBack and root.Limo:GetAttribute("Stand") == "idle")
	local _ = segs

	------------------------------------------------------------------ V3 'let me out' during the door delay: no founder clone rides away
	ctx.tick(300)
	ctx.stand(stand.door.Position)
	ctx.T.now += 5
	ctx.call({ action = "ride", op = "request", to = "pm_hotel" })
	ctx.stand(stand.stop * Vector3.new(5, 3, 4))
	ctx.call({ action = "ride", op = "board" })
	ctx.tick(0.5)
	local cc = ctx.call({ action = "ride", op = "cancel" })
	check("V3 cancel in the door delay ok", cc.ok, cc.err)
	ctx.tick(2.0)
	ctx.frame()
	check("V3 no founder clone in any car while the founder stands at the kerb; the idle limousine is back", count("Founder") == 0 and not ctx.player.root.Anchored and C._idle() ~= nil, count("Founder"))
	ctx.City.trips[4242] = nil
	ctx.tick(300)

	------------------------------------------------------------------ V4 two drivers at the entrance (stage 4)
	local dayStart0 = ctx.T.now - (ctx.T.now % Ops.DAY)
	ctx.T.now = dayStart0 + Ops.DAY + 45 -- 08:30 next morning
	ctx.tick(1.1)
	local entrance = ctx.hq(Vector3.new(0, 3, -60))
	ctx.stand(entrance)
	ctx.camera(entrance + Vector3.new(0, 12, -30), entrance)
	ctx.frame()
	local nPosts = 0
	for _ in C._posts() do nPosts += 1 end
	check("V4 stage 4: two drivers waiting at the entrance (day)", nPosts == 2 and Drive.onPost(ctx.T.now), nPosts)

	------------------------------------------------------------------ H idle fleet car in B1, the ride car takes its exact place
	local plot = ctx.plot
	local depot = Drive.place("hq_garage", plot.index)
	ctx.camera(depot.stop.Position + Vector3.new(-12, 6, -25), depot.stop.Position)
	ctx.frame()
	local idleCar = nil
	for _, car in C._depots() do idleCar = car end
	check("H an idle fleet car stands at the depot in B1 (company colour)", idleCar ~= nil and (idleCar.root.Position - depot.stop.Position).Magnitude < 1e-3
		and idleCar.model.Body.Color == root.Drivers_4242:GetAttribute("Livery"))
	local function litLights(model)
		local n = 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and (d.Name == "Headlight" or d.Name == "TailLight") and d.Material == G.Enum.Material.Neon then n += 1 end
		end
		return n
	end
	check("H the parked idle car has its lights off", idleCar ~= nil and litLights(idleCar.model) == 0, idleCar and litLights(idleCar.model))
	ctx.stand(entrance)
	ctx.T.now += 5
	local r1 = ctx.call({ action = "ride", op = "request", to = "clouddesk", passengers = nil })
	check("H booked", r1.ok, r1.err)
	ctx.frame()
	local rideCar = nil
	for _, v in C._views() do if v.folder:GetAttribute("Id") == r1.rideId then rideCar = v.car end end
	check("H the booked car is the one at the depot (same pose), the idle one is gone", rideCar and next(C._depots()) == nil and (rideCar.root.Position - depot.stop.Position).Magnitude < 1e-3)
	check("H ... and the ride car drives with its lights on", rideCar ~= nil and litLights(rideCar.model) == 4, rideCar and litLights(rideCar.model))

	------------------------------------------------------------------ A occupants inside the car + D marker + F back-seat view
	local legA = Drive.leg("hq_garage", "hq_entrance", plot.index)
	ctx.tick(Drive.walkAt(ctx.T.now) + legA.dur + 1)
	ctx.camera(entrance + Vector3.new(0, 12, -30), entrance)
	ctx.frame()
	local markerOk = C._marker() ~= nil and C._marker().AlwaysOnTop == true and C._marker().Label.Text == "Your car"
	check("D 'Your car' marker (always on top) over the waiting car; HUD says it is marked", markerOk and string.find(C._hud().sub.Text, "marked", 1, true) ~= nil)
	-- a full car: driver, founder and two colleagues (book again with passengers through the server API)
	ctx.call({ action = "ride", op = "cancel" })
	ctx.tick(120)
	ctx.T.now += 5
	local r2 = Driver.request(ctx.player, { to = "clouddesk", passengers = { { name = "Mia Chen", role = "marketer", seed = 1 }, { name = "Leo Park", role = "engineer", seed = 2 } } })
	check("A booked with two colleagues", r2.ok, r2.err)
	ctx.tick(Drive.walkAt(ctx.T.now) + legA.dur + 1)
	ctx.frame()
	local standing = 0
	for _, v in C._views() do if v.car then for _, s in v.car.seats do if s.standing then standing += 1 end end end end
	check("A the colleagues wait at the pick-up's door while the car waits", standing == 2, standing)
	ctx.stand((Drive.endCF(legA) * CFrame.new(6, 3, 2)).Position)
	ctx.call({ action = "ride", op = "board" })
	ctx.tick(Drive.BOARD_DELAY + 5)
	ctx.frame()
	local view
	for _, v in C._views() do if v.folder:GetAttribute("Id") == r2.rideId then view = v end end
	local car = view and view.car
	check("A full car: four occupants seated", car and car.seats.driver and car.seats.rearR and car.seats.rearL and car.seats.front)
	ctx.solveRigs(car.model)
	local shape = C.SHAPES.fleet
	local gh = C.glassHalf("fleet")
	local carCF = car.root.CFrame
	local worstOut, worstHead = -math.huge, -math.huge
	local spans = {}
	for seat, s in car.seats do
		local lo, hi = math.huge, -math.huge
		for _, p in s.model:GetDescendants() do
			if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" and p.Transparency < 1 then
				local hs = p.Size / 2
				for _, sx in { -1, 1 } do for _, sy in { -1, 1 } do for _, sz in { -1, 1 } do
					local w = carCF:PointToObjectSpace((p.CFrame * CFrame.new(hs.X * sx, hs.Y * sy, hs.Z * sz)).Position)
					local limit = if w.Y > 2.55 then gh else shape.w / 2
					if math.abs(w.X) - limit > 0.0 and DEBUG_A then info("out " .. seat .. " " .. p.Name .. string.format(" x %.2f y %.2f z %.2f", w.X, w.Y, w.Z)) end
					worstOut = math.max(worstOut, math.abs(w.X) - limit)
					worstHead = math.max(worstHead, w.Y - (shape.h - 0.32))
					if w.Y > 2.0 and w.Y < 4.2 then lo = math.min(lo, w.X); hi = math.max(hi, w.X) end
				end end end
			end
		end
		spans[seat] = { lo, hi }
	end
	local overlapFront = spans.driver[2] - spans.front[1]
	local overlapRear = spans.rearL[2] - spans.rearR[1]
	info(string.format("A worst outside glass/body %.2f, head vs roof %.2f, neighbour overlap front %.2f rear %.2f", worstOut, worstHead, overlapFront, overlapRear))
	check("A no occupant part outside the glass (above the belt line) or the body", worstOut <= 0.0, string.format("%.2f", worstOut))
	check("A heads (with caps) under the roof", worstHead <= 0.02, string.format("%.2f", worstHead))
	check("A side-by-side occupants do not overlap (<= 0.3 studs at the elbows)", overlapFront <= 0.3 and overlapRear <= 0.3, string.format("%.2f / %.2f", overlapFront, overlapRear))
	-- F: the back-seat view hides my clone's head (and accessories), orbit shows it again
	local hud = C._hud()
	M.fire(hud.view.Activated)
	ctx.frame()
	local head = car.seats.rearR.model:FindFirstChild("Head")
	check("F 'View' on the back seat: my clone's head hidden locally", head and head.LocalTransparencyModifier == 1 and cam.CameraType == G.Enum.CameraType.Scriptable)
	local camLocal = carCF:PointToObjectSpace(cam.CFrame.Position)
	check("F the back-seat camera sits between the two rear heads (x = 0)", math.abs(camLocal.X) < 0.01)
	M.fire(hud.view.Activated)
	ctx.frame()
	check("F orbit view: the head is shown again", head and head.LocalTransparencyModifier == 0)
	-- companions get out with him at the drop-off and stand at the door while the car waits
	local rsegs = Drive.decode(view.folder:GetAttribute("Plan"), plot.index)
	ctx.tick(rsegs[2].t0 + Drive.segLeg(rsegs[2], plot.index).dur - ctx.T.now + Driver.ALIGHT + 0.4)
	ctx.camera(Drive.place("clouddesk").door.Position + Vector3.new(0, 10, 30), Drive.place("clouddesk").door.Position)
	ctx.frame()
	local atDoor, seatedC, facingDoor = 0, 0, 0
	local doorCF = Drive.place("clouddesk").door
	if view.car then
		for _, s in view.car.seats do
			if s.standing and (s.root.Position - doorCF.Position).Magnitude < 4 then atDoor += 1 end
			if s.standing and s.root.CFrame.LookVector:Dot(doorCF.LookVector) > 0.99 then facingDoor += 1 end
			if not s.standing and (s.code == "C1" or s.code == "C2") then seatedC += 1 end
		end
	end
	check("A at the drop-off the colleagues stand at the door (not seated, not vanished) while the car waits", atDoor == 2 and seatedC == 0, atDoor .. "/" .. seatedC)
	check("A ... facing the door they walk to (not the car they just left)", facingDoor == 2, facingDoor)
	check("A ... and no founder clone stays in the car", count("Founder") == 0)

	------------------------------------------------------------------ H a car that stopped for good near the camera stays parked
	local back = Drive.planEnd(Drive.decode(view.folder:GetAttribute("Plan"), plot.index), plot.index)
	ctx.camera(depot.stop.Position + Vector3.new(-12, 6, -25), depot.stop.Position)
	ctx.tick(back - ctx.T.now - 0.5)
	ctx.frame()
	ctx.tick(1.5)
	ctx.frame()
	check("H the car back in the garage stays parked while the camera is near (no pop), no idle car on top of it", #C._ghosts() == 1 and next(C._depots()) == nil, #C._ghosts())
	ctx.camera(depot.stop.Position + Vector3.new(0, 300, -400), depot.stop.Position)
	ctx.frame()
	ctx.camera(depot.stop.Position + Vector3.new(-12, 6, -25), depot.stop.Position)
	ctx.frame()
	check("H camera away and back: the parked car is the idle fleet car at the depot again", #C._ghosts() == 0 and next(C._depots()) ~= nil)

	------------------------------------------------------------------ C the HUD slides below a toast
	check("C hudTop: no toast = 10, a toast 60 px tall at scale 0.65 -> below it", C.hudTop(nil, 0.65) == 10 and math.abs(C.hudTop(60, 0.65) - 68 / 0.65) < 1e-6)
	ctx.stand(entrance)
	ctx.T.now += 5
	ctx.call({ action = "ride", op = "request", to = "airport_departures" })
	ctx.frame()
	local h = C._hud()
	local top = ctx.playerGui:FindFirstChild("AIEmpire_Top")
	local holder = top and top:FindFirstChild("Toasts", true)
	check("C toast holder found", holder ~= nil)
	if holder then
		local K = M.KEY
		holder[K].props.AbsolutePosition = G.Vector2.new(420, 74)
		holder[K].props.AbsoluteSize = G.Vector2.new(440, 52)
		-- the HUD's ScreenGui reports a different origin than its GuiObjects (safe-area insets, as guiprev does):
		-- the toast must be measured against the HUD's root frame, not the ScreenGui
		h.gui[K].props.AbsolutePosition = G.Vector2.new(0, 58)
		ctx.frame()
		local panelTopPx = h.root.AbsolutePosition.Y + h.panel.Position.Y.Offset * h.scale.Scale
		check("C with a toast showing the panel's top edge is below the toast's bottom", panelTopPx >= 74 + 52, string.format("%.1f", panelTopPx))
		holder[K].props.AbsoluteSize = G.Vector2.new(440, 0)
		ctx.frame()
		check("C toast gone: the panel goes back up", h.panel.Position.Y.Offset == 10)
	end
	ctx.call({ action = "ride", op = "cancel" })

	------------------------------------------------------------------ far rides are not decoded; liveCars
	local farFolder = Instance.new("Folder")
	farFolder.Name = "Ride_999"
	farFolder:SetAttribute("Kind", "limo"); farFolder:SetAttribute("Look", "limo"); farFolder:SetAttribute("Zone", "abroad"); farFolder:SetAttribute("Plot", 0)
	farFolder:SetAttribute("State", "driving"); farFolder:SetAttribute("Rider", 0)
	farFolder:SetAttribute("Plan", "pm_depot>pm_hotel|D@" .. string.format("%.2f", ctx.T.now))
	farFolder.Parent = root.Limo
	ctx.camera(entrance + Vector3.new(0, 12, -30), entrance)
	ctx.frame()
	local fv = C._views()[farFolder]
	check("a ride in Port Meridian is not decoded while the camera is at home (no routing, no car)", fv and fv.segs == nil and fv.car == nil)
	farFolder:Destroy()
	ctx.T.now += 5
	ctx.call({ action = "ride", op = "request", to = "airport_departures" })
	ctx.tick(Drive.walkAt(ctx.T.now) + legA.dur * 0.6)
	ctx.camera(entrance + Vector3.new(0, 12, -30), entrance)
	ctx.frame()
	local lc = C.liveCars()
	check("liveCars(): the drawn cars with pose, length, width, speed", #lc >= 1 and lc[1].length == Drive.CAR_LENGTH.fleet and lc[1].width == Drive.CAR_WIDTH.fleet and lc[1].speed >= 0)
	ctx.call({ action = "ride", op = "cancel" })
	ctx.tick(200)

	------------------------------------------------------------------ night: no driver at the canopy (on call), the idle car stays
	local dayStart = ctx.T.now - (ctx.T.now % Ops.DAY)
	ctx.T.now = dayStart + Ops.DAY + 900 + (5 / 14) * 300
	ctx.tick(1.1)
	ctx.camera(entrance + Vector3.new(0, 12, -30), entrance)
	ctx.frame()
	local nightPosts = 0
	for _ in C._posts() do nightPosts += 1 end
	check("night (23:00): no driver under the canopy", nightPosts == 0 and not Drive.onPost(ctx.T.now), nightPosts)
	ctx.T.now = dayStart + 2 * Ops.DAY + 10
	ctx.tick(1.1)
	ctx.frame()
	nightPosts = 0
	for _ in C._posts() do nightPosts += 1 end
	check("morning: the drivers are back at the canopy", nightPosts == 2, nightPosts)

	------------------------------------------------------------------ E 44 pt touch targets on an iPhone-sized screen
	do
		ctx.GuiDump.setViewport(ctx.playerGui, 844, 390, { top = 58, right = 47, bottom = 21, left = 47 })
		cam[M.KEY].props.ViewportSize = G.Vector2.new(844, 390)
		C.closeSheet()
		ctx.stand(entrance)
		ctx.T.now += 5
		ctx.call({ action = "ride", op = "request", to = "airport_departures" })
		ctx.tick(Drive.walkAt(ctx.T.now) + legA.dur + 1)
		ctx.stand((Drive.endCF(legA) * CFrame.new(6, 3, 2)).Position)
		ctx.frame()
		ctx.GuiDump.setViewport(ctx.playerGui, 844, 390, { top = 58, right = 47, bottom = 21, left = 47 })
		ctx.frame()
		local hh = C._hud()
		local sc = hh.scale.Scale
		local minBtn = math.huge
		for _, b in { hh.board, hh.cancel } do if b.Visible then minBtn = math.min(minBtn, b.Size.Y.Offset * sc, b.Size.X.Offset * sc) end end
		check("E HUD buttons >= 44 pt on the phone (scale " .. string.format("%.2f", sc) .. ")", hh.compact and minBtn >= 44 - 1e-6, string.format("%.1f", minBtn))
		Driver.phoneHook(ctx.session, {})
		local sh = C._sheet()
		local close = sh and sh.gui:FindFirstChild("Close", true)
		local cancel = sh and sh.gui:FindFirstChild("CancelRide", true)
		local ssc = sh and sh.scale.Scale or 1
		check("E sheet close + cancel >= 44 pt on the phone", close and cancel and close.Size.Y.Offset * ssc >= 44 - 1e-6 and cancel.Size.Y.Offset * ssc >= 44 - 1e-6,
			close and string.format("%.1f / %.1f", close.Size.Y.Offset * ssc, cancel.Size.Y.Offset * ssc))
		C.closeSheet()
		ctx.call({ action = "ride", op = "cancel" })
		ctx.tick(200)
		ctx.GuiDump.setViewport(ctx.playerGui, 1280, 720, { top = 58, right = 0, bottom = 0, left = 0 })
		cam[M.KEY].props.ViewportSize = G.Vector2.new(1280, 720)
	end

	------------------------------------------------------------------ the ExecutiveLimo mesh path (stand-in with the manifest's part names)
	do
		local function stub()
			local m = Instance.new("Model")
			m.Name = "ExecutiveLimo"
			local base = Instance.new("Part"); base.Name = "Body"; base.Size = Vector3.new(7, 3, 27); base.CFrame = CFrame.new(0, 2, 0); base.Parent = m
			for _, w in { { "Wheel_FL", -2.96, -9.53 }, { "Wheel_FR", 2.96, -9.53 }, { "Wheel_RL", -2.96, 9.53 }, { "Wheel_RR", 2.96, 9.53 } } do
				local p = Instance.new("Part"); p.Name = w[1]; p.Size = Vector3.new(1, 2.5, 2.5); p.CFrame = CFrame.new(w[2], 1.255, w[3]); p.Parent = m
			end
			for _, d in { { "Door_RearL", -3.5, 5.46 }, { "Door_RearR", 3.5, 5.46 }, { "Door_Driver", -3.5, -7.14 } } do
				local p = Instance.new("Part"); p.Name = d[1]; p.Size = Vector3.new(0.2, 3, 4); p.CFrame = CFrame.new(d[2], 2.2, d[3]); p.Parent = m
			end
			for _, d in { { "Interior_Lounge", 0, 4 }, { "StarLights", 0, 5 } } do
				local p = Instance.new("Part"); p.Name = d[1]; p.Size = Vector3.new(4, 1, 6); p.CFrame = CFrame.new(d[2], 2.5, d[3]); p.Parent = m
			end
			m.PrimaryPart = base
			m.WorldPivot = CFrame.new()
			return m
		end
		local assets = Instance.new("Folder"); assets.Name = "Assets"
		local vehicles = Instance.new("Folder"); vehicles.Name = "Vehicles"; vehicles.Parent = assets
		local tpl = stub(); tpl.Parent = vehicles
		assets.Parent = game.ReplicatedStorage
		C._resetMesh()
		check("mesh: the imported ExecutiveLimo is found and used (wheelbase 18.10)", C.findMesh() == tpl and C.wheelbaseOf("limo") == 18.10)
		local mcar = C.buildCar("limo", G.Color3.new(0, 0, 0), "VIP")
		check("mesh: car model from the template (ScaleTo 0.95), parts anchored / no collision, wheels + doors found", mcar.mesh and mcar.model:GetAttribute("Mesh") == true
			and #mcar.wheels == 4 and #mcar.doors == 3 and mcar.model.Body.Anchored and not mcar.model.Body.CanCollide and math.abs(mcar.model:GetScale() - 0.95) < 1e-6)
		mcar.door = 1
		C.placeCar(mcar, CFrame.new(100, 25, 100))
		C.placeCar(mcar, CFrame.new(100, 25, 90))
		local rr = mcar.model.Door_RearR
		local rl = mcar.model.Door_RearL
		check("mesh: the kerb-side rear door swings open (the other rear door stays shut)", rr and rl and math.abs(rr.CFrame.LookVector:Dot(G.Vector3.new(0, 0, -1))) < 0.9
			and math.abs(rl.CFrame.LookVector:Dot(G.Vector3.new(0, 0, -1))) > 0.999)
		C.meshLod(mcar, 400)
		local hidden = mcar.model.Interior_Lounge.LocalTransparencyModifier == 1 and mcar.model.StarLights.LocalTransparencyModifier == 1 and mcar.model.Body.LocalTransparencyModifier == 0
		C.meshLod(mcar, 40)
		check("mesh: triangle budget - the interior is hidden beyond MESH.far, shown again close up, the body always drawn", hidden
			and mcar.model.Interior_Lounge.LocalTransparencyModifier == 0 and #mcar.interior == 2)
		local sc, seatCF = C.seatLayout(mcar, "rearR")
		check("mesh: rear right seat from the manifest, rigs scaled so the arms stay inside the cabin", math.abs(seatCF.Position.X - 1.3571) < 1e-4 and math.abs(seatCF.Position.Z - 8.7977) < 1e-4
			and sc <= 0.68 and seatCF.Position.Y + 2.32 * sc <= 4.787)
		mcar.model:Destroy()
		assets:Destroy()
		C._resetMesh()
		local pcar = C.buildCar("limo", G.Color3.new(0, 0, 0), "VIP")
		check("mesh removed: the part-built limousine exactly as before (wheelbase 13)", not pcar.mesh and pcar.model:FindFirstChild("ChromeLine") ~= nil and C.wheelbaseOf("limo") == Drive.WHEELBASE.limo)
		pcar.model:Destroy()
	end
end
local ok, err = M.runMain(body, { timeout = 900, maxSteps = 12000000 })
if not ok then failc += 1; print("CRASH " .. tostring(err)) end
print(string.format("drivers_review_client: %d passed, %d failed", pass, failc))
