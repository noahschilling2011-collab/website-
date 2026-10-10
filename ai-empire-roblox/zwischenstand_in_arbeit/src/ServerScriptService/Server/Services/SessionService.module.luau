--!strict
-- Hält die geladenen Spielerdaten im Speicher, schickt Snapshots an den Client und speichert.
-- Andere Services verändern session.data und rufen danach SessionService.markDirty(session).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ModelConfig = require(ReplicatedStorage.Shared.Config.ModelConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(script.Parent.Parent.Lib.ServerTypes)
local StatePatch = require(ReplicatedStorage.Shared.StatePatch)
local CompanyOps = require(ReplicatedStorage.Shared.CompanyOps)
local Remote = require(script.Parent.Parent.Lib.Remote)
local SaveService = require(script.Parent.SaveService)

type Session = ServerTypes.Session

local SessionService = {}

local sessions: { [Player]: Session } = {}
local loadedCallbacks: { (Session) -> () } = {}
local closingCallbacks: { (Session) -> () } = {}

local function emptyLive(): Types.LiveInfo
	return { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} }
end

function SessionService.get(player: Player): Session?
	return sessions[player]
end

function SessionService.all(): { [Player]: Session }
	return sessions
end

-- urgent = true: a direct player action outside Remote.bind (e.g. a ProximityPrompt) — send after
-- REPLICATE_URGENT_SECONDS instead of the steady REPLICATE_SECONDS. Remote calls are urgent anyway.
function SessionService.markDirty(session: Session, urgent: boolean?)
	session.dirty = true
	if urgent then
		session.urgent = true
	end
end

function SessionService.onLoaded(callback: (Session) -> ())
	table.insert(loadedCallbacks, callback)
end

function SessionService.onClosing(callback: (Session) -> ())
	table.insert(closingCallbacks, callback)
end

-- Replication (State remote). The first snapshot and every RequestState answer are FULL and reset
-- the per-player baseline (session.shadow = private copy of what was sent). Regular updates are
-- DELTAS: StatePatch.diff sends only values that changed since the last send to THAT player, the
-- client applies them onto its copy (StateController). seq/base let the client detect a missing
-- delta; it then fetches the full state once via RequestState.
-- Rate: at most every REPLICATE_SECONDS; right after a remote call of the player (the session
-- provider below marks it urgent) already after REPLICATE_URGENT_SECONDS, so actions feel instant.

-- data.shop.* entries the client never needs (purchase receipts / processed order ids): never sent
local SERVER_ONLY_SHOP_KEYS = { "receipts", "order" }

-- Counters that change every simulation second but are secondary on screen: compared (and sent)
-- only every REPLICATE_LAZY_SECONDS. Everything else in the same tables (new entries, status,
-- prices, removals) still goes out immediately. Root = { data, live }; "*" = every entry.
-- CORE_SPEC 11.8: the company log (deals.news), trust bars, the broke timer, the P&L ledger and the
-- per-minute company summary (live.ops), waitlist and load change every second but are secondary: every 5 s.
-- Marketplace offers: users and the version age (vage, +1 per second for every live model on the server).
local LAZY: StatePatch.Lazy = {
	data = { empire = {
		projects = { ["*"] = { visitors = true, revenueTotal = true } },
		deals = { news = true, trust = true, broke = true },
		ledger = true,
	} },
	live = {
		studio = { gallery = { ["*"] = { visitors = true, revenueTotal = true } } },
		marketplace = { offers = { ["*"] = { users = true, vage = true } } },
		ops = true,
		waitlist = true,
		load = true,
		demand = true,
	},
}

SessionService.LAZY = LAZY

-- What the client gets of the company state (CORE_SPEC 11.8 byte budget: deals <= 3 KB, ledger <= 2.5 KB):
--  * the company log keeps CompanyOps.NEWS_MAX (40) lines in the save; the phone shows the newest NEWS_SHOWN (20);
--  * trust bars to 0.001 (shown as "trust 67 %"; the save keeps the exact value);
--  * accounts as {expires, renewing?} and trips as {client, kind, back, founder?, hosted?}: what the screens and
--    CompanyOps on the client (presence / travellers, guest-house guests) read; since, crew and left stay
--    server-side (live.ops.trips carries the crew of every trip);
--  * the P&L ledger: the newest LEDGER_SHOWN company days of the LEDGER_DAYS saved.
local NEWS_SHOWN = CompanyOps.NEWS_SHOWN
local LEDGER_SHOWN = CompanyOps.LEDGER_SHOWN

