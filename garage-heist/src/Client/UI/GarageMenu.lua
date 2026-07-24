--[[
	GarageMenu
	Die Werkstatt: Teile kaufen, laufende Reparaturen sehen, geklaute Teile
	einbauen oder verkaufen, Autos und Garage ausbauen.

	Der Inhalt wird komplett aus dem letzten Snapshot des Servers gezeichnet.
	Der Client haelt keinen eigenen Spielstand.
]]

local Store = require(script.Parent.Parent.Store)
local GarageRows = require(script.Parent.GarageRows)
local Theme = require(script.Parent.Theme)

local GarageMenu = {}

function GarageMenu.Init(root: ScreenGui)
	local window = Theme.panel({
		Name = "GarageMenu",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 640, 0, 520),
		Visible = false,
		Parent = root,
	})
	Theme.padding(14).Parent = window

	Theme.label({
		Name = "Title",
		Text = "Werkstatt",
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
		GarageMenu.SetVisible(false)
	end)

	local scroll = Theme.create("ScrollingFrame", {
		Name = "Content",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 40),
		Size = UDim2.new(1, 0, 1, -40),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = window,
	}, { Theme.list(Enum.FillDirection.Vertical, 8) })

	GarageMenu._window = window
	GarageMenu._scroll = scroll

	Store.Changed:Connect(function(key)
		if key == "snapshot" and window.Visible then
			GarageMenu.Render()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			GarageRows.TickRepairs()
		end
	end)
	return GarageMenu
end

function GarageMenu.SetVisible(visible: boolean)
	GarageMenu._window.Visible = visible
	if visible then
		GarageMenu.Render()
	end
end

function GarageMenu.Toggle()
	GarageMenu.SetVisible(not GarageMenu._window.Visible)
end

function GarageMenu.Render()
	local snapshot = Store.snapshot
	local scroll = GarageMenu._scroll
	if not snapshot or not scroll then
		return
	end
	table.clear(GarageRows.repairLabels)
	for _, child in scroll:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	local garage = snapshot.garage
	GarageRows.Header(scroll, nextOrder(), ("Garage: %s (Stufe %d)"):format(garage.label, garage.level))
	GarageRows.Garage(scroll, nextOrder(), garage, snapshot.cash)

	for _, car in snapshot.cars do
		GarageRows.Header(scroll, nextOrder(), ("%s (Rate x%.2f)"):format(car.displayName, car.rateMult))
		for _, part in car.parts do
			GarageRows.Slot(scroll, nextOrder(), car, part, snapshot.cash)
		end
	end

	if #snapshot.looseParts > 0 then
		GarageRows.Header(scroll, nextOrder(), "Lose Teile in der Garage")
		for _, part in snapshot.looseParts do
			GarageRows.LoosePart(scroll, nextOrder(), part)
		end
	end

	GarageRows.Header(scroll, nextOrder(), ("Autos (%d/%d Stellplaetze)"):format(#snapshot.cars, garage.carSlots))
	for _, car in snapshot.shopCars do
		if car.cost > 0 then
			GarageRows.ShopCar(scroll, nextOrder(), car, snapshot, garage.carSlots)
		end
	end
end

return GarageMenu
