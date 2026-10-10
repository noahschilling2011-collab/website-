--!nocheck
-- guiprev scene of the models package: the Lab and Market apps in the states of ui_setup.luau.
--   python3 tools/guiprev/guiprev.py --scene tests/models/scene_models.luau --gen harness/.gen_models --state rich \
--       --viewport desktop --out out/models/market_rich.png app=market [view=release]
-- extra: app=lab|market (default market); view=release opens the Lab's launch card of the trained model.
local M = require("../../harness/mock")
local GuiDump = require("../../tools/guiprev/guidump")
local setup = require("./ui_setup")
local args = { ... }
local GEN = args[1] or "../../harness/.gen_models"
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
local APP = OPT.app or "market"

M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
GuiDump.init(M)
M.G.os = setmetatable({ clock = function() return M.Sched.now end }, { __index = os })

local function body()
	local ui = setup(M, GEN, STATE, VW, VH, INSETS)
	local game = M.game
	ui.Computer.open(APP)
	M.settle(0.5)
	if APP == "lab" and OPT.view == "release" then
		ui.LabApp.openRelease("study")
		M.settle(3) -- Recommended price: the client forecast runs over a few frames
	end
	ui.push()
	GuiDump.setViewport(ui.playerGui, VW, VH, INSETS)
	local n = GuiDump.applyFeedback({ ui.playerGui }, FEEDBACK)
	M.settle(0.3)
	local RunService = game:GetService("RunService")
	for _ = 1, tonumber(OPT.frames or 60) do
		M.fire(RunService.RenderStepped, 1 / 60)
		M.fire(RunService.Heartbeat, 1 / 60)
	end
	M.settle(0.3)
	GuiDump.dump({ ui.playerGui }, { scene = "models", app = APP, state = STATE, viewport = { VW, VH }, insets = INSETS, feedbackChanged = n })
end

setfenv(body, M.envFor(nil))
local ok, res, status = M.runMain(body, { timeout = 600 })
if not ok then print("@@ERROR body crashed (" .. tostring(status) .. "): " .. tostring(res)) end
if M.stats.errors > 0 then print("@@ERROR background thread errors: " .. M.stats.errors) end
