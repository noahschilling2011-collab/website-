--[[
	UIController.client.lua

	Einstiegspunkt auf dem Client: legt die ScreenGui an, startet die UI-Module
	und verdrahtet sie mit den Remotes. Keine Spiellogik -- der Client zeigt an
	und meldet Klicks, sonst nichts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local SoundCatalog = require(Shared:WaitForChild("SoundCatalog"))

-- UI liegt neben diesem Script in StarterPlayerScripts, nicht darin.
local UI = script.Parent:WaitForChild("UI")
local HeatBar = require(UI:WaitForChild("HeatBar"))
local OrderPanel = require(UI:WaitForChild("OrderPanel"))
local RoundEndBoard = require(UI:WaitForChild("RoundEndBoard"))
local RoundHud = require(UI:WaitForChild("RoundHud"))
local Scoreboard = require(UI:WaitForChild("Scoreboard"))

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
RoundEndBoard.Start(screenGui)
Scoreboard.Start(screenGui)
OrderPanel.Start(screenGui, function(terminalId, offerIndex)
	Remotes.Get(Remotes.ChooseOrder):FireServer(terminalId, offerIndex)
	-- Der Server bestaetigt per ActivityChanged bzw. CloseTerminal. Bis dahin
	-- ist das Panel zu, damit niemand zweimal klickt.
	OrderPanel.Close()
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
		OrderPanel.Close()
	end
end)

Remotes.Get(Remotes.OrderChanged).OnClientEvent:Connect(function(order, point)
	RoundHud.SetOrder(order, point)
end)

Remotes.Get(Remotes.OffersReady).OnClientEvent:Connect(function(terminalId, offers, terminalPosition)
	OrderPanel.Open(terminalId, offers, terminalPosition)
end)

Remotes.Get(Remotes.CloseTerminal).OnClientEvent:Connect(function()
	OrderPanel.Close()
end)

Remotes.Get(Remotes.RaidStarted).OnClientEvent:Connect(function(info)
	RoundHud.SetRaid(info)
end)

Remotes.Get(Remotes.RaidEnded).OnClientEvent:Connect(function(info)
	RoundHud.SetRaid(nil)
	SoundCatalog.Play(if info and info.escaped then "RaidEscaped" else "RaidCaught")
end)

Remotes.Get(Remotes.Scoreboard).OnClientEvent:Connect(function(entries)
	Scoreboard.Update(entries)
end)

--[[
	Zuschauer-Kamera nach 3.1: wer diese Runde nicht mitspielt, sieht von oben
	auf die Bank statt auf den eigenen Character. Wird zurueckgestellt, sobald
	die naechste Runde laeuft.
]]
local spectatorCameraActive = false

local function setSpectatorCamera(active: boolean)
	if active == spectatorCameraActive then
		return
	end
	spectatorCameraActive = active

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	if active then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(Vector3.new(0, 150, 220), Vector3.new(0, 20, 0))
	else
		camera.CameraType = Enum.CameraType.Custom
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

Remotes.Get(Remotes.RoundState).OnClientEvent:Connect(function(state)
	RoundHud.SetRound(state)
	setSpectatorCamera(typeof(state) == "table" and state.spectating == true)
	if typeof(state) == "table" and state.phase == "running" then
		-- Neue Runde: Endtafel weg, und kein Fluchtfenster ueberlebt sie.
		RoundEndBoard.Hide()
		RoundHud.SetRaid(nil)
	end
end)

Remotes.Get(Remotes.RoundEnded).OnClientEvent:Connect(function(result)
	OrderPanel.Close()
	RoundEndBoard.Show(result)
end)

Remotes.Get(Remotes.Notify).OnClientEvent:Connect(function(kind, text)
	RoundHud.Notify(kind, text)
end)
