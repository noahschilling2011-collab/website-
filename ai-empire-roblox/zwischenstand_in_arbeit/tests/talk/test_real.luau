--!nocheck
-- Talk integration test on the REAL headquarters (HeadquartersDesign.build: every generator, real
-- StaffAssignment posts and desks): the owner talks to EVERY rig (hired staff and all placed operations
-- staff) and walks the whole option tree; a visitor tries every rig (only front-of-house may answer).
-- Checks: each rig stands in a named room, every line is clean, 2..4 chips, bye ends it, the NPC is
-- released afterwards; every hired employee names the room of their real home desk, people explain the
-- room they stand in, the receptionist's tour cites the plan's floor guide. Prints job → room so the posts
-- can be eyeballed.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_talk && tools/luau tests/talk/test_real.luau -a .gen_talk [tier]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_talk")
local TIER = tonumber(args[2]) or 2
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
for path, src in require("./stubs") do sources[path] = src end
M.loadTree(manifest, sources)
M.quiet = true
local G = M.G
local say = print
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; say("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end
local function bad(text)
	return type(text) ~= "string" or #text < 8 or string.find(text, "[{}]") ~= nil or string.find(text, "nil", 1, true) ~= nil or string.find(text, "nan", 1, true) ~= nil or string.find(text, "  ", 1, true) ~= nil
end
local function body()
	local Instance, Vector3, CFrame = G.Instance, G.Vector3, G.CFrame
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local Services = Server.Services
	local EmpireMath = M.require(RS.Shared.EmpireMath)
	local EmployeeConfig = M.require(RS.Shared.Config.EmployeeConfig)
	local Dialogue = M.require(RS.Shared.Dialogue)
	local Template = M.require(Server.Lib.Template)
	local Remote = M.require(Server.Lib.Remote)
	local Session = M.require(Services.SessionService)
	local Plot = M.require(Services.PlotService)
	local Design = M.require(Services.HeadquartersDesign)
	local Talk = M.require(Services.TalkService)
	local OWNER, VISITOR = 1001, 2002
	local d = Template.new()
	d.company = { name = "Nimbus Labs", logo = "N", color = "cyan", spec = "general", reputation = 10, foundedAt = 0 }
	d.empire.office = M.require(RS.Shared.Config.BuildingPlan).officeForTier(TIER); d.money = 250000 -- econ: save office index of this plan tier (DATA_VERSION 6)
	d.empire.employees = { researcher = 4, engineer = 4, curator = 2, marketer = 2 }
	EmpireMath.syncProfiles(d.empire, OWNER)
	local function character(name)
		local c = Instance.new("Model"); c.Name = name
		local r = Instance.new("Part"); r.Name = "HumanoidRootPart"; r.Anchored = true; r.Parent = c; c.PrimaryPart = r; c.Parent = G.workspace
		return c, r
	end
	local oc, oroot = character("Tester")
	local vc, vroot = character("Guest")
	local owner = { UserId = OWNER, Name = "Tester", DisplayName = "Tester", Character = oc }
	local visitor = { UserId = VISITOR, Name = "Guest", DisplayName = "Guest", Character = vc }
	local session = { userId = OWNER, player = owner, data = d, live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} }, closed = false }
	local vsession = { userId = VISITOR, player = visitor, data = Template.new(), live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} }, closed = false }
	local cf = CFrame.lookAt(Vector3.new(160, 24, 252), Vector3.new(160, 24, 0))
	local t0 = os.clock()
	local office = Design.build(cf, session, G.Color3.fromRGB(120, 154, 129))
	local plots = Instance.new("Folder"); plots.Name = "Plots"; plots.Parent = G.workspace
	local plotModel = Instance.new("Model"); plotModel.Name = "Plot_01"; plotModel.Parent = plots
	office.Parent = plotModel
	say(string.format("tier %d built in %.1fs", TIER, os.clock() - t0))
	Session.sessions = { session, vsession }
	Plot.plots = { { owner = owner, office = office, cframe = cf, model = plotModel } }
	local clock = 0
	Talk.clock = function() return clock end
	Talk.init()
	local act = Remote.binds.TalkAction
	local rigs = {}
	for _, folderName in { "Employees", "OperationsEmployees" } do
		local folder = office:FindFirstChild(folderName)
		for _, m in (folder and folder:GetChildren() or {}) do
			if m:IsA("Model") and m:FindFirstChild("Head") and m.Head:FindFirstChild("EmployeeTalk") then
				m:SetAttribute("Activity", "WORKING")
				local role = m:GetAttribute("RoleId")
				local tasks = EmployeeConfig.TASKS[role] or EmployeeConfig.TASKS.support
				m:SetAttribute("Task", tasks[1].id)
				table.insert(rigs, m)
			end
		end
	end
	local hired, ops = 0, 0
	for _, m in rigs do if m:GetAttribute("RoleId") == "support" then ops += 1 else hired += 1 end end
	check("all hired staff have rigs", hired == 12, hired)
	check("operations staff placed", ops >= 12, ops)
	local function talkThrough(s, player, root, m, label)
		root.CFrame = CFrame.new(m.PrimaryPart.Position + Vector3.new(3, 0, 0))
		clock += 2
		local res = act(s, { action = "open", npc = m })
		if not res.ok then return res end
		local t = res.talk
		res.answers = {}
		local ok = not bad(t.greeting) and #t.options >= 2 and #t.options <= 4 and t.options[#t.options].id == "bye"
		local opts, steps = t.options, 0
		while ok do
			steps += 1
			if steps > 25 then ok = false; break end
			clock += 1
			local a = act(s, { action = "say", id = t.id, option = opts[1].id })
			if not a.ok or bad(a.text) then ok = false; say("   bad", label, opts[1].id, a.err, a.text); break end
			res.answers[opts[1].id] = a.text
			if a.close then break end
			if #a.options < 1 or #a.options > 4 or a.options[#a.options].id ~= "bye" then ok = false; break end
			opts = a.options
		end
		check(label .. ": whole conversation clean", ok)
		check(label .. ": released", Talk.conversation(m) == nil and m:GetAttribute("TalkingTo") == nil)
		return res
	end
	local rooms = {}
	local Plan = M.require(RS.Shared.Config.BuildingPlan)
	local withDesk, withRoom, tourOk = 0, 0, false
	for _, m in rigs do
		local job = m:GetAttribute("Role")
		local res = talkThrough(session, owner, oroot, m, "owner→" .. tostring(job) .. "#" .. tostring(m:GetAttribute("StaffIndex")))
		check("owner talks to " .. tostring(job), res.ok, res.err)
		if res.ok then
			check(tostring(job) .. " stands in a named room", type(res.talk.room) == "string" and type(res.talk.level) == "string", res.talk.room)
			if m:GetAttribute("RoleId") == "support" then rooms[#rooms + 1] = string.format("%-15s %s (%s)", job, tostring(res.talk.room), tostring(res.talk.level)) end
			local a = res.answers
			if m:GetAttribute("RoleId") ~= "support" then
				-- the real home desk: HomeWorkstation → station HomeRoom → plan room name
				local ws = m:GetAttribute("HomeWorkstation")
				local station
				for _, d in office:GetDescendants() do if d:IsA("Model") and d:GetAttribute("WorkstationId") == ws then station = d; break end end
				local room = station and Plan.room(TIER, station:GetAttribute("HomeRoom") or "")
				if room and a.team and string.find(a.team, "My desk is in the " .. room.name .. " (" .. Plan.levelLabel(TIER, room.level) .. ")", 1, true) then withDesk += 1
				else say("   no desk line", job, tostring(ws), tostring(a.team)) end
			end
			if a.room then withRoom += 1 end
			if job == "Reception" and a.tour then
				tourOk = string.find(a.tour, Dialogue.floorGuide(TIER), 1, true) ~= nil and string.find(a.tour, "computer desks in total", 1, true) ~= nil
			end
		end
	end
	check("every hired employee names the room of their real home desk", withDesk == hired, withDesk .. "/" .. hired)
	check("most people can explain the room they stand in", withRoom >= math.floor(#rigs * 0.8), withRoom .. "/" .. #rigs)
	check("receptionist tour: floor guide of the plan + desks", tourOk)
	local publicCount = 0
	for _, m in rigs do
		local job = m:GetAttribute("Role")
		local public = m:GetAttribute("RoleId") == "support" and Dialogue.isPublicJob(job)
		local res = talkThrough(vsession, visitor, vroot, m, "visitor→" .. tostring(job) .. "#" .. tostring(m:GetAttribute("StaffIndex")))
		if public then publicCount += 1; check("visitor talks to front-of-house " .. job, res.ok, res.err)
		else check("visitor refused by " .. tostring(job), res.ok == false and res.err == "NOT_PUBLIC", res.err) end
	end
	check("front-of-house rigs exist (reception x2, security x2, barista, chef, host)", publicCount >= 7, publicCount)
	table.sort(rooms)
	for _, line in rooms do say("  post " .. line) end
	say(string.format("talked to %d rigs (%d hired, %d ops), %d front-of-house; %d named their desk room, %d explained the room they stand in", #rigs, hired, ops, publicCount, withDesk, withRoom))
end
setfenv(body, M.envFor(nil))
local ok, err = M.runMain(body, { timeout = 600 })
if not ok then say("ERROR: " .. tostring(err)); failc += 1 end
say(string.format("talk real-building tests (tier %d): %d passed, %d failed", TIER, pass, failc))
if failc > 0 then error("talk real-building tests failed", 0) end
