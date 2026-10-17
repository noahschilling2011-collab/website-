--!nocheck
-- hotelpolish copy of harness/build_dump.luau (tests/hotelpolish/run.sh: out/gui_tier2.json) that also dumps GUI layout (Frame/TextLabel position, size, colours,
-- UICorner, SurfaceGui pixels per stud / light influence) for agents/hotelpolish/guishots.py.
-- Builds the headquarters for one tier inside the mock and dumps every instance.
-- Usage: tools/luau harness/build_dump.luau -a --tier 2 [--local|--plot|--cf x,y,z,yawDeg] [--settle 1] [--quiet] [--gen DIR]
--        [--module ServerScriptService.Server.Services.HeadquartersDesign] [--no-parent] [--allow-thread-errors]
-- Output (stdout): log lines, then one "@@D {json}" line per instance and a final "@@M {json}" meta line.
-- run.sh / harness/split_dump.py turn that into out/dump_tierN.json.
local T0 = os.clock()
local M = require("../../harness/mock")
local rawargs = { ... }
local gen = "."
for k = 1, #rawargs - 1 do if rawargs[k] == "--gen" then gen = rawargs[k + 1] end end
local manifest = require("../../harness/" .. gen .. "/manifest")
local sources = require("../../harness/" .. gen .. "/sources")
M.loadTree(manifest, sources)
local KEY, JSON, G = M.KEY, M.JSON, M.G
local game = M.game
local num, str = JSON.num, JSON.str
local fmt, tconcat, tinsert = string.format, table.concat, table.insert

-- arguments -----------------------------------------------------------------------
local args = { ... }
local opt = { tier = 1, mode = "local", settle = 1, module = "ServerScriptService.Server.Services.HeadquartersDesign", parent = true, threadErrorsFatal = true }
local i = 1
while i <= #args do
	local a = args[i]
	if a == "--tier" then i += 1; opt.tier = tonumber(args[i])
	elseif a == "--local" then opt.mode = "local"
	elseif a == "--plot" then opt.mode = "plot"
	elseif a == "--cf" then i += 1; opt.mode = "custom"; opt.cf = args[i]
	elseif a == "--settle" then i += 1; opt.settle = tonumber(args[i])
	elseif a == "--quiet" then M.quiet = true
	elseif a == "--module" then i += 1; opt.module = args[i]
	elseif a == "--no-parent" then opt.parent = false
	elseif a == "--allow-thread-errors" then opt.threadErrorsFatal = false
	elseif a == "--gen" then i += 1 -- handled above
	else error("unknown argument " .. tostring(a), 0) end
	i += 1
end
assert(opt.tier and opt.tier >= 0 and opt.tier <= 4, "--tier must be 0..4 (0 = garage stage)")

local function findByPath(path)
	local cur = game
	for seg in path:gmatch("[^%.]+") do
		local nx = cur:FindFirstChild(seg)
		if not nx then error("module path not found: " .. path .. " (missing '" .. seg .. "')", 0) end
		cur = nx
	end
	return cur
end

