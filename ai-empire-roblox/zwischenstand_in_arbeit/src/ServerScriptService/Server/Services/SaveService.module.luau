--!strict
-- Persistenz. Nur hier wird der DataStore angefasst.
--
-- Aufbau eines Eintrags: { data = PlayerData, meta = { lockJobId, lockTime, saveCount } }
-- Session-Lock: Beim Laden schreibt der Server seine JobId in meta. Ein anderer Server, der den
-- Spieler gleichzeitig lädt (schneller Serverwechsel), wartet. Ein Lock älter als
-- SESSION_LOCK_TIMEOUT gilt als tot (Server abgestürzt) und wird übernommen.
-- Jeder Save prüft, ob der Lock noch uns gehört – sonst wird NICHT geschrieben (kein Dupe/Rollback).
--
-- Offline-Modus: In einem unveröffentlichten Ort (PlaceId 0) oder ohne Studio-API-Zugriff läuft das
-- Spiel ohne Speichern weiter, statt kaputtzugehen.

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local SESSION_ID = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local Template = require(script.Parent.Parent.Lib.Template)

local SaveService = {}
SaveService.enabled = false

local store: DataStore? = nil

local function keyFor(userId: number): string
	return GameConfig.KEY_PREFIX .. tostring(userId)
end

-- NaN/inf sind in JSON nicht speicherbar und würden den Spielstand zerstören
local function sanitize(value: any): any
	local kind = typeof(value)
	if kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return 0
		end
		return value
	elseif kind == "table" then
		local copy = {}
		for key, inner in value do
			copy[key] = sanitize(inner)
		end
		return copy
	end
	return value
end

local function waitForBudget()
	for _ = 1, 20 do
		if DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync) > 0 then
			return
		end
		task.wait(0.5)
	end
end

function SaveService.init()
	if game.PlaceId == 0 then
		warn("[Save] Unveröffentlichter Ort (PlaceId 0): Speichern ist AUS. Zum Speichern: Ort veröffentlichen.")
		return
	end
	local ok, err = pcall(function()
		local candidate = DataStoreService:GetDataStore(GameConfig.DATASTORE_NAME)
		candidate:GetAsync("__probe")
		store = candidate
	end)
	if ok then
		SaveService.enabled = true
	else
		warn("[Save] DataStore nicht erreichbar, Speichern ist AUS:", err)
	end
end

-- Lädt und sperrt den Spielstand. Gibt (Daten, nil) oder (nil, Grund) zurück.
function SaveService.load(userId: number): (Types.PlayerData?, string?)
	local activeStore = store
	if not SaveService.enabled or not activeStore then
		if RunService:IsStudio() or game.PlaceId == 0 then return Template.new(), nil end
		return nil, "storage unavailable; please rejoin"
	end
	local key = keyFor(userId)
	local jobId = SESSION_ID

	for attempt = 1, GameConfig.LOAD_ATTEMPTS do
		local lockedElsewhere = false
		local loaded: any = nil
		local invalidReason: string? = nil
		waitForBudget()
		local ok, err = pcall(function()
			activeStore:UpdateAsync(key, function(old: any)
				lockedElsewhere = false
				loaded = nil
				invalidReason = nil
				local now = os.time()
				if old ~= nil and (typeof(old) ~= "table" or typeof(old.data) ~= "table") then
					invalidReason = "invalid save; original preserved"
					return nil
				end
				if typeof(old) == "table" and typeof(old.meta) == "table" then
					local owner = old.meta.lockJobId
					local age = now - (tonumber(old.meta.lockTime) or 0)
					if owner ~= nil and owner ~= jobId and age < GameConfig.SESSION_LOCK_TIMEOUT then
						lockedElsewhere = true
						return nil -- nichts schreiben, später erneut versuchen
					end
				end
				local record = if typeof(old) == "table" then old else { data = Template.new(), meta = {} }
				local migrated, reason = Template.migrate(record.data)
				if not migrated then
					invalidReason = reason or "invalid save; original preserved"
					return nil
				end
				record.data = migrated
				if typeof(record.meta) ~= "table" then
					record.meta = {}
				end
				record.meta.lockJobId = jobId
				record.meta.lockTime = now
				loaded = record.data
				return record
			end)
		end)
		if ok and invalidReason then return nil, invalidReason end
		if ok and not lockedElsewhere then
			return loaded, nil
		end
		if not ok then
			warn(`[Save] Laden fehlgeschlagen (Versuch {attempt}): {err}`)
		end
		task.wait(GameConfig.LOAD_RETRY_SECONDS)
	end
	return nil, "save could not be loaded"
end

-- Speichert. release = true gibt den Lock frei (Spieler verlässt den Server).
-- Rückgabe: (gespeichert, Lock verloren)
function SaveService.save(userId: number, data: Types.PlayerData, release: boolean): (boolean, boolean)
	local activeStore = store
	if not SaveService.enabled or not activeStore then
		return true, false
	end
	local key = keyFor(userId)
	local jobId = SESSION_ID
	local payload = sanitize(data)

	for attempt = 1, GameConfig.SAVE_ATTEMPTS do
		local lostLock = false
		waitForBudget()
		local ok, err = pcall(function()
			activeStore:UpdateAsync(key, function(old: any)
				lostLock = false
				local meta = if typeof(old) == "table" and typeof(old.meta) == "table" then old.meta else {}
				if meta.lockJobId ~= nil and meta.lockJobId ~= jobId then
					lostLock = true
					return nil -- eine andere Session besitzt die Daten: nicht überschreiben
				end
				return {
					data = payload,
					meta = {
						lockJobId = if release then nil else jobId,
						lockTime = os.time(),
						saveCount = (tonumber(meta.saveCount) or 0) + 1,
					},
				}
			end)
		end)
		if ok then
			if lostLock then
				warn(`[Save] Lock für {userId} gehört einem anderen Server – nicht gespeichert.`)
			end
			return not lostLock, lostLock
		end
		warn(`[Save] Speichern fehlgeschlagen (Versuch {attempt}): {err}`)
		task.wait(2 ^ attempt)
	end
	return false, false
end

-- Lock freigeben, ohne Daten zu schreiben (Spieler hat den Server verlassen, bevor das Laden fertig war)
function SaveService.releaseLock(userId: number)
	local activeStore = store
	if not SaveService.enabled or not activeStore then
		return
	end
	local jobId = SESSION_ID
	pcall(function()
		activeStore:UpdateAsync(keyFor(userId), function(old: any)
			if typeof(old) == "table" and typeof(old.meta) == "table" and old.meta.lockJobId == jobId then
				old.meta.lockJobId = nil
				return old
			end
			return nil
		end)
	end)
end

return SaveService
