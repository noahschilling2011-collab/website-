--[[
	DailyPanel
	Sieben Kaesten, einer pro Tag. Welcher Tag dran ist und ob abgeholt werden
	darf, entscheidet der Server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)

local DailyPanel = {}

function DailyPanel.Init(root: Frame)
	local window = Theme.panel({
		Name = "DailyPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.94, 0, 0.42, 0),
		Visible = false,
		Parent = root,
	})
	Theme.constrain(window, Vector2.new(320, 240), Vector2.new(620, 280))
	Theme.padding(14).Parent = window

	Theme.label({
		Text = "Taegliche Belohnung",
		Size = UDim2.new(1, -40, 0, 30),
		Font = Enum.Font.GothamBold,
		TextSize = 24,
		Parent = window,
	})
	local close = Theme.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 34, 0, 30),
		Text = "X",
		Parent = window,
	})
	close.Activated:Connect(function()
		DailyPanel.SetVisible(false)
	end)

	local strip = Theme.create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(1, 0, 0, 110),
		Parent = window,
	}, { Theme.list(Enum.FillDirection.Horizontal, 6) })

	local status = Theme.label({
		Position = UDim2.new(0, 0, 0, 160),
		Size = UDim2.new(1, 0, 0, 22),
		TextColor3 = Theme.Colors.sub,
		TextSize = 14,
		Parent = window,
	})

	local claim = Theme.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(0, 260, 0, 42),
		BackgroundColor3 = Theme.Colors.good,
		TextColor3 = Color3.fromRGB(15, 30, 20),
		TextSize = 17,
		Text = "Abholen",
		Parent = window,
	})
	claim.Activated:Connect(function()
		Remotes.Get("RequestClaimDaily"):FireServer()
	end)

	DailyPanel._refs = { window = window, strip = strip, status = status, claim = claim }

	Store.Changed:Connect(function(key)
		if key == "daily" and window.Visible then
			DailyPanel.Render()
		end
	end)
	return DailyPanel
end

function DailyPanel.SetVisible(visible: boolean)
	DailyPanel._refs.window.Visible = visible
	if visible then
		DailyPanel.Render()
	end
end

function DailyPanel.Toggle()
	DailyPanel.SetVisible(not DailyPanel._refs.window.Visible)
end

function DailyPanel.Render()
	local daily = Store.daily
	local refs = DailyPanel._refs
	if not daily then
		return
	end
	for _, child in refs.strip:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	for day, reward in daily.rewards do
		local claimed = day <= daily.streak and not (daily.canClaim and day == daily.nextStreak)
		local isNext = daily.canClaim and day == daily.nextStreak
		local box = Theme.panel({
			BackgroundColor3 = isNext and Theme.Colors.accent or (claimed and Theme.Colors.good or Theme.Colors.panelAlt),
			-- Sieben Kaesten teilen sich die Breite, statt 7x80 px zu verlangen.
			Size = UDim2.new(1 / #daily.rewards, -6, 1, 0),
			LayoutOrder = day,
			Parent = refs.strip,
		})
		Theme.label({
			Text = ("Tag %d"):format(day),
			Size = UDim2.new(1, 0, 0, 26),
			Position = UDim2.new(0, 0, 0, 12),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(20, 20, 24),
			TextSize = 15,
			Parent = box,
		})
		Theme.label({
			Text = Util.FormatCash(reward),
			Size = UDim2.new(1, 0, 0, 24),
			Position = UDim2.new(0, 0, 0, 44),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Color3.fromRGB(20, 20, 24),
			TextSize = 15,
			Parent = box,
		})
	end

	if daily.canClaim then
		refs.status.Text = ("Kette: %d Tage. Heute gibt es Tag %d."):format(daily.streak, daily.nextStreak)
		refs.claim.Text = ("Abholen: %s"):format(Util.FormatCash(daily.reward))
		refs.claim.BackgroundColor3 = Theme.Colors.good
		refs.claim.Active = true
	else
		refs.status.Text = ("Kette: %d Tage. Ein verpasster Tag setzt zurueck."):format(daily.streak)
		refs.claim.Text = ("Naechster Tag in %s"):format(Util.FormatTime(daily.nextInSeconds))
		refs.claim.BackgroundColor3 = Theme.Colors.panelAlt
		refs.claim.Active = false
	end
end

return DailyPanel
