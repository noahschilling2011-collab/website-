--!nocheck
-- Shared client setup of the apps UI suite (test_ui.luau) and the guiprev scene (scene_apps.luau): the real client
-- UI (UIRoot, HUD, Computer with every app, Toast) in the mock, wired to the REAL server handlers (EmpireService:
-- EmpireAction / DealAction / HireEmployee, AIModelService, MarketService) through RemoteFunction:InvokeServer.
-- Snapshots carry SessionService.replicatedData (what a real client receives: trimmed deals, 4 ledger days).
-- live.ops is the REAL CompanyOps.step summary of the state (computed once with dt = 0 at a night clock, so no trip
-- starts and no money moves); live.compute / capacity / load / waitlist follow EmpireService / CompanyOps.capacity.
-- The visible clock is 10:30 (company time). States:
--   garage   company founded in the Garage Lab, no model yet                       -> "Train your first AI"
--   client   garage, Nova v1 live, the founder is driving to CloudDesk             -> "Sign your first client"
--   save     garage, CloudDesk signed, $18,400 saved, profit running              -> "Founder Headquarters $27,000"
--   mid      Startup Campus (stage 3): 30 staff + 2 apprentices, 5 accounts (1 region), a rep on a region pilot, a
--            check-in, trust bars, a pinned and a skipped client, 4 ledger days, a rack fault, Save mode on
--   rich     Global AI HQ (stage 5): 180 staff, 4 live lines, 10 accounts (2 abroad), a flight abroad, a hosted client
--            team, 2 rack faults, servers over capacity, Lab level 6, jet not yet bought, $2.4M
-- Returns { M, session, push, Computer, HUD, playerGui, binds, calls, base, state }.
local GuiDump = require("../../tools/guiprev/guidump")
return function(M, genDir, state, vw, vh, insets, opt)
	opt = opt or {}
	GuiDump.init(M)
	local G = M.G
	local Instance = G.Instance
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local Client = game.StarterPlayer.StarterPlayerScripts.Client
	local OWNER = 4242

	-- company clock: 10:30 on a fixed server day (CompanyOps.hour: 08:00 + 225 s / 90 = 10:30)
	local BASE = 1416666 * 1200 + 225
	M.IMPL.Workspace.methods.GetServerTimeNow = function() return BASE + M.Sched.now end
	M.classInfo("Workspace").methods.GetServerTimeNow = M.IMPL.Workspace.methods.GetServerTimeNow
	G.os = setmetatable({ clock = function() return M.Sched.now end }, { __index = os })
	if opt.touch then
		local uis = game:GetService("UserInputService")
		uis[M.KEY].props.TouchEnabled = true
		uis[M.KEY].props.MouseEnabled = false
		uis[M.KEY].props.KeyboardEnabled = false
	end

	local Template = M.require(Server.Lib.Template)
	local Remote = M.require(Server.Lib.Remote)
	local SessionService = M.require(Server.Services.SessionService)
	local Economy = M.require(Server.Services.EconomyService)
	local EmpireMath = M.require(RS.Shared.EmpireMath)
	local Ops = M.require(RS.Shared.CompanyOps)
	local MarketMath = M.require(RS.Shared.MarketMath)
	local ModelMath = M.require(RS.Shared.ModelMath)
	local EmpireConfig = M.require(RS.Shared.Config.EmpireConfig)

	local playerGui = Instance.new("Folder"); playerGui.Name = "PlayerGui"
	local attrs = { TravelState = opt.travel }
	local localPlayer = { UserId = OWNER, Name = "Founder", DisplayName = "Founder", Character = nil, Parent = game.Players, CharacterAdded = M.newSignal("CharacterAdded"), CharacterRemoving = M.newSignal("CharacterRemoving"),
		WaitForChild = function(_, name) if name == "PlayerGui" then return playerGui end end,
		FindFirstChild = function(_, name) if name == "PlayerGui" then return playerGui end end,
		GetAttribute = function(_, name) return attrs[name] end,
		FindFirstChildOfClass = function() return nil end, Kick = function() end }
	M.IMPL.Players.get.LocalPlayer = function() return localPlayer end; M.classInfo("Players").get.LocalPlayer = function() return localPlayer end

	-- server handlers (real services; no rate limits); every client call is recorded in `calls`
	local RateLimiter = M.require(Server.Lib.RateLimiter)
	RateLimiter.new = function() return { allow = function() return true end, forget = function() end } end
	local binds, calls = {}, {}
	local origBind = Remote.bind
	Remote.bind = function(name, limits, handler) binds[name] = handler; origBind(name, limits, handler) end
	Remote.setup()
	local folder = RS:FindFirstChild("Remotes")
	local notifyEvent, stateEvent = folder:FindFirstChild("Notify"), folder:FindFirstChild("State")
	Remote.fire = function(player, name, kind, payload)
		if name == "Notify" then M.fire(notifyEvent.OnClientEvent, kind, payload) end
	end
	for _, name in { "AIModelService", "EmpireService", "MarketService" } do
		local ok, mod = pcall(M.require, Server.Services[name])
		if ok and mod.init then pcall(mod.init) end
	end

	local d = Template.new()
	d.company = { name = "Nimbus Labs", logo = "N", color = "cyan", spec = "general", reputation = 34, foundedAt = 0 }
	local e = d.empire
	e.office = 1
	d.money = 6450
	e.calendar = { day = 1, index = math.floor(BASE / 1200) }
	local live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} }

	local STATS = { reasoning = 58, coding = 52, math = 50, creativity = 64, knowledge = 61, reliability = 57, speed = 76, efficiency = 74 }
	local function model(id, name, version, target, status, opt2)
		opt2 = opt2 or {}
		local stats = opt2.stats or table.clone(STATS)
		local m = { id = id, name = name, version = version, sizeId = opt2.sizeId or "s1b", focusId = opt2.focusId or "balanced", status = status,
			createdAt = 0, trainedAt = 0, stats = stats, overall = ModelMath.overall(stats), trainCost = 4200, iterations = opt2.iterations,
			dataUsed = { total = 2e9, quality = 0.8, shares = { general = 1 } } }
		if target then
			m.release = { subPrice = opt2.sub or 10, apiPrice = opt2.api or 2, marketing = 0, target = target, releasedAt = 0, auto = opt2.auto ~= false }
			m.market = MarketMath.newMarketState(target, 0)
			m.market.vage = opt2.vage or 600
			m.market.age = opt2.vage or 600
			m.market.users = opt2.users or {}
		end
		m.replacedBy = opt2.replacedBy
		d.models[id] = m
		table.insert(d.modelOrder, id)
		return m
	end
	local function staff(counts)
		e.employees = counts
		EmpireMath.syncProfiles(e, OWNER)
	end
	local function ledgerDay(day, i, o) e.ledger[tostring(day)] = { i = i, o = o } end
	local faults = {}

	if state == "garage" then
		e.seconds = 40
	elseif state == "client" then
		e.seconds = 160
		d.money = 9100
		d.data = { general = { tokens = 1.5e9, quality = 0.7 } }
		d.stats.modelsTrained, d.stats.modelsReleased = 1, 1
		model("nova1", "Nova", 1, "general", "live", { sizeId = "s100m", stats = { reasoning = 30, coding = 26, math = 24, creativity = 34, knowledge = 31, reliability = 31, speed = 80, efficiency = 80 }, users = { consumers = 2600 } })
		staff({ researcher = 1, engineer = 1, curator = 1, marketer = 0 })
		e.deals.tripList = { { client = "helpdesk", kind = "sign", back = 240, founder = true, hosted = false, crew = 1, left = 0 } }
		e.deals.news = { "day 1 10:12: founder drives to CloudDesk: pilot, $80" }
		live.users, live.revenue, live.cost = 2600, 4.2, 0.32
		live.perModel = { nova1 = { users = 2600, revenue = 4.2, cost = 0.3 } }
		ledgerDay(1, { market = 2900, quest = 9500 }, { wages = 610, training = 1280, hire = 3000, trips = 80, upkeep = 16, food = 4 })
	elseif state == "save" then
		e.seconds = 900
		d.money = 18400
		d.data = { general = { tokens = 3e9, quality = 0.72 } }
		d.stats.modelsTrained, d.stats.modelsReleased = 3, 2
		model("nova1", "Nova", 1, "general", "retired", { sizeId = "s100m", replacedBy = "nova2" })
		model("nova2", "Nova", 2, "general", "live", { sizeId = "s500m", stats = { reasoning = 41, coding = 38, math = 36, creativity = 46, knowledge = 43, reliability = 40, speed = 78, efficiency = 78 }, users = { consumers = 9400, students = 800 } })
		staff({ researcher = 1, engineer = 2, curator = 1, marketer = 1 })
		e.contractsCompleted = 1
		e.deals.signed = 1
		e.deals.accounts = { helpdesk = { expires = 900 + 6800, since = 400, founder = true } }
		e.deals.tripList = { { client = "paper", kind = "sign", back = 1050, founder = true, hosted = false, crew = 1, left = 810 } }
		e.deals.trust = { code = 0.35 }
		e.deals.news = { "day 1 13:40: founder drives to Paper Studio: pilot, $80", "day 1 11:05: signed CloudDesk: pilot $9,000, $9,000/day", "day 1 10:12: founder drives to CloudDesk: pilot, $80" }
		live.users, live.revenue, live.cost = 10200, 38.5, 2.4
		live.perModel = { nova2 = { users = 10200, revenue = 38.5, cost = 2.1 } }
		ledgerDay(1, { market = 21400, pilot = 9000, b2b = 3700, quest = 18300 }, { wages = 5900, training = 6100, hire = 4200, gpu = 7500, trips = 160, upkeep = 225, food = 23, market = 1900 })
	elseif state == "mid" then
		e.office = 3
		e.seconds = 12100
		d.money = 74300
		e.calendar = { day = 10, index = math.floor(BASE / 1200) }
		e.points = 840
		e.research = { pipeline = true, cleaning = true, architecture = true }
		d.data = { general = { tokens = 9e9, quality = 0.84 }, code = { tokens = 4e9, quality = 0.8 } }
		d.gpus = { laptop = 1, workstation = 4, consumer = 2 }
		d.stats.modelsTrained, d.stats.modelsReleased = 7, 5
		e.contractsCompleted = 7
		e.deals.signed = 7
		model("nova3", "Nova", 3, "general", "live", { stats = { reasoning = 52, coding = 49, math = 53, creativity = 57, knowledge = 55, reliability = 54, speed = 76, efficiency = 74 }, vage = 1500, users = { consumers = 38400, students = 4100, developers = 900 } })
		model("coder", "Coder", 2, "developers", "live", { stats = { reasoning = 50, coding = 58, math = 52, creativity = 41, knowledge = 49, reliability = 53, speed = 76, efficiency = 74 }, vage = 2460, users = { developers = 15200, businesses = 1300 }, auto = false, sub = 5, api = 3 })
		staff({ researcher = 8, engineer = 9, curator = 7, marketer = 6 })
		-- two apprentices (CORE_SPEC 11.1: separate map, never in the profile): an engineer on day 3 and a curator on day 7
		local eng, cur = e.staffProfiles.engineer, e.staffProfiles.curator
		table.insert(eng, { n = "Jonas Weber", s = 7710001, k = 1, w = 1 }); e.employees.engineer += 1
		table.insert(cur, { n = "Ella Brandt", s = 7710002, k = 1, w = 1 }); e.employees.curator += 1
		e.apprentices = { ["7710001"] = { day = 8 }, ["7710002"] = { day = 4 } }
		local s0 = e.seconds
		e.deals.accounts = {
			helpdesk = { expires = s0 + 4800, since = 300, founder = true }, paper = { expires = s0 + 2300, since = 1900, founder = true },
			code = { expires = s0 + 700, since = 4100, renewing = true }, pixel = { expires = s0 + 6100, since = 6000 }, ledger = { expires = s0 + 5300, since = 9900 },
		}
		e.deals.tripList = {
			{ client = "creative", kind = "sign", back = s0 + 900, founder = false, hosted = false, crew = 2, left = s0 - 300 },
			{ client = "code", kind = "renew", back = s0 + 150, founder = false, hosted = false, crew = 1, left = s0 - 90 },
		}
		e.deals.trust = { creative = 0.4, study = 0.62 }
		e.deals.pinned = "orbitgames"
		e.deals.skip = { north = true }
		e.deals.pilots = 2
		e.deals.news = {
			"day 10 10:21: rep to ByteWorks: check-in, car, $100",
			"day 10 10:02: rep to PixelForge: pilot, City Hotel night, $470",
			"day 10 09:30: Save mode on: saving for the Innovation Campus",
			"day 9 16:10: signed Ledger Finance: pilot $27,000, $27,000/day",
			"day 9 13:44: apprentice Jonas Weber started (ML Engineer)",
			"day 9 11:02: visited StudySpark: trust 62%",
			"day 8 15:30: HR hired Mia Chen (Growth & Sales, fee $1,200)",
			"day 8 09:12: moved into the Startup Campus",
		}
		e.saveMode = "auto"
		e.nightShift = { data = true }
		e.hr = { auto = true, budget = 0.40 }
		faults = { { slot = 2, gpu = "workstation", since = s0 - 20 } }
		live.users, live.revenue, live.cost = 59900, 118.6, 9.7
		live.perModel = { nova3 = { users = 43400, revenue = 82.1, cost = 5.9 }, coder = { users = 16500, revenue = 36.5, cost = 3.4 } }
		ledgerDay(7, { market = 61200, b2b = 41300, pilot = 13500, studio = 2100 }, { wages = 52100, ops = 9600, upkeep = 9000, food = 1900, fleet = 300, trips = 940, market = 6200, b2bserve = 420, guest = 400, hire = 6000 })
		ledgerDay(8, { market = 66400, b2b = 45000, guest = 2160, retail = 230 }, { wages = 55800, ops = 10100, upkeep = 9000, food = 2000, fleet = 300, trips = 470, market = 6700, b2bserve = 470, guest = 400, office = 100000 })
		ledgerDay(9, { market = 70800, b2b = 47100, pilot = 27000, guest = 2160, retail = 260 }, { wages = 58600, ops = 10800, upkeep = 9000, food = 2100, fleet = 300, trips = 570, market = 7000, b2bserve = 560, guest = 400, hire = 2400 })
		ledgerDay(10, { market = 38900, b2b = 26600, guest = 1120 }, { wages = 31600, ops = 5900, upkeep = 4700, food = 1100, fleet = 160, trips = 570, market = 3800, b2bserve = 310, guest = 210, research = 12000 })
		ledgerDay(6, { market = 1 }, { wages = 1 }) -- older than the 4 replicated days (never reaches the client)
	elseif state == "rich" then
		e.office = 5
		e.seconds = 61500
		d.money = 2412000
		e.calendar = { day = 52, index = math.floor(BASE / 1200) }
		e.points = 6400
		for _, def in EmpireConfig.RESEARCH do e.research[def.id] = true end
		e.labLevel = 6
		d.data = { general = { tokens = 8e10, quality = 0.88 }, code = { tokens = 4e10, quality = 0.86 }, math = { tokens = 3e10, quality = 0.85 } }
		d.gpus = { laptop = 1, datacenter = 8, accelerator = 20, workstation = 4 }
		e.infrastructure.cooling = 2
		d.stats.modelsTrained, d.stats.modelsReleased = 31, 19
		e.contractsCompleted = 24
		e.deals.signed = 24
		model("nova7", "Nova", 7, "general", "live", { sizeId = "s7b", stats = { reasoning = 92, coding = 88, math = 90, creativity = 95, knowledge = 93, reliability = 91, speed = 70, efficiency = 66 }, vage = 900, users = { consumers = 610000, students = 41000 } })
		model("coder", "Coder", 5, "developers", "live", { sizeId = "s7b", focusId = "coding", stats = { reasoning = 90, coding = 97, math = 91, creativity = 77, knowledge = 88, reliability = 92, speed = 70, efficiency = 66 }, vage = 3300, users = { developers = 238000, businesses = 21000 } })
		model("sage", "Sage", 4, "students", "live", { sizeId = "s3b", stats = { reasoning = 84, coding = 70, math = 89, creativity = 71, knowledge = 86, reliability = 83, speed = 74, efficiency = 70 }, vage = 1800, users = { students = 301000 } })
		model("ledgerai", "Ledger", 3, "businesses", "live", { sizeId = "s3b", stats = { reasoning = 86, coding = 78, math = 88, creativity = 66, knowledge = 84, reliability = 89, speed = 74, efficiency = 70 }, vage = 2700, users = { businesses = 52000 } })
		staff({ researcher = 62, engineer = 54, curator = 28, marketer = 36 })
		local s0 = e.seconds
		e.deals.accounts = {
			helpdesk = { expires = s0 + 5800, since = 0, founder = true }, code = { expires = s0 + 3100, since = 0, founder = true },
			civic = { expires = s0 + 6400, since = 0 }, north = { expires = s0 + 2200, since = 0 }, creative = { expires = s0 + 4500, since = 0 },
			ledger = { expires = s0 + 1700, since = 0 }, atlas = { expires = s0 + 900, since = 0, renewing = true }, delta = { expires = s0 + 5200, since = 0 },
			enterprise = { expires = s0 + 3900, since = 0 }, helix = { expires = s0 + 6900, since = 0 },
		}
		e.deals.tripList = {
			{ client = "frontier", kind = "sign", back = s0 + 1900, founder = false, hosted = false, crew = 2, left = s0 - 500 },
			{ client = "mosaic", kind = "sign", back = s0 + 800, founder = false, hosted = true, crew = 0, left = s0 - 400 },
			{ client = "atlas", kind = "renew", back = s0 + 600, founder = false, hosted = false, crew = 1, left = s0 - 600 },
		}
		e.deals.trust = { frontier = 0.55, mosaic = 0.8, nova = 0.3 }
		e.deals.pilots = 9
		local news = {}
		for i = 1, 26 do table.insert(news, string.format("day %d %02d:%02d: %s", 52 - i // 6, 9 + i % 8, (i * 7) % 60, ({ "signed Delta Robotics: pilot $45,000, $45,000/day", "rep to Orbit Systems: pilot, flight + 2 nights, $2,520", "hosting Mosaic Worlds at the guest house: pilot, $240", "renewed Nova Logistics for 6 days", "HR hired Ava Lind (AI Researcher, fee $1,000)", "Lab level 6: +1 core stat on future models" })[i % 6 + 1])) end
		e.deals.news = news
		e.nightShift = { research = true, training = true }
		e.hr = { auto = true, budget = 0.55 }
		faults = { { slot = 5, gpu = "datacenter", since = s0 - 12 }, { slot = 22, gpu = "accelerator", since = s0 - 41 } }
		live.users, live.revenue, live.cost = 1512000, 2210, 282
		live.perModel = { nova7 = { users = 900000, revenue = 1102, cost = 140 }, coder = { users = 259000, revenue = 560, cost = 77 }, sage = { users = 301000, revenue = 391, cost = 38 }, ledgerai = { users = 52000, revenue = 157, cost = 16 } }
		for day = 49, 52 do
			local k = if day == 52 then 0.45 else 1
			ledgerDay(day, { market = math.floor(1.71e6 * k), b2b = math.floor(4.9e5 * k), pilot = if day == 50 then 45000 else 0, guest = math.floor(2160 * k), retail = math.floor(880 * k), studio = math.floor(3800 * k) },
				{ wages = math.floor(1.02e6 * k), ops = math.floor(15100 * k), upkeep = math.floor(48000 * k), food = math.floor(1500 * k), fleet = math.floor(600 * k), trips = 2520 + 470,
					market = math.floor(1.9e5 * k), b2bserve = math.floor(9800 * k), guest = math.floor(400 * k), jet = 0, lab = if day == 51 then 100663 else 0, gpu = if day == 49 then 360000 else 0 })
			for side, map in e.ledger[tostring(day)] do for cat, v in map do if v == 0 then map[cat] = nil end end end
		end
	end

	-- milestones: every finished quest is already collected (except in the fresh garage: the HUD nudge shows there)
	d.stats.peakUsers = math.max(d.stats.peakUsers or 0, live.users)
	if state ~= "garage" then
		for _, quest in EmpireConfig.QUESTS do
			if EmpireMath.progress(d, quest) >= quest.target then e.quests[quest.id] = true end
		end
	end

	-- live.ops: the real CompanyOps.step summary (dt = 0, night clock -> no trip starts, no flows), then the compute
	-- summary exactly as EmpireService.tick writes it, and serving capacity from CompanyOps.capacity
	if d.company then
		local session0 = { userId = OWNER, player = localPlayer, data = d, live = { revenue = 0, cost = 0 } }
		local calendar = table.clone(e.calendar)
		local news = table.clone(e.deals.news)
		local night = math.floor(BASE / 1200) * 1200 + 1000 -- 21:44 on the same server day
		Ops.step(session0, 0, Economy, night)
		e.calendar = calendar
		e.deals.news = news
		live.ops = session0.live.ops
		live.ops.wagesCost = math.floor(EmpireMath.bonuses(e).wage * 60 + 0.5)
		-- like EmpireService.tick: the market flow first, then wages, then the CompanyOps flows (all $/s)
		local ops = live.ops
		live.revenue += ((ops.b2b or 0) + (ops.guest or 0)) / 60
		live.cost += EmpireMath.bonuses(e).wage
		for _, k in { "wages", "ops", "upkeep", "food", "fleet", "guest", "jet", "b2bserve" } do
			if k ~= "wages" then live.cost += (ops[k .. "Cost"] or 0) / 60 end
		end
		live.ops.saveMode = (state == "mid")
		live.ops.income = math.floor(live.revenue * 60 * 0.97 + 0.5)
		local fleet = ModelMath.fleet(d.gpus)
		local lost = 0
		for _, f in faults do lost += 1 end
		live.compute = { units = fleet.throughput, lost = lost, reserved = math.floor((e.deals.reserved or 0) * 100 + 0.5) / 100, slots = fleet.slotsUsed, it = Ops.itOnDuty(e, BASE), faults = faults }
		if live.users > 0 then
			-- load in 500M-model users: users of each live model x SERVE_UNITS of its size (CORE_SPEC 3.1 step 6)
			local cap = Ops.capacity(d)
			local units = M.require(RS.Shared.Config.MarketConfig).SERVE_UNITS or {}
			local load = 0
			for id, r in live.perModel do
				local m = d.models[id]
				load += (r.users or 0) * (if m then units[m.sizeId] or 1 else 1)
			end
			if load == 0 then load = live.users end
			live.capacity = math.floor(cap)
			live.load = math.floor(load)
			-- demand in users (MarketMath: users = demand x served, served = min(1, capacity / load))
			live.demand = if load > cap then math.floor(live.users * load / cap) else live.users
			live.waitlist = if load > cap then math.floor(live.users * (1 - cap / load)) else 0
		end
	end

	local session = { userId = OWNER, player = localPlayer, data = d, live = live,
		dirty = false, lastSent = 0, nextSaveAt = math.huge, saving = false, closed = false, released = false, rng = G.Random.new(1) }
	SessionService.all()[localPlayer] = session
	local function snapshot() return { saveEnabled = false, serverTime = BASE + M.Sched.now, data = SessionService.replicatedData(session.data), live = session.live } end
	local function push() M.fire(stateEvent.OnClientEvent, snapshot()); M.settle(0.1) end
	local function patch(cls, name, fn) M.IMPL[cls].methods[name] = fn; M.classInfo(cls).methods[name] = fn end
	patch("RemoteFunction", "InvokeServer", function(self, payload)
		if self.Name == "RequestState" then return { ok = true, state = snapshot() } end
		table.insert(calls, { name = self.Name, payload = payload })
		local handler = binds[self.Name]
		if not handler then return { ok = false, err = "BAD_INPUT" } end
		local result = handler(session, payload or {})
		G.task.defer(push)
		return result
	end)

	-- client: the real UI
	local UIRoot = M.require(Client.UI.UIRoot)
	local Toast = M.require(Client.UI.Toast)
	local State = M.require(Client.Controllers.StateController)
	local Computer = M.require(Client.UI.Screens.Computer)
	local hud, dim, overlay, intro, top = UIRoot.init()
	if vw then GuiDump.setViewport(playerGui, vw, vh, insets) end
	Toast.mount(top)
	local HUD = M.require(Client.UI.Screens.HUD)
	HUD.mount(hud, false, function() end)
	Computer.mount(overlay, dim)
	State.init()
	M.settle(1)
	HUD.setHidden(false)
	if vw then GuiDump.setViewport(playerGui, vw, vh, insets) end
	push()
	M.settle(0.5)
	return { M = M, session = session, push = push, Computer = Computer, HUD = HUD, playerGui = playerGui, binds = binds, calls = calls,
		base = BASE, state = state, attrs = attrs, Toast = Toast }
end
