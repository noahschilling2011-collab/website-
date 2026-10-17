--!strict
-- Shop (shop package, SHOP_SPEC 5.1): a native Menu entry with 5 sub-tabs Home · Speed-ups · Boosts · Style · Extras
-- (Computer PAGES "shop.<tab>", each a part rendered by ShopApp.mountPart). Design px at the Menu's scale: text
-- >= 20 px (12 pt on an iPhone), targets 74 px (44 pt), effect texts wrap and are never cut.
--   * prices and icons come from Roblox (ShopCore: GetProductInfoAsync + IsForSale); a row whose price can't load is
--     hidden on live servers; Studio shows all 23 items as an owner preview ("Not set up", never prompts);
--   * live with every id at 0: "Shop coming soon" (and only the Home tab); some ids: only listed, available, ready,
--     priced items, empty tabs hidden (ShopApp.tabVisible, read by the Menu header);
--   * buy chips only open Roblox's purchase window (ShopCore.prompt); granting happens on the server (ProcessReceipt /
--     the pass event) and arrives as Notify SHOP_GRANTED; nothing is granted from PromptProductPurchaseFinished;
--   * no "featured" / "deal" / "limited" labels, no timers on offers (a running boost shows its real play time left).
-- Names tests read (ONBOARDING_SPEC B12): ComingSoon, NothingNow, Thanks, Product_<key>, Pass_<key>, Voucher_<key>,
-- ShopApp.status, ShopApp.owns.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ShopConfig = require(Shared.Config.ShopConfig)
local EmpireConfig = require(Shared.Config.EmpireConfig)
local ShopMath = require(Shared.ShopMath)
local Format = require(Shared.Format)
local Types = require(Shared.Types)

local UI = script.Parent.Parent
local Client = UI.Parent
local State = require(Client.Controllers.StateController)
local Action = require(Client.Controllers.ActionController)
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Toast = require(UI.Toast)
local ShopCore = require(UI.Shop.ShopCore)

local C = Theme.colors
local F = Theme.font

type Snapshot = Types.Snapshot
type ItemKind = "product" | "pass"
type Item = { kind: ItemKind, key: string, def: any }

local App = {}

-- Seams for the headless client test: MarketplaceService does not exist outside Roblox (forwarded to ShopCore).
function App._setDeps(patch: { [string]: any })
	ShopCore._setDeps(patch)
end

App.TABS = { "home", "speedups", "boosts", "style", "extras" }
App.TAB_LABELS = { home = "Home", speedups = "Speed-ups", boosts = "Boosts", style = "Style", extras = "Extras" }

local TAG_COLORS: { [string]: Color3 } = {
	["Speed-up"] = Color3.fromRGB(159, 211, 232),
	Boost = Color3.fromRGB(232, 180, 138),
	Cosmetic = Color3.fromRGB(176, 162, 208),
	Bundle = C.warn,
	Helper = Color3.fromRGB(134, 171, 198),
	["Company cash"] = C.good,
	["Car + perk"] = C.warn,
	["Gameplay bonus"] = C.warn,
	Tip = C.muted,
}
local ICONS: { [string]: string } = {
	eureka = "bulb", lastEpoch = "epoch", keynote = "mic", overclock = "bolt", fireworks = "fireworks", identityKit = "shield",
	serverGlow = "rack", stageLights = "spot", aiGallery = "gallery", teamHoodies = "hoodie", roboBuddy = "robot",
	styleCollection = "cards", seed = "coins", seriesA = "coins", seriesB = "coins", headhunter = "person", party = "balloon",
	tip = "heart", bigTip = "heart", vip = "crown", limo = "limo", founderSuite = "lounge", investor = "chart",
}
App.ICONS = ICONS

---------------------------------------------------------------------------------------------- state helpers

local function liveShop(snapshot: Snapshot?): any
	local live = if snapshot then snapshot.live :: any else nil
	local shop = if live then live.shop else nil
	return if typeof(shop) == "table" then shop else nil
end
local function dataShop(snapshot: Snapshot?): any
	local shop = if snapshot then (snapshot.data :: any).shop else nil
	return if typeof(shop) == "table" then shop else nil
end
local function ownFlags(snapshot: Snapshot?): any
	local shop = liveShop(snapshot)
	return if shop and typeof(shop.passes) == "table" then shop.passes else nil
end

-- owns pass `key` (its own flag or the Style Collection that includes it)
function App.owns(snapshot: Snapshot?, key: string): boolean
	return ShopMath.ownsPass(ownFlags(snapshot), key)
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
	return if snapshot then ShopMath.vouchers(snapshot.data, key) else 0
end
local function tips(snapshot: Snapshot?): number
	local shop = dataShop(snapshot)
	local n = if shop then tonumber(shop.tips) else nil
	return if n and n == n and n > 0 then math.floor(n) else 0
end

local function itemsOf(tab: string): { Item }
	local out: { Item } = {}
	for _, def in ShopConfig.PRODUCTS do
		if def.tab == tab then
			table.insert(out, { kind = "product", key = def.key, def = def })
		end
	end
	for _, def in ShopConfig.PASSES do
		if def.tab == tab then
			table.insert(out, { kind = "pass", key = def.key, def = def })
		end
	end
	return out
end
local function itemOf(key: string): Item?
	local product = ShopConfig.product(key)
	if product then
		return { kind = "product", key = key, def = product }
	end
	local pass = ShopConfig.pass(key)
	if pass then
		return { kind = "pass", key = key, def = pass }
	end
	return nil
end

