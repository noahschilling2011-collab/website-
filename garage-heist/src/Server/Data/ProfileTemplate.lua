--[[
	ProfileTemplate
	Das Schema eines Spielerprofils. Alles, was der Server ueber einen Spieler
	weiss, steht hier drin - und nur hier.

	Neue Felder duerfen ergaenzt werden: Util.Reconcile fuellt sie bei alten
	Profilen beim Laden nach.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Config = require(Shared.Config)
local CarCatalog = require(Shared.CarCatalog)

local ProfileTemplate = {}

-- 2 = Teile haben eine Feinabstimmung (part.subTier) und es gibt Rebirths.
-- Alte Profile brauchen keine Migration: subTier wird ueberall als
-- `part.subTier or 0` gelesen, rebirths fuellt Util.Reconcile nach.
ProfileTemplate.SCHEMA_VERSION = 2
ProfileTemplate.MAX_RECEIPTS = 60

function ProfileTemplate.New()
	return {
		schemaVersion = ProfileTemplate.SCHEMA_VERSION,

		cash = Config.START_CASH,
		pile = 0, -- verdientes, noch nicht abgeholtes Cash (Kasse in der Garage)
		lastOnline = 0, -- os.time() beim letzten Verlassen; 0 = noch nie gespielt
		firstJoin = 0,

		garageLevel = 1,
		rebirths = 0,
		preferredPlot = 0, -- zuletzt belegte Box, wird bevorzugt wieder vergeben

		-- cars ist ein dichtes Array. cars[i].parts[slotId] = Teil oder nil.
		-- Teil = { uid, slotId, tier, subTier, originalOwner, mult? }
		cars = {
			{ carId = CarCatalog.STARTER, parts = {} },
		},

		-- Laufende Reparaturen: repairs["1:engine"] = { endsAt = <os.time>, tier = <n> }
		-- Das Geld ist beim Kauf schon abgebucht, deshalb muss das persistent sein.
		repairs = {},

		-- Geklaute oder ausgebaute Teile ohne Einbauplatz: looseParts[uid] = { slotId, tier, originalOwner }
		looseParts = {},

		stats = {
			stolenToday = 0,
			stolenDay = 0, -- UTC-Tag, auf den sich stolenToday bezieht
			totalStolen = 0,
			partsLost = 0,
			totalEarned = 0,
			-- Beste je gemessene Pruefstandsleistung. Util.Reconcile setzt das
			-- Feld bei alten Profilen auf 0 nach.
			bestDyno = 0,
		},

		daily = {
			streak = 0,
			lastDay = 0, -- UTC-Tag der letzten Abholung
		},

		-- Idempotenz fuer ProcessReceipt
		receipts = {},
		receiptOrder = {},

		-- Einmalige Effekte aus Developer Products
		pendingRadar = 0, -- Anzahl gekaufter, noch nicht verbrauchter Radar-Ladungen
	}
end

return ProfileTemplate
