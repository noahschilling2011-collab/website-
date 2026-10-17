--!nocheck
-- itinerary package: ItineraryController (client) on the REAL published state: the real server modules
-- (tests/itinerary/common.luau) with the real Remote (Notify "ITINERARY" reaches the client; TripAction InvokeServer
-- runs the server handler), the client's PlayerGui laid out by guiprev's GuiDump (AbsolutePosition / Size).
--   banner per state (offer: Go / Not now, never folded; pickup: title, live timer; collapse toggle), Go sends
--   TripAction go with the trip key, Cancel trip asks twice ("Sure? Tap again") then ends the trip and closes the
--   banner, the auto-trip countdown (timer text + bar, Not now cancels), phone-size layout (folds by default, touch
--   targets >= 44 pt), the banner slides below the drivers' ride panel and folds while it shows, the beacon on a
--   leg on foot (label with the distance, hidden next to it), companions follow the founder only when published
--   With + ShowAt and he walks (not while held in a car), caps, the client team sits at the meeting table and poses
--   MEETING once joined, no network traffic per frame.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_itinerary && cd tests/itinerary && ../../tools/luau test_client.luau -a .gen_itinerary
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_itinerary")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
for path, src in require("../world/stubs") do
	if not string.find(path, "Lib/Remote", 1, true) then sources[path] = src end
end
M.loadTree(manifest, sources)
M.quiet = true
local G = M.G
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end
local function has(text, part) return typeof(text) == "string" and string.find(text, part, 1, true) ~= nil end
local Common = require("./common")
local P = print

