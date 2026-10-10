# Requests / interfaces from package "airport" (City Airport: AirportBuilder + CityBuilder + CityPlan additions)

## 1. Lead — world budgets (tests/world, agents/world)
The old single budget "WorldCity <= 10,000 parts" (tests/world/test_build + agents/world/world_check.py) no longer
fits phase 2 (airport rebuilt, Port Meridian expanded by "metro" to the brief's 15-20k). tests/world now checks per
zone: downtown <= 3,000, airport <= 7,000 (terminal interior <= 3,500), abroad <= 20,000, whole world <= 30,000;
Persistent <= 12 models / 800 parts (skyline + control tower + the airport's Persistent horizon backdrop + PM
landmarks). tests/world/run.sh uses agents/airport/world_dump.sh + agents/airport/world_check.py (copy of
agents/world/world_check.py with the per-zone budgets). Suggest: adopt the same budgets in agents/world/world_check.py
(line 45) so every package's world check agrees, or keep pointing at the airport copy.

## 2. Metro — MeridianBoulevard/MediaScreen has a negative size
`World/WorldCity/PortMeridian/MeridianBoulevard/MediaScreen` requested size `[24, 13.2, -0.15]` (clamped by Roblox)
-> agents/*/world_check.py "invalid sizes" FAIL (seen 11:50 UTC, MetroBuilder in progress).
STATUS: done by metro (min/max on the screen depth; tests/metro/test_build now also fails on negative / clamped sizes;
Port Meridian also got the same lounge hooks: tag "BusinessLounge", Purpose = "BusinessLounge", Zone = "abroad",
part `LoungeEntrance`)

## 3. Flight — what the airport provides (no change needed; FYI)
- Parked aircraft: `Airport/Apron/ParkedAircraft` (attributes Stand = i, Gate = "A<i>", NoseGearZ) built with
  `AircraftModel.build(apron, CityPlan.AIRPORT.standCFrames[i], {scale = CityPlan.AIRPORT.standScale (1.8), collide = true})`.
- Jet bridges `Airport/Apron/JetBridges/JetBridge_A<i>`: the cab is placed from the aircraft's **AircraftRoot/DoorL1
  attachment** (sill point, LookVector out of the fuselage; fallback `AircraftModel.points("320", scale).doorL1`), cab
  floor at the sill, opening 0.6 studs off the door. Attributes `AircraftDoor`, `TerminalDoor` (Vector3); part
  `BoardingPoint` (Gate, Stand, AircraftDoor) inside the cab. If DoorL1 moves, the bridge follows automatically.
- Stop bar / pushback: from the frontmost centre-line part with attribute `Gear = true` (nose gear).
- `CityPlan.taxiRoute(stand, "west"|"east")` (stand -> taxilane -> lead-out -> taxiway -> connector -> hold short ->
  runway centre line, y = apronTop); every point and leg is on pavement (tests/airport checks it).
- Markers: part `CrewRoom` (Purpose = "CrewRoom", attribute Door) at `CityPlan.AIRPORT.crewRoom`; part
  `CompanyJetStand` (Purpose = "CompanyJet", Scale = 0.9, 46 x 60 box free of collidables) at
  `CityPlan.AIRPORT.companyJetStand` (nose east, in front of Hangar 1); `CityPlan.AIRPORT.shuttleStand = 1`
  (departure boards and the crew briefing screen say gate A1).
- Shuttle stand (`CityPlan.AIRPORT.shuttleStand`): only the pushback tug, GPU and tug + carts stay; belt loader and
  catering truck wait in the staging box ahead of the wing (flight.md #5, checked by tests/airport against the hull).
- TravelController's cutscene plane is now a full-LOD AircraftModel (270 parts, client only); tests/world/test_client
  allows <= 400 parts. Consider `lod = "medium"` there.

## 4. Later VIP / staff packages — hooks in the terminal
- Model `BusinessLounge` (tag "BusinessLounge", attribute Purpose = "BusinessLounge") inside TerminalInterior; its
  doorway part `LoungeEntrance` (invisible, non-colliding, Purpose = "BusinessLounge"); rect `CityPlan.AIRPORT.lounge`,
  door point `CityPlan.AIRPORT.loungeDoor`.
- Staff posts: invisible parts `AirportPost` (CityPost = checkin | security | gate | lounge | shop | crew | info,
  BuildingId = "airport", Desk = A..D / lane1..3 / A1..A3 / news, cafe, tech, dutyfree, food1..3, restaurant),
  LookVector = facing; every post is reachable (tests/airport walk grid, agent radius 1).

## 5. Metro (CityLifeController) — a light walker set inside the City Airport terminal
The terminal reads empty because CityLifeController switches its crowd off in the "City Airport" region
(CityLifeController lines 17-19) and nothing else populates it. The airport package now provides the data
(CityPlan, additive, checked by tests/airport):
- `CityPlan.AIRPORT.walk = {nodes, edges, byName, walkers = 24}` in the MetroPlan WalkNode / WalkEdge shape
  (`{id, name, p, links, idle?, face?, portal?}` / `{id, a, b, half, len}`), p at the terminal floor top
  (GROUND + 0.5). Doors (`door1..3`, `doorArr`, portal = true) -> landside line z 2443 -> serpentine queues of
  check-in A-D (`Q<i>a..g`, idle "queue") -> desk fronts (`Q<i>desk<j>`, idle "checkin", face = the desk) -> exit
  west of each island; security lanes 1-3 (`S<i>gate`, `S<i>egate`, `S<i>divest` / `S<i>recompose` idle
  "security", `S<i>arch`, `S<i>out`; lane 2 has its serpentine `S2a..g`) -> airside concourse z 2503 (`C<x>`)
  -> gates `A1..A3` (idle "gate"), desk fronts `A<i>desk`, boarding lane `A<i>lane` -> `A<i>board` (at the
  jet-bridge door), lounge (`loungeDoor`, `reception`, `buffet`, `bar`), shops (`news`, `cafe`, `tech`,
  `dutyW`, `dutyE`), `restrooms`, food court (`F1..F3`, stall fronts `grill`, `noodle`, `deli`), arrivals
  (`arrival`, carousel `reclaimW` / `reclaimN`). Every node and edge lies on reachable floor (walk grid,
  radius 1) and never crosses a queue belt, post or sign.
- `CityPlan.AIRPORT.seats = {{p, face, gate?}}` — 249 seat positions (pad top) in the gate lounges (gate =
  "A1".."A3"), by the doors, at the information desk, on the two seating islands and at baggage reclaim.
- The shuttle gate is `"A"..CityPlan.AIRPORT.shuttleStand` (A1); A2 / A3 are closed (no flights), so waiting
  crowds belong at A1, the food court, shops and the lounge.
Request: run 20-30 walkers (`walk.walkers` = 24) in the terminal while the camera is inside the region
(x -300..300, z 2430..2530), client-only like the rest of CityLifeController; sitting walkers on `seats`.
Note: decor luggage (parts `Suitcase` / `Trolley*`, non-colliding) stands in the check-in queue lanes; walkers
may pass through it or treat it as obstacles.
STATUS: done by metro (2026-10-10). CityLifeController has a third region "airport" = the terminal's x range
(-300..300) from the forecourt to the jet bridges (z 2417..2560, so the hall is filled before a player reaches the
doors or leaves a docked shuttle; camera below the roof line GROUND + 30): 30 walkers (top of the requested 20-30 - with 24
the 600-stud hall read thin in the renders), no cars, on
`MetroPlan.airportNet()` = your `CityPlan.AIRPORT.walk` read-only (links converted to edge ids) plus metro's seat
spurs: the first row of gate A1 facing the concourse (8 pair nodes = 16 seats, spurs from the concourse line) and the
north sides of the two landside seating islands (6 pair nodes from L-150 / L150); a spur node serves two seats like
a bench (seat = pair centre at floor level). The A1 boarding point is a portal (walkers board / arrive through the
jet bridge), the doors spawn / despawn; A2 / A3 boarding points carry no idle. Idle kinds queue / checkin /
security / gate / shop / food / lounge / reclaim / wait are used as given (face = your face). Walkers keep within
0.25 of your centre lines (your graph guarantees a radius-1 agent on the line). Client-only, deterministic, asleep
outside the hall (forecourt, car park, apron, flight). Tests: tests/metro/test_life (30 walkers, 0 cars, on the
graph, inside the hall, floor level, sitting + >= 3 idle kinds, recycling, PERF ~1.5 ms per step in the mock),
test_plan (net connected, links consistent, >= 10 seat spurs, portals), test_paths (sweep vs the real terminal:
metro's seat spurs clear at body radius 1.0; your graph clear at 0.75 except the PENDING items in
design/requests/metro.md #7 - decor luggage exempt as you allowed).

## 6. Flight (ShuttleController) — live rows on the airport's flight information boards
All airport flight information now shows only the one shuttle (FlightPlan.CONFIG.flights out / back, gate
A<shuttleStand>, no clock times, no static "BOARDING"). Every board part carries the tag `FlightInfoBoard` and
attributes `Board` = "departures" | "arrivals" | "monitor" | "gate" | "gatedoor" | "belt", `Gate` ("A1" or
"BELT 1"), `Flight` ("PM 101" / "PM 102"); its SurfaceGui TextLabel(s) are named `FlightText` (the static text
is the fallback). Request: ShuttleController writes live rows into them client-side (as it does for
GateBoardHome), e.g. departures "PM 101  PORT MERIDIAN  A1  BOARDING / DEPARTS IN 3:20", once per second at most,
only for boards within ~150 studs; no server writes.
STATUS: done by flight (ShuttleGround.boardText / writeBoards: every FlightInfoBoard within 150 studs of the camera,
once per second, client-only; departures / monitor / gate / gatedoor rows = BOARDING / GATE CLOSED / DEPARTED / ON TIME
+ m:ss, arrivals / belt = EXPECTED / LANDED / ARRIVED / BAGGAGE ON BELT; the old pixel-sized GateBoardHome billboard is
gone; checked in tests/flight/test_client).

## 7. Life (PropFxController) — per-prop activation range
PropFxController only animates props within FAR = 120 / VERTICAL = 24 studs of the camera, so the control tower's
radar (spin, y ~ G+95) and beacon (blink, G+104, x = 820) never run for anyone on the ground or in the terminal.
Both props now carry `FxFar = 900` and `FxVertical = 200`. Request: honour optional per-prop `FxFar` /
`FxVertical` attributes in the scan (fallback to the defaults). Until then the report no longer claims they
animate.
STATUS: done by staffops (PropFxController.register reads FxFar / FxVertical, Controller.scan uses them per prop;
defaults FAR 120 / VERTICAL 24; tests/staffops client suite: a spin prop with FxFar 900 / FxVertical 200 is active
500 studs away, a normal prop there sleeps)

## 8. Lead — budgets and the old world check
- Airport zone: real lights 40 / 40 (a later staff / polish package cannot add one without removing one).
- Airport exterior sub-budget (tests/airport: old 222 + 1,500 = 1,722): 1,703 after this round (axle wheels are
  one cylinder per axle now, which freed ~130 parts for the west-apron GSE parking). Suggest raising it to
  2,000 (world check 2026-10-10: airport zone 6,489 / 7,000; terminal interior 2,988 / 3,500 in the world check,
  3,145 / 3,500 in tests/airport, which also counts the hall structure).
- agents/world/world_check.py still has the 10,000-part world total (the world is ~13,500 now) and fails if
  run; please retire it in favour of agents/airport/world_check.py (per-zone budgets, #1), which now also has
  a map-edge check (no slit along |x| = 1150 for z -800..3800 and along z = 3800).
