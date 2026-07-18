--!strict
-- EconomyService.luau
-- Berechnet Einwohner/Einkommen/Unlocks aus den Gebaeuden, verwaltet leaderstats,
-- schickt StateSync und laeuft den Einkommens-Tick (nur serverseitig).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("MiniCity")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Items = require(Shared:WaitForChild("Items"))

local PlotService = require(script.Parent.PlotService)
local UnlockService = require(script.Parent.UnlockService)

local EconomyService = {}

local stateSync = Remotes.StateSync()

-- ----------------------------------------------------------------------------
-- leaderstats
-- ----------------------------------------------------------------------------

function EconomyService.setupLeaderstats(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local money = Instance.new("IntValue")
	money.Name = "Geld"
	money.Parent = ls
	local pop = Instance.new("IntValue")
	pop.Name = "Einwohner"
	pop.Parent = ls
	ls.Parent = player
end

local function updateLeaderstats(player: Player, state)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		return
	end
	local money = ls:FindFirstChild("Geld") :: IntValue?
	local pop = ls:FindFirstChild("Einwohner") :: IntValue?
	if money then
		money.Value = math.floor(state.cash)
	end
	if pop then
		pop.Value = state.population
	end
end

-- ----------------------------------------------------------------------------
-- Neuberechnung + Sync
-- ----------------------------------------------------------------------------

function EconomyService.recompute(state)
	local population = 0
	local income = 0
	for _, b in state.buildings do
		local item = Items.get(b.id)
		if item then
			population += item.residents
			income += item.income
		end
	end
	state.population = population
	state.incomePerTick = income
	state.unlockedItems = UnlockService.computeUnlocked(population)
end

function EconomyService.sync(userId: number)
	local state = PlotService.getState(userId)
	if not state then
		return
	end
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return
	end
	updateLeaderstats(player, state)
	stateSync:FireClient(player, {
		cash = math.floor(state.cash),
		population = state.population,
		incomePerTick = state.incomePerTick,
		unlockedItems = state.unlockedItems,
	})
end

-- Neuberechnen und synchronisieren in einem Schritt.
function EconomyService.refresh(userId: number)
	local state = PlotService.getState(userId)
	if not state then
		return
	end
	EconomyService.recompute(state)
	EconomyService.sync(userId)
end

-- ----------------------------------------------------------------------------
-- Einkommens-Tick
-- ----------------------------------------------------------------------------

function EconomyService.start()
	task.spawn(function()
		while true do
			task.wait(Config.IncomeTickInterval)
			for _, player in Players:GetPlayers() do
				local state = PlotService.getState(player.UserId)
				if state then
					if state.incomePerTick > 0 then
						state.cash += state.incomePerTick
					end
					-- Immer syncen (auch ohne Einkommen): RemoteEvents puffern
					-- nicht, ein frueh verpasster Sync heilt sich so von selbst.
					EconomyService.sync(player.UserId)
				end
			end
		end
	end)
end

return EconomyService
