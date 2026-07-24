--[[
	Toast
	Kurzmeldungen unten links. Der Server schickt Text und Art, der Client
	zeigt sie an - mehr passiert hier nicht.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Toast = {}

local MAX_VISIBLE = 5
local LIFETIME = 5

local KIND_COLORS = {
	good = Theme.Colors.good,
	bad = Theme.Colors.bad,
	cash = Theme.Colors.accent,
	heist = Theme.Colors.heist,
	info = Theme.Colors.sub,
}

function Toast.Init(root: ScreenGui)
	local container = Theme.create("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.new(0, 340, 0, 260),
		Parent = root,
	}, {
		Theme.create("UIListLayout", {
			Padding = UDim.new(0, 6),
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	Toast._container = container
	Toast._counter = 0
	return Toast
end

function Toast.Show(text: string, kind: string?)
	local container = Toast._container
	if not container then
		return
	end
	Toast._counter += 1

	local frame = Theme.panel({
		Name = "Toast",
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.08,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = Toast._counter,
		Parent = container,
	})
	Theme.padding(10).Parent = frame

	Theme.create("Frame", {
		BackgroundColor3 = KIND_COLORS[kind or "info"] or Theme.Colors.sub,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 4, 1, 0),
		Parent = frame,
	}, { Theme.corner(2) })

	Theme.label({
		Text = text,
		Position = UDim2.new(0, 12, 0, 0),
		Size = UDim2.new(1, -12, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextSize = 15,
		Font = Enum.Font.GothamMedium,
		Parent = frame,
	})

	local children = container:GetChildren()
	local toasts = {}
	for _, child in children do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts > MAX_VISIBLE then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for index = 1, #toasts - MAX_VISIBLE do
			toasts[index]:Destroy()
		end
	end

	task.delay(LIFETIME, function()
		if frame.Parent then
			local tween = TweenService:Create(frame, TweenInfo.new(0.35), { BackgroundTransparency = 1 })
			tween:Play()
			tween.Completed:Wait()
			frame:Destroy()
		end
	end)
end

return Toast
