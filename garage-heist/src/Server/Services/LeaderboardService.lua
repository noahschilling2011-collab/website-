--[[
	LeaderboardService
	Zwei Ranglisten fuer diesen Server: teuerste Garage und meiste geklaute
	Teile heute. Beides steht auf einer Tafel im Hof und zusaetzlich in der
	Roblox-Spielerliste (leaderstats).

	Serverlokal und bewusst so: eine globale OrderedDataStore-Rangliste braucht
	Moderation und Cross-Server-Sync und gehoert nicht in die erste Version.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local ProfileOps = require(script.Parent.Parent.Data.ProfileOps)

local LeaderboardService = {}
LeaderboardService.Name = "LeaderboardService"

local TOP_COUNT = 8

function LeaderboardService:Init(services)
	self.Services = services
end

function LeaderboardService:Start()
	self:_buildBoard()

	self.Services.DataService.ProfileLoaded:Connect(function(player, data)
		self:_ensureLeaderstats(player, data)
	end)

	task.spawn(function()
		while true do
			task.wait(Config.LEADERBOARD_REFRESH)
			self:_refresh()
		end
	end)
end

function LeaderboardService:_ensureLeaderstats(player: Player, data)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end
	local cash = stats:FindFirstChild("Cash") or Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Parent = stats
	local stolen = stats:FindFirstChild("Geklaut") or Instance.new("IntValue")
	stolen.Name = "Geklaut"
	stolen.Parent = stats
end

local function makeColumn(gui, xScale, title)
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Position = UDim2.fromScale(xScale, 0.02)
	frame.Size = UDim2.fromScale(0.48, 0.96)
	frame.Parent = gui

	local header = Instance.new("TextLabel")
	header.BackgroundTransparency = 1
	header.Size = UDim2.fromScale(1, 0.14)
	header.Font = Enum.Font.GothamBold
	header.TextScaled = true
	header.TextColor3 = Color3.fromRGB(255, 210, 90)
	header.Text = title
	header.Parent = frame

	local body = Instance.new("TextLabel")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromScale(0, 0.16)
	body.Size = UDim2.fromScale(1, 0.84)
	body.Font = Enum.Font.Gotham
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextScaled = false
	body.TextSize = 28
	body.TextColor3 = Color3.fromRGB(240, 240, 245)
	body.Text = "-"
	body.Parent = frame

	return body
end

function LeaderboardService:_buildBoard()
	local board = Instance.new("Part")
	board.Name = "Leaderboard"
	board.Anchored = true
	board.Size = Vector3.new(34, 18, 1)
	board.CFrame = CFrame.new(0, 10, 0)
	board.Color = Color3.fromRGB(24, 24, 28)
	board.Material = Enum.Material.SmoothPlastic
	board.Parent = workspace

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(900, 500)
	gui.LightInfluence = 0
	gui.Parent = board

	local back = Instance.new("SurfaceGui")
	back.Face = Enum.NormalId.Back
	back.CanvasSize = Vector2.new(900, 500)
	back.LightInfluence = 0
	back.Parent = board

	self.labels = {
		richest = makeColumn(gui, 0.01, "Teuerste Garage"),
		thieves = makeColumn(gui, 0.51, "Meiste geklaute Teile heute"),
		richestBack = makeColumn(back, 0.01, "Teuerste Garage"),
		thievesBack = makeColumn(back, 0.51, "Meiste geklaute Teile heute"),
	}
end

local function renderList(entries, formatValue)
	if #entries == 0 then
		return "noch niemand"
	end
	local lines = {}
	for rank, entry in entries do
		table.insert(lines, ("%d. %s  %s"):format(rank, entry.name, formatValue(entry.value)))
	end
	return table.concat(lines, "\n")
end

function LeaderboardService:_refresh()
	local richest, thieves = {}, {}

	self.Services.DataService:ForEachProfile(function(player, data)
		ProfileOps.RollDailyStats(data)
		table.insert(richest, { name = player.DisplayName, value = ProfileOps.GarageValue(data) })
		table.insert(thieves, { name = player.DisplayName, value = data.stats.stolenToday })

		local stats = player:FindFirstChild("leaderstats")
		if stats then
			local cash = stats:FindFirstChild("Cash")
			local stolen = stats:FindFirstChild("Geklaut")
			if cash then
				cash.Value = math.floor(math.min(data.cash, 2 ^ 31 - 1))
			end
			if stolen then
				stolen.Value = data.stats.stolenToday
			end
		end
	end)

	local function sortAndTrim(list)
		table.sort(list, function(a, b)
			return a.value > b.value
		end)
		while #list > TOP_COUNT do
			table.remove(list)
		end
	end
	sortAndTrim(richest)
	sortAndTrim(thieves)

	local richestText = renderList(richest, Util.FormatCash)
	local thievesText = renderList(thieves, function(value)
		return ("%d Teile"):format(value)
	end)

	if self.labels then
		self.labels.richest.Text = richestText
		self.labels.richestBack.Text = richestText
		self.labels.thieves.Text = thievesText
		self.labels.thievesBack.Text = thievesText
	end

	Remotes.Get("LeaderboardUpdate"):FireAllClients({ richest = richest, thieves = thieves })
end

return LeaderboardService
