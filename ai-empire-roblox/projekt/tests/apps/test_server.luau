--!nocheck
-- apps package, server side + small client controllers, on the company states of tests/apps/ui_setup.luau:
--   * AssistantService.briefing: sections Today / Customers / Money / Models first, real numbers only (company day,
--     presence counts = CompanyOps.presence, trips with the hotel, accounts + retainers, today's P&L = ledger sums,
--     live lines, servers + waitlist, oldest line), the Next goal as recommendation 1 (a pending decision before it)
--   * BuildingStateService screens: data hall (load %, faults, reserved compute), business clients (accounts with
--     retainer and end day, never the old lease texts), reception (visitors, trips), guest-house reception, fleet
--     office, HR; every body <= 10 visual lines of 52 chars, header <= 40, footer <= 72 (the Desktop SurfaceGui)
--   * SecurityController: floor titles by plan tier (garage office 1 = plan tier 0, corefix #7), English buttons
-- Run: cd tests/apps && ../../tools/luau test_server.luau -a .gen_apps <garage|mid|rich>   (one state per process)
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_apps")
local STATE = args[2] or "mid"
local M = require("../../harness/mock")
local setup = require("./ui_setup")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local pass, failc = 0, 0
local say = print
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local function body()
	local G = M.G
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local results = { [STATE] = setup(M, GEN, STATE) }
	local Ops = M.require(RS.Shared.CompanyOps)
	local EmpireMath = M.require(RS.Shared.EmpireMath)
	local EmpireConfig = M.require(RS.Shared.Config.EmpireConfig)
	local Format = M.require(RS.Shared.Format)
	local Plan = M.require(RS.Shared.Config.BuildingPlan)
	local okA, Assistant = pcall(M.require, Server.Services.AssistantService)
	check("AssistantService loads", okA, Assistant)
	local okB, Screens = pcall(M.require, Server.Services.BuildingStateService)
	check("BuildingStateService loads", okB, Screens)
	if not okA or not okB then return end

	local function row(b, sectionTitle, label)
		for _, sec in b.sections do
			if sec.title == sectionTitle then
				for _, r in sec.rows do if r[1] == label then return r[2] end end
			end
		end
		return nil
	end
	------------------------------------------------------------------ briefing
	for state, ui in results do
		local s = ui.session
		local e = s.data.empire
		local b = Assistant.briefing(s)
		local titles = {}
		for _, sec in b.sections do table.insert(titles, sec.title) end
		check(state .. ": sections Today, Customers, Money, Models first", titles[1] == "Today" and titles[2] == "Customers" and titles[3] == "Money" and titles[4] == "Models", table.concat(titles, ","))
		check(state .. ": Training, Research and Team stay", table.find(titles, "Training") and table.find(titles, "Research") and table.find(titles, "Team"))
		local clock = G.workspace:GetServerTimeNow()
		check(state .. ": company day + visible hour", row(b, "Today", "Company day") == Format.dayClock(Ops.day(e), Ops.hour(clock)), row(b, "Today", "Company day"))
		-- presence counts from CompanyOps.presence
		local vac, sick = 0, 0
		for _, role in EmpireConfig.ROLES do for _, st in Ops.presence(e, role.id) do if st == "vacation" then vac += 1 elseif st == "sick" then sick += 1 end end end
		local team = row(b, "Today", "Team") or ""
		if EmpireMath.staff(e) == 0 then
			check(state .. ": nobody hired yet", string.find(team, "Nobody hired yet", 1, true) ~= nil, team)
		else
			check(state .. ": vacation count = CompanyOps.presence", (vac == 0 and string.find(team, "vacation", 1, true) == nil) or string.find(team, vac .. " on vacation", 1, true) ~= nil, team)
			check(state .. ": sick count = CompanyOps.presence", (sick == 0 and string.find(team, "sick", 1, true) == nil) or string.find(team, sick .. " sick", 1, true) ~= nil, team)
		end
		-- money: today's P&L = ledger sums
		local entry = e.ledger[tostring(Ops.day(e))]
		local inc, out = 0, 0
		if entry then for _, v in entry.i or {} do inc += v end; for _, v in entry.o or {} do out += v end end
		local today = row(b, "Money", "Today") or ""
		if inc + out == 0 then check(state .. ": empty day", today == "Nothing booked yet today.", today)
		else check(state .. ": today's P&L = ledger sums", today == string.format("income %s · costs %s · net %s", Ops.money(inc), Ops.money(out), Ops.money(inc - out)), today) end
		-- accounts + retainers
		local n, ret = 0, 0
		for id in e.deals.accounts do n += 1; ret += Ops.client(id).retainer end
		local acc = row(b, "Customers", "Accounts") or ""
		if n == 0 then check(state .. ": no account yet", acc == "No business client yet.", acc)
		else check(state .. ": accounts + retainer/day", acc == string.format("%d of %d slots · %s/day in retainers", n, Ops.accountLimit(e), Ops.money(ret)), acc) end
		-- first recommendation = the Next goal
		local goal = EmpireMath.nextGoal(s.data, s.live)
		check(state .. ": recommendation 1 is the Next goal", goal ~= nil and string.sub(b.recommendations[1].text, 1, #goal.text) == goal.text
			or (goal and goal.id == "release" and string.find(b.recommendations[1].text, "Release", 1, true) == 1), b.recommendations[1].text)
		check(state .. ": insight = recommendation 1", Assistant.insight(s) == b.recommendations[1].text)
		check(state .. ": at most 3 recommendations", #b.recommendations <= 3)
	end
	if results.mid then
		local s = results.mid.session
		local b = Assistant.briefing(s)
		local trips = row(b, "Today", "Trips") or ""
		check("mid: trip with hotel and return time", string.find(trips, "rep + engineer at PixelForge (pilot, back ", 1, true) ~= nil and string.find(trips, "City Hotel $140", 1, true) ~= nil, trips)
		check("mid: renewal under way named", string.find(row(b, "Customers", "Renewals") or "", "ByteWorks (check-in under way)", 1, true) ~= nil, row(b, "Customers", "Renewals"))
		check("mid: pipeline with best lead trust", string.find(row(b, "Customers", "Pipeline") or "", "StudySpark trust 62 %", 1, true) ~= nil, row(b, "Customers", "Pipeline"))
		check("mid: servers row", string.find(row(b, "Models", "Servers") or "", "% full", 1, true) ~= nil, row(b, "Models", "Servers"))
		check("mid: live lines", string.find(row(b, "Models", "Live lines") or "", "2 of 3: Consumer Chat Nova v3", 1, true) ~= nil, row(b, "Models", "Live lines"))
		check("mid: oldest line with lost fit", string.find(row(b, "Models", "Oldest line") or "", "Your Developer API line is 41 min old (-5 fit)", 1, true) ~= nil, row(b, "Models", "Oldest line"))
		check("mid: operations staff row", string.find(row(b, "Today", "Operations") or "", "14 operations staff", 1, true) ~= nil, row(b, "Today", "Operations"))
		-- a pending training decision comes before the goal
		s.data.training = { modelId = "nova3", workTotal = 100, workDone = 50, cost = 0, expected = 40, qualityMod = 1, eventRolled = true, epoch = 1, loss = {}, log = {}, event = { id = "data_issue", pending = true, expiresAt = 0 } }
		local b2 = Assistant.briefing(s)
		check("pending decision first, then the goal", string.find(b2.recommendations[1].text, "training event", 1, true) ~= nil and string.find(b2.recommendations[2].text, "Innovation Campus", 1, true) == 1, b2.recommendations[2] and b2.recommendations[2].text)
		s.data.training = nil
	end
	if results.rich then
		local b = Assistant.briefing(results.rich.session)
		check("rich: waitlist with the cooling hint", string.find(row(b, "Models", "Servers") or "", "waiting", 1, true) ~= nil, row(b, "Models", "Servers"))
		check("rich: hosted client team in the trips", string.find(row(b, "Today", "Trips") or "", "Mosaic Worlds team at the guest house", 1, true) ~= nil, row(b, "Today", "Trips"))
		check("rich: growth effect row", row(b, "Models", "Growth") ~= nil)
		check("rich: goal recommendation says how far the lines are", string.find(b.recommendations[1].text, "All 4 lines at 90+: 1 of 4 lines are there.", 1, true) == 1, b.recommendations[1].text)
	end
	if results.garage then
		local g = Assistant.briefing(results.garage.session)
		check("garage: data recommendation names the tokens", string.find(g.recommendations[1].text, "Train your first AI", 1, true) == 1 and string.find(g.recommendations[1].text, "tokens", 1, true) ~= nil, g.recommendations[1].text)
		check("garage: Data & hardware before the first release", (function() for _, sec in g.sections do if sec.title == "Data & hardware" then return true end end; return false end)())
	end

	------------------------------------------------------------------ screens
	local Instance, CFrame, Vector3 = G.Instance, G.CFrame, G.Vector3
	local function office(tier, rooms)
		local o = Instance.new("Model"); o.Name = "Office"
		o:SetAttribute("OfficeTier", tier); o:SetAttribute("CampusCFrame", CFrame.new())
		o:SetAttribute("HotelRooms", 12); o:SetAttribute("HotelGuests", 9)
		local folder = Instance.new("Folder"); folder.Name = "Rooms"; folder.Parent = o
		local screens = {}
		for _, def in rooms do
			local m = Instance.new("Model"); m.Name = def[1]; m:SetAttribute("RoomId", def[1]); m:SetAttribute("RoomName", def[1]); m:SetAttribute("Level", 0); m.Parent = folder
			local p = Instance.new("Part"); p.Name = "Screen_" .. def[2]; p:SetAttribute("LiveScreen", def[2]); p.Parent = m
			local gui = Instance.new("SurfaceGui"); gui.Name = "Desktop"; gui.Parent = p
			screens[def[1] .. ":" .. def[2]] = p
		end
		return o, screens
	end
	local o, sc = office(2, { { "G_LOBBY", "reception" }, { "H0_LOBBY", "reception" }, { "B1_DATAHALL", "compute" }, { "L1_EI4", "customers" }, { "B1_FLEET", "operations" }, { "F_HR", "hr" } })
	o.Parent = G.workspace
	local function present(s, kind, key)
		local ok, h, b, f, fill = pcall(Screens.presentation, s, kind, nil, if key then sc[key] else nil)
		if not ok then return "ERROR " .. tostring(h), "", "", 0 end
		return h, b, f, fill
	end
	local function fits(label, h, b, f, fill)
		local visual = 0
		for line in (b .. "\n"):gmatch("(.-)\n") do visual += math.max(1, math.ceil((utf8.len(line) or #line) / 52)) end
		check(label .. ": fits the screen (<= 10 lines, header <= 40, footer <= 72)", visual <= 10 and (utf8.len(h) or #h) <= 40 and (utf8.len(f) or #f) <= 72 and typeof(fill) == "number" and fill == fill,
			string.format("%d lines, header %d, footer %d", visual, utf8.len(h) or #h, utf8.len(f) or #f))
	end
	local all = {}
	for state, ui in results do
		local s = ui.session
		for _, def in { { "compute", "B1_DATAHALL:compute" }, { "customers", "L1_EI4:customers" }, { "reception", "G_LOBBY:reception" }, { "reception", "H0_LOBBY:reception" },
			{ "operations", "B1_FLEET:operations" }, { "hr", "F_HR:hr" }, { "growth" }, { "platform" }, { "lobby" }, { "training" } } do
			local h, b, f, fill = present(s, def[1], def[2])
			check(state .. " " .. def[1] .. (def[2] or "") .. ": no error", string.sub(h, 1, 5) ~= "ERROR", h)
			fits(state .. " " .. def[1] .. " " .. (def[2] or ""), h, b, f, fill)
			table.insert(all, h .. "\n" .. b .. "\n" .. f)
		end
	end
	local joined = table.concat(all, "\n")
	check("no screen shows the old lease texts (API customers / leases / API leases)", string.find(joined, "API customers", 1, true) == nil and string.find(joined, "lease", 1, true) == nil or string.find(joined, "Field cars leased", 1, true) ~= nil and string.find(joined, "from leases", 1, true) == nil and string.find(joined, "API leases", 1, true) == nil)
	if results.mid then
		local s = results.mid.session
		local h, b = present(s, "compute", "B1_DATAHALL:compute")
		check("data hall: rack fault header", h == "DATA HALL · RACK FAULT", h)
		check("data hall: fault line, IT on duty but nobody assigned yet", string.find(b, "Rack R2 fault · Workstation GPU · waiting for IT", 1, true) ~= nil, b)
		-- who repairs it (staffops request #8): the blade attributes FaultWorker / FaultFix of StaffEvents
		do
			local office = G.Instance.new("Model"); office.Name = "Office"
			local blades = G.Instance.new("Folder"); blades.Name = "Blades"; blades.Parent = office
			local list = {}
			for i = 1, 3 do local p = G.Instance.new("Part"); p.Name = "Blade" .. i; p.Parent = blades; list[i] = p end
			local screen = G.Instance.new("Part"); screen.Name = "Screen"; screen.Parent = office
			local function hall() local ok, h2, b2 = pcall(Screens.presentation, s, "compute", nil, screen); return if ok then b2 else tostring(h2) end
			list[2]:SetAttribute("FaultWorker", "IT Support"); list[2]:SetAttribute("FaultFix", "remote")
			check("data hall: IT doing a remote fix", string.find(hall(), "Rack R2 fault · Workstation GPU · IT Support · remote fix", 1, true) ~= nil, hall())
			list[2]:SetAttribute("FaultWorker", "ML Engineer"); list[2]:SetAttribute("FaultFix", "walk")
			check("data hall: engineer on the way", string.find(hall(), "ML Engineer on the way", 1, true) ~= nil, hall())
			list[2]:SetAttribute("FaultFix", "rack")
			check("data hall: engineer repairing at the rack", string.find(hall(), "ML Engineer repairing", 1, true) ~= nil, hall())
			office:Destroy()
		end
		check("data hall: reserved compute for 5 accounts", string.find(b, string.format("Reserved for clients %.1f units · 5 accounts", s.live.compute.reserved), 1, true) ~= nil, b)
		check("data hall: load %", string.find(b, string.format("Servers %d%% full", math.floor(s.live.load / s.live.capacity * 100 + 0.5)), 1, true) ~= nil, b)
		-- which model uses the serving compute: users x SERVE_UNITS (both 1B: Nova 43.4K users, Coder 16.5K users)
		check("data hall: serving share per live model", string.find(b, "Serving  Nova v3 72% · Coder v2 28%", 1, true) ~= nil, b)
		h, b = present(s, "customers", "L1_EI4:customers")
		check("clients screen: accounts + retainer/day", h == "BUSINESS CLIENTS" and string.find(b, "Accounts 5 / 7 · $72,000/day", 1, true) ~= nil, b)
		check("clients screen: account end day", string.find(b, "CloudDesk · $9,000/day · until day 14", 1, true) ~= nil, b)
		check("clients screen: renewing account", string.find(b, "ByteWorks · $13,500/day · check-in under way", 1, true) ~= nil, b)
		h, b = present(s, "reception", "G_LOBBY:reception")
		check("reception: today's trips", string.find(b, "Trip  Rep + engineer → PixelForge (pilot)", 1, true) ~= nil and string.find(b, "Trip  Rep → ByteWorks (check-in)", 1, true) ~= nil, b)
		check("reception: company day and team in today", string.find(b, "Day 10 · 10:30 · team", 1, true) ~= nil, b)
		h, b = present(s, "reception", "H0_LOBBY:reception")
		check("guest-house reception: rooms and guests (office attributes)", h == "GUEST HOUSE · RECEPTION" and string.find(b, "Rooms 12 · guests tonight 9", 1, true) ~= nil, b)
		h, b = present(s, "operations", "B1_FLEET:operations")
		check("fleet office: leased field cars = field reps", h == "FLEET OPERATIONS" and string.find(b, string.format("Field cars leased %d", Ops.fieldReps(s.data.empire)), 1, true) ~= nil, b)
		h, b = present(s, "hr", "F_HR:hr")
		check("HR screen: operations staff from CompanyOps", string.find(b, "14 operations staff", 1, true) ~= nil and string.find(b, "Growth & Sales  ", 1, true) ~= nil and string.find(b, "Saless", 1, true) == nil, b)
		h, b = present(s, "platform")
		check("platform: business clients + reserved compute", string.find(b, "Business clients  5", 1, true) ~= nil, b)
	end
	if results.rich then
		local h, b = present(results.rich.session, "reception", "H0_LOBBY:reception")
		check("guest-house reception names the hosted client team", string.find(b, "Client teams in house  Mosaic Worlds", 1, true) ~= nil, b)
	end
	if results.garage then
		local h = present(results.garage.session, "compute", "B1_DATAHALL:compute")
		check("garage data hall: idle + no IT desk", h == "DATA HALL · IDLE", h)
	end

	------------------------------------------------------------------ SecurityController (client): floor titles by plan tier
	if results.garage then
		local ui = results.garage
		local Client = game.StarterPlayer.StarterPlayerScripts.Client
		local okS, Security = pcall(M.require, Client.Controllers.SecurityController)
		check("SecurityController loads", okS, Security)
		if okS then
			local okI, errI = pcall(Security.init)
			check("SecurityController.init runs", okI, errI)
			local camera = G.workspace.CurrentCamera or Instance.new("Camera")
			if not G.workspace.CurrentCamera then camera.Parent = G.workspace; pcall(function() G.workspace.CurrentCamera = camera end) end
			local notify = game.ReplicatedStorage.Remotes:FindFirstChild("Notify")
			local function open(office)
				ui.session.data.empire.office = office
				ui.push()
				M.fire(notify.OnClientEvent, "SECURITY_OPEN", { ownerId = 4242, channels = { { id = "c1", name = "Garage door", cframe = CFrame.new(0, 5, 0), level = 0 } } })
				M.settle(0.5)
				local gui = ui.playerGui:FindFirstChild("CampusSecurity")
				local title = nil
				if gui then for _, x in gui:GetDescendants() do if x:IsA("TextLabel") and string.find(x.Text, "Garage door", 1, true) and string.find(x.Text, "01 / 01", 1, true) then title = x.Text end end end
				local labels = {}
				if gui then for _, x in gui:GetDescendants() do if x:IsA("TextButton") then table.insert(labels, x.Text) end end end
				return title, labels
			end
			local title, labels = open(1)
			local want = Plan.floorTitle(0, 0)
			check("garage (office 1): camera title uses plan tier 0", title ~= nil and string.find(title, want, 1, true) ~= nil, tostring(title) .. " / want " .. want)
			check("security buttons in English", table.find(labels, "Back") ~= nil and (table.find(labels, "← Previous") ~= nil) and table.find(labels, "Zurück") == nil, table.concat(labels, ","))
			pcall(Security.close)
			title = open(3)
			check("Startup Campus (office 3): plan tier 2 title", title ~= nil and string.find(title, Plan.floorTitle(2, 0), 1, true) ~= nil, title)
			pcall(Security.close)
		end
	end
end

setfenv(body, M.envFor(nil))
local ok, res = M.runMain(body, { timeout = 900 })
if not ok then failc += 1; print("FAIL  body crashed: " .. tostring(res)) end
if M.stats.errors > 0 then failc += 1; print("FAIL  background errors: " .. M.stats.errors) end
print(string.format("apps_server_%s: %d passed, %d failed", STATE, pass, failc))
