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
	local function r2(v) return math.floor(v * 100 + 0.5) / 100 end
	local function out(leg, plot, mesh)
		local pts = {}
		for i, p in leg.pts do pts[i] = { r2(p.X), r2(p.Y), r2(p.Z) } end
		-- playback poses (what DriveController shows): every 2 studs with the look's wheelbase (mesh = the imported
		-- ExecutiveLimo: wheelbase 18.10, 25.76 x 7.36)
		local limo = string.sub(leg.from, 1, 3) == "pm_" or string.sub(leg.to, 1, 3) == "pm_"
		local wb = if mesh then 18.10 elseif limo then Drive.WHEELBASE.limo else Drive.WHEELBASE.fleet
		local cfs = {}
		local s = 0
		while true do
			local cf = Drive.poseAtDist(leg, math.min(s, leg.len), wb)
			local l, u = cf.LookVector, cf.UpVector
			table.insert(cfs, { r2(cf.X), r2(cf.Y), r2(cf.Z), r2(l.X * 1000) / 1000, r2(l.Y * 1000) / 1000, r2(l.Z * 1000) / 1000, r2(u.X * 1000) / 1000, r2(u.Y * 1000) / 1000, r2(u.Z * 1000) / 1000 })
			if s >= leg.len then break end
			s += 2
		end
		rprint("@@LEG " .. HS:JSONEncode({ key = leg.key .. (if mesh then "#mesh" else ""), from = leg.from, to = leg.to, plot = plot, len = leg.len, dur = leg.dur, pts = pts, cfs = cfs, limo = limo,
			length = if mesh then 25.76 else nil, width = if mesh then 7.36 else nil }))
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
				if leg then out(leg, nil); out(leg, nil, true) else rprint("NOLEG", a.id, b.id, err); bad += 1 end
			end
		end
	end
	rprint("NOLEG count", bad)
end
setfenv(body, M.envFor(nil))
local ok, res = M.runMain(body, { timeout = 600 })
if not ok then rprint("CRASH " .. tostring(res)) end
