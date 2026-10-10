--!nocheck
-- Talk package client smoke test (headless mock): the real TalkController + UI/Screens/TalkPanel wired to
-- the real TalkService through patched RemoteFunction:InvokeServer and the Notify RemoteEvent.
-- Catches invalid properties/enums (the mock checks every member against the API dump) and broken flows:
-- open from the prompt, typing pause, chips, mouse click, keys 1–4, goodbye, close button, server-side
-- TALK_CLOSE (idle), error toast, UIScale, and the local talk-prompt visibility rules.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_talk && tools/luau tests/talk/test_client.luau [-a .gen_dir]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_talk")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
for path, src in require("./stubs") do sources[path] = src end
local fixture = require("./fixture")
M.loadTree(manifest, sources)
M.quiet = true
local G = M.G
local say = print
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; say("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end
local function body()
	local Instance, Vector3 = G.Instance, G.Vector3
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local Services = Server.Services
	local Client = game.StarterPlayer.StarterPlayerScripts.Client
	local Net = M.require(RS.Shared.Net)
	local Remote = M.require(Server.Lib.Remote)
	local Talk = M.require(Services.TalkService)
	local fx = fixture(M, G, 2)
	local owner = fx.ownerPlayer
	-- the owner is the local player
	local playerGui = Instance.new("Folder"); playerGui.Name = "PlayerGui"
	owner.CharacterAdded = M.newSignal("CharacterAdded")
	owner.WaitForChild = function(_, name) if name == "PlayerGui" then return playerGui end end
	owner.FindFirstChildOfClass = function() return nil end
	M.IMPL.Players.get.LocalPlayer = function() return owner end; M.classInfo("Players").get.LocalPlayer = function() return owner end
	local clock = 100
	Talk.clock = function() return clock end
	Talk.init()
	-- remotes: client calls go straight into the server handlers; Notify for the owner reaches the client
	local folder = Instance.new("Folder"); folder.Name = Net.FOLDER
	for _, name in Net.FUNCTIONS do local f = Instance.new("RemoteFunction"); f.Name = name; f.Parent = folder end
	for _, name in Net.EVENTS do local e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = folder end
	folder.Parent = RS
	local calls = {}
	local function patch(cls, name, fn) M.IMPL[cls].methods[name] = fn; M.classInfo(cls).methods[name] = fn end
	patch("RemoteFunction", "InvokeServer", function(self, payload)
		table.insert(calls, { name = self.Name, payload = payload })
		if self.Name == "RequestState" then return { ok = true, state = { saveEnabled = false, serverTime = 1.7e9, data = fx.ownerS.data, live = fx.ownerS.live } } end
		local handler = Remote.binds[self.Name]
		if not handler then return { ok = false, err = "BAD_INPUT" } end
		clock += 1 -- one virtual second per request keeps the say interval out of the way
		local result = handler(fx.ownerS, payload or {})
		calls[#calls].result = result
		return result
	end)
	local notifyEvent = folder:FindFirstChild("Notify")
	local rawFire = Remote.fire
	Remote.fire = function(player, name, ...)
		rawFire(player, name, ...)
		if player == owner and name == "Notify" then M.fire(notifyEvent.OnClientEvent, ...) end
	end
	-- client modules
	local UIRoot = M.require(Client.UI.UIRoot)
	local Toast = M.require(Client.UI.Toast)
	local State = M.require(Client.Controllers.StateController)
	local TalkController = M.require(Client.Controllers.TalkController)
	local TalkPanel = M.require(Client.UI.Screens.TalkPanel)
	local hud, dim, overlay, intro, top = UIRoot.init()
	Toast.mount(top)
	TalkController.init()
	State.init()
	M.settle(1)
	local function find(root, pred) for _, d in root:GetDescendants() do if pred(d) then return d end end; return nil end
	local function findText(root, cls, part) return find(root, function(d) return d:IsA(cls) and string.find(d.Text, part, 1, true) ~= nil end) end
	local function chips(screen)
		local out = {}
		for _, d in screen:GetDescendants() do if d:IsA("TextButton") and string.sub(d.Name, 1, 7) == "Option_" then table.insert(out, d) end end
		table.sort(out, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
		return out
	end
	local r = fx.rigs.researcher
	local q = r.Head.EmployeeTalk
	------------------------------------------------------------------ A. prompt visibility
	check("own staff prompt enabled", q.Enabled == true)
	r:SetAttribute("OffDuty", true); M.settle(.1)
	check("off duty → prompt hidden", q.Enabled == false)
	r:SetAttribute("OffDuty", false); M.settle(.1)
	check("back on duty → prompt shown", q.Enabled == true)
	local kitchenPrompt, receptionPrompt = fx.rigs.ops9.Head.EmployeeTalk, fx.rigs.ops1.Head.EmployeeTalk
	kitchenPrompt:SetAttribute("OwnerUserId", 1); receptionPrompt:SetAttribute("OwnerUserId", 1)
	check("someone else's back-of-house prompt hidden", TalkController.promptEnabled(fx.rigs.ops9, kitchenPrompt) == false)
	check("someone else's Public front-desk prompt shown", TalkController.promptEnabled(fx.rigs.ops1, receptionPrompt) == true)
	kitchenPrompt:SetAttribute("OwnerUserId", fx.OWNER); receptionPrompt:SetAttribute("OwnerUserId", fx.OWNER)
	------------------------------------------------------------------ B. open from the prompt
	fx.moveTo(fx.ownerRoot, fx.near(r))
	Talk._prompt(q, owner)
	M.settle(.1)
	local screen = playerGui:FindFirstChild("TalkPanel")
	check("TalkPanel opened", screen ~= nil and TalkPanel.isOpen())
	check("prompt hidden while talking (TalkingTo)", q.Enabled == false)
	check("header shows the name", screen and findText(screen, "TextLabel", r:GetAttribute("EmployeeName")) ~= nil)
	check("header shows job + room", screen and findText(screen, "TextLabel", "AI Researcher  ·  First AI Studio (G)") ~= nil)
	check("typing bubble first", screen and findText(screen, "TextLabel", "typing") ~= nil)
	local scale = screen and find(screen, function(d) return d:IsA("UIScale") and d.Parent and d.Parent:IsA("Frame") and d.Parent.Parent == screen end)
	check("panel UIScale fitted (0.3..1)", scale and scale.Scale >= 0.3 and scale.Scale <= 1)
	M.settle(2.5)
	local open = nil
	for _, f in Remote.fired do if f.args[1] == "TALK_OPEN" then open = f.args[2] end end
	check("greeting bubble after the typing pause", open and findText(screen, "TextLabel", string.sub(open.greeting, 1, 20)) ~= nil)
	local list = chips(screen)
	check("one chip per option", open and #list == #open.options, #list)
	check("goodbye chip last", list[#list] and list[#list].Name == "Option_bye")
	------------------------------------------------------------------ C. click a chip
	M.fire(list[1].Activated)
	M.settle(.1)
	check("player bubble shows the chosen option", findText(screen, "TextLabel", open.options[1].text) ~= nil)
	M.settle(3)
	check("answer bubble from the server (work → room)", findText(screen, "TextLabel", "First AI Studio (G).") ~= nil or findText(screen, "TextLabel", "in the First AI Studio") ~= nil)
	local list2 = chips(screen)
	check("new chips after the answer", #list2 >= 2 and list2[#list2].Name == "Option_bye")
	------------------------------------------------------------------ D. keys 1–4
	local secondText = string.match(list2[2].Text, "^%d  (.+)$") or list2[2].Text
	M.fire(game:GetService("UserInputService").InputBegan, { KeyCode = G.Enum.KeyCode.Two }, false)
	M.settle(3)
	check("key 2 picks the second chip", findText(screen, "TextLabel", secondText) ~= nil, secondText)
	M.fire(game:GetService("UserInputService").InputBegan, { KeyCode = G.Enum.KeyCode.One }, true)
	M.settle(.2)
	check("keys ignored when the game processed them", #chips(screen) > 0 and not findText(screen, "TextLabel", "typing"))
	------------------------------------------------------------------ E. goodbye
	local list3 = chips(screen)
	M.fire(list3[#list3].Activated)
	M.settle(1.2)
	local byeResult = calls[#calls].result
	check("farewell bubble shows the server's goodbye line", byeResult and byeResult.close and findText(screen, "TextLabel", byeResult.text) ~= nil, byeResult and byeResult.text)
	M.settle(2.5)
	check("panel closes after goodbye", not TalkPanel.isOpen() and playerGui:FindFirstChild("TalkPanel") == nil)
	check("server conversation closed", Talk.conversation(r) == nil)
	M.settle(.1)
	check("prompt visible again", q.Enabled == true)
	------------------------------------------------------------------ F. close button
	clock += 5
	Talk._prompt(q, owner)
	M.settle(2.5)
	screen = playerGui:FindFirstChild("TalkPanel")
	local closeBtn = screen and findText(screen, "TextButton", "Close")
	check("close button exists", closeBtn ~= nil)
	if closeBtn then M.fire(closeBtn.Activated) end
	M.settle(.5)
	check("close button closes panel + server conversation", not TalkPanel.isOpen() and Talk.conversation(r) == nil)
	------------------------------------------------------------------ G. server ends an idle conversation
	clock += 5
	Talk._prompt(q, owner)
	M.settle(2.5)
	check("reopened", TalkPanel.isOpen())
	M.settle(Talk.IDLE - 2.5 + 0.4)
	local closing = nil
	for _, f in Remote.fired do if f.args[1] == "TALK_CLOSE" then closing = f.args[2] end end
	check("TALK_CLOSE shows the farewell", closing and playerGui:FindFirstChild("TalkPanel") ~= nil and findText(playerGui.TalkPanel, "TextLabel", closing.text) ~= nil, closing and closing.text)
	M.settle(2)
	check("idle close closes the panel", not TalkPanel.isOpen())
	------------------------------------------------------------------ H. error toast after the server dropped the conversation
	clock += 5
	Talk._prompt(q, owner)
	M.settle(2.5)
	screen = playerGui:FindFirstChild("TalkPanel")
	fx.moveTo(fx.ownerRoot, fx.near(r, Vector3.new(30, 0, 0)))
	local l4 = chips(screen)
	M.fire(l4[1].Activated)
	M.settle(3)
	check("walked away → toast + panel closed", findText(top, "TextLabel", "walked away") ~= nil and not TalkPanel.isOpen(), TalkPanel.isOpen())
	------------------------------------------------------------------ I. TALK_NOTICE toast
	fx.moveTo(fx.ownerRoot, fx.near(fx.rigs.engineer, Vector3.new(40, 0, 0)))
	clock += 5
	Talk._prompt(fx.rigs.engineer.Head.EmployeeTalk, owner)
	M.settle(.3)
	check("one-liner toast for a refused prompt", findText(top, "TextLabel", "Step a little closer") ~= nil)
	------------------------------------------------------------------ J. respawn closes
	fx.moveTo(fx.ownerRoot, fx.near(r))
	clock += 5
	Talk._prompt(q, owner)
	M.settle(.2)
	M.fire(owner.CharacterAdded, owner.Character)
	M.settle(.2)
	check("respawn closes the panel", not TalkPanel.isOpen())
	local talkCalls = 0; for _, c in calls do if c.name == "TalkAction" then talkCalls += 1 end end
	say(string.format("client: %d TalkAction calls", talkCalls))
end
setfenv(body, M.envFor(nil))
local ok, err = M.runMain(body, { timeout = 600 })
if not ok then say("ERROR: " .. tostring(err)); failc += 1 end
say(string.format("talk client tests: %d passed, %d failed", pass, failc))
if failc > 0 then error("talk client tests failed", 0) end
