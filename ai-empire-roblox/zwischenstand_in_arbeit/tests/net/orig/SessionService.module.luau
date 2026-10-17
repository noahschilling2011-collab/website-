--!strict
-- Hält die geladenen Spielerdaten im Speicher, schickt Snapshots an den Client und speichert.
-- Andere Services verändern session.data und rufen danach SessionService.markDirty(session).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ModelConfig = require(ReplicatedStorage.Shared.Config.ModelConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(script.Parent.Parent.Lib.ServerTypes)
local Remote = require(script.Parent.Parent.Lib.Remote)
local SaveService = require(script.Parent.SaveService)

type Session = ServerTypes.Session

local SessionService = {}

local sessions: { [Player]: Session } = {}
local loadedCallbacks: { (Session) -> () } = {}
local closingCallbacks: { (Session) -> () } = {}

local function emptyLive(): Types.LiveInfo
	return { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} }
end

function SessionService.get(player: Player): Session?
	return sessions[player]
end

function SessionService.all(): { [Player]: Session }
	return sessions
end

function SessionService.markDirty(session: Session)
	session.dirty = true
end

function SessionService.onLoaded(callback: (Session) -> ())
	table.insert(loadedCallbacks, callback)
end

function SessionService.onClosing(callback: (Session) -> ())
	table.insert(closingCallbacks, callback)
end

-- staffProfiles können bis zu 240 Einträge haben und ändern sich nur bei Einstellen/Entlassen.
-- Regelmäßige Snapshots (delta) lassen sie weg, solange sie unverändert sind; der Client behält
-- seine letzte Kopie (StateController). RequestState schickt immer alles.
local function profileSignature(profiles: any): string
	if type(profiles) ~= "table" then
		return ""
	end
	local parts = {}
	for roleId, list in profiles do
		if type(list) == "table" then
			for i, p in list do
				if type(p) == "table" then
					table.insert(parts, `{roleId}#{i}:{p.s},{p.k},{p.w},{p.n}`)
				end
			end
		end
	end
	table.sort(parts)
	return table.concat(parts, "|")
end

function SessionService.snapshot(session: Session, delta: boolean?): Types.Snapshot
	local data = session.data
	local empire = data.empire
	if type(empire) == "table" then
		local signature = profileSignature(empire.staffProfiles)
		if delta and signature == session.profilesSent then
			local trimmed = table.clone(empire)
			trimmed.staffProfiles = nil
			trimmed.staffProfilesOmitted = true
			data = table.clone(data)
			data.empire = trimmed
		else
			session.profilesSent = signature
		end
	end
	return {
		saveEnabled = SaveService.enabled,
		serverTime = workspace:GetServerTimeNow(),
		data = data,
		live = session.live,
	}
end

-- Schickt geänderte Sessions an ihre Clients (höchstens alle REPLICATE_SECONDS)
function SessionService.flush(now: number)
	for _, session in sessions do
		if session.dirty and not session.closed and now - session.lastSent >= GameConfig.REPLICATE_SECONDS then
			session.dirty = false
			session.lastSent = now
			Remote.fire(session.player, "State", SessionService.snapshot(session, true))
		end
	end
end

local function saveSession(session: Session, release: boolean)
	local _, lostLock = SaveService.save(session.userId, session.data, release)
	if lostLock and not release then
		-- Ein anderer Server hat übernommen: hier nichts mehr verändern oder speichern
		session.closed = true
		session.player:Kick("AI Empire: Your company was opened on another server.")
	end
end

function SessionService.autosave(now: number)
	for _, session in sessions do
		if not session.saving and not session.closed and now >= session.nextSaveAt then
			session.saving = true
			session.nextSaveAt = now + GameConfig.AUTOSAVE_SECONDS
			task.spawn(function()
				saveSession(session, false)
				session.saving = false
			end)
		end
	end
end

local function onPlayerAdded(player: Player)
	local data, reason = SaveService.load(player.UserId)
	if player.Parent == nil then
		-- schon wieder weg, während wir geladen haben
		if data then
			SaveService.releaseLock(player.UserId)
		end
		return
	end
	if not data then
		player:Kick(`AI Empire: Your save could not be loaded ({reason}). Please rejoin in a minute.`)
		return
	end

	-- Ein offenes Trainings-Event aus der letzten Sitzung bekommt einen frischen Timer
	local training = data.training
	if training and training.event and training.event.pending then
		training.event.expiresAt = workspace:GetServerTimeNow() + ModelConfig.TRAINING.decisionTimeout
	end

	local now = os.clock()
	local session: Session = {
		player = player,
		userId = player.UserId,
		data = data,
		live = emptyLive(),
		dirty = true,
		lastSent = 0,
		nextSaveAt = now + GameConfig.AUTOSAVE_SECONDS + math.random() * 15, -- gestaffelt
		saving = false,
		closed = false,
		released = false,
		rng = Random.new(),
	}
	sessions[player] = session
	for _, callback in loadedCallbacks do
		task.spawn(callback, session)
	end
end

local function closeSession(player: Player)
	local session = sessions[player]
	if not session or session.released then
		return -- unbekannt oder wird schon geschlossen (PlayerRemoving + BindToClose gleichzeitig)
	end
	session.released = true
	local lockLost = session.closed -- closed ohne released = anderer Server hat übernommen
	session.closed = true
	for _, callback in closingCallbacks do
		local ok, err = pcall(callback :: (Session) -> any, session)
		if not ok then
			warn("[Session] closing callback:", err)
		end
	end
	if not lockLost then
		-- laufenden Autosave abwarten, dann final speichern und Lock freigeben
		local waited = 0
		while session.saving and waited < 15 do
			task.wait(0.2)
			waited += 0.2
		end
		session.saving = true
		saveSession(session, true)
	end
	sessions[player] = nil
end

function SessionService.init()
	Remote.setSessionProvider(function(player: Player): Session?
		return sessions[player]
	end)

	Remote.bind("RequestState", { burst = 4, perSecond = 1 }, function(session, _payload)
		return { ok = true, state = SessionService.snapshot(session) }
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(closeSession)

	game:BindToClose(function()
		local pending = 0
		local players = {}
		for player in sessions do
			table.insert(players, player)
		end
		for _, player in players do
			pending += 1
			task.spawn(function()
				closeSession(player)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.25)
		end
	end)
end

return SessionService
