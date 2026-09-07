--[[
	Audio
	Duenner Wrapper um SoundCatalog. Fehlt eine ID, passiert nichts - kein
	Fehler, keine Warnung im Spielbetrieb.
]]

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local SoundCatalog = require(script.Parent.SoundCatalog)

local Audio = {}

local MAX_LIFETIME = 10

-- Raeumlicher Klang an einer Weltposition.
function Audio.PlayAt(name: string, position: Vector3)
	local def = SoundCatalog.Get(name)
	if not def or not position then
		return
	end
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Position = position
	holder.Parent = workspace

	local sound = Instance.new("Sound")
	sound.SoundId = def.id
	sound.Volume = def.volume or 0.5
	sound.RollOffMaxDistance = def.rollOff or 60
	sound.Parent = holder
	sound:Play()

	Debris:AddItem(holder, math.min(MAX_LIFETIME, (sound.TimeLength > 0 and sound.TimeLength or 3) + 0.5))
end

-- Klang nur fuer den lokalen Spieler (Client).
function Audio.PlayLocal(name: string)
	local def = SoundCatalog.Get(name)
	if not def then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = def.id
	sound.Volume = def.volume or 0.5
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, MAX_LIFETIME)
end

return Audio
