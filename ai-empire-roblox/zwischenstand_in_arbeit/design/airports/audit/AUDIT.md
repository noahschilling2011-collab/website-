# AIRPORT AUDIT - City Airport (main island) and Port Meridian airport (abroad)

Design task, read-only on the game. Date 2026-10-17. Owner wish 32 (notes_integration.md:154): "airport also on the other
island, main airport much better, PM airport even better, impressive hotel on PM, better game logic".
This file maps what exists TODAY so the concept/spec agents do not have to re-measure.

## 0. Evidence and method

* **Source snapshot**: `design/airports/audit/src_snapshot/` = copy of `work/src` taken 2026-10-17 09:20:53 UTC
  (`src_snapshot.TIMESTAMP`, md5 list `src_snapshot.md5`, 167 files). **Every `file:line` below refers to this snapshot.**
  Drift check at 09:5x UTC: AirportBuilder, MetroBuilder, CityPlan, MetroPlan, FlightPlan, JetPlan, DrivePlan, ItineraryMath,
  CityBuilder, CityLifeController identical to live `work/src`; **ShuttleService** (+5 lines at :437, `travellersLeg`) and
  **ItineraryService** (57 diff lines) were changed meanwhile by the running itinerary fix round - ShuttleService lines > 437
  are +5 in the live tree.
* **Isolated sandbox** (nothing written outside this folder): `design/airports/audit/sb/` = copies of `harness/*`,
  `tests/{airport,metro,flight,world}`, `agents/{world,airport,metro}/world_*`, `tools/blenderprev` (+5 audit shots appended to
  the copy of `shots.py`), `work/src` -> symlink to the snapshot. Generated manifests live in `sb/harness/.gen_*`.
* **Commands run (all exit 0) and their outputs** (raw logs in `data/`):

| command (cwd `sb/`) | output |
|---|---|
| `bash tools/blenderprev/world_dump.sh` | `world dump: {'collidable': 4411, 'instances': 16793, 'lights': 225, 'models': 348, 'parts': 14810, 'prompts': 32, 'seats': 12}` |
| `python3 agents/world/world_check.py out/blenderprev/world/world_dump.json out/world/world` | `new parts by zone: abroad 5139, airport 6550, district 39, downtown 1719, harbour 8, none 192` / `real lights by zone: abroad 40, airport 40, downtown 40 (district's own lights: 105)` / `terminal interior parts: 2988 (budget 3500)` / holes 0 in all zones / `map edge: 0 uncovered` / `WORLD CHECK: OK` |
| `tools/luau tests/airport/test_airport.luau -a .gen_audit` | `airport parts: interior 3145, exterior 1764, parked aircraft 1650` / `walk grid: 44163 of 66000 cells reachable` / `airport: 95 passed, 0 failed` |
| `tools/luau tests/metro/test_build.luau -a .gen_audit` | `Port Meridian: 5253 parts (+4472 over the pre-metro city), real lights abroad 40` / `metro_build: 42 passed, 0 failed` |
| `bash tests/flight/run.sh` | `flight_plan 95/0, flight_shuttle 111/0, flight_client 90/0, flight_aircraft 45/0, flight_clearance 18/0, pending obstacles 0` (9.9 s) |
| `tests/world/test_{cityplan,build,travel}.luau`, `tests/metro/test_{plan,life,paths}.luau` | 144/0, 27/0 (`world parts 13647 (downtown 1719, airport 6550, terminal interior 2988, abroad 5139), lights 120`), 51/0, 44/0, 46/0 (`PERF airport terminal (mock): 1800 steps, mean 1.61 ms`), 6/0 |
| `tools/luau tests/audit/probe_times.luau` (mine) | timetable / heli / jet numbers in section 4 (`data/probe_times.txt`) |
| `tools/luau tests/audit/probe_plan.luau` (mine) | seats 249, walk graph 145 nodes / 151 edges, stands, places (`data/probe_plan.txt`) |
| `tools/luau tests/audit/probe_far.luau` (mine) | flight paths vs client far-skyline shells (`data/probe_far.txt`, section 5 W2) |
| `tools/luau tests/audit/probe_stream.luau` (mine) | streaming modes + part counts of the airport models (`data/probe_stream.txt`) |
| `python3 scripts/count.py <dump> <root> 1`, `scripts/bbox.py` | per-sub-folder part / light / prompt counts and world AABBs (tables below) |

Coordinates: Roblox studs, `GROUND = CampusConfig.STREET_Y = 24` (CampusConfig.module.luau:9), +X east, **-Z north**,
Port Meridian lies far to the **south** (+Z). Floor of both terminals = G+0.5.

---------------------------------------------------------------------------------------------------------------------

## 1. City Airport (main island) - `AirportBuilder.module.luau` (2,057 lines) + `CityPlan.AIRPORT`

### 1.1 Layout (CityPlan.module.luau:335-370, measured AABBs from the dump)

```
 z 2361 ─ Airport Road zebras ─────────────────────────────────────────────────────────── (road z 2380, CityPlan:69)
 z 2400..2418  drop-off lane (x -330..330)      car park x -820..-340, z 2400..2528 (west)
 z 2418..2430  forecourt / kerb, canopy columns
 z 2430..2530  TERMINAL x -300..300 (600 x 100, one level, roof G+27.5 front .. G+40 crown .. G+31.5 back; AABB y 24..69.6)
 z 2530..2840  APRON x -700..700: stands A1 x-200 / A2 x0 / A3 x200 at z 2612 (nose north), jet bridges z 2530..2575,
               remote stand R1 (470,2640) static aircraft, R2 (575,2700) ambient visits, GSE parking x -560..-356
               hangar x -1000..-840, z 2560..2720 (door east) + company-jet stand (-772,2640); tower (820,2620); fuel tanks x 980
 z 2790        taxilane, lead-outs at x -450 / 450
 z 2840..2880  TAXIWAY x -1000..1000, connectors x -950 / 950 to the runway, hold-short z 2924
 z 2940..3060  RUNWAY x -1100..1100 (2,200 x 120), designators 09 / 27; approach lights to x +-1324
 z 3090..3183  service road, perimeter fence (z 3120), tree row;  z 3200 quay; harbour water to z 3800
```
Top views: `renders/map_city_airport_top.png` (whole zone), `renders/plan_city_terminal_floor.png` (floor-level cut).

