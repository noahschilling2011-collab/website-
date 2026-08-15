--[[
	OrderPanel.lua

	Die drei Auftragskarten eines Terminals. Alles, was hier steht, kommt vom
	Server -- der Client rechnet keine Betraege aus und schickt beim Klick nur
	die Terminal-Id und den Index 1..3.

	Auf der Karte steht die Entfernung des Uebergabepunkts, nicht mehr eine
	Wartezeit. Das ist der Preis der Stufe.

	Das Panel schliesst sich selbst, wenn der Spieler sich vom Terminal
	entfernt. Der Server prueft die Distanz sowieso noch einmal; das hier ist
	nur, damit kein totes Fenster offen steht.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Balance"))

local Theme = require(script.Parent:WaitForChild("Theme"))

local OrderPanel = {}

local player = Players.LocalPlayer

local started = false
local screen: ScreenGui
local root: Frame
local titleLabel: TextLabel
local row: Frame

local openTerminalId: string? = nil
local terminalPosition: Vector3? = nil
local chooseCallback: ((string, number) -> ())? = nil

-- ------------------------------------------------------------------- Karten --

local function clearCards()
	for _, child in ipairs(row:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function buildCard(offer, index: number)
	local tierColor = Theme.TierColor(offer.tierId)

	local card = Theme.New("TextButton", {
		Name = "Card" .. index,
		LayoutOrder = index,
		Size = UDim2.fromOffset(200, 244),
		BackgroundColor3 = Theme.PanelRaised,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
	}, row) :: TextButton
	Theme.Corner(card, 10)
	Theme.Stroke(card, tierColor, 1.5, 0.45)

	local chip = Theme.New("Frame", {
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(74, 20),
		BackgroundColor3 = tierColor,
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
	}, card)
	Theme.Corner(chip, 6)

	Theme.Label({
		Size = UDim2.fromScale(1, 1),
		Text = string.upper(offer.tierLabel),
		TextSize = 11,
		Font = Enum.Font.GothamBold,
		TextColor3 = tierColor,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, chip)

	Theme.Label({
		Position = UDim2.fromOffset(12, 40),
		Size = UDim2.new(1, -24, 0, 38),
		Text = offer.name,
		TextSize = 16,
		Font = Enum.Font.GothamBold,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, card)

	Theme.Label({
		Position = UDim2.fromOffset(12, 78),
		Size = UDim2.new(1, -24, 0, 34),
		Text = offer.blurb,
		TextSize = 12,
		TextColor3 = Theme.TextDim,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, card)

	Theme.New("Frame", {
		Position = UDim2.fromOffset(12, 118),
		Size = UDim2.new(1, -24, 0, 1),
		BackgroundColor3 = Theme.Line,
		BorderSizePixel = 0,
	}, card)

	local rows = {
		{ "Basis", string.format("%d – %d", offer.minPayout, offer.maxPayout), Theme.Cash },
		{ "Heat", if offer.heat > 0 then string.format("+%d", offer.heat) else "keine", Theme.HeatLow },
		{ "Weg", string.format("%d – %d", offer.minDistance, offer.maxDistance), Theme.Delivery },
	}

	for rowIndex, entry in ipairs(rows) do
		local y = 130 + (rowIndex - 1) * 22

		Theme.Label({
			Position = UDim2.fromOffset(12, y),
			Size = UDim2.new(0.5, -12, 0, 18),
			Text = entry[1],
			TextSize = 12,
			TextColor3 = Theme.TextDim,
		}, card)

		Theme.Label({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, y),
			Size = UDim2.new(0.5, -12, 0, 18),
			Text = entry[2],
			TextSize = 13,
			Font = Enum.Font.GothamBold,
			TextColor3 = entry[3],
			TextXAlignment = Enum.TextXAlignment.Right,
		}, card)
	end

	local take = Theme.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -24, 0, 32),
		BackgroundColor3 = tierColor,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
	}, card)
	Theme.Corner(take, 8)

	Theme.Label({
		Size = UDim2.fromScale(1, 1),
		Text = "ANNEHMEN",
		TextSize = 13,
		Font = Enum.Font.GothamBold,
		TextColor3 = tierColor,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, take)

	card.MouseEnter:Connect(function()
		take.BackgroundTransparency = 0.6
	end)
	card.MouseLeave:Connect(function()
		take.BackgroundTransparency = 0.82
	end)

	card.Activated:Connect(function()
		local terminalId = openTerminalId
		if terminalId and chooseCallback then
			OrderPanel.FlyOut(card)
			chooseCallback(terminalId, index)
		end
	end)
end

-- ------------------------------------------------------------------ Aufbau --

local function build(screenGui: ScreenGui)
	root = Theme.New("Frame", {
		Name = "OrderPanel",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
	}, screenGui) :: Frame

	local panel = Theme.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(684, 352),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, root)
	Theme.Corner(panel, 14)
	Theme.Stroke(panel, Theme.Line, 1, 0.2)
	Theme.Padding(panel, 16)

	titleLabel = Theme.Label({
		Size = UDim2.new(1, -40, 0, 22),
		Text = "TERMINAL",
		TextSize = 16,
		Font = Enum.Font.GothamBold,
	}, panel)

	local close = Theme.New("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(28, 24),
		BackgroundTransparency = 1,
		Text = "×",
		TextSize = 24,
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.TextDim,
	}, panel) :: TextButton
	close.Activated:Connect(function()
		OrderPanel.Close()
	end)

	row = Theme.New("Frame", {
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 244),
		BackgroundTransparency = 1,
	}, panel) :: Frame

	Theme.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 12),
	}, row)

	Theme.Label({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 18),
		Text = "Annahme dauert "
			.. Balance.Orders.AcceptSeconds
			.. " s am Terminal. Danach zum Uebergabepunkt laufen — Heat kuehlt unterwegs nicht ab.",
		TextSize = 12,
		TextColor3 = Theme.TextDim,
	}, panel)
