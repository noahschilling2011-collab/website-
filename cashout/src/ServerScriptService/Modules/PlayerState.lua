--[[
	PlayerState.lua

	Haelt pro Spieler: cash, banked, heat und die gerade laufende Taetigkeit
	(Deal / Einzahlung / Stun). Einziger Ort, an dem diese Werte geschrieben
	werden -- alle anderen Services gehen ueber die Funktionen hier.

	Repliziert geaenderte Werte gebuendelt im Takt von
	Balance.Net.StateReplicateInterval zum Besitzer. Aktivitaeten werden sofort
	gesendet, weil daran die Fortschrittsanzeige haengt.

	Aktivitaeten tragen ein Token: nur wer das aktuelle Token haelt, darf sie
	beenden. Damit kann eine abgebrochene Deal-Schleife nicht die inzwischen
	gestartete Einzahlung wegraeumen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Balance"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerState = {}

local states: { [Player]: any } = {}
local connections: { [Player]: { RBXScriptConnection } } = {}
local running = false
local nextToken = 0

-- ------------------------------------------------------------------ intern --

local function track(player: Player, connection: RBXScriptConnection)
	local list = connections[player]
	if list then
		table.insert(list, connection)
	else
		connection:Disconnect()
	end
end

local function serialiseActivity(state): any?
	local activity = state.activity
	if not activity then
		return nil
	end
	return {
		kind = activity.kind,
		label = activity.label,
		startedAt = activity.startedAt,
		duration = activity.duration,
	}
end

local function pushActivity(player: Player, state)
	Remotes.Get(Remotes.ActivityChanged):FireClient(player, serialiseActivity(state))
end

local function pushState(player: Player, state)
	state.dirty = false
	Remotes.Get(Remotes.StateChanged):FireClient(player, {
		cash = state.cash,
		banked = state.banked,
		heat = state.heat,
	})
end

-- -------------------------------------------------------------- Lebenszyklus --

local function onPlayerAdded(player: Player)
	states[player] = {
		cash = Balance.Player.StartCash,
		banked = Balance.Player.StartBanked,
		heat = Balance.Player.StartHeat,
		activity = nil,
		dirty = true,

		-- Token-Bucket fuers Rate-Limit.
		tokens = Balance.Net.MaxRequestsPerSecond,
		lastRefill = os.clock(),
		lastRateWarn = -math.huge,
	}
	connections[player] = {}

	track(
		player,
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 10)
			if not humanoid or not humanoid:IsA("Humanoid") then
				return
			end
			humanoid.WalkSpeed = Balance.Player.WalkSpeed
			humanoid.JumpPower = Balance.Player.JumpPower
			humanoid.JumpHeight = Balance.Player.JumpHeight

			-- Respawn beendet jede laufende Taetigkeit.
			PlayerState.CancelActivity(player)
		end)
	)
end

local function onPlayerRemoving(player: Player)
	local list = connections[player]
	if list then
		for _, connection in ipairs(list) do
			connection:Disconnect()
		end
	end
	connections[player] = nil
	states[player] = nil
end

--[[
	Startet Spielerverwaltung und Replikationsschleife. Idempotent.
]]
function PlayerState.Start()
	if running then
		return
	end
	running = true

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	task.spawn(function()
		while running do
			task.wait(Balance.Net.StateReplicateInterval)
			for player, state in pairs(states) do
				if state.dirty and player.Parent then
					pushState(player, state)
				end
			end
		end
	end)
end

function PlayerState.Stop()
	running = false
end

-- ------------------------------------------------------------------ Zugriff --

function PlayerState.Get(player: Player)
	return states[player]
end

function PlayerState.GetAll()
	return states
end

function PlayerState.AddCash(player: Player, amount: number)
	local state = states[player]
	if not state then
		return
	end
	state.cash = math.max(0, state.cash + amount)
	state.dirty = true
end

--[[
	Setzt Cash auf einen Betrag und liefert die Differenz zurueck.
	Nur fuer die Razzia gedacht, die einen Anteil einbehaelt.
]]
function PlayerState.SetCash(player: Player, amount: number): number
	local state = states[player]
	if not state then
		return 0
	end
	local before = state.cash
	state.cash = math.max(0, amount)
	state.dirty = true
	return before - state.cash
end