-- the row of an item is shown (5.1 page states): Studio = every item (owner preview); live = listed, available,
-- ready, priced + for sale (or owned); a bundle never while a part is owned, a part never while the bundle is owned
local function itemShown(snapshot: Snapshot, item: Item, studio: boolean): boolean
	local def = item.def
	local flags = ownFlags(snapshot)
	if item.kind == "pass" then
		if def.includes then
			for _, part in def.includes do
				if typeof(flags) == "table" and flags[part] == true then
					return false
				end
			end
		else
			for _, bundle in ShopConfig.bundlesOf(item.key) do
				if typeof(flags) == "table" and flags[bundle.key] == true then
					return false
				end
			end
		end
	end
	if studio then
		return true
	end
	if def.id <= 0 or def.ready == false or not isAvailable(snapshot, item.key) then
		return false
	end
	if item.kind == "pass" and App.owns(snapshot, item.key) then
		return true
	end
	return ShopCore.priceOf(item.kind, def.id) ~= nil
end
App.itemShown = itemShown

-- a Menu sub-tab is shown: Home always; another tab when one of its items is shown (Studio: all)
function App.tabVisible(tab: string): boolean
	if tab == "home" then
		return true
	end
	local snapshot = State.snapshot
	if not snapshot then
		return false
	end
	local studio = ShopCore.isStudio()
	for _, item in itemsOf(tab) do
		if itemShown(snapshot, item, studio) then
			return true
		end
	end
	return false
end

-- Menu status (tests; the Menu rail shows no status line): vouchers first, then the shop state
function App.status(snapshot: Snapshot): (string, Color3)
	local vouchers = 0
	for _, def in ShopConfig.VOUCHERS do
		vouchers += voucherCount(snapshot, def.key)
	end
	if vouchers > 0 then
		return `{vouchers} item{if vouchers == 1 then "" else "s"} to use`, C.good
	end
	if not ShopConfig.anyListed() then
		return "Coming soon", C.dim
	end
	if App.owns(snapshot, "vip") then
		return "VIP Founder", C.warn
	end
	return "Support the game", C.dim
end

---------------------------------------------------------------------------------------------- texts

local function itemText(snapshot: Snapshot, item: Item): string
	local def = item.def
	if item.kind == "product" and def.kind == "cash" then
		return ShopMath.cashText(def, ShopMath.office(snapshot.data))
	end
	return def.desc
end

-- the extra line under an item's text (honest state: limits, why START is off, what an owned item does)
local function itemNote(snapshot: Snapshot, item: Item, studio: boolean): (string?, Color3?)
	local data: any = snapshot.data
	local key = item.key
	local now = ShopCore.serverNow(snapshot)
	if studio and item.def.ready == false then
		return "Not in the game yet: create this pass on the Creator Hub only when it ships.", C.dim
	end
	if item.kind == "product" and item.def.kind == "cash" and not ShopMath.packOpen(data, key) then
		-- S1 credits (fix round 1): an extra one bought in this office waits for the next office (Your items says so)
		local credit = ShopMath.packCredit(data, key)
		if credit > 0 then
			return `Bought for this office ✓ · {credit} more saved for your next office{if credit > 1 then "s" else ""}`, C.good
		end
		return "Bought for this office ✓", C.good
	end
	if key == "keynote" and not ShopMath.liveModel(data) then
		return "No live AI right now", C.warn
	end
	if key == "overclock" and data.training and ShopMath.atTrainingMinimum(data) then
		return "This run is already at the 12 s minimum: Overclock would not speed it up.", C.warn
	end
	if (key == "keynote" or key == "overclock" or key == "lastEpoch") and ShopMath.dailyUsed(data, key, now) >= (ShopConfig.DAILY[key] or math.huge) then
		return `That's today's limit ({ShopConfig.DAILY[key]} a day).`, C.muted
	end
	if key == "eureka" and voucherCount(snapshot, "eureka") >= ShopMath.eurekaUsesLeft(data) and voucherCount(snapshot, "eureka") > 0 then
		return "You hold a Eureka for every research step left.", C.muted
	end
	if key == "identityKit" and App.owns(snapshot, key) then
		return "Your Kit colours and logos are unlocked in Team → Settings.", C.good
	end
	if key == "vip" and App.owns(snapshot, key) then
		return "Your gold VIP tag is on.", C.good
	end
	return nil, nil
end

---------------------------------------------------------------------------------------------- building blocks

local refreshers: { (Snapshot) -> () } = {}
local navRef: any = nil
local mountedParts: { [string]: Frame } = {}

local function shownOnScreen(inst: Instance): boolean
	local node: Instance? = inst
	while node do
		if node:IsA("GuiObject") and not (node :: GuiObject).Visible then
			return false
		end
		if node:IsA("LayerCollector") then
			return true
		end
		node = node.Parent
	end
	return true
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

local function para(parent: Instance, text: string, size: number, color: Color3, order: number): TextLabel
	local label = Kit.para(parent, text, size, color, order)
	label.TextTruncate = Enum.TextTruncate.None
	return label
end

local function sectionHead(parent: Instance, title: string, hint: string?, order: number): Frame
	local row = Kit.frame(parent, UDim2.new(1, 0, 0, 40))
	row.Name = "Section"
	row.LayoutOrder = order
	local list = Kit.list(row, 14, true)
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	local t = Kit.text(row, string.upper(title), 22, F.bold, C.muted)
	t.LayoutOrder = 1
	if hint then
		local h = Kit.text(row, hint, 22, F.medium, C.dim)
		h.LayoutOrder = 2
	end
	return row
end

