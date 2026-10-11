--!strict
-- Markt: Gesamtzahlen, eigene Live-Modelle (Preise ändern, zurückziehen), Rangliste gegen NPCs.
-- CORE_SPEC 7 (models package): serving capacity / waitlist (live.capacity/load/waitlist), product lines with
-- the model that holds each line and the slots of the office, per model: line version, age, refinements x/3
-- (the model keeps serving while refining), Auto price toggle with the last automatic price change.
-- Money is shown per game day (CORE_SPEC 6: 1 day = 1200 s; prices per month = 3 game days).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local MarketConfig = require(Shared.Config.MarketConfig)
local CompanyConfig = require(Shared.Config.CompanyConfig)
local ModelConfig = require(Shared.Config.ModelConfig)
local ModelMath = require(Shared.ModelMath)
local Format = require(Shared.Format)
local Types = require(Shared.Types)

local UI = script.Parent.Parent
local Client = UI.Parent
local StateController = require(Client.Controllers.StateController)
local ActionController = require(Client.Controllers.ActionController)
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Toast = require(UI.Toast)
local ModelsUI = require(script.Parent.ModelsUI)

local C = Theme.colors
local F = Theme.font

type Snapshot = Types.Snapshot
type ModelData = Types.ModelData

type Card = {
	frame: Frame,
	users: Kit.Metric,
	revenue: Kit.Metric,
	serving: Kit.Metric,
	net: Kit.Metric,
	overall: TextLabel,
	segments: TextLabel,
	lineInfo: TextLabel,
	modeSeg: Kit.Segmented,
	priceNote: TextLabel,
	subSeg: Kit.Segmented,
	apiValue: TextLabel,
	apiLocal: number,
	touchedAt: number,
	refine: TextButton,
}

type LineUi = { detail: TextLabel, tag: TextLabel }

type Row = {
	frame: Frame,
	rank: TextLabel,
	dot: Frame,
	name: TextLabel,
	company: TextLabel,
	overall: TextLabel,
	users: TextLabel,
	price: TextLabel,
}

type Entry = {
	name: string,
	company: string,
	overall: number,
	users: number,
	sub: number,
	api: number,
	color: Color3,
	mine: boolean,
}

local API_STEP = 0.5

local MarketApp = {}

local root: Frame? = nil
local refresh: (Snapshot) -> () = function(_snapshot: Snapshot) end

local function sizeLabel(id: string): string
	local size = ModelConfig.getSize(id)
	return if size then size.label else id
end

local function priceText(sub: number, api: number): string
	return (if sub == 0 then "Free" else `${sub}/mo`) .. ` · {Format.price(api)}`
end

local function nextRank(peak: number): string
	for _, rank in CompanyConfig.RANKS do
		if rank.minUsers > peak then
			return `Next: {rank.name} at {Format.compact(rank.minUsers)} peak users`
		end
	end
	return "Top rank reached"
end

