--!strict
-- The wording of the "Next goal" (CORE_SPEC 8.2): EmpireMath.nextGoal(data, live) gives the goal, its progress
-- (have / need) and the ETA; this module words it and adds the concrete hint from real state (client trip, Save
-- mode, research, Lab level). Pure (snapshot in, view out). Moved out of Screens/HUD by the menu package so the
-- Menu's Home cards (Apps/HomeApp, ONBOARDING_SPEC B4) use the same title and progress text as the HUD card;
-- HUD.describe / HUD.etaText / HUD.safetyText / HUD.textWidth stay as aliases.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local EmpireConfig = require(Shared.Config.EmpireConfig)
local ModelConfig = require(Shared.Config.ModelConfig)
local EmpireMath = require(Shared.EmpireMath)
local CompanyOps = require(Shared.CompanyOps)
local ModelMath = require(Shared.ModelMath)
local Format = require(Shared.Format)
local Types = require(Shared.Types)

local UI = script.Parent
local Kit = require(UI.Kit)
local LabApp = require(UI.Apps.LabApp)

local GoalText = {}
local HUD = GoalText -- the moved code below still says HUD.*

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
	revealId: string?, -- LAB_SPEC 4.14: the trained model whose reveal has not played yet
}

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
	design = "Open the Model Studio: everything is prefilled, just press START.",
	train = "Start the training run in the Lab and watch the loss drop.",
	evaluation = "Evaluate it in the Lab, then release it.",
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
		training = false, warn = false, saving = saving, app = "empire", section = nil, releaseId = nil, revealId = nil,
	}
	local training = data.training
	local trainingModel: ModelData? = if training then data.models[training.modelId] else nil
	if training and training.event and training.event.pending then
		view.id = "decision"
		view.caption = "Decision needed"
		view.title = "Your training run needs a decision"
		view.body = "Open the Lab and choose what to do. Otherwise the default is picked automatically."
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
		-- menu package (ONBOARDING_SPEC 0.2 #3, lab request #2): a fresh save opens the Model Studio design view, whose
		-- first-model Review offers BUY DATA PLAN · START (no detour through Datasets, no "Step 1 of 7")
		view.app = "lab"
		view.section = "design"
		if training then
			view.section = "train"
			view.body = (if trainingModel then `Training {trainingModel.name} v{trainingModel.version}` else "Training") .. " · watch the loss drop in the Lab."
			view.progress = "Training"
			view.fraction = 0
			view.training = true
		else
			view.body = JOURNEY_HINT.design
			view.progress = "Open the Lab"
		end
	elseif id == "release" then
		local ready = trainedModel(data)
		view.app = "lab"
		view.section = "release"
		view.releaseId = if ready then ready.id else nil
		-- LAB_SPEC 4.14: a model the player has not seen yet keeps its score a surprise (openRelease plays the reveal)
		view.revealId = if ready and not LabApp.wasRevealed(ready.id) then ready.id else nil
		view.body = if ready and view.revealId then `{ready.name} v{ready.version} is ready · tap to reveal its score`
			elseif ready then `{ready.name} v{ready.version} is trained. Pick the Recommended price and launch it.`
			else "Train a model, then launch it with the Recommended price."
		view.progress = "Ready to launch"
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


return GoalText
