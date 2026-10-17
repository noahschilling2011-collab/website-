--!nocheck
-- Shop package, server side: ShopService receipts (exactly-once across retries, failed saves and server
-- crashes, unknown product, player offline, session loading late, closed session, lost lock, receipt
-- trimming, save-slot ordering), cash-pack scaling per stage, id = 0 hidden, game-pass ownership
-- (Roblox check, fallback cache, retry, purchase event, VIP tag, Founder Suite decor, revenue
-- multiplier), the ShopAction remote (status, vouchers, party), Template migration of old and
-- malformed saves, DebugService reset/pass. Real modules in the mock; MarketplaceService, Players,
-- the DataStore save and PlotService are test doubles injected through ShopService._setDeps.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_shop && tools/luau tests/shop/test_shop.luau [-a .gen_dir]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_shop")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local function deepcopy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in v do out[k] = deepcopy(x) end
	return out
end
local function count(t) local n = 0; for _ in t do n += 1 end; return n end

local function body()
	local G = M.G
	local game = M.game
	local Instance, CFrame, Vector3, Enum = G.Instance, G.CFrame, G.Vector3, G.Enum
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local S = Server.Services
	local Remote = M.require(Server.Lib.Remote)
	local Template = M.require(Server.Lib.Template)
	local GameConfig = M.require(RS.Shared.Config.GameConfig)
	local EmpireConfig = M.require(RS.Shared.Config.EmpireConfig)
	local ShopConfig = M.require(RS.Shared.Config.ShopConfig)
	local SessionService = M.require(S.SessionService)
	local Shop = M.require(S.ShopService)
	local ShopDecor = M.require(S.ShopDecor)
	local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted
	local NPY = Enum.ProductPurchaseDecision.NotProcessedYet

	------------------------------------------------------------------ id = 0: hidden, never granted
	check("default catalogue: nothing listed", ShopConfig.anyListed() == false)
	local allZero = true
	for _, d in ShopConfig.PRODUCTS do allZero = allZero and d.id == 0 end
	for _, d in ShopConfig.PASSES do allZero = allZero and d.id == 0 end
	check("default catalogue: every id is 0", allZero)
	check("id 0 never resolves to a product", ShopConfig.productById(0) == nil and ShopConfig.passById(0) == nil)
	check("negative/NaN ids never resolve", ShopConfig.productById(-1) == nil and ShopConfig.productById(0 / 0) == nil and ShopConfig.productById("1001") == nil)

	------------------------------------------------------------------ cash packs per stage
	do
		local real = EmpireConfig.OFFICES
		EmpireConfig.OFFICES = { { price = 0 }, { price = 18000 }, { price = 90000 }, { price = 350000 } }
		local expect = {
			-- econ: at the last stage the base is the last office price x CASH.topFactor = 1.0 (CORE_SPEC 11.7, was 3.5)
			-- shop package (owner decision S1, 2026-10-12): shares 0.10 / 0.20 / 0.30 (were 0.25 / 0.75 / 2.0), minimum $2,000
			seed = { 2000, 9000, 35000, 35000 },
			seriesA = { 3600, 18000, 70000, 70000 },
			seriesB = { 5400, 27000, 105000, 105000 },
		}
		for key, values in expect do
			local def = ShopConfig.product(key)
			for office, v in values do
				check(`cash {key} at stage {office} = {v}`, ShopConfig.cashFor(def, office) == v, ShopConfig.cashFor(def, office))
			end
		end
		check("cash: stage out of range clamps", ShopConfig.cashFor(ShopConfig.product("seriesA"), 99) == 70000 and ShopConfig.cashFor(ShopConfig.product("seriesA"), 0) == 3600 and ShopConfig.cashFor(ShopConfig.product("seriesA"), 0 / 0) == 3600)
		-- a new first stage whose next office is free still gives the minimum
		EmpireConfig.OFFICES = { { price = 0 }, { price = 0 }, { price = 18000 } }
		check("cash: free next office -> minimum", ShopConfig.cashFor(ShopConfig.product("seed"), 1) == ShopConfig.CASH.minimum)
		EmpireConfig.OFFICES = real
		-- with the real (possibly re-staged) office list: monotone, rounded, >= minimum
		local prev = 0
		local okMono = true
		for office = 1, #real do
			local v = ShopConfig.cashFor(ShopConfig.product("seed"), office)
			okMono = okMono and v >= prev and v % ShopConfig.CASH.step == 0 and v >= ShopConfig.CASH.minimum
			prev = v
		end
		check("cash: real offices monotone, rounded, >= minimum", okMono)
	end

	------------------------------------------------------------------ doubles
	local IDS = { seed = 1001, seriesA = 1002, seriesB = 1003, headhunter = 1004, party = 1005, tip = 1006 }
	local PASS_IDS = { vip = 2001, limo = 2002, founderSuite = 2003, investor = 2004 }
	for key, id in IDS do ShopConfig.product(key).id = id end
	for key, id in PASS_IDS do ShopConfig.pass(key).id = id end
	check("listed after ids are set", ShopConfig.anyListed() and ShopConfig.productById(1001).key == "seed" and ShopConfig.passById(2004).key == "investor")
	check("bigTip with id 0 stays hidden", ShopConfig.product("bigTip").id == 0 and ShopConfig.productById(0) == nil)

	local market = { owned = {}, fail = {}, calls = 0, PromptGamePassPurchaseFinished = M.newSignal("PromptGamePassPurchaseFinished") }
	function market:UserOwnsGamePassAsync(userId, id)
		self.calls += 1
		if self.fail[id] then error("HTTP 503 (test)") end
		return self.owned[userId .. ":" .. id] == true
	end
	local byUser = {}
	local playersDouble = { PlayerAdded = M.newSignal("PlayerAdded") }
	function playersDouble:GetPlayerByUserId(id) return byUser[id] end
	function playersDouble:GetPlayers() return {} end
	local store, saveMode, saves = {}, "ok", 0
	local saveDelay = 0
	local function save(userId, data, release)
		saves += 1
		if saveDelay > 0 then G.task.wait(saveDelay) end
		if saveMode == "fail" then return false, false end
		if saveMode == "error" then error("UpdateAsync exploded (test)") end
		if saveMode == "lost" then return false, true end
		store[userId] = deepcopy(data)
		return true, false
	end
	local clock = 1000
	local plots, plotChanged = {}, nil
	local Plot = { get = function(player) return plots[player] end, onChanged = function(fn) plotChanged = fn end }
	Shop._setDeps({ market = market, players = playersDouble, save = save, now = function() clock += 1; return clock end, plot = function() return Plot end })

	local binds, fired = {}, {}
	local origBind = Remote.bind
	Remote.bind = function(name, limits, handler) binds[name] = { limits = limits, handler = handler }; origBind(name, limits, handler) end
	Remote.fire = function(player, name, kind, payload) table.insert(fired, { player = player, name = name, kind = kind, payload = payload }) end
	local loadedCb, closingCb
	local origLoaded, origClosing = SessionService.onLoaded, SessionService.onClosing
	SessionService.onLoaded = function(cb) loadedCb = cb; origLoaded(cb) end
	SessionService.onClosing = function(cb) closingCb = cb; origClosing(cb) end
	Remote.setup()
	Shop.init()
	check("init binds ShopAction", binds.ShopAction ~= nil and binds.ShopAction.limits.burst >= 1 and binds.ShopAction.limits.perSecond > 0)
	check("init sets ProcessReceipt", market.ProcessReceipt == Shop.processReceipt)
	check("init registers onLoaded/onClosing/plot hook", loadedCb ~= nil and closingCb ~= nil and plotChanged ~= nil)
	local initTwice = pcall(Shop.init)
	check("init twice refuses (one receipt handler)", initTwice == false)

	local function newPlayer(userId)
		local p = { UserId = userId, Name = "P" .. userId, DisplayName = "Player" .. userId, Parent = game.Players, Character = nil, CharacterAdded = M.newSignal("CharacterAdded") }
		function p:Kick(msg) self.kicked = msg end
		byUser[userId] = p
		return p
	end
	local function newSession(player, data)
		return { player = player, userId = player.UserId, data = data or Template.new(), live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} },
			dirty = false, lastSent = 0, nextSaveAt = math.huge, saving = false, closed = false, released = false, rng = G.Random.new(1) }
	end
	local function attach(session) SessionService.all()[session.player] = session end
	local function detach(session) SessionService.all()[session.player] = nil end
	local function receipt(purchaseId, userId, productId) return { PurchaseId = purchaseId, PlayerId = userId, ProductId = productId, CurrencySpent = 49, CurrencyType = Enum.CurrencyType.Robux, PlaceIdWherePurchased = 1 } end
	local function firedOf(kind) local n = 0; for _, f in fired do if f.kind == kind then n += 1 end end; return n end

	------------------------------------------------------------------ receipts: exactly once
	local A = newPlayer(501)
	local sA = newSession(A)
	sA.data.empire.office = 2
	attach(sA)
	local money0 = sA.data.money
	local seedAt2 = ShopConfig.cashFor(ShopConfig.product("seed"), 2)
	check("grant: cash receipt granted", Shop.processReceipt(receipt("r1", 501, IDS.seed)) == GRANTED)
	check("grant: money + stage-2 seed amount", sA.data.money == money0 + seedAt2, sA.data.money - money0)
	check("grant: recorded in data.shop", sA.data.shop.receipts.r1 ~= nil and sA.data.shop.order[1] == "r1" and #sA.data.shop.order == 1)
	check("grant: persisted together with the money", store[501] and store[501].shop.receipts.r1 ~= nil and store[501].money == sA.data.money)
	check("grant: client notified once", firedOf("SHOP_GRANTED") == 1 and fired[#fired].payload.amount == seedAt2)
	check("grant: marked dirty + urgent", sA.dirty == true and sA.urgent == true)
	check("retry of a granted receipt: granted again (ack), no second grant", Shop.processReceipt(receipt("r1", 501, IDS.seed)) == GRANTED and sA.data.money == money0 + seedAt2 and #sA.data.shop.order == 1)
	check("retry: no second notification", firedOf("SHOP_GRANTED") == 1)

	-- save fails -> NotProcessedYet; the retry grants nothing new
	saveMode = "fail"
	check("save fails: NotProcessedYet", Shop.processReceipt(receipt("r2", 501, IDS.headhunter)) == NPY)
	check("save fails: voucher granted in memory once", sA.data.shop.vouchers.headhunter == 1)
	check("save fails: not persisted", store[501].shop.receipts.r2 == nil)
	saveMode = "error"
	check("save throws: NotProcessedYet", Shop.processReceipt(receipt("r2", 501, IDS.headhunter)) == NPY and sA.data.shop.vouchers.headhunter == 1)
	check("save throws: slot released", sA.saving == false)
	saveMode = "ok"
	check("retry after failed saves: granted", Shop.processReceipt(receipt("r2", 501, IDS.headhunter)) == GRANTED)
	check("retry after failed saves: exactly one voucher", sA.data.shop.vouchers.headhunter == 1 and store[501].shop.vouchers.headhunter == 1)

	-- server crash before the save: grant + record lost together; the retry on the new server grants once
	saveMode = "fail"
	local beforeCrash = store[501].money
	check("crash case: save fails", Shop.processReceipt(receipt("r3", 501, IDS.seriesA)) == NPY)
	detach(sA)
	local migrated = Template.migrate(deepcopy(store[501]))
	local sA2 = newSession(A, migrated)
	attach(sA2)
	saveMode = "ok"
	local a2 = ShopConfig.cashFor(ShopConfig.product("seriesA"), sA2.data.empire.office)
	check("crash case: new server has no record", sA2.data.shop.receipts.r3 == nil and sA2.data.money == beforeCrash)
	check("crash case: retry grants once", Shop.processReceipt(receipt("r3", 501, IDS.seriesA)) == GRANTED and sA2.data.money == beforeCrash + a2)
	check("crash case: second retry grants nothing", Shop.processReceipt(receipt("r3", 501, IDS.seriesA)) == GRANTED and sA2.data.money == beforeCrash + a2)
	-- crash AFTER the save but before Roblox got the answer: the record travels with the data
	check("ack lost: granted", Shop.processReceipt(receipt("r4", 501, IDS.tip)) == GRANTED and sA2.data.shop.tips == 1)
	detach(sA2)
	local sA3 = newSession(A, Template.migrate(deepcopy(store[501])))
	attach(sA3)
	check("ack lost: retry on the next server grants nothing", Shop.processReceipt(receipt("r4", 501, IDS.tip)) == GRANTED and sA3.data.shop.tips == 1)

	-- unknown product, offline player, bad input, closed session
	local moneyNow = sA3.data.money
	check("unknown product: NotProcessedYet", Shop.processReceipt(receipt("r5", 501, 999999)) == NPY and sA3.data.shop.receipts.r5 == nil)
	check("product with id 0: NotProcessedYet", Shop.processReceipt(receipt("r5", 501, 0)) == NPY)
	check("offline player: NotProcessedYet", Shop.processReceipt(receipt("r6", 777, IDS.seed)) == NPY)
	check("malformed receipts: NotProcessedYet", Shop.processReceipt(nil) == NPY and Shop.processReceipt({}) == NPY and Shop.processReceipt(receipt("", 501, IDS.seed)) == NPY and Shop.processReceipt(receipt(42, 501, IDS.seed)) == NPY and Shop.processReceipt(receipt(string.rep("x", 200), 501, IDS.seed)) == NPY)
	check("nothing granted by bad receipts", sA3.data.money == moneyNow)
	sA3.closed = true
	check("closed session: NotProcessedYet", Shop.processReceipt(receipt("r7", 501, IDS.seed)) == NPY and sA3.data.shop.receipts.r7 == nil)
	sA3.closed = false

	-- session not loaded yet: the receipt waits and is granted once the session appears
	local B = newPlayer(502)
	local resultB = nil
	G.task.spawn(function() resultB = Shop.processReceipt(receipt("b1", 502, IDS.seed)) end)
	check("late session: receipt is waiting", resultB == nil)
	local sB = newSession(B)
	G.task.delay(6, function() attach(sB) end)
	M.settle(8)
	check("late session: granted after the session loaded", resultB == GRANTED and sB.data.shop.receipts.b1 ~= nil and sB.data.money == GameConfig.START_MONEY + ShopConfig.cashFor(ShopConfig.product("seed"), 1))
	-- session never loads: gives up after SESSION_WAIT_SECONDS
	local C = newPlayer(503)
	local resultC = nil
	G.task.spawn(function() resultC = Shop.processReceipt(receipt("c1", 503, IDS.seed)) end)
	M.settle(ShopConfig.SESSION_WAIT_SECONDS - 5)
	check("never loads: still waiting before the timeout", resultC == nil)
	M.settle(10)
	check("never loads: NotProcessedYet after the timeout", resultC == NPY)
	-- player leaves while waiting
	local D = newPlayer(504)
	local resultD = nil
	G.task.spawn(function() resultD = Shop.processReceipt(receipt("d1", 504, IDS.seed)) end)
	D.Parent = nil
	M.settle(1)
	check("player left while waiting: NotProcessedYet", resultD == NPY)

	-- save slot: a running autosave is waited for; the receipt save comes after it
	sB.saving = true
	local savesBefore = saves
	local resultSlot = nil
	G.task.spawn(function() resultSlot = Shop.processReceipt(receipt("b2", 502, IDS.party)) end)
	M.settle(2)
	check("save slot: waits while an autosave runs", resultSlot == nil and saves == savesBefore and sB.data.shop.vouchers.party == 1)
	sB.saving = false
	M.settle(1)
	check("save slot: saves after the autosave", resultSlot == GRANTED and saves == savesBefore + 1 and store[502].shop.vouchers.party == 1)
	-- a stuck save slot: gives up (the closing save carries the grant)
	sB.saving = true
	local resultStuck = nil
	G.task.spawn(function() resultStuck = Shop.processReceipt(receipt("b3", 502, IDS.tip)) end)
	M.settle(20)
	check("stuck slot: NotProcessedYet after 15 s, grant recorded in memory", resultStuck == NPY and sB.data.shop.receipts.b3 ~= nil and sB.data.shop.tips == 1)
	sB.saving = false
	check("stuck slot: retry acks without a second tip", Shop.processReceipt(receipt("b3", 502, IDS.tip)) == GRANTED and sB.data.shop.tips == 1)
	-- concurrent receipts for the same id (Roblox retry while the first call still saves)
	saveDelay = 0.5
	local r1, r2 = nil, nil
	local tipsBefore = sB.data.shop.tips
	G.task.spawn(function() r1 = Shop.processReceipt(receipt("b4", 502, IDS.tip)) end)
	G.task.spawn(function() r2 = Shop.processReceipt(receipt("b4", 502, IDS.tip)) end)
	M.settle(3)
	saveDelay = 0
	check("concurrent same id: both acked, one grant", r1 == GRANTED and r2 == GRANTED and sB.data.shop.tips == tipsBefore + 1)
	-- lost lock: the session closes, the player is kicked
	saveMode = "lost"
	check("lost lock: NotProcessedYet", Shop.processReceipt(receipt("b5", 502, IDS.tip)) == NPY)
	check("lost lock: session closed + player kicked", sB.closed == true and type(B.kicked) == "string")
	saveMode = "ok"
	detach(sB)

	-- trimming: only the newest RECEIPTS_KEPT ids stay
	local E = newPlayer(505)
	local sE = newSession(E)
	attach(sE)
	local N = ShopConfig.RECEIPTS_KEPT + 7
	local okAll = true
	for i = 1, N do okAll = okAll and Shop.processReceipt(receipt("t" .. i, 505, IDS.tip)) == GRANTED end
	check("trim: all granted", okAll and sE.data.shop.tips == N)
	check("trim: order capped", #sE.data.shop.order == ShopConfig.RECEIPTS_KEPT and count(sE.data.shop.receipts) == ShopConfig.RECEIPTS_KEPT)
	check("trim: oldest dropped, newest kept, in order", sE.data.shop.receipts.t1 == nil and sE.data.shop.receipts.t7 == nil and sE.data.shop.receipts.t8 ~= nil and sE.data.shop.order[1] == "t8" and sE.data.shop.order[#sE.data.shop.order] == "t" .. N)
	check("trim: persisted capped", #store[505].shop.order == ShopConfig.RECEIPTS_KEPT)
	check("trim: newest retry still recognised", Shop.processReceipt(receipt("t" .. N, 505, IDS.tip)) == GRANTED and sE.data.shop.tips == N)
	detach(sE)

	------------------------------------------------------------------ game passes
	local F = newPlayer(601)
	local office = Instance.new("Model"); office.Name = "Office"; office:SetAttribute("OfficeTier", 2); office.Parent = G.workspace
	plots[F] = { office = office, cframe = CFrame.new(100, 0, 50), model = office }
	local head = Instance.new("Part"); head.Name = "Head"
	local character = Instance.new("Model"); character.Name = "P601"; head.Parent = character; character.Parent = G.workspace
	F.Character = character
	local sF = newSession(F)
	sF.data.company = { name = "Nimbus Labs", logo = "N", color = "cyan", spec = "general", reputation = 10, foundedAt = 0 }
	attach(sF)
	market.owned["601:" .. PASS_IDS.vip] = true
	local changes = {}
	Shop.onPassChanged(function(s, key, owned) table.insert(changes, { s = s, key = key, owned = owned }) end)
	market.calls = 0
	loadedCb(sF)
	M.settle(0.1)
	check("load: every listed pass asked once", market.calls == 4, market.calls)
	check("load: owned pass flagged", Shop.owns(sF, "vip") == true and Shop.owns(F, "vip") == true)
	check("load: not owned stays false", Shop.owns(sF, "investor") == false and Shop.owns(sF, "limo") == false)
	check("load: live.shop published", sF.live.shop and sF.live.shop.passes.vip == true and sF.live.shop.passes.investor == nil and sF.live.shop.checked == true)
	check("load: fallback cache written", sF.data.shop.passes.vip == true and sF.data.shop.passes.investor == nil)
	check("load: VIP tag on the head", head:FindFirstChild(ShopDecor.TAG_NAME) ~= nil and head[ShopDecor.TAG_NAME]:IsA("BillboardGui"))
	check("load: VIP tag shows the company", head[ShopDecor.TAG_NAME]:FindFirstChild("Company") and head[ShopDecor.TAG_NAME].Company.Text == "Nimbus Labs")
	M.settle(0.1)
	check("pass listener told", #changes >= 1 and changes[1].key == "vip" and changes[1].owned == true)
	check("unknown pass key is not owned", Shop.owns(sF, "nope") == false and Shop.owns({ data = {}, player = {} }, "vip") == false)
	-- availability: investor only after the market applies the multiplier; limo only with a limo car
	check("available: investor hidden until wired", sF.live.shop.available.investor == false)
	check("available: limo hidden without a limo car", sF.live.shop.available.limo == ShopConfig.limoCarExists())
	check("available: headhunter hidden without a redeem handler", sF.live.shop.available.headhunter == false and sF.live.shop.available.party == true and sF.live.shop.redeemable.party == true)
	check("multiplier 1 without the pass", Shop.revenueMultiplier(sF) == 1)
	check("available: investor after the first multiplier call", sF.live.shop.available.investor == true)
	-- purchase event sets the flag at once
	fired = {}
	M.fire(market.PromptGamePassPurchaseFinished, F, PASS_IDS.investor, false)
	check("purchase cancelled: nothing", Shop.owns(sF, "investor") == false and #fired == 0)
	M.fire(market.PromptGamePassPurchaseFinished, F, PASS_IDS.investor, true)
	check("purchase event: owned at once", Shop.owns(sF, "investor") == true and sF.live.shop.passes.investor == true)
	check("purchase event: notified", firedOf("SHOP_GRANTED") == 1 and fired[1].payload.kind == "pass" and fired[1].payload.key == "investor")
	check("multiplier with the pass", Shop.revenueMultiplier(sF) == ShopConfig.INVESTOR_MULTIPLIER)
	-- Roblox still says "not owned" right after the purchase (lagging answer / Studio test purchase)
	Shop.refreshPasses(sF)
	check("fresh purchase survives a lagging 'not owned' answer", Shop.owns(sF, "investor") == true and sF.data.shop.passes.investor == true)
	M.fire(market.PromptGamePassPurchaseFinished, F, 99999, true)
	check("purchase event for an unknown pass: ignored", Shop.owns(sF, "limo") == false)
	-- Founder Suite: attribute + decor on the office, removed when ownership goes away
	M.fire(market.PromptGamePassPurchaseFinished, F, PASS_IDS.founderSuite, true)
	check("founder suite: office attribute", office:GetAttribute("FounderSuite") == true)
	local decor = office:FindFirstChild(ShopDecor.SUITE_NAME)
	check("founder suite: decor built", decor ~= nil and #decor:GetChildren() > 10)
	local seats = 0
	if decor then for _, d in decor:GetDescendants() do if d:IsA("Seat") then seats += 1 end end end
	check("founder suite: two real seats", seats == 2)
	plotChanged(plots[F], sF)
	check("founder suite: plot rebuild hook keeps one decor", #(function() local t = {} for _, c in office:GetChildren() do if c.Name == ShopDecor.SUITE_NAME then table.insert(t, c) end end return t end)() == 1)
	-- a rebuilt office (new model) gets the decor from the plot hook
	local office2 = Instance.new("Model"); office2.Name = "Office"; office2:SetAttribute("OfficeTier", 3); office2.Parent = G.workspace
	plots[F].office = office2
	plotChanged(plots[F], sF)
	check("founder suite: rebuilt office decorated", office2:FindFirstChild(ShopDecor.SUITE_NAME) ~= nil and office2:GetAttribute("FounderSuite") == true)
	-- refund: Roblox now says no -> flag, cache, tag, decor go away
	market.owned["601:" .. PASS_IDS.vip] = nil
	Shop.refreshPasses(sF)
	check("refund: vip gone", Shop.owns(sF, "vip") == false and sF.data.shop.passes.vip == nil and sF.live.shop.passes.vip == nil)
	check("refund: tag removed", head:FindFirstChild(ShopDecor.TAG_NAME) == nil)
	check("bought this session: founder suite kept despite a 'not owned' answer", office2:FindFirstChild(ShopDecor.SUITE_NAME) ~= nil and office2:GetAttribute("FounderSuite") == true)
	-- owned from an earlier session (cache) while Roblox is down, then Roblox says no: decor removed
	local G2 = newPlayer(610)
	local officeG = Instance.new("Model"); officeG.Name = "Office"; officeG:SetAttribute("OfficeTier", 4); officeG.Parent = G.workspace
	plots[G2] = { office = officeG, cframe = CFrame.new(), model = officeG }
	local sG = newSession(G2)
	sG.data.shop.passes.founderSuite = true
	attach(sG)
	market.fail[PASS_IDS.founderSuite] = true
	G.task.spawn(loadedCb, sG)
	M.settle(0.2)
	check("cached founder suite while Roblox is down: decor built", officeG:FindFirstChild(ShopDecor.SUITE_NAME) ~= nil and officeG:GetAttribute("FounderSuite") == true)
	market.fail[PASS_IDS.founderSuite] = nil
	Shop.refreshPasses(sG)
	check("refund: founder suite decor + attribute removed", officeG:FindFirstChild(ShopDecor.SUITE_NAME) == nil and officeG:GetAttribute("FounderSuite") == nil and sG.data.shop.passes.founderSuite == nil)
	sG.closed = true; closingCb(sG); detach(sG)
	-- character respawn gets the tag again
	market.owned["601:" .. PASS_IDS.vip] = true
	Shop.refreshPasses(sF)
	local head2 = Instance.new("Part"); head2.Name = "Head"
	local character2 = Instance.new("Model"); character2.Name = "P601b"; head2.Parent = character2; character2.Parent = G.workspace
	F.Character = character2
	M.fire(playersDouble.PlayerAdded, F)
	M.fire(F.CharacterAdded, character2)
	M.settle(0.5)
	check("respawn: tag on the new head", head2:FindFirstChild(ShopDecor.TAG_NAME) ~= nil)
	-- API down: the fallback cache keeps a known pass, and the check is retried
	local H = newPlayer(602)
	local sH = newSession(H)
	sH.data.shop.passes.vip = true
	attach(sH)
	market.fail[PASS_IDS.vip] = true
	market.owned["602:" .. PASS_IDS.limo] = true
	G.task.spawn(loadedCb, sH)
	M.settle(0.2)
	check("API down: cached pass still active", Shop.owns(sH, "vip") == true)
	check("API down: other passes answered normally", Shop.owns(sH, "limo") == true and Shop.owns(sH, "founderSuite") == false)
	check("API down: not marked checked", sH.live.shop.checked == false)
	market.fail[PASS_IDS.vip] = nil
	market.owned["602:" .. PASS_IDS.vip] = false
	M.settle(ShopConfig.PASS_RETRY_SECONDS + 1)
	check("API back: retry corrects the flag + cache", Shop.owns(sH, "vip") == false and sH.data.shop.passes.vip == nil and sH.live.shop.checked == true)
	-- API down, nothing cached: not owned
	local I = newPlayer(603)
	local sI = newSession(I)
	attach(sI)
	market.fail[PASS_IDS.investor] = true
	G.task.spawn(loadedCb, sI)
	M.settle(0.2)
	check("API down without cache: not owned", Shop.owns(sI, "investor") == false and Shop.revenueMultiplier(sI) == 1)
	market.fail[PASS_IDS.investor] = nil
	-- passes with id 0 are never asked
	ShopConfig.pass("limo").id = 0
	market.calls = 0
	Shop.refreshPasses(sI)
	check("id 0 pass never asked", market.calls == 3)
	ShopConfig.pass("limo").id = PASS_IDS.limo
	-- closing forgets the per-session flags
	closingCb(sI)
	check("closing: flags dropped", Shop.owns(sI, "limo") == false)

	------------------------------------------------------------------ ShopAction remote
	local act = binds.ShopAction.handler
	local st = act(sF, { action = "status" })
	check("status: ok with passes/vouchers/available", st.ok == true and st.passes.vip == true and type(st.vouchers) == "table" and type(st.available) == "table")
	check("status: unknown action refused", act(sF, { action = "steal" }).ok == false and act(sF, {}).err == "BAD_INPUT")
	sF.data.shop.vouchers.headhunter = 2
	local r = act(sF, { action = "redeem", key = "headhunter" })
	check("redeem without handler: NOT_AVAILABLE, voucher kept", r.ok == false and r.err == "NOT_AVAILABLE" and sF.data.shop.vouchers.headhunter == 2)
	local hhCalls = 0
	local hhResult = { true, nil }
	Shop.setRedeemHandler("headhunter", function(s) hhCalls += 1; if hhResult == "throw" then error("recruiting broke") end; return hhResult[1], hhResult[2] end)
	check("handler registered: headhunter sellable + redeemable", sF.live.shop.available.headhunter == true and sF.live.shop.redeemable.headhunter == true)
	r = act(sF, { action = "redeem", key = "headhunter" })
	check("redeem: ok, one voucher used", r.ok == true and r.left == 1 and sF.data.shop.vouchers.headhunter == 1 and hhCalls == 1)
	hhResult = { false, "APPLICANTS_FULL" }
	r = act(sF, { action = "redeem", key = "headhunter" })
	check("redeem refused by the game: error passed on, voucher kept", r.ok == false and r.err == "APPLICANTS_FULL" and sF.data.shop.vouchers.headhunter == 1)
	hhResult = "throw"
	r = act(sF, { action = "redeem", key = "headhunter" })
	check("redeem handler error: SERVER_ERROR, voucher kept", r.ok == false and r.err == "SERVER_ERROR" and sF.data.shop.vouchers.headhunter == 1)
	hhResult = { true, nil }
	r = act(sF, { action = "redeem", key = "headhunter" })
	check("last voucher: entry removed", r.ok == true and r.left == 0 and sF.data.shop.vouchers.headhunter == nil)
	r = act(sF, { action = "redeem", key = "headhunter" })
	check("no voucher: NO_VOUCHER", r.ok == false and r.err == "NO_VOUCHER")
	check("redeem bad keys", act(sF, { action = "redeem", key = "money" }).err == "BAD_INPUT" and act(sF, { action = "redeem", key = "../x" }).err == "BAD_INPUT" and act(sF, { action = "redeem" }).err == "BAD_INPUT")
	-- party voucher: kit in front of the office, one at a time, removed after PARTY_SECONDS
	sF.data.shop.vouchers.party = 2
	r = act(sF, { action = "redeem", key = "party" })
	local kit = office2:FindFirstChild(ShopDecor.PARTY_NAME)
	check("party: kit built in the office", r.ok == true and kit ~= nil and #kit:GetDescendants() > 20)
	check("party: attribute for staff/talk", type(office2:GetAttribute("TeamPartyUntil")) == "number")
	local banner = kit and kit:FindFirstChild("PartyBanner")
	local label = banner and banner:FindFirstChildWhichIsA("SurfaceGui") and banner:FindFirstChildWhichIsA("SurfaceGui"):FindFirstChildWhichIsA("TextLabel")
	check("party: banner names the company", label and string.find(label.Text, "NIMBUS LABS", 1, true) ~= nil, label and label.Text)
	local collide = 0
	if kit then for _, d in kit:GetDescendants() do if d:IsA("BasePart") and (d.CanCollide or d.CanTouch or d.CanQuery or not d.Anchored) then collide += 1 end end end
	check("party: every part decorative + anchored", collide == 0, collide)
	r = act(sF, { action = "redeem", key = "party" })
	check("party: second party refused, voucher kept", r.ok == false and r.err == "PARTY_ACTIVE" and sF.data.shop.vouchers.party == 1)
	M.settle(ShopConfig.PARTY_SECONDS + 1)
	check("party: removed after the party", office2:FindFirstChild(ShopDecor.PARTY_NAME) == nil and office2:GetAttribute("TeamPartyUntil") == nil)
	r = act(sF, { action = "redeem", key = "party" })
	check("party: next party allowed", r.ok == true and sF.data.shop.vouchers.party == nil)
	local noPlot = newSession(newPlayer(604))
	noPlot.data.shop.vouchers.party = 1
	r = act(noPlot, { action = "redeem", key = "party" })
	check("party without a plot: NO_PLOT, voucher kept", r.ok == false and r.err == "NO_PLOT" and noPlot.data.shop.vouchers.party == 1)
	-- data.shop replaced by something broken: repaired, nothing crashes
	sF.data.shop = "broken"
	check("broken data.shop repaired on use", act(sF, { action = "status" }).ok == true and type(sF.data.shop.receipts) == "table")

	------------------------------------------------------------------ Template migration
	local old = Template.new()
	old.shop = nil
	local m1 = Template.migrate(deepcopy(old))
	check("migrate: old save without shop gets an empty shop", m1 and type(m1.shop) == "table" and next(m1.shop.receipts) == nil and #m1.shop.order == 0 and next(m1.shop.vouchers) == nil and m1.shop.tips == 0)
	check("migrate: no version bump", m1.version == GameConfig.DATA_VERSION and Template.new().version == GameConfig.DATA_VERSION)
	check("template: new save has a shop", type(Template.new().shop) == "table")
	local m2 = Template.migrate((function() local d = deepcopy(old); d.shop = "garbage"; return d end)())
	check("migrate: non-table shop replaced", type(m2.shop) == "table" and type(m2.shop.receipts) == "table")
	local bad = deepcopy(old)
	bad.shop = {
		receipts = { a = 5, b = "x", [7] = 3, [string.rep("z", 300)] = 1, c = 0 / 0 },
		order = { "a", "missing", "a", 9 },
		vouchers = { headhunter = 2.7, party = -1, legacy = 4, ["evil key!"] = 3, big = 1e9, nan = 0 / 0 },
		passes = { vip = true, limo = "yes", founderSuite = false },
		tips = -3,
		junk = { 1, 2, 3 },
	}
	local m3 = Template.migrate(bad).shop
	check("malformed: receipts keep string ids only", m3.receipts.a == 5 and m3.receipts.b == 0 and m3.receipts.c == 0 and m3.receipts[7] == nil and count(m3.receipts) == 3)
	check("malformed: order rebuilt (missing ids first, no dupes)", #m3.order == 3 and m3.order[3] == "a" and m3.order[1] == "b" and m3.order[2] == "c", table.concat(m3.order, ","))
	check("malformed: vouchers clamped, unknown keys kept", m3.vouchers.headhunter == 2 and m3.vouchers.party == nil and m3.vouchers.legacy == 4 and m3.vouchers["evil key!"] == nil and m3.vouchers.big == ShopConfig.VOUCHER_MAX and m3.vouchers.nan == nil)
	check("malformed: passes cache true only", m3.passes.vip == true and m3.passes.limo == nil and m3.passes.founderSuite == nil)
	check("malformed: tips clamped, junk dropped", m3.tips == 0 and m3.junk == nil)
	local many = deepcopy(old)
	many.shop = { receipts = {}, order = {}, vouchers = {}, passes = {}, tips = 0 }
	for i = 1, 150 do local id = "p" .. i; many.shop.receipts[id] = i; table.insert(many.shop.order, id) end
	local m4 = Template.migrate(many).shop
	check("migrate: receipts trimmed to the newest", #m4.order == ShopConfig.RECEIPTS_KEPT and m4.receipts.p50 == nil and m4.receipts.p51 ~= nil and m4.order[1] == "p51" and count(m4.receipts) == ShopConfig.RECEIPTS_KEPT)
	local good = deepcopy(store[501])
	local m5 = Template.migrate(deepcopy(good)).shop
	check("migrate: a valid shop is unchanged", #m5.order == #good.shop.order and m5.vouchers.headhunter == good.shop.vouchers.headhunter and m5.tips == good.shop.tips and m5.receipts.r1 == good.shop.receipts.r1)

	------------------------------------------------------------------ DebugService
	local Debug = M.require(S.DebugService)
	local debugBind
	Remote.bind = function(name, limits, handler) if name == "Debug" then debugBind = handler end end
	Debug.init()
	local function patchStudio(v)
		M.IMPL.RunService.methods.IsStudio = function() return v end
		M.classInfo("RunService").methods.IsStudio = function() return v end
	end
	local J = newPlayer(701)
	local sJ = newSession(J)
	attach(sJ)
	plots[J] = { office = office2, cframe = CFrame.new(), model = office2 }
	patchStudio(false)
	check("debug pass outside Studio: refused", debugBind(sJ, { cmd = "pass", key = "vip" }).err == "NOT_ALLOWED" and Shop.owns(sJ, "vip") == false)
	patchStudio(true)
	check("debug pass in Studio: flag set", debugBind(sJ, { cmd = "pass", key = "vip" }).ok == true and Shop.owns(sJ, "vip") == true)
	check("debug pass: not saved as cache", sJ.data.shop.passes.vip == nil)
	check("debug pass: bad key", debugBind(sJ, { cmd = "pass", key = "free_money" }).err == "BAD_INPUT" and debugBind(sJ, { cmd = "pass" }).err == "BAD_INPUT")
	check("debug voucher in Studio", debugBind(sJ, { cmd = "voucher", key = "party" }).ok == true and sJ.data.shop.vouchers.party == 1)
	sJ.data.shop.receipts.keep = 1; table.insert(sJ.data.shop.order, "keep")
	sJ.live.admin = true
	local shopRef = sJ.data.shop
	local Plots = M.require(S.PlotService)
	local origRefresh = Plots.refresh
	Plots.refresh = function() end
	check("debug reset ok", debugBind(sJ, { cmd = "reset" }).ok == true)
	Plots.refresh = origRefresh
	check("debug reset keeps data.shop", sJ.data.shop == shopRef and sJ.data.shop.receipts.keep == 1 and sJ.data.shop.vouchers.party == 1)
	check("debug reset keeps foreign live fields", sJ.live.admin == true and type(sJ.live.shop) == "table" and sJ.live.users == 0 and sJ.live.revenue == 0)
	check("debug reset resets the rest", sJ.data.money == GameConfig.START_MONEY)
	patchStudio(false)
end

setfenv(body, M.envFor(nil))
local ok, res, status = M.runMain(body, { timeout = 2000 })
if not ok then failc += 1; print("FAIL  body crashed (" .. tostring(status) .. "): " .. tostring(res)) end
if M.stats.errors > 0 then failc += 1; print("FAIL  background thread errors: " .. M.stats.errors) end
print(string.format("shop tests: %d passed, %d failed", pass, failc))
