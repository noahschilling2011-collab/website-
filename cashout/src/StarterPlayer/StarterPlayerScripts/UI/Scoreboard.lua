--[[
	Scoreboard.lua

	Live-Banked aller Spieler im Server, immer sichtbar (Dokument 2:
	"Sichtbarer Wettbewerb ... immer sichtbar").

	Zeigt nur Banked -- Cash gehoert niemandem, solange es nicht eingezahlt ist,
	und wer wie viel dabei hat, ist genau die Information, die das Spiel
	verschweigt.

	Zuschauer (Late-Join-Sperre aus 3.1) stehen mit drin, aber ausgegraut und
	ohne Zahl: sie spielen diese Runde nicht mit.
]]

local Players = game:GetService("Players")

local Theme = require(script.Parent:WaitForChild("Theme"))

local Scoreboard = {}

local player = Players.LocalPlayer

local started = false
local list: Frame
local emptyLabel: TextLabel

local ROW_HEIGHT = 22
local MAX_ROWS = 12

function Scoreboard.Start(screenGui: ScreenGui)
	if started then
		return
	end
	started = true

	local panel = Theme.New("Frame", {
		Name = "Scoreboard",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(240, 40 + ROW_HEIGHT * MAX_ROWS),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.Y,
	}, screenGui) :: Frame
	Theme.Corner(panel, 10)
	Theme.Stroke(panel, Theme.Line, 1, 0.35)
	Theme.Padding(panel, 10)

	Theme.Label({
		Size = UDim2.new(1, 0, 0, 14),
		Text = "BANKED IM SERVER",
		TextSize = 11,
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.TextDim,
	}, panel)

	list = Theme.New("Frame", {
		Name = "Rows",
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT * MAX_ROWS),
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
	}, panel) :: Frame

	Theme.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
	}, list)

	emptyLabel = Theme.Label({
		Name = "Empty",
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		Text = "niemand da",
		TextSize = 12,
		TextColor3 = Theme.TextDim,
	}, panel)
end

local function clear()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function Scoreboard.Update(entries)
	if not started or typeof(entries) ~= "table" then
		return
	end

	clear()
	emptyLabel.Visible = #entries == 0

	for index, entry in ipairs(entries) do
		if index > MAX_ROWS then
			break
		end

		local isSelf = entry.userId == player.UserId
		local row = Theme.New("Frame", {
			Name = "Row" .. index,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			BackgroundColor3 = Theme.PanelRaised,
			BackgroundTransparency = if isSelf then 0.2 else 1,
			BorderSizePixel = 0,
		}, list) :: Frame
		Theme.Corner(row, 4)

		Theme.Label({
			Position = UDim2.fromOffset(6, 0),
			Size = UDim2.new(1, -80, 1, 0),
			Text = entry.name,
			TextSize = 12,
			Font = if isSelf then Enum.Font.GothamBold else Enum.Font.Gotham,
			TextColor3 = if entry.spectating then Theme.TextDim else Theme.Text,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, row)

		Theme.Label({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 0),
			Size = UDim2.fromOffset(72, ROW_HEIGHT),
			Text = if entry.spectating then "sieht zu" else string.format("%d", entry.banked),
			TextSize = 12,
			Font = Enum.Font.GothamBold,
			TextColor3 = if entry.spectating then Theme.TextDim else Theme.Banked,
			TextXAlignment = Enum.TextXAlignment.Right,
		}, row)
	end
end

return Scoreboard
