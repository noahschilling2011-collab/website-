--!nolint
-- Zweiter Treiber: Grenzfaelle statt Normalbetrieb.
-- Muell vom Client, Drossel, fremde Uebergabepunkte, Weglaufen, Verlassen des
-- Servers mit offenem Auftrag, Rundenende mitten in einer Interaktion.

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

local Balance = require(Shared:FindFirstChild("Balance"))

do
	local mainScript = Harness.makeInstance("Script", "Main")
	mainScript.Parent = ServerScriptService
	local chunk, err = loadstring("local script = ...\n" .. SOURCES["Main.server"], "@Main.server")
	assert(chunk, tostring(err))
	task.spawn(chunk, mainScript)
end

Harness.pump(0.5)

local map = workspace:FindFirstChild("CashoutMap")
local deliveryFolder = map:FindFirstChild("DeliveryPoints")
local terminals = {}
for _, model in ipairs(map:FindFirstChild("Terminals"):GetChildren()) do
	terminals[model:GetAttribute("TerminalId")] = model:FindFirstChild("Pillar")
end
local bankCounter = map:FindFirstChild("Bank"):FindFirstChild("Counter")
local ChooseOrder = ReplicatedStorage:FindFirstChild("CashoutRemotes"):FindFirstChild("ChooseOrder")

-- ---------------------------------------------------------------- Spieler --

local function makeBot(name, userId)
	local bot = { offers = nil, terminal = nil, order = nil, point = nil, cash = 0, banked = 0, heat = 0 }
	bot.player = Harness.addPlayer(name, userId, Balance.Map.SpawnPosition + Vector3.new(0, 3, 0))
	bot.offersReceived = 0
	bot.activity = nil

	Harness.onClient(bot.player, "OffersReady", function(terminalId, offers)
		bot.offers = offers
		bot.terminal = terminalId
		bot.offersReceived += 1
	end)
	Harness.onClient(bot.player, "OrderChanged", function(order, point)
		bot.order = order
		bot.point = point
	end)
	Harness.onClient(bot.player, "StateChanged", function(state)
		bot.cash = state.cash
		bot.banked = state.banked
		bot.heat = state.heat
	end)
	Harness.onClient(bot.player, "ActivityChanged", function(activity)
		bot.activity = activity
	end)
	Harness.onClient(bot.player, "Notify", function() end)
	Harness.onClient(bot.player, "CloseTerminal", function()
		bot.offers = nil
	end)
	Harness.onClient(bot.player, "RoundState", function(state)
		bot.round = state
	end)
	Harness.onClient(bot.player, "RoundEnded", function(result)
		bot.result = result
	end)

	function bot.moveTo(position)
		local rootPart = bot.player.Character:FindFirstChild("HumanoidRootPart")
		rootPart.Position = Vector3.new(position.X, position.Y, position.Z)
		rootPart.CFrame = CFrame.new(rootPart.Position)
	end

	return bot
end

local a = makeBot("Alpha", 1)
local b = makeBot("Beta", 2)

-- Bis die Runde wirklich laeuft. Der RoundManager haengt erst in der
-- Warteschleife, bis genug Spieler da sind -- die Pause startet also nach dem
-- Beitritt, nicht bei t=0.
for _ = 1, 200 do
	Harness.pump(Harness.now() + 1)
	if a.round and a.round.phase == "running" then
		break
	end
end
assert(a.round and a.round.phase == "running", "Runde startet nicht")

local failures = {}
local function check(ok, message)
	if not ok then
		table.insert(failures, message)
	end
	print(string.format("  [%s] %s", if ok then "ok " else "FAIL", message))
end

local errorsBefore = #Harness.errors

print("================ Grenzfaelle ================")

-- A: Muell vom Client ------------------------------------------------------
print("A: Muellargumente an ChooseOrder")
a.moveTo(terminals.T1.Position)
terminals.T1:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(a.player)
Harness.pump(Harness.now() + 0.5)
check(a.offers ~= nil, "Terminal liefert drei Karten")

local junk = {
	{ nil, nil },
	{ "T1", 0 },
	{ "T1", -1 },
	{ "T1", 99 },
	{ "T1", 1.5 },
	{ "T1", "1" },
	{ "T1", {} },
	{ 42, 1 },
	{ {}, 1 },
	{ "T9", 1 },
	{ "T1", math.huge },
	{ "T1", 0 / 0 },
}
for _, args in ipairs(junk) do
	ChooseOrder.OnServerEvent:Fire(a.player, args[1], args[2])
	Harness.pump(Harness.now() + 0.4)
