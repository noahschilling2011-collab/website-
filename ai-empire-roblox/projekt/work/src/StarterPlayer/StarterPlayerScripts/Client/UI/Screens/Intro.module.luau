--!strict
-- Intro: title screen and company founding (ONBOARDING_SPEC A7, menu package). Own inset-free layer above everything
-- until a company exists. One screen: "AI Empire", one line, the company name box prefilled with a random fictional
-- name (CompanyConfig.COMPANY_NAME_IDEAS), a dice for another one, START (1 tap) and "Customize (optional) ›", which
-- opens today's logo, colour and specialization controls on the same screen (defaults LOGOS[1], COLORS[1], General).
-- Own UIScale with the Studio formula s = clamp(min(A.X/1254, A.Y/520), 0.5, 1.25) (text >= 20 px = 12 pt on phones).
-- With a company: "Welcome back" + CONTINUE. After a debug reset it shows again.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local CompanyConfig = require(Shared.Config.CompanyConfig)
local Format = require(Shared.Format)
local Types = require(Shared.Types)

local UI = script.Parent.Parent
local Client = UI.Parent
local StateController = require(Client.Controllers.StateController)
local ActionController = require(Client.Controllers.ActionController)
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Toast = require(UI.Toast)

local C = Theme.colors
local F = Theme.font

export type Callbacks = { onFinish: () -> (), onReopen: () -> () }

local Intro = {}

Intro.CANVAS = Vector2.new(1254, 520)
Intro.LINE = `You start in a garage with ${Format.int(GameConfig.START_MONEY)}. Build the biggest AI company.`

local function trim(text: string): string
	return (string.gsub(string.gsub(text, "^%s+", ""), "%s+$", ""))
end

local function validName(text: string): boolean
	local length = utf8.len(trim(text))
	return length ~= nil and length >= GameConfig.COMPANY_NAME_MIN and length <= GameConfig.COMPANY_NAME_MAX
end

local function colorOf(id: string): Color3
	local def = CompanyConfig.getColor(id)
	return if def then Theme.rgb(def.rgb) else Theme.DEFAULT_ACCENT
end