| element | value | source |
|---|---|---|
| zone | x -1150..1150, z 2300..3200, drivable | CityPlan:43 |
| terminal | x -300..300, z 2430..2530, height 30; doors x -150/0/150 (12 wide) + arrivals door x 270 | CityPlan:336-337, 356 |
| check-in counters (prompts) | (-225/-75/75/225, G, 2461) | CityPlan:338 |
| security line / lanes | z 2485, lanes x -60/0/60 | CityPlan:339 |
| gates (CFrames) | (-200/0/200, 28, 2512) facing the apron | CityPlan:340 |
| arrival point | (250, 28, 2450) east end landside | CityPlan:341 |
| stands | x -200/0/200, z 2612, scale 1.8, `shuttleStand = 1` (A1) | CityPlan:346, 353-355 |
| apron / taxiway / runway | see diagram | CityPlan:345-348 |
| tower / hangar / company jet stand | (820,G,2620) / x -1000..-840 z 2560..2720 / lookAt((-772,G+.25,2640) -> east) | CityPlan:349-350, 361 |
| crew room / lounge rect | (-226,G+3.5,2491) / x -298.5..-238, z 2485.5..2529.2 | CityPlan:362-363 |
| car park bays | 8 bays row A x -355..-425, z 2421 | CityPlan:366-369 |
| taxi route data | stand -> (x,2790) -> (-450,2790) -> (-450,2860) -> (-950,2860) -> (-950,2924) -> (-950,3000) (stand 1, west end) | CityPlan:375-385, probe_plan |

### 1.2 Terminal shell + interior (AirportBuilder:1-27 header, shell :344-457, build order :2026-2054)
Shell: limestone floor, north glass facade with mullions every 12 and 2 transoms, entrance portals with "DEPARTURES" /
"ARRIVALS" signs, south (apron) glass with gate door openings that follow the jet bridges, stone end walls with glass gables,
curved roof (wood soffit + metal skin, 2 skylight bands, ribs every 40), name fascia + rooftop "CITY AIRPORT", canopy
columns on the kerb (:344-457). Structure (tree columns, beams, light strips) = 157 parts.
Interior = ONE Atomic model `TerminalInterior` (2,988 parts; probe_stream; AirportBuilder:2037) - zones (dump AABBs):

| sub-folder | x range | z range | parts | coll. | real lights | prompts |
|---|---|---|---|---|---|---|
| CheckinHall (islands A-D, kiosks, queues, boards, info desk, coffee bar) | -298.5..296 | 2433.5..2484.6 | 900 | 179 | 6 | 4 |
| Arrivals (carousel, GPS kiosk "Route to my HQ") | 246.5..298.5 | 2431..2483.5 | 68 | 8 | 1 | 1 |
| Security (serpentine, 3 lanes, e-gates, x-ray, arches) | -66.7..68.9 | 2452..2498 | 179 | 21 | 1 | 0 |
| BusinessLounge (Model, tag + Purpose) | -299.2..-237.7 | 2485.5..2529.2 | 197 | 45 | 2 | 0 |
| CrewRoom (marker "CrewRoom") | -238..-214 | 2485.5..2499.3 | 22 | 9 | 1 | 0 |
| Shops (news, bakery café, tech, duty free, restrooms) | -214..168 | 2485.5..2504 | 457 | 59 | 4 | 0 |
| FoodCourt (grill / noodle / deli + seating) | 168..298.5 | 2485.5..2528.5 | 279 | 88 | 2 | 0 |
| Restaurant | -158..-42 | 2506.8..2528.4 | 219 | 69 | 1 | 0 |
| QuietZone | 41..156 | 2506.8..2529 | 71 | 28 | 1 | 0 |
| GateA1 (shuttle gate) / GateA2 / GateA3 | -235..-165 / -35..35 / 165..235 | 2506.2..2529.1 | 179 / 164 / 164 | 75 each | 1 each | 0 |
| FloorPlan (terrazzo zoning) / Wayfinding | whole hall / -132..210 | | 69 / 20 | 0 / 2 | 0 / 1 | 0 |
| **TerminalInterior total** | | | **2,988** | 733 | 23 | 5 |

Seats: 249 seat pads (gate A1/A2/A3 64 each, landside 57) from 20 `CityPlan.AIRPORT.seatRows` (probe_plan; CityPlan:398-425).
These are pads, not `Seat` instances (the whole world dump has 12 `Seat`s). Walk graph 145 nodes / 151 edges, `walkers = 24`
(CityPlan:427-527); MetroPlan.airportNet adds seat spurs -> 167 nodes / 173 edges (MetroPlan:1146-1227).
Gates A2/A3 are dressed but signed **"GATE CLOSED"** (AirportBuilder:1245-1247); only A1 shows the shuttle.
Staff posts `AirportPost` (CityPost = checkin | security | gate | lounge | shop | crew) exist (AirportBuilder:24-25, :274) -
**no service reads them** (grep: only AirportBuilder mentions AirportPost/CityPost) -> no airport staff NPCs.

### 1.3 Apron, stands, jet bridges, vehicles (AirportBuilder:1406-1640)
* 3 parked airliners `ParkedAircraft` (AircraftModel "320", scale 1.8, collide) on A1-A3 (990 parts) + `RemoteAircraft` on R1
  (330 parts) (:1527-1536, :1578-1583).
* `JetBridges/JetBridge_A1..A3` (32 parts each, 25 collidable): straight two-section telescoping tunnel from the facade
  (z 2530) to a cab whose floor = the aircraft's DoorL1 sill, open side 0.6 off the fuselage, read from the built aircraft
  (:1406-1497). Attributes `Gate`, `Stand`, `TerminalDoor`, `AircraftDoor`; `BoardingPoint` part. Client-animated only for
  A1 (ShuttleGround retract/dock, FP.BRIDGE angle 5 deg, retract 4, time 4 s - FlightPlan:297-298).
* `GroundVehicles` 379 parts (all non-collidable): per stand pushback, tug + 3 carts, GPU, belt loader, catering, fuel truck,
  stairs, cones; shuttle stand keeps its sweep clear (staging box) (:1540-1571); GSE parking box x -560..-356, z 2570..2676
  (169 parts) and a coned holding box (:1599-1625).
* 4 flood masts at z 2716 (x -330/-100/100/330) = the apron's 4 real lights (:1626-1633).
* Markings: taxilane z 2790, lead-outs, stand lines, stop bars, equipment roads z 2541/2553 and 2712/2724 (:1520-1598).

### 1.4 Taxiway, runway, tower, hangar, perimeter, horizon, forecourt, car park
* Runway (159 parts): 2 asphalt halves, edges, dashes, piano keys, 09/27 digits, aiming points, threshold/end light bars,
  8 approach bars each end, neon edge lights every 100, windsock at (620, 2928) (:1652-1729). **No real lights** (neon only).
* Taxiway + connectors + hold-short lines + red "09 – 27" signs at x -918 / 982 (connector + 32) + blue neon edge lights (:1652-1680).
* ControlTower (Persistent, 8 parts, up to y 129.6; radar + beacon via PropFx FxFar 900) (:1897-1916).
* Hangar 1 (409 parts incl. the 330-part decorative `PrivateJet` = a 320 model at scale 0.9, hidden locally for companies that
  own a jet - JetController.module.luau:412-423), HangarInterior crew corner 61 parts, company-jet stand marker (:1917-1950,
  :1829-1895). One real light (HangarLight).
