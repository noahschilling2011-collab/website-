--!strict
-- Trainingsdaten: Inventar pro Typ, kostenloses Scrapen, Datenmarkt.
-- Jede Paket-Karte zeigt, wie viel Overall das Paket für die im Lab gewählte Größe bringen würde.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local DataConfig = require(Shared.Config.DataConfig)
local ModelConfig = require(Shared.Config.ModelConfig)
local ModelMath = require(Shared.ModelMath)
local EmpireMath = require(Shared.EmpireMath)
local Format = require(Shared.Format)
local Types = require(Shared.Types)

local UI = script.Parent.Parent
local Client = UI.Parent
local StateController = require(Client.Controllers.StateController)
local ActionController = require(Client.Controllers.ActionController)
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Toast = require(UI.Toast)

local C = Theme.colors
local F = Theme.font

type Snapshot = Types.Snapshot

local TYPE_COLORS: { [string]: Color3 } = {
	general = Color3.fromRGB(96, 165, 250),
	code = Color3.fromRGB(52, 211, 153),
	math = Color3.fromRGB(251, 191, 36),
}

local DataApp = {}

local root: Frame? = nil
local refresh: (Snapshot) -> () = function(_snapshot: Snapshot) end

local function typeLabel(id: string): string
	for _, dataType in DataConfig.TYPES do
		if dataType.id == id then
			return dataType.label
		end
	end
	return id
end

