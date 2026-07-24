--[[
	ShopMenu
	Zeigt Gamepasses und Developer Products. Der Client kennt keine Produkt-IDs
	- er schickt nur den Schluessel, der Server loest den Kaufdialog aus.
	Produkte, die im Dashboard noch nicht existieren, sind ausgegraut.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)

local ShopMenu = {}

function ShopMenu.Init(root: ScreenGui)
	local window = Theme.panel({
		Name = "ShopMenu",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 520, 0, 470),
		Visible = false,
		Parent = root,
	})
	Theme.padding(14).Parent = window

	Theme.label({
		Text = "Shop",
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
		ShopMenu.SetVisible(false)
	end)

	local scroll = Theme.create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 40),
		Size = UDim2.new(1, 0, 1, -40),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = window,
	}, { Theme.list(Enum.FillDirection.Vertical, 8) })

	ShopMenu._window = window
	ShopMenu._scroll = scroll

	Store.Changed:Connect(function(key)
		if key == "shop" and window.Visible then
			ShopMenu.Render()
		end
	end)
	return ShopMenu
end

function ShopMenu.SetVisible(visible: boolean)
	ShopMenu._window.Visible = visible
	if visible then
		ShopMenu.Render()
	end
end

function ShopMenu.Toggle()
	ShopMenu.SetVisible(not ShopMenu._window.Visible)
end

function ShopMenu.Render()
	local scroll = ShopMenu._scroll
	for _, child in scroll:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	local order = 0
	for _, item in Store.shop do
		order += 1
		local frame = Theme.panel({
			BackgroundColor3 = Theme.Colors.panelAlt,
			Size = UDim2.new(1, 0, 0, 64),
			LayoutOrder = order,
			Parent = scroll,
		})
		Theme.padding(8).Parent = frame

		Theme.label({
			Text = item.title .. (item.kind == "pass" and "  (Gamepass)" or ""),
			Size = UDim2.new(1, -150, 0, 22),
			Font = Enum.Font.GothamBold,
			TextSize = 16,
			Parent = frame,
		})
		Theme.label({
			Text = item.desc,
			Position = UDim2.new(0, 0, 0, 24),
			Size = UDim2.new(1, -150, 0, 20),
			TextColor3 = Theme.Colors.sub,
			TextSize = 13,
			Parent = frame,
		})

		local text, enabled, color
		if item.owned then
			text, enabled, color = "Gekauft", false, Theme.Colors.panelAlt
		elseif not item.configured then
			text, enabled, color = "nicht eingerichtet", false, Theme.Colors.panelAlt
		else
			text, enabled, color = ("R$ %d"):format(item.robux), true, Theme.Colors.accent
		end

		local button = Theme.button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.new(0, 140, 0, 38),
			BackgroundColor3 = color,
			TextColor3 = enabled and Color3.fromRGB(20, 18, 12) or Theme.Colors.sub,
			TextSize = 15,
			Text = text,
			Parent = frame,
		})
		if enabled then
			button.Activated:Connect(function()
				Remotes.Get("RequestPromptPurchase"):FireServer(item.kind, item.key)
			end)
		end
	end
end

return ShopMenu
