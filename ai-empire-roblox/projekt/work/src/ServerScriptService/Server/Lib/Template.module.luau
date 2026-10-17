--!strict
-- Startdaten eines neuen Spielers + Migrationen alter Spielstände.
--
-- Neues Feld in einer späteren Phase:
--   1. GameConfig.DATA_VERSION um 1 erhöhen
--   2. hier in MIGRATIONS[alteVersion] das Feld setzen (z. B. data.employees = {})
--   3. Template.new() um das Feld ergänzen
-- Alte Spielstände werden beim Laden Schritt für Schritt hochgezogen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Types = require(ReplicatedStorage.Shared.Types)

local EmpireMath = require(ReplicatedStorage.Shared.EmpireMath)
local CampusConfig=require(ReplicatedStorage.Shared.Config.CampusConfig)
local CampusMath=require(ReplicatedStorage.Shared.CampusMath)
local EmpireConfig=require(ReplicatedStorage.Shared.Config.EmpireConfig)
local ShopConfig=require(ReplicatedStorage.Shared.Config.ShopConfig)
local DepartmentConfig=require(ReplicatedStorage.Shared.Config.DepartmentConfig)
local CompanyOps=require(ReplicatedStorage.Shared.CompanyOps)
local ModelMath=require(ReplicatedStorage.Shared.ModelMath)
local ModelConfig=require(ReplicatedStorage.Shared.Config.ModelConfig)
local TutorialMath=require(ReplicatedStorage.Shared.TutorialMath)
local Template = {}

local function finiteNumber(v: any): boolean
	return typeof(v) == "number" and v == v and v > -math.huge and v < math.huge
end
local function marketUsers(m: any): number
	local n = 0
	local market = m.market
	if typeof(market) == "table" and typeof(market.users) == "table" then
		for _, u in market.users do if finiteNumber(u) and u > 0 then n += u end end
	end
	return n
end
local function clearMarket(m: any)
	if typeof(m.market) == "table" then
		m.market.users = {}
		m.market.organic = {}
		m.market.hype = {}
	end
end
-- CORE_SPEC 7.1 / 7.2 for saves from before product lines: one live model per line and at most
-- MarketConfig.PRODUCT_SLOTS[office] live lines (old saves could run clones side by side).
--  * per line the best live model stays (overall, then users, then the order of modelOrder); every other live
--    model of that line retires into it like a release of a new version: replacedBy = kept id, its users x
--    ModelConfig.MIGRATE and its word of mouth (organic) move over (AIModelService.releaseModel / PricingMath);
--  * lines beyond the office's slots (fewest users first) go back to "trained": they keep their release data
--    and history and can be released again into a free line.
function Template.normaliseLines(d: any)
	local models, order = d.models, d.modelOrder
	if typeof(models) ~= "table" or typeof(order) ~= "table" then return end
	local lines: { [string]: { any } } = {}
	local lineOrder: { string } = {}
	for _, id in order do
		local m = if typeof(id) == "string" then models[id] else nil
		if typeof(m) == "table" and m.status == "live" and typeof(m.release) == "table" then
			local line = ModelMath.lineOf(if typeof(m.release.target) == "string" then m.release.target else nil)
			if not lines[line] then lines[line] = {}; table.insert(lineOrder, line) end
			table.insert(lines[line], m)
		end
	end
	local kept: { any } = {}
	for _, line in lineOrder do
		local list = lines[line]
		local best = list[1]
		for _, m in list do
			local ov, bo = tonumber(m.overall) or 0, tonumber(best.overall) or 0
			if ov > bo or (ov == bo and marketUsers(m) > marketUsers(best)) then best = m end
		end
		for _, m in list do
			if m ~= best then
				local om, bm = m.market, best.market
				if typeof(om) == "table" and typeof(bm) == "table" then
					if typeof(bm.users) ~= "table" then bm.users = {} end
					if typeof(bm.organic) ~= "table" then bm.organic = {} end
					if typeof(om.users) == "table" then
						for seg, n in om.users do
							if typeof(seg) == "string" and finiteNumber(n) and n > 0 then bm.users[seg] = (tonumber(bm.users[seg]) or 0) + n * ModelConfig.MIGRATE end
						end
					end
					if typeof(om.organic) == "table" then
						for seg, o in om.organic do
							if typeof(seg) == "string" and finiteNumber(o) and o > 0 then bm.organic[seg] = (tonumber(bm.organic[seg]) or 0) + o end
						end
					end
				end
				m.status = "retired"
				m.replacedBy = best.id
				clearMarket(m)
			end
		end
		table.insert(kept, { line = line, model = best, users = marketUsers(best) })
	end
	local slots = ModelMath.productSlots(if typeof(d.empire) == "table" then d.empire.office else nil)
	if #kept > slots then
		table.sort(kept, function(a: any, b: any): boolean
			if a.users ~= b.users then return a.users > b.users end
			return a.line < b.line
		end)
		for i = slots + 1, #kept do
			local m = kept[i].model
			m.status = "trained"
			clearMarket(m)
		end
	end