* Perimeter (93): fence z 3120, service road z 3090..3100, tree row (:1952-1972). Horizon (Persistent, 46 parts): sea from
  the quay to z 7500, coast land, hills, 3 islands at z 4150..4750 (:1974-2024).
* Forecourt (249 parts, 4 real canopy lights): drop-off lane, 4 taxis, 3 cars, 2 buses, bus shelter, bollards, totems,
  covered walkway to the car park (:1730-1794). CarPark (169 parts, 2 lamp lights) (:1796-1818).

### 1.5 Counts per sub-folder (dump, `scripts/count.py`)

| `WorldCity/Airport/...` | parts | collidable | real lights | prompts |
|---|---|---|---|---|
| Terminal (TerminalInterior 2,988 + shell 283 + Structure 157) | 3,428 | 795 | 23 | 5 |
| Apron (ParkedAircraft 990, GroundVehicles 379, RemoteAircraft 330, JetBridges 96, surface/markings 201) | 1,996 | 255 | 4 | 0 |
| Hangar (PrivateJet 330, HangarInterior 61, shell 11, stand area 7) | 409 | 61 | 1 | 0 |
| Forecourt | 249 | 48 | 4 | 0 |
| CarPark | 169 | 7 | 2 | 0 |
| Runway | 159 | 2 | 0 | 0 |
| Perimeter | 93 | 29 | 0 | 0 |
| Horizon (Persistent) | 46 | 0 | 0 | 0 |
| ControlTower (Persistent) | 8 | 4 | 1 | 0 |
| FuelTank (direct) | 2 | 2 | 0 | 0 |
| **Airport total** | **6,559** | 1,203 | **35** | 5 |

Test split (tests/airport/test_airport.luau:80-106): interior (TerminalInterior + Structure) **3,145 / 3,500**, exterior without
aircraft **1,764 / 2,000**, aircraft 1,650 (unbudgeted there). Airport zone by part centre (world_check): **6,550 / 7,000**.
Real lights in the airport zone: **40 / 40** = Airport 35 + 5 `Roads/StreetLampHead` on Airport Road (dump query). The hangar
comment already says "no real lights: the airport zone's light budget is full" (AirportBuilder:1826-1827).

### 1.6 Crowd / client life
* CityLifeController region "airport" = terminal rect x -300..300, z 2417..2560, y <= G+30 (MetroPlan:1235): **30 walkers,
  0 cars** (CityLifeController.module.luau:44, header :21-25) on `MetroPlan.airportNet()`; board/arrive through the A1 bridge.
  Mock perf `PERF airport terminal (mock): 1800 steps, mean 1.61 ms` (metro_life).
* GuestController terminal passengers (shuttle departures/arrivals from the real timetable) cap 40 (GuestController.module.luau:32,
  GuestPlan.module.luau:801-803).
* Ambient traffic (AirTrafficController, client): one runway visit per cycle (lands east, parks at R2, departs west) in the
  free slots + 2 sky crossings per cycle (FlightPlan:707-844). Only at City Airport.

### 1.7 What the player can actually do at City Airport
1. **Drive / be driven there**: DrivePlan places `airport_departures` stop (66, RT, 2413.5), door (66, WT+3, 2421.5) and
   `airport_arrivals` stop (300, RT, 2413.5) (DrivePlan.module.luau:335-351, probe_plan); own car into the car park (bays CityPlan:366).
2. **Check in** at counters A-D (prompt "Check in & fly", CityAction checkin, FlightTo abroad, 10 studs, hold 1;
   dump). Live ObjectText = `"Port Meridian · $700 return"` (CityService.module.luau:56-58, CityPlan:31); the harness dump shows
   "$1.5k" only because the harness passes its own text. Server: `Shuttle.ticket` spends $700 (return included) within 16 studs of
   a counter (ShuttleService:323-353). If the next boarding is > 180 s away the counter offers the instant "express/charter"
   flight = 10-s cutscene teleport (FlightPlan:50, TravelController.module.luau:3-12, CityService:76-121).
3. **Walk through security** to gate A1 (decor; no server check), sit in lounge/food court (decor; lounge has no access rule
   or perk - the `BusinessLounge` tag is read by nobody).
4. **Board**: server-made invisible "Board" prompt at the A1 desk (ShuttleService:146-161) or auto-board at the end of boarding
   when within `GATE_RADIUS = 36` of (-200, 28, 2512) (FlightPlan:224-230, ShuttleService:545-591). The character is
   anchored, hidden and parked at `FP.HOLD.home` = (-200, -16, 2612) under the stand (FlightPlan:234); the client shows the ride
   (cabin/chase camera). **The player never walks the jet bridge.**
5. **Arrive home**: server streams and `PivotTo` `AIRPORT.arrival` (250, 28, 2450) (ShuttleService `arrive` :589-616).
6. **Company jet** (stage >= 4, $900k + $8.5k/day, CORE_SPEC:449): owner-only prompt "Fly to Port Meridian" at the parked jet in
   Hangar 1 (JetService.module.luau:49-50, :212-214); pushback out of the hangar, taxi west edge, take-off; separation windows
   vs shuttle / ambient / other jets, `RUNWAY_BUSY` after 240 s (JetPlan:36-50, :455-650).
7. **Itinerary** (business trip, ItineraryService:1-50): driver -> `airport_departures` -> GPS beacon to gate A1
   (`IM.gatePoint("out")`, ItineraryMath:753-757) -> company booking (no ticket) -> flight -> ...; `IM.inAirport` = terminal
   rect + 24 (ItineraryMath:758-760).
8. **GPS kiosk** in arrivals "Route to my HQ" (dump prompt at (256, 27, 2444)).

---------------------------------------------------------------------------------------------------------------------

## 2. Port Meridian airport (abroad) - `MetroBuilder.airport()/apron()/lounge()/vipAirport()` + `CityPlan.ABROAD` + `MetroPlan`

### 2.1 Layout (CityPlan:531-543, MetroPlan:111, 126-158; top view `renders/plan_pm_airport_top.png`)

```
 z 7500  north edge of the PM zone (sea / client far-ground beyond)
 z 7520..7590  RUNWAY x -650..650 (1,300 x 70!), shuttle line FP.PM_LINE = z 7544 (11 studs north of centre)
 z 7590..7610  apron/shoulder concrete x -420..650
 z 7610..7690  ARRIVAL HALL x -160..160 (320 x 80, h 26), lounge in x -158.5..-104 | APRON x 160..548 (rects to z 7721.5):
               stand PM1 (252,7664) nose west into the ApronDoor x 160 z 7655..7667, stand PM2 (480,7664) parked 320
               heliport pad 44x44 at (604, G+1, 7670) + VIP helicopter terminal x 652..688
               low "airport" lots x -694..-214, z 7632..7716 (>= 75 off the runway centreline, test)
 z 7690..7760  ARRIVAL PLAZA x -200..200 (taxi rank x -200..-104, VIP limo lay-by x 104..200, stand (176, RT, 7762))
 z 7760+       Arrivals Drive (pm_arrivals), Meridian Boulevard south to the Meridian Grand (z 8362..8500)
```

