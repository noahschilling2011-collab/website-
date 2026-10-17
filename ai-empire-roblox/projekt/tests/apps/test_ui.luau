--!nocheck
-- apps package, client side: the real HUD ("Next goal"), Company app (Clients / Money / Settings) and Hardware app
-- (servers, faults, rack) in the mock, wired to the REAL server handlers (EmpireService EmpireAction / DealAction /
-- HireEmployee) through tests/apps/ui_setup.luau. One state per process:
--   garage  first goal "Train your first AI" (journey step, Datasets), garage limits (no night shift / apprentices / jet)
--   client  "Sign your first client (CloudDesk)" with the founder's trip countdown
--   save    "Founder Headquarters $27,000" with "First client ✓ · $18,400 / $27,000" and the nextGoal ETA
--   mid     Startup Campus: Save mode tag, client cards (accounts, leads, pinned, skipped, trip), Pin/Skip/Join payloads,
--           ledger tab sums (4 of 7 days replicated), every Settings switch through the server, apprentices,
--           compute split + fault countdown + 12 rack slots, error texts of CORE_SPEC 11.8
--   rich    Global AI HQ: buy the company jet, 72 rack slots, waitlist line, abroad trips
--   phone   mid on an iPhone-sized touch screen: compact goal card (no hint line, larger title)
-- Run: cd tests/apps && ../../tools/luau test_ui.luau -a .gen_apps <state>
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_apps")
local STATE = args[2] or "mid"
local M = require("../../harness/mock")
local setup = require("./ui_setup")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local DESK = { 1280, 720, { top = 58, right = 0, bottom = 0, left = 0 } }
local IPHONE = { 844, 390, { top = 58, right = 47, bottom = 21, left = 47 } }

