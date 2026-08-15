--[[
	HeatBar.lua

	Heat als Leiste, dazu die tatsaechliche Razzia-Wahrscheinlichkeit pro
	Check. Die Zahl kommt aus Balance.RaidChance -- der Client rechnet mit
	genau derselben Formel wie der Server, nur zur Anzeige.

	Ab Balance.Heat.DangerAt pulst der Rahmen. Ab Balance.Heat.WarnAt wechselt
	der Hinweistext.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Balance"))

local Theme = require(script.Parent:WaitForChild("Theme"))

local HeatBar = {}

local started = false
local heat = 0

local fill: Frame
local valueLabel: TextLabel
local riskLabel: TextLabel
local stroke: UIStroke

local function updatePulse()
	if heat < Balance.Heat.DangerAt then
		stroke.Transparency = 0.3
		return
	end
	-- 0 .. 0.55 im Sekundentakt: sichtbar, aber nicht zappelig.
	stroke.Transparency = 0.275 + math.sin(os.clock() * 6) * 0.275
end

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
	Theme.Padding(panel, 12)

	stroke = Theme.New("UIStroke", {
		Color = Theme.HeatHigh,
		Thickness = 1.5,
		Transparency = 0.3,
	}, panel) :: UIStroke

	Theme.Label({
		Name = "Caption",
		Size = UDim2.new(1, -60, 0, 14),
		Text = "HEAT",
		TextSize = 11,
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.TextDim,
	}, panel)

	valueLabel = Theme.Label({
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(60, 14),
		Text = "0",
		TextSize = 12,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, panel)

	local track = Theme.New("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(0, 22),
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

	riskLabel = Theme.Label({
		Name = "Risk",
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 14),
		Text = "",
		TextSize = 12,
		TextColor3 = Theme.TextDim,
	}, panel)

	HeatBar.SetHeat(0)
	RunService.Heartbeat:Connect(updatePulse)
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

	local chance = Balance.RaidChance(heat) * 100
	local suffix = if heat >= Balance.Heat.DangerAt
		then "  ·  Zeit einzuzahlen"
		elseif heat >= Balance.Heat.WarnAt then "  ·  wird eng"
		else ""

	riskLabel.Text = string.format("Razzia-Risiko %.1f %% pro Check%s", chance, suffix)
	riskLabel.TextColor3 = if heat >= Balance.Heat.WarnAt then Theme.HeatColor(t) else Theme.TextDim
end

return HeatBar
