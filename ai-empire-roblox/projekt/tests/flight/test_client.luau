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
	patch("Workspace", "BulkMoveTo", function(self, parts, cframes) bulkCalls += 1; for i, p in parts do p.CFrame = cframes[i] end end)
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

	------------------------------------------------------------------ check-in + boarding pass
	local checkin
	for _, d in game.Workspace.WorldCity:GetDescendants() do if d:IsA("ProximityPrompt") and d:GetAttribute("FlightTo") == "abroad" then checkin = d; break end end
	check("check-in prompt exists", checkin ~= nil)
	owner.Character:PivotTo(CFrame.new(0, 27.5, 0))
	M.fire(PPS.PromptTriggered, checkin, owner); M.settle(0.5)
	check("check-in far from the counter refused (toast)", toastHas("check-in counter") and playerGui:FindFirstChild("ShuttlePass") == nil)
	owner.Character:PivotTo(CFrame.new(counter.X, 27.5, counter.Z - 6))
	local money0 = s.data.money
	M.fire(PPS.PromptTriggered, checkin, owner); M.settle(0.5)
	local c = lastCall("TravelAction")
	check("check-in buys a shuttle ticket (not the instant flight)", c and c.payload.action == "ticket" and c.result.ok == true and s.data.money == money0 - CityPlan.TRAVEL.ticket)
	check("no cutscene", game.Workspace:FindFirstChild("FlightCutscene") == nil)
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
	local board
	for _, d in playerGui:GetChildren() do if d.Name == "ShuttleGateBoard" then local l = d:FindFirstChild("Text", true); if l and string.find(l.Text, "PORT MERIDIAN", 1, true) then board = l end end end
	check("gate board shows the live status", board ~= nil and string.find(board.Text, "BOARDING", 1, true) ~= nil, board and board.Text)
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
	local btn = playerGui.ShuttleRide:FindFirstChild("ViewButton", true)
	M.fire(btn.Activated); frame(0.1)
	check("view toggle: cockpit", string.find(btn.Text, "Cockpit", 1, true) ~= nil and playerGui.ShuttleRide.CabinWindow.Visible == false)
	M.fire(btn.Activated); frame(0.1)
	check("view toggle: outside", string.find(btn.Text, "Outside", 1, true) ~= nil)
	M.fire(btn.Activated); frame(0.1)
	check("view toggle: back to the window", string.find(btn.Text, "Window", 1, true) ~= nil)

	------------------------------------------------------------------ flight
	T = ls("out", K) + out.phases.doors.t0 + 1; City.tick(0.1); frame(0.1)
	T = ls("out", K) + out.phases.pushback.t0 + 0.5; City.tick(0.1); frame(0.1)
	check("captain's announcement at pushback", toastHas("This is your captain") and toastHas(FP.CONFIG.flights.out))
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
		check("ambient airliner is light (medium LOD, no collision)", m and m:GetAttribute("AircraftLod") == "medium" and select(2, parts(m)) == 0)
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

	------------------------------------------------------------------ shuttle off -> legacy check-in
	Shuttle.setEnabled(false)
	frame(0.1)
	check("shuttle off: client model removed", plane() == nil and SC.active() == false)
end

local ok, err = M.runMain(body, { timeout = 900, maxSteps = 8000000 })
if not ok then failc += 1; print("ERROR " .. tostring(err)) end
print(string.format("flight_client: %d passed, %d failed", pass, failc))
if failc > 0 then error("flight_client failed", 0) end
