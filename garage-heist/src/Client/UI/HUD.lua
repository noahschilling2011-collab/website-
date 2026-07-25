--[[
	HUD
	Cash, Rate, Kasse, Heist-Countdown, Trage-Anzeige und die Knoepfe fuer die
	Menues. Alle Zahlen kommen fertig vom Server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Audio = require(Shared.Audio)
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)

local HUD = {}

local function pill(parent, name, anchor, position, size)
	return Theme.panel({
		Name = name,
		AnchorPoint = anchor,
		Position = position,
		Size = size,
		BackgroundTransparency = 0.05,
		Parent = parent,
	})
end

function HUD.Init(root: Frame, callbacks)
	-- Reihenfolge oben: Heist-Anzeige mittig, Cash links darunter, Knoepfe
	-- rechts daneben. Auf 390 px Breite ueberschneidet sich damit nichts.
	local cashPill = pill(root, "CashPill", Vector2.new(0, 0), UDim2.new(0, 16, 0, 70), UDim2.new(0, 200, 0, 70))
	Theme.padding(10).Parent = cashPill

	local cashLabel = Theme.label({
		Text = "$0",
		Size = UDim2.new(1, 0, 0, 34),
		Font = Enum.Font.GothamBold,
		TextSize = 30,
		Parent = cashPill,
	})
	local rateLabel = Theme.label({
		Text = "$0,0/s",
		Position = UDim2.new(0, 0, 0, 36),
		Size = UDim2.new(1, 0, 0, 20),
		TextColor3 = Theme.Colors.good,
		TextSize = 16,
		Parent = cashPill,
	})

	local collectButton = Theme.button({
		Name = "Collect",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 16, 0, 148),
		Size = UDim2.new(0, 200, 0, 38),
		BackgroundColor3 = Theme.Colors.accent,
		TextColor3 = Color3.fromRGB(25, 20, 10),
		TextSize = 17,
		Visible = false,
		Text = "Kasse leeren",
		Parent = root,
	})
	collectButton.Activated:Connect(function()
		Remotes.Get("RequestCollect"):FireServer()
	end)

	local heistPill = pill(
		root,
		"HeistPill",
		Vector2.new(0.5, 0),
		UDim2.new(0.5, 0, 0, 8),
		UDim2.new(0.5, 0, 0, 48)
	)
	Theme.constrain(heistPill, Vector2.new(230, 48), Vector2.new(300, 48))
	local heistLabel = Theme.label({
		Text = "Klau-Fenster: -",
		Size = UDim2.new(1, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		TextSize = 20,
		Parent = heistPill,
	})

	local buttonColumn = Theme.create("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 70),
		Size = UDim2.new(0, 130, 0, 200),
		Parent = root,
	}, { Theme.list(Enum.FillDirection.Vertical, 8) })

	local function menuButton(text, order, callback)
		local button = Theme.button({
			Size = UDim2.new(1, 0, 0, 40),
			TextSize = 16,
			LayoutOrder = order,
			Text = text,
			Parent = buttonColumn,
		})
		button.Activated:Connect(callback)
		return button
	end

	menuButton("Werkstatt", 1, callbacks.toggleGarage)
	menuButton("Shop", 2, callbacks.toggleShop)
	local dailyButton = menuButton("Taeglich", 3, callbacks.toggleDaily)
	menuButton("Rangliste", 4, callbacks.toggleLeaderboard)

	-- Trage-Leiste ------------------------------------------------------
	local carryBar = Theme.panel({
		Name = "CarryBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.new(0.8, 0, 0, 96),
		Visible = false,
		Parent = root,
	})
	Theme.constrain(carryBar, Vector2.new(260, 96), Vector2.new(420, 96))
	Theme.padding(10).Parent = carryBar

	local carryLabel = Theme.label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		TextSize = 17,
		TextWrapped = true,
		Parent = carryBar,
	})
	local dropButton = Theme.button({
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(0.48, 0, 0, 34),
		TextSize = 15,
		Text = "Ablegen",
		Parent = carryBar,
	})
	dropButton.Activated:Connect(function()
		Remotes.Get("RequestDropPart"):FireServer()
	end)

	local tackleButton = Theme.button({
		Name = "Tackle",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -130),
		Size = UDim2.new(0, 220, 0, 44),
		BackgroundColor3 = Theme.Colors.heist,
		TextSize = 16,
		Visible = false,
		Text = "Rempeln (F)",
		Parent = root,
	})
	tackleButton.Activated:Connect(function()
		Remotes.Get("RequestTackle"):FireServer()
	end)

	local flash = Theme.create("Frame", {
		Name = "Flash",
		BackgroundColor3 = Theme.Colors.heist,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Visible = false,
		Parent = root,
	})

	HUD._refs = {
		cash = cashLabel,
		flash = flash,
		rate = rateLabel,
		collect = collectButton,
		heist = heistPill,
		heistLabel = heistLabel,
		carryBar = carryBar,
		carryLabel = carryLabel,
		tackle = tackleButton,
		daily = dailyButton,
	}

	Store.Changed:Connect(function()
		HUD.Update()
	end)
	RunService.Heartbeat:Connect(function()
		HUD._accumulator = (HUD._accumulator or 0) + 1
		if HUD._accumulator % 10 == 0 then
			HUD.UpdateTimer()
		end
	end)
	HUD.Update()
	return HUD
