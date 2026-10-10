--!nocheck
-- Shared helpers of the phone package tests: check counter, company fixtures built with the REAL Template /
-- EmpireMath code inside the mock, a session double, a stepping helper in EmpireService order (wages ->
-- CompanyOps.step) and the clock of a visible hour (CompanyOps.hour).
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
function C.find(list, fn)
	for i, v in list or {} do if fn(v, i) then return v, i end end
	return nil
end

function C.load(M)
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local R = {
		M = M, RS = RS, Server = Server,
		Ops = M.require(RS.Shared.CompanyOps),
		PhoneMath = M.require(RS.Shared.PhoneMath),
		EmpireMath = M.require(RS.Shared.EmpireMath),
		MarketMath = M.require(RS.Shared.MarketMath),
		ModelMath = M.require(RS.Shared.ModelMath),
		EmpireConfig = M.require(RS.Shared.Config.EmpireConfig),
		ModelConfig = M.require(RS.Shared.Config.ModelConfig),
		Template = M.require(Server.Lib.Template),
	}
	C.R = R
	return R
end

-- founded company at office `stage`, staff = {researcher = n, ...} (profiles via syncProfiles), live models
function C.company(opts)
	local R = C.R
	opts = opts or {}
	local d = R.Template.new()
	d.company = { name = opts.name or "Nimbus Labs", logo = "N", color = "cyan", spec = "general", foundedAt = 0, reputation = 10 }
	d.money = opts.money or 20000
	local e = d.empire
	e.office = opts.stage or 1
	for _, role in R.EmpireConfig.ROLES do e.employees[role.id] = (opts.staff and opts.staff[role.id]) or 0 end
	R.EmpireMath.syncProfiles(e, opts.userId or 1001)
	d.gpus = opts.gpus or { laptop = 1, consumer = 2 }
	for i, spec in opts.models or {} do
		local id = spec.id or ("model-" .. i)
		local stats = {}
		for _, st in R.ModelConfig.STATS do stats[st.id] = (spec.stats and spec.stats[st.id]) or spec.base or 10 end
		local m = { id = id, name = spec.name or ("Nova" .. i), version = spec.version or 1, sizeId = spec.sizeId or "s500m", focusId = spec.focusId or "balanced",
			status = spec.status or "live", stats = stats, overall = R.ModelMath.overall(stats), iterations = 0, createdAt = 0, trainedAt = 0, trainCost = 0,
			dataUsed = { total = 0, quality = 0.5 } }
		if m.status ~= "trained" then
			m.release = { subPrice = 10, apiPrice = 2, marketing = 0, target = spec.target or "general", releasedAt = 0 }
			m.market = R.MarketMath.newMarketState(m.release.target, 0)
		end
		d.models[id] = m
		table.insert(d.modelOrder, id)
	end
	return d
end

function C.session(data, userId)
	return { player = { UserId = userId or 1001, Name = "Tester", DisplayName = "Tester" }, userId = userId or 1001, data = data,
		live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} }, dirty = false, closed = false }
end

function C.step(s, Economy, clock, dt)
	local R = C.R
	dt = dt or 1
	local e = s.data.empire
	s.live.revenue = 0
	s.live.cost = 0
	e.seconds += dt
	local wage = R.Ops.wage(e)
	Economy.applyFlow(s, 0, wage * dt, "wages")
	s.live.cost += wage
	R.Ops.step(s, dt, Economy, clock)
end

-- server clock whose visible hour is h on server day `day` (0-based)
function C.clockAt(h, day)
	local s
	if h >= 8 and h < 18 then s = (h - 8) * 90 else s = 900 + ((h - 18) % 24) / 14 * 300 end
	return (day or 0) * 1200 + s
end
return C
