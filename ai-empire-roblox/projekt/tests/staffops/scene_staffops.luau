--!nocheck
-- guiprev scene of the staffops package (approximate previews from the REAL client code):
--   rack          world GUIs of rack faults through the real PropFx path (register + animate): HQ racks R48 (IT
--                 remote fix), R7 (engineer at the rack), R12 (IT on the way), the rack-door banner, and the
--                 garage cabinet with R1 + R3 down in one label
--   badges        employee badges: apprentices (dressApprentice, long names) next to a regular hire
--   talk_garage   the TalkPanel with a garage engineer repairing the mini rack (Dialogue from real state)
--   talk_rich     stage 5: the receptionist answers "Who's away today?" (CompanyOps.presence of 240 staff)
--   talk_trainer  stage 3: the Training Lead at a tour stop, then "How are the apprentices doing?"
-- python3 tools/guiprev/guiprev.py --scene tests/staffops/scene_staffops.luau --gen tests/staffops/gen --state talk_rich \
--     --viewport phone --dpr 2 --out out/staffops/phone_talk_rich.png
local M = require("../../harness/mock")
local GuiDump = require("../../tools/guiprev/guidump")
local args = { ... }
local GEN = args[1] or "./gen"
local STATE = args[2] or "talk_rich"
local VW, VH = tonumber(args[3]) or 1280, tonumber(args[4]) or 720
local insetList = string.split(args[5] or "58,0,0,0", ",")
local INSETS = { top = tonumber(insetList[1]) or 0, right = tonumber(insetList[2]) or 0, bottom = tonumber(insetList[3]) or 0, left = tonumber(insetList[4]) or 0 }
local FEEDBACK = if args[6] and args[6] ~= "-" then require(args[6]) else nil
local OPT_ASK = nil
for i = 7, #args do local k, v = string.match(args[i], "^([%w_]+)=(.*)$"); if k == "ask" then OPT_ASK = v end end

M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
GuiDump.init(M)
M.G.os = setmetatable({ clock = function() return M.Sched.now end }, { __index = os })

