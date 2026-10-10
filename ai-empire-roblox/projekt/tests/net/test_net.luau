--!nocheck
-- Net package: SessionService replication (full/delta, per-field change detection, shop stripping,
-- rate + urgent flush), client StateController (merge, gaps, out-of-order, legacy snapshots) and the
-- MarketService live-table merge. Real modules in the mock; remote delivery simulated with wire().
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_net && tools/luau tests/net/test_net.luau [-a .gen_dir]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_net")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local F = require("./mature")
local W = require("./wire")
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local function body()
	local G = M.G
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local S = Server.Services
	local Remote = M.require(Server.Lib.Remote)
	local GameConfig = M.require(RS.Shared.Config.GameConfig)
	local EmpireMath = M.require(RS.Shared.EmpireMath)
	local Workforce = M.require(RS.Shared.WorkforceMath)
	local SessionService = M.require(S.SessionService)
	local MarketService = M.require(S.MarketService)

	-- capture binds + provider like Remote.bind would use them; capture fired State messages
	local binds, provider = {}, nil
	local origBind, origSet = Remote.bind, Remote.setSessionProvider
	Remote.bind = function(name, limits, handler) binds[name] = handler; origBind(name, limits, handler) end
	Remote.setSessionProvider = function(fn) provider = fn; origSet(fn) end
	local outbox = {}
	Remote.fire = function(player, name, payload) if name == "State" then table.insert(outbox, { player = player, msg = payload }) end end
	Remote.setup()
	SessionService.init()
	local function invoke(player, name, payload)
		local session = provider(player) -- what Remote.bind does before the handler
		return binds[name](session, payload or {})
	end

	local OWNER = 1001
	local player = { UserId = OWNER, Name = "Founder", DisplayName = "Founder", Parent = game.Players }
	local data = F.build(M, { userId = OWNER, live = 4, seed = 3 })
	local session = { player = player, userId = OWNER, data = data, live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} },
		dirty = true, lastSent = 0, nextSaveAt = math.huge, saving = false, closed = false, released = false, rng = G.Random.new(1) }
	SessionService.all()[player] = session
	-- live fields as the other services set them
	session.live.workforce = { researcher = 30, engineer = 30, curator = 30, marketer = 30, visible = 10, total = 240, hour = 10, states = { WORKING = 100 } }
	session.live.admin = true
	session.live.campus = { hasCard = true, online = {}, passes = {}, supportStaff = 12, retailNetPerTicket = 12 }
	session.live.empire = { board = { { name = "A", best = 10, userId = 1 } } }
	session.live.studio = { gallery = { { id = "g1", name = "Site", visitors = 5, revenueTotal = 10, company = "X" } } }
	session.live.rankings = { status = "Server preview", boards = { overall = { { name = "A", userId = 1, score = 3 } } } }
	session.live.arena = { rivals = { { company = "Kiln", text = "Opened", time = 1 } } }
	session.live.marketplace = { offers = { { providerId = 5, id = "m1", name = "M", overall = 50, users = 100, price = 200 } }, customers = {} }

	------------------------------------------------------------------ server: first send, deltas
	local now = 10
	SessionService.flush(now)
	check("first send is one full snapshot", #outbox == 1 and outbox[1].msg.data ~= nil and outbox[1].msg.patch == nil)
	local first = outbox[1].msg
	check("full snapshot numbered", first.seq == 1)
	check("full snapshot has every heavy field", first.data.models and first.data.empire.staffProfiles and first.data.empire.projects and first.live.marketplace and first.live.workforce and true)
	table.clear(outbox)
	session.dirty = true
	now += 1
	SessionService.flush(now)
	check("dirty but nothing changed: nothing sent", #outbox == 0)
	data.money += 123
	session.dirty = true
	now += 1
	SessionService.flush(now)
	local d1 = outbox[1] and outbox[1].msg
	check("delta sent", d1 ~= nil and d1.patch ~= nil and d1.data == nil)
	check("delta numbered against the last send", d1 and d1.base == 1 and d1.seq == 2)
	check("delta carries only the change", d1 and d1.patch.p and d1.patch.p.data and d1.patch.p.data.s and d1.patch.p.data.s.money == data.money and d1.patch.p.live == nil)
	check("delta is tiny", d1 and F.json(M, d1) < 200, d1 and F.json(M, d1))
	table.clear(outbox)

	-- per heavy field: unchanged -> absent, changed -> present (and nothing else heavy)
	local HEAVY = {
		{ "models", { "data", "models" }, function() local id = data.modelOrder[#data.modelOrder]; data.models[id].market.users.consumer = (data.models[id].market.users.consumer or 0) + 1 end },
		{ "projects", { "data", "empire", "projects" }, function() local id = data.empire.projectOrder[1]; data.empire.projects[id].status = "archived" end },
		{ "history", { "data", "empire", "history" }, function() table.insert(data.empire.history, { time = 1, profit = 2, users = 3 }); table.remove(data.empire.history, 1) end },
		{ "staffProfiles", { "data", "empire", "staffProfiles" }, function() data.empire.staffProfiles.researcher[1].k = 5 end },
		{ "applicants", { "data", "empire", "applicants" }, function() table.remove(data.empire.applicants, 1) end },
		{ "invoices", { "data", "empire", "invoices" }, function() table.insert(data.empire.invoices, 1, { time = 2, text = "x", amount = 1 }) end },
		{ "arenaHistory", { "data", "empire", "arenaHistory" }, function() data.empire.arenaHistory[1].score += 1 end },
		{ "marketplace", { "live", "marketplace" }, function() session.live.marketplace = { offers = { { providerId = 5, id = "m1", name = "M", overall = 51, users = 100, price = 200 } }, customers = {} } end },
		{ "studio", { "live", "studio" }, function() session.live.studio = { gallery = { { id = "g1", name = "Site v2", visitors = 5, revenueTotal = 10, company = "X" } } } end },
		{ "rankings", { "live", "rankings" }, function() session.live.rankings = { status = "Global leaderboard", boards = session.live.rankings.boards } end },
		{ "arena", { "live", "arena" }, function() session.live.arena = { active = { model = "N", lane = 1, progress = 0.5, moves = 3, opponent = "K" }, rivals = session.live.arena.rivals } end },
		{ "workforce", { "live", "workforce" }, function() session.live.workforce = table.clone(session.live.workforce); session.live.workforce.visible = 11 end },
		{ "campus", { "live", "campus" }, function() session.live.campus.hasCard = false end },
	}
	-- rebuilt-but-equal tables (services recreate live tables every tick) are not resent
	session.live.rankings = { status = session.live.rankings.status, boards = { overall = { { name = "A", userId = 1, score = 3 } } } }
	session.live.marketplace = { offers = { { providerId = 5, id = "m1", name = "M", overall = 50, users = 100, price = 200 } }, customers = {} }
	data.money += 1; session.dirty = true; now += 1
	SessionService.flush(now)
	local quiet = outbox[1] and outbox[1].msg.patch
	for _, h in HEAVY do check("unchanged " .. h[1] .. " omitted", quiet and not W.touches(quiet, h[2]), h[1]) end
	check("rebuilt-but-equal live tables not resent", quiet and not W.touches(quiet, { "live" }))
	table.clear(outbox)
	for _, h in HEAVY do
		h[3]()
		session.dirty = true; now += 1
		SessionService.flush(now)
		local patch = outbox[1] and outbox[1].msg.patch
		check("changed " .. h[1] .. " sent", patch and W.touches(patch, h[2]))
		local others = 0
		for _, o in HEAVY do if o ~= h and patch and W.touches(patch, o[2]) then others += 1 end end
		check("only " .. h[1] .. " sent", others == 0, others)
		table.clear(outbox)
	end
	check("staffProfiles change sent as a single value", true)

	-- full state on request resets the baseline
	local res = invoke(player, "RequestState")
	check("RequestState returns a full snapshot", res.ok == true and res.state.data and res.state.data.empire.staffProfiles ~= nil and res.state.seq ~= nil)
	data.money += 5; session.dirty = true; now += 1
	SessionService.flush(now)
	check("next delta is based on the RequestState snapshot", outbox[1] and outbox[1].msg.base == res.state.seq)
	table.clear(outbox)

	-- shop: receipts/order never replicated, other shop fields are
	data.shop = { passes = { vip = true }, receipts = { r1 = { product = 1 } }, order = { "r1" } }
	local full = SessionService.snapshot(session)
	check("full snapshot strips shop.receipts/order", full.data.shop and full.data.shop.passes.vip == true and full.data.shop.receipts == nil and full.data.shop.order == nil)
	check("session data keeps receipts", data.shop.receipts.r1 ~= nil and data.shop.order[1] == "r1")
	data.shop.receipts.r2 = { product = 2 }; table.insert(data.shop.order, "r2")
	session.dirty = true; now += 1
	SessionService.flush(now)
	check("receipt changes never sent", #outbox == 0 or not W.touches(outbox[1].msg.patch, { "data", "shop" }))
	table.clear(outbox)
	data.shop.passes.boost = true
	session.dirty = true; now += 1
	SessionService.flush(now)
	local sp = outbox[1] and outbox[1].msg.patch
	check("other shop changes sent", sp and W.touches(sp, { "data", "shop", "passes" }) and not W.touches(sp, { "data", "shop", "receipts" }))
	table.clear(outbox)

	------------------------------------------------------------------ rate + urgent flush
	local sends, t = 0, 100
	session.lastSent = 0
	for frame = 1, 120 do -- 2 s at 60 fps, a change every frame
		t = 100 + frame / 60
		data.money += 1; session.dirty = true
		SessionService.flush(t)
	end
	sends = #outbox
	check(string.format("steady rate <= %.0f/s (got %d sends in 2 s)", 1 / GameConfig.REPLICATE_SECONDS, sends), sends <= math.ceil(2 / GameConfig.REPLICATE_SECONDS) and sends >= 3)
	table.clear(outbox)
	-- a remote action right after a send: goes out after REPLICATE_URGENT_SECONDS, not REPLICATE_SECONDS
	data.money += 1; session.dirty = true
	SessionService.flush(t + 0.5) -- regular send
	table.clear(outbox)
	invoke(player, "RequestState") -- any remote call marks the session urgent (here: also a new baseline)
	data.money += 7; SessionService.markDirty(session)
	SessionService.flush(t + 0.55)
	check("urgent: not before REPLICATE_URGENT_SECONDS", #outbox == 0)
	SessionService.flush(t + 0.5 + GameConfig.REPLICATE_URGENT_SECONDS + 0.01)
	check("urgent: sent right after REPLICATE_URGENT_SECONDS", #outbox == 1)
	table.clear(outbox)
	data.money += 1; session.dirty = true
	SessionService.flush(t + 0.5 + GameConfig.REPLICATE_URGENT_SECONDS + 0.05)
	check("without a new remote call back to the steady rate", #outbox == 0)
	table.clear(outbox)
	-- markDirty(session, true): prompt-driven actions (outside Remote.bind) can ask for the fast path
	local t2 = t + 5
	data.money += 1; session.dirty = true
	SessionService.flush(t2)
	table.clear(outbox)
	data.money += 2; SessionService.markDirty(session, true)
	SessionService.flush(t2 + GameConfig.REPLICATE_URGENT_SECONDS + 0.01)
	check("markDirty(session, true) takes the urgent path", #outbox == 1)
	table.clear(outbox)
	data.money += 2; SessionService.markDirty(session)
	SessionService.flush(t2 + 2 * GameConfig.REPLICATE_URGENT_SECONDS + 0.02)
	check("plain markDirty keeps the steady rate", #outbox == 0)
	table.clear(outbox)
	session.closed = true; session.dirty = true
	SessionService.flush(t + 20)
	check("closed session not sent", #outbox == 0)
	session.closed = false

	------------------------------------------------------------------ lazy counters
	session.sweptAt = 200
	local pid = data.empire.projectOrder[2]
	data.empire.projects[pid].visitors += 10
	session.dirty = true; session.lastSent = 0
	SessionService.flush(201)
	check("lazy counter (project visitors) waits", #outbox == 0 or not W.touches(outbox[1].msg.patch, { "data", "empire", "projects" }))
	table.clear(outbox)
	data.empire.projects[pid].visitors += 1; session.dirty = true
	SessionService.flush(200 + GameConfig.REPLICATE_LAZY_SECONDS + 0.1)
	check("lazy counter sent on the next sweep", outbox[1] and W.touches(outbox[1].msg.patch, { "data", "empire", "projects" }))
	table.clear(outbox)

	------------------------------------------------------------------ client StateController
	local Client = game.StarterPlayer.StarterPlayerScripts.Client
	local folder = RS:FindFirstChild("Remotes")
	local stateEvent = folder:FindFirstChild("State")
	local requests = 0
	local beforeReturn = nil -- runs after the server built the answer, before the client gets it
	local function patch(cls, name, fn) M.IMPL[cls].methods[name] = fn; M.classInfo(cls).methods[name] = fn end
	local legacy = nil
	patch("RemoteFunction", "InvokeServer", function(self, payload)
		if self.Name ~= "RequestState" then return { ok = false } end
		requests += 1
		if legacy then local l = legacy; legacy = nil; return W.wire({ ok = true, state = l }) end
		local result = W.wire(invoke(player, "RequestState", payload))
		if beforeReturn then local f = beforeReturn; beforeReturn = nil; f() end
		return result
	end)
	local State = M.require(Client.Controllers.StateController)
	local changes = 0
	State.onChange(function() changes += 1 end)
	local function deliver(msg) M.fire(stateEvent.OnClientEvent, W.wire(msg)) end
	local function serverView() return { data = (function() local v = table.clone(data); if v.shop then v.shop = table.clone(v.shop); v.shop.receipts = nil; v.shop.order = nil end return v end)(), live = session.live } end
	local function synced(label)
		local snap = State.snapshot
		local diff = if snap then W.equal({ data = snap.data, live = snap.live }, serverView()) else "no snapshot"
		check(label, diff == nil, diff)
	end
	local function step(change)
		change(); session.dirty = true; session.urgent = false; now += 1
		session.sweptAt = now -- full compare (lazy keys included) so the client must match exactly
		SessionService.flush(now)
		local msg = outbox[#outbox] and outbox[#outbox].msg
		table.clear(outbox)
		assert(msg, "step produced no State message")
		return msg
	end
	now = 1000 -- after the timing sections above
	State.init()
	M.settle(0.2)
	check("client: initial RequestState", requests == 1 and State.snapshot ~= nil)
	synced("client: initial state matches the server")
	local r0 = requests
	-- normal delta
	local m = step(function() data.money += 1000; data.empire.staffProfiles.engineer[2].n = "Renamed Person" end)
	local before = State.snapshot
	deliver(m)
	synced("client: delta applied")
	check("client: changed profile arrives", State.snapshot.data.empire.staffProfiles.engineer[2].n == "Renamed Person")
	check("client: snapshot object replaced (listeners see a new table)", State.snapshot ~= before)
	check("client: unchanged subtrees shared (no copy)", State.snapshot.data.models == before.data.models)
	check("client: no extra request", requests == r0)
	check("client: Workforce report follows live.workforce", Workforce.count(State.snapshot.data.empire, "marketer") == math.min(session.live.workforce.marketer, Workforce.capacity(State.snapshot.data.empire, "marketer")))
	local money0 = State.money()
	check("client: money extrapolation still uses data.money + live rates", math.abs(money0 - (data.money + (session.live.revenue - session.live.cost) * State.elapsed())) < 1e-6)
	-- missed delta -> one full request
	step(function() data.money += 1 end) -- lost
	m = step(function() data.money += 2 end)
	deliver(m)
	check("client: gap detected -> exactly one RequestState", requests == r0 + 1, requests - r0)
	synced("client: state after gap recovery matches the server")
	-- out of order: a delta arrives before the full snapshot it is based on (the mock cannot yield
	-- inside InvokeServer, so the newer delta is delivered while the answer is "on the way")
	r0 = requests
	local afterFull
	beforeReturn = function()
		afterFull = step(function() data.models[data.modelOrder[1]].name = "Renamed Model" end) -- based on the answer
		deliver(afterFull) -- arrives first: buffered, no second request
	end
	step(function() data.money += 3 end) -- lost
	m = step(function() data.money += 4 end)
	deliver(m) -- gap -> request
	M.settle(0.2)
	check("client: out-of-order -> still only one request", requests == r0 + 1, requests - r0)
	synced("client: buffered delta applied after the full snapshot")
	check("client: renamed model visible", State.snapshot.data.models[data.modelOrder[1]].name == "Renamed Model")
	-- duplicate / stale delta ignored
	local snapBefore = State.snapshot
	deliver(afterFull)
	check("client: duplicate delta ignored", State.snapshot == snapBefore and requests == r0 + 1)
	-- legacy full snapshot without seq (older server / test harness) is accepted, then resynced
	local n0 = changes
	deliver({ saveEnabled = false, serverTime = 1, data = W.wire(data), live = W.wire(session.live) })
	check("client: snapshot without seq accepted", changes == n0 + 1)
	r0 = requests
	m = step(function() data.money += 9 end)
	deliver(m)
	check("client: delta after a seq-less snapshot -> resync", requests == r0 + 1)
	synced("client: resynced")
	check("client: snapshot keeps the full shape", State.snapshot.saveEnabled ~= nil and State.snapshot.serverTime ~= nil and State.snapshot.data and State.snapshot.live)

	------------------------------------------------------------------ MarketService keeps foreign live fields
	local d2 = F.build(M, { userId = 2002, live = 2, seed = 9 })
	local p2 = { UserId = 2002, Name = "B", DisplayName = "B", Parent = game.Players }
	local s2 = { player = p2, userId = 2002, data = d2, live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} }, dirty = false, lastSent = 0, closed = false }
	SessionService.all()[p2] = s2
	s2.live.workforce = { researcher = 1, engineer = 2, curator = 3, marketer = 4, hour = 9 }
	s2.live.admin = true
	s2.live.campus = { hasCard = true }
	s2.live.empire = { board = {} }
	s2.live.studio = { gallery = {} }
	s2.live.arena = { rivals = {} }
	s2.live.rankings = { status = "x", boards = {} }
	local liveRef = s2.live
	MarketService.tickGlobal(1)
	MarketService.tick(s2, 1)
	check("market tick keeps live.workforce", s2.live.workforce and s2.live.workforce.marketer == 4)
	check("market tick keeps live.admin", s2.live.admin == true)
	check("market tick keeps campus/empire/studio/arena/rankings", s2.live.campus and s2.live.empire and s2.live.studio and s2.live.arena and s2.live.rankings and true)
	check("market tick updates its own fields", s2.live.users > 0 and s2.live.marketplace ~= nil and next(s2.live.perModel) ~= nil, s2.live.users)
	check("market tick keeps the live table (merge, no replace)", s2.live == liveRef)
	local perModelBefore = s2.live.perModel
	MarketService.tick(s2, 1)
	check("market-owned fields replaced each tick", s2.live.perModel ~= perModelBefore)
	SessionService.all()[p2] = nil
	check("all payloads were remote-safe", #W.problems == 0, W.problems[1])
end
local ok, err = M.runMain(body, { timeout = 1000, maxSteps = 5000000 })
if not ok then failc += 1; print("ERROR " .. tostring(err)) end
print(string.format("net tests: %d passed, %d failed", pass, failc))
