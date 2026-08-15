--[[
	HeatService.lua

	Zwei Uhren, sonst nichts:
	  - Zerfall  alle Balance.Heat.DecayInterval Sekunden -1 Heat fuer alle.
	  - Razzia   alle Balance.Heat.RaidCheckInterval Sekunden ein Wurf pro
	             Spieler gegen p = (Heat/100)^2 * 0.25.

	Ein Treffer nimmt 60 % vom Cash, senkt Heat um 35 und friert den Spieler
	3 s an Ort und Stelle ein. Banked bleibt unangetastet -- das ist der ganze
	Punkt des Spiels.

	Eine Razzia bricht ausserdem ab, was gerade laeuft: Deal wie Einzahlung.
	Wer mit vollem Cash und hohem Heat zur Bank rennt, kann kurz vor dem Ziel
	alles verlieren. Genau da liegt die Entscheidung.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Balance"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Modules = script.Parent
local PlayerState = require(Modules:WaitForChild("PlayerState"))

local HeatService = {}

local rng = Random.new()
local running = false

-- -------------------------------------------------------------------- Stun --

local function stun(player: Player)
	local token = PlayerState.BeginActivity(player, "stun", "Razzia", Balance.Heat.RaidStunSeconds)
	if not token then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		-- Beide, weil je nach Humanoid.UseJumpPower nur einer der Werte wirkt
		-- und der Spieler sich sonst aus dem Stun heraushuepfen kann.
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

-- ------------------------------------------------------------------ Razzia --

local function raid(player: Player, state)
	-- Erst abraeumen, was laeuft, dann den Stun setzen.
	PlayerState.ForceEndActivity(player)

	local kept = math.floor(state.cash * Balance.Heat.RaidCashKeptFraction)
	local lost = PlayerState.SetCash(player, kept)
	PlayerState.AddHeat(player, -Balance.Heat.RaidHeatLoss)

	stun(player)

	Remotes.Get(Remotes.RaidAlert):FireClient(player, {
		lost = lost,
		kept = kept,
		stunSeconds = Balance.Heat.RaidStunSeconds,
	})
	Remotes.Get(Remotes.CloseTerminal):FireClient(player)

	if lost > 0 then
		PlayerState.Notify(player, "bad", string.format("RAZZIA. -%d Cash.", lost))
	else
		PlayerState.Notify(player, "bad", "RAZZIA. Nichts zu holen.")
	end
end

-- ------------------------------------------------------------------- Start --

function HeatService.Start()
	if running then
		return
	end
	running = true

	-- Zerfall.
	task.spawn(function()
		while running do
			task.wait(Balance.Heat.DecayInterval)
			for player, state in pairs(PlayerState.GetAll()) do
				if state.heat > Balance.Heat.Min then
					PlayerState.AddHeat(player, -Balance.Heat.DecayAmount)
				end
			end
		end
	end)

	-- Razzia-Checks.
	task.spawn(function()
		while running do
			task.wait(Balance.Heat.RaidCheckInterval)
			for player, state in pairs(PlayerState.GetAll()) do
				if player.Parent and rng:NextNumber() < Balance.RaidChance(state.heat) then
					raid(player, state)
				end
			end
		end
	end)
end

function HeatService.Stop()
	running = false
end

return HeatService
