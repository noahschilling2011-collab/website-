--!strict
-- Model Studio ceremonies (LAB_SPEC 4.10, 4.11, 4.13):
--   training = the phone game's "in development": the card's cores light up with the real progress, loss bars,
--              the decision card with its real 25 s countdown (training runs on the server; closing never stops it)
--   reveal   = "INTRODUCING <name>": card flip, the overall counts up from the expected value, star pips (market
--              rank), benchmarks fill one by one, audience fit chips, confetti on a record. One tap skips to the end.
--   live     = "NOW LIVE": what the launch did (line, price, marketing, predecessor), users right now, confetti,
--              and "Design its successor".
-- Numbers: the snapshot (model, training), the TRAINING_COMPLETE payload (LabState.reveals) and LabPreview.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local ModelConfig = require(Shared.Config.ModelConfig)
local MarketConfig = require(Shared.Config.MarketConfig)
local ModelMath = require(Shared.ModelMath)
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
local ModelsUI = require(UI.Apps.ModelsUI)
local Parts = require(script.Parent.StudioParts)
local LabPreview = require(script.Parent.LabPreview)
local LabState = require(script.Parent.LabState)

local C = Theme.colors
local F = Theme.font
local T = ModelConfig.TRAINING

type Snapshot = Types.Snapshot
type ModelData = Types.ModelData

local LOSS_MIN, LOSS_MAX = 0.6, 5.2
local CORE = { "reasoning", "coding", "math", "creativity", "knowledge", "reliability" }
local ALL = { "reasoning", "coding", "math", "creativity", "knowledge", "reliability", "speed", "efficiency" }

local Stages = {}

local function cardState(data: Types.PlayerData, model: ModelData, extra: { [string]: any }?): Parts.CardState
	local company = data.company
	local target = if model.release then model.release.target else (LabState.plannedLine[model.id] or (model :: any).plan)
	local state: Parts.CardState = {
		sizeId = model.sizeId,
		focusId = model.focusId,
		name = model.name,
		version = model.version,
		lineShort = Parts.lineShort(if typeof(target) == "string" then target else "general"),
		logo = if company then company.logo else "N",
		look = (model :: any).look,
		recipeId = (model :: any).recipeId,
	}
	if extra then
		for k, v in extra do
			(state :: any)[k] = v
		end
	end
	return state
end

-- The product line a trained model is meant for: planned in the Studio, saved with the model, else best fit.
function Stages.plannedTarget(data: Types.PlayerData, model: ModelData): string
	local planned = LabState.plannedLine[model.id] or (model :: any).plan
	if typeof(planned) == "string" and ModelConfig.getLine(planned) then
		return planned
	end
	local best, bestFit = "general", -math.huge
	for _, line in ModelConfig.LINES do
		local fit = MarketMath.fit(model.stats, LabPreview.segmentOf(line.target))
		if fit > bestFit then
			best, bestFit = line.target, fit
		end
	end
	return best
end

local function keyStat(segment: MarketConfig.SegmentDef): string
	local best, w = "reasoning", -1
	for id, weight in segment.weights do
		if id ~= "speed" and weight > w then
			best, w = id, weight
		end
	end
	return best
end

local function statLabel(id: string): string
	for _, stat in ModelConfig.STATS do
		if stat.id == id then
			return stat.label
		end
	end
	return id
end

---------------------------------------------------------------------------- TRAINING

