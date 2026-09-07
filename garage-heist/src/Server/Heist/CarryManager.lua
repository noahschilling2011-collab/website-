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

local Util = require(Shared.Util)

local ProfileOps = require(script.Parent.Parent.Data.ProfileOps)
local PartVisual = require(script.Parent.PartVisual)
local StealTarget = require(script.Parent.StealTarget)

local CarryManager = {}
CarryManager.__index = CarryManager

function CarryManager.new(services)
	local self = setmetatable({}, CarryManager)
	self.Services = services
	-- [userId] = Liste von { part, model, weld, target }. Seit v8 duerfen es
	-- Config.CARRY_MAX_PARTS Stueck sein; leere Listen werden auf nil gesetzt,
	-- damit "for userId in self.carrying" weiter "traegt gerade" bedeutet.
	self.carrying = {}
	self.dropped = {} -- [model] = { part, prompt, target }
	self.tackleCooldown = {}
	self.immunity = {} -- [userId] = os.clock() des letzten Treffers
	return self
end

function CarryManager:List(player: Player)
	return self.carrying[player.UserId] or {}
end

function CarryManager:IsCarrying(player: Player): boolean
	return #self:List(player) > 0
end

function CarryManager:CanCarryMore(player: Player): boolean
	return #self:List(player) < Config.CARRY_MAX_PARTS
end

function CarryManager:_pushState(player: Player)
	local parts = {}
	for _, entry in self:List(player) do
		local tierDef = PartCatalog.GetTier(entry.part.slotId, entry.part.tier)
		local slotDef = PartCatalog.GetSlot(entry.part.slotId)
		table.insert(parts, {
			slotId = entry.part.slotId,
			slotName = slotDef and slotDef.displayName or entry.part.slotId,
			tierName = tierDef and tierDef.name or "Teil",
			tier = entry.part.tier,
		})
	end
	Remotes.Get("CarryState"):FireClient(player, { parts = parts })
end

-- Tempo faellt mit jedem weiteren Teil. Wer zwei traegt, ist deutlich
-- langsamer als ein Verfolger - das ist der Preis fuer die doppelte Beute.
function CarryManager:_applySpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local count = #self:List(player)
	if count <= 0 then
		humanoid.WalkSpeed = Config.NORMAL_WALKSPEED
		return
	end
	humanoid.WalkSpeed = math.max(4, Config.CARRY_WALKSPEED - (count - 1) * Config.CARRY_SECOND_PENALTY)
end

function CarryManager:StartCarry(player: Player, part, target)
	if not self:CanCarryMore(player) then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	local list = self.carrying[player.UserId]
	if not list then
		list = {}
		self.carrying[player.UserId] = list
	end
	-- Zweites Teil seitlich versetzt, sonst stecken beide ineinander.
	local slot = #list
	local offset = CFrame.new(slot * 1.7 - (Config.CARRY_MAX_PARTS - 1) * 0.85, 0.6, -2.4)

	local model = PartVisual.Build(part)
	model.CFrame = root.CFrame * offset
	model.Parent = workspace

	self.Services.EffectService:AttachTrail(model)

	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = model
	weld.C0 = offset
	weld.Parent = model

	table.insert(list, {
		part = part,
		model = model,
		weld = weld,
		target = target,
	})

	self:_applySpeed(player)
	self:_pushState(player)
	return true
end

-- Nimmt ALLE getragenen Teile aus der Hand und gibt sie als Liste zurueck.
-- Es gibt bewusst kein "nur eins ablegen": ein Rempler wirft alles, und beim
-- Abliefern will man ohnehin alles los werden.
function CarryManager:_clearCarry(player: Player)
	local list = self.carrying[player.UserId]
	if not list or #list == 0 then
		return {}
	end
	self.carrying[player.UserId] = nil
	for _, entry in list do
		if entry.model then
			entry.model:Destroy()
		end
	end
	self:_applySpeed(player)
	self:_pushState(player)
	return list
end

-- Teil faellt zu Boden und kann von jedem aufgehoben werden.
function CarryManager:Drop(player: Player, reason: string?)
	if not self:IsCarrying(player) then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local position = root and (root.Position + Vector3.new(0, -1.5, 0)) or Vector3.new(0, 5, 0)
	local list = self:_clearCarry(player)
	-- Faecherfoermig ablegen, sonst liegen zwei Teile exakt uebereinander und
	-- man kann nur eines aufheben.
	for index, entry in list do
		self:SpawnDropped(entry.part, position + Vector3.new((index - 1) * 3, 0, 0), entry.target)
	end
	if reason then
		self.Services.EconomyService:Notify(player, reason, "bad")
	end
	return true
end

function CarryManager:SpawnDropped(part, position: Vector3, target)
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

	self.dropped[model] = { part = part, prompt = prompt, target = target }

	prompt.Triggered:Connect(function(player)
		local entry = self.dropped[model]
		if not entry or not self.Services.HeistService:IsOpen() then
			return
		end
		if not self:CanCarryMore(player) then
			self.Services.EconomyService:Notify(player, "Du hast die Haende voll.", "bad")
			return
		end
		self.dropped[model] = nil
		model:Destroy()
		self:StartCarry(player, entry.part, entry.target)
	end)
	return model
