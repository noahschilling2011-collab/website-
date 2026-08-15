--[[
	RoundEndBoard.lua

	Endstand-Tafel nach 3.3: Banked aller Spieler, darunter die drei Zeilen
	hoechster Einzelauftrag / meiste Abfaenge / knappste Flucht.

	Phase 1 kann nur die erste der drei Zeilen fuellen -- Abfaenge kommen mit
	Phase 3, die Flucht mit Phase 2. Die beiden anderen Zeilen stehen deshalb
	mit einem Strich da statt zu fehlen: die Tafel behaelt ihre Form, und man
	sieht, was noch aussteht.

	Die 5 s Zeitlupe auf den Sieger sind Phase 4.
]]

local Players = game:GetService("Players")

local Theme = require(script.Parent:WaitForChild("Theme"))

local RoundEndBoard = {}

local player = Players.LocalPlayer

local started = false
local root: Frame
local list: Frame
local highlightList: Frame

local ROW_HEIGHT = 30

-- ------------------------------------------------------------------ Aufbau --

local function build(screenGui: ScreenGui)
	root = Theme.New("Frame", {
		Name = "RoundEndBoard",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 8,
	}, screenGui) :: Frame

	local panel = Theme.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 480),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		ZIndex = 9,
	}, root)
	Theme.Corner(panel, 14)
	Theme.Stroke(panel, Theme.Banked, 1.5, 0.4)
	Theme.Padding(panel, 18)

	Theme.Label({
		Size = UDim2.new(1, 0, 0, 24),
		Text = "ENDSTAND",
		TextSize = 18,
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.Banked,
	}, panel)

	Theme.Label({
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 16),
		Text = "Nur eingezahltes Geld zaehlt.",
		TextSize = 12,
		TextColor3 = Theme.TextDim,
	}, panel)

	list = Theme.New("Frame", {
		Name = "Standings",
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 0, 280),
		BackgroundTransparency = 1,
		ZIndex = 9,
	}, panel) :: Frame

	Theme.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	}, list)

	Theme.New("Frame", {
		Position = UDim2.fromOffset(0, 340),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Theme.Line,
		BorderSizePixel = 0,
		ZIndex = 9,
	}, panel)

	highlightList = Theme.New("Frame", {
		Name = "Highlights",
		Position = UDim2.fromOffset(0, 352),
		Size = UDim2.new(1, 0, 0, 90),
		BackgroundTransparency = 1,
		ZIndex = 9,
	}, panel) :: Frame

	Theme.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	}, highlightList)
end

local function clear(container: Frame)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function addStandingRow(index: number, entry)
	local isSelf = entry.userId == player.UserId
	local isWinner = index == 1

	local rowFrame = Theme.New("Frame", {
		Name = "Row" .. index,
		LayoutOrder = index,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundColor3 = if isSelf then Theme.PanelRaised else Theme.Panel,
		BackgroundTransparency = if isSelf then 0 else 1,
		BorderSizePixel = 0,
		ZIndex = 10,
	}, list) :: Frame
	Theme.Corner(rowFrame, 6)

	local nameColor = if isWinner then Theme.Banked else Theme.Text

	Theme.Label({
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.fromOffset(28, ROW_HEIGHT),
		Text = tostring(index),
		TextSize = 13,
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.TextDim,
		ZIndex = 10,
	}, rowFrame)

	Theme.Label({
		Position = UDim2.fromOffset(36, 0),
		Size = UDim2.new(1, -150, 0, ROW_HEIGHT),
		Text = entry.name,
		TextSize = 14,
		Font = if isWinner then Enum.Font.GothamBold else Enum.Font.Gotham,
		TextColor3 = nameColor,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 10,
	}, rowFrame)

	Theme.Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 0),
		Size = UDim2.fromOffset(110, ROW_HEIGHT),
		Text = string.format("%d", entry.banked),
		TextSize = 15,
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.Banked,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 10,
	}, rowFrame)
end

--[[
	who = nil bedeutet: diese Auswertung gibt es in dieser Phase noch nicht.
	Dann steht ein Strich da, keine erfundene Null.
]]
local function addHighlightRow(order: number, caption: string, entry, format: (number) -> string)
	local rowFrame = Theme.New("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		ZIndex = 10,
	}, highlightList) :: Frame

	Theme.Label({
		Size = UDim2.new(0.55, 0, 1, 0),
		Text = caption,
		TextSize = 12,
		TextColor3 = Theme.TextDim,
		ZIndex = 10,
	}, rowFrame)

	local hasValue = entry ~= nil and entry.who ~= nil
	Theme.Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.45, 0, 1, 0),
		Text = if hasValue then string.format("%s · %s", entry.who, format(entry.value)) else "—",
		TextSize = 13,
		Font = Enum.Font.GothamBold,
		TextColor3 = if hasValue then Theme.Text else Theme.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 10,
	}, rowFrame)
end

-- ------------------------------------------------------------------- Public --

function RoundEndBoard.Start(screenGui: ScreenGui)
	if started then
		return
	end
	started = true
	build(screenGui)
end

function RoundEndBoard.Show(result)
	if not started or typeof(result) ~= "table" then
		return
	end

	clear(list)
	clear(highlightList)

	local standings = result.standings or {}
	local maxRows = math.floor(list.AbsoluteSize.Y / (ROW_HEIGHT + 4))
	for index, entry in ipairs(standings) do
		-- AbsoluteSize ist beim ersten Frame noch 0; dann lieber alles zeigen
		-- als nichts.
		if maxRows <= 0 or index <= maxRows then
			addStandingRow(index, entry)
		end
	end

	local highlights = result.highlights or {}
	addHighlightRow(1, "Hoechster Einzelauftrag", highlights.bestOrder, function(value)
		return string.format("%d", value)
	end)
	addHighlightRow(2, "Meiste Abfaenge", highlights.mostIntercepts, function(value)
		return string.format("%d", value)
	end)
	addHighlightRow(3, "Knappste Flucht", highlights.narrowestEscape, function(value)
		return string.format("%d Studs", value)
	end)

	root.Visible = true
end

function RoundEndBoard.Hide()
	if not started then
		return
	end
	root.Visible = false
end

return RoundEndBoard
