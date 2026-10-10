--!strict
-- Shop: what players can spend Robux on (catalogue: ShopConfig, purchases: ShopService).
-- Prices come from Roblox (GetProductInfoAsync, fetched once); an item whose price can't be loaded is
-- hidden. Buy buttons only open the Roblox purchase window. Granting happens on the server
-- (ProcessReceipt / pass events) and arrives here as Notify SHOP_GRANTED; nothing is ever granted
-- from PromptProductPurchaseFinished. With every id at 0 the app says "Shop coming soon".

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local Format = require(ReplicatedStorage.Shared.Format)
local Types = require(ReplicatedStorage.Shared.Types)

local UI = script.Parent.Parent
local Client = UI.Parent
local State = require(Client.Controllers.StateController)
local Action = require(Client.Controllers.ActionController)
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Toast = require(UI.Toast)

local C = Theme.colors
local F = Theme.font

type Snapshot = Types.Snapshot
type ItemKind = "product" | "pass"

local App = {}

-- Seams for the headless client test (tests/shop): MarketplaceService does not exist outside Roblox.
local deps = {
	market = MarketplaceService :: any,
	player = function(): any
		return Players.LocalPlayer
	end,
}
function App._setDeps(patch: { [string]: any })
	for key, value in patch do
		(deps :: any)[key] = value
	end
end

local PRICE_RETRY_SECONDS = 30

local MESSAGES: { [string]: string } = {
	NO_VOUCHER = "You don't have that voucher.",
	NOT_AVAILABLE = "This voucher can't be redeemed yet. It stays in your account.",
	PARTY_ACTIVE = "A party is already running at your headquarters.",
	NO_PLOT = "Your headquarters isn't ready yet. Try again in a moment.",
	BUSY = "One moment, the last voucher is still being redeemed.",
	APPLICANTS_FULL = "Your application list is full. Hire or reject someone first; the voucher stays.",
	BAD_INPUT = "That didn't work. Try again.",
}

-- keyed by "product:<id>" / "pass:<id>" (ids are read live from ShopConfig)
local prices: { [string]: number } = {} -- PriceInRobux from Roblox
local failedAt: { [string]: number } = {} -- os.clock() of the last failed price lookup
local fetching: { [string]: boolean } = {}

local function priceKey(kind: ItemKind, id: number): string
	return kind .. ":" .. tostring(id)
end
local refreshers: { (Snapshot) -> () } = {}
local mounted = false

local function liveShop(snapshot: Snapshot?): any
	local live = if snapshot then snapshot.live :: any else nil
	local shop = if live then live.shop else nil
	return if typeof(shop) == "table" then shop else nil
end

local function dataShop(snapshot: Snapshot?): any
	local shop = if snapshot then (snapshot.data :: any).shop else nil
	return if typeof(shop) == "table" then shop else nil
end

function App.owns(snapshot: Snapshot?, key: string): boolean
	local shop = liveShop(snapshot)
	return shop ~= nil and typeof(shop.passes) == "table" and shop.passes[key] == true
end

local function isAvailable(snapshot: Snapshot?, key: string): boolean
	local shop = liveShop(snapshot)
	return shop ~= nil and typeof(shop.available) == "table" and shop.available[key] == true
end

local function canRedeem(snapshot: Snapshot?, key: string): boolean
	local shop = liveShop(snapshot)
	return shop ~= nil and typeof(shop.redeemable) == "table" and shop.redeemable[key] == true
end

local function voucherCount(snapshot: Snapshot?, key: string): number
	local shop = dataShop(snapshot)
	local count = if shop and typeof(shop.vouchers) == "table" then tonumber(shop.vouchers[key]) else nil
	return if count and count == count and count > 0 then math.floor(count) else 0
end

local function tips(snapshot: Snapshot?): number
	local shop = dataShop(snapshot)
	local n = if shop then tonumber(shop.tips) else nil
	return if n and n == n and n > 0 then math.floor(n) else 0
end

local function refreshAll()
	local snapshot = State.snapshot
	if not snapshot then
		return
	end
	for _, fn in refreshers do
		fn(snapshot)
	end
end

-- One lookup per item; failures are retried on the next onShow after PRICE_RETRY_SECONDS.
local function fetchPrice(kind: ItemKind, id: number)
	local key = priceKey(kind, id)
	if id <= 0 or prices[key] ~= nil or fetching[key] then
		return
	end
	local failed = failedAt[key]
	if failed and os.clock() - failed < PRICE_RETRY_SECONDS then
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
			prices[key] = price
			failedAt[key] = nil
		else
			failedAt[key] = os.clock()
		end
		refreshAll()
	end)
end

local function fetchAll()
	for _, def in ShopConfig.PRODUCTS do
		fetchPrice("product", def.id)
	end
	for _, def in ShopConfig.PASSES do
		fetchPrice("pass", def.id)
	end
end

-- Opens the Roblox purchase window. Nothing is granted here.
local function prompt(kind: ItemKind, id: number)
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
end

