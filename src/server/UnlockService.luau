--!strict
-- UnlockService.luau
-- Bestimmt anhand der Einwohnerzahl, welche Katalog-Items freigeschaltet sind.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiniCity")
local Items = require(Shared:WaitForChild("Items"))

local UnlockService = {}

-- Liste der Item-Ids, die bei gegebener Einwohnerzahl freigeschaltet sind.
function UnlockService.computeUnlocked(population: number): { string }
	local unlocked = {}
	for _, item in Items.List do
		if population >= item.unlockPop then
			table.insert(unlocked, item.id)
		end
	end
	return unlocked
end

-- Ist ein einzelnes Item bei dieser Einwohnerzahl freigeschaltet?
function UnlockService.isUnlocked(itemId: string, population: number): boolean
	local item = Items.get(itemId)
	if not item then
		return false
	end
	return population >= item.unlockPop
end

return UnlockService
