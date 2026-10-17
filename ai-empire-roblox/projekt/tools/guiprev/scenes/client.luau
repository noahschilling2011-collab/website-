--!nocheck
-- guiprev scene: the real client UI (UIRoot layers, HUD, Computer with any app, Toasts) wired to the
-- real ShopService exactly like tests/shop/test_client.luau (MarketplaceService test doubles on both sides,
-- RemoteFunction:InvokeServer patched to call the server handlers). Product/pass ids and Robux prices are
-- injected ONLY into this mock run (ShopConfig tables in memory); work/src is never touched.
--
-- args (passed by guiprev.py): <genDir> <state> <viewportW> <viewportH> <insets t,r,b,l> <feedbackModule|-> [key=value ...]
--   extra key=value (after the guiprev options): app=<computer app id> (default shop; empire, lab, data, compute,
--   market, studio, arena, campus, shop) or app=none (computer closed: HUD view)
-- states:
--   soon      shop as shipped (every id 0) -> "Shop coming soon"
--   catalog   test ids + suggested prices; the server lists what it really lists (headhunter has no redeem
--             handler, investor needs MarketService to apply the multiplier -> both hidden, like in the game)
--   owned     catalog + VIP Founder owned + one Team party voucher ready to redeem (toasts settled away)
--   toast     like owned, captured right after the VIP grant (grant toast visible)
--   wired     catalog + headhunter redeem handler + investor multiplier wired (every card the app can show)
--   decor     only the shop's world GUIs: VIP name tag (BillboardGui), party banner + Founder Suite plaque
--             (SurfaceGuis), each emitted as its own root
local M = require("../../../harness/mock")
local GuiDump = require("../guidump")
local args = { ... }
local GEN = args[1] or "../../../harness/.gen_guiprev" -- require path relative to this file
local STATE = args[2] or "soon"
local VW, VH = tonumber(args[3]) or 1280, tonumber(args[4]) or 720
local insetList = string.split(args[5] or "58,0,0,0", ",")
local INSETS = { top = tonumber(insetList[1]) or 0, right = tonumber(insetList[2]) or 0, bottom = tonumber(insetList[3]) or 0, left = tonumber(insetList[4]) or 0 }
local FEEDBACK = if args[6] and args[6] ~= "-" then require(args[6]) else nil
local OPT = {}
for i = 7, #args do
	local k, v = string.match(args[i], "^([%w_]+)=(.*)$")
	if k then OPT[k] = v end
end
local APP = OPT.app or "shop"

M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
GuiDump.init(M)

-- os.clock in virtual time, so Toast expiry / price retry timers follow M.settle like task.wait does
M.G.os = setmetatable({ clock = function() return M.Sched.now end }, { __index = os })

