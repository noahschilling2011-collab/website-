# Requests / interfaces from package "metro" (Port Meridian: MetroBuilder + MetroPlan; client city life: CityLifeController)

## 1. Lead — run_all: add the metro suites
Append to tests/lead/run_all.sh:
```
python3 harness/make_manifest.py --src work/src --gen harness/.gen_metro >/dev/null
for t in plan build life paths; do run "metro_$t" $L tests/metro/test_$t.luau -a .gen_metro; done
run metro_stress $L tests/metro/stress_traffic.luau -a .gen_metro 3
```
UPDATE (2026-10-10, apron + terminal crowd round): expected metro_plan 44/0, metro_build 42/0, metro_life 46/0,
metro_paths 6/0 (prints one PENDING line for the airport graph, #7), metro_stress 8/0 (apron, ShuttleStand, ApronDoor,
stand-1 hull space, runway strip, City Airport terminal crowd checks added).
UPDATE (fix round, 2026-10-05): `paths` is new (walkers vs the real scenery, ~10 s); metro_stress now also checks
world-space conflicts (oriented car boxes car-car and walker-in-car) and 2 x 240 s long runs (no gridlock, no
starving walkers) - ~3 min on a quiet machine. Expected: metro_plan 40/0, metro_build 36/0, metro_life 41/0,
metro_paths 4/0, metro_stress 8/0.
Expected today (16:5x UTC): metro_plan 35/0, metro_build 30/0, metro_life 37/0 (~30 s together; test_life simulates
90 s of Port Meridian + 60 s of downtown at 30 Hz), metro_stress 4/0 (~90 s: traffic over 3 more seeds x 5 foci -
no car overlaps in a lane, no red-light runs, cars on their lane lines; it caught a turn-entry overlap that the
fixed-seed suite missed, fixed in CityLifeController). The geometry part (world dump with per-zone budgets, holes,
walkability of the arrival area / lounge / VIP stand / helipad / waterfront) runs with `tests/metro/run.sh`
(~3 min with the stress run). `agents/metro/world_dump.sh` and `agents/metro/life_dump.sh` use private gen dirs (no races).
STATUS: done by integrate (run_all: metro_{plan,build,life,paths} on .gen_metro + metro_stress; metro_reach = tests/metro/reach.py on the shared world dump)

