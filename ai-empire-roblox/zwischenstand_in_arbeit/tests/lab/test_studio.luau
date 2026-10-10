--!nocheck
-- Lab package: the Model Studio built by the real client code in the mock, wired to the real server handlers
-- (LAB_SPEC 9.2): lifecycle under the Computer, first-model path and tap budget, tile texts = LabPreview,
-- honesty of the Review, error routing, reveal record rule, Launch Day, gamepad, touch controls, sizes,
-- scale maths, chat buttons, performance.
-- Run: cd tests/lab && ../../tools/luau test_studio.luau -a .gen_lab
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_lab")
local M = require("../../harness/mock")
local setup = require("./lab_setup")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local P = print
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; P("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end
local function note(text) P("NOTE  " .. text) end

local function body()
	local ui = setup(M, GEN, "rich")
	local G = M.G
	local Studio, LabApp, LabState, LP = ui.Studio, ui.LabApp, ui.LabState, ui.LabPreview
	local RS = M.game.ReplicatedStorage
	local Client = M.game.StarterPlayer.StarterPlayerScripts.Client
	local State = M.require(Client.Controllers.StateController)
	local PricingMath = M.require(RS.Shared.PricingMath)
	local ModelConfig = M.require(RS.Shared.Config.ModelConfig)

	local function settle(t) M.settle(t or 0.5) end
	local function visible(inst)
		local x = inst
		while x and x ~= ui.playerGui do
			if (x:IsA("GuiObject") and not x.Visible) or (x:IsA("ScreenGui") and not x.Enabled) then return false end
			x = x.Parent
		end
		return true
	end
	local function studioRoot()
		for _, x in ui.playerGui:GetDescendants() do
			if x.Name == "ModelStudio" then return x end
		end
		return nil
	end
	local function under(rootInst, name)
		if not rootInst then return nil end
		for _, x in rootInst:GetDescendants() do
			if x.Name == name and visible(x) then return x end
		end
		return nil
	end
	local function named(name) return under(studioRoot(), name) end
	local function homeButton(name)
		for _, x in ui.playerGui:GetDescendants() do
			if x.Name == name and x:IsA("GuiButton") and visible(x) then return x end
		end
		return nil
	end
	local function studioTexts()
		local out = {}
		local r = studioRoot()
		if not r then return out end
		for _, x in r:GetDescendants() do
			if (x:IsA("TextLabel") or x:IsA("TextButton")) and visible(x) and x.Text ~= "" then table.insert(out, x.Text) end
		end
		return out
	end
	local function has(list, needle)
		for _, t in list do if string.find(t, needle, 1, true) then return t end end
		return nil
	end
	local clicks = 0
	local function click(b)
		if b then clicks += 1; M.fire(b.Activated); settle(0.6) end
	end
	local function disabled(b) return b ~= nil and b:GetAttribute("Disabled") == true end
	local function view() return Studio.current() end
	local function step() local s = view() and view().state and view().state(); return s end
	local function labelIn(parentName, childPredicate)
		local p = named(parentName)
		if not p then return nil end
		for _, x in p:GetDescendants() do
			if x:IsA("TextLabel") and childPredicate(x) then return x end
		end
		return nil
	end
	-- capture StartTraining payloads at the server handler
	local sent = {}
	local origStart = ui.binds.StartTraining
	ui.binds.StartTraining = function(session, payload) table.insert(sent, payload); return origStart(session, payload) end
	local improveCalls = 0
	local origImprove = ui.binds.ImproveModel
	ui.binds.ImproveModel = function(session, payload) improveCalls += 1; return origImprove(session, payload) end

	------------------------------------------------------------------ 1. lifecycle (rich)
	ui.Computer.open("lab")
	settle()
	LabApp.openSection("design")
	settle()
	local root = studioRoot()
	check("DESIGN opens the Studio", Studio.mode == "design" and root ~= nil and root.Visible)
	check("ModelStudio is a descendant of the frame named Computer (not its own ScreenGui)", root and root:FindFirstAncestor("Computer") ~= nil)
	check("Studio draws above the Computer window (ZIndex 30 > 11)", root and root.ZIndex == 30)
	ui.Computer.close()
	settle(0.5)
	check("Computer.close() closes the Studio", Studio.mode == "closed" and not root.Visible)
	ui.Computer.open("lab"); settle()
	LabApp.openSection("design"); settle()
	ui.Computer.open("market"); settle()
	check("switching to another app closes the Studio", Studio.mode == "closed")
	ui.Computer.open("lab"); settle()
	LabApp.openSection("design"); settle()
	click(named("BackToLab"))
	check("‹ LAB returns to the Lab home", Studio.mode == "closed" and homeButton("DesignNewModel") ~= nil)

	------------------------------------------------------------------ 2. first model: fresh save, 5 taps to a live product
	do
		local s, d = ui.use("fresh")
		ui.Computer.open("lab"); settle()
		clicks = 0
		click(homeButton("DesignNewModel"))
		local stepNo = view().state()
		check("first model opens at step 6 (Review)", Studio.mode == "design" and stepNo == 6, stepNo)
		local t = studioTexts()
		check("first-model hint", has(t, "FIRST MODEL") ~= nil)
		check("fresh: Review shows the data plan", has(t, "2× Web Crawl Chunk + 2× Public Repos") ~= nil and has(t, "4B tokens") ~= nil, has(t, "Data plan"))
		check("fresh: expected panel shows the plan's result ~40.2", named("ExpectedValue") and named("ExpectedValue").Text == "~40.2", named("ExpectedValue") and named("ExpectedValue").Text)
		local primary = named("Primary")
		check("fresh: primary = BUY DATA PLAN · $7,400", primary and primary.Text == "BUY DATA PLAN · $7,400", primary and primary.Text)
		check("fresh: CASH AFTER ALL $3,520", has(t, "CASH AFTER ALL") ~= nil and has(t, "$3,520") ~= nil)
		click(primary)
		ui.push(); settle()
		check("after BUY DATA PLAN: 4B tokens, $4,800", d.data.general and d.data.code and d.money == 4800, d.money)
		primary = named("Primary")
		check("after the plan: START TRAINING · $1,280", primary and primary.Text == "START TRAINING · $1,280", primary and primary.Text)
		click(primary)
		local p = sent[#sent]
		check("START payload: 100M · creative · Standard · Consumer Chat (the bot's first model)", p and p.sizeId == "s100m" and p.focusId == "creative" and p.recipeId == "steady" and p.target == "general" and p.look == nil and typeof(p.name) == "string", p and (p.sizeId .. " " .. p.focusId))
		check("START switches to TRAINING", Studio.mode == "training")
		ui.push(); settle()
		ui.AIModelService.finishNow(s)
		ui.push(); settle(5)
		check("TRAINING_COMPLETE with the Computer open plays the REVEAL", Studio.mode == "reveal")
		local id = d.modelOrder[#d.modelOrder]
		local model = d.models[id]
		check("REVEAL shows model.overall", named("Overall") and named("Overall").Text == string.format("%.1f", model.overall), named("Overall") and named("Overall").Text)
		check("first model: YOUR FIRST MODEL pill", named("RecordPill") and named("RecordPill").Text == "YOUR FIRST MODEL")
		local refine = named("Refine")
		check("REFINE right after training: disabled, 'needs 100M new tokens'", refine and disabled(refine) and string.find(refine.Text, "needs 100M new tokens", 1, true) ~= nil, refine and refine.Text)
		local before = improveCalls
		click(refine)
		clicks -= 1
		check("disabled REFINE sends nothing", improveCalls == before)
		local starsWord = named("StarsWord")
		check("first model in the garage: CHALLENGER with a goal", starsWord and starsWord.Text == "CHALLENGER" and has(studioTexts(), "Next to beat: Vector Lite") ~= nil, starsWord and starsWord.Text)
		click(named("Launch"))
		settle(3); ui.push(); settle(1)
		check("LAUNCH › opens Launch Day with the planned line", Studio.mode == "launch" and view().state().target == "general", view() and view().state and view().state().target)
		click(named("LaunchButton"))
		settle(2); ui.push(); settle()
		check("LAUNCH -> model live in Consumer Chat", model.status == "live" and model.release and model.release.target == "general", model.status)
		check("NOW LIVE stage", Studio.mode == "live")
		check(`tap budget: fresh save -> live in <= 5 taps ({clicks})`, clicks <= 5, clicks)
		-- Design its successor from NOW LIVE
		click(named("DesignSuccessor"))
		check("DESIGN ITS SUCCESSOR opens the Review prefilled (same line, same name)", Studio.mode == "design" and view().state() == 6 and LabState.lineId == "general" and LabState.name == model.name, LabState.name)
	end

	------------------------------------------------------------------ 3. save with data: 4 taps
	do
		local s, d = ui.use("starter")
		ui.Computer.open("lab"); settle()
		clicks = 0
		click(homeButton("DesignNewModel"))
		click(named("Primary")) -- START
		ui.push(); settle()
		ui.AIModelService.finishNow(s)
		ui.push(); settle(5)
		click(named("Launch"))
		settle(3); ui.push(); settle(1)
		click(named("LaunchButton"))
		settle(2); ui.push(); settle()
		local live = 0
		for _, m in d.models do if m.status == "live" then live += 1 end end
		check(`tap budget: save with data -> live in <= 4 taps ({clicks})`, live == 1 and clicks <= 4, `{live} {clicks}`)
	end

	------------------------------------------------------------------ 4. rich: tiles = LabPreview, honest Review, 3-tap returning path
	do
		local s, d = ui.use("rich")
		State.setSelection("s1b", "coding")
		State.setRecipe("steady")
		LabState.lineId = "developers"
		LabState.name = "Sage"
		ui.Computer.open("lab"); settle()
		clicks = 0
		click(homeButton("DesignNewModel"))
		check("returning player opens at step 1", view().state() == 1)
		local chip2 = named("Chip_2")
		click(chip2)
		local d3 = labelIn("Size_s3b", function(x) return string.find(x.Text, "−", 1, true) == 1 end)
		local d100 = labelIn("Size_s100m", function(x) return string.find(x.Text, "−", 1, true) == 1 end)
		local deltas = LP.deltas(d, { sizeId = "s1b", focusId = "coding", recipeId = "steady" }, "sizeId", d.money)
		check("Size_s3b delta = LabPreview (−2.8)", d3 and d3.Text == "−2.8" and math.abs(deltas.s3b.dOverall + 2.8) < 1e-9, d3 and d3.Text)
		check("Size_s100m delta = LabPreview (−15.1)", d100 and d100.Text == "−15.1", d100 and d100.Text)
		check("Size_s1b shows 'picked'", labelIn("Size_s1b", function(x) return x.Text == "picked" end) ~= nil)
		check("BEST I CAN AFFORD shows 1B Deep · $16,896", has(studioTexts(), "1B Deep · $16,896") ~= nil, has(studioTexts(), "Deep"))
		clicks = 1
		click(named("Chip_6"))
		local exp = named("ExpectedValue") and named("ExpectedValue").Text
		local primary = named("Primary")
		check("rich Review: START TRAINING · $7,040", primary and primary.Text == "START TRAINING · $7,040", primary and primary.Text)
		check("rich Review lines: rank #1 of 5 for Developers, beats Coder v2", has(studioTexts(), "#1 of 5") ~= nil and has(studioTexts(), "beats Coder v2") ~= nil)
		click(primary)
		local p = sent[#sent]
		check("returning path DESIGN · 6 Review · START = 3 taps with the prefilled plan", clicks == 3 and p and p.sizeId == "s1b" and p.focusId == "coding" and p.recipeId == "steady" and p.target == "developers" and p.name == "Sage", clicks)
		check("Review '~74.5' == data.training.expected (honesty)", d.training and exp == string.format("~%.1f", d.training.expected), `{exp} vs {d.training and d.training.expected}`)
		ui.push(); settle()
		-- training stage texts: no float artefacts, real loss
		local tt = studioTexts()
		check("no '19.2000' (u/s fix) and no 'fill 200' in any Studio text", has(tt, "19.2000") == nil and has(tt, "fill 200") == nil and has(tt, "19.2 u/s") ~= nil, has(tt, "u/s"))
		check("training shows the planned line chip DEV API", has(tt, "DEV API") ~= nil)
		check("training: expected ~74.5 with one decimal", has(tt, "expected ~74.5") ~= nil, has(tt, "expected"))
		-- reveal record rule with the S1 payload
		ui.AIModelService.finishNow(s)
		ui.push(); settle(5)
		local id = d.modelOrder[#d.modelOrder]
		check("rich reveal: NEW RECORD (overall > previous best 61.6)", Studio.mode == "reveal" and named("RecordPill") and named("RecordPill").Text == "NEW RECORD")
		check("rich reveal: rank line #1 of 5 for Developers", has(studioTexts(), "#1 of 5") ~= nil and named("StarsWord").Text == "MARKET LEADER")
		check("rich reveal: lucky roll from the payload", has(studioTexts(), "lucky roll") ~= nil)
		check("revealed models count as revealed", LabState.wasRevealed(id))
	end

	------------------------------------------------------------------ 5. record rule cases (S1 before / previousBest)
	do
		local s, d = ui.use("rich")
		ui.Computer.open("lab"); settle()
		local m = d.models.study -- trained, overall 61.6
		LabState.storeReveal({ modelId = "study", overall = m.overall, previousBest = 80, expected = m.overall })
		LabApp.openReveal("study"); settle(5)
		check("no NEW RECORD below the previous best", not (named("RecordPill") and named("RecordPill").Visible))
		LabState.storeReveal({ modelId = "study", overall = m.overall, previousBest = 61.0, refinement = true, before = 62.0 })
		LabApp.openReveal("study"); settle(5)
		check("refinement compares with its own old score (61.6 < 62.0: no record)", not (named("RecordPill") and named("RecordPill").Visible) and has(studioTexts(), "from refinement") ~= nil)
		LabState.storeReveal({ modelId = "study", overall = m.overall, previousBest = 61.0, refinement = true, before = 60.0 })
		LabApp.openReveal("study"); settle(5)
		check("refinement above both: NEW RECORD", named("RecordPill") and named("RecordPill").Visible and named("RecordPill").Text == "NEW RECORD")
		LabState.storeReveal({ modelId = "study", overall = m.overall, previousBest = 50, expected = 65.7, eventId = "data_issue", outcome = "ignore" })
		LabApp.openReveal("study"); settle(5)
		check("quality event: 'vs expected · Ignore' instead of a lucky roll", has(studioTexts(), "vs expected · Ignore") ~= nil and has(studioTexts(), "lucky roll") == nil, has(studioTexts(), "expected"))
		-- openRelease of a model not revealed yet shows the reveal first (HUD path)
		LabState.storeReveal({ modelId = "study", overall = m.overall, previousBest = 61.0 })
		Studio.close()
		LabApp.openRelease("study"); settle(2)
		check("openRelease of an unrevealed model plays its reveal first", Studio.mode == "reveal")
		LabApp.openRelease("study"); settle(2)
		check("after the reveal openRelease goes to Launch Day", Studio.mode == "launch")
		LabApp.openSection("evaluation"); settle(1)
		check("EVALUATE shows BENCHMARK REPORT (no record chips)", Studio.mode == "reveal" and has(studioTexts(), "BENCHMARK REPORT") ~= nil and not named("RecordPill"))
	end

	------------------------------------------------------------------ 6. Launch Day: summary on every step, Recommended preselected, one forecast per selection
	do
		local s, d = ui.use("rich")
		ui.Computer.open("lab"); settle()
		local forecasts = 0
		local origProfit = PricingMath.profit
		PricingMath.profit = function(ctx, cand, seconds, pause)
			if seconds == ModelConfig.PRICING.cardSeconds then forecasts += 1 end
			return origProfit(ctx, cand, seconds, pause)
		end
		LabApp.openRelease("study"); settle(3); ui.push(); settle(1)
		for ls = 1, 3 do
			view().setStep(ls); settle(0.3)
			local t = studioTexts()
			check(`Launch Day step {ls}: Recommended price + auto text + forecast + launch total visible`, has(t, "Recommended: $") ~= nil and has(t, "Auto price: the server sets the Recommended price") ~= nil and has(t, "LAUNCH TOTAL") ~= nil and has(t, "users ·") ~= nil, has(t, "Recommended"))
		end
		local st = view().state()
		check("Campaign: Recommended preselected ($5,000 = PricingMath.recommendedMarketing)", st.campaign == "recommended" and st.marketing == 5000, st.campaign .. " " .. st.marketing)
		check("Launch Day preselects Study App (best allowed fit) with Auto price", st.target == "students" and st.auto == true)
		forecasts = 0
		click(named("Campaign_big"))
		settle(2)
		check(`one forecast job per selection (+ the cached no-campaign baseline): {forecasts}`, forecasts >= 1 and forecasts <= 2, forecasts)
		forecasts = 0
		click(named("Campaign_recommended"))
		settle(2)
		check(`a repeated selection reuses the baseline: {forecasts} forecast`, forecasts == 1, forecasts)
		check("campaign line 'campaign adds' uses the baseline", has(studioTexts(), "campaign adds") ~= nil or has(studioTexts(), "After launch:") ~= nil)
		PricingMath.profit = origProfit
		-- Global $250K is above the cash: not selectable
		local global = named("Campaign_global")
		check("Global $250K above the cash: 'Need $250K' and disabled", global and disabled(global) and has(studioTexts(), "Need $250K") ~= nil)
		check("a disabled campaign tile keeps its hidden Text invisible (no doubled 'Global')", global and global.TextTransparency == 1, global and global.TextTransparency)
	end

	------------------------------------------------------------------ 7. error routing
	do
		local s, d = ui.use("rich")
		local TF = M.require(M.game.ServerScriptService.Server.Lib.TextFilter)
		local origF = TF.forBroadcast
		TF.forBroadcast = function(text) return "####" end
		State.setSelection("s100m", "balanced"); State.setRecipe("steady")
		ui.Computer.open("lab"); settle()
		Studio.open("design", { step = 6 }); settle()
		click(named("Primary"))
		check("NAME_FILTERED -> step 5 with the name box", Studio.mode == "design" and view().state() == 5, view().state())
		TF.forBroadcast = origF
		-- VRAM refused by the server (GPUs sold after the Review was drawn): close + Hardware
		Studio.open("design", { step = 6 }); settle()
		d.gpus = { laptop = 1 }
		State.setSelection("s1b", "balanced") -- client still has the old snapshot? push not called: estimate uses the session table directly
		d.gpus = { workstation = 6 }
		Studio.refresh()
		d.gpus = { laptop = 1 } -- the server now has too little VRAM, the button still says START
		click(named("Primary"))
		settle()
		local compute = nil
		for _, x in ui.playerGui:GetDescendants() do if x.Name == "compute" and x:IsA("Frame") then compute = x end end
		check("VRAM from the server -> Studio closed, Computer shows Hardware", Studio.mode == "closed" and compute and compute.Visible, Studio.mode)
	end

	------------------------------------------------------------------ 8. gamepad + touch controls
	do
		local s, d = ui.use("rich")
		local UIS = M.game:GetService("UserInputService")
		local GS = M.game:GetService("GuiService")
		local pad, touch = true, false
		local function patchGet(cls, prop, fn) M.IMPL[cls] = M.IMPL[cls] or { methods = {}, get = {}, set = {}, defaults = {} }; M.IMPL[cls].get[prop] = fn; M.classInfo(cls).get[prop] = fn end
		local function patchMethod(cls, name, fn) M.IMPL[cls] = M.IMPL[cls] or { methods = {}, get = {}, set = {}, defaults = {} }; M.IMPL[cls].methods[name] = fn; M.classInfo(cls).methods[name] = fn end
		patchGet("UserInputService", "GamepadEnabled", function() return pad end)
		patchGet("UserInputService", "TouchEnabled", function() return touch end)
		local bound, unbound = {}, {}
		patchMethod("ContextActionService", "BindActionAtPriority", function(_, name) table.insert(bound, name) end)
		patchMethod("ContextActionService", "UnbindAction", function(_, name) table.insert(unbound, name) end)
		State.setSelection("s1b", "coding"); State.setRecipe("steady")
		LabState.lineId = "developers"
		ui.Computer.open("lab"); settle()
		Studio.open("design", { step = 1 }); settle()
		check("gamepad: step 1 selects the planned line tile", GS.SelectedObject and GS.SelectedObject.Name == "Line_developers", GS.SelectedObject and GS.SelectedObject.Name)
		click(named("Chip_2"))
		check("gamepad: after a step change the selected size tile is selected", GS.SelectedObject and GS.SelectedObject.Name == "Size_s1b", GS.SelectedObject and GS.SelectedObject.Name)
		view().step(1); settle()
		check("gamepad R1 -> step 3, focus tile selected", view().state() == 3 and GS.SelectedObject and GS.SelectedObject.Name == "Focus_coding", GS.SelectedObject and GS.SelectedObject.Name)
		view().step(3); settle()
		check("gamepad on the Review: the primary button is selected", GS.SelectedObject and GS.SelectedObject.Name == "Primary")
		check("ContextActionService bound while open (AIEmpireStudio)", table.find(bound, "AIEmpireStudio") ~= nil)
		Studio.close()
		check("UnbindAction on close", table.find(unbound, "AIEmpireStudio") ~= nil)
		-- touch: TouchControlsEnabled off while open, restored on every close path
		touch, pad = true, false
		GS.TouchControlsEnabled = true
		local writes = 0
		local paths = {
			{ "‹ LAB", function() click(named("BackToLab")) end },
			{ "×", function() click(named("CloseComputer")); settle(0.5) end },
			{ "Computer.close()", function() ui.Computer.close(); settle(0.5) end },
			{ "Computer.open(market)", function() ui.Computer.open("market"); settle() end },
		}
		for _, path in paths do
			ui.Computer.open("lab"); settle()
			Studio.open("design", {}); settle()
			local off = GS.TouchControlsEnabled == false
			path[2]()
			check(`touch: controls off while open, restored by {path[1]}`, off and GS.TouchControlsEnabled == true and Studio.mode == "closed", tostring(GS.TouchControlsEnabled))
		end
		touch = false
		GS.TouchControlsEnabled = true
		local origSet = M.classInfo("GuiService").set.TouchControlsEnabled
		local setter = function(self, st, v) writes += 1; st.props.TouchControlsEnabled = v end
		M.classInfo("GuiService").set.TouchControlsEnabled = setter
		ui.Computer.open("lab"); settle()
		Studio.open("design", {}); settle()
		Studio.close()
		check("no touch screen: TouchControlsEnabled never written", writes == 0, writes)
		M.classInfo("GuiService").set.TouchControlsEnabled = origSet
		pad = false
	end

	------------------------------------------------------------------ 9. sizes: text >= 20 design px (11.96 pt on the phone), taps >= 74 x 74
	do
		local s, d = ui.use("rich")
		ui.Computer.open("lab"); settle()
		local smallest, smallestName = math.huge, ""
		local smallTap, smallTapName = math.huge, ""
		local function scan()
			local r = studioRoot()
			for _, x in r:GetDescendants() do
				if visible(x) then
					if (x:IsA("TextLabel") or x:IsA("TextButton") or x:IsA("TextBox")) and x.Text ~= "" and x.TextTransparency < 1 then
						if x.TextSize < smallest then smallest, smallestName = x.TextSize, x:GetFullName() end
					end
					if x:IsA("GuiButton") and x.Name ~= "SkipCeremony" and x.Name ~= "Breakdown" then
						local sz = x.Size
						local w = if sz.X.Scale == 0 then sz.X.Offset else 999
						local h = if sz.Y.Scale == 0 then sz.Y.Offset else 999
						if math.min(w, h) < smallTap then smallTap, smallTapName = math.min(w, h), x:GetFullName() end
					end
				end
			end
		end
		for stepNo = 1, 6 do Studio.open("design", { step = stepNo }); settle(); scan() end
		State.setSelection("s1b", "coding")
		Studio.open("design", { step = 6 }); settle()
		click(named("Primary")); ui.push(); settle(); scan()
		local t = d.training
		t.eventRolled = true
		t.event = { id = "data_issue", pending = true, expiresAt = G.workspace:GetServerTimeNow() + 20, outcome = nil }
		ui.push(); settle(); scan()
		ui.binds.ResolveEvent(s, { choice = "clean" })
		ui.AIModelService.finishNow(s); ui.push(); settle(5); scan()
		for ls = 1, 3 do LabApp.openRelease(d.modelOrder[#d.modelOrder]); settle(2); view().setStep(ls); settle(); scan() end
		click(named("LaunchButton")); settle(2); ui.push(); settle(); scan()
		check(`every Studio text >= 20 design px (smallest {smallest})`, smallest >= 20, smallestName)
		check(`every Studio button >= 74 design px both ways (smallest {smallTap})`, smallTap >= 74, smallTapName)
		note(string.format("phone pt: smallest text %.2f pt, smallest tap %.1f pt (x 0.598 pt/px)", smallest * 0.598, smallTap * 0.598))
	end

	------------------------------------------------------------------ 10. scale maths (LAB_SPEC 3.2) + Lab home compact tokens
	do
		local s, d = ui.use("rich")
		ui.Computer.open("lab"); settle()
		Studio.open("design", {}); settle()
		local root = studioRoot()
		local host = root.Parent
		local overlayRoot = host.Parent
		local rootScale = overlayRoot:FindFirstChildOfClass("UIScale")
		local function setAbs(inst, v2)
			local st = inst[M.KEY]
			st.props.AbsoluteSize = v2
			M.firePropChanged(inst, st, "AbsoluteSize")
		end
		rootScale.Scale = 0.432
		setAbs(host, G.Vector2.new(750, 311))
		settle(0.2)
		local k = root:FindFirstChildOfClass("UIScale").Scale
		check("phone 844x390 (safe 750x311): Studio scale k = 0.598 / 0.432", math.abs(k - (311 / 520) / 0.432) < 1e-6, k)
		check("phone canvas 1254 x 520, compact", math.abs(Studio.canvas.X - 1254) < 1 and math.abs(Studio.canvas.Y - 520) < 0.5 and Studio.compact, tostring(Studio.canvas))
		rootScale.Scale = math.min(1280 / 1280, 662 / 720)
		setAbs(host, G.Vector2.new(1280, 662))
		settle(0.2)
		check("desktop 1280x720 (safe 1280x662): canvas 1254 x 648, regular", math.abs(Studio.canvas.X - 1254) < 1 and math.abs(Studio.canvas.Y - 648.6) < 1 and not Studio.compact, tostring(Studio.canvas))
		Studio.close()
		-- Lab home compact tokens on the phone: every text >= 28 px (12.1 pt at 0.432)
		rootScale.Scale = 0.432
		local lab = nil
		for _, x in ui.playerGui:GetDescendants() do if x.Name == "lab" and x:IsA("Frame") then lab = x end end
		setAbs(lab, G.Vector2.new(939 * 0.432, 542 * 0.432))
		settle(0.2)
		LabApp.onShow(); settle()
		local home = under(lab, "LabHome")
		local small, smallName = math.huge, ""
		for _, x in home:GetDescendants() do
			if (x:IsA("TextLabel") or x:IsA("TextButton")) and visible(x) and x.Text ~= "" then
				if x.TextSize < small then small, smallName = x.TextSize, x.Text end
			end
		end
		check(`Lab home compact: every text >= 28 px (smallest {small})`, small >= 28, smallName)
		local strings = {}
		for _, x in home:GetDescendants() do if (x:IsA("TextLabel") or x:IsA("TextButton")) and visible(x) then table.insert(strings, x.Text) end end
		for _, needle in { "MODEL LAB", "Product lines · 2 / 3 live at Startup Campus", "1 training slot", "Every stat caps at 99", "Lab level 2 adds +2 to each", "UPGRADE LAB · 364 RP + $15.4K", "REFINE 1/3", "refined 0/3", "DESIGN NEW MODEL", "SUCCESSOR", "Hall of fame" } do
			check("Lab home (compact) shows " .. needle, has(strings, needle) ~= nil)
		end
		rootScale.Scale = 1
		setAbs(lab, G.Vector2.new(939, 542))
		settle(0.2)
	end

	------------------------------------------------------------------ 11. chat buttons (design/requests/phone.md #3)
	do
		local s, d = ui.use("rich")
		local okPhone, Phone = pcall(M.require, Client.Controllers.PhoneController)
		local opened = nil
		if okPhone and typeof(Phone) == "table" then
			Phone.openChat = function(id) opened = id end
		end
		ui.Computer.open("lab"); settle()
		LabApp.onShow(); settle()
		local chats = {}
		for _, x in ui.playerGui:GetDescendants() do if x.Name == "Chat" and x:IsA("TextButton") and visible(x) then table.insert(chats, x) end end
		check("Lab hall of fame: CHAT on released models (live + retired = 3)", #chats == 3, #chats)
		if okPhone then
			click(chats[1])
			check("CHAT opens the phone chat of that model and closes the Computer", opened ~= nil and d.models[opened] and d.models[opened].release ~= nil and not ui.Computer.isOpen(), tostring(opened))
		else
			note("PhoneController does not load in this mock run; click not checked")
		end
		ui.Computer.open("market"); settle(); ui.push(); settle()
		local mchats = {}
		for _, x in ui.playerGui:GetDescendants() do if x.Name == "Chat" and x:IsA("TextButton") and visible(x) then table.insert(mchats, x) end end
		check("Market: CHAT on each live model card (2)", #mchats == 2, #mchats)
		check("Market CHAT text is upper case (never a 'Chat' prefix test collision)", mchats[1] and mchats[1].Text == "CHAT")
		if okPhone then
			opened = nil
			click(mchats[1])
			check("Market CHAT opens the phone chat", opened ~= nil, tostring(opened))
		end
	end

	------------------------------------------------------------------ 13. render-review regressions
	do
		local function hiddenLeaks()
			local bad = {}
			local r = studioRoot()
			if r then
				for _, x in r:GetDescendants() do
					if x:IsA("TextButton") and x:GetAttribute("HiddenText") == true and x.Text ~= "" and x.TextTransparency < 1 then table.insert(bad, x.Name) end
				end
			end
			return bad
		end
		-- garage: SAME AS LAST is disabled (no model yet) and must not draw its hidden Text under its labels
		local s, d = ui.use("starter")
		ui.Computer.open("lab"); settle()
		Studio.open("design", { step = 2 }); settle()
		local last = named("Preset_last")
		check("garage step 2: SAME AS LAST disabled without a model", last and disabled(last))
		check("disabled tiles keep TextTransparency 1 (garage step 2)", #hiddenLeaks() == 0, table.concat(hiddenLeaks(), ","))
		-- step 4: Deep overfits on 4B tokens at 42 % quality -> short honest hint
		view().step(2); settle(0.3)
		check("garage step 4: Deep says 'Too little data' (LabPreview overfit)", labelIn("Recipe_deep", function(x) return x.Text == "Too little data" end) ~= nil
			and LP.estimate(d, { sizeId = State.ui.sizeId, focusId = State.ui.focusId, recipeId = "deep" }, d.money).overfit == true)
		-- Lab home without a live line: short successor texts
		Studio.close(); settle()
		local t = {}
		for _, x in ui.playerGui:GetDescendants() do if x:IsA("TextLabel") and visible(x) then table.insert(t, x.Text) end end
		check("Lab home without a live line: successor tile 'None yet' / 'Launch a model first'", has(t, "None yet") ~= nil and has(t, "Launch a model first") ~= nil)
		-- phone class: the Review's BREAKDOWN opens on a tap and closes again
		s, d = ui.use("rich")
		State.setSelection("s1b", "coding"); State.setRecipe("steady"); LabState.lineId = "developers"
		ui.Computer.open("lab"); settle()
		Studio.open("design", { step = 6 }); settle()
		view().setClass(true); settle(0.2)
		check("phone Review: breakdown hidden until tapped", named("Breakdown") == nil)
		click(named("ReviewLines"))
		local tt = studioTexts()
		check("phone Review: tap opens the breakdown (plan + focus on their own line)", named("Breakdown") ~= nil and has(tt, "Plan ×1.00 (Standard) · focus Coding") ~= nil, has(tt, "Plan"))
		click(named("Breakdown"))
		check("phone Review: tap on the breakdown closes it", named("Breakdown") == nil)
		view().setClass(Studio.compact); settle(0.2)
		check("Review rank line fits: 'Quality rank #1 of 5 · Developers'", has(studioTexts(), "Quality rank <b>#1 of 5</b> · Developers") ~= nil, has(studioTexts(), "rank"))
		-- focus step: the BEST FIT tile drops the (+x) suffix next to the tag
		view().step(-3); settle(0.3)
		local bestTile
		for _, x in (studioRoot() :: any):GetDescendants() do
			if x.Name == "BEST FIT" or (x:IsA("TextLabel") and x.Text == "BEST FIT" and visible(x)) then bestTile = x.Parent end
		end
		local suffix = false
		if bestTile then for _, x in bestTile:GetDescendants() do if x:IsA("TextLabel") and string.find(x.Text, " fit ", 1, true) and string.find(x.Text, "(", 1, true) then suffix = true end end end
		check("focus step: BEST FIT tile line has no '(+x)' under the tag", bestTile ~= nil and not suffix, bestTile and bestTile.Name)
		-- stage 5: 1,184 GB VRAM shows as TB so the badge fits
		s, d = ui.use("hq")
		State.setSelection("s7b", "coding"); State.setRecipe("deep")
		ui.Computer.open("lab"); settle()
		Studio.open("design", { step = 2 }); settle()
		check("hq badge: VRAM 'of 1.2 TB'", has(studioTexts(), "of 1.2 TB") ~= nil, has(studioTexts(), " of "))
		Studio.close(); settle()
	end

	------------------------------------------------------------------ 12. performance (soft)
	do
		local s, d = ui.use("rich")
		ui.Computer.open("lab"); settle()
		Studio.open("design", { step = 2 }); settle()
		local t0 = os.clock()
		for _ = 1, 20 do Studio.refresh() end
		local ms = (os.clock() - t0) / 20 * 1000
		note(string.format("one design refresh (rich, step 2) = %.2f ms in the mock", ms))
		check("design refresh <= 10 ms in the mock (soft; LAB_SPEC target 2 ms in Roblox)", ms <= 10, ms)
	end
end

setfenv(body, M.envFor(nil))
local ok, res = M.runMain(body, { timeout = 900 })
if not ok then failc += 1; P("FAIL  body crashed: " .. tostring(res)) end
if M.stats.errors > 0 then failc += 1; P("FAIL  background errors: " .. M.stats.errors) end
P(string.format("lab_studio: %d passed, %d failed", pass, failc))
