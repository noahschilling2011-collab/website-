--[[
	InfoPanel
	Eine schlichte Liste mit Titel. Wird zweimal benutzt: fuer die Rangliste
	(dauerhaft ein-/ausblendbar) und fuer den Heist Radar (blendet sich nach
	dem Fenster selbst aus).
]]

local Theme = require(script.Parent.Theme)

local InfoPanel = {}
InfoPanel.__index = InfoPanel

function InfoPanel.new(root: Frame, title: string, position: UDim2, size: UDim2, anchor: Vector2?)
	local self = setmetatable({}, InfoPanel)

	self.window = Theme.panel({
		Name = title,
		AnchorPoint = anchor or Vector2.new(1, 0),
		Position = position,
		Size = size,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = root,
	})
	Theme.constrain(self.window, Vector2.new(210, 150), Vector2.new(320, 340))
	Theme.padding(12).Parent = self.window

	Theme.label({
		Text = title,
		Size = UDim2.new(1, 0, 0, 24),
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextColor3 = Theme.Colors.accent,
		Parent = self.window,
	})

	self.body = Theme.create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 30),
		Size = UDim2.new(1, 0, 1, -30),
		Parent = self.window,
	}, { Theme.list(Enum.FillDirection.Vertical, 4) })

	return self
end

function InfoPanel:SetLines(lines: { string })
	for _, child in self.body:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	if #lines == 0 then
		Theme.label({
			Text = "nichts zu melden",
			Size = UDim2.new(1, 0, 0, 20),
			TextColor3 = Theme.Colors.sub,
			TextSize = 14,
			Parent = self.body,
		})
		return
	end
	for index, line in lines do
		Theme.label({
			Text = line,
			Size = UDim2.new(1, 0, 0, 20),
			TextSize = 14,
			LayoutOrder = index,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = self.body,
		})
	end
end

function InfoPanel:SetVisible(visible: boolean)
	self.window.Visible = visible
end

function InfoPanel:Toggle()
	self.window.Visible = not self.window.Visible
end

function InfoPanel:IsVisible(): boolean
	return self.window.Visible
end

-- Blendet sich nach `seconds` selbst aus, sofern nicht vorher neu gesetzt.
function InfoPanel:ShowFor(seconds: number)
	self.window.Visible = true
	self._token = (self._token or 0) + 1
	local token = self._token
	task.delay(seconds, function()
		if self._token == token then
			self.window.Visible = false
		end
	end)
end

return InfoPanel
