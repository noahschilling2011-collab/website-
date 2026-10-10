--!nocheck
-- World package: CityService in the headless mock - flight state machine (check-in distance, vehicle,
-- money, ticket, stream request before the move, anchored hold, release by tick, return flight, cancel +
-- refund, respawn reset, leaving), the REAL PlotService (an office rebuild while abroad must not pull the
-- founder home; a respawn still does), GPS routes, meeting prompt placeholder + handler, no per-tick writes.
-- Real CityService, CityBuilder, CityPlan, EconomyService, PlotService; stubbed Session/Remote (stubs.luau);
-- HeadquartersDesign.build/DoorService/LiftService patched to tiny no-ops (no HQ geometry needed here).
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_world && tools/luau tests/world/test_travel.luau [-a .gen_dir]
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
local function near(a, b, tol) return (a - b).Magnitude <= (tol or 0.01) end

local function body()
	local Instance, Vector3, CFrame = G.Instance, G.Vector3, G.CFrame
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local S = Server.Services
	local F = require("./fixture")(M, G)
	local Remote = M.require(Server.Lib.Remote)
	local Session = M.require(S.SessionService)
	local CityPlan = M.require(RS.Shared.Config.CityPlan)
	-- PlotService runs for real; only the HQ generator and the door/lift registries are replaced
	local Design = M.require(S.HeadquartersDesign)
	local builds = 0
	Design.build = function(cf, session, accent)
		builds += 1
		-- OfficeTier = the plan tier (garage stage: office index - Plan.OFFICE_TIER_OFFSET), like the real generator
		local m = Instance.new("Model"); m.Name = "Office"; m:SetAttribute("OfficeTier", Design.tierFor(session)); m:SetAttribute("OwnerUserId", session.userId)
		return m
	end
	Design.staff = function() end
	local Doors = M.require(S.DoorService); Doors.register = function() end; Doors.unregister = function() end
	local Lift = M.require(S.LiftService); Lift.attach = function() end; Lift.detach = function() end
	local Plot = M.require(S.PlotService)
	local City = M.require(S.CityService)
	Plot.init()
	City.init()
	check("world built under workspace.WorldCity", game.Workspace:FindFirstChild("WorldCity") ~= nil)
	local act = Remote.binds.TravelAction
	check("TravelAction bound with a rate limit", act ~= nil and Remote.limits.TravelAction.burst > 0 and Remote.limits.TravelAction.perSecond > 0)

	local TICKET = CityPlan.TRAVEL.ticket
	local SECONDS = CityPlan.TRAVEL.flightSeconds
	local counter = CityPlan.AIRPORT.checkin[2]
	local atCounter = CFrame.new(counter.X, 27.5, counter.Z - 6)
	local abroadCounter = CityPlan.ABROAD.checkin[1]
	local atAbroadCounter = CFrame.new(abroadCounter.X, 27.5, abroadCounter.Z + 6)
	local p = F.player(4242, "Founder", CFrame.new(0, 27.5, 0))
	local s = F.session(p, 500)
	table.insert(Session.sessions, s)
	for _, fn in Session.loaded do fn(s) end -- PlotService.claim + CityService reset
	M.settle(1)
	local plot = Plot.get(p)
	check("plot claimed for the founder", plot ~= nil and plot.office ~= nil)
	local home = Plot.arrival(plot)
	check("claim sent the founder to the plaza (positive control for sendHome)", near(p.root.Position, home.Position, 0.01), tostring(p.root.Position))
	local function call(payload) return act(s, payload) end
	local function money() return s.data.money end

	------------------------------------------------------------------ refusals
	local st = call({ action = "status" })
	check("status: home, ticket from config", st.ok and st.state == "home" and st.ticket == TICKET and st.seconds == SECONDS)
	local r = call({ action = "flight", to = "abroad" })
	check("flight from the campus refused: not at a check-in counter", r.ok == false and r.err == "NOT_AT_CHECKIN", r.err)
	check("bad destination refused", call({ action = "flight", to = "mars" }).err == "BAD_INPUT")
	check("flight home while at home refused", call({ action = "flight", to = "home" }).err == "NOT_ABROAD")
	check("unknown action refused", call({ action = "teleport" }).err == "BAD_INPUT")
	p.Character:PivotTo(atCounter)
	local seat = Instance.new("Seat"); seat.Parent = game.Workspace
	-- the mock's Humanoid.SeatPart is always nil: read it from the instance state for this test
	local seatGetter = function(self) return self[M.KEY].props.SeatPart end
	M.IMPL.Humanoid.get.SeatPart = seatGetter; M.classInfo("Humanoid").get.SeatPart = seatGetter
	p.humanoid[M.KEY].props.SeatPart = seat
	check("seated players must leave their seat", call({ action = "flight", to = "abroad" }).err == "LEAVE_VEHICLE")
	p.humanoid[M.KEY].props.SeatPart = nil
	r = call({ action = "flight", to = "abroad" })
	check("not enough money: NO_MONEY, nothing spent, still home", r.err == "NO_MONEY" and money() == 500 and City.state(p) == "home" and p:GetAttribute("TravelState") == nil, r.err)
	check("no stream request without a ticket", #p.streamed == 0)

	------------------------------------------------------------------ outbound flight
	s.data.money = TICKET + 1000
	local cost0 = s.data.stats.totalCost
	r = call({ action = "flight", to = "abroad" })
	check("flight abroad accepted", r.ok == true and r.to == "abroad" and r.seconds == SECONDS and r.price == TICKET, r.err)
	check("ticket paid through Economy.spend", money() == 1000 and s.data.stats.totalCost == cost0 + TICKET, money())
	check("arrival area streamed to the player first", #p.streamed == 1 and near(p.streamed[1].pos, CityPlan.ABROAD.arrival.Position) and p.streamed[1].timeout == CityPlan.TRAVEL.streamTimeout)
	check("character moved to the Port Meridian arrival hall", near(p.root.Position, CityPlan.ABROAD.arrival.Position, 0.01), tostring(p.root.Position))
	check("state flying (attribute replicated)", City.state(p) == "flying" and p:GetAttribute("TravelState") == "flying" and City.isAway(p))
	check("character held (root anchored) during the cutscene", p.root.Anchored == true)
	check("second flight while boarding refused", call({ action = "flight", to = "abroad" }).err == "BUSY")
	City.tick(SECONDS - 0.2)
	check("still flying before the cutscene ends", City.state(p) == "flying" and p.root.Anchored == true)
	City.tick(0.3)
	check("released after the cutscene: abroad, root free", City.state(p) == "abroad" and p:GetAttribute("TravelState") == "abroad" and p.root.Anchored == false)
	check("flight abroad again refused", call({ action = "flight", to = "abroad" }).err == "ALREADY_ABROAD")
	local writes = p.attrWrites
	for _ = 1, 200 do City.tick(0.05) end
	check("no attribute writes while nothing changes (200 ticks)", p.attrWrites == writes, p.attrWrites - writes)

	------------------------------------------------------------------ rebuild while abroad (real PlotService)
	local beforeBuilds = builds
	s.data.empire.office = (s.data.empire.office or 1) + 1
	Plot.refresh(s)
	M.settle(1)
	check("office rebuilt", builds == beforeBuilds + 1 and plot.office:GetAttribute("OfficeTier") == Design.tierFor(s), builds - beforeBuilds)
	check("rebuild did NOT pull the founder home from abroad", near(p.root.Position, CityPlan.ABROAD.arrival.Position, 0.01), tostring(p.root.Position))
	check("still abroad after the rebuild", City.state(p) == "abroad")

	------------------------------------------------------------------ routes
	local rt = call({ action = "route", to = "byteworks" })
	check("abroad: a downtown route needs a flight", rt.ok == false and rt.err == "FLIGHT_REQUIRED", rt.err)
	rt = call({ action = "route", to = "intl_hotel" })
	check("abroad: walking guide to the hotel", rt.ok == true and #rt.points == 2 and rt.name == "Meridian Grand Hotel")
	check("route to an unknown place refused", call({ action = "route", to = "atlantis" }).err == "BAD_INPUT")
	check("route with a bad id type refused", call({ action = "route", to = 5 }).err == "BAD_INPUT")

	------------------------------------------------------------------ return flight
	r = call({ action = "flight", to = "home" })
	check("return flight refused away from the Port Meridian counter", r.err == "NOT_AT_CHECKIN")
	p.Character:PivotTo(atAbroadCounter)
	local m0 = money()
	r = call({ action = "flight", to = "home" })
	check("return flight accepted, included in the ticket", r.ok == true and r.price == 0 and money() == m0, r.err)
	check("home arrivals streamed before the move", #p.streamed == 2 and near(p.streamed[2].pos, CityPlan.AIRPORT.arrival.Position))
	check("character moved to the home arrivals hall", near(p.root.Position, CityPlan.AIRPORT.arrival.Position, 0.01))
	City.tick(SECONDS + 0.1)
	check("home again: state cleared", City.state(p) == "home" and p:GetAttribute("TravelState") == nil and not City.isAway(p) and p.root.Anchored == false)
	-- GPS home from the arrival hall: ends at the plot's garage barrier, all segments drivable
	rt = call({ action = "route", to = "home" })
	local okSeg = rt.ok == true
	if okSeg then
		for i = 2, #rt.points do
			local a, b = rt.points[i - 1], rt.points[i]
			for t = 0, 1, 0.02 do if not CityPlan.drivable(a:Lerp(b, t)) then okSeg = false end end
		end
	end
	local info = CityPlan.plots()[plot.index]
	check("GPS home: route to the plot barrier, drivable", okSeg and near(rt.points[#rt.points], info.gate, 0.6) and rt.length > 1000, rt.err)
	rt = call({ action = "route", to = "airport" })
	check("GPS to the airport from its own hall", rt.ok == true and rt.name == "City Airport")

	------------------------------------------------------------------ cancel + refund, respawn, leaving
	p.Character:PivotTo(atCounter)
	s.data.money = TICKET
	local costC = s.data.stats.totalCost
	p.streamHook = function(self) self.streamHook = nil; F.respawn(self, CFrame.new(0, 27.5, 0)) end -- player resets while streaming
	r = call({ action = "flight", to = "abroad" })
	check("respawn during the stream request cancels the flight", r.ok == false and r.err == "CANCELLED", r.err)
	check("cancelled flight refunded (money and cost stats)", money() == TICKET and s.data.stats.totalCost == costC)
	check("cancelled flight leaves the player at home", City.state(p) == "home" and p:GetAttribute("TravelState") == nil)
	M.settle(1)
	p.Character:PivotTo(atCounter)
	r = call({ action = "flight", to = "abroad" })
	check("flight again after the cancel", r.ok == true and money() == 0)
	City.tick(SECONDS + 0.1)
	check("abroad", City.state(p) == "abroad")
	F.respawn(p, CFrame.new(0, 27.5, 0))
	check("respawn while abroad resets to home at once", City.state(p) == "home" and p:GetAttribute("TravelState") == nil)
	M.settle(1)
	check("respawned character sent to the plaza by PlotService", near(p.root.Position, Plot.arrival(plot).Position, 0.01), tostring(p.root.Position))
	-- the stream API may throw (e.g. not available): the flight still happens
	s.data.money = TICKET
	p.Character:PivotTo(atCounter)
	local rawStream = p.RequestStreamAroundAsync
	p.RequestStreamAroundAsync = function() error("stream unavailable") end
	r = call({ action = "flight", to = "abroad" })
	check("stream request errors are caught (flight continues)", r.ok == true and near(p.root.Position, CityPlan.ABROAD.arrival.Position, 0.01), r.err)
	p.RequestStreamAroundAsync = rawStream
	for _, fn in Session.closing do fn(s) end
	check("leaving clears the trip", City.trips[p.UserId] == nil)

	------------------------------------------------------------------ meeting prompts
	local prompt
	for _, d in game.Workspace.WorldCity:GetDescendants() do
		if d:IsA("ProximityPrompt") and d:GetAttribute("CityAction") == "meeting" and d:GetAttribute("ClientId") == "byteworks" then prompt = d end
	end
	check("ByteWorks meeting prompt exists", prompt ~= nil and prompt.ActionText == "Start meeting" and prompt:GetAttribute("Public") == true)
	local PPS = game:GetService("ProximityPromptService")
	table.clear(Remote.fired)
	p.Character:PivotTo(CFrame.new(0, 27.5, 0))
	M.fire(PPS.PromptTriggered, prompt, p); M.settle(0.1)
	check("meeting prompt from far away ignored", #Remote.fired == 0)
	p.Character:PivotTo(prompt.Parent.CFrame * CFrame.new(0, 0, -6))
	M.fire(PPS.PromptTriggered, prompt, p); M.settle(0.1)
	local n = Remote.fired[1]
	check("placeholder notice without a meeting handler", n ~= nil and n.name == "Notify" and n.args[1] == "CAMPUS_NOTICE" and string.find(n.args[2].text, "ByteWorks", 1, true) ~= nil, n and n.args[2] and n.args[2].text)
	local got
	City.setMeetingHandler(function(player, clientId, q) got = { player, clientId, q } end)
	G.task.wait(1.2) -- prompt cooldown (virtual time)
	M.fire(PPS.PromptTriggered, prompt, p); M.settle(0.1)
	check("registered meeting handler gets player + ClientId", got ~= nil and got[1] == p and got[2] == "byteworks" and got[3] == prompt)
	table.clear(Remote.fired)
	City.guide(p, "airport")
	check("City.guide asks the client to draw a route", Remote.fired[1] and Remote.fired[1].args[1] == "TRAVEL_GUIDE" and Remote.fired[1].args[2].to == "airport")
end

local ok, err = M.runMain(body, { timeout = 600, maxSteps = 5000000 })
if not ok then failc += 1; print("ERROR " .. tostring(err)) end
print(string.format("world_travel: %d passed, %d failed", pass, failc))
if failc > 0 then error("world_travel failed", 0) end