end

-- Robux shop records (ShopService). receipts/order are server-only (SessionService never sends them):
-- receipts[PurchaseId] = os.time() of the grant, order = the same ids oldest first (trimmed to
-- ShopConfig.RECEIPTS_KEPT). vouchers[key] = unredeemed count. passes = fallback cache of game-pass
-- ownership, used only while Roblox can't be asked. tips = supporter tips received.
-- Shop package (SHOP_SPEC 7, pure additions, DATA_VERSION stays 6): boosts[key] = empire.seconds when the boost ends,
-- daily = {day = UTC day, used = {key = redeems that day}}, packs[key] = office of the last cash pack of that size,
-- packCredit[key] = cash packs of that size bought again in an office that already had one (fix round 1: paid one per
-- office move by ShopService.payPackCredits).
function Template.newShop(): any
	return { receipts = {}, order = {}, vouchers = {}, passes = {}, tips = 0, boosts = {}, daily = { used = {} }, packs = {}, packCredit = {} }
end

function Template.new(): Types.PlayerData
	local data: Types.PlayerData = {
		version = GameConfig.DATA_VERSION,
		empire = EmpireMath.new(),
		company = nil,
		money = GameConfig.START_MONEY,
		data = {},
		gpus = { laptop = 1 },
		models = {},
		modelOrder = {},
		training = nil,
		lastScrapeAt = 0,
		stats = {
			totalRevenue = 0,
			totalCost = 0,
			modelsTrained = 0,
			modelsReleased = 0,
			peakUsers = 0,
			bestOverall = 0,
		},
	}
	-- not part of Types.PlayerData (shared type); added untyped like the other optional save fields
	;(data :: any).shop = Template.newShop()
	;(data :: any).trainings = {} -- DATA_VERSION 6: reserved for training slots 2..4 (CORE_SPEC 7.6)
	return data
end

-- MIGRATIONS[v] hebt einen Spielstand von Version v auf v + 1.
local MIGRATIONS: { [number]: (data: any) -> () } = {
	[1] = function(data: any) data.empire = EmpireMath.new() end,
	[3] = function(data: any) end,
	[4] = function(data: any) end,
	[2] = function(data: any) end, -- nested defaults preserve existing founder progress
	-- 5 -> 6 (CORE_SPEC 2.4): the Garage Lab is inserted as office 1. A founded company keeps its building:
	-- old tier k becomes stage k + 1 (same plan tier through BuildingPlan.OFFICE_TIER_OFFSET = 1); a save
	-- that never founded a company starts in the garage.
	[5] = function(d: any)
		local e = d.empire
		if typeof(e) ~= "table" then return end
		if d.company then
			e.office = math.clamp(math.floor(tonumber(e.office) or 1) + 1, 2, 5) -- old tier k -> stage k+1 (same building)
		else
			e.office = 1 -- never founded: start in the garage
		end
		d.trainings = if typeof(d.trainings) == "table" then d.trainings else {} -- reserved for slots 2..4 (7.6)
		-- the lease auction is gone: its customers / revenue are empty compatibility fields (2.4)
		e.customers = {}
		e.businessRevenue = 0
		-- one live model per product line, live lines within the stage's slots (7.1 / 7.2)
		Template.normaliseLines(d)
	end,
}

