--!strict
-- Model Studio, LAUNCH DAY (LAB_SPEC 4.12): the phone game's 3-part launch panel. Steps 1 Line · 2 Price ·
-- 3 Campaign; the summary column (price, 5-minute forecast, launch total) and the LAUNCH button stay visible on
-- every step, so one tap launches with the preselected line, the Auto/Recommended price and the Recommended
-- campaign. The release logic is the Lab's old release card, unchanged: Recommended price = PricingMath.recommend
-- on the client (sliced over frames, a newer request cancels an older one), forecast = PricingMath.profit with
-- the company's bonuses and the market cycle, payload ReleaseModel {modelId, target, marketing, auto,
-- subPrice/apiPrice only when auto == false}.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ModelConfig = require(Shared.Config.ModelConfig)
local MarketConfig = require(Shared.Config.MarketConfig)
local EmpireConfig = require(Shared.Config.EmpireConfig)
local ModelMath = require(Shared.ModelMath)
local MarketMath = require(Shared.MarketMath)
local EmpireMath = require(Shared.EmpireMath)
local PricingMath = require(Shared.PricingMath)
local Format = require(Shared.Format)
local Types = require(Shared.Types)

local UI = script.Parent.Parent
local Client = UI.Parent
local StateController = require(Client.Controllers.StateController)
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local ModelsUI = require(UI.Apps.ModelsUI)
local Parts = require(script.Parent.StudioParts)
local LabPreview = require(script.Parent.LabPreview)
local LabState = require(script.Parent.LabState)

local C = Theme.colors
local F = Theme.font

type Snapshot = Types.Snapshot
type ModelData = Types.ModelData

local FORECAST_SECONDS = ModelConfig.PRICING.cardSeconds
local MARKETING_TIERS = { 5_000, 10_000, 25_000, 50_000, 100_000, 250_000 }
local CAMPAIGNS = {
	{ id = "none", label = "No campaign", amount = 0 },
	{ id = "recommended", label = "Recommended", amount = -1 }, -- PricingMath.recommendedMarketing
	{ id = "big", label = "Big push", amount = 25_000 },
	{ id = "mega", label = "Mega", amount = 100_000 },
	{ id = "global", label = "Global", amount = 250_000 },
	{ id = "custom", label = "Custom", amount = -2 },
}
local STEP_TITLES = { "Product line", "Price", "Campaign" }

local LaunchDay = {}

-- "$4 per 1M tokens" / "$10 per month": the price that matters for the line
local function linePrice(target: string, sub: number, api: number): string
	if PricingMath.lineUsesSub(target) then
		return if sub == 0 then "Free" else `${sub} per month`
	end
	local text = if api % 1 == 0 then tostring(api) else string.format("%.2f", api)
	return `${text} per 1M tokens`
end

