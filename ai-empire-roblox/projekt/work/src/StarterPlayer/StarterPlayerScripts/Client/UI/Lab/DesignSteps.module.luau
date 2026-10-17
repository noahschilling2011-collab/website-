--!strict
-- Model Studio, DESIGN mode (LAB_SPEC 4.2-4.9): six steps, one decision per screen, like the Design Studio of
-- "Build a Phone Empire". Left: the cost badge, the live Model Card and the Expected panel (they change with
-- every tap); right: STEP N OF 6, a one-line hint and the option tiles with cost and the difference against the
-- current pick; bottom: tappable step chips, BACK and the primary button (CONTINUE / START TRAINING / the fix).
-- Every number comes from LabPreview (= the server's own maths on the real snapshot).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local ModelConfig = require(Shared.Config.ModelConfig)
local MarketConfig = require(Shared.Config.MarketConfig)
local CompanyConfig = require(Shared.Config.CompanyConfig)
local DataConfig = require(Shared.Config.DataConfig)
local ModelMath = require(Shared.ModelMath)
local MarketMath = require(Shared.MarketMath)
local Format = require(Shared.Format)
local Types = require(Shared.Types)

local UI = script.Parent.Parent
local Client = UI.Parent
local StateController = require(Client.Controllers.StateController)
local ActionController = require(Client.Controllers.ActionController)
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Toast = require(UI.Toast)
local Parts = require(script.Parent.StudioParts)
local LabPreview = require(script.Parent.LabPreview)
local LabState = require(script.Parent.LabState)
local ModelsUI = require(UI.Apps.ModelsUI)
local ShopMath = require(Shared.ShopMath) -- shop package: the 7B lock strip (SHOP_SPEC 5.2.4), Kit looks (5.2.6)
local ShopCore = require(UI.Shop.ShopCore)

local C = Theme.colors
local F = Theme.font

type Snapshot = Types.Snapshot
type PlayerData = Types.PlayerData
type Sel = LabPreview.Sel

local DesignSteps = {}

local STEP_TITLES = { "Product", "Brain size", "Skill focus", "Training plan", "Name & look", "Final review" }
local STEP_HINTS = {
	"Who is it for? You can still change the line at launch.",
	"Bigger = smarter, but needs more VRAM, data and servers.",
	"Focus shifts skills (in %) and changes who likes the model.",
	"More compute gives a better model, if you have enough data.",
	"", -- live: "Becomes Sage v2 · looks never change the score"
	"Check it, then start. The real score is revealed at the end.",
}
local CORE = { "reasoning", "coding", "math", "creativity", "knowledge", "reliability" }

local function trim(text: string): string
	return string.match(text, "^%s*(.-)%s*$") or ""
end

local function validName(text: string): boolean
	local length = utf8.len(trim(text))
	return length ~= nil and length >= GameConfig.MODEL_NAME_MIN and length <= GameConfig.MODEL_NAME_MAX
end

local function statLabel(id: string): string
	for _, stat in ModelConfig.STATS do
		if stat.id == id then
			return stat.label
		end
	end
	return id
end

-- "+ Coding 18 · Reasoning 4", "− Creativity 12 · Knowledge 6" from the focus multipliers (in %)
local function focusLines(focus: ModelConfig.FocusDef): (string, string)
	type Part = { name: string, value: number }
	local plus: { Part }, minus: { Part } = {}, {}
	for _, stat in ModelConfig.STATS do
		local mult = focus.mult[stat.id]
		if mult and mult > 1 then
			table.insert(plus, { name = stat.label, value = math.floor((mult - 1) * 100 + 0.5) })
		elseif mult and mult < 1 then
			table.insert(minus, { name = stat.label, value = math.floor((1 - mult) * 100 + 0.5) })
		end
	end
	table.sort(plus, function(a: Part, b: Part): boolean
		return a.value > b.value
	end)
	table.sort(minus, function(a: Part, b: Part): boolean
		return a.value > b.value
	end)
	local function join(list: { Part }): string
		local parts = {}
		for _, p in list do
			table.insert(parts, `{p.name} {p.value}`)
		end
		return table.concat(parts, " · ")
	end
	if #plus == 0 and #minus == 0 then
		return "No bonus, no weakness", "All skills at 100 %"
	end
	return "+ " .. join(plus), "− " .. join(minus)
end

-- the two highest weights of a segment: "Wants Coding + Reasoning"
local function wants(segment: MarketConfig.SegmentDef): string
	type W = { id: string, w: number }
	local list: { W } = {}
	for id, w in segment.weights do
		if id ~= "speed" then
			table.insert(list, { id = id, w = w })
		end
	end
	table.sort(list, function(a: W, b: W): boolean
		return a.w > b.w
	end)
	local a = if list[1] then statLabel(list[1].id) else "?"
	local b = if list[2] then statLabel(list[2].id) else "?"
	return `Wants {a} + {b}`
end

local function focusColorId(data: PlayerData, focusId: string): string
	if focusId == "coding" then
		return "blue"
	elseif focusId == "reasoning" then
		return "violet"
	elseif focusId == "creative" then
		return "amber"
	end
	local company = data.company
	return if company and CompanyConfig.getColor(company.color) then company.color else "cyan"
end

local function logoIndex(data: PlayerData): number
	local company = data.company
	-- shop package: an Identity Kit company logo is an index after LOGOS (CompanyConfig.allLogos)
	local index = if company then table.find(CompanyConfig.allLogos(), company.logo) else nil
	return index or #CompanyConfig.LOGOS
end

-- shop package (SHOP_SPEC 5.2.6): owns the Identity Kit (its pass or the Style Collection)
local function ownsKit(snapshot: Snapshot): boolean
	local shop = (snapshot.live :: any).shop
	return ShopMath.ownsPass(if typeof(shop) == "table" then shop.passes else nil, CompanyConfig.KIT_PASS)
end

function DesignSteps.build(Studio: any): any
	local body: Frame = Studio.body
	local frame = Kit.frame(body)
	frame.Name = "DesignView"
	local main = Kit.frame(frame, UDim2.new(1, 0, 1, -82))
	local bottom = Kit.frame(frame, UDim2.new(1, 0, 0, 74), UDim2.new(0, 0, 1, -74))

	---------------------------------------------------------------- preview zone
	local preview = Kit.frame(main, UDim2.new(1, -734, 1, 0), UDim2.fromOffset(16, 0))
	preview.Name = "Preview"
	local badge = Parts.costBadge(preview)
	local card = Parts.modelCard(preview, Vector2.new(190, 246))
	card.frame.Position = UDim2.fromOffset(0, 90)
	local expPanel = Parts.panel(preview, UDim2.fromOffset(206, 90), UDim2.new(1, -206, 0, 246))
	expPanel.Name = "Expected"
	-- top row: caption left, range right; the big expected value below; then "vs your best" and the stat bars
	local expCaption = Parts.label(expPanel, "EXPECTED", 20, F.bold, C.muted, UDim2.fromOffset(14, 6), UDim2.new(1, -28, 0, 24))
	local rangeLabel = Parts.label(expPanel, "", 20, F.medium, C.muted, UDim2.fromOffset(14, 6), UDim2.new(1, -28, 0, 24), Enum.TextXAlignment.Right)
	local big = Parts.label(expPanel, "~0.0", 52, F.display, Theme.accent, UDim2.fromOffset(12, 28), UDim2.new(1, -24, 0, 58))
	big.Name = "ExpectedValue"
	big.TextTruncate = Enum.TextTruncate.None
	local vsBest = Parts.label(expPanel, "", 22, F.bold, C.good, UDim2.fromOffset(14, 86), UDim2.new(1, -28, 0, 26))
	vsBest.TextScaled = true -- "+19.9 vs best · with plan" shrinks to 20 px before it truncates
	local vsFit = Instance.new("UITextSizeConstraint")
	vsFit.MinTextSize = 20
	vsFit.MaxTextSize = 22
	vsFit.Parent = vsBest
	local bars = Parts.statBars(expPanel, CORE, 21, 112, UDim2.fromOffset(14, 116), UDim.new(1, -28))
	local specSheet = Parts.panel(preview, UDim2.fromOffset(0, 372), UDim2.new(1, 0, 0, 92))
	specSheet.Name = "SpecSheet"
	local spec1 = Parts.label(specSheet, "", 20, F.medium, C.muted, UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 30))
	local spec2 = Parts.label(specSheet, "", 20, F.medium, C.muted, UDim2.fromOffset(16, 48), UDim2.new(1, -32, 0, 30))

	---------------------------------------------------------------- right panel
	local panel = Parts.panel(main, UDim2.new(1, -702, 0, 0), UDim2.new(0, 686, 1, 0))
	panel.Name = "StepPanel"
	local title = Parts.label(panel, "", 34, F.display, C.text, UDim2.fromOffset(18, 10), UDim2.new(1, -250, 0, 42))
	local stepLabel = Parts.label(panel, "STEP 1 OF 6", 20, F.bold, Theme.accent, UDim2.fromOffset(18, 16), UDim2.new(1, -36, 0, 30), Enum.TextXAlignment.Right)
	local hint = Parts.label(panel, "", 22, F.medium, C.muted, UDim2.fromOffset(18, 54), UDim2.new(1, -36, 0, 28))
	hint.Name = "Hint"
	hint.RichText = true
	local stepBody = Kit.frame(panel, UDim2.new(1, -32, 1, -100), UDim2.fromOffset(16, 90))
	stepBody.Name = "StepBody"
	-- regular layout (desktop): one explanatory footnote under the tiles
	local footnote = Parts.label(stepBody, "", 20, F.medium, C.dim, UDim2.new(0, 0, 1, -52), UDim2.new(1, 0, 0, 52))
	footnote.Name = "Footnote"
	footnote.TextWrapped = true
	footnote.TextYAlignment = Enum.TextYAlignment.Bottom
	footnote.TextTruncate = Enum.TextTruncate.None
	local bodies: { Frame } = {}
	for i = 1, 6 do
		local f = Kit.frame(stepBody)
		f.Name = "Step" .. i
		f.Visible = false
		bodies[i] = f
	end

	---------------------------------------------------------------- state
	local step = 1
	local done = { false, false, false, false, false, false }
	local busy: string? = nil -- "start" | "buy" (a data purchase stays busy until a snapshot shows the new data)
	local buyKey: string? = nil -- data summary before the last BUY DATA PLAN
	local buyToken = 0
	local buyHold = false -- the first 0.6 s after a purchase: the second tap of a double tap must not START either
	local started = false -- START succeeded: the next DESIGN NEW MODEL starts at step 1 again
	-- a suggestion's data plan (SUGGESTED tile, line SUCCESSOR, "Design its successor"): offered on the Review as
	-- BUY DATA PLAN before START; `offer` is the exact plan of the suggestion while its selection and the data match
	local planMode = false
	local planOn = true
	local offer: { plan: LabPreview.DataPlan, selKey: string, dataKey: string }? = nil
	local shownPlan: LabPreview.DataPlan? = nil -- the plan BUY DATA PLAN buys (set by refresh)
	local nameBad = false
	local breakdownOpen = false
	local action: string? = nil
	local lastEstimate: LabPreview.Estimate? = nil
	local planCache: { key: string, plan: LabPreview.DataPlan }? = nil
	local compact = true
	local refresh: () -> () = function() end
	local studioLock: (Snapshot, Sel, number, any) -> string = function(_s: Snapshot, _sel: Sel, _m: number, _st: any): string return "" end
	local focusNow: () -> GuiObject? = function(): GuiObject? return nil end

	local function sel(): Sel
		local ui = StateController.ui
		return { sizeId = ui.sizeId, focusId = ui.focusId, recipeId = ui.recipeId or "steady" }
	end

	local function saveMode(snapshot: Snapshot): boolean
		local ops: any = snapshot.live.ops
		return typeof(ops) == "table" and ops.saveMode == true
	end

	local function dataKey(data: PlayerData): string
		local summary = ModelMath.dataSummary(data.data)
		return `{summary.total}|{summary.quality}`
	end

	local function selKey(s: Sel): string
		return `{s.sizeId}|{s.focusId}|{s.recipeId}`
	end

	local function dataPlan(data: PlayerData, s: Sel, money: number): LabPreview.DataPlan
		local summary = ModelMath.dataSummary(data.data)
		local key = `{s.sizeId}|{s.focusId}|{s.recipeId}|{summary.total}|{summary.quality}|{math.floor(money / 100)}`
		local cache = planCache
		if cache and cache.key == key then
			return cache.plan
		end
		local plan = LabPreview.dataPlan(data, s, money)
		planCache = { key = key, plan = plan }
		return plan
	end

	---------------------------------------------------------------- step 1: product line
	type LineTile = { option: Parts.OptionTile, tag: TextLabel, status: TextLabel }
	local lineTiles: { [string]: LineTile } = {}
	for i, line in ModelConfig.LINES do
		local col, row = (i - 1) % 2, (i - 1) // 2
		local option = Parts.optionTile(bodies[1], "Line_" .. line.target, UDim2.fromOffset(col * 333, row * 120), Vector2.new(321, 108), 1, 26, 24)
		local tag = Parts.tag(option.tile.button, "FREE", C.muted, UDim2.fromOffset(16, 72))
		tag.AutomaticSize = Enum.AutomaticSize.None
		tag.Size = UDim2.fromOffset(86, 28)
		-- "LIVE v2" needs ~72 px at 20 px bold: narrower side padding keeps it inside the 86 px chip
		local tagPad = tag:FindFirstChildOfClass("UIPadding")
		if tagPad then
			tagPad.PaddingLeft = UDim.new(0, 4)
			tagPad.PaddingRight = UDim.new(0, 4)
		end
		tag.TextXAlignment = Enum.TextXAlignment.Center
		local status = Parts.label(option.tile.button, "", 20, F.medium, C.muted, UDim2.fromOffset(110, 72), UDim2.new(1, -120, 0, 28))
		lineTiles[line.target] = { option = option, tag = tag, status = status }
		Kit.onClick(option.tile.button, function()
			LabState.lineId = line.target
			refresh()
		end)
	end

	---------------------------------------------------------------- step 2: size
	type Preset = { button: TextButton, stroke: UIStroke, name: TextLabel, detail: TextLabel }
	local presets: { [string]: Preset } = {}
	local presetX = { 0, 214, 470 }
	local presetW = { 204, 246, 184 }
	for i, def in { { "cheapest", "CHEAPEST" }, { "best", "BEST I CAN AFFORD" }, { "last", "SAME AS LAST" } } do
		local tile = Parts.tileButton(bodies[2], "Preset_" .. def[1], UDim2.fromOffset(presetX[i], 0), UDim2.fromOffset(presetW[i], 74), def[2])
		local name = Parts.label(tile.button, def[2], 20, F.bold, C.text, UDim2.fromOffset(10, 8), UDim2.new(1, -20, 0, 26), Enum.TextXAlignment.Center)
		local detail = Parts.label(tile.button, "", 20, F.medium, C.muted, UDim2.fromOffset(10, 38), UDim2.new(1, -20, 0, 26), Enum.TextXAlignment.Center)
		presets[def[1]] = { button = tile.button, stroke = tile.stroke, name = name, detail = detail }
	end
	-- shop package (SHOP_SPEC 5.2.4): the lock strip that replaces the presets while the picked size is locked by
	-- Frontier Architecture: OPEN RESEARCH › (free deep link) and, only when Frontier is the ONLY lock, SKIP RESEARCH ·
	-- EUREKA in the price-chip look (never the primary); or OPEN GPUs › when VRAM / a GPU is the other need
	-- fix round 1 (review): the Robux button is never wider than the free action next to it (equal widths), and on the
	-- Review (step 6) the strip has no OPEN RESEARCH › of its own (the primary is that same free deep link)
	type LockStrip = { frame: Frame, research: TextButton, gpus: TextButton, offer: ShopCore.OfferButton, review: boolean }
	local function lockStrip(parent: Instance, review: boolean): LockStrip
		local f = Kit.frame(parent, UDim2.new(1, 0, 0, 74))
		f.Name = "LockStrip"
		f.Visible = false
		f.ZIndex = 2
		local research = Parts.button(f, "OPEN RESEARCH ›", "secondary", UDim2.fromOffset(0, 0), UDim2.fromOffset(228, 74), 20)
		research.Name = "OpenResearch"
		local gpus = Parts.button(f, "OPEN GPUs ›", "secondary", UDim2.fromOffset(238, 0), UDim2.fromOffset(200, 74), 20)
		gpus.Name = "OpenGpus"
		gpus.Visible = false
		-- the short label fits the equal-width slot on a phone ("SKIP RESEARCH · EUREKA | R$ 15" needs ~370 px)
		local offer = ShopCore.offerButton(f, "SKIP · EUREKA", UDim2.new(1, -238, 0, 74), 20)
		offer.button.Name = "SkipResearch"
		offer.button.Position = UDim2.fromOffset(238, 0)
		offer.set(nil, "")
		research.Visible = not review
		return { frame = f, research = research, gpus = gpus, offer = offer, review = review }
	end
	local lockStrip2 = lockStrip(bodies[2], false)
	local lockStrip6 = lockStrip(bodies[6], true)
	type SizeTile = { tile: Parts.TileButton, label: TextLabel, tier: Parts.TierBar, cost: TextLabel, delta: TextLabel, time: TextLabel, warn2: TextLabel, vram: TextLabel, check: Frame }
	local sizeTiles: { [string]: SizeTile } = {}
	for i, size in ModelConfig.SIZES do
		local tile = Parts.tileButton(bodies[2], "Size_" .. size.id, UDim2.fromOffset((i - 1) * 132, 84), UDim2.fromOffset(122, 152), size.label)
		local b = tile.button
		local label = Parts.label(b, size.label, 32, F.display, C.text, UDim2.fromOffset(12, 6), UDim2.new(1, -20, 0, 36))
		local tier = Parts.tierBar(b, UDim2.fromOffset(12, 46), 98)
		tier.set(i)
		local cost = Parts.label(b, "", 22, F.bold, C.text, UDim2.fromOffset(12, 58), UDim2.new(1, -16, 0, 26))
		local delta = Parts.label(b, "", 22, F.bold, C.muted, UDim2.fromOffset(12, 84), UDim2.new(1, -16, 0, 26))
		local time = Parts.label(b, "", 20, F.medium, C.muted, UDim2.fromOffset(12, 110), UDim2.new(1, -16, 0, 24))
		local warn2 = Parts.label(b, "", 20, F.bold, C.warn, UDim2.fromOffset(12, 128), UDim2.new(1, -16, 0, 22))
		local vram = Parts.label(b, `{size.vram} GB`, 20, F.medium, C.dim, UDim2.fromOffset(12, 154), UDim2.new(1, -16, 0, 24))
		local check = Parts.check(b, UDim2.new(1, -42, 1, -42))
		check.Visible = false
		sizeTiles[size.id] = { tile = tile, label = label, tier = tier, cost = cost, delta = delta, time = time, warn2 = warn2, vram = vram, check = check }
		Kit.onClick(b, function()
			StateController.setSelection(size.id, StateController.ui.focusId)
		end)
	end

	---------------------------------------------------------------- step 3: focus
	type FocusTile = { option: Parts.OptionTile, edge: Frame }
	local focusTiles: { [string]: FocusTile } = {}
	for i, focus in ModelConfig.FOCUSES do
		local col, row = (i - 1) % 2, (i - 1) // 2
		local option = Parts.optionTile(bodies[3], "Focus_" .. focus.id, UDim2.fromOffset(col * 333, row * 124), Vector2.new(321, 112), 3, 22, 24)
		option.check.Visible = false
		local edge = Parts.box(option.tile.button, UDim2.new(), UDim2.new(0, 6, 1, 0), Parts.focusColor(focus.id), 0, 0)
		-- BEST FIT is part of the fit line (rich text), so nothing overlaps the 22 px rows on a phone
		option.lines[3].RichText = true
		focusTiles[focus.id] = { option = option, edge = edge }
		Kit.onClick(option.tile.button, function()
			StateController.setSelection(StateController.ui.sizeId, focus.id)
		end)
	end

	---------------------------------------------------------------- step 4: training plan + data strip
	local recipeTiles: { [string]: Parts.OptionTile } = {}
	for i, recipeId in { "rapid", "steady", "deep" } do
		local option = Parts.optionTile(bodies[4], "Recipe_" .. recipeId, UDim2.fromOffset((i - 1) * 222, 0), Vector2.new(210, 150), 4, 25, 24)
		option.check.Position = UDim2.new(1, -44, 0, 10)
		recipeTiles[recipeId] = option
		Kit.onClick(option.tile.button, function()
			StateController.setRecipe(recipeId)
		end)
	end
	local strip = Parts.box(bodies[4], UDim2.fromOffset(0, 162), UDim2.new(1, 0, 0, 74), C.panel2, 0, 14)
	strip.Name = "DataStrip"
	local strip1 = Parts.label(strip, "", 22, F.bold, C.text, UDim2.fromOffset(16, 4), UDim2.new(1, -350, 0, 28))
	local strip2 = Parts.label(strip, "", 20, F.medium, C.muted, UDim2.fromOffset(16, 30), UDim2.new(1, -350, 0, 24))
	local stripBar = Kit.bar(strip, 8, 0, C.good)
	stripBar.frame.Position = UDim2.fromOffset(16, 58)
	stripBar.frame.Size = UDim2.new(1, -350, 0, 8)
	local buyPlan = Parts.button(strip, "", "secondary", UDim2.new(1, -330, 0, 0), UDim2.fromOffset(190, 74), 20)
	buyPlan.Name = "BuyDataPlan"
	buyPlan.TextSize = 20
	local addData = Parts.button(strip, "+ DATA", "secondary", UDim2.new(1, -130, 0, 0), UDim2.fromOffset(130, 74), 24)
	addData.Name = "AddData"

	---------------------------------------------------------------- step 5: name & look
	local nameBox = Kit.input(bodies[5], "Model name", UDim2.fromOffset(430, 74))
	nameBox.Name = "NameBox"
	nameBox.TextSize = 30
	nameBox.Selectable = true
	local nameStroke = nameBox:FindFirstChildOfClass("UIStroke")
	local randomName = Parts.button(bodies[5], "RANDOM NAME", "secondary", UDim2.fromOffset(442, 0), UDim2.fromOffset(212, 74), 22)
	randomName.Name = "RandomName"
	-- shop package (SHOP_SPEC 5.2.6): colours and emblems sit in horizontal rows that scroll, so the 8 Identity Kit
	-- colours and 6 Kit logos can follow the free ones (with a small lock for non-owners, no buy button)
	local function lookRow(name: string, y: number): ScrollingFrame
		local row = Instance.new("ScrollingFrame")
		row.Name = name
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.Position = UDim2.fromOffset(0, y)
		row.Size = UDim2.new(1, 0, 0, 78)
		row.CanvasSize = UDim2.new()
		row.AutomaticCanvasSize = Enum.AutomaticSize.X
		row.ScrollingDirection = Enum.ScrollingDirection.X
		row.ScrollBarThickness = 3
		row.ScrollBarImageTransparency = 0.6
		row.HorizontalScrollBarInset = Enum.ScrollBarInset.None
		row.Parent = bodies[5]
		local list = Kit.list(row, 8, true)
		list.VerticalAlignment = Enum.VerticalAlignment.Top
		return row
	end
	local colorRow = lookRow("ColorRow", 81)
	local emblemRow = lookRow("EmblemRow", 162)
	local function lockBadge(parent: Instance): Frame
		local l = Kit.frame(parent, UDim2.fromOffset(28, 28), UDim2.new(1, -4, 1, -4))
		l.Name = "Lock"
		l.AnchorPoint = Vector2.new(1, 1)
		l.BackgroundTransparency = 0.1
		l.BackgroundColor3 = C.bg
		Kit.corner(l, 8)
		local icon = Kit.icon(l, "lock", 16)
		icon.frame.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.frame.Position = UDim2.fromScale(0.5, 0.5)
		icon.setColor(C.text)
		l.Visible = false
		return l
	end
	type Swatch = { tile: Parts.TileButton, check: Frame, lock: Frame?, kit: boolean }
	local swatches: { [string]: Swatch } = {}
	local allColors: { CompanyConfig.ColorDef } = table.clone(CompanyConfig.COLORS)
	for _, def in CompanyConfig.KIT_COLORS do
		table.insert(allColors, def)
	end
	for i, def in allColors do
		local kit = i > #CompanyConfig.COLORS
		local tile = Parts.tileButton(colorRow, "Color_" .. def.id, UDim2.fromOffset((i - 1) * 82, 0), UDim2.fromOffset(74, 74), def.id)
		tile.button.LayoutOrder = i
		tile.button.BackgroundColor3 = Theme.rgb(def.rgb)
		local check = Parts.check(tile.button, UDim2.fromOffset(20, 20))
		check.BackgroundColor3 = C.bg
		-- the badge is dark on the colour swatch, so its glyph must be light (Parts.check draws it in C.bg)
		local glyph = check:FindFirstChildWhichIsA("TextLabel")
		if glyph then
			glyph.TextColor3 = C.text
		end
		check.Visible = false
		local lock = if kit then lockBadge(tile.button) else nil
		swatches[def.id] = { tile = tile, check = check, lock = lock, kit = kit }
		Kit.onClick(tile.button, function()
			local snapshot = StateController.snapshot
			if kit and snapshot and not ownsKit(snapshot) then
				Toast.show("info", "This colour comes with Identity Kit.")
				return
			end
			LabState.colorId = def.id
			refresh()
		end)
	end
	local kitLine = Parts.label(colorRow, "More colours with Identity Kit (Shop)", 20, F.medium, C.dim, UDim2.new(), UDim2.fromOffset(250, 74))
	kitLine.Name = "KitLine"
	kitLine.TextWrapped = true
	kitLine.LayoutOrder = 99
	type EmblemTile = { tile: Parts.TileButton, lock: Frame?, kit: boolean }
	local emblems: { EmblemTile } = {}
	for i, glyph in CompanyConfig.allLogos() do
		local kit = i > #CompanyConfig.LOGOS
		local tile = Parts.tileButton(emblemRow, "Emblem_" .. i, UDim2.fromOffset((i - 1) * 82, 0), UDim2.fromOffset(74, 74), glyph)
		tile.button.LayoutOrder = i
		local label = Parts.label(tile.button, Parts.glyph(glyph), 30, F.bold, C.text, UDim2.new(), UDim2.fromScale(1, 1), Enum.TextXAlignment.Center)
		label.TextTruncate = Enum.TextTruncate.None
		local lock = if kit then lockBadge(tile.button) else nil
		emblems[i] = { tile = tile, lock = lock, kit = kit }
		Kit.onClick(tile.button, function()
			local snapshot = StateController.snapshot
			if kit and snapshot and not ownsKit(snapshot) then
				Toast.show("info", "This logo comes with Identity Kit.")
				return
			end
			if snapshot and LabState.colorId == nil then
				LabState.colorId = focusColorId(snapshot.data, StateController.ui.focusId)
			end
			LabState.emblem = i
			refresh()
		end)
	end
	local lookNote = Parts.label(bodies[5], "Colour and emblem are looks only and are saved with the model.", 20, F.medium, C.dim, UDim2.fromOffset(0, 246), UDim2.new(1, 0, 0, 26))

	---------------------------------------------------------------- step 6: review
	type Money = { frame: Frame, caption: TextLabel, value: TextLabel }
	local moneyTiles: { Money } = {}
	for i = 1, 3 do
		local f = Parts.box(bodies[6], UDim2.fromOffset((i - 1) * 222, 0), UDim2.fromOffset(210, 80), C.panel2, 0, 14)
		local caption = Parts.label(f, "", 20, F.bold, C.muted, UDim2.fromOffset(16, 8), UDim2.new(1, -24, 0, 24))
		local value = Parts.label(f, "", 30, F.display, C.text, UDim2.fromOffset(16, 34), UDim2.new(1, -24, 0, 38))
		moneyTiles[i] = { frame = f, caption = caption, value = value }
	end
	-- a suggestion's data plan: tile 2 becomes an ON/OFF toggle (skip the plan and train on today's data)
	local planToggle = Parts.tileButton(bodies[6], "PlanToggle", UDim2.fromOffset(222, 0), UDim2.fromOffset(210, 80), "DATA PLAN")
	planToggle.button.Visible = false
	local toggleCaption = Parts.label(planToggle.button, "DATA PLAN", 20, F.bold, C.muted, UDim2.fromOffset(16, 8), UDim2.new(1, -24, 0, 24))
	local toggleValue = Parts.label(planToggle.button, "", 26, F.display, C.text, UDim2.fromOffset(16, 36), UDim2.new(1, -24, 0, 34))
	local linesTile = Parts.tileButton(bodies[6], "ReviewLines", UDim2.fromOffset(0, 92), UDim2.new(1, 0, 0, 144), "BREAKDOWN")
	local reviewLines: { TextLabel } = {}
	for i = 1, 4 do
		local line = Parts.label(linesTile.button, "", 22, F.medium, C.text, UDim2.fromOffset(16, 8 + (i - 1) * 33), UDim2.new(1, if i == 3 then -170 else -32, 0, 30))
		line.RichText = true
		reviewLines[i] = line
	end
	local breakdownCue = Parts.label(linesTile.button, "BREAKDOWN ›", 20, F.bold, Theme.accent, UDim2.new(1, -186, 0, 76), UDim2.fromOffset(170, 26), Enum.TextXAlignment.Right)
	local breakdown = Parts.tileButton(bodies[6], "Breakdown", UDim2.new(), UDim2.new(1, 0, 1, 0), "CLOSE BREAKDOWN")
	breakdown.button.Visible = false
	breakdown.button.ZIndex = 5
	local breakdownLines: { TextLabel } = {}
	for i = 1, 6 do
		local line = Parts.label(breakdown.button, "", 20, F.medium, if i == 1 then C.text else C.muted, UDim2.fromOffset(18, 8 + (i - 1) * 30), UDim2.new(1, -36, 0, 28))
		line.ZIndex = 6
		line.TextWrapped = true
		breakdownLines[i] = line
	end

	---------------------------------------------------------------- bottom bar
	local chips = Parts.stepChips(Kit.frame(bottom, UDim2.new(1, -734, 1, 0), UDim2.fromOffset(16, 0)), 6, function(index: number)
		step = index
		breakdownOpen = false
		refresh()
		Studio.select(focusNow())
	end)
	chips.buttons[6]:SetAttribute("Width", 110)
	local back = Parts.button(bottom, "‹ BACK", "secondary", UDim2.new(1, -702, 0, 0), UDim2.fromOffset(180, 74), 26)
	back.Name = "Back"
	local primary = Parts.button(bottom, "CONTINUE ›", "primary", UDim2.new(1, -510, 0, 0), UDim2.fromOffset(494, 74), 26)
	primary.Name = "Primary"

	---------------------------------------------------------------- actions
	local function goStep(index: number)
		step = math.clamp(index, 1, 6)
		breakdownOpen = false
		refresh()
		Studio.select(focusNow())
	end

	local function closeTo(app: string)
		local nav = Studio.nav
		Studio.close()
		if nav and nav.isOpen() then
			nav.show(app)
		end
	end

	-- shop package (SHOP_SPEC 5.2.4): OPEN RESEARCH › = Lab → Research with the Frontier card outlined (free)
	local function openResearch()
		local nav = Studio.nav
		ShopCore.requestFocus("research", "frontier")
		Studio.close()
		if nav and nav.isOpen() then
			if (nav :: any).route then
				(nav :: any).route("open:empire/research")
			else
				nav.show("empire")
			end
		end
	end
	-- the lock strip's state (both steps) and the warn hint of step 2: Frontier is the only lock -> the Eureka offer
	-- (ShopMath.studioEurekaOffer); another lock after it -> name it, and OPEN GPUs › for VRAM / no GPU
	local stripActions: { [LockStrip]: boolean } = {}
	studioLock = function(snapshot: Snapshot, sel: Sel, money: number, strip: LockStrip): string
		local data = snapshot.data
		local size = ModelConfig.getSize(sel.sizeId) or ModelConfig.SIZES[1]
		local def = ModelConfig.getSize("s7b")
		local frontier = { cost = 65000, points = 500, seconds = 120 }
		for _, r in require(Shared.Config.EmpireConfig).RESEARCH do
			if r.id == "frontier" then frontier = { cost = r.cost, points = r.points, seconds = r.seconds } end
		end
		local ui = ShopCore.offerUi(snapshot, "eureka")
		local offer = ShopMath.studioEurekaOffer(data, sel, money, LabPreview.estimate, ui)
		local job = data.empire.researchJob
		local running = typeof(job) == "table" and job.id == "frontier"
		strip.offer.set(offer.state, if offer.state then select(3, ShopCore.offer(snapshot, "eureka")) else "")
		strip.offer.label.Text = if running then "FINISH · EUREKA" else "SKIP · EUREKA"
		local need = offer.need
		strip.gpus.Visible = need == "VRAM" or need == "NO_GPU"
		-- equal slots left to right: [OPEN RESEARCH ›] [OPEN GPUs ›] [SKIP RESEARCH · EUREKA]; the Review has no
		-- OPEN RESEARCH › here (its primary is the same link), and its Robux button takes half the strip at most
		local slots: { GuiObject } = {}
		if not strip.review then
			table.insert(slots, strip.research)
		end
		if strip.gpus.Visible then
			table.insert(slots, strip.gpus)
		end
		if strip.offer.button.Visible then
			table.insert(slots, strip.offer.button)
		end
		local count = math.max(2, #slots)
		for i, b in slots do
			b.Position = UDim2.new((i - 1) / count, if i > 1 then 5 else 0, 0, 0)
			b.Size = UDim2.new(1 / count, -5, 0, 74)
		end
		if not stripActions[strip] then
			stripActions[strip] = true
			Kit.onClick(strip.research, openResearch)
			Kit.onClick(strip.gpus, function()
				closeTo("compute")
			end)
			Kit.onClick(strip.offer.button, function()
				local snap = StateController.snapshot
				if not snap then return end
				local s2 = sel
				local after = LabPreview.estimate(ShopMath.withResearch(snap.data, "frontier"), s2, nil)
				local extra = { { caption = "Then", value = `{Parts.sizeLabel(s2.sizeId)} training costs {Parts.money(after.cost)}` } }
				local function done(ok: boolean)
					if ok then
						Toast.show("success", "7B is unlocked.", 4)
						refresh()
					end
				end
				if strip.offer.button:GetAttribute("OfferState") == "owned" then
					ShopCore.use("eureka", "frontier", { extra = extra, onDone = done })
				else
					ShopCore.buy("eureka", "frontier", { extra = extra, onDone = done })
				end
			end)
		end
		local label = size.label
		local base = `<b>{label} needs Frontier Architecture</b>`
		if running then
			return base .. string.format(" · researching now, %s left", Format.duration(job.seconds - job.elapsed))
		elseif need == "VRAM" then
			local est = LabPreview.estimate(data, sel, money)
			return base .. string.format(" + %d GB VRAM (have %d)", est.vramNeed, est.vramHave) -- one line on a phone
		elseif need == "NO_GPU" then
			return base .. " + a GPU"
		elseif need == "MONEY" then
			return base .. string.format(" + cash: %s and its training", Parts.money(frontier.cost))
		elseif need == "MODEL_LIMIT" then
			return base .. " + a free model slot"
		elseif need == "NO_DATA" then
			return base .. " + more training data"
		elseif need == "TRAINING" then
			return base .. " · training slot busy now"
		end
		local _ = def
		-- fix round 1 (review): with a Eureka offer the line says what it saves (SHOP_SPEC 5.2.4, ShopMath.savingText) and
		-- the cash both ways still cost; short enough for one phone line (the RP are what the Eureka covers)
		local check = offer.check
		if offer.state ~= nil and check and check.ok then
			return `<b>{label} needs Frontier</b>` .. string.format(" · %s · Eureka saves %s", Parts.money(frontier.cost), ShopMath.savingText(check.seconds))
		end
		return base .. string.format(" · %s · %d RP · %s", Parts.money(frontier.cost), frontier.points, Format.duration(frontier.seconds))
	end

	-- The reply of a remote call may arrive after the player left the Studio (× while STARTING…): then nothing
	-- switches modes or routes (Studio.open would re-bind input behind a closed Computer).
	local function stillHere(token: number): boolean
		return Studio.mode == "design" and Studio.token() == token
	end

	local function buyDataPlan(plan: LabPreview.DataPlan?)
		local snapshot = StateController.snapshot
		if busy or not snapshot or not plan or plan.cost <= 0 then
			return
		end
		busy = "buy"
		local before = dataKey(snapshot.data)
		refresh()
		local bought = 0
		for _, packId in plan.order do
			local left = plan.packs[packId] or 0
			local failed = false
			while left > 0 do
				local count = math.min(left, DataConfig.MAX_BUY)
				local ok = ActionController.call("BuyData", { packId = packId, count = count })
				if not ok then
					failed = true
					break
				end
				bought += 1
				left -= count
			end
			if failed then
				break
			end
		end
		planCache = nil
		if bought > 0 then
			-- the suggestion's plan is used up; the button stays BUYING DATA… until a snapshot carries the new data
			-- (a second tap before the State update must not buy the plan again), at most 3 s
			planMode, offer = false, nil
			buyKey = before
			buyHold = true
			buyToken += 1
			local token = buyToken
			task.delay(0.6, function()
				if buyToken == token then
					buyHold = false
					refresh()
				end
			end)
			task.delay(3, function()
				if buyKey ~= nil and buyToken == token then
					buyKey = nil
					busy = nil
					refresh()
				end
			end)
		else
			busy = nil
		end
		refresh()
	end

	local function startTraining()
		local snapshot = StateController.snapshot
		if busy or not snapshot then
			return
		end
		local token = Studio.token()
		local data = snapshot.data
		local s = sel()
		local name = trim(nameBox.Text)
		local payload: { [string]: any } = {
			name = name,
			sizeId = s.sizeId,
			focusId = s.focusId,
			recipeId = s.recipeId,
			target = LabState.lineId,
		}
		local look = LabState.look(logoIndex(data))
		if look then
			payload.look = look
		end
		busy = "start"
		refresh()
		local ok, result = ActionController.call("StartTraining", payload)
		busy = nil
		if ok and typeof(result.modelId) == "string" then
			LabState.plannedLine[result.modelId] = LabState.lineId
			LabState.name = ""
			-- a picked look belongs to this model: the next design starts with the focus colour again
			LabState.colorId = nil
			LabState.emblem = nil
			done = { false, false, false, false, false, false }
			started = true
			LabState.step = 1 -- the next DESIGN NEW MODEL starts at step 1 (also when the Computer closed meanwhile)
			planMode, offer = false, nil
			if stillHere(token) then
				Studio.open("training", { starting = result.modelId })
			end
			return
		end
		if not stillHere(token) then
			return
		end
		local err = result.err
		if err == "BAD_NAME" or err == "NAME_FILTERED" or err == "FILTER_DOWN" then
			nameBad = true
			goStep(5)
		elseif err == "VRAM" or err == "NO_GPU" then
			closeTo("compute")
		elseif err == "PREREQUISITE" then
			openResearch()
		elseif err == "NO_DATA" then
			local plan = dataPlan(data, s, StateController.money())
			if plan.cost > 0 then
				goStep(6)
			else
				closeTo("data")
			end
		elseif err == "TRAINING_ACTIVE" then
			Studio.open("training", {})
		else
			refresh()
		end
	end

	local function runPrimary()
		if primary:GetAttribute("Disabled") == true then
			return
		end
		if step < 6 then
			done[step] = true
			goStep(step + 1)
			return
		end
		local snapshot = StateController.snapshot
		if not snapshot then
			return
		end
		if action == "start" then
			startTraining()
		elseif action == "buy" then
			buyDataPlan(shownPlan)
		elseif action == "name" then
			nameBad = true
			goStep(5)
		elseif action == "training" then
			Studio.open("training", {})
		elseif action == "research" then
			openResearch()
		elseif action == "empire" or action == "market" or action == "compute" or action == "data" then
			closeTo(action)
		end
	end

	Kit.onClick(primary, runPrimary)
	Kit.onClick(back, function()
		if step <= 1 then
			Studio.close()
		else
			goStep(step - 1)
		end
	end)
	local stripPlan: LabPreview.DataPlan? = nil -- the step-4 strip's plan (set by refresh)
	Kit.onClick(buyPlan, function()
		buyDataPlan(stripPlan)
	end)
	Kit.onClick(planToggle.button, function()
		if busy then
			return
		end
		planOn = not planOn
		refresh()
	end)
	Kit.onClick(addData, function()
		LabState.step = step
		closeTo("data")
	end)
	Kit.onClick(randomName, function()
		local name = LabState.nextName()
		nameBox.Text = name
		LabState.name = name
		nameBad = false
		refresh()
	end)
	nameBox:GetPropertyChangedSignal("Text"):Connect(function()
		LabState.name = nameBox.Text
		if step == 5 and Studio.mode == "design" then
			nameBad = not validName(nameBox.Text) and nameBad
			refresh()
		end
	end)
	nameBox.FocusLost:Connect(function(enterPressed: boolean)
		LabState.name = trim(nameBox.Text)
		if enterPressed and validName(nameBox.Text) then
			done[5] = true
		end
		refresh()
	end)
	Kit.onClick(presets.cheapest.button, function()
		StateController.setSelection("s100m", StateController.ui.focusId)
		StateController.setRecipe("rapid")
	end)
	Kit.onClick(presets.best.button, function()
		local snapshot = StateController.snapshot
		if not snapshot then
			return
		end
		local pick = LabPreview.bestAffordable(snapshot.data, StateController.ui.focusId, StateController.money(), saveMode(snapshot))
		if pick then
			StateController.setSelection(pick.sizeId, StateController.ui.focusId)
			StateController.setRecipe(pick.recipeId)
		else
			Toast.show("info", "Nothing fits your cash above the reserve right now.")
		end
	end)
	Kit.onClick(presets.last.button, function()
		local snapshot = StateController.snapshot
		local last = if snapshot then LabPreview.sameAsLast(snapshot.data) else nil
		if last then
			StateController.setSelection(last.sizeId, last.focusId)
			if last.recipeId then
				StateController.setRecipe(last.recipeId)
			end
		end
	end)
	Kit.onClick(linesTile.button, function()
		if compact then
			breakdownOpen = true
			refresh()
		end
	end)
	Kit.onClick(breakdown.button, function()
		breakdownOpen = false
		refresh()
	end)

	---------------------------------------------------------------- refresh
	refresh = function()
		local snapshot = StateController.snapshot
		if not snapshot or Studio.mode ~= "design" then
			return
		end
		local data = snapshot.data
		if busy == "buy" and buyKey ~= nil and dataKey(data) ~= buyKey and not buyHold then
			busy, buyKey = nil, nil -- the snapshot carries the bought data
		end
		local money = StateController.money()
		local s = sel()
		local est = LabPreview.estimate(data, s, money)
		lastEstimate = est
		local noData = est.lock == "NO_DATA"
		-- the data plan the Review shows: forced with no usable data (first model), offered for a suggestion
		local plan: LabPreview.DataPlan? = nil
		if noData then
			plan = dataPlan(data, s, money)
		elseif planMode and planOn then
			local o = offer
			plan = if o and o.selKey == selKey(s) and o.dataKey == dataKey(data) then o.plan else dataPlan(data, s, money)
		end
		local afterPlan = plan ~= nil and plan.cost > 0
		local planCost = if plan and afterPlan then plan.cost else 0
		-- every number of every step describes the same data: after the plan when one is shown
		local dview = if plan and afterPlan then LabPreview.withStock(data, plan.stock) else data
		local viewMoney = money - planCost
		local shown = if afterPlan then LabPreview.estimate(dview, s, nil) else est
		shownPlan = if afterPlan then plan else nil
		local line = ModelConfig.getLine(LabState.lineId) or ModelConfig.LINES[1]
		local segment = LabPreview.segmentOf(line.target)
		local best = LabPreview.bestOverall(data, nil)
		local first = LabPreview.isFirstModel(data)
		local name = trim(nameBox.Text)
		local version = LabPreview.nextVersion(data, if name ~= "" then name else "?")
		local company = data.company
		local reserve = LabPreview.reserve(data)

		-- cost badge + card + expected panel
		badge.set(est.cost, est.seconds, est.vramNeed, est.vramHave, est.rate > 0)
		local look = LabState.look(logoIndex(data))
		local beats = best > 0 and shown.overall > best
		card.set({
			sizeId = s.sizeId,
			focusId = s.focusId,
			name = if name ~= "" then name else "Unnamed",
			version = if name ~= "" then version else nil,
			lineShort = line.short,
			logo = if company then company.logo else "N",
			look = look,
			lit = if noData then 0 else LabPreview.litCores(s.sizeId, shown.readiness),
			recipeId = s.recipeId,
			overfit = shown.overfit,
			beatsBest = beats,
		})
		local lo, hi = LabPreview.range(shown.overall)
		big.Text = string.format("~%.1f", shown.overall)
		big.TextColor3 = card.color
		expCaption.Text = "EXPECTED"
		rangeLabel.Text = string.format("final %.1f–%.1f", lo, hi)
		if afterPlan and best > 0 then
			local d = shown.overall - best
			vsBest.Text = `{Parts.signed(d)} vs best · with plan`
			vsBest.TextColor3 = if d >= 0 then C.good else C.bad
		elseif afterPlan then
			vsBest.Text = "After the data plan"
			vsBest.TextColor3 = C.warn
		elseif best > 0 then
			local d = shown.overall - best
			vsBest.Text = `{Parts.signed(d)} vs your best ({string.format("%.1f", best)})`
			vsBest.TextColor3 = if d >= 0 then C.good else C.bad
		else
			vsBest.Text = "Your first model"
			vsBest.TextColor3 = C.good
		end
		bars.set(shown.stats, LabPreview.bestStats(data), card.color)
		local size = ModelConfig.getSize(s.sizeId) or ModelConfig.SIZES[1]
		if not compact then
			-- the real ceiling of this design (data mix, focus, plan, spec, research and Lab level included)
			local ideal = size.dataNeed * ModelConfig.DATA.maxFill
			spec1.Text = string.format("Ceiling ~%.1f with ideal data · %s tokens at 100%%", LabPreview.ceiling(data, s), Format.tokens(ideal))
			spec2.Text = `Serving {(MarketConfig.SERVE_UNITS or {})[size.id] or 1} units/user · {Format.price(size.serveCost)}/1M · speed {size.speed}`
		end

		-- panel header
		for i, f in bodies do
			f.Visible = i == step
		end
		title.Text = STEP_TITLES[step]
		stepLabel.Text = `STEP {step} OF 6`
		stepLabel.TextColor3 = Theme.accent
		hint.TextColor3 = C.muted
		hint.Text = STEP_HINTS[step]
		footnote.Visible = not compact and step ~= 5 and step ~= 6
		if step == 1 then
			footnote.Text = "A specialist owns its line: outside its product line a model loses about 18 fit points. A live line gets the next version."
		elseif step == 2 then
			footnote.Text = "Locked sizes stay visible with the reason and can still be picked; the Review offers the fix. White tick on a stat bar = your best so far."
		elseif step == 3 then
			footnote.Text = "Fit decides how many users in the line pick the model (before price). BEST FIT = the highest fit for the planned line."
		end

		if step == 1 then
			for _, def in ModelConfig.LINES do
				local refs = lineTiles[def.target]
				local seg = LabPreview.segmentOf(def.target)
				local status = LabPreview.lineStatus(data, def.target)
				local selected = def.target == line.target
				local fit = MarketMath.fit(shown.stats, seg)
				refs.option.set({
					title = (if selected then "✓ " else "") .. def.label,
					right = string.format("fit %.1f", fit),
					lines = { wants(seg) },
					selected = selected,
					locked = status.kind == "FULL",
				})
				local model = status.model
				if status.kind == "LIVE" and model then
					refs.tag.Text = `LIVE v{status.version or 1}`
					refs.tag.TextColor3 = C.good
					refs.status.Text = string.format("%s v%d · %.1f aged", model.name, model.version, status.agedFit or 0)
				elseif status.kind == "FREE" then
					refs.tag.Text = "FREE"
					refs.tag.TextColor3 = C.muted
					refs.status.Text = if status.slots == math.huge then "new line" else `line {status.usedLines + 1} of {status.slots}`
				else
					refs.tag.Text = "FULL"
					refs.tag.TextColor3 = C.dim
					local nextOffice = ModelsUI.officeForLines(status.usedLines)
					refs.status.Text = if nextOffice then `opens with {ModelsUI.officeName(nextOffice)}` else "all lines in use"
				end
				local stroke = refs.tag:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = refs.tag.TextColor3
				end
				Parts.setDisabled(refs.option.tile.button, status.kind == "FULL")
			end
		elseif step == 2 then
			local deltas = LabPreview.deltas(dview, s, "sizeId", viewMoney)
			for _, sz in ModelConfig.SIZES do
				local refs = sizeTiles[sz.id]
				local d = deltas[sz.id]
				local e = d.estimate
				local selected = sz.id == s.sizeId
				Parts.paintTile(refs.tile, selected, e.lock ~= nil and e.lock ~= "NO_DATA")
				local lockLine1, lockLine2 = "", ""
				if e.lock == "FRONTIER" then
					lockLine1, lockLine2 = "Needs", "research"
				elseif e.lock == "VRAM" then
					lockLine1, lockLine2 = "Needs", `{sz.vram} GB`
				elseif e.lock == "MONEY" then
					lockLine1, lockLine2 = "Need", "more cash"
				elseif e.lock == "NO_GPU" then
					lockLine1, lockLine2 = "Needs", "a GPU"
				end
				local locked = lockLine1 ~= ""
				refs.cost.Text = Parts.money(e.cost)
				refs.cost.TextColor3 = if locked then C.dim else C.text
				if selected then
					refs.delta.Text = "picked"
					refs.delta.TextColor3 = if locked then C.dim else Theme.accent
				else
					refs.delta.Text = Parts.signed(d.dOverall)
					refs.delta.TextColor3 = if locked then C.dim elseif d.dOverall >= 0 then C.good else C.bad
				end
				refs.time.Text = if locked then lockLine1 elseif e.rate > 0 then Format.duration(e.seconds) else "--"
				refs.time.TextColor3 = if locked then C.warn else C.muted
				refs.time.Font = if locked then F.bold else F.medium
				refs.warn2.Text = lockLine2
				-- shop package (SHOP_SPEC 9 T18): a locked tile's lines sit tighter so "research" ends >= 4 px above the border
				refs.delta.Position = UDim2.fromOffset(12, if locked then 79 else 84)
				refs.time.Position = UDim2.fromOffset(12, if locked then 102 else 110)
				refs.warn2.Position = UDim2.fromOffset(12, if locked then 122 else 130)
				-- locked tiles read greyed out (the reference greys locked parts); the reason stays in warn
				refs.label.TextColor3 = if locked then C.dim else C.text
				refs.check.Visible = selected and not locked
				refs.vram.Visible = not compact
				refs.tier.set(table.find(ModelConfig.SIZES, sz) or 1, if locked then C.dim else card.color)
			end
			-- shop package (SHOP_SPEC 5.2.4): 7B (any size) picked and locked by Frontier Architecture -> the lock strip
			local frontierLock = est.lock == "FRONTIER"
			for _, p in presets do
				p.button.Visible = not frontierLock
			end
			lockStrip2.frame.Visible = frontierLock
			if frontierLock then
				local hintText = studioLock(snapshot, s, money, lockStrip2)
				hint.Text = hintText
				hint.TextColor3 = C.warn
			end
			-- presets: what each picks, outlined when it matches the current pick
			local cheapestOn = s.sizeId == "s100m" and s.recipeId == "rapid"
			local cheapest = LabPreview.estimate(data, { sizeId = "s100m", focusId = s.focusId, recipeId = "rapid" }, nil)
			presets.cheapest.detail.Text = `100M Quick · {Parts.money(cheapest.cost)}`
			local pick = LabPreview.bestAffordable(data, s.focusId, money, saveMode(snapshot))
			presets.best.detail.Text = if pick then `{Parts.sizeLabel(pick.sizeId)} {Parts.RECIPE_LABEL[pick.recipeId]} · {Parts.money(pick.estimate.cost)}` else "nothing fits yet"
			local bestOn = pick ~= nil and pick.sizeId == s.sizeId and pick.recipeId == s.recipeId
			local last = LabPreview.sameAsLast(data)
			presets.last.detail.Text = if last then `{Parts.sizeLabel(last.sizeId)} · {Parts.focusLabel(last.focusId)}` else "no model yet"
			local lastOn = last ~= nil and last.sizeId == s.sizeId and last.focusId == s.focusId and (last.recipeId == nil or last.recipeId == s.recipeId)
			Parts.setDisabled(presets.last.button, last == nil)
			Parts.setDisabled(presets.best.button, pick == nil)
			local states: { [string]: boolean } = { cheapest = cheapestOn, best = bestOn, last = lastOn }
			for key: string, on: boolean in states do
				local p = presets[key]
				p.stroke.Color = if on then Theme.accent else C.line
				p.stroke.Transparency = if on then 0 else 0.86
				p.stroke.Thickness = if on then 3 else 1
			end
		elseif step == 3 then
			local bestFocus = LabPreview.bestFocus(dview, s.sizeId, s.recipeId, line.target)
			local deltas = LabPreview.deltas(dview, s, "focusId", viewMoney)
			local baseFit = MarketMath.fit(shown.stats, segment)
			for _, focus in ModelConfig.FOCUSES do
				local refs = focusTiles[focus.id]
				local d = deltas[focus.id]
				local selected = focus.id == s.focusId
				local plus, minus = focusLines(focus)
				local fit = MarketMath.fit(d.estimate.stats, segment)
				local fitText = string.format("%s fit %.1f", line.short, fit)
				if focus.id == bestFocus then
					fitText ..= ` · <font color="#{Theme.accent:ToHex()}"><b>BEST FIT</b></font>`
				elseif not selected then
					fitText ..= string.format(" (%s)", Parts.signed(fit - baseFit))
				end
				refs.option.set({
					title = (if selected then "✓ " else "") .. focus.label,
					right = if selected then "picked" else Parts.signed(d.dOverall),
					rightColor = if selected then Theme.accent elseif d.dOverall >= 0 then C.good else C.bad,
					lines = { plus, minus, fitText },
					-- Balanced has neither a bonus nor a weakness: both lines muted
					colors = if string.sub(plus, 1, 1) == "+" then { C.good, C.bad, C.text } else { C.muted, C.muted, C.text },
					selected = selected,
					color = Parts.focusColor(focus.id),
				})
				refs.edge.BackgroundColor3 = Parts.focusColor(focus.id)
			end
		elseif step == 4 then
			local deltas = LabPreview.deltas(dview, s, "recipeId", viewMoney)
			local viewSummary = ModelMath.dataSummary(dview.data)
			local deepWhy = LabPreview.deepShort(s.sizeId, viewSummary)
			for recipeId, option in recipeTiles do
				local d = deltas[recipeId]
				local e = d.estimate
				local selected = recipeId == s.recipeId
				local last: string
				local lastColor = C.muted
				if recipeId == "rapid" then
					last = "35 % less compute"
				elseif recipeId == "steady" then
					last = "Normal run"
				elseif e.overfit then
					-- the condition that actually fails (ModelMath.recipeFactor: data amount or quality)
					last = deepWhy or "Overfits now"
					lastColor = C.warn
				else
					last = "Data check ✓"
					lastColor = C.good
				end
				option.set({
					title = Parts.RECIPE_LABEL[recipeId],
					lines = {
						`{if e.rate > 0 then Format.duration(e.seconds) else "--"} · {Parts.money(e.cost)}`,
						if e.overfit then string.format("Overfits ×%.2f", e.recipeFactor) else string.format("Quality ×%.2f", e.recipeFactor),
						if selected then "picked" else Parts.signed(d.dOverall),
						last,
					},
					colors = { C.text, if e.overfit then C.warn else C.muted, if selected then Theme.accent elseif d.dOverall >= 0 then C.good else C.bad, lastColor },
					selected = selected,
				})
				option.lines[1].Font = F.bold
				option.lines[3].Font = F.bold
				option.check.Visible = selected
			end
			local summary = ModelMath.dataSummary(data.data)
			local sp = if afterPlan then plan else dataPlan(data, s, money)
			stripPlan = sp
			local stripCost = if sp then sp.cost else 0
			local nowWhy = LabPreview.deepShort(s.sizeId, summary)
			footnote.Visible = not compact
			footnote.Text = `Deep needs at least half of the data this size wants and 60 % quality: you have {Format.tokens(summary.total)} of {Format.tokens(size.dataNeed * 0.5)} and {Format.percent(summary.quality)} {if nowWhy == nil then "✓" else "✗"}`
			strip1.Text = `Data {Format.tokens(summary.total)} · {Format.percent(summary.quality)}`
			if stripCost > 0 then
				strip2.Text = `{size.label} wants {Format.tokens(size.dataNeed)}`
				strip2.TextColor3 = C.muted
			elseif nowWhy then
				-- enough for Standard, but Deep would overfit: say which condition fails
				strip2.Text = `{size.label} wants {Format.tokens(size.dataNeed)} ✓ · Deep {string.lower(string.sub(nowWhy, 1, 1))}{string.sub(nowWhy, 2)}`
				strip2.TextColor3 = C.warn
			else
				strip2.Text = `{size.label} wants {Format.tokens(size.dataNeed)} · enough ✓`
				strip2.TextColor3 = C.good
			end
			stripBar.set(LabPreview.dataBenefit(est.readiness))
			buyPlan.Visible = stripCost > 0
			if sp then
				buyPlan.Text = string.format("BUY DATA PLAN\n%s · %s", Parts.money(sp.cost), Parts.signed(sp.after - sp.before))
			end
			Kit.setDisabled(buyPlan, busy ~= nil or stripCost > money)
			local labelWidth = if stripCost > 0 then -350 else -160
			strip1.Size = UDim2.new(1, labelWidth, 0, 28)
			strip2.Size = UDim2.new(1, labelWidth, 0, 24)
			stripBar.frame.Size = UDim2.new(1, labelWidth, 0, 8)
		elseif step == 5 then
			if nameBox.Text == "" and LabState.name ~= "" then
				nameBox.Text = LabState.name
			end
			if validName(nameBox.Text) then
				hint.Text = `Becomes <b>{Kit.escape(trim(nameBox.Text))} v{version}</b> · looks never change the score`
				hint.TextColor3 = C.muted
			else
				hint.Text = `Names need {GameConfig.MODEL_NAME_MIN}–{GameConfig.MODEL_NAME_MAX} characters`
				hint.TextColor3 = C.bad
			end
			if nameStroke then
				nameStroke.Color = if nameBad then C.bad else C.line
				nameStroke.Transparency = if nameBad then 0 else 0.84
				nameStroke.Thickness = if nameBad then 2 else 1
			end
			local colorId = LabState.colorId or focusColorId(data, s.focusId)
			local emblem = LabState.emblem or logoIndex(data)
			-- Identity Kit tiles (shop package): shown once the Shop is open (guide over, first launch), locked for
			-- non-owners; a saved Kit choice stays visible after a refund (it is the current pick)
			local kitShown = ShopMath.gateOpen(data)
			local owns = ownsKit(snapshot)
			for id, sw in swatches do
				local on = id == colorId
				sw.tile.stroke.Color = if on then C.white else C.line
				sw.tile.stroke.Transparency = if on then 0 else 0.7
				sw.tile.stroke.Thickness = if on then 3 else 1
				sw.check.Visible = on
				if sw.kit then
					sw.tile.button.Visible = kitShown or on
					local lock = sw.lock
					if lock then lock.Visible = not owns and not on end
				end
			end
			for i, et in emblems do
				Parts.paintTile(et.tile, i == emblem, false, card.color)
				if et.kit then
					et.tile.button.Visible = kitShown or i == emblem
					local lock = et.lock
					if lock then lock.Visible = not owns and i ~= emblem end
				end
			end
			kitLine.Visible = kitShown and not owns
			lookNote.Visible = not compact
		elseif step == 6 then
			-- shop package (SHOP_SPEC 5.2.4): the same lock strip at the top of the Final-review box
			local frontierLock = est.lock == "FRONTIER"
			local reviewLock = if frontierLock then studioLock(snapshot, s, money, lockStrip6) else nil
			-- the Review's strip has no OPEN RESEARCH › (the primary): shown only with OPEN GPUs › or a Eureka offer
			local stripShown = frontierLock and (lockStrip6.offer.button.Visible or lockStrip6.gpus.Visible)
			lockStrip6.frame.Visible = stripShown
			for _, t in moneyTiles do
				t.frame.Visible = not stripShown
			end
			local offered = planMode and not noData
			moneyTiles[1].caption.Text = "TRAINING COST"
			moneyTiles[1].value.Text = Parts.money(est.cost)
			moneyTiles[2].frame.Visible = not offered and not stripShown
			planToggle.button.Visible = offered and not stripShown
			moneyTiles[2].caption.Text = "TIME"
			moneyTiles[2].value.Text = if est.rate > 0 then "~" .. Format.duration(est.seconds) else "--"
			if offered then
				local cost = if plan then plan.cost else (if offer then offer.plan.cost else 0)
				toggleCaption.Text = "DATA PLAN"
				toggleValue.Text = if planOn then `ON · {Parts.money(cost)}` else "OFF · skip"
				toggleValue.TextColor3 = if planOn then C.good else C.muted
				Parts.paintTile(planToggle, planOn, false, C.good)
			end
			local after = money - planCost - est.cost
			moneyTiles[3].caption.Text = if planCost > 0 then "CASH AFTER ALL" else "CASH AFTER"
			moneyTiles[3].value.Text = Parts.money(after)
			moneyTiles[3].value.TextColor3 = if after < 0 then C.bad elseif after < reserve then C.warn else C.good
			if reviewLock then
				-- fix round 1 (review): START is impossible here, so the hint names the lock (not "Check it, then start.")
				hint.Text = reviewLock
				hint.TextColor3 = C.warn
			elseif first then
				hint.Text = if noData and afterPlan then "<b>FIRST MODEL</b> · buy the data plan, then press START." else "<b>FIRST MODEL</b> · a good starter is ready. Just press START."
				hint.TextColor3 = C.good
			elseif offered and afterPlan then
				hint.Text = "<b>SUGGESTED</b> · buy its data plan, then press START."
				hint.TextColor3 = C.good
			end
			-- the fit line: does it beat the line's live model, and by how much (the suggestions need +3)
			local function fitLine(): string
				local status = LabPreview.lineStatus(data, line.target)
				local fit = MarketMath.fit(shown.stats, segment)
				local model = status.model
				if status.kind == "LIVE" and model then
					local aged = status.agedFit or 0
					local gain = fit - aged
					local color = if gain >= 3 then C.good elseif gain > 0 then C.warn else C.bad
					local verdict = if gain >= 3 then "beats" elseif gain > 0 then `only {Parts.signed(gain)} over` else "below"
					return string.format("%s fit %.1f · <font color=\"#%s\">%s %s v%d (%.1f after age)</font>", line.label, fit, color:ToHex(), verdict, model.name, model.version, aged)
				end
				return string.format("%s fit %.1f · new product line", line.label, fit)
			end
			local rank = LabPreview.rank(snapshot, shown.stats, line.target)
			local rankLine = `Likely rank <b>#{rank.rank} of {rank.total}</b> · {segment.label}`
			local lastLine = LabPreview.oddsText(if company then company.spec else "general")
			if after >= 0 and after < reserve then
				lastLine = `<font color="#{C.warn:ToHex()}">Leaves {Parts.money(after)}: below your {Parts.money(reserve)} safety reserve</font>`
			end
			if noData and plan and afterPlan then
				local plo, phi = LabPreview.range(plan.after)
				reviewLines[1].Text = `<font color="#{C.warn:ToHex()}">No training data yet</font> · every AI learns from data`
				reviewLines[2].Text = `Data plan: <b>{LabPreview.planText(plan)}</b>`
				reviewLines[3].Text = `= {Format.tokens(plan.tokens)} tokens · {Format.percent(plan.quality)} quality · {Parts.money(plan.cost)}`
				reviewLines[4].Text = string.format("Then expected <b>~%.1f</b> · final %.1f–%.1f without events", shown.overall, plo, phi)
			elseif plan and afterPlan then
				reviewLines[1].Text = string.format("Expected <b>~%.1f</b> after the data plan · final %.1f–%.1f", shown.overall, lo, hi)
				reviewLines[2].Text = `Data plan: <b>{LabPreview.planText(plan)}</b> · {Parts.money(plan.cost)}`
				-- line 3 shares its row with BREAKDOWN › on a phone: the short rank line there, the long fit line below
				reviewLines[3].Text = rankLine
				reviewLines[4].Text = if after >= 0 and after < reserve then lastLine else fitLine()
			else
				reviewLines[1].Text = string.format("Expected <b>~%.1f</b> · final %.1f–%.1f without events", shown.overall, lo, hi)
				reviewLines[2].Text = fitLine()
				reviewLines[3].Text = rankLine
				reviewLines[4].Text = lastLine
			end
			breakdownCue.Visible = compact
			-- with a data plan the breakdown explains the shown (after-plan) number, not today's data
			local bd = LabPreview.breakdown(dview, s)
			breakdownLines[1].Text = string.format("Size max %d × %s: amount %.2f × quality factor %.2f", bd.potential, if afterPlan then "plan data" else "data", bd.quantity, bd.quality)
			breakdownLines[2].Text = string.format("Data %s quality · Plan ×%.2f (%s) · focus %s", Format.percent(ModelMath.dataSummary(dview.data).quality), bd.recipeFactor, Parts.RECIPE_LABEL[s.recipeId] or "", Parts.focusLabel(bd.focusId))
			breakdownLines[3].Text = string.format("Bonuses: %s · research + Lab +%s per skill · cap %d", LabPreview.specBonusText(bd.spec), string.format("%g", bd.core), bd.cap)
			if compact then
				breakdownLines[4].Text = if bd.reliabilityBonus > 0 then `Alignment research: +{bd.reliabilityBonus} Reliability` else "Training events can change the result."
				breakdownLines[5].Text = "The server adds a random ±2.5 to every skill at the end."
				breakdownLines[6].Text = "Tap to go back to the review."
			else
				-- desktop: the breakdown sits under the review lines (about 125 px), so 4 rows of 24
				breakdownLines[4].Text = (if bd.reliabilityBonus > 0 then `Alignment +{bd.reliabilityBonus} Reliability` else "Events can change it") .. " · random ±2.5 per skill at the end"
				breakdownLines[5].Text = ""
				breakdownLines[6].Text = ""
			end
			for i, row in breakdownLines do
				row.Position = UDim2.fromOffset(18, if compact then 8 + (i - 1) * 30 else 6 + (i - 1) * 24)
				row.Visible = row.Text ~= ""
			end
			breakdown.button.Visible = breakdownOpen or not compact
			if not compact then
				breakdown.button.Position = UDim2.fromOffset(0, 248)
				breakdown.button.Size = UDim2.new(1, 0, 1, -248)
			else
				breakdown.button.Position = UDim2.new()
				breakdown.button.Size = UDim2.fromScale(1, 1)
			end
		end

		-- step chips
		chips.set(step, done, nil)
		chips.buttons[6].Text = if step == 6 then "6 Review" else (if done[6] then "✓ Review" else "6 Review")
		chips.buttons[6].TextSize = 22
		back.Text = if step == 1 then "CLOSE" else "‹ BACK"

		-- primary button: CONTINUE on steps 1-5, the START state machine on the Review (server check order)
		action = nil
		local label: string
		local enabled = true
		if busy == "start" then
			label, enabled = "STARTING…", false
		elseif busy == "buy" then
			label, enabled = "BUYING DATA…", false
		elseif step < 6 then
			label = "CONTINUE ›"
		else
			local training = data.training
			if training then
				local tm = data.models[training.modelId]
				local p = if training.workTotal > 0 then training.workDone / training.workTotal else 0
				label = `TRAINING SLOT BUSY · {if tm then tm.name else "model"} {math.floor(p * 100)} %`
				action = "training"
			elseif not validName(nameBox.Text) then
				label = `NAME NEEDS {GameConfig.MODEL_NAME_MIN}-{GameConfig.MODEL_NAME_MAX} CHARACTERS`
				action = "name"
			elseif est.lock == "FRONTIER" then
				label = "OPEN RESEARCH › FRONTIER ARCHITECTURE" -- shop package (SHOP_SPEC 5.2.4): free deep link
				action = "research"
			elseif est.lock == "MODEL_LIMIT" then
				label = "MODEL LIMIT · RETIRE OLD MODELS"
				action = "market"
			elseif est.lock == "NO_GPU" then
				label = "NO GPU · OPEN GPUs" -- ONBOARDING_SPEC B7 (request onboarding #5)
				action = "compute"
			elseif est.lock == "VRAM" then
				label = `NEEDS {est.vramNeed - est.vramHave} GB MORE VRAM · OPEN GPUs`
				action = "compute"
			elseif plan and afterPlan and plan.cost <= money then
				-- the shown plan first (no data yet, or a suggestion's plan), then START with the bought data
				label = `BUY DATA PLAN · {Parts.money(plan.cost)}`
				action = "buy"
			elseif est.lock == "NO_DATA" then
				label = "NEED TRAINING DATA · OPEN DATA"
				action = "data"
			elseif est.lock == "MONEY" then
				label = `NEED {Parts.money(est.cost)}`
				enabled = false
			else
				label = `START TRAINING · {Parts.money(est.cost)}`
				action = "start"
			end
		end
		primary.Text = label
		primary.TextSize = if #label > 30 then 22 else 26
		Kit.setDisabled(primary, not enabled)
	end

	---------------------------------------------------------------- view
	local view = {
		frame = frame,
		title = "Model Studio",
	}

	function view.show(opts: any)
		local snapshot = StateController.snapshot
		busy = nil
		buyKey = nil
		buyHold = false
		started = false
		nameBad = false
		breakdownOpen = false
		planCache = nil
		planMode, planOn, offer = false, true, nil
		if snapshot then
			local data = snapshot.data
			local firstOpen = false
			if typeof(opts.prefill) == "table" then
				local p = opts.prefill
				if typeof(p.target) == "string" and ModelConfig.getLine(p.target) then
					LabState.lineId = p.target
				end
				if typeof(p.name) == "string" then
					LabState.name = p.name
				end
				if typeof(p.sizeId) == "string" and typeof(p.focusId) == "string" then
					StateController.setSelection(p.sizeId, p.focusId)
				end
				if typeof(p.recipeId) == "string" then
					StateController.setRecipe(p.recipeId)
				end
				-- a suggestion's data plan (LabPreview.prefillOf): offered on the Review as BUY DATA PLAN
				local plan = p.plan
				if typeof(plan) == "table" and typeof(plan.cost) == "number" and plan.cost > 0 and typeof(plan.order) == "table" then
					planMode = true
					offer = { plan = plan, selKey = selKey(sel()), dataKey = dataKey(data) }
				end
			elseif LabPreview.isFirstModel(data) and not data.training and not LabState.firstDefaults then
				-- first model (LAB_SPEC 4.9): 100M · best fit for Consumer Chat · Standard, opened at the Review; once
				-- per session, so the player's own picks survive a trip to Hardware or Data (LAB_SPEC 2: keeps every choice)
				LabState.firstDefaults = true
				firstOpen = true
				LabState.lineId = "general"
				local focusId = LabPreview.bestFocus(data, "s100m", "steady", "general")
				StateController.setSelection("s100m", focusId)
				StateController.setRecipe("steady")
			end
			if LabState.name == "" then
				LabState.name = LabState.nextName()
			end
			nameBox.Text = LabState.name
			if typeof(opts.step) == "number" then
				step = math.clamp(opts.step, 1, 6)
			elseif typeof(opts.prefill) == "table" or firstOpen then
				step = 6
			elseif LabState.step > 1 then
				step = LabState.step
			elseif LabPreview.isFirstModel(data) then
				step = 6
			else
				step = 1
			end
			LabState.step = 1
		end
		refresh()
	end

	function view.hide()
		-- leaving keeps the step (‹ LAB, a fix in Hardware or Data, a training decision): the next open resumes it
		LabState.step = if started then 1 else step
		busy = nil
		buyKey = nil
	end

	function view.refresh(_snapshot: Snapshot)
		refresh()
	end

	function view.focus(): GuiObject?
		if step == 6 then
			return primary
		end
		local s = sel()
		if step == 1 then
			return lineTiles[LabState.lineId] and lineTiles[LabState.lineId].option.tile.button or primary
		elseif step == 2 then
			return sizeTiles[s.sizeId] and sizeTiles[s.sizeId].tile.button or primary
		elseif step == 3 then
			return focusTiles[s.focusId] and focusTiles[s.focusId].option.tile.button or primary
		elseif step == 4 then
			return recipeTiles[s.recipeId] and recipeTiles[s.recipeId].tile.button or primary
		end
		return nameBox
	end

	focusNow = view.focus

	function view.primary()
		runPrimary()
	end

	function view.back()
		if step <= 1 then
			Studio.close()
		else
			goStep(step - 1)
			Studio.select(view.focus())
		end
	end

	function view.step(delta: number)
		goStep(step + delta)
		Studio.select(view.focus())
	end

	function view.setClass(isCompact: boolean)
		compact = isCompact
		-- regular layout: the card grows with the preview zone (taller main area, wider canvas on big screens) while
		-- the Expected panel keeps 300 px for its bars and the spec sheet fits below; compact keeps 190 x 246
		local cardSize = Vector2.new(190, 246)
		if not compact then
			local canvas: Vector2 = Studio.canvas
			local h = math.clamp(math.floor(canvas.Y - 184 - 90 - 12 - 92 - 8), 270, 440)
			local w = math.floor(h * 220 / 270)
			local maxW = math.floor(canvas.X - 734 - 16 - 300)
			if w > maxW then
				w = math.max(220, maxW)
				h = math.floor(w * 270 / 220)
			end
			cardSize = Vector2.new(w, h)
		end
		card.resize(cardSize)
		local x = cardSize.X + 16
		expPanel.Position = UDim2.fromOffset(x, 90)
		expPanel.Size = UDim2.new(1, -x, 0, cardSize.Y)
		specSheet.Visible = not compact
		specSheet.Position = UDim2.fromOffset(0, 90 + cardSize.Y + 12)
		bars.layout(if compact then 21 else math.clamp(math.floor((cardSize.Y - 120) / 6), 21, 34))
		for _, refs in sizeTiles do
			local b = refs.tile.button
			b.Size = UDim2.fromOffset(122, if compact then 152 else 190)
		end
		-- regular (desktop): taller 2x2 tiles on steps 1 and 3 use the panel's height (LAB_SPEC 4.3: 321x168 max;
		-- 140 keeps the desktop footnote free); the tag row of a line tile stays on the tile's bottom edge
		local tileH, rowH = if compact then 108 else 140, if compact then 120 else 152
		for i, line in ModelConfig.LINES do
			local refs = lineTiles[line.target]
			local col, row = (i - 1) % 2, (i - 1) // 2
			refs.option.tile.button.Size = UDim2.fromOffset(321, tileH)
			refs.option.tile.button.Position = UDim2.fromOffset(col * 333, row * rowH)
			refs.tag.Position = UDim2.new(0, 16, 1, -36)
			refs.status.Position = UDim2.new(0, 110, 1, -36)
		end
		local focusH, focusRow = if compact then 112 else 140, if compact then 124 else 152
		for i, focus in ModelConfig.FOCUSES do
			local col, row = (i - 1) % 2, (i - 1) // 2
			local button = focusTiles[focus.id].option.tile.button
			button.Size = UDim2.fromOffset(321, focusH)
			button.Position = UDim2.fromOffset(col * 333, row * focusRow)
		end
		refresh()
	end

	-- test hooks (tests/lab): current step and the last estimate
	function view.state(): (number, LabPreview.Estimate?, string?)
		return step, lastEstimate, action
	end

	return view
end

return DesignSteps
