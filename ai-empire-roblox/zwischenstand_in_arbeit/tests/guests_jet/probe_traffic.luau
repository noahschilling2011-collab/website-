--!nocheck
-- probe: shuttle legs + ambient visits over one cycle (phases, positions) to design the jet's field windows
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_gj")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
M.loadTree(manifest, sources)
M.quiet = true
local RS = M.game.ReplicatedStorage
local FP = M.require(RS.Shared.FlightPlan)
local JP = M.require(RS.Shared.JetPlan)
local I = FP.interval()
print("interval", I)
for _, dir in { "out", "back" } do
	local leg = FP.leg(dir)
	local s = dir .. " dur=" .. string.format("%.1f", leg.duration)
	for name, ph in leg.phases do s = s .. string.format(" %s=%.0f..%.0f", name, ph.t0, ph.t1) end
	print(s, "start", FP.legStart(dir, 0))
end
local k = 1000
for _, e in FP.ambient(k) do
	if e.kind ~= "sky" then
		local s = e.kind .. string.format(" t0=%.1f (cycle+%.1f) dur=%.1f", e.t0, e.t0 - (FP.CONFIG.epoch + k * I), e.duration)
		print(s)
		if e.kind ~= "parked" then
			local t = e.t0
			while t <= e.t0 + e.duration do
				local p = FP.ambientPose(e, t)
				print(string.format("   +%5.1f %-10s %8.1f %6.1f %8.1f", t - e.t0, p.phase, p.cf.X, p.cf.Y, p.cf.Z))
				t += 4
			end
		end
	end
end
