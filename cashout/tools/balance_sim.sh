#!/usr/bin/env bash
# balance_sim.sh -- misst die Erwartungswerte der Stufen aus Balance.lua.
#
# Simuliert eine 600-s-Runde pro Strategie ("immer diese Stufe spielen, ab
# Heat X einzahlen"), inklusive Laufweg zur Bank, Einzahlzeit, Heat-Zerfall,
# Razzia-Wuerfen und Stun. Nicht eingezahlter Cash zaehlt nicht.
#
# Braucht die Standalone-Luau-CLI: https://github.com/luau-lang/luau/releases
# Aufruf:  tools/balance_sim.sh [pfad/zu/luau]
#
# Das Skript liest Balance.lua direkt ein -- es haelt keine eigene Kopie der
# Zahlen. Wer tunt, aendert Balance.lua und laesst das hier neu laufen.

set -euo pipefail

LUAU="${1:-luau}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BALANCE="$ROOT/src/ReplicatedStorage/Shared/Balance.lua"
OUT="$(mktemp -t cashout-sim-XXXXXX.lua)"
trap 'rm -f "$OUT"' EXIT

{
  cat <<'HEAD'
-- Stubs, damit Balance.lua ausserhalb von Roblox laedt.
Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end }
math.randomseed(20260815)
Random = {
	new = function()
		return {
			NextNumber = function(self) return math.random() end,
			NextInteger = function(self, a, b) return math.random(a, b) end,
		}
	end,
}
local Balance = (function()
HEAD
  cat "$BALANCE"
  cat <<'TAIL'
end)()

local DT = 0.25
local WALK = Balance.Player.WalkSpeed
local TRAVEL = math.abs(Balance.Map.BankPosition.X - Balance.Map.TerminalAnchorX) / WALK
local ROUND = Balance.Round.DurationSeconds
local rng = Random.new(20260815)

-- Ein Durchlauf: Spieler macht ununterbrochen Deals einer Stufe und geht zur
-- Bank, sobald Heat >= threshold. Am Rundenende noch eine letzte Einzahlung,
-- wenn die Zeit reicht. Nicht eingezahlter Cash zaehlt nicht.
local function simulate(tier, threshold, ramp)
	ramp = ramp or tier
	local current = tier
	local t, cash, banked, heat = 0, 0, 0, 0
	local nextDecay, nextRaid = Balance.Heat.DecayInterval, Balance.Heat.RaidCheckInterval
	local state, until_ = "idle", 0
	local raids = 0

	while t < ROUND do
		t += DT

		while t >= nextDecay do
			heat = math.max(Balance.Heat.Min, heat - Balance.Heat.DecayAmount)
			nextDecay += Balance.Heat.DecayInterval
		end

		while t >= nextRaid do
			if rng:NextNumber() < Balance.RaidChance(heat) then
				cash = math.floor(cash * Balance.Heat.RaidCashKeptFraction)
				heat = math.max(Balance.Heat.Min, heat - Balance.Heat.RaidHeatLoss)
				raids += 1
				state, until_ = "stun", t + Balance.Heat.RaidStunSeconds
			end
			nextRaid += Balance.Heat.RaidCheckInterval
		end

		if state == "idle" then
			local timeLeft = ROUND - t
			local needed = TRAVEL + Balance.Bank.DepositSeconds
			-- Letzte Fahrt: einzahlen, solange es noch reicht.
			if cash > 0 and (heat >= threshold or timeLeft <= needed + current.Duration) then
				if timeLeft >= needed then
					state, until_ = "toBank", t + TRAVEL
				else
					break
				end
			else
				-- Extrem ist erst ab Heat >= 50 im Angebot: bis dahin die
				-- naechstkleinere Stufe spielen.
				current = if heat >= tier.MinHeatToOffer then tier else ramp
				state, until_ = "deal", t + current.Duration
			end
		elseif t >= until_ then
			if state == "deal" then
				cash += rng:NextInteger(current.MinPayout, current.MaxPayout)
				heat = math.min(Balance.Heat.Max, heat + current.Heat)
				state = "idle"
			elseif state == "toBank" then
				state, until_ = "deposit", t + Balance.Bank.DepositSeconds
			elseif state == "deposit" then
				banked += cash
				cash = 0
				heat = math.max(Balance.Heat.Min, heat - Balance.Bank.HeatRelief)
				state, until_ = "toTerminals", t + TRAVEL
			elseif state == "toTerminals" then
				state = "idle"
			elseif state == "stun" then
				state = "idle"
			end
		end
	end

	return banked, raids
end

local TRIALS = 3000
print(string.format("Rundenlaenge %ds, Weg Terminal<->Bank %.1fs pro Richtung, %d Durchlaeufe\n", ROUND, TRAVEL, TRIALS))
print(string.format("%-8s %-10s %10s %10s %8s", "Stufe", "Bank ab", "Banked oe", "vs Klein", "Razzien"))

local ramps = { Extreme = Balance.Deals.TierById.Large }

local baseline
for _, tier in ipairs(Balance.Deals.Tiers) do
	local bestBanked, bestThreshold, bestRaids = -1, 0, 0
	for threshold = 10, 100, 5 do
		local sum, raidSum = 0, 0
		for _ = 1, TRIALS do
			local b, r = simulate(tier, threshold, ramps[tier.Id])
			sum += b
			raidSum += r
		end
		local avg = sum / TRIALS
		if avg > bestBanked then
			bestBanked, bestThreshold, bestRaids = avg, threshold, raidSum / TRIALS
		end
	end
	baseline = baseline or bestBanked
	print(string.format("%-8s %-10d %10.0f %9.2fx %8.2f", tier.Label, bestThreshold, bestBanked, bestBanked / baseline, bestRaids))
end
TAIL
} > "$OUT"

"$LUAU" "$OUT"
