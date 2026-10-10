--!strict
-- HUD rechts oben (links oben gehört dem Roblox-Chat):
--   Glas-Panel (Firma, Geld, Nutzer, Reputation), "Next goal"-Karte, COMPUTER-Button
-- The "Next goal" card (CORE_SPEC 8.2) always shows ONE goal: EmpireMath.nextGoal(data, live) gives the goal,
-- its progress (have / need) and the ETA in minutes; this module only words it and adds the concrete hint from
-- real state (journey step, client trip, Save mode, research, Lab level). A pending training decision is the
-- only thing shown instead of the goal (it auto-resolves within seconds). A tap opens the relevant app.
-- Phones (small HUD scale, UIRoot < COMPACT_SCALE): the whole column gets its own UIScale COMPACT_BOOST and larger
-- compact text, so the goal title reads at about 13 pt and the progress at about 11 pt on an iPhone in landscape
-- (UIRoot 0.432 x 1.5), and the buttons are real touch targets (>= 44 pt); the card drops its hint line and shows the
-- step name in the progress text instead. The column is 300 design px wide at -16 from the right edge; the lane it
-- takes (300 x boost + 16, in HUD-layer px) is published as the HUD frame's attribute "LaneWidth" for the company
-- phone (Screens/Phone should keep left of it; design/requests/apps.md #4).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local CompanyConfig = require(Shared.Config.CompanyConfig)
local EmpireConfig = require(Shared.Config.EmpireConfig)
local ModelConfig = require(Shared.Config.ModelConfig)
local EmpireMath = require(Shared.EmpireMath)
local CompanyOps = require(Shared.CompanyOps)
local ModelMath = require(Shared.ModelMath)
local Journey = require(Shared.JourneyMath)
local Format = require(Shared.Format)
local Types = require(Shared.Types)

local UI = script.Parent.Parent
local Client = UI.Parent
local StateController = require(Client.Controllers.StateController)
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Toast = require(UI.Toast)
local Computer = require(UI.Screens.Computer)
local LabApp = require(UI.Apps.LabApp)

local C = Theme.colors
local F = Theme.font

type Snapshot = Types.Snapshot
type ModelData = Types.ModelData
-- One rendered goal: what the card shows and where a tap goes.
export type GoalView = {
	id: string, -- nextGoal id, "decision" (pending training event) or "done"
	caption: string,
	title: string,
	body: string, -- hint line (hidden on phones)
	progress: string, -- left text under the bar on desktops ("Client ✓ · $18,400 / $27,000", "Step 2 of 7")
	compactProgress: string, -- the same on the compact phone card ("Step 1 of 7 · Get training data", "Client ✓ · $18.4K / $27K")
	shortProgress: string, -- used when the text above does not fit beside the ETA ("Step 1/7 · Get training data", "$18.4K / $27K")
	eta: string, -- right text ("~2 min", "ready", "back in 1 min 20 s", "")
	fraction: number?, -- bar fill 0..1 (nil = no bar)
	training: boolean, -- bar follows the running training (smooth, client-side)
	warn: boolean,
	saving: boolean, -- Save mode is on (server: live.ops.saveMode)
	app: string,
	section: string?,
	releaseId: string?,
}

local WIDTH = 300 -- Screens/Phone.HUD_WIDTH depends on this width and the 16 px margin (x COMPACT_BOOST on phones)
local MARGIN = 16
local COMPACT_SCALE = 0.62 -- UIRoot scale below which the HUD is drawn compact (phones in landscape)
local COMPACT_BOOST = 1.5 -- the column's own UIScale in compact mode (0.432 x 1.5 = 0.65 on an iPhone 12-14)
local TOUCH_BUTTON = 70 -- compact touch buttons: 70 x 1.5 x 0.432 = 45 pt (Apple's 44 pt minimum)

local HUD = {}
HUD.WIDTH = WIDTH
HUD.MARGIN = MARGIN
HUD.COMPACT_BOOST = COMPACT_BOOST

local root: Frame? = nil

local function dollars(n: number): string
	return (if n < 0 then "-$" else "$") .. Format.int(math.abs(n))
end
-- "Client ✓ · $18,400 / $27,000" (the first client is signed), the compact form "Client ✓ · $18.4K / $27K" and the shortest
-- "$18.4K / $27K": the card shows the first one that fits beside the ETA, so the goal amount is never cut off
local function moneyProgress(prefix: string, have: number, need: number): (string, string, string)
	local short = Format.money(have) .. " / " .. Format.money(need)
	return prefix .. dollars(have) .. " / " .. dollars(need), prefix .. short, short
end
-- about how wide a line of text is (Gotham-like UI fonts average ~0.55 em per character)
local function textWidth(text: string, size: number): number
	return (utf8.len(text) or #text) * size * 0.55
end
HUD.textWidth = textWidth
-- no live model at all (released ones may have been retired): the hint asks for a release, never "best: 0"
local function needsText(c: any, best: number): string
	if best <= 0 then
		return `{c.name} needs {c.stat} {c.minimum}. No model is live: release one first.`
	end
	return `{c.name} needs {c.stat} {c.minimum}. Your best live model: {math.floor(best)}.`
end

-- "~3 min", "~1.4 h", "<1 min", "" (no profit = no ETA)
function HUD.etaText(minutes: number?): string
	if minutes == nil or minutes ~= minutes or minutes == math.huge then
		return ""
	end
	if minutes <= 0 then
		return "ready"
	end
	if minutes < 1 then
		return "<1 min"
	end
	if minutes < 120 then
		return "~" .. tostring(math.ceil(minutes)) .. " min"
	end
	if minutes < 600 then
		return string.format("~%.1f h", minutes / 60)
	end
	return string.format("~%d h", math.ceil(minutes / 60))
end

local function trainedModel(data: any): ModelData?
	for _, id in data.modelOrder do
		local m: ModelData? = data.models[id]
		if m and m.status == "trained" then
			return m
		end
	end
	return nil
end

local JOURNEY_HINT: { [string]: string } = {
	data = "Get training data: scrape the web for free or buy a pack in Datasets.",
	compute = "Check your compute: the laptop trains a 100M model; more VRAM fits bigger ones.",
	design = "Design your model in Models: pick a name, size and focus.",
	train = "Start the training run in Models and watch the loss drop.",
	evaluation = "Evaluate it in Models, then release it.",
	release = "Pick the Recommended price and launch it.",
	grow = "Users pay for your live model every second.",
}

-- seconds of play left until a trip is back (live.ops.trips[*].back is in empire.seconds)
local function tripFor(live: any, clientId: string): any
	local ops = live.ops
	if typeof(ops) ~= "table" or typeof(ops.trips) ~= "table" then
		return nil
	end
	for _, trip in ops.trips do
		if typeof(trip) == "table" and trip.client == clientId then
			return trip
		end
	end
	return nil
end

-- Words the goal of EmpireMath.nextGoal for the HUD (pure: snapshot in, view out; tests call it directly).
function HUD.describe(snapshot: Snapshot, selection: any?): GoalView
	local data: any = snapshot.data
	local live: any = snapshot.live
	local e = data.empire
	local ops = if typeof(live.ops) == "table" then live.ops else {}
	local saving = ops.saveMode == true
	local view: GoalView = {
		id = "done", caption = "Next goal", title = "", body = "", progress = "", compactProgress = "", shortProgress = "", eta = "", fraction = nil,
		training = false, warn = false, saving = saving, app = "empire", section = nil, releaseId = nil,
	}
	local training = data.training
	local trainingModel: ModelData? = if training then data.models[training.modelId] else nil
	if training and training.event and training.event.pending then
		view.id = "decision"
		view.caption = "Decision needed"
		view.title = "Your training run needs a decision"
		view.body = "Open Models and choose what to do. Otherwise the default is picked automatically."
		view.app = "lab"
		view.warn = true
		return view
	end
	local goal = EmpireMath.nextGoal(data, live)
	if goal == nil then
		view.title = "Every goal reached"
		view.body = "Keep shipping new versions: models age and rivals never stop."
		view.app = "market"
		return view
	end
	view.id = goal.id
	view.title = goal.text
	local have, need = tonumber(goal.have) or 0, math.max(1, tonumber(goal.need) or 1)
	local id = goal.id
	local compact: string? = nil
	local short: string? = nil
	if id == "train" then
		local journey = Journey.progress(data, selection)
		view.app = journey.step.app
		view.section = journey.step.section
		if training then
			view.body = (if trainingModel then `Training {trainingModel.name} v{trainingModel.version}` else "Training") .. " · watch the loss drop in Models."
			view.progress = "Training"
			view.fraction = 0
			view.training = true
			view.app = "lab"
		else
			view.body = JOURNEY_HINT[journey.step.id] or journey.step.body
			view.progress = `Step {journey.index} of {#Journey.STEPS}`
			compact = `Step {journey.index} of {#Journey.STEPS} · {journey.step.title}`
			short = `Step {journey.index}/{#Journey.STEPS} · {journey.step.title}`
			view.fraction = (journey.index - 1) / #Journey.STEPS
		end
	elseif id == "release" then
		local ready = trainedModel(data)
		view.app = "lab"
		view.section = "release"
		view.releaseId = if ready then ready.id else nil
		view.body = if ready then `{ready.name} v{ready.version} is trained. Pick the Recommended price and launch it.` else "Train a model, then launch it with the Recommended price."
		view.progress = `Step 6 of {#Journey.STEPS}`
		compact = `Step 6 of {#Journey.STEPS} · Release your model`
		short = `Step 6/{#Journey.STEPS} · Release your model`
		view.fraction = 5 / #Journey.STEPS
	elseif id == "client" then
		local first = CompanyOps.CLIENTS[1]
		view.app = "empire"
		view.section = "clients"
		view.progress = `Trust {math.floor(have)} %`
		view.fraction = have / need
		local trip = tripFor(live, first.id)
		local best = CompanyOps.liveBest(data, first.stat)
		if trip then
			view.body = `You drive to {first.name} for the pilot visit. Signing pays {dollars(first.retainer)} at once and every day.`
			view.eta = "back in " .. Kit.countdown(math.max(0, (tonumber(trip.back) or 0) - (tonumber(e.seconds) or 0)))
		elseif best < first.minimum then
			view.body = needsText(first, best)
			if best <= 0 then
				view.app = "lab"
				view.section = "release"
			end
		else
			-- trips start 08:00-15:00 (CompanyOps.DEPART) and only while cash covers the trip + CASH_MARGIN
			local hour = CompanyOps.hour(tonumber(snapshot.serverTime) or 0)
			local _, _, cost = CompanyOps.tripPlan(first.trip, 1, false)
			local tripCash = cost + CompanyOps.CASH_MARGIN
			if hour < CompanyOps.DEPART.from or hour >= CompanyOps.DEPART.to then
				view.body = `{first.name} wants a pilot. Visits start 08:00–15:00: you drive over at 08:00.`
			elseif (tonumber(data.money) or 0) < tripCash then
				view.body = `{first.name} wants a pilot. You drive over once cash covers the trip ({dollars(tripCash)}).`
			else
				view.body = `{first.name} wants a pilot. You drive over by yourself in a moment.`
			end
		end
	elseif id == "office2" or id == "office3" or id == "office4" or id == "office5" or id == "jet" then
		view.app = "empire"
		view.section = if id == "jet" then "settings" else "office"
		view.progress, compact, short = moneyProgress(if id == "office2" then "Client ✓ · " else "", have, need)
		view.fraction = have / need
		view.eta = if have >= need then "ready" else HUD.etaText(goal.etaMinutes)
		local revenue, cost = tonumber(live.revenue) or 0, tonumber(live.cost) or 0
		local earning = revenue > 0 or (typeof(e.deals) == "table" and typeof(e.deals.accounts) == "table" and next(e.deals.accounts) ~= nil)
		if have < need and goal.etaMinutes == nil and earning and cost > revenue then
			-- a company that sells but spends more: the real lever is costs and prices, not "release a model" (and it
			-- comes before a Save-mode line that is about to switch off)
			local wages = (tonumber(ops.wagesCost) or 0) / 60
			view.body = `Costs exceed income by {dollars((cost - revenue) * CompanyOps.DAY)}/day (wages {dollars(wages * CompanyOps.DAY)}/day): raise prices, set the HR budget lower or pause HR in Settings.`
			view.warn = true
			view.section = "settings"
		elseif saving then
			view.body = "Save mode: research, Lab levels and big buys wait until the move."
		elseif have < need and goal.etaMinutes == nil then
			view.body = "No profit right now. Release models and sign clients to get there."
		elseif id == "jet" then
			view.body = `Abroad trips by jet: {CompanyOps.JET.days} days, +{math.floor(CompanyOps.JET.trust * 100)} % trust.`
		else
			local stage = math.clamp(math.floor(tonumber(e.office) or 1) + 1, 1, #EmpireConfig.OFFICES)
			local def = EmpireConfig.OFFICES[stage]
			view.body = `{def.staff} desks, {ModelMath.productSlots(stage)} product lines, {CompanyOps.STAGES[stage].clients} client slots.`
		end
	elseif id == "lines2" then
		local ready = trainedModel(data)
		view.app = "lab"
		view.section = if ready then "release" else nil
		view.releaseId = if ready then ready.id else nil
		view.progress = `{math.floor(have)} / {math.floor(need)} lines live`
		view.fraction = have / need
		local lines = ModelMath.liveLines(data)
		local free: string? = nil
		for _, def in ModelConfig.LINES do
			if not lines[def.segment] then
				free = def.label
				break
			end
		end
		view.body = `Release a model into a second line{if free then ", e.g. " .. free else ""}. A specialist owns its line.`
	elseif id == "region" then
		view.app = "empire"
		view.section = "clients"
		view.progress = "0 / 1 region clients"
		view.fraction = 0
		local hint = "Region clients need a field rep: hire Growth & Sales."
		if CompanyOps.fieldReps(e) > 0 then
			hint = "Field reps visit region clients by themselves (City Hotel night)."
			for _, c in CompanyOps.CLIENTS do
				if c.trip == "region" and c.stage <= CompanyOps.stageIndex(e) then
					local best = CompanyOps.liveBest(data, c.stat)
					local trust = if typeof(e.deals) == "table" and typeof(e.deals.trust) == "table" then tonumber(e.deals.trust[c.id]) else nil
					if best < c.minimum then
						hint = needsText(c, best)
					elseif trust then
						hint = `{c.name}: trust {math.floor(math.min(1, trust) * 100)} %. Reps keep visiting.`
						view.fraction = math.min(1, trust)
					else
						hint = `{c.name} is ready for a pilot visit by a field rep.`
					end
					break
				end
			end
		end
		view.body = hint
	elseif id == "frontier" then
		view.app = "empire"
		view.section = "research"
		view.progress = "Research"
		view.fraction = 0
		view.body = "Research Frontier Architecture to train 7B models."
	elseif id == "lines90" then
		view.app = "lab"
		view.progress = `{math.floor(have)} / {math.floor(need)} lines at 90+`
		view.fraction = have / need
		view.body = "Train stronger versions for every product line."
	elseif id == "lab" then
		view.app = "lab"
		view.progress = `Lab level {math.floor(have)} / {math.floor(need)}`
		view.fraction = have / need
		local pts, cost = CompanyOps.labCost(math.floor(have))
		view.body = `Next level: {Format.int(pts)} research points + {dollars(cost)}.`
	else
		view.progress = `{math.floor(have)} / {math.floor(need)}`
		view.fraction = have / need
	end
	if training and id ~= "train" and not saving then
		local progress = if training.workTotal > 0 then training.workDone / training.workTotal else 0
		view.body = (if trainingModel then `Training {trainingModel.name} v{trainingModel.version}` else "Training") .. ` · {math.floor(progress * 100)} %. ` .. view.body
	end
	if view.fraction then
		view.fraction = math.clamp(view.fraction :: number, 0, 1)
	end
	view.compactProgress = compact or view.progress
	view.shortProgress = short or view.compactProgress
	return view
end

-- The safety rules (CORE_SPEC 8.3) as one HUD badge: "" when nothing applies.
function HUD.safetyText(snapshot: Snapshot): string
	local data: any = snapshot.data
	local live: any = snapshot.live
	local e = data.empire
	local ops = if typeof(live.ops) == "table" then live.ops else {}
	local leave = math.max(0, math.floor(tonumber(e.unpaidLeave) or 0))
	if ops.paused == true then
		return "Cash below $0 for a day · trips paused"
	elseif leave > 0 then
		return `{leave} on unpaid leave · cash below $0`
	elseif (tonumber(data.money) or 0) < 0 then
		return "Cash below $0"
	end
	return ""
end

local function travelState(): string?
	local player = Players.LocalPlayer
	local ok, value = pcall(function(): any
		return (player :: any):GetAttribute("TravelState")
	end)
	return if ok and typeof(value) == "string" then value else nil
end

function HUD.mount(parent: Frame, devAllowed: boolean, onDev: () -> ())
	local frame = Kit.frame(parent)
	frame.Name = "HUD"
	frame.Visible = false
	root = frame

	local column = Kit.frame(frame, UDim2.fromOffset(WIDTH, 0), UDim2.new(1, -MARGIN, 0, 12))
	column.Name = "Column"
	column.AnchorPoint = Vector2.new(1, 0)
	column.AutomaticSize = Enum.AutomaticSize.Y
	local layout = Kit.list(column, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	-- phones: the column's own scale (around its top-right anchor), see COMPACT_BOOST
	local boost = Instance.new("UIScale")
	boost.Name = "CompactBoost"
	boost.Parent = column
	frame:SetAttribute("LaneWidth", WIDTH + MARGIN)

	-- Firma und Zahlen in einem Glas-Panel: Geld groß, Nutzer und Reputation als Nebenwerte
	local panel = Kit.panel(column, UDim2.new(1, 0, 0, 0))
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.LayoutOrder = 1
	Kit.padding(panel, 12, 14, 12, 12)
	Kit.list(panel, 10)

	local identity = Kit.frame(panel, UDim2.new(1, 0, 0, 40))
	identity.LayoutOrder = 1
	local logoBox = Kit.frame(identity, UDim2.fromOffset(40, 40))
	logoBox.BackgroundTransparency = 0.72
	Theme.bindAccent(logoBox, "BackgroundColor3")
	Kit.corner(logoBox, 11)
	local logo = Kit.text(logoBox, "", 22, F.regular)
	logo.AnchorPoint = Vector2.new(0.5, 0.5)
	logo.Position = UDim2.fromScale(0.5, 0.5)
	local nameLabel = Kit.text(identity, "", 17, F.bold, C.text)
	nameLabel.AutomaticSize = Enum.AutomaticSize.None
	nameLabel.Size = UDim2.new(1, -52, 0, 22)
	nameLabel.Position = UDim2.fromOffset(52, 1)
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	local rankLabel = Kit.text(identity, "", 13, F.bold, C.muted)
	rankLabel.AutomaticSize = Enum.AutomaticSize.None
	rankLabel.Size = UDim2.new(1, -52, 0, 16)
	rankLabel.Position = UDim2.fromOffset(52, 23)
	rankLabel.TextTruncate = Enum.TextTruncate.AtEnd
	Theme.bindAccent(rankLabel, "TextColor3", Theme.lighter(0.3))

	Kit.divider(panel, 2)
	local moneyRow = Kit.frame(panel, UDim2.new(1, 0, 0, 26))
	moneyRow.LayoutOrder = 3
	local moneyValue = Kit.text(moneyRow, "$0", 22, F.display, C.text)
	moneyValue.AnchorPoint = Vector2.new(0, 0.5)
	moneyValue.Position = UDim2.fromScale(0, 0.5)
	local moneySub = Kit.text(moneyRow, "", 13, F.bold, C.dim)
	moneySub.Name = "NetPerDay"
	moneySub.AnchorPoint = Vector2.new(1, 0.5)
	moneySub.Position = UDim2.fromScale(1, 0.5)
	local statsRow = Kit.frame(panel, UDim2.new(1, 0, 0, 18))
	statsRow.LayoutOrder = 4
	local usersValue = Kit.text(statsRow, "0 users", 14, F.medium, C.muted)
	local repValue = Kit.text(statsRow, "Reputation 0", 14, F.medium, C.muted)
	repValue.AnchorPoint = Vector2.new(1, 0)
	repValue.Position = UDim2.fromScale(1, 0)

	local badges = Kit.frame(column, UDim2.new(1, 0, 0, 0))
	badges.AutomaticSize = Enum.AutomaticSize.Y
	badges.LayoutOrder = 2
	local badgeLayout = Kit.list(badges, 6, true)
	badgeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	local travelBadge = Kit.tag(badges, "Abroad · Port Meridian", C.muted, 1)
	travelBadge.Name = "TravelBadge"
	travelBadge.Visible = false
	local saveBadge = Kit.tag(badges, "Saving off (Studio test)", C.warn, 2)
	saveBadge.Visible = false
	local safetyBadge = Kit.tag(badges, "", C.bad, 0)
	safetyBadge.Name = "Safety"
	safetyBadge.Visible = false

	-- Next goal: one goal with progress and ETA; a tap opens the matching app
	local step = Instance.new("TextButton")
	step.Name = "NextGoal"
	step.AutoButtonColor = false
	step.Text = ""
	step.BorderSizePixel = 0
	step.Size = UDim2.new(1, 0, 0, 0)
	step.AutomaticSize = Enum.AutomaticSize.Y
	step.LayoutOrder = 3
	step.BackgroundColor3 = C.panel
	step.BackgroundTransparency = 0.02
	step.Selectable = true
	step.Parent = column
	Kit.corner(step, 14)
	local stepStroke = Kit.stroke(step, 0.87)
	stepStroke.Color = C.line
	local stepPadding = Kit.padding(step, 12, 14, 13, 14)
	Kit.list(step, 5)
	local captionRow = Kit.frame(step, UDim2.new(1, 0, 0, 16))
	captionRow.LayoutOrder = 1
	local stepCaption = Kit.text(captionRow, "Next goal", 13, F.medium, C.muted)
	stepCaption.Name = "Caption"
	stepCaption.AnchorPoint = Vector2.new(0, 0.5)
	stepCaption.Position = UDim2.fromScale(0, 0.5)
	Theme.bindAccent(stepCaption, "TextColor3")
	local saveTag = Kit.tag(captionRow, "Save mode", C.warn)
	saveTag.Name = "SaveMode"
	saveTag.AnchorPoint = Vector2.new(1, 0.5)
	saveTag.Position = UDim2.fromScale(1, 0.5)
	saveTag.Visible = false
	local stepTitle = Kit.para(step, "", 17, C.text, 2)
	stepTitle.Name = "Title"
	stepTitle.Font = F.bold
	local stepBody = Kit.para(step, "", 14, C.muted, 3)
	stepBody.Name = "Hint"
	local stepBar = Kit.bar(step, 6, 4)
	stepBar.frame.Name = "Progress"
	local progressRow = Kit.frame(step, UDim2.new(1, 0, 0, 16))
	progressRow.Name = "ProgressRow"
	progressRow.LayoutOrder = 5
	local progressText = Kit.text(progressRow, "", 13, F.medium, C.muted)
	progressText.Name = "Have"
	progressText.AutomaticSize = Enum.AutomaticSize.None
	progressText.Size = UDim2.new(1, -60, 1, 0)
	progressText.TextTruncate = Enum.TextTruncate.AtEnd
	local etaText = Kit.text(progressRow, "", 13, F.bold, C.text)
	etaText.Name = "Eta"
	etaText.AnchorPoint = Vector2.new(1, 0)
	etaText.Position = UDim2.fromScale(1, 0)
	etaText.TextXAlignment = Enum.TextXAlignment.Right
	Theme.bindAccent(etaText, "TextColor3", Theme.lighter(0.25))
	local current: GoalView? = nil
	Kit.onClick(step, function()
		local target = current
		if not target then
			return
		end
		Computer.open(target.app, target.section)
		local releaseId = target.releaseId
		if releaseId then
			LabApp.openRelease(releaseId)
		end
	end)

	-- milestone rewards are claimed by hand (EmpireAction ClaimQuest in Company → Goals): a small nudge. On phones it
	-- sits beside "Open company" in one row of touch-sized buttons (the column must stay clear of the phone button).
	local buttonRow = Kit.frame(column, UDim2.new(1, 0, 0, 0))
	buttonRow.Name = "Buttons"
	buttonRow.AutomaticSize = Enum.AutomaticSize.Y
	buttonRow.LayoutOrder = 4
	local buttonLayout = Kit.list(buttonRow, 8)
	local reward = Kit.button(buttonRow, "Milestone reward ready · Collect", "secondary", UDim2.new(1, 0, 0, 34))
	reward.Name = "RewardReady"
	reward.LayoutOrder = 1
	reward.TextSize = 14
	reward.TextWrapped = true
	reward.Visible = false
	Kit.onClick(reward, function()
		Computer.open("empire", "milestones")
	end)

	-- Computer-Button, für Tastatur mit Tastenkappe "C"
	local computerButton = Kit.button(buttonRow, "Open company", "primary", UDim2.new(1, 0, 0, 50))
	computerButton.Name = "OpenCompany"
	computerButton.LayoutOrder = 2
	computerButton.TextSize = 17
	Kit.onClick(computerButton, Computer.toggle)
	if UserInputService.KeyboardEnabled then
		local keycap = Kit.frame(computerButton, UDim2.fromOffset(26, 24), UDim2.new(1, -12, 0.5, 0))
		keycap.AnchorPoint = Vector2.new(1, 0.5)
		keycap.BackgroundTransparency = 0.82
		keycap.BackgroundColor3 = C.bg
		Kit.corner(keycap, 6)
		local key = Kit.text(keycap, "C", 13, F.bold, C.bg)
		key.AnchorPoint = Vector2.new(0.5, 0.5)
		key.Position = UDim2.fromScale(0.5, 0.5)
	end
	if devAllowed then
		local dev = Kit.button(column, "DEV TOOLS", "ghost", UDim2.fromOffset(110, 30))
		dev.LayoutOrder = 6
		dev.TextSize = 12
		Kit.onClick(dev, onDev)
	end

	-- Phones: the whole HUD layer is scaled down a lot (UIRoot), so the column gets its own UIScale (COMPACT_BOOST),
	-- the goal card drops its hint line (the step name moves into the progress text) and the buttons become touch
	-- sized. Read the scale of the HUD layer (sibling UIScale of this frame's parent).
	local compact = false
	local function layoutButtons()
		local touch = compact and Kit.isTouch()
		local h = if touch then TOUCH_BUTTON elseif compact then 56 else 50
		if compact then
			-- one row: [Collect reward | Open company]
			buttonLayout.FillDirection = Enum.FillDirection.Horizontal
			reward.Text = "Collect reward"
			reward.Size = UDim2.new(0.42, -4, 0, h)
			computerButton.Size = if reward.Visible then UDim2.new(0.58, -4, 0, h) else UDim2.new(1, 0, 0, h)
		else
			buttonLayout.FillDirection = Enum.FillDirection.Vertical
			reward.Text = "Milestone reward ready · Collect"
			reward.Size = UDim2.new(1, 0, 0, 34)
			computerButton.Size = UDim2.new(1, 0, 0, h)
		end
		computerButton.TextSize = if compact then 18 else 17
		reward.TextSize = if compact then 16 else 14
	end
	local function applyCompact()
		local scale = parent:FindFirstChildOfClass("UIScale")
		compact = scale ~= nil and scale.Scale < COMPACT_SCALE
		boost.Scale = if compact then COMPACT_BOOST else 1
		frame:SetAttribute("LaneWidth", WIDTH * boost.Scale + MARGIN)
		frame:SetAttribute("Compact", compact)
		stepTitle.TextSize = if compact then 20 else 17
		stepCaption.TextSize = if compact then 15 else 13
		progressText.TextSize = if compact then 17 else 13
		etaText.TextSize = if compact then 17 else 13
		progressRow.Size = UDim2.new(1, 0, 0, if compact then 20 else 16)
		captionRow.Size = UDim2.new(1, 0, 0, if compact then 18 else 16)
		usersValue.TextSize = if compact then 16 else 14
		repValue.TextSize = if compact then 16 else 14
		statsRow.Size = UDim2.new(1, 0, 0, if compact then 20 else 18)
		moneySub.TextSize = if compact then 15 else 13
		rankLabel.TextSize = if compact then 14 else 13
		stepPadding.PaddingTop = UDim.new(0, if compact then 9 else 12)
		stepPadding.PaddingBottom = UDim.new(0, if compact then 10 else 13)
		stepBody.Visible = not compact and stepBody.Text ~= ""
		layoutButtons()
	end
	local layerScale = parent:FindFirstChildOfClass("UIScale")
	if layerScale then
		layerScale:GetPropertyChangedSignal("Scale"):Connect(applyCompact)
	end
	applyCompact()

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not frame.Visible then
			return
		end
		if input.KeyCode == Enum.KeyCode.C then
			Computer.toggle()
		end
	end)

	StateController.onChange(function(snapshot: Snapshot)
		local data = snapshot.data
		local info = data.company
		frame.Visible = info ~= nil and frame:GetAttribute("Hidden") ~= true
		if not info then
			return
		end
		logo.Text = info.logo
		nameLabel.Text = info.name
		local stage = EmpireConfig.OFFICES[math.clamp(math.floor(tonumber(data.empire.office) or 1), 1, #EmpireConfig.OFFICES)]
		rankLabel.Text = CompanyConfig.rankFor(data.stats.peakUsers) .. "  ·  " .. (string.gsub(stage.name, "Headquarters", "HQ"))
		repValue.Text = `Reputation {string.format("%.0f", info.reputation)}`
		saveBadge.Visible = not snapshot.saveEnabled
		local travel = travelState()
		travelBadge.Visible = travel ~= nil
		travelBadge.Text = if travel == "flying" then "IN THE AIR" elseif travel == "abroad" then "ABROAD · PORT MERIDIAN" else ""
		local safety = HUD.safetyText(snapshot)
		safetyBadge.Text = string.upper(safety)
		safetyBadge.Visible = safety ~= ""
		badges.Visible = travelBadge.Visible or saveBadge.Visible or safetyBadge.Visible
		local claimable = false
		for _, quest in EmpireConfig.QUESTS do
			if not data.empire.quests[quest.id] and EmpireMath.progress(data, quest) >= quest.target then
				claimable = true
				break
			end
		end
		if reward.Visible ~= claimable then
			reward.Visible = claimable
			layoutButtons()
		end

		-- money per game day (CORE_SPEC 6: the UI shows running money per game day)
		local live = snapshot.live
		local net = live.revenue - live.cost
		if live.revenue > 0 or live.cost > 0 then
			moneySub.Text = Format.perDay(net)
			moneySub.TextColor3 = if net >= 0 then C.good else C.bad
		else
			moneySub.Text = "no income yet"
			moneySub.TextColor3 = C.dim
		end

		local view = HUD.describe(snapshot, StateController.ui)
		current = view
		stepCaption.Text = view.caption
		stepCaption.TextColor3 = if view.warn then C.warn else Theme.accent
		saveTag.Visible = view.saving
		stepTitle.Text = view.title
		stepBody.Text = view.body
		stepBody.Visible = not compact and view.body ~= ""
		stepBar.frame.Visible = view.fraction ~= nil
		if view.fraction and not view.training then
			stepBar.set(view.fraction :: number)
		end
		progressRow.Visible = view.progress ~= "" or view.eta ~= ""
		etaText.Text = view.eta
		-- the progress text takes what the ETA leaves: the first form that fits (desktop text, phone text, shortest)
		local etaWidth = if view.eta == "" then 0 else math.ceil(textWidth(view.eta, etaText.TextSize)) + 10
		progressText.Size = UDim2.new(1, -etaWidth, 1, 0)
		local room = WIDTH - stepPadding.PaddingLeft.Offset - stepPadding.PaddingRight.Offset - etaWidth
		local choice = view.shortProgress
		local candidates: { string } = if compact then { view.compactProgress } else { view.progress, view.compactProgress }
		for _, candidate in candidates do
			if textWidth(candidate, progressText.TextSize) <= room then
				choice = candidate
				break
			end
		end
		progressText.Text = choice
		stepStroke.Color = if view.warn then C.warn else C.line
		stepStroke.Transparency = if view.warn then 0.45 else 0.87
	end)

	-- Zahlen gleiten zum Zielwert (Geld läuft zwischen den Snapshots weiter)
	local shownMoney, shownUsers = 0, 0
	RunService.RenderStepped:Connect(function(dt: number)
		local snapshot = StateController.snapshot
		column.Visible = not Computer.isOpen() -- im Computer stehen dieselben Zahlen in der Kopfzeile
		if not snapshot or not frame.Visible then
			return
		end
		local alpha = math.min(1, dt * 8)
		local money = StateController.money()
		shownMoney = if math.abs(money - shownMoney) > 1e8 then money else shownMoney + (money - shownMoney) * alpha
		moneyValue.Text = Format.money(shownMoney)
		moneyValue.TextColor3 = if shownMoney < 0 then C.bad else C.text
		local users = snapshot.live.users
		shownUsers = if math.abs(users - shownUsers) > 1e7 then users else shownUsers + (users - shownUsers) * alpha
		usersValue.Text = `{Format.compact(shownUsers)} users`
		local view = current
		if view and view.training and stepBar.frame.Visible then
			local done, total = StateController.trainingWork()
			local fraction = if total > 0 then done / total else 0
			stepBar.set(fraction)
			progressText.Text = string.format("Training %d %%", math.floor(fraction * 100))
			local eta = StateController.trainingEta()
			etaText.Text = if eta > 0 and eta < math.huge then Kit.countdown(eta) .. " left" else ""
		end
	end)

	-- Benachrichtigungen vom Server
	StateController.onNotify(function(kind: string, payload: { [string]: any })
		if kind == "TRAINING_EVENT" then
			if Computer.isOpen() then
				return -- das Lab zeigt die Entscheidung ohnehin groß an
			end
			local def = if typeof(payload.eventId) == "string" then ModelConfig.getEvent(payload.eventId) else nil
			Toast.show("warn", `Training paused: {if def then def.title else "decision needed"}. Open the Lab to decide.`, 5)
		elseif kind == "TRAINING_COMPLETE" then
			local overall = if typeof(payload.overall) == "number" then payload.overall else 0
			if not Computer.isOpen() then -- bei offenem Computer erscheint das Ergebnis direkt im Lab
				Toast.show("success", `Training complete! Overall {string.format("%.1f", overall)}. Open your computer to see it.`, 5)
			end
		elseif kind == "MODEL_LIVE" then
			if not Computer.isOpen() then
				Toast.show("success", "Your model is live. Users are coming in!")
			end
		elseif kind == "RANK_UP" then
			local rank = if typeof(payload.rank) == "string" then payload.rank else "new rank"
			Toast.show("success", `Rank up! Your company is now a {rank}.`, 6)
		end
	end)
end

-- Während des Intros ausblenden
function HUD.setHidden(hidden: boolean)
	local frame = root
	if not frame then
		return
	end
	frame:SetAttribute("Hidden", hidden)
	local snapshot = StateController.snapshot
	frame.Visible = not hidden and snapshot ~= nil and snapshot.data.company ~= nil
end

return HUD