function MarketApp.mount(parent: Frame, navigation: Kit.Nav)
	root = parent

	local scroll = Kit.scroll(parent)
	Kit.padding(scroll, 2, 14, 20, 2)
	Kit.list(scroll, 14)

	Kit.heading(scroll, "MARKET", "A shared market for this server: your models, the AI labs and other companies compete for users in four product lines. Prices are per month (1 month = 3 game days = 1 hour); money is shown per game day.", 1)

	-- Kennzahlen
	local summary = Kit.stack(scroll, 10, 2) -- Kennzahlen ohne Karte: reine Information
	local grid = Kit.grid(summary, 3, 48, 12, 1)
	local mUsers = Kit.metric(grid, "Users", 1, 22)
	local mNet = Kit.metric(grid, "Net income", 2, 22)
	local mRep = Kit.metric(grid, "Reputation", 3, 22)
	local mRevenue = Kit.metric(grid, "Revenue", 4, 16)
	local mServing = Kit.metric(grid, "Serving cost", 5, 16)
	local mRank = Kit.metric(grid, "Rank", 6, 16)
	local rankNote = Kit.para(summary, "", 13, C.dim, 2)

	-- Serverkapazität (CORE_SPEC 3.1): Nutzer über der Kapazität warten
	local servingRow = Kit.stack(summary, 6, 3)
	local servingTop = Kit.frame(servingRow, UDim2.new(1, 0, 0, 20))
	servingTop.LayoutOrder = 1
	Kit.caption(servingTop, "Serving capacity")
	local servingValue = Kit.text(servingTop, "", 14, F.bold, C.text)
	servingValue.AnchorPoint = Vector2.new(1, 0)
	servingValue.Position = UDim2.fromScale(1, 0)
	local servingBar = Kit.bar(servingRow, 8, 2)
	local servingNote = Kit.para(servingRow, "", 13, C.dim, 3)

	-- Produktlinien (CORE_SPEC 7.1): welches Modell welche Linie hält, freie Plätze der Bürostufe
	local linesCard = Kit.card(scroll, 2, 8)
	local linesCaption = Kit.caption(linesCard, "Product lines", 1)
	local lineUi: { [string]: LineUi } = {}
	for index, line in ModelConfig.LINES do
		local row = Kit.frame(linesCard, UDim2.new(1, 0, 0, 44))
		row.LayoutOrder = 1 + index
		row.BackgroundTransparency = 0.3
		row.BackgroundColor3 = C.bg
		Kit.corner(row, 10)
		local name = Kit.text(row, line.label, 15, F.bold, C.text)
		name.Position = UDim2.fromOffset(12, 4)
		local detail = Kit.text(row, "", 13, F.medium, C.muted)
		detail.AutomaticSize = Enum.AutomaticSize.None
		detail.Size = UDim2.new(1, -100, 0, 18)
		detail.Position = UDim2.fromOffset(12, 23)
		detail.TextTruncate = Enum.TextTruncate.AtEnd
		local tag = Kit.tag(row, "free", C.dim)
		tag.AnchorPoint = Vector2.new(1, 0.5)
		tag.Position = UDim2.new(1, -10, 0.5, 0)
		lineUi[line.target] = { detail = detail, tag = tag }
	end
	local linesNote = Kit.para(linesCard, "", 13, C.dim, 9)

	local accessCard = Kit.card(scroll, 3, 10)
	Kit.caption(accessCard, "Your API subscription", 1)
	local accessInfo = Kit.para(accessCard, "", 14, C.muted, 2)
	local cancelAccess = Kit.button(accessCard, "STOP AUTO-RENEW", "secondary", UDim2.fromOffset(190,34))
	cancelAccess.LayoutOrder = 3
	Kit.onClick(cancelAccess,function() ActionController.call("CancelModelAccess",{}) end)
	Kit.para(accessCard,"API access adds research points while active. You keep training your own model. The provider receives your payment; access never copies their model or leaderboard score.",13,C.dim,4)
	Kit.caption(scroll,"Provider exchange · player companies",4)
	local exchange = Kit.stack(scroll,10,5)
	local providerRows: {[string]:any} = {}
	local providerKey = ""
	local customerCard = Kit.card(scroll,6,10)
	Kit.caption(customerCard,"Business clients · receipts",1)
	local businessInfo = Kit.para(customerCard,"",14,C.muted,2)
	local businessRows = {}
	for i=1,12 do
		businessRows[i]=Kit.para(customerCard,"",13,C.muted,i+2)
	end
	local ledger = Kit.para(customerCard,"",13,C.dim,15)

	-- Eigene Live-Modelle
	Kit.caption(scroll, "Your live models", 7)
	local cardList = Kit.stack(scroll, 12, 8)
	local emptyNote = Kit.para(scroll, "No live models yet. Train one in the Lab and launch it.", 14, C.dim, 9)
	local cards: { [string]: Card } = {}
	local cardKey = ""

	-- Rangliste
	Kit.caption(scroll, "Intelligence leaderboard · live models", 10)
	local board = Kit.card(scroll, 11, 2)
	local headerRow = Kit.frame(board, UDim2.new(1, 0, 0, 22))
	headerRow.LayoutOrder = 0
	local function headerCell(text: string, width: UDim, x: UDim, right: boolean?)
		local label = Kit.cell(headerRow, string.upper(text), width, 11, F.bold, C.dim)
		label.Position = UDim2.new(x, UDim.new(0, 0))
		if right then
			label.TextXAlignment = Enum.TextXAlignment.Right
		end
	end
	headerCell("#", UDim.new(0, 30), UDim.new(0, 0))
	headerCell("Model", UDim.new(0.34, -40), UDim.new(0, 40))
	headerCell("Company", UDim.new(0.26, 0), UDim.new(0.34, 10))
	headerCell("Overall", UDim.new(0, 64), UDim.new(0.6, 10), true)
	headerCell("Users", UDim.new(0, 80), UDim.new(0.6, 84), true)
	headerCell("Price", UDim.new(0.4, -184), UDim.new(0.6, 174), true)
	local rows: { Row } = {}

	local function makeRow(index: number): Row
		local frame = Kit.frame(board, UDim2.new(1, 0, 0, 34))
		frame.LayoutOrder = index
		frame.BackgroundColor3 = Theme.accent
		frame.BackgroundTransparency = 1
		Kit.corner(frame, 8)
		local rank = Kit.cell(frame, "", UDim.new(0, 30), 15, F.bold, C.dim)
		local dot = Kit.dot(frame, C.dim, 10)
		dot.AnchorPoint = Vector2.new(0, 0.5)
		dot.Position = UDim2.new(0, 34, 0.5, 0)
		local name = Kit.cell(frame, "", UDim.new(0.34, -52), 15, F.bold, C.text)
		name.Position = UDim2.fromOffset(52, 0)
		local company = Kit.cell(frame, "", UDim.new(0.26, 0), 14, F.medium, C.muted)
		company.Position = UDim2.new(0.34, 10, 0, 0)
		local overall = Kit.cell(frame, "", UDim.new(0, 64), 15, F.bold, C.text)
		overall.Position = UDim2.new(0.6, 10, 0, 0)
		overall.TextXAlignment = Enum.TextXAlignment.Right
		local users = Kit.cell(frame, "", UDim.new(0, 80), 15, F.bold, C.text)
		users.Position = UDim2.new(0.6, 84, 0, 0)
		users.TextXAlignment = Enum.TextXAlignment.Right
		local price = Kit.cell(frame, "", UDim.new(0.4, -184), 13, F.medium, C.muted)
		price.Position = UDim2.new(0.6, 174, 0, 0)
		price.TextXAlignment = Enum.TextXAlignment.Right
		return {
			frame = frame,
			rank = rank,
			dot = dot,
			name = name,
			company = company,
			overall = overall,
			users = users,
			price = price,
		}
	end

	local function buildCard(order: number, model: ModelData): Card
		local frame = Kit.card(cardList, order, 10)
		local top = Kit.frame(frame, UDim2.new(1, 0, 0, 26))
		top.LayoutOrder = 1
		local titleRow = Kit.frame(top, UDim2.new(1, -140, 1, 0))
		Kit.list(titleRow, 8, true)
		local name = Kit.text(titleRow, `{model.name} v{model.version}`, 19, F.bold, C.text)
		name.LayoutOrder = 1
		Kit.tag(titleRow, sizeLabel(model.sizeId), C.muted, 2)
		Kit.tag(titleRow, ModelsUI.lineLabel(model.release and model.release.target), Theme.accent, 3)
		Kit.tag(titleRow, "LIVE", C.good, 4)
		local overall = Kit.text(top, "", 15, F.bold, C.muted)
		overall.AnchorPoint = Vector2.new(1, 0.5)
		overall.Position = UDim2.fromScale(1, 0.5)

		local metrics = Kit.grid(frame, 4, 44, 10, 2)
		local users = Kit.metric(metrics, "Users", 1, 18)
		local revenue = Kit.metric(metrics, "Revenue", 2, 18)
		local serving = Kit.metric(metrics, "Serving", 3, 18)
		local net = Kit.metric(metrics, "Net", 4, 18)
		local segments = Kit.para(frame, "", 13, C.dim, 3)
		local lineInfo = Kit.para(frame, "", 13, C.muted, 4)

		-- Preismodus (CORE_SPEC 7.7): Auto price hält den Empfohlenen Preis, jede manuelle Änderung schaltet ihn ab
		local modeRow = Kit.frame(frame, UDim2.new(1, 0, 0, 36))
		modeRow.LayoutOrder = 5
		local card: Card
		local modeSeg = Kit.segmented(modeRow, {
			{ id = "auto", label = "Auto price" },
			{ id = "manual", label = "Manual" },
		}, if model.release and (model.release :: any).auto == false then "manual" else "auto", function(id: string)
			card.touchedAt = os.clock()
			ModelsUI.setAutoPrice(model.id, id == "auto")
		end, 34)
		modeSeg.frame.Size = UDim2.fromOffset(230, 34)
		local priceNote = Kit.text(modeRow, "", 13, F.medium, C.dim)
		priceNote.AutomaticSize = Enum.AutomaticSize.None
		priceNote.Size = UDim2.new(1, -244, 1, 0)
		priceNote.Position = UDim2.fromOffset(244, 0)
		priceNote.TextWrapped = true
		priceNote.TextTruncate = Enum.TextTruncate.AtEnd

		local controls = Kit.frame(frame, UDim2.new(1, 0, 0, 38))
		controls.LayoutOrder = 6
		local subCaption = Kit.caption(controls, "Sub")
		subCaption.Position = UDim2.new(0, 0, 0.5, 0)
		subCaption.AnchorPoint = Vector2.new(0, 0.5)
		local options: { Kit.Option } = {}
		for _, price in MarketConfig.SUB_PRICES do
			table.insert(options, { id = tostring(price), label = if price == 0 then "Free" else `${price}` })
		end
		local release = model.release
		local subSeg = Kit.segmented(controls, options, tostring(if release then release.subPrice else 0), function(id: string)
			card.touchedAt = os.clock()
			modeSeg.set("manual") -- a manual price switches auto-price off for this model
			ActionController.call("UpdatePricing", {
				modelId = model.id,
				subPrice = tonumber(id) or 0,
				apiPrice = card.apiLocal,
			})
		end, 36)
		subSeg.frame.Size = UDim2.fromOffset(230, 36)
		subSeg.frame.Position = UDim2.fromOffset(38, 1)

		local apiCaption = Kit.caption(controls, "API")
		apiCaption.Position = UDim2.new(0, 284, 0.5, 0)
		apiCaption.AnchorPoint = Vector2.new(0, 0.5)
		local minus = Kit.button(controls, "-", "secondary", UDim2.fromOffset(34, 34))
		minus.Position = UDim2.fromOffset(316, 2)
		local apiValue = Kit.text(controls, "", 15, F.bold, C.text)
		apiValue.AutomaticSize = Enum.AutomaticSize.None
		apiValue.Size = UDim2.fromOffset(64, 38)
		apiValue.Position = UDim2.fromOffset(354, 0)
		apiValue.TextXAlignment = Enum.TextXAlignment.Center
		local plus = Kit.button(controls, "+", "secondary", UDim2.fromOffset(34, 34))
		plus.Position = UDim2.fromOffset(422, 2)
		local retire = Kit.button(controls, "RETIRE", "danger", UDim2.fromOffset(110, 34))
		retire.AnchorPoint = Vector2.new(1, 0)
		retire.Position = UDim2.new(1, 0, 0, 2)
		retire.TextSize = 13

		local refineRow = Kit.row(frame, Kit.tap(34, 104), 10, 7)
		local refine = Kit.button(refineRow, "REFINE CHECKPOINT", "secondary", UDim2.fromOffset(Kit.tap(190, 300), Kit.tap(32, 104)))
		Kit.onClick(refine, function()
			ModelsUI.call("ImproveModel", { modelId = model.id })
		end)
		-- the phone's model chat (design/requests/phone.md #3): a released model answers in the phone's chat app
		local chat = Kit.button(refineRow, "CHAT", "secondary", UDim2.fromOffset(Kit.tap(110, 180), Kit.tap(32, 104)))
		chat.Name = "Chat"
		chat.LayoutOrder = 2
		Kit.onClick(chat, function()
			-- lazy require: PhoneController requires Screens/Computer, which requires the apps (no require cycle)
			local ok, phone = pcall(require, Client.Controllers.PhoneController)
			if ok and typeof(phone) == "table" and typeof((phone :: any).openChat) == "function" then
				(phone :: any).openChat(model.id)
				navigation.close()
			end
		end)
		Kit.para(frame, `Add 100M new tokens, then refine with your GPUs: the model keeps serving with the current version meanwhile. At most {ModelConfig.REFINE.limit} refinements per model, each costs 50 % more; every stat stays at most {ModelConfig.STAT_CAP}.`, 13, C.dim, 8)

		card = {
			frame = frame,
			users = users,
			revenue = revenue,
			serving = serving,
			net = net,
			overall = overall,
			segments = segments,
			lineInfo = lineInfo,
			modeSeg = modeSeg,
			priceNote = priceNote,
			subSeg = subSeg,
			apiValue = apiValue,
			apiLocal = if release then release.apiPrice else MarketConfig.API_PRICE.default,
			touchedAt = 0,
			refine = refine,
		}

		local function stepApi(direction: number)
			local P = MarketConfig.API_PRICE
			local value = math.clamp(math.round((card.apiLocal + direction * API_STEP) * 100) / 100, P.min, P.max)
			if value == card.apiLocal then
				return
			end
			card.apiLocal = value
			card.touchedAt = os.clock()
			modeSeg.set("manual")
			apiValue.Text = Format.price(value)
			ActionController.call("UpdatePricing", {
				modelId = model.id,
				subPrice = tonumber(subSeg.get()) or 0,
				apiPrice = value,
			})
		end
		Kit.onClick(minus, function()
			stepApi(-1)
		end)
		Kit.onClick(plus, function()
			stepApi(1)
		end)

		local armedAt = 0
		Kit.onClick(retire, function()
			if os.clock() - armedAt > 3 then
				armedAt = os.clock()
				retire.Text = "CONFIRM?"
				task.delay(3, function()
					if retire.Parent then
						retire.Text = "RETIRE"
					end
				end)
				return
			end
			armedAt = 0
			local ok = ActionController.call("RetireModel", { modelId = model.id })
			if ok then
				Toast.show("info", `{model.name} v{model.version} was retired.`)
			end
		end)
		return card
	end

	refresh = function(snapshot: Snapshot)
		local data = snapshot.data
		local live = snapshot.live
		local company = data.company

		mUsers.value.Text = Format.compact(live.users)
		mNet.value.Text = Format.perDay(live.revenue - live.cost)
		mNet.value.TextColor3 = if live.revenue >= live.cost then C.good else C.bad
		mRevenue.value.Text = Format.money(live.revenue * Format.DAY_SECONDS) .. "/day"
		mServing.value.Text = Format.money(live.cost * Format.DAY_SECONDS) .. "/day"
		mRep.value.Text = if company then string.format("%.1f", company.reputation) else "0"
		mRank.value.Text = CompanyConfig.rankFor(data.stats.peakUsers)
		rankNote.Text = `Peak users: {Format.compact(data.stats.peakUsers)} · {nextRank(data.stats.peakUsers)}`

		-- serving capacity and waitlist ("12,400 waiting — buy GPUs")
		local serving = ModelsUI.serving(live)
		servingRow.Visible = serving.known
		if serving.known then
			servingValue.Text = if serving.waitlist >= 1 then `{Format.int(serving.waitlist)} waiting` else Format.percent(math.min(serving.full, 9.99)) .. " full"
			servingValue.TextColor3 = if serving.waitlist >= 1 then C.bad elseif serving.full >= 0.85 then C.warn else C.text
			servingBar.set(serving.full)
			servingNote.Text = `{serving.text} · capacity {Format.compact(serving.capacity)} users (500M-model equivalents), demand {Format.compact(serving.load)}`
			servingNote.TextColor3 = if serving.waitlist >= 1 then C.warn else C.dim
		end

		-- product lines
		local lineRows, usedLines, slots = ModelsUI.lines(data)
		local slotText = if slots == math.huge then tostring(usedLines) else `{usedLines} / {slots}`
		linesCaption.Text = `Product lines · {slotText} live at {ModelsUI.officeName(data.empire.office)}`
		for _, lineRow in lineRows do
			local refs = lineUi[lineRow.line.target]
			local model = lineRow.model
			if model then
				refs.detail.Text = `{model.name} v{model.version} · line v{lineRow.version} · Overall {string.format("%.1f", model.overall)} · {ModelsUI.ageText(model)} · {ModelsUI.refineText(model)}`
					.. (if lineRow.extra > 0 then ` · +{lineRow.extra} more` else "")
				refs.detail.TextColor3 = C.text
				refs.tag.Text = "LIVE"
				refs.tag.TextColor3 = C.good
			elseif lineRow.open then
				local left = slots - usedLines
				refs.detail.Text = `Free: {left} more line{if left == 1 then "" else "s"} at this office · launch a model here from the Lab`
				refs.detail.TextColor3 = C.muted
				refs.tag.Text = "FREE"
				refs.tag.TextColor3 = C.muted
			else
				local nextStage = ModelsUI.officeForLines(usedLines)
				refs.detail.Text = if nextStage then `Opens with {ModelsUI.officeName(nextStage)}` else "All lines are in use"
				refs.detail.TextColor3 = C.dim
				refs.tag.Text = "LOCKED"
				refs.tag.TextColor3 = C.dim
			end
		end
		linesNote.Text = `One live model per line. A new release into a live line replaces it and takes over {math.floor(ModelConfig.MIGRATE * 100 + 0.5)} % of its users. Models age (up to -8 fit after 3 game days), so ship new versions.`

		local subscription=data.empire.subscriptions
		local active=typeof(subscription.expires)=="number" and subscription.expires>os.time()
		accessInfo.Text=if active then subscription.provider .. " / " .. subscription.name .. " · " .. Format.money(subscription.price) .. "/month · " .. Format.duration(subscription.expires-os.time()) .. " left · " .. (if subscription.autoRenew then "Auto-renew ON" else "One month, no automatic renewal") else "No active provider. Choose a player offer below."
		cancelAccess.Visible=active and subscription.autoRenew==true
		local market=live.marketplace or {offers={},customers={}}
		local ids={}
		for _,offer in market.offers do table.insert(ids,tostring(offer.providerId)..":"..offer.id) end
		local newKey=table.concat(ids,",")
		if newKey~=providerKey then
			providerKey=newKey
			for _,refs in providerRows do refs.frame:Destroy() end
			table.clear(providerRows)
			for index,offer in market.offers do
				local key=tostring(offer.providerId)..":"..offer.id
				local card=Kit.card(exchange,index,10)
				local title=Kit.text(card,offer.company.." / "..offer.name,17,F.bold,C.text)
				title.LayoutOrder=1
				local detail=Kit.para(card,"",13,C.muted,2)
				local actions=Kit.row(card,34,10,3)
				local purchase=Kit.button(actions,"BUY ONE MONTH","primary",UDim2.fromOffset(175,32))
				local renew=Kit.button(actions,"SUBSCRIBE + AUTO-RENEW","secondary",UDim2.fromOffset(235,32))
				renew.LayoutOrder=2
				local refs={frame=card,detail=detail,purchase=purchase,renew=renew,offer=offer}
				providerRows[key]=refs
				local function buyAccess(auto: boolean)
					local current=refs.offer
					ActionController.call("BuyModelAccess",{providerId=current.providerId,modelId=current.id,quotedPrice=current.price,autoRenew=auto})
				end
				Kit.onClick(purchase,function() buyAccess(false) end)
				Kit.onClick(renew,function() buyAccess(true) end)
			end
		end
		for _,offer in market.offers do
			local refs=providerRows[tostring(offer.providerId)..":"..offer.id]
			if refs then
				refs.offer=offer
				local mine=data.models[offer.id]~=nil
				refs.detail.Text=string.format("%.1f intelligence pts · %d refinements · %s / game month%s",offer.overall,offer.iterations,Format.money(offer.price),if mine then " · Your model" else "")
				Kit.setDisabled(refs.purchase,mine or active or data.money<offer.price)
				Kit.setDisabled(refs.renew,mine or active or data.money<offer.price)
			end
		end
		businessInfo.Text=ModelsUI.businessText(data)
		for index,label in businessRows do
			local customer=market.customers[index]
			label.Visible=customer~=nil
			if customer then
				label.Text=customer.name.." · "..customer.stat.." ≥ "..tostring(customer.minimum).." · "..customer.provider.." · "..(if customer.price>0 then Format.money(customer.price).."/month, renews in "..Format.duration(customer.remaining) else "Budget "..Format.money(customer.budget).."/month")
			end
		end
		local receipts={}
		for i=1,math.min(4,#data.empire.invoices) do
			local bill=data.empire.invoices[i]
			table.insert(receipts,bill.text.." · "..Format.money(bill.amount))
		end
		ledger.Text=if #receipts>0 then table.concat(receipts,"\n") else "No API access receipts yet."

		-- Karten neu aufbauen, wenn sich die Menge der Live-Modelle ändert
		local liveIds: { string } = {}
		for _, id in data.modelOrder do
			local model: ModelData? = data.models[id]
			if model and model.status == "live" then
				table.insert(liveIds, id)
			end
		end
		local key = table.concat(liveIds, ",")
		if key ~= cardKey then
			cardKey = key
			for _, card in cards do
				card.frame:Destroy()
			end
			table.clear(cards)
			for index, id in liveIds do
				cards[id] = buildCard(index, data.models[id])
			end
		end
		emptyNote.Visible = #liveIds == 0

		for id, card in cards do
			local model: ModelData? = data.models[id]
			local release = if model then model.release else nil
			local result = live.perModel[id]
			if model and release then
				card.overall.Text = `Overall {string.format("%.1f", model.overall)} / {ModelConfig.STAT_CAP}`
				local users = if result then result.users else 0
				local revenue = if result then result.revenue else 0
				local cost = if result then result.cost else 0
				card.users.value.Text = Format.compact(users)
				card.revenue.value.Text = Format.money(revenue * Format.DAY_SECONDS) .. "/day"
				card.serving.value.Text = Format.money(cost * Format.DAY_SECONDS) .. "/day"
				card.net.value.Text = Format.money((revenue - cost) * Format.DAY_SECONDS) .. "/day"
				card.net.value.TextColor3 = if revenue >= cost then C.good else C.bad
				local market = model.market
				local parts: { string } = {}
				for _, segment in MarketConfig.SEGMENTS do
					local count = if market then market.users[segment.id] or 0 else 0
					table.insert(parts, `{segment.label} {Format.compact(count)}`)
				end
				card.segments.Text = table.concat(parts, " · ")
				local predecessor = ModelsUI.predecessor(data, model.id)
				card.lineInfo.Text = `{ModelsUI.lineLabel(release.target)} · line v{ModelMath.lineVersion(data, model.id)}`
					.. (if predecessor then ` (successor of {predecessor.name} v{predecessor.version})` else "")
					.. ` · {ModelsUI.ageText(model)} · {ModelsUI.refineText(model)}`
				local auto = (release :: any).auto ~= false
				-- kurz nach eigener Änderung nicht vom (evtl. älteren) Snapshot überschreiben lassen
				if os.clock() - card.touchedAt > 1.5 then
					card.subSeg.set(tostring(release.subPrice))
					card.apiLocal = release.apiPrice
					card.modeSeg.set(if auto then "auto" else "manual")
				end
				card.apiValue.Text = Format.price(card.apiLocal)
				card.priceNote.Text = ModelsUI.autoPriceText(live, model)
				local runs = math.floor(tonumber(model.iterations) or 0)
				local refining = data.training ~= nil and data.training.modelId == id
				card.refine.Text = if refining then "REFINING…" elseif runs >= ModelConfig.REFINE.limit then `REFINED {runs}/{ModelConfig.REFINE.limit}` else `REFINE {runs + 1}/{ModelConfig.REFINE.limit}`
				Kit.setDisabled(card.refine, refining or runs >= ModelConfig.REFINE.limit or data.training ~= nil)
			end
		end

		-- Rangliste
		local entries: { Entry } = {}
		local npcList: { any } = if live.marketplace then {} else MarketConfig.NPC_MODELS
		for _, npc in npcList do
			table.insert(entries, {
				name = npc.name,
				company = npc.company,
				overall = ModelMath.overall(npc.stats),
				users = live.npcUsers[npc.id] or 0,
				sub = npc.subPrice,
				api = npc.apiPrice,
				color = Theme.rgb(npc.rgb),
				mine = false,
			})
		end
		for _, id in liveIds do
			local model = data.models[id]
			local release = model.release
			local result = live.perModel[id]
			table.insert(entries, {
				name = `{model.name} v{model.version}`,
				company = if company then company.name else "You",
				overall = model.overall,
				users = if result then result.users else 0,
				sub = if release then release.subPrice else 0,
				api = if release then release.apiPrice else 0,
				color = Theme.accent,
				mine = true,
			})
		end
		for _,offer in market.offers do
			if not data.models[offer.id] then
				table.insert(entries,{name=offer.name,company=offer.company,overall=offer.overall,users=offer.users,sub=offer.sub,api=offer.api,color=C.muted,mine=false})
			end
		end
		table.sort(entries, function(a: Entry, b: Entry): boolean
			if a.overall == b.overall then return a.company < b.company end
			return a.overall > b.overall
		end)
		while #rows < #entries do
			table.insert(rows, makeRow(#rows + 1))
		end
		for index, row in rows do
			local entry = entries[index]
			row.frame.Visible = entry ~= nil
			if entry then
				row.rank.Text = tostring(index)
				row.dot.BackgroundColor3 = entry.color
				row.name.Text = entry.name
				row.name.TextColor3 = if entry.mine then Theme.accent else C.text
				row.company.Text = entry.company
				row.overall.Text = string.format("%.1f", entry.overall)
				row.users.Text = Format.compact(entry.users)
				row.price.Text = priceText(entry.sub, entry.api)
				row.frame.BackgroundColor3 = Theme.accent
				row.frame.BackgroundTransparency = if entry.mine then 0.88 else 1
			end
		end
	end

	StateController.onChange(function(snapshot: Snapshot)
		if parent.Visible and navigation.isOpen() then
			refresh(snapshot)
		end
	end)
end

function MarketApp.onShow()
	local snapshot = StateController.snapshot
	if snapshot and root then
		refresh(snapshot)
	end
end

return MarketApp
