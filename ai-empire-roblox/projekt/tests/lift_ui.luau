--!nocheck
-- Smoke test of the lift cabin panel UI in CampusController (headless mock, stubbed network).
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_lift && tools/luau tests/lift_ui.luau
local M = require("../harness/mock")
local manifest = require("../harness/.gen_lift/manifest")
local sources = require("../harness/.gen_lift/sources")
M.loadTree(manifest, sources)
M.quiet = true
local KEY, G = M.KEY, M.G
local game = M.game

local passed, failed = 0, 0
local function check(cond, name)
	if cond then passed += 1 else failed += 1; print("FAIL: " .. name) end
end
local function find(path)
	local cur = game
	for seg in path:gmatch("[^%.]+") do cur = cur:FindFirstChild(seg); assert(cur, path) end
	return cur
end

local function body()
	local Instance, Vector3, CFrame = G.Instance, G.Vector3, G.CFrame
	local Players = game:GetService("Players")
	local me = M.newInstance("Player")
	me[KEY].props.Name = "Me"
	me[KEY].props.UserId = 5
	me.Parent = Players
	local gui = M.newInstance("PlayerGui"); gui.Name = "PlayerGui"; gui.Parent = me
	local character = Instance.new("Model"); character.Name = "Me"
	local root = Instance.new("Part"); root.Name = "HumanoidRootPart"; root.CFrame = CFrame.new(0, 3, 60); root.Parent = character
	Instance.new("Humanoid").Parent = character
	character.Parent = G.workspace
	me[KEY].props.Character = character
	M.classInfo("Players").get.LocalPlayer = function() return me end

	local listener
	local calls = {}
	local reply = { ok = true, kind = "car" }
	local stubs = {
		StateController = { onNotify = function(fn) listener = fn end },
		ActionController = {
			call = function(name, payload, silent)
				table.insert(calls, { name = name, payload = payload, silent = silent })
				if reply.ok then return true, reply end
				return false, reply
			end,
			message = function(err) return if err == "LIFT_NOT_PASSENGER" then "Step inside the lift to choose a floor." else "Something went wrong." end,
		},
	}
	local toasts = {}
	local mod = find("StarterPlayer.StarterPlayerScripts.Client.Controllers.CampusController")
	local fn = loadstring(sources[mod[KEY].file], "=CampusController")
	setfenv(fn, setmetatable({
		script = mod,
		require = function(m)
			if stubs[m.Name] then return stubs[m.Name] end
			if m.Name == "Net" then return { getEvent = function() return { FireServer = function() end } end } end
			local real = M.require(m)
			if m.Name == "Toast" then
				return { show = function(kind, text) table.insert(toasts, { kind, text }); return real.show(kind, text) end }
			end
			return real
		end,
	}, { __index = G }))
	local Controller = fn()
	Controller.init()
	check(type(listener) == "function", "notify listener registered")

	local stops = {
		{ level = -1, label = "B1", name = "Garage, fleet & building services", allowed = true },
		{ level = 0, label = "G", name = "Reception, atrium, café & compute", allowed = true },
		{ level = 1, label = "1", name = "Data & model foundations", allowed = true },
		{ level = 2, label = "2", name = "Founder suite & boardroom", allowed = false },
		{ level = 3, label = "R", name = "Roof terrace", allowed = true },
	}
	listener("LIFT_PANEL", { ownerId = 1001, current = 0, passenger = true, state = "IDLE", stops = stops })
	M.settle(0.1)
	local screen = gui:FindFirstChild("CampusLift")
	check(screen ~= nil and screen:IsA("ScreenGui") and screen.ResetOnSpawn == false, "panel ScreenGui created")
	local buttons, byText = {}, {}
	for _, d in screen:GetDescendants() do
		if d:IsA("TextButton") then table.insert(buttons, d); byText[d.Text] = d end
	end
	check(#buttons == #stops + 1, "one button per stop + Close (" .. #buttons .. ")")
	local g = byText["G  ·  Reception, atrium, café & compute"]
	check(g ~= nil, "button label format 'G  ·  name'")
	local locked = byText["2  ·  Founder suite & boardroom"]
	check(locked and locked:GetAttribute("Disabled") == true and locked.Selectable == false, "not allowed -> disabled and not selectable")
	check(g and g:FindFirstChildOfClass("UIStroke") ~= nil, "current level highlighted")
	local title = false
	for _, d in screen:GetDescendants() do if d:IsA("TextLabel") and d.Text == "Lift · choose a floor" then title = true end end
	check(title, "title text")
	-- top floor first
	local roof = byText["R  ·  Roof terrace"]
	check(roof and g and roof.LayoutOrder < g.LayoutOrder, "top floor listed first")
	-- disabled button ignores clicks
	M.fire(M.getSignal(locked[KEY], "Activated"))
	M.settle(0.1)
	check(#calls == 0, "disabled button does not call the server")
	-- choose R
	M.fire(M.getSignal(roof[KEY], "Activated"))
	M.settle(0.1)
	check(#calls == 1 and calls[1].name == "UseCampusLift" and calls[1].payload.ownerId == 1001 and calls[1].payload.floor == 3, "calls UseCampusLift {ownerId, floor}")
	check(screen.Parent == nil, "closes on success")
	-- failure keeps the panel and shows a message
	reply = { ok = false, err = "LIFT_FLOOR_LOCKED" }
	listener("LIFT_PANEL", { ownerId = 1001, current = 1, passenger = false, stops = stops })
	M.settle(0.1)
	screen = gui:FindFirstChild("CampusLift")
	local one
	for _, d in screen:GetDescendants() do if d:IsA("TextButton") and d.Text:sub(1, 1) == "1" then one = d end end
	M.fire(M.getSignal(one[KEY], "Activated"))
	M.settle(0.1)
	check(screen.Parent ~= nil, "panel stays open on error")
	check(toasts[#toasts] and toasts[#toasts][2] == "Your card does not open that floor.", "lift-specific fallback message")
	-- close button
	local close
	for _, d in screen:GetDescendants() do if d:IsA("TextButton") and d.Text == "Close" then close = d end end
	M.fire(M.getSignal(close[KEY], "Activated"))
	check(screen.Parent == nil, "Close button closes")
	-- walking away closes the panel
	listener("LIFT_PANEL", { ownerId = 1001, current = 0, passenger = true, stops = stops })
	screen = gui:FindFirstChild("CampusLift")
	root.CFrame = CFrame.new(0, 40, 60) -- riding up: stays open
	M.settle(1.2)
	check(screen.Parent ~= nil, "vertical travel keeps the panel open")
	root.CFrame = CFrame.new(30, 40, 60)
	M.settle(1.2)
	check(screen.Parent == nil, "walking away closes the panel")
	-- notices
	listener("LIFT_CALLED", { level = 2, label = "2", state = "queued" })
	check(toasts[#toasts][1] == "success" and toasts[#toasts][2]:find("Lift called to 2", 1, true) ~= nil, "LIFT_CALLED toast")
	listener("CAMPUS_NOTICE", { text = "LIFT_NOT_PASSENGER" })
	check(toasts[#toasts][2] == "Step inside the lift to choose a floor.", "error codes in notices become messages")
	listener("CAMPUS_NOTICE", { text = "Snack added to your backpack." })
	check(toasts[#toasts][1] == "info" and toasts[#toasts][2] == "Snack added to your backpack.", "plain notices unchanged")
end

setfenv(body, M.envFor(nil))
local ok, res = M.runMain(body, { timeout = 120 })
if not ok then print("ERROR: " .. tostring(res)); failed += 1 end
print(string.format("lift_ui: %d passed, %d failed", passed, failed))
if failed > 0 then error("lift_ui tests failed") end
