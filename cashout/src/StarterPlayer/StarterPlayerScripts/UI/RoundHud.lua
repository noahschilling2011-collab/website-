--[[
	RoundHud.lua

	Rundentimer, die beiden Zahlen (Cash und Banked), der getragene Auftrag mit
	Restentfernung, der Fortschrittsbalken der laufenden Interaktion und kurze
	Meldungen.

	Der Countdown laeuft hier lokal weiter -- der Server schickt nur bei
	Phasenwechseln und alle paar Sekunden einen Zeitstempel.

	Seit Phase 2 dazu der rote Rand des Fluchtfensters mit ablesbarer Restzeit
	(Dokument 1.4). Rot taucht nur hier auf -- 4.2 reserviert es ausschliesslich
	fuer Gefahr.

	Kamera-Kick, Herzschlag, Vignette und Einzahl-Beam sind Phase 4 und stehen
	bewusst noch nicht hier.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Balance"))
local SoundCatalog = require(Shared:WaitForChild("SoundCatalog"))

local Theme = require(script.Parent:WaitForChild("Theme"))

local RoundHud = {}

local player = Players.LocalPlayer

local started = false
local cashLabel: TextLabel
local bankedLabel: TextLabel
local timerLabel: TextLabel
local phaseLabel: TextLabel
local rushLabel: TextLabel
local orderFrame: Frame
local orderTitle: TextLabel
local orderDetail: TextLabel
local activityFrame: Frame
local activityLabel: TextLabel
local activityFill: Frame
local activityCountdown: TextLabel
local toastList: Frame
local raidFrame: Frame
local raidLabel: TextLabel

local currentActivity: any = nil
local currentRaid: any = nil
local currentRound: any = nil
local currentOrder: any = nil
local currentPoint: BasePart? = nil
local pointMarker: BillboardGui? = nil

local KIND_COLOR = {
	good = Theme.Cash,
	banked = Theme.Banked,
	info = Theme.Delivery,
	-- Kein Rot: Rot ist laut 4.2 ausschliesslich Gefahr.
	warn = Theme.Muted,
	bad = Theme.Muted,
}

local KIND_SOUND = {
	good = "OrderDelivered",
	banked = "DepositComplete",
	info = "OrderAccepted",
	warn = "ActionRefused",
	bad = "ActionRefused",
}

-- ------------------------------------------------------------------ Aufbau --

local function buildTopBar(parent: Instance)
	local panel = Theme.New("Frame", {
		Name = "Round",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(220, 68),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
	}, parent)
	Theme.Corner(panel, 10)
	Theme.Stroke(panel, Theme.Line, 1, 0.3)

	timerLabel = Theme.Label({
		Name = "Timer",
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 34),
		Text = "--:--",
		TextSize = 30,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, panel)

	phaseLabel = Theme.Label({
		Name = "Phase",
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 14),
		Text = "warten",
		TextSize = 11,
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, panel)

	rushLabel = Theme.Label({
		Name = "Rush",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 74),
		Size = UDim2.fromOffset(220, 20),
		Text = "",
		TextSize = 14,
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.Banked,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
	}, parent)
end

local function buildMoneyPanel(parent: Instance)
	local panel = Theme.New("Frame", {
		Name = "Money",
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(260, 96),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
	}, parent)
	Theme.Corner(panel, 10)
	Theme.Stroke(panel, Theme.Line, 1, 0.3)
	Theme.Padding(panel, 12)

	Theme.Label({
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 14),
		Text = "CASH  (angreifbar)",
		TextSize = 11,
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.TextDim,
	}, panel)

	cashLabel = Theme.Label({
		Name = "Cash",
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 26),
		Text = "0",
		TextSize = 24,
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.Cash,
	}, panel)

	Theme.Label({
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 0, 14),
		Text = "BANKED  (zaehlt)",
		TextSize = 11,
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.TextDim,
	}, panel)

	bankedLabel = Theme.Label({
		Name = "Banked",
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 0, 26),
		Text = "0",
		TextSize = 24,
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.Banked,
	}, panel)
end

local function buildOrderPanel(parent: Instance)
	orderFrame = Theme.New("Frame", {
		Name = "Order",
		Position = UDim2.fromOffset(16, 214),
		Size = UDim2.fromOffset(260, 66),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Visible = false,
	}, parent) :: Frame
	Theme.Corner(orderFrame, 10)
	Theme.Stroke(orderFrame, Theme.Delivery, 1.5, 0.4)
	Theme.Padding(orderFrame, 12)

	Theme.Label({
		Size = UDim2.new(1, 0, 0, 14),
		Text = "AUFTRAG UNTERWEGS",
		TextSize = 11,
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.Delivery,
	}, orderFrame)

	orderTitle = Theme.Label({
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, 18),
		Text = "",
		TextSize = 15,
		Font = Enum.Font.GothamBold,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, orderFrame)

	orderDetail = Theme.Label({
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 16),
		Text = "",
		TextSize = 12,
		TextColor3 = Theme.TextDim,
	}, orderFrame)
