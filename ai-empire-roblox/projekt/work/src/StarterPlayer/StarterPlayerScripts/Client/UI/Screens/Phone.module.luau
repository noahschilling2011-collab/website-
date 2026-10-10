--!strict
-- The company phone UI (package "phone"): its own ScreenGui "AIEmpire_Phone" with
--   * a phone button in the bottom-right corner (badge = unread messages + missed calls). On touch devices it
--     sits left of Roblox's jump button; it never overlaps the HUD column (top right).
--   * the phone itself, placed left of the HUD column: a dark smartphone with a status bar (company time and
--     day, decorative signal and battery), app screens (UI/Phone/PhoneScreens) and a navigation bar (back, home,
--     close). Portrait on desktops and consoles; LANDSCAPE on small screens (an iPhone held sideways), because
--     a portrait phone there would be too small to read. Its own UIScale per shape.
--   * an incoming-call banner next to the phone button (Answer / Decline) while the phone is closed.
-- The PhoneController feeds the view model (Phone.setView) and does every remote call (deps).
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local PhoneKit = require(UI.Phone.PhoneKit)
local Screens = require(UI.Phone.PhoneScreens)

local C = Theme.colors
local F = Theme.font
local P = PhoneKit.colors

type View = Screens.View
type Deps = Screens.Deps
type Built = Screens.Built

local Phone = {}

Phone.PORTRAIT = Vector2.new(330, 640) -- design size of the portrait phone
Phone.LANDSCAPE = Vector2.new(580, 300) -- design size of the landscape phone
Phone.BUTTON = 58
Phone.HUD_WIDTH = 300 + 16 -- HUD column width + its right margin (Screens/HUD: WIDTH = 300 at offset -16)
Phone.MARGIN = 12

local gui: ScreenGui? = nil
local phoneFrame: Frame? = nil
local phoneScale: UIScale? = nil
local content: Frame? = nil
local statusTime: TextLabel? = nil
local statusDay: TextLabel? = nil
local statusBar: Frame? = nil
local navBar: Frame? = nil
local screenArea: Frame? = nil
local button: TextButton? = nil
local buttonScale: UIScale? = nil
local buttonBadge: PhoneKit.Badge? = nil
local banner: Frame? = nil
local bannerScale: UIScale? = nil
local view: View? = nil
local deps: Deps? = nil
local current: { name: string, arg: any } = { name = "home", arg = nil }
local stack: { { name: string, arg: any } } = {}
local built: Built? = nil
local builtSig = ""
local landscape = false
local open = false
local hidden = false
local bannerCall: string? = nil
local layoutInfo: { [string]: any } = {}

Phone.layoutInfo = layoutInfo -- tests: chosen shape and scales

local function playerGui(): Instance?
	local player = Players.LocalPlayer
	return if player then player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui", 5) else nil
end

-- the UIRoot scale of the HUD layer (read from the real HUD ScreenGui; same formula as a fallback)
local function hudScale(size: Vector2): number
	local pg = playerGui()
	local hud = pg and pg:FindFirstChild("AIEmpire_HUD")
	local root = hud and hud:FindFirstChild("Root")
	local s = root and root:FindFirstChildOfClass("UIScale")
	if s then return s.Scale end
	if size.X <= 0 or size.Y <= 0 then return 1 end
	return math.clamp(math.min(size.X / 1280, size.Y / 720), 0.3, 1.25)
end

-- Roblox's touch jump button (PlayerModule TouchGui) in this gui's coordinates: (left x, top y, height) or nil
local function jumpButton(g: ScreenGui): (number?, number?, number?)
	local pg = playerGui()
	local touch = pg and pg:FindFirstChild("TouchGui")
	local frame = touch and touch:FindFirstChild("TouchControlFrame")
	local jump = frame and frame:FindFirstChild("JumpButton")
	if jump and jump:IsA("GuiObject") and jump.Visible then
		return jump.AbsolutePosition.X - g.AbsolutePosition.X, jump.AbsolutePosition.Y - g.AbsolutePosition.Y, jump.AbsoluteSize.Y
	end
	return nil, nil, nil
end

