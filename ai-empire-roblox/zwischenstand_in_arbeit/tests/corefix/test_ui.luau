--!nocheck
-- corefix package, client side: the Campus app (real client UI in the mock via tests/models/ui_setup.luau, wired to
-- the real server handlers) shows the Garage Lab honestly: one level in the building directory (no "R · Roof",
-- no "B1"), a garage text instead of the lift/reception directions, and no HQ-only cards (pavilion, founder
-- services, founder floor & roof, B1 garage, wellness rooms). After a move to the Startup Campus the full HQ
-- directory and cards come back (negative check: the HQ texts are not shown in the garage).
-- Run: cd tests/corefix && ../../tools/luau test_ui.luau -a .gen_corefix
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_corefix")
local M = require("../../harness/mock")
local setup = require("../models/ui_setup")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local function body()
	local ui = setup(M, GEN, "empty")
	local s = ui.session
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
	-- menu package (ONBOARDING_SPEC B9): campus/building ("Your headquarters", directory, getting around) is part of
	-- Team → Office now (campus/nil opens Team → Campus: cards & guests, stores & snacks)
	ui.Computer.open("campus", "building")
	M.settle(0.5)
	ui.push()
	local t = texts()
	check("garage: Campus app open on the building tab", has(t, "Building directory") ~= nil and has(t, "Garage Lab") ~= nil)
	local dir = has(t, "Garage lab · founder & first team")
	check("garage: directory lists the one level (G · Garage lab)", dir ~= nil and string.find(dir, "\n", 1, true) == nil, dir)
	check("garage: no 'R · Roof' / 'B1 · Roof' directory lines", has(t, "R  ·  Roof") == nil and has(t, "B1  ·  Roof") == nil)
	check("garage: getting-around text describes the garage (no lift)", has(t, "The Garage Lab has one level and no lift") ~= nil and has(t, "The lift stops at every level from B1") == nil)
	check("garage: HQ-only cards hidden (B1 garage, founder floor & roof, pavilion, founder services, wellness rooms)",
		has(t, "B1 · Garage & Data Hall") == nil and has(t, "Founder floor & roof terrace") == nil and has(t, "Wellness pavilion") == nil and has(t, "Founder services") == nil and has(t, "Use the rooms") == nil)
	-- the company moves into the Startup Campus
	s.data.empire.office = 3
	ui.push()
	M.settle(0.5)
	t = texts()
	check("HQ: directory lists every level from R to B1", has(t, "B1  ·  Garage, data hall") ~= nil and has(t, "G  ·  Reception, atrium") ~= nil)
	check("HQ: lift directions and the HQ cards are back", has(t, "The lift stops at every level from B1 to the roof") ~= nil and has(t, "B1 · Garage & Data Hall") ~= nil and has(t, "Wellness pavilion") ~= nil)
	check("HQ: no garage text", has(t, "The Garage Lab has one level") == nil)
end

setfenv(body, M.envFor(nil))
local ok, res = M.runMain(body, { timeout = 600 })
if not ok then failc += 1; print("FAIL  body crashed: " .. tostring(res)) end
if M.stats.errors > 0 then failc += 1; print("FAIL  background errors: " .. M.stats.errors) end
print(string.format("corefix ui tests: %d passed, %d failed", pass, failc))
