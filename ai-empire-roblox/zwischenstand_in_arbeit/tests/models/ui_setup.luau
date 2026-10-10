--!nocheck
-- Shared client setup of the models UI suites (test_ui.luau) and the guiprev scene (scene_models.luau):
-- the real client UI (UIRoot, HUD, Computer with every app, Toast) in the mock, wired to the REAL server
-- handlers (AIModelService, EmpireService, MarketService ...) through RemoteFunction:InvokeServer, exactly like
-- tools/guiprev/scenes/client.luau does for the shop. States:
--   empty     company founded in the garage, no models
--   rich      Startup Campus: Consumer Chat v2 (successor of v1, auto price with a note), Developer API (manual,
--             refined 1/3), a trained Study model ready to launch, Lab level 2 after the whole research tree,
--             servers over capacity (waitlist), rivals in the marketplace, 2 business clients
--   full      like rich, but every product line of the office is taken (LINE_LIMIT case in the release card)
-- Returns { M, session, push, Computer, LabApp, MarketApp, playerGui, binds }.
local GuiDump = require("../../tools/guiprev/guidump")
return function(M, genDir, state, vw, vh, insets)
	GuiDump.init(M)
	local G = M.G
	local Instance = G.Instance
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local Client = game.StarterPlayer.StarterPlayerScripts.Client

	local Template = M.require(Server.Lib.Template)
	local Remote = M.require(Server.Lib.Remote)
	local SessionService = M.require(Server.Services.SessionService)
	local MarketMath = M.require(RS.Shared.MarketMath)
	local ModelMath = M.require(RS.Shared.ModelMath)
	local EmpireConfig = M.require(RS.Shared.Config.EmpireConfig)
	local OWNER = 4242

	local playerGui = Instance.new("Folder"); playerGui.Name = "PlayerGui"
	local localPlayer = { UserId = OWNER, Name = "Founder", DisplayName = "Founder", Character = nil, Parent = game.Players, CharacterAdded = M.newSignal("CharacterAdded"),
		WaitForChild = function(_, name) if name == "PlayerGui" then return playerGui end end, FindFirstChildOfClass = function() return nil end, Kick = function() end }
	M.IMPL.Players.get.LocalPlayer = function() return localPlayer end; M.classInfo("Players").get.LocalPlayer = function() return localPlayer end

	-- server handlers (real services; no rate limits)
	local RateLimiter = M.require(Server.Lib.RateLimiter)
	RateLimiter.new = function() return { allow = function() return true end, forget = function() end } end
	local binds, loadedCb = {}, nil
	local origBind = Remote.bind
	Remote.bind = function(name, limits, handler) binds[name] = handler; origBind(name, limits, handler) end
	local origLoaded = SessionService.onLoaded
	SessionService.onLoaded = function(cb) loadedCb = cb; origLoaded(cb) end
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
	d.empire.office = 1
	d.money = 48250
	local live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} }

	local function model(id, name, version, target, status, opt)
		opt = opt or {}
		local stats = opt.stats or { reasoning = 58, coding = 52, math = 50, creativity = 64, knowledge = 61, reliability = 57, speed = 76, efficiency = 74 }
		local m = { id = id, name = name, version = version, sizeId = opt.sizeId or "s1b", focusId = opt.focusId or "balanced", status = status,
			createdAt = 0, trainedAt = 0, stats = stats, overall = ModelMath.overall(stats), trainCost = 4200, iterations = opt.iterations,
			dataUsed = { total = 2e9, quality = 0.8, shares = { general = 1 } } }
		if target then
			m.release = { subPrice = opt.sub or 10, apiPrice = opt.api or 2, marketing = 0, target = target, releasedAt = 0, auto = opt.auto ~= false }
			m.market = MarketMath.newMarketState(target, 0)
			m.market.vage = opt.vage or 600
			m.market.age = opt.vage or 600
			m.market.users = opt.users or {}
		end
		m.replacedBy = opt.replacedBy
		d.models[id] = m
		table.insert(d.modelOrder, id)
		return m
	end

	if state == "rich" or state == "full" then
		d.empire.office = 3
		d.money = 186400
		d.empire.labLevel = 2
		d.empire.points = 5200
		for _, def in EmpireConfig.RESEARCH do d.empire.research[def.id] = true end
		d.data = { general = { tokens = 8e9, quality = 0.82 }, code = { tokens = 5e9, quality = 0.8 }, math = { tokens = 3e9, quality = 0.78 } }
		d.gpus = { workstation = 6 }
		model("nova1", "Nova", 1, "general", "retired", { replacedBy = "nova2" })
		d.models.nova1.market.users = {}
		model("nova2", "Nova", 2, "general", "live", { vage = 1500, users = { consumers = 31200, students = 6100, developers = 1400, businesses = 300 },
			stats = { reasoning = 63, coding = 55, math = 54, creativity = 71, knowledge = 66, reliability = 60, speed = 76, efficiency = 74 } })
		model("coder", "Coder", 2, "developers", "live", { auto = false, iterations = 1, sub = 5, api = 3, vage = 2700, users = { developers = 18400, businesses = 2100, consumers = 900 },
			stats = { reasoning = 61, coding = 74, math = 63, creativity = 48, knowledge = 57, reliability = 62, speed = 76, efficiency = 74 } })
		model("study", "Sage", 1, nil, "trained", { stats = { reasoning = 64, coding = 51, math = 70, creativity = 55, knowledge = 68, reliability = 61, speed = 76, efficiency = 74 } })
		if state == "full" then
			model("biz", "Ledger", 1, "businesses", "live", { vage = 300, users = { businesses = 4200 } })
		end
		live.users = 60400
		live.revenue = 62.5
		live.cost = 9.8
		live.perModel = { nova2 = { users = 39000, revenue = 41.2, cost = 6.1 }, coder = { users = 21400, revenue = 21.3, cost = 3.7 } }
		live.capacity = 52000
		live.load = 64400
		live.waitlist = 12400
		live.pricing = { nova2 = { note = "Servers 97 % full → Consumer Chat price raised to $10", at = 0 } }
		live.marketplace = { customers = {}, offers = {
			{ providerId = -1, company = "Morrow Labs", id = "npc1", name = "Morrow Code", overall = 61.8, stats = { reasoning = 62, coding = 64, math = 60, creativity = 58, knowledge = 62, reliability = 64, speed = 70, efficiency = 70 }, sub = 10, api = 1.5, price = 1075, users = 52000, iterations = 4, target = "general", npc = true },
			{ providerId = -2, company = "Fern AI", id = "npc2", name = "Fern One", overall = 60.9, stats = { reasoning = 60, coding = 58, math = 62, creativity = 63, knowledge = 61, reliability = 61, speed = 70, efficiency = 70 }, sub = 10, api = 1.0, price = 1050, users = 47000, iterations = 3, target = "general", npc = true },
			{ providerId = 5151, company = "Orbit Minds", id = "p1", name = "Halo v3", overall = 57.2, stats = { reasoning = 57, coding = 60, math = 55, creativity = 56, knowledge = 58, reliability = 57, speed = 76, efficiency = 74 }, sub = 5, api = 2, price = 600, users = 12000, iterations = 1, target = "developers", npc = false },
		} }
		local e = d.empire
		if typeof(e.deals) == "table" then
			e.deals.accounts = { helpdesk = { expires = 9e9, since = 0 }, paper = { expires = 9e9, since = 0 } }
		end
	end

	local session = { userId = OWNER, player = localPlayer, data = d, live = live,
		dirty = false, lastSent = 0, nextSaveAt = math.huge, saving = false, closed = false, released = false, rng = G.Random.new(1) }
	SessionService.all()[localPlayer] = session
	local function snapshot() return { saveEnabled = false, serverTime = 1.7e9, data = session.data, live = session.live } end
	local function push() M.fire(stateEvent.OnClientEvent, snapshot()); M.settle(0.1) end
	local function patch(cls, name, fn) M.IMPL[cls].methods[name] = fn; M.classInfo(cls).methods[name] = fn end
	patch("RemoteFunction", "InvokeServer", function(self, payload)
		if self.Name == "RequestState" then return { ok = true, state = snapshot() } end
		local handler = binds[self.Name]
		if not handler then return { ok = false, err = "BAD_INPUT" } end
		local result = handler(session, payload or {})
		G.task.defer(push)
		return result
	end)
	if loadedCb then pcall(loadedCb, session) end

	-- client: shop needs a MarketplaceService double; the rest is the real UI
	local clientMarket = { prices = {}, PromptProductPurchaseFinished = M.newSignal("PromptProductPurchaseFinished"), PromptGamePassPurchaseFinished = M.newSignal("PromptGamePassPurchaseFinished") }
	function clientMarket:GetProductInfoAsync() error("HTTP 400 (test double)") end
	function clientMarket:PromptProductPurchase() end
	function clientMarket:PromptGamePassPurchase() end
	local ShopApp = M.require(Client.UI.Apps.ShopApp)
	if ShopApp._setDeps then ShopApp._setDeps({ market = clientMarket, player = function() return localPlayer end }) end
	local UIRoot = M.require(Client.UI.UIRoot)
	local Toast = M.require(Client.UI.Toast)
	local State = M.require(Client.Controllers.StateController)
	local Computer = M.require(Client.UI.Screens.Computer)
	local hud, dim, overlay, intro, top = UIRoot.init()
	if vw and GuiDump then
		GuiDump.setViewport(playerGui, vw, vh, insets)
	end
	Toast.mount(top)
	local okHud, HUD = pcall(M.require, Client.UI.Screens.HUD)
	if okHud then pcall(HUD.mount, hud, false, function() end) end
	Computer.mount(overlay, dim)
	State.init()
	M.settle(1)
	if okHud then pcall(HUD.setHidden, false) end
	push()
	return {
		M = M, session = session, push = push, Computer = Computer, playerGui = playerGui, binds = binds,
		LabApp = M.require(Client.UI.Apps.LabApp), MarketApp = M.require(Client.UI.Apps.MarketApp),
	}
end
