--[[
	Main.server.lua

	Startet die Services in der einzig moeglichen Reihenfolge: erst die Map,
	weil Deal- und BankService sich ihre Prompts daraus holen. Sonst passiert
	hier nichts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local Modules = ServerScriptService:WaitForChild("Modules")
local MapBuilder = require(Modules:WaitForChild("MapBuilder"))
local PlayerState = require(Modules:WaitForChild("PlayerState"))
local HeatService = require(Modules:WaitForChild("HeatService"))
local DealService = require(Modules:WaitForChild("DealService"))
local BankService = require(Modules:WaitForChild("BankService"))

-- Remotes zuerst, damit kein Client auf ein noch nicht existierendes Event wartet.
Remotes.CreateAll()

MapBuilder.Start()
PlayerState.Start()
HeatService.Start()
DealService.Start()
BankService.Start()

print("[CASHOUT] Phase 1 laeuft.")
