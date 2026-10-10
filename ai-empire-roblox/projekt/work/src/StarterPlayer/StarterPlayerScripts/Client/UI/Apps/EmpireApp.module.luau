--!strict
-- Company OS: reactive cards are built on tab changes, updated in place on snapshots.
-- Tabs: Overview, Clients (B2B pipeline, CORE_SPEC 3.2), Money (P&L per company day from empire.ledger, CORE_SPEC 4/6),
-- Team, Research, Goals, Office, Settings (auto-HR, Save mode, night shift, apprentices, company jet: CORE_SPEC 8.1,
-- 11.1, 11.2) and Board. Every number comes from the replicated company state; decisions go to the server through
-- EmpireAction / DealAction / HireEmployee (errors: ActionController texts, CORE_SPEC 11.8).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.EmpireConfig)
local DepartmentConfig = require(Shared.Config.DepartmentConfig)
local HardwareConfig = require(Shared.Config.HardwareConfig)
local Math = require(Shared.EmpireMath)
local Ops = require(Shared.CompanyOps)
local ModelMath = require(Shared.ModelMath)
local Format = require(Shared.Format)
local UI = script.Parent.Parent
local Client = UI.Parent
local State = require(Client.Controllers.StateController)
local Action = require(Client.Controllers.ActionController)
local People = require(Client.Controllers.PeopleController)
local Conversation = require(UI.Screens.Conversation)
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Toast = require(UI.Toast)
local C, F = Theme.colors, Theme.font
local App = {}
local page: Frame? = nil
local scroll: ScrollingFrame? = nil
local current = "overview"
local updaters: { (any) -> () } = {}
local nav: any = nil
local tabButtons: { [string]: TextButton } = {}
local function watch(fn: (any) -> ())
	table.insert(updaters, fn)
	if State.snapshot then fn(State.snapshot) end
end
local function button(parent: Instance, label: string, callback: () -> ())
	local b = Kit.button(parent, label, "primary", UDim2.new(1,0,0,40))
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
local function clearRows(rows: Instance)
	for _, child in rows:GetChildren() do if child:IsA("GuiObject") then child:Destroy() end end
end
-- small segmented switch inside a card row (Off / On, 25 / 40 / 55 %, Auto / Off)
local function switch(parent: Instance, options: { Kit.Option }, initial: string, order: number, width: number?, onSelect: (string) -> ()): Kit.Segmented
	local seg = Kit.segmented(parent, options, initial, onSelect, 36)
	seg.frame.LayoutOrder = order
	if width then seg.frame.Size = UDim2.fromOffset(width, 36) end
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
		positive.Text=Format.money(max).." / min"
		negative.Text=Format.money(min).." / min"
		caption.Text=if #history==0 then "The first sample appears after 10 seconds. Staff wages are included." else "Actual net profit · one sample every 10 seconds · staff wages included"
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
	local start = Kit.row(hero, 40, 8, 3)
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
	para(goal, "1. Buy data and train a model in Models.\n2. Launch it at the Recommended price.\n3. Sign business clients: you and your Growth & Sales reps visit them by yourselves.\n4. Hire a team, research upgrades and move into a bigger office.\n5. Build a frontier model and climb the server board.")
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
	local left = Format.duration(math.max(0, (tonumber(t.back) or 0) - (tonumber(s.data.empire.seconds) or 0)))
	local what = if t.kind == "renew" then "check-in" else "pilot visit"
	if t.hosted then return string.format("%s team at your guest house · %s · back in %s", name, what, left) end
	local who = if t.founder then "You (founder)" elseif (tonumber(t.crew) or 1) >= 2 then "Field rep + engineer" else "Field rep"
	local how = if tier == "abroad" then (if s.data.empire.jet == true then "company jet" else "flight + 2 nights") elseif tier == "region" then "City Hotel night" else "car"
	return string.format("%s → %s · %s · %s · back in %s", who, name, what, how, left)