## 2. Lead / world — agents/world/world_check.py still has the old single budget (10,000)
tests/world/run.sh already uses agents/airport/world_check.py (per-zone budgets, abroad <= 20,000; today the whole
world is 14,749 parts (2026-10-10 16:xx UTC: abroad zone 5,139 in world_check; tests/metro/test_build counts 5,253 Port Meridian parts =
+4,472 of the package's +4,500, i.e. the metro budget is used up - further metro additions must free parts first). agents/metro/world_dump.sh uses the airport copy as well. Adopt the
per-zone budgets in agents/world/world_check.py too (same request as airport.md #1).
STATUS: done by integrate (agents/world/world_check.py adopted the per-zone budgets of agents/airport/world_check.py; same as airport.md #1)

## 3. flight — VIP helicopter: the markers (no change needed)
- Two parts named `Helipad` (landing surface = top face, collidable, anchored, attributes Purpose, PadId, PadName):
  `Purpose = "VIP"`, PadId `pm_hotel` on the Meridian Grand Hotel roof (top = `MetroPlan.HOTEL_ROOF + 1`, 40x40,
  under `PortMeridian/Hotel_intl_hotel/RooftopHelipad`) and `Purpose = "VIPAirport"`, PadId `pm_airport` on the
  heliport east of the apron (since 2026-10-10 at (604, 7670); top = GROUND + 1, 44x44, fenced, gates south-west and
  east, VIP helicopter terminal beside it, under `PortMeridian/VipHelipad`). Apron / ShuttleStand / ApronDoor: see
  flight.md #7 STATUS.
  Centres / sizes also in `MetroPlan.HELIPADS` (`cf` = centre of the top face).
- Nothing stands above either pad; windsock and roof lift house are outside the pad squares. The hotel roof has the
  marker `HelipadExit` (see flight.md #4 STATUS).
- The Meridian Spire (468 studs + 74-stud mast, x 0, z 8520..8576) stands 140 studs south of the hotel pad: approach
  the roof pad from the north (boulevard axis) as planned.
STATUS: already done (integrate: FYI for flight, no change needed)

## 4. clients — VIP limousine stand (no change needed)
- Part `VipLimoStand` (under `PortMeridian/ArrivalPlaza/VipLimoArea`; invisible, no collision; attributes
  Purpose = "VIP", Zone = "abroad", Bays = 2, Bay2 = CFrame): its CFrame = bay 1 = car pivot on the road surface
  facing west in the lay-by on the north kerb of Arrivals Drive (`MetroPlan.VIP_LIMO.stand`, `.bay2`, `.layby`).
  Bay 1 is kept free for the chauffeur car; bay 2 holds a decorative model `Limousine` (hide it locally if the
  service parks there). Canopy "VIP CHAUFFEUR SERVICE", red carpet from the east terminal exit (x = 80).
  Leaving the stand: west along the lay-by into Arrivals Drive (dir -1 lane, `MetroPlan.portMeridian().lanes`).
- Lounge staff marker: invisible part `LoungeConciergePost` (attribute LoungePost = "concierge", LookVector = facing)
  behind the concierge desk of the Port Meridian `BusinessLounge` — for a hostess NPC (staff / talk packages).
STATUS: deferred to drivers (VIP limo stand bay 1 / bay 2 / lay-by for the chauffeur car)
STATUS: done by drivers (DrivePlan place pm_limo = MetroPlan.VIP_LIMO.stand (bay 1); booked limousines wait there and leave west through the lay-by into Arrivals Drive's westbound lane passing bay 2; DriveController shows an idle limousine + chauffeur in bay 1 while no ride stands there; the decorative Limousine in bay 2 stays as built)

## 5. Everyone — client city life (FYI, no API needed)
CityLifeController runs only while the camera is inside `MetroPlan.REGIONS` (Port Meridian x +-2600, z 6500..10200;
Business City x +-1260, z 700..2416; since 2026-10-10 also the City Airport terminal x +-300, z 2417..2560 (forecourt
to jet bridges) below its roof line: 30 walkers, no cars, airport.md #5 - forecourt, car park and apron stay quiet): <= 60 walkers / 25 cars
(downtown 44 / 18), all client-only, anchored, CanCollide/CanTouch/CanQuery false (CastShadow only on car bodies
and the torso / legs of walkers within 170 studs), under `workspace.CityLife`; Port Meridian also gets the client
far skyline `workspace.MetroFarSkyline` (beyond the walls, with the six tunnel gates at the street ends) and
impostors for streamed-out towers. Server parts it
changes locally: lamp plates tagged `MetroSignal` (Color), parts tagged `MetroNightGlow` (Material/Color/Transparency
at night), the Harbour Wheel (`MetroWheel`, CFrames). A cutscene or the shuttle camera inside a region simply sees
the crowd; nothing to switch off.
STATUS: already done (integrate: FYI, no API needed)

## 6. airport — two small things on your side (owner: airport; optional)
- `AirportBuilder` line ~1795: the car-park `ParkingSignPost` (x -338..-337, z 2402..2403, 12 studs tall) stands on
  Airport Road's south sidewalk, where Business City's walkers pass. MetroPlan.downtownObstacles now lists it so the
  walkers step round it; if you move it 3+ studs south (off the sidewalk band z ~2396..2408) tell metro and the entry
  can go.
- "Huge" Port Meridian (user request "riesig"): `CityPlan.ABROAD.rect` (1,400 x 1,200) is smaller than Business
  City's downtown. If a later round can afford it, an additive, larger rect (e.g. x +-1,000, same z) would let metro
  add a second ring of blocks; MetroPlan's layout is in absolute coordinates, so this needs a coordinated change
  (CityPlan rect + MetroPlan blocks / roads / walls), not a silent edit. For now metro raised the skyline instead
  (median tower 210 studs, 46 of 82 towers 200+, 7 of them 300+; Spire 468 + crown + mast) and made the street
  ends tunnel gates with traffic entering and leaving the city.
STATUS: dropped (integrate: ParkingSignPost - MetroPlan.downtownObstacles already routes walkers round it, and 3+ studs south would put it into the car-park entry lane; the larger Port Meridian rect needs a coordinated CityPlan + MetroPlan round with new blocks while the metro part budget is used up (5,253 / +4,500) - a later world round)

## 7. airport — terminal walk graph: three spots too close to scenery (owner: airport; found by tests/metro/test_paths)
The terminal crowd (airport.md #5, done) walks your `CityPlan.AIRPORT.walk` within 0.25 studs of the centre lines.
Sweeping it against the built terminal (body band, oriented boxes) finds:
- edge `loungeIn` (-244, 2501) -> `buffet` (-261.5, 2498) runs through the lounge's `MagazineRack` / `Magazine`
  at x -250..-247, z ~2500.5 (body radius 0.75 already hits) - please bend the edge (e.g. via a point at z 2503) or
  move the rack;
- edge `L270` (270, 2443) -> `arrival` (250, 2450) passes the `MeetingPointPost` at (262, 2446);
- posts 1.0-1.25 studs from a line (shoulders graze them): `QueuePost` at the desk-front rows (z 2457, x c +- ~2)
  and beside the gate boarding lanes (gx - 7, z 2513), `ShopPilaster`s on the food-court line z 2500.5
  (x 209-212, 251-254). 1.5 studs clearance from every centre line would make them clean;
- the decor luggage (`Suitcase`, `Trolley*`) stands in the queue lanes - exempt in the test as you allowed, but the
  walkers visibly pass through it; moving it beside the lanes (or listing its boxes in CityPlan so CityLifeController
  can step round them) would fix that.
test_paths prints these as PENDING (no failure); anything new fails.
STATUS: done by integrate (AirportBuilder: MagazineRack 2 studs long (1.6 off the edge loungeIn -> buffet), MeetingPointPost + sign moved to (264, 2449.5), 4 studs off L270 -> arrival; tests/metro/test_paths PENDING list emptied: metro_paths 6/0. Posts at 1.0-1.25 studs and the decor luggage only count as arm brushes - not changed)

