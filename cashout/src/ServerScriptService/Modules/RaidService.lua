--[[
	RaidService.lua

	Die Razzia als Fluchtfenster (Dokument 1.4).

	Alle Balance.Heat.RaidCheckInterval Sekunden ein Wurf pro Spieler gegen
	p = (Heat/100)^3 * 0.35. Trifft er:

	  1. Der Getroffene leuchtet fuer alle im Server sichtbar auf (Highlight),
	     bei ihm selbst kommen Sirene und roter Rand dazu.
	  2. Um seine Position legt sich ein Sperrkreis mit
	     Balance.Heat.RaidRingRadius, der in Balance.Heat.RaidRingSeconds
	     linear auf null schrumpft.
	  3. Beim Schliessen draussen: behaelt alles, Heat -15.
	  4. Drinnen: Cash * 0.35 bleibt uebrig, Heat -40, 3 s Stun.

	Kein NPC, kein Pathfinding -- ein schrumpfender Zylinder und ein
	Abstandsvergleich beim Schliessen.

	AUSLEGUNG, die das Dokument offen laesst: verglichen wird beim Schliessen
	gegen den ANFANGSRADIUS (40 Studs), nicht gegen den dann schon auf null
	geschrumpften Timer -- sonst waere jeder ausserhalb und die Razzia
	folgenlos. Der schrumpfende Zylinder ist die ablesbare Restzeit, der
	stehende Aussenring die Grenze. Bei WalkSpeed 16 sind 40 Studs in 2,5 s
	zu schaffen: das Fenster ist zu gewinnen, aber nur wenn man sofort losrennt
	und nicht ins Leere laeuft.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Balance"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Modules = script.Parent
local MapBuilder = require(Modules:WaitForChild("MapBuilder"))
local PlayerState = require(Modules:WaitForChild("PlayerState"))
local RoundManager = require(Modules:WaitForChild("RoundManager"))

local RaidService = {}

local rng = Random.new()
local running = false

-- [Player] = { origin, ring, highlight, token }
-- Eigene Buchfuehrung, damit das Aufraeumen nicht davon abhaengt, ob
-- PlayerState den Spieler beim Verlassen schon vergessen hat.
local active: { [Player]: any } = {}
local nextToken = 0

-- ------------------------------------------------------------------ intern --

local function flatDistance(a: Vector3, b: Vector3): number
	return (Vector3.new(a.X - b.X, 0, a.Z - b.Z)).Magnitude
end

local function highlightPlayer(player: Player)
	local character = player.Character
	if not character then
		return nil
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "CashoutRaidHighlight"
	highlight.FillColor = Color3.fromRGB(255, 60, 60)
	highlight.OutlineColor = Color3.fromRGB(255, 60, 60)
	highlight.FillTransparency = Balance.Map.RaidHighlightFill
	highlight.OutlineTransparency = 0
	highlight.Adornee = character
	highlight.Parent = character
	return highlight
end

--[[
	Raeumt Ring und Highlight ab. Vertraegt einen zweiten Aufruf.
]]
local function teardown(raid)
	if raid.ring then
		raid.ring.Model:Destroy()
		raid.ring = nil
	end
	if raid.highlight then
		raid.highlight:Destroy()
		raid.highlight = nil
	end
end

local function stun(player: Player)
	PlayerState.ForceEndActivity(player)

	local token = PlayerState.BeginActivity(player, "stun", "Festgesetzt", Balance.Heat.RaidStunSeconds)
	if not token then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		-- Beide, weil je nach Humanoid.UseJumpPower nur einer der Werte wirkt.
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	end

	task.delay(Balance.Heat.RaidStunSeconds, function()
		PlayerState.EndActivity(player, token)

		-- Nur zuruecksetzen, wenn es noch derselbe Humanoid ist. Nach einem
		-- Respawn haengt der alte im Nirgendwo und wird ignoriert.
		if humanoid and humanoid.Parent and player.Character == humanoid.Parent then
			humanoid.WalkSpeed = Balance.Player.WalkSpeed
			humanoid.JumpPower = Balance.Player.JumpPower
			humanoid.JumpHeight = Balance.Player.JumpHeight
		end
	end)
end

-- ---------------------------------------------------------------- Schliessen --

local function close(player: Player, token: number)
	local raid = active[player]
	if not raid or raid.token ~= token then
		return
	end
	active[player] = nil
	teardown(raid)

	if not player.Parent then
		return
	end

	local state = PlayerState.Get(player)
	if not state then
		return
	end

	local position = PlayerState.GetPosition(player)
	-- Ohne Character oder mit einem anderen als beim Start gilt man als drinnen:
	-- sonst waere Sterben die beste Fluchtmoeglichkeit.
	local sameCharacter = player.Character ~= nil and player.Character == raid.character
	local distance = if position and sameCharacter then flatDistance(position, raid.origin) else 0
	local margin = distance - Balance.Heat.RaidRingRadius
	local escaped = margin > 0

	if escaped then
		PlayerState.AddHeat(player, -Balance.Heat.RaidHeatLossEscaped)
		PlayerState.RecordEscape(player, margin)
		PlayerState.Notify(player, "good", string.format("Entkommen. %.0f Studs Vorsprung.", margin))
	else
		local kept = math.floor(state.cash * Balance.Heat.RaidCashKeptFraction)
		local lost = PlayerState.SetCash(player, kept)
		PlayerState.AddHeat(player, -Balance.Heat.RaidHeatLossCaught)
		stun(player)
		if lost > 0 then
			PlayerState.Notify(player, "bad", string.format("Erwischt. -%d Cash.", lost))
		else
			PlayerState.Notify(player, "bad", "Erwischt. Nichts zu holen.")
		end
	end

	Remotes.Get(Remotes.RaidEnded):FireClient(player, {
		escaped = escaped,
		marginStuds = margin,
	})
end

-- -------------------------------------------------------------------- Start --

local function begin(player: Player)
	local origin = PlayerState.GetPosition(player)
	if not origin then
		return
	end

	nextToken += 1
	local token = nextToken

	local ring = MapBuilder.CreateRaidRing(origin)
	local raid = {
		origin = origin,
		-- Merken, WELCHER Character das war. Wer im Fluchtfenster stirbt, wird am
		-- Spawn wiedergeboren -- weit weg vom Kreis. Ohne diesen Vergleich waere
		-- Sterben die zuverlaessigste Fluchtmoeglichkeit im Spiel.
		character = player.Character,
		ring = ring,
		highlight = highlightPlayer(player),
		token = token,
	}
	active[player] = raid

	-- Linear, damit die Restzeit am Radius ablesbar bleibt (Dokument 5).
	local shrink = TweenService:Create(
		ring.Timer,
		TweenInfo.new(Balance.Heat.RaidRingSeconds, Enum.EasingStyle.Linear),
		{ Size = Vector3.new(ring.Timer.Size.X, 0.05, 0.05) }
	)
	shrink:Play()

	Remotes.Get(Remotes.RaidStarted):FireClient(player, {
		startedAt = workspace:GetServerTimeNow(),
		duration = Balance.Heat.RaidRingSeconds,
		radius = Balance.Heat.RaidRingRadius,
		-- Ohne den Mittelpunkt kann der Client nicht sagen, wie weit noch
		-- fehlt. Er haette dann nur den schrumpfenden Zylinder -- und der zeigt
		-- die RESTZEIT, nicht die Grenze. Wer ihn fuer die Grenze haelt, hoert
		-- bei rund 27 Studs auf zu rennen und wird erwischt.
		origin = origin,
	})
	PlayerState.Notify(player, "bad", "RAZZIA. Raus aus dem Kreis.")

	task.delay(Balance.Heat.RaidRingSeconds, close, player, token)
end

-- ---------------------------------------------------------------- Aufraeumen --

--[[
	Bricht eine laufende Razzia folgenlos ab. Fuer Rundenwechsel und fuer
	Spieler, die den Server verlassen -- niemand soll fuer eine Razzia bezahlen,
	die es nicht mehr gibt.
]]
local function abort(player: Player)
	local raid = active[player]
	if not raid then
		return
	end
	active[player] = nil
	teardown(raid)

	-- Der Client haelt seinen roten Rand, bis RaidEnded kommt. Ohne diese
	-- Meldung stuende die Gefahrenanzeige die ganze Pause ueber im Bild --
	-- fuer eine Razzia, die es nicht mehr gibt.
	if player.Parent then
		Remotes.Get(Remotes.RaidEnded):FireClient(player, {
			escaped = true,
			aborted = true,
			marginStuds = 0,
		})
	end
end

local function abortAll()
	for player, _ in pairs(table.clone(active)) do
		abort(player)
	end
	-- Guertel und Hosentraeger, falls ein Ring seinen Eintrag ueberlebt hat.
	MapBuilder.ClearRaidRings()
	table.clear(active)
end

-- -------------------------------------------------------------------- Public --

function RaidService.Start()
	if running then
		return
	end
	running = true

	Players.PlayerRemoving:Connect(abort)
	RoundManager.OnRoundStart(abortAll)
	RoundManager.OnRoundEnd(abortAll)

	task.spawn(function()
		while running do
			task.wait(Balance.Heat.RaidCheckInterval)
			if RoundManager.IsRunning() then
				for player, state in pairs(PlayerState.GetAll()) do
					if
						player.Parent
						and not active[player]
						and rng:NextNumber() < Balance.RaidChance(state.heat)
					then
						begin(player)
					end
				end
			end
		end
	end)
end

function RaidService.Stop()
	running = false
end

function RaidService.IsRaided(player: Player): boolean
	return active[player] ~= nil
end

return RaidService
