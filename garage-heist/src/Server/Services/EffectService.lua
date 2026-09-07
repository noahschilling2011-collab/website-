--[[
	EffectService
	Funken, Partikel, Klaenge, Kamera-Wackler. Nichts hiervon entscheidet
	etwas - deshalb steht auch nichts davon in einem anderen Service.

	Partikel benutzen die eingebaute Standardtextur der Engine, keine
	hochgeladenen Assets. Klaenge laufen ueber Shared/Audio und bleiben stumm,
	solange in SoundCatalog keine ID steht.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Audio = require(Shared.Audio)
local Remotes = require(Shared.Remotes)

local EffectService = {}
EffectService.Name = "EffectService"

local SPARK_COLOR = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 110, 40))
local DEPOSIT_COLOR = ColorSequence.new(Color3.fromRGB(120, 220, 255), Color3.fromRGB(60, 140, 255))

function EffectService:Init(services)
	self.Services = services
end

function EffectService:Start() end

function EffectService:Sound(name: string, position: Vector3?)
	if position then
		Audio.PlayAt(name, position)
	end
end

-- Klang nur beim einzelnen Spieler (Kauf, Countdown, Fensteroeffnung).
function EffectService:LocalSound(player: Player, name: string)
	Remotes.Get("Effect"):FireClient(player, { kind = "sound", name = name })
end

function EffectService:LocalSoundAll(name: string)
	Remotes.Get("Effect"):FireAllClients({ kind = "sound", name = name })
end

function EffectService:Shake(player: Player, power: number)
	Remotes.Get("Effect"):FireClient(player, { kind = "shake", power = power })
end

-- Funken am Teil, solange daran geschraubt wird.
function EffectService:Sparks(anchor: BasePart?, duration: number)
	if not anchor or not anchor.Parent then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "DismountSparks"
	emitter.Color = SPARK_COLOR
	emitter.Size = NumberSequence.new(0.35, 0)
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Lifetime = NumberRange.new(0.25, 0.5)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Rate = 55
	emitter.Acceleration = Vector3.new(0, -40, 0)
	emitter.Parent = anchor

	Debris:AddItem(emitter, duration + 0.2)
	self:Sound("dismount", anchor.Position)
end

-- Kurzer Ausbruch am Abgabe-Pad.
function EffectService:Deposit(pad: BasePart?)
	if not pad then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "DepositBurst"
	emitter.Color = DEPOSIT_COLOR
	emitter.Size = NumberSequence.new(0.8, 0)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(10, 18)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Rate = 0
	emitter.Parent = pad
	emitter:Emit(45)

	Debris:AddItem(emitter, 2)
	self:Sound("deposit", pad.Position)
end

-- Leuchtspur am getragenen Teil, damit man Traeger von weitem sieht.
function EffectService:AttachTrail(part: BasePart)
	local front = Instance.new("Attachment")
	front.Name = "TrailFront"
	front.Position = Vector3.new(0, 0.4, 0)
	front.Parent = part

	local back = Instance.new("Attachment")
	back.Name = "TrailBack"
	back.Position = Vector3.new(0, -0.4, 0)
	back.Parent = part

	local trail = Instance.new("Trail")
	trail.Attachment0 = front
	trail.Attachment1 = back
	trail.Lifetime = 0.45
	trail.MinLength = 0.2
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 90, 60))
	trail.Transparency = NumberSequence.new(0.25, 1)
	trail.Parent = part
	return trail
end

return EffectService