-- Open job applications (RecruitingService): at most MAX_APPLICANTS well-formed entries survive.
-- Private traits (true skill, temperament) are not stored; the server derives them from `serial`.
local APPLICANT_STATUS={new=true,invited=true,interviewing=true}
local function cleanApplicants(raw: any): {any}
	local out={}
	if typeof(raw)~="table" then return out end
	local function finite(v: any): boolean return typeof(v)=="number" and v==v and v>-math.huge and v<math.huge end
	for _,a in raw do
		if #out>=EmpireMath.MAX_APPLICANTS then break end
		if typeof(a)~="table" or typeof(a.id)~="string" or #a.id>24 or not EmpireConfig.find(EmpireConfig.ROLES,a.role) then continue end
		if typeof(a.n)~="string" or not finite(a.s) or not finite(a.serial) or not finite(a.ask) or not finite(a.at) then continue end
		local asked={}
		if typeof(a.q)=="table" then for _,q in a.q do if typeof(q)=="string" and #q<=24 and #asked<7 then table.insert(asked,q) end end end
		table.insert(out,{id=a.id,serial=math.floor(math.abs(a.serial)),role=a.role,n=string.sub(a.n,1,40),s=math.floor(math.abs(a.s))%2147483647,
			xp=if finite(a.xp) then math.clamp(math.floor(a.xp),0,40) else 0,prev=if typeof(a.prev)=="string" then string.sub(a.prev,1,48) else "",
			spec=if typeof(a.spec)=="string" then string.sub(a.spec,1,48) else "",ask=math.clamp(a.ask,0.8,1.5),at=a.at,
			st=if typeof(a.st)=="string" and APPLICANT_STATUS[a.st] then a.st else "new",q=asked,
			r=if finite(a.r) then math.clamp(math.floor(a.r),1,3) else nil,low=if a.low==true then true else nil})
	end
	return out
end

-- Repairs data.shop without ever dropping something a player paid for: unknown voucher keys are kept
-- (a voucher removed from ShopConfig must not vanish), counts are clamped, receipts/order rebuilt.
local SHOP_KEY_MAX = 32
local SHOP_LIST_MAX = 32
local RECEIPT_ID_MAX = 128
local function shopKey(key: any): boolean
	return typeof(key) == "string" and #key > 0 and #key <= SHOP_KEY_MAX and string.find(key, "[^%w_]") == nil
end
function Template.cleanShop(raw: any): any
	local shop = Template.newShop()
	if typeof(raw) ~= "table" then
		return shop
	end
	local function finite(v: any): boolean
		return typeof(v) == "number" and v == v and v > -math.huge and v < math.huge
	end
	-- receipts: string id -> grant time. order: the same ids, oldest first, no duplicates.
	local receipts: { [string]: number } = {}
	if typeof(raw.receipts) == "table" then
		for id, at in raw.receipts do
			if typeof(id) == "string" and #id > 0 and #id <= RECEIPT_ID_MAX then
				receipts[id] = if finite(at) then at else 0
			end
		end
	end
	local order: { string } = {}
	local listed: { [string]: boolean } = {}
	if typeof(raw.order) == "table" then
		for _, id in raw.order do
			if typeof(id) == "string" and receipts[id] ~= nil and not listed[id] then
				listed[id] = true
				table.insert(order, id)
			end
		end
	end
	-- receipts missing from order count as the oldest (sorted by grant time, then id: deterministic)
	local missing: { string } = {}
	for id in receipts do
		if not listed[id] then
			table.insert(missing, id)
		end
	end
	table.sort(missing, function(a: string, b: string): boolean
		if receipts[a] ~= receipts[b] then
			return receipts[a] < receipts[b]
		end
		return a < b
	end)
	for i, id in missing do
		table.insert(order, i, id)
	end
	while #order > ShopConfig.RECEIPTS_KEPT do
		receipts[table.remove(order, 1) :: string] = nil
	end
	shop.receipts = receipts
	shop.order = order
	if typeof(raw.vouchers) == "table" then
		local n = 0
		for key, count in raw.vouchers do
			if shopKey(key) and finite(count) and n < SHOP_LIST_MAX then
				local c = math.clamp(math.floor(count), 0, ShopConfig.VOUCHER_MAX)
				if c > 0 then
					shop.vouchers[key] = c
					n += 1
				end
			end
		end
	end
	if typeof(raw.passes) == "table" then
		local n = 0
		for key, owned in raw.passes do
			if shopKey(key) and owned == true and n < SHOP_LIST_MAX then
				shop.passes[key] = true
				n += 1
			end
		end
	end
	shop.tips = if finite(raw.tips) then math.max(0, math.floor(raw.tips)) else 0
	-- shop package (SHOP_SPEC 7): known keys and finite values only
	if typeof(raw.boosts) == "table" then
		for key in ShopConfig.BOOSTS do
			local v = raw.boosts[key]
			if finite(v) and v > 0 then
				shop.boosts[key] = v
			end
		end
	end
	if typeof(raw.daily) == "table" then
		local day = raw.daily.day
		if finite(day) and day >= 0 and day % 1 == 0 then
			shop.daily.day = day
		end
		if typeof(raw.daily.used) == "table" then
			for key, cap in ShopConfig.DAILY do
				local n = raw.daily.used[key]
				if finite(n) then
					local c = math.clamp(math.floor(n), 0, cap)
					if c > 0 then
						shop.daily.used[key] = c
					end
				end
			end
		end
	end
	if typeof(raw.packs) == "table" then
		for _, def in ShopConfig.PRODUCTS do
			local office = raw.packs[def.key]
			if def.kind == "cash" and finite(office) and office % 1 == 0 and office >= 1 and office <= #EmpireConfig.OFFICES then
				shop.packs[def.key] = office
			end
		end
	end
	-- pack credits are paid for: kept like vouchers (any valid key, counts clamped, never dropped for being unknown)
	if typeof(raw.packCredit) == "table" then
		local n = 0
		for key, count in raw.packCredit do
			if shopKey(key) and finite(count) and n < SHOP_LIST_MAX then
				local c = math.clamp(math.floor(count), 0, ShopConfig.VOUCHER_MAX)
				if c > 0 then
					shop.packCredit[key] = c
					n += 1
				end
			end
		end
	end
	return shop
