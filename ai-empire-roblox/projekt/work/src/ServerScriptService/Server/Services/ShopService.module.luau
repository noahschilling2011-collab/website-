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
-- Public API for other systems:
--   ShopService.owns(player|session, passKey) -> boolean        (VehicleService: limo)
--   ShopService.revenueMultiplier(session) -> number             (MarketService: investor pass)
--   ShopService.setRedeemHandler(voucherKey, fn(session) -> (ok, errCode?))   (RecruitingService: headhunter)
--   ShopService.onPassChanged(fn(session, passKey, owned))
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local ServerTypes = require(script.Parent.Parent.Lib.ServerTypes)
local Guard = require(script.Parent.Parent.Lib.Guard)
local Remote = require(script.Parent.Parent.Lib.Remote)
local Template = require(script.Parent.Parent.Lib.Template)
local SaveService = require(script.Parent.SaveService)
local SessionService = require(script.Parent.SessionService)
local EconomyService = require(script.Parent.EconomyService)
local ShopDecor = require(script.Parent.ShopDecor)

type Session = ServerTypes.Session
type Redeemer = (Session) -> (boolean, string?)
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
	for _, def in ShopConfig.PASSES do
		if def.key == "limo" then
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
		local existing = office:FindFirstChild(ShopDecor.SUITE_NAME)
		if owned and not existing then
			local tier = office:GetAttribute("OfficeTier")
			ShopDecor.founderSuite(office, plot.cframe, if typeof(tier) == "number" then tier else (session.data.empire.office :: number))
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
	elseif key == "founderSuite" then
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

function Shop.owns(target: Player | Session, key: string): boolean
	local session: Session? = if isSession(target) then target :: any else deps.getSession(target)
	if not session then
		return false
	end
	local flags = passFlags[session]
	return flags ~= nil and flags[key] == true
end

-- MarketService multiplies the player's own market revenue with this (after market shares are
-- computed, so it never changes anyone else's share). Its first call also makes the Investor pass
-- sellable: the pass is only offered once the game really applies it.
function Shop.revenueMultiplier(session: Session): number
	if not investorWired then
		investorWired = true
		publishAll()
	end
	return if Shop.owns(session, "investor") then ShopConfig.INVESTOR_MULTIPLIER else 1
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
		local amount = ShopConfig.cashFor(def, session.data.empire.office)
		EconomyService.grant(session, amount, "shop") -- P&L line "shop" (corefix request 8)
		return { key = def.key, kind = "cash", amount = amount }
	elseif def.kind == "voucher" and def.voucher then
		local count = (tonumber(shop.vouchers[def.voucher]) or 0) + 1
		shop.vouchers[def.voucher] = count
		return { key = def.key, kind = "voucher", voucher = def.voucher, count = count }
	end
	shop.tips += 1
	return { key = def.key, kind = "tip", tips = shop.tips }
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

local function redeem(session: Session, key: string): ServerTypes.Result
	if not ShopConfig.voucher(key) then
		return { ok = false, err = "BAD_INPUT" }
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
	redeeming[session] = true
	local ok, done, err = pcall(handler, session)
	redeeming[session] = nil
	if not ok then
		warn(`[Shop] redeem {key} failed: {done}`)
		return { ok = false, err = "SERVER_ERROR" }
	end
	if done ~= true then
		return { ok = false, err = if typeof(err) == "string" then err else "NOT_AVAILABLE" }
	end
	-- re-read after the handler (it may yield)
	local vouchers = shopOf(session).vouchers
	local left = math.max(0, (tonumber(vouchers[key]) or 0) - 1)
	vouchers[key] = if left > 0 then left else nil
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
		return { ok = true, passes = passes, vouchers = table.clone(shopOf(session).vouchers), available = Shop.available() }
	elseif act == "redeem" then
		local key = Guard.id(payload.key)
		if not key then
			return { ok = false, err = "BAD_INPUT" }
		end
		return redeem(session, key)
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
