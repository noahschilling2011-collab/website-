--!nocheck
-- apps package, adversarial scenarios (ported from the independent review agents/review_apps/test_adv.luau and
-- extended for every issue of that review). One scenario per process, states of tests/apps/ui_setup.luau:
--   garage_edge  garage, cash < 0, the only released model no longer live, founder's own visit (no Join button)
--   stage5       Global AI HQ, every goal done, rack full of HBM GPUs at cooling 8/8 + waitlist: no "buy GPUs"
--   rackfull     Startup Campus rack full (12/12) + waitlist: no "buy GPUs", the next office / cluster / swap instead;
--                then heat-limited at cooling 8/8: never "upgrade cooling"; then heat-limited at cooling 1: "upgrade
--                cooling first"; positive control with free slots: "buy GPUs"; ComputeApp and briefing agree
--   oldsave      first snapshot after a join: no live.ops / compute / capacity, empty ledger, nil settings
--   many         400 staff / 60 apprentices: CPU per snapshot and GuiObject churn per tab (Money: none)
--   spam         100 ms round trips + the REAL rate limiter: night shift for three roles, Pin double tap, two
--                switches in a row, Pin then Join (one lane per remote)
--   midnight     company clock 07:59 (the game day wraps at 08:00): trip return text, new-day ledger
--   broke        losing money at stage 3: HUD advice, safety badge / lines (paused trips, unpaid leave), briefing
--   hr           the Automatic HR status line for every reason of EmpireService.autoHire / CompanyOps.hrAllowed
-- Run: cd tests/apps && ../../tools/luau test_adv.luau -a .gen_apps <scenario>
local realClock = os.clock
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_apps")
local SCEN = args[2] or "garage_edge"
local M = require("../../harness/mock")
local setup = require("./ui_setup")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end
local VERBOSE = os.getenv and os.getenv("APPS_VERBOSE") == "1"
local function note(s) if VERBOSE then print("NOTE  " .. s) end end

local base = ({ rackfull = "mid", garage_edge = "garage", stage5 = "rich", oldsave = "mid", many = "rich", spam = "mid", midnight = "mid", broke = "mid", hr = "mid" })[SCEN] or "mid"