local function touchLayout(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

------------------------------------------------------------------------------------------------ layout
local function applyLayout()
	local g = gui
	local frame, scale = phoneFrame, phoneScale
	if not g or not frame or not scale then return end
	local size = g.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then return end
	local hs = hudScale(size)
	local hudW = Phone.HUD_WIDTH * hs
	local m = Phone.MARGIN
	-- phone button: bottom right; on touch screens left of the jump button
	local bs = math.clamp(hs * 1.3, 0.8, 1.15)
	local bpx = Phone.BUTTON * bs
	local right, bottom = m + 4, m + 4
	if touchLayout() then
		local jx, jy, jh = jumpButton(g)
		if jx and jy and jh then
			right = math.max(m, size.X - jx + 10)
			bottom = math.max(m, size.Y - (jy + jh * 0.5 + bpx * 0.5)) -- level with the jump button's centre
		else
			local small = math.min(size.X, size.Y) <= 500
			right = if small then 95 + 10 else 170 + 12 -- PlayerModule TouchJump: x = W - 1.5 * size + 10
			bottom = m
		end
	end
	if buttonScale and button then
		buttonScale.Scale = bs
		button.Position = UDim2.new(1, -right, 1, -bottom)
	end
	if bannerScale and banner then
		bannerScale.Scale = bs
		banner.Position = UDim2.new(1, -(right + bpx + 10), 1, -bottom)
	end
	-- the phone: left of the HUD column, portrait when it is readable, otherwise landscape
	local availW, availH = size.X - hudW - 2 * m, size.Y - 2 * m
	local pw, ph = Phone.PORTRAIT.X, Phone.PORTRAIT.Y
	local lw, lh = Phone.LANDSCAPE.X, Phone.LANDSCAPE.Y
	local sp = math.min(availH / ph, availW / pw, 1.15)
	local shapeLandscape = sp < 0.78
	local s = sp
	local rightEdge = hudW + m
	if shapeLandscape then
		s = math.min(availH / lh, availW / lw, 1.15)
		if s < 0.7 then -- very narrow: use the full width (the HUD column is only covered while the phone is open)
			s = math.min(availH / lh, (size.X - 2 * m) / lw, 1.15)
			rightEdge = m
		end
	end
	s = math.max(0.45, s)
	layoutInfo.landscape = shapeLandscape
	layoutInfo.scale = s
	layoutInfo.hudScale = hs
	layoutInfo.buttonScale = bs
	layoutInfo.rightEdge = rightEdge
	scale.Scale = s
	frame.Size = UDim2.fromOffset(if shapeLandscape then lw else pw, if shapeLandscape then lh else ph)
	frame.Position = UDim2.new(1, -rightEdge, 1, -m)
	if shapeLandscape ~= landscape then
		landscape = shapeLandscape
		builtSig = "" -- rebuild the screen in the new shape
		if open then Phone.render(true) end
	end
	-- chrome sizes per shape
	local sb, nb = statusBar, navBar
	if sb and nb and screenArea and content then
		local barH = if landscape then 22 else 30
		local navH = if landscape then 28 else 36
		sb.Size = UDim2.new(1, 0, 0, barH)
		nb.Size = UDim2.new(1, 0, 0, navH)
		content.Size = UDim2.new(1, 0, 1, -(barH + navH))
		content.Position = UDim2.fromOffset(0, barH)
	end
end
Phone.layout = applyLayout

------------------------------------------------------------------------------------------------ screens
local function clearContent()
	local c = content
	if not c then return end
	for _, child in c:GetChildren() do child:Destroy() end
end

local function ctxFor(): Screens.Ctx?
	local c, v, d = content, view, deps
	if not c or not v or not d then return nil end
	return {
		view = v,
		deps = d,
		go = function(name: string, arg: any?) Phone.go(name, arg) end,
		back = function() Phone.back() end,
		content = c,
		landscape = landscape,
	}
end

-- (re)build the current screen; force = always rebuild
function Phone.render(force: boolean?)
	local ctx = ctxFor()
	if not ctx then return end
	local builder = (Screens :: any)[current.name]
	if typeof(builder) ~= "function" then current = { name = "home", arg = nil }; builder = Screens.home end
	if not force and built then
		local b = built :: Built
		local sig = b.sig(ctx.view)
		if sig == builtSig then
			if b.live then b.live(ctx.view) end -- cheap in-place updates (clock text)
			return
		end
		if b.update then
			b.update(ctx.view)
			builtSig = sig
			return
		end
	end
	-- keep the scroll position of a list that is rebuilt in place
	local keep: Vector2? = nil
	local c = content
	local old = c and c:FindFirstChild("Body")
	if not force and old and old:IsA("ScrollingFrame") then keep = old.CanvasPosition end
	clearContent()
	local result: Built = builder(ctx, current.arg)
	built = result
	builtSig = result.sig(ctx.view)
	local body = c and c:FindFirstChild("Body")
	if keep and body and body:IsA("ScrollingFrame") then body.CanvasPosition = keep end
end

function Phone.go(name: string, arg: any?)
	if current.name ~= name or current.arg ~= arg then
		table.insert(stack, current)
		while #stack > 12 do table.remove(stack, 1) end
	end
	current = { name = name, arg = arg }
	if name == "home" then table.clear(stack) end
	Phone.render(true)
end

function Phone.back()
	local prev = table.remove(stack)
	if not prev then
		if current.name == "home" then Phone.close() return end
		prev = { name = "home", arg = nil }
	end
	current = prev :: any
	Phone.render(true)
end

function Phone.screen(): (string, any)
	return current.name, current.arg
end

------------------------------------------------------------------------------------------------ open / close
local function refreshBadge()
	local v = view
	if buttonBadge and v then (buttonBadge :: PhoneKit.Badge).set(v.unread + v.missed) end
end

local function updateVisibility()
	if button then (button :: TextButton).Visible = not hidden end
	if phoneFrame then (phoneFrame :: Frame).Visible = open and not hidden end
	if banner then (banner :: Frame).Visible = bannerCall ~= nil and not open and not hidden end
end

function Phone.isOpen(): boolean
	return open
end

function Phone.open(name: string?, arg: any?)
	if hidden or not view then return end
	local d = deps
	if d then d.refresh() end -- fresh calendar and model list (setView does not render while closed)
	open = true
	Phone.hideBanner()
	applyLayout()
	updateVisibility()
	if name then
		table.clear(stack)
		if name ~= "home" then table.insert(stack, { name = "home", arg = nil }) end
		current = { name = name, arg = arg }
	end
	Phone.render(true)
end

function Phone.close()
	if not open then return end
	open = false
	if UserInputService.GamepadEnabled and GuiService.SelectedObject and phoneFrame and GuiService.SelectedObject:IsDescendantOf(phoneFrame :: Frame) then
		GuiService.SelectedObject = nil
	end
	local c = content
	local box = c and c:FindFirstChild("ChatInput", true)
	if box and box:IsA("TextBox") and box:IsFocused() then box:ReleaseFocus() end
	updateVisibility()
end

function Phone.toggle()
	if open then Phone.close() else Phone.open() end
end

-- hide everything (Computer open, intro, no company); closes the phone
function Phone.setHidden(value: boolean)
	if hidden == value then return end
	hidden = value
	if value then Phone.close() end
	updateVisibility()
end

function Phone.isHidden(): boolean
	return hidden
end

-- new data from the controller: badges, status bar, the open screen when its data changed
function Phone.setView(v: View)
	view = v
	refreshBadge()
	if statusTime then (statusTime :: TextLabel).Text = v.status end
	if statusDay then (statusDay :: TextLabel).Text = v.dayText end
	if open then Phone.render(false) end
end

------------------------------------------------------------------------------------------------ incoming call banner
function Phone.hideBanner()
	bannerCall = nil
	local b = banner
	if b then
		for _, child in b:GetChildren() do if child:IsA("GuiObject") then child:Destroy() end end
	end
	updateVisibility()
end

-- show a ringing call: the call screen when the phone is open, else the banner next to the phone button
function Phone.incoming(call: any)
	if open then
		Phone.go("call", call.id)
		return
	end
	local b = banner
	if not b or hidden then return end
	Phone.hideBanner()
	bannerCall = call.id
	local card = Kit.frame(b, UDim2.fromScale(1, 1))
	card.Name = "Card"
	card.BackgroundTransparency = 0.02
	card.BackgroundColor3 = P.card
	Kit.corner(card, 16)
	Kit.stroke(card, 0.8)
	local av = PhoneKit.avatar(card, string.sub(tostring(call.from), 1, 1), PhoneKit.senderColor(tostring(call.from)), 40)
	av.Position = UDim2.new(0, 10, 0.5, -20)
	local who = Kit.text(card, tostring(call.from) .. " is calling", 13, F.medium, C.muted)
	who.Position = UDim2.fromOffset(60, 9)
	local title = Kit.text(card, tostring(call.title), 15, F.bold, C.text)
	title.Name = "Title"
	title.AutomaticSize = Enum.AutomaticSize.None
	title.Size = UDim2.new(1, -172, 0, 20)
	title.Position = UDim2.fromOffset(60, 29)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	local function round(name: string, color: Color3, x: number, cross: boolean): TextButton
		local r = PhoneKit.tap(card, UDim2.fromOffset(42, 42), UDim2.new(1, x, 0.5, 0))
		r.Name = name
		r.AnchorPoint = Vector2.new(1, 0.5)
		r.BackgroundTransparency = 0
		r.BackgroundColor3 = color
		r.Selectable = true
		Kit.corner(r, 21)
		if cross then
			local t = Kit.text(r, "×", 28, F.bold, C.white)
			t.AutomaticSize = Enum.AutomaticSize.None
			t.Size = UDim2.fromScale(1, 1)
			t.TextXAlignment = Enum.TextXAlignment.Center
		else
			local g = PhoneKit.glyph(r, "calls", 24)
			g.AnchorPoint = Vector2.new(0.5, 0.5)
			g.Position = UDim2.fromScale(0.5, 0.5)
		end
		return r
	end
	local decline = round("Decline", P.decline, -62, true)
	local answer = round("Answer", P.accept, -12, false)
	local id = call.id
	Kit.onClick(answer, function()
		Phone.hideBanner()
		Phone.open("call", id)
	end)
	Kit.onClick(decline, function()
		Phone.hideBanner()
		local d = deps
		if d then d.answer(id, "decline") end
	end)
	updateVisibility()
	local ring = tonumber(call.ring) or 25
	task.delay(ring, function()
		if bannerCall == id then Phone.hideBanner() end
	end)
end

function Phone.bannerCall(): string?
	return bannerCall
end

------------------------------------------------------------------------------------------------ mount
local function chromeButton(parent: Instance, name: string, text: string, size: number, x: UDim): TextButton
	local b = PhoneKit.tap(parent, UDim2.new(0, 64, 1, 0), UDim2.new(x, UDim.new(0, 0)))
	b.Name = name
	b.AnchorPoint = Vector2.new(0.5, 0)
	b.Selectable = true
	local t = Kit.text(b, text, size, F.bold, C.muted)
	t.AutomaticSize = Enum.AutomaticSize.None
	t.Size = UDim2.fromScale(1, 1)
	t.TextXAlignment = Enum.TextXAlignment.Center
	return b
end

function Phone.mount(parent: Instance, d: Deps)
	deps = d
	local old = parent:FindFirstChild("AIEmpire_Phone")
	if old then old:Destroy() end
	local g = Instance.new("ScreenGui")
	g.Name = "AIEmpire_Phone"
	g.ResetOnSpawn = false
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	g.DisplayOrder = 15 -- above the HUD (10), below the Computer (19/20) and the talk panels (41/42)
	g.Parent = parent
	gui = g

	-- phone button
	local b = PhoneKit.tap(g, UDim2.fromOffset(Phone.BUTTON, Phone.BUTTON))
	b.Name = "PhoneButton"
	b.AnchorPoint = Vector2.new(1, 1)
	b.BackgroundTransparency = 0.02
	b.BackgroundColor3 = P.card
	b.Selectable = true
	Kit.corner(b, 18)
	Kit.stroke(b, 0.78)
	local bs = Instance.new("UIScale")
	bs.Parent = b
	buttonScale = bs
	local icon = Kit.frame(b, UDim2.fromOffset(40, 40), UDim2.fromScale(0.5, 0.5))
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.BackgroundTransparency = 0
	Theme.bindAccent(icon, "BackgroundColor3")
	Kit.corner(icon, 12)
	local ig = PhoneKit.glyph(icon, "calls", 24, P.screen)
	ig.AnchorPoint = Vector2.new(0.5, 0.5)
	ig.Position = UDim2.fromScale(0.5, 0.5)
	buttonBadge = PhoneKit.badge(b, 22)
	if UserInputService.KeyboardEnabled then
		local key = Kit.text(b, "P", 11, F.bold, C.dim)
		key.AnchorPoint = Vector2.new(0.5, 1)
		key.Position = UDim2.new(0.5, 0, 1, -1)
		key.Name = "Key"
	end
	Kit.onClick(b, Phone.toggle)
	button = b

	-- incoming call banner (left of the button)
	local bn = Kit.frame(g, UDim2.fromOffset(380, 64))
	bn.Name = "CallBanner"
	bn.AnchorPoint = Vector2.new(1, 1)
	bn.Visible = false
	local bns = Instance.new("UIScale")
	bns.Parent = bn
	banner = bn
	bannerScale = bns

	-- the phone
	local frame = Kit.frame(g, UDim2.fromOffset(Phone.PORTRAIT.X, Phone.PORTRAIT.Y))
	frame.Name = "PhoneFrame"
	frame.AnchorPoint = Vector2.new(1, 1)
	frame.Visible = false
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3 = P.bezel
	frame.Active = true
	Kit.corner(frame, 40)
	Kit.stroke(frame, 0.55, Color3.fromRGB(70, 78, 82), 2)
	local ps = Instance.new("UIScale")
	ps.Parent = frame
	phoneFrame, phoneScale = frame, ps
	-- swallow taps on the phone body (no camera turn underneath)
	local sink = PhoneKit.tap(frame)
	sink.Name = "Sink"
	sink.Selectable = false
	local screen = Kit.frame(frame, UDim2.new(1, -16, 1, -16), UDim2.fromOffset(8, 8))
	screen.Name = "Screen"
	screen.BackgroundTransparency = 0
	screen.BackgroundColor3 = P.screen
	screen.ClipsDescendants = true
	Kit.corner(screen, 32)
	screenArea = screen
	-- wallpaper: a soft accent glow at the top
	local glow = Kit.frame(screen, UDim2.new(1, 0, 0.55, 0))
	glow.Name = "Wallpaper"
	glow.BackgroundTransparency = 0.55
	Theme.bindAccent(glow, "BackgroundColor3", Theme.darker(0.45))
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	grad.Parent = glow
	-- status bar: time · notch · day + signal + battery
	local sb = Kit.frame(screen, UDim2.new(1, 0, 0, 30))
	sb.Name = "StatusBar"
	statusBar = sb
	local tl = Kit.text(sb, "--:--", 14, F.bold, C.text)
	tl.Name = "Time"
	tl.AnchorPoint = Vector2.new(0, 0.5)
	tl.Position = UDim2.new(0, 22, 0.5, 1)
	statusTime = tl
	local notch = Kit.frame(sb, UDim2.fromOffset(84, 20), UDim2.new(0.5, 0, 0, 5))
	notch.Name = "Notch"
	notch.AnchorPoint = Vector2.new(0.5, 0)
	notch.BackgroundTransparency = 0
	notch.BackgroundColor3 = P.bezel
	Kit.corner(notch, 10)
	local rightBox = Kit.frame(sb, UDim2.fromOffset(120, 20), UDim2.new(1, -18, 0.5, 1))
	rightBox.AnchorPoint = Vector2.new(1, 0.5)
	local rl = Kit.list(rightBox, 5, true)
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	local dl = Kit.text(rightBox, "", 12, F.bold, C.muted)
	dl.Name = "Day"
	dl.LayoutOrder = 1
	statusDay = dl
	PhoneKit.glyph(rightBox, "signal", 14, C.text).LayoutOrder = 2
	PhoneKit.glyph(rightBox, "battery", 20, C.text).LayoutOrder = 3
	-- content
	local c = Kit.frame(screen, UDim2.new(1, 0, 1, -66), UDim2.fromOffset(0, 30))
	c.Name = "Content"
	c.ClipsDescendants = true
	content = c
	-- navigation bar: back · home · close
	local nb = Kit.frame(screen, UDim2.new(1, 0, 0, 36), UDim2.fromScale(0, 1))
	nb.Name = "NavBar"
	nb.AnchorPoint = Vector2.new(0, 1)
	navBar = nb
	local back = chromeButton(nb, "NavBack", "‹", 26, UDim.new(0.2, 0))
	Kit.onClick(back, Phone.back)
	local home = PhoneKit.tap(nb, UDim2.new(0, 96, 1, 0), UDim2.fromScale(0.5, 0))
	home.Name = "NavHome"
	home.AnchorPoint = Vector2.new(0.5, 0)
	home.Selectable = true
	local pill = Kit.frame(home, UDim2.fromOffset(84, 5), UDim2.fromScale(0.5, 0.5))
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.BackgroundTransparency = 0.1
	pill.BackgroundColor3 = C.text
	Kit.corner(pill, 3)
	Kit.onClick(home, function() Phone.go("home") end)
	local close = chromeButton(nb, "NavClose", "×", 24, UDim.new(0.8, 0))
	Kit.onClick(close, Phone.close)

	g:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
	applyLayout()
	updateVisibility()
end

function Phone.gui(): ScreenGui?
	return gui
end

return Phone
