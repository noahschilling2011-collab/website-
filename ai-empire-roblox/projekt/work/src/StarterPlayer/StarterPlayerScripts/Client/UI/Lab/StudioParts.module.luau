--!strict
-- Building blocks of the Model Studio (LAB_SPEC 5.3): the live Model Card, option tiles, step chips, the cost
-- badge, stat bars and the ceremony stage (podium, light beams, confetti). Built from plain Frames, labels,
-- UICorner/UIStroke/UIGradient only (no images, no asset ids). Every part is built once; refreshes only change
-- texts, colours and sizes. Sizes are Studio design px (the Studio's own UIScale maps them to the screen).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ModelConfig = require(Shared.Config.ModelConfig)
local CompanyConfig = require(Shared.Config.CompanyConfig)
local ModelMath = require(Shared.ModelMath)
local Format = require(Shared.Format)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local C = Theme.colors
local F = Theme.font

local Parts = {}

Parts.MIN_TEXT = 20 -- LAB_SPEC 3.4: 20 design px = 11.96 pt on an iPhone in landscape, no exceptions
Parts.TAP = 74 -- every tappable thing is at least 74 x 74 design px (44.3 pt)

---------------------------------------------------------------------------- formatting and colours

-- "$7,040" below $100,000, "$186.4K" from there (LAB_SPEC 3.4)
function Parts.money(n: number): string
	if math.abs(n) < 100000 then
		return (if n < 0 then "-$" else "$") .. Format.int(math.abs(n))
	end
	return Format.money(n)
end

function Parts.signedMoney(n: number): string
	return (if n >= 0 then "+" else "−") .. Parts.money(math.abs(n))
end

-- "+1.9" / "−4.6" (a real minus sign reads better at 20 px)
function Parts.signed(n: number): string
	local text = Format.signed(n)
	return if string.sub(text, 1, 1) == "-" then "−" .. string.sub(text, 2) else text
end

local function companyColor(id: string): Color3
	local def = CompanyConfig.getColor(id)
	return if def then Theme.rgb(def.rgb) else Theme.accent
end

-- Card colour per skill focus (LAB_SPEC 3.4): Balanced = company accent, Coding blue, Reasoning violet,
-- Creative amber.
function Parts.focusColor(focusId: string): Color3
	if focusId == "coding" then
		return companyColor("blue")
	elseif focusId == "reasoning" then
		return companyColor("violet")
	elseif focusId == "creative" then
		return companyColor("amber")
	end
	return Theme.accent
end

-- Colour of a model card: the chosen look (ModelMath.parseLook), else the focus colour.
function Parts.cardColor(focusId: string, look: any): Color3
	local colorId = ModelMath.parseLook(look)
	if colorId then
		return companyColor(colorId)
	end
	return Parts.focusColor(focusId)
end

-- Display form of a company logo glyph: "⦿" (U+29BF) is missing from common fallback fonts (it renders as a box
-- in the previews), so the Studio draws "◉" (U+25C9) for it. Display only: the saved look keeps the index.
local GLYPH_SHOWN: { [string]: string } = { ["⦿"] = "◉" }
function Parts.glyph(glyph: string): string
	return GLYPH_SHOWN[glyph] or glyph
end

function Parts.emblem(look: any, logo: string?): string
	local _, index = ModelMath.parseLook(look)
	if index then
		return Parts.glyph(CompanyConfig.allLogos()[index] or "N") -- shop package: Kit emblems follow LOGOS (SHOP_SPEC 3.5)
	end
	return Parts.glyph(logo or "N")
end

function Parts.sizeLabel(id: string): string
	local size = ModelConfig.getSize(id)
	return if size then size.label else id
end

function Parts.focusLabel(id: string): string
	local focus = ModelConfig.getFocus(id)
	return if focus then focus.label else id
end

-- UI labels of the training plans (ModelConfig.RECIPES stays unchanged)
Parts.RECIPE_LABEL = { rapid = "Quick pass", steady = "Standard", deep = "Deep" } :: { [string]: string }

function Parts.lineShort(target: string?): string
	local line = ModelConfig.getLine(target)
	return if line then line.short else "Model"
end

---------------------------------------------------------------------------- primitives

function Parts.label(parent: Instance, text: string, size: number, font: Enum.Font?, color: Color3?, position: UDim2?, box: UDim2?, align: Enum.TextXAlignment?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Text = text
	label.TextSize = math.max(Parts.MIN_TEXT, size)
	label.Font = font or F.medium
	label.TextColor3 = color or C.text
	label.TextXAlignment = align or Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Position = position or UDim2.new()
	label.Size = box or UDim2.new(1, 0, 0, math.ceil(math.max(Parts.MIN_TEXT, size) * 1.25))
	label.Parent = parent
	return label
end

function Parts.box(parent: Instance, position: UDim2, size: UDim2, color: Color3?, transparency: number?, radius: number?): Frame
	local frame = Kit.frame(parent, size, position)
	frame.BackgroundColor3 = color or C.panel
	frame.BackgroundTransparency = transparency or 0
	if radius ~= 0 then
		Kit.corner(frame, radius or 14)
	end
	return frame
end

-- Glass panel of the Studio: panel colour, rounded, faint hairline
function Parts.panel(parent: Instance, position: UDim2, size: UDim2): Frame
	local frame = Parts.box(parent, position, size, C.panel, 0.02, 16)
	Kit.stroke(frame, 0.9)
	return frame
end

-- Bar buttons (Kit.button styles) at Studio sizes, selectable for gamepads.
function Parts.button(parent: Instance, text: string, style: Kit.ButtonStyle, position: UDim2, size: UDim2, textSize: number?): TextButton
	local button = Kit.button(parent, text, style, size)
	button.Position = position
	button.TextSize = math.max(Parts.MIN_TEXT, textSize or 26)
	button.TextWrapped = true
	button.Selectable = true
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, 14)
	end
	return button
end

-- A tappable tile: a TextButton with child labels and a stroke that marks the selection.
export type TileButton = { button: TextButton, stroke: UIStroke }
function Parts.tileButton(parent: Instance, name: string, position: UDim2, size: UDim2, text: string?): TileButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Text = text or ""
	button.TextTransparency = 1 -- the Text carries the short name for tests and screen readers; labels draw it
	button:SetAttribute("HiddenText", true)
	button.TextSize = Parts.MIN_TEXT
	button.Font = F.bold
	button.TextColor3 = C.text
	button.BackgroundColor3 = C.panel2
	button.BackgroundTransparency = 0
	button.Position = position
	button.Size = size
	button.Selectable = true
	button.ClipsDescendants = true
	button.Parent = parent
	button:SetAttribute("BaseBg", 0)
	Kit.corner(button, 14)
	local stroke = Kit.stroke(button, 0.86, C.line, 1)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseButton1Down:Connect(function()
		if button:GetAttribute("Disabled") ~= true then
			Kit.tween(scale, 0.08, { Scale = 0.98 })
		end
	end)
	button.MouseButton1Up:Connect(function()
		Kit.tween(scale, 0.12, { Scale = 1 })
	end)
	button.MouseLeave:Connect(function()
		Kit.tween(scale, 0.12, { Scale = 1 })
	end)
	return { button = button, stroke = stroke }
end

-- Kit.setDisabled for tiles: Kit dims the button's own Text (0.45), which would reveal a tile's hidden Text under
-- its labels, so a tile keeps TextTransparency 1.
function Parts.setDisabled(button: TextButton, disabled: boolean)
	Kit.setDisabled(button, disabled)
	if button:GetAttribute("HiddenText") == true then
		button.TextTransparency = 1
	end
end

-- Selected: accent stroke + faint accent fill; locked: dimmed; otherwise the plain panel.
function Parts.paintTile(tile: TileButton, selected: boolean, locked: boolean?, color: Color3?)
	local accent = color or Theme.accent
	tile.button.BackgroundColor3 = if selected then accent:Lerp(C.panel2, 0.8) else C.panel2
	tile.stroke.Color = if selected then accent else C.line
	tile.stroke.Transparency = if selected then 0 else (if locked then 0.93 else 0.86)
	tile.stroke.Thickness = if selected then 3 else 1
end

-- Round check badge (32 px circle, 20 px glyph)
function Parts.check(parent: Instance, position: UDim2): Frame
	local badge = Parts.box(parent, position, UDim2.fromOffset(34, 34), Theme.accent, 0, 17)
	badge.Name = "Check"
	local glyph = Parts.label(badge, "✓", 22, F.black, C.bg, UDim2.new(), UDim2.fromScale(1, 1), Enum.TextXAlignment.Center)
	glyph.TextTruncate = Enum.TextTruncate.None
	return badge
end

-- Small tag chip ("LIVE v2", "BEST FIT", "FREE"): 20 px bold, outlined
function Parts.tag(parent: Instance, text: string, color: Color3, position: UDim2?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundColor3 = C.bg
	label.BackgroundTransparency = 0.2
	label.BorderSizePixel = 0
	label.Text = text
	label.TextSize = Parts.MIN_TEXT
	label.Font = F.bold
	label.TextColor3 = color
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, 28)
	label.Position = position or UDim2.new()
	label.Parent = parent
	Kit.corner(label, 7)
	Kit.stroke(label, 0.4, color)
	Kit.padding(label, 0, 8, 0, 8)
	return label
end

-- 5-segment tier bar (tiers 1..5)
export type TierBar = { frame: Frame, set: (tier: number, color: Color3?) -> () }
function Parts.tierBar(parent: Instance, position: UDim2, width: number, segments: number?): TierBar
	local n = segments or 5
	local frame = Kit.frame(parent, UDim2.fromOffset(width, 8), position)
	local cells: { Frame } = {}
	local gap = 4
	local w = (width - gap * (n - 1)) / n
	for i = 1, n do
		local cell = Parts.box(frame, UDim2.fromOffset((i - 1) * (w + gap), 0), UDim2.fromOffset(w, 8), C.raised, 0, 4)
		cells[i] = cell
	end
	return {
		frame = frame,
		set = function(tier: number, color: Color3?)
			for i, cell in cells do
				cell.BackgroundColor3 = if i <= tier then (color or Theme.accent) else C.raised
			end
		end,
	}
end

---------------------------------------------------------------------------- Model Card

export type CardState = {
	sizeId: string,
	focusId: string,
	name: string,
	version: number?,
	lineShort: string,
	logo: string?,
	look: any,
	lit: number?, -- lit cores (nil = all)
	progress: number?, -- training: cores light up in reading order, the last two white
	overall: number?, -- footer: score + star pips
	stars: number?,
	recipeId: string?, -- plan meter 1/2/3
	overfit: boolean?,
	beatsBest: boolean?,
}

export type ModelCard = {
	frame: Frame,
	color: Color3,
	set: (state: CardState) -> (),
	resize: (size: Vector2) -> (),
	setProgress: (progress: number) -> (),
	setPulse: (on: boolean) -> (),
}

local MAX_CORES = 7

function Parts.modelCard(parent: Instance, size: Vector2): ModelCard
	local frame = Kit.frame(parent, UDim2.fromOffset(size.X, size.Y))
	frame.Name = "ModelCard"
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3 = C.panel2
	Kit.corner(frame, 18)
	local stroke = Kit.stroke(frame, 0, C.white, 2)
	local fill = Instance.new("UIGradient")
	fill.Rotation = 90
	fill.Parent = frame
	-- glow behind the card (a soft halo; guiprev draws it as a flat panel)
	local chip = Parts.tag(frame, "CHAT", C.text, UDim2.fromOffset(12, 12))
	chip.Name = "LineChip"
	local emblemBox = Parts.box(frame, UDim2.new(1, -44, 0, 12), UDim2.fromOffset(32, 32), C.bg, 0.3, 8)
	local emblem = Parts.label(emblemBox, "N", 20, F.bold, C.text, UDim2.new(), UDim2.fromScale(1, 1), Enum.TextXAlignment.Center)
	emblem.TextTruncate = Enum.TextTruncate.None
	local grid = Kit.frame(frame, UDim2.fromOffset(120, 120))
	grid.Name = "Cores"
	local cells: { Frame } = {}
	for i = 1, MAX_CORES * MAX_CORES do
		local cell = Kit.frame(grid, UDim2.fromOffset(10, 10))
		cell.BackgroundTransparency = 0
		cell.BackgroundColor3 = C.raised
		cell.Visible = false
		Kit.corner(cell, 4)
		cells[i] = cell
	end
	-- training plan meter (step 4): three signal bars, 16 px wide and 24 / 36 / 48 px tall, with the plan's name above
	-- (QUICK / STD / DEEP, 20 px), right of the core grid
	local METER_W, METER_H = 64, 78
	local meter = Kit.frame(frame, UDim2.fromOffset(METER_W, METER_H))
	meter.Name = "PlanMeter"
	local meterLabel = Parts.label(meter, "STD", 20, F.bold, C.muted, UDim2.new(), UDim2.fromOffset(METER_W, 24), Enum.TextXAlignment.Center)
	meterLabel.Name = "PlanName"
	meterLabel.TextTruncate = Enum.TextTruncate.None
	local meterBars: { Frame } = {}
	for i = 1, 3 do
		local barH = 12 + 12 * i
		local bar = Parts.box(meter, UDim2.fromOffset((i - 1) * 24, METER_H - barH), UDim2.fromOffset(16, barH), C.raised, 0, 4)
		meterBars[i] = bar
	end
	-- a custom colour keeps a thin edge in the skill-focus colour, so the focus still shows on the card
	local focusEdge = Parts.box(frame, UDim2.fromOffset(6, 22), UDim2.new(0, 5, 1, -44), C.raised, 0, 3)
	focusEdge.Name = "FocusEdge"
	focusEdge.Visible = false
	local nameLabel = Parts.label(frame, "", 26, F.display, C.text, UDim2.new(), UDim2.new(1, -16, 0, 32), Enum.TextXAlignment.Center)
	nameLabel.Name = "CardName"
	local sub = Parts.label(frame, "", 20, F.medium, C.muted, UDim2.new(), UDim2.new(1, -16, 0, 24), Enum.TextXAlignment.Center)
	sub.Name = "CardSub"
	local footer = Kit.frame(frame, UDim2.new(1, -24, 0, 26))
	footer.Visible = false
	local score = Parts.label(footer, "", 24, F.display, C.text, UDim2.new(), UDim2.new(0, 70, 1, 0))
	local pips: { Frame } = {}
	for i = 1, 5 do
		local pip = Parts.box(footer, UDim2.new(1, -(6 - i) * 21, 0.5, -8), UDim2.fromOffset(16, 16), C.raised, 0, 8)
		pips[i] = pip
	end
	local function layoutPips()
		local d = math.clamp(math.floor((frame.Size.X.Offset - 24 - 74) / 5) - 4, 10, 16)
		for i, pip in pips do
			pip.Size = UDim2.fromOffset(d, d)
			pip.Position = UDim2.new(1, -(6 - i) * (d + 4) + 4, 0.5, -d / 2)
		end
	end
	local beats = Parts.tag(frame, "BEATS YOUR BEST", C.good, UDim2.new())
	beats.Name = "BeatsBest"
	beats.Visible = false
	beats.AutomaticSize = Enum.AutomaticSize.None
	beats.TextXAlignment = Enum.TextXAlignment.Center
	local scale = Instance.new("UIScale")
	scale.Parent = frame

	local card: ModelCard
	local current: CardState? = nil
	local w, h = size.X, size.Y
	local cores = 3
	local litCount = 9
	local gridSide = 120
	local pulse: Tween? = nil

	local function layoutCells()
		local gap = math.max(3, math.floor(gridSide / cores * 0.14))
		local cellSize = (gridSide - gap * (cores - 1)) / cores
		for i, cell in cells do
			local index = i - 1
			local row, col = index // cores, index % cores
			local show = i <= cores * cores
			cell.Visible = show
			if show then
				cell.Position = UDim2.fromOffset(col * (cellSize + gap), row * (cellSize + gap))
				cell.Size = UDim2.fromOffset(cellSize, cellSize)
			end
		end
	end

	local function layout()
		frame.Size = UDim2.fromOffset(w, h)
		local footerOn = footer.Visible
		local bottom = if footerOn then 36 else 0
		-- the grid and the plan meter column are centred together (gap 12)
		gridSide = math.floor(math.min(w - 100, h - 140 - bottom))
		local groupX = math.floor((w - (gridSide + 12 + METER_W)) / 2)
		grid.Size = UDim2.fromOffset(gridSide, gridSide)
		grid.Position = UDim2.fromOffset(groupX, 52)
		meter.Position = UDim2.fromOffset(groupX + gridSide + 12, 52 + gridSide - METER_H)
		nameLabel.Position = UDim2.fromOffset(8, 52 + gridSide + 8)
		sub.Position = UDim2.fromOffset(8, 52 + gridSide + 40)
		footer.Position = UDim2.new(0, 12, 1, -34)
		layoutPips()
		beats.Position = UDim2.new(0, 8, 1, -36)
		beats.Size = UDim2.new(1, -16, 0, 28)
		beats.Text = if w >= 210 then "BEATS YOUR BEST" else "BEATS BEST"
		layoutCells()
	end

	local function paintCells(progress: number?)
		local color = card.color
		local total = cores * cores
		if progress then
			local done = math.floor(total * math.clamp(progress, 0, 1) + 0.5)
			for i = 1, total do
				local cell = cells[i]
				if i <= done - 2 then
					cell.BackgroundColor3 = color
					cell.BackgroundTransparency = 0
				elseif i <= done then
					cell.BackgroundColor3 = C.white
					cell.BackgroundTransparency = 0
				else
					cell.BackgroundColor3 = C.raised
					cell.BackgroundTransparency = 0.35
				end
			end
		else
			for i = 1, total do
				local cell = cells[i]
				local on = i <= litCount
				cell.BackgroundColor3 = if on then color else C.raised
				cell.BackgroundTransparency = if on then 0 else 0.35
			end
		end
	end

	card = {
		frame = frame,
		color = Theme.accent,
		set = function(state: CardState)
			current = state
			local color = Parts.cardColor(state.focusId, state.look)
			card.color = color
			stroke.Color = color
			fill.Color = ColorSequence.new(color:Lerp(C.panel2, 0.62), C.panel2)
			chip.Text = string.upper(state.lineShort)
			chip.TextColor3 = color:Lerp(C.white, 0.35)
			emblem.Text = Parts.emblem(state.look, state.logo)
			local n = math.clamp(2 + (function(): number
				for i, s in ModelConfig.SIZES do
					if s.id == state.sizeId then
						return i
					end
				end
				return 1
			end)(), 3, MAX_CORES)
			local newCores = n ~= cores
			cores = n
			litCount = if state.lit then math.clamp(state.lit, 0, n * n) else n * n
			nameLabel.Text = if state.version then `{state.name} v{state.version}` else state.name
			sub.Text = `{Parts.sizeLabel(state.sizeId)} · {Parts.focusLabel(state.focusId)}`
			local footerOn = state.overall ~= nil
			local footerChanged = footer.Visible ~= footerOn
			footer.Visible = footerOn
			sub.Visible = not footerOn or h >= 280
			if state.overall then
				score.Text = string.format("%.1f", state.overall)
				local stars = state.stars or 0
				for i, pip in pips do
					pip.BackgroundColor3 = if i <= stars then C.warn else C.raised
				end
			end
			local plan = if state.recipeId == "rapid" then 1 elseif state.recipeId == "deep" then 3 elseif state.recipeId then 2 else 0
			meter.Visible = plan > 0
			for i, bar in meterBars do
				bar.BackgroundColor3 = if i <= plan then (if state.overfit then C.warn else color) else C.raised
			end
			meterLabel.Text = if plan == 1 then "QUICK" elseif plan == 3 then "DEEP" else "STD"
			meterLabel.TextColor3 = if state.overfit then C.warn else color:Lerp(C.white, 0.35)
			local focusColor = Parts.focusColor(state.focusId)
			focusEdge.Visible = ModelMath.parseLook(state.look) ~= nil and focusColor ~= color
			focusEdge.BackgroundColor3 = focusColor
			beats.Visible = state.beatsBest == true and not footerOn
			if beats.Visible then
				sub.Visible = false
			end
			if newCores or footerChanged then
				layout()
			end
			paintCells(state.progress)
		end,
		resize = function(newSize: Vector2)
			w, h = newSize.X, newSize.Y
			layout()
			if current then
				card.set(current)
			end
		end,
		setProgress = function(progress: number)
			paintCells(progress)
		end,
		setPulse = function(on: boolean)
			if pulse then
				pulse:Cancel()
				pulse = nil
			end
			stroke.Thickness = 2
			if on then
				local info = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
				local tween = game:GetService("TweenService"):Create(stroke, info, { Thickness = 6 })
				tween:Play()
				pulse = tween
			end
		end,
	}
	layout()
	return card
end

---------------------------------------------------------------------------- option tiles

export type OptionTile = {
	tile: TileButton,
	title: TextLabel,
	right: TextLabel,
	lines: { TextLabel },
	check: Frame,
	set: (opts: { title: string?, right: string?, rightColor: Color3?, lines: { string }?, colors: { Color3 }?, selected: boolean, locked: boolean?, color: Color3? }) -> (),
}

-- A tile with a title row (title left, a value right) and up to `lineCount` lines below.
function Parts.optionTile(parent: Instance, name: string, position: UDim2, size: Vector2, lineCount: number, lineHeight: number?, titleSize: number?, text: string?): OptionTile
	local tile = Parts.tileButton(parent, name, position, UDim2.fromOffset(size.X, size.Y), text)
	local button = tile.button
	local lh = lineHeight or 24
	local ts = titleSize or 24
	local title = Parts.label(button, "", ts, F.bold, C.text, UDim2.fromOffset(16, 10), UDim2.new(1, -32, 0, ts + 6))
	local right = Parts.label(button, "", 22, F.bold, Theme.accent, UDim2.new(0, 16, 0, 10), UDim2.new(1, -32, 0, ts + 6), Enum.TextXAlignment.Right)
	local lines: { TextLabel } = {}
	for i = 1, lineCount do
		local line = Parts.label(button, "", 20, F.medium, C.muted, UDim2.fromOffset(16, 10 + ts + 8 + (i - 1) * lh), UDim2.new(1, -32, 0, lh))
		lines[i] = line
	end
	local check = Parts.check(button, UDim2.new(1, -44, 1, -44))
	check.Visible = false
	local option: OptionTile = {
		tile = tile,
		title = title,
		right = right,
		lines = lines,
		check = check,
		set = function(opts)
			if opts.title then
				title.Text = opts.title
			end
			right.Text = opts.right or ""
			right.TextColor3 = opts.rightColor or Theme.accent
			local list = opts.lines or {}
			for i, line in lines do
				line.Text = list[i] or ""
				line.TextColor3 = if opts.colors and opts.colors[i] then opts.colors[i] else C.muted
			end
			title.TextColor3 = if opts.locked then C.muted else C.text
			Parts.paintTile(tile, opts.selected, opts.locked, opts.color)
			check.BackgroundColor3 = opts.color or Theme.accent
		end,
	}
	return option
end

---------------------------------------------------------------------------- step chips

export type StepChips = { frame: Frame, buttons: { TextButton }, set: (current: number, done: { boolean }, labels: { string }?) -> () }

-- Numbered step pills. `widths` per chip (the current one may be wider), gap 8.
function Parts.stepChips(parent: Instance, count: number, onPick: (index: number) -> ()): StepChips
	local frame = Kit.frame(parent, UDim2.new(1, 0, 1, 0))
	frame.Name = "StepChips"
	local buttons: { TextButton } = {}
	local strokes: { UIStroke } = {}
	for i = 1, count do
		local tile = Parts.tileButton(frame, "Chip_" .. i, UDim2.new(), UDim2.fromOffset(Parts.TAP, Parts.TAP), "")
		local button = tile.button
		button.TextTransparency = 0
		button:SetAttribute("HiddenText", nil)
		button.TextSize = 26
		button.TextColor3 = C.muted
		button.ClipsDescendants = false
		buttons[i] = button
		strokes[i] = tile.stroke
		Kit.onClick(button, function()
			onPick(i)
		end)
	end
	return {
		frame = frame,
		buttons = buttons,
		set = function(current: number, done: { boolean }, labels: { string }?)
			local x = 0
			for i, button in buttons do
				local label = if labels then labels[i] else tostring(i)
				local isCurrent = i == current
				local text: string
				if labels then
					text = if isCurrent then label elseif done[i] then "✓ " .. string.gsub(label, "^%d+ ", "") else label
				else
					text = if done[i] and not isCurrent then "✓" else label
				end
				button.Text = text
				local width = tonumber(button:GetAttribute("Width")) or Parts.TAP
				button.Size = UDim2.fromOffset(width, Parts.TAP)
				button.Position = UDim2.fromOffset(x, 0)
				x += width + 8
				button.BackgroundColor3 = if isCurrent then Theme.accent:Lerp(C.panel2, 0.72) else C.panel2
				button.TextColor3 = if isCurrent then Theme.accent:Lerp(C.white, 0.2) elseif done[i] then C.good else C.muted
				strokes[i].Color = if isCurrent then Theme.accent else C.line
				strokes[i].Transparency = if isCurrent then 0.1 else 0.86
				strokes[i].Thickness = if isCurrent then 2 else 1
			end
		end,
	}
end

---------------------------------------------------------------------------- cost badge

export type CostBadge = {
	frame: Frame,
	set: (cost: number, seconds: number, vramNeed: number, vramHave: number, timeKnown: boolean) -> (),
}

function Parts.costBadge(parent: Instance): CostBadge
	local frame = Parts.panel(parent, UDim2.new(), UDim2.new(1, 0, 0, 76))
	frame.Name = "CostBadge"
	local function cell(x: UDim, width: UDim, caption: string): (TextLabel, TextLabel)
		local holder = Kit.frame(frame, UDim2.new(width, UDim.new(1, 0)), UDim2.new(x, UDim.new(0, 0)))
		Parts.label(holder, caption, 20, F.bold, C.muted, UDim2.fromOffset(18, 6), UDim2.new(1, -24, 0, 24))
		local value = Parts.label(holder, "", 30, F.display, C.text, UDim2.fromOffset(18, 30), UDim2.new(1, -24, 0, 38))
		return holder :: any, value
	end
	local _, costValue = cell(UDim.new(0, 0), UDim.new(0.44, 0), "TRAINING COST")
	local _, timeValue = cell(UDim.new(0.44, 0), UDim.new(0.22, 0), "TIME")
	local _, vramValue = cell(UDim.new(0.66, 0), UDim.new(0.34, 0), "VRAM")
	vramValue.RichText = true
	local deltaChip = Parts.tag(frame, "", C.bad, UDim2.new(0, 150, 0, 36))
	deltaChip.Visible = false
	for _, x in { 0.44, 0.66 } do
		local line = Kit.frame(frame, UDim2.new(0, 1, 1, -20), UDim2.new(x, 0, 0, 10))
		line.BackgroundTransparency = 0.9
		line.BackgroundColor3 = C.line
	end
	local lastCost: number? = nil
	local shownAt = 0
	return {
		frame = frame,
		set = function(cost: number, seconds: number, vramNeed: number, vramHave: number, timeKnown: boolean)
			costValue.Text = Parts.money(cost)
			if lastCost and lastCost ~= cost then
				local d = cost - lastCost
				deltaChip.Text = Parts.signedMoney(d)
				deltaChip.TextColor3 = if d > 0 then C.bad else C.good
				local stroke = deltaChip:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = deltaChip.TextColor3
				end
				deltaChip.Visible = true
				shownAt = os.clock()
				local mark = shownAt
				task.delay(1.2, function()
					if shownAt == mark then
						deltaChip.Visible = false
					end
				end)
			end
			lastCost = cost
			timeValue.Text = if timeKnown then Format.duration(seconds) else "--"
			local enough = vramHave >= vramNeed
			local have = if vramHave >= 1000 then string.format("%.1f TB", vramHave / 1000) else `{vramHave} GB`
			vramValue.Text = `{vramNeed} <font size="20">of {have}</font>`
			vramValue.TextColor3 = if enough then C.text else C.bad
		end,
	}
end

---------------------------------------------------------------------------- stat bars

export type StatBars = { frame: Frame, set: (stats: { [string]: number }, best: { [string]: number }?, color: Color3?) -> (), fill: (count: number) -> (), layout: (rowHeight: number) -> () }

-- One row per stat: label 20 px, bar, value 20 px bold, a white tick at the best value of that stat.
function Parts.statBars(parent: Instance, ids: { string }, rowHeight: number, labelWidth: number, position: UDim2, width: UDim): StatBars
	local frame = Kit.frame(parent, UDim2.new(width, UDim.new(0, rowHeight * #ids)), position)
	frame.Name = "StatBars"
	type Row = { fill: Frame, tick: Frame, value: TextLabel, track: Frame, id: string, name: TextLabel }
	local rows: { Row } = {}
	for i, id in ids do
		local y = (i - 1) * rowHeight
		local label = "?"
		for _, stat in ModelConfig.STATS do
			if stat.id == id then
				label = stat.label
			end
		end
		local name = Parts.label(frame, label, 20, F.medium, C.muted, UDim2.fromOffset(0, y), UDim2.new(0, labelWidth, 0, rowHeight))
		local track = Parts.box(frame, UDim2.new(0, labelWidth + 6, 0, y + rowHeight / 2 - 4), UDim2.new(1, -labelWidth - 62, 0, 8), C.raised, 0, 4)
		local fill = Parts.box(track, UDim2.new(), UDim2.fromScale(0, 1), Theme.accent, 0, 4)
		local tick = Parts.box(track, UDim2.new(0, 0, 0.5, -8), UDim2.fromOffset(3, 16), C.white, 0, 0)
		tick.Visible = false
		local value = Parts.label(frame, "0", 20, F.bold, C.text, UDim2.new(1, -50, 0, y), UDim2.new(0, 50, 0, rowHeight), Enum.TextXAlignment.Right)
		rows[i] = { fill = fill, tick = tick, value = value, track = track, id = id, name = name }
	end
	local lastStats: { [string]: number } = {}
	return {
		frame = frame,
		set = function(stats: { [string]: number }, best: { [string]: number }?, color: Color3?)
			lastStats = stats
			for _, row in rows do
				local max = if row.id == "speed" or row.id == "efficiency" then 100 else ModelConfig.STAT_CAP
				local v = stats[row.id] or 0
				row.fill.Size = UDim2.fromScale(math.clamp(v / max, 0, 1), 1)
				row.fill.BackgroundColor3 = color or Theme.accent
				row.value.Text = string.format("%.0f", v)
				local b = if best then best[row.id] else nil
				row.tick.Visible = b ~= nil and b > 0
				if b then
					row.tick.Position = UDim2.new(math.clamp(b / max, 0, 1), -1, 0.5, -8)
				end
			end
		end,
		layout = function(h: number)
			frame.Size = UDim2.new(frame.Size.X, UDim.new(0, h * #rows))
			for i, row in rows do
				local y = (i - 1) * h
				row.name.Position = UDim2.fromOffset(0, y)
				row.name.Size = UDim2.new(0, labelWidth, 0, h)
				row.track.Position = UDim2.new(0, labelWidth + 6, 0, y + h / 2 - 4)
				row.value.Position = UDim2.new(1, -50, 0, y)
				row.value.Size = UDim2.new(0, 50, 0, h)
			end
		end,
		-- reveal: bars fill one after the other (count = rows shown so far)
		fill = function(count: number)
			for i, row in rows do
				local max = if row.id == "speed" or row.id == "efficiency" then 100 else ModelConfig.STAT_CAP
				local v = if i <= count then (lastStats[row.id] or 0) else 0
				row.fill.Size = UDim2.fromScale(math.clamp(v / max, 0, 1), 1)
			end
		end,
	}
end

---------------------------------------------------------------------------- stage (podium, beams, confetti)

export type Stage = { frame: Frame, podium: Frame, burst: (count: number?) -> (), clear: () -> (), setFloor: (y: number, x: number?) -> () }

-- The ceremony backdrop inside `parent`: two light beams, a lit podium ellipse under a card centred at
-- (centerX, podiumY). Beams are vertical gradients (no Rotation: guiprev and low-end devices draw them flat).
function Parts.stage(parent: Instance, center: UDim2, podiumWidth: number): Stage
	local frame = Kit.frame(parent, UDim2.fromScale(1, 1))
	frame.Name = "Stage"
	-- spotlight from above onto the podium (the reference's spotlit reveal): a wide faint shaft and a narrow
	-- bright core, both vertical gradients that fade out towards the podium (Frames only, no Rotation)
	local floorY = center.Y.Offset
	local shafts: { Frame } = {}
	for _, def in { { 1.1, 0.86 }, { 0.8, 0.76 } } do
		local width = math.floor(podiumWidth * def[1])
		local shaft = Kit.frame(frame, UDim2.new(0, width, center.Y.Scale, floorY), UDim2.new(center.X.Scale, center.X.Offset, 0, 0))
		shaft.Name = "Spotlight"
		shaft.AnchorPoint = Vector2.new(0.5, 0)
		shaft.BackgroundTransparency = 0
		shaft.BackgroundColor3 = C.white
		Kit.corner(shaft, math.floor(width / 2))
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, def[2]),
			NumberSequenceKeypoint.new(0.7, math.min(1, def[2] + 0.06)),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = shaft
		table.insert(shafts, shaft)
	end
	-- soft halo behind the card (an ellipse fading out downwards)
	local halo = Kit.frame(frame, UDim2.fromOffset(math.floor(podiumWidth * 0.9), math.floor(podiumWidth * 0.9)), UDim2.new(center.X.Scale, center.X.Offset, center.Y.Scale, center.Y.Offset - math.floor(podiumWidth * 0.5)))
	halo.Name = "Halo"
	halo.AnchorPoint = Vector2.new(0.5, 0.5)
	halo.BackgroundTransparency = 0
	halo.BackgroundColor3 = Theme.accent
	Kit.corner(halo, podiumWidth)
	local haloFade = Instance.new("UIGradient")
	haloFade.Rotation = 90
	haloFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.45, 0.9),
		NumberSequenceKeypoint.new(1, 1),
	})
	haloFade.Parent = halo
	-- neon pillars left and right of the podium (the reveal stage of the reference game)
	local pillars: { { frame: Frame, dx: number } } = {}
	for _, dx in { -0.62, -0.48, 0.48, 0.62 } do
		local pillar = Kit.frame(frame, UDim2.new(0, 6, 1, -20), UDim2.new(center.X.Scale, center.X.Offset + math.floor(dx * podiumWidth) - 3, 0, 0))
		table.insert(pillars, { frame = pillar, dx = dx })
		pillar.Name = "Pillar"
		pillar.BackgroundTransparency = 0
		pillar.BackgroundColor3 = Theme.accent
		Kit.corner(pillar, 3)
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.35, if math.abs(dx) > 0.55 then 0.75 else 0.55),
			NumberSequenceKeypoint.new(1, 0.95),
		})
		g.Parent = pillar
	end
	local podium = Kit.frame(frame, UDim2.fromOffset(podiumWidth, math.floor(podiumWidth * 0.17)), center)
	podium.Name = "Podium"
	podium.AnchorPoint = Vector2.new(0.5, 0.5)
	podium.BackgroundTransparency = 0
	podium.BackgroundColor3 = C.panel2
	Kit.corner(podium, podiumWidth)
	local ring = Kit.stroke(podium, 0.3, Theme.accent, 2)
	ring.Name = "Ring"
	local glow = Instance.new("UIGradient")
	glow.Color = ColorSequence.new(C.raised, C.bg)
	glow.Rotation = 90
	glow.Parent = podium
	-- confetti falls behind the card and the side panels (an earlier sibling at the same ZIndex), in the two gaps
	-- beside the card, so the name, the score footer and the panel texts stay readable for its 2 s
	local confetti = Kit.frame(parent, UDim2.fromScale(1, 1))
	confetti.Name = "Confetti"
	local rng = Random.new(7)
	local colors = { C.good, C.warn, companyColor("violet"), companyColor("blue"), C.bad, Theme.accent }
	local pieces: { Frame } = {}
	local stage: Stage = {
		frame = frame,
		podium = podium,
		burst = function(count: number?)
			for _, piece in pieces do
				piece:Destroy()
			end
			table.clear(pieces)
			local n = math.min(40, count or 32)
			for i = 1, n do
				local x = if i % 2 == 0 then rng:NextNumber(0.31, 0.405) else rng:NextNumber(0.595, 0.66)
				local piece = Parts.box(confetti, UDim2.new(x, 0, rng:NextNumber(0.02, 0.5), 0), UDim2.fromOffset(rng:NextInteger(10, 16), rng:NextInteger(14, 22)), colors[(i % #colors) + 1], 0, 3)
				table.insert(pieces, piece)
				local fall = math.min(rng:NextNumber(0.25, 0.45), 0.86 - piece.Position.Y.Scale)
				local target = piece.Position + UDim2.fromScale(rng:NextNumber(-0.04, 0.04), fall)
				Kit.tween(piece, 2, { Position = target, BackgroundTransparency = 0.25 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
			local batch = table.clone(pieces)
			task.delay(2.2, function()
				for _, piece in batch do
					if piece.Parent then
						piece:Destroy()
					end
					local index = table.find(pieces, piece)
					if index then
						table.remove(pieces, index)
					end
				end
			end)
		end,
		clear = function()
			for _, piece in pieces do
				piece:Destroy()
			end
			table.clear(pieces)
		end,
		-- move the podium (and the spotlight's end) to y = `y` (and x = `x` offset) when the card size changes
		setFloor = function(y: number, x: number?)
			local px = x or center.X.Offset
			podium.Position = UDim2.new(center.X.Scale, px, center.Y.Scale, y)
			for _, shaft in shafts do
				shaft.Size = UDim2.new(0, shaft.Size.X.Offset, center.Y.Scale, y)
				shaft.Position = UDim2.new(center.X.Scale, px, 0, 0)
			end
			halo.Position = UDim2.new(center.X.Scale, px, center.Y.Scale, y - math.floor(podiumWidth * 0.5))
			for _, p in pillars do
				p.frame.Position = UDim2.new(center.X.Scale, px + math.floor(p.dx * podiumWidth) - 3, 0, 0)
			end
		end,
	}
	return stage
end

-- Count a label up from `from` to `to` over `seconds` ("%.1f"); returns a cancel function.
function Parts.countUp(label: TextLabel, from: number, to: number, seconds: number): () -> ()
	local cancelled = false
	task.spawn(function()
		local elapsed = 0
		while label.Parent and not cancelled do
			local t = math.min(1, elapsed / seconds)
			local eased = 1 - (1 - t) ^ 3
			label.Text = string.format("%.1f", from + (to - from) * eased)
			if t >= 1 then
				break
			end
			elapsed += task.wait()
		end
		if not cancelled then
			label.Text = string.format("%.1f", to)
		end
	end)
	return function()
		cancelled = true
		label.Text = string.format("%.1f", to)
	end
end

return Parts