local function iconTile(parent: Instance, key: string, size: number, tint: Color3?): (Frame, ImageLabel)
	local tile = Kit.frame(parent, UDim2.fromOffset(size, size))
	tile.Name = "Icon"
	tile.BackgroundTransparency = 0
	tile.BackgroundColor3 = C.raised
	Kit.corner(tile, math.floor(size / 6))
	Kit.stroke(tile, 0.88)
	local icon = Kit.icon(tile, ICONS[key] or "shop", math.floor(size * 0.52))
	icon.frame.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.frame.Position = UDim2.fromScale(0.5, 0.5)
	icon.setColor(tint or C.warn)
	-- the product's own icon from GetProductInfoAsync (IconImageAssetId) when the owner set one (ONBOARDING C2)
	local image = Instance.new("ImageLabel")
	image.Name = "RobloxIcon"
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Visible = false
	image.Parent = tile
	Kit.corner(image, math.floor(size / 6))
	return tile, image
end

local function tagChip(parent: Instance, tag: string, order: number): TextLabel
	local color = TAG_COLORS[tag] or C.muted
	local chip = Kit.text(parent, tag, 20, F.bold, color)
	chip.Name = "Tag"
	chip.LayoutOrder = order
	chip.BackgroundColor3 = color
	chip.BackgroundTransparency = 0.84
	Kit.corner(chip, 8)
	Kit.padding(chip, 2, 10, 2, 10)
	return chip
end

local function priceChip(parent: Instance, width: number?): TextButton
	local b = Kit.button(parent, "", "secondary", UDim2.fromOffset(width or 170, 74))
	b.Name = "Price"
	b.TextSize = 24
	b.Selectable = true
	local stroke = b:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke:Destroy()
	end
	Kit.stroke(b, 0.55, Theme.accent, 2)
	return b
end

-- sets a price chip: owned / Studio "Not set up" / loaded price / "…" loading; returns whether it is visible
local function paintChip(chip: TextButton, snapshot: Snapshot, item: Item, studio: boolean, allowed: boolean): boolean
	local def = item.def
	local owned = item.kind == "pass" and App.owns(snapshot, item.key)
	chip.TextTransparency = 0
	if owned then
		chip.Text = "✓ Owned"
		chip.TextColor3 = C.good
		Kit.setDisabled(chip, true)
		chip.TextTransparency = 0
		chip.BackgroundTransparency = 0.88
		chip.Visible = true
		return true
	end
	if not allowed then
		chip.Visible = false
		return false
	end
	if def.id <= 0 then
		chip.Visible = studio
		chip.Text = "Not set up"
		chip.TextColor3 = C.dim
		Kit.setDisabled(chip, true)
		chip.TextTransparency = 0
		return studio
	end
	local price = ShopCore.priceOf(item.kind, def.id)
	chip.Visible = true
	chip.TextColor3 = C.text
	if price then
		chip.Text = ShopCore.priceText(price)
		Kit.setDisabled(chip, false)
	else
		chip.Text = "…"
		Kit.setDisabled(chip, true)
	end
	return true
end

local function onChipClick(item: Item)
	local snapshot = State.snapshot
	if not snapshot then
		return
	end
	local def = item.def
	if def.id <= 0 or (item.kind == "pass" and App.owns(snapshot, item.key)) then
		return
	end
	ShopCore.prompt(item.kind, def.id)
end

