--[[
	OrderService.lua

	Auftraege statt Timer (Dokument 1.1).

	  1. Spieler loest den ProximityPrompt am Terminal aus (Server-Event, der
	     Client sendet dabei nichts).
	  2. Server zieht drei Karten fuer genau diesen Spieler an genau diesem
	     Terminal. Die Gewichte kommen aus dem Terminal-Profil -- weiter von
	     der Bank entfernte Terminals fuehren die besseren Stufen.
	  3. Client schickt ChooseOrder(terminalId, offerIndex). Mehr darf er
	     nicht, insbesondere keinen Betrag.
	  4. Annahme dauert Balance.Orders.AcceptSeconds am Terminal. Danach
	     erscheint irgendwo im Stufenabstand ein Uebergabepunkt, der Spieler
	     traegt ein sichtbares Paket in der Stufenfarbe.
	  5. Am Punkt: Balance.Orders.DeliverSeconds Interaktion, dann Cash + Heat.

	Ausgezahlt wird erst bei der Uebergabe, mit der Risikopraemie aus dem in
	dem Moment aktuellen Heat und dem Endspurt-Multiplikator der Runde.

	Weglaufen waehrend einer Interaktion bricht sie folgenlos ab. Ein
	angenommener Auftrag bleibt bestehen, bis er uebergeben ist oder die Runde
	endet -- er laeuft nicht ab.
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
local RoundManager = require(Modules:WaitForChild("RoundManager"))

local OrderService = {}

local rng = Random.new()
local running = false

-- [Player] = { terminalId, offers, expiresAt }
local pendingOffers: { [Player]: any } = {}
-- [ProximityPrompt] = Player  -- wem gehoert dieser Uebergabepunkt
local pointOwner: { [ProximityPrompt]: Player } = {}
-- [Player] = point
-- Eigene Buchfuehrung statt Umweg ueber PlayerState: beim Verlassen des
-- Servers loescht PlayerState seinen Eintrag zuerst (es haengt frueher an
-- PlayerRemoving), und der Punkt waere dann nicht mehr auffindbar.
local activePoints: { [Player]: any } = {}
-- [Player] = { RBXScriptConnection }
local playerConnections: { [Player]: { RBXScriptConnection } } = {}

-- Vorwaertsdeklaration: runAccept verdrahtet den Prompt eines frisch
-- erzeugten Uebergabepunkts, die Behandlung steht weiter unten.
local onPointTriggered

-- ------------------------------------------------------- Angebote erzeugen --

--[[
	Karten, die der Spieler bei seinem aktuellen Heat an diesem Terminal sehen
	darf. Gewicht 0 im Terminal-Profil schliesst eine Stufe hier ganz aus.
]]
local function eligibleCards(heat: number, profile)
	local pool = {}
	for _, card in ipairs(DealCatalog.Cards) do
		local tier = Balance.Orders.TierById[card.Tier]
		local weight = profile[card.Tier] or 0
		if tier and weight > 0 and heat >= tier.MinHeatToOffer then
			table.insert(pool, card)
		end
	end
	return pool
end

--[[
	Gewichtete Ziehung ohne Zuruecklegen.
]]
local function drawCards(pool, profile, count: number)
	local remaining = table.clone(pool)
	local drawn = {}

	while #drawn < count and #remaining > 0 do
		local total = 0
		for _, card in ipairs(remaining) do
			total += profile[card.Tier] or 0
		end
		if total <= 0 then
			break
		end

		local roll = rng:NextNumber() * total
		local pickedIndex = #remaining
		for index, card in ipairs(remaining) do
			roll -= profile[card.Tier] or 0
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
	Karte in die Form, die der Client sieht. Der Payout ist hier noch die
	Spanne der Stufe -- gewuerfelt wird bei der Annahme.
]]
local function toOffer(card)
	local tier = Balance.Orders.TierById[card.Tier]
	return {
		cardId = card.Id,
		name = card.Name,
		blurb = card.Blurb,
		tierId = tier.Id,
		tierLabel = tier.Label,
		minPayout = tier.MinPayout,
		maxPayout = tier.MaxPayout,
		heat = tier.Heat,
		minDistance = tier.MinDistance,
		maxDistance = tier.MaxDistance,
	}
end

local function buildOffers(player: Player, terminal)
	local state = PlayerState.Get(player)
	if not state then
		return nil
	end

	local profile = Balance.Orders.TerminalProfiles[terminal.Rank]
	if not profile then
		return nil
	end

	local cards = drawCards(eligibleCards(state.heat, profile), profile, Balance.Orders.OffersPerTerminal)
	if #cards == 0 then
		return nil
	end

	local offers = {}
	for _, card in ipairs(cards) do
		table.insert(offers, toOffer(card))
	end

	local record = {
		terminalId = terminal.Id,
		offers = offers,
		expiresAt = os.clock() + Balance.Orders.OfferLifetimeSeconds,
	}
	pendingOffers[player] = record
	return record
