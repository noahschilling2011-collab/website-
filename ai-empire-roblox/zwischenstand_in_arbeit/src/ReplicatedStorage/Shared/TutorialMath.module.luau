--!strict
-- "First steps" guide (ONBOARDING_SPEC A): pure logic, shared by the server (EmpireAction "tutorial" checks,
-- Template.cleanTutorial) and the client (GuideController, HUD guide card, Menu Home card, unlock waves).
-- Progress comes from game state (A5): the save only keeps flags and the highest step reached
-- (empire.tutorial = {v, step, done, skipped, tipsOff, seen, tips}). No money, items or unlocks depend on it.
--   TutorialMath.step(data, live, ui) -> View?   the card / ring / dim / chip of the current step (nil = guide off)
--   TutorialMath.unlockedKeys(data)              Menu pages open by state (unlock waves, B5)
--   TutorialMath.assistantName(userId)           first name of AssistantService.identity(userId) (same formula)
local Config = require(script.Parent.Config.EmpireConfig)
local ModelConfig = require(script.Parent.Config.ModelConfig)
local HardwareConfig = require(script.Parent.Config.HardwareConfig)
local EmployeeConfig = require(script.Parent.Config.EmployeeConfig)
local ModelMath = require(script.Parent.ModelMath)
local CampusMath = require(script.Parent.CampusMath)
local EmpireMath = require(script.Parent.EmpireMath)
local Format = require(script.Parent.Format)

local TutorialMath = {}

TutorialMath.STEPS = 5
TutorialMath.GREETING_SECONDS = 8 -- the greeting line shows this long or until the first input (A3)
TutorialMath.DONE_AFTER_INCOME = 120 -- GOT IT fires by itself this long after the first income (A3)
TutorialMath.DECIDE_RING_DELAY = 6 -- the server auto-picks after 25 s (LAB_SPEC 2.5)
TutorialMath.REVEAL_RING_DELAY = 0.18 + 0.2 + 1.15 + 8 * 0.12 + 3 -- reveal sequence (Stages) + 3 s
TutorialMath.NAME_MAX = 12 -- {Name} is left out when the display name is longer

-- Menu page keys that get a NEW badge until opened once (B5). Unknown keys are dropped by the cleaner.
TutorialMath.SEEN_KEYS = {
	"home.money", "home.goals", "lab.data", "lab.gpus", "lab.research", "lab.arena", "market", "market.projects",
	"clients", "clients.receipts", "team", "team.fleet", "team.campus", "team.settings",
}
-- one-time tips (A12); "shop" is never a tip
TutorialMath.TIP_KEYS = { "team", "phone", "clients", "gpus", "successor", "design_steps" }

-- every Menu page key with the wave that opens it (B5): 0 company, 1 first trained model, 2 first launch,
-- 3 first signed client; "research" = wave 2 or (before a launch) a first hire / 50 research points
local PAGES: { { key: string, wave: number | string } } = {
	{ key = "home", wave = 0 }, { key = "home.today", wave = 0 }, { key = "home.goals", wave = 0 },
	{ key = "home.money", wave = 2 },
	{ key = "lab", wave = 0 }, { key = "lab.models", wave = 0 }, { key = "lab.data", wave = 0 }, { key = "lab.gpus", wave = 0 },
	{ key = "lab.research", wave = "research" }, { key = "lab.arena", wave = 1 },
	{ key = "market", wave = 2 }, { key = "market.myais", wave = 2 }, { key = "market.lines", wave = 2 },
	{ key = "market.projects", wave = 1 }, { key = "market.leaderboard", wave = 2 },
	{ key = "clients", wave = 2 }, { key = "clients.clients", wave = 2 }, { key = "clients.receipts", wave = 3 },
	{ key = "team", wave = 2 }, { key = "team.staff", wave = 2 }, { key = "team.office", wave = 2 }, { key = "team.fleet", wave = 2 },
	{ key = "team.campus", wave = 2 }, { key = "team.settings", wave = 2 },
	{ key = "shop", wave = 2 },
}
TutorialMath.PAGES = PAGES

