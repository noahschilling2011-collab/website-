--!nocheck
-- Package "life" · job routes (helper of test_routes.py): builds one tier at the building-local frame,
-- checks every operations job point (inside a plan room the support staff may enter, look-at given) and
-- prints the straight hop segments the jobs walk inside a room (post points incl. via chains, the mop
-- loop, the lunch queue) as "@@SEG post a b" lines for the walkability probe in test_routes.py.
-- Run: tools/luau tests/life/routes.luau -a [tier]
local M = require("../../harness/mock")
M.loadTree(require("./gen_build/manifest"), require("./gen_build/sources"))
M.quiet = true
local G = M.G
local say = print
local args = { ... }
local TIER = tonumber(args[1]) or 2
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; say("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end
local function v(p) return string.format("%.3f,%.3f,%.3f", p.X, p.Y, p.Z) end

local function body()
	local Vector3, CFrame, Color3 = G.Vector3, G.CFrame, G.Color3
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local Template = M.require(Server.Lib.Template)
	local EmpireConfig = M.require(RS.Shared.Config.EmpireConfig)
	local EmployeeConfig = M.require(RS.Shared.Config.EmployeeConfig)
	local Plan = M.require(RS.Shared.Config.BuildingPlan)
	local Design = M.require(Server.Services.HeadquartersDesign)
	local d = Template.new()
	d.company = { name = "Nimbus Labs", logo = "N", color = "cyan", spec = "general", reputation = 10, foundedAt = 0 }
	d.empire.office = M.require(RS.Shared.Config.BuildingPlan).officeForTier(TIER) -- econ: save office index of this plan tier (DATA_VERSION 6)
	local cap = EmpireConfig.OFFICES[d.empire.office].staff
	for k, role in EmpireConfig.ROLES do d.empire.employees[role.id] = math.floor(cap / #EmpireConfig.ROLES) + (if k <= cap % #EmpireConfig.ROLES then 1 else 0) end
	local office = Design.build(CFrame.new(), { userId = 1001, player = { Name = "T", DisplayName = "T", UserId = 1001 }, data = d, live = {} }, Color3.fromRGB(120, 154, 129))
	local function room(p) local r = Plan.roomAt(TIER, p); return if r then r.id else nil end
	local segments = 0
	local function seg(label, a, b)
		segments += 1
		say("@@SEG " .. label .. " " .. v(a) .. " " .. v(b))
	end
	local posts = {}
	for _, m in office:GetDescendants() do
		if m:IsA("Model") and m:GetAttribute("OpsIndex") ~= nil then posts[m:GetAttribute("OpsIndex")] = m end
	end
	for i, post in posts do
		local job = EmployeeConfig.JOBS[EmployeeConfig.OPERATIONS_JOBS[i]]
		check("post " .. i .. " has a job", job ~= nil)
		local stand = post:GetAttribute("InteractionPosition")
		local home = room(stand)
		check("post " .. i .. " inside a room", home ~= nil, v(stand))
		local function point(name)
			if not name then return stand end
			local p = post:GetAttribute("JobPoint_" .. name)
			return if typeof(p) == "Vector3" then p else nil
		end
		-- every job point: inside a room support staff may enter, with a look-at point
		for name, value in post:GetAttributes() do
			if string.sub(name, 1, 9) == "JobPoint_" then
				local r = room(value)
				check("job point inside a room", r ~= nil, post.Name .. "." .. name .. " " .. v(value))
				check("job point allowed for support", Plan.employeeAllowed("support", TIER, value), post.Name .. "." .. name)
				check("job point at standing height", math.abs((value.Y - 2.8) - Plan.levelY(Plan.levelAt(TIER, value.Y) or 0) - 0.1) < 0.3 or math.abs((value.Y - 2.8) - Plan.levelY(Plan.levelAt(TIER, value.Y) or 0)) < 0.3, post.Name .. "." .. name)
			end
		end
		-- walk the job twice (wrap-around) and emit the in-room hops
		local here = stand
		for pass_ = 1, 2 do
			for _, step in job do
				if step.at or step.sit then
					local target = point(step.at)
					if target then
						local chain = {}
						for _, name in step.via or {} do local p = point(name); if p then table.insert(chain, p) end end
						table.insert(chain, target)
						for _, p in chain do
							if room(here) == room(p) and room(p) ~= nil then
								if pass_ == 1 then seg(post.Name, here, p) end
							end
							here = p
						end
					end
				end
			end
		end
	end
	-- mop loop and lunch queue (hops between consecutive points)
	local mops, queue = {}, {}
	for _, m in office:GetDescendants() do
		if m:IsA("Model") then
			if m:GetAttribute("WorkstationType") == "Mop" then mops[m:GetAttribute("MopIndex")] = m:GetAttribute("InteractionPosition") end
			if m:GetAttribute("WorkstationType") == "Queue" then queue[m:GetAttribute("QueueIndex")] = m:GetAttribute("InteractionPosition") end
		end
	end
	check("mop loop has 4 points", #mops == 4, #mops)
	check("lunch queue has 6 slots", #queue == 6, #queue)
	for k = 2, #mops do seg("AtriumMop", mops[k - 1], mops[k]) end
	for k = 2, #queue do seg("LunchQueue", queue[k], queue[k - 1]) end
	for k, p in queue do check("queue slot in the café", room(p) == "G_CAFE", k) end
	say(string.format("tier %d: %d posts, %d hop segments", TIER, (function() local n = 0; for _ in posts do n += 1 end; return n end)(), segments))
end
setfenv(body, M.envFor(nil))
local ok, err = M.runMain(body, { timeout = 600 })
if not ok then say("ERROR: " .. tostring(err)); failc += 1 end
say(string.format("life routes (plan): %d passed, %d failed", pass, failc))
