--!nocheck
-- Metro package: walkers vs the real scenery. Builds the world (CityBuilder in the mock) and sweeps every walk edge of
-- Port Meridian and Business City at five lateral lanes in both directions, with CityLifeController's obstacle
-- avoidance applied, against every solid part in the body band (feet + 0.6 .. + 5 studs; oriented boxes, inflated by
-- the body radius). Ends at door portals (3.5 studs) and idle spots (benches, shop fronts, stops, views) are exempt: walkers walk
-- into doors; at idle spots the last 1.2 studs (walkers stand there, a bench seat starts 0.6 behind). Reports the
-- walker core (radius 1.0) - must be clear - and the arm reach (1.9).
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_metro && tools/luau tests/metro/test_paths.luau -a .gen_metro
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
	local Vector3 = G.Vector3
	local game = M.game
	local RS = game.ReplicatedStorage
	local Plan = M.require(RS.Shared.Config.MetroPlan)
	local Builder = M.require(game.ServerScriptService.Server.Services.CityBuilder)
	local world = Builder.build("Port Meridian · $1.5k return")
	local Life = M.require(game.StarterPlayer.StarterPlayerScripts.Client.Controllers.CityLifeController)
	local CELL = 16
	local function key(gx, gz) return gx * 100003 + gz end
	-- solid parts with their oriented boxes, bucketed by AABB
	local solids, grid = {}, {}
	for _, p in world:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 0.99 then
			local cf, s = p.CFrame, p.Size
			local R = { cf.RightVector, cf.UpVector, -cf.LookVector }
			local ex = {}
			for k = 1, 3 do
				local axis = if k == 1 then Vector3.new(1, 0, 0) elseif k == 2 then Vector3.new(0, 1, 0) else Vector3.new(0, 0, 1)
				ex[k] = math.abs(R[1]:Dot(axis)) * s.X / 2 + math.abs(R[2]:Dot(axis)) * s.Y / 2 + math.abs(R[3]:Dot(axis)) * s.Z / 2
			end
			local pos = cf.Position
			local sol = { p = p, cf = cf, hx = s.X / 2, hy = s.Y / 2, hz = s.Z / 2, y1 = pos.Y - ex[2], y2 = pos.Y + ex[2], name = p.Name }
			-- skip huge slabs (ground, plazas, roads) quickly: they are floors when their top is low, buildings otherwise
			table.insert(solids, sol)
			for gx = math.floor((pos.X - ex[1]) / CELL), math.floor((pos.X + ex[1]) / CELL) do
				for gz = math.floor((pos.Z - ex[3]) / CELL), math.floor((pos.Z + ex[3]) / CELL) do
					local k = key(gx, gz)
					local list = grid[k]
					if not list then list = {}; grid[k] = list end
					table.insert(list, sol)
				end
			end
		end
	end
	local function hits(x, y, z, r)
		local list = grid[key(math.floor(x / CELL), math.floor(z / CELL))]
		if not list then return nil end
		for _, sol in list do
			if sol.y2 > y + 0.6 and sol.y1 < y + 5 then
				for _, h in { 1, 2.5, 4 } do
					local q = sol.cf:PointToObjectSpace(Vector3.new(x, y + h, z))
					if math.abs(q.X) < sol.hx + r and math.abs(q.Y) < sol.hy + 0.05 and math.abs(q.Z) < sol.hz + r then return sol end
				end
			end
		end
		return nil
	end
	local function sweep(name, net)
		local core, arms, samples = {}, 0, 0
		local byName = {}
		for _, e in net.edges do
			local na, nb = net.nodes[e.a], net.nodes[e.b]
			local pa, pb = na.p, nb.p
			local dx, dz = pb.X - pa.X, pb.Z - pa.Z
			local L = math.sqrt(dx * dx + dz * dz)
			if L > 0.05 then
				local ux, uz = dx / L, dz / L
				local exA = (na.portal and 3.5) or (na.idle and 1.2) or 0
				local exB = (nb.portal and 3.5) or (nb.idle and 1.2) or 0
				local s = 0
				while s <= L do
					if s >= exA and s <= L - exB then
						local y = pa.Y + (pb.Y - pa.Y) * (s / L)
						if e.junction and math.min(s, L - s) > 3 then y = Plan.ROAD_TOP end
						for _, fr in { 0, 0.25, 0.5, 0.75, 1 } do
							for _, dir in { 1, -1 } do
								local lat = (0.2 + 0.8 * fr) * e.half
								local le = if dir > 0 then lat else -lat
								le = Life.avoid(net, e, s, le)
								local x, z = pa.X + ux * s - uz * le, pa.Z + uz * s + ux * le
								samples += 1
								local h = hits(x, y, z, 1.0)
								if h then
									local k = h.name
									byName[k] = (byName[k] or 0) + 1
									if #core < 8 then table.insert(core, string.format("%s@%.0f,%.0f", k, x, z)) end
								elseif hits(x, y, z, 1.9) then
									arms += 1
								end
							end
						end
					end
					s += 0.5
				end
			end
		end
		local n = 0
		for _ in byName do n += 1 end
		local parts = {}
		for k, v in byName do table.insert(parts, k .. " x" .. v) end
		print(string.format("%s: %d samples, body hits %d (%s), arm brushes %d", name, samples, #core > 0 and 1 or 0, table.concat(parts, ", "), arms))
		return core, arms, samples, byName
	end
	local pmCore, pmArms, pmSamples = sweep("Port Meridian", Plan.portMeridian())
	check("Port Meridian: walkers never walk through scenery (core radius 1.0, avoidance applied)", #pmCore == 0, table.concat(pmCore, " "))
	check("Port Meridian: arm brushes < 0.5 % of the samples", pmArms < pmSamples * 0.005, pmArms .. " / " .. pmSamples)
	local dtCore, dtArms, dtSamples = sweep("Business City", Plan.downtown())
	check("Business City: walkers never walk through scenery (core radius 1.0, avoidance applied)", #dtCore == 0, table.concat(dtCore, " "))
	check("Business City: arm brushes < 0.5 % of the samples", dtArms < dtSamples * 0.005, dtArms .. " / " .. dtSamples)
end

local ok, err = M.runMain(body, { timeout = 600, maxSteps = 50000000 })
if not ok then print("ERROR " .. tostring(err)); failc += 1 end
print(string.format("metro_paths: %d passed, %d failed", pass, failc))
