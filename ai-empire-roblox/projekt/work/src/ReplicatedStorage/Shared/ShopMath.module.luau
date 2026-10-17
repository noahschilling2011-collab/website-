--!strict
-- Shop rules shared by the server (ShopService, EmpireService, AIModelService) and the client (Shop pages, the Lab's
-- Eureka buttons, the Studio's lock strip, the training view). Pure: no Roblox services, no yields (SHOP_SPEC 4, 5.2,
-- 5.3, shop package). Times: `now` = os.time-like seconds (the server's os.time, the client's snapshot.serverTime)
-- for UTC days; boost time = company play time data.empire.seconds; `clock` = os.clock-like seconds for the UI's
-- "never right after an error" rule.
--   * caps: daily counters (data.shop.daily), boosts (data.shop.boosts, end times in play seconds), buy guards (4.1)
--   * Eureka: eurekaCheck mirrors EmpireService.eureka (3.1); eurekaSaving / savingText = the honest "Saves" line (5.3)
--   * offers: offerState is the gate of every Robux button outside the Shop page (5.2.1); studioEurekaOffer (5.2.4)
--   * cash packs: one of each size per office (S1, the server keeps extra receipts as credits: packCredit), cashText

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local ShopConfig = require(Shared.Config.ShopConfig)
local EmpireConfig = require(Shared.Config.EmpireConfig)
local ModelConfig = require(Shared.Config.ModelConfig)
local EmpireMath = require(Shared.EmpireMath)
local Ops = require(Shared.CompanyOps)
local Format = require(Shared.Format)
local TutorialMath = require(Shared.TutorialMath)

local ShopMath = {}

export type Check = {
	ok: boolean,
	err: string?,
	kind: string?, -- "running" | "idle" | "lab"
	id: string?, -- research id ("lab" for a Lab level)
	name: string?,
	cost: number, -- $ still to pay (0 for a running project: paid at its start)
	points: number, -- research points the Eureka covers (or gives back for a running project)
	have: number, -- research points in stock
	timer: number, -- seconds of the job's timer the Eureka skips
	seconds: number, -- the saving: timer + the wait for missing research points at the peak office-hours speed
	level: number?, -- Lab level now (lab target)
}
export type OfferUi = {
	live: any?, -- snapshot.live (live.shop.available)
	priced: boolean?, -- the product's price came from Roblox and IsForSale is true
	studio: boolean?, -- RunService:IsStudio(): the owner preview ("Not set up", never prompts)
	clock: number?, -- os.clock() now
	lastErrorAt: number?, -- os.clock() of the last failed action (ActionController.lastFailure)
	now: number?, -- server time (os.time domain) for the daily counters
}

local function finite(v: any): boolean
	return typeof(v) == "number" and v == v and v > -math.huge and v < math.huge
end
local function num(v: any, default: number): number
	return if finite(v) then v else default
end
local function dollars(n: number): string
	return "$" .. Format.int(n)
end

local function shopOf(data: any): any
	local shop = if typeof(data) == "table" then data.shop else nil
	return if typeof(shop) == "table" then shop else nil
end

-- peak of the research-point time sheet: max over one game day of Ops.timesheet / Ops.TS_MEAN (about 1.70)
local peak = 0
for s = 0, Ops.DAY - 1 do
	peak = math.max(peak, Ops.timesheet(Ops.hour(s + 0.5)))
end
ShopMath.DUTY_PEAK = peak / Ops.TS_MEAN

---------------------------------------------------------------------------------------------- caps

function ShopMath.utcDay(now: number): number
	return math.floor(num(now, 0) / 86400)
end

function ShopMath.vouchers(data: any, key: string): number
	local shop = shopOf(data)
	local n = if shop and typeof(shop.vouchers) == "table" then shop.vouchers[key] else nil
	return if finite(n) and n > 0 then math.floor(n) else 0
end

-- redeems of `key` on the UTC day of `now` (the counter rolls over at 00:00 UTC)
function ShopMath.dailyUsed(data: any, key: string, now: number): number
	local shop = shopOf(data)
	local daily = if shop then shop.daily else nil
	if typeof(daily) ~= "table" or daily.day ~= ShopMath.utcDay(now) or typeof(daily.used) ~= "table" then
		return 0
	end
	local n = daily.used[key]
	return if finite(n) and n > 0 then math.floor(n) else 0
end

