--!nocheck
-- Models package, client side: the Lab and Market apps built by the real client code in the mock (ui_setup.luau),
-- wired to the real server handlers. Per state (empty | rich | full): the apps build without errors, show the
-- product lines with their holders and the office's slots, the serving capacity / waitlist, refinements x/3, the
-- stat cap, the Lab level with its price, the Recommended price and the Auto price toggle; clicks reach the server
-- (Auto price on/off, manual price, Lab level, launch as a new line or as the next version of a line) and the
-- negative cases stay inert (disabled Lab button, LINE_LIMIT launch, refinement limit).
-- Run: cd tests/models && ../../tools/luau test_ui.luau -a .gen_models <empty|rich|full>
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_models")
local STATE = args[2] or "rich"
local M = require("../../harness/mock")
local setup = require("./ui_setup")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local P = print
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; P("FAIL  [" .. STATE .. "] " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local function body()
	local ui = setup(M, GEN, STATE)
	local s = ui.session
	local d = s.data
	local G = M.G

	local function visible(inst)
		local x = inst
		while x and x ~= ui.playerGui do
			if (x:IsA("GuiObject") and not x.Visible) or (x:IsA("ScreenGui") and not x.Enabled) then return false end
			x = x.Parent
		end
		return true
	end
	local function texts()
		local out = {}
		for _, x in ui.playerGui:GetDescendants() do
			if (x:IsA("TextLabel") or x:IsA("TextButton")) and visible(x) and x.Text ~= "" then table.insert(out, x.Text) end
		end
		return out
	end
	local function has(list, needle)
		for _, t in list do if string.find(t, needle, 1, true) then return t end end
		return nil
	end
	local function buttons(text)
		local out = {}
		for _, x in ui.playerGui:GetDescendants() do
			if x:IsA("TextButton") and visible(x) and string.find(x.Text, text, 1, true) == 1 then table.insert(out, x) end
		end
		return out
	end
	-- the button whose nearest enclosing card also shows `marker` (closest ancestor wins)
	local function buttonNear(text, marker)
		local best, bestLevel = nil, math.huge
		for _, b in buttons(text) do
			local x = b.Parent
			for level = 1, 6 do
				if not x or level >= bestLevel then break end
				local found = false
				for _, y in x:GetDescendants() do
					if y:IsA("TextLabel") and y.Text == marker then found = true; break end
				end
				if found then best, bestLevel = b, level; break end
				x = x.Parent
			end
		end
		return best
	end
	local function appTexts(name)
		local out = {}
		for _, x in ui.playerGui:GetDescendants() do
			if x:IsA("ScrollingFrame") and x.Name == name and visible(x) then
				for _, y in x:GetDescendants() do
					if (y:IsA("TextLabel") or y:IsA("TextButton")) and visible(y) and y.Text ~= "" then table.insert(out, y.Text) end
				end
			end
		end
		return out
	end
	local function click(b) if b then M.fire(b.Activated); M.settle(0.5) end end
	local function disabled(b) return b ~= nil and b:GetAttribute("Disabled") == true end

	------------------------------------------------------------------ Market
	ui.Computer.open("market")
	M.settle(0.5)
	ui.push()
	local t = texts()
	check("market: heading", has(t, "MARKET") ~= nil)
	local slots = ({ empty = "0 / 1 live at Garage Lab", rich = "2 / 3 live at Startup Campus", full = "3 / 3 live at Startup Campus" })[STATE]
	check("market: product lines with the office's slots", has(t, "Product lines · " .. slots) ~= nil, has(t, "Product lines"))
	for _, label in { "Consumer Chat", "Study App", "Developer API", "Business API" } do
		check("market: line row " .. label, has(t, label) ~= nil)
	end
	if STATE == "empty" then
		check("market: no serving row without live.capacity", has(t, "waiting") == nil and has(t, "Serving capacity") == nil)
		check("market: empty live models note", has(t, "No live models yet") ~= nil)
		check("market: business clients hint", has(t, "No business clients yet") ~= nil)
	else
		check("market: waitlist text", has(t, "12,400 waiting — buy GPUs") ~= nil, has(t, "waiting"))
		check("market: holder of the chat line", has(t, "Nova v2 · line v2") ~= nil, has(t, "Nova v2 ·"))
		check("market: successor note", has(t, "successor of Nova v1") ~= nil)
		check("market: auto-price note", has(t, "Auto: Servers 97 % full → Consumer Chat price raised to $10") ~= nil)
		check("market: manual-price note", has(t, "Manual price.") ~= nil)
		check("market: refinements x/3", has(t, "REFINE 1/3") ~= nil and has(t, "REFINE 2/3") ~= nil and has(t, "refined 1/3") ~= nil)
		check("market: stat cap shown", has(t, "Overall 61.5 / 99") ~= nil)
		local mt = appTexts("ScrollingFrame")
		check("market: money per game day", has(mt, "/day") ~= nil and has(mt, "/min") == nil, has(mt, "/min"))
		check("market: stays-live note on refinement", has(t, "keeps serving with the current version") ~= nil)
		check("market: business clients", has(t, "2 business clients · $18K/day in retainers") ~= nil, has(t, "business client"))
		if STATE == "rich" then
			check("market: free line text", has(t, "Free: 1 more line at this office") ~= nil)
		else
			check("market: no free line left", has(t, "Free:") == nil and has(t, "Business API") ~= nil)
		end
		-- Auto price toggle -> EmpireAction autoPrice (server)
		local manual = buttonNear("Manual", "Nova v2")
		check("market: Manual button on the Nova card", manual ~= nil)
		click(manual)
		check("market: Manual -> release.auto = false on the server", d.models.nova2.release.auto == false, tostring(d.models.nova2.release.auto))
		local auto = buttonNear("Auto price", "Nova v2")
		click(auto)
		check("market: Auto price -> release.auto = true", d.models.nova2.release.auto == true)
		-- manual API price step on the Coder card
		local before = d.models.coder.release.apiPrice
		click(buttonNear("+", "Coder v2"))
		check("market: API + changes the price, auto stays off", d.models.coder.release.apiPrice == before + 0.5 and d.models.coder.release.auto == false, d.models.coder.release.apiPrice)
		-- refinement limit: button disabled
		d.models.coder.iterations = 3
		ui.push()
		local refined = buttons("REFINED 3/3")[1]
		check("market: refinement limit shows REFINED 3/3, disabled", refined ~= nil and disabled(refined))
		local money = d.money
		click(refined)
		check("market: disabled refine does nothing", d.training == nil and d.money == money)
		d.models.coder.iterations = 1
		ui.push()
	end

	------------------------------------------------------------------ Lab (creator)
	ui.Computer.open("lab")
	M.settle(0.5)
	ui.push()
	t = texts()
	check("lab: MODEL LAB", has(t, "MODEL LAB") ~= nil)
	check("lab: product lines card", has(t, "Product lines · " .. slots) ~= nil, has(t, "Product lines"))
	check("lab: training slot note", has(t, "1 training slot") ~= nil)
	check("lab: stat cap note", has(t, "Every stat caps at 99") ~= nil)
	if STATE == "empty" then
		check("lab: Lab level 0", has(t, "Lab level 0") ~= nil)
		check("lab: Lab level locked behind the research tree", has(t, "Unlocks after the whole research tree") ~= nil)
		local buy = buttons("UPGRADE LAB")[1]
		check("lab: Upgrade disabled", buy ~= nil and disabled(buy))
		click(buy)
		check("lab: disabled Upgrade does nothing", (d.empire.labLevel or 0) == 0)
	else
		check("lab: Lab level 2 with the next price", has(t, "Lab level 2") ~= nil and has(t, "UPGRADE LAB · 364 RP + $15.4K") ~= nil, has(t, "UPGRADE LAB"))
		check("lab: estimate mentions the Lab bonus", has(t, "Lab level 2 adds +2 to each") ~= nil)
		check("lab: ready model with REFINE 1/3", has(t, "REFINE 1/3") ~= nil and has(t, "refined 0/3") ~= nil)
		local points, money = d.empire.points, d.money
		click(buttons("UPGRADE LAB")[1])
		check("lab: Upgrade -> EmpireAction labLevel (level 3, points and cash paid)", d.empire.labLevel == 3 and d.empire.points == points - 364 and d.money == money - 15360,
			tostring(d.empire.labLevel) .. " " .. tostring(points - d.empire.points) .. " " .. tostring(money - d.money))
		ui.push()
		check("lab: shows level 3 and the next price", has(texts(), "Lab level 3") ~= nil and has(texts(), "UPGRADE LAB · 492 RP + $24.6K") ~= nil, has(texts(), "UPGRADE LAB"))

		------------------------------------------------------------------ Lab (release card)
		ui.LabApp.openRelease("study")
		M.settle(3)
		ui.push()
		M.settle(1)
		t = texts()
		check("release: Recommended price computed", has(t, "Recommended: $") ~= nil, has(t, "Recommended"))
		check("release: Auto price preselected", has(t, "Auto price: the server sets the Recommended price") ~= nil)
		if STATE == "rich" then
			check("release: best line Study App is free", has(t, "Study App: a new product line (3 of 3 lines).") ~= nil, has(t, "Study App:"))
			local launch = buttons("LAUNCH STUDY")[1]
			check("release: launch button for a new line", launch ~= nil and not disabled(launch), launch and launch.Text)
			click(launch)
			M.settle(2)
			local m = d.models.study
			check("release: launched as Study App with auto price", m.status == "live" and m.release.target == "students" and m.release.auto == true and table.find({ 5, 10 }, m.release.subPrice) ~= nil and table.find({ 1, 2, 3, 4 }, m.release.apiPrice) ~= nil,
				m.status .. " " .. tostring(m.release and m.release.target))
			check("release: other lines untouched", d.models.nova2.status == "live" and d.models.coder.status == "live")
		else
			check("release: LINE_LIMIT line dimmed, best allowed line preselected (successor)", has(t, "Consumer Chat: successor of Nova v2. Becomes version 3 of the line") ~= nil, has(t, "Consumer Chat:"))
			-- negative: the full Study line
			click(buttons("Study")[1])
			t = texts()
			check("release: Study (no free line) -> NO FREE PRODUCT LINE", has(t, "NO FREE PRODUCT LINE") ~= nil and has(t, "All 3 product lines of Startup Campus are live") ~= nil)
			local blocked = buttons("NO FREE PRODUCT LINE")[1]
			check("release: launch disabled", disabled(blocked))
			click(blocked)
			check("release: disabled launch does nothing", d.models.study.status == "trained")
			click(buttons("Chat")[1])
			local launch = buttons("NEW VERSION · CHAT")[1]
			check("release: successor launch button", launch ~= nil and not disabled(launch), launch and launch.Text)
			local users = d.models.nova2.market.users.consumers
			click(launch)
			M.settle(2)
			local m = d.models.study
			check("release: successor live, predecessor retired with replacedBy", m.status == "live" and m.release.target == "general" and d.models.nova2.status == "retired" and d.models.nova2.replacedBy == "study",
				m.status .. " " .. d.models.nova2.status)
			check("release: 90 % of the users moved", math.abs((m.market.users.consumers or 0) - users * 0.9) < 1e-6, m.market.users.consumers)
			ui.Computer.open("market"); M.settle(0.5); ui.push()
			check("market after the release: Sage v1 holds the chat line as line v3", has(texts(), "Sage v1 · line v3") ~= nil, has(texts(), "Sage v1"))
		end
	end
end

setfenv(body, M.envFor(nil))
local ok, res = M.runMain(body, { timeout = 600 })
if not ok then failc += 1; P("FAIL  [" .. STATE .. "] body crashed: " .. tostring(res)) end
if M.stats.errors > 0 then failc += 1; P("FAIL  [" .. STATE .. "] background errors: " .. M.stats.errors) end
P(string.format("models_ui_%s: %d passed, %d failed", STATE, pass, failc))
