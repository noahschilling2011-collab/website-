--[[
	Garage Heist - Client-Bootstrap

	Der Client baut die Oberflaeche, hoert auf die Remotes und schickt
	Anfragen. Er rechnet nichts aus, was mit Geld zu tun hat - alle Zahlen in
	diesem Ordner sind Kopien vom Server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local Store = require(script.Store)
local Theme = require(script.UI.Theme)
local Toast = require(script.UI.Toast)
local HUD = require(script.UI.HUD)
local GarageMenu = require(script.UI.GarageMenu)
local ShopMenu = require(script.UI.ShopMenu)
local DailyPanel = require(script.UI.DailyPanel)
local DismountBar = require(script.UI.DismountBar)
local InfoPanel = require(script.UI.InfoPanel)
local InputController = require(script.Controllers.InputController)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local root = Theme.Root(playerGui)

Toast.Init(root)
GarageMenu.Init(root)
ShopMenu.Init(root)
DailyPanel.Init(root)
DismountBar.Init(root)

local leaderPanel = InfoPanel.new(root, "Rangliste", UDim2.new(1, -16, 0.5, 0), UDim2.new(0, 300, 0, 300))
local radarPanel = InfoPanel.new(root, "Heist Radar", UDim2.new(1, -16, 0.5, 320), UDim2.new(0, 300, 0, 190))

local function renderLeaderboard()
	local board = Store.leaderboard
	local lines = { "-- Teuerste Garage --" }
	for rank, entry in board.richest do
		table.insert(lines, ("%d. %s  %s"):format(rank, entry.name, Util.FormatCash(entry.value)))
	end
	table.insert(lines, "")
	table.insert(lines, "-- Geklaute Teile heute --")
	for rank, entry in board.thieves do
		table.insert(lines, ("%d. %s  %d"):format(rank, entry.name, entry.value))
	end
	leaderPanel:SetLines(lines)
end

HUD.Init(root, {
	toggleGarage = function()
		GarageMenu.Toggle()
	end,
	toggleShop = function()
		ShopMenu.Toggle()
	end,
	toggleDaily = function()
		DailyPanel.Toggle()
	end,
	toggleLeaderboard = function()
		leaderPanel:Toggle()
		if leaderPanel:IsVisible() then
			renderLeaderboard()
		end
	end,
})

InputController.Start({ garage = GarageMenu })

-- Remotes -----------------------------------------------------------------
Remotes.Get("ProfileSync").OnClientEvent:Connect(function(snapshot)
	Store.Set("snapshot", snapshot)
end)

Remotes.Get("CashUpdate").OnClientEvent:Connect(function(payload)
	Store.Set("cash", payload)
end)

Remotes.Get("HeistState").OnClientEvent:Connect(function(payload)
	Store.Set("heist", payload)
end)

Remotes.Get("Notify").OnClientEvent:Connect(function(payload)
	Toast.Show(payload.text, payload.kind)
end)

Remotes.Get("CarryState").OnClientEvent:Connect(function(payload)
	Store.Set("carry", payload and payload.part or nil)
end)

Remotes.Get("DismountProgress").OnClientEvent:Connect(function(payload)
	DismountBar.Handle(payload)
end)

Remotes.Get("DailyState").OnClientEvent:Connect(function(payload)
	Store.Set("daily", payload)
end)

Remotes.Get("ShopState").OnClientEvent:Connect(function(payload)
	Store.Set("shop", payload)
end)

Remotes.Get("LeaderboardUpdate").OnClientEvent:Connect(function(payload)
	Store.Set("leaderboard", payload)
	if leaderPanel:IsVisible() then
		renderLeaderboard()
	end
end)

Remotes.Get("RadarPing").OnClientEvent:Connect(function(entries)
	local lines = {}
	for rank, entry in entries do
		table.insert(lines, ("%d. %s: %s (%s)"):format(rank, entry.owner, entry.tierName, Util.FormatCash(entry.value)))
	end
	radarPanel:SetLines(lines)
	radarPanel:ShowFor(75)
end)

-- Erststart ---------------------------------------------------------------
local function looksBrandNew(snapshot): boolean
	if not snapshot then
		return false
	end
	for _, car in snapshot.cars do
		for _, part in car.parts do
			if part.tier > 0 or part.repair then
				return false
			end
		end
	end
	return true
end

task.spawn(function()
	-- Beim Start kann der Server den Handler noch nicht gesetzt haben.
	local snapshot
	for attempt = 1, 4 do
		local ok, result = pcall(function()
			return Remotes.Get("GetSnapshot"):InvokeServer()
		end)
		if ok and result then
			snapshot = result
			break
		end
		task.wait(attempt)
	end
	if snapshot then
		Store.Set("snapshot", snapshot)
		Store.Set("cash", {
			cash = snapshot.cash,
			pile = snapshot.pile,
			rate = snapshot.rate,
			autoCollect = snapshot.passes and snapshot.passes.AutoCollect or false,
		})
		if looksBrandNew(snapshot) then
			-- Ziel: erster Kauf in unter 60 Sekunden. Deshalb geht das Menue
			-- von allein auf und sagt, was zu tun ist.
			GarageMenu.SetVisible(true)
			Toast.Show("Deine Karre ist Schrott. Kauf das erste Teil - Reifen kosten 100.", "cash")
			Toast.Show("Verbaute Teile bringen Cash pro Sekunde, auch wenn du offline bist.", "info")
		end
	end
end)
