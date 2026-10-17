--!nocheck
-- Shared helpers of the econ package tests (tests/econ/*): check counter, company fixtures built with the
-- REAL Template / EmpireMath code inside the mock, a session double and a stepping helper that mirrors
-- EmpireService.tick's order (market flow -> wages -> CompanyOps.step) without the services around it.
local C = {}
C.pass, C.fail = 0, 0
function C.check(name, ok, detail)
	if ok then
		C.pass += 1
	else
		C.fail += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else ""))
	end
end
function C.near(a, b, tol)
	return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (tol or 1e-6)
end
function C.count(t)
	local n = 0
	for _ in t or {} do n += 1 end
	return n
end
function C.summary(name)
	print(string.format("%s: %d passed, %d failed", name, C.pass, C.fail))
end

-- modules (call after M.loadTree)
function C.load(M)
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local R = {
		M = M,
		RS = RS,
		Server = Server,
		Ops = M.require(RS.Shared.CompanyOps),
		EmpireMath = M.require(RS.Shared.EmpireMath),
		Workforce = M.require(RS.Shared.WorkforceMath),
		MarketMath = M.require(RS.Shared.MarketMath),
		ModelMath = M.require(RS.Shared.ModelMath),
		EmpireConfig = M.require(RS.Shared.Config.EmpireConfig),
		MarketConfig = M.require(RS.Shared.Config.MarketConfig),
		HardwareConfig = M.require(RS.Shared.Config.HardwareConfig),
		GameConfig = M.require(RS.Shared.Config.GameConfig),
		EmployeeConfig = M.require(RS.Shared.Config.EmployeeConfig),
		ModelConfig = M.require(RS.Shared.Config.ModelConfig),
		Plan = M.require(RS.Shared.Config.BuildingPlan),
		Template = M.require(Server.Lib.Template),
	}
	C.R = R
	return R
end

-- a founded company at office `stage` with `staff` = {researcher=n, ...} (agency profiles via syncProfiles),
-- one live model per entry of `models` = { {stats = {...}, sizeId, target}, ... }, GPUs, money
function C.company(opts)
	local R = C.R
	opts = opts or {}
	local d = R.Template.new()
	d.company = { name = opts.name or "Nimbus Labs", logo = "N", color = "cyan", spec = "general", foundedAt = 0, reputation = opts.reputation or 10 }
	d.money = opts.money or 1e6
	local e = d.empire
	e.office = opts.stage or 1
	for _, role in R.EmpireConfig.ROLES do e.employees[role.id] = (opts.staff and opts.staff[role.id]) or 0 end
	R.EmpireMath.syncProfiles(e, opts.userId or 1001)
	if opts.skill then
		for _, list in e.staffProfiles do for _, p in list do p.k = opts.skill end end
	end
	d.gpus = opts.gpus or { laptop = 1, consumer = 2 }
	if opts.research == "all" then for _, def in R.EmpireConfig.RESEARCH do e.research[def.id] = true end end
	for i, spec in opts.models or {} do
		local id = "model-" .. i
		local stats = {}
		for _, st in R.ModelConfig.STATS do stats[st.id] = (spec.stats and spec.stats[st.id]) or spec.base or 10 end
		local m = { id = id, name = "Nova" .. i, version = 1, sizeId = spec.sizeId or "s500m", focusId = "balanced", status = "live",
			stats = stats, overall = R.ModelMath.overall(stats), iterations = 0, createdAt = 0, trainedAt = 0, trainCost = 0,
			dataUsed = { total = 0, quality = 0.5 } }
		m.release = { subPrice = 10, apiPrice = 2, marketing = 0, target = spec.target or "general", releasedAt = 0 }
		m.market = R.MarketMath.newMarketState(m.release.target, 0)
		d.models[id] = m
		table.insert(d.modelOrder, id)
	end
	return d
end

function C.session(data, userId)
	return { player = { UserId = userId or 1001, Name = "Tester", DisplayName = "Tester" }, userId = userId or 1001, data = data,
		live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} }, dirty = false, closed = false }
end

-- one simulated company second in EmpireService order: (market flow already in live) -> wages -> Ops.step.
-- clock = visible server clock (CompanyOps.hour(clock)); play time empire.seconds advances by dt.
function C.step(s, Economy, clock, dt, marketRevenue)
	local R = C.R
	dt = dt or 1
	local e = s.data.empire
	s.live.revenue = marketRevenue or 0
	s.live.cost = 0
	if marketRevenue and marketRevenue > 0 then Economy.applyFlow(s, marketRevenue * dt, 0, "market") end
	e.seconds += dt
	local wage = R.Ops.wage(e)
	Economy.applyFlow(s, 0, wage * dt, "wages")
	s.live.cost += wage
	R.Ops.step(s, dt, Economy, clock)
end

-- clock value (seconds) whose visible hour is h (0..24) on server day `day` (0-based)
function C.clockAt(h, day)
	local s
	if h >= 8 and h < 18 then s = (h - 8) * 90 else s = 900 + ((h - 18) % 24) / 14 * 300 end
	return (day or 0) * 1200 + s
end

function C.ledger(e, side, cat)
	local total = 0
	for _, entry in e.ledger or {} do total += (entry[side] and entry[side][cat]) or 0 end
	return total
end
return C
