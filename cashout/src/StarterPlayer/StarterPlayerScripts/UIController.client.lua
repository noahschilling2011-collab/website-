--[[
	UIController.client.lua

	Einstiegspunkt auf dem Client: legt die ScreenGui an, startet die drei
	UI-Module und verdrahtet sie mit den Remotes. Keine Spiellogik --
	der Client zeigt an und meldet Klicks, sonst nichts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

-- UI liegt neben diesem Script in StarterPlayerScripts, nicht darin.
local UI = script.Parent:WaitForChild("UI")
local DealPanel = require(UI:WaitForChild("DealPanel"))
local HeatBar = require(UI:WaitForChild("HeatBar"))
local RoundHud = require(UI:WaitForChild("RoundHud"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CashoutHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

RoundHud.Start(screenGui)
HeatBar.Start(screenGui)
DealPanel.Start(screenGui, function(terminalId, offerIndex)
	Remotes.Get(Remotes.ChooseDeal):FireServer(terminalId, offerIndex)
	-- Der Server bestaetigt per ActivityChanged bzw. CloseTerminal. Bis dahin
	-- ist das Panel zu, damit niemand zweimal klickt.
	DealPanel.Close()
end)

Remotes.Get(Remotes.StateChanged).OnClientEvent:Connect(function(state)
	RoundHud.SetState(state)
	if typeof(state) == "table" then
		HeatBar.SetHeat(state.heat)
	end
end)

Remotes.Get(Remotes.ActivityChanged).OnClientEvent:Connect(function(activity)
	RoundHud.SetActivity(activity)
	if activity then
		DealPanel.Close()
	end
end)

Remotes.Get(Remotes.OffersReady).OnClientEvent:Connect(function(terminalId, offers)
	DealPanel.Open(terminalId, offers)
end)

Remotes.Get(Remotes.CloseTerminal).OnClientEvent:Connect(function()
	DealPanel.Close()
end)

Remotes.Get(Remotes.Notify).OnClientEvent:Connect(function(kind, text)
	RoundHud.Notify(kind, text)
end)

Remotes.Get(Remotes.RaidAlert).OnClientEvent:Connect(function()
	RoundHud.FlashRaid()
end)
