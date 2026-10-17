--!strict
-- PhoneScreens (package "phone"): the app screens of the company phone, built into the phone's content area
-- (Screens/Phone owns the frame, status bar, navigation and incoming calls). Every screen reads only the view
-- model the PhoneController builds from real state (snapshot + PhoneService answers) and returns
--   { sig = view -> string, update = (view -> ())?, live = (view -> ())? }
-- Screens/Phone rebuilds a screen only when its signature changes (structure: which items, which states), calls
-- update instead when the screen has one (chat thread: new bubbles without losing the typed text), and calls
-- live on every new view for values that tick (clock, money, times) - so a running clock or a cash tick never
-- rebuilds a screen or moves the gamepad selection. The first control is selected for the gamepad only on
-- navigation (ctx.focus). Works in both phone shapes: portrait (desktop, consoles) and landscape (phones held
-- sideways, where a portrait phone would be too small to read).
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PhoneMath = require(ReplicatedStorage.Shared.PhoneMath)
local Ops = require(ReplicatedStorage.Shared.CompanyOps)
local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local PhoneKit = require(script.Parent.PhoneKit)

local C = Theme.colors
local F = Theme.font
local P = PhoneKit.colors

local Screens = {}

export type View = {
	company: string,
	status: string,
	dayText: string,
	today: number,
	dayLine: string,
	todayLine: string?,
	staff: number,
	-- the HUD's Next goal title (Screens/HUD.describe)
	goal: { text: string, caption: string? }?,
	messages: { any },
	read: { [string]: boolean },
	unread: number,
	calls: { any },
	missed: number,
	results: { [string]: any },
	dial: { [string]: any },
	calendar: { any },
	nextItem: any?, -- the first own calendar item (not the public shuttle timetable)
	models: { any },
	chats: { [string]: any },
	settings: { autoTrips: boolean, popups: boolean, saved: boolean },
	phones: number,
	phoneCost: string,
	stage: number,
	hooks: { itinerary: boolean, driver: boolean },
	finance: any, -- {cash, day, inTotal, outTotal, net, yesterday?, income = {{label, value}}, costs, ok}
	team: any, -- {staff, desks, office, roles = {{id, name, count}}, apprentices, night, applications, ops, sick, vacation, trip, leave}
	places: any, -- {list = {{id, name, kind, abroad, mine}}, active, gps}
}
export type Deps = {
	markRead: (keys: { string }) -> (),
	readCalls: () -> (),
	answer: (id: string, how: string) -> (),
	dial: (contact: string) -> (),
	setSetting: (key: string, value: boolean) -> (),
	sendChat: (modelId: string, text: string) -> (),
	resetChat: (modelId: string) -> (),
	setDraft: (modelId: string, text: string) -> (),
	guide: (placeId: string) -> (), -- GPS route ("home" = own HQ, "" = clear)
	openComputer: (app: string, section: string?) -> (),
	close: () -> (),
	refresh: () -> (), -- rebuild the full view (calendar, chat models) right before the phone opens
}
export type Ctx = {
	view: View,
	deps: Deps,
	go: (name: string, arg: any?) -> (),
	back: () -> (),
	content: Frame,
	landscape: boolean,
	focus: boolean, -- built by navigation: select the first control for the gamepad
}
-- sig: rebuild when it changes; update: used instead of a rebuild when the sig changes (chat thread);
-- live: called on every new view (ticking values)
export type Built = { sig: (View) -> string, update: ((View) -> ())?, live: ((View) -> ())? }

local CONTACTS = {
	{ id = "assistant", name = "Assistant", glyph = "assistant", color = PhoneKit.senderColor("Assistant"), sub = "Briefing and recommendations" },
	{ id = "driver", name = "Driver", glyph = "driver", color = Color3.fromRGB(236, 160, 64), sub = "Rides to the airport and to clients" },
	{ id = "reception", name = "Reception", glyph = "desk", color = Color3.fromRGB(104, 126, 168), sub = "Visitors, applicants, guest house" },
	{ id = "it", name = "IT desk", glyph = "server", color = Color3.fromRGB(96, 170, 200), sub = "Servers and rack faults" },
}
Screens.CONTACTS = CONTACTS
local function contactDef(id: string): any
	for _, c in CONTACTS do if c.id == id then return c end end
	return CONTACTS[1]
end

local function select(ctx: Ctx, obj: GuiObject?)
	if ctx.focus and obj and UserInputService.GamepadEnabled then GuiService.SelectedObject = obj end
end

local function timeText(m: any, today: number): string
	if m.day == today then return PhoneMath.clock(m.hour) end
	if m.day <= 0 then return "" end
	return "Day " .. tostring(m.day)
end

local function card(parent: Instance, order: number, gap: number?): Frame
	local f = Kit.frame(parent, UDim2.fromScale(1, 0))
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.LayoutOrder = order
	f.BackgroundTransparency = 0.05
	f.BackgroundColor3 = P.card
	Kit.corner(f, 14)
	Kit.padding(f, 10, 12, 11, 12)
	Kit.list(f, gap or 4)
	return f
end

-- one line of text that is cut with "..." (never wraps)
local function line(parent: Instance, text: string, size: number, font: Enum.Font, color: Color3, order: number, height: number?): TextLabel
	local t = Kit.text(parent, text, size, font, color)
	t.AutomaticSize = Enum.AutomaticSize.None
	t.Size = UDim2.new(1, 0, 0, height or (size + 4))
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.LayoutOrder = order
	return t
end

-- a "label ........ value" row
local function valueRow(parent: Instance, order: number, label: string, value: string, color: Color3?, bold: boolean?): (Frame, TextLabel)
	local row = Kit.frame(parent, UDim2.new(1, 0, 0, 22))
	row.LayoutOrder = order
	local l = Kit.text(row, label, 14, if bold then F.bold else F.regular, if bold then C.text else C.muted)
	l.Name = "Label"
	l.AutomaticSize = Enum.AutomaticSize.None
	l.Size = UDim2.new(0.62, 0, 1, 0)
	l.TextTruncate = Enum.TextTruncate.AtEnd
	local v = Kit.text(row, value, 14, F.bold, color or C.text)
	v.Name = "Value"
	v.AutomaticSize = Enum.AutomaticSize.None
	v.Size = UDim2.new(0.38, 0, 1, 0)
	v.Position = UDim2.fromScale(0.62, 0)
	v.TextXAlignment = Enum.TextXAlignment.Right
	return row, v
end

local function signed(n: number): string
	return if n >= 0 then "+" .. Ops.money(n) else Ops.money(n)
end

------------------------------------------------------------------------------------------------ home
local APPS: { { id: string, label: string, color: Color3? } } = {
	{ id = "messages", label = "Messages", color = P.messages },
	{ id = "calls", label = "Calls", color = P.calls },
	{ id = "calendar", label = "Calendar", color = P.calendar },
	{ id = "contacts", label = "Contacts", color = P.contacts },
	{ id = "chat", label = "AI Chat", color = nil },
	{ id = "map", label = "Map", color = P.map },
	{ id = "finance", label = "Finance", color = P.finance },
	{ id = "team", label = "Team", color = P.team },
	{ id = "settings", label = "Settings", color = P.settings },
}
Screens.APPS = APPS

local function itemWhen(item: any, today: number): string
	return if item.day == today or item.now then PhoneMath.clock(item.hour) else "Day " .. item.day
end

-- the phone's own "Today" card: who is away, trips under way, the next goal in one line (the HUD shows the full
-- goal card) and, in landscape (no peek rows), the next calendar entry
local function todayCard(parent: Instance, view: View, order: number, compact: boolean)
	local box = card(parent, order, 4)
	box.Name = "TodayCard"
	local cap = Kit.text(box, "Today", 13, F.bold, Theme.accent)
	Theme.bindAccent(cap, "TextColor3")
	cap.LayoutOrder = 1
	local who = if view.todayLine then (string.gsub(view.todayLine :: string, "^Today: ", "")) elseif view.staff == 0 then "Just you in the garage so far." else "Everyone is at work today."
	local t = Kit.para(box, who, 13, C.text, 2)
	t.Name = "TodayLine"
	local g = view.goal
	local goal = line(box, (if g then (g.caption or "Next goal") .. ": " .. g.text else "Every goal is done. Keep growing!"), 13, F.regular, C.muted, 3, 17)
	goal.Name = "GoalLine"
	if compact and view.nextItem then
		local n = view.nextItem
		local nx = line(box, "Next: " .. n.title .. " · " .. itemWhen(n, view.today), 13, F.regular, C.muted, 4, 17)
		nx.Name = "NextLine"
	end