local function priceText(kind: ItemKind, id: number): string
	local price = prices[priceKey(kind, id)]
	return if price then "R$ " .. Format.int(price) else ""
end

local function title(parent: Instance, text: string, order: number): TextLabel
	local label = Kit.para(parent, text, 18, C.text, order)
	label.Font = F.bold
	return label
end

local function section(parent: Instance, text: string, order: number): TextLabel
	local label = Kit.caption(parent, text, order)
	label.TextSize = 14
	return label
end

local function card(parent: Instance, order: number): (Frame, TextLabel, TextLabel, TextButton)
	local frame = Kit.card(parent, order, 8)
	local name = title(frame, "", 1)
	local info = Kit.para(frame, "", 14, C.muted, 2)
	local button = Kit.button(frame, "", "primary", UDim2.new(1, 0, 0, 38))
	button.LayoutOrder = 3
	return frame, name, info, button
end

local function productText(def: ShopConfig.Product, snapshot: Snapshot): string
	if def.kind == "cash" then
		local amount = ShopConfig.cashFor(def, snapshot.data.empire.office)
		return `+{Format.money(amount)} company cash at your current office. {def.desc}`
	elseif def.key == "party" then
		local minutes = math.max(1, math.round(ShopConfig.PARTY_SECONDS / 60))
		return `{def.desc} Lasts {minutes} minute{if minutes == 1 then "" else "s"}.`
	end
	return def.desc
end

local function passText(def: ShopConfig.Pass): string
	if def.key == "investor" then
		return `+{math.round((ShopConfig.INVESTOR_MULTIPLIER - 1) * 100)}% revenue from your own AI models. {def.desc}`
	end
	return def.desc
end

local function grantedText(payload: { [string]: any }): string
	local kind = payload.kind
	local key = if typeof(payload.key) == "string" then payload.key else ""
	if kind == "cash" and typeof(payload.amount) == "number" then
		return `Thank you! +{Format.money(payload.amount)} company cash.`
	elseif kind == "voucher" then
		local def = ShopConfig.voucher(if typeof(payload.voucher) == "string" then payload.voucher else key)
		return `Thank you! {if def then def.name else "Voucher"} added. Redeem it in the Shop.`
	elseif kind == "pass" then
		local def = ShopConfig.pass(key)
		return `Thank you! {if def then def.name else "Your pass"} is now active.`
	end
	return "Thank you so much for supporting the game!"
end

local REDEEMED: { [string]: string } = {
	party = "Party time! Look in front of your headquarters.",
	headhunter = "The headhunter found someone. Check your applications.",
}

local function redeem(key: string, button: TextButton)
	Kit.setDisabled(button, true)
	task.spawn(function()
		local ok, result = Action.call("ShopAction", { action = "redeem", key = key }, true)
		Kit.setDisabled(button, false)
		if ok then
			Toast.show("success", REDEEMED[key] or "Voucher redeemed.")
		else
			local err = if typeof(result.err) == "string" then result.err else nil
			Toast.show("error", if err and MESSAGES[err] then MESSAGES[err] else Action.message(err))
		end
	end)
end

-- Sidebar status line in the computer
function App.status(snapshot: Snapshot): (string, Color3)
	local vouchers = 0
	for _, def in ShopConfig.VOUCHERS do
		vouchers += voucherCount(snapshot, def.key)
	end
	if vouchers > 0 then
		return `{vouchers} voucher{if vouchers == 1 then "" else "s"} to redeem`, C.good
	end
	if not ShopConfig.anyListed() then
		return "Coming soon", C.dim
	end
	if App.owns(snapshot, "vip") then
		return "VIP Founder", C.warn
	end
	return "Support the game", C.dim
end

