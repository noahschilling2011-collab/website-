--[[
	DerelictService
	Freie Plots sind waehrend des Klau-Fensters keine leeren Boxen, sondern
	Leerstand-Garagen mit einem bestueckten Auto. Damit findet der Heist auch
	statt, wenn genau ein Spieler auf dem Server ist - der Normalfall beim Launch.

	Die Stufe der Teile haengt am Median der Garagenwerte der Anwesenden und ist
	auf Config.DERELICT_MAX_TIER gedeckelt. Leerstand-Teile tragen einen
	Wert-Multiplikator (Config.DERELICT_VALUE_MULT), damit PvP der lohnendere
	Weg bleibt.

	Alles hier existiert nur waehrend des Fensters. Am Ende wird es ersatzlos
	abgeraeumt - es gibt keinen Besitzer, dem etwas zurueckgegeben werden koennte.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.CarCatalog)
local Config = require(Shared.Config)
local PartCatalog = require(Shared.PartCatalog)
local Util = require(Shared.Util)

local Server = script.Parent.Parent
local CarBuilder = require(Server.World.CarBuilder)
local ProfileOps = require(Server.Data.ProfileOps)
local StealTarget = require(Server.Heist.StealTarget)

local DerelictService = {}
DerelictService.Name = "DerelictService"

function DerelictService:Init(services)
	self.Services = services
	self.plots = {} -- [plotIndex] = { state = {carId, parts}, refs = <CarBuilder-Refs> }
end

function DerelictService:Start() end

-- Median der Garagenwerte aller anwesenden Spieler -> Teilestufe.
function DerelictService:_targetTier(): number
	local values = {}
	self.Services.DataService:ForEachProfile(function(_, data)
		table.insert(values, ProfileOps.GarageValue(data))
	end)
	if #values == 0 then
		return 1
	end
	table.sort(values)
	local median = values[math.ceil(#values / 2)]

	local tier = 1
	for step, threshold in Config.DERELICT_TIER_STEPS do
		if median >= threshold then
			tier = step
		end
	end
	return math.clamp(tier, 1, Config.DERELICT_MAX_TIER)
end

-- Prozedurale Bestueckung: 1-4 Teile, Stufe um +/-1 gestreut.
function DerelictService:_makeState(baseTier: number)
	local slots = table.clone(PartCatalog.SlotOrder)
	for index = #slots, 2, -1 do
		local swap = math.random(index)
		slots[index], slots[swap] = slots[swap], slots[index]
	end

	local count = math.random(Config.DERELICT_MIN_PARTS, Config.DERELICT_MAX_PARTS)
	local parts = {}
	for index = 1, count do
		local slotId = slots[index]
		local tier = math.clamp(baseTier + math.random(-1, 1), 1, Config.DERELICT_MAX_TIER)
		parts[slotId] = {
			uid = Util.NewUid(),
			slotId = slotId,
			tier = tier,
			subTier = 0,
			originalOwner = 0,
			mult = Config.DERELICT_VALUE_MULT,
		}
	end

	local carIds = CarCatalog.Order
	return {
		carId = carIds[math.clamp(baseTier, 1, #carIds)],
		parts = parts,
	}
end

-- Wird vom HeistService beim Oeffnen des Fensters gerufen.
function DerelictService:Populate()
	local garage = self.Services.GarageService
	local baseTier = self:_targetTier()

	for plotIndex, plot in garage.plots do
		if not garage:GetOwnerOfPlot(plotIndex) and not self.plots[plotIndex] then
			local state = self:_makeState(baseTier)
			local pad = plot.carPads[1]
			local refs = CarBuilder.Build(state, 1, 0, pad, plot.model)

			for slotId, prompt in refs.prompts do
				prompt.Enabled = true
				prompt.ObjectText = "Leerstand"
				prompt.Triggered:Connect(function(thief)
					self.Services.HeistService:OnStealPrompt(
						thief,
						StealTarget.Derelict(plotIndex),
						1,
						slotId,
						prompt
					)
				end)
			end

			plot.sign.name.Text = "Leerstand - offen"
			plot.sign.value.Text = ("%d Teile"):format(self:_countParts(state))
			plot.sign.rate.Text = "kein Besitzer"

			self.plots[plotIndex] = { state = state, refs = refs }
		end
	end
end

function DerelictService:_countParts(state): number
	local count = 0
	for _ in state.parts do
		count += 1
	end
	return count
end

-- Wird vom HeistService beim Schliessen gerufen.
function DerelictService:Clear()
	local garage = self.Services.GarageService
	for plotIndex, entry in self.plots do
		if entry.refs then
			if entry.refs.billboard and entry.refs.billboard.part then
				entry.refs.billboard.part:Destroy()
			end
			entry.refs.model:Destroy()
		end
		local plot = garage.plots[plotIndex]
		if plot and not garage:GetOwnerOfPlot(plotIndex) then
			plot.sign.name.Text = "Freie Box"
			plot.sign.value.Text = ""
			plot.sign.rate.Text = ""
		end
	end
	table.clear(self.plots)
end

-- Ein Spieler uebernimmt den Plot mitten im Fenster: Leerstand raeumen.
function DerelictService:Release(plotIndex: number)
	local entry = self.plots[plotIndex]
	if not entry then
		return
	end
	if entry.refs.billboard and entry.refs.billboard.part then
		entry.refs.billboard.part:Destroy()
	end
	entry.refs.model:Destroy()
	self.plots[plotIndex] = nil
end

function DerelictService:GetPart(plotIndex: number, carIndex: number, slotId: string)
	local entry = self.plots[plotIndex]
	if not entry or carIndex ~= 1 then
		return nil
	end
	return entry.state.parts[slotId]
end

-- Teil abmontiert: hier gibt es kein Profil, das Teil wird einfach herausgeloest.
function DerelictService:TakePart(plotIndex: number, carIndex: number, slotId: string)
	local entry = self.plots[plotIndex]
	if not entry or carIndex ~= 1 then
		return nil
	end
	local part = entry.state.parts[slotId]
	if not part then
		return nil
	end
	entry.state.parts[slotId] = nil
	self:_rerender(plotIndex)
	return part
end

function DerelictService:_rerender(plotIndex: number)
	local entry = self.plots[plotIndex]
	local plot = self.Services.GarageService.plots[plotIndex]
	if not entry or not plot then
		return
	end
	if entry.refs.billboard and entry.refs.billboard.part then
		entry.refs.billboard.part:Destroy()
	end
	entry.refs.model:Destroy()

	local refs = CarBuilder.Build(entry.state, 1, 0, plot.carPads[1], plot.model)
	for slotId, prompt in refs.prompts do
		prompt.Enabled = self.Services.HeistService:IsPlotOpen(plotIndex)
		prompt.ObjectText = "Leerstand"
		prompt.Triggered:Connect(function(thief)
			self.Services.HeistService:OnStealPrompt(thief, StealTarget.Derelict(plotIndex), 1, slotId, prompt)
		end)
	end
	entry.refs = refs
	plot.sign.value.Text = ("%d Teile"):format(self:_countParts(entry.state))
end

return DerelictService
