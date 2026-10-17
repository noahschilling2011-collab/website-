--!nocheck
-- Lead test: State replication. The first snapshot / RequestState are full; regular updates are deltas
-- (StatePatch) that leave out everything unchanged (e.g. staffProfiles) and the client StateController
-- rebuilds a complete snapshot from them, fetching the full state once when it misses a delta.
-- (Updated by the net package for the delta protocol; the full net suites live in tests/net/.)
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_leadtest && tools/luau tests/lead/test_snapshot.luau
local M = require("../../harness/mock")
M.loadTree(require("../../harness/.gen_leadtest/manifest"), require("../../harness/.gen_leadtest/sources"))
M.quiet = true
local G = M.G
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end
local function copy(v) if type(v) ~= "table" then return v end local t = {} for k, x in v do t[k] = copy(x) end return t end
local function touches(patch, path)
	local node = patch
	for i, key in path do
		if type(node) ~= "table" then return false end
		if node.s and node.s[key] ~= nil then return true end
		node = node.p and node.p[key]
		if node == nil then return false end
		if i == #path then return true end
	end
	return false
end
local function body()
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local Template = M.require(Server.Lib.Template)
	local EmpireMath = M.require(RS.Shared.EmpireMath)
	local Remote = M.require(Server.Lib.Remote)
	local SessionService = M.require(Server.Services.SessionService)
	local OWNER = 777
	local d = Template.new()
	d.empire.office = 2
	d.empire.employees = { researcher = 3, engineer = 2, curator = 0, marketer = 1 }
	EmpireMath.syncProfiles(d.empire, OWNER)
	local player = { UserId = OWNER, Name = "T" }
	local session = { player = player, userId = OWNER, data = d, live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} }, closed = false, dirty = true, lastSent = 0 }
	local sent = {}
	Remote.fire = function(_, name, msg) if name == "State" then table.insert(sent, msg) end end
	SessionService.all()[player] = session
	local now = 10
	local function flush() session.dirty = true; now += 1; table.clear(sent); SessionService.flush(now); return sent[1] end

	local s1 = flush()
	check("first snapshot is full", s1 and s1.data and s1.data.empire.staffProfiles ~= nil and s1.patch == nil)
	d.money += 10
	local s2 = flush()
	check("delta leaves unchanged profiles out", s2 and s2.patch and not touches(s2.patch, { "data", "empire", "staffProfiles" }) and touches(s2.patch, { "data", "money" }))
	check("session data untouched", d.empire.staffProfiles ~= nil and d.empire.staffProfilesOmitted == nil)
	local full = SessionService.snapshot(session)
	check("RequestState snapshot always full", full.data.empire.staffProfiles ~= nil and full.data.empire.office == 2)
	d.empire.staffProfiles.researcher[1].k = 5
	local s3 = flush()
	check("changed profile is sent", s3 and touches(s3.patch, { "data", "empire", "staffProfiles" }))
	d.money += 1
	check("then omitted again", not touches(flush().patch, { "data", "empire", "staffProfiles" }))
	d.empire.employees.engineer = 3
	EmpireMath.syncProfiles(d.empire, OWNER)
	check("hire is sent", touches(flush().patch, { "data", "empire", "staffProfiles" }))

	-- client side
	local folder = G.Instance.new("Folder"); folder.Name = "Remotes"
	local Net = M.require(RS.Shared.Net)
	for _, name in Net.FUNCTIONS do local f = G.Instance.new("RemoteFunction"); f.Name = name; f.Parent = folder end
	for _, name in Net.EVENTS do local e = G.Instance.new("RemoteEvent"); e.Name = name; e.Parent = folder end
	folder.Parent = RS
	local requests = 0
	local function patch(cls, name, fn) M.IMPL[cls].methods[name] = fn; M.classInfo(cls).methods[name] = fn end
	patch("RemoteFunction", "InvokeServer", function(self)
		if self.Name == "RequestState" then requests += 1; return copy({ ok = true, state = SessionService.snapshot(session) }) end
		return { ok = false }
	end)
	local State = M.require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.StateController)
	local stateEvent = folder:FindFirstChild("State")
	State.init()
	M.settle(0.1)
	check("client asked for the full state once", requests == 1 and State.snapshot ~= nil)
	local before = requests
	d.money += 1; flush() -- lost on the way
	d.money += 1
	M.fire(stateEvent.OnClientEvent, copy(flush()))
	M.settle(0.5)
	local snap = State.snapshot
	check("client got profiles after a missed delta", snap and snap.data.empire.staffProfiles ~= nil and requests - before == 1, requests - before)
	check("client money up to date", snap and snap.data.money == d.money)
	d.money += 1
	M.fire(stateEvent.OnClientEvent, copy(flush()))
	check("delta keeps the previous profiles", State.snapshot.data.empire.staffProfiles ~= nil and #State.snapshot.data.empire.staffProfiles.engineer == 3)
	d.empire.staffProfiles.engineer[2].n = "Renamed Person"
	M.fire(stateEvent.OnClientEvent, copy(flush()))
	check("changed profiles reach the client", State.snapshot.data.empire.staffProfiles.engineer[2].n == "Renamed Person")
	check("no further full requests", requests - before == 1)
end
local ok, err = M.runMain(body, { timeout = 100 })
if not ok then failc += 1; print("ERROR " .. tostring(err)) end
print(string.format("snapshot test: %d passed, %d failed", pass, failc))