-- build -----------------------------------------------------------------------------
local timings = {}
local built = {}
local function body()
	local CFrame, Vector3, Color3 = G.CFrame, G.Vector3, G.Color3
	local tReq = os.clock()
	local Design = M.require(findByPath(opt.module))
	local Template = M.require(findByPath("ServerScriptService.Server.Lib.Template"))
	local EmpireConfig = M.require(findByPath("ReplicatedStorage.Shared.Config.EmpireConfig"))
	local okCC, CompanyConfig = pcall(M.require, findByPath("ReplicatedStorage.Shared.Config.CompanyConfig"))
	timings.require = os.clock() - tReq

	local data = Template.new()
	data.company = { name = "Nimbus Labs", logo = "◈", color = "cyan", spec = "general", reputation = 10, foundedAt = 0 }
	-- save office index of this plan tier (BuildingPlan.officeForTier: identity before DATA_VERSION 6, +1 after)
	local PlanModule = M.require(findByPath("ReplicatedStorage.Shared.Config.BuildingPlan"))
	data.empire.office = if PlanModule.officeForTier then PlanModule.officeForTier(opt.tier) else opt.tier
	local cap
	local planTier = nil
	if opt.tier == 0 and (PlanModule.OFFICE_TIER_OFFSET or 0) == 0 then
		-- plan tier 0 (garage stage): forced through session.planTier (HeadquartersDesign.tierFor), the
		-- save keeps a valid office index; staff = the garage's team desks (BuildingPlan.GARAGE_STAGE)
		local Plan = M.require(findByPath("ReplicatedStorage.Shared.Config.BuildingPlan"))
		data.empire.office = 1
		planTier = 0
		cap = Plan.GARAGE_STAGE.staff
	else
		cap = EmpireConfig.OFFICES[data.empire.office].staff
	end
	local roles = { "researcher", "engineer", "curator", "marketer" }
	local split = {}
	for k, r in roles do
		local n = math.floor(cap / #roles) + (if k <= cap % #roles then 1 else 0)
		data.empire.employees[r] = n
		split[r] = n
	end
	built.staff = split
	built.staffCap = cap
	local session = { userId = 1001, player = { Name = "Tester", DisplayName = "Tester", UserId = 1001 }, data = data,
		live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} }, planTier = planTier }

	local accent = Color3.fromRGB(120, 154, 129)
	if okCC and CompanyConfig and CompanyConfig.getColor then
		local def = CompanyConfig.getColor("cyan")
		if def then accent = Color3.fromRGB(def.rgb[1], def.rgb[2], def.rgb[3]) end
	end
	built.accent = accent

	local cf
	if opt.mode == "plot" then
		cf = CFrame.lookAt(Vector3.new(160, 24, 252), Vector3.new(160, 24, 0))
	elseif opt.mode == "custom" then
		local x, y, z, yaw = opt.cf:match("^([^,]+),([^,]+),([^,]+),?([^,]*)$")
		assert(x, "--cf expects x,y,z[,yawDeg]")
		cf = CFrame.new(tonumber(x), tonumber(y), tonumber(z)) * CFrame.Angles(0, math.rad(tonumber(yaw) or 0), 0)
	else
		cf = CFrame.new(0, 0, 0)
	end
	built.cf = cf

	local tb = os.clock()
	local office = Design.build(cf, session, accent)
	timings.build = os.clock() - tb
	if not M.isInstance(office) then error("Design.build did not return an Instance (got " .. M.typeof(office) .. ")", 0) end
	if opt.parent then
		-- same as PlotService.claim: the office lives under workspace.Plots.Plot_01 after build
		local plots = Instance.new("Folder"); plots.Name = "Plots"; plots.Parent = G.workspace
		local plot = Instance.new("Model"); plot.Name = "Plot_01"; plot:SetAttribute("CampusCFrame", cf); plot.Parent = plots
		office.Parent = plot
	end
	return office
end
setfenv(body, M.envFor(nil))
local ok, res, status = M.runMain(body, { timeout = 60 })
if not ok then
	print("[harness] BUILD FAILED (" .. tostring(status) .. ") tier " .. opt.tier)
	print(tostring(res))
	error("build failed", 0)
end
local office = res
local settleStatus = M.settle(opt.settle)
timings.total_build = os.clock() - T0

-- serialisation helpers -------------------------------------------------------------------
local typeof = M.typeof
local function cfArr(c)
	local t = {}
	for k = 1, 12 do t[k] = JSON.nump(c[k]) end
	return "[" .. tconcat(t, ",") .. "]"
end
local function v3Arr(v) return "[" .. num(v.X) .. "," .. num(v.Y) .. "," .. num(v.Z) .. "]" end
local function c3Arr(c) return "[" .. num(c.R * 255) .. "," .. num(c.G * 255) .. "," .. num(c.B * 255) .. "]" end
local function value(v)
	local t = typeof(v)
	if t == "number" then return num(v) end
	if t == "boolean" then return v and "true" or "false" end
	if t == "string" then return str(v) end
	if t == "nil" then return "null" end
	if t == "Vector3" then return '{"Vector3":' .. v3Arr(v) .. "}" end
	if t == "CFrame" then return '{"CFrame":' .. cfArr(v) .. "}" end
	if t == "Color3" then return '{"Color3":' .. c3Arr(v) .. "}" end
	if t == "EnumItem" then return '{"EnumItem":' .. str(tostring(v)) .. "}" end
	if t == "Vector2" then return '{"Vector2":[' .. num(v.X) .. "," .. num(v.Y) .. "]}" end
	if t == "UDim2" then return '{"UDim2":[' .. num(v.X.Scale) .. "," .. num(v.X.Offset) .. "," .. num(v.Y.Scale) .. "," .. num(v.Y.Offset) .. "]}" end
	if t == "UDim" then return '{"UDim":[' .. num(v.Scale) .. "," .. num(v.Offset) .. "]}" end
	if t == "NumberRange" then return '{"NumberRange":[' .. num(v.Min) .. "," .. num(v.Max) .. "]}" end
	if t == "BrickColor" then return '{"BrickColor":' .. str(v.Name) .. "}" end
	if t == "Instance" then return '{"Instance":' .. str(M.fullName(v)) .. "}" end
	return "{" .. str(t) .. ":" .. str(tostring(v)) .. "}"