function App.mount(parent: Frame, _nav: Kit.Nav)
	mounted = true
	local head = Kit.frame(parent, UDim2.new(1, 0, 0, 38))
	local heading = Kit.text(head, "Shop", 24, F.display, C.text)
	heading.Position = UDim2.fromOffset(0, 2)
	local scroll = Kit.scroll(parent, UDim2.new(1, 0, 1, -46), UDim2.fromOffset(0, 46))
	scroll.Name = "ShopScroll"
	local stack = Kit.stack(scroll, 12)
	Kit.padding(stack, 0, 8, 24, 0)

	local intro = Kit.para(stack, "Robux items to support the game. Prices come from Roblox, and nothing here is random.", 14, C.muted, 1)
	intro.Name = "Intro"

	local soon = Kit.card(stack, 2)
	soon.Name = "ComingSoon"
	title(soon, "Shop coming soon", 1)
	Kit.para(soon, "Robux items appear here as soon as the game owner sets them up. Until then everything in AI Empire is earned by playing.", 14, C.muted, 2)

	local empty = Kit.card(stack, 3)
	empty.Name = "NothingNow"
	title(empty, "Nothing to buy right now", 1)
	Kit.para(empty, "Prices could not be loaded from Roblox. Open the shop again in a moment.", 14, C.muted, 2)

	local order = 10
	local function nextOrder(): number
		order += 1
		return order
	end

	-- vouchers you own (always shown when you have one, even if the product is no longer sold)
	local voucherHeader = section(stack, "Your vouchers", nextOrder())
	local voucherCards: { Frame } = {}
	for _, def in ShopConfig.VOUCHERS do
		local frame, name, info, button = card(stack, nextOrder())
		frame.Name = "Voucher_" .. def.key
		info.Text = def.desc
		Kit.onClick(button, function()
			redeem(def.key, button)
		end)
		table.insert(voucherCards, frame)
		table.insert(refreshers, function(snapshot: Snapshot)
			local count = voucherCount(snapshot, def.key)
			frame.Visible = count > 0
			name.Text = if count > 1 then `{def.name} ×{count}` else def.name
			local ready = canRedeem(snapshot, def.key)
			button.Text = if ready then "Redeem" else "Available soon"
			Kit.setDisabled(button, not ready)
		end)
	end

	-- def: a ShopConfig.PRODUCTS / PASSES entry; its id is read on every refresh/click
	local function itemCard(kind: ItemKind, def: { key: string, id: number, name: string }, describe: (Snapshot) -> string): Frame
		local key = def.key
		local frame, name, info, button = card(stack, nextOrder())
		frame.Name = (if kind == "pass" then "Pass_" else "Product_") .. key
		name.Text = def.name
		local baseText = button.TextColor3
		Kit.onClick(button, function()
			if def.id > 0 and not (kind == "pass" and App.owns(State.snapshot, key)) then
				prompt(kind, def.id)
			end
		end)
		table.insert(refreshers, function(snapshot: Snapshot)
			local id = def.id
			local owned = kind == "pass" and App.owns(snapshot, key)
			local listed = id > 0 and isAvailable(snapshot, key)
			frame.Visible = id > 0 and (owned or (listed and prices[priceKey(kind, id)] ~= nil))
			info.Text = describe(snapshot)
			button.Text = if owned then "✓ Owned" else "Buy · " .. priceText(kind, id)
			Kit.setDisabled(button, owned)
			-- the disabled look fades text to ~2:1 contrast; "Owned" is the only proof of the
			-- purchase, so it stays fully readable in the success colour on a faint panel
			button.TextColor3 = if owned then C.good else baseText
			if owned then
				button.TextTransparency = 0
				button.BackgroundTransparency = 0.88
			end
		end)
		return frame
	end

	local groups: { { header: TextLabel, cards: { Frame } } } = {}
	local function group(text: string): { header: TextLabel, cards: { Frame } }
		local g = { header = section(stack, text, nextOrder()), cards = {} }
		table.insert(groups, g)
		return g
	end

	-- each header is created right before its own cards (LayoutOrder follows creation order)
	local function productGroup(text: string, kind: string)
		local g = group(text)
		for _, def in ShopConfig.PRODUCTS do
			local k = if def.kind == "cash" or def.kind == "voucher" then def.kind else "support"
			if k == kind then
				local product = def
				table.insert(g.cards, itemCard("product", def, function(snapshot: Snapshot): string
					return productText(product, snapshot)
				end))
			end
		end
	end
	productGroup("Company cash", "cash")
	productGroup("Vouchers", "voucher")
	productGroup("Support the developer", "support")
	local passes = group("Game passes")
	for _, def in ShopConfig.PASSES do
		local pass = def
		table.insert(passes.cards, itemCard("pass", def, function(_snapshot: Snapshot): string
			return passText(pass)
		end))
	end
	local thanks = Kit.para(stack, "", 14, C.good, nextOrder())
	thanks.Name = "Thanks"

	-- section headers and the empty states follow the visible cards (runs after the card refreshers)
	table.insert(refreshers, function(snapshot: Snapshot)
		local anyVoucher = false
		for _, frame in voucherCards do
			anyVoucher = anyVoucher or frame.Visible
		end
		voucherHeader.Visible = anyVoucher
		local anyItem = false
		for _, g in groups do
			local visible = false
			for _, frame in g.cards do
				visible = visible or frame.Visible
			end
			g.header.Visible = visible
			anyItem = anyItem or visible
		end
		local listed = ShopConfig.anyListed()
		soon.Visible = not listed and not anyVoucher
		local loading = false
		for _, busy in fetching do
			loading = loading or busy
		end
		empty.Visible = listed and not anyItem and not loading
		local n = tips(snapshot)
		thanks.Visible = n > 0
		thanks.Text = if n == 1 then "Thank you for your supporter tip!" else `Thank you for your {n} supporter tips!`
	end)

	State.onChange(function(_snapshot: Snapshot)
		refreshAll()
	end)
	State.onNotify(function(kind: string, payload: { [string]: any })
		if kind == "SHOP_GRANTED" then
			Toast.show("success", grantedText(payload), 5)
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
	refreshAll()
end

function App.onShow()
	if mounted then
		fetchAll()
		refreshAll()
	end
end

return App
