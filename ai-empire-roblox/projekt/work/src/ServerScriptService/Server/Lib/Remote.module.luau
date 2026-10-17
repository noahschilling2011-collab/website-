--!strict
-- Sicherheits-Schicht für alle Client-Anfragen:
--   1. Rate-Limit pro Spieler und Remote
--   2. Spielerdaten müssen geladen sein
--   3. Payload muss eine Tabelle sein (Felder prüft der Handler mit Guard)
--   4. Fehler im Handler werden abgefangen -> Client bekommt nur einen Code, nie einen Stacktrace

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.RateLimiter)
local ServerTypes = require(script.Parent.ServerTypes)

type Session = ServerTypes.Session
-- company = true: Aktion erst nach der Firmengründung erlaubt
export type Limits = { burst: number, perSecond: number, company: boolean? }

local Remote = {}

local folder: Folder? = nil
local limiters: { RateLimiter.Limiter } = {}
local sessionProvider: (Player) -> Session? = function(_player: Player)
	return nil
end

function Remote.setup()
	assert(folder == nil, "Remote.setup doppelt aufgerufen")
	local created = Instance.new("Folder")
	created.Name = Net.FOLDER
	for _, name in Net.FUNCTIONS do
		local fn = Instance.new("RemoteFunction")
		fn.Name = name
		fn.Parent = created
	end
	for _, name in Net.EVENTS do
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = created
	end
	created.Parent = ReplicatedStorage
	folder = created

	Players.PlayerRemoving:Connect(function(player)
		for _, limiter in limiters do
			limiter.forget(player)
		end
	end)
end

-- SessionService meldet sich hier an (kein zirkuläres require)
function Remote.setSessionProvider(provider: (Player) -> Session?)
	sessionProvider = provider
end

function Remote.bind(name: string, limits: Limits, handler: ServerTypes.Handler)
	assert(folder, "Remote.setup zuerst aufrufen")
	local fn = folder:FindFirstChild(name)
	assert(fn and fn:IsA("RemoteFunction"), "Unbekanntes Remote: " .. name)
	local limiter = RateLimiter.new(limits.burst, limits.perSecond)
	table.insert(limiters, limiter)

	fn.OnServerInvoke = function(player: Player, payload: any): ServerTypes.Result
		if not limiter.allow(player) then
			return { ok = false, err = "RATE_LIMIT" }
		end
		local session = sessionProvider(player)
		if not session or session.closed then
			return { ok = false, err = "LOADING" }
		end
		if limits.company and not session.data.company then
			return { ok = false, err = "NO_COMPANY" }
		end
		local cleanPayload: ServerTypes.Payload = if typeof(payload) == "table" then payload else {}
		local ok, result = pcall(handler, session, cleanPayload)
		if not ok then
			warn(`[Remote] {name} von {player.Name} fehlgeschlagen: {result}`)
			return { ok = false, err = "SERVER_ERROR" }
		end
		return result
	end
end

function Remote.fire(player: Player, name: string, ...: any)
	assert(folder, "Remote.setup zuerst aufrufen")
	local event = folder:FindFirstChild(name)
	if event and event:IsA("RemoteEvent") then
		event:FireClient(player, ...)
	end
end

return Remote
