--!nocheck
-- menu package, client side (ONBOARDING_SPEC A + B, lab requests #1 #2 #5): the real HUD, Menu (Computer), Home,
-- Guide layer, GuideController, Model Studio and Intro in the mock, wired to the REAL server handlers.
--   state "guide" (tests/lab/lab_setup "fresh", iPhone 844x390, touch):
--     guided path from spawn to a live AI by tapping ONLY the ringed element (T6 resolver on every step, 5 taps),
--     Collect $X, funnel ops, first income + GOT IT + hand-off; redirects of the founder computer / C / Menu / L1
--     during steps 1-2 (A8); skip, restart (A12); T8 (no guide button, no Active, card hidden under the Menu, no chip
--     in the Menu, no gamepad selection in the world); lab #1 (no score in the toast), #2 (Studio sections), #5
--     (Toast.hold); the Intro (A7)
--   state "menu" (tests/apps/ui_setup "mid", desktop): T11 route table (+ every (app, section) pair grepped by
--     tests/menu/routes.py), back rule from every page, unknown -> Home, no feature lost, unlock waves + locked card +
--     deep links (B5), NEW badges (never Shop, none during the guide, `seen` batches <= 8), HUD Shop button rule
--     (B11/T12), T9 Home.cards (incl. never a Shop card), T12 no Shop in TutorialMath.step
-- Run: python3 tests/menu/routes.py && cd tests/menu && ../../tools/luau test_client.luau -a .gen_menu <guide|menu>
local P = print
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_menu")
local STATE = args[2] or "guide"
local M = require("../../harness/mock")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

-- the shared setups (plain requires outside the mock's environment)
local setupLab = require("../lab/lab_setup")
local setupApps = require("../apps/ui_setup")
local okFound, found = pcall(require, "./.routes_found")

local IPHONE = { 844, 390, { top = 58, right = 47, bottom = 21, left = 47 } }
local DESK = { 1280, 720, { top = 58, right = 0, bottom = 0, left = 0 } }

local function patchMethod(cls, name, fn)
	M.IMPL[cls] = M.IMPL[cls] or { methods = {}, get = {}, set = {}, defaults = {} }
	M.IMPL[cls].methods[name] = fn
	M.classInfo(cls).methods[name] = fn
end
local function patchGet(cls, prop, fn)
	M.IMPL[cls] = M.IMPL[cls] or { methods = {}, get = {}, set = {}, defaults = {} }
	M.IMPL[cls].get[prop] = fn
	M.classInfo(cls).get[prop] = fn
end

local function body()
	local game = M.game
	local G = M.G
	local RS = game.ReplicatedStorage
	local Client = game.StarterPlayer.StarterPlayerScripts.Client
	local Enum = G.Enum
	local UIS = game:GetService("UserInputService")
	local GS = game:GetService("GuiService")
	local RunService = game:GetService("RunService")

	-- ContextActionService: record the Menu's bindings (they are made in Computer.mount, inside the setup)
	local cas = {}
	patchMethod("ContextActionService", "BindActionAtPriority", function(_, name, fn, touchButton, priority, ...)
		cas[name] = { fn = fn, touch = touchButton, priority = priority, keys = { ... } }
	end)
	patchMethod("ContextActionService", "UnbindAction", function(_, name) cas[name] = nil end)
	local preferred = Enum.PreferredInput.Touch
	patchGet("UserInputService", "PreferredInput", function() return preferred end)
	local studio = false
	patchMethod("RunService", "IsStudio", function() return studio end)

	-- os.clock follows the mock's virtual clock (ring delays, dim timing, tips), like tests/apps/ui_setup does
	G.os = setmetatable({ clock = function() return M.Sched.now end }, { __index = os })
	local function settle(t) M.settle(t or 0.3) end
	local function frames(n)
		for _ = 1, n or 3 do
			M.fire(RunService.RenderStepped, 1 / 60)
			M.fire(RunService.Heartbeat, 1 / 60)
		end
	end

	if STATE == "guide" then
		---------------------------------------------------------------------------------------------- setup
		local uis = UIS
		uis[M.KEY].props.TouchEnabled = true
		uis[M.KEY].props.MouseEnabled = false
		uis[M.KEY].props.KeyboardEnabled = false
		local ui = setupLab(M, GEN, "fresh", IPHONE[1], IPHONE[2], IPHONE[3])
		local pg = ui.playerGui
		local lp = game.Players.LocalPlayer
		lp.FindFirstChild = function(_, n) if n == "PlayerGui" then return pg end return nil end
		lp.GetAttribute = function() return nil end
		local TM = M.require(RS.Shared.TutorialMath)
		local JourneyMath = M.require(RS.Shared.JourneyMath)
		local CompanyConfig = M.require(RS.Shared.Config.CompanyConfig)
		local Computer = ui.Computer
		local Studio = ui.Studio
		local LabState = ui.LabState
		local HUD = M.require(Client.UI.Screens.HUD)
		local Guide = M.require(Client.UI.Screens.Guide)
		local GuideController = M.require(Client.Controllers.GuideController)
		local HomeApp = M.require(Client.UI.Apps.HomeApp)
		local Toast = M.require(Client.UI.Toast)
		local GoalText = M.require(Client.UI.GoalText)
		local State = M.require(Client.Controllers.StateController)

		-- every EmpireAction "tutorial" op and ClaimQuest call reaches the real handler; record them
		local ops, claims = {}, {}
		local origEA, origCQ = ui.binds.EmpireAction, ui.binds.ClaimQuest
		ui.binds.EmpireAction = function(s, p)
			if typeof(p) == "table" and p.action == "tutorial" then table.insert(ops, table.clone(p)) end
			return origEA(s, p)
		end
		ui.binds.ClaimQuest = function(s, p) table.insert(claims, p); return origCQ(s, p) end
		local toasts = {}
		local origShow = Toast.show
		Toast.show = function(kind, text, seconds) table.insert(toasts, { kind = kind, text = text }); return origShow(kind, text, seconds) end
		local function lastOp(name) for i = #ops, 1, -1 do if ops[i].op == name then return ops[i] end end return nil end
		local function stepOps() local out = {} for _, o in ops do if o.op == "step" then table.insert(out, o.n) end end return out end

		local function fresh()
			local s, d = ui.use("fresh")
			d.money = 10000
			d.empire.quests = {}
			d.empire.tutorial = { v = 1, step = 0, done = false, skipped = false, tipsOff = false, seen = {}, tips = {} }
			s.live.revenue, s.live.cost, s.live.users = 0, 0, 0
			GuideController._reset()
			ui.push(); settle()
			return s, d
		end
		Guide.mount(pg)
		GuideController.init()
		local s, d = fresh()

		local function update(n) for _ = 1, n or 1 do GuideController.update() end end
		-- the guide's 0.2 s heartbeat (frame signals never fire in the mock): virtual time advances with task.wait
		-- (settle only runs queued events), so wait in steps and update after each
		local function tick(seconds)
			local left = seconds
			while left > 0 do
				local dt = math.min(0.25, left)
				G.task.wait(dt)
				M.settle(0)
				GuideController.update()
				left -= dt
			end
		end
		local function visible(inst)
			local x = inst
			while x and x ~= pg do
				if (x:IsA("GuiObject") and not x.Visible) or (x:IsA("ScreenGui") and not x.Enabled) then return false end
				x = x.Parent
			end
			return x == pg
		end
		local taps = 0
		local function tap(b, counted)
			if not b then return false end
			if counted ~= false then taps += 1 end
			M.fire(b.Activated, {}, 1)
			settle(0.6)
			return true
		end
		local function studioPart(name)
			local root = Studio.root
			if not root then return nil end
			return root:FindFirstChild(name, true)
		end

		---------------------------------------------------------------------------------------------- step 1
		update(2)
		local v = GuideController.view()
		check("step 1 on a fresh company: Open your AI lab", v and v.step == 1 and v.title == "Open your AI lab", v and v.step)
		local action = GuideController.resolve("guide_action")
		check("T6 guide_action -> the HUD row's GuideAction button 'OPEN LAB ›', visible", action and action.Name == "GuideAction" and action.Text == "OPEN LAB ›" and visible(action), action and action.Text)
		check("T6 the ring sits on the HUD action at once (no delay at step 1)", Guide.ringTarget() == action)
		check("step 1: dim at first contact (hole = card + row)", Guide.dimming())
		check("step 1: chip 'Tap to open the lab' (touch)", Guide.chipText() == "Tap to open the lab", Guide.chipText())
		local refs = HUD.guideTargets()
		local collect = refs.collect
		check("[Collect $1,200] beside the action (founder reward)", collect and collect.Visible and collect.Text == "Collect $1,200", collect and collect.Text)
		local caption = pg:FindFirstChild("GuideCaption", true)
		local line = pg:FindFirstChild("GuideLine", true)
		check("card caption FIRST STEPS · 1/5", caption and caption.Text == "FIRST STEPS · 1/5", caption and caption.Text)
		local A = TM.assistantName(lp.UserId)
		check("card line '{A}: Hi Founder! ...' (greeting with the display name, RichText-escaped)", line and string.find(line.Text, A .. ":", 1, true) and string.find(line.Text, "Hi Founder! Let&apos;s build your first AI.", 1, true) and v.text == "Hi Founder! Let's build your first AI.", line and line.Text)
		-- compact phone panel (A2.2): logo, name, cash, +$X/day; the glass panel is hidden
		local mini, panel = pg:FindFirstChild("CompactPanel", true), pg:FindFirstChild("Panel", true)
		check("phone: compact HUD panel instead of the glass panel", mini and mini.Visible and panel and not panel.Visible)
		local netLabel = mini and mini:FindFirstChild("NetPerDay", true)
		check("compact panel keeps the name NetPerDay (B12 contract)", netLabel ~= nil and string.find(netLabel.Text, "/day", 1, true) ~= nil, netLabel and netLabel.Text)
		-- gamepad: the guide never selects a HUD button by itself in the world (A10)
		preferred = Enum.PreferredInput.Gamepad
		GS.SelectedObject = nil
		GuideController._reset() -- the ring is placed again (first contact) while a gamepad is the input
		update(3); frames(3); update(1)
		check("T8 gamepad world step: no automatic SelectedObject", GS.SelectedObject == nil, GS.SelectedObject and GS.SelectedObject.Name)
		v = GuideController.view()
		check("gamepad chip 'Press L1 to open the lab' (fix round 1: L1 alone opens it; no (A) that would buy the data plan)", v.chip == "Press L1 to open the lab", v.chip)
		preferred = Enum.PreferredInput.Touch
		update(1)
		-- T8: nothing in the guide layer is a button or active
		local guiLayer = pg:FindFirstChild("AIEmpire_Guide")
		local bad = {}
		for _, x in guiLayer:GetDescendants() do
			if x:IsA("GuiButton") then table.insert(bad, x.Name .. " is a button") end
			if x:IsA("GuiObject") and x.Active then table.insert(bad, x.Name .. " Active") end
			if x:IsA("GuiObject") then
				local ok, sink = pcall(function() return x.InputSink end)
				if ok and sink ~= nil and sink ~= Enum.InputSink.None then table.insert(bad, x.Name .. " InputSink") end
			end
		end
		check("T8 no guide object is a GuiButton, Active or sinks input", #bad == 0 and guiLayer.DisplayOrder == 22, table.concat(bad, ", "))

		-- Collect $X: every finished goal in place (ClaimQuest {all = true}), one toast
		local money0 = d.money
		tap(collect, false)
		ui.push(); settle()
		check("Collect $1,200 -> ClaimQuest {all = true}, +$1,200, toast '+$1,200 from 1 goal'", claims[#claims] and claims[#claims].all == true and d.money == money0 + 1200 and toasts[#toasts] and toasts[#toasts].text == "+$1,200 from 1 goal", toasts[#toasts] and toasts[#toasts].text)

		---------------------------------------------------------------------------------------------- step 2
		tap(GuideController.resolve("guide_action"))
		update(2)
		check("OPEN LAB › opens the Model Studio design view (first model at the Review)", Computer.isOpen() and Studio.mode == "design", Studio.mode)
		frames(2)
		local column = pg:FindFirstChild("Column", true)
		check("T8 the HUD card is hidden while the Menu is open", column and not column.Visible)
		v = GuideController.view()
		check("step 2 buyData: Get training data", v.step == 2 and v.sub == "buyData" and v.title == "Get training data", v.sub)
		local primary = GuideController.resolve("Primary")
		check("T6 Primary -> 'BUY DATA PLAN · $…' under ModelStudio (the plan the Studio picks for the cash)", primary and primary.Name == "Primary" and string.find(primary.Text, "^BUY DATA PLAN · %$") ~= nil and primary:IsDescendantOf(Studio.root), primary and primary.Text)
		local strip = studioPart("BuyDataPlan")
		check("T6 the step-4 strip button BuyDataPlan is NOT visible on the Review (revision-1 bug)", strip == nil or not visible(strip))
		check("T8 no chip while the Menu is open (Studio target)", Guide.chipText() == nil and v.chip == nil)
		check("ring on Primary + first-contact dim", Guide.ringTarget() == primary and Guide.dimming())
		check("funnel: op step n = 2 sent once", table.find(stepOps(), 2) ~= nil)
		tap(primary)
		ui.push(); settle(); update(2)
		primary = GuideController.resolve("Primary")
		v = GuideController.view()
		check("after BUY DATA PLAN: 2 start, Primary 'START TRAINING · $1,280'", v.sub == "start" and primary and primary.Text == "START TRAINING · $1,280", primary and primary.Text)
		check("ring stays on Primary after the label change", Guide.ringTarget() == primary)

		---------------------------------------------------------------------------------------------- step 3
		tap(primary)
		ui.push(); settle(); update(2)
		v = GuideController.view()
		check("START -> step 3 wait (Your AI is training), no ring", v.step == 3 and v.sub == "wait" and v.target == nil and Guide.ringTarget() == nil, v.sub)
		check("funnel: op step n = 3", table.find(stepOps(), 3) ~= nil)
		-- the Studio decision card (if the run pauses) is ringed by name
		d.training.event = { id = "data_issue", pending = true, expiresAt = 0 }
		ui.push(); settle(); update(1)
		Studio.open("training"); settle(); update(1)
		local decision = GuideController.resolve("Decision")
		check("T6 Decision -> the Studio's decision card", decision ~= nil and decision:IsDescendantOf(Studio.root), decision and decision.Name)
		tick(6.5)
		check("decide: ring after 6 s on Decision (no chip in the Studio)", Guide.ringTarget() == decision and Guide.chipText() == nil)
		d.training.event = nil
		ui.push(); settle(); update(1)

		---------------------------------------------------------------------------------------------- step 4
		ui.AIModelService.finishNow(s)
		ui.push(); settle(5); update(1)
		check("TRAINING_COMPLETE with the Studio open plays the reveal", Studio.mode == "reveal", Studio.mode)
		v = GuideController.view()
		check("step 4 reveal: card hidden, target Launch", v.step == 4 and v.sub == "reveal" and v.card == false and v.target == "Launch", v.sub)
		local launch = GuideController.resolve("Launch")
		check("T6 Launch -> LAUNCH › under ModelStudio (not the Lab home's Launch row)", launch and launch:IsDescendantOf(Studio.root), launch and launch:GetFullName())
		check("reveal: no ring before the sequence + 3 s", Guide.ringTarget() ~= launch)
		tick(6)
		check("reveal: ring on LAUNCH › after the sequence + 3 s", Guide.ringTarget() == launch)
		check("funnel: op step n = 4", table.find(stepOps(), 4) ~= nil)
		tap(launch)
		settle(3); ui.push(); settle(1); update(2)
		check("LAUNCH › -> Launch Day", Studio.mode == "launch", Studio.mode)
		local launchButton = GuideController.resolve("LaunchButton")
		check("T6 LaunchButton -> Launch Day's LAUNCH button, ringed at once with a dim", launchButton and launchButton:IsDescendantOf(Studio.root) and Guide.ringTarget() == launchButton and Guide.dimming(), launchButton and launchButton.Text)
		tap(launchButton)
		settle(2); ui.push(); settle(); update(2)
		v = GuideController.view()
		check("LAUNCH -> step 5 (Your AI is live)", v and v.step == 5 and v.sub == "waitIncome" and d.stats.modelsReleased == 1, v and v.sub)
		check(`spawn -> live AI by tapping only the ringed element: 5 taps ({taps})`, taps == 5, taps)
		check("funnel: op step n = 5", table.find(stepOps(), 5) ~= nil)

		---------------------------------------------------------------------------------------------- step 5 + hand-off
		-- fix round 1 (review): the first revenue arrives while the player still looks at NOW LIVE in the Studio; the
		-- "First income!" burst and its 120 s auto-done wait until the Menu is closed and the HUD card is on screen
		local bursts = 0
		local origCelebrate = HUD.celebrate
		HUD.celebrate = function() bursts += 1; return origCelebrate() end
		s.live.revenue, s.live.users = 2, 300
		ui.push(); settle(); update(2)
		v = GuideController.view()
		check("A4 first revenue with the Menu open: step 5 income, but no burst yet", v and v.sub == "income" and bursts == 0, tostring(bursts))
		tick(125)
		check("A4 ... and no auto-done while the card is hidden (120 s timer not started)", lastOp("done") == nil)
		Computer.close(); settle(0.5)
		update(2)
		check("A4 Menu closed: the 'First income!' burst plays once, on screen", bursts == 1 and not Computer.isOpen(), tostring(bursts))
		update(2)
		check("A4 the burst never repeats", bursts == 1)
		HUD.celebrate = origCelebrate
		v = GuideController.view()
		check("first revenue -> 5 income 'First income!' + op step n = 6 (funnel 7)", v.sub == "income" and v.title == "First income!" and table.find(stepOps(), 6) ~= nil, v.sub)
		local gotIt = GuideController.resolve("guide_action") or HUD.guideTargets().action
		check("GOT IT in the row", gotIt and gotIt.Text == "GOT IT", gotIt and gotIt.Text)
		toasts = {}
		tap(gotIt, false)
		ui.push(); settle(); update(2)
		check("GOT IT -> op done, guide finished on the server", lastOp("done") ~= nil and d.empire.tutorial.done == true)
		local stepCaption = pg:FindFirstChild("Caption", true)
		check("hand-off: caption GUIDE COMPLETE ✓", stepCaption and stepCaption.Text == "GUIDE COMPLETE ✓", stepCaption and stepCaption.Text)
		local handoff = false
		for _, t in toasts do if t.text == "New in your Menu: Market, Clients, Team" then handoff = true end end
		check("hand-off toast 'New in your Menu: Market, Clients, Team'", handoff)
		check("after the guide: no ring, no chip", Guide.ringTarget() == nil and Guide.chipText() == nil)

		---------------------------------------------------------------------------------------------- tips (A12)
		d.empire.employees = { researcher = 1, engineer = 0, curator = 0, marketer = 0 }
		ui.push(); settle()
		tick(20)
		local tipRow = pg:FindFirstChild("TipRow", true)
		check("A12 no tip in the first 60 s after the guide", tipRow and not tipRow.Visible)
		tick(45)
		local tipLabel = pg:FindFirstChild("Tip", true)
		check("A12 one-time tip 'HR hires for you. Meet them in Team.' with SHOW ME (card tap)", tipRow.Visible and tipLabel and string.find(tipLabel.Text, "HR hires for you. Meet them in Team.", 1, true) and string.find(tipLabel.Text, "SHOW ME", 1, true), tipLabel and tipLabel.Text)
		check("A12 the tip key is saved (op tip team)", (function() for _, o in ops do if o.op == "tip" and o.key == "team" then return true end end return false end)())
		M.fire(pg:FindFirstChild("NextGoal", true).Activated, {}, 1); settle(0.6)
		check("A12 tapping the card runs SHOW ME: Team → Staff", Computer.isOpen() and Computer.current() == "team.staff", Computer.current())
		Computer.close(); settle(0.5)
		tick(12)
		check("A12 the tip is gone after its 10 s and never comes back", not tipRow.Visible and d.empire.tutorial.tips.team == true)

		---------------------------------------------------------------------------------------------- redirects (A8)
		s, d = fresh()
		update(2)
		Computer.toggle(); settle(0.6)
		check("A8 step 1: the Menu button (Computer.toggle) opens the Studio design view", Computer.isOpen() and Studio.mode == "design", Studio.mode)
		Computer.close(); settle(0.5)
		check("closing the Menu closes the Studio", Studio.mode == "closed")
		Computer.open("empire"); settle(0.6)
		check("A8 step 1: founder computer (OWNER_COMPUTER app=empire) -> Studio design", Studio.mode == "design")
		Computer.close(); settle(0.5)
		M.fire(UIS.InputBegan, { KeyCode = Enum.KeyCode.C, UserInputType = Enum.UserInputType.Keyboard }, false)
		settle(0.6)
		check("A8 step 1: the C key -> Studio design", Computer.isOpen() and Studio.mode == "design", Studio.mode)
		Computer.close(); settle(0.5)
		local l1 = cas.AIEmpireMenu
		check("B6 L1 toggles the Menu: ButtonL1 at ContextActionPriority.Medium, no touch button", l1 and l1.priority == Enum.ContextActionPriority.Medium.Value and table.find(l1.keys, Enum.KeyCode.ButtonL1) ~= nil and l1.touch == false, l1 and l1.priority)
		if l1 then l1.fn("AIEmpireMenu", Enum.UserInputState.Begin, {}) end
		settle(0.6)
		check("L1 during step 1 -> Studio design (same redirect)", Computer.isOpen() and Studio.mode == "design")
		Computer.close(); settle(0.5)
		Computer.open("market"); settle(0.6)
		check("a deep link (market) is never redirected and opens the locked page", Computer.current() == "market.myais" and Studio.mode == "closed", Computer.current())
		check("deep link marks Market unlocked for the session", Computer.isUnlocked("market"))
		Computer.close(); settle(0.5)
		Computer.routeTo("page:home.today"); settle(0.6); update(2)
		local homeGuide = GuideController.resolve("menu_lab")
		check("T6 menu_lab on Home -> the guide card's OPEN LAB ›", homeGuide and homeGuide == HomeApp.guideButton() and homeGuide.Text == "OPEN LAB ›", homeGuide and homeGuide.Text)
		v = GuideController.view()
		check("Home guide card line 'I picked a good first model for you.' (no world hints in the Menu)", v.text == TM.TEXTS.menuLab, v.text)
		local rail = Computer.railButton("clients")
		tap(rail, false); update(1)
		check("locked Clients tap -> locked card; the ring hides under it", Computer.lockedShown() and GuideController.resolve("menu_lab") == nil)
		local goLab = pg:FindFirstChild("GoToLab", true)
		tap(goLab, false); update(2)
		check("GO TO LAB › -> Lab → Models; T6 menu_lab -> DesignNewModel", Computer.current() == "lab.models" and GuideController.resolve("menu_lab") and GuideController.resolve("menu_lab").Name == "DesignNewModel")
		Computer.close(); settle(0.5)
		-- after step 2 the founder computer opens Home again
		d.training = { modelId = "x", workTotal = 100, workDone = 10, cost = 1280, eventRolled = true, epoch = 1, loss = {}, log = {} }
		ui.push(); settle(); update(1)
		Computer.open("empire"); settle(0.6)
		check("A8 after step 2 (training): the founder computer opens Home", Computer.current() == "home.today" and Studio.mode == "closed", Computer.current())
		Computer.close(); settle(0.5)
		d.training = nil
		ui.push(); settle(); update(1)

		---------------------------------------------------------------------------------------------- skip / restart (A12)
		local skip = HUD.guideTargets().skip
		check("Skip in the card: 96 x 68 hit box (44 pt on phones), Selectable", skip and skip.Visible and skip.Size.X.Offset >= 68 and skip.Size.Y.Offset >= 68 and skip.Selectable)
		tap(skip, false); ui.push(); settle(); update(2)
		check("Skip -> op skip, guide off, normal goal card", lastOp("skip") ~= nil and d.empire.tutorial.skipped == true and GuideController.view() == nil and pg:FindFirstChild("GuideBody", true).Visible == false)
		check("after a skip: no ring, no chip, no redirect", Guide.ringTarget() == nil and Guide.chipText() == nil)
		Computer.open("empire"); settle(0.6)
		check("after a skip the founder computer opens Home", Computer.current() == "home.today" and Studio.mode == "closed")
		Computer.routeTo("page:home.goals"); settle(0.6)
		local restart = pg:FindFirstChild("RestartGuide", true)
		check("Home → Goals 'Guide & tips' card: Restart first steps visible before the first launch", restart and visible(restart))
		tap(restart, false); ui.push(); settle(); update(2)
		check("Restart -> op restart, guide active again at step 1", lastOp("restart") ~= nil and TM.active(d) and GuideController.view() and GuideController.view().step == 1)
		Computer.close(); settle(0.5)

		---------------------------------------------------------------------------------------------- lab requests
		toasts = {}
		M.fire(game.ReplicatedStorage.Remotes.Notify.OnClientEvent, "TRAINING_COMPLETE", { modelId = "x", overall = 61.5, expected = 60 })
		settle()
		local tc = nil
		for _, t in toasts do if string.find(t.text, "Training complete", 1, true) then tc = t.text end end
		check("lab #1: TRAINING_COMPLETE toast without the score (no digits)", tc ~= nil and string.find(tc, "%d") == nil, tc)
		local js = {}
		for _, st in JourneyMath.STEPS do js[st.id] = st end
		check("lab #2: JourneyMath design/train open the Studio (section design / train)", js.design.section == "design" and js.train.section == "train")
		local gv = GoalText.describe(State.snapshot, nil)
		check("lab #2 / A3: fresh goal 'Train your first AI' -> lab/design, progress 'Open the Lab' (no Step 1 of 7)", gv.app == "lab" and gv.section == "design" and gv.progress == "Open the Lab", gv.app .. "/" .. tostring(gv.section) .. " " .. gv.progress)
		-- lab #5: Toast.hold queues info/success (dedupe, max 3), errors show at once, hold(false) flushes
		local holder = pg:FindFirstChild("Toasts", true)
		local function toastTexts()
			local out = {}
			for _, x in holder:GetDescendants() do if x:IsA("TextLabel") and x.Text ~= "" and x.TextTransparency < 1 then table.insert(out, x.Text) end end
			return out
		end
		settle(6)
		Toast.hold(true)
		origShow("info", "held A"); origShow("info", "held A"); origShow("success", "held B"); origShow("info", "held C"); origShow("info", "held D")
		local during = toastTexts()
		check("lab #5: info/success wait while held", not table.find(during, "held A") and not table.find(during, "held D"), table.concat(during, "|"))
		origShow("error", "error now")
		check("lab #5: errors show while held", table.find(toastTexts(), "error now") ~= nil)
		check("lab #5: Toast.isHeld()", Toast.isHeld() == true)
		Toast.hold(false)
		local seen = {}
		for _ = 1, 30 do settle(0.5); for _, t in toastTexts() do seen[t] = true end end
		check("lab #5: hold(false) flushes the queue (max 3, oldest dropped, deduped)", seen["held B"] and seen["held C"] and seen["held D"] and not seen["held A"], (seen["held A"] and "A " or "") .. (seen["held B"] and "B " or "") .. (seen["held C"] and "C " or "") .. (seen["held D"] and "D" or ""))
		check("Toast on phones: compact boost (15 px x 0.432 x 1.9 >= 12 pt)", holder:FindFirstChild("CompactBoost") and holder.CompactBoost.Scale >= 1.85)

		---------------------------------------------------------------------------------------------- Intro (A7)
		local created = nil
		ui.binds.CreateCompany = function(_, p) created = p; return { ok = true } end
		d.company = nil
		ui.push(); settle()
		local Intro = M.require(Client.UI.Screens.Intro)
		local introRoot = pg:FindFirstChild("AIEmpire_Intro"):FindFirstChild("Root")
		Intro.mount(introRoot, { onFinish = function() end, onReopen = function() end })
		ui.push(); settle()
		local nameBox = introRoot:FindFirstChild("NameBox", true)
		local ideas = CompanyConfig.COMPANY_NAME_IDEAS
		check("A7 Intro line 'You start in a garage with $10,000. Build the biggest AI company.'", Intro.LINE == "You start in a garage with $10,000. Build the biggest AI company.", Intro.LINE)
		check("A7 name box prefilled with a name idea (8 fictional names)", nameBox and table.find(ideas, nameBox.Text) ~= nil and #ideas == 8, nameBox and nameBox.Text)
		local before = nameBox.Text
		tap(introRoot:FindFirstChild("Dice", true), false)
		check("A7 the dice rolls another idea", nameBox.Text ~= before and table.find(ideas, nameBox.Text) ~= nil, nameBox.Text)
		local panelC = introRoot:FindFirstChild("CustomizePanel", true)
		check("A7 Customize is closed by default", panelC and not panelC.Visible)
		tap(introRoot:FindFirstChild("Customize", true), false)
		check("A7 Customize (optional) › opens logo, colour, specialization", panelC.Visible)
		nameBox.Text = "Kite Labs"
		settle()
		tap(introRoot:FindFirstChild("Start", true), false)
		check("A7 START (1 tap) -> CreateCompany with the name and the defaults LOGOS[1] / COLORS[1] / general", created and created.name == "Kite Labs" and created.logo == CompanyConfig.LOGOS[1] and created.color == CompanyConfig.COLORS[1].id and created.spec == CompanyConfig.SPECIALIZATIONS[1].id, created and created.name)
	else
		---------------------------------------------------------------------------------------------- state "menu"
		local ui = setupApps(M, GEN, "mid", DESK[1], DESK[2], DESK[3], {})
		local pg = ui.playerGui
		local s = ui.session
		local d = s.data
		local e = d.empire
		local Template = M.require(game.ServerScriptService.Server.Lib.Template)
		local TM = M.require(RS.Shared.TutorialMath)
		local EmpireConfig = M.require(RS.Shared.Config.EmpireConfig)
		local Computer = ui.Computer
		local HUD = ui.HUD
		local HomeApp = M.require(Client.UI.Apps.HomeApp)
		local State = M.require(Client.Controllers.StateController)
		local ops = {}
		local origEA = ui.binds.EmpireAction
		ui.binds.EmpireAction = function(sess, p)
			if typeof(p) == "table" and p.action == "tutorial" then table.insert(ops, table.clone(p)) end
			return origEA(sess, p)
		end
		-- a save that launched before the guide existed: the real cleaner marks it done and fills `seen`
		e.tutorial = { v = 1, step = 0, done = false, skipped = false, tipsOff = false, seen = {}, tips = {} }
		Template.cleanTutorial(d)
		ui.push(); settle()
		local function visible(inst)
			local x = inst
			while x and x ~= pg do
				if (x:IsA("GuiObject") and not x.Visible) or (x:IsA("ScreenGui") and not x.Enabled) then return false end
				x = x.Parent
			end
			return x == pg
		end
		local function texts(root)
			local out = {}
			for _, x in (root or pg):GetDescendants() do
				if (x:IsA("TextLabel") or x:IsA("TextButton")) and x.Text ~= "" and visible(x) then table.insert(out, x.Text) end
			end
			return out
		end
		local function has(list, needle)
			for _, t in list do if string.find(t, needle, 1, true) then return t end end
			return nil
		end

		---------------------------------------------------------------------------------------------- B5 NEW badges (first, before any page was opened this session)
		check("migrated save: no NEW pill anywhere (seen filled by the cleaner)", (function()
			for _, x in pg:GetDescendants() do if x.Name == "NewPill" and visible(x) then return false end end
			return true
		end)())
		-- NEW badges right after the guide (done, nothing seen yet): pills on the open entries, never on Shop
		e.tutorial.seen = {}
		ui.push(); settle()
		Computer.routeTo("page:home.today"); settle(0.5)
		local function pill(entry)
			local b = Computer.railButton(entry)
			local p = b and b:FindFirstChild("NewPill", true)
			return p ~= nil and p.Visible
		end
		check("B5 NEW pills on Market, Clients, Team after the guide", pill("market") and pill("clients") and pill("team"))
		check("B5 the Shop never gets a NEW badge", not pill("shop"))
		ops = {}
		Computer.routeTo("page:market.projects"); settle(2)
		local seenOps = {}
		for _, o in ops do if o.op == "seen" then table.insert(seenOps, o) end end
		local seenKeys = {}
		for _, o in seenOps do for _, k in o.keys do seenKeys[k] = true end end
		check("opening Market → Projects sends op seen with market + market.projects (<= 8 keys per call)", seenKeys.market and seenKeys["market.projects"] and (function()
			for _, o in seenOps do if #o.keys > 8 then return false end end
			return #seenOps >= 1
		end)())
		ui.push(); settle(0.5)
		check("the pill disappears once seen", not pill("market"))
		-- during the guide no NEW pill shows at all
		e.tutorial.done = false
		ui.push(); settle(0.5)
		check("B5 NEW pills are suppressed while the guide is active", not pill("clients") and not pill("team") and not pill("home"))
		e.tutorial.done = true
		Computer.close(); settle(0.4)


		---------------------------------------------------------------------------------------------- T11 route table
		local B9 = {
			{ "empire", nil, "home.today" }, { "empire", "overview", "home.today" }, { "empire", "clients", "clients.clients" },
			{ "empire", "contracts", "clients.clients" }, { "empire", "money", "home.money" }, { "empire", "team", "team.staff" },
			{ "empire", "research", "lab.research" }, { "empire", "milestones", "home.goals" }, { "empire", "office", "team.office" },
			{ "empire", "settings", "team.settings" }, { "empire", "board", "market.leaderboard" },
			{ "lab", nil, "lab.models" }, { "lab", "design", "lab.models", "design" }, { "lab", "train", "lab.models", "train" },
			{ "lab", "evaluation", "lab.models", "evaluation" }, { "lab", "release", "lab.models", "release" },
			{ "data", nil, "lab.data" }, { "compute", nil, "lab.gpus" }, { "market", nil, "market.myais" }, { "studio", nil, "market.projects" },
			{ "arena", nil, "lab.arena" }, { "campus", nil, "team.campus" }, { "campus", "access", "team.campus" }, { "campus", "shops", "team.campus" },
			{ "campus", "fleet", "team.fleet" }, { "campus", "building", "team.office" }, { "shop", nil, "shop.home" }, -- shop package: 5 native Shop tabs, Home first
			{ "nonsense", nil, "home.today" }, { "empire", "nonsense", "home.today" },
		}
		local wrong = {}
		for _, row in B9 do
			local key, labSection = Computer.route(row[1], row[2])
			if key ~= row[3] or labSection ~= row[4] then table.insert(wrong, `{row[1]}/{tostring(row[2])} -> {key}/{tostring(labSection)}`) end
		end
		check("T11 B9 route table: every old (app, section) lands on its new page; unknown -> Home", #wrong == 0, table.concat(wrong, "; "))
		check("T11 routes.py ran (tests/menu/.routes_found.luau)", okFound and typeof(found) == "table" and #found >= 15, okFound and #found)
		local known = { empire = true, lab = true, data = true, compute = true, market = true, studio = true, arena = true, campus = true, shop = true, home = true, clients = true, team = true }
		local SECTIONS = {
			empire = { overview = true, clients = true, contracts = true, money = true, team = true, research = true, milestones = true, office = true, settings = true, board = true },
			lab = { design = true, train = true, evaluation = true, release = true, research = true, data = true, gpus = true, arena = true },
			market = { myais = true, lines = true, leaderboard = true, projects = true, access = true, receipts = true },
			campus = { access = true, shops = true, fleet = true, building = true },
		}
		local badPairs = {}
		for _, f in (if okFound then found else {}) do
			local key = Computer.route(f.app, f.section)
			local okPair = known[f.app] and Computer.PAGES[key] ~= nil
			if okPair and f.section and SECTIONS[f.app] and not SECTIONS[f.app][f.section] and not (f.app == "compute") then okPair = false end
			if not okPair then table.insert(badPairs, `{f.app}/{tostring(f.section)} ({f.where}) -> {key}`) end
		end
		check(`T11 every grepped (app, section) pair ({if okFound then #found else 0}) lands on an existing page`, okFound and #badPairs == 0, table.concat(badPairs, "; "))

		-- every page opens, and ‹ / B leads to the entry default, Home, then closes (never a hidden selection)
		local backBad = {}
		for key in Computer.PAGES do
			Computer.routeTo("page:" .. key); settle(0.4)
			if Computer.current() ~= key or not visible(Computer.pageFrame(key)) then table.insert(backBad, key .. " did not open") end
			-- expected: the entry's default tab (if not there), then Home → Today (if another entry), then closed
			local entryId = string.match(key, "^(%w+)")
			local expect = {}
			for _, en in Computer.ENTRIES do
				if en.id == entryId then
					local default = en.id .. "." .. en.tabs[1].id
					if key ~= default then table.insert(expect, default) end
				end
			end
			if entryId ~= "home" then table.insert(expect, "home.today") end
			local got = {}
			local steps = 0
			while Computer.isOpen() and steps < 5 do
				Computer.back(); steps += 1; settle(0.3)
				table.insert(got, if Computer.isOpen() then Computer.current() else "closed")
			end
			table.insert(expect, "closed")
			if table.concat(got, ">") ~= table.concat(expect, ">") then table.insert(backBad, key .. ": " .. table.concat(got, ">") .. " (want " .. table.concat(expect, ">") .. ")") end
			local sel = G.game and nil
			sel = game:GetService("GuiService").SelectedObject
			if sel and pg:FindFirstChild("Computer", true) and sel:IsDescendantOf(pg:FindFirstChild("Computer", true)) then table.insert(backBad, key .. " left a selection") end
		end
		check("T11 back rule: from every page ‹ goes to the entry's default tab, then Home, then closes", #backBad == 0, table.concat(backBad, "; "))
		Computer.open("lab", "train"); settle(0.5)
		check("Computer.open/close/toggle/isOpen/show keep working (B12)", Computer.isOpen() and Computer.current() == "lab.models")
		Computer.show("market", "lines"); settle(0.3)
		check("Computer.show(app, section) switches pages (B12)", Computer.current() == "market.lines")
		Computer.toggle(); settle(0.5)
		check("Computer.toggle closes", not Computer.isOpen())
		check("root frame named Computer (Model Studio host, B12)", pg:FindFirstChild("Computer", true) ~= nil and pg:FindFirstChild("Computer", true):FindFirstChild("Menu") ~= nil)

		-- no Menu-reachable feature of today disappears (Campus, Research + API, Overview chart/cycle/daily)
		Computer.routeTo("page:team.campus"); settle(0.6)
		local t = texts(Computer.pageFrame("team.campus"))
		check("T11 Team → Campus: 'Cards & guests' + 'Stores & snacks' on one page", has(t, "Cards & guests") and has(t, "Stores & snacks"), #t)
		Computer.routeTo("page:lab.research"); settle(0.6)
		t = texts(Computer.pageFrame("lab.research"))
		check("T11 Lab → Research: research projects + 'Your API subscription' + 'Provider exchange'", has(t, "Parallel Training") and has(t, "API subscription") and has(t, "Provider exchange"), has(t, "API") or #t)
		Computer.routeTo("page:home.money"); settle(0.6)
		t = texts(Computer.pageFrame("home.money"))
		check("T11 Home → Money: profit chart ('How the business is doing') + 'Market cycle' + metrics", has(t, "How the business is doing") and has(t, "Market cycle") and has(t, "Profit per game day"))
		Computer.routeTo("page:market.leaderboard"); settle(0.6)
		t = texts(Computer.pageFrame("market.leaderboard"))
		check("T11 Market → Leaderboard: Intelligence leaderboard + Company rankings", has(t, "Intelligence leaderboard") and has(t, "Company rankings"))
		Computer.routeTo("page:team.office"); settle(0.6)
		t = texts(Computer.pageFrame("team.office"))
		check("T11 Team → Office: office upgrade + the campus/building cards (building name, 'Getting around')", has(t, "Getting around") ~= nil and has(t, EmpireConfig.OFFICES[e.office].name) ~= nil)
		Computer.routeTo("page:clients.receipts"); settle(0.6)
		t = texts(Computer.pageFrame("clients.receipts"))
		check("T11 Clients → Receipts: 'Business clients · receipts'", has(t, "Business clients") ~= nil)
		e.daily = nil
		ui.push()
		Computer.routeTo("page:home.today"); settle(0.6)
		local daily = pg:FindFirstChild("Daily", true)
		check("T11 the Overview's daily grant became the Home live strip's DAILY button", daily and visible(daily) and string.find(daily.Text, "DAILY +", 1, true), daily and daily.Text)
		local liveStrip = pg:FindFirstChild("LiveStrip", true)
		check("Home live strip: CASH, NET, USERS, LIVE, TRAINING", liveStrip and liveStrip:FindFirstChild("Value_users", true) and liveStrip:FindFirstChild("Value_training", true))
		Computer.close(); settle(0.4)

		---------------------------------------------------------------------------------------------- B5 unlock waves, locked card, NEW badges
		local released, trained = d.stats.modelsReleased, d.stats.modelsTrained
		d.stats.modelsReleased = 0
		e.contractsCompleted = 0
		ui.push(); settle()
		check("B5 before a launch: Market, Clients, Team, Shop locked; Lab → Research open (staff >= 1)", not Computer.isUnlocked("market") and not Computer.isUnlocked("clients") and not Computer.isUnlocked("team") and not Computer.isUnlocked("shop.home") and Computer.isUnlocked("lab.research"))
		Computer.routeTo("page:home.today"); settle(0.4)
		M.fire(Computer.railButton("team").Activated, {}, 1); settle(0.4)
		local lockedTitle = nil
		for _, x in pg:GetDescendants() do if x:IsA("TextLabel") and string.find(x.Text, "opens after your first launch", 1, true) and visible(x) then lockedTitle = x.Text end end
		check("B5 locked entry tap -> 'Team opens after your first launch.'", lockedTitle == "Team opens after your first launch.", lockedTitle)
		check("locked entry stays visible at 40 % (label transparency 0.6, no padlock)", (function()
			local label = Computer.railButton("team"):FindFirstChild("Label")
			return label and math.abs(label.TextTransparency - 0.6) < 1e-6
		end)())
		-- fix round 1 (review): B / ‹ first closes the locked card (the page behind stays); Computer.close() hides it too
		local pageBefore = Computer.current()
		Computer.back(); settle(0.3)
		check("B6 B / ‹ with the locked card shown: closes the card, stays on the page", not Computer.lockedShown() and Computer.isOpen() and Computer.current() == pageBefore, Computer.current())
		M.fire(Computer.railButton("team").Activated, {}, 1); settle(0.4)
		Computer.close(); settle(0.4)
		Computer.open(); settle(0.4)
		check("B6 the locked card never reappears on the next open", not Computer.lockedShown())
		Computer.close(); settle(0.4)
		-- gamepad: a deep link from outside the Menu (HUD Shop button, Home card) gives the new page the selection
		preferred = Enum.PreferredInput.Gamepad
		local hudButton = pg:FindFirstChild("OpenCompany", true)
		GS.SelectedObject = hudButton
		Computer.open("empire", "team"); settle(0.5)
		local sel = GS.SelectedObject
		check("B6 gamepad deep link: the new page's first button takes the selection (not the hidden HUD button)", sel ~= nil and sel ~= hudButton and sel:IsDescendantOf(Computer.pageFrame("team.staff")), sel and sel:GetFullName())
		local rail = Computer.railButton("market")
		GS.SelectedObject = rail
		Computer.routeTo("page:team.office"); settle(0.5)
		check("B6 a selection on the rail stays where the player put it", GS.SelectedObject == rail, GS.SelectedObject and GS.SelectedObject.Name)
		Computer.close(); settle(0.4)
		preferred = Enum.PreferredInput.Touch
		GS.SelectedObject = nil
		Computer.open("empire", "team"); settle(0.5)
		check("B5 a deep link to a locked page opens it and unlocks it for the session", Computer.current() == "team.staff" and Computer.isUnlocked("team"))
		Computer.close(); settle(0.4)
		d.stats.modelsReleased = released
		e.contractsCompleted = 7
		---------------------------------------------------------------------------------------------- B11 / T12 Shop button and Shop page
		ui.push(); settle(); frames(2)
		local shopButton = pg:FindFirstChild("ShopButton", true)
		check("B11 live server with every id 0: no HUD Shop button", shopButton and not shopButton.Visible)
		studio = true
		ui.push(); settle(); frames(2)
		check("B11 Studio owner preview after the first launch, guide done: HUD Shop button", shopButton.Visible)
		e.tutorial.done = false
		ui.push(); settle(); frames(2)
		check("B11 never during the guide (Studio too)", not shopButton.Visible)
		e.tutorial.done = true
		local savedRel = d.stats.modelsReleased
		d.stats.modelsReleased = 0
		ui.push(); settle(); frames(2)
		check("B11 never before the first launch", not shopButton.Visible)
		d.stats.modelsReleased = savedRel
		studio = false
		ui.push(); settle()
		Computer.open("shop"); settle(0.6)
		local soon = pg:FindFirstChild("ComingSoon", true)
		check("T12 live with every id 0 -> the Shop page shows 'Shop coming soon' (ComingSoon)", Computer.current() == "shop.home" and soon and visible(soon)) -- shop package: Shop → Home
		Computer.close(); settle(0.4)

		---------------------------------------------------------------------------------------------- T9 Home.cards (pure)
		local function snap(data, live) return { data = data, live = live or { users = 0, revenue = 0, cost = 0, perModel = {} }, serverTime = ui.base, saveEnabled = false } end
		local function newCo()
			local x = Template.new()
			x.company = { name = "Kite Labs", logo = "N", color = "cyan", spec = "general", reputation = 0, foundedAt = 0 }
			return x
		end
		local function noShop(cards)
			for _, c in cards do
				if string.find(string.lower(c.route), "shop", 1, true) or string.find(c.title, "Shop", 1, true) or string.find(c.title, "Robux", 1, true) then return false end
			end
			return true
		end
		local allNoShop = true
		local function cards(data, live, guide, money)
			local out = HomeApp.cards(snap(data, live), { guide = guide, money = money })
			allNoShop = allNoShop and noShop(out)
			return out
		end
		local f = newCo()
		local view1 = TM.step(f, {}, { computerOpen = true, menuHome = true, assistant = "Ada" })
		local c = cards(f, nil, view1)
		check("T9 fresh (guide step 1): guide card first + Collect $1,200, nothing invented", #c == 2 and c[1].kind == "guide" and c[1].caption == "FIRST STEPS · 1/5" and c[1].button == "OPEN LAB ›" and c[1].line == "Ada: I picked a good first model for you." and c[2].title == "Collect $1,200", #c .. " " .. (c[2] and c[2].title or ""))
		local tr = newCo()
		tr.empire.quests.founder = true
		tr.training = { modelId = "m", workTotal = 100, workDone = 30, cost = 1280, eventRolled = false, epoch = 1, loss = {}, log = {} }
		local vt = TM.step(tr, {}, { computerOpen = true, assistant = "Ada", trainingEta = 50 })
		c = cards(tr, nil, vt)
		check("T9 training (guide step 3): guide card 'Your AI is training' with WATCH ›", c[1] and c[1].kind == "guide" and c[1].title == "Your AI is training" and c[1].button == "WATCH ›", c[1] and c[1].title)
		tr.training.event = { id = "data_issue", pending = true, expiresAt = 0 }
		c = cards(tr, nil, TM.step(tr, {}, { computerOpen = true, assistant = "Ada" }))
		check("T9 decision: urgent 'Decide: …' first", c[1] and c[1].kind == "urgent" and string.sub(c[1].title, 1, 8) == "Decide: " and c[1].route == "lab_train", c[1] and c[1].title)
		local tn = newCo()
		tn.empire.quests.founder = true
		tn.models.m1 = { id = "m1", name = "Nova", version = 1, sizeId = "s100m", focusId = "creative", status = "trained", stats = {}, overall = 40, createdAt = 0, trainedAt = 0 }
		tn.modelOrder = { "m1" }
		tn.stats.modelsTrained = 1
		c = cards(tn, nil, nil)
		check("T9 trained, not launched: 'Launch Nova v1' (LAUNCH ›)", c[1] and c[1].title == "Launch Nova v1" and c[1].route == "lab_release" and c[1].modelId == "m1", c[1] and c[1].title)
		c = cards(tn, nil, TM.step(tn, {}, { computerOpen = true, assistant = "Ada" }))
		check("T9 guide step 4 + trained model: one card (guide and Launch dedupe)", c[1].kind == "guide" and (c[2] == nil or c[2].route ~= "lab_release"), #c)
		local cl = newCo()
		cl.empire.tutorial.done = true
		c = cards(cl, nil, nil)
		check("T9 claimable goals: 'Collect $1,200' (claims in place) with 'Goal done: …'", (function() for _, x in c do if x.route == "collect" and x.title == "Collect $1,200" and string.find(x.line, "Goal done:", 1, true) then return true end end return false end)())
		local neg = newCo()
		neg.empire.tutorial.done = true
		neg.money = -500
		c = cards(neg, nil, nil, -500)
		check("T9 cash < 0: urgent 'Cash below $0 · lower costs' -> Team → Settings first", c[1] and c[1].title == "Cash below $0 · lower costs" and c[1].route == "page:team.settings", c[1] and c[1].title)
		local of = newCo()
		of.empire.tutorial.done = true
		of.empire.contractsCompleted = 1
		of.money = 30000
		c = cards(of, nil, nil, 30000)
		check("T9 office affordable and allowed: 'Move to Founder Headquarters'", (function() for _, x in c do if x.title == "Move to " .. EmpireConfig.OFFICES[2].name and x.route == "page:team.office" then return true end end return false end)())
		of.empire.contractsCompleted = 0
		c = cards(of, nil, nil, 30000)
		check("T9 garage without the first client: no move card", (function() for _, x in c do if string.sub(x.title, 1, 8) == "Move to " then return false end end return true end)())
		local full = HomeApp.cards(State.snapshot, { guide = nil, money = d.money })
		allNoShop = allNoShop and noShop(full)
		local sv = { users = 50000, revenue = 100, cost = 10, capacity = 1000, load = 990, waitlist = 4000, perModel = {} }
		c = cards(d, sv, nil, d.money)
		check("T9 servers >= 95 % with a waitlist: 'Servers full · buy a GPU' -> Lab → GPUs", c[1] and c[1].title == "Servers full · buy a GPU" and c[1].route == "page:lab.gpus", c[1] and c[1].title)
		check("T9 late game: next goal (worded like the HUD) + fillers, max 3", #full >= 2 and #full <= 3 and (function() for _, x in full do if x.kind == "goal" then return true end end return false end)(), #full)
		check("T9/T12 never a Shop card in any case", allNoShop)

		---------------------------------------------------------------------------------------------- T12 no Shop in the guide
		local routes = {}
		local states = {}
		local s1 = newCo(); table.insert(states, s1)
		local s2 = newCo(); s2.empire.tutorial.step = 2; table.insert(states, s2)
		table.insert(states, tr); table.insert(states, tn)
		local s5 = newCo(); s5.stats.modelsReleased = 1; table.insert(states, s5)
		for _, st in states do
			for _, ui2 in { { computerOpen = false }, { computerOpen = true, studioOpen = true, studioMode = "design" }, { computerOpen = true, menuHome = true } } do
				local vv = TM.step(st, { revenue = 1 }, ui2)
				if vv and vv.action then table.insert(routes, vv.action.route) end
			end
		end
		local shopRoute = false
		for _, r in routes do if string.find(r, "shop", 1, true) then shopRoute = true end end
		check("T12 TutorialMath.step never routes to the Shop", not shopRoute and #routes >= 10, #routes)
		check("T12 no tip key for the Shop", table.find(TM.TIP_KEYS, "shop") == nil)
	end
end

setfenv(body, M.envFor(nil))
local ok, res, status = M.runMain(body, { timeout = 900 })
if not ok then failc += 1; print("FAIL  body crashed (" .. tostring(status) .. "): " .. tostring(res)) end
if M.stats.errors > 0 then failc += 1; print("FAIL  background thread errors: " .. M.stats.errors) end
print(string.format("menu_client_%s: %d passed, %d failed", STATE, pass, failc))
