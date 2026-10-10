--!strict
-- Models app = the Lab home + the entry to the Model Studio (LAB_SPEC 2, 4.1; package "lab").
-- The Lab home lives inside the Computer window: DESIGN NEW MODEL, SUCCESSOR, the training slot, models ready to
-- launch, product lines, Lab level and the hall of fame. Designing, training, the reveal, Launch Day and NOW LIVE
-- happen in the full-screen Model Studio (UI/Lab/Studio), modelled on the Design Studio of "Build a Phone Empire".
-- CORE_SPEC 7: product lines with one live model each (a release into a live line is its next version),
-- refinement x/3 (the model keeps serving), stat cap 99, Lab level with its price, Recommended price + Auto price.
-- Public API: mount, onShow, openRelease(modelId), openSection("design"|"train"|"evaluation"|"release"),
-- openStudio(mode, opts), openReveal(modelId), wasRevealed(modelId), plannedLine.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ModelConfig = require(Shared.Config.ModelConfig)
local ModelMath = require(Shared.ModelMath)
local Format = require(Shared.Format)
local Types = require(Shared.Types)
local Journey = require(Shared.JourneyMath)

local UI = script.Parent.Parent
local Client = UI.Parent
local StateController = require(Client.Controllers.StateController)
local ActionController = require(Client.Controllers.ActionController)
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Toast = require(UI.Toast)
local ModelsUI = require(script.Parent.ModelsUI)
local Lab = UI.Lab
local Studio = require(Lab.Studio)
local StudioParts = require(Lab.StudioParts)
local LabPreview = require(Lab.LabPreview)
local LabState = require(Lab.LabState)
local DesignSteps = require(Lab.DesignSteps)
local Stages = require(Lab.Stages)
local LaunchDay = require(Lab.LaunchDay)

local C = Theme.colors
local F = Theme.font
local STAT_CAP = ModelConfig.STAT_CAP

type Snapshot = Types.Snapshot
type ModelData = Types.ModelData

local LabApp = {}

LabApp.plannedLine = LabState.plannedLine

local nav: Kit.Nav? = nil
local container: Frame? = nil
local scroll: ScrollingFrame? = nil
local compactHome: boolean? = nil
local renderHome: (Snapshot) -> () = function(_snapshot: Snapshot) end

type Tokens = { caption: number, body: number, title: number, rowTitle: number, tag: number, button: number, heroH: number, gap: number, pad: number }
local COMPACT: Tokens = { caption = 28, body = 28, title = 44, rowTitle = 34, tag = 28, button = 104, heroH = 236, gap = 14, pad = 18 }
local REGULAR: Tokens = { caption = 14, body = 15, title = 30, rowTitle = 18, tag = 13, button = 52, heroH = 150, gap = 14, pad = 16 }

local function sizeLabel(id: string): string
	local size = ModelConfig.getSize(id)
	return if size then size.label else id
end

local function focusLabel(id: string): string
	local focus = ModelConfig.getFocus(id)
	return if focus then focus.label else id
end

local function designScale(inst: Instance): number
	local s = 1
	local node: Instance? = inst
	while node do
		local u = node:FindFirstChildOfClass("UIScale")
		if u then
			s *= u.Scale
		end
		node = node.Parent
	end
	return if s > 0 then s else 1
end

local function saving(snapshot: Snapshot): boolean
	local ops: any = snapshot.live.ops
	return typeof(ops) == "table" and ops.saveMode == true
end

---------------------------------------------------------------------------- Studio entry points

function LabApp.openStudio(mode: string, opts: { [string]: any }?)
	Studio.open(mode, opts or {})
end

function LabApp.openReveal(modelId: string)
	Studio.open("reveal", { modelId = modelId })
end

function LabApp.wasRevealed(modelId: string): boolean
	return LabState.wasRevealed(modelId)
end

-- From outside (HUD "Release it", Journey LAUNCH, tests): Launch Day of a trained model. A model that finished
-- training in this session and was not revealed yet shows its reveal first (the score stays a surprise).
function LabApp.openRelease(modelId: string)
	if not LabState.wasRevealed(modelId) then
		LabApp.openReveal(modelId)
		return
	end
	Studio.open("launch", { modelId = modelId })
end

