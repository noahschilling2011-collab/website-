--!nocheck
-- menu package (ONBOARDING_SPEC A + B5), server + pure logic on the real modules in the mock:
--   T1  TutorialMath.step for every guide state (texts, targets, dim, chip, collect, cash edge lines)
--   T2  Template.cleanTutorial (idempotent, junk repaired, unknown keys dropped, old saves) + DATA_VERSION 6
--   T3  EmpireAction {action = "tutorial"}: each op's rule, negatives, no op changes money; funnel steps
--   T4  ClaimQuest {all = true}: each quest once, second call claims nothing, total, single-id path unchanged
--   T5  TutorialMath.assistantName == first name of AssistantService.identity for 20 ids (1 and -1 -> "Ada")
--   T10 TutorialMath.unlockedKeys for the unlock waves
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_menu && cd tests/menu && ../../tools/luau test_server.luau -a .gen_menu
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_menu")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local C = require("../econ/common")
local check = C.check

local function body()
	local R = C.load(M)
	local game = M.game
	local RS, S = R.RS, R.Server.Services
	local TM = M.require(RS.Shared.TutorialMath)
	local EmpireMath, EmpireConfig, GameConfig, Template = R.EmpireMath, R.EmpireConfig, R.GameConfig, R.Template
	local Funnel = M.require(R.Server.Lib.Funnel)
	local T = TM.TEXTS

	local function fresh(opts)
		opts = opts or {}
		local d = Template.new()
		d.company = { name = "Nimbus Labs", logo = "N", color = "cyan", spec = "general", foundedAt = 0, reputation = 0 }
		if opts.money then d.money = opts.money end
		return d
	end
	local function addModel(d, id, status, name, version)
		local m = { id = id, name = name or "Nova", version = version or 1, sizeId = "s100m", focusId = "balanced", status = status,
			stats = {}, overall = 40, createdAt = 0, trainedAt = 0, trainCost = 1280, dataUsed = { total = 4e9, quality = 0.4 } }
		d.models[id] = m
		table.insert(d.modelOrder, id)
		return m
	end
	local function data4B(d) d.data = { general = { tokens = 4e9, quality = 0.42 } } end
	local NOW = 1416666 * 1200 -- a fixed server time (unix seconds)
	local function takeDaily(d) d.empire.daily = { day = math.floor(NOW / 86400), streak = 1 } end
	local function claimAllQuests(d)
		for _, q in EmpireConfig.QUESTS do if EmpireMath.progress(d, q) >= q.target then d.empire.quests[q.id] = true end end
	end

	------------------------------------------------------------------ T1 TutorialMath.step
	local d = fresh()
	local v = TM.step(d, { revenue = 0 }, { computerOpen = false, inputKind = "touch", greetingOver = false, displayName = "Sam", assistant = "Ada" })
	check("T1 fresh save, Computer closed -> step 1 openLab", v and v.step == 1 and v.sub == "openLab" and v.title == "Open your AI lab", v and v.step)
	check("T1 step 1 greeting with the display name", v.line == "Ada: Hi Sam! Let's build your first AI.", v.line)
	check("T1 step 1 action OPEN LAB › -> Studio design", v.action and v.action.label == "OPEN LAB ›" and v.action.route == "lab_design")
	check("T1 step 1 ring on the HUD action, dim on, chip left of the column", v.target == "guide_action" and v.dim == true and v.chip == "Tap to open the lab", v.chip)
	check("T1 step 1 collect = founder reward $1,200", v.collect == 1200, v.collect)
	v = TM.step(d, {}, { greetingOver = false, displayName = "AVeryLongDisplayName", assistant = "Ada" })
	check("T1 {Name} dropped when longer than 12 characters", v.text == "Hi! Let's build your first AI.", v.text)
	v = TM.step(d, {}, { greetingOver = false, displayName = "TwelveChars1", assistant = "Ada" })
	check("T1 {Name} kept at exactly 12 characters", v.text == "Hi TwelveChars1! Let's build your first AI.", v.text)
	v = TM.step(d, {}, { greetingOver = true, inputKind = "pc", assistant = "Ada" })
	check("T1 step 1 PC line mentions C", v.text == T.pc and string.find(v.text, "press C", 1, true) ~= nil and v.chip == "Click to open the lab", v.chip)
	v = TM.step(d, {}, { greetingOver = true, inputKind = "touch", assistant = "Ada" })
	check("T1 step 1 touch line", v.text == T.touch)
	v = TM.step(d, {}, { greetingOver = true, inputKind = "pad", assistant = "Ada" })
	check("T1 step 1 gamepad line + chip 'Press L1 to open the lab' (fix round 1)", v.text == T.pad and v.chip == "Press L1 to open the lab" and string.find(T.pad, "(A)", 1, true) == nil, v.chip)
	v = TM.step(d, {}, { computerOpen = true, assistant = "Ada" })
	check("T1 step 1 inside the Menu: Home line, ring target menu_lab, no chip", v.text == T.menuLab and v.target == "menu_lab" and v.chip == nil)

	-- 2: the Studio's first-model Review
	v = TM.step(d, {}, { computerOpen = true, studioOpen = true, studioMode = "design", assistant = "Ada" })
	check("T1 Studio design without data -> 2 buyData, ring on Primary, dim, no chip", v.step == 2 and v.sub == "buyData" and v.target == "Primary" and v.dim and v.chip == nil and v.title == "Get training data", v.sub)
	data4B(d)
	v = TM.step(d, {}, { computerOpen = true, studioOpen = true, studioMode = "design", assistant = "Ada" })
	check("T1 after the data plan -> 2 start, ring on Primary", v.step == 2 and v.sub == "start" and v.target == "Primary" and v.text == T.start, v.sub)
	d.data = {}
	-- cash edge: plan too expensive (Primary reads NEED TRAINING DATA · OPEN DATA), nothing claimable, daily taken
	claimAllQuests(d); takeDaily(d)
	v = TM.step(d, {}, { computerOpen = true, studioOpen = true, studioMode = "design", studioPrimary = "needData", serverTime = NOW, assistant = "Ada" })
	check("T1 plan costs more than the cash -> cash edge 'Datasets has free data'", v.step == 2 and v.sub == "cash" and v.text == T.cashData and v.collect == nil, v.text)
	check("T1 cash edge: no dim on a disabled / redirecting Primary", v.dim == false)
	v = TM.step(d, {}, { computerOpen = true, studioOpen = true, studioMode = "design", studioPrimary = "needCash", serverTime = NOW, assistant = "Ada" })
	check("T1 starter GPU only, nothing claimable, daily taken -> '00:00 UTC' (never 'Sell a GPU')", v.text == T.cashWait and string.find(v.text, "Sell a GPU", 1, true) == nil, v.text)
	d.gpus = { laptop = 1, consumer = 1 }
	claimAllQuests(d) -- owning a GPU finishes the "Upgrade the rig" goal: collected, so the GPU line can show
	v = TM.step(d, {}, { computerOpen = true, studioOpen = true, studioMode = "design", studioPrimary = "needCash", serverTime = NOW, assistant = "Ada" })
	check("T1 owns a non-starter GPU -> 'Sell a GPU'", v.text == T.cashSell, v.text)
	d.gpus = { laptop = 1 }
	d.empire.daily = { day = -1, streak = 0 }
	v = TM.step(d, {}, { computerOpen = true, studioOpen = true, studioMode = "design", studioPrimary = "needCash", serverTime = NOW, assistant = "Ada" })
	check("T1 daily grant claimable -> 'Claim today's grant on Home'", v.text == T.cashDaily, v.text)
	d.empire.quests = {}
	v = TM.step(d, {}, { computerOpen = true, studioOpen = true, studioMode = "design", studioPrimary = "needCash", serverTime = NOW, assistant = "Ada" })
	check("T1 claimable quests first -> 'Collect your rewards first'", v.text == T.cashClaim and v.collect == 1200, v.text)
	-- Studio closed after opening it (saved step 2) -> stays 2
	d.empire.tutorial.step = 2
	v = TM.step(d, {}, { computerOpen = false, assistant = "Ada" })
	check("T1 Studio closed with saved step 2 -> 2 (not 1), HUD ring + OPEN LAB", v.step == 2 and v.target == "guide_action" and v.action.label == "OPEN LAB ›", v.step)
	d.empire.tutorial.step = 0
	-- data bought in Datasets first, then the Studio opens -> 2 start
	data4B(d)
	v = TM.step(d, {}, { studioOpen = true, computerOpen = true, studioMode = "design", assistant = "Ada" })
	check("T1 data bought in Datasets first -> 2 start", v.step == 2 and v.sub == "start")

	-- 3: training
	d.training = { modelId = "m1", workTotal = 100, workDone = 40, cost = 1280, eventRolled = false }
	addModel(d, "m1", "training")
	v = TM.step(d, {}, { trainingEta = 72, assistant = "Ada" })
	check("T1 training -> 3 wait with the ETA text", v.step == 3 and v.sub == "wait" and v.text == "About 1 min 12 s left. You can close the lab.", v.text)
	check("T1 3 wait: WATCH › secondary, no ring, bar = training progress", v.action.label == "WATCH ›" and v.action.style == "secondary" and v.target == nil and math.abs(v.frac - 0.4) < 1e-9, v.frac)
	v = TM.step(d, {}, { trainingEta = 40, assistant = "Ada" })
	check("T1 3 wait: '40 s' form", v.text == "About 40 s left. You can close the lab.", v.text)
	d.training.event = { id = "data_issue", pending = true, expiresAt = 0 }
	v = TM.step(d, {}, { trainingEta = 40, assistant = "Ada", inputKind = "touch" })
	check("T1 pending event -> 3 decide, DECIDE › gold, ring after 6 s, collect hidden", v.sub == "decide" and v.action.label == "DECIDE ›" and v.action.style == "warn" and v.delay == 6 and v.collect == nil and v.target == "guide_action" and v.chip == "Tap to decide", v.chip)
	v = TM.step(d, {}, { computerOpen = true, studioOpen = true, studioMode = "training", assistant = "Ada" })
	check("T1 decide in the Studio -> ring on Decision, no chip", v.target == "Decision" and v.chip == nil)
	d.training = nil
	d.models.m1.status = "trained"
	d.stats.modelsTrained = 1

	-- 4: launch
	v = TM.step(d, {}, { computerOpen = false, assistant = "Ada", inputKind = "touch" })
	check("T1 trained, world -> 4 open, SEE YOUR AI › -> lab_release with the model id", v.step == 4 and v.sub == "open" and v.action.label == "SEE YOUR AI ›" and v.action.route == "lab_release" and v.action.modelId == "m1", v.sub)
	check("T1 4 open line names the model as the Studio does", v.text == "Nova v1 is ready! Let's see how it did." and v.chip == "Tap to see it", v.text)
	v = TM.step(d, {}, { computerOpen = true, studioOpen = true, studioMode = "reveal", assistant = "Ada" })
	check("T1 reveal mode -> ring on Launch after the sequence + 3 s, card hidden", v.sub == "reveal" and v.target == "Launch" and v.card == false and math.abs(v.delay - (0.18 + 0.2 + 1.15 + 0.96 + 3)) < 1e-9, v.delay)
	v = TM.step(d, {}, { computerOpen = true, studioOpen = true, studioMode = "launch", assistant = "Ada" })
	check("T1 launch mode -> ring on LaunchButton with dim", v.sub == "launch" and v.target == "LaunchButton" and v.dim == true)

	-- 5: live
	d.models.m1.status = "live"
	d.stats.modelsReleased = 1
	v = TM.step(d, { revenue = 0 }, { assistant = "Ada" })
	check("T1 released, no revenue -> 5 waitIncome", v.step == 5 and v.sub == "waitIncome" and v.text == "Users are trying Nova v1 now." and v.action.route == "done", v.text)
	v = TM.step(d, { revenue = 3.2 }, { assistant = "Ada" })
	check("T1 first revenue -> 5 income, bar full", v.sub == "income" and v.title == "First income!" and v.frac == 1 and v.text == "People pay to use Nova v1. Well done!", v.text)
	d.stats.totalRevenue = 12
	v = TM.step(d, { revenue = 0 }, { assistant = "Ada" })
	check("T1 stats.totalRevenue also counts as income", v.sub == "income")
	-- collect = exact sum of the claimable rewards
	d.empire.quests = {}
	local want = 0
	for _, q in EmpireConfig.QUESTS do if EmpireMath.progress(d, q) >= q.target then want += q.reward end end
	v = TM.step(d, { revenue = 1 }, { assistant = "Ada" })
	check("T1 collect = the exact sum of claimable rewards (" .. want .. ")", v.collect == want and want == 1200 + 2500 + 3000 + 1800, v.collect)
	-- skipped / done
	d.empire.tutorial.skipped = true
	check("T1 skipped -> nil", TM.step(d, {}, {}) == nil and not TM.active(d))
	d.empire.tutorial.skipped = false
	d.empire.tutorial.done = true
	check("T1 done -> nil", TM.step(d, {}, {}) == nil)
	check("T1 no company -> nil", TM.step(Template.new(), {}, {}) == nil)
	-- extra Robux cash changes nothing
	local rich = fresh({ money = 5e6 })
	local vr = TM.step(rich, {}, { greetingOver = true, inputKind = "touch", assistant = "Ada" })
	check("T1 extra Robux cash -> the same step 1", vr.step == 1 and vr.sub == "openLab")
	vr = TM.step(rich, {}, { studioOpen = true, computerOpen = true, studioMode = "design", assistant = "Ada" })
	check("T1 extra Robux cash -> the same step 2 (no cash edge)", vr.step == 2 and vr.sub == "buyData")
	-- old saves through the real migration
	local old = fresh()
	old.version = 6
	old.empire.tutorial = nil
	addModel(old, "o1", "live"); old.stats.modelsTrained = 3; old.stats.modelsReleased = 2; old.empire.contractsCompleted = 1
	local migrated = Template.migrate(old)
	check("T1 old save with a release (after the cleaner) -> nil, guide done", TM.step(migrated, {}, {}) == nil and migrated.empire.tutorial.done == true)
	check("T1 old save: seen filled with its open pages (no NEW flood)", migrated.empire.tutorial.seen.market == true and migrated.empire.tutorial.seen["clients.receipts"] == true and migrated.empire.tutorial.seen["lab.research"] == true)
	local old2 = fresh()
	old2.empire.tutorial = nil
	addModel(old2, "o2", "trained"); old2.stats.modelsTrained = 1
	local migrated2 = Template.migrate(old2)
	local v2 = TM.step(migrated2, {}, { assistant = "Ada" })
	check("T1 old save trained but unreleased -> 4", v2 and v2.step == 4 and migrated2.empire.tutorial.done == false, v2 and v2.step)

	------------------------------------------------------------------ T2 cleaner
	check("T2 DATA_VERSION stays 6", GameConfig.DATA_VERSION == 6)
	check("T2 EmpireMath.new has the tutorial default", (function()
		local t = EmpireMath.new().tutorial
		return t.v == 1 and t.step == 0 and t.done == false and t.skipped == false and t.tipsOff == false and next(t.seen) == nil and next(t.tips) == nil
	end)())
	local function cleaned(tut, extra)
		local x = fresh()
		x.empire.tutorial = tut
		if extra then extra(x) end
		Template.cleanTutorial(x)
		return x.empire.tutorial, x
	end
	for _, case in { { "3", 0 }, { 0 / 0, 0 }, { math.huge, 0 }, { -math.huge, 0 }, { true, 0 }, { 9, 5 }, { -2, 0 }, { 2.7, 2 }, { 4, 4 } } do
		local t = cleaned({ step = case[1] })
		check("T2 step " .. tostring(case[1]) .. " -> " .. case[2], t.step == case[2], t.step)
	end
	local t = cleaned("junk")
	check("T2 junk tutorial -> default shape", t.v == 1 and t.step == 0 and t.done == false and typeof(t.seen) == "table" and typeof(t.tips) == "table")
	t = cleaned({ done = "yes", skipped = 1, tipsOff = true, seen = { market = true, bogus = true, team = "true", ["home.money"] = true, [1] = true }, tips = { team = true, shop = true, phone = false } })
	check("T2 non-boolean flags -> false, tipsOff kept", t.done == false and t.skipped == false and t.tipsOff == true)
	check("T2 unknown / non-true seen keys dropped", t.seen.market == true and t.seen["home.money"] == true and t.seen.bogus == nil and t.seen.team == nil and t.seen[1] == nil)
	check("T2 unknown tip keys dropped (shop is never a tip)", t.tips.team == true and t.tips.shop == nil and t.tips.phone == nil)
	local x = fresh()
	x.empire.tutorial = { step = 3, done = false, seen = { market = true }, tips = { gpus = true } }
	Template.cleanTutorial(x)
	local snapshot1 = { step = x.empire.tutorial.step, done = x.empire.tutorial.done, seen = table.clone(x.empire.tutorial.seen), tips = table.clone(x.empire.tutorial.tips) }
	Template.cleanTutorial(x)
	local t2 = x.empire.tutorial
	check("T2 idempotent (two runs give equal output)", t2.step == snapshot1.step and t2.done == snapshot1.done and C.count(t2.seen) == C.count(snapshot1.seen) and t2.seen.market and t2.tips.gpus and C.count(t2.tips) == 1)
	-- migration: a save without the field gets it; a v5 save migrates through every step and keeps working
	local bare = fresh()
	bare.empire.tutorial = nil
	local mb = Template.migrate(bare)
	check("T2 save without the field -> default via nested defaults", mb.empire.tutorial and mb.empire.tutorial.step == 0 and mb.empire.tutorial.done == false)
	local v5 = { version = 5, money = 5000, company = { name = "Old Co", logo = "N", color = "cyan", spec = "general", reputation = 3 }, empire = { office = 2, quests = {} }, stats = { modelsReleased = 1, modelsTrained = 1 } }
	local m5, err5 = Template.migrate(v5)
	check("T2 a v5 save migrates (DATA_VERSION 6) and the released company never sees the guide", m5 ~= nil and err5 == nil and m5.version == 6 and m5.empire.tutorial.done == true, err5)
	local mm = Template.migrate(Template.migrate(fresh()))
	check("T2 migrate twice keeps the tutorial", mm.empire.tutorial.step == 0 and mm.empire.tutorial.v == 1)
	-- size of the replicated field (< 0.5 KB with every key set)
	do
		local full = { v = 1, step = 5, done = true, skipped = false, tipsOff = true, seen = {}, tips = {} }
		for _, k in TM.SEEN_KEYS do full.seen[k] = true end
		for _, k in TM.TIP_KEYS do full.tips[k] = true end
		local HttpService = game:GetService("HttpService")
		local ok, json = pcall(function() return HttpService:JSONEncode(full) end)
		local bytes = if ok and typeof(json) == "string" then #json else -1
		check("T2 the full tutorial table is under 0.5 KB as JSON (" .. bytes .. " B)", bytes > 0 and bytes < 512, bytes)
	end

	------------------------------------------------------------------ T3 EmpireAction tutorial
	local Remote = M.require(R.Server.Lib.Remote)
	local binds = {}
	local origBind = Remote.bind
	Remote.bind = function(name, limits, handler) binds[name] = { handler = handler, limits = limits }; origBind(name, limits, handler) end
	Remote.setup()
	local SessionService = M.require(S.SessionService)
	local EmpireService = M.require(S.EmpireService)
	SessionService.init()
	EmpireService.init()
	local sessions = SessionService.all()
	local function add(data, uid)
		local player = { UserId = uid, Name = "P" .. uid, DisplayName = "Player " .. uid, Parent = game.Players }
		local s = C.session(data, uid)
		s.player = player
		s.lastSent, s.nextSaveAt, s.saving, s.released = 0, math.huge, false, false
		sessions[player] = s
		return s
	end
	local function act(s, payload) payload.action = "tutorial"; return binds.EmpireAction.handler(s, payload) end
	Funnel._reset(false)
	local s = add(fresh(), 3001)
	local money0 = s.data.money
	local tut = s.data.empire.tutorial
	check("T3 step n=6 on a fresh save -> BAD_INPUT", act(s, { op = "step", n = 6 }).err == "BAD_INPUT" and tut.step == 0)
	check("T3 step n=3 on a fresh save (reachable 1 + 1 = 2) -> BAD_INPUT", act(s, { op = "step", n = 3 }).err == "BAD_INPUT")
	check("T3 step n = 2.5 / '2' / NaN / 0 -> BAD_INPUT", act(s, { op = "step", n = 2.5 }).err == "BAD_INPUT" and act(s, { op = "step", n = "2" }).err == "BAD_INPUT" and act(s, { op = "step", n = 0 / 0 }).err == "BAD_INPUT" and act(s, { op = "step", n = 0 }).err == "BAD_INPUT")
	local r = act(s, { op = "step", n = 2 })
	check("T3 step n=2 -> step 2, funnel 3 'Lab opened'", r.ok and tut.step == 2 and Funnel.log[#Funnel.log].step == 3, #Funnel.log)
	act(s, { op = "step", n = 1 })
	check("T3 step never goes down", tut.step == 2)
	local logN = #Funnel.log
	act(s, { op = "step", n = 2 })
	check("T3 funnel step sent once per session", #Funnel.log == logN)
	check("T3 done before release -> NOT_READY", act(s, { op = "done" }).err == "NOT_READY" and tut.done == false)
	check("T3 seen with an unknown key -> BAD_INPUT, nothing stored", act(s, { op = "seen", keys = { "market", "bogus" } }).err == "BAD_INPUT" and tut.seen.market == nil)
	check("T3 seen with 9 keys -> BAD_INPUT", act(s, { op = "seen", keys = { "market", "team", "clients", "lab.data", "lab.gpus", "lab.arena", "home.money", "home.goals", "team.fleet" } }).err == "BAD_INPUT")
	check("T3 seen non-table / empty -> BAD_INPUT", act(s, { op = "seen", keys = "market" }).err == "BAD_INPUT" and act(s, { op = "seen", keys = {} }).err == "BAD_INPUT")
	check("T3 seen with dictionary keys -> BAD_INPUT", act(s, { op = "seen", keys = { a = "market" } }).err == "BAD_INPUT")
	r = act(s, { op = "seen", keys = { "market", "team" } })
	check("T3 seen marks the keys", r.ok and tut.seen.market == true and tut.seen.team == true)
	check("T3 tip with an unknown key / shop -> BAD_INPUT", act(s, { op = "tip", key = "shop" }).err == "BAD_INPUT" and act(s, { op = "tip", key = 5 }).err == "BAD_INPUT")
	check("T3 tip marks the key", act(s, { op = "tip", key = "phone" }).ok and tut.tips.phone == true)
	check("T3 tips on=false -> tipsOff; non-boolean -> BAD_INPUT", act(s, { op = "tips", on = false }).ok and tut.tipsOff == true and act(s, { op = "tips", on = "no" }).err == "BAD_INPUT")
	check("T3 tips on=true -> tipsOff false", act(s, { op = "tips", on = true }).ok and tut.tipsOff == false)
	check("T3 replayTips clears the tips", act(s, { op = "replayTips" }).ok and next(tut.tips) == nil)
	check("T3 unknown op -> BAD_INPUT", act(s, { op = "grant" }).err == "BAD_INPUT" and act(s, {}).err == "BAD_INPUT")
	r = act(s, { op = "skip" })
	check("T3 skip -> skipped, custom event TutorialSkipped (not a funnel step)", r.ok and tut.skipped == true and Funnel.log[#Funnel.log].kind == "custom" and Funnel.log[#Funnel.log].name == "TutorialSkipped" and Funnel.log[#Funnel.log].value == 2)
	check("T3 step after a skip -> NOT_AVAILABLE", act(s, { op = "step", n = 2 }).err == "NOT_AVAILABLE")
	r = act(s, { op = "restart" })
	check("T3 restart before a release -> skipped/done cleared, step 0", r.ok and tut.skipped == false and tut.done == false and tut.step == 0)
	-- release, done, restart refused
	addModel(s.data, "r1", "live"); s.data.stats.modelsTrained = 1; s.data.stats.modelsReleased = 1
	check("T3 step n=6 allowed once released (first income)", act(s, { op = "step", n = 6 }).ok and tut.step == 5)
	r = act(s, { op = "done" })
	check("T3 done after the release -> done, funnel 8", r.ok and tut.done == true and Funnel.log[#Funnel.log].step == 8)
	check("T3 skip after done -> ALREADY_DONE", act(s, { op = "skip" }).err == "ALREADY_DONE")
	check("T3 restart after a release -> NOT_AVAILABLE", act(s, { op = "restart" }).err == "NOT_AVAILABLE" and tut.done == true)
	check("T3 no tutorial op changed money", s.data.money == money0, s.data.money - money0)
	check("T3 EmpireAction stays rate limited (burst 4, 2/s, company)", binds.EmpireAction.limits.burst == 4 and binds.EmpireAction.limits.perSecond == 2 and binds.EmpireAction.limits.company == true)
	-- a missing / broken table is repaired on the fly
	local s2 = add(fresh(), 3002)
	s2.data.empire.tutorial = "broken"
	check("T3 broken tutorial table repaired by the handler", act(s2, { op = "tip", key = "team" }).ok and typeof(s2.data.empire.tutorial) == "table" and s2.data.empire.tutorial.tips.team == true)

	------------------------------------------------------------------ T4 ClaimQuest {all = true}
	local s3 = add(fresh(), 3003)
	data4B(s3.data) -- data quest (1B tokens) done
	addModel(s3.data, "q1", "live"); s3.data.stats.modelsTrained = 1; s3.data.stats.modelsReleased = 1
	local expected, ids = 0, {}
	for _, q in EmpireConfig.QUESTS do if EmpireMath.progress(s3.data, q) >= q.target then expected += q.reward; table.insert(ids, q.id) end end
	local cash = s3.data.money
	local xp0 = s3.data.empire.xp
	r = binds.ClaimQuest.handler(s3, { all = true })
	check("T4 claims every eligible quest once (" .. #ids .. ")", r.ok and #r.claimed == #ids and #ids == 4, #ids)
	check("T4 total = the sum of rewards = cash gained", r.total == expected and s3.data.money == cash + expected and expected == 1200 + 1800 + 2500 + 3000, r.total)
	check("T4 xp of every claimed quest", s3.data.empire.xp - xp0 == 50 + 70 + 100 + 120, s3.data.empire.xp - xp0)
	local cash2 = s3.data.money
	r = binds.ClaimQuest.handler(s3, { all = true })
	check("T4 a second call claims nothing", r.ok and r.total == 0 and #r.claimed == 0 and s3.data.money == cash2)
	check("T4 all = 'yes' -> BAD_INPUT", binds.ClaimQuest.handler(s3, { all = "yes" }).err == "BAD_INPUT")
	local s4 = add(fresh(), 3004)
	local c4 = s4.data.money
	r = binds.ClaimQuest.handler(s4, { questId = "founder" })
	check("T4 single-id path unchanged", r.ok and s4.data.money == c4 + 1200 and s4.data.empire.quests.founder == true)
	check("T4 single-id again -> ALREADY_DONE", binds.ClaimQuest.handler(s4, { questId = "founder" }).err == "ALREADY_DONE")
	check("T4 single-id not ready -> NOT_READY", binds.ClaimQuest.handler(s4, { questId = "release" }).err == "NOT_READY")
	check("T4 ledger records the claimed rewards as 'quest'", C.ledger(s3.data.empire, "i", "quest") >= expected, C.ledger(s3.data.empire, "i", "quest"))

	------------------------------------------------------------------ T5 assistant name
	local okA, Assistant = pcall(M.require, S.AssistantService)
	check("T5 AssistantService loads in the mock", okA, Assistant)
	if okA then
		local same, total = 0, 0
		for _, id in { 1, -1, 2, 3, 7, 42, 99, 1001, 4242, 77777, 123456, 9999999, 2147483646, 31, 500, 8, 64, 1000000, 3003, 271828 } do
			total += 1
			local full = Assistant.identity(id)
			if TM.assistantName(id) == string.match(full, "^(%S+)") then same += 1 else print("  mismatch " .. id .. ": " .. TM.assistantName(id) .. " vs " .. full) end
		end
		check("T5 assistantName == first name of AssistantService.identity for 20 ids", same == total and total == 20, same .. "/" .. total)
		check("T5 user ids 1 and -1 -> 'Ada'", TM.assistantName(1) == "Ada" and TM.assistantName(-1) == "Ada", TM.assistantName(1) .. "/" .. TM.assistantName(-1))
	end

	------------------------------------------------------------------ T10 unlock waves
	local function has(list, key) return table.find(list, key) ~= nil end
	local f = fresh()
	local keys = TM.unlockedKeys(f)
	check("T10 fresh: Home + Lab (Models, Data, GPUs) only", has(keys, "home") and has(keys, "home.goals") and has(keys, "lab.models") and has(keys, "lab.data") and has(keys, "lab.gpus")
		and not has(keys, "market") and not has(keys, "lab.research") and not has(keys, "lab.arena") and not has(keys, "shop") and not has(keys, "home.money") and not has(keys, "team"), table.concat(keys, ","))
	f.stats.modelsTrained = 1
	keys = TM.unlockedKeys(f)
	check("T10 first trained: + Test arena, Market → Projects; Market itself still locked", has(keys, "lab.arena") and has(keys, "market.projects") and not has(keys, "market") and not has(keys, "shop"))
	local hired = fresh(); hired.empire.employees.researcher = 1
	check("T10 first hire before a launch: + Lab → Research", has(TM.unlockedKeys(hired), "lab.research") and not has(TM.unlockedKeys(hired), "market"))
	local pts = fresh(); pts.empire.points = 50
	check("T10 50 research points before a launch: + Lab → Research", has(TM.unlockedKeys(pts), "lab.research"))
	f.stats.modelsReleased = 1
	keys = TM.unlockedKeys(f)
	check("T10 first launch: Market, Clients, Team (incl. Campus), Home → Money, Research, Shop", has(keys, "market") and has(keys, "market.myais") and has(keys, "market.lines") and has(keys, "market.leaderboard")
		and has(keys, "clients") and has(keys, "clients.clients") and has(keys, "team.campus") and has(keys, "team.settings") and has(keys, "home.money") and has(keys, "lab.research") and has(keys, "shop") and not has(keys, "clients.receipts"))
	f.empire.contractsCompleted = 1
	check("T10 first client: + Clients → Receipts", has(TM.unlockedKeys(f), "clients.receipts"))
	local o2 = fresh(); o2.empire.office = 2
	check("T10 office 2 alone opens nothing new (Campus is wave 2)", not has(TM.unlockedKeys(o2), "team.campus") and #TM.unlockedKeys(o2) == #TM.unlockedKeys(fresh()))
	check("T10 SEEN_KEYS are 14 page keys, all in PAGES", #TM.SEEN_KEYS == 14 and (function()
		for _, k in TM.SEEN_KEYS do local found = false; for _, p in TM.PAGES do if p.key == k then found = true end end; if not found then return false end end
		return true
	end)())
	check("T10 TIP_KEYS has 6 keys and no shop", #TM.TIP_KEYS == 6 and not table.find(TM.TIP_KEYS, "shop"))
end

setfenv(body, M.envFor(nil))
local ok, res = M.runMain(body, { timeout = 300 })
if not ok then C.fail += 1; print("FAIL  body crashed: " .. tostring(res)) end
if M.stats.errors > 0 then C.fail += 1; print("FAIL  background errors: " .. M.stats.errors) end
C.summary("menu_server")