-- a random entry of COMPANY_NAME_IDEAS, never `except` (the dice always changes the name)
function Intro.nameIdea(except: string?): string
	local list = CompanyConfig.COMPANY_NAME_IDEAS
	if #list == 0 then
		return ""
	end
	for _ = 1, 8 do
		local pick = list[math.random(1, #list)]
		if pick ~= except then
			return pick
		end
	end
	return list[1]
end

local function designScale(inst: Instance, skip: UIScale?): number
	local s = 1
	local node: Instance? = inst
	while node do
		local u = node:FindFirstChildOfClass("UIScale")
		if u and u ~= skip then
			s *= u.Scale
		end
		node = node.Parent
	end
	return if s > 0 then s else 1
end

function Intro.mount(parent: Frame, callbacks: Callbacks)
	local blocker = Kit.blocker(parent, C.bg, 0)
	blocker.Name = "Intro"
	blocker.ZIndex = 30

	-- own scale (Studio formula) around a 1254-wide canvas
	local canvas = Kit.frame(blocker)
	canvas.Name = "Canvas"
	local scale = Instance.new("UIScale")
	scale.Parent = canvas
	local function applyScale()
		local A = blocker.AbsoluteSize
		local P = designScale(blocker, scale)
		local s = if A.X > 0 and A.Y > 0 then math.clamp(math.min(A.X / Intro.CANVAS.X, A.Y / Intro.CANVAS.Y), 0.5, 1.25) else 1
		local k = s / P
		scale.Scale = k
		canvas.Size = UDim2.fromScale(1 / k, 1 / k)
	end
	blocker:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(applyScale)
	end)
	applyScale()

	local scroll = Kit.scroll(canvas)
	scroll.Name = "IntroScroll"
	Kit.padding(scroll, 92, 24, 24, 24) -- the layer is inset-free: room for the Roblox top bar
	-- fix round 1 (review): the scroll (and its scrollbar) stays inside the device's safe area on the sides and the
	-- bottom (notch, home indicator). The insets are read from a CoreUISafeInsets layer of the UI (AIEmpire_Overlay:
	-- its left / right / bottom edges are the device's safe area; its top includes the Roblox top bar, which the
	-- 92 px top padding already clears), in screen px, then turned into this canvas's design px
	local function safeArea()
		local layer = blocker:FindFirstAncestorWhichIsA("ScreenGui")
		local playerGui = if layer then layer.Parent else nil
		local safeGui = if playerGui then playerGui:FindFirstChild("AIEmpire_Overlay") else nil
		if not safeGui or not safeGui:IsA("ScreenGui") then
			return
		end
		local full, fullPos = blocker.AbsoluteSize, blocker.AbsolutePosition
		local safe, safePos = safeGui.AbsoluteSize, safeGui.AbsolutePosition
		if full.X <= 0 or full.Y <= 0 or safe.X <= 0 or safe.Y <= 0 then
			return
		end
		local k = designScale(canvas)
		local left = math.max(0, safePos.X - fullPos.X) / k
		local right = math.max(0, (fullPos.X + full.X) - (safePos.X + safe.X)) / k
		local bottom = math.max(0, (fullPos.Y + full.Y) - (safePos.Y + safe.Y)) / k
		scroll.Position = UDim2.fromOffset(left, 0)
		scroll.Size = UDim2.new(1, -(left + right), 1, -bottom)
	end
	blocker:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(safeArea)
	end)
	task.defer(safeArea)
	local scrollList = Kit.list(scroll, 14)
	scrollList.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local column = Kit.frame(scroll, UDim2.fromOffset(860, 0))
	column.Name = "Column"
	column.AutomaticSize = Enum.AutomaticSize.Y
	local columnList = Kit.list(column, 12)
	columnList.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local title = Kit.text(column, "AI Empire", 72, F.display, C.white)
	title.Name = "Title"
	title.LayoutOrder = 1
	local line = Kit.text(column, Intro.LINE, 26, F.medium, C.muted)
	line.Name = "Line"
	line.LayoutOrder = 2
	local status = Kit.text(column, "Connecting...", 22, F.medium, C.dim)
	status.Name = "Status"
	status.LayoutOrder = 3

	-- the name form
	local form = Kit.panel(column, UDim2.fromScale(1, 0))
	form.Name = "Form"
	form.AutomaticSize = Enum.AutomaticSize.Y
	form.LayoutOrder = 4
	form.BackgroundTransparency = 0.06
	form.Visible = false
	Kit.padding(form, 22, 24, 22, 24)
	Kit.list(form, 14)
	local nameHead = Kit.frame(form, UDim2.new(1, 0, 0, 26))
	nameHead.LayoutOrder = 1
	Kit.text(nameHead, "COMPANY NAME", 20, F.bold, C.muted)
	local counter = Kit.text(nameHead, "", 20, F.bold, C.dim)
	counter.AnchorPoint = Vector2.new(1, 0)
	counter.Position = UDim2.fromScale(1, 0)
	local nameRow = Kit.frame(form, UDim2.new(1, 0, 0, 84))
	nameRow.LayoutOrder = 2
	local nameBox = Kit.input(nameRow, "Your company name", UDim2.new(1, -96, 1, 0))
	nameBox.Name = "NameBox"
	nameBox.TextSize = 30
	local dice = Kit.button(nameRow, "", "secondary", UDim2.fromOffset(84, 84))
	dice.Name = "Dice"
	dice.AnchorPoint = Vector2.new(1, 0)
	dice.Position = UDim2.fromScale(1, 0)
	-- a die drawn from frames (no glyph that a font might lack): rounded square with five pips
	local die = Kit.frame(dice, UDim2.fromOffset(44, 44), UDim2.fromScale(0.5, 0.5))
	die.AnchorPoint = Vector2.new(0.5, 0.5)
	Kit.corner(die, 10)
	Kit.stroke(die, 0, C.text, 3)
	for _, at in { { 0.25, 0.25 }, { 0.75, 0.25 }, { 0.5, 0.5 }, { 0.25, 0.75 }, { 0.75, 0.75 } } do
		local pip = Kit.frame(die, UDim2.fromOffset(8, 8), UDim2.fromScale(at[1], at[2]))
		pip.AnchorPoint = Vector2.new(0.5, 0.5)
		pip.BackgroundTransparency = 0
		pip.BackgroundColor3 = C.text
		Kit.corner(pip, 4)
	end
	local startRow = Kit.frame(form, UDim2.new(1, 0, 0, 84))
	startRow.LayoutOrder = 3
	local start = Kit.button(startRow, "START", "primary", UDim2.fromOffset(320, 84))
	start.Name = "Start"
	start.TextSize = 30
	local customizeLink = Instance.new("TextButton")
	customizeLink.Name = "Customize"
	customizeLink.AutoButtonColor = false
	customizeLink.BackgroundTransparency = 1
	customizeLink.Text = "Customize (optional) ›"
	customizeLink.TextSize = 24
	customizeLink.Font = F.bold
	customizeLink.TextXAlignment = Enum.TextXAlignment.Right
	customizeLink.Size = UDim2.new(1, -340, 1, 0)
	customizeLink.AnchorPoint = Vector2.new(1, 0)
	customizeLink.Position = UDim2.fromScale(1, 0)
	customizeLink.Parent = startRow
	Theme.bindAccent(customizeLink, "TextColor3")
	local note = Kit.para(form, "Logo, colour and specialization are picked for you. Customize changes them now.", 20, C.dim, 4)
	note.Name = "Note"

	-- Customize: today's logo, colour and specialization controls
	local custom = Kit.frame(form, UDim2.fromScale(1, 0))
	custom.Name = "CustomizePanel"
	custom.AutomaticSize = Enum.AutomaticSize.Y
	custom.LayoutOrder = 5
	custom.Visible = false
	Kit.list(custom, 16)

	local selectedLogo = CompanyConfig.LOGOS[1]
	local selectedColor = CompanyConfig.COLORS[1].id
	local selectedSpec = CompanyConfig.SPECIALIZATIONS[1].id

	local logoCard = Kit.stack(custom, 10, 1)
	Kit.text(logoCard, "LOGO", 20, F.bold, C.muted).LayoutOrder = 1
	local logoRow = Kit.row(logoCard, 74, 10, 2)
	local logoButtons: { [string]: { button: TextButton, stroke: UIStroke } } = {}
	for index, glyph in CompanyConfig.LOGOS do
		local button = Instance.new("TextButton")
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.Text = glyph
		button.TextSize = 34
		button.Font = F.regular
		button.TextColor3 = C.text
		button.Size = UDim2.fromOffset(74, 74)
		button.LayoutOrder = index
		button.BackgroundColor3 = C.raised
		button.Parent = logoRow
		Kit.corner(button, 14)
		local stroke = Kit.stroke(button, 1, Theme.accent, 3)
		logoButtons[glyph] = { button = button, stroke = stroke }
	end

	local colorCard = Kit.stack(custom, 10, 2)
	Kit.text(colorCard, "COLOUR", 20, F.bold, C.muted).LayoutOrder = 1
	local colorRow = Kit.row(colorCard, 74, 12, 2)
	local colorStrokes: { [string]: UIStroke } = {}
	local colorClicks: { [string]: TextButton } = {}
	for index, def in CompanyConfig.COLORS do
		local button = Instance.new("TextButton")
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.Text = ""
		button.Size = UDim2.fromOffset(74, 74)
		button.LayoutOrder = index
		button.BackgroundColor3 = Theme.rgb(def.rgb)
		button.Parent = colorRow
		Kit.corner(button, 37)
		colorStrokes[def.id] = Kit.stroke(button, 1, C.white, 4)
		colorClicks[def.id] = button
	end

	local specCard = Kit.stack(custom, 10, 3)
	Kit.text(specCard, "SPECIALIZATION · a small bonus. Stays for the whole game.", 20, F.bold, C.muted).LayoutOrder = 1
	local specGrid = Kit.grid(specCard, 3, 112, 10, 2)
	local specButtons: { [string]: { button: TextButton, stroke: UIStroke } } = {}
	for index, spec in CompanyConfig.SPECIALIZATIONS do
		local button = Instance.new("TextButton")
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.Text = ""
		button.LayoutOrder = index
		button.BackgroundColor3 = C.bg
		button.BackgroundTransparency = 0.3
		button.Parent = specGrid
		Kit.corner(button, 12)
		local stroke = Kit.stroke(button, 0.88, C.line, 2)
		Kit.padding(button, 10, 12, 10, 12)
		Kit.list(button, 4)
		local name = Kit.text(button, spec.name, 22, F.bold, C.text)
		name.LayoutOrder = 1
		Kit.para(button, spec.desc, 20, C.muted, 2)
		specButtons[spec.id] = { button = button, stroke = stroke }
	end

	local function paint()
		local text = trim(nameBox.Text)
		local length = utf8.len(text) or 0
		counter.Text = `{length}/{GameConfig.COMPANY_NAME_MAX}`
		counter.TextColor3 = if length > GameConfig.COMPANY_NAME_MAX then C.bad else C.dim
		for glyph, refs in logoButtons do
			local on = glyph == selectedLogo
			refs.stroke.Transparency = if on then 0 else 1
			refs.stroke.Color = Theme.accent
			refs.button.BackgroundColor3 = if on then Theme.accent:Lerp(C.bg, 0.65) else C.raised
		end
		for id, stroke in colorStrokes do
			stroke.Transparency = if id == selectedColor then 0 else 1
		end
		for id, refs in specButtons do
			local on = id == selectedSpec
			refs.stroke.Color = if on then Theme.accent else C.line
			refs.stroke.Transparency = if on then 0 else 0.88
		end
		Kit.setDisabled(start, not validName(nameBox.Text))
	end

	for glyph, refs in logoButtons do
		refs.button.Activated:Connect(function()
			selectedLogo = glyph
			paint()
		end)
	end
	for id, button in colorClicks do
		button.Activated:Connect(function()
			selectedColor = id
			Theme.setAccent(colorOf(id)) -- Vorschau sofort in der Firmenfarbe
			paint()
		end)
	end
	for id, refs in specButtons do
		refs.button.Activated:Connect(function()
			selectedSpec = id
			paint()
		end)
	end
	nameBox:GetPropertyChangedSignal("Text"):Connect(paint)
	Theme.onAccent(function()
		paint()
	end)
	Kit.onClick(dice, function()
		nameBox.Text = Intro.nameIdea(trim(nameBox.Text))
	end)
	Kit.onClick(customizeLink, function()
		custom.Visible = not custom.Visible
		customizeLink.Text = if custom.Visible then "Hide options ‹" else "Customize (optional) ›"
		note.Visible = not custom.Visible
	end)
	nameBox.Text = Intro.nameIdea(nil)
	paint()

	-- "Welcome back" (a company exists)
	local continue = Kit.button(column, "CONTINUE", "primary", UDim2.fromOffset(320, 84))
	continue.Name = "Continue"
	continue.LayoutOrder = 5
	continue.TextSize = 30
	continue.Visible = false

	---------------------------------------------------------------- flow
	local stage = "loading" -- loading | welcome | new | done

	local function finish()
		if stage == "done" then
			return
		end
		stage = "done"
		Kit.tween(blocker, 0.6, { Position = UDim2.fromScale(0, -1) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.delay(0.6, function()
			if stage == "done" then
				blocker.Visible = false
			end
		end)
		callbacks.onFinish()
	end

	local function showNew()
		stage = "new"
		blocker.Position = UDim2.new()
		blocker.Visible = true
		status.Visible = false
		form.Visible = true
		continue.Visible = false
		line.Text = Intro.LINE
		paint()
	end

	Kit.onClick(continue, function()
		if stage == "welcome" then
			finish()
		end
	end)

	Kit.onClick(start, function()
		if stage ~= "new" then
			return
		end
		local name = trim(nameBox.Text)
		local ok = ActionController.call("CreateCompany", {
			name = name,
			logo = selectedLogo,
			color = selectedColor,
			spec = selectedSpec,
		})
		if ok then
			Toast.show("success", `Welcome to {name}! Your garage office is ready.`, 5)
			finish()
		end
	end)

	StateController.onChange(function(snapshot: Types.Snapshot)
		local company = snapshot.data.company
		if stage == "done" then
			if not company then
				-- Firma wurde zurückgesetzt (Debug): Intro wieder zeigen
				callbacks.onReopen()
				showNew()
			end
			return
		end
		if company then
			if stage == "new" then
				finish()
			elseif stage ~= "welcome" then
				stage = "welcome"
				form.Visible = false
				status.Visible = true
				status.Text = `Welcome back, {company.logo} {company.name}`
				continue.Visible = true
			end
		elseif stage == "loading" or stage == "welcome" then
			-- no company (yet, or again after a debug reset before CONTINUE): the founding form
			showNew()
		end
	end)
end

return Intro
