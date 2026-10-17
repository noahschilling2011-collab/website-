# Airport concept "HUB & SPECTACLE" (both airports)

Concept for the airport redesign (owner wish 32, `notes_integration.md:154`): City Airport becomes a real
international hub; Port Meridian becomes the most luxurious, cinematic airport in the game and connects in style to the
Meridian Grand. This is a design document only. Nothing under `work/`, `tests/`, `agents/stable/` or the existing design
files was edited. My own files are in `design/airports/spectacle/`.
Date 2026-10-17. Paths are relative to `scratchpad/`.

Labels: **[M]** measured (file:line or a command with its output), **[D]** design value set by this concept,
**[S]** only Studio or a real iPhone can confirm, **[A]** assumption.

---------------------------------------------------------------------------------------------------------------------

## 0. One page

| | City Airport, "the Hub" | Port Meridian, "Meridian Bay International" |
|---|---|---|
| Identity | One sweeping **Wing Roof** over the terminal and the kerb, with a raised **Hub Lantern** over the check-in hall; a 150-stud **Hub Tower** as the landmark; the double-deck airliner parked outside a new maintenance hangar | A **sea-front glass terminal** on a new bay: aircraft land over the water, the terminal has two levels with a gallery looking over the runway to the sea, a sail roof, a palm court and a gold meridian line running from the sea to the boulevard |
| Stands | A1-A3 (unchanged) + **Pier B** with contact stands **B1, B2** (with jet bridges) + R2 ambient stand (unchanged) + maintenance stand with the 380 | PM1 shuttle stand (unchanged) **with a glass jet bridge**, 2 remote stands W1/W2 with parked airliners, and a **4-slot private-jet ramp** (was 2) at the **Meridian Jet Centre** (FBO) |
| Life | Staff at check-in, security, gate and lounge, ground crew, a follow-me car, a bus to R2, a meet & greet group with a name sign for the arriving player, live departure boards | Marshaller who waves the shuttle in, staff, terminal crowd, a juice bar in the **Meridian Club**, a **Welcome Wall** with the player's company name, a short arrival camera shot down the **Palm Boulevard** to the Meridian Grand |
| Signature moment | Walk down the A1 jet bridge to the aircraft door (flag-gated) | Walk off through the glass bridge → the Sky Gallery over the bay → the Club → **rooftop-level heliport on the Sky Terrace** (41 s to the hotel roof), or the porte-cochère limousine down the Palm Boulevard to the Meridian Grand |
| New parts | ~1,970 (zone cap 7,000 → **9,000**) | ~3,450 in a new capped model `MeridianAirport` (cap **4,100**), and **-862** parts the metro count no longer has to carry |
| Real lights | 40/40, no change | the airport's 9 existing lights, reused; 40/40 |
| Fixes | W3 (closed gates), W6, W8, W10 (bottle shelf) | **W2 (planes through buildings): measured 0 shells hit after the change**, W1, W4, W6, W7, W9, W10, W11 (airport side), PM_STANDS_FULL at the 5th jet instead of the 3rd |

What is deliberately **not** changed: the City runway, taxiway, A1 stand and taxi routes, the Port Meridian runway,
`FP.PM_LINE`, stand PM1, the taxi line at x 340, the `ApronDoor`, the 368-s shuttle cycle, the ambient-traffic stand R2,
all prices, DATA_VERSION 6, the Net remotes. That is why the flight timetable does not move (section 6).

---------------------------------------------------------------------------------------------------------------------

## 1. Evidence and method

* **Inputs I read:** `design/airports/audit/AUDIT.md` (all of it), `design/GRANDHOTEL_SPEC.md` §0-1, §5.5, §6, §11, §18-21,
  `notes_integration.md` (log), and live source: `CityPlan`, `MetroPlan`, `MetroBuilder`, `AirportBuilder`, `FlightPlan`,
  `JetPlan`, `JetService`, `JetController`, `DrivePlan`, `ShuttleService`, `ItineraryMath`, `GuestPlan`, `GuestController`,
  `CityBuilder`, `CityLifeController`, `AirTrafficController`, `AircraftModel`, `tests/metro/test_build.luau`,
  `tests/world/test_build.luau`, `tests/airport/test_airport.luau`, `agents/world/world_check.py`.
* **Drift check against the audit snapshot** (run 10:42 UTC, `cmp` on 14 files): identical except `ShuttleService`
  (11 diff lines) and `ItineraryMath` (28 diff lines), both edited by the running round 2b. Every `ShuttleService` /
  `ItineraryMath` line I cite was read in the **live** tree. Other `file:line` refers to the live tree (identical to the snapshot).
* **My sandbox** (`design/airports/spectacle/sb/`): a copy of the audit harness and of `src_snapshot`, plus 3 variants
  (`work/src_bay` = my Meridian Bay data in MetroPlan + the new heli pad; `work/src_city`, `work/src_city2` = ambient-stand
  experiments). Nothing outside `design/airports/spectacle/` was written.

| Command (cwd `design/airports/spectacle/sb`) | Output (excerpt) |
|---|---|
| `tools/luau tests/metro/test_build.luau -a .gen_base` | `Port Meridian: 5253 parts (+4472 over the pre-metro city), real lights abroad 40` / `metro_build: 42 passed, 0 failed` |
| `tools/luau tests/airport/test_airport.luau -a .gen_base` | `airport parts: interior 3145, exterior 1764, parked aircraft 1650` / `airport: 95 passed, 0 failed` |
| `tools/luau tests/spectacle/probe_bay.luau -a .gen_base` | today: `shuttle out ... time with a hull point inside 3.25 s; shells pierced 4`, `shuttle back 2.50 s / 3`, `jet out 2.75 s / 5`, `jet back 2.50 s / 3`; `heli ... a->b 46.1 s ... track 1281.4` |
| `tools/luau tests/spectacle/probe_bay.luau -a .gen_bay` | concept: `far shells 171` (was 279); `shuttle out min hull-point distance to a far shell 69.4 ... 0.00 s; shells pierced 0`, `shuttle back 88.5 / 0`, `jet out 102.4 / 0`, `jet back 118.3 / 0`; `heli pad airport (-211,41.0,7651) -> hotel: a->b 41.2 s, b->a 41.1 s, track 936.3`; `heliTimes hotel: ride 0.0..41.2, free again 84.3`; `heli: lowest height above ground while over z 7690..8300: 92.6` |
| `tools/luau tests/spectacle/probe_env.luau -a .gen_base` | swept hull points: `shuttle out landing x -734.4..328.3 z 7487.4..7600.6`, `shuttle out taxiin x 192.6..397.0 z 7487.0..7720.6`, `shuttle back pushback x 192.6..397.2 z 7607.4..7734.3`, `jet slot 1 out (PM ground) x -693.9..653.4 z 7522.6..7632.8`, `jet slot 2 ... z ..7685.5`, `ambient departure (City ground) x -231.3..1006.9 z 2640.6..3056.6` |
| `tools/luau tests/spectacle/probe_ambient2.luau -a .gen_base / .gen_city / .gen_city2` | R2 today: `arrival 84.1 s departure 94.3 s slots 5, 171.3`; ambient stand moved to a Pier B bridge (560, 2612): `arrival 87.4 s departure 98.4 s slots 171` (**one slot lost**); same with doors hold 4 → 1 s: `departure 95.4 s slots 171` (still lost) |
| `python3 layout.py ../audit/sb/out/blenderprev/world/world_dump.json` (cwd `design/airports/spectacle`) | `layout checks: 250 ok, 0 bad` (every proposed rectangle vs measured envelopes, stand hull boxes, zones, the Meridian Grand site); plots `plan_pm_concept.png`, `plan_city_concept.png` |
| `python3 density.py ../audit/sb/out/blenderprev/world/world_dump.json` | parts within 512 studs (flat): City terminal centre (0,2480) **5,594**; PM hall centre (0,7650) **1,838**; PM plaza (0,7725) 2,077; hotel door (0,8375) **2,514** (same number as GRANDHOTEL §19.1, so the method matches) |
| `python3 apicheck.py ../../../tools/API-Dump.json apis.txt` | `checked 67, missing 0` (every Roblox API this concept names, section 15) |
| `python3` dump query: PM parts with centre z 7500..7760 | `Airfield 437, ArrivalTerminal 188, ArrivalPlaza 96, Greenery 78, VipHelipad 34, CityBlocks 30, Signage 18`; lots `Tower_aw_1..5` = **30** parts; boulevard median `Tree` 24 + `TreeCanopy` 24 = **48** parts |

Raw outputs: `design/airports/spectacle/{probe_bay_out.txt, probe_env_out.txt, probe_ambient_out.txt, layout_out.txt, density_out.txt}`.

---------------------------------------------------------------------------------------------------------------------

## 2. Rules this concept keeps (from the brief and the existing specs)

* **Economy unchanged.** Ticket $700 = `CityPlan.TRAVEL.ticket` (`CityPlan.module.luau:31`), heli `Shuttle.HELI_FEE = 2500` or the limo
  pass (`ShuttleService.module.luau:63`), jet costs in CompanyOps. The new lounge, Jet Centre, terrace and boards are free. No paid item,
  no random reward, nothing new is charged.
* **Nothing saved.** DATA_VERSION stays 6. Every new state is a session attribute or client-only.
* **Server-authoritative, no new remote.** Boarding, the heli and the jet keep their existing server checks; new server prompts are
  plain `ProximityPrompt`s with existing `CityAction` values (`board`, `heli`). Everything else (staff, crowd, bridge animation,
  welcome wall, camera shot, night glow) is client-only and deterministic from server time, seeds and replicated attributes.
