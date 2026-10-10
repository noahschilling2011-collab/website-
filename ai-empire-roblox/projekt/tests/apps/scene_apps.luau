--!nocheck
-- guiprev scene of the apps package: HUD (Next goal) and the Company / Hardware apps in the states of ui_setup.luau.
--   python3 tools/guiprev/guiprev.py --scene tests/apps/scene_apps.luau --gen harness/.gen_apps --state mid \
--       --viewport desktop --out out/apps/empire_mid_clients.png app=empire section=clients
-- extra: app=none|empire|compute|lab|... (default none = HUD only), section=<Company tab>, touch=1, travel=abroad
local M = require("../../harness/mock")
local GuiDump = require("../../tools/guiprev/guidump")
local setup = require("./ui_setup")
local args = { ... }
local GEN = args[1] or "../../harness/.gen_apps"
local STATE = args[2] or "mid"
local VW, VH = tonumber(args[3]) or 1280, tonumber(args[4]) or 720
local insetList = string.split(args[5] or "58,0,0,0", ",")
local INSETS = { top = tonumber(insetList[1]) or 0, right = tonumber(insetList[2]) or 0, bottom = tonumber(insetList[3]) or 0, left = tonumber(insetList[4]) or 0 }
local FEEDBACK = if args[6] and args[6] ~= "-" then require(args[6]) else nil
local OPT = {}
for i = 7, #args do
	local k, v = string.match(args[i], "^([%w_]+)=(.*)$")
	if k then OPT[k] = v end
end
local APP = OPT.app or "none"

M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
GuiDump.init(M)

local function body()
	local ui = setup(M, GEN, STATE, VW, VH, INSETS, { touch = OPT.touch == "1", travel = OPT.travel })
	local game = M.game
	if APP ~= "none" then
		ui.Computer.open(APP, OPT.section)
		M.settle(0.5)
	end
	if OPT.brief == "1" then
		-- the assistant's briefing panel (PeopleController) with the real AssistantService payload of this state
		local Client = game.StarterPlayer.StarterPlayerScripts.Client
		local G = M.G
		local cam = G.workspace.CurrentCamera
		if not cam then cam = G.Instance.new("Camera"); cam.Parent = G.workspace; pcall(function() G.workspace.CurrentCamera = cam end) end
		pcall(function() cam[M.KEY].props.ViewportSize = G.Vector2.new(VW, VH - INSETS.top) end) -- read-only in Roblox: mock internals
		local People = M.require(Client.Controllers.PeopleController)
		People.init(function(app, section) ui.Computer.open(app, section) end)
		local Assistant = M.require(game.ServerScriptService.Server.Services.AssistantService)
		local notify = game.ReplicatedStorage.Remotes:FindFirstChild("Notify")
		M.fire(notify.OnClientEvent, "ASSISTANT_OPEN", Assistant.payload(ui.session))
		M.settle(0.5)
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
	GuiDump.dump({ ui.playerGui }, { scene = "apps", app = APP, state = STATE, viewport = { VW, VH }, insets = INSETS, feedbackChanged = n })
end

setfenv(body, M.envFor(nil))
local ok, res, status = M.runMain(body, { timeout = 600 })
if not ok then print("@@ERROR body crashed (" .. tostring(status) .. "): " .. tostring(res)) end
if M.stats.errors > 0 then print("@@ERROR background thread errors: " .. M.stats.errors) end
