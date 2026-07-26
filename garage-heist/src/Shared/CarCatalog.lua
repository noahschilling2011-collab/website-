--[[
	CarCatalog
	Autos sind Deko-Objekte mit Werten. Kein Fahrverhalten, keine Seats,
	kein VehicleSeat. Nur Groesse, Farbe, Preis und ein Ratenmultiplikator.
]]

local CarCatalog = {}

CarCatalog.Order = { "scrap_sedan", "hatchback", "muscle", "supercar" }

CarCatalog.Cars = {
	scrap_sedan = {
		displayName = "Schrott-Limousine",
		cost = 0,
		rateMult = 1.0,
		bodySize = Vector3.new(5.2, 1.6, 11.0),
		roofSize = Vector3.new(4.6, 1.4, 5.0),
		roofOffset = Vector3.new(0, 2.6, 0.6),
		baseColor = Color3.fromRGB(120, 116, 110),
		wheelbase = 3.4,
		track = 2.9,
	},
	hatchback = {
		displayName = "Kompakt-Hatch",
		cost = 3000,
		rateMult = 1.25,
		bodySize = Vector3.new(5.0, 1.7, 9.6),
		roofSize = Vector3.new(4.4, 1.6, 5.4),
		roofOffset = Vector3.new(0, 2.7, 0.4),
		baseColor = Color3.fromRGB(90, 140, 120),
		wheelbase = 3.0,
		track = 2.8,
	},
	muscle = {
		displayName = "Muscle Coupe",
		cost = 15000,
		rateMult = 1.6,
		bodySize = Vector3.new(5.8, 1.6, 12.4),
		roofSize = Vector3.new(4.8, 1.3, 4.6),
		roofOffset = Vector3.new(0, 2.5, 1.2),
		baseColor = Color3.fromRGB(150, 60, 60),
		wheelbase = 3.9,
		track = 3.2,
	},
	supercar = {
		displayName = "Supersportler",
		cost = 75000,
		rateMult = 2.2,
		bodySize = Vector3.new(6.0, 1.2, 12.8),
		roofSize = Vector3.new(4.4, 1.0, 4.0),
		roofOffset = Vector3.new(0, 2.0, 1.6),
		baseColor = Color3.fromRGB(230, 190, 40),
		wheelbase = 4.1,
		track = 3.3,
	},
}

function CarCatalog.Get(carId)
	return CarCatalog.Cars[carId]
end

function CarCatalog.IsValid(carId)
	return CarCatalog.Cars[carId] ~= nil
end

CarCatalog.STARTER = "scrap_sedan"

return CarCatalog
