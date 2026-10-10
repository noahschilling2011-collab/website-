--!nocheck
-- guiprev scene of the phone package: the company phone in the states of ui_setup.luau.
--   python3 tools/guiprev/guiprev.py --scene tests/phone/scene_phone.luau --gen harness/.gen_phone --state rich \
--       --viewport desktop --out out/phone/home_rich.png screen=home
-- extra: screen=closed|banner|home|messages|message|calls|call|calendar|contacts|dial|chat|thread|strip|map|finance|team|settings
--        (default home)
--        touch=1 (touch device: phone button left of the jump button)
local M = require("../../harness/mock")
local GuiDump = require("../../tools/guiprev/guidump")
local setup = require("./ui_setup")
local args = { ... }
local GEN = args[1] or "../../harness/.gen_phone"
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
local SCREEN = OPT.screen or "home"

M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
GuiDump.init(M)

local function body()
	local ui = setup(M, GEN, STATE, VW, VH, INSETS, { touch = OPT.touch == "1" })
	local Phone, C = ui.Phone, ui.Controller
	local deps = C.deps
	local function firstMessage()
		local v = C.view()
		return v and v.messages[1] and v.messages[1].key
	end
	local function ringingCall()
		local v = C.view()
		for _, c in (v and v.calls or {}) do if c.state == "ringing" then return c.id end end
		return v and v.calls[1] and v.calls[1].id
	end
	if SCREEN == "banner" then
		-- the phone stays closed; the ringing call shows next to the phone button
	elseif SCREEN == "closed" then
		Phone.hideBanner()
	elseif SCREEN == "thread" then
		local v = C.view()
		local id = OPT.model or (v and v.models[1] and v.models[1].id) or "nova2"
		Phone.hideBanner()
		C.open("thread", id)
		M.settle(0.2)
		deps.sendChat(id, "Hi! Who are you?")
		M.settle(5)
		deps.sendChat(id, "What is 12 * 7?")
		M.settle(5)
		deps.sendChat(id, "Tell me a joke")
		M.settle(5)
	elseif SCREEN == "strip" then
		-- a call rings while the player writes a chat message: the strip on top, the draft stays
		local v = C.view()
		local id = OPT.model or (v and v.models[1] and v.models[1].id) or "nova2"
		Phone.hideBanner()
		C.open("thread", id)
		M.settle(0.2)
		deps.sendChat(id, "Hi! Who are you?")
		M.settle(5)
		local gui = ui.playerGui:FindFirstChild("AIEmpire_Phone")
		local box = gui and gui:FindFirstChild("ChatInput", true)
		if box then box.Text = "Can you write a short poem about our" end
		ui.PhoneService.ring(ui.session, { title = "We can move!", text = "x", kind = "office", accept = "Open Office", decline = "Later", open = "empire", section = "office" })
		M.settle(0.5)
	elseif SCREEN == "finance" then
		local e = ui.session.data.empire
		if STATE == "rich" then
			e.ledger = { ["9"] = { i = { b2b = 63000, market = 4810, guest = 1800 }, o = { wages = 41800, trips = 2520, ops = 3600, market = 2900 } },
				["8"] = { i = { b2b = 54000, market = 4200 }, o = { wages = 40100, trips = 1260, ops = 3600 } } }
		end
		ui.push()
		Phone.hideBanner()
		C.open("finance")
	elseif SCREEN == "message" then
		C.open("message", firstMessage())
	elseif SCREEN == "call" then
		C.open("call", ringingCall())
	elseif SCREEN == "callresult" then
		local id = ringingCall()
		C.open("call", id)
		M.settle(0.2)
		deps.answer(id, "accept")
		M.settle(1)
	elseif SCREEN == "dial" then
		C.open("dial", OPT.contact or "it")
		deps.dial(OPT.contact or "it")
		M.settle(1)
	else
		C.open(SCREEN)
	end
	M.settle(0.5)
	ui.push()
	GuiDump.setViewport(ui.playerGui, VW, VH, INSETS)
	local n = GuiDump.applyFeedback({ ui.playerGui }, FEEDBACK)
	M.settle(0.3)
	local RunService = M.game:GetService("RunService")
	for _ = 1, 30 do
		M.fire(RunService.RenderStepped, 1 / 60)
		M.fire(RunService.Heartbeat, 1 / 60)
	end
	M.settle(0.3)
	GuiDump.dump({ ui.playerGui }, { scene = "phone", screen = SCREEN, state = STATE, viewport = { VW, VH }, insets = INSETS, feedbackChanged = n })
end

setfenv(body, M.envFor(nil))
local ok, res, status = M.runMain(body, { timeout = 600 })
if not ok then print("@@ERROR body crashed (" .. tostring(status) .. "): " .. tostring(res)) end
if M.stats.errors > 0 then print("@@ERROR background thread errors: " .. M.stats.errors) end