-- One catalogue row (5.1 "Row"): icon 94 · name 28 + tag chip 20 · effect text 22 (wraps, never cut) · an optional
-- note · right: an optional primary 170 x 74 (START / ADD 15 MIN; CHANGE LOOK › 220 wide) and the price chip 170 x 74.
type RowRefs = { frame: Frame, refresh: (Snapshot) -> () }
local function itemRow(parent: Instance, item: Item, order: number, studio: () -> boolean): RowRefs
	local def = item.def
	local frame = Kit.frame(parent, UDim2.fromScale(1, 0))
	frame.Name = (if item.kind == "pass" then "Pass_" else "Product_") .. item.key
	frame.LayoutOrder = order
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3 = C.panel2
	Kit.corner(frame, 16)
	Kit.stroke(frame, 0.92)
	local minSize = Instance.new("UISizeConstraint")
	minSize.MinSize = Vector2.new(0, 126)
	minSize.Parent = frame
	local pad = Kit.padding(frame, 16, 16, 16, 16)
	local _ = pad
	local icon, image = iconTile(frame, item.key, 94, TAG_COLORS[def.tag])
	icon.Position = UDim2.fromOffset(0, 0)
	local right = Kit.frame(frame, UDim2.fromOffset(0, 74), UDim2.new(1, 0, 0, 10))
	right.Name = "Right"
	right.AnchorPoint = Vector2.new(1, 0)
	right.AutomaticSize = Enum.AutomaticSize.X
	local rlist = Kit.list(right, 12, true)
	rlist.HorizontalAlignment = Enum.HorizontalAlignment.Right
	local primary = Kit.button(right, "", "primary", UDim2.fromOffset(170, 74))
	primary.Name = "Use"
	primary.TextSize = 24
	primary.LayoutOrder = 1
	primary.Visible = false
	primary.Selectable = true
	local chip = priceChip(right)
	chip.LayoutOrder = 2
	local body = Kit.frame(frame, UDim2.new(1, -110, 0, 0), UDim2.fromOffset(110, 0))
	body.Name = "Body"
	body.AutomaticSize = Enum.AutomaticSize.Y
	Kit.list(body, 6)
	local head = Kit.frame(body, UDim2.new(1, 0, 0, 36))
	head.LayoutOrder = 1
	local hlist = Kit.list(head, 12, true)
	hlist.VerticalAlignment = Enum.VerticalAlignment.Center
	local name = Kit.text(head, def.name, 28, F.bold, C.text)
	name.Name = "Name"
	name.LayoutOrder = 1
	local count = Kit.text(head, "", 24, F.bold, C.good)
	count.Name = "Count"
	count.LayoutOrder = 2
	tagChip(head, def.tag, 3)
	local text = para(body, def.desc, 22, C.muted, 2)
	text.Name = "Text"
	local note = para(body, "", 20, C.muted, 3)
	note.Name = "Note"
	note.Font = F.bold
	local primaryAction: (() -> ())? = nil
	Kit.onClick(chip, function()
		onChipClick(item)
	end)
	Kit.onClick(primary, function()
		if primaryAction then
			primaryAction()
		end
	end)
	local function refresh(snapshot: Snapshot)
		local isStudio = studio()
		frame.Visible = itemShown(snapshot, item, isStudio)
		if not frame.Visible then
			return
		end
		local data: any = snapshot.data
		local now = ShopCore.serverNow(snapshot)
		text.Text = itemText(snapshot, item)
		local n, nColor = itemNote(snapshot, item, isStudio)
		note.Text = n or ""
		note.Visible = n ~= nil
		note.TextColor3 = nColor or C.muted
		local held = if def.voucher then voucherCount(snapshot, def.voucher) else 0
		count.Text = if held > 0 then `×{held}` else ""
		count.Visible = held > 0
		local iconId = if def.id > 0 then ShopCore.iconOf(item.kind, def.id) else nil
		image.Visible = iconId ~= nil
		if iconId then
			image.Image = "rbxassetid://" .. tostring(iconId)
		end
		-- the buy guard (4.1): never sell more than can be used, one cash pack of each size per office
		local allowed = ShopMath.buyAllowed(data, snapshot.live, item.key, now)
		paintChip(chip, snapshot, item, isStudio, allowed)
		-- the primary: START / ADD 15 MIN for a held boost, CHANGE LOOK › for an owned Identity Kit
		primaryAction = nil
		local label: string? = nil
		local enabled = true
		if (item.key == "keynote" or item.key == "overclock") and held > 0 then
			local running = ShopMath.boostLeft(data, item.key, ShopCore.playSeconds(snapshot)) > 0
			label = if running then "ADD 15 MIN" else "START"
			enabled = ShopMath.boostCheck(data, item.key, now, ShopCore.playSeconds(snapshot))
			local key = item.key
			primaryAction = function()
				ShopCore.use(key, nil)
			end
		elseif item.key == "identityKit" and App.owns(snapshot, "identityKit") then
			label = "CHANGE LOOK ›"
			primaryAction = function()
				if navRef then
					navRef.route("open:empire/settings")
				end
			end
		end
		primary.Visible = label ~= nil
		primary.Text = label or ""
		-- a long label (CHANGE LOOK ›) gets a wider button instead of a smaller text, so it never spills out
		local long = label ~= nil and #label > 10
		local pw = if long then 220 else 170
		primary.TextSize = if long then 22 else 24
		primary.Size = UDim2.fromOffset(pw, 74)
		Kit.setDisabled(primary, not enabled)
		-- the text column ends left of the buttons
		local rw = (if primary.Visible then pw + 12 else 0) + (if chip.Visible then 170 else 0)
		body.Size = UDim2.new(1, -110 - rw - (if rw > 0 then 16 else 0), 0, 0)
	end
	table.insert(refreshers, refresh)
	return { frame = frame, refresh = refresh }
end

---------------------------------------------------------------------------------------------- tabs

local function studioFn(): boolean
	return ShopCore.isStudio()
end

local function previewBanner(parent: Instance, order: number): Frame
	local banner = Kit.frame(parent, UDim2.fromScale(1, 0))
	banner.Name = "OwnerPreview"
	banner.LayoutOrder = order
	banner.AutomaticSize = Enum.AutomaticSize.Y
	banner.BackgroundTransparency = 0.88
	banner.BackgroundColor3 = C.warn
	Kit.corner(banner, 12)
	Kit.stroke(banner, 0.2, C.warn, 2)
	Kit.padding(banner, 12, 16, 12, 16)
	local t = para(banner, "OWNER PREVIEW · Studio only. Items without an id show 'Not set up'. Nothing can be bought here.", 22, C.warn, 1)
	t.Font = F.bold
	table.insert(refreshers, function(_snapshot: Snapshot)
		banner.Visible = ShopCore.isStudio()
	end)
	return banner
end

local function intro(parent: Instance, text: string, order: number): TextLabel
	local label = para(parent, text, 22, C.muted, order)
	label.Name = "Intro"
	return label
end

local function buildRows(parent: Instance, keys: { string }, order: number): number
	for _, key in keys do
		local item = itemOf(key)
		if item then
			order += 1
			itemRow(parent, item, order, studioFn)
		end
	end
	return order
end

-- a section header that hides itself when none of its rows is visible
local function section(parent: Instance, title: string, hint: string?, keys: { string }, order: number): number
	local head = sectionHead(parent, title, hint, order)
	local rows: { Frame } = {}
	for _, key in keys do
		local item = itemOf(key)
		if item then
			order += 1
			table.insert(rows, itemRow(parent, item, order, studioFn).frame)
		end
	end
	table.insert(refreshers, function(_snapshot: Snapshot)
		local any = false
		for _, f in rows do
			any = any or f.Visible
		end
		head.Visible = any
	end)
	return order + 1
end