local function compactDeals(deals: any): any
	local out = table.clone(deals)
	local news = deals.news
	if type(news) == "table" and #news > NEWS_SHOWN then
		out.news = table.move(news, 1, NEWS_SHOWN, 1, {})
	end
	if type(deals.trust) == "table" then
		local trust = {}
		for id, t in deals.trust do
			trust[id] = if type(t) == "number" then math.floor(t * 1000 + 0.5) / 1000 else t
		end
		out.trust = trust
	end
	if type(deals.accounts) == "table" then
		local accounts = {}
		for id, acc in deals.accounts do
			if type(acc) == "table" then
				accounts[id] = if acc.renewing == true then { expires = acc.expires, renewing = true } else { expires = acc.expires }
			end
		end
		out.accounts = accounts
	end
	if type(deals.tripList) == "table" then
		local trips = {}
		for _, t in deals.tripList do
			if type(t) == "table" then
				table.insert(trips, { client = t.client, kind = t.kind, back = t.back, founder = if t.founder == true then true else nil, hosted = if t.hosted == true then true else nil })
			end
		end
		out.tripList = trips
	end
	return out
end

local function newestDays(ledger: any): any
	local keys = {}
	for key in ledger do
		local n = tonumber(key)
		if n then table.insert(keys, n) end
	end
	if #keys <= LEDGER_SHOWN then
		return ledger
	end
	table.sort(keys, function(a: number, b: number): boolean return a > b end)
	local out = {}
	for i = 1, LEDGER_SHOWN do
		local key = tostring(keys[i])
		out[key] = ledger[key]
	end
	return out
end

-- data may already be a shallow clone (cloned = true): then it is changed in place
local function trimCompany(data: any, cloned: boolean): any
	local e = data.empire
	if type(e) ~= "table" then
		return data
	end
	local deals = e.deals
	local ledger = e.ledger
	if type(deals) ~= "table" and type(ledger) ~= "table" then
		return data
	end
	local trimmedEmpire = table.clone(e)
	if type(deals) == "table" then
		trimmedEmpire.deals = compactDeals(deals)
	end
	if type(ledger) == "table" then
		trimmedEmpire.ledger = newestDays(ledger)
	end
	local trimmed = if cloned then data else table.clone(data)
	trimmed.empire = trimmedEmpire
	return trimmed
end

-- What the client gets of data: server-only shop records stripped, the company state trimmed (above).
-- Shallow clones only along the changed paths (the save table itself is never modified).
function SessionService.replicatedData(data: Types.PlayerData): Types.PlayerData
	local out: any = data
	local cloned = false
	local shop = (data :: any).shop
	if type(shop) == "table" then
		local strip = false
		for _, key in SERVER_ONLY_SHOP_KEYS do
			if shop[key] ~= nil then
				strip = true
			end
		end
		if strip then
			local trimmedShop = table.clone(shop)
			for _, key in SERVER_ONLY_SHOP_KEYS do
				trimmedShop[key] = nil
			end
			out = table.clone(data)
			out.shop = trimmedShop
			cloned = true
		end
	end
	return trimCompany(out, cloned)
end
local replicatedData = SessionService.replicatedData

local function nextSeq(session: Session): number
	local seq = (session.seq or 0) + 1
	session.seq = seq
	return seq
end

-- Full snapshot (first send, RequestState). Resets the delta baseline for this player.
function SessionService.snapshot(session: Session): Types.Snapshot
	local data = replicatedData(session.data)
	local live = session.live
	session.shadow = StatePatch.copy({ data = data, live = live })
	return {
		seq = nextSeq(session),
		saveEnabled = SaveService.enabled,
		serverTime = workspace:GetServerTimeNow(),
		data = data,
		live = live,
	}
end

-- Changes since the last snapshot sent to this player. nil when nothing changed or when there is no
-- baseline yet (SessionService.snapshot creates it). lazy = true skips the LAZY counters this time.
function SessionService.delta(session: Session, lazy: boolean?): Types.StateDelta?
	local shadow = session.shadow
	if shadow == nil then
		return nil
	end
	local root = { data = replicatedData(session.data), live = session.live }
	local patch = StatePatch.diff(shadow, root, if lazy then LAZY else nil)
	if patch == nil then
		return nil
	end
	local base = session.seq or 0
	return {
		seq = nextSeq(session),
		base = base,
		saveEnabled = SaveService.enabled,
		serverTime = workspace:GetServerTimeNow(),
		patch = patch,
	}
