--[[
	RepairMinigame
	Die Leiste, mit der man eine laufende Reparatur verkuerzt. Optik nach dem
	Vorbild der DismountBar.

	Zwei Dinge, die hier bewusst NICHT passieren:
	- Es wird keine Zeit ausgerechnet. Der Client meldet nur, wo der Marker
	  stand; wieviel das bringt, entscheidet der Server.
	- Die Leiste erscheint nur, wenn wirklich etwas zu tun ist: laufende
	  Reparatur, Schlaege uebrig, Spieler nah genug an der eigenen Werkbank.
	  Die Naehe wird hier nur fuer die Anzeige geprueft - der Server prueft sie
	  beim Schlag noch einmal.

	Der Marker haengt an Workspace:GetServerTimeNow() und derselben Formel wie
	auf dem Server (Util.RepairMarker). Deshalb muss kein Startzeitpunkt
	uebertragen werden, und beide Seiten sehen dieselbe Welle.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)

local RepairMinigame = {}

local refs = {}
local active = nil -- { carIndex, slotId, hits }

-- Die eigene Werkbank. PlotIndex setzt der Server als Attribut am Spieler.
local function workbench(): BasePart?
	local index = Players.LocalPlayer:GetAttribute("PlotIndex")
	if not index then
		return nil
	end
	local garages = Workspace:FindFirstChild("Garages")
	local plot = garages and garages:FindFirstChild("Plot" .. index)
	local bench = plot and plot:FindFirstChild("Workbench")
	return if bench and bench:IsA("BasePart") then bench else nil
end

local function nearBench(): boolean
	local bench = workbench()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not bench or not root then
		return false
	end
	return (bench.Position - (root :: BasePart).Position).Magnitude <= Config.REPAIR_MINIGAME_RANGE
end

-- Erste laufende Reparatur mit uebrigen Schlaegen. Bei mehreren gleichzeitig
-- wird bewusst nur EINE gezeigt: drei Leisten uebereinander waeren Chaos, und
-- der Spieler kann ohnehin nur eine gleichzeitig treffen.
local function pickRepair()
	local snapshot = Store.snapshot
	if not snapshot then
		return nil
	end
	for _, car in snapshot.cars do
		for _, part in car.parts do
			if part.repair and (part.repair.hits or 0) < Config.REPAIR_MINIGAME_ROUNDS then
				return { carIndex = car.carIndex, slotId = part.slotId, hits = part.repair.hits or 0 }
			end
		end
	end
	return nil
end

function RepairMinigame.Hit()
	if not active or not refs.frame or not refs.frame.Visible then
		return
	end
	local position = Util.RepairMarker(Workspace:GetServerTimeNow(), Config.REPAIR_SWEEP)
	Remotes.Get("RequestRepairTick"):FireServer(active.carIndex, active.slotId, position)
end

function RepairMinigame.Init(root: Frame)
	-- Ueber der Trage-Leiste, unter dem Zielbalken des Onboardings.
	local frame = Theme.panel({
		Name = "RepairMinigame",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -126),
		Size = UDim2.new(0.56, 0, 0, 62),
		Visible = false,
		ZIndex = 14,
		Parent = root,
	})
	Theme.constrain(frame, Vector2.new(230, 62), Vector2.new(380, 62))
	Theme.padding(8).Parent = frame

	local title = Theme.label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 16),
		Font = Theme.Fonts.bodyBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 15,
		Parent = frame,
	})

	local track = Theme.create("Frame", {
		Name = "Track",
		Position = UDim2.new(0, 0, 0, 20),
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundColor3 = Theme.Colors.bg,
		BorderSizePixel = 0,
		ZIndex = 15,
		Parent = frame,
	}) :: Frame
	Theme.corner(6).Parent = track

	-- Gruene Zone und Kern liegen mittig; die Breiten kommen aus Config, damit
	-- Anzeige und Serverpruefung nicht auseinanderlaufen koennen.
	Theme.create("Frame", {
		Name = "Zone",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(Config.REPAIR_ZONE_HALF * 2, 0, 1, 0),
		BackgroundColor3 = Theme.Colors.good,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 15,
		Parent = track,
	})
	Theme.create("Frame", {
		Name = "Core",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(Config.REPAIR_PERFECT_HALF * 2, 0, 1, 0),
		BackgroundColor3 = Theme.Colors.accent,
		BorderSizePixel = 0,
		ZIndex = 16,
		Parent = track,
	})

	local marker = Theme.create("Frame", {
		Name = "Marker",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0, 4, 1, 0),
		BackgroundColor3 = Theme.Colors.text,
		BorderSizePixel = 0,
		ZIndex = 17,
		Parent = track,
	}) :: Frame

	-- Eigener Knopf, damit es auf dem Handy ueberhaupt spielbar ist. Auf dem
	-- PC tut es zusaetzlich die Taste R (InputController).
	local button = Theme.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(0.5, 0, 0, 18),
		BackgroundColor3 = Theme.Colors.accent,
		TextColor3 = Theme.Colors.ink,
		TextSize = 12,
		Text = "SCHLAG  (R)",
		ZIndex = 16,
		Parent = frame,
	})
	button.Activated:Connect(RepairMinigame.Hit)

	refs.frame = frame
	refs.title = title
	refs.marker = marker

	local function refresh()
		active = pickRepair()
		local show = active ~= nil and nearBench()
		frame.Visible = show
		if show and active then
			title.Text = ("Mitschrauben - noch %d Schlaege"):format(
				Config.REPAIR_MINIGAME_ROUNDS - active.hits
			)
		end
	end

	Store.Changed:Connect(function(key)
		if key == "snapshot" then
			refresh()
		end
	end)

	RunService.RenderStepped:Connect(function()
		if not frame.Visible then
			return
		end
		local position = Util.RepairMarker(Workspace:GetServerTimeNow(), Config.REPAIR_SWEEP)
		marker.Position = UDim2.fromScale(position, 0)
	end)

	-- Die Naehe aendert sich beim Laufen, ohne dass ein Snapshot kommt.
	task.spawn(function()
		while true do
			task.wait(0.4)
			refresh()
		end
	end)

	refresh()
	return RepairMinigame
end

return RepairMinigame
