--[[
	AdminPanel
	Wird nur gebaut, wenn der Server sagt, dass dieser Spieler Admin ist. Der
	Client entscheidet das nicht selbst - und selbst wenn jemand das Panel
	nachbaut, prueft der Server jeden einzelnen Befehl noch einmal.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)

local Theme = require(script.Parent.Theme)

local AdminPanel = {}

-- Reihenfolge = Reihenfolge im Panel.
local COMMANDS = {
	{ key = "cash", label = "+10.000 Cash", value = 10000 },
	{ key = "cash", label = "+1.000.000", value = 1000000 },
	{ key = "max", label = "Alles auf Max" },
	{ key = "level", label = "Garage Stufe 5", value = 5 },
	{ key = "heist", label = "Fenster oeffnen" },
	{ key = "close", label = "Fenster schliessen" },
	{ key = "radar", label = "Radar-Ladung" },
	{ key = "rebirth", label = "Rebirth erzwingen" },
	{ key = "reset", label = "Profil zuruecksetzen" },
}

function AdminPanel.Init(root: Frame)
	local toggle = Theme.button({
		Name = "AdminToggle",
		-- Oben links ueber der Cash-Anzeige. Der Platz darunter gehoert dem
		-- Radar-Panel, deshalb nicht dorthin.
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 16, 0, 20),
		Size = UDim2.new(0, 96, 0, 30),
		BackgroundColor3 = Theme.Colors.heist,
		TextSize = 13,
		Text = "ADMIN",
		Visible = false,
		Parent = root,
	})

	local window = Theme.panel({
		Name = "AdminPanel",
		-- Als Modal in der Mitte: links ist kein Platz, ohne etwas zu verdecken.
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 220, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		ZIndex = 25,
		Parent = root,
	})
	Theme.padding(10).Parent = window
	Theme.create("UIListLayout", {
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = window,
	})

	Theme.label({
		Text = "Admin-Werkzeuge",
		Size = UDim2.new(1, 0, 0, 20),
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = Theme.Colors.heist,
		LayoutOrder = 0,
		ZIndex = 26,
		Parent = window,
	})

	for index, entry in COMMANDS do
		local button = Theme.button({
			Size = UDim2.new(1, 0, 0, 30),
			TextSize = 13,
			LayoutOrder = index,
			Text = entry.label,
			ZIndex = 26,
			Parent = window,
		})
		button.Activated:Connect(function()
			Remotes.Get("AdminCommand"):FireServer(entry.key, entry.value)
		end)
	end

	toggle.Activated:Connect(function()
		window.Visible = not window.Visible
	end)

	AdminPanel._toggle = toggle
	AdminPanel._window = window

	Remotes.Get("AdminState").OnClientEvent:Connect(function(payload)
		local isAdmin = type(payload) == "table" and payload.isAdmin == true
		toggle.Visible = isAdmin
		if not isAdmin then
			window.Visible = false
		end
	end)

	return AdminPanel
end

return AdminPanel
