--!nocheck
-- Package "buildings" · admin test command "tier0" (AdminService) + HeadquartersDesign.tierFor:
--   * Design.tierFor: session.planTier (session only, never saved) wins, else Plan.tierForOffice(office)
--   * with today's PlotService double (no rebuild for a session-only plan tier): "tier0" answers
--     TIER_NOT_BUILT and undoes everything (planTier, office index, the saved staff are kept)
--   * with a PlotService that rebuilds when the built OfficeTier differs from Design.tierFor(session)
--     (requested in design/requests/buildings.md): "tier0" builds the garage stage (OfficeTier 0, staff
--     trimmed to the garage desks), further refreshes keep it, "tier1" goes back to plan tier 1
-- Run: python3 tests/buildings/mkharness.py && tools/luau tests/buildings/test_admin.luau
local M = require("../../harness/mock")
M.loadTree(require("./gen/manifest"), require("./gen/sources"))
M.quiet = true
local G = M.G
local say = print
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; say("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local function body()
	local Instance, Vector3, CFrame, Color3 = G.Instance, G.Vector3, G.CFrame, G.Color3
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local Services = Server.Services
	local Plan = M.require(RS.Shared.Config.BuildingPlan)
	local EmpireMath = M.require(RS.Shared.EmpireMath)
	local Template = M.require(Server.Lib.Template)
	local Remote = M.require(Server.Lib.Remote)
	local Design = M.require(Services.HeadquartersDesign)
	local PlotStub = M.require(Services.PlotService)
	local SessionStub = M.require(Services.SessionService)
	local Admin = M.require(Services.AdminService)
	local OWNER = 1001
	-- tierFor ---------------------------------------------------------------------------------------
	-- econ (DATA_VERSION 6): office 1 = Garage Lab = plan tier 0, office 5 = plan tier 4 (OFFICE_TIER_OFFSET 1)
	check("tierFor: office index 1 -> plan tier 0", Design.tierFor({ data = { empire = { office = 1 } } }) == 0)
	check("tierFor: office index 5 -> plan tier 4", Design.tierFor({ data = { empire = { office = 5 } } }) == 4)
	check("tierFor: session.planTier 0 wins", Design.tierFor({ planTier = 0, data = { empire = { office = 3 } } }) == 0)
	check("tierFor: out-of-range planTier clamped", Design.tierFor({ planTier = 9, data = { empire = { office = 1 } } }) == Plan.MAX_TIER)
	check("tierFor: NaN planTier ignored", Design.tierFor({ planTier = 0 / 0, data = { empire = { office = 2 } } }) == 1)
	-- session + plot ---------------------------------------------------------------------------------
	local cf = CFrame.lookAt(Vector3.new(160, 24, 252), Vector3.new(160, 24, 0))
	local d = Template.new()
	d.company = { name = "Nimbus Labs", logo = "N", color = "cyan", spec = "general", reputation = 10, foundedAt = 0 }
	local START = Plan.officeForTier(1) -- office index of plan tier 1 (2 since DATA_VERSION 6)
	d.empire.office = START
	d.empire.employees = { researcher = 3, engineer = 3, curator = 2, marketer = 2 } -- 10 staff
	EmpireMath.syncProfiles(d.empire, OWNER)
	local player = { UserId = OWNER, Name = "nonortrttrt", DisplayName = "Founder", Character = nil, CharacterAdded = M.newSignal("CharacterAdded") }
	local session = { userId = OWNER, player = player, data = d, live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} }, closed = false }
	SessionStub.sessions = { session }
	local plots = Instance.new("Folder"); plots.Name = "Plots"; plots.Parent = G.workspace
	local model = Instance.new("Model"); model.Name = "Plot_01"; model.Parent = plots
	local plot = { model = model, owner = player, cframe = cf, index = 1 }
	plot.office = Design.build(cf, session, Color3.fromRGB(120, 154, 129)); plot.office.Parent = model
	PlotStub.plots = { plot }
	check("start: plan tier 1 built", plot.office:GetAttribute("OfficeTier") == 1)
	Admin.init()
	local action = Remote.binds.AdminAction
	check("AdminAction bound", typeof(action) == "function")
	local function staffCount()
		local n = 0; for _, v in d.empire.employees do n += v end; return n
	end
	-- (a) today's PlotService double: refresh never rebuilds -> honest error, nothing changed
	local res = action(session, { cmd = "tier0" })
	check("(a) tier0 without a rebuilding PlotService: TIER_NOT_BUILT", res.ok == false and res.err == "TIER_NOT_BUILT", res.err)
	check("(a) planTier undone", session.planTier == nil, session.planTier)
	check("(a) saved staff kept (10)", staffCount() == 10, staffCount())
	check("(a) office index kept", d.empire.office == START)
	-- (b) PlotService as requested: rebuild when the built OfficeTier differs from Design.tierFor(session)
	local rebuilds = 0
	PlotStub.refresh = function(s)
		local p = PlotStub.get(s.player)
		if not p or not p.office then return end
		local tier = Design.tierFor(s)
		if p.office:GetAttribute("OfficeTier") ~= tier then
			rebuilds += 1
			p.office:Destroy()
			p.office = Design.build(p.cframe, s, Color3.fromRGB(120, 154, 129)); p.office.Parent = p.model
		end
	end
	res = action(session, { cmd = "tier0" })
	check("(b) tier0 ok", res.ok == true, res.err)
	check("(b) garage stage built (OfficeTier 0)", plot.office:GetAttribute("OfficeTier") == 0 and plot.office:GetAttribute("GarageStage") == true, plot.office:GetAttribute("OfficeTier"))
	check("(b) staff trimmed to the garage desks", staffCount() == Plan.GARAGE_STAGE.staff, staffCount())
	check("(b) employees placed in the garage", #plot.office.Employees:GetChildren() == Plan.GARAGE_STAGE.staff, #plot.office.Employees:GetChildren())
	check("(b) save keeps a valid office index (the garage)", d.empire.office == Plan.officeForTier(0))
	check("(b) garage reached through the save office: no session override, nothing extra saved", session.planTier == nil and d.planTier == nil)
	local before = rebuilds
	PlotStub.refresh(session); PlotStub.refresh(session)
	check("(b) further refreshes keep the garage (no rebuild loop)", rebuilds == before and plot.office:GetAttribute("OfficeTier") == 0, rebuilds - before)
	res = action(session, { cmd = "diag" })
	check("(b) diag reports the garage stage", res.ok and string.find(res.report, "plan tier 0", 1, true) ~= nil and string.find(res.report, "no lift", 1, true) ~= nil, res.report and string.sub(res.report, 1, 120))
	res = action(session, { cmd = "tier1" })
	check("(b) tier1 ok", res.ok == true, res.err)
	check("(b) back to plan tier 1", plot.office:GetAttribute("OfficeTier") == 1 and session.planTier == nil, plot.office:GetAttribute("OfficeTier"))
	res = action(session, { cmd = "tier2" })
	check("(b) tier2 builds the guest house", res.ok == true and plot.office:GetAttribute("OfficeTier") == 2 and plot.office:GetAttribute("HotelRooms") == Plan.HOTEL_ROOMS, plot.office:GetAttribute("OfficeTier"))
	res = action(session, { cmd = "tier7" })
	check("tier7 rejected", res.ok == false, res.err)
	local stranger = { userId = 2002, player = { UserId = 2002, Name = "someone" }, data = d, live = {} }
	res = action(stranger, { cmd = "tier0" })
	check("non-admin rejected", res.ok == false and res.err == "ADMIN_ONLY", res.err)
end
setfenv(body, M.envFor(nil))
local ok, err = M.runMain(body, { timeout = 900 })
if not ok then say("ERROR: " .. tostring(err)); failc += 1 end
say(string.format("buildings admin: %d passed, %d failed", pass, failc))
if failc > 0 then error("buildings admin tests failed", 0) end
