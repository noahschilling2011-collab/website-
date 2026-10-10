--!nocheck
-- Flight package: AircraftModel geometry and budgets in the headless mock - part budgets per LOD, real
-- proportions (manifest dimensions), the legacy 66-stud scale, wheels on the ground, decoration flags,
-- collide option, boarding attachments (DoorL1 found by the airport package's jet-bridge rule), the glazed
-- cockpit with seats inside the canopy, imported-mesh path (clone, anchored, attachments) and mesh=false,
-- the VIP helicopter (budget, rotors, skids on the ground).
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_flight && tools/luau tests/flight/test_aircraft.luau [-a .gen_dir]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_flight")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
M.loadTree(manifest, sources)
M.quiet = true
local G = M.G
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local function body()
	local Instance, Vector3, CFrame, Color3, Enum = G.Instance, G.Vector3, G.CFrame, G.Color3, G.Enum
	local RS = M.game.ReplicatedStorage
	local A = M.require(RS.Shared.AircraftModel)
	local folder = Instance.new("Folder"); folder.Parent = M.game.Workspace
	local function stats(m)
		local n, solid, badFlags, minY, lo, hi, bad = 0, 0, 0, math.huge, Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge), 0
		local root = m.PrimaryPart
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d ~= root then
				n += 1
				if d.CanCollide then solid += 1 elseif d.CanTouch or d.CanQuery then badFlags += 1 end
				if not d.Anchored then bad += 1 end
				local s = d.Size
				if s.X ~= s.X or s.X <= 0 or s.Y <= 0 or s.Z <= 0 then bad += 1 end
				if d.Transparency < 1 then
					local cf = root.CFrame:ToObjectSpace(d.CFrame)
					local wedge = d:IsA("WedgePart")
					for _, sx in { -1, 1 } do for _, sy in { -1, 1 } do for _, sz in { -1, 1 } do
						-- a WedgePart has no top-front edge (slope towards -Z): skip those two box corners
						if wedge and sy > 0 and sz < 0 then continue end
						local p = (cf * CFrame.new(sx * s.X / 2, sy * s.Y / 2, sz * s.Z / 2)).Position
						lo = Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z))
						hi = Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z))
					end end end
				end
			end
		end
		return { n = n, solid = solid, badFlags = badFlags, bad = bad, lo = lo, hi = hi, size = hi - lo }
	end
	local function near(a, b, tol) return math.abs(a - b) <= tol end
	local cf0 = CFrame.new(100, 24.25, 300) * CFrame.Angles(0, math.rad(37), 0)
	-- full LODs at real size
	local m320 = A.build(folder, cf0, { scale = A.REAL_SCALE, kind = "320", livery = Color3.fromRGB(24, 120, 128), name = "T320", airline = "Meridian Air" })
	local s320 = stats(m320)
	check("320 full <= 350 parts", s320.n <= 350 and s320.n >= 200, s320.n)
	check("320 proportions: length 134.2, span 127.9, height 42.1 (+-4%)", near(s320.size.Z, 134.18, 5.4) and near(s320.size.X, 127.85, 5.1) and near(s320.size.Y, 42.14, 1.7), tostring(s320.size))
	check("320 wheels on the ground (origin = tyre contact)", near(s320.lo.Y, 0, 0.15), s320.lo.Y)
	check("320 nose towards -Z", s320.lo.Z < -60 and s320.hi.Z > 60)
	check("320 decoration: no collision unless collide=true", s320.solid == 0, s320.solid)
	check("320 non-colliding parts never touch or query", s320.badFlags == 0, s320.badFlags)
	check("320 all parts anchored, valid sizes", s320.bad == 0, s320.bad)
	check("320 model name and kind", m320.Name == "T320" and m320:GetAttribute("AircraftKind") == "320" and m320:GetAttribute("AircraftLod") == "full")
	local m380 = A.build(folder, cf0 * CFrame.new(0, 0, 400), { scale = A.REAL_SCALE, kind = "380", name = "T380" })
	local s380 = stats(m380)
	check("380 full <= 360 parts", s380.n <= 360 and s380.n >= 200, s380.n)
	check("380 proportions: length 259.7, span 284.8, height 86 (+-4%)", near(s380.size.Z, 259.73, 10.4) and near(s380.size.X, 284.82, 11.4) and near(s380.size.Y, 86.04, 3.5), tostring(s380.size))
	check("380 on the ground", near(s380.lo.Y, 0, 0.2), s380.lo.Y)
	local engines = 0
	for _, d in m380:GetDescendants() do if d.Name == "Fan" then engines += 1 end end
	check("380 has four engines, 320 two", engines == 4 and (function() local e = 0; for _, d in m320:GetDescendants() do if d.Name == "Fan" then e += 1 end end; return e == 2 end)())
	-- LODs
	local med = stats(A.build(folder, cf0, { kind = "320", lod = "medium" }))
	local low = stats(A.build(folder, cf0, { kind = "320", lod = "low" }))
	check("medium LOD <= 80 parts", med.n <= 80, med.n)
	check("low LOD <= 30 parts", low.n <= 30, low.n)
	-- legacy scale (callers built the old 66-stud aircraft with scale 1)
	local leg = stats(A.build(folder, cf0, { name = "Legacy" }))
	check("scale 1 = the old 66-stud aircraft", near(leg.size.Z, 66, 2.7), leg.size.Z)
	-- collide option
	local sc = stats(A.build(folder, cf0, { scale = 1.8, collide = true }))
	check("collide=true: fuselage, wings, engines and wheels collide", sc.solid >= 12, sc.solid)
	-- livery
	local fin
	for _, d in m320:GetDescendants() do if d.Name == "Fin" then fin = d; break end end
	check("fin in the livery colour", fin ~= nil and fin.Color == Color3.fromRGB(24, 120, 128))
	-- attachments for boarding
	local pts = A.points("320", 1.8)
	local m = A.build(folder, cf0, { scale = 1.8, kind = "320", name = "Stand" })
	local root = m:FindFirstChild("AircraftRoot")
	local door = root and root:FindFirstChild("DoorL1")
	check("AircraftRoot = PrimaryPart at the origin", root ~= nil and m.PrimaryPart == root and (root.Position - cf0.Position).Magnitude < 1e-6)
	check("DoorL1 attachment tagged BoardingDoor with DoorHalf", door ~= nil and door:GetAttribute("BoardingDoor") == true and math.abs(door:GetAttribute("DoorHalf") - pts.doorHalf) < 1e-6)
	check("DoorL1 = points().doorL1 (left side, outward)", door and (door.WorldPosition - (cf0 * pts.doorL1).Position).Magnitude < 1e-4 and pts.doorL1.Position.X < 0 and pts.doorL1.LookVector.X < -0.9)
	local names = {}
	for _, a in root:GetChildren() do names[a.Name] = true end
	check("seat and camera attachments", names.CaptainSeat and names.FirstOfficerSeat and names.CockpitCamera and names.CabinCamera and names.CabinSeat1 and names.CabinSeat6 and names.DoorR1 and names.DoorL2)
	-- the airport package's jet-bridge rule: frontmost left "Door*" part/attachment, tagged ones first
	local best, bestScore
	for _, d in m:GetDescendants() do
		local tagged = d:GetAttribute("BoardingDoor") == true
		if tagged or string.sub(d.Name, 1, 4) == "Door" then
			local pos = if d:IsA("BasePart") then d.Position elseif d:IsA("Attachment") then d.WorldPosition else nil
			if pos then
				local l = cf0:PointToObjectSpace(pos)
				local score = if tagged then -1e6 + l.Z else l.Z
				if l.X < 0 and (not bestScore or score < bestScore) then best = d; bestScore = score end
			end
		end
	end
	check("jet bridges pick DoorL1", best == door, best and best:GetFullName())
	local outlinesNamedDoor = 0
	for _, d in m:GetDescendants() do if d:IsA("BasePart") and string.sub(d.Name, 1, 4) == "Door" then outlinesNamedDoor += 1 end end
	check("no decorative part is named Door*", outlinesNamedDoor == 0, outlinesNamedDoor)
	local sill = (cf0 * pts.doorL1).Position.Y - pts.doorHalf - cf0.Position.Y
	check("door sill at cabin floor height (+-0.3)", math.abs(sill - pts.cabin.floorY) < 0.3, sill .. " vs " .. pts.cabin.floorY)
	-- glazed cockpit with the seats inside the canopy, below the crown and above the lower nose
	local glass, ws = 0, 0
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "CockpitSideWindow" or d.Name == "Windshield") then
			if d.Transparency > 0.3 and d.Transparency < 0.9 then glass += 1 end
			if d.Name == "Windshield" then ws += 1 end
		end
	end
	check("cockpit glass: windshield + side windows (see-through)", glass >= 8 and ws >= 4, glass)
	local cap = pts.captain.Position
	check("captain seat inside the cockpit, head height in the window band", cap.Z < pts.noseZ * 0.75 and cap.X < 0 and cap.Y + 1.5 > pts.cabin.floorY + 4 and cap.Y + 1.5 < pts.height * 0.45, tostring(cap))
	check("cockpit camera behind the seats, looking forward", pts.cockpitCamera.Position.Z > cap.Z and pts.cockpitCamera.LookVector.Z < -0.9)
	check("cabin camera looks out of the left side", pts.cabinCamera.LookVector.X < -0.5)
	-- the seated pilots are visible from where players stand: the segment eye -> head centre (seat + 1.5, the
	-- EmployeeRigDesign rig sitting) crosses no opaque part (glass with transparency > 0.3 is see-through).
	-- Exact shapes: boxes, Roblox wedges (no top-front edge), cylinders, balls and sphere-mesh ellipsoids.
	-- The shuttle on its real stand (FlightPlan.HOME_STAND, scale 1.8); eyes in the gate A1 lounge (terminal
	-- floor + 5.5, between the seat rows and at the glass) and on the apron.
	local FP = M.require(RS.Shared.FlightPlan)
	local CityPlan = M.require(RS.Shared.Config.CityPlan)
	local function segmentHits(d, from, to, stop)
		local o = d.CFrame:PointToObjectSpace(from)
		local dir = to - from
		local len = dir.Magnitude
		local v = d.CFrame:VectorToObjectSpace(dir / len)
		local h = d.Size / 2
		local t0, t1 = 0, len - stop
		local function slab(oa, va, ha)
			if math.abs(va) < 1e-9 then return math.abs(oa) <= ha end
			local a1, b1 = (-ha - oa) / va, (ha - oa) / va
			if a1 > b1 then a1, b1 = b1, a1 end
			t0 = math.max(t0, a1); t1 = math.min(t1, b1)
			return t0 <= t1
		end
		local function quad(a2, b2, c2) -- a t^2 + b t + c <= 0
			if math.abs(a2) < 1e-12 then return c2 <= 0 end
			local disc = b2 * b2 - 4 * a2 * c2
			if disc < 0 then return false end
			local r = math.sqrt(disc)
			local q1, q2 = (-b2 - r) / (2 * a2), (-b2 + r) / (2 * a2)
			t0 = math.max(t0, math.min(q1, q2)); t1 = math.min(t1, math.max(q1, q2))
			return t0 <= t1
		end
		if not (slab(o.X, v.X, h.X) and slab(o.Y, v.Y, h.Y) and slab(o.Z, v.Z, h.Z)) then return false end
		local mesh = d:FindFirstChildOfClass("SpecialMesh")
		if mesh and mesh.MeshType == Enum.MeshType.Sphere then
			local ox, oy, oz = o.X / h.X, o.Y / h.Y, o.Z / h.Z
			local vx, vy, vz = v.X / h.X, v.Y / h.Y, v.Z / h.Z
			return quad(vx * vx + vy * vy + vz * vz, 2 * (ox * vx + oy * vy + oz * vz), ox * ox + oy * oy + oz * oz - 1)
		elseif d:IsA("WedgePart") then
			-- solid where y*hz - z*hy <= 0
			local f0, df = o.Y * h.Z - o.Z * h.Y, v.Y * h.Z - v.Z * h.Y
			if math.abs(df) < 1e-12 then return f0 <= 0 end
			local tc = -f0 / df
			if df > 0 then t1 = math.min(t1, tc) else t0 = math.max(t0, tc) end
			return t0 <= t1
		elseif d:IsA("Part") and d.Shape == Enum.PartType.Cylinder then
			local r = math.min(h.Y, h.Z)
			return quad(v.Y * v.Y + v.Z * v.Z, 2 * (o.Y * v.Y + o.Z * v.Z), o.Y * o.Y + o.Z * o.Z - r * r)
		elseif d:IsA("Part") and d.Shape == Enum.PartType.Ball then
			local r = math.min(h.X, h.Y, h.Z)
			return quad(v:Dot(v), 2 * o:Dot(v), o:Dot(o) - r * r)
		end
		return true
	end
	local function blockers(model, from, to)
		local hits = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency <= 0.3 and segmentHits(d, from, to, 0.7) then
				table.insert(hits, d.Name)
			end
		end
		return hits
	end
	local sCf = FP.HOME_STAND
	local shuttle = A.build(folder, sCf, { scale = FP.CONFIG.scale, kind = "320", name = "VisTest" })
	local sp = A.points("320", FP.CONFIG.scale)
	local gx = sCf.Position.X
	local eyeY = CityPlan.GROUND + 0.5 + 5.5
	local lounge = {
		{ "lounge west rows, back", Vector3.new(gx - 26, eyeY, 2511.5) }, { "lounge west rows, front", Vector3.new(gx - 26, eyeY, 2524.5) },
		{ "boarding lane at the glass", Vector3.new(gx - 12, eyeY, 2527) }, { "gate centre at the glass", Vector3.new(gx, eyeY, 2527) },
		{ "lounge east rows, front", Vector3.new(gx + 14, eyeY, 2519.5) }, { "lounge east rows, far", Vector3.new(gx + 28, eyeY, 2519.5) },
		{ "gate desk", Vector3.new(gx + 4, eyeY, 2512) },
	}
	for _, seat in { { "captain", sp.captain, -1 }, { "first officer", sp.firstOfficer, 1 } } do
		local head = (sCf * seat[2]).Position + Vector3.new(0, 1.5, 0)
		local seen, blockedBy = 0, {}
		for _, view in lounge do
			local hits = blockers(shuttle, view[2], head)
			if #hits == 0 then seen += 1 else table.insert(blockedBy, view[1] .. ": " .. table.concat(hits, "/")) end
		end
		check(seat[1] .. "'s head visible from >= 5 of 7 gate A1 lounge positions", seen >= 5, seen .. " of 7; " .. table.concat(blockedBy, "; "))
		print(string.format("  %s: head visible from %d of 7 gate A1 lounge positions%s", seat[1], seen, if #blockedBy > 0 then " (blocked: " .. table.concat(blockedBy, "; ") .. ")" else ""))
		local l = seat[2].Position
		local apron = {
			{ "from the side at cockpit height", sCf * Vector3.new(seat[3] * 26, l.Y + 1.6, l.Z) },
			{ "from the apron (5 studs eye height, 40 studs out, abeam)", sCf * Vector3.new(seat[3] * 40, 5, l.Z - 2) },
			{ "from the apron ahead (5 studs eye height, 45 studs ahead)", sCf * Vector3.new(seat[3] * 4, 5, sp.noseZ - 45) },
		}
		for _, view in apron do
			local hits = blockers(shuttle, view[2], head)
			check(seat[1] .. "'s head visible " .. view[1], #hits == 0, table.concat(hits, ","))
		end
	end
	shuttle:Destroy()
	-- mesh path
	local assets = Instance.new("Folder"); assets.Name = "Assets"
	local air = Instance.new("Folder"); air.Name = "Aircraft"; air.Parent = assets
	local tpl = Instance.new("Model"); tpl.Name = "Skyliner320"
	for _, n in { "Fuselage", "Wing_L", "Fan_1", "NoseGear", "MainWheels_L" } do
		local p = Instance.new("Part"); p.Name = n; p.Size = Vector3.new(4, 4, 4); p.Anchored = false; p.CFrame = CFrame.new(0, 6, 0); p.Parent = tpl
	end
	tpl.WorldPivot = CFrame.new()
	tpl.Parent = air
	assets.Parent = RS
	local mm = A.build(folder, cf0, { scale = A.REAL_SCALE, kind = "320", collide = true, name = "MeshPlane" })
	check("imported mesh template used when present", mm:GetAttribute("AircraftMesh") == true and mm:FindFirstChild("Fuselage") ~= nil and mm:FindFirstChild("AircraftRoot") ~= nil)
	local allAnchored, fanSpin, gearMark, fuseSolid, otherSolid = true, false, false, false, false
	for _, d in mm:GetDescendants() do
		if d:IsA("BasePart") then
			if not d.Anchored then allAnchored = false end
			if d.Name == "Fan_1" and d:GetAttribute("Spin") then fanSpin = true end
			if d.Name == "NoseGear" and d:GetAttribute("Gear") then gearMark = true end
			if d.Name == "Fuselage" and d.CanCollide then fuseSolid = true end
			if d.Name == "Wing_L" and d.CanCollide then otherSolid = true end
		end
	end
	check("mesh clone anchored, fans spin, gear marked, only the fuselage collides", allAnchored and fanSpin and gearMark and fuseSolid and not otherSolid)
	check("mesh clone carries the boarding attachments", mm.AircraftRoot:FindFirstChild("DoorL1") ~= nil and mm.AircraftRoot.DoorL1:GetAttribute("BoardingDoor") == true)
	local nm = A.build(folder, cf0, { scale = A.REAL_SCALE, kind = "320", mesh = false })
	check("mesh=false builds the part model", nm:GetAttribute("AircraftMesh") == nil and nm:FindFirstChild("Nose") ~= nil)
	local md = A.build(folder, cf0, { kind = "320", lod = "medium" })
	check("distant LODs never use the mesh", md:GetAttribute("AircraftMesh") == nil)
	assets:Destroy()
	-- helicopter
	local hcf = CFrame.new(10, 24.25, 10) * CFrame.Angles(0, 1, 0)
	local h = A.buildHelicopter(folder, hcf, { airline = "Meridian Air" })
	local hs = stats(h)
	check("helicopter <= 60 parts, pure decoration", hs.n <= 60 and hs.solid == 0 and hs.badFlags == 0, hs.n)
	check("helicopter skids on the ground", near(hs.lo.Y, 0, 0.15), hs.lo.Y)
	local mainBlades, tailBlades = 0, 0
	for _, d in h:GetDescendants() do
		if d:GetAttribute("Rotor") == "main" and d.Name == "HeliBlade" then mainBlades += 1 end
		if d:GetAttribute("Rotor") == "tail" and d.Name == "HeliTailBlade" then tailBlades += 1 end
	end
	check("rotors: 4 main blades, 2 tail blades, hubs published", mainBlades == 4 and tailBlades == 2 and h:GetAttribute("RotorHub") ~= nil and h:GetAttribute("TailHub") ~= nil)
	check("rotor diameter ~32 studs", hs.size.X > 28 and hs.size.X < 36, hs.size.X)
end

local ok, err = M.runMain(body, { timeout = 300, maxSteps = 5000000 })
if not ok then failc += 1; print("ERROR " .. tostring(err)) end
print(string.format("flight_aircraft: %d passed, %d failed", pass, failc))
if failc > 0 then error("flight_aircraft failed", 0) end