-- English card texts (A3). {A} assistant, {Name} display name, {Model} "Nova v1", {eta} "1 min 12 s".
TutorialMath.TEXTS = {
	openLab = "Open your AI lab",
	greet = "Hi {Name}! Let's build your first AI.",
	greetNoName = "Hi! Let's build your first AI.",
	touch = "Tap OPEN LAB or walk to the glowing computer.",
	pc = "Click OPEN LAB or press C.",
	-- fix round 1 (review): in steps 1-2 L1 alone opens the lab (the guide's open filter); a following (A) would press
	-- the Studio's selected BUY DATA PLAN straight away, so step 1 never asks for (A)
	pad = "Press L1 or walk to the glowing computer.",
	menuLab = "I picked a good first model for you.",
	buyDataTitle = "Get training data",
	buyData = "I picked a good first model. It needs data.",
	startTitle = "Start training",
	start = "Data is in. Now press START.",
	cashClaim = "Not enough cash. Collect your rewards first.",
	cashDaily = "Not enough cash. Claim today's grant on Home.",
	cashData = "The plan costs too much. Datasets has free data.",
	cashSell = "Not enough cash. Sell a GPU in Lab → GPUs for half back.",
	cashWait = "Not enough cash. Your next daily grant comes at 00:00 UTC.",
	waitTitle = "Your AI is training",
	wait = "About {eta} left. You can close the lab.",
	paused = "Training is paused.",
	decideTitle = "Quick choice needed",
	decide = "Pick one in the lab. If you wait, it picks for you.",
	launchTitle = "Launch your AI",
	launch = "{Model} is ready! Let's see how it did.",
	liveTitle = "Your AI is live",
	live = "Users are trying {Model} now.",
	incomeTitle = "First income!",
	income = "People pay to use {Model}. Well done!",
	complete = "GUIDE COMPLETE ✓",
}
TutorialMath.ACTIONS = {
	openLab = "OPEN LAB ›",
	watch = "WATCH ›",
	decide = "DECIDE ›",
	seeAi = "SEE YOUR AI ›",
	gotIt = "GOT IT",
}
TutorialMath.CHIPS = { openLab = "to open the lab", decide = "to decide", seeAi = "to see it" }

export type InputKind = "touch" | "pc" | "pad"
export type Ui = {
	computerOpen: boolean?,
	studioOpen: boolean?,
	studioMode: string?, -- Studio.mode: closed | design | training | reveal | launch | live
	revealed: ((id: string) -> boolean)?,
	inputKind: InputKind?,
	greetingOver: boolean?,
	displayName: string?,
	assistant: string?, -- {A}
	trainingEta: number?, -- seconds (StateController.trainingEta)
	trainingFrac: number?, -- 0..1
	studioPrimary: string?, -- "needCash" | "needData" | nil: what the Studio's Primary button says (cash edge)
	serverTime: number?,
	menuHome: boolean?, -- the Menu shows Home (Home card text, B4)
}
export type Action = { label: string, route: string, modelId: string?, style: string? }
export type View = {
	step: number, -- 1..5
	sub: string,
	title: string,
	speaker: string, -- "{A}"
	text: string, -- the line after "{A}: "
	line: string, -- speaker .. ": " .. text
	action: Action?,
	collect: number?,
	target: string?, -- "guide_action" | "menu_lab" | "Primary" | "Decision" | "Launch" | "LaunchButton"
	dim: boolean,
	delay: number,
	chip: string?,
	frac: number,
	card: boolean, -- the HUD / Home card shows (false while the Studio runs a ceremony step: 4 reveal / launch)
}

local function finite(v: any): boolean
	return typeof(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function tutorialOf(data: any): any
	local e = if typeof(data) == "table" then data.empire else nil
	local t = if typeof(e) == "table" then e.tutorial else nil
	return if typeof(t) == "table" then t else nil
end

-- company exists and the guide was neither finished nor skipped
function TutorialMath.active(data: any): boolean
	if typeof(data) ~= "table" or data.company == nil then
		return false
	end
	local t = tutorialOf(data)
	if t == nil then
		return true
	end
	return t.done ~= true and t.skipped ~= true
end

local function stat(data: any, key: string): number
	local stats = if typeof(data) == "table" then data.stats else nil
	local v = if typeof(stats) == "table" then stats[key] else nil
	return if finite(v) then v else 0
end

local function trainedModel(data: any): any
	if typeof(data.modelOrder) ~= "table" or typeof(data.models) ~= "table" then
		return nil
	end
	for _, id in data.modelOrder do
		local m = data.models[id]
		if typeof(m) == "table" and m.status == "trained" then
			return m
		end
	end
	return nil
end

local function latestModel(data: any): any
	if typeof(data.modelOrder) ~= "table" or typeof(data.models) ~= "table" then
		return nil
	end
	local best = nil
	for _, id in data.modelOrder do
		local m = data.models[id]
		if typeof(m) == "table" and (m.status == "live" or m.status == "retired" or m.status == "trained") then
			best = m
			if m.status == "live" then
				return m
			end
		end
	end
	return best
end

-- highest step the state proves: 5 released, 4 trained, 3 training, else 1 (server check for op "step")
function TutorialMath.reachable(data: any): number
	if stat(data, "modelsReleased") >= 1 then
		return 5
	end
	if stat(data, "modelsTrained") >= 1 or trainedModel(data) ~= nil then
		return 4
	end
	if data.training ~= nil then
		return 3
	end
	return 1
end

-- sum of the rewards of every finished, not yet collected goal (the HUD's claim test); 0 when none
function TutorialMath.claimable(data: any): (number, number)
	local e = data.empire
	local quests = if typeof(e) == "table" and typeof(e.quests) == "table" then e.quests else {}
	local total, count = 0, 0
	for _, quest in Config.QUESTS do
		if not quests[quest.id] and EmpireMath.progress(data, quest) >= quest.target then
			total += quest.reward
			count += 1
		end
	end
	return total, count
end

-- the first name of AssistantService.identity(userId) (same formula, AssistantService is server-only)
function TutorialMath.assistantName(userId: number): string
	local owner = if finite(userId) then userId else 0
	local seed = EmployeeConfig.hash((math.floor(math.abs(owner)) * 13 + 4242) % 4294967296) % 2147483647
	local full = CampusMath.nameForSeed(seed, true)
	return string.match(full, "^(%S+)") or full
end

-- "1 min 12 s", "40 s" (the client's Kit.countdown format below 10 minutes)
local function countdown(seconds: number): string
	local s = math.max(0, math.floor((if seconds == seconds then seconds else 0) + 0.5))
	if s < 60 then
		return tostring(s) .. " s"
	end
	if s < 600 then
		local m, r = s // 60, s % 60
		return if r == 0 then tostring(m) .. " min" else string.format("%d min %d s", m, r)
	end
	return "~" .. tostring(math.floor(s / 60 + 0.5)) .. " min"
end
TutorialMath.countdown = countdown

local function fill(text: string, values: { [string]: string }): string
	return (string.gsub(text, "{(%a+)}", function(key: string): string
		return values[key] or ("{" .. key .. "}")
	end))
end

local function inputWord(kind: InputKind?): string
	if kind == "pad" then
		return "Press L1, then (A),"
	elseif kind == "pc" then
		return "Click"
	end
	return "Tap"
end

local function ownsSellableGpu(data: any): boolean
	if typeof(data.gpus) ~= "table" then
		return false
	end
	for id, count in data.gpus do
		local def = if typeof(id) == "string" then HardwareConfig.getGPU(id) else nil
		if def and def.starter ~= true and finite(count) and count > 0 then
			return true
		end
	end
	return false
end

local function dailyOpen(data: any, now: number?): boolean
	local e = data.empire
	local daily = if typeof(e) == "table" then e.daily else nil
	local day = if typeof(daily) == "table" and finite(daily.day) then daily.day else -1
	local t = if finite(now) then now :: number else os.time()
	return day < math.floor(t / 86400)
end

-- The guide's current step (A5, first match wins).
function TutorialMath.step(data: any, live: any, ui: Ui?): View?
	if not TutorialMath.active(data) then
		return nil
	end
	local u: Ui = ui or {}
	local t = tutorialOf(data) or {}
	local saved = if finite(t.step) then t.step else 0
	local mode = u.studioMode or "closed"
	local studio = u.studioOpen == true and mode ~= "closed"
	local computer = u.computerOpen == true
	local A = u.assistant or "Ada"
	local T = TutorialMath.TEXTS
	local collect = TutorialMath.claimable(data)
	local view: View = {
		step = 1, sub = "openLab", title = T.openLab, speaker = A, text = "", line = "", action = nil,
		collect = if collect > 0 then collect else nil, target = nil, dim = false, delay = 0, chip = nil, frac = 0.35, card = true,
	}
	local function say(text: string, values: { [string]: string }?)
		view.text = fill(text, values or {})
		view.line = A .. ": " .. view.text
	end
	local function chip(key: string)
		if not computer then
			-- step 1 on a gamepad: L1 alone opens the lab (no "then (A)", see TEXTS.pad)
			local word = if key == "openLab" and u.inputKind == "pad" then "Press L1" else inputWord(u.inputKind)
			view.chip = word .. " " .. TutorialMath.CHIPS[key]
		end
	end
	local function modelName(m: any): string
		if typeof(m) ~= "table" then
			return "your AI"
		end
		return tostring(m.name) .. " v" .. tostring(m.version or 1)
	end

	if stat(data, "modelsReleased") >= 1 then
		-- 5: the first AI is live; income shows once revenue flows
		local m = latestModel(data)
		local revenue = if typeof(live) == "table" and finite(live.revenue) then live.revenue else 0
		view.step = 5
		view.frac = 1
		view.action = { label = TutorialMath.ACTIONS.gotIt, route = "done" }
		if revenue > 0 or stat(data, "totalRevenue") > 0 then
			view.sub = "income"
			view.title = T.incomeTitle
			say(T.income, { Model = modelName(m) })
		else
			view.sub = "waitIncome"
			view.title = T.liveTitle
			say(T.live, { Model = modelName(m) })
		end
		return view
	end

	local trained = trainedModel(data)
	if trained then
		view.step = 4
		view.title = T.launchTitle
		say(T.launch, { Model = modelName(trained) })
		if studio and mode == "reveal" then
			view.sub = "reveal"
			view.card = false
			view.target = "Launch"
			view.delay = TutorialMath.REVEAL_RING_DELAY
		elseif studio and mode == "launch" then
			view.sub = "launch"
			view.card = false
			view.target = "LaunchButton"
			view.dim = true
		else
			view.sub = "open"
			view.action = { label = TutorialMath.ACTIONS.seeAi, route = "lab_release", modelId = trained.id }
			view.target = if computer then "menu_lab" else "guide_action"
			chip("seeAi")
		end
		return view
	end

	local training = data.training
	if training ~= nil then
		view.step = 3
		local event = if typeof(training) == "table" then training.event else nil
		if typeof(event) == "table" and event.pending then
			view.sub = "decide"
			view.title = T.decideTitle
			say(T.decide)
			view.collect = nil -- one urgent button
			view.action = { label = TutorialMath.ACTIONS.decide, route = "lab_train", style = "warn" }
			view.delay = TutorialMath.DECIDE_RING_DELAY
			if studio then
				view.target = "Decision"
			else
				view.target = if computer then "menu_lab" else "guide_action"
				chip("decide")
			end
		else
			view.sub = "wait"
			view.title = T.waitTitle
			local eta = u.trainingEta
			if finite(eta) and (eta :: number) > 0 then
				say(T.wait, { eta = countdown(eta :: number) })
			else
				say(T.paused)
			end
			view.action = { label = TutorialMath.ACTIONS.watch, route = "lab_train", style = "secondary" }
			local frac = u.trainingFrac
			if not finite(frac) and typeof(training) == "table" and finite(training.workTotal) and training.workTotal > 0 then
				frac = (tonumber(training.workDone) or 0) / training.workTotal
			end
			view.frac = if finite(frac) then math.clamp(frac :: number, 0, 1) else 0
		end
		return view
	end

	if (studio and mode == "design") or saved >= 2 then
		view.step = 2
		local stock = ModelMath.dataSummary(if typeof(data.data) == "table" then data.data else {})
		local hasData = stock.total >= ModelConfig.TRAINING.minTokens
		view.sub = if hasData then "start" else "buyData"
		view.title = if hasData then T.startTitle else T.buyDataTitle
		say(if hasData then T.start else T.buyData)
		view.action = { label = TutorialMath.ACTIONS.openLab, route = "lab_design" }
		local edge = u.studioPrimary
		if edge == "needCash" or edge == "needData" then
			view.sub = "cash"
			if collect > 0 then
				say(T.cashClaim)
			elseif dailyOpen(data, u.serverTime) then
				say(T.cashDaily)
			elseif edge == "needData" then
				say(T.cashData)
			elseif ownsSellableGpu(data) then
				say(T.cashSell)
			else
				say(T.cashWait)
			end
		end
		if studio and mode == "design" then
			view.target = "Primary"
			view.dim = view.sub ~= "cash"
		else
			view.target = if computer then "menu_lab" else "guide_action"
		end
		return view
	end

	-- 1: open the lab
	view.step = 1
	view.sub = "openLab"
	view.action = { label = TutorialMath.ACTIONS.openLab, route = "lab_design" }
	if computer or u.menuHome then
		say(T.menuLab)
	elseif not u.greetingOver then
		local name = u.displayName
		if typeof(name) == "string" and name ~= "" and (utf8.len(name) or #name) <= TutorialMath.NAME_MAX then
			say(T.greet, { Name = name })
		else
			say(T.greetNoName)
		end
	else
		local kind = u.inputKind
		say(if kind == "pad" then T.pad elseif kind == "pc" then T.pc else T.touch)
	end
	view.target = if computer then "menu_lab" else "guide_action"
	view.dim = true
	chip("openLab")
	return view
end

-- Menu page keys open by state (unlock waves, B5)
function TutorialMath.unlockedKeys(data: any): { string }
	local e = if typeof(data) == "table" and typeof(data.empire) == "table" then data.empire else {}
	local trained = stat(data, "modelsTrained") >= 1
	local released = stat(data, "modelsReleased") >= 1
	local staff = 0
	if typeof(e.employees) == "table" then
		for _, n in e.employees do
			if finite(n) then
				staff += n
			end
		end
	end
	local points = if finite(e.points) then e.points else 0
	local signed = (if finite(e.contractsCompleted) then e.contractsCompleted else 0) >= 1
	local out = {}
	for _, page in PAGES do
		local w = page.wave
		local open = if w == 0 then true
			elseif w == 1 then trained or released
			elseif w == 2 then released
			elseif w == 3 then signed
			else released or staff >= 1 or points >= 50
		if open then
			table.insert(out, page.key)
		end
	end
	return out
end

function TutorialMath.isUnlocked(data: any, key: string): boolean
	return table.find(TutorialMath.unlockedKeys(data), key) ~= nil
end

-- "+$X from N goals" (HUD / Home toast after Collect all)
function TutorialMath.collectText(total: number, count: number): string
	return "+$" .. Format.int(total) .. " from " .. tostring(count) .. (if count == 1 then " goal" else " goals")
end

return TutorialMath