end
type ClientRow = { frame: Frame, update: (any) -> () }
local function clientRow(parent: Instance, c: any): ClientRow
	local frame = Kit.frame(parent, UDim2.new(1, 0, 0, 84))
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3 = C.panel2
	Kit.corner(frame, 10)
	local stroke = Kit.stroke(frame, 0.93)
	Kit.padding(frame, 12, 14, 12, 16)
	local nameRow = Kit.frame(frame, UDim2.new(1, -190, 0, 22))
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
	status.Size = UDim2.new(1, -190, 0, 18)
	status.Position = UDim2.fromOffset(0, 27)
	status.TextTruncate = Enum.TextTruncate.AtEnd
	local bar = Kit.bar(frame, 6)
	bar.frame.Name = "Trust"
	bar.frame.Size = UDim2.new(1, -190, 0, 6)
	bar.frame.Position = UDim2.fromOffset(0, 52)
	local buttons = Kit.frame(frame, UDim2.fromOffset(176, 30), UDim2.fromScale(1, 1))
	buttons.AnchorPoint = Vector2.new(1, 1)
	local layout = Kit.list(buttons, 8, true)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	local pin = Kit.button(buttons, "Pin", "secondary", UDim2.fromOffset(84, 30))
	pin.Name = "Pin"
	pin.TextSize = 14
	pin.LayoutOrder = 1
	local skip = Kit.button(buttons, "Skip", "ghost", UDim2.fromOffset(84, 30))
	skip.Name = "Skip"
	skip.TextSize = 14
	skip.LayoutOrder = 2
	local join = Kit.button(buttons, "Join in person", "secondary", UDim2.fromOffset(176, 30))
	join.Name = "Join"
	join.TextSize = 14
	join.LayoutOrder = 3
	Kit.onClick(pin, function() call("DealAction", { action = "pin", clientId = c.id }) end)
	Kit.onClick(skip, function() call("DealAction", { action = "skip", clientId = c.id }) end)
	Kit.onClick(join, function()
		task.spawn(function()
			local ok, res = Action.call("DealAction", { action = "joinMeeting", clientId = c.id }, true)
			if ok then Toast.show("success", "You joined the " .. c.name .. " meeting: trust +15 %.", 5)
			elseif res.err == "ALREADY_DONE" then Toast.show("info", "You are already in the " .. c.name .. " meeting.", 4)
			elseif res.err ~= "BUSY" then Toast.show("error", Action.message(res.err)) end
		end)
	end)
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
			text = string.format("Needs %s %d · your best live model: %d", c.stat, c.minimum, math.floor(best))
			color = C.warn
			canPin = true
		else
			canPin = true
			fraction = math.min(1, trust or 0)
			if trip and trip.kind == "sign" then
				text = (if trip.hosted then "Client team at your guest house" else "Pilot visit under way") .. " · back in " .. Format.duration(math.max(0, (tonumber(trip.back) or 0) - (tonumber(e.seconds) or 0)))
				color = C.text
				canJoin = not trip.hosted
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

		pin.Text = if pinned then "Unpin" else "Pin"
		skip.Text = if skipped then "Unskip" else "Skip"
		value.TextColor3 = if group == "account" then C.good elseif group == "later" then C.dim else C.text
		name.TextColor3 = if group == "later" then C.muted else C.text
		frame.LayoutOrder = GROUPS[group] + table.find(Ops.CLIENTS, c) :: number
		-- rows without a trust bar or buttons (accounts, later stages) are shorter
		frame.Size = UDim2.new(1, 0, 0, if fraction ~= nil or canPin then 84 else 62)
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
	local road = Kit.card(parent, 2)
	title(road, "On the road")
	local roadRows = Kit.stack(road, 6, 2)
	local list = Kit.stack(parent, 8, 3)
	local captions: { [string]: TextLabel } = {}
	for group, order in GROUPS do
		local cap = Kit.text(list, "", 15, F.bold, C.text)
		cap.LayoutOrder = order
		captions[group] = cap
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
		captions.needs.Text = string.format("Needs a better model (%d)", counts.needs)
		captions.later.Text = string.format("Later stages (%d)", counts.later)
		for group, cap in captions do cap.Visible = (counts[group] or 0) > 0 end
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
local function lineRow(parent: Instance, order: number, label: string, value: string, color: Color3, bold: boolean?): Frame
	local row = Kit.frame(parent, UDim2.new(1, 0, 0, 22))
	row.LayoutOrder = order
	Kit.cell(row, label, UDim.new(0.62, 0), 14, if bold then F.bold else F.regular, if bold then C.text else C.muted).Position = UDim2.new()
	local v = Kit.cell(row, value, UDim.new(0.38, 0), 14, F.bold, color)
	v.Position = UDim2.fromScale(0.62, 0)
	v.TextXAlignment = Enum.TextXAlignment.Right
	return row
