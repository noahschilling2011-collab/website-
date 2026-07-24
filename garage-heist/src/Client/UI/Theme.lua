--[[
	Theme
	Farben, Schriften und ein winziger Instance-Builder. Damit bleiben die
	UI-Dateien kurz genug, um sie noch lesen zu koennen.
]]

local Workspace = game:GetService("Workspace")

local Theme = {}

-- Zwei Schwellen: schmal (Handy hochkant) und flach (Handy quer). Beides
-- verkleinert die Oberflaeche, damit die Leiste oben und die Knoepfe unten
-- gleichzeitig Platz haben.
local NARROW_WIDTH = 600
local NARROW_SCALE = 0.75
local SHORT_HEIGHT = 500
local SHORT_SCALE = 0.6

Theme.Colors = {
	bg = Color3.fromRGB(18, 18, 22),
	panel = Color3.fromRGB(30, 31, 36),
	panelAlt = Color3.fromRGB(43, 45, 52),
	accent = Color3.fromRGB(245, 166, 35),
	good = Color3.fromRGB(90, 215, 130),
	bad = Color3.fromRGB(235, 80, 80),
	heist = Color3.fromRGB(225, 60, 90),
	text = Color3.fromRGB(240, 240, 245),
	sub = Color3.fromRGB(168, 172, 182),
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
	corner.CornerRadius = UDim.new(0, radius or 8)
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

function Theme.label(props): TextLabel
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or Enum.Font.Gotham
	props.TextColor3 = props.TextColor3 or Theme.Colors.text
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.Text = props.Text or ""
	return Theme.create("TextLabel", props) :: TextLabel
end

function Theme.button(props): TextButton
	props.BackgroundColor3 = props.BackgroundColor3 or Theme.Colors.panelAlt
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or Theme.Colors.text
	props.AutoButtonColor = true
	props.BorderSizePixel = 0
	props.Text = props.Text or ""
	local button = Theme.create("TextButton", props) :: TextButton
	Theme.corner(8).Parent = button
	return button
end

function Theme.panel(props): Frame
	props.BackgroundColor3 = props.BackgroundColor3 or Theme.Colors.panel
	props.BorderSizePixel = 0
	local frame = Theme.create("Frame", props) :: Frame
	Theme.corner(12).Parent = frame
	return frame
end

-- Begrenzt eine in Skalen definierte Flaeche, damit sie auf grossen Schirmen
-- nicht aufgeblasen und auf kleinen nicht unlesbar wird.
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
-- Wichtig: UIScale wirkt nur auf GuiObjects, nicht auf eine ScreenGui. Deshalb
-- liegt zwischen ScreenGui und UI eine Container-Flaeche. Sie wird um 1/scale
-- groesser gemacht und danach um `scale` verkleinert - unterm Strich deckt sie
-- exakt den Bildschirm ab, nur ist alles darin kleiner. So bleiben rechts und
-- unten verankerte Elemente da, wo sie hingehoeren.
function Theme.Root(playerGui: Instance): Frame
	if root and root.Parent then
		return root
	end

	local screen = Theme.create("ScreenGui", {
		Name = "GarageHeistUI",
		ResetOnSpawn = false,
		-- Auf Touch liegt oben die Roblox-Leiste; wir zeichnen selbst darunter
		-- und brauchen die volle Flaeche.
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
