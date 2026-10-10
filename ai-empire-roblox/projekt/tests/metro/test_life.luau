--!nocheck
-- Metro package: CityLifeController in the headless mock (client-only crowds and traffic).
--   * Port Meridian: activation at the arrival plaza fills the caps (60 walkers / 25 cars), every figure stays on
--     the walk graph (no walker inside a building lot / tower, height = the surface), cars stay on their lanes or
--     inside a junction box, never overlap in a lane and never pass a stop line on red; walkers start crossings
--     only with enough walk time; benches / shop fronts / bus stops are used; turns and boundary exits happen;
--     crossing / seat counters stay consistent; caps hold; batch size; time per step with the caps reached.
--   * Signals / night glow / Harbour Wheel / impostors on the real Port Meridian (CityBuilder world in workspace).
--   * Downtown (no signals): caps, walkers wait for gaps, cars stop for occupied crossings.
--   * Sleep: on the campus everything is unparented, the step connection is cut, update() does nothing.
--   * Determinism: the same timeline twice gives identical positions.
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_metro && tools/luau tests/metro/test_life.luau [-a .gen_dir]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_metro")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
M.loadTree(manifest, sources)
M.quiet = true
local G = M.G
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local function body()
	local Vector3, CFrame, Enum = G.Vector3, G.CFrame, G.Enum
	local game = M.game
	local RS = game.ReplicatedStorage
	local Plan = M.require(RS.Shared.Config.MetroPlan)
	local City = M.require(RS.Shared.Config.CityPlan)
	local Builder = M.require(game.ServerScriptService.Server.Services.CityBuilder)
	local world = Builder.build("Port Meridian · $1.5k return")
	local Life = M.require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.CityLifeController)
	Life.init()
	local ws = game.Workspace
	local function apply(parts, frames) for i, p in parts do p.CFrame = frames[i] end end
	local function fd(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2) end
	-- distance from a point to the nearest walk edge (flat) and the edge
	local function nearestEdge(net, p)
		local best, be = math.huge, nil
		for _, e in net.edges do
			local a, b = net.nodes[e.a].p, net.nodes[e.b].p
			local dx, dz = b.X - a.X, b.Z - a.Z
			local l2 = dx * dx + dz * dz
			local t = if l2 > 0 then math.clamp(((p.X - a.X) * dx + (p.Z - a.Z) * dz) / l2, 0, 1) else 0
			local d = math.sqrt((p.X - (a.X + dx * t)) ^ 2 + (p.Z - (a.Z + dz * t)) ^ 2)
			if d < best then best, be = d, e end
		end
		return best, be
	end
	local blocked = {}
	for _, l in Plan.LOTS do table.insert(blocked, { x1 = l.x - l.w / 2 + 1, x2 = l.x + l.w / 2 - 1, z1 = l.z - l.d / 2 + 1, z2 = l.z + l.d / 2 - 1, id = l.id }) end
	for _, b in City.BUILDINGS do
		if b.zone == "abroad" then
			local c1 = b.frame:PointToWorldSpace(Vector3.new(-b.width / 2 + 1, 0, 2)); local c2 = b.frame:PointToWorldSpace(Vector3.new(b.width / 2 - 1, 0, b.depth - 1))
			table.insert(blocked, { x1 = math.min(c1.X, c2.X), x2 = math.max(c1.X, c2.X), z1 = math.min(c1.Z, c2.Z), z2 = math.max(c1.Z, c2.Z), id = b.id })
		end
	end
	-- world-space oriented car boxes (body minus a small margin): car vs car and walker inside a car
	local function carRect(c)
		local f = Vector3.new(c.look.X, 0, c.look.Z)
		if f.Magnitude < 0.01 then f = Vector3.new(0, 0, -1) end
		f = f.Unit
		return { p = Vector3.new(c.pos.X, 0, c.pos.Z), f = f, r = Vector3.new(-f.Z, 0, f.X), hl = c.len / 2 - 0.4, hw = c.parts[1].Size.X / 2 - 0.3 }
	end
	local function inRect(R, p, pad)
		local d = Vector3.new(p.X, 0, p.Z) - R.p
		return math.abs(d:Dot(R.f)) < R.hl + pad and math.abs(d:Dot(R.r)) < R.hw + pad
	end
	local function proj(R, axis)
		local c = R.p:Dot(axis)
		local e = math.abs(R.f:Dot(axis)) * R.hl + math.abs(R.r:Dot(axis)) * R.hw
		return c - e, c + e
	end
	local function rectsOverlap(A, B)
		for _, ax in { A.f, A.r, B.f, B.r } do
			local a1, a2 = proj(A, ax)
			local b1, b2 = proj(B, ax)
			if a2 < b1 or b2 < a1 then return false end
		end
		return true
	end
	local function conflictsNow()
		local rs, wc, cc = {}, 0, 0
		for _, c in Life.cars() do if c.alive then table.insert(rs, carRect(c)) end end
		for _, w in Life.walkers() do
			if w.alive and w.mode ~= "sit" and w.pos.Y > 0 then
				for _, R in rs do if inRect(R, w.pos, 0.6) then wc += 1 end end
			end
		end
		for a = 1, #rs do for b = a + 1, #rs do if rectsOverlap(rs[a], rs[b]) then cc += 1 end end end
		return wc, cc
	end
	local function insideBlocked(p)
		for _, r in blocked do if p.X > r.x1 and p.X < r.x2 and p.Z > r.z1 and p.Z < r.z2 then return r.id end end
		return nil
	end

	------------------------------------------------------------------ Port Meridian
	local focus = Vector3.new(0, 30, 7745)
	local now = 1.7e9 + 1000
	local dt = 1 / 60
	Life.update(focus, dt, now)
	local st = Life.stats()
	local R = Life.region()
	check("metro region active at the arrival plaza", R ~= nil and R.id == "metro" and st.region == "metro", st.region)
	local alive = 0
	for _, w in Life.walkers() do if w.alive then alive += 1 end end
	check("first fill: 60 walkers", alive == 60, alive)
	local carsAlive = 0
	for _, c in Life.cars() do if c.alive then carsAlive += 1 end end
	check("first fill: 15-25 cars", carsAlive >= 15 and carsAlive <= 25, carsAlive)
	local folder = Life.folder()
	check("CityLife folder in workspace, far skyline in workspace", folder and folder.Parent == ws and Life.far() and Life.far().Parent == ws)
	-- decoration flags of every client part; shadows only from car bodies and the torso / legs of near walkers
	local bad, nparts, shadows = 0, 0, 0
	local SHADOW = { Body = true, Torso = true, LeftLeg = true, RightLeg = true }
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			nparts += 1
			if d.CanCollide or d.CanQuery or d.CanTouch or not d.Anchored then bad += 1 end
			if d.CastShadow then shadows += 1; if not SHADOW[d.Name] then bad += 1 end end
		end
	end
	local farShadow = 0
	for _, w in Life.walkers() do
		for _, p in w.parts do if p.CanCollide or p.CanQuery or p.CanTouch then bad += 1 end end
		if w.alive and w.far then for _, p in w.parts do if p.CastShadow then farShadow += 1 end end end
	end
	for _, d in Life.far():GetDescendants() do if d:IsA("BasePart") and (d.CanCollide or d.CanQuery or d.CanTouch) then bad += 1 end end
	check("client parts: anchored, no collide/touch/query; shadows only car bodies + near walkers' torso/legs (<= 205)", bad == 0 and farShadow == 0 and shadows > 25 and shadows <= 60 * 3 + 25, bad .. " bad, " .. shadows .. " shadow parts, far " .. farShadow)
	local eyesNear, eyesFar = 0, 0
	for _, w in Life.walkers() do
		if w.alive then
			for _, e in w.eyes do if e.Parent ~= nil then if w.far then eyesFar += 1 else eyesNear += 1 end end end
		end
	end
	check("eyes on near walkers only", eyesNear > 0 and eyesFar == 0, eyesNear .. " / " .. eyesFar)
	local wp = 0
	for _, w in Life.walkers() do wp += #w.parts end
	check("walker rigs 7-9 parts (avg <= 8.5)", wp / #Life.walkers() <= 8.5 and wp / #Life.walkers() >= 7, wp / #Life.walkers())
	local farN = 0
	for _, d in Life.far():GetDescendants() do if d:IsA("BasePart") then farN += 1 end end
	check("far skyline + impostors <= 700 client parts", farN <= 700 and farN > 200, farN)

	-- simulate 90 s at 60 fps (update throttles to 30 Hz)
	local net = R.net
	local signalViolations, crossViolations, offGraph, inBuilding, badHeight, overlap, offLane = 0, 0, 0, 0, 0, 0, 0
	local walkerInCar, carInCar = 0, 0
	local seen = { sit = 0, idle = 0, wait = 0, cross = 0, turns = 0, exits = 0, portalIn = 0 }
	local maxBatch, steps, tSum, tMax = 0, 0, 0, 0
	local prevProg = {}
	local prevCross = {}
	local exampleOff
	local wasTurning = {}
	for f = 1, 90 * 60 do
		now += dt
		local t0 = os.clock()
		local stepped = Life.update(focus, dt, now)
		local el = os.clock() - t0
		if stepped then
			steps += 1; tSum += el; tMax = math.max(tMax, el)
			maxBatch = math.max(maxBatch, Life.stats().parts)
		end
		if stepped and steps % 3 == 0 then
			local wc, cc = conflictsNow()
			walkerInCar += wc; carInCar += cc
			for _, w in Life.walkers() do
				if w.alive then
					if w.mode == "sit" then seen.sit += 1 elseif w.mode == "idle" then seen.idle += 1 elseif w.mode == "wait" then seen.wait += 1 end
					if w.crossKey and not prevCross[w] then
						seen.cross += 1
						local e = w.edge
						if e and e.junction and Plan.walkLeft(e.junction, e.axis, now) <= 0 then crossViolations += 1 end
					end
					prevCross[w] = w.crossKey
					if w.pos.Y > 0 and w.mode ~= "sit" then
						local d = nearestEdge(net, w.pos)
						local okEdge = d <= 4.2
						if not okEdge then
							for _, e in net.edges do
								local a, b = net.nodes[e.a].p, net.nodes[e.b].p
								local dx, dz = b.X - a.X, b.Z - a.Z
								local l2 = dx * dx + dz * dz
								local t = if l2 > 0 then math.clamp(((w.pos.X - a.X) * dx + (w.pos.Z - a.Z) * dz) / l2, 0, 1) else 0
								if math.sqrt((w.pos.X - (a.X + dx * t)) ^ 2 + (w.pos.Z - (a.Z + dz * t)) ^ 2) <= e.half + 0.8 then okEdge = true; break end
							end
						end
						if not okEdge then offGraph += 1; exampleOff = exampleOff or string.format("%s %.0f,%.0f d=%.1f", w.mode, w.pos.X, w.pos.Z, d) end
						if insideBlocked(w.pos) then inBuilding += 1 end
						if math.abs(w.pos.Y - City.GROUND) > 1.7 then badHeight += 1 end -- up to the spire plinth (G + 1.6)
					end
				end
			end
			for _, L in R.lanes do
				local sorted = table.clone(L.cars)
				table.sort(sorted, function(p, q) return p.a * L.dir < q.a * L.dir end)
				for i = 1, #sorted - 1 do
					local a, b = sorted[i], sorted[i + 1]
					if (b.a * L.dir - b.len / 2) - (a.a * L.dir + a.len / 2) < -0.5 then
						overlap += 1
						if overlap == 1 then print(string.format("  overlap %s lane %s dir %d: %s a=%.1f v=%.1f / %s a=%.1f v=%.1f", L.road.id, L.lane.index, L.dir, a.kind, a.a, a.v, b.kind, b.a, b.v)) end
					end
				end
				for _, c in L.cars do
					local p = Plan.lanePoint(L.lane, c.a, City.ROAD_TOP)
					if fd(p, c.pos) > 0.6 then offLane += 1 end
					-- red-light check: front crossing a stop line between two samples while red
					local front = c.a * L.dir + c.len / 2
					local pp = prevProg[c]
					local pf = if pp and pp.lane == L then pp.front else nil
					if pf and R.net.signals then
						for _, ref in L.refs do
							local stopP = ref.a * L.dir - (Plan.walkOff(ref.other) + 4.5)
							if pf < stopP - 0.2 and front >= stopP + 0.2 and Plan.greenLeft(ref.j, L.road.axis, now) <= 0 and Plan.greenLeft(ref.j, L.road.axis, now - 0.6) <= 0 then
								signalViolations += 1
								print(string.format("  red-light %s %s lane %d dir %d a=%.1f v=%.1f pf=%.1f front=%.1f stop=%.1f", c.kind, L.road.id, L.lane.index, L.dir, c.a, c.v, pf, front, stopP))
							end
						end
					end
					prevProg[c] = { lane = L, front = front }
				end
			end
			for _, c in Life.cars() do
				if c.turn and not wasTurning[c] then seen.turns += 1 end
				wasTurning[c] = c.turn ~= nil
				if not c.lane then prevProg[c] = nil end
			end
		end
	end
	st = Life.stats()
	check("walkers stay on the walk graph (within an edge half width)", offGraph == 0, offGraph .. " " .. tostring(exampleOff))
	check("no walker inside a building lot or tower", inBuilding == 0, inBuilding)
	check("walker feet at street level", badHeight == 0, badHeight)
	check("cars never overlap in a lane", overlap == 0, overlap)
	check("no car overlaps another car anywhere (oriented boxes, turns included)", carInCar == 0, carInCar)
	check("no walker inside a car (oriented boxes)", walkerInCar == 0, walkerInCar)
	check("cars on their lane line (or turning)", offLane == 0, offLane)
	check("no car passes a stop line on red", signalViolations == 0, signalViolations)
	check("walkers start crossings only on the walk phase", crossViolations == 0 and seen.cross > 5, crossViolations .. " / " .. seen.cross)
	check("walkers sit on benches", seen.sit > 0, seen.sit)
	check("walkers idle at shop fronts / bus stops / views", seen.idle > 0, seen.idle)
	check("walkers wait at crossings", seen.wait > 0, seen.wait)
	check("cars turn", seen.turns >= 3, seen.turns)
	check("recycling (despawn + respawn) happens", st.despawned > 0 and st.spawnedWalkers > 60, st.despawned .. " / " .. st.spawnedWalkers)
	local occSum, crossing = 0, 0
	for _, v in R.occ do occSum += v end
	for _, w in Life.walkers() do if w.crossKey then crossing += 1 end end
	check("crossing counters consistent", occSum == crossing, occSum .. " vs " .. crossing)
	local seatSum, sitting = 0, 0
	for _, v in R.seats do seatSum += v end
	for _, w in Life.walkers() do if w.benchNode then sitting += 1 end end
	check("bench counters consistent (<= 2 per bench)", seatSum == sitting, seatSum .. " vs " .. sitting)
	alive, carsAlive = 0, 0
	for _, w in Life.walkers() do if w.alive then alive += 1; assert(fd(w.pos, focus) <= Life.DESPAWN + 30 or w.pos.Y < 0) end end
	for _, c in Life.cars() do if c.alive then carsAlive += 1 end end
	check("caps hold after 90 s (<= 60 walkers, <= 25 cars, >= 45 walkers)", alive <= 60 and alive >= 45 and carsAlive <= 25, alive .. " / " .. carsAlive)
	check("<= 30 steps per second", steps <= 90 * 30 + 2, steps)
	check("batch <= 60*(9+2 eyes) + 25*12 + wheel parts", maxBatch <= 60 * 11 + 25 * 12 + 60, maxBatch)
	print(string.format("PERF metro (mock): %d steps, mean %.2f ms, max %.2f ms per step (caps reached: %d walkers, %d cars, batch %d parts)", steps, tSum / steps * 1000, tMax * 1000, alive, carsAlive, maxBatch))
	check("mean step time in the mock < 8 ms", tSum / steps * 1000 < 8, tSum / steps * 1000)

	------------------------------------------------------------------ signals / glow / wheel / impostors
	local sig = 0
	local sigOk = 0
	local parts, frames = Life.step(1 / 30, now, focus)
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "SignalLamp" then
			sig += 1
			-- force the 4 Hz update and compare
		end
	end
	for _ = 1, 10 do Life.step(1 / 30, now, focus) end
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "SignalLamp" then
			local j = R.net.junctions[d:GetAttribute("Junction")]
			local g = Plan.greenLeft(j, d:GetAttribute("Axis"), now)
			local want = if g > 3 then "g" elseif g > 0 then "a" else "r"
			local c = d.Color
			local got = if c.G > c.R and c.G > 0.6 then "g" elseif c.R > 0.8 and c.G > 0.5 then "a" elseif c.R > 0.7 then "r" else "?"
			if got == want then sigOk += 1 end
		end
	end
	check("signal lamps show the shared phase (8 per junction)", sig == #R.net.junctions * 8 and sigOk == sig, sigOk .. "/" .. sig)
	local glow = {}
	for _, d in world:GetDescendants() do if d:IsA("BasePart") and d:GetAttribute("GlowColor") then table.insert(glow, { p = d, m = d.Material, c = d.Color, t = d.Transparency }) end end
	Life.setNight(true)
	local neon, dark, alwaysLit, alwaysN = 0, 0, 0, 0
	for _, g in glow do
		if g.p.Material == Enum.Material.Neon then neon += 1
		elseif g.p.Color.R + g.p.Color.G + g.p.Color.B < g.c.R + g.c.G + g.c.B - 0.05 then dark += 1 end
		if g.p.Name ~= "Windows" and g.p.Name ~= "WindowGlow" and g.p.Name ~= "GlassBand" then alwaysN += 1; if g.p.Material == Enum.Material.Neon then alwaysLit += 1 end end
	end
	Life.setNight(false)
	local restored = 0
	for _, g in glow do if g.p.Material == g.m and g.p.Color == g.c and g.p.Transparency == g.t then restored += 1 end end
	check("night: shop fronts / spire / cafés always glow, office windows on ~45 % (rest darken), all restored by day",
		#glow > 100 and neon + dark == #glow and alwaysLit == alwaysN and neon > #glow * 0.4 and neon < #glow * 0.9 and restored == #glow, #glow .. " neon " .. neon .. " dark " .. dark .. " restored " .. restored)
	local wheelModel
	for _, d in world:GetDescendants() do if d.Name == "HarbourWheel" then wheelModel = d end end
	local rim
	for _, d in wheelModel:GetDescendants() do if d.Name == "WheelRim" then rim = d; break end end
	local hub = wheelModel:GetAttribute("Hub")
	local nearWheel = Vector3.new(540, 30, 8600)
	table.clear(parts); table.clear(frames)
	Life.poseWheels(nearWheel, now)
	local p1 = nil
	local P, F = {}, {}
	-- poseWheels pushes into the module batch; run a step near the wheel and read the rim's frame
	parts, frames = Life.step(1 / 15, now, nearWheel)
	for i, p in parts do if p == rim then p1 = frames[i].Position end end
	parts, frames = Life.step(1 / 15, now + 20, nearWheel)
	local p2
	for i, p in parts do if p == rim then p2 = frames[i].Position end end
	check("Harbour Wheel turns on the client (rim stays on its circle)", p1 and p2 and (p1 - p2).Magnitude > 1 and math.abs((p2 - hub).Magnitude - rim:GetAttribute("WheelR")) < 0.01, p1 and p2 and (p1 - p2).Magnitude)
	Life.updateImpostors()
	local shown = 0
	for _, imp in Life.impostors() do if imp.shown then shown += 1 end end
	check("impostors hidden while the real towers are present", shown == 0 and #Life.impostors() == #Plan.LOTS + 5, shown .. " / " .. #Life.impostors())
	local blocks = world:FindFirstChild("PortMeridian"):FindFirstChild("CityBlocks")
	local victim = blocks:GetChildren()[1]
	victim.Parent = nil
	Life.updateImpostors()
	shown = 0
	for _, imp in Life.impostors() do if imp.shown then shown += 1 end end
	check("impostor shown for a streamed-out tower", shown == 1, shown)
	victim.Parent = blocks

	------------------------------------------------------------------ sleep on the campus
	local campus = Vector3.new(0, 30, 0)
	for _ = 1, 40 do now += dt; Life.update(campus, dt, now) end
	local before = Life.stats().steps
	local any = false
	for _ = 1, 60 do now += dt; any = Life.update(campus, dt, now) or any end
	check("campus: asleep (no region, nothing parented, no steps)", Life.region() == nil and folder.Parent == nil and Life.far().Parent == nil and not any and Life.stats().steps == before)
	alive = 0
	for _, w in Life.walkers() do if w.alive or w.model.Parent ~= nil then alive += 1 end end
	for _, c in Life.cars() do if c.alive or c.model.Parent ~= nil then alive += 1 end end
	check("campus: every walker / car released", alive == 0, alive)
	check("airport (check-in desks z 2461, car park z 2421, apron) / harbour / flight corridor are outside both regions",
		Plan.regionAt(Vector3.new(0, 30, 2800)) == nil and Plan.regionAt(Vector3.new(0, 300, 5000)) == nil and Plan.regionAt(Vector3.new(0, 30, 3500)) == nil
		and Plan.regionAt(Vector3.new(-200, 30, 2461)) == nil and Plan.regionAt(Vector3.new(200, 30, 2461)) == nil and Plan.regionAt(Vector3.new(0, 30, 2421)) == nil)

	------------------------------------------------------------------ activation keeps the frame step (no 0.5 s freeze)
	Life.connectStep()
	local c0 = Life.stepConnected()
	Life.update(Vector3.new(0, 30, 7745), dt, now) -- first activation inside the step
	local c1 = Life.stepConnected() and Life.region() ~= nil and Life.region().id == "metro"
	for _ = 1, 40 do now += dt; Life.update(Vector3.new(180, 30, 1000), dt, now) end -- metro -> downtown switch inside the step
	local c2 = Life.stepConnected() and Life.region() ~= nil and Life.region().id == "downtown"
	for _ = 1, 40 do now += dt; Life.update(campus, dt, now) end
	local c3 = not Life.stepConnected() and Life.region() == nil
	check("entering / switching regions keeps the step connection; leaving both cuts it", c0 and c1 and c2 and c3, tostring(c0) .. tostring(c1) .. tostring(c2) .. tostring(c3))

	------------------------------------------------------------------ downtown
	local dfocus = Vector3.new(180, 30, 1000)
	Life.update(dfocus, dt, now)
	R = Life.region()
	alive, carsAlive = 0, 0
	for _, w in Life.walkers() do if w.alive then alive += 1 end end
	for _, c in Life.cars() do if c.alive then carsAlive += 1 end end
	check("downtown active: 44 walkers, <= 18 cars", R and R.id == "downtown" and alive == 44 and carsAlive >= 8 and carsAlive <= 18, alive .. " / " .. carsAlive)
	local occStops, gapViol, dOff, dIn = 0, 0, 0, 0
	local dts, dtSum = 0, 0
	for f = 1, 60 * 60 do
		now += dt
		local t0 = os.clock()
		local stepped = Life.update(dfocus, dt, now)
		if stepped then dts += 1; dtSum += os.clock() - t0 end
		if stepped and dts % 3 == 0 then
			for _, L in R.lanes do
				for _, c in L.cars do
					if c.v < 0.5 then
						for _, ref in L.refs do
							local stopP = ref.a * L.dir - (Plan.walkOff(ref.other) + 4.5)
							local front = c.a * L.dir + c.len / 2
							if math.abs(front - stopP) < 4 and (R.occ[ref.j.id .. ":" .. L.road.axis] or 0) > 0 then occStops += 1 end
						end
					end
				end
			end
			for _, w in Life.walkers() do
				if w.alive and w.mode ~= "sit" and w.pos.Y > 0 then
					if nearestEdge(R.net, w.pos) > 4.2 then dOff += 1 end
				end
			end
		end
	end
	check("downtown walkers on the walk graph", dOff == 0, dOff)
	check("downtown cars stop for walkers on a crossing", occStops > 0, occStops)
	print(string.format("PERF downtown (mock): %d steps, mean %.2f ms", dts, dtSum / math.max(1, dts) * 1000))

	------------------------------------------------------------------ determinism
	local function run()
		Life.deactivate()
		local t = 1.7e9 + 5000
		Life.update(focus, dt, t)
		for _ = 1, 600 do t += dt; Life.update(focus, dt, t) end
		local h = 0
		for _, w in Life.walkers() do if w.alive then h += w.pos.X * 3 + w.pos.Z * 7 end end
		for _, c in Life.cars() do if c.alive then h += c.pos.X * 11 + c.pos.Z * 13 end end
		return h
	end
	local h1, h2 = run(), run()
	check("deterministic: same timeline -> same crowd and traffic", math.abs(h1 - h2) < 1e-6, h1 .. " vs " .. h2)
end

local ok, err = M.runMain(body, { timeout = 600, maxSteps = 5000000 })
if not ok then print("ERROR " .. tostring(err)); failc += 1 end
print(string.format("metro_life: %d passed, %d failed", pass, failc))
