--!strict
-- Throwaway integration test: every Layout wall/door + room floors/ceilings for one tier via ArchKit.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Plan = require(ReplicatedStorage.Shared.Config.BuildingPlan)
local Layout = require(ReplicatedStorage.Shared.BuildingLayout)
local Kit = require(script.Parent.ArchKit)
local S = {}
function S.build(cf: CFrame, session: any, accent: Color3): Model
	Kit.resetStats()
	local tier = session.data.empire.office
	local office = Instance.new("Model")
	office.Name = "Office"
	local wallsF = Instance.new("Folder"); wallsF.Name = "Walls"; wallsF.Parent = office
	local doorsF = Instance.new("Folder"); doorsF.Name = "Doors"; doorsF.Parent = office
	local roomsF = Instance.new("Folder"); roomsF.Name = "Rooms"; roomsF.Parent = office
	local wallParts, doorParts = 0, 0
	for _, level in Plan.levels(tier) do
		local y = Plan.levelY(level)
		local lm = Instance.new("Model"); lm.Name = "Level_" .. level; lm.Parent = wallsF
		local segs = Layout.walls(tier, level)
		local ext = Kit.wallExtents(segs)
		for _, seg in segs do
			local before = Kit.stats.parts
			local e = ext[seg]
			Kit.wall(lm, cf, seg, y, 1001, doorsF, { extend1 = e[1], extend2 = e[2] })
			wallParts += Kit.stats.parts - before
		end
	end
	-- exterior doors too (facade agent would call Kit.door directly)
	for _, d in Layout.doors(tier) do
		if d.builder == "exterior" and d.kind ~= "opening" then
			Kit.door(doorsF, cf, d, 1001)
		end
	end
	local lightsBefore = Kit.stats.lights
	local finishParts = 0
	for _, r in Plan.rooms(tier) do
		if r.outdoor then continue end
		local before = Kit.stats.parts
		local m = Instance.new("Model"); m.Name = r.id; m.Parent = roomsF
		local y = Plan.levelY(r.level)
		local finish = if r.kind == "wc" or r.kind == "restrooms" or r.kind == "showers" then "tile" elseif r.mood == "founder" then "oak" elseif r.mood == "tech" then "rubber" else "carpet"
		Kit.floor(m, cf, r, y, finish)
		if r.kind ~= "lobby" and r.kind ~= "atrium" and r.kind ~= "stair" and r.kind ~= "garage" and r.kind ~= "compute" then
			Kit.ceiling(m, cf, r, y, if r.mood == "founder" then "timber" else "acoustic", r.mood or "neutral")
		end
		Kit.accessVolume(m, cf, r)
		finishParts += Kit.stats.parts - before
	end
	print(string.format("[plan] tier %d: wall+door parts %d, room finish parts %d, ceiling lights %d, total parts %d", tier, wallParts, finishParts, Kit.stats.lights - lightsBefore, Kit.stats.parts))
	return office
end
return S
