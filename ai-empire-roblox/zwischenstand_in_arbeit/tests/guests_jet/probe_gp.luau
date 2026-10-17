--!nocheck
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_gj")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
M.loadTree(manifest, sources)
M.quiet = true
local RS = M.game.ReplicatedStorage
local GP = M.require(RS.Shared.GuestPlan)
local FP = M.require(RS.Shared.FlightPlan)
local foot, top = GP.pmStairs()
print("pmStairs foot", foot, "top", top)
print("home seats", #GP.HOME_SEATS, "pm seats", #GP.PM_SEATS, "bf", #GP.BREAKFAST_SEATS, "lounge", #GP.LOUNGE_SEATS)
for _, a in GP.homeDepartures(10) do
	local t0, t1 = GP.span(a)
	local B0 = FP.legStart("out", 10)
	local sitT
	for _, s in a.segs do if s.kind == "sit" then sitT = string.format("%.0f..%.0f", s.t0 - B0, s.t1 - B0) end end
	print(a.id, string.format("%.0f..%.0f", t0 - B0, t1 - B0), "sit", sitT, #a.segs)
end
for _, a in GP.pmDepartures(10) do
	local t0, t1 = GP.span(a)
	local B0 = FP.legStart("back", 10)
	local last = a.segs[#a.segs]
	print(a.id, string.format("%.0f..%.0f", t0 - B0, t1 - B0), last.kind, #a.segs)
end
for _, a in GP.pmArrivals(10) do local t0, t1 = GP.span(a); local D0 = FP.legStart("out", 10) + FP.leg("out").phases.deboarding.t0; print(a.id, string.format("%.0f..%.0f", t0 - D0, t1 - D0)) end
for g = 1, 12 do
	for _, a in GP.slotDay(7, g, 100) do
		local s = {}
		for _, sg in a.segs do table.insert(s, string.format("%s%.0f-%.0f", sg.kind:sub(1, 2), sg.t0, sg.t1)) end
		print("slot", g, a.role, table.concat(s, " "))
	end
end
print("inHouse night", GP.inHouse(7, 12, 100, 1100), "morning", GP.inHouse(7, 12, 100, 10), "noon", GP.inHouse(7, 12, 100, GP.sOfHour(12)))