end

local function buildActivityBar(parent: Instance)
	activityFrame = Theme.New("Frame", {
		Name = "Activity",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(420, 58),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Visible = false,
	}, parent) :: Frame
	Theme.Corner(activityFrame, 10)
	Theme.Stroke(activityFrame, Theme.Line, 1, 0.3)
	Theme.Padding(activityFrame, 12)

	activityLabel = Theme.Label({
		Size = UDim2.new(1, -70, 0, 16),
		Text = "",
		TextSize = 14,
		Font = Enum.Font.GothamBold,
	}, activityFrame)

	activityCountdown = Theme.Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(70, 16),
		Text = "",
		TextSize = 14,
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, activityFrame)

	local track = Theme.New("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 10),
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
	}, activityFrame)
	Theme.Corner(track, 5)

	activityFill = Theme.New("Frame", {
		Name = "Fill",
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Theme.Delivery,
		BorderSizePixel = 0,
	}, track) :: Frame
	Theme.Corner(activityFill, 5)
end

local function buildToasts(parent: Instance)
	toastList = Theme.New("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(320, 240),
		BackgroundTransparency = 1,
	}, parent) :: Frame

	Theme.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	}, toastList)
end

--[[
	Roter Rand waehrend des Fluchtfensters. Vier Balken statt eines gefuellten
	Frames, damit die Mitte des Bildschirms frei bleibt -- man muss beim Rennen
	sehen, wohin.
]]
local function buildRaidBorder(parent: Instance)
	raidFrame = Theme.New("Frame", {
		Name = "RaidBorder",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 15,
	}, parent) :: Frame

	local thickness = 14
	local edges = {
		{ UDim2.fromScale(0, 0), UDim2.new(1, 0, 0, thickness) },
		{ UDim2.new(0, 0, 1, -thickness), UDim2.new(1, 0, 0, thickness) },
		{ UDim2.fromScale(0, 0), UDim2.new(0, thickness, 1, 0) },
		{ UDim2.new(1, -thickness, 0, 0), UDim2.new(0, thickness, 1, 0) },
	}
	for index, edge in ipairs(edges) do
		Theme.New("Frame", {
			Name = "Edge" .. index,
			Position = edge[1],
			Size = edge[2],
			BackgroundColor3 = Theme.Danger,
			BorderSizePixel = 0,
			ZIndex = 15,
		}, raidFrame)
	end

	raidLabel = Theme.Label({
		Name = "Countdown",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 110),
		Size = UDim2.fromOffset(420, 30),
		Text = "",
		TextSize = 22,
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.Danger,
		TextStrokeTransparency = 0.5,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 16,
	}, raidFrame)
end

-- ------------------------------------------------------------ Marker am Ziel --