end

-- ------------------------------------------------------ Uebergabepunkt setzen --

local function isInsidePlayArea(position: Vector3): boolean
	local half = Balance.Map.PlayableHalfExtent
	return math.abs(position.X) <= half and math.abs(position.Z) <= half
end

--[[
	Sucht eine Richtung, in der der Uebergabepunkt im Stufenabstand noch auf
	der Spielflaeche liegt und nicht im Bankgebaeude steckt. Der Abstand selbst
	bleibt dabei unveraendert -- er ist die Waehrung der Stufe.

	Findet keine Richtung, wird geklemmt. Bei der aktuellen Kartengroesse
	(480 Studs Halbkante gegen hoechstens 340 Studs Abstand) kommt das nicht
	vor; der Zweig ist nur da, damit ein kleinerer Boden nicht in eine
	Endlosschleife laeuft.
]]
local function pickDeliveryPosition(origin: Vector3, tier): Vector3
	local distance = rng:NextNumber(tier.MinDistance, tier.MaxDistance)
	local tries = Balance.Map.DeliveryPlacementTries
	local startAngle = rng:NextNumber(0, 2 * math.pi)
	local clearance = Balance.Map.BankPlinthSize.X / 2 + Balance.Map.DeliveryPadSize.X / 2

	for step = 0, tries - 1 do
		local angle = startAngle + step * (2 * math.pi / tries)
		local candidate = origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local flatToBank = Vector3.new(
			candidate.X - Balance.Map.BankPosition.X,
			0,
			candidate.Z - Balance.Map.BankPosition.Z
		)
		if isInsidePlayArea(candidate) and flatToBank.Magnitude > clearance then
			return Vector3.new(candidate.X, Balance.Map.GroundY, candidate.Z)
		end
	end

	local half = Balance.Map.PlayableHalfExtent
	local fallback = origin + Vector3.new(math.cos(startAngle) * distance, 0, math.sin(startAngle) * distance)
	return Vector3.new(
		math.clamp(fallback.X, -half, half),
		Balance.Map.GroundY,
		math.clamp(fallback.Z, -half, half)
	)
end

-- ---------------------------------------------------------------- Paket --

