--[[
	Feel.lua

	Die kleinen Sachen aus Dokument 5, die den Unterschied zwischen
	"funktioniert" und "macht Spass" ausmachen:

	  - Zahlen-Popup ueber dem Kopf: gruen nach oben bei Gewinn, rot nach unten
	    bei Verlust, 0,6 s, Transparenz auf 1.
	  - Bank-Ring: der 8-Sekunden-Fortschritt als Ring um den Spieler, der sich
	    schliesst. Bei Abbruch springt er nicht auf null, sondern laeuft in
	    0,3 s zurueck.
	  - Pfeil am Bildschirmrand zum eigenen Uebergabepunkt (4.2, Cyan), solange
	    der nicht im Bild ist.

	Alles ohne Bild-Assets: der Ring ist aus einzelnen Segmenten gebaut, der
	Pfeil ist ein gedrehtes Zeichen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Balance"))

local Theme = require(script.Parent:WaitForChild("Theme"))

local Feel = {}

local player = Players.LocalPlayer

local started = false
local screen: ScreenGui
local arrow: TextLabel

local RING_SEGMENTS = 28

local ringBillboard: BillboardGui? = nil
local ringSegments: { Frame } = {}
local ringProgress = 0
local ringTarget = 0
local ringActive = false
local ringStartedAt = 0
local ringDuration = 1

local targetPart: BasePart? = nil

-- ------------------------------------------------------------------ Popup --

--[[
	Zahl ueber dem Kopf. Gewinn steigt gruen, Verlust faellt rot -- Rot ist
	laut 4.2 der Gefahr vorbehalten, und Geld zu verlieren ist genau das.
]]
function Feel.Popup(amount: number)
	if not started or amount == 0 then
		return
	end

	local character = player.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if not head or not head:IsA("BasePart") then
		return
	end

	local gain = amount > 0
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CashoutPopup"
	billboard.Size = UDim2.fromOffset(160, 40)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = head
	billboard.Parent = head

	local label = Theme.Label({
		Size = UDim2.fromScale(1, 1),
		Text = if gain then string.format("+%d", amount) else string.format("%d", amount),
		TextSize = 26,
		Font = Enum.Font.GothamBold,
		TextColor3 = if gain then Theme.Cash else Theme.Danger,
		TextStrokeTransparency = 0.4,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, billboard)

	local rise = if gain then Balance.Feel.PopupRise else -Balance.Feel.PopupRise
	local info = TweenInfo.new(Balance.Feel.PopupSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(billboard, info, { StudsOffset = Vector3.new(0, 2.5 + rise, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()

	task.delay(Balance.Feel.PopupSeconds + 0.1, function()
		billboard:Destroy()
	end)
end

-- ------------------------------------------------------------------- Ring --

local function buildRing()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	if ringBillboard then
		ringBillboard:Destroy()
	end
	table.clear(ringSegments)

	local size = 120
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CashoutBankRing"
	billboard.Size = UDim2.fromOffset(size, size)
	billboard.StudsOffset = Vector3.new(0, 0.2, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = root
	billboard.Parent = root
	ringBillboard = billboard

	for index = 1, RING_SEGMENTS do
		local angle = (index - 1) / RING_SEGMENTS * 2 * math.pi
		local radius = size * 0.42
		local segment = Theme.New("Frame", {
			Name = "Segment" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(angle) * radius, 0.5, math.sin(angle) * radius),
			Size = UDim2.fromOffset(6, 12),
			Rotation = math.deg(angle) + 90,
			BackgroundColor3 = Theme.Banked,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, billboard) :: Frame
		Theme.Corner(segment, 2)
		table.insert(ringSegments, segment)
	end
end

local function updateRing(deltaTime: number)
	if #ringSegments == 0 then
		return
	end

	if ringActive then
		local elapsed = workspace:GetServerTimeNow() - ringStartedAt
		ringTarget = math.clamp(elapsed / math.max(ringDuration, 0.001), 0, 1)
		ringProgress = ringTarget
	elseif ringProgress > 0 then
		-- Zuruecklaufen statt springen.
		ringProgress = math.max(0, ringProgress - deltaTime / Balance.Feel.BankRingResetSeconds)
	end

	local lit = ringProgress * RING_SEGMENTS
	for index, segment in ipairs(ringSegments) do
		segment.BackgroundTransparency = if index <= lit then 0 else 0.85
	end

	if ringBillboard then
		ringBillboard.Enabled = ringProgress > 0
	end
end

--[[
	active = laeuft gerade eine Einzahlung. startedAt/duration kommen aus der
	Aktivitaet, damit der Ring dieselbe Uhr benutzt wie der Server.
]]
function Feel.SetDeposit(active: boolean, startedAt: number?, duration: number?)
	if not started then
		return
	end

	if active then
		if #ringSegments == 0 or (ringBillboard and not ringBillboard.Parent) then
			buildRing()
		end
		ringActive = true
		ringStartedAt = startedAt or workspace:GetServerTimeNow()
		ringDuration = duration or Balance.Bank.DepositSeconds
	else
		ringActive = false
	end
end

-- ------------------------------------------------------------------ Pfeil --

function Feel.SetTarget(part: BasePart?)
	if not started then
		return
	end
	targetPart = part
	if not part then
		arrow.Visible = false
	end
end

local function updateArrow()
	if not targetPart or not targetPart.Parent then
		arrow.Visible = false
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		arrow.Visible = false
		return
	end

	local point, onScreen = camera:WorldToViewportPoint(targetPart.Position)
	if onScreen and point.Z > 0 then
		-- Ziel ist im Bild: der Marker am Punkt selbst reicht.
		arrow.Visible = false
		return
	end

	local viewport = camera.ViewportSize
	local center = Vector2.new(viewport.X / 2, viewport.Y / 2)
	local direction = Vector2.new(point.X - center.X, point.Y - center.Y)
	if point.Z < 0 then
		direction = -direction
	end
	if direction.Magnitude < 1 then
		direction = Vector2.new(0, -1)
	end
	direction = direction.Unit

	local margin = 60
	local edge = Vector2.new(
		math.clamp(center.X + direction.X * viewport.X, margin, viewport.X - margin),
		math.clamp(center.Y + direction.Y * viewport.Y, margin, viewport.Y - margin)
	)

	arrow.Visible = true
	arrow.Position = UDim2.fromOffset(edge.X, edge.Y)
	-- Das Zeichen zeigt nach oben; 0 Grad ist damit "nach oben".
	arrow.Rotation = math.deg(math.atan2(direction.Y, direction.X)) + 90
end

-- ------------------------------------------------------------------- Public --

function Feel.Start(screenGui: ScreenGui)
	if started then
		return
	end
	started = true
	screen = screenGui

	arrow = Theme.Label({
		Name = "TargetArrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(48, 48),
		Text = "▲",
		TextSize = 40,
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.Delivery,
		TextStrokeTransparency = 0.5,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		ZIndex = 4,
	}, screenGui)

	player.CharacterAdded:Connect(function()
		-- Neuer Character, neuer Ring.
		table.clear(ringSegments)
		ringBillboard = nil
		ringProgress = 0
		ringActive = false
	end)

	RunService.RenderStepped:Connect(function(deltaTime)
		updateRing(deltaTime)
		updateArrow()
	end)
end

return Feel
