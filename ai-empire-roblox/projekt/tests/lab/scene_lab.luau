--!nocheck
-- guiprev scene of the lab package: the Lab home and every mode of the Model Studio in the states of lab_setup.
--   python3 tools/guiprev/guiprev.py --scene tests/lab/scene_lab.luau --gen harness/.gen_labprev --state rich \
--       --viewport phone --dpr 2 --out out/lab/x.png view=design step=2
-- extra: view=home|design|training|reveal|launch|live|market|benchmark|suggest (scale=0.25)|banner  step=1..6 (design)  ls=1..3 (launch)
--        event=1 (training paused for a decision)  progress=0.45 (training)  breakdown=1 (review)  custom=1
--        wait=3 (reveal: dump during the record confetti instead of the settled final frame)
local M = require("../../harness/mock")
local GuiDump = require("../../tools/guiprev/guidump")
local setup = require("./lab_setup")
local args = { ... }
local GEN = args[1] or "../../harness/.gen_labprev"
local STATE = args[2] or "rich"
local VW, VH = tonumber(args[3]) or 1280, tonumber(args[4]) or 720
local insetList = string.split(args[5] or "58,0,0,0", ",")
local INSETS = { top = tonumber(insetList[1]) or 0, right = tonumber(insetList[2]) or 0, bottom = tonumber(insetList[3]) or 0, left = tonumber(insetList[4]) or 0 }
local FEEDBACK = if args[6] and args[6] ~= "-" then require(args[6]) else nil
local OPT = {}
for i = 7, #args do
	local k, v = string.match(args[i], "^([%w_]+)=(.*)$")
	if k then OPT[k] = v end
end
local VIEW = OPT.view or "home"

M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
GuiDump.init(M)
M.G.os = setmetatable({ clock = function() return M.Sched.now end }, { __index = os })

