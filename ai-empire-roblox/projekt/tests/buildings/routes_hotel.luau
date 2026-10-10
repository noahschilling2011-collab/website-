--!nocheck
-- Package "buildings" · guest-house job routes (helper of test_geometry.py): builds one tier at the
-- building-local frame, checks the guest-house operations posts (13 Hotel Reception, 14 Housekeeping:
-- every job point inside a plan room the support staff may enter) and prints the straight in-room hop
-- segments their jobs walk (StaffJobs.moveTo: same room -> direct Humanoid:MoveTo lines) as
-- "@@SEG post a b" lines, plus the guest-room points, for the walkability probe in test_geometry.py.
-- Run: tools/luau tests/buildings/routes_hotel.luau -a [tier]
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
	local CFrame, Color3 = G.CFrame, G.Color3
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
	local posts = {}
	for _, m in office:GetDescendants() do
		if m:IsA("Model") and (m:GetAttribute("OpsIndex") == 13 or m:GetAttribute("OpsIndex") == 14) then posts[m:GetAttribute("OpsIndex")] = m end
	end
	check("post 13 (Hotel Reception) exists", posts[13] ~= nil)
	check("post 14 (Housekeeping) exists", posts[14] ~= nil)
	local segments = 0
	for i, post in posts do
		local job = EmployeeConfig.JOBS[EmployeeConfig.OPERATIONS_JOBS[i]]
		check("post " .. i .. " has a job", job ~= nil)
		local stand = post:GetAttribute("InteractionPosition")
		check("post " .. i .. " inside a guest-house room", room(stand) ~= nil and Plan.annexAt(TIER, stand) == "hotel", v(stand))
		local function point(name)
			if not name then return stand end
			local p = post:GetAttribute("JobPoint_" .. name)
			return if typeof(p) == "Vector3" then p else nil
		end
		for _, step in job or {} do
			if step.at then check("post " .. i .. " has job point " .. step.at, point(step.at) ~= nil) end
		end
		for name, value in post:GetAttributes() do
			if string.sub(name, 1, 9) == "JobPoint_" then
				check("job point inside a room", room(value) ~= nil, post.Name .. "." .. name .. " " .. v(value))
				check("job point allowed for support", Plan.employeeAllowed("support", TIER, value), post.Name .. "." .. name)
				check("job point has a look-at point", typeof(post:GetAttribute("JobFace_" .. string.sub(name, 10))) == "Vector3", name)
			end
		end
		-- walk the job twice (wrap-around) and print the in-room hops
		local here = stand
		for pass_ = 1, 2 do
			for _, step in job or {} do
				if step.at or step.sit then
					local target = point(step.at)
					if target then
						if room(here) == room(target) and room(target) ~= nil and pass_ == 1 then
							segments += 1
							say("@@SEG " .. post.Name .. " " .. v(here) .. " " .. v(target))
						end
						here = target
					end
				end
			end
		end
	end
	-- guest-room points (later hotel-guest NPCs): one per guest room, in its room
	local guests = 0
	for _, m in office:GetDescendants() do
		if m:IsA("Model") and m:GetAttribute("WorkstationType") == "GuestBed" then
			guests += 1
			local p = m:GetAttribute("InteractionPosition")
			check("guest point inside its room", room(p) == m:GetAttribute("GuestRoom"), m.Name)
		end
	end
	check("12 guest-room points", guests == Plan.HOTEL_ROOMS, guests)
	say(string.format("tier %d: %d hop segments", TIER, segments))
end
setfenv(body, M.envFor(nil))
local ok, err = M.runMain(body, { timeout = 600 })
if not ok then say("ERROR: " .. tostring(err)); failc += 1 end
say(string.format("buildings routes (plan): %d passed, %d failed", pass, failc))
