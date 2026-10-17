--!nocheck
-- guiprev scene of the menu package (ONBOARDING_SPEC A + B): the real client UI of tests/apps/ui_setup.luau (HUD,
-- Menu, Toasts, real server handlers) plus the guide layer (Screens/Guide + GuideController) and the Intro.
--   python3 tools/guiprev/guiprev.py --scene tests/menu/scene_menu.luau --gen harness/.gen_menu --no-manifest \
--       --state guide1 --viewport phone --dpr 2 --out out/menu/x.png touch=1
-- states: garage client save mid rich (ui_setup, guide finished) and the guide states (garage company, guide on):
--   guide1   step 1, first contact (greeting, dim, ring, chip), $10,000, founder reward claimable
--   guide1b  step 1 after the dim and the greeting, reward collected ($11,200)
--   guide2   step 2: the Model Studio first-model Review (ring on Primary = BUY DATA PLAN)
--   guide2s  step 2 start: data bought (ring on Primary = START TRAINING)
--   guide3   step 3: training 42 %          guide3d  step 3: a training decision (gold DECIDE ›)
--   guide4   step 4: trained, world          guide4r  step 4 reveal (ring on LAUNCH ›)   guide4l  Launch Day
--   guide5   step 5: first income            handoff  guide done: GUIDE COMPLETE ✓ + hand-off toast
--   intro    the Intro (new company)         introc   the Intro with Customize open
-- extra: app=<Computer.open app> section=<s>, page=<menu page key>, touch=1, locked=<entry> (locked card),
--        settle=<seconds before the dump>, mod=broke|abroad
local P = print -- the real print (inside body the mock's print is quiet)
local M = require("../../harness/mock")
local GuiDump = require("../../tools/guiprev/guidump")
local setup = require("../apps/ui_setup")
local args = { ... }
local GEN = args[1] or "../../harness/.gen_menu"
local STATE = args[2] or "guide1"
local VW, VH = tonumber(args[3]) or 1280, tonumber(args[4]) or 720
local insetList = string.split(args[5] or "58,0,0,0", ",")
local INSETS = { top = tonumber(insetList[1]) or 0, right = tonumber(insetList[2]) or 0, bottom = tonumber(insetList[3]) or 0, left = tonumber(insetList[4]) or 0 }
local FEEDBACK = if args[6] and args[6] ~= "-" then require(args[6]) else nil
local OPT = {}
for i = 7, #args do
	local k, v = string.match(args[i], "^([%w_]+)=(.*)$")
	if k then OPT[k] = v end
end

M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
GuiDump.init(M)

local GUIDE = { guide1 = true, guide1b = true, guide2 = true, guide2s = true, guide3 = true, guide3d = true, guide4 = true, guide4r = true, guide4l = true, guide5 = true, handoff = true }

local function body()
	local base = if GUIDE[STATE] or STATE == "intro" or STATE == "introc" then "garage" else STATE
	local ui = setup(M, GEN, base, VW, VH, INSETS, { touch = OPT.touch == "1", travel = if OPT.mod == "abroad" then "abroad" else nil })
	local game = M.game
	local G = M.G
	local RS = game.ReplicatedStorage
	local Client = game.StarterPlayer.StarterPlayerScripts.Client
	local s = ui.session
	local d = s.data
	local e = d.empire
	local EmpireConfig = M.require(RS.Shared.Config.EmpireConfig)
	local EmpireMath = M.require(RS.Shared.EmpireMath)
	local MarketMath = M.require(RS.Shared.MarketMath)
	local ModelMath = M.require(RS.Shared.ModelMath)
	local RunService = game:GetService("RunService")
	local function frames(n)
		for _ = 1, n do
			M.fire(RunService.RenderStepped, 1 / 60)
			M.fire(RunService.Heartbeat, 1 / 60)
		end
	end
	if OPT.touch == "1" then
		-- the engine reports PreferredInput = Touch on phones (the mock's default is the first enum item)
		local uis = game:GetService("UserInputService")
		pcall(function() uis[M.KEY].props.PreferredInput = G.Enum.PreferredInput.Touch end)
	end
	if OPT.mod == "broke" then
		d.money = -48250
		s.live.revenue, s.live.cost = 20, 60
	end

	if OPT.studio == "1" then
		-- the Studio owner preview (RunService:IsStudio() = true): the HUD Shop button shows with every id at 0
		M.IMPL.RunService.methods.IsStudio = function() return true end
		M.classInfo("RunService").methods.IsStudio = function() return true end
	end
	if STATE == "intro" or STATE == "introc" then
		-- a new player: no company in the snapshot before the Intro mounts (like the real join order)
		d.company = nil
		ui.push()
		M.settle(0.2)
		local Intro = M.require(Client.UI.Screens.Intro)
		local introLayer = ui.playerGui:FindFirstChild("AIEmpire_Intro"):FindFirstChild("Root")
		Intro.mount(introLayer, { onFinish = function() end, onReopen = function() end })
		ui.push()
		M.settle(0.3)
		if STATE == "introc" then
			for _, x in ui.playerGui:GetDescendants() do
				if x:IsA("TextButton") and x.Name == "Customize" then M.fire(x.Activated, {}, 1) end
			end
			M.settle(0.3)
		end
	elseif GUIDE[STATE] then
		-- a fresh garage company: $10,000, no staff, the guide on
		d.money = 10000
		e.seconds = 30
		e.quests = {}
		local function trainedModel(status)
			local stats = { reasoning = 42, coding = 43, math = 27, creativity = 48, knowledge = 42, reliability = 37, speed = 80, efficiency = 80 }
			local m = { id = "nova1", name = "Nova", version = 1, sizeId = "s100m", focusId = "creative", status = status, createdAt = 0, trainedAt = 0,
				stats = stats, overall = ModelMath.overall(stats), trainCost = 1280, dataUsed = { total = 4e9, quality = 0.42, shares = { general = 1 } } }
			d.models.nova1 = m
			d.modelOrder = { "nova1" }
			return m
		end
		if STATE == "guide1b" then
			e.quests.founder = true
			d.money = 11200
		elseif STATE == "guide2s" then
			e.quests.founder = true
			d.money = 3800
			d.data = { general = { tokens = 4e9, quality = 0.42 } }
			e.tutorial.step = 2
		elseif STATE == "guide3" or STATE == "guide3d" then
			e.quests.founder = true
			d.money = 2520
			d.data = { general = { tokens = 4e9, quality = 0.42 } }
			e.tutorial.step = 3
			trainedModel("training")
			d.training = { modelId = "nova1", workTotal = 100, workDone = 42, cost = 1280, expected = 40.2, qualityMod = 1, eventRolled = STATE == "guide3d", epoch = 3, loss = {}, log = {} }
			if STATE == "guide3d" then
				d.training.event = { id = "data_issue", pending = true, expiresAt = 0 }
			end
		elseif STATE == "guide4" or STATE == "guide4r" or STATE == "guide4l" then
			e.quests.founder = true; e.quests.data = true
			d.money = 4320
			d.data = { general = { tokens = 4e9, quality = 0.42 } }
			e.tutorial.step = 4
			trainedModel("trained")
			d.stats.modelsTrained = 1
		elseif STATE == "guide5" or STATE == "handoff" then
			e.quests.founder = true; e.quests.data = true; e.quests.train = true
			d.money = 1820
			d.data = { general = { tokens = 4e9, quality = 0.42 } }
			e.tutorial.step = 5
			local m = trainedModel("live")
			m.release = { subPrice = 10, apiPrice = 2, marketing = 5000, target = "general", releasedAt = 0, auto = true }
			m.market = MarketMath.newMarketState("general", 0)
			m.market.users = { consumers = 640 }
			d.stats.modelsTrained, d.stats.modelsReleased = 1, 1
			s.live.users, s.live.revenue, s.live.cost = 640, 1.6, 0.3
			s.live.perModel = { nova1 = { users = 640, revenue = 1.6, cost = 0.3 } }
		end
		local Guide = M.require(Client.UI.Screens.Guide)
		Guide.mount(ui.playerGui)
		local GuideController = M.require(Client.Controllers.GuideController)
		GuideController.init()
		-- virtual time moves only in settle(); frame signals never fire there, so the guide's 0.2 s heartbeat is
		-- emulated: settle in small steps and run GuideController.update() after each (ring delays count from there)
		local function tick(seconds)
			local left = seconds
			while left > 0 do
				local dt = math.min(0.25, left)
				G.task.wait(dt) -- virtual time advances only with scheduled waits
				M.settle(0)
				GuideController.update()
				left -= dt
			end
		end
		ui.push()
		M.settle(0.3)
		if STATE == "guide2" or STATE == "guide2s" then
			ui.Computer.open("lab", "design")
			M.settle(0.6)
		elseif STATE == "guide4r" then
			local LabState = M.require(Client.UI.Lab.LabState)
			LabState.storeReveal({ modelId = "nova1", overall = d.models.nova1.overall, expected = 40.2 })
			ui.Computer.open("lab", "release")
			-- the ring on LAUNCH › waits for the reveal sequence (~2.5 s) + 3 s (TutorialMath.REVEAL_RING_DELAY)
			tick(tonumber(OPT.reveal) or 6.5)
		elseif STATE == "guide4l" then
			ui.Computer.open("lab", "release")
			M.settle(0.8)
		elseif STATE == "handoff" then
			-- GOT IT: the server marks the guide done; the HUD shows GUIDE COMPLETE ✓ and the hand-off toast
			ui.binds.EmpireAction(s, { action = "tutorial", op = "done" })
			ui.push()
			M.settle(0.3)
			frames(20)
			M.settle(0.5)
		end
		if STATE == "guide1b" or OPT.settle then
			-- past the first-contact dim and the 8 s greeting
			G.task.wait(tonumber(OPT.settle) or 9)
			ui.push()
			M.settle(0.3)
		end
	else
		-- the Menu / HUD of a save that launched before the guide existed: the real cleaner marks the guide done and
		-- fills `seen` with the open pages (no NEW-badge flood); fresh=1 = just finished the guide (NEW pills show)
		if OPT.fresh == "1" then
			e.tutorial.done = true
		else
			e.tutorial = { v = 1, step = 0, done = false, skipped = false, tipsOff = false, seen = {}, tips = {} }
			M.require(game.ServerScriptService.Server.Lib.Template).cleanTutorial(d)
		end
		ui.push()
		if OPT.tip == "1" then
			-- a one-time tip line in the goal card (GuideController shows these after the guide, A12)
			ui.HUD.setTip("HR hires for you. Meet them in Team.", function() end, 600)
		end
	end

	if OPT.app then
		ui.Computer.open(if OPT.app == "nil" then nil else OPT.app, OPT.section)
		M.settle(0.6)
	end
	if OPT.page then
		ui.Computer.routeTo("page:" .. OPT.page)
		M.settle(0.6)
	end
	if OPT.locked then
		local rail = ui.Computer.railButton(OPT.locked)
		if rail then M.fire(rail.Activated, {}, 1) end
		M.settle(0.3)
	end
	ui.push()
	-- virtual time moves only with scheduled waits: half a second into the first-contact dim (fade-in done)
	G.task.wait(tonumber(OPT.wait or 0.5))
	GuiDump.setViewport(ui.playerGui, VW, VH, INSETS)
	local n = GuiDump.applyFeedback({ ui.playerGui }, FEEDBACK)
	M.settle(0.2)
	frames(tonumber(OPT.frames or 90))
	pcall(function()
		local Guide = M.require(Client.UI.Screens.Guide)
		Guide.update()
		if OPT.debug == "1" then
			local parts = Guide.parts()
			P("@@DBG dim1", parts.dims[1] and parts.dims[1].Visible, parts.dims[1] and parts.dims[1].BackgroundTransparency, "dimming", Guide.dimming(), "now", M.Sched.now)
		end
	end)
	GuiDump.dump({ ui.playerGui }, { scene = "menu", state = STATE, viewport = { VW, VH }, insets = INSETS, feedbackChanged = n })
end

setfenv(body, M.envFor(nil))
local ok, res, status = M.runMain(body, { timeout = 600 })
if not ok then print("@@ERROR body crashed (" .. tostring(status) .. "): " .. tostring(res)) end
if M.stats.errors > 0 then print("@@ERROR background thread errors: " .. M.stats.errors) end
