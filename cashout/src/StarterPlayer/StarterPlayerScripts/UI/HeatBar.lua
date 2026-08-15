--[[
	HeatBar.lua

	Heat als Leiste (Orange -> Rot nach 4.2) und die Risikopraemie aus 1.2 --
	also womit jeder Auftrag gerade multipliziert wird. Die Formel kommt aus
	Balance, der Client rechnet mit exakt derselben wie der Server.

Dazu die Razzia-Wahrscheinlichkeit pro
	Check. In Phase 1 stand die Zeile bewusst nicht hier, weil es die Razzia
	noch nicht gab; seit Phase 2 beschreibt sie ein Ereignis, das wirklich
	eintritt.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Balance"))

local Theme = require(script.Parent:WaitForChild("Theme"))

local HeatBar = {}

local started = false
local heat = 0

local fill: Frame
local valueLabel: TextLabel
local premiumLabel: TextLabel
local riskLabel: TextLabel

function HeatBar.Start(screenGui: ScreenGui)
	if started then
		return
	end
	started = true

	local panel = Theme.New("Frame", {
		Name = "Heat",
		Position = UDim2.fromOffset(16, 124),
		Size = UDim2.fromOffset(260, 78),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
	}, screenGui) :: Frame
	Theme.Corner(panel, 10)
	Theme.Stroke(panel, Theme.Line, 1, 0.3)
	Theme.Padding(panel, 12)

	Theme.Label({
		Size = UDim2.new(1, -70, 0, 14),
		Text = "HEAT",
		TextSize = 11,
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.TextDim,
	}, panel)

	valueLabel = Theme.Label({
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(70, 14),
		Text = "0 / 100",
		TextSize = 12,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, panel)

	local track = Theme.New("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 12),
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
	}, panel)
	Theme.Corner(track, 6)

	fill = Theme.New("Frame", {
		Name = "Fill",
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Theme.HeatLow,
		BorderSizePixel = 0,
	}, track) :: Frame
	Theme.Corner(fill, 6)

	premiumLabel = Theme.Label({
		Name = "Premium",
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 0, 15),
		Text = "",
		TextSize = 13,
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.Cash,
	}, panel)

	riskLabel = Theme.Label({
		Name = "Risk",
		Position = UDim2.fromOffset(0, 51),
		Size = UDim2.new(1, 0, 0, 14),
		Text = "",
		TextSize = 12,
		TextColor3 = Theme.TextDim,
	}, panel)

	HeatBar.SetHeat(0)
end

function HeatBar.SetHeat(value: number)
	if not started then
		return
	end

	heat = math.clamp(value or 0, Balance.Heat.Min, Balance.Heat.Max)

	local t = heat / Balance.Heat.Max
	fill.Size = UDim2.new(t, 0, 1, 0)
	fill.BackgroundColor3 = Theme.HeatColor(t)

	valueLabel.Text = string.format("%d / %d", math.floor(heat + 0.5), Balance.Heat.Max)
	valueLabel.TextColor3 = Theme.HeatColor(t)

	premiumLabel.Text = string.format("Auftraege zahlen x%.2f", Balance.RiskPremium(heat))

	local chance = Balance.RaidChance(heat) * 100
	riskLabel.Text = string.format("Razzia-Risiko %.1f %% pro Check", chance)
	riskLabel.TextColor3 = if heat >= Balance.Heat.AmbientTenseUntil then Theme.HeatColor(t) else Theme.TextDim
end

return HeatBar
