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
	-- Serverzeit des letzten ausgespielten Prototyps. Bewusst nur hier und
	-- nicht im Profil: der Cooldown gilt fuer den Server, nicht pro Spieler -
	-- sonst umgeht ihn eine zweite Person am selben Ort.
	self.lastT4At = 0
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

-- Darf in diesem Fenster ueberhaupt ein Prototyp auftauchen? Drei Schranken,
-- alle auf dem Server. Der Wurf steht bewusst zuletzt: faellt er negativ aus,
-- laeuft der Cooldown nicht an und das naechste Fenster wuerfelt neu.
function DerelictService:_rollT4(baseTier: number): boolean
	if baseTier < #Config.DERELICT_TIER_STEPS then
		return false
	end
	local now = os.time()
	if now - (self.lastT4At or 0) < Config.DERELICT_T4_COOLDOWN then
		return false
	end
	if math.random() >= Config.DERELICT_T4_CHANCE then
		return false
	end
	self.lastT4At = now
	return true
end

-- Prozedurale Bestueckung: 1-4 Teile, Stufe um +/-1 gestreut.
-- `t4Slot` bekommt der Aufrufer aus _rollT4 - hoechstens ein Slot im ganzen
-- Fenster, sonst haette eine einzige Box vier Prototypen.
function DerelictService:_makeState(baseTier: number, withT4: boolean?, valueMult: number?)
	local slots = table.clone(PartCatalog.SlotOrder)
	for index = #slots, 2, -1 do
		local swap = math.random(index)
		slots[index], slots[swap] = slots[swap], slots[index]
	end

	local count = math.random(Config.DERELICT_MIN_PARTS, Config.DERELICT_MAX_PARTS)
	-- slots ist schon gemischt, also ist der erste Eintrag ein zufaelliger Slot.
	local t4Slot = withT4 and slots[1] or nil
	local parts = {}
	for index = 1, count do
		local slotId = slots[index]
		-- Der Streuwurf bleibt unter der Kaufgrenze: alles darueber ist
		-- Prototyp und kommt ausschliesslich ueber t4Slot ins Spiel.
		local tier = math.clamp(baseTier + math.random(-1, 1), 1, Config.MAX_PURCHASABLE_TIER)
		if slotId == t4Slot then
			tier = Config.DERELICT_MAX_TIER
		end
		parts[slotId] = {
			uid = Util.NewUid(),
			slotId = slotId,
			tier = tier,
			subTier = 0,
			originalOwner = 0,
			mult = Config.DERELICT_VALUE_MULT * (valueMult or 1),
		}
	end

	local carIds = CarCatalog.Order
	return {
		carId = carIds[math.clamp(baseTier, 1, #carIds)],
		parts = parts,
	}
end

-- Wird vom HeistService beim Oeffnen des Fensters gerufen.
-- `valueMult` hebt den Wert der Beute an (Nachtschicht). 1 = normal.
function DerelictService:Populate(valueMult: number?)
	local garage = self.Services.GarageService
	local baseTier = self:_targetTier()

	-- Erst sammeln, dann bestuecken: der Prototyp soll in einer zufaelligen
	-- freien Box liegen und nicht immer in der ersten, die die Schleife trifft.
	-- _rollT4 setzt den Cooldown, deshalb erst fragen, wenn es ueberhaupt eine
	-- Box gibt, in die das Teil passt.
	local free = {}
	for plotIndex, plot in garage.plots do
		if not garage:GetOwnerOfPlot(plotIndex) and not self.plots[plotIndex] then
			table.insert(free, { index = plotIndex, plot = plot })
		end
	end
	local t4Index = nil
	if #free > 0 and self:_rollT4(baseTier) then
		t4Index = free[math.random(#free)].index
	end
	-- Merken, damit der HeistService den Tag-7-Hinweis ausliefern kann.
	self.t4Index = t4Index

	for _, entry in free do
		local plotIndex, plot = entry.index, entry.plot
		local state = self:_makeState(baseTier, plotIndex == t4Index, valueMult)
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
		-- Der Prototyp muss auffindbar sein, sonst laeuft der Spieler an der
		-- einzigen Box vorbei, die im Fenster zaehlt.
		plot.sign.rate.Text = if plotIndex == t4Index then "PROTOTYP an Bord" else "kein Besitzer"

		self.plots[plotIndex] = { state = state, refs = refs }
	end
end

-- In welcher Box liegt in diesem Fenster der Prototyp? nil = in keiner.
function DerelictService:GetT4Plot(): number?
	return self.t4Index
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
