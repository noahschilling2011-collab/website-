--!nocheck
-- Metro package: traffic stress over several seeds / foci: overlaps in a lane, red-light runs, cars off their lane,
-- and world-space conflicts (oriented car boxes vs each other - turns included - and walkers inside a car), plus
-- gridlock (the longest standstill of any car) and box reservations taken by force.
-- Run (from tests/metro): ../../tools/luau stress_traffic.luau -a .gen_metro [seeds]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_metro")
local NSEEDS = tonumber(args[2] or "6")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
M.loadTree(manifest, sources)
M.quiet = true
local G = M.G
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end
local function body()
	local Vector3 = G.Vector3
	local game = M.game
	local RS = game.ReplicatedStorage
	local Plan = M.require(RS.Shared.Config.MetroPlan)
	local City = M.require(RS.Shared.Config.CityPlan)
	local Builder = M.require(game.ServerScriptService.Server.Services.CityBuilder)
	Builder.build("Port Meridian · $1.5k return")
	local Life = M.require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.CityLifeController)
	Life.init()
	local function fd(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2) end
	local function carRect(c)
		local f = Vector3.new(c.look.X, 0, c.look.Z)
		if f.Magnitude < 0.01 then f = Vector3.new(0, 0, -1) end
		f = f.Unit
		return { p = Vector3.new(c.pos.X, 0, c.pos.Z), f = f, r = Vector3.new(-f.Z, 0, f.X), hl = c.len / 2 - 0.4, hw = c.parts[1].Size.X / 2 - 0.3, c = c }
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
	local foci = { Vector3.new(0, 30, 7745), Vector3.new(0, 30, 8080), Vector3.new(420, 30, 8336), Vector3.new(180, 30, 1250), Vector3.new(0, 30, 1500) }
	local base = Plan.SEED
	local total = { overlap = 0, red = 0, off = 0, turns = 0, steps = 0, carCar = 0, walkerCar = 0, maxStill = 0, samples = 0 }
	for s = 1, NSEEDS do
		for fi, focus in foci do
			Plan.SEED = base + s * 7919
			Life.deactivate()
			local now = 1.7e9 + 500 + s * 37 + fi * 11
			local dt = 1 / 30
			local prevProg, wasTurning, still = {}, {}, {}
			for f = 1, 60 * 30 do
				now += dt
				if Life.update(focus, dt, now) then
							local R = Life.region()
					total.steps += 1
					for _, L in R.lanes do
						local sorted = table.clone(L.cars)
						table.sort(sorted, function(p, q) return p.a * L.dir < q.a * L.dir end)
						for i = 1, #sorted - 1 do
							local a, b = sorted[i], sorted[i + 1]
							if (b.a * L.dir - b.len / 2) - (a.a * L.dir + a.len / 2) < -0.5 then
								total.overlap += 1
								if total.overlap <= 3 then print(string.format("  overlap seed %d focus %d %s lane %d dir %d: %s a=%.1f v=%.1f / %s a=%.1f v=%.1f", s, fi, L.road.id, L.lane.index, L.dir, a.kind, a.a, a.v, b.kind, b.a, b.v)) end
							end
						end
						for _, c in L.cars do
							if fd(Plan.lanePoint(L.lane, c.a, City.ROAD_TOP), c.pos) > 0.6 then total.off += 1 end
							local front = c.a * L.dir + c.len / 2
							local pp = prevProg[c]
							local pf = if pp and pp.lane == L then pp.front else nil
							if pf and R.net.signals then
								for _, ref in L.refs do
									local stopP = ref.a * L.dir - (Plan.walkOff(ref.other) + 4.5)
									if pf < stopP - 0.2 and front >= stopP + 0.2 and Plan.greenLeft(ref.j, L.road.axis, now) <= 0 and Plan.greenLeft(ref.j, L.road.axis, now - 0.6) <= 0 then
										total.red += 1
										if total.red <= 3 then print(string.format("  red-light seed %d focus %d %s %s a=%.1f v=%.1f", s, fi, c.kind, L.road.id, c.a, c.v)) end
									end
								end
							end
							prevProg[c] = { lane = L, front = front }
						end
					end
					for _, c in Life.cars() do
						if c.turn and not wasTurning[c] then total.turns += 1 end
						wasTurning[c] = c.turn ~= nil
						if not c.lane then prevProg[c] = nil end
						if c.alive and c.v < 0.3 then still[c] = (still[c] or 0) + dt; total.maxStill = math.max(total.maxStill, still[c]) else still[c] = 0 end
					end
					if total.steps % 2 == 0 then
						total.samples += 1
						local rs = {}
						for _, c in Life.cars() do if c.alive then table.insert(rs, carRect(c)) end end
						for a = 1, #rs do
							for b = a + 1, #rs do
								if rectsOverlap(rs[a], rs[b]) then
									total.carCar += 1
									if total.carCar <= 3 then print(string.format("  car-car seed %d focus %d: %s at %.0f,%.0f vs %s at %.0f,%.0f", s, fi, rs[a].c.kind, rs[a].c.pos.X, rs[a].c.pos.Z, rs[b].c.kind, rs[b].c.pos.X, rs[b].c.pos.Z)) end
								end
							end
						end
						for _, w in Life.walkers() do
							if w.alive and w.mode ~= "sit" and w.pos.Y > 0 then
								for _, R in rs do
									if inRect(R, w.pos, 0.6) then
										total.walkerCar += 1
										if total.walkerCar <= 3 then print(string.format("  walker-in-car seed %d focus %d: walker at %.0f,%.0f in %s", s, fi, w.pos.X, w.pos.Z, R.c.kind)) end
									end
								end
							end
						end
					end
				end
			end
		end
	end
	Plan.SEED = base
	print(string.format("stress: %d seeds x %d foci, %d steps, %d turns, %d world-space samples, longest standstill %.1f s, box reservations forced %d", NSEEDS, #foci, total.steps, total.turns, total.samples, total.maxStill, Life.stats().forcedBox))
	check("no overlaps in a lane (all seeds)", total.overlap == 0, total.overlap)
	check("no red-light runs (all seeds)", total.red == 0, total.red)
	check("cars on their lane line (all seeds)", total.off == 0, total.off)
	check("cars turn (all seeds)", total.turns > NSEEDS * 10, total.turns)
	check("no car-car overlap anywhere (oriented boxes, all seeds)", total.carCar == 0, total.carCar)
	check("no walker inside a car (all seeds)", total.walkerCar == 0, total.walkerCar)
	-- long runs (busiest foci: arrival plaza with the boulevard's T-end, Exchange junction): no car or walker
	-- starves (a signal cycle is 28 s; turning cars yield to walkers on the walk phase and to older requests)
	local longStill, longWait, longSteps = 0, 0, 0
	for fi, focus in { Vector3.new(0, 30, 7745), Vector3.new(0, 30, 8080) } do
		Plan.SEED = base + 7919
		Life.deactivate()
		local now = 1.7e9 + 500 + 37 + fi * 11
		local dt = 1 / 30
		local still = {}
		for f = 1, 240 * 30 do
			now += dt
			if Life.update(focus, dt, now) then
				longSteps += 1
				for _, c in Life.cars() do
					if c.alive and c.v < 0.3 then still[c] = (still[c] or 0) + dt; longStill = math.max(longStill, still[c]) else still[c] = 0 end
				end
				for _, w in Life.walkers() do if w.alive and w.mode == "wait" then longWait = math.max(longWait, w.waitT) end end
			end
		end
	end
	Plan.SEED = base
	print(string.format("long runs: 2 foci x 240 s, %d steps, longest car standstill %.1f s, longest walker wait %.1f s", longSteps, longStill, longWait))
	check("no gridlock: every car moves again within 100 s (busiest foci, 240 s)", longStill < 100, longStill)
	check("no walker waits more than 60 s at a crossing (busiest foci, 240 s)", longWait < 60, longWait)
end
local ok, err = M.runMain(body, { timeout = 3000, maxSteps = 500000000 })
if not ok then failc += 1; print("ERROR " .. tostring(err)) end
print(string.format("metro_stress: %d passed, %d failed", pass, failc))
if failc > 0 then error("metro_stress failed") end
