--[[
	Theme (Visual-Rewrite)

	Drop-in-Ersatz: alle bisherigen Funktionen (create, corner, padding, list,
	label, button, panel, constrain, Root) und alle bisherigen Farbnamen
	(panel, panelAlt, accent, good, bad, heist, text, sub) bleiben erhalten.
	Die restlichen UI-Dateien muessen nicht angefasst werden.

	Was sich aendert:
	- Palette hat jetzt einen Blaustich statt Neutralgrau. Reines Grau sieht
	  auf Roblox-Handys nach Debug-Menue aus.
	- Jedes Panel und jeder Knopf bekommt eine Kontur und einen Verlauf.
	  Ein flaches Rechteck ohne Kante liest sich nicht als Knopf.
	- Michroma als Anzeigeschrift. Gotham ist die Roblox-Standardschrift -
	  damit sieht jede UI aus wie jede andere.

	Neu dazu (optional nutzbar):
		Theme.stroke, Theme.gradient, Theme.glow, Theme.pop, Theme.countTo
]]

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Theme = {}

local NARROW_WIDTH = 600
local NARROW_SCALE = 0.75
local SHORT_HEIGHT = 500
local SHORT_SCALE = 0.6

Theme.Colors = {
	bg = Color3.fromRGB(11, 13, 18),
	panel = Color3.fromRGB(23, 26, 33),
	panelAlt = Color3.fromRGB(34, 38, 48),
	line = Color3.fromRGB(56, 64, 80),
	accent = Color3.fromRGB(245, 166, 35),
	neon = Color3.fromRGB(56, 214, 255),
	good = Color3.fromRGB(74, 222, 128),
	bad = Color3.fromRGB(240, 82, 82),
	heist = Color3.fromRGB(255, 45, 85),
	text = Color3.fromRGB(242, 244, 248),
	sub = Color3.fromRGB(138, 147, 165),
	ink = Color3.fromRGB(14, 12, 6), -- Text auf hellen Knoepfen
}

Theme.Fonts = {
	display = Enum.Font.Michroma,
	heading = Enum.Font.GothamBlack,
	body = Enum.Font.Gotham,
	bodyBold = Enum.Font.GothamBold,
}

function Theme.create(className: string, props: { [string]: any }?, children: { Instance }?): Instance
	local instance = Instance.new(className)
	if props then
		local parent = props.Parent
		props.Parent = nil
		for key, value in props do
			(instance :: any)[key] = value
		end
		if children then
			for _, child in children do
				child.Parent = instance
			end
		end
		if parent then
			instance.Parent = parent
		end
	elseif children then
		for _, child in children do
			child.Parent = instance
		end
	end
	return instance
end

function Theme.corner(radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 10)
	return corner
end

function Theme.padding(amount: number): UIPadding
	local padding = Instance.new("UIPadding")
	local offset = UDim.new(0, amount)
	padding.PaddingTop = offset
	padding.PaddingBottom = offset
	padding.PaddingLeft = offset
	padding.PaddingRight = offset
	return padding
end

function Theme.list(direction: Enum.FillDirection?, gap: number?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction or Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, gap or 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	return layout
end

-- Kontur. Der billigste Trick, damit ein Panel nicht im Hintergrund versinkt.
function Theme.stroke(parent: GuiObject, color: Color3?, thickness: number?, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.Colors.line
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0.35
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

-- Senkrechter Verlauf: oben etwas heller als unten. Gibt Flaechen eine
-- Lichtrichtung, statt sie als gleichmaessige Farbfelder stehen zu lassen.
--
-- ACHTUNG: UIGradient faerbt bei TextLabel/TextButton auch den Text mit.
-- Deshalb nur auf Frames anwenden, nie auf Knoepfe.
function Theme.gradient(parent: GuiObject, lift: number?, rotation: number?): UIGradient
	local amount = lift or 0.14
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation or 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1):Lerp(Color3.new(1.0, 1.0, 1.0), 0)),
		ColorSequenceKeypoint.new(1, Color3.new(1 - amount, 1 - amount, 1 - amount)),
	})
	gradient.Parent = parent
	return gradient
end

