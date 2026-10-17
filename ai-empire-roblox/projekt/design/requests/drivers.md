# Requests from package "drivers" (company chauffeurs, fleet rides, VIP limousine)

The drivers package works without every item below. API: agents/drivers/API.md (DriverService.request / cancel / free /
places / onArrive / status / onTripAction).

## 1. itinerary - TripAction is bound by DriverService (important)
`Remote.bind("TripAction", ...)` happens in DriverService.init (Main.server runs it before ItineraryService.init).
A second `Remote.bind("TripAction", ...)` would REPLACE the handler and break the driver rides. Register your actions
instead, in ItineraryService.init:
```lua
local Driver = require(script.Parent.DriverService)
Driver.onTripAction("go", function(session, payload) ... return {ok = true} end)   -- also "cancel", "leave", "status", ...
```
`action = "ride"` stays the drivers' own (`op = request | board | cancel | status | places`). Driver to the airport for
an itinerary: `Driver.request(player, {to = "airport_departures", purpose = "itinerary", passengers = {{name, role, seed}},
onArrive = function(rideId, placeId) ... end})`; abroad from the limousine stand to a tower:
`{to = "pm_" .. buildingId}` (`DrivePlan.clientPlace(client.name).id`).

## 2. lead - tests/lead/run_all.sh lines
```
python3 harness/make_manifest.py --src work/src --gen harness/.gen_drivers >/dev/null
run drivers_plan      bash -c "cd tests/drivers && ../../tools/luau test_plan.luau -a .gen_drivers"
run drivers_service   bash -c "cd tests/drivers && ../../tools/luau test_service.luau -a .gen_drivers"
run drivers_client    bash -c "cd tests/drivers && ../../tools/luau test_client.luau -a .gen_drivers"
run drivers_clearance bash tests/drivers/clearance.sh
```
Same as `tests/drivers/run.sh`. Mutation proof: `tests/drivers/negative.sh`. Previews: `tests/drivers/render_gui.sh`
(out/drivers/gui), renders `python3 tests/drivers/render.py all` (out/drivers/render).

## 3. phone (optional) - a destination list in the phone itself
The Driver contact works today: the hook answers with the honest state (shown on the dial screen) and, when there is
something to book or a ride to manage, DriveController opens its own destination sheet (Notify `DRIVE_SHEET`,
ScreenGui `DriveSheet`, DisplayOrder 45 above the open phone). Booking closes the sheet and the phone.
If the phone wants the list inline instead: the hook result carries `sheet = true`; the payload of the sheet
(`{title, text, state, rideId?, zone, pickup?, pickupName?, canBook, places = {{id, title, sub?, eta}}}`) can be fetched
with `TripAction {action = "ride", op = "places"}` and a row books with `{action = "ride", op = "request", to = id}`.
Minimal change if you prefer one modal: add `DriveSheet = true` to `PhoneController.PANELS` (the phone then closes when
the sheet opens).

## 4. district (CampusService) - Founder Square props on the East Ring Road asphalt (FYI)
`PublicTerminal` (x 1036.5..1043.5, z -11..-9), `FounderBoard` (x 1032..1092, z 33) and the west `SquarePlanter`
(x 1010..1018, z 48..56) stand on the 48-wide ring road (x 992..1040) at the avenue junction. Company cars use the
middle of each half (x 1004 / 1028, `DrivePlan.laneOff`) and pass them (tests/drivers clearance), but CityLife traffic
on the outer lanes or player cars can still hit them. Moving them 8+ studs east (x >= 1044) would clear the road.

## 5. talk (optional) - talk to the drivers
Drivers at the HQ entrance and the Port Meridian chauffeur are client-side clones of rig templates (no server rig,
no EmployeeTalk prompt), like the shuttle pilots / jet crew. A talk line set for the job "Driver" / "Chauffeur" would
need a server-side prompt part at `DrivePlan.HQ.post[i]` (plot frame) - DriverService could create it if TalkService
gets an API for non-rig speakers.

## 6. vehicles - use the imported ExecutiveLimo mesh for the VIP limousine when it exists
Asset: `assets/vehicles/executivelimo/` (ExecutiveLimo.fbx, manifest.json = the numbers below, README.md section 7 =
how the owner imports it). Nothing under work/ was changed. Please implement in DriveController.buildCar("limo", ...):

**Lookup (client, once, cache the template):** `ReplicatedStorage.Assets.Vehicles.ExecutiveLimo`, else
`ReplicatedStorage.VehicleAssets.ExecutiveLimo` (a Model). If neither exists, or a required part is missing
(`Body`, `Wheel_FL/FR/RL/RR`, `Door_RearL`, `Door_RearR`), keep the part-built limo exactly as today.

**Clone + scale:** `local m = template:Clone(); m:ScaleTo(0.95)`. The Model pivot is the ground point on the centre
line half-way between the axles; front = -Z, up = +Y, right = +X, driver on the left (-X), like SHAPES/SEATS. Then for
every BasePart: Anchored = true, CanCollide = CanQuery = CanTouch = false, collision group "DriveCars", CastShadow
only for `Body`; record `offset = m:GetPivot():ToObjectSpace(part.CFrame)` into car.parts / car.offsets (the existing
BulkMoveTo path then works unchanged). Colours: `Body`, `Door_Driver`, `Door_RearL`, `Door_RearR`, `Mirror_L`,
`Mirror_R` Color = (14,15,18) = the part-built limo's body colour today (the manifest's default is the slightly bluer
midnight (18,20,27); either works: paint is white in the vertex colours, so Color sets the paint); every other part keeps
Color (255,255,255). `Glass` + `Door_Driver_Glass`: Material Glass, Transparency 0.45; `GlassPrivacy`,
`Door_RearL_Glass`, `Door_RearR_Glass`: Glass, 0.22; `Ambient_LED` + `StarLights`: Material Neon (Ambient_LED
Color (140,123,255) or any colour); `Lights_Front` / `Lights_Rear`: Neon when the lights are on.