end

function HUD.Update()
	local refs = HUD._refs
	if not refs then
		return
	end
	local cash = Store.cash
	-- Der hochzaehlende Zaehler ist bei einem Idle-Spiel das Kernfeedback.
	local previous = HUD._lastCash or cash.cash
	if math.abs(cash.cash - previous) > 0.5 then
		Theme.countTo(refs.cash, previous, cash.cash, Util.FormatCash, 0.35)
		Theme.pop(refs.cash, 0.06)
	else
		refs.cash.Text = Util.FormatCash(cash.cash)
	end
	HUD._lastCash = cash.cash
	refs.rate.Text = Util.FormatRate(cash.rate)
	refs.collect.Visible = (not cash.autoCollect) and cash.pile >= 1
	refs.collect.Text = ("Kasse leeren: %s"):format(Util.FormatCash(cash.pile))

	if Store.heist.open and not HUD._wasOpen then
		HUD.Flash()
	end
	HUD._wasOpen = Store.heist.open

	local carry = Store.carry
	refs.carryBar.Visible = carry ~= nil
	if carry then
		refs.carryLabel.Text = ("Du traegst: %s (%s)\nAb in deine Garage - auf das blaue Pad!"):format(
			carry.tierName,
			carry.slotName
		)
	end
	refs.tackle.Visible = Store.heist.open and carry == nil

	if Store.daily then
		refs.daily.BackgroundColor3 = Store.daily.canClaim and Theme.Colors.good or Theme.Colors.panelAlt
		refs.daily.TextColor3 = Store.daily.canClaim and Color3.fromRGB(15, 30, 20) or Theme.Colors.text
	end
	HUD.UpdateTimer()
end

function HUD.UpdateTimer()
	local refs = HUD._refs
	if not refs then
		return
	end
	local heist = Store.heist
	local now = workspace:GetServerTimeNow()
	if heist.open then
		refs.heist.BackgroundColor3 = Theme.Colors.heist
		refs.heistLabel.Text = ("KLAU-FENSTER OFFEN  %s"):format(Util.FormatTime(heist.endsAt - now))
		return
	end

	local remaining = heist.nextAt - now
	refs.heistLabel.Text = ("Klau-Fenster in %s"):format(Util.FormatTime(remaining))

	-- Ein Tick pro Sekunde in den letzten fuenf.
	local whole = math.ceil(remaining)
	if whole <= 5 and whole >= 1 and HUD._lastTick ~= whole then
		HUD._lastTick = whole
		Audio.PlayLocal("countdown")
	elseif whole > 5 then
		HUD._lastTick = nil
	end
	if remaining <= Config.HEIST_PULSE_AT and remaining > 0 then
		-- Letzte Sekunden: pulsierend auf die Heist-Farbe ziehen.
		local pulse = (math.sin(os.clock() * 6) + 1) / 2
		refs.heist.BackgroundColor3 = Theme.Colors.panel:Lerp(Theme.Colors.heist, pulse)
	else
		refs.heist.BackgroundColor3 = Theme.Colors.panel
	end
end

-- Kurzer Vollbild-Impuls, wenn das Fenster aufgeht.
function HUD.Flash()
	local refs = HUD._refs
	if not refs or not refs.flash then
		return
	end
	refs.flash.Visible = true
	refs.flash.BackgroundTransparency = 0.45
	local tween = TweenService:Create(refs.flash, TweenInfo.new(0.7), { BackgroundTransparency = 1 })
	tween:Play()
	tween.Completed:Connect(function()
		refs.flash.Visible = false
	end)
end

return HUD