| element | value | source |
|---|---|---|
| zone | x -700..700, z 7500..8700, not drivable (scripted cars only) | CityPlan:45, 532 |
| runway | x -650..650, z 7520..7590 | CityPlan:533 |
| terminal | x -160..160, z 7610..7690, h 26, doors x -80/0/80 (south) | CityPlan:534-535 |
| check-in "Fly home" | (-70/70, G, 7636) | CityPlan:536 |
| arrival point | lookAt((0,28,7655) -> south) | CityPlan:537 |
| apron / stands / door / taxi line | rects, stand (252,7664) & stand2 (480,7664) facing west, door x 160 z 7655..7667, taxiX 340 | MetroPlan:151-158 |
| helipads | airport (604, G+1, 7670) size 44 Purpose VIPAirport; hotel (0, HOTEL_ROOF+1 = 151.2, 8408) size 40 Purpose VIP | MetroPlan:126-135 |
| VIP limo stand / lay-by / taxi rank | (176, RT, 7762) facing west / x 104..200 / x -200..-104 | MetroPlan:138-143 |
| lounge | x -158.5..-104, door gap z 7644..7656 | MetroPlan:145 |

### 2.2 Arrival hall (MetroBuilder:242-339) and lounge (:341-415)
* Hall = CityBuilder's generic `hall()` box (flat roof slab, glass front/back, stone side walls, mullions every 24;
  CityBuilder.module.luau:553-575) + east-wall `ApronDoor` opening, stand ident, 7 roof "waves", spine, entrance canopy with
  4 columns, "PORT MERIDIAN AIRPORT · ARRIVALS" sign (:259-289).
* `TerminalInterior` (Atomic, **54 parts**): 2 check-in counters "Fly home" (`K.checkin`, ObjectText "City Airport · return
  ticket included"), GPS kiosk to the Meridian Grand, welcome sign, 3 neon ceiling bars = 3 real lights, static departure board,
  4 marble columns, 4 benches, baggage carousel + 4 suitcases, café counter + 4 stools, news kiosk, 3 hanging signs, 2 planters
  (:291-339). **No security, no gate, no airside, no jet bridge, no shops beyond the café/kiosk, no toilets, no seating rows.**
* `BusinessLounge` (Atomic, 90 parts, tag + Purpose + Zone abroad): frosted partition, concierge desk + `LoungeConciergePost`,
  bar "THE MERIDIAN BAR" with back-bar **bottle shelf** (:365-370), 3 sofa groups (real `Seat`s: 3 sofas + 6 armchairs), 3 work
  pods with seats, buffet, ceiling cloud, 6 pendants (2 real lights), flight screen, heli info (:341-415).
* Static departure board text: `PM 102 CITY AIRPORT CHECK-IN OPEN / PM 104 CITY AIRPORT ON TIME / VIP HELICOPTER ON REQUEST`
  (:297-299) - **"PM 104" does not exist** in FlightPlan (only PM 101 / PM 102, FlightPlan:48); the City Airport package
  enforces FlightPlan-only boards (tests/airport header "flight information = FlightPlan"), PM does not.

### 2.3 Airfield, apron, heliport (MetroBuilder:160-241, 417-462)
* Runway (asphalt, dashes every 120, edges, thresholds, neon edge lights every 130 - no real lights) (:242-256). **No taxiway**:
  a painted taxi line at x 340 from the runway edge to the stand line (:182-185).
* Apron concrete + shoulders x -420..650 between runway and hall (:171-174); stand marks, red safety boxes, walkway from the
  ApronDoor to PM1's forward door (:186-200, walkway :195-200); marker `ShuttleStand` (Stand PM1, Purpose Shuttle, attribute Door) (:202-205);
  PM2 = parked `ParkedAircraft` (330 parts, Stand PM2) with airstair wedge, GPU, baggage tug + carts, cones, "STAND 2" sign
  (:206-228); glass fence towards the city, runway side open (:230-240).
* VIP heliport (`VipHelipad`, 34 parts, 1 real light): pad + ring + H + 8 edge lights + windsock, fence with 2 gates, glass VIP
  helicopter terminal with canopy and red carpet (:417-462).

### 2.4 Counts (dump)

| `WorldCity/PortMeridian/...` | parts | coll. | real lights | prompts | note |
|---|---|---|---|---|---|
| Airfield | 437 | 57 | 0 | 0 | incl. ParkedAircraft 330 -> **107** runway/apron/fence/GSE parts |
| ArrivalTerminal | **188** | 65 | 5 | 3 | Hall 29 + TerminalInterior 54 + BusinessLounge 90 + 15 roof/canopy/sign |
| VipHelipad | 34 | 16 | 1 | 0 | |
| ArrivalPlaza | 125 | 40 | 3 | 1 | taxi rank, limo lay-by, metro entrance (decor), kiosk |
| **airport-related total** | **784** | | **9** | 4 | vs City Airport 6,559 parts / 35 lights |
| Port Meridian total | 5,253 | 1,611 | 40 | 9 | CityBlocks 1,192, Streets 1,094, HarbourQuarter 861, Greenery 458, ... Hotel_intl_hotel 78 |

The City Airport terminal (3,428 parts) is **18x** the PM terminal (188); per floor area 2,988/60,000 vs 144/25,600 sq studs
(0.050 vs 0.0056 parts per sq stud, ~9x sparser).

### 2.5 What the player can do at Port Meridian airport
1. **Arrive** by shuttle (teleport into the hall at `ABROAD.arrival`), by company jet (placed by the VIP limo stand,
   `JP.ARRIVAL.abroad` = (168, 27.3, 7750); JetPlan:101, probe) or not at all by road (CityPlan.route -> `FLIGHT_REQUIRED`, CityPlan:232-238).
2. **Fly home**: "Fly home" counters -> free ticket (`Shuttle.ticket`, abroad, price 0; ShuttleService:345); boarding = anywhere
   within 36 studs of `FP.PM_GATES` = ApronDoor inside point (148, 28, 7661), hall centre (0, 28, 7636) or either counter
   (FlightPlan:224-230, probe). No gate, no airside.
3. **VIP helicopter** to the Meridian Grand roof: client prompt on the airport pad (AirTrafficController.module.luau:175),
   $2,500 or free with the "limo" pass (ShuttleService:63, :671); ride 46.1 s each way; **arrival = hotel lobby** because "the roof
   pad has no way down" (ShuttleService:641-647); return from the lobby prompt (AirTrafficController:187). Heli waits on the airport pad and ferries.
4. **Limousine** (DriverService VIP limo, pm_limo stand (176, RT, 7762); DrivePlan:390-400) or walk; `pm_airport` drop-off kerb
   at (-75, RT, 7772.6), door (-80, PT+3, 7757) (DrivePlan:408-411, probe).
5. **Company jet**: 2 PM jet slots only - slot 1 "VIP apron" (600, AY, 7612) beside the heliport, slot 2 = stand PM2 (hides the
   parked airliner locally) (JetPlan:87-96) -> a third jet-owning company gets `PM_STANDS_FULL` (JetService:11, :505).
6. **Itinerary**: `IM.inPMAirport` = terminal rect +14 or plaza rect +14 (ItineraryMath:765-768); `Drive.PM_STAND_AREA` = the
   same two rects (DrivePlan:499-511); return leg drives to `pm_airport` (ItineraryService:981-997).
7. **Life**: Port Meridian walkers live outside (portals at the 3 terminal exits, MetroPlan:1040); inside only GuestController
   terminal passengers (GuestPlan.TERMINALS.pm, GuestPlan:803). No ambient airliners at PM (AirTrafficController :3-7).

---------------------------------------------------------------------------------------------------------------------

## 3. Budgets, streaming, separation

### 3.1 Port Meridian part budget test (the binding one)
`tests/metro/test_build.luau:20-21` `BASE_PARTS = 781`, `BUDGET = 4500` -> cap **5,281**; check at :37-38 counts **every
BasePart under `PortMeridian`**. Today 5,253 -> **28 parts left**. Real lights abroad <= 40 (:39): **40/40, 0 left**.
Other binding PM checks: only the Spire may be Persistent (:137-145), towers 75 studs off the runway (:126-132), stand 1 hull
box empty (:106-125), ApronDoor opening free (:93-102), lounge Atomic >= 8 seats (:57-61), 2 helipads + exit (:66-81).

How the Meridian Grand split counts the hotel (GRANDHOTEL_SPEC §19.1, must-fix F9 / CC-11): the metro test keeps BASE/BUDGET
unchanged and counts the hotel **frozen at 78 parts**; the hotel's own models get their own caps (Shell 950, GrandLifts 120,
Forecourt 110, RooftopHelipad 40, Interior 450, SkylineFloor 560, SpaFloor 440, SuiteFloor 600 -> hotel cap **3,250**).
GRANDHOTEL_SPEC's table says "5,257 ... 24 left" with the hotel frozen (4 sidewalk splits). => **An airport rebuild in PM needs
the same treatment** (own model(s), own cap, excluded from the metro count), because the metro budget has 24-28 parts left.

