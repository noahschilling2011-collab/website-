--!strict
-- PhoneKit (package "phone"): the small building blocks of the company phone UI. Typed Instance.new + direct
-- property writes like UI/Kit (luau-lsp checks the property names). Icons are drawn from Frames (no emoji, no
-- asset ids, no Rotation so they look the same everywhere). Sizes are design pixels inside the phone frame,
-- which has its own UIScale (Screens/Phone).
local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local C = Theme.colors
local F = Theme.font

local PhoneKit = {}

PhoneKit.colors = {
	screen = Color3.fromRGB(10, 14, 16),
	card = Color3.fromRGB(26, 34, 37),
	card2 = Color3.fromRGB(34, 44, 47),
	bezel = Color3.fromRGB(6, 7, 8),
	messages = Color3.fromRGB(52, 186, 96),
	calls = Color3.fromRGB(38, 166, 132),
	calendar = Color3.fromRGB(226, 92, 84),
	contacts = Color3.fromRGB(104, 126, 168),
	settings = Color3.fromRGB(104, 114, 122),
	map = Color3.fromRGB(64, 150, 226),
	finance = Color3.fromRGB(214, 168, 52),
	team = Color3.fromRGB(166, 112, 220),
	accept = Color3.fromRGB(52, 186, 96),
	decline = Color3.fromRGB(226, 84, 76),
	badge = Color3.fromRGB(236, 72, 64),
}
local P = PhoneKit.colors

export type Badge = { frame: Frame, set: (n: number) -> () }
export type Tile = { button: TextButton, badge: Badge }
export type Toggle = { frame: TextButton, set: (on: boolean) -> (), get: () -> boolean, flip: () -> () }

