# Airport concept: "Departures are content" (gameplay first)

This is one complete concept for **both** airports: City Airport on the main island and Port Meridian Airport abroad.
Date: 2026-10-17. It is design only. Nothing under `work/`, `tests/`, `agents/stable/` or the existing `design/*` files
was edited. My own evidence (probes, scripts, outputs and plan PNGs) is in
`design/airports/concept_gameplay_work/` (listed in Appendix C).
Paths are relative to `scratchpad/` = `/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad`.

**The angle in one sentence.** Today an airport is a counter plus a teleport. In this concept each airport becomes a
place with a route to walk, staff who greet you, lounges you earn, a hangar you upgrade, shops you collect from and
planes you watch. Every step is tied to the AI-company systems that already exist: office stage, B2B trips, the
company jet, drivers and the itinerary. Port Meridian is the reward city for stage 4 and 5, so its airport has the
best lounge in the game (the Meridian Founders Club), the Executive Jet & Heli Centre, a real jet bridge and the
"business world" welcome.

---------------------------------------------------------------------------------------------------------------------

## 0. Evidence, labels, method

### 0.1 Labels
- **[M]** = measured. A `file:line` reference or a command with its output is given.
- **[D]** = a design value set by this concept. It is not a fact about the game.
- **[A]** = an assumption, stated as one.
- **[S]** = only Roblox Studio or a real iPhone can confirm it.

Coordinates are world studs. Ground `G = 24` (`CampusConfig.STREET_Y`, via `CityPlan.GROUND`,
`CityPlan.module.luau:26`). +X is east and **+Z is south**. Port Meridian lies far to the south (+Z).

### 0.2 Source state I relied on
- The colleague's audit `design/airports/audit/AUDIT.md` was re-checked where I rely on it. The audit snapshot is
  09:20 UTC. I compared it with live `work/src` at 10:14 UTC using `cmp` over all 167 files. Only these differ:
  ItineraryMath (4 lines), ItineraryService (61), ShuttleService (7) and ItineraryController (43). These are the
  running itinerary fix. Every geometry file is byte-identical to the snapshot: AirportBuilder, MetroBuilder,
  CityPlan, MetroPlan, FlightPlan, JetPlan, DrivePlan, CityBuilder and CityLifeController. **All `file:line`
  references below are to live `work/src`.**
- I ran these commands. They are read-only, used my own manifest in my work dir, and all exited with code 0:

| command (cwd `design/airports/concept_gameplay_work/`) | output (excerpt) |
|---|---|
| `python3 harness/make_manifest.py --src work/src --gen <work>/.gen` (from scratchpad) | `manifest: 181 entries, 167 scripts` |
| `../../../tools/luau probe_corridor.luau` | `PM_LINE 7544.0  far shells 279  interval 360` · `leg out PM 101 duration 208.3 boarding 75.5` · `leg back PM 102 duration 159.7 boarding 30.0` · TODAY `worst -62.0, shells within the hull reach: 8` · CORRIDOR A `removes 14 of 279 shells` → `worst 32.6, shells still within the hull reach: 0` (`probe_corridor_out.txt`) |
| `../../../tools/luau probe_points.luau` | `p320.length = 118.80`, `span = 113.20`, `height = 37.31`, `noseZ = -59.40`; `biz.length = 46.00`, `span = 41.60`; door tables `320 doorL1 (-6.24, 13.63, -41.26)`; `PM_STAND (252.0, 24.2, 7664.0) look (-1.00, 0.00)` (`probe_points_out.txt`) |
| `python3 walk_times.py` | walk lengths and times of every proposed route, plus floor areas (`walk_times_out.txt`, table in §3.1) |
| `python3 apicheck.py tools/API-Dump.json apis.txt` | `checked 61 missing 0` (`apicheck_out.txt`, Appendix B) |
| `python3 plans.py` | `plan_city_concept.png`, `plan_pm_concept.png` (I looked at both) |

### 0.3 What exists today and matters for gameplay [M]
- **Ticket.** `Shuttle.ticket` spends `CityPlan.TRAVEL.ticket` = $700 within 16 studs of a counter. The return flight
  is free (`ShuttleService.module.luau:323-353`, `CityPlan.module.luau:31`). The instant "charter" is a 10-s
  teleport from the counter that reuses that ticket (`CityService.module.luau:76-114`). It is offered when boarding
  is more than 180 s away (`FlightPlan.module.luau:50`).
- **Boarding.** You board within `GATE_RADIUS` 36 of the gate (`FlightPlan:224-230`). The character is then hidden
  and anchored under the stand (`ShuttleService:528-549`). Arrival pivots you to `AIRPORT.arrival` /
  `ABROAD.arrival` (`ShuttleService:594-617`). At PM the "gates" are the apron door, the hall centre and both
  counters (`FlightPlan:228`).
- **Jet bridges.** A1-A3 already carry a `BoardingPoint` part on the cab. It has attributes `Gate`, `Stand` and
  `AircraftDoor` (`AirportBuilder.module.luau:1491-1494`). Only A1 is animated, locally (`ShuttleGround.module.luau:1-14`).
- **Staff posts.** City staff posts `AirportPost` (attribute `CityPost`) exist at 13 call sites:
  check-in, info, security lanes, lounge, crew, shops, food, restaurant and gates (`AirportBuilder:274-276`,
  `:557`, `:679`, `:857`, `:964`, `:1046`, `:1065-1207`, `:1277`). No code reads them (audit 1.2).
- **Lounge tag.** The `BusinessLounge` tag and Purpose exist at City (`AirportBuilder:944-956`) and at PM. No code
  reads them either.
- **Company jet.** The company jet needs `Ops.JET = {price 900000, stage 4, ...}` (`CompanyOps.module.luau:118`).
  It is bought with `Ops.buyJet` (`CompanyOps:640-647`, `EmpireService.module.luau:501-502`). It parks in Hangar 1
  (`JetPlan.module.luau:81`). PM has 2 slots (`JetPlan:87-96`), so a 3rd jet gets `PM_STANDS_FULL`
  (`JetService.module.luau:505`). `JetService.summon` exists ("the jet picks you up", `JetService:554`). The jet
  folder publishes `Livery` (`JetService:222`).
- **Itinerary.** For a shuttle trip the itinerary books through `Shuttle.book`. It drives you to
  `airport_departures` and puts a GPS beacon on gate A1 (`ItineraryService:12-13`, `ItineraryMath.module.luau:754-763`).
  For a jet trip it calls `JetService.fly` **as soon as you reach the airport**, so you never see the hangar
  (`ItineraryService:783-800`, `tryJet` `:753-776`). The plan estimate for kerb → gate is `IM.WALK_GATE = 40` s
  (`ItineraryMath:35`).
- **Visiting clients.** Drivers already fetch a hosted client team "from their building / the arrivals kerb"
  (`DriverService.module.luau:63`, `:1102-1122`).
- **Who can see deals.** The client sees `deals.accounts`: EmpireApp reads it (`EmpireApp.module.luau:480`).
  Office stage is `Ops.stageIndex(e)` (`CompanyOps:192-194`). `e.jet` and `e.deals` are saved fields
  (`EmpireMath.module.luau:21`).
- **Remotes.** `TravelAction` is bound in CityService with a limit of `{burst=4, perSecond=.6}` and dispatches
  `flight|route|ticket|board|heli|status` (`CityService:188-201`). `Net` is frozen (GRANDHOTEL_SPEC 0.4).
- **Roblox Shop.** Passes exist: `vip` (cosmetic tag), `limo` (car + free heli) and `founderSuite` (cosmetic
  terrace) (`ShopConfig.module.luau:92-98`). **No airport perk in this concept is sold for Robux.** Lounges unlock
  by company progress only.

---------------------------------------------------------------------------------------------------------------------

## 1. Pitch and storyboard (what a 13-year-old experiences)

**First trip (stage 1-2, everyone).** You buy a ticket at a staffed counter and get a **boarding pass card**
("PM 101 · Gate A1 · Boarding 14:32 · Seat 3A"). You walk through security: a short scanner beep and a green light.
Airside there are interactive shops, the **SkyDeck** tower for plane spotting and a **kids' aviation corner**. When
the gate opens you walk the **jet bridge** to the aircraft door, press "Board" and you are aboard. In Port Meridian
you **walk off the bridge** into the Meridian Hall: "WELCOME TO PORT MERIDIAN · WHERE BUSINESS HAPPENS". Two
souvenir shops are only there.