### 3.2 Zone budgets (agents/world/world_check.py:46-56, tests/world/test_build.luau:51-56)

| zone | parts now (by centre) | cap | left | real lights | cap |
|---|---|---|---|---|---|
| airport (z 2300..3200) | 6,550 | 7,000 | **450** | 40 | 40 (**0 left**) |
| terminal interior (TerminalInterior) | 2,988 (world_check) / 3,145 incl. Structure (airport test) | 3,500 | 512 / 355 | - | - |
| airport exterior w/o aircraft (airport test) | 1,764 | 2,000 | **236** | - | - |
| abroad (x +-700, z 7500..8700) | 5,139 (zone) / 5,253 (model) | 20,000 | 14,861 | 40 | 40 (**0 left**) |
| abroad after the Meridian Grand (§19.1) | <= 8,429 | 20,000 | ~11,571 | 40 (hotel keeps exactly 3) | 40 |
| downtown | 1,719 | 3,000 | 1,281 | 40 | 40 |
| whole shared world | 13,647 (WorldCity) | 30,000 | 16,353 | - | - |

Main-island counts: world dump 14,810 parts = TechDistrict 1,163 + WorldCity 13,647 (Airport 7,483 instances / 6,559 parts,
Downtown 1,775 inst., Roads 300, Ground 21). Each claimed HQ plot adds its own building (tier 4: 28,341 parts, GRANDHOTEL_SPEC §19.1).
Lights are a **real-PointLight budget enforced in code**: `CityBuilder.light` refuses the 41st light per zone and leaves a neon
head (CityBuilder.module.luau:57-64); build order = downtown, airport, Port Meridian, then street lamps (:592-604).

### 3.3 Streaming and separation
* Place settings set by `pack.py:128-133` (scripts cannot): StreamingEnabled, **MinRadius 128, TargetRadius 512**,
  ModelStreamingBehavior Improved, StreamOutBehavior Opportunistic, StreamingIntegrityMode MinimumRadiusPause
  (also CityBuilder.module.luau:11-17).
* Persistent airport models: `Airport/ControlTower` 8 parts, `Airport/Horizon` 46 parts; abroad only `MeridianSpire` 81
  (probe_stream). Atomic: City `TerminalInterior` 2,988 parts (one unit), PM `TerminalInterior` 54, PM `BusinessLounge` 90.
* Separation: City runway centre z 3000 vs PM runway centre z 7555 = **4,555 studs**; harbour edge z 3800 (CityPlan:529) to the PM
  zone z 7500 = **3,700 studs of sea** (Horizon OpenSea strips up to z 7500, AirportBuilder:1985-1987; islands at z 4150..4750).
  With TargetRadius 512 the zones never co-stream. Travel = server `RequestStreamAroundAsync(arrival, 8 s)` then `PivotTo`
  (CityService:96-108, CityPlan:33); the shuttle moves a held character 3 times (board, mid-cruise, arrival) (ShuttleService:20-26).
* Client-only geometry beyond the PM walls: `MetroPlan.FAR` 279 shells (bands w/e x 740..1780 out, n z 6900..7480, s z 9260..9700;
  MetroPlan:384-421) + FAR_GROUND, built by CityLifeController while the **camera** is in region "metro" x +-2600, z 6500..10200
  (MetroPlan:1232-1234, CityLifeController:1327-1345, :1479-1481). See weakness W2.

### 3.4 What the Meridian Grand will add (GRANDHOTEL_SPEC §19, built BEFORE any airport work)
+~3,172 parts in its own capped models (78 -> cap 3,250), **no new server light** (exactly 3), <= 3 client lights, ~295 MetroNightGlow
parts on the hotel (PM total 198 -> ~493), ~25 prompts, ~130 seats, <= 40 SurfaceGuis, 22 staff rig templates, client rigs <= 8 / guests <= 12;
PM zone total <= 8,429 parts (§19.1-19.3). Also: HelipadExit moves to the roof (52, 152.7, 8442) and `Shuttle.heliArrival("hotel")`
switches to the roof behind `GrandPlan.HELI_ROOF` (§11, §18.3); `pm_hotel` DrivePlan place is redone (§6.3).
**Consequence for airports:** after the hotel, PM still has ~11.5k zone parts but **0 server lights** and **24 metro-test parts**;
everything new for the PM airport must be (a) its own budgeted model excluded from the metro count, (b) lit by neon /
MetroNightGlow / client lights, (c) Atomic or Default streaming (Persistent is test-forbidden abroad).

---------------------------------------------------------------------------------------------------------------------

## 4. Flight paths and timing a redesign must keep working

