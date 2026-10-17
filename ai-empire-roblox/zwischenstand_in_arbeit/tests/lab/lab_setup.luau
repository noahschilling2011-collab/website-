--!nocheck
-- Shared setup of the lab package's suites and its guiprev scene: tests/models/ui_setup.luau (the real client UI
-- wired to the real server handlers in the mock) built ONCE, plus the lab states, switched with ui.use(name):
--   empty    company founded in the garage, $48,250, no models (ui_setup "empty")
--   fresh    garage, $12,200, NO data (Template data = {}): the casual bot's start (LAB_SPEC 4.9)
--   starter  garage after the bot's data plan: 2x Web Crawl Chunk + 2x Public Repos, $4,800 left
--   rich     Startup Campus (ui_setup "rich"): 6 workstation GPUs, 16B tokens, all research, Lab level 2
--   full     like rich, every product line of the office taken (ui_setup "full")
--   hq       stage 5 (Global AI Headquarters): 10 accelerators + 2 datacenter GPUs, 53B tokens, Lab level 6,
--            three live lines + a trained Sage v1 ready, $2.4M (a late-game rich state)
-- Returns the ui table of ui_setup plus ui.use(name), ui.state, ui.Studio, ui.LabState, ui.LabPreview,
-- ui.AIModelService.
local setup = require("../models/ui_setup")

local function deepcopy(v, seen)
	if typeof(v) ~= "table" then return v end
	seen = seen or {}
	if seen[v] then return seen[v] end
	local out = {}
	seen[v] = out
	for k, x in v do out[deepcopy(k, seen)] = deepcopy(x, seen) end
	return out
end

return function(M, genDir, state, vw, vh, insets)
	local ui = setup(M, genDir, "rich", vw, vh, insets)
	local s = ui.session
	-- BuyData (the Studio's BUY DATA PLAN uses DataApp's remote): bind DatasetService like ui_setup binds the others
	do
		local ok, mod = pcall(M.require, M.game.ServerScriptService.Server.Services.DatasetService)
		if ok and mod.init then pcall(mod.init) end
	end
	local RS, Server = M.game.ReplicatedStorage, M.game.ServerScriptService.Server
	local Template = M.require(Server.Lib.Template)
	local MarketMath = M.require(RS.Shared.MarketMath)
	local ModelMath = M.require(RS.Shared.ModelMath)

	local states = {}
	states.rich = { data = deepcopy(s.data), live = deepcopy(s.live) }
	-- full: + a live Business API model (ui_setup "full")
	do
		local d, live = deepcopy(s.data), deepcopy(s.live)
		local stats = { reasoning = 58, coding = 52, math = 50, creativity = 64, knowledge = 61, reliability = 57, speed = 76, efficiency = 74 }
		local m = { id = "biz", name = "Ledger", version = 1, sizeId = "s1b", focusId = "balanced", status = "live", createdAt = 0, trainedAt = 0,
			stats = stats, overall = ModelMath.overall(stats), trainCost = 4200, dataUsed = { total = 2e9, quality = 0.8, shares = { general = 1 } } }
		m.release = { subPrice = 10, apiPrice = 2, marketing = 0, target = "businesses", releasedAt = 0, auto = true }
		m.market = MarketMath.newMarketState("businesses", 0)
		m.market.vage, m.market.age, m.market.users = 300, 300, { businesses = 4200 }
		d.models.biz = m
		table.insert(d.modelOrder, "biz")
		states.full = { data = d, live = live }
		local h, hl = deepcopy(d), deepcopy(live)
		h.empire.office = 5
		h.empire.labLevel = 6
		h.money = 2400000
		h.gpus = { accelerator = 10, datacenter = 2 }
		h.data = { general = { tokens = 30e9, quality = 0.8 }, code = { tokens = 15e9, quality = 0.82 }, math = { tokens = 8e9, quality = 0.8 } }
		hl.capacity, hl.load, hl.waitlist = 400000, 180000, 0
		states.hq = { data = h, live = hl }
	end
	-- empty garage company (ui_setup "empty")
	do
		local d = Template.new()
		d.company = { name = "Nimbus Labs", logo = "N", color = "cyan", spec = "general", reputation = 34, foundedAt = 0 }
		d.empire.office = 1
		d.money = 48250
		local live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} }
		states.empty = { data = d, live = live }
		local f = deepcopy(d)
		f.money = 12200
		f.data = {}
		states.fresh = { data = f, live = deepcopy(live) }
		local st = deepcopy(d)
		st.money = 4800
		st.data = { general = { tokens = 2e9, quality = 0.35 }, code = { tokens = 2e9, quality = 0.5 } }
		states.starter = { data = st, live = deepcopy(live) }
	end

	local Client = M.game.StarterPlayer.StarterPlayerScripts.Client
	ui.Studio = M.require(Client.UI.Lab.Studio)
	ui.LabState = M.require(Client.UI.Lab.LabState)
	ui.LabPreview = M.require(Client.UI.Lab.LabPreview)
	ui.AIModelService = M.require(Server.Services.AIModelService)
	ui.states = states
	function ui.use(name)
		local def = states[name]
		assert(def, "unknown lab state " .. tostring(name))
		s.data = deepcopy(def.data)
		s.live = deepcopy(def.live)
		ui.state = name
		-- client session memory starts fresh for every state
		table.clear(ui.LabState.reveals)
		table.clear(ui.LabState.plannedLine)
		ui.LabState.name = ""
		ui.LabState.colorId = nil
		ui.LabState.emblem = nil
		ui.LabState.lineId = "general"
		ui.LabState.step = 1
		ui.LabState.firstDefaults = false
		ui.LabState.revealing = nil
		ui.Studio.setBanner(nil, nil)
		if ui.Studio.isOpen() then ui.Studio.close() end
		ui.push()
		return s, s.data
	end
	ui.use(state or "rich")
	return ui
end