end
local function enumName(e) return e and e.Name or nil end
-- GUI layout fields (hotelpolish gui_dump: Frames / TextLabels on SurfaceGuis for the preview renders)
local function ud2(u) return "[" .. num(u.X.Scale) .. "," .. num(u.X.Offset) .. "," .. num(u.Y.Scale) .. "," .. num(u.Y.Offset) .. "]" end
function guiFields(f, p)
	if p.Position then tinsert(f, '"pos":' .. ud2(p.Position)) end
	if p.Size then tinsert(f, '"gsize":' .. ud2(p.Size)) end
	if p.AnchorPoint then tinsert(f, '"anchor":[' .. num(p.AnchorPoint.X) .. "," .. num(p.AnchorPoint.Y) .. "]") end
	if p.SizeConstraint then tinsert(f, '"sizeConstraint":' .. str(enumName(p.SizeConstraint) or "RelativeXY")) end
	if p.BackgroundColor3 then tinsert(f, '"bg":' .. c3Arr(p.BackgroundColor3)) end
	tinsert(f, '"bgT":' .. num(if p.BackgroundTransparency ~= nil then p.BackgroundTransparency else 0))
	if p.ZIndex then tinsert(f, '"z":' .. num(p.ZIndex)) end
	tinsert(f, '"visible":' .. tostring(p.Visible ~= false))
end

-- dump --------------------------------------------------------------------------------------
local td = os.clock()
local ids = {}
local counter = 0
local counts = { instances = 0, parts = 0, collidable = 0, models = 0, prompts = 0, seats = 0, lights = 0 }
local classCount = {}
local lines = 0
local function emit(s)
	print("@@D " .. s)
	lines += 1
