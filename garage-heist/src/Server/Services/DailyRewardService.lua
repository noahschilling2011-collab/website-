--[[
	DailyRewardService
	Sieben-Tage-Kette auf UTC-Tagen. Ein verpasster Tag setzt die Kette auf 1
	zurueck. Nach Tag 7 faengt sie wieder bei 1 an.

	Die Tagesgrenze rechnet der Server. Der Client bekommt nur, ob abgeholt
	werden kann und wie lange es noch dauert.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local Throttle = require(script.Parent.Parent.Garage.Throttle)

local DailyRewardService = {}
DailyRewardService.Name = "DailyRewardService"

local STREAK_LENGTH = #Config.DAILY_REWARDS

function DailyRewardService:Init(services)
	self.Services = services
end

function DailyRewardService:Start()
	self.Services.DataService.ProfileLoaded:Connect(function(player, data)
		task.delay(1.5, function()
			if player.Parent then
				self:Push(player, data)
			end
		end)
	end)

	Throttle.Connect("RequestClaimDaily", Config.CLAIM_COOLDOWN, function(player)
		self:Claim(player)
	end)

	task.spawn(function()
		while true do
			task.wait(60)
			self.Services.DataService:ForEachProfile(function(player, data)
				self:Push(player, data)
			end)
		end
	end)
end

function DailyRewardService:_state(data)
	local today = Util.UtcDay()
	local lastDay = data.daily.lastDay or 0
	local canClaim = lastDay < today
	local streak = data.daily.streak or 0
	local nextStreak
	if lastDay == today - 1 then
		nextStreak = (streak % STREAK_LENGTH) + 1
	else
		nextStreak = 1
	end
	if not canClaim then
		nextStreak = streak
	end
	local secondsToMidnight = ((today + 1) * 86400) - os.time()
	return {
		streak = streak,
		canClaim = canClaim,
		nextStreak = nextStreak,
		reward = Config.DAILY_REWARDS[math.clamp(nextStreak, 1, STREAK_LENGTH)],
		rewards = Config.DAILY_REWARDS,
		nextInSeconds = secondsToMidnight,
	}
end

function DailyRewardService:Push(player: Player, data)
	data = data or self.Services.DataService:Get(player)
	if not data then
		return
	end
	Remotes.Get("DailyState"):FireClient(player, self:_state(data))
end

function DailyRewardService:Claim(player: Player)
	local data = self.Services.DataService:Get(player)
	if not data then
		return false
	end
	local state = self:_state(data)
	if not state.canClaim then
		self.Services.EconomyService:Notify(player, "Heute schon abgeholt. Morgen wieder.", "info")
		return false
	end

	data.daily.streak = state.nextStreak
	data.daily.lastDay = Util.UtcDay()
	local reward = Config.DAILY_REWARDS[math.clamp(data.daily.streak, 1, STREAK_LENGTH)]
	self.Services.EconomyService:AddCash(player, reward, "Daily")
	self.Services.EconomyService:Notify(
		player,
		("Tag %d der Kette: %s"):format(data.daily.streak, Util.FormatCash(reward)),
		"good"
	)
	self:Push(player, data)
	self.Services.GarageService:Sync(player, data)
	return true
end

return DailyRewardService
