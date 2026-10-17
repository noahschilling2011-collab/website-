--!nocheck
-- probe: one abroad itinerary end to end with prints (development aid)
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_itinerary")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
for path, src in require("../world/stubs") do sources[path] = src end
M.loadTree(manifest, sources)
M.quiet = true
local G = M.G
local function body()
	local X = require("./common")(M, G)
	local Vector3, CFrame = G.Vector3, G.CFrame
	local p, s = X.newPlayer(7001, "Ava", 4)
	M.settle(1)
	X.advance(1.5)
	X.standAt(p, X.hqPoint(p, Vector3.new(0, 3, -60)))
	local trip = X.addTrip(s, "helix")
	local last = ""
	X.onTick = function()
		local st = X.state(p)
		local k = st and (tostring(st.state) .. "/" .. tostring(st.sub) .. " reason=" .. tostring(st.reason)) or "nil"
		if k ~= last then last = k; print(string.format("t=%.1f %s", X.T % 100000, k), p.root.Position, p.root.Anchored, X.City.state(p)) end
	end
	X.advance(3)
	local calls = X.Phone.calls(s)
	print("call:", calls[1] and calls[1].kind, calls[1] and calls[1].title)
	print(calls[1] and calls[1].text)
	local res = X.Phone._act(s, { action = "call", id = calls[1].id, answer = "accept" })
	print("accept:", res.ok, res.text, res.err)
	print("ride:", X.rideFolder(p) and X.rideFolder(p):GetAttribute("State"))
	X.waitFor(function() local rf = X.rideFolder(p); return rf and rf:GetAttribute("State") == "waiting" end, 120)
	print("board:", X.boardCar(p, s))
	X.waitFor(function() return X.state(p).state == "airport" end, 200)
	print("booking:", X.Shuttle.booking(p) and X.Shuttle.booking(p).prepaid)
	X.standAt(p, X.FP.HOME_GATES[1] + Vector3.new(2, 0, 3))
	local st0 = X.state(p)
	print("airport: departs in", st0.departs - X.T, "boardEnd in", st0.boardEnd - X.T, "pos", p.root.Position, "gate", X.FP.HOME_GATES[1])
	print("shuttle enabled", X.Shuttle.enabled(), "phase", X.FP.at(X.T).phase, X.FP.at(X.T).dir)
	X.waitFor(function() return X.state(p).state == "flight" end, 400)
	print("after wait: phase", X.FP.at(X.T).phase, X.FP.at(X.T).dir, "city", X.City.state(p), "booking", X.Shuttle.booking(p) ~= nil, "pos", p.root.Position)
	for i = 1, 12 do
		X.advance(30)
		local tr = X.City.trips[p.UserId]
		print("  flight t+", i * 30, X.FP.at(X.T).phase, X.FP.at(X.T).dir, "city", X.City.state(p), tr and tr.kind, tr and tr.arriving, tr and tr.arrived, "itin", X.state(p).state, X.state(p).sub, "pos", p.root.Position)
		if X.state(p).state == "limo" then break end
	end
	X.waitFor(function() local rf = X.rideFolder(p); return rf and rf:GetAttribute("State") == "waiting" end, 120)
	print("board limo:", X.boardCar(p, s))
	X.waitFor(function() return X.state(p).state == "meeting" end, 200)
	local key = X.IM.officeId("Helix Research")
	local q = X.meetingPrompt(key)
	print("prompt:", q, key)
	if q then
		X.standAt(p, q.Parent.Position + Vector3.new(0, 0, -4))
		X.firePrompt(q, p)
	end
	print("joined:", trip.joined)
	X.waitFor(function() return X.state(p).state == "hotel" end, 60)
	print("hotel view:", X.lastView(p).title, "|", X.lastView(p).line)
	local door = X.Drive.clientPlace("Helix Research").door.Position
	X.standAt(p, door)
	X.waitFor(function() local rf = X.rideFolder(p); return rf and rf:GetAttribute("State") == "waiting" end, 120)
	print("board hotel car:", X.boardCar(p, s))
	X.waitFor(function() return X.state(p).sub == "arrived" end, 200)
	local prompt = G.game.Workspace.ItineraryPrompts:FindFirstChild("ItinRoom_7001")
	print("room prompt:", prompt and prompt.RoomPrompt.ActionText, prompt and prompt.RoomPrompt.ObjectText)
	if prompt then X.standAt(p, prompt.Position + Vector3.new(0, 0, -3)); X.firePrompt(prompt.RoomPrompt, p) end
	print("checked in:", X.state(p).checkedIn, X.lastView(p).line)
	local r = X.act(s, { action = "leave" })
	print("leave:", r.ok, r.err)
	X.standAt(p, X.Drive.place("pm_hotel").door.Position)
	X.waitFor(function() local rf = X.rideFolder(p); return rf and rf:GetAttribute("State") == "waiting" end, 120)
	print("board limo2:", X.boardCar(p, s))
	X.waitFor(function() return X.state(p).sub == "gate" end, 200)
	X.standAt(p, X.FP.PM_GATES[1] + Vector3.new(2, 0, 2))
	X.waitFor(function() return X.state(p).state == "home" end, 600)
	X.waitFor(function() local rf = X.rideFolder(p); return rf and rf:GetAttribute("State") == "waiting" end, 200)
	print("board home:", X.boardCar(p, s))
	X.waitFor(function() return X.state(p).state == "none" end, 300)
	print("econ calls:", #X.econCalls)
	for _, n in X.notices(p) do print("  notice:", n) end
end
local ok, err = M.runMain(body, { timeout = 4000, maxSteps = 20000000 })
if not ok then print("CRASH " .. tostring(err)) end