local function body()
	local ui = setup(M, GEN, STATE, VW, VH, INSETS)
	local s, d = ui.session, ui.session.data
	local Studio = ui.Studio
	local function settle(t) M.settle(t or 0.5) end
	-- optional prefilled plan: size= focus= recipe= line= name=
	local StateC = M.require(M.game.StarterPlayer.StarterPlayerScripts.Client.Controllers.StateController)
	if OPT.size or OPT.focus then StateC.setSelection(OPT.size or StateC.ui.sizeId, OPT.focus or StateC.ui.focusId) end
	if OPT.recipe then StateC.setRecipe(OPT.recipe) end
	if OPT.line then ui.LabState.lineId = OPT.line end
	if OPT.name then ui.LabState.name = OPT.name end
	ui.Computer.open("lab")
	settle(0.5)
	local function startTraining(payload)
		local ok, r = ui.binds.StartTraining(s, payload or { name = "Sage", sizeId = d.gpus.laptop and "s100m" or "s1b", focusId = d.gpus.laptop and "creative" or "coding", recipeId = "steady", target = d.gpus.laptop and "general" or "developers" }), nil
		ui.push()
		return ok
	end
	if VIEW == "design" then
		Studio.open("design", { step = tonumber(OPT.step) or nil })
		settle(0.5)
		if OPT.step then Studio.current().step(0) end
	elseif VIEW == "training" or VIEW == "reveal" or VIEW == "live" or VIEW == "benchmark" then
		local r = ui.binds.StartTraining(s, { name = (STATE == "fresh" or STATE == "starter") and "Nova" or "Sage",
			sizeId = (STATE == "fresh" or STATE == "starter") and "s100m" or (STATE == "hq" and "s7b" or "s1b"),
			focusId = (STATE == "fresh" or STATE == "starter") and "creative" or "coding", recipeId = "steady",
			target = (STATE == "fresh" or STATE == "starter") and "general" or "developers" })
		ui.push()
		if r.ok then ui.LabState.plannedLine[r.modelId] = (STATE == "fresh" or STATE == "starter") and "general" or "developers" end
		Studio.open("training", {})
		settle(0.3)
		if VIEW == "training" then
			local t = d.training
			if t then
				t.workDone = t.workTotal * (tonumber(OPT.progress) or 0.45)
				-- loss points and log lines as the server writes them (AIModelService tick rules, jitter 0)
				local ModelMath = M.require(M.game.ReplicatedStorage.Shared.ModelMath)
				local T = M.require(M.game.ReplicatedStorage.Shared.Config.ModelConfig).TRAINING
				local wanted = math.floor(t.workDone / t.workTotal * (T.lossPoints - 1)) + 1
				while #t.loss < wanted do
					table.insert(t.loss, math.round(ModelMath.lossAt(#t.loss / (T.lossPoints - 1), t.expected, 0) * 1000) / 1000)
				end
				local epoch = math.min(9, math.floor(t.workDone / t.workTotal * 10))
				while t.epoch < epoch do
					t.epoch += 1
					local idx = math.floor(t.epoch / 10 * (T.lossPoints - 1)) + 1
					local at = math.round(ModelMath.lossAt((idx - 1) / (T.lossPoints - 1), t.expected, 0) * 1000) / 1000
					table.insert(t.log, string.format("Epoch %d/%d  loss %.3f", t.epoch, 10, at))
					while #t.log > T.logLines do table.remove(t.log, 1) end
				end
				if OPT.event == "1" then
					t.eventRolled = true
					t.event = { id = "data_issue", pending = true, expiresAt = M.G.workspace:GetServerTimeNow() + 18, outcome = nil }
					table.insert(t.log, "[!] DATA ISSUE DETECTED")
				end
			end
			ui.push()
			settle(0.3)
		else
			ui.AIModelService.finishNow(s)
			ui.push()
			-- wait=<s>: catch the reveal mid-ceremony (the record confetti bursts ~2.5 s in and lives 2.2 s)
			settle(tonumber(OPT.wait) or 6)
			if VIEW == "benchmark" then
				ui.LabApp.openSection("evaluation")
				settle(0.5)
			end
			if VIEW == "live" then
				Studio.current().primary() -- LAUNCH › on the reveal
				settle(3)
				ui.push()
				settle(1)
				Studio.current().primary() -- LAUNCH on Launch Day
				settle(2)
				ui.push()
				settle(0.5)
			end
		end
	elseif VIEW == "launch" then
		local id = nil
		for _, mid in d.modelOrder do if d.models[mid].status == "trained" then id = mid end end
		ui.LabApp.openRelease(id)
		settle(3)
		ui.push()
		settle(1)
		local ls = tonumber(OPT.ls) or 1
		Studio.current().setStep(ls)
		if OPT.custom == "1" then
			for _, x in ui.playerGui:GetDescendants() do
				if x:IsA("TextButton") and x.Name == "Campaign_custom" then M.fire(x.Activated) end
			end
		end
		settle(1)
	elseif VIEW == "market" then
		ui.Computer.open("market")
		settle(0.5)
	elseif VIEW == "suggest" then
		-- the Lab home's SUGGESTED tile with less data (scale=0.25): the Review offers the suggestion's data plan
		local k = tonumber(OPT.scale) or 1
		for _, st in d.data do st.tokens *= k end
		ui.push()
		settle(0.5)
		for _, x in ui.playerGui:GetDescendants() do
			if x:IsA("TextButton") and x.Name == "SuccessorTile" then M.fire(x.Activated) end
		end
		settle(0.5)
	elseif VIEW == "banner" then
		-- a training finishes while the player designs: the READY banner in the top bar, the step stays
		Studio.open("design", { step = tonumber(OPT.step) or 3 })
		settle(0.5)
		ui.binds.StartTraining(s, { name = "Vega", sizeId = "s100m", focusId = "creative", recipeId = "steady", target = "students" })
		ui.push()
		settle(0.3)
		ui.AIModelService.finishNow(s)
		ui.push()
		settle(1)
	end
	ui.push()
	GuiDump.setViewport(ui.playerGui, VW, VH, INSETS)
	local n = GuiDump.applyFeedback({ ui.playerGui }, FEEDBACK)
	M.settle(0.3)
	-- the phone class of the Studio follows the AbsoluteSize guiprev feeds back, so the Review tap comes after it
	if VIEW == "design" and OPT.breakdown == "1" then
		for _, x in ui.playerGui:GetDescendants() do
			if x:IsA("TextButton") and x.Name == "ReviewLines" then M.fire(x.Activated) end
		end
		M.settle(0.3)
	end
	local RunService = M.game:GetService("RunService")
	for _ = 1, tonumber(OPT.frames or 30) do
		M.fire(RunService.RenderStepped, 1 / 60)
	end
	M.settle(0.3)
	GuiDump.dump({ ui.playerGui }, { scene = "lab", view = VIEW, state = STATE, viewport = { VW, VH }, insets = INSETS, feedbackChanged = n })
end

setfenv(body, M.envFor(nil))
local ok, res, status = M.runMain(body, { timeout = 600 })
if not ok then print("@@ERROR body crashed (" .. tostring(status) .. "): " .. tostring(res)) end
if M.stats.errors > 0 then print("@@ERROR background thread errors: " .. M.stats.errors) end
