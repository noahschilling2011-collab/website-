--!strict
-- HUD.luau
-- Zeigt Geld, Einwohner und Einkommen/Tick. Blendet Freischalt-Meldungen ein.

local TweenService = game:GetService("TweenService")

local HUD = {}
HUD.__index = HUD

local function makeLabel(parent: Instance, order: number): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -16, 0, 26)
	lbl.Position = UDim2.new(0, 8, 0, 8 + order * 28)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	lbl.TextStrokeTransparency = 0.5
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 20
	lbl.Text = ""
	lbl.Parent = parent
	return lbl
end

function HUD.create(parentGui: ScreenGui)
	local self = setmetatable({}, HUD)

	local panel = Instance.new("Frame")
	panel.Name = "StatsPanel"
	panel.Size = UDim2.fromOffset(240, 98)
	panel.Position = UDim2.fromOffset(12, 12)
	panel.BackgroundColor3 = Color3.fromRGB(25, 28, 34)
	panel.BackgroundTransparency = 0.25
	panel.BorderSizePixel = 0
	panel.Parent = parentGui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel

	self.cashLabel = makeLabel(panel, 0)
	self.popLabel = makeLabel(panel, 1)
	self.incomeLabel = makeLabel(panel, 2)

	-- Toast-Container (Bildschirmmitte oben)
	self.toastLabel = Instance.new("TextLabel")
	self.toastLabel.Size = UDim2.fromOffset(420, 44)
	self.toastLabel.Position = UDim2.new(0.5, -210, 0, 90)
	self.toastLabel.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
	self.toastLabel.BackgroundTransparency = 1
	self.toastLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	self.toastLabel.TextTransparency = 1
	self.toastLabel.Font = Enum.Font.GothamBold
	self.toastLabel.TextSize = 22
	self.toastLabel.Text = ""
	self.toastLabel.BorderSizePixel = 0
	self.toastLabel.Parent = parentGui
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0, 8)
	tc.Parent = self.toastLabel

	self:update({ cash = 0, population = 0, incomePerTick = 0 })
	return self
end

function HUD:update(state)
	self.cashLabel.Text = string.format("Geld: %d $", state.cash or 0)
	self.popLabel.Text = string.format("Einwohner: %d", state.population or 0)
	self.incomeLabel.Text = string.format("Einkommen: +%d $ / Tick", state.incomePerTick or 0)
end

function HUD:toast(text: string, color: Color3?)
	local lbl = self.toastLabel
	lbl.Text = text
	lbl.BackgroundColor3 = color or Color3.fromRGB(40, 120, 60)
	TweenService:Create(lbl, TweenInfo.new(0.25), { TextTransparency = 0, BackgroundTransparency = 0.1 }):Play()
	task.delay(2.2, function()
		if lbl.Text == text then
			TweenService:Create(lbl, TweenInfo.new(0.5), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		end
	end)
end

return HUD
