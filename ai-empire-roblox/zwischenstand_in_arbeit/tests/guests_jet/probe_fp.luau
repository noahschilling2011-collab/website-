--!nocheck
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_gj")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
M.loadTree(manifest, sources)
M.quiet = true
local RS = M.game.ReplicatedStorage
local FP = M.require(RS.Shared.FlightPlan)
local CityPlan = M.require(RS.Shared.Config.CityPlan)
print("interval", FP.interval(), "GROUND", CityPlan.GROUND, "ROAD_TOP", CityPlan.ROAD_TOP)
for _, dir in {"out","back"} do
  local leg = FP.leg(dir)
  local s = dir.." dur="..string.format("%.1f",leg.duration)
  for _, n in FP.PHASES do local ph=leg.phases[n]; if ph then s=s..string.format(" %s=%.1f..%.1f",n,ph.t0,ph.t1) end end
  print(s)
end
print("slots", table.concat(FP.ambientSlots(), ","))
local Ops = M.require(RS.Shared.CompanyOps)
print("hour 0", Ops.hour(0), Ops.hour(225), Ops.hour(900), Ops.hour(975), Ops.hour(1199))