local function openSuccessor(snapshot: Snapshot, target: string?)
	local data = snapshot.data
	local pick: LabPreview.Successor? = nil
	if target then
		local status = LabPreview.lineStatus(data, target)
		local model = status.model
		if model then
			local focusId = if ModelConfig.getFocus(model.focusId) then model.focusId else "balanced"
			local preset = LabPreview.successorPick(data, snapshot.live, target, focusId, StateController.money(), saving(snapshot))
			pick = {
				target = target,
				name = model.name,
				focusId = focusId,
				sizeId = if preset then preset.sizeId else model.sizeId,
				recipeId = if preset then preset.recipeId else "steady",
				model = model,
			}
		end
	else
		pick = LabPreview.successor(data, StateController.money(), saving(snapshot), snapshot.live)
	end
	if pick then
		Studio.open("design", { prefill = { target = pick.target, name = pick.name, sizeId = pick.sizeId, focusId = pick.focusId, recipeId = pick.recipeId } })
	end
end

---------------------------------------------------------------------------- Lab home

local function buildHome(parent: Frame, T: Tokens)
	local old = scroll
	if old then
		old:Destroy()
	end
	local list = Kit.scroll(parent)
	list.Name = "LabHome"
	Kit.padding(list, 2, 14, 20, 2)
	Kit.list(list, T.gap)
	scroll = list

	local function text(p: Instance, value: string, size: number, font: Enum.Font?, color: Color3?, order: number?): TextLabel
		local label = Kit.text(p, value, size, font, color)
		label.LayoutOrder = order or 0
		return label
	end
	local function para(p: Instance, value: string, size: number, color: Color3?, order: number?): TextLabel
		return Kit.para(p, value, size, color, order)
	end
	local function card(order: number): Frame
		local f = Kit.card(list, order, 10)
		local pad = f:FindFirstChildOfClass("UIPadding")
		if pad then
			pad.PaddingTop = UDim.new(0, T.pad)
			pad.PaddingBottom = UDim.new(0, T.pad)
			pad.PaddingLeft = UDim.new(0, T.pad)
			pad.PaddingRight = UDim.new(0, T.pad)
		end
		return f
	end
	local function button(p: Instance, value: string, style: Kit.ButtonStyle, width: number): TextButton
		local b = Kit.button(p, value, style, UDim2.fromOffset(width, T.button))
		b.TextSize = math.max(T.body, if T == COMPACT then 28 else 14)
		b.TextWrapped = true
		return b
	end

	-- 1. heading
	local head = Kit.row(list, math.floor(T.title * 1.3), 16, 1)
	text(head, "MODEL LAB", T.title, F.display, C.text, 1)
	text(head, "Design, train and launch your AI models.", T.body, F.medium, C.muted, 2)

	-- 2. hero row: DESIGN NEW MODEL · SUCCESSOR · TRAINING
	local hero = Kit.frame(list, UDim2.new(1, 0, 0, T.heroH))
	hero.LayoutOrder = 2
	local design = Instance.new("TextButton")
	design.Name = "DesignNewModel"
	design.Text = ""
	design.AutoButtonColor = false
	design.BorderSizePixel = 0
	design.Size = UDim2.new(0.45, -10, 1, 0)
	design.Parent = hero
	design.Selectable = true
	Theme.bindAccent(design, "BackgroundColor3")
	Kit.corner(design, 16)
	local icon = Kit.icon(design, "lab", if T == COMPACT then 62 else 34)
	icon.frame.Position = UDim2.fromOffset(T.pad, T.pad)
	icon.setColor(C.bg)
	local designTitle = text(design, "DESIGN NEW MODEL", if T == COMPACT then 40 else 22, F.display, C.bg)
	designTitle.AutomaticSize = Enum.AutomaticSize.None
	designTitle.TextWrapped = true
	designTitle.Size = UDim2.new(1, -2 * T.pad, 0, if T == COMPACT then 96 else 30)
	designTitle.Position = UDim2.new(0, T.pad, 1, if T == COMPACT then -150 else -66)
	designTitle.TextYAlignment = Enum.TextYAlignment.Bottom
	local designSub = text(design, "6 steps · all prefilled", T.caption, F.bold, C.bg)
	designSub.Position = UDim2.new(0, T.pad, 1, if T == COMPACT then -46 else -30)
	Kit.onClick(design, function()
		Studio.open("design", {})
	end)

	local function sideTile(name: string, x: UDim, width: UDim): (TextButton, UIStroke)
		local b = Instance.new("TextButton")
		b.Name = name
		b.Text = ""
		b.AutoButtonColor = false
		b.BorderSizePixel = 0
		b.BackgroundColor3 = C.panel2
		b.Position = UDim2.new(x, UDim.new(0, 0))
		b.Size = UDim2.new(width, UDim.new(1, 0))
		b.Selectable = true
		b.Parent = hero
		Kit.corner(b, 16)
		local stroke = Kit.stroke(b, 0.85)
		Kit.padding(b, T.pad - 4, T.pad, T.pad - 4, T.pad)
		Kit.list(b, if T == COMPACT then 2 else 3)
		return b, stroke
	end
	local successorTile, _ = sideTile("SuccessorTile", UDim.new(0.45, 4), UDim.new(0.27, -8))
	text(successorTile, "SUCCESSOR", T.caption, F.bold, C.muted, 1)
	local succName = text(successorTile, "", T.rowTitle, F.display, C.text, 2)
	local succLine = para(successorTile, "", T.caption, C.muted, 3)
	succLine.Font = F.medium
	local succPlan = para(successorTile, "", T.caption, C.muted, 4)
	succPlan.Font = F.medium
	local succCue = text(successorTile, "REVIEW ›", T.caption, F.bold, Theme.accent, 5)
	local trainTile, trainStroke = sideTile("TrainingTile", UDim.new(0.72, 2), UDim.new(0.28, -2))
	trainStroke.Transparency = 0.7
	text(trainTile, "TRAINING", T.caption, F.bold, C.muted, 1)
	local trainState = text(trainTile, "Free", T.rowTitle, F.display, C.text, 2)
	local trainNote = para(trainTile, "1 training slot · one run at a time", T.caption, C.muted, 3)
	trainNote.Font = F.medium
	Kit.onClick(successorTile, function()
		local snapshot = StateController.snapshot
		if snapshot then
			openSuccessor(snapshot, nil)
		end
	end)
	Kit.onClick(trainTile, function()
		local snapshot = StateController.snapshot
		if snapshot and snapshot.data.training then
			Studio.open("training", {})
		else
			Studio.open("design", {})
		end
	end)

	-- 3. ready to launch
	local readyCard = card(3)
	text(readyCard, "Ready to launch", T.caption, F.bold, C.muted, 1)
	local readyList = Kit.stack(readyCard, 8, 2)
	local readyEmpty = para(readyCard, `Your trained checkpoints appear here. Add 100M fresh tokens to refine a checkpoint with your own GPUs (at most {ModelConfig.REFINE.limit} times per model; every stat caps at {STAT_CAP}).`, T.body, C.dim, 3)
	local readyKey = ""

	-- 4. product lines
	local linesCard = card(4)
	local linesCaption = text(linesCard, "Product lines", T.caption, F.bold, C.muted, 1)
	type LineUi = { detail: TextLabel, tag: TextLabel, successor: TextButton }
	local lineUi: { [string]: LineUi } = {}
	local rowH = if T == COMPACT then 132 else 56
	for index, line in ModelConfig.LINES do
		local row = Kit.frame(linesCard, UDim2.new(1, 0, 0, rowH))
		row.LayoutOrder = 1 + index
		row.BackgroundTransparency = 0.3
		row.BackgroundColor3 = C.bg
		Kit.corner(row, 12)
		local name = text(row, line.label, T.rowTitle, F.bold, C.text)
		name.Position = UDim2.fromOffset(14, if T == COMPACT then 8 else 5)
		local tag = Kit.tag(row, "free", C.dim)
		tag.TextSize = T.tag
		tag.Position = UDim2.fromOffset(if T == COMPACT then 320 else 178, if T == COMPACT then 12 else 7)
		local detail = text(row, "", T.body, F.medium, C.muted)
		detail.AutomaticSize = Enum.AutomaticSize.None
		detail.TextWrapped = true
		detail.TextYAlignment = Enum.TextYAlignment.Top
		detail.Size = UDim2.new(1, if T == COMPACT then -250 else -150, 0, if T == COMPACT then 72 else 22)
		detail.Position = UDim2.fromOffset(14, if T == COMPACT then 52 else 28)
		local succ = button(row, "SUCCESSOR", "secondary", if T == COMPACT then 210 else 120)
		succ.Name = "LineSuccessor"
		succ.AnchorPoint = Vector2.new(1, 0.5)
		succ.Position = UDim2.new(1, -12, 0.5, 0)
		succ.Size = UDim2.fromOffset(if T == COMPACT then 210 else 120, if T == COMPACT then 104 else 40)
		succ.Visible = false
		Kit.onClick(succ, function()
			local snapshot = StateController.snapshot
			if snapshot then
				openSuccessor(snapshot, line.target)
			end
		end)
		lineUi[line.target] = { detail = detail, tag = tag, successor = succ }
	end
	local linesNote = para(linesCard, "", T.body, C.dim, 9)

	-- 5. Lab level
	local labCard = card(5)
	local labTop = Kit.frame(labCard, UDim2.new(1, 0, 0, math.floor(T.rowTitle * 1.4)))
	labTop.LayoutOrder = 1
	local labTitle = text(labTop, "Lab level 0", T.rowTitle + 2, F.display, C.text)
	local labTag = Kit.tag(labTop, "0 / 10", C.muted)
	labTag.TextSize = T.tag
	labTag.AnchorPoint = Vector2.new(1, 0.5)
	labTag.Position = UDim2.new(1, 0, 0.5, 0)
	local labBar = Kit.bar(labCard, if T == COMPACT then 14 else 8, 2)
	para(labCard, "Every level adds +1 to every core stat of the models you train next. Your researchers unlock levels after the whole research tree.", T.body, C.dim, 3)
	local capNote = para(labCard, "", T.body, C.muted, 4)
	local labCost = para(labCard, "", T.body, C.muted, 5)
	local labBuy = Kit.button(labCard, "UPGRADE LAB", "secondary", UDim2.new(1, 0, 0, T.button))
	labBuy.LayoutOrder = 6
	labBuy.TextSize = if T == COMPACT then 30 else 15
	local labCanBuy = false
	Kit.onClick(labBuy, function()
		if not labCanBuy then
			return
		end
		local ok = ModelsUI.call("EmpireAction", { action = "labLevel" })
		if ok then
			Toast.show("success", "Lab upgraded: new models get +1 on every core stat.")
		end
	end)

	-- 6. hall of fame
	local fameCard = card(6)
	text(fameCard, "Hall of fame", T.caption, F.bold, C.muted, 1)
	local fame = Kit.scroll(fameCard, UDim2.new(1, 0, 0, if T == COMPACT then 250 else 120))
	fame.LayoutOrder = 2
	fame.ScrollingDirection = Enum.ScrollingDirection.X
	fame.AutomaticCanvasSize = Enum.AutomaticSize.X
	fame.ScrollBarThickness = 4
	Kit.list(fame, 12, true)
	local fameEmpty = para(fameCard, "Every model you train gets its card here.", T.body, C.dim, 3)
	local fameKey = ""

	local function rebuildReady(snapshot: Snapshot)
		local data = snapshot.data
		local ids: { string } = {}
		for _, id in data.modelOrder do
			local model: ModelData? = data.models[id]
			if model and model.status == "trained" then
				table.insert(ids, id)
			end
		end
		local parts: { string } = {}
		local money = StateController.money()
		for _, id in ids do
			local model = data.models[id]
			local check = LabPreview.refineCheck(data, model, money)
			table.insert(parts, `{id}:{model.iterations or 0}:{check.ok}:{check.reason or ""}:{LabState.wasRevealed(id)}:{data.training ~= nil}`)
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
			local row = Kit.frame(readyList, UDim2.new(1, 0, 0, if T == COMPACT then 124 else 58))
			row.LayoutOrder = index
			row.BackgroundTransparency = 0.3
			row.BackgroundColor3 = C.bg
			Kit.corner(row, 12)
			local width = if T == COMPACT then 210 else 120
			local name = text(row, `{model.name} v{model.version}`, if T == COMPACT then 36 else 17, F.bold, C.text)
			name.Position = UDim2.fromOffset(14, if T == COMPACT then 12 else 7)
			name.AutomaticSize = Enum.AutomaticSize.None
			name.Size = UDim2.new(1, -2 * width - 40, 0, if T == COMPACT then 44 else 22)
			name.TextTruncate = Enum.TextTruncate.AtEnd
			local revealed = LabState.wasRevealed(id)
			local scoreText = if revealed then string.format("%.1f", model.overall) else "score hidden"
			local sub = text(row, `{sizeLabel(model.sizeId)} · {focusLabel(model.focusId)} · {scoreText} · {ModelsUI.refineText(model)}`, T.body, F.medium, C.muted)
			sub.Position = UDim2.fromOffset(14, if T == COMPACT then 62 else 32)
			sub.AutomaticSize = Enum.AutomaticSize.None
			sub.Size = UDim2.new(1, -2 * width - 40, 0, if T == COMPACT then 40 else 18)
			sub.TextTruncate = Enum.TextTruncate.AtEnd
			local check = LabPreview.refineCheck(data, model, money)
			local runs = math.floor(tonumber(model.iterations) or 0)
			local runText = if runs >= ModelConfig.REFINE.limit then "REFINED" else `REFINE {runs + 1}/{ModelConfig.REFINE.limit}`
			local refine = button(row, if check.ok then `{runText}\n{StudioParts.money(check.cost or 0)}` else `{runText}\n{check.reason or ""}`, "secondary", width)
			refine.Name = "Refine"
			refine.TextSize = if T == COMPACT then 28 else 13
			refine.AnchorPoint = Vector2.new(1, 0.5)
			refine.Position = UDim2.new(1, -width - 24, 0.5, 0)
			refine.Size = UDim2.fromOffset(width, if T == COMPACT then 104 else 44)
			Kit.setDisabled(refine, not check.ok)
			Kit.onClick(refine, function()
				local ok = ModelsUI.call("ImproveModel", { modelId = id })
				if ok then
					Studio.open("training", {})
				end
			end)
			local launch = button(row, if revealed then "LAUNCH" else "REVEAL", "primary", width)
			launch.Name = if revealed then "Launch" else "Reveal"
			launch.AnchorPoint = Vector2.new(1, 0.5)
			launch.Position = UDim2.new(1, -12, 0.5, 0)
			launch.Size = UDim2.fromOffset(width, if T == COMPACT then 104 else 44)
			Kit.onClick(launch, function()
				LabApp.openRelease(id)
			end)
		end
		readyEmpty.Visible = #ids == 0
	end

	local function rebuildFame(snapshot: Snapshot)
		local data = snapshot.data
		local ids: { string } = {}
		for i = #data.modelOrder, 1, -1 do
			local id = data.modelOrder[i]
			local model = data.models[id]
			if model and model.status ~= "training" then
				table.insert(ids, id)
				if #ids >= 8 then
					break
				end
			end
		end
		local parts: { string } = {}
		for _, id in ids do
			local model = data.models[id]
			table.insert(parts, `{id}:{model.status}:{model.overall}:{LabState.wasRevealed(id)}`)
		end
		local key = table.concat(parts, ",")
		if key == fameKey then
			return
		end
		fameKey = key
		for _, child in fame:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local company = data.company
		for index, id in ids do
			local model = data.models[id]
			local width = if T == COMPACT then 230 else 150
			local f = Kit.frame(fame, UDim2.new(0, width, 1, -8))
			f.LayoutOrder = index
			f.BackgroundTransparency = 0
			f.BackgroundColor3 = C.bg
			Kit.corner(f, 12)
			local color = StudioParts.cardColor(model.focusId, (model :: any).look)
			Kit.stroke(f, 0.3, color, if T == COMPACT then 2 else 1)
			local stripe = Kit.frame(f, UDim2.new(1, 0, 0, if T == COMPACT then 10 else 6))
			stripe.BackgroundTransparency = 0
			stripe.BackgroundColor3 = color
			Kit.corner(stripe, 12)
			local inner = Kit.frame(f, UDim2.new(1, -24, 1, -20), UDim2.fromOffset(12, if T == COMPACT then 16 else 10))
			Kit.list(inner, if T == COMPACT then 4 else 2)
			local nm = text(inner, `{model.name} v{model.version}`, if T == COMPACT then 30 else 15, F.bold, C.text, 1)
			nm.AutomaticSize = Enum.AutomaticSize.None
			nm.Size = UDim2.new(1, 0, 0, if T == COMPACT then 36 else 18)
			nm.TextTruncate = Enum.TextTruncate.AtEnd
			local revealed = LabState.wasRevealed(id)
			text(inner, if revealed then string.format("Overall %.1f", model.overall) else "Overall ?", T.caption, F.medium, C.muted, 2)
			local release = model.release
			local tagText = if model.status == "live" and release then `LIVE · {StudioParts.lineShort(release.target)}` elseif model.status == "trained" then "READY" else "RETIRED"
			local tag = Kit.tag(inner, tagText, if model.status == "live" then C.good elseif model.status == "trained" then Theme.accent else C.dim, 3)
			tag.TextSize = T.tag
			local _ = company
			if release and (model.status == "live" or model.status == "retired") then
				-- the phone's model chat (design/requests/phone.md #3): only released models can chat
				local chat = Kit.button(inner, "CHAT ›", "secondary", UDim2.new(1, 0, 0, if T == COMPACT then 104 else 34))
				chat.Name = "Chat"
				chat.LayoutOrder = 4
				chat.TextSize = if T == COMPACT then 28 else 14
				Kit.onClick(chat, function()
					-- lazy require: PhoneController requires Screens/Computer, which requires the apps (no require cycle)
					local ok, phone = pcall(require, Client.Controllers.PhoneController)
					local currentNav = nav
					if ok and typeof(phone) == "table" and typeof((phone :: any).openChat) == "function" then
						(phone :: any).openChat(id)
						if currentNav then
							currentNav.close()
						end
					end
				end)
			end
		end
		fameEmpty.Visible = #ids == 0
	end

	renderHome = function(snapshot: Snapshot)
		local data = snapshot.data
		local money = StateController.money()
		local first = LabPreview.isFirstModel(data)
		designSub.Text = if first then "Your first model · 6 steps" else "6 steps · all prefilled"

		-- successor hero
		local succ = LabPreview.successor(data, money, saving(snapshot), snapshot.live)
		if succ then
			local status = LabPreview.lineStatus(data, succ.target)
			local est = LabPreview.estimate(data, { sizeId = succ.sizeId, focusId = succ.focusId, recipeId = succ.recipeId }, nil)
			succName.Text = `{succ.name} v{ModelMath.nextVersion(data, succ.name)}`
			local age = ModelMath.ageFit(ModelMath.versionAge(succ.model))
			succLine.Text = `{StudioParts.lineShort(succ.target)} · −{string.format("%.0f", age)} fit`
			succPlan.Text = string.format("%s %s · ~%.0f", sizeLabel(succ.sizeId), StudioParts.RECIPE_LABEL[succ.recipeId] or "", est.overall)
			succCue.Visible = true
			local _ = status
			Kit.setDisabled(successorTile :: any, false)
		else
			succName.Text = "None yet"
			succLine.Text = "Launch a model first"
			succPlan.Text = ""
			succCue.Visible = false
		end
		successorTile.Active = succ ~= nil

		-- training slot
		local training = data.training
		if training then
			local done, total = StateController.trainingWork()
			local p = if total > 0 then done / total else 0
			local tm = data.models[training.modelId]
			local pending = training.event and training.event.pending
			trainState.Text = if pending then "Decision!" else string.format("%d %% · ETA %s", math.floor(p * 100), Format.duration(StateController.trainingEta()))
			trainState.TextColor3 = if pending then C.warn else Theme.accent
			trainNote.Text = `{if tm then tm.name .. " v" .. tm.version else "Training"} · 1 training slot · one run at a time`
		else
			trainState.Text = "Free"
			trainState.TextColor3 = C.text
			trainNote.Text = "1 training slot · one run at a time"
		end

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
				refs.successor.Visible = true
			elseif lineRow.open then
				local left = slots - usedLines
				refs.detail.Text = `Free: {left} more line{if left == 1 then "" else "s"} at this office`
				refs.detail.TextColor3 = C.muted
				refs.tag.Text = "FREE"
				refs.tag.TextColor3 = C.muted
				refs.successor.Visible = false
			else
				local nextStage = ModelsUI.officeForLines(usedLines)
				refs.detail.Text = if nextStage then `Another line opens with {ModelsUI.officeName(nextStage)}` else "All lines are in use"
				refs.detail.TextColor3 = C.dim
				refs.tag.Text = "LOCKED"
				refs.tag.TextColor3 = C.dim
				refs.successor.Visible = false
			end
		end
		linesNote.Text = `One live model per line. A release into a live line is its next version: it takes over {math.floor(ModelConfig.MIGRATE * 100 + 0.5)} % of the users. Models age: up to -8 fit after 3 game days, so ship new versions.`

		-- Lab level
		local lab = ModelsUI.lab(data, money)
		labTitle.Text = `Lab level {lab.level}`
		labTag.Text = `{lab.level} / {lab.max}`
		labBar.set(lab.level / math.max(1, lab.max))
		capNote.Text = `Every stat caps at {STAT_CAP}.` .. (if lab.level > 0 then ` Lab level {lab.level} adds +{lab.level} to each.` else "")
		labCost.Text = lab.reason
		labCanBuy = lab.canBuy
		labBuy.Text = if lab.level >= lab.max then "LAB AT MAX LEVEL" else `UPGRADE LAB · {Format.int(lab.points)} RP + {Format.money(lab.cash)}`
		Kit.setDisabled(labBuy, not lab.canBuy)

		rebuildReady(snapshot)
		rebuildFame(snapshot)
	end