end

function Screens.home(ctx: Ctx): Built
	local view = ctx.view
	local root = ctx.content
	local first: GuiObject? = nil
	local function grid(parent: Instance, cell: UDim2, iconSize: number, gapY: number)
		local holder = Kit.frame(parent, UDim2.fromScale(1, 0))
		holder.Name = "Apps"
		holder.AutomaticSize = Enum.AutomaticSize.Y
		holder.LayoutOrder = 10
		local layout = Instance.new("UIGridLayout")
		layout.CellSize = cell
		layout.CellPadding = UDim2.fromOffset(4, gapY)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = holder
		for i, app in APPS do
			local tile = PhoneKit.tile(holder, app.id, app.label, app.color, i, iconSize)
			tile.button.Size = cell
			if app.id == "messages" then tile.badge.set(view.unread) elseif app.id == "calls" then tile.badge.set(view.missed) end
			Kit.onClick(tile.button, function() ctx.go(app.id) end)
			if i == 1 then first = tile.button end
		end
	end
	if ctx.landscape then
		local left = Kit.frame(root, UDim2.new(0.44, -6, 1, -8), UDim2.fromOffset(12, 4))
		left.Name = "Left"
		Kit.list(left, 4)
		local clock = Kit.text(left, view.status, 40, F.display, C.text)
		clock.Name = "Clock"
		clock.LayoutOrder = 1
		local date = line(left, view.dayText .. " · " .. view.company, 13, F.medium, C.muted, 2, 18)
		date.Name = "Date"
		local spacer = Kit.frame(left, UDim2.new(1, 0, 0, 4))
		spacer.LayoutOrder = 3
		todayCard(left, view, 4, true)
		local right = Kit.frame(root, UDim2.new(0.56, -12, 1, -8), UDim2.new(0.44, 6, 0, 4))
		right.Name = "Right"
		Kit.list(right, 0).VerticalAlignment = Enum.VerticalAlignment.Center
		grid(right, UDim2.new(1 / 3, -4, 0, 70), 44, 4) -- three columns at any landscape width (520-580 design px)
	else
		-- a scrolling column: everything fits on the design size, a long today line only scrolls
		local body = Kit.scroll(root, UDim2.new(1, 0, 1, -4), UDim2.fromOffset(0, 4))
		body.Name = "Body"
		body.ScrollBarThickness = 3
		body.Selectable = false
		local stack = Kit.frame(body, UDim2.new(1, -24, 0, 0), UDim2.fromOffset(12, 0))
		stack.Name = "Stack"
		stack.AutomaticSize = Enum.AutomaticSize.Y
		local layout = Kit.list(stack, 6)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		Kit.padding(stack, 0, 0, 8, 0)
		local clock = Kit.text(stack, view.status, 48, F.display, C.text)
		clock.Name = "Clock"
		clock.LayoutOrder = 1
		local date = line(stack, view.dayText .. " · " .. view.company, 14, F.medium, C.muted, 2, 18)
		date.Name = "Date"
		date.TextXAlignment = Enum.TextXAlignment.Center
		local spacer = Kit.frame(stack, UDim2.new(1, 0, 0, 2))
		spacer.LayoutOrder = 3
		todayCard(stack, view, 4, false)
		grid(stack, UDim2.fromOffset(90, 80), 52, 6)
		-- the newest message and the next own calendar entry (tap opens them)
		local latest = view.messages[1]
		local nextItem = view.nextItem
		local function peek(order: number, name: string, caption: string, title: string, sub: string, color: Color3, onTap: () -> ()): TextButton
			local row = PhoneKit.tap(stack, UDim2.new(1, 0, 0, 52))
			row.Name = name
			row.LayoutOrder = order
			row.BackgroundTransparency = 0.05
			row.BackgroundColor3 = P.card
			row.Selectable = true
			Kit.corner(row, 14)
			local bar = Kit.frame(row, UDim2.new(0, 4, 1, -18), UDim2.fromOffset(10, 9))
			bar.BackgroundTransparency = 0
			bar.BackgroundColor3 = color
			Kit.corner(bar, 2)
			local cap = Kit.text(row, caption, 12, F.bold, C.dim)
			cap.Position = UDim2.fromOffset(24, 7)
			local t = Kit.text(row, title, 14, F.bold, C.text)
			t.AutomaticSize = Enum.AutomaticSize.None
			t.Size = UDim2.new(1, -36, 0, 18)
			t.Position = UDim2.fromOffset(24, 25)
			t.TextTruncate = Enum.TextTruncate.AtEnd
			local w = Kit.text(row, sub, 12, F.medium, C.dim)
			w.Name = "When"
			w.AnchorPoint = Vector2.new(1, 0)
			w.Position = UDim2.new(1, -12, 0, 7)
			Kit.onClick(row, onTap)
			return row
		end
		if latest then
			peek(20, "Latest", "Latest · " .. latest.from, latest.title, timeText(latest, view.today), PhoneKit.senderColor(latest.from), function() ctx.go("message", latest.key) end)
		end
		if nextItem then
			peek(21, "NextItem", if nextItem.now then "Under way" else "Next in your calendar", nextItem.title, itemWhen(nextItem, view.today), P.calendar, function() ctx.go("calendar") end)
		end
	end
	select(ctx, first)
	return {
		sig = function(v: View): string
			local g = v.goal
			local m, n = v.messages[1], v.nextItem
			return table.concat({ v.dayText, tostring(v.unread), tostring(v.missed), if g then (g.caption or "") .. g.text else "-", v.todayLine or "", tostring(v.staff == 0), v.company,
				if m then m.key else "-", if n then n.key .. n.title .. tostring(n.now) else "-" }, "|")
		end,
		live = function(v: View)
			local clock = root:FindFirstChild("Clock", true)
			if clock and clock:IsA("TextLabel") then clock.Text = v.status end
			local n = v.nextItem
			if n then
				local peekRow = root:FindFirstChild("NextItem", true)
				local w = peekRow and peekRow:FindFirstChild("When")
				if w and w:IsA("TextLabel") then w.Text = itemWhen(n, v.today) end
				local nx = root:FindFirstChild("NextLine", true)
				if nx and nx:IsA("TextLabel") then nx.Text = "Next: " .. n.title .. " · " .. itemWhen(n, v.today) end
			end
		end,
	}
end