### 4.1 Shuttle timetable (FlightPlan:34-52, :373-450; probe_times)
`interval` configured 360, built **368 s** (moving phases + boarding must fit). One aircraft, one cycle = leg "out" + leg "back".

| leg | flight | duration | boarding | pushback->deboard | phases (s) |
|---|---|---|---|---|---|
| out (City -> PM) | PM 101 | 208.3 | 75.5 | 117.8 | doors 5, pushback 16.5, taxi 23.0, takeoff 12.9, climb 9.8, cruise 14.6, approach 12.9, landing 14.6, taxiin 13.4, deboard 10 |
| back (PM -> City) | PM 102 | 159.7 | 30.0 (= max(pmBoarding, CREW_TURN 28)) | 114.7 | doors 5, pushback 11.9, taxi 9.1, takeoff 13.1, climb 8.9, cruise 16.6, approach 11.1, landing 19.4, taxiin 24.6, deboard 10 |

Out leg max altitude 602 (x -2850..1611); back leg 712 (x -1952..2982) (probe). Charter/express offered when boarding is > 180 s
away (FlightPlan:50). Crew: CREW_WALK 22, CREW_LEAVE 20, walkaround at PM 22 s from 3 s, CREW_TURN 28 (FlightPlan:588-593).

### 4.2 Geometry contract (FlightPlan:203-306)
* Home: stand = `A.standCFrames[shuttleStand]` = (-200, 24.25, 2612) nose north; pushback (-200,TL)->(-155,TL) r 32; taxi via
  exit x -450, taxiway z 2860, west connector x -950 onto the runway, roll east from x -890 to lift-off x 10 (`liftX = WEST+60+900`).
* Out air track: 17 control points from (liftX, HY, 3000) over the sea (1350,G+200,3150) ... (-2850,G+250,7400) to the PM final
  on `FP.PM_LINE` z 7544: (-1900,G+112) (-1300,G+55) flare (-850,G+14) touchdown (-600, PY) (FlightPlan:241-247).
* PM: roll-out to taxi line x 340-70, taxi north->stand line, nose-in to PM1 (252, 24.25, 7664) (FlightPlan:248-256); back leg
  pushback east to x 340 (+11 south), taxi, roll west to lift-off x -580, climb along PM_LINE until x < -1040, then north
  (FlightPlan:267-290), air track clamped never south of PM_LINE while x > -1100 (:282-284).
* Home arrival: westbound final along z 3000, flare (1150,G+22), touchdown (820,HY), roll-out to x -700, taxi back via the west
  connector / exit -450 / taxilane to the stand nose-in (:278-286).
* Gates / holds: `HOME_GATES` (-200, 28, 2512), `PM_GATES` 4 points, `GATE_RADIUS 36`, `HOLD.home` (-200,-16,2612),
  `HOLD.abroad` (252,-16,7664) (FlightPlan:224-234).
* Jet bridge + tug (client, A1 only): `FP.TUG {detach 3, home 18, aside 24}`, `FP.BRIDGE {angle 5 deg, retract 4, time 4}`,
  bridge parts named `BridgeOuter*` stay, others telescope (FlightPlan:297-298, :566-582; ShuttleGround.module.luau:1-14).
* Ambient (FlightPlan:707-844): R2 `AMBIENT_STAND` lookAt((575,HY,2700) -> north) (:716); slots placed outside the shuttle's
  runway windows - today slots at 5.0 s and 171.3 s of each cycle (arrival 84.1 s, parked 82.1 s, departure 94.3 s) + 2 sky
  crossings at 2,400-3,400 studs (probe_times).

### 4.3 Clearance gate (tests/flight/clearance.py, `tests/flight/clearance_dump.sh`)
Real hull (320, scale 1.8, full LOD) sampled on a 0.35-stud grid, every low pose (<150 studs AGL, 0.25 s) of both shuttle legs,
the ambient runway traffic and the heli transfer, against every visible **server** part (transparency < 0.99) inflated by
MARGIN 0.5; excluded: the A1 parked aircraft (hidden locally), markings < 0.5 above ground, heli skids; docked A1 bridge checked
with 0.25 and in its retracted frames (clearance.py:1-35, :190-203, :240-298). Today `flight_clearance: 18 passed, 0 failed,
pending obstacles 0`. **It does not see client-only geometry** (MetroPlan.FAR, CityLife cars/walkers, DriveController cars).
Any moved runway, stand, tower, light mast, fence, bridge or building near the tracks must re-pass this sweep; the airport
test also checks "no ground vehicle in the sweep of the shuttle on stand A1" and "taxiRoute points on paved collidable tops".

### 4.4 Company jet (JetPlan, guests_jet)
bizjet scale 1.6 (46 x 41.6 x 15.5 studs). Home: `HOME_PARK` (-930, 24.25, 2640) nose west inside Hangar 1, `HOME_STAND`
(-772, ..., 2640); pushback out of the hangar to x -700, taxi down the west apron edge x -700 to the taxiway, west connector,
roll east from x -905 to lift-off x -285 (JetPlan:81-83, :175-188). Air tracks = the shuttle's control points (same PM_LINE).
PM slots (600, AY, 7612) and (480, AY, 7664) (JetPlan:87-96). Durations (probe, delay 0): out 169.7 / 167.6 s, back 170.0 /
169.5 s (incl. towin 19.8), ferry 154 s. Separation fields "home", "rwy", "pm" (z PM_LINE-300..+46, x -1700..950, < 120 AGL),
"apron" (x < -660, z 2540..taxiway) (JetPlan:450-476; scheduler :637-650); maxDelay 240 s / 600 s empty (JetPlan:47-48).

### 4.5 VIP helicopter (FlightPlan:620-705, ShuttleService:620-695)
Pads: airport (604, 25, 7670) -> hotel (0, 151.2, 8408); spool 3 s, lift 7 s to hover +30, transit at max(pad Y)+60 along the
boulevard corridor x = 0, descend 9 s; **46.1 s** a->b, 46.0 s b->a, track 1,281 studs; to the hotel = ride then empty ferry back
(busy 94.2 s), to the airport = ferry out then ride (probe). Start radius 40 studs (|dy| <= 16) of the departure pad / lobby
(ShuttleService:64, :667). GRANDHOTEL_SPEC §11 requires the rotor circle r 16.4 and the approach along x = 0 from the north at
roof + 60 to stay free.

### 4.6 Hard contracts other code relies on (break one -> tests or runtime fail)
* Markers/names: `CheckinCounter` prompts (CityAction checkin, FlightTo, CheckinTo, Public), `GateA<n>/GateDesk`
  (ShuttleService:155-160 finds the board prompt spot), `JetBridge_A<n>` (TerminalDoor/AircraftDoor attrs, BridgeOuter* names),
  `ParkedAircraft` Stand/Gate attrs + `NoseGearZ`, `Pushback` vehicle nearest A1 (ShuttleGround), `FlightInfoBoard` tag
  (Board/Gate/Flight attrs, labels "FlightText"), `BusinessLounge` model (tag + Purpose), `CrewRoom` part, `CompanyJetStand`
  (Purpose CompanyJet), `Hangar/PrivateJet`, `AirportPost`; PM: `ShuttleStand` (Stand PM1, Door), `ApronDoor`, `ParkedAircraft`
  Stand PM2, `Helipad` x2 (Purpose VIPAirport / VIP, PadId), `HelipadExit` (To intl_hotel), `VipLimoStand`, `LoungeConciergePost`.
