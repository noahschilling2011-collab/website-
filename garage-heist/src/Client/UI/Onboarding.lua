--[[
	Onboarding
	Erklaert das Spiel in den ersten zwei Minuten - und hoert danach auf.

	Vorher gab es zwei Toasts beim Erststart. Toasts verschwinden nach ein
	paar Sekunden; wer in dem Moment gerade woanders hinschaut, hat das Spiel
	nie erklaert bekommen. Roblox-Spieler lesen keine Textwaende, also:

	1. Eine Karte beim allerersten Beitritt. Drei Saetze, ein Knopf.
	2. Danach ein kleiner Zielbalken unten, der genau EINE Aufgabe zeigt und
	   sich mit dem Spielstand weiterschaltet.
	3. Dazu ein Marker in der Welt ueber dem Ding, das gemeint ist - durch
	   Waende sichtbar, damit "Werkbank" nicht gesucht werden muss.

	Der Balken verschwindet dauerhaft, sobald drei Teile verbaut sind.

	EINSCHRAENKUNG: der Fortschritt lebt nur in dieser Sitzung. Der Client
	kann nichts speichern. Wer neu beitritt und schon Teile hat, bekommt den
	Balken gar nicht erst zu sehen (weil die Bedingung nicht mehr passt) -
	die Intro-Karte aber schon wieder, falls das Auto komplett leer ist.
	Sauber waere ein Feld `tutorialDone` im Profil.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)

local Onboarding = {}

local STEPS = {
	buy = {
		text = "Geh zur WERKBANK und kauf dein erstes Teil",
		hint = "Reifen kosten 100.",
		target = "Workbench",
		color = Theme.Colors.accent,
	},
	collect = {
		text = "Dein Geld liegt in der KASSE",
		hint = "Ohne Abholen laeuft sie irgendwann voll.",
		target = "CashRegister",
		color = Theme.Colors.good,
	},
	heist = {
		text = "ALLE TORE SIND OFFEN",
		hint = "Rein in eine fremde Garage, Teil abmontieren, zurueck aufs blaue Pad.",
		target = nil,
		color = Theme.Colors.heist,
	},
	grow = {
		text = "Bau weiter aus",
		hint = "Jedes Teil bringt mehr pro Sekunde - auch waehrend du offline bist.",
		target = "Workbench",
		color = Theme.Colors.accent,
	},
}

-- Zustand ---------------------------------------------------------------
local state = {
	introShown = false,
	collectDone = false,
	sawFullPile = false,
	heistShown = 0,
	finished = false,
	current = nil,
}

local refs = {}

local function countParts(): (number, boolean)
	local snapshot = Store.snapshot
	if not snapshot then
		return 0, false
	end
	local installed, repairing = 0, false
	for _, car in snapshot.cars do
		for _, slot in car.parts do
			if slot.tier > 0 then
				installed += 1
			end
			if slot.repair then
				repairing = true
			end
		end
	end
	return installed, repairing
end

local function decideStep(): string?
	if state.finished then
		return nil
	end
	local installed, repairing = countParts()

	if installed == 0 and not repairing then
		return "buy"
	end

	local cash = Store.cash
	if not state.collectDone and not cash.autoCollect then
		if cash.pile >= 8 then
			state.sawFullPile = true
			return "collect"
		end
		if state.sawFullPile and cash.pile < 2 then
			state.collectDone = true
		end
	end

	if Store.heist.open and state.heistShown < 2 then
		return "heist"
	end

	if installed >= 3 then
		state.finished = true
		return nil
	end
	return "grow"
end

-- Weltmarker ------------------------------------------------------------
local function ownPlot(): Model?
	local player = Players.LocalPlayer
	local index = player:GetAttribute("PlotIndex")
	if not index then
		return nil
	end
	local garages = Workspace:FindFirstChild("Garages")
	if not garages then
		return nil
	end
	return garages:FindFirstChild("Plot" .. index) :: Model?
end

local function ensureMarker()
	if refs.marker and refs.marker.Parent then
		return refs.marker
	end
	-- Vom Client erzeugt, also rein lokal.
	local anchor = Instance.new("Part")
	anchor.Name = "OnboardingMarker"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Parent = Workspace

	local beam = Instance.new("Part")
	beam.Name = "OnboardingBeam"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Size = Vector3.new(3.4, 14, 3.4)
	beam.Shape = Enum.PartType.Cylinder
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.55
	beam.Parent = Workspace

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(10, 2.4)
	gui.StudsOffset = Vector3.new(0, 1.2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 300
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Michroma
	label.TextScaled = true
	label.TextStrokeTransparency = 0.3
	label.TextColor3 = Theme.Colors.accent
	label.Parent = gui

	refs.marker = anchor
	refs.markerBeam = beam
	refs.markerLabel = label
	return anchor
end

local function setMarker(targetName: string?, text: string, color: Color3)
	if not targetName then
		if refs.marker then
			refs.marker.Parent = nil
			refs.markerBeam.Parent = nil
		end
		return
	end
	local plot = ownPlot()
	local target = plot and plot:FindFirstChild(targetName)
	if not target or not target:IsA("BasePart") then
		if refs.marker then
			refs.marker.Parent = nil
			refs.markerBeam.Parent = nil
		end
		return
	end

	ensureMarker()
	refs.marker.Parent = Workspace
	refs.markerBeam.Parent = Workspace
	refs.marker.Position = target.Position + Vector3.new(0, 8.5, 0)
	-- Zylinder liegt entlang X, deshalb aufrichten.
	refs.markerBeam.CFrame = CFrame.new(target.Position + Vector3.new(0, 7, 0))
		* CFrame.Angles(0, 0, math.rad(90))
	refs.markerBeam.Color = color
	refs.markerLabel.Text = text
	refs.markerLabel.TextColor3 = color
end

-- Intro-Karte -----------------------------------------------------------
local function showIntro(root: Frame)
	if state.introShown then
		return
	end
	state.introShown = true

	local card = Theme.panel({
		Name = "Intro",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.8, 0, 0, 320),
		ZIndex = 40,
		Parent = root,
	})
	Theme.constrain(card, Vector2.new(300, 320), Vector2.new(460, 320))
	Theme.padding(20).Parent = card
	Theme.glow(card, Theme.Colors.accent)

	Theme.label({
		Text = "GARAGE HEIST",
		Size = UDim2.new(1, 0, 0, 34),
		Font = Theme.Fonts.display,
		TextSize = 24,
		TextColor3 = Theme.Colors.accent,
		ZIndex = 41,
		Parent = card,
	})

	local lines = {
		"Bau Teile in deine Karre. Jedes Teil macht Geld pro Sekunde - auch wenn du offline bist.",
		"Alle 3 Minuten gehen ALLE Tore auf. Dann kannst du bei anderen Teile abmontieren und mitnehmen.",
		"Wer dich unterwegs rempelt, kriegt das Teil. Also: schnell rein, schnell raus.",
	}
	for index, text in lines do
		Theme.label({
			Text = ("%d.  %s"):format(index, text),
			Position = UDim2.new(0, 0, 0, 46 + (index - 1) * 68),
			Size = UDim2.new(1, 0, 0, 62),
			TextSize = 15,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = Theme.Colors.text,
			ZIndex = 41,
			Parent = card,
		})
	end

	local ok = Theme.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(0.7, 0, 0, 44),
		BackgroundColor3 = Theme.Colors.accent,
		TextColor3 = Theme.Colors.ink,
		TextSize = 17,
		Text = "Los geht's",
		ZIndex = 41,
		Parent = card,
	})
	ok.Activated:Connect(function()
		local tween = TweenService:Create(card, TweenInfo.new(0.2), { BackgroundTransparency = 1 })
		tween:Play()
		tween.Completed:Connect(function()
			card:Destroy()
		end)
	end)

	Theme.pop(card, 0.12)