local function body()
	local G = M.G
	local Instance, Enum = G.Instance, G.Enum
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local Client = game.StarterPlayer.StarterPlayerScripts.Client
	local ShopConfig = M.require(RS.Shared.Config.ShopConfig)

	------------------------------------------------------------------ decor: world GUIs only
	if STATE == "decor" then
		local ShopDecor = M.require(Server.Services.ShopDecor)
		local holder = Instance.new("Folder")
		holder.Name = "DecorPreview"
		holder.Parent = G.workspace
		-- VIP tag on a stand-in head, with and without a company line
		local head = Instance.new("Part"); head.Name = "Head"; head.Size = G.Vector3.new(2, 1, 1); head.Parent = holder
		ShopDecor.vipTag(head, "Nimbus Labs")
		local head2 = Instance.new("Part"); head2.Name = "HeadNoCompany"; head2.Size = G.Vector3.new(2, 1, 1); head2.Parent = holder
		ShopDecor.vipTag(head2, nil)
		-- party kit + founder suite (real builders), at the origin
		local office = Instance.new("Model"); office.Name = "Office"; office.Parent = holder
		ShopDecor.party(office, G.CFrame.new(), "Nimbus Labs")
		pcall(function() ShopDecor.founderSuite(office, G.CFrame.new(), 2) end)
		M.settle(0.5)
		GuiDump.dump({ holder }, { scene = "client", state = STATE })
		return
	end

	local Template = M.require(Server.Lib.Template)
	local Remote = M.require(Server.Lib.Remote)
	local SessionService = M.require(Server.Services.SessionService)
	local Shop = M.require(Server.Services.ShopService)
	local OWNER = 4242

	-- fake local player (as in tests/shop/test_client.luau)
	local playerGui = Instance.new("Folder"); playerGui.Name = "PlayerGui"
	local localPlayer = { UserId = OWNER, Name = "Founder", DisplayName = "Founder", Character = nil, Parent = game.Players, CharacterAdded = M.newSignal("CharacterAdded"),
		WaitForChild = function(_, name) if name == "PlayerGui" then return playerGui end end, FindFirstChildOfClass = function() return nil end, Kick = function() end }
	M.IMPL.Players.get.LocalPlayer = function() return localPlayer end; M.classInfo("Players").get.LocalPlayer = function() return localPlayer end

	-- server: real ShopService with doubles
	local serverMarket = { PromptGamePassPurchaseFinished = M.newSignal("PromptGamePassPurchaseFinished"), owned = {} }
	function serverMarket:UserOwnsGamePassAsync(userId, id) return self.owned[id] == true end
	local playersDouble = { PlayerAdded = M.newSignal("PlayerAdded") }
	function playersDouble:GetPlayerByUserId(id) return if id == OWNER then localPlayer else nil end
	function playersDouble:GetPlayers() return {} end
	local plots = {}
	local Plot = { get = function(p) return plots[p] end, onChanged = function() end }
	Shop._setDeps({ market = serverMarket, players = playersDouble, save = function() return true, false end, plot = function() return Plot end })
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
	Shop.init()

	local d = Template.new()
	d.company = { name = "Nimbus Labs", logo = "N", color = "cyan", spec = "general", reputation = 10, foundedAt = 0 }
	d.empire.office = 2
	local session = { userId = OWNER, player = localPlayer, data = d, live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} },
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
	loadedCb(session)

	-- test ids + suggested Robux prices (ShopConfig comments) -- mock only
	local IDS = { seed = 1001, seriesA = 1002, seriesB = 1003, headhunter = 1004, party = 1005, tip = 1006, bigTip = 1007 }
	local PASS = { vip = 2001, limo = 2002, founderSuite = 2003, investor = 2004 }
	local PRICES = { [1001] = 49, [1002] = 129, [1003] = 299, [1004] = 39, [1005] = 25, [1006] = 25, [1007] = 100,
		[2001] = 149, [2002] = 199, [2003] = 199, [2004] = 349 }

	-- client: market double + the real UI
	local clientMarket = { prices = {}, PromptProductPurchaseFinished = M.newSignal("PromptProductPurchaseFinished"), PromptGamePassPurchaseFinished = M.newSignal("PromptGamePassPurchaseFinished") }
	function clientMarket:GetProductInfoAsync(id, infoType)
		local p = self.prices[id]
		if p == nil then error("HTTP 400 (no such item in the test double)") end
		return { PriceInRobux = p, Name = "Item " .. id }
	end
	function clientMarket:PromptProductPurchase() end
	function clientMarket:PromptGamePassPurchase() end
	local ShopApp = M.require(Client.UI.Apps.ShopApp)
	ShopApp._setDeps({ market = clientMarket, player = function() return localPlayer end })
	local UIRoot = M.require(Client.UI.UIRoot)
	local Toast = M.require(Client.UI.Toast)
	local Theme = M.require(Client.UI.Theme)
	local State = M.require(Client.Controllers.StateController)
	local Computer = M.require(Client.UI.Screens.Computer)
	local CompanyConfig = M.require(RS.Shared.Config.CompanyConfig)
	local hud, dim, overlay, intro, top = UIRoot.init()
	GuiDump.setViewport(playerGui, VW, VH, INSETS)
	Toast.mount(top)
	local okHud, HUD = pcall(M.require, Client.UI.Screens.HUD)
	if okHud then
		local ok, err = pcall(HUD.mount, hud, false, function() end)
		if not ok then G.warn("[guiprev] HUD.mount failed: " .. tostring(err)) end
	end
	Computer.mount(overlay, dim)
	-- Main.client: company colour = accent colour of the whole UI
	State.onChange(function(snap)
		local company = snap.data.company
		if company then
			local def = CompanyConfig.getColor(company.color)
			if def then Theme.setAccent(Theme.rgb(def.rgb)) end
		end
	end)
	State.init()
	M.settle(1)
	if okHud then pcall(HUD.setHidden, false) end -- intro finished

	if STATE ~= "soon" then
		for k, id in IDS do ShopConfig.product(k).id = id end
		for k, id in PASS do ShopConfig.pass(k).id = id end
		clientMarket.prices = PRICES
		if STATE == "wired" then
			Shop.setRedeemHandler("headhunter", function() return true end)
			Shop.revenueMultiplier(session)
		end
		push()
	end
	if APP ~= "none" then
		Computer.open(APP)
	end
	M.settle(1)

	if STATE == "owned" or STATE == "toast" then
		-- VIP Founder bought (server pass event) + one party voucher bought (receipt) and not yet redeemed
		serverMarket.owned[PASS.vip] = true
		M.fire(serverMarket.PromptGamePassPurchaseFinished, localPlayer, PASS.vip, true)
		push()
		Shop.processReceipt({ PurchaseId = "prev-1", PlayerId = OWNER, ProductId = IDS.party })
		push()
		M.settle(if STATE == "toast" then 0.5 else 8) -- toasts expire after 3-5 s
		if STATE == "toast" then
			M.fire(serverMarket.PromptGamePassPurchaseFinished, localPlayer, PASS.vip, true) -- grant toast again, freshest
			M.settle(0.5)
		end
	end
	push()

	-- engine-side layout feedback (AbsoluteSize/AbsolutePosition from guiprev.py), then one rendered frame
	GuiDump.setViewport(playerGui, VW, VH, INSETS)
	local n = GuiDump.applyFeedback({ playerGui }, FEEDBACK)
	M.settle(0.3)
	local RunService = game:GetService("RunService")
	for _ = 1, tonumber(OPT.frames or 120) do -- frame signals (count-up labels, RenderStepped money) reach a steady state
		M.fire(RunService.RenderStepped, 1 / 60)
		M.fire(RunService.Heartbeat, 1 / 60)
	end
	M.settle(if STATE == "toast" then 0.05 else 0.3)
	GuiDump.dump({ playerGui }, { scene = "client", app = APP, state = STATE, viewport = { VW, VH }, insets = INSETS, feedbackChanged = n,
		shopListed = ShopConfig.anyListed() })
end

setfenv(body, M.envFor(nil))
local ok, res, status = M.runMain(body, { timeout = 600 })
if not ok then print("@@ERROR body crashed (" .. tostring(status) .. "): " .. tostring(res)) end
if M.stats.errors > 0 then print("@@ERROR background thread errors: " .. M.stats.errors) end
