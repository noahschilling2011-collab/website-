--!nocheck
-- drivers package: dumps what DriveController draws at one moment of a REAL ride (client_setup.luau: DriverService +
-- DriveController in the mock) as a harness-style JSON dump for the Blender renders (tests/drivers/render.py).
-- The mock has no physics: rig limbs are solved from their Motor6D / WeldConstraint chains (ctx.solveRigs).
-- usage: ../../tools/luau dump_scene.luau -a .gen_drivers <moment> > out.txt   (moment: hq_post | hq_pickup |
--        hq_board | hq_depot | airport_kerb | ride_city | ride_full | pm_stand | pm_board | pm_depart | field_door)
--   hq_depot: the idle fleet car parked at the depot in B1 (no ride); ride_full: driver + founder + two colleagues on
--   a straight piece of road (seated occupants inside the body); pm_depart: the booked limousine 3 s after it pulled
--   away from bay 1 (no idle limousine drawn inside it); field_door: a field rep standing at CloudDesk's door while
--   the company car waits for him to walk in.
-- Output: "@@DUMP {json}" with {meta, instances}; positions in world studs (plot 1 = the founder's plot).
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_drivers")
local MOMENT = args[2] or "hq_post"
M.loadTree(require(GEN .. "/manifest"), require(GEN .. "/sources"))
M.quiet = true
local G = M.G
local setup = require("./client_setup")
local rprint = print

local function body()
	local Vector3, CFrame = G.Vector3, G.CFrame
	local ctx = setup(M, { stage = 2, company = "Nimbus Labs", color = "cyan" })
	local Drive, Driver = ctx.Drive, ctx.Driver
	local plot = ctx.plot
	ctx.tick(1.1)
	local entrance = ctx.hq(Vector3.new(0, 3, -60))
	local legA = Drive.leg("hq_garage", "hq_entrance", plot.index)
	local extra = {} -- additional models to dump (the founder's own character when he stands outside the car)
	local function book(to)
		ctx.T.now += 5
		local r = ctx.call({ action = "ride", op = "request", to = to })
		assert(r.ok, "request failed: " .. tostring(r.err))
	end
	local function board()
		ctx.stand((Drive.endCF(legA) * CFrame.new(6, 3, 2)).Position)
		local r = ctx.call({ action = "ride", op = "board" })
		assert(r.ok, "board failed: " .. tostring(r.err))
	end
	if MOMENT == "hq_post" then
		ctx.stand(entrance + Vector3.new(-30, 0, -40))
		ctx.camera(entrance + Vector3.new(0, 8, -30), entrance)
	elseif MOMENT == "hq_pickup" or MOMENT == "hq_board" then
		book("airport_departures")
		ctx.tick(Drive.walkAt(ctx.T.now) + legA.dur + 3)
		local stop = Drive.endCF(legA)
		if MOMENT == "hq_board" then
			-- the founder walks up to the rear door
			local at = stop * CFrame.new(5.2, 3, 2.6)
			ctx.stand(at.Position)
			ctx.player.Character:PivotTo(CFrame.lookAt(at.Position, (stop * CFrame.new(0, 3, 2.6)).Position))
			table.insert(extra, ctx.player.Character)
		else
			ctx.stand(entrance)
		end
		ctx.camera(stop.Position + Vector3.new(0, 10, -40), stop.Position)
	elseif MOMENT == "ride_city" then
		book("clouddesk")
		ctx.tick(Drive.walkAt(ctx.T.now) + legA.dur + 2)
		board()
		local legB = Drive.leg("hq_entrance", "clouddesk", plot.index)
		ctx.tick(Drive.BOARD_DELAY + legB.dur * 0.62)
	elseif MOMENT == "airport_kerb" then
		book("airport_departures")
		ctx.tick(Drive.walkAt(ctx.T.now) + legA.dur + 2)
		board()
		local legB = Drive.leg("hq_entrance", "airport_departures", plot.index)
		ctx.tick(Drive.BOARD_DELAY + legB.dur + Driver.ALIGHT + 0.6)
		-- the founder stands at the departures door, the car still at the kerb with the driver
		table.insert(extra, ctx.player.Character)
		local door = Drive.place("airport_departures").door
		ctx.camera(door.Position + Vector3.new(-30, 8, 20), door.Position)
	elseif MOMENT == "hq_depot" then
		local depot = ctx.hq(Drive.HQ.depot)
		ctx.stand(entrance)
		ctx.camera(depot + Vector3.new(-12, 6, -24), depot)
	elseif MOMENT == "ride_full" then
		ctx.stand(entrance)
		ctx.T.now += 5
		local r = Driver.request(ctx.player, { to = "clouddesk", passengers = { { name = "Mia Chen", role = "marketer", seed = 11 }, { name = "Leo Park", role = "engineer", seed = 12 } } })
		assert(r.ok, "request failed: " .. tostring(r.err))
		ctx.tick(Drive.walkAt(ctx.T.now) + legA.dur + 2)
		board()
		local legB = Drive.leg("hq_entrance", "clouddesk", plot.index)
		-- a straight piece of road at speed (like the review's rv_full moment)
		local best = 0.6
		for f = 0.40, 0.95, 0.01 do
			local cfa = Drive.at(legB, legB.dur * f)
			local cfb = Drive.at(legB, legB.dur * f + 1)
			if cfa.LookVector:Dot(cfb.LookVector) > 0.9999 then best = f; break end
		end
		ctx.tick(Drive.BOARD_DELAY + legB.dur * best)
		local car = Drive.at(legB, legB.dur * best)
		ctx.camera(car.Position + Vector3.new(0, 10, -20), car.Position)
	elseif MOMENT == "field_door" then
		local e = ctx.session.data.empire
		e.employees = e.employees or {}
		e.employees.marketer = 1
		e.staffProfiles = { marketer = { { n = "Kai Lund", s = 4444 } } }
		e.deals.tripList = {}
		ctx.tick(1.1)
		table.insert(e.deals.tripList, { client = "helpdesk", kind = "renew", back = e.seconds + 2400, founder = false, hosted = false, crew = 1, left = e.seconds })
		ctx.tick(1.1)
		-- the company driver fetches the rep at the HQ entrance and drives him to CloudDesk; 2 s after the stop he
		-- stands at the door while the car still waits (Driver.FIELD_PAUSE)
		local legE = Drive.leg("hq_entrance", "clouddesk", plot.index)
		ctx.tick(Drive.walkAt(ctx.T.now) + legA.dur + Driver.FIELD_PAUSE + legE.dur + 2)
		local cd = Drive.place("clouddesk")
		ctx.camera(cd.stop.Position + Vector3.new(10, 8, 10), cd.stop.Position)
	elseif MOMENT == "pm_depart" then
		local stand = Drive.place("pm_limo")
		ctx.camera(stand.stop.Position + Vector3.new(20, 10, -30), stand.stop.Position)
		ctx.City.trips[ctx.player.UserId] = { player = ctx.player, state = "abroad", to = "abroad", releaseAt = math.huge }
		ctx.stand(stand.door.Position)
		book("pm_hotel")
		ctx.stand((stand.stop * CFrame.new(5, 3, 4)).Position)
		local r = ctx.call({ action = "ride", op = "board" })
		assert(r.ok, "board failed: " .. tostring(r.err))
		ctx.tick(Drive.BOARD_DELAY + 3)
	elseif MOMENT == "pm_stand" or MOMENT == "pm_board" then
		local stand = Drive.place("pm_limo")
		ctx.camera(stand.stop.Position + Vector3.new(20, 10, -30), stand.stop.Position)
		if MOMENT == "pm_board" then
			ctx.City.trips[ctx.player.UserId] = { player = ctx.player, state = "abroad", to = "abroad", releaseAt = math.huge }
			ctx.stand(stand.door.Position)
			book("pm_hotel")
			local at = stand.stop * CFrame.new(5.6, 3, 4.6)
			ctx.stand(at.Position)
			ctx.player.Character:PivotTo(CFrame.lookAt(at.Position, (stand.stop * CFrame.new(0, 3, 4.6)).Position))
			table.insert(extra, ctx.player.Character)
		end
	end
	ctx.frame()
	local cars = M.game.Workspace:FindFirstChild("DriveCars")
	ctx.solveRigs(cars)
	for _, m in extra do ctx.solveRigs(m.Parent) end
	-- serialise BaseParts + SpecialMeshes + Humanoids (dump2blend's input)
	local HS = M.game:GetService("HttpService")
	local out = {}
	local ids = {}
	local n = 0
	local function v3(v) return { v.X, v.Y, v.Z } end
	local function rec(inst, parentId, path)
		n += 1
		local id = n
		ids[inst] = id
		local p = path .. "/" .. inst.Name
		local row = { id = id, parent = parentId, path = p, class = inst.ClassName, name = inst.Name }
		if inst:IsA("BasePart") then
			local cf = inst.CFrame
			local r = { cf:GetComponents() }
			row.size = v3(inst.Size)
			row.cframe = r
			row.color = { inst.Color.R * 255, inst.Color.G * 255, inst.Color.B * 255 }
			row.material = inst.Material.Name
			row.transparency = inst.Transparency
			row.canCollide = inst.CanCollide
			row.anchored = inst.Anchored
			if inst:IsA("Part") then row.shape = inst.Shape.Name end
		elseif inst:IsA("SpecialMesh") then
			row.meshType = inst.MeshType.Name
			row.scale = v3(inst.Scale)
		end
		table.insert(out, row)
		for _, c in inst:GetChildren() do
			if c:IsA("BasePart") or c:IsA("Model") or c:IsA("SpecialMesh") or c:IsA("Humanoid") or c:IsA("Folder") then rec(c, id, p) end
		end
	end
	rec(cars, nil, "Drive")
	for _, m in extra do rec(m, nil, "Founder") end
	rprint("@@DUMP " .. HS:JSONEncode({ meta = { moment = MOMENT, plot = plot.index, time = ctx.T.now }, instances = out }))
end
local ok, err = M.runMain(body, { timeout = 600, maxSteps = 8000000 })
if not ok then rprint("CRASH " .. tostring(err)) end
