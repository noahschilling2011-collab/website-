--!nocheck
-- Flight package client smoke test (headless mock): the real TravelController -> ShuttleController /
-- AirTrafficController wired to the real CityService/ShuttleService through patched remotes, with a
-- controlled server clock. Frames are stepped by hand (the mock never fires RenderStepped).
-- Checks: the client shuttle (LOD by distance, parked on the stand, the stand aircraft hidden locally, one
-- BulkMoveTo per frame), check-in -> boarding pass + gate beacon, gate board, the pilots (walk, seat in the
-- cockpit), board prompt -> ride (camera, window overlay, view toggle, captain announcement, gear up),
-- arrival (camera back, welcome toast), Port Meridian airstairs, ambient traffic appears and goes, the VIP
-- helicopter (parked, flying a published transfer, rider camera), shuttle off -> legacy check-in.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_flight && tools/luau tests/flight/test_client.luau [-a .gen_dir]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_flight")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
for path, src in require("../world/stubs") do sources[path] = src end
M.loadTree(manifest, sources)
M.quiet = true
local G = M.G
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local function body()
	local Instance, Vector3, CFrame, Enum = G.Instance, G.Vector3, G.CFrame, G.Enum
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local S = Server.Services
	local Client = game.StarterPlayer.StarterPlayerScripts.Client
	local F = require("../world/fixture")(M, G)
	local Net = M.require(RS.Shared.Net)
	local Remote = M.require(Server.Lib.Remote)
	local Session = M.require(S.SessionService)
	local Shop = M.require(S.ShopService)
	local CityPlan = M.require(RS.Shared.Config.CityPlan)
	local FP = M.require(RS.Shared.FlightPlan)
	local Aircraft = M.require(RS.Shared.AircraftModel)
	-- clock + BulkMoveTo
	local T = 1.7e9
	local function patch(cls, name, fn) M.IMPL[cls].methods[name] = fn; local ci = M.classInfo(cls); if ci.methods then ci.methods[name] = fn end end
	patch("Workspace", "GetServerTimeNow", function() return T end)
	local bulkCalls = 0
	local bulkModels = {}
	patch("Workspace", "BulkMoveTo", function(self, parts, cframes) bulkCalls += 1; if parts[1] then bulkModels[parts[1].Parent] = (bulkModels[parts[1].Parent] or 0) + 1 end; for i, p in parts do p.CFrame = cframes[i] end end)
	local Design = M.require(S.HeadquartersDesign); Design.build = function() local m = Instance.new("Model"); m.Name = "Office"; return m end; Design.staff = function() end
	local Plot = M.require(S.PlotService)
	Plot.get = function(player) return { index = 3, cframe = CityPlan.plots()[3].cframe, owner = player } end
	local City = M.require(S.CityService)
	local Shuttle = M.require(S.ShuttleService)
	local I = FP.interval()
	local K = math.floor((T - FP.CONFIG.epoch) / I) + 1
	local out, back = FP.leg("out"), FP.leg("back")
	local function ls(dir, k) return FP.legStart(dir, k) end
	T = ls("out", K - 1) + out.phases.cruise.t0
	City.init()
	-- local player with per-attribute change signals
	local counter = CityPlan.AIRPORT.checkin[1]
	local owner = F.player(9101, "Flyer", CFrame.new(counter.X, 27.5, counter.Z - 6))
	local s = F.session(owner, 100000)
	table.insert(Session.sessions, s)
	for _, fn in Session.loaded do fn(s) end
	local playerGui = Instance.new("Folder"); playerGui.Name = "PlayerGui"
	owner.FindFirstChild = function(_, name) if name == "PlayerGui" then return playerGui end end
	owner.WaitForChild = function(_, name) if name == "PlayerGui" then return playerGui end end
	local signals = {}
	owner.GetAttributeChangedSignal = function(_, name) signals[name] = signals[name] or M.newSignal(name); return signals[name] end
	local rawSet = owner.SetAttribute
	owner.SetAttribute = function(self, k, v) rawSet(self, k, v); if signals[k] then M.fire(signals[k]) end end
	M.IMPL.Players.get.LocalPlayer = function() return owner end; M.classInfo("Players").get.LocalPlayer = function() return owner end
	local folder = Instance.new("Folder"); folder.Name = Net.FOLDER
	for _, name in Net.FUNCTIONS do local f = Instance.new("RemoteFunction"); f.Name = name; f.Parent = folder end
	for _, name in Net.EVENTS do local e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = folder end
	folder.Parent = RS
	local calls = {}
	patch("RemoteFunction", "InvokeServer", function(self, payload)
		table.insert(calls, { name = self.Name, payload = payload })
		if self.Name == "RequestState" then return { ok = true, state = { saveEnabled = false, serverTime = T, data = s.data, live = s.live } } end
		local handler = Remote.binds[self.Name]
		if not handler then return { ok = false, err = "BAD_INPUT" } end
		local result = handler(s, payload or {})
		calls[#calls].result = result
		return result
	end)
	local UIRoot = M.require(Client.UI.UIRoot)
	local Toast = M.require(Client.UI.Toast)
	local State = M.require(Client.Controllers.StateController)
	local Travel = M.require(Client.Controllers.TravelController)
	local SC = M.require(Client.Controllers.ShuttleController)
	local AT = M.require(Client.Controllers.AirTrafficController)
	local hud, dim, overlay, intro, top = UIRoot.init()
	Toast.mount(top)
	local World = M.require(Client.Controllers.WorldController)
	World.init(function() end) -- disables every prompt that is neither own nor Public
	Travel.init()
	State.init()
	M.settle(1)
	local function toastHas(part)
		for _, d in top:GetDescendants() do if d:IsA("TextLabel") and string.find(d.Text, part, 1, true) then return true end end
		return false
	end
	local function lastCall(name) for i = #calls, 1, -1 do if calls[i].name == name then return calls[i] end end end
	local PPS = game:GetService("ProximityPromptService")
	local camera = game.Workspace.CurrentCamera
	local function look(at) camera.CFrame = CFrame.new(at + Vector3.new(0, 60, 120), at) end
	local function frame(dt) SC.step(dt or 0.3) end
	local client = function() return game.Workspace:FindFirstChild("ShuttleClient") end
	local function plane() return SC.plane() end
	local function parts(m) local n, solid = 0, 0; for _, d in m:GetDescendants() do if d:IsA("BasePart") then n += 1; if d.CanCollide then solid += 1 end end end; return n, solid end

	------------------------------------------------------------------ the parked shuttle
	check("controller sees the shuttle", SC.active() == true)
	local stand = CityPlan.AIRPORT.standCFrames[CityPlan.AIRPORT.shuttleStand]
	T = ls("out", K) - 5; City.tick(0.1) -- deboarding of the previous return leg: parked
	look(stand.Position)
	local b0 = bulkCalls
	frame(0.3)
	local pl = plane()
	check("client shuttle built near the camera (full LOD)", pl ~= nil and pl:GetAttribute("AircraftLod") == "full" and pl.Parent == client())
	local np, nsolid = parts(pl)
	check("full shuttle <= 400 parts", np <= 400 and np > 150, np)
	check("parked exactly on the stand", pl and (pl.PrimaryPart.Position - stand.Position).Magnitude < 0.01)
	check("one BulkMoveTo per frame", bulkCalls == b0 + 1, bulkCalls - b0)
	local hidden, total = 0, 0
	for _, d in game.Workspace.WorldCity:GetDescendants() do
		if d:IsA("Model") and d.Name == "ParkedAircraft" and d:GetAttribute("Stand") == CityPlan.AIRPORT.shuttleStand then
			for _, p in d:GetDescendants() do if p:IsA("BasePart") then total += 1; if p.LocalTransparencyModifier == 1 and not p.CanCollide then hidden += 1 end end end
		end
	end
	check("the stand's server aircraft is hidden locally (the shuttle replaces it)", total > 0 and hidden == total, hidden .. "/" .. total)
	-- the model is not Atomic: a part streaming in later is hidden as it arrives
	for _, d in game.Workspace.WorldCity:GetDescendants() do
		if d:IsA("Model") and d.Name == "ParkedAircraft" and d:GetAttribute("Stand") == CityPlan.AIRPORT.shuttleStand then
			local late = G.Instance.new("Part"); late.Name = "StreamedIn"; late.CanCollide = true; late.Parent = d
			check("a part of the stand aircraft that streams in later is hidden too", late.LocalTransparencyModifier == 1 and not late.CanCollide)
			late:Destroy()
			break
		end
	end
	look(Vector3.new(0, 30, 0)) -- the campus district, ~2,600 studs away
	frame(0.1)
	check("medium LOD from the district", plane() ~= nil and plane():GetAttribute("AircraftLod") == "medium")
	look(Vector3.new(0, 30, -6000))
	frame(0.1)
	check("nothing built far away", plane() == nil)

	------------------------------------------------------------------ check-in: shuttle or express when boarding is far away
	-- a second company with an abroad trip: its field rep flies on the next out leg (ShuttlePassengers)
	local pf = F.player(9109, "Fiona", CFrame.new(0, 27.5, 0))
	local sf = F.session(pf, 100000)
	sf.data.company.name = "Helix Partners"
	local ef = sf.data.empire
	ef.office = 4; ef.employees = ef.employees or {}; ef.employees.marketer = 1; ef.employees.engineer = 0
	ef.staffProfiles = { marketer = { { n = "Mia Chen", s = 1111 } } }
	ef.deals = ef.deals or {}
	ef.deals.tripList = { { client = "helix", kind = "sign", back = 1e12, founder = false, hosted = false, crew = 1, left = 4242 } }
	table.insert(Session.sessions, sf)
	local checkin
	for _, d in game.Workspace.WorldCity:GetDescendants() do if d:IsA("ProximityPrompt") and d:GetAttribute("FlightTo") == "abroad" then checkin = d; break end end
	check("check-in prompt exists", checkin ~= nil)
	owner.Character:PivotTo(CFrame.new(counter.X, 27.5, counter.Z - 6))
	local Tsave = T
	T = ls("out", K) - FP.CONFIG.charterAfter - 60
	local nCalls = #calls
	M.fire(PPS.PromptTriggered, checkin, owner); M.settle(0.3)
	local choiceGui = playerGui:FindFirstChild("FlightChoice")
	check("boarding > 3 min away: the counter offers shuttle or express (no ticket bought yet)", choiceGui ~= nil and #calls == nCalls)
	local btns = {}
	if choiceGui then for _, d in choiceGui:GetDescendants() do if d:IsA("TextButton") then table.insert(btns, d.Text) end end end
	check("choice: shuttle boarding pass and an express flight now", #btns == 2 and string.find(btns[1], "Shuttle", 1, true) ~= nil and string.find(btns[2], "Express", 1, true) ~= nil, table.concat(btns, " | "))
	T = Tsave

	------------------------------------------------------------------ check-in + boarding pass
	owner.Character:PivotTo(CFrame.new(0, 27.5, 0))
	M.fire(PPS.PromptTriggered, checkin, owner); M.settle(0.5)
	check("check-in far from the counter refused (toast)", toastHas("check-in counter") and playerGui:FindFirstChild("ShuttlePass") == nil)
	owner.Character:PivotTo(CFrame.new(counter.X, 27.5, counter.Z - 6))
	local money0 = s.data.money
	M.fire(PPS.PromptTriggered, checkin, owner); M.settle(0.5)
	local c = lastCall("TravelAction")
	check("check-in buys a shuttle ticket (not the instant flight)", c and c.payload.action == "ticket" and c.result.ok == true and s.data.money == money0 - CityPlan.TRAVEL.ticket)
	check("no cutscene", game.Workspace:FindFirstChild("FlightCutscene") == nil)
	check("boarding soon: straight to the boarding pass, the choice panel closed", playerGui:FindFirstChild("FlightChoice") == nil)
	check("boarding pass shown", playerGui:FindFirstChild("ShuttlePass") ~= nil and SC.ticket() ~= nil)
	check("check-in toast names the flight and the gate", toastHas("Checked in: " .. FP.CONFIG.flights.out) and toastHas("gate A" .. CityPlan.AIRPORT.shuttleStand))
	check("gate beacon placed", client():FindFirstChild("ShuttleGateBeacon") ~= nil)
	frame(0.3)
	local passText = playerGui.ShuttlePass:FindFirstChild("Text", true)
	check("pass counts down to boarding", passText and string.find(passText.Text, "Boarding in", 1, true) ~= nil, passText and passText.Text)

	------------------------------------------------------------------ boarding, gate board, pilots
	local walkStart = out.phases.boarding.t1 - FP.CREW_SEATED - FP.CREW_WALK
	T = ls("out", K) + walkStart + 6; City.tick(0.1)
	look(FP.HOME_GATES[1])
	frame(0.3)
	check("pass: boarding now", string.find(passText.Text, "BOARDING NOW", 1, true) ~= nil, passText.Text)
	local CS = game:GetService("CollectionService")
	local gateText, doorText
	for _, p in CS:GetTagged("FlightInfoBoard") do
		local l = p:FindFirstChild("FlightText", true)
		if l and p:GetAttribute("Board") == "gate" then gateText = l.Text end
		if l and p:GetAttribute("Board") == "gatedoor" then doorText = l.Text end
	end
	check("the airport's gate sign shows the live status (FlightInfoBoard)", gateText ~= nil and string.find(gateText, "BOARDING", 1, true) ~= nil and string.find(gateText, FP.CONFIG.flights.out, 1, true) ~= nil, gateText)
	check("gate door sign live too", doorText ~= nil and string.find(doorText, "BOARDING", 1, true) ~= nil, doorText)
	check("no pixel-sized home gate board any more", (function() for _, d in playerGui:GetChildren() do if d.Name == "ShuttleGateBoard" and d.Enabled and d.Adornee and d.Adornee.Name == "GateBoardHome" then return false end end return true end)())
	-- the field rep of the other company walks to the aircraft during boarding
	T = ls("out", K) + 5 + 4; City.tick(0.1); frame(0.3)
	local walkers = {}
	for _, d in client():GetChildren() do if string.sub(d.Name, 1, 9) == "Passenger" then table.insert(walkers, d) end end
	check("field staff passenger walking to the aircraft during boarding", #walkers == 1 and walkers[1]:GetAttribute("PassengerName") == "Mia Chen", #walkers)
	local wr = walkers[1] and walkers[1]:FindFirstChild("HumanoidRootPart")
	local wHead = walkers[1] and walkers[1]:FindFirstChild("Head")
	check("passenger visible, between the gate and the aircraft door", wr ~= nil and wHead.LocalTransparencyModifier == 0 and wr.Position.Z > 2500 and wr.Position.Z < stand.Position.Z, wr and wr.Position)
	T = ls("out", K) + 5 + 30; frame(0.3)
	local still = 0
	for _, d in client():GetChildren() do if string.sub(d.Name, 1, 9) == "Passenger" then still += 1 end end
	check("passenger boarded (removed once inside)", still == 0, still)
	T = ls("out", K) + walkStart + 6; frame(0.3)
	local solidNow = 0
	for _, d in plane():GetDescendants() do if d:IsA("BasePart") and d.CanCollide then solidNow += 1 end end
	check("parked full shuttle collides (nobody walks through it)", solidNow >= 12, solidNow)
	local cap = client():FindFirstChild("Captain"); local fo = client():FindFirstChild("FirstOfficer")
	check("two pilots on the client", cap ~= nil and fo ~= nil)
	local seatCap = Aircraft.points(FP.CONFIG.kind, FP.CONFIG.scale).captain
	local capRoot = cap and cap:FindFirstChild("HumanoidRootPart")
	check("pilots walking (not yet in the seat)", capRoot and (capRoot.Position - (stand * seatCap).Position).Magnitude > 5, capRoot and capRoot.Position)
	check("pilot clones are decoration (no collision, no humanoid)", (function()
		for _, d in cap:GetDescendants() do if d:IsA("BasePart") and d.CanCollide then return false end; if d:IsA("Humanoid") then return false end end
		return true end)())
	local function capVisible() local head = cap:FindFirstChild("Head"); return head and head.LocalTransparencyModifier == 0 end
	check("walking pilot visible", capVisible())
	T = ls("out", K) + walkStart - 1; frame(0.3)
	check("pilots hidden while they wait in the crew room", not capVisible())
	T = ls("out", K) + out.phases.boarding.t1 - 1; frame(0.3)
	check("seated pilot visible", capVisible())
	check("captain seated in the cockpit", (capRoot.Position - (stand * seatCap).Position).Magnitude < 0.05, (capRoot.Position - (stand * seatCap).Position).Magnitude)
	local gatePrompt = game.Workspace.ShuttleGates.GateBoardHome.BoardPrompt
	owner.Character:PivotTo(CFrame.new(FP.HOME_GATES[1].X, 27.5, FP.HOME_GATES[1].Z + 3))
	check("board prompt stays enabled under WorldController", gatePrompt.Enabled == true)
	M.fire(PPS.PromptTriggered, gatePrompt, owner); M.settle(0.5)
	check("board prompt boards (server)", lastCall("TravelAction").payload.action == "board" and owner:GetAttribute("ShuttleLeg") == "out:" .. K)
	check("ride view opened, pass closed", playerGui:FindFirstChild("ShuttleRide") ~= nil and playerGui:FindFirstChild("ShuttlePass") == nil and SC.riding() ~= nil)
	frame(0.1)
	check("scriptable camera in the cabin", camera.CameraType == Enum.CameraType.Scriptable and (camera.CFrame.Position - stand.Position).Magnitude < 60)
	check("cabin window overlay visible", playerGui.ShuttleRide.CabinWindow.Visible == true)
	local function nearCamHidden()
		local n = 0
		for _, d in plane():GetDescendants() do if d:IsA("BasePart") and (d.Name == "Window" or d.Name == "Outline") and d.LocalTransparencyModifier == 1 then n += 1 end end
		return n
	end
	check("window seat: the thin window / outline plates at the camera hidden locally", nearCamHidden() >= 1, nearCamHidden())
	local btn = playerGui.ShuttleRide:FindFirstChild("ViewButton", true)
	M.fire(btn.Activated); frame(0.1)
	check("view toggle: cockpit", string.find(btn.Text, "Cockpit", 1, true) ~= nil and playerGui.ShuttleRide.CabinWindow.Visible == false)
	check("cockpit view: window plates shown again", nearCamHidden() == 0)
	check("cockpit view: jump seat camera, FOV 56", camera.FieldOfView == 56)
	local capArm = cap:FindFirstChild("Right Arm"); local foArm = fo:FindFirstChild("Left Arm")
	check("cockpit view: the pilots' inner arms hidden locally (outer arms shown)", capArm.LocalTransparencyModifier == 1 and foArm.LocalTransparencyModifier == 1 and cap:FindFirstChild("Left Arm").LocalTransparencyModifier == 0)
	M.fire(btn.Activated); frame(0.1)
	check("view toggle: outside", string.find(btn.Text, "Outside", 1, true) ~= nil)
	check("outside view: the arms are back", capArm.LocalTransparencyModifier == 0 and foArm.LocalTransparencyModifier == 0)
	M.fire(btn.Activated); frame(0.1)
	check("view toggle: back to the window", string.find(btn.Text, "Window", 1, true) ~= nil)

	------------------------------------------------------------------ flight
	T = ls("out", K) + out.phases.doors.t0 + 1; City.tick(0.1); frame(0.1)
	local Ground = M.require(Client.Controllers.ShuttleGround)
	local cabFloor
	for _, p in Ground.bridgeParts() do if p.Name == "CabFloor" then cabFloor = p end end
	local cab0 = cabFloor and cabFloor.Position
	T = ls("out", K) + out.phases.doors.t1 - 0.1; City.tick(0.1); frame(0.1)
	check("jet bridge retracts while the doors close", cabFloor ~= nil and (cabFloor.Position - cab0).Magnitude > 2, cabFloor and (cabFloor.Position - cab0).Magnitude)
	local tugBody
	for _, p in Ground.homeTugParts() do if p.Name == "Body" then tugBody = p end end
	local tug0 = tugBody and tugBody.Position
	T = ls("out", K) + out.phases.pushback.t0 + 0.5; City.tick(0.1); frame(0.1)
	check("captain's announcement at pushback", toastHas("This is your captain") and toastHas(FP.CONFIG.flights.out))
	T = ls("out", K) + out.phases.pushback.t0 + 6; frame(0.1)
	local pushPose = FP.pose(T)
	local noseGear = (pushPose.cf * CFrame.new(0, 0, Aircraft.points(FP.CONFIG.kind, FP.CONFIG.scale).noseGearZ)).Position
	check("the stand's tug pushes the aircraft (moved, at the nose gear)", tugBody ~= nil and (tugBody.Position - tug0).Magnitude > 5 and (Vector3.new(tugBody.Position.X, 0, tugBody.Position.Z) - Vector3.new(noseGear.X, 0, noseGear.Z)).Magnitude < 14, tugBody and (tugBody.Position - tug0).Magnitude)
	local movingSolid = 0
	for _, d in plane():GetDescendants() do if d:IsA("BasePart") and d.CanCollide then movingSolid += 1 end end
	check("moving shuttle never collides (nobody gets trapped inside)", movingSolid == 0, movingSolid)
	T = ls("out", K) + out.phases.taxi.t0 + FP.TUG.home + 1; frame(0.1)
	check("tug back in its parking spot after the pushback", tugBody and (tugBody.Position - tug0).Magnitude < 0.01)
	local cr = out.phases.cruise
	T = ls("out", K) + (cr.t0 + cr.t1) / 2; City.tick(0.1); frame(0.3)
	local pose = FP.pose(T)
	check("aircraft follows the shared flight path", (plane().PrimaryPart.Position - pose.cf.Position).Magnitude < 0.01 and pose.altitude > 300)
	check("camera rides along", (camera.CFrame.Position - pose.cf.Position).Magnitude < 40)
	local gearShown = 0
	for _, d in plane():GetDescendants() do if d:IsA("BasePart") and d:GetAttribute("Gear") and d.Transparency < 1 then gearShown += 1 end end
	check("gear retracted in the cruise", gearShown == 0, gearShown)
	check("pilots fly along in the cockpit", (capRoot.Position - (pose.cf * seatCap).Position).Magnitude < 0.05)
	local info = playerGui.ShuttleRide:FindFirstChild("FlightInfo", true)
	local infoText = info and info:FindFirstChildWhichIsA("TextLabel")
	check("flight info panel", infoText and string.find(infoText.Text, "Cruising", 1, true) ~= nil and string.find(infoText.Text, "arrival in", 1, true) ~= nil, infoText and infoText.Text)
	T = ls("out", K) + out.phases.approach.t0 + 0.5; City.tick(0.1); frame(0.1)
	check("approach announcement", toastHas("prepare for landing"))
	T = ls("out", K) + out.phases.deboarding.t0 + 0.2; City.tick(0.1); M.settle(1)
	frame(0.1)
	check("arrived: ShuttleLeg cleared, ride closed", owner:GetAttribute("ShuttleLeg") == nil and playerGui:FindFirstChild("ShuttleRide") == nil and SC.riding() == nil)
	check("camera back to the player", camera.CameraType == Enum.CameraType.Custom)
	check("welcome toast", toastHas("Welcome to Port Meridian"))
	check("character in the arrival hall", (owner.root.Position - CityPlan.ABROAD.arrival.Position).Magnitude < 0.01)
	look(FP.PM_STAND.Position); frame(0.3)
	check("airstairs at the Port Meridian stand", client():FindFirstChild("ShuttleAirstairs") ~= nil)
	check("Port Meridian: local pushback tug at the nose", (not FP.PM_APRON) or Ground.pmTug() ~= nil)
	check("arrived field staff walk off at Port Meridian", (not FP.PM_APRON) or (function()
		T = ls("out", K) + out.phases.deboarding.t0 + 5 + 3; frame(0.3)
		for _, d in client():GetChildren() do if string.sub(d.Name, 1, 9) == "Passenger" and d.Head.LocalTransparencyModifier == 0 then return true end end
		return false end)())
	T = ls("back", K) + FP.WALKAROUND_START + FP.WALKAROUND * 0.5; frame(0.3)
	fo = client():FindFirstChild("FirstOfficer") -- the crew clones are rebuilt near the camera
	local foRoot = fo:FindFirstChild("HumanoidRootPart")
	local foSeat = Aircraft.points(FP.CONFIG.kind, FP.CONFIG.scale).firstOfficer
	check("Port Meridian: the first officer's walkaround (outside, at the nose gear)", (foRoot.Position - (FP.PM_STAND * foSeat).Position).Magnitude > 8 and fo.Head.LocalTransparencyModifier == 0 and foRoot.Position.Y < FP.PM_STAND.Y + 5, foRoot.Position)
	T = ls("back", K) + FP.WALKAROUND_START + FP.WALKAROUND + 1; frame(0.3)
	check("... and back in the seat", (foRoot.Position - (FP.PM_STAND * foSeat).Position).Magnitude < 0.05)
	local pmb = Ground.pmBoard()
	check("Port Meridian gate board (studs-sized) shows the return flight", pmb ~= nil and pmb.Size.X.Offset == 0 and string.find(pmb:FindFirstChild("Text", true).Text, "CITY AIRPORT", 1, true) ~= nil)
	if FP.PM_APRON then
		local pmTug = Ground.pmTug()
		local tb = pmTug and pmTug:FindFirstChild("Body"); local tb0 = tb and tb.Position
		T = ls("back", K) + back.phases.pushback.t0 + 4; frame(0.3)
		check("Port Meridian pushback by the local tug", tb ~= nil and (tb.Position - tb0).Magnitude > 4, tb and (tb.Position - tb0).Magnitude)
	end
	T = ls("back", K) + back.phases.climb.t0 + 2; frame(0.3)
	check("airstairs gone once the shuttle left", client():FindFirstChild("ShuttleAirstairs") == nil)

	------------------------------------------------------------------ ambient traffic
	local ev
	for _, e in FP.ambient(K + 1) do if e.kind ~= "sky" then ev = e; break end end
	check("an ambient runway movement exists", ev ~= nil)
	if ev then
		T = ev.t0 + ev.duration * 0.5
		look(Vector3.new(0, 40, 2700))
		AT.step(0.1)
		local tr = game.Workspace:FindFirstChild("AirTraffic")
		local n = 0
		if tr then for _, d in tr:GetChildren() do if d.Name == "TrafficAircraft" then n += 1 end end end
		check("ambient airliner visible during its movement", n >= 1, n)
		local m = tr and tr:FindFirstChild("TrafficAircraft")
		local dist = m and (m.PrimaryPart.Position - camera.CFrame.Position).Magnitude
		check("ambient airliner: distance LOD (full within 600, medium beyond 700), no collision", m and select(2, parts(m)) == 0
			and ((dist < 600 and m:GetAttribute("AircraftLod") == "full") or (dist > 700 and m:GetAttribute("AircraftLod") == "medium") or (dist >= 600 and dist <= 700)), m and (tostring(m:GetAttribute("AircraftLod")) .. " at " .. math.floor(dist)))
		-- the same aircraft parks on remote stand R2 between its landing and its departure
		local park
		for _, e in FP.ambient(K + 1) do if e.kind == "parked" then park = e end end
		if park then
			T = park.t0 + 10
			look(FP.AMBIENT_STAND.Position + Vector3.new(0, 0, -200))
			AT.step(0.1)
			local pm = tr:FindFirstChild("TrafficAircraft")
			check("visiting airliner parked on stand R2 (full LOD near the camera)", pm ~= nil and (pm.PrimaryPart.Position - FP.AMBIENT_STAND.Position).Magnitude < 0.05 and pm:GetAttribute("AircraftLod") == "full")
			table.clear(bulkModels)
			T += 5; AT.step(0.1)
			check("a parked visitor costs no BulkMoveTo", bulkModels[pm] == nil, bulkModels[pm])
		end
		T = ev.t0 + ev.duration + 5
		AT.step(0.1)
		local left = 0
		if tr then for _, d in tr:GetChildren() do if d.Name == "TrafficAircraft" then left += 1 end end end
		check("ambient airliner removed after its movement", left == 0 or AT.liveCount() <= 2, left)
	end

	------------------------------------------------------------------ VIP helicopter
	City.tick(0.1)
	local fold = RS.Shuttle
	check("helicopter available", fold:GetAttribute("HeliAvailable") == true)
	local padA = fold:GetAttribute("HeliFromPad")
	look(padA)
	AT.step(0.1)
	local heli = game.Workspace.AirTraffic:FindFirstChild("VipHelicopter")
	check("helicopter parked on the airport pad", heli ~= nil and (heli.PrimaryPart.Position - padA).Magnitude < 0.01)
	local hp, hsolid = parts(heli)
	check("helicopter is light decoration", hp <= 60 and hsolid == 0, hp)
	local padPrompt
	for _, d in game.Workspace.WorldCity:GetDescendants() do if d:IsA("ProximityPrompt") and d:GetAttribute("CityAction") == "heli" then padPrompt = d end end
	check("local helipad prompt (Public, so WorldController keeps it enabled)", padPrompt ~= nil and padPrompt:GetAttribute("HeliTo") == "hotel" and padPrompt:GetAttribute("Public") == true)
	M.settle(0.2)
	check("helipad prompt stays enabled under WorldController", padPrompt.Enabled == true)
	Shop.passes[owner.UserId] = { limo = true }
	owner.Character:PivotTo(CFrame.new(padA.X + 3, padA.Y + 3, padA.Z + 3))
	M.fire(PPS.PromptTriggered, padPrompt, owner); M.settle(0.5)
	check("helipad prompt books the VIP transfer", lastCall("TravelAction").payload.action == "heli" and lastCall("TravelAction").result.ok == true and toastHas("VIP transfer"))
	local start = fold:GetAttribute("HeliStart")
	local blade
	for _, d in heli:GetDescendants() do if d.Name == "HeliBlade" then blade = d; break end end
	local blade0 = blade.CFrame
	T = start + 15; AT.step(0.1); AT.step(0.1)
	check("helicopter flying the transfer", (heli.PrimaryPart.Position - padA).Magnitude > 20)
	check("rotor turning", (blade.CFrame.Position - blade0.Position).Magnitude > 0.5 or blade.CFrame.LookVector:Dot(blade0.LookVector) < 0.999)
	check("rider camera follows the helicopter", camera.CameraType == Enum.CameraType.Scriptable and (camera.CFrame.Position - heli.PrimaryPart.Position).Magnitude < 80 and playerGui:FindFirstChild("HeliRide") ~= nil)
	local _, r1 = FP.heliTimes("hotel", start, padA, fold:GetAttribute("HeliToPad"))
	T = r1 + 0.2; City.tick(0.1); M.settle(1); AT.step(0.1)
	check("after landing: camera back, in the hotel lobby", camera.CameraType == Enum.CameraType.Custom and playerGui:FindFirstChild("HeliRide") == nil and (owner.root.Position - CityPlan.INTL_HOTEL.lobby.Position).Magnitude < 0.01)

	------------------------------------------------------------------ express flight home from Port Meridian
	local pmCheck
	for _, d in game.Workspace.WorldCity:GetDescendants() do if d:IsA("ProximityPrompt") and d:GetAttribute("FlightTo") == "home" then pmCheck = d; break end end
	local pc = CityPlan.ABROAD.checkin[1]
	owner.Character:PivotTo(CFrame.new(pc.X, 27.5, pc.Z + 6))
	local kb = math.floor((T - FP.CONFIG.epoch) / I)
	T = FP.legStart("back", kb + 1) - FP.CONFIG.charterAfter - 40
	M.fire(PPS.PromptTriggered, pmCheck, owner); M.settle(0.3)
	local cg = playerGui:FindFirstChild("FlightChoice")
	local express
	if cg then for _, d in cg:GetDescendants() do if d:IsA("TextButton") and string.find(d.Text, "Express", 1, true) then express = d end end end
	check("Port Meridian counter: choice offered when the shuttle is far away", cg ~= nil and express ~= nil)
	if express then M.fire(express.Activated); M.settle(25) end
	local fc = lastCall("TravelAction")
	check("express flight = the instant flight (TravelAction flight), home again", fc and fc.payload.action == "flight" and fc.result.ok == true and City.state(owner) ~= "abroad", fc and fc.payload.action)

	------------------------------------------------------------------ shuttle off -> legacy check-in
	Shuttle.setEnabled(false)
	frame(0.1)
	check("shuttle off: client model removed", plane() == nil and SC.active() == false)
end

local ok, err = M.runMain(body, { timeout = 900, maxSteps = 8000000 })
if not ok then failc += 1; print("ERROR " .. tostring(err)) end
print(string.format("flight_client: %d passed, %d failed", pass, failc))
if failc > 0 then error("flight_client failed", 0) end