------------------------------------------------------------------------------------------------ messages
function Screens.messages(ctx: Ctx): Built
	local view = ctx.view
	PhoneKit.header(ctx.content, "Messages", ctx.back)
	local _, list = PhoneKit.body(ctx.content)
	local first: GuiObject? = nil
	local keys = {}
	for i, m in view.messages do
		table.insert(keys, m.key)
		local row = PhoneKit.tap(list, UDim2.new(1, 0, 0, 60))
		row.Name = "Message"
		row.LayoutOrder = i
		row.BackgroundTransparency = 0.05
		row.BackgroundColor3 = P.card
		row.Selectable = true
		Kit.corner(row, 12)
		local av = PhoneKit.avatar(row, string.sub(m.from, 1, 1), PhoneKit.senderColor(m.from), 38)
		av.Position = UDim2.new(0, 10, 0.5, -19)
		local unread = not view.read[m.key]
		local title = Kit.text(row, m.title, 15, if unread then F.bold else F.medium, C.text)
		title.Name = "Title"
		title.AutomaticSize = Enum.AutomaticSize.None
		title.Size = UDim2.new(1, -118, 0, 20)
		title.Position = UDim2.fromOffset(58, 9)
		title.TextTruncate = Enum.TextTruncate.AtEnd
		local preview = Kit.text(row, m.from .. ": " .. m.body, 13, F.regular, C.muted)
		preview.AutomaticSize = Enum.AutomaticSize.None
		preview.Size = UDim2.new(1, -92, 0, 18)
		preview.Position = UDim2.fromOffset(58, 31)
		preview.TextTruncate = Enum.TextTruncate.AtEnd
		local when = Kit.text(row, timeText(m, view.today), 12, F.medium, C.dim)
		when.AnchorPoint = Vector2.new(1, 0)
		when.Position = UDim2.new(1, -12, 0, 11)
		if unread then
			local dot = Kit.dot(row, Theme.accent, 9)
			Theme.bindAccent(dot, "BackgroundColor3")
			dot.AnchorPoint = Vector2.new(1, 0)
			dot.Position = UDim2.new(1, -14, 0, 35)
		end
		local stripe = Kit.frame(row, UDim2.new(0, 3, 0, 26), UDim2.new(0, 0, 0.5, -13))
		stripe.BackgroundTransparency = if m.tone == "info" then 1 else 0.2
		stripe.BackgroundColor3 = PhoneKit.toneColor(m.tone)
		Kit.corner(stripe, 2)
		Kit.onClick(row, function() ctx.go("message", m.key) end)
		if i == 1 then first = row end
	end
	if #view.messages == 0 then
		PhoneKit.empty(list, "No messages yet", "Your company writes here: new clients, trips, hires, sick days, server faults and goals.")
	end
	select(ctx, first)
	ctx.deps.markRead(keys) -- opening the inbox reads it (the list still shows which ones were new)
	return {
		sig = function(v: View): string
			local parts = {}
			for _, m in v.messages do table.insert(parts, m.key) end
			return table.concat(parts, "\n") .. "|" .. tostring(v.today)
		end,
	}
end

function Screens.message(ctx: Ctx, key: any): Built
	local view = ctx.view
	PhoneKit.header(ctx.content, "Messages", ctx.back)
	local _, list = PhoneKit.body(ctx.content)
	local m: any = nil
	for _, x in view.messages do if x.key == key then m = x end end
	if not m then
		PhoneKit.empty(list, "Message gone", "Older messages leave the phone after " .. PhoneMath.INBOX_MAX .. " entries.")
	else
		local box = card(list, 1, 8)
		local head = Kit.frame(box, UDim2.new(1, 0, 0, 44))
		head.LayoutOrder = 1
		PhoneKit.avatar(head, string.sub(m.from, 1, 1), PhoneKit.senderColor(m.from), 40)
		local from = Kit.text(head, m.from, 15, F.bold, C.text)
		from.Position = UDim2.fromOffset(50, 2)
		local when = Kit.text(head, if m.day > 0 then "Day " .. m.day .. " · " .. PhoneMath.clock(m.hour) else "", 13, F.medium, C.dim)
		when.Position = UDim2.fromOffset(50, 23)
		local title = Kit.para(box, m.title, 18, C.text, 2)
		title.Name = "Title"
		title.Font = F.bold
		local text = Kit.para(box, m.body, 15, C.text, 3)
		text.Name = "Body"
		if m.tone ~= "info" then
			local tag = Kit.tag(box, if m.tone == "good" then "good news" elseif m.tone == "bad" then "problem" else "heads-up", PhoneKit.toneColor(m.tone), 4)
			tag.Name = "Tone"
		end
		ctx.deps.markRead({ m.key })
	end
	select(ctx, ctx.content:FindFirstChild("Back", true) :: GuiObject?)
	return { sig = function(v: View): string
		for _, x in v.messages do if x.key == key then return x.key end end
		return "gone"
	end }
end

------------------------------------------------------------------------------------------------ calls
local function callState(c: any): (string, Color3)
	if c.state == "ringing" then return "Incoming", P.accept end
	if c.state == "missed" then return "Missed", P.decline end
	if c.state == "accepted" then return "Answered", C.muted end
	return "Declined", C.dim
end

function Screens.calls(ctx: Ctx): Built
	local view = ctx.view
	PhoneKit.header(ctx.content, "Calls", ctx.back)
	local _, list = PhoneKit.body(ctx.content)
	local first: GuiObject? = nil
	for i, c in view.calls do
		local row = PhoneKit.tap(list, UDim2.new(1, 0, 0, 58))
		row.Name = "Call"
		row.LayoutOrder = i
		row.BackgroundTransparency = 0.05
		row.BackgroundColor3 = P.card
		row.Selectable = true
		Kit.corner(row, 12)
		local stateText, color = callState(c)
		local icon = Kit.frame(row, UDim2.fromOffset(36, 36), UDim2.new(0, 10, 0.5, -18))
		icon.BackgroundTransparency = 0.75
		icon.BackgroundColor3 = color
		Kit.corner(icon, 18)
		local g = PhoneKit.glyph(icon, "calls", 22, color)
		g.AnchorPoint = Vector2.new(0.5, 0.5)
		g.Position = UDim2.fromScale(0.5, 0.5)
		local title = Kit.text(row, c.title, 15, F.bold, if c.state == "missed" then C.bad else C.text)
		title.AutomaticSize = Enum.AutomaticSize.None
		title.Size = UDim2.new(1, -120, 0, 20)
		title.Position = UDim2.fromOffset(56, 9)
		title.TextTruncate = Enum.TextTruncate.AtEnd
		local sub = Kit.text(row, tostring(c.from) .. " · " .. stateText, 13, F.medium, C.muted)
		sub.Position = UDim2.fromOffset(56, 31)
		local when = Kit.text(row, timeText(c, view.today), 12, F.medium, C.dim)
		when.AnchorPoint = Vector2.new(1, 0)
		when.Position = UDim2.new(1, -12, 0, 11)
		Kit.onClick(row, function() ctx.go("call", c.id) end)
		if i == 1 then first = row end
	end
	if #view.calls == 0 then
		PhoneKit.empty(list, "No calls yet", "Your assistant calls when something important happens: your first client, a trip abroad, a new office you can afford.")
	end
	ctx.deps.readCalls()
	select(ctx, first)
	return { sig = function(v: View): string
		local parts = {}
		for _, c in v.calls do table.insert(parts, c.id .. c.state) end
		return table.concat(parts, ",") .. "|" .. tostring(v.today)
	end }
end

