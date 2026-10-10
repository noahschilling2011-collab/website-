# Requests / interfaces from package "metro" (Port Meridian: MetroBuilder + MetroPlan; client city life: CityLifeController)

## 1. Lead — run_all: add the metro suites
Append to tests/lead/run_all.sh:
```
python3 harness/make_manifest.py --src work/src --gen harness/.gen_metro >/dev/null
for t in plan build life paths; do run "metro_$t" $L tests/metro/test_$t.luau -a .gen_metro; done
run metro_stress $L tests/metro/stress_traffic.luau -a .gen_metro 3
```
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

## 2. Lead / world — agents/world/world_check.py still has the old single budget (10,000)
tests/world/run.sh already uses agents/airport/world_check.py (per-zone budgets, abroad <= 20,000; today the whole
world is ~11,600 parts, Port Meridian ~4,090 = +3,300 over the pre-phase-2 city). agents/metro/world_dump.sh uses the airport copy as well. Adopt the
per-zone budgets in agents/world/world_check.py too (same request as airport.md #1).

## 3. flight — VIP helicopter: the markers (no change needed)
- Two parts named `Helipad` (landing surface = top face, collidable, anchored, attributes Purpose, PadId, PadName):
  `Purpose = "VIP"`, PadId `pm_hotel` on the Meridian Grand Hotel roof (top = `MetroPlan.HOTEL_ROOF + 1`, 40x40,
  under `PortMeridian/Hotel_intl_hotel/RooftopHelipad`) and `Purpose = "VIPAirport"`, PadId `pm_airport` beside the
  arrival terminal (top = GROUND + 1, 44x44, fenced, gate at the south-west corner, under `PortMeridian/VipHelipad`).
  Centres / sizes also in `MetroPlan.HELIPADS` (`cf` = centre of the top face).
- Nothing stands above either pad; windsock and roof lift house are outside the pad squares. The hotel roof has the
  marker `HelipadExit` (see flight.md #4 STATUS).
- The Meridian Spire (468 studs + 74-stud mast, x 0, z 8520..8576) stands 140 studs south of the hotel pad: approach
  the roof pad from the north (boulevard axis) as planned.

## 4. clients — VIP limousine stand (no change needed)
- Part `VipLimoStand` (under `PortMeridian/ArrivalPlaza/VipLimoArea`; invisible, no collision; attributes
  Purpose = "VIP", Zone = "abroad", Bays = 2, Bay2 = CFrame): its CFrame = bay 1 = car pivot on the road surface
  facing west in the lay-by on the north kerb of Arrivals Drive (`MetroPlan.VIP_LIMO.stand`, `.bay2`, `.layby`).
  Bay 1 is kept free for the chauffeur car; bay 2 holds a decorative model `Limousine` (hide it locally if the
  service parks there). Canopy "VIP CHAUFFEUR SERVICE", red carpet from the east terminal exit (x = 80).
  Leaving the stand: west along the lay-by into Arrivals Drive (dir -1 lane, `MetroPlan.portMeridian().lanes`).
- Lounge staff marker: invisible part `LoungeConciergePost` (attribute LoungePost = "concierge", LookVector = facing)
  behind the concierge desk of the Port Meridian `BusinessLounge` — for a hostess NPC (staff / talk packages).

## 5. Everyone — client city life (FYI, no API needed)
CityLifeController runs only while the camera is inside `MetroPlan.REGIONS` (Port Meridian x +-2600, z 6500..10200;
Business City x +-1260, z 700..2416 - City Airport's landside from z 2421 stays quiet): <= 60 walkers / 25 cars
(downtown 44 / 18), all client-only, anchored, CanCollide/CanTouch/CanQuery false (CastShadow only on car bodies
and the torso / legs of walkers within 170 studs), under `workspace.CityLife`; Port Meridian also gets the client
far skyline `workspace.MetroFarSkyline` (beyond the walls, with the six tunnel gates at the street ends) and
impostors for streamed-out towers. Server parts it
changes locally: lamp plates tagged `MetroSignal` (Color), parts tagged `MetroNightGlow` (Material/Color/Transparency
at night), the Harbour Wheel (`MetroWheel`, CFrames). A cutscene or the shuttle camera inside a region simply sees
the crowd; nothing to switch off.

## 6. airport — two small things on your side (owner: airport; optional)
- `AirportBuilder` line ~1795: the car-park `ParkingSignPost` (x -338..-337, z 2402..2403, 12 studs tall) stands on
  Airport Road's south sidewalk, where Business City's walkers pass. MetroPlan.downtownObstacles now lists it so the
  walkers step round it; if you move it 3+ studs south (off the sidewalk band z ~2396..2408) tell metro and the entry
  can go.
- "Huge" Port Meridian (user request "riesig"): `CityPlan.ABROAD.rect` (1,400 x 1,200) is smaller than Business
  City's downtown. If a later round can afford it, an additive, larger rect (e.g. x +-1,000, same z) would let metro
  add a second ring of blocks; MetroPlan's layout is in absolute coordinates, so this needs a coordinated change
  (CityPlan rect + MetroPlan blocks / roads / walls), not a silent edit. For now metro raised the skyline instead
  (median tower 204 studs, 46 of 85 towers 200+, 7 of them 300+; Spire 468 + crown + mast) and made the street
  ends tunnel gates with traffic entering and leaving the city.
