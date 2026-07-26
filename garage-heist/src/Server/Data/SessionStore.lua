--[[
	SessionStore
	DataStore-Zugriff mit Session-Lock und Retry-Backoff.

	Ablage pro Key: { lock = { jobId, at }, payload = <Profil> }

	Regeln:
	- Laden nimmt den Lock. Haelt ihn ein anderer Server und ist er frisch,
	  wird gewartet und erneut versucht - nicht geladen.
	- Speichern prueft den Lock. Wurde er uebernommen, wird NICHT geschrieben,
	  damit zwei Server sich nicht gegenseitig ueberschreiben.
	- Ohne DataStore-Zugriff (Studio ohne API Services) faellt der Store auf
	  einen In-Memory-Modus zurueck, damit man trotzdem testen kann. Das wird
	  laut in die Konsole geschrieben.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local JOB_ID = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)

local SessionStore = {}
SessionStore.__index = SessionStore

function SessionStore.new(storeName: string)
	local self = setmetatable({}, SessionStore)
	self._mock = false
	self._mockData = {}
	self._name = storeName

	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(storeName)
	end)
	if ok and store then
		self._store = store
		local probeOk, err = pcall(function()
			return store:GetAsync("__probe__")
		end)
		if not probeOk then
			self:_enterMock(tostring(err))
		end
	else
		self:_enterMock(tostring(store))
	end
	return self
end

function SessionStore:_enterMock(reason: string)
	self._mock = true
	warn(("[SessionStore] Kein DataStore-Zugriff (%s). Fallback auf In-Memory - "):format(reason)
		.. "Fortschritt wird NICHT gespeichert. In Studio: Game Settings > Security > "
		.. "'Enable Studio Access to API Services' aktivieren.")
end

function SessionStore:IsMock(): boolean
	return self._mock
end

function SessionStore:_key(userId: number): string
	return "player_" .. tostring(userId)
end

-- Fuehrt UpdateAsync mit Retry aus. `transform` darf nil zurueckgeben, um den
-- Schreibvorgang abzubrechen (z.B. weil ein fremder Lock aktiv ist).
-- `deadline` ist ein os.clock()-Zeitpunkt. Ist er ueberschritten, wird nicht
-- mehr weiterprobiert.
function SessionStore:_update(key: string, transform: (any) -> any, deadline: number?): (boolean, any, string?)
	if self._mock then
		local current = self._mockData[key]
		local result = transform(current)
		if result == nil then
			return false, nil, "aborted"
		end
		self._mockData[key] = result
		return true, result
	end

	local lastError = "unknown"
	for attempt = 1, Config.LOAD_ATTEMPTS do
		if deadline and os.clock() >= deadline then
			return false, nil, "timeout"
		end
		local aborted = false
		local ok, result = pcall(function()
			return self._store:UpdateAsync(key, function(old)
				local transformed = transform(old)
				if transformed == nil then
					aborted = true
				end
				return transformed
			end)
		end)
		if ok and not aborted then
			return true, result
		end
		if aborted then
			return false, nil, "aborted"
		end
		lastError = tostring(result)
		warn(("[SessionStore] UpdateAsync Versuch %d/%d fehlgeschlagen: %s"):format(attempt, Config.LOAD_ATTEMPTS, lastError))
		local wait = Config.RETRY_BASE_WAIT * 2 ^ (attempt - 1)
		if deadline then
			wait = math.min(wait, math.max(0, deadline - os.clock()))
		end
		task.wait(wait)
	end
	return false, nil, lastError
end

local function lockIsForeign(entry): boolean
	local lock = entry and entry.lock
	if not lock or lock.jobId == JOB_ID then
		return false
	end
	return (os.time() - (lock.at or 0)) < Config.SESSION_LOCK_TIMEOUT
end

-- Laedt das Profil und nimmt den Lock. Gibt (true, payload) oder (false, grund).
function SessionStore:Load(userId: number)
	local key = self:_key(userId)
	local deadline = os.clock() + Config.LOAD_TOTAL_BUDGET
	for attempt = 1, Config.LOAD_ATTEMPTS do
		if os.clock() >= deadline then
			return false, "timeout"
		end
		local ok, entry, err = self:_update(key, function(old)
			if lockIsForeign(old) then
				return nil -- anderer Server haelt den Lock, spaeter erneut versuchen
			end
			local fresh = old or {}
			fresh.lock = { jobId = JOB_ID, at = os.time() }
			return fresh
		end, deadline)
		if ok and entry then
			return true, entry.payload
		end
		if err ~= "aborted" then
			return false, "datastore: " .. tostring(err)
		end
		warn(("[SessionStore] Profil %d ist von einer anderen Session gesperrt (Versuch %d)"):format(userId, attempt))
		task.wait(math.min(Config.RETRY_BASE_WAIT * attempt, math.max(0, deadline - os.clock())))
	end
	return false, "session-locked"
end

-- Schreibt das Profil. `release = true` gibt den Lock frei.
function SessionStore:Save(userId: number, payload, release: boolean?)
	local key = self:_key(userId)
	local ok, _, err = self:_update(key, function(old)
		if lockIsForeign(old) then
			return nil -- Lock wurde uebernommen: nicht ueberschreiben
		end
		local entry = old or {}
		entry.payload = payload
		if release then
			entry.lock = nil
		else
			entry.lock = { jobId = JOB_ID, at = os.time() }
		end
		return entry
	end)
	if not ok then
		if err == "aborted" then
			warn(("[SessionStore] Speichern fuer %d abgebrochen: fremder Session-Lock"):format(userId))
		else
			warn(("[SessionStore] Speichern fuer %d fehlgeschlagen: %s"):format(userId, tostring(err)))
		end
	end
	return ok
end

return SessionStore
