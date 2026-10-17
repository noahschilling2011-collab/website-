# Airport concept "MAX WOW PER PART" (both airports, iPhone first)

Concept 3 of the airports design round (angle: biggest visual upgrade inside honest budgets). Design only: nothing under
`work/`, `tests/`, `agents/stable/` or the existing `design/` files was edited. Date 2026-10-17.
Evidence and scripts: `design/airports/concept_budget_work/` (own sandbox `sb/` with a source snapshot, probes, plots).
Paths are relative to `scratchpad/` = `/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad`.

---------------------------------------------------------------------------------------------------------------------

## 0. One page

**Idea.** The game already has two expensive habits: it spends parts where nobody looks (1,650 parked-aircraft parts at City
Airport, 330 of them hidden locally by every client) and it spends nothing on the three things a phone player actually
notices: a silhouette you can read, light at night, and movement. This concept moves parts, it does not just add them:

1. **Reclaim** what nobody sees (measured: 1,976 server parts at City Airport).
2. **Re-spend** them on a few large shapes (an upswept roof edge, a wing roof, two towers). Each shape is an extruded
   profile, so it costs 5 to 75 parts, not hundreds.
3. **Light with neon and glow tags, not real lights.** Both airports keep their exact real-light counts (City 35, PM 9).
4. **Put clutter and motion on the client** (suitcases, trolleys, shop goods, ground vehicles, staff, baggage trains) inside
   a hard client cap, built only near the camera.
5. **Meshes are an upgrade, never a budget.** There is an optional Blender kit (the same owner-import pattern as the
   aircraft and the limo). Every budget below is counted on the part fallback.

| | City Airport "Sky Wave" (main island) | Port Meridian "Meridian Wing" (abroad) |
|---|---|---|
| Hero shapes | upswept 20-stud front roof lip with a neon edge over the kerb, deep facade fins, tree columns, a better tower (Persistent, same height) | a wing roof rising to G+52 over the hall and plaza, the **Sky Deck** mezzanine where planes pass 60-90 studs from you, the **Meridian Tower** (G+120) |
| Walk to the plane | walkable A1 jet bridge, board at the cab | **tarmac walk** under a lit canopy to the airstairs, a client marshal with wands |
| Arrival | unchanged hall; life added | **sea approach**: fixes the planes flying through buildings (W2), adds a water corridor and an approach-light pier with a client "rabbit" |
| Server parts | 6,559 -> **5,166** (zone 6,550 -> 5,157 of an **unchanged 7,000 cap**) | airport scope 784 -> **~2,357 (cap 2,650)**, kept out of the metro count like the hotel |
| Real lights | 35 (zone stays 40/40) | 9 (zone stays 40/40) |
| Device load (parts within 512 studs, incl. client + walkers) | kerb 5,533 -> 5,419; gate A1 5,718 -> 5,940 | hall 2,368 -> 4,395; worst point (boulevard midpoint, hotel + airport) 7,972 |

Budget changes: **City none** (zone, interior, exterior and light caps all unchanged). **PM one**: the four airport folders
are frozen at 784 in `tests/metro/test_build.luau`, exactly as GRANDHOTEL freezes the hotel at 78, and get their own cap of
2,650. The abroad zone cap (20,000) still binds: about 10,000 (estimate) or 10,295 (all caps full).
For scale: the game's own tier-4 office is 28,341 parts, 207 lights and 1,714 GUIs in one model (measured, section 2.4). Every
airport viewpoint stays at most at about 28 % of it (worst: 7,972 at the boulevard midpoint, with the hotel).

**Biggest risk:** none of the device numbers has been measured on a real iPhone. They are streaming-radius proxies from the
mock world dump; the project has no device profile for any scene. The specific new risk is the client detail layer: about 1,170 City parts move
from the server to a client controller. That keeps server budgets honest, but it can hitch or pop in on a phone. Mitigations
(section 9): builds spread over frames (at most 120 parts per frame), a pre-fill margin around each region, and the kill switch
`AirportsPlan.CLIENT_DETAIL = false`. Second risk: the PM north roof edge is only 5.2 studs (in plan) from the shuttle's
wingtip line, so the real-hull clearance sweep decides it.

---------------------------------------------------------------------------------------------------------------------

## 1. Evidence, labels, method

Labels: **[M]** measured (file:line or a command with its output), **[D]** a design value set by this concept,
**[A]** an assumption, **[S]** only Studio or a real iPhone can confirm.

* **Source.** The geometry files are identical in the live `work/src` and the audit snapshot. I checked this with
  `cmp` over all 167 files at 10:55 UTC: only ItineraryMath, ShuttleService, DriverService, ItineraryService, JetService and
  ItineraryController differ, none of them geometry. My own snapshot is `concept_budget_work/sb/src_snapshot/`
  (taken 2026-10-17 11:02:55 UTC, `src_snapshot.md5`, 167 files); manifest `sb/harness/.gen/`.
* **World dump** (read-only): `design/airports/audit/sb/out/blenderprev/world/world_dump.json` (audit, 14,810 parts) and
  `out/hotelpolish/dump_tier4.json` (one tier-4 office).
* **Commands (all exit 0), outputs in `concept_budget_work/`:**

| command (cwd `concept_budget_work/`) | key output |
|---|---|
| `python3 measure.py <world_dump> <dump_tier4>` -> `measure_out.txt` | per-group inventory; parts / lights / GUIs within 128 / 256 / 512 studs of 11 viewpoints; tier-4 office `28341 parts, 207 real lights, 1714 SurfaceGui/BillboardGui` |
| `python3 names.py <dump> World/WorldCity/Airport` -> `names_city.txt`; `../audit/scripts/count.py <dump> World/WorldCity/Airport 2` -> `count_city_d2.txt` | part-name histograms (e.g. `QueuePost 132`, `Goods 183`, `Suitcase 96`) |
| `sb/probes: ../../../../../tools/luau probe_lod.luau` -> `probe_lod_out.txt` | `kind=320 lod=full parts=330 / medium 76 / low 30`; `bizjet full 271 / medium 76 / low 26`; `380 full 331 / medium 134 / low 49` |
| `tools/luau probe_doors.luau` -> `probe_doors_out.txt` | `DoorL1 world=-206.24, 37.88, 2570.74` for **all three LODs** (jet bridge docking survives an LOD change) |
| `tools/luau probe_corridor.luau` -> `probe_corridor_out.txt` | today: shuttle / jet min distance to a far shell **0.0**; with corridor x -1800..-700, z 7394..7694: `removes 23 of 279 shells`, min distance **141.6** (shuttle) / **123.4** (jet out) |
| `tools/luau probe_client.luau` -> `probe_client_far.txt`, `probe_client_out.txt` | `far skyline + impostors client parts: 574 (test cap 700)`, `one walker figure: 9 parts`, per-folder counts, `lights 40 40 40` |
| `python3 project.py <dump>` -> `project_out.txt` | the device-load projection in section 7.4 |
| `python3 apicheck.py ../../../tools/API-Dump.json apis.txt` -> `apicheck_out.txt` | `checked 122, missing 0` (flags in Appendix B) |
| `python3 plans.py <dump> .` | `plan_city_budget.png`, `plan_pm_budget.png`, `plan_pm_approach.png` (looked at each one) |

Coordinates: Roblox studs, `G = CityPlan.GROUND = 24`, +x east, **-z north**; Port Meridian is far south (+z).

---------------------------------------------------------------------------------------------------------------------

## 2. The budget truth today [M]

### 2.1 Server parts per group (`measure_out.txt`; dump of the audit snapshot)

| group | parts | aircraft parts | real lights | GUIs | translucent area* |
|---|---|---|---|---|---|
| City Terminal (TerminalInterior 2,988) | 3,428 | 0 | 23 | 221 | 70,930 |
| City Apron | 1,996 | 1,320 | 4 | 12 | 2,027 |
| City Hangar | 409 | 330 | 1 | 10 | 37 |
| City Forecourt / CarPark / Runway / Perimeter / Horizon / Tower | 249 / 169 / 159 / 93 / 46 / 8 | 0 | 4 / 2 / 0 / 0 / 0 / 1 | 12 / 1 / 0 / 0 / 0 / 0 | - |
| **City Airport total** | **6,559** | **1,650** | **35** | **255** | 96,115 (excluding sea) |
| PM Airfield / ArrivalTerminal / VipHelipad / ArrivalPlaza | 437 / 188 / 34 / 125 | 330 / 0 / 0 / 0 | 0 / 5 / 1 / 3 | 4 / 25 / 1 / 8 | 21,212 together |
| **PM airport scope** | **784** | 330 | **9** | 38 | |
| Port Meridian total | 5,253 | 330 | 40 | 230 | |

\* sum of each part's largest face, for parts with 0.05 < Transparency < 0.95 (the GRANDHOTEL critic's metric, GRANDHOTEL_SPEC
§19.3), sea, water and horizon parts excluded (`translucent_out.txt`).

