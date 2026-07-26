--[[
	GarageService
	Verteilt Plots, haelt Welt und Profil synchron, besitzt die einzige
	Schnittstelle, ueber die Teile den Besitzer wechseln.

	Pruefung der Client-Wuensche: GarageRequests + RequestRouter.
	Rendern: GarageView. Geometrie: World/*.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local Server = script.Parent.Parent
local Throttle = require(Server.Garage.Throttle)
local StealTarget = require(Server.Heist.StealTarget)
local GarageView = require(Server.Garage.GarageView)
local GarageTicks = require(Server.Garage.GarageTicks)
local TheftOps = require(Server.Garage.TheftOps)
local RepairView = require(Server.Garage.RepairView)
local RequestRouter = require(Server.Garage.RequestRouter)
local Snapshot = require(Server.Garage.Snapshot)
local PlotBuilder = require(Server.World.PlotBuilder)
local ProfileOps = require(Server.Data.ProfileOps)

local GarageService = {}
GarageService.Name = "GarageService"

local DOOR_COLOR = Color3.fromRGB(160, 90, 40)
local DOOR_COLOR_VIP = Color3.fromRGB(232, 190, 62)

function GarageService:Init(services)
	self.Services = services
	self.plots = {}
	self.plotOwner = {}
	self.views = {}
end

function GarageService:Start()
	local folder = Instance.new("Folder")
	folder.Name = "Garages"
	folder.Parent = workspace
	self.folder = folder

	for index = 1, Config.PLOT_COUNT do
		local plot = PlotBuilder.Build(index, folder)
		self.plots[index] = plot
		local prompt = plot.register:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
				if self.plotOwner[index] == player.UserId then
					self.Services.EconomyService:Collect(player)
				end
			end)
		end

		-- Pruefstand. Nur der Besitzer, gedrosselt wie jede andere Anfrage.
		local dynoPrompt = plot.dyno and plot.dyno:FindFirstChildOfClass("ProximityPrompt")
		if dynoPrompt then
			dynoPrompt.Triggered:Connect(function(player)
				if self.plotOwner[index] ~= player.UserId then
					return
				end
				if Throttle.Blocked(player, "Dyno", Config.DYNO_COOLDOWN) then
					return
				end
				self:RunDyno(player, plot)
			end)
		end
	end

	self.Services.DataService.ProfileLoaded:Connect(function(player, data)
		self:_setup(player, data)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:_teardown(player)
	end)

	RequestRouter.Bind(self)

	GarageTicks.Start(self)
end

function GarageService:_setup(player: Player, data)
	-- Erst abrechnen, dann bauen: sonst zaehlen Teile, die offline fertig
	-- geworden sind, fuer die gesamte Abwesenheit mit.
	self.Services.EconomyService:EnsureOfflineApplied(player, data)

	ProfileOps.ClearAllInTransit(data)
	local plotIndex = self:_claimPlot(player, data)
	if not plotIndex then
		player:Kick("Alle Garagen sind belegt. Bitte einem anderen Server beitreten.")
		return
	end

	self.views[player.UserId] = {
		plotIndex = plotIndex,
		plot = self.plots[plotIndex],
		cars = {},
		stealEnabled = false,
	}

	if player.Character then
		task.spawn(function()
			self:_placeCharacter(player, player.Character)
		end)
	end
	player.CharacterAdded:Connect(function(character)
		self:_placeCharacter(player, character)
	end)

	self:Refresh(player, data)
end

-- Neulinge landen einmal in der Werkhalle und laufen selbst zur Box; wer schon
-- etwas verbaut hat, kommt wie bisher direkt an seiner Garage raus. Ohne diese
-- Unterscheidung sieht die Halle niemand: der Teleport feuert 0,1 s nach jedem
-- Spawn.
function GarageService:_placeCharacter(player: Player, character: Model, force: boolean?)
	local view = self.views[player.UserId]
	if not view then
		return
	end
	character:WaitForChild("HumanoidRootPart", 8)
	task.wait(0.1)
	if not character.Parent then
		return
	end

	if not force and not view.leftHall then
		local data = self.Services.DataService:Get(player)
		if data and ProfileOps.GarageValue(data) <= 0 then
			return -- bleibt auf dem LobbySpawn in der Halle
		end
	end

	view.leftHall = true
	character:PivotTo(view.plot.spawnCFrame)
end

-- Wird vom Warp-Pad in der Werkhalle aufgerufen.
function GarageService:SendToPlot(player: Player)
	local character = player.Character
	if character then
		task.spawn(function()
			self:_placeCharacter(player, character, true)
		end)
	end
end

function GarageService:_claimPlot(player: Player, data): number?
	-- Erst die Box von letztem Mal, damit die Garage nicht wandert.
	local preferred = data and data.preferredPlot or 0
	if preferred >= 1 and preferred <= Config.PLOT_COUNT and not self.plotOwner[preferred] then
		self.plotOwner[preferred] = player.UserId
		player:SetAttribute("PlotIndex", preferred)
		self.Services.DerelictService:Release(preferred)
		return preferred
	end
	for index = 1, Config.PLOT_COUNT do
		if not self.plotOwner[index] then
			self.plotOwner[index] = player.UserId
			-- Der Client braucht das, um die eigene Werkbank zu erkennen.
			player:SetAttribute("PlotIndex", index)
			-- Falls hier gerade ein Leerstand-Auto steht: abraeumen, sonst
			-- ueberlagert es das Auto des neuen Besitzers.
			self.Services.DerelictService:Release(index)
			return index
		end
	end
	return nil
end

function GarageService:_teardown(player: Player)
	local view = self.views[player.UserId]
	self.views[player.UserId] = nil
	if not view then
		return
	end
	RepairView.Clear(view)
	for _, refs in view.cars do
		if refs.billboard and refs.billboard.part then
			refs.billboard.part:Destroy()
		end
		refs.model:Destroy()
	end
	view.plot.door.Color = DOOR_COLOR
	-- Sonst behaelt eine freie Box die Optik des letzten Besitzers.
	PlotBuilder.ApplyLevel(view.plot, 1)
	view.plot.sign.name.Text = "Freie Box"
	view.plot.sign.value.Text = ""
	view.plot.sign.rate.Text = ""
	self.plotOwner[view.plotIndex] = nil
end

function GarageService:GetOwnerOfPlot(plotIndex: number): number?
	return self.plotOwner[plotIndex]
end

function GarageService:GetPlotIndexOf(player: Player): number?
	local view = self.views[player.UserId]
	return view and view.plotIndex or nil
end

function GarageService:Refresh(player: Player, data)
	data = data or self.Services.DataService:Get(player)
	local view = self.views[player.UserId]
	if not data or not view then
		return
	end
	GarageView.RenderCars(view, player, data, function(thief, carIndex, slotId, prompt)
		self.Services.HeistService:OnStealPrompt(thief, StealTarget.Player(player), carIndex, slotId, prompt)
	end)
	-- Die alten Balken hingen an den eben zerstoerten Modellen.
	view.repairBars = nil
	RepairView.Sync(view, data)
	self:Sync(player, data)
end

function GarageService:Sync(player: Player, data)
	data = data or self.Services.DataService:Get(player)
	if not data then
		return
	end
	local view = self.views[player.UserId]
	local rate = self.Services.EconomyService:GetRate(player, data)
	data.preferredPlot = view and view.plotIndex or data.preferredPlot
	if view then
		GarageView.UpdateSign(view, player, data, rate)
		GarageView.UpdateBillboards(view, data)
		-- VIP-Tor: reine Optik, wird auch genau so verkauft.
		local vip = self.Services.MonetizationService:HasPass(player, "VIP")
		view.plot.door.Color = vip and DOOR_COLOR_VIP or DOOR_COLOR
	end
	Remotes.Get("ProfileSync"):FireClient(
		player,
		Snapshot.Build(player, data, {
			rate = rate,
			passes = self.Services.MonetizationService:GetOwnership(player),
		})
	)
end

function GarageService:SetStealEnabledFor(userId: number, enabled: boolean)
	local view = self.views[userId]
	if view then
		GarageView.SetStealEnabled(view, enabled)
	end
end

--[[
	Pruefstand: misst die Leistung des staerksten Autos in dieser Garage.

	Der Wert kommt aus ProfileOps.DynoPower - der Client bekommt nur das
	Ergebnis. Die Wartezeit ist reine Inszenierung; entschieden ist alles schon
	beim Druecken, damit ein Verbindungsabbruch waehrenddessen nichts kaputt
	macht.
]]
function GarageService:RunDyno(player: Player, plot)
	local data = self.Services.DataService:Get(player)
	if not data then
		return
	end
	local power = ProfileOps.BestDynoPower(data)
	if power <= 0 then
		self.Services.EconomyService:Notify(player, "Da ist nichts zu messen - bau erst ein Teil ein.", "bad")
		return
	end

	local label = plot.dynoLabel
	task.spawn(function()
		if label then
			for step = 1, Config.DYNO_SPIN_TIME * 4 do
				if not label.Parent then
					return
				end
				label.Text = ("%d PS"):format(math.floor(power * (step / (Config.DYNO_SPIN_TIME * 4))))
				task.wait(0.25)
			end
			label.Text = ("%d PS"):format(power)
		end
	end)

	local record = power > (data.stats.bestDyno or 0)
	if record then
		data.stats.bestDyno = power
	end
	-- Kleine Auszahlung, damit Messen nicht nur Zierde ist. Nur beim Rekord,
	-- sonst waere der Pruefstand ein Knopf zum Gelddrucken.
	if record then
		local reward = math.floor(power * Config.DYNO_REWARD_PER_PS)
		if reward > 0 then
			self.Services.EconomyService:AddCash(player, reward, "Dyno")
		end
		self.Services.EconomyService:Notify(
			player,
			("Neuer Rekord: %d PS (+%s)."):format(power, Util.FormatCash(reward)),
			"good"
		)
	else
		self.Services.EconomyService:Notify(
			player,
			("%d PS - dein Rekord steht bei %d."):format(power, data.stats.bestDyno or 0),
			"info"
		)
	end
	self:Sync(player, data)
end

-- Besitzwechsel von Teilen liegt komplett in Garage/TheftOps.
function GarageService:TakePart(victim: Player, thief: Player, carIndex: number, slotId: string)
	return TheftOps.Take(self, victim, thief, carIndex, slotId)
end

function GarageService:GiveStolenPart(thief: Player, part, target)
	return TheftOps.Deposit(self, thief, part, target)
end

-- Schreibt den Besitzwechsel beim Opfer fest, ohne dass der Dieb das Teil
-- bekommt. Nur der Hehler braucht das: dort loest sich das Teil auf und der
-- Dieb wird stattdessen in Cash bezahlt.
function GarageService:CommitTheft(victim: Player, uid: string): boolean
	return TheftOps.Commit(self, victim, uid)
end

-- Kurs des Hehlers. Steht hier und nicht im CarryManager, weil er von
-- Freischaltungen des Spielers abhaengt - und die kennt der Server ueber das
-- Profil, nicht der Heist.
function GarageService:FenceRate(player: Player): number
	local data = self.Services.DataService:Get(player)
	return ProfileOps.FenceRate(data)
end

function GarageService:ClearInTransit(victim: Player, uid: string)
	return TheftOps.Clear(self, victim, uid)
end

return GarageService