* **Deterministic, seeded builds** (palm / staff variations by `MetroPlan.hash` / position hashes, never `Random` at build time).
* **Kid-friendly.** No alcohol: the Port Meridian bar sign and bottle shelf (`MetroBuilder.module.luau:368-370`) are removed with the old
  hall and replaced by a juice bar; the City lounge shelf (`AirportBuilder.module.luau:965`, `BOTTLES`) gets a tea & juice palette. No
  gambling, no brands, English signs, ASCII + `· É ► ◄ –` only.
* **Real lights** only through the budgeted `CityBuilder.light` (refuses the 41st per zone, `CityBuilder.module.luau:57-64`).
* **Streaming:** no new Persistent model in Port Meridian (only the Spire may be, `tests/metro/test_build.luau:137-145`); new interiors
  Atomic; place settings MinRadius 128 / TargetRadius 512 (`pack.py:128-133`, audit 3.3).

---------------------------------------------------------------------------------------------------------------------

## 3. Port Meridian: "Meridian Bay International"

### 3.1 The player journey (what makes it the best airport in the game)

1. **Approach over the bay.** The north edge of Port Meridian becomes the Meridian Bay (water). The shuttle descends over water along
   flush approach lights and lands on a runway that sits on a seawall, with the city skyline on its right. The
   planes-through-buildings bug (W2) is gone (3.3, measured).
2. **The marshaller.** A ground marshaller waves the shuttle onto PM1 (client figure, timed from the `taxiin` phase). The glass jet bridge
   swings onto the door, like A1 at home.
3. **Walk off** (flag `WALK_BRIDGE`, section 6). The passenger appears in the jet bridge cab and walks through the glass tunnel, with the bay
   on one side and the runway on the other, into the terminal.
4. **The atrium.** A 44-stud-high glass atrium with a palm court, the gold **Meridian Compass** in the floor where the arrival point already
   stands (`CityPlan.ABROAD.arrival` = (0, 28, 7655), `CityPlan.module.luau:537`) and the **Welcome Wall** on the Skybridge above:
   "WELCOME TO PORT MERIDIAN" plus the player's company name (client text).
5. **Up or out.**
   * **Up** the Grand Stairs to the **Sky Gallery** (L1, G+16.5): the **Meridian Club** VIP lounge (juice bar, sofas, kids' Pilot Corner,
     aquarium wall) and through its glass doors onto the **Sky Terrace** with the heliport: 41.2 s to the Meridian Grand roof [M], where
     the hotel's package A/B puts you on the roof (GRANDHOTEL §11, §18.3).
   * **Out** through the central doors onto the **Palm Plaza**: fountains, palms, the VIP limousine under a new porte-cochère, and the view
     straight down the Palm Boulevard (x = 0) to the Meridian Grand and the Spire. On the first arrival of a session a 5-s camera shot rises
     over the plaza and looks down the boulevard (skippable). The limousine ride to the porte-cochère of the Meridian Grand already exists
     (`pm_limo → pm_hotel` 40.5 s, GRANDHOTEL §6.3).
6. **Private jet owners** land, roll to the **Meridian Jet Centre** ramp, walk 20 studs through a red-carpet door into the FBO lounge, and
   find their chauffeur at the Jet Centre kerb.

### 3.2 Plan view (world studs, G = 24, +x east, +z south; plot: `design/airports/spectacle/plan_pm_concept.png`)

```
 z 7240..7500  MERIDIAN BAY - water (client FarSea + the existing persistent OpenSea), flush approach-light bars x -1300..-700 on z 7544
 z 7487        shuttle north wingtip on PM_LINE (measured 7487.0) - nothing above G+1 north of the runway
 z 7500..7504  SEAWALL (flush granite edge + quay neon, top <= G+0.4)                           [zone edge z 7500, unchanged]
 z 7520..7590  RUNWAY 09/27  x -650..650  (unchanged)   PM_LINE z 7544 (unchanged)   touchdown x -600   taxi line x 340 (unchanged)
 z 7590..7610  shoulder; jet slot S1 (600,7612)
 x:  -700  W1 (-560,7676)  W2 (-390,7676) | SKY TERRACE | BAY TERMINAL x -160..160, z 7610..7690   |bridge| PM1 (252,7664) | S2 (480,7664)
            parked 320      parked 320     | x -262..-160| L0 G+0.5 / L1 Sky Gallery G+16.5 (z 7610..   | PM1  | pushback       | S3 (600,7668)
            nose east       nose east      | heli pad    | 7650), atrium x -60..60, sail roof G+44    |      | envelope       | S4 (600,7724)
                                           | (-211,G+17, |                                            |      | x <= 397.2,    |
       Bay Tower (-660,7730)               |  7651)      |                                            |      | z <= 7734.4    | JET CENTRE x 410..515, z 7698..7756
 z 7690..7760                              PALM PLAZA x -200..200: fountains (+-40,7710), palms, porte-cochere x 104..200 z 7740..7768
 z 7760..7808  Arrivals Drive (unchanged): pm_airport kerb (-75,7772.6), pm_limo (176,7762), NEW pm_jetcentre kerb (470,7772.6)
 z 7801..8301  PALM BOULEVARD: the 24 median trees (x +-19.5) and 8 forecourt trees (x +-98) become palms - nothing new at z > 8310
```

| Element | Coordinates [D] | Note |
|---|---|---|
| Zone | x -700..700, z 7500..8700 (unchanged, `CityPlan.module.luau:45`) | the airport stays inside it; only client water lies outside |
| Runway / PM_LINE / PM1 / taxi line / ApronDoor | unchanged (`CityPlan.module.luau:533`, `FlightPlan.module.luau:215`, `MetroPlan.module.luau:151-158`) | keeps every shuttle and jet track |
| Bay Terminal | `CityPlan.ABROAD.terminal` unchanged rect x -160..160, z 7610..7690; height 26 → **32** (north eave), sail-roof crest G+44, eave overhang to z 7604 | north face stays 9.2 studs south of the measured wingtip envelope (7600.8), as today |
| L1 Sky Gallery | floor G+16.5 over x -160..160, z 7610..7650, minus the atrium void x -60..60, z 7626..7650; Skybridge x -60..60, z 7610..7626 | Grand Stairs inside the atrium x -60..-44 and x 44..60, foot z 7662 (L0), top z 7626 on the Skybridge (22 steps, rise 0.73, run 1.64) |
| Meridian Club (`BusinessLounge`) | L1, x -160..-60, z 7610..7650 | same model name, tag, `Purpose`, `Zone`; >= 8 Seats (test `tests/metro/test_build.luau:61` still holds: inside the terminal rect in x/z) |
| Sky Terrace + heliport | deck G+16 at x -262..-160, z 7614..7688; pad 44 x 44 centre (-211, G+17, 7651); rotor circle r 16.4 inside the pad | `MetroPlan.HELIPADS.airport.cf` (`MetroPlan.module.luau:134`) → `CFrame.new(-211, G+17, 7651)` |
| Jet bridge PM1 | from the ApronDoor (x 160, z 7655..7667, floor G+0.5) to a cab at the shuttle's DoorL1: x 210.7, z 7670.8+, sill G+11.1 | door from `AircraftModel` points (`AircraftModel.module.luau:188`: DoorL1 (-7.05, 15.4, -46.6) at real size; x 0.885 at scale 1.8 = (-6.24, 13.64, -41.26)); tunnel passes >= 4 studs south of the nose |
| Remote stands W1, W2 | pivots (-560, 7676) and (-390, 7676), 320 x1.8, nose east; W1 full LOD, W2 medium LOD | replace the 5 low "airport" lots (block "aw", `MetroPlan.module.luau:256`); north wingtip z 7619.4 = **~18.6** studs south of the measured runway envelope (7600.8) |
| VIP jet ramp | slots S1 (600, 7612) [today's slot 1], S2 (480, 7664) [today's slot 2, no parked airliner to hide], **S3 (600, 7668)**, **S4 (600, 7724)**, all nose west | lanes: S2 in x 520 / out x 450; S3+S4 in x 650 / out x 548 (section 3.6) |
| Meridian Jet Centre (FBO) | x 410..515, z 7698..7756, two levels (lounge G+0.5, Jet Deck terrace G+12); airside door (470, 7698), landside door (470, 7756) | 13 studs east of the PM1 pushback envelope, 10 studs west of S4's turn |
| Bay Tower | x -668..-652, z 7722..7738, cab G+84..96, beacon to G+104 | Default streaming (not Persistent) |
| Palm Plaza | today's plaza rect x -200..200, z 7690..7760 (`CityPlan.module.luau:538`); fountains r 7 at (±40, 7710); porte-cochère x 104..200, z 7740..7768, underside **G+14** | GRANDHOTEL requires <= 12.8 clearance for the mesh limo at its canopy; G+14 is higher |
| Palm Boulevard | palms at the 24 `MetroPlan.MEDIAN_TREES` points (`MetroPlan.module.luau:805-814`, z 7823..8301) + the 8 forecourt planter points (x ±98, `MetroBuilder.module.luau:774`) + the 4 plaza planters (x -130/-40/40/130, z 7742.5) | same points as the trees → walk-graph obstacles unchanged (`MetroPlan.module.luau:911` registers them) |