type Seg = { key: string, name: string, line: string, button: string?, run: (() -> ())?, enabled: boolean, frameName: string? }
-- YOUR ITEMS (5.1): held vouchers and running boosts as compact segments (owned passes show in their tab)
local function yourItems(parent: Instance, order: number)
	local box = Kit.frame(parent, UDim2.fromScale(1, 0))
	box.Name = "YourItems"
	box.LayoutOrder = order
	box.AutomaticSize = Enum.AutomaticSize.Y
	Kit.list(box, 10)
	sectionHead(box, "Your items", nil, 1)
	local grid = Kit.frame(box, UDim2.fromScale(1, 0))
	grid.Name = "Segments"
	grid.LayoutOrder = 2
	grid.AutomaticSize = Enum.AutomaticSize.Y
	Kit.list(grid, 10)
	local signature = ""
	table.insert(refreshers, function(snapshot: Snapshot)
		local data: any = snapshot.data
		local segs: { Seg } = {}
		local play = ShopCore.playSeconds(snapshot)
		local now = ShopCore.serverNow(snapshot)
		for _, def in ShopConfig.VOUCHERS do
			local key = def.key
			local n = voucherCount(snapshot, key)
			local running = (key == "keynote" or key == "overclock") and ShopMath.boostLeft(data, key, play) > 0
			if n > 0 or running then
				local name = ShopCore.itemName(key) .. (if n > 1 then ` ×{n}` elseif n == 1 then " ×1" else "")
				if key == "eureka" then
					if ShopMath.eurekaUsesLeft(data) <= 0 then
						table.insert(segs, ({ key = key, name = name, line = "Nothing left to research. Your Eureka can't be used.", enabled = false } :: Seg))
					else
						table.insert(segs, ({ key = key, name = name, line = "Use it in Lab → Research", button = "OPEN LAB ›", enabled = true,
							run = function() if navRef then navRef.route("open:lab/research") end end } :: Seg))
					end
				elseif key == "lastEpoch" then
					table.insert(segs, ({ key = key, name = name, line = "Use it in the training view", button = "OPEN LAB ›", enabled = true,
						run = function() if navRef then navRef.route("lab_train") end end } :: Seg))
				elseif key == "keynote" or key == "overclock" then
					local left = ShopMath.boostLeft(data, key, play)
					local effect = if key == "keynote" then "+20 %" else "×1.5"
					local line = if left > 0 then `{effect} · {ShopMath.clock(left)} left (play time)` else "Start it in Boosts"
					table.insert(segs, ({ key = key, name = if n > 0 then name else ShopCore.itemName(key), line = line, button = "BOOSTS ›", enabled = true,
						run = function() if navRef then navRef.route("page:shop.boosts") end end } :: Seg))
				else
					local line = def.desc
					if key == "headhunter" then
						local role = EmpireConfig.find(EmpireConfig.ROLES, ShopMath.headhuntRole(data.empire))
						line = `Finds a skill-4 {if role then role.name else "applicant"} (your smallest team)`
					end
					local ready = canRedeem(snapshot, key)
					table.insert(segs, ({ key = key, name = name, line = line, button = if ready then "REDEEM" else "LATER", enabled = ready,
						run = function() ShopCore.redeem(key, nil) end } :: Seg))
				end
			end
		end
		-- S1 credits (fix round 1): a cash pack bought again in an office that already had one is paid at the next office
		local office = ShopMath.office(data)
		local last = office >= #EmpireConfig.OFFICES
		for _, def in ShopConfig.PRODUCTS do
			local n = if def.kind == "cash" then ShopMath.packCredit(data, def.key) else 0
			if n > 0 then
				local nextOffice = EmpireConfig.OFFICES[office + 1]
				table.insert(segs, ({ key = def.key, frameName = "Credit_" .. def.key, name = `{def.name} ×{n}`,
					line = if last then "Saved, but this is your last office: it can't be paid out." else `Paid when you move to {if nextOffice then nextOffice.name else "your next office"}`,
					button = if last then nil else "OFFICE ›", enabled = not last,
					run = function() if navRef then navRef.route("open:empire/office") end end } :: Seg))
			end
		end
		box.Visible = #segs > 0
		local sig = ""
		for _, sgm in segs do
			sig ..= sgm.key .. "|" .. sgm.name .. "|" .. sgm.line .. "|" .. tostring(sgm.button) .. tostring(sgm.enabled) .. ";"
		end
		if sig == signature then
			return
		end
		signature = sig
		for _, child in grid:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local rowFrame: Frame? = nil
		for i, sgm in segs do
			if i % 2 == 1 then
				local r = Kit.frame(grid, UDim2.new(1, 0, 0, 98))
				r.LayoutOrder = i
				Kit.list(r, 12, true)
				rowFrame = r
			end
			local f = Kit.frame(rowFrame, UDim2.new(0.5, -6, 1, 0))
			f.Name = sgm.frameName or ("Voucher_" .. sgm.key)
			f.LayoutOrder = i
			f.BackgroundTransparency = 0
			f.BackgroundColor3 = C.panel2
			Kit.corner(f, 14)
			Kit.stroke(f, 0.9)
			local tile = iconTile(f, sgm.key, 70)
			tile.Position = UDim2.fromOffset(14, 14)
			local bw = if sgm.button then 170 else 0
			local nameLabel = Kit.text(f, sgm.name, 24, F.bold, C.text)
			nameLabel.Name = "Name"
			nameLabel.AutomaticSize = Enum.AutomaticSize.None
			nameLabel.Size = UDim2.new(1, -(98 + bw + 24), 0, 30)
			nameLabel.Position = UDim2.fromOffset(98, 12)
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			local lineLabel = Kit.text(f, sgm.line, 20, F.medium, C.muted)
			lineLabel.Name = "Line"
			lineLabel.AutomaticSize = Enum.AutomaticSize.None
			lineLabel.TextWrapped = true
			lineLabel.TextYAlignment = Enum.TextYAlignment.Top
			lineLabel.Size = UDim2.new(1, -(98 + bw + 24), 0, 50)
			lineLabel.Position = UDim2.fromOffset(98, 44)
			if sgm.button then
				local b = Kit.button(f, sgm.button, "secondary", UDim2.fromOffset(170, 74))
				b.Name = "Go"
				b.TextSize = 22
				b.AnchorPoint = Vector2.new(1, 0.5)
				b.Position = UDim2.new(1, -12, 0.5, 0)
				b.Selectable = true
				Kit.setDisabled(b, not sgm.enabled)
				local run = sgm.run
				Kit.onClick(b, function()
					if run then
						run()
					end
				end)
			end
		end
		local _ = now
	end)