local function body()
	local RL = M.require(M.game.ServerScriptService.Server.Lib.RateLimiter)
	local realNew = RL.new -- ui_setup replaces RateLimiter.new; the spam scenario uses the real one
	local ui = setup(M, GEN, base, 1280, 720, { top = 58, right = 0, bottom = 0, left = 0 }, {})
	local game = M.game
	local RS = game.ReplicatedStorage
	local Client = game.StarterPlayer.StarterPlayerScripts.Client
	local s = ui.session
	local d = s.data
	local e = d.empire
	local pg = ui.playerGui
	local EmpireMath = M.require(RS.Shared.EmpireMath)
	local Ops = M.require(RS.Shared.CompanyOps)
	local ModelMath = M.require(RS.Shared.ModelMath)
	local HardwareConfig = M.require(RS.Shared.Config.HardwareConfig)
	local State = M.require(Client.Controllers.StateController)
	local EmpireApp = M.require(Client.UI.Apps.EmpireApp)
	local ComputeApp = M.require(Client.UI.Apps.ComputeApp)
	local Theme = M.require(Client.UI.Theme)
	local Toast = ui.Toast
	local HUD = ui.HUD
	local Assistant = M.require(game.ServerScriptService.Server.Services.AssistantService)

	local function visible(inst)
		local x = inst
		while x and x ~= pg do
			if (x:IsA("GuiObject") and not x.Visible) or (x:IsA("ScreenGui") and not x.Enabled) then return false end
			x = x.Parent
		end
		return true
	end
	local function texts(root)
		local out = {}
		for _, x in (root or pg):GetDescendants() do
			if (x:IsA("TextLabel") or x:IsA("TextButton")) and visible(x) and x.Text ~= "" then table.insert(out, x.Text) end
		end
		return out
	end
	local function has(needle, root)
		for _, t in texts(root) do if string.find(t, needle, 1, true) then return t end end
		return nil
	end
	local function find(name, root)
		for _, x in (root or pg):GetDescendants() do if x.Name == name and visible(x) then return x end end
		return nil
	end
	local function button(text, root)
		for _, x in (root or pg):GetDescendants() do
			if x:IsA("TextButton") and visible(x) and x.Text == text then return x end
		end
		return nil
	end
	local function click(b, wait)
		if not b then return false end
		M.fire(b.Activated, {}, 1)
		M.settle(wait or 0.4)
		return true
	end
	local function openTab(id)
		ui.Computer.open("empire", id)
		M.settle(0.4)
		ui.push()
		return find("Tab_" .. id)
	end
	local function rowOf(name)
		for _, x in pg:GetDescendants() do
			if x:GetAttribute("Group") ~= nil and visible(x) then
				for _, y in x:GetDescendants() do if y:IsA("TextLabel") and y.Text == name then return x end end
			end
		end
		return nil
	end
	local toasts = {}
	local origShow = Toast.show
	Toast.show = function(kind, text, ...) table.insert(toasts, kind .. ": " .. tostring(text)); return origShow(kind, text, ...) end
	local function brief()
		local ok, b = pcall(Assistant.briefing, s)
		check("briefing builds", ok, b)
		if not ok then return nil end
		return b
	end
	local function row(b, sec, label)
		for _, x in b.sections do if x.title == sec then for _, r in x.rows do if r[1] == label then return r[2] end end end end
		return nil
	end
	local function recsOf(b)
		local out = {}
		for _, r in b.recommendations do table.insert(out, r.text) end
		return table.concat(out, " || ")
	end
	local function errors() return M.stats.errors end
	-- the waitlist advice of the Hardware app and of the briefing, for the current state
	local function adviceBoth()
		ui.Computer.open("compute"); M.settle(0.5); ui.push()
		local w = find("Waitlist")
		local b = brief()
		ui.Computer.close(); M.settle(0.4)
		return w, b
	end

	if SCEN == "garage_edge" then
		d.money = -2500
		s.live.revenue, s.live.cost = 0, 0.5
		ui.push()
		local hud = pg:FindFirstChild("AIEmpire_HUD")
		check("negative cash: HUD shows the net per day in red", find("NetPerDay", hud) and find("NetPerDay", hud).Text == "-$600/day", find("NetPerDay", hud) and find("NetPerDay", hud).Text)
		check("negative cash: safety badge 'CASH BELOW $0'", find("Safety", hud) and find("Safety", hud).Text == "CASH BELOW $0", find("Safety", hud) and find("Safety", hud).Text)
		-- one model was released, then it stopped being live: goal = client, best live = 0
		d.stats.modelsTrained, d.stats.modelsReleased = 1, 1
		d.data = { general = { tokens = 1.5e9, quality = 0.7 } }
		local stats = { reasoning = 30, coding = 26, math = 24, creativity = 34, knowledge = 31, reliability = 31, speed = 80, efficiency = 80 }
		d.models.nova1 = { id = "nova1", name = "Nova", version = 1, sizeId = "s100m", focusId = "balanced", status = "trained", createdAt = 0, trainedAt = 0, stats = stats, overall = ModelMath.overall(stats), trainCost = 1, dataUsed = { total = 1e9, quality = 0.7, shares = { general = 1 } } }
		table.insert(d.modelOrder, "nova1")
		d.money = 4000
		ui.push()
		local v = HUD.describe(State.snapshot)
		check("client goal while no model is live", v.id == "client", v.id)
		check("HUD hint never says 'best live model: 0' (asks for a release)", string.find(v.body, "best live model: 0", 1, true) == nil and string.find(v.body, "release one first", 1, true) ~= nil, v.body)
		check("HUD tap goes to the release screen", v.app == "lab" and v.section == "release")
		local b = brief()
		if b then
			check("briefing never says 'best live model: 0'", string.find(recsOf(b), "best live model: 0", 1, true) == nil and string.find(recsOf(b), "No model is live", 1, true) ~= nil, recsOf(b))
		end
		openTab("clients")
		check("Clients tab: CloudDesk says release a model first", has("Needs reliability 24 · release a model first") ~= nil)
		check("Clients tab: group heading 'Needs a live model'", has("Needs a live model (") ~= nil and has("Needs a better model") == nil)
		-- the founder's own pilot visit is under way: no Join button (the founder is the visit), a countdown in words
		e.deals.tripList = { { client = "helpdesk", kind = "sign", back = (e.seconds or 0) + 200, founder = true, hosted = false, crew = 1, left = 0 } }
		d.models.nova1.status = "live"
		d.models.nova1.release = { subPrice = 10, apiPrice = 2, marketing = 0, target = "general", releasedAt = 0, auto = true }
		ui.push()
		openTab("clients")
		local cloud = rowOf("CloudDesk")
		check("founder's own visit: no 'Join in person' button", cloud ~= nil and not cloud:FindFirstChild("Join", true).Visible)
		check("founder's own visit: status with a countdown in words", has("You are on the pilot visit · back in 3 min 20 s") ~= nil, has("You are on the pilot visit"))
		openTab("settings")
		check("garage: night shift locked text", has("Night shifts start at the") ~= nil)
		check("garage: apprentices locked text", has("Apprentices start at the") ~= nil)
		check("garage: jet locked", has("Needs the Innovation Campus") ~= nil)
		check("no background errors", errors() == 0, errors())

	elseif SCEN == "stage5" then
		e.office = 5
		e.jet = true
		e.labLevel = Ops.LAB_MAX
		for _, id in d.modelOrder do
			local m = d.models[id]
			if m.status == "live" then for k, val in m.stats do m.stats[k] = math.max(val, 95) end; m.overall = ModelMath.overall(m.stats) end
		end
		ui.push()
		local v = HUD.describe(State.snapshot)
		check("stage 5 + every goal done: 'Every goal reached'", v.title == "Every goal reached", v.title .. " / " .. v.id)
		local slots = HardwareConfig.slots(e)
		d.gpus = { laptop = 1, datacenter = 0 }
		while ModelMath.fleet(d.gpus).slotsUsed < slots do d.gpus.datacenter += 1 end
		e.infrastructure.cooling = 8
		s.live.waitlist = 250000
		s.live.load = math.floor((s.live.capacity or 1e6) * 1.3)
		ui.push()
		check("rack is full", ModelMath.fleet(d.gpus).slotsUsed >= slots)
		local w, b = adviceBoth()
		note("stage5 waitlist: " .. tostring(w and w.Text))
		check("stage 5 full rack at 8/8: no 'buy GPUs' in the Hardware app", w ~= nil and string.find(w.Text, "buy GPUs", 1, true) == nil, w and w.Text)
		check("stage 5 at 8/8: no 'upgrade cooling' in the Hardware app", w ~= nil and string.find(w.Text, "upgrade cooling", 1, true) == nil, w and w.Text)
		check("stage 5: the real limit is named (largest office, raise prices)", w ~= nil and (string.find(w.Text, "largest office", 1, true) ~= nil) and string.find(w.Text, "aise prices", 1, true) ~= nil, w and w.Text)
		if b then
			local servers = row(b, "Models", "Servers") or ""
			check("stage 5: briefing never promises a GPU serves more users", string.find(servers, "serves", 1, true) == nil and string.find(recsOf(b), "buy GPUs", 1, true) == nil, servers .. " / " .. recsOf(b))
			check("stage 5: briefing never says 'upgrade cooling'", string.find(servers .. recsOf(b), "upgrade cooling", 1, true) == nil)
		end
		ui.Computer.open("compute"); M.settle(0.5); ui.push()
		check("full rack: buy buttons say RACK FULL", has("RACK FULL") ~= nil)
		check("cooling button at maximum", has("COOLING AT MAXIMUM (8 / 8)") ~= nil)
		ui.Computer.close(); M.settle(0.4)
		openTab("settings")
		check("jet owned card", has("Owned. Parked in the airport hangar") ~= nil)
		check("Lab level max text", has("the highest level") ~= nil)
		openTab("office")
		check("office: maximum reached", has("Maximum office reached") ~= nil)
		check("no background errors", errors() == 0, errors())

	elseif SCEN == "rackfull" then
		-- positive control first: a free slot and users waiting -> "buy GPUs"
		s.live.waitlist = 12000
		s.live.load = math.floor((s.live.capacity or 1e5) * 1.2)
		ui.push()
		local a0 = ComputeApp.advice(d, d.money)
		check("free slot: advice 'buy' with a GPU that adds users", a0.kind == "buy" and a0.gpu ~= nil and a0.extra >= 1, a0.kind)
		local w, b = adviceBoth()
		check("free slot: Hardware app says buy GPUs (control)", w ~= nil and string.find(w.Text, "buy GPUs", 1, true) ~= nil, w and w.Text)
		-- capacity counts 500M-model user equivalents: the hint converts them into real users (demand / load)
		local Format = M.require(RS.Shared.Format)
		local perUnit = s.live.demand / s.live.load
		check("users per capacity unit = demand / load", math.abs(ComputeApp.usersPerUnit(s.live) - perUnit) < 1e-9 and perUnit < 1, perUnit)
		check("buy hint counts real users (extra x demand / load)", w ~= nil and string.find(w.Text, "serves " .. Format.int(a0.extra * perUnit) .. " more users", 1, true) ~= nil, w and w.Text)
		check("briefing uses the same real-user number", b ~= nil and string.find(row(b, "Models", "Servers") or "", Format.int(a0.extra * perUnit), 1, true) ~= nil, b and row(b, "Models", "Servers"))
		-- rack full with Consumer GPUs (no cooling limit)
		local slots = HardwareConfig.slots(e)
		while ModelMath.fleet(d.gpus).slotsUsed < slots do d.gpus.consumer = (d.gpus.consumer or 0) + 1 end
		ui.push()
		local a1 = ComputeApp.advice(d, d.money)
		local a1s = Assistant._computeAdvice(d, d.money)
		check("full rack: advice kind 'rack' in both the app and the briefing", a1.kind == "rack" and a1s.kind == "rack", a1.kind .. "/" .. a1s.kind)
		check("full rack: the swap gain is computed for the weakest GPU", a1.weakest == "consumer" and a1.gpu ~= nil and a1.extra >= 1 and a1.extra == a1s.extra, tostring(a1.weakest) .. " " .. tostring(a1.gpu) .. " " .. a1.extra)
		w, b = adviceBoth()
		note("rack full: " .. tostring(w and w.Text))
		check("full rack: waitlist hint never says 'buy GPUs'", w ~= nil and string.find(w.Text, "buy GPUs", 1, true) == nil, w and w.Text)
		check("full rack: names the next office, Distributed Cluster and the swap", w ~= nil and string.find(w.Text, "rack full (12 / 12)", 1, true) ~= nil and string.find(w.Text, "Innovation Campus (24 slots)", 1, true) ~= nil
			and string.find(w.Text, "Distributed Cluster", 1, true) ~= nil and string.find(w.Text, "swap a Consumer GPU for an ", 1, true) ~= nil, w and w.Text)
		check("articles: 'an AI Accelerator', never 'a AI'", ComputeApp.article("AI Accelerator") == "an AI Accelerator" and ComputeApp.article("Workstation GPU") == "a Workstation GPU" and (w == nil or string.find(w.Text, " a AI", 1, true) == nil))
		if b then
			local servers = row(b, "Models", "Servers") or ""
			check("full rack: briefing has no 'buy GPUs' and names the rack", string.find(servers .. recsOf(b), "buy GPUs", 1, true) == nil and string.find(servers, "rack full", 1, true) ~= nil, servers)
		end
		ui.Computer.open("compute"); M.settle(0.5); ui.push()
		check("full rack: buy buttons say RACK FULL", has("RACK FULL") ~= nil)
		ui.Computer.close(); M.settle(0.4)
		-- heat-limited at cooling 1: "upgrade cooling first" (with its price)
		while HardwareConfig.thermal(e, ModelMath.fleet(d.gpus).throughput) >= 1 do d.gpus.datacenter = (d.gpus.datacenter or 0) + 1; d.gpus.consumer = math.max(0, (d.gpus.consumer or 0) - 1) end
		ui.push()
		local a2 = ComputeApp.advice(d, d.money)
		check("heat-limited, cooling 1: advice 'cooling'", a2.kind == "cooling" and Assistant._computeAdvice(d, d.money).kind == "cooling", a2.kind)
		w, b = adviceBoth()
		check("heat-limited, cooling 1: says upgrade cooling first with the price", w ~= nil and string.find(w.Text, "upgrade cooling first (level 1 / 8, " .. M.require(RS.Shared.Format).money(8000) .. ")", 1, true) ~= nil, w and w.Text)
		-- heat-limited at cooling 8/8: never "upgrade cooling"
		e.infrastructure.cooling = 8
		while HardwareConfig.thermal(e, ModelMath.fleet(d.gpus).throughput) >= 1 do d.gpus.datacenter = (d.gpus.datacenter or 0) + 1; d.gpus.consumer = math.max(0, (d.gpus.consumer or 0) - 1) end
		ui.push()
		local a3 = ComputeApp.advice(d, d.money)
		check("heat-limited at 8/8: advice 'maxed'", a3.kind == "maxed" and Assistant._computeAdvice(d, d.money).kind == "maxed", a3.kind)
		w, b = adviceBoth()
		note("cooling maxed: " .. tostring(w and w.Text))
		check("cooling 8/8: the hint never says 'upgrade cooling'", w ~= nil and string.find(w.Text, "upgrade cooling", 1, true) == nil and string.find(w.Text, "cooling is maxed (8 / 8)", 1, true) ~= nil, w and w.Text)
		if b then
			check("cooling 8/8: briefing never says 'upgrade cooling'", string.find(recsOf(b) .. (row(b, "Models", "Servers") or ""), "upgrade cooling", 1, true) == nil, recsOf(b))
		end
		check("no background errors", errors() == 0, errors())

	elseif SCEN == "oldsave" then
		s.live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} }
		e.ledger = {}
		e.deals.news = {}
		e.apprentices = nil
		e.nightShift = nil
		e.hr = nil
		e.calendar = nil
		ui.push()
		local hud = pg:FindFirstChild("AIEmpire_HUD")
		local card = find("NextGoal", hud)
		check("HUD goal still shown", card ~= nil and find("Title", card).Text ~= "")
		for _, tab in { "overview", "clients", "money", "team", "research", "milestones", "office", "settings", "board" } do
			local before = errors()
			local ok = pcall(openTab, tab)
			check("tab " .. tab .. " renders without errors", ok and errors() == before, errors())
		end
		openTab("money")
		check("empty ledger: Nothing booked yet today", has("Nothing booked yet today.") ~= nil)
		check("empty ledger: no '+$0' anywhere", has("+$0") == nil, has("+$0"))
		check("no rates yet: 'Rates appear after the first update'", has("Rates appear after the first update.") ~= nil)
		openTab("overview")
		check("overview chart never labels per minute", has("/ min") == nil and has("$1 /") == nil)
		openTab("clients")
		check("empty log text", has("Nothing happened yet.") ~= nil)
		ui.Computer.open("compute"); M.settle(0.5); ui.push()
		check("compute renders without live.compute", errors() == 0, errors())
		ui.Computer.close(); M.settle(0.4)
		local b = brief()
		if b then
			check("briefing: Today row with the day fallback", row(b, "Today", "Company day") ~= nil)
			check("briefing: running rate empty state", row(b, "Money", "Running now") == "no income or costs yet", row(b, "Money", "Running now"))
		end
		check("no background errors", errors() == 0, errors())

	elseif SCEN == "many" then
		local counts = { researcher = 140, engineer = 120, curator = 60, marketer = 80 }
		e.employees = counts
		EmpireMath.syncProfiles(e, 4242)
		e.apprentices = {}
		for _, role in { "researcher", "engineer", "curator", "marketer" } do
			for i = 1, 15 do
				local p = e.staffProfiles[role][i]
				e.apprentices[tostring(p.s)] = { day = Ops.day(e) - (i % 8) }
			end
		end
		ui.push()
		local function timeIt(label, fn, reps)
			local t0 = realClock()
			for _ = 1, reps or 1 do fn() end
			local dt = (realClock() - t0) / (reps or 1) * 1000
			note(string.format("%s: %.2f ms", label, dt))
			return dt
		end
		for _, tab in { "clients", "money", "settings", "team" } do
			openTab(tab)
			local created = 0
			local conn = pg.DescendantAdded:Connect(function(x) if x:IsA("GuiObject") then created += 1 end end)
			local dt = timeIt("tab " .. tab .. ": one snapshot (400 staff)", function()
				local key = tostring(Ops.day(e))
				local entry = e.ledger[key] or { i = {}, o = {} }
				e.ledger[key] = entry
				entry.i.market = (entry.i.market or 0) + 37
				entry.o.wages = (entry.o.wages or 0) + 29
				s.live.revenue += 0.37
				ui.push()
			end, 20)
			conn:Disconnect()
			check("tab " .. tab .. ": snapshot update < 8 ms", dt < 8, dt)
			check("tab " .. tab .. ": no GuiObject churn over 20 snapshots (ledger + rates move)", created == 0, created)
		end
		-- a segmented control per rebuilt tab must not keep its accent callback (Theme.onAccent leak)
		openTab("settings")
		local n0 = Theme.listenerCount()
		for _ = 1, 5 do openTab("money"); openTab("settings") end
		check("Theme accent listeners do not grow with re-rendered tabs", Theme.listenerCount() == n0, n0 .. " -> " .. Theme.listenerCount())
		local b
		local dtb = timeIt("AssistantService.briefing (400 staff)", function() b = Assistant.briefing(s) end, 10)
		check("briefing with 400 staff < 8 ms", b ~= nil and dtb < 8, dtb)
		check("no background errors", errors() == 0, errors())

	elseif SCEN == "spam" then
		-- every InvokeServer takes 100 ms; the real per-player token buckets of EmpireService.init
		local limits = { EmpireAction = { 4, 2 }, DealAction = { 4, 2 }, HireEmployee = { 3, 1 } }
		local buckets = {}
		for name, l in limits do buckets[name] = realNew(l[1], l[2]) end
		local G = M.G
		local player = s.player
		local results = {}
		local function patch(cls, name, fn) M.IMPL[cls].methods[name] = fn; M.classInfo(cls).methods[name] = fn end
		patch("RemoteFunction", "InvokeServer", function(self, payload)
			if self.Name == "RequestState" then return { ok = true, state = { saveEnabled = false, serverTime = ui.base + M.Sched.now, data = M.require(game.ServerScriptService.Server.Services.SessionService).replicatedData(d), live = s.live } } end
			G.task.wait(0.05)
			local bucket = buckets[self.Name]
			local res
			if bucket and not bucket.allow(player) then res = { ok = false, err = "RATE_LIMIT" }
			else res = ui.binds[self.Name](s, payload or {}) end
			table.insert(results, self.Name .. ":" .. tostring((payload or {}).action) .. ":" .. tostring((payload or {}).dept or (payload or {}).clientId) .. "=" .. (if res.ok then "ok" else tostring(res.err)))
			G.task.wait(0.05)
			G.task.defer(ui.push)
			return res
		end)
		openTab("settings")
		local function nightSwitch(roleId, label)
			local rowF = find("Night_" .. roleId)
			return rowF and button(label, rowF)
		end
		table.clear(toasts)
		click(nightSwitch("researcher", "On"), 0.15)
		click(nightSwitch("engineer", "On"), 0.15)
		click(nightSwitch("curator", "Off"), 0.15)
		M.settle(4)
		ui.push()
		note("night shift calls: " .. table.concat(results, ", "))
		local ns = e.nightShift or {}
		local function deptState(list) local on, all = 0, 0; for _, dpt in list do all += 1; if ns[dpt] then on += 1 end end; return on, all end
		local rOn, rAll = deptState(Ops.ROLE_DEPTS.researcher)
		local gOn, gAll = deptState(Ops.ROLE_DEPTS.engineer)
		local cOn = deptState(Ops.ROLE_DEPTS.curator)
		check("three night-shift taps: researcher fully on", rOn == rAll, rOn .. "/" .. rAll)
		check("three night-shift taps: engineer fully on (no RATE_LIMIT half state)", gOn == gAll, gOn .. "/" .. gAll)
		check("three night-shift taps: curator off", cOn == 0, cOn)
		check("no RATE_LIMIT answer reached the player", string.find(table.concat(toasts, "|"), "Slow down", 1, true) == nil, table.concat(toasts, " | "))
		local rated = 0
		for _, r in results do if string.find(r, "RATE_LIMIT", 1, true) then rated += 1 end end
		check("the client lane mirrors the server bucket (no RATE_LIMIT at all)", rated == 0, table.concat(results, ", "))
		-- half-on role from an older save: neither side highlighted, the label says so, one tap fixes it
		e.nightShift = { engineering = true }
		ui.push()
		check("half-on role shown as such", has("on in 1 of 2 departments") ~= nil)
		click(nightSwitch("engineer", "On"), 0.2)
		M.settle(2)
		ui.push()
		check("tap On fixes the half-on role", e.nightShift.engineering == true and e.nightShift.training == true)
		-- two switches in a row (same remote): both applied
		table.clear(results)
		local autoRow, saveRow
		for _, x in pg:GetDescendants() do
			if x:IsA("TextLabel") and x.Text == "Hire automatically" then autoRow = x.Parent end
			if x:IsA("TextLabel") and x.Text == "Save for the next office" then saveRow = x.Parent end
		end
		click(autoRow and button("Off", autoRow), 0.05)
		click(saveRow and button("Off", saveRow), 0.05)
		M.settle(2)
		check("two switches tapped at once: both reach the server", e.hr.auto == false and e.saveMode == "off", table.concat(results, ", "))
		-- Pin double tap: the second tap lands after the first answer and its snapshot (toggle on the server)
		openTab("clients")
		table.clear(results)
		local studyRow = rowOf("StudySpark")
		local pin = studyRow and studyRow:FindFirstChild("Pin", true)
		M.fire(pin.Activated, {}, 1)
		M.settle(0.12) -- the first answer and its snapshot are back
		M.fire(pin.Activated, {}, 1)
		M.settle(1)
		ui.push()
		check("double tap on Pin keeps the client pinned", e.deals.pinned == "study", tostring(e.deals.pinned) .. " " .. table.concat(results, ", "))
		M.settle(1)
		ui.push()
		check("after the lock Unpin is a deliberate tap again", pin.Text == "Unpin" and pin:GetAttribute("Disabled") ~= true)
		check("no background errors", errors() == 0, errors())

	elseif SCEN == "midnight" then
		local now = ui.base + M.Sched.now
		local into = now % 1200
		M.Sched.now += (1199.3 - into)
		M.settle(0.1)
		for _, t in e.deals.tripList do if t.client == "creative" then t.back = e.seconds + 60 end end
		if s.live.ops and s.live.ops.trips then for _, t in s.live.ops.trips do if t.client == "creative" then t.back = e.seconds + 60 end end end
		ui.push()
		local b = brief()
		local trips = b and row(b, "Today", "Trips") or ""
		note("briefing trips at 07:59: " .. trips)
		check("trip back 60 s after 07:59 is just the time, never 'tomorrow' or 'day N'", string.find(trips, "back 08:39", 1, true) ~= nil and string.find(trips, "tomorrow", 1, true) == nil, trips)
		local far = Assistant._backText(e, e.seconds + 400, ui.base + M.Sched.now) -- 400 s = ~4.4 game hours after 07:59
		check("backText: a return 2+ game hours away names the day", string.match(far, "^day (%d+) 12:%d%d$") == tostring(Ops.day(e) + 1), far)
		openTab("clients")
		check("Clients: countdown in words at 07:59", has("PixelForge · pilot visit · City Hotel night · back in 1 min") ~= nil, has("PixelForge ·"))
		M.Sched.now += 2
		M.settle(0.1)
		e.calendar.day += 1
		ui.push()
		openTab("money")
		check("new day: picker shows Today and the old days", has("Today") ~= nil and has("Day 10") ~= nil)
		check("new day: Nothing booked yet today", has("Nothing booked yet today.") ~= nil)
		check("no background errors", errors() == 0, errors())

	elseif SCEN == "broke" then
		-- stage 3, models live, accounts signed, but costs exceed income and cash is negative
		d.money = -48250
		s.live.revenue, s.live.cost = 20, 60
		ui.push()
		local v = HUD.describe(State.snapshot)
		local net = (60 - 20) * Ops.DAY
		check("losing money: HUD says costs exceed income (not 'release models')", string.find(v.body, "Costs exceed income by " .. Ops.money(net) .. "/day", 1, true) ~= nil and string.find(v.body, "Release models", 1, true) == nil, v.body)
		check("losing money: hint points to prices / HR budget, opens Settings", string.find(v.body, "raise prices", 1, true) ~= nil and v.section == "settings" and v.warn, v.body)
		local hud = pg:FindFirstChild("AIEmpire_HUD")
		check("HUD safety badge: cash below $0", find("Safety", hud) and find("Safety", hud).Text == "CASH BELOW $0")
		s.live.ops.paused = true
		e.unpaidLeave = 3
		ui.push()
		check("HUD safety badge: trips paused", find("Safety", hud) and find("Safety", hud).Text == "CASH BELOW $0 FOR A DAY · TRIPS PAUSED", find("Safety", hud) and find("Safety", hud).Text)
		openTab("clients")
		check("Clients: paused trips explained", has("Cash has been below $0 for a whole game day: trips and night shifts are paused.") ~= nil)
		check("Clients: unpaid leave explained", has("3 newest hires are on unpaid leave until cash is above") ~= nil)
		openTab("team")
		check("Team: safety line too", has("3 newest hires are on unpaid leave") ~= nil)
		openTab("settings")
		check("Settings: HR status 'Paused: cash is below $0'", has("Paused: cash is below $0.") ~= nil)
		check("Settings: night shift paused text", has("Paused: cash has been below $0 for a whole game day.") ~= nil)
		local b = brief()
		if b then
			check("briefing: Today warning row (paused + unpaid leave)", string.find(row(b, "Today", "Warning") or "", "paused", 1, true) ~= nil and string.find(row(b, "Today", "Warning") or "", "unpaid leave", 1, true) ~= nil, row(b, "Today", "Warning"))
			check("briefing: a cash recommendation right after the goal", b.recommendations[2] and string.find(b.recommendations[2].text, "Cash is " .. M.require(RS.Shared.Format).money(-48250) .. " and falling", 1, true) ~= nil, recsOf(b))
		end
		check("no background errors", errors() == 0, errors())

	elseif SCEN == "hr" then
		openTab("settings")
		local function status() ui.push(); local t = find("HrStatus"); return t and t.Text or "" end
		-- mid: Save mode on with 32 of 64 desks filled (CompanyOps.hrAllowed checks Save mode before the budget)
		check("Save mode: HR stops at half the desks", string.find(status(), "Save mode: HR stops at half the desks", 1, true) ~= nil, status())
		s.live.ops.saveMode = false
		local text, warn = EmpireApp.hrStatus(State.snapshot)
		check("mid without Save mode: HR paused because the payroll is above the 40 % budget", string.find(status(), "Paused: payroll", 1, true) ~= nil and string.find(text, "above the 40 % budget", 1, true) ~= nil and warn, status())
		-- the same decision as the server: CompanyOps.hrAllowed says no for the picked role
		local roleId = Ops.hrPick(e)
		check("client status agrees with CompanyOps.hrAllowed", roleId ~= nil and Ops.hrAllowed(e, d.money, (s.live.ops.income or 0) / 60, false, roleId) == false)
		s.live.ops.income = 1e7
		check("enough income: CompanyOps.hrAllowed agrees (allowed)", Ops.hrAllowed(e, d.money, 1e7 / 60, false, roleId) == true)
		local st = status()
		check("enough income, no Save mode: hiring (or keeping the reserve)", string.find(st, "Hiring: next hire", 1, true) ~= nil or string.find(st, "cash reserve", 1, true) ~= nil, st)
		d.money = 1e7
		check("plenty of cash: 'Hiring: next hire <role>'", string.find(status(), "Hiring: next hire", 1, true) ~= nil, status())
		d.money = 2000
		check("little cash: keeps the reserve", string.find(status(), "keeps a cash reserve", 1, true) ~= nil, status())
		d.money = 1e7
		e.unpaidLeave = 2
		check("unpaid leave pauses HR", string.find(status(), "unpaid leave", 1, true) ~= nil, status())
		e.unpaidLeave = 0
		local cap = M.require(RS.Shared.Config.EmpireConfig).OFFICES[Ops.stageIndex(e)].staff
		e.employees.engineer += cap
		check("desks full", string.find(status(), "every desk is filled", 1, true) ~= nil, status())
		e.employees.engineer -= cap
		e.hr.auto = false
		check("auto off", status() == "Off: hire by hand in Team.", status())
		check("no background errors", errors() == 0, errors())
	end
end

setfenv(body, M.envFor(nil))
local ok, res, status = M.runMain(body, { timeout = 900 })
if not ok then failc += 1; print("FAIL  scenario crashed (" .. tostring(status) .. "): " .. tostring(res)) end
if M.stats.errors > 0 then failc += 1; print("FAIL  background errors: " .. M.stats.errors) end
print(string.format("apps_adv_%s: %d passed, %d failed", SCEN, pass, failc))
