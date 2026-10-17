--!strict
-- The company: hiring, research, offices, quests, the daily login, Lab levels, the company jet and the
-- per-second company tick (wages, then CompanyOps.step: B2B pipeline, running costs, calendar, safety
-- rules), plus the automatic HR coordinator and the server racks (CORE_SPEC 3-8).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.EmpireConfig)
local Math = require(Shared.EmpireMath)
local ModelMath = require(Shared.ModelMath)
local Workforce=require(Shared.WorkforceMath)
local Employee=require(Shared.Config.EmployeeConfig)
local DepartmentConfig=require(Shared.Config.DepartmentConfig)
local Ops=require(Shared.CompanyOps)
local Guard = require(script.Parent.Parent.Lib.Guard)
local Remote = require(script.Parent.Parent.Lib.Remote)
local SessionService = require(script.Parent.SessionService)
local Economy = require(script.Parent.EconomyService)
local PlotService = require(script.Parent.PlotService)
local TutorialMath = require(Shared.TutorialMath)
local Funnel = require(script.Parent.Parent.Lib.Funnel)
local ShopService = require(script.Parent.ShopService) -- shop package: the Eureka voucher (ShopService never requires this module)
local Empire = {}
local function success(session: any): any
	SessionService.markDirty(session)
	return { ok = true }
