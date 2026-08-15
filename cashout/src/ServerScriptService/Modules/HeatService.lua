--[[
	HeatService.lua

	Phase 1: nur der Zerfall.

	-1 Heat pro Balance.Heat.DecayInterval Sekunden, und **nur ausserhalb eines
	laufenden Auftrags** (Dokument 1.3). Wer durchgehend arbeitet, kuehlt nicht
	ab. Wer abkuehlen will, verliert Verdienstzeit -- das ist die zweite
	Entscheidungsachse neben dem Banken.

	Der Zerfall laeuft nur waehrend einer Runde. In der Pause bleibt Heat
	stehen; zum Rundenstart setzt PlayerState ohnehin alles zurueck.

	Die Razzia (Razzia-Check, Sperrkreis, Fluchtfenster) ist Phase 2 und steht
	bewusst noch nicht hier -- ihre Zahlen liegen aber schon in Balance.Heat.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Balance"))

local Modules = script.Parent
local PlayerState = require(Modules:WaitForChild("PlayerState"))
local RoundManager = require(Modules:WaitForChild("RoundManager"))

local HeatService = {}

local running = false

function HeatService.Start()
	if running then
		return
	end
	running = true

	task.spawn(function()
		while running do
			task.wait(Balance.Heat.DecayInterval)
			if RoundManager.IsRunning() then
				for player, state in pairs(PlayerState.GetAll()) do
					-- Ein getragener Auftrag friert den Zerfall ein.
					if state.heat > Balance.Heat.Min and not state.order then
						PlayerState.AddHeat(player, -Balance.Heat.DecayAmount)
					end
				end
			end
		end
	end)
end

function HeatService.Stop()
	running = false
end

return HeatService
