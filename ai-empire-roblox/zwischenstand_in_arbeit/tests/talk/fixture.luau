--!nocheck
-- Talk tests: one tier-2 office on a rotated plot with real EmployeeRigDesign rigs (a researcher with a
-- persistent profile, an engineer, and operations staff at posts in their real rooms), an owner and a
-- visitor session with characters. Positions are building-local and converted with the plot frame.
return function(M, G, TIER)
	local Instance, Vector3, CFrame = G.Instance, G.Vector3, G.CFrame
	local game = M.game
	local workspace = M.workspace
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local Services = Server.Services
	local Template = M.require(Server.Lib.Template)
	local EmpireMath = M.require(RS.Shared.EmpireMath)
	local EmployeeConfig = M.require(RS.Shared.Config.EmployeeConfig)
	local Rig = M.require(Services.EmployeeRigDesign)
	local Session = M.require(Services.SessionService)
	local Plot = M.require(Services.PlotService)
	local OWNER, VISITOR = 4242, 777
	local cf = CFrame.new(140, 24, -60) * CFrame.Angles(0, math.rad(37), 0)
	local plots = workspace:FindFirstChild("Plots") or Instance.new("Folder"); plots.Name = "Plots"; plots.Parent = workspace
	local plot = Instance.new("Model"); plot.Name = "Plot_01"; plot.Parent = plots
	local office = Instance.new("Model"); office.Name = "Office"; office:SetAttribute("OwnerUserId", OWNER); office:SetAttribute("OfficeTier", TIER); office.Parent = plot
	local employees = Instance.new("Folder"); employees.Name = "Employees"; employees.Parent = office
	local operations = Instance.new("Folder"); operations.Name = "OperationsEmployees"; operations.Parent = office
	-- café seats + desks so the static counts have something to count
	for i = 1, 5 do local m = Instance.new("Model"); m.Name = "Dining" .. i; m:SetAttribute("WorkstationId", "D" .. i); m:SetAttribute("WorkstationType", "Dining"); m.Parent = office end
	for i = 1, 7 do local m = Instance.new("Model"); m.Name = "Desk" .. i; m:SetAttribute("WorkstationId", "C" .. i); m:SetAttribute("WorkstationType", "Computer"); m.Parent = office end
	-- owner session
	local d = Template.new()
	d.company = { name = "Nimbus Labs", logo = "N", color = "cyan", spec = "general", reputation = 10, foundedAt = 0 }
	d.empire.office = TIER; d.money = 54321
	d.empire.employees = { researcher = 1, engineer = 1, curator = 0, marketer = 0 }
	EmpireMath.syncProfiles(d.empire, OWNER)
	d.empire.staffProfiles.researcher[1].k = 5; d.empire.staffProfiles.researcher[1].w = 1.4
	d.empire.staffProfiles.engineer[1].k = 2; d.empire.staffProfiles.engineer[1].w = 0.8
	d.data = { general = { tokens = 2e9, quality = 0.5 } }
	d.gpus = { consumer = 1 }
	local function character(name)
		local c = Instance.new("Model"); c.Name = name
		local r = Instance.new("Part"); r.Name = "HumanoidRootPart"; r.Anchored = true; r.Size = Vector3.new(2, 2, 1); r.Parent = c
		c.PrimaryPart = r; c.Parent = workspace
		return c, r
	end
	local ownerChar, ownerRoot = character("Noah")
	local visitorChar, visitorRoot = character("Guest")
	local ownerPlayer = { UserId = OWNER, Name = "Noah", DisplayName = "Noah", Character = ownerChar }
	local visitorPlayer = { UserId = VISITOR, Name = "Guest", DisplayName = "Guesty", Character = visitorChar }
	local ownerS = { userId = OWNER, player = ownerPlayer, data = d, live = { users = 1200, revenue = 3, cost = 1, perModel = {}, npcUsers = {}, campus = { passes = { { id = VISITOR, expires = 0 } } } }, closed = false }
	local vd = Template.new()
	local visitorS = { userId = VISITOR, player = visitorPlayer, data = vd, live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} }, closed = false }
	Session.sessions = { ownerS, visitorS }
	Plot.plots = { { office = office, owner = ownerPlayer, cframe = cf } }
	-- rigs: local position (building space), standing at their post facing +Z
	local rigs = {}
	local function place(key, parent, index, role, lp, profile, attrs)
		local m = Rig.build(parent, OWNER, index, role, cf * CFrame.new(lp), profile)
		m:SetAttribute("CampusCFrame", cf); m:SetAttribute("Activity", "WORKING")
		for k, v in attrs or {} do m:SetAttribute(k, v) end
		rigs[key] = m
		return m
	end
	local p = d.empire.staffProfiles.researcher[1]
	place("researcher", employees, 1, "researcher", Vector3.new(-32, 3, 10), { n = p.n, s = p.s, k = p.k }, { Task = "RunExperiment" })
	local q = d.empire.staffProfiles.engineer[1]
	place("engineer", employees, 2, "engineer", Vector3.new(-30, 3, 14), { n = q.n, s = q.s, k = q.k }, { Task = "WriteCode" })
	local POSTS = { [1] = Vector3.new(-4, 3, -32), [3] = Vector3.new(8, 3, -30), [5] = Vector3.new(30, -13, 70), [6] = Vector3.new(-32, 3, 60), [7] = Vector3.new(40, 3, -20),
		[8] = Vector3.new(70, 3, 40), [9] = Vector3.new(62, 3, 44), [10] = Vector3.new(50, 3, 0), [12] = Vector3.new(34, -13, 50) }
	for i, lp in POSTS do place("ops" .. i, operations, 300 + i, "support", lp, nil, { Task = "CampusOperations" }) end
	local function near(model, offset)
		return model.PrimaryPart.Position + (offset or Vector3.new(4, 0, 0))
	end
	local function moveTo(root, position) root.CFrame = CFrame.new(position) end
	return {
		cf = cf, office = office, plot = plot, rigs = rigs, data = d, ownerS = ownerS, visitorS = visitorS, ownerPlayer = ownerPlayer, visitorPlayer = visitorPlayer,
		ownerRoot = ownerRoot, visitorRoot = visitorRoot, OWNER = OWNER, VISITOR = VISITOR, near = near, moveTo = moveTo, jobs = EmployeeConfig.OPERATIONS_JOBS,
	}
end
