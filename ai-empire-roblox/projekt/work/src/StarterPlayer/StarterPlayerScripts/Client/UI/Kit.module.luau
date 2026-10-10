--!strict
-- UI-Bausteine. Bewusst typisiert (Instance.new + direkte Property-Zuweisung), damit luau-lsp
-- falsche Property-Namen findet. Größen sind Design-Pixel (UIRoot skaliert alles passend).

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)

local C = Theme.colors
local F = Theme.font

export type Nav = { show: (appId: string) -> (), close: () -> (), isOpen: () -> boolean }
export type ButtonStyle = "primary" | "secondary" | "ghost" | "danger" | "warn"
export type Option = { id: string, label: string }
export type Bar = { frame: Frame, fill: Frame, set: (fraction: number) -> () }
export type Segmented = {
	frame: Frame,
	set: (id: string) -> (),
	get: () -> string,
	setDim: (id: string, dim: boolean) -> (),
}
export type Slider = {
	frame: Frame,
	set: (value: number) -> (),
	get: () -> number,
	setRange: (min: number, max: number) -> (),
}
export type StatRow = { frame: Frame, set: (value: number, max: number?) -> () }
export type Metric = { frame: Frame, value: TextLabel, label: TextLabel }
export type Icon = { frame: Frame, setColor: (color: Color3) -> () }

local Kit = {}

function Kit.tween(
	inst: Instance,
	seconds: number,
	goals: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out)
	local tween = TweenService:Create(inst, info, goals)
	tween:Play()
	return tween
end

function Kit.corner(parent: Instance, radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 10)
	corner.Parent = parent
	return corner
end

function Kit.stroke(parent: Instance, transparency: number?, color: Color3?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color or C.line
	stroke.Transparency = transparency or 0.9
	stroke.Thickness = thickness or 1
	stroke.Parent = parent
	return stroke
end

function Kit.padding(parent: Instance, top: number, right: number?, bottom: number?, left: number?): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, top)
	padding.PaddingRight = UDim.new(0, right or top)
	padding.PaddingBottom = UDim.new(0, bottom or top)
	padding.PaddingLeft = UDim.new(0, left or right or top)
	padding.Parent = parent
	return padding
end

function Kit.list(parent: Instance, gap: number?, horizontal: boolean?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, gap or 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	if horizontal then
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	layout.Parent = parent
	return layout
end

function Kit.gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = rotation or 90
	gradient.Parent = parent
	return gradient
end

function Kit.frame(parent: Instance?, size: UDim2?, position: UDim2?): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = size or UDim2.fromScale(1, 1)
	frame.Position = position or UDim2.new()
	frame.Parent = parent
	return frame
end

-- Spalte mit Inhaltshöhe (volle Breite)
function Kit.stack(parent: Instance, gap: number?, order: number?): Frame
	local frame = Kit.frame(parent, UDim2.fromScale(1, 0))
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = order or 0
	Kit.list(frame, gap)
	return frame
end

-- Zeile mit fester Höhe, Kinder nebeneinander
function Kit.row(parent: Instance, height: number, gap: number?, order: number?): Frame
	local frame = Kit.frame(parent, UDim2.new(1, 0, 0, height))
	frame.LayoutOrder = order or 0
	Kit.list(frame, gap, true)
	return frame
end

-- Glas-Kante: oben hell, nach unten fast unsichtbar (Licht von oben)
function Kit.litStroke(parent: Instance, top: number?): UIStroke
	local stroke = Kit.stroke(parent, 0, C.line, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, top or 0.78),
		NumberSequenceKeypoint.new(0.4, 0.9),
		NumberSequenceKeypoint.new(1, 0.95),
	})
	gradient.Parent = stroke
	return stroke
end

-- Großes Glas-Panel (Fenster, HUD)
function Kit.panel(parent: Instance?, size: UDim2?, position: UDim2?): Frame
	local frame = Kit.frame(parent, size, position)
	frame.BackgroundColor3 = C.panel
	frame.BackgroundTransparency = 0.02
	Kit.corner(frame, 12)
	Kit.stroke(frame, 0.87)
	return frame
end

-- Inhaltskarte mit Innenabstand und Liste
function Kit.card(parent: Instance, order: number?, gap: number?): Frame
	local frame = Kit.frame(parent, UDim2.fromScale(1, 0))
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = order or 0
	frame.BackgroundColor3 = C.panel2
	frame.BackgroundTransparency = 0
	Kit.corner(frame, 10)
	Kit.stroke(frame, 0.93)
	Kit.padding(frame, 16)
	Kit.list(frame, gap or 10)
	return frame
