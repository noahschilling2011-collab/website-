--!strict
-- Robux purchases (catalogue: ShopConfig). The ONLY script that sets MarketplaceService.ProcessReceipt.
--
-- Developer products are granted exactly once. The grant and its record live in the same
-- session-locked save record (data.shop.receipts[PurchaseId]):
--   find player -> wait for the loaded session (up to 45 s: products can be bought outside the game,
--   so receipts arrive during joins) -> if the id is not recorded: grant + record (no yield in between)
--   -> save now -> PurchaseGranted only after a successful save, NotProcessedYet otherwise.
-- A retry of an already recorded id only saves again; a server crash before the save loses grant AND
-- record together, so Roblox's retry on the next join grants it fresh. Ids answered PurchaseGranted
-- are never sent again, so only the newest ShopConfig.RECEIPTS_KEPT ids are kept.
-- Anything that could fail later (an applicant, a party) is granted as a voucher and redeemed through
-- the ShopAction remote under the normal game rules.
--
-- Game passes: ownership is asked from Roblox when the session loads (retried on failure), set at
-- once by PromptGamePassPurchaseFinished, and kept per session (module-level weak table). The saved
-- data.shop.passes is only a fallback cache while Roblox can't be asked. Clients see the flags in
-- live.shop (written on change; MarketService merges session.live instead of replacing it).
--
-- Shop package (SHOP_SPEC): redeem(session, key, target) with the generic daily caps (ShopConfig.DAILY), the timed
-- boosts Keynote Boost / Overclock (startBoost, end times in company play seconds, at most 60 min left), Rooftop
-- Fireworks, bundles (a pass that `includes` others), passes with ready = false never sold, cash packs once per office
-- (S1, enforced here: a second receipt of the same size in one office is never refused but becomes a credit,
-- data.shop.packCredit, paid at the next office by payPackCredits), the ServerGlow office attribute.
--
-- Public API for other systems:
--   ShopService.owns(player|session, passKey) -> boolean        (VehicleService: limo; honours bundles)
--   ShopService.revenueMultiplier(session) -> number             (MarketService: investor pass + Keynote Boost)
--   ShopService.trainingMultiplier(session) -> number            (Overclock; AIModelService uses ShopMath.boostRate)
--   ShopService.setRedeemHandler(voucherKey, fn(session, target?) -> (ok, errCode?))
--       (RecruitingService: headhunter, EmpireService: eureka, AIModelService: lastEpoch)
--   ShopService.onPassChanged(fn(session, passKey, owned))
--   ShopService.payPackCredits(session) -> number                (EmpireService.upgrade: saved cash-pack credits, S1)
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local ShopMath = require(ReplicatedStorage.Shared.ShopMath)
local CompanyConfig = require(ReplicatedStorage.Shared.Config.CompanyConfig)
local ServerTypes = require(script.Parent.Parent.Lib.ServerTypes)
local Guard = require(script.Parent.Parent.Lib.Guard)
local Remote = require(script.Parent.Parent.Lib.Remote)
local Template = require(script.Parent.Parent.Lib.Template)
local SaveService = require(script.Parent.SaveService)
local SessionService = require(script.Parent.SessionService)
local EconomyService = require(script.Parent.EconomyService)
local ShopDecor = require(script.Parent.ShopDecor)

type Session = ServerTypes.Session
type Redeemer = (Session, string?) -> (boolean, string?)
type PassListener = (Session, string, boolean) -> ()

local Shop = {}

local NOT_PROCESSED = Enum.ProductPurchaseDecision.NotProcessedYet
local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted
local SAVE_WAIT_SECONDS = 15 -- like SessionService.closeSession: wait for a running autosave

-- Seams for the headless tests (tests/shop): MarketplaceService does not exist outside Roblox.
type Deps = {
	market: any,
	players: any,
	save: (userId: number, data: any, release: boolean) -> (boolean, boolean),
	getSession: (player: any) -> Session?,
	now: () -> number,
	plot: () -> any, -- PlotService, required lazily (it pulls in the whole building generator)
}
local deps: Deps = {
	market = MarketplaceService,
	players = Players,
	save = SaveService.save,
	getSession = SessionService.get,
	now = os.time,
	plot = function(): any
		return require(script.Parent.PlotService) :: any
	end,
}