end
check(#Harness.errors == errorsBefore, "kein Serverfehler durch Muellargumente")
check(a.order == nil, "kein Auftrag durch Muellargumente entstanden")
check(a.cash == 0, "kein Cash durch Muellargumente entstanden")

-- B: Drossel ---------------------------------------------------------------
print("B: Drossel (ein Aufruf pro Aktion pro 0,3 s)")
a.offersReceived = 0
local prompt = terminals.T1:FindFirstChildOfClass("ProximityPrompt")
for _ = 1, 10 do
	prompt.Triggered:Fire(a.player)
end
Harness.pump(Harness.now() + 0.05)
check(a.offersReceived <= 1, "10 Prompt-Ausloesungen im selben Tick ergeben hoechstens ein Angebot, waren: " .. a.offersReceived)

-- C: Auftrag annehmen ------------------------------------------------------
print("C: Auftrag annehmen und uebergeben")
Harness.pump(Harness.now() + 1)
prompt.Triggered:Fire(a.player)
Harness.pump(Harness.now() + 0.3)
check(a.offers ~= nil, "Angebote nach der Drossel wieder da")
ChooseOrder.OnServerEvent:Fire(a.player, a.terminal, 1)
Harness.pump(Harness.now() + Balance.Orders.AcceptSeconds + 0.6)
check(a.order ~= nil, "Auftrag angenommen")
check(#deliveryFolder:GetChildren() == 1, "genau ein Uebergabepunkt in der Welt")

local packageAttached = a.player.Character:FindFirstChild("CashoutPackage") ~= nil
check(packageAttached, "Paket haengt am Character")

-- D: Fremder darf den Punkt nicht ausloesen --------------------------------
print("D: fremder Uebergabepunkt")
local pointPrompt = a.point:FindFirstChildOfClass("ProximityPrompt")
b.moveTo(a.point.Position)
pointPrompt.Triggered:Fire(b.player)
Harness.pump(Harness.now() + 0.5)
check(b.activity == nil, "Beta kann Alphas Uebergabepunkt nicht ausloesen")
check(b.cash == 0, "Beta bekommt nichts von Alphas Auftrag")
check(a.order ~= nil, "Alphas Auftrag ist noch da")

-- E: Weglaufen bricht die Uebergabe ab --------------------------------------
print("E: Weglaufen waehrend der Uebergabe")
a.moveTo(a.point.Position)
pointPrompt.Triggered:Fire(a.player)
Harness.pump(Harness.now() + 0.3)
check(a.activity ~= nil, "Uebergabe laeuft")
a.moveTo(Vector3.new(400, 3, 400))
Harness.pump(Harness.now() + Balance.Orders.DeliverSeconds + 1)
check(a.order ~= nil, "Auftrag bleibt nach Abbruch bestehen")
check(a.cash == 0, "kein Geld fuer eine abgebrochene Uebergabe")

-- F: Uebergabe sauber zu Ende --------------------------------------------
print("F: Uebergabe zu Ende")
a.moveTo(a.point.Position)
pointPrompt.Triggered:Fire(a.player)
Harness.pump(Harness.now() + Balance.Orders.DeliverSeconds + 0.8)
check(a.order == nil, "Auftrag nach der Uebergabe weg")
check(a.cash > 0, "Cash gutgeschrieben: " .. a.cash)
check(#deliveryFolder:GetChildren() == 0, "Uebergabepunkt abgeraeumt")
check(a.player.Character:FindFirstChild("CashoutPackage") == nil, "Paket entfernt")

-- G: Einzahlung abbrechen --------------------------------------------------
print("G: Einzahlung abbrechen und dann durchziehen")
local cashBefore = a.cash
a.moveTo(bankCounter.Position)
bankCounter:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(a.player)
Harness.pump(Harness.now() + 1)
a.moveTo(Vector3.new(400, 3, 400))
Harness.pump(Harness.now() + Balance.Bank.DepositSeconds + 1)
check(a.banked == 0, "abgebrochene Einzahlung bucht nichts")
check(a.cash == cashBefore, "Cash nach Abbruch unveraendert")

a.moveTo(bankCounter.Position)
bankCounter:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(a.player)
Harness.pump(Harness.now() + Balance.Bank.DepositSeconds + 1)
check(a.banked == cashBefore, string.format("Einzahlung bucht %d, gebucht: %d", cashBefore, a.banked))
check(a.cash == 0, "Cash nach der Einzahlung leer")

-- H: Einzahlen ohne Cash ---------------------------------------------------
print("H: Einzahlen ohne Cash")
bankCounter:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(a.player)
Harness.pump(Harness.now() + 0.5)
check(a.activity == nil, "leere Einzahlung startet nicht")

-- I: Spieler verlaesst den Server mit offenem Auftrag ----------------------
print("I: Verlassen mit offenem Auftrag")
b.moveTo(terminals.T3.Position)
terminals.T3:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(b.player)
Harness.pump(Harness.now() + 0.4)
ChooseOrder.OnServerEvent:Fire(b.player, b.terminal, 1)
Harness.pump(Harness.now() + Balance.Orders.AcceptSeconds + 0.6)
check(b.order ~= nil, "Beta traegt einen Auftrag")
check(#deliveryFolder:GetChildren() == 1, "Betas Punkt steht")

local errorsBeforeLeave = #Harness.errors
Harness.removePlayer(b.player)
Harness.pump(Harness.now() + 2)
check(#Harness.errors == errorsBeforeLeave, "kein Fehler beim Verlassen mit offenem Auftrag")
check(#deliveryFolder:GetChildren() == 0, "Punkt des gegangenen Spielers abgeraeumt")

-- J: Rundenende mitten in einer Interaktion --------------------------------
print("J: Rundenende mitten in einer Uebergabe")
a.moveTo(terminals.T5.Position)
terminals.T5:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(a.player)
Harness.pump(Harness.now() + 0.4)
if a.offers then
	ChooseOrder.OnServerEvent:Fire(a.player, a.terminal, 1)
	Harness.pump(Harness.now() + Balance.Orders.AcceptSeconds + 0.6)
end
check(a.order ~= nil, "Auftrag fuer den Rundenschluss angenommen")

local bankedBeforeEnd = a.banked
-- Bis kurz vor Rundenende laufen, dann mitten in der Uebergabe stehen.
local roundEnd = a.round.endsAt
Harness.pump(roundEnd - Balance.Orders.DeliverSeconds / 2)
a.moveTo(a.point.Position)
a.point:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(a.player)
local errorsBeforeEnd = #Harness.errors
Harness.pump(roundEnd + 3)

check(#Harness.errors == errorsBeforeEnd, "kein Fehler beim Rundenende in einer Interaktion")
check(a.result ~= nil, "Endtafel empfangen")
check(a.cash == 0, "nicht eingezahlter Cash ist am Rundenende weg")
check(#deliveryFolder:GetChildren() == 0, "keine Uebergabepunkte ueberleben das Rundenende")
check(a.activity == nil, "keine Interaktion ueberlebt das Rundenende")
if a.result then
	local mine
	for _, entry in ipairs(a.result.standings) do
		if entry.userId == 1 then
			mine = entry
		end
	end
	check(mine ~= nil and mine.banked == bankedBeforeEnd, "Endtafel zeigt das eingezahlte Geld")
end

-- K: Neue Runde setzt zurueck ----------------------------------------------
print("K: naechste Runde setzt zurueck")
Harness.pump(Harness.now() + Balance.Round.IntermissionSeconds + 2)
check(a.round.phase == "running", "naechste Runde laeuft, Phase: " .. tostring(a.round.phase))
check(a.banked == 0, "Banked ist zum Rundenstart zurueckgesetzt")
check(a.heat == 0, "Heat ist zum Rundenstart zurueckgesetzt")

print("=============================================")
if #Harness.errors > 0 then
	print("Laufzeitfehler:")
	for index, err in ipairs(Harness.errors) do
		print(index .. ": " .. err)
		if index >= 6 then
			break
		end
	end
end
if #failures == 0 then
	print("ERGEBNIS: alle Grenzfaelle bestanden")
else
	print("ERGEBNIS: " .. #failures .. " Grenzfall/Grenzfaelle fehlgeschlagen")
	error(#failures .. " Grenzfall/Grenzfaelle fehlgeschlagen", 0)
end
