--!strict
-- Geld wird nur hier verändert. Der Client nennt nie Beträge, die er bekommt –
-- alle Preise kommen aus den Configs auf dem Server.
-- P&L ledger (CORE_SPEC 4, Appendix A): every flow with a category is added to
-- data.empire.ledger[tostring(company day)] = { i = income by category, o = costs by category }.
-- Whole dollars are stored (small JSON); the fractions are carried in memory per category.
-- At most LEDGER_DAYS days and LEDGER_CATEGORIES categories per side and day (overflow -> "other").
-- spend / grant without a category are booked as "other", so the ledger always adds up to the change in
-- cash (applyFlow's default is "market").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CompanyOps = require(ReplicatedStorage.Shared.CompanyOps)
local ServerTypes = require(script.Parent.Parent.Lib.ServerTypes)
local SessionService = require(script.Parent.SessionService)

type Session = ServerTypes.Session

local EconomyService = {}
EconomyService.LEDGER_DAYS = CompanyOps.LEDGER_DAYS
EconomyService.LEDGER_CATEGORIES = CompanyOps.LEDGER_CATEGORIES

local function valid(amount: number): boolean
	return amount == amount and amount >= 0 and amount < math.huge
end

-- fractional remainders per empire table: carry[e]["i:market"] = 0.37
local carry: { [any]: { [string]: number } } = setmetatable({}, { __mode = "k" }) :: any

local function book(session: Session, side: string, category: string, amount: number)
	if amount <= 0 or typeof(category) ~= "string" then
		return
	end
	local e = (session.data :: any).empire
	if typeof(e) ~= "table" then
		return
	end
	local cal = e.calendar
	local day = if typeof(cal) == "table" and typeof(cal.day) == "number" then math.max(1, math.floor(cal.day)) else 1
	local ledger = e.ledger
	if typeof(ledger) ~= "table" then
		ledger = {}
		e.ledger = ledger
	end
	local key = tostring(day)
	local entry = ledger[key]
	if typeof(entry) ~= "table" then
		entry = { i = {}, o = {} }
		ledger[key] = entry
		-- keep the newest LEDGER_DAYS days
		local keys = {}
		for k in ledger do
			local n = tonumber(k)
			if n then table.insert(keys, n) else ledger[k] = nil end
		end
		table.sort(keys, function(a: number, b: number): boolean return a > b end)
		for i = EconomyService.LEDGER_DAYS + 1, #keys do
			ledger[tostring(keys[i])] = nil
		end
	end
	local map = entry[side]
	if typeof(map) ~= "table" then
		map = {}
		entry[side] = map
	end
	local cat = string.sub(category, 1, 16)
	if map[cat] == nil and cat ~= "other" then
		-- at most LEDGER_CATEGORIES lines per side and day, "other" included
		local n = 0
		for key in map do
			if key ~= "other" then
				n += 1
			end
		end
		if n >= EconomyService.LEDGER_CATEGORIES - 1 then
			cat = "other"
		end
	end
	local c = carry[e]
	if not c then
		c = {}
		carry[e] = c
	end
	local slot = side .. ":" .. cat
	local total = (c[slot] or 0) + amount
	local whole = math.floor(total)
	c[slot] = total - whole
	if whole > 0 or map[cat] == nil then
		map[cat] = (map[cat] or 0) + whole
	end
end
EconomyService.book = book

-- Zieht `amount` ab, wenn genug da ist. Ein negatives Konto blockiert alle Ausgaben > 0.
-- category (optional, default "other"): the cost line of the P&L ledger.
function EconomyService.spend(session: Session, amount: number, category: string?): boolean
	if not valid(amount) then
		return false
	end
	if amount == 0 then
		return true -- kostenlose Aktionen (z. B. Release ohne Marketing) gehen auch mit Schulden
	end
	if session.data.money < amount then
		return false
	end
	session.data.money -= amount
	session.data.stats.totalCost += amount
	book(session, "o", category or "other", amount)
	SessionService.markDirty(session)
	return true
end

-- category (optional, default "other"): the income line of the P&L ledger.
function EconomyService.grant(session: Session, amount: number, category: string?)
	if not valid(amount) then
		return
	end
	session.data.money += amount
	book(session, "i", category or "other", amount)
	SessionService.markDirty(session)
end

-- Laufende Einnahmen/Kosten (pro Tick). Darf ins Minus gehen. category (optional, default "market"):
-- the ledger line of CORE_SPEC 4 (market, b2b, pilot, studio, guest, wages, ops, upkeep, food, fleet,
-- trips, b2bserve, jet, ...). Revenue counts toward totalRevenue (pilot fees included).
function EconomyService.applyFlow(session: Session, revenue: number, cost: number, category: string?)
	if not valid(revenue) or not valid(cost) then
		return
	end
	session.data.money += revenue - cost
	session.data.stats.totalRevenue += revenue
	session.data.stats.totalCost += cost
	local cat = category or "market"
	if revenue > 0 then
		book(session, "i", cat, revenue)
	end
	if cost > 0 then
		book(session, "o", cat, cost)
	end
end

return EconomyService
