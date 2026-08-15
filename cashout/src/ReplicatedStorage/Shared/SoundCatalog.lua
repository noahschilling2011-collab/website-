--[[
	SoundCatalog.lua

	Alle Sound-Ids an einer Stelle. **Jede Id ist 0** -- hier ist keine
	Roblox-Sound-Id erfunden worden. Das Spiel laeuft mit ausschliesslich
	leeren Ids vollstaendig: SoundCatalog.Play() prueft vorher und tut dann
	schlicht nichts.

	SoundCatalog.WarnMissing() gibt beim Start EINE gesammelte Zeile mit allen
	leeren Eintraegen aus, kein Spam pro Aufruf.

	Die Effekte selbst (Herzschlag im Heat-Takt, Kamera-Kick, Einzahl-Beam)
	sind Phase 4. Hier steht nur der Katalog und das Abspielen.
]]

local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")

local SoundCatalog = {}

--[[
	Id = 0 heisst "fehlt". Reihenfolge = Reihenfolge in ASSETS_TODO.md.
]]
SoundCatalog.Ids = {
	-- Phase 1
	OrderAccepted = 0,
	OrderDelivered = 0,
	DepositStart = 0,
	DepositComplete = 0,
	ActionRefused = 0,
	RoundStart = 0,
	RoundEnd = 0,

	-- Phase 2
	RaidAlarm = 0,
	RaidEscaped = 0,
	RaidCaught = 0,

	-- Phase 3
	Intercept = 0,

	-- Phase 4
	Heartbeat = 0,
	SirenLoop = 0,
}

local warned = false

--[[
	Spielt einen Katalog-Eintrag als 2D-Sound. Ohne Id passiert nichts.
	Nur auf dem Client sinnvoll -- serverseitig still ignoriert.
]]
function SoundCatalog.Play(key: string)
	if not RunService:IsClient() then
		return
	end

	local id = SoundCatalog.Ids[key]
	if not id or id == 0 then
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. tostring(id)
	sound.Parent = SoundService
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	sound.Destroying:Connect(function()
		sound:Stop()
	end)
	sound:Play()
end

--[[
	Einmalige Sammelmeldung ueber alle fehlenden Ids.
]]
function SoundCatalog.WarnMissing()
	if warned then
		return
	end
	warned = true

	local missing = {}
	for key, id in pairs(SoundCatalog.Ids) do
		if id == 0 then
			table.insert(missing, key)
		end
	end

	if #missing == 0 then
		return
	end

	table.sort(missing)
	warn(
		string.format(
			"[CASHOUT] %d Sound-Ids fehlen (siehe ASSETS_TODO.md): %s",
			#missing,
			table.concat(missing, ", ")
		)
	)
end

return SoundCatalog
