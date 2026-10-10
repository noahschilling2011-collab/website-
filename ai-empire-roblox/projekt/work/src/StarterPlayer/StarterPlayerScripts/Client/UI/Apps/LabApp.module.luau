--!strict
-- Modell-Labor. Vier Ansichten, je nach Zustand:
--   creator  -> Modell entwerfen (Name, Größe, Fokus) mit Live-Schätzung
--   training -> Fortschritt, Loss-Graph, Events mit Entscheidung, Log
--   result   -> Ergebnis mit Stats und Vergleich
--   release  -> Preise, Marketing, Zielgruppe, Prognose, Launch
-- CORE_SPEC 7 (models package): product lines with one live model each (a release into a live line is its
-- next version), refinement count x/3 (the model keeps serving), stat cap 99, Lab level with its price,
-- Recommended price preselected + Auto price, forecast with live rivals (PricingMath = the server's math).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local ModelConfig = require(Shared.Config.ModelConfig)
local MarketConfig = require(Shared.Config.MarketConfig)
local ModelMath = require(Shared.ModelMath)
local EmpireMath = require(Shared.EmpireMath)
local EmpireConfig = require(Shared.Config.EmpireConfig)
local MarketMath = require(Shared.MarketMath)
local PricingMath = require(Shared.PricingMath)
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
local T = ModelConfig.TRAINING

type Snapshot = Types.Snapshot
type ModelData = Types.ModelData

local NAME_IDEAS = { "Nova", "Atlas", "Echo", "Pulse", "Quill", "Sage", "Orbit", "Flux", "Iris", "Vega", "Lumen", "Spark" }
local CORE_STATS = { "reasoning", "coding", "math", "creativity", "knowledge", "reliability" }
local LOSS_MIN, LOSS_MAX = 0.6, 5.2
local FORECAST_SECONDS = ModelConfig.PRICING.cardSeconds
local STAT_CAP = ModelConfig.STAT_CAP
local MARKETING_TIERS = { 5_000, 10_000, 25_000, 50_000, 100_000, 250_000 }

local LabApp = {}

local nav: Kit.Nav? = nil
local container: Frame? = nil
local Journey=require(ReplicatedStorage.Shared.JourneyMath)
local view = "creator"
local resultId: string? = nil
local resultBest: number? = nil
local releaseId: string? = nil
local views: { [string]: GuiObject } = {}
local refreshers: { [string]: (Snapshot) -> () } = {}
local nameBox: TextBox? = nil

---------------------------------------------------------------------------- Helfer

local function statLabel(id: string): string
	for _, stat in ModelConfig.STATS do
		if stat.id == id then
			return stat.label
		end
	end
	return id
end

local function sizeLabel(id: string): string
	local size = ModelConfig.getSize(id)
	return if size then size.label else id
end

local function focusLabel(id: string): string
	local focus = ModelConfig.getFocus(id)
	return if focus then focus.label else id
end

local function modelTitle(model: ModelData): string
	return `{model.name} v{model.version}`
end

local function trim(text: string): string
	return string.match(text, "^%s*(.-)%s*$") or ""
end

local function validName(text: string): boolean
	local length = utf8.len(trim(text))
	return length ~= nil and length >= GameConfig.MODEL_NAME_MIN and length <= GameConfig.MODEL_NAME_MAX
end

local function bestOverall(data: Types.PlayerData, exceptId: string?): number
	local best = 0
	for id, model in data.models do
		if id ~= exceptId and model.status ~= "training" then
			best = math.max(best, model.overall)
		end
	end
	return best
end

local function specOf(data: Types.PlayerData): string
	local company = data.company
	return if company then company.spec else "general"
end

local function decideView(snapshot: Snapshot): string
	local data = snapshot.data
	if data.training then
		return "training"
	end
	local rid = releaseId
	if rid then
		local model: ModelData? = data.models[rid]
		if model and model.status == "trained" then
			return "release"
		end
		releaseId = nil
	end
	local res = resultId
	if res then
		local model: ModelData? = data.models[res]
		if model and model.status ~= "training" then
			return "result"
		end
		resultId = nil
	end
	return "creator"
end

local function render()
	local snapshot = StateController.snapshot
	if not snapshot then
		return
	end
	local nextView = decideView(snapshot)
	if nextView ~= view then
		view = nextView
		for id, frame in views do
			frame.Visible = id == view
		end
	end
	local refresh = refreshers[view]
	if refresh then
		refresh(snapshot)
	end
end

local function header(parent: Instance, captionText: string, order: number): (TextLabel, TextLabel, TextLabel)
	local head = Kit.stack(parent, 2, order)
	local caption = Kit.caption(head, captionText, 1)
	local title = Kit.text(head, "", 24, F.display, C.text)
	title.LayoutOrder = 2
	local sub = Kit.text(head, "", 15, F.medium, C.muted)
	sub.LayoutOrder = 3
	return caption, title, sub
end

local function scrollView(parent: Frame, id: string): ScrollingFrame
	local scroll = Kit.scroll(parent)
	scroll.Name = id
	scroll.Visible = id == view
	Kit.padding(scroll, 2, 14, 20, 2)
	Kit.list(scroll, 14)
	views[id] = scroll
	return scroll
end

local function animateNumber(label: TextLabel, target: number)
	task.spawn(function()
		local start = os.clock()
		local duration = 1.1
		while label.Parent do
			local t = math.min(1, (os.clock() - start) / duration)
			local eased = 1 - (1 - t) ^ 3
			label.Text = string.format("%.1f", target * eased)
			if t >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
	end)
end

---------------------------------------------------------------------------- Creator

local function buildCreator(parent: Frame)
	local scroll = scrollView(parent, "creator")
	Kit.heading(scroll, "MODEL LAB", "Pick a size and a focus, then train on your GPUs. Bigger models need more VRAM and much more data. Each product line runs one live model; a new release into a live line is its next version.", 1)

	local left, right = Kit.columns(scroll, 0.52, 16, 2)

	-- Konfiguration
	local config = Kit.card(left, 1, 10)
	Kit.caption(config, "Model name", 1)
	local box = Kit.input(config, "e.g. Nova")
	box.LayoutOrder = 2
	box.Text = NAME_IDEAS[math.random(1, #NAME_IDEAS)]
	nameBox = box

	local sizeOptions: { Kit.Option } = {}
	for _, size in ModelConfig.SIZES do
		table.insert(sizeOptions, { id = size.id, label = size.label })
	end
	local focusOptions: { Kit.Option } = {}
	for _, focus in ModelConfig.FOCUSES do
		table.insert(focusOptions, { id = focus.id, label = focus.label })
	end

	Kit.caption(config, "Size (parameters)", 3)
	local sizeSeg = Kit.segmented(config, sizeOptions, StateController.ui.sizeId, function(id: string)
		StateController.setSelection(id, StateController.ui.focusId)
		render()
	end)
	sizeSeg.frame.LayoutOrder = 4
	local sizeHint = Kit.para(config, "", 13, C.dim, 5)

	Kit.caption(config, "Training focus", 6)
	local focusSeg = Kit.segmented(config, focusOptions, StateController.ui.focusId, function(id: string)
		StateController.setSelection(StateController.ui.sizeId, id)
		render()
	end)
	focusSeg.frame.LayoutOrder = 7
	local focusHint = Kit.para(config, "", 13, C.dim, 8)

	Kit.caption(config,"Training budget & validation",9)
	local recipeOptions={};for _,recipe in ModelConfig.RECIPES do table.insert(recipeOptions,{id=recipe.id,label=recipe.label}) end
	local recipes=Kit.segmented(config,recipeOptions,StateController.ui.recipeId or "steady",function(id) StateController.setRecipe(id);render() end)
	recipes.frame.LayoutOrder=10
	local recipeHint=Kit.para(config,"",13,C.dim,11)

	-- Produktlinien (CORE_SPEC 7.1): eine Zeile je Linie, welches Modell sie hält, freie Plätze
	local linesCard = Kit.card(left, 2, 8)
	local linesCaption = Kit.caption(linesCard, "Product lines", 1)
	type LineUi = { frame: Frame, detail: TextLabel, tag: TextLabel }
	local lineUi: { [string]: LineUi } = {}
	for index, line in ModelConfig.LINES do
		local row = Kit.frame(linesCard, UDim2.new(1, 0, 0, 46))
		row.LayoutOrder = 1 + index
		row.BackgroundTransparency = 0.3
		row.BackgroundColor3 = C.bg
		Kit.corner(row, 10)
		local name = Kit.text(row, line.label, 15, F.bold, C.text)
		name.Position = UDim2.fromOffset(12, 5)
		local detail = Kit.text(row, "", 13, F.medium, C.muted)
		detail.AutomaticSize = Enum.AutomaticSize.None
		detail.Size = UDim2.new(1, -110, 0, 18)
		detail.Position = UDim2.fromOffset(12, 24)
		detail.TextTruncate = Enum.TextTruncate.AtEnd
		local tag = Kit.tag(row, "free", C.dim)
		tag.AnchorPoint = Vector2.new(1, 0.5)
		tag.Position = UDim2.new(1, -10, 0.5, 0)
		lineUi[line.target] = { frame = row, detail = detail, tag = tag }
	end
	local linesNote = Kit.para(linesCard, "", 13, C.dim, 9)

	-- Fertige, noch nicht veröffentlichte Modelle
	local readyCard = Kit.card(left, 3, 8)
	Kit.caption(readyCard, "Ready to launch", 1)
	local readyList = Kit.stack(readyCard, 8, 2)
	local readyEmpty = Kit.para(readyCard, `Your trained checkpoints appear here. Add 100M fresh tokens to refine a checkpoint with your own GPUs (at most {ModelConfig.REFINE.limit} times per model; every stat caps at {STAT_CAP}).`, 14, C.dim, 3)
	local readyKey = ""

	-- Schätzung
	local est = Kit.card(right, 1, 10)
	Theme.bindAccent(est, "BackgroundColor3", Theme.tint(0.88)) -- Hero-Fläche
	Kit.caption(est, "Expected result", 1)
	local overallRow = Kit.row(est, 58, 14, 2)
	local expected = Kit.text(overallRow, "--", 40, F.display)
	expected.LayoutOrder = 1
	Theme.bindAccent(expected, "TextColor3")
	local info = Kit.frame(overallRow, UDim2.new())
	info.AutomaticSize = Enum.AutomaticSize.XY
	info.LayoutOrder = 2
	Kit.list(info, 2)
	Kit.caption(info, "Overall (estimate)", 1)
	local bestText = Kit.text(info, "", 14, F.medium, C.muted)
	bestText.LayoutOrder = 2

	local rows: { [string]: Kit.StatRow } = {}
	for index, id in CORE_STATS do
		rows[id] = Kit.statRow(est, statLabel(id), 2 + index)
	end
	local capNote = Kit.para(est, "", 12, C.dim, 9)
	Kit.divider(est, 10)
	local metrics = Kit.grid(est, 2, 46, 10, 11)
	local mTime = Kit.metric(metrics, "Training time", 1, 18)
	local mCost = Kit.metric(metrics, "Training cost", 2, 18)
	local mVram = Kit.metric(metrics, "VRAM", 3, 18)
	local mCompute = Kit.metric(metrics, "Compute", 4, 18)
	Kit.caption(est, "Data fill", 12)
	local fillBar = Kit.bar(est, 10, 13)
	local fillText = Kit.para(est, "", 13, C.dim, 14)
	local train = Kit.button(est, "START TRAINING", "primary", UDim2.new(1, 0, 0, 50))
	train.LayoutOrder = 15
	train.TextSize = 17
	Kit.para(est, "1 training slot: one training or refinement runs at a time.", 12, C.dim, 16)

	-- Lab-Level (CORE_SPEC 7.5): nach dem Forschungsbaum, +1 auf jeden Kern-Stat neuer Modelle
	local labCard = Kit.card(right, 2, 8)
	local labTop = Kit.frame(labCard, UDim2.new(1, 0, 0, 28))
	labTop.LayoutOrder = 1
	local labTitle = Kit.text(labTop, "Lab level 0", 20, F.display, C.text)
	labTitle.Position = UDim2.fromOffset(0, 2)
	local labTag = Kit.tag(labTop, "0 / 10", C.muted)
	labTag.AnchorPoint = Vector2.new(1, 0.5)
	labTag.Position = UDim2.new(1, 0, 0.5, 0)
	local labBar = Kit.bar(labCard, 8, 2)
	Kit.para(labCard, `Every level adds +1 to every core stat of the models you train next (stats cap at {STAT_CAP}). Your researchers unlock levels after the whole research tree.`, 13, C.dim, 3)
	local labCost = Kit.para(labCard, "", 14, C.muted, 4)
	local labBuy = Kit.button(labCard, "UPGRADE LAB", "secondary", UDim2.new(1, 0, 0, 42))
	labBuy.LayoutOrder = 5
	local labCanBuy = false

	local action: string? = nil -- "train" | "compute" | "data"

	local function rebuildReady(data: Types.PlayerData)
		local ids: { string } = {}
		for _, id in data.modelOrder do
			local model: ModelData? = data.models[id]
			if model and model.status == "trained" then
				table.insert(ids, id)
			end
		end
		local parts: { string } = {}
		for _, id in ids do
			table.insert(parts, id .. ":" .. tostring(data.models[id].iterations or 0))
		end
		local key = table.concat(parts, ",")
		if key == readyKey then
			return
		end
		readyKey = key
		for _, child in readyList:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for index, id in ids do
			local model = data.models[id]
			local row = Kit.frame(readyList, UDim2.new(1, 0, 0, 56))
			row.LayoutOrder = index
			row.BackgroundTransparency = 0.3
			row.BackgroundColor3 = C.bg
			Kit.corner(row, 10)
			local name = Kit.text(row, modelTitle(model), 16, F.bold, C.text)
			name.Position = UDim2.fromOffset(12, 8)
			name.AutomaticSize = Enum.AutomaticSize.None
			name.Size = UDim2.new(1,-300,0,22)
			name.TextTruncate = Enum.TextTruncate.AtEnd
			local sub = Kit.text(
				row,
				`{sizeLabel(model.sizeId)} · {focusLabel(model.focusId)} · Overall {string.format("%.1f", model.overall)} · {ModelsUI.refineText(model)}`,
				13,
				F.medium,
				C.muted
			)
			sub.Position = UDim2.fromOffset(12, 30)
			sub.AutomaticSize = Enum.AutomaticSize.None
			sub.Size = UDim2.new(1,-300,0,18)
			sub.TextTruncate = Enum.TextTruncate.AtEnd
			local runs = math.floor(tonumber(model.iterations) or 0)
			local atLimit = runs >= ModelConfig.REFINE.limit
			local refine = Kit.button(row, if atLimit then "REFINED" else `REFINE {runs + 1}/{ModelConfig.REFINE.limit}`, "secondary", UDim2.fromOffset(110,36))
			refine.AnchorPoint = Vector2.new(1,0.5)
			refine.Position = UDim2.new(1,-125,0.5,0)
			refine.TextSize = 14
			Kit.setDisabled(refine, atLimit)
			Kit.onClick(refine,function() ModelsUI.call("ImproveModel",{modelId=id}) end)
			local button = Kit.button(row, "RELEASE", "primary", UDim2.fromOffset(104, 36))
			button.AnchorPoint = Vector2.new(1, 0.5)
			button.Position = UDim2.new(1, -10, 0.5, 0)
			button.TextSize = 14
			Kit.onClick(button, function()
				releaseId = id
				resultId = nil
				render()
			end)
		end
		readyEmpty.Visible = #ids == 0
	end

	refreshers.creator = function(snapshot: Snapshot)
		local data = snapshot.data
		local ui = StateController.ui
		sizeSeg.set(ui.sizeId)
		focusSeg.set(ui.focusId)
		local size = ModelConfig.getSize(ui.sizeId)
		local focus = ModelConfig.getFocus(ui.focusId)
		if not size or not focus then
			return
		end
		local fleet = ModelMath.fleet(data.gpus)
		local summary = ModelMath.dataSummary(data.data)
		local recipeId=ui.recipeId or "steady"
		recipes.set(recipeId)
		recipeHint.Text=ModelConfig.getRecipe(recipeId).desc
		local plan = ModelMath.plan(size, fleet, summary,recipeId)
		local stats, overall = ModelMath.computeStats(size.id, focus.id, summary, specOf(data), ModelMath.recipeFactor(size,summary,recipeId), nil)
		stats, overall = EmpireMath.boostStats(stats, data.empire)
		stats, overall = ModelMath.capStats(stats)
		plan.rate = EmpireMath.trainingRate(data.gpus, plan.work, data.empire)
		plan.seconds = if plan.rate > 0 then plan.work / plan.rate else 0

		expected.Text = string.format("%.1f", overall)
		local best = bestOverall(data, nil)
		bestText.Text = if best > 0
			then `your best: {string.format("%.1f", best)}  ({Format.signed(overall - best)})`
			else "your first model"
		for id, row in rows do
			row.set(stats[id] or 0, STAT_CAP)
		end
		local level = math.floor(tonumber(data.empire.labLevel) or 0)
		capNote.Text = `Every stat caps at {STAT_CAP}.` .. (if level > 0 then ` Lab level {level} adds +{level} to each.` else "")

		-- product lines
		local lineRows, usedLines, slots = ModelsUI.lines(data)
		local slotText = if slots == math.huge then tostring(usedLines) else `{usedLines} / {slots}`
		linesCaption.Text = `Product lines · {slotText} live at {ModelsUI.officeName(data.empire.office)}`
		for _, lineRow in lineRows do
			local refs = lineUi[lineRow.line.target]
			local model = lineRow.model
			if model then
				refs.detail.Text = `{model.name} v{model.version} · line v{lineRow.version} · Overall {string.format("%.1f", model.overall)} · {ModelsUI.ageText(model)}`
					.. (if lineRow.extra > 0 then ` · +{lineRow.extra} more` else "")
				refs.detail.TextColor3 = C.text
				refs.tag.Text = "LIVE"
				refs.tag.TextColor3 = C.good
			elseif lineRow.open then
				local left = slots - usedLines
				refs.detail.Text = `Free: {left} more line{if left == 1 then "" else "s"} at this office`
				refs.detail.TextColor3 = C.muted
				refs.tag.Text = "FREE"
				refs.tag.TextColor3 = C.muted
			else
				local nextStage = ModelsUI.officeForLines(usedLines)
				refs.detail.Text = if nextStage then `Another line opens with {ModelsUI.officeName(nextStage)}` else "All lines are in use"
				refs.detail.TextColor3 = C.dim
				refs.tag.Text = "LOCKED"
				refs.tag.TextColor3 = C.dim
			end
		end
		linesNote.Text = `One live model per line. A release into a live line is its next version: it takes over {math.floor(ModelConfig.MIGRATE * 100 + 0.5)} % of the users. Models age: up to -8 fit after 3 game days, so ship new versions.`

		-- Lab level
		local lab = ModelsUI.lab(data, StateController.money())
		labTitle.Text = `Lab level {lab.level}`
		labTag.Text = `{lab.level} / {lab.max}`
		labBar.set(lab.level / math.max(1, lab.max))
		labCost.Text = lab.reason
		labCanBuy = lab.canBuy
		labBuy.Text = if lab.level >= lab.max then "LAB AT MAX LEVEL" else `UPGRADE LAB · {Format.int(lab.points)} RP + {Format.money(lab.cash)}`
		Kit.setDisabled(labBuy, not lab.canBuy)

		mTime.value.Text = if plan.rate > 0 then Format.duration(plan.seconds) else "--"
		mCost.value.Text = Format.money(plan.cost)
		mVram.value.Text = `{size.vram} of {fleet.vram} GB`
		mVram.value.TextColor3 = if fleet.vram >= size.vram then C.text else C.bad
		mCompute.value.Text = `{string.format("%g", math.round(fleet.throughput * 10) / 10)} units/s`

		local readiness = ModelMath.readiness(size, summary)
		fillBar.set(readiness.fill)
		fillText.Text = `{Format.tokens(summary.total)} tokens · fill {Format.percent(readiness.fill)} · quality {Format.percent(summary.quality)}`
			.. (if readiness.fill < 1 then "  (more data = smarter model)" else "")

		for _, other in ModelConfig.SIZES do
			sizeSeg.setDim(other.id, fleet.vram < other.vram or (other.id == "s7b" and not data.empire.research.frontier))
		end
		sizeHint.Text = `{size.label} params · needs {size.vram} GB VRAM · full data at {Format.tokens(size.dataNeed)} tokens`
		local parts: { string } = {}
		for _, stat in ModelConfig.STATS do
			local mult = focus.mult[stat.id]
			if mult then
				table.insert(parts, `{stat.label} {Format.signed((mult - 1) * 100, 0)}%`)
			end
		end
		focusHint.Text = if #parts > 0 then table.concat(parts, " · ") else "No bonus, no weakness."

		local nameText = if nameBox then nameBox.Text else ""
		action = nil
		local label: string
		if not validName(nameText) then
			label = `NAME NEEDS {GameConfig.MODEL_NAME_MIN}-{GameConfig.MODEL_NAME_MAX} CHARACTERS`
		elseif plan.reason == "NO_GPU" then
			label = "NO GPU · OPEN COMPUTE"
			action = "compute"
		elseif plan.reason == "VRAM" then
			label = `NEEDS {size.vram-fleet.vram} GB MORE VRAM · OPEN COMPUTE`
			action = "compute"
		elseif plan.reason == "NO_DATA" then
			label = "NEED TRAINING DATA · OPEN DATA"
			action = "data"
		elseif size.id == "s7b" and not data.empire.research.frontier then
			label = "RESEARCH FRONTIER ARCHITECTURE · COMPANY"
			action = "empire"
		elseif StateController.money() < plan.cost then
			label = `NEED {Format.money(plan.cost)}`
		else
			label = `START TRAINING · {Format.money(plan.cost)}`
			action = "train"
		end
		train.Text = label
		Kit.setDisabled(train, action == nil)
		rebuildReady(data)
	end

	Kit.onClick(labBuy, function()
		if not labCanBuy then
			return
		end
		local ok = ModelsUI.call("EmpireAction", { action = "labLevel" })
		if ok then
			Toast.show("success", "Lab upgraded: new models get +1 on every core stat.")
		end
	end)

	box:GetPropertyChangedSignal("Text"):Connect(function()
		if view == "creator" then
			render()
		end
	end)

	Kit.onClick(train, function()
		local currentNav = nav
		if action == "compute" and currentNav then
			currentNav.show("compute")
			return
		elseif action == "data" and currentNav then
			currentNav.show("data")
			return
		elseif action == "empire" and currentNav then
			currentNav.show("empire")
			return
		elseif action ~= "train" then
			return
		end
		local name = trim(box.Text)
		local ui = StateController.ui
		ActionController.call("StartTraining", { name = name, sizeId = ui.sizeId, focusId = ui.focusId, recipeId=ui.recipeId })
		-- Rückmeldung ist die Trainingsansicht selbst, die mit dem nächsten Snapshot erscheint
	end)
end

---------------------------------------------------------------------------- Training

local function buildTraining(parent: Frame)
	local scroll = scrollView(parent, "training")
	local _, title, sub = header(scroll, "Training in progress", 1)

	local progressCard = Kit.card(scroll, 2, 8)
	local progressRow = Kit.frame(progressCard, UDim2.new(1, 0, 0, 30))
	progressRow.LayoutOrder = 1
	local percent = Kit.text(progressRow, "0%", 26, F.black, C.text)
	local eta = Kit.text(progressRow, "", 16, F.bold, C.muted)
	eta.AnchorPoint = Vector2.new(1, 0)
	eta.Position = UDim2.fromScale(1, 0)
	local bar = Kit.bar(progressCard, 14, 2)

	local lossCard = Kit.card(scroll, 3, 8)
	Theme.bindAccent(lossCard, "BackgroundColor3", Theme.tint(0.9)) -- Signatur: der Trainingslauf
	local lossRow = Kit.frame(lossCard, UDim2.new(1, 0, 0, 20))
	lossRow.LayoutOrder = 1
	Kit.caption(lossRow, "Training loss (lower is better)")
	local lossValue = Kit.text(lossRow, "", 16, F.bold, C.text)
	lossValue.AnchorPoint = Vector2.new(1, 0)
	lossValue.Position = UDim2.fromScale(1, 0)
	lossValue.Font = F.display
	local graph = Kit.frame(lossCard, UDim2.new(1, 0, 0, 190))
	graph.LayoutOrder = 2
	graph.BackgroundTransparency = 0.2
	graph.BackgroundColor3 = C.bg
	graph.ClipsDescendants = true
	Kit.corner(graph, 10)
	for i = 1, 3 do
		local line = Kit.frame(graph, UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, i / 4, 0))
		line.BackgroundTransparency = 0.94
		line.BackgroundColor3 = C.line
	end
	local lossBars: { Frame } = {}
	for i = 1, T.lossPoints do
		local b = Kit.frame(graph, UDim2.new(1 / T.lossPoints, -3, 0.02, 0), UDim2.new((i - 1) / T.lossPoints, 1, 1, 0))
		b.AnchorPoint = Vector2.new(0, 1)
		b.BackgroundTransparency = 0.88
		Theme.bindAccent(b, "BackgroundColor3")
		Kit.corner(b, 2)
		local fade = Instance.new("UIGradient") -- Säulen leuchten oben, laufen nach unten aus
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new(0, 0.7)
		fade.Parent = b
		lossBars[i] = b
	end

	local metrics = Kit.grid(scroll, 4, 50, 10, 4)
	local mCompute = Kit.metric(metrics, "Compute", 1, 18)
	local mCost = Kit.metric(metrics, "Cost", 2, 18)
	local mData = Kit.metric(metrics, "Data", 3, 18)
	local mQuality = Kit.metric(metrics, "Quality mod", 4, 18)

	-- Entscheidungs-Event
	local eventCard = Kit.card(scroll, 5, 10)
	eventCard.Visible = false
	local eventStroke = eventCard:FindFirstChildOfClass("UIStroke")
	if eventStroke then
		eventStroke.Color = C.warn
		eventStroke.Transparency = 0.3
		eventStroke.Thickness = 2
		local lit = eventStroke:FindFirstChildOfClass("UIGradient") -- Warnrahmen gleichmäßig, ohne Lichtverlauf
		if lit then
			lit:Destroy()
		end
	end
	local eventTitle = Kit.text(eventCard, "", 22, F.black, C.warn)
	eventTitle.LayoutOrder = 1
	local eventText = Kit.para(eventCard, "", 15, C.text, 2)
	local choiceRow = Kit.grid(eventCard, 2, 66, 10, 3)
	local choiceButtons: { TextButton } = {}
	local choiceIds: { string } = {}
	for i = 1, 2 do
		local button = Kit.button(choiceRow, "", if i == 1 then "secondary" else "warn")
		button.LayoutOrder = i
		button.RichText = true
		button.TextWrapped = true
		choiceButtons[i] = button
		choiceIds[i] = ""
		Kit.onClick(button, function()
			local choice = choiceIds[i]
			if choice ~= "" then
				ActionController.call("ResolveEvent", { choice = choice })
			end
		end)
	end
	local countdown = Kit.para(eventCard, "", 13, C.muted, 4)
	local currentEvent = ""
	local defaultLabel = ""

	local logCard = Kit.card(scroll, 6, 4)
	Kit.caption(logCard, "Log", 0)
	local logLabels: { TextLabel } = {}
	for i = 1, T.logLines do
		local line = Kit.text(logCard, "", 13, F.mono, C.muted)
		line.LayoutOrder = i
		logLabels[i] = line
	end

	refreshers.training = function(snapshot: Snapshot)
		local data = snapshot.data
		local training = data.training
		if not training then
			return
		end
		local model: ModelData? = data.models[training.modelId]
		if model then
			title.Text = modelTitle(model)
			if training.refinement then
				local run = math.floor(tonumber(model.iterations) or 0) + 1
				sub.Text = `Refinement {run}/{ModelConfig.REFINE.limit} · {sizeLabel(model.sizeId)} · `
					.. (if model.status == "live" then "keeps serving users with the current version" else `expected overall ~{string.format("%.0f", training.expected)}`)
			else
				sub.Text = `{sizeLabel(model.sizeId)} · {focusLabel(model.focusId)} · expected overall ~{string.format("%.0f", training.expected)}`
			end
			mData.value.Text = Format.tokens(model.dataUsed.total)
		end

		local count = #training.loss
		for i, b in lossBars do
			local value = training.loss[i]
			if value then
				local h = math.clamp((value - LOSS_MIN) / (LOSS_MAX - LOSS_MIN), 0.03, 1)
				b.Size = UDim2.new(1 / T.lossPoints, -3, h, 0)
				b.BackgroundTransparency = if i == count then 0 else 0.25
				b.BackgroundColor3 = if i == count then Theme.accent:Lerp(C.white, 0.45) else Theme.accent
			else
				b.Size = UDim2.new(1 / T.lossPoints, -3, 0.02, 0)
				b.BackgroundTransparency = 0.88
				b.BackgroundColor3 = Theme.accent
			end
		end
		lossValue.Text = string.format("%.3f", training.loss[count] or T.lossStart)

		local fleet = ModelMath.fleet(data.gpus)
		mCompute.value.Text = `{fleet.throughput} u/s`
		mCost.value.Text = Format.money(training.cost)
		mQuality.value.Text = string.format("x%.2f", training.qualityMod)
		mQuality.value.TextColor3 = if training.qualityMod < 1
			then C.bad
			elseif training.qualityMod > 1 then C.good
			else C.text

		for i, line in logLabels do
			line.Text = training.log[i] or ""
		end

		local event = training.event
		local def = if event and event.pending then ModelConfig.getEvent(event.id) else nil
		local choices = if def then def.choices else nil
		eventCard.Visible = choices ~= nil
		if def and choices and event and currentEvent ~= event.id then
			currentEvent = event.id
			eventTitle.Text = def.title
			eventText.Text = def.text .. " Training is paused until you decide."
			defaultLabel = ""
			for i, button in choiceButtons do
				local choice = choices[i]
				button.Visible = choice ~= nil
				if choice then
					choiceIds[i] = choice.id
					button.Text = `<b>{Kit.escape(choice.label)}</b>\n<font size="13">{Kit.escape(choice.desc)}</font>`
					if choice.id == def.default then
						defaultLabel = choice.label
					end
				else
					choiceIds[i] = ""
				end
			end
		elseif not choices then
			currentEvent = ""
		end
	end

	RunService.RenderStepped:Connect(function()
		local currentNav = nav
		local snapshot = StateController.snapshot
		if not currentNav or not currentNav.isOpen() or view ~= "training" or not snapshot then
			return
		end
		local training = snapshot.data.training
		if not training then
			return
		end
		local done, total = StateController.trainingWork()
		local fraction = if total > 0 then done / total else 0
		bar.set(fraction)
		percent.Text = Format.percent(fraction)
		local event = training.event
		if event and event.pending then
			eta.Text = "PAUSED"
			eta.TextColor3 = C.warn
			local remaining = math.max(0, event.expiresAt - workspace:GetServerTimeNow())
			countdown.Text = `Auto-picks "{defaultLabel}" in {math.ceil(remaining)}s`
		else
			eta.Text = "ETA " .. Format.duration(StateController.trainingEta())
			eta.TextColor3 = C.muted
		end
	end)
end

---------------------------------------------------------------------------- Result

local function buildResult(parent: Frame)
	local scroll = scrollView(parent, "result")
	local caption, title, sub = header(scroll, "Training complete", 1)
	caption.TextColor3 = C.good

	local scoreCard = Kit.card(scroll, 2, 6)
	Theme.bindAccent(scoreCard, "BackgroundColor3", Theme.tint(0.88))
	local scoreRow = Kit.row(scoreCard, 84, 18, 1)
	local score = Kit.text(scoreRow, "0.0", 64, F.display)
	score.LayoutOrder = 1
	Theme.bindAccent(score, "TextColor3")
	local scoreInfo = Kit.frame(scoreRow, UDim2.new())
	scoreInfo.AutomaticSize = Enum.AutomaticSize.XY
	scoreInfo.LayoutOrder = 2
	Kit.list(scoreInfo, 4)
	Kit.caption(scoreInfo, "Overall score", 1)
	local delta = Kit.text(scoreInfo, "", 18, F.bold, C.good)
	delta.LayoutOrder = 2
	local rankText = Kit.para(scoreCard, "", 14, C.muted, 2)

	local statsCard = Kit.card(scroll, 3, 8)
	Kit.caption(statsCard, "Benchmarks", 0)
	local rows: { [string]: Kit.StatRow } = {}
	for index, stat in ModelConfig.STATS do
		rows[stat.id] = Kit.statRow(statsCard, stat.label, index)
	end

	local buttons = Kit.row(scroll, 50, 10, 4)
	local release = Kit.button(buttons, "RELEASE", "primary", UDim2.fromOffset(190, 48))
	release.LayoutOrder = 1
	local retrain = Kit.button(buttons, "REFINE", "secondary", UDim2.fromOffset(160, 48))
	retrain.LayoutOrder = 2
	local later = Kit.button(buttons, "LATER", "ghost", UDim2.fromOffset(110, 48))
	later.LayoutOrder = 3

	local animatedFor: string? = nil

	refreshers.result = function(snapshot: Snapshot)
		local id = resultId
		local model: ModelData? = if id then snapshot.data.models[id] else nil
		if not model or not id then
			return
		end
		title.Text = modelTitle(model)
		sub.Text = `{sizeLabel(model.sizeId)} · {focusLabel(model.focusId)} · cost {Format.money(model.trainCost)}`
		if animatedFor ~= id then
			animatedFor = id
			animateNumber(score, model.overall)
		end
		local best = resultBest or bestOverall(snapshot.data, id)
		if best <= 0 then
			delta.Text = "Your first model!"
			delta.TextColor3 = C.good
		else
			local diff = model.overall - best
			delta.Text = `{Format.signed(diff)} vs your best ({string.format("%.1f", best)})`
			delta.TextColor3 = if diff >= 0 then C.good else C.bad
		end
		for statId, row in rows do
			row.set(model.stats[statId] or 0, if (statId == "speed" or statId == "efficiency") then 100 else STAT_CAP)
		end
		local runs = math.floor(tonumber(model.iterations) or 0)
		retrain.Text = if runs >= ModelConfig.REFINE.limit then "REFINED 3/3" else `REFINE {runs + 1}/{ModelConfig.REFINE.limit}`
		Kit.setDisabled(retrain, runs >= ModelConfig.REFINE.limit)
		release.Visible = model.status == "trained"

		-- Marktvergleich nach Overall: live Rivalen (NPC-Labore + andere Firmen aus dem Marktplatz) + eigene Live-Modelle
		local better, total = 0, 1
		local strongestName, strongest = "", 0
		local marketplace: any = snapshot.live.marketplace
		local npcList: { any } = if marketplace then {} else MarketConfig.NPC_MODELS
		for _, npc in npcList do
			local overall = ModelMath.overall(npc.stats)
			total += 1
			if overall > model.overall then
				better += 1
			end
			if overall > strongest then
				strongest = overall
				strongestName = `{npc.company} {npc.name}`
			end
		end
		for _, other in snapshot.data.models do
			if other.status == "live" and other.id ~= id then
				total += 1
				if other.overall > model.overall then
					better += 1
				end
			end
		end
		for _, other in (snapshot.live.marketplace and snapshot.live.marketplace.offers) or {} do
			if not snapshot.data.models[other.id] then
				total += 1
				if other.overall > model.overall then better += 1 end
				if other.overall > strongest then strongest=other.overall; strongestName=other.company.." / "..other.name end
			end
		end
		rankText.Text = `Market check: would rank #{better + 1} of {total} by overall. `
			.. (if model.overall >= strongest
				then "That beats every rival model!"
				else `Strongest rival: {strongestName} ({string.format("%.1f", strongest)}).`)
	end

	Kit.onClick(release, function()
		releaseId = resultId
		resultId = nil
		render()
	end)
	Kit.onClick(retrain, function()
		if resultId then
			local ok=ModelsUI.call("ImproveModel",{modelId=resultId})
			if ok then resultId=nil; render() end
		end
	end)
	Kit.onClick(later, function()
		resultId = nil
		render()
	end)
end

---------------------------------------------------------------------------- Release

local function playLaunch(modelName: string)
	local parent = container
	if not parent then
		return
	end
	local overlay = Kit.blocker(parent, C.bg, 1)
	overlay.ZIndex = 40
	Kit.tween(overlay, 0.2, { BackgroundTransparency = 0.06 })
	local big = Kit.text(overlay, "3", 120, F.black, C.text)
	big.AnchorPoint = Vector2.new(0.5, 0.5)
	big.Position = UDim2.fromScale(0.5, 0.45)
	big.ZIndex = 41
	local scale = Instance.new("UIScale")
	scale.Parent = big
	local subLabel = Kit.text(overlay, "", 20, F.medium, C.muted)
	subLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	subLabel.Position = UDim2.fromScale(0.5, 0.64)
	subLabel.ZIndex = 41

	task.spawn(function()
		for _, step in { "3", "2", "1" } do
			big.Text = step
			scale.Scale = 1.5
			Kit.tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
			task.wait(0.6)
		end
		big.Text = "MODEL LIVE"
		big.TextSize = 84
		big.TextColor3 = Theme.accent
		scale.Scale = 0.6
		Kit.tween(scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
		subLabel.Text = `{modelName} is now serving users`
		task.wait(1.6)
		Kit.tween(overlay, 0.3, { BackgroundTransparency = 1 })
		Kit.tween(big, 0.3, { TextTransparency = 1 })
		Kit.tween(subLabel, 0.3, { TextTransparency = 1 })
		task.wait(0.32)
		overlay:Destroy()
		local currentNav = nav
		if currentNav then
			currentNav.show("market")
		end
	end)
end

local function buildRelease(parent: Frame)
	local scroll = scrollView(parent, "release")
	local _, title, sub = header(scroll, "Launch", 1)
	local left, right = Kit.columns(scroll, 0.55, 16, 2)

	local subPrice = 5
	local apiPrice = MarketConfig.API_PRICE.default
	local marketing = 0
	local target = "general"
	local autoMode = true -- Auto price: the server sets the Recommended price now and re-checks it every 5 min
	local manualTouched = false
	local configuredFor: string? = nil
	local updateForecast: () -> () = function() end
	local requestRecommendation: () -> () = function() end
	local rec: PricingMath.Choice? = nil
	local recKey = ""
	local recGen = 0

	-- Produktlinie (CORE_SPEC 7.1/7.2)
	local lineCard = Kit.card(left, 1, 10)
	Kit.caption(lineCard, "Product line", 1)
	local lineOptions: { Kit.Option } = {}
	for _, line in ModelConfig.LINES do
		table.insert(lineOptions, { id = line.target, label = line.short })
	end
	local lineSeg = Kit.segmented(lineCard, lineOptions, target, function(id: string)
		target = id
		requestRecommendation()
		updateForecast()
	end)
	lineSeg.frame.LayoutOrder = 2
	local lineInfo = Kit.para(lineCard, "", 14, C.text, 3)
	Kit.para(lineCard, "Marketing hits the line's own audience hardest. In the other segments a model is offered too, but clearly weaker than a specialist.", 13, C.dim, 4)

	-- Preis
	local pricing = Kit.card(left, 2, 10)
	Kit.caption(pricing, "Price", 1)
	local subSeg: Kit.Segmented
	local apiSlider: Kit.Slider
	local function paintControls()
		subSeg.set(tostring(subPrice))
		apiSlider.set(apiPrice)
		for _, price in MarketConfig.SUB_PRICES do
			subSeg.setDim(tostring(price), autoMode and price ~= subPrice)
		end
	end
	local modeSeg = Kit.segmented(pricing, {
		{ id = "auto", label = "Auto price" },
		{ id = "manual", label = "Manual" },
	}, "auto", function(id: string)
		autoMode = id == "auto"
		if autoMode and rec then
			subPrice, apiPrice = rec.sub, rec.api
		end
		paintControls()
		updateForecast()
	end)
	modeSeg.frame.LayoutOrder = 2
	local recText = Kit.para(pricing, "", 14, C.text, 3)
	local function toManual()
		manualTouched = true
		if autoMode then
			autoMode = false
			modeSeg.set("manual")
		end
	end

	Kit.caption(pricing, "Subscription (per month = 3 game days)", 4)
	local subOptions: { Kit.Option } = {}
	for _, price in MarketConfig.SUB_PRICES do
		table.insert(subOptions, { id = tostring(price), label = if price == 0 then "Free" else `${price}` })
	end
	subSeg = Kit.segmented(pricing, subOptions, tostring(subPrice), function(id: string)
		toManual()
		subPrice = tonumber(id) or 0
		paintControls()
		updateForecast()
	end)
	subSeg.frame.LayoutOrder = 5
	Kit.para(pricing, "Consumer Chat and Study App users pay a monthly subscription.", 13, C.dim, 6)

	local apiRow = Kit.frame(pricing, UDim2.new(1, 0, 0, 18))
	apiRow.LayoutOrder = 7
	Kit.caption(apiRow, "API price (per 1M tokens)")
	local apiValue = Kit.text(apiRow, "", 16, F.bold, C.text)
	apiValue.AnchorPoint = Vector2.new(1, 0)
	apiValue.Position = UDim2.fromScale(1, 0)
	apiSlider = Kit.slider(
		pricing,
		MarketConfig.API_PRICE.min,
		MarketConfig.API_PRICE.max,
		MarketConfig.API_PRICE.step,
		apiPrice,
		function(value: number)
			toManual()
			apiPrice = value
			updateForecast()
		end
	)
	apiSlider.frame.LayoutOrder = 8
	Kit.para(pricing, "Developer API and Business API customers pay per token. Serving costs you money per token too.", 13, C.dim, 9)

	local mktRow = Kit.frame(pricing, UDim2.new(1, 0, 0, 18))
	mktRow.LayoutOrder = 10
	Kit.caption(mktRow, "Marketing budget")
	local mktValue = Kit.text(mktRow, "", 16, F.bold, C.text)
	mktValue.AnchorPoint = Vector2.new(1, 0)
	mktValue.Position = UDim2.fromScale(1, 0)
	local mktSlider = Kit.slider(pricing, 0, MarketConfig.MARKETING.max, MarketConfig.MARKETING.step, 0, function(value: number)
		marketing = value
		requestRecommendation()
		updateForecast()
	end)
	mktSlider.frame.LayoutOrder = 11
	Kit.para(pricing, "Hype at launch. Fades over about 10 minutes, word of mouth stays.", 13, C.dim, 12)
	local modeNote = Kit.para(pricing, "", 12, C.dim, 13)

	-- rechts: Passung und Prognose
	local fitCard = Kit.card(right, 1, 8)
	Kit.caption(fitCard, "Audience fit (what each group values)", 0)
	local fitRows: { [string]: Kit.StatRow } = {}
	for index, segment in MarketConfig.SEGMENTS do
		fitRows[segment.id] = Kit.statRow(fitCard, segment.label, index)
	end

	local forecastCard = Kit.card(right, 2, 10)
	Kit.caption(forecastCard, "Forecast after 5 minutes", 0)
	local forecastGrid = Kit.grid(forecastCard, 2, 46, 10, 1)
	local fUsers = Kit.metric(forecastGrid, "Users", 1, 20)
	local fNet = Kit.metric(forecastGrid, "Net income", 2, 20)
	local fRevenue = Kit.metric(forecastGrid, "Revenue", 3, 16)
	local fServing = Kit.metric(forecastGrid, "Serving cost", 4, 16)
	local fCompany = Kit.para(forecastCard, "", 13, C.muted, 2)
	local fServers = Kit.para(forecastCard, "", 13, C.dim, 3)
	Kit.para(forecastCard, "Live rivals and your other lines are simulated with the real market rules. Real numbers move with reputation and the market cycle.", 12, C.dim, 4)

	local launch = Kit.button(right, "LAUNCH", "primary", UDim2.new(1, 0, 0, 52))
	launch.LayoutOrder = 3
	launch.TextSize = 17
	local back = Kit.button(right, "BACK", "ghost", UDim2.new(1, 0, 0, 40))
	back.LayoutOrder = 4

	-- Recommended price on the client: the same forecast the server runs at launch, spread over frames
	requestRecommendation = function()
		local snapshot = StateController.snapshot
		local id = releaseId
		local model: ModelData? = if snapshot and id then snapshot.data.models[id] else nil
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
				paintControls()
			end
			updateForecast()
		end)
	end

	updateForecast = function()
		local snapshot = StateController.snapshot
		local id = releaseId
		local model: ModelData? = if snapshot and id then snapshot.data.models[id] else nil
		if not snapshot or not model or not id then
			return
		end
		local data = snapshot.data
		apiValue.Text = Format.price(apiPrice)
		mktValue.Text = Format.money(marketing)
		local money = StateController.money()
		mktValue.TextColor3 = if marketing > money then C.bad else C.text

		-- line: successor, free slot or LINE_LIMIT
		local check = ModelMath.releaseCheck(data, id, target)
		local lineName = ModelsUI.lineLabel(target)
		local predecessor = check.replaced[1]
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
			lineInfo.Text = `{lineName}: successor of {predecessor.name} v{predecessor.version}. Becomes version {ModelMath.lineVersion(data, predecessor.id) + 1} of the line and takes over {math.floor(ModelConfig.MIGRATE * 100 + 0.5)} % of its {Format.compact(users)} users; {predecessor.name} v{predecessor.version} retires.`
			lineInfo.TextColor3 = C.text
		elseif check.ok then
			local slots = if check.slots == math.huge then "" else ` ({check.usedLines + 1} of {check.slots} lines)`
			lineInfo.Text = `{lineName}: a new product line{slots}.`
			lineInfo.TextColor3 = C.text
		else
			lineInfo.Text = `All {check.slots} product lines of {ModelsUI.officeName(data.empire.office)} are live. Pick a live line to release a new version there, or move to a bigger office for another line.`
			lineInfo.TextColor3 = C.warn
		end

		-- price mode texts
		if rec then
			recText.Text = `Recommended: {ModelsUI.priceText(rec.sub, rec.api)}. Best company profit over the next 30 minutes in the forecast.`
		else
			recText.Text = "Calculating the Recommended price from the live market..."
		end
		modeNote.Text = if autoMode
			then "Auto price: the server sets the Recommended price at launch and re-checks it every 5 minutes. Any manual price switches it off for this model."
			else "Manual price: auto price stays off for this model until you switch it on again in the Market app."

		-- 5-minute forecast of this model with live rivals, capacity and your other lines
		local ctx = ModelsUI.context(snapshot)
		local candidate: PricingMath.Entry = {
			id = id,
			stats = model.stats,
			sizeId = model.sizeId,
			subPrice = subPrice,
			apiPrice = apiPrice,
			market = PricingMath.releaseMarket(target, marketing, check.replaced),
			target = target,
		}
		local _, result, last = PricingMath.profit(ctx, candidate, FORECAST_SECONDS)
		local bonuses = EmpireMath.bonuses(data.empire)
		local cycle = EmpireConfig.cycle(snapshot.serverTime)
		local revenue = result.revenue * bonuses.revenue * cycle.revenue
		local cost = result.cost * bonuses.serving * cycle.cost
		fUsers.value.Text = Format.compact(result.users)
		fRevenue.value.Text = Format.money(revenue * Format.DAY_SECONDS) .. "/day"
		fServing.value.Text = Format.money(cost * Format.DAY_SECONDS) .. "/day"
		fNet.value.Text = Format.perDay(revenue - cost)
		fNet.value.TextColor3 = if revenue >= cost then C.good else C.bad
		fCompany.Text = if rec then `With the Recommended price your company earns about {Format.money(rec.profit)} in the next 30 minutes.` else ""
		local serving = ModelsUI.serving(last)
		fServers.Text = if serving.known and (serving.full >= 0.85 or serving.waitlist >= 1)
			then `After launch: {serving.text}.`
			else ""

		if not check.ok then
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
	end

	refreshers.release = function(snapshot: Snapshot)
		local id = releaseId
		local model: ModelData? = if id then snapshot.data.models[id] else nil
		if not model or not id then
			return
		end
		local data = snapshot.data
		title.Text = modelTitle(model)
		sub.Text = `Overall {string.format("%.1f", model.overall)} · {sizeLabel(model.sizeId)} · {focusLabel(model.focusId)} · {ModelsUI.refineText(model)}`

		local money = StateController.money()
		local step = MarketConfig.MARKETING.step
		local affordable = math.max(0, math.min(MarketConfig.MARKETING.max, math.floor(money / step) * step))

		local fits: { { target: string, fit: number } } = {}
		for _, segment in MarketConfig.SEGMENTS do
			local fit = MarketMath.fit(model.stats, segment)
			local row = fitRows[segment.id]
			if row then
				row.set(fit)
			end
			for _, line in ModelConfig.LINES do
				if ModelMath.lineOf(line.target) == segment.id then
					table.insert(fits, { target = line.target, fit = fit })
				end
			end
		end

		if configuredFor ~= id then
			configuredFor = id
			autoMode = true
			manualTouched = false
			modeSeg.set("auto")
			subPrice = 5
			apiPrice = MarketConfig.API_PRICE.default
			marketing = PricingMath.recommendedMarketing(money, EmpireMath.bonuses(data.empire).wage)
			-- best-fitting line that this office allows (a live line = new version, else a free slot)
			table.sort(fits, function(a, b): boolean
				return a.fit > b.fit
			end)
			target = fits[1] and fits[1].target or "general"
			for _, option in fits do
				if ModelMath.releaseCheck(data, id, option.target).ok then
					target = option.target
					break
				end
			end
			lineSeg.set(target)
			paintControls()
		end
		for _, line in ModelConfig.LINES do
			lineSeg.setDim(line.target, not ModelMath.releaseCheck(data, id, line.target).ok)
		end
		-- Regler-Bereich in festen Stufen über dem verfügbaren Geld: fein genug am Anfang,
		-- springt aber nicht bei jedem Einnahmen-Tick
		local range = MARKETING_TIERS[#MARKETING_TIERS]
		for _, tier in MARKETING_TIERS do
			if tier >= affordable then
				range = tier
				break
			end
		end
		mktSlider.setRange(0, range)
		mktSlider.set(marketing)
		marketing = mktSlider.get()
		requestRecommendation()
		updateForecast()
	end

	Kit.onClick(launch, function()
		local id = releaseId
		local snapshot = StateController.snapshot
		local model: ModelData? = if snapshot and id then snapshot.data.models[id] else nil
		if not model or not id then
			return
		end
		local payload: { [string]: any } = { modelId = id, target = target, marketing = marketing, auto = autoMode }
		if not autoMode then
			payload.subPrice = subPrice
			payload.apiPrice = apiPrice
		end
		local ok = ModelsUI.call("ReleaseModel", payload)
		if ok then
			releaseId = nil
			configuredFor = nil
			recKey = ""
			playLaunch(modelTitle(model))
			render()
		end
	end)
	Kit.onClick(back, function()
		releaseId = nil
		render()
	end)
end

---------------------------------------------------------------------------- Einstieg

function LabApp.mount(parent: Frame, navigation: Kit.Nav)
	container = parent
	nav = navigation
	buildCreator(parent)
	buildTraining(parent)
	buildResult(parent)
	buildRelease(parent)

	StateController.onChange(function(_snapshot)
		if parent.Visible and navigation.isOpen() then
			render()
		end
	end)
	StateController.onUiChange(function()
		if parent.Visible and view == "creator" then
			render()
		end
	end)
	StateController.onNotify(function(kind: string, payload: { [string]: any })
		if kind == "TRAINING_COMPLETE" then
			resultId = if typeof(payload.modelId) == "string" then payload.modelId else nil
			resultBest = if typeof(payload.previousBest) == "number" then payload.previousBest else nil
			releaseId = nil
			if navigation.isOpen() then
				navigation.show("lab")
			end
		elseif kind == "TRAINING_EVENT" then
			if navigation.isOpen() then
				navigation.show("lab")
			end
		end
	end)
end

function LabApp.onShow()
	render()
end

-- Von außen (HUD "Launch ..."): direkt die Release-Ansicht eines fertigen Modells öffnen
function LabApp.openRelease(modelId: string)
	releaseId = modelId
	resultId = nil
	render()
end

function LabApp.openSection(section: string)
 local snapshot=StateController.snapshot;if not snapshot then return end
 if section=="evaluation" then
  local model=Journey.latest(snapshot.data)
  if model then resultId=model.id;releaseId=nil;render();task.spawn(function()ActionController.call("EvaluateModel",{modelId=model.id})end)
  else Toast.show("info","Train a model first. Its real benchmark scores will appear here.") end
 elseif section=="release" then
  local model=Journey.latest(snapshot.data,true)
  if model then LabApp.openRelease(model.id) else Toast.show("info","No unreleased trained model yet. Train and evaluate a checkpoint first.") end
 end
end
return LabApp