-- one call (incoming, missed or done): who, what, and the decision buttons
function Screens.call(ctx: Ctx, id: any): Built
	local view = ctx.view
	local c: any = nil
	for _, x in view.calls do if x.id == id then c = x end end
	local root = ctx.content
	local result = view.results[tostring(id)]
	if not c then
		PhoneKit.header(root, "Calls", ctx.back)
		local _, list = PhoneKit.body(root)
		PhoneKit.empty(list, "Call ended", "This call is no longer in the call log.")
		return { sig = function(v: View): string return "none" end }
	end
	local stateText = if c.state == "ringing" then "Incoming call" elseif c.state == "missed" then "Missed call · " .. timeText(c, view.today)
		elseif c.state == "accepted" then "Call ended" else "Declined"
	local function who(parent: Instance, order: number)
		local box = Kit.frame(parent, UDim2.fromScale(1, 0))
		box.AutomaticSize = Enum.AutomaticSize.Y
		box.LayoutOrder = order
		Kit.list(box, 4).HorizontalAlignment = Enum.HorizontalAlignment.Center
		local av = PhoneKit.avatar(box, string.sub(tostring(c.from), 1, 1), PhoneKit.senderColor(tostring(c.from)), if ctx.landscape then 64 else 84)
		av.LayoutOrder = 1
		local name = Kit.text(box, tostring(c.from), 22, F.display, C.text)
		name.LayoutOrder = 2
		local st = Kit.text(box, stateText, 14, F.medium, if c.state == "missed" then C.bad else C.muted)
		st.Name = "State"
		st.LayoutOrder = 3
	end
	local function talk(parent: Instance, order: number)
		local box = card(parent, order, 6)
		box.Name = "CallText"
		local title = Kit.para(box, tostring(c.title), 16, C.text, 1)
		title.Font = F.bold
		local text = Kit.para(box, tostring(c.text), 15, C.text, 2)
		text.Name = "Text"
		if result then
			local r = card(parent, order + 1, 4)
			r.Name = "Result"
			r.BackgroundColor3 = P.card2
			Kit.para(r, if typeof(result.text) == "string" then result.text elseif result.pending then "Connecting..." else "Done.", 14, C.text, 1)
		end
	end
	local first: GuiObject? = nil
	local function buttons(parent: Instance, order: number)
		local row = Kit.frame(parent, UDim2.new(1, 0, 0, 96))
		row.Name = "Buttons"
		row.LayoutOrder = order
		local layout = Kit.list(row, 18, true)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		if (c.state == "ringing" or c.state == "missed") and not result then
			local no = PhoneKit.callButton(row, tostring(c.decline), P.decline, 1, true)
			no.Name = "Decline"
			local yes = PhoneKit.callButton(row, tostring(c.accept), P.accept, 2)
			yes.Name = "Accept"
			Kit.onClick(no, function() ctx.deps.answer(c.id, "decline") end)
			Kit.onClick(yes, function() ctx.deps.answer(c.id, "accept") end)
			first = yes
		else
			local done = Kit.button(row, "Done", "secondary", UDim2.fromOffset(150, 44))
			done.Name = "Done"
			Kit.onClick(done, function() ctx.go("home") end)
			first = done
		end
	end
	if ctx.landscape then
		local left = Kit.frame(root, UDim2.new(0.34, 0, 1, -8), UDim2.fromOffset(8, 8))
		local ll = Kit.list(left, 8)
		ll.HorizontalAlignment = Enum.HorizontalAlignment.Center
		who(left, 1)
		-- deciding: Decline / Accept in a fixed bar under the text (never scrolled away, the text scrolls above it);
		-- once answered, "Done" sits under the caller
		local deciding = (c.state == "ringing" or c.state == "missed") and not result
		local barH = if deciding then 96 else 0
		local right = Kit.scroll(root, UDim2.new(0.66, -16, 1, -(8 + barH)), UDim2.new(0.34, 8, 0, 4))
		right.Name = "Body"
		local col = Kit.frame(right, UDim2.new(1, -6, 0, 0))
		col.AutomaticSize = Enum.AutomaticSize.Y
		Kit.list(col, 6)
		talk(col, 1)
		if deciding then
			local bar = Kit.frame(root, UDim2.new(0.66, -16, 0, barH), UDim2.new(0.34, 8, 1, -barH))
			bar.Name = "Decision"
			Kit.list(bar, 0)
			buttons(bar, 1)
		else
			buttons(left, 5)
		end
	else
		local scroll = Kit.scroll(root, UDim2.new(1, 0, 1, -4), UDim2.fromOffset(0, 4))
		scroll.Name = "Body"
		local col = Kit.frame(scroll, UDim2.fromScale(1, 0))
		col.AutomaticSize = Enum.AutomaticSize.Y
		Kit.list(col, 10)
		Kit.padding(col, 14, 12, 12, 12)
		who(col, 1)
		talk(col, 2)
		buttons(col, 5)
	end
	select(ctx, first)
	return { sig = function(v: View): string
		local s = "none"
		for _, x in v.calls do if x.id == id then s = x.state end end
		local r = v.results[tostring(id)]
		return s .. "|" .. (if r then tostring(r.text) .. tostring(r.pending) else "-")
	end }
end

------------------------------------------------------------------------------------------------ calendar
local function calSection(item: any, today: number): string
	return if item.now then "Under way" elseif item.day == today then "Today" else "Coming up"
end

function Screens.calendar(ctx: Ctx): Built
	local view = ctx.view
	PhoneKit.header(ctx.content, "Calendar", ctx.back)
	local _, list = PhoneKit.body(ctx.content)
	local todayBox = card(list, 1, 3)
	todayBox.Name = "Today"
	local t = Kit.text(todayBox, view.dayText .. " · " .. view.status, 17, F.bold, C.text)
	t.Name = "Now"
	t.LayoutOrder = 1
	local dl = Kit.para(todayBox, view.dayLine, 13, C.muted, 2)
	dl.Name = "DayLine"
	local order = 10
	local lastSection = ""
	-- the time labels of each row (refreshed in place by live: times move, the list does not)
	local rows: { { when: TextLabel, sub: TextLabel?, detail: TextLabel } } = {}
	for i, item in view.calendar do
		local section = calSection(item, view.today)
		if section ~= lastSection then
			lastSection = section
			order += 1
			local cap = Kit.caption(list, section, order)
			cap.Name = "Section"
			Kit.padding(cap, 6, 0, 0, 4)
		end
		order += 1
		local row = Kit.frame(list, UDim2.fromScale(1, 0))
		row.Name = "Item"
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.LayoutOrder = order
		row.BackgroundTransparency = if item.public then 0.35 else 0.05
		row.BackgroundColor3 = P.card
		Kit.corner(row, 12)
		Kit.padding(row, 9, 10, 10, 10)
		local timeCol = Kit.frame(row, UDim2.new(0, 56, 0, 0))
		timeCol.AutomaticSize = Enum.AutomaticSize.Y
		Kit.list(timeCol, 0)
		local stripeColor = if item.kind == "flight" then Color3.fromRGB(64, 156, 236) elseif item.kind == "renewal" then C.warn elseif item.kind == "trip" then P.calls else Theme.accent
		if item.now and typeof(item.tag) == "string" then Kit.text(timeCol, item.tag, 12, F.medium, C.dim).LayoutOrder = 0 end
		local hh = Kit.text(timeCol, if item.day == view.today then PhoneMath.clock(item.hour) else "Day " .. item.day, 14, F.bold, stripeColor)
		hh.Name = "When"
		hh.LayoutOrder = 1
		local sub: TextLabel? = nil
		if item.day ~= view.today then
			sub = Kit.text(timeCol, PhoneMath.clock(item.hour), 12, F.medium, C.dim)
			local s = sub :: TextLabel
			s.Name = "Sub"
			s.LayoutOrder = 2
		end
		local textCol = Kit.frame(row, UDim2.new(1, -62, 0, 0), UDim2.fromOffset(62, 0))
		textCol.AutomaticSize = Enum.AutomaticSize.Y
		Kit.list(textCol, 2)
		local title = Kit.para(textCol, item.title, 14, if item.public then C.muted else C.text, 1)
		title.Font = F.bold
		local detail = Kit.para(textCol, item.detail, 13, C.muted, 2)
		detail.Name = "Detail"
		rows[i] = { when = hh, sub = sub, detail = detail }
	end
	if #view.calendar == 0 then
		PhoneKit.empty(list, "Nothing planned", "Client visits, trips abroad, contract check-ins and flights show up here as your company grows.", 50)
	end
	select(ctx, ctx.content:FindFirstChild("Back", true) :: GuiObject?)
	return {
		sig = function(v: View): string
			local parts = { v.dayText }
			for _, item in v.calendar do
				table.insert(parts, item.key .. "|" .. item.title .. "|" .. calSection(item, v.today) .. "|" .. tostring(item.day == v.today))
			end
			return table.concat(parts, "\n")
		end,
		live = function(v: View)
			t.Text = v.dayText .. " · " .. v.status
			dl.Text = v.dayLine
			for i, item in v.calendar do
				local r = rows[i]
				if not r then continue end
				local when = if item.day == v.today then PhoneMath.clock(item.hour) else "Day " .. item.day
				if r.when.Text ~= when then r.when.Text = when end
				local sub = r.sub
				if sub and sub.Text ~= PhoneMath.clock(item.hour) then sub.Text = PhoneMath.clock(item.hour) end
				if r.detail.Text ~= item.detail then r.detail.Text = item.detail end
			end
		end,
	}
end

