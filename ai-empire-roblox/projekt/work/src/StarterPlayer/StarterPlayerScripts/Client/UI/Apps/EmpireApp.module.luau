--!strict
-- Company OS: reactive cards are built on tab changes, updated in place on snapshots.
-- Tabs: Overview, Clients (B2B pipeline, CORE_SPEC 3.2), Money (P&L per company day from empire.ledger, CORE_SPEC 4/6),
-- Team, Research, Goals, Office, Settings (auto-HR, Save mode, night shift, apprentices, company jet: CORE_SPEC 8.1,
-- 11.1, 11.2) and Board. Every number comes from the replicated company state; decisions go to the server through
-- EmpireAction / DealAction / HireEmployee (errors: ActionController texts, CORE_SPEC 11.8).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.EmpireConfig)
local HardwareConfig = require(Shared.Config.HardwareConfig)
local CityPlan = require(Shared.Config.CityPlan)
local Math = require(Shared.EmpireMath)
local Ops = require(Shared.CompanyOps)
local ModelMath = require(Shared.ModelMath)
local Format = require(Shared.Format)
local TutorialMath = require(Shared.TutorialMath)
local ShopMath = require(Shared.ShopMath) -- shop package (SHOP_SPEC 5.2.2, 5.2.6)
local ShopConfigRebrand = require(Shared.Config.ShopConfig).REBRAND_COOLDOWN
local CompanyConfig = require(Shared.Config.CompanyConfig)
local UI = script.Parent.Parent
local Client = UI.Parent
local State = require(Client.Controllers.StateController)
local Action = require(Client.Controllers.ActionController)
local People = require(Client.Controllers.PeopleController)
local Conversation = require(UI.Screens.Conversation)
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Toast = require(UI.Toast)
local ShopCore = require(UI.Shop.ShopCore) -- shop package: Eureka buttons, focus requests
local C, F = Theme.colors, Theme.font
local App = {}
local scroll: ScrollingFrame? = nil
local current = "overview"
local updaters: { (any) -> () } = {}
local nav: any = nil
local tabButtons: { [string]: TextButton } = {}
-- Menu pages (ONBOARDING_SPEC B, menu package): App.mountPart renders one tab builder (or a composite) into a page
-- frame of the Menu. Every part keeps its own updater list; `building` is the list watch() fills right now and
-- `inPage` is true while a part renders (cards that duplicate another Menu page are left out there).
local building: { (any) -> () } = updaters
local inPage = false
local function watch(fn: (any) -> ())
	table.insert(building, fn)
	if State.snapshot then fn(State.snapshot) end
end
-- Touch-first screens: row buttons and switches are at least TAP design px tall. The Computer window is drawn at about
-- 0.43 on a phone in landscape, so 96 px is about 41 pt (Apple asks for 44 pt; a Computer-wide touch scale is filed in
-- design/requests/apps.md).
local TAP = 96
App.TAP = TAP
local function button(parent: Instance, label: string, callback: () -> ())
	local b = Kit.button(parent, label, "primary", UDim2.new(1,0,0,Kit.tap(40, TAP)))
	b.LayoutOrder = 9
	Kit.onClick(b, callback)
	return b
end
local function call(name: string, payload: any, message: string?)
	task.spawn(function()
		local ok = Action.call(name, payload)
		if ok and message then Toast.show("success", message) end
	end)
end
-- One action at a time per remote: EmpireAction and DealAction each have a per-player token bucket on the server (4 calls
-- at once, then 2 per second; EmpireService.init), and ActionController answers BUSY while a call of the same remote is
-- in flight. Each remote gets a lane that mirrors that bucket a little stricter (BURST calls, then RATE per second, so
-- other buttons keep a token) and retries RATE_LIMIT / BUSY answers, so a burst of taps (night shift for three roles,
-- Pin twice, two switches) never ends half done. Jobs of one remote run in tap order.
local BURST, RATE = 3, 1.8
type Lane = { jobs: { () -> () }, running: boolean, tokens: number, last: number }
local lanes: { [string]: Lane } = {}
local function lane(name: string): Lane
	local l = lanes[name]
	if l == nil then
		local made: Lane = { jobs = {}, running = false, tokens = BURST, last = os.clock() }
		lanes[name] = made
		return made
	end
	return l
end
local function enqueue(name: string, job: () -> ())
	local l = lane(name)
	table.insert(l.jobs, job)
	if l.running then return end
	l.running = true
	task.spawn(function()
		while #l.jobs > 0 do
			local nextJob = table.remove(l.jobs, 1)
			if nextJob then nextJob() end
		end
		l.running = false
	end)
end
local function paced(name: string, payload: any): (boolean, any)
	local l = lane(name)
	local last: any = { ok = false, err = "RATE_LIMIT" }
	for attempt = 1, 5 do
		local now = os.clock()
		l.tokens = math.min(BURST, l.tokens + (now - l.last) * RATE)
		l.last = now
		if l.tokens < 1 then
			task.wait((1 - l.tokens) / RATE)
			l.tokens = 1
			l.last = os.clock()
		end
		l.tokens -= 1
		local ok, res = Action.call(name, payload, true)
		last = res
		if ok then return true, res end
		if res.err ~= "RATE_LIMIT" and res.err ~= "BUSY" then return false, res end
		l.tokens = 0 -- the server's bucket is empty (another button used it): wait for a fresh token
		task.wait(0.5 * attempt)
	end
	return false, last
end
-- a queued EmpireAction / DealAction with its success toast (errors: ActionController texts)
local function queued(name: string, payload: any, message: string?)
	enqueue(name, function()
		local ok, res = paced(name, payload)
		if ok and message then
			Toast.show("success", message)
		elseif not ok then
			Toast.show("error", Action.message(res.err))
		end
	end)
end
App.RATE = RATE
App.BURST = BURST
local function para(parent: Instance, text: string, order: number?)
	return Kit.para(parent, text, 14, C.muted, order or 2)
end
local function title(parent: Instance, text: string)
	local t = Kit.para(parent, text, 18, C.text, 1)
	t.Font = F.bold
	return t
end
local function dim(parent: Instance, text: string, order: number?)
	return Kit.para(parent, text, 13, C.dim, order or 8)
end
local function metric(parent: Instance, label: string, value: (any) -> string, order: number)
	local card = Kit.card(parent, order)
	Kit.caption(card, label, 1)
	local t = Kit.para(card, "", 23, C.text, 2)
	t.Font = F.bold
	watch(function(s) t.Text = value(s) end)
	return card
end
local function dollars(n: number): string
	return Ops.money(n)
end
local function perDay(perMinute: number): string
	return dollars(perMinute * Ops.DAY / 60) .. "/day"
