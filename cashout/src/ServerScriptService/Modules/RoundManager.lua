--[[
	RoundManager.lua

	Rundenzustand, Timer, Rundenende. Einzige Autoritaet darueber, ob gerade
	gespielt wird.

	Ablauf: Wartephase (zu wenige Spieler) -> Pause -> Runde -> Endtafel,
	danach wieder Pause. Die Endtafel steht waehrend der gesamten Pause.

	Andere Services haengen sich per OnRoundStart / OnRoundEnd ein, statt dass
	RoundManager sie kennt -- das haelt die Requires zyklenfrei. Deshalb wird
	RoundManager.Start() in Main zuletzt aufgerufen.

	Der Countdown laeuft clientseitig. Der Server schickt nur bei
	Phasenwechseln und alle Balance.Round.StateResyncInterval Sekunden einen
	Zeitstempel -- das haelt die Uhr synchron, ohne jede Sekunde zu senden.

	Seit Phase 3 dazu die Late-Join-Regel aus 3.1 und das Live-Leaderboard.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Balance"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Modules = script.Parent
local MapBuilder = require(Modules:WaitForChild("MapBuilder"))
local PlayerState = require(Modules:WaitForChild("PlayerState"))

local RoundManager = {}

local running = false
local startListeners: { () -> () } = {}
local endListeners: { () -> () } = {}

local phase = "waiting"
local phaseEndsAt = 0
local roundEndsAt = 0
local lastResult: any = nil

-- ------------------------------------------------------------------ intern --

local function roundState(player: Player?)
	return {
		phase = phase,
		endsAt = phaseEndsAt,
		finalRushSeconds = Balance.Round.FinalRushSeconds,
		finalRushMultiplier = Balance.Round.FinalRushMultiplier,
		spectating = player ~= nil and PlayerState.IsSpectating(player) or false,
	}
end

local function broadcastState(player: Player?)
	local remote = Remotes.Get(Remotes.RoundState)
	if player then
		remote:FireClient(player, roundState(player))
		return
	end
	for target, _ in pairs(PlayerState.GetAll()) do
		if target.Parent then
			remote:FireClient(target, roundState(target))
		end
	end
end

--[[
	Live-Leaderboard (Phase 3): das Banked aller Mitspieler, immer sichtbar.
	Zuschauer stehen mit drin, aber ohne Wertung -- sie haben nichts eingezahlt.
]]
local function broadcastScoreboard()
	local entries = {}
	for player, state in pairs(PlayerState.GetAll()) do
		table.insert(entries, {
			userId = player.UserId,
			name = player.DisplayName,
			banked = state.banked,
			spectating = state.spectating,
		})
	end

	table.sort(entries, function(a, b)
		if a.banked == b.banked then
			return a.name < b.name
		end
		return a.banked > b.banked
	end)

	Remotes.Get(Remotes.Scoreboard):FireAllClients(entries)
end

local function fire(listeners: { () -> () }, label: string)
	for _, listener in ipairs(listeners) do
		local ok, err = pcall(listener)
		if not ok then
			warn(string.format("[CASHOUT] %s-Listener fehlgeschlagen: %s", label, tostring(err)))
		end
	end
end

--[[
	Wartet bis zum Zeitpunkt, bricht bei Stop ab und synchronisiert
	zwischendurch. Kein while true ohne Abbruchbedingung.
]]
local function waitUntil(deadline: number)
	local nextResync = os.clock() + Balance.Round.StateResyncInterval
	while running and os.clock() < deadline do
		task.wait(0.1)
		if os.clock() >= nextResync then
			nextResync = os.clock() + Balance.Round.StateResyncInterval
			broadcastState()
		end
	end
end

local function enoughPlayers(): boolean
	return #Players:GetPlayers() >= Balance.Round.MinPlayers
end

local function setPhase(newPhase: string, duration: number)
	phase = newPhase
	phaseEndsAt = workspace:GetServerTimeNow() + duration
	broadcastState()
end

-- ------------------------------------------------------------- Rundenschluss --

local function buildResult()
	local standings = {}
	local bestOrder = { value = 0, who = nil }
	local mostIntercepts = { value = 0, who = nil }
	local narrowestEscape = { value = -1, who = nil }

	for player, state in pairs(PlayerState.GetAll()) do
		table.insert(standings, {
			userId = player.UserId,
			name = player.DisplayName,
			banked = state.banked,
		})

		local stats = state.stats
		if stats.bestOrder > bestOrder.value then
			bestOrder = { value = stats.bestOrder, who = player.DisplayName }
		end
		if stats.intercepts > mostIntercepts.value then
			mostIntercepts = { value = stats.intercepts, who = player.DisplayName }
		end
		if stats.narrowestEscapeStuds >= 0 then
			if narrowestEscape.value < 0 or stats.narrowestEscapeStuds < narrowestEscape.value then
				narrowestEscape = { value = stats.narrowestEscapeStuds, who = player.DisplayName }
			end
		end
	end

	table.sort(standings, function(a, b)
		if a.banked == b.banked then
			return a.name < b.name
		end
		return a.banked > b.banked
	end)

	return {
		standings = standings,
		highlights = {
			-- Phase 1 fuellt nur bestOrder. Die anderen beiden Zeilen stehen
			-- mit who = nil in der Tafel und zeigen dort einen Strich, bis
			-- Phase 2 und 3 sie fuellen.
			bestOrder = bestOrder,
			mostIntercepts = mostIntercepts,
			narrowestEscape = narrowestEscape,
		},
	}
end

local function endRound()
	MapBuilder.SetWorldPromptsEnabled(false)

	-- Nicht eingezahlter Cash zaehlt nicht -- das wird hier sichtbar gemacht,
	-- statt es nur bei der Wertung zu ignorieren.
	for player, _ in pairs(PlayerState.GetAll()) do
		PlayerState.ForceEndActivity(player)
		PlayerState.SetCash(player, 0)
		PlayerState.FlushState(player)
	end

	fire(endListeners, "RoundEnd")

	broadcastScoreboard()
	lastResult = buildResult()
	Remotes.Get(Remotes.RoundEnded):FireAllClients(lastResult)
end

--[[
	Late Join nach 3.1. Rueckgabe: true, wenn der Spieler mitspielen darf.

	  - erste 60 s: normaler Start
	  - danach: Banked = Median aller Mitspieler * 0,5 als Aufholbonus.
	    Bewusst nicht der volle Median, sonst lohnt sich spaetes Joinen.
	  - letzte 45 s: gar kein Einstieg mehr, direkt in die Lobby
]]
local function applyLateJoin(player: Player)
	if phase ~= "running" then
		PlayerState.SetSpectating(player, false)
		return
	end

	local remaining = roundEndsAt - workspace:GetServerTimeNow()
	local elapsed = Balance.Round.DurationSeconds - remaining

	if remaining <= Balance.LateJoin.LockoutSeconds then
		PlayerState.SetSpectating(player, true)
		PlayerState.Notify(player, "info", "Runde laeuft aus. Du bist in der naechsten dabei.")
		return
	end

	PlayerState.SetSpectating(player, false)

	if elapsed <= Balance.LateJoin.GraceSeconds then
		return
	end

	local values = {}
	for other, state in pairs(PlayerState.GetAll()) do
		if other ~= player and not state.spectating then
			table.insert(values, state.banked)
		end
	end
	if #values == 0 then
		return
	end

	table.sort(values)
	local middle = #values // 2
	local median = if #values % 2 == 1 then values[middle + 1] else (values[middle] + values[middle + 1]) / 2

	local bonus = math.floor(median * Balance.LateJoin.MedianFactor)
	if bonus <= 0 then
		return
	end

	PlayerState.AddBanked(player, bonus)
	PlayerState.Notify(player, "banked", string.format("Aufholbonus: %d Banked.", bonus))
end

local function startRound()
	for player, _ in pairs(PlayerState.GetAll()) do
		PlayerState.ResetForRound(player)
	end

	fire(startListeners, "RoundStart")

	lastResult = nil
	MapBuilder.SetWorldPromptsEnabled(true)

	setPhase("running", Balance.Round.DurationSeconds)
	roundEndsAt = phaseEndsAt
	broadcastState()
	broadcastScoreboard()
end

-- ------------------------------------------------------------------ Schleife --

local function loop()
	while running do
		if not enoughPlayers() then
			setPhase("waiting", 0)
			while running and not enoughPlayers() do
				task.wait(1)
			end
			if not running then
				return
			end
		end

		setPhase("intermission", Balance.Round.IntermissionSeconds)
		waitUntil(os.clock() + Balance.Round.IntermissionSeconds)
		if not running then
			return
		end

		if not enoughPlayers() then
			-- Waehrend der Pause sind alle gegangen: zurueck in die Warteschleife.
			continue
		end

		startRound()
		waitUntil(os.clock() + Balance.Round.DurationSeconds)
		if not running then
			return
		end

		endRound()
	end
end

-- -------------------------------------------------------------------- Public --

--[[
	Wird VOR Start() von den Services aufgerufen.
]]
function RoundManager.OnRoundStart(listener: () -> ())
	table.insert(startListeners, listener)
end

function RoundManager.OnRoundEnd(listener: () -> ())
	table.insert(endListeners, listener)
end

function RoundManager.IsRunning(): boolean
	return phase == "running"
end

--[[
	Endspurt: die letzten Balance.Round.FinalRushSeconds einer Runde.
]]
function RoundManager.IsFinalRush(): boolean
	if phase ~= "running" then
		return false
	end
	return roundEndsAt - workspace:GetServerTimeNow() <= Balance.Round.FinalRushSeconds
end

--[[
	Payout-Multiplikator aus dem Rundenzustand. Ausserhalb des Endspurts 1.
]]
function RoundManager.PayoutMultiplier(): number
	return if RoundManager.IsFinalRush() then Balance.Round.FinalRushMultiplier else 1
end

function RoundManager.Start()
	if running then
		return
	end
	running = true

	Players.PlayerAdded:Connect(function(player)
		-- Frisch verbundene Clients brauchen den aktuellen Stand, sonst steht
		-- ihr Timer bis zum naechsten Resync auf null. task.defer, damit
		-- PlayerState den Spieler zuerst angelegt hat.
		task.defer(function()
			if not player.Parent then
				return
			end
			applyLateJoin(player)
			broadcastState(player)
			broadcastScoreboard()
			if lastResult then
				Remotes.Get(Remotes.RoundEnded):FireClient(player, lastResult)
			end
		end)
	end)

	task.spawn(function()
		while running do
			task.wait(Balance.Net.ScoreboardInterval)
			if phase == "running" then
				broadcastScoreboard()
			end
		end
	end)

	task.spawn(loop)
end

function RoundManager.Stop()
	running = false
end

return RoundManager
