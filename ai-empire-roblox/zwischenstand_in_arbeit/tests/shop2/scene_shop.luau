--!nocheck
-- guiprev scene of the shop package (SHOP_SPEC 5): the real client UI of tests/apps/ui_setup.luau (HUD, Menu, Toasts,
-- real server handlers) plus the real ShopService (doubles for Roblox's marketplace, the save and the plot), the
-- UseSheet layer and the Model Studio.
--   python3 tools/guiprev/guiprev.py --scene tests/shop2/scene_shop.luau --gen harness/.gen_shop2 --no-manifest \
--       --state mid --viewport phone --dpr 2 --out out/shop/x.png touch=1 app=shop section=home catalog=1
-- states: the ui_setup states (garage client save mid rich). Options (after the guiprev options):
--   app=<Computer.open app> section=<s> page=<menu page key>   which Menu page to show
--   catalog=1        every product / pass gets a test id and its suggested price (in memory only; work/src untouched)
--   studio=1         RunService:IsStudio() = true (owner preview: "Not set up", never prompts)
--   vouchers=k:n,..  held vouchers           boost=key:secondsLeft,..   running boosts (play time)
--   owned=k,..       owned passes (live.shop.passes)          daily=key:n,..   today's redeems
--   sheet=eureka:<target>|lastEpoch|keynote|overclock   open the UseSheet like a tap on the owned button
--   received=eureka:<target>   the "received - use it now?" sheet          studio7b=1 Model Studio step 2 with 7B picked
--   review7b=1  Model Studio step 6 (Review) with 7B picked        training=<0..1> a running training at that progress
--   tutorial=1  the guide is still running (no Robux buttons)      money=<n>  cash        points=<n> research points
--   research=a,b  research done (replaces)    job=<id>:<elapsed>  a running research project     lab=<n> Lab level
--   vram=<gb>  GPUs for that VRAM (128 = enough for 7B)             released=0  no launch yet
--   reveal=<s>  with trainingview=1: finish the training and dump <s> seconds into the reveal (Stage Lights: owned=stageLights)
--   scroll=<px>  scroll the shown Menu page (PageScroll) to that canvas position
--   packs=k,..  cash packs already bought for this office (buy chip hidden, "Bought for this office")
--   focus=<Name>  scroll the page so the first visible element with that name is at the top (ShopCore.scrollTo)
local P = print
local M = require("../../harness/mock")
local GuiDump = require("../../tools/guiprev/guidump")
local setup = require("../apps/ui_setup")
local args = { ... }
local GEN = args[1] or "../../harness/.gen_shop2"
local STATE = args[2] or "mid"
local VW, VH = tonumber(args[3]) or 1280, tonumber(args[4]) or 720
local insetList = string.split(args[5] or "58,0,0,0", ",")
local INSETS = { top = tonumber(insetList[1]) or 0, right = tonumber(insetList[2]) or 0, bottom = tonumber(insetList[3]) or 0, left = tonumber(insetList[4]) or 0 }
local FEEDBACK = if args[6] and args[6] ~= "-" then require(args[6]) else nil
local OPT = {}
for i = 7, #args do
	local k, v = string.match(args[i], "^([%w_]+)=(.*)$")
	if k then OPT[k] = v end
end

M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
GuiDump.init(M)

local SUGGESTED = { eureka = 15, lastEpoch = 9, keynote = 35, overclock = 19, fireworks = 19, identityKit = 59, serverGlow = 45, stageLights = 39,
	aiGallery = 65, teamHoodies = 75, roboBuddy = 95, styleCollection = 109, seed = 25, seriesA = 45, seriesB = 75, headhunter = 39, party = 25,
	tip = 25, bigTip = 100, vip = 149, limo = 199, founderSuite = 199, investor = 349 }

local function pairsOf(text)
	local out = {}
	for item in string.gmatch(text or "", "[^,]+") do
		local k, v = string.match(item, "^([%w_]+):?(.*)$")
		if k then out[k] = v end
	end
	return out
end

local function body()
	local G = M.G
	local game = M.game
	local RS = game.ReplicatedStorage
	local Server = game.ServerScriptService.Server
	local Client = game.StarterPlayer.StarterPlayerScripts.Client
	local ShopConfig = M.require(RS.Shared.Config.ShopConfig)
	local EmpireConfig = M.require(RS.Shared.Config.EmpireConfig)
	if OPT.studio == "1" then
		M.IMPL.RunService.methods.IsStudio = function() return true end
		M.classInfo("RunService").methods.IsStudio = function() return true end
	end
	-- catalogue ids (in memory) + the client's marketplace double (prices = SHOP_SPEC 2 suggestions)
	local clientMarket = { prompts = {}, PromptProductPurchaseFinished = M.newSignal("PromptProductPurchaseFinished"), PromptGamePassPurchaseFinished = M.newSignal("PromptGamePassPurchaseFinished"), prices = {} }
	function clientMarket:GetProductInfoAsync(id) return { PriceInRobux = self.prices[id], IsForSale = self.prices[id] ~= nil } end
	function clientMarket:PromptProductPurchase(_p, id) table.insert(self.prompts, id) end
	function clientMarket:PromptGamePassPurchase(_p, id) table.insert(self.prompts, id) end
	if OPT.catalog == "1" then
		local id = 50000
		for _, def in ShopConfig.PRODUCTS do id += 1; def.id = id; clientMarket.prices[id] = SUGGESTED[def.key] end
		for _, def in ShopConfig.PASSES do id += 1; def.id = id; clientMarket.prices[id] = SUGGESTED[def.key] end
	end
	local ShopCore = M.require(Client.UI.Shop.ShopCore)
	ShopCore._setDeps({ market = clientMarket, studio = function() return OPT.studio == "1" end })

	local ui = setup(M, GEN, STATE, VW, VH, INSETS, { touch = OPT.touch == "1" })
	local s = ui.session
	local d = s.data
	local e = d.empire
	if OPT.touch == "1" then
		local uis = game:GetService("UserInputService")
		pcall(function() uis[M.KEY].props.PreferredInput = G.Enum.PreferredInput.Touch end)
	end
	-- the real ShopService with doubles (its ShopAction lands in ui.binds through ui_setup's Remote.bind hook)
	local Shop = M.require(Server.Services.ShopService)
	local serverMarket = { PromptGamePassPurchaseFinished = M.newSignal("PromptGamePassPurchaseFinished") }
	function serverMarket:UserOwnsGamePassAsync() return false end
	local playersDouble = { PlayerAdded = M.newSignal("PlayerAdded") }
	function playersDouble:GetPlayerByUserId() return s.player end
	function playersDouble:GetPlayers() return {} end
	Shop._setDeps({ market = serverMarket, players = playersDouble, save = function() return true, false end, now = function() return ui.base + M.Sched.now end,
		plot = function() return { get = function() return nil end, onChanged = function() end } end })
	pcall(Shop.init)
	pcall(function() M.require(Server.Services.AIModelService).init() end)
	Shop.revenueMultiplier(s) -- the market applies it: Investor Relations sellable
	-- RecruitingService is not started in the UI scene; in the game its init registers the Headhunter handler, so the
	-- Extras page shows the HELPER row. A stand-in handler (never redeemed here) gives the same `available` flag.
	pcall(function() Shop.setRedeemHandler("headhunter", function() return false, "NOT_AVAILABLE" end) end)

	-- state options
	-- a save that launched before (the real cleaner marks the guide done and fills `seen`: no NEW-pill flood);
	-- tutorial=1 = the guide still runs
	e.tutorial = { v = 1, step = 0, done = false, skipped = false, tipsOff = false, seen = {}, tips = {} }
	if OPT.tutorial == "1" then
		e.tutorial.step = 1
	else
		M.require(Server.Lib.Template).cleanTutorial(d)
	end
	if OPT.released == "0" then d.stats.modelsReleased = 0 end
	if OPT.money then d.money = tonumber(OPT.money) end
	if OPT.points then e.points = tonumber(OPT.points) end
	if OPT.lab then e.labLevel = tonumber(OPT.lab) end
	if OPT.research then
		e.research = {}
		for id in string.gmatch(OPT.research, "[^,]+") do if id ~= "none" then e.research[id] = true end end
	end
	if OPT.job then
		local id, el = string.match(OPT.job, "^(%w+):?(%d*)$")
		local def = EmpireConfig.find(EmpireConfig.RESEARCH, id)
		e.researchJob = { id = id, elapsed = tonumber(el) or 0, seconds = def.seconds }
	end
	if OPT.vram then
		local gb = tonumber(OPT.vram)
		d.gpus = if gb >= 192 then { laptop = 1, datacenter = 3, accelerator = 2 } elseif gb >= 128 then { laptop = 1, datacenter = 2 } else { laptop = 1, workstation = 2 } -- 102 GB
	end
	for k, v in pairsOf(OPT.vouchers) do d.shop.vouchers[k] = tonumber(v) or 1 end
	for k, v in pairsOf(OPT.boost) do d.shop.boosts[k] = e.seconds + (tonumber(v) or 760) end
	local day = math.floor((ui.base + M.Sched.now) / 86400)
	d.shop.daily = { day = day, used = {} }
	for k, v in pairsOf(OPT.daily) do d.shop.daily.used[k] = tonumber(v) or 1 end
	-- packs=seed,..: that cash pack was already bought for the current office (SHOP_SPEC 3.12, S1)
	local ShopMath = M.require(RS.Shared.ShopMath)
	d.shop.packs = d.shop.packs or {}
	for k in pairsOf(OPT.packs) do d.shop.packs[k] = ShopMath.office(d) end
	local passes = {}
	for k in pairsOf(OPT.owned) do passes[k] = true; Shop.debugGrantPass(s, k) end
	local redeemable = {}
	for _, def in ShopConfig.VOUCHERS do redeemable[def.key] = true end
	s.live.shop = { passes = passes, available = Shop.available(), redeemable = redeemable, checked = true }
	if OPT.training then
		local p = tonumber(OPT.training) or 0.4
		local id = d.modelOrder[1]
		local m = d.models[id]
		d.models.trainee = { id = "trainee", name = "Sage", version = 3, sizeId = "s1b", focusId = "balanced", status = "training", createdAt = 0, trainedAt = 0,
			stats = m and m.stats or {}, overall = 0, trainCost = 9000, dataUsed = { total = 4e9, quality = 0.8, shares = { general = 1 } } }
		table.insert(d.modelOrder, "trainee")
		d.training = { modelId = "trainee", workTotal = 1000, workDone = 1000 * p, cost = 9000, expected = 61.2, qualityMod = 1, eventRolled = p > 0.35, epoch = math.floor(p * 10),
			loss = { 2.1, 1.7, 1.4, 1.2 }, log = { "Epoch 1/10  loss 2.100", "Epoch 2/10  loss 1.700" } }
	end
	local UseSheet = M.require(Client.UI.Shop.UseSheet)
	UseSheet.mount(ui.playerGui)
	ShopCore.mount()
	ui.push()
	M.settle(0.3)

	if OPT.studio7b == "1" or OPT.review7b == "1" then
		local State = M.require(Client.Controllers.StateController)
		State.setSelection("s7b", "balanced")
		State.setRecipe("steady")
		local LabState = M.require(Client.UI.Lab.LabState)
		LabState.lineId = "general"
		LabState.firstDefaults = true
		ui.Computer.open("lab")
		M.settle(0.4)
		local LabApp = M.require(Client.UI.Apps.LabApp)
		LabApp.openStudio("design", { step = if OPT.review7b == "1" then 6 else 2 })
		M.settle(0.6)
	end
	if OPT.app then
		ui.Computer.open(if OPT.app == "nil" then nil else OPT.app, OPT.section)
		M.settle(0.8)
	end
	if OPT.page then
		ui.Computer.routeTo("page:" .. OPT.page)
		M.settle(0.8)
	end
	if OPT.trainingview == "1" then
		local LabApp = M.require(Client.UI.Apps.LabApp)
		ui.Computer.open("lab")
		M.settle(0.3)
		LabApp.openStudio("training", {})
		M.settle(0.6)
		if OPT.reveal then
			ui.push()
			M.settle(0.3)
			M.require(Server.Services.AIModelService).finishNow(s)
			ui.push()
			M.settle(tonumber(OPT.reveal) or 1.5)
		end
	end
	ui.push()
	M.settle(0.5)
	if OPT.sheet then
		local key, target = string.match(OPT.sheet, "^(%w+):?(.*)$")
		local okSheet = ShopCore.use(key, if target ~= "" then target else nil)
		if not okSheet then P("@@ERROR sheet " .. OPT.sheet .. " could not open (the action does not work in this state)") end
	end
	if OPT.received then
		local key, target = string.match(OPT.received, "^(%w+):?(.*)$")
		ShopCore.use(key, if target ~= "" then target else nil, { received = true })
	end
	M.settle(0.5)
	GuiDump.setViewport(ui.playerGui, VW, VH, INSETS)
	local n = GuiDump.applyFeedback({ ui.playerGui }, FEEDBACK)
	M.settle(0.3)
	if OPT.focus then
		local target = nil
		for _, x in ui.playerGui:GetDescendants() do
			if x.Name == OPT.focus and x:IsA("GuiObject") and target == nil then
				local v, a = true, x
				while a and a ~= ui.playerGui do
					if (a:IsA("GuiObject") and not a.Visible) or (a:IsA("ScreenGui") and not a.Enabled) then v = false end
					a = a.Parent
				end
				if v then target = x end
			end
		end
		-- needs the layout of the previous pass (AbsolutePosition feedback): render focus shots with --passes 2
		if target then ShopCore.scrollTo(target) elseif FEEDBACK then P("@@ERROR focus " .. OPT.focus .. " not found") end
		M.settle(0.3)
	end
	-- scroll=<canvas px>: set the shown page's scroll position directly (guiprev's AbsolutePosition feedback is not exact
	-- under the phone's nested UIScales, so focus= can overshoot on long Shop pages; the game itself uses real positions)
	if OPT.scroll then
		for _, x in ui.playerGui:GetDescendants() do
			if x:IsA("ScrollingFrame") and x.Name == "PageScroll" then
				local v, a = true, x
				while a and a ~= ui.playerGui do
					if (a:IsA("GuiObject") and not a.Visible) or (a:IsA("ScreenGui") and not a.Enabled) then v = false end
					a = a.Parent
				end
				if v then x.CanvasPosition = Vector2.new(0, tonumber(OPT.scroll) or 0) end
			end
		end
		M.settle(0.3)
	end
	local RunService = game:GetService("RunService")
	for _ = 1, tonumber(OPT.frames or 30) do
		M.fire(RunService.RenderStepped, 1 / 60)
		M.fire(RunService.Heartbeat, 1 / 60)
	end
	GuiDump.dump({ ui.playerGui }, { scene = "shop", state = STATE, viewport = { VW, VH }, insets = INSETS, feedbackChanged = n })
end

setfenv(body, M.envFor(nil))
local ok, res, status = M.runMain(body, { timeout = 600 })
if not ok then print("@@ERROR body crashed (" .. tostring(status) .. "): " .. tostring(res)) end
if M.stats.errors > 0 then print("@@ERROR background thread errors: " .. M.stats.errors) end
