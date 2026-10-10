--!nocheck
-- Package "life" · props: (1) PropFx registration contract of every prop the room kits build (real
-- HeadquartersDesign, tiers 1-4), (2) FacilityService prop/fixture actions only write state attributes
-- (FxUntil / PlayerUntil) and never a CFrame, with the cooldown and the new "guest" refusal text.
-- Run: python3 tests/life/mkharness.py && tools/luau tests/life/test_props.luau -a [contract|facility|negative] [tier]
--   negative: the facility checks against the ORIGINAL FacilityService (must report failures).
local M = require("../../harness/mock")
local args = { ... }
local MODE = args[1] or "all"
local ONLY_TIER = tonumber(args[2])
local gen = if MODE == "negative" then "gen_neg" else "gen"
M.loadTree(require("./" .. gen .. "/manifest"), require("./" .. gen .. "/sources"))
M.quiet = true
local G = M.G
local say = print
local pass, failc = 0, 0
local failures = {}
local function check(name, ok, detail)
	if ok then pass += 1 return end
	failc += 1
	if not failures[name] then
		failures[name] = 0
		say("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else ""))
	end
	failures[name] += 1
end

local KINDS = { spin = true, belt = true, flow = true, steam = true, flame = true, blink = true, hinge = true, slider = true, paper = true, screen = true, arm = true, breathe = true, leds = true, ticker = true }
local MOTION = { spin = true, belt = true, slider = true, hinge = true, arm = true }
local GATES = { Training = true, Hour = true, Lift = true, Meeting = true }
local REQUIRED_IDS = { "Range", "KitchenCoffeeMachine", "Servery", "DishStation", "KitchenSink", "Pass", "CardPrinter", "CarLift", "EVCharger2", "EVCharger4", "MailLockers", "SaunaHeater", "ITBench", "RobotArm1", "RobotArm2", "TestRig", "GarageVending", "AtriumCooler", "WellnessWater" }

local function body()
	local Instance, Vector3, CFrame, Color3 = G.Instance, G.Vector3, G.CFrame, G.Color3
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local Services = Server.Services
	local Collection = game:GetService("CollectionService")
	local Template = M.require(Server.Lib.Template)
	local EmpireConfig = M.require(RS.Shared.Config.EmpireConfig)
	local Design = M.require(Services.HeadquartersDesign)
	local OWNER = 1001
	local cf = CFrame.lookAt(Vector3.new(160, 24, 252), Vector3.new(160, 24, 0))
	local function build(tier)
		local d = Template.new()
		d.company = { name = "Nimbus Labs", logo = "N", color = "cyan", spec = "general", reputation = 10, foundedAt = 0 }
		d.empire.office = M.require(RS.Shared.Config.BuildingPlan).officeForTier(tier) -- econ: save office index of this plan tier (DATA_VERSION 6)
		local cap = EmpireConfig.OFFICES[d.empire.office].staff
		for k, role in EmpireConfig.ROLES do d.empire.employees[role.id] = math.floor(cap / #EmpireConfig.ROLES) + (if k <= cap % #EmpireConfig.ROLES then 1 else 0) end
		local session = { userId = OWNER, player = { Name = "Tester", DisplayName = "Tester", UserId = OWNER }, data = d, live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} } }
		local office = Design.build(cf, session, Color3.fromRGB(120, 154, 129))
		local plots = G.workspace:FindFirstChild("Plots") or Instance.new("Folder")
		plots.Name = "Plots"; plots.Parent = G.workspace
		local plot = Instance.new("Model"); plot.Name = "Plot_" .. tier; plot.Parent = plots
		office.Parent = plot
		return office, session, plot
	end

	------------------------------------------------------------------ (1) registration contract
	local function contract(tier)
		local office = build(tier)
		local stations, meetings, propIds = {}, {}, {}
		for _, d in office:GetDescendants() do
			local wid = d:GetAttribute("WorkstationId")
			if wid ~= nil then stations[wid] = d end
			local mr = d:GetAttribute("MeetingRoom")
			if typeof(mr) == "string" then meetings[mr] = true end
		end
		local counts, roots = {}, 0
		for _, root in Collection:GetTagged("PropFx") do
			if not root:IsDescendantOf(office) then continue end
			roots += 1
			local label = root:GetFullName()
			check("root is BasePart or Model", root:IsA("BasePart") or root:IsA("Model"), label)
			local fx = root:GetAttribute("Fx")
			check("Fx attribute", typeof(fx) == "string" and fx ~= "", label)
			local kinds, motion = {}, 0
			for kind in string.gmatch(fx or "", "[%a]+") do
				check("known kind " .. kind, KINDS[kind] == true, label)
				kinds[kind] = true
				counts[kind] = (counts[kind] or 0) + 1
				if MOTION[kind] then motion += 1 end
			end
			check("at most one motion kind", motion <= 1, label)
			local axis = root:GetAttribute("FxAxis")
			check("FxAxis valid", axis == nil or axis == "x" or axis == "y" or axis == "z", label)
			check("no FxUntil at build", root:GetAttribute("FxUntil") == nil, label)
			-- parts that move
			local parts = {}
			if root:IsA("BasePart") then table.insert(parts, root) end
			local flagged, emitters, fires, glow, show, guis, links = false, {}, {}, 0, 0, 0, 0
			for _, d in root:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(parts, d)
					if d:GetAttribute("FxMove") == true then flagged = true end
				elseif d:IsA("ParticleEmitter") then table.insert(emitters, d)
				elseif d:IsA("Fire") then table.insert(fires, d)
				elseif d:IsA("SurfaceGui") then guis += 1 end
			end
			for _, p in parts do
				if p:GetAttribute("FxGlow") == true then glow += 1 end
				if typeof(p:GetAttribute("FxShow")) == "number" then show += 1 end
				if typeof(p:GetAttribute("FxLink")) == "number" then links += 1 end
			end
			if motion > 0 then
				for _, p in parts do
					local moves = root:IsA("BasePart") or (kinds.arm and typeof(p:GetAttribute("FxLink")) == "number") or (not kinds.arm and ((not flagged) or p:GetAttribute("FxMove") == true))
					if moves then
						check("moving part anchored", p.Anchored == true, p:GetFullName())
						check("moving part never collides", p.CanCollide == false, p:GetFullName())
						check("moving part is no Seat", not p:IsA("Seat"), p:GetFullName())
					end
				end
				check("motion prop has parts", #parts > 0, label)
			end
			if root:IsA("Model") and #parts > 1 then
				check("multi-part prop streams atomically", root.ModelStreamingMode == G.Enum.ModelStreamingMode.Atomic, label)
			end
			if kinds.hinge then check("hinge has FxHinge + FxTravel", typeof(root:GetAttribute("FxHinge")) == "Vector3" and (root:GetAttribute("FxTravel") or 0) ~= 0, label) end
			if kinds.slider then check("slider has FxTravel", (root:GetAttribute("FxTravel") or 0) ~= 0, label) end
			if kinds.belt then check("belt has FxTravel > 0", (root:GetAttribute("FxTravel") or 0) > 0, label) end
			if kinds.arm then
				check("arm is a Model with joints", root:IsA("Model") and typeof(root:GetAttribute("FxJoint1")) == "CFrame" and typeof(root:GetAttribute("FxJoint2")) == "CFrame" and typeof(root:GetAttribute("FxJoint3")) == "CFrame", label)
				check("arm has linked parts", links >= 3, label)
			end
			if kinds.steam then
				check("steam has an emitter", #emitters > 0, label)
				for _, e in emitters do check("emitter prebuilt disabled", e.Enabled == false, e:GetFullName()) end
			end
			if kinds.flame then
				check("flame has a Fire", #fires > 0, label)
				for _, f in fires do check("fire prebuilt disabled", f.Enabled == false, f:GetFullName()) end
			end
			if kinds.blink then check("blink has FxColor and a glow part", typeof(root:GetAttribute("FxColor")) == "Color3" and (glow > 0 or root:IsA("BasePart")), label) end
			if kinds.flow then check("flow shows parts or bobs", show > 0 or root:IsA("BasePart") or (root:GetAttribute("FxTravel") or 0) ~= 0, label) end
			if kinds.screen or kinds.leds or kinds.ticker then check("screen-like kind has a SurfaceGui", guis > 0, label) end
			if kinds.breathe then check("breathe on a rack blade", root:IsA("BasePart") and root.Name == "RackBlade", label) end
			local station = root:GetAttribute("FxStation")
			if station ~= nil then check("FxStation refers to a station", stations[station] ~= nil, label .. " -> " .. tostring(station)) end
			local gate = root:GetAttribute("FxGate")
			if gate ~= nil then check("FxGate known", GATES[gate] == true, label .. " " .. tostring(gate)) end
			if gate == "Meeting" then check("FxMeeting names a meeting room", meetings[root:GetAttribute("FxMeeting")] == true, label .. " " .. tostring(root:GetAttribute("FxMeeting"))) end
			local pid = root:GetAttribute("PropId")
			if pid ~= nil then
				check("PropId unique per office", propIds[pid] == nil, pid)
				propIds[pid] = root
			end
		end
		for _, id in REQUIRED_IDS do check("tier " .. tier .. " has prop " .. id, propIds[id] ~= nil) end
		-- every "prop" prompt sits on (or under) a PropFx root; every post job prop exists
		local propPrompts = 0
		for _, q in office:GetDescendants() do
			if q:IsA("ProximityPrompt") and q:GetAttribute("CampusAction") == "prop" then
				propPrompts += 1
				local node, found = q.Parent, false
				while node and node ~= office do
					if Collection:HasTag(node, "PropFx") then found = true; break end
					node = node.Parent
				end
				-- a prompt beside its prop names it by PropId (prompt Value)
				found = found or (typeof(q:GetAttribute("Value")) == "string" and propIds[q:GetAttribute("Value")] ~= nil)
				check("prop prompt has a PropFx root", found, q:GetFullName())
				check("prop prompt parent is a BasePart", q.Parent:IsA("BasePart"), q:GetFullName())
			end
			if q:IsA("Model") and q:GetAttribute("OpsIndex") ~= nil then
				for name, value in q:GetAttributes() do
					if string.sub(name, 1, 8) == "JobProp_" then check("job prop exists " .. value, propIds[value] ~= nil, q.Name .. "." .. name) end
					if string.sub(name, 1, 9) == "JobPoint_" then
						check("job point has a look-at", typeof(q:GetAttribute("JobFace_" .. string.sub(name, 10))) == "Vector3", q.Name .. "." .. name)
					end
				end
			end
		end
		check("tier " .. tier .. " prop prompts", propPrompts >= 20, propPrompts)
		local kinds = {}
		for k, n in counts do table.insert(kinds, k .. "=" .. n) end
		table.sort(kinds)
		say(string.format("tier %d: %d PropFx roots, %d prop prompts, %d PropIds · %s", tier, roots, propPrompts, (function() local n = 0; for _ in propIds do n += 1 end; return n end)(), table.concat(kinds, " ")))
		office.Parent.Parent = nil
	end

	------------------------------------------------------------------ (2) FacilityService actions
	local function facility()
		-- FacilityService throttles with os.clock(): give the mock environment a virtual clock
		local realOs = os
		G.os = setmetatable({ clock = function() return M.Sched.now end }, { __index = realOs })
		local SessionStub = M.require(Services.SessionService)
		local PlotStub = M.require(Services.PlotService)
		PlotStub.arrival = function(p) return p.cframe * CFrame.new(0, 3, -104) end
		local Remote = M.require(Server.Lib.Remote)
		local Plan = M.require(RS.Shared.Config.BuildingPlan)
		local Facility = M.require(Services.FacilityService)
		local tier = 2
		local office, session, plotModel = build(tier)
		-- owner + a visitor with a guest card
		local function fakePlayer(id, name)
			local char = Instance.new("Model"); char.Name = name
			local hrp = Instance.new("Part"); hrp.Name = "HumanoidRootPart"; hrp.Anchored = true; hrp.Parent = char; char.PrimaryPart = hrp
			local hum = Instance.new("Humanoid"); hum.Parent = char
			char.Parent = G.workspace
			local bag = Instance.new("Backpack")
			local player = { UserId = id, Name = name, DisplayName = name, Character = char, Parent = G.workspace }
			function player.FindFirstChildOfClass(_, cls) if cls == "Backpack" then return bag end return nil end
			return player, hrp
		end
		local owner, ownerRoot = fakePlayer(OWNER, "Founder")
		session.player = owner; session.closed = false
		local visitor, visitorRoot = fakePlayer(2002, "Visitor")
		local vsession = { userId = 2002, player = visitor, data = Template.new(), live = {}, closed = false }
		SessionStub.sessions = { session, vsession }
		PlotStub.plots = { { owner = owner, office = office, cframe = cf, model = plotModel } }
		-- PropFx part CFrames before
		local before, nParts = {}, 0
		for _, root in Collection:GetTagged("PropFx") do
			if root:IsDescendantOf(office) then
				for _, p in (if root:IsA("BasePart") then { root } else {}) do before[p] = p.CFrame; nParts += 1 end
				for _, p in root:GetDescendants() do if p:IsA("BasePart") then before[p] = p.CFrame; nParts += 1 end end
			end
		end
		local clock = 0
		local function advance(seconds)
			local steps = math.ceil(seconds / 0.05)
			for _ = 1, steps do
				clock += 0.05
				M.Sched.now += 0.05
				Facility.tick(0.05)
			end
		end
		local function promptsWith(action, value)
			local out = {}
			for _, q in office:GetDescendants() do
				if q:IsA("ProximityPrompt") and q:GetAttribute("CampusAction") == action and (value == nil or q:GetAttribute("Value") == value) then table.insert(out, q) end
			end
			return out
		end
		local function use(player, root, q)
			root.CFrame = q.Parent.CFrame * CFrame.new(0, 0, -2)
			advance(0.35) -- prompt throttle 0.3 s
			Facility.handle(player, q)
		end
		local function rootOf(inst, q)
			local node = inst
			while node and node ~= office do
				if Collection:HasTag(node, "PropFx") then return node end
				node = node.Parent
			end
			local id = q and q:GetAttribute("Value")
			for _, r in Collection:GetTagged("PropFx") do if r:IsDescendantOf(office) and id ~= nil and r:GetAttribute("PropId") == id then return r end end
			return nil
		end
		-- generic prop action: every prop prompt sets FxUntil = now + FxSeconds; second use within the
		-- cooldown is refused with a notice
		local props = promptsWith("prop")
		check("facility: prop prompts found", #props >= 15, #props)
		local okProps = 0
		for _, q in props do
			if q:GetAttribute("OwnerOnly") == true then continue end
			local root = rootOf(q.Parent, q)
			use(owner, ownerRoot, q)
			local untilTime = root and root:GetAttribute("FxUntil")
			local secs = (root and root:GetAttribute("FxSeconds")) or 4
			if typeof(untilTime) == "number" and math.abs(untilTime - (G.workspace:GetServerTimeNow() + secs)) < 0.2 then okProps += 1 else check("prop use sets FxUntil", false, q:GetFullName()) end
		end
		check("facility: prop uses set FxUntil", okProps >= 15, okProps)
		-- cooldown
		local q1 = props[1]; local r1 = rootOf(q1.Parent, q1)
		use(owner, ownerRoot, q1)
		local first = r1:GetAttribute("FxUntil")
		local fired0 = #Remote.fired
		use(owner, ownerRoot, q1)
		check("facility: cooldown keeps FxUntil", r1:GetAttribute("FxUntil") == first)
		check("facility: cooldown notice", #Remote.fired > fired0 and string.find(tostring(Remote.fired[#Remote.fired].args[2] and Remote.fired[#Remote.fired].args[2].text), "busy") ~= nil)
		-- founder-only robot arm: the visitor is refused, the founder runs it
		local arm = nil
		for _, q in props do if q:GetAttribute("Value") == "RobotArm1" then arm = q end end
		check("facility: robot arm prompt", arm ~= nil)
		if arm then
			local Fac = Facility
			Fac.issueCard(owner, OWNER)
			local armRoot = rootOf(arm.Parent, arm)
			armRoot:SetAttribute("FxUntil", nil)
			use(visitor, visitorRoot, arm)
			check("facility: visitor cannot run the robot arm", armRoot:GetAttribute("FxUntil") == nil)
			advance(1)
			use(owner, ownerRoot, arm)
			check("facility: founder runs the robot arm", typeof(armRoot:GetAttribute("FxUntil")) == "number")
		end
		-- fixtures: flush / tap / shower toggle / sauna -> FxUntil on the water / heater roots
		for _, spec in { { "flush", "ToiletWater", 2 }, { "tap", "TapWater", 6 }, { "shower", "ShowerWater", 15 } } do
			local q = promptsWith(spec[1])[1]
			check("facility: " .. spec[1] .. " prompt", q ~= nil)
			if q then
				local key = q.Parent:GetAttribute("FixtureKey")
				local water = nil
				for _, d in office:GetDescendants() do if d.Name == spec[2] and d:GetAttribute("FixtureKey") == key then water = d end end
				use(owner, ownerRoot, q)
				local u = water and water:GetAttribute("FxUntil")
				check("facility: " .. spec[1] .. " sets FxUntil", typeof(u) == "number" and math.abs(u - (G.workspace:GetServerTimeNow() + spec[3])) < 0.2, u)
				if spec[1] ~= "flush" then
					advance(1)
					use(owner, ownerRoot, q)
					check("facility: second " .. spec[1] .. " stops the water", water:GetAttribute("FxUntil") == 0)
				end
			end
		end
		local sauna = promptsWith("sauna")[1]
		if sauna then
			use(owner, ownerRoot, sauna)
			check("facility: sauna steams via FxUntil", typeof(sauna.Parent:GetAttribute("FxUntil")) == "number")
			local steam = sauna.Parent:FindFirstChild("Steam")
			check("facility: sauna emitter untouched on the server", steam and steam.Enabled == false)
		end
		-- workout: treadmill 1 runs 18 s; belt FxUntil + PlayerUntil on the wellness station (after the
		-- sauna session's 60 s cooldown)
		advance(80)
		local tread = promptsWith("workout", 1)[1]
		check("facility: treadmill prompt", tread ~= nil)
		if tread then
			use(owner, ownerRoot, tread)
			local belt = nil
			for _, root in Collection:GetTagged("PropFx") do if root:IsDescendantOf(office) and root:GetAttribute("Machine") == 1 then belt = root end end
			local lastText = Remote.fired[#Remote.fired] and Remote.fired[#Remote.fired].args[2] and Remote.fired[#Remote.fired].args[2].text
			check("facility: treadmill belt runs (FxUntil)", belt and typeof(belt:GetAttribute("FxUntil")) == "number", tostring(belt) .. " / " .. tostring(lastText))
			local station = belt and office:FindFirstChild(belt:GetAttribute("FxStation"), true)
			check("facility: wellness station blocked for employees", station and typeof(station:GetAttribute("PlayerUntil")) == "number")
			advance(19)
		end
		local rower = promptsWith("workout", 6)[1]
		check("facility: rowing machine prompt (machine 6)", rower ~= nil)
		local weights = promptsWith("workout", 8)[1]
		check("facility: free weights prompt (machine 8)", weights ~= nil)
		-- guest access class: the refusal text of the hotel annex
		local realAccess = Plan.accessAt
		Plan.accessAt = function(t, p) return "guest", nil end
		Facility.issueCard(visitor, OWNER, os.time() + 3600)
		local fired1 = #Remote.fired
		advance(1)
		local q = props[2]
		visitorRoot.CFrame = q.Parent.CFrame * CFrame.new(0, 0, -2)
		Facility.handle(visitor, q) -- directly: the access guard would show the visitor out first
		Plan.accessAt = realAccess
		local refused = false
		for i = fired1 + 1, #Remote.fired do
			local a = Remote.fired[i].args[2]
			if a and a.text == "Hotel rooms are for guests." then refused = true end
		end
		check("facility: guest class refusal", refused)
		-- no PropFx part moved on the server, ever
		advance(5)
		local moved = 0
		for p, c in before do if p.Parent and (p.CFrame.Position - c.Position).Magnitude > 1e-6 then moved += 1 end end
		check("facility: no server CFrame writes on PropFx parts", moved == 0, moved .. " of " .. nParts)
		say(string.format("facility: %d prop prompts used, %d PropFx parts watched", okProps, nParts))
	end

	if MODE == "all" or MODE == "contract" then
		for tier = 1, 4 do if not ONLY_TIER or ONLY_TIER == tier then contract(tier) end end
	end
	if MODE == "all" or MODE == "facility" or MODE == "negative" then facility() end
end
setfenv(body, M.envFor(nil))
local ok, err = M.runMain(body, { timeout = 600 })
if not ok then say("ERROR: " .. tostring(err)); failc += 1 end
for name, n in failures do if n > 1 then say(string.format("  (%s failed %d times)", name, n)) end end
say(string.format("life props: %d passed, %d failed", pass, failc))
if failc > 0 then error("life props failed", 0) end