--[[
	Cyan-Schild am eigenen Uebergabepunkt. Bewusst clientseitig: der Punkt-Part
	steht fuer alle in der Welt, das Cyan-Schild sieht nur der Besitzer.
	Der Pfeil am Bildschirmrand ist Phase 4.
]]
local function setPointMarker(point: BasePart?)
	if pointMarker then
		pointMarker:Destroy()
		pointMarker = nil
	end
	currentPoint = point
	if not point then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CashoutOwnDelivery"
	billboard.Size = UDim2.fromOffset(180, 40)
	billboard.StudsOffset = Vector3.new(0, 20, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = point
	billboard.Parent = point

	Theme.Label({
		Size = UDim2.fromScale(1, 1),
		Text = "DEIN ZIEL",
		TextSize = 20,
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.Delivery,
		TextStrokeTransparency = 0.4,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, billboard)

	pointMarker = billboard
end

-- --------------------------------------------------------------- Pro Frame --

local function updateActivity()
	if not currentActivity then
		return
	end

	local elapsed = workspace:GetServerTimeNow() - currentActivity.startedAt
	local duration = math.max(currentActivity.duration, 0.001)
	activityFill.Size = UDim2.new(math.clamp(elapsed / duration, 0, 1), 0, 1, 0)
	activityCountdown.Text = string.format("%.1f s", math.max(duration - elapsed, 0))
end

local function updateRound()
	if not currentRound then
		return
	end

	local remaining = currentRound.endsAt - workspace:GetServerTimeNow()

	if currentRound.phase == "waiting" then
		timerLabel.Text = "--:--"
		timerLabel.TextColor3 = Theme.TextDim
		phaseLabel.Text = "warten auf Spieler"
		rushLabel.Visible = false
		return
	end

	timerLabel.Text = Theme.Clock(remaining)

	if currentRound.phase == "intermission" then
		timerLabel.TextColor3 = Theme.TextDim
		phaseLabel.Text = "Pause"
		rushLabel.Visible = false
		return
	end

	phaseLabel.Text = "Runde laeuft"
	local isRush = remaining <= currentRound.finalRushSeconds
	timerLabel.TextColor3 = if isRush then Theme.Banked else Theme.Text
	rushLabel.Visible = isRush
	if isRush then
		rushLabel.Text = string.format("ENDSPURT  ·  alle Payouts x%d", currentRound.finalRushMultiplier)
	end
end

local function updateRaid()
	if not currentRaid then
		return
	end

	local remaining = currentRaid.startedAt + currentRaid.duration - workspace:GetServerTimeNow()
	if remaining <= 0 then
		raidLabel.Text = "RAZZIA"
		return
	end
	raidLabel.Text = string.format("RAZZIA — %.1f s — %d Studs raus", remaining, currentRaid.radius)
end

local function updateOrderDistance()
	if not currentOrder or not orderFrame.Visible then
		return
	end

	local base = string.format(
		"%s · Basis %d · +%d Heat",
		currentOrder.tierLabel,
		currentOrder.basePayout,
		currentOrder.heatGain
	)

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if currentPoint and currentPoint.Parent and root and root:IsA("BasePart") then
		local flat = Vector3.new(
			currentPoint.Position.X - root.Position.X,
			0,
			currentPoint.Position.Z - root.Position.Z
		)
		orderDetail.Text = string.format("%s · noch %d Studs", base, math.floor(flat.Magnitude + 0.5))
	else
		orderDetail.Text = base
	end
end

-- ------------------------------------------------------------------- Public --

function RoundHud.Start(screenGui: ScreenGui)
	if started then
		return
	end
	started = true

	buildTopBar(screenGui)
	buildMoneyPanel(screenGui)
	buildOrderPanel(screenGui)
	buildActivityBar(screenGui)
	buildToasts(screenGui)
	buildRaidBorder(screenGui)

	RunService.Heartbeat:Connect(function()
		updateActivity()
		updateRound()
		updateRaid()
		updateOrderDistance()
	end)
end

function RoundHud.SetState(state)
	if not started or typeof(state) ~= "table" then
		return
	end
	cashLabel.Text = string.format("%d", state.cash or 0)
	bankedLabel.Text = string.format("%d", state.banked or 0)
end

function RoundHud.SetRound(state)
	if not started or typeof(state) ~= "table" then
		return
	end
	currentRound = state
	updateRound()
end

function RoundHud.SetOrder(order, point: BasePart?)
	if not started then
		return
	end

	currentOrder = order
	setPointMarker(point)

	if not order then
		orderFrame.Visible = false
		return
	end

	orderFrame.Visible = true
	orderTitle.Text = order.name
	local stroke = orderFrame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Theme.TierColor(order.tierId)
	end
	updateOrderDistance()
end

function RoundHud.SetActivity(activity)
	if not started then
		return
	end

	currentActivity = activity
	if not activity then
		activityFrame.Visible = false
		return
	end

	activityFrame.Visible = true
	activityFill.BackgroundColor3 = if activity.kind == "deposit"
		then Theme.Banked
		elseif activity.kind == "deliver" then Theme.Delivery
		else Theme.Muted

	local prefix = if activity.kind == "deposit"
		then "EINZAHLUNG"
		elseif activity.kind == "deliver" then "UEBERGABE"
		elseif activity.kind == "accept" then "ANNAHME"
		else string.upper(tostring(activity.kind))
	activityLabel.Text = prefix .. "  ·  " .. tostring(activity.label)

	activityFill.Size = UDim2.new(0, 0, 1, 0)
	updateActivity()
end

--[[
	Fluchtfenster an oder aus. info = nil beendet es.
]]
function RoundHud.SetRaid(info)
	if not started then
		return
	end
	currentRaid = info
	raidFrame.Visible = info ~= nil
	if info then
		SoundCatalog.Play("RaidAlarm")
		updateRaid()
	end
end

function RoundHud.Notify(kind: string, text: string)
	if not started then
		return
	end

	local color = KIND_COLOR[kind] or Theme.Muted
	if KIND_SOUND[kind] then
		SoundCatalog.Play(KIND_SOUND[kind])
	end

	local toast = Theme.New("Frame", {
		Name = "Toast",
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
	}, toastList) :: Frame
	Theme.Corner(toast, 8)

	Theme.New("Frame", {
		Size = UDim2.fromOffset(4, 34),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, toast)

	local label = Theme.Label({
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -22, 1, 0),
		Text = text,
		TextSize = 14,
		Font = Enum.Font.GothamBold,
		TextColor3 = color,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, toast)

	task.delay(Balance.Net.NotifyDuration, function()
		if not toast.Parent then
			return
		end
		local info = TweenInfo.new(0.35)
		TweenService:Create(toast, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, info, { TextTransparency = 1 }):Play()
		task.delay(0.4, function()
			toast:Destroy()
		end)
	end)
end

return RoundHud