------------------------------------------------------------------------------------------------ contacts
function Screens.contacts(ctx: Ctx): Built
	local view = ctx.view
	PhoneKit.header(ctx.content, "Contacts", ctx.back)
	local _, list = PhoneKit.body(ctx.content)
	local first: GuiObject? = nil
	for i, def in CONTACTS do
		local row = PhoneKit.tap(list, UDim2.new(1, 0, 0, 60))
		row.Name = "Contact_" .. def.id
		row.LayoutOrder = i
		row.BackgroundTransparency = 0.05
		row.BackgroundColor3 = P.card
		row.Selectable = true
		Kit.corner(row, 12)
		local icon = Kit.frame(row, UDim2.fromOffset(40, 40), UDim2.new(0, 10, 0.5, -20))
		icon.BackgroundTransparency = 0
		icon.BackgroundColor3 = def.color
		Kit.corner(icon, 12)
		local g = PhoneKit.glyph(icon, def.glyph, 24)
		g.AnchorPoint = Vector2.new(0.5, 0.5)
		g.Position = UDim2.fromScale(0.5, 0.5)
		local name = Kit.text(row, def.name, 15, F.bold, C.text)
		name.Position = UDim2.fromOffset(60, 10)
		local subText = def.sub
		if def.id == "driver" and view.stage < 2 then subText = "Starts at the Founder Headquarters"
		elseif def.id == "driver" and not view.hooks.driver then subText = "Ride service coming soon"
		elseif def.id == "reception" and view.stage < 2 then subText = "Opens at the Founder Headquarters" end
		local sub = Kit.text(row, subText, 13, F.regular, C.muted)
		sub.AutomaticSize = Enum.AutomaticSize.None
		sub.Size = UDim2.new(1, -130, 0, 18)
		sub.Position = UDim2.fromOffset(60, 32)
		sub.TextTruncate = Enum.TextTruncate.AtEnd
		local pill = Kit.frame(row, UDim2.fromOffset(56, 28), UDim2.new(1, -10, 0.5, 0))
		pill.AnchorPoint = Vector2.new(1, 0.5)
		pill.BackgroundTransparency = 0
		pill.BackgroundColor3 = P.accept
		Kit.corner(pill, 14)
		local pg = PhoneKit.glyph(pill, "calls", 18)
		pg.AnchorPoint = Vector2.new(0.5, 0.5)
		pg.Position = UDim2.fromScale(0.5, 0.5)
		Kit.onClick(row, function()
			if def.id == "assistant" then
				ctx.deps.dial("assistant")
			else
				ctx.go("dial", def.id)
				ctx.deps.dial(def.id)
			end
		end)
		if i == 1 then first = row end
	end
	local note = Kit.para(list, "Your assistant opens her briefing. Reception and IT answer with live company data.", 12, C.dim, 20)
	note.TextXAlignment = Enum.TextXAlignment.Center
	select(ctx, first)
	return { sig = function(v: View): string return tostring(v.stage) .. tostring(v.hooks.driver) end }
end

function Screens.dial(ctx: Ctx, contact: any): Built
	local view = ctx.view
	local def = contactDef(tostring(contact))
	local root = ctx.content
	local r = view.dial[def.id]
	local function who(parent: Instance, order: number, big: number)
		local box = Kit.frame(parent, UDim2.fromScale(1, 0))
		box.AutomaticSize = Enum.AutomaticSize.Y
		box.LayoutOrder = order
		Kit.list(box, 6).HorizontalAlignment = Enum.HorizontalAlignment.Center
		local icon = Kit.frame(box, UDim2.fromOffset(big, big))
		icon.LayoutOrder = 1
		icon.BackgroundTransparency = 0
		icon.BackgroundColor3 = def.color
		Kit.corner(icon, big)
		local g = PhoneKit.glyph(icon, def.glyph, math.floor(big * 0.58))
		g.AnchorPoint = Vector2.new(0.5, 0.5)
		g.Position = UDim2.fromScale(0.5, 0.5)
		local name = Kit.text(box, def.name, 22, F.display, C.text)
		name.LayoutOrder = 2
		local st = Kit.text(box, if r == nil or r.pending then "Calling..." else "Connected", 14, F.medium, C.muted)
		st.Name = "State"
		st.LayoutOrder = 3
	end
	local function reply(parent: Instance, order: number)
		if r and not r.pending then
			local box = card(parent, order, 4)
			box.Name = "Reply"
			Kit.para(box, if typeof(r.text) == "string" and r.text ~= "" then r.text else "Nobody answered.", 15, C.text, 1).Name = "Text"
			if r.soon then
				local tag = Kit.tag(box, "coming soon", C.warn, 2)
				tag.Name = "Soon"
			end
		end
	end
	local function hangUp(parent: Instance, order: number): TextButton
		local hang = PhoneKit.tap(parent, UDim2.fromOffset(64, 64))
		hang.Name = "HangUp"
		hang.LayoutOrder = order
		hang.BackgroundTransparency = 0
		hang.BackgroundColor3 = P.decline
		hang.Selectable = true
		Kit.corner(hang, 32)
		local x = Kit.text(hang, "×", 40, F.bold, C.white)
		x.AutomaticSize = Enum.AutomaticSize.None
		x.Size = UDim2.fromScale(1, 1)
		x.TextXAlignment = Enum.TextXAlignment.Center
		Kit.onClick(hang, ctx.back)
		return hang
	end
	local hang
	if ctx.landscape then
		local left = Kit.frame(root, UDim2.new(0.34, 0, 1, -8), UDim2.fromOffset(8, 8))
		Kit.list(left, 10).HorizontalAlignment = Enum.HorizontalAlignment.Center
		who(left, 1, 56)
		hang = hangUp(left, 2)
		local right = Kit.scroll(root, UDim2.new(0.66, -16, 1, -8), UDim2.new(0.34, 8, 0, 8))
		right.Name = "Body"
		local col = Kit.frame(right, UDim2.new(1, -6, 0, 0))
		col.AutomaticSize = Enum.AutomaticSize.Y
		Kit.list(col, 6)
		reply(col, 1)
	else
		local scroll = Kit.scroll(root, UDim2.new(1, 0, 1, -4), UDim2.fromOffset(0, 4))
		scroll.Name = "Body"
		local col = Kit.frame(scroll, UDim2.fromScale(1, 0))
		col.AutomaticSize = Enum.AutomaticSize.Y
		Kit.list(col, 10).HorizontalAlignment = Enum.HorizontalAlignment.Center
		Kit.padding(col, 18, 12, 12, 12)
		who(col, 1, 76)
		reply(col, 4)
		hang = hangUp(col, 6)
	end
	select(ctx, hang)
	return { sig = function(v: View): string
		local x = v.dial[def.id]
		return if x == nil then "nil" else tostring(x.pending) .. tostring(x.text)
	end }
end

------------------------------------------------------------------------------------------------ map (GPS)
local KIND_LABEL: { [string]: string } = { client = "Client office", hotel = "Hotel", venue = "Venue", airport = "Airport", landmark = "Landmark", home = "Your headquarters" }

function Screens.map(ctx: Ctx): Built
	local view = ctx.view
	local places = view.places or { list = {}, active = false, gps = false }
	PhoneKit.header(ctx.content, "Map", ctx.back)
	local _, list = PhoneKit.body(ctx.content)
	local info = card(list, 1, 3)
	info.Name = "GpsInfo"
	local t = Kit.text(info, "GPS", 15, F.bold, C.text)
	t.LayoutOrder = 1
	Kit.para(info, if places.gps then "Pick a place: a glowing line on the road shows you the way, with the distance at the goal."
		else "The GPS is not available right now.", 13, C.muted, 2)
	local first: GuiObject? = nil
	local order = 10
	local function row(id: string, name: string, sub: string, color: Color3, mine: boolean?): TextButton
		order += 1
		local r = PhoneKit.tap(list, UDim2.new(1, 0, 0, 52))
		r.Name = "Place_" .. id
		r.LayoutOrder = order
		r.BackgroundTransparency = 0.05
		r.BackgroundColor3 = P.card
		r.Selectable = true
		Kit.corner(r, 12)
		local icon = Kit.frame(r, UDim2.fromOffset(34, 34), UDim2.new(0, 10, 0.5, -17))
		icon.BackgroundTransparency = 0
		icon.BackgroundColor3 = color
		Kit.corner(icon, 10)
		local g = PhoneKit.glyph(icon, "map", 22)
		g.AnchorPoint = Vector2.new(0.5, 0.5)
		g.Position = UDim2.fromScale(0.5, 0.5)
		local n = Kit.text(r, name, 15, F.bold, C.text)
		n.AutomaticSize = Enum.AutomaticSize.None
		n.Size = UDim2.new(1, -96, 0, 20)
		n.Position = UDim2.fromOffset(54, 7)
		n.TextTruncate = Enum.TextTruncate.AtEnd
		local s = Kit.text(r, sub, 13, F.regular, if mine then C.good else C.muted)
		s.AutomaticSize = Enum.AutomaticSize.None
		s.Size = UDim2.new(1, -96, 0, 18)
		s.Position = UDim2.fromOffset(54, 27)
		s.TextTruncate = Enum.TextTruncate.AtEnd
		local chev = Kit.text(r, "›", 24, F.bold, C.dim)
		chev.AnchorPoint = Vector2.new(1, 0.5)
		chev.Position = UDim2.new(1, -14, 0.5, 0)
		Kit.onClick(r, function() ctx.deps.guide(id) end)
		if not first then first = r end
		return r
	end
	local function section(text: string)
		order += 1
		local cap = Kit.caption(list, text, order)
		cap.Name = "Section"
		Kit.padding(cap, 6, 0, 0, 4)
	end
	if places.gps then
		if places.active then
			local clear = row("", "Clear the current route", "Removes the glowing line", C.raised)
			clear.Name = "ClearRoute"
		end
		section("Business City")
		row("home", "My HQ", KIND_LABEL.home, P.map)
		for _, p in places.list do
			if not p.abroad then row(p.id, p.name, (KIND_LABEL[p.kind] or "Place") .. (if p.mine then " · your client" else ""), if p.mine then P.accept else P.map, p.mine) end
		end
		section("Port Meridian · fly from City Airport")
		for _, p in places.list do
			if p.abroad then row(p.id, p.name, (KIND_LABEL[p.kind] or "Place") .. (if p.mine then " · your client" else ""), if p.mine then P.accept else Color3.fromRGB(64, 156, 236), p.mine) end
		end
	end
	select(ctx, first)
	return { sig = function(v: View): string
		local pl = v.places or { list = {}, active = false, gps = false }
		local parts = { tostring(pl.active), tostring(pl.gps) }
		for _, p in pl.list do table.insert(parts, p.id .. tostring(p.mine)) end
		return table.concat(parts, ",")
	end }
