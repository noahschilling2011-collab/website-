--!nocheck
-- guiprev scene of the itinerary package: the founder's banner (ItineraryController), the drivers' ride panel, the HUD,
-- the phone (call sheet with the assistant's booking, calendar with the itinerary items) on the REAL server state
-- machine (ItineraryService + DriverService + ShuttleService + CityService + PhoneService, tests/itinerary/common.luau).
--   python3 tools/guiprev/guiprev.py --scene tests/itinerary/scene_trip.luau --gen harness/.gen_itinerary --no-manifest \
--       --state airport --viewport phone --dpr 2 --out out/itinerary/phone_airport.png
-- states: countdown | offer | call | pickup (the timed pick-up) | airport | deboard | limo | meeting | hotel | return | calendar |
-- collapsed | region
local M = require("../../harness/mock")
local args = { ... }
local GEN = args[1] or "../../harness/.gen_itinerary"
local STATE = args[2] or "airport"
local VW, VH = tonumber(args[3]) or 1280, tonumber(args[4]) or 720
local insetList = string.split(args[5] or "58,0,0,0", ",")
local INSETS = { top = tonumber(insetList[1]) or 0, right = tonumber(insetList[2]) or 0, bottom = tonumber(insetList[3]) or 0, left = tonumber(insetList[4]) or 0 }
local FEEDBACK = if args[6] and args[6] ~= "-" then require(args[6]) else nil
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
-- only the session / shop doubles: the real Remote module carries Notify to the client
for path, src in require("../world/stubs") do
	if not string.find(path, "Lib/Remote", 1, true) then sources[path] = src end
end
M.loadTree(manifest, sources)
M.quiet = true
local Common = require("./common")
local GuiDump = require("../../tools/guiprev/guidump")

local function body()
	local G = M.G
	local Vector3, CFrame = G.Vector3, G.CFrame
	local X = Common(M, G, { realRemote = true })
	local p, s = X.newPlayer(4242, "Founder", 4)
	s.data.company.name = "Nimbus Labs"
	if STATE == "countdown" then s.data.empire.prefs.autoTrips = true end
	local playerGui = X.clientSetup(p, s, { w = VW, h = VH, insets = INSETS })
	-- the rest of the client the player sees: HUD column, the drivers' ride panel, the phone
	local Client = M.game.StarterPlayer.StarterPlayerScripts.Client
	local okHud, HUD = pcall(M.require, Client.UI.Screens.HUD)
	if okHud then pcall(HUD.mount, X.hudLayer, false, function() end) end
	X.Phone.init()
	local Computer = M.require(Client.UI.Screens.Computer)
	local PhoneCtl = M.require(Client.Controllers.PhoneController)
	PhoneCtl.init()
	local Phone = M.require(Client.UI.Screens.Phone)
	local okDrive, Drive = pcall(M.require, Client.Controllers.DriveController)
	if okDrive then
		Drive.DIRECT = true
		pcall(Drive.init)
		if Drive._setRoot then pcall(Drive._setRoot, X.RS:FindFirstChild("CompanyDrivers"), M.game.Workspace:FindFirstChild("DriveCars")) end
	end
	local stateEvent = X.RS.Remotes:FindFirstChild("State")
	local function push()
		M.fire(stateEvent.OnClientEvent, { saveEnabled = false, serverTime = X.T, data = s.data, live = s.live })
		M.settle(0.1)
	end
	push()
	if okHud then pcall(HUD.setHidden, false) end
	GuiDump.setViewport(playerGui, VW, VH, INSETS)
	X.advance(1.5)
	X.standAt(p, X.hqPoint(p, Vector3.new(0, 3, -60)))
	if STATE == "timed" then
		-- the trip starts right after a boarding closed: the car is called later (timed pick-up, no wait at the gate)
		local _, ls, _, be = X.FP.nextLeg("out", X.T)
		X.advance(math.max(0, be - X.T) + 6, 0.5)
		local _ = ls
	end
	local client = if STATE == "region" then "creative" else "helix"
	if STATE == "region" then s.data.empire.office = 3 end
	X.addTrip(s, client)
	X.advance(if STATE == "countdown" then 6 else 3)
	local function accept()
		local calls = X.Phone.calls(s)
		local id = calls[1] and calls[1].id
		if id then X.Phone._act(s, { action = "call", id = id, answer = "accept" }) end
	end
	local function waitCar() return X.waitFor(function() local rf = X.rideFolder(p); return rf ~= nil and rf:GetAttribute("State") == "waiting" end, 240) end
	local function st() return X.state(p) end
	if STATE == "offer" then
		-- the call was not answered: the banner keeps the offer (the call is in the log as missed)
		X.advance(27)
		Phone.hideBanner()
	elseif STATE == "call" then
		PhoneCtl.open("call", X.Phone.calls(s)[1].id)
	elseif STATE == "pickup" or STATE == "region" or STATE == "timed" then
		accept()
		X.advance(8)
		Phone.hideBanner()
	elseif STATE == "calendar" then
		accept()
		X.advance(4)
		Phone.hideBanner()
		PhoneCtl.open("calendar")
	elseif STATE ~= "countdown" then
		accept()
		Phone.hideBanner()
		-- a timed pick-up: the player taps "Call car now" (the scene does not wait minutes for it)
		if st().sub == "scheduled" then X.act(s, { action = "retry" }) end
		waitCar()
		X.boardCar(p, s)
		X.waitFor(function() return st().state == "airport" end, 300)
		X.standAt(p, X.FP.HOME_GATES[1] + Vector3.new(6, 0, -14))
		X.advance(2)
		if STATE ~= "airport" and STATE ~= "collapsed" then
			X.standAt(p, X.FP.HOME_GATES[1] + Vector3.new(2, 0, 3))
			X.waitFor(function() return st().state == "limo" end, 900)
			X.advance(1)
			-- deboard: the colleagues walk off the shuttle first; then the limousine is called
			if STATE ~= "deboard" then X.advance(X.IM.DEBOARD_WAIT + 2) end
			if STATE ~= "limo" and STATE ~= "deboard" then
				waitCar()
				X.boardCar(p, s)
				X.waitFor(function() return st().state == "meeting" end, 300)
				X.advance(5)
				if STATE ~= "meeting" then
					local q = X.meetingPrompt(X.IM.officeId("Helix Research"))
					X.standAt(p, q.Parent.Position + Vector3.new(0, 0, -4))
					X.firePrompt(q, p)
					X.waitFor(function() return st().state == "hotel" end, 60)
					X.standAt(p, X.Drive.clientPlace("Helix Research").door.Position)
					waitCar()
					X.boardCar(p, s)
					X.waitFor(function() return st().sub == "arrived" end, 300)
					X.advance(2)
					if STATE == "return" then
						X.act(s, { action = "leave" })
						X.advance(1)
					end
				end
			end
		end
		if STATE == "collapsed" then X.Ctl._apply(X.lastView(p)); X.frame(0.3) end
	end
	push()
	if STATE == "collapsed" then
		local gui = playerGui:FindFirstChild("ItineraryBanner")
		local btn = gui and gui:FindFirstChild("Collapse", true)
		if btn then M.fire(btn.Activated) end
	end
	local RunService = M.game:GetService("RunService")
	for _ = 1, 20 do
		M.fire(RunService.RenderStepped, 1 / 60)
		M.fire(RunService.Heartbeat, 1 / 60)
	end
	X.frame(0.5)
	GuiDump.setViewport(playerGui, VW, VH, INSETS)
	local n = GuiDump.applyFeedback({ playerGui }, FEEDBACK)
	M.settle(0.2)
	for _ = 1, 15 do
		M.fire(RunService.RenderStepped, 1 / 60)
		M.fire(RunService.Heartbeat, 1 / 60)
	end
	X.frame(0.5)
	local v = X.lastView(p)
	print("@@INFO state=" .. tostring(v and v.state) .. " title=" .. tostring(v and v.title) .. " line=" .. tostring(v and v.line))
	GuiDump.dump({ playerGui }, { scene = "itinerary", state = STATE, viewport = { VW, VH }, insets = INSETS, feedbackChanged = n })
end

setfenv(body, M.envFor(nil))
local ok, res, status = M.runMain(body, { timeout = 6000, maxSteps = 40000000 })
if not ok then print("@@ERROR body crashed (" .. tostring(status) .. "): " .. tostring(res)) end
if M.stats.errors > 0 then print("@@ERROR background thread errors: " .. M.stats.errors) end
