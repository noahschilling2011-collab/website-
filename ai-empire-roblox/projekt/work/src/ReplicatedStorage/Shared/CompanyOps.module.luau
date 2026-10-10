--!strict
-- CompanyOps (CORE_SPEC final design, sections 3-6, 8 and 11): the company as a real business.
-- Pure functions of saved company state (data.empire, data.models, data.gpus), play time (empire.seconds)
-- and the visible server clock, so a company earns exactly the same whether anybody watches its
-- building or not. Runs on the server (EmpireService.tick -> Ops.step) and on the client (screens,
-- WorkforceMath.count) with identical results.
--   * one saved company calendar (empire.calendar), play time empire.seconds, 1 game day = 1200 s
--   * time sheet TS(hour): expected share of a team at work (seed-uniform shifts), day average 0.5538
--   * staff presence: vacation / sick days from hashes of the appearance seed (no profile fields), HR
--     collision cap per team, unpaid leave, travelling engineers, apprentices, night crew -> output O_r
--   * B2B pipeline: catalogue client -> founder / Growth & Sales field rep drives (city/region) or flies
--     (abroad) -> deterministic trust bar -> pilot fee + daily retainer -> check-in visit before term end
--   * guest house (stage >= 3): every second region/abroad pilot is hosted at HQ (no flight/hotel, +trust)
--   * running costs besides hired wages: operations staff, drivers, Training Lead, phones, rent and
--     utilities, lunch, fleet leases, trips, guest house, company jet
--   * serving capacity (users) from GPUs, cooling and engineers; B2B reserves part of it; a rack fault
--     takes one compute unit off line until IT fixes it
--   * auto-HR helpers (need, pick, wage budget), Save mode, safety rules (unpaid leave, broke pause)
-- Money only moves through EconomyService (passed in as `Economy`: spend / applyFlow with a ledger category).
local Config = script.Parent.Config
local HardwareConfig = require(Config.HardwareConfig)
local ModelConfig = require(Config.ModelConfig)
local EmpireConfig = require(Config.EmpireConfig)
local MarketConfig = require(Config.MarketConfig)
local EmployeeConfig = require(Config.EmployeeConfig)
local ModelMath = require(script.Parent.ModelMath)
local Workforce = require(script.Parent.WorkforceMath)

