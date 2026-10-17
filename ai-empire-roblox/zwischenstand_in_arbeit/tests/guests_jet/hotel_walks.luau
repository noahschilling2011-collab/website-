--!nocheck
-- guests_jet: prints every hotel-guest walk (GuestPlan.hotelWalksForTests, building-local) as WALK lines for
-- tests/guests_jet/hotel_paths.py. Run: ../../tools/luau hotel_walks.luau -a .gen_gj > walks.txt
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_gj")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
M.loadTree(manifest, sources)
M.quiet = true
local GP = M.require(M.game.ReplicatedStorage.Shared.GuestPlan)
for _, w in GP.hotelWalksForTests() do
	local parts = { "WALK", w.name, string.format("%.2f", w.radius), string.format("%.2f", w.trimStart or 0), string.format("%.2f", w.trimEnd or 0), tostring(#w.path) }
	for _, p in w.path do table.insert(parts, string.format("%.3f %.3f %.3f", p.X, p.Y, p.Z)) end
	print(table.concat(parts, " "))
end
