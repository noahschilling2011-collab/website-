--!nocheck
-- probe: pilot seat candidates vs the bizjet cockpit skin / glass (same criteria as test_jet's seat test)
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_gj")
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local G = M.G
local CFrame, Vector3 = G.CFrame, G.Vector3
local RS, S = M.game.ReplicatedStorage, M.game.ServerScriptService.Server.Services
local JP = M.require(RS.Shared.JetPlan)
local Aircraft = M.require(RS.Shared.AircraftModel)
local Rig = M.require(S.EmployeeRigDesign)
local jm = Aircraft.build(nil, CFrame.new(), { kind = JP.KIND, scale = JP.SCALE, lod = "full", name = "SeatTest", airstair = false })
local skins, glass = {}, {}
for _, d in jm:GetDescendants() do
	if d:IsA("BasePart") then
		if d.Name == "CockpitSkin" or d.Name == "CockpitPillar" or d.Name == "WindowSurround" then table.insert(skins, d) end
		if d.Name == "CockpitSideWindow" or d.Name == "Windshield" then table.insert(glass, d) end
	end
end
local function corners(p)
	local out, h = {}, p.Size / 2
	for _, a in { -1, 1 } do for _, b in { -1, 1 } do for _, c in { -1, 1 } do table.insert(out, (p.CFrame * CFrame.new(h.X * a, h.Y * b, h.Z * c)).Position) end end end
	return out
end
local function sep(a, b)
	local ax = { a.CFrame.RightVector, a.CFrame.UpVector, a.CFrame.LookVector, b.CFrame.RightVector, b.CFrame.UpVector, b.CFrame.LookVector }
	for i = 1, 3 do for j = 4, 6 do local c = ax[i]:Cross(ax[j]); if c.Magnitude > 1e-4 then table.insert(ax, c.Unit) end end end
	local ca, cb = corners(a), corners(b)
	for _, n in ax do
		local a1, a2, b1, b2 = math.huge, -math.huge, math.huge, -math.huge
		for _, q in ca do local d = q:Dot(n); a1 = math.min(a1, d); a2 = math.max(a2, d) end
		for _, q in cb do local d = q:Dot(n); b1 = math.min(b1, d); b2 = math.max(b2, d) end
		if a2 < b1 + 0.02 or b2 < a1 + 0.02 then return true end
	end
	return false
end
local function probe(x, y, z)
	local mid = Vector3.new(0, y + 1, z)
	local function through(w, q)
		local l, h = w.CFrame:PointToObjectSpace(q), w.Size / 2
		if math.abs(l.Y) > h.Y or math.abs(l.Z) > h.Z or (l.Y + h.Y) / (2 * h.Y) > (l.Z + h.Z) / (2 * h.Z) then return 0 end
		local out = if w.CFrame.RightVector:Dot(w.Position - mid) >= 0 then 1 else -1
		local d = l.X * out - h.X
		return if d > 0.02 and d < 1.5 then d else 0
	end
	local bad, deep, names = 0, 0, {}
	for owner = 1, 40 do
		for _, index in { 9201, 9241 } do
			local seat = CFrame.new(x, y, z)
			local m = Rig.build(M.game.Workspace, owner * 101, index, "pilot", seat, nil)
			local arm = m:FindFirstChild("Left Arm")
			local hidden = { [arm] = true }
			for _, d in m:GetDescendants() do
				local w = if d:IsA("BasePart") then d:FindFirstChildOfClass("WeldConstraint") else nil
				if w and w.Part0 == arm then hidden[d] = true end
			end
			local n = 0
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 1 and not hidden[d] and d.Position.Y > y - 0.9 then
					for _, s in skins do if not sep(d, s) then n += 1; names[d.Name .. "x" .. s.Name] = true end end
					for _, q in corners(d) do for _, g in glass do local dd = through(g, q); if dd > 0 then n += 1; deep = math.max(deep, dd); names[d.Name .. ">" .. g.Name] = true end end end
				end
			end
			if n > 0 then bad += 1 end
			m:Destroy()
		end
	end
	local list = {}
	for k in names do table.insert(list, k) end
	table.sort(list)
	print(string.format("x=%.2f y=%.2f z=%.2f  bad=%d/80 deepest=%.3f  %s", x, y, z, bad, deep, table.concat(list, " ")))
end
for _, c in { { -1.05, 5.75, -16.1 }, { -1.08, 5.75, -16.1 }, { -1.05, 5.8, -16.1 } } do
	probe(c[1], c[2], c[3])
end
