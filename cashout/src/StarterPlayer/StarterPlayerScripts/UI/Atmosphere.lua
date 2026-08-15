--[[
	Atmosphere.lua

	Die Welt reagiert auf Heat (Dokument 4.3). Alles clientseitig, alles ueber
	Lighting-Effekte und ein Rand-Frame -- kein Postprocessing-Zoo.

	    0-30    nichts
	   30-60    leichte Vignette, Saettigung -10 %
	   60-85    Vignette pulsiert im Takt des Herzschlags, ferne Sirene im Loop,
	            leiser Kontrast-Anstieg
	   85-100   roter Randpuls, Bild minimal wackelig, Sirene deutlich naeher

	Der Herzschlag-Takt kommt aus Balance.HeartbeatInterval: bei Heat 30 alle
	1,2 s, bei Heat 100 alle 0,45 s. Er treibt den Puls auch dann, wenn die
	Sound-Id noch 0 ist -- die Vignette schlaegt also von Anfang an richtig.

	Hier haengt auch der Kamera-Kick, weil er dieselbe Stellschraube benutzt
	(Humanoid.CameraOffset) wie das Wackeln.

	Die Vignette ist aus vier Rand-Frames mit Verlauf gebaut. Ein echtes
	radiales Vignetten-Bild waere eine Asset-Id, und die gibt es hier nicht.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Balance"))
local SoundCatalog = require(Shared:WaitForChild("SoundCatalog"))

local Theme = require(script.Parent:WaitForChild("Theme"))

local Atmosphere = {}

local player = Players.LocalPlayer

local started = false
local heat = 0
local pulse = 0
local nextBeat = 0

local colorCorrection: ColorCorrectionEffect
local edges: { Frame } = {}

local kickStuds = 0
local kickUntil = 0
local kickSeconds = 0

local sirenSound: Sound? = nil

-- ------------------------------------------------------------------ Aufbau --

--[[
	Vier Randstreifen mit Verlauf von aussen (deckend) nach innen (klar).
	Zusammen ergibt das eine rechteckige Vignette ohne jedes Bild-Asset.
]]
local function buildVignette(screenGui: ScreenGui)
	local root = Theme.New("Frame", {
		Name = "Vignette",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, screenGui)

	local thickness = 0.22
	local edgeSpecs = {
		{ UDim2.fromScale(0, 0), UDim2.new(1, 0, thickness, 0), 90 },
		{ UDim2.new(0, 0, 1 - thickness, 0), UDim2.new(1, 0, thickness, 0), 270 },
		{ UDim2.fromScale(0, 0), UDim2.new(thickness, 0, 1, 0), 0 },
		{ UDim2.new(1 - thickness, 0, 0, 0), UDim2.new(thickness, 0, 1, 0), 180 },
	}

	for index, spec in ipairs(edgeSpecs) do
		local edge = Theme.New("Frame", {
			Name = "Edge" .. index,
			Position = spec[1],
			Size = spec[2],
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, root) :: Frame

		Theme.New("UIGradient", {
			Rotation = spec[3],
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, edge)

		table.insert(edges, edge)
	end
end

local function setEdges(transparency: number, color: Color3)
	for _, edge in ipairs(edges) do
		edge.BackgroundTransparency = transparency
		edge.BackgroundColor3 = color
	end
end

-- ------------------------------------------------------------- Pro Frame --

local function humanoid(): Humanoid?
	local character = player.Character
	local found = character and character:FindFirstChildOfClass("Humanoid")
	return found
end

local function step(deltaTime: number)
	local now = os.clock()

	-- Herzschlag-Takt.
	local interval = Balance.HeartbeatInterval(heat)
	if interval then
		if now >= nextBeat then
			nextBeat = now + interval
			pulse = 1
			if heat >= Balance.Heat.AmbientTenseUntil then
				SoundCatalog.Play("Heartbeat")
			end
		end
		-- Abklingen bis zum naechsten Schlag.
		pulse = math.max(0, pulse - deltaTime / math.max(interval * 0.6, 0.05))
	else
		nextBeat = now
		pulse = 0
	end

	-- Vignette.
	if heat < Balance.Heat.AmbientCalmUntil then
		setEdges(1, Color3.fromRGB(0, 0, 0))
	else
		local critical = heat >= Balance.Heat.AmbientHighUntil
		local tense = heat >= Balance.Heat.AmbientTenseUntil

		-- 0 bei Ruhe, 1 bei Maximum.
		local ramp = math.clamp(
			(heat - Balance.Heat.AmbientCalmUntil) / (Balance.Heat.Max - Balance.Heat.AmbientCalmUntil),
			0,
			1
		)
		local base = 1 - ramp * Balance.Feel.VignetteMaxTransparency
		-- Erst ab "angespannt" pulsiert die Vignette mit.
		local beat = if tense then pulse * 0.18 else 0
		setEdges(
			math.clamp(base - beat, 0, 1),
			if critical then Theme.Danger else Color3.fromRGB(0, 0, 0)
		)
	end

	-- Farbe: Saettigung runter, ab "hoch" etwas Kontrast dazu.
	if heat < Balance.Heat.AmbientCalmUntil then
		colorCorrection.Saturation = 0
		colorCorrection.Contrast = 0
	else
		local ramp = math.clamp(
			(heat - Balance.Heat.AmbientCalmUntil) / (Balance.Heat.AmbientTenseUntil - Balance.Heat.AmbientCalmUntil),
			0,
			1
		)
		colorCorrection.Saturation = Balance.Feel.SaturationAtTense * ramp
		colorCorrection.Contrast = if heat >= Balance.Heat.AmbientTenseUntil then Balance.Feel.ContrastAtHigh else 0
	end

	-- Sirene ab "angespannt", naeher ab "kritisch".
	if sirenSound then
		if heat >= Balance.Heat.AmbientTenseUntil then
			sirenSound.Volume = if heat >= Balance.Heat.AmbientHighUntil then 0.6 else 0.25
			if not sirenSound.IsPlaying then
				sirenSound:Play()
			end
		elseif sirenSound.IsPlaying then
			sirenSound:Stop()
		end
	end

	-- Wackeln und Kamera-Kick teilen sich denselben Offset.
	local target = humanoid()
	if target then
		local offset = Vector3.zero

		if heat >= Balance.Heat.AmbientHighUntil then
			local amount = Balance.Feel.ShakeStudsAtCritical
			offset += Vector3.new(
				math.sin(now * 37) * amount,
				math.sin(now * 43) * amount,
				0
			)
		end

		if now < kickUntil then
			local left = (kickUntil - now) / math.max(kickSeconds, 0.001)
			offset += Vector3.new(0, -kickStuds * left, 0)
		end

		target.CameraOffset = offset
	end
end

-- ------------------------------------------------------------------- Public --

function Atmosphere.Start(screenGui: ScreenGui)
	if started then
		return
	end
	started = true

	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "CashoutHeatColor"
	colorCorrection.Saturation = 0
	colorCorrection.Contrast = 0
	colorCorrection.Parent = Lighting

	-- Sirene nur anlegen, wenn es sie gibt. Bis dahin bleibt es still.
	if SoundCatalog.Ids.SirenLoop ~= 0 then
		local sound = Instance.new("Sound")
		sound.Name = "CashoutSiren"
		sound.SoundId = "rbxassetid://" .. tostring(SoundCatalog.Ids.SirenLoop)
		sound.Looped = true
		sound.Volume = 0
		-- SoundService, nicht script: ein Sound unter einem ModuleScript ist
		-- kein zuverlaessiger 2D-Sound.
		sound.Parent = SoundService
		sirenSound = sound
	end

	buildVignette(screenGui)
	RunService.RenderStepped:Connect(step)
end

function Atmosphere.SetHeat(value: number)
	if not started then
		return
	end
	heat = math.clamp(value or 0, Balance.Heat.Min, Balance.Heat.Max)
end

--[[
	Kurzer Kamera-Kick. Dokument 5: 0,25 s bei Razzia-Start, ein zweiter,
	kuerzerer bei geglueckter Flucht.
]]
function Atmosphere.Kick(studs: number, seconds: number)
	if not started then
		return
	end
	kickStuds = studs
	kickSeconds = seconds
	kickUntil = os.clock() + seconds
end

return Atmosphere
