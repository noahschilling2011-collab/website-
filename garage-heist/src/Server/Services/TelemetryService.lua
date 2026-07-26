--[[
	TelemetryService
	Onboarding-Funnel, Economy-Events und Badges.

	Ohne das weisst du nach dem Launch nicht, an welcher Stelle die Spieler
	abspringen. Alles laeuft durch pcall: eine kaputte oder in Studio nicht
	verfuegbare Analytics-API darf niemals das Spiel anhalten.

	Badge-IDs stehen in Config.BADGE_IDS und sind Platzhalter (0). Was wo
	anzulegen ist, steht in docs/SETUP.md.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local TelemetryService = {}
TelemetryService.Name = "TelemetryService"

-- Reihenfolge ist die Reihenfolge im Dashboard.
local FUNNEL = "Onboarding"
local STEPS = {
	joined = { number = 1, name = "Profil geladen" },
	firstPart = { number = 2, name = "Erstes Teil gekauft" },
	firstWindow = { number = 3, name = "Erstes Klau-Fenster erlebt" },
	firstLoot = { number = 4, name = "Erstes Diebesgut abgeliefert" },
}

function TelemetryService:Init(services)
	self.Services = services
	self._sent = {} -- [userId] = { [stepKey] = true }
	self._badges = {} -- [userId] = { [badgeKey] = true }
end

function TelemetryService:Start()
	self.Services.DataService.ProfileLoaded:Connect(function(player, data)
		self:Funnel(player, "joined")
		-- Wer schon Teile hat, hat die ersten Schritte hinter sich; sonst
		-- meldet der Funnel bei jedem Rejoin einen "neuen" Spieler.
		for _, car in data.cars do
			for _ in car.parts do
				self:Funnel(player, "firstPart")
				break
			end
		end
		if (data.stats.totalStolen or 0) > 0 then
			self:Funnel(player, "firstWindow")
			self:Funnel(player, "firstLoot")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._sent[player.UserId] = nil
		self._badges[player.UserId] = nil
	end)
end

function TelemetryService:Funnel(player: Player, stepKey: string)
	local step = STEPS[stepKey]
	if not step then
		return
	end
	local sent = self._sent[player.UserId]
	if not sent then
		sent = {}
		self._sent[player.UserId] = sent
	end
	if sent[stepKey] then
		return
	end
	sent[stepKey] = true

	local ok, err = pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step.number, step.name, FUNNEL)
	end)
	if not ok then
		warn(("[Telemetry] Funnel-Schritt %s fehlgeschlagen: %s"):format(stepKey, tostring(err)))
	end
end

-- flow: "source" (Zufluss) oder "sink" (Abfluss).
function TelemetryService:Economy(player: Player, flow: string, amount: number, endingBalance: number, source: string)
	if amount <= 0 then
		return
	end
	local ok, err = pcall(function()
		local flowType = flow == "sink" and Enum.AnalyticsEconomyFlowType.Sink or Enum.AnalyticsEconomyFlowType.Source
		AnalyticsService:LogEconomyEvent(
			player,
			flowType,
			"Cash",
			math.floor(amount),
			math.floor(endingBalance),
			source
		)
	end)
	if not ok then
		warn(("[Telemetry] Economy-Event (%s/%s) fehlgeschlagen: %s"):format(flow, source, tostring(err)))
	end
end

function TelemetryService:Award(player: Player, badgeKey: string)
	local badgeId = Config.BADGE_IDS[badgeKey]
	if not badgeId or badgeId == 0 then
		return -- im Dashboard noch nicht angelegt, siehe docs/SETUP.md
	end
	local cache = self._badges[player.UserId]
	if not cache then
		cache = {}
		self._badges[player.UserId] = cache
	end
	if cache[badgeKey] then
		return
	end
	cache[badgeKey] = true

	task.spawn(function()
		local ok, owns = pcall(function()
			return BadgeService:UserHasBadgeAsync(player.UserId, badgeId)
		end)
		if ok and owns then
			return
		end
		local granted, err = pcall(function()
			BadgeService:AwardBadge(player.UserId, badgeId)
		end)
		if not granted then
			warn(("[Telemetry] Badge %s fehlgeschlagen: %s"):format(badgeKey, tostring(err)))
		end
	end)
end

return TelemetryService