function Stages.buildTraining(Studio: any): any
	local frame = Kit.frame(Studio.body)
	frame.Name = "TrainingView"
	local main = Kit.frame(frame, UDim2.new(1, 0, 1, -82))
	local bottom = Kit.frame(frame, UDim2.new(1, 0, 0, 74), UDim2.new(0, 0, 1, -74))

	local preview = Kit.frame(main, UDim2.new(1, -734, 1, 0), UDim2.fromOffset(16, 0))
	preview.Name = "Preview"
	local stage = Parts.stage(preview, UDim2.fromOffset(135, 270), 250)
	local card = Parts.modelCard(preview, Vector2.new(190, 246))
	card.frame.Position = UDim2.fromOffset(40, 14)
	local caption = Parts.label(preview, "TRAINING", 20, F.bold, C.muted, UDim2.fromOffset(276, 24), UDim2.new(1, -276, 0, 26))
	local percent = Parts.label(preview, "0 %", 72, F.display, C.text, UDim2.fromOffset(272, 50), UDim2.new(1, -272, 0, 84))
	percent.Name = "Percent"
	percent.TextTruncate = Enum.TextTruncate.None
	local eta = Parts.label(preview, "", 28, F.bold, C.muted, UDim2.fromOffset(276, 136), UDim2.new(1, -276, 0, 34))
	local expectedText = Parts.label(preview, "", 22, F.medium, C.muted, UDim2.fromOffset(276, 180), UDim2.new(1, -276, 0, 56))
	expectedText.TextWrapped = true
	expectedText.TextYAlignment = Enum.TextYAlignment.Top
	local paid = Parts.label(preview, "", 22, F.medium, C.muted, UDim2.fromOffset(276, 240), UDim2.new(1, -276, 0, 28))
	local bar = Kit.bar(preview, 18, 0)
	bar.frame.Position = UDim2.new(0, 0, 1, -18)
	bar.frame.Size = UDim2.new(1, 0, 0, 18)

	local panel = Parts.panel(main, UDim2.new(1, -702, 0, 0), UDim2.new(0, 686, 1, 0))
	panel.Name = "LossPanel"
	local normal = Kit.frame(panel)
	normal.Name = "Normal"
	Parts.label(normal, "Training loss", 34, F.display, C.text, UDim2.fromOffset(18, 10), UDim2.fromOffset(250, 42))
	Parts.label(normal, "lower is better", 22, F.medium, C.muted, UDim2.fromOffset(262, 18), UDim2.fromOffset(220, 30))
	local lossValue = Parts.label(normal, "", 34, F.display, C.text, UDim2.new(1, -218, 0, 10), UDim2.fromOffset(200, 42), Enum.TextXAlignment.Right)
	lossValue.Name = "Loss"
	local graph = Parts.box(normal, UDim2.fromOffset(16, 62), UDim2.new(1, -32, 0, 118), C.bg, 0.2, 12)
	graph.ClipsDescendants = true
	local lossBars: { Frame } = {}
	for i = 1, T.lossPoints do
		local b = Kit.frame(graph, UDim2.new(1 / T.lossPoints, -3, 0.02, 0), UDim2.new((i - 1) / T.lossPoints, 2, 1, 0))
		b.AnchorPoint = Vector2.new(0, 1)
		b.BackgroundTransparency = 0.88
		b.BackgroundColor3 = Theme.accent
		Kit.corner(b, 2)
		lossBars[i] = b
	end
	type Metric = { caption: TextLabel, value: TextLabel }
	local metrics: { Metric } = {}
	for i, name in { "COMPUTE", "COST", "DATA", "QUALITY" } do
		local x = 18 + (i - 1) * 164
		local cap = Parts.label(normal, name, 20, F.bold, C.muted, UDim2.fromOffset(x, 190), UDim2.fromOffset(156, 24))
		local value = Parts.label(normal, "", 26, F.bold, C.text, UDim2.fromOffset(x, 214), UDim2.fromOffset(156, 32))
		metrics[i] = { caption = cap, value = value }
	end
	local logLabels: { TextLabel } = {}
	for i = 1, T.logLines do
		local line = Parts.label(normal, "", 20, F.mono, C.muted, UDim2.fromOffset(18, 254 + (i - 1) * 27), UDim2.new(1, -36, 0, 26))
		logLabels[i] = line
	end

	local decision = Kit.frame(panel)
	decision.Name = "Decision"
	decision.Visible = false
	local eventTitle = Parts.label(decision, "", 34, F.display, C.warn, UDim2.fromOffset(18, 10), UDim2.new(1, -190, 0, 42))
	Parts.label(decision, "DECISION", 20, F.bold, C.warn, UDim2.new(1, -170, 0, 16), UDim2.fromOffset(152, 30), Enum.TextXAlignment.Right)
	local eventText = Parts.label(decision, "", 22, F.medium, C.text, UDim2.fromOffset(18, 56), UDim2.new(1, -36, 0, 58))
	eventText.TextWrapped = true
	eventText.TextYAlignment = Enum.TextYAlignment.Top
	type Choice = { button: TextButton, label: TextLabel, desc: TextLabel, id: string }
	local choices: { Choice } = {}
	for i = 1, 2 do
		local button = Parts.button(decision, "", if i == 1 then "secondary" else "warn", UDim2.fromOffset(16 + (i - 1) * 333, 120), UDim2.fromOffset(321, 118), 26)
		button.Name = "Choice" .. i
		local label = Parts.label(button, "", 26, F.bold, if i == 1 then C.text else C.warn, UDim2.fromOffset(18, 18), UDim2.new(1, -36, 0, 34))
		local desc = Parts.label(button, "", 20, F.bold, if i == 1 then C.muted else C.warn, UDim2.fromOffset(18, 56), UDim2.new(1, -36, 0, 50))
		desc.TextWrapped = true
		desc.TextYAlignment = Enum.TextYAlignment.Top
		local entry: Choice = { button = button, label = label, desc = desc, id = "" }
		choices[i] = entry
		Kit.onClick(button, function()
			if entry.id ~= "" then
				ActionController.call("ResolveEvent", { choice = entry.id })
			end
		end)
	end
	local autoPick = Parts.label(decision, "", 22, F.medium, C.text, UDim2.fromOffset(18, 248), UDim2.new(1, -36, 0, 30))
	autoPick.RichText = true
	local countdown = Kit.bar(decision, 10, 0, C.warn)
	countdown.frame.Position = UDim2.fromOffset(18, 286)
	countdown.frame.Size = UDim2.new(1, -36, 0, 10)
	local stroke = panel:FindFirstChildOfClass("UIStroke")

	Parts.label(bottom, "Runs on the server · close any time", 22, F.medium, C.muted, UDim2.fromOffset(16, 0), UDim2.new(1, -750, 1, 0))
	local labBack = Parts.button(bottom, "‹ LAB", "secondary", UDim2.new(1, -702, 0, 0), UDim2.fromOffset(180, 74), 26)
	local closeAll = Parts.button(bottom, "CLOSE · it keeps training", "ghost", UDim2.new(1, -510, 0, 0), UDim2.fromOffset(494, 74), 26)
	closeAll.Name = "CloseKeepTraining"
	closeAll.TextColor3 = C.text
	Kit.onClick(labBack, function()
		Studio.close()
	end)
	Kit.onClick(closeAll, function()
		local nav = Studio.nav
		Studio.close()
		if nav then
			nav.close()
		end
	end)

	local startingId: string? = nil
	local currentEvent = ""
	local defaultLabel = ""
	local connection: RBXScriptConnection? = nil
	local lastPercent = -1
	local lastEta = -1
	local lastCount = -1
	local compact = true

	local function refresh()
		local snapshot = StateController.snapshot
		if not snapshot then
			return
		end
		local data = snapshot.data
		local training = data.training
		local starting = startingId ~= nil and (not training or training.modelId ~= startingId)
		if training and startingId and training.modelId == startingId then
			startingId = nil
		end
		if not training and not starting then
			return
		end
		local modelId = if training then training.modelId else startingId
		local model = if modelId then data.models[modelId] else nil
		if model then
			local done, total = StateController.trainingWork()
			card.set(cardState(data, model, { progress = if training and not starting and total > 0 then done / total else 0 }))
		end
		card.setPulse(starting)
		if starting or not training then
			caption.Text = "STARTING"
			percent.Text = "0 %"
			eta.Text = "Allocating GPUs…"
			eta.TextColor3 = C.muted
			expectedText.Text = ""
			paid.Text = ""
			normal.Visible = true
			decision.Visible = false
			return
		end
		local refinement = training.refinement == true
		if model then
			if refinement then
				local run = math.floor(tonumber(model.iterations) or 0) + 1
				expectedText.Text = `Refinement {run}/{ModelConfig.REFINE.limit} · keeps serving users with the current version`
			else
				expectedText.Text = string.format("expected ~%.1f", training.expected)
			end
			metrics[3].value.Text = Format.tokens(model.dataUsed.total)
		end
		paid.Text = `{Parts.money(training.cost)} paid`
		local fleet = ModelMath.fleet(data.gpus)
		metrics[1].value.Text = `{string.format("%g", math.round(fleet.throughput * 10) / 10)} u/s`
		metrics[2].value.Text = Parts.money(training.cost)
		metrics[4].value.Text = string.format("×%.2f", training.qualityMod)
		metrics[4].value.TextColor3 = if training.qualityMod < 1 then C.bad elseif training.qualityMod > 1 then C.good else C.text
		local count = #training.loss
		if count ~= lastCount then
			lastCount = count
			for i, b in lossBars do
				local value = training.loss[i]
				if value then
					local h = math.clamp((value - LOSS_MIN) / (LOSS_MAX - LOSS_MIN), 0.03, 1)
					b.Size = UDim2.new(1 / T.lossPoints, -3, h, 0)
					b.BackgroundTransparency = if i == count then 0 else 0.2
					b.BackgroundColor3 = if i == count then card.color:Lerp(C.white, 0.45) else card.color
				else
					b.Size = UDim2.new(1 / T.lossPoints, -3, 0.02, 0)
					b.BackgroundTransparency = 0.88
				end
			end
		end
		lossValue.Text = string.format("%.3f", training.loss[count] or T.lossStart)
		local shownLines = if compact then 2 else T.logLines
		local first = math.max(1, #training.log - shownLines + 1)
		for i, line in logLabels do
			line.Visible = i <= shownLines
			line.Text = training.log[first + i - 1] or ""
		end

		local event = training.event
		local def = if event and event.pending then ModelConfig.getEvent(event.id) else nil
		local list = if def then def.choices else nil
		decision.Visible = list ~= nil
		normal.Visible = list == nil
		caption.Text = if list then "TRAINING PAUSED" else "TRAINING"
		if stroke then
			stroke.Color = if list then C.warn else C.line
			stroke.Transparency = if list then 0.1 else 0.9
			stroke.Thickness = if list then 2 else 1
		end
		if def and list and event and currentEvent ~= event.id then
			currentEvent = event.id
			eventTitle.Text = def.title
			eventText.Text = def.text .. "\nTraining is paused until you decide."
			defaultLabel = ""
			for i, choice in choices do
				local c = list[i]
				choice.button.Visible = c ~= nil
				choice.id = if c then c.id else ""
				if c then
					choice.label.Text = c.label
					choice.desc.Text = c.desc
					if c.id == def.default then
						defaultLabel = c.label
					end
				end
			end
		elseif not list then
			currentEvent = ""
		end
	end

	local function frameStep()
		local snapshot = StateController.snapshot
		local training = if snapshot then snapshot.data.training else nil
		if not snapshot or not training or startingId ~= nil then
			return
		end
		local done, total = StateController.trainingWork()
		local fraction = if total > 0 then done / total else 0
		local p = math.floor(fraction * 100)
		if p ~= lastPercent then
			lastPercent = p
			percent.Text = `{p} %`
			bar.set(fraction)
			card.setProgress(fraction)
		end
		local event = training.event
		if event and event.pending then
			local remaining = math.max(0, event.expiresAt - workspace:GetServerTimeNow())
			local secs = math.ceil(remaining)
			if secs ~= lastEta then
				lastEta = secs
				eta.Text = "PAUSED"
				eta.TextColor3 = C.warn
				autoPick.Text = `Auto-picks <b>{Kit.escape(defaultLabel)}</b> in <font color="#{C.warn:ToHex()}">{secs} s</font>`
				countdown.set(remaining / T.decisionTimeout)
			end
		else
			local secs = math.ceil(StateController.trainingEta())
			if secs ~= lastEta then
				lastEta = secs
				eta.Text = "ETA " .. Format.duration(secs)
				eta.TextColor3 = C.muted
			end
		end
	end

	local view = { frame = frame, title = "Training" }
	function view.show(opts: any)
		startingId = if typeof(opts.starting) == "string" then opts.starting else nil
		lastPercent, lastEta, lastCount, currentEvent = -1, -1, -1, ""
		if connection then
			connection:Disconnect()
		end
		connection = RunService.RenderStepped:Connect(frameStep)
		refresh()
		frameStep()
	end
	function view.hide()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		card.setPulse(false)
	end
	function view.refresh(_snapshot: Snapshot)
		local snapshot = StateController.snapshot
		if snapshot and not snapshot.data.training and startingId == nil then
			return -- finished: LabApp switches to the reveal when TRAINING_COMPLETE arrives
		end
		lastEta = -1
		refresh()
		frameStep()
	end
	function view.focus(): GuiObject?
		return if decision.Visible then choices[1].button else closeAll
	end
	function view.primary() end
	function view.back()
		Studio.close()
	end
	function view.setClass(isCompact: boolean)
		compact = isCompact
		lastCount = -1
		-- regular (desktop): a bigger card standing on the podium, the numbers next to it
		local cw, ch = if compact then 190 else 230, if compact then 246 else 300
		card.resize(Vector2.new(cw, ch))
		card.frame.Position = UDim2.fromOffset(40, if compact then 14 else 30)
		stage.podium.Position = UDim2.fromOffset(40 + cw / 2, (if compact then 14 else 30) + ch + 8)
		local x = 40 + cw + 46
		for _, label in { caption, percent, eta, expectedText, paid } do
			label.Position = UDim2.fromOffset(x - (if label == percent then 4 else 0), label.Position.Y.Offset)
			label.Size = UDim2.new(1, -x, 0, label.Size.Y.Offset)
		end
		refresh()
	end
	return view
end

---------------------------------------------------------------------------- REVEAL

function Stages.buildReveal(Studio: any): any
	local frame = Kit.frame(Studio.body)
	frame.Name = "RevealView"
	local main = Kit.frame(frame, UDim2.new(1, 0, 1, -82))
	local bottom = Kit.frame(frame, UDim2.new(1, 0, 0, 74), UDim2.new(0, 0, 1, -74))
	local stage = Parts.stage(main, UDim2.new(0.5, 0, 0, 294), 340)
	local card = Parts.modelCard(main, Vector2.new(206, 286))
	card.frame.AnchorPoint = Vector2.new(0.5, 0)
	card.frame.Position = UDim2.new(0.5, 0, 0, 8)
	card.frame.ClipsDescendants = true

	local left = Parts.panel(main, UDim2.fromOffset(16, 0), UDim2.new(0, 360, 1, 0))
	left.Name = "Benchmarks"
	local benchCaption = Parts.label(left, "BENCHMARKS", 20, F.bold, C.muted, UDim2.fromOffset(18, 10), UDim2.new(1, -36, 0, 26))
	local bars = Parts.statBars(left, ALL, 30, 128, UDim2.fromOffset(18, 42), UDim.new(1, -36))
	Parts.label(left, "Speed, Efficiency: not in Overall", 20, F.medium, C.dim, UDim2.new(0, 18, 1, -36), UDim2.new(1, -36, 0, 26))

	local right = Parts.panel(main, UDim2.new(1, -436, 0, 0), UDim2.new(0, 420, 1, 0))
	right.Name = "Score"
	local overall = Parts.label(right, "0.0", 64, F.display, Theme.accent, UDim2.fromOffset(18, 4), UDim2.fromOffset(176, 74))
	overall.Name = "Overall"
	overall.TextTruncate = Enum.TextTruncate.None
	local overallCaption = Parts.label(right, "OVERALL", 20, F.bold, C.muted, UDim2.fromOffset(200, 12), UDim2.new(1, -214, 0, 24))
	local pill = Parts.tag(right, "NEW RECORD", C.warn, UDim2.fromOffset(200, 42))
	pill.Name = "RecordPill"
	pill.BackgroundColor3 = C.warn
	pill.BackgroundTransparency = 0.82
	local pipsRow = Kit.frame(right, UDim2.new(1, -36, 0, 30), UDim2.fromOffset(18, 84))
	local pips: { Frame } = {}
	for i = 1, 5 do
		pips[i] = Parts.box(pipsRow, UDim2.fromOffset((i - 1) * 24, 5), UDim2.fromOffset(20, 20), C.raised, 0, 10)
	end
	local word = Parts.label(pipsRow, "", 26, F.display, C.warn, UDim2.fromOffset(130, 0), UDim2.new(1, -130, 1, 0))
	word.Name = "StarsWord"
	local rankLine = Parts.label(right, "", 22, F.medium, C.text, UDim2.fromOffset(18, 118), UDim2.new(1, -36, 0, 28))
	rankLine.RichText = true
	local vsLine = Parts.label(right, "", 22, F.medium, C.text, UDim2.fromOffset(18, 146), UDim2.new(1, -36, 0, 28))
	vsLine.RichText = true
	local nextLine = Parts.label(right, "", 22, F.medium, C.muted, UDim2.fromOffset(18, 174), UDim2.new(1, -36, 0, 28))
	type Chip = { frame: Frame, stroke: UIStroke, top: TextLabel, bottom: TextLabel }
	local chips: { [string]: Chip } = {}
	for i, segment in MarketConfig.SEGMENTS do
		local col, row = (i - 1) % 2, (i - 1) // 2
		local f = Parts.box(right, UDim2.fromOffset(18 + col * 196, 204 + row * 64), UDim2.fromOffset(188, 58), C.panel2, 0, 10)
		local s = Kit.stroke(f, 0.88, C.line, 1)
		local top = Parts.label(f, "", 22, F.bold, C.text, UDim2.fromOffset(10, 2), UDim2.new(1, -16, 0, 28))
		local bot = Parts.label(f, "", 20, F.medium, C.muted, UDim2.fromOffset(10, 28), UDim2.new(1, -16, 0, 26))
		chips[segment.id] = { frame = f, stroke = s, top = top, bottom = bot }
	end

	local note = Parts.label(bottom, "Saved · launch now or later", 22, F.medium, C.muted, UDim2.fromOffset(16, 0), UDim2.new(1, -962, 1, 0))
	local later = Parts.button(bottom, "LATER", "secondary", UDim2.new(1, -938, 0, 0), UDim2.fromOffset(180, 74), 26)
	later.Name = "Later"
	local refine = Parts.button(bottom, "", "secondary", UDim2.new(1, -750, 0, 0), UDim2.fromOffset(330, 74), 22)
	refine.Name = "Refine"
	local launch = Parts.button(bottom, "LAUNCH ›", "primary", UDim2.new(1, -412, 0, 0), UDim2.fromOffset(396, 74), 28)
	launch.Name = "Launch"

	local skip = Instance.new("TextButton")
	skip.Name = "SkipCeremony"
	skip.Text = ""
	skip.BackgroundTransparency = 1
	skip.Size = UDim2.fromScale(1, 1)
	skip.ZIndex = 20
	skip.Visible = false
	skip.Selectable = false
	skip.Parent = main

	local modelId: string? = nil
	local shownPayload: { [string]: any } = {}
	local benchmark = false
	local sequence = 0
	local cancelCount: (() -> ())? = nil
	local finishNow: () -> () = function() end

	local function paint(final: boolean)
		local snapshot = StateController.snapshot
		local id = modelId
		local model = if snapshot and id then snapshot.data.models[id] else nil
		if not snapshot or not model or not id then
			return
		end
		local data = snapshot.data
		local payload = shownPayload
		local target = Stages.plannedTarget(data, model)
		local rank = LabPreview.rank(snapshot, model.stats, target)
		local stars, starWord = LabPreview.stars(rank.rank, rank.total)
		Studio.setCenter(if benchmark then "BENCHMARK REPORT" else "INTRODUCING", `{model.name} v{model.version}`)
		card.set(cardState(data, model, { overall = model.overall, stars = stars }))
		overall.TextColor3 = card.color
		if final then
			overall.Text = string.format("%.1f", model.overall)
		end
		bars.set(model.stats, nil, card.color)
		for i, pip in pips do
			pip.BackgroundColor3 = if i <= stars then C.warn else C.raised
		end
		word.Text = starWord
		local segment = LabPreview.segmentOf(target)
		rankLine.Text = `<b>#{rank.rank} of {rank.total}</b> for {segment.label}`
		local nxt = rank.next
		-- record and comparison (S1 payload; a chip is hidden when its field is missing)
		local refinement = payload.refinement == true
		local before = tonumber(payload.before)
		local previousBest = tonumber(payload.previousBest)
		local best = previousBest or LabPreview.bestOverall(data, id)
		local vsText: string
		if best > 0 then
			local d = model.overall - best
			vsText = `<font color="#{(if d >= 0 then C.good else C.bad):ToHex()}">{Parts.signed(d)}</font> vs best ({string.format("%.1f", best)})`
		else
			vsText = "Your first model"
		end
		local extra: string? = nil -- lucky roll / event / refinement gain
		pill.Visible = false
		if not benchmark then
			if refinement and before then
				extra = `<font color="#{C.good:ToHex()}">{Parts.signed(model.overall - before)}</font> from refinement`
			elseif typeof(payload.expected) == "number" then
				local eventId, outcome = payload.eventId, payload.outcome
				local qualityNote: string? = nil
				local def = if typeof(eventId) == "string" then ModelConfig.getEvent(eventId) else nil
				if def then
					if def.quality and outcome == "auto" then
						qualityNote = `{def.title}: {Parts.signed((def.quality - 1) * 100)} % quality`
					elseif typeof(outcome) == "string" and not string.find(outcome, "_lucky", 1, true) then
						local choice = ModelConfig.getChoice(def, outcome)
						if choice and choice.quality then
							qualityNote = `{choice.label}: {choice.desc}`
						end
					end
				end
				local diff = model.overall - payload.expected
				if qualityNote then
					extra = `{Parts.signed(diff)} vs expected · {qualityNote}`
				else
					extra = `<font color="#{(if diff >= 0 then C.good else C.bad):ToHex()}">{Parts.signed(diff)}</font> lucky roll`
				end
			end
			if typeof(previousBest) == "number" then
				if previousBest <= 0 and not refinement then
					pill.Text = "YOUR FIRST MODEL"
					pill.Visible = true
				elseif model.overall > math.max(previousBest, before or 0) then
					pill.Text = "NEW RECORD"
					pill.Visible = true
				end
			end
		end
		if rank.rank > 1 and nxt then
			-- the goal comes first; the roll moves to the comparison line when it is short
			vsLine.Text = if extra and #extra < 60 then `{vsText} · {extra}` else vsText
			nextLine.Text = string.format("Next to beat: %s · fit %.1f", nxt.name, nxt.quality)
		else
			vsLine.Text = vsText
			nextLine.Text = if extra then extra else "Stars = your rank in the line's market"
		end
		nextLine.RichText = true
		local planned = ModelMath.lineOf(target)
		for _, seg in MarketConfig.SEGMENTS do
			local chip = chips[seg.id]
			local key = keyStat(seg)
			chip.top.Text = string.format("%s %.0f", seg.label, MarketMath.fit(model.stats, seg))
			chip.bottom.Text = string.format("key: %s %.0f", statLabel(key), model.stats[key] or 0)
			local on = seg.id == planned
			chip.stroke.Color = if on then card.color else C.line
			chip.stroke.Transparency = if on then 0 else 0.88
			chip.stroke.Thickness = if on then 2 else 1
		end
		-- buttons
		local check = LabPreview.refineCheck(data, model, StateController.money())
		local runText = `REFINE {math.min(check.runs + 1, ModelConfig.REFINE.limit)}/{ModelConfig.REFINE.limit}`
		if check.ok then
			refine.Text = `{runText} · {Parts.money(check.cost or 0)}`
		else
			refine.Text = `{runText}\n{check.reason or ""}`
		end
		Kit.setDisabled(refine, not check.ok)
		launch.Visible = model.status == "trained"
		later.Text = if model.status == "trained" then "LATER" else "‹ LAB"
		note.Text = if model.status == "trained" then "Saved · launch now or later" else "Live model · benchmark report"
	end

	finishNow = function()
		sequence += 1
		skip.Visible = false
		if cancelCount then
			cancelCount()
			cancelCount = nil
		end
		card.frame.Size = UDim2.fromOffset(if Studio.compact then 206 else 250, if Studio.compact then 286 else 340)
		paint(true)
		bars.fill(#ALL)
		for _, chip in chips do
			chip.frame.Visible = true
		end
		pipsRow.Visible = true
	end
	Kit.onClick(skip, finishNow)

	local function play()
		local snapshot = StateController.snapshot
		local id = modelId
		local model = if snapshot and id then snapshot.data.models[id] else nil
		if not snapshot or not model or not id then
			return
		end
		sequence += 1
		local mine = sequence
		local payload: { [string]: any } = LabState.reveals[id] or {}
		paint(false)
		local from = if typeof(payload.expected) == "number" then payload.expected elseif typeof(payload.before) == "number" then payload.before else 0
		overall.Text = string.format("%.1f", from)
		bars.fill(0)
		pipsRow.Visible = false
		for _, chip in chips do
			chip.frame.Visible = false
		end
		skip.Visible = true
		local w = if Studio.compact then 206 else 250
		local h = if Studio.compact then 286 else 340
		task.spawn(function()
			-- card flip: width 1 -> 0 -> 1 (no Rotation: guiprev and low-end devices draw it flat)
			card.frame.Size = UDim2.fromOffset(w, h)
			Kit.tween(card.frame, 0.17, { Size = UDim2.fromOffset(0, h) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.wait(0.18)
			if mine ~= sequence then
				return
			end
			Kit.tween(card.frame, 0.18, { Size = UDim2.fromOffset(w, h) }, Enum.EasingStyle.Back)
			task.wait(0.2)
			if mine ~= sequence then
				return
			end
			cancelCount = Parts.countUp(overall, from, model.overall, 1.1)
			task.wait(1.15)
			if mine ~= sequence then
				return
			end
			pipsRow.Visible = true
			for i = 1, #ALL do
				bars.fill(i)
				task.wait(0.12)
				if mine ~= sequence then
					return
				end
			end
			for _, chip in chips do
				chip.frame.Visible = true
			end
			if pill.Visible then
				stage.burst(36)
			end
			skip.Visible = false
		end)
	end

	Kit.onClick(later, function()
		Studio.close()
	end)
	Kit.onClick(launch, function()
		local id = modelId
		if id then
			Studio.open("launch", { modelId = id })
		end
	end)
	Kit.onClick(refine, function()
		local id = modelId
		if not id then
			return
		end
		local ok = ModelsUI.call("ImproveModel", { modelId = id })
		if ok then
			Studio.open("training", {})
		end
	end)

	local view = { frame = frame, title = nil :: string? }
	function view.show(opts: any)
		modelId = if typeof(opts.modelId) == "string" then opts.modelId else nil
		local id0 = modelId
		shownPayload = if id0 and LabState.reveals[id0] then LabState.reveals[id0] else {}
		benchmark = opts.benchmark == true
		benchCaption.Text = "BENCHMARKS"
		overallCaption.Text = "OVERALL"
		if benchmark or opts.instant == true then
			finishNow()
		else
			play()
		end
		local id = modelId
		if id and not benchmark then
			LabState.markRevealed(id)
		end
	end
	function view.hide()
		sequence += 1
		skip.Visible = false
		stage.clear()
	end
	function view.refresh(_snapshot: Snapshot)
		if not skip.Visible then
			paint(true)
		end
	end
	function view.focus(): GuiObject?
		return if launch.Visible then launch else later
	end
	function view.primary()
		if skip.Visible then
			finishNow()
		elseif launch.Visible then
			local id = modelId
			if id then
				Studio.open("launch", { modelId = id })
			end
		end
	end
	function view.back()
		Studio.close()
	end
	function view.setClass(isCompact: boolean)
		local w = if isCompact then 206 else 250
		local h = if isCompact then 286 else 340
		card.resize(Vector2.new(w, h))
		stage.podium.Position = UDim2.new(0.5, 0, 0, h + 8)
	end
	function view.finish()
		finishNow()
	end
	return view
end

---------------------------------------------------------------------------- NOW LIVE

function Stages.buildLive(Studio: any): any
	local frame = Kit.frame(Studio.body)
	frame.Name = "LiveView"
	local main = Kit.frame(frame, UDim2.new(1, 0, 1, -82))
	local bottom = Kit.frame(frame, UDim2.new(1, 0, 0, 74), UDim2.new(0, 0, 1, -74))
	local stage = Parts.stage(main, UDim2.new(0.5, 0, 0, 294), 340)
	local card = Parts.modelCard(main, Vector2.new(206, 286))
	card.frame.AnchorPoint = Vector2.new(0.5, 0)
	card.frame.Position = UDim2.new(0.5, 0, 0, 8)

	local left = Parts.panel(main, UDim2.fromOffset(16, 16), UDim2.new(0, 380, 1, -32))
	left.Name = "LaunchDayCard"
	Parts.label(left, "LAUNCH DAY", 20, F.bold, C.muted, UDim2.fromOffset(18, 10), UDim2.new(1, -36, 0, 26))
	local lines: { TextLabel } = {}
	for i = 1, 5 do
		local line = Parts.label(left, "", 22, F.medium, C.text, UDim2.fromOffset(18, 42 + (i - 1) * 34), UDim2.new(1, -36, 0, 30))
		line.RichText = true
		lines[i] = line
	end
	Parts.label(left, "From the server's launch reply", 20, F.medium, C.dim, UDim2.new(0, 18, 1, -36), UDim2.new(1, -36, 0, 26))

	local right = Parts.panel(main, UDim2.new(1, -396, 0, 16), UDim2.new(0, 380, 1, -32))
	right.Name = "UsersCard"
	Parts.label(right, "USERS RIGHT NOW", 20, F.bold, C.muted, UDim2.fromOffset(18, 10), UDim2.new(1, -36, 0, 26))
	local users = Parts.label(right, "0", 52, F.display, C.text, UDim2.fromOffset(18, 38), UDim2.new(1, -36, 0, 62))
	users.Name = "UsersNow"
	local since = Parts.label(right, "", 22, F.bold, C.good, UDim2.fromOffset(18, 102), UDim2.new(1, -36, 0, 28))
	local forecast = Parts.label(right, "", 22, F.medium, C.muted, UDim2.fromOffset(18, 136), UDim2.new(1, -36, 0, 60))
	forecast.TextWrapped = true
	forecast.TextYAlignment = Enum.TextYAlignment.Top
	Parts.label(right, "Counts up live with your company", 20, F.medium, C.dim, UDim2.new(0, 18, 1, -36), UDim2.new(1, -36, 0, 26))

	local successor = Parts.button(bottom, "DESIGN ITS SUCCESSOR ›", "secondary", UDim2.fromOffset(16, 0), UDim2.new(1, -750, 0, 74), 24)
	successor.Name = "DesignSuccessor"
	local backLab = Parts.button(bottom, "BACK TO LAB", "secondary", UDim2.new(1, -702, 0, 0), UDim2.fromOffset(180, 74), 22)
	backLab.Name = "BackToLabLive"
	local market = Parts.button(bottom, "OPEN MARKET ›", "primary", UDim2.new(1, -510, 0, 0), UDim2.fromOffset(494, 74), 28)
	market.Name = "OpenMarket"

	local info: { [string]: any } = {}
	local view = { frame = frame, title = nil :: string? }

	local function refresh()
		local snapshot = StateController.snapshot
		local id = info.modelId
		local model = if snapshot and typeof(id) == "string" then snapshot.data.models[id] else nil
		if not snapshot or not model then
			return
		end
		local data = snapshot.data
		local target = info.target or (if model.release then model.release.target else "general")
		local line = ModelConfig.getLine(target)
		Studio.setCenter("NOW LIVE", if line then line.label else "Model", C.good)
		local rank = LabPreview.rank(snapshot, model.stats, target)
		local stars = LabPreview.stars(rank.rank, rank.total)
		card.set(cardState(data, model, { overall = model.overall, stars = stars }))
		local version = ModelMath.lineVersion(data, model.id)
		lines[1].Text = `Line <b>{if line then line.label else target}</b> · line v{version}`
		local usesSub = PricingMath.lineUsesSub(target)
		local priceText = if usesSub then (if (info.sub or 0) == 0 then "Free" else `${info.sub} per month`) else `${string.format("%g", info.api or 0)} per 1M tokens`
		lines[2].Text = `Price <b>{if info.auto then "Auto" else "Manual"} · {priceText}</b>`
		lines[3].Text = `Marketing <b>{Parts.money(info.marketing or 0)}</b>`
		if typeof(info.replacedName) == "string" then
			lines[4].Text = `<b>{info.replacedName}</b> retired`
			lines[5].Text = `<font color="#{C.good:ToHex()}">{Format.compact(info.moved or 0)} users moved over</font>`
		else
			lines[4].Text = "A new product line"
			lines[5].Text = ""
		end
		local now = 0
		local m = model.market
		if m and model.status == "live" then
			now = MarketMath.totalUsers(m)
		else
			now = info.moved or 0
		end
		users.Text = Format.int(now)
		local base = info.moved or 0
		local diff = now - base
		since.Text = `{if diff >= 0 then "+" else "−"}{Format.int(math.abs(diff))} since launch`
		forecast.Text = if typeof(info.forecastUsers) == "number" then `Forecast: {Format.compact(info.forecastUsers)} users after 5 min` else ""
	end

	function view.show(opts: any)
		info = opts
		refresh()
		stage.burst(36)
	end
	function view.hide()
		stage.clear()
	end
	function view.refresh(_snapshot: Snapshot)
		refresh()
	end
	function view.focus(): GuiObject?
		return market
	end
	function view.primary()
		local nav = Studio.nav
		Studio.close()
		if nav then
			nav.show("market")
		end
	end
	function view.back()
		Studio.close()
	end
	function view.setClass(isCompact: boolean)
		card.resize(if isCompact then Vector2.new(206, 286) else Vector2.new(250, 340))
		stage.podium.Position = UDim2.new(0.5, 0, 0, (if isCompact then 286 else 340) + 8)
	end
	Kit.onClick(market, view.primary)
	Kit.onClick(backLab, function()
		Studio.close()
	end)
	Kit.onClick(successor, function()
		local snapshot = StateController.snapshot
		local id = info.modelId
		local model = if snapshot and typeof(id) == "string" then snapshot.data.models[id] else nil
		if not snapshot or not model then
			return
		end
		local ops: any = snapshot.live.ops
		local saving = typeof(ops) == "table" and ops.saveMode == true
		local focusId = if ModelConfig.getFocus(model.focusId) then model.focusId else "balanced"
		local target = info.target or (if model.release then model.release.target else "general")
		local preset = LabPreview.successorPick(snapshot.data, snapshot.live, target, focusId, StateController.money(), saving)
		Studio.open("design", {
			prefill = {
				target = target,
				name = model.name,
				sizeId = if preset then preset.sizeId else model.sizeId,
				focusId = focusId,
				recipeId = if preset then preset.recipeId else "steady",
			},
		})
	end)
	return view
end

return Stages
