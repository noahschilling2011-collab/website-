--!strict
-- BuildMenuUI.luau
-- Baumenue als Leiste aus Item-Buttons. Gesperrte Items ausgegraut mit
-- Freischalt-Bedingung. Enthaelt zusaetzlich Abriss- und Abbrechen-Knopf.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiniCity")
local Items = require(Shared:WaitForChild("Items"))

local BuildMenuUI = {}
BuildMenuUI.__index = BuildMenuUI

local COL_UNLOCKED = Color3.fromRGB(45, 90, 140)
local COL_LOCKED = Color3.fromRGB(55, 58, 64)
local COL_SELECTED = Color3.fromRGB(70, 150, 220)
local COL_DEMOLISH = Color3.fromRGB(150, 60, 60)
local COL_DEMOLISH_ON = Color3.fromRGB(210, 80, 80)

local function makeButton(parent: Instance, layoutOrder: number): TextButton
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromOffset(96, 64)
	btn.LayoutOrder = layoutOrder
	btn.BackgroundColor3 = COL_LOCKED
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextStrokeTransparency = 0.6
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 13
	btn.TextWrapped = true
	btn.Text = ""
	btn.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = btn
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 0
	stroke.Color = COL_SELECTED
	stroke.Parent = btn
	return btn
end

function BuildMenuUI.create(parentGui: ScreenGui, callbacks)
	local self = setmetatable({}, BuildMenuUI)
	self.callbacks = callbacks
	self.buttons = {} :: { [string]: { btn: TextButton, stroke: UIStroke } }
	self.unlocked = {} :: { [string]: boolean }

	local bar = Instance.new("Frame")
	bar.Name = "BuildBar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -12)
	bar.Size = UDim2.fromOffset(0, 76)
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	bar.BackgroundTransparency = 0.2
	bar.BorderSizePixel = 0
	bar.Parent = parentGui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = bar
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = bar
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bar

	-- Item-Buttons
	for i, item in Items.List do
		local btn = makeButton(bar, i)
		local stroke = btn:FindFirstChildOfClass("UIStroke") :: UIStroke
		btn.Activated:Connect(function()
			if self.unlocked[item.id] then
				self.callbacks.onSelectItem(item.id)
			end
		end)
		self.buttons[item.id] = { btn = btn, stroke = stroke }
	end

	-- Abriss-Button
	local demolish = makeButton(bar, #Items.List + 1)
	demolish.BackgroundColor3 = COL_DEMOLISH
	demolish.Text = "Abriss\n(50% zurueck)"
	demolish.Activated:Connect(function()
		self.callbacks.onToggleDemolish()
	end)
	self.demolishBtn = demolish
	self.demolishStroke = demolish:FindFirstChildOfClass("UIStroke") :: UIStroke

	-- Abbrechen-Button
	local cancel = makeButton(bar, #Items.List + 2)
	cancel.BackgroundColor3 = Color3.fromRGB(70, 72, 80)
	cancel.Text = "Abbrechen"
	cancel.Activated:Connect(function()
		self.callbacks.onCancel()
	end)

	return self
end

-- Aktualisiert Freischalt-Zustaende anhand von state.unlockedItems + population.
function BuildMenuUI:update(state)
	local unlockedSet = {}
	for _, id in state.unlockedItems or {} do
		unlockedSet[id] = true
	end
	self.unlocked = unlockedSet

	for _, item in Items.List do
		local entry = self.buttons[item.id]
		local btn = entry.btn
		if unlockedSet[item.id] then
			btn.BackgroundColor3 = COL_UNLOCKED
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
			btn.Text = string.format("%s\n%d $", item.name, item.price)
		else
			btn.BackgroundColor3 = COL_LOCKED
			btn.TextColor3 = Color3.fromRGB(150, 150, 155)
			btn.Text = string.format("%s\n[ab %d Einw.]", item.name, item.unlockPop)
		end
	end
end

-- Hebt den aktiven Bau-Button hervor (id) oder den Abriss-Modus.
function BuildMenuUI:setActive(kind: string, id: string?)
	for itemId, entry in self.buttons do
		entry.stroke.Thickness = (kind == "build" and itemId == id) and 2 or 0
	end
	if kind == "demolish" then
		self.demolishStroke.Thickness = 2
		self.demolishBtn.BackgroundColor3 = COL_DEMOLISH_ON
	else
		self.demolishStroke.Thickness = 0
		self.demolishBtn.BackgroundColor3 = COL_DEMOLISH
	end
end

return BuildMenuUI
