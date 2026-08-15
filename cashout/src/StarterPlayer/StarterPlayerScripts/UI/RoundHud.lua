--[[
	RoundHud.lua

	Die beiden Zahlen, um die es geht (Cash und Banked), der Fortschritts-
	balken der laufenden Taetigkeit, kurze Meldungen und der Razzia-Blitz.

	SetRoundTime() ist bereits fertig, wird in Phase 1 nur von niemandem
	aufgerufen -- der Timer bleibt bis dahin ausgeblendet.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared:WaitForChild("Assets"))
local Balance = require(Shared:WaitForChild("Balance"))

local Theme = require(script.Parent:WaitForChild("Theme"))

local RoundHud = {}

local started = false
local cashLabel: TextLabel
local bankedLabel: TextLabel
local timerLabel: TextLabel
local activityFrame: Frame
local activityLabel: TextLabel
local activityFill: Frame
local activityCountdown: TextLabel
local toastList: Frame
local flash: Frame

local currentActivity: any = nil

local KIND_COLOR = {
	good = Theme.Banked,
	banked = Theme.Banked,
	bad = Theme.Bad,
	warn = Theme.Warn,
	info = Theme.Cool,
}

local KIND_SOUND = {
	good = "DealComplete",
	banked = "DepositComplete",
	-- "bad" bekommt bewusst nicht die Sirene: die spielt FlashRaid, sonst
	-- kaeme sie bei einer Razzia doppelt.
	bad = "Warning",
	warn = "Warning",
}

--[[
	Spielt ein Asset nur, wenn in Assets.lua eine Id hinterlegt ist.
	Solange dort "" steht, passiert hier nichts -- kein Fehler, kein Rauschen.
]]
local function playSound(key: string)
	local assetId = Assets.Sounds[key]
	if not assetId or assetId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = assetId
	sound.Parent = SoundService
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	sound:Play()
end

-- ------------------------------------------------------------------ Aufbau --

local function buildMoneyPanel(parent: Instance)
	local panel = Theme.New("Frame", {
		Name = "Money",
		AnchorPoint = Vector2.new(0, 0),
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
		Name = "CashCaption",
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
		Name = "BankedCaption",
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

local function buildTimer(parent: Instance)
	timerLabel = Theme.Label({
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(160, 34),
		Text = "--:--",
		TextSize = 28,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
	}, parent)
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
		Name = "Label",
		Size = UDim2.new(1, -70, 0, 16),
		Text = "",
		TextSize = 14,
		Font = Enum.Font.GothamBold,
	}, activityFrame)

	activityCountdown = Theme.Label({
		Name = "Countdown",
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
		BackgroundColor3 = Theme.Cool,
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

local function buildFlash(parent: Instance)
	flash = Theme.New("Frame", {
		Name = "RaidFlash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Bad,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 20,
		Visible = false,
	}, parent) :: Frame
end

-- --------------------------------------------------------------- Fortschritt --

local function updateActivity()
	if not currentActivity then
		return
	end

	local elapsed = workspace:GetServerTimeNow() - currentActivity.startedAt
	local duration = math.max(currentActivity.duration, 0.001)
	local progress = math.clamp(elapsed / duration, 0, 1)

	activityFill.Size = UDim2.new(progress, 0, 1, 0)
	activityCountdown.Text = string.format("%.1f s", math.max(duration - elapsed, 0))
end

-- ------------------------------------------------------------------- Public --

function RoundHud.Start(screenGui: ScreenGui)
	if started then
		return
	end
	started = true

	buildMoneyPanel(screenGui)
	buildTimer(screenGui)
	buildActivityBar(screenGui)
	buildToasts(screenGui)
	buildFlash(screenGui)

	RunService.Heartbeat:Connect(updateActivity)
end

function RoundHud.SetState(state)
	if not started or typeof(state) ~= "table" then
		return
	end
	cashLabel.Text = string.format("%d", state.cash or 0)
	bankedLabel.Text = string.format("%d", state.banked or 0)
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
	activityFill.BackgroundColor3 = if activity.kind == "stun"
		then Theme.Bad
		elseif activity.kind == "deposit" then Theme.Banked
		else Theme.Cool

	local prefix = if activity.kind == "deposit"
		then "EINZAHLUNG"
		elseif activity.kind == "stun" then "FESTGESETZT"
		else "DEAL"
	activityLabel.Text = prefix .. "  ·  " .. tostring(activity.label)

	activityFill.Size = UDim2.new(0, 0, 1, 0)
	updateActivity()
end

function RoundHud.Notify(kind: string, text: string)
	if not started then
		return
	end

	local color = KIND_COLOR[kind] or Theme.Cool
	if KIND_SOUND[kind] then
		playSound(KIND_SOUND[kind])
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
		Name = "Accent",
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

function RoundHud.FlashRaid()
	if not started then
		return
	end
	playSound("RaidSiren")
	flash.Visible = true
	flash.BackgroundTransparency = 0.45
	local tween = TweenService:Create(flash, TweenInfo.new(0.7), { BackgroundTransparency = 1 })
	tween.Completed:Connect(function()
		flash.Visible = false
	end)
	tween:Play()
end

--[[
	Phase 2: Rundenrestzeit in Sekunden. Blendet den Timer beim ersten Aufruf ein.
]]
function RoundHud.SetRoundTime(seconds: number)
	if not started then
		return
	end
	local clamped = math.max(math.floor(seconds), 0)
	timerLabel.Visible = true
	timerLabel.Text = string.format("%d:%02d", clamped // 60, clamped % 60)
	timerLabel.TextColor3 = if clamped <= 30 then Theme.Bad else Theme.Text
end

return RoundHud
