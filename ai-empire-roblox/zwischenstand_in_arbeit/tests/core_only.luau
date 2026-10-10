--!nocheck
-- Headless test of CoreDesign alone (lift shaft, landings, cabin, stairs, head house, nav nodes).
-- Run: tests/core_only.sh   (regenerates harness/.gen_core, runs this, renders out/core/*.png)
-- or:  tools/luau tests/core_only.luau -a [--dump]   (exit code 1 on any failed assertion)
-- Prints "@@P {json}" per part with --dump (building-local CFrames) for tests/core_render.py.
local M = require("../harness/mock")
local manifest = require("../harness/.gen_core/manifest")
local sources = require("../harness/.gen_core/sources")
M.loadTree(manifest, sources)
local G = M.G
local game = M.game

local args = { ... }
local DUMP = table.find(args, "--dump") ~= nil

local fails, checks = 0, 0
local function check(name, ok, detail)
	checks += 1
	if not ok then
		fails += 1
		print("FAIL  " .. name .. (if detail then "  -- " .. tostring(detail) else ""))
	end
end

local function body()
	local CFrame, Vector3, Color3, Instance = G.CFrame, G.Vector3, G.Color3, G.Instance
	local RS = game:GetService("ReplicatedStorage")
	local SSS = game:GetService("ServerScriptService")
	local Plan = M.require(RS.Shared.Config.BuildingPlan)
	local Core = M.require(SSS.Server.Services.CoreDesign)

	local function newOffice(tier)
		local office = Instance.new("Model")
		office.Name = "Office"
		local folders = {}
		for _, n in { "Structure", "Facade", "Site", "Core", "Lift", "Walls", "Doors", "Rooms", "Circulation", "Cameras", "Navigation" } do
			local f = Instance.new("Folder")
			f.Name = n
			f.Parent = office
			folders[n] = f
		end
		return office, folders
	end

	local function build(tier, cf)
		local office, folders = newOffice(tier)
		local res = Core.build({ office = office, cf = cf, tier = tier, floors = Plan.floors(tier), owner = 1001, accent = Color3.fromRGB(80, 170, 200), company = "Nimbus Labs", folders = folders })
		return office, folders, res
	end

	-- oriented box helpers (building-local, cf = identity unless stated)
	local function corners(p, cf)
		local c = cf:ToObjectSpace(p.CFrame)
		local s = p.Size / 2
		local out = {}
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					table.insert(out, c * Vector3.new(sx * s.X, sy * s.Y, sz * s.Z))
				end
			end
		end
		return out
	end
	local function aabb(p, cf)
		local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, v in corners(p, cf or CFrame.new()) do
			lo, hi = lo:Min(v), hi:Max(v)
		end
		return lo, hi
	end
	local function overlaps(lo, hi, blo, bhi, eps)
		eps = eps or 1e-6
		return lo.X < bhi.X - eps and hi.X > blo.X + eps and lo.Y < bhi.Y - eps and hi.Y > blo.Y + eps and lo.Z < bhi.Z - eps and hi.Z > blo.Z + eps
	end
	local function parts(root)
		local out = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end
	local function near(a, b, eps)
		return math.abs(a - b) <= (eps or 1e-4)
	end

	local summary = {}
	for tier = 1, 4 do
		local cf = CFrame.new()
		local office, folders, res = build(tier, cf)
		local roof = Plan.roofLevel(tier)
		local all = parts(office)
		local lights = 0
		for _, d in office:GetDescendants() do
			if d:IsA("Light") then
				lights += 1
			end
		end
		local counts = { Core = #parts(folders.Core), Lift = #parts(folders.Lift), Navigation = #parts(folders.Navigation) }
		table.insert(summary, string.format("tier %d: parts %d (Core %d, Lift %d, Navigation %d), lights %d, stops %d, stair levels %d", tier, #all, counts.Core, counts.Lift, counts.Navigation, lights, #Plan.liftStops(tier), roof + 1))
		if tier == 4 then
			check("tier 4 part budget <= 900", #all <= 900, #all)
		end

		-- generic part sanity
		for _, p in all do
			check("anchored " .. p:GetFullName(), p.Anchored)
			check("min size " .. p:GetFullName(), math.min(p.Size.X, p.Size.Y, p.Size.Z) >= 0.05 - 1e-9, tostring(p.Size))
			if math.min(p.Size.X, p.Size.Y, p.Size.Z) < 1 and p.Transparency < 1 and p.CanCollide then
				-- thin collidable parts must be structural (named) - list them for review
				if not (p.Name:match("^Shaft") or p.Name:match("^Cabin") or p.Name:match("^Door") or p.Name:match("^Stair") or p.Name:match("^Portal") or p.Name:match("^HeadHouse") or p.Name == "Sill") then
					check("thin collidable part is structural " .. p:GetFullName(), false, tostring(p.Size))
				end
			end
		end

		-- ------------------------------------------------------------------ cabin
		local cabin = res.cabin
		check("cabin is LiftCabin", cabin and cabin.Name == "LiftCabin" and cabin.Parent == folders.Lift)
		check("cabin atomic", cabin.ModelStreamingMode == G.Enum.ModelStreamingMode.Atomic)
		check("cabin CurrentLevel=0", cabin:GetAttribute("CurrentLevel") == 0)
		local floor = cabin:FindFirstChild("CabinFloor")
		check("cabin primary part", cabin.PrimaryPart == floor)
		check("cabin floor size", floor.Size == Vector3.new(12, 0.5, 12), tostring(floor.Size))
		check("cabin floor centre", (floor.Position - Vector3.new(0, -0.25, 60.8)).Magnitude < 1e-6, tostring(floor.Position))
		for _, n in { "CabinPanel", "CabinDisplay", "CabinDoorL", "CabinDoorR" } do
			check("cabin has " .. n, cabin:FindFirstChild(n) ~= nil)
		end
		local cp = cabin:FindFirstChild("CabinPanel"):FindFirstChildOfClass("ProximityPrompt")
		check("panel prompt", cp and cp.ActionText == "Choose floor" and cp.ObjectText == "Lift" and cp.MaxActivationDistance == 6 and cp.RequiresLineOfSight == false and cp:GetAttribute("CampusAction") == "liftPanel" and cp:GetAttribute("Public") == true)
		local disp = cabin:FindFirstChild("CabinDisplay"):FindFirstChild("Display")
		check("cabin display labels", disp and disp:FindFirstChild("Level") and disp:FindFirstChild("Arrow") and disp:FindFirstChild("Status"))
		check("cabin display faces +Z", (cabin.CabinDisplay.CFrame.LookVector - Vector3.new(0, 0, 1)).Magnitude < 1e-6, tostring(cabin.CabinDisplay.CFrame.LookVector))
		check("cabin panel faces +Z", (cabin.CabinPanel.CFrame.LookVector - Vector3.new(0, 0, 1)).Magnitude < 1e-6)
		local hasLight = false
		for _, d in cabin:GetDescendants() do
			if d:IsA("PointLight") or d:IsA("SurfaceLight") then
				hasLight = true
			end
		end
		check("cabin light", hasLight)
		-- envelope and clear volume
		local envLo, envHi = Vector3.new(-6, -0.5, 54.8), Vector3.new(6, 11, 66.8)
		local clearLo, clearHi = Vector3.new(-5.5, 0.05, 55.41), Vector3.new(5.5, 10, 66.41)
		local cabLo, cabHi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, p in parts(cabin) do
			local lo, hi = aabb(p)
			check("cabin part in envelope " .. p.Name, lo.X >= envLo.X - 1e-6 and lo.Y >= envLo.Y - 1e-6 and lo.Z >= envLo.Z - 1e-6 and hi.X <= envHi.X + 1e-6 and hi.Y <= envHi.Y + 1e-6 and hi.Z <= envHi.Z + 1e-6, tostring(lo) .. " .. " .. tostring(hi))
			check("cabin part outside clear volume " .. p.Name, not overlaps(lo, hi, clearLo, clearHi), tostring(lo) .. " .. " .. tostring(hi))
			cabLo, cabHi = cabLo:Min(lo), cabHi:Max(hi)
		end
		-- leaves: offsets relative to CabinFloor, open positions clear the opening and stay near the cabin
		for _, n in { "CabinDoorL", "CabinDoorR" } do
			local leaf = cabin[n]
			local co, oo = leaf:GetAttribute("ClosedOffset"), leaf:GetAttribute("OpenOffset")
			check(n .. " offsets", M.typeof(co) == "CFrame" and M.typeof(oo) == "CFrame")
			check(n .. " closed offset reproduces leaf", (floor.CFrame * co).Position:FuzzyEq(leaf.Position, 1e-5))
			check(n .. " size", leaf.Size == Vector3.new(3.05, 10, 0.3))
			local openPos = (floor.CFrame * oo).Position
			local slide = math.abs(openPos.X - leaf.Position.X)
			check(n .. " slides 3.0 outward", near(slide, 3.0) and math.sign(openPos.X) == math.sign(leaf.Position.X))
			check(n .. " open clears opening", math.abs(openPos.X) - 1.525 >= 3 - 1e-6)
			cabLo = cabLo:Min(Vector3.new(openPos.X - 1.525, openPos.Y - 5, openPos.Z - 0.15))
			cabHi = cabHi:Max(Vector3.new(openPos.X + 1.525, openPos.Y + 5, openPos.Z + 0.15))
		end
		local dL, dR = cabin.CabinDoorL, cabin.CabinDoorR
		check("cabin leaves closed fill x[-3,3]", near(dL.Position.X - 1.525, -3.05) and near(dL.Position.X + 1.525, 0) and near(dR.Position.X - 1.525, 0) and near(dR.Position.X + 1.525, 3.05))
		-- shaft clearance (inner faces x=+-6.75, z 54.25 / 67.75) incl. open leaves
		local gap = math.min(6.75 - cabHi.X, cabLo.X + 6.75, cabLo.Z - 54.25, 67.75 - cabHi.Z)
		check("cabin >= 0.5 from shaft inner faces", gap >= 0.5 - 1e-6, gap)
		if tier == 4 then
			print(string.format("cabin extents incl. open leaves: x[%.2f, %.2f] z[%.2f, %.2f]  min gap to shaft %.2f", cabLo.X, cabHi.X, cabLo.Z, cabHi.Z, gap))
		end
		-- swept volume (B1 .. roof) must not hit any non-cabin part
		local sweepLo = Vector3.new(cabLo.X, Plan.levelY(-1) - 0.5, cabLo.Z)
		local sweepHi = Vector3.new(cabHi.X, Plan.levelY(roof) + 11, cabHi.Z)
		for _, p in all do
			if not p:IsDescendantOf(cabin) and p.Name ~= "LiftGuide" then
				local lo, hi = aabb(p)
				check("cabin sweep free of " .. p:GetFullName(), not overlaps(lo, hi, sweepLo, sweepHi), tostring(lo) .. ".." .. tostring(hi))
			end
		end
		local topY = Plan.levelY(roof) + 13
		check("cabin top below shaft top at roof stop", Plan.levelY(roof) + cabHi.Y < topY)

		-- guide
		local guide = res.guide
		check("guide", guide.Name == "LiftGuide" and guide.Parent == folders.Lift and guide.Size == Vector3.new(1, 1, 1) and guide.CanCollide == false and guide.Transparency == 1 and guide.Position:FuzzyEq(Vector3.new(0, Plan.levelY(-1), 60.8), 1e-6))

		-- ------------------------------------------------------------------ landings + shaft
		local shaftParts = 0
		for _, p in parts(folders.Core.LiftShaft) do
			check("shaft attr " .. p.Name, p:GetAttribute("LiftShaft") == true)
			shaftParts += 1
		end
		for _, stop in Plan.liftStops(tier) do
			local L = stop.level
			local y = Plan.levelY(L)
			local m = res.landings[L]
			check("landing model L" .. L, m and m.Name == "Landing_" .. L and m.Parent == folders.Lift and m:GetAttribute("LiftStop") == L and m:GetAttribute("LevelLabel") == Plan.levelLabel(tier, L))
			for _, n in { "DoorL", "DoorR", "CallButton", "Indicator", "WaitMarker", "Sill" } do
				check("landing L" .. L .. " has " .. n, m:FindFirstChild(n) ~= nil)
			end
			local l, r = m.DoorL, m.DoorR
			for _, leaf in { l, r } do
				local c, o = leaf:GetAttribute("ClosedCFrame"), leaf:GetAttribute("OpenCFrame")
				check("leaf cframes L" .. L, M.typeof(c) == "CFrame" and M.typeof(o) == "CFrame" and c.Position:FuzzyEq(leaf.Position, 1e-6))
				check("leaf LiftShaft L" .. L, leaf:GetAttribute("LiftShaft") == true)
				check("leaf size L" .. L, leaf.Size == Vector3.new(3.05, 10, 0.3))
				check("leaf in front of wall face L" .. L, near(leaf.Position.Z + 0.15, 53.75))
				check("leaf slides 3 outward L" .. L, near(math.abs(o.Position.X) - math.abs(c.Position.X), 3.0))
				check("leaf open clears opening L" .. L, math.abs(o.Position.X) - 1.525 >= 3 - 1e-6)
				check("leaf bottom on sill L" .. L, near(leaf.Position.Y - 5, y + 0.01))
			end
			check("landing leaves closed fill [-3,3] L" .. L, near(l.Position.X - 1.525, -3.05) and near(l.Position.X + 1.525, 0) and near(r.Position.X - 1.525, 0) and near(r.Position.X + 1.525, 3.05))
			-- the open leaves are hidden behind the portal cladding/jambs (in front of them, -Z)
			local portal = folders.Core:FindFirstChild("LiftPortal_" .. L)
			check("portal L" .. L, portal ~= nil)
			for _, leaf in { l, r } do
				local o = leaf:GetAttribute("OpenCFrame").Position
				-- sample the open leaf's front face; every sample must be behind a portal part
				local rects = {}
				for _, pp in parts(portal) do
					local lo, hi = aabb(pp)
					if hi.Z <= o.Z - 0.15 + 1e-6 then
						table.insert(rects, { lo, hi })
					end
				end
				local covered, total = 0, 0
				for sx = 0, 30 do
					for sy = 0, 20 do
						local px, py = o.X - 1.525 + 3.05 * sx / 30, o.Y - 5 + 10 * sy / 20
						total += 1
						for _, rc in rects do
							if px >= rc[1].X - 1e-6 and px <= rc[2].X + 1e-6 and py >= rc[1].Y - 1e-6 and py <= rc[2].Y + 1e-6 then
								covered += 1
								break
							end
						end
					end
				end
				covered = covered / total * 3.05
				check("open leaf hidden behind portal L" .. L, covered >= 3.05 - 1e-6, covered)
			end
			-- opening in the front wall: nothing of the shaft front inside x[-3,3], y[L, L+10]
			for _, p in parts(folders.Core.LiftShaft) do
				local lo, hi = aabb(p)
				check("opening clear L" .. L .. " " .. p.Name, not overlaps(lo, hi, Vector3.new(-3, y, 53.75), Vector3.new(3, y + 10, 54.25)))
			end
			local sill = m.Sill
			local slo, shi = aabb(sill)
			check("sill z range L" .. L, near(slo.Z, 53.4) and near(shi.Z, 54.7) and shi.Z < 54.8 and sill:GetAttribute("LiftShaft") == true)
			check("sill top flush L" .. L, near(shi.Y, y + 0.01))
			local cb = m.CallButton
			check("call button pos L" .. L, near(cb.Position.X, 4.6) and near(cb.Position.Y, y + 3.6))
			local q = cb:FindFirstChildOfClass("ProximityPrompt")
			check("call prompt L" .. L, q and q.ActionText == "Call lift" and q.ObjectText == "Lift" and q.MaxActivationDistance == 7 and q.RequiresLineOfSight == false and q.HoldDuration == 0 and q:GetAttribute("CampusAction") == "liftCall" and q:GetAttribute("Value") == L and q:GetAttribute("Public") == true)
			local ind = m.Indicator
			local g = ind:FindFirstChild("Display")
			check("indicator L" .. L, g and g:IsA("SurfaceGui") and g:FindFirstChild("Level") and g:FindFirstChild("Arrow") and g:FindFirstChild("Status") and g.Status.Text == Plan.floorTitle(tier, L) and near(ind.Position.Y, y + 11.2) and (ind.CFrame.LookVector - Vector3.new(0, 0, -1)).Magnitude < 1e-6 and g.LightInfluence <= 0.2)
			local w = m.WaitMarker
			check("wait marker L" .. L, w.Position:FuzzyEq(Plan.liftWaitPoint(L, 1), 1e-6) and w:GetAttribute("LiftStop") == L and w.CanCollide == false and w.Transparency == 1 and w.Size == Vector3.new(1, 1, 1))
			-- nav nodes
			local wn = folders.Navigation:FindFirstChild(string.format("L%d_LiftWait", L))
			local sn = folders.Navigation:FindFirstChild(string.format("L%d_Stair", L))
			check("nav nodes L" .. L, wn and sn and wn:GetAttribute("NavigationNode") == "Elevator" and sn:GetAttribute("NavigationNode") == "Stairs" and wn:GetAttribute("Floor") == L and sn:GetAttribute("Floor") == L and near(wn.Position.Y, y + 2.8) and near(sn.Position.Y, y + 2.8) and table.find(M.getTags(wn), "NavigationNode") ~= nil)
		end
		-- the front wall above/below openings is continuous: spandrel tops / bottoms chain correctly
		do
			local spans = {}
			for _, p in parts(folders.Core.LiftShaft) do
				if p.Name == "ShaftSpandrel" then
					local lo, hi = aabb(p)
					table.insert(spans, { lo.Y, hi.Y })
				end
			end
			table.sort(spans, function(a, b)
				return a[1] < b[1]
			end)
			local stops = Plan.liftStops(tier)
			check("spandrel count", #spans == #stops + 1, #spans)
			for i, st in stops do
				check("spandrel below stop " .. st.level, near(spans[i][2], st.y - 0.17) and near(spans[i + 1][1], st.y + 10))
			end
			check("shaft top", near(spans[#spans][2], Plan.levelY(roof) + 13))
			check("shaft bottom = pit", near(spans[1][1], Plan.levelY(-1) - 5))
		end

		-- ------------------------------------------------------------------ stairs
		local stairs = folders.Core.Stair
		local flights = 0
		for level = -1, roof - 1 do
			local m = stairs:FindFirstChild("Stair_" .. level)
			check("stair level model " .. level, m ~= nil)
			local y0, y1 = Plan.levelY(level), Plan.levelY(level + 1)
			local mid = (y0 + y1) / 2
			local ramps, treads, nosings, rails = {}, 0, 0, {}
			for _, p in parts(m) do
				if p.Name == "StairRamp" then
					table.insert(ramps, p)
				elseif p.Name == "StairTread" then
					treads += 1
					check("tread decorative", p.CanCollide == false and p.CanQuery == false and p.CanTouch == false)
				elseif p.Name == "StairNosing" then
					nosings += 1
				elseif p.Name == "StairHandrail" then
					table.insert(rails, p)
				end
			end
			check("two ramps L" .. level, #ramps == 2)
			check("treads L" .. level, treads == (if level < 0 then 31 else 32), treads)
			check("nosings L" .. level, nosings == 32, nosings)
			check("rails L" .. level, #rails == 4, #rails)
			for _, ramp in ramps do
				flights += 1
				check("ramp invisible+collidable", ramp.Transparency == 1 and ramp.CanCollide == true)
				local isA = ramp.Position.X < -14.5
				local yA, zA, yB, zB
				if isA then
					yA, zA, yB, zB = y0, 60, mid, 75
				else
					yA, zA, yB, zB = mid, 75, y1, 60
				end
				-- top face end points
				local e1 = ramp.CFrame * Vector3.new(0, ramp.Size.Y / 2, ramp.Size.Z / 2)
				local e2 = ramp.CFrame * Vector3.new(0, ramp.Size.Y / 2, -ramp.Size.Z / 2)
				local lo1, hi1 = e1, e2
				if lo1.Z > hi1.Z then
					lo1, hi1 = hi1, lo1
				end
				-- expected lower-z and higher-z end
				local ez1y, ez2y = (if zA < zB then yA else yB), (if zA < zB then yB else yA)
				local err = math.max(math.abs(lo1.Z - 60), math.abs(lo1.Y - ez1y), math.abs(hi1.Z - 75), math.abs(hi1.Y - ez2y))
				check(string.format("ramp %s L%d end points (err %.5f)", if isA then "A" else "B", level, err), err < 0.05)
				if level == 2 or level == -1 then
					print(string.format("tier %d L%d flight %s: top surface z=%.4f y=%.4f  ->  z=%.4f y=%.4f   (expected y %.2f -> %.2f)", tier, level, if isA then "A" else "B", lo1.Z, lo1.Y, hi1.Z, hi1.Y, ez1y, ez2y))
				end
				-- never above the landings: every corner below the walking line (or the landing top beyond the ends)
				local worst = -math.huge
				for _, c in corners(ramp, CFrame.new()) do
					local lineY
					if c.Z <= 60 then
						lineY = ez1y
					elseif c.Z >= 75 then
						lineY = ez2y
					else
						lineY = ez1y + (c.Z - 60) * (ez2y - ez1y) / 15
					end
					worst = math.max(worst, c.Y - lineY)
				end
				check("ramp never above walking line/landing (" .. worst .. ")", worst <= 1e-4)
				-- treads: nosing edges lie on the walking line
				local lineAt = function(z)
					return ez1y + (z - 60) * (ez2y - ez1y) / 15
				end
				for _, p in parts(m) do
					if p.Name == "StairTread" and ((isA and p.Position.X < -14.5) or (not isA and p.Position.X > -14.5)) then
						local lo, hi = aabb(p)
						local noseZ = if isA then lo.Z else hi.Z
						check("tread nosing on walking line", math.abs(hi.Y - lineAt(noseZ)) < 1e-4, hi.Y - lineAt(noseZ))
						check("tread below walking line", hi.Y <= lineAt(if isA then hi.Z else lo.Z) + 1e-4)
					end
				end
				-- rails follow the slope at RAIL_H above the walking line
				for _, rail in rails do
					if (isA and rail.Position.X < -14.5) or (not isA and rail.Position.X > -14.5) then
						local r1 = rail.CFrame * Vector3.new(0, 0, rail.Size.Z / 2)
						local r2 = rail.CFrame * Vector3.new(0, 0, -rail.Size.Z / 2)
						check("rail follows slope", math.abs(r1.Y - lineAt(r1.Z) - 3.2) < 1e-4 and math.abs(r2.Y - lineAt(r2.Z) - 3.2) < 1e-4, (r1.Y - lineAt(r1.Z)) .. "," .. (r2.Y - lineAt(r2.Z)))
					end
				end
			end
			local landing = m:FindFirstChild("StairLanding")
			local llo, lhi = aabb(landing)
			check("mid landing L" .. level, near(lhi.Y, mid) and near(llo.Y, mid - 1) and near(llo.Z, 75) and near(lhi.Z, 79.5) and near(llo.X, -21.5) and near(lhi.X, -7.5))
			local soffitsOK = true
			for _, p in parts(m) do
				if p.Name == "StairSoffit" then
					-- soffit top face must stay below the walking line
					local isA = p.Position.X < -14.5
					local ez1y = if isA then y0 else y1
					local ez2y = mid
					for _, c in corners(p, CFrame.new()) do
						local z = math.clamp(c.Z, 60, 75)
						if c.Y > ez1y + (z - 60) * (ez2y - ez1y) / 15 - 0.5 + 1e-4 then
							soffitsOK = false
						end
					end
				end
			end
			check("soffits 0.5 below walking line L" .. level, soffitsOK)
		end
		check("flight count", flights == 2 * (roof + 1))
		check("divider", stairs.StairCore:FindFirstChild("StairDivider") ~= nil)
		for level = -1, roof do
			check("stair sign " .. level, stairs.StairCore:FindFirstChild("StairSign_" .. level) ~= nil)
		end

		-- head house
		local hh = folders.Core.HeadHouse
		local roofY = Plan.levelY(roof)
		local hlo, hhi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, p in parts(hh) do
			if p.Name == "HeadHouseRoof" then
				local lo, hi = aabb(p)
				hlo, hhi = hlo:Min(lo), hhi:Max(hi)
				check("head house roof height", near(lo.Y, roofY + 12) and near(hi.Y, roofY + 13))
			end
		end
		check("head house covers x[-22,22] z[42,80]", hlo.X <= -22 and hhi.X >= 22 and hlo.Z <= 42 and hhi.Z >= 80)

		-- dump (building-local) for rendering
		if DUMP and tier == 4 then
			for _, p in all do
				local c = { p.CFrame:GetComponents() }
				local col = p.Color
				print(string.format('@@P {"tier":%d,"path":"%s","name":"%s","size":[%.4f,%.4f,%.4f],"cf":[%s],"color":[%d,%d,%d],"t":%.3f,"collide":%s,"shape":"%s"}', tier, p:GetFullName(), p.Name, p.Size.X, p.Size.Y, p.Size.Z,
					table.concat((function()
						local s = {}
						for i = 1, 12 do
							s[i] = string.format("%.5f", c[i])
						end
						return s
					end)(), ","),
					math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5), p.Transparency, tostring(p.CanCollide), if p:IsA("Part") then tostring(p.Shape.Name) else "Block"))
			end
		end
	end

	-- frame consistency: a rotated, translated plot must give the same building-local geometry
	do
		local cfA = CFrame.new()
		local cfB = CFrame.new(-37.5, 11, 90) * CFrame.Angles(0, math.rad(37), 0)
		local oA, fA, rA = build(2, cfA)
		local oB, fB, rB = build(2, cfB)
		local pa, pb = parts(oA), parts(oB)
		check("frame: same part count", #pa == #pb)
		local maxErr = 0
		for i = 1, math.min(#pa, #pb) do
			local a = pa[i].CFrame
			local b = cfB:ToObjectSpace(pb[i].CFrame)
			local ca, cb = { a:GetComponents() }, { b:GetComponents() }
			for k = 1, 12 do
				maxErr = math.max(maxErr, math.abs(ca[k] - cb[k]))
			end
		end
		check("frame: local CFrames identical (max err " .. maxErr .. ")", maxErr < 1e-4)
		-- world attributes follow the plot
		local la, lb = rA.landings[0].DoorL, rB.landings[0].DoorL
		local ea = la:GetAttribute("OpenCFrame")
		local eb = cfB:ToObjectSpace(lb:GetAttribute("OpenCFrame"))
		check("frame: OpenCFrame is world space", ea.Position:FuzzyEq(eb.Position, 1e-4))
		local fl = rB.cabin.CabinFloor
		local leaf = rB.cabin.CabinDoorR
		check("frame: ClosedOffset relative to floor", (fl.CFrame * leaf:GetAttribute("ClosedOffset")).Position:FuzzyEq(leaf.Position, 1e-4))
		local open = fl.CFrame * leaf:GetAttribute("OpenOffset")
		local openLocal = cfB:ToObjectSpace(open).Position
		check("frame: OpenOffset slides along cabin x", near(openLocal.X, 1.525 + 3, 1e-4) and near(openLocal.Z, 54.97, 1e-4))
		check("frame: guide world position", rB.guide.Position:FuzzyEq((cfB * CFrame.new(0, -16, 60.8)).Position, 1e-4))
	end

	for _, s in summary do
		print(s)
	end
end
setfenv(body, M.envFor(nil))
local ok, res, status = M.runMain(body, { timeout = 60 })
if not ok then
	print("TEST CRASHED (" .. tostring(status) .. ")")
	print(tostring(res))
	fails += 1
end
print(string.format("core_only: %d checks, %d failed; mock warnings %d, stubs %s", checks, fails, M.stats.warnings, (function()
	local t = {}
	for k, v in M.stats.stubs do
		table.insert(t, k .. " x" .. v)
	end
	return table.concat(t, ", ")
end)()))
if fails > 0 then
	error("core_only FAILED", 0)
end