end

-- the featured tile (5.1): the first cosmetic of ShopConfig.FEATURED that can be bought right now; no label
local function featured(parent: Instance, order: number)
	local tile = Kit.frame(parent, UDim2.fromScale(1, 0))
	tile.Name = "Featured"
	tile.LayoutOrder = order
	tile.AutomaticSize = Enum.AutomaticSize.Y
	tile.BackgroundTransparency = 0
	tile.BackgroundColor3 = C.white -- the UIGradient multiplies the background: white = the gradient's own colours
	Kit.corner(tile, 18)
	Kit.stroke(tile, 0.5, C.warn, 1)
	Kit.gradient(tile, Color3.fromRGB(66, 56, 36), Color3.fromRGB(34, 40, 39), 0)
	Kit.padding(tile, 18, 18, 18, 18)
	local minSize = Instance.new("UISizeConstraint")
	minSize.MinSize = Vector2.new(0, 150)
	minSize.Parent = tile
	local iconHolder = Kit.frame(tile, UDim2.fromOffset(114, 114))
	iconHolder.Name = "IconHolder"
	local body = Kit.frame(tile, UDim2.new(1, -330, 0, 0), UDim2.fromOffset(132, 0))
	body.Name = "Body"
	body.AutomaticSize = Enum.AutomaticSize.Y
	Kit.list(body, 6)
	local head = Kit.frame(body, UDim2.new(1, 0, 0, 40))
	head.LayoutOrder = 1
	local hlist = Kit.list(head, 12, true)
	hlist.VerticalAlignment = Enum.VerticalAlignment.Center
	local name = Kit.text(head, "", 32, F.display, C.text)
	name.Name = "Name"
	name.LayoutOrder = 1
	local tagHolder = Kit.frame(head, UDim2.fromOffset(0, 32))
	tagHolder.AutomaticSize = Enum.AutomaticSize.X
	tagHolder.LayoutOrder = 2
	local text = para(body, "", 22, C.muted, 2)
	text.Name = "Text"
	local parts = Kit.frame(body, UDim2.new(1, 0, 0, 40))
	parts.Name = "Parts"
	parts.LayoutOrder = 3
	Kit.list(parts, 10, true)
	local chip = priceChip(tile, 190)
	chip.AnchorPoint = Vector2.new(1, 0.5)
	chip.Position = UDim2.new(1, 0, 0.5, 0)
	local current: Item? = nil
	Kit.onClick(chip, function()
		local item = current
		if item then
			onChipClick(item)
		end
	end)
	local shownKey = ""
	table.insert(refreshers, function(snapshot: Snapshot)
		local studio = ShopCore.isStudio()
		local pick: Item? = nil
		for _, key in ShopConfig.FEATURED do
			local item = itemOf(key)
			if item and item.def.ready ~= false and itemShown(snapshot, item, studio) and not App.owns(snapshot, key)
				and ShopMath.buyAllowed(snapshot.data, snapshot.live, key, ShopCore.serverNow(snapshot)) then
				pick = item
				break
			end
		end
		current = pick
		tile.Visible = pick ~= nil
		if not pick then
			return
		end
		if shownKey ~= pick.key then
			shownKey = pick.key
			for _, child in iconHolder:GetChildren() do
				child:Destroy()
			end
			local icon = iconTile(iconHolder, pick.key, 114, C.warn)
			icon.BackgroundColor3 = Color3.fromRGB(70, 60, 40)
			for _, child in tagHolder:GetChildren() do
				child:Destroy()
			end
			tagChip(tagHolder, pick.def.tag, 1)
			for _, child in parts:GetChildren() do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
			local includes = pick.def.includes
			parts.Visible = includes ~= nil
			for i, partKey in includes or {} do
				local p = Kit.frame(parts, UDim2.fromOffset(0, 40))
				p.AutomaticSize = Enum.AutomaticSize.X
				p.LayoutOrder = i
				p.BackgroundTransparency = 0
				p.BackgroundColor3 = C.raised
				Kit.corner(p, 10)
				Kit.padding(p, 0, 12, 0, 8)
				local l = Kit.list(p, 8, true)
				l.VerticalAlignment = Enum.VerticalAlignment.Center
				local ic = Kit.icon(p, ICONS[partKey] or "shop", 24)
				ic.setColor(C.warn)
				ic.frame.LayoutOrder = 1
				local t = Kit.text(p, ShopCore.itemName(partKey), 22, F.bold, C.text)
				t.LayoutOrder = 2
			end
		end
		name.Text = pick.def.name
		text.Text = pick.def.desc
		paintChip(chip, snapshot, pick, studio, true)
	end)
end

