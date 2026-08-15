--!nolint
-- Fuenfter Treiber: Phase 3.
-- Abfangen samt Sperre und Einmaligkeit, Bank-Sperrzone fuer Auftraege,
-- Late Join mit Aufholbonus und Zuschauersperre, Live-Leaderboard.

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

local PlayerState = require(Modules:FindFirstChild("PlayerState"))

local map = workspace:FindFirstChild("CashoutMap")
local bankCounter = map:FindFirstChild("Bank"):FindFirstChild("Counter")
local terminals = {}
for _, model in ipairs(map:FindFirstChild("Terminals"):GetChildren()) do
	terminals[model:GetAttribute("TerminalId")] = model:FindFirstChild("Pillar")
end
local ChooseOrder = ReplicatedStorage:FindFirstChild("CashoutRemotes"):FindFirstChild("ChooseOrder")

local failures = {}
local function check(ok, message)
	if not ok then
		table.insert(failures, message)
	end
	print(string.format("  [%s] %s", if ok then "ok " else "FAIL", message))
end

-- ---------------------------------------------------------------- Spieler --

local function makeBot(name, userId, position)
	local bot = { cash = 0, banked = 0, heat = 0, activity = nil, offers = nil, notifies = {} }
	bot.player = Harness.addPlayer(name, userId, position or Vector3.new(60, 3, 60))

	Harness.onClient(bot.player, "StateChanged", function(state)
		bot.cash = state.cash
		bot.banked = state.banked
		bot.heat = state.heat
	end)
	Harness.onClient(bot.player, "ActivityChanged", function(activity)
		bot.activity = activity
	end)
	Harness.onClient(bot.player, "OffersReady", function(terminalId, offers)
		bot.offers = offers
		bot.terminal = terminalId
	end)
	Harness.onClient(bot.player, "CloseTerminal", function()
		bot.offers = nil
	end)
	Harness.onClient(bot.player, "RoundState", function(state)
		bot.round = state
	end)
	Harness.onClient(bot.player, "Scoreboard", function(entries)
		bot.scoreboard = entries
	end)
	Harness.onClient(bot.player, "Notify", function(kind, text)
		table.insert(bot.notifies, kind .. ": " .. text)
	end)
	for _, remoteName in ipairs({ "OrderChanged", "RoundEnded", "RaidStarted", "RaidEnded" }) do
		Harness.onClient(bot.player, remoteName, function() end)
	end

	function bot.moveTo(target)
		local rootPart = bot.player.Character:FindFirstChild("HumanoidRootPart")
		rootPart.Position = Vector3.new(target.X, target.Y, target.Z)
		rootPart.CFrame = CFrame.new(rootPart.Position)
	end
	function bot.lastNotify()
		return bot.notifies[#bot.notifies] or ""
	end

	return bot
end

local a = makeBot("Alpha", 1)
local b = makeBot("Beta", 2)

for _ = 1, 200 do
	Harness.pump(Harness.now() + 1)
	if a.round and a.round.phase == "running" then
		break
	end
end
assert(a.round and a.round.phase == "running", "Runde startet nicht")

print("================ Phase 3 ================")

-- A: Live-Leaderboard ------------------------------------------------------
print("A: Live-Leaderboard")
Harness.pump(Harness.now() + Balance.Net.ScoreboardInterval + 0.5)
check(a.scoreboard ~= nil and #a.scoreboard == 2, "Leaderboard listet beide Spieler")

-- B: Bank-Sperrzone --------------------------------------------------------
print("B: keine Auftraege im Bankumkreis")
-- Terminal direkt neben die Bank holen geht nicht, also andersherum: der
-- Spieler steht am Terminal, aber innerhalb der Sperrzone kann er nicht.
-- Dafuer wird er kuenstlich an die Bank gestellt und ein Terminal-Prompt
-- ausgeloest -- der Distanzcheck zum Terminal schlaegt dann zuerst zu, also
-- wird stattdessen direkt ChooseOrder geprueft.
a.moveTo(terminals.T1.Position)
terminals.T1:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(a.player)
Harness.pump(Harness.now() + 0.5)
check(a.offers ~= nil, "Angebote am Terminal")

local lockoutRadius = Balance.Bank.NoOrderRadius
check(
	(terminals.T1.Position - bankCounter.Position).Magnitude > lockoutRadius,
	"Terminal 1 liegt ausserhalb der Sperrzone (sonst waere der Test sinnlos)"
)

-- C: Abfangen --------------------------------------------------------------
print("C: Abfangen")
PlayerState.AddCash(a.player, 1000)
Harness.pump(Harness.now() + 0.3)

a.moveTo(bankCounter.Position)
b.moveTo(bankCounter.Position)
bankCounter:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(a.player)
Harness.pump(Harness.now() + 0.6)
check(a.activity ~= nil and a.activity.kind == "deposit", "Einzahlung laeuft")

local root = a.player.Character:FindFirstChild("HumanoidRootPart")
local marker = root:FindFirstChild("CashoutDepositMarker")
local interceptPrompt = root:FindFirstChild("CashoutInterceptPrompt")
check(a.player.Character:FindFirstChild("CashoutDepositHighlight") ~= nil, "Einzahlender leuchtet weiss")
check(marker ~= nil, "Schild ueber dem Kopf")
check(interceptPrompt ~= nil, "Abfang-Prompt haengt am Einzahlenden")

-- Selbst abfangen geht nicht.
interceptPrompt.Triggered:Fire(a.player)
Harness.pump(Harness.now() + 0.4)
check(a.cash == 1000, "sich selbst abfangen tut nichts")

local cashBefore = a.cash
local heatBefore = b.heat
interceptPrompt.Triggered:Fire(b.player)
Harness.pump(Harness.now() + 0.4)

local expectedTaken = math.floor(cashBefore * Balance.Intercept.SplitFraction)
check(b.cash == expectedTaken, string.format("Abfaenger bekommt %d auf Cash, hat %d", expectedTaken, b.cash))
check(b.banked == 0, "Abfaenger bekommt es NICHT auf Banked")
check(a.cash == cashBefore - expectedTaken, string.format("Bestohlener behaelt den Rest: %d", a.cash))
check(
	b.heat >= heatBefore + Balance.Intercept.HeatGain - 1,
	string.format("Abfaenger bekommt +%d Heat (%d -> %d)", Balance.Intercept.HeatGain, heatBefore, b.heat)
)
check(root:FindFirstChild("CashoutInterceptPrompt") == nil, "Markierung verschwindet nach dem Abfangen")

-- Zweites Abfangen derselben Einzahlung: nichts mehr zu holen.
local bCashAfterFirst = b.cash
interceptPrompt.Triggered:Fire(b.player)
Harness.pump(Harness.now() + 0.4)
check(b.cash == bCashAfterFirst, "eine Einzahlung laesst sich nur einmal abfangen")

-- Die Einzahlung laeuft mit dem Rest zu Ende.
Harness.pump(Harness.now() + Balance.Bank.DepositSeconds + 1)
check(a.activity == nil, "Einzahlung ist durch")
check(
	a.banked == cashBefore - expectedTaken,
	string.format("Rest ist eingezahlt: erwartet %d, gebucht %d", cashBefore - expectedTaken, a.banked)
)
check(a.cash == 0, "kein Cash mehr uebrig")

-- D: Abfang-Sperre ---------------------------------------------------------
print("D: Abfang-Sperre 45 s")
PlayerState.AddCash(a.player, 600)
Harness.pump(Harness.now() + 0.3)
a.moveTo(bankCounter.Position)
bankCounter:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(a.player)
Harness.pump(Harness.now() + 0.6)

local root2 = a.player.Character:FindFirstChild("HumanoidRootPart")
local prompt2 = root2:FindFirstChild("CashoutInterceptPrompt")
check(prompt2 ~= nil, "zweite Einzahlung ist wieder markiert")

local bCash = b.cash
prompt2.Triggered:Fire(b.player)
Harness.pump(Harness.now() + 0.5)
check(b.cash == bCash, "Abfangen innerhalb der Sperre bringt nichts")
check(string.find(b.lastNotify(), "gesperrt") ~= nil, "Abfaenger wird auf die Sperre hingewiesen")

Harness.pump(Harness.now() + Balance.Bank.DepositSeconds + 1)

-- E: Late Join -------------------------------------------------------------
print("E: Late Join")
-- Alpha hat jetzt Banked; ein spaeter Einsteiger bekommt den halben Median.
-- Erst ueber die Schonfrist hinaus laufen: davor waere kein Bonus korrekt.
local function elapsedNow()
	return Balance.Round.DurationSeconds - (a.round.endsAt - Harness.now())
end
if elapsedNow() <= Balance.LateJoin.GraceSeconds then
	Harness.pump(Harness.now() + (Balance.LateJoin.GraceSeconds - elapsedNow()) + 2)
end
check(
	elapsedNow() > Balance.LateJoin.GraceSeconds,
	string.format("Test laeuft ausserhalb der Schonfrist (%.0f s)", elapsedNow())
)

local c = makeBot("Gamma", 3)
Harness.pump(Harness.now() + 1)

local values = { a.banked, b.banked }
table.sort(values)
local median = (values[1] + values[2]) / 2
local expectedBonus = math.floor(median * Balance.LateJoin.MedianFactor)
check(
	c.banked == expectedBonus,
	string.format("Aufholbonus = Median %d x %.1f = %d, bekommen %d", median, Balance.LateJoin.MedianFactor, expectedBonus, c.banked)
)
check(c.round ~= nil and c.round.spectating == false, "Gamma spielt mit")

-- F: Zuschauersperre in den letzten 45 s ----------------------------------
print("F: Zuschauersperre")
Harness.pump(a.round.endsAt - Balance.LateJoin.LockoutSeconds + 2)
local d = makeBot("Delta", 4)
Harness.pump(Harness.now() + 1)

check(d.round ~= nil and d.round.spectating == true, "Delta ist Zuschauer")
check(d.banked == 0, "Zuschauer bekommt keinen Bonus")

d.moveTo(terminals.T1.Position)
terminals.T1:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(d.player)
Harness.pump(Harness.now() + 0.5)
check(d.offers == nil, "Zuschauer bekommt keine Auftraege")

PlayerState.AddCash(d.player, 500)
d.moveTo(bankCounter.Position)
bankCounter:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(d.player)
Harness.pump(Harness.now() + 0.5)
check(d.activity == nil, "Zuschauer kann nicht einzahlen")

-- G: naechste Runde nimmt den Zuschauer auf ------------------------------
print("G: naechste Runde")
Harness.pump(a.round.endsAt + Balance.Round.IntermissionSeconds + 3)
check(d.round ~= nil and d.round.phase == "running", "naechste Runde laeuft")
check(d.round.spectating == false, "Delta spielt jetzt mit")
check(d.banked == 0 and d.cash == 0, "alles zurueckgesetzt")

print("=========================================")
if #Harness.errors > 0 then
	print("Laufzeitfehler:")
	for index, err in ipairs(Harness.errors) do
		print(index .. ": " .. err)
		if index >= 5 then
			break
		end
	end
	table.insert(failures, #Harness.errors .. " Laufzeitfehler")
end
if #failures == 0 then
	print("ERGEBNIS: alle Phase-3-Pruefungen bestanden")
else
	print("ERGEBNIS: " .. #failures .. " Phase-3-Pruefung(en) fehlgeschlagen")
	for _, failure in ipairs(failures) do
		print("  - " .. failure)
	end
	error(#failures .. " Phase-3-Pruefung(en) fehlgeschlagen", 0)
end
