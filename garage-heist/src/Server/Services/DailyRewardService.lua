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

local STREAK_LENGTH = #Config.DAILY_RATE_MINUTES

--[[
	Belohnung fuer einen Kettentag.

	Cash sind Minuten der EIGENEN Rate, mit einem Boden fuer Neulinge, deren
	Rate noch bei 0 liegt. Damit ist Tag 7 fuer einen ausgebauten Spieler
	weiterhin etwas wert - vorher waren es feste 8000, die er im Leerlauf in
	unter einer Minute verdient.

	Reine Rechnung, kein Zustand: der Aufrufer entscheidet, ob ausgezahlt wird.
]]
local function rewardFor(services, player: Player, data, streak: number)
	local index = math.clamp(streak, 1, STREAK_LENGTH)
	local minutes = Config.DAILY_RATE_MINUTES[index]
	local rate = services.EconomyService:GetRate(player, data)
	local cash = math.max(math.floor(rate * minutes * 60), Config.DAILY_MIN_CASH[index])
	return cash, minutes, Config.DAILY_UNLOCKS[index]
end

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

function DailyRewardService:_state(player: Player, data)
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

	-- Der Client zeigt nur an, was hier drinsteht - gerechnet wird auf dem
	-- Server. Deshalb wandert die fertige Betragsliste mit, nicht die Formel.
	local preview = {}
	for index = 1, STREAK_LENGTH do
		local cash = rewardFor(self.Services, player, data, index)
		local unlock = Config.DAILY_UNLOCKS[index]
		preview[index] = { cash = cash, label = unlock and unlock.label or nil }
	end

	return {
		streak = streak,
		canClaim = canClaim,
		nextStreak = nextStreak,
		reward = preview[math.clamp(nextStreak, 1, STREAK_LENGTH)].cash,
		nextLabel = preview[math.clamp(nextStreak, 1, STREAK_LENGTH)].label,
		rewards = preview,
		nextInSeconds = secondsToMidnight,
	}
end

function DailyRewardService:Push(player: Player, data)
	data = data or self.Services.DataService:Get(player)
	if not data then
		return
	end
	Remotes.Get("DailyState"):FireClient(player, self:_state(player, data))
end

function DailyRewardService:Claim(player: Player)
	local data = self.Services.DataService:Get(player)
	if not data then
		return false
	end
	local state = self:_state(player, data)
	if not state.canClaim then
		self.Services.EconomyService:Notify(player, "Heute schon abgeholt. Morgen wieder.", "info")
		return false
	end

	data.daily.streak = state.nextStreak
	data.daily.lastDay = Util.UtcDay()

	local reward, minutes, unlock = rewardFor(self.Services, player, data, data.daily.streak)
	self.Services.EconomyService:AddCash(player, reward, "Daily")
	self.Services.EconomyService:Notify(
		player,
		("Tag %d der Kette: %s (%d Minuten deiner Rate)"):format(
			data.daily.streak,
			Util.FormatCash(reward),
			minutes
		),
		"good"
	)

	-- Freischaltungen aus der Tabelle. Jede schreibt genau ein Profilfeld -
	-- kein `if streak == 7` im Code.
	if unlock then
		if unlock.fenceBonus then
			data.fenceBonusUntil = os.time() + Config.DAILY_FENCE_DURATION
		end
		if unlock.instantRepair then
			data.instantRepairCharges = (data.instantRepairCharges or 0) + unlock.instantRepair
		end
		if unlock.t4Hint then
			-- Die Ladung wartet, bis wirklich ein Prototyp auftaucht. Ein
			-- Hinweis auf ein Fenster ohne T4 waere kein Hinweis.
			data.pendingT4Hint = (data.pendingT4Hint or 0) + unlock.t4Hint
		end
		self.Services.EconomyService:Notify(player, unlock.label, "good")
	end
	self:Push(player, data)
	self.Services.GarageService:Sync(player, data)
	return true
end

return DailyRewardService