-- CATEGORIES (5.1): 4 tiles, the whole tile is the button; count chip = items shown in that tab
local CATEGORY_LINES = {
	speedups = "Finish research or training now",
	boosts = "15 min of extra income or speed",
	style = "Colours, lights and fun. Looks only.",
	extras = "Perks, company cash and tips",
}
local CATEGORY_ICONS = { speedups = "bulb", boosts = "bolt", style = "cards", extras = "coins" }
local function categories(parent: Instance, order: number)
	local box = Kit.frame(parent, UDim2.fromScale(1, 0))
	box.Name = "Categories"
	box.LayoutOrder = order
	box.AutomaticSize = Enum.AutomaticSize.Y
	Kit.list(box, 10)
	sectionHead(box, "Categories", nil, 1)
	local row = Kit.frame(box, UDim2.new(1, 0, 0, 170))
	row.LayoutOrder = 2
	Kit.list(row, 12, true)
	local tiles: { [string]: { button: TextButton, count: TextLabel } } = {}
	for i, tab in ShopConfig.TABS do
		local b = Instance.new("TextButton")
		b.Name = "Category_" .. tab
		b.Text = ""
		b.AutoButtonColor = false
		b.BorderSizePixel = 0
		b.BackgroundColor3 = C.panel2
		b.Size = UDim2.new(0.25, -9, 1, 0)
		b.LayoutOrder = i
		b.Selectable = true
		b.Parent = row
		Kit.corner(b, 16)
		Kit.stroke(b, 0.9)
		Kit.padding(b, 14, 16, 14, 16)
		local ic = Kit.icon(b, CATEGORY_ICONS[tab], 40)
		ic.setColor(C.warn)
		local count = Kit.text(b, "", 20, F.bold, C.muted)
		count.Name = "Count"
		count.AnchorPoint = Vector2.new(1, 0)
		count.Position = UDim2.fromScale(1, 0)
		count.BackgroundTransparency = 0
		count.BackgroundColor3 = C.raised
		Kit.corner(count, 8)
		Kit.padding(count, 2, 10, 2, 10)
		local title = Kit.text(b, App.TAB_LABELS[tab], 28, F.display, C.text)
		title.Position = UDim2.fromOffset(0, 50)
		local line = Kit.text(b, CATEGORY_LINES[tab], 20, F.medium, C.muted)
		line.AutomaticSize = Enum.AutomaticSize.None
		line.TextWrapped = true
		line.TextYAlignment = Enum.TextYAlignment.Top
		line.Size = UDim2.new(1, -20, 0, 50)
		line.Position = UDim2.fromOffset(0, 88)
		local cue = Kit.text(b, "›", 28, F.bold, Theme.accent)
		cue.AnchorPoint = Vector2.new(1, 1)
		cue.Position = UDim2.fromScale(1, 1)
		Kit.onClick(b, function()
			if navRef then
				navRef.route("page:shop." .. tab)
			end
		end)
		tiles[tab] = { button = b, count = count }
	end
	table.insert(refreshers, function(snapshot: Snapshot)
		local studio = ShopCore.isStudio()
		local anyTile = false
		for tab, refs in tiles do
			local n = 0
			for _, item in itemsOf(tab) do
				if itemShown(snapshot, item, studio) then
					n += 1
				end
			end
			refs.button.Visible = n > 0
			refs.count.Text = `{n} item{if n == 1 then "" else "s"}`
			anyTile = anyTile or n > 0
		end
		box.Visible = anyTile
	end)
end

local function buildHome(stack: Frame)
	intro(stack, "Optional extras for Robux. You can reach every office and every client without them.", 1)
	previewBanner(stack, 2)
	local soon = Kit.card(stack, 3)
	soon.Name = "ComingSoon"
	local soonTitle = para(soon, "Shop coming soon", 28, C.text, 1)
	soonTitle.Font = F.bold
	para(soon, "Nothing to buy yet. Every office and every client can be reached without the shop.", 22, C.muted, 2)
	local empty = Kit.card(stack, 4)
	empty.Name = "NothingNow"
	local emptyTitle = para(empty, "Nothing to buy right now", 28, C.text, 1)
	emptyTitle.Font = F.bold
	para(empty, "Some items couldn't load from Roblox. Open the shop again in a moment.", 22, C.muted, 2)
	local loading = para(stack, "Loading prices from Roblox…", 22, C.dim, 5)
	loading.Name = "Loading"
	yourItems(stack, 6)
	featured(stack, 7)
	categories(stack, 8)
	local thanks = para(stack, "", 22, C.good, 9)
	thanks.Name = "Thanks"
	table.insert(refreshers, function(snapshot: Snapshot)
		local studio = ShopCore.isStudio()
		local listed = ShopConfig.anyListed()
		local anyItem = false
		for _, tab in ShopConfig.TABS do
			for _, item in itemsOf(tab) do
				anyItem = anyItem or itemShown(snapshot, item, studio)
			end
		end
		local anyVoucher = false
		for _, def in ShopConfig.VOUCHERS do
			anyVoucher = anyVoucher or voucherCount(snapshot, def.key) > 0
		end
		soon.Visible = not listed and not studio and not anyVoucher
		local fetchingNow = ShopCore.isFetching()
		empty.Visible = listed and not studio and not anyItem and not fetchingNow
		loading.Visible = listed and not studio and fetchingNow
		local n = tips(snapshot)
		thanks.Visible = n > 0
		thanks.Text = if n == 1 then "Thank you for your supporter tip!" else `Thank you for your {n} supporter tips!`
	end)
end