-- a TextButton without the default look (the phone's tap targets)
function PhoneKit.tap(parent: Instance?, size: UDim2?, position: UDim2?): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundTransparency = 1
	b.Text = ""
	b.Size = size or UDim2.fromScale(1, 1)
	b.Position = position or UDim2.new()
	b.Parent = parent
	return b
end

-- Line icon of `kind` in a square of `size` design px (white unless color is given)
function PhoneKit.glyph(parent: Instance, kind: string, size: number, color: Color3?): Frame
	local frame = Kit.frame(parent, UDim2.fromOffset(size, size))
	frame.Name = "Glyph_" .. kind
	local col = color or C.white
	local function block(x: number, y: number, w: number, h: number, radius: number?)
		local b = Kit.frame(frame, UDim2.fromScale(w, h), UDim2.fromScale(x, y))
		b.BackgroundTransparency = 0
		b.BackgroundColor3 = col
		Kit.corner(b, radius or 2)
	end
	local function ring(x: number, y: number, w: number, h: number, radius: number, thick: number?)
		local r = Kit.frame(frame, UDim2.fromScale(w, h), UDim2.fromScale(x, y))
		Kit.corner(r, radius)
		Kit.stroke(r, 0, col, thick or math.max(1.5, size / 14))
	end
	if kind == "messages" then
		block(0.08, 0.14, 0.84, 0.58, math.floor(size * 0.22))
		block(0.2, 0.62, 0.2, 0.22, 2)
		local dots = { 0.27, 0.45, 0.63 }
		for _, x in dots do
			local d = Kit.frame(frame, UDim2.fromScale(0.1, 0.1), UDim2.fromScale(x, 0.38))
			d.BackgroundTransparency = 0.15
			d.BackgroundColor3 = P.messages:Lerp(C.black, 0.25)
			Kit.corner(d, size)
		end
	elseif kind == "calls" then -- desk telephone: handset bar, body, dial
		block(0.06, 0.18, 0.88, 0.17, math.floor(size * 0.1))
		block(0.06, 0.18, 0.2, 0.3, 3)
		block(0.74, 0.18, 0.2, 0.3, 3)
		block(0.18, 0.46, 0.64, 0.42, math.floor(size * 0.12))
		local dial = Kit.frame(frame, UDim2.fromScale(0.28, 0.28), UDim2.fromScale(0.36, 0.53))
		dial.BackgroundTransparency = 0
		dial.BackgroundColor3 = P.calls
		Kit.corner(dial, size)
	elseif kind == "calendar" then
		ring(0.1, 0.18, 0.8, 0.72, math.floor(size * 0.14))
		block(0.1, 0.18, 0.8, 0.2, math.floor(size * 0.1))
		block(0.28, 0.06, 0.1, 0.2, 2)
		block(0.62, 0.06, 0.1, 0.2, 2)
		for row = 0, 1 do
			for col2 = 0, 2 do block(0.24 + col2 * 0.2, 0.5 + row * 0.18, 0.12, 0.1, 1) end
		end
	elseif kind == "contacts" then
		local head = Kit.frame(frame, UDim2.fromScale(0.36, 0.36), UDim2.fromScale(0.32, 0.08))
		head.BackgroundTransparency = 0
		head.BackgroundColor3 = col
		Kit.corner(head, size)
		block(0.14, 0.52, 0.72, 0.4, math.floor(size * 0.22))
	elseif kind == "chat" then -- bubble with "AI"
		block(0.06, 0.12, 0.88, 0.62, math.floor(size * 0.2))
		block(0.62, 0.62, 0.2, 0.22, 2)
		local label = Kit.text(frame, "AI", math.floor(size * 0.36), F.black, Color3.fromRGB(20, 26, 28))
		label.AutomaticSize = Enum.AutomaticSize.None
		label.Size = UDim2.fromScale(0.88, 0.62)
		label.Position = UDim2.fromScale(0.06, 0.12)
		label.TextXAlignment = Enum.TextXAlignment.Center
	elseif kind == "settings" then -- gear: ring with four teeth and a hub
		block(0.42, 0.02, 0.16, 0.2, 2)
		block(0.42, 0.78, 0.16, 0.2, 2)
		block(0.02, 0.42, 0.2, 0.16, 2)
		block(0.78, 0.42, 0.2, 0.16, 2)
		ring(0.18, 0.18, 0.64, 0.64, size, math.max(2, size / 9))
		local hub = Kit.frame(frame, UDim2.fromScale(0.24, 0.24), UDim2.fromScale(0.38, 0.38))
		hub.BackgroundTransparency = 0
		hub.BackgroundColor3 = col
		Kit.corner(hub, size)
	elseif kind == "map" then -- location pin: round head with a hole, pointed foot
		local head = Kit.frame(frame, UDim2.fromScale(0.56, 0.56), UDim2.fromScale(0.22, 0.06))
		head.BackgroundTransparency = 0
		head.BackgroundColor3 = col
		Kit.corner(head, size)
		block(0.42, 0.5, 0.16, 0.36, 3)
		local hole = Kit.frame(frame, UDim2.fromScale(0.22, 0.22), UDim2.fromScale(0.39, 0.23))
		hole.BackgroundTransparency = 0
		hole.BackgroundColor3 = P.map:Lerp(C.black, 0.15)
		Kit.corner(hole, size)
		block(0.2, 0.88, 0.6, 0.08, 2)
	elseif kind == "finance" then -- rising bars on a base line
		block(0.12, 0.56, 0.18, 0.3, 2)
		block(0.41, 0.38, 0.18, 0.48, 2)
		block(0.7, 0.16, 0.18, 0.7, 2)
		block(0.06, 0.88, 0.88, 0.08, 2)
	elseif kind == "team" then -- two people
		local h1 = Kit.frame(frame, UDim2.fromScale(0.28, 0.28), UDim2.fromScale(0.12, 0.14))
		h1.BackgroundTransparency = 0
		h1.BackgroundColor3 = col
		Kit.corner(h1, size)
		local h2 = Kit.frame(frame, UDim2.fromScale(0.28, 0.28), UDim2.fromScale(0.6, 0.14))
		h2.BackgroundTransparency = 0
		h2.BackgroundColor3 = col
		Kit.corner(h2, size)
		block(0.02, 0.5, 0.48, 0.38, math.floor(size * 0.16))
		block(0.5, 0.5, 0.48, 0.38, math.floor(size * 0.16))
	elseif kind == "signal" then
		for i = 0, 3 do block(0.04 + i * 0.25, 0.7 - i * 0.2, 0.17, 0.3 + i * 0.2, 1) end
	elseif kind == "battery" then
		ring(0.02, 0.22, 0.82, 0.56, 3, 1.2)
		block(0.1, 0.32, 0.6, 0.36, 1)
		block(0.86, 0.38, 0.1, 0.24, 1)
	elseif kind == "driver" then -- car: body, roof, wheels
		block(0.06, 0.44, 0.88, 0.3, math.floor(size * 0.12))
		block(0.24, 0.22, 0.52, 0.3, math.floor(size * 0.12))
		local w1 = Kit.frame(frame, UDim2.fromScale(0.22, 0.22), UDim2.fromScale(0.16, 0.66))
		w1.BackgroundTransparency = 0
		w1.BackgroundColor3 = Color3.fromRGB(20, 26, 28)
		Kit.corner(w1, size)
		Kit.stroke(w1, 0, col, 1.5)
		local w2 = w1:Clone()
		w2.Position = UDim2.fromScale(0.62, 0.66)
		w2.Parent = frame
	elseif kind == "desk" then -- reception desk with a bell
		block(0.06, 0.56, 0.88, 0.3, 3)
		block(0.36, 0.28, 0.28, 0.22, math.floor(size * 0.14))
		block(0.46, 0.18, 0.08, 0.1, 1)
	elseif kind == "server" then -- rack with blades
		ring(0.16, 0.06, 0.68, 0.88, 3)
		for i = 0, 2 do block(0.26, 0.18 + i * 0.25, 0.48, 0.12, 1) end
	elseif kind == "assistant" then
		local head = Kit.frame(frame, UDim2.fromScale(0.34, 0.34), UDim2.fromScale(0.33, 0.1))
		head.BackgroundTransparency = 0
		head.BackgroundColor3 = col
		Kit.corner(head, size)
		block(0.18, 0.52, 0.64, 0.38, math.floor(size * 0.2))
		block(0.47, 0.52, 0.06, 0.2, 1)
	end
	return frame
end

-- red count bubble at the top-right corner of `parent`
function PhoneKit.badge(parent: Instance, size: number?): Badge
	local s = size or 20
	local frame = Kit.frame(parent, UDim2.fromOffset(s, s), UDim2.new(1, s * 0.25, 0, -s * 0.35))
	frame.Name = "Badge"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3 = P.badge
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.ZIndex = 5
	frame.Visible = false
	Kit.corner(frame, s)
	Kit.stroke(frame, 0.2, P.screen, 2)
	local label = Kit.text(frame, "", math.floor(s * 0.66), F.bold, C.white)
	label.Name = "Count"
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.new(0, s, 1, 0)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.ZIndex = 6
	Kit.padding(label, 0, math.floor(s * 0.25), 0, math.floor(s * 0.25))
	return {
		frame = frame,
		set = function(n: number)
			frame.Visible = n > 0
			label.Text = if n > 99 then "99+" else tostring(n)
		end,
	}
end

-- home-screen app: rounded colour square with a glyph, label underneath, badge
function PhoneKit.tile(parent: Instance, kind: string, label: string, color: Color3?, order: number, iconSize: number?): Tile
	local s = iconSize or 58
	local button = PhoneKit.tap(parent, UDim2.fromOffset(s + 20, s + 26))
	button.Name = "App_" .. kind
	button.LayoutOrder = order
	button.Selectable = true
	local icon = Kit.frame(button, UDim2.fromOffset(s, s), UDim2.new(0.5, 0, 0, 0))
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.BackgroundTransparency = 0
	if color then icon.BackgroundColor3 = color else Theme.bindAccent(icon, "BackgroundColor3") end
	Kit.corner(icon, math.floor(s * 0.26))
	Kit.gradient(icon, C.white, Color3.fromRGB(190, 196, 200), 90)
	local g = PhoneKit.glyph(icon, kind, math.floor(s * 0.56))
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Position = UDim2.fromScale(0.5, 0.5)
	local text = Kit.text(button, label, 13, F.medium, C.text)
	text.AutomaticSize = Enum.AutomaticSize.None
	text.Size = UDim2.new(1, 0, 0, 18)
	text.Position = UDim2.fromOffset(0, s + 5)
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.TextTruncate = Enum.TextTruncate.AtEnd
	local badge = PhoneKit.badge(icon, 22)
	return { button = button, badge = badge }
end

-- round avatar with initials
function PhoneKit.avatar(parent: Instance, text: string, color: Color3, size: number): Frame
	local frame = Kit.frame(parent, UDim2.fromOffset(size, size))
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3 = color
	Kit.corner(frame, size)
	Kit.gradient(frame, C.white, Color3.fromRGB(170, 176, 182), 90)
	local label = Kit.text(frame, text, math.floor(size * 0.42), F.bold, C.white)
	label.AutomaticSize = Enum.AutomaticSize.None
	label.Size = UDim2.fromScale(1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Center
	return frame
end

-- colour of a sender / tone
local SENDER: { [string]: Color3 } = {
	Sales = Color3.fromRGB(64, 156, 236),
	HR = Color3.fromRGB(176, 120, 222),
	["Travel desk"] = Color3.fromRGB(236, 160, 64),
	["Guest house"] = Color3.fromRGB(204, 140, 96),
	["IT desk"] = Color3.fromRGB(96, 170, 200),
	Finance = Color3.fromRGB(208, 186, 80),
	Product = Color3.fromRGB(80, 196, 150),
	Pricing = Color3.fromRGB(120, 180, 120),
	Lab = Color3.fromRGB(150, 140, 230),
	Assistant = Color3.fromRGB(226, 120, 160),
	Company = Color3.fromRGB(120, 134, 150),
}
function PhoneKit.senderColor(from: string): Color3
	return SENDER[from] or SENDER.Company
end
function PhoneKit.toneColor(tone: string): Color3
	return if tone == "good" then C.good elseif tone == "bad" then C.bad elseif tone == "warn" then C.warn else C.muted
end

-- app header: back chevron + title (+ optional right-hand action)
function PhoneKit.header(parent: Instance, title: string, onBack: (() -> ())?, right: string?, onRight: (() -> ())?): (Frame, TextButton?)
	local bar = Kit.frame(parent, UDim2.new(1, 0, 0, 40))
	bar.Name = "Header"
	bar.LayoutOrder = 0
	local x = 14
	if onBack then
		-- 52 x 44 tap target (2 px beyond the 40 px bar at the top and bottom), the chevron stays centred
		local back = PhoneKit.tap(bar, UDim2.fromOffset(52, 44), UDim2.fromOffset(0, -2))
		back.Name = "Back"
		back.Selectable = true
		local chev = Kit.text(back, "‹", 30, F.bold, Theme.accent)
		Theme.bindAccent(chev, "TextColor3")
		chev.AutomaticSize = Enum.AutomaticSize.None
		chev.Size = UDim2.fromScale(1, 1)
		chev.TextXAlignment = Enum.TextXAlignment.Center
		chev.TextYAlignment = Enum.TextYAlignment.Center
		Kit.onClick(back, onBack)
		x = 46
	end
	local label = Kit.text(bar, title, 20, F.display, C.text)
	label.Name = "Title"
	label.AutomaticSize = Enum.AutomaticSize.None
	label.Size = UDim2.new(1, -x - (if right then 96 else 12), 1, 0)
	label.Position = UDim2.fromOffset(x, 0)
	label.TextTruncate = Enum.TextTruncate.AtEnd
	local action: TextButton? = nil
	if right and onRight then
		-- an 88 x 44 tap target around the visible 80 x 36 pill (touch: never a small target)
		local b = PhoneKit.tap(bar, UDim2.fromOffset(88, 44), UDim2.new(1, -4, 0.5, 0))
		b.Name = "HeaderAction"
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Selectable = true
		local pill = Kit.frame(b, UDim2.fromOffset(80, 36), UDim2.fromScale(0.5, 0.5))
		pill.Name = "Pill"
		pill.AnchorPoint = Vector2.new(0.5, 0.5)
		pill.BackgroundTransparency = 0
		pill.BackgroundColor3 = P.card2
		Kit.corner(pill, 18)
		local t = Kit.text(pill, right, 14, F.bold, C.text)
		t.Name = "ActionText"
		t.AutomaticSize = Enum.AutomaticSize.None
		t.Size = UDim2.fromScale(1, 1)
		t.TextXAlignment = Enum.TextXAlignment.Center
		Kit.onClick(b, onRight)
		action = b
	end
	return bar, action
end

-- on / off switch (flip() = what a tap does; a whole settings row calls it too)
function PhoneKit.toggle(parent: Instance, on: boolean, onChange: (on: boolean) -> ()): Toggle
	local b = PhoneKit.tap(parent, UDim2.fromOffset(52, 30))
	b.Name = "Toggle"
	b.BackgroundTransparency = 0
	b.Selectable = true
	Kit.corner(b, 15)
	local knob = Kit.frame(b, UDim2.fromOffset(24, 24), UDim2.new(0, 3, 0.5, 0))
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.BackgroundTransparency = 0
	knob.BackgroundColor3 = C.white
	Kit.corner(knob, 12)
	local state = on
	local function paint()
		b.BackgroundColor3 = if state then P.accept else C.raised
		knob.Position = if state then UDim2.new(1, -27, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
	end
	paint()
	local function flip()
		state = not state
		paint()
		onChange(state)
	end
	Kit.onClick(b, flip)
	return {
		frame = b,
		set = function(v: boolean)
			state = v
			paint()
		end,
		get = function(): boolean return state end,
		flip = flip,
	}
end

-- round call button (accept / decline) with a caption under it
function PhoneKit.callButton(parent: Instance, text: string, color: Color3, order: number, cross: boolean?): TextButton
	local holder = Kit.frame(parent, UDim2.fromOffset(110, 92))
	holder.LayoutOrder = order
	local b = PhoneKit.tap(holder, UDim2.fromOffset(64, 64), UDim2.new(0.5, 0, 0, 0))
	b.Name = "CallButton"
	b.AnchorPoint = Vector2.new(0.5, 0)
	b.BackgroundTransparency = 0
	b.BackgroundColor3 = color
	b.Selectable = true
	Kit.corner(b, 32)
	if cross then
		local x = Kit.text(b, "×", 40, F.bold, C.white)
		x.AutomaticSize = Enum.AutomaticSize.None
		x.Size = UDim2.fromScale(1, 1)
		x.TextXAlignment = Enum.TextXAlignment.Center
	else
		local g = PhoneKit.glyph(b, "calls", 34)
		g.AnchorPoint = Vector2.new(0.5, 0.5)
		g.Position = UDim2.fromScale(0.5, 0.5)
	end
	local label = Kit.text(holder, text, 13, F.medium, C.text)
	label.AutomaticSize = Enum.AutomaticSize.None
	label.Size = UDim2.new(1, 0, 0, 22)
	label.Position = UDim2.fromOffset(0, 68)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	return b
end

-- scrolling list body under a header (fills the rest of the screen)
function PhoneKit.body(parent: Instance, top: number?): (ScrollingFrame, Frame)
	local scroll = Kit.scroll(parent, UDim2.new(1, 0, 1, -(top or 40)), UDim2.fromOffset(0, top or 40))
	scroll.Name = "Body"
	scroll.ScrollBarThickness = 3
	scroll.Selectable = false
	local list = Kit.frame(scroll, UDim2.fromScale(1, 0))
	list.AutomaticSize = Enum.AutomaticSize.Y
	Kit.list(list, 6)
	Kit.padding(list, 4, 12, 12, 12)
	return scroll, list
end

-- empty-state text in the middle of a list
function PhoneKit.empty(parent: Instance, title: string, text: string, order: number?): Frame
	local box = Kit.frame(parent, UDim2.fromScale(1, 0))
	box.Name = "Empty"
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.LayoutOrder = order or 100
	Kit.list(box, 6).HorizontalAlignment = Enum.HorizontalAlignment.Center
	Kit.padding(box, 24, 10, 10, 10)
	local t = Kit.para(box, title, 16, C.text, 1)
	t.Font = F.bold
	t.TextXAlignment = Enum.TextXAlignment.Center
	local p = Kit.para(box, text, 14, C.muted, 2)
	p.TextXAlignment = Enum.TextXAlignment.Center
	return box
end

return PhoneKit