* Data used by other packages: CityPlan.AIRPORT (stands, standCFrames, apronTop, taxilane, exits, connectors, holdShortZ,
  companyJetStand, crewRoom, lounge, seats, seatRows, walk, gates, arrival, checkin, carParkBays), CityPlan.ABROAD (terminal,
  plaza, runway, checkin, arrival), MetroPlan.APRON / HELIPADS / VIP_LIMO / TAXI_RANK / LOUNGE / REGIONS.airport.
* Positional predicates: `IM.inAirport` (terminal +24), `IM.inPMAirport` (terminal/plaza +14), `IM.atGate` (36 / 14),
  `Drive.PM_STAND_AREA`, `Drive.PICKUP_RADIUS.airport = 140, pm = 110` (DrivePlan:50), DrivePlan places airport_departures /
  airport_arrivals / pm_airport / pm_limo, `GuestPlan.TERMINALS`, `MetroPlan.REGIONS.airport`.
* Economy: `CityPlan.TRAVEL.ticket = 700` = `CompanyOps.TRIPS.abroad.flight` (CORE_SPEC 11.4), HELI_FEE 2500, jet fuel per leg
  `Ops.JET.fuel/2`; DATA_VERSION 6 - nothing airport-related is saved (tickets/trips are memory-only).

---------------------------------------------------------------------------------------------------------------------

## 5. Weaknesses a player would notice (ranked; renders in section 6)

W1. **The "other island" airport is the weak one.** PM airport = 188-part generic hall + 107 airfield parts (+330 parked plane):
    no security, no gates, no airside, no jet bridge, no shops/food beyond a café counter and a news kiosk, flat slab roof with
    7 decorative fins (counts 2.4; MetroBuilder:242-339). Boarding is "stand within 36 studs of the hall centre / counters"
    (FlightPlan:224-230). Wish 32 asks for the opposite ranking (PM even better than City).
W2. **Aircraft fly through buildings at Port Meridian (client side).** The shuttle and the company jet pass *through* the
    client far-skyline shells west of the PM runway: pivot inside a shell 1.75 s on the out leg (5 shells), 1.25 s on the back
    leg (3 shells); jet out 2.0 s / back 1.25 s; heli 0 (probe_far: e.g. `out ... pos (-1460,94,7544) shell x-1481 z7568 w52 d82
    h77`). Cause: band "w" covers x -1780..-740, z 7380..8660 (MetroPlan:409) and FAR_CLEAR only clears tunnels (MetroPlan:374-382);
    clearance.py sweeps server parts only. *Not yet seen in Studio* - derived from the shared maths both clients use.
W3. **One flight, one destination, one aircraft.** 2 of 3 City gates say "GATE CLOSED" (AirportBuilder:1245-1247); boards show
    only PM 101/102; the PM board even lists a non-existent "PM 104" (MetroBuilder:299). A player can wait up to a full cycle
    (368 s) or take the instant charter teleport (FlightPlan:50).
W4. **You never walk to the plane.** Boarding anchors and hides the character under the stand (FP.HOLD) and arrival teleports
    into the hall (FlightPlan:231-234, ShuttleService arrive); jet bridges, the PM walkway and the ApronDoor are decoration.
W5. **The flight itself is short and the cruise tiny**: take-off to touchdown ~65 s (takeoff 12.9 + climb 9.8 + cruise 14.6 +
    approach 12.9 + landing 14.6) for 4,555 studs; boarding at home 75.5 s (probe_times).
W6. **Empty buildings, no staff, decor-only lounges.** No NPC behind check-in, security or gate desks (AirportPost unread);
    both BusinessLounges have no access rule or benefit (tag read by nobody); renders show the hall without life (runtime
    walkers exist only on the client: 30 + up to 40 passengers City, passengers only in the PM hall).
W7. **PM airfield is cramped**: 70-wide runway at the city's north edge (z 7520..7590 in a zone starting at 7500), hall face
    55 studs and towers >= 75 studs from the centreline (FlightPlan:211-214 comment says faces ~57) -> the 11-stud PM_LINE hack (FlightPlan:211-216); no taxiway; 2 jet slots -> PM_STANDS_FULL;
    no ambient traffic there; the arrival hall's long side faces the runway, the city side gets a canopy.
W8. **City Airport is flat and sparse outside the terminal**: one 600 x 100 single-level hall, flat curtain wall without a
    landmark (render), empty apron band z ~2700..2840 behind the stands and empty grass east of the terminal up to x 1150 except an
    8-part tower and 2 tanks (`renders/map_city_airport_top.png`); hangar is a metal box; the "private jet" for non-owners is a
    shrunken airliner (AirportBuilder:1930, `scale=.9`, default kind 320).
W9. **No light budget left** in either zone (40/40 each) -> runway, taxiway, hangar and the whole PM airfield are neon-only;
    a night redesign must use neon / MetroNightGlow / client lights.
W10. **Kid-friendly risk**: "THE MERIDIAN BAR" sign over a shelf of `Bottles` in the PM lounge (MetroBuilder:365-370) and a
    bottle shelf in the City lounge bar (AirportBuilder:965-966, `BOTTLES` palette :64). Rule: no alcohol (GRANDHOTEL critic
    swapped the hotel bar for a juice bar, notes_integration.md:143). (City-side duty free is labelled "fragrance · watches ·
    sweets", AirportBuilder:1124 - fine.)
W11. **VIP heli lands on the hotel roof but drops you in the lobby** (ShuttleService:641-647, "the roof pad has no way down") -
    already planned to change with the Meridian Grand (GRANDHOTEL_SPEC §11, §18.3).

## 6. Renders (blenderprev Cycles, preview quality 1024x576 16 spp, real geometry from the snapshot dump; SurfaceGui text,
runtime NPCs, client cars/walkers and client far-skyline are NOT drawn - see tools/blenderprev/README.md "Not represented")

Command (cwd `sb/`): `python3 tools/blenderprev/shots.py airport_terminal audit_hall audit_concourse audit_apron airport_aerial audit_pm_aerial audit_pm_hall --preview --res 1024x576 --out ../renders`
(render times 37-131 s each on a shared 4-core box, `renders/render_stdout.txt`). Camera positions in `sb/tools/blenderprev/shots.py` (audit_* entries).