end

------------------------------------------------------------------------------------------------ finance
function Screens.finance(ctx: Ctx): Built
	local view = ctx.view
	local fin = view.finance or { cash = 0, day = view.today, inTotal = 0, outTotal = 0, net = 0, income = {}, costs = {}, ok = false }
	PhoneKit.header(ctx.content, "Finance", ctx.back)
	local _, list = PhoneKit.body(ctx.content)
	local cashBox = card(list, 1, 2)
	cashBox.Name = "Cash"
	local cap = Kit.text(cashBox, "Cash", 13, F.bold, Theme.accent)
	Theme.bindAccent(cap, "TextColor3")
	cap.LayoutOrder = 1
	local cash = Kit.text(cashBox, Ops.money(fin.cash), 30, F.display, C.text)
	cash.Name = "CashValue"
	cash.LayoutOrder = 2
	local todayBox = card(list, 2, 2)
	todayBox.Name = "TodayMoney"
	local tcap = Kit.text(todayBox, "Today · Day " .. tostring(fin.day), 15, F.bold, C.text)
	tcap.LayoutOrder = 1
	local _, inV = valueRow(todayBox, 2, "Income", "+" .. Ops.money(fin.inTotal), C.good)
	local _, outV = valueRow(todayBox, 3, "Costs", "-" .. Ops.money(fin.outTotal), C.bad)
	local _, netV = valueRow(todayBox, 4, "Net so far", signed(fin.net), if fin.net >= 0 then C.good else C.bad, true)
	inV.Name, outV.Name, netV.Name = "Income", "Costs", "Net"
	local yRow, yV = valueRow(todayBox, 5, "Yesterday (net)", if fin.yesterday then signed(fin.yesterday) else "-", C.muted)
	yRow.Name = "Yesterday"
	local lines: { TextLabel } = {}
	if #fin.income > 0 or #fin.costs > 0 then
		local top = card(list, 3, 2)
		top.Name = "Biggest"
		local bt = Kit.text(top, "Biggest lines today", 15, F.bold, C.text)
		bt.LayoutOrder = 1
		local o = 1
		for _, x in fin.income do
			o += 1
			local _, v = valueRow(top, o, x.label, "+" .. Ops.money(x.value), C.good)
			table.insert(lines, v)
		end
		for _, x in fin.costs do
			o += 1
			local _, v = valueRow(top, o, x.label, "-" .. Ops.money(x.value), C.bad)
			table.insert(lines, v)
		end
	end
	local open = Kit.button(list, "Open Home → Money", "primary", UDim2.new(1, 0, 0, 44))
	open.Name = "OpenMoney"
	open.LayoutOrder = 10
	Kit.onClick(open, function() ctx.deps.openComputer("empire", "money") end)
	local note = Kit.para(list, "The same numbers as Home → Money: today's ledger by category. A game day is 20 minutes.", 12, C.dim, 11)
	note.TextXAlignment = Enum.TextXAlignment.Center
	select(ctx, open)
	return {
		sig = function(v: View): string
			local f = v.finance or { day = 0, income = {}, costs = {} }
			local parts = { tostring(f.day), tostring(f.yesterday ~= nil) }
			for _, x in f.income do table.insert(parts, x.label) end
			table.insert(parts, "|")
			for _, x in f.costs do table.insert(parts, x.label) end
			return table.concat(parts, ",")
		end,
		live = function(v: View)
			local f = v.finance
			if not f then return end
			cash.Text = Ops.money(f.cash)
			inV.Text = "+" .. Ops.money(f.inTotal)
			outV.Text = "-" .. Ops.money(f.outTotal)
			netV.Text = signed(f.net)
			netV.TextColor3 = if f.net >= 0 then C.good else C.bad
			yV.Text = if f.yesterday then signed(f.yesterday) else "-"
			local i = 0
			for _, x in f.income do
				i += 1
				if lines[i] then lines[i].Text = "+" .. Ops.money(x.value) end
			end
			for _, x in f.costs do
				i += 1
				if lines[i] then lines[i].Text = "-" .. Ops.money(x.value) end
			end
		end,
	}
end

