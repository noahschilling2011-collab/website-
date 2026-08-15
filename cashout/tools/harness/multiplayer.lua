--!nolint
-- Sechster Treiber: sechs Bots in einer Runde, mit gegensaetzlichen Strategien.
--
-- Der Simulator rechnet einen Spieler allein. Der sagt nichts darueber, ob
-- Bankcamping sich lohnt, ob Laeufer sich gegenseitig ausbremsen oder ob bei
-- zwoelf Spielern irgendetwas kippt. Das hier laesst sie wirklich
-- gegeneinander laufen -- gegen den echten Servercode.
--
-- Geprueft wird nicht auf eine Wunschzahl, sondern auf drei Zusagen:
--   * kein Laufzeitfehler bei sechs gleichzeitigen Spielern,
--   * die Buchhaltung stimmt fuer jeden einzelnen (Banked = Summe seiner
--     Einzahlungen + Abfangbeute, die er selbst heimgebracht hat),
--   * Bankcamping schlaegt Spielen nicht.
-- Die Rangliste selbst wird ausgegeben, damit man sieht, was passiert ist.

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

local Players = game:GetService("Players")
local map = workspace:FindFirstChild("CashoutMap")
local bankCounter = map:FindFirstChild("Bank"):FindFirstChild("Counter")
local ChooseOrder = ReplicatedStorage:FindFirstChild("CashoutRemotes"):FindFirstChild("ChooseOrder")

local terminals = {}
for _, model in ipairs(map:FindFirstChild("Terminals"):GetChildren()) do
	table.insert(terminals, { id = model:GetAttribute("TerminalId"), part = model:FindFirstChild("Pillar") })
end
table.sort(terminals, function(a, b)
	return a.id < b.id
end)

local WALK = Balance.Player.WalkSpeed

-- ---------------------------------------------------------------- Bot-Bau --

local bots = {}

