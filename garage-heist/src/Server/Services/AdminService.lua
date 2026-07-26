--[[
	AdminService
	Werkzeuge zum Testen: Cash setzen, Garage hochziehen, Fenster sofort
	oeffnen, Profil zuruecksetzen.

	WER IST ADMIN:
	1. Der Besitzer des Spiels (game.CreatorId) - du musst nichts eintragen.
	2. Wer in Config.ADMIN_USER_IDS steht (fuer Freunde/Tester).
	3. In Roblox Studio jeder - dort spielst du auf deinem eigenen Rechner,
	   und ohne das koenntest du im Studio-Test nichts pruefen.

	Im veroeffentlichten Spiel kommt also ausser dir niemand ran, solange du
	niemanden in ADMIN_USER_IDS eintraegst.

	Sicherheitsregel: der Client schickt nur den Befehlsnamen. Jede Pruefung
	passiert hier. Ein manipulierter Client kann das Remote feuern so oft er
	will - ohne Adminrecht passiert nichts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local PartCatalog = require(Shared.PartCatalog)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local Server = script.Parent.Parent
local ProfileOps = require(Server.Data.ProfileOps)
local ProfileTemplate = require(Server.Data.ProfileTemplate)
local Throttle = require(Server.Garage.Throttle)

local AdminService = {}
AdminService.Name = "AdminService"

local MAX_CASH_GRANT = 1e9

function AdminService:Init(services)
	self.Services = services
end

function AdminService:Start()
	Throttle.Connect("AdminCommand", Config.ADMIN_COMMAND_COOLDOWN, function(player, command, value)
		self:_run(player, command, value)
	end)

	self.Services.DataService.ProfileLoaded:Connect(function(player)
		-- Der Client baut das Panel nur, wenn hier true ankommt.
		Remotes.Get("AdminState"):FireClient(player, { isAdmin = self:IsAdmin(player) })
	end)
end

function AdminService:IsAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	for _, userId in Config.ADMIN_USER_IDS do
		if userId == player.UserId then
			return true
		end
	end
	return false
end

local COMMANDS = {}

COMMANDS.cash = function(self, player, data, value)
	local amount = math.clamp(math.floor(Util.SafeNumber(value, 10000)), 1, MAX_CASH_GRANT)
	self.Services.EconomyService:AddCash(player, amount, "Admin")
	return ("+%s Cash."):format(Util.FormatCash(amount))
end

COMMANDS.level = function(self, player, data, value)
	local level = math.clamp(math.floor(Util.SafeNumber(value, 5)), 1, #Config.GARAGE_LEVELS)
	data.garageLevel = level
	return ("Garage auf Stufe %d (%s)."):format(level, Config.GARAGE_LEVELS[level].label)
end

-- Alle Slots aller Autos auf die hoechste Stufe. Damit ist Rebirth testbar,
-- ohne drei Stunden zu spielen.
COMMANDS.max = function(self, player, data)
	for carIndex in data.cars do
		for _, slotId in PartCatalog.SlotOrder do
			ProfileOps.SetPart(data, carIndex, slotId, {
				uid = Util.NewUid(),
				slotId = slotId,
				tier = PartCatalog.TierCount(slotId),
				subTier = Config.SUBTIER_COUNT,
				originalOwner = player.UserId,
			})
		end
	end
	data.repairs = {}
	data.garageLevel = #Config.GARAGE_LEVELS
	return "Alle Teile auf Maximum, Garage voll ausgebaut."
end

--[[
	Alles freischalten, was im Shop steht. Produkte wie CashSmall sind
	Einmalkaeufe und haben keinen Besitzzustand - der Grant wirkt deshalb nur
	auf die Paesse (VIP, AutoCollect, GarageLock) und auf die Anzeige. Fuer
	Cash gibt es den cash-Befehl, fuer die Reparatur das Guthaben aus Tag 5.

	Die Rechte landen im Profil, ueberleben also einen Rejoin. Begruendung
	steht in MonetizationService.
]]
COMMANDS.unlockall = function(self, player, data)
	data.adminGrants = data.adminGrants or {}
	for _, key in self.Services.MonetizationService:AllKeys() do
		data.adminGrants[key] = true
	end
	self.Services.MonetizationService:PushShop(player)
	return "Alle Paesse und Produkte freigeschaltet."
end

-- Gegenstueck, damit man den Kaufzustand wieder testen kann.
COMMANDS.lockall = function(self, player, data)
	data.adminGrants = {}
	self.Services.MonetizationService:PushShop(player)
	return "Alle Admin-Freischaltungen zurueckgenommen."
end

COMMANDS.rebirth = function(self, player, data)
	local count = ProfileOps.Rebirth(data)
	return ("Rebirth %d erzwungen."):format(count)
end

COMMANDS.heist = function(self)
	self.Services.HeistService:ForceOpen()
	return "Klau-Fenster geoeffnet."
end

COMMANDS.close = function(self)
	self.Services.HeistService:ForceClose()
	return "Klau-Fenster geschlossen."
end

COMMANDS.radar = function(self, player, data)
	self.Services.HeistService:GrantRadar(player, data)
	return "Radar-Ladung gutgeschrieben."
end

-- Setzt das Profil auf den Auslieferungszustand. Praktisch, um das Onboarding
-- immer wieder von vorne zu sehen.
COMMANDS.reset = function(self, player, data)
	local fresh = ProfileTemplate.New()
	fresh.firstJoin = data.firstJoin
	fresh.preferredPlot = data.preferredPlot
	for key in data do
		data[key] = nil
	end
	for key, value in fresh do
		data[key] = value
	end
	return "Profil zurueckgesetzt."
end

function AdminService:_run(player: Player, command, value)
	if not self:IsAdmin(player) then
		warn(("[Admin] %s (%d) hat '%s' versucht, ist aber kein Admin."):format(
			player.Name,
			player.UserId,
			tostring(command)
		))
		return
	end
	if type(command) ~= "string" then
		return
	end
	local handler = COMMANDS[command]
	if not handler then
		self.Services.EconomyService:Notify(player, ("Unbekannter Befehl: %s"):format(command), "bad")
		return
	end
	local data = self.Services.DataService:Get(player)
	if not data then
		return
	end

	local ok, message = pcall(handler, self, player, data, value)
	if not ok then
		warn(("[Admin] Befehl '%s' ist gescheitert: %s"):format(command, tostring(message)))
		self.Services.EconomyService:Notify(player, "Befehl gescheitert - siehe Konsole.", "bad")
		return
	end

	self.Services.GarageService:Refresh(player, data)
	self.Services.EconomyService:Push(player, true)
	self.Services.EconomyService:Notify(player, "[Admin] " .. tostring(message), "good")
end

return AdminService