function LaunchDay.build(Studio: any): any
	local frame = Kit.frame(Studio.body)
	frame.Name = "LaunchView"
	local main = Kit.frame(frame, UDim2.new(1, 0, 1, -82))
	local bottom = Kit.frame(frame, UDim2.new(1, 0, 0, 74), UDim2.new(0, 0, 1, -74))

	---------------------------------------------------------------- preview zone: card + summary column
	local preview = Kit.frame(main, UDim2.new(1, -734, 1, 0), UDim2.fromOffset(16, 0))
	local card = Parts.modelCard(preview, Vector2.new(164, 262))
	local summary = Parts.panel(preview, UDim2.fromOffset(176, 0), UDim2.new(1, -176, 1, 0))
	summary.Name = "Summary"
	local sumList = Kit.frame(summary, UDim2.new(1, -28, 1, -16), UDim2.fromOffset(14, 8))
	local layout = Kit.list(sumList, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	local function sumLabel(text: string, size: number, font: Enum.Font, color: Color3, order: number, wrap: boolean?): TextLabel
		local label = Parts.label(sumList, text, size, font, color)
		label.LayoutOrder = order
		label.Size = UDim2.new(1, 0, 0, 0)
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.TextWrapped = wrap == true
		label.TextTruncate = if wrap then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd
		return label
	end
	-- a small gap before each section caption so the three groups read apart
	local function gap(order: number)
		local spacer = Kit.frame(sumList, UDim2.new(1, 0, 0, 6))
		spacer.LayoutOrder = order
	end
	sumLabel("PRICE", 20, F.bold, C.muted, 1)
	local recText = sumLabel("", 22, F.bold, C.text, 2, true)
	recText.Name = "Recommended"
	local modeNote = sumLabel("", 20, F.medium, C.muted, 3, true)
	modeNote.Name = "PriceMode"
	gap(4)
	sumLabel("AFTER 5 MIN", 20, F.bold, C.muted, 5)
	local forecastLine = sumLabel("", 22, F.bold, C.text, 6, true)
	forecastLine.RichText = true
	local campaignLine = sumLabel("", 20, F.medium, C.muted, 7, true)
	gap(8)
	sumLabel("LAUNCH TOTAL", 20, F.bold, C.muted, 9)
	local totalLine = sumLabel("", 22, F.bold, C.text, 10)

	---------------------------------------------------------------- right panel
	local panel = Parts.panel(main, UDim2.new(1, -702, 0, 0), UDim2.new(0, 686, 1, 0))
	panel.Name = "LaunchPanel"
	local title = Parts.label(panel, "", 34, F.display, C.text, UDim2.fromOffset(18, 10), UDim2.new(1, -300, 0, 42))
	local stepLabel = Parts.label(panel, "", 20, F.bold, Theme.accent, UDim2.fromOffset(18, 16), UDim2.new(1, -36, 0, 30), Enum.TextXAlignment.Right)
	local hint = Parts.label(panel, "", 20, F.medium, C.muted, UDim2.fromOffset(18, 52), UDim2.new(1, -36, 0, 52))
	hint.Name = "LineInfo"
	hint.TextWrapped = true
	hint.TextYAlignment = Enum.TextYAlignment.Top
	local bodies: { Frame } = {}
	for i = 1, 3 do
		local f = Kit.frame(panel, UDim2.new(1, -32, 1, -114), UDim2.fromOffset(16, 106))
		f.Name = "LaunchStep" .. i
		f.Visible = false
		bodies[i] = f
	end

	---------------------------------------------------------------- state
	local step = 1
	local done = { false, false, false }
	local modelId: string? = nil
	local subPrice = 5
	local apiPrice = MarketConfig.API_PRICE.default
	local marketing = 0
	local campaignId = "recommended"
	local target = "general"
	local autoMode = true
	local manualTouched = false
	local configuredFor: string? = nil
	local rec: PricingMath.Choice? = nil
	local recKey = ""
	local recGen = 0
	local forecastGen = 0
	local forecast: { users: number, net: number, serversText: string?, baseUsers: number? }? = nil
	local baseCache: { [string]: number } = {}
	local launching = false
	local updateForecast: () -> () = function() end
	local requestRecommendation: () -> () = function() end
	local refresh: () -> () = function() end

	local function snapshotModel(): (Snapshot?, ModelData?)
		local snapshot = StateController.snapshot
		local id = modelId
		local model = if snapshot and id then snapshot.data.models[id] else nil
		return snapshot, model
	end

	---------------------------------------------------------------- step 1: line tiles (Text = line.short)
	type LineTile = { option: Parts.OptionTile, tag: TextLabel }
	local lineTiles: { [string]: LineTile } = {}
	for i, line in ModelConfig.LINES do
		local col, row = (i - 1) % 2, (i - 1) // 2
		local option = Parts.optionTile(bodies[1], "Line_" .. line.target, UDim2.fromOffset(col * 333, row * 110), Vector2.new(321, 98), 2, 26, 24, line.short)
		option.check.Visible = false
		local tag = Parts.tag(option.tile.button, "NEW LINE", C.muted, UDim2.new(1, -174, 0, 10))
		tag.AutomaticSize = Enum.AutomaticSize.None
		tag.Size = UDim2.fromOffset(160, 28)
		-- "NEW VERSION" needs ~142 px at 20 px bold: narrower side padding keeps it inside the chip
		local tagPad = tag:FindFirstChildOfClass("UIPadding")
		if tagPad then
			tagPad.PaddingLeft = UDim.new(0, 4)
			tagPad.PaddingRight = UDim.new(0, 4)
		end
		tag.TextXAlignment = Enum.TextXAlignment.Center
		option.title.Size = UDim2.new(1, -190, 0, 30)
		option.right.Visible = false
		lineTiles[line.target] = { option = option, tag = tag }
		Kit.onClick(option.tile.button, function()
			target = line.target
			requestRecommendation()
			updateForecast()
			refresh()
		end)
	end

	---------------------------------------------------------------- step 2: price
	local autoTile = Parts.optionTile(bodies[2], "PriceAuto", UDim2.fromOffset(0, 0), Vector2.new(321, 90), 2, 24, 24, "AUTO")
	local manualTile = Parts.optionTile(bodies[2], "PriceManual", UDim2.fromOffset(333, 0), Vector2.new(321, 90), 2, 24, 24, "MANUAL")
	autoTile.check.Position = UDim2.new(1, -44, 0, 10)
	manualTile.check.Position = UDim2.new(1, -44, 0, 10)
	Parts.label(bodies[2], "SUBSCRIPTION / MONTH", 20, F.bold, C.muted, UDim2.fromOffset(0, 100), UDim2.fromOffset(320, 26))
	Parts.label(bodies[2], "API PER 1M TOKENS", 20, F.bold, C.muted, UDim2.fromOffset(340, 100), UDim2.fromOffset(310, 26))
	local subChips: { [number]: Parts.TileButton } = {}
	for i, price in MarketConfig.SUB_PRICES do
		local text = if price == 0 then "Free" else `${price}`
		local tile = Parts.tileButton(bodies[2], "Sub_" .. price, UDim2.fromOffset((i - 1) * 80, 128), UDim2.fromOffset(74, 74), text)
		tile.button.TextTransparency = 0
		tile.button:SetAttribute("HiddenText", nil)
		tile.button.TextSize = 22
		subChips[price] = tile
		Kit.onClick(tile.button, function()
			manualTouched = true
			autoMode = false
			subPrice = price
			updateForecast()
			refresh()
		end)
	end
	local minus = Parts.button(bodies[2], "−", "secondary", UDim2.fromOffset(340, 128), UDim2.fromOffset(74, 74), 34)
	minus.Name = "ApiMinus"
	local apiValue = Parts.label(bodies[2], "", 30, F.display, C.text, UDim2.fromOffset(420, 128), UDim2.fromOffset(150, 74), Enum.TextXAlignment.Center)
	local plus = Parts.button(bodies[2], "+", "secondary", UDim2.fromOffset(576, 128), UDim2.fromOffset(74, 74), 34)
	plus.Name = "ApiPlus"
	local function stepApi(direction: number)
		local P = MarketConfig.API_PRICE
		local value = math.clamp(math.round((apiPrice + direction * 0.5) * 100) / 100, P.min, P.max)
		manualTouched = true
		autoMode = false
		apiPrice = value
		updateForecast()
		refresh()
	end
	Kit.onClick(minus, function()
		stepApi(-1)
	end)
	Kit.onClick(plus, function()
		stepApi(1)
	end)
	Kit.onClick(autoTile.tile.button, function()
		autoMode = true
		local r = rec
		if r then
			subPrice, apiPrice = r.sub, r.api
		end
		updateForecast()
		refresh()
	end)
	Kit.onClick(manualTile.tile.button, function()
		autoMode = false
		manualTouched = true
		updateForecast()
		refresh()
	end)

	---------------------------------------------------------------- step 3: campaign
	type Campaign = { option: Parts.OptionTile, bar: Kit.Bar, amount: number }
	local campaigns: { [string]: Campaign } = {}
	for i, def in CAMPAIGNS do
		local col, row = (i - 1) % 3, (i - 1) // 3
		local option = Parts.optionTile(bodies[3], "Campaign_" .. def.id, UDim2.fromOffset(col * 222, row * 110), Vector2.new(210, 98), 2, 24, 24, def.label)
		option.check.Position = UDim2.new(1, -44, 1, -50)
		local b = Kit.bar(option.tile.button, 4, 0, C.good)
		b.frame.Position = UDim2.new(0, 16, 1, -7)
		b.frame.Size = UDim2.new(1, -32, 0, 4)
		campaigns[def.id] = { option = option, bar = b, amount = def.amount }
		Kit.onClick(option.tile.button, function()
			if def.id == "custom" then
				campaignId = "custom"
				refresh()
				return
			end
			campaignId = def.id
			local snapshot = StateController.snapshot
			if def.amount == -1 and snapshot then
				marketing = PricingMath.recommendedMarketing(StateController.money(), EmpireMath.bonuses(snapshot.data.empire).wage)
			else
				marketing = math.max(0, def.amount)
			end
			requestRecommendation()
			updateForecast()
			refresh()
		end)
	end
	-- custom amount: − / + steppers (touch friendly), range = the next marketing tier above the cash
	local custom = Parts.box(bodies[3], UDim2.fromOffset(0, 0), UDim2.new(1, 0, 1, 0), C.panel, 0, 14)
	custom.Name = "CustomCampaign"
	custom.Visible = false
	custom.ZIndex = 5
	local customTitle = Parts.label(custom, "Custom campaign", 26, F.bold, C.text, UDim2.fromOffset(16, 8), UDim2.new(1, -32, 0, 34))
	customTitle.ZIndex = 6
	local customMinus = Parts.button(custom, "−", "secondary", UDim2.fromOffset(16, 56), UDim2.fromOffset(74, 74), 34)
	customMinus.ZIndex = 6
	local customValue = Parts.label(custom, "", 30, F.display, C.text, UDim2.fromOffset(96, 56), UDim2.fromOffset(200, 74), Enum.TextXAlignment.Center)
	customValue.ZIndex = 6
	local customPlus = Parts.button(custom, "+", "secondary", UDim2.fromOffset(302, 56), UDim2.fromOffset(74, 74), 34)
	customPlus.ZIndex = 6
	local customBuzz = Parts.label(custom, "", 22, F.bold, C.good, UDim2.fromOffset(392, 56), UDim2.new(1, -408, 0, 74))
	customBuzz.ZIndex = 6
	local customDone = Parts.button(custom, "DONE", "primary", UDim2.new(1, -196, 1, -82), UDim2.fromOffset(180, 74), 26)
	customDone.ZIndex = 6
	local function customStep(direction: number)
		-- $1,000 steps below $10K, $5,000 below $50K, then $25,000; capped at the next tier above the cash
		local base = if direction > 0 then marketing else marketing - 1
		local stepSize = if base < 10_000 then 1_000 elseif base < 50_000 then 5_000 else 25_000
		local money = StateController.money()
		local maxAmount = MarketConfig.MARKETING.max
		for _, tier in MARKETING_TIERS do
			if tier >= money then
				maxAmount = tier
				break
			end
		end
		marketing = math.clamp(marketing + direction * stepSize, 0, maxAmount)
		requestRecommendation()
		updateForecast()
		refresh()
	end
	Kit.onClick(customMinus, function()
		customStep(-1)
	end)
	Kit.onClick(customPlus, function()
		customStep(1)
	end)
	Kit.onClick(customDone, function()
		custom.Visible = false
		refresh()
	end)

	---------------------------------------------------------------- bottom bar
	local chipHolder = Kit.frame(bottom, UDim2.new(1, -734, 1, 0), UDim2.fromOffset(16, 0))
	local chips = Parts.stepChips(chipHolder, 3, function(index: number)
		done[step] = true
		step = index
		custom.Visible = false
		refresh()
	end)
	local back = Parts.button(bottom, "‹ BACK", "secondary", UDim2.new(1, -702, 0, 0), UDim2.fromOffset(180, 74), 26)
	local launch = Parts.button(bottom, "LAUNCH", "primary", UDim2.new(1, -510, 0, 0), UDim2.fromOffset(494, 74), 22)
	launch.Name = "LaunchButton"

	---------------------------------------------------------------- recommendation + forecast (release card logic)
	requestRecommendation = function()
		local snapshot, model = snapshotModel()
		local id = modelId
		if not snapshot or not model or not id then
			return
		end
		local key = `{id}|{target}|{marketing}|{snapshot.data.empire.office}`
		if key == recKey then
			return
		end
		recKey = key
		recGen += 1
		local gen = recGen
		rec = nil
		local forModel: ModelData = model
		local forTarget, forMarketing = target, marketing
		task.spawn(function()
			local ok, choice = pcall(function(): PricingMath.Choice
				local ctx = ModelsUI.context(snapshot)
				-- one frame of work at most PRICING.clientBudget of CPU, then yield; a newer request cancels this one
				return PricingMath.recommend(ctx, snapshot.data, forModel, forTarget, forMarketing, PricingMath.slicer(ModelConfig.PRICING.clientBudget, function()
					task.wait()
					if gen ~= recGen then
						error("stale", 0)
					end
				end))
			end)
			if not ok or gen ~= recGen then
				return
			end
			rec = choice
			if autoMode or not manualTouched then
				subPrice, apiPrice = choice.sub, choice.api
			end
			updateForecast()
			refresh()
		end)
	end

	-- 5-minute forecast of the selected setup only (sliced; a newer request cancels an older one). The
	-- no-campaign forecast of the same line and prices is cached for "campaign adds +N users".
	updateForecast = function()
		local snapshot, model = snapshotModel()
		local id = modelId
		if not snapshot or not model or not id then
			return
		end
		if autoMode and rec == nil then
			-- the Recommended price is still being calculated: its result starts the one forecast of this selection
			forecastGen += 1
			forecast = nil
			return
		end
		forecastGen += 1
		local gen = forecastGen
		local data = snapshot.data
		local forTarget, forSub, forApi, forMarketing = target, subPrice, apiPrice, marketing
		local check = ModelMath.releaseCheck(data, id, forTarget)
		task.spawn(function()
			local function run(m: number): (number, PricingMath.Entry, any, any)
				local ctx = ModelsUI.context(snapshot)
				local candidate: PricingMath.Entry = {
					id = id,
					stats = model.stats,
					sizeId = model.sizeId,
					subPrice = forSub,
					apiPrice = forApi,
					market = PricingMath.releaseMarket(forTarget, m, check.replaced),
					target = forTarget,
				}
				local _, result, last = PricingMath.profit(ctx, candidate, FORECAST_SECONDS, PricingMath.slicer(ModelConfig.PRICING.clientBudget, function()
					task.wait()
					if gen ~= forecastGen then
						error("stale", 0)
					end
				end))
				return 0, candidate, result, last
			end
			local ok, err = pcall(function()
				local _, _, result, last = run(forMarketing)
				local baseKey = `{id}|{forTarget}|{forSub}|{forApi}`
				local base = baseCache[baseKey]
				if base == nil then
					if forMarketing == 0 then
						base = result.users
					else
						local _, _, baseResult = run(0)
						base = baseResult.users
					end
					baseCache[baseKey] = base
				end
				local bonuses = EmpireMath.bonuses(data.empire)
				local cycle = EmpireConfig.cycle(snapshot.serverTime)
				local revenue = result.revenue * bonuses.revenue * cycle.revenue
				local cost = result.cost * bonuses.serving * cycle.cost
				local serving = ModelsUI.serving(last)
				forecast = {
					users = result.users,
					net = revenue - cost,
					serversText = if serving.known and (serving.full >= 0.85 or serving.waitlist >= 1) then serving.text else nil,
					baseUsers = base,
				}
			end)
			if gen ~= forecastGen then
				return
			end
			if not ok and err ~= "stale" then
				forecast = nil
			end
			refresh()
		end)
	end

	---------------------------------------------------------------- refresh
	refresh = function()
		local snapshot, model = snapshotModel()
		local id = modelId
		if not snapshot or not model or not id or Studio.mode ~= "launch" then
			return
		end
		local data = snapshot.data
		local money = StateController.money()
		local company = data.company

		-- card + summary
		local rank = LabPreview.rank(snapshot, model.stats, target)
		local stars = LabPreview.stars(rank.rank, rank.total)
		card.set({
			sizeId = model.sizeId,
			focusId = model.focusId,
			name = model.name,
			version = model.version,
			lineShort = Parts.lineShort(target),
			logo = if company then company.logo else "N",
			look = (model :: any).look,
			recipeId = (model :: any).recipeId,
			overall = model.overall,
			stars = stars,
		})
		local r = rec
		recText.Text = if r then `Recommended: {linePrice(target, r.sub, r.api)}` else "Calculating the Recommended price from the live market..."
		modeNote.Text = if autoMode
			then "Auto price: the server sets the Recommended price and re-checks it every 5 min."
			else "Manual price: auto price stays off for this model until you switch it on again in the Market app."
		local f = forecast
		if f then
			forecastLine.Text = `{Format.compact(f.users)} users · <font color="#{(if f.net >= 0 then C.good else C.bad):ToHex()}">{Format.perDay(f.net)}</font>`
			if f.serversText then
				campaignLine.Text = `After launch: {f.serversText}.`
				campaignLine.TextColor3 = C.warn
			elseif f.baseUsers then
				local add = math.floor(f.users - f.baseUsers + 0.5)
				campaignLine.Text = `campaign adds {if add >= 0 then "+" else "−"}{Format.int(math.abs(add))} users`
				campaignLine.TextColor3 = C.muted
				-- what each extra user costs: the buzz cards look big, the forecast shows what they really add
				if marketing > 0 then
					if add > 0 then
						local each = marketing / add
						campaignLine.Text ..= ` · {Parts.money(math.floor(each + 0.5))} each`
					else
						campaignLine.TextColor3 = C.warn
					end
				end
			else
				campaignLine.Text = ""
			end
		else
			forecastLine.Text = "Forecasting…"
			campaignLine.Text = ""
		end
		totalLine.Text = `{Parts.money(marketing)} · {Parts.money(money - marketing)} left`

		-- line check + hint (the old release card's lineInfo text)
		local check = ModelMath.releaseCheck(data, id, target)
		local lineName = ModelsUI.lineLabel(target)
		local predecessor = check.replaced[1]
		if step == 1 then
			if predecessor then
				local users = 0
				for _, old in check.replaced do
					local market = old.market
					if market then
						for _, n in market.users do
							users += n
						end
					end
				end
				hint.Text = `{lineName}: successor of {predecessor.name} v{predecessor.version}. Becomes version {ModelMath.lineVersion(data, predecessor.id) + 1} of the line and takes over {math.floor(ModelConfig.MIGRATE * 100 + 0.5)} % of its {Format.compact(users)} users; {predecessor.name} v{predecessor.version} retires.`
				hint.TextColor3 = C.text
			elseif check.ok then
				local slots = if check.slots == math.huge then "" else ` ({check.usedLines + 1} of {check.slots} lines)`
				hint.Text = `{lineName}: a new product line{slots}.`
				hint.TextColor3 = C.text
			else
				hint.Text = `All {check.slots} product lines of {ModelsUI.officeName(data.empire.office)} are live. Pick a live line to release a new version there, or move to a bigger office for another line.`
				hint.TextColor3 = C.warn
			end
		elseif step == 2 then
			hint.Text = "Auto picks the best menu price and keeps adjusting it."
			hint.TextColor3 = C.muted
		else
			hint.Text = `Launch buzz in {LabPreview.segmentOf(target).label} fades over about 10 minutes. Left: what the picked campaign adds.`
			hint.TextColor3 = C.muted
		end
		title.Text = STEP_TITLES[step]
		stepLabel.Text = `LAUNCH DAY · {step} OF 3`
		stepLabel.TextColor3 = Theme.accent
		for i, b in bodies do
			b.Visible = i == step
		end

		if step == 1 then
			for _, line in ModelConfig.LINES do
				local refs = lineTiles[line.target]
				local c = ModelMath.releaseCheck(data, id, line.target)
				local old = c.replaced[1]
				local fit = MarketMath.fit(model.stats, LabPreview.segmentOf(line.target))
				local moved = 0
				for _, m in c.replaced do
					if m.market then
						moved += MarketMath.totalUsers(m.market) * ModelConfig.MIGRATE
					end
				end
				refs.option.set({
					title = line.short,
					lines = {
						if old then (function(): string
							local text = `Replaces {old.name} v{old.version} · {Format.compact(moved)}`
							return if #text <= 24 then text .. " move" else text
						end)() elseif c.ok then (if c.slots == math.huge then "New line" else `New line · {c.usedLines + 1} of {c.slots}`) else "No free line",
						string.format("fit %.1f · %s", fit, line.label),
					},
					colors = { C.text, C.good },
					selected = line.target == target,
					locked = not c.ok,
				})
				refs.tag.Text = if old then "NEW VERSION" elseif c.ok then "NEW LINE" else "FULL"
				refs.tag.TextColor3 = if old then C.good elseif c.ok then C.muted else C.dim
				local stroke = refs.tag:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = refs.tag.TextColor3
				end
			end
		elseif step == 2 then
			autoTile.set({
				title = "AUTO",
				lines = { if r then linePrice(target, r.sub, r.api) else "Calculating…", "Recommended · every 5 min" },
				colors = { C.text, C.muted },
				selected = autoMode,
			})
			manualTile.set({ title = "MANUAL", lines = { "You set the price", "auto price stays off" }, colors = { C.text, C.muted }, selected = not autoMode })
			autoTile.check.Visible = autoMode
			manualTile.check.Visible = not autoMode
			for price, tile in subChips do
				Parts.paintTile(tile, price == subPrice, autoMode)
				tile.button.TextColor3 = if autoMode then C.dim elseif price == subPrice then C.text else C.muted
			end
			apiValue.Text = Format.price(apiPrice)
			apiValue.TextColor3 = if autoMode then C.dim else C.text
		else
			local wage = EmpireMath.bonuses(data.empire).wage
			local recommended = PricingMath.recommendedMarketing(money, wage)
			for _, def in CAMPAIGNS do
				local refs = campaigns[def.id]
				local amount = if def.amount == -1 then recommended elseif def.amount == -2 then marketing else def.amount
				local buzz = LabPreview.campaignBuzz(target, amount)
				local tooMuch = amount > money and amount > 0
				local selected = campaignId == def.id
				local priceText = if def.id == "custom" then (if selected then Parts.money(amount) else "any amount") elseif amount == 0 then "Free" else Parts.money(amount)
				refs.option.set({
					title = def.label,
					lines = {
						priceText,
						if def.id == "custom" and not selected then `up to {Parts.money(MarketConfig.MARKETING.max)}` elseif tooMuch then `Need {Parts.money(math.ceil(amount - money))} more` else string.format("+%d %% buzz", math.floor(buzz * 100 + 0.5)),
					},
					colors = { C.text, if tooMuch then C.warn else C.good },
					selected = selected,
					locked = tooMuch,
				})
				refs.option.lines[1].Font = F.bold
				refs.option.check.Visible = selected
				refs.bar.set(buzz / MarketConfig.REACH.hypeMax)
				Parts.setDisabled(refs.option.tile.button, tooMuch and def.id ~= "custom")
			end
			customValue.Text = Parts.money(marketing)
			customBuzz.Text = string.format("+%d %% buzz", math.floor(LabPreview.campaignBuzz(target, marketing) * 100 + 0.5))
			custom.Visible = campaignId == "custom" and custom.Visible
		end

		-- chips + buttons
		chips.set(step, done, { "1 Line", "2 Price", "3 Campaign" })
		for i, button in chips.buttons do
			button:SetAttribute("Width", if i == step then 236 else 130)
			button.TextSize = 22
		end
		chips.set(step, done, { "1 Line", "2 Price", "3 Campaign" })
		back.Text = if step == 1 then "CLOSE" else "‹ BACK"
		if launching then
			launch.Text = "LAUNCHING…"
			Kit.setDisabled(launch, true)
		elseif not check.ok then
			launch.Text = "NO FREE PRODUCT LINE"
			Kit.setDisabled(launch, true)
		elseif marketing > money then
			launch.Text = "NOT ENOUGH MONEY FOR THIS BUDGET"
			Kit.setDisabled(launch, true)
		else
			local line = ModelConfig.getLine(target)
			local short = string.upper(if line then line.short else lineName)
			local what = if predecessor then `NEW VERSION · {short}` else `LAUNCH {short}`
			launch.Text = what .. (if marketing > 0 then ` · {Format.money(marketing)} MARKETING` else "")
			Kit.setDisabled(launch, false)
		end
		launch.TextSize = if #launch.Text > 30 then 22 else 26
	end

	local function configure(snapshot: Snapshot, model: ModelData, id: string)
		local data = snapshot.data
		local money = StateController.money()
		configuredFor = id
		autoMode = true
		manualTouched = false
		subPrice = 5
		apiPrice = MarketConfig.API_PRICE.default
		marketing = PricingMath.recommendedMarketing(money, EmpireMath.bonuses(data.empire).wage)
		campaignId = "recommended"
		forecast = nil
		baseCache = {}
		-- the line planned in the Studio (or saved with the model) when it is allowed, else the best-fitting
		-- line this office allows (a live line = new version, else a free slot): the old release card's rule
		local planned = LabState.plannedLine[id] or (model :: any).plan
		if typeof(planned) == "string" and ModelConfig.getLine(planned) and ModelMath.releaseCheck(data, id, planned).ok then
			target = planned
			return
		end
		type Fit = { target: string, fit: number }
		local fits: { Fit } = {}
		for _, segment in MarketConfig.SEGMENTS do
			local fit = MarketMath.fit(model.stats, segment)
			for _, line in ModelConfig.LINES do
				if ModelMath.lineOf(line.target) == segment.id then
					table.insert(fits, { target = line.target, fit = fit })
				end
			end
		end
		table.sort(fits, function(a: Fit, b: Fit): boolean
			return a.fit > b.fit
		end)
		target = if fits[1] then fits[1].target else "general"
		for _, option in fits do
			if ModelMath.releaseCheck(data, id, option.target).ok then
				target = option.target
				break
			end
		end
	end

	local function doLaunch()
		local snapshot, model = snapshotModel()
		local id = modelId
		if not snapshot or not model or not id or launching then
			return
		end
		if launch:GetAttribute("Disabled") == true then
			return
		end
		local token = Studio.token()
		local check = ModelMath.releaseCheck(snapshot.data, id, target)
		local predecessor = check.replaced[1]
		local moved = 0
		for _, old in check.replaced do
			if old.market then
				moved += MarketMath.totalUsers(old.market) * ModelConfig.MIGRATE
			end
		end
		local payload: { [string]: any } = { modelId = id, target = target, marketing = marketing, auto = autoMode }
		if not autoMode then
			payload.subPrice = subPrice
			payload.apiPrice = apiPrice
		end
		launching = true
		refresh()
		local ok, result = ModelsUI.call("ReleaseModel", payload)
		launching = false
		if ok then
			local f = forecast
			configuredFor = nil
			recKey = ""
			if Studio.mode ~= "launch" or Studio.token() ~= token then
				return -- the player closed the Computer while LAUNCHING…: the model is live, nothing re-opens
			end
			Studio.open("live", {
				modelId = id,
				target = target,
				marketing = marketing,
				auto = result.auto ~= false,
				sub = tonumber(result.subPrice) or subPrice,
				api = tonumber(result.apiPrice) or apiPrice,
				replacedName = if predecessor then `{predecessor.name} v{predecessor.version}` else nil,
				moved = math.floor(moved + 0.5),
				forecastUsers = if f then f.users else nil,
			})
		else
			refresh()
		end
	end

	Kit.onClick(launch, doLaunch)
	Kit.onClick(back, function()
		if step <= 1 then
			Studio.close()
		else
			step -= 1
			custom.Visible = false
			refresh()
		end
	end)
	-- the Custom card opens the stepper overlay
	Kit.onClick(campaigns.custom.option.tile.button, function()
		custom.Visible = true
		campaignId = "custom"
		refresh()
	end)

	local view = { frame = frame, title = "Launch Day" }
	function view.show(opts: any)
		local id = if typeof(opts.modelId) == "string" then opts.modelId else nil
		modelId = id
		step = if typeof(opts.step) == "number" then math.clamp(opts.step, 1, 3) else 1
		done = { false, false, false }
		launching = false
		custom.Visible = false
		local snapshot, model = snapshotModel()
		if snapshot and model and id and configuredFor ~= id then
			configure(snapshot, model, id)
		end
		requestRecommendation()
		updateForecast()
		refresh()
	end
	function view.hide()
		recGen += 1
		forecastGen += 1
		recKey = ""
	end
	function view.refresh(_snapshot: Snapshot)
		local _, model = snapshotModel()
		if model and model.status ~= "trained" and not launching then
			return
		end
		refresh()
	end
	function view.focus(): GuiObject?
		return launch
	end
	function view.primary()
		doLaunch()
	end
	function view.back()
		if step <= 1 then
			Studio.close()
		else
			step -= 1
			refresh()
		end
	end
	function view.step(delta: number)
		done[step] = true
		step = math.clamp(step + delta, 1, 3)
		refresh()
	end
	function view.setClass(isCompact: boolean)
		card.resize(if isCompact then Vector2.new(164, 262) else Vector2.new(180, 300))
		summary.Position = UDim2.fromOffset(if isCompact then 176 else 192, 0)
		summary.Size = UDim2.new(1, if isCompact then -176 else -192, 1, 0)
	end
	-- test hooks
	function view.state(): { [string]: any }
		return { target = target, marketing = marketing, auto = autoMode, sub = subPrice, api = apiPrice, step = step, campaign = campaignId }
	end
	function view.setStep(index: number)
		step = math.clamp(index, 1, 3)
		refresh()
	end
	return view
end

return LaunchDay
