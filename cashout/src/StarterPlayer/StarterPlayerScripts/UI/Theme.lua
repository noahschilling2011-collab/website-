--[[
	Theme.lua

	Farben und ein paar Instanz-Helfer, damit OrderPanel, HeatBar, RoundHud und
	RoundEndBoard nicht viermal dasselbe Instance.new-Geruest enthalten.

	Der Farbcode aus Dokument 4.2 ist bindend, nicht dekorativ:

	  Gruen  (60,220,120)  Cash, unsicher       -- nirgends sonst
	  Gold   (255,200,60)  Banked, sicher       -- Bank, Sieger
	  Orange -> Rot        Heat, Verlaufskurve
	  Rot    (255,60,60)   AUSSCHLIESSLICH Gefahr
	  Weiss                fremder Spieler zahlt gerade ein
	  Cyan                 dein aktiver Uebergabepunkt

	Deshalb ist Danger hier zwar definiert, wird in Phase 1 aber nirgends
	benutzt -- es gibt noch keine Gefahr. Negative Meldungen laufen ueber
	Theme.Muted, nicht ueber Rot.

	Stufenfarben kommen aus Balance.Orders.Tiers, damit Server (Paket) und
	Client (Karte) dieselbe Farbe benutzen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Balance"))

local Theme = {}

-- Untergrund
Theme.Background = Color3.fromRGB(14, 16, 20)
Theme.Panel = Color3.fromRGB(24, 27, 33)
Theme.PanelRaised = Color3.fromRGB(34, 38, 46)
Theme.Line = Color3.fromRGB(56, 62, 72)

Theme.Text = Color3.fromRGB(238, 242, 246)
Theme.TextDim = Color3.fromRGB(146, 154, 166)

-- Gebundener Farbcode
Theme.Cash = Color3.fromRGB(60, 220, 120)
Theme.Banked = Color3.fromRGB(255, 200, 60)
Theme.Danger = Color3.fromRGB(255, 60, 60)
Theme.Depositing = Color3.fromRGB(255, 255, 255)
Theme.Delivery = Color3.fromRGB(80, 220, 235)

-- Heat-Verlauf: Orange -> Rot
Theme.HeatLow = Color3.fromRGB(255, 150, 50)
Theme.HeatHigh = Theme.Danger

-- Neutral fuer Hinweise und Abbrueche. Bewusst kein Rot.
Theme.Muted = Color3.fromRGB(176, 184, 196)

function Theme.TierColor(tierId: string): Color3
	local tier = Balance.Orders.TierById[tierId]
	return tier and tier.Color or Theme.Muted
end

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
	Heat-Farbe fuer t in [0, 1]: Orange -> Rot.
]]
function Theme.HeatColor(t: number): Color3
	return Theme.HeatLow:Lerp(Theme.HeatHigh, math.clamp(t, 0, 1))
end

--[[
	mm:ss, nie negativ.
]]
function Theme.Clock(seconds: number): string
	local whole = math.max(math.floor(seconds), 0)
	return string.format("%d:%02d", whole // 60, whole % 60)
end

return Theme
