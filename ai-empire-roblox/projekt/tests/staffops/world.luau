--!nocheck
-- Shared world for the staffops suites: the REAL headquarters (HeadquartersDesign.build + StaffAssignment)
-- with the real StaffService / StaffJobs / StaffEvents / StaffRota / WorkstationService, test doubles for
-- Door/Lift/Plot/Session/Remote (staff_harness/stubs), straight-line paths and Humanoid:MoveTo simulated
-- step by step (like tests/life). The server clock of the mock is workspace:GetServerTimeNow() =
-- 1.7e9 + Sched.now; W.setHour moves it forward to a company hour (CompanyOps.hour).
return function(M, opts)
	local G = M.G
	local Instance, Vector3, CFrame, Enum, Color3 = G.Instance, G.Vector3, G.CFrame, G.Enum, G.Color3
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local Services = Server.Services
	local W = { M = M, G = G }
	W.Template = M.require(Server.Lib.Template)
	W.EmpireConfig = M.require(RS.Shared.Config.EmpireConfig)
	W.EmployeeConfig = M.require(RS.Shared.Config.EmployeeConfig)
	W.Plan = M.require(RS.Shared.Config.BuildingPlan)
	W.EmpireMath = M.require(RS.Shared.EmpireMath)
	W.Ops = M.require(RS.Shared.CompanyOps)
	W.Dialogue = M.require(RS.Shared.Dialogue)
	W.Design = M.require(Services.HeadquartersDesign)
	W.Staff = M.require(Services.StaffService)
	W.Assignment = M.require(Services.StaffAssignment)
	W.Workstations = M.require(Services.WorkstationService)
	W.SessionStub = M.require(Services.SessionService)
	W.PlotStub = M.require(Services.PlotService)
	W.LiftStub = M.require(Services.LiftService)
	local okR, Rota = pcall(function() return M.require(Services.StaffRota) end)
	W.Rota = if okR then Rota else nil
	local okE, Events = pcall(function() return M.require(Services.StaffEvents) end)
	W.Events = if okE then Events else nil
	local OWNER = 1001
	W.OWNER = OWNER
	local Ops = W.Ops
	-- company hour h -> seconds into the server day, then move the mock clock forward to it
	function W.secondsOf(h)
		h = h % 24
		if h >= 8 and h < 18 then return (h - 8) * 90 end
		return 900 + ((h - 18) % 24) * 300 / 14
	end
	function W.serverNow() return G.workspace:GetServerTimeNow() end
	function W.hour() return Ops.hour(W.serverNow()) end
	function W.setHour(h)
		local cur = W.serverNow() % 1200
		local delta = (W.secondsOf(h) - cur) % 1200
		M.Sched.now += delta
	end
	W.setHour(opts.hour or 8.6)
	local tier = opts.tier or 2
	W.tier = tier
	local cf = CFrame.lookAt(Vector3.new(160, 24, 252), Vector3.new(160, 24, 0))
	W.cf = cf
	local d = W.Template.new()
	d.company = { name = "Nimbus Labs", logo = "N", color = "cyan", spec = "general", reputation = 10, foundedAt = 0 }
	d.empire.office = W.Plan.officeForTier(tier)
	if opts.employees then
		for k, v in opts.employees do d.empire.employees[k] = v end
	else
		local cap = opts.staff or W.EmpireConfig.OFFICES[d.empire.office].staff
		for k, role in W.EmpireConfig.ROLES do d.empire.employees[role.id] = math.floor(cap / #W.EmpireConfig.ROLES) + (if k <= cap % #W.EmpireConfig.ROLES then 1 else 0) end
	end
	d.empire.calendar = { day = opts.day or 1 }
	W.EmpireMath.syncProfiles(d.empire, OWNER)
	if opts.prepare then opts.prepare(d, W) end
	W.data = d
	local char = Instance.new("Model"); char.Name = "Founder"
	local hrp = Instance.new("Part"); hrp.Name = "HumanoidRootPart"; hrp.Anchored = true; hrp.CFrame = cf * CFrame.new(0, 3, 10); hrp.Parent = char; char.PrimaryPart = hrp; char.Parent = G.workspace
	W.founderRoot = hrp
	local player = { UserId = OWNER, Name = "Founder", DisplayName = "Founder", Character = char, CharacterAdded = M.newSignal("CharacterAdded") }
	local session = { userId = OWNER, player = player, data = d, live = { users = 0, revenue = 0, cost = 0 }, closed = false }
	W.session, W.player = session, player
	local office = W.Design.build(cf, session, Color3.fromRGB(120, 154, 129))
	local plots = Instance.new("Folder"); plots.Name = "Plots"; plots.Parent = G.workspace
	local plot = Instance.new("Model"); plot.Name = "Plot_01"; plot.Parent = plots
	office.Parent = plot
	W.office, W.plot = office, plot
	W.SessionStub.sessions = { session }
	W.PlotStub.plots = { { model = plot, office = office, owner = player, cframe = cf, index = 1 } }
	local function patch(cls, name, fn) M.IMPL[cls].methods[name] = fn; M.classInfo(cls).methods[name] = fn end
	patch("PathfindingService", "CreatePath", function(_, params)
		local fake = { Status = Enum.PathStatus.NoPath, _points = {}, Blocked = M.newSignal("Blocked") }
		function fake.ComputeAsync(self, start, target)
			local pts = {}; local n = math.max(1, math.ceil((target - start).Magnitude / 4))
			for i = 0, n do table.insert(pts, start:Lerp(target, i / n)) end
			self.Status = Enum.PathStatus.Success; self._points = pts
		end
		function fake.GetWaypoints(self) local out = {}; for _, p in self._points do table.insert(out, { Position = p }) end; return out end
		return fake
	end)
	local moveTarget = {}
	patch("Humanoid", "MoveTo", function(self, pos) moveTarget[self] = pos end)
	W.Staff.init()
	function W.rigs()
		local out = {}
		for _, name in { "Employees", "OperationsEmployees" } do
			local f = office:FindFirstChild(name)
			if f then for _, m in f:GetChildren() do table.insert(out, m) end end
		end
		return out
	end
	local function moveAll()
		for _, m in W.rigs() do
			local root = m.PrimaryPart; local h = m:FindFirstChildOfClass("Humanoid"); local goal = moveTarget[h]
			if goal and root and not root.Anchored then
				local here = root.Position; local dd = goal - here; local flat = Vector3.new(dd.X, 0, dd.Z); local len = h.WalkSpeed * .2
				local mv = if flat.Magnitude > len then flat.Unit * len else flat
				local y = here.Y + (if math.abs(dd.Y) > 4 then dd.Y * math.min(1, len / math.max(flat.Magnitude, len)) else 0)
				root.CFrame = CFrame.new(here.X + mv.X, y, here.Z + mv.Z)
			end
		end
	end
	W.onTick = nil
	function W.tick(n, each)
		for i = 1, n or 1 do
			W.LiftStub.clock += .2
			M.Sched.now += .2
			moveAll()
			W.Staff.tick(.2)
			if each then each(i) end
		end
	end
	function W.record(m) return W.Staff.recordOf(m) end
	function W.byRole(role)
		local out = {}
		for _, m in W.rigs() do if m:GetAttribute("RoleId") == role then table.insert(out, m) end end
		table.sort(out, function(a, b) return a:GetAttribute("StaffIndex") < b:GetAttribute("StaffIndex") end)
		return out
	end
	function W.job(title)
		for _, m in W.rigs() do if m:GetAttribute("Role") == title then return m end end
		return nil
	end
	-- the rig of profile i of a role (StaffAssignment numbers roles in ROLES order)
	function W.rigOf(role, i)
		local before = 0
		for _, r in W.EmpireConfig.ROLES do if r.id == role then break end; before += d.empire.employees[r.id] or 0 end
		for _, m in W.rigs() do if m:GetAttribute("StaffIndex") == before + i and m:GetAttribute("RoleId") == role then return m end end
		return nil
	end
	-- a hire like EmpireService.hire (profile + count) followed by PlotService.refresh (StaffAssignment)
	function W.hire(role, opts2)
		local e = d.empire
		W.EmpireMath.syncProfiles(e, OWNER)
		local name, seed = W.EmpireMath.nextIdentity(e, OWNER)
		table.insert(e.staffProfiles[role], { n = name, s = seed, k = if opts2 and opts2.apprentice then 1 else 3, w = 1 })
		if opts2 and opts2.apprentice then
			if type(e.apprentices) ~= "table" then e.apprentices = {} end
			e.apprentices[tostring(seed)] = { day = W.Ops.day(e) }
		end
		e.employees[role] = (e.employees[role] or 0) + 1
		if opts2 and opts2.from then W.Staff.expectArrival(office, seed, opts2.from) end
		if opts2 and opts2.hold then W.Staff.expectArrival(office, seed, nil, true) end
		W.Assignment.assign(office, cf, session)
		return name, seed
	end
	return W
end
