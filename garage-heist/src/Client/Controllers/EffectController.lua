--[[
	EffectController
	Nimmt die Effekt-Anweisungen des Servers entgegen: lokale Klaenge und den
	Kamera-Wackler beim Rempler. Reine Praesentation - hier haengt kein
	Spielzustand dran.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Audio = require(Shared.Audio)
local Remotes = require(Shared.Remotes)

local EffectController = {}

local SHAKE_TIME = 0.45

local function shake(power: number)
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local startedAt = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startedAt
		if elapsed >= SHAKE_TIME or not humanoid.Parent then
			if humanoid.Parent then
				humanoid.CameraOffset = Vector3.zero
			end
			connection:Disconnect()
			return
		end
		local decay = 1 - elapsed / SHAKE_TIME
		humanoid.CameraOffset = Vector3.new(
			math.sin(elapsed * 70) * power * decay,
			math.cos(elapsed * 55) * power * decay,
			0
		)
	end)
end

function EffectController.Start()
	Remotes.Get("Effect").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.kind == "sound" then
			Audio.PlayLocal(payload.name)
		elseif payload.kind == "shake" then
			shake(payload.power or 1)
		end
	end)
	return EffectController
end

return EffectController