`layout.py` checks all of this: every proposed rectangle against the measured envelopes, the stand hull boxes (the bands of
`tests/metro/test_build.luau:111-125`), the zone and the Meridian Grand site → `layout checks: 250 ok, 0 bad` [M].
The only intended overlap: the bridge cab enters the PM1 fuselage band (gap -23.4) → test exception, exactly like A1's docked bridge at home (sections 6 and 11).

### 3.3 The Meridian Bay and the approach (fixes W2)

Today the client far skyline is built north (band "n", z 6900..7480) and west (band "w", x -1780..-740, z 7380..8660) of Port Meridian
(`MetroPlan.module.luau:409-411`), on far ground at G-2..G (`CityLifeController.module.luau:1188-1191`). The aircraft fly through band "w"
(audit W2; my hull-point probe: 2.5-3.25 s inside a shell per leg [M]).

Change (data in `MetroPlan` + client parts in `CityLifeController`) [D]:
* delete band "n" and the north far-ground rect (`MetroPlan.module.luau:411, 420`);
* band "w" and the west far-ground rect start at z **7660** instead of 7380 / 6880;
* new `MetroPlan.FAR_SEA` rects filled by the client with water at G-3.2..G-3 (same level as the home Horizon `OpenSea`,
  `AirportBuilder.module.luau:1979`): {x -1800..-1150, z 7240..7660} and {x -1150..-704, z 7500..7660}. North of z 7500 between x ±1150
  the **persistent** home `OpenSea` (x -1150..1150, z 5800..7500, `AirportBuilder.module.luau:1987`) already lies under the far ground and
  becomes visible by itself;
* flush approach lights on the water (neon bars at G-2.9, x -1300..-700 along z 7544 + 2 cross bars), client-only;
* the east far ground and band "e" stay (the bay is closed by a city shore in the east).

Measured with the patched copy (`probe_bay.luau -a .gen_bay`) [M]: shells 279 → 171; minimum hull-point distance to any shell 69.4
(shuttle out), 88.5 (back), 102.4 (jet out), 118.3 (jet back); 0 s inside; 0 shells pierced. The shuttle and jet tracks themselves are not
touched. To stop this from coming back, `tests/flight/clearance.py` also sweeps `MetroPlan.FAR` boxes (they are pure data).

### 3.4 Bay Terminal

**Architecture.** North facade: full-height glass (G+0.5..G+32) with slim bronze mullions every 16 and an opaque frit band G+28..32
(less transparent area, section 9); seven white **sail vaults** (one per 40 studs of facade) tilt up towards the sea, crest G+44, with
skylight slits between them (the existing 7-fin rhythm, `MetroBuilder.module.luau:280-283`, becomes the real roof). South facade: glass
with the three doors at x -80 / 0 / 80 unchanged (`CityPlan.module.luau:535`; the CityLife portals depend on them, `MetroPlan.module.luau:1040`),
each in a tall bronze portal frame; entrance canopy over the plaza. A gold **meridian line** runs along x = 0 from the plaza's
`MeridianLine` (`MetroBuilder.module.luau:470`) through the terminal to the north glass; the axis x -40..40 stays free from door to sea.

**L0 (floor G+0.5), Atomic `TerminalInterior`, cap 1,250 parts:**

| Zone | Place [D] | Content |
|---|---|---|
| Atrium | x -60..60 | Meridian Compass inlay (gold ring r 12 at (0, 7655), the arrival point), palm court (4 palms in granite planters at (±30, 7630), (±30, 7678)), benches, the two Grand Stairs |
| Check-in "Fly home" | west wing north, 4 desks at (-130 / -110 / -90 / -70, G, 7636) | today's points are (-70) and (70) (`CityPlan.module.luau:536`); `ABROAD.checkin` becomes {(-70), (-110), (-90), (-130)}: [1] unchanged, [2] moves from +70 to -110 so the east wing is free for the gate. `FP.PM_GATES` reads `checkin[1..2]` (`FlightPlan.module.luau:228`), so its 4th point moves with it; same `K.checkin` attributes; queue belts |
| Departures | west wing south, x -160..-60, z 7656..7690 | security arches (decor, like City), shops: Café Aurora (moved), Meridian Sweets & Gelato, **Toy Hangar** (model planes), News · Travel |
| Gate PM1 | east wing north, x 60..158, z 7612..7650 | gate desk + Board prompt (server, section 6), seat rows, docking board; `FP.PM_GATES[1]` = (148, 28, 7661) stays at the ApronDoor |
| Arrivals | east wing south, x 60..158, z 7656..7690 | 2 baggage carousels, **Welcome Desk** (concierge post), **VIP Chauffeur** desk at the east door (x 80, ~120 studs from the limo stand), the existing GPS kiosk to the Meridian Grand (30, 7676) |
| Boards | atrium + gate | `FlightInfoBoard` rows from FlightPlan only (PM 101 / PM 102, heli "ON REQUEST"); the invented "PM 104" (`MetroBuilder.module.luau:299`) disappears |

**L1 Sky Gallery (G+16.5), Atomic `SkyGallery` (cap 320) + Atomic `BusinessLounge` (cap 340):**
* **The Meridian Club** (x -160..-60): "MERIDIAN JUICE BAR" with fruit bowls and smoothie machines (no bottles), 4 sofa groups (real `Seat`s,
  >= 12), 3 work pods, buffet, concierge desk with `LoungeConciergePost` (kept name), an aquarium wall, the kids' **Pilot Corner** (two
  cockpit play seats with flight-screen panels), glass doors at x -160 onto the Sky Terrace.
* **Skybridge** (x -60..60, z 7610..7626) across the atrium: the Welcome Wall faces the atrium; 4 telescopes on the bay side (client "Look"
  prompts: camera zoom on the runway, exit button 44 pt).
* **Sky Deck** (x 60..160): plane-spotter seats over PM1 and the runway.

**Sky Terrace (`SkyTerrace`, cap 90).** Deck on 6 columns over a ground-level palm garden; glass balustrade G+16..19.5; the pad from
`MetroBuilder.helipad()` unchanged in shape (pad, ring, H, 8 edge lights, windsock; `MetroBuilder.module.luau:417-435`); heli attendant post;
sign "VIP HELICOPTER · MERIDIAN GRAND ROOF". The VIP helicopter terminal pavilion east of today's pad goes away (its job moves to the Club).

### 3.5 Airfield, remote stands, seawall, tower

* **Runway re-dress** (geometry unchanged): touchdown-zone bars, aiming points, centreline, 09 / 27, thresholds, neon edge lights every 100,
  localiser antenna at the east end (<= G+3), windsock. No real lights (none left, section 8.3).
* **Seawall** z 7500..7504, flush: the shuttle's north wingtip overhangs the zone edge to z 7487.0 [M], so nothing above G+1 there.
* **W1 / W2** (moved from today's PM2): two parked 320s on the old lot block "aw", airstairs, GSE. The landing shuttle passes 18 studs from
  W1's wingtip at touchdown (x -600) - the spectacle of landing past parked jets. `tests/metro/test_build.luau:105` (parked aircraft on
  stand 2) becomes "W1/W2 RemoteAircraft (Stand W1/W2), visible in the flight clearance sweep".
* **Bay Tower** at the west end: slim shaft, glass cab, beacon neon (PropFx blink like the City tower, `AirportBuilder.module.luau:1909`).

### 3.6 Meridian Jet Centre (FBO) and the 4-slot VIP ramp

Today Port Meridian has 2 jet slots: slot 1 "VIP apron" (600, 7612) and slot 2 = stand PM2, which hides the parked airliner
(`JetPlan.module.luau:87-96`); a third jet company gets `PM_STANDS_FULL` (`JetService.module.luau:444, 505`). `JetService.freeSlot`
already loops over `JP.PM_SLOTS` (`JetService.module.luau:277-280`) and the separation scheduler over `JP.FIELDS`
(`JetPlan.module.luau:510`), so more slots are data.

| Slot [D] | Pivot (nose west) | arrive (after the roll-out at x 470 on PM_LINE) | depart |
|---|---|---|---|
| 1 VIP 1 | (600, AY, 7612) | unchanged | unchanged |
| 2 VIP 2 | (480, AY, 7664) | unchanged; `hides = nil` | unchanged |
| 3 VIP 3 | (600, AY, 7668) | (470,PZ) → (650,PZ) → (650,7668) → (600,7668), R 26 | (600,7668) → (548,7668) → (548,PZ) → (500,PZ), rollFrom 500 |
| 4 VIP 4 | (600, AY, 7724) | (470,PZ) → (650,PZ) → (650,7724) → (600,7724) | (600,7724) → (548,7724) → (548,PZ) → (500,PZ) |

Clearances (bizjet x1.6 = 46 x 41.6, `AircraftModel.module.luau:30`; computed on the rectangles by `layout.py`): lane x 650 passes S1/S3 tails
by 6, the depart lane x 548 passes S1's nose by 8 and S2's tail by 24, all >= 20 from the PM1 envelope, S4's turn 10 from the Jet Centre.
A new JetPlan field **"vip"** (x 400..700, z 7590..7760) keeps two jets from moving on the ramp at the same time.
`JP.ARRIVAL.abroad` (`JetPlan.module.luau:101`) moves from the limousine stand to the Jet Centre lobby (470, G+3.3, 7735) facing the landside
door; the companions' `exit` paths lead to the airside door (470, 7698). `PM_STANDS_FULL` then appears for the **5th** jet company (S1-S4 +
nothing else). JetController's welcome toast ("The VIP limousine stand is right here", `JetController.module.luau:784`) gets the new text.