### 2.2 Caps that bind today

| cap | where | now |
|---|---|---|
| airport zone <= 7,000 by part centre | `agents/world/world_check.py:48`, `tests/world/test_build.luau:54` | 6,550 (450 left) |
| terminal interior <= 3,500 (TerminalInterior + Structure) | `tests/airport/test_airport.luau:102` | 3,145 |
| airport exterior without aircraft <= 2,000 | `tests/airport/test_airport.luau:106` | 1,764 |
| PM: 781 + 4,500 = 5,281 for **every** BasePart under `PortMeridian` | `tests/metro/test_build.luau:20-21, 38` | 5,253 (28 left; 24 once the hotel is frozen at 78, GRANDHOTEL §19.1) |
| abroad zone <= 20,000; world <= 30,000 | `world_check.py:48`, `tests/world/test_build.luau:55-56` | 5,139 / 13,647 |
| real PointLights <= 40 per zone; the 41st is refused and a neon head stays | `CityBuilder.module.luau:25, 57-64` | airport 40/40, abroad 40/40 |
| only the Meridian Spire may be Persistent abroad | `tests/metro/test_build.luau:141-145` | 1 model |
| far skyline + impostors <= 700 client parts | `tests/metro/test_life.luau:144` | 574 (`probe_client_far.txt`) |

### 2.3 Where City Airport's parts go and who sees them [M]

| item | parts | who sees it | source |
|---|---|---|---|
| A1 `ParkedAircraft` (full LOD) | 330 | **nobody**: every client hides it and shows its own shuttle (`LocalTransparencyModifier = 1`) | `ShuttleController.module.luau:145-170`, `AirportBuilder.module.luau:1531` |
| `RemoteAircraft` R1 (470, 2640), full LOD | 330 | from the terminal at least ~205 studs away (food court x 298, z 2528); only a player who walks out onto the apron gets closer | `measure_out.txt` aircraft list |
| Hangar `PrivateJet` = a 320 airliner at scale 0.9 | 330 | non-owners only; owners get it hidden. It is the wrong model (W8) | `AirportBuilder.module.luau:1930`, `JetController.module.luau:412-433` |
| non-collidable interior clutter: Suitcase 96, SuitcaseHandle 45, Trolley* 176, Goods 183, ShelfBoard 57, QueuePost 132, QueueBelt 26 | **715** | only from inside the hall | name histogram (all `canCollide = false`) |
| ground vehicles outside stand A1 (GSE parking 169, remote stand 40, A2/A3 sets) | 337 | from the gates and apron | `GroundVehicles` breakdown |
| car-park cars | 116 | from Airport Road and the car park | `CarPark/Car` |

Measured LOD costs (`probe_lod_out.txt`): 320 full 330 / medium 76 / low 30; bizjet full 271 / medium 76. All LODs keep
`AircraftRoot` and `DoorL1` at the same position (`probe_doors_out.txt`), so jet bridges and `NoseGearZ` still find their door.

### 2.4 What a phone holds: streaming load at viewpoints [M]

Place settings: StreamingEnabled, MinRadius 128, **TargetRadius 512**, Improved, Opportunistic, MinimumRadiusPause
(`pack.py:128-133`); Lighting Technology Future, GlobalShadows on (`pack.py:135-142`). Proxy = server parts / real lights /
GUIs whose centre lies within 512 studs (3D) of the camera point.

| viewpoint | parts <= 512 | lights <= 512 | GUIs <= 512 |
|---|---|---|---|
| City kerb (departures stop 66, 2413.5) | 5,533 | 37 | 242 |
| City check-in hall centre | 5,539 | 35 | 242 |
| City gate A1 | 5,448 | 36 | 240 |
| PM arrival hall centre | 1,828 | 20 | 104 |
| PM arrival plaza | 2,062 | 22 | 116 |
| PM hotel door (GRANDHOTEL ref.; their critic measured 2,514 flat) | 2,469 | 19 | 108 |
| **reference: one tier-4 office** (`out/hotelpolish/dump_tier4.json`) | **28,341** (whole model) | **207** | **1,714** |

Client crowds come on top: CityLife walkers are 9 parts each (`probe_client_out.txt`); caps are 30 in the City terminal and
60 in Port Meridian (`CityLifeController.module.luau:44`).

---------------------------------------------------------------------------------------------------------------------

## 3. The method: what buys wow cheaply, and what this concept will not use

| technique | cost | why it pays | used for |
|---|---|---|---|
| **Extruded profile** (roofs built as long slabs, one per profile segment, spanning the whole building; City already does this, `AirportBuilder.module.luau:320-335`) | ~2 parts per segment + edges | a 600-stud curved roof costs as much as one sofa group | City lip, PM wing, PM plaza canopy |
| **LOD as a reclaim** (`AircraftModel` lods full / medium / low, measured above) | 330 -> 76 / 30 | the same silhouette at the distances people actually see | A1 (hidden anyway), R1, PrivateJet -> bizjet, new R3 |
| **Neon + `MetroNightGlow` tags** (CityLife lights tagged parts at night, `CityLifeController.module.luau:1047-1076, 1500-1504`) | 0-5 parts | night drama without touching the 40-light caps; **only opaque parts** are tagged, because CityLife turns a tagged part into near-opaque Neon (Transparency <= 0.15, `CityLifeController:1048-1050`) and GRANDHOTEL §5.4 forbids tagging real glass | facade fins, roof edges, tower cab bands, fence rails, walkway |
| **PropFx motion** (spin / blink / belt, client-animated, server writes nothing; `design/PROPFX_CONTRACT.md`) | 0 extra parts | movement draws the eye more than detail does | tower radars and beacons, baggage belts |
| **Client detail layer** (built only near the camera, deterministic placements shared with tests) | client cap | the server budget no longer pays for clutter; far away the phone holds nothing | clutter, ground vehicles, cars, staff, baggage trains, approach pier |
| **Client impostors** (CityLife impostor list, `CityLifeController.module.luau:1223-1289`) | 2-3 client parts each | a streamed-out landmark still shows (hotel penthouse, harbour) | PM wing, Meridian Tower |
| **Atomic streaming** (`Enum.ModelStreamingMode.Atomic`) | 0 | a phone never sees half a room or half a facade | every interior / shell model |
| **Mesh kit (optional)**: Blender FBX -> owner imports in Studio -> `ReplicatedStorage/Assets/Airport/<Name>`, part fallback when missing (pattern: `AircraftModel.module.luau:860-875`, `DriveController.module.luau:214-240`, `assets/vehicles/IMPORT_IN_ROBLOX.md`) | 1-3 MeshParts replace 10-60 parts | smoother shapes and fewer parts **on the device**; tests count the fallback, so it is never a budget source | seat modules, ground vehicles, roof shells, tower cabs |

**Not used, and why ([M] = API-Dump security):**
* `Model.LevelOfDetail` / StreamingMesh impostors: **PluginSecurity** (read and write). The airports are built by scripts at
  run time, and `pack.py` can only set properties of items that are in the place file. Not usable.
* Creating MeshParts from ids in code: `MeshPart.MeshId` write is **NotAccessibleSecurity**, so only cloning imported templates
  works (the existing pattern). `MeshPart.RenderFidelity` write is PluginSecurity, so it is set on the template in Studio.
* `AssetService:CreateEditableMesh` / `CreateMeshPartAsync` exist (API-Dump), but meshes made at run time would be client-only
  with their own memory budget, untested in this project, and **unsure** for publishing rules. Not needed.
* Unions / CSG (`UnionOperation`, run-time union calls): slow, costly triangles and collision. Every shape is a block, wedge,
  cylinder, ball or SpecialMesh primitive, or an imported MeshPart. "Union-free" is a test rule (`PartOperation` count = 0).
* Decals, Textures, SurfaceAppearance, image ids: the project bans invented asset ids (GRANDHOTEL §0.4). Not used.
* `Highlight`, Beams without a texture id (look unverified): not used.

---------------------------------------------------------------------------------------------------------------------

## 4. City Airport "Sky Wave" (main island)

### 4.1 Plan view (world studs; picture `concept_budget_work/plan_city_budget.png`)

