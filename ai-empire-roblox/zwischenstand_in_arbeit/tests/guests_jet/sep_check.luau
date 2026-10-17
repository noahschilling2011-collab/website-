--!nocheck
-- guests_jet: separation sweep (module, used by test_jet.luau): every scheduled company-jet flight against the
-- shuttle, the ambient airliners (FlightPlan.ambient) and a second company jet - hull distance at every altitude.
-- Hull = sample points along the fuselage and the wing line (jet 46 x 41.6, airliners 118.8 x 113.2 at scale 1.8).
return function(M, G, check, opts)
	local Vector3 = G.Vector3
	local RS = M.game.ReplicatedStorage
	local JP = M.require(RS.Shared.JetPlan)
	local FP = M.require(RS.Shared.FlightPlan)
	local CP = M.require(RS.Shared.Config.CityPlan)
	local STEP = opts.step or 6
	local DT = 0.5
	local function hull(len, span, n)
		local pts = {}
		for i = 0, n do table.insert(pts, Vector3.new(0, 0, -len / 2 + len * i / n)) end
		for i = 0, n do table.insert(pts, Vector3.new(-span / 2 + span * i / n, 0, len * 0.05)) end
		return pts
	end
	local JH, SH = hull(46, 41.6, 10), hull(118.8, 113.2, 14)
	local function minDist(cfA, ha, cfB, hb)
		local dc = (cfA.Position - cfB.Position).Magnitude
		if dc > 200 then return dc end
		local best = math.huge
		local wa = {}
		for _, p in ha do table.insert(wa, cfA * p) end
		for _, q in hb do local wq = cfB * q; for _, p in wa do local d = (p - wq).Magnitude; if d < best then best = d end end end
		return best
	end
	-- the position halfway between two samples too (closing speeds up to ~250 studs/s): check at DT / 2
	local hg = CP.AIRPORT.hangar
	local function inHangar(p) return p.X < hg.x2 + 2 and p.X > hg.x1 and p.Z > hg.z1 and p.Z < hg.z2 end
	local I = FP.interval()
	local base = FP.CONFIG.epoch + (opts.cycle or 1000) * I
	local CLEAR = 8
	------------------------------------------------------------------ 1. jet vs shuttle + ambient airliners
	local flights, unclear, hitS, hitA, worstS, worstA, exS, exA = 0, 0, 0, 0, math.huge, math.huge, nil, nil
	local delays = {}
	local minS, minA, minSx, minAx = math.huge, math.huge, nil, nil
	for _, kind in { "out", "back", "ferry" } do
		for _, slot in { 1, 2 } do
			local T = base
			while T < base + 2 * I do
				local d, clear = JP.schedule(kind, slot, T, {}, JP.CONFIG.maxDelayEmpty)
				flights += 1
				if not clear then unclear += 1 end
				table.insert(delays, d)
				local tl = JP.timeline(kind, slot, d)
				local tau = 0
				local fS, fA = false, false
				while tau <= tl.duration do
					local t = T + tau
					local jp = JP.pose(tl, tau)
					local p = jp.cf.Position
					if not inHangar(p) then
						local sp = FP.pose(t)
						local md = minDist(jp.cf, JH, sp.cf, SH)
						if md < minS then minS = md; minSx = string.format("%s%d tau=%.1f jet %s %s / shuttle %s %s", kind, slot, tau, jp.phase, tostring(p), sp.phase, tostring(sp.cf.Position)) end
						if md < CLEAR then fS = true; if md < worstS then worstS = md; exS = string.format("%s%d d=%d tau=%.1f jet %s %s / shuttle %s %s", kind, slot, d, tau, jp.phase, tostring(p), sp.phase, tostring(sp.cf.Position)) end end
						local k = math.floor((t - FP.CONFIG.epoch) / I)
						for kk = k - 1, k do
							for _, e in FP.ambient(kk) do
								if e.kind ~= "sky" then
									local ap = FP.ambientPose(e, t)
									if ap then
										local ma = minDist(jp.cf, JH, ap.cf, SH)
										if ma < minA then minA = ma; minAx = string.format("%s%d tau=%.1f jet %s %s / ambient %s %s", kind, slot, tau, jp.phase, tostring(p), ap.phase, tostring(ap.cf.Position)) end
										if ma < CLEAR then fA = true; if ma < worstA then worstA = ma; exA = string.format("%s%d d=%d tau=%.1f jet %s %s / ambient %s %s", kind, slot, d, tau, jp.phase, tostring(p), ap.phase, tostring(ap.cf.Position)) end end
									end
								end
							end
						end
					end
					tau += DT
				end
				if fS then hitS += 1 end
				if fA then hitA += 1 end
				T += STEP
			end
		end
	end
	table.sort(delays)
	local function q(f) return delays[math.max(1, math.floor(#delays * f + 0.5))] end
	check(string.format("separation: %d scheduled jet flights (out / back / ferry, both PM slots, 2 timetable cycles) all find a clear slot", flights), unclear == 0, unclear)
	check(string.format("separation: no jet hull within %d studs of the shuttle's at any altitude", CLEAR), hitS == 0, tostring(hitS) .. " flights, worst " .. string.format("%.1f", worstS) .. " " .. tostring(exS))
	check(string.format("separation: no jet hull within %d studs of an ambient airliner's (runway, approach, climb)", CLEAR), hitA == 0, tostring(hitA) .. " flights, worst " .. string.format("%.1f", worstA) .. " " .. tostring(exA))
	print(string.format("INFO  separation: delays median %ds, 90%% %ds, max %ds; closest shuttle %.0f studs (%s), closest ambient %.0f studs (%s)", q(0.5), q(0.9), delays[#delays], minS, tostring(minSx), minA, tostring(minAx)))
	------------------------------------------------------------------ 2. two company jets
	local pairsN, unclearY, jj, js, ja, ex = 0, 0, 0, 0, 0, nil
	local minJ, minJx = math.huge, nil
	for _, kx in { "out", "back" } do
		for _, ky in { "out", "back" } do
			local T0 = base
			while T0 < base + I do
				local off = 0
				while off <= 200 do
					pairsN += 1
					local dx = JP.schedule(kx, 1, T0, {}, JP.CONFIG.maxDelayEmpty)
					local tlx = JP.timeline(kx, 1, dx)
					local wx = JP.absWindows(tlx, T0)
					local Ty = T0 + off
					local dy, cy = JP.schedule(ky, 2, Ty, wx, JP.CONFIG.maxDelayEmpty)
					if not cy then unclearY += 1 else
						local tly = JP.timeline(ky, 2, dy)
						local hitJ = false
						local t = Ty
						while t < Ty + tly.duration do
							local py = JP.pose(tly, t - Ty)
							if t >= T0 and t < T0 + tlx.duration then
								local px = JP.pose(tlx, t - T0)
								-- the shared hangar: each client shows only its own jet inside it
								if not inHangar(px.cf.Position) and not inHangar(py.cf.Position) then
									local md = minDist(px.cf, JH, py.cf, JH)
									if md < minJ then minJ = md; minJx = string.format("%s+%s %s %s / %s %s", kx, ky, px.phase, tostring(px.cf.Position), py.phase, tostring(py.cf.Position)) end
									if md < 6 then hitJ = true; ex = ex or string.format("%s+%s off=%d dy=%d tau=%.0f: %s %s / %s %s d=%.1f", kx, ky, off, dy, t - Ty, px.phase, tostring(px.cf.Position), py.phase, tostring(py.cf.Position), md) end
								end
							end
							t += 1
						end
						if hitJ then jj += 1 end
					end
					off += opts.pairStep or 25
				end
				T0 += opts.pairT or 37
			end
		end
	end
	print(string.format("INFO  two jets: closest hulls %.0f studs (%s)", minJ, tostring(minJx)))
	check(string.format("two jets: the second jet (%d pairs) always finds a slot clear of the first jet and the traffic (<= %d s)", pairsN, JP.CONFIG.maxDelayEmpty), unclearY == 0, unclearY)
	check("two jets: hulls never closer than 6 studs (runways, taxiways, apron in front of Hangar 1, Port Meridian)", jj == 0, tostring(jj) .. " pairs; " .. tostring(ex))
	return { flights = flights, delays = delays }
end