end

local function render()
	local snapshot = StateController.snapshot
	local parent = container
	if not snapshot or not parent then
		return
	end
	local compact = designScale(parent) < 0.62
	if compact ~= compactHome then
		compactHome = compact
		buildHome(parent, if compact then COMPACT else REGULAR)
	end
	renderHome(snapshot)
end

---------------------------------------------------------------------------- mount

function LabApp.mount(parent: Frame, navigation: Kit.Nav)
	container = parent
	nav = navigation
	Studio.init(parent, navigation)
	Studio.register("design", DesignSteps.build)
	Studio.register("training", Stages.buildTraining)
	Studio.register("reveal", Stages.buildReveal)
	Studio.register("live", Stages.buildLive)
	Studio.register("launch", LaunchDay.build)
	table.insert(Studio.onClosed, function()
		if parent.Visible then
			render()
		end
	end)

	StateController.onChange(function(_snapshot)
		if parent.Visible and navigation.isOpen() then
			render()
		end
	end)
	StateController.onUiChange(function()
		if parent.Visible and navigation.isOpen() and not Studio.isOpen() then
			render()
		end
	end)
	parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if compactHome ~= nil and (designScale(parent) < 0.62) ~= compactHome then
			task.defer(render)
		end
	end)
	StateController.onNotify(function(kind: string, payload: { [string]: any })
		if kind == "TRAINING_COMPLETE" then
			LabState.storeReveal(payload)
			if navigation.isOpen() then
				navigation.show("lab") -- onShow plays the reveal
			end
		elseif kind == "TRAINING_EVENT" then
			if navigation.isOpen() then
				navigation.show("lab")
				Studio.open("training", {})
			end
		end
	end)