end

-- Abgabe im eigenen Plot. Wird vom Touched-Event des Abgabe-Pads gerufen.
function CarryManager:TryDeposit(player: Player, plotIndex: number)
	if not self:IsCarrying(player) then
		return false
	end
	if self.Services.GarageService:GetOwnerOfPlot(plotIndex) ~= player.UserId then
		return false
	end
	local list = self:_clearCarry(player)
	local plot = self.Services.GarageService.plots[plotIndex]
	self.Services.EffectService:Deposit(plot and plot.lootBay)
	for _, entry in list do
		local _, message = self.Services.GarageService:GiveStolenPart(player, entry.part, entry.target)
		self.Services.EconomyService:Notify(player, message or "Teil abgeliefert.", "good")
		StealTarget.NotifyVictim(
			self.Services,
			entry.target,
			("%s hat dein Teil in die eigene Garage geschleppt."):format(player.DisplayName)
		)
	end
	return true
end

--[[
	Alles beim Hehler verticken. Der Server rechnet den Betrag aus dem
	Teilewert; der Client schickt nur die Absicht.

	Reihenfolge ist wichtig: erst den Besitzwechsel beim Opfer festschreiben
	(Commit entfernt das Teil und zahlt dessen Versicherung), dann den Dieb
	bezahlen. Schlaegt der Commit fehl - Opfer ist weg -, gibt es auch kein
	Geld, sonst entstuende Cash aus einem Teil, das nie den Besitzer gewechselt
	hat.
]]
function CarryManager:Fence(player: Player)
	if not self.Services.HeistService:IsOpen() then
		return false, "Der Hehler macht nur waehrend des Fensters auf."
	end
	if not self:IsCarrying(player) then
		return false, "Du traegst nichts."
	end
	local list = self:_clearCarry(player)
	local total = 0
	local sold = 0
	for _, entry in list do
		local value = ProfileOps.PartValue(entry.part)
		local ok = true
		if StealTarget.IsPlayer(entry.target) then
			local victim = entry.target.player
			ok = victim.Parent ~= nil and self.Services.GarageService:CommitTheft(victim, entry.part.uid)
		end
		if ok then
			total += math.floor(value * self.Services.GarageService:FenceRate(player))
			sold += 1
			StealTarget.NotifyVictim(
				self.Services,
				entry.target,
				("%s hat dein Teil beim Hehler verticken lassen."):format(player.DisplayName)
			)
		end
	end
	if sold == 0 then
		return false, "Der Besitzer ist weg - der Hehler zahlt nichts."
	end
	self.Services.EconomyService:AddCash(player, total, "Fence")
	return true, ("%d Teil(e) verticken lassen: %s."):format(sold, Util.FormatCash(total))
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
	self.immunity = self.immunity or {}
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	self.tackleCooldown[player.UserId] = now

	local bestPlayer, bestDistance = nil, Config.TACKLE_RANGE
	for userId, list in self.carrying do
		-- Wer gerade getroffen wurde, ist kurz unantastbar. Ohne das haelt ein
		-- Verfolger den Traeger dauerhaft am Boden: 16 gegen 12 Studs/s.
		if userId ~= player.UserId and #list > 0 and now - (self.immunity[userId] or 0) >= Config.TACKLE_IMMUNITY then
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
	self.immunity[bestPlayer.UserId] = now
	self:Drop(bestPlayer, ("%s hat dir alles aus der Hand geschlagen."):format(player.DisplayName))
	self.Services.EconomyService:Notify(player, ("Treffer! %s liegt das Teil vor den Fuessen."):format(bestPlayer.DisplayName), "good")
	self.Services.EffectService:Sound("tackle", root.Position)
	self.Services.EffectService:Shake(bestPlayer, Config.TACKLE_SHAKE)
	self.Services.EffectService:Shake(player, Config.TACKLE_SHAKE * 0.5)
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
			local list = self:_clearCarry(player)
			if #list > 0 then
				for _, entry in list do
					self:_returnOrDiscard(entry.part, entry.target)
				end
				self.Services.EconomyService:Notify(player, "Zu spaet abgeliefert - alles weg.", "bad")
			end
		else
			self.carrying[userId] = nil
		end
	end
	for _, model in droppedModels do
		local entry = self.dropped[model]
		if entry then
			self:_returnOrDiscard(entry.part, entry.target)
		end
		self.dropped[model] = nil
		model:Destroy()
	end
end

-- Spielerteile gehen an den Besitzer zurueck. Leerstand-Gut hat keinen
-- Besitzer und verschwindet ersatzlos.
function CarryManager:_returnOrDiscard(part, target)
	if StealTarget.IsPlayer(target) then
		self.Services.GarageService:ClearInTransit(target.player, part.uid)
	end
end

function CarryManager:HandleLeave(player: Player)
	local list = self:_clearCarry(player)
	self.tackleCooldown[player.UserId] = nil
	if self.immunity then
		self.immunity[player.UserId] = nil
	end
	for _, entry in list do
		self:_returnOrDiscard(entry.part, entry.target)
	end
end

function CarryManager:HandleDeath(player: Player)
	if self:IsCarrying(player) then
		self:Drop(player, "Du hast alles fallen lassen.")
	end
end

return CarryManager
