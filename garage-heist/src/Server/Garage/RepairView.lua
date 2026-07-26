--[[
	RepairView
	Fortschrittsbalken direkt am Teil, solange daran geschraubt wird. Die
	Wartezeit zwischen zwei Klau-Fenstern soll als Fortschritt lesbar sein und
	nicht als Nichts.

	Quelle ist ausschliesslich data.repairs. Der Client bekommt hier nichts zu
	entscheiden - die Anzeige haengt am Server-Zustand.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PartCatalog = require(Shared.PartCatalog)

local RepairView = {}

local BAR_COLOR = Color3.fromRGB(245, 166, 35)

local function build(anchor: BasePart)
	local holder = Instance.new("Part")
	holder.Name = "RepairBar"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = anchor.CFrame * CFrame.new(0, 2.2, 0)
	holder.Parent = anchor.Parent

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(7, 1.5)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80
	gui.Parent = holder

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0.55)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.Parent = gui

	local track = Instance.new("Frame")
	track.Position = UDim2.fromScale(0.05, 0.6)
	track.Size = UDim2.fromScale(0.9, 0.3)
	track.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
	track.BorderSizePixel = 0
	track.Parent = gui

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = BAR_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = track

	return { holder = holder, label = label, fill = fill }
end

-- Legt fehlende Balken an und raeumt fertige ab.
function RepairView.Sync(view, data)
	view.repairBars = view.repairBars or {}
	local bars = view.repairBars

	local stale = {}
	for key in bars do
		if not data.repairs[key] then
			table.insert(stale, key)
		end
	end
	for _, key in stale do
		bars[key].holder:Destroy()
		bars[key] = nil
	end

	for key, repair in data.repairs do
		if not bars[key] then
			local refs = view.cars[repair.carIndex]
			local anchor = refs and refs.anchors and refs.anchors[repair.slotId]
			if anchor then
				bars[key] = build(anchor)
			end
		end
	end
	RepairView.Tick(view, data)
end

-- Fuellstand und Text aktualisieren. Wird mehrmals pro Sekunde gerufen.
function RepairView.Tick(view, data)
	local bars = view.repairBars
	if not bars then
		return
	end
	local now = os.time()
	for key, bar in bars do
		local repair = data.repairs[key]
		if repair then
			local total = math.max(1, repair.endsAt - (repair.startedAt or (repair.endsAt - 1)))
			local remaining = math.max(0, repair.endsAt - now)
			local tierDef = PartCatalog.GetTier(repair.slotId, repair.tier)
			bar.fill.Size = UDim2.fromScale(math.clamp(1 - remaining / total, 0, 1), 1)
			bar.label.Text = ("%s  %ds"):format(tierDef and tierDef.name or repair.slotId, math.ceil(remaining))
		end
	end
end

function RepairView.Clear(view)
	if not view.repairBars then
		return
	end
	for _, bar in view.repairBars do
		bar.holder:Destroy()
	end
	table.clear(view.repairBars)
end

return RepairView
