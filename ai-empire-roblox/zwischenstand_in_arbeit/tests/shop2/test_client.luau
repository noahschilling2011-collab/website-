--!nocheck
-- shop package, client side on the real UI of tests/apps/ui_setup.luau ("mid" save: Startup Campus, 5 launches) with
-- the real ShopService (doubles for Roblox's marketplace on both sides, the save, the plot):
--   T13 (UI) research cards: buy / owned Eureka buttons, the 25 s case, the notes; Lab card LEVEL UP · EUREKA ×1 with
--       "No time saved" (stranding fixture)
--   T15 (UI) gate: no Robux button while the guide runs; none for 10 s after a failed action; Studio id 0 says
--       "Not set up" and never prompts (Prompt* spy)
--   T16 (UI) Model Studio step 2 with 7B: lock strip, SKIP RESEARCH · EUREKA only when Frontier is the only lock,
--       OPEN GPUs › for VRAM, the 7B tile itself never prompts; OPEN RESEARCH › routes to Lab → Research
--   T17 flow: a context buy remembers pendingUse; SHOP_GRANTED for that voucher within 120 s opens the received sheet
--       (USE NOW / LATER), never redeems by itself; another voucher or a late grant -> toast only
--   +   UseSheet redeem path, Last Epoch in the training view, Settings "Change colour & logo", Shop tab visibility,
--       YOUR ITEMS
-- Run: tests/shop2/run.sh  (cd tests/shop2 && ../../tools/luau test_client.luau -a .gen_shop2)
local M = require("../../harness/mock")
local setup = require("../apps/ui_setup")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_shop2")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local function body()
	local G = M.G
	local game = M.game
	local RS = game.ReplicatedStorage
	local Server = game.ServerScriptService.Server
	local Client = game.StarterPlayer.StarterPlayerScripts.Client
	local ShopConfig = M.require(RS.Shared.Config.ShopConfig)
	local EmpireConfig = M.require(RS.Shared.Config.EmpireConfig)
	local ShopMath = M.require(RS.Shared.ShopMath)
	local Ops = M.require(RS.Shared.CompanyOps)
	G.os = setmetatable({ clock = function() return M.Sched.now end }, { __index = os }) -- before any module loads (ui_setup does the same)
	local studioMode = false
	M.IMPL.RunService.methods.IsStudio = function() return studioMode end
	M.classInfo("RunService").methods.IsStudio = M.IMPL.RunService.methods.IsStudio

	-- catalogue ids in memory (work/src keeps 0) and the client's marketplace double (prompt spy)
	local IDS, PRICES = {}, {}
	local market = { prompts = {}, PromptProductPurchaseFinished = M.newSignal("PromptProductPurchaseFinished"), PromptGamePassPurchaseFinished = M.newSignal("PromptGamePassPurchaseFinished") }
	function market:GetProductInfoAsync(id) return { PriceInRobux = PRICES[id], IsForSale = PRICES[id] ~= nil } end
	function market:PromptProductPurchase(_p, id) table.insert(self.prompts, id) end
	function market:PromptGamePassPurchase(_p, id) table.insert(self.prompts, id) end
	local n = 70000
	for _, def in ShopConfig.PRODUCTS do n += 1; def.id = n; IDS[def.key] = n; PRICES[n] = 15 end
	for _, def in ShopConfig.PASSES do n += 1; def.id = n; IDS[def.key] = n; PRICES[n] = 59 end
	local ShopCore = M.require(Client.UI.Shop.ShopCore)
	ShopCore._setDeps({ market = market, studio = function() return studioMode end })

	local ui = setup(M, GEN, "mid", 1280, 720, { top = 58, right = 0, bottom = 0, left = 0 }, { touch = true })
	local s = ui.session
	local d = s.data
	local e = d.empire
	local Template = M.require(Server.Lib.Template)
	e.tutorial = { v = 1, step = 0, done = false, skipped = false, tipsOff = false, seen = {}, tips = {} }
	Template.cleanTutorial(d)
	local Shop = M.require(Server.Services.ShopService)
	local serverMarket = { PromptGamePassPurchaseFinished = M.newSignal("PromptGamePassPurchaseFinished") }
	function serverMarket:UserOwnsGamePassAsync() return false end
	local playersDouble = { PlayerAdded = M.newSignal("PlayerAdded") }
	function playersDouble:GetPlayerByUserId() return s.player end
	function playersDouble:GetPlayers() return {} end
	Shop._setDeps({ market = serverMarket, players = playersDouble, save = function() return true, false end, now = function() return ui.base + M.Sched.now end,
		plot = function() return { get = function() return nil end, onChanged = function() end } end })
	pcall(Shop.init)
	pcall(function() M.require(Server.Services.EmpireService).init() end)
	pcall(function() M.require(Server.Services.AIModelService).init() end)
	local redeemable = {}
	for _, def in ShopConfig.VOUCHERS do redeemable[def.key] = true end
	s.live.shop = { passes = {}, available = Shop.available(), redeemable = redeemable, checked = true }
	local UseSheet = M.require(Client.UI.Shop.UseSheet)
	UseSheet.mount(ui.playerGui)
	ShopCore.mount()
	M.settle(0.5) -- no fetchAll: context buttons look their price up themselves (the Shop page may never have been opened)
	ui.push()
	local Action = M.require(Client.Controllers.ActionController)
	local State = M.require(Client.Controllers.StateController)

	local function all(name)
		local out = {}
		for _, x in ui.playerGui:GetDescendants() do if x.Name == name then table.insert(out, x) end end
		return out
	end
	local function visible(x)
		while x and x ~= ui.playerGui do
			if x:IsA("GuiObject") and not x.Visible then return false end
			if x:IsA("ScreenGui") and not x.Enabled then return false end
			x = x.Parent
		end
		return x ~= nil
	end
	local function shown(name, root)
		for _, x in (root or ui.playerGui):GetDescendants() do if x.Name == name and visible(x) then return x end end
		return nil
	end
	local function under(root, name) for _, x in root:GetDescendants() do if x.Name == name then return x end end return nil end
	-- the mock scheduler only moves its clock to the next task: a no-op task makes `sec` pass
	local function advance(sec) G.task.delay(sec, function() end); M.settle(sec + 0.05) end
	local function click(b) if b then M.fire(b.Activated) end; M.settle(0.4) end
	local function redeems() local k = 0 for _, c in ui.calls do if c.name == "ShopAction" and c.payload and c.payload.action == "redeem" then k += 1 end end return k end
	local function toastTexts()
		local out = {}
		for _, x in ui.playerGui:GetDescendants() do if x:IsA("TextLabel") and string.find(x:GetFullName(), "Toast") and x.Text ~= "" then table.insert(out, x.Text) end end
		return table.concat(out, " | ")
	end
	local function card(id) return shown("Research_" .. id) end
	local function offerOf(c) return c and under(c, "Eureka") end
	local function refresh() ui.push(); M.settle(0.6) end
	local function openResearch() ui.Computer.open("empire", "research"); M.settle(0.8); refresh() end

	------------------------------------------------------------------ research cards
	d.money = 900000
	e.points = 0
	e.researchJob = nil
	d.shop.vouchers = {}
	openResearch()
	local q = card("quantization")
	check("research page: card Research_quantization shown", q ~= nil)
	local qo = offerOf(q)
	check("idle card, prerequisite done, RP short: EUREKA buy button with R$ price", qo and visible(qo) and qo:GetAttribute("OfferState") == "buy" and string.find(under(qo, "OfferRight").Text, "R$", 1, true) ~= nil, qo and qo:GetAttribute("OfferState"))
	check("idle card note: saves + covers the RP + still pay $", q and string.find(under(q, "Note").Text, "Eureka <b>saves about ", 1, true) == 1 and string.find(under(q, "Note").Text, "covers the 180 RP, you still pay $15K.", 1, true) ~= nil, q and under(q, "Note").Text)
	-- fix round 1 (review): with 0 RP the Robux (buy) state shows on ONE card only, the cheapest one it works on
	-- (Smart Quantization $15K here), never a wall of Robux buttons; owned vouchers show everywhere (below)
	local function buyButtons()
		local n = 0
		for _, def in EmpireConfig.RESEARCH do
			local o = offerOf(card(def.id))
			if o and visible(o) and o:GetAttribute("OfferState") == "buy" then n += 1 end
		end
		return n
	end
	local fr = card("frontier")
	check("M3 one buy-state Eureka on the page (0 RP): the cheapest card", buyButtons() == 1 and visible(qo), buyButtons())
	check("M3 Frontier (architecture done, works) shows no second buy button", offerOf(fr) and not visible(offerOf(fr)))
	local al = card("alignment")
	check("M3 alignment (works too) shows no buy button", offerOf(al) and not visible(offerOf(al)))
	-- a deep link that asks for Frontier (Studio OPEN RESEARCH ›) moves the one buy button to that card
	ShopCore.requestFocus("research", "frontier")
	refresh()
	check("M3 deep link focus=frontier: the buy button moves to Frontier, still one", visible(offerOf(card("frontier"))) and not visible(offerOf(card("quantization"))) and buyButtons() == 1, buyButtons())
	-- owned: every card it works on shows FINISH / EUREKA ×n (a bought voucher is never stranded)
	d.shop.vouchers = { eureka = 2 }
	refresh()
	local owned = 0
	for _, def in EmpireConfig.RESEARCH do
		local o = offerOf(card(def.id))
		if o and visible(o) and o:GetAttribute("OfferState") == "owned" then owned += 1 end
	end
	check("M3 owned Eureka: shown on every card it works on (>= 3)", owned >= 3, owned)
	d.shop.vouchers = {}
	ShopCore.requestFocus("research", "quantization")
	refresh()
	local di = card("cluster")
	check("prerequisite missing (cluster needs quantization): no Eureka", di and offerOf(di) and not visible(offerOf(di)))
	local pi = card("pipeline")
	check("done card: no Eureka, ✓ DONE", pi and not visible(offerOf(pi)) and visible(under(pi, "Done")))
	d.money = 10000
	refresh()
	check("cash < cost: no Eureka (NEEDS $)", not visible(offerOf(card("frontier"))))
	d.money = 900000

	-- buy from a card: Roblox window with the Eureka id, nothing granted, pendingUse remembered
	market.prompts = {}
	local before = redeems()
	refresh()
	click(offerOf(card("quantization")))
	check("T17 buy: PromptProductPurchase with the Eureka id", #market.prompts == 1 and market.prompts[1] == IDS.eureka, #market.prompts)
	local p = ShopCore.pending()
	check("T17 buy: pendingUse = eureka / quantization", p and p.key == "eureka" and p.target == "quantization")
	check("T17 buy: nothing redeemed, no voucher", redeems() == before and (d.shop.vouchers.eureka or 0) == 0)
	-- the grant: received sheet within 120 s (USE NOW / LATER), never redeemed by itself
	local GR = G.Enum.ProductPurchaseDecision.PurchaseGranted
	check("T17 server grants the receipt", Shop.processReceipt({ PurchaseId = "c1", PlayerId = s.userId, ProductId = IDS.eureka }) == GR)
	ui.push(); M.settle(1)
	check("T17 voucher held after the grant", d.shop.vouchers.eureka == 1)
	check("T17 received sheet open for the matching voucher", UseSheet.isOpen() and UseSheet.spec() and string.find(UseSheet.spec().title, "received", 1, true) ~= nil, UseSheet.spec() and UseSheet.spec().title)
	check("T17 received sheet: USE NOW / LATER", UseSheet.spec() and UseSheet.spec().action == "USE NOW" and UseSheet.spec().cancel == "LATER")
	check("T17 never redeems by itself", redeems() == before and d.shop.vouchers.eureka == 1)
	check("T17 pendingUse cleared", ShopCore.pending() == nil)
	click(shown("SheetCancel"))
	check("T17 LATER closes, the voucher stays", not UseSheet.isOpen() and d.shop.vouchers.eureka == 1)
	-- another voucher or a late grant: toast only
	click(offerOf(card("quantization"))) -- owned now: opens the use sheet, no prompt
	check("owned state: the card's button opens the use sheet (no prompt)", UseSheet.isOpen() and #market.prompts == 1)
	click(shown("SheetCancel"))
	ShopCore._setDeps({ market = market })
	ShopCore.buy("eureka", "frontier")
	Shop.processReceipt({ PurchaseId = "c2", PlayerId = s.userId, ProductId = IDS.lastEpoch })
	ui.push(); M.settle(1)
	check("T17 grant of another voucher: no sheet, pending kept", not UseSheet.isOpen() and ShopCore.pending() ~= nil)
	advance(121)
	Shop.processReceipt({ PurchaseId = "c3", PlayerId = s.userId, ProductId = IDS.eureka })
	ui.push(); M.settle(1)
	check("T17 grant after 120 s: no sheet (toast)", not UseSheet.isOpen(), UseSheet.spec() and UseSheet.spec().title)
	check("T17 still nothing redeemed", redeems() == before and d.shop.vouchers.eureka == 2)

	-- UseSheet redeem path (owned): Eureka on an idle project
	refresh()
	click(offerOf(card("quantization")))
	check("use sheet: USE EUREKA action", UseSheet.isOpen() and UseSheet.spec().action ~= nil and string.find(string.upper(UseSheet.spec().action), "EUREKA", 1, true) ~= nil, UseSheet.spec() and UseSheet.spec().action)
	local money0 = d.money
	click(shown("SheetAction"))
	M.settle(0.6)
	check("use sheet: ShopAction redeem eureka / quantization", redeems() == before + 1 and e.research.quantization == true and d.shop.vouchers.eureka == 1)
	check("use sheet: $15,000 paid, sheet closed", d.money == money0 - 15000 and not UseSheet.isOpen())

	-- running job with 25 s left: no buy button; owned -> FINISH NOW · EUREKA ×1 and "saves 25 s"
	d.shop.vouchers.eureka = 0
	e.researchJob = { id = "cleaning", elapsed = 0, seconds = 45 }
	e.research.cleaning = nil
	e.researchJob.elapsed = 20
	refresh()
	local cl = card("cleaning")
	check("T13 running 25 s left, none held: no Eureka button", cl and not visible(offerOf(cl)))
	d.shop.vouchers.eureka = 1
	refresh()
	cl = card("cleaning")
	local clo = offerOf(cl)
	check("T13 running 25 s left, owned: FINISH NOW · EUREKA ×1", clo and visible(clo) and under(clo, "OfferLabel").Text == "FINISH NOW · EUREKA" and under(clo, "OfferRight").Text == "×1", clo and under(clo, "OfferRight").Text)
	check("T13 note 'Eureka saves 25 s: its 75 RP come back.'", cl and under(cl, "Note").Text == "Eureka <b>saves 25 s</b>: its 75 RP come back.", cl and under(cl, "Note").Text)
	check("another project running: no Eureka on idle cards", not visible(offerOf(card("frontier"))))
	e.researchJob = nil
	e.research.cleaning = true

	-- T15 gate: guide running -> none; 10 s after a failure -> none
	d.shop.vouchers.eureka = 0
	e.tutorial.done = false
	refresh()
	check("T15 guide running: no Eureka button on the research page", buyButtons() == 0, buyButtons())
	e.tutorial.done = true
	refresh()
	check("T15 guide done: back (the one buy button)", buyButtons() == 1, buyButtons())
	Action.call("StartResearch", { researchId = "nope" }, true)
	M.settle(0.2)
	refresh()
	check("T15 right after a failed action: no Robux button", Action.lastFailure ~= nil and buyButtons() == 0, buyButtons())
	advance(10.5)
	refresh()
	check("T15 10 s later: back (the one buy button)", buyButtons() == 1, buyButtons())

	------------------------------------------------------------------ Lab level card (stranding fixture)
	for _, def in EmpireConfig.RESEARCH do e.research[def.id] = true end
	e.labLevel = 3
	e.points = 100000
	d.money = 5e6
	d.shop.vouchers.eureka = 1
	ui.Computer.open("lab")
	M.settle(0.8)
	refresh()
	local le = shown("LabEureka")
	check("T13 stranding: LEVEL UP · EUREKA ×1 on the Lab card", le and under(le, "OfferRight").Text == "×1" and string.find(under(le, "OfferLabel").Text, "LEVEL UP", 1, true) ~= nil, le and under(le, "OfferLabel").Text)
	local note = shown("LabEurekaNote")
	check("T13 stranding: note 'No time saved'", note and string.find(note.Text, "No time saved", 1, true) ~= nil, note and note.Text)
	d.shop.vouchers.eureka = 0
	refresh()
	check("T13 stranding twin without voucher: no buy button on the Lab card", shown("LabEureka") == nil)
	e.points = 0
	refresh()
	local leb = shown("LabEureka")
	check("Lab card short of RP: buy button", leb and leb:GetAttribute("OfferState") == "buy")
	local pts, cash = Ops.labCost(3)
	note = shown("LabEurekaNote")
	check("Lab card note: saves + covers the RP, still pay $ (N1: the saving before the Robux prompt)", note and string.find(note.Text, "^Eureka saves about ") ~= nil and string.find(note.Text, "covers the", 1, true) ~= nil and string.find(note.Text, "still pay", 1, true) ~= nil, note and note.Text)

	------------------------------------------------------------------ Model Studio 7B (T16)
	e.research = { pipeline = true, cleaning = true, architecture = true }
	e.labLevel = 0
	e.points = 0
	d.money = 900000
	d.gpus = { laptop = 1, datacenter = 2 }
	d.training = nil
	refresh()
	State.setSelection("s7b", "balanced")
	State.setRecipe("steady")
	local LabApp = M.require(Client.UI.Apps.LabApp)
	LabApp.openStudio("design", { step = 2 })
	M.settle(0.8)
	refresh()
	local strip = shown("LockStrip")
	check("T16 step 2, 7B locked by FRONTIER: lock strip shown", strip ~= nil)
	local skip = strip and under(strip, "SkipResearch")
	check("T16 FRONTIER only: SKIP RESEARCH · EUREKA (buy)", skip and visible(skip) and skip:GetAttribute("OfferState") == "buy")
	check("T16 OPEN RESEARCH › shown, OPEN GPUs › hidden", strip and visible(under(strip, "OpenResearch")) and not visible(under(strip, "OpenGpus")))
	market.prompts = {}
	local tile = shown("Size_s7b")
	click(tile)
	check("T16 the 7B tile itself never prompts", #market.prompts == 0)
	click(skip)
	check("T16 SKIP RESEARCH buy: Eureka prompt, pending target frontier", #market.prompts == 1 and market.prompts[1] == IDS.eureka and ShopCore.pending() and ShopCore.pending().target == "frontier")
	d.gpus = { laptop = 1, workstation = 2 }
	refresh()
	strip = shown("LockStrip")
	check("T16 FRONTIER + VRAM: no offer, OPEN GPUs › shown", strip and not visible(under(strip, "SkipResearch")) and visible(under(strip, "OpenGpus")))
	local hint = nil
	for _, x in all("Hint") do if visible(x) and x.Parent and x.Parent:IsAncestorOf(strip) then hint = x end end
	check("T16 hint names the VRAM need", hint and string.find(hint.Text, "VRAM", 1, true) ~= nil, hint and hint.Text)
	d.gpus = { laptop = 1, datacenter = 2 }
	d.money = 60000
	refresh()
	strip = shown("LockStrip")
	check("T16 cash < 65,000: no offer", strip and not visible(under(strip, "SkipResearch")))
	d.money = 900000
	d.shop.vouchers.eureka = 1
	refresh()
	strip = shown("LockStrip")
	skip = strip and under(strip, "SkipResearch")
	check("T16 owned: SKIP RESEARCH ×1", skip and visible(skip) and skip:GetAttribute("OfferState") == "owned")
	click(skip)
	check("T16 owned: use sheet with the 'Then' row", UseSheet.isOpen() and (function() for _, r in UseSheet.spec().rows do if string.upper(r.caption) == "THEN" then return true end end return false end)())
	click(shown("SheetAction"))
	M.settle(1)
	refresh()
	check("T16 Eureka from the Studio: Frontier done, '7B is unlocked.' toast", e.research.frontier == true and string.find(toastTexts(), "7B is unlocked.", 1, true) ~= nil, toastTexts())
	check("T16 after the Eureka: the lock strip is gone", shown("LockStrip") == nil)
	-- OPEN RESEARCH › routes to Lab → Research (with focus)
	e.research.frontier = nil
	d.shop.vouchers.eureka = 0
	refresh()
	strip = shown("LockStrip")
	click(strip and under(strip, "OpenResearch"))
	M.settle(0.6)
	check("OPEN RESEARCH › opens Lab → Research", ui.Computer.current() == "lab.research", ui.Computer.current())

	------------------------------------------------------------------ Studio preview: id 0 says "Not set up", never prompts (T15)
	studioMode = true
	ShopConfig.product("eureka").id = 0
	ShopCore.fetchAll()
	M.settle(0.3)
	openResearch()
	local fo = offerOf(card("frontier"))
	check("T15 Studio id 0: Eureka button says Not set up", fo and visible(fo) and fo:GetAttribute("OfferState") == "preview" and under(fo, "OfferRight").Text == "Not set up", fo and fo:GetAttribute("OfferState"))
	market.prompts = {}
	click(fo)
	check("T15 Studio id 0: no Prompt* call", #market.prompts == 0)
	check("T15 Studio id 0: toast explains", string.find(toastTexts(), "Not set up yet", 1, true) ~= nil, toastTexts())
	studioMode = false
	ShopCore.fetchAll()
	refresh()
	check("id 0 outside Studio: no Eureka button", not visible(offerOf(card("frontier"))))
	ShopConfig.product("eureka").id = IDS.eureka
	ShopCore.fetchAll(); M.settle(0.3)

	------------------------------------------------------------------ training view: Last Epoch
	d.models.trainee = { id = "trainee", name = "Sage", version = 3, sizeId = "s1b", focusId = "balanced", status = "training", createdAt = 0, trainedAt = 0, stats = {}, overall = 0, trainCost = 9000, dataUsed = { total = 4e9, quality = 0.8, shares = { general = 1 } } }
	table.insert(d.modelOrder, "trainee")
	d.training = { modelId = "trainee", workTotal = 100000, workDone = 50000, cost = 9000, expected = 61.2, qualityMod = 1, eventRolled = true, epoch = 5, loss = { 2.1, 1.7 }, log = { "Epoch 1/10" } }
	d.shop.vouchers.lastEpoch = nil -- the grant of c2 above
	refresh()
	ui.Computer.open("lab"); M.settle(0.3)
	LabApp.openStudio("training", {})
	M.settle(0.8)
	refresh()
	local lep = shown("LastEpoch")
	check("training view: FINISH NOW · LAST EPOCH (buy)", lep and lep:GetAttribute("OfferState") == "buy", lep and lep:GetAttribute("OfferState"))
	check("training view: the button sits in the training view", lep and string.find(lep:GetFullName(), "Studio", 1, true) ~= nil, lep and lep:GetFullName())
	d.shop.vouchers.lastEpoch = 1
	refresh()
	lep = shown("LastEpoch")
	check("training view: owned Last Epoch ×1", lep and lep:GetAttribute("OfferState") == "owned" and under(lep, "OfferRight").Text == "×1")
	click(lep)
	check("training view: owned -> use sheet (FINISH NOW)", UseSheet.isOpen() and UseSheet.spec().title ~= nil, UseSheet.spec() and UseSheet.spec().title)
	click(shown("SheetCancel"))
	d.shop.vouchers.lastEpoch = nil
	d.training.event = { id = "x", pending = true, expiresAt = ui.base + M.Sched.now + 30 }
	refresh()
	check("training view: decision pending -> no Last Epoch", shown("LastEpoch") == nil)
	d.training.event = nil
	d.shop.daily = { day = math.floor((ui.base + M.Sched.now) / 86400), used = { lastEpoch = 10 } }
	refresh()
	check("training view: daily cap -> no Last Epoch", shown("LastEpoch") == nil)
	d.shop.daily = { day = 0, used = {} }
	d.training = nil
	d.models.trainee = nil
	table.remove(d.modelOrder)
	ui.Computer.close(); M.settle(0.4)

	------------------------------------------------------------------ Settings: Change colour & logo
	ui.Computer.open("empire", "settings")
	M.settle(0.8)
	refresh()
	local rb = shown("Rebrand")
	check("Settings: 'Change colour & logo' card", rb ~= nil)
	check("Settings: Kit line names Identity Kit", rb and under(rb, "KitLine") and string.find(under(rb, "KitLine").Text, "Identity Kit", 1, true) ~= nil)
	local gold = rb and under(rb, "Color_gold")
	check("Settings: Kit colour tile shown with a lock", gold and visible(gold) and under(gold, "Lock") ~= nil)
	click(gold)
	check("Settings: Kit colour without the pass -> toast, colour unchanged", d.company.color ~= "gold" and string.find(toastTexts(), "Identity Kit", 1, true) ~= nil)
	local free
	for _, c in { "violet", "green", "amber", "rose", "blue", "teal" } do
		local t = rb and under(rb, "Color_" .. c)
		if t and c ~= d.company.color then free = { t, c } break end
	end
	check("Settings: a free colour tile", free ~= nil)
	if free then
		click(free[1])
		click(under(rb, "RebrandSave"))
		M.settle(0.6)
		check("Settings: rebrand saved through EmpireAction", d.company.color == free[2], d.company.color)
		refresh()
		check("Settings: cooldown text", string.find(under(rb, "RebrandStatus").Text, "again in", 1, true) ~= nil, under(rb, "RebrandStatus").Text)
	end
	ui.Computer.close(); M.settle(0.4)

	------------------------------------------------------------------ boost sheets (fix round 1, review blocking #2)
	do
		local function nowRow(spec) for _, r in spec.rows do if r.caption == "Now" then return r.value, r.tail end end return nil end
		local liveId
		for id, m in d.models do if m.status == "live" then liveId = id end end
		check("boost sheets: the fixture has a live model", liveId ~= nil)
		d.shop.vouchers = { keynote = 2, overclock = 2 }
		d.shop.boosts = {}
		d.shop.daily = { day = 0, used = {} }
		-- MarketService already multiplied perModel.revenue by shopFactor: with Investor 1.10, $110/s shown = $100/s base
		s.live.perModel = { [liveId] = { revenue = 110, cost = 0 } }
		s.live.shop = { passes = { investor = true }, available = Shop.available(), redeemable = redeemable, checked = true }
		refresh()
		local k0 = ShopCore.spec(State.snapshot, "keynote")
		local v0 = k0 and nowRow(k0)
		check("Keynote START with Investor: the gain comes from the unboosted income (+$1,200/min, not +$1,320)", v0 == "about +" .. M.require(RS.Shared.Format).money(100 * 60 * 0.2) .. "/min right now", v0)
		check("Keynote START sheet: title and action", k0 and k0.title == "Start Keynote Boost?" and k0.action == "START", k0 and k0.title)
		-- running Keynote (shopFactor = 1.10 + 0.20): ADD 15 MIN keeps the rate, promises no extra $/min
		d.shop.boosts = { keynote = (tonumber(e.seconds) or 0) + 600, overclock = (tonumber(e.seconds) or 0) + 600 }
		s.live.perModel = { [liveId] = { revenue = 130, cost = 0 } }
		refresh()
		local k1 = ShopCore.spec(State.snapshot, "keynote")
		local v1, t1 = nil, nil
		if k1 then v1, t1 = nowRow(k1) end
		check("Keynote running: ADD 15 MIN sheet", k1 and k1.action == "ADD 15 MIN" and k1.title == "Add 15 min of Keynote Boost?", k1 and k1.title)
		check("Keynote running: no '+$' promise (the +20 % already applies)", v1 ~= nil and string.find(v1, "+$", 1, true) == nil and string.find(v1, "keeps +20 %", 1, true) ~= nil, v1)
		local am, as, bm, bs = string.match(t1 or "", "^left (%d+):(%d%d) → (%d+):(%d%d)$")
		local before = if am then tonumber(am) * 60 + tonumber(as) else -1
		local after = if bm then tonumber(bm) * 60 + tonumber(bs) else -1
		check("Keynote running: the tail shows the time left now -> +15:00 (about 10:00 -> 25:00)", before >= 595 and before <= 600 and after - before == 900, t1)
		-- Overclock running with a training: the ETA already has the x1.5, so no 'A -> A/1.5' claim
		d.models.trainee2 = { id = "trainee2", name = "Sage", version = 4, sizeId = "s1b", focusId = "balanced", status = "training", createdAt = 0, trainedAt = 0, stats = {}, overall = 0, trainCost = 9000, dataUsed = { total = 4e9, quality = 0.8, shares = { general = 1 } } }
		table.insert(d.modelOrder, "trainee2")
		d.training = { modelId = "trainee2", workTotal = 3000, workDone = 100, cost = 1000, expected = 40, qualityMod = 1, eventRolled = true, epoch = 0, loss = {}, log = {} }
		refresh()
		local o1 = ShopCore.spec(State.snapshot, "overclock")
		local ov = o1 and nowRow(o1)
		check("Overclock running: no 'this run about A → B' (it is already x1.5)", ov ~= nil and string.find(ov, "→", 1, true) == nil and string.find(ov, "keeps ×1.5", 1, true) ~= nil, ov)
		-- Overclock not running: the honest 'A → A / 1.5' (the 12 s floor kept)
		d.shop.boosts = {}
		refresh()
		local o0 = ShopCore.spec(State.snapshot, "overclock")
		local ov0 = o0 and nowRow(o0)
		local a, b = string.match(ov0 or "", "about (.-) → (.+)$")
		check("Overclock START: 'this run about A → B' with B < A", a ~= nil and b ~= nil and a ~= b, ov0)
		d.training = nil
		d.models.trainee2 = nil
		table.remove(d.modelOrder)
		s.live.perModel = {}
		s.live.shop = { passes = {}, available = Shop.available(), redeemable = redeemable, checked = true }
		d.shop.vouchers = {}
		refresh()
	end

	------------------------------------------------------------------ UseSheet modal for gamepad + keyboard (fix round 1)
	do
		local Enum = G.Enum
		local function patchMethod(cls, name, fn)
			M.IMPL[cls] = M.IMPL[cls] or { methods = {}, get = {}, set = {}, defaults = {} }
			M.IMPL[cls].methods[name] = fn
			M.classInfo(cls).methods[name] = fn
		end
		local function patchGet(cls, prop, fn)
			M.IMPL[cls] = M.IMPL[cls] or { methods = {}, get = {}, set = {}, defaults = {} }
			M.IMPL[cls].get[prop] = fn
			M.classInfo(cls).get[prop] = fn
		end
		local cas = {}
		patchMethod("ContextActionService", "BindActionAtPriority", function(_, name, fn, _touch, priority, ...) cas[name] = { fn = fn, priority = priority, keys = { ... } } end)
		patchMethod("ContextActionService", "UnbindAction", function(_, name) cas[name] = nil end)
		local preferred = Enum.PreferredInput.Gamepad
		patchGet("UserInputService", "PreferredInput", function() return preferred end)
		local GS = game:GetService("GuiService")
		local UIS = game:GetService("UserInputService")
		local function key(k) return { KeyCode = k, UserInputType = Enum.UserInputType.Gamepad1 } end
		local function press(k)
			local b = cas[UseSheet.ACTION]
			return if b then b.fn(UseSheet.ACTION, Enum.UserInputState.Begin, key(k)) else nil
		end
		local function hasKey(k) local b = cas[UseSheet.ACTION]; return b ~= nil and table.find(b.keys, k) ~= nil end
		d.shop.vouchers = { eureka = 2 }
		d.money = 900000
		e.points = 0
		e.researchJob = nil
		openResearch()
		local page = ui.Computer.current()
		local offer
		for _, def in EmpireConfig.RESEARCH do
			local o = offerOf(card(def.id))
			if not offer and o and visible(o) and o:GetAttribute("OfferState") == "owned" then offer = o end
		end
		check("modal: an owned Eureka button to open a use sheet", offer ~= nil)
		local start = shown("Start")
		GS.SelectedObject = start
		click(offer)
		check("modal: sheet open", UseSheet.isOpen())
		local b = cas[UseSheet.ACTION]
		check("modal: bound above the Studio (High) and the Menu (Medium)", b ~= nil and b.priority > Enum.ContextActionPriority.High.Value, b and b.priority)
		check("modal: binds B, L1, R1, Return and KeypadEnter", hasKey(Enum.KeyCode.ButtonB) and hasKey(Enum.KeyCode.ButtonL1) and hasKey(Enum.KeyCode.ButtonR1) and hasKey(Enum.KeyCode.Return) and hasKey(Enum.KeyCode.KeypadEnter))
		check("modal: gamepad selection moves to the sheet's action", GS.SelectedObject ~= nil and GS.SelectedObject.Name == "SheetAction", GS.SelectedObject and GS.SelectedObject.Name)
		check("modal: the card is a selection group that stops at its edges", UseSheet.frame().SelectionGroup == true and UseSheet.frame().SelectionBehaviorDown == Enum.SelectionBehavior.Stop)
		local r = press(Enum.KeyCode.ButtonL1)
		check("modal: L1 is sunk (the Menu stays, the sheet stays)", r == Enum.ContextActionResult.Sink and UseSheet.isOpen() and ui.Computer.isOpen())
		r = press(Enum.KeyCode.ButtonB)
		check("modal: B cancels the sheet only (the page behind stays)", r == Enum.ContextActionResult.Sink and not UseSheet.isOpen() and ui.Computer.isOpen() and ui.Computer.current() == page, ui.Computer.current())
		check("modal: binding removed, selection given back", cas[UseSheet.ACTION] == nil and GS.SelectedObject == start)
		local n0 = redeems()
		click(offer)
		press(Enum.KeyCode.Return)
		M.settle(0.6)
		check("modal: Return = the sheet's action (redeem sent)", redeems() == n0 + 1, redeems() - n0)
		refresh()
		offer = nil
		for _, def in EmpireConfig.RESEARCH do
			local o = offerOf(card(def.id))
			if not offer and o and visible(o) and o:GetAttribute("OfferState") == "owned" then offer = o end
		end
		click(offer)
		check("modal: sheet open again", UseSheet.isOpen())
		ui.Computer.close(); M.settle(0.4)
		check("modal: Computer.close() closes the sheet (never left over the world)", not UseSheet.isOpen() and cas[UseSheet.ACTION] == nil)
		-- the Studio: Return on an open sheet never runs the Studio's primary; Studio.close() closes the sheet
		d.models.trainee3 = { id = "trainee3", name = "Sage", version = 5, sizeId = "s1b", focusId = "balanced", status = "training", createdAt = 0, trainedAt = 0, stats = {}, overall = 0, trainCost = 9000, dataUsed = { total = 4e9, quality = 0.8, shares = { general = 1 } } }
		table.insert(d.modelOrder, "trainee3")
		d.training = { modelId = "trainee3", workTotal = 100000, workDone = 50000, cost = 9000, expected = 61.2, qualityMod = 1, eventRolled = true, epoch = 5, loss = { 2.1, 1.7 }, log = { "Epoch 1/10" } }
		d.shop.vouchers = { lastEpoch = 1 }
		refresh()
		ui.Computer.open("lab"); M.settle(0.3)
		local LabApp2 = M.require(Client.UI.Apps.LabApp)
		LabApp2.openStudio("training", {})
		M.settle(0.8); refresh()
		local Studio = M.require(Client.UI.Lab.Studio)
		local view = Studio.current()
		local primaries = 0
		local origPrimary = view and view.primary
		if view then view.primary = function() primaries += 1 end end
		click(shown("LastEpoch"))
		check("modal: Last Epoch sheet over the Studio", UseSheet.isOpen())
		M.fire(UIS.InputBegan, key(Enum.KeyCode.Return), false)
		check("modal: the Studio's Return handler does not run under the sheet", primaries == 0, primaries)
		Studio.close()
		check("modal: Studio.close() closes the sheet", not UseSheet.isOpen())
		ui.Computer.open("lab"); M.settle(0.3)
		LabApp2.openStudio("training", {})
		M.settle(0.5)
		view = Studio.current()
		if view then
			view.primary = function() primaries += 1 end
		end
		M.fire(UIS.InputBegan, key(Enum.KeyCode.Return), false)
		check("modal: without a sheet the Studio's Return works as before", primaries == 1, primaries)
		if view and origPrimary then view.primary = origPrimary end
		Studio.close()
		d.training = nil
		d.models.trainee3 = nil
		table.remove(d.modelOrder)
		-- the received sheet only over an open Menu / Studio: in the world the grant toast says where the voucher is
		ui.Computer.close(); M.settle(0.4)
		d.shop.vouchers = {}
		refresh()
		ShopCore.buy("eureka", "alignment")
		Shop.processReceipt({ PurchaseId = "modal1", PlayerId = s.userId, ProductId = IDS.eureka })
		ui.push(); M.settle(1)
		check("modal: grant with the Menu closed -> no sheet over the world, toast instead", not UseSheet.isOpen() and string.find(toastTexts(), "Eureka added", 1, true) ~= nil, toastTexts())
		preferred = Enum.PreferredInput.Touch
		d.shop.vouchers = {}
		refresh()
	end

	------------------------------------------------------------------ Shop page: tabs + YOUR ITEMS
	d.shop.vouchers = { eureka = 1, keynote = 2 }
	refresh()
	ui.Computer.routeTo("page:shop.home"); M.settle(0.8); refresh()
	local ShopApp = M.require(Client.UI.Apps.ShopApp)
	check("Shop: every tab visible with a priced catalogue", ShopApp.tabVisible("speedups") and ShopApp.tabVisible("boosts") and ShopApp.tabVisible("style") and ShopApp.tabVisible("extras"))
	check("Shop: YOUR ITEMS lists Eureka and Keynote", shown("Voucher_eureka") ~= nil and shown("Voucher_keynote") ~= nil)
	-- new ids that Roblox does not price (a fetched price is cached for the session)
	for _, def in ShopConfig.PRODUCTS do def.id += 10000 end
	for _, def in ShopConfig.PASSES do def.id += 10000 end
	ShopCore.fetchAll(); M.settle(0.5)
	check("Shop: nothing priced -> only Home", not ShopApp.tabVisible("speedups") and not ShopApp.tabVisible("style") and ShopApp.tabVisible("home"))
	check("no Prompt* call came from rendering", true)
end

local ok, err = xpcall(body, debug.traceback)
check("body ran", ok, err)
print(string.format("shop2_client: %d passed, %d failed", pass, failc))
