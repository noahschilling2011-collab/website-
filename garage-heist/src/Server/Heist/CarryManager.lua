--[[
	CarryManager
	Was mit einem abmontierten Teil passiert, solange es niemandem gehoert:
	tragen, fallen lassen, aufheben, abliefern.

	Besitzwechsel passiert erst beim Abliefern in der eigenen Garage. Bis dahin
	haelt der Server das Teil in der Hand - im Wortsinn: es haengt am Charakter
	und ist beim Tod, beim Verlassen oder beim Fenster-Ende wieder weg.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local PartCatalog = require(Shared.PartCatalog)
local Remotes = require(Shared.Remotes)

local PartVisual = require(script.Parent.PartVisual)

local CarryManager = {}
CarryManager.__index = CarryManager

function CarryManager.new(services)
	local self = setmetatable({}, CarryManager)
	self.Services = services
	self.carrying = {} -- [userId] = { part, model, weld, victimUserId }
	self.dropped = {} -- [model] = { part, prompt }
	self.tackleCooldown = {}
	return self
end

function CarryManager:IsCarrying(player: Player): boolean
	return self.carrying[player.UserId] ~= nil
end

function CarryManager:_pushState(player: Player)
	local entry = self.carrying[player.UserId]
	local payload = nil
	if entry then
		local tierDef = PartCatalog.GetTier(entry.part.slotId, entry.part.tier)
		local slotDef = PartCatalog.GetSlot(entry.part.slotId)
		payload = {
			slotId = entry.part.slotId,
			slotName = slotDef and slotDef.displayName or entry.part.slotId,
			tierName = tierDef and tierDef.name or "Teil",
			tier = entry.part.tier,
		}
	end
	Remotes.Get("CarryState"):FireClient(player, { part = payload })
end

function CarryManager:StartCarry(player: Player, part, victimUserId: number?)
	if self.carrying[player.UserId] then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	local model = PartVisual.Build(part)
	model.CFrame = root.CFrame * CFrame.new(0, 0.6, -2.4)
	model.Parent = workspace

	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = model
	weld.C0 = CFrame.new(0, 0.6, -2.4)
	weld.Parent = model

	self.carrying[player.UserId] = {
		part = part,
		model = model,
		weld = weld,
		victimUserId = victimUserId,
	}

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Config.CARRY_WALKSPEED
	end
	self:_pushState(player)
	return true
end

function CarryManager:_clearCarry(player: Player)
	local entry = self.carrying[player.UserId]
	if not entry then
		return nil
	end
	self.carrying[player.UserId] = nil
	if entry.model then
		entry.model:Destroy()
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Config.NORMAL_WALKSPEED
	end
	self:_pushState(player)
	return entry
end

-- Teil faellt zu Boden und kann von jedem aufgehoben werden.
function CarryManager:Drop(player: Player, reason: string?)
	local entry = self.carrying[player.UserId]
	if not entry then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local position = root and (root.Position + Vector3.new(0, -1.5, 0)) or Vector3.new(0, 5, 0)
	self:_clearCarry(player)
	self:SpawnDropped(entry.part, position)
	if reason then
		self.Services.EconomyService:Notify(player, reason, "bad")
	end
	return true
end

function CarryManager:SpawnDropped(part, position: Vector3)
	local model = PartVisual.Build(part)
	model.Anchored = true
	model.CFrame = CFrame.new(position)
	model.Parent = workspace

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Aufheben"
	prompt.ObjectText = "Herrenloses Teil"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.DROPPED_PART_PICKUP_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = model

	self.dropped[model] = { part = part, prompt = prompt }

	prompt.Triggered:Connect(function(player)
		local entry = self.dropped[model]
		if not entry or not self.Services.HeistService:IsOpen() then
			return
		end
		if self:IsCarrying(player) then
			self.Services.EconomyService:Notify(player, "Du traegst schon ein Teil.", "bad")
			return
		end
		self.dropped[model] = nil
		model:Destroy()
		self:StartCarry(player, entry.part, nil)
	end)
	return model
end

-- Abgabe im eigenen Plot. Wird vom Touched-Event des Abgabe-Pads gerufen.
function CarryManager:TryDeposit(player: Player, plotIndex: number)
	local entry = self.carrying[player.UserId]
	if not entry then
		return false
	end
	if self.Services.GarageService:GetOwnerOfPlot(plotIndex) ~= player.UserId then
		return false
	end
	self:_clearCarry(player)
	local _, message = self.Services.GarageService:GiveStolenPart(player, entry.part)
	self.Services.EconomyService:Notify(player, message or "Teil abgeliefert.", "good")

	local victim = entry.victimUserId and Players:GetPlayerByUserId(entry.victimUserId)
	if victim then
		self.Services.EconomyService:Notify(
			victim,
			("%s hat dein Teil in die eigene Garage geschleppt."):format(player.DisplayName),
			"bad"
		)
	end
	return true
end

-- Rempler: wer nah genug an einem Traeger steht, schlaegt ihm das Teil aus der Hand.
function CarryManager:Tackle(player: Player)
	if not self.Services.HeistService:IsOpen() then
		return
	end
	local now = os.clock()
	if now - (self.tackleCooldown[player.UserId] or 0) < Config.TACKLE_COOLDOWN then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	self.tackleCooldown[player.UserId] = now

	local bestPlayer, bestDistance = nil, Config.TACKLE_RANGE
	for userId in self.carrying do
		if userId ~= player.UserId then
			local other = Players:GetPlayerByUserId(userId)
			local otherRoot = other and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			if otherRoot then
				local distance = (otherRoot.Position - root.Position).Magnitude
				if distance <= bestDistance then
					bestPlayer, bestDistance = other, distance
				end
			end
		end
	end

	if not bestPlayer then
		self.Services.EconomyService:Notify(player, "Niemand in Reichweite.", "info")
		return
	end
	self:Drop(bestPlayer, ("%s hat dir das Teil aus der Hand geschlagen."):format(player.DisplayName))
	self.Services.EconomyService:Notify(player, ("Treffer! %s liegt das Teil vor den Fuessen."):format(bestPlayer.DisplayName), "good")
end

-- Alles einsammeln, was noch herumliegt oder getragen wird: zurueck zum
-- urspruenglichen Besitzer.
function CarryManager:ReturnEverything()
	-- Erst Schluessel einsammeln: die Schleifen veraendern beide Tabellen.
	local carriers = {}
	for userId in self.carrying do
		table.insert(carriers, userId)
	end
	local droppedModels = {}
	for model in self.dropped do
		table.insert(droppedModels, model)
	end

	for _, userId in carriers do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			local entry = self:_clearCarry(player)
			if entry then
				if not self.Services.GarageService:ReturnPart(entry.part) then
					self.Services.EconomyService:Notify(player, "Das Fenster ist zu - das Teil ist weg.", "bad")
				else
					self.Services.EconomyService:Notify(player, "Zu spaet abgeliefert. Das Teil ist zurueck beim Besitzer.", "bad")
				end
			end
		else
			self.carrying[userId] = nil
		end
	end
	for _, model in droppedModels do
		local entry = self.dropped[model]
		if entry then
			self.Services.GarageService:ReturnPart(entry.part)
		end
		self.dropped[model] = nil
		model:Destroy()
	end
end

function CarryManager:HandleLeave(player: Player)
	local entry = self:_clearCarry(player)
	self.tackleCooldown[player.UserId] = nil
	if entry then
		self.Services.GarageService:ReturnPart(entry.part)
	end
end

function CarryManager:HandleDeath(player: Player)
	if self.carrying[player.UserId] then
		self:Drop(player, "Du hast das Teil fallen lassen.")
	end
end

return CarryManager
