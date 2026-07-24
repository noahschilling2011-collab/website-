--[[
	MonetizationService

	=========================================================================
	PRODUKT-IDS - HIER EINTRAGEN, sonst nirgends.
	Alles auf 0 = im Creator Dashboard noch nicht angelegt. Ein Produkt mit
	ID 0 wird nie zum Kauf angeboten, es erscheint nur als "nicht eingerichtet".
	Die Liste zum Anlegen steht in docs/MONETIZATION.md.
	=========================================================================
]]

local GAMEPASS_IDS = {
	VIP = 0, -- doppelte Cash-Rate + eigenes Garagen-Tor
	AutoCollect = 0, -- Cash landet direkt auf dem Konto
	GarageLock = 0, -- eigenes Klau-Fenster nur 20 statt 60 Sekunden
}

local PRODUCT_IDS = {
	CashSmall = 0, -- 5.000 Cash
	CashMedium = 0, -- 30.000 Cash
	CashLarge = 0, -- 150.000 Cash
	InstantRepair = 0, -- ueberspringt eine laufende Reparatur
	HeistRadar = 0, -- zeigt ein Fenster lang die wertvollsten Teile
}

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Server = script.Parent.Parent
local ProfileOps = require(Server.Data.ProfileOps)
local ProfileTemplate = require(Server.Data.ProfileTemplate)
local PurchaseEffects = require(Server.Monetization.PurchaseEffects)
local Throttle = require(Server.Garage.Throttle)

local MonetizationService = {}
MonetizationService.Name = "MonetizationService"

-- Anzeigetexte fuer den Shop. Preise sind Empfehlungen und muessen im
-- Dashboard identisch gesetzt werden - der Server verkauft nichts selbst.
local CATALOG = {
	{ kind = "pass", key = "VIP", title = "VIP", desc = "Doppelte Cash-Rate + goldenes Tor.", robux = 199 },
	{ kind = "pass", key = "AutoCollect", title = "Auto-Collect", desc = "Cash ohne Einsammeln.", robux = 149 },
	{ kind = "pass", key = "GarageLock", title = "Garage Lock", desc = "Dein Tor faellt nach 20s zu.", robux = 249 },
	{ kind = "product", key = "CashSmall", title = "Cash-Paket S", desc = "5.000 Cash", robux = 25 },
	{ kind = "product", key = "CashMedium", title = "Cash-Paket M", desc = "30.000 Cash", robux = 99 },
	{ kind = "product", key = "CashLarge", title = "Cash-Paket L", desc = "150.000 Cash", robux = 399 },
	{ kind = "product", key = "InstantRepair", title = "Instant Repair", desc = "Reparatur sofort fertig.", robux = 19 },
	{ kind = "product", key = "HeistRadar", title = "Heist Radar", desc = "Top-Teile im naechsten Fenster.", robux = 49 },
}

function MonetizationService:Init(services)
	self.Services = services
	self.owned = {}
	self.pendingRepair = {}
end

function MonetizationService:Start()
	self.Services.DataService.ProfileLoaded:Connect(function(player)
		task.spawn(function()
			self:RefreshOwnership(player)
			self:PushShop(player)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self.owned[player.UserId] = nil
		self.pendingRepair[player.UserId] = nil
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if not wasPurchased then
			return
		end
		for key, id in GAMEPASS_IDS do
			if id == passId and id ~= 0 then
				local cache = self.owned[player.UserId]
				if cache then
					cache[key] = true
				end
				self.Services.EconomyService:Notify(player, ("%s ist aktiv."):format(key), "good")
				self:PushShop(player)
				self.Services.GarageService:Sync(player)
			end
		end
	end)

	-- Kaufdialoge duerfen nicht spammbar sein: sonst kann ein Client den
	-- Spieler mit Roblox-Popups zuschuetten.
	Throttle.Connect("RequestPromptPurchase", Config.PROMPT_COOLDOWN, function(player, kind, key)
		self:_prompt(player, kind, key)
	end)
	Throttle.Connect("RequestInstantRepair", Config.PROMPT_COOLDOWN, function(player, carIndex, slotId)
		self:_requestInstantRepair(player, carIndex, slotId)
	end)

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		return self:_processReceipt(receiptInfo)
	end
end

function MonetizationService:RefreshOwnership(player: Player)
	local cache = self.owned[player.UserId] or {}
	for key, id in GAMEPASS_IDS do
		if id == 0 then
			cache[key] = false
		else
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
			end)
			if ok then
				cache[key] = owns == true
			else
				-- Abfrage kaputt: alten Stand behalten, nicht raten.
				cache[key] = cache[key] == true
				warn(("[Monetization] Gamepass-Abfrage %s fehlgeschlagen: %s"):format(key, tostring(owns)))
			end
		end
	end
	self.owned[player.UserId] = cache
	return cache
