--!strict
local Config = require(script.Parent.Config.EmpireConfig)
local ModelMath = require(script.Parent.ModelMath)
local HardwareConfig = require(script.Parent.Config.HardwareConfig)
local ModelConfig = require(script.Parent.Config.ModelConfig)
local CampusMath=require(script.Parent.CampusMath)
local Workforce=require(script.Parent.WorkforceMath)
local Employee=require(script.Parent.Config.EmployeeConfig)
local Ops=require(script.Parent.CompanyOps)
local MarketConfig=require(script.Parent.Config.MarketConfig)
local Math = {}
Math.MAX_APPLICANTS = 5 -- open job applications at once (RecruitingService)
Math.APPLICATION_SECONDS = 1800 -- an application nobody invited stays open this long (play time, empire.seconds)
function Math.new(): any
	return { campus = CampusMath.new(), office = 1, employees = {}, research = {}, points = 25, researchJob = nil,
		quests = {}, contracts = {}, contractsCompleted = 0, xp = 0, seconds = 0,
		daily = { day = -1, streak = 0 }, lastSeen = 0, history = {}, historyClock = 0, subscriptions = {}, invoices = {}, customers = {}, businessRevenue = 0, projects = {}, projectOrder = {}, projectJob = nil, deliveries = {}, arenaHistory = {}, arenaBest = 0, infrastructure = {cooling=1,trainingShare=0.7},
		staffProfiles = {}, applicants = {}, hireSerial = 0,
		-- CORE_SPEC Appendix A (DATA_VERSION 6): company calendar, B2B pipeline, Lab levels, jet, auto-HR,
		-- Save mode, night shifts, apprentices, unpaid leave, P&L ledger (Template.migrate cleans them)
		calendar = { day = 1 }, deals = Ops.newDeals(), labLevel = 0, jet = false, hr = { auto = true, budget = 0.40 },
		saveMode = "auto", nightShift = {}, apprentices = {}, unpaidLeave = 0, ledger = {} }
end
-- Persistent staff identities: staffProfiles[roleId][i] = {n = name, s = appearance seed,
-- k = skill 1..5, w = wage multiplier} for the i-th hired person of that role (StaffAssignment builds
-- rig i of the role from it). Invariant: #staffProfiles[role] == employees[role].
-- syncProfiles repairs any save to that invariant without changing what the building shows today:
-- a missing name/seed becomes exactly the generated identity StaffAssignment/EmployeeRigDesign use
-- for that person now (global index over EmpireConfig.ROLES order, CampusMath.staffName and
-- EmployeeConfig.seed); missing k = 3 and w = 1 keep the old economy. owner = nil (Template.migrate
-- has no user id) only cleans and truncates; names/seeds are filled once the session knows its owner.
local function cleanProfile(raw: any): any
	local p: any = if typeof(raw) == "table" then raw else {}
	local n, s, k, w = p.n, p.s, p.k, p.w
	return {
		n = if typeof(n) == "string" and string.match(n, "%S") then string.sub(n, 1, 40) else nil,
		s = if typeof(s) == "number" and s == s and math.abs(s) < 1e15 then math.floor(math.abs(s)) % 2147483647 else nil,
		k = Workforce.skill(k),
		w = if typeof(w) == "number" and w == w and w > -math.huge and w < math.huge then math.clamp(w, 0.5, 2) else 1,
	}
end
function Math.profilesConsistent(e: any): boolean
	local profiles = e.staffProfiles
	if typeof(profiles) ~= "table" then return false end
	for _, role in Config.ROLES do
		local list = profiles[role.id]
		local n = e.employees[role.id] or 0
		if typeof(list) ~= "table" or #list ~= n then return false end
		for i = 1, n do
			local p = list[i]
			if typeof(p) ~= "table" or typeof(p.n) ~= "string" or typeof(p.s) ~= "number" or typeof(p.k) ~= "number" or typeof(p.w) ~= "number" then return false end
		end
	end
	return true
end
function Math.syncProfiles(e: any, owner: number?)
	local profiles = if typeof(e.staffProfiles) == "table" then e.staffProfiles else {}
	local clean = {}
	local index = 0
	for _, role in Config.ROLES do
		local list = profiles[role.id]
		local out = {}
		for i = 1, e.employees[role.id] or 0 do
			index += 1
			local p = cleanProfile(if typeof(list) == "table" then list[i] else nil)
			if owner then
				if p.n == nil then p.n = CampusMath.staffName(index, owner) end
				if p.s == nil then p.s = Employee.seed(index, owner) end
			end
			out[i] = p
		end
		clean[role.id] = out
	end
	e.staffProfiles = clean
end
-- Σ wage multipliers of the hired people of a role (old saves: exactly the hired count).
function Math.payroll(e: any, roleId: string): number
	local n = e.employees[roleId] or 0
	local list = if typeof(e.staffProfiles) == "table" then e.staffProfiles[roleId] else nil
	if typeof(list) ~= "table" then return n end
	local total = 0
	for i = 1, n do
		local p = list[i]
		local w = if typeof(p) == "table" then p.w else nil
		total += if typeof(w) == "number" and w == w then w else 1
	end
	return total