------------------------------------------------------------------------------------------------ team
function Screens.team(ctx: Ctx): Built
	local view = ctx.view
	local tm = view.team or { staff = 0, desks = 0, office = "", roles = {}, apprentices = 0, night = 0, applications = 0, ops = 0, sick = 0, vacation = 0, trip = 0, leave = 0 }
	PhoneKit.header(ctx.content, "Team", ctx.back)
	local _, list = PhoneKit.body(ctx.content)
	local head = card(list, 1, 3)
	head.Name = "Headcount"
	local big = Kit.text(head, string.format("%d / %d desks", tm.staff, tm.desks), 26, F.display, C.text)
	big.Name = "Desks"
	big.LayoutOrder = 1
	Kit.para(head, tm.office .. (if tm.ops > 0 then string.format(" · %d operations post%s", tm.ops, if tm.ops == 1 then "" else "s") else ""), 13, C.muted, 2)
	local away = {}
	if tm.sick > 0 then table.insert(away, tm.sick .. " sick") end
	if tm.vacation > 0 then table.insert(away, tm.vacation .. " on vacation") end
	if tm.trip > 0 then table.insert(away, tm.trip .. " on a business trip") end
	if tm.leave > 0 then table.insert(away, tm.leave .. " on unpaid leave") end
	local todayText = if tm.staff == 0 then "Nobody hired yet: hire your first specialists in Team → Staff."
		elseif #away == 0 then "Today: everyone is at work." else "Today: " .. table.concat(away, " · ") .. "."
	local tl = Kit.para(head, todayText, 13, if #away > 0 then C.warn else C.text, 3)
	tl.Name = "Away"
	local roles = card(list, 2, 2)
	roles.Name = "Roles"
	Kit.text(roles, "Roles", 15, F.bold, C.text).LayoutOrder = 1
	for i, r in tm.roles do valueRow(roles, i + 1, r.name, tostring(r.count)) end
	local extra = card(list, 3, 2)
	extra.Name = "Extra"
	valueRow(extra, 1, "Apprentices", tostring(tm.apprentices))
	valueRow(extra, 2, "Night shift (departments)", tostring(tm.night))
	valueRow(extra, 3, "Open applications", tostring(tm.applications), if tm.applications > 0 then C.warn else nil)
	local open = Kit.button(list, "Open Team", "primary", UDim2.new(1, 0, 0, 44))
	open.Name = "OpenTeam"
	open.LayoutOrder = 10
	Kit.onClick(open, function() ctx.deps.openComputer("empire", "team") end)
	select(ctx, open)
	return { sig = function(v: View): string
		local x = v.team or {}
		local parts = { tostring(x.staff), tostring(x.desks), tostring(x.office), tostring(x.ops), tostring(x.sick), tostring(x.vacation), tostring(x.trip), tostring(x.leave),
			tostring(x.apprentices), tostring(x.night), tostring(x.applications) }
		for _, r in (x.roles or {}) do table.insert(parts, tostring(r.count)) end
		return table.concat(parts, ",")
	end }
end

------------------------------------------------------------------------------------------------ AI chat
function Screens.chat(ctx: Ctx): Built
	local view = ctx.view
	PhoneKit.header(ctx.content, "AI Chat", ctx.back)
	local _, list = PhoneKit.body(ctx.content)
	local first: GuiObject? = nil
	for i, m in view.models do
		local row = PhoneKit.tap(list, UDim2.new(1, 0, 0, 62))
		row.Name = "Model"
		row.LayoutOrder = i
		row.BackgroundTransparency = 0.05
		row.BackgroundColor3 = P.card
		row.Selectable = true
		Kit.corner(row, 12)
		local icon = Kit.frame(row, UDim2.fromOffset(40, 40), UDim2.new(0, 10, 0.5, -20))
		icon.BackgroundTransparency = if m.live then 0 else 0.5
		Theme.bindAccent(icon, "BackgroundColor3")
		Kit.corner(icon, 12)
		local g = PhoneKit.glyph(icon, "chat", 26)
		g.AnchorPoint = Vector2.new(0.5, 0.5)
		g.Position = UDim2.fromScale(0.5, 0.5)
		local title = Kit.text(row, m.title, 15, F.bold, C.text)
		title.Position = UDim2.fromOffset(60, 9)
		local tag = Kit.text(row, if m.live then "LIVE" else "RETIRED", 11, F.bold, if m.live then C.good else C.dim)
		tag.AnchorPoint = Vector2.new(1, 0)
		tag.Position = UDim2.new(1, -12, 0, 11)
		local score = Kit.text(row, string.format("%.0f", m.overall), 15, F.bold, C.text)
		score.Name = "Overall"
		score.AnchorPoint = Vector2.new(1, 0)
		score.Position = UDim2.new(1, -12, 0, 31)
		local sub = Kit.text(row, tostring(m.sub), 13, F.regular, C.muted)
		sub.AutomaticSize = Enum.AutomaticSize.None
		sub.Size = UDim2.new(1, -104, 0, 18)
		sub.Position = UDim2.fromOffset(60, 33)
		sub.TextTruncate = Enum.TextTruncate.AtEnd
		Kit.onClick(row, function() ctx.go("thread", m.id) end)
		if i == 1 then first = row end
	end
	if #view.models == 0 then
		PhoneKit.empty(list, "No released model yet", "Train a model in the Lab and release it. Then you can chat with it here.", 50)
		local open = Kit.button(list, "Open the Lab", "primary", UDim2.fromOffset(170, 44))
		open.Name = "OpenLab"
		open.LayoutOrder = 51
		Kit.onClick(open, function() ctx.deps.openComputer("lab") end)
		local holder = list:FindFirstChildOfClass("UIListLayout")
		if holder then holder.HorizontalAlignment = Enum.HorizontalAlignment.Center end
		first = open
	else
		local note = Kit.para(list, "Chat with your released models. Replies come from Roblox's text generator when it is available; otherwise you get clearly labelled demo replies.", 12, C.dim, 90)
		note.TextXAlignment = Enum.TextXAlignment.Center
	end
	select(ctx, first)
	return { sig = function(v: View): string
		local parts = {}
		for _, m in v.models do table.insert(parts, m.id .. m.line .. tostring(m.live) .. tostring(m.overall)) end
		return table.concat(parts, ",")
	end }
end

-- the text, colour and "not sent" mark of a bubble (also after it was drawn: pending -> filtered text, failed)
local function paintBubble(holder: Frame, turn: any)
	local text = holder:FindFirstChild("Text", true)
	if text and text:IsA("TextLabel") then
		if text.Text ~= tostring(turn.text) then text.Text = tostring(turn.text) end
		if turn.who ~= "system" then text.TextColor3 = if turn.pending then C.muted else C.text end
	end
	local b = holder:FindFirstChild("You")
	if turn.failed and b and not b:FindFirstChild("Failed") then
		local f = Kit.text(b, "not sent", 12, F.medium, C.bad)
		f.Name = "Failed"
		f.LayoutOrder = 2
	end
end

local function bubble(list: Instance, turn: any, order: number): Frame
	local holder = Kit.frame(list, UDim2.fromScale(1, 0))
	holder.Name = "Turn"
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.LayoutOrder = order
	if turn.who == "system" then
		local t = Kit.para(holder, tostring(turn.text), 12, C.dim, 1)
		t.Name = "Text"
		t.TextXAlignment = Enum.TextXAlignment.Center
		return holder
	end
	local mine = turn.who == "you"
	local b = Kit.frame(holder, UDim2.new(0.82, 0, 0, 0))
	b.Name = if mine then "You" else "Model"
	b.AutomaticSize = Enum.AutomaticSize.Y
	b.BackgroundTransparency = 0
	if mine then
		b.AnchorPoint = Vector2.new(1, 0)
		b.Position = UDim2.fromScale(1, 0)
		Theme.bindAccent(b, "BackgroundColor3", Theme.tint(0.55))
	else
		b.BackgroundColor3 = P.card2
	end
	Kit.corner(b, 14)
	Kit.padding(b, 7, 11, 8, 11)
	Kit.list(b, 3)
	if not mine and typeof(turn.label) == "string" then
		-- the honesty label: as readable as the text ("Demo reply (offline)" is never small print)
		local demo = turn.source ~= "ai"
		local label = Kit.text(b, turn.label, 13, F.bold, if demo then C.warn else Theme.accent)
		label.Name = "Label"
		label.LayoutOrder = 0
		if not demo then Theme.bindAccent(label, "TextColor3") end
	end
	local text = Kit.para(b, tostring(turn.text), 15, if turn.pending then C.muted else C.text, 1)
	text.Name = "Text"
	paintBubble(holder, turn)
	return holder
end

function Screens.thread(ctx: Ctx, modelId: any): Built
	local view = ctx.view
	local id = tostring(modelId)
	local model: any = nil
	for _, m in view.models do if m.id == id then model = m end end
	local root = ctx.content
	PhoneKit.header(root, if model then model.title else "AI Chat", ctx.back, "Clear", function() ctx.deps.resetChat(id) end)
	if not model then
		local _, list = PhoneKit.body(root)
		PhoneKit.empty(list, "Model not available", "Only released models can chat.")
		return { sig = function(v: View): string return "none" end }
	end
	local inputH = if ctx.landscape then 50 else 56
	local top = 40
	if not ctx.landscape then -- landscape keeps the room for the conversation
		local sub = Kit.text(root, tostring(model.sub) .. " · " .. string.format("%.0f", model.overall) .. " overall" .. (if model.live then "" else " · retired"), 12, F.medium, C.dim)
		sub.Name = "ModelLine"
		sub.AutomaticSize = Enum.AutomaticSize.None
		sub.Size = UDim2.new(1, -24, 0, 16)
		sub.Position = UDim2.fromOffset(14, 38)
		sub.TextTruncate = Enum.TextTruncate.AtEnd
		top = 56
	end
	local scroll = Kit.scroll(root, UDim2.new(1, 0, 1, -(top + inputH)), UDim2.fromOffset(0, top))
	scroll.Name = "Thread"
	scroll.ScrollBarThickness = 3
	local list = Kit.frame(scroll, UDim2.fromScale(1, 0))
	list.AutomaticSize = Enum.AutomaticSize.Y
	Kit.list(list, 6)
	Kit.padding(list, 4, 12, 8, 12)
	bubble(list, { who = "system", text = "Chat with " .. model.title .. ". Nothing you write here changes your company." }, 0)
	-- bubbles keyed by their turn (every turn has a stable id = its LayoutOrder): trimming the oldest turns
	-- removes their bubbles and never re-labels the others
	local drawn: { [any]: Frame } = {}
	local typingRow: Frame? = nil
	-- New bubbles scroll the thread to the newest one, and it keeps following while the canvas grows (the
	-- AutomaticCanvasSize / list size updates after the layout pass) until the player scrolls up to read older
	-- bubbles. The jump target lies beyond the end: the ScrollingFrame clamps CanvasPosition (the usual chat-log
	-- idiom), and reading the clamped value back tells a scroll-up by the player from the canvas growing.
	local stick = true
	local lastSet = -1
	local function jump()
		if not scroll.Parent then return end
		scroll.CanvasPosition = Vector2.new(0, math.max(scroll.AbsoluteCanvasSize.Y, list.AbsoluteSize.Y) + 40)
		lastSet = scroll.CanvasPosition.Y
	end
	local function follow()
		if stick then jump() end
	end
	local function toBottom()
		stick = true -- new content: always show it
		jump()
		task.defer(follow)
	end
	scroll:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(follow)
	list:GetPropertyChangedSignal("AbsoluteSize"):Connect(follow)
	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		local y = scroll.CanvasPosition.Y
		if y < lastSet - 4 then
			stick = false -- the player scrolled up
		elseif y >= lastSet - 1 then
			stick = true -- back at the newest bubble
		end
	end)
	local function sync(v: View)
		local chat = v.chats[id]
		local turns: { any } = if chat then chat.turns else {}
		local keep: { [any]: boolean } = {}
		local added = false
		for i, turn in turns do
			keep[turn] = true
			local holder = drawn[turn]
			if holder then
				paintBubble(holder, turn)
			else
				drawn[turn] = bubble(list, turn, tonumber(turn.id) or i)
				added = true
			end
		end
		for turn, holder in drawn do
			if not keep[turn] then
				holder:Destroy()
				drawn[turn] = nil
			end
		end
		local waiting = chat ~= nil and chat.waiting == true
		if waiting and not typingRow then
			local holder = Kit.frame(list, UDim2.fromScale(1, 0))
			holder.Name = "Typing"
			holder.AutomaticSize = Enum.AutomaticSize.Y
			holder.LayoutOrder = 1073741824
			local b = Kit.frame(holder, UDim2.fromOffset(64, 30))
			b.BackgroundTransparency = 0
			b.BackgroundColor3 = P.card2
			Kit.corner(b, 14)
			local dots = Kit.text(b, "...", 18, F.bold, C.muted)
			dots.AutomaticSize = Enum.AutomaticSize.None
			dots.Size = UDim2.fromScale(1, 1)
			dots.TextXAlignment = Enum.TextXAlignment.Center
			typingRow = holder
			added = true
		elseif not waiting and typingRow then
			(typingRow :: Frame):Destroy()
			typingRow = nil
		end
		if added or waiting then toBottom() end
	end
	-- input row
	local inputRow = Kit.frame(root, UDim2.new(1, -20, 0, 44), UDim2.new(0, 10, 1, -(inputH - 4)))
	inputRow.Name = "InputRow"
	local box = Kit.input(inputRow, "Message " .. model.title, UDim2.new(1, -52, 1, 0))
	box.Name = "ChatInput"
	box.TextSize = 15
	box.ClipsDescendants = true
	box.BackgroundColor3 = P.card2
	box.BackgroundTransparency = 0
	local chat0 = view.chats[id]
	if chat0 and typeof(chat0.draft) == "string" then box.Text = chat0.draft end -- the unsent draft survives calls and navigation
	local send = PhoneKit.tap(inputRow, UDim2.fromOffset(44, 44), UDim2.new(1, 0, 0, 0))
	send.Name = "Send"
	send.AnchorPoint = Vector2.new(1, 0)
	send.BackgroundTransparency = 0
	send.Selectable = true
	Theme.bindAccent(send, "BackgroundColor3")
	Kit.corner(send, 22)
	local arrow = Kit.text(send, "›", 30, F.bold, C.bg)
	arrow.AutomaticSize = Enum.AutomaticSize.None
	arrow.Size = UDim2.fromScale(1, 1)
	arrow.TextXAlignment = Enum.TextXAlignment.Center
	local function submit()
		local text = box.Text
		if not string.match(text, "%S") then return end
		local chat = ctx.view.chats[id]
		if chat and chat.waiting then return end
		box.Text = ""
		ctx.deps.sendChat(id, text)
	end
	Kit.onClick(send, submit)
	box.FocusLost:Connect(function(enter: boolean) if enter then submit() end end)
	-- limit the typed text to the server's length (characters) and keep it as the draft
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local n = utf8.len(box.Text)
		if n and n > PhoneMath.CHAT_MAX_CHARS then
			local cut = utf8.offset(box.Text, PhoneMath.CHAT_MAX_CHARS + 1)
			if cut then box.Text = string.sub(box.Text, 1, cut - 1) end
			return
		end
		ctx.deps.setDraft(id, box.Text)
	end)
	sync(view)
	select(ctx, send)
	return {
		sig = function(v: View): string
			local chat = v.chats[id]
			if not chat then return "0" end
			return tostring(chat.seq) .. ":" .. #chat.turns .. ":" .. tostring(chat.waiting)
		end,
		update = sync,
	}