end
local function money(parent: Instance)
	local today = Kit.card(parent, 1)
	local todayTitle = title(today, "Today")
	local todayText = para(today, "", 2)
	local cols = Kit.frame(today, UDim2.fromScale(1, 0))
	cols.AutomaticSize = Enum.AutomaticSize.Y
	cols.LayoutOrder = 3
	local left = Kit.frame(cols, UDim2.new(0.5, -12, 0, 0))
	left.AutomaticSize = Enum.AutomaticSize.Y
	Kit.list(left, 2)
	local right = Kit.frame(cols, UDim2.new(0.5, -12, 0, 0), UDim2.new(0.5, 12, 0, 0))
	right.AutomaticSize = Enum.AutomaticSize.Y
	Kit.list(right, 2)
	local net = Kit.text(today, "", 20, F.display, C.text)
	net.LayoutOrder = 4
	local days = Kit.card(parent, 2)
	title(days, "Last company days")
	local daysText = para(days, "", 2)
	local tableFrame = Kit.stack(days, 2, 3)
	local chart = Kit.frame(days, UDim2.new(1, 0, 0, 96))
	chart.LayoutOrder = 4
	local running = Kit.card(parent, 3)
	title(running, "Running now, per game day")
	local runRows = Kit.stack(running, 2, 2)
	dim(running, "Live rates at this moment (a game day is 20 minutes: 15 min day, 5 min night). Wages are paid day and night, also during vacation and sick days.", 3)
	local sig: string? = nil
	watch(function(s)
		local e = s.data.empire
		local ledger = if typeof(e.ledger) == "table" then e.ledger else {}
		local dayNow = Ops.day(e)
		local list = App.ledgerDays(ledger)
		local income, costs, inTotal, outTotal = App.ledgerDay(ledger[tostring(dayNow)])
		todayTitle.Text = "Today · day " .. dayNow
		todayText.Text = if #income + #costs == 0 then "Nothing booked yet today." else "Every dollar of today, by category (the company day started at 08:00)."
		local s2 = tostring(dayNow) .. "|" .. tostring(inTotal) .. "|" .. tostring(outTotal) .. "|" .. tostring(#list)
		for _, k in list do local _, _, a, b = App.ledgerDay(ledger[tostring(k)]); s2 ..= "|" .. a .. ":" .. b end
		if s2 ~= sig then
			sig = s2
			clearRows(left); clearRows(right)
			Kit.list(left, 2); Kit.list(right, 2)
			Kit.caption(left, "Income", 0)
			Kit.caption(right, "Costs", 0)
			for i, l in income do lineRow(left, i, App.categoryLabel(l.cat, false), "+" .. dollars(l.value), C.good) end
			for i, l in costs do lineRow(right, i, App.categoryLabel(l.cat, true), "-" .. dollars(l.value), C.bad) end
			if #income == 0 then lineRow(left, 1, "No income yet", "$0", C.dim) end
			if #costs == 0 then lineRow(right, 1, "No costs yet", "$0", C.dim) end
			lineRow(left, 99, "Total", "+" .. dollars(inTotal), C.good, true)
			lineRow(right, 99, "Total", if outTotal > 0 then "-" .. dollars(outTotal) else "$0", C.bad, true)
			local n = inTotal - outTotal
			net.Text = "Net today  " .. (if n >= 0 then "+" else "") .. dollars(n)
			net.TextColor3 = if n >= 0 then C.good else C.bad
			-- last days: oldest left, today right
			clearRows(tableFrame)
			clearRows(chart)
			local shown = {}
			for i = math.min(#list, Ops.LEDGER_SHOWN), 1, -1 do table.insert(shown, list[i]) end
			daysText.Text = if #shown <= 1 then "The table fills up day by day (the last " .. Ops.LEDGER_SHOWN .. " company days are kept here)." else string.format("The last %d company days (today so far on the right).", #shown)
			local head = Kit.frame(tableFrame, UDim2.new(1, 0, 0, 22))
			head.LayoutOrder = 0
			local w = 1 / (#shown + 1)
			Kit.cell(head, "", UDim.new(w, 0), 13, F.medium, C.muted)
			local rowNames = { "Income", "Costs", "Net" }
			local totals: { { number } } = {}
			for j, day in shown do
				local _, _, a, b = App.ledgerDay(ledger[tostring(day)])
				totals[j] = { a, b, a - b }
				local cell = Kit.cell(head, if day == dayNow then "Day " .. day .. " (today)" else "Day " .. day, UDim.new(w, 0), 13, F.bold, C.muted)
				cell.Position = UDim2.fromScale(w * j, 0)
				cell.TextXAlignment = Enum.TextXAlignment.Right
			end
			for r, rowName in rowNames do
				local row = Kit.frame(tableFrame, UDim2.new(1, 0, 0, 22))
				row.LayoutOrder = r
				Kit.cell(row, rowName, UDim.new(w, 0), 14, if r == 3 then F.bold else F.regular, if r == 3 then C.text else C.muted)
				for j in shown do
					local v = totals[j][r]
					local text = if r == 1 then "+" .. dollars(v) elseif r == 2 then "-" .. dollars(v) else (if v >= 0 then "+" else "") .. dollars(v)
					local cell = Kit.cell(row, text, UDim.new(w, 0), 14, F.bold, if r == 1 then C.good elseif r == 2 then C.bad elseif v >= 0 then C.good else C.bad)
					cell.Position = UDim2.fromScale(w * j, 0)
					cell.TextXAlignment = Enum.TextXAlignment.Right
				end
			end
			-- net bars per day (zero line placed by the largest gain and loss, like the profit chart)
			tableFrame.Visible = #shown >= 1
			chart.Visible = #shown >= 1
			local hi, lo = 0, 0
			for _, t in totals do hi = math.max(hi, t[3]); lo = math.min(lo, t[3]) end
			local range = math.max(1, hi - lo)
			local zeroY = hi / range
			local zero = Kit.frame(chart, UDim2.new(1, 0, 0, 1), UDim2.fromScale(0, zeroY))
			zero.BackgroundTransparency = 0.5
			zero.BackgroundColor3 = C.dim
			for j, t in totals do
				local h = math.abs(t[3]) / range
				local b = Kit.frame(chart, UDim2.new(w * 0.5, 0, h, 0), UDim2.fromScale(w * j + w * 0.45, zeroY))
				b.AnchorPoint = Vector2.new(0, if t[3] >= 0 then 1 else 0)
				b.BackgroundTransparency = 0.15
				b.BackgroundColor3 = if t[3] >= 0 then C.good else C.bad
				Kit.corner(b, 3)
			end
		end
		-- running rates per game day from the live summary (live.ops: $/min per category)
		clearRows(runRows)
		local ops = if typeof(s.live.ops) == "table" then s.live.ops else {}
		local revenueMin = (tonumber(s.live.revenue) or 0) * 60
		local costMin = (tonumber(s.live.cost) or 0) * 60
		local b2b, guest = tonumber(ops.b2b) or 0, tonumber(ops.guest) or 0
		type Line = { label: string, value: number, income: boolean }
		local lines: { Line } = {
			{ label = "AI products (users + API)", value = math.max(0, revenueMin - b2b - guest), income = true },
			{ label = "Client retainers", value = b2b, income = true },
			{ label = "Guest house", value = guest, income = true },
		}
		local known = 0
		for _, key in { "wages", "ops", "upkeep", "food", "fleet", "guest", "jet", "b2bserve" } do
			local v = tonumber(ops[key .. "Cost"]) or 0
			known += v
			table.insert(lines, { label = App.categoryLabel(key, true), value = v, income = false })
		end
		table.insert(lines, { label = "Serving & power", value = math.max(0, costMin - known), income = false })
		local order = 0
		for _, l in lines do
			if l.value > 0.5 then
				order += 1
				lineRow(runRows, order, l.label, (if l.income then "+" else "-") .. perDay(l.value), if l.income then C.good else C.bad)
			end
		end
		order += 1
		local netMin = revenueMin - costMin
		lineRow(runRows, order, "Net", (if netMin >= 0 then "+" else "-") .. perDay(math.abs(netMin)), if netMin >= 0 then C.good else C.bad, true)
	end)
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
				local row = Kit.frame(rows, UDim2.new(1, 0, 0, 52))
				row.LayoutOrder = i
				local initials = ""
				for word in string.gmatch(a.n, "%S+") do initials ..= string.sub(word, 1, 1) end
				Conversation.avatar(row, string.upper(string.sub(initials, 1, 2)), a.s, 40).Position = UDim2.fromOffset(0, 6)
				local name = Kit.text(row, a.n, 16, F.bold, C.text)
				name.Position = UDim2.fromOffset(52, 4)
				-- same price the server charges (RecruitingService.hireCost: escalates with the team size)
				local cost = if roleDef then Format.money(math.floor(Math.hireCost(e, roleDef) * a.ask + 0.5)) else "?"
				local sub = Kit.text(row, string.format("%s  ·  %d yrs  ·  ex-%s  ·  asks %s", if roleDef then roleDef.name else a.role, a.xp, a.prev, cost), 13, F.regular, C.muted)
				sub.Position = UDim2.fromOffset(52, 27)
				sub.AutomaticSize = Enum.AutomaticSize.None
				sub.Size = UDim2.new(1, -250, 0, 18)
				sub.TextTruncate = Enum.TextTruncate.AtEnd
				local status = Kit.text(row, "", 12, F.medium, C.muted)
				status.AnchorPoint = Vector2.new(1, 0)
				status.Position = UDim2.new(1, -180, 0, 6)
				status.TextXAlignment = Enum.TextXAlignment.Right
				if a.st == "new" then
					expiry[a.id] = status
					local invite = Kit.button(row, "Invite", "primary", UDim2.fromOffset(86, 34))
					invite.AnchorPoint = Vector2.new(1, 0.5)
					invite.Position = UDim2.new(1, -90, 0.5, 0)
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
				local reject = Kit.button(row, "Reject", "danger", UDim2.fromOffset(80, 34))
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
			if label then label.Text = "Closes in " .. Format.duration(math.max(0, Math.APPLICATION_SECONDS - ((e.seconds or 0) - a.at))) end
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
			local row = Kit.frame(rows, UDim2.new(1, 0, 0, 34))
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
	end)
	selector.frame.LayoutOrder = 3
	rows = Kit.stack(card, 4, 4)
	more = para(card, "", 5)
	watch(update)
end
local function team(parent: Instance)
	local intro = Kit.card(parent, 1)
	title(intro, "Specialists, real advantages")
	local capacity = para(intro, "")
	watch(function(s)
		local e = s.data.empire
		capacity.Text = string.format("%d / %d desks filled. Staff earn wages every second, day and night (also on vacation and sick days). Bonuses stop when you dismiss an employee. Hiring fees are non-refundable. Agency hires start at once with average skill (★2–★3); interviewing applicants is how you find stronger people. Automatic HR and apprentices: Company → Settings.",Math.staff(e),Config.OFFICES[e.office].staff)
	end)
	applications(parent, 2)
	roster(parent, 3)
	for i, role in Config.ROLES do
		local card = Kit.card(parent, i+3)
		title(card, role.name)
		para(card, role.desc)
		local info = para(card, "", 3)
		local row = Kit.row(card,40,10,4)
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
local function research(parent: Instance)
	local active=Kit.card(parent,1)
	title(active,"The research lab")
	local info=para(active,"")
	local bar=Kit.bar(active,8,3)
	watch(function(s)
		local e=s.data.empire
		local job=e.researchJob
		local b=Math.bonuses(e)
		info.Text=string.format("%.0f RP available · +%.2f RP/s at full staff (only during office hours)\n",e.points,b.points*(if s.data.company.spec=="research" then 1.2 else 1)) ..
			(if job then "Researching " .. Config.find(Config.RESEARCH,job.id).name .. " · " .. tostring(math.ceil(job.seconds-job.elapsed)) .. "s left" else "Pick your next breakthrough. Research continues while you are online.")
		bar.frame.Visible=job~=nil
		if job then bar.set(job.elapsed/job.seconds) end
	end)
	for i,def in Config.RESEARCH do
		local card=Kit.card(parent,i+1)
		title(card,def.name)
		para(card,def.desc)
		local info=para(card,"",3)
		local b=button(card,"Research",function() call("StartResearch",{researchId=def.id},"Research started: " .. def.name) end)
		watch(function(s)
			local e=s.data.empire
			local locked=def.prereq and not e.research[def.prereq]
			local done=e.research[def.id]==true
			info.Text=string.format("%s · %d RP · %ds",Format.money(def.cost),def.points,def.seconds) ..
				(if locked then "\nRequires: " .. Config.find(Config.RESEARCH,def.prereq).name else "")
			b.Text=if done then "Completed" elseif e.researchJob and e.researchJob.id==def.id then "Researching..." elseif locked then "Locked" else "Start research"
			Kit.setDisabled(b,done or locked==true or e.researchJob~=nil or e.points<def.points or s.data.money<def.cost)
		end)
	end
end
local function milestones(parent: Instance)
	for i,def in Config.QUESTS do
		local card=Kit.card(parent,i)
		title(card,def.name)
		para(card,def.desc .. "  Reward: " .. Format.money(def.reward) .. " + " .. tostring(def.xp) .. " XP")
		local bar=Kit.bar(card,7,3)
		local b=button(card,"In progress",function() call("ClaimQuest",{questId=def.id},"Milestone reward collected!") end)
		watch(function(s)
			local p=Math.progress(s.data,def)
			local done=s.data.empire.quests[def.id]==true
			bar.set(math.min(1,p/def.target))
			b.Text=if done then "Collected" elseif p>=def.target then "Collect " .. Format.money(def.reward) else Format.compact(p) .. " / " .. Format.compact(def.target)
			Kit.setDisabled(b,done or p<def.target)
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
local function settings(parent: Instance)
	-- automatic HR
	local hr = Kit.card(parent, 1)
	title(hr, "Automatic HR")
	local hrText = para(hr, "", 2)
	local autoRow = Kit.row(hr, 36, 12, 3)
	Kit.text(autoRow, "Hire automatically", 15, F.medium, C.text).LayoutOrder = 1
	local autoSwitch = switch(autoRow, { { id = "on", label = "On" }, { id = "off", label = "Off" } }, "on", 2, 170, function(id)
		call("EmpireAction", { action = "hrAuto", on = id == "on" }, if id == "on" then "Automatic HR is on." else "Automatic HR is off. Hire by hand in Team.")
	end)
	local budgetRow = Kit.row(hr, 36, 12, 4)
	Kit.text(budgetRow, "Wage budget", 15, F.medium, C.text).LayoutOrder = 1
	local budgetOptions: { Kit.Option } = {}
	for _, b in Ops.HR_BUDGETS do table.insert(budgetOptions, { id = string.format("%.2f", b), label = string.format("%d %%", math.floor(b * 100 + 0.5)) }) end
	local budgetSwitch = switch(budgetRow, budgetOptions, "0.40", 2, 260, function(id)
		call("EmpireAction", { action = "hrBudget", budget = tonumber(id) }, "Wage budget set to " .. math.floor((tonumber(id) or 0) * 100 + 0.5) .. " % of income.")
	end)
	local needText = para(hr, "", 5)
	dim(hr, "HR hires one person every " .. Ops.HIRE_GAP .. " s into the department furthest below its need, only while the payroll (team + operations staff) stays inside the budget share of the 5-minute income. The first " .. Ops.HR_STARTERS .. " hires are always allowed. In Save mode HR stops at half the desks.", 6)
	-- Save mode
	local save = Kit.card(parent, 2)
	title(save, "Save mode")
	local saveText = para(save, "", 2)
	local saveRow = Kit.row(save, 36, 12, 3)
	Kit.text(saveRow, "Save for the next office", 15, F.medium, C.text).LayoutOrder = 1
	local saveSwitch = switch(saveRow, { { id = "auto", label = "Auto" }, { id = "off", label = "Off" } }, "auto", 2, 170, function(id)
		call("EmpireAction", { action = "saveMode", mode = id }, if id == "auto" then "Save mode: automatic." else "Save mode switched off.")
	end)
	dim(save, "Auto switches on when the next office is less than " .. Ops.SAVE_MINUTES .. " minutes of profit away. It pauses research, Lab levels, big trainings, HR beyond half the desks and ordinary GPU buys. GPUs that pay back fast while servers are full still get bought.", 4)
	-- night shift
	local night = Kit.card(parent, 3)
	title(night, "Night shift")
	local nightText = para(night, "", 2)
	local nightRows = Kit.stack(night, 6, 3)
	local nightSwitches: { [string]: Kit.Segmented } = {}
	local nightLabels: { [string]: TextLabel } = {}
	-- the night crew works per role (CompanyOps.nightOn: any department of the role); the switch sets all of them
	for i, roleDef in Config.ROLES do
		local row = Kit.row(nightRows, 36, 12, i)
		row.Name = "Night_" .. roleDef.id
		local label = Kit.cell(row, roleDef.name, UDim.new(0, 170), 15, F.medium, C.text)
		label.LayoutOrder = 1
		local sub = Kit.cell(row, "", UDim.new(1, -370), 13, F.regular, C.muted)
		sub.LayoutOrder = 2
		nightLabels[roleDef.id] = sub
		nightSwitches[roleDef.id] = switch(row, { { id = "off", label = "Off" }, { id = "on", label = "On" } }, "off", 3, 170, function(id)
			local snapshot = State.snapshot
			if not snapshot then return end
			local map = snapshot.data.empire.nightShift
			task.spawn(function()
				local okAll = true
				for _, dept in Ops.ROLE_DEPTS[roleDef.id] or {} do
					local on = typeof(map) == "table" and map[dept] == true
					if on ~= (id == "on") then
						local ok = Action.call("EmpireAction", { action = "nightShift", dept = dept, on = id == "on" })
						okAll = okAll and ok
					end
				end
				if okAll then Toast.show("success", roleDef.name .. (if id == "on" then ": night shift on." else ": night shift off.")) end
			end)
		end)
	end
	dim(night, "Heads beyond the desks (up to as many again) work 22:00–06:00 at full output instead of half, for " .. string.format("%.1f", Ops.NIGHT.wage) .. "× wage. It only pays when a department has more people than desks. Paused while cash stays below $0 for a whole day.", 4)
	-- apprentices
	local appr = Kit.card(parent, 4)
	title(appr, "Apprentices")
	local apprText = para(appr, "", 2)
	local hireRow = Kit.grid(appr, 4, 40, 8, 3)
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
		call("EmpireAction", { action = "buyJet" }, "The company jet is yours. It waits in the airport hangar with your 2 pilots.")
	end)
	jetButton.Name = "BuyJet"
	-- Lab level lives in the Models app
	local lab = Kit.card(parent, 6)
	title(lab, "Lab level")
	local labText = para(lab, "", 2)
	local labButton = Kit.button(lab, "Open Models", "secondary", UDim2.new(1, 0, 0, 40))
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
		local anyLive = false
		for _, id in s.data.modelOrder do local m = s.data.models[id]; if m and m.status == "live" then anyLive = true; break end end
		hrText.Text = string.format("Payroll now %s · budget %s (%d %% of the income of the last 5 minutes)%s",
			perDay(payrollMin), perDay(budget * income), math.floor(budget * 100 + 0.5), if not auto then " · automatic hiring is off" elseif not anyLive then " · HR starts hiring once your first model is live" else "")
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
		nightText.Text = if nightOpen then "Optional per team. Needs a security guard on duty (operations staff)." else "Night shifts start at the " .. stageName(Ops.NIGHT.from) .. "."
		if nightOpen then
			for _, roleDef in Config.ROLES do
				local heads = e.employees[roleDef.id] or 0
				local seats = Ops.seats(e, roleDef.id)
				local over = math.max(0, heads - seats)
				local on = false
				for _, dept in Ops.ROLE_DEPTS[roleDef.id] or {} do
					if typeof(e.nightShift) == "table" and e.nightShift[dept] == true then on = true end
				end
				nightSwitches[roleDef.id].set(if on then "on" else "off")
				nightLabels[roleDef.id].Text = string.format("%d people / %d desks%s", heads, seats,
					if over > 0 then string.format(" · %d work at night", math.min(over, seats)) elseif on then " · nobody over the desks yet" else "")
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
			jetText.Text = string.format("%s once, then %s/day (%d pilots + upkeep) and %s fuel per abroad trip. Abroad trips take %.1f days instead of %d and win +%d %% trust. Needs the %s.",
				dollars(J.price), dollars(running), J.pilots, dollars(J.fuel), J.days, Ops.TRIPS.abroad.days, math.floor(J.trust * 100), stageName(J.stage))
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
			labText.Text = string.format("Lab level %d / %d. The next level costs %s research points + %s%s and adds +1 to every core stat of future models. It lives in Models.", level, Ops.LAB_MAX, Format.int(pts), dollars(cost), if treeDone then "" else " (after the whole research tree)")
		end
	end)
end
local function board(parent: Instance)
	local head=Kit.card(parent,1)
	title(head,"Company rankings")
	local status=para(head,"Global rankings load in a published game with saving enabled.")
	local mode="overall"
	local selector=Kit.segmented(head,{{id="overall",label="Overall"},{id="coding",label="Coding"},{id="math",label="Math"},{id="reasoning",label="Reasoning"},{id="creativity",label="Creative"},{id="arena",label="Arena"}},mode,function(id) mode=id;if State.snapshot then for _,fn in updaters do fn(State.snapshot) end end end)
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
local builders: { [string]: (Instance) -> () } = {overview=overview,clients=clients,money=money,team=team,research=research,milestones=milestones,office=office,settings=settings,board=board}
local TABS = {{"overview","Overview"},{"clients","Clients"},{"money","Money"},{"team","Team"},{"research","Research"},{"milestones","Goals"},{"office","Office"},{"settings","Settings"},{"board","Board"}}
local function paintTabs()
	for id,btn in tabButtons do btn.BackgroundColor3=if id==current then Theme.accent:Lerp(C.panel,0.6) else C.raised end
end
local function render()
	local container=scroll
	if not container then return end
	updaters={}
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
function App.mount(parent: Frame, navigation: any)
	nav=navigation
	page=parent
	local head=Kit.frame(parent,UDim2.new(1,0,0,38))
	local label=Kit.text(head,"Company",24,F.display,C.text)
	label.Position=UDim2.fromOffset(0,2)
	local tabs=Instance.new("ScrollingFrame")
	tabs.Name="Tabs"
	tabs.BackgroundTransparency=1
	tabs.BorderSizePixel=0
	tabs.Size=UDim2.new(1,0,0,46)
	tabs.Position=UDim2.fromOffset(0,42)
	tabs.CanvasSize=UDim2.new()
	tabs.AutomaticCanvasSize=Enum.AutomaticSize.X
	tabs.ScrollingDirection=Enum.ScrollingDirection.X
	tabs.ScrollBarThickness=2
	tabs.Parent=parent
	Kit.list(tabs,6,true)
	tabButtons={}
	for i,def in TABS do
		local b=Kit.button(tabs,def[2],"secondary",UDim2.fromOffset(96,36))
		b.Name="Tab_"..def[1]
		b.LayoutOrder=i
		tabButtons[def[1]]=b
		Kit.onClick(b,function()
			current=def[1]
			render()
		end)
	end
	paintTabs()
	local body=Kit.scroll(parent,UDim2.new(1,0,1,-100),UDim2.fromOffset(0,100))
	body.Name="EmpireScroll"
	scroll=body
	State.onChange(function(s)
		if not s.data.company then return end
		if #updaters==0 then render() end
		for _,fn in updaters do fn(s) end
	end)
	State.onNotify(function(kind,payload)
		if kind=="EMPIRE_NOTICE" and typeof(payload.text)=="string" then Toast.show("success",payload.text,5) end
	end)
end
function App.onShow()
	if #updaters==0 and State.snapshot and State.snapshot.data.company then render() end
end
function App.openSection(section: string)
	local id=if section=="contracts" then "clients" else section
	if builders[id] then current=id;render() end
end
return App