local function body()
	local G = M.G
	local Instance, Vector3, CFrame, Color3 = G.Instance, G.Vector3, G.CFrame, G.Color3
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local Client = game.StarterPlayer.StarterPlayerScripts.Client
	local Dialogue = M.require(RS.Shared.Dialogue)
	local Template = M.require(Server.Lib.Template)
	local EmpireMath = M.require(RS.Shared.EmpireMath)
	local Ops = M.require(RS.Shared.CompanyOps)
	if STATE == "rack" then
		local Fx = M.require(Client.Controllers.PropFxController)
		local Collection = game:GetService("CollectionService")
		local holder = Instance.new("Model"); holder.Name = "Office"; holder.Parent = G.workspace
		local roots = {}
		local now = G.workspace:GetServerTimeNow()
		-- HQ data-hall racks (ArchKit.serverRack): one blade per rack, the perforated door in front of it
		for k, case in { { slot = 48, left = 290, worker = "IT Support", fix = "remote" }, { slot = 7, left = 42, worker = "ML Engineer", fix = "rack" }, { slot = 12, left = 263, worker = "IT Support", fix = "walk" } } do
			local x = k * 12
			local blade = Instance.new("Part"); blade.Name = "RackBlade"; blade.Size = Vector3.new(1.4, 4.4, 0.08); blade.CFrame = CFrame.new(x, 3.8, 0); blade.Anchored = true; blade.Parent = holder
			blade:SetAttribute("Fx", "breathe"); Collection:AddTag(blade, "PropFx")
			local door = Instance.new("Part"); door.Name = "RackDoor"; door.Size = Vector3.new(2, 7.3, 0.08); door.CFrame = CFrame.new(x, 3.75, -0.18); door.Anchored = true; door.Parent = holder
			door:SetAttribute("Fx", "hinge,leds"); Collection:AddTag(door, "PropFx")
			local mesh = Instance.new("SurfaceGui"); mesh.Name = "Mesh"; mesh.Face = Enum.NormalId.Front; mesh.CanvasSize = Vector2.new(200, 730); mesh.Parent = door
			local perforation = Instance.new("Frame"); perforation.Name = "Perforation"; perforation.BorderSizePixel = 0; perforation.Position = UDim2.fromOffset(16, 40); perforation.Size = UDim2.fromOffset(168, 650)
			perforation.BackgroundColor3 = Color3.fromRGB(60, 64, 70); perforation.BackgroundTransparency = 0.2; perforation.Parent = mesh
			for i = 1, 8 do
				local led = Instance.new("Frame"); led.Name = "LED" .. i; led.BorderSizePixel = 0; led.Position = UDim2.fromOffset(176, 120 + i * 50); led.Size = UDim2.fromOffset(10, 10)
				led.BackgroundColor3 = Color3.fromRGB(80, 200, 120); led.Parent = mesh
			end
			local pb, pd = Fx.register(blade), Fx.register(door)
			blade:SetAttribute("FxState", "broken"); blade:SetAttribute("FaultSlot", case.slot); blade:SetAttribute("FaultUntil", now + case.left)
			blade:SetAttribute("FaultWorker", case.worker); blade:SetAttribute("FaultFix", case.fix)
			door:SetAttribute("FxState", "broken"); door:SetAttribute("FaultSlot", case.slot)
			Fx.animate(pb, now, 0.1, {}, {}); Fx.animate(pd, now, 0.1, {}, {})
			table.insert(roots, pb.fault.overlay.beacon)
			if k == 1 then table.insert(roots, door) end
		end
		-- the garage cabinet (RoomKitsGarage.gpuRack): blades R1 + R3 down behind one door, nobody on it yet
		local at = CFrame.new(80, 0, 0)
		local gdoor = Instance.new("Part"); gdoor.Name = "RackDoor"; gdoor.Size = Vector3.new(2.6, 6.8, 0.08); gdoor.CFrame = at * CFrame.new(0, 3.5, -2.52); gdoor.Anchored = true; gdoor.Parent = holder
		gdoor:SetAttribute("Fx", "hinge"); Collection:AddTag(gdoor, "PropFx"); Fx.register(gdoor)
		local gp = {}
		for i = 1, 3 do
			local b = Instance.new("Part"); b.Name = "RackBlade"; b.Size = Vector3.new(2.0, 0.6, 0.08); b.CFrame = at * CFrame.new(0, 1.0 + (i - 1) * 0.85, -2.44); b.Anchored = true; b.Parent = holder
			b:SetAttribute("Fx", "breathe"); Collection:AddTag(b, "PropFx"); gp[i] = Fx.register(b)
		end
		for _, i in { 1, 3 } do gp[i].root:SetAttribute("FxState", "broken"); gp[i].root:SetAttribute("FaultSlot", i); gp[i].root:SetAttribute("FaultUntil", now + 288 + i) end
		for _, i in { 1, 3 } do Fx.animate(gp[i], now, 0.1, {}, {}) end
		table.insert(roots, gp[1].fault.overlay.beacon)
		GuiDump.dump(roots, { scene = "staffops", state = STATE })
		return
	end
	if STATE == "badges" then
		-- employee badges (EmployeeRigDesign) of a regular hire and of apprentices (StaffAssignment.dressApprentice)
		local Rig = M.require(Server.Services.EmployeeRigDesign)
		local Assignment = M.require(Server.Services.StaffAssignment)
		local folder = Instance.new("Folder"); folder.Name = "Employees"; folder.Parent = G.workspace
		local roots = {}
		local cases = { { role = "marketer", name = "Maximilian Okonkwo-Schulz", appr = true }, { role = "curator", name = "Mia Weber", appr = true }, { role = "marketer", name = "Jonas Klein", appr = false }, { role = "engineer", name = "Alexandra Petrovic", appr = true } }
		for i, c in cases do
			local m = Rig.build(folder, 1001, i, c.role, CFrame.new(i * 6, 3, 0), { n = c.name, s = 1000 + i * 37, k = if c.appr then 1 else 3 })
			if c.appr then Assignment.dressApprentice(m, true) end
			table.insert(roots, m.Head)
		end
		GuiDump.dump(roots, { scene = "staffops", state = STATE })
		return
	end
	-- the local player + PlayerGui for the TalkPanel
	local playerGui = Instance.new("Folder"); playerGui.Name = "PlayerGui"
	local player = { UserId = 1001, Name = "Noah", DisplayName = "Noah", Character = nil, CharacterAdded = M.newSignal("CharacterAdded") }
	player.WaitForChild = function(_, name) if name == "PlayerGui" then return playerGui end end
	player.FindFirstChildOfClass = function() return nil end
	M.IMPL.Players.get.LocalPlayer = function() return player end; M.classInfo("Players").get.LocalPlayer = function() return player end
	-- the camera viewport the TalkPanel fits its UIScale to (read-only in Roblox: set on the mock directly)
	G.workspace.CurrentCamera[M.KEY].props.ViewportSize = G.Vector2.new(VW, VH)
	local TalkPanel = M.require(Client.UI.Screens.TalkPanel)
	-- company state behind the lines
	local d = Template.new()
	d.company = { name = "Nimbus Labs", logo = "N", color = "cyan", spec = "general", reputation = 10, foundedAt = 0 }
	local subject, ask
	local HOUR = 10.4
	if STATE == "talk_night" then
		d.empire.office = 3
		d.empire.employees = { researcher = 30, engineer = 14, curator = 10, marketer = 10 }
		EmpireMath.syncProfiles(d.empire, 1001)
		d.empire.nightShift = { research = true }
		local p = d.empire.staffProfiles.researcher[29]
		subject = { name = p.n, roleId = "researcher", job = "AI Researcher", seed = p.s, index = 29, activity = "RESEARCH", task = "RunExperiment", room = "Research Lab", level = "1", levelNumber = 1, shiftStart = 22, shiftEnd = 6 }
		ask = "work"
		HOUR = 23.2
	elseif STATE == "talk_itremote" then
		d.empire.office = 3
		d.empire.employees = { researcher = 12, engineer = 12, curator = 10, marketer = 10 }
		EmpireMath.syncProfiles(d.empire, 1001)
		d.gpus.accelerator = 3
		Ops.faultStep(d.empire, d.gpus, 1001, 0, 0)
		table.insert(Ops.faults(d.empire), { slot = 2, gpu = "accelerator", throughput = 1, left = 1, since = 0 })
		subject = { name = "Ivo Lang", roleId = "support", job = "IT Support", seed = 4242, index = 306, activity = "SERVER_CHECK", task = "RackRepair", pose = "typeStand", level = "1", levelNumber = 1 }
		ask = "work"
	elseif STATE == "talk_garage" then
		d.empire.office = 1
		d.empire.employees = { researcher = 1, engineer = 2, curator = 1, marketer = 0 }
		EmpireMath.syncProfiles(d.empire, 1001)
		d.gpus.consumer = 2
		Ops.faultStep(d.empire, d.gpus, 1001, 0, 0)
		table.insert(Ops.faults(d.empire), { slot = 1, gpu = "consumer", throughput = 1, left = 1, since = 0 })
		local p = d.empire.staffProfiles.engineer[1]
		subject = { name = p.n, roleId = "engineer", job = "ML Engineer", seed = p.s, index = 2, activity = "SERVER_CHECK", task = "RackRepair", room = "Garage Lab", level = "G", levelNumber = 0 }
		ask = "work"
	elseif STATE == "talk_trainer" then
		d.empire.office = 3
		d.empire.employees = { researcher = 12, engineer = 12, curator = 10, marketer = 10 }
		EmpireMath.syncProfiles(d.empire, 1001)
		d.empire.calendar = { day = 6 }
		d.empire.apprentices = {}
		for _, role in { "researcher", "engineer", "curator" } do
			local list = d.empire.staffProfiles[role]
			d.empire.apprentices[tostring(list[#list].s)] = { day = if role == "curator" then 6 else 3 }
		end
		local Plan = M.require(RS.Shared.Config.BuildingPlan)
		local stop = "G_CAFE"
		for _, r in Plan.rooms(2) do if r.dept == "data" and (r.desks or 0) > 1 then stop = r.id; break end end
		subject = { name = "Clara Novak", roleId = "support", job = "Training Lead", seed = 4711, index = 317, activity = "WORKING", task = "Tour:" .. stop }
		ask = OPT_ASK or "work"
	else
		d.empire.office = 5
		d.empire.employees = { researcher = 60, engineer = 60, curator = 60, marketer = 60 }
		EmpireMath.syncProfiles(d.empire, 1001)
		d.empire.calendar = { day = 13 }
		subject = { name = "Lina Rossi", roleId = "support", job = "Reception", seed = 3301, index = 301, activity = "WORKING", task = "CampusOperations", room = "Reception Hall", level = "G", levelNumber = 0, shiftStart = 7.3, shiftEnd = 18.2 }
		ask = "away"
	end
	local facts = Dialogue.facts(d, { users = 0, revenue = 0, cost = 0 })
	local tier = math.max(0, d.empire.office - 1)
	local lines = Dialogue.lines(subject, { viewer = "owner", viewerName = "Noah", day = d.empire.calendar.day or 1, hour = HOUR, tier = tier, facts = facts, company = "Nimbus Labs" })
	local asked = {}
	local function call(p)
		if p.action == "say" then
			local answer, options = Dialogue.step(lines, asked, p.option)
			return true, { text = answer and answer.text or "", options = options, close = answer and answer.close }
		end
		return true, {}
	end
	-- the opening chips with the staffops topic first
	local opts = {}
	table.insert(opts, { id = ask, text = (lines.answers[ask] and (ask == "away" and "Who's away today?" or ask == "apprentices" and "How are the apprentices doing?" or "What are you working on?")) })
	for _, o in lines.options do if o.id ~= ask and #opts < 3 then table.insert(opts, o) end end
	table.insert(opts, { id = "bye", text = "Thanks, carry on." })
	local payload = { id = "c1", name = subject.name, initials = Dialogue.initials(subject.name), seed = subject.seed, job = subject.job, room = subject.room, level = subject.level, greeting = lines.greeting, options = opts }
	TalkPanel.open(payload, call)
	M.settle(3)
	-- pick the staffops topic (chip 1)
	local screen = playerGui:FindFirstChild("TalkPanel")
	local chip = nil
	for _, x in screen:GetDescendants() do if x:IsA("TextButton") and x.Name == "Option_" .. ask then chip = x end end
	if chip then M.fire(chip.Activated) end
	M.settle(4)

	GuiDump.setViewport(playerGui, VW, VH, INSETS)
	local n = GuiDump.applyFeedback({ playerGui }, FEEDBACK)
	M.settle(0.3)
	GuiDump.dump({ playerGui }, { scene = "staffops", state = STATE, viewport = { VW, VH }, insets = INSETS, feedbackChanged = n })
end

setfenv(body, M.envFor(nil))
local ok, res, status = M.runMain(body, { timeout = 600 })
if not ok then print("@@ERROR body crashed (" .. tostring(status) .. "): " .. tostring(res)) end
if M.stats.errors > 0 then print("@@ERROR background thread errors: " .. M.stats.errors) end