end

------------------------------------------------------------------------------------------------ settings
function Screens.settings(ctx: Ctx): Built
	local view = ctx.view
	PhoneKit.header(ctx.content, "Settings", ctx.back)
	local _, list = PhoneKit.body(ctx.content)
	local function toggleRow(order: number, title: string, desc: string, on: boolean, key: string): Frame
		local box = card(list, order, 6)
		box.Name = "Setting_" .. key
		-- the whole row (44 px) flips the switch, not only the small switch
		local top = PhoneKit.tap(box, UDim2.new(1, 0, 0, 44))
		top.Name = "Row"
		top.LayoutOrder = 1
		top.Selectable = false
		local t = Kit.text(top, title, 15, F.bold, C.text)
		t.AutomaticSize = Enum.AutomaticSize.None
		t.Size = UDim2.new(1, -64, 1, 0)
		t.TextWrapped = true
		local tg = PhoneKit.toggle(top, on, function(v: boolean) ctx.deps.setSetting(key, v) end)
		tg.frame.AnchorPoint = Vector2.new(1, 0.5)
		tg.frame.Position = UDim2.new(1, 0, 0.5, 0)
		Kit.onClick(top, tg.flip)
		Kit.para(box, desc, 13, C.muted, 2)
		return box
	end
	local trips = toggleRow(1, "Join business trips automatically",
		"When a client meeting needs you, the trip starts by itself after a short countdown you can cancel. Off: your assistant asks first.", view.settings.autoTrips, "autoTrips")
	local status = Kit.para(trips, (if view.settings.saved then "Saved with your company." else "Kept for this session.")
		.. (if view.hooks.itinerary then "" else " The travel desk that uses it is coming soon."), 12, C.dim, 3)
	status.Name = "SaveState"
	local popups = toggleRow(2, "Call pop-ups", "On: a ringing call shows a banner, or the call screen while the phone is open. Off: calls only appear in Calls, with a badge.",
		view.settings.popups, "popups")
	local pstate = Kit.para(popups, "Kept for this session.", 12, C.dim, 3)
	pstate.Name = "PopupState"
	local info = card(list, 3, 4)
	info.Name = "PhoneInfo"
	local t = Kit.text(info, "Company phones", 15, F.bold, C.text)
	t.LayoutOrder = 1
	Kit.para(info, view.phoneCost, 13, C.muted, 2).Name = "Cost"
	Kit.para(info, if UserInputService.KeyboardEnabled then "Shortcut: P opens and closes the phone." else "Tip: the phone button sits in the bottom-right corner.", 12, C.dim, 3)
	select(ctx, ctx.content:FindFirstChild("Toggle", true) :: GuiObject?)
	return { sig = function(v: View): string
		return tostring(v.settings.autoTrips) .. tostring(v.settings.popups) .. tostring(v.settings.saved) .. v.phoneCost .. tostring(v.hooks.itinerary)
	end }
end

return Screens