end
local function rec(inst, parentId, path)
	counter += 1
	local id = counter
	ids[inst] = id
	local st = inst[KEY]
	local info = st.info
	local p = st.props
	local name = p.Name
	local mypath = if path == "" then name else path .. "/" .. name
	counts.instances += 1
	classCount[st.cls] = (classCount[st.cls] or 0) + 1
	local f = {
		'"id":' .. id,
		'"parent":' .. (parentId and tostring(parentId) or "null"),
		'"path":' .. str(mypath),
		'"parentPath":' .. (if path == "" then "null" else str(path)),
		'"class":' .. str(st.cls),
		'"name":' .. str(name),
	}
	-- attributes (sorted)
	local keys = {}
	for k in st.attrs do tinsert(keys, k) end
	if #keys > 0 then
		table.sort(keys)
		local a = {}
		for _, k in keys do tinsert(a, str(k) .. ":" .. value(st.attrs[k])) end
		tinsert(f, '"attrs":{' .. tconcat(a, ",") .. "}")
	end
	if st.tags then
		local tl = M.getTags(inst)
		local q = {}
		for _, t in tl do tinsert(q, str(t)) end
		tinsert(f, '"tags":[' .. tconcat(q, ",") .. "]")
	end
	local isa = info.isa
	if isa.BasePart then
		counts.parts += 1
		if p.CanCollide then counts.collidable += 1 end
		tinsert(f, '"size":' .. v3Arr(p.Size))
		if st.requestedSize then tinsert(f, '"requestedSize":' .. v3Arr(st.requestedSize)) end
		tinsert(f, '"cframe":' .. cfArr(p.CFrame))
		tinsert(f, '"color":' .. c3Arr(p.Color))
		tinsert(f, '"material":' .. str(enumName(p.Material) or "Plastic"))
		tinsert(f, '"transparency":' .. num(p.Transparency))
		tinsert(f, '"canCollide":' .. tostring(p.CanCollide == true))
		tinsert(f, '"canQuery":' .. tostring(p.CanQuery == true))
		tinsert(f, '"canTouch":' .. tostring(p.CanTouch == true))
		tinsert(f, '"anchored":' .. tostring(p.Anchored == true))
		tinsert(f, '"collisionGroup":' .. str(p.CollisionGroup or "Default"))
		if p.Massless then tinsert(f, '"massless":true') end
		if p.CastShadow == false then tinsert(f, '"castShadow":false') end
		if isa.Part then tinsert(f, '"shape":' .. str(enumName(p.Shape) or "Block")) end
		if isa.Seat or isa.VehicleSeat then
			counts.seats += 1
			tinsert(f, '"disabled":' .. tostring(p.Disabled == true))
		end
		if isa.MeshPart then tinsert(f, '"meshId":' .. str(p.MeshId or "")) end
	elseif isa.Model then
		counts.models += 1
		local pp = p.PrimaryPart
		tinsert(f, '"pivot":' .. cfArr(M.getPivot(inst)))
		if st.pivotSet then tinsert(f, '"worldPivotSet":true') end
		if pp then tinsert(f, '"primaryPartPath":' .. str(M.fullName(pp))) end
	elseif isa.ProximityPrompt then
		counts.prompts += 1
		tinsert(f, '"actionText":' .. str(p.ActionText or ""))
		tinsert(f, '"objectText":' .. str(p.ObjectText or ""))
		tinsert(f, '"maxActivationDistance":' .. num(p.MaxActivationDistance or 10))
		tinsert(f, '"holdDuration":' .. num(p.HoldDuration or 0))
		tinsert(f, '"requiresLineOfSight":' .. tostring(p.RequiresLineOfSight ~= false))
		tinsert(f, '"enabled":' .. tostring(p.Enabled ~= false))
	elseif isa.TextLabel or isa.TextButton or isa.TextBox then
		tinsert(f, '"text":' .. str(p.Text or ""))
		guiFields(f, p)
		if p.TextColor3 then tinsert(f, '"textColor":' .. c3Arr(p.TextColor3)) end
		tinsert(f, '"textScaled":' .. tostring(p.TextScaled == true))
		if p.TextSize then tinsert(f, '"textSize":' .. num(p.TextSize)) end
		if p.TextXAlignment then tinsert(f, '"alignX":' .. str(enumName(p.TextXAlignment) or "Center")) end
		if p.Font then tinsert(f, '"font":' .. str(enumName(p.Font) or "")) end
	elseif isa.Frame then
		guiFields(f, p)
	elseif isa.UICorner then
		local cr = p.CornerRadius
		if cr then tinsert(f, '"corner":[' .. num(cr.Scale) .. "," .. num(cr.Offset) .. "]") end
	elseif isa.SurfaceGui then
		tinsert(f, '"face":' .. str(enumName(p.Face) or "Front"))
		tinsert(f, '"pps":' .. num(p.PixelsPerStud or 50))
		tinsert(f, '"lightInfluence":' .. num(p.LightInfluence or 1))
		tinsert(f, '"maxDistance":' .. num(p.MaxDistance or 0))
	elseif isa.Light then
		counts.lights += 1
		tinsert(f, '"range":' .. num(p.Range or 0))
		tinsert(f, '"brightness":' .. num(p.Brightness or 1))
		tinsert(f, '"lightColor":' .. c3Arr(p.Color))
		tinsert(f, '"shadows":' .. tostring(p.Shadows == true))
		tinsert(f, '"enabled":' .. tostring(p.Enabled ~= false))
		if isa.SpotLight or isa.SurfaceLight then
			tinsert(f, '"face":' .. str(enumName(p.Face) or "Front"))
			tinsert(f, '"angle":' .. num(p.Angle or 90))
		end
	elseif isa.PathfindingModifier then
		tinsert(f, '"label":' .. str(p.Label or ""))
		tinsert(f, '"passThrough":' .. tostring(p.PassThrough == true))
	elseif isa.JointInstance or isa.WeldConstraint then
		if p.Part0 then tinsert(f, '"part0":' .. str(M.fullName(p.Part0))) end
		if p.Part1 then tinsert(f, '"part1":' .. str(M.fullName(p.Part1))) end
	elseif isa.SpecialMesh then
		tinsert(f, '"meshType":' .. str(enumName(p.MeshType) or "Head"))
		if p.Scale then tinsert(f, '"scale":' .. v3Arr(p.Scale)) end
	elseif isa.Attachment then
		tinsert(f, '"cframe":' .. cfArr(p.CFrame))
	elseif isa.Sound then
		tinsert(f, '"soundId":' .. str(p.SoundId or ""))
	elseif isa.Decal then
		tinsert(f, '"texture":' .. str(p.Texture or ""))
		tinsert(f, '"face":' .. str(enumName(p.Face) or "Front"))
	elseif isa.ParticleEmitter then
		tinsert(f, '"enabled":' .. tostring(p.Enabled ~= false))
	end
	emit("{" .. tconcat(f, ",") .. "}")
	for _, c in st.children do rec(c, id, mypath) end