end
-- payload.apprentice = true (CORE_SPEC 11.1, from the Training Lead's stage): half the agency fee, skill 1
-- rising +1 per 3 company days to 3, 40 % wage, regular staff after 9 days (CompanyOps.apprentice / graduate).
-- Apprentices are kept in empire.apprentices[tostring(seed)] = {day}, never in the profile.
local function hire(session: any, payload: any): any
	local role = Config.find(Config.ROLES, payload.roleId)
	if not role then return {ok=false, err="BAD_INPUT"} end
	local e = session.data.empire
	local count=if payload.count==nil then 1 else payload.count
	if typeof(count)~="number" or count~=math.floor(count) or count<1 or count>10 then return {ok=false,err="BAD_INPUT"} end
	if payload.apprentice~=nil and typeof(payload.apprentice)~="boolean" then return {ok=false,err="BAD_INPUT"} end
	local apprentice=payload.apprentice==true
	if apprentice and Ops.stageIndex(e)<Ops.TRAINING_LEAD.from then return {ok=false,err="OFFICE"} end
	if Math.staff(e)+count > Config.OFFICES[e.office].staff then return {ok=false, err="STAFF_FULL"} end
	local cost=0
	local owned=e.employees[role.id] or 0
	for i=0,count-1 do
		local fee=Math.hireCost({employees={[role.id]=owned+i}},role)
		cost+=if apprentice then math.floor(fee*Ops.APPRENTICE.fee) else fee
	end
	if not Economy.spend(session,cost,"hire") then return {ok=false, err="NO_MONEY"} end
	-- Agency hires (instant, flat fee) are solid but average: skill 2-3, standard wage.
	Math.syncProfiles(e,session.userId)
	local list=e.staffProfiles[role.id]
	local names={}
	if apprentice and typeof(e.apprentices)~="table" then e.apprentices={} end
	for _=1,count do
		local name,seed=Math.nextIdentity(e,session.userId)
		table.insert(list,{n=name,s=seed,k=if apprentice then Ops.APPRENTICE.startSkill else 2+Employee.hash(seed+5)%2,w=1})
		if apprentice then e.apprentices[tostring(seed)]={day=Ops.day(e)} end
		table.insert(names,name)
	end
	e.employees[role.id]=owned+count
	PlotService.refresh(session)
	SessionService.markDirty(session)
	return { ok = true, names = names }
end
-- Dismisses payload.index (1-based position in the role's team list; an optional payload.name must
-- match), otherwise the lowest-skill person of the role (the most recent hire among equals).
-- Counts and profiles stay in sync.
local function fire(session: any, payload: any): any
	local role = Config.find(Config.ROLES, payload.roleId)
	if not role then return {ok=false, err="BAD_INPUT"} end
	local e = session.data.empire
	local n=e.employees[role.id] or 0
	if n < 1 then return {ok=false, err="NOT_OWNED"} end
	if payload.index~=nil and (typeof(payload.index)~="number" or payload.index~=math.floor(payload.index) or payload.index<1 or payload.index>n) then return {ok=false, err="BAD_INPUT"} end
	Math.syncProfiles(e,session.userId)
	local list=e.staffProfiles[role.id]
	local index=payload.index
	-- the team list may have changed since the client rendered it: an optional name must still match
	if index~=nil and typeof(payload.name)=="string" and list[index].n~=payload.name then return {ok=false, err="BAD_INPUT"} end
	if index==nil then
		index=n
		for i=n,1,-1 do if list[i].k<list[index].k then index=i end end
	end
	local gone=table.remove(list,index)
	if typeof(gone)=="table" and typeof(e.apprentices)=="table" then e.apprentices[tostring(gone.s)]=nil end
	e.employees[role.id] = n-1
	e.unpaidLeave=math.clamp(math.floor(tonumber(e.unpaidLeave) or 0),0,Math.staff(e))
	PlotService.refresh(session)
	return success(session)
end
local function research(session: any, payload: any): any
	local def = Config.find(Config.RESEARCH, payload.researchId)
	if not def then return {ok=false, err="BAD_INPUT"} end
	local e = session.data.empire
	if e.research[def.id] then return {ok=false, err="ALREADY_DONE"} end
	if e.researchJob then return {ok=false, err="RESEARCH_ACTIVE"} end
	if def.prereq and not e.research[def.prereq] then return {ok=false, err="PREREQUISITE"} end
	if e.points < def.points then return {ok=false, err="NO_POINTS"} end
	if not Economy.spend(session, def.cost, "research") then return {ok=false, err="NO_MONEY"} end
	e.points -= def.points
	e.researchJob = { id = def.id, elapsed = 0, seconds = def.seconds }
	return success(session)
end
-- Office upgrade (CORE_SPEC 2.1). Leaving the garage needs the first signed client AND the price.
local function upgrade(session: any, _payload: any): any
	local e = session.data.empire
	local def = Config.OFFICES[e.office + 1]
	if not def then return {ok=false, err="MAX_OFFICE"} end
	if e.office == 1 and (tonumber(e.contractsCompleted) or 0) < 1 then return {ok=false, err="FIRST_CLIENT"} end
	if not Economy.spend(session, def.price, "office") then return {ok=false, err="NO_MONEY"} end
	e.office += 1
	e.xp += 100
	-- S1 (shop fix round 1): a cash pack bought twice in the last office was saved as a credit; one per size is paid
	-- now, at the new office's amount. The guard keeps ShopService test doubles without the hook working.
	if typeof((ShopService :: any).payPackCredits) == "function" then
		ShopService.payPackCredits(session)
	end
	PlotService.refresh(session)
	Ops.post(e, "moved into the " .. def.name)
	Remote.fire(session.player, "Notify", "EMPIRE_NOTICE", { text = "New office unlocked: " .. def.name })
	return success(session)
end
-- ClaimQuest {all = true} (ONBOARDING_SPEC B11, menu package): every finished goal at once, no yield between the
-- checks and the grants (one reward per quest). Returns {ok, claimed = {ids}, total}; nothing claimable = ok, total 0.
local function claimAll(session: any): any
	local data = session.data
	local claimed, total = {}, 0
	for _, def in Config.QUESTS do
		if not data.empire.quests[def.id] and Math.progress(data, def) >= def.target then
			data.empire.quests[def.id] = true
			data.empire.xp += def.xp
			total += def.reward
			table.insert(claimed, def.id)
		end
	end
	if total > 0 then
		Economy.grant(session, total, "quest")
		SessionService.markDirty(session)
	end
	return { ok = true, claimed = claimed, total = total }
end
local function quest(session: any, payload: any): any
	if payload.all ~= nil then
		if payload.all ~= true then return {ok=false, err="BAD_INPUT"} end
		return claimAll(session)
	end
	local def = Config.find(Config.QUESTS, payload.questId)
	if not def then return {ok=false, err="BAD_INPUT"} end
	local data = session.data
	if data.empire.quests[def.id] then return {ok=false, err="ALREADY_DONE"} end
	if Math.progress(data, def) < def.target then return {ok=false, err="NOT_READY"} end
	-- No yields between eligibility and grant: one reward per quest.
	data.empire.quests[def.id] = true
	data.empire.xp += def.xp
	Economy.grant(session, def.reward, "quest")
	return success(session)
end
-- The old daily contract clicks are gone (EmpireConfig.CONTRACTS = {}): their clients are in the B2B
-- pipeline (CompanyOps). The remote stays bound so old clients get a clean answer.
local function deliver(session: any, payload: any): any
	local def = Config.find(Config.CONTRACTS, payload.contractId)
	if not def or typeof(payload.modelId) ~= "string" then return {ok=false, err="BAD_INPUT"} end
	return {ok=false, err="BAD_INPUT"}
end
local function daily(session: any, _payload: any): any
	local e = session.data.empire
	local day = math.floor(os.time() / 86400)
	if e.daily.day >= day then return {ok=false, err="ALREADY_DONE"} end
	local streak = if e.daily.day == day - 1 then math.min(7, e.daily.streak + 1) else 1
	e.daily = {day = day, streak = streak}
	local reward = 1000 + (streak - 1) * 500
	e.points += 15
	e.xp += 50
	Economy.grant(session, reward, "daily")
	return success(session)
end
-- Lab levels (CORE_SPEC 7.5): repeatable researcher sink after the whole research tree.
-- Level L -> L+1 costs floor(200 * 1.35^L) research points and $floor(6000 * 1.6^L); +1 core stat each.
Empire.labCost = Ops.labCost
function Empire.labLevel(session: any): any
	local e = session.data.empire
	local L = math.floor(tonumber(e.labLevel) or 0)
	if L >= Ops.LAB_MAX then return {ok=false, err="MAX_LEVEL"} end
	for _, def in Config.RESEARCH do if not e.research[def.id] then return {ok=false, err="PREREQUISITE"} end end
	local pts, cost = Empire.labCost(L)
	if e.points < pts then return {ok=false, err="NO_POINTS"} end
	if not Economy.spend(session, cost, "lab") then return {ok=false, err="NO_MONEY"} end
	e.points -= pts
	e.labLevel = L + 1
	Ops.post(e, "Lab level " .. e.labLevel .. ": +1 core stat on future models")
	return success(session)
end

-- runtime state per session (never saved): auto-HR clock + trailing income, last office attributes
local runtime: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
local function stateOf(session: any): any
	local r = runtime[session]
	if not r then r = { hrClock = 0, income = nil }; runtime[session] = r end
	return r
end
Empire.HIRE_GAP = Ops.HIRE_GAP
Empire.SAVE_NEWS_HOLD = 20
-- Automatic HR (CORE_SPEC 8.1): every HIRE_GAP seconds one agency hire into the department with the
-- lowest heads / need below its need, within the wage budget of the 5-minute trailing income, through
-- the normal hire path. Save mode stops it at half the desks; never while broke or anyone is on leave.
local function autoHire(session: any, dt: number, saving: boolean)
	local e = session.data.empire
	local r = stateOf(session)
	r.hrClock += dt
	if r.hrClock < Ops.HIRE_GAP then return end
	local auto = Ops.hrSettings(e)
	if not auto then return end
	local live = false
	for _, id in session.data.modelOrder do local m = session.data.models[id]; if m and m.status == "live" then live = true; break end end
	if not live then return end -- nothing to sell yet: no payroll
	local roleId = Ops.hrPick(e)
	if not roleId then return end
	if not Ops.hrAllowed(e, session.data.money, r.income or 0, saving, roleId) then return end
	local role = Config.find(Config.ROLES, roleId)
	if not role or session.data.money - Ops.reserve(e) * 1.5 < Math.hireCost(e, role) then return end
	local result = hire(session, { roleId = roleId, count = 1 })
	if result.ok then
		r.hrClock = 0
		Ops.post(e, string.format("HR hired %s (%s, fee %s)", tostring(result.names and result.names[1] or "someone"), role.name, Ops.money(Math.hireCost(e, role))))
	end
end
-- The garage stage's site board (CORE_SPEC 2.3): "Future HQ of <company>: first client yes/no, $x / $27,000".
-- Money is shown in whole thousands, so the text (and the office attribute SiteGoal) changes rarely.
function Empire.siteGoal(data: any): string?
	local e = data.empire
	if Ops.stageIndex(e) ~= 1 or not data.company then return nil end
	local nextDef = Config.OFFICES[2]
	local signed = (tonumber(e.contractsCompleted) or 0) >= 1
	local cash = math.max(0, math.floor((tonumber(data.money) or 0) / 1000) * 1000)
	return string.format("Future HQ of %s\nFirst client: %s\n%s / %s saved", data.company.name, if signed then "signed" else "not yet", Ops.money(math.min(cash, nextDef.price)), Ops.money(nextDef.price))
end
-- Office attributes for the building visuals: HotelRooms / HotelGuests (guest house), RackFaults
-- ("3,7" = blade slots of failed GPUs in PlotService blade order), ServerFaults (count), SiteGoal (garage
-- stage: the goal text, also written into the site board's Body label). Written on change.
local function officeAttributes(session: any)
	local p = PlotService.get(session.player)
	local office = if p then p.office else nil
	if not office then return end
	local e = session.data.empire
	local st = Ops.stage(e)
	local function set(name: string, value: any)
		if office:GetAttribute(name) ~= value then office:SetAttribute(name, value) end
	end
	local goal = Empire.siteGoal(session.data)
	if goal and office:GetAttribute("SiteGoal") ~= goal then
		office:SetAttribute("SiteGoal", goal)
		local r = runtime[session]
		local body = if r then r.siteBody else nil
		if not (body and body:IsDescendantOf(office)) then
			body = nil
			local board = office:FindFirstChild("SiteBoard", true) -- tier 0 only (small model), once per rebuild
			if board then
				for _, d in board:GetDescendants() do
					if d.Name == "Body" and d:IsA("TextLabel") then body = d; break end
				end
			end
			if r then r.siteBody = body end
		end
		if body then (body :: TextLabel).Text = goal end
	elseif not goal and office:GetAttribute("SiteGoal") ~= nil then
		office:SetAttribute("SiteGoal", nil)
	end
	if st.guest then
		set("HotelRooms", Ops.GUEST.rooms)
		set("HotelGuests", Ops.hotelGuests(e))
	end
	local slots = {}
	for _, f in Ops.faults(e) do table.insert(slots, tostring(f.slot)) end
	set("RackFaults", table.concat(slots, ","))
	set("ServerFaults", #slots)
end
-- A research project is done: the same effects for the timer (tick) and the Eureka voucher (SHOP_SPEC 3.1), so goals,
-- the HUD, the 7B unlock and the Studio lock update the same way. The player sees the same notice either way.
local function completeResearch(session: any, id: string)
	local e = session.data.empire
	e.research[id] = true
	e.researchJob = nil
	e.xp += 150
	local def = Config.find(Config.RESEARCH, id)
	Remote.fire(session.player, "Notify", "EMPIRE_NOTICE", {text = "Research complete: " .. (if def then def.name else id)})
end
-- Eureka voucher (shop package, SHOP_SPEC 3.1; redeemed through ShopAction {action = "redeem", key = "eureka", target}):
-- finishes ONE research project or ONE Lab level now. Its research points and its timer are covered; its $ price is
-- still paid. Deterministic, no yield between the checks and the effect; any error keeps the voucher (ShopService).
--   target = "lab"          -> the next Lab level (tree complete, level < 10, cash for the level); no RP taken
--   a project is running    -> it finishes now and its research points come back (target nil or its id); no cash
--   target = a research id  -> start + finish it now (known, not done, prerequisite done, cash); no RP taken
function Empire.eureka(session: any, target: any): (boolean, string?)
	local data = session.data
	if not data.company then return false, "NO_COMPANY" end
	local e = data.empire
	local want = if target == nil then nil else Guard.id(target)
	if target ~= nil and not want then return false, "BAD_INPUT" end
	if want == "lab" then
		local L = math.floor(tonumber(e.labLevel) or 0)
		if L >= Ops.LAB_MAX then return false, "MAX_LEVEL" end
		for _, def in Config.RESEARCH do if not e.research[def.id] then return false, "PREREQUISITE" end end
		local _, cost = Empire.labCost(L)
		if not Economy.spend(session, cost, "lab") then return false, "NO_MONEY" end
		e.labLevel = L + 1
		Ops.post(e, "Lab level " .. e.labLevel .. " (Eureka): +1 core stat on future models")
		SessionService.markDirty(session)
		return true, nil
	end
	local job = e.researchJob
	if job then
		if want ~= nil and want ~= job.id then return false, "RESEARCH_ACTIVE" end
		local def = Config.find(Config.RESEARCH, job.id)
		e.points = math.min(100000, e.points + (if def then def.points else 0))
		completeResearch(session, job.id)
		SessionService.markDirty(session)
		return true, nil
	end
	local def = Config.find(Config.RESEARCH, want)
	if not def then return false, "BAD_INPUT" end
	if e.research[def.id] then return false, "ALREADY_DONE" end
	if def.prereq and not e.research[def.prereq] then return false, "PREREQUISITE" end
	if not Economy.spend(session, def.cost, "research") then return false, "NO_MONEY" end
	completeResearch(session, def.id)
	SessionService.markDirty(session)
	return true, nil
end
function Empire.tick(session: any, dt: number)
	local data = session.data
	if not data.company then return end
	local e = data.empire
	local clock = workspace:GetServerTimeNow()
	local b = Math.bonuses(e)
	local duty = Ops.duty(clock) -- stock outputs follow the time sheet (mean 1 per game day): nothing at night
	e.seconds += dt
	e.points = math.min(100000, e.points + b.points * dt * duty * (if data.company.spec == "research" then 1.2 else 1))
	local access = e.subscriptions
	if access.expires and access.expires > os.time() then
		e.points = math.min(100000,e.points + math.min(3,access.score/100) * dt)
	end
	e.lastSeen = os.time()
	local job = e.researchJob
	if job then
		job.elapsed = math.min(job.seconds, job.elapsed + dt)
		if job.elapsed >= job.seconds then
			completeResearch(session, job.id)
		end
	end
	local curators = Workforce.count(e,"curator")
	if curators > 0 then
		local total = ModelMath.dataSummary(data.data).total
		local tokens = math.min(curators * 300000 * dt * duty, math.max(0, 1e12 - total))
		if tokens > 0 then
			local quality = if e.research.cleaning then 0.85 else 0.65
			for _, id in {"general", "code", "math"} do ModelMath.addTokens(data.data, id, tokens / 3, quality) end
		end
	end
	-- MarketService sets the model flow first. Staff costs are added once, then the company runs.
	Economy.applyFlow(session, 0, b.wage * dt, "wages")
	session.live.cost += b.wage
	Ops.step(session, dt, Economy, clock)
	if session.live.ops then session.live.ops.wagesCost = math.floor(b.wage * 60 + 0.5) end
	-- apprentices whose 9 training days are over become regular staff (skill 3, full wage)
	local graduates = Ops.graduate(e)
	if #graduates > 0 then
		for _, name in graduates do Ops.post(e, "apprentice " .. name .. " graduated (skill 3, full wage)", clock) end
		PlotService.refresh(session)
	end
	-- servers: rack faults (deterministic per company and minute of play) and the compute summary
	Ops.faultStep(e, data.gpus, session.userId, dt, clock)
	local fleet = ModelMath.fleet(data.gpus)
	local faults = {}
	-- eta = remaining repair seconds at the current rate in whole 5 s steps (apps request 2: exact across IT shift changes)
	local faultRate = if Ops.itOnDuty(e, clock) then 1 / Ops.FAULT.it else 1 / Ops.FAULT.alone
	for _, f in Ops.faults(e) do table.insert(faults, { slot = f.slot, gpu = f.gpu, since = math.floor(f.since), eta = math.ceil(f.left / faultRate / 5) * 5 }) end
	session.live.compute = { units = fleet.throughput, lost = Ops.faultLoss(e), reserved = math.floor(((e.deals and e.deals.reserved) or 0) * 100 + 0.5) / 100,
		slots = fleet.slotsUsed, it = Ops.itOnDuty(e, clock), faults = faults }
	-- trailing income (5-minute average) and Save mode for the HR coordinator
	local r = stateOf(session)
	local revenue = session.live.revenue or 0
	r.income = if r.income == nil then revenue else r.income + (revenue - r.income) * math.min(1, dt / 300)
	local saving = Ops.saveMode(e, data.money, revenue - (session.live.cost or 0))
	if session.live.ops then
		session.live.ops.saveMode = saving
		session.live.ops.income = math.floor(r.income * 60 + 0.5)
	end
	-- Save mode switches write one news line (CORE_SPEC 8.2) once the new state has held SAVE_NEWS_HOLD
	-- seconds (the market cycle swings net profit; no news spam around the threshold)
	if r.saveShown == nil then r.saveShown = saving; r.saveFlip = 0 end
	if saving ~= r.saveShown then
		r.saveFlip += dt
		if r.saveFlip >= Empire.SAVE_NEWS_HOLD then
			r.saveShown = saving
			r.saveFlip = 0
			local nextDef = Config.OFFICES[Ops.stageIndex(e) + 1]
			Ops.post(e, if saving and nextDef then "Save mode on: saving for the " .. nextDef.name else "Save mode off", clock)
		end
	else
		r.saveFlip = 0
	end
	autoHire(session, dt, saving)
	officeAttributes(session)
	e.historyClock += dt
	if e.historyClock >= 10 then
		e.historyClock = 0
		table.insert(e.history, {
			time = workspace:GetServerTimeNow(),
			profit = math.round((session.live.revenue - session.live.cost) * 600) / 10,
			users = math.round(session.live.users),
		})
		while #e.history > 36 do table.remove(e.history, 1) end
	end
	SessionService.markDirty(session)
end

-- Remotes: EmpireAction (company settings and late purchases) and DealAction (B2B clients) -----------------
local function setFlag(session: any): any
	return success(session)
end
-- EmpireAction {action = "tutorial", op = ...} (ONBOARDING_SPEC A6, menu package): the guide's flags only. No op
-- changes money, items or unlocks; a forged `step` can only distort analytics. Funnel steps (A11): op step n = 2..6
-- sends funnel step n + 1 for a new maximum, op done sends 8, a skip is the custom event "TutorialSkipped".
Empire.TUTORIAL_SEEN_MAX = 8
local function tutorialOf(e: any): any
	local t = e.tutorial
	if typeof(t) ~= "table" then
		t = { v = 1, step = 0, done = false, skipped = false, tipsOff = false, seen = {}, tips = {} }
		e.tutorial = t
	end
	if typeof(t.seen) ~= "table" then t.seen = {} end
	if typeof(t.tips) ~= "table" then t.tips = {} end
	if typeof(t.step) ~= "number" or t.step ~= t.step then t.step = 0 end
	return t
end
local function tutorialAction(session: any, p: any): any
	local data = session.data
	local t = tutorialOf(data.empire)
	local op = p.op
	if op == "skip" then
		if t.done == true then return {ok=false, err="ALREADY_DONE"} end
		if t.skipped ~= true then
			t.skipped = true
			Funnel.custom(session.player, "TutorialSkipped", math.clamp(math.floor(t.step), 0, TutorialMath.STEPS))
		end
		return setFlag(session)
	elseif op == "done" then
		if (tonumber(data.stats.modelsReleased) or 0) < 1 then return {ok=false, err="NOT_READY"} end
		if t.done ~= true then
			t.done = true
			Funnel.step(session.player, 8)
		end
		return setFlag(session)
	elseif op == "restart" then
		if (tonumber(data.stats.modelsReleased) or 0) ~= 0 then return {ok=false, err="NOT_AVAILABLE"} end
		t.skipped = false
		t.done = false
		t.step = 0
		return setFlag(session)
	elseif op == "step" then
		local n = Guard.integer(p.n, 1, 6)
		if not n then return {ok=false, err="BAD_INPUT"} end
		if t.done == true or t.skipped == true then return {ok=false, err="NOT_AVAILABLE"} end
		if n > TutorialMath.reachable(data) + 1 then return {ok=false, err="BAD_INPUT"} end
		local before = t.step
		t.step = math.max(before, math.min(n, TutorialMath.STEPS))
		if n >= 2 then Funnel.step(session.player, n + 1) end
		return setFlag(session)
	elseif op == "seen" then
		local keys = p.keys
		if typeof(keys) ~= "table" then return {ok=false, err="BAD_INPUT"} end
		local list = {}
		for i, key in keys do
			if typeof(i) ~= "number" or #list >= Empire.TUTORIAL_SEEN_MAX or typeof(key) ~= "string" or not table.find(TutorialMath.SEEN_KEYS, key) then
				return {ok=false, err="BAD_INPUT"}
			end
			table.insert(list, key)
		end
		if #list == 0 then return {ok=false, err="BAD_INPUT"} end
		for _, key in list do t.seen[key] = true end
		return setFlag(session)
	elseif op == "tip" then
		local key = p.key
		if typeof(key) ~= "string" or not table.find(TutorialMath.TIP_KEYS, key) then return {ok=false, err="BAD_INPUT"} end
		t.tips[key] = true
		return setFlag(session)
	elseif op == "tips" then
		if typeof(p.on) ~= "boolean" then return {ok=false, err="BAD_INPUT"} end
		t.tipsOff = not p.on
		return setFlag(session)
	elseif op == "replayTips" then
		t.tips = {}
		return setFlag(session)
	end
	return {ok=false, err="BAD_INPUT"}
end
Empire.tutorialAction = tutorialAction
local function empireAction(session: any, p: any): any
	local e = session.data.empire
	local action = p.action
	if action == "tutorial" then return tutorialAction(session, p) end -- menu package (ONBOARDING_SPEC A6)
	if action == "labLevel" then return Empire.labLevel(session) end
	if action == "rebrand" then -- shop package (SHOP_SPEC 3.5, S4): free colour & logo change for everyone
		local module = script.Parent:FindFirstChild("CompanyService")
		local company = if module then (require :: any)(module) else nil
		if not company or typeof(company.rebrand) ~= "function" then return {ok=false, err="NOT_AVAILABLE"} end
		return company.rebrand(session, p.color, p.logo)
	end
	if action == "buyJet" then
		local result = Ops.buyJet(session, Economy)
		if result.ok then Ops.post(e, "bought the company jet (2 pilots, " .. Ops.money(Ops.JET.pilots * Ops.JET.pilotWage + Ops.JET.upkeep) .. "/day)"); SessionService.markDirty(session) end
		return result
	end
	if action == "hrBudget" then
		local budget = tonumber(p.budget)
		if budget == nil then return {ok=false, err="BAD_INPUT"} end
		for _, allowed in Ops.HR_BUDGETS do
			if math.abs(allowed - budget) < 1e-6 then e.hr = { auto = (e.hr or {}).auto ~= false, budget = allowed }; return setFlag(session) end
		end
		return {ok=false, err="BAD_INPUT"}
	end
	if action == "hrAuto" then
		if typeof(p.on) ~= "boolean" then return {ok=false, err="BAD_INPUT"} end
		local budget = if typeof(e.hr) == "table" then e.hr.budget else 0.40
		e.hr = { auto = p.on, budget = budget or 0.40 }
		return setFlag(session)
	end
	if action == "saveMode" then
		if p.mode ~= "auto" and p.mode ~= "off" then return {ok=false, err="BAD_INPUT"} end
		e.saveMode = p.mode
		return setFlag(session)
	end
	-- night shift for every department of a role in one call (apps request 5: atomic, so a role is never half on)
	if action == "nightShift" and p.role ~= nil then
		local list = (Ops.ROLE_DEPTS :: { [string]: { string } })[Guard.id(p.role) or ""]
		if not list or typeof(p.on) ~= "boolean" then return {ok=false, err="BAD_INPUT"} end
		if Ops.stageIndex(e) < Ops.NIGHT.from then return {ok=false, err="OFFICE"} end
		if typeof(e.nightShift) ~= "table" then e.nightShift = {} end
		for _, dept in list do e.nightShift[dept] = if p.on then true else nil end
		return setFlag(session)
	end
	if action == "nightShift" then
		local dept = Guard.id(p.dept)
		if not dept or not DepartmentConfig.DEPARTMENTS[dept] or typeof(p.on) ~= "boolean" then return {ok=false, err="BAD_INPUT"} end
		local known = false
		for _, list in Ops.ROLE_DEPTS :: { [string]: { string } } do if table.find(list, dept) then known = true end end
		if not known then return {ok=false, err="BAD_INPUT"} end
		if Ops.stageIndex(e) < Ops.NIGHT.from then return {ok=false, err="OFFICE"} end
		if typeof(e.nightShift) ~= "table" then e.nightShift = {} end
		e.nightShift[dept] = if p.on then true else nil
		return setFlag(session)
	end
	if action == "autoPrice" then
		-- the rule lives in the models package (AIModelService.setAutoPrice validates, re-prices on the next tick)
		local module = script.Parent:FindFirstChild("AIModelService")
		local models = if module then (require :: any)(module) else nil
		local modelId = if p.model ~= nil then p.model else p.modelId
		if models and typeof(models.setAutoPrice) == "function" then
			local result = models.setAutoPrice(session, modelId, p.on) -- non-boolean `on` -> BAD_INPUT there
			if typeof(result) == "table" and result.ok then SessionService.markDirty(session) end
			return result
		end
		local id = Guard.id(modelId)
		local m = if id then session.data.models[id] else nil
		if not m or not m.release or typeof(p.on) ~= "boolean" then return {ok=false, err="BAD_INPUT"} end
		m.release.auto = p.on
		return setFlag(session)
	end
	return {ok=false, err="BAD_INPUT"}
end
-- The founder joins the pilot meeting of a running visit in person: +0.15 trust on that visit.
local function joinMeeting(session: any, client: any): any
	local d = Ops.ensure(session.data.empire)
	for _, trip in d.tripList do
		if trip.client == client.id and trip.kind == "sign" then
			if trip.joined then return {ok=false, err="ALREADY_DONE"} end
			trip.joined = true
			Ops.post(session.data.empire, "founder joined the " .. client.name .. " meeting (+15% trust)")
			SessionService.markDirty(session)
			return {ok=true}
		end
	end
	return {ok=false, err="NO_MEETING"}
end
Empire.joinMeeting = joinMeeting
local MEETING_RANGE = 40
local function dealAction(session: any, p: any): any
	local client = Ops.client(Guard.id(p.clientId))
	if not client then return {ok=false, err="BAD_INPUT"} end
	local d = Ops.ensure(session.data.empire)
	-- pin / skip: an optional boolean `on` sets the state (idempotent, apps request 6); without it they toggle
	if p.action == "pin" then
		local want = if typeof(p.on) == "boolean" then p.on else d.pinned ~= client.id
		d.pinned = if want then client.id elseif d.pinned == client.id then nil else d.pinned
		if d.pinned == client.id then d.skip[client.id] = nil end
		return success(session)
	end
	if p.action == "skip" then
		local want = if typeof(p.on) == "boolean" then p.on else not d.skip[client.id]
		d.skip[client.id] = if want then true else nil
		if want and d.pinned == client.id then d.pinned = nil end
		return success(session)
	end
	if p.action == "joinMeeting" then
		-- the founder must stand at that client's office (lobby, reception or meeting room)
		local module = ReplicatedStorage.Shared.Config:FindFirstChild("CityPlan")
		local character = session.player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if not module or not root or not root:IsA("BasePart") then return {ok=false, err="TOO_FAR"} end
		local dest = (require :: any)(module).clientOffice(client.name)
		local near = false
		if dest then
			for _, cf in { dest.lobby, dest.meeting, dest.reception, dest.door } do
				if typeof(cf) == "CFrame" and (cf.Position - root.Position).Magnitude <= MEETING_RANGE then near = true end
			end
		end
		if not near then return {ok=false, err="TOO_FAR"} end
		return joinMeeting(session, client)
	end
	return {ok=false, err="BAD_INPUT"}
end
function Empire.init()
	local limit = {burst=3, perSecond=1, company=true}
	Remote.bind("HireEmployee", limit, hire)
	Remote.bind("FireEmployee", limit, fire)
	Remote.bind("StartResearch", limit, research)
	Remote.bind("UpgradeOffice", limit, upgrade)
	Remote.bind("ClaimQuest", limit, quest)
	Remote.bind("DeliverContract", limit, deliver)
	Remote.bind("ClaimDaily", limit, daily)
	local actions = {burst=4, perSecond=2, company=true}
	Remote.bind("EmpireAction", actions, empireAction)
	Remote.bind("DealAction", actions, dealAction)
	-- shop package (SHOP_SPEC 3.1): the Eureka voucher. The real ShopService always has the hook; the guard keeps test
	-- doubles of ShopService without it (tests/world/stubs.luau, used by tests/itinerary) working unchanged.
	if typeof((ShopService :: any).setRedeemHandler) == "function" then
		ShopService.setRedeemHandler("eureka", Empire.eureka)
	end
	-- CityService "Start meeting" prompts in the client offices (prompt range checked there)
	local city = script.Parent:FindFirstChild("CityService")
	local plan = ReplicatedStorage.Shared.Config:FindFirstChild("CityPlan")
	if city and plan then
		local City = (require :: any)(city)
		local CityPlan = (require :: any)(plan)
		if typeof(City.setMeetingHandler) == "function" then
			City.setMeetingHandler(function(player: Player, clientId: string, _prompt: ProximityPrompt)
				local session = SessionService.get(player)
				if not session or not session.data.company then return end
				local dest = CityPlan.clientOffice(clientId)
				local client = Ops.clientByName(if dest then dest.name else clientId)
				if not client then return end
				local result = joinMeeting(session, client)
				local text = if result.ok then "You joined the " .. client.name .. " meeting: trust +15%."
					elseif result.err == "ALREADY_DONE" then "You are already in the " .. client.name .. " meeting."
					else "No meeting with " .. client.name .. " is scheduled right now."
				Remote.fire(player, "Notify", "CAMPUS_NOTICE", { text = text })
			end)
		end
	end
end
return Empire