end

function MonetizationService:HasPass(player: Player, key: string): boolean
	local cache = self.owned[player.UserId]
	if not cache then
		return false
	end
	return cache[key] == true
end

function MonetizationService:GetOwnership(player: Player)
	return self.owned[player.UserId] or {}
end

function MonetizationService:PushShop(player: Player)
	local entries = {}
	for _, item in CATALOG do
		local id = item.kind == "pass" and GAMEPASS_IDS[item.key] or PRODUCT_IDS[item.key]
		table.insert(entries, {
			kind = item.kind,
			key = item.key,
			title = item.title,
			desc = item.desc,
			robux = item.robux,
			configured = id ~= 0,
			owned = item.kind == "pass" and self:HasPass(player, item.key) or false,
		})
	end
	Remotes.Get("ShopState"):FireClient(player, entries)
end

function MonetizationService:_prompt(player: Player, kind, key)
	if type(kind) ~= "string" or type(key) ~= "string" then
		return
	end
	local id = (kind == "pass") and GAMEPASS_IDS[key] or PRODUCT_IDS[key]
	if not id then
		return
	end
	if id == 0 then
		self.Services.EconomyService:Notify(player, "Dieses Produkt ist noch nicht eingerichtet.", "bad")
		return
	end
	if kind == "pass" then
		if self:HasPass(player, key) then
			self.Services.EconomyService:Notify(player, "Hast du schon.", "info")
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, id)
	else
		MarketplaceService:PromptProductPurchase(player, id)
	end
end

function MonetizationService:_requestInstantRepair(player: Player, carIndex, slotId)
	local data = self.Services.DataService:Get(player)
	if not data or type(carIndex) ~= "number" or type(slotId) ~= "string" then
		return
	end
	if not data.repairs[ProfileOps.RepairKey(carIndex, slotId)] then
		self.Services.EconomyService:Notify(player, "Da laeuft keine Reparatur.", "bad")
		return
	end
	self.pendingRepair[player.UserId] = { carIndex = carIndex, slotId = slotId }
	self:_prompt(player, "product", "InstantRepair")
end

function MonetizationService:_apply(player: Player, data, key: string): boolean
	if PurchaseEffects.CASH_AMOUNTS[key] then
		return PurchaseEffects.GrantCash(self.Services, player, data, key)
	elseif key == "InstantRepair" then
		local target = self.pendingRepair[player.UserId]
		local ok = PurchaseEffects.InstantRepair(self.Services, player, data, target)
		if ok then
			self.pendingRepair[player.UserId] = nil
		end
		return ok
	elseif key == "HeistRadar" then
		return PurchaseEffects.HeistRadar(self.Services, player, data)
	end
	return false
end

function MonetizationService:_processReceipt(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = self.Services.DataService:Get(player)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receiptInfo.PurchaseId)
	-- Idempotenz: schon verbucht -> nur bestaetigen, nicht nochmal gutschreiben.
	if data.receipts[purchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local productKey = nil
	for key, id in PRODUCT_IDS do
		if id ~= 0 and id == receiptInfo.ProductId then
			productKey = key
			break
		end
	end
	if not productKey then
		warn(("[Monetization] Unbekannte ProductId %d - nicht verbucht."):format(receiptInfo.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if not self:_apply(player, data, productKey) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	data.receipts[purchaseId] = os.time()
	table.insert(data.receiptOrder, purchaseId)
	while #data.receiptOrder > ProfileTemplate.MAX_RECEIPTS do
		local oldest = table.remove(data.receiptOrder, 1)
		data.receipts[oldest] = nil
	end

	-- Erst wenn der Receipt persistent ist, gilt der Kauf als erledigt.
	if not self.Services.DataService:SaveNow(player) then
		data.receipts[purchaseId] = nil
		local index = table.find(data.receiptOrder, purchaseId)
		if index then
			table.remove(data.receiptOrder, index)
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	self.Services.GarageService:Sync(player, data)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

return MonetizationService