--[[
	Zahlt den gesamten Cash aufs Konto ein und liefert den Betrag zurueck.
]]
function PlayerState.BankAllCash(player: Player): number
	local state = states[player]
	if not state then
		return 0
	end
	local amount = state.cash
	state.cash = 0
	state.banked += amount
	state.dirty = true
	return amount
end

function PlayerState.AddHeat(player: Player, delta: number)
	local state = states[player]
	if not state then
		return
	end
	local before = state.heat
	state.heat = math.clamp(state.heat + delta, Balance.Heat.Min, Balance.Heat.Max)
	if state.heat ~= before then
		state.dirty = true
	end
end

function PlayerState.Notify(player: Player, kind: string, text: string)
	Remotes.Get(Remotes.Notify):FireClient(player, kind, text)
end

-- ---------------------------------------------------------------- Rate-Limit --

--[[
	Verbraucht ein Request-Token. false = Anfrage ignorieren.
	Warnt hoechstens einmal pro Balance.Net.RateWarnCooldown Sekunden.
]]
function PlayerState.ConsumeRequest(player: Player): boolean
	local state = states[player]
	if not state then
		return false
	end

	local now = os.clock()
	local cap = Balance.Net.MaxRequestsPerSecond
	state.tokens = math.min(cap, state.tokens + (now - state.lastRefill) * cap)
	state.lastRefill = now

	if state.tokens < 1 then
		if now - state.lastRateWarn >= Balance.Net.RateWarnCooldown then
			state.lastRateWarn = now
			PlayerState.Notify(player, "warn", "Zu viele Anfragen. Langsamer.")
		end
		return false
	end

	state.tokens -= 1
	return true
end

-- -------------------------------------------------------------- Taetigkeiten --

function PlayerState.IsBusy(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.activity ~= nil
end

--[[
	Startet eine Taetigkeit und liefert deren Token.
	nil, wenn der Spieler schon beschaeftigt ist.
]]
function PlayerState.BeginActivity(player: Player, kind: string, label: string, duration: number): number?
	local state = states[player]
	if not state or state.activity then
		return nil
	end

	nextToken += 1
	state.activity = {
		kind = kind,
		label = label,
		duration = duration,
		startedAt = workspace:GetServerTimeNow(),
		cancelled = false,
		token = nextToken,
	}
	pushActivity(player, state)
	return nextToken
end

--[[
	Beendet die Taetigkeit, falls sie noch die mit diesem Token ist.
]]
function PlayerState.EndActivity(player: Player, token: number)
	local state = states[player]
	if not state or not state.activity or state.activity.token ~= token then
		return
	end
	state.activity = nil
	pushActivity(player, state)
end

--[[
	Markiert die laufende Taetigkeit als abgebrochen. Die zustaendige Schleife
	sieht das beim naechsten Tick und raeumt selbst auf.
]]
function PlayerState.CancelActivity(player: Player)
	local state = states[player]
	if state and state.activity then
		state.activity.cancelled = true
	end
end

--[[
	Bricht sofort ab und gibt den Slot frei, damit direkt eine andere
	Taetigkeit starten kann (Razzia-Stun). Die alte Schleife merkt am naechsten
	Tick, dass ihr Token nicht mehr gilt, und beendet sich selbst.
]]
function PlayerState.ForceEndActivity(player: Player)
	local state = states[player]
	if not state or not state.activity then
		return
	end
	state.activity.cancelled = true
	state.activity = nil
	pushActivity(player, state)
end

function PlayerState.IsActivityCancelled(player: Player, token: number): boolean
	local state = states[player]
	if not state or not state.activity or state.activity.token ~= token then
		return true
	end
	return state.activity.cancelled
end

-- ------------------------------------------------------------------ Position --

--[[
	Position des Spielers oder nil, wenn er gerade keinen Character hat.
	Bewusst nicht player:DistanceFromCharacter -- das liefert 0 ohne Character
	und wuerde jeden Distanzcheck bestehen lassen.
]]
function PlayerState.GetPosition(player: Player): Vector3?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	return root.Position
end

function PlayerState.IsNear(player: Player, position: Vector3, radius: number): boolean
	local here = PlayerState.GetPosition(player)
	if not here then
		return false
	end
	return (here - position).Magnitude <= radius
end

return PlayerState
