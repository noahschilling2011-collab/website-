--!nolint
-- Treiber: baut den Instanzbaum, startet Main.server.lua, laesst einen Bot
-- eine volle 300-s-Runde spielen und prueft danach die Zusagen aus Phase 1.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = Harness.makeFolder("Shared", ReplicatedStorage)
Harness.makeModule("Balance", Shared, "Shared/Balance")
Harness.makeModule("DealCatalog", Shared, "Shared/DealCatalog")
Harness.makeModule("Remotes", Shared, "Shared/Remotes")
Harness.makeModule("Assets", Shared, "Shared/Assets")
Harness.makeModule("SoundCatalog", Shared, "Shared/SoundCatalog")

local Modules = Harness.makeFolder("Modules", ServerScriptService)
Harness.makeModule("MapBuilder", Modules, "Modules/MapBuilder")
Harness.makeModule("PlayerState", Modules, "Modules/PlayerState")
Harness.makeModule("RoundManager", Modules, "Modules/RoundManager")
Harness.makeModule("OrderService", Modules, "Modules/OrderService")
Harness.makeModule("HeatService", Modules, "Modules/HeatService")
Harness.makeModule("BankService", Modules, "Modules/BankService")
Harness.makeModule("RaidService", Modules, "Modules/RaidService")

local Balance = require(Shared:FindFirstChild("Balance"))

-- Main als Script laden (kein Modul, also direkt ausfuehren).
do
	local mainScript = Harness.makeInstance("Script", "Main")
	mainScript.Parent = ServerScriptService
	local chunk, err = loadstring("local script = ...\n" .. SOURCES["Main.server"], "@Main.server")
	assert(chunk, "Main.server.lua: " .. tostring(err))
	task.spawn(chunk, mainScript)
end

Harness.pump(0.5)

-- ------------------------------------------------------------------ Welt --

local map = workspace:FindFirstChild("CashoutMap")
if not map then
	for index, err in ipairs(Harness.errors) do
		print("STARTFEHLER " .. index .. ": " .. err)
	end
	error("MapBuilder hat keine Map gebaut")
end

local terminals = {}
for _, model in ipairs(map:FindFirstChild("Terminals"):GetChildren()) do
	table.insert(terminals, {
		id = model:GetAttribute("TerminalId"),
		part = model:FindFirstChild("Pillar"),
	})
end
table.sort(terminals, function(a, b)
	return a.id < b.id
end)

local bankCounter = map:FindFirstChild("Bank"):FindFirstChild("Counter")

-- ------------------------------------------------------------------- Bot --

local WALKSPEED = Balance.Player.WalkSpeed
local DEPOSIT_AT = 700

local report = {
	deliveries = {},
	deposits = {},
	bankedDelta = 0,
	offersSeen = 0,
	extremeOffersBelowHeat50 = 0,
	weightZeroViolations = 0,
	heatDriftWhileCarrying = {},
	notifies = {},
	roundsSeen = 0,
	result = nil,
	maxHeat = 0,
	minHeat = 0,
}

local bot = {
	cash = 0,
	banked = 0,
	heat = 0,
	activity = nil,
	order = nil,
	point = nil,
	offers = nil,
	offerTerminal = nil,
	round = nil,
	heatAtAccept = nil,
	pendingDelivery = nil,
}

local player = Harness.addPlayer("Bot", 1001, Balance.Map.SpawnPosition + Vector3.new(0, 3, 0))

Harness.onClient(player, "StateChanged", function(state)
	local prevCash = bot.cash
	bot.cash = state.cash
	bot.banked = state.banked
	bot.heat = state.heat
	report.maxHeat = math.max(report.maxHeat, state.heat)

	-- Auszahlung einer gerade abgeschlossenen Uebergabe pruefen.
	local pending = bot.pendingDelivery
	if pending and state.cash > prevCash then
		bot.pendingDelivery = nil
		table.insert(report.deliveries, {
			name = pending.name,
			base = pending.base,
			heatBefore = pending.heat,
			heatAfter = state.heat,
			heatGain = pending.heatGain,
			gained = state.cash - pending.cash,
			multiplier = pending.multiplier,
			remaining = pending.remaining,
		})
	end
end)

Harness.onClient(player, "ActivityChanged", function(activity)
	bot.activity = activity
end)

Harness.onClient(player, "OrderChanged", function(order, point)
	if order then
		bot.order = order
		bot.point = point
		bot.heatAtAccept = bot.heat
	else
		if bot.order then
			-- Auftrag verschwindet: entweder Uebergabe oder Rundenende.
			local remaining = if bot.round then bot.round.endsAt - Harness.now() else 0
			bot.pendingDelivery = {
				name = bot.order.name,
				base = bot.order.basePayout,
				heatGain = bot.order.heatGain,
				heat = bot.heat,
				cash = bot.cash,
				remaining = remaining,
				multiplier = if remaining <= (bot.round and bot.round.finalRushSeconds or 60)
					then Balance.Round.FinalRushMultiplier
					else 1,
			}
			if bot.heatAtAccept ~= nil and bot.heat ~= bot.heatAtAccept then
				table.insert(report.heatDriftWhileCarrying, {
					from = bot.heatAtAccept,
					to = bot.heat,
				})
			end
		end
		bot.order = nil
		bot.point = nil
		bot.heatAtAccept = nil
	end
end)

