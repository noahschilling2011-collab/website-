-- DoorService state machine test (headless mock). Fake door models follow SPEC §3; characters are
-- plain Models with a HumanoidRootPart, players are tables fed through Doors._setPlayerSource.
local G = M.G
local Vector3, CFrame, Instance, Color3 = G.Vector3, G.CFrame, G.Instance, G.Color3
local game, workspace = M.game, M.workspace
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Palette = M.require(game.ReplicatedStorage.Shared.Config.ArchPalette)
local Doors = M.require(game.ServerScriptService.Server.Services.DoorService)

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then
		pass += 1
	else
		fail += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else ""))
	end
end
local function near(a, b, eps)
	return (a - b).Magnitude <= (eps or 1e-3)
end
local function cfnear(a, b)
	return near(a.Position, b.Position) and near(a.LookVector, b.LookVector) and near(a.UpVector, b.UpVector)
end
local function colorEq(a, b)
	return math.abs(a.R - b.R) < 1e-6 and math.abs(a.G - b.G) < 1e-6 and math.abs(a.B - b.B) < 1e-6
end

-- World ------------------------------------------------------------------------------------------
local OWNER = 1
local function makeOffice(owner, cf)
	local office = Instance.new("Model")
	office.Name = "Office"
	office:SetAttribute("OwnerUserId", owner)
	office:SetAttribute("OfficeTier", 1)
	office:SetAttribute("CampusCFrame", cf)
	local doors = Instance.new("Folder")
	doors.Name = "Doors"
	doors.Parent = office
	local staff = Instance.new("Folder")
	staff.Name = "Employees"
	staff.Parent = office
	office.Parent = workspace
	return office
end
local office = makeOffice(OWNER, CFrame.new())
local NEUTRAL = Color3.fromRGB(40, 44, 48)

-- A door in the x/y plane at `centre`; protected side = +Z unless normal is given.
local function makeDoor(id, kind, access, centre, opts)
	opts = opts or {}
	local m = Instance.new("Model")
	m.Name = "Door_" .. id
	m:SetAttribute("DoorId", id)
	m:SetAttribute("DoorKind", kind)
	m:SetAttribute("AccessClass", access)
	if opts.normal ~= false then
		m:SetAttribute("SecureNormal", opts.normal or Vector3.new(0, 0, 1))
	end
	if opts.auto ~= nil then m:SetAttribute("AutoOpen", opts.auto) end
	if opts.hold then m:SetAttribute("HoldOpen", opts.hold) end
	if opts.fixture then m:SetAttribute("FixtureKey", opts.fixture) end
	CollectionService:AddTag(m, "CampusDoor")
	local frame = Instance.new("Model")
	frame.Name = "Frame"
	frame.Parent = m
	local jamb = Instance.new("Part")
	jamb.Name = "Jamb"
	jamb.Size = Vector3.new(0.4, 9, 0.6)
	jamb.CFrame = CFrame.new(centre + Vector3.new(-2.2, 0, 0))
	jamb.Anchored = true
	jamb.Parent = frame
	local leaf = Instance.new("Model")
	leaf.Name = "Leaf1"
	local slab = Instance.new("Part")
	slab.Name = "Slab"
	slab.Size = Vector3.new(4, 9, 0.3)
	slab.CFrame = CFrame.new(centre)
	slab.Anchored = true
	slab.CanCollide = true
	slab.Parent = leaf
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.6)
	handle.CFrame = CFrame.new(centre + Vector3.new(1.6, 0, 0))
	handle.Anchored = true
	handle.CanCollide = false
	handle.Parent = leaf
	local hinge = CFrame.new(centre + Vector3.new(-2, 0, 0))
	leaf.WorldPivot = hinge
	leaf:SetAttribute("ClosedPivot", hinge)
	leaf:SetAttribute("OpenPivot", hinge * CFrame.Angles(0, math.rad(-95), 0))
	leaf.Parent = m
	local sensor = Instance.new("Part")
	sensor.Name = "Sensor"
	sensor.Size = Vector3.new(5, 10, 8)
	sensor.CFrame = CFrame.new(centre)
	sensor.Transparency = 1
	sensor.CanCollide = false
	sensor.Anchored = true
	sensor.Parent = m
	local reader = Instance.new("Part")
	reader.Name = "PromptOut"
	reader.CFrame = CFrame.new(centre + Vector3.new(2.8, 0, -0.4))
	reader.Anchored = true
	reader.Parent = m
	local light = Instance.new("Part")
	light.Name = "ReaderLight"
	light.Color = NEUTRAL
	light.Anchored = true
	light.Parent = reader
	m.Parent = opts.parent or office.Doors
	return m, slab, light, leaf