end

-- Sends changed sessions to their clients (see the replication note above)
function SessionService.flush(now: number)
	for _, session in sessions do
		if session.dirty and not session.closed then
			local gap = now - session.lastSent
			if gap >= GameConfig.REPLICATE_SECONDS or (session.urgent and gap >= GameConfig.REPLICATE_URGENT_SECONDS) then
				session.dirty = false
				session.urgent = false
				session.lastSent = now
				if session.shadow == nil then
					session.sweptAt = now
					Remote.fire(session.player, "State", SessionService.snapshot(session))
				else
					local sweep = now - (session.sweptAt or 0) >= GameConfig.REPLICATE_LAZY_SECONDS
					if sweep then
						session.sweptAt = now
					end
					local delta = SessionService.delta(session, not sweep)
					if delta then
						Remote.fire(session.player, "State", delta)
					end
				end
			end
		end
	end
end

local function saveSession(session: Session, release: boolean)
	local _, lostLock = SaveService.save(session.userId, session.data, release)
	if lostLock and not release then
		-- Ein anderer Server hat übernommen: hier nichts mehr verändern oder speichern
		session.closed = true
		session.player:Kick("AI Empire: Your company was opened on another server.")
	end
end

function SessionService.autosave(now: number)
	for _, session in sessions do
		if not session.saving and not session.closed and now >= session.nextSaveAt then
			session.saving = true
			session.nextSaveAt = now + GameConfig.AUTOSAVE_SECONDS
			task.spawn(function()
				saveSession(session, false)
				session.saving = false
			end)
		end
	end
end

local function onPlayerAdded(player: Player)
	local data, reason = SaveService.load(player.UserId)
	if player.Parent == nil then
		-- schon wieder weg, während wir geladen haben
		if data then
			SaveService.releaseLock(player.UserId)
		end
		return
	end
	if not data then
		player:Kick(`AI Empire: Your save could not be loaded ({reason}). Please rejoin in a minute.`)
		return
	end

	-- Ein offenes Trainings-Event aus der letzten Sitzung bekommt einen frischen Timer
	local training = data.training
	if training and training.event and training.event.pending then
		training.event.expiresAt = workspace:GetServerTimeNow() + ModelConfig.TRAINING.decisionTimeout
	end

	local now = os.clock()
	local session: Session = {
		player = player,
		userId = player.UserId,
		data = data,
		live = emptyLive(),
		dirty = true,
		lastSent = 0,
		nextSaveAt = now + GameConfig.AUTOSAVE_SECONDS + math.random() * 15, -- gestaffelt
		saving = false,
		closed = false,
		released = false,
		rng = Random.new(),
	}
	sessions[player] = session
	for _, callback in loadedCallbacks do
		task.spawn(callback, session)
	end
end

local function closeSession(player: Player)
	local session = sessions[player]
	if not session or session.released then
		return -- unbekannt oder wird schon geschlossen (PlayerRemoving + BindToClose gleichzeitig)
	end
	session.released = true
	local lockLost = session.closed -- closed ohne released = anderer Server hat übernommen
	session.closed = true
	for _, callback in closingCallbacks do
		local ok, err = pcall(callback :: (Session) -> any, session)
		if not ok then
			warn("[Session] closing callback:", err)
		end
	end
	if not lockLost then
		-- laufenden Autosave abwarten, dann final speichern und Lock freigeben
		local waited = 0
		while session.saving and waited < 15 do
			task.wait(0.2)
			waited += 0.2
		end
		session.saving = true
		saveSession(session, true)
	end
	sessions[player] = nil
end

function SessionService.init()
	-- Remote.bind asks for the session on every (rate-limit approved) remote call of the player:
	-- whatever the handler changes goes out on the next Heartbeat instead of the steady cadence.
	Remote.setSessionProvider(function(player: Player): Session?
		local session = sessions[player]
		if session then
			session.urgent = true
		end
		return session
	end)

	Remote.bind("RequestState", { burst = 4, perSecond = 1 }, function(session, _payload)
		return { ok = true, state = SessionService.snapshot(session) }
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(closeSession)

	game:BindToClose(function()
		local pending = 0
		local players = {}
		for player in sessions do
			table.insert(players, player)
		end
		for _, player in players do
			pending += 1
			task.spawn(function()
				closeSession(player)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.25)
		end
	end)
end

return SessionService