**Size at scale 0.95 (studs):** length 25.76, body width 6.64, width over mirrors 7.36 (<= Drive.CAR_WIDTH.limo 7.4),
roof 5.09, **wheelbase 18.10**, wheel radius 1.193. So the mesh limo needs `wb = 18.10` in Drive.poseAtDist /
Drive.endCF (not WHEELBASE.limo = 13, or the body cuts corners) and length 25.76 wherever CAR_LENGTH.limo = 21 spaces
cars (queue at the stand, VIP lay-by: bay centres 48 apart leave ~22 studs between two cars; the 8 x 22 gold pad is
overhung by ~1.9 studs at each end).

**Wheels (spin + steer):** `Wheel_FL` (-2.8161, 1.1927, -9.0522), `Wheel_FR` (2.8161, 1.1927, -9.0522), `Wheel_RL`
(-2.8161, 1.1927, 9.0522), `Wheel_RR` (2.8161, 1.1927, 9.0522) = axle centres at scale 0.95 (= each part's imported
pivot, `part:GetPivot()`). Spin about the part's local +X through that pivot: angle = -distance / 1.1927 (rolling
forward towards -Z is a negative angle). FL/FR also steer about +Y through the same pivot (positive = front of the
wheel turns to the car's left, limit +-30 deg). `Caliper_FL/FR/RL/RR` share the wheel pivots: no spin, the front ones
steer with their wheel. Per frame: `offset_i = pivotRel * CFrame.Angles(0, steer, 0) * CFrame.Angles(spin, 0, 0) *
pivotRel:Inverse() * restOffset_i`, where `pivotRel = m:GetPivot():ToObjectSpace(part:GetPivot())` taken at build time.
If per-frame wheel updates are too costly for far cars, spin only the local player's ride.

**Doors (boarding, Drive.BOARD_DELAY = 2 s):** vertical hinges, rotate about +Y through the part pivot:
`Door_Driver` pivot (-3.325, 2.1036, -6.7789), open angle **-65 deg**; `Door_RearL` (-3.325, 2.1036, 5.1842), **-65 deg**;
`Door_RearR` (3.325, 2.1036, 5.1842), **+65 deg** (kerb side at the Port Meridian stand). The glass parts
`Door_Driver_Glass`, `Door_RearL_Glass`, `Door_RearR_Glass` use the same pivot and angle as their door. Offset while
opening: `pivotRel * CFrame.Angles(0, math.rad(angle * t), 0) * pivotRel:Inverse() * restOffset`, t = 0..1 (ease)
over ~0.6 s, close again before the car pulls away. The front passenger door is part of Body (does not open).

**Seats (rig roots at scale 0.95, studs, model space; LookVector in brackets):** R6 roots follow your convention (1.5
above the seat surface, head + cap 2.32 above the root) but are **lowered** so heads stay 0.05 under the measured
headliner (the real-proportion cabin is lower than the part-built 5.4 roof):
| Drive.SEATS.limo key | manifest anchor | rig root | faces | cushion top / headliner y |
|---|---|---|---|---|
| driver | DriverSeat | (-1.3571, 2.205, -3.7593) | -Z | 1.66 / 4.58 |
| front | FrontPassengerSeat | (1.3571, 2.204, -3.7593) | -Z | 1.66 / 4.57 |
| rearL | PassengerSeat1 (rear bench left) | (-1.3571, 2.417, 8.7977) | -Z | 1.66 / 4.79 |
| rearR (founder) | PassengerSeat3 (rear bench right) | (1.3571, 2.417, 8.7977) | -Z | 1.66 / 4.79 |
| extra | PassengerSeat2 (rear centre) | (0, 2.417, 8.7977) | -Z | 1.66 / 4.79 |
| extra | PassengerSeat6 / 5 / 4 (side bench, front to rear) | (2.0866, 2.373, -0.7566 / 1.5845 / 3.9255) | -X | 1.66 / 4.74 |
The hips then sit 0.75-0.96 stud into the cushion (legs hidden in the seat; acceptable through privacy glass). If
that looks wrong, alternatives: ScaleTo(1.0) (sink 0.58-0.81, but 7.75 wide over the mirrors > 7.4), or scale the
seated rigs to ~0.85. The founder's own avatar clone (any rig type) should use the same root and lower it further
if it is taller than R6.

**Camera / extras:** "View" (back seat) can use PassengerSeat3's root + (0, 1.6, 0). FX points at scale 0.95 (fx
anchors in manifest.json › game_scale › anchors_at_scale): Headlight_L/R, Taillight_L/R, Exhaust_L/R, CabinLight,
PlateFront/PlateRear; door entry points on the ground: DoorL1 (-5.1911, 0, -4.7092), DoorL2 (-5.1911, 0, 6.5923),
DoorR2 (5.1911, 0, 6.5923), each facing the car. `SteeringWheel` pivot (-1.3572, 2.9688, -5.337), axis
(0, 0.40674, 0.91355), positive = steering left (optional: turn it with the front wheels x ~12).

**Budget:** 29 MeshParts, 69,316 triangles (largest: Body 18,132; Roblox limit 20,000 per mesh). Use the mesh only for
the riding limo and the one waiting at the VIP stand (bay 1, and bay 2's decorative car if MetroBuilder wants it);
far cars keep the part-built look (or skip `Interior_*`, `Ambient_LED`, `StarLights` beyond ~150 studs).
Test: with the Model removed from both folders the game must look exactly as today (part-built limo).