local function buildSpeedups(stack: Frame)
	intro(stack, "Each one finishes one job right now. You keep it until you use it.", 1)
	previewBanner(stack, 2)
	buildRows(stack, { "eureka", "lastEpoch" }, 2)
	local info = Kit.card(stack, 10)
	info.Name = "WhereToUse"
	local text = para(info, "", 22, C.muted, 1)
	table.insert(refreshers, function(snapshot: Snapshot)
		local n = ShopMath.eurekaUsesLeft(snapshot.data)
		text.Text = "Where to use them: Eureka in Lab → Research, on the Lab level card or at a \"Needs research\" size in the Model Studio. Last Epoch in the training view. "
			.. `{n} research step{if n == 1 then " is" else "s are"} left in your save, so you can still use up to {n} Eureka{if n == 1 then "" else "s"}.`
	end)
end

local function buildBoosts(stack: Frame)
	intro(stack, "Boosts count play time only and never affect other players. Up to 4 starts of each a day.", 1)
	previewBanner(stack, 2)
	for i, key in { "keynote", "overclock" } do
		local card = Kit.frame(stack, UDim2.new(1, 0, 0, 86))
		card.Name = "Running_" .. key
		card.LayoutOrder = 2 + i
		card.BackgroundTransparency = 0
		card.BackgroundColor3 = Color3.fromRGB(44, 38, 32)
		Kit.corner(card, 16)
		Kit.stroke(card, 0.4, TAG_COLORS.Boost, 2)
		local tile = iconTile(card, key, 62, TAG_COLORS.Boost)
		tile.Position = UDim2.fromOffset(12, 12)
		local title = Kit.text(card, `{ShopCore.itemName(key)} is on`, 26, F.bold, C.text)
		title.Position = UDim2.fromOffset(90, 6)
		local line = Kit.text(card, "", 22, F.medium, C.text)
		line.Position = UDim2.fromOffset(90, 36)
		local bar = Kit.bar(card, 8, 0, TAG_COLORS.Boost)
		bar.frame.Position = UDim2.new(0, 90, 1, -16)
		bar.frame.Size = UDim2.new(1, -110, 0, 8)
		table.insert(refreshers, function(snapshot: Snapshot)
			local data: any = snapshot.data
			local left = ShopMath.boostLeft(data, key, ShopCore.playSeconds(snapshot))
			card.Visible = left > 0
			if left > 0 then
				local effect = if key == "keynote" then "+20 % app and API income" else "training 1.5× as fast"
				local used = ShopMath.dailyUsed(data, key, ShopCore.serverNow(snapshot))
				line.Text = `{effect} · {ShopMath.clock(left)} left (play time) · {used} of {ShopConfig.DAILY[key]} today`
				-- fix round 1 (review): measured against the 15-min blocks this run has (a fresh boost is a full bar, not
				-- 25 % of the 60 min maximum, which read as "almost used up")
				local block = ShopConfig.BOOSTS[key].seconds
				bar.set(math.clamp(left / (math.max(1, math.ceil(left / block - 1e-6)) * block), 0, 1))
			end
		end)
	end
	buildRows(stack, { "keynote", "overclock" }, 6)
end

local function buildStyle(stack: Frame)
	intro(stack, "Looks only. Nothing here changes your income or other players.", 1)
	previewBanner(stack, 2)
	local order = buildRows(stack, { "styleCollection" }, 2)
	order = section(stack, "Company look", "buy once, keep", { "identityKit", "serverGlow", "aiGallery", "teamHoodies" }, order + 1)
	order = section(stack, "Shows", nil, { "stageLights", "fireworks", "party" }, order + 1)
	section(stack, "Founder", nil, { "vip", "founderSuite", "roboBuddy" }, order + 1)
end

local function buildExtras(stack: Frame)
	previewBanner(stack, 1)
	local order = section(stack, "Perks", nil, { "limo", "investor" }, 2)
	order = section(stack, "Helper", nil, { "headhunter" }, order + 1)
	order = section(stack, "Company cash", "one of each per office · grows with your office", { "seed", "seriesA", "seriesB" }, order + 1)
	section(stack, "Support the developer", nil, { "tip", "bigTip" }, order + 1)
end

local BUILDERS: { [string]: (Frame) -> () } = { home = buildHome, speedups = buildSpeedups, boosts = buildBoosts, style = buildStyle, extras = buildExtras }

local bound = false
local function bind()
	if bound then
		return
	end
	bound = true
	ShopCore.mount()
	State.onChange(function(_snapshot: Snapshot)
		for _, frame in mountedParts do
			if shownOnScreen(frame) then
				refreshAll()
				return
			end
		end
	end)
	ShopCore.onChange(refreshAll)
end

-- A Menu page part (Computer PAGES "shop.<tab>"): built once, refreshed while shown
function App.mountPart(frame: Frame, id: string, nav: any): { show: () -> () }
	local builder = BUILDERS[id]
	assert(builder, "unknown ShopApp part " .. tostring(id))
	navRef = navRef or nav
	bind()
	frame.AutomaticSize = Enum.AutomaticSize.Y
	local stack = Kit.stack(frame, 14)
	stack.Name = "ShopTab_" .. id
	builder(stack)
	mountedParts[id] = frame
	refreshAll()
	return {
		show = function()
			ShopCore.fetchAll()
			refreshAll()
		end,
	}
end

-- Old single-page API (kept for callers that mount the whole shop into one frame: every tab in one scroll)
function App.mount(parent: Frame, nav: any)
	local scroll = Kit.scroll(parent)
	scroll.Name = "ShopScroll"
	Kit.padding(scroll, 2, 14, 24, 2)
	Kit.list(scroll, 18)
	for i, tab in App.TABS do
		local holder = Kit.frame(scroll, UDim2.fromScale(1, 0))
		holder.LayoutOrder = i
		App.mountPart(holder, tab, nav)
	end
end

function App.onShow()
	ShopCore.fetchAll()
	refreshAll()
end

local _ = Players
local _2 = Format
local _3 = Action
local _4 = Toast
return App
