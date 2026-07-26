--[[
	DataService
	Besitzt alle Profile der Spieler auf diesem Server. Kein anderer Service
	fasst den DataStore an.

	- Laden mit Session-Lock (SessionStore). Schlaegt das Laden fehl, wird der
	  Spieler gekickt statt mit einem leeren Profil weiterzuspielen.
	- Autosave alle 60s (haelt gleichzeitig den Lock frisch).
	- BindToClose speichert alle offenen Profile beim Herunterfahren.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Signal = require(Shared.Signal)
local Util = require(Shared.Util)

local Data = script.Parent.Parent.Data
local ProfileTemplate = require(Data.ProfileTemplate)
local SessionStore = require(Data.SessionStore)

local DataService = {}
DataService.Name = "DataService"

DataService.ProfileLoaded = Signal.new() -- (player, data)

local profiles: { [number]: any } = {}
local loading: { [number]: boolean } = {}

function DataService:Init()
	self._store = SessionStore.new(Config.DATASTORE_NAME)
end

function DataService:Start()
	Players.PlayerAdded:Connect(function(player)
		self:_load(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:_load(player)
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		self:_release(player)
	end)

	task.spawn(function()
		while true do
			task.wait(Config.AUTOSAVE_INTERVAL)
			for _, player in Players:GetPlayers() do
				local data = profiles[player.UserId]
				if data then
					data.lastOnline = os.time()
					self._store:Save(player.UserId, data, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and self._store:IsMock() then
			return
		end
		local pending = 0
		for _, player in Players:GetPlayers() do
			local data = profiles[player.UserId]
			if data then
				pending += 1
				task.spawn(function()
					self:_release(player)
					pending -= 1
				end)
			end
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

function DataService:_load(player: Player)
	if profiles[player.UserId] or loading[player.UserId] then
		return
	end
	loading[player.UserId] = true

	local ok, payload = self._store:Load(player.UserId)
	loading[player.UserId] = nil

	if not player.Parent then
		-- Spieler ist waehrend des Ladens gegangen: Lock wieder freigeben.
		if ok then
			self._store:Save(player.UserId, payload or ProfileTemplate.New(), true)
		end
		return
	end

	if not ok then
		local reason = tostring(payload)
		warn(("[DataService] Laden fuer %s fehlgeschlagen: %s"):format(player.Name, reason))
		local text = if reason == "session-locked" or reason == "timeout"
			then "Dein Spielstand haengt noch in einer alten Session fest. Bitte in etwa einer Minute neu beitreten."
			else "Dein Spielstand konnte nicht geladen werden (Roblox-Datenspeicher gestoert). Bitte in ein paar Minuten neu versuchen."
		player:Kick(text)
		return
	end

	local data = Util.Reconcile(payload or ProfileTemplate.New(), ProfileTemplate.New())
	data.schemaVersion = ProfileTemplate.SCHEMA_VERSION
	if data.firstJoin == 0 then
		data.firstJoin = os.time()
	end

	profiles[player.UserId] = data
	self.ProfileLoaded:Fire(player, data)
end

function DataService:_release(player: Player)
	local data = profiles[player.UserId]
	if not data then
		return
	end
	data.lastOnline = os.time()
	profiles[player.UserId] = nil
	self._store:Save(player.UserId, data, true)
end

-- Gibt das Profil zurueck oder nil, wenn es (noch) nicht geladen ist.
function DataService:Get(player: Player)
	return profiles[player.UserId]
end

-- Wartet bis zu `timeout` Sekunden auf das Profil.
function DataService:Wait(player: Player, timeout: number?)
	local deadline = os.clock() + (timeout or 15)
	while os.clock() < deadline do
		local data = profiles[player.UserId]
		if data then
			return data
		end
		if not player.Parent then
			return nil
		end
		task.wait(0.1)
	end
	return nil
end

function DataService:ForEachProfile(callback: (Player, any) -> ())
	for _, player in Players:GetPlayers() do
		local data = profiles[player.UserId]
		if data then
			callback(player, data)
		end
	end
end

-- Nur fuer Tests/Debug: erzwingt ein Speichern.
function DataService:SaveNow(player: Player)
	local data = profiles[player.UserId]
	if not data then
		return false
	end
	data.lastOnline = os.time()
	return self._store:Save(player.UserId, data, false)
end

function DataService:IsMock(): boolean
	return self._store:IsMock()
end

return DataService
