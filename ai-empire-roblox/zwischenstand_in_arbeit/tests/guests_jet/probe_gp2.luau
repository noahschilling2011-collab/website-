--!nocheck
local M = require("../../harness/mock")
local GEN = "../../harness/.gen_gj"
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
M.loadTree(manifest, sources)
M.quiet = true
local RS = M.game.ReplicatedStorage
local GP = M.require(RS.Shared.GuestPlan)
for _, i in { 11, 12 } do
	local a = GP.homeDepartures(10)[i]
	for _, s in a.segs do
		local len = s.path and GP.pathLength(s.path) or 0
		print(a.id, s.kind, string.format("%.1f %.0f studs", s.t1 - s.t0, len), s.path and (tostring(s.path[1]) .. " -> " .. tostring(s.path[#s.path])) or "")
	end
end
