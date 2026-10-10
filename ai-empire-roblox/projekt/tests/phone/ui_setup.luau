--!nocheck
-- Shared client setup of the phone UI suite (test_ui.luau) and the guiprev scene (scene_phone.luau): the real
-- client UI (UIRoot, HUD, Computer, Toast, PeopleController, PhoneController) in the mock, wired to the REAL
-- server handlers (PhoneService, AssistantService payload through PhoneAction) via RemoteFunction:InvokeServer.
-- The visible clock is 10:30 (company time). States:
--   garage  company founded in the Garage Lab, nothing released, no staff: every phone app in its empty state
--   rich    Innovation Campus, 88 staff, 3 live models + a retired version, 4 business clients, a rep + engineer
--           abroad at Helix Research, a client team at the guest house, a rack fault, 20 company-log lines,
--           3 new lines during the session (unread badge), a missed call and a ringing itinerary call
-- Returns { M, session, push, Phone, Controller, PhoneService, playerGui, binds, state }.
local GuiDump = require("../../tools/guiprev/guidump")
return function(M, genDir, state, vw, vh, insets, opt)
	opt = opt or {}
	GuiDump.init(M)
	local G = M.G
	local Instance = G.Instance
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local Client = game.StarterPlayer.StarterPlayerScripts.Client
	local OWNER = 4242

	-- company clock: 10:30 on a fixed server day (CompanyOps.hour)
	local BASE = 1416666 * 1200 + 225
	M.IMPL.Workspace.methods.GetServerTimeNow = function() return BASE + M.Sched.now end
	M.classInfo("Workspace").methods.GetServerTimeNow = M.IMPL.Workspace.methods.GetServerTimeNow
	G.os = setmetatable({ clock = function() return M.Sched.now end }, { __index = os })
	if opt.touch then
		local uis = game:GetService("UserInputService")
		uis[M.KEY].props.TouchEnabled = true
		uis[M.KEY].props.MouseEnabled = false
		uis[M.KEY].props.KeyboardEnabled = false
	end

	local Template = M.require(Server.Lib.Template)
	local Remote = M.require(Server.Lib.Remote)
	local SessionService = M.require(Server.Services.SessionService)
	local EmpireMath = M.require(RS.Shared.EmpireMath)
	local MarketMath = M.require(RS.Shared.MarketMath)
	local ModelMath = M.require(RS.Shared.ModelMath)

	local playerGui = Instance.new("Folder"); playerGui.Name = "PlayerGui"
	local localPlayer = { UserId = OWNER, Name = "Founder", DisplayName = "Founder", Character = nil, Parent = game.Players, CharacterAdded = M.newSignal("CharacterAdded"),
		WaitForChild = function(_, name) if name == "PlayerGui" then return playerGui end end,
		FindFirstChild = function(_, name) if name == "PlayerGui" then return playerGui end end,
		FindFirstChildOfClass = function() return nil end, Kick = function() end }
	M.IMPL.Players.get.LocalPlayer = function() return localPlayer end; M.classInfo("Players").get.LocalPlayer = function() return localPlayer end

	-- server handlers (real services; no rate limits)
	local RateLimiter = M.require(Server.Lib.RateLimiter)
	RateLimiter.new = function() return { allow = function() return true end, forget = function() end } end
	local binds = {}
	local origBind = Remote.bind
	Remote.bind = function(name, limits, handler) binds[name] = handler; origBind(name, limits, handler) end
	Remote.setup()
	local folder = RS:FindFirstChild("Remotes")
	local notifyEvent, stateEvent = folder:FindFirstChild("Notify"), folder:FindFirstChild("State")
	Remote.fire = function(player, name, kind, payload)
		if name == "Notify" then M.fire(notifyEvent.OnClientEvent, kind, payload) end
	end
	local PhoneService = M.require(Server.Services.PhoneService)
	PhoneService._seams({ now = function() return M.Sched.now end })
	PhoneService.init()

	local d = Template.new()
	d.company = { name = "Nimbus Labs", logo = "N", color = "cyan", spec = "general", reputation = 34, foundedAt = 0 }
	d.empire.office = 1
	d.money = 6450
	local live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} }
	local e = d.empire

	local function model(id, name, version, target, status, stats, sizeId, focusId)
		local m = { id = id, name = name, version = version, sizeId = sizeId or "s1b", focusId = focusId or "balanced", status = status,
			createdAt = 0, trainedAt = 0, stats = stats, overall = ModelMath.overall(stats), trainCost = 4200, dataUsed = { total = 2e9, quality = 0.8, shares = { general = 1 } } }
		if target then
			m.release = { subPrice = 10, apiPrice = 2, marketing = 0, target = target, releasedAt = 0, auto = true }
			m.market = MarketMath.newMarketState(target, 0)
			m.market.vage = 600
		end
		d.models[id] = m
		table.insert(d.modelOrder, id)
		return m
	end

	if state == "rich" then
		e.office = 4
		d.money = 412800
		e.calendar = { day = 9, index = math.floor((BASE) / 1200) }
		e.seconds = 12000
		e.employees = { researcher = 24, engineer = 30, curator = 16, marketer = 18 }
		EmpireMath.syncProfiles(e, OWNER)
		d.gpus = { workstation = 8 }
		d.stats.modelsTrained, d.stats.modelsReleased = 6, 4
		e.contractsCompleted = 6
		model("nova1", "Nova", 1, "general", "retired", { reasoning = 55, coding = 50, math = 48, creativity = 62, knowledge = 58, reliability = 54, speed = 76, efficiency = 74 })
		model("nova2", "Nova", 2, "general", "live", { reasoning = 66, coding = 58, math = 57, creativity = 74, knowledge = 69, reliability = 63, speed = 70, efficiency = 68 }, "s3b")
		model("coder", "Coder", 2, "developers", "live", { reasoning = 71, coding = 86, math = 70, creativity = 52, knowledge = 64, reliability = 70, speed = 70, efficiency = 68 }, "s3b", "coding")
		model("sage", "Sage", 1, "students", "live", { reasoning = 60, coding = 41, math = 66, creativity = 47, knowledge = 58, reliability = 55, speed = 76, efficiency = 74 }, "s1b", "reasoning")
		local s0 = e.seconds
		e.deals.accounts = { helpdesk = { expires = s0 + 5200, since = 0 }, code = { expires = s0 + 900, since = 0 }, ledger = { expires = s0 + 4100, since = 0, founder = nil }, pixel = { expires = s0 + 6900, since = 0 } }
		e.deals.signed = 6
		e.deals.tripList = {
			{ client = "helix", kind = "sign", back = s0 + 1900, founder = false, hosted = false, crew = 2, left = s0 - 500 },
			{ client = "atlas", kind = "sign", back = s0 + 800, founder = false, hosted = true, crew = 0, left = s0 - 400 },
		}
		e.deals.news = {
			"day 9 10:05: rep to Helix Research: pilot, flight + 2 nights, $2,520",
			"day 9 09:40: hosting Atlas Search at the guest house: pilot, $240",
			"day 9 09:12: Nova v2: Servers 97 % full → Consumer Chat price raised to $10",
			"day 9 08:30: HR hired Mia Chen (Growth & Sales, fee $1,200)",
			"day 8 16:20: signed Pixel Games: pilot $13,500, $13,500/day",
			"day 8 14:02: renewed CloudDesk for 6 days",
			"day 8 11:45: visited Pixel Games: trust 63%",
			"day 8 10:10: Sage v1 launched as Study App",
			"day 8 09:00: moved into the Innovation Campus",
			"day 7 15:30: signed Ledger Finance: pilot $27,000, $27,000/day",
			"day 7 12:00: Save mode off",
			"day 7 09:20: Lab level 2: +1 core stat on future models",
		}
		live.users, live.revenue, live.cost = 182000, 610, 420
		live.compute = { units = 40, lost = 1, reserved = 3.2, slots = 8, it = true, faults = { { slot = 3, gpu = "workstation", since = s0 - 20 } } }
		live.ops = { travelling = 2, accounts = 4, limit = 10, trips = {
			{ client = "helix", name = "Helix Research", kind = "sign", tier = "abroad", back = s0 + 1900, founder = false, hosted = false, crew = 2 },
			{ client = "atlas", name = "Atlas Search", kind = "sign", tier = "region", back = s0 + 800, founder = false, hosted = true, crew = 0 },
		} }
	end

	local session = { userId = OWNER, player = localPlayer, data = d, live = live,
		dirty = false, lastSent = 0, nextSaveAt = math.huge, saving = false, closed = false, released = false, rng = G.Random.new(1) }
	SessionService.all()[localPlayer] = session
	local function snapshot() return { saveEnabled = false, serverTime = BASE + M.Sched.now, data = session.data, live = session.live } end
	local function push() M.fire(stateEvent.OnClientEvent, snapshot()); M.settle(0.1) end
	local function patch(cls, name, fn) M.IMPL[cls].methods[name] = fn; M.classInfo(cls).methods[name] = fn end
	patch("RemoteFunction", "InvokeServer", function(self, payload)
		if self.Name == "RequestState" then return { ok = true, state = snapshot() } end
		local handler = binds[self.Name]
		if not handler then return { ok = false, err = "BAD_INPUT" } end
		local result = handler(session, payload or {})
		G.task.defer(push)
		return result
	end)

	-- client: the real UI
	local UIRoot = M.require(Client.UI.UIRoot)
	local Toast = M.require(Client.UI.Toast)
	local State = M.require(Client.Controllers.StateController)
	local Computer = M.require(Client.UI.Screens.Computer)
	local hud, dim, overlay, intro, top = UIRoot.init()
	if vw then GuiDump.setViewport(playerGui, vw, vh, insets) end
	Toast.mount(top)
	local okHud, HUD = pcall(M.require, Client.UI.Screens.HUD)
	if okHud then pcall(HUD.mount, hud, false, function() end) end
	Computer.mount(overlay, dim)
	local People = M.require(Client.Controllers.PeopleController)
	People.init(function(app, section) Computer.open(app, section) end)
	local Controller = M.require(Client.Controllers.PhoneController)
	Controller.init()
	local Phone = M.require(Client.UI.Screens.Phone)
	State.init()
	M.settle(1)
	if okHud then pcall(HUD.setHidden, false) end
	if vw then GuiDump.setViewport(playerGui, vw, vh, insets) end
	push()
	M.settle(0.5)
	if state == "rich" then
		-- what happens during the session: 3 new log lines (unread), a rack fault already known, two calls
		table.insert(e.deals.news, 1, "day 9 10:18: visited Pixel Games: trust 88%")
		table.insert(e.deals.news, 1, "day 9 10:24: Coder v2 replaces Coder v1 (Developer API, 90% of users move)")
		table.insert(e.deals.news, 1, "day 9 10:29: signed Atlas Search: pilot $36,000, $36,000/day")
		push()
		PhoneService.ring(session, { title = "First client signed!", text = "Great news: CloudDesk signed!", kind = "info", accept = "Great!", decline = "Later" })
		local calls = PhoneService.calls(session)
		calls[1].state = "missed"
		calls[1].day, calls[1].hour = 2, 15.2
		M.settle(0.2)
		local rep = string.match(e.staffProfiles.marketer[1].n, "^(%S+)")
		local PM = M.require(RS.Shared.PhoneMath)
		local title, text = PM.tripCall({ client = "Helix Research", tier = "abroad", rep = rep, engineer = "Leo", backDay = 10, backHour = 12.1, today = 9, hotel = "Meridian Grand Hotel", jet = false, flight = "PM 101 at 14:30" })
		PhoneService.ring(session, { title = title, text = text, kind = "itinerary", accept = "Join the trip", decline = "Not this time", data = { client = "helix", rep = rep, engineer = "Leo" } })
		push()
		M.settle(0.3)
	end
	return { M = M, session = session, push = push, Phone = Phone, Controller = Controller, PhoneService = PhoneService, playerGui = playerGui, binds = binds,
		state = state, Computer = Computer, base = BASE }
end