end
rec(office, nil, "")
timings.dump = os.clock() - td

-- meta ---------------------------------------------------------------------------------------
local function arr(list, f)
	local t = {}
	for _, v in list do tinsert(t, f(v)) end
	return "[" .. tconcat(t, ",") .. "]"
end
local stubList = {}
for k, n in M.stats.stubs do tinsert(stubList, str(k) .. ":" .. n) end
table.sort(stubList)
local pairsList = {}
for k, v in M.collision.pairs do tinsert(pairsList, str(k) .. ":" .. tostring(v)) end
table.sort(pairsList)
local terr = {}
for _, op in M.terrainOps do
	local parts = { '"op":' .. str(op.op) }
	local a = {}
	for k = 1, #op do tinsert(a, value(op[k])) end
	tinsert(parts, '"args":[' .. tconcat(a, ",") .. "]")
	tinsert(terr, "{" .. tconcat(parts, ",") .. "}")
end
local classList = {}
for k, n in classCount do tinsert(classList, str(k) .. ":" .. n) end
table.sort(classList)
local staff = {}
for k, n in built.staff do tinsert(staff, str(k) .. ":" .. n) end
table.sort(staff)
local meta = {
	'"tier":' .. opt.tier,
	'"mode":' .. str(opt.mode),
	'"module":' .. str(opt.module),
	'"campusCFrame":' .. cfArr(built.cf),
	'"accent":' .. c3Arr(built.accent),
	'"staff":{' .. tconcat(staff, ",") .. "}",
	'"staffCap":' .. built.staffCap,
	'"counts":{' .. (function()
		local t = {}
		for k, v in counts do tinsert(t, str(k) .. ":" .. v) end
		table.sort(t)
		return tconcat(t, ",")
	end)() .. "}",
	'"classes":{' .. tconcat(classList, ",") .. "}",
	'"timings":{' .. (function()
		local t = {}
		for k, v in timings do tinsert(t, str(k) .. ":" .. num(v)) end
		table.sort(t)
		return tconcat(t, ",")
	end)() .. "}",
	'"mock":{"threadErrors":' .. M.stats.errors .. ',"warnings":' .. M.stats.warnings .. ',"stubs":{' .. tconcat(stubList, ",") .. '},"schedulerSteps":' .. M.Sched.steps .. ',"virtualTime":' .. num(M.Sched.now) .. ',"settle":' .. str(tostring(settleStatus)) .. "}",
	'"collisionGroups":{"groups":' .. arr(M.collision.groups, str) .. ',"pairs":{' .. tconcat(pairsList, ",") .. "}}",
	'"terrainOps":[' .. tconcat(terr, ",") .. "]",
	'"modules":' .. arr(M.modulesLoaded, function(m) return "{" .. '"name":' .. str(m.name) .. ',"file":' .. str(m.file or "") .. ',"seconds":' .. num(m.seconds) .. "}" end),
	'"instances":' .. lines,
}
print("@@M {" .. tconcat(meta, ",") .. "}")
print(fmt("[harness] tier %d (%s): %d instances, %d parts (%d collidable), require %.2fs, build %.2fs, dump %.2fs, thread errors %d",
	opt.tier, opt.mode, counts.instances, counts.parts, counts.collidable, timings.require or 0, timings.build or 0, timings.dump, M.stats.errors))
if M.stats.errors > 0 and opt.threadErrorsFatal then
	error(fmt("%d error(s) in spawned threads (see [mock:error] lines); use --allow-thread-errors to ignore", M.stats.errors), 0)
end