end

local function makeChar(name, pos)
	local c = Instance.new("Model")
	c.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(pos)
	root.Anchored = true
	root.Parent = c
	local h = Instance.new("Humanoid")
	h.Parent = c
	c.PrimaryPart = root
	c.Parent = workspace
	return c, root, h
end
local function moveTo(root, pos)
	root.CFrame = CFrame.new(pos)
end

local players = {}
local function makePlayer(userId, name, pos)
	local c, root, h = makeChar(name, pos)
	local p = { UserId = userId, Name = name, Character = c }
	table.insert(players, p)
	return p, root, h
end
Doors._setPlayerSource(function()
	return players
end)
local authCalls = 0
Doors.setAuthorizer(function(player, _office, door)
	authCalls += 1
	if player.UserId == OWNER then
		return true
	end
	local class = door:GetAttribute("AccessClass")
	if class == "public" then
		return true
	end
	if player.cardHolder and class == "staff" then
		return true
	end
	return false, "Denied:" .. tostring(class)
end)
local notices = {}
Doors.setNotifier(function(player, text)
	table.insert(notices, { player = player, text = text })
end)

local heartbeat = RunService.Heartbeat
local function run(seconds, dt)
	dt = dt or 0.05
	local t = 0
	while t < seconds - 1e-9 do
		M.fire(heartbeat, dt)
		Doors.tick(dt)
		t += dt
	end
end
local function runUntil(pred, maxSeconds)
	local t = 0
	while not pred() and t < maxSeconds do
		run(0.05)
		t += 0.05
	end
	return t
end

-- Doors ------------------------------------------------------------------------------------------
local P1 = Vector3.new(0, 4.5, 0)
local door1, slab1, light1, leaf1 = makeDoor("L1_A_D1", "solid", "founder", P1)
local P2 = Vector3.new(40, 4.5, 0)
local door2, slab2 = makeDoor("L1_B_D1", "secure", "research", P2)
local P3 = Vector3.new(80, 4.5, 0)
local cub, cubSlab = makeDoor("WC_C1", "cubicle", "staff", P3, { fixture = "T1" })
local P4 = Vector3.new(120, 4.5, 0)
local auto, autoSlab = makeDoor("G_GATE", "autoslide", "staff", P4, { auto = true })
local P5 = Vector3.new(160, 4.5, 0)
local book = makeDoor("P1_ARCHIVE_D2", "bookcase", "founder", P5)
local P6 = Vector3.new(200, 4.5, 0)
local gate = makeDoor("G_ATRIUM_D2", "speedgate", "staff", P6, { auto = true })
-- No SecureNormal: the id exists in the tier-1 plan, so the plan's inward normal is used.
local showroomDef
for _, d in M.require(game.ReplicatedStorage.Shared.BuildingLayout).doors(1) do
	if d.id == "G_SHOWROOM_D1" then showroomDef = d end
end
local P7 = Vector3.new(showroomDef.x, 4.5, showroomDef.z)
local plannedDoor = makeDoor("G_SHOWROOM_D1", "glassdouble", "staff", P7, { normal = false })

-- toilet seat for the cubicle
local seat = Instance.new("Seat")
seat.Name = "ToiletSeat"
seat:SetAttribute("FixtureKey", "T1")
seat.CFrame = CFrame.new(P3 + Vector3.new(0, -3, 4))
seat.Anchored = true
seat.Parent = office

Doors.init()
Doors.register(office)