The **Jet Centre**: glass pavilion with bronze fins, concierge, 6 lounge Seats, juice bar, a "COMPANY JETS" board (client text from the jet
folders JetController already reads [A]), stairs to the Jet Deck roof terrace; red carpets and stanchions to S2; fuel truck, GPU, cones.
Landside: new kerb place **`pm_jetcentre`** on Arrivals Drive's westbound kerb at (470, RT, 7772.6), built like `pm_airport`
(`DrivePlan.module.luau:409-411`, no sidewalk gap needed); `Drive.PM_STAND_AREA` (`DrivePlan.module.luau:499`) gets the Jet Centre rect and
`nearestPickup` returns `pm_jetcentre` there.

### 3.7 Palm Plaza, Palm Boulevard and the connection to the Meridian Grand

* **Palm Plaza** (today's `ArrivalPlaza` is rebuilt inside the new model, with the same taxi rank, metro entrance and VIP lay-by): the
  existing navy canopy over the limousine lay-by (`MetroBuilder.module.luau:499-505`) becomes a glass **porte-cochère** (underside G+14,
  4 bronze columns on the plaza side only, `VipLimoStand` marker unchanged); two fountains between the doors; palms in the 4 planters;
  flags at z 7698 stay (`MetroPlan.module.luau:816`).
* **Palm Boulevard:** a palm (8 parts: 3 trunk segments, crown ball, 4 frond wedges; trunk collidable like the tree trunk today,
  `CityBuilder.module.luau:93-99`) at each of the 36 tree points. `MetroBuilder.boulevard()` skips its median and forecourt trees
  (`MetroBuilder.module.luau:723, 774`) when `AirportsPlan.PALMS` is on; the palms belong to the airport model and its cap.
* **The Meridian Axis:** from the central door (0, 7690) the boulevard runs straight to the hotel door (0, 8375) and the Spire (0, 8548).
  The Spire is Persistent (`test_build.luau:137-145`); the hotel shows as GRANDHOTEL's 6-part impostor from the plaza (GRANDHOTEL §5.5).
  Nothing new is built on x -24..24 south of the plaza.
* **Heli:** 41.2 s from the terrace to the hotel roof [M], always above G+92 while over the plaza and boulevard [M]; the hotel end and its
  approach "along x = 0 from the north at roof + 60" (GRANDHOTEL §11) are unchanged because `FP.heliPlan` always uses the x = 0 corridor
  (`FlightPlan.module.luau:629-640`).

### 3.8 Life at Port Meridian (client, `AirportLifeController`)

* Staff roster 14 (check-in 2, gate 1, welcome desk 1, chauffeur desk 1, Club concierge 1, juice bar 1, café 1, heli attendant 1, Jet
  Centre host 1, marshaller 1, ramp crew 2), **<= 8 drawn** (nearest first), posts = `AirportPost` markers (same convention as City,
  `AirportBuilder.module.luau:24-25`), uniforms from existing `EmployeeRigDesign` feature keys (jacket, tie, cap, vest, hivis, gloves;
  GRANDHOTEL §0.3), poses from the existing `EmployeeController.pose` list (typeStand, greet, scan, present, carry, phone).
* Marshaller at PM1 during the shuttle's `taxiin` (FlightPlan timeline; pose `greet` with two neon wands [A: no dedicated marshal pose]).
* Terminal walkers: new CityLife region "pmairport" (the terminal + terrace, y <= G+34) with a small walk graph (L0 + stairs + L1),
  **16 walkers**; `GuestController` terminal passengers unchanged (cap 40, `GuestController.module.luau:32`).
* Welcome Wall text with the local player's company name [A: the company name is readable on the client, as the hotel's greetings assume,
  GRANDHOTEL §10.6].
* Arrival camera shot: first time per session the local player leaves the terminal through a south door after a flight: 5 s, camera
  rises to G+60 over the plaza looking down x = 0, then returns; any tap skips; never during a ride, never while the phone is open.