end
local function stageName(i: number): string
	local def = Config.OFFICES[math.clamp(math.floor(i), 1, #Config.OFFICES)]
	return def.name
end
-- The safety rules of CORE_SPEC 8.3 in one line ("" when nothing applies): a whole game day below $0 pauses trips and
-- night shifts (live.ops.paused); deep debt sends the newest hires on unpaid leave (empire.unpaidLeave)
function App.safetyLine(s: any): string
	local e = s.data.empire
	local ops = if typeof(s.live.ops) == "table" then s.live.ops else {}
	local leave = math.max(0, math.floor(tonumber(e.unpaidLeave) or 0))
	local parts = {}
	if ops.paused == true then
		table.insert(parts, "Cash has been below $0 for a whole game day: trips and night shifts are paused")
	elseif (tonumber(s.data.money) or 0) < 0 then
		table.insert(parts, "Cash is below $0: trips and night shifts pause after a whole game day like this")
	end
	if leave > 0 then
		table.insert(parts, string.format("%d newest hire%s on unpaid leave until cash is above %s", leave, if leave == 1 then " is" else "s are", dollars(Ops.dailyPayroll(e))))
	end
	return if #parts > 0 then table.concat(parts, ". ") .. "." else ""
end
-- Why automatic HR is or is not hiring right now: the checks of EmpireService.autoHire and CompanyOps.hrAllowed in
-- the same order (the decision itself stays on the server). Returns the line and whether it is a warning.
function App.hrStatus(s: any): (string, boolean)
	local data = s.data
	local e = data.empire
	local ops = if typeof(s.live.ops) == "table" then s.live.ops else {}
	local auto, budget = Ops.hrSettings(e)
	if not auto then return "Off: hire by hand in Team.", false end
	local anyLive = false
	for _, id in data.modelOrder do local m = data.models[id]; if m and m.status == "live" then anyLive = true; break end end
	if not anyLive then return "Waiting: HR starts hiring once your first model is live.", false end
	local roleId = Ops.hrPick(e)
	local role = if roleId then Config.find(Config.ROLES, roleId) else nil
	if not role then return "Every department is at its HR target.", false end
	local staff = Ops.heads(e)
	local cap = Config.OFFICES[Ops.stageIndex(e)].staff
	local cash = tonumber(data.money) or 0
	if staff >= cap then return "Paused: every desk is filled. A bigger office adds desks.", true end
	if cash < 0 then return "Paused: cash is below $0.", true end
	if (tonumber(e.unpaidLeave) or 0) > 0 then return "Paused: people are on unpaid leave until cash covers a day of payroll.", true end
	if ops.saveMode == true and staff >= cap * 0.5 then return "Save mode: HR stops at half the desks until the move.", true end
	if staff >= Ops.HR_STARTERS then
		local payroll = Ops.wage(e) + Ops.opsPosts(e) * Ops.OPS_WAGE / Ops.DAY -- $/s, like CompanyOps.hrAllowed
		local income = math.max(0, (tonumber(ops.income) or 0) / 60)
		if payroll + role.wage > budget * income then
			return string.format("Paused: payroll %s/day is above the %d %% budget (%s/day). More income or a bigger budget lets HR hire again.",
				dollars(payroll * Ops.DAY), math.floor(budget * 100 + 0.5), dollars(budget * income * Ops.DAY)), true
		end
	end
	local fee = Math.hireCost(e, role)
	local reserve = Ops.reserve(e) * 1.5
	if cash - reserve < fee then
		return string.format("Waiting: HR keeps a cash reserve of %s plus the %s fee.", dollars(reserve), dollars(fee)), true
	end
	return string.format("Hiring: next hire %s (fee %s), one every %d s.", role.name, dollars(fee), Ops.HIRE_GAP), false
end
local function safetyNote(parent: Instance, order: number): TextLabel
	local t = Kit.para(parent, "", 14, C.warn, order)
	t.Name = "Safety"
	t.Font = F.bold
	watch(function(s)
		local text = App.safetyLine(s)
		t.Text = text
		t.Visible = text ~= ""
	end)
	return t
end
local function clearRows(rows: Instance)
	for _, child in rows:GetChildren() do if child:IsA("GuiObject") then child:Destroy() end end
end
-- small segmented switch inside a card row (Off / On, 25 / 40 / 55 %, Auto / Off)
local function switch(parent: Instance, options: { Kit.Option }, initial: string, order: number, width: number?, onSelect: (string) -> ()): Kit.Segmented
	local h = Kit.tap(36, TAP)
	local seg = Kit.segmented(parent, options, initial, onSelect, h)
	seg.frame.LayoutOrder = order
	if width then seg.frame.Size = UDim2.fromOffset(width, h) end
	return seg
end
local function profitChart(parent: Instance, order: number)
	local card=Kit.card(parent,order)
	title(card,"How the business is doing")
	local caption=para(card,"",2)
	local graph=Kit.frame(card,UDim2.new(1,0,0,130))
	graph.LayoutOrder=3
	local positive=Kit.text(graph,"",11,F.medium,C.dim)
	positive.Position=UDim2.new(0,0,0,0)
	local negative=Kit.text(graph,"",11,F.medium,C.dim)
	negative.Position=UDim2.new(0,0,1,-15)
	local plot=Kit.frame(graph,UDim2.new(1,0,1,-34),UDim2.fromOffset(0,17))
	for i=0,3 do
		local line=Kit.frame(plot,UDim2.new(1,0,0,1),UDim2.fromScale(0,i/3))
		line.BackgroundColor3=C.line
		line.BackgroundTransparency=0.96
	end
	local baseline=Kit.frame(plot,UDim2.new(1,0,0,1))
	baseline.BackgroundColor3=C.dim
	baseline.BackgroundTransparency=0.4
	local bars={}
	for i=1,36 do
		local b=Kit.frame(plot)
		Kit.corner(b,2)
		bars[i]=b
	end
	watch(function(s)
		local history=s.data.empire.history
		local min,max=0,1
		for _,sample in history do min=math.min(min,sample.profit);max=math.max(max,sample.profit) end
		local range=max-min
		local zero=1-(0-min)/range
		baseline.Position=UDim2.fromScale(0,zero)
		-- samples are $/min (EmpireService history): shown per game day like the rest of the UI (CORE_SPEC 6)
		local perGameDay=Ops.DAY/60
		positive.Text=if #history==0 then "" else Format.money(max*perGameDay).."/day"
		negative.Text=if #history==0 or min>=0 then "" else Format.money(min*perGameDay).."/day"
		caption.Text=if #history==0 then "The first sample appears after 10 seconds. Staff wages are included." else "Net profit per game day · one sample every 10 seconds · staff wages included"
		for i,b in bars do
			local sample=history[i]
			b.Visible=sample~=nil
			if sample then
				b.AnchorPoint=Vector2.new(0,if sample.profit>=0 then 1 else 0)
				b.Position=UDim2.fromScale((i-1)/36,zero)
				b.Size=UDim2.fromScale(0.021,math.abs(sample.profit)/range)
				b.BackgroundColor3=if sample.profit>=0 then C.good else C.bad
				b.BackgroundTransparency=0.15
			end
		end
	end)
end
local function overview(parent: Instance)
	local hero = Kit.card(parent, 1)
	local headline = title(hero, "Your next chapter")
	local text = para(hero, "", 2)
	watch(function(s)
		local e = s.data.empire
		local stage = Ops.stageIndex(e)
		headline.Text = stageName(stage) .. "  /  Level " .. tostring(1 + math.floor(e.xp / 250))
		local b = Math.bonuses(e)
		local goal = Math.nextGoal(s.data, s.live)
		text.Text = string.format("%s  ·  %d/%d employees  ·  %.0f research points  ·  %.0f XP\nTraining +%.0f%%  ·  Revenue +%.0f%%  ·  Wages %s/day\nNext goal: %s",
			Format.dayClock(Ops.day(e), Ops.hour(s.serverTime)), Math.staff(e), Config.OFFICES[stage].staff, e.points, e.xp, (b.speed-1)*100, (b.revenue-1)*100, dollars(b.wage*Ops.DAY),
			if goal then goal.text else "every goal reached")
	end)
	local start = Kit.row(hero, Kit.tap(40, TAP), 8, 3)
	for _, def in {{"Clients","empire","clients"},{"Money","empire","money"},{"Settings","empire","settings"}} do
		local b = Kit.button(start, def[1], "secondary", UDim2.new(1/3,-6,1,0))
		Kit.onClick(b, function() App.openSection(def[3]) end)
	end
	local metrics = Kit.grid(parent, 3, 96, 10, 2)
	metric(metrics, "Cash available", function(s) return Format.money(s.data.money) end, 1)
	metric(metrics, "Profit per game day", function(s) return Format.perDay(s.live.revenue-s.live.cost) end, 2)
	metric(metrics, "Active users", function(s) return Format.compact(s.live.users) end, 3)
	profitChart(parent,3)
	local cycle = Kit.card(parent, 4)
	local cycleTitle = title(cycle, "Market cycle")
	local cycleText = para(cycle, "")
	watch(function(s)
		local def, left = Config.cycle(s.serverTime)
		cycleTitle.Text = def.name
		cycleText.Text = def.desc .. "  Next cycle in " .. tostring(math.ceil(left)) .. "s."
	end)
	local daily = Kit.card(parent, 5)
	title(daily, "Daily founder grant")
	local dailyText = para(daily, "")
	local claim = button(daily, "Claim daily grant", function() call("ClaimDaily", {}, "Daily grant collected! +15 research points") end)
	watch(function(s)
		local e = s.data.empire
		local day = math.floor(s.serverTime/86400)
		local done = e.daily.day >= day
		local nextStreak = if e.daily.day == day-1 then math.min(7,e.daily.streak+1) else 1
		dailyText.Text = if done then "Collected today. Streak: " .. tostring(e.daily.streak) .. ". Resets at 00:00 UTC."
			else "Today's grant: " .. Format.money(1000+(nextStreak-1)*500) .. " + 15 research points. Consecutive days increase the grant."
		Kit.setDisabled(claim, done)
		claim.Text = if done then "Come back tomorrow" else "Claim founder grant"
	end)
	local goal = Kit.card(parent, 6)
	title(goal, "A business with a plan")
	para(goal, "1. Buy data and train a model in the Lab.\n2. Launch it at the Recommended price.\n3. Sign business clients: you and your Growth & Sales reps visit them by yourselves.\n4. Hire a team, research upgrades and move into a bigger office.\n5. Build a frontier model and climb the server board.")
end

-- Clients (CORE_SPEC 3.2): the B2B pipeline -------------------------------------------------------------------
local TIER_TEXT: { [string]: string } = { city = "City", region = "Region", abroad = "Abroad" }
local GROUPS: { [string]: number } = { account = 100, lead = 200, needs = 300, later = 400 }
-- remaining company days of an account -> the company day it ends on (the calendar moves with the server day)
local function endDay(s: any, secondsLeft: number): number
	local e = s.data.empire
	local into = (s.serverTime % Ops.DAY) / Ops.DAY
	return Ops.day(e) + math.floor(into + math.max(0, secondsLeft) / Ops.DAY)
end
local function tripOf(s: any, clientId: string): any
	local ops = s.live.ops
	if typeof(ops) == "table" and typeof(ops.trips) == "table" then
		for _, t in ops.trips do if typeof(t) == "table" and t.client == clientId then return t end end
	end
	local d = s.data.empire.deals
	if typeof(d) == "table" and typeof(d.tripList) == "table" then
		for _, t in d.tripList do if typeof(t) == "table" and t.client == clientId then return t end end
	end
	return nil
end
local function tripText(s: any, t: any): string
	local c = Ops.client(t.client)
	local name = if c then c.name else tostring(t.client)
	local tier = t.tier or (if c then c.trip else "city")
	local left = Kit.countdown(math.max(0, (tonumber(t.back) or 0) - (tonumber(s.data.empire.seconds) or 0)))
	local what = if t.kind == "renew" then "check-in" else "pilot visit"
	if t.hosted then return string.format("%s team at your guest house · %s · back in %s", name, what, left) end
	local who = if t.founder then "You (founder)" elseif (tonumber(t.crew) or 1) >= 2 then "Field rep + engineer" else "Field rep"
	local how = if tier == "abroad" then (if s.data.empire.jet == true then "company jet" else "flight + 2 nights") elseif tier == "region" then "City Hotel night" else "car"
	return string.format("%s → %s · %s · %s · back in %s", who, name, what, how, left)
end
-- where a client's office is (CityPlan destination + zone name: "Business City", "Port Meridian", ...)
function App.clientPlace(c: any): (any, string)
	local dest = CityPlan.clientOffice(c.name)
	local zone = if dest then CityPlan.zone(dest.zone) else nil
	return dest, if zone then zone.name elseif c.trip == "abroad" then "Port Meridian" else "Business City"
end
-- "Join in person" away from the client: a GPS route there (or to City Airport for Port Meridian) instead of an error
function App.routeToClient(c: any, secondsLeft: number)
	local dest, where = App.clientPlace(c)
	if not dest then
		Toast.show("error", Action.message("TOO_FAR"))
		return
	end
	local Travel: any = require(Client.Controllers.TravelController) -- lazy: loaded after the apps
	local within = Kit.countdown(secondsLeft)
	local away = (game:GetService("Players").LocalPlayer :: any):GetAttribute("TravelState")
	if dest.zone == "abroad" and away ~= "abroad" then
		Travel.guide("airport")
		Toast.show("info", string.format("%s is in Port Meridian: route to City Airport started. Fly over and tap Join at their lobby within %s.", c.name, within), 7)
	else
		Travel.guide(dest.id)
		Toast.show("info", string.format("Route to %s (%s) started. Tap Join at their lobby within %s.", c.name, where, within), 7)
	end
end
type ClientRow = { frame: Frame, update: (any) -> () }
-- Pin / Skip are toggles on the server (DealAction): after a tap the row's buttons stay locked until a snapshot shows
-- the new state AND at least MIN_LOCK s have passed (a double tap never undoes itself), at most LOCK_SECONDS
local LOCK_SECONDS = 3
local MIN_LOCK = 0.6
App.MIN_LOCK = MIN_LOCK
local function clientRow(parent: Instance, c: any): ClientRow
	local touch = Kit.isTouch()
	local btnW, btnH = if touch then 124 else 84, if touch then TAP else 30
	local rowH, shortH = if touch then btnH + 24 else 84, if touch then 66 else 62
	local side = 2 * btnW + 8 + 14 -- right column with the buttons
	local frame = Kit.frame(parent, UDim2.new(1, 0, 0, rowH))
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3 = C.panel2
	Kit.corner(frame, 10)
	local stroke = Kit.stroke(frame, 0.93)
	Kit.padding(frame, 12, 14, 12, 16)
	local nameRow = Kit.frame(frame, UDim2.new(1, -side, 0, 22))
	Kit.list(nameRow, 8, true)
	local name = Kit.text(nameRow, c.name, 17, F.bold, C.text)
	name.LayoutOrder = 1
	local tierTag = Kit.tag(nameRow, TIER_TEXT[c.trip] or c.trip, if c.trip == "abroad" then C.warn elseif c.trip == "region" then C.good else C.muted, 2)
	tierTag.Name = "Tier"
	local pinTag = Kit.tag(nameRow, "Pinned", C.text, 3)
	Theme.bindAccent(pinTag, "TextColor3")
	pinTag.Visible = false
	local value = Kit.text(frame, dollars(c.retainer) .. "/day", 16, F.bold, C.text)
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.fromScale(1, 0)
	local status = Kit.text(frame, "", 14, F.medium, C.muted)
	status.Name = "Status"
	status.AutomaticSize = Enum.AutomaticSize.None
	status.Size = UDim2.new(1, -side, 0, 18)
	status.Position = UDim2.fromOffset(0, 27)
	status.TextTruncate = Enum.TextTruncate.AtEnd
	local bar = Kit.bar(frame, 6)
	bar.frame.Name = "Trust"
	bar.frame.Size = UDim2.new(1, -side, 0, 6)
	bar.frame.Position = UDim2.fromOffset(0, 52)
	local buttons = Kit.frame(frame, UDim2.fromOffset(2 * btnW + 8, btnH), UDim2.fromScale(1, 1))
	buttons.AnchorPoint = Vector2.new(1, 1)
	local layout = Kit.list(buttons, 8, true)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	local pin = Kit.button(buttons, "Pin", "secondary", UDim2.fromOffset(btnW, btnH))
	pin.Name = "Pin"
	pin.TextSize = if touch then 16 else 14
	pin.LayoutOrder = 1
	local skip = Kit.button(buttons, "Skip", "ghost", UDim2.fromOffset(btnW, btnH))
	skip.Name = "Skip"
	skip.TextSize = if touch then 16 else 14
	skip.LayoutOrder = 2
	local join = Kit.button(buttons, "Join in person", "secondary", UDim2.fromOffset(2 * btnW + 8, btnH))
	join.Name = "Join"
	join.TextSize = if touch then 16 else 14
	join.LayoutOrder = 3
	-- Pin and Skip are toggles on the server (DealAction): one tap locks the row until a snapshot shows the result
	local lock: { kind: string, want: boolean, at: number }? = nil
	local function toggle(kind: string)
		if lock then return end
		local snapshot = State.snapshot
		local d: any = if snapshot then snapshot.data.empire.deals else nil
		local now = if typeof(d) ~= "table" then false elseif kind == "pin" then d.pinned == c.id else typeof(d.skip) == "table" and d.skip[c.id] == true
		lock = { kind = kind, want = not now, at = os.clock() }
		Kit.setDisabled(pin, true)
		Kit.setDisabled(skip, true)
		enqueue("DealAction", function()
			local ok, res = paced("DealAction", { action = kind, clientId = c.id, on = not now }) -- explicit state: a repeat never undoes it
			if not ok then
				lock = nil
				Kit.setDisabled(pin, false)
				Kit.setDisabled(skip, false)
				Toast.show("error", Action.message(res.err))
			end
		end)
	end
	Kit.onClick(pin, function() toggle("pin") end)
	Kit.onClick(skip, function() toggle("skip") end)
	local backLeft = 0
	Kit.onClick(join, function()
		enqueue("DealAction", function()
			local ok, res = paced("DealAction", { action = "joinMeeting", clientId = c.id })
			if ok then Toast.show("success", "You joined the " .. c.name .. " meeting: trust +15 %.", 5)
			elseif res.err == "ALREADY_DONE" then Toast.show("info", "You are already in the " .. c.name .. " meeting.", 4)
			elseif res.err == "TOO_FAR" then App.routeToClient(c, backLeft)
			else Toast.show("error", Action.message(res.err)) end
		end)
	end)
	local _, where = App.clientPlace(c)
	local function update(s: any)
		local data = s.data
		local e = data.empire
		local d = if typeof(e.deals) == "table" then e.deals else Ops.newDeals()
		local acc = if typeof(d.accounts) == "table" then d.accounts[c.id] else nil
		local trust = if typeof(d.trust) == "table" then tonumber(d.trust[c.id]) else nil
		local pinned = d.pinned == c.id
		local skipped = typeof(d.skip) == "table" and d.skip[c.id] == true
		local trip = tripOf(s, c.id)
		local stage = Ops.stageIndex(e)
		local best = Ops.liveBest(data, c.stat)
		local group, text, color = "lead", "", C.muted
		local fraction: number? = nil
		local canPin, canJoin = false, false
		if lock then
			local seen = if lock.kind == "pin" then pinned else skipped
			local age = os.clock() - lock.at
			if (seen == lock.want and age >= MIN_LOCK) or age > LOCK_SECONDS then
				lock = nil
			end
		end
		if acc then
			group = "account"
			local left = (tonumber(acc.expires) or 0) - (tonumber(e.seconds) or 0)
			if acc.renewing or (trip and trip.kind == "renew") then
				text = "Account · check-in visit under way · renews for " .. Ops.TERM_DAYS .. " more days"
			else
				text = string.format("Account until day %d · %.1f days left", endDay(s, left), math.max(0, left) / Ops.DAY)
			end
			color = C.good
		elseif stage < c.stage then
			group = "later"
			text = "Unlocks at the " .. stageName(c.stage) .. (if c.trip == "abroad" then " · Port Meridian, flight + 2 nights" elseif c.trip == "region" then " · Business City, City Hotel night" else "")
			color = C.dim
		elseif best < c.minimum then
			group = "needs"
			text = if best <= 0 then string.format("Needs %s %d · release a model first", c.stat, c.minimum)
				else string.format("Needs %s %d · your best live model: %d", c.stat, c.minimum, math.floor(best))
			color = C.warn
			canPin = true
		else
			canPin = true
			fraction = math.min(1, trust or 0)
			if trip and trip.kind == "sign" then
				backLeft = math.max(0, (tonumber(trip.back) or 0) - (tonumber(e.seconds) or 0))
				text = (if trip.hosted then "Client team at your guest house" elseif trip.founder then "You are on the pilot visit" else "Pilot visit at " .. where)
					.. " · back in " .. Kit.countdown(backLeft)
				color = C.text
				-- the founder can join a rep's meeting in person (not the founder's own simulated visit, not a hosted one)
				canJoin = not trip.hosted and not trip.founder
				canPin = false -- the visit is already under way
			elseif skipped then
				text = "Skipped · your sales team leaves it out"
				color = C.dim
			else
				local accounts, limit = 0, Ops.accountLimit(e)
				if typeof(d.accounts) == "table" then for _ in d.accounts do accounts += 1 end end
				local seller = if c.trip == "city" then "you or a field rep" else "a field rep"
				local why = if accounts >= limit then " · all account slots are taken" elseif c.trip ~= "city" and Ops.fieldReps(e) == 0 then " · needs a field rep (Growth & Sales)" else " · next visit by " .. seller
				text = string.format("Lead · trust %d %%", math.floor((trust or 0) * 100)) .. why
				color = C.muted
			end
		end
		if pinned and group ~= "account" then text = "Pinned · visited next · " .. text end
		status.Text = text
		status.TextColor3 = color
		pinTag.Visible = pinned and group ~= "account"
		stroke.Color = if pinned and group ~= "account" then Theme.accent else C.line
		stroke.Transparency = if pinned and group ~= "account" then 0.4 else 0.93
		bar.frame.Visible = fraction ~= nil
		if fraction then bar.set(fraction) end
		pin.Visible = canPin
		skip.Visible = canPin and not canJoin
		join.Visible = canJoin
		Kit.setDisabled(pin, lock ~= nil)
		Kit.setDisabled(skip, lock ~= nil)
		pin.Text = if pinned then "Unpin" else "Pin"
		skip.Text = if skipped then "Unskip" else "Skip"
		value.TextColor3 = if group == "account" then C.good elseif group == "later" then C.dim else C.text
		name.TextColor3 = if group == "later" then C.muted else C.text
		frame.LayoutOrder = GROUPS[group] + table.find(Ops.CLIENTS, c) :: number
		-- rows without a trust bar or buttons (accounts, later stages) are shorter
		frame.Size = UDim2.new(1, 0, 0, if fraction ~= nil or canPin or canJoin then rowH else shortH)
		frame:SetAttribute("Group", group)
	end
	return { frame = frame, update = update }
end
local function clients(parent: Instance)
	local head = Kit.card(parent, 1)
	title(head, "Business clients")
	local summary = para(head, "", 2)
	local stats = Kit.grid(head, 4, 52, 10, 3)
	local mAccounts = Kit.metric(stats, "Accounts", 1, 20)
	local mRetainers = Kit.metric(stats, "Retainers", 2, 20)
	local mReps = Kit.metric(stats, "Field reps", 3, 20)
	local mTrips = Kit.metric(stats, "On the road", 4, 20)
	dim(head, "Sales run by themselves: the founder sells city clients (up to " .. Ops.FOUNDER_ACCOUNTS .. " accounts), Growth & Sales field reps take " .. Ops.ACCOUNTS_PER_REP .. " accounts each. Visits start 08:00–15:00. A signed client pays one day as pilot fee, then every day for " .. Ops.TERM_DAYS .. " days; a check-in visit renews it. Pin a client to visit it next, skip to leave it out.", 4)
	safetyNote(head, 5)
	local road = Kit.card(parent, 2)
	title(road, "On the road")
	local roadRows = Kit.stack(road, 6, 2)
	local list = Kit.stack(parent, 8, 3)
	-- group headings with some air above them (the list itself is packed at 8 px)
	local captions: { [string]: TextLabel } = {}
	local captionRows: { [string]: Frame } = {}
	for group, order in GROUPS do
		local holder = Kit.frame(list, UDim2.new(1, 0, 0, 30))
		holder.Name = "Group_" .. group
		holder.LayoutOrder = order
		local cap = Kit.text(holder, "", 15, F.bold, C.text)
		cap.AnchorPoint = Vector2.new(0, 1)
		cap.Position = UDim2.new(0, 2, 1, -2)
		captions[group] = cap
		captionRows[group] = holder
	end
	local rows: { ClientRow } = {}
	for _, c in Ops.CLIENTS do table.insert(rows, clientRow(list, c)) end
	local log = Kit.card(parent, 4)
	title(log, "Company log")
	local logText = Kit.para(log, "", 13, C.muted, 2)
	local roadSig: string? = nil
	watch(function(s)
		local e = s.data.empire
		local d = if typeof(e.deals) == "table" then e.deals else Ops.newDeals()
		local ops = if typeof(s.live.ops) == "table" then s.live.ops else {}
		local accounts, retainer = 0, 0
		if typeof(d.accounts) == "table" then
			for id in d.accounts do
				local c = Ops.client(id)
				accounts += 1
				if c then retainer += c.retainer end
			end
		end
		local limit = Ops.accountLimit(e)
		local reps = Ops.fieldReps(e)
		local trips = if typeof(ops.trips) == "table" then ops.trips else (if typeof(d.tripList) == "table" then d.tripList else {})
		mAccounts.value.Text = string.format("%d / %d", accounts, limit)
		mRetainers.value.Text = dollars(retainer) .. "/day"
		mReps.value.Text = tostring(reps)
		mTrips.value.Text = tostring(#trips)
		local slots = Ops.stage(e).clients
		summary.Text = string.format("%d of %d account slots in use (%s: %d slots, you %d + field reps %d × %d). Retainers pay %s/day.",
			accounts, limit, stageName(Ops.stageIndex(e)), slots, Ops.FOUNDER_ACCOUNTS, reps, Ops.ACCOUNTS_PER_REP, dollars(retainer))
		local sig = ""
		for _, t in trips do sig ..= tostring(t.client) .. tostring(t.kind) .. "|" end
		if sig ~= roadSig then
			roadSig = sig
			clearRows(roadRows)
			for i, t in trips do
				local line = Kit.para(roadRows, "", 14, C.text, i)
				line.Name = "Trip_" .. tostring(t.client)
			end
			if #trips == 0 then
				Kit.para(roadRows, "Nobody is travelling right now.", 14, C.dim, 1).Name = "Empty"
			end
		end
		for _, t in trips do
			local line = roadRows:FindFirstChild("Trip_" .. tostring(t.client))
			if line and line:IsA("TextLabel") then line.Text = tripText(s, t) end
		end
		local counts: { [string]: number } = { account = 0, lead = 0, needs = 0, later = 0 }
		for _, row in rows do
			row.update(s)
			local g = row.frame:GetAttribute("Group")
			if typeof(g) == "string" then counts[g] = (counts[g] or 0) + 1 end
		end
		captions.account.Text = string.format("Accounts (%d)", counts.account)
		captions.lead.Text = string.format("Leads (%d)", counts.lead)
		local anyLive = false
		for _, id in s.data.modelOrder do local m = s.data.models[id]; if m and m.status == "live" then anyLive = true; break end end
		captions.needs.Text = string.format(if anyLive then "Needs a better model (%d)" else "Needs a live model (%d)", counts.needs)
		captions.later.Text = string.format("Later stages (%d)", counts.later)
		for group, holder in captionRows do holder.Visible = (counts[group] or 0) > 0 end
		local news = if typeof(d.news) == "table" then d.news else {}
		local lines = {}
		for i = 1, math.min(Ops.NEWS_SHOWN, #news) do table.insert(lines, tostring(news[i])) end
		logText.Text = if #lines > 0 then table.concat(lines, "\n") else "Nothing happened yet. Every automatic decision (trips, signings, hires, prices, Save mode) is written here."
	end)
end

-- Money (CORE_SPEC 4 / 6): P&L per company day from the replicated ledger -------------------------------------
local LABELS: { [string]: string } = {
	market = "AI products (users + API)", api = "API access sales", b2b = "Client retainers", pilot = "Pilot fees", studio = "Studio briefs",
	guest = "Guest house", retail = "Café & stores", daily = "Daily grant", quest = "Milestones", shop = "Shop", campus = "Campus",
	wages = "Wages", ops = "Operations staff", upkeep = "Rent & utilities", food = "Lunch", fleet = "Fleet leases", trips = "Trips & hotels",
	b2bserve = "Client serving", jet = "Company jet", jetbuy = "Jet purchase", hire = "Hiring fees", research = "Research", lab = "Lab levels",
	office = "Office move", gpu = "GPUs", data = "Training data", training = "Training runs", refine = "Refinement", marketing = "Marketing",
	travel = "Travel", cars = "Cars", other = "Other", admin = "Admin", debug = "Debug",
}
local COST_LABELS: { [string]: string } = { market = "Serving & power", guest = "Guest house running", campus = "Campus purchases" }
function App.categoryLabel(cat: string, cost: boolean): string
	if cost and COST_LABELS[cat] then return COST_LABELS[cat] end
	local known = LABELS[cat]
	if known then return known end
	return string.upper(string.sub(cat, 1, 1)) .. string.sub(cat, 2)
end
-- one company day of the ledger: sorted lines and totals (whole dollars, zero lines dropped)
function App.ledgerDay(entry: any): ({ { cat: string, value: number } }, { { cat: string, value: number } }, number, number)
	local function side(map: any): ({ { cat: string, value: number } }, number)
		local out, total = {}, 0
		if typeof(map) == "table" then
			for cat, v in map do
				local n = tonumber(v) or 0
				if n > 0 and typeof(cat) == "string" then table.insert(out, { cat = cat, value = n }); total += n end
			end
		end
		table.sort(out, function(a, b) if a.value ~= b.value then return a.value > b.value end; return a.cat < b.cat end)
		return out, total
	end
	local income, inTotal = side(if typeof(entry) == "table" then entry.i else nil)
	local costs, outTotal = side(if typeof(entry) == "table" then entry.o else nil)
	return income, costs, inTotal, outTotal
end
function App.ledgerDays(ledger: any): { number }
	local days = {}
	if typeof(ledger) == "table" then for key in ledger do local n = tonumber(key); if n then table.insert(days, n) end end end
	table.sort(days, function(a, b) return a > b end)
	return days
end
-- One label / value row of the Money tab. Rows are built once and only their texts, colours and visibility change on
-- snapshots (the ledger moves every tick and live rates every snapshot: no GuiObject churn).
type LineRow = { frame: Frame, label: TextLabel, value: TextLabel, set: (label: string, value: string, color: Color3) -> () }
local function lineRow(parent: Instance, order: number, label: string, value: string, color: Color3, bold: boolean?): LineRow
	local row = Kit.frame(parent, UDim2.new(1, 0, 0, 22))
	row.LayoutOrder = order
	local l = Kit.cell(row, label, UDim.new(0.62, 0), 14, if bold then F.bold else F.regular, if bold then C.text else C.muted)
	l.Position = UDim2.new()
	l.TextTruncate = Enum.TextTruncate.AtEnd
	local v = Kit.cell(row, value, UDim.new(0.38, 0), 14, F.bold, color)
	v.Position = UDim2.fromScale(0.62, 0)
	v.TextXAlignment = Enum.TextXAlignment.Right
	local made: LineRow = { frame = row, label = l, value = v, set = function(_a: string, _b: string, _c: Color3) end }
	made.set = function(newLabel: string, newValue: string, newColor: Color3)
		if l.Text ~= newLabel then l.Text = newLabel end
		if v.Text ~= newValue then v.Text = newValue end
		v.TextColor3 = newColor
	end
	return made
end
-- signed whole dollars for the ledger: "+$1,200", "-$300", and a grey "$0" (never "+$0")
local function signed(n: number, sign: string): (string, Color3)
	if math.abs(n) < 0.5 then return "$0", C.dim end
	return sign .. dollars(math.abs(n)), if sign == "-" then C.bad else C.good
end
-- the running rates of the Money tab, in a fixed order (live.ops $/min per category; serving & power = the rest)
local RATE_COSTS = { "wages", "ops", "upkeep", "food", "fleet", "guest", "jet", "b2bserve" }
local function money(parent: Instance)
	local today = Kit.card(parent, 1)
	local todayTitle = title(today, "Today")
	-- day picker: the category breakdown of any replicated company day (CompanyOps.LEDGER_SHOWN), today by default
	local picker = Kit.frame(today, UDim2.new(1, 0, 0, Kit.tap(36, TAP)))
	picker.Name = "DayPicker"
	picker.LayoutOrder = 2
	local todayText = para(today, "", 3)
	local cols = Kit.frame(today, UDim2.fromScale(1, 0))
	cols.AutomaticSize = Enum.AutomaticSize.Y
	cols.LayoutOrder = 4
	local left = Kit.frame(cols, UDim2.new(0.5, -12, 0, 0))
	left.Name = "Income"
	left.AutomaticSize = Enum.AutomaticSize.Y
	Kit.list(left, 2)
	local right = Kit.frame(cols, UDim2.new(0.5, -12, 0, 0), UDim2.new(0.5, 12, 0, 0))
	right.Name = "Costs"
	right.AutomaticSize = Enum.AutomaticSize.Y
	Kit.list(right, 2)
	Kit.caption(left, "Income", 0)
	Kit.caption(right, "Costs", 0)
	local noIncome = lineRow(left, 1, "No income yet", "$0", C.dim)
	local noCosts = lineRow(right, 1, "No costs yet", "$0", C.dim)
	local inTotalRow = lineRow(left, 999, "Total", "$0", C.dim, true)
	local outTotalRow = lineRow(right, 999, "Total", "$0", C.dim, true)
	local catRows: { [string]: LineRow } = {} -- "i:market", "o:wages", ... (created the first time a category appears)
	local net = Kit.text(today, "", 20, F.display, C.text)
	net.Name = "Net"
	net.LayoutOrder = 5
	local days = Kit.card(parent, 2)
	title(days, "Last company days")
	local daysText = para(days, "", 2)
	local tableFrame = Kit.stack(days, 2, 3)
	tableFrame.Name = "DayTable"
	local chart = Kit.frame(days, UDim2.new(1, 0, 0, 96))
	chart.Name = "DayChart"
	chart.LayoutOrder = 4
	local running = Kit.card(parent, 3)
	title(running, "Running now, per game day")
	local runRows = Kit.stack(running, 2, 2)
	runRows.Name = "Rates"
	local runEmpty = Kit.para(running, "Rates appear after the first update.", 14, C.dim, 3)
	runEmpty.Name = "RatesEmpty"
	dim(running, "Live rates at this moment (a game day is 20 minutes: 15 min day, 5 min night). Wages are paid day and night, also during vacation and sick days.", 4)
	-- running rows: fixed lines, built once
	type Rate = { key: string, income: boolean, row: LineRow }
	local rates: { Rate } = {}
	for i, key in { "market", "b2b", "guest" } do
		table.insert(rates, { key = key, income = true, row = lineRow(runRows, i, App.categoryLabel(key, false), "", C.good) })
	end
	for i, key in RATE_COSTS do
		table.insert(rates, { key = key, income = false, row = lineRow(runRows, 10 + i, App.categoryLabel(key, true), "", C.bad) })
	end
	table.insert(rates, { key = "serving", income = false, row = lineRow(runRows, 30, "Serving & power", "", C.bad) })
	local netRate = lineRow(runRows, 40, "Net", "", C.dim, true)
	-- day table + chart: rebuilt only when the set of days changes (a new company day), cells updated in place
	type DayCols = { head: { TextLabel }, cells: { { TextLabel } }, bars: { Frame }, zero: Frame? }
	local dayCols: DayCols = { head = {}, cells = {}, bars = {}, zero = nil }
	local daysKey: string? = nil
	local pickSig: string? = nil
	local picked: number? = nil -- nil = today
	local update: (any) -> () = function(_s: any) end
	update = function(s: any)
		local e = s.data.empire
		local ledger = if typeof(e.ledger) == "table" then e.ledger else {}
		local dayNow = Ops.day(e)
		local list = App.ledgerDays(ledger)
		-- the picker lists the replicated days, oldest left, today right
		local pick = {}
		for i = math.min(#list, Ops.LEDGER_SHOWN), 1, -1 do table.insert(pick, list[i]) end
		if #pick == 0 or pick[#pick] ~= dayNow then table.insert(pick, dayNow) end
		local shownDay = if picked and ledger[tostring(picked)] ~= nil and picked ~= dayNow then picked :: number else dayNow
		local pk = tostring(dayNow) .. ":" .. table.concat(pick, ",")
		if pk ~= pickSig then
			pickSig = pk
			clearRows(picker)
			local options: { Kit.Option } = {}
			for _, day in pick do table.insert(options, { id = tostring(day), label = if day == dayNow then "Today" else "Day " .. day }) end
			local seg = Kit.segmented(picker, options, tostring(shownDay), function(id)
				local n = tonumber(id)
				picked = if n == dayNow then nil else n
				if State.snapshot then update(State.snapshot) end
			end, Kit.tap(36, TAP))
			seg.frame.Size = UDim2.new(math.min(1, 0.2 * #options), 0, 0, Kit.tap(36, TAP))
		end
		picker.Visible = #pick >= 2
		local isToday = shownDay == dayNow
		local income, costs, inTotal, outTotal = App.ledgerDay(ledger[tostring(shownDay)])
		todayTitle.Text = if isToday then "Today · day " .. dayNow else "Day " .. shownDay
		todayText.Text = if #income + #costs == 0 then (if isToday then "Nothing booked yet today." else "Nothing was booked that day.")
			elseif isToday then "Every dollar of today, by category (the company day started at 08:00)."
			else "Every dollar of company day " .. shownDay .. ", by category."
		-- category rows: shown / hidden / re-ordered, never rebuilt
		local seen: { [string]: boolean } = {}
		local function place(side: string, parentFrame: Frame, lines: { { cat: string, value: number } })
			for i, l in lines do
				local key = side .. ":" .. l.cat
				local r = catRows[key]
				if r == nil then
					local made = lineRow(parentFrame, i + 1, "", "", C.text)
					made.frame.Name = "Cat_" .. key
					catRows[key] = made
					r = made
				end
				assert(r)
				seen[key] = true
				r.frame.LayoutOrder = i + 1
				r.frame.Visible = true
				r.set(App.categoryLabel(l.cat, side == "o"), (if side == "i" then "+" else "-") .. dollars(l.value), if side == "i" then C.good else C.bad)
			end
		end
		place("i", left, income)
		place("o", right, costs)
		for key, r in catRows do if not seen[key] then r.frame.Visible = false end end
		noIncome.frame.Visible = #income == 0
		noCosts.frame.Visible = #costs == 0
		local inText, inColor = signed(inTotal, "+")
		local outText, outColor = signed(outTotal, "-")
		inTotalRow.set("Total", inText, inColor)
		outTotalRow.set("Total", outText, outColor)
		local n = inTotal - outTotal
		local netText = if math.abs(n) < 0.5 then "$0" else (if n > 0 then "+" else "") .. dollars(n)
		net.Text = (if isToday then "Net today  " else "Net day " .. shownDay .. "  ") .. netText
		net.TextColor3 = if n >= 0.5 then C.good elseif n <= -0.5 then C.bad else C.muted
		-- last days: oldest left, today right
		local shown = {}
		for i = math.min(#list, Ops.LEDGER_SHOWN), 1, -1 do table.insert(shown, list[i]) end
		daysText.Text = if #shown <= 1 then "The table fills up day by day (the last " .. Ops.LEDGER_SHOWN .. " company days are kept here)." else string.format("The last %d company days (today so far on the right).", #shown)
		local dk = tostring(dayNow) .. "|" .. table.concat(shown, ",")
		local w = 1 / (#shown + 1)
		if dk ~= daysKey then
			daysKey = dk
			clearRows(tableFrame)
			clearRows(chart)
			dayCols = { head = {}, cells = {}, bars = {}, zero = nil }
			local head = Kit.frame(tableFrame, UDim2.new(1, 0, 0, 22))
			head.LayoutOrder = 0
			Kit.cell(head, "", UDim.new(w, 0), 13, F.medium, C.muted)
			for j, day in shown do
				local cell = Kit.cell(head, if day == dayNow then "Day " .. day .. " (today)" else "Day " .. day, UDim.new(w, 0), 13, F.bold, C.muted)
				cell.Position = UDim2.fromScale(w * j, 0)
				cell.TextXAlignment = Enum.TextXAlignment.Right
				dayCols.head[j] = cell
			end
			for r, rowName in { "Income", "Costs", "Net" } do
				local row = Kit.frame(tableFrame, UDim2.new(1, 0, 0, 22))
				row.LayoutOrder = r
				Kit.cell(row, rowName, UDim.new(w, 0), 14, if r == 3 then F.bold else F.regular, if r == 3 then C.text else C.muted)
				dayCols.cells[r] = {}
				for j in shown do
					local cell = Kit.cell(row, "", UDim.new(w, 0), 14, F.bold, C.text)
					cell.Position = UDim2.fromScale(w * j, 0)
					cell.TextXAlignment = Enum.TextXAlignment.Right
					dayCols.cells[r][j] = cell
				end
			end
			local zero = Kit.frame(chart, UDim2.new(1, 0, 0, 1))
			zero.BackgroundTransparency = 0.5
			zero.BackgroundColor3 = C.dim
			dayCols.zero = zero
			for j in shown do
				local b = Kit.frame(chart, UDim2.new(w * 0.5, 0, 0, 0), UDim2.fromScale(w * j + w * 0.45, 0))
				b.Name = "Bar" .. j
				b.BackgroundTransparency = 0.15
				Kit.corner(b, 3)
				dayCols.bars[j] = b
			end
		end
		tableFrame.Visible = #shown >= 1
		chart.Visible = #shown >= 1
		local totals: { { number } } = {}
		local hi, lo = 0, 0
		for j, day in shown do
			local _, _, a, b = App.ledgerDay(ledger[tostring(day)])
			totals[j] = { a, b, a - b }
			hi = math.max(hi, a - b)
			lo = math.min(lo, a - b)
		end
		for r = 1, 3 do
			for j, t in totals do
				local cell = dayCols.cells[r] and dayCols.cells[r][j]
				if cell then
					local v = t[r]
					local text, color = signed(v, if r == 1 then "+" elseif r == 2 then "-" elseif v >= 0 then "+" else "-")
					if cell.Text ~= text then cell.Text = text end
					cell.TextColor3 = color
				end
			end
		end
		-- net bars per day (zero line placed by the largest gain and loss, like the profit chart)
		local range = math.max(1, hi - lo)
		local zeroY = hi / range
		if dayCols.zero then dayCols.zero.Position = UDim2.fromScale(0, zeroY) end
		for j, t in totals do
			local b = dayCols.bars[j]
			if b then
				b.Size = UDim2.new(w * 0.5, 0, math.abs(t[3]) / range, 0)
				b.Position = UDim2.fromScale(w * j + w * 0.45, zeroY)
				b.AnchorPoint = Vector2.new(0, if t[3] >= 0 then 1 else 0)
				b.BackgroundColor3 = if t[3] >= 0 then C.good else C.bad
			end
		end
		-- running rates per game day from the live summary (live.ops: $/min per category), updated in place
		local ops = if typeof(s.live.ops) == "table" then s.live.ops else nil
		local revenueMin = (tonumber(s.live.revenue) or 0) * 60
		local costMin = (tonumber(s.live.cost) or 0) * 60
		local any = ops ~= nil and (revenueMin > 0.5 or costMin > 0.5)
		runEmpty.Visible = ops == nil
		local o: any = ops or {}
		local known = 0
		for _, key in RATE_COSTS do known += tonumber(o[key .. "Cost"]) or 0 end
		for _, r in rates do
			local v = if r.key == "market" then math.max(0, revenueMin - (tonumber(o.b2b) or 0) - (tonumber(o.guest) or 0))
				elseif r.key == "serving" then math.max(0, costMin - known)
				elseif r.income then tonumber(o[r.key]) or 0
				else tonumber(o[r.key .. "Cost"]) or 0
			r.row.frame.Visible = any and v > 0.5
			if r.row.frame.Visible then
				r.row.set(r.row.label.Text, (if r.income then "+" else "-") .. perDay(v), if r.income then C.good else C.bad)
			end
		end
		local netMin = revenueMin - costMin
		netRate.frame.Visible = ops ~= nil
		if not any or math.abs(netMin * Ops.DAY / 60) < 0.5 then
			netRate.set("Net", "$0/day", C.dim)
		else
			netRate.set("Net", (if netMin >= 0 then "+" else "-") .. perDay(math.abs(netMin)), if netMin >= 0 then C.good else C.bad)
		end
	end
	watch(update)
end

-- Team section: open applications (invite → the candidate walks to the visitor lounge for an in-person
-- interview), the hired team with persistent names, revealed skill and individual wage, and the
-- instant agency hires below.
local function stars(k: number): string
	local n = math.clamp(math.floor(k + 0.5), 1, 5)
	return string.rep("★", n) .. string.rep("☆", 5 - n)
end
local function applications(parent: Instance, order: number)
	local card = Kit.card(parent, order)
	title(card, "Applications")
	local info = para(card, "", 2)
	local rows = Kit.stack(card, 8, 3)
	local signature: string? = nil
	local expiry: { [string]: TextLabel } = {}
	watch(function(s)
		local e = s.data.empire
		local list = e.applicants or {}
		local full = Math.staff(e) >= Config.OFFICES[e.office].staff
		info.Text = if #list == 0 then (if full then "Every desk is filled, so nobody is applying. Upgrade your office to grow the team." else "No open applications right now. While desks are free, a new candidate applies every few minutes.")
			else "Invite a candidate and they walk to the visitor lounge on the ground floor. Talk to them there: the interview decides whether you hire them. Applications close after 30 minutes."
		local sig = ""
		for _, a in list do sig ..= a.id .. a.st .. "|" end
		sig ..= tostring(Math.staff(e))
		if sig ~= signature then
			signature = sig
			clearRows(rows)
			table.clear(expiry)
			for i, a in list do
				local roleDef = Config.find(Config.ROLES, a.role)
				local row = Kit.frame(rows, UDim2.new(1, 0, 0, Kit.tap(52, TAP)))
				row.LayoutOrder = i
				local initials = ""
				for word in string.gmatch(a.n, "%S+") do initials ..= string.sub(word, 1, 1) end
				Conversation.avatar(row, string.upper(string.sub(initials, 1, 2)), a.s, 40).Position = UDim2.new(0, 0, 0.5, -20)
				local name = Kit.text(row, a.n, 16, F.bold, C.text)
				name.Position = UDim2.fromOffset(52, 4)
				-- same price the server charges (RecruitingService.hireCost: escalates with the team size)
				local cost = if roleDef then Format.money(math.floor(Math.hireCost(e, roleDef) * a.ask + 0.5)) else "?"
				local sub = Kit.text(row, string.format("%s  ·  %d yrs  ·  ex-%s  ·  asks %s", if roleDef then roleDef.name else a.role, a.xp, a.prev, cost), 13, F.regular, C.muted)
				sub.Position = UDim2.fromOffset(52, 27)
				sub.AutomaticSize = Enum.AutomaticSize.None
				sub.Size = UDim2.new(1, -Kit.tap(250, 300), 0, 18)
				sub.TextTruncate = Enum.TextTruncate.AtEnd
				local status = Kit.text(row, "", 12, F.medium, C.muted)
				status.AnchorPoint = Vector2.new(1, 0)
				status.Position = UDim2.new(1, -Kit.tap(180, 240), 0, 6)
				status.TextXAlignment = Enum.TextXAlignment.Right
				if a.st == "new" then
					expiry[a.id] = status
					local invite = Kit.button(row, "Invite", "primary", UDim2.fromOffset(Kit.tap(86, 110), Kit.tap(34, 80)))
					invite.AnchorPoint = Vector2.new(1, 0.5)
					invite.Position = UDim2.new(1, -Kit.tap(90, 122), 0.5, 0)
					invite.TextSize = 15
					Kit.onClick(invite, function()
						task.spawn(function()
							local ok = People.call("RecruitAction", { action = "invite", id = a.id })
							if ok then Toast.show("success", a.n .. " is on the way to your visitor lounge.", 4) end
						end)
					end)
				else
					status.Text = if a.st == "interviewing" then "In the interview" else "Waiting in the visitor lounge (G)"
					Theme.bindAccent(status, "TextColor3")
				end
				local reject = Kit.button(row, "Reject", "danger", UDim2.fromOffset(Kit.tap(80, 110), Kit.tap(34, 80)))
				reject.AnchorPoint = Vector2.new(1, 0.5)
				reject.Position = UDim2.new(1, 0, 0.5, 0)
				reject.TextSize = 15
				Kit.onClick(reject, function()
					task.spawn(function()
						local ok = People.call("RecruitAction", { action = "reject", id = a.id })
						if ok then Toast.show("info", "Application from " .. a.n .. " declined.", 3) end
					end)
				end)
			end
		end
		for _, a in list do
			local label = expiry[a.id]
			if label then label.Text = "Closes in " .. Kit.countdown(math.max(0, Math.APPLICATION_SECONDS - ((e.seconds or 0) - a.at))) end
		end
	end)
end
local ROSTER_LIMIT = 40
local function roster(parent: Instance, order: number)
	local card = Kit.card(parent, order)
	title(card, "Your team")
	local summary = para(card, "", 2)
	local filter = "all"
	local signature: string? = nil
	local rows: Frame
	local more: TextLabel
	local function update(s: any)
		local e = s.data.empire
		local profiles = e.staffProfiles or {}
		local total, skill, payroll = 0, 0, 0
		local entries = {}
		local day = Ops.day(e)
		for _, roleDef in Config.ROLES do
			local list = profiles[roleDef.id] or {}
			for i = 1, e.employees[roleDef.id] or 0 do
				local p = list[i]
				local k = if p and typeof(p.k) == "number" then p.k else 3
				local w = if p and typeof(p.w) == "number" then p.w else 1
				local apprentice = if p and typeof(p.s) == "number" then (Ops.apprentice(e, p.s, day)) else nil
				total += 1; skill += k; payroll += roleDef.wage * w
				if filter == "all" or filter == roleDef.id then
					table.insert(entries, { role = roleDef, index = i, name = if p and typeof(p.n) == "string" then p.n else "New hire", k = k, wage = roleDef.wage * w, apprentice = apprentice ~= nil })
				end
			end
		end
		summary.Text = if total == 0 then "Nobody works here yet. Interview applicants or hire through the agency below."
			else string.format("%d people  ·  average skill %.1f ★  ·  payroll $%.2f/s  ·  skill ★1–★5 changes each person's output from 80%% to 120%%", total, skill / total, payroll)
		table.sort(entries, function(a, b) if a.k ~= b.k then return a.k > b.k end; return a.name < b.name end)
		local sig = filter
		for n, entry in entries do if n > ROSTER_LIMIT then break end; sig ..= entry.role.id .. entry.index .. entry.name .. entry.k .. string.format("%.3f", entry.wage) .. tostring(entry.apprentice) end
		if sig == signature then return end
		signature = sig
		clearRows(rows)
		for n, entry in entries do
			if n > ROSTER_LIMIT then break end
			local row = Kit.frame(rows, UDim2.new(1, 0, 0, Kit.tap(34, 72)))
			row.LayoutOrder = n
			Kit.cell(row, entry.name, UDim.new(0.3, 0), 15, F.bold, C.text).Position = UDim2.new()
			local roleCell = Kit.cell(row, if entry.apprentice then entry.role.name .. " · apprentice" else entry.role.name, UDim.new(0.22, 0), 13, F.regular, C.muted)
			roleCell.Position = UDim2.fromScale(0.3, 0)
			local starCell = Kit.cell(row, stars(entry.k), UDim.new(0.18, 0), 15, F.bold, C.warn)
			starCell.Position = UDim2.fromScale(0.52, 0)
			local wageCell = Kit.cell(row, string.format("$%.2f/s", entry.wage), UDim.new(0.14, 0), 13, F.medium, C.muted)
			wageCell.Position = UDim2.fromScale(0.7, 0)
			local dismiss = Kit.button(row, "Dismiss", "ghost", UDim2.new(0.15, 0, 1, -4))
			dismiss.AnchorPoint = Vector2.new(1, 0)
			dismiss.Position = UDim2.new(1, 0, 0, 2)
			dismiss.TextSize = 13
			Kit.onClick(dismiss, function()
				call("FireEmployee", { roleId = entry.role.id, index = entry.index, name = entry.name }, entry.name .. " left the company.")
			end)
		end
		more.Text = if #entries > ROSTER_LIMIT then string.format("+ %d more (showing the %d most skilled)", #entries - ROSTER_LIMIT, ROSTER_LIMIT) else ""
		more.Visible = #entries > ROSTER_LIMIT
	end
	local selector = Kit.segmented(card, { { id = "all", label = "All" }, { id = "researcher", label = "Research" }, { id = "engineer", label = "Engineering" }, { id = "curator", label = "Data" }, { id = "marketer", label = "Growth" } }, filter, function(id)
		filter = id
		signature = nil
		if State.snapshot then update(State.snapshot) end
	end, Kit.tap(38, 62)) -- fix round 1 (review): 56 px chips on touch = 44.8 pt on an iPhone (legacy page x 0.80)
	selector.frame.LayoutOrder = 3
	rows = Kit.stack(card, 4, 4)
	more = para(card, "", 5)
	watch(update)
end
-- fix round 1 (review, B9 "hire cards first" / B10 "Hire: 3 taps, 0 swipes"): applications and the four Hire cards
-- come first, the roster and the long explanation under them
local function team(parent: Instance)
	local intro = Kit.card(parent, 8)
	title(intro, "Specialists, real advantages")
	local capacity = para(intro, "")
	watch(function(s)
		local e = s.data.empire
		capacity.Text = string.format("%d / %d desks filled. Staff earn wages every second, day and night (also on vacation and sick days). Bonuses stop when you dismiss an employee. Hiring fees are non-refundable. Agency hires start at once with average skill (★2–★3); interviewing applicants is how you find stronger people. Automatic HR and apprentices: Team → Settings.",Math.staff(e),Config.OFFICES[e.office].staff)
	end)
	safetyNote(intro, 3)
	applications(parent, 1)
	roster(parent, 7)
	for i, role in Config.ROLES do
		local card = Kit.card(parent, i+1)
		title(card, role.name)
		para(card, role.desc)
		local info = para(card, "", 3)
		local row = Kit.row(card,Kit.tap(40, TAP),10,4)
		local hire = Kit.button(row,"Hire","primary",UDim2.new(0.4,-6,1,0))
		local group = Kit.button(row,"Hire 5","secondary",UDim2.new(0.35,-6,1,0))
		local fire = Kit.button(row,"Dismiss one","secondary",UDim2.new(0.25,-6,1,0))
		Kit.onClick(hire,function() call("HireEmployee",{roleId=role.id},role.name .. " hired!") end)
		Kit.onClick(group,function()call("HireEmployee",{roleId=role.id,count=5},"Five specialists hired!")end)
		Kit.onClick(fire,function() call("FireEmployee",{roleId=role.id},"Employee dismissed.") end)
		watch(function(s)
			local e=s.data.empire
			local count=e.employees[role.id] or 0
			local price=Math.hireCost(e,role)
			info.Text=string.format("On your team: %d  ·  Wage: $%.2f/s each (%s/day)",count,role.wage,dollars(role.wage*Ops.DAY))
			hire.Text="Hire · " .. Format.money(price)
			Kit.setDisabled(hire,Math.staff(e)>=Config.OFFICES[e.office].staff or s.data.money<price)
			local groupCost=0
			for j=0,4 do groupCost+=Math.hireCost({employees={[role.id]=count+j}},role) end
			group.Text="Hire 5 · "..Format.money(groupCost)
			Kit.setDisabled(group,Math.staff(e)+5>Config.OFFICES[e.office].staff or s.data.money<groupCost)
			Kit.setDisabled(fire,count==0)
		end)
	end
end
-- Lab → Research (shop package, SHOP_SPEC 5.2.2): a status row (RESEARCH POINTS · SPEED IN OFFICE HOURS · message) and
-- the projects as cards in 2 columns. Each card has its free action first (START · $cost, or why not) and, only when
-- it works right now, a secondary Eureka button beside it (ShopCore.eurekaOffer: guide over, Shop unlocked, never
-- within 10 s of a failure; the Robux state only for a saving >= 30 s). The note line says what a Eureka saves and
-- what it does not cover. Sizes for this page's scale (0.80 on an iPhone): text >= 15 px = 12 pt, buttons 56 px.
-- Fix round 1 (review): the Robux (buy) state shows on ONE idle card only (the card a deep link asked for, else the
-- cheapest one it works on), so a page with 0 RP is never a wall of Robux buttons; an owned Eureka shows on every
-- card it works on (a bought voucher is never stranded).
local RT = { caption = 15, body = 16, title = 21, button = 56 }
local function research(parent: Instance)
	local status = Kit.card(parent, 1, 8)
	status.Name = "ResearchStatus"
	local cells = Kit.frame(status, UDim2.new(1, 0, 0, 52))
	cells.LayoutOrder = 1
	Kit.list(cells, 24, true)
	local function cell(caption: string, order: number, width: number): TextLabel
		local f = Kit.frame(cells, UDim2.new(0, width, 1, 0))
		f.LayoutOrder = order
		local c = Kit.text(f, caption, RT.caption, F.bold, C.muted)
		c.Position = UDim2.fromOffset(0, 0)
		local v = Kit.text(f, "", 24, F.bold, C.text)
		v.Position = UDim2.fromOffset(0, 22)
		return v
	end
	local pointsValue = cell("RESEARCH POINTS", 1, 190)
	pointsValue.Name = "ResearchPoints"
	local speedValue = cell("SPEED IN OFFICE HOURS", 2, 220)
	speedValue.Name = "ResearchSpeed"
	local message = Kit.para(status, "", RT.body, C.muted, 2)
	message.Name = "ResearchMessage"
	local bar = Kit.bar(status, 8, 3)
	local grid = Kit.frame(parent, UDim2.fromScale(1, 0))
	grid.Name = "ResearchCards"
	grid.LayoutOrder = 2
	grid.AutomaticSize = Enum.AutomaticSize.Y
	Kit.list(grid, 12)
	type CardRefs = { def: any, card: Frame, stroke: UIStroke, done: TextLabel, meta: TextLabel, free: TextButton, offer: ShopCore.OfferButton, note: TextLabel, bar: Kit.Bar, buttons: Frame }
	local cards: { CardRefs } = {}
	local row: Frame? = nil
	for i, def in Config.RESEARCH do
		if i % 2 == 1 then
			local r = Kit.frame(grid, UDim2.fromScale(1, 0))
			r.LayoutOrder = i
			r.AutomaticSize = Enum.AutomaticSize.Y
			Kit.list(r, 12, true).VerticalAlignment = Enum.VerticalAlignment.Top -- cards of a row start at the same line
			row = r
		end
		local card = Kit.card(row :: Frame, i, 8)
		card.Name = "Research_" .. def.id
		card.Size = UDim2.new(0.5, -6, 0, 0)
		local stroke = Kit.stroke(card, 1, Theme.accent, 3)
		stroke.Name = "Focus"
		local head = Kit.frame(card, UDim2.new(1, 0, 0, 30))
		head.LayoutOrder = 1
		local name = Kit.text(head, def.name, RT.title, F.bold, C.text)
		name.Name = "Name"
		local done = Kit.text(head, "✓ DONE", RT.caption, F.bold, C.good)
		done.Name = "Done"
		done.AnchorPoint = Vector2.new(1, 0)
		done.Position = UDim2.fromScale(1, 0)
		done.BackgroundTransparency = 0.85
		done.BackgroundColor3 = C.good
		Kit.corner(done, 6)
		Kit.padding(done, 3, 8, 3, 8)
		local meta = Kit.text(card, string.format("%s · %d RP · %s", Format.money(def.cost), def.points, Format.duration(def.seconds)), RT.body, F.bold, C.text)
		meta.LayoutOrder = 2
		local desc = Kit.para(card, def.desc, RT.body, C.muted, 3)
		desc.Name = "Desc"
		local buttons = Kit.frame(card, UDim2.new(1, 0, 0, RT.button))
		buttons.Name = "Buttons"
		buttons.LayoutOrder = 4
		Kit.list(buttons, 10, true)
		local free = Kit.button(buttons, "", "primary", UDim2.new(0.5, -5, 1, 0))
		free.Name = "Start"
		free.TextSize = RT.body
		free.TextWrapped = true
		free.LayoutOrder = 1
		free.Selectable = true
		local offer = ShopCore.offerButton(buttons, "EUREKA", UDim2.new(0.5, -5, 1, 0), RT.body)
		offer.button.Name = "Eureka"
		offer.button.LayoutOrder = 2
		local cardBar = Kit.bar(card, 8, 5)
		local note = Kit.para(card, "", RT.caption, C.muted, 6)
		note.Name = "Note"
		note.RichText = true
		local refs: CardRefs = { def = def, card = card, stroke = stroke, done = done, meta = meta, free = free, offer = offer, note = note, bar = cardBar, buttons = buttons }
		table.insert(cards, refs)
		Kit.onClick(free, function()
			call("StartResearch", { researchId = def.id }, "Research started: " .. def.name)
		end)
		Kit.onClick(offer.button, function()
			local snapshot = State.snapshot
			if not snapshot then return end
			local job = snapshot.data.empire.researchJob
			local target = if job then job.id else def.id
			local state = offer.button:GetAttribute("OfferState")
			if state == "owned" then
				ShopCore.use("eureka", target)
			elseif state == "buy" then
				ShopCore.buy("eureka", target)
			else
				ShopCore.buy("eureka", target) -- preview: says "Not set up", never prompts
			end
		end)
	end
	local focusUntil = 0
	local lastFocus: string? = nil
	watch(function(s)
		local data = s.data
		local e = data.empire
		local job = e.researchJob
		local money = State.money()
		local now = ShopCore.serverNow(s)
		local doneCount = 0
		for _, def in Config.RESEARCH do if e.research[def.id] then doneCount += 1 end end
		pointsValue.Text = Format.int(e.points) .. " RP"
		speedValue.Text = string.format("+%.1f/s", ShopMath.peakRate(data, now))
		if job then
			local def = Config.find(Config.RESEARCH, job.id)
			message.Text = string.format("Researching %s · %s left. %d of %d done.", if def then def.name else job.id, Format.duration(job.seconds - job.elapsed), doneCount, #Config.RESEARCH)
		else
			message.Text = string.format("No project running. Research points come in office hours. %d of %d done.", doneCount, #Config.RESEARCH)
		end
		bar.frame.Visible = job ~= nil
		if job then bar.set(job.elapsed / math.max(1, job.seconds)) end
		-- a deep link from the Model Studio (OPEN RESEARCH ›) asks for one card: outline it for a moment
		local focus = ShopCore.takeFocus("research")
		if focus then
			focusUntil = os.clock() + 3
			lastFocus = focus
		end
		type Plan = { label: string, enabled: boolean, primary: boolean, offerTarget: string?, running: boolean }
		local plans: { [CardRefs]: Plan } = {}
		local offers: { [CardRefs]: { state: string?, check: ShopMath.Check?, right: string } } = {}
		local buyCard: CardRefs? = nil
		for _, r in cards do
			local def = r.def
			local isDone = e.research[def.id] == true
			local running = job ~= nil and job.id == def.id
			local locked = def.prereq ~= nil and not e.research[def.prereq]
			r.done.Visible = isDone
			r.buttons.Visible = not isDone
			r.bar.frame.Visible = running
			if focus == def.id then
				ShopCore.scrollTo(r.card)
			end
			r.stroke.Transparency = if os.clock() < focusUntil and focus ~= nil and focus == def.id then 0.1 else 1
			local label, enabled, primary = "", false, false
			local offerTarget: string? = nil
			if isDone then
				label = ""
			elseif running then
				label = Format.duration(job.seconds - job.elapsed) .. " left"
				r.bar.set(job.elapsed / math.max(1, job.seconds))
				offerTarget = def.id
			elseif job ~= nil then
				label = "Another project is running"
			elseif locked then
				local pre = Config.find(Config.RESEARCH, def.prereq)
				label = "NEEDS " .. string.upper(if pre then pre.name else def.prereq) .. " FIRST"
			elseif money < def.cost then
				label = "NEEDS " .. Format.money(def.cost)
			elseif e.points < def.points then
				label = string.format("NEEDS %d RP", def.points)
				offerTarget = def.id
			else
				label, enabled, primary = "START · " .. Format.money(def.cost), true, true
				offerTarget = def.id
			end
			plans[r] = { label = label, enabled = enabled, primary = primary, offerTarget = offerTarget, running = running }
			local state, check, right = nil, nil, ""
			if offerTarget and not isDone then
				state, check, right = ShopCore.eurekaOffer(s, offerTarget, money)
			end
			offers[r] = { state = state, check = check, right = right }
			-- the one card that may show the Robux (buy / preview) state: the deep link's card, else the cheapest
			if state ~= nil and state ~= "owned" and not running then
				local pick = buyCard
				if pick == nil or (lastFocus == def.id) or (lastFocus ~= pick.def.id and def.cost < pick.def.cost) then
					buyCard = r
				end
			end
		end
		for _, r in cards do
			local def = r.def
			local plan = plans[r]
			local running, label, enabled, primary = plan.running, plan.label, plan.enabled, plan.primary
			r.free.Text = label
			Kit.setDisabled(r.free, not enabled)
			r.free.BackgroundColor3 = if primary then Theme.accent else C.raised
			r.free.TextColor3 = if primary then C.bg else C.muted
			local o = offers[r]
			local state, check, right = o.state, o.check, o.right
			if state ~= nil and state ~= "owned" and not running and r ~= buyCard then
				state, check, right = nil, nil, ""
			end
			r.offer.set(state, right)
			r.offer.label.Text = if running then "FINISH NOW · EUREKA" else "EUREKA"
			local width = if state == nil then 1 elseif running then 0.28 else 0.5 -- "0:25 left" | FINISH NOW · EUREKA | R$ 15
			r.free.Size = UDim2.new(width, if state == nil then 0 else -5, 1, 0)
			r.offer.button.Size = UDim2.new(1 - width, -5, 1, 0)
			if state and check then
				local saves = ShopMath.savingText(check.seconds)
				if running then
					r.note.Text = string.format("Eureka <b>saves %s</b>: its %d RP come back.", saves, check.points)
				elseif e.points >= def.points then
					r.note.Text = string.format("Eureka <b>saves %s</b>: you keep your %s RP, you still pay %s.", saves, Format.int(e.points), Format.money(def.cost))
				else
					r.note.Text = string.format("Eureka <b>saves %s</b>: covers the %d RP, you still pay %s.", saves, def.points, Format.money(def.cost))
				end
				r.note.Visible = true
			else
				r.note.Text = ""
				r.note.Visible = false
			end
		end
	end)
end
-- fix round 1 (review): a goal shows a COLLECT button only when it can be collected; progress and "Collected ✓" are a
-- text line (no full-width disabled buttons that make the page several screens long)
local function milestones(parent: Instance)
	for i,def in Config.QUESTS do
		local card=Kit.card(parent,i)
		title(card,def.name)
		para(card,def.desc .. "  Reward: " .. Format.money(def.reward) .. " + " .. tostring(def.xp) .. " XP")
		local bar=Kit.bar(card,7,3)
		local status=para(card,"",4)
		status.Name="GoalStatus"
		local b=button(card,"Collect",function() call("ClaimQuest",{questId=def.id},"Milestone reward collected!") end)
		watch(function(s)
			local p=Math.progress(s.data,def)
			local done=s.data.empire.quests[def.id]==true
			local ready=not done and p>=def.target
			bar.set(math.min(1,p/def.target))
			bar.frame.Visible=not done
			status.Text=if done then "Collected ✓" else Format.compact(math.min(p,def.target)) .. " / " .. Format.compact(def.target)
			status.TextColor3=if done then C.good else C.muted
			status.Visible=not ready
			b.Text="Collect " .. Format.money(def.reward)
			b.Visible=ready
		end)
	end
end
local function office(parent: Instance)
	local card=Kit.card(parent,1)
	local name=title(card,"Office")
	local info=para(card,"")
	local b=button(card,"Upgrade",function() call("UpgradeOffice",{},"Office expanded. Visit your new building!") end)
	watch(function(s)
		local e=s.data.empire
		local def=Config.OFFICES[e.office]
		local nextOffice=Config.OFFICES[e.office+1]
		name.Text=def.name
		-- 5 stages (CORE_SPEC 2.1): the Garage Lab, then the four headquarters buildings
		local gate=e.office==1 and (tonumber(e.contractsCompleted) or 0)<1
		info.Text=string.format("Stage %d / %d · %d staff desks · %.2f base RP/s · rent & utilities %s/day\n%s",e.office,#Config.OFFICES,def.staff,def.points,dollars(Ops.STAGES[Ops.stageIndex(e)].upkeep),
			if e.office==1 then "A converted garage with 5 team desks, the founder corner and a small GPU shelf. Leaving it needs your first signed business client." else "Floors, campus operations staff, stores, kitchen and underground parking grow with every stage.")
		b.Text=if not nextOffice then "Maximum office reached" elseif gate then "Sign your first client to leave the garage" else "Upgrade: " .. nextOffice.name .. " · " .. Format.money(nextOffice.price)
		Kit.setDisabled(b,nextOffice==nil or gate or (nextOffice~=nil and s.data.money<nextOffice.price))
	end)
	for i,def in Config.OFFICES do
		local row=Kit.card(parent,i+1)
		local head=title(row,tostring(i) .. " · " .. def.name)
		watch(function(s)
			local here=Ops.stageIndex(s.data.empire)==i
			head.Text=tostring(i) .. " · " .. def.name .. (if here then "  ·  your office" else "")
			head.TextColor3=if here then Theme.accent:Lerp(C.white,0.3) else C.text
		end)
		local st=Ops.STAGES[i]
		para(row,string.format("%d employee desks · %d GPU slots · %d product line%s · %d client slots · %s trips · rent & utilities %s/day\n%s",
			def.staff,HardwareConfig.STAGE_SLOTS[i] or 0,ModelMath.productSlots(i),if ModelMath.productSlots(i)==1 then "" else "s",st.clients,st.trips,dollars(st.upkeep),
			if i==1 then "Where every company starts" elseif i==2 then Format.money(def.price) .. " + your first signed client" else Format.money(def.price)))
	end
end

-- Settings (CORE_SPEC 8.1 / 11.1 / 11.2): the player decisions of the automatic company -------------------------
local function apprenticeList(e: any): { { name: string, role: string, day: number, skill: number } }
	local out = {}
	local map = e.apprentices
	if typeof(map) ~= "table" or next(map) == nil or typeof(e.staffProfiles) ~= "table" then return out end
	local today = Ops.day(e)
	for _, roleDef in Config.ROLES do
		local list = e.staffProfiles[roleDef.id]
		if typeof(list) == "table" then
			for i = 1, math.min(#list, e.employees[roleDef.id] or 0) do
				local p = list[i]
				local entry = if typeof(p) == "table" and typeof(p.s) == "number" then map[tostring(p.s)] else nil
				if typeof(entry) == "table" then
					local skill = Ops.apprentice(e, p.s, today)
					if skill then
						table.insert(out, { name = tostring(p.n), role = roleDef.name, day = today - (tonumber(entry.day) or today) + 1, skill = skill })
					end
				end
			end
		end
	end
	table.sort(out, function(a, b) if a.day ~= b.day then return a.day > b.day end; return a.name < b.name end)
	return out
end
App.apprenticeList = apprenticeList
-- Team → Settings: "Change colour & logo" (shop package, SHOP_SPEC 3.5 / 5.2.6, owner decision S4): free for everyone.
-- The 8 Identity Kit colours and 6 Kit logos show with a small lock for non-owners and one line "More colours with
-- Identity Kit (Shop)"; there is no buy button here. 60 s between two changes (server: REBRAND_COOLDOWN).
local REBRAND_TILE = 56 -- 44.8 pt on an iPhone at this page's 0.80 scale
local function rebrandCard(parent: Instance, order: number)
	local card = Kit.card(parent, order, 10)
	card.Name = "Rebrand"
	title(card, "Change colour & logo")
	local intro = Kit.para(card, "Free for everyone. Your GPU racks change at once; HQ trim, cars and the jet at their next build.", 15, C.muted, 2)
	intro.Name = "RebrandIntro"
	local pickColor: string? = nil
	local pickLogo: string? = nil
	local lastSave = -math.huge
	type Tile = { button: TextButton, stroke: UIStroke, lock: Frame?, kit: boolean, id: string }
	local tiles: { Tile } = {}
	local refresh: () -> () = function() end
	local function tileRow(order2: number, list: { any }, kit: boolean, isColor: boolean)
		local row = Kit.frame(card, UDim2.new(1, 0, 0, REBRAND_TILE))
		row.LayoutOrder = order2
		Kit.list(row, 8, true)
		for i, item in list do
			local id = if isColor then item.id else item
			local b = Instance.new("TextButton")
			b.Name = (if isColor then "Color_" else "Logo_") .. (if isColor then id else tostring(i + (if kit then #CompanyConfig.LOGOS else 0)))
			b.AutoButtonColor = false
			b.BorderSizePixel = 0
			b.Size = UDim2.fromOffset(REBRAND_TILE, REBRAND_TILE)
			b.LayoutOrder = i
			b.Selectable = true
			b.Text = if isColor then "" else id
			b.Font = F.bold
			b.TextSize = 26
			b.TextColor3 = C.text
			b.BackgroundColor3 = if isColor then Theme.rgb(item.rgb) else C.raised
			b.Parent = row
			Kit.corner(b, 12)
			local stroke = Kit.stroke(b, 0.75, C.line, 1)
			local lock: Frame? = nil
			if kit then
				local l = Kit.frame(b, UDim2.fromOffset(22, 22), UDim2.new(1, -3, 1, -3))
				l.Name = "Lock"
				l.AnchorPoint = Vector2.new(1, 1)
				l.BackgroundTransparency = 0.15
				l.BackgroundColor3 = C.bg
				Kit.corner(l, 6)
				local icon = Kit.icon(l, "lock", 14)
				icon.frame.AnchorPoint = Vector2.new(0.5, 0.5)
				icon.frame.Position = UDim2.fromScale(0.5, 0.5)
				icon.setColor(C.text)
				lock = l
			end
			local tile: Tile = { button = b, stroke = stroke, lock = lock, kit = kit, id = id }
			table.insert(tiles, tile)
			Kit.onClick(b, function()
				local snapshot = State.snapshot
				local owns = snapshot ~= nil and ShopMath.ownsPass((snapshot.live :: any).shop and (snapshot.live :: any).shop.passes, CompanyConfig.KIT_PASS)
				if kit and not owns then
					Toast.show("info", "This colour comes with Identity Kit.")
					return
				end
				if isColor then pickColor = id else pickLogo = id end
				refresh()
			end)
		end
	end
	tileRow(3, CompanyConfig.COLORS, false, true)
	tileRow(4, CompanyConfig.KIT_COLORS, true, true)
	tileRow(5, CompanyConfig.LOGOS, false, false)
	tileRow(6, CompanyConfig.KIT_LOGOS, true, false)
	local more = Kit.para(card, "More colours with Identity Kit (Shop)", 15, C.dim, 7)
	more.Name = "KitLine"
	local status = Kit.para(card, "", 15, C.muted, 8)
	status.Name = "RebrandStatus"
	local save = Kit.button(card, "SAVE COLOUR & LOGO", "primary", UDim2.new(1, 0, 0, REBRAND_TILE))
	save.Name = "RebrandSave"
	save.LayoutOrder = 9
	save.TextSize = 16
	Kit.onClick(save, function()
		local snapshot = State.snapshot
		local company = if snapshot then snapshot.data.company else nil
		if not company then return end
		local color, logo = pickColor or company.color, pickLogo or company.logo
		lastSave = os.clock()
		queued("EmpireAction", { action = "rebrand", color = color, logo = logo }, "New company colour and logo saved.")
		pickColor, pickLogo = nil, nil
	end)
	refresh = function()
		local snapshot = State.snapshot
		local company = if snapshot then snapshot.data.company else nil
		if not snapshot or not company then return end
		local liveShop = (snapshot.live :: any).shop
		local owns = ShopMath.ownsPass(if typeof(liveShop) == "table" then liveShop.passes else nil, CompanyConfig.KIT_PASS)
		local color, logo = pickColor or company.color, pickLogo or company.logo
		for _, t in tiles do
			local on = t.id == color or t.id == logo
			-- fix round 1 (review): a locked Kit tile shows its TRUE colour / glyph (the player can judge it); only the
			-- lock badge and a grey border say that it needs Identity Kit
			local lockedKit = t.kit and not owns
			t.stroke.Color = if on then C.white elseif lockedKit then C.dim else C.line
			t.stroke.Transparency = if on then 0 elseif lockedKit then 0.2 else 0.75
			t.stroke.Thickness = if on then 3 elseif lockedKit then 2 else 1
			if t.lock then
				t.lock.Visible = not owns
			end
			t.button.BackgroundTransparency = 0
			t.button.TextTransparency = 0
		end
		more.Visible = not owns
		local wait = math.ceil(ShopConfigRebrand - (os.clock() - lastSave))
		local changed = color ~= company.color or logo ~= company.logo
		status.Text = if wait > 0 then string.format("You can change it again in %d s", wait) elseif changed then "Not saved yet." else "Your company colour and logo."
		Kit.setDisabled(save, wait > 0 or not changed)
	end
	watch(function(_s) refresh() end)
end

local function settings(parent: Instance)
	rebrandCard(parent, 0) -- shop package (SHOP_SPEC 5.2.6, S4)
	-- automatic HR
	local hr = Kit.card(parent, 1)
	title(hr, "Automatic HR")
	local hrText = para(hr, "", 2)
	local hrStatus = Kit.para(hr, "", 14, C.text, 3)
	hrStatus.Name = "HrStatus"
	hrStatus.Font = F.bold
	local autoRow = Kit.row(hr, Kit.tap(36, TAP), 12, 4)
	Kit.text(autoRow, "Hire automatically", 15, F.medium, C.text).LayoutOrder = 1
	local autoSwitch = switch(autoRow, { { id = "on", label = "On" }, { id = "off", label = "Off" } }, "on", 2, Kit.tap(170, 220), function(id)
		queued("EmpireAction", { action = "hrAuto", on = id == "on" }, if id == "on" then "Automatic HR is on." else "Automatic HR is off. Hire by hand in Team.")
	end)
	local budgetRow = Kit.row(hr, Kit.tap(36, TAP), 12, 5)
	Kit.text(budgetRow, "Wage budget", 15, F.medium, C.text).LayoutOrder = 1
	local budgetOptions: { Kit.Option } = {}
	for _, b in Ops.HR_BUDGETS do table.insert(budgetOptions, { id = string.format("%.2f", b), label = string.format("%d %%", math.floor(b * 100 + 0.5)) }) end
	local budgetSwitch = switch(budgetRow, budgetOptions, "0.40", 2, Kit.tap(260, 330), function(id)
		queued("EmpireAction", { action = "hrBudget", budget = tonumber(id) }, "Wage budget set to " .. math.floor((tonumber(id) or 0) * 100 + 0.5) .. " % of income.")
	end)
	local needText = para(hr, "", 6)
	dim(hr, "HR hires one person every " .. Ops.HIRE_GAP .. " s into the department furthest below its need, only while the payroll (team + operations staff) stays inside the budget share of the 5-minute income. The first " .. Ops.HR_STARTERS .. " hires are always allowed. In Save mode HR stops at half the desks.", 7)
	-- Save mode
	local save = Kit.card(parent, 2)
	title(save, "Save mode")
	local saveText = para(save, "", 2)
	local saveRow = Kit.row(save, Kit.tap(36, TAP), 12, 3)
	Kit.text(saveRow, "Save for the next office", 15, F.medium, C.text).LayoutOrder = 1
	local saveSwitch = switch(saveRow, { { id = "auto", label = "Auto" }, { id = "off", label = "Off" } }, "auto", 2, Kit.tap(170, 220), function(id)
		queued("EmpireAction", { action = "saveMode", mode = id }, if id == "auto" then "Save mode: automatic." else "Save mode switched off.")
	end)
	dim(save, "Auto switches on when the next office is less than " .. Ops.SAVE_MINUTES .. " minutes of profit away. It pauses research, Lab levels, big trainings, HR beyond half the desks and ordinary GPU buys. GPUs that pay back fast while servers are full still get bought.", 4)
	-- night shift
	local night = Kit.card(parent, 3)
	title(night, "Night shift")
	local nightText = para(night, "", 2)
	local nightRows = Kit.stack(night, 6, 3)
	local nightSwitches: { [string]: Kit.Segmented } = {}
	local nightLabels: { [string]: TextLabel } = {}
	local nightWant: { [string]: boolean } = {} -- a switch tap still on its way to the server (shown meanwhile)
	-- the night crew works per role (CompanyOps.nightOn: any department of the role); the switch sets every department
	-- of the role in ONE call (EmpireAction nightShift with role: atomic and idempotent, it sets, never toggles), so a
	-- burst of taps on several roles never ends with a role half on
	local switchW, rowH = Kit.tap(170, 220), Kit.tap(36, TAP)
	for i, roleDef in Config.ROLES do
		local row = Kit.row(nightRows, rowH, 12, i)
		row.Name = "Night_" .. roleDef.id
		local label = Kit.cell(row, roleDef.name, UDim.new(0, 170), 15, F.medium, C.text)
		label.LayoutOrder = 1
		local sub = Kit.cell(row, "", UDim.new(1, -(200 + switchW)), 13, F.regular, C.muted)
		sub.LayoutOrder = 2
		sub.TextTruncate = Enum.TextTruncate.AtEnd
		nightLabels[roleDef.id] = sub
		nightSwitches[roleDef.id] = switch(row, { { id = "off", label = "Off" }, { id = "on", label = "On" } }, "off", 3, switchW, function(id)
			local want = id == "on"
			nightWant[roleDef.id] = want
			enqueue("EmpireAction", function()
				local failed: string? = nil
				local ok, res = paced("EmpireAction", { action = "nightShift", role = roleDef.id, on = want })
				if not ok then failed = tostring(res.err) end
				if nightWant[roleDef.id] == want then nightWant[roleDef.id] = nil end
				if failed then
					Toast.show("error", Action.message(failed))
				else
					Toast.show("success", roleDef.name .. (if want then ": night shift on." else ": night shift off."))
				end
			end)
		end)
	end
	dim(night, "Heads beyond the desks (up to as many again) work 22:00–06:00 at full output instead of half, for " .. string.format("%.1f", Ops.NIGHT.wage) .. "× wage. It only pays when a department has more people than desks. Paused while cash stays below $0 for a whole day.", 4)
	-- apprentices
	local appr = Kit.card(parent, 4)
	title(appr, "Apprentices")
	local apprText = para(appr, "", 2)
	local hireRow = Kit.grid(appr, 4, Kit.tap(40, TAP), 8, 3)
	local hireButtons: { [string]: TextButton } = {}
	for i, roleDef in Config.ROLES do
		local b = Kit.button(hireRow, roleDef.name, "secondary", UDim2.new())
		b.LayoutOrder = i
		b.TextSize = 14
		b.Name = "Apprentice_" .. roleDef.id
		hireButtons[roleDef.id] = b
		Kit.onClick(b, function() call("HireEmployee", { roleId = roleDef.id, apprentice = true }, "New apprentice: " .. roleDef.name .. ". The Training Lead shows them around.") end)
	end
	local apprRows = Kit.stack(appr, 4, 4)
	dim(appr, string.format("Young trainees start at skill %d, gain +1 skill every %d company days up to %d and become regular staff after %d days. They cost %d %% of the agency fee and %d %% of the wage. The Training Lead (%s/day) is paid while you have apprentices.",
		Ops.APPRENTICE.startSkill, Ops.APPRENTICE.rampDays, Ops.APPRENTICE.endSkill, Ops.APPRENTICE.graduateDays, math.floor(Ops.APPRENTICE.fee * 100), math.floor(Ops.APPRENTICE.wage * 100), dollars(Ops.TRAINING_LEAD.wage)), 5)
	-- company jet
	local jet = Kit.card(parent, 5)
	title(jet, "Company jet")
	local jetText = para(jet, "", 2)
	local jetButton = button(jet, "Buy company jet", function()
		queued("EmpireAction", { action = "buyJet" }, "The company jet is yours. It waits in the airport hangar with your 2 pilots.")
	end)
	jetButton.Name = "BuyJet"
	-- Lab level lives in the Models app (a duplicate card: not on the Menu's Team → Settings page, ONBOARDING_SPEC B9)
	local lab = Kit.card(parent, 6)
	lab.Visible = not inPage
	title(lab, "Lab level")
	local labText = para(lab, "", 2)
	local labButton = Kit.button(lab, "Open the Lab", "secondary", UDim2.new(1, 0, 0, Kit.tap(40, TAP)))
	labButton.LayoutOrder = 3
	Kit.onClick(labButton, function() if nav then nav.show("lab") end end)
	local apprSig: string? = nil
	watch(function(s)
		local e = s.data.empire
		local stage = Ops.stageIndex(e)
		local ops = if typeof(s.live.ops) == "table" then s.live.ops else {}
		local auto, budget = Ops.hrSettings(e)
		autoSwitch.set(if auto then "on" else "off")
		budgetSwitch.set(string.format("%.2f", budget))
		local payrollMin = (tonumber(ops.wagesCost) or 0) + (tonumber(ops.opsCost) or 0)
		local income = tonumber(ops.income) or 0
		hrText.Text = string.format("Payroll now %s · budget %s (%d %% of the income of the last 5 minutes)",
			perDay(payrollMin), perDay(budget * income), math.floor(budget * 100 + 0.5))
		local statusLine, warn = App.hrStatus(s)
		hrStatus.Text = statusLine
		hrStatus.TextColor3 = if warn then C.warn else C.text
		local needs = {}
		for _, id in Ops.HR_ORDER do
			local roleDef = Config.find(Config.ROLES, id)
			table.insert(needs, string.format("%s %d / %d", if roleDef then roleDef.name else id, e.employees[id] or 0, Ops.hrNeed(e, id)))
		end
		needText.Text = "People / HR target: " .. table.concat(needs, "  ·  ")
		-- Save mode
		saveSwitch.set(if e.saveMode == "off" then "off" else "auto")
		local nextDef = Config.OFFICES[stage + 1]
		saveText.Text = if e.saveMode == "off" then "Off: the company spends freely."
			elseif ops.saveMode == true and nextDef then "On now: saving for the " .. nextDef.name .. " (" .. Format.money(nextDef.price) .. ")."
			elseif not nextDef then "You own the largest office: nothing to save for."
			elseif stage == 1 and (tonumber(e.contractsCompleted) or 0) < 1 then "Starts after your first client has signed."
			else "Not active: the " .. nextDef.name .. " is still more than " .. Ops.SAVE_MINUTES .. " minutes of profit away."
		-- night shift
		local nightOpen = stage >= Ops.NIGHT.from
		nightRows.Visible = nightOpen
		nightText.Text = if nightOpen and ops.paused == true then "Paused: cash has been below $0 for a whole game day. Night crews come back once cash is positive."
			elseif nightOpen then "Optional per team. Needs a security guard on duty (operations staff)." else "Night shifts start at the " .. stageName(Ops.NIGHT.from) .. "."
		if nightOpen then
			for _, roleDef in Config.ROLES do
				local heads = e.employees[roleDef.id] or 0
				local seats = Ops.seats(e, roleDef.id)
				local over = math.max(0, heads - seats)
				local depts = Ops.ROLE_DEPTS[roleDef.id] or {}
				local onCount = 0
				for _, dept in depts do
					if typeof(e.nightShift) == "table" and e.nightShift[dept] == true then onCount += 1 end
				end
				local want = nightWant[roleDef.id]
				local partial = want == nil and onCount > 0 and onCount < #depts
				local on = if want ~= nil then want else onCount > 0
				-- a half-on role (an older save, a failed call) highlights neither side, so either tap fixes it
				nightSwitches[roleDef.id].set(if partial then "partial" elseif on then "on" else "off")
				local sub = nightLabels[roleDef.id]
				sub.Text = string.format("%d people / %d desks%s", heads, seats,
					if want ~= nil then " · switching…"
					elseif partial then string.format(" · on in %d of %d departments: tap On or Off", onCount, #depts)
					elseif over > 0 then string.format(" · %d work at night", math.min(over, seats)) elseif on then " · nobody over the desks yet" else "")
				sub.TextColor3 = if partial then C.warn else C.muted
			end
		end
		-- apprentices
		local apprOpen = stage >= Ops.TRAINING_LEAD.from
		hireRow.Visible = apprOpen
		local list = apprenticeList(e)
		local full = Math.staff(e) >= Config.OFFICES[stage].staff
		apprText.Text = if not apprOpen then "Apprentices start at the " .. stageName(Ops.TRAINING_LEAD.from) .. " with a Training Lead."
			elseif #list > 0 then string.format("Training Lead on duty (%s/day) · %d apprentice%s in training. Hire another:", dollars(Ops.TRAINING_LEAD.wage), #list, if #list == 1 then "" else "s")
			else "No apprentices: the Training Lead is not paid. Hire one:"
		for _, roleDef in Config.ROLES do
			local b = hireButtons[roleDef.id]
			local fee = math.floor(Math.hireCost(e, roleDef) * Ops.APPRENTICE.fee)
			b.Text = string.format("%s · %s", string.gsub(roleDef.name, "^AI ", ""), dollars(fee))
			Kit.setDisabled(b, not apprOpen or full or s.data.money < fee)
		end
		local sig = ""
		for _, a in list do sig ..= a.name .. a.day .. a.skill .. "|" end
		if sig ~= apprSig then
			apprSig = sig
			clearRows(apprRows)
			for i, a in list do
				local row = Kit.frame(apprRows, UDim2.new(1, 0, 0, 26))
				row.LayoutOrder = i
				Kit.cell(row, a.name, UDim.new(0.3, 0), 15, F.bold, C.text)
				Kit.cell(row, a.role, UDim.new(0.25, 0), 13, F.regular, C.muted).Position = UDim2.fromScale(0.3, 0)
				Kit.cell(row, string.format("day %d of %d", math.max(1, a.day), Ops.APPRENTICE.graduateDays), UDim.new(0.2, 0), 13, F.medium, C.muted).Position = UDim2.fromScale(0.55, 0)
				local skillCell = Kit.cell(row, if a.skill >= Ops.APPRENTICE.endSkill then string.format("skill %d (max)", a.skill) else string.format("skill %d → %d", a.skill, Ops.APPRENTICE.endSkill), UDim.new(0.25, 0), 13, F.bold, C.warn)
				skillCell.Position = UDim2.fromScale(0.75, 0)
				skillCell.TextXAlignment = Enum.TextXAlignment.Right
			end
		end
		-- company jet
		local J = Ops.JET
		local running = J.pilots * J.pilotWage + J.upkeep
		if e.jet == true then
			jetText.Text = string.format("Owned. Parked in the airport hangar with %d company pilots · running %s/day · abroad trips take %.1f days instead of %d, %d hotel night, +%d %% trust, no airline tickets.",
				J.pilots, dollars(running), J.days, Ops.TRIPS.abroad.days, J.nights, math.floor(J.trust * 100))
			jetButton.Text = "Owned"
			Kit.setDisabled(jetButton, true)
		else
			jetText.Text = string.format("%s once, then %s/day (%d pilots + upkeep) and %s fuel per abroad trip. Abroad trips take %.1f days instead of %d and win +%d %% trust. %s",
				dollars(J.price), dollars(running), J.pilots, dollars(J.fuel), J.days, Ops.TRIPS.abroad.days, math.floor(J.trust * 100),
				if stage < J.stage then "Needs the " .. stageName(J.stage) .. "." else "It waits in the airport hangar with 2 company pilots once you buy it.")
			jetButton.Text = if stage < J.stage then "Needs the " .. stageName(J.stage) else "Buy company jet · " .. dollars(J.price)
			Kit.setDisabled(jetButton, stage < J.stage or s.data.money < J.price)
		end
		local level = math.floor(tonumber(e.labLevel) or 0)
		if level >= Ops.LAB_MAX then
			labText.Text = string.format("Lab level %d / %d: the highest level. Every future model gets +%d core stats.", level, Ops.LAB_MAX, level)
		else
			local pts, cost = Ops.labCost(level)
			local treeDone = true
			for _, def in Config.RESEARCH do if not e.research[def.id] then treeDone = false end end
			labText.Text = string.format("Lab level %d / %d. The next level costs %s research points + %s%s and adds +1 to every core stat of future models. It lives in Lab → Models.", level, Ops.LAB_MAX, Format.int(pts), dollars(cost), if treeDone then "" else " (after the whole research tree)")
		end
	end)
end
local function board(parent: Instance)
	local head=Kit.card(parent,1)
	title(head,"Company rankings")
	local status=para(head,"Global rankings load in a published game with saving enabled.")
	local mode="overall"
	local mine=building -- this tab's updaters (a Menu page renders the board next to other parts)
	local selector=Kit.segmented(head,{{id="overall",label="Overall"},{id="coding",label="Coding"},{id="math",label="Math"},{id="reasoning",label="Reasoning"},{id="creativity",label="Creative"},{id="arena",label="Arena"}},mode,function(id) mode=id;if State.snapshot then for _,fn in mine do fn(State.snapshot) end end end,Kit.tap(38,62)) -- fix round 1 (B3): 56 px tabs on touch
	selector.frame.LayoutOrder=3
	watch(function(s) status.Text=if s.live.rankings then s.live.rankings.status.." · best self-trained records, refreshed every three minutes" else "Server preview · strongest self-trained AI" end)
	for i=1,10 do
		local row=Kit.card(parent,i+1)
		local name=title(row,"");local stats=para(row,"")
		watch(function(s)
			local ranking=s.live.rankings
			local entry=if ranking then ranking.boards[mode] and ranking.boards[mode][i] else s.live.empire and s.live.empire.board[i]
			row.Visible=entry~=nil
			if entry then name.Text=tostring(i)..". "..entry.name;stats.Text=string.format("%.1f %s points",entry.score or entry.best,mode) end
		end)
	end
end
-- Menu composites (ONBOARDING_SPEC B4, menu package) ---------------------------------------------------------
-- Home → Money: Company → Overview's metrics, profit chart and market cycle on top of the Money builder
local function homeMoney(parent: Instance)
	local metrics = Kit.grid(parent, 3, 96, 10, 1)
	metric(metrics, "Cash available", function(s) return Format.money(s.data.money) end, 1)
	-- nothing booked yet reads "$0/day", never "+$0" (apps rule: no "+$0" anywhere)
	metric(metrics, "Profit per game day", function(s) local net = s.live.revenue-s.live.cost; return if net == 0 then "$0/day" else Format.perDay(net) end, 2)
	metric(metrics, "Active users", function(s) return Format.compact(s.live.users) end, 3)
	profitChart(parent, 2)
	local cycle = Kit.card(parent, 3)
	local cycleTitle = title(cycle, "Market cycle")
	local cycleText = para(cycle, "")
	watch(function(s)
		local def, left = Config.cycle(s.serverTime)
		cycleTitle.Text = "Market cycle · " .. def.name
		cycleText.Text = def.desc .. "  Next cycle in " .. tostring(math.ceil(left)) .. "s."
	end)
	local ledger = Kit.stack(parent, 12, 4)
	money(ledger)
end
-- "Guide & tips" (ONBOARDING_SPEC A12): skip the guide, restart it before the first launch, tips on/off, replay tips
local function guideCard(parent: Instance, order: number)
	local card = Kit.card(parent, order)
	card.Name = "GuideTips"
	title(card, "Guide & tips")
	local state = para(card, "", 2)
	local row = Kit.grid(card, 2, Kit.tap(40, TAP), 10, 3)
	local skip = Kit.button(row, "Skip guide", "secondary", UDim2.new())
	skip.Name = "SkipGuide"
	skip.LayoutOrder = 1
	local restart = Kit.button(row, "Restart first steps", "secondary", UDim2.new())
	restart.Name = "RestartGuide"
	restart.LayoutOrder = 2
	local tips = Kit.button(row, "Tips: on", "secondary", UDim2.new())
	tips.Name = "TipsToggle"
	tips.LayoutOrder = 3
	local replay = Kit.button(row, "Replay tips", "secondary", UDim2.new())
	replay.Name = "ReplayTips"
	replay.LayoutOrder = 4
	local tipsOn = true
	Kit.onClick(skip, function() queued("EmpireAction", { action = "tutorial", op = "skip" }, "Guide skipped. Restart it here any time before your first launch.") end)
	Kit.onClick(restart, function() queued("EmpireAction", { action = "tutorial", op = "restart" }, "First steps restarted: follow the gold ring.") end)
	Kit.onClick(tips, function() queued("EmpireAction", { action = "tutorial", op = "tips", on = not tipsOn }, if tipsOn then "Tips are off." else "Tips are on.") end)
	Kit.onClick(replay, function() queued("EmpireAction", { action = "tutorial", op = "replayTips" }, "Tips will show again.") end)
	watch(function(s)
		local t = s.data.empire.tutorial
		t = if typeof(t) == "table" then t else {}
		local released = (tonumber(s.data.stats.modelsReleased) or 0) >= 1
		local active = TutorialMath.active(s.data)
		card.LayoutOrder = if active then 0 else order -- fix round 1: first on Home → Goals while the guide runs
		tipsOn = t.tipsOff ~= true
		state.Text = if active then string.format("First steps: step %d of %d. The gold ring shows the next button.", math.max(1, TutorialMath.reachable(s.data)), TutorialMath.STEPS)
			elseif t.skipped == true and not released then "First steps skipped. Restart them any time before your first launch."
			elseif t.done == true or released then "First steps done. One-time tips explain new things as they appear."
			else "First steps skipped."
		skip.Visible = active
		restart.Visible = not active and not released
		tips.Text = if tipsOn then "Tips: on" else "Tips: off"
	end)
end
-- Home → Goals: Collect all, the goals, "A business with a plan" and "Guide & tips"
local function homeGoals(parent: Instance)
	local top = Kit.card(parent, 1)
	title(top, "Goals")
	local info = para(top, "", 2)
	local collect = button(top, "Collect all", function()
		task.spawn(function()
			local ok, res = Action.call("ClaimQuest", { all = true })
			if ok and typeof(res.total) == "number" and res.total > 0 then
				Toast.show("success", TutorialMath.collectText(res.total, if typeof(res.claimed) == "table" then #res.claimed else 0), 4)
			end
		end)
	end)
	collect.Name = "CollectAll"
	watch(function(s)
		local done = 0
		for _, q in Config.QUESTS do if s.data.empire.quests[q.id] then done += 1 end end
		local total, count = TutorialMath.claimable(s.data)
		info.Text = string.format("%d of %d goals done%s", done, #Config.QUESTS, if count > 0 then string.format(" · %d ready to collect", count) else "")
		collect.Text = "Collect all · " .. Format.money(total)
		collect.Visible = total > 0 -- fix round 1: no disabled "Nothing to collect yet" button
	end)
	local list = Kit.stack(parent, 12, 2)
	milestones(list)
	local plan = Kit.card(parent, 3)
	title(plan, "A business with a plan")
	para(plan, "1. Buy data and train a model in the Lab.\n2. Launch it at the Recommended price.\n3. Sign business clients: you and your Growth & Sales reps visit them by yourselves.\n4. Hire a team, research upgrades and move into a bigger office.\n5. Build a frontier model and climb the server board.")
	guideCard(parent, 4)
end

local builders: { [string]: (Instance) -> () } = {overview=overview,clients=clients,money=money,team=team,research=research,milestones=milestones,office=office,settings=settings,board=board}
local PART_BUILDERS: { [string]: (Instance) -> () } = {homeMoney=homeMoney,homeGoals=homeGoals,overview=overview,clients=clients,money=money,team=team,research=research,milestones=milestones,office=office,settings=settings,board=board}
-- the legacy tab name a part's stack carries ("Tab_<id>", tests and the HUD find it by name)
local PART_TAB: { [string]: string } = {homeMoney="money",homeGoals="milestones"}
local TABS = {{"overview","Overview"},{"clients","Clients"},{"money","Money"},{"team","Team"},{"research","Research"},{"milestones","Goals"},{"office","Office"},{"settings","Settings"},{"board","Board"}}
local function paintTabs()
	for id,btn in tabButtons do btn.BackgroundColor3=if id==current then Theme.accent:Lerp(C.panel,0.6) else C.raised end
end
local function render()
	local container=scroll
	if not container then return end
	updaters={}
	building=updaters
	for _,child in container:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	local stack=Kit.stack(container,12)
	stack.Name="Tab_"..current
	Kit.padding(stack,0,8,24,0)
	builders[current](stack)
	container.CanvasPosition=Vector2.zero
	paintTabs()
end
-- EMPIRE_NOTICE toasts (research complete, new office), registered once for App.mount and the Menu parts
local noticesBound = false
local function bindNotices()
	if noticesBound then return end
	noticesBound = true
	State.onNotify(function(kind,payload)
		if kind=="EMPIRE_NOTICE" and typeof(payload.text)=="string" then Toast.show("success",payload.text,5) end
	end)
end
function App.mount(parent: Frame, navigation: any)
	nav=navigation
	bindNotices()
	local head=Kit.frame(parent,UDim2.new(1,0,0,38))
	local label=Kit.text(head,"Company",24,F.display,C.text)
	label.Position=UDim2.fromOffset(0,2)
	local tabs=Instance.new("ScrollingFrame")
	tabs.Name="Tabs"
	tabs.BackgroundTransparency=1
	tabs.BorderSizePixel=0
	local tabH=Kit.tap(36,80)
	tabs.Size=UDim2.new(1,0,0,tabH+10)
	tabs.Position=UDim2.fromOffset(0,42)
	tabs.CanvasSize=UDim2.new()
	tabs.AutomaticCanvasSize=Enum.AutomaticSize.X
	tabs.ScrollingDirection=Enum.ScrollingDirection.X
	tabs.ScrollBarThickness=2
	tabs.Parent=parent
	Kit.list(tabs,6,true)
	tabButtons={}
	for i,def in TABS do
		local b=Kit.button(tabs,def[2],"secondary",UDim2.fromOffset(Kit.tap(96,140),tabH))
		b.Name="Tab_"..def[1]
		b.LayoutOrder=i
		tabButtons[def[1]]=b
		Kit.onClick(b,function()
			current=def[1]
			render()
		end)
	end
	paintTabs()
	local top=42+tabH+22
	local body=Kit.scroll(parent,UDim2.new(1,0,1,-top),UDim2.fromOffset(0,top))
	body.Name="EmpireScroll"
	scroll=body
	State.onChange(function(s)
		if not s.data.company then return end
		if #updaters==0 then render() end
		for _,fn in updaters do fn(s) end
	end)
end
function App.onShow()
	if #updaters==0 and State.snapshot and State.snapshot.data.company then render() end
end

-- A Menu page part: one builder rendered into `frame` (no own scroll; the Menu page scrolls). Rendered on its first
-- show, updated in place on snapshots while it is visible. Returns the part handle the Menu keeps.
export type Part = { frame: Frame, id: string, show: () -> (), rebuild: () -> () }
type PartState = { frame: Frame, id: string, updaters: { (any) -> () }, built: boolean }
local partStates: { PartState } = {}
local partsBound = false
local function shown(inst: Instance): boolean
	local node: Instance? = inst
	while node do
		if node:IsA("GuiObject") and not (node :: GuiObject).Visible then return false end
		if node:IsA("LayerCollector") then return true end
		node = node.Parent
	end
	return true
end
local function renderPart(part: PartState)
	local snapshot = State.snapshot
	if not snapshot or not snapshot.data.company then return end
	for _, child in part.frame:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	part.updaters = {}
	local before, beforePage = building, inPage
	building, inPage = part.updaters, true
	local stack = Kit.stack(part.frame, 12)
	stack.Name = "Tab_" .. (PART_TAB[part.id] or part.id)
	local builder = PART_BUILDERS[part.id]
	local ok, err = pcall(function()
		builder(stack)
	end)
	building, inPage = before, beforePage
	if not ok then warn("[EmpireApp] part " .. part.id .. ": " .. tostring(err)) end
	part.built = true
end
function App.mountPart(frame: Frame, id: string, navigation: any): Part
	assert(PART_BUILDERS[id], "unknown EmpireApp part " .. id)
	nav = nav or navigation
	bindNotices()
	frame.AutomaticSize = Enum.AutomaticSize.Y
	local part: PartState = { frame = frame, id = id, updaters = {}, built = false }
	table.insert(partStates, part)
	if not partsBound then
		partsBound = true
		State.onChange(function(s)
			if not s.data.company then return end
			for _, p in partStates do
				if p.built and shown(p.frame) then
					for _, fn in p.updaters do fn(s) end
				end
			end
		end)
	end
	return {
		frame = frame,
		id = id,
		show = function()
			if not part.built then
				renderPart(part)
			elseif State.snapshot then
				for _, fn in part.updaters do fn(State.snapshot) end
			end
		end,
		rebuild = function() renderPart(part) end,
	}
end
App.PARTS = PART_BUILDERS
function App.openSection(section: string)
	local id=if section=="contracts" then "clients" else section
	if builders[id] then current=id;render() end
end
return App
