--[[
	DealService.lua

	Angebote erzeugen, Auswahl pruefen, Deal ausfuehren, auszahlen.

	Ablauf:
	  1. Spieler loest den ProximityPrompt am Terminal aus (Server-Event, der
	     Client sendet dabei nichts).
	  2. Server erzeugt drei Karten fuer genau diesen Spieler an genau diesem
	     Terminal und merkt sie sich. Innerhalb der Gueltigkeit liefert erneutes
	     Ansprechen dieselben Karten -- kein Reroll-Spam.
	  3. Client schickt ChooseDeal(terminalId, offerIndex). Mehr darf er nicht,
	     insbesondere keinen Betrag.
	  4. Server prueft alles nach, bindet den Spieler ans Terminal und zahlt
	     erst am Ende aus.

	Weglaufen, Respawn oder Razzia brechen den Deal ab: kein Geld, kein Heat.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Balance"))
local DealCatalog = require(Shared:WaitForChild("DealCatalog"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Modules = script.Parent
local MapBuilder = require(Modules:WaitForChild("MapBuilder"))
local PlayerState = require(Modules:WaitForChild("PlayerState"))

local DealService = {}

local rng = Random.new()
local running = false

-- [Player] = { terminalId, cards = { {cardId, tierId, ...}, ... }, expiresAt }
local pendingOffers: { [Player]: any } = {}

-- ------------------------------------------------------- Angebote erzeugen --

--[[
	Karten, die der Spieler bei seinem aktuellen Heat sehen darf.
]]
local function eligibleCards(heat: number)
	local pool = {}
	for _, card in ipairs(DealCatalog.Cards) do
		local tier = Balance.Deals.TierById[card.Tier]
		if tier and heat >= tier.MinHeatToOffer then
			table.insert(pool, card)
		end
	end
	return pool
end

--[[
	Gewichtete Ziehung ohne Zuruecklegen. Gewicht kommt aus
	Balance.Deals.TierWeights, damit "Extrem" selten bleibt, auch wenn der
	Katalog dort viele Karten hat.
]]
local function drawCards(pool, count: number)
	local remaining = table.clone(pool)
	local drawn = {}

	while #drawn < count and #remaining > 0 do
		local total = 0
		for _, card in ipairs(remaining) do
			total += Balance.Deals.TierWeights[card.Tier] or 1
		end

		local roll = rng:NextNumber() * total
		local pickedIndex = #remaining
		for index, card in ipairs(remaining) do
			roll -= Balance.Deals.TierWeights[card.Tier] or 1
			if roll <= 0 then
				pickedIndex = index
				break
			end
		end

		table.insert(drawn, remaining[pickedIndex])
		table.remove(remaining, pickedIndex)
	end

	return drawn
end

--[[
	Karten in die Form, die der Client sieht. Payout bleibt eine Spanne --
	gewuerfelt wird erst bei der Auszahlung.
]]
local function toOffer(card)
	local tier = Balance.Deals.TierById[card.Tier]
	return {
		cardId = card.Id,
		name = card.Name,
		blurb = card.Blurb,
		tierId = tier.Id,
		tierLabel = tier.Label,
		minPayout = tier.MinPayout,
		maxPayout = tier.MaxPayout,
		heat = tier.Heat,
		duration = tier.Duration,
	}
end

local function buildOffers(player: Player, terminalId: string)
	local state = PlayerState.Get(player)
	if not state then
		return nil
	end

	local cards = drawCards(eligibleCards(state.heat), Balance.Deals.OffersPerTerminal)
	if #cards == 0 then
		return nil
	end

	local offers = {}
	for _, card in ipairs(cards) do
		table.insert(offers, toOffer(card))
	end

	local record = {
		terminalId = terminalId,
		offers = offers,
		expiresAt = os.clock() + Balance.Deals.OfferLifetimeSeconds,
	}
	pendingOffers[player] = record
	return record
end

-- ------------------------------------------------------------ Terminal auf --

local function onTerminalTriggered(terminal, player: Player)
	if not PlayerState.Get(player) then
		return
	end
	if not PlayerState.ConsumeRequest(player) then
		return
	end

	if PlayerState.IsBusy(player) then
		PlayerState.Notify(player, "warn", "Du bist gerade beschaeftigt.")
		return
	end

	if not PlayerState.IsNear(player, terminal.Position, Balance.Map.TerminalRadius) then
		return
	end

	local record = pendingOffers[player]
	local reuse = record ~= nil
		and record.terminalId == terminal.Id
		and os.clock() < record.expiresAt

	if not reuse then
		record = buildOffers(player, terminal.Id)
	end

	if not record then
		PlayerState.Notify(player, "warn", "Dieses Terminal hat gerade nichts.")
		return
	end

	Remotes.Get(Remotes.OffersReady):FireClient(player, terminal.Id, record.offers)
end

-- ---------------------------------------------------------------- Deal Lauf --

local function runDeal(player: Player, terminal, offer)
	local token = PlayerState.BeginActivity(player, "deal", offer.name, offer.duration)
	if not token then
		return
	end

	local deadline = os.clock() + offer.duration
	local aborted = false

	while os.clock() < deadline do
		task.wait(Balance.Activity.CheckInterval)

		if not player.Parent or not PlayerState.Get(player) then
			return
		end
		if PlayerState.IsActivityCancelled(player, token) then
			aborted = true
			break
		end
		if not PlayerState.IsNear(player, terminal.Position, Balance.Map.TerminalRadius) then
			aborted = true
			break
		end
	end

	PlayerState.EndActivity(player, token)
	Remotes.Get(Remotes.CloseTerminal):FireClient(player)

	if aborted then
		-- Abbruch heisst wirklich nichts: kein Geld, kein Heat.
		PlayerState.Notify(player, "bad", "Deal abgebrochen.")
		return
	end

	local tier = Balance.Deals.TierById[offer.tierId]
	local payout = rng:NextInteger(tier.MinPayout, tier.MaxPayout)

	PlayerState.AddCash(player, payout)
	PlayerState.AddHeat(player, tier.Heat)
	PlayerState.Notify(player, "good", string.format("%s: +%d Cash, +%d Heat", offer.name, payout, tier.Heat))
end

-- --------------------------------------------------------------- Auswahl an --

local function onChooseDeal(player: Player, terminalId: any, offerIndex: any)
	if not PlayerState.Get(player) then
		return
	end
	if not PlayerState.ConsumeRequest(player) then
		return
	end

	-- Alles, was vom Client kommt, ist erstmal Muell.
	if typeof(terminalId) ~= "string" then
		return
	end
	if typeof(offerIndex) ~= "number" or offerIndex ~= math.floor(offerIndex) then
		return
	end
	if offerIndex < 1 or offerIndex > Balance.Deals.OffersPerTerminal then
		return
	end

	local record = pendingOffers[player]
	if not record or record.terminalId ~= terminalId then
		return
	end
	if os.clock() >= record.expiresAt then
		pendingOffers[player] = nil
		PlayerState.Notify(player, "warn", "Angebot abgelaufen.")
		Remotes.Get(Remotes.CloseTerminal):FireClient(player)
		return
	end

	local offer = record.offers[offerIndex]
	if not offer then
		return
	end

	local terminal = MapBuilder.GetTerminal(terminalId)
	if not terminal then
		return
	end

	if PlayerState.IsBusy(player) then
		PlayerState.Notify(player, "warn", "Du bist gerade beschaeftigt.")
		return
	end

	if not PlayerState.IsNear(player, terminal.Position, Balance.Map.TerminalRadius) then
		PlayerState.Notify(player, "warn", "Zu weit vom Terminal weg.")
		Remotes.Get(Remotes.CloseTerminal):FireClient(player)
		return
	end

	-- Angebot ist verbraucht: naechster Besuch bringt neue Karten.
	pendingOffers[player] = nil

	task.spawn(runDeal, player, terminal, offer)
end

-- ------------------------------------------------------------------- Start --

function DealService.Start()
	if running then
		return
	end
	running = true

	for _, terminal in ipairs(MapBuilder.GetTerminals()) do
		terminal.Prompt.Triggered:Connect(function(player)
			onTerminalTriggered(terminal, player)
		end)
	end

	Remotes.Get(Remotes.ChooseDeal).OnServerEvent:Connect(onChooseDeal)

	Players.PlayerRemoving:Connect(function(player)
		pendingOffers[player] = nil
	end)
end

function DealService.Stop()
	running = false
end

return DealService
