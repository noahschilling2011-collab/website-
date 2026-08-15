--!nolint
-- Dritter Treiber: die Razzia aus Phase 2.
-- Fluchtfenster, Grenzfall genau auf dem Radius, Erwischtwerden samt Stun,
-- Aufraeumen bei Rundenende und beim Verlassen des Servers.

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

do
	local mainScript = Harness.makeInstance("Script", "Main")
	mainScript.Parent = ServerScriptService
	local chunk, err = loadstring("local script = ...\n" .. SOURCES["Main.server"], "@Main.server")
	assert(chunk, tostring(err))
	task.spawn(chunk, mainScript)
end

Harness.pump(0.5)

-- Weissbox-Zugriff: nur der Test greift hier direkt zu, um Heat und Cash zu
-- stellen. Ein Auftrag pro Test waere langsamer und wuerde nichts beweisen,
-- was die anderen Treiber nicht schon pruefen.
local PlayerState = require(Modules:FindFirstChild("PlayerState"))

local map = workspace:FindFirstChild("CashoutMap")
local raidFolder = map:FindFirstChild("RaidRings")

local failures = {}
local function check(ok, message)
	if not ok then
		table.insert(failures, message)
	end
	print(string.format("  [%s] %s", if ok then "ok " else "FAIL", message))
end

-- ---------------------------------------------------------------- Spieler --

local function makeBot(name, userId)
	local bot = { cash = 0, banked = 0, heat = 0, activity = nil, raid = nil, ended = nil }
	bot.player = Harness.addPlayer(name, userId, Vector3.new(200, 3, 200))

	Harness.onClient(bot.player, "StateChanged", function(state)
		bot.cash = state.cash
		bot.banked = state.banked
		bot.heat = state.heat
	end)
	Harness.onClient(bot.player, "ActivityChanged", function(activity)
		bot.activity = activity
	end)
	Harness.onClient(bot.player, "RaidStarted", function(info)
		bot.raid = info
		bot.raidCount = (bot.raidCount or 0) + 1
	end)
	Harness.onClient(bot.player, "RaidEnded", function(info)
		bot.raid = nil
		bot.ended = info
	end)
	Harness.onClient(bot.player, "RoundState", function(state)
		bot.round = state
	end)
	for _, name2 in ipairs({ "Notify", "OrderChanged", "OffersReady", "CloseTerminal", "RoundEnded" }) do
		Harness.onClient(bot.player, name2, function() end)
	end

	function bot.moveTo(position)
		local rootPart = bot.player.Character:FindFirstChild("HumanoidRootPart")
		rootPart.Position = Vector3.new(position.X, position.Y, position.Z)
		rootPart.CFrame = CFrame.new(rootPart.Position)
	end
	function bot.position()
		return bot.player.Character:FindFirstChild("HumanoidRootPart").Position
	end
	function bot.humanoid()
		return bot.player.Character:FindFirstChildOfClass("Humanoid")
	end

	return bot
end

local a = makeBot("Alpha", 1)

for _ = 1, 200 do
	Harness.pump(Harness.now() + 1)
	if a.round and a.round.phase == "running" then
		break
	end
end
assert(a.round and a.round.phase == "running", "Runde startet nicht")

--[[
	Waehrend des Fluchtfensters laeuft der normale Heat-Zerfall weiter (er
	pausiert nur mit getragenem Auftrag). Deshalb wird nicht auf den Punkt
	geprueft, sondern auf ein Fenster von so vielen Zerfallstakten, wie in die
	Razzia passen. Ein falscher Verlustwert (15 statt 40) faellt trotzdem sofort
	auf -- der Unterschied ist 25.
]]
local function heatAfterLoss(before, loss)
	local ticks = math.ceil((Balance.Heat.RaidRingSeconds + 1) / Balance.Heat.DecayInterval)
	local target = math.max(0, before - loss)
	return target - ticks, target
end

--[[
	Wartet auf die naechste Razzia. Bei Heat 100 ist p = 35 % pro Check alle
	10 s -- ueber 40 Checks ist ein Ausbleiben praktisch ausgeschlossen.
]]
local function waitForRaid(bot, limit)
	local deadline = Harness.now() + (limit or 400)
	while not bot.raid and Harness.now() < deadline do
		PlayerState.AddHeat(bot.player, Balance.Heat.Max)
		Harness.pump(Harness.now() + 1)
	end
	return bot.raid ~= nil
end

print("================ Razzia ================")

