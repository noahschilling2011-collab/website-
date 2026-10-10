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
--   fixes:  the review round's scenarios: 40+ chat turns keep their sides, a call while typing (strip + draft),
--           pop-ups off while open, missed calls (server notice + client expiry), cash ticks and a running play
--           clock rebuild nothing and keep the gamepad selection, PHONE_UPDATE payloads (no refetch) and coalesced
--           / retried refetches, the field staff's arrival report, draw order and the flight panel, the Map, Finance
--           and Team apps, settings rows, the honesty label size, the public shuttle never as "next"
--   touch:  a 667 x 375 touch phone: banner scale and 48 px call buttons, the phone left of the phone button,
--           the whole banner answers, 36 px navigation, Clear / Send / settings row sizes
-- Run: cd tests/phone && ../../tools/luau test_ui.luau -a .gen_phone [garage|rich|fixes|touch]
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
	local hudFrame = ui.playerGui:FindFirstChild("AIEmpire_HUD"):FindFirstChild("Root"):FindFirstChild("HUD")
	check("garage: the phone takes the HUD lane from the HUD frame's LaneWidth attribute", Phone.layoutInfo.hudLane == hudFrame:GetAttribute("LaneWidth"),
		tostring(Phone.layoutInfo.hudLane) .. " vs " .. tostring(hudFrame:GetAttribute("LaneWidth")))
	local hudW = hudFrame:GetAttribute("LaneWidth") * Phone.layoutInfo.hudScale
	check("garage: the phone sits left of the HUD column (no overlap)", Phone.layoutInfo.rightEdge >= hudW, Phone.layoutInfo.rightEdge .. " < " .. hudW)
	H.click(H.button())
	check("garage: tapping the button opens the phone", Phone.isOpen() and H.visible(H.frame()))
	check("garage: home shows the first goal from EmpireMath.nextGoal", H.has("Train your first AI") ~= nil)
	check("garage: the phone's Today card (not a copy of the HUD goal card): who is at work + the goal in one line",
		H.find("TodayCard") ~= nil and H.has("Just you in the garage so far.") ~= nil and H.has("Next goal: Train your first AI") ~= nil and H.find("GoalCard") == nil,
		table.concat(H.texts(H.find("TodayCard")), " | "))
	check("garage: no public shuttle in a garage company's calendar, nothing as 'next in your calendar'", #C.view().calendar == 0 and C.view().nextItem == nil and H.find("NextItem") == nil, #C.view().calendar)
	check("garage: status bar shows the company day", H.has("Day 1") ~= nil)
	check("garage: status bar shows the company time 10:3x", H.has("10:3") ~= nil, H.has("10:"))
	local tiles = 0
	for _, id in { "messages", "calls", "calendar", "contacts", "chat", "map", "finance", "team", "settings" } do if H.tile(id) then tiles += 1 end end
	check("garage: nine apps on the home screen (with map, finance and team)", tiles == 9, tiles)
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
	-- the thread follows the newest bubble while the canvas grows, until the player scrolls up
	local thread = H.find("Thread")
	local tlist = thread and thread:FindFirstChildOfClass("Frame")
	local function grow(h)
		tlist[M.KEY].props.AbsoluteSize = Vector2.new(300, h)
		M.firePropChanged(tlist, tlist[M.KEY], "AbsoluteSize")
		M.settle(0.1)
	end
	grow(900)
	check("rich: the thread follows the newest bubble when the list grows", thread.CanvasPosition.Y >= 900, thread.CanvasPosition.Y)
	thread.CanvasPosition = Vector2.new(0, 120)
	M.settle(0.1)
	grow(1000)
	check("rich: scrolled up to read -> a growing list does not pull the thread down", thread.CanvasPosition.Y == 120, thread.CanvasPosition.Y)
	M.settle(4)
	box.Text = "thanks"
	H.click(H.find("Send"))
	M.settle(1)
	check("rich: a new message scrolls to the newest bubble again", thread.CanvasPosition.Y >= 1000, thread.CanvasPosition.Y)
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
	-- phones: the HUD column has its own UIScale (compact boost), so its lane is wider than 300 + 16
	local hudFrame = ui.playerGui:FindFirstChild("AIEmpire_HUD"):FindFirstChild("Root"):FindFirstChild("HUD")
	local lane = hudFrame:GetAttribute("LaneWidth")
	check("rich: on the iPhone the phone follows the compact HUD's wider lane", hudFrame:GetAttribute("Compact") ~= true or (Phone.layoutInfo.hudLane == lane and lane > Phone.HUD_WIDTH),
		tostring(hudFrame:GetAttribute("Compact")) .. " " .. tostring(Phone.layoutInfo.hudLane) .. " vs " .. tostring(lane))
	local hudW = lane * Phone.layoutInfo.hudScale
	check("rich: landscape phone left of the HUD column", Phone.layoutInfo.rightEdge >= hudW, Phone.layoutInfo.rightEdge .. " < " .. hudW)
	local size = H.gui.AbsoluteSize
	local frameW = Phone.layoutInfo.width * Phone.layoutInfo.scale
	check("rich: landscape phone fits on the screen", Phone.layoutInfo.rightEdge + frameW <= size.X and Phone.LANDSCAPE.Y * Phone.layoutInfo.scale <= size.Y, frameW)
	C.open("home")
	check("rich: landscape home builds both columns", H.find("Left") ~= nil and H.find("Right") ~= nil)
	C.open("call", id2)
	check("rich: landscape call screen builds", H.find("CallText") ~= nil)
	local id3 = ui.PhoneService.ring(ui.session, { title = "Helix Research wants to meet", text = string.rep("A long itinerary line with the flight, the hotel and who travels. ", 6), kind = "itinerary" })
	M.settle(0.3)
	C.open("call", id3)
	M.settle(0.2)
	local decision, acceptBtn, bodyScroll = H.find("Decision"), H.find("Accept"), H.find("Body")
	check("rich: landscape call: Decline / Accept sit in a fixed bar outside the scrolling text (always visible)",
		decision ~= nil and acceptBtn ~= nil and acceptBtn:IsDescendantOf(decision) and bodyScroll ~= nil and not acceptBtn:IsDescendantOf(bodyScroll))
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


-- review round 1 (rich state, desktop): every issue of the review as a scenario on the real UI + server
local function fixes()
	local ui = setup(M, GEN, "rich", DESK[1], DESK[2], DESK[3])
	local H = helpers(ui)
	local Phone, C = ui.Phone, ui.Controller
	local Ops = M.require(M.game.ReplicatedStorage.Shared.CompanyOps)
	local uis = M.game:GetService("UserInputService")
	local GuiService = M.game:GetService("GuiService")
	local e = ui.session.data.empire
	local content = H.frame():FindFirstChild("Screen"):FindFirstChild("Content")
	-- count the PhoneAction calls the client makes (by action)
	local counts = {}
	local failNext = nil
	local realHandler = ui.binds.PhoneAction
	ui.binds.PhoneAction = function(sess, payload)
		local a = tostring(payload and payload.action)
		counts[a] = (counts[a] or 0) + 1
		if failNext and failNext == a then failNext = nil; return { ok = false, err = "RATE_LIMIT" } end
		return realHandler(sess, payload)
	end
	Phone.hideBanner()

	-- 1. the chat thread past CHAT_TURNS: every bubble on the right side, newest last
	C.open("thread", "coder")
	M.settle(0.3)
	for i = 1, 24 do
		C.deps.sendChat("coder", "question number " .. i)
		if i == 22 then
			M.settle(1)
			C.deps.sendChat("coder", "too fast") -- a "Wait n s" line: an odd number of turns is trimmed
		end
		M.settle(6.5)
	end
	local chat = C.view().chats.coder
	local byId = {}
	for _, t in chat.turns do byId[t.id] = t end
	local list = H.find("Thread"):FindFirstChildOfClass("Frame")
	local bad, n, maxOrder, lastText = 0, 0, -1, nil
	for _, child in list:GetChildren() do
		if child.Name == "Turn" and child.LayoutOrder > 0 then
			n += 1
			local turn = byId[child.LayoutOrder]
			local side = if child:FindFirstChild("You") then "you" elseif child:FindFirstChild("Model") then "model" else "system"
			local want = if turn == nil then "gone" elseif turn.who == "you" then "you" elseif turn.who == "system" then "system" else "model"
			if side ~= want then bad += 1 end
			if child.LayoutOrder > maxOrder then maxOrder = child.LayoutOrder; local t = child:FindFirstChild("Text", true); lastText = t and t.Text end
		end
	end
	check("fixes: 40 turns kept, 40 bubbles drawn", #chat.turns == C.CHAT_TURNS and n == #chat.turns, #chat.turns .. " / " .. n)
	check("fixes: after trimming every bubble keeps its side (player right, model left)", bad == 0, bad .. " of " .. n)
	check("fixes: the newest reply is the last bubble", lastText == tostring(chat.turns[#chat.turns].text), tostring(lastText))
	local label = H.find("Label")
	check("fixes: the 'Demo reply (offline)' label is as readable as the text (>= 13 px)", label and label.TextSize >= 13 and label.Text == "Demo reply (offline)", label and label.TextSize)

	-- 2. a call while the player writes: a strip, the screen stays, the draft survives
	local box = H.find("ChatInput")
	box.Text = "half a sentence I am still typ"
	M.settle(0.1)
	local cid = ui.PhoneService.ring(ui.session, { title = "We can move!", text = "x", kind = "office", accept = "Open Office", decline = "Later", open = "empire", section = "office" })
	M.settle(0.5)
	check("fixes: a call while the chat thread is open does not take over the screen", select(1, Phone.screen()) == "thread" and H.find("ChatInput") == box and box.Text == "half a sentence I am still typ", select(1, Phone.screen()))
	check("fixes: it shows a call strip on top of the phone instead", Phone.stripCall() == cid and H.find("CallStrip") ~= nil)
	H.click(H.find("CallStrip"):FindFirstChild("Answer", true))
	check("fixes: Answer on the strip opens the call screen", select(1, Phone.screen()) == "call" and H.find("CallStrip") == nil)
	Phone.back()
	M.settle(0.2)
	local box2 = H.find("ChatInput")
	check("fixes: back in the thread the unsent draft is still there", box2 and box2.Text == "half a sentence I am still typ", box2 and box2.Text)
	local cid2 = ui.PhoneService.ring(ui.session, { title = "Another call", text = "y", kind = "info" })
	M.settle(0.3)
	Phone.close()
	M.settle(0.2)
	check("fixes: closing the phone moves a ringing strip call to the banner", Phone.bannerCall() == cid2 and Phone.stripCall() == nil, tostring(Phone.bannerCall()))
	C.deps.answer(cid2, "decline") -- answered somewhere else (e.g. from the Calls list)
	M.settle(0.5)
	check("fixes: a call that stops ringing takes its banner with it", Phone.bannerCall() == nil, tostring(Phone.bannerCall()))
	Phone.hideBanner()
	C.deps.setSetting("popups", false)
	C.open("home")
	M.settle(0.2)
	local missed0 = C.view().missed
	ui.PhoneService.ring(ui.session, { title = "Quiet call", text = "z", kind = "info" })
	M.settle(0.3)
	check("fixes: 'Call pop-ups: Off' is honoured while the phone is open (no takeover, no strip)", select(1, Phone.screen()) == "home" and Phone.stripCall() == nil, select(1, Phone.screen()))
	check("fixes: ... the call still counts on the Calls badge", C.view().missed >= missed0)
	C.deps.setSetting("popups", true)

	-- 3. a ringing call the server already marked missed / that ran out on the client
	M.settle(30)
	C.open("calls")
	M.settle(0.3)
	check("fixes: after the ring time the Calls screen no longer says 'Incoming'", H.has("Incoming") == nil, table.concat(H.texts(content), " | "))
	local lone = ui.PhoneService.ring(ui.session, { title = "Client-only expiry", text = "q", kind = "info" })
	M.settle(0.2)
	for _, c in C.view().calls do if c.id == lone then c.at -= 100 end end -- as if the server's notice got lost
	C.publish()
	local st = nil
	for _, c in C.view().calls do if c.id == lone then st = c.state end end
	check("fixes: the phone itself treats a ringing call past its ring time as missed", st == "missed", st)

	-- 4. home: cash ticks rebuild nothing and keep the gamepad selection
	uis[M.KEY].props.GamepadEnabled = true
	Phone.hideBanner()
	C.open("home")
	M.settle(0.3)
	local cardFrame = H.find("TodayCard")
	local tile = H.find("App_settings")
	GuiService.SelectedObject = tile
	local rebuilt, moved = 0, 0
	for _ = 1, 5 do
		ui.session.data.money += 137
		ui.push()
		M.settle(1.1)
		if H.find("TodayCard") ~= cardFrame then rebuilt += 1; cardFrame = H.find("TodayCard") end
		if GuiService.SelectedObject ~= tile then moved += 1; tile = H.find("App_settings"); GuiService.SelectedObject = tile end
	end
	check("fixes: 5 cash ticks rebuild the home screen 0 times", rebuilt == 0, rebuilt)
	check("fixes: ... and never move the gamepad selection", moved == 0, moved)
	table.insert(e.deals.news, 1, "day 9 10:40: renewed Pixel Games for 6 days")
	ui.push()
	M.settle(0.5)
	local sel = GuiService.SelectedObject
	check("fixes: a real change (new message) rebuilds the home screen but the gamepad stays on the same tile", H.find("TodayCard") ~= cardFrame and sel and sel.Name == "App_settings" and sel.Parent ~= nil, sel and sel.Name)
	uis[M.KEY].props.GamepadEnabled = false
	local v = C.view()
	check("fixes: the public shuttle is never 'next in your calendar'", v.nextItem == nil or v.nextItem.public ~= true)
	local hasShuttle = false
	for _, it in v.calendar do if it.public then hasShuttle = true end end
	check("fixes: at the Innovation Campus the calendar lists the public shuttle timetable", hasShuttle)

	-- 5. the open calendar while the play clock ticks: no rebuilds, no jitter (a rebuild is only allowed when
	-- the list itself changed, e.g. the next public shuttle replaced the one that just left)
	C.open("calendar")
	M.settle(0.3)
	local first = H.find("Today")
	local function keyOrder()
		local ks = {}
		for _, it in C.view().calendar do table.insert(ks, it.key) end
		return table.concat(ks, ",")
	end
	local order0 = keyOrder()
	local rebuilds, details = 0, {}
	local function sample()
		C.publish() -- the phone's own 1 s tick runs at any phase between two snapshots
		for _, it in C.view().calendar do if string.sub(it.key, 1, 5) == "trip:" then details[it.key] = details[it.key] or {}; details[it.key][it.detail] = true end end
	end
	for _ = 1, 20 do
		M.settle(0.25)
		sample()
		M.settle(0.5)
		sample()
		e.seconds += 1 -- the server's play clock steps once per second
		ui.push()
		M.settle(0.25)
		local order1 = keyOrder()
		if H.find("Today") ~= first then
			if order1 == order0 then rebuilds += 1 end
			first = H.find("Today")
		end
		order0 = order1
	end
	local variants = 0
	for _, set in details do variants = math.max(variants, (function() local k = 0 for _ in set do k += 1 end return k end)()) end
	check("fixes: 20 s with a running play clock: no rebuild of the open calendar unless its list changed", rebuilds == 0, rebuilds)
	check("fixes: ... and every trip keeps one detail text (no minute jitter)", variants == 1, variants)

	-- 6. PHONE_UPDATE carries the new items: no refetch; bursts without payload are coalesced and retried
	local c0, i0 = counts.calendar or 0, counts.inbox or 0
	for k = 1, 5 do ui.PhoneService.addCalendarItem(ui.session, { key = "itin" .. k, title = "Itinerary step " .. k, at = ui.base + M.Sched.now + 600 + k * 60, kind = "flight" }) end
	for k = 1, 3 do ui.PhoneService.message(ui.session, { from = "Travel desk", title = "Booked step " .. k, text = "ok" }) end
	M.settle(1)
	local items, msgs = 0, 0
	for _, it in C.view().calendar do if string.find(it.key, "item:itin", 1, true) then items += 1 end end
	for _, m in C.view().messages do if string.find(m.title, "Booked step", 1, true) then msgs += 1 end end
	check("fixes: 5 calendar items + 3 messages in one tick arrive with their notices (all shown)", items == 5 and msgs == 3, items .. " / " .. msgs)
	check("fixes: ... without a single refetch", (counts.calendar or 0) == c0 and (counts.inbox or 0) == i0, ((counts.calendar or 0) - c0) .. " / " .. ((counts.inbox or 0) - i0))
	local st2 = ui.PhoneService._state(ui.session)
	table.insert(st2.messages, 1, { id = "mx", from = "Company", title = "Silent message", body = "b", tone = "info", day = 9, hour = 10 })
	for _ = 1, 5 do C._onNotify("PHONE_UPDATE", { what = "messages" }) end
	M.settle(1)
	check("fixes: 5 notices without payload -> one coalesced inbox fetch", (counts.inbox or 0) == i0 + 1, (counts.inbox or 0) - i0)
	table.insert(st2.messages, 1, { id = "my", from = "Company", title = "After a rate limit", body = "b", tone = "info", day = 9, hour = 10 })
	failNext = "inbox"
	C._onNotify("PHONE_UPDATE", { what = "messages" })
	M.settle(4)
	local after = false
	for _, m in C.view().messages do if m.title == "After a rate limit" then after = true end end
	check("fixes: a RATE_LIMIT answer is retried and the message arrives", after and (counts.inbox or 0) == i0 + 3, (counts.inbox or 0) - i0)

	-- 7. field staff report: arrived, checked in
	table.insert(e.deals.tripList, { client = "delta", kind = "sign", back = e.seconds + 800, founder = false, hosted = false, crew = 2, left = e.seconds - 200 })
	ui.push()
	M.settle(0.3)
	local arrived = nil
	for _, m in C.view().messages do if m.title == "Arrived in Business City" then arrived = m end end
	check("fixes: a region trip's travellers report 'Arrived in Business City' and the hotel", arrived and string.find(arrived.body, "checked in at the City Hotel", 1, true) ~= nil
		and string.find(arrived.body, "Delta Robotics", 1, true) ~= nil and arrived.from == "Travel desk", arrived and arrived.body)
	check("fixes: the report arrived during the session, so it is unread", arrived and not C.view().read[arrived.key])
	local arr = C._shuttleArrive(ui.base + 1000)
	check("fixes: the abroad arrival comes from the FlightPlan timetable (after the trip left)", typeof(arr) == "number" and arr > ui.base + 1000, arr)

	-- 8. panels, draw order
	C.open("home")
	check("fixes: the open phone draws above the shuttle pass (DisplayOrder 28)", H.gui.DisplayOrder == 28, H.gui.DisplayOrder)
	local fc = Instance.new("ScreenGui"); fc.Name = "FlightChoice"; fc.Parent = ui.playerGui
	M.settle(0.1)
	check("fixes: the flight choice panel closes the phone", not Phone.isOpen())
	check("fixes: closed, the phone layer goes back to DisplayOrder 15", H.gui.DisplayOrder == 15)
	fc:Destroy()

	-- 9. map, finance, team (pop-ups off: the cash ticks below may make the next office affordable, and the
	-- assistant's "We can move!" call would rightly take over the screen)
	C.deps.setSetting("popups", false)
	local okT, Travel = pcall(M.require, M.game.StarterPlayer.StarterPlayerScripts.Client.Controllers.TravelController)
	local guided = nil
	if okT then
		Travel.guide = function(id) guided = id end
		Travel.active = function() return true end
	end
	C.open("map")
	M.settle(0.2)
	check("fixes: the Map app lists My HQ, your clients and Port Meridian", H.find("Place_home") ~= nil and H.has("Pixel Games") ~= nil and H.has("your client") ~= nil and H.has("Port Meridian · fly from City Airport") ~= nil,
		table.concat(H.texts(content), " | "))
	check("fixes: an active route can be cleared from the Map", H.find("ClearRoute") ~= nil)
	H.click(H.find("Place_pixelgames"))
	check("fixes: tapping a place starts the GPS route (TravelController.guide) and closes the phone", guided == "pixelgames" and not Phone.isOpen(), tostring(guided))
	e.ledger = { ["9"] = { i = { b2b = 50000, market = 1200 }, o = { wages = 30000, trips = 2520 } }, ["8"] = { i = { b2b = 40000 }, o = { wages = 28000 } } }
	ui.push()
	C.open("finance")
	M.settle(0.2)
	local cashLabel = H.find("CashValue")
	check("fixes: Finance shows the real cash", cashLabel and cashLabel.Text == Ops.money(ui.session.data.money), cashLabel and cashLabel.Text)
	check("fixes: Finance shows today's ledger (income, costs, net) and yesterday", H.find("Income").Text == "+$51,200" and H.find("Costs").Text == "-$32,520" and H.find("Net").Text == "+$18,680"
		and H.has("+$12,000") ~= nil, H.find("Income").Text .. " " .. H.find("Costs").Text .. " " .. H.find("Net").Text)
	check("fixes: Finance uses the Company app's category names", H.has("Client retainers") ~= nil and H.has("Wages") ~= nil)
	local cashBox = H.find("Cash")
	ui.session.data.money += 999
	ui.push()
	M.settle(1.1)
	check("fixes: a cash tick updates the number in place (no rebuild)", H.find("Cash") == cashBox and cashLabel.Text == Ops.money(ui.session.data.money), cashLabel.Text)
	H.click(H.find("OpenMoney"))
	M.settle(0.3)
	check("fixes: 'Open Company → Money' opens the Company app", ui.Computer.isOpen() and not Phone.isOpen())
	ui.Computer.close()
	M.settle(0.6)
	C.open("team")
	M.settle(0.2)
	check("fixes: Team shows staff and desks of the office", H.find("Desks") and H.find("Desks").Text == "88 / 128 desks", H.find("Desks") and H.find("Desks").Text)
	check("fixes: Team lists the roles with their real counts", H.has("Growth & Sales") ~= nil and H.has("30") ~= nil)
	C.deps.setSetting("popups", true)
	-- 10. settings: the whole row flips the switch
	C.open("settings")
	M.settle(0.2)
	local before = ui.PhoneService.setting(ui.session, "autoTrips")
	H.click(H.find("Setting_autoTrips"):FindFirstChild("Row"))
	M.settle(0.4)
	check("fixes: tapping the settings row (not only the small switch) flips it", ui.PhoneService.setting(ui.session, "autoTrips") == not before)
	check("fixes: both settings say they are kept for this session", H.has("Kept for this session.") ~= nil and H.find("PopupState") ~= nil)
end

-- review round 1 (rich state on a small touch phone, 667 x 375 landscape): touch targets and placement
local function touchMode()
	local ui = setup(M, GEN, "rich", 667, 375, { top = 58, right = 0, bottom = 0, left = 0 }, { touch = true })
	local H = helpers(ui)
	local Phone, C = ui.Phone, ui.Controller
	local L = Phone.layoutInfo
	Phone.layout()
	check("touch: landscape phone", L.landscape == true, L.landscape)
	check("touch: the call banner is at least full size on touch screens", L.bannerScale >= 1, L.bannerScale)
	local ans, dec = H.find("Answer"), H.find("Decline")
	check("touch: Answer and Decline are 48 px buttons", ans and dec and ans.Size.X.Offset >= 48 and dec.Size.X.Offset >= 48, ans and ans.Size.X.Offset)
	local gap = ans and dec and (-dec.Position.X.Offset) - dec.Size.X.Offset - (-ans.Position.X.Offset)
	check("touch: with at least 16 px between them", gap and gap >= 16, gap)
	local bpx = Phone.BUTTON * L.buttonScale
	check("touch: the phone sits left of the phone button (no overlap with the bezel)", L.rightEdge >= L.buttonRight + bpx + Phone.MARGIN - 0.01, L.rightEdge .. " < " .. (L.buttonRight + bpx + Phone.MARGIN))
	check("touch: still readable next to the wide compact HUD lane (the landscape phone narrows before it shrinks)", L.scale >= 0.82,
		string.format("gui %s hudScale %.3f lane %s rightEdge %.1f scale %.3f width %.1f", tostring(ui.playerGui:FindFirstChild("AIEmpire_Phone").AbsoluteSize), L.hudScale, tostring(L.hudLane), L.rightEdge, L.scale, L.width))
	check("touch: ... and stays between 520 and 580 design px wide, fully on the screen", L.width >= Phone.LANDSCAPE_MIN_W and L.width <= Phone.LANDSCAPE.X
		and L.rightEdge + L.width * L.scale <= ui.playerGui:FindFirstChild("AIEmpire_Phone").AbsoluteSize.X + 0.01, L.width)
	H.click(H.find("CallBanner"):FindFirstChild("Card"))
	check("touch: the whole banner card answers the call", Phone.isOpen() and select(1, Phone.screen()) == "call")
	local nav = H.frame():FindFirstChild("Screen"):FindFirstChild("NavBar")
	check("touch: the navigation bar keeps 36 px in landscape", nav.Size.Y.Offset >= 36, nav.Size.Y.Offset)
	local back = H.find("NavBack")
	check("touch: back / close are 88 px wide", back.Size.X.Offset >= 88, back.Size.X.Offset)
	C.open("thread", "coder")
	M.settle(0.2)
	local clear = H.find("HeaderAction")
	check("touch: Clear is an 88 x 44 tap target (visible pill 80 x 36)", clear.Size.X.Offset >= 88 and clear.Size.Y.Offset >= 44 and clear:FindFirstChild("Pill") ~= nil,
		clear.Size.X.Offset .. " x " .. clear.Size.Y.Offset)
	local hb = H.find("Back")
	check("touch: the header back button is a 44 px tap target", hb and hb.Size.X.Offset >= 44 and hb.Size.Y.Offset >= 44, hb and hb.Size.Y.Offset)
	check("touch: Send is 44 x 44", H.find("Send").Size.X.Offset >= 44 and H.find("Send").Size.Y.Offset >= 44)
	C.open("settings")
	M.settle(0.2)
	check("touch: a settings row is a 44 px tap target", H.find("Row").Size.Y.Offset >= 44)
	C.open("home")
	M.settle(0.2)
	check("touch: landscape home with nine apps builds", H.find("App_team") ~= nil and H.find("TodayCard") ~= nil)
	-- a narrower HUD lane (the HUD publishes a new LaneWidth): the layout follows by itself, and where the phone
	-- button reaches further left than the lane the phone keeps left of the button
	local hudFrame = ui.playerGui:FindFirstChild("AIEmpire_HUD"):FindFirstChild("Root"):FindFirstChild("HUD")
	local oldLane = hudFrame:GetAttribute("LaneWidth")
	hudFrame:SetAttribute("LaneWidth", 120)
	M.settle(0.1)
	local tb = Phone.BUTTON * L.buttonScale
	check("touch: a new LaneWidth re-runs the phone layout by itself", L.hudLane == 120, L.hudLane)
	check("touch: the narrow lane is the case where the button reaches further left", L.buttonRight + tb > 120 * L.hudScale, (L.buttonRight + tb) .. " vs " .. (120 * L.hudScale))
	check("touch: the phone sits left of the phone button", L.rightEdge >= L.buttonRight + tb + Phone.MARGIN - 0.01, L.rightEdge .. " < " .. (L.buttonRight + tb + Phone.MARGIN))
	hudFrame:SetAttribute("LaneWidth", oldLane)
	M.settle(0.1)
	check("touch: back to the HUD's real lane", L.hudLane == oldLane, L.hudLane)
end

local function body()
	if ONLY == "rich" then rich() elseif ONLY == "fixes" then fixes() elseif ONLY == "touch" then touchMode() else garage() end
end
local ENV = M.envFor(nil)
setfenv(garage, ENV)
setfenv(rich, ENV)
setfenv(fixes, ENV)
setfenv(touchMode, ENV)
setfenv(helpers, ENV)

setfenv(body, M.envFor(nil))
local ok, res = M.runMain(body, { timeout = 900 })
if not ok then failc += 1; print("FAIL  body crashed: " .. tostring(res)) end
if M.stats.errors > 0 then failc += 1; print("FAIL  background errors: " .. M.stats.errors) end
print(string.format("phone_ui_%s: %d passed, %d failed", ONLY, pass, failc))
