--[[
	DismountManager
	Vier Sekunden schrauben. Der Server misst die Zeit, prueft waehrenddessen
	weiter Entfernung, Fenster und ob das Teil ueberhaupt noch dran ist. Der
	Client zeichnet nur den Balken - er kann den Vorgang nicht abkuerzen.

	Das Ziel ist ein StealTarget: entweder ein Spieler oder eine Leerstand-
	Garage. Beide laufen durch exakt denselben Pfad.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local PartCatalog = require(Shared.PartCatalog)
local Remotes = require(Shared.Remotes)

local StealTarget = require(script.Parent.StealTarget)

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
function DismountManager:_check(thief: Player, target, carIndex: number, slotId: string, anchor: BasePart?)
	if not self.Services.HeistService:IsOpen() then
		return false, "Das Klau-Fenster ist zu."
	end
	if StealTarget.IsPlayer(target) and target.player == thief then
		return false, "Das ist deine eigene Garage."
	end
	local plotIndex = StealTarget.PlotIndex(self.Services, target)
	if not plotIndex or not self.Services.HeistService:IsPlotOpen(plotIndex) then
		return false, "Diese Garage ist verriegelt."
	end
	local part = StealTarget.GetPart(self.Services, target, carIndex, slotId)
	if not part or part.inTransit then
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

function DismountManager:Start(thief: Player, target, carIndex: number, slotId: string, anchor: BasePart?)
	if self.active[thief.UserId] then
		return
	end
	local ok, reason = self:_check(thief, target, carIndex, slotId, anchor)
	if not ok then
		self.Services.EconomyService:Notify(thief, reason, "bad")
		return
	end

	local part = StealTarget.GetPart(self.Services, target, carIndex, slotId)
	local tierDef = part and PartCatalog.GetTier(slotId, part.tier)
	local label = tierDef and tierDef.name or slotId
	local token = (self._token or 0) + 1
	self._token = token
	self.active[thief.UserId] = token
	self:_progress(thief, "start", Config.DISMOUNT_TIME, label)
	StealTarget.NotifyVictim(
		self.Services,
		target,
		("%s schraubt an deinem Auto!"):format(thief.DisplayName)
	)
	self.Services.EffectService:Sparks(anchor, Config.DISMOUNT_TIME)

	task.spawn(function()
		local elapsed = 0
		while elapsed < Config.DISMOUNT_TIME do
			task.wait(CHECK_STEP)
			elapsed += CHECK_STEP
			if self.active[thief.UserId] ~= token then
				return -- abgebrochen (Cancel, Tod, Fenster zu)
			end
			local stillOk, why = self:_check(thief, target, carIndex, slotId, anchor)
			if not stillOk then
				self.active[thief.UserId] = nil
				self:_progress(thief, "cancel")
				self.Services.EconomyService:Notify(thief, why, "bad")
				return
			end
		end

		self.active[thief.UserId] = nil
		local taken = StealTarget.TakePart(self.Services, target, thief, carIndex, slotId)
		if not taken then
			self:_progress(thief, "cancel")
			return
		end
		self:_progress(thief, "done")
		if not self.Carry:StartCarry(thief, taken, target) then
			-- Charakter ist im letzten Moment weg: Teil faellt an Ort und Stelle.
			local root = rootOf(thief)
			self.Carry:SpawnDropped(taken, root and root.Position or anchor and anchor.Position or Vector3.new(0, 5, 0), target)
			return
		end
		self.Services.EconomyService:Notify(thief, ("%s abmontiert - ab in deine Garage!"):format(label), "good")
		StealTarget.NotifyVictim(
			self.Services,
			target,
			("%s hat dir %s abmontiert!"):format(thief.DisplayName, label)
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
