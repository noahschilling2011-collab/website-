--!nocheck
-- probe: the jet's field windows, the shuttle / ambient windows, and how often JP.schedule finds a clear delay
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
for _, kind in { "out", "back", "ferry" } do
	for slot = 1, 2 do
		local tl = JP.timeline(kind, slot, 0)
		local s = kind .. slot .. string.format(" dur=%.0f", tl.duration)
		for _, w in JP.windows(tl) do s = s .. string.format("  %s %.1f..%.1f (%.0f)", w.field, w.a, w.b, w.b - w.a) end
		print(s)
	end
end
local base = FP.CONFIG.epoch + 1000 * I
for _, f in { "home", "pm", "rwy" } do
	local s = f .. ":"
	for _, w in JP.trafficWindows(f, base, base + I) do s = s .. string.format(" %.0f..%.0f", w[1] - base, w[2] - base) end
	print(s)
end
for _, kind in { "out", "back", "ferry" } do
	local hist = { [0] = 0 }
	local n, unclear, sum, maxd = 0, 0, 0, 0
	local T = base
	while T < base + 2 * I do
		local d, ok = JP.schedule(kind, 1, T, {}, JP.CONFIG.maxDelayEmpty)
		n += 1
		if not ok then unclear += 1 else sum += d; maxd = math.max(maxd, d) end
		local b = if not ok then "X" elseif d <= 30 then "<=30" elseif d <= 90 then "<=90" elseif d <= 150 then "<=150" elseif d <= 300 then "<=300" else "<=600"
		hist[b] = (hist[b] or 0) + 1
		T += 3
	end
	local s = string.format("%s: %d starts, unclear %d, mean %.1f, max %d |", kind, n, unclear, sum / math.max(1, n - unclear), maxd)
	for _, b in { "<=30", "<=90", "<=150", "<=300", "<=600", "X" } do s = s .. " " .. b .. "=" .. (hist[b] or 0) end
	print(s)
end
