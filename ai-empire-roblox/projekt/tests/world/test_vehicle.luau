--!nocheck
-- World package: VehicleService in the headless mock - CityPlan bounds (cars drive downtown and to the
-- airport, the sea / off-map still resets), the car survives an office rebuild while parked away from
-- the plot (airport car park) but not on the plot, the limo game-pass car (ShopService.owns gate, error /
-- missing owns = not owned, fallback to the Hatch), regular cars unchanged.
-- Real VehicleService/EconomyService/CityPlan; stubbed Session/Remote/ShopService (stubs.luau), PlotService
-- stubbed in-test (get + onChanged capture).
-- Run: python3 harness/make_manifest.py --src work/src --gen harness/.gen_world && tools/luau tests/world/test_vehicle.luau [-a .gen_dir]
local M = require("../../harness/mock")
local args = { ... }
local GEN = "../../harness/" .. (args[1] or ".gen_world")
local manifest, sources = require(GEN .. "/manifest"), require(GEN .. "/sources")
for path, src in require("./stubs") do sources[path] = src end
sources["ServerScriptService/Server/Services/PlotService.module.luau"] = [[
--!strict
-- TEST STUB (world vehicle test)
local Plot={}
Plot.plots={} :: {any}
Plot.changed={} :: {any}
function Plot.get(player: any): any for _,p in Plot.plots do if p.owner==player then return p end end;return nil end
function Plot.onChanged(fn: any) table.insert(Plot.changed,fn) end
function Plot.setAwayCheck(_fn: any) end
return Plot
]]
M.loadTree(manifest, sources)
M.quiet = true
local G = M.G
local pass, failc = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else failc += 1; print("FAIL  " .. name .. (if detail ~= nil then "  -- " .. tostring(detail) else "")) end
end

