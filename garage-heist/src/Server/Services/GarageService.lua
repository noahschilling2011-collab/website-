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
local PartCatalog = require(Shared.PartCatalog)
local Remotes = require(Shared.Remotes)

local Server = script.Parent.Parent
local GarageRequests = require(Server.Garage.GarageRequests)
local GarageView = require(Server.Garage.GarageView)
local RequestRouter = require(Server.Garage.RequestRouter)
local Snapshot = require(Server.Garage.Snapshot)
local DoorController = require(Server.World.DoorController)
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
	self._cooldowns = {}
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
	end

	self.Services.DataService.ProfileLoaded:Connect(function(player, data)
		self:_setup(player, data)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:_teardown(player)
	end)

	RequestRouter.Bind(self)

	task.spawn(function()
		while true do
			task.wait(1)
			self:_repairTick()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			DoorController.Tick(self.plots, self.plotOwner, function(index)
				return self.Services.HeistService:IsPlotOpen(index)
			end)
		end
	end)
end

function GarageService:_setup(player: Player, data)
	-- Erst abrechnen, dann bauen: sonst zaehlen Teile, die offline fertig
	-- geworden sind, fuer die gesamte Abwesenheit mit.
	self.Services.EconomyService:EnsureOfflineApplied(player, data)

	local plotIndex = self:_claimPlot(player)
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

function GarageService:_placeCharacter(player: Player, character: Model)
	local view = self.views[player.UserId]
	if not view then
		return
	end
	character:WaitForChild("HumanoidRootPart", 8)
	task.wait(0.1)
	if character.Parent then
		character:PivotTo(view.plot.spawnCFrame)
	end
end

function GarageService:_claimPlot(player: Player): number?
	for index = 1, Config.PLOT_COUNT do
		if not self.plotOwner[index] then
			self.plotOwner[index] = player.UserId
			-- Der Client braucht das, um die eigene Werkbank zu erkennen.
			player:SetAttribute("PlotIndex", index)
			return index
		end
	end
	return nil
end

function GarageService:_teardown(player: Player)
	local view = self.views[player.UserId]
	self.views[player.UserId] = nil
	self._cooldowns[player.UserId] = nil
	if not view then
		return
	end
	for _, refs in view.cars do
		if refs.billboard and refs.billboard.part then
			refs.billboard.part:Destroy()
		end
		refs.model:Destroy()
	end
	view.plot.door.Color = DOOR_COLOR
	view.plot.sign.name.Text = "Freie Box"
	view.plot.sign.value.Text = ""
	view.plot.sign.rate.Text = ""
	self.plotOwner[view.plotIndex] = nil
end

function GarageService:GetView(userId: number)
	return self.views[userId]
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
	GarageView.RenderCars(view, player, data, function(thief, victim, carIndex, slotId, prompt)
		self.Services.HeistService:OnStealPrompt(thief, victim, carIndex, slotId, prompt)
	end)
	self:Sync(player, data)
end

function GarageService:Sync(player: Player, data)
	data = data or self.Services.DataService:Get(player)
	if not data then
		return
	end
	local view = self.views[player.UserId]
	local rate = self.Services.EconomyService:GetRate(player, data)
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

-- Teil aus einem fremden Auto loesen. Nur der HeistService ruft das auf,
-- nachdem er Fenster, Entfernung und Besitz geprueft hat.
function GarageService:TakePart(victim: Player, carIndex: number, slotId: string)
	local data = self.Services.DataService:Get(victim)
	if not data then
		return nil
	end
	local part = ProfileOps.RemovePart(data, carIndex, slotId)
	if not part then
		return nil
	end
	data.stats.partsLost += 1
	self:Refresh(victim, data)
	return part
end

-- Diebesgut in der eigenen Garage abliefern.
function GarageService:GiveStolenPart(thief: Player, part)
	local data = self.Services.DataService:Get(thief)
	if not data then
		return false, "Profil nicht geladen."
	end
	ProfileOps.RollDailyStats(data)
	data.stats.stolenToday += 1
	data.stats.totalStolen += 1
	local ok, message = GarageRequests.DepositStolenPart(self.Services, thief, data, part)
	self:Refresh(thief, data)
	return ok, message
end

-- Fenster vorbei oder Dieb weg: Teil geht zurueck an den urspruenglichen
-- Besitzer, sofern der noch auf dem Server ist.
function GarageService:ReturnPart(part): boolean
	local owner = Players:GetPlayerByUserId(part.originalOwner)
	if not owner then
		return false
	end
	local data = self.Services.DataService:Get(owner)
	if not data then
		return false
	end
	GarageRequests.DepositStolenPart(self.Services, owner, data, part)
	data.stats.partsLost = math.max(0, data.stats.partsLost - 1)
	self:Refresh(owner, data)
	local tierDef = PartCatalog.GetTier(part.slotId, part.tier)
	self.Services.EconomyService:Notify(
		owner,
		("%s ist zurueck in deiner Garage."):format(tierDef and tierDef.name or part.slotId),
		"good"
	)
	return true
end

function GarageService:_repairTick()
	local now = os.time()
	self.Services.DataService:ForEachProfile(function(player, data)
		if not self.Services.EconomyService:IsSettled(player) then
			return
		end
		local due = ProfileOps.RepairsDueBefore(data, now)
		if #due == 0 then
			return
		end
		for _, repair in due do
			local part = ProfileOps.FinishRepair(data, repair.carIndex, repair.slotId, player.UserId)
			if part then
				local tierDef = PartCatalog.GetTier(part.slotId, part.tier)
				self.Services.EconomyService:Notify(
					player,
					("%s ist eingebaut."):format(tierDef and tierDef.name or part.slotId),
					"good"
				)
			end
		end
		self:Refresh(player, data)
	end)
end

return GarageService