local function body()
	local vp = if STATE == "phone" then IPHONE else DESK
	local ui = setup(M, GEN, if STATE == "phone" then "mid" else STATE, vp[1], vp[2], vp[3], { touch = STATE == "phone" })
	local game = M.game
	local RS = game.ReplicatedStorage
	local Client = game.StarterPlayer.StarterPlayerScripts.Client
	local s = ui.session
	local e = s.data.empire
	local pg = ui.playerGui
	local EmpireMath = M.require(RS.Shared.EmpireMath)
	local Ops = M.require(RS.Shared.CompanyOps)
	local HardwareConfig = M.require(RS.Shared.Config.HardwareConfig)
	local Format = M.require(RS.Shared.Format)
	local Action = M.require(Client.Controllers.ActionController)
	local State = M.require(Client.Controllers.StateController)
	local EmpireApp = M.require(Client.UI.Apps.EmpireApp)
	local ComputeApp = M.require(Client.UI.Apps.ComputeApp)
	local HUD = ui.HUD

	local function visible(inst)
		local x = inst
		while x and x ~= pg do
			if (x:IsA("GuiObject") and not x.Visible) or (x:IsA("ScreenGui") and not x.Enabled) then return false end
			x = x.Parent
		end
		return true
	end
	local function texts(root)
		local out = {}
		for _, x in (root or pg):GetDescendants() do
			if (x:IsA("TextLabel") or x:IsA("TextButton")) and visible(x) and x.Text ~= "" then table.insert(out, x.Text) end
		end
		return out
	end
	local function has(needle, root)
		for _, t in texts(root) do if string.find(t, needle, 1, true) then return t end end
		return nil
	end
	local function find(name, root)
		for _, x in (root or pg):GetDescendants() do if x.Name == name and visible(x) then return x end end
		return nil
	end
	local function button(text, root)
		for _, x in (root or pg):GetDescendants() do
			if x:IsA("TextButton") and visible(x) and x.Text == text then return x end
		end
		return nil
	end
	local function click(b)
		if not b then return false end
		M.fire(b.Activated, {}, 1)
		M.settle(0.4)
		return true
	end
	local function lastCall(name)
		for i = #ui.calls, 1, -1 do if ui.calls[i].name == name then return ui.calls[i].payload end end
		return nil
	end
	local function frames(n)
		local RunService = game:GetService("RunService")
		for _ = 1, n or 10 do M.fire(RunService.RenderStepped, 1 / 60) end
	end
	local function openTab(id)
		ui.Computer.open("empire", id)
		M.settle(0.4)
		ui.push()
		return find("Tab_" .. id)
	end

	------------------------------------------------------------------ HUD: Next goal
	local hud = pg:FindFirstChild("AIEmpire_HUD")
	local card = hud and find("NextGoal", hud)
	check("HUD goal card visible", card ~= nil)
	local snap = State.snapshot
	local goal = EmpireMath.nextGoal(snap.data, snap.live)
	local titleLabel = card and find("Title", card)
	check("goal title = EmpireMath.nextGoal text", titleLabel ~= nil and goal ~= nil and titleLabel.Text == goal.text, titleLabel and titleLabel.Text)
	local view = HUD.describe(snap)
	check("HUD.describe agrees with the card", titleLabel ~= nil and view.title == titleLabel.Text and view.id == goal.id)
	check("money shown per game day in the HUD", (function()
		local net = find("NetPerDay", hud)
		return net ~= nil and (net.Text == "no income yet" or string.find(net.Text, "/day$") ~= nil)
	end)(), find("NetPerDay", hud) and find("NetPerDay", hud).Text)
	local have = card and find("Have", card)
	local eta = card and find("Eta", card)
	local hint = card and card:FindFirstChild("Hint")
	if STATE == "garage" then
		check("garage: Train your first AI", goal.id == "train" and titleLabel.Text == "Train your first AI")
		check("garage: journey step progress", have and have.Text == "Step 1 of 7", have and have.Text)
		check("garage: hint from the journey (Datasets)", hint and string.find(hint.Text, "Datasets", 1, true) ~= nil, hint and hint.Text)
		check("garage: milestone reward nudge (company founded quest open)", find("RewardReady", hud) ~= nil)
		click(card)
		check("garage: tap opens the Datasets app", ui.Computer.isOpen() and find("data") ~= nil)
		ui.Computer.close(); M.settle(0.5)
	elseif STATE == "client" then
		check("client: Sign your first client", goal.id == "client" and titleLabel.Text == "Sign your first client (CloudDesk)")
		check("client: trust progress", have and have.Text == "Trust 0 %", have and have.Text)
		check("client: founder trip countdown (back - seconds = 80 s, never a clock-like 1:20)", eta and eta.Text == "back in 1 min 20 s", eta and eta.Text)
		click(card)
		check("client: tap opens Company → Clients", ui.Computer.isOpen() and find("Tab_clients") ~= nil and has("Business clients") ~= nil)
		check("client: founder trip listed on the road", has("You (founder) → CloudDesk · pilot visit · car") ~= nil)
		ui.Computer.close(); M.settle(0.5)
	elseif STATE == "save" then
		check("save: Founder Headquarters goal", goal.id == "office2" and titleLabel.Text == "Founder Headquarters $27,000", titleLabel.Text)
		-- the first form that fits beside the ETA: exact, compact money, compact without the prefix (never cut off)
		local function firstFit(list)
			local room = HUD.WIDTH - 28 - (if eta.Text == "" then 0 else math.ceil(HUD.textWidth(eta.Text, eta.TextSize)) + 10)
			for _, t in list do if HUD.textWidth(t, have.TextSize) <= room then return t end end
			return list[#list]
		end
		check("save: desktop shows the exact form 'Client ✓ · $18,400 / $27,000'", have and have.Text == "Client ✓ · $18,400 / $27,000"
			and firstFit({ "Client ✓ · $18,400 / $27,000" }) == have.Text, have and have.Text)
		check("save: describe() keeps the exact, compact and short forms", view.progress == "Client ✓ · $18,400 / $27,000" and view.compactProgress == "Client ✓ · $18.4K / $27K" and view.shortProgress == "$18.4K / $27K")
		-- deep debt in the garage (reviewer: '-$48,250 / $27,…' was cut off): a shorter form, never an ellipsis
		local cash0 = s.data.money
		s.data.money = -1248250
		ui.push()
		local v2 = HUD.describe(State.snapshot)
		local want2 = firstFit({ v2.progress, v2.compactProgress, v2.shortProgress })
		check("deep debt: progress picks the first form that fits", have.Text == want2 and want2 ~= v2.progress, have.Text .. " / " .. want2)
		s.data.money = cash0
		ui.push()
		local want = "~" .. math.ceil(goal.etaMinutes) .. " min"
		check("save: ETA from nextGoal (" .. want .. ")", eta and eta.Text == want and HUD.etaText(goal.etaMinutes) == want, eta and eta.Text)
		check("save: no Save-mode tag in the garage", find("SaveMode", card) == nil)
		check("save: bar = have / need", math.abs(view.fraction - 18400 / 27000) < 1e-6)
	elseif STATE == "mid" or STATE == "phone" then
		check("mid: Innovation Campus goal", goal.id == "office4" and titleLabel.Text == "Innovation Campus $380,000", titleLabel.Text)
		check("mid: Save-mode tag on the card", find("SaveMode", card) ~= nil)
		if STATE == "phone" then
			check("phone: compact card (no hint line)", hint ~= nil and hint.Visible == false)
			check("phone: larger title on a small screen", titleLabel.TextSize == 20, titleLabel.TextSize)
			local column = find("Column", hud)
			check("phone: HUD column keeps width 300 at -16, scaled by its own UIScale 1.5", column.Size.X.Offset == 300 and column.Position.X.Offset == -16
				and column:FindFirstChild("CompactBoost").Scale == HUD.COMPACT_BOOST and HUD.COMPACT_BOOST == 1.5)
			local hudFrame = find("HUD", hud)
			check("phone: HUD frame attributes LaneWidth = 466, Compact = true", hudFrame and hudFrame:GetAttribute("LaneWidth") == 466 and hudFrame:GetAttribute("Compact") == true, hudFrame and hudFrame:GetAttribute("LaneWidth"))
			-- text and touch targets in screen points: UIRoot scale x the column's boost
			local rootScale = hud:FindFirstChild("Root"):FindFirstChildOfClass("UIScale").Scale
			local k = rootScale * column:FindFirstChild("CompactBoost").Scale
			check("phone: goal title >= 12.5 pt, progress >= 10.5 pt on screen", titleLabel.TextSize * k >= 12.5 and have.TextSize * k >= 10.5, string.format("%.1f / %.1f pt (scale %.3f)", titleLabel.TextSize * k, have.TextSize * k, k))
			local open = find("OpenCompany", hud)
			check("phone: Open company is a 44 pt touch target", open and open.Size.Y.Offset * k >= 44, open and string.format("%.1f pt", open.Size.Y.Offset * k))
			check("phone: compact progress text ($74.3K / $380K)", have.Text == "$74.3K / $380K", have.Text)
		else
			check("desktop: hint line shown with the Save mode reason", hint and hint.Visible and string.find(hint.Text, "Save mode", 1, true) ~= nil, hint and hint.Text)
		end
	elseif STATE == "rich" then
		check("rich: lines at 90+ goal", goal.id == "lines90" and have and have.Text == "1 / 4 lines at 90+", have and have.Text)
	end
	-- a pending training decision is the only thing shown instead of the goal
	do
		local d = s.data
		local saved = d.training
		d.training = { modelId = "x", workTotal = 100, workDone = 10, cost = 0, expected = 40, qualityMod = 1, eventRolled = true, epoch = 1, loss = {}, log = {}, event = { id = "data_issue", pending = true, expiresAt = 0 } }
		ui.push()
		check("decision overrides the goal (warn caption)", find("Caption", card).Text == "Decision needed" and titleLabel.Text == "Your training run needs a decision")
		d.training = saved
		ui.push()
		check("goal back after the decision", titleLabel.Text == goal.text)
	end
	if STATE == "phone" then return end

	------------------------------------------------------------------ Company app: tabs
	openTab("overview")
	local tabs = {}
	for _, x in pg:GetDescendants() do if x:IsA("TextButton") and string.sub(x.Name, 1, 4) == "Tab_" then table.insert(tabs, x.Text) end end
	check("9 Company tabs incl. Clients, Money, Settings; no Contracts tab", #tabs == 9 and table.find(tabs, "Clients") and table.find(tabs, "Money") and table.find(tabs, "Settings") and not table.find(tabs, "Contracts"), table.concat(tabs, ","))
	check("overview shows the next goal and profit per game day", has("Next goal: " .. goal.text) ~= nil and has("Profit per game day") ~= nil)
	check("no lease-auction texts (Business MRR / monthly business customers)", has("Business MRR") == nil and has("Monthly business customers") == nil)

	------------------------------------------------------------------ Clients
	openTab("clients")
	local rows = {}
	for _, x in pg:GetDescendants() do if x:GetAttribute("Group") ~= nil then rows[x] = x:GetAttribute("Group") end end
	local nRows, nAcc = 0, 0
	for _, g in rows do nRows += 1; if g == "account" then nAcc += 1 end end
	local accounts = 0
	for _ in e.deals.accounts do accounts += 1 end
	check("one card per catalogue client (18)", nRows == #Ops.CLIENTS, nRows)
	check("account cards = signed accounts", nAcc == accounts, nAcc .. " vs " .. accounts)
	check("accounts metric", has(string.format("%d / %d", accounts, Ops.accountLimit(e))) ~= nil)
	if STATE == "mid" then
		check("account until day N (CloudDesk: day 10 + 4.0 days)", has("Account until day 14 · 4.0 days left") ~= nil)
		check("renewing account", has("Account · check-in visit under way") ~= nil)
		check("trip under way: rep + engineer to PixelForge (City Hotel night)", has("Field rep + engineer → PixelForge · pilot visit · City Hotel night · back in 15 min") ~= nil)
		check("row status names where the visit is", has("Pilot visit at Business City · back in 15 min") ~= nil)
		check("lead with trust bar text", has("Lead · trust 62 %") ~= nil)
		check("pinned client marked", has("Pinned · visited next") ~= nil)
		check("skipped client marked", has("Skipped · your sales team leaves it out") ~= nil)
		check("later-stage client says where it unlocks", has("Unlocks at the Innovation Campus · Port Meridian, flight + 2 nights") ~= nil)
		check("company log shows the news lines", has("day 10 10:02: rep to PixelForge") ~= nil)
		-- buttons -> DealAction payloads -> real server state
		local function rowOf(name)
			for row in rows do
				for _, x in row:GetDescendants() do if x:IsA("TextLabel") and x.Text == name then return row end end
			end
			return nil
		end
		local study = rowOf("StudySpark")
		click(study and study:FindFirstChild("Pin", true))
		local p = lastCall("DealAction")
		check("Pin → DealAction {pin, study}", p and p.action == "pin" and p.clientId == "study")
		check("server pinned StudySpark", e.deals.pinned == "study")
		local north = rowOf("North Logistics")
		local skipBtn = north and north:FindFirstChild("Skip", true)
		check("skipped client shows Unskip", skipBtn and skipBtn.Text == "Unskip")
		click(skipBtn)
		p = lastCall("DealAction")
		check("Unskip → DealAction {skip, north}", p and p.action == "skip" and p.clientId == "north" and e.deals.skip.north == nil, p and (tostring(p.action) .. "/" .. tostring(p.clientId) .. "/" .. tostring(e.deals.skip.north)))
		local forge = rowOf("PixelForge")
		check("trip under way: Join in person instead of Pin/Skip", forge and forge:FindFirstChild("Join", true).Visible and not forge:FindFirstChild("Pin", true).Visible)
		-- Join away from the client's office: the server says TOO_FAR, the app starts a GPS route there (TravelController)
		local Travel = M.require(Client.Controllers.TravelController)
		local guided
		local origGuide = Travel.guide
		Travel.guide = function(id) guided = id end
		click(forge and forge:FindFirstChild("Join", true))
		M.settle(0.5)
		Travel.guide = origGuide
		p = lastCall("DealAction")
		check("Join → DealAction {joinMeeting, creative}", p and p.action == "joinMeeting" and p.clientId == "creative")
		local CityPlan = M.require(RS.Shared.Config.CityPlan)
		local dest = CityPlan.clientOffice("PixelForge")
		check("Join far away (TOO_FAR) → GPS route to the client's office", dest ~= nil and guided == dest.id, tostring(guided))
		check("Join far away → toast names the client and where it is", has("Route to PixelForge (Business City) started") ~= nil and has(Action.message("TOO_FAR")) == nil)
	elseif STATE == "rich" then
		check("abroad trip by flight", has("Field rep + engineer → Orbit Systems · pilot visit · flight + 2 nights") ~= nil)
		check("hosted pilot at the guest house", has("Mosaic Worlds team at your guest house") ~= nil)
	elseif STATE == "garage" then
		check("garage: every client is a later stage or needs a model", nAcc == 0 and has("Accounts (") == nil)
		check("garage: needs text asks for a first release (no 'best live model: 0')", has("Needs reliability 24 · release a model first") ~= nil and has("your best live model: 0") == nil)
	end

	------------------------------------------------------------------ Money (ledger)
	openTab("money")
	local dayKey = tostring(Ops.day(e))
	local entry = e.ledger[dayKey]
	local income, costs, inTotal, outTotal = EmpireApp.ledgerDay(entry)
	local sumIn, sumOut = 0, 0
	if entry then
		for _, v in entry.i or {} do sumIn += v end
		for _, v in entry.o or {} do sumOut += v end
	end
	check("ledgerDay totals = sum of the categories", inTotal == sumIn and outTotal == sumOut, inTotal .. "/" .. sumIn)
	check("ledgerDay drops zero lines and sorts by size", (function()
		for i = 2, #costs do if costs[i].value > costs[i - 1].value then return false end end
		for _, l in income do if l.value <= 0 then return false end end
		return true
	end)())
	check("Today card title", has("Today · day " .. dayKey) ~= nil)
	local net = inTotal - outTotal
	check("net today shown", has("Net today  " .. (if net > 0 then "+" else "") .. Ops.money(net)) ~= nil, Ops.money(net))
	if STATE == "mid" then
		check("today: wages line", has("-$31,600") ~= nil and has("Wages") ~= nil)
		check("today: retainers line", has("Client retainers") ~= nil and has("+$26,600") ~= nil)
		check("4 company days in the table (7..10, today marked)", has("Day 7") ~= nil and has("Day 9") ~= nil and has("Day 10 (today)") ~= nil)
		check("day 6 is not replicated (4 of 7 days)", has("Day 6") == nil and State.snapshot.data.empire.ledger["6"] == nil and e.ledger["6"] ~= nil)
		local _, _, a8, b8 = EmpireApp.ledgerDay(e.ledger["8"])
		check("day 8 net (office move) shown negative", has("-" .. Ops.money(b8 - a8)) ~= nil, Ops.money(a8 - b8))
		check("running rates per game day", has("Running now, per game day") ~= nil and has("/day") ~= nil)
		-- day picker: the category breakdown of an earlier replicated day
		local picker = find("DayPicker")
		check("day picker lists the 4 replicated days (Day 7 .. Today)", picker and button("Day 7", picker) and button("Day 9", picker) and button("Today", picker) and button("Day 6", picker) == nil)
		click(picker and button("Day 8", picker))
		ui.push()
		local inc8, out8, a8b, b8b = EmpireApp.ledgerDay(e.ledger["8"])
		check("Day 8 picked: title, office move line and net of that day", has("Every dollar of company day 8, by category.") ~= nil and has("Office move") ~= nil and has("-$100,000") ~= nil
			and has("Net day 8  " .. Ops.money(a8b - b8b)) ~= nil, Ops.money(a8b - b8b))
		click(picker and button("Today", picker))
		ui.push()
		check("Today picked again", has("Today · day " .. dayKey) ~= nil and has("Office move") == nil)
		-- rows are updated in place: the ledger and the live rates move on every snapshot, no GuiObject is created
		local created = 0
		local conn = pg.DescendantAdded:Connect(function(x) if x:IsA("GuiObject") then created += 1 end end)
		for i = 1, 6 do
			e.ledger[dayKey].i.market += 111
			e.ledger[dayKey].o.wages += 37
			s.live.revenue += 0.5
			ui.push()
		end
		conn:Disconnect()
		check("Money tab: no GuiObject churn while the ledger and rates move", created == 0, created)
		check("Money tab: today's income total follows the ledger", has("+" .. Ops.money(inTotal + 666)) ~= nil, Ops.money(inTotal + 666))
	elseif STATE == "garage" then
		check("garage: empty day says so", has("Nothing booked yet today.") ~= nil)
		check("garage: no day table yet", has("Income") ~= nil and has("Day 1 (today)") == nil)
		check("garage: no day picker with one day", find("DayPicker") == nil)
	end
	check("ledgerDay drops zero and negative lines", (function()
		local inc, out, a, b = EmpireApp.ledgerDay({ i = { market = 0, b2b = 500, pilot = -3 }, o = { wages = 0 } })
		return #inc == 1 and inc[1].cat == "b2b" and #out == 0 and a == 500 and b == 0
	end)())
	check("category labels", EmpireApp.categoryLabel("b2b", false) == "Client retainers" and EmpireApp.categoryLabel("market", true) == "Serving & power" and EmpireApp.categoryLabel("newthing", true) == "Newthing")

	------------------------------------------------------------------ Settings
	openTab("settings")
	local function seg(label)
		for _, x in pg:GetDescendants() do
			if x:IsA("TextButton") and visible(x) and x.Text == label and x.Parent and x.Parent:FindFirstChildOfClass("UIListLayout") and x.Parent:FindFirstChildOfClass("UIPadding") then return x end
		end
		return nil
	end
	if STATE == "mid" then
		click(seg("55 %"))
		local p = lastCall("EmpireAction")
		check("wage budget 55 % → EmpireAction {hrBudget, 0.55}", p and p.action == "hrBudget" and math.abs((p.budget or 0) - 0.55) < 1e-9 and e.hr.budget == 0.55)
		check("HR status line explains why HR waits (Save mode at half the desks)", has("Save mode: HR stops at half the desks until the move.") ~= nil)
		click(seg("Off"))
		p = lastCall("EmpireAction")
		check("HR auto Off → EmpireAction {hrAuto, false}", p and p.action == "hrAuto" and p.on == false and e.hr.auto == false)
		ui.push()
		check("HR status says automatic hiring is off", has("Off: hire by hand in Team.") ~= nil)
		-- Save mode switch: the second "Off" on the page (row "Save for the next office")
		local saveRow
		for _, x in pg:GetDescendants() do if x:IsA("TextLabel") and x.Text == "Save for the next office" then saveRow = x.Parent end end
		click(saveRow and button("Off", saveRow))
		p = lastCall("EmpireAction")
		check("Save mode Off → EmpireAction {saveMode, off}", p and p.action == "saveMode" and p.mode == "off" and e.saveMode == "off")
		-- night shift for ML Engineers: both departments (engineering, training)
		local engRow = find("Night_engineer")
		local before = #ui.calls
		click(engRow and button("On", engRow))
		M.settle(1)
		-- integrate (apps request 5): ONE atomic call {nightShift, role, on} instead of one call per department
		local roleCalls, deptCalls, roleOn = 0, 0, nil
		for i = before + 1, #ui.calls do
			local c = ui.calls[i]
			if c.name == "EmpireAction" and c.payload.action == "nightShift" then
				if c.payload.role ~= nil then roleCalls += 1; roleOn = c.payload.role == "engineer" and c.payload.on else deptCalls += 1 end
			end
		end
		check("night shift On → one nightShift {role = engineer, on} call; engineering + training on", roleCalls == 1 and deptCalls == 0 and roleOn == true and e.nightShift.engineering == true and e.nightShift.training == true, roleCalls .. "/" .. deptCalls)
		-- a role half on (older save / failed call): label says so in warn colour, neither side highlighted
		e.nightShift = { engineering = true }
		ui.push()
		local engSub = has("on in 1 of 2 departments", engRow)
		check("night shift half on: 'on in 1 of 2 departments'", engSub ~= nil)
		local onBtn, offBtn = button("On", engRow), button("Off", engRow)
		check("night shift half on: neither On nor Off highlighted", onBtn and offBtn and onBtn.BackgroundTransparency == 1 and offBtn.BackgroundTransparency == 1)
		-- apprentices
		check("apprentice list: day and skill from empire.apprentices", has("Jonas Weber") ~= nil and has("day 3 of 9") ~= nil and has("skill 3 (max)") ~= nil)
		check("Training Lead on duty while apprentices train", has("Training Lead on duty ($900/day)") ~= nil)
		local money0 = s.data.money
		local nAppr = Ops.apprenticeCount(e)
		click(find("Apprentice_researcher"))
		p = lastCall("HireEmployee")
		check("apprentice hire → HireEmployee {researcher, apprentice=true}", p and p.roleId == "researcher" and p.apprentice == true)
		check("server: apprentice added at half the fee", Ops.apprenticeCount(e) == nAppr + 1 and s.data.money == money0 - 500, s.data.money - money0)
		-- company jet: disabled before the Innovation Campus; the server says OFFICE
		local jet = find("BuyJet")
		local cash0 = s.data.money
		s.data.money = 2000000 -- enough cash: the stage alone must keep the button disabled
		ui.push()
		check("jet button needs the Innovation Campus (even with $2M cash)", jet and jet.Text == "Needs the Innovation Campus" and jet:GetAttribute("Disabled") == true)
		s.data.money = cash0
		ui.push()
		local ok, res = Action.call("EmpireAction", { action = "buyJet" })
		M.settle(0.3)
		check("direct buyJet → OFFICE with its English text", not ok and res.err == "OFFICE" and has(Action.message("OFFICE")) ~= nil)
	elseif STATE == "rich" then
		local jet = find("BuyJet")
		check("rich: Buy company jet · $900,000", jet and jet.Text == "Buy company jet · $900,000" and jet:GetAttribute("Disabled") ~= true)
		check("rich: jet text no longer names a stage requirement", has("Needs the Innovation Campus") == nil and has("once you buy it") ~= nil)
		local money0 = s.data.money
		click(jet)
		M.settle(0.3)
		local p = lastCall("EmpireAction")
		check("Buy → EmpireAction {buyJet}; server owns the jet", p and p.action == "buyJet" and e.jet == true and s.data.money == money0 - 900000)
		ui.push()
		check("jet card shows the owned state with its running cost", has("Owned. Parked in the airport hangar with 2 company pilots · running $8,500/day") ~= nil and find("BuyJet").Text == "Owned")
		local ok, res = Action.call("EmpireAction", { action = "buyJet" })
		check("second buy → OWNED", not ok and res.err == "OWNED")
	elseif STATE == "garage" then
		check("garage: night shift starts at the Startup Campus", has("Night shifts start at the Startup Campus.") ~= nil)
		check("garage: apprentices start at the Startup Campus", has("Apprentices start at the Startup Campus with a Training Lead.") ~= nil and find("Apprentice_researcher") == nil)
		check("garage: Save mode waits for the first client", has("Starts after your first client has signed.") ~= nil)
		local ok, res = Action.call("HireEmployee", { roleId = "engineer", apprentice = true })
		check("garage: apprentice hire refused (OFFICE)", not ok and res.err == "OFFICE")
		check("garage: HR waits for the first live model", has("HR starts hiring once your first model is live") ~= nil)
	end

	------------------------------------------------------------------ error texts (CORE_SPEC 11.8)
	local generic = Action.message("NOPE_UNKNOWN")
	local missing = {}
	for _, code in { "FIRST_CLIENT", "LINE_LIMIT", "REFINE_LIMIT", "MAX_LEVEL", "PREREQUISITE", "NO_POINTS", "OWNED", "OFFICE", "NO_MONEY", "TOO_FAR", "NO_MEETING", "STAFF_FULL" } do
		if Action.message(code) == generic then table.insert(missing, code) end
	end
	check("every CORE_SPEC 11.8 error code has an English text", #missing == 0, table.concat(missing, ","))

	------------------------------------------------------------------ Hardware app: servers really work
	ui.Computer.open("compute")
	M.settle(0.4)
	ui.push()
	local data = State.snapshot.data
	local live = State.snapshot.live
	local sp = ComputeApp.split(data, live)
	local thermal = HardwareConfig.thermal(data.empire, live.compute.units)
	check("split parts add up to the fleet", math.abs(sp.clients + sp.serving + sp.free + sp.offline - sp.total) < 1e-6, string.format("%.3f vs %.3f", sp.clients + sp.serving + sp.free + sp.offline, sp.total))
	check("split: business clients = reserved compute", math.abs(sp.clients - math.min(live.compute.reserved, (live.compute.units - live.compute.lost) * thermal)) < 1e-6)
	check("split: offline = faulty units x thermal", math.abs(sp.offline - live.compute.lost * thermal) < 1e-6)
	local fleet = M.require(RS.Shared.ModelMath).fleet(data.gpus)
	local expectShare = math.max(0.3, 1 - (data.empire.deals.reserved or 0) / fleet.throughput)
	check("training share = max(0.3, 1 - reserved / throughput)", math.abs(ComputeApp.trainingShare(data) - expectShare) < 1e-6, ComputeApp.trainingShare(data))
	local slotsShown = 0
	local rack = find("Rack")
	for _, x in rack:GetChildren() do if x:IsA("Frame") and x.Visible then slotsShown += 1 end end
	check("rack shows the GPU slots of the stage (" .. HardwareConfig.slots(data.empire) .. ")", slotsShown == HardwareConfig.slots(data.empire), slotsShown)
	check("extra users of one GPU from CompanyOps.capacity", ComputeApp.extraUsers(data, "workstation") >= 0)
	if STATE == "mid" then
		check("fault line with IT countdown", has("Rack R2 fault · Workstation GPU · IT on the way · ~40 s") ~= nil)
		check("faulty rack slot marked", rack:FindFirstChild("Slot2") and rack.Slot2:FindFirstChildOfClass("TextLabel").Text == "!")
		check("training speed line", has(string.format("Training runs at %d %% speed", math.floor(expectShare * 100 + 0.5))) ~= nil)
		check("running power cost per game day", has("Power while serving " .. Ops.money(fleet.throughput * 0.025 * 1200)) ~= nil)
		check("studio split text (corefix #10)", has("More training compute leaves less capacity for studio projects.") ~= nil and has("projects and business customers") == nil)
	elseif STATE == "rich" then
		check("waitlist line", find("Waitlist") and string.find(find("Waitlist").Text, "users waiting", 1, true) ~= nil, find("Waitlist") and find("Waitlist").Text)
		check("two faults listed", has("Rack R5 fault") ~= nil and has("Rack R22 fault") ~= nil)
	elseif STATE == "garage" then
		check("garage: servers idle", has("Servers idle") ~= nil and has("the garage has no IT desk") ~= nil)
	end
end

setfenv(body, M.envFor(nil))
local ok, res = M.runMain(body, { timeout = 900 })
if not ok then failc += 1; print("FAIL  body crashed: " .. tostring(res)) end
if M.stats.errors > 0 then failc += 1; print("FAIL  background errors: " .. M.stats.errors) end
print(string.format("apps_ui_%s: %d passed, %d failed", STATE, pass, failc))