local function body()
	local Instance, Vector3, CFrame = G.Instance, G.Vector3, G.CFrame
	local game = M.game
	local RS, Server = game.ReplicatedStorage, game.ServerScriptService.Server
	local S = Server.Services
	local F = require("./fixture")(M, G)
	local Remote = M.require(Server.Lib.Remote)
	local Session = M.require(S.SessionService)
	local Plot = M.require(S.PlotService)
	local Shop = M.require(S.ShopService)
	local Config = M.require(RS.Shared.Config.CampusConfig)
	local CityPlan = M.require(RS.Shared.Config.CityPlan)
	local Plan = M.require(RS.Shared.Config.BuildingPlan)
	local Net = M.require(RS.Shared.Net)
	local folder = Instance.new("Folder"); folder.Name = Net.FOLDER
	for _, name in Net.EVENTS do local e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = folder end
	folder.Parent = RS
	local Vehicles = M.require(S.VehicleService)
	Vehicles.init()
	local buy, spawn = Remote.binds.BuyCar, Remote.binds.SpawnCar
	check("BuyCar/SpawnCar bound", buy ~= nil and spawn ~= nil)
	-- a plot with an office (GarageSpawn marker like RoomKitsSpecial) for the founder
	local p = F.player(77, "Driver", CFrame.new(0, 27.5, 0))
	local s = F.session(p, 50000)
	table.insert(Session.sessions, s)
	local cf = CFrame.lookAt(Vector3.new(-800, 24, 252), Vector3.new(-800, 24, 0)) -- plot 7
	local office = Instance.new("Model"); office.Name = "Office"; office.Parent = game.Workspace
	local marker = Instance.new("Part"); marker.Name = "GarageSpawn"; marker:SetAttribute("SpawnCFrame", cf * Plan.GARAGE_SPAWN); marker.Anchored = true; marker.Parent = office
	local plot = { owner = p, office = office, cframe = cf, index = 7 }
	Plot.plots = { plot }

	------------------------------------------------------------------ limo (game pass)
	local limo = Config.find(Config.CARS, "limo")
	check("limo is a pass car in CampusConfig.CARS", limo ~= nil and limo.pass == "limo" and limo.price == 0)
	local m0 = s.data.money
	local r = buy(s, { carId = "limo" })
	check("limo without the pass: NEEDS_PASS, nothing stored", r.ok == false and r.err == "NEEDS_PASS" and s.data.empire.campus.cars.limo == nil and s.data.money == m0, r.err)
	check("limo spawn without the pass refused", spawn(s, { carId = "limo" }).err == "NOT_OWNED")
	Shop.setMode("missing")
	check("ShopService without owns(): not owned", buy(s, { carId = "limo" }).err == "NEEDS_PASS")
	Shop.setMode("error")
	check("ShopService.owns throwing: not owned (pcall)", buy(s, { carId = "limo" }).err == "NEEDS_PASS")
	Shop.setMode("ok")
	Shop.passes[77] = { limo = true }
	r = buy(s, { carId = "limo" })
	check("limo with the pass joins the fleet for $0", r.ok == true and s.data.empire.campus.cars.limo == true and s.data.empire.campus.selectedCar == "limo" and s.data.money == m0, r.err)
	r = spawn(s, { carId = "limo" })
	local rec = Vehicles.cars[77]
	check("limo spawned at the garage", r.ok == true and rec ~= nil and rec.model:GetAttribute("VehicleType") == "limo", r.err)
	local nparts = 0; for _, d in rec.model:GetDescendants() do if d:IsA("BasePart") then nparts += 1 end end
	check("limo stays a light model (<= 40 parts)", nparts <= 40 and nparts >= 25, nparts)
	check("limo body length from config", math.abs(rec.root.Size.Z - limo.length) < 1e-6)
	Shop.passes[77] = nil
	rec.spawnedAt = -100 -- skip the 3 s cooldown
	check("pass gone: explicit limo spawn refused", spawn(s, { carId = "limo" }).err == "NOT_OWNED")
	r = spawn(s, {})
	check("pass gone: default collection falls back to the Hatch", r.ok == true and Vehicles.cars[77].model:GetAttribute("VehicleType") == "compact" and s.data.empire.campus.selectedCar == "compact", r.err)
	------------------------------------------------------------------ regular cars unchanged
	s.data.money = 100
	check("van without money: NO_MONEY", buy(s, { carId = "van" }).err == "NO_MONEY")
	s.data.money = 20000
	r = buy(s, { carId = "van" })
	check("van bought for its price", r.ok == true and s.data.money == 4000 and s.data.empire.campus.cars.van == true)
	check("van again: ALREADY_DONE", buy(s, { carId = "van" }).err == "ALREADY_DONE")
	check("unknown car: BAD_INPUT", buy(s, { carId = "tank" }).err == "BAD_INPUT")

	------------------------------------------------------------------ bounds (CityPlan.drivable)
	Vehicles.cars[77].spawnedAt = -100
	spawn(s, { carId = "compact" })
	rec = Vehicles.cars[77]
	local home = rec.home
	local function placeAndTick(pos)
		rec.model:PivotTo(CFrame.new(pos))
		rec.lastPosition = rec.root.Position -- isolate the bounds check from the teleport check
		rec.checkClock = 0
		for _ = 1, 12 do Vehicles.tick(0.05) end -- 0.6 s: one bounds check
		return (rec.root.Position - pos).Magnitude < 0.01
	end
	check("downtown (z 1500) is drivable: no reset", placeAndTick(Vector3.new(-600, 26.2, 1500)))
	check("past the old z=800 limit (z 900): no reset", placeAndTick(Vector3.new(0, 26.2, 900)))
	check("airport runway: no reset", placeAndTick(Vector3.new(0, 26.2, 3000)))
	check("airport car park: no reset", placeAndTick(CityPlan.AIRPORT.carPark.Position + Vector3.new(0, .2, 0)))
	check("sea (z 3300): reset to the garage", not placeAndTick(Vector3.new(0, 26.2, 3300)) and (rec.root.Position - home.Position).Magnitude < 0.01)
	check("east of the district (x 1200): reset", not placeAndTick(Vector3.new(1200, 26.2, 0)))
	check("below the map (y -10): reset", not placeAndTick(Vector3.new(0, -10, 1500)))

	------------------------------------------------------------------ office rebuilds
	local onChanged = Plot.changed[1]
	check("VehicleService listens to plot changes", onChanged ~= nil)
	rec.model:PivotTo(CityPlan.AIRPORT.carPark)
	local marker2 = Instance.new("Part"); marker2.Name = "GarageSpawn"; marker2:SetAttribute("SpawnCFrame", cf * CFrame.new(100, -12, 4)); marker2.Anchored = true
	local office2 = Instance.new("Model"); office2.Name = "Office"; marker2.Parent = office2; office2.Parent = game.Workspace
	plot.office = office2
	onChanged(plot, s)
	check("car parked at the airport survives an office rebuild", Vehicles.cars[77] == rec and rec.model.Parent ~= nil)
	check("its reset spot follows the rebuilt garage", (rec.home.Position - (cf * CFrame.new(100, -12, 4)).Position).Magnitude < 0.01)
	rec.model:PivotTo(cf * Plan.GARAGE_SPAWN)
	onChanged(plot, s)
	check("car in the plot garage is cleared by a rebuild (as before)", Vehicles.cars[77] == nil and rec.model.Parent == nil)
end

local ok, err = M.runMain(body, { timeout = 120, maxSteps = 2000000 })
if not ok then failc += 1; print("ERROR " .. tostring(err)) end
print(string.format("world_vehicle: %d passed, %d failed", pass, failc))
if failc > 0 then error("world_vehicle failed", 0) end