-- Leuchtrand fuer Zustaende, die auffallen sollen (Heist offen, Belohnung da).
function Theme.glow(parent: GuiObject, color: Color3): UIStroke
	local stroke = Theme.stroke(parent, color, 2, 0.1)
	stroke.Name = "Glow"
	return stroke
end

function Theme.label(props): TextLabel
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or Theme.Fonts.body
	props.TextColor3 = props.TextColor3 or Theme.Colors.text
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.Text = props.Text or ""
	return Theme.create("TextLabel", props) :: TextLabel
end

function Theme.button(props): TextButton
	props.BackgroundColor3 = props.BackgroundColor3 or Theme.Colors.panelAlt
	props.Font = props.Font or Theme.Fonts.bodyBold
	props.TextColor3 = props.TextColor3 or Theme.Colors.text
	props.AutoButtonColor = true
	props.BorderSizePixel = 0
	props.Text = props.Text or ""
	local button = Theme.create("TextButton", props) :: TextButton
	Theme.corner(10).Parent = button
	-- Kein UIGradient auf Knoepfen: der Verlauf wuerde den Text mitfaerben.
	Theme.stroke(button, Theme.Colors.line, 1, 0.45)

	-- Kurzer Druckpunkt. Ohne Rueckmeldung fuehlt sich Touch-UI kaputt an.
	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.96 }):Play()
	end)
	local function release()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)

	return button
end

function Theme.panel(props): Frame
	props.BackgroundColor3 = props.BackgroundColor3 or Theme.Colors.panel
	props.BorderSizePixel = 0
	local frame = Theme.create("Frame", props) :: Frame
	Theme.corner(14).Parent = frame
	Theme.gradient(frame, 0.12)
	Theme.stroke(frame, Theme.Colors.line, 1, 0.4)
	return frame
end

-- Kurzer Skalen-Impuls, z.B. wenn Cash reinkommt.
function Theme.pop(instance: GuiObject, strength: number?)
	local scale = instance:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = instance
	scale.Scale = 1 + (strength or 0.08)
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
end

-- Zahlen hochzaehlen statt umspringen. Der Unterschied zwischen "eine Zahl
-- steht da" und "ich verdiene gerade Geld".
function Theme.countTo(label: TextLabel, from: number, to: number, format: (number) -> string, duration: number?)
	local value = Instance.new("NumberValue")
	value.Value = from
	local connection
	connection = value:GetPropertyChangedSignal("Value"):Connect(function()
		label.Text = format(value.Value)
	end)
	local tween = TweenService:Create(value, TweenInfo.new(duration or 0.35, Enum.EasingStyle.Quad), { Value = to })
	tween.Completed:Connect(function()
		label.Text = format(to)
		connection:Disconnect()
		value:Destroy()
	end)
	tween:Play()
end

function Theme.constrain(instance: GuiObject, minSize: Vector2?, maxSize: Vector2?)
	local constraint = Instance.new("UISizeConstraint")
	if minSize then
		constraint.MinSize = minSize
	end
	if maxSize then
		constraint.MaxSize = maxSize
	end
	constraint.Parent = instance
	return instance
end

local root: Frame? = nil

-- Liefert die Flaeche, in die alle UI-Module zeichnen.
--
-- UIScale wirkt nur auf GuiObjects, nicht auf eine ScreenGui. Deshalb liegt
-- zwischen ScreenGui und UI eine Container-Flaeche: sie wird um 1/scale
-- groesser gemacht und danach um `scale` verkleinert.
function Theme.Root(playerGui: Instance): Frame
	if root and root.Parent then
		return root
	end

	local screen = Theme.create("ScreenGui", {
		Name = "GarageHeistUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})

	local container = Theme.create("Frame", {
		Name = "Layer",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = screen,
	}) :: Frame

	local scale = Instance.new("UIScale")
	scale.Parent = container

	local camera = Workspace.CurrentCamera
	local function fit()
		local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
		local factor = 1
		if viewport.X < NARROW_WIDTH then
			factor = NARROW_SCALE
		end
		if viewport.Y < SHORT_HEIGHT then
			factor = math.min(factor, SHORT_SCALE)
		end
		scale.Scale = factor
		container.Size = UDim2.fromScale(1 / factor, 1 / factor)
	end

	local function watch()
		camera = Workspace.CurrentCamera
		fit()
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
		end
	end

	watch()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watch)

	root = container
	return container
end

return Theme