* Two sky crossings per cycle over Port Meridian from the same `FP.ambient` sky events the City uses (`FlightPlan.module.luau:817-825`);
  no runway visits at Port Meridian (no parallel taxiway; the runway is the shuttle's).

---------------------------------------------------------------------------------------------------------------------

## 4. City Airport: "the Hub"

### 4.1 The player journey
Drive in under the **Wing Roof**; the **Hub Lantern** over the check-in hall glows at night; staff at the islands and at security; a
departures wall that also lists the visiting airliner; walk the concourse to gate A1 or through the new door at the food court into
**Pier B** with two docked airliners and the Plane Spotters corner; the double-deck airliner in front of Hangar 2 fills the east window.
On arrival home, a meet & greet group at the arrivals exit holds a sign with your company name.

### 4.2 Plan view (plot: `design/airports/spectacle/plan_city_concept.png`)

```
 z 2380        Airport Road (unchanged)                                    airport_departures (66,2413.5) / arrivals (300,2413.5) unchanged
 z 2400..2546  WING ROOF x -330..330 (front edge G+36 at the kerb z 2400, crest G+50, back G+38), pylons x +-(328..334), z 2421..2427
 z 2430..2530  TERMINAL x -300..300 (unchanged); HUB LANTERN x -60..60, z 2455..2505 to G+58   HUB TOWER x 415..445, z 2455..2485 (G+150)
                                                                                                 HANGAR 2 x 805..1075, z 2420..2530 (G+90)
 z 2515..2545                                     PIER B x 300..770 (door from the food court at x 300, z 2515..2527)
 z 2552..2678  A1 (-200) A2 (0) A3 (200) unchanged     B1 (420,2612)  B2 (720,2612)  nose north, jet bridges   A380 (940,2650) nose south
 z 2640..2766                                          R2 (575,2700) ambient stand (unchanged)  GSE east x 650..790, z 2700..2768
 z 2790 / 2840..2880 / 2940..3060   taxilane / taxiway / runway (unchanged)        fuel farm moved to x 1088..1132, z 2560..2690
```

| Element | Coordinates [D] | Note |
|---|---|---|
| Wing Roof | x -330..330, z 2400..2546 (front edge on the kerb line, not over Airport Road's asphalt z 2360..2400, `CityPlan.module.luau:69`); underside >= 2 studs above every existing roof part (front G+27.5, crown G+40, back G+31.5, audit 1.1) | the existing roof stays; no coplanar faces; front pylons 6 studs from the car park (x <= -340) and 3 studs south of the drop-off lane (z <= 2418) |
| Hub Lantern | x -60..60, z 2455..2505, clerestory glass G+50..58, name "CITY AIRPORT INTERNATIONAL" | |
| Hub Tower | footprint x 415..445, z 2455..2485, Ops podium G+12, flared shaft, glass cab G+130..142, radar + beacon (the old tower's PropFx and its 1 real light move here) | replaces the 8-part tower at (820, 2620) (`AirportBuilder.module.luau:1897-1916`); Persistent like today, 80 parts |
| Pier B | x 300..770, z 2515..2545, one level, glass both sides, roof G+18 with a neon ribbon; Atomic model `PierB` | B noses are 7.6 studs from its south face (nose 59.4 ahead of the pivot [M: `AircraftModel.module.luau:200`, x 0.885]) |
| B1 | (420, G+.25, 2612) nose north, today's `RemoteAircraft` moved here from R1 (470, 2640) | R1's hull would overlap B1 |
| B2 | (720, G+.25, 2612) nose north, new parked 320 (full LOD) | B1 and B2 are 300 apart; R2 (575, 2700) sits between and behind them, >= 10 studs from both hulls and from its own measured envelope |
| Jet bridges B1, B2 | from the pier's south face (z 2545) to DoorL1 (z 2570.7, sill G+11.1), same builder as A1-A3 | 26-stud tunnels |
| R2 ambient stand | (575, 2700) unchanged (`FlightPlan.module.luau:716`) | measured: moving it onto a pier bridge costs one of the two ambient runway slots (section 1) - so it stays, served by a bus gate in Pier B |
| Hangar 2 + the 380 | hangar x 805..1075, z 2420..2530, door south, H 90; 380 static at (940, G, 2650) nose south, full LOD | 380 at the 1.8-equivalent scale: span 252, length 230, fin 76 [M from `AircraftModel.module.luau:104` x 0.885]; nose 21 studs north of taxiway traffic (2783) |
| Fuel farm | 2 tanks moved from x 980 (`AirportBuilder.module.luau:1945-1946`) to x 1110, z 2600 / 2660 | the 380's wing needs the space |
| GSE east | x 650..790, z 2700..2768 | 10+ studs from R2's measured envelope and B2 |

`layout.py` (City part): B1/B2 vs Pier B, A3, R2 and its measured ambient envelope (x 485.6..631.6, z 2640.6..2917), the 380 vs taxiway
traffic, fuel farm, GSE; tower vs pier and hangar; pylons vs lane and car park → all OK [M].

### 4.3 Departures / arrivals life (client, `AirportLifeController`, except where noted)
* **Gates A2 / A3 / B1 / B2** carry parked aircraft with turnaround life (belt loader conveyor via PropFx "belt" as on the carousel,
  catering truck lift, fuel truck, tug); their signs say "PARKED · TURNAROUND" instead of "GATE CLOSED" (`AirportBuilder.module.luau:1245-1247`).
* **Boards:** A1 shows PM 101 (unchanged); the ambient visit to R2 gets a fictional flight number and city from a new `FP.AMBIENT_FLIGHTS`
  table, with status from its real timeline (LANDED / AT STAND R2 / DEPARTED). Boards still show only what FlightPlan moves.
* **R2 bus gate** in Pier B: during the ambient `parked` phase an apron bus drives between the pier and R2 (client, deterministic).
* **Follow-me car** leads the ambient airliner from the east connector to R2 (client).
* **Staff** at the existing `AirportPost` markers (checkin, security, gate, lounge, shop, crew), roster 17, **<= 8 drawn**.
* **Meet & greet** at the arrivals exit (x 270): 4 figures, one with a sign carrying the arriving local player's company name.
* **Crowd:** CityLife region "airport" grows to the terminal + Pier B (`MetroPlan.module.luau:1235`) and the airport walk graph gets a pier
  branch; walkers 30 → **36** (`CityLifeController.module.luau:44`).
* **Plane Spotters corner** at the pier's east end: telescopes (client "Look"), info boards about the aircraft types.

### 4.4 Inside the main terminal (TerminalInterior cap stays 3,500)
Departures wall (FIDS) in the check-in hall, a "Hub Globe" sculpture under the lantern, the door to Pier B in the food court's east wall
(x 300, z 2515..2527), the lounge shelf with tea & juice jars. +140 parts: 3,145 → 3,285 of 3,500 [M today, D after].

---------------------------------------------------------------------------------------------------------------------

## 5. Why Port Meridian ends up better than the new City Airport

| Criterion | New City Airport | Port Meridian | Better |
|---|---|---|---|
| First view | Wing Roof from Airport Road | water approach + seawall runway + skyline (seen by every arriving passenger) | PM |
| Walk to / from the aircraft | A1 bridge (flag) | PM1 glass bridge into a two-level glass terminal (flag) | PM |
| Interior detail density | whole `TerminalInterior` 2,988 parts / 60,000 sq studs = 0.050 [M, audit 2.4] | L0 outside the open atrium 1,040 / 16,000 = **0.065**, the Club 280 / 4,000 = **0.070**; L0 including the atrium 1,100 / 25,600 = 0.043 [D] | PM (except the deliberately open atrium) |
| Views | apron through the concourse glass | runway and sea from the Sky Gallery, boulevard axis from the atrium | PM |
| VIP | business lounge (no access rule) | Meridian Club + Sky Terrace heliport + Jet Centre with its own kerb | PM |
| Private jets | Hangar 1 (unchanged) | 4-slot VIP ramp, FBO lounge, chauffeur at the door | PM |
| Connection to the destination | Airport Road | Palm Plaza → Palm Boulevard → Meridian Grand porte-cochère; heli to the hotel roof | PM |
| Personal touches | meet & greet sign | Welcome Wall, marshaller, arrival camera shot, meet at the Jet Centre | PM |
| Traffic | more stands, ambient visit, the 380 | parked fleet + jets + sky crossings | City (by design: the hub) |

---------------------------------------------------------------------------------------------------------------------

## 6. Every existing flow: kept, or exactly what changes in which file

| Flow | Today [M] | Concept | Files (package) |
|---|---|---|---|
| **Shuttle, home side** | stand A1 (-200, 24.25, 2612), gate (-200, 28, 2512), board prompt at `GateA1/GateDesk` (`ShuttleService.module.luau:155-160`), auto-board within 36 of `FP.HOME_GATES` (`FlightPlan.module.luau:224, 230`; `ShuttleService.module.luau:574-592`), hold under the stand (`FlightPlan.module.luau:234`), arrival PivotTo `AIRPORT.arrival` (`ShuttleService.module.luau:599, 606`) | **unchanged** with `WALK_BRIDGE = false`. With `true`: `FP.HOME_GATES` gets a 2nd point at the A1 cab (computed in FlightPlan from `standCFrames[1]` x the scaled DoorL1), a 2nd board prompt at `JetBridge_A1/BoardingPoint`, and the arrival frame is the A1 cab facing the terminal, `FP.BRIDGE.time` (4 s, `FlightPlan.module.luau:298`) after the deboarding phase starts (it lasts 10 s) | FlightPlan, ShuttleService, ShuttleController (AP4) |
| **Shuttle, Port Meridian side** | stand PM1, `ApronDoor`, `FP.PM_GATES` 4 points (`FlightPlan.module.luau:228`), arrival `ABROAD.arrival` | PM1, ApronDoor, PM_GATES[1..3] unchanged; PM_GATES[4] follows `ABROAD.checkin[2]` (+70 → -110, inside the new L0). `WALK_BRIDGE`: arrival in the PM1 cab, 5th PM gate point at the cab, board prompt at the cab | FlightPlan, ShuttleService (AP4); bridge animation ShuttleGround (AP5) |
| **Timetable / ambient** | 368-s cycle, ambient slots 5.0 / 171.3 (audit 4.1-4.2) | unchanged: no runway, stand, taxi route or R2 change. Measured why R2 stays (section 1) | none |
| **Charter / express** | 10-s cutscene teleport to `ABROAD.arrival` / `AIRPORT.arrival` (`CityPlan.module.luau:32`, CityService) | unchanged points; the new buildings keep them on a free floor (test) | none |
| **Clearance** | `flight_clearance 18/0`, server parts only | + all new server parts (W1/W2, tower, terrace, Jet Centre, bridges, Pier B, Hub Tower, 380) + the `MetroPlan.FAR` boxes | tests/flight/clearance.py, clearance_dump.sh (AP1 for FAR; AP4 re-runs) |
| **Company jet, home** | Hangar 1, `HOME_PARK` (-930, 2640), apron field (`JetPlan.module.luau:81-83, 472`) | unchanged | none |
| **Company jet, PM** | 2 slots, `PM_STANDS_FULL` at the 3rd | 4 slots, field "vip", `ARRIVAL.abroad` at the Jet Centre, new exits, toast text (3.6) | JetPlan, JetController (AP4); JetService only if a test shows it assumes 2 slots |
| **VIP heli** | pad (604, 25, 7670), 46.1 s, start radius 40 / dy <= 16 (`ShuttleService.module.luau:64, 672`), arrival at the airport = `(p.X-28, GROUND+3.5, p.Z+44)` (`ShuttleService.module.luau:654`) | pad on the Sky Terrace (-211, G+17, 7651): 41.2 s [M]. `heliArrival("airport")` must use the **pad top Y** instead of `GROUND+3.5` and the offset (+30, 0) so the passenger lands on the deck at (-181, G+19.5, 7651) facing the Club door; the hotel branch stays GRANDHOTEL B's. The client prompt follows the `Helipad` part (`AirTrafficController.module.luau:177`) | MetroPlan (AP0 data), ShuttleService (AP4), tests/flight test_shuttle/test_client heli expectations (AP4), tests/metro/test_build.luau:72 (AP2) |
| **Limo / drivers** | `airport_departures` (66, 2413.5), `airport_arrivals` (300, 2413.5), `pm_limo` (176, 7762), `pm_airport` (-75, 7772.6), `pm_hotel` (`DrivePlan.module.luau:341-416`), `PM_STAND_AREA` (`:499`), pick-up radius airport 140 / pm 110 (`:50`) | all unchanged; + `pm_jetcentre`; `PM_STAND_AREA` + Jet Centre rect; the Wing Roof pylons and the porte-cochère must pass `tests/drivers/clearance.sh` | DrivePlan (AP4); tests/drivers (AP4) |
| **Itinerary** | `IM.gatePoint` = HOME_GATES[1] / PM_GATES[1], `IM.inAirport` = terminal + 24, `IM.inPMAirport` = terminal / plaza + 14 (`ItineraryMath.module.luau:753-768`, live) | gate points unchanged. `inAirport` also true inside Pier B; `inPMAirport` also true on the Sky Terrace and in the Jet Centre | ItineraryMath (AP4); tests/itinerary (AP4) |
| **Crowd** | CityLife airport region + 30 walkers; GuestPlan terminals (`GuestPlan.module.luau:801-803`); 40 passengers | region + graph into Pier B, 36 walkers; new "pmairport" region, 16 walkers; GuestPlan rects unchanged (the PM rect already reaches x 270; its height follows `ABROAD.height`, G+56 → G+62) | MetroPlan data (AP0), CityLifeController (AP5) |
| **Markers** | audit 4.6 | kept with the same names/attributes: `ShuttleStand`, `ApronDoor`, `BusinessLounge` (now L1), `LoungeConciergePost`, `VipLimoStand`, `Helipad` x2, `HelipadExit` (hotel, untouched), `CheckinCounter`, `GateA<n>/GateDesk`, `JetBridge_A<n>`, `ParkedAircraft` (A1-A3), `CompanyJetStand`, `Hangar/PrivateJet`, `FlightInfoBoard`, `AirportPost`, `CrewRoom`. New: `JetBridge_PM1`, `JetBridge_B1/B2`, `RemoteAircraft` W1/W2 (Stand attr), `GateB<n>/GateDesk`, `JetCentreDoor` | AP2, AP3 |

---------------------------------------------------------------------------------------------------------------------

## 7. No overlap with the Meridian Grand (site and budget)

**Areas this concept uses** (world): Port Meridian airport district x -700..700, z 7500..7768 (north of Arrivals Drive's north kerb);
one kerb place at (470, RT, 7772.6) on Arrivals Drive; the palm points on the boulevard median lawns (x ±19.5, z 7823..8301), at the
tower forecourts (x ±98, z 7915..8245) and in the 4 plaza planters; client-only water outside the zone at x -1800..-704, z 7240..7660.
**Nothing at z > 8310.**

**Areas of the Meridian Grand** (GRANDHOTEL §0.2, §6.1, §11, §0.3 critic row): building x -70..70, z 8380..8500; forecourt / drive x -54..54,
z 8352..8380 with mouths x -54..-36 and 36..52.6, z 8352..8360; lift tower site x 70..95, z 8370..8510; roof pad and approach; `pm_hotel`;
Harbour Street gaps; the hotel impostor. Minimum distance from any new airport rectangle to the hotel site: **> 50 studs** (checked in
`layout.py`; the nearest palm is at z 8301, 51 studs from the forecourt edge z 8352).

**Budgets:** the airport gets its own capped model `WorldCity/PortMeridian/MeridianAirport`, excluded from the metro count exactly like the
hotel (GRANDHOTEL §19.1, F9). It uses 0 of the hotel's 3 real lights, has its own client-light cap (<= 4, only within 300 studs of the
terminal; the hotel controller's <= 3 are 600+ studs away), its own `MetroNightGlow` count (<= 150) and never touches `GrandPlan`,
`Hotel_intl_hotel` or the hotel's tests. The hotel's "24 parts left" in the metro count grows to ~886 (section 8).

Shared files the hotel packages edit first (`MetroPlan`, `CityLifeController`, `ShuttleService`, `tests/metro/test_build.luau`,
`tests/flight/test_shuttle.luau`, `test_client.luau`): the airport packages edit their **post-hotel** versions, additively, and re-run the
hotel's suites (`tests/grandhotel/run.sh`) as a gate.

---------------------------------------------------------------------------------------------------------------------

## 8. Budgets

### 8.1 Parts - City Airport (zone "airport")

| Item [D] | Estimate | Cap (test) |
|---|---|---|
| Wing Roof + Hub Lantern + door portals | 180 | 260 |
| Hub Tower (80) minus the old tower (8) | +72 | tower model 90 |
| Pier B shell + fit-out (Atomic `PierB`: 2 gate lounges, bus gate, spotters corner) | 520 | 650 |
| Jet bridges B1, B2 (2 x 32, measured size of A bridges, audit 1.3) | 64 | 70 |
| B2 parked 320 (B1 = today's R1 aircraft, moved) | 330 | - (aircraft) |
| GSE at B1/B2 (R1's remote-stand GSE moves to the R2 bus gate) | 140 | in exterior |
| Hangar 2 shell / the 380 (full LOD "<= ~350", `AircraftModel.module.luau:24`) | 45 / 350 | 70 / - |
| Forecourt dress, apron extension and markings | 130 | in exterior |
| TerminalInterior adds | 140 | interior cap 3,500 unchanged |
| **Total new** | **~1,971** | |

* Airport zone: 6,550 [M] → ~8,520; **cap 7,000 → 9,000** (`agents/world/world_check.py:48` BUDGET and `tests/world/test_build.luau:54`).
* `tests/airport/test_airport.luau`: interior 3,145 → ~3,285 (cap 3,500, unchanged); exterior without aircraft 1,764 → ~2,395, **cap
  2,000 → 2,500**; new check `PierB` <= 650; aircraft (unbudgeted there) 1,650 → ~2,330.
* Persistent in WorldCity: +72 parts (tower), within `tests/world/test_build.luau:87` (<= 12 models, <= 800 parts).

### 8.2 Parts - Port Meridian

Removed from the metro-built city [M, dump]: ArrivalTerminal 188 + Airfield 437 + VipHelipad 34 + ArrivalPlaza 125 + lots "aw" 30 +
median trees 48 = **862**.

| `MeridianAirport` sub-model [D] | Streaming | Estimate | Cap |
|---|---|---|---|
| BayTerminal shell (glass, sail vaults, L1 slab, stairs, portals) | Default | 400 | 500 |
| TerminalInterior L0 | Atomic | 1,100 | 1,250 |
| SkyGallery L1 | Atomic | 260 | 320 |
| BusinessLounge "The Meridian Club" | Atomic | 280 | 340 |
| SkyTerrace + Helipad | Default | 56 | 90 |
| JetBridge_PM1 | Default | 38 | 45 |
| Airfield (runway dress, seawall, markings, ramp marks, GSE, localiser) | Default | 200 | 260 |
| RemoteApron W1 (full 330) + W2 (medium ~76) + stairs + GSE | Default | 444 | 480 |
| JetCentre (shell + Atomic interior + ramp GSE) | Default / Atomic | 160 | 220 |
| PalmPlaza (rebuilt plaza, porte-cochère, fountains, 4 palms) | Default | 210 | 240 |
| PalmBoulevard (32 palms x 8) | Default | 256 | 260 |
| BayTower | Default | 50 | 60 |
| **MeridianAirport** | | **~3,454** | **4,100** (sub-caps sum 4,065) |

* Metro count (`tests/metro/test_build.luau:20-21`, cap 781 + 4,500 = 5,281, hotel frozen at 78 per GRANDHOTEL F9): 5,257 → **~4,395**
  (MeridianAirport excluded like the hotel) → ~886 left instead of 24.
* Port Meridian zone: <= 8,429 after the hotel (GRANDHOTEL §19.1) - 862 + 4,100 = **<= 11,667 of 20,000**.
* Whole shared world: <= 17,980 after the hotel (GRANDHOTEL §19.1) + 2,450 (City zone cap headroom 9,000 - 6,550) - 862 + 4,100 = **<= 23,668 of 30,000**.

### 8.3 Lights, glow, glass, prompts, seats

| Item | City | Port Meridian |
|---|---|---|
| Real lights | 40/40 unchanged (zone 35 airport + 5 road lamps, audit 1.5); the tower's beacon light moves with the tower; Pier B, Hangar 2, Wing Roof use neon | MeridianAirport uses **exactly 9** = the 9 the removed pieces had (hall 3, lounge 2, heli 1, plaza 3, audit 2.4): atrium 2, Sky Gallery 1, Club 2, terrace 1, porte-cochère 1, Jet Centre 1, plaza lamp 1. Built in today's airport slot of `Metro.build` (first, `MetroBuilder.module.luau:1295-1297`), so the street lamps keep theirs; zone stays 40/40 |
| Client lights | <= 4 (`AirportLifeController`, `Shadows = false`, range <= 24, only near the camera) | <= 4, same rules; none further than 300 studs from the terminal |
| Night glow | own tag `AirportNightGlow` (<= 150 parts) with a 2-s night check in `AirportLifeController` (CityLife's glow only updates inside its regions, `CityLifeController.module.luau:1463, 1509-1517`) | `MetroNightGlow` <= 150 more (PM 198 today → ~493 after the hotel → <= 643) |
| Visible semi-transparent area (largest face, 0.05 < T < 0.95) | <= 10,000 sq studs new (Pier B one glazed side + clerestory) | <= 20,000 sq studs (frit bands on the north wall; GRANDHOTEL caps its own at 25,000) |
| Server prompts | +1 (board at the A1 cab, flag) | +2 check-in, +1 board at the PM1 cab (flag); heli and telescopes are client prompts |
| Seats (`Seat` instances) | 0 new | >= 24 (Club 12, Jet Centre 6, Sky Deck 6) |
| SurfaceGuis | <= 30 new, `MaxDistance` <= 60 | <= 40 new, `MaxDistance` <= 60 |
| ParticleEmitters | 0 | 0 (fountains are neon jets like the boulevard's, `MetroBuilder.module.luau:695-700`) |

---------------------------------------------------------------------------------------------------------------------

## 9. iPhone performance

* **Streamed density.** Parts within 512 studs (flat) [M today, D after]: City terminal centre 5,594 → ~6,450 (Pier B is half outside the
  radius, the 380 and Hangar 2 at x 940 are outside it); Port Meridian terminal 1,838 → ~4,100 (+3,454 new minus W1, the Bay Tower and
  ~12 palms outside the radius, minus ~750 removed parts inside it); the hotel door 2,514 → GRANDHOTEL's ~5,400 + ~144 (palms within 512
  of the door replace 48 tree parts). Both airports stay below ~6,500, far below one tier-4 HQ (28,341 parts, GRANDHOTEL §19.1).
* **Atomic sizes:** PM L0 <= 1,250, Club <= 340, Sky Gallery <= 320, Jet Centre interior <= 120, City Pier B <= 650 (today the City
  `TerminalInterior` is 2,988 Atomic; its iPhone load time was never measured - [S]).
* **Client work:** `AirportLifeController` step <= 30 Hz, disconnected (one 1-Hz check left) while the camera is > 700 studs from both
  airports; `debug.profilebegin("AirportLife.step")`; `stats().lastStepMs`; staff rigs <= 8 drawn (<= 22 parts each, `Rig.MAX_PARTS`), full
  limb animation within 40 studs, 5 Hz to 90, hidden beyond; one `BulkMoveTo` per frame for all moving figures and vehicles; walkers City
  36 (mock today 30 walkers = 1.61 ms per step, audit 1.6) and PM 16.
* **Fewer client parts at Port Meridian:** 108 far shells fewer [M] (279 → 171).
* **Glass overdraw:** caps in 8.3; frit bands and opaque soffits; Glass material only on the terminal facades, never stacked behind a second
  glass layer within 20 studs.
* **Cut list** (in this order, if profiling on a device demands it [S]): (1) W2 aircraft → low LOD; (2) palms 8 → 5 parts; (3) staff
  drawn 8 → 5; (4) arrival camera shot off; (5) PM walkers 16 → 8; (6) Club aquarium; (7) Sky Gallery telescopes; (8) the 380 → medium LOD;
  (9) Pier B spotters corner; (10) `WALK_BRIDGE = false`.

---------------------------------------------------------------------------------------------------------------------

## 10. Packages, order and file ownership

**Order:** round 2b + shop released → GRANDHOTEL A and B built, verified and reviewed (GRANDHOTEL §21.1) → **AP1** → **AP0** →
**AP2 ∥ AP3** → **AP4** → **AP5** → joint verify → independent review → fix round.
No file belongs to two packages that run at the same time. Every package re-runs `run_all` and the suites listed below; all rc 0 is the gate.

| Package | Starts after | Owns (may edit) | Must stay green |
|---|---|---|---|
| **AP1 `airports_bay`** (W2 fix, small, ships alone) | GRANDHOTEL A + B | `MetroPlan.module.luau` (FAR bands, FAR_GROUND, new FAR_SEA only), `CityLifeController.module.luau` (FarSea parts, flush approach lights), `tests/flight/clearance.py` + `clearance_dump.sh` (sweep `MetroPlan.FAR`), `tests/metro/test_life.luau` (far counts) | tests/flight/run.sh, tests/metro/*, tests/grandhotel/run.sh |
| **AP0 `airports_prewire`** (integrate role) | AP1 | `ReplicatedStorage/Shared/Config/AirportsPlan.module.luau` (new, v1 written verbatim from the spec: every coordinate, cap and flag `WALK_BRIDGE`, `PALMS`, `ARRIVAL_SHOT`); data edits written verbatim: `CityPlan.module.luau` (`AIRPORT.piers.B`, B stands, tower; `ABROAD.checkin` 4 points, `ABROAD.height` 32, terrace and Jet Centre rects), `MetroPlan.module.luau` (`HELIPADS.airport`, BLOCKS without "aw", REGIONS + PM terminal walk data, plaza fountain obstacles); new `JetBridgeKit.module.luau` = extraction of AirportBuilder's bridge builder (world dump byte-identical, tests/airport 95/0) + the 2-line call change in `AirportBuilder.module.luau`; stubs `MeridianAirportBuilder`, `AirportLifeController`; `Main.server` / `Main.client` wiring; run_all lines for `tests/airports/run.sh` | everything (no visible change yet) |
| **AP2 `pm_airport_build`** | AP0 | `ServerScriptService/Server/Services/MeridianAirportBuilder.module.luau` (new: all of section 3 geometry, markers, 9 lights, glow tags), `MetroBuilder.module.luau` (replace the calls `airport/lounge/vipAirport/plaza` by `MeridianAirportBuilder.build(m, K)` in the same slot; skip median and forecourt trees when `PALMS`), `tests/metro/test_build.luau` (exclude `MeridianAirport` like the hotel; re-point the airport checks: lounge, ShuttleStand, ApronDoor, hull with the bridge exception, helipad on the terrace, W1/W2), `tests/airports/test_pm_build.luau`, `tests/airports/render_pm.py` (new) | tests/metro/*, tests/world/*, tests/flight/run.sh (clearance), tests/grandhotel/run.sh |
| **AP3 `city_hub_build`** | AP0 (parallel to AP2) | `AirportBuilder.module.luau` (Wing Roof, lantern, Hub Tower, Pier B, B stands and bridges via JetBridgeKit, R1 → B1, Hangar 2 + 380, fuel farm, forecourt, lounge palette, interior adds, gate signs), `tests/airport/test_airport.luau` (caps, Pier B checks), `tests/world/test_build.luau` (airport zone 9,000), `agents/world/world_check.py` (BUDGET airport 9,000), `tests/airports/test_city_build.luau`, `tests/airports/render_city.py` (new) | tests/airport/*, tests/world/*, tests/flight/run.sh, tests/drivers/clearance.sh |
| **AP4 `airport_flows`** | AP2 + AP3 | `FlightPlan.module.luau` (`WALK_BRIDGE` gate points + arrival frames, `AMBIENT_FLIGHTS` names), `ShuttleService.module.luau` (heli airport arrival Y + offset; board prompts at the cabs; walk-on arrival), `ShuttleController.module.luau` (arrival timing), `JetPlan.module.luau` (slots 3-4, exits, `ARRIVAL.abroad`, field "vip"), `JetController.module.luau` (toast text), `JetService.module.luau` (only if needed), `DrivePlan.module.luau` (`pm_jetcentre`, `PM_STAND_AREA`, `nearestPickup`), `ItineraryMath.module.luau` (`inAirport`, `inPMAirport`), tests in `tests/flight/`, `tests/guests_jet/`, `tests/drivers/`, `tests/itinerary/`, `tests/airports/test_flows.luau` | all travel suites + clearance + drivers clearance |
| **AP5 `airport_life`** | AP4 | `StarterPlayer/.../Controllers/AirportLifeController.module.luau` (new: staff, marshaller, GSE and bus animation, follow-me car, meet & greet, Welcome Wall text, arrival camera shot, telescopes, night glow, client lights), `AirTrafficController.module.luau` (PM sky crossings, live board rows), `ShuttleGround.module.luau` (PM1 bridge dock / retract like A1, keeps a bridge docked while the local character stands in it), `CityLifeController.module.luau` (airport region + pier walkers 36, "pmairport" region 16), `EmployeeRigDesign.module.luau` (airport uniforms, additive), `CampusAudioConfig.module.luau` (silent keys `""`), `tests/airports/test_life.luau`, GUI previews | tests/metro/test_life, tests/flight/*, guiprev |

**Contracts between packages:** AP0's `AirportsPlan` v1 is the only source of new coordinates (changes only by request to the AP0 owner);
AP2/AP3 build the markers of section 6 with exactly those names; AP4 reads markers only through `AirportsPlan` / `CityPlan` / `MetroPlan`
data (FlightPlan stays pure); AP5 never writes server instances.

---------------------------------------------------------------------------------------------------------------------

## 11. Tests and gates (each suite prints "<name>: N passed, M failed")

* **AP1:** probe-equivalent test: 0 s of any shuttle / jet hull point inside a far shell, >= 50 studs minimum distance (today 0, concept
  69.4 measured); far shells never inside `FAR_SEA`; FarSea seams with the persistent OpenSea (no gap > 0.5 stud along z 7500 / 7240).
* **AP2:** part caps of 8.2; exactly 9 real lights in `MeridianAirport`, 40 abroad; nothing above G+1 in x -700..700, z 7487..7520; nothing
  above G+0.6 inside the measured PM1 envelope (x 192.6..397.2, z 7487..7734.4) except PM1's bridge; stand-1 hull free except
  `JetBridge_PM1` (checked by the flight sweep with 0.25 and in its retracted frames, like A1); ApronDoor opening free (unchanged test);
  helipad: one `VIPAirport` pad on the terrace, rotor circle r 16.4 free above the pad top; Club Atomic with >= 8 Seats; Persistent only for
  the Spire; nothing new at z > 8310; walk portals at x -80/0/80 reachable; arrival point and charter point on a free floor.
* **AP3:** caps of 8.1; B noses >= 5 from Pier B; R2's measured envelope free; the 380 >= 20 from taxiway traffic; jet-bridge cabs at the
  DoorL1 of the built aircraft (as the A-bridges are tested); world_check OK; drivers clearance with the Wing Roof pylons.
* **AP4:** `WALK_BRIDGE=false` → byte-identical FlightPlan timetable and travel behaviour (probe_times numbers of audit 4.1); `true` →
  board at the cab, arrival in the cab after docking, nobody left in a retracting bridge; heli 41.2 s and arrival on the deck; 4 jet slots
  with >= 4-stud hull distance to parked jets in every scheduled sample (tests/guests_jet test_jet), `PM_STANDS_FULL` at the 5th company;
  `pm_jetcentre` legs routed 15..70 s like the other PM places; itinerary predicates.
* **AP5:** `AirportLifeController` step mean <= 1.0 ms in the mock with 8 rigs + 16 walkers drawn; <= 4 client lights at any time; no
  server instance written; deterministic positions for two clients at the same server time.
* **Joint verify:** world dump + world_check, `world_entrances`, flight clearance (+FAR), drivers clearance, metro paths, run_all,
  blenderprev shots (City: Wing Roof from Airport Road, lantern hall, Pier B, airside aerial with the 380; PM: approach over the bay,
  terminal from the plaza, atrium with the Skybridge, Club, Sky Terrace with the heli, Jet Centre ramp, boulevard axis to the hotel), guiprev
  of the two small client UIs (telescope view, arrival-shot skip) at 844x390 and 1280x720.

---------------------------------------------------------------------------------------------------------------------

## 12. Risks

1. **Biggest risk: the Port Meridian rebuild migrates many hard contracts at once** (metro test split, re-pointed metro checks, heli pad
   + `heliArrival`, 4 jet slots, the PM1 bridge hull exception, the walk-on flow) in files that round 2b and the hotel packages edit just
   before (`ShuttleService`, `FlightPlan`, `MetroPlan`, `CityLifeController`, `tests/metro/test_build.luau`). A slip shows up as a broken
   trip abroad - the core loop. Mitigation: everything that defines a flight stays fixed (runway, PM_LINE, PM1, ApronDoor, taxi line,
   timetable, R2); the data lands first and verbatim in AP0; walk-on is behind `WALK_BRIDGE` (false = today's behaviour, tested
   byte-identical); AP1 (the W2 fix) ships alone first; every package re-runs the hotel and travel suites.
2. **iPhone cost of a glass terminal** with ~4,100 parts within 512 studs, two Atomic interiors and ~20,000 sq studs of glass - only measurable on a device [S]; caps
   and the cut list are in section 9.
3. **Timing fragility:** moving R2 onto a pier bridge measurably cost one of the two ambient runway slots (section 1); any later change
   to stands or taxi routes must re-run `probe_times` / `FP.ambientSlots`.
4. **Bridge cabs and players:** a client-animated bridge moves server geometry locally; a player standing in it while it retracts could
   fall. Mitigation in AP5 (bridge stays docked locally while the local character is inside; auto-board covers the cab point).
5. **Walker graph obstacles:** the plaza fountains are new solid props; they must be added to MetroPlan's obstacle list (AP0) or the
   walkers step through them.

---------------------------------------------------------------------------------------------------------------------

## 13. Only Studio or a real iPhone can confirm [S]

Frame time and memory at both terminals on an iPhone in landscape; load time of the Atomic interiors; the FarSea seam with the persistent
OpenSea seen from the approach and from the Sky Gallery; heli arrival on the terrace deck (Humanoid lands on the deck, not under it);
glass overdraw in the atrium at night; that a player can actually walk the PM1 bridge slope (rise 10.6 over ~52 studs) and the Grand
Stairs (0.73 rise per step) on touch controls; the marshaller and staff poses read well from the cockpit camera.

## 14. Assumptions [A]

* The company name is available on the client (Welcome Wall, meet & greet sign), as GRANDHOTEL §10.6 assumes for the hotel greetings.
* The Jet Centre "COMPANY JETS" board can read the replicated jet folders JetController already reads.
* No marshal pose exists in `EmployeeController.pose` (GRANDHOTEL §0.3 list); the marshaller uses `greet` with neon wands.
* The 380 part count follows the `AircraftModel` comment ("full (<= ~350 parts)", `AircraftModel.module.luau:24`); not built and counted here.
* Part estimates in 8.1 / 8.2 are design estimates from comparable measured pieces (bridge 32, gate lounge 164-179, parked 320 330, lounge
  90-197); the caps are what the tests enforce.

## 15. Roblox APIs named in this concept (all in `tools/API-Dump.json`, `apicheck.py`: 67 checked, 0 missing)

`ProximityPrompt` (ActionText, ObjectText, HoldDuration, MaxActivationDistance, RequiresLineOfSight, Triggered), `Model.ModelStreamingMode`
+ `Enum.ModelStreamingMode.{Atomic,Persistent,Default}`, `Player:RequestStreamAroundAsync`, `PointLight` (Range, Brightness, Shadows),
`SurfaceLight`, `BasePart` (CastShadow, CanCollide, CanTouch, CanQuery, Material, Transparency), `Enum.Material.{Neon,Glass,Marble,Granite,
Limestone,LeafyGrass,Wood,Metal}`, `CollectionService` (GetTagged, GetInstanceAddedSignal, AddTag), `WorldRoot:BulkMoveTo`,
`Camera` (CameraType, CFrame, FieldOfView) + `Enum.CameraType.{Scriptable,Custom}`, `Workspace.CurrentCamera`, `TweenService:Create`,
`Lighting.ClockTime`, `PVInstance:PivotTo`, `Model:GetBoundingBox`, `WedgePart`, `Part.Shape` + `Enum.PartType.{Ball,Cylinder}`,
`SurfaceGui` (Face, MaxDistance), `TextLabel`, `UserInputService.InputBegan`, `Instance` (SetAttribute, GetAttribute,
GetAttributeChangedSignal), `ScreenGui.ScreenInsets` + `Enum.ScreenInsets.CoreUISafeInsets`, `RunService` (Heartbeat, RenderStepped).
`debug.profilebegin` / `profileend` are Luau built-ins.

## 16. Files

* this concept: `design/airports/concept_spectacle.md`
* plan plots: `design/airports/spectacle/plan_pm_concept.png`, `plan_city_concept.png`
* checks and probes: `design/airports/spectacle/layout.py`, `density.py`, `apicheck.py`, `apis.txt`,
  `sb/tests/spectacle/probe_bay.luau`, `probe_env.luau`, `probe_ambient.luau`, `probe_ambient2.luau`
* outputs: `design/airports/spectacle/probe_bay_out.txt`, `probe_env_out.txt`, `probe_ambient_out.txt`, `layout_out.txt`, `density_out.txt`
* sandbox variants: `design/airports/spectacle/sb/work/src_bay` (Meridian Bay + terrace pad), `src_city`, `src_city2` (ambient experiments)

---------------------------------------------------------------------------------------------------------------------

## Appendix A. `AirportsPlan` v1 sketch (for the AP0 prewire; world studs, G = CityPlan.GROUND)

```lua
-- flags
WALK_BRIDGE = true, PALMS = true, ARRIVAL_SHOT = true,
-- Port Meridian
PM = {
  terminalHeight = 32, roofCrest = 44, gallery = {y = 16.5, x1 = -160, x2 = 160, z1 = 7610, z2 = 7650, void = {x1 = -60, x2 = 60, z1 = 7626, z2 = 7650}},
  stairs = {{x1 = -60, x2 = -44, foot = 7662, top = 7626}, {x1 = 44, x2 = 60, foot = 7662, top = 7626}}, -- top lands on the Skybridge
  club = {x1 = -160, x2 = -60, z1 = 7610, z2 = 7650},
  terrace = {x1 = -262, x2 = -160, z1 = 7614, z2 = 7688, y = 16}, heliPad = Vector3.new(-211, 17, 7651), heliArrive = Vector3.new(-181, 19.5, 7651),
  checkin = {Vector3.new(-70, 0, 7636), Vector3.new(-110, 0, 7636), Vector3.new(-90, 0, 7636), Vector3.new(-130, 0, 7636)}, -- [1] unchanged, [2] was (70)
  remote = {{id = "W1", cf = CFrame.lookAt(Vector3.new(-560, 0.25, 7676), Vector3.new(-500, 0.25, 7676)), lod = "full"},
            {id = "W2", cf = CFrame.lookAt(Vector3.new(-390, 0.25, 7676), Vector3.new(-330, 0.25, 7676)), lod = "medium"}},
  jetSlots = {{600, 7612}, {480, 7664}, {600, 7668}, {600, 7724}}, vipField = {x1 = 400, x2 = 700, z1 = 7590, z2 = 7760},
  jetCentre = {x1 = 410, x2 = 515, z1 = 7698, z2 = 7756, airside = Vector3.new(470, 0, 7698), landside = Vector3.new(470, 0, 7756), arrival = Vector3.new(470, 3.3, 7735)},
  jetCentreKerb = Vector3.new(470, 0.22, 7772.6),
  tower = {x1 = -668, x2 = -652, z1 = 7722, z2 = 7738, cab = 84, top = 104},
  porteCochere = {x1 = 104, x2 = 200, z1 = 7740, z2 = 7768, underside = 14}, fountains = {{-40, 7710, 7}, {40, 7710, 7}},
  seawall = {z1 = 7500, z2 = 7504, maxTop = 0.4}, northKeepLow = {z1 = 7487, z2 = 7520, maxTop = 1},
  caps = {model = 4100, shell = 500, l0 = 1250, gallery = 320, club = 340, terrace = 90, bridge = 45, airfield = 260, remote = 480, jetCentre = 220, plaza = 240, palms = 260, tower = 60, lights = 9, glow = 150, clientLights = 4},
},
BAY = {farW_z1 = 7660, sea = {{x1 = -1800, x2 = -1150, z1 = 7240, z2 = 7660}, {x1 = -1150, x2 = -704, z1 = 7500, z2 = 7660}}, approachLights = {x1 = -1300, x2 = -700, z = 7544, y = -2.9}},
-- City Airport
CITY = {
  wing = {x1 = -330, x2 = 330, z1 = 2400, z2 = 2546, front = 36, crest = 50, back = 38, pylons = {{-334, -328}, {328, 334}}, pylonZ = {2421, 2427}},
  lantern = {x1 = -60, x2 = 60, z1 = 2455, z2 = 2505, top = 58},
  tower = {x1 = 415, x2 = 445, z1 = 2455, z2 = 2485, cab = 130, top = 150},
  pierB = {x1 = 300, x2 = 770, z1 = 2515, z2 = 2545, roof = 18, door = {x = 300, z1 = 2515, z2 = 2527}},
  standsB = {{id = "B1", x = 420}, {id = "B2", x = 720}}, standZ = 2612,
  hangar2 = {x1 = 805, x2 = 1075, z1 = 2420, z2 = 2530, h = 90}, a380 = CFrame.lookAt(Vector3.new(940, 0, 2650), Vector3.new(940, 0, 2750)),
  fuelFarm = {x = 1110, z = {2600, 2660}}, gseEast = {x1 = 650, x2 = 790, z1 = 2700, z2 = 2768},
  caps = {zone = 9000, exterior = 2500, pierB = 650, tower = 90, wing = 260, hangar2 = 70, glow = 150, clientLights = 4},
},
```
(y values are relative to G; the prewire converts them. Every number here is also in sections 3-4.)