end

-- A pending decision opens the training stage; a model that finished in this session opens its reveal.
function LabApp.onShow()
	render()
	local snapshot = StateController.snapshot
	if not snapshot then
		return
	end
	local data = snapshot.data
	local training = data.training
	if training and training.event and training.event.pending then
		if Studio.mode ~= "training" then
			Studio.open("training", {})
		end
		return
	end
	for _, id in data.modelOrder do
		local model = data.models[id]
		if model and model.status ~= "training" and not LabState.wasRevealed(id) then
			if Studio.mode ~= "reveal" then
				LabApp.openReveal(id)
			end
			return
		end
	end
	if Studio.isOpen() then
		Studio.refresh()
	end
end

function LabApp.openSection(section: string)
	local snapshot = StateController.snapshot
	if not snapshot then
		return
	end
	if section == "design" then
		Studio.open("design", {})
	elseif section == "train" then
		Studio.open(if snapshot.data.training then "training" else "design", {})
	elseif section == "evaluation" then
		local model = Journey.latest(snapshot.data)
		if model then
			Studio.open("reveal", { modelId = model.id, benchmark = LabState.wasRevealed(model.id) })
			task.spawn(function()
				ActionController.call("EvaluateModel", { modelId = model.id })
			end)
		else
			Toast.show("info", "Train a model first. Its real benchmark scores will appear here.")
		end
	elseif section == "release" then
		local model = Journey.latest(snapshot.data, true)
		if model then
			LabApp.openRelease(model.id)
		else
			Toast.show("info", "No unreleased trained model yet. Train and evaluate a checkpoint first.")
		end
	end
end

return LabApp
