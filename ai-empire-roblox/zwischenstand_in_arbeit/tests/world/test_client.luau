--!nocheck
-- World package client smoke test (headless mock): the real TravelController wired to the real CityService
-- through a patched RemoteFunction:InvokeServer and the Notify event. Check-in prompt -> fade -> flight ->
-- client cutscene (scene built, camera scripted, restored) -> arrival; error toast; GPS guide drawn from a
-- real route (dashes + beacon, nothing inside campus plots, all local parts non-colliding), arrival clears
-- it, Notify TRAVEL_GUIDE, kiosk prompt, GPS panel only while driving the own car.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_world && tools/luau tests/world/test_client.luau [-a .gen_dir]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_world")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
for path, src in require("./stubs") do sources[path] = src end
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
	local F = require("./fixture")(M, G)
	local Net = M.require(RS.Shared.Net)
	local Remote = M.require(Server.Lib.Remote)
	local Session = M.require(S.SessionService)
	local CityPlan = M.require(RS.Shared.Config.CityPlan)
	local Design = M.require(S.HeadquartersDesign); Design.build = function() local m = Instance.new("Model"); m.Name = "Office"; return m end; Design.staff = function() end
	local Plot = M.require(S.PlotService)
	Plot.get = function(player) return { index = 3, cframe = CityPlan.plots()[3].cframe, owner = player } end
	local City = M.require(S.CityService)
	City.init()
	-- local player
	local counter = CityPlan.AIRPORT.checkin[1]
	local owner = F.player(9001, "Pilot", CFrame.new(counter.X, 27.5, counter.Z - 6))
	local s = F.session(owner, 100000)
	table.insert(Session.sessions, s)
	for _, fn in Session.loaded do fn(s) end
	local playerGui = Instance.new("Folder"); playerGui.Name = "PlayerGui"
	owner.WaitForChild = function(_, name) if name == "PlayerGui" then return playerGui end end
	local changed = M.newSignal("TravelStateChanged")
	owner.GetAttributeChangedSignal = function() return changed end
	local rawSet = owner.SetAttribute
	owner.SetAttribute = function(self, k, v) rawSet(self, k, v); if k == "TravelState" then M.fire(changed) end end
	M.IMPL.Players.get.LocalPlayer = function() return owner end; M.classInfo("Players").get.LocalPlayer = function() return owner end
	-- remotes
	local folder = Instance.new("Folder"); folder.Name = Net.FOLDER
	for _, name in Net.FUNCTIONS do local f = Instance.new("RemoteFunction"); f.Name = name; f.Parent = folder end
	for _, name in Net.EVENTS do local e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = folder end
	folder.Parent = RS
	local calls = {}
	local function patch(cls, name, fn) M.IMPL[cls].methods[name] = fn; M.classInfo(cls).methods[name] = fn end
	patch("RemoteFunction", "InvokeServer", function(self, payload)
		table.insert(calls, { name = self.Name, payload = payload })
		if self.Name == "RequestState" then return { ok = true, state = { saveEnabled = false, serverTime = 1.7e9, data = s.data, live = s.live } } end
		local handler = Remote.binds[self.Name]
		if not handler then return { ok = false, err = "BAD_INPUT" } end
		local result = handler(s, payload or {})
		calls[#calls].result = result
		return result
	end)
	local notifyEvent = folder:FindFirstChild("Notify")
	local rawFire = Remote.fire
	Remote.fire = function(player, name, ...)
		rawFire(player, name, ...)
		if player == owner and name == "Notify" then M.fire(notifyEvent.OnClientEvent, ...) end
	end
	local UIRoot = M.require(Client.UI.UIRoot)
	local Toast = M.require(Client.UI.Toast)
	local State = M.require(Client.Controllers.StateController)
	local Travel = M.require(Client.Controllers.TravelController)
	local hud, dim, overlay, intro, top = UIRoot.init()
	Toast.mount(top)
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

	------------------------------------------------------------------ GPS guide
	local guide = function() return game.Workspace:FindFirstChild("TravelGuide") end
	Travel.guide("byteworks"); M.settle(0.2)
	local c = lastCall("TravelAction")
	check("guide asks the server for a route", c ~= nil and c.payload.action == "route" and c.payload.to == "byteworks" and c.result.ok == true)
	local g = guide()
	local dashes, beacon, bad = 0, nil, 0
	if g then
		for _, d in g:GetDescendants() do
			if d:IsA("BasePart") then
				if d.Name == "GuideDash" then dashes += 1 elseif d.Name == "GuideBeacon" then beacon = d end
				if d.CanCollide or d.CanQuery or d.CanTouch or not d.Anchored then bad += 1 end
			end
		end
	end
	check("route drawn: dashes + beacon", g ~= nil and dashes > 50 and beacon ~= nil and beacon:FindFirstChildWhichIsA("BillboardGui") ~= nil, dashes)
	check("guide parts are local decoration (no collision/query/touch, anchored)", bad == 0, bad)
	check("toast names the destination", toastHas("Route to ByteWorks"))
	-- arrival clears it
	owner.Character:PivotTo(CFrame.new(c.result.points[#c.result.points] + Vector3.new(0, 3, 0)))
	G.task.wait(1)
	check("arriving clears the guide", guide() == nil and toastHas("You have arrived at ByteWorks"))
	-- from a garage: nothing drawn inside the campus plot
	local p3 = CityPlan.plots()[3]
	owner.Character:PivotTo(p3.cframe * CFrame.new(100, -12, 2))
	Travel.guide("airport"); M.settle(0.2)
	g = guide()
	local inPlot = 0
	if g then for _, d in g:GetChildren() do if d.Name == "GuideDash" and CityPlan.plotAt(d.Position) then inPlot += 1 end end end
	check("route from the garage drawn, no dashes inside the plot", g ~= nil and inPlot == 0, inPlot)
	Travel.clear()
	check("clear() removes the guide", guide() == nil)
	-- server-initiated guide (appointments) and a kiosk prompt
	City.guide(owner, "city_hotel"); M.settle(0.3)
	check("Notify TRAVEL_GUIDE draws a guide", guide() ~= nil and lastCall("TravelAction").payload.to == "city_hotel")
	local kiosk
	for _, d in game.Workspace.WorldCity:GetDescendants() do if d:IsA("ProximityPrompt") and d:GetAttribute("CityAction") == "navigate" and d:GetAttribute("To") == "airport" then kiosk = d end end
	M.fire(PPS.PromptTriggered, kiosk, owner); M.settle(0.3)
	check("navigate prompt (plaza map board) requests the airport route", kiosk ~= nil and lastCall("TravelAction").payload.to == "airport")
	local others = { UserId = 5 }
	local n0 = #calls
	M.fire(PPS.PromptTriggered, kiosk, others); M.settle(0.2)
	check("prompts of other players are ignored", #calls == n0)

	------------------------------------------------------------------ flight
	-- the scheduled shuttle (flight package) replaced the cutscene; this section covers the fallback path
	-- (design/requests/flight.md #1; the shuttle client flow has its own suite: tests/flight)
	M.require(S.ShuttleService).setEnabled(false)
	local checkin
	for _, d in game.Workspace.WorldCity:GetDescendants() do if d:IsA("ProximityPrompt") and d:GetAttribute("FlightTo") == "abroad" then checkin = d; break end end
	owner.Character:PivotTo(CFrame.new(0, 27.5, 0)) -- away from the counters
	M.fire(PPS.PromptTriggered, checkin, owner)
	G.task.wait(3)
	check("flight refused far from the counter: readable toast, screen visible again", toastHas("check-in counter") and playerGui:FindFirstChild("TravelOverlay").Frame.BackgroundTransparency == 1)
	owner.Character:PivotTo(CFrame.new(counter.X, 27.5, counter.Z - 6))
	local money0 = s.data.money
	M.fire(PPS.PromptTriggered, checkin, owner)
	G.task.wait(1.5)
	check("cutscene running: client scene built, camera scripted", game.Workspace:FindFirstChild("FlightCutscene") ~= nil and camera.CameraType == Enum.CameraType.Scriptable)
	local plane = game.Workspace:FindFirstChild("FlightCutscene") and game.Workspace.FlightCutscene:FindFirstChild("CutscenePlane")
	local planeParts, planeSolid = 0, 0
	if plane then for _, d in plane:GetDescendants() do if d:IsA("BasePart") then planeParts += 1; if d.CanCollide then planeSolid += 1 end end end end
	-- client-only model; the flight package's AircraftModel "full" LOD is documented at <= ~300 parts
	check("cutscene plane: <= 400 parts (client only), none colliding", plane ~= nil and planeParts <= 400 and planeSolid == 0, planeParts)
	check("flight call sent, ticket paid, character abroad", lastCall("TravelAction").payload.action == "flight" and s.data.money == money0 - CityPlan.TRAVEL.ticket and (owner.root.Position - CityPlan.ABROAD.arrival.Position).Magnitude < 0.01)
	G.task.wait(CityPlan.TRAVEL.flightSeconds + 2)
	City.tick(CityPlan.TRAVEL.flightSeconds + 1)
	check("cutscene ends: scene removed, camera back to Custom", game.Workspace:FindFirstChild("FlightCutscene") == nil and camera.CameraType == Enum.CameraType.Custom)
	check("welcome toast abroad", toastHas("Welcome to Port Meridian"))
	check("screen faded back in", playerGui.TravelOverlay.Frame.BackgroundTransparency == 1)
	check("server state abroad", City.state(owner) == "abroad" and owner:GetAttribute("TravelState") == "abroad")

	------------------------------------------------------------------ GPS panel while driving
	local car = Instance.new("Model"); car:SetAttribute("OwnerUserId", owner.UserId); car.Parent = game.Workspace
	local seat = Instance.new("VehicleSeat"); seat.Parent = car
	local seatGetter = function(self) return self[M.KEY].props.SeatPart end
	M.IMPL.Humanoid.get.SeatPart = seatGetter; M.classInfo("Humanoid").get.SeatPart = seatGetter
	owner.humanoid[M.KEY].props.SeatPart = seat
	G.task.wait(1)
	local panel = playerGui:FindFirstChild("TravelGPS")
	check("GPS panel appears while driving the own car", panel ~= nil)
	local toggle; if panel then for _, d in panel:GetDescendants() do if d:IsA("TextButton") and string.find(d.Text, "GPS", 1, true) then toggle = d end end end
	if toggle then M.fire(toggle.Activated) end
	local hq = false; if panel then for _, d in panel:GetDescendants() do if d:IsA("TextButton") and d.Text == "My HQ" then hq = true end end end
	check("panel lists destinations incl. My HQ", toggle ~= nil and hq)
	owner.humanoid[M.KEY].props.SeatPart = nil
	G.task.wait(1)
	check("panel closes when leaving the car", playerGui:FindFirstChild("TravelGPS") == nil)
	car.Parent = nil
	local foreign = Instance.new("Model"); foreign:SetAttribute("OwnerUserId", 1); foreign.Parent = game.Workspace
	local fseat = Instance.new("VehicleSeat"); fseat.Parent = foreign
	owner.humanoid[M.KEY].props.SeatPart = fseat
	G.task.wait(1)
	check("no panel in someone else's car", playerGui:FindFirstChild("TravelGPS") == nil)
	owner.humanoid[M.KEY].props.SeatPart = nil
end

local ok, err = M.runMain(body, { timeout = 600, maxSteps = 5000000 })
if not ok then failc += 1; print("ERROR " .. tostring(err)) end
print(string.format("world_client: %d passed, %d failed", pass, failc))
if failc > 0 then error("world_client failed", 0) end
