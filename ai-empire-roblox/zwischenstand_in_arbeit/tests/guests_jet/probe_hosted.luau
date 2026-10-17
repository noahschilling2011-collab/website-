--!nocheck
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_gj")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
M.loadTree(manifest, sources)
M.quiet = true
local RS = M.game.ReplicatedStorage
local GP = M.require(RS.Shared.GuestPlan)
local Ops = M.require(RS.Shared.CompanyOps)
for d = 700, 702 do
	for g = 8, 9 do
		for _, a in GP.slotDay(4242, g, d) do
			local s = a.id .. " " .. a.role
			for _, sg in a.segs do s = s .. string.format(" [%s %s %.1fh-%.1fh]", sg.kind, tostring(sg.pose), Ops.hour(sg.t0), Ops.hour(sg.t1)) end
			print(s)
		end
	end
end
local cnt = {}
for g = 1, 12 do
	local n = 0
	for d = 700, 799 do if GP.u("eve:4242:" .. g .. ":" .. d) < 0.74 then n += 1 end end
	table.insert(cnt, g .. "=" .. n)
end
print("eveningWant per slot over 100 days:", table.concat(cnt, " "))
local ev = {}
for g = 1, 12 do
	local n = 0
	for d = 700, 799 do
		for _, a in GP.slotDay(4242, g, d) do for _, sg in a.segs do if sg.pose == "relax" and sg.t0 >= GP.sOfHour(18) then n += 1 end end end
	end
	table.insert(ev, g .. "=" .. n)
end
print("evenings per slot over 100 days:", table.concat(ev, " "))
