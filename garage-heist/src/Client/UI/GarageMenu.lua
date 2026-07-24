--[[
	GarageMenu
	Die Werkstatt: Teile kaufen, laufende Reparaturen sehen, geklaute Teile
	einbauen oder verkaufen, Autos und Garage ausbauen.

	Der Inhalt wird komplett aus dem letzten Snapshot des Servers gezeichnet.
	Der Client haelt keinen eigenen Spielstand.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)

local Store = require(script.Parent.Parent.Store)
local GarageRows = require(script.Parent.GarageRows)
local Theme = require(script.Parent.Theme)

local GarageMenu = {}

function GarageMenu.Init(root: Frame)
	local window = Theme.panel({
		Name = "GarageMenu",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.92, 0, 0.86, 0),
		Visible = false,
		Parent = root,
	})
	Theme.constrain(window, Vector2.new(300, 260), Vector2.new(640, 520))
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
	GarageMenu._confirm = GarageMenu._buildConfirm(root)

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

-- Bestaetigungsdialog fuer alles, was nicht rueckgaengig zu machen ist.
function GarageMenu._buildConfirm(root: Frame)
	local frame = Theme.panel({
		Name = "Confirm",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.8, 0, 0.34, 0),
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})
	Theme.constrain(frame, Vector2.new(280, 170), Vector2.new(420, 210))
	Theme.padding(16).Parent = frame

	local text = Theme.label({
		Size = UDim2.new(1, 0, 0, 100),
		TextWrapped = true,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 21,
		Parent = frame,
	})
	local yes = Theme.button({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(0.48, 0, 0, 40),
		BackgroundColor3 = Theme.Colors.heist,
		TextSize = 16,
		Text = "Ja, durchziehen",
		ZIndex = 21,
		Parent = frame,
	})
	local no = Theme.button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.new(0.48, 0, 0, 40),
		TextSize = 16,
		Text = "Abbrechen",
		ZIndex = 21,
		Parent = frame,
	})

	local confirm = { frame = frame, text = text }
	no.Activated:Connect(function()
		frame.Visible = false
	end)
	yes.Activated:Connect(function()
		frame.Visible = false
		if confirm.action then
			confirm.action()
			confirm.action = nil
		end
	end)
	return confirm
end

function GarageMenu.Ask(message: string, action)
	local confirm = GarageMenu._confirm
	confirm.text.Text = message
	confirm.action = action
	confirm.frame.Visible = true
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

	local rebirth = snapshot.rebirth
	if rebirth and (rebirth.can or rebirth.count > 0) then
		GarageRows.Header(scroll, nextOrder(), "Rebirth")
		GarageRows.Rebirth(scroll, nextOrder(), rebirth, function()
			GarageMenu.Ask(
				("Rebirth %d ausloesen?\n\nAutos, Teile, Garage und Cash gehen zurueck auf Anfang.\nDauerhaft bleibt: +%d%% Rate."):format(
					rebirth.count + 1,
					math.floor(rebirth.bonus * (rebirth.count + 1) * 100)
				),
				function()
					Remotes.Get("RequestRebirth"):FireServer()
				end
			)
		end)
	end

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
