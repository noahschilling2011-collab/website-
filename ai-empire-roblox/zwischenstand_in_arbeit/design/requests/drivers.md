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

**Update (drivers review round 1, 2026-10-11):**
* integrate / lead: the header of the `ItineraryService` stub still says TripAction is "bound by this service (or
  DriverService)". Please change it to: *"The remote TripAction is bound by DriverService (it owns action = "ride");
  register every other action with `DriverService.onTripAction(action, handler)` in init() - never call
  `Remote.bind("TripAction", ...)` here (it would replace the drivers' handler)."* so the itinerary package does not
  double-bind.
* Each TripAction action now has its own per-player rate limit (`DriverService.LIMITS`: ride writes 6 / 2 per s,
  ride status + places 12 / 4 per s, every itinerary action its own 8 / 3 per s bucket) - status polls of the
  itinerary never starve a booking.
* Port Meridian: the limousine can be booked from anywhere in the arrivals hall / plaza (`CityPlan.ABROAD.terminal`,
  `.plaza` -> pick-up `pm_limo`), i.e. right where ShuttleService places the founder after a landing. Bay 1 holds one
  car; a second booking there waits for the next limousine (`queued = true`, honest ETA), bookings elsewhere in Port
  Meridian get one of `DriverService.LIMO_FLEET` (3) garage cars. `pm_limo` is a pick-up only (BAD_PLACE as a
  destination). A ride of the founder in the other city is cancelled automatically when he flies (notice), so
  `request` abroad never fails with ALREADY_RIDING because of a forgotten home booking.
* Field staff: a business trip's rep is driven by a FREE company driver (request 22); with every driver busy the trip
  stays data. Itinerary rides (purpose = "itinerary") use the same drivers and queue honestly.
STATUS: done by itinerary (ItineraryService.init registers go / cancel / leave / status / retry with DriverService.onTripAction, never Remote.bind; the header says so; rides use Driver.request purpose "itinerary" with the real rep + engineer as passengers; tests/itinerary/test_service.luau remote scenario checks validation + the per-action limit)

## 2. lead - tests/lead/run_all.sh lines
```
python3 harness/make_manifest.py --src work/src --gen harness/.gen_drivers >/dev/null
run drivers_plan      bash -c "cd tests/drivers && ../../tools/luau test_plan.luau -a .gen_drivers"
run drivers_service   bash -c "cd tests/drivers && ../../tools/luau test_service.luau -a .gen_drivers"
run drivers_client    bash -c "cd tests/drivers && ../../tools/luau test_client.luau -a .gen_drivers"
run drivers_review    bash -c "cd tests/drivers && ../../tools/luau test_review.luau -a .gen_drivers"
run drivers_review_cl bash -c "cd tests/drivers && ../../tools/luau test_review_client.luau -a .gen_drivers"
run drivers_clearance bash tests/drivers/clearance.sh
```
(updated 2026-10-11: + test_review / test_review_client = the review round's adversarial scenarios R1-R8 / V1-V4 and
one check per review issue - please add all six lines; still OPEN)
STATUS: done by verify2b (2026-10-17): all six lines are in tests/lead/run_all.sh (agents/verify2b/runall.txt).
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

**Size at scale 0.95 (studs):** length 25.76, body width 6.64, width over mirrors 7.30 (<= Drive.CAR_WIDTH.limo 7.4),
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
PlateFront/PlateRear; door entry points on the ground: DoorL1 (-5.1911, 0, -3.5558), DoorL2 (-5.1911, 0, 8.153),
DoorR2 (5.1911, 0, 8.153), each facing the car, placed just behind the OPEN door (a standing R6 footprint there touches
neither the open door nor its glass). `SteeringWheel` pivot (-1.3572, 2.9688, -5.337), axis
(0, 0.40674, 0.91355), positive = steering left (optional: turn it with the front wheels x ~12).

**Budget:** 29 MeshParts, 69,910 triangles (largest: Body 18,448; Roblox limit 20,000 per mesh). Use the mesh only for
the riding limo and the one waiting at the VIP stand (bay 1, and bay 2's decorative car if MetroBuilder wants it);
far cars keep the part-built look (or skip `Interior_*`, `Ambient_LED`, `StarLights` beyond ~150 studs).
Test: with the Model removed from both folders the game must look exactly as today (part-built limo).
STATUS: done by drivers (DriveController.findMesh: ReplicatedStorage.Assets.Vehicles.ExecutiveLimo, else
ReplicatedStorage.VehicleAssets.ExecutiveLimo, required parts checked, cached; ScaleTo(0.95), anchored / no collision /
group DriveCars, colours + glass + neon as listed, wheel spin + front steer about the part pivots, kerb-side rear door
(Door_RearR +65 deg) opens over the 2 s boarding delay and closes before the car pulls away, seat table from the
manifest (rigs scaled so arms stay inside the cabin), wheelbase 18.10 into poseAtDist / endCF, length 25.76 for
spacing; budget: beyond 150 studs from the camera a mesh limousine hides its interior locally (Interior_*,
SteeringWheel, Ambient_LED, StarLights = 16.7k of 69.3k triangles; LocalTransparencyModifier, written only when the
distance threshold is crossed); at most MAX_CARS = 10 cars are drawn at all. Model absent = the part-built limousine
exactly as before. tests/drivers/test_review_client.luau "mesh:" checks with a stand-in model carrying the manifest's part names.
Studio-only: the look of the real imported mesh.)

UPDATE 2026-10-11 (ExecutiveLimo fix round 2, assets/vehicles/executivelimo/manifest.json regenerated): part names,
door / wheel / caliper / steering pivots, hinge axes and open angles, and all seat rig roots are UNCHANGED, so the
implementation above keeps working as is. What changed in the mesh: (1) both opening doors and their glass now swing
0..65 deg without touching Body, Chrome, the mirrors, the interior or the wheels (checked every 2.5 deg on the exported
FBX); the driver door no longer carries a strip of the cowl/dashboard. (2) `Mirror_L` / `Mirror_R` sit 1.6 cm higher
and 3 cm further back so the driver door passes under the mirror: pivots at scale 0.95 now (-2.8471, 3.515, -5.5575) /
(2.8471, 3.515, -5.5575) (only matters if a pivot is hard-coded; offsets read from the model are fine). (3) Width over
the mirrors at 0.95 is 7.30 (was 7.36): `MESH.width = 7.36` in DriveController still works (slightly conservative);
7.30 is the exact value. (4) Interior_Lounge no longer reaches into the rear wheel wells. (5) Triangles 69,910
(Body 18,448); the locally hidden interior set (Interior_*, SteeringWheel, Ambient_LED, StarLights) is now 16.9k
(the comment in MESH.far says 16.7k of 69.3k). (6) Door entry points moved ~1.2 (DoorL1) / ~1.6 (DoorL2, DoorR2)
studs rearward at scale 1 so a character standing there is clear of the open door: at scale 0.95 DoorL1
(-5.1911, 0, -3.5558), DoorL2 (-5.1911, 0, 8.153), DoorR2 (5.1911, 0, 8.153), LookVector towards the car (+X for the
left points, -X for DoorR2). Use them if boarding NPCs / the founder walk up to the car.
RE-CHECK 2026-10-12 (ExecutiveLimo re-export after the review): no part name, pivot, hinge axis, open angle, seat
root, entry point or triangle count changed (still 29 MeshParts, 69,910 triangles, Body 18,448); only a sub-mm
needle triangle in Body was re-triangulated. Nothing to do on the drivers side.

STATUS (update of 2026-10-11): done by drivers (2026-10-12) - MESH.width = 7.30 and the MESH.far comment (16.9k of
69.9k triangles) in DriveController; part names, pivots, hinge angles and seat roots are read / used as before, so
nothing else changed. The door entry points (DoorL1 / DoorL2 / DoorR2) are not used: the founder boards with the
prompt / HUD button at the kerb-side rear door and is held at once (no walk-up animation).

## 7. metro - CityLifeController: treat company cars / limousines as traffic (review issue 10)
Company cars in Port Meridian now cruise at the city traffic's pace (DrivePlan class "metro" = 30 studs/s) on the
boulevard's outer lane, but CityLife's ambient cars and walkers do not know about them, so a limousine can still pass
through an ambient car or a crossing walker. DriveController publishes what it draws:
```lua
local Drive = require(script.Parent.DriveController)   -- client
for _, c in Drive.liveCars() do   -- every frame: {cf: CFrame, length: number, width: number, speed: number}
	-- c.cf = ground point on the centre line between the axles, LookVector = driving direction
end
```
Minimal change in CityLifeController (owner: metro): when picking a car's leader in its lane, also consider every
`liveCars()` entry within ~2 m of the lane line ahead of it (keep the usual gap, stop behind it), and let a walker at a
crossing wait while a live car is within ~25 studs of the crossing. Read once per frame (a handful of entries, MAX_CARS
= 10); nothing goes over the network.


## 8. guests_jet (FYI, optional) - abroad field staff with the company jet
When a company has the jet (empire.jet), JetService flies the abroad B2B travellers as companions. DriverService
still drives the same rep (+ engineer) from the HQ entrance to the City Airport **departures kerb** when the trip
starts, and fetches them at the **arrivals kerb** when it ends (it only reads empire.deals.tripList and does not know
about the jet). If the jet leaves before the car reaches the kerb (about 2 min after the trip starts: the driver's walk, 28 s from
the garage to the entrance, 6 s to get in, then 81-87 s to the departures kerb), the same person can be
seen in the car and in the jet cabin at the same time. That needs the camera near both places, which is rare.
Two options; drivers can do either once you say which you prefer:
(a) JetService delays a staff "out" flight until the driver's drop-off. DriverService already publishes the ride
    (Ride_<n>, Kind "field", attribute To = "airport_departures", Plan); I can add `DriverService.fieldEta(userId,
    tripKey) -> seconds?`.
(b) DriverService skips abroad field rides while empire.jet is true: the reps leave the HQ with no car and appear in
    the jet, which is what JetService shows today.
No STATUS needed until one of you picks an option. Today nothing is wrong with the money or the data, only this
visual overlap.
STATUS: guests_jet picked (a); the JetService side is done by guests_jet (fix round 1): a staff "out" flight (and a
founder flight taking the staff along) waits until `DriverService.fieldEta(userId, tripKey) -> seconds?` has passed
(read once when the trip is first seen, pcall-protected, capped at JetService.FIELD_WAIT_MAX = 240 s; tripKey =
tostring(trip.client)..":"..tostring(trip.left), the key both services already use). Until DriverService exports
fieldEta, JetService behaves as before (eta 0). Open for drivers: add `DriverService.fieldEta` (seconds until the
field ride of that trip drops the travellers at the departures kerb; nil = no ride / not abroad).
