--[[
	GarageRows
	Die einzelnen Zeilen im Werkstatt-Menue. Jede Zeile schickt beim Klick genau
	eine Anfrage an den Server und zeigt sonst nur das an, was im Snapshot steht.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local Theme = require(script.Parent.Theme)

local GarageRows = {}

-- Labels laufender Reparaturen, damit der Countdown tickt.
GarageRows.repairLabels = {}

function GarageRows.Row(parent, order, height)
	local frame = Theme.panel({
		BackgroundColor3 = Theme.Colors.panelAlt,
		Size = UDim2.new(1, 0, 0, height or 56),
		LayoutOrder = order,
		Parent = parent,
	})
	Theme.padding(8).Parent = frame
	return frame
end

function GarageRows.Action(parent, text, color, enabled, callback)
	local button = Theme.button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 168, 0, 36),
		BackgroundColor3 = enabled and color or Color3.fromRGB(60, 62, 68),
		TextColor3 = enabled and Color3.fromRGB(20, 18, 12) or Theme.Colors.sub,
		TextSize = 14,
		Text = text,
		Parent = parent,
	})
	if enabled and callback then
		button.Activated:Connect(callback)
	end
	return button
end

function GarageRows.Header(parent, order, text)
	return Theme.label({
		Text = text,
		Size = UDim2.new(1, 0, 0, 28),
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextColor3 = Theme.Colors.accent,
		LayoutOrder = order,
		Parent = parent,
	})
end

local function twoLines(frame, title, subtitle)
	Theme.label({
		Text = title,
		Size = UDim2.new(1, -180, 0, 20),
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		Parent = frame,
	})
	return Theme.label({
		Text = subtitle,
		Position = UDim2.new(0, 0, 0, 22),
		Size = UDim2.new(1, -180, 0, 18),
		TextColor3 = Theme.Colors.sub,
		TextSize = 13,
		Parent = frame,
	})
end

function GarageRows.Slot(parent, order, car, part, cash)
	local frame = GarageRows.Row(parent, order)

	local info
	if part.repair then
		info = "wird eingebaut ..."
	elseif part.tier > 0 then
		info = ("Stufe %d  -  %s"):format(part.tier, Util.FormatRate(part.rate))
	else
		info = "leer - bringt nichts ein"
	end
	if part.inTransit then
		info = "wird gerade weggetragen"
	elseif part.stolen then
		info ..= "  (geklaut)"
	end

	-- Feinabstimmung als Punkte hinter dem Namen: Motor - Big Block V8 ..
	local title = ("%s - %s"):format(part.slotName, part.tierName)
	if (part.subTier or 0) > 0 then
		title ..= " " .. string.rep("+", part.subTier)
	end

	local subLabel = twoLines(frame, title, info)

	if part.repair then
		table.insert(GarageRows.repairLabels, { label = subLabel, endsAt = part.repair.endsAt })
		GarageRows.Action(frame, "Sofort fertig (R$)", Theme.Colors.accent, true, function()
			Remotes.Get("RequestInstantRepair"):FireServer(car.carIndex, part.slotId)
		end)
	elseif part.nextKind == "locked" then
		-- Kein toter Kaufknopf, sondern die Ansage, wo das Teil herkommt. Der
		-- Server hat die Stufe gesperrt; hier wird sie nur erklaert.
		GarageRows.Action(frame, "nur als Beute", Theme.Colors.heist, false)
		subLabel.Text ..= ("   ->  %s: aus einer fremden Box holen"):format(part.nextName or "Prototyp")
	elseif part.nextCost then
		local affordable = cash >= part.nextCost
		local prefix = part.nextKind == "sub" and "Fein " or ""
		GarageRows.Action(
			frame,
			("%s%s  %ds"):format(prefix, Util.FormatCash(part.nextCost), part.nextTime),
			affordable and Theme.Colors.good or Theme.Colors.panelAlt,
			affordable,
			function()
				Remotes.Get("RequestBuyPart"):FireServer(car.carIndex, part.slotId)
			end
		)
		if part.nextName then
			subLabel.Text ..= ("   ->  %s"):format(part.nextName)
		end
	else
		GarageRows.Action(frame, "Maximum", Theme.Colors.panelAlt, false)
	end
	return frame
end

function GarageRows.LoosePart(parent, order, part)
	local frame = GarageRows.Row(parent, order)
	twoLines(
		frame,
		("%s - %s"):format(part.slotName, part.tierName),
		part.installCarIndex and "passt in ein freies Auto" or "kein freier Platz"
	)
	if part.installCarIndex then
		GarageRows.Action(frame, "Einbauen", Theme.Colors.good, true, function()
			Remotes.Get("RequestInstallLoosePart"):FireServer(part.uid, part.installCarIndex)
		end)
	else
		GarageRows.Action(frame, ("Verkaufen %s"):format(Util.FormatCash(part.sellValue)), Theme.Colors.accent, true, function()
			Remotes.Get("RequestSellLoosePart"):FireServer(part.uid)
		end)
	end
	return frame
end

function GarageRows.ShopCar(parent, order, car, snapshot, carSlots)
	local frame = GarageRows.Row(parent, order)
	twoLines(frame, car.displayName, ("Rate x%.2f"):format(car.rateMult))
	local canBuy = snapshot.cash >= car.cost and #snapshot.cars < carSlots
	GarageRows.Action(
		frame,
		Util.FormatCash(car.cost),
		canBuy and Theme.Colors.good or Theme.Colors.panelAlt,
		canBuy,
		function()
			Remotes.Get("RequestBuyCar"):FireServer(car.carId)
		end
	)
	return frame
end

-- Rebirth-Zeile. Nur sichtbar, wenn die Bedingung erfuellt ist - sonst steht
-- hier, was noch fehlt.
function GarageRows.Rebirth(parent, order, rebirth, onConfirm)
	local frame = GarageRows.Row(parent, order, 62)
	twoLines(
		frame,
		("Rebirth %d  (dauerhaft +%d%% Rate)"):format(rebirth.count, math.floor(rebirth.bonus * 100)),
		rebirth.can and "Alles zurueck auf Anfang - der Bonus bleibt." or rebirth.reason
	)
	GarageRows.Action(
		frame,
		rebirth.can and "Rebirth" or "gesperrt",
		Theme.Colors.heist,
		rebirth.can,
		onConfirm
	)
	return frame
end

function GarageRows.Garage(parent, order, garage, cash)
	local frame = GarageRows.Row(parent, order)
	Theme.label({
		Text = ("Rate x%.2f  -  %d Stellplaetze"):format(garage.rateMult, garage.carSlots),
		Size = UDim2.new(1, -180, 1, 0),
		TextSize = 14,
		Parent = frame,
	})
	if garage.nextCost then
		local affordable = cash >= garage.nextCost
		GarageRows.Action(
			frame,
			("Ausbauen %s"):format(Util.FormatCash(garage.nextCost)),
			affordable and Theme.Colors.good or Theme.Colors.panelAlt,
			affordable,
			function()
				Remotes.Get("RequestUpgradeGarage"):FireServer()
			end
		)
	else
		GarageRows.Action(frame, "Voll ausgebaut", Theme.Colors.panelAlt, false)
	end
	return frame
end

-- endsAt kommt als Unix-Zeit vom Server, os.time() ist dieselbe Basis.
function GarageRows.TickRepairs()
	for _, entry in GarageRows.repairLabels do
		if entry.label.Parent then
			entry.label.Text = ("wird eingebaut - noch %ds"):format(math.ceil(math.max(0, entry.endsAt - os.time())))
		end
	end
end

return GarageRows
