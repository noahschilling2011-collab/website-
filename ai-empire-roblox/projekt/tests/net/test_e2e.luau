--!nocheck
-- Net package end-to-end: N players with mature saves on the REAL server simulation (same per-tick
-- order as Main.server; StaffService replaced by a 5 Hz workforce report, arena at 10 Hz, flush at
-- 60 Hz, a few player remote actions per minute). Player 1's messages go through wire() into the
-- real StateController; its rebuilt snapshot must equal the server state after every send (lazy
-- counters excepted until their sweep) — also with 5 % of the messages dropped. Bandwidth must stay
-- <= 15 KB/s per player (JSON proxy, steady state).
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_net && tools/luau tests/net/test_e2e.luau [-a .gen_dir [players [seconds]]]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_net")
local PLAYERS = tonumber(args[2]) or 12
local SECONDS = tonumber(args[3]) or 60
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local F = require("./mature")
local W = require("./wire")
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end
-- mirrors SessionService.LAZY (econ package added the CORE_SPEC 11.8 paths: deals.news/trust, ledger, live.ops/waitlist/load/demand;
-- corefix: deals.broke and the marketplace offers' vage)
local LAZY = { data = { empire = { projects = { ["*"] = { visitors = true, revenueTotal = true } }, deals = { news = true, trust = true, broke = true }, ledger = true } },
	live = { studio = { gallery = { ["*"] = { visitors = true, revenueTotal = true } } }, marketplace = { offers = { ["*"] = { users = true, vage = true } } },
		ops = true, waitlist = true, load = true, demand = true } }

local function body()
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local S = Server.Services
	local Remote = M.require(Server.Lib.Remote)
	local SessionService = M.require(S.SessionService)
	local MarketService = M.require(S.MarketService)
	local NPCService = M.require(S.NPCService)
	local AIModelService = M.require(S.AIModelService)
	local StudioService = M.require(S.StudioService)
	local EmpireService = M.require(S.EmpireService)
	local FacilityService = M.require(S.FacilityService)
	local RecruitingService = M.require(S.RecruitingService)
	local LeaderboardService = M.require(S.LeaderboardService)
	local CampusService = M.require(S.CampusService)
	local ArenaService = M.require(S.ArenaService)
	local binds, provider = {}, nil
	local origBind, origSet = Remote.bind, Remote.setSessionProvider
	Remote.bind = function(name, limits, handler) binds[name] = handler; origBind(name, limits, handler) end
	Remote.setSessionProvider = function(fn) provider = fn; origSet(fn) end
	Remote.setup()
	SessionService.init()
	NPCService.init()

	local sessions = SessionService.all()
	local players = {}
	for i = 1, PLAYERS do
		local uid = 1000 + i
		local data = F.build(M, { userId = uid, live = 3 + (i - 1) % 8, seed = i, name = "Company " .. i })
		local player = { UserId = uid, Name = "P" .. i, DisplayName = "Player " .. i, Parent = game.Players }
		sessions[player] = { player = player, userId = uid, data = data, live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} },
			dirty = true, lastSent = 0, nextSaveAt = math.huge, saving = false, closed = false, released = false, rng = M.G.Random.new(i) }
		table.insert(players, player)
	end
	local me = players[1]
	local mine = sessions[me]

	-- client of player 1
	local folder = RS:FindFirstChild("Remotes")
	local stateEvent = folder:FindFirstChild("State")
	local function patch(cls, name, fn) M.IMPL[cls].methods[name] = fn; M.classInfo(cls).methods[name] = fn end
	local requests = 0
	patch("RemoteFunction", "InvokeServer", function(self, payload)
		if self.Name ~= "RequestState" then return { ok = false } end
		requests += 1
		return W.wire(binds.RequestState(provider(me), payload or {}))
	end)
	local State = M.require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.StateController)

	local measuring, dropEvery = false, 0
	local stats = { sends = 0, json = 0, bin = 0, n = 0 }
	local delivered, dropped, sentToMe = 0, 0, false
	local fireCpu = 0 -- time spent in measuring + the client, excluded from the flush cost
	Remote.fire = function(player, name, payload)
		if name ~= "State" then return end
		local f0 = os.clock()
		fireCpu -= f0
		local function done() fireCpu += os.clock() end
		if measuring then
			stats.sends += 1; stats.json += F.json(M, payload); stats.bin += F.bin(payload)
		end
		if player == me then
			delivered += 1
			if dropEvery > 0 and delivered % dropEvery == 0 then dropped += 1; done(); return end
			sentToMe = true
			M.fire(stateEvent.OnClientEvent, W.wire(payload))
		end
		done()
	end
	State.init()
	M.settle(0.1)

	local function simulate(step)
		NPCService.tick(step); MarketService.tickGlobal(step)
		for _, s in sessions do
			AIModelService.tick(s, step); MarketService.tick(s, step)
			StudioService.tick(s, step); EmpireService.tick(s, step); FacilityService.economyTick(s, step)
			RecruitingService.tick(s, step)
		end
		StudioService.refresh(); LeaderboardService.tick(step); CampusService.tick(step)
	end
	local rng = M.G.Random.new(5)
	local function view(s)
		-- econ: what SessionService replicates (shop receipts/order stripped, company log trimmed to 20 lines)
		return { data = SessionService.replicatedData(s.data), live = s.live }
	end
	local mismatches, compares, firstMismatch = 0, 0, nil
	local now, acc, arenaAcc, staffAcc = 0, 0, 0, 0
	local flushCpu = 0
	local function run(seconds, measure)
		local nextAction = {}
		for i, p in players do nextAction[p] = now + i * 0.37 end
		for _ = 1, seconds * 60 do
			now += 1 / 60
			measuring = measure and now > 5
			staffAcc += 1 / 60
			if staffAcc >= 0.2 then
				staffAcc = 0
				for _, s in sessions do
					s.live.workforce = { researcher = rng:NextNumber() * 60, engineer = rng:NextNumber() * 60, curator = rng:NextNumber() * 60, marketer = rng:NextNumber() * 60,
						visible = 80, total = 240, hour = 8 + (now % 1200) / 90, states = { WORKING = rng:NextInteger(100, 200), LUNCH = rng:NextInteger(0, 30) } }
				end
			end
			arenaAcc += 1 / 60
			if arenaAcc >= 0.1 then ArenaService.tick(arenaAcc); arenaAcc = 0 end
			acc += 1 / 60
			if acc >= 1 then simulate(acc); acc = 0 end
			for _, p in players do -- ~4 remote actions per minute per player
				if now >= nextAction[p] then
					nextAction[p] = now + 15
					local s = provider(p)
					s.data.empire.campus.snacks.coffee = (s.data.empire.campus.snacks.coffee or 0) + 1
					SessionService.markDirty(s)
				end
			end
			sentToMe = false
			local t0 = os.clock()
			local c0 = fireCpu
			SessionService.flush(now)
			if measuring then flushCpu += os.clock() - t0 - (fireCpu - c0) end
			if sentToMe then
				compares += 1
				local snap = State.snapshot
				local diff = if snap then W.equal({ data = snap.data, live = snap.live }, view(mine), LAZY) else "no snapshot"
				if diff then mismatches += 1; firstMismatch = firstMismatch or diff end
			end
		end
	end
	local function sweep()
		mine.sweptAt = -math.huge; mine.dirty = true; mine.lastSent = -math.huge
		sentToMe = false
		SessionService.flush(now)
		local snap = State.snapshot
		return if snap then W.equal({ data = snap.data, live = snap.live }, view(mine)) else "no snapshot"
	end

	local r0 = requests
	run(SECONDS + 5, true)
	local kbs = stats.json / PLAYERS / SECONDS / 1024
	local kbsBin = stats.bin / PLAYERS / SECONDS / 1024
	print(string.format("  %d players, %d s: %.2f sends/s per player, %.2f KB/s JSON (%.2f KB/s binary-est) per player, server out %.1f KB/s",
		PLAYERS, SECONDS, stats.sends / PLAYERS / SECONDS, kbs, kbsBin, stats.json / SECONDS / 1024))
	print(string.format("  flush CPU (mock env, ~3.5x slower than plain Luau): %.2f ms per second for %d players", flushCpu * 1000 / SECONDS, PLAYERS))
	check(string.format("bandwidth <= 15 KB/s per player (%.2f)", kbs), kbs <= 15)
	check(string.format("steady rate <= 2 sends/s per player (%.2f)", stats.sends / PLAYERS / SECONDS), stats.sends / PLAYERS / SECONDS <= 2.05)
	check(string.format("client == server after every send (%d compares)", compares), mismatches == 0 and compares > SECONDS / 2, firstMismatch)
	check("no resync requests without loss", requests == r0, requests - r0)
	check("after a sweep the client matches exactly (lazy counters too)", sweep() == nil, sweep())
	-- lossy delivery: every 20th message to player 1 is lost
	dropEvery = 20
	r0 = requests
	mismatches, compares, firstMismatch = 0, 0, nil
	run(40, false)
	dropEvery = 0
	check(string.format("lossy: %d messages dropped, client resynced (%d requests)", dropped, requests - r0), dropped > 0 and requests - r0 >= 1 and requests - r0 <= dropped + 1)
	check("lossy: client == server after every applied send", mismatches == 0, firstMismatch)
	check("lossy: exact after a sweep", sweep() == nil)
	check("all messages remote-safe", #W.problems == 0, W.problems[1])
end
local ok, err = M.runMain(body, { timeout = 100000, maxSteps = 50000000 })
if not ok then failc += 1; print("ERROR " .. tostring(err)) end
print(string.format("net e2e tests: %d passed, %d failed", pass, failc))