end

-- A boost never has more than BOOST_MAX_LEFT of play time left (fix round 1): a corrupt end time far in the future is cut
-- back to "60 min from now". Runs after cleanShop and the empire cleaners (empire.seconds is a finite number >= 0 then).
function Template.clampBoosts(raw: any)
	local shop = raw.shop
	local e = raw.empire
	if typeof(shop) ~= "table" or typeof(shop.boosts) ~= "table" or typeof(e) ~= "table" then
		return
	end
	local now = tonumber(e.seconds) or 0
	if now ~= now or now == math.huge then
		now = 0
	end
	for key, v in shop.boosts do
		if typeof(v) == "number" and v > now + ShopConfig.BOOST_MAX_LEFT then
			shop.boosts[key] = now + ShopConfig.BOOST_MAX_LEFT
		end
	end
end

-- CORE_SPEC Appendix A cleaners (DATA_VERSION 6 fields). Runs after the nested defaults, so every field
-- exists; repairs types and value ranges without dropping valid progress.
local function finite(v: any): boolean
	return typeof(v) == "number" and v == v and v > -math.huge and v < math.huge
end
local HR_BUDGETS = { [0.25] = true, [0.40] = true, [0.55] = true }
local TRIP_KINDS = { sign = true, renew = true }
function Template.cleanCompany(raw: any)
	local e = raw.empire
	-- company calendar: day integer >= 1, index (server day index of the last tick) number or nil
	local cal = if typeof(e.calendar) == "table" then e.calendar else {}
	e.calendar = { day = if finite(cal.day) then math.max(1, math.floor(cal.day)) else 1, index = if finite(cal.index) then math.floor(cal.index) else nil }
	-- B2B pipeline (CompanyOps.ensure does the type part): only catalogue clients, <= 16 well-formed trips,
	-- <= 40 news lines of <= 120 characters, finite numbers >= 0
	local d = CompanyOps.ensure(e)
	local accounts = {}
	for id, acc in d.accounts do
		if CompanyOps.client(id) and typeof(acc) == "table" and finite(acc.expires) then
			accounts[id] = { expires = math.floor(math.max(0, acc.expires)), since = if finite(acc.since) then math.floor(math.max(0, acc.since)) else 0,
				founder = if acc.founder == true then true else nil, renewing = if acc.renewing == true then true else nil }
		end
	end
	d.accounts = accounts
	local trust = {}
	for id, t in d.trust do if CompanyOps.client(id) and finite(t) and t > 0 then trust[id] = math.min(t, 2) end end
	d.trust = trust
	local trips = {}
	for _, t in d.tripList do
		if #trips >= CompanyOps.TRIPS_MAX then break end
		if typeof(t) == "table" and CompanyOps.client(t.client) and TRIP_KINDS[t.kind] and finite(t.back) then
			table.insert(trips, { client = t.client, kind = t.kind, back = math.floor(math.max(0, t.back) + 0.5), founder = t.founder == true, hosted = t.hosted == true,
				crew = if finite(t.crew) then math.clamp(math.floor(t.crew), 0, 2) else 1, left = if finite(t.left) then math.floor(t.left) else nil, joined = if t.joined == true then true else nil })
		end
	end
	d.tripList = trips
	local news = {}
	for _, line in d.news do
		if #news >= CompanyOps.NEWS_MAX then break end
		if typeof(line) == "string" then table.insert(news, CompanyOps.clip(line, CompanyOps.NEWS_CHARS)) end
	end
	d.news = news
	local skip = {}
	for id, v in d.skip do if CompanyOps.client(id) and v == true then skip[id] = true end end
	d.skip = skip
	-- Lab level 0..10, jet boolean, auto-HR settings, Save mode, night shifts, apprentices, unpaid leave
	e.labLevel = if finite(e.labLevel) then math.clamp(math.floor(e.labLevel), 0, CompanyOps.LAB_MAX) else 0
	e.jet = e.jet == true
	local hr = if typeof(e.hr) == "table" then e.hr else {}
	local budget = tonumber(hr.budget)
	if budget then budget = math.round(budget * 100) / 100 end
	e.hr = { auto = hr.auto ~= false, budget = if budget and HR_BUDGETS[budget] then budget else 0.40 }
	e.saveMode = if e.saveMode == "off" then "off" else "auto"
	local night = {}
	if typeof(e.nightShift) == "table" then
		for dept, on in e.nightShift do if typeof(dept) == "string" and DepartmentConfig.DEPARTMENTS[dept] and on == true then night[dept] = true end end
	end
	e.nightShift = night
	local seeds: { [string]: boolean } = {}
	for _, list in e.staffProfiles do
		if typeof(list) == "table" then for _, p in list do if typeof(p) == "table" and finite(p.s) then seeds[tostring(p.s)] = true end end end
	end
	local apprentices = {}
	if typeof(e.apprentices) == "table" then
		for key, a in e.apprentices do
			if typeof(key) == "string" and seeds[key] and typeof(a) == "table" and finite(a.day) then apprentices[key] = { day = math.max(1, math.floor(a.day)) } end
		end
	end
	e.apprentices = apprentices
	e.unpaidLeave = if finite(e.unpaidLeave) then math.clamp(math.floor(e.unpaidLeave), 0, EmpireMath.staff(e)) else 0
	-- player preferences (phone request 1): only the boolean autoTrips survives, every other key is dropped
	local prefs = if typeof(e.prefs) == "table" then e.prefs else {}
	e.prefs = { autoTrips = prefs.autoTrips == true }
	-- the lease auction is gone (CORE_SPEC 2.4): empty compatibility fields, also for saves migrated earlier
	e.customers = {}
	e.businessRevenue = 0
	-- P&L ledger: <= LEDGER_DAYS day keys, each {i = income by category, o = costs by category} with
	-- <= LEDGER_CATEGORIES finite entries per side ("other" included; the smallest extra lines merge into it)
	local ledger = {}
	if typeof(e.ledger) == "table" then
		local days = {}
		for key, entry in e.ledger do
			local day = tonumber(key)
			if typeof(key) == "string" and day and finite(day) and day == math.floor(day) and day >= 1 and typeof(entry) == "table" then table.insert(days, day) end
		end
		table.sort(days, function(a: number, b: number): boolean return a > b end)
		for k = 1, math.min(CompanyOps.LEDGER_DAYS, #days) do
			local entry = e.ledger[tostring(days[k])]
			local clean = { i = {}, o = {} }
			for _, side in { "i", "o" } do
				if typeof(entry[side]) == "table" then
					local cats = {}
					for cat, v in entry[side] do
						if typeof(cat) == "string" and #cat > 0 and #cat <= 16 and finite(v) then table.insert(cats, { cat = cat, v = v }) end
					end
					table.sort(cats, function(a: any, b: any): boolean
						if a.v ~= b.v then return a.v > b.v end
						return a.cat < b.cat
					end)
					local n, other, hasOther = 0, 0, false
					for _, c in cats do
						if c.cat == "other" then other += c.v; hasOther = true
						elseif n < CompanyOps.LEDGER_CATEGORIES - 1 then clean[side][c.cat] = c.v; n += 1
						else other += c.v; hasOther = true end
					end
					if hasOther then clean[side].other = other end
				end
			end
			ledger[tostring(days[k])] = clean
		end
	end
	e.ledger = ledger
	-- reserved v2 training slots: string keys "2".."4" only (empty in v1)
	local trainings = {}
	if typeof(raw.trainings) == "table" then
		for key, job in raw.trainings do if (key == "2" or key == "3" or key == "4") and typeof(job) == "table" then trainings[key] = job end end
	end
	raw.trainings = trainings
	-- model fields of CORE_SPEC 7 (models package): version age, successor link, auto-price flag
	if typeof(raw.models) == "table" then
		for _, m in raw.models do
			if typeof(m) ~= "table" then continue end
			if typeof(m.market) == "table" then
				local vage = m.market.vage
				m.market.vage = if finite(vage) and vage >= 0 then vage elseif finite(m.market.age) then math.max(0, m.market.age) else 0
			end
			if m.replacedBy ~= nil and (typeof(m.replacedBy) ~= "string" or typeof(raw.models[m.replacedBy]) ~= "table") then m.replacedBy = nil end
			if typeof(m.release) == "table" then m.release.auto = m.release.auto ~= false end
		end
	end
end

-- "First steps" guide (ONBOARDING_SPEC A6, menu package): empire.tutorial = {v, step 0..5, done, skipped, tipsOff,
-- seen = {[SEEN_KEY] = true}, tips = {[TIP_KEY] = true}}. Idempotent; unknown keys and junk types are dropped.
-- Old saves that already launched a model never see the guide and get no NEW-badge flood.
function Template.cleanTutorial(raw: any)
	local e = raw.empire
	local t = if typeof(e.tutorial) == "table" then e.tutorial else {}
	-- `finite` returns a boolean (local helper above), never the number
	local step = if finite(t.step) then math.clamp(math.floor(t.step), 0, TutorialMath.STEPS) else 0
	local out = { v = 1, step = step, done = t.done == true, skipped = t.skipped == true, tipsOff = t.tipsOff == true, seen = {}, tips = {} }
	for k, v in (if typeof(t.seen) == "table" then t.seen else {}) do
		if v == true and typeof(k) == "string" and table.find(TutorialMath.SEEN_KEYS, k) then out.seen[k] = true end
	end
	for k, v in (if typeof(t.tips) == "table" then t.tips else {}) do
		if v == true and typeof(k) == "string" and table.find(TutorialMath.TIP_KEYS, k) then out.tips[k] = true end
	end
	local released = if typeof(raw.stats) == "table" then tonumber(raw.stats.modelsReleased) or 0 else 0
	if out.step == 0 and not out.done and not out.skipped and released > 0 then
		out.done = true
		for _, key in TutorialMath.unlockedKeys(raw) do
			if table.find(TutorialMath.SEEN_KEYS, key) then out.seen[key] = true end
		end
	end
	e.tutorial = out
end

-- Gibt (Daten, nil) oder (nil, Grund) zurück. Ein Grund bedeutet: NICHT überschreiben, Spieler kicken.
function Template.migrate(raw: any): (Types.PlayerData?, string?)
	if typeof(raw) ~= "table" then
		if raw == nil then return Template.new(), nil end
		return nil, "invalid save; original preserved"
	end
	local version = if typeof(raw.version) == "number" then raw.version else 0
	if version > GameConfig.DATA_VERSION then
		return nil, "save is from a newer game version"
	end
	while version < GameConfig.DATA_VERSION do
		local step = MIGRATIONS[version]
		if step then
			step(raw)
		end
		version += 1
	end
	raw.version = version

	-- fehlende Felder auffüllen: robust gegen halbe Spielstände
	local defaults: any = Template.new()
	for key, value in defaults do
		if raw[key] == nil then
			raw[key] = value
		end
	end
	if typeof(raw.stats) ~= "table" then
		raw.stats = defaults.stats
	end
	for key, value in defaults.stats do
		if raw.stats[key] == nil then
			raw.stats[key] = value
		end
	end
	-- Nested defaults protect migrations without clearing existing progress.
	if typeof(raw.empire) ~= "table" then raw.empire = EmpireMath.new() end
	for key, value in EmpireMath.new() do
		if raw.empire[key] == nil then raw.empire[key] = value end
	end
	local e = raw.empire
	for _, key in {"employees", "research", "quests", "contracts", "history", "subscriptions", "invoices", "customers", "projects", "projectOrder", "deliveries", "arenaHistory"} do
		if typeof(e[key]) ~= "table" then e[key] = {} end
	end
	if typeof(e.infrastructure)~="table" then e.infrastructure={cooling=1,trainingShare=0.7} end
	e.infrastructure.cooling=math.clamp(math.floor(tonumber(e.infrastructure.cooling) or 1),1,8)
	e.infrastructure.trainingShare=math.clamp(tonumber(e.infrastructure.trainingShare) or 0.7,0.25,0.9)
	if e.projectJob~=nil and typeof(e.projectJob)~="table" then e.projectJob=nil end
	e.arenaBest=math.max(0,tonumber(e.arenaBest) or 0)
	e.historyClock = math.clamp(tonumber(e.historyClock) or 0,0,10)
	if typeof(e.daily) ~= "table" then e.daily = {day=-1,streak=0} end
	e.daily.day = tonumber(e.daily.day) or -1
	e.daily.streak = math.clamp(math.floor(tonumber(e.daily.streak) or 0),0,7)
	e.office = math.clamp(math.floor(tonumber(e.office) or 1),1,#EmpireConfig.OFFICES)
	local remaining=EmpireConfig.OFFICES[e.office].staff
	local cleanEmployees={}
	for _,role in EmpireConfig.ROLES do
		local n=tonumber(e.employees[role.id]) or 0
		if n~=n or n==math.huge or n==-math.huge then n=0 end
		n=math.clamp(math.floor(n),0,remaining);cleanEmployees[role.id]=n;remaining-=n
	end
	e.employees=cleanEmployees
	-- Staff identities follow the cleaned counts (240 cap included). Without the user id only the
	-- shape is repaired; RecruitingService fills generated names/seeds when the session loads, which
	-- are exactly the identities the building shows today (EmpireMath.syncProfiles).
	EmpireMath.syncProfiles(e,nil)
	e.hireSerial=math.max(0,math.floor(tonumber(e.hireSerial) or 0))
	if e.hireSerial~=e.hireSerial or e.hireSerial==math.huge then e.hireSerial=0 end
	e.applicants=cleanApplicants(e.applicants)
	if typeof(e.campus)~="table" then e.campus=CampusMath.new() end
	local c=e.campus
	for k,v in CampusMath.new() do if c[k]==nil then c[k]=v end end
	local function number(value: any,default: number): number
		local n=tonumber(value);return if n and n==n and n<math.huge and n> -math.huge then n else default
	end
	c.retailLevel=math.clamp(math.floor(number(c.retailLevel,1)),1,4)
	c.retailClock=math.clamp(number(c.retailClock,0),0,29.99)
	c.retailSales=math.max(0,math.floor(number(c.retailSales,0)));c.retailRevenue=math.max(0,number(c.retailRevenue,0))
	c.boostUntil=math.clamp(number(c.boostUntil,0),0,os.time()+240);c.boostSpeed=math.clamp(number(c.boostSpeed,16),16,21)
	local snacks={};local slots=16
	for _,def in CampusConfig.SNACKS do
		local count=if typeof(c.snacks)=="table" then number(c.snacks[def.id],0) else 0
		count=math.clamp(math.floor(count),0,slots);snacks[def.id]=count;slots-=count
	end
	c.snacks=snacks
	local cars={compact=true}
	for _,def in CampusConfig.CARS do if typeof(c.cars)=="table" and c.cars[def.id]==true then cars[def.id]=true end end
	c.cars=cars;c.selectedCar=if typeof(c.selectedCar)=="string" and cars[c.selectedCar] then c.selectedCar else "compact"
	for _,key in {"points","xp","seconds","contractsCompleted"} do
		e[key] = math.max(0, tonumber(e[key]) or 0)
	end
	Template.cleanCompany(raw)
	Template.cleanTutorial(raw) -- menu package (ONBOARDING_SPEC A6)
	-- Robux records: old saves get an empty shop (filled above), malformed ones are repaired. No
	-- DATA_VERSION bump needed: a pure addition, like staffProfiles.
	raw.shop = Template.cleanShop(raw.shop)
	Template.clampBoosts(raw) -- fix round 1: at most 60 min of a boost left
	return raw :: Types.PlayerData, nil
end

return Template
