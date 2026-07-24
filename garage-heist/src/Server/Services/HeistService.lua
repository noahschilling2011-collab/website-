--[[
	HeistService
	Der globale Timer. Alle 8 Minuten geht fuer 60 Sekunden jedes Garagentor
	auf. Der Server entscheidet, wann - der Client bekommt nur Zeitstempel und
	rechnet daraus seinen Countdown.

	Garage Lock (Gamepass) schliesst das eigene Tor nach 20 Sekunden wieder.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local PartCatalog = require(Shared.PartCatalog)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local Server = script.Parent.Parent
local CarryManager = require(Server.Heist.CarryManager)
local DismountManager = require(Server.Heist.DismountManager)

local HeistService = {}
HeistService.Name = "HeistService"

local function now(): number
	return workspace:GetServerTimeNow()
end

function HeistService:Init(services)
	self.Services = services
	self.Carry = CarryManager.new(services)
	self.Dismount = DismountManager.new(services, self.Carry)
	self.open = false
	self.openUntil = 0
	self.nextOpenAt = now() + Config.HEIST_FIRST_DELAY
	self.plotClosesAt = {}
	self._warned = {}
end

function HeistService:Start()
	Remotes.Get("RequestTackle").OnServerEvent:Connect(function(player)
		self.Carry:Tackle(player)
	end)
	Remotes.Get("RequestDropPart").OnServerEvent:Connect(function(player)
		self.Carry:Drop(player, "Teil abgelegt.")
	end)

	Players.PlayerAdded:Connect(function(player)
		self:_bindCharacter(player)
		task.delay(1, function()
			if player.Parent then
				self:_pushState(player)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self.Dismount:Cancel(player)
		self.Carry:HandleLeave(player)
	end)
	for _, player in Players:GetPlayers() do
		self:_bindCharacter(player)
	end

	task.spawn(function()
		-- Abgabe-Pads: liegt in der Verantwortung des Servers, nicht des Clients.
		task.wait(1)
		self:_bindLootBays()
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			self:_tick()
		end
	end)
end

function HeistService:_bindCharacter(player: Player)
	local function hook(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Connect(function()
				self.Dismount:Cancel(player)
				self.Carry:HandleDeath(player)
			end)
		end
	end
	if player.Character then
		task.spawn(hook, player.Character)
	end
	player.CharacterAdded:Connect(hook)
end

function HeistService:_bindLootBays()
	local garage = self.Services.GarageService
	for index, plot in garage.plots do
		local debounce = {}
		plot.lootBay.Touched:Connect(function(hit)
			local character = hit.Parent
			local player = character and Players:GetPlayerFromCharacter(character)
			if not player then
				return
			end
			if os.clock() - (debounce[player.UserId] or 0) < 0.5 then
				return
			end
			debounce[player.UserId] = os.clock()
			self.Carry:TryDeposit(player, index)
		end)
	end
end

function HeistService:IsOpen(): boolean
	return self.open
end

function HeistService:IsPlotOpen(plotIndex: number): boolean
	if not self.open then
		return false
	end
	local closesAt = self.plotClosesAt[plotIndex]
	if closesAt and now() >= closesAt then
		return false
	end
	return true
end

function HeistService:GetState()
	return {
		open = self.open,
		endsAt = self.openUntil,
		nextAt = self.nextOpenAt,
		serverTime = now(),
		windowLength = Config.HEIST_WINDOW,
	}
end

function HeistService:_pushState(player: Player?)
	local remote = Remotes.Get("HeistState")
	local state = self:GetState()
	if player then
		remote:FireClient(player, state)
	else
		remote:FireAllClients(state)
	end
end

function HeistService:_tick()
	local current = now()
	if self.open then
		if current >= self.openUntil then
			self:_close()
			return
		end
		-- Verriegelte Garagen: Prompts ausschalten, sobald die 20s um sind.
		for plotIndex, closesAt in self.plotClosesAt do
			if current >= closesAt and not self._warned["locked" .. plotIndex] then
				self._warned["locked" .. plotIndex] = true
				local ownerId = self.Services.GarageService:GetOwnerOfPlot(plotIndex)
				if ownerId then
					self.Services.GarageService:SetStealEnabledFor(ownerId, false)
				end
			end
		end
		return
	end

	local remaining = self.nextOpenAt - current
	for _, mark in Config.HEIST_WARN_AT do
		local key = "warn" .. mark
		if remaining <= mark and not self._warned[key] then
			self._warned[key] = true
			self:_announce(("Klau-Fenster in %s"):format(Util.FormatTime(math.max(0, math.floor(remaining)))), "info")
		end
	end
	if current >= self.nextOpenAt then
		self:_open()
	end
end

function HeistService:_open()
	self.open = true
	self.openUntil = now() + Config.HEIST_WINDOW
	self.nextOpenAt = self.openUntil + (Config.HEIST_INTERVAL - Config.HEIST_WINDOW)
	table.clear(self._warned)
	table.clear(self.plotClosesAt)

	local garage = self.Services.GarageService
	for _, player in Players:GetPlayers() do
		local plotIndex = garage:GetPlotIndexOf(player)
		if plotIndex then
			local locked = self.Services.MonetizationService:HasPass(player, "GarageLock")
			self.plotClosesAt[plotIndex] = locked and (now() + Config.GARAGE_LOCK_WINDOW) or self.openUntil
			garage:SetStealEnabledFor(player.UserId, true)
			if locked then
				self.Services.EconomyService:Notify(player, "Garage Lock: dein Tor faellt in 20s wieder zu.", "good")
			end
		end
	end

	self:_pushState()
	self:_announce("Klau-Fenster offen! 60 Sekunden.", "heist")
	self:_sendRadar()
end

function HeistService:_close()
	self.open = false
	table.clear(self._warned)
	table.clear(self.plotClosesAt)

	for _, player in Players:GetPlayers() do
		self.Dismount:Cancel(player)
		self.Services.GarageService:SetStealEnabledFor(player.UserId, false)
	end
	self.Carry:ReturnEverything()

	self:_pushState()
	self:_announce("Fenster zu. Tore sind verriegelt.", "info")
end

function HeistService:_announce(text: string, kind: string)
	Remotes.Get("Notify"):FireAllClients({ text = text, kind = kind })
end

function HeistService:OnStealPrompt(thief: Player, victim: Player, carIndex: number, slotId: string, prompt: ProximityPrompt)
	local anchor = prompt.Parent
	self.Dismount:Start(thief, victim, carIndex, slotId, anchor and anchor:IsA("BasePart") and anchor or nil)
end

-- Heist Radar: eine Ladung zeigt fuer ein Fenster die wertvollsten Teile.
function HeistService:GrantRadar(player: Player, data)
	data.pendingRadar += 1
	if self.open then
		self:_consumeRadar(player, data)
	else
		self.Services.EconomyService:Notify(player, "Heist Radar ist scharf - er meldet sich beim naechsten Fenster.", "good")
	end
end

function HeistService:_topParts()
	local entries = {}
	self.Services.DataService:ForEachProfile(function(owner, data)
		for carIndex, car in data.cars do
			for slotId, part in car.parts do
				table.insert(entries, {
					owner = owner.DisplayName,
					plotIndex = self.Services.GarageService:GetPlotIndexOf(owner),
					slotName = PartCatalog.GetSlot(slotId).displayName,
					tierName = (PartCatalog.GetTier(slotId, part.tier) or {}).name or "?",
					value = PartCatalog.GetValue(slotId, part.tier),
					carIndex = carIndex,
				})
			end
		end
	end)
	table.sort(entries, function(a, b)
		return a.value > b.value
	end)
	while #entries > Config.RADAR_TOP_COUNT do
		table.remove(entries)
	end
	return entries
end

function HeistService:_consumeRadar(player: Player, data)
	if (data.pendingRadar or 0) <= 0 then
		return
	end
	data.pendingRadar -= 1
	Remotes.Get("RadarPing"):FireClient(player, self:_topParts())
end

function HeistService:_sendRadar()
	self.Services.DataService:ForEachProfile(function(player, data)
		if (data.pendingRadar or 0) > 0 then
			self:_consumeRadar(player, data)
		end
	end)
end

return HeistService
