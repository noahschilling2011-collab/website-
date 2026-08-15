--[[
	PlayerState.lua

	Haelt pro Spieler: cash, banked, heat, den getragenen Auftrag und die
	gerade laufende Interaktion. Einziger Ort, an dem diese Werte geschrieben
	werden -- alle anderen Services gehen ueber die Funktionen hier.

	Repliziert geaenderte Werte gebuendelt im Takt von
	Balance.Net.StateReplicateInterval zum Besitzer. Auftrag und Interaktion
	gehen sofort raus, weil Marker und Fortschrittsbalken daran haengen.

	Interaktionen tragen ein Token: nur wer das aktuelle Token haelt, darf sie
	beenden. Damit kann eine abgebrochene Auftragsannahme nicht die inzwischen
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

local function pushOrder(player: Player, state)
	local order = state.order
	if not order then
		Remotes.Get(Remotes.OrderChanged):FireClient(player, nil, nil)
		return
	end

	Remotes.Get(Remotes.OrderChanged):FireClient(player, {
		cardId = order.cardId,
		tierId = order.tierId,
		tierLabel = order.tierLabel,
		name = order.name,
		basePayout = order.basePayout,
		heatGain = order.heatGain,
		distance = order.distance,
	}, order.point and order.point.Part or nil)
end

local function pushState(player: Player, state)
	state.dirty = false
	Remotes.Get(Remotes.StateChanged):FireClient(player, {
		cash = state.cash,
		banked = state.banked,
		heat = state.heat,
	})
end

local function freshStats()
	return {
		bestOrder = 0,
		ordersDelivered = 0,
		-- Phase 2 / 3 fuellen diese beiden. In Phase 1 bleiben sie bei 0 und
		-- die Endtafel zeigt dafuer einen Strich.
		escapes = 0,
		narrowestEscapeStuds = -1,
		intercepts = 0,
	}
end

-- -------------------------------------------------------------- Lebenszyklus --

local function onPlayerAdded(player: Player)
	states[player] = {
		cash = Balance.Player.StartCash,
		banked = Balance.Player.StartBanked,
		heat = Balance.Player.StartHeat,
		activity = nil,
		order = nil,
		-- Wer waehrend der Sperrfrist am Rundenende joint, sieht nur zu.
		spectating = false,
		lastInterceptAt = -math.huge,
		stats = freshStats(),
		dirty = true,

		-- Ein Zeitstempel pro Aktion fuer die 0,3-s-Drossel.
		actionAt = {},
		lastThrottleWarn = -math.huge,
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

			-- Respawn beendet jede laufende Interaktion. Der Auftrag selbst
			-- bleibt bestehen -- das Paket wird von OrderService neu gehaengt.
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
	Fuer Razzia (Phase 2) und Rundenreset.
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
	Schreibt direkt aufs Konto. Nur fuer den Aufholbonus beim Late Join --
	verdientes Geld geht immer ueber BankAllCash.
]]
function PlayerState.AddBanked(player: Player, amount: number)
	local state = states[player]
	if not state or amount <= 0 then
		return
	end
	state.banked += amount
	state.dirty = true
end

--[[
	Nimmt einen Anteil vom Cash und liefert den genommenen Betrag zurueck.
	Fuer das Abfangen: der Bestohlene behaelt den Rest, seine Einzahlung laeuft
	damit zu Ende.
]]
function PlayerState.TakeCashShare(player: Player, fraction: number): number
	local state = states[player]
	if not state then
		return 0
	end
	local taken = math.floor(state.cash * fraction)
	if taken <= 0 then
		return 0
	end
	state.cash -= taken
	state.dirty = true
	return taken
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

--[[
	Zwingt eine sofortige Replikation. Nur fuer Momente, in denen der Client
	die Zahl auf den Frame genau braucht (Rundenstart, Rundenende).
]]
function PlayerState.FlushState(player: Player)
	local state = states[player]
	if state and player.Parent then
		pushState(player, state)
	end
end

-- ---------------------------------------------------------------- Drosselung --

--[[
	Dokument 7: ein Aufruf pro Spieler und Aktion pro 0,3 s.
	false = Anfrage ignorieren.
]]
function PlayerState.ConsumeAction(player: Player, action: string): boolean
	local state = states[player]
	if not state then
		return false
	end

	local now = os.clock()
	local last = state.actionAt[action]
	if last and now - last < Balance.Net.ActionCooldown then
		if now - state.lastThrottleWarn >= Balance.Net.ThrottleWarnCooldown then
			state.lastThrottleWarn = now
			PlayerState.Notify(player, "warn", "Zu schnell. Kurz durchatmen.")
		end
		return false
	end

	state.actionAt[action] = now
	return true
end

-- ------------------------------------------------------------- Interaktionen --

function PlayerState.IsBusy(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.activity ~= nil
end

--[[
	Startet eine Interaktion und liefert deren Token.
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

function PlayerState.EndActivity(player: Player, token: number)
	local state = states[player]
	if not state or not state.activity or state.activity.token ~= token then
		return
	end
	state.activity = nil
	pushActivity(player, state)
end

--[[
	Markiert die laufende Interaktion als abgebrochen. Die zustaendige Schleife
	sieht das beim naechsten Tick und raeumt selbst auf.
]]
function PlayerState.CancelActivity(player: Player)
	local state = states[player]
	if state and state.activity then
		state.activity.cancelled = true
	end
end

--[[
	Bricht sofort ab und gibt den Slot frei, damit direkt etwas anderes starten
	kann. Die alte Schleife merkt am naechsten Tick, dass ihr Token nicht mehr
	gilt, und beendet sich selbst.
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

-- ---------------------------------------------------------------- Auftraege --

function PlayerState.HasOrder(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.order ~= nil
end

function PlayerState.GetOrder(player: Player)
	local state = states[player]
	return state and state.order or nil
end

function PlayerState.SetOrder(player: Player, order)
	local state = states[player]
	if not state then
		return
	end
	state.order = order
	pushOrder(player, state)
end

function PlayerState.ClearOrder(player: Player)
	local state = states[player]
	if not state then
		return
	end
	state.order = nil
	pushOrder(player, state)
end

-- ------------------------------------------------------------------ Statistik --

--[[
	Knappste Flucht der Runde: der kleinste Vorsprung, mit dem jemand den
	Sperrkreis verlassen hat (Dokument 3.3).
]]
function PlayerState.IsSpectating(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.spectating
end

function PlayerState.SetSpectating(player: Player, value: boolean)
	local state = states[player]
	if state then
		state.spectating = value
	end
end

--[[
	Abfang-Sperre nach 3.2: 45 s zwischen zwei Versuchen. Verbraucht die Sperre
	nur, wenn der Versuch auch zaehlt.
]]
function PlayerState.CanIntercept(player: Player): boolean
	local state = states[player]
	if not state then
		return false
	end
	return os.clock() - state.lastInterceptAt >= Balance.Intercept.CooldownSeconds
end

function PlayerState.MarkIntercept(player: Player)
	local state = states[player]
	if not state then
		return
	end
	state.lastInterceptAt = os.clock()
	state.stats.intercepts += 1
end

function PlayerState.RecordEscape(player: Player, marginStuds: number)
	local state = states[player]
	if not state then
		return
	end
	state.stats.escapes += 1
	if state.stats.narrowestEscapeStuds < 0 or marginStuds < state.stats.narrowestEscapeStuds then
		state.stats.narrowestEscapeStuds = marginStuds
	end
end

function PlayerState.RecordDelivery(player: Player, payout: number)
	local state = states[player]
	if not state then
		return
	end
	state.stats.ordersDelivered += 1
	if payout > state.stats.bestOrder then
		state.stats.bestOrder = payout
	end
end

-- --------------------------------------------------------------- Rundenreset --

--[[
	Setzt einen Spieler auf den Rundenstart zurueck. Auftrag und Interaktion
	raeumt der Aufrufer ab (OrderService kennt Paket und Punkt).
]]
function PlayerState.ResetForRound(player: Player)
	local state = states[player]
	if not state then
		return
	end
	state.cash = Balance.Player.StartCash
	state.banked = Balance.Player.StartBanked
	state.heat = Balance.Player.StartHeat
	state.spectating = false
	state.lastInterceptAt = -math.huge
	state.stats = freshStats()
	state.dirty = true
	pushState(player, state)
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
