--[[
	DismountManager
	Vier Sekunden schrauben. Der Server misst die Zeit, prueft waehrenddessen
	weiter Entfernung, Fenster und ob das Teil ueberhaupt noch dran ist. Der
	Client zeichnet nur den Balken - er kann den Vorgang nicht abkuerzen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local PartCatalog = require(Shared.PartCatalog)
local Remotes = require(Shared.Remotes)

local ProfileOps = require(script.Parent.Parent.Data.ProfileOps)

local DismountManager = {}
DismountManager.__index = DismountManager

local CHECK_STEP = 0.2

function DismountManager.new(services, carry)
	return setmetatable({
		Services = services,
		Carry = carry,
		active = {},
	}, DismountManager)
end

local function rootOf(player: Player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

function DismountManager:_progress(thief: Player, state: string, duration: number?, label: string?)
	Remotes.Get("DismountProgress"):FireClient(thief, {
		state = state,
		duration = duration,
		label = label,
	})
end

-- Alles, was stimmen muss - vor dem Start und waehrend der vier Sekunden.
function DismountManager:_check(thief: Player, victim: Player, carIndex: number, slotId: string, anchor: BasePart?)
	if not self.Services.HeistService:IsOpen() then
		return false, "Das Klau-Fenster ist zu."
	end
	if thief == victim then
		return false, "Das ist deine eigene Garage."
	end
	local victimPlot = self.Services.GarageService:GetPlotIndexOf(victim)
	if not victimPlot or not self.Services.HeistService:IsPlotOpen(victimPlot) then
		return false, "Diese Garage ist verriegelt."
	end
	local victimData = self.Services.DataService:Get(victim)
	if not victimData or not ProfileOps.GetPart(victimData, carIndex, slotId) then
		return false, "Da ist nichts mehr."
	end
	if self.Carry:IsCarrying(thief) then
		return false, "Erst abliefern, dann weiterklauen."
	end
	local root = rootOf(thief)
	if not root then
		return false, "Kein Charakter."
	end
	if anchor and (anchor.Position - root.Position).Magnitude > Config.DISMOUNT_MAX_DISTANCE then
		return false, "Zu weit weg."
	end
	return true
end

function DismountManager:Start(thief: Player, victim: Player, carIndex: number, slotId: string, anchor: BasePart?)
	if self.active[thief.UserId] then
		return
	end
	local ok, reason = self:_check(thief, victim, carIndex, slotId, anchor)
	if not ok then
		self.Services.EconomyService:Notify(thief, reason, "bad")
		return
	end

	local tierDef = PartCatalog.GetTier(slotId, ProfileOps.CurrentTier(self.Services.DataService:Get(victim), carIndex, slotId))
	local label = tierDef and tierDef.name or slotId
	local token = (self._token or 0) + 1
	self._token = token
	self.active[thief.UserId] = token
	self:_progress(thief, "start", Config.DISMOUNT_TIME, label)
	self.Services.EconomyService:Notify(
		victim,
		("%s schraubt an deinem Auto!"):format(thief.DisplayName),
		"bad"
	)

	task.spawn(function()
		local elapsed = 0
		while elapsed < Config.DISMOUNT_TIME do
			task.wait(CHECK_STEP)
			elapsed += CHECK_STEP
			if self.active[thief.UserId] ~= token then
				return -- abgebrochen (Cancel, Tod, Fenster zu)
			end
			local stillOk, why = self:_check(thief, victim, carIndex, slotId, anchor)
			if not stillOk then
				self.active[thief.UserId] = nil
				self:_progress(thief, "cancel")
				self.Services.EconomyService:Notify(thief, why, "bad")
				return
			end
		end

		self.active[thief.UserId] = nil
		local part = self.Services.GarageService:TakePart(victim, carIndex, slotId)
		if not part then
			self:_progress(thief, "cancel")
			return
		end
		self:_progress(thief, "done")
		if not self.Carry:StartCarry(thief, part, victim.UserId) then
			-- Charakter ist im letzten Moment weg: Teil faellt an Ort und Stelle.
			local root = rootOf(thief)
			self.Carry:SpawnDropped(part, root and root.Position or anchor and anchor.Position or Vector3.new(0, 5, 0))
			return
		end
		self.Services.EconomyService:Notify(thief, ("%s abmontiert - ab in deine Garage!"):format(label), "good")
		self.Services.EconomyService:Notify(
			victim,
			("%s hat dir %s abmontiert!"):format(thief.DisplayName, label),
			"bad"
		)
	end)
end

function DismountManager:Cancel(thief: Player)
	if self.active[thief.UserId] then
		self.active[thief.UserId] = nil
		self:_progress(thief, "cancel")
	end
end

return DismountManager
