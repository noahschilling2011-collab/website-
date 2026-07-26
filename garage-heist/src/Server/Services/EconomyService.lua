--[[
	EconomyService
	Einziger Ort, an dem sich Cash veraendert. Der Client bekommt Zahlen nur
	zum Anzeigen - er schickt nie einen Betrag, er fragt nur nach Aktionen.

	Online: jede Sekunde wandert rate * dt in die Garagenkasse (gedeckelt).
	        Mit Auto-Collect landet es direkt auf dem Konto.
	Offline: beim Laden wird die Abwesenheit abgerechnet, exakt segmentiert an
	        Reparaturen, die waehrenddessen fertig wurden, und bei 8h gekappt.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local ProfileOps = require(script.Parent.Parent.Data.ProfileOps)
local Throttle = require(script.Parent.Parent.Garage.Throttle)

local EconomyService = {}
EconomyService.Name = "EconomyService"

function EconomyService:Init(services)
	self.Services = services
	self._lastPush = {}
	self._offlineDone = {}
	self._offlineRunning = {}
end

function EconomyService:Start()
	local DataService = self.Services.DataService

	DataService.ProfileLoaded:Connect(function(player, data)
		self:EnsureOfflineApplied(player, data)
		self:Push(player, true)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._lastPush[player.UserId] = nil
		self._offlineDone[player.UserId] = nil
		self._offlineRunning[player.UserId] = nil
	end)

	Throttle.Connect("RequestCollect", Config.COLLECT_COOLDOWN, function(player)
		self:Collect(player)
	end)

	task.spawn(function()
		while true do
			local dt = task.wait(Config.ACCRUAL_TICK)
			self:_tick(dt)
		end
	end)
end

-- Cash/Sekunde inkl. Gamepass-Multiplikator.
function EconomyService:GetRate(player: Player, data): number
	data = data or self.Services.DataService:Get(player)
	if not data then
		return 0
	end
	local rate = ProfileOps.ComputeBaseRate(data)
	if self.Services.MonetizationService:HasPass(player, "VIP") then
		rate *= Config.VIP_RATE_MULT
	end
	return rate
end

function EconomyService:_tick(dt: number)
	local DataService = self.Services.DataService
	DataService:ForEachProfile(function(player, data)
		local rate = self:GetRate(player, data)
		if rate <= 0 then
			return
		end
		local earned = rate * dt
		data.stats.totalEarned += earned
		if self.Services.MonetizationService:HasPass(player, "AutoCollect") then
			data.cash += earned
		else
			local cap = rate * Config.PILE_CAP_SECONDS
			data.pile = math.min(data.pile + earned, cap)
		end
		self:Push(player)
	end)
end

-- Genau einmal pro Session. GarageService ruft das ebenfalls auf, bevor es
-- fertige Reparaturen einbaut - sonst haengt die Offline-Summe an der
-- Reihenfolge zweier Signal-Handler.
function EconomyService:EnsureOfflineApplied(player: Player, data)
	local id = player.UserId
	if self._offlineDone[id] then
		return
	end
	if self._offlineRunning[id] then
		local deadline = os.clock() + 20
		while self._offlineRunning[id] and os.clock() < deadline do
			task.wait(0.05)
		end
		return
	end
	self._offlineRunning[id] = true
	local ok, err = pcall(function()
		self:_applyOffline(player, data)
	end)
	self._offlineRunning[id] = nil
	self._offlineDone[id] = true
	if not ok then
		warn(("[EconomyService] Offline-Abrechnung fuer %s fehlgeschlagen: %s"):format(player.Name, tostring(err)))
	end
end

-- Erst wenn das true ist, darf jemand anders an data.repairs ran.
function EconomyService:IsSettled(player: Player): boolean
	return self._offlineDone[player.UserId] == true
end

function EconomyService:_applyOffline(player: Player, data)
	local now = os.time()
	local last = data.lastOnline
	if last <= 0 or now <= last then
		data.lastOnline = now
		return
	end

	-- Gamepass-Besitz vor der Rechnung sicherstellen (VIP verdoppelt die Rate).
	self.Services.MonetizationService:RefreshOwnership(player)

	local capEnd = last + Config.OFFLINE_CAP_SECONDS
	local segmentEnd = math.min(now, capEnd)
	local cursor = last
	local total = 0
	local multiplier = self.Services.MonetizationService:HasPass(player, "VIP") and Config.VIP_RATE_MULT or 1

	-- Reparaturen, die waehrend der Abwesenheit fertig wurden, aendern die Rate
	-- mittendrin. Deshalb wird pro Abschnitt gerechnet.
	for _, repair in ProfileOps.RepairsDueBefore(data, now) do
		local boundary = math.min(repair.endsAt, segmentEnd)
		if boundary > cursor then
			total += ProfileOps.ComputeBaseRate(data) * multiplier * (boundary - cursor)
			cursor = boundary
		end
		ProfileOps.FinishRepair(data, repair.carIndex, repair.slotId, player.UserId)
	end
	if segmentEnd > cursor then
		total += ProfileOps.ComputeBaseRate(data) * multiplier * (segmentEnd - cursor)
	end

	local earned = math.floor(total * Config.OFFLINE_RATE)
	data.lastOnline = now
	if earned <= 0 then
		return
	end

	data.cash += earned
	data.stats.totalEarned += earned
	self.Services.TelemetryService:Economy(player, "source", earned, data.cash, "Idle")
	local away = now - last
	local capped = away > Config.OFFLINE_CAP_SECONDS
	self:Notify(
		player,
		("Offline-Einnahmen: %s fuer %s%s"):format(
			Util.FormatCash(earned),
			Util.FormatTime(math.min(away, Config.OFFLINE_CAP_SECONDS)),
			capped and " (Deckel: 8h)" or ""
		),
		"cash"
	)
end

function EconomyService:Collect(player: Player)
	local data = self.Services.DataService:Get(player)
	if not data then
		return false
	end
	local amount = math.floor(data.pile)
	if amount <= 0 then
		return false
	end
	data.pile -= amount
	data.cash += amount
	self.Services.TelemetryService:Economy(player, "source", amount, data.cash, "Idle")
	self:Push(player, true)
	self:Notify(player, ("Kasse geleert: %s"):format(Util.FormatCash(amount)), "cash")
	return true
end

-- `source` landet in der Analytik ("Idle", "Heist", "Daily", "Robux").
function EconomyService:AddCash(player: Player, amount: number, source: string?, notifyText: string?)
	local data = self.Services.DataService:Get(player)
	if not data or amount <= 0 then
		return false
	end
	data.cash += amount
	self.Services.TelemetryService:Economy(player, "source", amount, data.cash, source or "Gameplay")
	self:Push(player, true)
	if notifyText then
		self:Notify(player, ("+%s %s"):format(Util.FormatCash(amount), notifyText), "cash")
	end
	return true
end

-- Einzige erlaubte Art, Geld auszugeben. Gibt false zurueck, wenn es nicht reicht.
function EconomyService:TrySpend(player: Player, amount: number, sink: string?): boolean
	local data = self.Services.DataService:Get(player)
	if not data then
		return false
	end
	amount = math.max(0, math.floor(Util.SafeNumber(amount, 0)))
	if data.cash < amount then
		return false
	end
	data.cash -= amount
	self.Services.TelemetryService:Economy(player, "sink", amount, data.cash, sink or "Gameplay")
	self:Push(player, true)
	return true
end

function EconomyService:Push(player: Player, force: boolean?)
	local data = self.Services.DataService:Get(player)
	if not data then
		return
	end
	local now = os.clock()
	local last = self._lastPush[player.UserId] or 0
	if not force and now - last < Config.CASH_PUSH_INTERVAL then
		return
	end
	self._lastPush[player.UserId] = now
	if data.cash >= Config.BADGE_RICH_AT then
		self.Services.TelemetryService:Award(player, "Rich")
	end
	Remotes.Get("CashUpdate"):FireClient(player, {
		cash = math.floor(data.cash),
		pile = math.floor(data.pile),
		rate = self:GetRate(player, data),
		autoCollect = self.Services.MonetizationService:HasPass(player, "AutoCollect"),
	})
end

function EconomyService:Notify(player: Player, text: string, kind: string?)
	Remotes.Get("Notify"):FireClient(player, { text = text, kind = kind or "info" })
end

return EconomyService
