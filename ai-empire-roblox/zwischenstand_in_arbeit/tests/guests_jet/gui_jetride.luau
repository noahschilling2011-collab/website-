--!nocheck
-- guiprev scene (guests_jet): the company-jet ride HUD of the real JetController - the founder riding in the cruise
-- (flight info panel, View button, window-seat overlay) plus the welcome toast.
-- states: window | cockpit | outside (the View mode); "+phone" (e.g. window+phone) also mounts the real phone UI
-- (closed: its button, Phone.ORDER_CLOSED) to show that it stays above the cabin wall (JetRide DisplayOrder 14);
-- "+arrived": the flight has ended while JetService still places the founder (info line without a countdown)
-- Run: python3 tools/guiprev/guiprev.py --scene tests/guests_jet/gui_jetride.luau --state window --viewport phone --dpr 2 --out out/guests_jet/gui_jetride_phone.png
local M = require("../../harness/mock")
local GuiDump = require("../../tools/guiprev/guidump")
local args = { ... }
local GEN = args[1] or "../../harness/.gen_guiprev"
local STATE = args[2] or "window"
local WITH_PHONE = string.find(STATE, "+phone", 1, true) ~= nil
local ARRIVED = string.find(STATE, "+arrived", 1, true) ~= nil -- the flight has ended, the arrival area still streams in
local MODE = string.gsub(string.gsub(STATE, "%+phone", ""), "%+arrived", "")
local VW, VH = tonumber(args[3]) or 1280, tonumber(args[4]) or 720
local insetList = string.split(args[5] or "58,0,0,0", ",")
local INSETS = { top = tonumber(insetList[1]) or 0, right = tonumber(insetList[2]) or 0, bottom = tonumber(insetList[3]) or 0, left = tonumber(insetList[4]) or 0 }
local FEEDBACK = if args[6] and args[6] ~= "-" then require(args[6]) else nil
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
GuiDump.init(M)
M.G.os = setmetatable({ clock = function() return M.Sched.now end }, { __index = os })

local function body()
	local G = M.G
	local Instance = G.Instance
	local game = M.game
	local RS = game.ReplicatedStorage
	local Client = game.StarterPlayer.StarterPlayerScripts.Client
	local JP = M.require(RS.Shared.JetPlan)
	local T = 1.7e9
	M.IMPL.Workspace.methods.GetServerTimeNow = function() return T end
	if M.classInfo("Workspace").methods then M.classInfo("Workspace").methods.GetServerTimeNow = function() return T end end
	local attrs = {}
	local playerGui = Instance.new("Folder"); playerGui.Name = "PlayerGui"
	local localPlayer = { UserId = 4242, Name = "Founder", DisplayName = "Founder", Character = nil, Parent = game.Players, CharacterAdded = M.newSignal("CharacterAdded"),
		WaitForChild = function(_, name) if name == "PlayerGui" then return playerGui end end, FindFirstChild = function(_, name) if name == "PlayerGui" then return playerGui end end,
		FindFirstChildOfClass = function() return nil end, GetAttribute = function(_, k) return attrs[k] end, SetAttribute = function(_, k, v) attrs[k] = v end,
		GetAttributeChangedSignal = function(_, k) return M.newSignal(k) end }
	M.IMPL.Players.get.LocalPlayer = function() return localPlayer end; M.classInfo("Players").get.LocalPlayer = function() return localPlayer end
	local UIRoot = M.require(Client.UI.UIRoot)
	local Toast = M.require(Client.UI.Toast)
	local hud, dim, overlay, intro, top = UIRoot.init()
	GuiDump.setViewport(playerGui, VW, VH, INSETS)
	Toast.mount(top)
	-- the founder's own jet in the cruise to Port Meridian
	local root = Instance.new("Folder"); root.Name = "CompanyJets"; root.Parent = RS
	local f = Instance.new("Folder"); f.Name = "Jet_4242"
	f:SetAttribute("Owner", 4242); f:SetAttribute("Company", "Nimbus Labs"); f:SetAttribute("Livery", G.Color3.fromRGB(0, 170, 200))
	f:SetAttribute("At", "home"); f:SetAttribute("Slot", 1)
	local tl = JP.timeline("out", 1, 0)
	local start = if ARRIVED then T - (tl.duration + 2) else T - (tl.phases.cruise.t0 + 4)
	f:SetAttribute("FlightKind", "out"); f:SetAttribute("FlightSlot", 1); f:SetAttribute("FlightDelay", 0); f:SetAttribute("FlightStart", start); f:SetAttribute("FlightId", "jet:4242:1")
	f.Parent = root
	local JC = M.require(Client.Controllers.JetController)
	JC.attach(root)
	attrs.JetFlight = "jet:4242:1"
	JC.onFlight()
	JC.setRideMode(MODE)
	if WITH_PHONE then
		local Phone = M.require(Client.UI.Screens.Phone)
		local nop = function() end
		Phone.mount(playerGui, { markRead = nop, readCalls = nop, answer = nop, dial = nop, setSetting = nop, sendChat = nop, resetChat = nop,
			setDraft = nop, guide = nop, openComputer = nop, close = nop, refresh = nop })
	end
	for _ = 1, 4 do JC.step(0.3) end
	GuiDump.setViewport(playerGui, VW, VH, INSETS)
	local n = GuiDump.applyFeedback({ playerGui }, FEEDBACK)
	M.settle(0.3)
	GuiDump.dump({ playerGui }, { scene = "jetride", state = STATE, viewport = { VW, VH }, insets = INSETS, feedbackChanged = n })
end
setfenv(body, M.envFor(nil))
local ok, res, status = M.runMain(body, { timeout = 600 })
if not ok then print("@@ERROR body crashed (" .. tostring(status) .. "): " .. tostring(res)) end
if M.stats.errors > 0 then print("@@ERROR background thread errors: " .. M.stats.errors) end