end
-- Fresh persistent identity for a new hire or applicant: appearance seed from (owner, hireSerial),
-- name from that seed (presentation consistent with EmployeeConfig.feminine(seed), ~50 % women).
-- Names stay unique within the company (team + open applicants). Advances e.hireSerial.
function Math.nextIdentity(e: any, owner: number): (string, number, number)
	local used: { [string]: boolean } = {}
	if typeof(e.staffProfiles) == "table" then
		for _, list in e.staffProfiles do
			if typeof(list) == "table" then for _, p in list do if typeof(p) == "table" and typeof(p.n) == "string" then used[p.n] = true end end end
		end
	end
	if typeof(e.applicants) == "table" then
		for _, a in e.applicants do if typeof(a) == "table" and typeof(a.n) == "string" then used[a.n] = true end end
	end
	local base = Employee.hash(math.floor(math.abs(owner)) % 4294967296 + 0x5bd1e995)
	local serial, seed, name = 0, 0, ""
	for _ = 1, 64 do
		e.hireSerial = math.max(0, math.floor(tonumber(e.hireSerial) or 0)) + 1
		serial = e.hireSerial
		seed = Employee.hash((base + serial * 0x9e3779b9) % 4294967296) % 2147483647
		name = CampusMath.nameForSeed(seed)
		if not used[name] then break end
	end
	return name, seed, serial
end
function Math.staff(e: any): number
	local n = 0
	for _, def in Config.ROLES do n += e.employees[def.id] or 0 end
	return n
end
-- Flat agency fee (CORE_SPEC 4): about a third of a day's wage, the same for every hire.
function Math.hireCost(_e: any, role: any): number
	return math.floor(role.price)
