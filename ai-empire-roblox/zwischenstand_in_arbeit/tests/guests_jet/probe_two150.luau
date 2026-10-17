--!nocheck
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
local base = FP.CONFIG.epoch + 2000 * I
for _, kx in { "out", "back" } do
	for _, ky in { "out", "back" } do
		local n, busy, sum, cnt = 0, 0, 0, 0
		local T0 = base
		while T0 < base + I do
			local off = 0
			while off <= 200 do
				local dx = JP.schedule(kx, 1, T0, {}, JP.CONFIG.maxDelayEmpty)
				local wx = JP.absWindows(JP.timeline(kx, 1, dx), T0)
				local dy, cy = JP.schedule(ky, 2, T0 + off, wx, tonumber(args[2]) or JP.CONFIG.maxDelay)
				n += 1
				if not cy then busy += 1 else sum += dy; cnt += 1 end
				off += 10
			end
			T0 += 17
		end
		print(string.format("first %s, second %s: %d pairs, RUNWAY_BUSY %d (%.0f%%), mean delay when clear %.0f", kx, ky, n, busy, 100 * busy / n, sum / math.max(1, cnt)))
	end
end
