--[[
	Main.server.lua

	Startet die Services. Die Reihenfolge ist nicht beliebig:
	  - Remotes zuerst, damit kein Client auf ein fehlendes Event wartet.
	  - MapBuilder vor Order- und BankService, die sich ihre Prompts daraus holen.
	  - RoundManager zuletzt, weil die anderen Services sich bei ihm per
	    OnRoundStart / OnRoundEnd anmelden, bevor die erste Runde laeuft.

	Sonst passiert hier nichts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local SoundCatalog = require(Shared:WaitForChild("SoundCatalog"))

local Modules = ServerScriptService:WaitForChild("Modules")
local MapBuilder = require(Modules:WaitForChild("MapBuilder"))
local PlayerState = require(Modules:WaitForChild("PlayerState"))
local HeatService = require(Modules:WaitForChild("HeatService"))
local OrderService = require(Modules:WaitForChild("OrderService"))
local BankService = require(Modules:WaitForChild("BankService"))
local RaidService = require(Modules:WaitForChild("RaidService"))
local RoundManager = require(Modules:WaitForChild("RoundManager"))

Remotes.CreateAll()
SoundCatalog.WarnMissing()

MapBuilder.Start()
PlayerState.Start()
HeatService.Start()
OrderService.Start()
BankService.Start()
RaidService.Start()
RoundManager.Start()

print("[CASHOUT] v2 Phase 2 laeuft.")