**Startup Campus (stage 3).** The company is getting known. The airport says so: you get **Business status**. It
opens both Business Lounges (juice bar, snacks, your company's trip board), the **Fast Track** lane, and
**boarding straight from the lounge sofa**.

**Innovation Campus (stage 4).** Port Meridian clients unlock (Helix Research, CORE_SPEC 11.4). You can buy the
jet. Either one earns **Founder status**. That opens the **Meridian Founders Club** on the top floor of the PM
terminal (runway terrace, Deal Room, Wall of Founders, your souvenir shelf, private boarding), the
**Executive Jet & Heli Centre** and the **Private Terminal** at home. As a jet owner you also start upgrading
**Hangar 1** (lounge, livery studio, flagship hangar).

**Business trip (stage 4-5).** The assistant calls and you tap "Go". The driver drops you at the departures kerb,
or at the Private Terminal for jet trips. The banner guides you step by step: Fast Track ► Lounge (optional) ►
Gate A1 ► door. Your field rep and engineer walk with you, as they already do. In Port Meridian a **client host**
holds a sign with your company name in the Welcome Hall. The limo concierge sends you to the limo. On the way back
the Founders Club lets you board from the terrace.

What makes Port Meridian **better than City**:
- the Founders Club (the top lounge, exists only there);
- the Executive Jet & Heli Centre (exists only there);
- a two-level terminal with ~99k sq studs of floor, against City's ~64k (§3.1);
- the Welcome Hall with client hosts;
- the Business World Board and the 4 client souvenirs;
- a public SkyDeck over the gate.

City gets the Private Terminal, Hangar levels, the kids' corner and the SkyDeck tower landmark.

---------------------------------------------------------------------------------------------------------------------

## 2. Progression: Travel Status (derived, nothing new saved)

### 2.1 Rule (pure function, `AirportPlan.tier(e, booking)`)
| Tier | Rule [D] | Data source [M] |
|---|---|---|
| 0 Traveller | everyone | – |
| 1 **Business** | `Ops.stageIndex(e) >= 3`, **or** the player holds a company booking (itinerary: `Shuttle.booking(player) ~= nil`) | `CompanyOps:192`, `ShuttleService:425` |
| 2 **Founder** | `stageIndex >= 5`, **or** (`stageIndex >= 4` **and** (`e.jet == true` **or** an active account whose `client.trip == "abroad"`)) | `e.jet` (`EmpireMath:21`), `e.deals.accounts` + `Ops.client(id).trip` (`CompanyOps:139-142`, `:844-880`) |

- Server side, `AirportService` computes the tier at login, on every office or jet change, and once per 1 Hz tick
  while the player is inside an airport region. It publishes Player attribute `TravelTier` (0/1/2) **only when the
  value changes**.
- Every perk that matters is checked **on the server** against that function, never against the attribute.
- Founder status that comes from an abroad account lasts while the account is active. Accounts can lapse at
  `CompanyOps:880`. That is honest: "Founder access while you have a Port Meridian client".
- The tier never changes money, income or trust. Its only effects are access and convenience.

### 2.2 What each office stage gets at the airports
| Stage (CORE_SPEC 2.1) | Tier | City Airport | Port Meridian Airport |
|---|---|---|---|
| 1 Garage Lab, 2 Founder HQ | Traveller | ticket, boarding pass, security, shops, food, SkyDeck tower, kids' corner, walk-on boarding at A1, A3 charter gate | arrivals Welcome Hall, shops (2 PM-only), Café, public SkyDeck, gate M1 bridge, M2 charter, Business World Board ("locked" rows) |
| 3 Startup Campus | Business | + Business Lounge (refit), Fast Track lane, board from the lounge | + Business Lounge (rebuilt), Fast Track, board from the lounge |
| 4 Innovation Campus | Business; **Founder** with a PM client or the jet | + Private Terminal (jet owners); Hangar levels H1-H3 (jet owners, §3.4) | + **Meridian Founders Club**, Executive Jet & Heli Centre lounge, private boarding from the club, client souvenirs |
| 5 Global AI HQ | Founder | all | all |

---------------------------------------------------------------------------------------------------------------------

## 3. Gameplay systems

### 3.1 The Journey (both airports, same grammar)

`kerb → check-in (staffed; skipped with a booking) → security (lane FX; Fast Track for Business+) → airside
(shops / food / lounge / SkyDeck) → gate → jet bridge → aircraft door "Board"`.
Arrival runs the same route the other way: door → bridge → one-way **Arrivals** door → landside → kerb, driver or
limo.

Walk lengths come from `walk_times.py`. They assume WalkSpeed 16 [A]: the game never sets the player's WalkSpeed,
and `grep WalkSpeed work/src` hits only NPC code [M]. The Roblox default of 16 is assumed.

| route | studs | s | constraint it must fit [M] |
|---|---|---|---|
| City departure: departures door → counter → security → A1 cab | 409 | 25.5 | `IM.WALK_GATE` 40 s (`ItineraryMath:35`); home boarding 75.5 s (probe) |
| City departure with a company booking (no counter) | 383 | 23.9 | same |
| City arrival walk-off: A1 cab → **west** arrivals door → kerb x -150 | 189 | 11.8 | itinerary `DEBOARD_WAIT` 20 s before the driver is called (`ItineraryMath:49`) |
| City jet: `airport_private` kerb → Private Terminal → jet airstair | 307 | 19.2 | none (jet waits; `maxDelay` 240, `JetPlan:44`) |
| PM departure: `pm_airport` door → counter → security → M1 cab | 354 | 22.1 | PM boarding is only **30 s** (probe), so players wait at the gate. The ticket stays valid "for the next departures until used" (`ShuttleService:14-16`). Lounges let you board from the sofa (§3.3) |
| PM arrival walk-off: M1 cab → Welcome Hall → limo stand | 268 | 16.7 | `DEBOARD_WAIT` 20 s |
| PM jet: `pm_jetcentre` kerb → Jet Centre → slot 3 / slot 1 airstair | 269 / 212 | 16.8 / 13.2 | none |

Server and client split:
- **Server-authoritative:** ticket, board (zones by tier), arrival placement, charter, shop purchases, souvenirs and
  hangar purchases.
- **Client-only, no effect on the server:** scanner FX, door visuals, staff rigs, spotter card and boarding-pass
  card.

### 3.2 Boarding and arrival (the core change)
1. **Walk-on boarding (both airports).** During `boarding`, `Shuttle.board` also accepts a player within
   `AirportPlan.BOARD_DOOR_RADIUS = 8` [D] of the departure stand's `BoardingPoint`. That point is the bridge cab at
   the aircraft door:
   - A1 door L1 world ≈ (-206.2, 37.9, 2570.7) [M: AircraftModel `320 doorL1 (-6.24, 13.63, -41.26)` × stand
     (-200, 24.25, 2612) nose north];
   - PM1 door L1 ≈ (210.7, 37.9, 7670.2) [M: same door × `PM_STAND` (252, 24.2, 7664) facing -X].

   The prompt "Board PM 101" sits on the BoardingPoint. The hold, cutscene and ride stay exactly as today
   (`ShuttleService:528-549`), so the character "steps into the plane" at the door.
   - Auto-board at the end of boarding keeps `GATE_RADIUS` 36 around the gate points.
   - The client moves anyone still standing in a bridge **without** boarding back to the gate desk before the bridge
     retracts. It moves only its own character (`AirportController`).
2. **Walk-off arrival.** Arrival happens at `deboarding.t0 + FP.BRIDGE.time + 0.5` = 4.5 s into the 10-s deboarding
   phase. By then the bridge has docked (`FP.BRIDGE = {angle 5°, retract 4, time 4}`, `FlightPlan:298`).
   - The character is placed at `AirportPlan.GATE_ARRIVAL[dir]`: the bridge cab, facing along the bridge towards
     the terminal.
   - The server still moves the character exactly 3 times: board, mid-cruise, arrival (`ShuttleService:22-26`).
   - `CityPlan.AIRPORT.arrival` (250, 28, 2450) **stays**. The charter and GuestPlan arrivals still use it, and today
     the jet does too.
3. **Charter gets a gate.** Gate A3 at City and desk M2 at PM become **CHARTER** gates.
   - The counter sells or holds the same ticket as today, so the price logic is unchanged (`CityService:89-91`).
   - `City.flight` also accepts the charter gate point (A3 `BoardingPoint`, or the M2 desk at (100, 28, 7616)) when
     the flags are on. The 10-s cutscene stays.
   - Effect: 2 of 3 City gates are usable instead of 1 ("GATE CLOSED", `AirportBuilder:1247`).
4. **A2 "Spotter bridge"** [D, cut-able]. The A2 bridge opens for walking to a viewing window at the parked airliner.
   It has no boarding and an honest sign.
5. **Flags.** `AirportPlan.CITY_JOURNEY` and `AirportPlan.PM_V2` default to `false`. With a flag off, everything
   above falls back to today's behaviour. Integrate flips them at the joint verify (§9).
   - The flags gate geometry and data too. AirportBuilder builds the refit only under `CITY_JOURNEY`. MetroBuilder
     calls PMAirportBuilder (otherwise today's `airport()` / `lounge()` / `plaza()`) and the PM values of
     `CityPlan.ABROAD`, `MetroPlan.LOUNGE`, pmPaths and JetPlan slots apply only under `PM_V2`. The values are chosen
     at require time.
   - Each package's own suites run with its flag forced on, plus one run with it off. The off run must be
     byte-identical to today's world dump.

### 3.3 Lounges

| Lounge | Where | Access (server rule for perks; the door opens locally) | Content | Perks (none touch money) |
|---|---|---|---|---|
| **Business Lounge, City** | existing rect x -298.5..-238, z 2485.5..2529.2, door (-238.6, 27.5, 2502.5) (`CityPlan:363-364`) | Business+ | refit: bottle shelf → **juice and smoothie bar**; buffet; work pods; "Your trips" board (`deals.tripList`: who of your staff travels now); window bar at the apron | **board from the lounge**: `Shuttle.board` accepts the lounge rect for Business+ during the out boarding; free smoothie held item; quiet seats |
| **Business Lounge, PM** | x -318.5..-210, z 7610.8..7684 (new `MetroPlan.LOUNGE`) | Business+ | juice bar ("THE MERIDIAN JUICE BAR"), sofas with **>= 8 real `Seat`s** (test `test_build.luau:57-61`), work pods, buffet, flight screen | board from the lounge (back leg) |
| **Meridian Founders Club** (the founder lounge) | PM level 2, x -318..-90, z 7612..7690, floor G+16.5; stair x -205..-185, z 7662..7682 (airside) | Founder | host desk (greets with company name and stage); runway **terrace** (glass balustrade, 3 telescopes); juice bar + chef's buffet; **Deal Room** (8-seat glass room whose screen shows your live PM deals from `deals.accounts`); **Wall of Founders** (founders on this server: company name + stage, §6.4); **your souvenir shelf** (dressed locally); flight-deck seat (sitting switches the camera to a live runway view, like the CCTV world camera in `SecurityController.module.luau:2-4`); 4 nap pods | **private boarding** (the club rect is a board zone for Founder); **"Call our jet"** button for jet owners → existing `JetService.summon` (`JetService:554`) |
| **Hangar Lounge** | Hangar 1 (x -1000..-840, z 2560..2720), H1 upgrade, drawn locally per viewer | jet owner with H1 | glass lounge box facing your jet; the pilots greet you; trip board | waiting room before jet trips; companions wait here |
| **Executive Jet & Heli Centre lounge** | PM x 556..700, z 7708..7748 | Founder or jet owner | concierge (limo via the existing VIP limo service, which is free); heli waiting room. The heli arrival spot (576, 27.5, 7714) is inside and stays free (`ShuttleService:647-655` formula) | walk-out to your jet; heli arrivals land you in the VIP lounge |

**Door technique** [A][S]. Each lounge door is a glass panel that collides on the server. The client of an eligible
player sets `CanCollide = false` on it locally, so that player walks through. This is a common Roblox "VIP door"
pattern because the client simulates its own character. An exploiter can still walk in, but gains nothing: every
perk is validated on the server. A host NPC greets eligible players. Ineligible players see a friendly toast:
"Business status opens at Startup Campus. Keep growing!"

### 3.4 The company jet: Private Terminal, Hangar levels, Jet Centre
- **Private Terminal** (City, new Atomic model): x -836..-776, z 2470..2526, at the car park's south-west corner.
  - It does not touch the hangar (x <= -840) or the bays (x -355..-425, `CityPlan:366-368`).
  - The kerb place `airport_private` stops at (-806, RT, 2394) on Airport Road's eastbound lane, with the door on
    the south sidewalk at (-806, WT+3, 2405) [D; the drivers package confirms the lane].
  - Route: north door, then the airside door south (z 2526), then the hangar apron, then the jet's airstair.
- **Hangar levels** (jet owners). Each owner sees **their own** level in the shared hangar, the same way JetController
  already shows only the local company's jet (`JetService:46-48`).
  - **H1 Hangar Lounge.** The lounge box from §3.3.
  - **H2 Livery Studio.** Pick a livery *pattern*: stripe, two-tone or chevron. The new attribute `LiveryPattern`
    sits next to `Livery` (`JetService:222`), and everyone sees it at PM. Colours stay with the Identity Kit pass
    (`ShopConfig:101-102`); a pattern is not a colour.
  - **H3 Flagship Hangar** (stage 5). Logo floor, a door light show at tow-in, a "Flagship" fin badge and a
    countdown board.
  - All three are cosmetic or comfort only.
  - **Owner decision O-1:** buy them with cash or unlock them by progress (§12.3).
    - *Cash option* (CORE_SPEC 10.3 risk 3 says the late game lacks money sinks): `Ops.HANGAR` prices
      H1 $150,000 / H2 $300,000 / H3 $600,000 [D]. H1 copies the spec-only $150k cosmetic precedent of CORE_SPEC
      10.3 (guest-house suites). H2 and H3 are 1/3 and 2/3 of `JET.price`. The economy simulator
      (`agents/logic_understand/economy/sim.luau`) must run before shipping.
    - *Progress option:* H1 when the jet is bought, H2 at `deals.jetFlights >= 5` [D], H3 at stage 5.
- **Port Meridian Jet & Heli Centre and 3 jet slots** (today there are 2).
  - Slot 1 "VIP apron" (600, AY, 7612) does not change.
  - Slot 2 moves (480, 7664) → **(460, AY, 7676)**.
  - New **slot 3 (460, AY, 7618)**.
  - All slots park nose west. Arrival lane x 520, departure lane west to x 405 then north, roll from x 355 [D].
  - Gaps: slot-2 arrival wingtip to slot-3 tail ≈ 16 studs; slot-2 departure wingtip to slot-3 nose ≈ 11 studs.
    Bizjet dimensions: length 46, span 41.6, nose -22.6 and tail +23 from the pivot [M probe_points].
  - Needs a new JetPlan field window **"pmapron"** (x 300..560, z 7590..7725). It separates jets on the east apron
    from the shuttle's taxi line x 340. This uses the same mechanism as the existing home "apron" field (audit 4.4).
  - Slot 3 needs the PM2 decorative airliner retired (330 parts, `MetroBuilder:206-228`; owner decision O-3).
  - `PM_STANDS_FULL` then appears at the **4th** jet in PM at the same time, not the 3rd.
  - Optional AP1b item: "drop & go". When all slots are full, the jet deboards you and ferries home empty (the
    existing `ferry` kind).
- **Display jets** (client-only, cut-able). A free PM slot shows a decorative "Meridian Executive Charter" bizjet
  drawn locally. It hides when a real jet is assigned, using the same hide mechanism as `hiddenDecor` today
  (`JetController.module.luau:62`, `:398-423`).
- **Walk-off for jets.** `JetPlan.arrivalSpots` puts the founder at the airstair foot (`slot.exit[1]`) at PM, and in
  front of Hangar 1 at home (HOME_STAND area). Today it uses the limo stand at PM (`JetPlan:101`) and City arrivals
  at home.

### 3.5 Business trips (ItineraryService), step by step
| Step | Today [M] | Concept | Change (file, package) |
|---|---|---|---|
| Call / plan | assistant call; `IM.plan` with `WALK_GATE` 40 | unchanged; adds `IM.WALK_GATE_PM = 25`, `IM.WALK_PRIVATE = 20` [D, from §3.1] | ItineraryMath (AP1a) |
| Drive out (shuttle) | driver → `airport_departures` (66, RT, 2413.5) (`DrivePlan:341`) | unchanged | – |
| Airport (shuttle) | GPS beacon to gate A1 (`ItineraryService:277-280`) | banner steps "Fast Track ► Lounge (optional) ► Gate A1 ► door". GPS chevrons follow the terminal walk graph (`CityPlan.AIRPORT.walk`, `CityPlan:527`). A booking = Business tier, so Fast Track and board from the lounge both work | ItineraryController + `AirportPlan.route` (AP1a) |
| Airport (jet) | `tryJet` at the departures kerb, so you are held at once (`ItineraryService:783-800`) | driver → **`airport_private`**. New sub `"private"`: GPS to the jet airstair; the itinerary's own owner-only prompt "Board our jet" there → `tryJet` (no `pay`, so the economy is unchanged) | ItineraryService, DrivePlan (AP1a) |
| Arrive PM (shuttle) | teleport into the hall (0, 28, 7655) | walk off the M1 bridge. A **client host** with a "<Company>" sign stands in the Welcome Hall while the player's `Itinerary` attribute is in the flight or deboard state (`ItineraryService:31-32`). The host is drawn locally by AirportPeopleController, with no itinerary edit | AP4 |
| Limo | `pm_limo` (176, RT, 7762) | unchanged (exit door x 40 → 136 studs along the canopy) | – |
| Return (shuttle) | limo → `pm_airport` (-75, RT, 7772.6), gate = `FP.PM_GATES[1]` | unchanged code. The new `PM_GATES[1]` is the M1 gate door inside point (148, 28, 7690), and Business+ can board from the lounge or club | FlightPlan (AP1a) |
| Return (jet) | `tryJet` in Port Meridian | limo → **`pm_jetcentre`** (628, RT, 7772.6) → Jet Centre → airstair prompt → `tryJet` | ItineraryService, DrivePlan (AP1a) |
| Home | driver from `airport_arrivals` (300, RT, 2413.5) | `airport_arrivals` moves to **(-150, RT, 2413.5)**, at the west arrivals exit, when `CITY_JOURNEY` is on | DrivePlan (AP1a) |

The economy trip is never touched (`ItineraryService:23-26`). The new steps are as optional as the old ones: if you
leave the route, GPS or beacon fallback applies.

### 3.6 People travelling (staff, field staff, clients, crowd)
- **Airport staff** (client-drawn, deterministic). The technique copies GRANDHOTEL_SPEC §14.1: `EmployeeRigDesign`
  templates are built once into ReplicatedStorage (not workspace), clients clone them, and poses come from
  `EmployeeController.pose`. The pose list includes `type`, `greet`, `scan`, `inspect`, `pour` and `present`
  (GRANDHOTEL_SPEC 0.3). Uniform features include `vest`, `cap`, `tie` and `hivis` (same source).
  - **City.** They stand on the existing 13 `AirportPost` call sites: check-in agents (type), security (scan), lounge
    host (greet), shop clerks, food stalls, restaurant host and gate agents (greet).
  - **PM.** About 18 new posts [D] (Appendix A): check-in 3, travel desk 1, security 3, gates M1/M2 2, lounge host 1,
    club host 1, juice bars 2, shops 3, limo concierge 1, Jet Centre concierge 1.
  - Shifts follow the company clock: day 08-18 full; at night 1 security, 1 check-in and 1 gate agent per airport.
    The clock is `Ops.hour`; StaffService writes `Lighting.ClockTime` (GRANDHOTEL_SPEC 0.3, critic row).
  - **At most 8 staff rigs drawn** per client, nearest first.
- **Your own people.** The field rep and engineer already fly as shuttle Passengers (`ShuttleService:29-37`). The
  gate board adds the line "with Mia (Growth & Sales) from <Company>". It reads the existing Passenger attributes
  `PassengerName` and `Company`.
- **Visiting clients.** For a hosted visit the driver already fetches the client team at the arrivals kerb
  (`DriverService:1102-1122`). City arrivals show them walking out with a name board, "<Client> visiting <Company>"
  (GuestPlan arrival passengers, AP4).
- **Crowd.** City keeps CityLife's 30 walkers (`CityLifeController:44`) and up to 40 passengers
  (`GuestController:32`, audit 1.6). PM adds a CityLife region `pmairport` with **20 walkers** [D] on a new terminal
  walk net. Today PM has only passengers inside (audit 2.5.7).

### 3.7 Shops, souvenirs and things to do (no gambling)
**Hard rules.**
- Every purchase is deterministic.
- No random items, loot boxes, mystery packs, claw or slot machines, scratch cards or lucky draws.
- No alcohol: no bar, wine or bottle imagery. Use "juice bar" and "smoothies".
- Nothing is sold for Robux.

| Shop (City, airside band `AirportBuilder:1065-1132` posts) | Items (held item + souvenir) |
|---|---|
| News & Books | "Read & Fly" magazine (held), **City Airport postcard** (souvenir) |
| Bakery Café | smoothie / hot chocolate (held cup); **Founder's travel mug** (souvenir, Business+) |
| Gadget Gate (tech) | **model PM 101 shuttle** (souvenir, held) |
| Gifts & Sweets (ex duty free, already "fragrance · watches · sweets", `AirportBuilder:1124`) | **Sky Sweets box** (souvenir) |
| SkyDeck spotter shop | **SkyDeck pin**, free after the City spotter card |
| Private Terminal | **Hangar patch**, free for jet owners |

| Shop (PM airside) | Items |
|---|---|
| Meridian Market (fragrance, watches, sweets) | **Meridian sweets tin** |
| Spire Souvenirs | **Meridian Spire snow globe** (held) |
| Robo Store (AI gadgets, fits the fantasy) | **Robo buddy figurine** (held) |
| Founders Club juice bar | **Meridian Juice cup** (Founder) |
| Business World Board (Meridian Hall) | **client gifts**, free while or after you hold that account: Helix Research mug (`helix`), Orbit Systems pin (`frontier`), Nova Infrastructure cap (`nova`), Frontier Science rocket (`science`) (ids `CompanyOps:139-142`) |
| Public SkyDeck | **Spotter badge**, free after both spotter cards |

- **Purchase.** The channel is `TravelAction {action="airport", op="buy", item}`, dispatched by CityService to
  `AirportService.buy`. The server checks:
  - within 14 studs of that shop's counter part;
  - tier, if the item needs one;
  - price from **`Ops.TRAVEL_SHOP`** (CompanyOps) [D]: held snacks $25, toys $150, souvenirs $400; client gifts and
    badges $0;
  - `Economy.spend(s, price, "travel")`, the same P&L line as the ticket (`ShuttleService:346`);
  - rate limit from the existing `TravelAction` limiter.
  - Economy effect: buying the whole set costs about $3k, against the $27k stage-2 price (CORE_SPEC 2.1).
    Negligible. Owner decision O-2 can make everything complimentary.
- **Held item.**
  - One at a time, welded to the right hand on the server with `WeldConstraint`.
  - `CanCollide/CanTouch/CanQuery = false`, `Massless = true`.
  - Removed on death or leave, and hidden while seated or flying.
  - These rules copy SHOP_SPEC 3.10 (Robo Buddy).
- **Souvenir collection** (saved as an addition). `empire.souvenirs`: at most 16 known ids, deduplicated, cleaned in
  `Template.migrate`, defaulted in `EmpireMath.new`. **DATA_VERSION stays 6.** It is shown on the Founders Club
  shelf and in a "Souvenirs" sheet opened at that shelf, or from the boarding-pass card. It is the long collection
  goal for kids, and PM holds the late-game pieces.
- **Spotter cards** (client only, nothing saved, no reward). Modelled on the hotel's spa mini-quest
  (GRANDHOTEL_SPEC 9.4).
  - City: spot the shuttle take-off, the shuttle landing, an ambient arrival, an ambient departure, a sky crossing
    and a company jet. Sources: `ReplicatedStorage.Shuttle` phases (`ShuttleService:4-9`), `FlightPlan.ambient`
    (AirTrafficController, `:3-9`) and `CompanyJets` folders (`JetService:42-45`).
  - PM: shuttle landing, shuttle take-off, heli lift-off (`HeliStart`), company jet landing.
  - Completing a card unlocks its free souvenir through the server. The server checks only that the claim happens at
    the SkyDeck, so a cheat gains one free souvenir.
- **SkyDeck City** (public tower, the landmark).
  - Footprint x 312..352, z 2436..2476. Open deck floor at G+50 [D], so it looks over the roof crown at G+40
    (audit 1.1).
  - Ground floor holds the **"Little Pilots"** kids' corner: a mini plane with real `Seat`s, a slide, and a luggage
    belt that kids ride (a moving walkway). It also holds the spotter shop.
  - Glass lift (LiftLogic, the HQ and hotel lift logic, GRANDHOTEL_SPEC 13) plus a stair. Telescopes and a live
    "What's flying" board.
- **SkyDeck PM** (public). Level 2, x -60..150, z 7612..7660, above the café and gate lounge. It faces the runway
  and stand M1.
- **Business World Board** (PM Meridian Hall, landside). The 4 PM clients, with this player's status per client:
  "Signed · next check-in in 2 days" / "Trip under way" / "Locked: reach Innovation Campus". Data comes from
  `deals.accounts` on the client (`EmpireApp:480`). It is the "reward destination" goal board.
- **Photo spot.** "I'm in Port Meridian" frame in the Welcome Hall, with a client camera preset. A smaller
  "City Airport" frame stands at the SkyDeck.
- **Moving walkways.** Anchored parts with `AssemblyLinearVelocity` set (conveyor) [A][S]. There is no player speed
  anti-cheat in the tree [M: grep `speedhack|SpeedCheck|anticheat|MAX_SPEED` returns nothing].

### 3.8 Fixes this concept includes
| Weakness (audit) | Fix |
|---|---|
| W10 kid-friendly | PM "THE MERIDIAN BAR" + `Bottles` (`MetroBuilder:368-370`) → "THE MERIDIAN JUICE BAR" with fruit and juice dispensers. City lounge bottle shelf (`AirportBuilder:966`) and restaurant bar bottle shelf (`AirportBuilder:1196-1198`) → coffee, juice and fruit shelves. Test: no part named `Bottles`, and no label containing "BAR" except "JUICE BAR". *Outside the airport scope, but in a file AP3 owns:* shop name "WINE CELLAR" in `MetroBuilder:72` → e.g. "TEA HOUSE" (AP3 renames it) |
| W3 fake flight "PM 104" | PM boards become `FlightInfoBoard`-tagged and are filled live by ShuttleGround (`ShuttleGround:11-13`). No literal flight numbers |
| W2 planes through buildings | new `FAR_CLEAR` rect x -2700..-640, z 7454..7634 (= PM_LINE ± 90). **Measured:** it removes 14 of 279 shells, and the minimum clearance becomes +32.6 studs beyond a 62-stud hull reach for the shuttle and +68.6 for the jet. Today it is -62, i.e. inside (`probe_corridor_out.txt`). The hard-coded z comes from `CityPlan.ABROAD.runway`, because MetroPlan cannot require FlightPlan (FlightPlan requires MetroPlan, `FlightPlan:33`). The probe becomes a regression test (`tests/flight/far_corridor.luau`) |
| W4 never walk to the plane | §3.2 |
| W6 no staff, decor lounges | §3.3, §3.6 |
| W7 cramped PM / 2 jet slots | 3 slots + Jet Centre (§3.4). The 70-wide runway and the 11-stud `PM_LINE` offset (`FlightPlan:211-216`) **stay**: this concept does not move any runway (honest limit, §12) |
| W8 flat City box | Gateway canopy x -180..180 over the kerb, SkyDeck tower, apron life (display jets, A2 spotter bridge) |
| W9 no lights | no new real light. Existing ones are redistributed; neon, `MetroNightGlow` (PM) and at most 3 client lights per airport (§7.2) |
| W11 heli lobby | handled by GRANDHOTEL_SPEC 18.3 (roof arrival). The airport side lands you in the Jet Centre VIP lounge |
| W5 short flight | **not changed.** The 368-s cycle and FlightPlan tracks stay. The airports add 20-40 s of real airport time each way. The cabin package (still open, `notes_integration.md:156`) can extend the ride |

---------------------------------------------------------------------------------------------------------------------

## 4. Layouts with coordinates (plan view)

Plans: `design/airports/concept_gameplay_work/plan_city_concept.png` (zone and terminal close-up) and
`design/airports/concept_gameplay_work/plan_pm_concept.png` (PM level 1). Grey = today, colour = proposal.

### 4.1 City Airport (runway, taxiway, stands, hangar shell and tower unchanged)
```
 z 2360..2400  Airport Road (CityPlan:69)   ● airport_private kerb (-806,2394)            ● departures (66,2413.5)
 z 2400..2418  drop-off lane x -330..330    ● airport_arrivals NEW (-150,2413.5) [was (300,2413.5)]
 z 2404..2430  GATEWAY canopy x -180..180 (over kerb + doors x -150/0/150)
 z 2430..2530  TERMINAL x -300..300 (shell unchanged)              | SKYDECK tower x 312..352, z 2436..2476, link x 300..312
   landside z 2431..2484: islands A-D (counters x -225/-75/75/225), info, arrivals carousel x 246..298 (kept)
   security z 2452..2498: lanes x -60 = FAST TRACK (Business+), 0, 60
   airside  z 2485..2529: LOUNGE x -298.5..-238 | crew x -238..-214 | shops x -214..168 (ARRIVALS one-way corridor
            x -156..-144, door in the security wall at x -150) | food court x 168..298.5 | gates A1 -200 / A2 0 / A3 200
 z 2530..2575  jet bridges; A1 BoardingPoint ≈ (-206,38,2571); A3 = CHARTER gate; A2 = spotter bridge (optional)
 x -836..-776, z 2470..2526  PRIVATE TERMINAL (jet owners) → hangar apron → Hangar 1 x -1000..-840, z 2560..2720
```
| Element | Rect / point [D unless marked] | Notes |
|---|---|---|
| Gateway canopy | x -180..180, z 2404..2430, underside >= G+14 | over the drop-off lane (x -330..330, z 2400..2418) and the forecourt |
| Fast Track lane | x -66..-54, z 2452..2498 (lane x -60, `CityPlan:339`) | local-collision barrier for Traveller |
| Arrivals corridor | x -156..-144, z 2485..2504; one-way door in the security wall (z 2485) | the café in the shops band loses 12 studs; the facade door x -150 exists (`CityPlan:337`) |
| Lounge board zone | `CityPlan.AIRPORT.lounge` rect, y 24..38 | Business+ |
| Charter gate | A3 `BoardingPoint` (existing) | sign "A3 · CHARTER · INSTANT FLIGHT" replaces "GATE CLOSED" |
| SkyDeck | tower x 312..352, z 2436..2476, deck floor G+50, roof G+62; link x 300..312, z 2442..2458 | landside, public |
| Private Terminal | x -836..-776, z 2470..2526 | Atomic; doors N (car park) and S (airside) |
| Hangar levels | inside Hangar 1, client-drawn | per viewer |
| Decorative `PrivateJet` | 320 @ 0.9 (`AirportBuilder:1930`) → AircraftModel `bizjet` | fixes "shrunken airliner" (W8) |

### 4.2 Port Meridian Airport (runway, PM_LINE, stand PM1, taxi line x 340 and heliport unchanged)
```
 z 7520..7590  RUNWAY x -650..650 (CityPlan:533), FP.PM_LINE z 7544 (FlightPlan:215)
 z 7592..7605  keep-out for x < 400: nothing above 0.5 (the shuttle half span 56.6 reaches z 7601)
 z 7610..7748  MERIDIAN HALL x -320..160 (2 levels, height 34; replaces the old hall x -160..160, z 7610..7690)
   L1 airside N   x -320..60,  z 7612..7684: BUSINESS LOUNGE x -318.5..-210 | shops x -210..-40 | Café x -40..60
   L1 security    x -320..60,  z 7684..7692: lanes x -40 FAST TRACK / 0 / 40
   L1 landside    x -320..60,  z 7692..7746: Gallery x -318..-210 | CHECK-IN x -150/-110/-70 @ z 7712, desk x -190 |
                                             WELCOME HALL x -40..60 (client host, LED wall, limo concierge)
   L1 airside E   x 60..158,   z 7612..7746: GATE LOUNGE (M1 desk (130,7676), M2 charter desk (100,7616)),
                                             arrivals corridor → one-way door at x 60, z 7716..7728
   L2 (G+16.5)    FOUNDERS CLUB x -318..-90, z 7612..7690 (terrace z 7612..7624) | SKYDECK x -60..150, z 7612..7660
 x 160, z 7684..7696  M1 gate door → JetBridge_M1: rotunda (180,24.5,7690) → cab at door L1 ≈ (210.7,37.9,7670.2)
 x 160, z 7655..7667  ApronDoor (kept: crew and NPC passengers, test_build.luau:93-102)
 x 160..548, z 7590..7721.5  apron (MetroPlan:151-158): PM1 shuttle (252,7664); jet slot 2 (460,7676); slot 3 NEW (460,7618)
 (600,7612) jet slot 1 VIP apron · (604,25,7670) heliport (MetroPlan:134)
 x 556..700, z 7708..7748  EXECUTIVE JET & HELI CENTRE (absorbs the VIP heli terminal x 649..690, z 7666..7709, MetroPlan:976)
 z 7748..7766  kerb canopy x -320..200, entrances x -200 / -80 / 40;  limo lay-by x 104..200 (MetroPlan:138-143)
 z 7768..7800  Arrivals Drive (MetroPlan:76): pm_airport (-75,7772.6) · pm_limo (176,7762) · pm_jetcentre NEW (628,7772.6)
 x -694..-340, z 7632..7716  airport lots block (was x -694..-214, MetroPlan:256)
```
| Element | Value [D] | Ripple |
|---|---|---|
| `CityPlan.ABROAD.terminal` | {x1=-320, x2=160, z1=7610, z2=7748}, height 34 | x2 stays 160, so `MetroPlan.APRON` rects and door (`MetroPlan:151-158`) stay valid. Follows automatically: `IM.inPMAirport` (`ItineraryMath:765-768`), `GuestPlan.TERMINALS.pm` (`GuestPlan:801-803`), `Drive.PM_STAND_AREA` (`DrivePlan:499`) |
| `CityPlan.ABROAD.entrances` | {-200, -80, 40} | `pm_airport` door (-80, 7757) is unchanged (`DrivePlan:409-411`); MetroPlan portals move from z 7695 to z 7752 (`MetroPlan:1040`) |
| `CityPlan.ABROAD.checkin` | (-150 / -110 / -70, G, 7712) | `Shuttle.ticket` reads it (`ShuttleService:335`); no longer a board point |
| `CityPlan.ABROAD.arrival` | lookAt((-20, 28, 7722) → south) | charter arrival lands in the Welcome Hall (landside) |
| `CityPlan.ABROAD.plaza` | {x1=-320, x2=200, z1=7748, z2=7768} | the kerb canopy strip |
| `MetroPlan.LOUNGE` | {x1=-318.5, x2=-210, z1=7610.8, z2=7684, doorZ1=7644, doorZ2=7656} (door on the x2 side) | today it is derived from `terminal.z1/z2` (`MetroPlan:145`), which would cross the security line; rewritten |
| `FP.PM_GATES` (PM_V2) | {(148, 28, 7690) gate-door inside point, (130, 28, 7676) M1 desk}, radius 36 | it covers x 94..184, so never the landside (x <= 60); the hall centre and counters are dropped (`FlightPlan:228`) |
| JetBridge_M1 | link from the gate door to the rotunda (180, 24.5, 7690); telescoping tunnel to the cab 0.6 off the fuselage at door L1 | rotunda is outside every PM1 hull band (fuselage band x 192..318, z 7644..7684, `test_build.luau:106-125`, bands at :111); the cab is inside, so it is exempt like the docked A1 bridge and checked at 0.25 (clearance.py) |
| Jet Centre | x 556..700, z 7708..7748, roof <= G+18 | north face is 2.4 studs south of the heliport fence at z 7705.6 (`MetroPlan:976`) and 38 from the pad centre (rotor r 16.4); it replaces the VIP heli terminal box x 649..690, z 7666..7709 (same line); the heli climbs south-west from (604, 55, 7670) towards (302, 133, 7730) (`FlightPlan:630-641`), so it crosses z 7708 west of x 556 |
| District walk | z 7728 re-routed to z 7752 for x -330..200 and x 550..690; the heliport-gate path ends at the Jet Centre west door | `pmPaths` (`MetroPlan:988-998`) |
| District trees | trees inside x -330..-246 removed | `MetroPlan:863-868` |

### 4.3 No overlap with the Meridian Grand (GRANDHOTEL_SPEC)
| Resource | Meridian Grand uses (GRANDHOTEL_SPEC) | This concept uses | Distance / split |
|---|---|---|---|
| Ground | hotel x -70..70, z 8380..8500 (§0.2); drive and porch x -54..54, z 8360..8380, mouths z 8352..8360 (§6.1); lift tower x 70..95, z 8370..8510 (§13) | Airport District only: x -320..160, z 7610..7766; x 556..700, z 7708..7748; apron and heliport (existing); kerb places on Arrivals Drive | closest pair: terminal canopy z 7766 vs hotel drive mouths z 8352 = **586 studs** |
| Air | roof pad (0, 151.2, 8408), rotor r 16.4, approach along x = 0 at roof + 60 (§11) | the airport pad is unchanged; airport roofs <= G+38 (terminal) and <= G+18 (Jet Centre). The heli passes over the airport district at >= 55 studs and climbs towards y 211 | heli sweep re-run (§10) |
| Part budget | `Hotel_intl_hotel` models, cap 3,250; metro test counts the hotel frozen at 78 (§19.1) | own models `PMTerminal/*`, `PMJetCentre`, caps 4,080 total, excluded from the metro count **the same way** | separate caps |
| Real lights | hotel exactly 3 (§19.2) | airport keeps its own 9 (today: terminal 5 + heliport 1 + plaza 3, audit 2.4), redistributed | PM total stays 40/40 |
| Client lights | hotel <= 3 (§19.2) | airport <= 3, created only while the camera is in an airport region | never at the same time (770+ studs apart) |
| `MetroNightGlow` | hotel ~295, PM ~493 after the hotel (§19.3) | airport <= 120 → PM <= 613 | – |
| Files | A edits MetroPlan, MetroBuilder, DrivePlan, CityLifeController; B edits ShuttleService, PhoneService, ItineraryService (§21) | edited **after** the hotel joint verify, on the post-hotel version, additively; hotel suites re-run as a gate (§9) | sequential |

---------------------------------------------------------------------------------------------------------------------

## 5. Every existing flow: what stays, what changes, where
| Flow | Stays | Changes | File(s) | Package | Test gate |
|---|---|---|---|---|---|
| Shuttle timetable and paths | all FlightPlan tracks, `PM_LINE` 7544, stands A1 / PM1, taxi x 340, 368-s cycle, ambient slots | none | – | – | `tests/flight/run.sh` 341 + clearance 18 must still pass |
| Shuttle boarding | hold / stream / ride, auto-board radius 36 | + door radius 8 at the BoardingPoint; + tier board zones; PM gate points | ShuttleService (`board` :550-573, `autoBoard` :574-593), FlightPlan (`PM_GATES` :228) | AP1a | test_shuttle + new `tests/airport_logic` |
| Shuttle arrival | 3 server moves, streaming first | dest = bridge cab at deboarding + 4.5 s (flag) | ShuttleService (`arrive` :594-617) | AP1a | test_shuttle / test_client |
| Jet bridge A1 animation | unchanged | – | – | – | clearance (docked + retracted) |
| Jet bridge M1 (new) | – | dock / retract like A1 | ShuttleGround | AP3 | clearance + test_build hull exemption |
| Charter | price, ticket reuse, 10-s cutscene | + charter gate points | CityService (`flight` :76-114) | AP1a | tests/world travel + airport_logic |
| Company jet | timelines, separation, fuel, folders | slot 2 moved, slot 3 new, field "pmapron", arrival at the airstair, display jets, livery pattern | JetPlan (:87-101), JetService, JetController | AP1b | `tests/guests_jet/*` (sep_check, clearance, two-jet probes) |
| VIP heli ferry | pads, fees, `heliTimes`, client prompt | none (the heli arrival point is kept free inside the Jet Centre) | – | – | clearance heli sweep |
| Hotel heli roof switch | GRANDHOTEL_SPEC 18.3 | none | – | – | – |
| Driver / limo places | `airport_departures`, `pm_airport`, `pm_limo`, `pm_hotel` | `airport_arrivals` x 300 → -150 (flag); new `airport_private`, `pm_jetcentre`; PM_STAND_AREA + Jet Centre rect → `pm_jetcentre` | DrivePlan (:341-351, :394-411, :499-511) | AP1a | `tests/drivers/*` incl. clearance legs |
| Itinerary | state machine, economy untouched | jet sub "private"; banner steps; walk estimates | ItineraryService, ItineraryMath, ItineraryController | AP1a | `tests/itinerary/*` |
| City crowd | 30 walkers, airport net | none (optional SkyDeck region grows on request) | – | – | metro_life |
| PM crowd | passengers | GuestPlan PM graph → new hall; CityLife region `pmairport` 20 walkers | GuestPlan; MetroPlan, CityLifeController | AP4; AP3 | guests_jet, metro_life / paths |
| Check-in counters | prompts `CheckinCounter` (CityAction checkin), radius 16 | PM counters move (data) | CityPlan.ABROAD | AP3 | test_build, travel |
| Markers other code reads (audit 4.6) | all names kept: `CheckinCounter`, `GateA<n>/GateDesk`, `JetBridge_A<n>`, `ParkedAircraft` (City), `FlightInfoBoard`, `BusinessLounge`, `CrewRoom`, `CompanyJetStand`, `Hangar/PrivateJet`, `AirportPost`, `ShuttleStand`, `ApronDoor`, `Helipad` ×2, `HelipadExit`, `VipLimoStand`, `LoungeConciergePost` | PM `ParkedAircraft` (Stand PM2) retired → the test "parked aircraft on stand 2" (`test_build.luau:104-105`) becomes "no airliner on the jet stands"; the JetController PM2 hide finds nothing (harmless, `JetController:412-423`) | MetroBuilder, tests/metro/test_build | AP3 | test_build |

---------------------------------------------------------------------------------------------------------------------

## 6. Data, save, economy, network

### 6.1 New shared module `ReplicatedStorage/Shared/Config/AirportPlan.module.luau`
Pure data and functions. The prewire writes v1 verbatim from Appendix A, and it is frozen after that.
- Holds flags, tier rules, zones, gates, board zones, gate arrival frames, kerbs, jet slots 2-3, the far corridor,
  posts, shops, souvenirs, hangar levels and spotter targets.
- It requires CityPlan, MetroPlan (pcall, like FlightPlan does) and AircraftModel (door points). It never requires
  FlightPlan, so FlightPlan can require it.

### 6.2 Save (DATA_VERSION stays 6; additions only)
| Field | Default (`EmpireMath.new`) | Cleaner (`Template.migrate`) |
|---|---|---|
| `empire.souvenirs` | `{}` | array of strings; keep only ids in `AirportPlan.SOUVENIRS`; dedupe; at most 16 |
| `empire.hangar` (only with O-1 "cash" or "progress") | `0` | integer `0..#Ops.HANGAR`; non-number → 0 |

Tickets, tiers, held items, spotter cards and lounge state stay in memory only, as today (audit 4.6, "nothing
airport-related is saved").

### 6.3 Economy (all numbers in CompanyOps; nothing creates money)
- `Ops.TRAVEL_SHOP = { snack = 25, toy = 150, souvenir = 400 }` [D]. P&L line `"travel"`.
- `Ops.HANGAR = { {id="lounge", price=150000}, {id="livery", price=300000}, {id="flagship", price=600000, stage=5} }`
  [D, O-1].
- `Ops.buyHangar(session, Economy, level)` copies `Ops.buyJet` (`CompanyOps:640-647`). It requires `e.jet`, the
  previous level and the stage.
- EmpireAction `"hangar"` is handled next to `"buyJet"` (`EmpireService:501`).
- Unchanged: ticket $700 = `TRIPS.abroad.flight` (CORE_SPEC 11.4), `HELI_FEE` 2,500, jet fuel per leg, every trip
  cost.
- Lounges and tiers are free. A Business tier from a company booking is a perk of the trip, not money.

### 6.4 Network (no new remote)
- `TravelAction {action="airport", op = "buy" | "claim" | "status" | "hangarView"}`. This adds one dispatch line in
  CityService (`:188-201`), and the existing limiter `{burst 4, 0.6/s}` applies.
- `EmpireAction {action="hangar", level}`.
- Player attribute `TravelTier` (on change).
- `ReplicatedStorage.Airport` attribute `Founders`: at most 12 entries "Company|stage", rewritten at most every 10 s
  and only on change. Company names are already filtered at save (SHOP_SPEC 3.8).
- Purchase results return through the remote's return value. `Notify` is used for toasts.

---------------------------------------------------------------------------------------------------------------------

## 7. Budgets (today measured → caps)

### 7.1 Parts
| Item | Today [M] | Estimate / cap [D] | Who enforces |
|---|---|---|---|
| City `Terminal/TerminalInterior` (Atomic) | 2,988 (audit 1.5) | refit net **+<= 460** → **<= 3,450** | world_check terminal interior budget **3,500 (unchanged)** |
| City interior incl. `Structure` (airport test) | 3,145 / 3,500 | <= 3,605 → cap **3,650** | `tests/airport/test_airport.luau:102` (raise) |
| City exterior w/o aircraft (airport test) | 1,764 / 2,000 | + Gateway canopy 150 + signs 20 → **<= 1,934** (cap unchanged 2,000) | `test_airport.luau:106` |
| City `Airport/SkyDeck` (new, Atomic) | – | cap **450** | new check in tests/airport |
| City `Airport/PrivateTerminal` (new, Atomic) | – | cap **180** | new check |
| City airport zone (world_check, by part centre) | 6,550 / 7,000 | 6,550 + 460 + 170 + 450 + 180 = **<= 7,810** → cap **8,000** | `agents/world/world_check.py:46-56` + `tests/world/test_build.luau:54` (raise) |
| PM `PMTerminal/Shell` (Atomic) | – | **800** | new `tests/pmairport` |
| PM `PMTerminal/Hall` (Atomic) | (old hall 29 + interior 54) | **1,800** | same |
| PM `PMTerminal/BusinessLounge` (Atomic, sibling) | 90 | inside Hall's 1,800 (counted with it) | `test_build.luau:57-61` (>= 8 seats, inside the terminal rect) |
| PM `PMTerminal/FoundersClub` (Atomic) | – | **750** | new |
| PM `PMTerminal/SkyDeck` (Default) | – | **150** | new |
| PM `PMTerminal/Forecourt` (Default) | ArrivalPlaza 125 | **160** | new |
| PM `PMJetCentre` (Atomic) | (VIP heli terminal inside VipHelipad 34) | **420** (VipHelipad marker model stays) | new |
| **PM new models, total caps** | – | **4,080** (excluded from the metro count, like the hotel) | `tests/metro/test_build.luau` scope split |
| PM removed from the metro-counted world | ArrivalTerminal 188 + ParkedAircraft 330 + ArrivalPlaza 125 = **643** (+ about 1 airport lot in x -340..-214, count **unsure**) | – | – |
| PM airfield additions (metro-counted) | Airfield 437 | JetBridge_M1 <= 45, J3 markings <= 20, runway neon refresh <= 40 → **<= +105** | test_build |
| Metro test (cap 5,281) | 5,253 (5,257 with the hotel frozen) | 5,257 - 643 + 105 = **<= 4,719** → **>= 562 left** | `test_build.luau:20-21, 37-38` |
| PM zone (cap 20,000) | 5,139 / <= 8,429 after the hotel | <= 8,429 - 643 + 105 + 4,080 = **<= 11,971** | world_check / `tests/world/test_build.luau:55` |
| Whole shared world (cap 30,000) | 13,647 (WorldCity); hotel spec <= 17,980 | + City <= 1,260 + PM net <= 3,542 → **<= 22,800** | `tests/world/test_build.luau:56` |
| Client-only parts (not in any server count) | – | staff rigs 8 × <= 22 = 176 per client; hangar dressing <= 220; display jets <= 3 bizjets (part count measured at build, unsure); held items 1-3 per player | AirportController stats |

Part-count arithmetic for the PM terminal against City:
- PM terminal + club + SkyDeck + forecourt + Jet Centre: 4,080 parts on ~99k sq studs, i.e. ~0.041 per sq stud.
- City TerminalInterior: 0.050 per sq stud (audit 2.4).
- Old PM hall: 0.0056 per sq stud.
- PM gets more rooms and functions per player. City keeps the denser fit-out and the big airfield.

### 7.2 Lights and other caps
| Item | Today [M] | Cap [D] |
|---|---|---|
| Real lights, airport zone | 40 / 40 (audit 3.2; refused by `CityBuilder.light` at 41, `CityBuilder.module.luau:57-64`) | **40 / 40 unchanged.** AirportBuilder stays at 35: SkyDeck gets 2 moved from TerminalInterior (23 → 21); PrivateTerminal gets 1 of CarPark's 2 |
| Real lights, PM airport | 9 (terminal 5, heliport 1, plaza 3) | **9**: Hall 3, Founders Club 2, heliport 1, Forecourt 2, Jet Centre 1. PM stays 40 / 40 |
| Client lights | 0 | **<= 3 per airport at any time**, `Shadows = false`, range <= 24, only while the camera is in that airport's region (lounge cove, SkyDeck at night, Hangar Lounge / club juice bar / Jet Centre lounge) |
| Neon (build-time) | – | no face > 24 sq studs (hotel rule) |
| `MetroNightGlow` (PM) | 198 → ~493 after the hotel | airport <= **120**, each with `GlowColor` |
| Server prompts | City 5 in the interior (audit 1.5) | + about 8 City (4 shops, A3 board, lift calls 2, Private Terminal 1) + about 12 PM (3 check-in, 3 shops, M2, 2 juice bars, concierge, board claim, Jet Centre) |
| Real `Seat`s | 12 in the whole world dump | PM lounge >= 8, club about 30, kids' plane 4. Gate seating stays pads, as at City (249 pads, audit 1.2) |
| Server SurfaceGuis | – | City +20, PM +40, `MaxDistance` <= 60 |
| Staff rigs drawn | 0 | **<= 8** per client (nearest); <= 40 studs at 30 Hz with limb swing, 40-90 studs at 5 Hz, hidden beyond |
| Crowd | City 30 walkers + <= 40 passengers | PM `pmairport` 20 walkers [D] + existing passengers |

---------------------------------------------------------------------------------------------------------------------

## 8. iPhone performance (landscape first)
- **Streaming.** The place uses MinRadius 128, TargetRadius 512, Improved, Opportunistic and MinimumRadiusPause
  (`pack.py:128-133`).
  - Every new interior is **Atomic** and split per floor or zone: PM Shell, Hall, BusinessLounge and FoundersClub;
    City SkyDeck and PrivateTerminal. A phone never sees half a room. This is the pattern the City TerminalInterior
    (2,988, Atomic) and the hotel floors use.
  - Nothing is **Persistent**: the test allows only the Spire abroad (`test_build.luau:141-145`).
  - The islands are 4,555 studs apart, so the airports never stream together (audit 3.3).
- **Parts near the camera.** At the PM terminal: the airport is at most ~4,300, plus the city blocks within 512.
  At City: the airport zone is at most 7,810. A tier-4 HQ is 28,341 parts (GRANDHOTEL_SPEC 19.1). Players already
  stand in that every day, so the airports stay well below the game's own worst case. Device FPS is **[S]**.
- **Client step.**
  - `AirportController` runs at <= 30 Hz with `debug.profilebegin("Airport.step")`. When the camera is more than
    300 studs from both terminals it disconnects, leaving one 1 Hz region check (the HotelController rule,
    GRANDHOTEL_SPEC 19.3).
  - Staff rigs use one `BulkMoveTo` per step.
  - Boards update once per second, within `BOARD_RANGE` 150 (`ShuttleGround:22`).
  - Moving walkways cost nothing in scripts (physics conveyor) [A].
- **Server.** No per-frame work. `AirportService` ticks at 1 Hz (tiers on change, held-item cleanup). Purchases go
  through the rate-limited remote.
- **Translucency.** Glass stays the existing material language. The PM Shell's visible semi-transparent area is at
  most 9,000 sq studs [D] (the hotel caps itself at 25,000 for a 10-floor tower). The test measures it the way
  GRANDHOTEL_SPEC 19.3 does.
- **UI** (iPhone landscape 844×390 first).
  - Boarding-pass card <= 38 % of the width; shop sheet as a bottom sheet; spotter chip; tier toast.
  - `ScreenInsets = CoreUISafeInsets`, touch targets >= 44 pt, the HUD goal bar never covered (GRANDHOTEL_SPEC 17
    rules).
  - Previews with `tools/guiprev` at 844×390 and 1280×720.
- **Cut list** if profiling demands it: §12.2.

---------------------------------------------------------------------------------------------------------------------

## 9. Packages, file ownership, order (all after the grand hotel)

### 9.1 Order
0. **Gate.** GRANDHOTEL_SPEC §21.1 completes: round 2b lands, then the hotel prewire, then A `grandhotel_shell` in
   parallel with B `grandhotel_inside`, then the joint verify and the review / fix round. The airport work starts
   only after that (`notes_integration.md:156`: "grandhotel A/B -> airports packages -> logic2"). Every file the
   hotel touched is edited on its post-hotel version, additively.
1. **AP0 `airport_prewire`** (integrate, the frozen-file owner):
   - writes `AirportPlan.module.luau` v1 verbatim (Appendix A), both flags false;
   - adds empty stubs for every new module;
   - wires `Main.server` / `Main.client` (AirportService.init + tick; AirportController and AirportPeopleController
     init);
   - adds run_all lines;
   - writes the split of `tests/guests_jet/` into jet files (AP1b) and guest files (AP4) into the package briefs. No
     request to a finished package is needed: each edited file is owned by exactly one airport package (§9.2).
2. **AP1a, AP1b, AP2 and AP3 in parallel.** Their file sets are disjoint (§9.2). Each works behind the flags against
   AirportPlan data.
3. **AP4 `airport_people_shops`** after AP1a and AP3 (it needs posts, rooms and the PM hall).
4. **Joint verify** (integrate): world dump, `world_check`, `world_entrances`, metro paths, flight clearance (+ far
   corridor + M1 bridge + heli), drivers and guests_jet clearance, run_all, blenderprev renders, guiprev. **Flags
   are flipped here:** `CITY_JOURNEY` once AP1a, AP2 and AP4 are green, `PM_V2` once AP1a, AP1b, AP3 and AP4 are
   green (AP4 moves the PM passenger walks into the new hall).
5. Independent review, then a fix round.

### 9.2 File ownership (no file appears twice)
| Package | Owns (edits) |
|---|---|
| **AP0 airport_prewire** | `ReplicatedStorage/Shared/Config/AirportPlan.module.luau` (v1, then frozen; changes via `design/requests/airport_plan.md`, applied by integrate); `Main.server.luau`, `Main.client.luau` (wiring only); `tests/lead/run_all.sh` lines |
| **AP1a airport_journey** (server + client logic) | NEW `ServerScriptService/Server/Services/AirportService.module.luau` (tier, board zones API, shop buy, souvenir grant, founders list); NEW `Client/Controllers/AirportController.module.luau` (lounge doors, scanner FX, spotter cards, bridge evacuation, moving-walkway visuals, hangar-level dressing *is not here*, see AP1b); NEW `Client/UI/Airport/BoardingPass.module.luau`, `SpotterCard.module.luau`, `TierToast.module.luau`; `ShuttleService.module.luau` (board zones, door radius, gate arrival); `FlightPlan.module.luau` (only `PM_GATES` under `PM_V2`); `CityService.module.luau` (TravelAction dispatch line; charter gate points); `DrivePlan.module.luau` (3 kerbs, Jet Centre stand area); `ItineraryService.module.luau`, `ItineraryMath.module.luau`, `ItineraryController.module.luau`; tests: NEW `tests/airport_logic/*`, `tests/flight/test_shuttle.luau`, `tests/flight/test_plan.luau`, `tests/itinerary/*`, `tests/drivers/*` (place expectations only) |
| **AP1b jet_hangar_save** | `JetPlan.module.luau` (slots 2-3, field "pmapron", arrival spots); `JetService.module.luau` (slot assignment, `LiveryPattern`, optional drop & go); `JetController.module.luau` (display jets, livery pattern, **hangar-level dressing**); `CompanyOps.module.luau` (`TRAVEL_SHOP`, `HANGAR`, `buyHangar`); `EmpireMath.module.luau` (defaults); `Template.module.luau` (cleaners); `EmpireService.module.luau` (action "hangar"); tests: `tests/guests_jet/*`, `tests/econ/*` (cleaner + sim rows), NEW `tests/hangar/*` |
| **AP2 city_airport_v2** (City geometry) | `AirportBuilder.module.luau` (interior refit, juice shelves, Fast Track barrier, arrivals corridor and one-way door, lounge door and board-zone markers, A3 charter sign, A2 spotter bridge, Gateway canopy, NEW models `SkyDeck` and `PrivateTerminal`, bizjet `PrivateJet`, light redistribution); tests: `tests/airport/*`, `tests/world/test_build.luau` (airport cap line), `agents/world/world_check.py` (airport BUDGET line) |
| **AP3 pm_airport_v2** (PM geometry) | NEW `ServerScriptService/Server/Services/PMAirportBuilder.module.luau` (`PMTerminal/*`, `PMJetCentre`, `JetBridge_M1` + `BoardingPoint`, PM posts); `MetroBuilder.module.luau` (old `airport()` / `lounge()` / `vipAirport()` / `plaza()` replaced by the PMAirportBuilder call; `apron()` without the parked airliner; boards tagged); `MetroPlan.module.luau` (LOUNGE, FAR_CLEAR corridor, pmPaths / portals / trees / lots, REGIONS `pmairport` + net; City SkyDeck region on AP2's request); `CityPlan.module.luau` (**only** the `City.ABROAD` table); `CityLifeController.module.luau` (`CAPS.pmairport`); `ShuttleGround.module.luau` (M1 bridge dock / retract); tests: `tests/metro/test_build.luau` (scope split, lounge rect, PM2 check, hull exemption), NEW `tests/pmairport/*`, `tests/flight/clearance.py` + `clearance_dump.sh` (M1 bridge frames), NEW `tests/flight/far_corridor.luau` |
| **AP4 airport_people_shops** | NEW `Client/Controllers/AirportPeopleController.module.luau` (staff at posts, shifts, client host at PM, visiting-client name boards); NEW `Client/UI/Airport/ShopSheet.module.luau`, `SouvenirSheet.module.luau`; `EmployeeRigDesign.module.luau` (additive airport uniforms + role mapping); `GuestPlan.module.luau` (PM passenger graph → new hall; visiting-client arrivals); tests: NEW `tests/airport_people/*`, `tests/guests_jet/*` **guest suites only** (GuestPlan rows; AP1b owns the jet rows, so the suites are split by file before AP1b starts) |

*Shared-file note.* `tests/guests_jet/` contains both jet and guest suites. AP1b edits only the jet files and AP4
only the guest files. The prewire lists both file sets explicitly.

---------------------------------------------------------------------------------------------------------------------

## 10. Tests and acceptance (mock unless marked)
- **tests/airport_logic** (AP1a):
  - tier matrix: stage 1-5 × jet × abroad account × booking;
  - board zones: inside or outside the lounge, with or without the tier, wrong leg, not boarding → errors;
  - door radius at the A1 / M1 BoardingPoint;
  - arrival frame at deboarding + 4.5 s;
  - charter at the A3 / M2 points (same price, held-ticket reuse);
  - shop buy: radius, tier, `NO_MONEY`, rate limit, souvenir granted once;
  - spotter claim only at the SkyDeck;
  - DrivePlan: the 3 new places route on the road graph;
  - flags off → byte-identical behaviour (snapshot of today's results);
  - **negative mutations**: remove the tier check, widen the radius, double the grant. The suite must fail on each.
- **tests/hangar** (AP1b): order H1 → H3, stage-5 gate for H3, `OWNED`, `NO_MONEY`; cleaner (bad types, unknown
  souvenir ids, more than 16); the economy sim re-run with the chosen O-1 option.
- **tests/guests_jet** (AP1b): 3 slots clearance against the built world; sep_check with "pmapron"; 2- and 3-jet
  probes; `PM_STANDS_FULL` at the 4th.
- **tests/airport** (AP2):
  - caps from §7.1;
  - markers of audit 4.6 unchanged;
  - no part named `Bottles` in `WorldCity/Airport`;
  - walk grid reaches the A1 BoardingPoint through the bridge [S for the real bridge floor];
  - arrivals door one-way geometry;
  - SkyDeck walkable (stair) and lift stops;
  - real lights in the airport model == 35.
- **tests/pmairport** (AP3):
  - caps and Atomic modes;
  - PM airport real lights == 9;
  - markers (`ApronDoor`, `ShuttleStand`, `BusinessLounge` >= 8 seats inside the new rect, `VipLimoStand`,
    2 `Helipad`, `HelipadExit` unchanged, `JetBridge_M1` + `BoardingPoint`, `AirportPost` × PM posts);
  - walkability of L1 and L2 (stair);
  - board zones inside their rooms;
  - heli arrival spot free;
  - no "BAR" label except "JUICE BAR"; no literal "PM 1" text outside tagged boards;
  - keep-out band z 7592..7605 empty for x < 400 above 0.5.
- **tests/metro/test_build** (AP3): scope split (PMTerminal/PMJetCentre excluded like the hotel); 42 checks still
  pass, with the PM2 check rewritten.
- **tests/flight**: clearance with the M1 bridge (docked at 0.25, retracted frames) and the heli sweep;
  `far_corridor.luau` asserts 0 shells within the hull reach (shuttle 62, jet 26) for both legs and both jet slots.
  It is my `probe_corridor.luau` turned into a test.
- **run_all** stays green. Every owner suite of an edited file is a gate (drivers, guests_jet, itinerary, flight,
  metro, world, airport, econ, shop2 for the economy rows).
- **Renders** (`tools/blenderprev`, look at each one):
  - City: forecourt / Gateway, SkyDeck from Airport Road, the lounge refit, Private Terminal + hangar;
  - PM: aerial, Meridian Hall landside, gate lounge + M1 bridge from the apron, Founders Club, terrace view, Jet
    Centre.
  - The audit renders are the "before" set (`design/airports/audit/renders/`).
- **GUI previews** (`tools/guiprev --viewport phone --dpr 2 --report` and desktop): boarding pass, shop sheet,
  souvenir sheet, spotter chip, tier toast.
- **Studio / iPhone only [S]:**
  - walking the jet bridges, the conveyor feel and local door collision;
  - Atomic load time of PM Hall (1,800) and City TerminalInterior (3,450) on an iPhone;
  - client lights at night; staff rig cost.

---------------------------------------------------------------------------------------------------------------------

## 11. Audit weaknesses covered
| Audit | Covered by | Fully? |
|---|---|---|
| W1 PM airport weak | Meridian Hall (2 levels, ~99k sq studs), Founders Club, Jet Centre, M1 bridge, SkyDeck, Welcome Hall | yes |
| W2 planes through buildings | FAR_CLEAR corridor (measured 14 shells, +32.6 clearance) + regression test | yes |
| W3 one flight, fake PM 104 | live boards, A3 / M2 charter gates, A2 spotter bridge | partly (still one destination) |
| W4 never walk to the plane | walk-on / walk-off, jets at the airstair | yes |
| W5 short flight | – | **no** (out of scope; cabin package) |
| W6 no staff, decor lounges | staff at posts, tiered lounges with server perks | yes |
| W7 PM cramped, 2 jet slots | 3 slots, Jet Centre; runway kept | partly |
| W8 City flat and sparse | Gateway canopy, SkyDeck tower, display jets, bizjet decor | partly (the apron band z 2700..2840 stays empty) |
| W9 no lights | redistribution, neon, client lights | yes, within the existing budget |
| W10 kid-friendly | juice bars, no bottles, no gambling rules | yes (+ `WINE CELLAR` rename in AP3) |
| W11 heli lobby | hotel spec; Jet Centre arrival | yes (with GRANDHOTEL_SPEC 18.3) |

---------------------------------------------------------------------------------------------------------------------

## 12. Risks, cut list, owner decisions

### 12.1 Risks (biggest first)
1. **Biggest risk: changing the boarding / arrival contract in the most-tested flow of the game.** Walk-on at the
   bridge door, walk-off from the bridge, PM gate points and tier board zones touch ShuttleService, FlightPlan,
   CityService, ItineraryService and DrivePlan. These belong to 4 finished packages: flight 341 + 18 checks,
   itinerary, drivers and world travel. GuestPlan / ShuttlePassengers NPC walks still use the ApronDoor and today's
   points. Other agents keep editing ShuttleService and ItineraryService (this morning: +7 / +61 lines).
   *Mitigation:*
   - two flags default off, so flags off = today's behaviour (asserted by a snapshot test);
   - old arrival points kept for the charter and jet fallback;
   - additive edits on the post-hotel versions;
   - every owner suite as a gate;
   - flags flipped only at the joint verify.
2. **Walking fatigue for kids.** It adds 12-26 s per leg (§3.1), and the PM boarding window is 30 s. *Mitigation:*
   board from the lounge or club, moving walkways, the charter for the impatient, staff wayfinding, GPS chevrons.
3. **iPhone load of the Atomic PM Hall (1,800) and the City interior (3,450)** [S]. *Mitigation:* split
   Landside / Airside Atomic models (cut 6); caps enforced by tests.
4. **Jet slot geometry at PM (11-16 stud gaps)** [D]. *Mitigation:* guests_jet clearance + sep_check decide. The
   fallback is 2 slots + "drop & go".
5. **Bridge physics.** A player standing in a bridge while it retracts locally. *Mitigation:* the client moves its
   own character out before the retract; tests and [S].
6. **Local-collision doors** are cosmetic access only [A]. The server never trusts them.

### 12.2 Cut list (in this order; each cut leaves every existing flow working)
1. display jets;
2. A2 spotter bridge;
3. photo spots;
4. visiting-client name boards;
5. PM `pmairport` walkers 20 → 10;
6. split the PM Hall / City interior into two Atomic halves (performance, not a feature cut);
7. Hangar H3;
8. kids' belt ride (keep the mini plane);
9. Founders Club game corner + nap pods;
10. souvenirs saved → session-only (drops the save addition);
11. PM slot 3 (keep the PM2 airliner; `PM_STANDS_FULL` at the 3rd);
12. Private Terminal (the jet trip keeps today's immediate `tryJet`).

**Never cut:** walk-on / walk-off; tier lounges with server perks; the M1 bridge; the Founders Club; kid-friendly
fixes; the far corridor.

### 12.3 Owner decisions (the lead or the user)
- **O-1 Hangar levels:** buy with cash (`Ops.HANGAR` 150k / 300k / 600k [D], a late sink per CORE_SPEC 10.3) or
  unlock by progress.
- **O-2 Shop prices** (`Ops.TRAVEL_SHOP` $25 / $150 / $400 [D]) or everything complimentary.
- **O-3 Retire the PM2 parked airliner** (needed for slot 3).
- **O-4 Walk-off arrival by default** (recommended) or keep today's teleport as a setting. A setting would need a
  saved pref, so I recommend no setting.
- **O-5 Tier thresholds:** Business at stage 3; Founder at stage 5, or stage 4 with a PM client or the jet.

---------------------------------------------------------------------------------------------------------------------

## Appendix A. `AirportPlan` v1 (sketch the prewire writes; values from §2-4, [D])
```lua
--!strict
-- AirportPlan v1 (airport packages): pure data + functions shared by server and client. No instances.
local RS = game:GetService("ReplicatedStorage")
local CityPlan = require(RS.Shared.Config.CityPlan)
local Aircraft = require(RS.Shared.AircraftModel)
local G = CityPlan.GROUND
local P = {}
P.CITY_JOURNEY = false -- flipped by integrate at the joint verify
P.PM_V2 = false
P.TIER = { traveller = 0, business = 1, founder = 2 }
P.RULES = { businessStage = 3, founderStage = 5, founderStage4 = true } -- stage 4 + (jet or abroad account)
P.BOARD_DOOR_RADIUS = 8
P.SHOP_RADIUS = 14
P.ZONES = {
	city = {
		lounge = { rect = CityPlan.AIRPORT.lounge, y1 = G, y2 = G + 14, tier = 1, board = "out" },
		fastTrack = { x1 = -66, x2 = -54, z1 = 2452, z2 = 2498, tier = 1 },
		arrivalsDoor = { x1 = -156, x2 = -144, z = 2485 },
		charterGate = 3, -- gate A3 BoardingPoint
		skyDeck = { x1 = 312, x2 = 352, z1 = 2436, z2 = 2476, deckY = G + 50 },
		privateTerminal = { x1 = -836, x2 = -776, z1 = 2470, z2 = 2526 },
		region = { x1 = -320, x2 = 360, z1 = 2400, z2 = 2580 },
	},
	pm = {
		terminal = { x1 = -320, x2 = 160, z1 = 7610, z2 = 7748, height = 34, level2 = G + 16.5 },
		lounge = { rect = { x1 = -318.5, x2 = -210, z1 = 7610.8, z2 = 7684 }, y1 = G, y2 = G + 16, tier = 1, board = "back" },
		club = { rect = { x1 = -318, x2 = -90, z1 = 7612, z2 = 7690 }, y1 = G + 16, y2 = G + 32, tier = 2, board = "back" },
		skyDeck = { x1 = -60, x2 = 150, z1 = 7612, z2 = 7660 },
		gateLounge = { x1 = 60, x2 = 158, z1 = 7612, z2 = 7746 },
		security = { z1 = 7684, z2 = 7692, lanes = { -40, 0, 40 }, fastTrack = 1 },
		arrivalsDoor = { x = 60, z1 = 7716, z2 = 7728 },
		gateDoor = { x = 160, z1 = 7684, z2 = 7696 },
		rotunda = Vector3.new(180, G + 0.5, 7690),
		gates = { Vector3.new(148, G + 4, 7690), Vector3.new(130, G + 4, 7676) }, -- FP.PM_GATES when PM_V2
		charterDesk = Vector3.new(100, G + 4, 7616),
		jetCentre = { x1 = 556, x2 = 700, z1 = 7708, z2 = 7748, keepFree = Vector3.new(576, G + 3.5, 7714) },
		keepOut = { x1 = -700, x2 = 400, z1 = 7592, z2 = 7605, maxTop = G + 0.5 },
		farCorridor = { x1 = -2700, x2 = -640, z1 = 7454, z2 = 7634 },
		region = { x1 = -330, x2 = 710, z1 = 7600, z2 = 7770 },
	},
}
P.KERBS = { -- DrivePlan places (drivers package confirms lanes)
	airport_arrivals = { stop = Vector3.new(-150, CityPlan.ROAD_TOP, 2413.5), door = Vector3.new(-150, CityPlan.WALK_TOP + 3, 2421.5) },
	airport_private = { stop = Vector3.new(-806, CityPlan.ROAD_TOP, 2394), door = Vector3.new(-806, CityPlan.WALK_TOP + 3, 2405) },
	pm_jetcentre = { stop = Vector3.new(628, CityPlan.ROAD_TOP, 7772.6), door = Vector3.new(628, CityPlan.WALK_TOP + 3, 7757) },
}
P.JET_SLOTS = { -- JetPlan.PM_SLOTS 2..3 (slot 1 unchanged); nose west; AY = MetroPlan.APRON.top
	[2] = { cf = Vector3.new(460, 0, 7676), arriveX = 520, departX = 405, rollFrom = 355 },
	[3] = { cf = Vector3.new(460, 0, 7618), arriveX = 520, departX = 405, rollFrom = 355 },
	pmapron = { x1 = 300, x2 = 560, z1 = 7590, z2 = 7725 },
}
-- door L1 of the shuttle on a stand frame (bridge cab target; GATE_ARRIVAL = cab frame facing along the bridge)
function P.doorWorld(stand: CFrame): Vector3
	local d = Aircraft.points("320", 1.8).doorL1 :: any
	return stand:PointToWorldSpace(Vector3.new(d[1], d[2], d[3]))
end
P.SOUVENIRS = { "city_postcard", "city_mug", "city_model", "city_sweets", "skydeck_pin", "hangar_patch",
	"pm_sweets", "pm_globe", "pm_robo", "pm_juice", "gift_helix", "gift_frontier", "gift_nova", "gift_science", "spotter_badge" }
P.HANGAR = { "lounge", "livery", "flagship" } -- prices in CompanyOps.HANGAR
P.SPOTTER = { city = { "shuttle_takeoff", "shuttle_landing", "ambient_arrival", "ambient_departure", "sky_crossing", "company_jet" },
	pm = { "shuttle_landing", "shuttle_takeoff", "heli_liftoff", "company_jet" } }
-- PM staff posts (AirportPost, CityPost kind, Zone abroad) - positions on L1 unless y given
P.PM_POSTS = {
	{ "checkin", -150, 7716 }, { "checkin", -110, 7716 }, { "checkin", -70, 7716 }, { "desk", -190, 7716 },
	{ "security", -44, 7690 }, { "security", -4, 7690 }, { "security", 36, 7690 },
	{ "gate", 130, 7680 }, { "gate", 100, 7620 }, { "lounge", -214, 7650 }, { "club", -190, 7666, G + 16.5 },
	{ "shop", -180, 7630 }, { "shop", -125, 7630 }, { "shop", -70, 7630 }, { "juice", -300, 7630 }, { "juice", -280, 7640, G + 16.5 },
	{ "concierge", 40, 7736 }, { "concierge", 640, 7728 },
}
function P.tier(e: any, hasBooking: boolean?): number -- implemented with CompanyOps (stageIndex, client trip)
	error("AP1a implements; the prewire ships the signature only")
end
return P
```

## Appendix B. Roblox APIs named (all present in `tools/API-Dump.json`, `apicheck_out.txt`: 61 checked, 0 missing)
`BasePart.AssemblyLinearVelocity`, `CanCollide`, `CanTouch`, `CanQuery`, `CastShadow`, `Anchored`, `Transparency`,
`Massless`, `SetNetworkOwner`.
`ProximityPrompt.ActionText`, `ObjectText`, `HoldDuration`, `MaxActivationDistance`, `RequiresLineOfSight`,
`Enabled`, `Triggered`; `ProximityPromptService.PromptTriggered`, `PromptShown`.
`Player:RequestStreamAroundAsync`, `Player.ReplicationFocus`; `Model.ModelStreamingMode`, `Model:PivotTo`;
`Enum.ModelStreamingMode.Atomic / Persistent / Default`.
`WorldRoot:BulkMoveTo`, `WorldRoot:GetPartBoundsInBox`; `Workspace:GetServerTimeNow`.
`Instance:SetAttribute / GetAttribute / GetAttributeChangedSignal / AddTag`;
`CollectionService:GetTagged / GetInstanceAddedSignal`.
`PointLight` (`Shadows`, `Range`), `SurfaceLight`; `SurfaceGui.MaxDistance`, `BillboardGui.MaxDistance`.
`Humanoid.WalkSpeed`, `Humanoid.SeatPart`, `Seat.Disabled`; `TweenService:Create`; `ParticleEmitter.Enabled`.
`Beam`, `Highlight`, `WeldConstraint`, `AlignPosition`.
`ScreenGui.ScreenInsets` + `Enum.ScreenInsets.CoreUISafeInsets`; `Enum.Material.Neon / Glass / Marble / Carpet / WoodPlanks`.
`Workspace.StreamingEnabled / StreamingTargetRadius / StreamingMinRadius` (read-only for scripts; set by `pack.py`).
`Players.LocalPlayer`, `Camera.CFrame`.
No asset, sound or animation ids. No Robux product ids. No new remote.

## Appendix C. My evidence files (`design/airports/concept_gameplay_work/`)
`probe_corridor.luau` + `probe_corridor_out.txt` (timetable, far-shell conflicts, corridor test) ·
`probe_points.luau` + `probe_points_out.txt` (aircraft door and extent points) ·
`walk_times.py` + `walk_times_out.txt` · `apicheck.py` + `apis.txt` + `apicheck_out.txt` ·
`plans.py` + `plan_city_concept.png` + `plan_pm_concept.png` · `.gen/` (manifest of live `work/src`, 10:14 UTC).
