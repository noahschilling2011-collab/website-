--!nolint
-- Vierter Treiber: Rauchtest fuer den Balance-Simulator.
--
-- Geprueft wird NICHT, ob die Zahlen im Zielkorridor liegen -- das ist eine
-- Design-Entscheidung und darf keinen Build rot machen. Geprueft wird, dass
-- der Simulator gegen den aktuellen Stand von Balance.lua ueberhaupt laeuft,
-- jede Strategie ein Ergebnis liefert und nichts davon Unsinn ist.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = Harness.makeFolder("Shared", ReplicatedStorage)
Harness.makeModule("Balance", Shared, "Shared/Balance")

local Dev = Harness.makeFolder("Dev", ServerScriptService)
local BalanceSim = require(Harness.makeModule("BalanceSim", Dev, "Dev/BalanceSim"))

local failures = {}
local function check(ok, message)
	if not ok then
		table.insert(failures, message)
	end
	print(string.format("  [%s] %s", if ok then "ok " else "FAIL", message))
end

print("================ Balance-Simulator ================")
local report = BalanceSim.Run(300, 4711)

check(typeof(report) == "table", "Simulator liefert einen Bericht")
check(#report.results == 32, "32 Strategien gerechnet, waren: " .. #report.results)
check(#Harness.errors == 0, "keine Laufzeitfehler")

local allFinite = true
local anyBanked = false
for _, result in ipairs(report.results) do
	if result.banked ~= result.banked or result.banked < 0 then
		allFinite = false
	end
	if result.heat < 0 or result.heat > 100 then
		allFinite = false
	end
	if result.banked > 0 then
		anyBanked = true
	end
end
check(allFinite, "alle Werte plausibel (Banked >= 0, Heat in 0..100)")
check(anyBanked, "mindestens eine Strategie zahlt ueberhaupt etwas ein")

print("===================================================")
if #failures == 0 then
	print("ERGEBNIS: Simulator laeuft")
else
	print("ERGEBNIS: " .. #failures .. " Pruefung(en) fehlgeschlagen")
	error(#failures .. " Pruefung(en) fehlgeschlagen", 0)
end