end

function Kit.text(parent: Instance?, text: string, size: number?, font: Enum.Font?, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Text = text
	label.TextSize = size or 16
	label.Font = font or F.medium
	label.TextColor3 = color or C.text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.new()
	label.Parent = parent
	return label
end

-- Fließtext über die volle Breite mit Umbruch
function Kit.para(parent: Instance, text: string, size: number?, color: Color3?, order: number?): TextLabel
	local label = Kit.text(parent, text, size or 15, F.regular, color or C.muted)
	label.Size = UDim2.fromScale(1, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.LayoutOrder = order or 0
	return label
end

-- Abschnittsname: normale Schreibung, gedämpft (keine Großbuchstaben-Etiketten)
function Kit.caption(parent: Instance, text: string, order: number?): TextLabel
	local label = Kit.text(parent, text, 13, F.medium, C.muted)
	label.LayoutOrder = order or 0
	return label
end

-- Fester Textblock (z. B. Spalte in einer Tabelle)
function Kit.cell(parent: Instance, text: string, width: UDim, size: number?, font: Enum.Font?, color: Color3?): TextLabel
	local label = Kit.text(parent, text, size or 15, font, color)
	label.AutomaticSize = Enum.AutomaticSize.None
	label.Size = UDim2.new(width, UDim.new(1, 0))
	label.TextTruncate = Enum.TextTruncate.AtEnd
	return label
end

function Kit.tag(parent: Instance, text: string, color: Color3, order: number?): TextLabel
	local label = Kit.text(parent, string.upper(text), 11, F.bold, color)
	label.BackgroundColor3 = C.bg -- dunkle Basis: lesbar auch über hellem Himmel
	label.BackgroundTransparency = 0.15
	label.LayoutOrder = order or 0
	Kit.corner(label, 6)
	Kit.stroke(label, 0.55, color)
	Kit.padding(label, 3, 7, 3, 7)
	return label
end

function Kit.dot(parent: Instance, color: Color3, size: number?): Frame
	local dot = Kit.frame(parent, UDim2.fromOffset(size or 10, size or 10))
	dot.BackgroundTransparency = 0
	dot.BackgroundColor3 = color
	Kit.corner(dot, (size or 10) // 2 + 1)
	return dot
end

function Kit.divider(parent: Instance, order: number?): Frame
	local line = Kit.frame(parent, UDim2.new(1, 0, 0, 1))
	line.BackgroundTransparency = 0.92
	line.BackgroundColor3 = C.line
	line.LayoutOrder = order or 0
	return line
end

-- Für RichText: Spielertexte (Namen) immer escapen
function Kit.escape(text: string): string
	return (
		string.gsub(text, "[&<>\"']", {
			["&"] = "&amp;",
			["<"] = "&lt;",
			[">"] = "&gt;",
			['"'] = "&quot;",
			["'"] = "&apos;",
		})
	)
end

---------------------------------------------------------------------------- Buttons

function Kit.button(parent: Instance?, text: string, style: ButtonStyle?, size: UDim2?): TextButton
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Text = text
	button.Font = F.bold
	button.TextSize = 16
	button.Size = size or UDim2.fromOffset(140, 40)
	button.Parent = parent
	Kit.corner(button, 10)

	local kind = style or "secondary"
	if kind == "primary" then
		Theme.bindAccent(button, "BackgroundColor3")
		button.BackgroundTransparency = 0
		button.TextColor3 = C.bg
	elseif kind == "danger" or kind == "warn" then
		local color = if kind == "danger" then C.bad else C.warn
		button.BackgroundColor3 = color
		button.BackgroundTransparency = 0.82
		button.TextColor3 = color
		Kit.stroke(button, 0.55, color)
	elseif kind == "ghost" then
		button.BackgroundColor3 = C.raised
		button.BackgroundTransparency = 1
		button.TextColor3 = C.muted
		Kit.stroke(button, 0.84)
	else
		button.BackgroundColor3 = C.raised
		button.BackgroundTransparency = 0
		button.TextColor3 = C.text
		Kit.litStroke(button, 0.8)
	end
	button:SetAttribute("BaseBg", button.BackgroundTransparency)

	-- kleines "Juice": Hover und Druck skalieren den Button
	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseEnter:Connect(function()
		if button:GetAttribute("Disabled") ~= true then
			Kit.tween(scale, 0.15, { Scale = 1.015 })
		end
	end)
	button.MouseLeave:Connect(function()
		Kit.tween(scale, 0.15, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		if button:GetAttribute("Disabled") ~= true then
			Kit.tween(scale, 0.08, { Scale = 0.98 })
		end
	end)
	button.MouseButton1Up:Connect(function()
		Kit.tween(scale, 0.12, { Scale = 1 })
	end)
	return button
end

function Kit.setDisabled(button: TextButton, disabled: boolean)
	if (button:GetAttribute("Disabled") == true) == disabled then
		return
	end
	button:SetAttribute("Disabled", disabled)
	local base = button:GetAttribute("BaseBg")
	local baseBg = if typeof(base) == "number" then base else 0
	button.BackgroundTransparency = if disabled then math.min(1, baseBg + 0.5) else baseBg
	button.TextTransparency = if disabled then 0.45 else 0
end

-- Klick-Handler, der deaktivierte Buttons ignoriert
function Kit.onClick(button: GuiButton, callback: () -> ())
	button.Activated:Connect(function()
		if button:GetAttribute("Disabled") == true then
			return
		end
		callback()
	end)
end

-- Unsichtbarer Vollflächen-Button: schluckt Klicks/Touches (Kamera dreht sich nicht mit)
function Kit.blocker(parent: Instance, color: Color3, transparency: number): TextButton
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Text = ""
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundColor3 = color
	button.BackgroundTransparency = transparency
	button.Modal = true -- gibt die Maus frei, falls die Kamera sie festhält
	button.Parent = parent
	return button
end

---------------------------------------------------------------------------- Eingaben

function Kit.input(parent: Instance, placeholder: string, size: UDim2?): TextBox
	local box = Instance.new("TextBox")
	box.ClearTextOnFocus = false
	box.Text = ""
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = C.dim
	box.Font = F.medium
	box.TextSize = 18
	box.TextColor3 = C.text
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.BackgroundColor3 = C.bg
	box.BackgroundTransparency = 0.25
	box.BorderSizePixel = 0
	box.ClipsDescendants = true
	box.Size = size or UDim2.new(1, 0, 0, 44)
	box.Parent = parent
	Kit.corner(box, 10)
	Kit.padding(box, 0, 14, 0, 14)
	local stroke = Kit.stroke(box, 0.84)
	box.Focused:Connect(function()
		stroke.Color = Theme.accent
		stroke.Transparency = 0.2
	end)
	box.FocusLost:Connect(function()
		stroke.Color = C.line
		stroke.Transparency = 0.84
	end)
	return box
end

function Kit.segmented(
	parent: Instance,
	options: { Option },
	initial: string,
	onSelect: (id: string) -> (),
	height: number?
): Segmented
	local frame = Kit.frame(parent, UDim2.new(1, 0, 0, height or 38))
	frame.BackgroundColor3 = C.bg
	frame.BackgroundTransparency = 0.25
	Kit.corner(frame, 10)
	Kit.stroke(frame, 0.9)
	Kit.padding(frame, 3)
	Kit.list(frame, 3, true)

	local count = #options
	local buttons: { [string]: TextButton } = {}
	local dimmed: { [string]: boolean } = {}
	local selected = initial

	local function paint()
		for id, button in buttons do
			local on = id == selected
			button.BackgroundColor3 = if on then Theme.accent else C.raised
			button.BackgroundTransparency = if on then 0 else 1
			button.TextColor3 = if on then C.bg elseif dimmed[id] then C.dim else C.muted
		end
	end

	for index, option in options do
		local button = Instance.new("TextButton")
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.Text = option.label
		button.Font = F.bold
		button.TextSize = 15
		button.Size = UDim2.new(1 / count, -3 * (count - 1) / count, 1, 0)
		button.LayoutOrder = index
		button.Parent = frame
		Kit.corner(button, 8)
		buttons[option.id] = button
		button.Activated:Connect(function()
			if selected == option.id then
				return
			end
			selected = option.id
			paint()
			onSelect(option.id)
		end)
	end
	paint()
	Theme.onAccent(function()
		paint()
	end)

	return {
		frame = frame,
		set = function(id: string)
			selected = id
			paint()
		end,
		get = function(): string
			return selected
		end,
		setDim = function(id: string, dim: boolean)
			dimmed[id] = dim
			paint()
		end,
	}
end

function Kit.slider(
	parent: Instance,
	min: number,
	max: number,
	step: number,
	value: number,
	onChange: (value: number) -> ()
): Slider
	local frame = Kit.frame(parent, UDim2.new(1, 0, 0, 30))
	local track = Instance.new("TextButton")
	track.AutoButtonColor = false
	track.Text = ""
	track.BorderSizePixel = 0
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, 10, 0.5, 0)
	track.Size = UDim2.new(1, -20, 0, 8)
	track.BackgroundColor3 = C.raised
	track.Parent = frame
	Kit.corner(track, 4)

	local fill = Kit.frame(track, UDim2.fromScale(0, 1))
	fill.BackgroundTransparency = 0
	Theme.bindAccent(fill, "BackgroundColor3")
	Kit.corner(fill, 4)

	local knob = Kit.frame(track, UDim2.fromOffset(20, 20))
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.BackgroundTransparency = 0
	knob.BackgroundColor3 = C.white
	Kit.corner(knob, 10)
	Kit.stroke(knob, 0.3, C.bg, 2)

	local lo, hi, current = min, max, value
	local dragging = false

	local function clampSnap(v: number): number
		local snapped = math.round((v - lo) / step) * step + lo
		return math.round(math.clamp(snapped, lo, math.max(lo, hi)) * 100) / 100
	end

	local function paint()
		local fraction = if hi > lo then (current - lo) / (hi - lo) else 0
		fill.Size = UDim2.fromScale(fraction, 1)
		knob.Position = UDim2.fromScale(fraction, 0.5)
	end

	local function updateFrom(x: number)
		local width = track.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local fraction = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		local v = clampSnap(lo + fraction * (hi - lo))
		if v ~= current then
			current = v
			paint()
			onChange(v)
		end
	end

	local function begin(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			updateFrom(input.Position.X)
		end
	end
	track.InputBegan:Connect(begin)
	knob.InputBegan:Connect(begin)
	-- ungeprüft: X-Koordinaten von InputObject und AbsolutePosition stimmen bei seitlichen Notch-Insets überein
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			updateFrom(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)
	paint()

	return {
		frame = frame,
		set = function(v: number)
			current = clampSnap(v)
			paint()
		end,
		get = function(): number
			return current
		end,
		setRange = function(newMin: number, newMax: number)
			lo, hi = newMin, math.max(newMin, newMax)
			current = clampSnap(current)
			paint()
		end,
	}
end

---------------------------------------------------------------------------- Anzeigen

-- Fortschrittsbalken. Ohne color folgt die Füllung der Akzentfarbe.
function Kit.bar(parent: Instance, height: number?, order: number?, color: Color3?): Bar
	local h = height or 8
	local frame = Kit.frame(parent, UDim2.new(1, 0, 0, h))
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3 = C.raised
	frame.LayoutOrder = order or 0
	frame.ClipsDescendants = true
	Kit.corner(frame, math.ceil(h / 2))
	local fill = Kit.frame(frame, UDim2.fromScale(0, 1))
	fill.BackgroundTransparency = 0
	if color then
		fill.BackgroundColor3 = color
	else
		Theme.bindAccent(fill, "BackgroundColor3")
	end
	Kit.corner(fill, math.ceil(h / 2))
	Kit.gradient(fill, Color3.fromRGB(170, 176, 190), C.white, 0) -- Füllung wird nach rechts heller
	return {
		frame = frame,
		fill = fill,
		set = function(fraction: number)
			local f = if fraction == fraction then math.clamp(fraction, 0, 1) else 0
			fill.Size = UDim2.fromScale(f, 1)
		end,
	}
end

-- Stacked bar: segments side by side, each a share of `total` (sum of the values when total is nil).
-- Segments with value 0 are hidden; the rest of the track stays empty (C.raised).
export type SplitBar = { frame: Frame, set: (segments: { { value: number, color: Color3 } }, total: number?) -> () }
function Kit.splitBar(parent: Instance, height: number?, order: number?): SplitBar
	local h = height or 12
	local frame = Kit.frame(parent, UDim2.new(1, 0, 0, h))
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3 = C.raised
	frame.LayoutOrder = order or 0
	frame.ClipsDescendants = true
	Kit.corner(frame, math.ceil(h / 2))
	local parts: { Frame } = {}
	return {
		frame = frame,
		set = function(segments: { { value: number, color: Color3 } }, total: number?)
			local sum = 0
			for _, seg in segments do
				sum += math.max(0, if seg.value == seg.value then seg.value else 0)
			end
			local whole = math.max(total or sum, 1e-9)
			local x = 0
			for i, seg in segments do
				if i > #parts then
					local made = Kit.frame(frame)
					made.BackgroundTransparency = 0
					table.insert(parts, made)
				end
				local part = parts[i]
				local share = math.clamp(math.max(0, if seg.value == seg.value then seg.value else 0) / whole, 0, math.max(0, 1 - x))
				part.Visible = share > 0
				part.BackgroundColor3 = seg.color
				part.Position = UDim2.fromScale(x, 0)
				part.Size = UDim2.fromScale(share, 1)
				x += share
			end
			for i = #segments + 1, #parts do
				parts[i].Visible = false
			end
		end,
	}
end

-- Legend chip: coloured dot + short text (for split bars and charts)
function Kit.legend(parent: Instance, color: Color3, text: string, order: number?): (Frame, TextLabel)
	local holder = Kit.frame(parent, UDim2.new(0, 0, 0, 18))
	holder.AutomaticSize = Enum.AutomaticSize.X
	holder.LayoutOrder = order or 0
	Kit.list(holder, 6, true)
	local dot = Kit.dot(holder, color, 9)
	dot.LayoutOrder = 1
	local label = Kit.text(holder, text, 13, F.medium, C.muted)
	label.LayoutOrder = 2
	return holder, label
end

-- Zeile "Name ▓▓▓▓░░ Wert" für Modell-Stats
function Kit.statRow(parent: Instance, label: string, order: number?): StatRow
	local row = Kit.frame(parent, UDim2.new(1, 0, 0, 22))
	row.LayoutOrder = order or 0
	local name = Kit.cell(row, label, UDim.new(0, 92), 14, F.medium, C.muted)
	name.Position = UDim2.new()
	local track = Kit.frame(row, UDim2.new(1, -150, 0, 6), UDim2.new(0, 98, 0.5, -3))
	track.BackgroundTransparency = 0
	track.BackgroundColor3 = C.raised
	Kit.corner(track, 3)
	local fill = Kit.frame(track, UDim2.fromScale(0, 1))
	fill.BackgroundTransparency = 0
	Theme.bindAccent(fill, "BackgroundColor3")
	Kit.corner(fill, 3)
	local value = Kit.cell(row, "0", UDim.new(0, 44), 14, F.bold, C.text)
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.fromScale(1, 0)
	value.TextXAlignment = Enum.TextXAlignment.Right
	return {
		frame = row,
		set = function(v: number, max: number?)
			fill.Size = UDim2.fromScale(math.clamp(v / (max or 100), 0, 1), 1)
			value.Text = string.format("%.0f", v)
		end,
	}
end

-- Kennzahl: kleine Überschrift + großer Wert
function Kit.metric(parent: Instance, label: string, order: number?, valueSize: number?): Metric
	local frame = Kit.frame(parent, UDim2.new())
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.LayoutOrder = order or 0
	Kit.list(frame, 2)
	local caption = Kit.caption(frame, label, 1)
	local value = Kit.text(frame, "–", valueSize or 20, F.bold, C.text)
	value.LayoutOrder = 2
	return { frame = frame, value = value, label = caption }
end

-- Zwei Spalten nebeneinander (links/rechts), jeweils mit Inhaltshöhe
function Kit.columns(parent: Instance, leftShare: number, gap: number?, order: number?): (Frame, Frame)
	local holder = Kit.frame(parent, UDim2.fromScale(1, 0))
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.LayoutOrder = order or 0
	local g = gap or 14
	local left = Kit.frame(holder, UDim2.new(leftShare, -g / 2, 0, 0))
	left.AutomaticSize = Enum.AutomaticSize.Y
	Kit.list(left, 12)
	local right = Kit.frame(holder, UDim2.new(1 - leftShare, -g / 2, 0, 0), UDim2.new(leftShare, g / 2, 0, 0))
	right.AutomaticSize = Enum.AutomaticSize.Y
	Kit.list(right, 12)
	return left, right
end

-- Raster mit festen Spalten und fester Zellenhöhe, Gesamthöhe automatisch
function Kit.grid(parent: Instance, columns: number, cellHeight: number, gap: number?, order: number?): Frame
	local frame = Kit.frame(parent, UDim2.fromScale(1, 0))
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = order or 0
	local g = gap or 10
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / columns, -g * (columns - 1) / columns, 0, cellHeight)
	grid.CellPadding = UDim2.fromOffset(g, g)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = frame
	return frame
end

function Kit.scroll(parent: Instance, size: UDim2?, position: UDim2?): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = size or UDim2.fromScale(1, 1)
	scroll.Position = position or UDim2.new()
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = C.white
	scroll.ScrollBarImageTransparency = 0.75
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	scroll.Parent = parent
	return scroll
end

-- Seitenkopf einer App: Titel in der Display-Schrift, darunter eine Zeile Erklärung
function Kit.heading(parent: Instance, title: string, subtitle: string?, order: number?): TextLabel
	local head = Kit.stack(parent, 6, order)
	local label = Kit.text(head, title, 22, F.display, C.text)
	label.LayoutOrder = 1
	if subtitle then
		Kit.para(head, subtitle, 14, C.muted, 2)
	end
	return label
end

-- Kleine Linien-Icons aus Frames (keine Emoji, keine Asset-IDs): lab, data, compute, market
function Kit.icon(parent: Instance, kind: string, size: number?): Icon
	local s = size or 20
	local frame = Kit.frame(parent, UDim2.fromOffset(s, s))
	local fills: { Frame } = {}
	local rings: { UIStroke } = {}
	local function block(x: number, y: number, w: number, h: number, radius: number?)
		local b = Kit.frame(frame, UDim2.fromScale(w, h), UDim2.fromScale(x, y))
		b.BackgroundTransparency = 0
		Kit.corner(b, radius or 2)
		table.insert(fills, b)
	end
	local function ring(x: number, y: number, w: number, h: number, radius: number)
		local r = Kit.frame(frame, UDim2.fromScale(w, h), UDim2.fromScale(x, y))
		Kit.corner(r, radius)
		table.insert(rings, Kit.stroke(r, 0, C.white, 2))
	end
	if kind == "empire" then
		block(0.12,0.25,0.76,0.68,2)
		ring(0.3,0.02,0.4,0.23,2)
	elseif kind == "lab" then -- Neuron
		ring(0.08, 0.08, 0.84, 0.84, s)
		block(0.34, 0.34, 0.32, 0.32, s)
	elseif kind == "data" then -- gestapelte Datensätze
		block(0.04, 0.1, 0.92, 0.2)
		block(0.04, 0.4, 0.92, 0.2)
		block(0.04, 0.7, 0.92, 0.2)
	elseif kind == "compute" then -- Chip mit Pins
		ring(0.18, 0.18, 0.64, 0.64, 3)
		block(0.38, 0.38, 0.24, 0.24, 1)
		block(0, 0.3, 0.12, 0.1, 1)
		block(0, 0.6, 0.12, 0.1, 1)
		block(0.88, 0.3, 0.12, 0.1, 1)
		block(0.88, 0.6, 0.12, 0.1, 1)
	elseif kind=="studio" then
		ring(.06,.12,.88,.76,2);block(.12,.19,.76,.12);block(.14,.4,.3,.38);block(.5,.4,.32,.1);block(.5,.62,.32,.1)
	elseif kind=="campus" then
		ring(.15,.18,.7,.75,1);block(.05,.88,.9,.1);block(.3,.34,.12,.15);block(.57,.34,.12,.15);block(.44,.65,.12,.28)
	elseif kind=="shop" then -- shopping bag with handle
		ring(.14,.34,.72,.58,3);ring(.32,.08,.36,.36,6);block(.14,.5,.72,.08)
	elseif kind=="arena" then
		ring(.1,.05,.8,.57,3);block(.43,.6,.14,.22);block(.25,.85,.5,.1)
	else -- Markt: steigende Balken
		block(0.04, 0.56, 0.24, 0.4)
		block(0.38, 0.32, 0.24, 0.64)
		block(0.72, 0.06, 0.24, 0.9)
	end
	return {
		frame = frame,
		setColor = function(color: Color3)
			for _, b in fills do
				b.BackgroundColor3 = color
			end
			for _, r in rings do
				r.Color = color
			end
		end,
	}
end

return Kit
