--[[
	Store
	Der Client haelt genau eine Kopie dessen, was der Server geschickt hat.
	Nichts hier wird berechnet - insbesondere kein Cash. Wer etwas will,
	schickt eine Anfrage und wartet auf das naechste Update.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Signal)

local Store = {}

Store.snapshot = nil -- Garage, Autos, Teile, Preise
Store.cash = { cash = 0, pile = 0, rate = 0, autoCollect = false }
Store.heist = { open = false, endsAt = 0, nextAt = 0 }
Store.daily = nil
Store.shop = {}
Store.carry = nil
Store.leaderboard = { richest = {}, thieves = {} }

Store.Changed = Signal.new() -- (was: string)

function Store.Set(key: string, value)
	Store[key] = value
	Store.Changed:Fire(key)
end

return Store
