--[[
	BalanceSim.lua  (Dokument 6)

	Rechnet Strategien gegen Balance.lua durch, ohne dass jemand mitspielen
	muss. Laeuft auf Knopfdruck, nicht von allein:

	    require(game.ServerScriptService.Dev.BalanceSim).Run()

	Optional mit weniger Runden zum schnellen Ausprobieren:

	    require(game.ServerScriptService.Dev.BalanceSim).Run(500)

	Das Modul haelt KEINE eigenen Spielzahlen. Payouts, Heat, Entfernungen,
	Razzia-Formel und Kartengeometrie kommen alle aus Balance.lua -- wer dort
	tunt, sieht das Ergebnis hier sofort.

	Was das Modell NICHT kann, damit niemand die Zahlen fuer mehr haelt als sie
	sind: ein Spieler allein, keine Mitspieler, kein Abfangen, keine Wege um
	Hindernisse, und die Fluchtquote ist eine gesetzte Konstante statt echten
	Koennens.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Balance"))
local DealCatalog = require(Shared:WaitForChild("DealCatalog"))

local BalanceSim = {}

-- ------------------------------------------------------------- Annahmen --
-- Alles, was das Dokument nicht festlegt und das Modell trotzdem braucht.
-- Bewusst hier oben und nicht in Balance.lua: das sind Annahmen ueber
-- Spielerverhalten, keine Spielregeln.

-- Dokument 6: "Annahme: 50 % Fluchtquote, als Konstante oben im Skript".
local ESCAPE_RATE = 0.5

-- Zeitverlust einer Razzia zusaetzlich zum Fluchtfenster selbst. Wer entkommt,
-- rennt in Richtung seines Ziels weiter und verliert nichts; wer erwischt wird,
-- steht den Stun ab.
local ESCAPED_TIME_COST = 0
local CAUGHT_TIME_COST = Balance.Heat.RaidStunSeconds

-- Bearing-Stuetzstellen fuer den Erwartungswert der Strecke Uebergabepunkt -> Bank.
local BEARING_SAMPLES = 72

local DEFAULT_ROUNDS = 5000

local DEPOSIT_THRESHOLDS = { 400, 800, 1500, 3000 }

-- Dokument 6: "optionalem 'ab Heat 70 nur noch Klein'".
local PANIC_HEAT = 70

-- ------------------------------------------------------------- Geometrie --

local TIER_INDEX = {}
for index, tier in ipairs(Balance.Orders.Tiers) do
	TIER_INDEX[tier.Id] = index
end

--[[
	Terminal-Rang, an dem eine Stufe am haeufigsten im Angebot ist. Ein Spieler,
	der immer "Gross" will, geht an das Terminal, das Gross am staerksten fuehrt.
]]
local function bestRankFor(tierId: string): number
	local bestRank, bestWeight = 1, -1
	for rank, profile in ipairs(Balance.Orders.TerminalProfiles) do
		local weight = profile[tierId] or 0
		if weight > bestWeight then
			bestRank, bestWeight = rank, weight
		end
	end
	return bestRank
end

--[[
	Erwartete Strecke vom Uebergabepunkt zur Bank. Der Punkt liegt D Studs vom
	Terminal entfernt in zufaelliger Richtung, das Terminal R Studs von der
	Bank -- gemittelt ueber den Winkel.
]]
local function expectedPointToBank(radius: number, distance: number): number
	local total = 0
	for index = 0, BEARING_SAMPLES - 1 do
		local angle = (index / BEARING_SAMPLES) * 2 * math.pi
		local dx = radius - distance * math.cos(angle)
		local dz = distance * math.sin(angle)
		total += math.sqrt(dx * dx + dz * dz)
	end
	return total / BEARING_SAMPLES
end

-- -------------------------------------------------------------- Angebote --

--[[
	Dieselbe gewichtete Ziehung ohne Zuruecklegen wie in OrderService: drei
	Karten aus dem Profil des Terminals, Extrem erst ab Heat 50.
]]
local function drawOffers(rng, rank: number, heat: number)
	local profile = Balance.Orders.TerminalProfiles[rank]
	local pool = {}
	-- Ein Eintrag pro KARTE, nicht pro Stufe -- genau wie eligibleCards im
	-- OrderService. Der Unterschied ist nicht kosmetisch: gezogen wird ohne
	-- Zuruecklegen. Mit einem Eintrag pro Stufe kaemen immer drei
	-- VERSCHIEDENE Stufen heraus, waehrend der Server aus 16 Karten zieht und
	-- dieselbe Stufe mehrfach anbieten kann -- oder die gesuchte gar nicht.
	for _, card in ipairs(DealCatalog.Cards) do
		local tier = Balance.Orders.TierById[card.Tier]
		local weight = profile[card.Tier] or 0
		if tier and weight > 0 and heat >= tier.MinHeatToOffer then
			table.insert(pool, tier)
		end
	end

	local drawn = {}
	local remaining = table.clone(pool)
	for _ = 1, math.min(Balance.Orders.OffersPerTerminal, #pool) do
		local total = 0
		for _, tier in ipairs(remaining) do
			total += profile[tier.Id]
		end
		local roll = rng:NextNumber() * total
		local pickedIndex = #remaining
		for index, tier in ipairs(remaining) do
			roll -= profile[tier.Id]
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
	targetIndex = nil bedeutet "die hoechste verfuegbare Stufe nehmen".
	Sonst die angepeilte Stufe, und wenn sie nicht dabei ist, die naechst
	niedrigere -- und wenn es die auch nicht gibt, die niedrigste im Angebot.
]]
local function pickOffer(offers, targetIndex: number?)
	local best = nil
	for _, tier in ipairs(offers) do
		local index = TIER_INDEX[tier.Id]
		if targetIndex == nil then
			if not best or index > TIER_INDEX[best.Id] then
				best = tier
			end
		elseif index <= targetIndex then
			if not best or index > TIER_INDEX[best.Id] then
				best = tier
			end
		end
	end
	if best then
		return best
	end
	-- Nichts auf oder unter dem Ziel: die niedrigste Karte nehmen.
	local lowest = offers[1]
	for _, tier in ipairs(offers) do
		if TIER_INDEX[tier.Id] < TIER_INDEX[lowest.Id] then
			lowest = tier
		end
	end
	return lowest
end

-- ------------------------------------------------------------- Simulation --

local function newSim(rng)
	return {
		rng = rng,
		t = 0,
		cash = 0,
		banked = 0,
		heat = 0,
		nextRaid = Balance.Heat.RaidCheckInterval,
		nextDecay = Balance.Heat.DecayInterval,
		raids = 0,
		escapes = 0,
		deposits = 0,
		heatSum = 0,
		heatSamples = 0,
	}
end

local function payoutMultiplier(sim): number
	local remaining = Balance.Round.DurationSeconds - sim.t
	return if remaining <= Balance.Round.FinalRushSeconds then Balance.Round.FinalRushMultiplier else 1
end

--[[
	Laesst die Uhr um seconds weiterlaufen und arbeitet dabei Zerfallstakte und
	Razzia-Checks ab. carrying = laeuft gerade ein Auftrag (dann kein Zerfall).
]]
local function advance(sim, seconds: number, carrying: boolean)
	local remaining = seconds

	while remaining > 1e-9 do
		local step = math.min(remaining, sim.nextRaid - sim.t, sim.nextDecay - sim.t)
		if step < 0 then
			step = 0
		end
		sim.t += step
		remaining -= step

		if sim.t >= sim.nextRaid - 1e-9 then
			sim.nextRaid += Balance.Heat.RaidCheckInterval
			sim.heatSum += sim.heat
			sim.heatSamples += 1

			if sim.rng:NextNumber() < Balance.RaidChance(sim.heat) then
				sim.raids += 1
				if sim.rng:NextNumber() < ESCAPE_RATE then
					sim.escapes += 1
					sim.heat = math.max(Balance.Heat.Min, sim.heat - Balance.Heat.RaidHeatLossEscaped)
					remaining += ESCAPED_TIME_COST
				else
					sim.cash = math.floor(sim.cash * Balance.Heat.RaidCashKeptFraction)
					sim.heat = math.max(Balance.Heat.Min, sim.heat - Balance.Heat.RaidHeatLossCaught)
					remaining += CAUGHT_TIME_COST
				end
			end
		end

		if sim.t >= sim.nextDecay - 1e-9 then
			sim.nextDecay += Balance.Heat.DecayInterval
			if not carrying and sim.heat > Balance.Heat.Min then
				sim.heat = math.max(Balance.Heat.Min, sim.heat - Balance.Heat.DecayAmount)
			end
		end

		if sim.t >= Balance.Round.DurationSeconds then
			return
		end
	end
end

--[[
	Eine Runde mit einer Strategie. Rueckgabe: banked, Ø heat, raids, escapes.
]]
local function simulateRound(rng, strategy)
	local sim = newSim(rng)
	local rank = strategy.rank
	local radius = Balance.Map.TerminalRadii[rank]
	local walk = Balance.Player.WalkSpeed

	-- Start an der Bank (Spawn liegt dort).
	local atBank = true

	while sim.t < Balance.Round.DurationSeconds do
		local timeLeft = Balance.Round.DurationSeconds - sim.t

		-- Reicht die Zeit ueberhaupt noch fuer einen Auftrag samt Einzahlung?
		local minimalCycle = radius / walk
			+ Balance.Orders.AcceptSeconds
			+ Balance.Orders.Tiers[1].MinDistance / walk
			+ Balance.Orders.DeliverSeconds

		local mustBankNow = sim.cash > 0
			and timeLeft <= (if atBank then 0 else radius / walk) + Balance.Bank.DepositSeconds + 1

		if mustBankNow or (sim.cash >= strategy.threshold and timeLeft > Balance.Bank.DepositSeconds) then
			if not atBank then
				advance(sim, strategy.pointToBank / walk, false)
				atBank = true
			end
			if sim.t >= Balance.Round.DurationSeconds then
				break
			end
			advance(sim, Balance.Bank.DepositSeconds, false)
			if sim.t < Balance.Round.DurationSeconds then
				sim.banked += sim.cash
				sim.cash = 0
				sim.deposits += 1
				sim.heat = math.max(Balance.Heat.Min, sim.heat - Balance.Bank.HeatRelief)
			end
		elseif timeLeft <= minimalCycle then
			break
		else
			-- Zum Terminal.
			advance(sim, (if atBank then radius else strategy.pointToTerminal) / walk, false)
			atBank = false
			if sim.t >= Balance.Round.DurationSeconds then
				break
			end

			advance(sim, Balance.Orders.AcceptSeconds, false)
			if sim.t >= Balance.Round.DurationSeconds then
				break
			end

			local targetIndex = strategy.targetIndex
			if strategy.panic and sim.heat >= PANIC_HEAT then
				targetIndex = TIER_INDEX.Small
			end

			local offers = drawOffers(rng, rank, sim.heat)
			if #offers == 0 then
				break
			end
			local tier = pickOffer(offers, targetIndex)

			local basePayout = rng:NextInteger(tier.MinPayout, tier.MaxPayout)
			local distance = rng:NextNumber(tier.MinDistance, tier.MaxDistance)

			-- Ab jetzt getragen: kein Zerfall bis zur Uebergabe.
			advance(sim, distance / walk, true)
			if sim.t >= Balance.Round.DurationSeconds then
				break
			end
			advance(sim, Balance.Orders.DeliverSeconds, true)
			if sim.t >= Balance.Round.DurationSeconds then
				break
			end

			local payout = math.floor(basePayout * Balance.RiskPremium(sim.heat) * payoutMultiplier(sim) + 0.5)
			sim.cash += payout
			sim.heat = math.min(Balance.Heat.Max, sim.heat + tier.Heat)
		end
	end

	local averageHeat = if sim.heatSamples > 0 then sim.heatSum / sim.heatSamples else 0
	return sim.banked, averageHeat, sim.raids, sim.escapes, sim.deposits
end

-- ------------------------------------------------------------ Strategien --

local function buildStrategies()
	local list = {}

	local targets = {
		{ label = "immer Klein", tierId = "Small", targetIndex = TIER_INDEX.Small },
		{ label = "immer Mittel", tierId = "Medium", targetIndex = TIER_INDEX.Medium },
		{ label = "immer Gross", tierId = "Large", targetIndex = TIER_INDEX.Large },
		{ label = "hoechste verfuegbare", tierId = "Extreme", targetIndex = nil },
	}

	for _, target in ipairs(targets) do
		local rank = bestRankFor(target.tierId)
		local radius = Balance.Map.TerminalRadii[rank]
		-- Mittlere Entfernung der angepeilten Stufe fuer die Rueckwege.
		local tier = Balance.Orders.TierById[target.tierId]
		local meanDistance = (tier.MinDistance + tier.MaxDistance) / 2

		for _, threshold in ipairs(DEPOSIT_THRESHOLDS) do
			for _, panic in ipairs({ false, true }) do
				table.insert(list, {
					label = string.format(
						"%s, Bank ab %d%s",
						target.label,
						threshold,
						if panic then ", ab Heat 70 Klein" else ""
					),
					rank = rank,
					targetIndex = target.targetIndex,
					threshold = threshold,
					panic = panic,
					pointToTerminal = meanDistance,
					pointToBank = expectedPointToBank(radius, meanDistance),
				})
			end
		end
	end

	return list
end

-- ---------------------------------------------------------------- Ausgabe --

local function formatRow(result)
	return string.format(
		"%-46s %9.0f %7.1f %8.2f %10s %6.1f %s",
		result.label,
		result.banked,
		result.heat,
		result.raids,
		if result.raids > 0 then string.format("%.0f %%", result.escapeShare * 100) else "-",
		result.deposits,
		if result.sensible then "" else "  (Schwelle unerreichbar)"
	)
end

--[[
	Zielkorridor aus Dokument 6.
]]
local function checkCorridor(results)
	local lines = {}
	local ok = true

	local best = results[1].banked
	local third = results[math.min(3, #results)].banked
	local spread = if best > 0 then (best - third) / best else 0
	local spreadOk = spread <= 0.15
	ok = ok and spreadOk
	table.insert(
		lines,
		string.format(
			"  [%s] die drei besten Strategien liegen innerhalb von 15 %%: %.1f %%",
			if spreadOk then "ok " else "NEIN",
			spread * 100
		)
	)

	local heatSum = 0
	local topCount = math.min(3, #results)
	for index = 1, topCount do
		heatSum += results[index].heat
	end
	local topHeat = heatSum / topCount
	local heatOk = topHeat >= 40 and topHeat <= 70
	ok = ok and heatOk
	table.insert(
		lines,
		string.format(
			"  [%s] Ø Heat der Spitzenstrategien zwischen 40 und 70: %.1f",
			if heatOk then "ok " else "NEIN",
			topHeat
		)
	)

	-- Untergrenze ist die schlechteste Strategie, deren Einzahlschwelle
	-- ueberhaupt erreichbar war.
	local worst, worstLabel = nil, "-"
	for _, result in ipairs(results) do
		if result.sensible and (not worst or result.banked < worst) then
			worst, worstLabel = result.banked, result.label
		end
	end
	worst = worst or results[#results].banked
	local ratio = if worst > 0 then best / worst else math.huge
	local ratioOk = ratio <= 8
	ok = ok and ratioOk
	table.insert(
		lines,
		string.format(
			"  [%s] beste hoechstens 8x die schlechteste sinnvolle: %.2fx  (Untergrenze: %s)",
			if ratioOk then "ok " else "NEIN",
			ratio,
			worstLabel
		)
	)

	return ok, lines
end

-- ------------------------------------------------------------------- Run --

--[[
	rounds: Runden je Strategie, Vorgabe 5000.
	seed:   fuer reproduzierbare Laeufe.
]]
function BalanceSim.Run(rounds: number?, seed: number?)
	local roundCount = rounds or DEFAULT_ROUNDS
	local rng = Random.new(seed or 20260815)
	local strategies = buildStrategies()

	print("================ CASHOUT Balance-Simulator ================")
	print(
		string.format(
			"%d Strategien x %d Runden a %d s. Fluchtquote als Annahme: %d %%.",
			#strategies,
			roundCount,
			Balance.Round.DurationSeconds,
			ESCAPE_RATE * 100
		)
	)
	print("")
	print(
		string.format(
			"%-46s %9s %7s %8s %10s %6s",
			"Strategie",
			"Ø Banked",
			"Ø Heat",
			"Razzien",
			"geflohen",
			"Einz."
		)
	)

	local results = {}
	for _, strategy in ipairs(strategies) do
		local bankedSum, heatSum, raidSum, escapeSum, depositSum = 0, 0, 0, 0, 0
		for _ = 1, roundCount do
			local banked, heat, raids, escapes, deposits = simulateRound(rng, strategy)
			bankedSum += banked
			heatSum += heat
			raidSum += raids
			escapeSum += escapes
			depositSum += deposits
		end

		local deposits = depositSum / roundCount
		table.insert(results, {
			label = strategy.label,
			banked = bankedSum / roundCount,
			heat = heatSum / roundCount,
			raids = raidSum / roundCount,
			deposits = deposits,
			escapeShare = if raidSum > 0 then escapeSum / raidSum else 0,
			-- "Sinnvoll" heisst: die Einzahlschwelle war ueberhaupt erreichbar.
			-- Wer mit Klein-Auftraegen auf 3000 wartet, zahlt nur die eine
			-- Pflichteinzahlung am Rundenende ein -- das ist keine Strategie,
			-- sondern ein Konfigurationsfehler, und taugt nicht als Untergrenze
			-- fuer den 8x-Vergleich.
			sensible = deposits >= 2,
		})
	end

	table.sort(results, function(a, b)
		return a.banked > b.banked
	end)

	for _, result in ipairs(results) do
		print(formatRow(result))
	end

	print("")
	print("Zielkorridor:")
	local ok, lines = checkCorridor(results)
	for _, line in ipairs(lines) do
		print(line)
	end

	print("")
	if ok then
		print("ERGEBNIS: im Korridor.")
	else
		print("ERGEBNIS: ausserhalb des Korridors. Balance.lua bleibt unveraendert --")
		print("die Zahlen oben sind die Grundlage fuer eine Entscheidung, kein Auftrag.")
	end
	print("==========================================================")

	return {
		results = results,
		inCorridor = ok,
	}
end

return BalanceSim
