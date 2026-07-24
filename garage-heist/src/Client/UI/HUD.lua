--[[
	HUD
	Cash, Rate, Kasse, Heist-Countdown, Trage-Anzeige und die Knoepfe fuer die
	Menues. Alle Zahlen kommen fertig vom Server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
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

function HUD.Init(root: ScreenGui, callbacks)
	local cashPill = pill(root, "CashPill", Vector2.new(0, 0), UDim2.new(0, 16, 0, 16), UDim2.new(0, 240, 0, 78))
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
		Position = UDim2.new(0, 16, 0, 102),
		Size = UDim2.new(0, 240, 0, 42),
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
		UDim2.new(0.5, 0, 0, 16),
		UDim2.new(0, 300, 0, 52)
	)
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
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.new(0, 150, 0, 200),
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
		Size = UDim2.new(0, 420, 0, 96),
		Visible = false,
		Parent = root,
	})
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
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -130),
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

	HUD._refs = {
		cash = cashLabel,
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
	refs.cash.Text = Util.FormatCash(cash.cash)
	refs.rate.Text = Util.FormatRate(cash.rate)
	refs.collect.Visible = (not cash.autoCollect) and cash.pile >= 1
	refs.collect.Text = ("Kasse leeren: %s"):format(Util.FormatCash(cash.pile))

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
	else
		refs.heist.BackgroundColor3 = Theme.Colors.panel
		refs.heistLabel.Text = ("Klau-Fenster in %s"):format(Util.FormatTime(heist.nextAt - now))
	end
end

return HUD
