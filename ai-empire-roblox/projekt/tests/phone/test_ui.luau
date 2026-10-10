--!nocheck
-- phone package, client side: the real phone UI (Screens/Phone + UI/Phone/*) driven by the real PhoneController
-- and the real PhoneService handlers in the mock (tests/phone/ui_setup.luau).
--   garage: button without badge, home with the first goal, every app's empty state, Open the Lab, contacts in
--           the garage, the trips setting through the server, hiding behind the Computer / closing for panels,
--           keyboard P, portrait layout left of the HUD column
--   rich:   badge = unread + missed, the ringing call banner -> call screen -> "Join the trip" -> honest answer,
--           messages read on open, message detail, calendar items, AI chat thread (demo replies with the real
--           stats, the filtered user text, the 4 s cooldown line, input length limit), the assistant contact opens
--           her briefing, a call while the Computer is open -> toast, the office call opens the Company app,
--           landscape layout on an iPhone-sized screen, touch layout left of the jump button
-- Run: cd tests/phone && ../../tools/luau test_ui.luau -a .gen_phone [garage|rich]
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_phone")
local ONLY = args[2] or "garage" -- one state per process (run.sh runs both)
local M = require("../../harness/mock")
local setup = require("./ui_setup")
local GuiDump = require("../../tools/guiprev/guidump")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local DESK = { 1280, 720, { top = 58, right = 0, bottom = 0, left = 0 } }
local IPHONE = { 844, 390, { top = 58, right = 47, bottom = 21, left = 47 } }

local function helpers(ui)
	local pg = ui.playerGui
	local gui = pg:FindFirstChild("AIEmpire_Phone")
	local function visible(inst)
		local x = inst
		while x and x ~= pg do
			if (x:IsA("GuiObject") and not x.Visible) or (x:IsA("ScreenGui") and not x.Enabled) then return false end
			x = x.Parent
		end
		return true
	end
	local function texts(root)
		local out = {}
		for _, x in (root or gui):GetDescendants() do
			if (x:IsA("TextLabel") or x:IsA("TextButton")) and visible(x) and x.Text ~= "" then table.insert(out, x.Text) end
		end
		return out
	end
	local function has(needle, root)
		for _, t in texts(root) do if string.find(t, needle, 1, true) then return t end end
		return nil
	end
	local function find(name, root)
		for _, x in (root or gui):GetDescendants() do if x.Name == name and visible(x) then return x end end
		return nil
	end
	local function click(b)
		if not b then return false end
		M.fire(b.Activated, {}, 1)
		M.settle(0.3)
		return true
	end
	local function frame() return gui:FindFirstChild("PhoneFrame") end
	local function button() return gui:FindFirstChild("PhoneButton") end
	local function badge()
		local b = button():FindFirstChild("Badge")
		return if b and b.Visible then tonumber(b:FindFirstChild("Count").Text) else 0
	end
	local function tile(id) return find("App_" .. id) end
	local function tileBadge(id)
		local t = tile(id)
		local b = t and t:FindFirstChild("Badge", true)
		return if b and b.Visible then tonumber(b:FindFirstChild("Count").Text) else 0
	end
	return { gui = gui, visible = visible, texts = texts, has = has, find = find, click = click, frame = frame, button = button, badge = badge, tile = tile, tileBadge = tileBadge }
end

local function garage()
	local ui = setup(M, GEN, "garage", DESK[1], DESK[2], DESK[3])
	local H = helpers(ui)
	local Phone, C = ui.Phone, ui.Controller
	check("garage: the phone has its own ScreenGui", H.gui ~= nil and H.gui:IsA("ScreenGui") and H.gui.DisplayOrder == 15)
	check("garage: phone button visible, phone closed", H.visible(H.button()) and not H.visible(H.frame()))
	check("garage: no badge (nothing unread, no calls)", H.badge() == 0)
	check("garage: portrait layout on a desktop screen", Phone.layoutInfo.landscape == false and Phone.layoutInfo.scale > 0.9, Phone.layoutInfo.scale)
	local hudW = Phone.HUD_WIDTH * Phone.layoutInfo.hudScale
	check("garage: the phone sits left of the HUD column (no overlap)", Phone.layoutInfo.rightEdge >= hudW, Phone.layoutInfo.rightEdge .. " < " .. hudW)
	H.click(H.button())
	check("garage: tapping the button opens the phone", Phone.isOpen() and H.visible(H.frame()))
	check("garage: home shows the first goal from EmpireMath.nextGoal", H.has("Train your first AI") ~= nil)
	check("garage: status bar shows the company day", H.has("Day 1") ~= nil)
	check("garage: status bar shows the company time 10:3x", H.has("10:3") ~= nil, H.has("10:"))
	local tiles = 0
	for _, id in { "messages", "calls", "calendar", "contacts", "chat", "settings" } do if H.tile(id) then tiles += 1 end end
	check("garage: six apps on the home screen", tiles == 6, tiles)
	H.click(H.tile("messages"))
	check("garage: messages empty state", H.has("No messages yet") ~= nil)
	H.click(H.find("NavHome"))
	H.click(H.tile("calls"))
	check("garage: calls empty state", H.has("No calls yet") ~= nil)
	H.click(H.find("Back"))
	check("garage: back goes home", select(1, Phone.screen()) == "home")
	H.click(H.tile("calendar"))
	check("garage: calendar shows the day and office hours", H.has("Office open until 18:00") ~= nil)
	check("garage: no client items in a fresh company", H.has("Check-in visit") == nil and H.has("pilot visit") == nil)
	H.click(H.find("NavHome"))
	H.click(H.tile("contacts"))
	check("garage: driver starts at the Founder HQ", H.has("Starts at the Founder Headquarters") ~= nil)
	H.click(H.find("Contact_reception"))
	M.settle(0.5)
	check("garage: calling reception answers honestly", H.has("no reception yet") ~= nil)
	H.click(H.find("HangUp"))
	H.click(H.find("NavHome"))
	H.click(H.tile("settings"))
	local toggle = H.find("Toggle")
	check("garage: trips setting off by default", toggle ~= nil and ui.PhoneService.setting(ui.session, "autoTrips") == false)
	H.click(toggle)
	M.settle(0.5)
	check("garage: the toggle goes through PhoneAction setting", ui.PhoneService.setting(ui.session, "autoTrips") == true)
	check("garage: honest save state (session only, travel desk coming soon)", H.has("Kept for this session") ~= nil and H.has("coming soon") ~= nil)
	check("garage: phone cost from CompanyOps.PHONE", H.has("0 phones × $10 per game day") ~= nil, H.has("phones"))
	H.click(H.find("NavHome"))
	H.click(H.tile("chat"))
	check("garage: AI chat empty state", H.has("No released model yet") ~= nil)
	H.click(H.find("OpenLab"))
	M.settle(0.5)
	check("garage: Open the Lab opens the Computer and closes the phone", ui.Computer.isOpen() and not Phone.isOpen())
	M.settle(0.5)
	check("garage: phone button hidden while the Computer is open", not H.visible(H.button()))
	ui.Computer.close()
	M.settle(0.6)
	check("garage: button back after the Computer closes", H.visible(H.button()))
	-- keyboard P
	local uis = M.game:GetService("UserInputService")
	M.fire(uis.InputBegan, { KeyCode = Enum.KeyCode.P, UserInputType = Enum.UserInputType.Keyboard }, false)
	M.settle(0.2)
	check("garage: P opens the phone", Phone.isOpen())
	M.fire(uis.InputBegan, { KeyCode = Enum.KeyCode.P, UserInputType = Enum.UserInputType.Keyboard }, true)
	check("garage: P while typing (processed) does nothing", Phone.isOpen())
	check("garage: the phone reopens on the last screen (AI Chat)", select(1, Phone.screen()) == "chat", select(1, Phone.screen()))
	M.fire(uis.InputBegan, { KeyCode = Enum.KeyCode.ButtonB, UserInputType = Enum.UserInputType.Gamepad1 }, true)
	check("garage: gamepad B goes back (to home)", Phone.isOpen() and select(1, Phone.screen()) == "home", select(1, Phone.screen()))
	M.fire(uis.InputBegan, { KeyCode = Enum.KeyCode.ButtonB, UserInputType = Enum.UserInputType.Gamepad1 }, true)
	check("garage: gamepad B on the home screen closes the phone", not Phone.isOpen())
	M.fire(uis.InputBegan, { KeyCode = Enum.KeyCode.ButtonY, UserInputType = Enum.UserInputType.Gamepad1 }, false)
	check("garage: gamepad Y opens the phone", Phone.isOpen())
	-- a talk panel in the middle of the screen closes the phone
	local talk = Instance.new("ScreenGui")
	talk.Name = "TalkPanel"
	talk.Parent = ui.playerGui
	M.settle(0.1)
	check("garage: a talk panel closes the phone", not Phone.isOpen())
	talk:Destroy()
	-- no company -> no phone
	ui.session.data.company = nil
	ui.push()
	M.settle(0.5)
	check("garage: no company -> phone button hidden", not H.visible(H.button()))
end

local function rich()
	local ui = setup(M, GEN, "rich", DESK[1], DESK[2], DESK[3])
	local H = helpers(ui)
	local Phone, C = ui.Phone, ui.Controller
	local v = C.view()
	check("rich: 3 new log lines + today's absence are unread", v.unread == 4 or v.unread == 3, v.unread)
	check("rich: badge = unread + missed/ringing calls", H.badge() == v.unread + 2, H.badge())
	check("rich: ringing call -> banner next to the button", H.visible(H.find("CallBanner")) and H.has("Assistant is calling") ~= nil)
	check("rich: banner title is the call title", H.has("Helix Research wants to meet") ~= nil)
	H.click(H.find("Answer"))
	check("rich: Answer opens the phone on the call screen", Phone.isOpen() and select(1, Phone.screen()) == "call")
	check("rich: call screen shows the itinerary text with the real hotel and flight", H.has("Meridian Grand Hotel") ~= nil and H.has("PM 101") ~= nil)
	check("rich: call buttons carry the call's labels", H.has("Join the trip") ~= nil and H.has("Not this time") ~= nil)
	H.click(H.find("Accept"))
	M.settle(0.5)
	check("rich: accepting without the itinerary package -> 'travel desk opens soon'", H.has("travel desk opens soon") ~= nil, table.concat(H.texts(), " | "))
	local accepted = false
	for _, c in ui.PhoneService.calls(ui.session) do if c.kind == "itinerary" and c.state == "accepted" then accepted = true end end
	check("rich: the server call log has the call accepted", accepted)
	check("rich: Done button after the answer", H.find("Done") ~= nil)
	H.click(H.find("Done"))
	check("rich: home badge for messages", H.tileBadge("messages") == v.unread, H.tileBadge("messages"))
	check("rich: home shows the latest message and the next calendar entry", H.find("Latest") ~= nil and H.find("NextItem") ~= nil)
	H.click(H.tile("messages"))
	check("rich: newest message first (Signed Atlas Search)", H.has("Signed Atlas Search") ~= nil)
	check("rich: older log lines listed too", H.has("Trip to Helix Research") ~= nil and H.has("Welcome Mia Chen") ~= nil)
	M.settle(0.3)
	check("rich: opening the inbox reads it", C.view().unread == 0, C.view().unread)
	local first = H.find("Message")
	H.click(first)
	check("rich: message detail with sender and body", H.has("New client Atlas Search: pilot $36,000, $36,000/day.") ~= nil and H.has("GOOD NEWS") ~= nil)
	H.click(H.find("NavHome"))
	check("rich: messages badge cleared", H.tileBadge("messages") == 0)
	H.click(H.tile("calls"))
	check("rich: call log lists the missed call", H.has("First client signed!") ~= nil and H.has("Missed") ~= nil)
	M.settle(0.3)
	check("rich: opening Calls marks missed calls seen", C.view().missed == 0, C.view().missed)
	H.click(H.find("NavHome"))
	H.click(H.tile("calendar"))
	check("rich: calendar lists the trip abroad with its return", H.has("pilot visit at Helix Research") ~= nil and H.has("Port Meridian") ~= nil)
	check("rich: calendar lists the ByteWorks check-in visit", H.has("Check-in visit: ByteWorks") ~= nil)
	check("rich: calendar lists the guest-house team", H.has("Atlas Search team at our guest house") ~= nil)
	H.click(H.find("NavHome"))
	-- AI chat
	H.click(H.tile("chat"))
	check("rich: released models listed, retired version marked", H.has("Nova v2") ~= nil and H.has("RETIRED") ~= nil and H.has("Sage v1") ~= nil)
	H.click(H.find("Model"))
	local name, id = Phone.screen()
	check("rich: tapping a model opens its thread", name == "thread" and id ~= nil)
	local model = ui.session.data.models[id]
	local box = H.find("ChatInput")
	box.Text = "Who are you?"
	H.click(H.find("Send"))
	M.settle(1)
	check("rich: the player's line in the thread", H.has("Who are you?") ~= nil)
	check("rich: reply labelled 'Demo reply (offline)' (TextGenerator not available in the mock)", H.has("Demo reply (offline)") ~= nil)
	check("rich: the demo reply uses the model's real overall", H.has("overall score is " .. math.floor(model.overall)) ~= nil, model.overall)
	check("rich: input cleared after sending", box.Text == "")
	box.Text = "again"
	H.click(H.find("Send"))
	M.settle(0.5)
	check("rich: a second message within 4 s -> wait line, nothing sent", H.has("before your next message") ~= nil)
	M.settle(4)
	box.Text = "What is 12 * 7?"
	H.click(H.find("Send"))
	M.settle(1)
	local replies = 0
	for _, t in H.texts() do if t == "Demo reply (offline)" then replies += 1 end end
	check("rich: after the cooldown the next question is answered", replies == 2, replies)
	box.Text = string.rep("x", 250)
	M.settle(0.1)
	check("rich: the input is cut to 200 characters", utf8.len(box.Text) == 200, utf8.len(box.Text))
	box.Text = ""
	check("rich: chat history only in memory (not in the save)", ui.session.data.empire.chat == nil and ui.session.data.chat == nil)
	H.click(H.find("HeaderAction"))
	M.settle(0.3)
	check("rich: Clear empties the thread", H.has("Who are you?") == nil)
	H.click(H.find("NavHome"))
	-- assistant contact opens her briefing
	H.click(H.tile("contacts"))
	H.click(H.find("Contact_assistant"))
	M.settle(0.5)
	check("rich: the assistant contact opens her briefing panel", ui.playerGui:FindFirstChild("PeopleAssistant") ~= nil)
	check("rich: and the phone closes", not Phone.isOpen())
	local briefing = ui.playerGui:FindFirstChild("PeopleAssistant")
	if briefing then briefing:Destroy() end
	-- a call while the Computer is open: toast, no banner
	ui.Computer.open("empire")
	M.settle(0.5)
	ui.PhoneService.ring(ui.session, { title = "Test call", text = "x", kind = "info" })
	M.settle(0.3)
	local top = ui.playerGui:FindFirstChild("AIEmpire_Top")
	check("rich: a call while the Computer is open -> toast", top and H.has("called: Test call", top) ~= nil)
	check("rich: no banner while hidden", H.find("CallBanner") == nil and Phone.isHidden())
	ui.Computer.close()
	M.settle(0.6)
	-- the office call opens the Company app
	local id2 = ui.PhoneService.ring(ui.session, { title = "We can move!", text = "x", kind = "office", accept = "Open offices", decline = "Later", open = "empire" })
	M.settle(0.3)
	C.open("call", id2)
	H.click(H.find("Accept"))
	M.settle(0.5)
	check("rich: accepting the office call opens the Company app", ui.Computer.isOpen() and not Phone.isOpen())
	ui.Computer.close()
	M.settle(0.6)
	-- iPhone landscape
	GuiDump.setViewport(ui.playerGui, IPHONE[1], IPHONE[2], IPHONE[3])
	M.settle(0.2)
	Phone.layout()
	check("rich: iPhone-sized screen -> landscape phone", Phone.layoutInfo.landscape == true, Phone.layoutInfo.landscape)
	check("rich: landscape phone is readable (scale >= 0.9)", Phone.layoutInfo.scale >= 0.9, Phone.layoutInfo.scale)
	local hudW = Phone.HUD_WIDTH * Phone.layoutInfo.hudScale
	check("rich: landscape phone left of the HUD column", Phone.layoutInfo.rightEdge >= hudW, Phone.layoutInfo.rightEdge .. " < " .. hudW)
	local size = H.gui.AbsoluteSize
	local frameW = Phone.LANDSCAPE.X * Phone.layoutInfo.scale
	check("rich: landscape phone fits on the screen", Phone.layoutInfo.rightEdge + frameW <= size.X and Phone.LANDSCAPE.Y * Phone.layoutInfo.scale <= size.Y, frameW)
	C.open("home")
	check("rich: landscape home builds both columns", H.find("Left") ~= nil and H.find("Right") ~= nil)
	C.open("call", id2)
	check("rich: landscape call screen builds", H.find("CallText") ~= nil)
	Phone.close()
	-- touch: the button moves left of Roblox's jump button
	local uis = M.game:GetService("UserInputService")
	uis[M.KEY].props.TouchEnabled = true
	uis[M.KEY].props.MouseEnabled = false
	local touchGui = Instance.new("ScreenGui"); touchGui.Name = "TouchGui"; touchGui.Parent = ui.playerGui
	local tcf = Instance.new("Frame"); tcf.Name = "TouchControlFrame"; tcf.Parent = touchGui
	local jump = Instance.new("ImageButton"); jump.Name = "JumpButton"; jump.Parent = tcf
	local gp = H.gui.AbsolutePosition
	jump[M.KEY].props.AbsolutePosition = Vector2.new(gp.X + size.X - 48, gp.Y + size.Y - 69)
	jump[M.KEY].props.AbsoluteSize = Vector2.new(70, 70)
	Phone.layout()
	local b = H.button()
	local right = -b.Position.X.Offset
	local bpx = Phone.BUTTON * Phone.layoutInfo.buttonScale
	check("rich: touch -> phone button left of the jump button", size.X - right <= size.X - 48 - 9 and size.X - right - bpx >= 0, right)
	uis[M.KEY].props.TouchEnabled = false
	uis[M.KEY].props.MouseEnabled = true
end

local function body()
	if ONLY == "rich" then rich() else garage() end
end
local ENV = M.envFor(nil)
setfenv(garage, ENV)
setfenv(rich, ENV)
setfenv(helpers, ENV)

setfenv(body, M.envFor(nil))
local ok, res = M.runMain(body, { timeout = 900 })
if not ok then failc += 1; print("FAIL  body crashed: " .. tostring(res)) end
if M.stats.errors > 0 then failc += 1; print("FAIL  background errors: " .. M.stats.errors) end
print(string.format("phone_ui_%s: %d passed, %d failed", ONLY, pass, failc))