-- A: Fluchtfenster oeffnet sich ueberhaupt -------------------------------
print("A: Fluchtfenster")
a.moveTo(Vector3.new(200, 3, 200))
check(waitForRaid(a), "Razzia loest bei Heat 100 aus")
check(a.raid ~= nil and a.raid.radius == Balance.Heat.RaidRingRadius, "Client bekommt den Radius")
check(#raidFolder:GetChildren() == 1, "genau ein Sperrkreis in der Welt")
local highlight = a.player.Character:FindFirstChild("CashoutRaidHighlight")
check(highlight ~= nil, "Getroffener leuchtet fuer alle sichtbar auf")

-- B: Entkommen ------------------------------------------------------------
print("B: Entkommen")
local origin = a.position()
PlayerState.AddCash(a.player, 1000)
Harness.pump(Harness.now() + 0.3)
local cashBefore = a.cash
local heatBefore = a.heat
a.moveTo(origin + Vector3.new(Balance.Heat.RaidRingRadius + 20, 0, 0))
Harness.pump(Harness.now() + Balance.Heat.RaidRingSeconds + 1)

check(a.ended ~= nil and a.ended.escaped == true, "als entkommen gewertet")
check(a.cash == cashBefore, string.format("Cash bleibt: %d von %d", a.cash, cashBefore))
local lo, hi = heatAfterLoss(heatBefore, Balance.Heat.RaidHeatLossEscaped)
check(
	a.heat >= lo and a.heat <= hi,
	string.format("Heat -%d bei Flucht (%d -> %d, erwartet %d..%d)", Balance.Heat.RaidHeatLossEscaped, heatBefore, a.heat, lo, hi)
)
check(#raidFolder:GetChildren() == 0, "Sperrkreis abgeraeumt")
check(a.player.Character:FindFirstChild("CashoutRaidHighlight") == nil, "Highlight entfernt")
check(a.activity == nil, "kein Stun nach erfolgreicher Flucht")

-- C: Erwischt -------------------------------------------------------------
print("C: Erwischt")
a.ended = nil
check(waitForRaid(a), "zweite Razzia loest aus")
cashBefore = a.cash
heatBefore = a.heat
-- Stehen bleiben.
Harness.pump(Harness.now() + Balance.Heat.RaidRingSeconds + 0.5)

local expectedKept = math.floor(cashBefore * Balance.Heat.RaidCashKeptFraction)
check(a.ended ~= nil and a.ended.escaped == false, "als erwischt gewertet")
check(a.cash == expectedKept, string.format("Cash x%.2f: erwartet %d, bekommen %d", Balance.Heat.RaidCashKeptFraction, expectedKept, a.cash))
lo, hi = heatAfterLoss(heatBefore, Balance.Heat.RaidHeatLossCaught)
check(
	a.heat >= lo and a.heat <= hi,
	string.format("Heat -%d beim Erwischtwerden (%d -> %d, erwartet %d..%d)", Balance.Heat.RaidHeatLossCaught, heatBefore, a.heat, lo, hi)
)
check(a.activity ~= nil and a.activity.kind == "stun", "Stun laeuft")
check(a.humanoid().WalkSpeed == 0, "festgesetzt: WalkSpeed 0")

Harness.pump(Harness.now() + Balance.Heat.RaidStunSeconds + 0.5)
check(a.activity == nil, "Stun endet nach " .. Balance.Heat.RaidStunSeconds .. " s")
check(a.humanoid().WalkSpeed == Balance.Player.WalkSpeed, "WalkSpeed wiederhergestellt")

-- D: Grenzfall genau auf dem Radius --------------------------------------
print("D: genau auf dem Radius")
a.ended = nil
PlayerState.AddCash(a.player, 1000)
check(waitForRaid(a), "dritte Razzia loest aus")
origin = a.position()
a.moveTo(origin + Vector3.new(Balance.Heat.RaidRingRadius, 0, 0))
Harness.pump(Harness.now() + Balance.Heat.RaidRingSeconds + 1)
check(a.ended ~= nil and a.ended.escaped == false, "genau auf der Grenze zaehlt als drinnen")

Harness.pump(Harness.now() + Balance.Heat.RaidStunSeconds + 0.5)

-- E: Hoehe zaehlt nicht mit ----------------------------------------------
print("E: nur die Grundflaeche zaehlt")
a.ended = nil
check(waitForRaid(a), "vierte Razzia loest aus")
origin = a.position()
-- 100 Studs nach oben, aber waagerecht keinen Zentimeter weg.
a.moveTo(Vector3.new(origin.X, origin.Y + 100, origin.Z))
Harness.pump(Harness.now() + Balance.Heat.RaidRingSeconds + 1)
check(a.ended ~= nil and a.ended.escaped == false, "nach oben ausweichen rettet nicht")
Harness.pump(Harness.now() + Balance.Heat.RaidStunSeconds + 0.5)

-- F: Verlassen des Servers waehrend der Razzia ---------------------------
print("F: Verlassen waehrend der Razzia")
local b = makeBot("Beta", 2)
Harness.pump(Harness.now() + 0.5)
b.moveTo(Vector3.new(-200, 3, -200))
check(waitForRaid(b), "Razzia fuer Beta")
local errorsBefore = #Harness.errors
Harness.removePlayer(b.player)
Harness.pump(Harness.now() + Balance.Heat.RaidRingSeconds + 2)
check(#Harness.errors == errorsBefore, "kein Fehler beim Verlassen im Fluchtfenster")
check(#raidFolder:GetChildren() == 0, "Sperrkreis des gegangenen Spielers abgeraeumt")

-- G: Rundenende mitten im Fluchtfenster ----------------------------------
print("G: Rundenende im Fluchtfenster")
a.ended = nil
PlayerState.AddCash(a.player, 500)
Harness.pump(Harness.now() + 0.3)
local roundEnd = a.round.endsAt
-- Kurz vor Schluss eine Razzia erzwingen, die ueber das Rundenende hinausragt.
Harness.pump(roundEnd - 2)
PlayerState.AddHeat(a.player, Balance.Heat.Max)
local gotOne = false
for _ = 1, 4 do
	Harness.pump(Harness.now() + 0.5)
	if a.raid then
		gotOne = true
		break
	end
end
errorsBefore = #Harness.errors
Harness.pump(roundEnd + Balance.Heat.RaidRingSeconds + 2)
check(#Harness.errors == errorsBefore, "kein Fehler beim Rundenende im Fluchtfenster")
check(#raidFolder:GetChildren() == 0, "kein Sperrkreis ueberlebt das Rundenende")
if gotOne then
	print("     (Razzia lief tatsaechlich ins Rundenende hinein)")
end

-- H: Sterben im Fluchtfenster ist keine Flucht --------------------------
print("H: Respawn im Fluchtfenster")
a.ended = nil
-- Cash ERST setzen, wenn die Razzia laeuft. Vorher kann ein Rundenwechsel
-- dazwischenkommen und alles auf null zuruecksetzen -- dann prueft die
-- Zusicherung unten 0 gegen 0 und ist wertlos.
check(waitForRaid(a), "Razzia fuer den Respawn-Test")
PlayerState.AddCash(a.player, 1000)
Harness.pump(Harness.now() + 0.3)
local cashBeforeRespawn = a.cash
check(cashBeforeRespawn == 1000, "der Test traegt wirklich Cash: " .. cashBeforeRespawn)
-- Sterben und weit weg wieder auftauchen -- genau das, was der Spawnpunkt tut.
Harness.respawn(a.player, Balance.Map.SpawnPosition + Vector3.new(0, 3, 0))
Harness.pump(Harness.now() + Balance.Heat.RaidRingSeconds + 1)
check(
	a.ended ~= nil and a.ended.escaped == false,
	"Sterben im Fluchtfenster zaehlt als erwischt, nicht als Flucht"
)
check(
	a.cash == math.floor(cashBeforeRespawn * Balance.Heat.RaidCashKeptFraction),
	string.format("und kostet entsprechend Cash: %d von %d", a.cash, cashBeforeRespawn)
)
Harness.pump(Harness.now() + Balance.Heat.RaidStunSeconds + 0.5)

-- I: Abbruch meldet sich beim Client -------------------------------------
print("I: abgebrochene Razzia meldet sich ab")
a.ended = nil
check(waitForRaid(a), "Razzia fuer den Abbruch-Test")
local errorsBeforeAbort = #Harness.errors
-- Verlassen und wiederkommen ist der eine Abbruchweg; der andere ist das
-- Rundenende, das Fall G schon abdeckt.
local c = makeBot("Gamma", 3)
Harness.pump(Harness.now() + 0.5)
check(waitForRaid(c), "Razzia fuer Gamma")
c.ended = nil
-- Rundenende erzwingen, indem bis dahin gelaufen wird.
Harness.pump(c.round.endsAt + 1)
check(
	c.ended ~= nil,
	"der Client bekommt ein RaidEnded, wenn die Razzia beim Rundenende abgebrochen wird"
)
check(#Harness.errors == errorsBeforeAbort, "kein Fehler beim Abbruch")

print("========================================")
if #Harness.errors > 0 then
	print("Laufzeitfehler:")
	for index, err in ipairs(Harness.errors) do
		print(index .. ": " .. err)
		if index >= 5 then
			break
		end
	end
end
if #failures == 0 then
	print("ERGEBNIS: alle Razzia-Pruefungen bestanden")
else
	print("ERGEBNIS: " .. #failures .. " Razzia-Pruefung(en) fehlgeschlagen")
	for _, failure in ipairs(failures) do
		print("  - " .. failure)
	end
	error(#failures .. " Razzia-Pruefung(en) fehlgeschlagen", 0)
end
