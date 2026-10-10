--!nocheck
-- guiprev scene of the apps package: HUD (Next goal) and the Company / Hardware apps in the states of ui_setup.luau.
--   python3 tools/guiprev/guiprev.py --scene tests/apps/scene_apps.luau --gen harness/.gen_apps --state mid \
--       --viewport desktop --out out/apps/empire_mid_clients.png app=empire section=clients
-- extra: app=none|empire|compute|lab|... (default none = HUD only), section=<Company tab>, touch=1, travel=abroad,
--        brief=1 (assistant briefing panel), press=<button text, _ for spaces>, phone=1 (mount the company phone:
--        lane / overlap check), mod=rackfull|maxed|broke|oldsave|nolive|longname (adversarial states of test_adv)
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
	local RS = game.ReplicatedStorage
	local s = ui.session
	local d = s.data
	local e = d.empire
	if OPT.phone == "1" then
		local Controller = M.require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.PhoneController)
		pcall(Controller.init)
		M.settle(0.5)
	end
	local ModelMath = M.require(RS.Shared.ModelMath)
	local HardwareConfig = M.require(RS.Shared.Config.HardwareConfig)
	local mod = OPT.mod
	if mod == "rackfull" or mod == "maxed" then
		local slots = HardwareConfig.slots(e)
		while ModelMath.fleet(d.gpus).slotsUsed < slots do d.gpus.consumer = (d.gpus.consumer or 0) + 1 end
		s.live.waitlist = 12000
		s.live.load = math.floor((s.live.capacity or 1e5) * 1.2)
		if mod == "maxed" then
			e.infrastructure.cooling = 8
			while HardwareConfig.thermal(e, ModelMath.fleet(d.gpus).throughput) >= 1 do d.gpus.datacenter = (d.gpus.datacenter or 0) + 1; d.gpus.consumer = math.max(0, (d.gpus.consumer or 0) - 1) end
		end
	elseif mod == "broke" then
		d.money = -48250
		s.live.revenue, s.live.cost = 20, 60
		s.live.ops.paused = true
		s.live.ops.saveMode = false
		e.unpaidLeave = 3
	elseif mod == "oldsave" then
		s.live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} }
		e.ledger = {}
	elseif mod == "nolive" then
		for _, id in d.modelOrder do local m = d.models[id]; if m.status == "live" then m.status = "retired" end end
		s.live.users, s.live.revenue = 0, 0
	elseif mod == "longname" then
		d.company.name = "Extraordinarily Long Company Name"
		d.money = 1234567890
		s.live.users = 987654321
		s.live.revenue, s.live.cost = 123456, 3
	end
	if mod then ui.push(); M.settle(0.3) end
	if OPT.phoneopen == "1" then
		local Phone = M.require(game.StarterPlayer.StarterPlayerScripts.Client.UI.Screens.Phone)
		pcall(Phone.open)
		M.settle(0.5)
	end
	if APP ~= "none" then
		ui.Computer.open(APP, OPT.section)
		M.settle(0.5)
	end
	if OPT.press then
		-- press the first TextButton with this text (e.g. press=Day_8 for the Money tab's day picker; "_" = space)
		local want = string.gsub(OPT.press, "_", " ")
		ui.push()
		for _, x in ui.playerGui:GetDescendants() do
			if x:IsA("TextButton") and x.Text == want then M.fire(x.Activated, {}, 1); break end
		end
		M.settle(0.4)
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