local function body()
	local Vector3, CFrame, Instance, UDim2 = G.Vector3, G.CFrame, G.Instance, G.UDim2
	local X = Common(M, G, { realRemote = true })
	local IM = X.IM
	local p, s = X.newPlayer(7901, "Noa", 4)
	local INSETS = { top = 58, right = 0, bottom = 0, left = 0 }
	local pg = X.clientSetup(p, s, { w = 1280, h = 720, insets = INSETS })
	local Ctl = X.Ctl
	-- count the client's TripAction calls (InvokeServer runs the bound handler)
	local invokes = 0
	local bound = X.Remote.binds.TripAction
	X.Remote.binds.TripAction = function(ss, payload) invokes += 1; return bound(ss, payload) end
	local lastPayload = nil
	local inner = X.Remote.binds.TripAction
	X.Remote.binds.TripAction = function(ss, payload) lastPayload = payload; return inner(ss, payload) end

	-- what guiprev's layout pass would write back (AbsolutePosition / AbsoluteSize in screen px)
	local function setAbs(inst, x, y, w, h)
		local stt = inst[M.KEY]
		stt.props.AbsolutePosition = G.Vector2.new(x, y)
		M.firePropChanged(inst, stt, "AbsolutePosition")
		stt.props.AbsoluteSize = G.Vector2.new(w, h)
		M.firePropChanged(inst, stt, "AbsoluteSize")
	end
	local function gui() return pg:FindFirstChild("ItineraryBanner") end
	local function find(name) local g = gui(); return g and g:FindFirstChild(name, true) end
	local function layout()
		X.GuiDump.setViewport(pg, X.vw or 1280, X.vh or 720, INSETS)
	end
	local function frames(sec)
		X.frame(sec or 0.5)
		layout()
		X.frame(0.25)
		layout()
	end
	local function click(name)
		local b = find(name)
		if not b then return false end
		M.fire(b.Activated)
		M.settle(0.1)
		return true
	end
	local function st() return X.state(p) or {} end
	local function atHQ() X.standAt(p, X.hqPoint(p, Vector3.new(0, 3, -60))) end
	local function waitCar(max) return X.waitFor(function() local rf = X.rideFolder(p); return rf ~= nil and rf:GetAttribute("State") == "waiting" end, max or 240) end
	X.advance(1.5)
	atHQ()
	X.advance(1.1)

	------------------------------------------------------------------ offer banner
	local trip = X.addTrip(s, "helix")
	local key = IM.tripKey(trip)
	X.advance(3.5)
	frames()
	check("banner shown for the offer", gui() ~= nil and gui().DisplayOrder == Ctl.ORDER)
	check("offer title", find("Title") and find("Title").Text == "Trip offer · Helix Research", find("Title") and find("Title").Text)
	check("offer buttons Go / Not this time (the call's labels)", find("Btn_go") ~= nil and find("Btn_decline") ~= nil and find("Btn_go").Text == "Go" and find("Btn_decline").Text == "Not this time")
	check("offer never folds (collapse hidden)", find("Collapse") and find("Collapse").Visible == false and find("Line").Visible == true)
	-- (the colleagues' tag is honest: "with X and Y", or "X and Y went ahead" when a field car already took them)
	check("offer line: city + flight + colleagues", has(find("Line").Text, "Port Meridian") and (has(find("Line").Text, "with ") or has(find("Line").Text, " went ahead")), find("Line").Text)
	-- Go
	click("Btn_go")
	X.advance(0.5)
	frames()
	check("Go sends TripAction go with the trip key", lastPayload and lastPayload.action == "go" and lastPayload.key == key)
	check("server: pickup", st().state == "pickup")
	check("pickup title", find("Title") and find("Title").Text == "To City Airport", find("Title") and find("Title").Text)
	local timer = find("Timer")
	check("live timer 'Car there in m:ss'", timer and timer.Visible and string.match(timer.Text, "^Car there in %d+:%d%d$") ~= nil, timer and timer.Text)
	check("step text 1 of 7 · Driver", find("StepText") and find("StepText").Text == "1 of 7 · Driver")
	check("cancel button", find("Btn_cancel") ~= nil and find("Btn_cancel").Text == "Cancel trip")
	-- drivers' ride panel on top: the banner slides below it and folds
	local drive = Instance.new("ScreenGui"); drive.Name = "DriveHUD"; drive.DisplayOrder = 24; drive.Enabled = true; drive.Parent = pg
	local rp = Instance.new("Frame"); rp.Name = "RidePanel"; rp.Size = UDim2.fromOffset(700, 80); rp.Position = UDim2.fromOffset(0, 0); rp.Parent = drive
	local sc = Ctl.bannerScale(gui())
	setAbs(find("Root"), 0, 58, 1280, 662)
	setAbs(find("TripPanel"), 12 * sc, 58 + 10 * sc, 380 * sc, 120 * sc)
	setAbs(rp, 290, 0, 700, 80)
	X.frame(0.3)
	local top = Ctl._avoidTop()
	check("banner moves below the ride panel", math.abs(top - (80 - 58 + 8) / sc) < 0.6 and find("TripPanel").Position.Y.Offset == top, tostring(top) .. " " .. tostring(find("TripPanel").Position.Y.Offset))
	check("banner folds while the ride panel shows (no second Cancel)", find("Line").Visible == false)
	drive:Destroy()
	X.frame(0.3)
	check("unfolds when the ride panel is gone, back to the top", find("Line").Visible == true and Ctl._avoidTop() <= 10.5 and find("TripPanel").Position.Y.Offset == 10)
	-- a ride panel elsewhere on the screen (no overlap) leaves the banner where it is
	local drive2 = Instance.new("ScreenGui"); drive2.Name = "DriveHUD"; drive2.Enabled = true; drive2.Parent = pg
	local rp2 = Instance.new("Frame"); rp2.Name = "RidePanel"; rp2.Size = UDim2.fromOffset(300, 80); rp2.Parent = drive2
	setAbs(rp2, 900, 0, 300, 80)
	X.frame(0.3)
	check("no overlap: banner stays at the top", Ctl._avoidTop() <= 10.5)
	drive2:Destroy()
	X.frame(0.3)
	-- collapse toggle (player's choice wins for this state)
	click("Collapse")
	frames()
	check("collapsed: one chip, no line, no buttons", find("Line").Visible == false and find("Btn_cancel") == nil and find("Collapse").Text == "+")
	click("Collapse")
	frames()
	check("unfolded again", find("Line").Visible == true and find("Btn_cancel") ~= nil and find("Collapse").Text == "–")
	-- no traffic per frame
	local before = invokes
	for _ = 1, 50 do X.frame(0.2) end
	check("no TripAction calls while idle (10 s of frames)", invokes == before, invokes - before)
	-- Cancel trip: two taps
	click("Btn_cancel")
	frames(0.3)
	check("first tap asks again", find("Btn_cancel") and find("Btn_cancel").Text == "Sure? Tap again" and st().state == "pickup")
	check("first tap sends nothing", lastPayload.action == "go")
	click("Btn_cancel")
	X.advance(0.5)
	frames()
	check("second tap cancels the trip", lastPayload.action == "cancel" and st().state == "none")
	check("banner closed", gui() == nil)
	check("player attribute cleared", p:GetAttribute("Itinerary") == nil)

	------------------------------------------------------------------ countdown
	s.data.empire.prefs.autoTrips = true
	X.addTrip(s, "frontier")
	X.advance(3.5)
	frames()
	check("countdown banner", st().state == "countdown" and find("Title") and has(find("Title").Text, "Business trip · Orbit Systems"))
	check("countdown timer 'Leaving in N s'", find("Timer") and string.match(find("Timer").Text, "^Leaving in %d+ s$") ~= nil, find("Timer") and find("Timer").Text)
	check("countdown bar visible", find("Countdown") and find("Countdown").Visible == true)
	click("Btn_decline")
	X.advance(0.5)
	frames()
	check("Not this time cancels the countdown (TripAction cancel)", lastPayload.action == "cancel" and st().state == "none" and gui() == nil)
	s.data.empire.prefs.autoTrips = nil

	------------------------------------------------------------------ phone-size screen
	X.vw, X.vh = 844, 390
	X.GuiDump.setViewport(pg, 844, 390, { top = 58, right = 47, bottom = 21, left = 47 })
	INSETS = { top = 58, right = 47, bottom = 21, left = 47 }
	local trip3 = X.addTrip(s, "nova")
	X.advance(3.5)
	frames()
	check("phone: offer not folded", find("Line") and find("Line").Visible == true)
	local goBtn = find("Btn_go")
	local pt = goBtn and goBtn.Size.Y.Offset * Ctl.bannerScale(gui())
	check("phone: touch target >= 44 pt", pt and pt >= 44, pt)
	check("phone: compact metrics", Ctl.bannerScale(gui()) < Ctl.COMPACT)
	click("Btn_go")
	X.advance(0.5)
	frames()
	check("phone: Go (2)", st().state == "pickup", st().state .. " " .. tostring(lastPayload and lastPayload.action))
	check("phone: a step without a decision starts folded", st().state == "pickup" and find("Line").Visible == false and find("Collapse").Visible == true)
	check("phone: folded chip shows the timer", find("Timer") and find("Timer").Visible == true)
	local panel = find("TripPanel")
	local scP = Ctl.bannerScale(gui())
	check("phone: banner (chip) fits the safe area", panel and (panel.Position.X.Offset + panel.Size.X.Offset) * scP <= 844 - 47 - 47, panel and (panel.Position.X.Offset + panel.Size.X.Offset) * scP)
	local _ = trip3
	X.vw, X.vh = 1280, 720
	INSETS = { top = 58, right = 0, bottom = 0, left = 0 }
	X.GuiDump.setViewport(pg, 1280, 720, INSETS)

	------------------------------------------------------------------ companions follow (the published folder: With + ShowAt)
	-- (the server side of With / ShowAt is test_service's; here the client's reading of it, X.frame only)
	local f = X.RS.CompanyItinerary:FindFirstChild("Itin_" .. p.UserId)
	check("published folder with two companions", f ~= nil and f:FindFirstChild("Companion1") ~= nil and f:FindFirstChild("Companion2") ~= nil)
	local cam = M.game.Workspace.CurrentCamera
	if not cam then
		cam = Instance.new("Camera"); cam.Parent = M.game.Workspace
		pcall(function() M.game.Workspace.CurrentCamera = cam end)
	end
	local function camAt(pos) if cam then cam.CFrame = CFrame.new(pos + Vector3.new(0, 10, 20)) end end
	local start = X.hqPoint(p, Vector3.new(0, 3, -80))
	X.standAt(p, start)
	camAt(start)
	f:SetAttribute("With", false)
	X.frame(0.6)
	check("With false: nobody walks along", (Ctl.counts()) == 0)
	f:SetAttribute("With", true)
	f:SetAttribute("ShowAt", X.T + 5)
	X.frame(0.6)
	check("not before ShowAt (the car's drop-off pause)", (Ctl.counts()) == 0)
	f:SetAttribute("ShowAt", X.T - 1)
	X.frame(0.6)
	check("With + ShowAt reached: both companions follow", (Ctl.counts()) == 2, (Ctl.counts()))
	local people = M.game.Workspace:FindFirstChild("ItineraryPeople")
	check("client clones without Humanoid", people ~= nil and #people:GetChildren() == 2 and people:GetChildren()[1]:FindFirstChildOfClass("Humanoid") == nil)
	-- walk 30 studs: they keep up behind him
	for i = 1, 30 do
		X.standAt(p, start + Vector3.new(0, 0, i))
		X.frame(1 / 15)
	end
	X.frame(2)
	local maxD = 0
	for _, m in (people and people:GetChildren() or {}) do
		local r = m:FindFirstChild("HumanoidRootPart")
		if r then maxD = math.max(maxD, (Vector3.new(r.Position.X, 0, r.Position.Z) - Vector3.new(p.root.Position.X, 0, p.root.Position.Z)).Magnitude) end
	end
	check("companions keep up (a few studs behind)", maxD > 1 and maxD < 12, maxD)
	-- a jump (teleport, elevator): they are put next to him
	X.standAt(p, start + Vector3.new(150, 0, 0))
	camAt(p.root.Position)
	X.frame(0.2)
	local far = 0
	for _, m in (people and people:GetChildren() or {}) do
		local r = m:FindFirstChild("HumanoidRootPart")
		if r then far = math.max(far, (r.Position - p.root.Position).Magnitude) end
	end
	check("companions catch up a jump (TELEPORT)", far < 15, far)
	-- held by a car / a flight (anchored): no walkers
	p.root.Anchored = true
	X.frame(0.6)
	check("anchored (riding / flying): no walkers", (Ctl.counts()) == 0)
	p.root.Anchored = false
	X.frame(0.6)
	check("walkers back when he stands again", (Ctl.counts()) == 2)
	-- far from the camera: culled
	camAt(p.root.Position + Vector3.new(0, 0, 600))
	X.frame(0.6)
	check("culled beyond FOLLOW_NEAR", (Ctl.counts()) == 0)
	camAt(p.root.Position)
	X.Itin.cancel(p)
	X.advance(0.5)
	X.frame(0.6)
	check("trip over: walkers gone", (Ctl.counts()) == 0 and #M.game.Workspace.ItineraryPeople:GetChildren() == 0)

	------------------------------------------------------------------ beacon (a leg on foot: the view's target)
	local gate = X.FP.HOME_GATES[1]
	X.standAt(p, gate + Vector3.new(60, 0, 0))
	Ctl._apply({ seq = 99, state = "airport", tier = "abroad", title = "Gate A1 · PM 101", line = "", buttons = {}, step = 2, steps = 7, stepName = "Airport",
		icon = "map", target = { pos = gate, label = "Gate A1 · PM 101" } })
	X.frame(0.3)
	local bf = M.game.Workspace:FindFirstChild("ItineraryBeacon")
	check("beacon drawn at the target", bf ~= nil and bf:FindFirstChild("Beacon") ~= nil and math.abs(bf.Beacon.Position.X - gate.X) < 0.1)
	local bl = bf and bf:FindFirstChild("BeaconLabel", true)
	local label = bl and bl:FindFirstChildOfClass("TextLabel")
	check("beacon label: name + distance", label and label.Text == "Gate A1 · PM 101\n60 studs", label and label.Text)
	X.standAt(p, gate + Vector3.new(1, 0, 1))
	X.frame(0.3)
	check("beacon hidden next to it", bf and bf.Beacon.Transparency == 1 and bl.Enabled == false)
	Ctl._apply({ closed = true })
	X.frame(0.3)
	check("closed view: beacon + banner gone", M.game.Workspace:FindFirstChild("ItineraryBeacon") == nil and gui() == nil)

	------------------------------------------------------------------ the client team in the meeting room (region trip)
	atHQ()
	local trip4 = X.addTrip(s, "creative")
	X.advance(3.5)
	X.Itin.go(p, IM.tripKey(trip4))
	X.advance(0.5)
	local place = X.Drive.clientPlace("PixelForge")
	X.standAt(p, place.door.Position)
	X.advance(1)
	check("region: at the office -> meeting", st().state == "meeting")
	local spot = IM.meetingSpot(IM.officeId("PixelForge"))
	if cam then cam.CFrame = CFrame.new(spot.table.Position + Vector3.new(0, 8, 12)) end
	X.frame(0.6)
	local _, nT = Ctl.counts()
	check("client team seated at the table (2)", nT == 2, nT)
	local seatedOk = true
	for _, m in M.game.Workspace.ItineraryPeople:GetChildren() do
		local r = m:FindFirstChild("HumanoidRootPart")
		local near = false
		for _, cf in spot.clients do if r and (r.Position - cf.Position).Magnitude < 0.1 then near = true end end
		if string.find(m.Name, "Client", 1, true) and not near then seatedOk = false end
	end
	check("client team on the far chairs", seatedOk)
	-- the folded chip on a phone says what to do in this step (review: "press Start meeting" never showed folded)
	X.vw, X.vh = 844, 390
	INSETS = { top = 58, right = 47, bottom = 21, left = 47 }
	X.GuiDump.setViewport(pg, 844, 390, INSETS)
	frames()
	check("phone: meeting step folded, the chip shows the action", find("Line").Visible == false and find("Action") and find("Action").Visible == true
		and find("Action").Text == "Press Start meeting at the table" and find("Title").Text == "Meeting · PixelForge", find("Action") and find("Action").Text)
	check("phone: folded chip shows no progress dots when it has an action", find("Dots").Visible == false)
	X.vw, X.vh = 1280, 720
	INSETS = { top = 58, right = 0, bottom = 0, left = 0 }
	X.GuiDump.setViewport(pg, 1280, 720, INSETS)
	frames()
	-- a second founder visits the same client at the same time: his client team takes the other chairs (SeatSet 2)
	local pB = X.newPlayer(7902, "Ben", 4)
	local fA = X.RS.CompanyItinerary["Itin_" .. p.UserId]
	local fB = fA:Clone()
	fB.Name = "Itin_" .. pB.UserId
	fB:SetAttribute("Owner", pB.UserId)
	fB:SetAttribute("SeatSet", 2)
	fB:SetAttribute("With", false)
	fB.Parent = X.RS.CompanyItinerary
	X.frame(0.6)
	local _, nTeams = Ctl.counts()
	local seatsUsed, clash = {}, false
	for _, m in M.game.Workspace.ItineraryPeople:GetChildren() do
		if string.find(m.Name, "Client", 1, true) then
			local r = m:FindFirstChild("HumanoidRootPart")
			for _, q in seatsUsed do if (q - r.Position).Magnitude < 1 then clash = true end end
			table.insert(seatsUsed, r.Position)
		end
	end
	check("two teams at one client: 4 client NPCs on 4 different chairs", nTeams == 4 and #seatsUsed == 4 and not clash, tostring(nTeams) .. " clash=" .. tostring(clash))
	fB:Destroy()
	X.frame(1.5)
	trip4.joined = true
	X.advance(0.6)
	X.frame(0.6)
	check("joined -> folder Joined (MEETING pose)", X.RS.CompanyItinerary["Itin_" .. p.UserId]:GetAttribute("Joined") == true)
	if cam then cam.CFrame = CFrame.new(spot.table.Position + Vector3.new(0, 8, 400)) end
	X.frame(0.6)
	local _, nT2 = Ctl.counts()
	check("client team culled far away (CLIENTS_NEAR)", nT2 == 0, nT2)
	X.Itin.cancel(p)
	X.advance(0.5)
	X.frame(0.6)
	X.frame(1.5)
	check("all client NPCs gone after the trip", #M.game.Workspace.ItineraryPeople:GetChildren() == 0)

	------------------------------------------------------------------ followers: stairs, jumps, fades, caps, LOD, boarding (review round)
	-- synthetic published folders (the server is not ticked below: these attributes stay as set)
	atHQ()
	table.clear(s.data.empire.deals.tripList) -- (the earlier trips used up the field reps)
	X.advance(1.5)
	local trip5 = X.addTrip(s, "helix")
	X.advance(3.5)
	X.Itin.go(p, IM.tripKey(trip5))
	X.advance(0.5)
	local real = X.RS.CompanyItinerary:FindFirstChild("Itin_" .. p.UserId)
	check("fixture: a trip with two companion templates", real ~= nil and real:FindFirstChild("Companion2") ~= nil)
	real:SetAttribute("With", false)
	real:SetAttribute("MeetingOn", false)
	local function synth(owner, extra)
		local f = Instance.new("Folder")
		f.Name = "Itin_syn" .. owner
		f:SetAttribute("Owner", owner); f:SetAttribute("With", true); f:SetAttribute("ShowAt", 0); f:SetAttribute("State", "limo")
		for _, c in real:GetChildren() do if string.match(c.Name, "^Companion%d$") then c:Clone().Parent = f end end
		for k, v in extra or {} do f:SetAttribute(k, v) end
		f.Parent = X.RS.CompanyItinerary
		return f
	end
	local base = X.hqPoint(p, Vector3.new(30, 3, -90))
	X.standAt(p, base)
	camAt(base)
	X.frame(0.6)
	local fs = synth(p.UserId, real:GetAttribute("ClientKey") and {} or {})
	X.frame(0.15)
	local g = Ctl._groups()[p.UserId]
	local rg1 = g and g.rigs[1]
	local function lt(rg) for _, d in rg.model:GetDescendants() do if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then return d.LocalTransparencyModifier end end return -1 end
	check("a companion fades in (not popping in)", rg1 ~= nil and lt(rg1) > 0.5, rg1 and lt(rg1))
	X.frame(1)
	check("... fully visible after FADE_IN", rg1 ~= nil and lt(rg1) == 0, rg1 and lt(rg1))
	-- up a ramp (0.5 studs per stud): the followers stand at the height of the trail point they walk, not at his
	for i = 1, 24 do
		X.standAt(p, base + Vector3.new(0, i * 0.5, i))
		X.frame(1 / 12)
	end
	X.frame(2)
	local top = p.root.Position.Y
	local r2 = g and g.rigs[2]
	check("stairs: the second companion (6.8 studs behind) is ~3.4 studs lower than him", r2 ~= nil and math.abs((top - r2.pos.Y) - Ctl.GAP * 2 * 0.5) < 1.2, r2 and (top - r2.pos.Y))
	check("stairs: the first companion ~1.7 studs lower", rg1 ~= nil and math.abs((top - rg1.pos.Y) - Ctl.GAP * 0.5) < 1, rg1 and (top - rg1.pos.Y))
	-- a jump: with a ground ray they stay on the ground (the mock has no physics: a patched Raycast plays the floor)
	local groundY = p.root.Position.Y - 3
	local realRay = M.IMPL.Workspace.methods.Raycast
	local function fakeRay(_, origin, dir) return { Position = Vector3.new(origin.X, groundY, origin.Z), Normal = Vector3.new(0, 1, 0), Distance = origin.Y - groundY } end
	M.IMPL.Workspace.methods.Raycast = fakeRay
	M.classInfo("Workspace").methods.Raycast = fakeRay
	for i = 1, 6 do X.standAt(p, p.root.Position + Vector3.new(0, 0, 0.6)); X.frame(0.1) end
	-- a long jump: 9 studs forward in the air (the trail he leaves is up there)
	for i = 1, 9 do X.standAt(p, Vector3.new(p.root.Position.X, groundY + 3 + 5, p.root.Position.Z + 1)); X.frame(0.06) end
	X.frame(0.3)
	check("a jump: the companions stay on the ground (ground ray), not on his trail in the air", rg1 ~= nil and math.abs(rg1.pos.Y - (groundY + 3)) < 1 and r2 ~= nil
		and math.abs(r2.pos.Y - (groundY + 3)) < 1, rg1 and (rg1.pos.Y - groundY))
	M.IMPL.Workspace.methods.Raycast = realRay
	M.classInfo("Workspace").methods.Raycast = realRay
	X.standAt(p, p.root.Position - Vector3.new(0, 6, 0))
	X.frame(0.5)
	-- pose LOD: no joint updates beyond POSE_FAR from the camera
	local joint
	for _, j in pairs(rg1 and rg1.joints or {}) do joint = j; break end
	if joint then
		joint.Transform = CFrame.new()
		Ctl._pose(rg1, "IDLE", false, true, X.T + 0.37, rg1.root.Position + Vector3.new(0, 0, Ctl.POSE_FAR + 10))
		local farSame = joint.Transform == CFrame.new()
		Ctl._pose(rg1, "IDLE", false, true, X.T + 0.37, rg1.root.Position + Vector3.new(0, 0, 5))
		check("pose LOD: skipped beyond POSE_FAR, posed near", farSame and joint.Transform ~= CFrame.new())
	else
		check("rig has joints", false)
	end
	-- they leave by fading out (not vanishing)
	fs:SetAttribute("With", false)
	X.frame(0.6)
	check("With off: no longer following, still fading out", (Ctl.counts()) == 0 and Ctl.rigCount() == 2, Ctl.rigCount())
	X.frame(1)
	check("... gone after FADE_OUT", Ctl.rigCount() == 0, Ctl.rigCount())
	-- the cap counts rigs: 5 founders with 2 companions each near the camera -> at most MAX_FOLLOWERS rigs
	fs:SetAttribute("With", true)
	local extras = {}
	for i = 1, 4 do
		local px = X.newPlayer(7910 + i, "Cap" .. i, 4)
		X.standAt(px, p.root.Position + Vector3.new(i * 6, 0, 0))
		table.insert(extras, synth(px.UserId))
	end
	X.frame(1.2)
	local nF = Ctl.counts()
	check("follower cap counts rigs (<= MAX_FOLLOWERS)", nF <= Ctl.MAX_FOLLOWERS and nF >= 4, nF)
	for _, f in extras do f:Destroy() end
	X.frame(1.5)
	-- boarding at gate A1: they walk the shuttle's boarding path into the cabin (ShuttlePassengers.path), then go
	local gate = X.FP.HOME_GATES[1]
	local cycle = X.FP.nextLeg("out", X.T)
	local boardT = X.FP.legStart("out", cycle + 1) + 20
	X.T = boardT
	local stB = X.FP.at(X.T)
	check("fixture: out boarding open", stB.dir == "out" and stB.phase == "boarding", stB.phase)
	X.standAt(p, gate + Vector3.new(2, 0, 3))
	camAt(p.root.Position)
	fs:SetAttribute("State", "airport")
	X.frame(1.2)
	check("followers at the gate", (Ctl.counts()) == 2)
	local before = {}
	for i, rg in Ctl._groups()[p.UserId].rigs do before[i] = rg.pos end
	p.root.Anchored = true -- boarded (held by the shuttle)
	fs:SetAttribute("State", "flight")
	X.frame(0.6)
	local gb = Ctl._groups()[p.UserId]
	check("boarding: they leave walking into the aircraft (not fading at the gate)", gb ~= nil and gb.leaving == "board", gb and gb.leaving)
	X.frame(2)
	local moved = gb and gb.rigs[1] and gb.rigs[1].walked > 10 and (gb.rigs[1].pos - before[1]).Magnitude > 2
	check("boarding: they walk the boarding path", moved == true, gb and gb.rigs[1] and gb.rigs[1].walked)
	X.frame(Ctl.BOARD_MAX + 1)
	check("boarding: gone inside the cabin", Ctl._groups()[p.UserId] == nil and Ctl.rigCount() == 0)
	p.root.Anchored = false
	fs:Destroy()
	X.Itin.cancel(p)
	check("no background errors", M.stats.errors == 0, M.stats.errors)
end

setfenv(body, M.envFor(nil))
local ok, err = M.runMain(body, { timeout = 6000, maxSteps = 60000000 })
if not ok then failc += 1; print("CRASH " .. tostring(err)) end
if M.stats.errors > 0 then failc += 1; print("FAIL  background thread errors: " .. M.stats.errors) end
print(string.format("itinerary_client: %d passed, %d failed", pass, failc))
