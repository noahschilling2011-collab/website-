--!nocheck
-- Net package: snapshot bandwidth benchmark on the REAL server simulation.
-- N players with mature saves (tests/net/mature.luau) are inserted into the real SessionService; every
-- virtual second runs the same per-tick order as Main.server (NPC, shared market, per player: training,
-- market, studio, empire, facility economy, recruiting; studio refresh, leaderboard, campus); arena at
-- 10 Hz, a workforce report every 0.2 s (stand-in for StaffService, which needs a built office), and
-- SessionService.flush at 60 Hz. Every fired "State" payload is measured (JSON proxy + binary estimate).
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_net && tools/luau tests/net/bw.luau -a [players] [seconds] [actionsPerMinute] [models] [live] [genDir]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[6] or ".gen_net") -- 6th arg: another generated tree (e.g. .gen_net_neg_session = pre-change code)
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local F = require("./mature")
local PLAYERS = tonumber(args[1]) or 12
local SECONDS = tonumber(args[2]) or 60
local ACTIONS = tonumber(args[3]) or 0 -- simulated player remote actions per minute per player
local MODELS = tonumber(args[4]) or 30 -- models per save
local LIVE = tonumber(args[5]) -- live models per save (default: 3..10 varying per player)
local WARMUP = 5

local function body()
	local game = M.game
	local Server = game.ServerScriptService.Server
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
	Remote.setup()
	local origSet = Remote.setSessionProvider
	Remote.setSessionProvider = function(provider) Remote._provider = provider; origSet(provider) end
	SessionService.init()
	NPCService.init()

	-- capture what would go over the wire
	local stats = {} -- [userId] = {sends, json, bin, firstJson, firstBin}
	local measuring = false
	local measureCpu = 0
	Remote.fire = function(player, name, payload)
		if name ~= "State" then return end
		local m0 = os.clock()
		local st = stats[player.UserId]
		if not st then st = { sends = 0, json = 0, bin = 0 }; stats[player.UserId] = st end
		if not st.firstJson then
			st.firstJson = F.json(M, payload); st.firstBin = F.bin(payload)
		elseif measuring then
			st.sends += 1
			st.json += F.json(M, payload)
			st.bin += F.bin(payload)
		end
		measureCpu += os.clock() - m0 -- measuring is not part of the flush cost
	end

	local sessions = SessionService.all()
	local players = {}
	for i = 1, PLAYERS do
		local uid = 1000 + i
		local data = F.build(M, { userId = uid, models = MODELS, live = LIVE or (3 + (i - 1) % 8), seed = i, name = "Company " .. i })
		local player = { UserId = uid, Name = "P" .. i, DisplayName = "Player " .. i, Parent = game.Players, Character = nil }
		local session = { player = player, userId = uid, data = data, live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} },
			dirty = true, lastSent = 0, nextSaveAt = math.huge, saving = false, closed = false, released = false, rng = M.G.Random.new(i) }
		sessions[player] = session
		table.insert(players, player)
	end
	local function safely(label, fn)
		local ok, err = pcall(fn)
		if not ok then error(label .. ": " .. tostring(err)) end
	end
	local function simulate(step)
		safely("npc", function() NPCService.tick(step) end)
		safely("market", function() MarketService.tickGlobal(step) end)
		for _, session in sessions do
			if not session.closed then
				safely("training", function() AIModelService.tick(session, step) end)
				safely("marketTick", function() MarketService.tick(session, step) end)
				safely("empire", function()
					StudioService.tick(session, step)
					EmpireService.tick(session, step)
					FacilityService.economyTick(session, step)
				end)
				safely("recruiting", function() RecruitingService.tick(session, step) end)
			end
		end
		StudioService.refresh()
		LeaderboardService.tick(step)
		CampusService.tick(step)
	end
	local rng = M.G.Random.new(99)
	local STATES = { "WORKING", "RESEARCH", "COFFEE_BREAK", "LUNCH", "MEETING", "TALKING", "WALKING", "OFF_DUTY" }
	local function workforce(session, hour)
		local states = {}
		for _, k in STATES do states[k] = rng:NextInteger(0, 40) end
		session.live.workforce = { researcher = rng:NextNumber() * 60, engineer = rng:NextNumber() * 60, curator = rng:NextNumber() * 60,
			marketer = rng:NextNumber() * 60, visible = 80, total = 240, hour = hour, states = states }
	end
	local FPS = 60
	local now = 0
	local acc, arenaAcc, staffAcc = 0, 0, 0
	local nextAction = {}
	for i, p in players do nextAction[p] = if ACTIONS > 0 then (i / PLAYERS) * 60 / ACTIONS else math.huge end
	local flushCpu, flushCalls = 0, 0
	for frame = 1, (SECONDS + WARMUP) * FPS do
		local dt = 1 / FPS
		now += dt
		if now >= WARMUP and not measuring then measuring = true end
		staffAcc += dt
		if staffAcc >= 0.2 then
			staffAcc = 0
			for _, s in sessions do workforce(s, 8 + (now % 1200) / 90) end
		end
		arenaAcc += dt
		if arenaAcc >= 0.1 then
			local step = arenaAcc; arenaAcc = 0
			ArenaService.tick(step)
		end
		acc += dt
		if acc >= 1 then
			local step = acc; acc = 0
			simulate(step)
		end
		-- a player action: a remote handler changes data and marks the session dirty (goes through the
		-- session provider exactly like Remote.bind does)
		for _, p in players do
			if now >= nextAction[p] then
				nextAction[p] += 60 / ACTIONS
				local s = sessions[p]
				local provider = Remote._provider
				if provider then provider(p) end
				s.data.empire.campus.snacks.coffee = (s.data.empire.campus.snacks.coffee or 0) + 1
				SessionService.markDirty(s)
			end
		end
		local t0 = os.clock()
		local m0 = measureCpu
		SessionService.flush(now)
		local dtc = os.clock() - t0 - (measureCpu - m0)
		if measuring then flushCpu += dtc; flushCalls += 1 end
	end
	local totalJson, totalBin, totalSends, n = 0, 0, 0, 0
	local firstJson, firstBin = 0, 0
	for _, st in stats do
		totalJson += st.json; totalBin += st.bin; totalSends += st.sends; n += 1
		firstJson += st.firstJson; firstBin += st.firstBin
	end
	print(string.format("players=%d seconds=%d actions/min=%d models=%d live=%s", PLAYERS, SECONDS, ACTIONS, MODELS, if LIVE then tostring(LIVE) else "3-10"))
	print(string.format("first (full) snapshot: %.1f KB JSON, %.1f KB binary-est (avg per player)", firstJson / n / 1024, firstBin / n / 1024))
	print(string.format("steady: %.2f sends/s per player, %.1f B JSON / %.1f B bin per send", totalSends / n / SECONDS, totalJson / math.max(1, totalSends), totalBin / math.max(1, totalSends)))
	print(string.format("BANDWIDTH per player: %.2f KB/s JSON, %.2f KB/s binary-est", totalJson / n / SECONDS / 1024, totalBin / n / SECONDS / 1024))
	print(string.format("server out total: %.1f KB/s JSON, %.1f KB/s binary-est", totalJson / SECONDS / 1024, totalBin / SECONDS / 1024))
	print(string.format("flush CPU (mock): %.3f ms per second of game time (%.4f ms per flush call, all players)", flushCpu * 1000 / SECONDS, flushCpu * 1000 / math.max(1, flushCalls)))
end
local ok, err = M.runMain(body, { timeout = 100000, maxSteps = 50000000 })
if not ok then print("FAILED", err) end
