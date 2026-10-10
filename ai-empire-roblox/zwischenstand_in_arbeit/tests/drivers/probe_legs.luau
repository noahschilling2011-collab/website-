--!nocheck
-- dev probe: legs of DrivePlan -> JSON lines (@@LEG {...}) for the clearance check (clearance.py)
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_drivers")
local M = require("../../harness/mock")
local rprint = print
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local function body()
	local RS = M.game.ReplicatedStorage
	local Drive = M.require(RS.Shared.DrivePlan)
	local HS = M.game:GetService("HttpService")
	local function out(leg, plot)
		local pts = {}
		for i, p in leg.pts do pts[i] = { math.floor(p.X * 100) / 100, math.floor(p.Y * 100) / 100, math.floor(p.Z * 100) / 100 } end
		rprint("@@LEG " .. HS:JSONEncode({ key = leg.key, from = leg.from, to = leg.to, plot = plot, len = leg.len, dur = leg.dur, pts = pts }))
	end
	local bad = 0
	for _, plot in { tonumber(args[2]) or 1, tonumber(args[3]) or 7 } do
		local list = Drive.places("home", plot)
		for _, a in list do
			for _, b in list do
				if a.id ~= b.id then
					local leg, err = Drive.leg(a.id, b.id, plot)
					if leg then out(leg, plot) else rprint("NOLEG", a.id, b.id, err); bad += 1 end
				end
			end
		end
		local leg = Drive.leg("hq_entrance", "hq_garage", plot, "drop"); if leg then out(leg, plot) end
	end
	local pm = Drive.places("abroad")
	for _, a in pm do
		for _, b in pm do
			if a.id ~= b.id then
				local leg, err = Drive.leg(a.id, b.id)
				if leg then out(leg, nil) else rprint("NOLEG", a.id, b.id, err); bad += 1 end
			end
		end
	end
	rprint("NOLEG count", bad)
end
setfenv(body, M.envFor(nil))
local ok, res = M.runMain(body, { timeout = 600 })
if not ok then rprint("CRASH " .. tostring(res)) end
