--!nocheck
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_gj")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
M.loadTree(manifest, sources)
M.quiet = true
local RS = M.game.ReplicatedStorage
local JP = M.require(RS.Shared.JetPlan)
for _, kind in {"out","back","ferry"} do
  for slot=1,2 do
    local tl = JP.timeline(kind, slot, 0)
    local s = kind..slot.." dur="..string.format("%.1f",tl.duration)
    for _, n in JP.PHASES do local ph=tl.phases[n]; if ph then s=s..string.format(" %s=%.1f..%.1f",n,ph.t0,ph.t1) end end
    print(s)
  end
end
local T=1.7e9
local ds={}
for i=0,40 do local d,ok=JP.schedule("out",1,T+i*37); table.insert(ds,d..(ok and "" or "!")) end
print("delays out", table.concat(ds," "))
ds={}
for i=0,40 do local d,ok=JP.schedule("back",1,T+i*37); table.insert(ds,d..(ok and "" or "!")) end
print("delays back", table.concat(ds," "))
local tl=JP.timeline("out",1,0)
for tau=0,tl.duration,10 do local p=JP.pose(tl,tau); print(string.format("%5.0f %-10s %8.1f %6.1f %8.1f spd %5.1f", tau, p.phase, p.cf.X, p.cf.Y, p.cf.Z, p.speed)) end
