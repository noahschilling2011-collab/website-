--[[
	GarageView
	Haelt die sichtbare Welt am Profil dran: Autos neu bauen, Schild und
	Billboards beschriften, Klau-Prompts verdrahten.

	Der Zustand liegt immer im Profil. Diese Datei liest ihn nur ab.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.CarCatalog)
local PartCatalog = require(Shared.PartCatalog)
local Util = require(Shared.Util)

local Server = script.Parent.Parent
local CarBuilder = require(Server.World.CarBuilder)
local PlotBuilder = require(Server.World.PlotBuilder)
local ProfileOps = require(Server.Data.ProfileOps)

local GarageView = {}

-- Baut alle Autos eines Spielers neu. Wird nach jeder Zustandsaenderung
-- aufgerufen (Kauf, Reparatur fertig, Teil geklaut, Teil abgeliefert).
function GarageView.RenderCars(view, player: Player, data, onStealPrompt)
	for _, carRefs in view.cars do
		if carRefs.billboard and carRefs.billboard.part then
			carRefs.billboard.part:Destroy()
		end
		carRefs.model:Destroy()
	end
	table.clear(view.cars)

	for carIndex, carState in data.cars do
		local pad = view.plot.carPads[carIndex]
		if pad then
			-- Teile, die gerade weggetragen werden, sind am Auto nicht mehr dran.
			local visible = { carId = carState.carId, parts = {} }
			for slotId, part in carState.parts do
				if not part.inTransit then
					visible.parts[slotId] = part
				end
			end
			local refs = CarBuilder.Build(visible, carIndex, player.UserId, pad, view.plot.model, {
				rebirths = data.rebirths or 0,
			})
			view.cars[carIndex] = refs
			for slotId, prompt in refs.prompts do
				prompt.Enabled = view.stealEnabled == true
				prompt.Triggered:Connect(function(thief)
					onStealPrompt(thief, carIndex, slotId, prompt)
				end)
			end
		end
	end
	GarageView.UpdateBillboards(view, data)
end

function GarageView.UpdateBillboards(view, data)
	for carIndex, refs in view.cars do
		local carState = data.cars[carIndex]
		if carState then
			local carDef = CarCatalog.Get(carState.carId)
			local sum = 0
			for _, part in carState.parts do
				sum += ProfileOps.PartRate(part) -- unterwegs = 0
			end
			sum *= carDef and carDef.rateMult or 1
			local missing = 0
			for _, slotId in PartCatalog.SlotOrder do
				if not carState.parts[slotId] then
					missing += 1
				end
			end
			refs.billboard.title.Text = carDef and carDef.displayName or carState.carId
			refs.billboard.sub.Text = if missing > 0
				then ("%s  -  %d Teile fehlen"):format(Util.FormatRate(sum), missing)
				else Util.FormatRate(sum)
		end
	end
end

function GarageView.UpdateSign(view, player: Player, data, rate: number)
	-- Akzentfarbe, Deckenlicht und Bodenmarkierung haengen an der Garagenstufe.
	-- Ohne das sieht ein 260k-Ausbau aus wie der Anfangszustand.
	PlotBuilder.ApplyLevel(view.plot, data.garageLevel or 1)
	local sign = view.plot.sign
	sign.name.Text = player.DisplayName .. "s Garage"
	sign.value.Text = "Wert " .. Util.FormatCash(ProfileOps.GarageValue(data))
	sign.rate.Text = Util.FormatRate(rate)
end

-- Klau-Prompts an/aus. Wird vom HeistService gesteuert, nicht vom Client.
function GarageView.SetStealEnabled(view, enabled: boolean)
	view.stealEnabled = enabled
	for _, refs in view.cars do
		for _, prompt in refs.prompts do
			prompt.Enabled = enabled
		end
	end
end

return GarageView
