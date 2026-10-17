--!strict
-- Client core of the shop package (SHOP_SPEC 5-6), shared by the Shop pages (ShopApp) and every Robux button outside
-- them (Lab → Research, the Lab level card, the Model Studio lock strip, the training view, Shop → Boosts):
--   * prices and icons from Roblox (GetProductInfoAsync, also IsForSale), fetched once, failures retried after 30 s;
--   * prompt(kind, id): Roblox's purchase window is the confirmation; nothing is granted on the client, ever;
--   * context buys remember `pendingUse = {key, target, at}`; when SHOP_GRANTED arrives within 120 s for that voucher,
--     the "received - use it now?" sheet opens (never an automatic redeem: the $ is paid when it is used);
--   * use(key, target): the UseSheet with the honest rows of 5.3, then ShopAction {action = "redeem", key, target};
--   * offerButton: the price-chip look "{ACTION} · EUREKA | R$ 15" (buy) or "| ×2" (owned); never the primary style;
--   * every offer goes through ShopMath.offerState (guide over, Shop unlocked, never within 10 s of a failure).
-- Texts: MESSAGES (errors end with "Your {item} is kept."), grantedText, REDEEMED (success toasts).

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local ShopConfig = require(Shared.Config.ShopConfig)
local EmpireConfig = require(Shared.Config.EmpireConfig)
local ModelConfig = require(Shared.Config.ModelConfig)
local ShopMath = require(Shared.ShopMath)
local EmpireMath = require(Shared.EmpireMath)
local Ops = require(Shared.CompanyOps)
local Format = require(Shared.Format)
local Types = require(Shared.Types)

local UI = script.Parent.Parent
local Client = UI.Parent
local State = require(Client.Controllers.StateController)
local Action = require(Client.Controllers.ActionController)
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Toast = require(UI.Toast)
local UseSheet = require(script.Parent.UseSheet)

local C = Theme.colors
local F = Theme.font

type Snapshot = Types.Snapshot
export type ItemKind = "product" | "pass"
export type PriceInfo = { price: number, forSale: boolean, icon: number? }

local ShopCore = {}

-- Seams for the headless tests: MarketplaceService does not exist outside Roblox.
local deps = {
	market = MarketplaceService :: any,
	player = function(): any
		return Players.LocalPlayer
	end,
	studio = function(): boolean
		local ok, value = pcall(function(): boolean
			return RunService:IsStudio()
		end)
		return ok and value == true
	end,
}
function ShopCore._setDeps(patch: { [string]: any })
	for key, value in patch do
		(deps :: any)[key] = value
	end
end

ShopCore.PRICE_RETRY_SECONDS = 30
ShopCore.PENDING_SECONDS = 120

---------------------------------------------------------------------------------------------- texts

local ITEM_WORD: { [string]: string } = { eureka = "Eureka", lastEpoch = "Last Epoch", keynote = "Keynote Boost", overclock = "Overclock", fireworks = "voucher" }
local function kept(key: string?): string
	return ` Your {if key and ITEM_WORD[key] then ITEM_WORD[key] else "voucher"} is kept.`
end
local function resetTime(now: number): string
	local nextMidnight = (math.floor(now / 86400) + 1) * 86400
	local t = os.date("*t", nextMidnight) :: any
	return string.format("%02d:%02d", tonumber(t.hour) or 0, tonumber(t.min) or 0)
end
ShopCore.MESSAGES = {
	RESEARCH_ACTIVE = "Another project is running. Finish that one first.",
	PREREQUISITE = "Finish the research it builds on first.",
	ALREADY_DONE = "Already researched.",
	MAX_LEVEL = "All 10 Lab levels are done.",
	NO_COMPANY = "Found your company first.",
	NO_TRAINING = "Nothing is training right now.",
	DECIDE_FIRST = "Decide the training event first.",
	NO_LIVE_MODEL = "Release an AI first: Keynote Boost adds to app and API income.",
	BOOST_FULL = "This boost already has an hour left.",
	FIREWORKS_ACTIVE = "Fireworks are already going.",
	PARTY_ACTIVE = "A party is already running at your headquarters.",
	NO_PLOT = "Your headquarters isn't ready yet. Try again in a moment.",
	BUSY = "One moment, the last item is still being used.",
	APPLICANTS_FULL = "Your application list is full. Hire or reject someone first.",
	STAFF_FULL = "All desks are filled.",
	NO_CANDIDATE = "No applicant found right now.",
	NOT_AVAILABLE = "This can't be used yet.",
	NO_VOUCHER = "You don't have that item.",
	BAD_INPUT = "That didn't work. Try again.",
} :: { [string]: string }