```
 z 2380  Airport Road ──────────────────────────────────────────────────────────────────────────────────────────────
 z 2392  ╔═ C1 SKY WAVE LIP: roof edge moves 2398 -> 2392 and rises G+27.5 -> G+44, neon leading edge, x -312..312 ═╗
 z 2400..2418  drop-off lane (unchanged; driver stops 66 / 300)          car park x -820..-340 (cars -> client)
 z 2420  C2 tree columns at x -225 / -75 / 75 / 225 (the same 4 spots as today's CanopyColumns)
 z 2430  C3 front facade: deep fins every 24 (was mullions every 12); the fins' outer faces glow at night (tags; glass untagged)
 z 2430..2530  TERMINAL x -300..300 (unchanged footprint): C6 check-in island canopies, C5 gate A1, C7 spotter corner
               x 230..298 z 2508..2528; roof crown ribbon (neon) + roof graphic seen from the plane
 z 2530..2575  A1 JET BRIDGE becomes walkable: boarding point at the cab (-204, G+12, 2566)
 z 2530..2840  APRON: A1 (-200,2612) low LOD (hidden locally), A2/A3 full (unchanged), R1 (470,2640) medium,
               C13 R3 (-470,2640) medium (new, nose north); GSE except stand A1 -> client
               HANGAR x -1000..-840 z 2560..2720: C11 "AI EMPIRE JET CENTRE" re-skin, PrivateJet -> bizjet medium
               C9 TOWER (820, 2620): 8 -> <= 40 parts, Persistent, top stays G+105.6
 z 2690..2790  C10 CARGO VILLAGE x 720..1100 (sheds x 725..845 and 1005..1095, freighter 320 low at (925, 2730));
               stays outside the R2 ambient taxi sweep (wingtips x <= 632 on the north-south leg, z >= 2803 on the
               taxiway leg) and the fuel tanks at x 968..992, z 2588..2612 / 2648..2672
 z 2840..2880  taxiway; z 2940..3060 runway (unchanged)
```

### 4.2 Reclaim (server parts) [M counts, D decisions]

| # | change | parts | why it is invisible or better |
|---|---|---|---|
| R-A1 | A1 `ParkedAircraft` lod "low" | 330 -> 30 (**-300**) | hidden locally by every client today (`ShuttleController:145-170`); door and nose gear stay (`probe_doors_out.txt`); clearance already excludes it |
| R-R1 | `RemoteAircraft` lod "medium" | 330 -> 76 (**-254**) | ~205 studs from the nearest indoor spot; the medium LOD keeps the full silhouette |
| R-PJ | Hangar `PrivateJet` -> `kind = "bizjet"`, lod "medium", name kept | 330 -> 76 (**-254**) | fixes W8 (shrunken airliner); JetController still finds it by name (`JetController:420-424`) |
| R-CL | interior clutter -> client (`AirportDetailCity`) | **-715** | all non-collidable; drawn by the client when the camera is in the terminal |
| R-GSE | ground vehicles except stand A1's set and its `Pushback` (`ShuttleGround` needs it) -> client | **-337** | the client also animates 2 baggage trains on the existing equipment roads |
| R-CAR | car-park cars -> client | **-116** | built within 300 studs of the camera |
| | **total** | **-1,976** | |

### 4.3 New and changed server elements [D estimates]

| # | element | parts | wow |
|---|---|---|---|
| C1 | **Sky Wave lip**: roof profile `RZ = {2392, 2430, 2462, 2500, 2530, 2548}`, `RY = {G+44, G+34, G+40, G+40, G+35, G+31.5}` (today `{2398,...}` / `{G+27.5, G+35,...}`, `AirportBuilder:320-321`); same segment count; + neon leading edge (2) + 3 soffit light lines | +5 | from Airport Road the flat glass box turns into a wave lifting 20 studs above the kerb, glowing at night |
| C2 | 4 tree columns (trunk + 4 branches) replace 4 CanopyColumns + 8 struts at the same x | +8 | structure you can read; the drivers' clearance positions stay |
| C3 | front facade: deep fins (3 studs) every 24 replace mullions every 12 | -23 | shadow lines instead of a flat sheet |
| C4 | roof crown ribbon (neon, 2) + roof graphic (3) + `MetroNightGlow` on the opaque facade fins, roof edges and skylight frames (glass panes stay untagged) | +5 | seen on every take-off and landing |
| C5 | gate A1: bridge ceiling light strips, "Have a nice flight" cab sign, 2 boarding e-gates, big FlightInfoBoard | +60 | the gate becomes a place |
| C6 | check-in islands: overhead light canopies, information desk rework | +200 | the hall's best room (audit render 2) gets a ceiling |
| C7 | plane-spotting corner (airside east): 4 client-prompt scopes, step seating | +30 | kids watch R2 visits and take-offs |
| C8 | kid-safe: lounge and restaurant `BOTTLES` shelves (`AirportBuilder:966, 1198`) -> teapots / juice; duty-free perfume (`:1115, 1126`, labelled fragrance) stays | 0 | W10 |
| C9 | **control tower** (Persistent): tapered shaft, flared glass cab with a neon band, gold crown ring, radar + beacon PropFx; top kept at G+105.6 (`AirportBuilder:1897-1916`) | 8 -> <= 40 (+32) | the airport's landmark from downtown and from the air |
| C10 | **cargo village**: 2 sheds with sawtooth roofs, docks, 16 containers, apron slab, fence; 320 freighter (low LOD, 30) | +130 | fills the empty east grass (W8) seen on every arrival |
| C11 | **Jet Centre**: barrel-vault roof over the hangar walls (G+46..60), glazing strip, "AI EMPIRE JET CENTRE" sign; the door opening and bizjet paths stay | +40 | business aviation looks like business |
| C12 | forecourt: lit lane arrows and kerb edge | +20 | |
| C13 | **R3** remote stand (-470, apronTop, 2640) nose north, 320 medium | +76 | the west apron stops looking empty (W8) |
| | **total** | **+583** | |

**City result** (server): 6,559 - 1,976 + 583 = **5,166 parts** (zone by part centre 5,157 of **7,000**); interior 3,145 - 715 + 290
= **2,720 / 3,500**; exterior 1,764 - 453 + 187 = **1,498 / 2,000**; aircraft 1,650 -> 948. **Unspent zone reserve 1,843**
(owner decision O4: keep it for a later package, for example real second-destination gates).

### 4.4 What changes for the player (City)

* Arrival by car: a white wave rises over the kerb, with gold neon underneath at night, tree columns and glowing facade fins.
* Check-in hall: light canopies over the islands; staff at the 21 existing `AirportPost` markers (checkin 4, info 1,
  security 3, lounge 1, crew 1, shop 8, gate 3; counted in the dump), drawn by the client; suitcases and trolleys as today
  (now client-side).
* **Walk to the plane**: through gate A1 and down the jet bridge to the cab, "Board" at the plane's door (sections 10, 12 AP3).
* Through the glass: R2 visits as today, baggage trains crossing the apron, R3 and R1 parked, the cargo village beyond.
* Night: roof ribbon, glowing fins, neon lip, beacon blink and radar spin on the tower.

---------------------------------------------------------------------------------------------------------------------

## 5. Port Meridian "Meridian Wing" (abroad)

### 5.1 Plan view (world studs; pictures `plan_pm_budget.png`, `plan_pm_approach.png`)

```
 x:   -1800 ............ -704 | -700 ....... -214  -195..-179  -176 ..................... 176   204 .... 548  568..688
 z 7394..7694  CLIENT SEA CORRIDOR + approach-light pier (x -720..-1200 on z 7544)     (plan_pm_approach.png)
 z 7500..7520  north shoulder asphalt (new, visual) ─ runway paint centred on PM_LINE z 7544 ─────────────────────────
 z 7520..7590  RUNWAY (data rect unchanged: x -650..650)        shuttle wingtip line z 7600.8 (keep raised parts >= 7606)
 z 7606        WING north eave G+30 ───────────────────────────────┐
 z 7610..7690  west towers aw_1..aw_5 (unchanged)   TOWER   │ LOUNGE │ SKY DECK x -96..150, z 7612..7634, G+12.5 │ APRON
               x -694..-214                        (-187,  │-158.5..│ check-in │ GLOBE  │ security │ gate PM1     │ PM1 (252)
                                                    7676)  │ -104   │ -104..-36│-36..36 │ 36..96   │ 96..158      │ PM2 (480)
                                                    G+120  │        │ shops / Harbour Kitchen z 7668..7688│bag claim│ full LOD
 z 7655..7667                                                                         ApronDoor x 160 ═► TARMAC WALK
 z 7690        south facade, doors x -80 / 0 / 80                                      (162,7661)->(204,7688) -> stairs
 z 7690..7726  PLAZA CANOPY = the wing's cantilever, lip G+52 at z 7726; tree columns (+-40, +-120, 7716)
 z 7690..7768  arrival plaza, taxi rank x -200..-104, VIP limo lay-by x 104..200 (unchanged)      HELIPORT (604,7670)
 z 7768..7800  Arrivals Drive (unchanged) -> Meridian Boulevard south to the Meridian Grand (z 8360+, not touched)
```

Kept as data (no change): `CityPlan.ABROAD.runway / terminal / plaza / checkin / arrival` (`CityPlan.module.luau:531-543`),
`MetroPlan.APRON / LOUNGE / HELIPADS / VIP_LIMO / TAXI_RANK` (`MetroPlan.module.luau:132-158`), `FP.PM_LINE = PRZ - 11 = 7544`
(`FlightPlan.module.luau:215`). So the shuttle, jet and heli tracks and all timings stay identical.

