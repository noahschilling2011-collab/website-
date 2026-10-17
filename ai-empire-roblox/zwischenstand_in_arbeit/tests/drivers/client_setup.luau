--!nocheck
-- drivers package: one mock world with the REAL server side (DriverService, PlotService, CityService state,
-- PhoneService hook, VehicleService, EmployeeRigDesign) and the REAL client side (DriveController, Toast, UIRoot,
-- StateController) for test_client.luau, the guiprev scene (scene_drive.luau) and the render dump (dump_scene.luau).
-- The local player's character is a real EmployeeRigDesign rig (so the founder on the back seat looks like a person
-- in the renders). The server clock is T.now (controlled); server ticks and client frames are stepped explicitly
-- (the mock never fires frame signals). RemoteFunction:InvokeServer calls the bound server handler directly.
-- opt = {stage = 2, userId = 4242, name = "Founder", vw, vh, insets, touch}
local GuiDump = require("../../tools/guiprev/guidump")
return function(M, opt)
	opt = opt or {}
	GuiDump.init(M)
	local G = M.G
	local Instance, Vector3, CFrame = G.Instance, G.Vector3, G.CFrame
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local Client = game.StarterPlayer.StarterPlayerScripts.Client
	local S = Server.Services
	local OWNER = opt.userId or 4242
	local T = { now = 1.7e9 + 9 * 90 } -- 09:00 company time on a server day
	local function clock() return T.now end
	M.IMPL.Workspace.methods.GetServerTimeNow = clock
	M.classInfo("Workspace").methods.GetServerTimeNow = clock
	if opt.touch then
		local uis = game:GetService("UserInputService")
		uis[M.KEY].props.TouchEnabled = true
		uis[M.KEY].props.MouseEnabled = false
		uis[M.KEY].props.KeyboardEnabled = false
	end

	-- HQ generator + doors stubbed (PlotService itself runs for real)
	local Design = M.require(S.HeadquartersDesign)
	Design.build = function(cf, session, accent)
		local m = Instance.new("Model"); m.Name = "Office"
		m:SetAttribute("OfficeTier", Design.tierFor(session)); m:SetAttribute("OwnerUserId", session.userId)
		local door = Instance.new("Model"); door.Name = "Door_SITE_BARRIER"; door.Parent = m
		return m
	end
	Design.staff = function() end
	local Doors = M.require(S.DoorService)
	Doors.register = function() end; Doors.unregister = function() end
	Doors.find = function(office, id) return office:FindFirstChild("Door_" .. id) end
	Doors.requestNPC = function() return true end
	local Lift = M.require(S.LiftService); Lift.attach = function() end; Lift.detach = function() end

	-- remotes: real Remote module, handlers recorded and invoked directly
	local Remote = M.require(Server.Lib.Remote)
	local RateLimiter = M.require(Server.Lib.RateLimiter)
	RateLimiter.new = function() return { allow = function() return true end, forget = function() end } end
	local binds = {}
	local origBind = Remote.bind
	Remote.bind = function(name, limits, handler) binds[name] = handler; origBind(name, limits, handler) end
	Remote.setup()
	local folder = RS:FindFirstChild("Remotes")
	local notifyEvent = folder:FindFirstChild("Notify")
	local fired = {}
	Remote.fire = function(player, name, kind, payload)
		table.insert(fired, { name = name, kind = kind, payload = payload })
		if name == "Notify" then M.fire(notifyEvent.OnClientEvent, kind, payload) end
	end

	-- the local player: a table double with a real rig as character
	local Rig = M.require(S.EmployeeRigDesign)
	local playerGui = Instance.new("Folder"); playerGui.Name = "PlayerGui"
	local attrs = {}
	local localPlayer
	localPlayer = { UserId = OWNER, Name = opt.name or "Founder", DisplayName = opt.name or "Founder", Character = nil, Parent = game.Players,
		CharacterAdded = M.newSignal("CharacterAdded"), streamed = {},
		WaitForChild = function(_, name) if name == "PlayerGui" then return playerGui end end,
		FindFirstChild = function(_, name) if name == "PlayerGui" then return playerGui end end,
		FindFirstChildOfClass = function() return nil end, Kick = function() end,
		SetAttribute = function(_, k, v) attrs[k] = v end, GetAttribute = function(_, k) return attrs[k] end,
		RequestStreamAroundAsync = function(self, pos) table.insert(self.streamed, pos) end }
	local holder = Instance.new("Folder")
	local character = Rig.build(holder, OWNER, 1, "marketer", CFrame.new(0, 3, 0), { n = "Alex Founder", s = 777 })
	character:RemoveTag("CompanyEmployee")
	for _, d in character:GetDescendants() do
		if d:IsA("ProximityPrompt") or d:IsA("BillboardGui") then d:Destroy() end
	end
	character.Name = localPlayer.Name
	character.HumanoidRootPart.Anchored = false
	character.Parent = game.Workspace
	holder:Destroy()
	localPlayer.Character = character
	localPlayer.root = character.HumanoidRootPart
	localPlayer.humanoid = character:FindFirstChildOfClass("Humanoid")
	M.IMPL.Players.get.LocalPlayer = function() return localPlayer end
	M.classInfo("Players").get.LocalPlayer = function() return localPlayer end
	local others = {}
	local function byId(_, uid) if uid == OWNER then return localPlayer end; return others[uid] end
	M.IMPL.Players.methods.GetPlayerByUserId = byId
	M.classInfo("Players").methods.GetPlayerByUserId = byId

	-- the session (real Template data) + plot claim
	local Template = M.require(Server.Lib.Template)
	local SessionService = M.require(S.SessionService)
	local d = Template.new()
	d.company = { name = opt.company or "Nimbus Labs", logo = "N", color = opt.color or "cyan", spec = "general", reputation = 20, foundedAt = 0 }
	d.money = 250000
	d.empire.office = opt.stage or 2
	local session = { userId = OWNER, player = localPlayer, data = d, live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} },
		dirty = false, lastSent = 0, nextSaveAt = math.huge, saving = false, closed = false, released = false, rng = G.Random.new(1) }
	SessionService.all()[localPlayer] = session
	local patch = function(cls, name, fn) M.IMPL[cls].methods[name] = fn; M.classInfo(cls).methods[name] = fn end
	patch("RemoteFunction", "InvokeServer", function(self, payload)
		local handler = binds[self.Name]
		if not handler then return { ok = false, err = "BAD_INPUT" } end
		return handler(session, payload or {})
	end)
	local Plot = M.require(S.PlotService)
	Plot.init()
	Plot.claim(session)
	local City = M.require(S.CityService)
	M.require(S.PhoneService)
	local Driver = M.require(S.DriverService)
	Driver.init()

	-- client
	local UIRoot = M.require(Client.UI.UIRoot)
	local Toast = M.require(Client.UI.Toast)
	local State = M.require(Client.Controllers.StateController)
	local hud, dim, overlay, intro, top = UIRoot.init()
	if opt.vw then GuiDump.setViewport(playerGui, opt.vw, opt.vh, opt.insets) end
	Toast.mount(top)
	local Controller = M.require(Client.Controllers.DriveController)
	Controller.DIRECT = true
	Controller.init()
	M.settle(0.2)
	Controller._setRoot(RS:FindFirstChild("CompanyDrivers"), game.Workspace:FindFirstChild("DriveCars"))
	pcall(function() State.init() end)
	M.settle(0.3)

	local Drive = M.require(RS.Shared.DrivePlan)
	local plot = Plot.get(localPlayer)
	local ctx = { M = M, T = T, session = session, player = localPlayer, Driver = Driver, Drive = Drive, Controller = Controller, City = City,
		playerGui = playerGui, binds = binds, fired = fired, plot = plot, Plot = Plot, others = others, Toast = Toast, GuiDump = GuiDump }
	function ctx.tick(seconds, step)
		local left = seconds or 0
		step = step or 0.25
		while left > 1e-9 do
			local dt = math.min(step, left)
			T.now += dt
			Driver.tick(dt)
			left -= dt
		end
	end
	function ctx.frame()
		Controller.step(T.now)
	end
	function ctx.camera(pos, look)
		local cam = game.Workspace.CurrentCamera
		cam.CFrame = CFrame.lookAt(pos, look or (pos + Vector3.new(0, 0, -1)))
	end
	function ctx.stand(pos)
		localPlayer.root.CFrame = CFrame.new(pos)
		character:PivotTo(CFrame.new(pos))
	end
	function ctx.hq(local3)
		return plot.cframe:PointToWorldSpace(local3)
	end
	function ctx.call(payload)
		return binds.TripAction(session, payload)
	end
	-- Motor6D + WeldConstraint solve of every rig under `parentInst` (the mock has no physics): limbs follow the
	-- anchored root through C0 * Transform * C1^-1, accessories keep their template offsets
	function ctx.solveRigs(parentInst)
		for _, m in parentInst:GetDescendants() do
			if not m:IsA("Model") then continue end
			local r = m:FindFirstChild("HumanoidRootPart")
			if not r then continue end
			local base = {}
			local tpl = m:GetAttribute("TemplateRoot")
			for _, p in m:GetDescendants() do if p:IsA("BasePart") then base[p] = p.CFrame end end
			-- template frame: limbs were built around the root's template CFrame (identity for DriverService templates)
			local rootTpl = if typeof(tpl) == "CFrame" then tpl else nil
			local motors, welds = {}, {}
			for _, j in m:GetDescendants() do
				if j:IsA("Motor6D") then table.insert(motors, j) elseif j:IsA("WeldConstraint") then table.insert(welds, j) end
			end
			-- offsets of welded parts in their Part0's template frame
			local woff = {}
			for _, w in welds do
				if w.Part0 and w.Part1 and base[w.Part0] and base[w.Part1] then woff[w] = base[w.Part0]:Inverse() * base[w.Part1] end
			end
			local done = { [r] = true }
			local progress = true
			-- Model:ScaleTo in Roblox also scales the joints' C0 / C1 positions; the mock's ScaleTo scales the parts only,
			-- so the solve applies the model scale to the joint offsets itself
			local k = m:GetScale()
			local function scaled(c)
				if math.abs(k - 1) < 1e-6 then return c end
				return CFrame.new(c.Position * k) * c.Rotation
			end
			while progress do
				progress = false
				for _, j in motors do
					local p0, p1 = j.Part0, j.Part1
					if p0 and p1 and done[p0] and not done[p1] then
						p1.CFrame = p0.CFrame * scaled(j.C0) * j.Transform * scaled(j.C1):Inverse()
						done[p1] = true
						progress = true
					end
				end
				for _, w in welds do
					local p0, p1 = w.Part0, w.Part1
					if p0 and p1 and done[p0] and not done[p1] and woff[w] then
						p1.CFrame = p0.CFrame * woff[w]
						done[p1] = true
						progress = true
					end
				end
			end
			local _ = rootTpl
		end
	end
	return ctx
end