-- the error toast of a refused use (SHOP_SPEC 5.4); `cost` fills NO_MONEY
function ShopCore.message(err: string?, key: string?, cost: number?): string
	local tail = kept(key)
	if err == "NO_MONEY" then
		return (if cost then `You need {Format.money(cost)} for this.` else "You need more cash for this.") .. tail
	elseif err == "DAILY_LIMIT" then
		local n = if key then ShopConfig.DAILY[key] else nil
		local snapshot = State.snapshot
		local now = if snapshot then tonumber((snapshot :: any).serverTime) or os.time() else os.time()
		return `That's today's limit ({n or "a few"} a day). It resets at {resetTime(now)}.` .. tail
	elseif err == "NO_VOUCHER" then
		return ShopCore.MESSAGES.NO_VOUCHER
	end
	local text = if err then ShopCore.MESSAGES[err] else nil
	return (text or Action.message(err)) .. tail
end

ShopCore.WHERE = {
	eureka = "Use it in Lab → Research.",
	lastEpoch = "Use it in the training view.",
	keynote = "Start it in Shop → Boosts.",
	overclock = "Start it in Shop → Boosts.",
	fireworks = "Use it in Shop → Home.",
	party = "Use it in Shop → Home.",
	headhunter = "Use it in Shop → Home.",
} :: { [string]: string }

function ShopCore.itemName(key: string): string
	local product = ShopConfig.product(key)
	if product then
		return product.name
	end
	local pass = ShopConfig.pass(key)
	if pass then
		return pass.name
	end
	local voucher = ShopConfig.voucher(key)
	return if voucher then voucher.name else key
end

function ShopCore.grantedText(payload: { [string]: any }): string
	local kind = payload.kind
	local key = if typeof(payload.key) == "string" then payload.key else ""
	if kind == "cash" and typeof(payload.amount) == "number" then
		-- S1 on the server (fix round 1): a second pack of one size in one office is saved for the next office
		if typeof(payload.credit) == "number" then
			local snapshot = State.snapshot
			local office = if snapshot then ShopMath.office(snapshot.data) else 1
			if office >= #EmpireConfig.OFFICES then
				return `Thank you! This office already had its {ShopCore.itemName(key)}, and it is your last office, so this one is saved but can't be paid out.`
			end
			return `Thank you! This office already had its {ShopCore.itemName(key)}. This one is paid when you move to your next office.`
		elseif payload.fromCredit == true then
			return `+{Format.money(payload.amount)} company cash: your saved {ShopCore.itemName(key)} for this office.`
		end
		return `Thank you! +{Format.money(payload.amount)} company cash.`
	elseif kind == "voucher" then
		local voucher = if typeof(payload.voucher) == "string" then payload.voucher else key
		return `{ShopCore.itemName(voucher)} added. {ShopCore.WHERE[voucher] or "Use it in the Shop."}`
	elseif kind == "pass" then
		return `{ShopCore.itemName(key)} is yours.`
	end
	return "Thank you so much for supporting the game!"
end

ShopCore.REDEEMED = {
	party = "Party time! Look in front of your headquarters.",
	headhunter = "The headhunter found someone. Check your applications.",
	fireworks = "Fireworks! Look up above your HQ.",
	lastEpoch = "Training finished (Last Epoch).",
	keynote = "Keynote Boost started: 15 min of play.",
	overclock = "Overclock started: 15 min of play.",
} :: { [string]: string }

---------------------------------------------------------------------------------------------- prices