| # | file | camera -> look | what I see (looked at each image) |
|---|---|---|---|
| 1 | `/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad/design/airports/audit/renders/airport_terminal_preview.png` | (-60,31,2330) -> (60,40,2428), existing shot | City terminal from Airport Road: one long, flat 30-stud glass wall under a thin blue roof edge, 4 canopy struts, a few cars/taxis/2 buses at the kerb, big empty grass verge in front. Reads as a regional terminal; no landmark element, no height accent, tower not visible from the front. |
| 2 | `/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad/design/airports/audit/renders/audit_hall_preview.png` | (-150,31,2440) -> (60,31,2470) | Check-in hall: the best part of the game's airports - tree columns, wood soffit, skylights, island C with screens, kiosks, queue belts, planters. Feels sterile (no people in the render; runtime has 30 client walkers + passengers), long narrow hall (100 deep), hanging sign boards block the eye line. |
| 3 | `/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad/design/airports/audit/renders/audit_concourse_preview.png` | (-150,30,2503) -> (120,30,2512) | Airside concourse: café counter left, food-court/restaurant seating behind a planter strip right, apron glass, pendant lights; a straight 600-stud corridor with one perspective. Good material work, but blocky furniture and no gate drama (the gates are side pockets). |
| 4 | `/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad/design/airports/audit/renders/audit_apron_preview.png` | (40,31,2560) -> (-200,36,2610) | Eye level at stand A2: jet bridge cab docked on the door, the white bellows tube reads as a blob on the nose, faceted cockpit, blocky GSE boxes (catering cart, tug). Fine from 50 studs, toy-like up close. |
| 5 | `/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad/design/airports/audit/renders/airport_aerial_preview.png` | (380,210,3180) -> (-40,30,2560), existing shot | Airside aerial: compact terminal with a nice curved skylight roof, 3 stands + remote stand, 4 flood masts, hangar far left, Business City behind. The apron behind the stands and the land east of the terminal are empty concrete/grass; only 4 aircraft for a 2,200-stud runway. |
| 6 | `/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad/design/airports/audit/renders/audit_pm_aerial_preview.png` | (-650,260,7330) -> (250,24,7650) | Port Meridian airport: a 70-wide runway squeezed on the waterline at the city's north edge, the arrival hall = a flat white roof slab with thin fins, a short apron with one parked airliner far east, the city towers directly behind. No terminal identity, no jet bridge, nothing that says "international airport". (The client far skyline west of the runway is not drawn - see W2.) |
| 7 | `/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad/design/airports/audit/renders/audit_pm_hall_preview.png` | (-60,31,7686) -> (120,29,7630) | PM arrival hall interior: an almost empty grey room - 4 white columns, 3 neon ceiling bars, a distant blue check-in panel, a few low benches, 2 planters, flat ceiling. This is the first room a player sees abroad. |
| 8 | `/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad/design/airports/audit/renders/map_city_airport_top.png`, `/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad/design/airports/audit/renders/plan_city_terminal_floor.png` | top views (world_check / plan_crop.py, y 24..33 cut) | Dense, well-zoned terminal plan (islands, security, shop band, gates, lounge west, food court east); outside it the apron is a flat rectangle and the east half of the zone is grass. |
| 9 | `/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad/design/airports/audit/renders/map_port_meridian_top.png`, `/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad/design/airports/audit/renders/plan_pm_airport_top.png`, `/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad/design/airports/audit/renders/plan_pm_terminal_floor.png` | top views | PM: runway on the north edge, hall + small apron + heliport in one strip, the lounge (west sixth, x -158.5..-104) is the only furnished part of the hall; the remaining 264 x 80 studs hold 2 counters, a carousel, a café and 4 benches. |
| 10 | `/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad/design/airports/audit/renders/map_home_world_top.png` | world_check map | The whole home island (district, Business City, airport, harbour) for context. |


## 7. Redesign constraints checklist (derived from sections 3-4)
1. Keep or migrate every marker / attribute / data field of 4.6 - tests/airport (95 checks), tests/metro test_build (42),
   tests/flight (341 + clearance 18), tests/world, tests/itinerary, tests/drivers, tests/guests_jet read them.
2. PM: new airport geometry must live in its own model(s) with their own cap and be excluded from the metro count (cap 5,281,
   24-28 left), like the Meridian Grand split; abroad zone cap 20,000 (~11.5k left after the hotel); no Persistent model abroad
   except the Spire (test); 0 server lights left -> neon / MetroNightGlow / <= a few client lights.
3. City: airport zone 450 parts left (7,000), terminal interior 355-512 left (3,500), exterior 236 left (2,000), 0 lights left.
   A "much better" City Airport needs those caps raised deliberately (and the airport test + world_check updated) or cuts.
4. Every change near the flight tracks re-runs `tests/flight/run.sh` (clearance sweep with the real hull, margin 0.5) and
   should add the client far skyline (W2) to the swept world or clear a corridor (FAR_CLEAR) along PM_LINE west of x -650.
5. Moving a runway / stand / gate changes FlightPlan (shuttle, 368-s cycle, ambient slots), JetPlan (tracks, PM slots, field
   windows, hangar paths), the ItineraryMath / DrivePlan predicates and places, GuestPlan.TERMINALS, MetroPlan.REGIONS and the
   CityLife airport walk graph - all data-driven from CityPlan / MetroPlan, so the data must move together.
6. Server-authoritative travel stays: ticket $700 (CompanyOps.TRIPS.abroad.flight), heli $2,500 / limo pass, jet fuel per leg;
   nothing saved (DATA_VERSION 6 untouched); kid-friendly (no bar / bottle imagery).
7. Order: Meridian Grand A/B first (GRANDHOTEL_SPEC), then airports (notes_integration.md:156).

## 8. Assumptions and limits (marked)
* W2 (aircraft through far shells) is computed from FlightPlan/JetPlan poses vs MetroPlan.FAR boxes (both shared, deterministic);
  **assumption**: CityLifeController has the far model parented while the camera is in region "metro" (code at
  CityLifeController:1340-1344 says so); not verified in Studio.
* Renders omit SurfaceGui text, NPCs, client cars/walkers, the far skyline, particles and Roblox lighting (blenderprev README);
  they show geometry, scale and emptiness only.
* Atomic streaming of the 2,988-part City `TerminalInterior`: the build comment says it "streams in complete"
  (AirportBuilder:16-17); its iPhone load cost was not measured (unsure).
* Part counts are mock (harness) counts of the snapshot; counts in the live tree can differ after other agents' edits
  (only ShuttleService / ItineraryService differed at the drift check, both without geometry).

## 9. Files
* this report: `design/airports/audit/AUDIT.md`
* renders: `design/airports/audit/renders/*.png`; top views `map_*.png`, `plan_*.png`
* dumps/logs: `design/airports/audit/sb/out/blenderprev/world/world_dump.json`, `data/*.txt`
* probes: `design/airports/audit/sb/tests/audit/probe_{times,plan,far,stream}.luau`; scripts `design/airports/audit/scripts/{count,bbox,plan_crop}.py`
