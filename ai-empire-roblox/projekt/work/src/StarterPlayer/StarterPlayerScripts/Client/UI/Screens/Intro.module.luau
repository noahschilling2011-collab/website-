--!strict
-- Intro: Titelbildschirm und Firmengründung. Eigene randlose Ebene über allem, bis eine Firma existiert.
-- Bei bestehender Firma: "Welcome back" + CONTINUE. Nach Debug-Reset erscheint es wieder.

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

function Intro.mount(parent: Frame, callbacks: Callbacks)
	local blocker = Kit.blocker(parent, C.white, 0)
	blocker.Name = "Intro"
	blocker.ZIndex = 30
	

	-- Quiet architectural backdrop: one border, a small wordmark and generous space.
	blocker.BackgroundColor3 = C.bg
	local edge = Kit.frame(blocker, UDim2.new(0, 1, 1, -96), UDim2.new(0, 48, 0, 48))
	edge.BackgroundColor3 = C.line
	edge.BackgroundTransparency = 0.92
	local edition = Kit.text(blocker, "FOUNDER DISTRICT   /   01", 12, F.bold, C.muted)
	edition.Position = UDim2.fromOffset(72, 52)
	local footerNote = Kit.text(blocker, "A garage today. Your company tomorrow.", 14, F.regular, C.dim)
	footerNote.Position = UDim2.new(0, 72, 1, -48)
	local mark = Kit.frame(blocker, UDim2.fromOffset(28, 28), UDim2.new(1,-72,0,52))
	mark.BackgroundColor3 = Theme.accent
	mark.BackgroundTransparency = 0.1
	Kit.corner(mark, 5)
	local cut = Kit.frame(mark,UDim2.fromOffset(8,20),UDim2.fromOffset(10,4))
	cut.BackgroundColor3 = C.bg
	cut.BackgroundTransparency = 0

	---------------------------------------------------------------- Titel
	local splash = Kit.frame(blocker, UDim2.fromOffset(860, 0), UDim2.fromScale(0.5, 0.46))
	splash.AnchorPoint = Vector2.new(0.5, 0.5)
	splash.AutomaticSize = Enum.AutomaticSize.Y
	local splashLayout = Kit.list(splash, 12)
	splashLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local title = Kit.text(splash, "AI Empire", 64, F.display, C.white)
	title.LayoutOrder = 1
	title.TextXAlignment = Enum.TextXAlignment.Center
	local horizon = Kit.frame(splash, UDim2.fromOffset(52, 3))
	horizon.LayoutOrder = 2
	horizon.BackgroundTransparency = 0
	Theme.bindAccent(horizon, "BackgroundColor3")
	local horizonFade = Instance.new("UIGradient")
	horizonFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	horizonFade.Parent = horizon
	local tagline = Kit.text(splash, "Train the model. Build the business.", 21, F.medium, C.muted)
	tagline.LayoutOrder = 3
	local spacer = Kit.frame(splash, UDim2.fromOffset(1, 10))
	spacer.LayoutOrder = 4
	local status = Kit.text(splash, "Connecting...", 16, F.medium, C.dim)
	status.LayoutOrder = 5
	local start = Kit.button(splash, "Build your company", "primary", UDim2.fromOffset(260, 56))
	start.LayoutOrder = 6
	start.TextSize = 19
	start.Visible = false

	---------------------------------------------------------------- Formular
	local form = Kit.scroll(blocker)
	form.Visible = false
	Kit.padding(form, 72, 24, 28, 24) -- oben Platz für die Roblox-Topbar (Ebene ist randlos)
	local formLayout = Kit.list(form, 14)
	formLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local column = Kit.frame(form, UDim2.fromScale(1, 0))
	column.AutomaticSize = Enum.AutomaticSize.Y
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(800, math.huge)
	limit.Parent = column
	Kit.list(column, 14)

	local head = Kit.stack(column, 8, 1)
	local formTitle = Kit.text(head, "Make it your company", 26, F.display, C.text)
	formTitle.LayoutOrder = 1
	Kit.para(
		head,
		`You start in a garage with {Format.money(GameConfig.START_MONEY)} and an old laptop. Everything else you build yourself.`,
		16,
		C.muted,
		2
	)

	local selectedLogo = CompanyConfig.LOGOS[1]
	local selectedColor = CompanyConfig.COLORS[1].id
	local selectedSpec = CompanyConfig.SPECIALIZATIONS[1].id

	local formPanel = Kit.panel(column, UDim2.fromScale(1, 0))
	formPanel.AutomaticSize = Enum.AutomaticSize.Y
	formPanel.LayoutOrder = 2
	formPanel.BackgroundTransparency = 0.06
	Kit.padding(formPanel, 22, 24, 22, 24)
	Kit.list(formPanel, 20)

	-- Name
	local nameCard = Kit.stack(formPanel, 8, 1)
	local nameHead = Kit.frame(nameCard, UDim2.new(1, 0, 0, 18))
	nameHead.LayoutOrder = 1
	Kit.caption(nameHead, "Company name")
	local counter = Kit.text(nameHead, "", 13, F.bold, C.dim)
	counter.AnchorPoint = Vector2.new(1, 0)
	counter.Position = UDim2.fromScale(1, 0)
	local nameBox = Kit.input(nameCard, "e.g. Nimbus Labs")
	nameBox.LayoutOrder = 2

	-- Logo
	local logoCard = Kit.stack(formPanel, 10, 2)
	Kit.caption(logoCard, "Logo", 1)
	local logoRow = Kit.row(logoCard, 54, 8, 2)
	local logoButtons: { [string]: { button: TextButton, stroke: UIStroke } } = {}
	for index, glyph in CompanyConfig.LOGOS do
		local button = Instance.new("TextButton")
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.Text = glyph
		button.TextSize = 26
		button.Font = F.regular
		button.Size = UDim2.fromOffset(54, 54)
		button.LayoutOrder = index
		button.BackgroundColor3 = C.raised
		button.Parent = logoRow
		Kit.corner(button, 12)
		local stroke = Kit.stroke(button, 1, Theme.accent, 2)
		logoButtons[glyph] = { button = button, stroke = stroke }
	end

	-- Farbe
	local colorCard = Kit.stack(formPanel, 10, 3)
	Kit.caption(colorCard, "Brand color", 1)
	local colorRow = Kit.row(colorCard, 44, 10, 2)
	local colorButtons: { [string]: UIStroke } = {}
	local colorClicks: { [string]: TextButton } = {}
	for index, def in CompanyConfig.COLORS do
		local button = Instance.new("TextButton")
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.Text = ""
		button.Size = UDim2.fromOffset(40, 40)
		button.LayoutOrder = index
		button.BackgroundColor3 = Theme.rgb(def.rgb)
		button.Parent = colorRow
		Kit.corner(button, 20)
		colorButtons[def.id] = Kit.stroke(button, 1, C.white, 3)
		colorClicks[def.id] = button
	end

	-- Spezialisierung
	local specCard = Kit.stack(formPanel, 10, 4)
	Kit.caption(specCard, "Specialization: a small bonus that lasts forever", 1)
	local specGrid = Kit.grid(specCard, 3, 80, 10, 2)
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
		local name = Kit.text(button, spec.name, 16, F.bold, C.text)
		name.LayoutOrder = 1
		Kit.para(button, spec.desc, 13, C.muted, 2)
		specButtons[spec.id] = { button = button, stroke = stroke }
	end

	-- Vorschau + Gründen
	Kit.divider(formPanel, 5)
	local footer = Kit.frame(formPanel, UDim2.new(1, 0, 0, 60))
	footer.LayoutOrder = 6
	local previewLogo = Kit.frame(footer, UDim2.fromOffset(52, 52), UDim2.new(0, 0, 0.5, -26))
	previewLogo.BackgroundTransparency = 0.7
	Theme.bindAccent(previewLogo, "BackgroundColor3")
	Kit.corner(previewLogo, 14)
	local previewGlyph = Kit.text(previewLogo, selectedLogo, 28, F.regular)
	previewGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
	previewGlyph.Position = UDim2.fromScale(0.5, 0.5)
	local previewName = Kit.text(footer, "", 22, F.black, C.text)
	previewName.AutomaticSize = Enum.AutomaticSize.None
	previewName.Size = UDim2.new(1, -340, 0, 26)
	previewName.Position = UDim2.fromOffset(66, 8)
	previewName.TextTruncate = Enum.TextTruncate.AtEnd
	local previewSpec = Kit.text(footer, "", 14, F.bold, C.muted)
	previewSpec.Position = UDim2.fromOffset(66, 36)
	Theme.bindAccent(previewSpec, "TextColor3")
	local found = Kit.button(footer, "Create company", "primary", UDim2.fromOffset(250, 54))
	found.AnchorPoint = Vector2.new(1, 0.5)
	found.Position = UDim2.fromScale(1, 0.5)
	found.TextSize = 18

	local function paint()
		local text = trim(nameBox.Text)
		local length = utf8.len(text) or 0
		counter.Text = `{length}/{GameConfig.COMPANY_NAME_MAX}`
		counter.TextColor3 = if length > GameConfig.COMPANY_NAME_MAX then C.bad else C.dim
		previewName.Text = if text ~= "" then text else "Your company"
		previewGlyph.Text = selectedLogo
		local spec = CompanyConfig.getSpec(selectedSpec)
		previewSpec.Text = if spec then spec.name else ""
		for glyph, refs in logoButtons do
			local on = glyph == selectedLogo
			refs.stroke.Transparency = if on then 0 else 1
			refs.stroke.Color = Theme.accent
			refs.button.BackgroundColor3 = if on then Theme.accent:Lerp(C.bg, 0.65) else C.raised
		end
		for id, stroke in colorButtons do
			stroke.Transparency = if id == selectedColor then 0 else 1
		end
		for id, refs in specButtons do
			local on = id == selectedSpec
			refs.stroke.Color = if on then Theme.accent else C.line
			refs.stroke.Transparency = if on then 0 else 0.88
		end
		Kit.setDisabled(found, not validName(nameBox.Text))
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
	paint()

	---------------------------------------------------------------- Ablauf
	local stage = "loading" -- loading | welcome | new | form | done

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
		form.Visible = false
		splash.Visible = true
		status.Text = `You have {Format.money(GameConfig.START_MONEY)}, an old laptop and a big idea.`
		start.Text = "Build your company"
		start.Visible = true
	end

	Kit.onClick(start, function()
		if stage == "welcome" then
			finish()
		elseif stage == "new" then
			stage = "form"
			splash.Visible = false
			form.Visible = true
		end
	end)

	Kit.onClick(found, function()
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
			if stage == "form" then
				finish()
			elseif stage ~= "welcome" then
				stage = "welcome"
				status.Text = `Welcome back, {company.logo} {company.name}`
				start.Text = "Back to work"
				start.Visible = true
			end
		elseif stage == "loading" then
			showNew()
		end
	end)
end

return Intro
