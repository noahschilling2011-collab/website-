--!nocheck
-- Shared setup of the itinerary suites: the REAL server services (ItineraryService, DriverService, JetService,
-- ShuttleService, CityService + the built world, PhoneService, EmpireService, PlotService, CompanyOps) in the mock with
-- a controlled server clock; SessionService / Remote / ShopService are the world test doubles (tests/world/stubs.luau),
-- the HQ generator and doors are stubbed like in tests/drivers. Returns the environment table `X`.
local GuiDumpLib = require("../../tools/guiprev/guidump")
local Fixture = require("../world/fixture")
return function(M, G, opts)
	opts = opts or {}
	local Instance, Vector3, CFrame = G.Instance, G.Vector3, G.CFrame
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local S = Server.Services
	local F = Fixture(M, G)
	local X = { M = M, G = G, F = F, RS = RS, S = S }
	X.Remote = M.require(Server.Lib.Remote)
	X.Session = M.require(S.SessionService)
	X.CityPlan = M.require(RS.Shared.Config.CityPlan)
	X.FP = M.require(RS.Shared.FlightPlan)
	X.Drive = M.require(RS.Shared.DrivePlan)
	X.Ops = M.require(RS.Shared.CompanyOps)
	X.IM = M.require(RS.Shared.ItineraryMath)
	X.PhoneMath = M.require(RS.Shared.PhoneMath)
	X.EmpireMath = M.require(RS.Shared.EmpireMath)
	-- controlled server clock: company time 10:00 (CompanyOps.hour), daytime (drivers at the canopy)
	X.T = opts.start or (1416666 * 1200 + 180)
	local function patch(cls, name, fn) M.IMPL[cls].methods[name] = fn; local ci = M.classInfo(cls); if ci.methods then ci.methods[name] = fn end end
	patch("Workspace", "GetServerTimeNow", function() return X.T end)
	patch("Workspace", "BulkMoveTo", function(self, parts, cframes) for i, p in parts do p.CFrame = cframes[i] end end)
	-- HQ generator + doors stubbed (PlotService runs for real); the stub office carries the garage barrier door
	local Design = M.require(S.HeadquartersDesign)
	Design.build = function(cf, session, accent)
		local m = Instance.new("Model"); m.Name = "Office"
		m:SetAttribute("OfficeTier", Design.tierFor(session)); m:SetAttribute("OwnerUserId", session.userId)
		local door = Instance.new("Model"); door.Name = "Door_SITE_BARRIER"; door:SetAttribute("DoorId", "SITE_BARRIER"); door.Parent = m
		return m
	end
	Design.staff = function() end
	local Doors = M.require(S.DoorService)
	Doors.register = function() end; Doors.unregister = function() end
	Doors.find = function(office, id) return office:FindFirstChild("Door_" .. id) end
	Doors.requestNPC = function() return true end
	local Lift = M.require(S.LiftService); Lift.attach = function() end; Lift.detach = function() end
	-- money flows are recorded (the itinerary must never call them)
	X.Economy = M.require(S.EconomyService)
	X.econCalls = {}
	for _, name in { "spend", "grant", "applyFlow" } do
		local orig = X.Economy[name]
		X.Economy[name] = function(s, ...)
			table.insert(X.econCalls, { fn = name, s = s, args = { ... }, t = X.T, trace = debug.traceback() })
			return orig(s, ...)
		end
	end
	-- opts.realRemote: the real Remote module (client tests / GUI scenes) with the stub's recording API on top; Notify of
	-- the client player is delivered to the client's Notify event
	if opts.realRemote then
		local R = X.Remote
		R.binds, R.fired, R.limits = {}, {}, {}
		local origBind = R.bind
		R.bind = function(name, limits, handler) R.binds[name] = handler; R.limits[name] = limits; origBind(name, limits, handler) end
		R.setup()
		local folder = RS:FindFirstChild("Remotes")
		local notifyEvent = folder:FindFirstChild("Notify")
		R.fire = function(player, name, ...)
			table.insert(R.fired, { player = player, name = name, args = { ... } })
			if name == "Notify" and X.clientPlayer ~= nil and player == X.clientPlayer then M.fire(notifyEvent.OnClientEvent, ...) end
		end
		local function invokeServer(self, payload)
			local handler = R.binds[self.Name]
			if not handler or not X.clientSession then return { ok = false, err = "BAD_INPUT" } end
			return handler(X.clientSession, payload or {})
		end
		M.IMPL.RemoteFunction.methods.InvokeServer = invokeServer
		M.classInfo("RemoteFunction").methods.InvokeServer = invokeServer
	end
	X.Plot = M.require(S.PlotService)
	X.City = M.require(S.CityService)
	X.Shuttle = M.require(S.ShuttleService)
	X.Phone = M.require(S.PhoneService)
	X.Empire = M.require(S.EmpireService)
	X.Jet = M.require(S.JetService)
	X.Driver = M.require(S.DriverService)
	X.Itin = M.require(S.ItineraryService)
	X.Plot.init()
	X.City.init()
	X.Empire.init()
	X.Jet.init()
	X.Driver.init()
	X.Itin.init()
	for k in X.Driver.LIMITS do X.Driver.LIMITS[k] = { 1e6, 1e6 } end
	X.act = X.Remote.binds.TripAction
	X.travel = X.Remote.binds.TravelAction

	function X.advance(seconds, step)
		step = step or 0.25
		local left = seconds
		while left > 1e-9 do
			local d = math.min(step, left)
			X.T += d
			for _, s in X.Session.sessions do
				if s.econ and not s.closed then s.data.empire.seconds += d end
			end
			X.City.tick(d)
			X.Jet.tick(d)
			X.Driver.tick(d)
			X.Itin.tick(d)
			if X.onTick then X.onTick(d) end
			-- spawned server tasks (streaming waits) run on the same clock: the scheduler's virtual time follows
			local target = M.Sched.now + d
			M.Sched.run(target, 200000)
			if M.Sched.now < target then M.Sched.now = target end
			left -= d
		end
	end
	-- advance until cond() is true (or max seconds): returns true when reached
	function X.waitFor(cond, max, step)
		local waited = 0
		while waited < max do
			if cond() then return true end
			X.advance(step or 0.25, step or 0.25)
			waited += step or 0.25
		end
		return cond()
	end
	function X.newPlayer(id, name, stage, cf)
		local p = F.player(id, name, cf or CFrame.new(0, 27.5, 0))
		local s = F.session(p, 500000)
		local e = s.data.empire
		e.office = stage or 4
		e.employees = { researcher = 4, engineer = 4, curator = 2, marketer = 3 }
		X.EmpireMath.syncProfiles(e, id)
		e.seconds = 9000
		e.calendar = { day = 9, index = math.floor(X.T / 1200) }
		s.econ = true -- empire.seconds runs with the clock (play time while online)
		table.insert(X.Session.sessions, s)
		for _, fn in X.Session.loaded do fn(s) end
		return p, s
	end
	-- the local player of the client side (PlayerGui, attribute signals, Players:GetPlayerByUserId)
	function X.clientSetup(p, s, vp)
		local playerGui = Instance.new("Folder"); playerGui.Name = "PlayerGui"
		p.FindFirstChild = function(_, name) if name == "PlayerGui" then return playerGui end end
		p.WaitForChild = function(_, name) if name == "PlayerGui" then return playerGui end end
		p.FindFirstChildOfClass = function() return nil end
		local signals = {}
		local rawSet = p.SetAttribute
		p.GetAttributeChangedSignal = function(_, k) signals[k] = signals[k] or M.newSignal(k); return signals[k] end
		p.SetAttribute = function(self, k, v) rawSet(self, k, v); if signals[k] then M.fire(signals[k]) end end
		M.IMPL.Players.get.LocalPlayer = function() return p end
		M.classInfo("Players").get.LocalPlayer = function() return p end
		local function byId(_, uid)
			for _, ss in X.Session.sessions do if ss.player.UserId == uid then return ss.player end end
			return nil
		end
		M.IMPL.Players.methods.GetPlayerByUserId = byId
		M.classInfo("Players").methods.GetPlayerByUserId = byId
		X.clientPlayer, X.clientSession, X.playerGui = p, s, playerGui
		local Client = game.StarterPlayer.StarterPlayerScripts.Client
		local UIRoot = M.require(Client.UI.UIRoot)
		X.Toast = M.require(Client.UI.Toast)
		X.State = M.require(Client.Controllers.StateController)
		local hud, dim, overlay, intro, top = UIRoot.init()
		if vp then
			local GuiDump = GuiDumpLib
			GuiDump.init(M)
			GuiDump.setViewport(playerGui, vp.w, vp.h, vp.insets)
			X.GuiDump = GuiDump
		end
		X.Toast.mount(top)
		X.hudLayer = hud
		X.Ctl = M.require(Client.Controllers.ItineraryController)
		X.Ctl.init()
		pcall(function() X.State.init() end)
		M.settle(0.3)
		return playerGui
	end
	function X.frame(seconds, step)
		local left = seconds or 0.2
		step = step or 0.1
		while left > 1e-9 do
			local d = math.min(step, left)
			X.Ctl._frame(d)
			left -= d
		end
	end
	function X.close(p, s)
		p.Parent = nil
		s.closed = true
		for _, fn in X.Session.closing do fn(s) end
		local i = table.find(X.Session.sessions, s)
		if i then table.remove(X.Session.sessions, i) end
	end
	function X.hqPoint(p, local3)
		local plot = X.Plot.get(p)
		return plot.cframe:PointToWorldSpace(local3)
	end
	function X.standAt(p, pos)
		p.root.CFrame = CFrame.new(pos)
	end
	-- a pilot trip of a field rep (CompanyOps tripList shape): abroad Helix Research by default
	function X.addTrip(s, client, opts2)
		opts2 = opts2 or {}
		local e = s.data.empire
		local c = X.Ops.client(client)
		local days = if c.trip == "abroad" then (if e.jet == true then X.Ops.JET.days else 2) elseif c.trip == "region" then 1 else 0.2
		local trip = { client = client, kind = opts2.kind or "sign", back = math.floor(e.seconds + (opts2.duration or days * 1200) + 0.5), founder = opts2.founder or false,
			hosted = opts2.hosted or false, crew = opts2.crew or 2, left = math.floor(e.seconds) }
		table.insert(e.deals.tripList, trip)
		return trip
	end
	function X.notices(p)
		local out = {}
		for _, f in X.Remote.fired do
			if f.player == p and f.name == "Notify" and f.args[1] == "CAMPUS_NOTICE" then table.insert(out, f.args[2].text) end
		end
		return out
	end
	function X.views(p)
		local out = {}
		for _, f in X.Remote.fired do
			if f.player == p and f.name == "Notify" and f.args[1] == "ITINERARY" then table.insert(out, f.args[2]) end
		end
		return out
	end
	function X.lastView(p)
		local v = X.views(p)
		return v[#v]
	end
	function X.notifies(p, kind)
		local out = {}
		for _, f in X.Remote.fired do
			if f.player == p and f.name == "Notify" and f.args[1] == kind then table.insert(out, f.args[2]) end
		end
		return out
	end
	function X.state(p) return X.Itin.state(p) end
	-- the founder's own ride folder (home company folder or the limousine service)
	function X.rideFolder(p)
		local root = RS:FindFirstChild("CompanyDrivers")
		if not root then return nil end
		local lists = { root:FindFirstChild("Drivers_" .. p.UserId), root:FindFirstChild("Limo") }
		for _, f in lists do
			if f then
				for _, r in f:GetChildren() do
					if r:GetAttribute("Rider") == p.UserId and (r:GetAttribute("Kind") == "founder" or r:GetAttribute("Kind") == "limo") then return r end
				end
			end
		end
		return nil
	end
	-- walk to the waiting car and get in (TripAction ride board)
	function X.boardCar(p, s)
		local rf = X.rideFolder(p)
		if not rf or rf:GetAttribute("State") ~= "waiting" then return false, "no waiting car" end
		local plot = rf:GetAttribute("Plot")
		local segs = X.Drive.decode(rf:GetAttribute("Plan"), plot)
		local carCF
		if segs and #segs > 0 then
			local leg = X.Drive.segLeg(segs[#segs], plot)
			if leg then carCF = X.Drive.endCF(leg) end
		end
		if not carCF then
			local pk = X.Drive.place(rf:GetAttribute("Pickup"), plot)
			carCF = pk and pk.stop
		end
		if not carCF then return false, "no car frame" end
		X.standAt(p, carCF * Vector3.new(5, 3, 2))
		local r = X.act(s, { action = "ride", op = "board" })
		return r.ok, r.err
	end
	function X.phoneState(s) return X.Phone._state(s) end
	function X.calendarKeys(s)
		local out = {}
		for _, it in X.Phone._state(s).calendar do out[it.key] = it end
		return out
	end
	function X.ledgerSum(s)
		local total = 0
		local led = s.data.empire.ledger
		if typeof(led) == "table" then
			for _, day in led do
				for _, side in { "i", "o" } do
					if typeof(day[side]) == "table" then for _, v in day[side] do total += v end end
				end
			end
		end
		return total
	end
	-- the CityBuilder "Start meeting" prompt of a client office (CityPlan id)
	function X.meetingPrompt(key)
		local world = game.Workspace:FindFirstChild("WorldCity")
		if not world then return nil end
		for _, d in world:GetDescendants() do
			if d:IsA("ProximityPrompt") and d:GetAttribute("CityAction") == "meeting" and d:GetAttribute("ClientId") == key then return d end
		end
		return nil
	end
	function X.firePrompt(q, p)
		local svc = game:GetService("ProximityPromptService")
		M.fire(svc.PromptTriggered, q, p)
		M.settle(0.05)
	end
	return X
end