local prices: { [string]: PriceInfo } = {}
local failedAt: { [string]: number } = {}
local fetching: { [string]: boolean } = {}
local listeners: { () -> () } = {}

function ShopCore.priceKey(kind: ItemKind, id: number): string
	return kind .. ":" .. tostring(id)
end

function ShopCore.onChange(fn: () -> ())
	table.insert(listeners, fn)
end
local function changed()
	for _, fn in listeners do
		task.spawn(fn)
	end
end

-- the loaded price (nil while loading, after a failure or when Roblox says IsForSale = false)
function ShopCore.priceOf(kind: ItemKind, id: number): number?
	local info = prices[ShopCore.priceKey(kind, id)]
	return if info and info.forSale then info.price else nil
end
function ShopCore.iconOf(kind: ItemKind, id: number): number?
	local info = prices[ShopCore.priceKey(kind, id)]
	return if info then info.icon else nil
end
function ShopCore.isFetching(): boolean
	for _, busy in fetching do
		if busy then
			return true
		end
	end
	return false
end
function ShopCore.anyFailed(): boolean
	for key in failedAt do
		local _ = key
		return true
	end
	for _, info in prices do
		if not info.forSale then
			return true
		end
	end
	return false
end

-- one lookup per item; a failure is retried on a later call after PRICE_RETRY_SECONDS
function ShopCore.fetchPrice(kind: ItemKind, id: number)
	local key = ShopCore.priceKey(kind, id)
	if id <= 0 or prices[key] ~= nil or fetching[key] then
		return
	end
	local failed = failedAt[key]
	if failed and os.clock() - failed < ShopCore.PRICE_RETRY_SECONDS then
		return
	end
	fetching[key] = true
	task.spawn(function()
		local ok, info = pcall(function(): any
			return deps.market:GetProductInfoAsync(id, if kind == "pass" then Enum.InfoType.GamePass else Enum.InfoType.Product)
		end)
		fetching[key] = nil
		local price = if ok and typeof(info) == "table" then info.PriceInRobux else nil
		if typeof(price) == "number" and price == price and price >= 0 then
			-- ONBOARDING_SPEC C4: IsForSale must be true as well as a price; the icon comes from the same answer
			local forSale = info.IsForSale ~= false
			local icon = info.IconImageAssetId
			prices[key] = { price = price, forSale = forSale, icon = if typeof(icon) == "number" and icon > 0 then icon else nil }
			failedAt[key] = nil
		else
			failedAt[key] = os.clock()
		end
		changed()
	end)
end

function ShopCore.fetchAll()
	for _, def in ShopConfig.PRODUCTS do
		ShopCore.fetchPrice("product", def.id)
	end
	for _, def in ShopConfig.PASSES do
		ShopCore.fetchPrice("pass", def.id)
	end
end

function ShopCore.priceText(price: number): string
	return "R$ " .. Format.int(price)
end

function ShopCore.isStudio(): boolean
	return deps.studio()
end

-- Opens the Roblox purchase window. Nothing is granted here. Never for id 0 (Studio preview: "Not set up").
function ShopCore.prompt(kind: ItemKind, id: number): boolean
	if id <= 0 then
		return false
	end
	local ok = pcall(function()
		if kind == "pass" then
			deps.market:PromptGamePassPurchase(deps.player(), id)
		else
			deps.market:PromptProductPurchase(deps.player(), id)
		end
	end)
	if not ok then
		Toast.show("error", "The Roblox purchase window could not open. Try again.")
	end
	return ok
end

---------------------------------------------------------------------------------------------- offers

local function serverNow(snapshot: Snapshot?): number
	local t = if snapshot then tonumber((snapshot :: any).serverTime) else nil
	return t or os.time()
end
ShopCore.serverNow = serverNow

-- empire.seconds now (play time), extrapolated between snapshots
function ShopCore.playSeconds(snapshot: Snapshot): number
	return (tonumber(snapshot.data.empire.seconds) or 0) + State.elapsed()
end