local function findTorso(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		return torso
	end
	return nil
end

local function removePackage(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local existing = character:FindFirstChild("CashoutPackage")
	if existing then
		existing:Destroy()
	end
end

--[[
	Sichtbares Paket auf dem Ruecken. Farbe = Stufe, damit von weitem lesbar
	ist, ob sich das Verfolgen lohnt.
]]
local function attachPackage(player: Player, tier)
	removePackage(player)

	local torso = findTorso(player)
	if not torso then
		return
	end

	local pack = Instance.new("Part")
	pack.Name = "CashoutPackage"
	pack.Size = Balance.Map.PackageSize
	pack.Color = tier.Color
	pack.Material = Enum.Material.Neon
	pack.Anchored = false
	pack.CanCollide = false
	pack.CanQuery = false
	pack.Massless = true
	pack.CFrame = torso.CFrame * CFrame.new(Balance.Map.PackageOffset)
	pack.Parent = torso.Parent

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = pack
	weld.Part1 = torso
	weld.Parent = pack
end

-- ------------------------------------------------------------ Auftrag loesen --

--[[
	Raeumt Punkt und Paket ab. Der Auftrag selbst wird im PlayerState geloescht,
	falls es den Spieler dort noch gibt.
]]
local function clearOrder(player: Player)
	local point = activePoints[player]
	if point then
		activePoints[player] = nil
		pointOwner[point.Prompt] = nil
		point.Model:Destroy()
	end
	removePackage(player)
	PlayerState.ClearOrder(player)
end

-- --------------------------------------------------------------- Annahme --

local function runAccept(player: Player, terminal, offer)
	local token = PlayerState.BeginActivity(player, "accept", offer.name, Balance.Orders.AcceptSeconds)
	if not token then
		return
	end

	local deadline = os.clock() + Balance.Orders.AcceptSeconds
	local aborted = false

	while os.clock() < deadline do
		task.wait(Balance.Orders.CheckInterval)

		if not player.Parent or not PlayerState.Get(player) then
			return
		end
		if PlayerState.IsActivityCancelled(player, token) then
			aborted = true
			break
		end
		if not PlayerState.IsNear(player, terminal.Position, Balance.Orders.InteractRadius) then
			aborted = true
			break
		end
	end

	PlayerState.EndActivity(player, token)
	Remotes.Get(Remotes.CloseTerminal):FireClient(player)

	if aborted or not RoundManager.IsRunning() then
		PlayerState.Notify(player, "bad", "Annahme abgebrochen.")
		return
	end

	-- Zwischen Auswahl und Ablauf der Sekunde kann ein anderer Auftrag
	-- angenommen worden sein.
	if PlayerState.HasOrder(player) then
		PlayerState.Notify(player, "warn", "Du traegst schon einen Auftrag.")
		return
	end

	local tier = Balance.Orders.TierById[offer.tierId]
	local position = pickDeliveryPosition(terminal.Position, tier)
	local basePayout = rng:NextInteger(tier.MinPayout, tier.MaxPayout)

	local point = MapBuilder.CreateDeliveryPoint(
		position,
		string.format("%s · %s", tier.Label, offer.name),
		tier.Color
	)
	pointOwner[point.Prompt] = player
	activePoints[player] = point
	point.Prompt.Triggered:Connect(function(triggeringPlayer)
		onPointTriggered(point.Prompt, triggeringPlayer)
	end)
	point.Prompt.Enabled = true

	local flat = Vector3.new(position.X - terminal.Position.X, 0, position.Z - terminal.Position.Z)

	PlayerState.SetOrder(player, {
		cardId = offer.cardId,
		tierId = tier.Id,
		tierLabel = tier.Label,
		name = offer.name,
		basePayout = basePayout,
		heatGain = tier.Heat,
		distance = math.floor(flat.Magnitude + 0.5),
		point = point,
	})

	attachPackage(player, tier)
	PlayerState.Notify(
		player,
		"info",
		string.format("%s angenommen. Uebergabe in %d Studs.", offer.name, math.floor(flat.Magnitude + 0.5))
	)
end

local function onTerminalTriggered(terminal, player: Player)
	if not RoundManager.IsRunning() then
		return
	end
	if not PlayerState.Get(player) then
		return
	end
	if not PlayerState.ConsumeAction(player, "OpenTerminal") then
		return
	end

	if PlayerState.HasOrder(player) then
		PlayerState.Notify(player, "warn", "Erst den laufenden Auftrag uebergeben.")
		return
	end
	if PlayerState.IsBusy(player) then
		PlayerState.Notify(player, "warn", "Du bist gerade beschaeftigt.")
		return
	end
	if not PlayerState.IsNear(player, terminal.Position, Balance.Orders.InteractRadius) then
		return
	end

	local record = pendingOffers[player]
	local reuse = record ~= nil and record.terminalId == terminal.Id and os.clock() < record.expiresAt

	if not reuse then
		record = buildOffers(player, terminal)
	end

	if not record then
		PlayerState.Notify(player, "warn", "Dieses Terminal hat gerade nichts.")
		return
	end

	Remotes.Get(Remotes.OffersReady):FireClient(player, terminal.Id, record.offers)
end

local function onChooseOrder(player: Player, terminalId: any, offerIndex: any)
	if not RoundManager.IsRunning() then
		return
	end
	if not PlayerState.Get(player) then
		return
	end
	if not PlayerState.ConsumeAction(player, "ChooseOrder") then
		return
	end

	-- Alles, was vom Client kommt, ist erstmal Muell.
	if typeof(terminalId) ~= "string" then
		return
	end
	if typeof(offerIndex) ~= "number" or offerIndex ~= math.floor(offerIndex) then
		return
	end
	if offerIndex < 1 or offerIndex > Balance.Orders.OffersPerTerminal then
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

	if PlayerState.HasOrder(player) then
		PlayerState.Notify(player, "warn", "Erst den laufenden Auftrag uebergeben.")
		return
	end
	if PlayerState.IsBusy(player) then
		PlayerState.Notify(player, "warn", "Du bist gerade beschaeftigt.")
		return
	end
	if not PlayerState.IsNear(player, terminal.Position, Balance.Orders.InteractRadius) then
		PlayerState.Notify(player, "warn", "Zu weit vom Terminal weg.")
		Remotes.Get(Remotes.CloseTerminal):FireClient(player)
		return
	end

	-- Angebot ist verbraucht: naechster Besuch bringt neue Karten.
	pendingOffers[player] = nil

	task.spawn(runAccept, player, terminal, offer)
end

-- -------------------------------------------------------------- Uebergabe --

local function runDeliver(player: Player, order)
	local token = PlayerState.BeginActivity(player, "deliver", order.name, Balance.Orders.DeliverSeconds)
	if not token then
		return
	end

	local deadline = os.clock() + Balance.Orders.DeliverSeconds
	local aborted = false

	while os.clock() < deadline do
		task.wait(Balance.Orders.CheckInterval)

		if not player.Parent or not PlayerState.Get(player) then
			return
		end
		if PlayerState.IsActivityCancelled(player, token) then
			aborted = true
			break
		end
		-- Der Auftrag kann zwischenzeitlich weg sein (Rundenende).
		if PlayerState.GetOrder(player) ~= order then
			aborted = true
			break
		end
		if not PlayerState.IsNear(player, order.point.Position, Balance.Orders.InteractRadius) then
			aborted = true
			break
		end
	end

	PlayerState.EndActivity(player, token)

	if aborted or not RoundManager.IsRunning() then
		if PlayerState.GetOrder(player) == order then
			PlayerState.Notify(player, "bad", "Uebergabe abgebrochen.")
		end
		return
	end

	local state = PlayerState.Get(player)
	if not state then
		return
	end

	-- Risikopraemie aus dem Heat VOR dieser Uebergabe, dann erst der Zuschlag
	-- dieses Auftrags. Endspurt multipliziert obendrauf.
	local premium = Balance.RiskPremium(state.heat)
	local multiplier = RoundManager.PayoutMultiplier()
	local payout = math.floor(order.basePayout * premium * multiplier + 0.5)

	clearOrder(player)

	PlayerState.AddCash(player, payout)
	PlayerState.AddHeat(player, order.heatGain)
	PlayerState.RecordDelivery(player, payout)

	local suffix = if multiplier > 1 then string.format("  (x%d Endspurt)", multiplier) else ""
	PlayerState.Notify(
		player,
		"good",
		string.format("%s: +%d Cash, +%d Heat%s", order.name, payout, order.heatGain, suffix)
	)
end

function onPointTriggered(prompt: ProximityPrompt, player: Player)
	if not RoundManager.IsRunning() then
		return
	end
	if pointOwner[prompt] ~= player then
		-- Fremder Uebergabepunkt. Phase 3 macht daraus vielleicht etwas,
		-- Phase 1 ignoriert es still.
		return
	end
	if not PlayerState.Get(player) then
		return
	end
	if not PlayerState.ConsumeAction(player, "Deliver") then
		return
	end

	local order = PlayerState.GetOrder(player)
	if not order or not order.point or order.point.Prompt ~= prompt then
		return
	end
	if PlayerState.IsBusy(player) then
		PlayerState.Notify(player, "warn", "Du bist gerade beschaeftigt.")
		return
	end
	if not PlayerState.IsNear(player, order.point.Position, Balance.Orders.InteractRadius) then
		return
	end

	task.spawn(runDeliver, player, order)
end

-- ------------------------------------------------------------------ Aufraeumen --

local function releasePlayer(player: Player)
	pendingOffers[player] = nil
	clearOrder(player)

	local list = playerConnections[player]
	if list then
		for _, connection in ipairs(list) do
			connection:Disconnect()
		end
		playerConnections[player] = nil
	end
end

local function resetAll()
	for player, _ in pairs(PlayerState.GetAll()) do
		pendingOffers[player] = nil
	end
	for player, _ in pairs(table.clone(activePoints)) do
		clearOrder(player)
	end

	-- Guertel und Hosentraeger: was sich trotzdem in die Welt gemogelt hat,
	-- verschwindet beim Rundenwechsel. Kein Instance ueberlebt eine Runde.
	MapBuilder.ClearDeliveryPoints()
	table.clear(activePoints)
	table.clear(pointOwner)
end

local function onPlayerAdded(player: Player)
	playerConnections[player] = {}
	table.insert(
		playerConnections[player],
		player.CharacterAdded:Connect(function()
			-- Respawn: das Paket haengt am alten Character. Neu anhaengen,
			-- solange der Auftrag laeuft.
			local order = PlayerState.GetOrder(player)
			if not order then
				return
			end
			local tier = Balance.Orders.TierById[order.tierId]
			if tier then
				task.defer(attachPackage, player, tier)
			end
		end)
	)
end

-- ---------------------------------------------------------------------- Start --

function OrderService.Start()
	if running then
		return
	end
	running = true

	for _, terminal in ipairs(MapBuilder.GetTerminals()) do
		terminal.Prompt.Triggered:Connect(function(player)
			onTerminalTriggered(terminal, player)
		end)
	end

	Remotes.Get(Remotes.ChooseOrder).OnServerEvent:Connect(onChooseOrder)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(releasePlayer)

	RoundManager.OnRoundStart(resetAll)
	RoundManager.OnRoundEnd(resetAll)
end

function OrderService.Stop()
	running = false
end

return OrderService