end

-- Zielbalken ------------------------------------------------------------
function Onboarding.Init(root: Frame)
	-- Unten mittig, ueber dem Rempeln-Knopf. Oben ist auf schmalen Schirmen
	-- kein Platz: dort stehen schon Cash links, Heist-Pille mittig und die
	-- Knopfleiste rechts.
	local bar = Theme.panel({
		Name = "Objective",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -190),
		Size = UDim2.new(0.62, 0, 0, 56),
		Visible = false,
		ZIndex = 12,
		Parent = root,
	})
	Theme.constrain(bar, Vector2.new(240, 56), Vector2.new(400, 56))
	Theme.padding(9).Parent = bar

	local title = Theme.label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 20),
		Font = Theme.Fonts.bodyBold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 13,
		Parent = bar,
	})
	local hint = Theme.label({
		Text = "",
		Position = UDim2.new(0, 0, 0, 21),
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = 12,
		TextWrapped = true,
		TextColor3 = Theme.Colors.sub,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 13,
		Parent = bar,
	})
	local glow = Theme.glow(bar, Theme.Colors.accent)

	refs.bar = bar
	refs.title = title
	refs.hint = hint
	refs.glow = glow

	local function refresh()
		local key = decideStep()
		if key == state.current then
			-- Marker nachziehen, falls der Plot erst jetzt zugewiesen wurde.
			if key then
				local step = STEPS[key]
				setMarker(step.target, step.text, step.color)
			end
			return
		end
		state.current = key

		if not key then
			bar.Visible = false
			setMarker(nil, "", Theme.Colors.accent)
			return
		end

		local step = STEPS[key]
		if key == "heist" then
			state.heistShown += 1
		end
		bar.Visible = true
		title.Text = step.text
		title.TextColor3 = step.color
		hint.Text = step.hint
		glow.Color = step.color
		setMarker(step.target, step.text, step.color)
		Theme.pop(bar, 0.1)
	end

	Store.Changed:Connect(function(changedKey)
		if changedKey == "snapshot" and not state.introShown then
			local installed = countParts()
			if installed == 0 then
				showIntro(root)
			else
				-- Wer schon Teile hat, braucht keine Erklaerung mehr.
				state.introShown = true
			end
		end
		refresh()
	end)

	-- Der Marker muss auch dann auftauchen, wenn der Plot erst nach dem
	-- ersten Snapshot zugewiesen wird.
	Players.LocalPlayer:GetAttributeChangedSignal("PlotIndex"):Connect(refresh)

	-- Leichter Puls auf dem Weltmarker, damit er nicht wie Deko wirkt.
	RunService.Heartbeat:Connect(function()
		if refs.markerBeam and refs.markerBeam.Parent then
			local pulse = (math.sin(os.clock() * 4) + 1) / 2
			refs.markerBeam.Transparency = 0.4 + pulse * 0.35
		end
	end)

	refresh()
	return Onboarding
end

return Onboarding