function ShopCore.offerUi(snapshot: Snapshot, key: string): ShopMath.OfferUi
	local def = ShopConfig.productForVoucher(key)
	local failure = Action.lastFailure
	-- a context button may come before the Shop page was ever opened: look its price up on demand (once the Shop is
	-- open for this player; fetchPrice asks Roblox once per item and retries a failure after PRICE_RETRY_SECONDS)
	if def and def.id > 0 and ShopCore.priceOf("product", def.id) == nil and ShopMath.gateOpen(snapshot.data) then
		ShopCore.fetchPrice("product", def.id)
	end
	return {
		live = snapshot.live,
		priced = def ~= nil and def.id > 0 and ShopCore.priceOf("product", def.id) ~= nil,
		studio = deps.studio(),
		clock = os.clock(),
		lastErrorAt = if failure then failure.at else nil,
		now = serverNow(snapshot),
	}
end

-- (state, count, label): "owned" + count, "buy" + "R$ 15", "preview" + "Not set up", or nil (no button)
function ShopCore.offer(snapshot: Snapshot, key: string): (string?, number, string)
	local state = ShopMath.offerState(snapshot.data, key, ShopCore.offerUi(snapshot, key))
	local count = ShopMath.vouchers(snapshot.data, key)
	if state == "owned" then
		return state, count, `×{count}`
	elseif state == "buy" then
		local def = ShopConfig.productForVoucher(key)
		local price = if def then ShopCore.priceOf("product", def.id) else nil
		return state, count, if price then ShopCore.priceText(price) else "…"
	elseif state == "preview" then
		return state, count, "Not set up"
	end
	return nil, count, ""
end

-- Eureka offer on `target`: the gate, then the job check (buy and preview states need the 30 s saving / RP short)
function ShopCore.eurekaOffer(snapshot: Snapshot, target: string?, money: number): (string?, ShopMath.Check?, string)
	local state, _, label = ShopCore.offer(snapshot, "eureka")
	if not state then
		return nil, nil, ""
	end
	local check = ShopMath.eurekaCheck(snapshot.data, target, money, state ~= "owned", serverNow(snapshot))
	if not check.ok then
		return nil, check, ""
	end
	return state, check, label
end

-- Last Epoch offer: training running, no decision pending, under the daily cap; buy / preview need >= 20 s left
function ShopCore.lastEpochOffer(snapshot: Snapshot): (string?, number, string)
	local state, _, label = ShopCore.offer(snapshot, "lastEpoch")
	if not state then
		return nil, 0, ""
	end
	local eta = ShopCore.trainingEta(snapshot)
	local ok = ShopMath.lastEpochCheck(snapshot.data, eta, state ~= "owned", serverNow(snapshot))
	if not ok then
		return nil, eta, ""
	end
	return state, eta, label
end

-- seconds left of the running training (with Overclock), like StateController.trainingEta
function ShopCore.trainingEta(snapshot: Snapshot): number
	local training = snapshot.data.training
	if not training then
		return 0
	end
	return State.trainingEta()
end

---------------------------------------------------------------------------------------------- use sheets

local function money(n: number): string
	return "$" .. Format.int(n)
end

local function rateText(data: any, now: number): string
	return string.format("+%.1f RP/s", ShopMath.peakRate(data, now))
end

