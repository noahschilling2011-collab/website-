--[[
	Theme.lua

	Farben und ein paar Instanz-Helfer, damit DealPanel, HeatBar und RoundHud
	nicht dreimal dasselbe Instance.new-Geruest enthalten.
	Nur Darstellung -- hier steht keine Spielregel und keine Balance-Zahl.
]]

local Theme = {}

Theme.Background = Color3.fromRGB(18, 20, 24)
Theme.Panel = Color3.fromRGB(28, 31, 37)
Theme.PanelRaised = Color3.fromRGB(38, 42, 50)
Theme.Line = Color3.fromRGB(58, 63, 72)

Theme.Text = Color3.fromRGB(238, 242, 246)
Theme.TextDim = Color3.fromRGB(150, 158, 168)

Theme.Cash = Color3.fromRGB(240, 202, 92)
Theme.Banked = Color3.fromRGB(92, 200, 136)
Theme.Bad = Color3.fromRGB(226, 86, 86)
Theme.Warn = Color3.fromRGB(232, 168, 72)
Theme.Cool = Color3.fromRGB(92, 174, 214)

Theme.HeatLow = Color3.fromRGB(92, 200, 136)
Theme.HeatMid = Color3.fromRGB(232, 190, 72)
Theme.HeatHigh = Color3.fromRGB(226, 76, 76)

Theme.TierColor = {
	Small = Color3.fromRGB(120, 176, 208),
	Medium = Color3.fromRGB(128, 196, 140),
	Large = Color3.fromRGB(232, 180, 84),
	Extreme = Color3.fromRGB(228, 96, 96),
}

--[[
	Instanz mit Eigenschaften anlegen. Parent kommt zuletzt, damit nichts
	unfertig im Baum haengt.
]]
function Theme.New(className: string, props: { [string]: any }, parent: Instance?): Instance
	local instance = Instance.new(className)
	for key, value in pairs(props) do
		instance[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Theme.Corner(parent: Instance, radius: number)
	Theme.New("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

function Theme.Stroke(parent: Instance, color: Color3, thickness: number, transparency: number?)
	Theme.New("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
	}, parent)
end

function Theme.Padding(parent: Instance, px: number)
	Theme.New("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	}, parent)
end

function Theme.Label(props: { [string]: any }, parent: Instance): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Text = "",
	}
	for key, value in pairs(props) do
		defaults[key] = value
	end
	return Theme.New("TextLabel", defaults, parent) :: TextLabel
end

--[[
	Farbverlauf gruen -> gelb -> rot ueber t in [0, 1]. Fuer die Heat-Leiste.
]]
function Theme.HeatColor(t: number): Color3
	t = math.clamp(t, 0, 1)
	if t < 0.5 then
		return Theme.HeatLow:Lerp(Theme.HeatMid, t / 0.5)
	end
	return Theme.HeatMid:Lerp(Theme.HeatHigh, (t - 0.5) / 0.5)
end

return Theme