-- play seconds left on a boost (`seconds` = empire.seconds now; the client passes its extrapolated value)
function ShopMath.boostLeft(data: any, key: string, seconds: number?): number
	local shop = shopOf(data)
	local boosts = if shop then shop.boosts else nil
	local untilPlay = if typeof(boosts) == "table" and finite(boosts[key]) then boosts[key] else 0
	local e = if typeof(data) == "table" then data.empire else nil
	local now = seconds or (if typeof(e) == "table" then num(e.seconds, 0) else 0)
	return math.max(0, untilPlay - now)
end

function ShopMath.trainingFactor(data: any, seconds: number?): number
	return if ShopMath.boostLeft(data, "overclock", seconds) > 0 then ShopConfig.BOOSTS.overclock.training or 1 else 1
end

-- the training rate with Overclock: x1.5, never faster than the 12 s floor per run (EmpireMath.trainingRate's own cap)
function ShopMath.boostRate(data: any, workTotal: number, rate: number, seconds: number?): number
	local f = ShopMath.trainingFactor(data, seconds)
	if f == 1 then
		return rate
	end
	return math.min(rate * f, workTotal / ModelConfig.TRAINING.minSeconds)
end

-- the running training already trains at the 12 s minimum: Overclock would not speed it up
function ShopMath.atTrainingMinimum(data: any): boolean
	local training = if typeof(data) == "table" then data.training else nil
	if typeof(training) ~= "table" or not finite(training.workTotal) or training.workTotal <= 0 then
		return false
	end
	local rate = EmpireMath.trainingRate(data.gpus, training.workTotal, data.empire)
	return rate >= training.workTotal / ModelConfig.TRAINING.minSeconds - 1e-9
end

-- Keynote Boost: +0.20 on the own market revenue multiplier (added to Investor's 1.10, never multiplied: S6)
function ShopMath.revenueBonus(data: any, seconds: number?): number
	return if ShopMath.boostLeft(data, "keynote", seconds) > 0 then ShopConfig.BOOSTS.keynote.revenue or 0 else 0
end

function ShopMath.liveModel(data: any): boolean
	if typeof(data) ~= "table" or typeof(data.models) ~= "table" then
		return false
	end
	for _, m in data.models do
		if typeof(m) == "table" and m.status == "live" then
			return true
		end
	end
	return false
end

-- may a boost start now? (the server's startBoost order; the daily cap is checked by ShopService.redeem)
function ShopMath.boostCheck(data: any, key: string, now: number, seconds: number?): (boolean, string?)
	local def = ShopConfig.BOOSTS[key]
	if not def then
		return false, "BAD_INPUT"
	end
	if typeof(data) ~= "table" or not data.company then
		return false, "NO_COMPANY"
	end
	if key == "keynote" and not ShopMath.liveModel(data) then
		return false, "NO_LIVE_MODEL"
	end
	if ShopMath.boostLeft(data, key, seconds) + def.seconds > ShopConfig.BOOST_MAX_LEFT then
		return false, "BOOST_FULL"
	end
	local cap = ShopConfig.DAILY[key]
	if cap and ShopMath.dailyUsed(data, key, now) >= cap then
		return false, "DAILY_LIMIT"
	end
	return true, nil
end

---------------------------------------------------------------------------------------------- Eureka

-- research steps left in the save: projects not done (a running one counts) + Lab levels below 10
function ShopMath.eurekaUsesLeft(data: any): number
	local e = data.empire
	local n = 0
	for _, def in EmpireConfig.RESEARCH do
		if not (typeof(e.research) == "table" and e.research[def.id]) then
			n += 1
		end
	end
	return n + math.max(0, Ops.LAB_MAX - math.floor(num(e.labLevel, 0)))
end

-- research points per second at the peak of office hours (the "Saves" line never shows more than the real saving)
function ShopMath.peakRate(data: any, now: number?): number
	local e = data.empire
	local company = data.company
	local b = EmpireMath.bonuses(e)
	local rate = b.points * (if company and company.spec == "research" then 1.2 else 1) * ShopMath.DUTY_PEAK
	local access = e.subscriptions
	if typeof(access) == "table" and finite(access.expires) and access.expires > num(now, os.time()) then
		rate += math.min(3, num(access.score, 0) / 100)
	end
	return math.max(1e-6, rate)
end

local function treeDone(e: any): boolean
	for _, def in EmpireConfig.RESEARCH do
		if not (typeof(e.research) == "table" and e.research[def.id]) then
			return false
		end
	end
	return true
end

local function fail(err: string): Check
	return { ok = false, err = err, cost = 0, points = 0, have = 0, timer = 0, seconds = 0 }
end

-- What a Eureka on `target` ("lab", a research id, or nil for the running project) would do now, in the order of
-- EmpireService.eureka. forBuy = the Robux (buy) state: the saving must be >= EUREKA_MIN_SAVING and a Lab level
-- needs research points short of its price (with enough RP a Lab level has no wait). An owned Eureka has no minimum.
function ShopMath.eurekaCheck(data: any, target: string?, money: number, forBuy: boolean?, now: number?): Check
	if typeof(data) ~= "table" or not data.company then
		return fail("NO_COMPANY")
	end
	local e = data.empire
	local have = num(e.points, 0)
	local out: Check
	if target == "lab" then
		local level = math.floor(num(e.labLevel, 0))
		if level >= Ops.LAB_MAX then
			return fail("MAX_LEVEL")
		end
		if not treeDone(e) then
			return fail("PREREQUISITE")
		end
		local pts, cash = Ops.labCost(level)
		if money < cash then
			return fail("NO_MONEY")
		end
		out = { ok = true, kind = "lab", id = "lab", name = `Lab level {level + 1}`, cost = cash, points = pts, have = have, timer = 0,
			seconds = math.max(0, pts - have) / ShopMath.peakRate(data, now), level = level }
		if forBuy and have >= pts then
			return fail("NOT_SHORT")
		end
	else
		local job = e.researchJob
		if typeof(job) == "table" then
			if target ~= nil and target ~= job.id then
				return fail("RESEARCH_ACTIVE")
			end
			local def = EmpireConfig.find(EmpireConfig.RESEARCH, job.id)
			local left = math.max(0, num(job.seconds, 0) - num(job.elapsed, 0))
			out = { ok = true, kind = "running", id = job.id, name = if def then def.name else tostring(job.id), cost = 0,
				points = if def then def.points else 0, have = have, timer = left, seconds = left }
		else
			local def = EmpireConfig.find(EmpireConfig.RESEARCH, target)
			if not def then
				return fail("BAD_INPUT")
			end
			if typeof(e.research) == "table" and e.research[def.id] then
				return fail("ALREADY_DONE")
			end
			if def.prereq and not (typeof(e.research) == "table" and e.research[def.prereq]) then
				return fail("PREREQUISITE")
			end
			if money < def.cost then
				return fail("NO_MONEY")
			end
			out = { ok = true, kind = "idle", id = def.id, name = def.name, cost = def.cost, points = def.points, have = have, timer = def.seconds,
				seconds = def.seconds + math.max(0, def.points - have) / ShopMath.peakRate(data, now) }
		end
	end
	if forBuy and out.seconds < ShopConfig.EUREKA_MIN_SAVING then
		return fail("TOO_SMALL")
	end
	return out
end

function ShopMath.eurekaSaving(data: any, target: string?, now: number?): number
	local check = ShopMath.eurekaCheck(data, target, math.huge, false, now)
	return if check.ok then check.seconds else 0
end

-- rounded DOWN, never more than the real saving: whole minutes from 60 s ("about 3 min"), tens of seconds from 30 s
-- ("about 40 s"), whole seconds below ("12 s")
function ShopMath.savingText(seconds: number): string
	local s = math.max(0, num(seconds, 0))
	if s >= 60 then
		return `about {math.floor(s / 60)} min`
	elseif s >= 30 then
		return `about {math.floor(s / 10) * 10} s`
	end
	return `{math.floor(s)} s`
end

-- a copy of data with research `id` done (the snapshot itself is never changed: three table levels are cloned)
function ShopMath.withResearch(data: any, id: string): any
	local out = table.clone(data)
	out.empire = table.clone(data.empire)
	out.empire.research = table.clone(data.empire.research or {})
	out.empire.research[id] = true
	return out
end

---------------------------------------------------------------------------------------------- Last Epoch

-- may Last Epoch finish the running training now? `eta` = seconds left (with Overclock); forBuy needs >= 20 s
function ShopMath.lastEpochCheck(data: any, eta: number, forBuy: boolean?, now: number): (boolean, string?)
	local training = if typeof(data) == "table" then data.training else nil
	if typeof(training) ~= "table" then
		return false, "NO_TRAINING"
	end
	local event = training.event
	if typeof(event) == "table" and event.pending then
		return false, "DECIDE_FIRST"
	end
	if ShopMath.dailyUsed(data, "lastEpoch", now) >= (ShopConfig.DAILY.lastEpoch or math.huge) then
		return false, "DAILY_LIMIT"
	end
	if forBuy and num(eta, 0) < ShopConfig.LAST_EPOCH_MIN_LEFT then
		return false, "TOO_SMALL"
	end
	return true, nil
end

---------------------------------------------------------------------------------------------- cash packs

function ShopMath.office(data: any): number
	local e = if typeof(data) == "table" then data.empire else nil
	return math.clamp(math.floor(num(if typeof(e) == "table" then e.office else nil, 1)), 1, #EmpireConfig.OFFICES)
end

-- S1: each pack size once per office. false while data.shop.packs[key] is the current office.
function ShopMath.packOpen(data: any, key: string): boolean
	local shop = shopOf(data)
	local packs = if shop then shop.packs else nil
	return not (typeof(packs) == "table" and packs[key] == ShopMath.office(data))
end

-- S1 credits (fix round 1): packs of `key` bought again in an office that already had one; ShopService pays one per
-- size at the next office move (payPackCredits)
function ShopMath.packCredit(data: any, key: string): number
	local shop = shopOf(data)
	local credit = if shop then shop.packCredit else nil
	local n = if typeof(credit) == "table" then credit[key] else nil
	return if finite(n) and n > 0 then math.floor(n) else 0
end

local SHARE_WORDS: { [string]: string } = {
	["0.1"] = "10 % of", ["0.2"] = "20 % of", ["0.25"] = "a quarter of", ["0.3"] = "30 % of", ["0.5"] = "half of",
	["0.75"] = "three quarters of", ["1"] = "the full", ["2"] = "twice",
}
function ShopMath.shareWords(share: number): string
	local key = string.format("%g", math.floor(num(share, 0) * 100 + 0.5) / 100)
	return SHARE_WORDS[key] or `{math.floor(num(share, 0) * 100 + 0.5)} % of`
end

-- "+$2,700 company cash now: 10 % of the Founder Headquarters price. One per office."
function ShopMath.cashText(def: ShopConfig.Product, office: number): string
	local amount = ShopConfig.cashFor(def, office)
	local nextOffice = EmpireConfig.OFFICES[office + 1]
	local text: string
	-- gsub replacements are literal here ("10 % of" contains a % sign)
	local function lit(value: string): string
		return (string.gsub(value, "%%", "%%%%"))
	end
	if nextOffice then
		text = string.gsub(def.desc, "{amount}", lit(dollars(amount)))
		text = string.gsub(text, "{share}", lit(ShopMath.shareWords(def.share or 0)))
		text = string.gsub(text, "{office}", lit(nextOffice.name))
	else
		text = `+{dollars(amount)} company cash (based on the {EmpireConfig.OFFICES[#EmpireConfig.OFFICES].name} price). One per office.`
	end
	if def.key == "seriesB" and office == 1 then
		text ..= " Leaving the garage still needs your first client."
	end
	return text
end

---------------------------------------------------------------------------------------------- passes, guards

-- owns pass `key` with a passes map {[key] = true} (live.shop.passes): its own flag or a bundle that includes it
function ShopMath.ownsPass(passes: any, key: string): boolean
	if typeof(passes) ~= "table" then
		return false
	end
	if passes[key] == true then
		return true
	end
	for _, bundle in ShopConfig.bundlesOf(key) do
		if passes[bundle.key] == true then
			return true
		end
	end
	return false
end

local function livePasses(live: any): any
	local shop = if typeof(live) == "table" then live.shop else nil
	return if typeof(shop) == "table" then shop.passes else nil
end

-- SHOP_SPEC 4.1 buy guards (client): never sell more than can be used
function ShopMath.buyAllowed(data: any, live: any, key: string, now: number): boolean
	local held = ShopMath.vouchers(data, key)
	if key == "eureka" then
		return held < ShopMath.eurekaUsesLeft(data)
	elseif key == "lastEpoch" then
		local cap = ShopConfig.DAILY.lastEpoch
		return held < cap and not (ShopMath.dailyUsed(data, key, now) >= cap and held >= 1)
	elseif key == "keynote" or key == "overclock" then
		local cap = ShopConfig.DAILY[key]
		return held < cap and not (ShopMath.dailyUsed(data, key, now) >= cap and held >= 1)
	end
	local product = ShopConfig.product(key)
	if product and product.kind == "cash" then
		return ShopMath.packOpen(data, key)
	end
	local pass = ShopConfig.pass(key)
	if pass then
		local passes = livePasses(live)
		if ShopMath.ownsPass(passes, key) then
			return false
		end
		local parts = pass.includes
		if parts then
			for _, part in parts do
				if typeof(passes) == "table" and passes[part] == true then
					return false -- a bundle is never sold to someone who owns one of its parts
				end
			end
		end
	end
	return true
end

-- the Shop is open for Robux buttons: the guide is done or skipped and the first AI is launched (ONBOARDING B5)
function ShopMath.gateOpen(data: any): boolean
	if typeof(data) ~= "table" or not data.company or TutorialMath.active(data) then
		return false
	end
	local stats = data.stats
	return typeof(stats) == "table" and num(stats.modelsReleased, 0) >= 1
end

-- SHOP_SPEC 5.2.1 parts 1, 2 and 4 for a voucher product `key`: "owned" (a voucher is held), "buy" (listed,
-- available, priced, for sale, buy guard ok), "preview" (Studio with id 0: "Not set up", never prompts) or nil.
-- Part 3 (the action works right now, the minimum saving in the buy state) is the caller's check.
function ShopMath.offerState(data: any, key: string, ui: OfferUi): string?
	if not ShopMath.gateOpen(data) then
		return nil
	end
	if ui.lastErrorAt ~= nil and ui.clock ~= nil and ui.clock - ui.lastErrorAt < 10 then
		return nil -- never right after a failure
	end
	if ShopMath.vouchers(data, key) >= 1 then
		return "owned"
	end
	local def = ShopConfig.productForVoucher(key)
	if not def or def.ready == false then
		return nil
	end
	if def.id <= 0 or ui.priced ~= true then
		return if ui.studio == true then "preview" else nil
	end
	local liveShop = if typeof(ui.live) == "table" then ui.live.shop else nil
	local available = typeof(liveShop) == "table" and typeof(liveShop.available) == "table" and liveShop.available[def.key] == true
	if not available or not ShopMath.buyAllowed(data, ui.live, key, num(ui.now, 0)) then
		return nil
	end
	return "buy"
end

export type StudioOffer = { state: string?, check: Check?, after: any?, need: string? }
-- SHOP_SPEC 5.2.4: SKIP RESEARCH · EUREKA in the Model Studio only when Frontier Architecture is the ONLY thing that
-- blocks the picked size (7B): no other lock after it, no training running, the cash covers Frontier and the training.
-- `estimate` = LabPreview.estimate (client module, passed in). Returns {need} = the other lock when that blocks.
function ShopMath.studioEurekaOffer(data: any, sel: any, money: number, estimate: (any, any, number?) -> any, ui: OfferUi): StudioOffer
	local est = estimate(data, sel, money)
	if not est or est.lock ~= "FRONTIER" then
		return { state = nil }
	end
	local job = data.empire.researchJob
	local running = typeof(job) == "table" and job.id == "frontier"
	local check = ShopMath.eurekaCheck(data, "frontier", money, false, ui.now)
	if not check.ok then
		return { state = nil, check = check }
	end
	local cost = if running then 0 else check.cost
	local after = estimate(ShopMath.withResearch(data, "frontier"), sel, money - cost)
	if after and after.lock ~= nil then
		return { state = nil, check = check, after = after, need = after.lock }
	end
	if data.training ~= nil then
		return { state = nil, check = check, after = after, need = "TRAINING" }
	end
	local state = ShopMath.offerState(data, "eureka", ui)
	if state ~= nil and state ~= "owned" then -- a buy (and the owner preview of one): only when it saves >= 30 s
		local buyCheck = ShopMath.eurekaCheck(data, "frontier", money, true, ui.now)
		if not buyCheck.ok then
			state = nil
		end
	end
	return { state = state, check = check, after = after }
end

---------------------------------------------------------------------------------------------- texts

-- "12:40" (play time left)
function ShopMath.clock(seconds: number): string
	local s = math.max(0, math.floor(num(seconds, 0) + 0.5))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- Headhunter (SHOP_SPEC 3.12): the department with the fewest people (team + open applications; ties in
-- EmpireConfig.ROLES order). RecruitingService.headhunt adds its skill-4 applicant there; YOUR ITEMS shows it.
function ShopMath.headhuntRole(e: any): string
	local best, bestN = EmpireConfig.ROLES[1].id, math.huge
	for _, role in EmpireConfig.ROLES do
		local n = if typeof(e.employees) == "table" then num(e.employees[role.id], 0) else 0
		if typeof(e.applicants) == "table" then
			for _, a in e.applicants do
				if typeof(a) == "table" and a.role == role.id then
					n += 1
				end
			end
		end
		if n < bestN then
			best, bestN = role.id, n
		end
	end
	return best
end

return ShopMath