Harness.onClient(player, "OffersReady", function(terminalId, offers)
	bot.offers = offers
	bot.offerTerminal = terminalId
	report.offersSeen += #offers

	local rank = tonumber((string.gsub(terminalId, "^T", "")))
	local profile = Balance.Orders.TerminalProfiles[rank]
	for _, offer in ipairs(offers) do
		if offer.tierId == "Extreme" and bot.heat < 50 then
			report.extremeOffersBelowHeat50 += 1
		end
		if (profile[offer.tierId] or 0) <= 0 then
			report.weightZeroViolations += 1
		end
	end
end)

Harness.onClient(player, "CloseTerminal", function()
	bot.offers = nil
	bot.offerTerminal = nil
end)

Harness.onClient(player, "RoundState", function(state)
	if state.phase == "running" and (not bot.round or bot.round.phase ~= "running") then
		report.roundsSeen += 1
	end
	bot.round = state
end)

Harness.onClient(player, "RoundEnded", function(result)
	report.result = result
end)

Harness.onClient(player, "Notify", function(kind, text)
	table.insert(report.notifies, kind .. ": " .. text)
	if kind == "banked" then
		local amount = tonumber(string.match(text, "%+(%d+)"))
		if amount then
			table.insert(report.deposits, amount)
		end
	end
end)

-- ------------------------------------------------------------- Bot-Logik --

local function root()
	return player.Character:FindFirstChild("HumanoidRootPart")
end

local function moveTo(position)
	local from = root().Position
	local flat = Vector3.new(position.X - from.X, 0, position.Z - from.Z)
	task.wait(flat.Magnitude / WALKSPEED)
	local target = Vector3.new(position.X, from.Y, position.Z)
	root().Position = target
	root().CFrame = CFrame.new(target)
end

local function waitWhileBusy(limit)
	local deadline = Harness.now() + (limit or 20)
	while bot.activity and Harness.now() < deadline do
		task.wait(0.1)
	end
end

local function roundRunning()
	return bot.round ~= nil and bot.round.phase == "running"
end

--[[
	Immer den Auftrag mit dem hoechsten Maximalwert nehmen.
]]
local function bestOfferIndex()
	local bestIndex, bestValue = 1, -1
	for index, offer in ipairs(bot.offers) do
		if offer.maxPayout > bestValue then
			bestIndex, bestValue = index, offer.maxPayout
		end
	end
	return bestIndex
end

local terminalCursor = 0

task.spawn(function()
	local ChooseOrder = ReplicatedStorage:FindFirstChild("CashoutRemotes"):FindFirstChild("ChooseOrder")

	while true do
		task.wait(0.2)
		if not roundRunning() then
			continue
		end

		if bot.order then
			moveTo(bot.point.Position)
			if not roundRunning() or not bot.order then
				continue
			end
			local prompt = bot.point:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Triggered:Fire(player)
			end
			waitWhileBusy(6)
		elseif bot.cash >= DEPOSIT_AT then
			moveTo(bankCounter.Position)
			if not roundRunning() then
				continue
			end
			bankCounter:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(player)
			waitWhileBusy(12)
		else
			terminalCursor = terminalCursor % #terminals + 1
			local terminal = terminals[terminalCursor]
			moveTo(terminal.part.Position)
			if not roundRunning() then
				continue
			end
			terminal.part:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(player)

			local deadline = Harness.now() + 2
			while not bot.offers and Harness.now() < deadline do
				task.wait(0.1)
			end
			if bot.offers then
				ChooseOrder.OnServerEvent:Fire(player, bot.offerTerminal, bestOfferIndex())
				waitWhileBusy(5)
			end
		end
	end
end)

-- Am Rundenende soll auch der Rest eingezahlt werden: ab 60 s vor Schluss
-- senkt der Bot seine Einzahlschwelle.
task.spawn(function()
	while true do
		task.wait(1)
		if roundRunning() and bot.round.endsAt - Harness.now() <= 40 then
			DEPOSIT_AT = 1
		elseif roundRunning() then
			DEPOSIT_AT = 700
		end
	end
end)

-- ------------------------------------------------------------------ Lauf --

-- Pause (15 s) + Runde (300 s) + etwas Puffer fuer die Endtafel.
Harness.pump(Balance.Round.IntermissionSeconds + Balance.Round.DurationSeconds + 5)

-- --------------------------------------------------------------- Auswertung --

local function line(fmt, ...)
	print(string.format(fmt, ...))
end

