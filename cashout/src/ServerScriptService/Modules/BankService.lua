--[[
	BankService.lua

	Einzahlen: Balance.Bank.DepositSeconds ununterbrochen im Radius stehen.
	Erfolg -> gesamter Cash wird Banked, Heat sinkt um Balance.Bank.HeatRelief.
	Weglaufen, Respawn oder Razzia brechen ab, ohne dass etwas passiert.

	Phase 3 (Abfangen) haengt spaeter hier dran: der markierte Zustand waehrend
	der acht Sekunden ist genau dieses Zeitfenster.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Balance"))

local Modules = script.Parent
local MapBuilder = require(Modules:WaitForChild("MapBuilder"))
local PlayerState = require(Modules:WaitForChild("PlayerState"))

local BankService = {}

local running = false

local function runDeposit(player: Player, bank)
	local token = PlayerState.BeginActivity(player, "deposit", "Einzahlung", Balance.Bank.DepositSeconds)
	if not token then
		return
	end

	local deadline = os.clock() + Balance.Bank.DepositSeconds
	local aborted = false

	while os.clock() < deadline do
		task.wait(Balance.Activity.CheckInterval)

		if not player.Parent or not PlayerState.Get(player) then
			return
		end
		if PlayerState.IsActivityCancelled(player, token) then
			aborted = true
			break
		end
		if not PlayerState.IsNear(player, bank.Position, Balance.Bank.Radius) then
			aborted = true
			break
		end
	end

	PlayerState.EndActivity(player, token)

	if aborted then
		PlayerState.Notify(player, "bad", "Einzahlung abgebrochen.")
		return
	end

	local amount = PlayerState.BankAllCash(player)
	PlayerState.AddHeat(player, -Balance.Bank.HeatRelief)
	PlayerState.Notify(player, "banked", string.format("+%d eingezahlt. Sicher.", amount))
end

local function onBankTriggered(bank, player: Player)
	local state = PlayerState.Get(player)
	if not state then
		return
	end
	if not PlayerState.ConsumeRequest(player) then
		return
	end

	if PlayerState.IsBusy(player) then
		PlayerState.Notify(player, "warn", "Du bist gerade beschaeftigt.")
		return
	end
	if state.cash <= 0 then
		PlayerState.Notify(player, "warn", "Nichts dabei zum Einzahlen.")
		return
	end
	if not PlayerState.IsNear(player, bank.Position, Balance.Bank.Radius) then
		return
	end

	task.spawn(runDeposit, player, bank)
end

function BankService.Start()
	if running then
		return
	end
	running = true

	local bank = MapBuilder.GetBank()
	if not bank then
		warn("[CASHOUT] BankService: keine Bank in der Map. MapBuilder.Start() zuerst aufrufen.")
		return
	end

	bank.Prompt.Triggered:Connect(function(player)
		onBankTriggered(bank, player)
	end)
end

function BankService.Stop()
	running = false
end

return BankService
