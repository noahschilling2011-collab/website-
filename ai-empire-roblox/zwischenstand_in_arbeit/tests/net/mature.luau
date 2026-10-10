--!nocheck
-- Fixture for the net package: a realistic late-game save (tier 4, 240 staff, 30 models, 3-10 live,
-- 30 published projects, full history/invoices/applicants) built with the REAL Template/EmpireMath/
-- ModelMath/MarketMath/StudioMath code inside the mock. Adapted from
-- agents/logic_understand/save_net_ui/measure.luau (same shapes), parameterised per player.
-- Also: size estimators (JSON proxy like the data_ui report, and a Roblox-binary estimate).
local F = {}

-- opts: { userId, models = 30, live = 3, seed = 7, name }
function F.build(M, opts)
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local Template = M.require(Server.Lib.Template)
	local EmpireMath = M.require(RS.Shared.EmpireMath)
	local EmpireConfig = M.require(RS.Shared.Config.EmpireConfig)
	local ModelMath = M.require(RS.Shared.ModelMath)
	local MarketMath = M.require(RS.Shared.MarketMath)
	local ModelConfig = M.require(RS.Shared.Config.ModelConfig)
	local MarketConfig = M.require(RS.Shared.Config.MarketConfig)
	local DataConfig = M.require(RS.Shared.Config.DataConfig)
	local HardwareConfig = M.require(RS.Shared.Config.HardwareConfig)
	local StudioConfig = M.require(RS.Shared.Config.StudioConfig)
	local StudioMath = M.require(RS.Shared.StudioMath)
	local CampusConfig = M.require(RS.Shared.Config.CampusConfig)
	local Http = game:GetService("HttpService")
	local userId = opts.userId or 1001
	local MODELS = opts.models or 30
	local LIVE = opts.live or 3
	local rng = M.G.Random.new(opts.seed or 7)
	local now = os.time()
	local function f(x) return x * (0.7 + rng:NextNumber() * 0.6) end -- non-round double

	local d = Template.new()
	d.company = { name = opts.name or ("Company " .. userId), logo = "N", color = "cyan", spec = "general", foundedAt = now - 9e5, reputation = f(80) }
	d.money = f(4.2e6)
	d.data = {}
	for _, t in DataConfig.TYPES do d.data[t.id] = { tokens = f(2e10), quality = f(0.8) } end
	d.gpus = {}
	for i, g in HardwareConfig.GPUS do d.gpus[g.id] = i end
	local summary = ModelMath.dataSummary(d.data)
	local segs = {}
	for _, s in MarketConfig.SEGMENTS do if not string.find(s.id, "^npc_") then table.insert(segs, s.id) end end
	for i = 1, MODELS do
		local size = ModelConfig.SIZES[(i - 1) % #ModelConfig.SIZES + 1]
		local focus = ModelConfig.FOCUSES[(i - 1) % #ModelConfig.FOCUSES + 1]
		local stats, overall = ModelMath.computeStats(size.id, focus.id, summary, "general", 1, nil)
		local id = Http:GenerateGUID(false)
		local status = if i > MODELS - LIVE then "live" elseif i > MODELS - LIVE - 5 then "trained" else "retired"
		local m = { id = id, name = "Nimbus " .. tostring(i), version = i, sizeId = size.id, focusId = focus.id, status = status,
			createdAt = now - i * 3600, trainedAt = now - i * 3000, stats = stats, overall = overall, trainCost = f(50000),
			iterations = i % 4, dataUsed = summary }
		if status ~= "trained" then
			m.release = { subPrice = 20, apiPrice = 2, marketing = 5000, target = segs[1], releasedAt = now - i * 2000 }
			local mk = MarketMath.newMarketState(segs[1], 5000)
			mk.age = f(20000)
			for _, s in segs do mk.users[s] = f(30000); mk.organic[s] = f(0.05) end
			mk.revenueTotal = f(2e6); mk.peakUsers = f(90000)
			m.market = mk
		end
		d.models[id] = m
		table.insert(d.modelOrder, id)
	end
	local loss = {}
	for i = 1, ModelConfig.TRAINING.lossPoints do loss[i] = math.round(f(3) * 1000) / 1000 end
	local log = {}
	for i = 1, ModelConfig.TRAINING.logLines do log[i] = "Epoch " .. i .. " · loss 1.234 · 4096 GB VRAM busy" end
	d.stats = { totalRevenue = f(9e7), totalCost = f(6e7), modelsTrained = MODELS, modelsReleased = MODELS - 5, peakUsers = f(4e5), bestOverall = f(180) }
	d.lastScrapeAt = now

	local e = d.empire
	e.office = 4
	local per = math.floor(240 / #EmpireConfig.ROLES)
	local left = 240
	for i, r in EmpireConfig.ROLES do
		local n = if i == #EmpireConfig.ROLES then left else per
		e.employees[r.id] = n; left -= n
	end
	EmpireMath.syncProfiles(e, userId)
	for _, list in e.staffProfiles do for _, p in list do p.w = math.floor(f(1.1) * 100 + 0.5) / 100 end end
	e.hireSerial = 400
	for _, r in EmpireConfig.RESEARCH do e.research[r.id] = true end
	for _, q in EmpireConfig.QUESTS do e.quests[q.id] = true end
	for _, c in EmpireConfig.CONTRACTS do e.contracts[c.id] = math.floor(now / 86400) end
	e.contractsCompleted = 140; e.xp = f(90000); e.points = f(5000); e.seconds = f(400000); e.lastSeen = now
	e.daily = { day = math.floor(now / 86400), streak = 7 }
	for i = 1, 36 do table.insert(e.history, { time = now - (36 - i) * 10 + rng:NextNumber(), profit = math.round(f(80000) * 10) / 10, users = math.round(f(4e5)) }) end
	e.historyClock = f(5)
	for i = 1, 20 do table.insert(e.invoices, { time = now - i * 60, text = "API access: Nimbus " .. i, amount = -math.floor(f(4000)) }) end
	for i = 1, 30 do
		local kind = StudioConfig.KINDS[(i - 1) % #StudioConfig.KINDS + 1]
		local brief = StudioConfig.BRIEFS[(i - 1) % #StudioConfig.BRIEFS + 1]
		local id = "project-" .. Http:GenerateGUID(false)
		e.projects[id] = { id = id, name = "Project " .. i, kind = kind.id, style = "paper", briefId = brief.id, status = "published", quality = f(80),
			content = StudioMath.content("Project " .. i, kind.id, brief.id), modelName = "Nimbus 3", sourceId = d.modelOrder[1], createdAt = now,
			visitors = math.floor(f(9000)), revenueTotal = f(30000), delivered = true }
		table.insert(e.projectOrder, id)
		e.deliveries[brief.id] = math.floor(now / 86400)
	end
	for i = 1, 12 do table.insert(e.arenaHistory, { name = "Nimbus " .. i, score = math.floor(f(900)), moves = 40, seconds = 31.4, winner = true, opponent = "Kiln Logic", opponentScore = 700, time = now }) end
	e.arenaBest = 1200
	for _ = 1, EmpireMath.MAX_APPLICANTS do
		local name, seed, serial = EmpireMath.nextIdentity(e, userId)
		table.insert(e.applicants, { id = "app" .. serial, serial = serial, role = EmpireConfig.ROLES[1].id, n = name, s = seed, xp = 7, prev = "Northwind Analytics",
			spec = "Distributed training", ask = 1.12, at = e.seconds, st = "new", q = { "experience", "motivation" } })
	end
	local c = e.campus
	for _, s in CampusConfig.SNACKS do c.snacks[s.id] = 2 end
	for _, car in CampusConfig.CARS do c.cars[car.id] = true end
	c.retailLevel = 4; c.retailSales = 9000; c.retailRevenue = f(108000)
	local migrated, err = Template.migrate(d)
	assert(migrated, err)
	return migrated
end

-- JSON size (mock encoder, 6 decimals: same proxy as the data_ui report's low column)
function F.json(M, v)
	return #M.JSON.encode(v)
end

-- Estimate of Roblox's binary remote encoding (type tag + payload; numbers are 8-byte doubles, strings
-- length-prefixed, tables = count + entries, dictionary keys as strings). An ESTIMATE, not measured.
local function varint(n)
	local b = 1
	while n >= 128 do n = n // 128; b += 1 end
	return b
end
local function bin(v)
	local t = type(v)
	if t == "number" then return 9 end
	if t == "boolean" then return 2 end
	if t == "string" then return 1 + varint(#v) + #v end
	if t == "table" then
		local n = #v
		local total, count = 1, 0
		if n > 0 then
			for i = 1, n do total += bin(v[i]) end
			return total + varint(n)
		end
		for k, val in v do
			count += 1
			local ks = tostring(k)
			total += varint(#ks) + #ks + bin(val)
		end
		return total + varint(count)
	end
	return 2
end
F.bin = bin

return F
