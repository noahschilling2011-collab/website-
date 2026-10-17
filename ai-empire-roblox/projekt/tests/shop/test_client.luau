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
	local function buttonOf(card) return card and card:FindFirstChildWhichIsA("TextButton") end
	local function click(button) if button then M.fire(button.Activated) end end

	------------------------------------------------------------------ registration
	local shopContainer = find(overlay, function(x) return x:IsA("Frame") and x.Name == "shop" end)
	check("Shop app registered in the computer", shopContainer ~= nil)
	local navTitle = find(overlay, function(x) return x:IsA("TextLabel") and x.Text == "Shop" and x.Parent and x.Parent:IsA("TextButton") end)
	check("Shop button in the sidebar", navTitle ~= nil)
	local navStatus = navTitle and find(navTitle.Parent, function(x) return x:IsA("TextLabel") and x ~= navTitle and x.Position.Y.Offset == 32 end)
	check("sidebar status: Coming soon with every id at 0", navStatus and navStatus.Text == "Coming soon", navStatus and navStatus.Text)

	------------------------------------------------------------------ every id 0
	Computer.open("shop")
	M.settle(0.5)
	check("computer opens the shop", Computer.isOpen() and shopContainer.Visible == true)
	local soon = named(shopContainer, "ComingSoon")
	check("'Shop coming soon' shown", soon and soon.Visible == true and find(soon, function(x) return x:IsA("TextLabel") and x.Text == "Shop coming soon" end) ~= nil)
	check("no Roblox price lookups with every id at 0", clientMarket.infoCalls == 0)
	local anyCard = find(shopContainer, function(x) return (string.match(x.Name, "^Product_") or string.match(x.Name, "^Pass_")) and x.Visible end)
	check("no item card visible", anyCard == nil)
	check("no empty-state card", named(shopContainer, "NothingNow").Visible == false)

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
	Computer.open("shop")
	M.settle(1)
	check("prices fetched once per listed item", clientMarket.infoCalls == 8, clientMarket.infoCalls)
	check("coming soon gone once something is listed", soon.Visible == false)
	local seed = named(shopContainer, "Product_seed")
	check("seed card visible with the Roblox price", seed and seed.Visible and buttonOf(seed).Text == "Buy · R$ 49", seed and buttonOf(seed).Text)
	local seedInfo = seed and find(seed, function(x) return x:IsA("TextLabel") and string.find(x.Text, "company cash at your current office", 1, true) end)
	check("seed card shows the stage-2 amount", seedInfo and string.find(seedInfo.Text, "+$25K", 1, true) ~= nil, seedInfo and seedInfo.Text) -- econ: 0.25 x Startup Campus $100,000 (CORE_SPEC 2.1)
	check("failed price lookup: card hidden", named(shopContainer, "Product_seriesA").Visible == false)
	check("no price from Roblox: card hidden", named(shopContainer, "Pass_investor").Visible == false)
	check("id 0 item hidden", named(shopContainer, "Product_seriesB").Visible == false and named(shopContainer, "Pass_limo").Visible == false)
	check("headhunter hidden until redeemable on the server", named(shopContainer, "Product_headhunter").Visible == false)
	check("party + tip + vip + founder suite visible", named(shopContainer, "Product_party").Visible and named(shopContainer, "Product_tip").Visible and named(shopContainer, "Pass_vip").Visible and named(shopContainer, "Pass_founderSuite").Visible)
	check("section headers follow their cards", find(shopContainer, function(x) return x:IsA("TextLabel") and x.Text == "Company cash" and x.Visible end) ~= nil
		and find(shopContainer, function(x) return x:IsA("TextLabel") and x.Text == "Your vouchers" and x.Visible end) == nil)
	-- retry of a failed lookup only after PRICE_RETRY_SECONDS
	Computer.close(); M.settle(0.3); Computer.open("shop"); M.settle(0.5)
	check("failed lookup not retried at once", clientMarket.infoCalls == 8)

	------------------------------------------------------------------ buying opens Roblox, grants nothing
	local money0 = session.data.money
	click(buttonOf(seed))
	check("Buy -> PromptProductPurchase with the product id", #clientMarket.prompts == 1 and clientMarket.prompts[1].kind == "product" and clientMarket.prompts[1].id == 1001 and clientMarket.prompts[1].player == localPlayer)
	click(buttonOf(named(shopContainer, "Pass_vip")))
	check("Buy pass -> PromptGamePassPurchase with the pass id", #clientMarket.prompts == 2 and clientMarket.prompts[2].kind == "pass" and clientMarket.prompts[2].id == 2001)
	local before = #calls
	M.fire(clientMarket.PromptProductPurchaseFinished, OWNER, 1001, true)
	M.settle(0.3)
	check("PromptProductPurchaseFinished grants nothing", session.data.money == money0 and #calls == before)
	check("PromptProductPurchaseFinished: only a hint", toastHas("Purchase received"), toasts())
	-- the real grant: Roblox calls ProcessReceipt on the server
	local decision = Shop.processReceipt({ PurchaseId = "ui-1", PlayerId = OWNER, ProductId = 1001 })
	M.settle(0.3)
	check("server grant", decision == Enum.ProductPurchaseDecision.PurchaseGranted and session.data.money == money0 + 25000) -- econ: CORE_SPEC 2.1 prices
	check("grant toast from the server's Notify", toastHas("Thank you! +$25K"), toasts())

	------------------------------------------------------------------ passes: owned
	M.fire(serverMarket.PromptGamePassPurchaseFinished, localPlayer, 2001, true)
	push()
	local vipButton = buttonOf(named(shopContainer, "Pass_vip"))
	check("owned pass says Owned", vipButton.Text == "✓ Owned" and vipButton:GetAttribute("Disabled") == true and vipButton.TextTransparency == 0)
	click(vipButton)
	check("owned pass: no second prompt", #clientMarket.prompts == 2)
	local badge = named(overlay, "VipBadge")
	check("VIP badge in the computer header", badge and badge.Visible == true)
	-- every group header must sit directly above its own first card (LayoutOrder), not stacked at the top
	do
		local function orderOf(pred) local x = find(shopContainer, pred); return if x then x.LayoutOrder else nil end
		local cashHeader = orderOf(function(x) return x:IsA("TextLabel") and x.Text == "Company cash" end)
		local seed = orderOf(function(x) return x.Name == "Product_seed" end)
		local tipHeader = orderOf(function(x) return x:IsA("TextLabel") and x.Text == "Support the developer" end)
		local firstTip = nil
		for _, x in shopContainer:GetDescendants() do
			if x.Name:match("^Product_tip") and (firstTip == nil or x.LayoutOrder < firstTip) then firstTip = x.LayoutOrder end
		end
		check("cash header directly above the cash cards", cashHeader ~= nil and seed ~= nil and seed == cashHeader + 1, tostring(cashHeader) .. "/" .. tostring(seed))
		check("support header above the tip cards", tipHeader ~= nil and firstTip ~= nil and tipHeader < firstTip and (seed or 0) < tipHeader)
	end

	check("pass toast", toastHas("VIP Founder is now active"), toasts())
	M.fire(clientMarket.PromptGamePassPurchaseFinished, localPlayer, 2003, true)
	M.settle(1.5)
	local rechecked = false
	for _, c in calls do if c.name == "ShopAction" and c.payload.action == "status" and c.payload.recheck == true then rechecked = true end end
	check("client pass purchase asks the server to recheck", rechecked)

	------------------------------------------------------------------ vouchers
	check("party voucher card hidden without a voucher", named(shopContainer, "Voucher_party").Visible == false)
	Shop.processReceipt({ PurchaseId = "ui-2", PlayerId = OWNER, ProductId = 1005 })
	Shop.processReceipt({ PurchaseId = "ui-3", PlayerId = OWNER, ProductId = 1005 })
	push()
	local partyCard = named(shopContainer, "Voucher_party")
	check("voucher card shows the count", partyCard.Visible and find(partyCard, function(x) return x:IsA("TextLabel") and x.Text == "Team party voucher ×2" end) ~= nil)
	check("vouchers header visible", find(shopContainer, function(x) return x:IsA("TextLabel") and x.Text == "Your vouchers" and x.Visible end) ~= nil)
	check("sidebar status counts vouchers", navStatus.Text == "2 vouchers to redeem", navStatus.Text)
	check("redeem button ready", buttonOf(partyCard).Text == "Redeem")
	-- redeem without a plot: server refuses, voucher kept, error toast
	click(buttonOf(partyCard)); M.settle(0.5)
	check("redeem refused without a plot: voucher kept", session.data.shop.vouchers.party == 2)
	local office = Instance.new("Model"); office.Name = "Office"; office:SetAttribute("OfficeTier", 2); office.Parent = G.workspace
	plots[localPlayer] = { office = office, cframe = G.CFrame.new(), model = office }
	click(buttonOf(partyCard)); M.settle(0.5)
	check("redeem through the UI: party built, one voucher used", office:FindFirstChild("TeamParty") ~= nil and session.data.shop.vouchers.party == 1)
	check("redeem toast", toastHas("Party time"), toasts())
	check("voucher card updates", find(partyCard, function(x) return x:IsA("TextLabel") and x.Text == "Team party voucher" end) ~= nil)
	-- a voucher the server can't redeem yet: shown, but disabled
	session.data.shop.vouchers.headhunter = 1
	push()
	local hh = named(shopContainer, "Voucher_headhunter")
	check("headhunter voucher shown but not redeemable yet", hh.Visible and buttonOf(hh).Text == "Available soon" and buttonOf(hh):GetAttribute("Disabled") == true)
	Shop.setRedeemHandler("headhunter", function() return true end)
	push()
	check("headhunter redeemable once the handler exists", buttonOf(hh).Text == "Redeem" and named(shopContainer, "Product_headhunter").Visible == true)

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