end
-- Department outputs O_r (WorkforceMath.count = CompanyOps.output, CORE_SPEC 5.1) drive every bonus:
--   engineers: training speed 1 + 0.15 O, serving cost x (1 - 0.2 (1 - e^(-O/10)))
--   researchers: research points/s base(stage) + 0.6 O (x duty where it accrues), core-stat bonus
--     floor(50 (1 - e^(-O/10))) / 10 (<= +5) on new models, + Lab level
--   Growth & Sales in the office (field reps excluded): revenue x (1 + 0.4 (1 - e^(-O_g/10)))
-- wage = hired payroll $/s (CompanyOps.wage: profile multipliers, unpaid leave, apprentices, night crew).
function Math.bonuses(e: any): any
	local r = e.research
	local engineers = Workforce.count(e,"engineer")
	local researchers = Workforce.count(e,"researcher")
	local speed = 1 + engineers * 0.15 + (if r.pipeline then 0.2 else 0) + (if r.cluster then 0.35 else 0)
	local stage = Config.OFFICES[math.clamp(math.floor(tonumber(e.office) or 1), 1, #Config.OFFICES)]
	return { speed = speed, wage = Ops.wage(e),
		revenue = 1 + 0.4 * (1 - math.exp(-Ops.growthO(e) / 10)) + (if r.distribution then 0.15 else 0),
		serving = (if r.quantization then 0.85 else 1) * (1 - 0.2 * (1 - math.exp(-engineers / 10))),
		core = (if r.architecture then 4 else 0) + (if r.frontier then 6 else 0) + math.floor(50 * (1 - math.exp(-researchers / 10))) / 10 + math.clamp(math.floor(tonumber(e.labLevel) or 0), 0, Ops.LAB_MAX),
		reliability = if r.alignment then 8 else 0,
		points = stage.points + researchers * 0.6 }
end
-- Training speed: GPUs x staff x thermal; compute reserved for B2B retainers slows training
-- (max(0.3, 1 - reserved / throughput), CORE_SPEC 3.2); a running studio project takes its share.
function Math.trainingRate(gpus: any, total: number, e: any): number
	local fleet = ModelMath.fleet(gpus)
	local reserved = if typeof(e.deals) == "table" then (tonumber(e.deals.reserved) or 0) else 0
	local b2b = math.max(0.3, 1 - reserved / math.max(1e-6, fleet.throughput))
	return math.min(fleet.throughput * Math.bonuses(e).speed * HardwareConfig.thermal(e,fleet.throughput) * b2b * (if e.projectJob then e.infrastructure.trainingShare else 1), total / ModelConfig.TRAINING.minSeconds)
end
function Math.boostStats(stats: any, e: any): (any, number)
	local b = Math.bonuses(e)
	for _, stat in ModelConfig.STATS do
		if stat.weight > 0 then
			local value = math.round(((stats[stat.id] or 0) + b.core + (if stat.id == "reliability" then b.reliability else 0)) * 10) / 10
			stats[stat.id] = math.min(99, value) -- every core stat is capped at 99 (CORE_SPEC 7.5)
		end
	end
	return stats, ModelMath.overall(stats)
end
function Math.progress(data: any, quest: any): number
	local e = data.empire
	if quest.kind == "company" then return if data.company then 1 else 0 end
	if quest.kind == "tokens" then return ModelMath.dataSummary(data.data).total end
	if quest.kind == "gpus" then return ModelMath.fleet(data.gpus).slotsUsed end
	if quest.kind == "staff" then return Math.staff(e) end
	if quest.kind == "office" then return e.office end
	if quest.kind == "research" then
		local count = 0
		for _, def in Config.RESEARCH do if e.research[def.id] then count += 1 end end
		return count
	end
	if quest.kind == "contractsCompleted" then return e.contractsCompleted end
	return data.stats[quest.kind] or 0
end
-- "Next goal" bar (CORE_SPEC 8.2): the first unmet goal of the fixed order, built only from real state.
-- live (optional) = session.live for the ETA: (price + 2 reserve - cash) / net profit per minute.
-- Returns {id, text, have, need, etaMinutes?} or nil when everything is done.
local function liveLines(data: any): ({ [string]: any }, number)
	local lines: { [string]: any } = {}
	local n = 0
	for _, id in data.modelOrder or {} do
		local m = data.models[id]
		if m and m.status == "live" and m.release then
			local line = ((MarketConfig :: any).LINE_OF or {})[m.release.target or "general"] or "consumers"
			if not lines[line] then n += 1 end
			if not lines[line] or (lines[line].overall or 0) < (m.overall or 0) then lines[line] = m end
		end
	end
	return lines, n
end
function Math.nextGoal(data: any, live: any?): any
	local e = data.empire
	local stats = data.stats or {}
	local cash = tonumber(data.money) or 0
	local net = if live then ((tonumber(live.revenue) or 0) - (tonumber(live.cost) or 0)) * 60 else 0
	local function money(id: string, text: string, price: number): any
		local need = price + Ops.reserve(e) * 2
		local eta = if cash >= need then 0 elseif net > 0 then (need - cash) / net else nil
		return { id = id, text = text, have = math.floor(cash), need = price, etaMinutes = eta }
	end
	local office = math.clamp(math.floor(tonumber(e.office) or 1), 1, #Config.OFFICES)
	local lines, nLines = liveLines(data)
	if (stats.modelsTrained or 0) < 1 then return { id = "train", text = "Train your first AI", have = 0, need = 1 } end
	if (stats.modelsReleased or 0) < 1 then return { id = "release", text = "Release it", have = 0, need = 1 } end
	if (tonumber(e.contractsCompleted) or 0) < 1 then
		local first = Ops.CLIENTS[1]
		local trust = if typeof(e.deals) == "table" and typeof(e.deals.trust) == "table" then tonumber(e.deals.trust[first.id]) or 0 else 0
		return { id = "client", text = "Sign your first client (" .. first.name .. ")", have = math.floor(trust * 100), need = 100 }
	end
	if office < 2 then return money("office2", Config.OFFICES[2].name .. " " .. Ops.money(Config.OFFICES[2].price), Config.OFFICES[2].price) end
	if nLines < 2 then return { id = "lines2", text = "Second product line", have = nLines, need = 2 } end
	if office < 3 then return money("office3", Config.OFFICES[3].name .. " " .. Ops.money(Config.OFFICES[3].price), Config.OFFICES[3].price) end
	local region = false
	if typeof(e.deals) == "table" and typeof(e.deals.accounts) == "table" then
		for id in e.deals.accounts do local c = Ops.client(id); if c and c.trip ~= "city" then region = true end end
	end
	if not region then return { id = "region", text = "First region client", have = 0, need = 1 } end
	if office < 4 then return money("office4", Config.OFFICES[4].name .. " " .. Ops.money(Config.OFFICES[4].price), Config.OFFICES[4].price) end
	if not e.research.frontier then return { id = "frontier", text = "Frontier research (7B)", have = 0, need = 1 } end
	if office < 5 then return money("office5", Config.OFFICES[5].name .. " " .. Ops.money(Config.OFFICES[5].price), Config.OFFICES[5].price) end
	local strong = 0
	for _, m in lines do if (m.overall or 0) >= 90 then strong += 1 end end
	if strong < 4 then return { id = "lines90", text = "All 4 lines at 90+", have = strong, need = 4 } end
	local lab = math.floor(tonumber(e.labLevel) or 0)
	if lab < Ops.LAB_MAX then return { id = "lab", text = "Lab level " .. Ops.LAB_MAX, have = lab, need = Ops.LAB_MAX } end
	if e.jet ~= true then return money("jet", "Company jet " .. Ops.money(Ops.JET.price), Ops.JET.price) end
	return nil
end
function Math.eligible(model: any, contract: any): boolean
	return model.status == "live" and (model.stats[contract.stat] or 0) >= contract.minimum
		and (contract.focus == nil or model.focusId == contract.focus)
end
return Math