-- 1. registry ------------------------------------------------------------------------------------
local list = Doors.inspect(office)
check("inspect lists all doors", #list == 7, #list)
check("initial state closed", Doors.state(door1) == "closed" and door1:GetAttribute("DoorState") == "closed")
check("find by id", Doors.find(office, "L1_A_D1") == door1)
check("find unknown id", Doors.find(office, "NOPE") == nil)
check("doorsNear sorted", Doors.doorsNear(office, P2 + Vector3.new(1, 0, 0), 50)[1] == door2)
check("speedgate default hold 2 (state machine later)", gate:GetAttribute("DoorState") == "closed")

-- 2. open / hold / close for the founder ---------------------------------------------------------
local owner, ownerRoot = makePlayer(OWNER, "Founder", P1 + Vector3.new(1, -1.5, -3))
local ok, reason = Doors.request(owner, door1, "out")
check("owner request ok", ok == true, reason)
check("opening state", Doors.state(door1) == "opening")
check("leaf not collidable while opening", slab1.CanCollide == false)
check("reader good", colorEq(light1.Color, Palette.color.statusGood))
run(0.35)
local mid = leaf1:GetPivot()
check("leaf mid-way", not cfnear(mid, leaf1:GetAttribute("ClosedPivot")) and not cfnear(mid, leaf1:GetAttribute("OpenPivot")))
-- repeated triggers during opening must not restart the animation
Doors.request(owner, door1, "out")
Doors.request(owner, door1, "out")
run(0.3)
check("open after ~0.65 s despite repeated triggers", Doors.state(door1) == "open", Doors.state(door1))
check("leaf at OpenPivot", cfnear(leaf1:GetPivot(), leaf1:GetAttribute("OpenPivot")))
check("handle followed the leaf", slab1.CanCollide == false)
moveTo(ownerRoot, P1 + Vector3.new(0, -1.5, -12)) -- step away from the doorway
run(1.2)
check("reader back to neutral", colorEq(light1.Color, NEUTRAL))
run(2.5) -- ~3.8 s since fully open (HoldOpen counts from fully open)
check("still open within HoldOpen", Doors.state(door1) == "open")
run(1.4)
check("closing after HoldOpen", Doors.state(door1) == "closing" or Doors.state(door1) == "closed", Doors.state(door1))
run(0.8)
check("closed again", Doors.state(door1) == "closed")
check("leaf collidable again", slab1.CanCollide == true)
check("leaf at ClosedPivot", cfnear(leaf1:GetPivot(), leaf1:GetAttribute("ClosedPivot")))

-- 3. distance and denial -------------------------------------------------------------------------
local guest, guestRoot = makePlayer(2, "Guest", P1 + Vector3.new(0, -1.5, -15))
guest.cardHolder = true
ok, reason = Doors.request(guest, door1, "out")
check("too far rejected", ok == false and reason == "Move closer to the door.", reason)
moveTo(guestRoot, P1 + Vector3.new(0, -1.5, -3))
ok, reason = Doors.request(guest, door1, "out")
check("guest denied at founder door", ok == false and reason == "Denied:founder", reason)
check("reader bad", colorEq(light1.Color, Palette.color.statusBad))
check("door stays closed", Doors.state(door1) == "closed" and slab1.CanCollide == true)
run(1.6)
check("bad light restored", colorEq(light1.Color, NEUTRAL))

-- 4. egress always works (guest stuck inside the founder room) ----------------------------------
moveTo(guestRoot, P1 + Vector3.new(0, -1.5, 3))
ok, reason = Doors.request(guest, door1, "in")
check("egress from secure side", ok == true, reason)
run(0.7)
check("egress opened", Doors.state(door1) == "open")
moveTo(guestRoot, P1 + Vector3.new(0, -1.5, -14))

-- 5. reopen when the doorway is occupied during closing ------------------------------------------
local waited = runUntil(function() return Doors.state(door1) == "closing" end, 8)
check("closing begins after HoldOpen", Doors.state(door1) == "closing" and waited > 4.5 and waited < 5.6, waited)
moveTo(guestRoot, P1 + Vector3.new(0, -1.5, 0.5)) -- steps into the doorway
run(0.1)
check("reopens for occupant", Doors.state(door1) == "opening" or Doors.state(door1) == "open", Doors.state(door1))
check("leaf stays passable", slab1.CanCollide == false)
run(6)
check("held open while occupied", Doors.state(door1) == "open", Doors.state(door1))
moveTo(guestRoot, P1 + Vector3.new(0, -1.5, -14))
run(4)
check("closes after the doorway clears", Doors.state(door1) == "closed" and slab1.CanCollide == true, Doors.state(door1))

-- 6. lockdown ------------------------------------------------------------------------------------
Doors.lockAll(office, true)
check("locked state published", door1:GetAttribute("DoorState") == "locked" and Doors.state(door1) == "locked")
moveTo(ownerRoot, P1 + Vector3.new(0, -1.5, -3))
ok, reason = Doors.request(owner, door1, "out")
check("locked blocks entry", ok == false and reason == "Locked.", reason)
moveTo(guestRoot, P1 + Vector3.new(0, -1.5, 3))
ok = Doors.request(guest, door1, "in")
check("locked still allows egress", ok == true)
run(0.7)
check("egress through locked door opens", Doors.state(door1) == "open")
Doors.lockAll(office, false)
moveTo(guestRoot, P1 + Vector3.new(0, -1.5, -14))
moveTo(ownerRoot, P1 + Vector3.new(0, -1.5, -14))
run(6)
check("unlocked door closed", Doors.state(door1) == "closed")

-- 7. cubicle -------------------------------------------------------------------------------------
local _, _, sitter = makeChar("Sitter", P3 + Vector3.new(0, -1.5, 5))
seat[M.KEY].props.Occupant = sitter -- the seat is taken (Occupant is read-only in Roblox)
moveTo(guestRoot, P3 + Vector3.new(0, -1.5, -3))
ok, reason = Doors.request(guest, cub, "out")
check("occupied cubicle refuses outside", ok == false and reason == "Occupied", reason)
seat[M.KEY].props.Occupant = nil
ok, reason = Doors.request(guest, cub, "out")
check("free cubicle opens (no card check)", ok == true, reason)
run(0.7)
check("cubicle open", Doors.state(cub) == "open")
moveTo(guestRoot, P3 + Vector3.new(0, -1.5, 2)) -- inside, within the sensor
ok = Doors.request(guest, cub, "in")
check("toggle close accepted", ok == true and Doors.state(cub) == "closing")
run(0.8)
check("cubicle shut although occupied (manual)", Doors.state(cub) == "closed")
check("cubicle leaf not solid while occupant in sensor", cubSlab.CanCollide == false)
moveTo(guestRoot, P3 + Vector3.new(0, -1.5, 7))
run(0.1)
check("cubicle solid once doorway clear", cubSlab.CanCollide == true)
ok = Doors.request(guest, cub, "in")
check("egress from cubicle", ok == true)
run(0.7)
check("cubicle reopened", Doors.state(cub) == "open")
moveTo(guestRoot, P3 + Vector3.new(0, -1.5, -14))
run(6)

-- 8. employees -----------------------------------------------------------------------------------
local function makeNpc(role, pos, parentOffice)
	local npc, root = makeChar("Employee_" .. role, pos)
	npc:SetAttribute("OwnerUserId", (parentOffice or office):GetAttribute("OwnerUserId"))
	npc:SetAttribute("RoleId", role)
	npc.Parent = (parentOffice or office).Employees
	return npc, root
end
local researcher, rRoot = makeNpc("researcher", P2 + Vector3.new(0, -1.5, -3))
local marketer, mRoot = makeNpc("marketer", P2 + Vector3.new(1, -1.5, -3))
check("marketer denied research door", Doors.requestNPC(marketer, door2) == false)
check("researcher allowed research door", Doors.requestNPC(researcher, door2) == true)
run(0.7)
check("research door open for NPC", Doors.state(door2) == "open")
moveTo(mRoot, P2 + Vector3.new(0, -1.5, 3))
check("marketer egress from inside", Doors.requestNPC(marketer, door2) == true)
moveTo(rRoot, P2 + Vector3.new(0, -1.5, -20))
check("npc too far", Doors.requestNPC(researcher, door2) == false)
moveTo(rRoot, P5 + Vector3.new(0, -1.5, 3))
check("hidden bookcase never opens for NPCs (even egress)", Doors.requestNPC(researcher, book) == false)
local other = makeOffice(99, CFrame.new())
local outsider = makeNpc("engineer", P2 + Vector3.new(0, -1.5, -2), other)
check("npc of another office refused", Doors.requestNPC(outsider, door2) == false)
moveTo(mRoot, P2 + Vector3.new(0, -1.5, -30))
moveTo(rRoot, P2 + Vector3.new(0, -1.5, -30))
outsider:Destroy()
run(6)
check("research door closed again", Doors.state(door2) == "closed")

-- 9. automatic door ------------------------------------------------------------------------------
local visitor, visitorRoot = makePlayer(3, "Visitor", P4 + Vector3.new(0, -1.5, -20))
run(0.5)
check("auto door idle", Doors.state(auto) == "closed")
moveTo(visitorRoot, P4 + Vector3.new(0, -1.5, -5)) -- no card, outside
run(0.5)
check("auto door refuses card-less visitor", Doors.state(auto) == "closed")
check("denied approach notified once", #notices == 1 and notices[1].text == "Denied:staff", #notices)
run(2)
check("notice throttled", #notices == 1, #notices)
moveTo(visitorRoot, P4 + Vector3.new(0, -1.5, 5)) -- inside (e.g. after a tailgate): egress
run(0.3)
check("auto door opens for egress", Doors.state(auto) == "opening" or Doors.state(auto) == "open")
moveTo(visitorRoot, P4 + Vector3.new(0, -1.5, 40))
run(7)
check("auto door closes", Doors.state(auto) == "closed" and autoSlab.CanCollide == true)
visitor.cardHolder = true
moveTo(visitorRoot, P4 + Vector3.new(2, -1.5, -6))
run(0.3)
check("auto door opens for card holder", Doors.state(auto) ~= "closed")
moveTo(visitorRoot, P4 + Vector3.new(0, -1.5, -40))
run(7)

-- 10. speed gate ---------------------------------------------------------------------------------
moveTo(visitorRoot, P6 + Vector3.new(0, -1.5, -5))
run(0.5)
check("speed gate ignores people 5 studs away", Doors.state(gate) == "closed")
moveTo(visitorRoot, P6 + Vector3.new(0, -1.5, -2.5))
run(0.3)
check("speed gate opens for badge holder", Doors.state(gate) ~= "closed")
run(0.5)
moveTo(visitorRoot, P6 + Vector3.new(0, -1.5, 12))
run(3.0)
check("speed gate closes quickly behind", Doors.state(gate) == "closed", Doors.state(gate))

-- 11. plan fallback for a missing SecureNormal ---------------------------------------------------
local inward = showroomDef.inward
moveTo(guestRoot, P7 - inward * 3 + Vector3.new(0, -1.5, 0))
guest.cardHolder = false
ok = Doors.request(guest, plannedDoor, "out")
check("plan normal: outside denied", ok == false)
moveTo(guestRoot, P7 + inward * 3 + Vector3.new(0, -1.5, 0))
ok = Doors.request(guest, plannedDoor, "in")
check("plan normal: inside egress", ok == true)

-- 12. self-heal and unregister -------------------------------------------------------------------
door2:Destroy()
run(3.1)
check("destroyed door dropped", #Doors.inspect(office) == 6, #Doors.inspect(office))
check("destroyed door state", Doors.isPassable(door2) == false)
-- a door added after register is picked up lazily
local late = makeDoor("LATE_D1", "glass", "staff", Vector3.new(300, 4.5, 0))
check("late door found", Doors.find(office, "LATE_D1") == late)
Doors.unregister(office)
check("unregister clears", #Doors.inspect(office) == 0)
check("unregistered door refuses", (Doors.request(owner, door1, "out")) == false)

check("no errors in heartbeat threads", M.stats.errors == 0, M.stats.errors)
print(string.format("door_service_test: %d passed, %d failed", pass, fail))
if fail > 0 then
	error("door service test failed")
end