### 5.2 Elements [D estimates; caps in 7.2]

| # | element | parts | wow / notes |
|---|---|---|---|
| P1 | **Wing roof** x -176..176, profile (z, y) = (7606, G+30) (7630, G+34) (7660, G+40) (7690, G+45) (7712, G+49) (7726, G+52): 5 segments x (soffit + skin), end fascias, gold neon leading edge on the lip, 3 soffit light lines over the plaza, a gold "meridian line" on the roof along x = 0 continuing the plaza's gold inlay (`MetroBuilder:470`) | 75 | the terminating view of Meridian Boulevard, seen from the plaza, the limo, the heli and (as an impostor) from the Grand's penthouse |
| P2 | 8 tree columns: hall (+-30, +-100; 7666), plaza edge (+-40, +-120; 7716) | 32 | |
| P3 | glazing: north (runway) full height to the roof, 6 panes + 7 fins; south 3 portals + panes; east wall keeps the **ApronDoor** opening (x 160, z 7655..7667, 11.5 high); west wall | 50 | |
| P4 | **Sky Deck** structure: slab, edge fascia, glass balustrade (SmoothPlastic + Transparency, not Glass, GRANDHOTEL §5.3), 2 stairs (x -100..-88 and 100..112, z 7634..7652), lift box, slim columns | 36 | |
| P5 | Sky Deck fit-out: **Meridian Squeeze juice bar**, 4 sofa groups with Seats, **4 spotter scopes** (client prompt "Look" zooms the camera toward the runway and shows "Next arrival PM 101 in m:ss" from the `ReplicatedStorage.Shuttle` attributes), flight board, planters | 160 | the only place in the game where an airliner rolls past 60-90 studs away at cockpit height (the deck floor is at G+12.5; the shuttle runs on z 7544) |
| P6 | ground floor (`TerminalInterior`, Atomic): check-in (the 2 "Fly home" counters at the data points + 6 kiosks + light ring), **Meridian Globe** atrium at the arrival point (globe + rings + basin + bench ring), the hanging **"Meridian Flyer"** (an `AircraftModel` low-LOD model, 30 parts, on cables), 2 security lanes, **gate PM1** lounge (8 seat rows in the finer furniture kit, desk, e-gates, boards), baggage claim, Café Aurora, **Harbour Kitchen** (2 counters + shared tables), 3 shops (Meridian Market, Sky Toys, Port News; goods drawn by the client), **Junior Pilot** cockpit play corner, landside seating, wayfinding, planters, restrooms, 10 `AirportPost` markers, GPS kiosk | ~1,050 | denser and finer than the City hall per square stud (section 6) |
| P7 | **Meridian Lounge** (kid-safe rebuild in the same rect): "THE MERIDIAN BAR" + `Bottles` (`MetroBuilder:366-370`) become a juice & smoothie bar; keep >= 8 Seats (`test_build.luau:57-61`), concierge post, work pods, buffet, family corner | ~240 | W10 |
| P8 | **tarmac walk**: canopy from the ApronDoor (162, 7661) to (204, 7688), ending ~4 studs short of the client airstair foot (210.7, G, 7684.7, derived from `ShuttleController:173-200` + the door at (210.74, 37.88, 7670.24)); neon edge, glass windbreak, 8 flush floor lamps | 30 | you walk outside along the jet's nose and up the stairs |
| P9 | **Meridian Tower** (control tower) at (-187, 7676), footprint 16 x 16 in the gap between tower aw_5 (x <= -214) and the hall (x >= -160): tapered shaft, glass cab ring, 4 gold blades echoing the Spire, radar spin + beacon blink (PropFx), top **G+120** (taller than City's G+105.6). 121 studs from the runway centreline, 67 from the wingtip line | 40 | |
| P10 | apron: existing markings / fence / walkway kept; GSE -> client (-20); **no masts** (they would stand in the shuttle's turn sweep near x 340, where its wingtip reaches z 7721); instead the apron fence rails get `MetroNightGlow` tags (0 parts), plus flush stand lead-in lights, a neon PM1 stop board and 2 glowing stand-number totems at the existing sign posts | ~60 | |
| P11 | **PM2** `ParkedAircraft` stays **full LOD** under `Airfield` with `Stand = "PM2"` (JetController searches there, `JetController:426-432`); only its ground vehicles move to the client (counted in P10) | 330 | the heliport fence (x 568) is ~25 studs from its tail (x ~542), so it is seen close up: no LOD cut here |
| P12 | runway visuals: north shoulder asphalt z 7500..7520, **centreline painted at z 7544** (the plane rolls on a centred 90-wide strip; data rect and `PM_LINE` unchanged; fixes the look of the 11-stud hack, W7); "09"/"27" designators; flush touchdown-zone and threshold lights (<= 0.4 high = markings for the clearance sweep) | ~64 | |
| P13 | heliport (pad, fence, rotor area unchanged) + VIP terminal glow and canopy | ~50 | |
| P14 | arrival plaza (layout unchanged) + 2 glowing welcome totems | ~140 | |
| | **airport scope estimate** | **~2,357** | |

Client side (AP2 data + AP4 code; budgets in 7.3): the sea corridor (`FAR_CLEAR` rect + one water strip), the approach-light pier with a
**rabbit** (sequential neon flash on 9 bars, client), 2 impostors (wing 3 parts, tower 2 parts), PM2 ground vehicles, staff
figures at the 10 posts, a **marshal** with two neon wands at (190, 7664) waving while the shuttle is in its PM taxi-in
phases, walkers inside the hall (MetroPlan interior walk graph joined to the existing terminal portals, `MetroPlan:1040`).

### 5.3 The PM moments, in order

1. **Approach** (every out leg; the camera follows the shuttle): low over a water corridor, approach lights rushing at you,
   touchdown on a centred runway. Today the plane flies *through* 5 shells on the way in and 3 on the way out (W2).
2. **Arrival**: you appear at (0, 28, 7655) under the wing's highest point, facing the Meridian Globe, the Flyer overhead
   and the boulevard through the south glass.
3. **Sky Deck**: juice bar, scopes, planes passing at cockpit height.
4. **Fly home**: check-in, security, gate PM1, out through the ApronDoor, along the lit canopy, up the stairs.
   The marshal waves the shuttle in.
5. **Night**: gold lip, glowing glazing fins and soffit lines (the warm hall reads through untagged glass), Meridian Tower cab band and beacon, approach rabbit, glowing apron fence, heliport edge lights.

---------------------------------------------------------------------------------------------------------------------

## 6. Why Port Meridian ends up better than the new City Airport

| criterion | City (new) | Port Meridian (new) |
|---|---|---|
| landmark silhouette | lip G+44, tower G+105.6 | wing G+52 + **Meridian Tower G+120** |
| the approach | sea from the east, existing approach bars | **water corridor + approach-light pier + rabbit**, and it fixes W2 |
| walk to the plane | inside a jet bridge | **outside on the tarmac**, airstairs, marshal |
| a room only this airport has | spotter corner (R2 stand ~360 studs, runway centreline ~480 studs away) | **Sky Deck**, planes at 60-90 studs and cockpit height |
| arrival moment | arrivals hall (unchanged) | under the wing's peak, globe, Flyer, boulevard view |
| interior density, server + client parts per sq stud | (2,720 + 715) / 60,000 = **0.057** | (1,050 + 160 + 240 + ~360) / 31,000 (hall + deck) = **0.058**, spent on the finer furniture kit |
| night look | ribbon, lip, glowing fins | gold lip, glazing fins + 3 plaza soffit lines, tower cab band, rabbit, apron fence glow, heliport |
| life | 30 walkers, staff at 21 posts, baggage trains | walkers newly inside, staff at 10 posts, marshal, GuestController passengers |
| kid features | scopes | scopes, juice bar, Junior Pilot corner, hanging Flyer, globe |
| kid-safety fixes | bottle shelves gone | "THE MERIDIAN BAR" gone; the board's fake "PM 104" gone (`MetroBuilder:299`) |
| raw server parts | 5,166 (runway 2,200 long, cargo, car park, hangar) | 2,357 in the airport scope |

Honest position: PM wins on every *experience* row and ties on density. It does **not** win on raw part count, because City
carries a 2,200-stud airfield. If the owner wants PM to win that row too (**owner decision O1**), the PM cap can rise to
3,500 safely: zone ~11,145 of 20,000, device load at the hall ~5,540 (4,395 + 1,143), still below City's gate today (5,718).

---------------------------------------------------------------------------------------------------------------------

## 7. Budgets (server, light, client, device)

### 7.1 City Airport (**no cap changes**)

| cap (test) | today [M] | concept [D] | cap |
|---|---|---|---|
| airport zone by part centre (`world_check.py:48`, `tests/world/test_build.luau:54`) | 6,550 | **5,157** | 7,000 (unchanged) |
| terminal interior (`test_airport.luau:102`) | 3,145 | 2,720 | 3,500 (unchanged) |
| exterior without aircraft (`:106`) | 1,764 | 1,498 | 2,000 (unchanged) |
| aircraft parts (not capped there) | 1,650 | 948 | new check: <= 1,000 |
| real lights in the airport zone | 40 (airport 35 + 5 street lamps) | 40 (airport **35**: the 2 car-park lamp lights move to the kerb canopy) | 40 (unchanged) |
| Persistent | ControlTower 8 + Horizon 46 | ControlTower <= 40 + Horizon 46 | new check: tower <= 40 |
| SurfaceGuis | 255 | <= 270; every new one sets `SurfaceGui.MaxDistance` | new check |
| translucent area (excluding sea) | 96,115 | <= 96,000 (front fins replace mullions; no new glass walls) | new check |
| unions | 0 | 0 | new check |

### 7.2 Port Meridian airport scope (**one change: scope split**)

| model (streaming) | today [M] | estimate [D] | **cap** |
|---|---|---|---|
| `ArrivalTerminal/Hall` (P1-P4 shell, Atomic) | 29 + 15 roof/canopy | ~193 | 230 |
| `ArrivalTerminal/TerminalInterior` (P6, Atomic) | 54 | ~1,050 | 1,150 |
| `ArrivalTerminal/SkyDeck` (P5, Atomic) | - | ~160 | 180 |
| `ArrivalTerminal/BusinessLounge` (P7, Atomic) | 90 | ~240 | 270 |
| `Airfield` without aircraft, incl. tarmac walk (P8, P10, P12) | 107 | ~154 | 190 |
| `Airfield/ParkedAircraft` PM2 (P11) | 330 | 330 (full LOD kept) | 335 |
| `Airfield/MeridianTower` (P9, Atomic) | - | 40 | 45 |
| `VipHelipad` (P13) | 34 | ~50 | 60 |
| `ArrivalPlaza` (P14) | 125 | ~140 | 165 |
| **airport scope** | **784** | **~2,357** | **2,650** (model caps sum 2,625) |
| metro test count (hotel frozen 78, airport frozen 784) | 5,253 | 5,257 (GRANDHOTEL's 4 sidewalk splits) | 5,281 (unchanged numbers) |
| abroad zone (`world_check.py:48`, `tests/world/test_build.luau:55`) | 5,139 | <= 8,429 (after the hotel) - 784 + 2,357 = **~10,002** (all caps full: 10,295) | 20,000 |
| world (`tests/world/test_build.luau:56`) | 14,810 (dump) | ~17,980 (after the hotel, GRANDHOTEL §19.1) - 1,393 + 1,573 = **~18,160** | 30,000 |
| PM real lights | 40 (airport 9) | 40 (airport **exactly 9**: hall 2, Sky Deck 1, lounge 2, heliport 1, plaza 3), same per-group distribution | 40 |
| Persistent abroad | Spire only | Spire only | test unchanged |
| GUIs / translucent area | 38 / 21,212 | <= 90 (MaxDistance on all) / <= 36,000 | new checks |
| `MetroNightGlow` parts | 198 (+ ~295 hotel) | + ~50 (glazing fins, tower cab band, apron fence rails; never a glass pane) | none glass or Transparency > 0.2 (CityLife turns them into Neon) |

### 7.3 Client budgets (new, asserted in the mock)

| client item | City cap | PM cap | rule |
|---|---|---|---|
| interior clutter (`AirportDetailCity/PM`) | 715 | 360 | only while the camera is in the terminal rect + 60 (pre-fill), y <= roof |
| ground vehicles + 2 baggage trains | 380 | 150 | per vehicle within 260 studs (City) / 220 (PM) |
| car-park cars | 116 | - | within 300 |
| staff figures (`CityLife.buildWalker`, 9 parts, `CityLifeController:259`) | 12 (108 parts) | 10 + marshal (99) | within 120 studs; idle sway at <= 10 Hz beyond 40 studs |
| approach pier + rabbit | - | 19 | only in the PM approach region or during the shuttle's approach phase |
| impostors (CityLife far model) | - | 5 | far + impostors total <= 700 (`test_life:144`): 574 - 23 + 2 + 5 + hotel 5 = **563** |
| client lights | <= 3 | <= 3 | `Shadows = false`, Range <= 24, only within 150 studs of the terminal; the hotel's <= 3 are never active at the same time (>= 592 studs apart, both controllers sleep) |
| **total client parts at once** | **<= 1,400** | **<= 700** | step <= 30 Hz, one `workspace:BulkMoveTo`, builds spread over frames (<= 120 parts per frame), asleep outside the airport zone (one region check per 0.5 s) |

### 7.4 Device load projection [D] (`project.py`, `project_out.txt`)

Method: the measured dump minus the exact reclaimed parts, the PM airport scope replaced by the element list (parts spread
on a grid over each element's box), the hotel added (+3,172 over its box), plus the active client caps and walkers.

| viewpoint | today parts <= 512 + walkers | concept: server <= 512 | + client | + walkers | **device total** | new test cap |
|---|---|---|---|---|---|---|
| City kerb | 5,533 | 4,378 | 1,041 | 0 | **5,419** | 6,500 |
| City check-in | 5,809 | 4,395 | 1,139 | 270 | **5,804** | 6,500 |
| City gate A1 | 5,718 | 4,401 | 1,269 | 270 | **5,940** | 6,500 |
| City Hangar 1 | 1,041 | 610 | 120 | 0 | 730 | 6,500 |
| PM arrival hall | 2,368 | 3,345 | 510 | 540 | **4,395** | 6,500 |
| PM Sky Deck | 2,290 | 3,263 | 510 | 540 | 4,313 | 6,500 |
| PM arrival plaza | 2,602 | 3,575 | 510 | 540 | **4,625** | 6,500 |
| PM heliport | 1,602 | 1,399 | 150 | 540 | 2,089 | 6,500 |
| PM boulevard midpoint (0, 8050): hotel and airport both within 512 | 3,247 | 7,432 | 0 | 540 | **7,972** | 8,500 |
| PM hotel door | 3,009 | 5,641 | 0 | 540 | 6,181 (hotel-driven) | - (GRANDHOTEL) |

Kerb: the downtown crowd (CityLife region `downtown` reaches z 2416, <= 44 walkers and 18 cars) comes on top in both columns.
Lights within 512 stay as measured (City 35-37, PM 19-22) plus at most 3 client lights. GUIs within 512: City <= 260, PM <= 160.
All of this is at most about 28 % of the tier-4 office (7,972 / 28,341 parts; 207 lights; 1,714 GUIs).

### 7.5 Mesh kit budgets (optional AP5)

| kit item | replaces (fallback) | MeshParts | tris cap |
|---|---|---|---|
| `SeatModule5` / `SeatModule3` (gate rows; 1 invisible collider per module keeps pads and seat spots) | ~2.1 parts per seat (249 seats: pads 249, armrests 215, legs, beams) | 1 visual + 1 collider per module | 1,500 each |
| GSE: Tug, BeltLoader, Catering, FuelTruck, Stairs, Bus, Cart (client) | 8-22 parts each | 1-3 | 3,000 each |
| `CityWaveLip`, `PMWingRoof` (server, CanCollide false; must lie inside the fallback envelope in `AirportsPlan`) | 5-75 parts | 1-3 | <= 20,000 per mesh (Roblox limit recorded in `assets/vehicles/*/manifest.json` `triangle_limit_per_mesh`) |
| `CityTowerCab`, `MeridianTowerCab` | ~10 parts | 1 | 4,000 |
| **kit total** | | | **<= 60,000 tris** (about one Skyliner380: 59,686, `assets/vehicles/skyliner380/manifest.json`) |
Tests run both variants: fallback (no templates) and mesh, using stand-in templates made from the manifests. Both must fit
every cap. Meshes are instanced per MeshId on the device [A].

---------------------------------------------------------------------------------------------------------------------

## 8. Budget changes needed, and why each is safe

| # | change | file | why safe (numbers) | safe? |
|---|---|---|---|---|
| B1 | PM airport scope (folders `Airfield`, `ArrivalTerminal`, `VipHelipad`, `ArrivalPlaza`) frozen at **784** in the metro count; new scope cap **2,650** | `tests/metro/test_build.luau` (after GRANDHOTEL A's hotel freeze), new `tests/pmairport/test_build.luau` | Same mechanism the hotel critic accepted (GRANDHOTEL §19.1 F9 / CC-11). The real limits still bind: zone ~10,002 of 20,000; device <= 6,500 at every airport viewpoint; the airport's real lights stay 9. The airport and hotel are >= 645 studs apart (plaza z 7730 to hotel door z 8375), beyond TargetRadius 512, so they co-stream only on the boulevard (7,972 projected) | **yes** |
| B2 | City caps | - | No change needed: zone 5,157 / 7,000, interior 2,720 / 3,500, exterior 1,498 / 2,000 | n/a |
| B3 | real lights | - | No cap change. City airport keeps 35 (2 car-park lamp lights move to the kerb), PM airport keeps 9 and is built at the same three build-order points (terminal + lounge before `towers()`, heliport, plaza after `spire()`: `MetroBuilder:1294-1300`), so no street lamp loses its light. Night drama comes from neon and tags | **yes** |
| B4 | City ControlTower 8 -> <= 40 parts, Persistent | `AirportBuilder` + a new check | +32 parts on every client in the game. CityBuilder already ships ~7 Persistent models (~300 parts, `CityBuilder:13-17`); a tier-4 office is 28,341 | **yes** |
| B5 | far skyline: corridor `FAR_CLEAR` rect x -1800..-700, z 7394..7694 | `MetroPlan.module.luau:374-382` | -23 shells; far total 574 -> 563 (cap 700); flight clearance to client shells goes from 0 to >= 123 studs (`probe_corridor_out.txt`) | **yes** |
| B6 | new device and client caps | new `tests/airports/test_device.luau`, `test_life.luau` | they only add limits | **yes** |
| B7 | *(owner option O1)* PM cap 2,650 -> 3,500 | `tests/pmairport/test_build.luau` | zone ~11,145 / 20,000; hall ~5,540, still <= City gate today (5,718) | yes, but not needed |

The one budget I would **not** raise: real lights per zone. No device measurement exists for the 40-light cap under Future
lighting [S]. The tier-4 office's 207 lights prove only that the game ships them, not that they are cheap on a phone.

---------------------------------------------------------------------------------------------------------------------

## 9. iPhone performance (landscape first)

* **Parts and streaming**: section 7.4. Every airport viewpoint is <= 6,000 parts including client parts and walkers; the
  worst PM point is 7,972 (boulevard, with the hotel). City gets *cheaper* everywhere except the gate (+222), because 1,976 server
  parts stop streaming at all distances.
* **Atomic units**: City `TerminalInterior` shrinks 2,988 -> ~2,690 (less to stream in at once); PM `TerminalInterior` <= 1,150,
  `Hall` <= 230, `SkyDeck` <= 180, `BusinessLounge` <= 270, `MeridianTower` <= 45 [stream-in hitch: S].
* **CPU (client)**: one new controller (`AirportLifeController`). It is asleep outside the two airport zones (one region check
  every 0.5 s, like CityLife, `CityLifeController:1510-1517`). Awake: <= 30 Hz, one `workspace:BulkMoveTo` for moving vehicles,
  trains and staff, staff beyond 40 studs at <= 10 Hz, builds spread over frames (<= 120 parts per frame). Mock perf gate: mean
  step <= 0.5 ms at full caps. Reference: CityLife's airport crowd measured 1.61 ms per step in the mock (audit, metro_life).
  Mock time is not iPhone time [S].
* **GPU proxies**: no new real lights; client lights <= 3 within 150 studs; decor `CastShadow = false` (existing test); no
  textures or decals; new transparency only on the PM glazing (<= 36,000 sq studs; the PM skyline already puts 340,000 sq studs
  within 512 of the hall, `translucent_out.txt`); Glass material only on facades (it hides transparent things behind it, which
  is fine there; GRANDHOTEL §5.3); GUIs carry `MaxDistance`.
* **Memory**: no new assets in the part-only version. The mesh kit is <= 60k tris, about one Skyliner380.
* **Graceful degrade**: `AirportsPlan.CLIENT_DETAIL = false` stops the client layer entirely. The airports stay fully working,
  just emptier. The mesh kit falls back to parts when templates are missing (existing pattern).
* **Only a device can say** [S]: FPS and memory on iPhone, the hitch when a 1,150-part Atomic unit streams in, pop-in of client
  clutter, neon glare under Future lighting, and SurfaceGui cost.

---------------------------------------------------------------------------------------------------------------------

## 10. Every existing flow: what stays, what changes, in which file

| flow | stays | change (file) |
|---|---|---|
| Shuttle at City (stand A1, bridge animation, hidden stand aircraft, taxi route, 368-s cycle) | stand CFrames, `taxiRoute`, `FP` tracks and timings | A1 model lod "low" (`AirportBuilder`); `ShuttleController` still finds `ParkedAircraft` with `Stand = 1` and hides it |
| Boarding at City | `FP.HOME_GATES[1]` (itinerary `IM.gatePoint`, `ItineraryMath:766-769`), desk prompt | **append** the bridge-cab point (-204, G+12, 2566) to `FP.HOME_GATES` (`FlightPlan:224`); `nearAny` is flat distance <= 36 with \|dy\| < 14 (`ShuttleService:90-93`), so no logic change; 1 extra `gatePrompt` call at the cab (`ShuttleService:802`); at "doors" a non-boarded player inside the bridge box is moved back to the gate (new, ShuttleService) |
| Shuttle at PM (PM1, airstairs, walkway, deboard, 30-s boarding) | stand, ApronDoor, `ShuttleStand` attributes, `FP.PM_GATES[1..4]` | **append** the stair-foot point (210.7, G+4, 7684.7) to `FP.PM_GATES` (`FlightPlan:228`); 1 `gatePrompt` there (`ShuttleService:803`) |
| Flight clearance | sweep method | re-run `tests/flight/run.sh` (all geometry near tracks moves); new client-geometry sweep `tests/flight/test_far_clearance.luau` (shells, sea, pier vs shuttle and jet tracks, >= 60 studs) |
| Company jet (Hangar 1, PM slots 1/2, separation windows) | `JP.HOME_PARK/HOME_STAND/PM_SLOTS` (`JetPlan:81-96`), names `PrivateJet` and `ParkedAircraft PM2` | PrivateJet kind/lod (`AirportBuilder`); PM2 (full LOD, new PM builder) under `Airfield` (JetController search, `JetController:426-432`); hangar door opening and the slot exit walks ((575,7622)->(558,7660); (452,7680)->(300,7705)) kept clear; `tests/guests_jet` re-run. `PM_STANDS_FULL` unchanged (optional AP6) |
| VIP heli ferry | pads (604, 25, 7670) and hotel (0, 151.2, 8408), `FP.heliPlan` | nothing; the wing lip (y <= 76 at z <= 7726) stays ~89 studs below the path (~y 165 over x 176) |
| Limo / driver places | `airport_departures` (66, RT, 2413.5), `airport_arrivals` (300, ...), `pm_airport` (-75, RT, 7772.6), `pm_limo` (176, ..., 7762) (`DrivePlan:341-411`) | tree columns at today's x; canopy >= G+40 over the plaza; `tests/drivers/clearance.sh` re-run |
| Itinerary | `IM.inAirport` / `inPMAirport` rect tests (`ItineraryMath:770-780`, used at `ItineraryService:854, 990, 1371, 1431`) | none: rects unchanged; Sky Deck players still pass `atGate` (\|dy\| = ~11.5 < 14) |
| Crowd | CityLife airport region and graph (`MetroPlan:1232-1236`), GuestPlan terminals (`GuestPlan:801-803`) | PM: interior walk graph + portals (`MetroPlan` pmPaths); new furniture must keep GuestPlan PM routes clear (2D check, rig radius 0.9) |
| Ambient traffic (R2) | slots, R2 stand, routes (`FlightPlan:716-760`) | cargo village and R3 outside the sweeps; clearance re-run |
| Boards | `FlightInfoBoard` tag, FlightPlan-only rows | PM board without "PM 104" |
| Economy, save, net | ticket $700 = `CompanyOps.TRIPS.abroad.flight`, heli fee, jet fuel; DATA_VERSION 6; no new remote | none. Scopes, marshal and staff are client-only; board prompts use the existing `CityAction = "board"` |

---------------------------------------------------------------------------------------------------------------------

## 11. No overlap with the Meridian Grand (GRANDHOTEL_SPEC)

* **Hotel areas (not touched):** hotel footprint x -70..70, z 8380..8500 and the lift tower east of it (x 70..95,
  z 8370..8510); drive and porch x -54..54, z 8360..8380; Harbour Street mouths x -54..-36 and 36..52.6, z 8352..8360; ACCESS
  (+-45, 8356); roof helipad (0, 151.2, 8408) with rotor circle r 16.4 and the x = 0 approach at roof + 60; HelipadExit
  (52, 152.7, 8442); `pm_hotel` DrivePlan place; hotel impostor; ~295 hotel glow tags (GRANDHOTEL §5.4, 5.5, 6.1, 11, 18).
* **Areas this concept uses:** the airport district only, x -700..700, z 7500..7768 (north of Arrivals Drive), plus client-only
  geometry west of the zone (x -1800..-704, z 7394..7694) and 2 impostor entries. The nearest new geometry to the hotel
  (plaza totems at z <= 7768) is **592 studs** from the hotel forecourt (z 8360).
* **Budget separation:** hotel = its own models, frozen at 78 in the metro count, cap 3,250, 3 real lights, <= 3 client lights.
  Airport = its own scope, frozen at 784, cap 2,650, 9 real lights, <= 3 client lights. The two light allocations sit at
  different build-order points and do not change each other.
* **Shared files, sequential edits:** `MetroPlan` (hotel: gaps, ACCESS, mouth paths; airport: FAR_CLEAR, FAR_GROUND split,
  interior paths), `MetroBuilder` (hotel: `towers()`; airport: the airport / lounge / heliport / plaza call sites),
  `CityLifeController` (hotel: impostor + `setLit`; airport: 2 impostors + sea strip), `ShuttleService` (hotel B: heli roof;
  airport: 2 prompts + bridge clear-out), `tests/metro/test_build.luau` (hotel freeze, then airport freeze). The airport
  packages start only after GRANDHOTEL A and B and their joint verify.

---------------------------------------------------------------------------------------------------------------------

## 12. Packages, order, file ownership (all after GRANDHOTEL A + B)

```
GRANDHOTEL A + B + joint verify  ->  AP0 prewire  ->  AP1 city ‖ AP2 pm ‖ AP3 flight hooks  ->  AP4 airport life  ->  AP-V verify
                                                                                                       └-> AP5 mesh kit (optional)  ->  AP6 jet slot 3 (optional)
```

| package | owns (no file in two parallel packages) | content |
|---|---|---|
| **AP0 airports_prewire** (integrate role) | new `ReplicatedStorage/Shared/Config/AirportsPlan.module.luau` (v1 verbatim from Appendix A); stubs: `ServerScriptService/Server/Services/PortMeridianAirportBuilder.module.luau`, `ReplicatedStorage/Shared/AirportDetailCity.module.luau`, `ReplicatedStorage/Shared/AirportDetailPM.module.luau`, `StarterPlayer/StarterPlayerScripts/Client/Controllers/AirportLifeController.module.luau`; `Main.client` require + init; run_all lines; `tests/airports/run.sh`, `tests/pmairport/run.sh` skeletons | frozen data contract (positions, profiles, caps, radii, kill switch) |
| **AP1 city_airport** | `AirportBuilder.module.luau`, `AirportDetailCity.module.luau`, `tests/airport/test_airport.luau` (expectation updates only), new `tests/airports/test_city.luau` | R-A1 ... R-CAR, C1-C13; clutter / GSE / car placements move from AirportBuilder into the pure `AirportDetailCity` (the same positions, one source for the client and the tests) |
| **AP2 pm_airport** | `PortMeridianAirportBuilder.module.luau`, `MetroBuilder.module.luau` (the airport / lounge / vipAirport / plaza bodies are replaced by 3 calls at the same build-order points), `MetroPlan.module.luau` (FAR_CLEAR corridor, FAR_GROUND split + `Plan.FAR_SEA`, interior walk graph + portals), `AirportDetailPM.module.luau`, `tests/metro/test_build.luau`, `tests/metro/test_life.luau` (impostor count +2, far total), `tests/metro/test_plan.luau` (far shells), new `tests/pmairport/*` | P1-P14, scope split B1, kid-safe lounge, board fix, every marker and name of AUDIT §4.6 kept |
| **AP3 flight_hooks** | `FlightPlan.module.luau` (append 2 gate points from AirportsPlan; nothing else), `ShuttleService.module.luau` (2 `gatePrompt` calls, bridge clear-out), `tests/flight/*` (expectations + new `test_far_clearance.luau`) | boarding at the cab / stair foot; client-geometry clearance gate |
| **AP4 airport_life** | `AirportLifeController.module.luau`, `CityLifeController.module.luau` (additive only: 2 PM airport impostors, sea strip from `Plan.FAR_SEA`), new `tests/airports/test_life.luau`, `tests/airports/test_device.luau` | client clutter / GSE / trains / cars / staff / marshal / scopes / pier + rabbit / <= 3 client lights / night refresh via `CityLife.setNight` (exported, `CityLifeController:1070`) |
| **AP5 mesh_kit** (optional; after AP1 + AP2 + AP4 land, hand-off declared) | new `assets/airport/*` (bpy `model.py`, FBX / OBJ, manifest, `IMPORT_AIRPORT.md`), mesh hooks in `AirportBuilder`, `PortMeridianAirportBuilder`, `AirportDetailCity/PM`, new `tests/airports/test_mesh.luau` | the owner imports once in Studio; fallback stays |
| **AP6 pm_jet_slot3** (optional, owner decision O3) | `JetPlan.module.luau`, `JetService.module.luau`, `tests/guests_jet/*` | third PM slot (site to be chosen: the VIP apron extension east of slot 1, or a west ramp replacing tower lot aw_5) |
| **AP-V** | read-only + reports | world dump, `world_check`, all suites, flight + drivers clearance, renders (blenderprev shots of kerb, wing, Sky Deck, tarmac walk, aerials), independent review -> fix round |

---------------------------------------------------------------------------------------------------------------------

## 13. Tests and acceptance (mock unless marked; every suite prints "<name>: N passed, M failed")

* **AP1** `test_city`: zone <= 7,000; interior <= 3,500; exterior <= 2,000; aircraft <= 1,000; airport real lights == 35 and
  zone == 40; ControlTower Persistent <= 40 parts, top <= G+105.6; no `BOTTLES` on the lounge / restaurant shelves; tree-column
  x == today's; cargo village and R3 outside the R2 / shuttle sweep boxes and the fuel tanks; translucent <= 96,000; GUIs <= 270,
  all new ones with MaxDistance; unions 0. Plus `tests/airport` 95 checks and walk-grid reachable cells >= 44,163.
* **AP2** `tests/metro/test_build` green with both freezes; `pmairport/test_build`: per-model caps (7.2), scope <= 2,650; PM
  lights == 40 with the airport exactly 9 and the per-group distribution identical; listed models Atomic, nothing Persistent;
  marker contract (ShuttleStand PM1 + Door, ApronDoor opening free, ParkedAircraft PM2 under Airfield, two Helipads + exit,
  VipLimoStand, LoungeConciergePost, BusinessLounge >= 8 Seats, 2 "Fly home" CheckinCounters at the data points, GPS kiosk);
  no text "PM 104", no part named `Bottles`, no "BAR" sign; no part with its top more than 1.0 above ground within 60
  studs of z 7544 for x -650..650 (today's edge-light heads are 0.9), everything taller north of the hall at z >= 7606; tower >= 75 from the runway centreline; walk graph reaches
  gate, deck and lounge; GuestPlan PM routes clear of collidable footprints (rig radius 0.9).
* **AP3**: `tests/flight/run.sh` green (incl. `flight_clearance` with the new geometry); `test_far_clearance`: shuttle out / back
  and jet out / back >= 60 studs from every client shell, sea and pier part, pier top <= G+2 under the flare (x > -1000);
  `HOME_GATES[1]` / `PM_GATES[1]` unchanged; boarding from the cab / stair foot accepted, from 40 studs off rejected; the
  bridge clear-out moves a non-boarded player at "doors".
* **AP4** `test_life`: caps (7.3); asleep outside the zones (no step connection); deterministic placements (two runs
  identical); clutter positions == `AirportDetailCity` == the old server positions; <= 3 client lights; mean step <= 0.5 ms at
  caps; scopes, marshal and staff create no remote and write no server instance. `test_device`: section 7.4 caps from a fresh
  dump plus client caps. `tests/metro/test_life` far total <= 700.
* **AP5** `test_mesh`: both variants within every cap; manifest tris per mesh <= the limits in 7.5; hero meshes inside the
  `AirportsPlan` envelopes.
* **AP-V** [S] Studio and phone list: section 15.

---------------------------------------------------------------------------------------------------------------------

## 14. Risks (biggest first) and cut list

1. **Unmeasured device cost and the new client layer** (summary, section 0). Mitigation: frame-sliced builds, pre-fill
   margin, kill switch, all caps asserted in the mock. Residual risk [S].
2. **Clearance margins**: the PM north eave sits 5.2 studs (in plan) from the wingtip line; the tarmac canopy is near PM1's
   nose; City's R3 and freighter are near taxi sweeps. Mitigation: the real-hull sweep decides. Fallbacks: eave at z 7610,
   canopy ending at the door, freighter at z 2715 or dropped, R3 at low LOD further west.
3. **Shared files with the hotel and round 2b** (MetroPlan, MetroBuilder, CityLifeController, ShuttleService, metro tests).
   Start only after GRANDHOTEL A + B, re-run their suites; edits are additive and in separate functions.
4. **Water z-fighting**: the client sea strip overlaps the City Horizon's Persistent OpenSea for x -1150..-704, z 7394..7500
   (`AirportBuilder:1985-1987`, sea z 5800..7500). Put the strip 0.05 lower (G-3.25..-3.05) or clip it to z >= 7500 there.
5. **Kids on the PM tarmac**: the client plane has no physics for them; ticket holders within 36 studs are auto-boarded
   (`ShuttleService:587`); others can stand on the apron (also possible today). The canopy guides the path; [S] check.
6. **Fallback-only look** if the mesh kit is never imported: budgets are unaffected; only the smoothness of hero shapes differs.

**Cut list** (in order; each cut leaves every flow working): City C6 (-200) -> PM Harbour Kitchen (~-60) -> City R3 (-76) ->
freighter (-30) -> PM Junior Pilot (~-30) -> PM Sky Deck sofas (~-28) -> client baggage trains -> client staff at
shops -> the rabbit (static pier).

**Owner decisions:** O1 PM cap 2,650 (default) or 3,500. O2 import the mesh kit in Studio (manual, like the aircraft). O3 AP6
third PM jet slot. O4 keep City's 1,843-part reserve.

---------------------------------------------------------------------------------------------------------------------

## 15. Assumptions [A] and Studio / iPhone checks [S]

* [A] Device cost scales with the parts, lights and GUIs held within the streaming radius; the airports never co-stream with
  each other (4,555 studs apart, AUDIT §3.3).
* [A] Recolouring a `CityLife.buildWalker` figure into a uniform works by part name. Check the figure's part names in AP4.
* [A] MeshParts that share a MeshId share geometry memory on the device.
* [A] The 320 at scale 1.8 has a half span of 56.8 (`MetroPlan.module.luau:148` comment); the wingtip line is z 7600.8.
* [S] FPS / memory on iPhone at the 10 viewpoints; Atomic stream-in hitch; client clutter pop-in; neon glare and Glass look
  under Future lighting; walking the A1 bridge while it is client-animated; the Flyer's readability; scope camera comfort.

---------------------------------------------------------------------------------------------------------------------

## Appendix A. `AirportsPlan` v1 sketch (AP0 writes it; world studs, G = CityPlan.GROUND) [D]

```lua
AP.CLIENT_DETAIL = true                                  -- kill switch for the client layer (section 9)
AP.CITY = {
  lip = {RZ = {2392,2430,2462,2500,2530,2548}, RY = {44,34,40,40,35,31.5}},          -- + G
  treeColumns = {-225,-75,75,225}, treeColumnZ = 2420, finPitch = 24, finDepth = 3,
  bridgeBoard = Vector3.new(-204, 36, 2566),             -- appended to FP.HOME_GATES (G+12)
  bridgeBox = {x1=-212, x2=-196, z1=2530, z2=2576},      -- clear-out at "doors"
  tower = {pos = Vector3.new(820, 24, 2620), top = 129.6, maxParts = 40},
  cargo = {x1=720, x2=1100, z1=2690, z2=2790}, freighter = CFrame.lookAt(Vector3.new(925,24.25,2730), Vector3.new(925,24.25,2630)),
  r3 = CFrame.lookAt(Vector3.new(-470,24.25,2640), Vector3.new(-470,24.25,2540)),
  lods = {A1 = "low", R1 = "medium", PrivateJet = {kind = "bizjet", lod = "medium"}},
}
AP.PM = {
  wing = {x1=-176, x2=176, profile = {{7606,30},{7630,34},{7660,40},{7690,45},{7712,49},{7726,52}}},  -- y + G
  deck = {x1=-96, x2=150, z1=7612, z2=7634, top=12.5},
  tower = {x=-187, z=7676, half=8, top=120},
  tarmac = {from = Vector3.new(162,24,7661), to = Vector3.new(204,24,7688)},
  stairFoot = Vector3.new(210.7, 28, 7684.7),            -- appended to FP.PM_GATES (G+4)
  runwayVisual = {z1=7500, z2=7590, centre=7544},
  corridor = {x1=-1800, x2=-700, z1=7394, z2=7694},      -- MetroPlan FAR_CLEAR + FAR_SEA
  pier = {x1=-1200, x2=-720, step=60, z=7544, top=2},    -- bars <= G+2
  marshal = CFrame.lookAt(Vector3.new(190,24,7664), Vector3.new(230,24,7664)),
  lights = {hall=2, deck=1, lounge=2, heli=1, plaza=3},
}
AP.CAPS = {cityZone=7000, cityInterior=3500, cityExterior=2000, cityAircraft=1000, cityTower=40,
  pmScope=2650, pmHall=230, pmInterior=1150, pmDeck=180, pmLounge=270, pmAirfield=190, pmPM2=335, pmTower=45, pmHeli=60, pmPlaza=165,
  clientCity=1400, clientPM=700, clientLights=3, device=6500, deviceBoulevard=8500, partsPerFrame=120}
```

## Appendix B. Roblox APIs named (all in `tools/API-Dump.json`; `apicheck_out.txt`: 122 checked, 0 missing)

Used: `Model.ModelStreamingMode` (`Atomic`, `Default`, `Persistent`), `Model:ScaleTo`, `Model:PivotTo`, `Model:GetBoundingBox`,
`MeshPart` (cloned templates), `MeshPart.CollisionFidelity`, `Enum.CollisionFidelity.Box`, `MeshPart.DoubleSided`,
`WedgePart`, `CornerWedgePart`, `Part.Shape` (`Cylinder`, `Ball`, `Wedge`, `CornerWedge`), `SpecialMesh.MeshType`
(`Sphere`), `BasePart.CastShadow / CanCollide / CanQuery / CanTouch / LocalTransparencyModifier / Material / Transparency /
Reflectance`, `Enum.Material.Neon / Glass / SmoothPlastic / Concrete / Metal / DiamondPlate / Marble / Limestone`,
`Workspace:BulkMoveTo`, `Enum.BulkMoveMode.FireCFrameChanged`, `Player:RequestStreamAroundAsync`, `Workspace.CurrentCamera`,
`Camera.CFrame / FieldOfView`, `SurfaceGui.MaxDistance / PixelsPerStud / SizingMode / LightInfluence / Brightness / Face /
CanvasSize`, `BillboardGui.MaxDistance`, `PointLight / SpotLight / SurfaceLight` (`Range`, `Angle`, `Face`, `Brightness`,
`Shadows`, `Color`, `Enabled`), `Attachment`, `Lighting.ClockTime`, `CollectionService:AddTag / GetTagged /
GetInstanceAddedSignal / GetInstanceRemovedSignal`, `Instance:SetAttribute / GetAttribute / GetAttributeChangedSignal`,
`RunService.Heartbeat / RenderStepped`, `ProximityPrompt.MaxActivationDistance / RequiresLineOfSight / HoldDuration /
ObjectText / ActionText`, `Seat`, `TextLabel.TextScaled`, `Workspace:GetServerTimeNow`, `TweenService:Create`.

Flagged by the check and **not used from scripts**: `Model.LevelOfDetail` (PluginSecurity / PluginSecurity),
`MeshPart.MeshId` (write NotAccessibleSecurity), `MeshPart.RenderFidelity` (write PluginSecurity, NotReplicated: set on the
template in Studio), `Workspace.StreamingEnabled / StreamingMinRadius / StreamingTargetRadius / ModelStreamingBehavior /
StreamOutBehavior / StreamingIntegrityMode` (NotScriptable / PluginSecurity: `pack.py` sets them), `Lighting.Technology`
(RobloxScriptSecurity: `pack.py`). Named as not used: `AssetService:CreateEditableMesh`, `AssetService:CreateMeshPartAsync`,
`EditableMesh`, `UnionOperation` / `PartOperation`, `Decal`, `Texture`, `SurfaceAppearance`, `Highlight`, `Beam`,
`ParticleEmitter`, `UserGameSettings.SavedQualityLevel` (usually "Automatic" on phones, so not a reliable LOD signal).

## Appendix C. Files

* this concept: `design/airports/concept_budget.md`
* plans: `design/airports/concept_budget_work/plan_city_budget.png`, `plan_pm_budget.png`, `plan_pm_approach.png`
* scripts: `measure.py`, `names.py`, `project.py`, `plans.py`, `apicheck.py` + `apis.txt`; probes `sb/probes/probe_lod.luau`,
  `probe_doors.luau`, `probe_corridor.luau`, `probe_client.luau`
* outputs: `measure_out.txt`, `count_city_d2.txt`, `names_city.txt`, `probe_lod_out.txt`, `probe_doors_out.txt`,
  `probe_corridor_out.txt`, `probe_client_out.txt`, `probe_client_far.txt`, `project_out.txt`, `translucent_out.txt`,
  `apicheck_out.txt`, `far_shells.txt`; source snapshot `sb/src_snapshot/` (+ `.TIMESTAMP`, `.md5`)