type PassState = { checkedAt: number, checked: boolean }
local passFlags: { [Session]: { [string]: boolean } } = setmetatable({}, { __mode = "k" }) :: any
local passStates: { [Session]: PassState } = setmetatable({}, { __mode = "k" }) :: any
-- passes bought during this session (purchase event): a later "not owned" answer from Roblox (its
-- ownership answer can lag behind a fresh purchase, e.g. Studio test purchases) never takes them away
local boughtNow: { [Session]: { [string]: boolean } } = setmetatable({}, { __mode = "k" }) :: any
local parties: { [Session]: Model } = setmetatable({}, { __mode = "k" }) :: any
local fireworksKits: { [Session]: Model } = setmetatable({}, { __mode = "k" }) :: any
local redeeming: { [Session]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local redeemers: { [string]: Redeemer } = {}
local passListeners: { PassListener } = {}
local investorWired = false -- becomes true when the market applies revenueMultiplier
local initialised = false

---------------------------------------------------------------------------------------------- data

-- data.shop with a valid shape (repairs it in place when another system replaced data)
local function shopOf(session: Session): any
	local data = session.data :: any
	local shop = data.shop
	if
		typeof(shop) ~= "table"
		or typeof(shop.receipts) ~= "table"
		or typeof(shop.order) ~= "table"
		or typeof(shop.vouchers) ~= "table"
		or typeof(shop.passes) ~= "table"
		or typeof(shop.tips) ~= "number"
		or typeof(shop.boosts) ~= "table" -- shop package: an old save gets the new fields once (SHOP_SPEC 7)
		or typeof(shop.daily) ~= "table"
		or typeof(shop.daily.used) ~= "table"
		or typeof(shop.packs) ~= "table"
		or typeof(shop.packCredit) ~= "table" -- fix round 1: cash packs bought twice in one office (S1)
	then
		shop = Template.cleanShop(shop)
		data.shop = shop
	end
	return shop
end

local function stateOf(session: Session): PassState
	local state = passStates[session]
	if not state then
		state = { checkedAt = -math.huge, checked = false }
		passStates[session] = state
	end
	return state
end

local function isSession(target: any): boolean
	return typeof(target) == "table" and target.data ~= nil and target.player ~= nil
end

-------------------------------------------------------------------------------------- publishing

-- Which listed items can be sold right now (features owned by other systems must exist first).
function Shop.available(): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, def in ShopConfig.PRODUCTS do
		out[def.key] = if def.kind == "voucher" then def.voucher ~= nil and redeemers[def.voucher] ~= nil else true
	end
	for _, def in ShopConfig.PRODUCTS do
		if def.ready == false then
			out[def.key] = false
		end
	end
	for _, def in ShopConfig.PASSES do
		if def.ready == false then
			out[def.key] = false -- its feature is not in the game yet (phase 2/3): never sold
		elseif def.key == "limo" then
			out[def.key] = ShopConfig.limoCarExists()
		elseif def.key == "investor" then
			out[def.key] = investorWired
		else
			out[def.key] = true
		end
	end
	return out
end

-- live.shop for the client: owned passes, sellable items, redeemable vouchers.
local function publish(session: Session)
	if session.closed then
		return
	end
	local flags = passFlags[session] or {}
	local passes: { [string]: boolean } = {}
	for _, def in ShopConfig.PASSES do
		if flags[def.key] == true then
			passes[def.key] = true
		end
	end
	local redeemable: { [string]: boolean } = {}
	for key in redeemers do
		redeemable[key] = true
	end
	local live = session.live :: any
	live.shop = { passes = passes, available = Shop.available(), redeemable = redeemable, checked = stateOf(session).checked }
	SessionService.markDirty(session)
end

local function publishAll()
	for _, session in SessionService.all() do
		publish(session)
	end
end

------------------------------------------------------------------------------- office + character

-- FounderSuite attribute + decor on the owner's office (after pass changes and every rebuild).
local function refreshOffice(session: Session)
	local ok, err = pcall(function(): any
		local Plot = deps.plot()
		local plot = Plot.get(session.player)
		local office: Instance? = if plot then plot.office else nil
		if not plot or not office then
			return nil
		end
		local owned = Shop.owns(session, "founderSuite")
		office:SetAttribute("FounderSuite", if owned then true else nil)
		-- Server Glow pass (SHOP_SPEC 3.6): PropFxController runs the rack light wave while this is set
		office:SetAttribute("ServerGlow", if Shop.owns(session, "serverGlow") then true else nil)
		local existing = office:FindFirstChild(ShopDecor.SUITE_NAME)
		if owned and not existing then
			local tier = office:GetAttribute("OfficeTier")
			-- ONBOARDING_SPEC C4: the fallback is a plan tier (BuildingPlan.tierForOffice), never the office index
			local Plan = require(ReplicatedStorage.Shared.Config.BuildingPlan) :: any
			ShopDecor.founderSuite(office, plot.cframe, if typeof(tier) == "number" then tier else Plan.tierForOffice(session.data.empire.office))
		elseif not owned and existing then
			existing:Destroy()
		end
		return nil
	end)
	if not ok then
		warn("[Shop] founder suite:", err)
	end
end

-- VIP tag on the current character (character spawns, pass changes)
local function refreshTag(player: Player)
	local character = player.Character
	local head = if character then character:FindFirstChild("Head") else nil
	if not head or not head:IsA("BasePart") then
		return
	end
	local session = deps.getSession(player)
	local owned = session ~= nil and Shop.owns(session, "vip")
	local existing = head:FindFirstChild(ShopDecor.TAG_NAME)
	if owned and session and not existing then
		local company = session.data.company
		ShopDecor.vipTag(head, if company then company.name else nil)
	elseif not owned and existing then
		existing:Destroy()
	end
end

local function watchCharacter(player: Player)
	local function spawned(character: Model)
		task.spawn(function()
			character:WaitForChild("Head", 10)
			if character.Parent then
				refreshTag(player)
			end
		end)
	end
	player.CharacterAdded:Connect(spawned)
	if player.Character then
		spawned(player.Character)
	end
end

------------------------------------------------------------------------------------- game passes

-- persist = true: an authoritative answer (Roblox / purchase event) -> update the fallback cache
local function setPass(session: Session, key: string, owned: boolean, persist: boolean)
	local flags = passFlags[session]
	if not flags then
		flags = {}
		passFlags[session] = flags
	end
	if persist then
		local passes = shopOf(session).passes
		if (passes[key] == true) ~= owned then
			passes[key] = if owned then true else nil
			SessionService.markDirty(session)
		end
	end
	if flags[key] == owned then
		return
	end
	flags[key] = owned
	publish(session)
	if key == "vip" then
		refreshTag(session.player)
	elseif key == "founderSuite" or key == "serverGlow" or key == "styleCollection" then
		refreshOffice(session)
	end
	for _, listener in passListeners do
		task.spawn(listener, session, key, owned)
	end
end

-- Asks Roblox for every listed pass (yields). true when every answer arrived.
function Shop.refreshPasses(session: Session): boolean
	local state = stateOf(session)
	state.checkedAt = os.clock()
	local allAnswered = true
	for _, def in ShopConfig.PASSES do
		if def.id > 0 then
			local ok, owns = pcall(function(): any
				return deps.market:UserOwnsGamePassAsync(session.userId, def.id)
			end)
			if session.closed then
				return false
			end
			if ok then
				local bought = boughtNow[session]
				if owns == true or not (bought and bought[def.key]) then
					setPass(session, def.key, owns == true, true)
				end
			else
				allAnswered = false
				warn(`[Shop] UserOwnsGamePassAsync {def.key} for {session.userId} failed: {owns}`)
				local flags = passFlags[session]
				if not flags or flags[def.key] == nil then
					setPass(session, def.key, shopOf(session).passes[def.key] == true, false) -- fallback cache
				end
			end
		end
	end
	if allAnswered and not state.checked then
		state.checked = true
		publish(session)
	end
	return allAnswered
end

local function onPassPurchaseFinished(player: Player, passId: number, purchased: boolean)
	if not purchased then
		return
	end
	local def = ShopConfig.passById(passId)
	local session = deps.getSession(player)
	if not def or not session or session.closed then
		return
	end
	local bought = boughtNow[session]
	if not bought then
		bought = {}
		boughtNow[session] = bought
	end
	bought[def.key] = true
	setPass(session, def.key, true, true)
	Remote.fire(player, "Notify", "SHOP_GRANTED", { key = def.key, kind = "pass" })
end

-- the pass's own flag, or a bundle that includes it (Style Collection: SHOP_SPEC 3.11)
function Shop.owns(target: Player | Session, key: string): boolean
	local session: Session? = if isSession(target) then target :: any else deps.getSession(target)
	if not session then
		return false
	end
	local flags = passFlags[session]
	return flags ~= nil and ShopMath.ownsPass(flags, key)
end

-- MarketService multiplies the player's own market revenue with this (after market shares are
-- computed, so it never changes anyone else's share). Its first call also makes the Investor pass
-- sellable: the pass is only offered once the game really applies it.
function Shop.revenueMultiplier(session: Session): number
	if not investorWired then
		investorWired = true
		publishAll()
	end
	local factor = if Shop.owns(session, "investor") then ShopConfig.INVESTOR_MULTIPLIER else 1
	-- Keynote Boost: +0.20 added (S6: with Investor 1.30), own market revenue only, after shares
	return factor + ShopMath.revenueBonus(session.data)
end

-- seconds of company play time left on a boost ("keynote" | "overclock")
function Shop.boostLeft(session: Session, key: string): number
	return ShopMath.boostLeft(session.data, key)
end

-- Overclock: training x1.5 (callers keep the 12 s floor: ShopMath.boostRate)
function Shop.trainingMultiplier(session: Session): number
	return ShopMath.trainingFactor(session.data)
end

-- Redeem handler of the boost vouchers (SHOP_SPEC 3.3). Another start adds 15 min; refused while more than
-- BOOST_MAX_LEFT - 15 min are left. The daily cap is checked by redeem before this runs.
function Shop.startBoost(session: Session, key: string): (boolean, string?)
	local def = ShopConfig.BOOSTS[key]
	if not def then
		return false, "BAD_INPUT"
	end
	local data = session.data
	if not data.company then
		return false, "NO_COMPANY"
	end
	if key == "keynote" and not ShopMath.liveModel(data) then
		return false, "NO_LIVE_MODEL" -- +20 % of nothing
	end
	local left = ShopMath.boostLeft(data, key)
	if left + def.seconds > ShopConfig.BOOST_MAX_LEFT then
		return false, "BOOST_FULL"
	end
	local now = tonumber(data.empire.seconds) or 0
	shopOf(session).boosts[key] = now + left + def.seconds
	SessionService.markDirty(session, true)
	return true, nil
end

function Shop.onPassChanged(listener: PassListener)
	table.insert(passListeners, listener)
end

------------------------------------------------------------------------------------------ receipts

-- Waits for a free save slot, saves (not releasing the lock) and reports whether it was written.
-- Same rules as SessionService: session.saving keeps saves in order, a lost lock closes the session.
function Shop.saveNow(session: Session): boolean
	local waited = 0
	while session.saving and waited < SAVE_WAIT_SECONDS do
		task.wait(0.2)
		waited += 0.2
	end
	if session.saving or session.closed then
		return false -- closing: the final save carries the grant; the retry then finds the record
	end
	session.saving = true
	local ok, saved, lostLock = pcall(deps.save, session.userId, session.data, false)
	session.saving = false
	if not ok then
		warn("[Shop] save failed:", saved)
		return false
	end
	if lostLock then
		session.closed = true
		session.player:Kick("AI Empire: Your company was opened on another server.")
		return false
	end
	return saved == true
end

local function waitForSession(player: any): Session?
	local waited = 0
	while true do
		local session = deps.getSession(player)
		if session then
			return session
		end
		if player.Parent == nil or waited >= ShopConfig.SESSION_WAIT_SECONDS then
			return nil
		end
		task.wait(0.5)
		waited += 0.5
	end
end

-- The effect of one purchase. Must never fail: cash, a voucher count or a tip count.
local function grant(session: Session, def: ShopConfig.Product): { [string]: any }
	local shop = shopOf(session)
	if def.kind == "cash" then
		local office = ShopMath.office(session.data)
		if shop.packs[def.key] == office then
			-- S1 on the server: this office already got its pack of this size (a purchase outside our UI, a double tap
			-- before the snapshot hid the chip). The receipt is never refused; the cash waits as a credit and is paid at
			-- the next office, at that office's amount (payPackCredits). So no office ever gets two packs of one size.
			local credit = math.min(ShopConfig.VOUCHER_MAX, math.max(0, math.floor(tonumber(shop.packCredit[def.key]) or 0)) + 1)
			shop.packCredit[def.key] = credit
			return { key = def.key, kind = "cash", amount = 0, credit = credit }
		end
		local amount = ShopConfig.cashFor(def, office)
		EconomyService.grant(session, amount, "shop") -- P&L line "shop" (corefix request 8)
		shop.packs[def.key] = office -- S1: one of each size per office
		return { key = def.key, kind = "cash", amount = amount }
	elseif def.kind == "voucher" and def.voucher then
		local count = (tonumber(shop.vouchers[def.voucher]) or 0) + 1
		shop.vouchers[def.voucher] = count
		return { key = def.key, kind = "voucher", voucher = def.voucher, count = count }
	end
	shop.tips += 1
	return { key = def.key, kind = "tip", tips = shop.tips }
end

-- S1 credits (see grant): after an office move, one saved credit per pack size is paid at the new office's amount and
-- counts as that office's pack (packs[key] = office), so the buy chip stays hidden there. EmpireService.upgrade calls
-- this right after the move; no yield. Returns the cash paid.
function Shop.payPackCredits(session: Session): number
	local shop = shopOf(session)
	local office = ShopMath.office(session.data)
	local total = 0
	for _, def in ShopConfig.PRODUCTS do
		local n = math.floor(tonumber(shop.packCredit[def.key]) or 0)
		if def.kind == "cash" and n >= 1 and shop.packs[def.key] ~= office then
			local amount = ShopConfig.cashFor(def, office)
			EconomyService.grant(session, amount, "shop")
			shop.packs[def.key] = office
			shop.packCredit[def.key] = if n > 1 then n - 1 else nil
			total += amount
			Remote.fire(session.player, "Notify", "SHOP_GRANTED", { key = def.key, kind = "cash", amount = amount, fromCredit = true })
		end
	end
	if total > 0 then
		SessionService.markDirty(session, true)
	end
	return total
end

local function trimReceipts(shop: any)
	while #shop.order > ShopConfig.RECEIPTS_KEPT do
		local oldest = table.remove(shop.order, 1)
		if typeof(oldest) == "string" then
			shop.receipts[oldest] = nil
		end
	end
end

-- MarketplaceService.ProcessReceipt
function Shop.processReceipt(info: any): Enum.ProductPurchaseDecision
	if typeof(info) ~= "table" then
		return NOT_PROCESSED
	end
	local purchaseId, playerId, productId = info.PurchaseId, info.PlayerId, info.ProductId
	if typeof(purchaseId) ~= "string" or #purchaseId == 0 or #purchaseId > 128 then
		return NOT_PROCESSED
	end
	if typeof(playerId) ~= "number" or typeof(productId) ~= "number" then
		return NOT_PROCESSED
	end
	local def = ShopConfig.productById(productId)
	if not def then
		warn(`[Shop] receipt {purchaseId}: unknown product {productId} (not in ShopConfig.PRODUCTS)`)
		return NOT_PROCESSED
	end
	local player = deps.players:GetPlayerByUserId(playerId)
	if not player then
		return NOT_PROCESSED -- Roblox retries when the player is back
	end
	local session = waitForSession(player)
	if not session or session.closed then
		return NOT_PROCESSED
	end
	-- check, grant and record without yielding in between
	local shop = shopOf(session)
	if shop.receipts[purchaseId] == nil then
		local result = grant(session, def)
		shop.receipts[purchaseId] = deps.now()
		table.insert(shop.order, purchaseId)
		trimReceipts(shop)
		SessionService.markDirty(session, true)
		Remote.fire(player, "Notify", "SHOP_GRANTED", result)
	end
	if Shop.saveNow(session) then
		return GRANTED
	end
	return NOT_PROCESSED
end

------------------------------------------------------------------------------------------ vouchers

function Shop.setRedeemHandler(voucher: string, handler: Redeemer)
	redeemers[voucher] = handler
	publishAll()
end

-- Built-in voucher: a team party in front of the player's headquarters.
local function throwParty(session: Session): (boolean, string?)
	local Plot = deps.plot()
	local plot = Plot.get(session.player)
	local office: Instance? = if plot then plot.office else nil
	if not plot or not office or not office.Parent then
		return false, "NO_PLOT"
	end
	local running = parties[session]
	if running and running.Parent then
		return false, "PARTY_ACTIVE"
	end
	local company = session.data.company
	local kit = ShopDecor.party(office, plot.cframe, if company then company.name else session.player.DisplayName)
	parties[session] = kit
	local untilTime = workspace:GetServerTimeNow() + ShopConfig.PARTY_SECONDS
	office:SetAttribute("TeamPartyUntil", untilTime) -- for staff/talk systems that want to react
	task.delay(ShopConfig.PARTY_SECONDS, function()
		if kit.Parent then
			kit:Destroy()
		end
		if parties[session] == kit then
			parties[session] = nil
		end
		if office.Parent and office:GetAttribute("TeamPartyUntil") == untilTime then
			office:SetAttribute("TeamPartyUntil", nil)
		end
	end)
	return true, nil
end

-- Built-in voucher (SHOP_SPEC 3.4): 45 s of fireworks in the company colour above the headquarters.
local function fireworks(session: Session): (boolean, string?)
	local Plot = deps.plot()
	local plot = Plot.get(session.player)
	local office: Instance? = if plot then plot.office else nil
	if not plot or not office or not office.Parent then
		return false, "NO_PLOT"
	end
	local running = fireworksKits[session]
	if running and running.Parent then
		return false, "FIREWORKS_ACTIVE"
	end
	local company = session.data.company
	local def = if company then CompanyConfig.getColor(company.color) else nil
	local rgb = if def then def.rgb else { 120, 200, 174 }
	local kit = ShopDecor.fireworks(office, plot.cframe, Color3.fromRGB(rgb[1], rgb[2], rgb[3]), ShopConfig.FIREWORKS_SECONDS)
	fireworksKits[session] = kit
	task.delay(ShopConfig.FIREWORKS_SECONDS, function()
		if kit.Parent then
			kit:Destroy()
		end
		if fireworksKits[session] == kit then
			fireworksKits[session] = nil
		end
	end)
	return true, nil
end

-- SHOP_SPEC 6.3: every voucher redeem. Any refusal keeps the voucher; the daily counter rolls at 00:00 UTC and counts
-- successful redeems only.
local function redeem(session: Session, key: string, target: any): ServerTypes.Result
	if not ShopConfig.voucher(key) then
		return { ok = false, err = "BAD_INPUT" }
	end
	local want: string? = nil
	if target ~= nil then
		want = Guard.id(target)
		if not want then
			return { ok = false, err = "BAD_INPUT" }
		end
	end
	if (tonumber(shopOf(session).vouchers[key]) or 0) < 1 then
		return { ok = false, err = "NO_VOUCHER" }
	end
	local handler = redeemers[key]
	if not handler then
		return { ok = false, err = "NOT_AVAILABLE" } -- the voucher stays
	end
	if redeeming[session] then
		return { ok = false, err = "BUSY" }
	end
	local cap = ShopConfig.DAILY[key]
	local daily = shopOf(session).daily
	local today = ShopMath.utcDay(deps.now())
	if daily.day ~= today then
		daily.day = today
		daily.used = {}
	end
	if cap and (tonumber(daily.used[key]) or 0) >= cap then
		return { ok = false, err = "DAILY_LIMIT" }
	end
	redeeming[session] = true
	local ok, done, err = pcall(handler, session, want)
	redeeming[session] = nil
	if not ok then
		warn(`[Shop] redeem {key} failed: {done}`)
		return { ok = false, err = "SERVER_ERROR" }
	end
	if done ~= true then
		return { ok = false, err = if typeof(err) == "string" then err else "NOT_AVAILABLE" }
	end
	-- re-read after the handler (it may yield)
	local shop = shopOf(session)
	local vouchers = shop.vouchers
	local left = math.max(0, (tonumber(vouchers[key]) or 0) - 1)
	vouchers[key] = if left > 0 then left else nil
	if cap then
		local used = shop.daily.used
		used[key] = math.min(cap, (tonumber(used[key]) or 0) + 1)
	end
	SessionService.markDirty(session, true)
	return { ok = true, key = key, left = left }
end

local function action(session: Session, payload: ServerTypes.Payload): ServerTypes.Result
	local act = Guard.id(payload.action)
	if act == "status" then
		if payload.recheck == true and os.clock() - stateOf(session).checkedAt >= ShopConfig.RECHECK_SECONDS then
			Shop.refreshPasses(session)
		end
		if session.closed then
			return { ok = false, err = "LOADING" }
		end
		local flags = passFlags[session] or {}
		local passes: { [string]: boolean } = {}
		for _, def in ShopConfig.PASSES do
			if flags[def.key] == true then
				passes[def.key] = true
			end
		end
		local shop = shopOf(session)
		return { ok = true, passes = passes, vouchers = table.clone(shop.vouchers), available = Shop.available(),
			daily = table.clone(shop.daily), boosts = table.clone(shop.boosts) }
	elseif act == "redeem" then
		local key = Guard.id(payload.key)
		if not key then
			return { ok = false, err = "BAD_INPUT" }
		end
		return redeem(session, key, payload.target)
	end
	return { ok = false, err = "BAD_INPUT" }
end

----------------------------------------------------------------------------------- debug + tests

-- Studio test helpers (DebugService gates them to Studio). Flags only for this session, not saved.
function Shop.debugGrantPass(session: Session, key: string): boolean
	if not ShopConfig.pass(key) then
		return false
	end
	setPass(session, key, true, false)
	return true
end

function Shop.debugGrantVoucher(session: Session, key: string): boolean
	if not ShopConfig.voucher(key) then
		return false
	end
	local vouchers = shopOf(session).vouchers
	vouchers[key] = (tonumber(vouchers[key]) or 0) + 1
	SessionService.markDirty(session)
	return true
end

function Shop._setDeps(patch: { [string]: any })
	for key, value in patch do
		(deps :: any)[key] = value
	end
end

Shop._action = action
Shop._grant = grant -- the economy simulator buys cash packs through the real grant (fix round 1, S1 credits)

------------------------------------------------------------------------------------------- start

local function onLoaded(session: Session)
	passFlags[session] = passFlags[session] or {}
	publish(session)
	refreshTag(session.player)
	for _ = 0, ShopConfig.PASS_RETRIES do
		if session.closed or Shop.refreshPasses(session) then
			return
		end
		task.wait(ShopConfig.PASS_RETRY_SECONDS)
	end
end

function Shop.init()
	assert(not initialised, "ShopService.init called twice")
	initialised = true
	redeemers.party = throwParty
	redeemers.fireworks = fireworks
	redeemers.keynote = function(session: Session): (boolean, string?)
		return Shop.startBoost(session, "keynote")
	end
	redeemers.overclock = function(session: Session): (boolean, string?)
		return Shop.startBoost(session, "overclock")
	end
	deps.market.ProcessReceipt = Shop.processReceipt
	deps.market.PromptGamePassPurchaseFinished:Connect(onPassPurchaseFinished)
	Remote.bind("ShopAction", { burst = 4, perSecond = 1 }, action)
	SessionService.onLoaded(onLoaded)
	SessionService.onClosing(function(session: Session)
		passFlags[session] = nil
		passStates[session] = nil
		boughtNow[session] = nil
		redeeming[session] = nil
		parties[session] = nil -- the kit lives in the office and goes with it
		fireworksKits[session] = nil
	end)
	deps.players.PlayerAdded:Connect(watchCharacter)
	for _, player in deps.players:GetPlayers() do
		watchCharacter(player)
	end
	deps.plot().onChanged(function(_plot: any, session: any)
		if session and passFlags[session] then
			refreshOffice(session)
		end
	end)
end

return Shop