-- The rows of a use sheet (SHOP_SPEC 5.3), or nil when the action would not work right now. opts.received = the
-- "received - use it now?" form; opts.extra = more rows (Studio: THEN "7B training costs $x").
export type SpecOpts = { received: boolean?, extra: { UseSheet.Row }?, targetName: string? }
function ShopCore.spec(snapshot: Snapshot, key: string, target: string?, opts: SpecOpts?): UseSheet.Spec?
	local o: SpecOpts = opts or {}
	local data: any = snapshot.data
	local now = serverNow(snapshot)
	local cash = State.money()
	local have = ShopMath.vouchers(data, key)
	local title, sub, rows, actionLabel, icon = "", nil :: string?, {} :: { UseSheet.Row }, "", "shop"
	local where = ""
	if key == "eureka" then
		icon = "bulb"
		local check = ShopMath.eurekaCheck(data, target, cash, false, now)
		if not check.ok then
			return nil
		end
		actionLabel = "USE EUREKA"
		sub = `Eureka · you have {have}`
		local saves = if check.seconds < 1 then "no time" else ShopMath.savingText(check.seconds)
		local savesTail = if check.seconds < 1 then "your research points cover it" else `at your office-hours speed ({rateText(data, now)})`
		if check.kind == "lab" then
			local L = check.level or 0
			title = `Use 1 Eureka on Lab level {L + 1}?`
			where = `Lab level {L + 1}`
			rows = {
				{ caption = "Finishes", value = `Lab level {L} → {L + 1} now`, tail = "+1 core stat on new models" },
				-- fix round 1: no "you have 0, they stay yours" tail with 0 RP
				{ caption = "Covers", value = `{Format.int(check.points)} RP`, tail = if check.have > 0 then `you have {Format.int(check.have)}, they stay yours` else nil },
				{ caption = "You pay", value = money(check.cost), tail = `cash after {money(cash - check.cost)}` },
				{ caption = "Saves", value = saves, tail = savesTail },
			}
		elseif check.kind == "running" then
			local def = EmpireConfig.find(EmpireConfig.RESEARCH, check.id)
			title = `Finish {check.name} now?`
			where = check.name or ""
			rows = {
				{ caption = "Finishes", value = `{check.name} now`, tail = if def then def.desc else nil },
				{ caption = "Comes back", value = `{Format.int(check.points)} RP` },
				{ caption = "You pay", value = "nothing more" },
				{ caption = "Saves", value = ShopMath.clock(check.seconds) },
			}
		else
			local def = EmpireConfig.find(EmpireConfig.RESEARCH, check.id)
			title = `Use 1 Eureka on {check.name}?`
			where = check.name or ""
			rows = {
				{ caption = "Finishes", value = `{check.name} now`, tail = if def then def.desc else nil },
				{ caption = "Covers", value = `{Format.int(check.points)} RP`,
					tail = if check.have >= check.points then `you keep your {Format.int(check.have)} RP` elseif check.have > 0 then `you have {Format.int(check.have)}, they stay yours` else nil },
				{ caption = "You pay", value = money(check.cost), tail = `cash after {money(cash - check.cost)}` },
				{ caption = "Saves", value = saves, tail = savesTail },
			}
		end
	elseif key == "lastEpoch" then
		icon = "epoch"
		local eta = ShopCore.trainingEta(snapshot)
		if not ShopMath.lastEpochCheck(data, eta, false, now) then
			return nil
		end
		local training = data.training
		local m = if training then data.models[training.modelId] else nil
		local name = if m then `{m.name} v{m.version}` else "Your AI"
		title = "Finish this training now?"
		sub = `Last Epoch · you have {have}`
		where = "this training"
		actionLabel = "USE LAST EPOCH"
		rows = {
			{ caption = "Finishes", value = `{name} now`, tail = "same chances as waiting" },
			{ caption = "Event", value = "decided first if one comes" },
			{ caption = "Skips", value = "the extra time of an event choice" },
			{ caption = "Saves", value = Format.duration(eta) },
		}
	elseif key == "keynote" or key == "overclock" then
		icon = if key == "keynote" then "mic" else "bolt"
		local ok = ShopMath.boostCheck(data, key, now, ShopCore.playSeconds(snapshot))
		if not ok then
			return nil
		end
		local running = ShopMath.boostLeft(data, key, ShopCore.playSeconds(snapshot)) > 0
		local name = ShopCore.itemName(key)
		title = if running then `Add 15 min of {name}?` else `Start {name}?`
		sub = `{name} · you have {have}`
		where = "Shop → Boosts"
		actionLabel = if running then "ADD 15 MIN" else "START"
		local used = ShopMath.dailyUsed(data, key, now)
		local play = ShopCore.playSeconds(snapshot)
		local left = ShopMath.boostLeft(data, key, play)
		local def = ShopConfig.BOOSTS[key]
		if running then
			-- fix round 1 (review blocking #2): while the boost runs, its effect already applies; ADD 15 MIN only keeps it
			-- going longer (one rate, never stacked), so the sheet promises no extra $/min and no faster run
			local effect = if key == "keynote" then "+20 %" else "×1.5"
			rows = {
				{ caption = "Effect", value = if key == "keynote" then "+20 % on app and API income" else "training 1.5× as fast" },
				{ caption = "Now", value = `keeps {effect} for 15 more min of play`, tail = `left {ShopMath.clock(left)} → {ShopMath.clock(left + def.seconds)}` },
				{ caption = "Length", value = "+15 min of play", tail = `{used + 1} of {ShopConfig.DAILY[key]} today` },
			}
		elseif key == "keynote" then
			-- the gain from the UNBOOSTED market income: MarketService already multiplied perModel.revenue by
			-- shopFactor = (Investor 1.10 or 1) + the Keynote bonus (S6), so divide that factor out first
			local market = 0
			local perModel = (snapshot.live :: any).perModel
			if typeof(perModel) == "table" then
				for _, r in perModel do
					market += tonumber(r.revenue) or 0
				end
			end
			local liveShop = (snapshot.live :: any).shop
			local investor = typeof(liveShop) == "table" and ShopMath.ownsPass(liveShop.passes, "investor")
			local factor = (if investor then ShopConfig.INVESTOR_MULTIPLIER else 1) + ShopMath.revenueBonus(data, play)
			local base = market / math.max(1e-6, factor)
			rows = {
				{ caption = "Effect", value = "+20 % on app and API income" },
				{ caption = "Now", value = `about +{Format.money(base * 60 * (def.revenue or 0))}/min right now`, tail = "it moves with the market" },
				{ caption = "Length", value = "15 min of play", tail = `{used + 1} of {ShopConfig.DAILY[key]} today` },
			}
		else
			local nowText = "no training is running right now"
			if data.training then
				-- not running: StateController.trainingEta is the unboosted ETA here (trainingFactor = 1)
				local eta = ShopCore.trainingEta(snapshot)
				local workTotal = tonumber(data.training.workTotal) or 0
				local base = EmpireMath.trainingRate(data.gpus, workTotal, data.empire)
				local boosted = math.min(base * (ShopConfig.BOOSTS.overclock.training or 1), workTotal / ModelConfig.TRAINING.minSeconds)
				local after = if boosted > 0 then eta * base / boosted else eta
				nowText = if ShopMath.atTrainingMinimum(data) then "this run is already at the 12 s minimum" else `this run about {Format.duration(eta)} → {Format.duration(after)}`
			end
			rows = {
				{ caption = "Effect", value = "training 1.5× as fast" },
				{ caption = "Now", value = nowText },
				{ caption = "Length", value = "15 min of play", tail = `{used + 1} of {ShopConfig.DAILY[key]} today` },
			}
		end
	else
		return nil
	end
	local extra: { UseSheet.Row } = o.extra or {}
	for _, r in extra do
		table.insert(rows, r)
	end
	local spec: UseSheet.Spec = {
		icon = icon,
		title = title,
		sub = sub,
		rows = rows,
		action = actionLabel,
		cancel = "CANCEL",
		onAction = function() end,
	}
	if o.received then
		spec.title = `{ShopCore.itemName(key)} received. Use it now?`
		spec.sub = `On {o.targetName or where} · you can also keep it for later`
		spec.action = "USE NOW"
		spec.cancel = "LATER"
	end
	return spec
end

-- ShopAction redeem with the success / error toasts. done(ok) after the reply.
function ShopCore.redeem(key: string, target: string?, done: ((boolean) -> ())?)
	task.spawn(function()
		local before = State.snapshot
		local cost: number? = nil
		if before and key == "eureka" then
			local check = ShopMath.eurekaCheck(before.data, target, math.huge, false, serverNow(before))
			cost = if check.ok then check.cost else nil
		end
		local level = if before then tonumber(before.data.empire.labLevel) or 0 else 0
		local payload: { [string]: any } = { action = "redeem", key = key }
		if target then
			payload.target = target
		end
		local ok, result = Action.call("ShopAction", payload, true)
		if ok then
			if key == "eureka" and target == "lab" then
				Toast.show("success", `Lab level {level + 1} (Eureka): new models get +1 on every core stat.`, 5)
			elseif key ~= "eureka" then
				Toast.show("success", ShopCore.REDEEMED[key] or "Done.", 5)
			end
			-- projects: the server notice "Research complete: {name}" shows (no second toast, SHOP_SPEC 3.1)
		else
			local err = if typeof(result.err) == "string" then result.err else nil
			Toast.show("error", ShopCore.message(err, key, cost))
		end
		if done then
			done(ok)
		end
	end)
end

-- The UseSheet for an owned voucher; opts.onDone(ok) after the redeem (Studio: "7B is unlocked.")
export type UseOpts = { extra: { UseSheet.Row }?, onDone: ((boolean) -> ())?, received: boolean?, targetName: string? }
function ShopCore.use(key: string, target: string?, opts: UseOpts?): boolean
	local o: UseOpts = opts or {}
	local snapshot = State.snapshot
	if not snapshot then
		return false
	end
	local spec = ShopCore.spec(snapshot, key, target, { extra = o.extra, received = o.received, targetName = o.targetName })
	if not spec then
		return false
	end
	spec.onAction = function()
		UseSheet.setBusy(true)
		ShopCore.redeem(key, target, function(ok: boolean)
			UseSheet.close()
			if o.onDone then
				o.onDone(ok)
			end
		end)
	end
	UseSheet.open(spec)
	return true
end

---------------------------------------------------------------------------------------------- buying

type Pending = { key: string, target: string?, at: number, opts: UseOpts? }
local pendingUse: Pending? = nil
-- is the Menu (or the Model Studio inside it) open? Computer registers it (it requires this module, not the other
-- way round). The received sheet is skipped in the world: the grant toast says where the voucher is.
local hostOpen: () -> boolean = function(): boolean
	return true
end
function ShopCore.setHostOpen(fn: () -> boolean)
	hostOpen = fn
end

-- a context Robux button: remember what it was for, then open Roblox's window (never redeemed automatically)
function ShopCore.buy(key: string, target: string?, opts: UseOpts?): boolean
	local def = ShopConfig.productForVoucher(key)
	if not def or def.id <= 0 then
		Toast.show("info", "Not set up yet: the owner adds this product on the Creator Hub (Studio preview).")
		return false
	end
	pendingUse = { key = key, target = target, at = os.clock(), opts = opts }
	return ShopCore.prompt("product", def.id)
end

function ShopCore.pending(): Pending?
	return pendingUse
end

-- SHOP_GRANTED: the received sheet for the matching pending context buy (within 120 s), otherwise the toast
function ShopCore.onGranted(payload: { [string]: any })
	local voucher = if payload.kind == "voucher" and typeof(payload.voucher) == "string" then payload.voucher else nil
	local p = pendingUse
	if voucher and p and p.key == voucher and os.clock() - p.at < ShopCore.PENDING_SECONDS then
		pendingUse = nil
		local o: UseOpts = table.clone(p.opts or {})
		o.received = true
		-- the state moved on (the grant's snapshot may still be on its way): build the sheet with the next snapshot
		task.delay(0.3, function()
			if not hostOpen() or not ShopCore.use(voucher, p.target, o) then
				Toast.show("success", ShopCore.grantedText(payload), 5)
			end
		end)
		return
	end
	Toast.show("success", ShopCore.grantedText(payload), 5)
end

---------------------------------------------------------------------------------------------- the button

export type OfferButton = { button: TextButton, label: TextLabel, right: TextLabel, set: (state: string?, rightText: string) -> () }
-- The Robux context button (SHOP_SPEC 5.2.1): raised fill, accent stroke 45 %, "{ACTION} · EUREKA", a divider, then
-- the price ("R$ 15"), the count ("×2") or "Not set up" (Studio). Never the primary style. plain = true keeps the
-- ordinary secondary look (no accent stroke): where the free buttons next to it are plain too (the training view).
function ShopCore.offerButton(parent: Instance, text: string, size: UDim2, textSize: number?, plain: boolean?): OfferButton
	local b = Kit.button(parent, "", "secondary", size)
	b.Name = "OfferButton"
	b.Selectable = true
	if not plain then
		local stroke = b:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke:Destroy()
		end
		local accent = Kit.stroke(b, 0.55, Theme.accent, 2)
		accent.Name = "AccentStroke"
	end
	local row = Kit.frame(b, UDim2.fromScale(1, 1))
	row.Name = "Row"
	local list = Kit.list(row, 8, true)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	local ts = textSize or 22
	local label = Kit.text(row, text, ts, F.bold, C.text)
	label.Name = "OfferLabel"
	label.LayoutOrder = 1
	local divider = Kit.frame(row, UDim2.fromOffset(2, math.floor(ts * 1.2)))
	divider.Name = "Divider"
	divider.LayoutOrder = 2
	divider.BackgroundTransparency = 0.6
	divider.BackgroundColor3 = C.line
	local right = Kit.text(row, "", ts, F.bold, C.warn)
	right.Name = "OfferRight"
	right.LayoutOrder = 3
	local handle: OfferButton = {
		button = b,
		label = label,
		right = right,
		set = function(state: string?, rightText: string)
			b.Visible = state ~= nil
			right.Text = rightText
			right.TextColor3 = if state == "owned" then C.good elseif state == "preview" then C.dim else C.warn
			b:SetAttribute("OfferState", state)
		end,
	}
	return handle
end

---------------------------------------------------------------------------------------------- focus requests

-- a deep link that wants one item outlined on its page (Studio OPEN RESEARCH › -> Lab → Research focus "frontier")
local focusRequests: { [string]: string } = {}
function ShopCore.requestFocus(page: string, id: string)
	focusRequests[page] = id
end
function ShopCore.takeFocus(page: string): string?
	local id = focusRequests[page]
	focusRequests[page] = nil
	return id
end

-- scrolls the nearest ScrollingFrame so `target` is at its top (CanvasPosition is in pre-UIScale units)
function ShopCore.scrollTo(target: GuiObject)
	local scroll = target:FindFirstAncestorWhichIsA("ScrollingFrame")
	if not scroll then
		return
	end
	task.defer(function()
		local scale = 1
		local node: Instance? = scroll
		while node do
			local u = node:FindFirstChildOfClass("UIScale")
			if u then
				scale *= u.Scale
			end
			node = node.Parent
		end
		local dy = (target.AbsolutePosition.Y - scroll.AbsolutePosition.Y) / math.max(1e-3, scale)
		scroll.CanvasPosition = Vector2.new(0, math.max(0, scroll.CanvasPosition.Y + dy - 12))
	end)
end

---------------------------------------------------------------------------------------------- mount

local mounted = false
local lastBoost: { [string]: boolean } = {}
function ShopCore.mount()
	if mounted then
		return
	end
	mounted = true
	State.onNotify(function(kind: string, payload: { [string]: any })
		if kind == "SHOP_GRANTED" then
			ShopCore.onGranted(payload)
		end
	end)
	-- "{Boost} ended." once a running boost reaches 0 (play time)
	State.onChange(function(snapshot: Snapshot)
		for key in ShopConfig.BOOSTS do
			local on = ShopMath.boostLeft(snapshot.data, key) > 0
			if lastBoost[key] == true and not on then
				Toast.show("info", `{ShopCore.itemName(key)} ended.`, 4)
			end
			lastBoost[key] = on
		end
	end)
	-- UI feedback only (the server grants via ProcessReceipt / the pass event)
	pcall(function()
		deps.market.PromptProductPurchaseFinished:Connect(function(userId: number, _productId: number, purchased: boolean)
			local player = deps.player()
			if purchased and player and userId == player.UserId then
				Toast.show("info", "Purchase received. Adding it to your company...")
			end
		end)
		deps.market.PromptGamePassPurchaseFinished:Connect(function(who: any, _passId: number, purchased: boolean)
			if purchased and who == deps.player() then
				task.delay(1, function()
					Action.call("ShopAction", { action = "status", recheck = true }, true)
				end)
			end
		end)
	end)
end

local _ = Ops
return ShopCore
