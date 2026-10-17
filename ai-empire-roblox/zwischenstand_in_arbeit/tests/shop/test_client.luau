--!nocheck
-- Shop package, client side: the real Computer (Shop registered in the sidebar, status line, VIP badge)
-- and the real ShopApp, wired to the real ShopService through patched RemoteFunction:InvokeServer /
-- Notify. MarketplaceService is a test double on both sides (ShopApp._setDeps / ShopService._setDeps).
-- Checks: "Shop coming soon" with every id at 0 (and no Roblox lookups), prices only from
-- GetProductInfoAsync (failed lookup -> hidden), Buy opens the Roblox window with the right id and
-- grants nothing, owned passes say "Owned", vouchers redeem through ShopAction, nothing is granted from
-- PromptProductPurchaseFinished, the grant toast comes from the server's Notify.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_shop && tools/luau tests/shop/test_client.luau [-a .gen_dir]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_shop")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local function body()
	local G = M.G
	local Instance, Enum = G.Instance, G.Enum
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local Client = game.StarterPlayer.StarterPlayerScripts.Client
	local Template = M.require(Server.Lib.Template)
	local Remote = M.require(Server.Lib.Remote)
	local ShopConfig = M.require(RS.Shared.Config.ShopConfig)
	local SessionService = M.require(Server.Services.SessionService)
	local Shop = M.require(Server.Services.ShopService)
	local OWNER = 4242

	-- fake local player
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
	local fired = {}
	Remote.fire = function(player, name, kind, payload)
		table.insert(fired, { name = name, kind = kind, payload = payload })
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
	local calls = {}
	local function patch(cls, name, fn) M.IMPL[cls].methods[name] = fn; M.classInfo(cls).methods[name] = fn end
	patch("RemoteFunction", "InvokeServer", function(self, payload)
		table.insert(calls, { name = self.Name, payload = payload })
		if self.Name == "RequestState" then return { ok = true, state = snapshot() } end
		local handler = binds[self.Name]
		if not handler then return { ok = false, err = "BAD_INPUT" } end
		local result = handler(session, payload or {})
		G.task.defer(push) -- the next state update after a remote call
		return result
	end)
	loadedCb(session)

	-- client: market double + the real UI
	local clientMarket = { prompts = {}, infoCalls = 0, failIds = {}, prices = {},
		PromptProductPurchaseFinished = M.newSignal("PromptProductPurchaseFinished"), PromptGamePassPurchaseFinished = M.newSignal("PromptGamePassPurchaseFinished") }
	function clientMarket:GetProductInfoAsync(id, infoType)
		self.infoCalls += 1
		self.lastType = infoType
		if self.failIds[id] then error("HTTP 500 (test)") end
		return { PriceInRobux = self.prices[id], Name = "Item " .. id }
	end
	function clientMarket:PromptProductPurchase(player, id) table.insert(self.prompts, { kind = "product", id = id, player = player }) end
	function clientMarket:PromptGamePassPurchase(player, id) table.insert(self.prompts, { kind = "pass", id = id, player = player }) end
	local ShopApp = M.require(Client.UI.Apps.ShopApp)
	ShopApp._setDeps({ market = clientMarket, player = function() return localPlayer end })
	local UIRoot = M.require(Client.UI.UIRoot)
	local Toast = M.require(Client.UI.Toast)
	local State = M.require(Client.Controllers.StateController)
	local Computer = M.require(Client.UI.Screens.Computer)
	local hud, dim, overlay, intro, top = UIRoot.init()
	Toast.mount(top)
	Computer.mount(overlay, dim)
	State.init()
	M.settle(1)
	check("state received", State.snapshot ~= nil)

	local function find(root, pred) for _, x in root:GetDescendants() do if pred(x) then return x end end return nil end
	local function named(root, name) return find(root, function(x) return x.Name == name end) end
	local function visibleChain(x)
		while x and x ~= overlay do
			if x:IsA("GuiObject") and not x.Visible then return false end
			x = x.Parent
		end
		return true
	end
	-- every toast text currently in the toast layer (an old toast may still be fading out)
	local function toasts()
		local out = {}
		for _, x in top:GetDescendants() do if x:IsA("TextLabel") and x.Text ~= "" then table.insert(out, x.Text) end end
		return table.concat(out, " | ")
	end
	local function toastHas(text) return string.find(toasts(), text, 1, true) ~= nil end
	-- shop package (SHOP_SPEC 5.1): a row's buy control is its price chip "Price"; a YOUR ITEMS segment's is "Go"
	local function buttonOf(card) return card and (named(card, "Price") or named(card, "Go") or card:FindFirstChildWhichIsA("TextButton")) end
	local function click(button) if button then M.fire(button.Activated) end end
	local function textIn(root, pred) return find(root, function(x) return x:IsA("TextLabel") and pred(x.Text) end) end

	------------------------------------------------------------------ registration
	-- shop package: the Shop is 5 native Menu pages (Page_shop_home ... Page_shop_extras), Home first
	local shopContainer = find(overlay, function(x) return x:IsA("Frame") and x.Name == "Page_shop_home" end)
	check("Shop app registered in the computer", shopContainer ~= nil)
	local menuFrame = find(overlay, function(x) return x.Name == "Content" end)
	local navTitle = find(overlay, function(x) return x:IsA("TextLabel") and x.Text == "Shop" and x.Parent and x.Parent:IsA("TextButton") end)
	check("Shop button in the sidebar", navTitle ~= nil)
	-- menu package (ONBOARDING_SPEC B): the sidebar became the Menu rail (icon + label, no status line); the shop's
	-- status text is still ShopApp.status (the shop package decides where it shows)
	check("Shop entry in the Menu rail", navTitle ~= nil and navTitle.Parent.Name == "Rail_shop", navTitle and navTitle.Parent.Name)
	local function shopStatus() local text = ShopApp.status(State.snapshot); return text end
	check("shop status: Coming soon with every id at 0", shopStatus() == "Coming soon", shopStatus())

	------------------------------------------------------------------ every id 0
	Computer.open("shop")
	M.settle(0.5)
	check("computer opens the shop", Computer.isOpen() and shopContainer.Visible == true and Computer.current() == "shop.home")
	local soon = named(shopContainer, "ComingSoon")
	check("'Shop coming soon' shown", soon and soon.Visible == true and find(soon, function(x) return x:IsA("TextLabel") and x.Text == "Shop coming soon" end) ~= nil)
	check("no Roblox price lookups with every id at 0", clientMarket.infoCalls == 0)
	local function anyCardVisible()
		return find(menuFrame, function(x) return (string.match(x.Name, "^Product_") or string.match(x.Name, "^Pass_")) and visibleChain(x) end)
	end
	check("no item card visible", anyCardVisible() == nil)
	check("no empty-state card", named(shopContainer, "NothingNow").Visible == false)
	check("live with every id 0: only the Home tab", ShopApp.tabVisible("home") and not ShopApp.tabVisible("speedups") and not ShopApp.tabVisible("extras"))

	------------------------------------------------------------------ ids set
	local IDS = { seed = 1001, seriesA = 1002, headhunter = 1004, party = 1005, tip = 1006 }
	local PASS = { vip = 2001, investor = 2004, founderSuite = 2003 }
	for k, id in IDS do ShopConfig.product(k).id = id end
	for k, id in PASS do ShopConfig.pass(k).id = id end
	clientMarket.prices = { [1001] = 49, [1002] = 129, [1004] = 39, [1005] = 25, [1006] = 25, [2001] = 149, [2003] = 199 } -- 2004: no price
	clientMarket.failIds[1002] = true
	Shop.revenueMultiplier(session) -- the market applies the multiplier -> investor sellable
	push()
	Computer.close(); M.settle(0.3)
	Computer.open("shop", "extras")
	M.settle(1)
	local extras = find(overlay, function(x) return x:IsA("Frame") and x.Name == "Page_shop_extras" end)
	check("prices fetched once per listed item", clientMarket.infoCalls == 8, clientMarket.infoCalls)
	check("coming soon gone once something is listed", soon.Visible == false)
	local seed = named(extras, "Product_seed")
	check("seed card visible with the Roblox price", seed and seed.Visible and buttonOf(seed).Text == "R$ 49", seed and buttonOf(seed).Text)
	local seedInfo = seed and textIn(seed, function(t) return string.find(t, "company cash now", 1, true) ~= nil end)
	-- shop package (owner decision S1): 10 % of the next office (Startup Campus $100,000), one per office
	check("seed card shows the stage-2 amount", seedInfo and string.find(seedInfo.Text, "+$10,000", 1, true) ~= nil and string.find(seedInfo.Text, "10 % of the Startup Campus price", 1, true) ~= nil, seedInfo and seedInfo.Text)
	check("failed price lookup: card hidden", named(extras, "Product_seriesA").Visible == false)
	check("no price from Roblox: card hidden", named(extras, "Pass_investor").Visible == false)
	check("id 0 item hidden", named(extras, "Product_seriesB").Visible == false and named(extras, "Pass_limo").Visible == false)
	check("headhunter hidden until redeemable on the server", named(extras, "Product_headhunter").Visible == false)
	local style = find(overlay, function(x) return x:IsA("Frame") and x.Name == "Page_shop_style" end)
	check("party + tip + vip + founder suite visible", named(style, "Product_party").Visible and named(extras, "Product_tip").Visible and named(style, "Pass_vip").Visible and named(style, "Pass_founderSuite").Visible)
	check("section headers follow their cards", textIn(extras, function(t) return t == "COMPANY CASH" end) ~= nil and visibleChain(textIn(extras, function(t) return t == "COMPANY CASH" end))
		and named(shopContainer, "YourItems").Visible == false)
	check("empty tabs hidden (Speed-ups / Boosts have no listed item), Extras / Style shown", not ShopApp.tabVisible("speedups") and not ShopApp.tabVisible("boosts") and ShopApp.tabVisible("extras") and ShopApp.tabVisible("style"))
	-- retry of a failed lookup only after PRICE_RETRY_SECONDS
	Computer.close(); M.settle(0.3); Computer.open("shop", "extras"); M.settle(0.5)
	check("failed lookup not retried at once", clientMarket.infoCalls == 8)

	------------------------------------------------------------------ buying opens Roblox, grants nothing
	local money0 = session.data.money
	click(buttonOf(seed))
	check("Buy -> PromptProductPurchase with the product id", #clientMarket.prompts == 1 and clientMarket.prompts[1].kind == "product" and clientMarket.prompts[1].id == 1001 and clientMarket.prompts[1].player == localPlayer)
	click(buttonOf(named(style, "Pass_vip")))
	check("Buy pass -> PromptGamePassPurchase with the pass id", #clientMarket.prompts == 2 and clientMarket.prompts[2].kind == "pass" and clientMarket.prompts[2].id == 2001)
	local before = #calls
	M.fire(clientMarket.PromptProductPurchaseFinished, OWNER, 1001, true)
	M.settle(0.3)
	check("PromptProductPurchaseFinished grants nothing", session.data.money == money0 and #calls == before)
	check("PromptProductPurchaseFinished: only a hint", toastHas("Purchase received"), toasts())
	-- the real grant: Roblox calls ProcessReceipt on the server
	local decision = Shop.processReceipt({ PurchaseId = "ui-1", PlayerId = OWNER, ProductId = 1001 })
	M.settle(0.3)
	check("server grant", decision == Enum.ProductPurchaseDecision.PurchaseGranted and session.data.money == money0 + 10000) -- S1: 0.10 x $100,000
	check("grant toast from the server's Notify", toastHas("Thank you! +$10K"), toasts())
	push()
	check("S1: one Seed round per office -> its row says so and has no buy chip", textIn(seed, function(t) return t == "Bought for this office ✓" end) ~= nil and buttonOf(seed).Visible == false)

	------------------------------------------------------------------ passes: owned
	M.fire(serverMarket.PromptGamePassPurchaseFinished, localPlayer, 2001, true)
	push()
	local vipButton = buttonOf(named(style, "Pass_vip"))
	check("owned pass says Owned", vipButton.Text == "✓ Owned" and vipButton:GetAttribute("Disabled") == true and vipButton.TextTransparency == 0)
	click(vipButton)
	check("owned pass: no second prompt", #clientMarket.prompts == 2)
	local badge = named(overlay, "VipBadge")
	check("VIP badge in the computer header", badge and badge.Visible == true)
	-- every group header must sit directly above its own first card (LayoutOrder), not stacked at the top
	do
		local function orderOf(pred) local x = find(extras, pred); return if x then x.LayoutOrder else nil end
		local cashHeader = orderOf(function(x) return x.Name == "Section" and textIn(x, function(t) return t == "COMPANY CASH" end) ~= nil end)
		local seedOrder = orderOf(function(x) return x.Name == "Product_seed" end)
		local tipHeader = orderOf(function(x) return x.Name == "Section" and textIn(x, function(t) return t == "SUPPORT THE DEVELOPER" end) ~= nil end)
		local firstTip = nil
		for _, x in extras:GetDescendants() do
			if x.Name:match("^Product_tip") and (firstTip == nil or x.LayoutOrder < firstTip) then firstTip = x.LayoutOrder end
		end
		check("cash header directly above the cash cards", cashHeader ~= nil and seedOrder ~= nil and seedOrder == cashHeader + 1, tostring(cashHeader) .. "/" .. tostring(seedOrder))
		check("support header above the tip cards", tipHeader ~= nil and firstTip ~= nil and tipHeader < firstTip and (seedOrder or 0) < tipHeader)
	end

	check("pass toast", toastHas("VIP Founder is yours."), toasts())
	M.fire(clientMarket.PromptGamePassPurchaseFinished, localPlayer, 2003, true)
	M.settle(1.5)
	local rechecked = false
	for _, c in calls do if c.name == "ShopAction" and c.payload.action == "status" and c.payload.recheck == true then rechecked = true end end
	check("client pass purchase asks the server to recheck", rechecked)

	------------------------------------------------------------------ vouchers (YOUR ITEMS on Shop → Home)
	Computer.open("shop", "home"); M.settle(0.5)
	local function segment(key) return named(shopContainer, "Voucher_" .. key) end
	check("party voucher card hidden without a voucher", segment("party") == nil or not visibleChain(segment("party")))
	Shop.processReceipt({ PurchaseId = "ui-2", PlayerId = OWNER, ProductId = 1005 })
	Shop.processReceipt({ PurchaseId = "ui-3", PlayerId = OWNER, ProductId = 1005 })
	push()
	local partyCard = segment("party")
	check("voucher card shows the count", partyCard and partyCard.Visible and textIn(partyCard, function(t) return t == "Team party ×2" end) ~= nil)
	check("vouchers header visible", named(shopContainer, "YourItems").Visible and textIn(shopContainer, function(t) return t == "YOUR ITEMS" end) ~= nil)
	check("shop status counts vouchers", shopStatus() == "2 items to use", shopStatus())
	check("redeem button ready", buttonOf(partyCard).Text == "REDEEM")
	-- redeem without a plot: server refuses, voucher kept, error toast
	click(buttonOf(partyCard)); M.settle(0.5)
	check("redeem refused without a plot: voucher kept", session.data.shop.vouchers.party == 2)
	local office = Instance.new("Model"); office.Name = "Office"; office:SetAttribute("OfficeTier", 2); office.Parent = G.workspace
	plots[localPlayer] = { office = office, cframe = G.CFrame.new(), model = office }
	click(buttonOf(segment("party"))); M.settle(0.5)
	check("redeem through the UI: party built, one voucher used", office:FindFirstChild("TeamParty") ~= nil and session.data.shop.vouchers.party == 1)
	check("redeem toast", toastHas("Party time"), toasts())
	check("voucher card updates", textIn(segment("party"), function(t) return t == "Team party ×1" end) ~= nil)
	-- a voucher the server can't redeem yet: shown, but disabled
	session.data.shop.vouchers.headhunter = 1
	push()
	local hh = segment("headhunter")
	check("headhunter voucher shown but not redeemable yet", hh and hh.Visible and buttonOf(hh).Text == "LATER" and buttonOf(hh):GetAttribute("Disabled") == true)
	Shop.setRedeemHandler("headhunter", function() return true end)
	push()
	check("headhunter redeemable once the handler exists", buttonOf(segment("headhunter")).Text == "REDEEM" and named(extras, "Product_headhunter").Visible == true)

	------------------------------------------------------------------ tips
	Shop.processReceipt({ PurchaseId = "ui-4", PlayerId = OWNER, ProductId = 1006 })
	push()
	local thanks = named(shopContainer, "Thanks")
	check("thank-you line for tips", thanks.Visible and thanks.Text == "Thank you for your supporter tip!")

	------------------------------------------------------------------ everything fails: empty state
	for _, def in ShopConfig.PRODUCTS do def.id = 0 end
	ShopConfig.product("seriesA").id = 1002
	for _, def in ShopConfig.PASSES do def.id = 0 end
	session.data.shop.vouchers = {}
	push()
	check("listed but no price: 'Nothing to buy right now'", named(shopContainer, "NothingNow").Visible == true and soon.Visible == false)
end

setfenv(body, M.envFor(nil))
local ok, res, status = M.runMain(body, { timeout = 600 })
if not ok then failc += 1; print("FAIL  body crashed (" .. tostring(status) .. "): " .. tostring(res)) end
if M.stats.errors > 0 then failc += 1; print("FAIL  background thread errors: " .. M.stats.errors) end
print(string.format("shop client tests: %d passed, %d failed", pass, failc))