local Ops = {}
Ops.DAY = 1200 -- seconds per game day (EmployeeConfig.hour: 900 s 08-18 + 300 s night)
Ops.MONTH = 3600 -- billing month = 3 game days (GameConfig.GAME_MONTH_SECONDS, unchanged)
Ops.AVAILABILITY = 0.9 -- expected share present: 1 - vacation 8.3 % - sick 1.7 % (used for lunch counts and HR maths)
Ops.PILOT_DAYS = 1 -- pilot fee on signing = 1 day of retainer
Ops.TERM_DAYS = 6 -- a retainer runs 2 billing months, then needs a check-in visit to renew
Ops.RENEW_LEAD_DAYS = 0.5
Ops.ACCOUNTS_PER_REP = 2 -- one field rep (Growth & Sales on field duty) looks after <= 2 retainers
Ops.FOUNDER_ACCOUNTS = 2 -- the founder sells too (city clients only)
Ops.DEPART = { from = 8, to = 15 } -- trips start in office hours only (server clock, what the player sees)
Ops.OPS_WAGE = (EmployeeConfig :: any).OPS_WAGE_PER_DAY or 720 -- $ per game day per operations post
Ops.FLEET_LEASE = 100 -- $ per game day per leased field car (one per field rep; the boss's car is owned)
Ops.CASH_MARGIN = 500 -- trips only when cash covers the trip + this
Ops.FIRST_CLIENT_TRUST = 0.5 -- "your friend at CloudDesk": the scripted first pilot signs on the first visit
Ops.MEETING_TRUST = 0.15 -- the founder joins a pilot meeting in person (CityService meeting prompt)
Ops.CAP_PER_UNIT = 15000 -- users served per compute unit (x thermal x engineering factor)
Ops.ENG_CAP = 1.0 -- engineers raise serving capacity by up to +100 % (1 - e^(-O/20))
Ops.ENG_K = 20
Ops.B2B_SCALE = 1 -- tuning knob of the simulator: multiplies every retainer (stays 1)
Ops.UPKEEP_SCALE = 1 -- tuning knob of the simulator (stays 1)
Ops.PHONE = 10 -- $ per employee (hired + operations) per game day: company phones
Ops.DRIVER = { wage = 720, from = 2, more = 4 } -- 1 driver from stage 2, 2 from stage 4 (ops/fleet job)
Ops.TRAINING_LEAD = { wage = 900, from = 3 } -- the apprentices' trainer (Ausbilder)
Ops.APPRENTICE = { wage = 0.4, fee = 0.5, rampDays = 3, graduateDays = 9, startSkill = 1, endSkill = 3 }
Ops.NIGHT = { wage = 1.3, from = 3 } -- night crew: overflow heads (up to the seats) work 22-06 at 1.0, wage x1.3
Ops.HIRE_GAP = 20 -- auto-HR: one hire per 20 s
Ops.HR_BUDGETS = { 0.25, 0.40, 0.55 } -- wage budget slider (share of the 5-minute trailing income)
Ops.HR_STARTERS = 3 -- the first 3 hires are always allowed
Ops.SAVE_MINUTES = 8 -- Save mode: the next office is less than 8 minutes of net profit away
Ops.NEWS_MAX = 40
Ops.NEWS_SHOWN = 20 -- the client (phone, assistant) gets the newest 20 (SessionService trims the replicated copy)
-- bytes per news line incl. the stamp "day 12 10:00: " (Appendix A allows <= 120; 80 keeps the 20 replicated
-- lines + 14 accounts + 7 trips inside the 3 KB deals budget of CORE_SPEC 11.8). Lines are cut on a UTF-8
-- character boundary (Ops.clip), never inside a multi-byte character.
Ops.NEWS_CHARS = 80
Ops.TRIPS_MAX = 16
-- P&L ledger (CORE_SPEC 4, Appendix A): LEDGER_DAYS company days are saved, the newest LEDGER_SHOWN are
-- replicated (SessionService), at most LEDGER_CATEGORIES lines per side and day ("other" included) so the
-- replicated ledger stays <= 2.5 KB even at the caps (CORE_SPEC 11.8).
Ops.LEDGER_DAYS = 7
Ops.LEDGER_SHOWN = 4
Ops.LEDGER_CATEGORIES = 16
-- rack faults (CORE_SPEC 5.2 / 5.5): every installed rack GPU fails with FAULT.rate per game day of play
-- (rolled once per FAULT.every play seconds from a hash of the company and the minute: deterministic,
-- identical watched or not); a fault takes FAULT.units compute units of that GPU off line ("capacity -1 unit
-- per fault", CORE_SPEC 5.5 / 10) until fixed: FAULT.it seconds of repair work with the IT post on duty,
-- FAULT.alone seconds without (the garage has no IT post, IT works 08-18 and from stage 5 also at night).
-- A staffed hardware lab (stage >= 4, engineers >= half their desks) halves the rate.
Ops.FAULT = { rate = 0.06, every = 60, it = 60, alone = 300, hwlab = 0.5, units = 1 }

-- office stages (EmpireConfig.OFFICES index; 1 = Garage Lab, 2..5 = the HQ buildings of plan tiers 1..4)
-- lines = live product lines; clients = B2B account slots; ops = automatic operations posts;
-- upkeep = rent + utilities per game day; food = lunch $ per person per day; trips = farthest trip tier;
-- kitchen = lunches per day; wellness / barista feed morale
Ops.STAGES = {
	{ lines = 1, clients = 2, ops = 0, upkeep = 300, food = 6, guest = false, trips = "city", kitchen = 0, wellness = 0, barista = 0 },
	{ lines = 2, clients = 4, ops = 8, upkeep = 2500, food = 8, guest = false, trips = "city", kitchen = 120, wellness = 0.5, barista = 1 },
	{ lines = 3, clients = 7, ops = 12, upkeep = 9000, food = 8, guest = true, trips = "region", kitchen = 145, wellness = 1, barista = 1 },
	{ lines = 4, clients = 10, ops = 14, upkeep = 24000, food = 8, guest = true, trips = "abroad", kitchen = 145 + 4 * 15, wellness = 1, barista = 1 },
	{ lines = 4, clients = 14, ops = 16, upkeep = 48000, food = 8, guest = true, trips = "abroad", kitchen = 145 + 6 * 15, wellness = 1, barista = 1 },
}
local TIER = { city = 1, region = 2, abroad = 3 }
-- seats per role per stage (BuildingPlan room desks; garage = 5 shared team desks + the founder desk)
-- researcher = design + research + 1/2 evaluation; engineer = engineering + training + 1/2 evaluation;
-- curator = data (+3 First AI data desks at T1); marketer (Growth & Sales) = growth + deployment
Ops.SEATS = {
	{ researcher = 5, engineer = 5, curator = 5, marketer = 5 },
	{ researcher = 15, engineer = 16, curator = 14, marketer = 16 },
	{ researcher = 26, engineer = 28, curator = 32, marketer = 34 },
	{ researcher = 50, engineer = 56, curator = 32, marketer = 34 },
	{ researcher = 93, engineer = 85, curator = 32, marketer = 71 },
}
-- departments (BuildingPlan / DepartmentConfig ids) of each hired role: night shifts are set per department
Ops.ROLE_DEPTS = {
	researcher = { "research", "design", "evaluation" },
	engineer = { "engineering", "training" },
	curator = { "data" },
	marketer = { "growth", "deployment" },
}
-- trips: days away, hotel nights per traveller, fuel, flight per traveller (round trip), hotel $/night, crew
Ops.TRIPS = {
	city = { days = 0.2, nights = 0, fuel = 30, flight = 0, hotel = 0, crew = 1 },
	region = { days = 1, nights = 1, fuel = 90, flight = 0, hotel = 140, crew = 2 },
	abroad = { days = 2, nights = 2, fuel = 40, flight = 700, hotel = 220, crew = 2 },
}
Ops.PER_DIEM = 50 -- per traveller per started day
-- company jet (late purchase from stage JET.stage, a money sink that adds convenience, not income): abroad
-- trips fly the jet with the 2 company pilots instead of the airline - no tickets, 1.5 days instead of 2
-- (1 hotel night), +0.05 trust per abroad visit; fixed running cost per game day (pilot wages + upkeep)
Ops.JET = { price = 900000, stage = 4, pilots = 2, pilotWage = 3000, upkeep = 2500, fuel = 1500, days = 1.5, nights = 1, trust = 0.05 }
Ops.HOSTED = { nightCost = 60, guests = 2, nights = 2, trust = 0.10 } -- client team stays at the guest house
Ops.GUEST = { rooms = 12, occupancy = 0.6, rate = 300, utilities = 400, staff = 2 }
-- one client catalogue (replaces EmpireConfig.CONTRACTS + MarketService.businesses); retainer $/game day,
-- tokens = M tokens per billing month (they reserve compute: deals.reserved = sum tokens / 100).
-- Map a client to its building BY NAME (CityPlan.clientOffice(client.name)), never by id.
Ops.CLIENTS = {
	{ id = "helpdesk", name = "CloudDesk", stat = "reliability", minimum = 24, stage = 1, retainer = 9000, tokens = 40, trip = "city", first = true },
	{ id = "paper", name = "Paper Studio", stat = "creativity", minimum = 30, stage = 1, retainer = 9000, tokens = 50, trip = "city" },
	{ id = "code", name = "ByteWorks", stat = "coding", minimum = 36, stage = 1, retainer = 13500, tokens = 70, trip = "city" },
	{ id = "pixel", name = "Pixel Games", stat = "coding", minimum = 40, stage = 2, retainer = 13500, tokens = 90, trip = "city" },
	{ id = "study", name = "StudySpark", stat = "math", minimum = 40, stage = 2, retainer = 13500, tokens = 90, trip = "city" },
	{ id = "north", name = "North Logistics", stat = "reasoning", minimum = 42, stage = 2, retainer = 15000, tokens = 100, trip = "city" },
	{ id = "civic", name = "Civic Support", stat = "reliability", minimum = 46, stage = 2, retainer = 18000, tokens = 120, trip = "city" },
	{ id = "creative", name = "PixelForge", stat = "creativity", minimum = 48, stage = 3, retainer = 24000, tokens = 160, trip = "region" },
	{ id = "ledger", name = "Ledger Finance", stat = "math", minimum = 50, stage = 3, retainer = 27000, tokens = 180, trip = "region" },
	{ id = "orbitgames", name = "Orbit Games", stat = "coding", minimum = 52, stage = 3, retainer = 30000, tokens = 200, trip = "region" },
	{ id = "atlas", name = "Atlas Search", stat = "knowledge", minimum = 55, stage = 3, retainer = 36000, tokens = 240, trip = "region" },
	{ id = "delta", name = "Delta Robotics", stat = "reasoning", minimum = 60, stage = 4, retainer = 45000, tokens = 300, trip = "region" },
	{ id = "enterprise", name = "Nova Logistics", stat = "reliability", minimum = 62, stage = 4, retainer = 54000, tokens = 360, trip = "region" },
	{ id = "mosaic", name = "Mosaic Worlds", stat = "creativity", minimum = 65, stage = 4, retainer = 63000, tokens = 420, trip = "region" },
	{ id = "helix", name = "Helix Research", stat = "math", minimum = 70, stage = 4, retainer = 78000, tokens = 520, trip = "abroad" },
	{ id = "frontier", name = "Orbit Systems", stat = "reasoning", minimum = 75, stage = 5, retainer = 105000, tokens = 700, trip = "abroad" },
	{ id = "nova", name = "Nova Infrastructure", stat = "coding", minimum = 80, stage = 5, retainer = 135000, tokens = 900, trip = "abroad" },
	{ id = "science", name = "Frontier Science", stat = "reasoning", minimum = 86, stage = 5, retainer = 180000, tokens = 1200, trip = "abroad" },
} :: { any }
local byId: { [string]: any } = {}
for _, c in Ops.CLIENTS do byId[c.id] = c end
Ops.byId = byId
local scaled = false
function Ops.applyScale()
	if scaled then return end
	scaled = true
	for _, c in Ops.CLIENTS do c.retainer = math.floor(c.retainer * Ops.B2B_SCALE) end
	for _, st in Ops.STAGES do st.upkeep = math.floor(st.upkeep * Ops.UPKEEP_SCALE) end
end
function Ops.client(id: any): any
	return if typeof(id) == "string" then byId[id] else nil
end
-- catalogue client by its (case-insensitive) name; CityService meeting prompts carry CityPlan's keys
function Ops.clientByName(name: any): any
	if typeof(name) ~= "string" then return nil end
	local want = string.lower(name)
	for _, c in Ops.CLIENTS do if string.lower(c.name) == want then return c end end
	return nil
end

-- clock and time sheet ------------------------------------------------------------------------------
function Ops.hour(clock: number): number
	local s = clock % Ops.DAY
	if s < 900 then return 8 + s / 90 end
	return (18 + (s - 900) / 300 * 14) % 24
end
-- Expected share of a hired team working at `hour` (seed-uniform shifts: start 7.75-9.0, finish 16.5-18.0,
-- lunch start 11.75-13.5 for 1 h, 0.94 for short breaks). Same function on- and offscreen.
function Ops.timesheet(h: number): number
	local started = math.clamp((h - 7.75) / 1.25, 0, 1)
	local notDone = math.clamp((18 - h) / 1.5, 0, 1)
	local lunch = math.max(0, math.min(h, 13.5) - math.max(h - 1, 11.75)) / 1.75
	return started * notDone * (1 - lunch) * 0.94
end
local mean = 0
for s = 0, Ops.DAY - 1 do mean += Ops.timesheet(Ops.hour(s + 0.5)) end
Ops.TS_MEAN = mean / Ops.DAY -- real-time day average (0.5538)
-- multiplier for accruing "stock" outputs (research points, curated tokens): mean over one game day = 1
function Ops.duty(clock: number): number
	return Ops.timesheet(Ops.hour(clock)) / Ops.TS_MEAN
end
function Ops.inOffice(clock: number): boolean
	local h = Ops.hour(clock)
	return h >= 8 and h < 18
end

-- helpers ---------------------------------------------------------------------------------------------
function Ops.stageIndex(e: any): number
	return math.clamp(math.floor(tonumber(e.office) or 1), 1, #Ops.STAGES)
end
function Ops.stage(e: any): any
	return Ops.STAGES[Ops.stageIndex(e)]
end
function Ops.seats(e: any, role: string): number
	return Ops.SEATS[Ops.stageIndex(e)][role] or 0
end
function Ops.day(e: any): number
	local c = e.calendar
	local day = if typeof(c) == "table" then tonumber(c.day) else nil
	return math.max(1, math.floor(day or 1))
end
local function heads(e: any): number
	local n = 0
	if typeof(e.employees) == "table" then for _, k in e.employees do n += tonumber(k) or 0 end end
	return n
end
Ops.heads = heads
function Ops.opsPosts(e: any): number
	local st = Ops.stage(e)
	return st.ops + (if st.guest then Ops.GUEST.staff else 0)
end
-- morale M = clamp(0.90 + 0.10 lunch + 0.03 wellness + 0.02 barista, 0.90, 1.05)
function Ops.morale(e: any): number
	local st = Ops.stage(e)
	local n = heads(e) + Ops.opsPosts(e)
	local lunch = if st.kitchen == 0 then 0.5 else math.min(1, st.kitchen / math.max(1, n * Ops.AVAILABILITY))
	return math.clamp(0.90 + 0.10 * lunch + 0.03 * st.wellness + 0.02 * st.barista, 0.90, 1.05)
end
-- field reps: Growth & Sales heads on field duty (HR assigns as many as the free account slots need);
-- they are the first n profiles of staffProfiles.marketer
function Ops.fieldReps(e: any): number
	local st = Ops.stage(e)
	local need = math.ceil(math.max(0, st.clients - Ops.FOUNDER_ACCOUNTS) / Ops.ACCOUNTS_PER_REP)
	return math.min(tonumber(e.employees and e.employees.marketer) or 0, need)
end

-- staff presence (CORE_SPEC 5.3) -------------------------------------------------------------------------
local function seedOf(p: any, i: number): number
	local s = if typeof(p) == "table" then p.s else nil
	return if typeof(s) == "number" and s == s then math.floor(math.abs(s)) % 2147483647 else i
end
-- sick on company day `day`: 1.7 % of all person-days
function Ops.isSick(seed: number, day: number): boolean
	return EmployeeConfig.hash(seed * 7919 + day) % 1000 < 17
end
-- vacation day (0..11) of each seed in the 12-day cycle `cycle`, after the HR collision shift: at most
-- ceil(0.10 * team) people of a team share a day; the extra people (highest seed first) move to the next
-- day of the cycle with room. Pure function of the team's seeds.
function Ops.vacationDays(seeds: { number }, cycle: number): { [number]: number }
	local order = {}
	for i, s in seeds do table.insert(order, { s = s, i = i }) end
	table.sort(order, function(a: any, b: any): boolean
		if a.s ~= b.s then return a.s < b.s end
		return a.i < b.i
	end)
	local cap = math.max(1, math.ceil(0.10 * #seeds))
	local used: { [number]: number } = {}
	local out: { [number]: number } = {}
	for _, o in order do
		local d = EmployeeConfig.hash(o.s * 31 + cycle) % 12
		for _ = 1, 12 do
			if (used[d] or 0) < cap then break end
			d = (d + 1) % 12
		end
		used[d] = (used[d] or 0) + 1
		out[o.i] = d
	end
	return out
end
-- unpaid leave (safety rule): empire.unpaidLeave = n newest hires; taken one at a time from the role with
-- the most active heads (ties in EmpireConfig.ROLES order), always that role's last profile
function Ops.leaveCounts(e: any): { [string]: number }
	local out: { [string]: number } = {}
	local n = math.max(0, math.floor(tonumber(e.unpaidLeave) or 0))
	local active: { [string]: number } = {}
	for _, r in EmpireConfig.ROLES do out[r.id] = 0; active[r.id] = tonumber(e.employees and e.employees[r.id]) or 0 end
	for _ = 1, n do
		local best: string? = nil
		for _, r in EmpireConfig.ROLES do
			if active[r.id] > 0 and (best == nil or active[r.id] > active[best :: string]) then best = r.id end
		end
		if best == nil then break end
		active[best] -= 1
		out[best] += 1
	end
	return out
end
-- engineers away on region/abroad pilot trips (rep + 1 engineer; they count as absent like vacation)
function Ops.travellers(e: any): { [string]: number }
	local out: { [string]: number } = { engineer = 0 }
	local d = e.deals
	if typeof(d) ~= "table" or typeof(d.tripList) ~= "table" then return out end
	for _, trip in d.tripList do
		local c = if typeof(trip) == "table" then byId[trip.client] else nil
		if c and trip.kind == "sign" and not trip.founder and not trip.hosted and c.trip ~= "city" then out.engineer += 1 end
	end
	return out
end
-- apprentice skill / wage factor of a profile seed on company `day` (nil = not an apprentice)
function Ops.apprentice(e: any, seed: number, day: number): (number?, number?)
	local map = e.apprentices
	if typeof(map) ~= "table" or next(map) == nil then return nil, nil end -- usual case: no string key built
	local entry = map[tostring(seed)]
	if typeof(entry) ~= "table" then return nil, nil end
	local A = Ops.APPRENTICE
	local age = day - (tonumber(entry.day) or day)
	if age >= A.graduateDays then return nil, nil end
	return math.min(A.endSkill, A.startSkill + math.floor(math.max(0, age) / A.rampDays)), A.wage
end
function Ops.apprenticeCount(e: any): number
	local map = e.apprentices
	if typeof(map) ~= "table" then return 0 end
	local n = 0
	for _ in map do n += 1 end
	return n
end
-- Apprentices whose training is over (graduateDays company days) become regular staff: their profile gets
-- skill endSkill and wage factor 1 and the apprentices entry is removed (no new profile fields; CORE_SPEC
-- 11.1). Returns the names of the graduates (EmpireService writes the news line).
function Ops.graduate(e: any): { string }
	local done: { string } = {}
	local map = e.apprentices
	if typeof(map) ~= "table" or next(map) == nil or typeof(e.staffProfiles) ~= "table" then return done end
	local day = Ops.day(e)
	local A = Ops.APPRENTICE
	for _, list in e.staffProfiles do
		if typeof(list) ~= "table" then continue end
		for _, p in list do
			local key = if typeof(p) == "table" and typeof(p.s) == "number" then tostring(p.s) else nil
			local entry = if key then map[key] else nil
			if key and typeof(entry) == "table" and day - (tonumber(entry.day) or day) >= A.graduateDays then
				p.k = A.endSkill
				p.w = 1
				map[key] = nil
				table.insert(done, tostring(p.n))
			end
		end
	end
	return done
end
function Ops.nightOn(e: any, role: string): boolean
	if Ops.stageIndex(e) < Ops.NIGHT.from then return false end
	local d = e.deals
	if typeof(d) == "table" and (tonumber(d.broke) or 0) >= Ops.DAY then return false end -- broke for a day: paused
	local map = e.nightShift
	if typeof(map) ~= "table" then return false end
	for _, dept in Ops.ROLE_DEPTS[role] or {} do if map[dept] == true then return true end end
	return false
end

-- Who of a role is at work today: per profile index i (1..employees[role]) one of "present", "vacation",
-- "sick", "leave" (unpaid), "trip" (travelling engineer). Pure function of saved data.
function Ops.presence(e: any, role: string): { string }
	local n = math.max(0, math.floor(tonumber(e.employees and e.employees[role]) or 0))
	local list = if typeof(e.staffProfiles) == "table" then e.staffProfiles[role] else nil
	local day = Ops.day(e)
	local seeds = {}
	for i = 1, n do seeds[i] = seedOf(if typeof(list) == "table" then list[i] else nil, i) end
	local vac = Ops.vacationDays(seeds, day // 12)
	local leave = Ops.leaveCounts(e)[role] or 0
	local out = {}
	for i = 1, n do
		if i > n - leave then out[i] = "leave"
		elseif vac[i] == day % 12 then out[i] = "vacation"
		elseif Ops.isSick(seeds[i], day) then out[i] = "sick"
		else out[i] = "present" end
	end
	local away = (Ops.travellers(e) :: any)[role] or 0
	for i = n, 1, -1 do
		if away <= 0 then break end
		if out[i] == "present" then out[i] = "trip"; away -= 1 end
	end
	return out
end

-- Department output O_r (CORE_SPEC 5.1) from saved data only:
--   H = sum of f(k) over the people at work today (f = WorkforceMath.factor; apprentices ramp 1 -> 3)
--   O = (min(H, S) + night + 0.5 * rest) * morale,  S = seats of the stage, night = min(H - S, S) with a
--   night shift (stage >= 3), rest = the overflow beyond that. Level outputs use O directly; stock outputs
--   (research points, curated tokens) multiply by duty(clock) where they accrue.
local cache: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
local function signature(e: any): string
	local parts = { tostring(Ops.day(e)), tostring(e.office), tostring(e.unpaidLeave) }
	for _, r in EmpireConfig.ROLES do
		local list = if typeof(e.staffProfiles) == "table" then e.staffProfiles[r.id] else nil
		local last = if typeof(list) == "table" then list[#list] else nil
		table.insert(parts, tostring(e.employees and e.employees[r.id]) .. ":" .. tostring(if typeof(list) == "table" then #list else -1) .. ":" .. tostring(if typeof(last) == "table" then last.s else nil) .. ":" .. tostring(if typeof(last) == "table" then last.k else nil))
	end
	table.insert(parts, tostring(Ops.travellers(e).engineer))
	local appr = 0
	if typeof(e.apprentices) == "table" then for _ in e.apprentices do appr += 1 end end
	table.insert(parts, tostring(appr))
	local night = ""
	if typeof(e.nightShift) == "table" then for _, r in EmpireConfig.ROLES do night ..= if Ops.nightOn(e, r.id) then "1" else "0" end end
	table.insert(parts, night)
	return table.concat(parts, "|")
end
function Ops.output(e: any, role: string): number
	if typeof(e) ~= "table" or typeof(e.employees) ~= "table" then return 0 end
	local sig = signature(e)
	local c = cache[e]
	if c == nil or c.sig ~= sig then
		c = { sig = sig, out = {} }
		cache[e] = c
	end
	local hit = c.out[role]
	if hit ~= nil then return hit end
	local presence = Ops.presence(e, role)
	local list = if typeof(e.staffProfiles) == "table" then e.staffProfiles[role] else nil
	local day = Ops.day(e)
	local H = 0
	for i, state in presence do
		if state == "present" then
			local p = if typeof(list) == "table" then list[i] else nil
			local k = if typeof(p) == "table" then p.k else nil
			local ak = Ops.apprentice(e, seedOf(p, i), day)
			H += Workforce.factor(if ak then ak else k)
		end
	end
	local S = Ops.seats(e, role)
	local over = math.max(0, H - S)
	local night = if Ops.nightOn(e, role) then math.min(over, S) else 0
	local O = (math.min(H, S) + night + 0.5 * (over - night)) * Ops.morale(e)
	c.out[role] = O
	return O
end
-- payroll $ per second of the hired team: profile wage multipliers x role wage; unpaid leave pays nothing,
-- apprentices 40 %, night crew x1.3 (the overflow heads beyond the seats, newest first)
function Ops.wage(e: any): number
	local total = 0
	local day = Ops.day(e)
	local leave = Ops.leaveCounts(e)
	for _, role in EmpireConfig.ROLES do
		local n = math.max(0, math.floor(tonumber(e.employees and e.employees[role.id]) or 0))
		local list = if typeof(e.staffProfiles) == "table" then e.staffProfiles[role.id] else nil
		local paid = n - (leave[role.id] or 0)
		local S = Ops.seats(e, role.id)
		local nightHeads = if Ops.nightOn(e, role.id) then math.min(math.max(0, paid - S), S) else 0
		for i = 1, paid do
			local p = if typeof(list) == "table" then list[i] else nil
			local w = if typeof(p) == "table" and typeof(p.w) == "number" and p.w == p.w then p.w else 1
			local _, aw = Ops.apprentice(e, seedOf(p, i), day)
			if aw then w *= aw end
			if i > paid - nightHeads then w *= Ops.NIGHT.wage end
			total += w * role.wage
		end
	end
	return total
end
-- Growth & Sales in the office (field reps excluded)
function Ops.growthO(e: any): number
	local n = tonumber(e.employees and e.employees.marketer) or 0
	if n <= 0 then return 0 end
	return Workforce.count(e, "marketer") * (n - Ops.fieldReps(e)) / n
end
-- reachable market share of a segment: the stage's maximum, reached only with enough Growth & Sales
-- in the office (marketing, partnerships, support): REACH_BASE + REACH_PER_FTE per working in-office FTE
Ops.REACH_BASE = 0.2
Ops.REACH_PER_FTE = 0.012
function Ops.reachCap(data: any, stageMax: number): number
	return math.min(stageMax, Ops.REACH_BASE + Ops.REACH_PER_FTE * Ops.growthO(data.empire))
end

-- auto-HR (CORE_SPEC 8.1) -------------------------------------------------------------------------------
-- "department need" (HR never hires past it; the assistant says "at full effect"):
--   researchers: their desks while research or Lab levels are open, afterwards RESEARCH_AFTER of them;
--   Growth & Sales: the field reps the client slots need + max(GROWTH_OFFICE_MAX, heads that reach the
--   stage's reach cap) in the office; engineers and curators: their desks.
Ops.GROWTH_OFFICE_MAX = 24
Ops.RESEARCH_AFTER = 0.25
Ops.LAB_MAX = 10
function Ops.researchOpen(e: any): boolean
	if (tonumber(e.labLevel) or 0) < Ops.LAB_MAX then return true end
	local done = if typeof(e.research) == "table" then e.research else {}
	for _, def in EmpireConfig.RESEARCH do if not done[def.id] then return true end end
	return false
end
-- Lab levels (CORE_SPEC 7.5): level L -> L + 1 costs floor(200 * 1.35^L) research points and
-- $floor(6000 * 1.6^L); +1 core stat on future models each, at most LAB_MAX levels
function Ops.labCost(level: number): (number, number)
	return math.floor(200 * 1.35 ^ level), math.floor(6000 * 1.6 ^ level)
end
function Ops.hrNeed(e: any, role: string): number
	local seats = Ops.seats(e, role)
	if role == "researcher" then return if Ops.researchOpen(e) then seats else math.ceil(seats * Ops.RESEARCH_AFTER) end
	if role == "marketer" then
		local st = Ops.stage(e)
		local field = math.ceil(math.max(0, st.clients - Ops.FOUNDER_ACCOUNTS) / Ops.ACCOUNTS_PER_REP)
		local stageMax = (MarketConfig.STAGE_REACH or {})[Ops.stageIndex(e)] or 0.9
		local reachHeads = math.ceil(math.max(0, stageMax - Ops.REACH_BASE) / Ops.REACH_PER_FTE / (Ops.AVAILABILITY * Ops.morale(e)))
		return math.min(seats, field + math.max(Ops.GROWTH_OFFICE_MAX, reachHeads))
	end
	return seats
end
-- the department with the lowest heads / need below its need (EmpireConfig.ROLES order breaks ties)
Ops.HR_ORDER = { "engineer", "curator", "researcher", "marketer" }
function Ops.hrPick(e: any): string?
	local best, bestRatio = nil, math.huge
	for _, id in Ops.HR_ORDER do
		local need = Ops.hrNeed(e, id)
		local n = tonumber(e.employees and e.employees[id]) or 0
		local ratio = n / math.max(1, need)
		if n < need and ratio < bestRatio - 1e-9 then best = id; bestRatio = ratio end
	end
	return best
end
function Ops.hrSettings(e: any): (boolean, number)
	local hr = if typeof(e.hr) == "table" then e.hr else {}
	local budget = tonumber(hr.budget) or 0.40
	return hr.auto ~= false, budget
end
-- cash kept back by automation: max($1,500, 2 minutes of payroll)
function Ops.reserve(e: any): number
	return math.max(1500, Ops.wage(e) * 120)
end
-- daily payroll of hired (all, incl. unpaid leave) + operations staff: the unpaid-leave thresholds
function Ops.dailyPayroll(e: any): number
	local hired = 0
	for _, role in EmpireConfig.ROLES do
		local n = math.max(0, math.floor(tonumber(e.employees and e.employees[role.id]) or 0))
		local list = if typeof(e.staffProfiles) == "table" then e.staffProfiles[role.id] else nil
		for i = 1, n do
			local p = if typeof(list) == "table" then list[i] else nil
			hired += (if typeof(p) == "table" and typeof(p.w) == "number" and p.w == p.w then p.w else 1) * role.wage
		end
	end
	return hired * Ops.DAY + Ops.opsPosts(e) * Ops.OPS_WAGE
end
-- Save mode (auto): the next office is less than SAVE_MINUTES of net profit away; off in the garage until
-- the first client signed. netPerSecond = live revenue - live cost.
function Ops.saveMode(e: any, money: number, netPerSecond: number): boolean
	if e.saveMode == "off" then return false end
	local nextDef = EmpireConfig.OFFICES[Ops.stageIndex(e) + 1]
	if not nextDef then return false end
	if Ops.stageIndex(e) == 1 and (tonumber(e.contractsCompleted) or 0) < 1 then return false end
	local net = netPerSecond * 60
	return net > 0 and (nextDef.price + Ops.reserve(e) * 2 - money) / net < Ops.SAVE_MINUTES
end
-- may HR hire one more `role` person now? payroll (hired + ops) after the hire <= budget x trailing income;
-- the first HR_STARTERS hires always; Save mode stops HR at half the desks; never while broke or on leave
function Ops.hrAllowed(e: any, money: number, income: number, saving: boolean, roleId: string): boolean
	local role = EmpireConfig.find(EmpireConfig.ROLES, roleId)
	if not role then return false end
	local _, budget = Ops.hrSettings(e)
	local staff = heads(e)
	local def = EmpireConfig.OFFICES[Ops.stageIndex(e)]
	local cap = if def then def.staff else 0
	if staff >= cap then return false end
	if money < 0 or (tonumber(e.unpaidLeave) or 0) > 0 then return false end
	if saving and staff >= cap * 0.5 then return false end
	if staff < Ops.HR_STARTERS then return true end
	local payroll = Ops.wage(e) + Ops.opsPosts(e) * Ops.OPS_WAGE / Ops.DAY
	return payroll + role.wage <= budget * math.max(0, income)
end

-- serving capacity, compute, rack faults ----------------------------------------------------------------
local faultState: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
-- rack GPUs in blade order (PlotService lights blades best GPU first): { {slot, gpu id, throughput} }
function Ops.rack(gpus: any): { any }
	local out = {}
	for i = #HardwareConfig.GPUS, 1, -1 do
		local g = HardwareConfig.GPUS[i]
		if not g.starter then
			for _ = 1, math.max(0, math.floor(tonumber(gpus and gpus[g.id]) or 0)) do table.insert(out, { slot = #out + 1, gpu = g.id, throughput = g.throughput }) end
		end
	end
	return out
end
-- throughput currently off line because of rack faults
function Ops.faultLoss(e: any): number
	local st = faultState[e]
	if not st then return 0 end
	local lost = 0
	for _, f in st.list do lost += f.throughput end
	return lost
end
function Ops.faults(e: any): { any }
	local st = faultState[e]
	return if st then st.list else {}
end
function Ops.itOnDuty(e: any, clock: number): boolean
	local stage = Ops.stageIndex(e)
	if stage < 2 then return false end -- the garage has no IT post
	return Ops.inOffice(clock) or stage >= 5 -- IT works the day shift; from stage 5 an IT engineer is on call at night
end
function Ops.hwlabStaffed(e: any): boolean
	return Ops.stageIndex(e) >= 4 and (tonumber(e.employees and e.employees.engineer) or 0) >= Ops.seats(e, "engineer") * 0.5
end
-- one fault step (EmpireService.tick via Ops.step): repair running faults, roll new ones once per minute
-- of play. seedKey = a number identifying the company (its user id). Returns true when the list changed.
function Ops.faultStep(e: any, gpus: any, seedKey: number, dt: number, clock: number): boolean
	local st = faultState[e]
	if not st then st = { list = {}, minute = nil }; faultState[e] = st end
	local changed = false
	local rack = Ops.rack(gpus)
	local F = Ops.FAULT
	local rate = if Ops.itOnDuty(e, clock) then 1 / F.it else 1 / F.alone
	local keep = {}
	for _, f in st.list do
		f.left -= dt * rate
		local still = rack[f.slot]
		if f.left > 0 and still and still.gpu == f.gpu then table.insert(keep, f) else changed = true end
	end
	st.list = keep
	local minute = math.floor((tonumber(e.seconds) or 0) / F.every)
	if st.minute == nil then st.minute = minute end
	if minute ~= st.minute then
		st.minute = minute
		local p = F.rate * F.every / Ops.DAY * (if Ops.hwlabStaffed(e) then F.hwlab else 1)
		local base = math.floor(math.abs(seedKey)) % 2147483647
		for _, r in rack do
			local broken = false
			for _, f in st.list do if f.slot == r.slot then broken = true end end
			if not broken and EmployeeConfig.hash(base + minute * 131 + r.slot * 7919) % 1000000 < p * 1000000 then
				table.insert(st.list, { slot = r.slot, gpu = r.gpu, throughput = math.min(F.units, r.throughput), left = 1, since = tonumber(e.seconds) or 0 })
				changed = true
			end
		end
	end
	return changed
end
-- serving capacity in users (consumer market), after B2B reservations and rack faults
function Ops.capacity(data: any): number
	local e = data.empire
	local fleet = ModelMath.fleet(data.gpus)
	local throughput = math.max(0, fleet.throughput - Ops.faultLoss(e))
	local thermal = HardwareConfig.thermal(e, fleet.throughput)
	local reserved = (typeof(e.deals) == "table" and tonumber(e.deals.reserved)) or 0
	local eng = 1 + Ops.ENG_CAP * (1 - math.exp(-Workforce.count(e, "engineer") / Ops.ENG_K))
	return math.max(0, throughput * thermal - reserved) * Ops.CAP_PER_UNIT * eng
end
-- buy the company jet (EmpireAction "buyJet"): stage >= JET.stage, paid at once
function Ops.buyJet(session: any, Economy: any): any
	local e = session.data.empire
	if e.jet == true then return { ok = false, err = "OWNED" } end
	if Ops.stageIndex(e) < Ops.JET.stage then return { ok = false, err = "OFFICE" } end
	if not Economy.spend(session, Ops.JET.price, "jetbuy") then return { ok = false, err = "NO_MONEY" } end
	e.jet = true
	return { ok = true }
end

-- calendar ----------------------------------------------------------------------------------------------
-- company date: day + 1 whenever the server day index floor(clock / DAY) changes while the company is online
function Ops.advanceCalendar(e: any, clock: number): number
	local c = e.calendar
	if typeof(c) ~= "table" then c = { day = 1 }; e.calendar = c end
	local index = math.floor(clock / Ops.DAY)
	if typeof(c.index) ~= "number" then c.index = index end
	if index ~= c.index then c.day = Ops.day(e) + 1; c.index = index end
	return c.day
end
function Ops.stamp(e: any, clock: number): string
	local h = Ops.hour(clock)
	return string.format("day %d %02d:%02d", Ops.day(e), math.floor(h), math.floor((h % 1) * 60))
end
local function money(n: number): string
	local text = tostring(math.floor(math.abs(n) + 0.5))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	if string.sub(formatted, 1, 1) == "," then formatted = string.sub(formatted, 2) end
	return (if n < 0 then "-$" else "$") .. formatted
end
Ops.money = money

-- trips -------------------------------------------------------------------------------------------------
-- duration (s), hotel nights per traveller, cost of a trip; hosted = client comes to the guest house
function Ops.tripPlan(kind: string, crew: number, hosted: boolean, jet: boolean?): (number, number, number)
	local t = Ops.TRIPS[kind] or Ops.TRIPS.city
	if hosted then
		local h = Ops.HOSTED
		return Ops.DAY, 0, h.guests * h.nights * h.nightCost
	end
	if jet and kind == "abroad" then
		local J = Ops.JET
		local cost = J.fuel + crew * (J.nights * t.hotel + math.ceil(J.days) * Ops.PER_DIEM)
		return J.days * Ops.DAY, J.nights, cost
	end
	local days = math.max(1, math.ceil(t.days))
	local cost = t.fuel + crew * (t.flight + t.nights * t.hotel + days * Ops.PER_DIEM)
	return t.days * Ops.DAY, t.nights, cost
end
local NUMBERS = { "signed", "lost", "nights", "trips", "reserved", "pilots", "hosted", "flights", "jetFlights", "broke" }
function Ops.newDeals(): any
	local d: any = { accounts = {}, trust = {}, tripList = {}, news = {}, skip = {} }
	for _, k in NUMBERS do d[k] = 0 end
	return d
end
-- type repair of empire.deals (Template.migrate does the value checks)
function Ops.ensure(e: any): any
	local d = e.deals
	if typeof(d) ~= "table" then d = Ops.newDeals(); e.deals = d end
	for _, k in { "accounts", "trust", "tripList", "news", "skip" } do if typeof(d[k]) ~= "table" then d[k] = {} end end
	for _, k in NUMBERS do
		local v = tonumber(d[k])
		d[k] = if v and v == v and v > -math.huge and v < math.huge then math.max(0, v) else 0
	end
	if d.pinned ~= nil and not byId[d.pinned] then d.pinned = nil end
	return d
end
-- First `n` bytes of `s`, cut on a UTF-8 character boundary (a cut never splits a multi-byte character:
-- saves must stay valid UTF-8 for the DataStore and the client's text labels).
function Ops.clip(s: string, n: number): string
	if #s <= n then return s end
	local cut = math.max(0, math.floor(n))
	while cut > 0 do
		local b = string.byte(s, cut + 1)
		if b == nil or b < 0x80 or b >= 0xC0 then break end -- next byte starts a character: the cut is clean
		cut -= 1
	end
	return string.sub(s, 1, cut)
end
-- One line in the company log (newest first, <= NEWS_MAX lines of <= NEWS_CHARS bytes). stamp = this
-- company's "day 8 11:54" (Ops.stamp); Ops.post computes it from the company itself.
function Ops.news(d: any, text: string, stamp: string?)
	local line = if stamp and stamp ~= "" then stamp .. ": " .. text else text
	table.insert(d.news, 1, Ops.clip(line, Ops.NEWS_CHARS))
	while #d.news > Ops.NEWS_MAX do table.remove(d.news) end
end
-- News written outside Ops.step (remote handlers, HR, pricing, model releases): stamped with the company's
-- own calendar day and the visible server clock (never another company's day).
function Ops.post(e: any, text: string, clock: number?)
	local d = Ops.ensure(e)
	Ops.news(d, text, Ops.stamp(e, clock or workspace:GetServerTimeNow()))
end
local function liveBest(data: any, stat: string): (number, any)
	local best, model = 0, nil
	for _, id in data.modelOrder or {} do
		local m = data.models[id]
		if m and m.status == "live" and m.stats and (m.stats[stat] or 0) > best then best = m.stats[stat] or 0; model = m end
	end
	return best, model
end
Ops.liveBest = liveBest
local function repSkill(e: any): number
	local list = typeof(e.staffProfiles) == "table" and e.staffProfiles.marketer or nil
	local n = Ops.fieldReps(e)
	if typeof(list) ~= "table" or n == 0 then return 3 end
	local sum, c = 0, 0
	for i = 1, math.min(n, #list) do sum += Workforce.skill(list[i] and list[i].k); c += 1 end
	return if c > 0 then sum / c else 3
end
-- trust gained on one visit (shown as "trust 67 %"): deterministic, no dice
function Ops.trustGain(e: any, data: any, c: any, hosted: boolean, founder: boolean, joined: boolean?): number
	local best = liveBest(data, c.stat)
	local skill = if founder then 3 else repSkill(e)
	local d = Ops.ensure(e)
	local first = if c.first and d.signed == 0 then Ops.FIRST_CLIENT_TRUST else 0
	local jet = if c.trip == "abroad" and not hosted and e.jet == true then Ops.JET.trust else 0
	local meet = if joined then Ops.MEETING_TRUST else 0
	return math.clamp(0.5 + 0.025 * (best - c.minimum) + 0.05 * (skill - 3) + (if hosted then Ops.HOSTED.trust else 0) + first + jet + meet, 0.35, 1)
end
local function eligible(e: any, data: any, c: any): boolean
	local st = Ops.stage(e)
	return Ops.stageIndex(e) >= c.stage and TIER[c.trip] <= TIER[st.trips] and liveBest(data, c.stat) >= c.minimum
end
Ops.eligible = eligible
-- free account slots: min(stage slots, founder accounts + 2 per field rep)
function Ops.accountLimit(e: any): number
	return math.min(Ops.stage(e).clients, Ops.FOUNDER_ACCOUNTS + Ops.ACCOUNTS_PER_REP * Ops.fieldReps(e))
end
-- token capacity for B2B retainers (M tokens per billing month): throughput x 100 x thermal
function Ops.tokenCap(data: any): number
	local fleet = ModelMath.fleet(data.gpus)
	return fleet.throughput * 100 * HardwareConfig.thermal(data.empire, fleet.throughput)
end
-- hosted client teams staying at the guest house right now
function Ops.hostedInHouse(e: any): number
	local d = e.deals
	local n = 0
	if typeof(d) == "table" and typeof(d.tripList) == "table" then for _, t in d.tripList do if typeof(t) == "table" and t.hosted == true then n += 1 end end end
	return n
end
function Ops.hotelGuests(e: any): number
	local g = Ops.GUEST
	return math.floor(g.rooms * g.occupancy + 0.5) + Ops.HOSTED.guests * Ops.hostedInHouse(e)
end

-- safety rules (CORE_SPEC 8.3) ----------------------------------------------------------------------------
-- broke: seconds of continuous negative cash (>= 1 day pauses trips and night crews);
-- unpaid leave: cash < -2 x daily payroll -> one more newest hire on unpaid leave per HIRE_GAP seconds while
-- the net flow is negative; cash > 1 x daily payroll -> everybody back.
local leaveClock: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any
function Ops.safety(e: any, cash: number, netPerSecond: number, dt: number): boolean
	local d = Ops.ensure(e)
	d.broke = if cash < 0 then d.broke + dt else 0
	local daily = Ops.dailyPayroll(e)
	local leave = math.max(0, math.floor(tonumber(e.unpaidLeave) or 0))
	local changed = false
	if leave > 0 and cash > daily then
		e.unpaidLeave = 0
		changed = true
	elseif cash < -2 * daily and netPerSecond < 0 and leave < heads(e) then
		local t = (leaveClock[e] or 0) + dt
		if t >= Ops.HIRE_GAP or leave == 0 then
			t = 0
			e.unpaidLeave = leave + 1
			changed = true
		end
		leaveClock[e] = t
	end
	return changed
end

-- one simulation step (EmpireService.tick, after wages). Economy = EconomyService (spend / applyFlow).
function Ops.step(session: any, dt: number, Economy: any, clock: number)
	Ops.applyScale()
	local data = session.data
	local e = data.empire
	local live = session.live
	local d = Ops.ensure(e)
	local now = tonumber(e.seconds) or 0
	Ops.advanceCalendar(e, clock)
	local stamp = Ops.stamp(e, clock) -- this company's day and the visible hour (per company, never shared)
	local function news(log: any, text: string)
		Ops.news(log, text, stamp)
	end
	local st = Ops.stage(e)
	local tokenCap = Ops.tokenCap(data)
	local inc: { [string]: number } = { b2b = 0, guest = 0 }
	local out: { [string]: number } = { b2bserve = 0, fleet = 0, ops = 0, upkeep = 0, food = 0, guest = 0, jet = 0 }
	local oneIn: { [string]: number } = {}
	local oneOut: { [string]: number } = {}
	local reps = Ops.fieldReps(e)
	local limit = Ops.accountLimit(e)
	local function accountCount(): number
		local n = 0
		for _ in d.accounts do n += 1 end
		return n
	end
	-- (times in accounts / trips are whole play seconds: small saves and snapshots, CORE_SPEC 11.8)
	-- 1. trips that are back
	local still = {}
	for _, trip in d.tripList do
		local c = if typeof(trip) == "table" then byId[trip.client] else nil
		if not c then continue end
		if now < (tonumber(trip.back) or 0) then table.insert(still, trip); continue end
		if trip.kind == "renew" then
			local acc = d.accounts[c.id]
			if acc then acc.expires = math.floor(math.max(acc.expires, now) + Ops.TERM_DAYS * Ops.DAY + 0.5); acc.renewing = nil; news(d, "renewed " .. c.name .. " for " .. Ops.TERM_DAYS .. " days") end
		elseif eligible(e, data, c) and not d.accounts[c.id] then
			d.trust[c.id] = (tonumber(d.trust[c.id]) or 0) + Ops.trustGain(e, data, c, trip.hosted == true, trip.founder == true, trip.joined == true)
			if d.trust[c.id] >= 1 and accountCount() < limit then
				d.trust[c.id] = nil
				d.accounts[c.id] = { expires = math.floor(now + Ops.TERM_DAYS * Ops.DAY + 0.5), since = math.floor(now), founder = if trip.founder == true then true else nil }
				d.signed += 1
				e.contractsCompleted = (tonumber(e.contractsCompleted) or 0) + 1
				if data.company then data.company.reputation = math.min(100, data.company.reputation + 1.5) end
				oneIn.pilot = (oneIn.pilot or 0) + c.retainer * Ops.PILOT_DAYS
				news(d, string.format("signed %s: pilot %s, %s/day", c.name, money(c.retainer * Ops.PILOT_DAYS), money(c.retainer)))
			else
				news(d, string.format("visited %s: trust %d%%", c.name, math.floor(math.min(1, d.trust[c.id] or 0) * 100)))
			end
		end
	end
	d.tripList = still
	-- 2. active retainers
	local used = 0
	local function busyOn(id: string): boolean
		for _, trip in d.tripList do if trip.client == id then return true end end
		return false
	end
	for _, c in Ops.CLIENTS do
		local acc = d.accounts[c.id]
		if acc then
			local term = acc.expires > now or acc.renewing == true
			local best, m = liveBest(data, c.stat)
			local ok = term and Ops.stageIndex(e) >= c.stage and best >= c.minimum and used + c.tokens <= tokenCap
			if ok then
				used += c.tokens
				inc.b2b += c.retainer / Ops.DAY
				local size = m and ModelConfig.getSize(m.sizeId)
				out.b2bserve += c.tokens * (if size then size.serveCost else 0) / Ops.MONTH
			else
				d.accounts[c.id] = nil
				d.lost += 1
				local why = if not term then "no check-in before the term ended"
					elseif best < c.minimum then string.format("needs %s %d, best live %d", c.stat, c.minimum, math.floor(best))
					else "not enough server capacity"
				news(d, "lost " .. c.name .. " (" .. why .. ")")
			end
		end
	end
	d.reserved = used / 100
	-- 3. free sellers start trips: renewals first, then a pinned client, then the most valuable open client.
	--    Founder: city only, one trip at a time, may hold FOUNDER_ACCOUNTS accounts.
	--    The scripted first pilot (CloudDesk) ignores the departure window.
	local office = Ops.hour(clock) >= Ops.DEPART.from and Ops.hour(clock) < Ops.DEPART.to
	local founderBusy, repTrips = false, 0
	for _, trip in d.tripList do if trip.founder then founderBusy = true else repTrips += 1 end end
	local freeReps = reps - repTrips
	local cashOk = data.money >= 0 and d.broke < Ops.DAY
	-- trip costs are booked after the loop below: every start checks the cash still uncommitted in this step,
	-- so several reps leaving together can never take the company below CASH_MARGIN (CORE_SPEC 8.3)
	local committed = 0
	local function openFor(c: any, founder: boolean): boolean
		if founder and c.trip ~= "city" then return false end
		return not d.accounts[c.id] and not busyOn(c.id) and not d.skip[c.id] and eligible(e, data, c) and used + c.tokens <= tokenCap
	end
	local function pickFor(founder: boolean): (any, string?)
		for _, c in Ops.CLIENTS do
			local acc = d.accounts[c.id]
			if acc and not acc.renewing and (acc.founder == true) == founder and acc.expires - now < (Ops.TRIPS[c.trip].days + Ops.RENEW_LEAD_DAYS) * Ops.DAY then return c, "renew" end
		end
		local pending = 0
		for _, trip in d.tripList do if trip.kind == "sign" then pending += 1 end end
		if accountCount() + pending >= limit then return nil, nil end
		if founder then
			local fa = 0
			for _, acc in d.accounts do if acc.founder then fa += 1 end end
			for _, trip in d.tripList do if trip.founder and trip.kind == "sign" then fa += 1 end end
			if fa >= Ops.FOUNDER_ACCOUNTS then return nil, nil end
			-- the scripted first pilot: "your friend at CloudDesk" is always the first client visited
			if d.signed == 0 then
				for _, c in Ops.CLIENTS do
					if c.first and not d.accounts[c.id] and not busyOn(c.id) and eligible(e, data, c) then return c, "sign" end
				end
			end
		end
		local pinned = byId[d.pinned or ""]
		if pinned and openFor(pinned, founder) then return pinned, "sign" end
		for k = #Ops.CLIENTS, 1, -1 do
			local c = Ops.CLIENTS[k]
			if openFor(c, founder) then return c, "sign" end
		end
		return nil, nil
	end
	local function start(c: any, kind: string, founder: boolean): boolean
		local hosted = false
		if kind == "sign" and not founder and st.guest and c.trip ~= "city" then
			hosted = (d.pilots % 2) == 1 -- every second region/abroad pilot is hosted at the guest house
		end
		local crew = if kind == "renew" or founder then 1 else Ops.TRIPS[c.trip].crew
		local jet = e.jet == true
		local duration, nights, cost = Ops.tripPlan(c.trip, crew, hosted, jet)
		if data.money - committed < cost + Ops.CASH_MARGIN then return false end
		committed += cost
		oneOut.trips = (oneOut.trips or 0) + cost
		if not hosted then
			d.nights += crew * nights
			if c.trip == "abroad" then if jet then d.jetFlights += 1 else d.flights += crew end end
		else
			d.hosted += 1
		end
		if kind == "sign" and c.trip ~= "city" and not founder then d.pilots += 1 end
		d.trips += 1
		if kind == "renew" then d.accounts[c.id].renewing = true end
		table.insert(d.tripList, { client = c.id, kind = kind, back = math.floor(now + duration + 0.5), founder = founder, hosted = hosted, crew = if hosted then 0 else crew, left = math.floor(now) })
		local what = if kind == "renew" then "check-in" else "pilot"
		if founder then
			news(d, string.format("founder drives to %s: %s, %s", c.name, what, money(cost)))
		elseif hosted then
			news(d, string.format("hosting %s at the guest house: %s, %s", c.name, what, money(cost)))
		else
			local how = if c.trip == "abroad" then (if jet then "jet" else "flight") .. " + " .. nights .. (if nights == 1 then " night" else " nights")
				elseif c.trip == "region" then "City Hotel night"
				else "car"
			news(d, string.format("rep to %s: %s, %s, %s", c.name, what, how, money(cost)))
		end
		return true
	end
	if cashOk and not founderBusy then
		local c, kind = pickFor(true)
		if c and kind and (office or (c.first and d.signed == 0)) then if start(c, kind, true) then founderBusy = true end end
	end
	while cashOk and office and freeReps > 0 do
		local c, kind = pickFor(false)
		if not c or not kind then break end
		if not start(c, kind, false) then break end
		freeReps -= 1
	end
	-- 4. running costs
	local posts = Ops.opsPosts(e)
	local stageIdx = Ops.stageIndex(e)
	local drivers = if stageIdx >= Ops.DRIVER.more then 2 elseif stageIdx >= Ops.DRIVER.from then 1 else 0
	-- the Training Lead is paid while there are apprentices to train (stage >= 3)
	local lead = if stageIdx >= Ops.TRAINING_LEAD.from and Ops.apprenticeCount(e) > 0 then Ops.TRAINING_LEAD.wage else 0
	local staff = heads(e)
	out.fleet = reps * Ops.FLEET_LEASE / Ops.DAY
	out.ops = ((posts + drivers) * Ops.OPS_WAGE + lead + (staff + posts) * Ops.PHONE) / Ops.DAY
	out.upkeep = st.upkeep / Ops.DAY
	if e.jet == true then out.jet = (Ops.JET.pilots * Ops.JET.pilotWage + Ops.JET.upkeep) / Ops.DAY end
	out.food = (staff + posts) * Ops.AVAILABILITY * st.food / Ops.DAY
	if st.guest then
		local g = Ops.GUEST
		inc.guest = g.rooms * g.occupancy * g.rate / Ops.DAY
		out.guest = g.utilities / Ops.DAY
	end
	-- 5. book everything through EconomyService (4th argument = ledger category)
	local summary: { [string]: any } = {}
	for cat, r in inc do
		if r > 0 then Economy.applyFlow(session, r * dt, 0, cat); live.revenue += r end
		summary[cat] = math.floor(r * 60 + 0.5)
	end
	for cat, c in out do
		if c > 0 then Economy.applyFlow(session, 0, c * dt, cat); live.cost += c end
		summary[cat .. "Cost"] = math.floor(c * 60 + 0.5)
	end
	for cat, amount in oneIn do Economy.applyFlow(session, amount, 0, cat) end
	for cat, amount in oneOut do Economy.applyFlow(session, 0, amount, cat) end
	-- 6. safety rules (broke pause, unpaid leave)
	local wasBroke = d.broke >= Ops.DAY
	if Ops.safety(e, data.money, (live.revenue or 0) - (live.cost or 0), dt) then
		local n = math.floor(tonumber(e.unpaidLeave) or 0)
		news(d, if n > 0 then string.format("cash below -%s: %d newest hires on unpaid leave", money(2 * Ops.dailyPayroll(e)), n) else "cash recovered: everybody is back from unpaid leave")
	end
	if not wasBroke and d.broke >= Ops.DAY then news(d, "cash below $0 for a whole day: trips and night shifts paused") end
	-- 7. what later visuals and the phone need (session.live.ops: replicated lazily)
	local trips = {}
	for _, trip in d.tripList do
		local c = byId[trip.client]
		table.insert(trips, { client = trip.client, name = c and c.name, kind = trip.kind, tier = c and c.trip, back = math.floor(trip.back), founder = trip.founder == true, hosted = trip.hosted == true, crew = trip.crew or 1 })
	end
	summary.accounts = accountCount()
	summary.limit = limit
	summary.slots = st.clients
	summary.travelling = #d.tripList
	summary.trips = trips
	summary.reps = reps
	summary.ops = posts
	summary.drivers = drivers
	summary.guests = if st.guest then Ops.hotelGuests(e) else 0
	summary.day = Ops.day(e)
	summary.paused = d.broke >= Ops.DAY
	live.ops = summary
end
return Ops