local function makeBot(name, userId, role)
	local bot = {
		name = name,
		role = role,
		cash = 0,
		banked = 0,
		heat = 0,
		activity = nil,
		order = nil,
		point = nil,
		offers = nil,
		terminal = nil,
		round = nil,
		deposited = 0,
		intercepted = 0,
		interceptedFor = 0,
		lostToIntercept = 0,
		raidsCaught = 0,
		raidsEscaped = 0,
		maxHeat = 0,
		heatSum = 0,
		heatSamples = 0,
	}
	bot.player = Harness.addPlayer(name, userId, Vector3.new(0, 3, 40))

	Harness.onClient(bot.player, "StateChanged", function(state)
		bot.cash = state.cash
		bot.banked = state.banked
		bot.heat = state.heat
		bot.maxHeat = math.max(bot.maxHeat, state.heat)
		bot.heatSum += state.heat
		bot.heatSamples += 1
	end)
	Harness.onClient(bot.player, "ActivityChanged", function(activity)
		bot.activity = activity
	end)
	Harness.onClient(bot.player, "OrderChanged", function(order, point)
		bot.order = order
		bot.point = point
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
	Harness.onClient(bot.player, "RoundEnded", function(result)
		bot.result = result
	end)
	Harness.onClient(bot.player, "RaidEnded", function(info)
		if info and info.escaped then
			bot.raidsEscaped += 1
		else
			bot.raidsCaught += 1
		end
	end)
	Harness.onClient(bot.player, "RaidStarted", function() end)
	Harness.onClient(bot.player, "Scoreboard", function() end)
	Harness.onClient(bot.player, "Notify", function(kind, text)
		if kind == "banked" then
			local amount = tonumber(string.match(text, "%+(%d+)"))
			if amount then
				bot.deposited += amount
			end
		elseif kind == "good" and string.find(text, "abgefangen") then
			local amount = tonumber(string.match(text, "(%d+) abgefangen"))
			if amount then
				bot.intercepted += 1
				bot.interceptedFor += amount
			end
		elseif kind == "bad" and string.find(text, "Abgefangen") then
			local amount = tonumber(string.match(text, "%-(%d+)"))
			if amount then
				bot.lostToIntercept += amount
			end
		end
	end)

	function bot.root()
		local character = bot.player.Character
		return character and character:FindFirstChild("HumanoidRootPart")
	end
	function bot.moveTo(position)
		local rootPart = bot.root()
		if not rootPart then
			return
		end
		local from = rootPart.Position
		local flat = Vector3.new(position.X - from.X, 0, position.Z - from.Z)
		task.wait(flat.Magnitude / WALK)
		local landed = bot.root()
		if landed then
			landed.Position = Vector3.new(position.X, from.Y, position.Z)
			landed.CFrame = CFrame.new(landed.Position)
		end
	end
	function bot.waitIdle(limit)
		local deadline = Harness.now() + (limit or 20)
		while bot.activity and Harness.now() < deadline do
			task.wait(0.1)
		end
	end
	function bot.running()
		return bot.round ~= nil and bot.round.phase == "running" and not bot.round.spectating
	end

	table.insert(bots, bot)
	return bot
end

-- --------------------------------------------------------------- Rollen --

--[[
	Laeufer: nimmt am Terminal immer die wertvollste Karte, uebergibt, zahlt ab
	einer Schwelle ein.
]]
local function runRunner(bot, threshold)
	local cursor = 0
	while true do
		task.wait(0.25)
		if not bot.running() then
			continue
		end

		if bot.order then
			if bot.point and bot.point.Parent then
				bot.moveTo(bot.point.Position)
				local prompt = bot.point:FindFirstChildOfClass("ProximityPrompt")
				if prompt and bot.running() then
					prompt.Triggered:Fire(bot.player)
					bot.waitIdle(6)
				end
			else
				task.wait(1)
			end
		elseif bot.cash >= threshold then
			bot.moveTo(bankCounter.Position)
			if bot.running() then
				bankCounter:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(bot.player)
				bot.waitIdle(14)
			end
		else
			cursor = cursor % #terminals + 1
			local terminal = terminals[cursor]
			bot.moveTo(terminal.part.Position)
			if not bot.running() then
				continue
			end
			terminal.part:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(bot.player)

			local deadline = Harness.now() + 2
			while not bot.offers and Harness.now() < deadline do
				task.wait(0.1)
			end
			if bot.offers then
				local bestIndex, bestValue = 1, -1
				for index, offer in ipairs(bot.offers) do
					if offer.maxPayout > bestValue then
						bestIndex, bestValue = index, offer.maxPayout
					end
				end
				ChooseOrder.OnServerEvent:Fire(bot.player, bot.terminal, bestIndex)
				bot.waitIdle(5)
			end
		end
	end
end

--[[
	Camper: steht an der Bank und fangt ab, was sich zeigt. Nimmt selbst nie
	einen Auftrag an -- die Sperrzone um die Bank verbietet das ohnehin.
	Zahlt seine Beute ein, sobald sie sich lohnt.
]]
local function runCamper(bot)
	while true do
		task.wait(0.3)
		if not bot.running() then
			continue
		end

		local rootPart = bot.root()
		if not rootPart then
			continue
		end
		if (rootPart.Position - bankCounter.Position).Magnitude > 4 then
			bot.moveTo(bankCounter.Position)
			continue
		end

		-- Nach jemandem suchen, der gerade einzahlt.
		local target = nil
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= bot.player then
				local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
				local prompt = otherRoot and otherRoot:FindFirstChild("CashoutInterceptPrompt")
				if prompt then
					target = prompt
					break
				end
			end
		end

		if target then
			target.Triggered:Fire(bot.player)
			task.wait(0.4)
		elseif bot.cash > 0 and not bot.activity then
			bankCounter:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(bot.player)
			bot.waitIdle(14)
		end
	end
end

-- ------------------------------------------------------------------- Lauf --

local runnerA = makeBot("Laeufer-A", 1, "Laeufer (Bank ab 800)")
local runnerB = makeBot("Laeufer-B", 2, "Laeufer (Bank ab 1500)")
local runnerC = makeBot("Laeufer-C", 3, "Laeufer (Bank ab 400)")
local farmer = makeBot("Kleinvieh", 4, "Laeufer (Bank ab 200)")
local camperA = makeBot("Camper-A", 5, "Bankcamper")
local camperB = makeBot("Camper-B", 6, "Bankcamper")

for _ = 1, 200 do
	Harness.pump(Harness.now() + 1)
	if runnerA.round and runnerA.round.phase == "running" then
		break
	end
end
assert(runnerA.round and runnerA.round.phase == "running", "Runde startet nicht")

task.spawn(runRunner, runnerA, 800)
task.spawn(runRunner, runnerB, 1500)
task.spawn(runRunner, runnerC, 400)
task.spawn(runRunner, farmer, 200)
task.spawn(runCamper, camperA)
task.spawn(runCamper, camperB)

local roundEnd = runnerA.round.endsAt
Harness.pump(roundEnd + 3)

-- -------------------------------------------------------------- Auswertung --

print("================ Sechs Bots, eine Runde ================")
print(string.format("%-12s %-22s %8s %8s %7s %9s %8s %6s %6s", "Bot", "Rolle", "Banked", "Einzahl", "Abgef.", "verloren", "Razzien", "HeatØ", "Heat^"))

local standings = runnerA.result and runnerA.result.standings or {}
local bankedById = {}
for _, entry in ipairs(standings) do
	bankedById[entry.userId] = entry.banked
end

table.sort(bots, function(a, b)
	return (bankedById[a.player.UserId] or 0) > (bankedById[b.player.UserId] or 0)
end)

for _, bot in ipairs(bots) do
	print(string.format(
		"%-12s %-22s %8d %8d %7d %9d %8s %6.1f %6d",
		bot.name,
		bot.role,
		bankedById[bot.player.UserId] or 0,
		bot.deposited,
		bot.intercepted,
		bot.lostToIntercept,
		string.format("%d/%d", bot.raidsCaught, bot.raidsCaught + bot.raidsEscaped),
		if bot.heatSamples > 0 then bot.heatSum / bot.heatSamples else 0,
		bot.maxHeat
	))
end

local failures = {}
local function check(ok, message)
	if not ok then
		table.insert(failures, message)
	end
	print(string.format("  [%s] %s", if ok then "ok " else "FAIL", message))
end

print("")
check(#Harness.errors == 0, "kein Laufzeitfehler bei sechs gleichzeitigen Spielern")
check(#standings == #bots, "die Endtafel listet alle sechs")

-- Buchhaltung: Banked ist genau die Summe der eigenen Einzahlungen.
local bookkeepingOk = true
for _, bot in ipairs(bots) do
	local banked = bankedById[bot.player.UserId] or 0
	if banked ~= bot.deposited then
		bookkeepingOk = false
		print(string.format("     %s: Banked %d, aber %d eingezahlt", bot.name, banked, bot.deposited))
	end
end
check(bookkeepingOk, "Banked jedes Spielers = Summe seiner eigenen Einzahlungen")

-- Die eigentliche Frage: schlaegt Campen das Spielen?
local bestRunner, bestCamper = 0, 0
for _, bot in ipairs(bots) do
	local banked = bankedById[bot.player.UserId] or 0
	if bot.role == "Bankcamper" then
		bestCamper = math.max(bestCamper, banked)
	else
		bestRunner = math.max(bestRunner, banked)
	end
end
print("")
print(string.format("bester Laeufer: %d    bester Camper: %d", bestRunner, bestCamper))
check(bestRunner > bestCamper, "Spielen schlaegt Bankcamping")

-- Kein Test, sondern eine Meldung: wenn in einer vollen Runde mit sechs
-- Spielern keine einzige Razzia faellt, ist Phase 2 im echten Spiel Deko.
local totalRaids = 0
local peakHeat = 0
for _, bot in ipairs(bots) do
	totalRaids += bot.raidsCaught + bot.raidsEscaped
	peakHeat = math.max(peakHeat, bot.maxHeat)
end
print("")
print(string.format(
	"Razzien in dieser Runde ueber alle Spieler: %d.  Hoechster Heat irgendwo: %d.",
	totalRaids,
	peakHeat
))
if totalRaids == 0 then
	print("HINWEIS: die Razzia hat kein einziges Mal ausgeloest. Das ist kein Fehler im")
	print("Code, sondern dieselbe Beobachtung wie der gerissene Heat-Korridor im")
	print("Simulator -- hier nur mit echten Spielern statt im Modell.")
end

print("========================================================")
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
	print("ERGEBNIS: alle Mehrspieler-Pruefungen bestanden")
else
	print("ERGEBNIS: " .. #failures .. " Mehrspieler-Pruefung(en) fehlgeschlagen")
	for _, failure in ipairs(failures) do
		print("  - " .. failure)
	end
	error(#failures .. " Mehrspieler-Pruefung(en) fehlgeschlagen", 0)
end