function DataApp.mount(parent: Frame, navigation: Kit.Nav)
	root = parent

	local scroll = Kit.scroll(parent)
	Kit.padding(scroll, 2, 14, 20, 2)
	Kit.list(scroll, 14)

	Kit.heading(scroll, "TRAINING DATA", "More data makes models smarter, better data makes them reliable. Data is not used up by training.", 1)

	-- Inventar
	local inventory = Kit.card(scroll, 2, 10)
	local invHead = Kit.frame(inventory, UDim2.new(1, 0, 0, 20))
	invHead.LayoutOrder = 1
	Kit.caption(invHead, "Your datasets")
	local totalText = Kit.text(invHead, "", 14, F.bold, C.text)
	totalText.AnchorPoint = Vector2.new(1, 0)
	totalText.Position = UDim2.fromScale(1, 0)
	local tiles = Kit.grid(inventory, #DataConfig.TYPES, 86, 10, 2)
	local tileRefs: { [string]: { tokens: TextLabel, bar: Kit.Bar, quality: TextLabel } } = {}
	for index, dataType in DataConfig.TYPES do
		local tile = Kit.frame(tiles)
		tile.LayoutOrder = index
		tile.BackgroundTransparency = 0.3
		tile.BackgroundColor3 = C.bg
		Kit.corner(tile, 10)
		Kit.padding(tile, 10, 12, 10, 12)
		Kit.list(tile, 4)
		local name = Kit.text(tile, dataType.label, 13, F.bold, TYPE_COLORS[dataType.id] or C.muted)
		name.LayoutOrder = 1
		local tokens = Kit.text(tile, "0", 22, F.black, C.text)
		tokens.LayoutOrder = 2
		local bar = Kit.bar(tile, 6, 3, TYPE_COLORS[dataType.id])
		local quality = Kit.text(tile, "", 12, F.medium, C.dim)
		quality.LayoutOrder = 4
		tileRefs[dataType.id] = { tokens = tokens, bar = bar, quality = quality }
	end
	local readiness = Kit.para(inventory, "", 14, C.muted, 3)

	-- Scrapen
	local scrapeCard = Kit.card(scroll, 3, 8)
	local scrapeTitle = Kit.text(scrapeCard, "Scrape the web", 18, F.bold, C.text)
	scrapeTitle.LayoutOrder = 1
	Kit.para(
		scrapeCard,
		`Free, but slow and messy: {Format.tokens(DataConfig.SCRAPE.tokens)} tokens of {typeLabel(DataConfig.SCRAPE.type)} at {Format.percent(DataConfig.SCRAPE.quality)} quality, every {DataConfig.SCRAPE.cooldown}s.`,
		14,
		C.muted,
		2
	)
	-- fix round 1 (review B3): touch targets >= 56 px on touch (44.8 pt in the Menu's legacy x 0.80)
	local scrapeButton = Kit.button(scrapeCard, "SCRAPE", "secondary", UDim2.fromOffset(200, Kit.tap(42, 56)))
	scrapeButton.LayoutOrder = 3
	Kit.onClick(scrapeButton, function()
		local ok = ActionController.call("Scrape", {})
		if ok then
			Toast.show("success", `+{Format.tokens(DataConfig.SCRAPE.tokens)} tokens scraped.`)
		end
	end)

	-- Markt
	local marketCaption = Kit.caption(scroll, "Data market", 4)
	marketCaption.TextSize = 13
	local deltaNote = Kit.para(scroll, "", 13, C.dim, 5)
	local packGrid = Kit.grid(scroll, 2, 148, 12, 6)
	local packRefs: { [string]: { delta: TextLabel, buy: TextButton, buy5: TextButton } } = {}
	for index, pack in DataConfig.PACKS do
		local card = Kit.frame(packGrid)
		card.LayoutOrder = index
		card.BackgroundTransparency = 0.05
		card.BackgroundColor3 = C.panel2
		Kit.corner(card, 12)
		Kit.stroke(card, 0.92)
		Kit.padding(card, 12, 14, 12, 14)

		local name = Kit.text(card, pack.label, 17, F.bold, C.text)
		name.Position = UDim2.new()
		local tag = Kit.tag(card, typeLabel(pack.type), TYPE_COLORS[pack.type] or C.muted)
		tag.AnchorPoint = Vector2.new(1, 0)
		tag.Position = UDim2.fromScale(1, 0)
		local info = Kit.text(card, `{Format.tokens(pack.tokens)} tokens · quality {Format.percent(pack.quality)}`, 14, F.medium, C.muted)
		info.Position = UDim2.fromOffset(0, 26)
		local delta = Kit.text(card, "", 14, F.bold, C.good)
		delta.Position = UDim2.fromOffset(0, 48)
		local price = Kit.text(card, Format.money(pack.price), 18, F.black, C.text)
		price.AnchorPoint = Vector2.new(0, 1)
		price.Position = UDim2.fromScale(0, 1)
		local tapH = Kit.tap(36, 56)
		local buy5W = Kit.tap(52, 58)
		local buy5 = Kit.button(card, "x5", "ghost", UDim2.fromOffset(buy5W, tapH))
		buy5.AnchorPoint = Vector2.new(1, 1)
		buy5.Position = UDim2.fromScale(1, 1)
		buy5.TextSize = 14
		local buy = Kit.button(card, "BUY", "primary", UDim2.fromOffset(86, tapH))
		buy.AnchorPoint = Vector2.new(1, 1)
		buy.Position = UDim2.new(1, -(buy5W + 8), 1, 0)
		buy.TextSize = 14

		local function purchase(count: number)
			local ok = ActionController.call("BuyData", { packId = pack.id, count = count })
			if ok then
				Toast.show("success", `Bought {count}x {pack.label} (+{Format.tokens(pack.tokens * count)} tokens).`, 2)
			end
		end
		Kit.onClick(buy, function()
			purchase(1)
		end)
		Kit.onClick(buy5, function()
			purchase(5)
		end)
		packRefs[pack.id] = { delta = delta, buy = buy, buy5 = buy5 }
	end

	refresh = function(snapshot: Snapshot)
		local data = snapshot.data
		local summary = ModelMath.dataSummary(data.data)
		totalText.Text = `{Format.tokens(summary.total)} tokens · avg quality {Format.percent(summary.quality)}`
		local largest = 1
		for _, stock in data.data do
			largest = math.max(largest, stock.tokens)
		end
		for id, refs in tileRefs do
			local stock = data.data[id]
			local tokens = if stock then stock.tokens else 0
			refs.tokens.Text = Format.tokens(tokens)
			refs.bar.set(tokens / largest)
			refs.quality.Text = if stock then `quality {Format.percent(stock.quality)}` else "none yet"
		end

		local ui = StateController.ui
		local size = ModelConfig.getSize(ui.sizeId)
		local company = data.company
		local spec = if company then company.spec else "general"
		if size then
			local ready = ModelMath.readiness(size, summary)
			readiness.Text = `Data fill for a {size.label} model: {Format.percent(ready.fill)}`
				.. (if ready.fill < 1 then ` (full at {Format.tokens(size.dataNeed)} tokens)` else " - full! Quality matters most now.")
			deltaNote.Text = `Green numbers: Overall change for your selected {size.label} {string.lower(ui.focusId)} model in the Lab.`
			local baseStats, baseOverall = ModelMath.computeStats(size.id, ui.focusId, summary, spec, 1, nil)
			baseStats, baseOverall = EmpireMath.boostStats(baseStats, data.empire)
			for _, pack in DataConfig.PACKS do
				local refs = packRefs[pack.id]
				if refs then
					local stock = ModelMath.copyStock(data.data)
					ModelMath.addTokens(stock, pack.type, pack.tokens, pack.quality)
					local packStats, withPack = ModelMath.computeStats(size.id, ui.focusId, ModelMath.dataSummary(stock), spec, 1, nil)
					packStats, withPack = EmpireMath.boostStats(packStats, data.empire)
					local diff = withPack - baseOverall
					refs.delta.Text = `{Format.signed(diff)} Overall on {size.label}`
					refs.delta.TextColor3 = if diff > 0.05 then C.good elseif diff < -0.05 then C.bad else C.dim
				end
			end
		end

		local money = StateController.money()
		for _, pack in DataConfig.PACKS do
			local refs = packRefs[pack.id]
			if refs then
				Kit.setDisabled(refs.buy, money < pack.price)
				Kit.setDisabled(refs.buy5, money < pack.price * 5)
			end
		end
	end

	StateController.onChange(function(snapshot: Snapshot)
		if parent.Visible and navigation.isOpen() then
			refresh(snapshot)
		end
	end)
	StateController.onUiChange(function()
		local snapshot = StateController.snapshot
		if snapshot and parent.Visible then
			refresh(snapshot)
		end
	end)

	-- Cooldown-Anzeige läuft unabhängig vom Snapshot-Takt
	RunService.RenderStepped:Connect(function()
		local snapshot = StateController.snapshot
		if not snapshot or not parent.Visible or not navigation.isOpen() then
			return
		end
		local remaining = snapshot.data.lastScrapeAt + DataConfig.SCRAPE.cooldown - workspace:GetServerTimeNow()
		if remaining > 0 then
			scrapeButton.Text = `COOLDOWN {math.ceil(remaining)}s`
			Kit.setDisabled(scrapeButton, true)
		else
			scrapeButton.Text = `SCRAPE (+{Format.tokens(DataConfig.SCRAPE.tokens)})`
			Kit.setDisabled(scrapeButton, false)
		end
	end)
end

function DataApp.onShow()
	local snapshot = StateController.snapshot
	if snapshot and root then
		refresh(snapshot)
	end
end


return DataApp