print("================ CASHOUT v2 Phase 1 — Kopflauf ================")
line("Virtuelle Zeit: %.1f s", Harness.now())
line("Runden gesehen: %d", report.roundsSeen)
line("Angebote gesehen: %d", report.offersSeen)
line("Uebergaben: %d", #report.deliveries)
line("Einzahlungen: %d", #report.deposits)

local depositSum = 0
for _, amount in ipairs(report.deposits) do
	depositSum += amount
end

local standingsBanked = nil
if report.result then
	for _, entry in ipairs(report.result.standings) do
		if entry.userId == 1001 then
			standingsBanked = entry.banked
		end
	end
end

line("Summe der Einzahlungen: %d", depositSum)
line("Banked in der Endtafel: %s", tostring(standingsBanked))
line("Heat-Maximum: %d", report.maxHeat)

local failures = {}

local function check(ok, message)
	if not ok then
		table.insert(failures, message)
	end
end

check(#Harness.errors == 0, string.format("%d Laufzeitfehler", #Harness.errors))
check(report.roundsSeen == 1, "genau eine Runde erwartet, gesehen: " .. report.roundsSeen)
check(report.result ~= nil, "keine Endtafel empfangen")
check(#report.deliveries > 0, "keine einzige Uebergabe zustande gekommen")
check(#report.deposits > 0, "keine einzige Einzahlung zustande gekommen")
check(
	standingsBanked == depositSum,
	string.format("Banked (%s) weicht von der Summe der Einzahlungen (%d) ab", tostring(standingsBanked), depositSum)
)
check(
	#report.heatDriftWhileCarrying == 0,
	string.format("%d mal ist Heat waehrend eines getragenen Auftrags gewandert", #report.heatDriftWhileCarrying)
)
check(
	report.extremeOffersBelowHeat50 == 0,
	string.format("%d Extrem-Karten unter Heat 50 angeboten", report.extremeOffersBelowHeat50)
)
check(
	report.weightZeroViolations == 0,
	string.format("%d Karten an einem Terminal, dessen Profil sie ausschliesst", report.weightZeroViolations)
)
check(report.maxHeat <= Balance.Heat.Max, "Heat ueber dem Maximum")

-- Auszahlungsformel nachrechnen.
local payoutMismatches = 0
local rushSeen = 0
for _, delivery in ipairs(report.deliveries) do
	local premium = Balance.RiskPremium(delivery.heatBefore)
	local expected = math.floor(delivery.base * premium * delivery.multiplier + 0.5)
	if delivery.multiplier > 1 then
		rushSeen += 1
	end
	-- Am Uebergang zum Endspurt darf sich der Multiplikator um einen Tick
	-- unterscheiden; dort beide Varianten zulassen.
	local alternative = math.floor(delivery.base * premium + 0.5)
	local altRush = math.floor(delivery.base * premium * Balance.Round.FinalRushMultiplier + 0.5)
	local nearBoundary = math.abs(delivery.remaining - Balance.Round.FinalRushSeconds) < 1.5
	local ok = delivery.gained == expected
		or (nearBoundary and (delivery.gained == alternative or delivery.gained == altRush))
	if not ok then
		payoutMismatches += 1
		line(
			"  Payout falsch: %s base=%d heat=%d mult=%d erwartet=%d bekommen=%d",
			delivery.name,
			delivery.base,
			delivery.heatBefore,
			delivery.multiplier,
			expected,
			delivery.gained
		)
	end

	local expectedHeat = math.clamp(delivery.heatBefore + delivery.heatGain, 0, Balance.Heat.Max)
	if delivery.heatAfter ~= expectedHeat then
		line(
			"  Heat falsch: %s vorher=%d +%d erwartet=%d bekommen=%d",
			delivery.name,
			delivery.heatBefore,
			delivery.heatGain,
			expectedHeat,
			delivery.heatAfter
		)
		payoutMismatches += 1
	end
end

check(payoutMismatches == 0, payoutMismatches .. " Auszahlungen stimmen nicht mit der Formel ueberein")
check(rushSeen > 0, "kein Endspurt-Payout beobachtet (x2 nie ausgeloest)")

line("Endspurt-Auszahlungen: %d von %d", rushSeen, #report.deliveries)

if report.result then
	local best = report.result.highlights.bestOrder
	line("Hoechster Einzelauftrag: %s (%s)", tostring(best.value), tostring(best.who))
	check(best.who ~= nil, "Endtafel nennt keinen hoechsten Einzelauftrag")
	check(
		report.result.highlights.mostIntercepts.who == nil,
		"Endtafel meldet Abfaenge, obwohl Phase 3 nicht gebaut ist"
	)
end

if #Harness.errors > 0 then
	print("---- Laufzeitfehler ----")
	for index, err in ipairs(Harness.errors) do
		print(index .. ": " .. err)
		if index >= 5 then
			print("... weitere unterdrueckt")
			break
		end
	end
end

print("================================================================")
if #failures == 0 then
	print("ERGEBNIS: alle Pruefungen bestanden")
else
	print("ERGEBNIS: " .. #failures .. " Pruefung(en) fehlgeschlagen")
	for _, failure in ipairs(failures) do
		print("  - " .. failure)
	end
	-- Nicht null zurueckgeben, damit CI daran haengen bleibt.
	error(#failures .. " Pruefung(en) fehlgeschlagen", 0)
end