end

--[[
	Dokument 5: die angenommene Karte fliegt zum Bildschirmrand und wird dort
	zum Marker. Verbindet Auswahl und Ziel sichtbar miteinander -- den Marker
	selbst uebernimmt danach Feel.lua.
]]
function OrderPanel.FlyOut(card: TextButton)
	local flying = card:Clone()
	flying.Name = "FlyingCard"
	-- An die ScreenGui, nicht ans Panel: das Panel geht im selben Moment zu,
	-- und ein Kind eines unsichtbaren Frames fliegt unsichtbar.
	flying.Parent = screen
	flying.ZIndex = 20
	flying.Position = UDim2.fromOffset(card.AbsolutePosition.X, card.AbsolutePosition.Y)
	flying.Size = UDim2.fromOffset(card.AbsoluteSize.X, card.AbsoluteSize.Y)
	flying.AnchorPoint = Vector2.new(0, 0)

	local info = TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
	TweenService:Create(flying, info, {
		Position = UDim2.new(0, 24, 0.5, 0),
		Size = UDim2.fromOffset(24, 30),
		BackgroundTransparency = 1,
	}):Play()

	task.delay(0.45, function()
		flying:Destroy()
	end)
end

-- ------------------------------------------------------------- Distanzwache --

local function watchDistance()
	if not openTerminalId then
		return
	end

	-- Ohne Terminal-Position laesst sich nichts pruefen: dann zumachen, statt
	-- ein Panel offen stehen zu lassen, das nie wieder von allein schliesst.
	if not terminalPosition then
		OrderPanel.Close()
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		OrderPanel.Close()
		return
	end

	-- Gegen das Terminal messen, nicht gegen die Stelle, an der der Spieler
	-- beim Oeffnen stand. Sonst schliesst sich das Panel beim Umrunden des
	-- Terminals, obwohl der Server die Annahme noch erlauben wuerde.
	if (rootPart.Position - terminalPosition).Magnitude > Balance.Orders.InteractRadius then
		OrderPanel.Close()
	end
end

-- ------------------------------------------------------------------- Public --

function OrderPanel.Start(screenGui: ScreenGui, onChoose: (string, number) -> ())
	if started then
		return
	end
	started = true
	chooseCallback = onChoose
	screen = screenGui

	build(screenGui)
	RunService.Heartbeat:Connect(watchDistance)
end

function OrderPanel.Open(terminalId: string, offers, position: Vector3?)
	if not started or typeof(offers) ~= "table" then
		return
	end

	openTerminalId = terminalId
	terminalPosition = if typeof(position) == "Vector3" then position else nil

	-- Klammern, damit nur der String und nicht der Ersetzungszaehler ankommt.
	local shortId = (string.gsub(terminalId, "^T", ""))
	titleLabel.Text = string.format("TERMINAL %s  ·  drei Auftraege", shortId)

	clearCards()
	for index, offer in ipairs(offers) do
		buildCard(offer, index)
	end

	root.Visible = true
end

function OrderPanel.Close()
	if not started then
		return
	end
	openTerminalId = nil
	terminalPosition = nil
	root.Visible = false
	clearCards()
end

function OrderPanel.IsOpen(): boolean
	return started and root.Visible
end

return OrderPanel
