# GRANDHOTEL_SPEC.md - Meridian Grand Hotel rebuild (BINDING)

Lead design spec for the build packages **grandhotel_shell (A)** and **grandhotel_inside (B)**. Date 2026-10-11.
Written by grandhotel_design / lead. Design only: nothing under `work/src` or `tests` was edited for this spec.
**Critic pass 2026-10-12** (independent feasibility review): every edit is listed at the end in "Critic changes" (CC-1..CC-30);
the edited text below is binding. Evidence files: `agents/grandhotel_design/critic2/`.
Paths are relative to `scratchpad/` (= `/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad`).

Sources: judges' winner `agents/grandhotel_design/proposal_wow.md` + grafts from `proposal_life.md` and `proposal_iphone.md`,
scouts `agents/grandhotel_design/code.md` and `research.md`, round-2b scope `agents/stable/round2b.js`, drivers API
`agents/drivers/API.md`, the current `work/src` (re-read on 2026-10-11, see §0.3) and the current renders in `out/meridian_grand/`.

Floor plans (rendered with Node Playwright from one data source, LOOKED at, labels fixed):
`out/grandhotel_design/plan_lobby.png`, `plan_guest.png`, `plan_wellness.png`, `plan_suites.png`, `plan_roof.png`.
Their data source is `agents/grandhotel_design/lead/plan.py` (rooms, zones, furniture footprints, walls with door gaps,
posts, NPC waypoint graphs, routes). `python3 plan.py` validates it: 13 rooms, no overlaps, every room >= 20 studs wide,
every door on a corridor edge, **every NPC edge clear of every collidable footprint and wall (rig radius 0.9)**, keep-free
points clear. Current result: `validation: OK (0 problems)`. Builders copy numbers from this spec; if a number here and
in `plan.py` ever differ, `plan.py` wins and the spec is fixed.

---------------------------------------------------------------------------------------------------------------------

## 0. How to read this spec

### 0.1 Labels
- **[M]** measured in today's code or in a world dump (file:line or command given).
- **[D]** design value set by this spec (binding).
- **[S]** only Roblox Studio or a real iPhone can confirm (collected in §24).
- **MUST** = acceptance criterion; a test in §22 checks it.

### 0.2 Coordinates
- **Hotel-local frame** = the CityPlan frame of `intl_hotel` [M] `CityPlan.module.luau:323`: origin O = world
  (0, 24, 8380), identity rotation. `x` = world x (east +), `ly` = world y - 24, `lz` = world z - 8380.
  The street (Harbour Street, Meridian Boulevard) is at negative lz (north, the facade faces -Z). The building covers
  x -70..70, lz 0..120. **world = (x, 24 + ly, 8380 + lz).**
- All tables give local coordinates unless they say "world". Floor-level points (posts, nodes) are at the floor top of
  their level; a rig root stands 3 studs above (as `City.layout` points do).
- Road top = ly 0.22 (world 24.22 = `City.ROAD_TOP`), sidewalk top = ly 0.475 (`City.WALK_TOP`), lobby floor ly 0.5 [M].

### 0.3 Facts re-verified in the current tree for this spec (2026-10-11)
| Fact | Where |
|---|---|
| `pm_hotel` is still the old kerb: stop (70, RT, 8347.4) heading +X, approach {(38,8344),(58,8347.4)}, depart {(110,8344)}, door lookAt((66,WT+3,8356.5),(30,WT+3,8380)); all kerbPlace segments class `access` | `DrivePlan.module.luau:413-416`, `kerbPlace` l.323 |
| `Drive.SPEED.access` 18, corner limit v = sqrt(A_LAT=10 * R), `FILLET` 16, `SPEED.metro` 30; limo 21 x 7.4, wheelbase 13; `SEATS.limo.rearR` = (1.6, 2.6, **4.4**) car frame -> the rear right door is 4.4 behind the pivot | `DrivePlan.module.luau:35-54, 1051` |
| `DriverService.ALIGHT` = 1.2 s (founder placed at `place.door` 1.2 s after the stop) | `DriverService.module.luau:97` |
| Ride folders publish `Id, Kind, Look, Zone, Plot, Driver, Rider, Pickup, To, ToName, WaitUntil, Until, Purpose, State, Plan, Companions`; `Drive.decode(str, plot)` -> `{Seg{from,to,side,t0,who}}`, `Drive.segEnd(sg, plot)` | `DriverService.module.luau:301-309`, `DrivePlan.module.luau:1094-1155` |
| `DriverService.onTripAction(action, handler(session, payload))` (`"ride"` reserved), per-action limiter `{8 burst, 3/s}`; `DriverService.phoneHook` exported | `DriverService.module.luau:994, 1844-1870, 1805` |
| The drivers fix round (task "drivers fix: tests ...") is still running: **pm_hotel is re-done only after it lands** (§6.3) | shared task list |
| `LiftLogic.new(levels, heights, startLevel, capacity, position?)`, `call(car, "hall"|"car", level)`, `step(car, dt, now, input)`; VMAX 10, ACCEL 6, DOOR_TIME 0.8, DWELL 3.5; no requires | `LiftLogic.module.luau:13-28, 86, 213, 627` |
| `UNIFORMS` feature keys: shirt, jacket, vest, trousers, shoes, skirt, tie, apron, hat, cap, driverCap, gloves, hivis; job mapping l.82; `Rig.MAX_PARTS` 22 | `EmployeeRigDesign.module.luau:18, 43-64, 82` |
| `EmployeeController.pose(activity, sitting, walking, time, seed, holdingCup?, pose?, talking?, lookYaw?)`; poses present: type, typeStand, stir, pour, plate, carry, chop, wash, wipe, push, write, reach, plug, inspect, scan, greet, sort, run, cycle, row, lift, relax, eat, phone, present, shower. **No "swim"** | `EmployeeController.module.luau:59-200` |
| `GuestPlan` exports `sample(actor, t)`, `span`, `sOfHour(h)`, `dayOf(t)`, `route`, `hash`; its graph builders are local; `GuestController` exports no figure builder | `GuestPlan.module.luau:42-305`, `GuestController.module.luau:345-373` |
| CityLife night look: `WINDOW_PARTS = {Windows, WindowGlow, GlassBand, FarTower, Impostor}` lit if hash % 20 < 9 (45 %), `look.lit` fixed at `registerGlow`; night = ClockTime < 6.3 or > 18.2; hotel impostor = ONE Glass box, shown while `WorldCity/PortMeridian/Hotel_intl_hotel/Shell` has < 3 children | `CityLifeController.module.luau:1047-1080, 1128-1137, 1264-1272` |
| `Shuttle.heliArrival("hotel")` = `CityPlan.INTL_HOTEL.lobby`; return transfer must start within `HELI_RADIUS` 40 (abs dy <= 16) of the lobby point; ride published on `ReplicatedStorage.Shuttle` as `HeliStart/HeliMode/HeliRider`; `FP.heliTimes` shared | `ShuttleService.module.luau:53-54, 460-505, 601` |
| AirTrafficController dispatches ANY prompt with `CityAction == "heli"` + `HeliTo` (so a hotel-made local prompt works without editing it); its lobby prompt is a local part at the lobby point, 12 studs | `AirTrafficController.module.luau:181-191, 296-299` |
| `Phone.onAction(kind, handler)`; contacts `{assistant, driver, reception, it}`; only `driver` runs a hook; `runHook` turns a non-table result into `{ok=true}` (so a reception hook needs an explicit fall-through rule) | `PhoneService.module.luau:53, 163, 408-418, 627` |
| `CampusConfig.PLOT_COUNT` = 12; `MetroPlan.HOTEL_ROOF` = 150.2; `HELIPADS.hotel` (0, 151.2, 8408), size 40 | `CampusConfig.module.luau:6`, `MetroPlan.module.luau:130-133` |
| Harbour Street `road("pm_harbour", "x", 8336, -700, 700, 32, 8, 0, 1)` (no gaps); `gaps = {side, a1, a2}`, side 1 = south sidewalk; `ACCESS` holds {0,8356}; walk spur `(0,8356)->(0,8370)`; hotel portal `(0,8376)` facing +Z | `MetroPlan.module.luau:66-80, 761-765, 1010, 1042` |
| `towers()` builds RoofLiftHouse, RoofLiftDoor, HelipadExit (23,152.7,8394), HotelRoofSign + Glow | `MetroBuilder.module.luau:784-802` |
| Hotel model attrs `BuildingId`, `Zone`; `Shell` (Floor part = x -70..70, y 0..0.5, z 0..120) + `Interior` (Atomic) | `CityBuilder.module.luau:341-355` |
| **Port Meridian today: 5,253 parts (+4,472 over BASE 781, BUDGET 4,500 -> 28 left), real lights abroad 40/40, `metro_build: 42 passed, 0 failed`** | ran `tools/luau tests/metro/test_build.luau -a .gen_ghspec` (manifest from work/src) |
| Itinerary package not started (no `agents/itinerary/`; ItineraryService/Controller are stubs) | file listing |
| Every Roblox API named in this spec is in `tools/API-Dump.json` (201 names checked; only the two deliberately unused ones fail: `Model.LevelOfDetail` PluginSecurity, `GuiService.PreferredInput` missing) | `agents/grandhotel_design/lead/apicheck.py lead/apis.txt` |
| *(critic)* Re-checked 2026-10-12: lead list 201/201 present (1 missing = `GuiService.PreferredInput`, not used) + a regex scan of the whole spec + 78 extra members/enums the critic named (`PrismaticConstraint.LinearResponsiveness`, `UserInputService.PreferredInput`, `Enum.PreferredInput.*`, `ScreenGui.ScreenInsets`, `Workspace:BulkMoveTo`, `Terrain.WaterColor` / `WaterTransparency` / `WaterReflectance` / `WaterWaveSize` / `WaterWaveSpeed`, `Seat.Disabled`, `ProximityPrompt.KeyboardKeyCode/GamepadKeyCode`, `Enum.Material.Limestone/Glacier/Cobblestone/...`): 0 missing; only `Model.LevelOfDetail` (PluginSecurity) and `Lighting.Technology` (RobloxScriptSecurity) flagged, both "not used" | `critic/apiscan.py design/GRANDHOTEL_SPEC.md`, `lead/apicheck.py critic/apis_critic.txt` |
| *(critic)* ExecutiveLimo mesh (hook already in DriveController): 25.76 x 7.36 at scale 0.95, pivot half-way between the axles, wheelbase 18.10 -> **front 12.44 / rear 13.32** from the pivot; rear seat rig root z **+8.80** (part-built limo: 21 centred, rear seat z +4.4). `tests/drivers/probe_legs.luau` already emits every `pm_*` leg twice (part + `#mesh`) for `clearance.sh` | `DriveController.module.luau:64-91`, `assets/vehicles/executivelimo/manifest.json` (front/rear overhang 3.562 / 4.491 m-studs x 0.95), `tests/drivers/probe_legs.luau:30-50` |
| *(critic)* `DriverService.DROP_PAUSE` 4 s (drop-off: the car leaves 4 s after the stop); a **pick-up car waits up to 90 s** at the stop | `DriverService.module.luau:98`, `agents/drivers/API.md` (Flow 2) |
| *(critic)* A MetroPlan sidewalk `gap` is a lay-by: the CityLife walk line is **cut** there (no walk edge across) | `MetroPlan.module.luau:553-575` (`inGap`, `sidewalk`) |
| *(critic)* `PhoneController` toggles the phone on **P / ButtonY** (unless the input was processed) and closes it when a ScreenGui named in the public table `PhoneController.PANELS` appears | `PhoneController.module.luau:50, 790-801` |
| *(critic)* Company clock = `Ops.hour(workspace:GetServerTimeNow())`; StaffService writes it to `Lighting.ClockTime`; company day = `floor(t / Ops.DAY)`; `GuestPlan.sOfHour`: 08-18 at 90 s/h, 18-08 at 21.43 s/h | `StaffService.module.luau:50, 552`, `CompanyOps.module.luau:30, 166-170`, `GuestPlan.module.luau:308-317` |
| *(critic)* GuestPlan was edited after this spec (guests_jet fix round, 2026-10-11 17:32): `sample`, `span`, `sOfHour`, `dayOf`, `route`, `hash` and the `Actor` / `Seg` types are unchanged | `GuestPlan.module.luau:52-53, 62, 139, 189-217, 308-317` |
| *(critic)* World dump (`out/meridian_grand/dump/world_dump.json`) re-measured: hotel 78 parts, 3 PointLights, 11 Glass parts, 0 `MetroNightGlow` (Port Meridian 198), Port Meridian 5,253 parts, **2,514 parts within 512 studs (flat) of the door (0, 8375)**; east of the hotel (x 70..95, z 8370..8510) nothing but ground paving (lift tower site free) | `critic2/` queries (`critic/q.py`) |

### 0.4 Hard rules (repeat of the brief, all binding)
- **Economy: no change.** No money is created or charged by anything in this spec; all hotel services are free
  ("complimentary"); the helicopter keeps its existing fee logic; B2B travellers' Meridian Grand nights stay inside the trip
  cost (`Ops.TRIPS.abroad.hotel`, CompanyOps). No paid items, no random rewards.
- **No new saved field.** Every hotel state is a session attribute; old saves load unchanged.
- **No new remote.** `Net` is frozen. Channels: server ProximityPrompts (attribute `HotelAction`), client-made prompts,
  `TripAction {action="hotel"}` through `DriverService.onTripAction`, existing `Notify`.
- **No invented ids.** No asset / animation / sound ids. Sounds only as silent hooks (`""`) in `CampusAudioConfig`.
  The only texture string allowed is the project's existing `Kit.steamEmitter` built-in smoke texture.
- **No brands, no real hotel names.** Signs ASCII + `· É ► ◄ –` only, no "STUDS"; "MERIDIAN GRAND HOTEL" must stay in the signage.
- Admin stays username-based (not touched). `--!strict`, English UI, deterministic (seeded) everywhere.

---------------------------------------------------------------------------------------------------------------------

## 1. What gets built (one page)

| The user's wish (German, translated) | What he gets |
|---|---|
| "Zimmer die richtig krass sein müssen" (the rooms must be really impressive) | **13 bookable rooms, one for every founder on the server (12 plots) and never shared.** The **Royal Penthouse 1001**: a 50-stud glass wall straight down Meridian Boulevard, its own glass **Lantern Room** in a gold turret next to the helipad (spiral stair), a bar, dining for 8, a **secret bookshelf door to a private cinema** ("NOW SHOWING · <Company>: Year One"), a tub at the glass, a terrace whirlpool 113 studs above the street. **Panorama Suite 1002** with a 20-stud **aquarium wall**, corner-glass tub, game corner, CEO desk. **Spire Suite 1003**: bath with the 468-stud Meridian Spire 20 studs outside the glass. **Deluxe Kings 1004/1005** and **8 Skyline Studios 801-808**: every one with a tub at the floor-to-ceiling window, rain shower with steam, LED bed, game corner, company TV, mood light |
| "natürlich eine Wellness Etage" (of course a wellness floor) | **Sky Spa on F9**: a **swimmable infinity pool** (Terrain water) whose water runs to the edge above the colonnade with the boulevard below; Finnish sauna ("Pour water" -> steam), hammam under a star dome, cold zone (cold plunge, ice fountain, snow cabin, polar-rain showers), whirlpool, relax lounge with fireplace, gym with a view, treatment rooms, spire relaxation room, two terraces with a hot tub; the spa routine mini-quest "Brrr! ... Spa routine complete, Finnish style." |
| "das Hotel muss Mitarbeiter haben" (the hotel must have staff) | **22 named staff in hotel uniforms, 16 on duty at noon, 3 at night**, shift changes at 07:00 and 19:00 through the staff door, a doorman who is at the limo's rear door when the founder gets out (timed from the published ride), bellhop with the brass luggage cart who brings the suitcase to the room door, receptionists who greet by name and time of day, concierge, bartender, evening pianist, café host with breakfast, duty manager, security (night rounds), spa receptionist, pool attendant, therapist, housekeepers (rounds, turndown chocolate), room-service waiter, heli attendant, maintenance on a ladder at the chandelier; plus up to 12 visible hotel guests (breakfast, pool, swimmers, gym, bar, balconies) |
| Promised by the lead | a real grand facade (rusticated podium, colossal colonnade, cornices, balconies, setbacks, gold turrets), a porte-cochère with a marquee canopy where the VIP limo drops you off, a doorman, windows that glow at night (room by room, changing every company hour), a lobby with a 3-tier chandelier, rugs and a bar |

Shape of the work: two packages after round 2b (§21). **A** builds the envelope and everything outside + all world
integration (drive, DrivePlan, roof, lift tower geometry, night tags, impostor, Terrain pool). **B** builds the four interior
floors and all behaviour (rooms, check-in, doors, lifts, staff, guests, UI). Budget: hotel 78 -> **<= 3,250 parts**
(critic recount ~2,960; the lead's 2,817 left out partition walls and the lift landings, CC-12), real lights stay **3**,
client lights **<= 3**, staff rigs drawn **<= 8**, guest figures **<= 12**.

---------------------------------------------------------------------------------------------------------------------

## 2. Decisions taken by the lead (winner, grafts, must-fixes)

### 2.1 Base
The judges' winner **proposal_wow** is the base: same footprint, Beaux-Arts body with Art-Deco gold crowns, colonnade,
setbacks at F9/F10, gold turrets, marquee porte-cochère, atrium lobby, Sky Spa with the infinity pool, Royal Penthouse,
panoramic glass lifts outside the east facade.

### 2.2 Grafts applied (every graft of the verdict)
| # | Graft | Where in this spec |
|---|---|---|
| G1 | life staff choreography (shifts 07/19 via staff door, night porter, breakfast 07:00-10:30, maintenance on a ladder, heli attendant from HeliStart/HeliMode/HeliRider, evening balcony guests, seeded per company day) | §14, §15 |
| G2 | doorman timed from the published ride (To == "pm_hotel", Drive.decode + Drive.segEnd, walk starts 3.5 s before the stop, at the rear door when the founder appears at +1.2 s; no 18 studs/s sprint) | §6.5 |
| G3 | a room for every founder: 13 rooms >= PLOT_COUNT 12; F8 is a real Skyline floor (8 studios) built around the pool basin; tests "#ROOMS >= PLOT_COUNT" and "two players racing for the penthouse, exactly one wins" | §8, §12, §22 |
| G4 | the hotel knows the player: TV with live company numbers, welcome card naming today's client, greetings by company hour + name, colleague checks in and is at breakfast with the return time, room service through the company phone's Reception contact | §10.6, §14.4, §18.4 |
| G5 | `CityLife.setLit` hook: lit-window share changes every company hour (60/40/15/30 %); booked rooms switch their cove on so the street sees which rooms real players have | §5.4 |
| G6 | invite up to 3 friends + Knock prompt with a notice to the owner | §16 |
| G7 | spa mini-quest + a swim pose for 1-2 pool guests | §9.4, §15 |
| G8 | iPhone performance rules (<= 3 client lights, Shadows=false, NPC step disconnected beyond 200 studs, profiling hooks, no Glass within 12 studs of water, visible semi-transparent area cap, emitters disabled at build and <= 2 active per client, ordered cut list) | §19, §20, §22 |
| G9 | Shell is Atomic | §20 |
| G10 | lift: key card for the room floors (`KEY_REQUIRED` or invite), only real stops listed, ButtonB closes, `GuiService.SelectedObject` on the first enabled button | §13, §17 |
| G11 | Aquarium wall (custom, no Glass over water) and the "NOW SHOWING · <Company>: Year One" cinema text + game corner | §10 |
| G12 | island flag recoloured to the booked founder's company colour (one local Color write); mood light as one cycling owner prompt; drive-up option B (east entry) as fallback | §6.2, §10.6, §6.3 |
| G13 | Terrain block on the 4-stud grid in all three axes, mock test that `meta.terrainOps` holds exactly one FillBlock equal to the pool rect, `POOL.mode = "terrain" | "part"` tested both ways | §9.2, §22 |

### 2.3 Must-fixes (all resolved)
| # | Must-fix | Resolution |
|---|---|---|
| F1 | wow's limo stop (3.5, 8369) blocked the pedestrian path at x 0 | stop **A at pivot (19, RT, 8368.5)** *(critic: was 16 - the ExecutiveLimo mesh's rear end reached x 2.7, over the walk gap)* -> part-built limo body x 8.5..29.5, mesh limo x 5.7..31.4; the walk spur x 0 and the island gap x -4..4 stay free; the rear right doors (part x 14.6, mesh x 10.2) both open onto the **east porch side door x 9..15**; `tests/drivers/clearance.sh` (part + mesh legs) and `tests/metro/test_paths.luau` re-run (§6.3, §22) |
| F2 | pool water top y 125.2 off the 4-stud grid | **Terrain water world y 116..124** (x -24..24, z 8380..8400): all six bounds multiples of 4; water top 1 stud below the F9 deck (125); lip top 124, catch trough top 123.4 (§9.2) |
| F3 | up to 8 client lights per floor band | **<= 3 client lights in total at any time**, `Shadows = false`, range <= 24; the rest of the glow is Neon (§19.2) |
| F4 | 4 stacked 120 x 52 lift buttons cannot fit 844 x 390 | **3 + 2 grid of 64 x 52 pt buttons** (panel 232 x 170 pt) at the right edge, bottom >= 140 pt above the screen bottom; checked with `guiprev --viewport phone --report` (§17) |
| F5 | always-on Neon of F9/F10 rendered as a near-white light box | no Neon part with a face > 24 sq studs anywhere in the hotel, total build-time Neon face area in Shell + SpaFloor + SuiteFloor <= 400 sq studs, Neon colours max channel <= 230 on F9/F10, F9/F10 coves are client-controlled (only booked rooms, only at night), loggia has one 0.4-stud warm strip; re-render night before building (§5.4, §22, §23) |
| F6 | "whole hotel within StreamingMinRadius 128" is false | claim dropped; Shell Atomic; the lift calls `Player:RequestStreamAroundAsync` for the destination landing (§13.6, §20) |
| F7 | physics lifts: replication jitter risk | `GrandPlan.LIFT_MODE = "physics" | "express"`; the express lift (doors, floor counter, fade, PivotTo, same LiftLogic and panel) ships behind the flag; both paths tested in the mock (§13) |
| F8 | overflow rooms shared with strangers | 13 rooms for 12 plots; never shared; a 14th player (only possible if MaxPlayers > 13) gets `FULL` with an honest text and keeps every public area (§12) |
| F9 | metro budget test (28 parts left) | **one fix approved: wow's split, made honest by the critic (CC-11).** `tests/metro/test_build.luau` counts Port Meridian with the hotel **frozen at its pre-rebuild 78 parts** (`#pm - #hotel + 78`) against the unchanged 781 + 4,500 (BASE 781 contains the old hotel, so simply dropping the hotel would hand the metro 78 free parts): today 5,253 -> 5,257 after the 4 sidewalk-gap parts = **24 left**; `tests/grandhotel/test_shell.luau` caps the hotel at 3,250 (§19.1) |
| F10 | DrivePlan pm_hotel is being changed by the drivers fix round | package A re-does pm_hotel only after that round has landed, against the then-current DrivePlan; `tests/drivers/clearance.py` (0 hits) and the 15..70 s ETA test are hard gates (§6.3) |
| F11 | iPhone drive-up speeds / detour | the straight boulevard entry is used; numbers are stated with DrivePlan's real corner limit (12.6 studs/s on the 16-stud fillets) (§6.3) |
| F12 | iPhone honesty: transparent surface | stated as visible area: the cap in §19.3 counts only each part's largest face (today's 9 glass bands: ~33,000 sq studs visible per the judge, not 340,304). *(critic: the spec's own estimate was ~17,000; a recount from the §5/§8-§10 geometry gives ~24,500, ~23,200 after CC-9/CC-10 - inside the 25,000 cap with a cut-list item in reserve)* |

The verdict text was cut after F12 ("The 340,304 sq-stud figure includes the top and bottom faces of the glass ban...");
nothing after that point could be read. *(critic decision: the cut sentence continues F12 itself - handled by the recount in
CC-10; the critic's own pass re-checked the areas the judges covered (drive, budgets, night, lifts, staff, UI) and found the
issues listed in "Critic changes". Nothing is left open and nothing needs the user.)*

---------------------------------------------------------------------------------------------------------------------

## 3. Floor stack

| Level | Local floor top ly (world y) | Clear to | Real? | Model (owner, streaming) | Contents |
|---|---|---|---|---|---|
| Forecourt | road 0.22 / porch 0.5 | canopy underside ly 13 | real | `Forecourt` (A, Default) | drive, islands, canopy, porch |
| L1 Lobby | 0.5 (24.5) | ly 16; atrium void **and the stair hall `STAIR_VOID` x -30..30, lz 72..106** open to ly 28 *(critic CC-7)* | real | `Interior` (B, Atomic) - the name stays `Interior` | vestibule, atrium, reception, concierge, lounge, bar, imperial stair, café, lift hall, bell desk |
| L2 Gallery | 17 (41) | 28 | real (ring only) | part of `Interior` | gallery ring around the atrium void, "Ballroom" / "Meridian Room" doors (decor) |
| F3-F7 | 29, 41, 53, 65, 77 (53..101) | - | **faked** | `Shell` (A) | solid volume + 210 window panes + balconies (guests on balconies in the evening) |
| F8 Skyline | 89 (113) | 100 | real | `SkylineFloor` (B, Atomic) | 8 studios 801-808, Skyline Lounge with the pool window, service |
| F9 Sky Spa | 101 (125) | 112 | real | `SpaFloor` (B, Atomic) | pool loggia, deck, spa (§9) |
| F10 Suites | 113 (137) | 124 | real | `SuiteFloor` (B, Atomic) | 1001-1005, gallery corridor, Lantern Room interior |
| Roof | 126.2 (150.2 = `MetroPlan.HOTEL_ROOF`) | - | real | `Shell` (A) + `RooftopHelipad` (MetroBuilder, Default) | helipad (unchanged), turrets, roof deck, pergola, roof bridge |
| Lifts *(critic CC-13)* | 0.5 / 89 / 101 / 113 / 126.2 | tower ly 0..139 | real | `GrandLifts` (A, Default) with each car its own Atomic model `GrandLiftCar` | tower, 2 cars, landings, `LiftStop` markers, call-prompt parts, skybridge, roof bridge - **not inside the Atomic `Shell`** |

- Slabs are 1 stud thick under each floor top (F8 slab ly 88..89 etc.); the roof slab is ly 125..126.2 and **its top MUST be
  exactly ly 126.2** under the pad (`tests/metro/test_build.luau:73-80`). Pad top ly 127.2 (world 151.2), unchanged.
- The CityPlan record stays as it is (floors 10, width 140, depth 120): the three copies of the height formula
  (CityBuilder, `MetroPlan.HOTEL_ROOF`, CityLife impostor) keep giving 150.2 and nothing else in the world moves.
- Upper floors are 12 studs floor to floor (11 clear). Every real room is >= 20 studs in both directions (camera room).
- Envelopes: F1-F8 x -69.5..69.5; F9 x -60..60 (terraces x +-60..70 on the F8 roof); F10 x -50..50 (terraces x +-50..60 on the
  F9 roof); roof x -50..50. North face of every level at lz 0; south at lz 120.
- Corridors and lift landings are at **lz 56..68 on every floor** (the lift doors are in the east wall at x 69.5..70 or on
  freestanding frames at x 70 on F9/F10/R).

---------------------------------------------------------------------------------------------------------------------

## 4. Pool basin, colonnade and the front-centre bay (the one place where floors interlock)

| Element | Local geometry | World | Owner |
|---|---|---|---|
| Terrain water | x -24..24, lz 0..20, ly 92..100 | x -24..24, z 8380..8400, y 116..124 (`FillBlock(CFrame.new(0,120,8390), Vector3.new(48,8,20), Enum.Material.Water)`) | A |
| Basin structure (CeramicTiles, collidable) | floor slab x -25..25, lz -1..21, ly 91..92; side walls x +-24..25 ly 92..100; back wall lz 20..21 ly 92..100 (holds the pool window); filler below the basin to the F8 floor (ly 89..91) | | A |
| Marble lip (the vanishing edge) | x -24..24, lz -1.2..0, top **ly 100** (= water top, flush) | top y 124 | A |
| Catch trough | x -24..24, lz -4..-1.2, part water top ly 99.4 (SmoothPlastic teal, T 0.35, non-colliding) in a trough box on the cornice | | A |
| Swimmer barrier | x -24..24, lz -1.6..-1.2, ly 100..106, Transparency 1, CanCollide true | | A |
| Colonnade | 6 columns x -25, -15, -5, 5, 15, 25 at lz -3, diameter 3.6: plinth 5 x 3 x 5 ly 31..34, Marble shaft ly 34..89, gold capital ly 89..91.5 | z 8377 | A |
| Entablature | x -29..29, lz -5..0: architrave ly 91.5..93.5, navy frieze ly 93.5..97 with "MERIDIAN GRAND HOTEL" (gold Fondamento, LightInfluence 0, front face), cornice ly 97..**99.4** projecting to lz -6.5 | | A |
| F8 front-centre bay | x -25.5..25.5, lz 0..21 = basin, no access; the F8 facade has no windows there | | A |
| Pool window | the basin back wall at lz 20..21, panel x -12..12, ly 92..99, SmoothPlastic T 0.4 (looks into the water from the Skyline Lounge); flag `GrandPlan.POOL_WINDOW` (false = opaque tiles + aqua Neon strip 0.3 high) [S] | | A builds the panel, B the lounge |
| Loggia | F9 x -24..24, lz 0..20 open to the north (no glass); ceiling = F10 floor slab (ly 112..113); one warm Neon strip 0.4 x 0.4 along the front soffit edge | | A |

Everything in front of the water is lower than the water top (cornice 99.4 < lip 100), so from the pool the water meets the
boulevard. Nothing transparent sits between the camera on the deck and the water (no Glass in the loggia).

---------------------------------------------------------------------------------------------------------------------

## 5. Exterior (package A, model `Shell`, Atomic)

### 5.1 Facade elements
Style "Port Meridian Deco Grand": rusticated limestone podium, colossal colonnade, deep cornice, gold Deco crowns that echo the
Meridian Spire. Symmetric about x = 0. Colours: limestone ivory (232,224,206), light limestone (244,238,224), granite plinth
(120,116,112), bronze `PM.bronze` (128,92,56), navy `PM.navy` (30,44,74), gold `PM.gold` (212,172,86).

| Element | Geometry (local) | Material / colour | Parts (est.) |
|---|---|---|---|
| Plinth course | ring ly 0..2 around the podium | Granite | 4 |
| Podium walls F1-F2 | ly 0..29; north wings x +-21..+-69.5, sides, south; rustication grooves every 3 studs (16 thin dark strips, cut-list item 1) | Limestone ivory | 30 |
| Arched windows | north: 4 per wing (centres x +-27.5, +-38.5, +-49.5, +-60.5), 7 wide: lower pane ly 2..16 + half-cylinder arch d 7 at ly 16 + keystone; F2 window above each (ly 22..26.5); west side 9, east side 7 (no windows at lz 50..74, the lift bay), south 10 = **34 arches** | F1 panes **SmoothPlastic** (46,58,70) T 0.35 (nothing transparent behind them); **F2 panes opaque** (T 0, (40,48,58)) *(critic: the F2 mezzanine behind them is a solid box)*; **all 34** arch transoms named `TransomGlow` (tagged, §5.4) | **136** *(critic recount: 34 x pane + arch + keystone + F2 pane)* |
| Porch screen | x -21..21 at lz 0, bronze-framed glazing ly 0.5..14 with the three openings (revolving door x -4.5..4.5, side doors x -15..-9 and 9..15), transom "M · G" monogram ly 14..16 | Metal bronze + SmoothPlastic T 0.35 | 8 |
| Revolving door | drum centre (0, 4.5), d 9: 2 curved glass side walls (collidable, x +-3.9..4.5), canopy disc ly 9.5, **4 wings = PropFx `spin` Model root, `FxAxis = "y"`, `FxIdle = "on"`, `FxRate` 0.6, wings non-collidable** (the doorway stays open) | SmoothPlastic T 0.5, bronze | 8 |
| Side doors | x 9..15 and -15..-9: 2 glass leaves each, **non-collidable**; HotelController slides them 2.6 studs apart (local, client) while any character is within 8 studs | SmoothPlastic T 0.4 | 4 |
| Podium cornice | ly 29..31, projecting 1.5 (sides/back) / 2.5 (north) | Limestone light | 4 |
| Royal balcony | x -29..29, lz -7.5..0, ly 29..31 + stone balustrade to ly 33; carries the column plinths | Limestone light | 3 |
| Body F3-F7 | solid `Volume` x -69.5..69.5, lz 0..120, ly 29..89 (behind the podium cornice) | Limestone ivory | 1 |
| Window panes F3-F7 | per floor: north wings 8 (x +-31.5, +-41.5, +-51.5, +-61.5), centre bay 5 behind the columns (x -20..20 step 10), west 12, east 10 (skips lz 50..74), south 7 double (12 wide, x -54..54 step 18); 6 x 7.5 at floor + 2.5..10, proud 0.3; **named `Windows`**, SmoothPlastic, tone per pane by `Kit.hash`: dark glass (58,64,72) 60 %, sheer curtain (150,146,136) 30 %, drawn curtain (122,104,86) 10 % = 42 per floor x 5 = **210** | SmoothPlastic, opaque | 210 |
| Piers + quoins | full-height piers F3-F7 between window pairs (north 10, south 8, sides 2 x 10), 4 corner quoins | Limestone light, proud 0.8 | 42 |
| String courses | one per face per floor F3-F7 | Limestone light | 20 |
| Balconies | F3 (piano nobile) and F7: north wings x +-27..+-67 and sides lz 10..46 / 74..110: slab + balustrade + rail; window hoods over the F3 north windows | Limestone light, bronze rail | 44 |
| Colonnade + entablature | §4; plus 6 column uplights (small Neon cubes at the plinths, tagged trims) | Marble, gold Metal (not Foil: Cycles renders Foil white-hot, Studio check §24) | 27 |
| F8 attic storey (real rooms) | French windows x 9 tall (ly 90..99): north 2 per studio, **8 wide** *(critic CC-9: 10-wide windows 9 apart overlapped, and 802/803 ran behind the entablature end at x +-29)*: 801 x -64, -54; 802 -43.5, -33.5; 803 33.5, 43.5; 804 54, 64; south 2 per studio, 10 wide (805: -62, -49; 806: -34, -21; 807: 21, 34; 808: 49, 62), corner studios 2 on the side face (801, 804, 805, 808), 8 wide = **24 windows**, each pane + bronze frame + Juliet rail; piers between; no window pane within x -29.5..29.5 on the north face | panes **SmoothPlastic** (60,74,84) T 0.35 Reflectance 0.15, **not tagged** | 92 |
| Main cornice | ly 101..103.4 over the wings x +-25..+-69.5 (north), sides, south; gold line under it (tagged trim) | Limestone light + Metal gold | 10 |
| F9 envelope | x +-60: north glass x +-24..+-60 (ly 101..112) with bronze mullions every 6; side walls glass lz 0..56, stone lz 56..120; south: stone + spire glass x -6..60 | SmoothPlastic (70,120,130) T 0.35 (pool near: no Glass) | 45 |
| F9 terraces | x +-60..70, lz 0..120 on the F8 roof: teak deck, balustrade SmoothPlastic T 0.6 + bronze rail, granite planters | WoodPlanks (146,112,80) | 20 |
| F10 envelope | x +-50: north glass wall x -50..50 with bronze mullions every 5; side glass except the corridor ends (lz 56..68 stone); south glass | SmoothPlastic (60,74,84) T 0.3 | 45 |
| F10 terraces | x +-50..60 on the F9 roof (west lz 0..56 = penthouse terrace, east lz 0..50 = Panorama terrace, east lz 50..72 = skybridge landing) | as F9 | 15 |
| Roof | slab x -50..50, lz 0..120, ly 125..126.2; bronze parapet 1.2 (outside the rotor circle); gold crown line (tagged trim); compass-rose inlay d 14 at (0, 90); 6 cypress planters at lz 117 (x -40..40 step 16); Sky Lounge pergola x 26..48, lz 76..100 with 2 sofas (Seats) | Limestone, Metal, Foil-free gold Metal | 38 |
| Turrets | x +-38..+-50, lz 0..12, ly 126.2..158: stone base, gold-glass lantern ly 128..142 (Glass (200,168,104) T 0.25), 4 gold fins (tagged trims, GlowColor (200,150,80)), cap, 2 gold steps, finial mast to ly 158, red aviation light (small Neon). **West turret = the Lantern Room** (interior by B) | Limestone, Glass, Metal gold | 22 |
| Panoramic lift tower **-> model `GrandLifts`, not Shell** *(critic CC-13)* | x 70..81, lz 54..70, **ly 0..139** *(critic CC-6: a car at stop R has its roof at 126.2 + 10 + 0.4 = 136.6, above the old 135 cap)*: 4 bronze posts, 3 full-height panes (north, east, south; SmoothPlastic T 0.6, **not Glass**: glass-behind-glass rule), floor bands at each stop, cap ly 138..139; 2 cabins (§13.2) built **anchored**, each its own Atomic model `GrandLiftCar`, `LiftGuide` per car; landing door frames + 2 leaves per car per stop (5 stops); F10 skybridge x 60..70, lz 56..68 at ly 113 (deck + 2 rails); roof bridge x 50..70, lz 56..68 at ly 126.2 | Metal bronze, SmoothPlastic | ~100 in `GrandLifts` (cap 120) |
| Slabs + volumes | F1 `Floor` (x -70..70, ly 0..0.5, lz 0..120, **name `Floor`, building-frame orientation** - entrances.py needs it), F1 ceiling ly 16..17 outside the gallery ring **and outside `STAIR_VOID` (x -30..30, lz 72..106)**, F2 mezzanine solid ly 17..28 outside x -30..30 / lz 18..**106** *(critic CC-7: the old boxes filled the space the imperial stair's side flights climb through - lz 78..92 from ly 9 to 17, head room to ly 22)*, atrium + stair-hall roof ly 28..29 over x -30..30, lz 18..106 (laylight frame by B over the void x -24..24, lz 24..72), F8 slab, F9 slab (2 pieces around the basin), F10 slab | Limestone / Concrete | 21 |
| Exterior signs | frieze (in the entablature), side fascias of the canopy are in `Forecourt` | | 2 |
| Pool basin, lip, trough + trough water, swimmer barrier, pool window panel, filler (§4), loggia strip | | | 12 |
| **Shell total** | | | **~865 (cap 950)** *(critic recount: the lead's table summed to ~896 with 110 arched-window parts and the 71-part lift tower inside; recounted 136 arches + pool 12, lift tower moved to `GrandLifts`)* |

Why it no longer reads as an office block: punched windows with curtains instead of glass ribbons; a hierarchy (centre
colonnade, wings with balconies, corner quoins, rusticated base, stepped crown) instead of four identical faces; a 60 x 22
marquee instead of a 20-stud canopy; doors, flags, planters and a doorman; gold turrets framing the helipad.

### 5.2 Signs (ASCII + `· É ► ◄ –` only)
| Sign | Where | Text |
|---|---|---|
| Frieze | entablature front, ly 93.5..97 | `MERIDIAN GRAND HOTEL` (keeps `tests/metro/test_build.luau:196-202` green) |
| Marquee fascia | canopy front (Forecourt) | `MERIDIAN GRAND`; both side fascias `HOTEL` |
| Porch transom | above the revolving door | `M · G` |
| Lobby logo wall | behind reception (B) | `MERIDIAN GRAND HOTEL` / `Reception` |
| Lift hall (B) | wayfinding | `Panorama Lifts · 8 Skyline · 9 Sky Spa · 10 Suites · R Helipad` |
| Bar / café / spa (B) | lettering | `THE MERIDIAN BAR`, `CAFE MERIDIAN`, `SKY SPA`, `FINNISH SAUNA`, `HAMMAM`, `COLD PLUNGE`, `STAFF ONLY` |
| Room plates (B) | doors | `1001 · Royal Penthouse`, `1002 · Panorama Suite`, `1003 · Spire Suite`, `1004 · Deluxe King`, `1005 · Deluxe King`, `801 · Skyline Studio` ... `808 · Skyline Studio` |
| Roof (A) | at the bridge | `Lifts ►` |

### 5.3 Materials rule (Glass)
`Enum.Material.Glass` hides transparent things behind it and does not refract on mobile (research §0 #3-4). Glass is allowed
**only** for the turret lanterns (opaque furniture behind) - everything else that is see-through is SmoothPlastic +
Transparency. **MUST:** no part with Material Glass within 12 studs (box distance) of the Terrain pool block or of any part
whose name ends in `Water` (test §22).

### 5.4 Night lighting (no new server light)
- **Window panes F3-F7 (210, named `Windows`)**: tagged `MetroNightGlow` with `GlowColor` = **(146,110,70)** with the same
  contract as MetroBuilder's local `glowTag` (`p:SetAttribute("GlowColor", c)` + `CollectionService:AddTag(p, "MetroNightGlow")`). CityLife lights 45 % by its hash out of the box.
- **Lived-in pattern (graft G5)**: A adds the hook `CityLife.setLit(p: BasePart, lit: boolean?)` (§18.5). B's HotelController
  calls it for the 210 panes (each carries attribute `GrandWindow = <index 1..210>`) once per company-hour slot while it is
  night: pane i is lit if `GuestPlan.hash(day .. ":" .. slot .. ":" .. i) % 100 < share`, with share **60 % for
  18:12-22:00, 40 % for 22:00-01:00, 15 % for 01:00-06:00, 30 % for 06:00-06:18** (`GrandPlan.LIT_SHARE`). About 10-40
  panes change per slot. Without the hook (or before B lands) the static 45 % stays: graceful.
- **Always-lit trims** (tagged, names outside `WINDOW_PARTS`, GlowColor (240,190,120) unless noted): **34** arch
  `TransomGlow` parts *(critic: the lead's "20" did not match the 34 arches of §5.1)*, 6 column uplights, main-cornice gold
  line (4), roof crown line (4), turret fins (8, (200,150,80)), 24 marquee bulbs + 3 canopy soffit strips + 2 island lanterns
  (Forecourt). **~295 tagged parts on the hotel** (Port Meridian 198 -> ~493).
- **Never tag real glass** (F8 windows, F9/F10 glazing, porch screen, lift panes): `nightLook` would turn it into opaque Neon
  seen from inside. **Never tag anything inside B's floor models.**
- **Booked rooms glow (G5)**: every studio/suite has 1-2 cove strips (Neon colour (204,152,96), 0.3 x 0.3 studs) that B
  builds as SmoothPlastic; HotelController switches them to Neon **only at night and only for rooms whose `RoomDoor` has
  `Booked = true`**. From the street you see exactly which rooms real players have.
- **F5 must-fix (light box)**: no build-time Neon part with any face > 24 sq studs anywhere in the hotel; total build-time
  Neon largest-face area in Shell + SpaFloor + SuiteFloor <= 400 sq studs; on F9/F10 Neon colours have max channel <= 230;
  the pool glow is 2 underwater strips 0.4 high (colour (40,140,150)) on the long basin walls; the loggia has one 0.4 x 0.4
  warm strip. The atrium laylight is SmoothPlastic cream (232,214,170) behind a bronze grid, not Neon.
- **Real lights stay 3** (today: 2 lobby + 1 helipad edge [M]): chandelier PointLight (B, ly 22.5 at (0, 48), Range 40,
  Brightness 1.2), canopy soffit PointLight (A, (0, 12.6, -11), Range 30, Brightness 1.0), helipad edge light (unchanged,
  `MetroBuilder.helipad`). All `Shadows = false`, all through the budgeted CityBuilder `light()` (= `K.light`), never
  `Kit.light`. `towers()` keeps its position in the build order, so Port Meridian's first-come allocation (40/40) is
  identical and no street lamp loses its light.

### 5.5 Far impostor (A, CityLifeController additive)
From the arrival plaza (620-690 studs) the hotel is beyond the 512 target radius and the client shows the impostor. Replace the
single glass box by 6 parts from `GrandPlan.IMPOSTOR` (world coordinates; still ONE impostor entry, so
`tests/metro/test_life.luau:315-318` keeps `#Plan.LOTS + 5`):

| Part name | World box | Colour / material |
|---|---|---|
| `Impostor` (main, registerGlow as today) | x -70..70, z 8380..8500, y 24..125 | (232,224,206) Limestone |
| `ImpostorSetback` | x -60..60, z 8380..8500, y 125..137 | (196,208,214) SmoothPlastic |
| `ImpostorSetback` | x -50..50, z 8380..8500, y 137..150.2 | (196,208,214) SmoothPlastic |
| `ImpostorCrown` | x -50..-38, z 8380..8392, y 150.2..182 | (212,172,86) Metal |
| `ImpostorCrown` | x 38..50, z 8380..8392, y 150.2..182 | (212,172,86) Metal |
| `ImpostorFrieze` | x -29..29, z 8374..8380, y 115.5..123.4 | (30,44,74) Metal |

The `present` check stays `cityPath({"PortMeridian","Hotel_intl_hotel","Shell"})`; with Shell Atomic it has >= 3 children
whenever it is streamed in.

---------------------------------------------------------------------------------------------------------------------

## 6. Porte-cochère, drive, limo drop-off, doorman, luggage

### 6.1 The drive (one-way horseshoe; the boulevard flows into the hotel)
Measured context [M]: Harbour Street asphalt world z 8320..8352 (lz -60..-28), south sidewalk z 8352..8360 (lz -28..-20, one
part x -700..700), boulevard southbound lanes x -31 / -45 (outer -45), northbound +31 / +45, median ends at z 8319, zebras
x +-55..61 at z 8348..8351, signal post at (53.4, 8353.4), free forecourt z 8360..8380 (lz -20..0).

Path of a limousine (right-hand traffic, hotel on the passenger side):
1. southbound in the outer lane x -45, straight across Harbour Street (the junction becomes a crossroads whose south arm is
   the hotel drive; CityLife cars do not yield - cosmetic, §24),
2. through the west sidewalk gap, left turn on the 16-stud fillet into the drive lane at lz -11.5 heading +X,
3. **stop A: car pivot (19, 0.22, -11.5)** = world (19, 24.22, 8368.5), heading +X *(critic CC-1: was 16)*; part-built limo body
   x 8.5..29.5, mesh limo x 5.68..31.44, both lz -15.2..-7.8,
4. drives on, left turn at x +45 through the east gap, north into the boulevard's northbound outer lane x +45.

| Piece | Local geometry | Notes |
|---|---|---|
| Drive slab | granite setts `Cobblestone` (150,140,128), top ly 0.22, x -54..54, lz -20..-6.6, collidable, top inside y 23.5..25.7 | world_check sees no holes |
| Mouths | sidewalk gaps x -54..-36 and x 36..52.6, lz -28..-20, paved with the same setts at ly 0.22 | via `MetroPlan` Harbour Street `gaps = {{1,-54,-36},{1,36,52.6}}`; the signal post at x 53.1..53.7 stays on the sidewalk (mesh-limo sweep gap 1.0, part 1.8, measured). **A gap cuts the CityLife walk line (lay-by semantics, §0.3)** -> A also adds, in `MetroPlan` `pmPaths`, one walk path per mouth across the setts at road level: `add(2.5, {v(-54.5, 8356, Wk), v(-53.5, 8356, City.ROAD_TOP), v(-36.5, 8356, City.ROAD_TOP), v(-35.5, 8356, Wk)})` and the same for x 35.5 / 36.5 / 52.1 / 53.1 (`GrandPlan.DRIVE.mouthWalkWorld`) *(critic CC-3)* |
| ACCESS points | (+-45, 8356) world added to `MetroPlan` ACCESS | no lamp or tree within 7 studs (generator rule) |
| Islands | x -18..-4 and 4..18, lz -20..-16.6, kerb top ly 0.5 (below the clearance band); flower beds + 1 bronze lantern each at (+-11, -18.3); **all island furniture non-collidable decor, <= 1 stud high, except the columns** | pedestrian gap x -4..4 (walk spur) |
| Canopy columns | 4 bronze, d 2, at (+-8, -18.3), (+-16, -18.3) on the islands; body margin to the limo 2.1 | the only collidable things beside the lane |
| Lane | centre lz -11.5; limo 21 x 7.4 -> island edge margin 1.4, porch kerb margin 1.2 on the straight. **Measured sweep of all 14 `pm_hotel` legs** (critic, `critic2/sweep2.py legs19.txt`): islands 1.4 (both looks), canopy columns 2.1, signal post 1.8 / 1.0 (part / mesh); on the two turns the body overhangs the porch kerb (0.28 high, below the clearance band) up to lz -5.2 (part) / **lz -3.8 (mesh)** near x +-(14..40) | `tests/drivers/clearance.sh` (part + `#mesh` legs) decides |
| Porch | x -30..30, lz -6.6..0, top ly 0.5 (0.28 kerb), Marble; red runner carpets x -4..4 and x 9..15 from the kerb to the doors (flat decor); 4 granite urns with topiary balls at x +-24, +-28, **lz -1.5** (d 2); 2 bronze lanterns at x +-20, **lz -0.8**, against the facade *(critic CC-2: with the urns at lz -3 the mesh-limo legs hit urn x 28 and both lanterns - `clearance.py`: 14 of 28 legs failed; at the new positions 28 / 28 pass)*. **MUST: on the porch nothing collidable and nothing taller than 0.6 at lz < -2.6 (`GrandPlan.DRIVE.porchKeepOutZ`); on the drive slab nothing but flat markings; on the islands only the canopy columns are collidable (the sweep keeps 1.4 off the island edge)** | flat entry, no steps |
| Marquee canopy | cantilevered, x -30..30, lz -22..0, underside ly 13 (12.8 above the road; the limo band is 0.6..5.6, a mesh limo <= 13 high fits), roof ly 13..15.6; navy fascia ly 13..16.4 with gold `MERIDIAN GRAND`, side fascias `HOTEL`; 3 soffit strips (tagged); **24 marquee bulbs** (Neon balls d 0.6, tagged, along the fascia bottom edge x -28..28); 4 tie rods to the facade at ly 26 | the canopy PointLight hangs at (0, 12.6, -11) |
| Facade flags | 4 angled poles on the podium face at x +-10, +-18 (ly 21 -> 26, 8.6 out), navy / gold / navy / teal Fabric | above the canopy; the canopy's 4 tie rods run at x +-4 and +-26 (never at a flag pole) *(critic)* |
| Zebra on the setts | white stripes x -2..2 across the lane | walk spur crossing |

The walk spur `(0,8356)->(0,8370)` and the portal `(0,8376)` stay unchanged [M]: walkers cross the islands' gap and the lane
at x 0 and reach the revolving door. **MUST:** at stop A neither limo look covers x -4..4 (part body x >= 8.5, mesh x >= 5.68).
CityLife walkers and the moving limo do not see each other (walkers may cross through a passing car - cosmetic, as everywhere
in Port Meridian; §24).

### 6.2 Founder drop-off point and the welcome flag
- DrivePlan door (founder root after getting out): **(12, 3.5, -4) facing +Z** = world (12, 27.5, 8376), in front of the east
  side door (x 9..15). The rear right door at stop A is at x 19 - 4.4 = **14.6** (part-built) or 19 - 8.8 = **10.2** (mesh),
  lz -7.8: both inside the east side door span; the founder appears 2.6 / 1.8 studs beside it.
- **Welcome flag (G12)**: when the local player has a booking (`HotelRoom` attribute), HotelController recolours the
  east-most facade flag to his company accent colour (one local Color write; reverts on checkout).

### 6.3 DrivePlan `pm_hotel` (package A, after the drivers fix round has landed)
```lua
-- in metroPlaces(), replacing the current pm_hotel line (DrivePlan.module.luau:413-416 today)
table.insert(out, kerbPlace("pm_hotel", if hotel then hotel.name else "Meridian Grand Hotel", "the Meridian Grand", "abroad", "hotel",
	Vector3.new(19, RT, 8368.5), 1, 0,   -- critic CC-1: 19 (mesh limo rear end at x 5.68, clear of the walk gap)
	{ Vector3.new(-45, RT, 8250), Vector3.new(-45, RT, 8368.5) },   -- in: boulevard SB outer lane (snaps to the boulevard, 86 from Harbour St), corner -> fillet 16
	{ Vector3.new(45, RT, 8368.5), Vector3.new(45, RT, 8250) },     -- out: corner -> fillet, boulevard NB outer lane
	CFrame.lookAt(Vector3.new(12, WT + 3.025, 8376), Vector3.new(12, WT + 3.025, 8390)), "pm"))
```
- `WT + 3.025` = 27.5 (porch top 0.5 + 3). The first in-point (-45, 8250) is 45 from the boulevard axis and 86 from Harbour
  Street's, so `snap` picks the boulevard edge; the last out-point likewise.
- Corner speed on the 16-stud fillets: sqrt(10 x 16) = **12.6 studs/s**; access cruise 18. **Measured with this exact place in a
  sandbox (critic, `critic2/probe_hotel.luau` on `harness/.gen_ghcrit19`)**: all 14 legs to / from `pm_hotel` route (NOLEG 0);
  `pm_limo -> pm_hotel` 865.8 studs / **40.5 s**; `pm_airport -> pm_hotel` 59.8 s; `pm_depot -> pm_hotel` 58.4 s; `pm_hotel ->
  pm_airport` 33.3 s - the test window is 15..70 s. `clearance.py` against a world with the §6.1 forecourt: 28 / 28 legs clear.
- **Gates (all MUST be green before A finishes):** `tests/drivers/test_plan.luau`, `test_service.luau`, `test_client.luau`
  (drop at `place.door` +-0.6, limo stand -> hotel 15..70 s), `tests/drivers/clearance.sh` (limo 21 x 7.4, band 0.6..5.6:
  **0 hits** along both legs and at the stop), `tests/metro/test_paths.luau` (spur vs canopy columns and island kerbs).
- If DrivePlan's router cannot start the approach on the boulevard SB lane (NO_ROUTE), **option B (G12)**: east entry,
  stop at (14, RT, 8368.5) heading -X, the founder gets out on the street side and the doorman walks round the car; the
  east side door then stays the door point. A documents which option shipped.
- A second limousine reaching stop A while another stands there overlaps it visually (client cars, no physics). The window is
  ~4 s for a drop-off (`DROP_PAUSE`) but **up to 90 s for a pick-up** (the car waits for its rider). **Decision (critic,
  answering §25 Q2): accepted as cosmetic for this build** - every shared kerb place in the game behaves the same today
  (e.g. `airport_departures`), the drivers' fix round is still running, and a queue is DriverService logic. A per-place
  "second bay" (`pm_hotel` bay B at pivot (-17, RT, 8368.5): part body x -27.5..-6.5, mesh x -30.3..-4.6, clear of the walk gap) is noted for a later
  drivers-wide round together with the airport kerbs; this build files nothing.
- The ExecutiveLimo mesh hook is DriveController's (`ReplicatedStorage.Assets.Vehicles.ExecutiveLimo`, part-built
  fallback) [M]. The canopy clears any car <= 12.8 high; nothing else in the hotel depends on the car model.

### 6.4 Doorman, bellhop, luggage - cast
| Who | Post (local, floor ly 0.5) | Faces |
|---|---|---|
| Doorman A (day 07-19) / night porter (19-07) | D1 (6, -2.5) | north (-Z) |
| Doorman B (day 07-19) | D2 (-6, -2.5) | north |
| Limo cue target | DL (15, -5.6): beside the rear right door of either look at stop A (part-built x 14.6, mesh x 10.2 - the doorman stands by the opened door's hinge side), 3 studs east of the founder's drop point; the mesh / part sweeps pass >= 0.4 from DL only while the car leaves, when the doorman is already walking back (T + 4) | west/north towards the car door |
| Bellhop + cart | BS (18, 3.2) at the bell stand inside the vestibule | north |

### 6.5 Doorman timeline from the published ride (graft G2)
HotelController watches `ReplicatedStorage.CompanyDrivers` (DescendantAdded + AttributeChanged on `Plan`) for ride folders with
`To == "pm_hotel"` (drop-offs) or `Pickup == "pm_hotel"` (pick-ups). For a drop-off it decodes
`Drive.decode(f:GetAttribute("Plan"), plot)` (`plot` = `Plot` attribute, nil when 0), takes the segment whose `to ==
"pm_hotel"` and computes the stop time **T = Drive.segEnd(sg, plot)** (server time). Everyone's client computes the same T.

| Time | Doorman (D1 or the night porter) | Bellhop | Founder |
|---|---|---|---|
| T - 6 | head turns to the drive (`lookYaw`) | cart out to (20, -3) (walk 4 studs/s, `push`) | car on the drive |
| T - 3.5 | walks D1 -> DL (9.5 studs at 4 studs/s = 2.4 s, pose walk) | waits | |
| T - 1.1 | at DL, pose `reach` (opening the door) until T + 2.5 | | car stops at T |
| T + 1.2 | bubble "Welcome to the Meridian Grand, <DisplayName>!" (3 s) | a client-only suitcase appears at the car's rear (x 7.9 part-built / 5.1 mesh, lz -11.5; `DriveController.findMesh()` tells which) and moves onto the cart (0.6 s) | DriverService places him at (12, 27.5, 8376) |
| T + 4 | walks back to D1, pose `present` | pushes the cart in: BS route (§14.5) | walks in through the east side door |

- Pick-up (`Pickup == "pm_hotel"`, State `waiting`): the doorman walks to DL when the car stops and plays `reach` when the
  rider comes within 6 studs.
- Only rides whose stop lies within the next 30 s are processed (cheap); cue at most one ride at a time (nearest T).
- Shift: 07:00-19:00 doorman A, 19:00-07:00 the night porter; doorman B never does cues.

---------------------------------------------------------------------------------------------------------------------

## 7. Lobby F1 + gallery L2 (package B, model `Interior`, Atomic) - plan: `out/grandhotel_design/plan_lobby.png`

Keep-free points (CityPlan, unchanged, world test "no destination point inside a solid"): door **DX (0, -5)** on the porch,
lobby **LP (-35, 20)** (helicopter arrival + AirTrafficController's local "VIP helicopter" prompt; nothing collidable within 4
studs), reception **RX (0, 45)** (on the atrium rug), plus entrances.py's lobby probe **(-20, 12)** in the vestibule (keep 2
studs clear) and its reception probe = the `ReceptionistPost`.

### 7.1 Zones (local x, lz; floor ly 0.5)
| Zone | Rect | Contents (server parts unless *client*) | Parts (est.) |
|---|---|---|---|
| Vestibule | x -24..24, lz 0..24 | gold compass-rose inlay (Foil-free gold Metal disc d 12 + thin Neon ring) at (0, 12); 2 granite urns at the side doors; ceiling cove | 8 |
| Atrium | x -24..24, lz 24..72, void to ly 28 | 8 marble columns d 2.4 at x +-24, lz 24/40/56/72 (shaft + gold capital + base); **3-tier chandelier** centred (0, 48) hanging ly 28 -> 17: gold crown, chain, three glass drums d 16 / 11 / 6 each around a 0.4-thick Neon ring (warm (255,214,150)), 8 glass drops, finial - 17 parts, the server PointLight in the middle tier (ly 22.5); round **rug d 30** at (0, 48) (Carpet burgundy (110,30,40) + gold border ring); **flower table** d 6 at (0, 64) with a big arrangement (5 coloured balls + greens); **laylight** at the void ceiling ly 27.6: cream SmoothPlastic panel 48 x 48 behind a bronze 4 x 4 grid | 75 |
| Imperial stair | x -28..28, lz 72..120 | centre flight x -6..6, lz 76..92, ly 0.5 -> 9; landing x -20..20, lz 92..104 at ly 9 (slab ly 8..9, **walkable underneath: 7.5 clear**); side flights x +-12..20 from the landing (lz 92, ly 9) back to the gallery (lz 78, ly 17). Each flight = one invisible collidable **thin rotated ramp slab** (0.5 thick, so the space under it stays free) + decor treads (RoomKitsHotel pattern) + brass handrails + runner carpet; 4 newel posts with bronze globes at (+-6, 76), (+-20, 92). **The stair hall `GrandPlan.STAIR_VOID` (x -30..30, lz 72..106) is open up to ly 28** - no F1 ceiling slab and no F2 mezzanine solid there (A, §5.1); the gallery balustrade continues along its edges *(critic CC-7)* | 55 |
| Gallery L2 | ring x -30..30, lz 18..78 minus the void x -24..24, lz 24..72, floor ly 17 | glass balustrade (SmoothPlastic T 0.5) + bronze rail on the void edge, 4 benches (Seats) at (+-27, 32), (+-27, 64), 4 framed artworks (`Kit.artwork`), 2 bronze double doors `Ballroom` (-30, 48) and `Meridian Room` (30, 48) (decor, no prompt) | 30 |
| Lounge | x -69.5..-28, lz 0..74 | 3 sofa groups on rugs: (-55, 14) two sofas facing each other + table; (-52, 40) sofa facing the **fireplace** on the west wall (x -69.5..-67, lz 34..46: stone surround + Neon firebox + `Kit.flame` Fire, disabled at build) + 2 armchairs + table; (-55, 62) two sofas + table; palms at (-66, 4), (-66, 71), (-40, 3) | 60 |
| Concierge | desk x -41..-29, lz 25..28 (front face lz 25), in the lounge | walnut desk, brass globe, bell, "CONCIERGE" plate; **post CO (-35, 30)** behind the desk; prompt CQ (-35, 24.5); keeps LP (-35, 20) free | 8 |
| Reception | x 28..56, lz 18..50 | 3-segment walnut desk x 36..52, lz 30..33 (marble top, bronze kick plate, 3 monitors, bell); staff zone lz 33..40, staff gap x 52..56; **key wall x 34..54, lz 40..42** (backlit cubbies like `RoomKitsHotel` keyGrid) with a **custom aquarium** x 40..48 (opaque deep-blue water card, SmoothPlastic T 0.5 front pane, Neon strip 0.3 on top, 3 fish as a PropFx `slider` group with `FxIdle = "on"`; **not** `Kit.aquarium`, which puts Glass over water) and the `MERIDIAN GRAND HOTEL / Reception` lettering above; key-card printer (PropFx `paper`) at (50, 31.5); **`ReceptionistPost`** (invisible 2 x 5 x 1, `CityPost = "hotel_reception"`, `BuildingId = "intl_hotel"`, identity rotation) at (44, 3.5, 36); check-in prompt part at (44, 3.5, 29) | 35 |
| Bell desk + waiting | x 24..69.5, lz 0..18 (the bell stand itself stands in the vestibule east at (17..19.5, 5..7)) | bell stand with a stool, **brass luggage cart** (6 parts: deck, 2 uprights, hanger bar, bumper, wheels; never the trademarked name) parked at (20, 3), armchair pair (40..48, 8..12), palm (66, 3) | 16 |
| Lounge east | x 28..56, lz 50..80 | 4 armchairs at (40, 58), (50, 58), (40, 70), (50, 70) around a low table | 12 |
| Lift hall | x 56..69.5, lz 46..80 | marble floor, wayfinding sign, 2 sconces, call prompt LC (64, 62), security post SE (59, 50); landing doors in the east wall at lz 56.25..60.25 (car 1) and 63.75..67.75 (car 2) (A) | 8 |
| The Meridian Bar | x -69.5..-28, lz 76..120; planter wall at lz 75 with openings x -60..-50 and -48..-42 | curved counter x -62..-38, lz 104..107 (3 segments), 6 leather stools (Seats) at lz 102.5, back bar x -66..-34, lz 114..117 with Neon-lit shelves (thin strips) and 12 coloured "juice and syrup" carafes (fruit colours, no wine / spirit shapes or labels) and a plate `MOCKTAILS · JUICES · COFFEE` *(critic CC-22: keeps the experience free of alcohol references for its content-maturity questionnaire; the user is a teenager)*; 3 lounge tables at (-64, 82), (-64, 93), (-56, 87.5) with 2-3 lounge chairs (`Kit.loungeChair` Seats); **grand piano** x -40..-30, lz 80..88 (body, wedge lid, key strip) + bench, pianist post PI (-35, 90.5) facing north; order prompt BQ (-50, 103) | 75 |
| Café Meridian | x 28..69.5, lz 80..120; north wall lz 80 with the opening x 30..46 | glass pastry counter x 36..58, lz 108..111 with "cakes", café host post CH (47, 114); **breakfast buffet** x 64..67, lz 86..104 (food decor toggled *client-side* 07:00-10:30); 4 bistro tables at (42, 88), (52, 88), (42, 98), (52, 98) with 2 chairs each (Seats); coffee machine (`Kit.steamEmitter` puff, `HotelSteam`); breakfast prompt at the buffet (62, 3.5, 95) | 40 |
| Walls, ceilings, coves | partitions above, ceiling coves, 12 thin Neon sconces | | 20 |
| Staff doors | `STAFF ONLY` door SW (0, 118) in the back wall (under/behind the landing), kitchen door SX (62, 118) | NPC portals (staff appear / vanish) | 4 |
| **Interior total** | | | **~410 (cap 430)** |

Rugs: atrium d 30, runner from the revolving door to the stair, one under each lounge group, one in the bar.
Seats (Seats are the only sitting method; default sit, no animation id): 6 sofas (2 Seats each), 4+2 armchairs, 6 stools,
8 lounge chairs, 8 bistro chairs, 4 gallery benches, piano bench = ~44.

### 7.2 Lobby prompts (server, `Public = true`, `RequiresLineOfSight = false` unless noted)
| Prompt | Part at | ActionText / ObjectText | HotelAction | Distance / hold | Key |
|---|---|---|---|---|---|
| CK | (44, 3.5, 29) | "Check in" / "Meridian Grand Reception" | `checkin` | 10 / 0.3 | default (E / ButtonX) |
| CQ | (-35, 3.5, 24.5) | "Ask concierge" / "Limousine & city" | `concierge` | 8 / 0.3 | keyboard **F**, gamepad **default (ButtonX)** *(critic CC-14: `PhoneController` toggles the phone on ButtonY - a ButtonY prompt could open the phone at the same time; on a gamepad `OnePerButton` then shows the nearer of CQ / the heli prompt, which is fine)* |
| BQ | (-50, 3.5, 103) | "Order a mocktail" / "The Meridian Bar" | `bar` | 8 / 0.3 | default |
| BB | (62, 3.5, 95) | "Take breakfast" / "Cafe Meridian" | `breakfast` | 8 / 0.3 | default |
| LC | (64, 3.5, 62) | "Call lift" / "Panorama Lifts" | `liftcall`, `Stop = "L"` | 10 / 0 | default |

All five lie below world y 70, so `agents/world/entrances.py` (--lift none) must reach them on foot from the street - they are
on the lobby floor, so it does.

---------------------------------------------------------------------------------------------------------------------

## 8. F8 Skyline floor (package B, model `SkylineFloor`, Atomic) - plan: `plan_guest.png`

| Zone | Rect (local) | Door | Notes |
|---|---|---|---|
| 801 / 802 / 803 / 804 Skyline Studio | x -69.5..-47.5 / -47.5..-25.5 / 25.5..47.5 / 47.5..69.5, lz 0..56 (22 x 56) | on lz 56 at x -58.5 / -36.5 / 36.5 / 58.5 (4 wide) | north: the boulevard; 801/804 also a side window |
| Pool basin | x -25.5..25.5, lz 0..21 | - | A's structure, no access |
| Skyline Lounge (shared) | x -25.5..25.5, lz 21..56 | opening x -8..8 on lz 56 | **pool window** in the basin wall (x -12..12, ly 92..99): swimmers seen from below; 2 sofas (x -18..-6 and 6..18 at lz 30..32.5) facing the window; unstaffed "Skyline Bar" counter x 12..22, lz 47..49.5 (decor); 2 floor lamps, plants (~40 parts) |
| Corridor | x -69.5..69.5, lz 56..68 | lift doors at x 69.5 | carpet runner, 8 sconces, 4 artworks, ceiling cove; call prompt L8 at (64, 62), part at ly 92.5 |
| 805 / 806 / 807 / 808 Skyline Studio | x -69.5..-41.5 / -41.5..-14 / 14..41.5 / 41.5..69.5, lz 68..120 (28 / 27.5 / 27.5 / 28 x 52) | on lz 68 at x -55.5 / -27.75 / 27.75 / 55.5 | south: the Meridian Spire and the harbour |
| Service | x -14..14, lz 68..120 | door x -2..2 on lz 68 | linen shelves x -13.4..-9, pantry counter x 9..13.4 (lz 72..96), housekeeping cart home (0, 76), **service-lift portal** W8 (0, 116) (NPC portal: doors + floor counter, no cabin) |

### 8.1 Skyline Studio fixtures (every studio; north type shown, south type mirrored along lz; <= 52 parts each)
- **Door set** (A-side corridor wall is B's partition): leaf as PropFx `hinge` root (`FxTravel` 1.4 rad), frame, key reader with a
  status dot (client colour), gold number plate (SurfaceGui, MaxDistance 30), invisible collidable `DoorBlock` (5).
- **King bed** centred in the room at lz 18..28 (north type) / 92..102 (south): frame, mattress, duvet, 2 pillows,
  headboard with a Neon backlight strip, under-bed Neon strip (mood colours, client) (7); 2 nightstands + lamps (4).
- **Freestanding oval tub right at the floor-to-ceiling window** (north: lz 3..7; south: lz 113..117): marble shell (2 Cylinder
  ends + body), part water (SmoothPlastic teal T 0.35, non-colliding, starts hidden; *client* "Fill tub" raises it), a Seat
  inside at the water line (sit up to the chest) (5).
- **Rain shower** in a SmoothPlastic T 0.6 box (6 x 6) inside the bath block (x0 + 0.6 .. x0 + 10, lz 38..50; mirrored per
  studio) + Neon rain panel + steam emitter (disabled; `HotelSteam`), vanity (marble top, basin, dark mirror panel
  Reflectance 0.3 - no real mirror), WC behind a partition (8).
- **Game corner** at the window side wall (x0+1..x0+6, lz 10..15): TV wall (`Kit.tvScreen`), console, 2 bean-bag Seats (5).
- **Company TV** (wall screen opposite the bed): *client* SurfaceGui text "Welcome, <DisplayName> · <Company>" + revenue /
  staff / best model from the client's replicated state (§10.6) (2).
- Wardrobe (2), desk + chair (3), rug, plant, drapes x 2 (sheer, *client* slider "Curtains"), room keypad (mood prompt) (6).
- 1 cove strip (Neon when booked + night, §5.4) (1). Total ~48.

### 8.2 F8 prompts
Server: `Knock` on every studio door (`HotelAction = "knock"`, `Room = "80x"`, distance 6, hold 0.3, Public; disabled locally
while `DND`), `Call lift` L8 (`liftcall`, `Stop = "8"`). All other room prompts are client-made for the occupant / invitees
(§16.2).

---------------------------------------------------------------------------------------------------------------------

## 9. F9 Sky Spa - the wellness floor (package B, model `SpaFloor`, Atomic; pool by A) - plan: `plan_wellness.png`

Open to every player 24 h; staffed 07:00-22:00 (sign at the spa desk: `SKY SPA · staffed 07:00-22:00`).

### 9.1 Zones (local, floor ly 101)
| Zone | Rect | Contents |
|---|---|---|
| Infinity pool | x -24..24, lz 0..20 | §4 + §9.2 |
| Pool deck | x -24..24, lz 20..48 | 8 loungers (Seat tilted 35 deg + 2 legs) at lz 22..28, x -21..21 step 6, facing north; **whirlpool d 12** centred (14, 40) (marble rim, part water, 8 seat pads = Seats at the water line, warm Neon ring 0.3 thick, steam emitter); towel station (-20..-16, 43..45); pool attendant post PA (0, 34); "Jets on" prompt JQ at (14, 47.4), part at ly 104.5; 2 underwater Neon strips + entry steps x -4..4 at lz 18..20 + ladder at x 20 |
| Relax lounge | x -60..-24, lz 0..48 (north glass) | 5 heated loungers at lz 5..12 (x -56..-32 step 6) facing the glass; fireplace on the south wall x -48..-36, lz 46..48 (stone, Neon firebox, `Kit.flame` Fire disabled at build); rugs, side tables, plants, sheer curtains |
| Gym | x 24..60, lz 0..48 (north glass) | 2 treadmills at x 30, 37 (lz 4..11, PropFx `belt` while used), 2 bikes x 46, 53, rower (29..32, 18..26), weights rack (57..60, 18..40), bench, mirror wall (Reflectance 0.4, sky glints only) on the south wall, mats |
| Spa street | x -60..36, lz 48..56 | corridor from the foyer to the west terrace door (x -60, lz 49..55) |
| Spa foyer | x 36..60, lz 48..88 | entry from the east terrace door (x 60, lz 59..65) = the lift landing side; **spa desk island** x 46..52, lz 70..76 (front faces north); **spa receptionist post SR (49, 78.5)**; towel shelves; therapist post TH (39, 71) between the treatment doors |
| Finnish sauna | x -58..-42, lz 56..72, door (-50, 56) | cedar WoodPlanks walls, SmoothPlastic T 0.5 door, 2 bench tiers (Seats) along lz 66..71.4, Basalt stove with stones at (-44.5, 58.5) with a steam emitter, bucket + ladle, warm Neon under the benches; "Pour water" prompt SQ (-50, 62) |
| Hammam | x -40..-16, lz 56..80 (octagon), door on the thermal corridor (x -16, lz 64..70) | 8 marble wall segments, dome of 8 WedgeParts, **16 small Neon star dots** in the dome (0.4 balls), heated marble navel stone (Cylinder d 8) at (-28, 68), 4 marble basins, steam emitter `FxIdle`-like (rate 2 while the camera is inside, §19.3) |
| Thermal corridor | x -14..-6, lz 56..120 | links spa street -> hammam -> cold zone -> spire room |
| Cold zone | x -60..-16, lz 84..120, open to the corridor at x -16, lz 92..110 | **cold plunge** (x -57..-48, lz 87..97: tiled basin, part water (120,190,220) T 0.35, 3 step Seats), **ice fountain** (-38, 91) (stone basin + 5 Ice / Glacier chunks + pale-blue Neon base), **snow cabin** x -31..-19, lz 86..98 (Snow / Glacier walls, SmoothPlastic door, white snow emitter), **3 experience showers** x -57..-35, lz 110..116 ("polar rain" blue / "tropical" amber Neon panels) |
| Lockers + changing | x -6..16, lz 56..88, door (x -6, lz 67..75) | `Kit.lockers` (ArchKit l.782) 2 banks, 4 changing cabins, benches |
| Treatment 1 / 2 | x 16..36, lz 56..72 / 72..88, doors on the foyer (x 36, lz 60..66 / 76..82) | treatment table, cabinet, Neon candles (thin), plant |
| Spire relaxation room | x -6..60, lz 88..120 (south glass x -6..60), doors from the corridor (x -6) and the foyer (x 40..50, lz 88) | 6 loungers at lz 110..117 facing the spire, tea counter (57..59.4, 96..112) (decor), plants |
| West terrace | x -70..-60, lz 0..120 (F8 roof) | fresh-air deck after the sauna (door x -60, lz 49..55), bucket shower (PropFx `flow`) at (-65, 100), 4 loungers |
| East terrace | x 60..70, lz 0..120 | lift landing area lz 54..70 (doors at x 70), **hot tub d 8.4** at (65, 30) (4 Seats, Neon ring, steam, "Jets on" prompt), 4 loungers lz 36..48, planters |

**SpaFloor parts ~390 (cap 420).** Seats ~36.

### 9.2 How water, steam and glow are built (verified APIs)
| Effect | Technique | APIs |
|---|---|---|
| Swimmable infinity pool (A) | `workspace.Terrain:FillBlock(CFrame.new(0, 120, 8390), Vector3.new(48, 8, 20), Enum.Material.Water)` once at build, when `GrandPlan.POOL.mode == "terrain"`; Terrain is unused anywhere else in the game [M], so the global look is set once: `Terrain.WaterColor = (40,170,190)`, `WaterTransparency = 0.7`, `WaterReflectance = 0.4`, `WaterWaveSize = 0.05`, `WaterWaveSpeed = 6`. 8 studs deep -> `Enum.HumanoidStateType.Swimming` [S]. The mock records it in `meta.terrainOps`; blenderprev does not draw Terrain (renders use a stand-in slab named `PoolWaterRender`, labelled in file names) | `Terrain:FillBlock`, `Terrain.WaterColor/WaterTransparency/WaterReflectance/WaterWaveSize/WaterWaveSpeed`, `Enum.Material.Water`, `Enum.HumanoidStateType.Swimming` |
| Fallback | `POOL.mode = "part"`: one SmoothPlastic slab named `PoolWater` (aqua, T 0.35, Reflectance 0.15, non-colliding) from ly 98.5 to 100 over a collidable tiled floor at ly 98.5 = a wading pool with 6 step Seats; same look from outside | `BasePart.Transparency/Reflectance/CanCollide` |
| Whirlpools, plunge, tubs | part water (SmoothPlastic, T 0.35, non-colliding) over a collidable floor; Seats 1.8 below the water line (the default sit puts the body in the water); steam via `Kit.steamEmitter` (built-in smoke texture) | `Seat`, `ParticleEmitter.Rate/Enabled/Emit` |
| Sauna "Pour water" | server prompt -> the stove root gets `FxUntil = now + 6` (8 s cooldown); HotelController sees FxUntil > now and calls `:Emit(25)` once + enables the emitter for 6 s, bench Neon lerps warmer; toast "Steam! Feel the heat." | `ParticleEmitter:Emit`, `ProximityPromptService.PromptTriggered` |
| Snow cabin | white emitter with the same built-in texture, small size, `Acceleration = (0,-6,0)`, `Drag = 1`, enabled only while the camera is within 40 studs (counts toward the 2 active emitters) | `ParticleEmitter.Acceleration/Drag/Size/Color` |
| Ice fountain "Grab ice", cold showers | *client-made* prompts (no server write): toast "Brrr!" | `ProximityPrompt.Triggered` |
| Fireplaces | `Kit.flame` (Fire, disabled at build), enabled client-side while the camera is within 40 studs; at most 1 Fire enabled per client | `Fire.Enabled/Size/Heat` |
| Hammam stars | 16 Neon balls d 0.4 | `Part.Shape = Enum.PartType.Ball` |

Steam roots in the hotel carry the attribute **`HotelSteam = true`** and use the PropFx state attribute `FxUntil` (one server
write per use), but **not** the `PropFx` tag: HotelController enables at most **2** hotel emitters at once (the nearest working
ones within 40 studs) and disables the rest. (PropFx would enable every emitter under every working root.)

*(critic CC-21)* **PropFx contract for every animated root in this spec** (revolving door, door leaves, secret bookshelf, fish
sliders, key-card printer, treadmill belts, popcorn blink, bucket shower): CollectionService tag **`PropFx`** + attribute
**`Fx`** = the kind word(s) (`"spin"`, `"hinge"`, `"slider"`, `"paper"`, `"belt"`, `"blink"`, `"flow"`) - the spec named the kinds,
PropFx reads them from `Fx`; `FxHinge` (Vector3, hinge offset from the root pivot) for hinges, `FxTravel` = radians (hinge) or
studs (slider / belt), `FxAxis`, `FxRate`, `FxIdle = "on" | "slow"`; the server writes only `FxUntil` / `FxState`
(`PropFxController.module.luau:23-38, 190-260`, `design/PROPFX_CONTRACT.md`).

### 9.3 Spa prompts
Server (Public): SQ "Pour water" (`sauna`, 8 / 0.3), JQ "Jets on" on the deck whirlpool and the terrace hot tub (`jets`,
`PropId`, 8 / 0.3), L9 "Call lift" (65, 62) on the east terrace (`liftcall`, `Stop = "9"`). Client-made: "Grab ice", "Cold
shower", "Fill tub" (studios), telescope.

### 9.4 Spa routine mini-quest (G7, client only, no reward, nothing saved)
1. Sit on a sauna bench while the stove's `FxUntil` is active (the player triggered it or anyone did) for >= 10 s ->
2. within 60 s: sit in the cold plunge, or use a cold shower / the snow cabin / "Grab ice" -> toast **"Brrr! Cold plunge done."**
3. within 120 s: lie on any spa lounger (relax lounge, spire room, deck) for >= 15 s -> toast **"Spa routine complete, Finnish style."**
Detected locally from `Humanoid.SeatPart` and positions. The pool attendant says "Nice laps!" once per visit to a player whose
`Humanoid:GetState() == Enum.HumanoidStateType.Swimming`.

---------------------------------------------------------------------------------------------------------------------

## 10. F10 Suite floor (package B, model `SuiteFloor`, Atomic) - plan: `plan_suites.png`

### 10.1 Layout (local, floor ly 113)
| Zone | Rect | Door |
|---|---|---|
| 1001 Royal Penthouse | x -50..0, lz 0..56 + west terrace x -60..-50, lz 0..56 + Lantern Room (west turret) | (-22, 56) |
| service riser | x 0..4, lz 0..56 | - |
| 1002 Panorama Suite | x 4..50, lz 0..56 + east terrace x 50..60, lz 0..50 | (27, 56) |
| Gallery corridor | x -50..50, lz 56..68; east door x 50, lz 59..65 -> east terrace landing (x 50..60, lz 50..72) -> skybridge (x 60..70) -> lifts | - |
| 1004 Deluxe King West | x -50..-26, lz 68..120 | (-38, 68) |
| 1005 Deluxe King East | x -26..-2, lz 68..120 | (-14, 68) |
| Service | x -2..14, lz 68..120: linen, pantry, service-lift portal W10 (6, 116), housekeeping cart home H10 (6, 76) | (6, 68) |
| 1003 Spire Suite | x 14..50, lz 68..120 (south + east glass) | (32, 68) |

Corridor: carpet runner, panelling, 8 sconces, 4 artworks, ceiling cove; call prompt L10 at the bridge end (66, 62).

### 10.2 1001 Royal Penthouse (the itinerary's suite when free; ~185 parts)
| Area (local) | Fixtures | Hook |
|---|---|---|
| Lantern stair x -50..-38, lz 0..12 | spiral stair d 8 at (-44, 6): 17 treads + one invisible ramp per turn, through the roof slab into the west turret | **your own glass room in a gold tower next to the helipad** |
| Lantern Room (turret, ly 128..142) | round sofa (3 Seats), telescope (*client* prompt: camera FOV 20 for 8 s, ButtonB ends), mini bar, 1 *client* PointLight while inside | the helicopter lands about 49 studs away (pad centre (0, 28)) |
| Bar + dining x -38..-25 (+ x -50..-38, lz 12..26), lz 0..26 | bar counter x -37..-27, lz 4..7 + 4 stools (Seats) + glass shelves; dining table for 8 x -36..-27, lz 16..23 (8 chairs, Seats) | |
| Living x -25..0, lz 0..26 | **50-stud glass wall x -50..0 at lz 0 straight down Meridian Boulevard** (A's F10 north glass); sectional sofa x -22..-4, lz 13..16.5 (3 Seats) facing north, coffee table with the *client* welcome card, 2 armchairs, rug, fireplace on the east wall (x -1.6..0, lz 10..18, Neon firebox only, no Fire), telescope at (-4, 4) | the boulevard, the fountains and the client towers under your feet |
| Hall + walk-in wardrobe x -25..-16, lz 26..44 | lit shelves (thin Neon), bench | |
| Foyer x -25..-16, lz 44..56 | plaque, welcome screen ("Welcome, <DisplayName>"), console; **bookshelf on its east wall (x -16, lz 46..50) = the secret door** (PropFx `hinge` root + `DoorBlock`), occupant prompt BK (-17.5, 48) | |
| Private cinema x -16..0, lz 26..56 | 24-wide screen on the north wall (lz 26.5) with *client* text **"NOW SHOWING · <Company>: Year One"**, 2 rows of recliners (4 + 4 Seats at lz 36 and 42), popcorn cart (PropFx `blink` top) | **a secret door to your own cinema** |
| Bedroom x -50..-25, lz 26..46 | king bed (x -42..-33, lz 32..42; frame, mattress, duvet, 4 pillows, headboard Neon backlight, bench Seat), 2 nightstands + lamps, under-bed strip | |
| Bath x -50..-25, lz 46..56 | **freestanding marble tub at the west glass** (x -49..-44, lz 48..54; Seat inside) looking at the terrace and the sunset, rain shower (x -34..-28, lz 47..52) with steam, double vanity, WC | tub at the window |
| West terrace x -60..-50, lz 0..56 (ly 113) | **whirlpool d 8 at (-55, 10)** with a gold Neon ring (0.3) and steam + 5 Seats, 2 loungers, planters, glass balustrade (A) | a whirlpool 113 studs above the street |

### 10.3 1002 Panorama Suite (~90 parts)
Living x 4..34, lz 0..28 (north glass; sofa x 10..26, lz 14..17); **aquarium wall** x 8..28, lz 28..30 between living and
bedroom: opaque deep-blue "water" card (SmoothPlastic (20,70,110)), front panes SmoothPlastic T 0.5 on both faces, a Neon
caustic strip (0.3) on top, **8 fish in 2 PropFx `slider` groups** (`FxRate` 0.08, `FxIdle = "on"`, active within PropFx NEAR
60), bubble emitter (`HotelSteam` rules) - custom-built (`Kit.aquarium` is 4.4 wide and uses Glass over water); bath x 34..50,
lz 0..28 with the **tub in the north-east glass corner** (x 42..48, lz 2..7) and a rain shower; bedroom + **game corner**
(console table, TV wall, 2 bean bags) x 4..50, lz 30..56 (bed x 10..20, lz 38..48; CEO desk x 36..48, lz 50..54 with 3
screens showing the company name, *client* text); east terrace: **plunge whirlpool d 7** at (55, 12) + telescope (55, 40).

### 10.4 1003 Spire Suite (~85 parts)
Bedroom facing south (bed x 34..44, lz 92..102); bath x 14..28, lz 100..120 behind a partition at lz 100 with the **tub at the
south glass** (x 17..23, lz 112..117): the 468-stud Meridian Spire (x -28..28, z 8520..8576 world) fills the window, its light
lines at night; daybed window seat (x 44..49, lz 108..118, Seat); bar cart; game corner (x 40..49, lz 72..80); rain shower.

### 10.5 1004 / 1005 Deluxe King (~50 parts each)
Studio fixture set (§8.1) in a 24 x 52 room: bath block at the corridor side (x0 + 0.6..x0 + 10, lz 72..84), king bed (lz
92..102), **tub at the south window** (lz 113..117), game corner, company TV.

### 10.6 Shared in every room ("the hotel knows you", G4; client-only, nothing saved, nothing charged)
- **Company TV** text: "Welcome, <DisplayName> · <Company>", then live lines from the client's replicated company state
  (revenue per day, staff count, best live model) - exactly the numbers the player's own HUD already shows; no new remote.
- **Welcome card** on the table: "Congratulations on the meeting with <Client>!" when the itinerary passed the client name in
  `book()` (attribute `HotelClient`), else "Welcome to Port Meridian, <DisplayName>!".
- **Mood light** = ONE cycling owner prompt on the keypad: "Lights: Relax" -> "Work" -> "Night" -> "Party" (cove, headboard,
  under-bed strips + the room's client light: Relax (255,190,120), Work (235,240,255), Night (60,80,160), Party slow hue cycle
  at 0.2 Hz). One prompt instead of a panel (G12).
- **Curtains**: cycling prompt "Curtains: close / open" (local slider). **TV**: "TV: on / off".
- **Turndown** after the housekeeper's visit (§14.5): duvet corner folded, a chocolate on each pillow, bedside lamps on.
- **"Rest"**: the bed has an edge Seat (honest fallback - there is no id-free lying pose) [S].
- **Suitcase on the luggage rack** after the bellhop came (client part).

---------------------------------------------------------------------------------------------------------------------

## 11. Roof (package A; `Shell` + `RooftopHelipad`) - plan: `plan_roof.png`

| Element | Local | Rule |
|---|---|---|
| Helipad | MetroBuilder `helipad()` unchanged, 40 x 40 at (0, 127.2, 28) (world (0, 151.2, 8408)) | pad top = HOTEL_ROOF + 1; highest collidable hotel part under the pad centre = ly 126.2 +- 0.05 |
| Rotor circle | r 16.4 around (0, 28) | nothing above the pad top inside it; the heli approaches along x = 0 from the north at roof + 60 and descends vertically 30 [M] |
| Removed | RoofLiftHouse, RoofLiftDoor, HotelRoofSign, HotelRoofSignGlow (MetroBuilder `towers()` l.795-801) | the frieze carries the name |
| HelipadExit | exactly one, **moved to (52, 128.7, 62) facing +X** (world (52, 152.7, 8442)), `To = "intl_hotel"`, `PadId = "pm_hotel"`, in `RooftopHelipad` | `tests/metro/test_build.luau:81` |
| Turrets | x +-38..+-50, lz 0..12 (nearest corner 41.2 from the pad axis) | flight clearance gate |
| Roof bridge | x 50..70, lz 56..68 at ly 126.2 -> lift stop R at x 70 | |
| Pergola | x 26..48, lz 76..100, 2 sofas | 54 from the pad axis |
| Heli attendant post HA | (26, 30) on the deck east of the pad, faces west | outside the rotor circle |
| Return prompt | *client-made* (HotelController) on the pad marker when `GrandPlan.HELI_ROOF`: "VIP helicopter" / "To the airport", `CityAction = "heli"`, `HeliTo = "airport"`, `Public = true`, 28 studs -> AirTrafficController's existing dispatcher handles it | needs the ShuttleService start check (§18.3) |

---------------------------------------------------------------------------------------------------------------------

## 12. Rooms and booking

### 12.1 Room table (13 rooms >= `CampusConfig.PLOT_COUNT` 12; data for `GrandRooms.ROOMS`)
| Room | Name | Floor | Rect x1..x2, lz1..lz2 | Size | Door (x, lz) | View | Tier | Parts cap |
|---|---|---|---|---|---|---|---|---|
| 1001 | Royal Penthouse | F10 | x -50..0, lz 0..56 | 50 x 56 + terrace + Lantern Room | (-22, 56) | north: 50-stud glass wall down Meridian Boulevard | penthouse | 190 |
| 1002 | Panorama Suite | F10 | x 4..50, lz 0..56 | 46 x 56 + terrace | (27, 56) | north + east corner glass | suite | 95 |
| 1003 | Spire Suite | F10 | x 14..50, lz 68..120 | 36 x 52 | (32, 68) | south: the spire 20 studs away; east glass | suite | 90 |
| 1004 | Deluxe King West | F10 | x -50..-26, lz 68..120 | 24 x 52 | (-38, 68) | south-west: spire + harbour | deluxe | 55 |
| 1005 | Deluxe King East | F10 | x -26..-2, lz 68..120 | 24 x 52 | (-14, 68) | south: spire | deluxe | 55 |
| 801 | Skyline Studio | F8 | x -69.5..-47.5, lz 0..56 | 22 x 56 | (-58.5, 56) | north: boulevard | studio | 52 |
| 802 | Skyline Studio | F8 | x -47.5..-25.5, lz 0..56 | 22 x 56 | (-36.5, 56) | north: boulevard | studio | 52 |
| 803 | Skyline Studio | F8 | x 25.5..47.5, lz 0..56 | 22 x 56 | (36.5, 56) | north: boulevard | studio | 52 |
| 804 | Skyline Studio | F8 | x 47.5..69.5, lz 0..56 | 22 x 56 | (58.5, 56) | north: boulevard | studio | 52 |
| 805 | Skyline Studio | F8 | x -69.5..-41.5, lz 68..120 | 28 x 52 | (-55.5, 68) | south: spire + harbour | studio | 52 |
| 806 | Skyline Studio | F8 | x -41.5..-14, lz 68..120 | 27.5 x 52 | (-27.75, 68) | south: spire | studio | 52 |
| 807 | Skyline Studio | F8 | x 14..41.5, lz 68..120 | 27.5 x 52 | (27.75, 68) | south: spire | studio | 52 |
| 808 | Skyline Studio | F8 | x 41.5..69.5, lz 68..120 | 28 x 52 | (55.5, 68) | south: harbour | studio | 52 |

Room door marker: `RoomDoor` part (invisible, 4 x 8 x 0.6, at the door centre, ly floor + 4) with attributes `Room` ("1001"),
`RoomName`, `Floor` (8 | 10), `Booked` (bool, server), `DND` (bool, server); the leaf is a PropFx `hinge` root; `DoorBlock` is
an invisible collidable part in the opening.

### 12.2 Booking rules (no economy)
- **One room per player, never shared.** `HotelService.book` gives the **best free room** in the order
  `1001, 1002, 1003, 1004, 1005, 801, 802, 803, 804, 805, 806, 807, 808` - for itinerary and walk-in guests alike (a
  low-stage player gets the wow too). When the room is better than the itinerary's text implied, the receptionist line is
  the upgrade line (§16.4).
- Check-in is free for every founder in Port Meridian ("Founders of our partner companies stay as our guests").
- 13 rooms for 12 plots: everybody gets one. A 14th player (only if MaxPlayers is raised above 13) gets `FULL`: "All rooms are
  taken right now. The Sky Spa, the Skyline Lounge and the roof are open to you." He keeps every public area.
- A booking lives only while the player is in Port Meridian. Released on: travel state leaving `abroad` (CityService state;
  respawn sends the character home and resets it [M] `CityService.module.luau:185-189`), `Players.PlayerRemoving`, **Check out**,
  or a new `book()` by the itinerary for the next trip. Nothing is saved.
- Race: two `book()` calls in the same frame -> exactly one gets 1001 (the service is single-threaded; the test proves it).
- Invite: the occupant may invite up to 3 players who are in Port Meridian and within 30 studs; invitees may open his door and
  ride to his floor until checkout or uninvite.

---------------------------------------------------------------------------------------------------------------------

## 13. Panoramic lifts (HQ lift brain reused; A builds, B drives)

### 13.1 Stops
| Stop id | LiftLogic level | Height (local ly = servo position) | World y | Landing |
|---|---|---|---|---|
| `L` | 1 | 0.5 | 24.5 | lobby lift hall, doors in the east wall x 69.5..70 |
| `8` | 2 | 89 | 113 | F8 corridor, doors in the east wall |
| `9` | 3 | 101 | 125 | F9 east terrace (freestanding door frames at x 70) -> spa door x 60 |
| `10` | 4 | 113 | 137 | skybridge x 60..70 -> F10 east terrace -> corridor door x 50 |
| `R` | 5 | 126.2 | 150.2 | roof bridge x 50..70 -> roof deck |

Travel times (LiftLogic profile, VMAX 10, ACCEL 6: t = d/v + v/a for d >= 16.7, else 2 sqrt(d/a)): L->8 10.5 s, L->R 14.2 s,
8->9 2.8 s, 9->10 2.8 s, 10->R 3.0 s; plus 0.8 s doors and 3.5 s dwell. Only these five stops exist; the panel never shows a
faked floor.

### 13.2 Geometry (A, in the model `GrandLifts` under `Hotel_intl_hotel` - not in `Shell` - built anchored)
*(critic CC-13: moving, unanchored cabin assemblies inside the Atomic `Shell` are an untested streaming case and the lift parts
pushed Shell to its cap; `GrandLifts` is Default, each `GrandLiftCar` is its own Atomic model, so a car never streams in half.)*
- Tower x 70..81, lz 54..70, **ly 0..139** (cap ly 138..139; the car roof at stop R is at ly 136.6 *(critic CC-6)*). **Car 1** interior x 71..80, lz 55..61.5; **car 2** x 71..80, lz 62.5..69; cabin height
  10, capacity 6; separation wall lz 61.5..62.5.
- Each car: a Model `GrandLiftCar` (`ModelStreamingMode = Atomic`, parent `GrandLifts`; attributes `Car` = 1 | 2, `Stops` = "L,8,9,10,R") with `CabinFloor` (collidable), 3 walls
  SmoothPlastic T 0.6 (north/south/east), roof, 2 door leaves (west face x 71, sliding along z; car 1 opening lz
  56.25..60.25, car 2 lz 63.75..67.75), a panel plate, a thin Neon light strip; **every part anchored at build** (so "everything
  anchored" world tests pass when the world is built alone); one anchored `LiftGuide` per car (thin bar at x 80.5).
- Landing: per car per stop a door frame + 2 leaves (`LandingDoor`, attributes `Car`, `Stop`), a `LiftStop` marker
  (attributes `Car`, `Stop`, `Y`; harness `check_geometry.py --lift stops` understands it), and per stop one call-prompt part
  (`liftcall`, `Stop`) at (64..66, floor + 3.5, 62).

### 13.3 Behaviour (B, `HotelLiftService`)
- One `LiftLogic.new({1,2,3,4,5}, {[1]=0.5,[2]=89,[3]=101,[4]=113,[5]=126.2}, 1, 6)` per car (car 2 starts at level 5).
- Hall call (prompt `liftcall`): the server picks the better car (idle and nearest by |position - stop height|, else the one
  already heading there) and calls `Logic.call(car, "hall", level)`.
- Car call: `TripAction {action = "hotel", op = "lift", car = 1 | 2, stop = "L" | "8" | "9" | "10" | "R"}` (§16).
- Car model attributes published on change only: `Stop` (current), `Target`, `Doors` ("open" | "opening" | "closed" |
  "closing"), `Moving` (bool), `Mode` ("physics" | "express").
- NPCs never ride: staff and guests use the lift doors as a portal (doors open locally, the NPC vanishes and reappears at the
  destination landing after the travel time from the table above).

### 13.4 Mode "physics" (default, `GrandPlan.LIFT_MODE = "physics"`)
LiftService's documented recipe [M] `LiftService.module.luau:1-27`, applied to these two world cars without touching
LiftService: at `HotelLiftService.init` the cabin parts are unanchored and welded (`WeldConstraint`) to `CabinFloor`; a
`PrismaticConstraint` (Attachment0 on `LiftGuide`, Attachment1 on `CabinFloor`, axis vertical, `ActuatorType = Servo`,
`Speed` 10, high `ServoMaxForce`, `LinearResponsiveness` as LiftService) carries it; the server owns the assembly; door leaves on
`Weld`s; collision groups `LiftCabin` / `LiftShaft` (registered in a pcall, reused if LiftService already registered them);
`TargetPosition` written at ~20 Hz **only while a car moves** (from `car.cmd`). Riders are carried by the engine (several players
may ride together).

### 13.5 Mode "express" (fallback flag, must-fix F7)
Same panel, same calls, same LiftLogic. The cabin stays anchored. When a car departs: doors close (0.8 s), every rider inside the
cabin box is anchored, the server calls `Player:RequestStreamAroundAsync(destination landing)` in a task (timeout 4 s), 3.0 s
after departure it `PivotTo`s the cabin model to the destination and every rider's character by the same offset, unanchors, and
LiftLogic's position is set to the destination height; doors open. The riders' clients show a 0.3 s fade (HotelController:
local root inside a car whose `Moving` is true and `Mode == "express"`). A rider who left, died or respawned in between is
skipped (`CANCELLED`, as CityService's hold pattern does).

### 13.6 Streaming
Both modes: when a car departs with at least one player inside, the server requests streaming around the destination landing for
each rider (`Player:RequestStreamAroundAsync`, in a task, pattern `CityService.module.luau:94-104`). The roof stop also covers
the pad. No claim that the whole hotel is inside StreamingMinRadius (it is not: the diagonal is ~223 studs).

---------------------------------------------------------------------------------------------------------------------

## 14. Staff (package B; graft G1)

### 14.1 Technique (existing patterns only, no asset ids)
- **Templates (server)**: `HotelService` builds one rig per staff member with
  `EmployeeRigDesign.Rig.build(temp, 0, index, "hotel:<Uniform>", CFrame.new(), {n = CampusMath.staffName(index, 0)})`
  (indices **9601..9622**, owner 0 = city NPC like the chauffeur 9407), then strips it exactly like
  `DriverService.template` [M] `DriverService.module.luau:247-266` *(critic: lines moved in the drivers fix round)* (tag + prompts removed, parts non-colliding, only the root
  anchored), names it `S01`..`S22`, badge "<Name>\n<Role> · Meridian Grand", parent `ReplicatedStorage.GrandHotelStaff`
  (Folder; not in workspace = no server physics). <= 22 parts each.
- **Uniforms (additive in `EmployeeRigDesign.UNIFORMS`)** with the existing feature keys only:

| Key | shirt | jacket / vest | trousers | shoes | extras |
|---|---|---|---|---|---|
| `Doorman` | (244,244,240) | jacket (110,30,40) | (30,30,34) | (18,18,20) | cap (110,30,40), gloves (238,238,234) |
| `Bellhop` | (244,244,240) | jacket (110,30,40) | (30,30,34) | (18,18,20) | cap (110,30,40) |
| `Concierge` | (240,240,236) | jacket (26,34,58) | (26,34,58) | (18,18,20) | tie (212,172,86) |
| `Bartender` | (244,244,240) | vest (24,24,26) | (24,24,26) | (18,18,20) | tie (24,24,26) |
| `Pianist` | (244,244,240) | jacket (16,16,20) | (16,16,20) | (12,12,14) | tie (14,14,18) |
| `Duty Manager` | (236,236,232) | jacket (58,60,66) | (58,60,66) | (20,20,22) | tie (110,30,40) |
| `Spa` | (246,246,242) | - | (236,236,230) | (236,236,230) | skirt = true |
| `Pool Attendant` | (52,150,160) | - | (240,240,236) | (240,240,236) | |
| `Room Service` | (246,246,242) | jacket (246,246,242) | (24,24,26) | (18,18,20) | tie (24,24,26) |

  Existing keys reused: `Hotel Reception`, `Housekeeping`, `Security`, `Cafe Host`, `Facilities`, `Fleet` (hi-vis).
  Role mapping, one additive branch before `Config.ROLES[role]` in `Rig.build` l.82:
  `elseif string.sub(role, 1, 6) == "hotel:" then string.sub(role, 7)`.
- **Client**: `HotelController` clones templates into a pool, poses joints with the exported pure
  `EmployeeController.pose(...)`, writes `Motor6D.Transform`, and places all roots with **one
  `workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)` per step**. Held items (tray with cloche, towels,
  suitcase, cart, ladder) are client parts welded to the arm / root.
- **Positions** come from the pure `GrandStaffPlan`: GuestPlan-compatible actors `{id, seed, role, segs = {kind, t0, t1, path,
  cum, at, pose, carry}}` sampled with **`GuestPlan.sample(actor, t)`**, `t = workspace:GetServerTimeNow()`, built per company
  day `d = floor(t / Ops.DAY)` (`GuestPlan.dayOf`), hours converted with `GuestPlan.sOfHour(h)` (08:00 = s 0; 09:00 = 90;
  12:00 = 360; 18:00 = 900; 19:00 = 921.4; 22:00 = 985.7; 00:00 = 1028.6; 07:00 = 1178.6; `Ops.DAY` 1200). Segments that
  start in the 07:00-08:00 tail belong to day d and may run into day d + 1: the controller samples the actors of d and d - 1.
  Paths run only on the waypoint graphs of Appendix B (`npc_paths.py` sweeps them against the built walls).
- **Walking speed**: staff 4 studs/s (doorman cue included), guests 3.5; never faster than 5.

### 14.2 Roster (22 people; posts are floor points, rig root +3)
| Id | Index | Role (badge) | Uniform | Shift (company h) | Post (floor: node) | Routine |
|---|---|---|---|---|---|---|
| S01 | 9601 | Doorman | Doorman | 07-19 | L1: D1 (6, -2.5) | stands `present`, head turns to people within 12; limo cue (§6.5); greets walk-ins within 10 ("Welcome to the Meridian Grand!", <= 1 line per player per 45 s); hands over to S03 side by side at PO for the last 3 real seconds before 19:00 (s 918.4..921.4) |
| S02 | 9602 | Doorman | Doorman | 07-19 | L1: D2 (-6, -2.5) | `present`; plays `reach` (holding the door) when a player comes within 6 of PW / PE |
| S03 | 9603 | Night porter | Doorman | 19-07 | L1: D1 | limo cue as S01; 02:00-05:00 sits on the bell stand stool (BS, `relax`) and gets up for a limo cue |
| S04 | 9604 | Bellhop | Bellhop | 07-23 | L1: BS (18, 3.2) | luggage timelines (§14.5); idle `wipe` at the cart; every 2 company hours without a task a cosmetic loop BS -> VE -> PE -> PO -> VI -> BS with a guest's cases |
| S05 | 9605 | Receptionist | Hotel Reception | 07-19 | L1: R1 (40, 36) | `type`; turns + `greet` when a player is within 14 of CK; the receptionist nearest to the player speaks the check-in lines; printer `FxUntil` on check-in |
| S06 | 9606 | Receptionist | Hotel Reception | 07-19 | L1: R2 (48, 36) | as S05 |
| S07 | 9607 | Night receptionist | Hotel Reception | 19-07 | L1: RP (44, 36) | as S05 |
| S08 | 9608 | Concierge | Concierge | 08-22 | L1: CO (-35, 30) | `write`, `phone` bursts every ~30 s; greets |
| S09 | 9609 | Bartender | Bartender | 11-02 | L1: BT lane BTE..BTW (lz 110.5) | `wipe` <-> `pour`; walks along the lane to a player sitting on a stool: "What can I get you?" |
| S10 | 9610 | Pianist | Pianist | 19-23 | L1: PI (-35, 90.5), seated | `type` (reads as playing; no sound - audio hooks stay silent) |
| S11 | 9611 | Café host | Cafe Host | 07-17 | L1: CH (47, 114) | 07:00-10:30 breakfast refills CH -> CK1 -> BF every 25 s (`carry` tray), then the counter (`pour`) |
| S12 | 9612 | Duty manager | Duty Manager | 08-20 | L1: loop | duty-manager route (Appendix B: 411 studs at 4 studs/s + 4 stops = ~2 real minutes per loop), stops 4 s at RF, SE, BM, W1 (`inspect`): "Everything to your liking?" once per player per day |
| S13 | 9613 | Security | Security | 07-19 | L1: SE (59, 50) | `scan`; nod to players |
| S14 | 9614 | Night security | Security | 19-07 | L1: SE | **two rounds per night** *(critic CC-15: the old 4 rounds 3 company hours = 64 real s apart could not fit one ~150 s round)*: 19:30 F8 (SE -> LH -> LC1 portal 8 s -> F8 LND -> C5 -> LND -> portal -> SE, ~88 s) and 01:00 F10 (SE -> LC1 -> F10 LND -> K5 -> LND -> SE, ~78 s); otherwise at SE (`scan`) |
| S15 | 9615 | Spa receptionist | Spa | 07-22 | F9: SR (49, 78.5) | "Welcome to the Sky Spa - towels are by the pool." hands a towel (client held item, 30 s) |
| S16 | 9616 | Pool attendant | Pool Attendant | 07-21 | F9: PA (0, 34) | towel loop PA -> DECK -> TW every 40 s (`carry`); "Nice laps!" to a swimming player |
| S17 | 9617 | Spa therapist | Spa | 09-21 | F9: TH (39, 71) | every 3 company hours into treatment 1 or 2 for one company hour (hidden behind the door; client sign "Treatment in progress"), then back to TH |
| S18 | 9618 | Housekeeper | Housekeeping | 09-16, turndown 17:00-19:30 | F8: H8 cart (0, 76) | door-to-door round of the F8 rooms (a booked room only while its occupant is out and DND is off), **60 s per room** (+ the walk: whole tour 422 studs = 106 s; 8 x 60 + 106 = 586 <= 630) *(critic CC-15)*; turndown visits (§14.5) |
| S19 | 9619 | Housekeeper | Housekeeping | 09-16, turndown 17:00-19:30 | F10: H10 cart (6, 76) | as S18 on F10, **100 s per room** (tour 268 studs = 67 s; 5 x 100 + 67 = 567 <= 630) |
| S20 | 9620 | Room-service waiter | Room Service | on demand, 24 h | F8 W8 / F10 W10 portal | §14.5 |
| S21 | 9621 | Heli attendant | Fleet | around helicopter rides | Roof: HA (26, 30) | from `HeliStart`/`HeliMode`/`HeliRider` on `ReplicatedStorage.Shuttle` and `FP.heliTimes`: shown from 20 s before a ride touches the hotel pad until 30 s after; `greet` (waving it in), then `present` towards the lift; greets the arriving player by name |
| S22 | 9622 | Maintenance | Facilities | 10-16 | L1: MT (6, 48) 10:00-12:00 on a client ladder at the chandelier (`reach`); F9 lockers LKI (5, 71) 13:00-16:00 (`inspect`) | |

On duty at 12:00: S01, S02, S04, S05, S06, S08, S09, S11, S12, S13, S15, S16, S17, S18, S19, S22 = **16** (+ S20 on demand).
At 03:00: S03, S07, S14 = **3** (+ S20). Hotel staff are city NPCs of an independent hotel: **no wages, no CompanyOps line**,
nothing to do with the player's employees.

### 14.3 Shift changes (07:00 = s 1178.6, 19:00 = s 921.4)
The leaving person walks from the post to the staff door SW (0, 118) (kitchen staff: SX (62, 118)) along the graph and vanishes;
the arriving person appears there and walks to the post (route "Shift change" in `plan_lobby.png`). Spa / F8 / F10 staff use the
service-lift portals W8 / W10 or the lift doors. The arriving person appears at the portal at `T_shift - 3 - walk / 4` (walk =
graph length of its route, e.g. SW -> PO 144 studs = 36 s, the "Shift change" route 166 studs = 42 s) and is at the post 3 real
seconds before the change; the leaving person leaves the post at `T_shift`. Doorman and night porter stand side by side at PO for
those 3 real seconds *(critic: 18:55-19:00 lasts only 1.8 real s at the night rate of 21.43 s per company hour)*. At night the city only looks dark for ~259 s of every 1,200 s (ClockTime < 6.3 or > 18.2); 22:00-06:00 is
~171 s (2.9 real minutes); the economy clock runs on (no night skip).

### 14.4 How staff react to the player (G4)
- Head turn (`lookYaw`) to a player within 12 studs; body turn for receptionists, concierge, bartender, spa desk.
- Bubbles: client BillboardGui (MaxDistance 30, 3 s, <= 1 line per staff member per player per 45 s, <= 3 bubbles at once).
  Greeting by company hour (`CompanyOps.hour`): "Good morning / Good afternoon / Good evening, <DisplayName>." (05-12 / 12-18 /
  18-05); with a booking: "Welcome back, <DisplayName>! <Room name> is ready for you."
- Prompts only where they do something (no talk prompt on every NPC: fewer buttons on the phone screen).

### 14.5 Service timelines (deterministic from replicated attributes; every client draws the same)
| Service | Trigger | Timeline |
|---|---|---|
| Bellhop -> room | player attrs `HotelRoom`, `HotelCheckedIn` = server time C | C+0..4 loads the suitcase at the bell stand (if the founder arrived by limo, the case is already on the cart); C+4..39 pushes the cart BS -> ... -> LC1 (bellhop route, 141 studs) and vanishes in car 1 (portal); C+52 appears at the room floor's landing (F8 LND / F10 LND); walks the corridor to the door node (route "Bellhop with the suitcase"; farthest door: F8 134.5 studs, F10 115 studs -> <= 34 s *(critic)*); waits until the occupant opens the door or C+170; the occupant's client then puts the suitcase on the luggage rack; "Enjoy your stay!"; back to the portal; at BS again at C+240 |
| Room service | player attr `HotelOrder = "<item>:<O>"` (O = server time) | **O+12** the waiter with a domed trolley comes out of the service portal (W8 / W10); walks to the door (**<= 123 studs, <= 31 s** - farthest door from W8 is 122.5 studs; knock by O+45) *(critic CC-15: O+20 + 31 s missed the O+45 knock)*; knocks (`reach`), bubble "Room service!"; if the occupant opens within 30 s the trolley rolls in to the table (client tray + dish), else it is left at the door; the waiter leaves |
| Turndown | the room is booked at 17:00 (sOfHour 810) | *(critic CC-15: the old 19:00-21:00 window is only 42.9 real s for up to 13 doors - consecutive F8 visits would have been 3.3 s apart for a 42-stud walk)* per floor the housekeeper leaves her cart at 17:00 and visits the floor's booked rooms in corridor order (walk 4 studs/s on the graph + 4 s at each door), a deterministic schedule from the booked set at 17:00 (drawn only if the camera is on that floor); visits that would start after 19:30 (sOfHour 932.1) are not drawn - those rooms are turned down silently; if the occupant is inside at his visit, she knocks, says "I'll come back later" and moves on, and the turndown appears the next time he leaves the room (client-only); from then on the occupant's client shows the turned-down bed + chocolates |
| Colleague (itinerary companion) | `HotelCompanion` (name) + `HotelCompanionSeed` from `book()` | arrives with the founder, checks in at R2's desk position, walks to the lift; next company day 07:00-09:00 sits at bistro table (42, 88): "Morning! Our return is at <HotelReturnAt as hh:mm>." (or "Morning! Big day yesterday." without a return time); one cheap guest figure, not a rig |

### 14.6 Housekeeping
09:00-16:00 = 630 real seconds. S18 visits F8's rooms in order 801..808, S19 F10's 1005, 1004, 1003, 1002, 1001; a booked room is
skipped while its `RoomDoor.DND` is true or its occupant is inside (free rooms are always cleaned); the cart stays in the corridor at the door node; **60 s (F8) / 100 s
(F10)** inside each room (hidden), then the next; the walk between doors is extra (graph length / 4) and the whole round fits 630 s *(critic CC-15)*.

---------------------------------------------------------------------------------------------------------------------

## 15. Hotel guests (package B, client figures)
- Own cheap figures in HotelController (7-8 parts, GuestController's recipe and palettes copied - GuestController exports no
  builder and is not edited), walk / sit / stand poses, suitcase / bag carry; **one new pose "swim"** (root horizontal at the
  water line ly 99.6, arm strokes, 0.4 s period) for 1-2 pool guests (G7).
- About **24 actors per company day** (seeded per day with `GuestPlan.hash("grand:" .. d .. ":" .. i)`): 6 business guests
  (laptop), 10 leisure guests, 4 couples (walk as pairs), 4 arrivals / departures with suitcases.

| Where | When (company h) | Who | Max at once |
|---|---|---|---|
| Café breakfast | 07:00-10:30 | 6-8 at the bistro tables (+ the colleague) | 8 |
| Lounge | 11-15 | 3 reading on the sofas | 3 |
| Check-in / check-out | 08-11 out, 14-18 in | through the revolving door, reception, lifts (portal) | 2 |
| Bar | 18-01 | 4-6 on stools and at tables | 6 |
| Pool deck / pool | 10-19 | 4 on loungers, **2 swimming** | 6 |
| Gym | 08-11, 17-20 | 2 on treadmill / bike (walk cycle in place) | 2 |
| Sauna / relax | 10-21 | 2 seated | 2 |
| F8 / F10 corridors | 14-22 | 2 walking to rooms (enter free rooms only) | 2 |
| Balconies F3 / F7 (facade) | 18-22 | 2-3 standing at the railings, visible from the street | 3 |

**Cap: 12 figures drawn at once** (nearest first within the camera's floor band); beyond 90 studs hidden except the balcony
figures (visible to 160 from the street at 5 Hz).

---------------------------------------------------------------------------------------------------------------------

## 16. Interactions (server-validated, no new remote)

### 16.1 Channels
- **Server prompts** built by A or B with attribute **`HotelAction`** (never `CityAction` - the world test counts
  `CityAction == "checkin"` prompts, and TravelController dispatches `CityAction` on the client) and `Public = true`;
  HotelService handles them in its own `ProximityPromptService.PromptTriggered` connection (CityService pattern).
- **Client-made prompts** for the occupant / invitees (door "Open", keypad, room phone, jets, secret door, telescope, ice,
  cold shower, fill tub, curtains, TV): created locally by HotelController like AirTrafficController's local heli prompt
  (WorldController never re-evaluates owner changes, so per-player server prompts would be stale). Their triggers call the remote.
- **Remote**: `TripAction {action = "hotel", op = ...}` registered with `DriverService.onTripAction("hotel", handler)` in
  `HotelService.init` (never `Remote.bind("TripAction")`). The remote's limiter (burst 8, 3/s per action, company required)
  applies; a `NO_COMPANY` answer shows "Found your company first." *(critic CC-19: `onTripAction` silently overwrites an action
  key - the action name `"hotel"` is reserved in the itinerary request (Appendix D.1) and `test_service` asserts that after
  every `init` the `"hotel"` handler is HotelService's and the itinerary's actions still route.)*
- **Notify kinds** (free strings on the existing `Notify` event): `HOTEL_KEY` (key card payload), `HOTEL_SHEET`
  (`{sheet = "service" | "invite"}`), `HOTEL_SERVICE` (`{kind = "drink" | "plate"}`); toasts use the existing `CAMPUS_NOTICE`.

### 16.2 Interaction table
| Interaction | Trigger | Server validation (all also `typeof` / `Guard.id` / whitelist) | Result |
|---|---|---|---|
| Check in | prompt CK `checkin` | session loaded; travel state `abroad` (CityService) else `NOT_ABROAD`; alive; root within 14 of CK; 1 s throttle; already booked -> same card again (ok) | assign the best free room (§12.2); Player attrs; `RoomDoor.Booked = true`; printer `FxUntil = now + 2`; Notify `HOTEL_KEY` + receptionist line |
| Open door | client prompt "Open · <room>" (occupant or invitee; distance 6) -> `op = "door", room` | room booked by the player or he is invited; root within 8 of the `RoomDoor`; 1 s cooldown per player | `DoorBlock.CanCollide = false` for 4 s; leaf `FxUntil = now + 4` (PropFx hinge); reader dot green (client) |
| Knock | server prompt on every room door `knock` (`Room`) | room booked; not DND (else "Do not disturb is on."); 5 s throttle per knocker | Notify `CAMPUS_NOTICE` to the occupant: "<Name> is knocking at <room>. Open the door to let them in."; the occupant's next "Open" lets anyone through for 4 s |
| Do not disturb | stay sheet toggle / occupant door prompt "Do not disturb: on/off" -> `op = "dnd", on` | has a room | `RoomDoor.DND`; knock prompts hide locally; housekeeping skips |
| Invite / uninvite | stay sheet -> `op = "invite" | "uninvite", userId` | both in PM; target within 30 studs; <= 3 invites | Player attr `HotelInvites` = "uid,uid"; the target's client creates the door prompt |
| Lift hall call | prompt `liftcall` (`Stop`) | root within 10 of that landing; 0.5 s per player | hall call on the better car |
| Lift car call | panel -> `op = "lift", car, stop` | root inside that car's cabin box (x/z +1 stud, y -4..10 relative to the cabin floor, LiftService's lag box); not seated; stop in {L,8,9,10,R}; **8 / 10 need a booking or an invitation (`KEY_REQUIRED`)**; 0.5 s per player; LiftLogic de-duplicates; out of service -> `OUT_OF_SERVICE` | car call |
| Room service | room phone (client prompt "Room service") or the company phone's Reception contact (§18.4) -> sheet -> `op = "service", item` (item in {`club`, `fruit`, `cocoa`, `sushi`}) | has a room; no open order; 120 s cooldown | `HotelOrder = "<item>:<now>"`; waiter timeline (§14.5); complimentary |
| Suite jets | occupant client prompt on 1001's / 1002's whirlpool -> `op = "jets", prop` | occupant or invitee; within 10 of that `PropId`; 30 s cooldown | `FxUntil = now + 30` on that root (steam, Neon ring brighter) |
| Spa jets / sauna | server prompts `jets` (`PropId`) / `sauna` | within 10; per-prop cooldown 30 s / 8 s | `FxUntil = now + 30` / `now + 6` |
| Secret door | occupant client prompt BK "Bookshelf" -> `op = "secret"` | occupant or invitee of 1001; within 6 | bookshelf leaf `FxUntil = now + 6`, its `DoorBlock` off for 6 s |
| Bar | prompt `bar` | within 10; 60 s cooldown per player | Notify `HOTEL_SERVICE {kind = "drink"}` -> a client glass in the hand for 30 s; the bartender walks over (client cue): "Here you go!" |
| Breakfast | prompt `breakfast` | within 10; company hour 07:00-10:30 else "Breakfast is served 07:00-10:30. The cafe is open until 17:00."; 60 s cooldown | Notify `HOTEL_SERVICE {kind = "plate"}` -> a client plate for 30 s |
| Concierge | prompt `concierge` (keyboard F, gamepad ButtonX) | within 10; 2 s cooldown | calls the exported `DriverService.phoneHook(session)` -> the drivers' existing `DRIVE_SHEET` with the abroad destinations (VIP limousine, free); toast "Your limousine is one tap away." (the helicopter stays at the existing lobby prompt LP) |
| Check out | stay sheet -> `op = "checkout"` | has a room | release (§12.2) |
| Mood / curtains / TV / telescope / ice / cold shower / fill tub | client prompts | none (purely local) | local effects |

Every handler returns `{ok, err?, ...}`; HotelService never calls `Economy`, `EmpireService` or any money function (static test).

### 16.3 Session attributes (never saved)
Player: `HotelRoom` ("1001"), `HotelRoomName`, `HotelFloor` (8 | 10), `HotelBy` ("itinerary" | "walkin"), `HotelCheckedIn`
(server time), `HotelOrder`, `HotelDND` (bool), `HotelInvites`, `HotelClient` (itinerary client name, optional),
`HotelCompanion`, `HotelCompanionSeed`, `HotelReturnAt` (server time, optional). `RoomDoor`: `Room`, `RoomName`, `Floor`,
`Booked`, `DND`. Lift car: `Stop`, `Target`, `Doors`, `Moving`, `Mode`. Steam / jets roots: `FxUntil`.

### 16.4 Texts (English; error code -> text shown in a toast)
| Code / moment | Text |
|---|---|
| check-in (new) | "Good <morning/afternoon/evening>, <DisplayName>! Your key card for <RoomName> <Room>, floor <F>. The Panorama Lifts are on the east side." |
| check-in (upgrade) | "Good news, <DisplayName> - we have upgraded you to the <RoomName>!" |
| already booked | "Welcome back, <DisplayName>! <RoomName> <Room> is ready." |
| `NOT_ABROAD` | "Check-in is only possible in Port Meridian." |
| `LOADING` | "One moment, your company is still loading." |
| `TOO_FAR` | "Step up to the reception desk to check in." |
| `FULL` | "All rooms are taken right now. The Sky Spa, the Skyline Lounge and the roof are open to you." |
| `WRONG_ROOM` | "This is <Room>. Your key card opens <yours>." |
| `NO_ROOM` | "Check in at reception first - it's free for founders." |
| `KEY_REQUIRED` | "Key card needed: check in at reception." |
| `DND` | "Do not disturb is on." |
| `COOLDOWN` | "One moment..." |
| `RATE_LIMIT` | "Slow down a little." |
| `NO_COMPANY` | "Found your company first." |
| `INVITE_FAR` | "<Name> needs to be next to you to get an invitation." |
| `INVITE_FULL` | "You can invite up to 3 friends." |
| `ORDER_OPEN` | "Your order is already on its way." |
| `NOT_IN_CABIN` | "Step into the lift first." |
| `OUT_OF_SERVICE` | "This lift is being checked. Please use the other one." |
| `CANCELLED` (express lift) | (silent; the rider stays where he is) |
| checkout | "Thank you for staying at the Meridian Grand, <DisplayName>!" |

---------------------------------------------------------------------------------------------------------------------

## 17. UI (package B; every ScreenGui `ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets`, touch targets >= 44 pt)

Reference phone: 844 x 390 pt landscape, CoreUISafeInsets top 58, left 47, bottom 21, right 47 -> usable x 47..797, y 58..369
(750 x 311). Nothing goes under the Roblox top bar. Desktop 1280 x 720: same layout, scale 1.

| Element | Size (pt) | Position (phone) | Behaviour |
|---|---|---|---|
| Key card | 300 x 150 | top centre: x 272..572, y 66..216 | navy card, gold `UIStroke`, `MERIDIAN GRAND` (Fondamento), "<RoomName> · <Room>", "Floor <F> · Panorama Lifts (east side)", "<DisplayName> · <Company>"; buttons **Show the way** (140 x 44) and **OK** (64 x 44); auto-collapses after 6 s into the chip; `DisplayOrder` 32 |
| Key chip | 120 x 44 | top-right of the safe area: x 669..789, y 66..110; if guiprev shows an overlap with the existing HUD, the fallback is the right edge centre (y 190..234) | "Suite 1001" / "Studio 805"; tap opens the stay sheet; **hidden while the lift panel is shown** (they share the right column) |
| Stay sheet | 360 x 220 | centred: x 242..602, y 85..305 | 2 columns x 3 rows of 168 x 44 buttons: Show the way, Room service, Do not disturb: Off/On, Invite friends, Check out, Close; `DisplayOrder` 45 |
| Lift panel | 232 x 170 (padding 12, title 22, 2 rows of 52 + gap 8, caption 16) | right edge: x 557..789, y 76..246 (bottom 144 pt above the screen bottom: the jump button stays free) | title "Lift <n> · <current stop>"; **3 + 2 grid of 64 x 52 buttons, two-line labels** *(critic CC-16: "10 Suites" in one line does not fit 64 pt at a readable size)*: the stop in 22 pt bold on top (`R`, `10`, `9` / `8`, `L`) and the name in 11 pt below (`Helipad`, `Suites`, `Sky Spa` / `Skyline`, `Lobby`); current stop outlined; 8 / 10 disabled without a key with the caption **"Key card needed"** (the full KEY_REQUIRED text comes as a toast); shown while the local root is inside a cabin (4 Hz check), hidden when outside |
| Room-service menu | 360 x 240 | centred | 4 items as 2 x 2 buttons of 168 x 52 ("Club sandwich", "Fruit platter", "Hot chocolate", "Sushi platter"), caption "Complimentary", Close (44) |
| Invite list | 360 x 260 | centred | up to 6 nearby players (rows 44 high, ScrollingFrame), "Invite" / "Remove" buttons 96 x 44 |
| "Show the way" | world markers | - | BillboardGui (MaxDistance 300, AlwaysOnTop) "Lifts ►" over the lift hall, then "Your room ►" over the `RoomDoor`; removed on arrival |

Gamepad: opening any panel sets `GuiService.SelectedObject` to its first **enabled** button; `NextSelectionUp/Down/Left/Right`
wired across the grid; **ButtonB closes** (`UserInputService.InputBegan`); every hotel prompt keeps the default gamepad key ButtonX -
**no hotel prompt or panel uses ButtonY** (the phone's toggle key, §0.3) *(critic CC-14)*. PC: prompts by key (CQ: F), panels by
mouse. Input hints from `UserInputService.PreferredInput` (`GuiService.PreferredInput` does not exist in the dump).
**The phone closes when a hotel panel opens** *(critic CC-17)*: HotelController adds the ScreenGui names `HotelKeyCard`,
`HotelStaySheet`, `HotelRoomService`, `HotelInvite`, `HotelLiftPanel` to the public table `PhoneController.PANELS` at init (a
runtime write, no edit of the phone package's file); the phone's own ButtonB handling stays first while the phone is open.
The key card (6 s, `DisplayOrder` 32) may cover the HUD's top-centre goal bar while it is shown; nothing else may overlap the HUD.

---------------------------------------------------------------------------------------------------------------------

## 18. Integration with other systems (who owns what)

### 18.1 DriverService / DrivePlan (drivers package; read-only for B, one edit by A)
- **A** replaces the `pm_hotel` place (§6.3) after the drivers fix round has landed; A also updates `tests/drivers/*`
  expectations only where they pin the old coordinates. Everything else in DrivePlan / DriverService / DriveController stays.
- **B** reads ride folders (`ReplicatedStorage.CompanyDrivers/...`) for the doorman / bellhop cues (§6.5), registers
  `DriverService.onTripAction("hotel", handler)` and calls the exported `DriverService.phoneHook(session)` for the concierge.
- The VIP limousine abroad is free and "not a company driver" [M] API.md - nothing in the hotel changes that.

### 18.2 ExecutiveLimo mesh
DriveController's hook (`ReplicatedStorage.Assets.Vehicles.ExecutiveLimo` or `ReplicatedStorage.VehicleAssets.ExecutiveLimo`,
part-built fallback) [M] `DriveController.module.luau:64, 214-223, 315`. The hotel only guarantees the canopy clearance (12.8).

### 18.3 ShuttleService helicopter (B, additive, after round 2b; behind `GrandPlan.HELI_ROOF`)
- `Shuttle.heliArrival("hotel")`: when `GrandPlan.HELI_ROOF` is true **and** `HotelLiftService.ready()` (optional require in a
  pcall) returns true -> the roof `HelipadExit` frame (world (52, 152.7, 8442) facing +X); otherwise the lobby point as today.
- `Shuttle.heli(s, "airport")` start check: accept within `HELI_RADIUS` (40, |dy| <= 16) of the lobby point **or** of the hotel pad
  (world (0, 151.2, 8408)).
- Fee logic untouched (`HELI_FEE` or the limo pass). This answers `design/requests/flight.md` #4.
- `tests/flight/test_shuttle.luau:353-358` / `test_client.luau:398` expect the lobby arrival: B updates them minimally to read the
  arrival from `Shuttle.heliArrival("hotel")` and adds both flag states. Flight clearance (`flight_clearance`) is unaffected
  (no roof structure in the heli path).

### 18.4 PhoneService - Reception contact for room service (B, additive, 3 lines, after round 2b)
In `action == "call"`: run a `reception` hook when one is registered and use its result **only if it is a table** (a nil result
falls through to today's HQ reception text). HotelService registers `Phone.onAction("reception", fn)`: no room -> `nil`; with a
room -> `{ok = true, title = "Meridian Grand front desk", text = "Good evening, <DisplayName>! What can we bring to <RoomName>?"}`
plus `Notify HOTEL_SHEET {sheet = "service"}` (opens the room-service menu). Phone tests re-run.

### 18.5 CityLifeController (A, additive)
- Hotel impostor: §5.5.
- Night-window hook (G5):
```lua
-- CityLife.setLit(p, lit): override the lit flag of a registered glow part; nil restores CityLife's own hash rule.
function CityLife.setLit(p: BasePart, lit: boolean?)
	local look = glowParts[p]
	if not look then return end
	if lit == nil then
		local h = Plan.hash(string.format("%d:%d", math.floor(p.Position.X), math.floor(p.Position.Z + p.Position.Y)))
		lit = not WINDOW_PARTS[p.Name] or h % 20 < 9
	end
	if look.lit == lit then return end
	look.lit = lit
	p.Material = look.material; p.Color = look.color; p.Transparency = look.transparency -- an unlit nightLook keeps the material
	applyLook(p)
end
```
  (Place it after the local `applyLook` definition, ~l.1072 today. `nightLook` only darkens the colour of an unlit part, so the
  material must be reset before re-applying.) HotelController uses
  the same night rule as CityLife (`Lighting.ClockTime < 6.3 or > 18.2`).
- *(critic CC-18)* Streaming: a pane that streams out is removed from CityLife's `glowParts` and re-registers with the 45 % hash
  rule when it streams back in. HotelController therefore re-applies the current slot's pattern whenever a `GrandWindow` pane is
  added (`CollectionService:GetInstanceAddedSignal("MetroNightGlow")`, `task.defer` so CityLife registers it first), not only
  at slot changes. `test_client` streams the Shell out and in at night and checks the lit set equals the slot's set.

### 18.6 Itinerary "Your room" (itinerary owns its step; hotel owns rooms)
HotelService API (stable contract, B):
```text
HotelService.book(player, opts: {source: "itinerary" | "walkin", client: string?, companions: {{name: string, role: string?, seed: number?}}?, returnAt: number?})
    -> {ok: boolean, room: string?, name: string?, floor: number?, door: CFrame?, upgraded: boolean?, err: string?}
       -- err: NOT_ABROAD | LOADING | FULL ; already booked -> ok = true with the same room
HotelService.roomOf(player) -> (room: string?, info: {name: string, floor: number, door: CFrame}?)
HotelService.release(player, reason: string?)
HotelService.onCheckIn(fn(player, room)) -> disconnect      -- fires for itinerary bookings and walk-ins
HotelService.markerOf(room) -> BasePart?                    -- the RoomDoor marker (GPS / "Your room" target)
HotelService.ready() -> boolean                             -- interiors + lifts attached
```
- The itinerary ships first with its own "Your room" prompt / marker. **Plan A**: the itinerary exposes a provider hook
  (request text Appendix D.1, **filed by the critic on 2026-10-12 as section 1 of `design/requests/grandhotel.md`** - the itinerary package
  has not started, so it reads it as an open request): `Itinerary.setHotelProvider(fn)`; HotelService
  registers `fn = function(player, trip) return HotelService.book(player, {source = "itinerary", client = trip.clientName,
  companions = ..., returnAt = ...}) end` at init, and the itinerary's banner shows "Your room: <RoomName> <Room>" and points its
  GPS at `markerOf(room)`. **Plan B** (if the hook does not exist when the hotel is built): B adds the same 10-line hook to
  ItineraryService additively and lists it in its report.
- The itinerary's own fallback marker must sit at `CityPlan.INTL_HOTEL.reception` (or on the `ReceptionistPost`), never on
  other parts of today's hotel interior (`LiftFront`, `FloorSign`, `ReceptionDesk` ... are all replaced by the rebuild) - this
  is part of the filed request; the reception point stays a keep-free point (§7) *(critic)*.
- The colleague of the trip comes in through `companions`; the return time through `returnAt` (§14.5).

### 18.7 Other systems
| System | Use | Owner of the change |
|---|---|---|
| CityService | travel state (`abroad` or not) for check-in validation and release; nothing edited | - |
| AirTrafficController | unchanged; HotelController's local roof prompt uses its generic `CityAction == "heli"` dispatcher | - |
| GuestPlan | read-only require (`sample`, `sOfHour`, `dayOf`, `hash`) | - |
| EmployeeController | read-only require of `pose` | - |
| EmployeeRigDesign | uniforms + `hotel:` mapping (§14.1) | B, additive |
| CampusAudioConfig | silent hooks `hotelLobby = ""`, `spa = ""`, `pool = ""` (empty id = silent; no ids) | B, additive |
| MetroBuilder `towers()` | roof block replaced (§11) | A |
| CityBuilder `Builder.building` | `if b.id == "intl_hotel" then return GrandHotelBuilder.build(parent, b, {light = light, sign = sign, prompt = prompt}) end` at the top (CityBuilder's own locals, so the zone light budget is shared) - the City Hotel stays byte-identical | A |
| MetroPlan | Harbour Street `gaps`, 2 ACCESS points; `HOTEL_ROOF` untouched | A |
| Main.server / Main.client | require + init/tick of HotelService, HotelLiftService, HotelController | integrate prewire (frozen for builders) |
| Economy files, Net, admin | untouched | - |

---------------------------------------------------------------------------------------------------------------------

## 19. Budgets (today measured -> hard caps)

### 19.1 Parts
| Model (owner, streaming) | Today [M] | Estimate [D] | **Cap (test)** |
|---|---|---|---|
*(critic CC-12: the lead's estimates are recounted below. The interior numbers had no partition walls / room shells (8 studios x
~5 wall parts, suites ~30, spa rooms ~40) and the Shell sum left out the pool basin and under-counted the arches and the lift
landings; all estimates stay [D] until the joint build measures them - the caps are what the tests enforce.)*

| Model (owner, streaming) | Today [M] | Estimate [D] (critic) | **Cap (test)** |
|---|---|---|---|
| `Hotel_intl_hotel/Shell` (A, Atomic) | 36 | ~865 | **950** |
| `GrandLifts` (A, Default; 2 Atomic `GrandLiftCar`) *(new, CC-13)* | - | ~100 | **120** |
| `Forecourt` (A, Default) | - (forecourt slab was in Shell) | 90 | **110** |
| `RooftopHelipad` (MetroBuilder + A, Default) | 21 | 17 | **40** |
| `Interior` (B, Atomic) | 21 | ~420 | **450** |
| `SkylineFloor` (B, Atomic) | - | ~515 | **560** |
| `SpaFloor` (B, Atomic) | - | ~400 | **440** |
| `SuiteFloor` (B, Atomic) | - | ~550 | **600** |
| **Hotel total** | **78** | **~2,960** | **3,250** (model caps sum 3,270 <= hotel cap + 30) |
| Port Meridian (`WorldCity/PortMeridian`) | 5,253 | <= 8,429 (= 5,253 - 78 + 3,250 + 4 sidewalk splits) | zone <= 20,000 (`tests/world/test_build.luau:55`, world_check) |
| Port Meridian with the hotel frozen at 78 (metro test, must-fix F9, CC-11) | 5,253 | 5,257 | 781 + 4,500 = 5,281 (unchanged numbers; 24 left) |
| World (tier-1 dump) | 14,804 | <= 17,980 | <= 30,000 (`tests/world/test_build.luau:56`) |
| Parts within 512 studs (flat) of the hotel door | 2,514 [M] (critic, this dump; the lead's 2,467 came from `agents/grandhotel_design/life/measure.py`) | ~5,400 | - (context: a tier-4 HQ is 28,341 parts; every hotel floor model is Atomic, so a phone loads whole floors, never half) |

### 19.2 Lights
| Kind | Today [M] | Cap |
|---|---|---|
| Server real lights in the hotel | 3 (2 lobby, 1 helipad) | **exactly 3** (chandelier B, canopy A, helipad unchanged), `Shadows = false`, via the budgeted `light()` only |
| Port Meridian real lights | 40 / 40 | 40 / 40, same per-group distribution as before (street lamps keep theirs) |
| Client lights (HotelController) | 0 | **<= 3 at any time**, `Shadows = false`, range <= 24, created on entering a zone and destroyed on leaving: lobby bar backlight (1) + reception key wall (1); F8/F10 the room the camera is in (1-2: cove + bath); F9 pool `SurfaceLight` facing up (Range 18) + sauna (1); roof Lantern Room (1) |

### 19.3 Other caps
| Item | Today | Cap |
|---|---|---|
| `MetroNightGlow` parts on the hotel / in Port Meridian | 0 / 198 | ~295 / ~493; every one with a Color3 `GlowColor`; none inside B's models; none Glass or Transparency > 0.2 |
| Build-time Neon | - | no face > 24 sq studs; total largest-face area <= 400 sq studs in Shell + SpaFloor + SuiteFloor; max colour channel <= 230 on F9/F10 |
| Visible semi-transparent area (largest face of each part with 0.05 < Transparency < 0.95, whole hotel) | ~33,000 sq studs (the 9 glass bands' visible faces, judge's figure) | **<= 25,000 sq studs** (critic recount ~24,500 from the spec geometry -> **~23,200** after the 8-wide F8 windows (CC-9) and the opaque F2 panes (CC-10); biggest items: lift tower panes 5,300, F10 glazing 4,600, podium F1 panes 3,300, F9 glazing 2,750; `critic/translucent_est.py`) |
| Glass material | 11 parts | only the 2 turret lanterns; none within 12 studs of water |
| Server prompts | 0 | ~25 (lobby 5, F8 9, F9 4, F10 6, roof 1), all `Public = true` |
| Seats | 0 | ~130 |
| Server SurfaceGuis | 4 | <= 40 (room plates `MaxDistance` 30, TVs 40) |
| ParticleEmitters | 0 | <= 24, all disabled at build (`HotelSteam`), **<= 2 enabled per client**; Fire 2, <= 1 enabled per client |
| Staff rig templates (ReplicatedStorage, not in workspace) | 0 | 22 x <= 22 parts |
| Staff rigs drawn | 0 | **<= 8** (nearest first, floor band) |
| Guest figures drawn | 0 | **<= 12** |
| HotelController step | - | <= 30 Hz; `debug.profilebegin("GrandHotel.step")` / `profileend`; `HotelController.stats().lastStepMs`; **disconnected (one 1 Hz region check left) while the camera is > 200 studs from world (0, 24, 8440)**; rigs: <= 40 studs 30 Hz with limb swing, 40-90 studs 5 Hz, > 90 hidden (doorman + balcony figures to 160 from the street at 5 Hz); worst case 8 roots + 12 figures in one `BulkMoveTo`, <= 1,440 Motor6D writes/s |
| Server per-frame work | - | none, except `TargetPosition` at ~20 Hz while a physics car moves; HotelService 1 Hz tick (door timers, releases, turndown flags) |
| Network | - | attributes on change only (bookings, orders, doors / FxUntil, lift state); 2 server-owned lift assemblies in physics mode |

### 19.4 Cut list (in this order, if device profiling demands it [S])
1. rustication grooves (-16 parts); 2. guest figures 12 -> 6; 3. rigs drawn 8 -> 5; 4. hammam stars 16 -> 8; 5. F3/F7 side
balconies (-24); 6. café furniture (-20); 7. gym machines (-15); 8. `POOL_WINDOW = false`; 9. `LIFT_MODE = "express"`;
10. `POOL.mode = "part"`. *(critic)* Translucency reserve, applied first if `test_shell` measures more than 25,000 sq studs:
lift tower north / south panes opaque bronze-framed stone (-~3,000 sq studs; the east pane keeps the panoramic view).

---------------------------------------------------------------------------------------------------------------------

## 20. Streaming and LOD
- `Shell`: **Atomic** (G9) - a phone never sees a half-loaded facade, and the CityLife impostor rule (Shell < 3 children) stays
  correct. **Not Persistent** (`tests/metro/test_build.luau:141-145` allows only the spire; 900 parts must not ship to every
  client in the game).
- `Forecourt`, `RooftopHelipad`, `GrandLifts`: Default (each `GrandLiftCar` inside `GrandLifts` is Atomic). `Interior`,
  `SkylineFloor`, `SpaFloor`, `SuiteFloor`: Atomic (each floor appears whole).
- Place settings [M] (`agents/stable/pack_stable.py:126-133`): StreamingEnabled, MinRadius 128, TargetRadius 512, Improved,
  Opportunistic, MinimumRadiusPause. From the arrival plaza the hotel is the 6-part impostor (§5.5).
- The Terrain pool is outside the Atomic models and streams by region: the water may appear a moment before / after the basin [S].
- Lifts request streaming of the destination landing (§13.6). `Model.LevelOfDetail` is PluginSecurity -> not used.
- Client LOD: §19.3 (HotelController), PropFx's own LOD (NEAR 60 / FAR 120, sleeps > 24 studs above/below the camera), client
  lights per zone, emitters / Fire caps.

---------------------------------------------------------------------------------------------------------------------

## 21. Packages, file ownership, contract, order

### 21.1 Order of work
1. Drivers fix round lands; round 2b finishes (drivers, guests_jet, itinerary, verify2b). *(critic)* Files the hotel packages
   touch after 2b that a 2b package also touched (DrivePlan, MetroPlan, EmployeeRigDesign: drivers; CityLifeController: maybe
   guests_jet; ShuttleService: itinerary; ItineraryService: itinerary) are edited on their **post-2b** version, additively, and
   the owning package's suites are re-run (`tests/drivers/run.sh`, `tests/guests_jet/run.sh`, `tests/itinerary/*`,
   `tests/flight/run.sh`, `tests/metro/*`) - all rc 0 is a gate for A and B.
2. **Integrate prewire** (frozen-file owner): writes `GrandPlan.module.luau` v1 **verbatim from Appendix A**, empty stubs for every
   new module of A and B (so requires resolve), the `Main.server` / `Main.client` wiring (HotelService.init + tick, HotelLiftService.init
   + tick, HotelController.init) and the run_all lines for `tests/grandhotel/run.sh`; files Appendix D requests if still open.
3. **A and B in parallel.** B develops against a marker stub of the hotel built from GrandRooms (doors, posts, lift stops, seats at
   plan positions) until A's shell lands; A develops against a stub `GrandInteriors` (empty floors).
4. Joint verify: world dump, `world_check`, `world_entrances`, drivers + flight clearance, metro paths, run_all, renders, GUI previews.
5. Independent review -> fix round.

### 21.2 Package A "grandhotel_shell" owns
| File | Content |
|---|---|
| `ReplicatedStorage/Shared/Config/GrandPlan.module.luau` (after the prewire) | frozen v1 data; changes only through `design/requests/grandhotel_shell.md` |
| `ServerScriptService/Server/Services/GrandHotelBuilder.module.luau` (new) | `GrandHotelBuilder.build(parent, b, kit) -> Model`: model `Hotel_intl_hotel` (attrs `BuildingId`, `Zone`), `Shell`, `Forecourt`, roof pieces, **`GrandLifts`** (lift tower + anchored cars as Atomic `GrandLiftCar` models + landings + `LiftStop` markers + call prompts, CC-13), Terrain pool, night tags, exterior signs; calls `GrandInteriors.build(model, ctx)` in a pcall'd optional require |
| `CityBuilder.module.luau` | the id-gated hook (one line + require) |
| `MetroBuilder.module.luau` | `towers()` roof block (§11) |
| `MetroPlan.module.luau` | Harbour Street gaps, ACCESS points, **the two mouth walk paths in `pmPaths` (CC-3)** |
| `DrivePlan.module.luau` | `pm_hotel` (§6.3), after the drivers fix |
| `CityLifeController.module.luau` | impostor + `setLit` (§5.5, §18.5) |
| `tests/metro/test_build.luau` | budget scope split (F9) |
| `tests/drivers/*` | pm_hotel expectations only if they pin the old place |
| `tests/grandhotel/test_plan.luau`, `test_shell.luau`, `test_drive.luau`, `nightify.py`, `render_shell.py`, `run.sh` (calls `run_shell.sh` and `run_inside.sh`), `run_shell.sh`, `negative_shell.sh` | A's suites |

### 21.3 Package B "grandhotel_inside" owns
| File | Content |
|---|---|
| `ReplicatedStorage/Shared/Config/GrandRooms.module.luau` (new) | rooms (§12.1), zones, posts, waypoint graphs (Appendix B), client light plan, prompt list |
| `ReplicatedStorage/Shared/GrandStaffPlan.module.luau` (new) | pure: roster (§14.2), staff + guest actors per day, cue timelines (doorman, bellhop, waiter, turndown, colleague) |
| `ServerScriptService/Server/Services/GrandInteriors.module.luau` (new) | `GrandInteriors.build(hotel, ctx)` -> `Interior`, `SkylineFloor`, `SpaFloor`, `SuiteFloor` (ArchKit helpers; lights only via `ctx.light`, allowance 1) |
| `ServerScriptService/Server/Services/HotelService.module.luau` (new) | bookings, prompts, `onTripAction("hotel")`, doors, orders, staff templates, phone hook, itinerary API |
| `ServerScriptService/Server/Services/HotelLiftService.module.luau` (new) | LiftLogic per car, physics attach / express mode, calls, rate limits, streaming |
| `StarterPlayer/StarterPlayerScripts/Client/Controllers/HotelController.module.luau` (new) | staff, guests, cues, client lights, steam caps, local prompts, window pattern, coves, flag, markers, fades |
| `StarterPlayer/StarterPlayerScripts/Client/UI/Hotel/KeyCard.module.luau`, `LiftPanel.module.luau`, `StaySheet.module.luau` (new) | §17 |
| `EmployeeRigDesign.module.luau` | additive uniforms + mapping |
| `CampusAudioConfig.module.luau` | additive silent keys |
| `ShuttleService.module.luau` | additive roof arrival / start (§18.3) |
| `PhoneService.module.luau` | additive reception hook fall-through (§18.4) |
| `ItineraryService.module.luau` | only Plan B of §18.6 |
| `tests/flight/test_shuttle.luau`, `test_client.luau` | minimal update for the roof arrival flag |
| `tests/grandhotel/test_rooms.luau`, `test_staffplan.luau`, `test_service.luau`, `test_lift.luau`, `test_client.luau`, `npc_paths.py`, `gui_hotel.luau`, `render_inside.py`, `run_inside.sh`, `negative_inside.sh` | B's suites |

No file appears in both lists.

### 21.4 A <-> B contract
1. **GrandPlan v1** (Appendix A): both read it; only A edits it (requests from B in `design/requests/grandhotel_shell.md`).
2. **Builder call**: A's `GrandHotelBuilder.build` creates the model and the Shell, then calls
   `GrandInteriors.build(model, ctx)` with `ctx = {plan = GrandPlan, kit = ArchKit, light = <CityBuilder light (budgeted)>, sign =
   <CityBuilder sign>, prompt = <CityBuilder prompt (sets Public)>}`. B returns nothing; it parents its four models under `model`.
   A's tests run with a stub that builds empty floors; the joint suite builds both.
3. **Envelope split**: A builds the slabs listed in §5.1 (including the F1 `Floor`), all exterior walls and glazing (F1-F10), the
   pool basin + lip + trough + barrier + Terrain fill + pool window panel, the revolving door and side doors, the lift tower,
   cars, landings, `LiftStop` markers and call prompts, the roof, the turrets' shells, the F9/F10 terraces' decks and balustrades.
   B builds everything inside the zones of `GrandRooms` (partitions, room doors, furniture, fixtures, interior prompts, posts,
   the chandelier and its light, terrace furniture: whirlpools, loungers, hot tub), the Lantern Room interior and the atrium
   gallery ring.
4. **Markers B relies on** (names + attributes, built by A): `GrandLifts` (model) containing `GrandLiftCar` (`Car`, `Stops`; Atomic) with `CabinFloor`; `LiftGuide`;
   `LandingDoor` (`Car`, `Stop`); `LiftStop` (`Car`, `Stop`, `Y`); call prompts (`HotelAction = "liftcall"`, `Stop`); `Windows`
   panes with `GrandWindow` index; the pad's `Helipad` part (existing); `HelipadExit`; the porch posts `DoormanPost` (D1, D2),
   `LimoDoorMark` (DL), `BellStand` (BS) - invisible 1 x 1 x 1 parts at the §6.4 points; the facade flags `HotelFlag` (1..4).
5. **Lights**: A uses 1 (canopy) + the helipad's existing one; `ctx.light` lets B create exactly 1 (chandelier). The joint test
   asserts hotel real lights == 3.
6. **Night tags**: only A tags; B never tags.

---------------------------------------------------------------------------------------------------------------------

## 22. Tests (all in the mock unless noted; every suite prints "<name>: N passed, M failed")

### 22.1 Package A (`tests/grandhotel/`)
| Suite | Asserts |
|---|---|
| `test_plan.luau` (pure GrandPlan) | `LEVEL.ROOF + 24 == MetroPlan.HOTEL_ROOF` (150.2); F3..F10 floor tops 12 apart; pool world bounds (x -24..24, y 116..124, z 8380..8400) all multiples of 4 and water top == F9 world floor - 1; lip top == water top; cornice top < water top; lift stops == the LEVEL values; *(critic)* the rear right door x of **both looks** (`DRIVE.stop.X - rearDoorOffset` = 14.6, `- meshRearDoorOffset` = 10.2) inside the east side door span x 9..15 (+-0.5); `LIFT.tower.y2 >= LIFT.stops[R].y + cabinHeight + 1`; `STAIR_VOID` covers the side flights (x +-12..20, lz 78..92); the urns / porch lanterns at lz >= `porchKeepOutZ`; KEEP_FREE == `CityPlan.INTL_HOTEL` door / lobby / reception (local); IMPOSTOR has 6 boxes; CAPS sum consistent (models <= hotel cap + 30) |
| `test_shell.luau` (world build through `CityBuilder.build`, once with a stub `GrandInteriors`, once with the real one when present) | Shell <= 950, GrandLifts <= 120, Forecourt <= 110, RooftopHelipad <= 40, hotel <= 3,250; *(critic)* no `GrandLiftCar` and no unanchored part inside `Shell`, each `GrandLiftCar` Atomic; every hotel part inside x -76..83, lz -28..122 (footprint + facade projections such as the royal balcony, colonnade, cornices, flags and side balconies + the drive + `GrandLifts`), and nothing of MetroPlan (lots, lamps, trees, walk nodes, roads) inside x -76..-70 / 70..83 for lz 0..120 (measured free today); no F1 ceiling / F2 solid part intersects `STAIR_VOID`; no north-face window pane overlaps another pane or x -29.5..29.5 at F8; the Harbour Street south walk line is still one connected component from x -100 to x 100 (the mouth paths, CC-3); **hotel real lights == 3** and Port Meridian <= 40 with the same per-group distribution as the baseline dump; >= 250 hotel parts tagged `MetroNightGlow`, each with Color3 `GlowColor`, none inside `Interior` / `SkylineFloor` / `SpaFloor` / `SuiteFloor`, none Material Glass or Transparency > 0.2; `Shell` ModelStreamingMode Atomic, `Forecourt` Default, no Persistent model in the hotel; everything anchored (cars included); decor flags (non-colliding => no touch / query); `Helipad` top == 151.2; highest collidable hotel part under the pad centre == 150.2 +- 0.05; exactly one `HelipadExit` with `To = "intl_hotel"` at `GrandPlan.HELIPAD_EXIT` +- 0.05; signage contains `MERIDIAN GRAND HOTEL`, ASCII + allowed glyphs only, no brand words; **City Hotel unchanged (61 parts, same names)**; determinism (two builds identical); **Terrain: `meta.terrainOps` holds exactly one `FillBlock` with `Enum.Material.Water` equal to the pool rect when `POOL.mode == "terrain"`, and none plus one part `PoolWater` when "part" (both modes)**; nothing above the pad top within 16.4 studs (flat) of world (0, 8408) except pad parts; turrets >= 40 from the pad axis; *(critic)* the helicopter's measured corridor is empty - transit along x = 0 at y 182..214 from z 8253 to 8400, hover at y 181.2 over the pad, vertical descent (`out/flight_clearance/log.txt`, poses `heli_to_hotel` / `heli_to_airport`): no hotel part inside x -20..20, z 8320..8388 above y 164, nor inside r 20 around (0, 8408) above y 151.4 except pad parts (the flight package's own sweep only tests poses below 150 studs above the ground, so this check is the hotel's); **no Material Glass within 12 studs of the Terrain block or any `*Water` part**; visible semi-transparent area <= 25,000 sq studs; build-time Neon: no face > 24 sq studs, total <= 400 sq studs, F9/F10 max channel <= 230; `Floor` part present with the building frame orientation; destination points and the entrances lobby probe (-20, 25.25, 8392) not inside solids; the porch kerb, island kerbs and drive slab tops inside y 23.5..25.7 (no holes) |
| `test_drive.luau` | `Drive.place("pm_hotel")`: stop (**19**, RT, 8368.5) heading +X; door (12, 27.5, 8376) facing +Z; the rear right seat (`Drive.seatCF("rearR", "limo", ...)`) world x within 0.6 of **14.6**; a route `pm_limo -> pm_hotel` exists and lasts 15..70 s (sandbox: 40.5 s); at the stop **neither** the part box (21 x 7.4, centred) **nor the mesh box (front 12.44 / rear 13.32 x 7.36)** overlaps x -4..4 or any canopy column; *(critic)* the swept bodies of both looks along every `pm_hotel` leg (`Drive.poseAtDist` every 0.5 stud, wheelbase 13 / 18.10) keep >= 0.5 stud from every collidable or > 0.6-high Forecourt part (urns, lanterns, columns, island decor) and >= 0.8 from the signal post; the out leg ends on the boulevard northbound lane (x 45 +- 1) heading -Z |
| re-run gates | `tests/drivers/*` + `tests/drivers/clearance.sh` (**0 hits**, part **and** `#mesh` legs - with the lead's porch positions 14 mesh legs hit, critic CC-2), `tests/flight/clearance.py` (`flight_clearance`, 0 hits), `tests/metro/test_build.luau` (with the F9 scope split), `test_paths.luau`, `test_life.luau` (impostor count unchanged), `test_plan.luau`, `tests/world/*` (23 `Interior`, 20 `ReceptionistPost`, Public prompts, destination points, Persistent caps), `world_check` (holes at the drive / mouths, abroad <= 20,000, lights <= 40), `world_entrances` (intl_hotel probes 3/3, every prompt below y 70 reachable on foot), `metro_reach` |

Negative mutations A (`negative_shell.sh`, each must make a check fail): a 4th real light (`Kit.light` on the canopy); pool block
shifted by 2 studs (off the grid); a canopy column moved to lz -14 (limo lane -> drivers clearance); a turret moved to x 10
(heli clearance); `GlowColor` removed from one pane; a tagged pane set to Glass; roof slab top 150.0; a second `HelipadExit`;
Shell streaming mode Default; a 48 x 48 Neon panel added to the loggia; a Glass part next to the pool; the lip raised to 101.
*(critic additions)* stop A back at x 16 (mesh box over the walk gap -> test_drive); an urn back at lz -3 (mesh sweep ->
test_drive + `clearance.sh`); one mouth walk path removed (south walk line splits -> test_shell); a `GrandLiftCar` parented
into `Shell` (-> test_shell); lift tower cap at ly 135 (-> test_plan); the F2 mezzanine box back over lz 78..92 (-> test_shell
`STAIR_VOID`); the F8 802 window back at x -32, 10 wide (pane overlap -> test_shell); the metro budget counted without the
hotel but with BASE 781 (-> a pinned expectation in test_build: 24 parts left, not 102).

### 22.2 Package B (`tests/grandhotel/`)
| Suite | Asserts |
|---|---|
| `test_rooms.luau` | `#GrandRooms.ROOMS >= CampusConfig.PLOT_COUNT`; ids unique; rects inside the floor envelopes; no overlaps; every room >= 20 studs both ways; every door on lz 56 or 68 inside its room's edge; built floors: one `RoomDoor` + one `DoorBlock` per room at the plan position +- 0.05 with `Room` / `RoomName` / `Floor`; one `ReceptionistPost` (`CityPost = "hotel_reception"`) in the hotel and 20 in the world; every server prompt `Public = true` with a whitelisted `HotelAction`; floor model caps; the four models Atomic; exactly one model named `Interior` in the hotel; no `MetroNightGlow` tag in B's models; B created exactly one light (the chandelier); lounge Seats face their table / view; keep-free points (LP radius 4, RX, lobby probe) clear |
| `test_staffplan.luau` (pure) | *(critic)* every route step is an Appendix B edge (the plan validator checks the same since the critic pass); housekeeping rounds end by 16:00 (F8 60 s, F10 100 s per room + walks); turndown visits start 17:00, sequential, none drawn after 19:30; two night-security rounds (19:30 F8, 01:00 F10) that never overlap; arriving shift staff are at their post 3 s before the change; on duty at 12:00 = 16, at 03:00 = 3; shift-change segments at 07:00 / 19:00 end / start at the staff-door portal; breakfast segments only inside 07:00-10:30; pianist only 19-23; same day -> identical actors, next day -> different guest actors (same staff posts); continuity: every actor sampled every 0.25 s moves <= 5 studs/s except across portal nodes; **doorman cue: walk starts at T - 3.5, at DL by T - 1.1 (9.5 studs at 4 studs/s), `reach` covers T + 1.2, DL within 3.5 studs of the drop door** (no sprint); room service knock by O + 45; <= 12 guest figures visible per floor band at any sampled time; turndown only while the occupant is out; housekeeping skips DND / occupied rooms; every actor path uses only Appendix B edges |
| `test_service.luau` | check-in: zone, distance, throttle, best-free order, upgrade line, idempotent repeat; **12 players -> 12 distinct rooms, 13 -> 13, 14th -> `FULL`**; **two players racing for 1001 in the same frame -> exactly one gets it**; door: occupant / invitee ok, other player `WRONG_ROOM`, no room `NO_ROOM`, far, cooldown; `DoorBlock` collides again after 4 s; knock (DND blocks, throttle, occupant notice); invite (<= 3, within 30, both in PM) / uninvite; DND; room service (cooldown 120, attribute format, `ORDER_OPEN`); jets / sauna / secret door write only `FxUntil`; lift op (inside the cabin, `KEY_REQUIRED` for 8 / 10 without a key, stop whitelist, rate limit); checkout; release on leaving PM, PlayerRemoving and respawn; itinerary API (`book` / `roomOf` / `release` / `onCheckIn` / `markerOf`, `NOT_ABROAD`, `LOADING`, companions -> attributes); phone hook returns nil without a room; **economy proof: money / ledger snapshot identical before and after every op (spies on `Economy.spend` / `grant` record zero calls), session data diff empty (no saved field), no hotel module requires Economy / EmpireService (static check)** |
| `test_lift.luau` | LiftLogic with the 5 stops: L -> R <= 16 s, hall + car calls de-duplicated, doors never close on a rider (reuse `tests/lift_logic.luau` patterns); physics: anchored before `attach`, unanchored + welds + `PrismaticConstraint` after (servo emulation like `tests/lift_service.luau`), riders carried; **express: riders and cabin `PivotTo`'d by the same offset, `RequestStreamAroundAsync` called with the destination landing, `CANCELLED` for a rider who left or respawned**; both modes share the panel API; capacity 6; out-of-service text |
| `test_client.luau` | HotelController in the mock with a fake clock and camera: *(critic)* the five hotel ScreenGui names are in `PhoneController.PANELS` after init and opening one closes an open phone; after the Shell streams out and back in at night the lit pane set equals the slot's set (CC-18); the doorman's DL / suitcase spot follow `DriveController.findMesh()` (both looks); <= 8 rigs, <= 12 figures, <= 3 client lights all `Shadows = false`, <= 2 enabled emitters, <= 1 enabled Fire; staff on other floors hidden; **step disconnected when the camera is > 200 studs from (0, 24, 8440) and reconnected inside**; `stats().lastStepMs` present; doorman cue started from a fake ride folder (`To = "pm_hotel"`, `Plan` encoded with `Drive.encode`) at T - 3.5; `CityLife.setLit` called only at night, the lit share per slot within +-5 % of LIT_SHARE; booked-room coves Neon only at night; panels inside CoreUISafeInsets, buttons >= 44, `GuiService.SelectedObject` set to the first enabled button, ButtonB closes |
| `npc_paths.py` | every Appendix B edge swept as a capsule (radius 1.2, feet +0.6..+5) against the collidable parts of the built hotel dump; nodes not inside solids; posts within 1.5 of their markers; seats reachable (`tests/guests_jet/hotel_paths.py` pattern) |
| `gui_hotel.luau` + guiprev | the previews of §23.2, `--report` clean |

Negative mutations B (`negative_inside.sh`): a door opens for another player; room service charges $1 (ledger check); a saved
field added; a staff edge through the reception desk (npc_paths); only 11 rooms (PLOT_COUNT check); a second model named
`Interior`; a `MetroNightGlow` tag on a suite pane; lift stop 8 accepted without a key; a 4th client light; a 9th rig; step still
connected at 260 studs; doorman walk starting at T (late); a `Kit.light` in the lobby (light count).
*(critic additions)* the old F8 housekeeping route (C7 -> C6, not an edge -> test_staffplan); turndown slots from the old
formula (3.3 s apart -> continuity <= 5 studs/s fails); night-security rounds every 3 company hours (overlap -> test_staffplan);
F8 housekeeping at 78 s per room (round ends after 16:00 -> test_staffplan); the concierge prompt with `GamepadKeyCode =
ButtonY` (-> test_rooms: no ButtonY prompt); a second handler registered for TripAction `"hotel"` after HotelService (->
test_service); setLit pattern not re-applied after a stream-in (-> test_client); a hotel panel missing from
`PhoneController.PANELS` (-> test_client).

### 22.3 How to run
`tests/grandhotel/run.sh` (calls `run_shell.sh` and `run_inside.sh`), then `negative_shell.sh` / `negative_inside.sh`; both packages
also run the full verification loop of round 2b (luau-compile, lsp, `RUNALL_TAG=<pkg> tests/lead/run_all.sh`, `GEN=<pkg>
harness/run.sh --out out/<pkg> --check`).

---------------------------------------------------------------------------------------------------------------------

## 23. Renders and GUI previews (LOOK at every image; iterate until clean)

### 23.1 blenderprev shot list (`python3 tools/blenderprev/shots.py custom --scene world --cam x,y,z --look x,y,z --lens L
[--preset day|golden|night]`, world coordinates, dump of the built hotel)
`tests/grandhotel/nightify.py` turns a dump into the night look players see: CityLife's `nightLook` on tagged parts (the 45 % hash,
or the LIT_SHARE pattern for a given hour), booked-room coves for 3 sample rooms, client lights of the zone. Render-only stand-ins
are named in the file name: `PoolWaterRender` (blenderprev draws no Terrain), a static limo copy at stop A, rig copies without
Humanoid for staff and guests (the world scene drops Humanoid rigs), no SurfaceGui text (overlay via `agents/airport/textshots.py`
where text matters), no particles.

| Shot | cam -> look (world) | lens / preset | Judges |
|---|---|---|---|
| `gh_hero_golden`, `gh_hero_night` | (-10, 29.5, 8160) -> (0, 84, 8400) | 24 / golden, night | facade hierarchy, no office look, **night: no light box at the top** (F5) |
| `gh_hero_phone` | same at `--res 1688x780` | 24 / golden | what an iPhone shows in landscape |
| `gh_porte_golden`, `gh_porte_night` | (-44, 29.5, 8338) -> (2, 36, 8386) | 22 / golden, night | canopy, bulbs, flags, limo at stop A, walkers' gap |
| `gh_limo_doorman` | (34, 28, 8352) -> (12, 28, 8373) | 28 / golden | doorman at DL beside the rear door, founder at the drop point, bellhop with the cart |
| `gh_lobby_atrium` | (0, 30.5, 8386) -> (0, 40, 8452) | 18 / day | chandelier, rug, stair, laylight, gallery |
| `gh_reception_staff` | (24, 30, 8392) -> (46, 30, 8418) | 24 / day | receptionists typing, key wall + aquarium, a guest checking in (staff at work) |
| `gh_bar_night` | (-26, 30, 8452) -> (-56, 29, 8486) | 22 / night | bar, piano with the pianist, guests |
| `gh_pool_loggia` | (-6, 130, 8398) -> (0, 118, 8250) | 18 / golden | **the spa shot**: water to the edge, boulevard below |
| `gh_spa_staff` | (10, 130, 8440) -> (0, 128, 8410) | 22 / day | pool attendant, loungers, 2 swimmers (stand-ins), whirlpool |
| `gh_sauna`, `gh_hammam`, `gh_cold_zone` | (-46, 129, 8442) -> (-52, 127, 8448); (-28, 128, 8445) -> (-28, 134, 8448); (-20, 129, 8475) -> (-45, 126, 8472) | 18 / day | interiors (particles not drawn: say so) |
| `gh_studio_801`, `gh_studio_806` | (-58.5, 117.5, 8430) -> (-58.5, 116, 8380); (-27.75, 117.5, 8460) -> (-27.75, 116, 8500) | 20 / golden | standard room: tub at the window, boulevard / spire |
| `gh_penthouse_living`, `gh_penthouse_bath`, `gh_penthouse_cinema` | (-12, 142, 8420) -> (-12, 140, 8300); (-30, 141, 8430) -> (-48, 139, 8431); (-8, 141, 8432) -> (-8, 141, 8406) | 18 / golden, golden, night | the "krass" proof |
| `gh_lantern_room` | (-44, 156, 8386) -> (0, 152, 8408) | 20 / golden | glass room in the gold turret beside the pad |
| `gh_panorama_aquarium` | (18, 141, 8396) -> (18, 140, 8409) | 20 / day | aquarium wall |
| `gh_spire_suite_bath` | (22, 141, 8478) -> (10, 140, 8540) | 20 / night | spire in the window |
| `gh_roof_aerial` | (90, 199, 8340) -> (0, 152, 8440) | 30 / golden | roof, turrets, pad, terraces, lift tower |
| `gh_aerial_city_day`, `gh_aerial_city_night` | shots.py `pm_hotel` camera | - / day, night | skyline integration, lit-window pattern |
| `gh_impostor_plaza` | (0, 40, 7740) -> (0, 80, 8440), dump with the 6 impostor boxes inserted instead of the hotel (labelled) | 35 / golden | silhouette from the airport |
| *(critic)* `gh_limo_mesh_stop` | (36, 31, 8350) -> (12, 27, 8372) with a 25.76 x 7.36 x 5.09 stand-in of the ExecutiveLimo at stop A (pivot 19; labelled "mesh stand-in") | 24 / golden | the walk gap x -4..4 stays free, rear door at the east side door, urns behind the keep-out line |
| *(critic)* `gh_spa_cutaway` | (0, 236, 8436) -> (0, 125, 8440), dump with `SuiteFloor`, the F10 slab, roof and turrets removed (render-only cutaway, labelled) | 30 / day | **the whole wellness floor in one picture**: pool to the edge, sauna, hammam, cold zone, gym, relax lounge, staff and swimmers (stand-ins) |
| *(critic)* `gh_suites_cutaway` | (0, 250, 8440) -> (0, 137, 8440), dump with roof + turrets removed above ly 124 (labelled) | 30 / golden | **all five suites from above**: penthouse with cinema, terrace whirlpool, aquarium wall, spire bath |
| *(critic)* `gh_staff_lineup` | (0, 30.5, 8392) -> (0, 29, 8440), render-only: the 22 staff rig copies (no Humanoid) standing in two rows on the atrium rug in uniform | 22 / day | **"the hotel has staff"**: every role and uniform readable, badges overlaid with `textshots.py` |

### 23.2 GUI previews (`tools/guiprev`, `--viewport phone --dpr 2 --report` and `--viewport desktop --report`)
Key card (fresh, upgraded, already booked); key chip (both positions); stay sheet (DND off / on); lift panel (on L, on 8 with the
key, on 9 without a key = 8 / 10 disabled + caption "Key card needed"; gamepad selection visible; two-line labels readable at
phone size *(critic)*); the phone open when the lift panel appears (-> the phone closes, `PhoneController.PANELS`); room-service menu; invite list (0, 3, 6 players);
toasts ("Brrr! Cold plunge done.", "Spa routine complete, Finnish style.", KEY_REQUIRED). Checks: nothing under the top bar, every
target >= 44 pt, no overlap with DriveController's ride HUD (bottom), the itinerary banner (whatever it ships) and the existing
HUD / phone button.

---------------------------------------------------------------------------------------------------------------------

## 24. Only Studio (or a real iPhone) can confirm
1. Terrain water at y 116..124 in an open loggia: look, `Swimming` state, edges against the basin parts, streaming timing vs the
   Atomic floor; fallback `POOL.mode = "part"`.
2. The pool window: Terrain water seen through a SmoothPlastic panel (fallback `POOL_WINDOW = false`).
3. Physics cars with 2-3 riders on an iPhone: jitter at 10 studs/s; fallback `LIFT_MODE = "express"`.
4. Atomic `Shell` streaming behaviour at the 512-stud edge with MinimumRadiusPause (does it pop in as one piece, any stall?).
5. Frame time and draw calls on an older iPhone at the porte-cochère at night looking up, in the atrium, and on the pool deck;
   apply the §19.4 cut list in order if needed.
6. Neon on graphics level 1 (no bloom): does the night facade still read? Are the turret fins and bulbs bright enough?
7. Client lights: per-pixel light limits on iPhone with the chandelier + 3 client lights.
8. Seats: lounger recline, sitting in the whirlpools / tubs (body in the water), the bed-edge "Rest" Seat.
9. Revolving door: walking through non-colliding wings feels right; side doors slide in time.
10. Gold Metal vs Foil colour (Cycles renders Foil white-hot).
11. Prompt crowding in the lobby on a phone (CQ on F next to the heli prompt; knock vs open at doors).
12. The limo crossing the Harbour Street junction while CityLife cars run their lights (cosmetic).
13. CoreUISafeInsets on a real notch phone (the key chip next to the existing HUD).
14. *(critic)* Moving `GrandLiftCar` assemblies (Atomic models inside the Default `GrandLifts`) under StreamingEnabled with
    MinimumRadiusPause: no pop-in of a car mid-ride; fallback `LIFT_MODE = "express"`.
15. *(critic)* ProximityPrompt key input vs `PhoneController`'s P / ButtonY toggle: confirm no hotel prompt opens the phone (no
    hotel prompt uses ButtonY / P by design).
16. *(critic)* The limo body overhanging the porch kerb on the turns (up to lz -3.8 with the mesh) reads naturally; CityLife
    walkers crossing the drive mouths at road level while a limo passes (cosmetic, as elsewhere in Port Meridian).

---------------------------------------------------------------------------------------------------------------------

## 25. Open questions for the lead / user - answered by the critic (2026-10-12); nothing needs the user
1. **Itinerary provider hook**: **decided - filed.** The critic filed Appendix D.1 (with two additions: the reserved TripAction
   key `"hotel"` and the fallback marker at the reception point) as `design/requests/grandhotel.md` section 1; the itinerary package has
   not started, so it picks it up as an open request. If it is still not implemented when the hotel is built, B uses Plan B.
2. **Two limousines at the hotel** (up to 90 s for a waiting pick-up car, not ~6 s): **decided - accepted as cosmetic** for this
   build, no drivers request now (reasons in §6.3: same behaviour at every shared kerb place, drivers fix round still running).
3. **Truncated must-fix list**: **decided - closed.** The cut sentence was the end of F12 (translucent area), recounted in CC-10;
   the critic's own pass covers the rest (Critic changes).
4. MaxPlayers above 13 would make `FULL` reachable (honest text, public areas stay open).
5. With `HELI_ROOF` on, helicopter arrivals land on the roof and walk to the lift (intended; flight tests updated by B).
6. German UI is not planned (the game UI is English); the user's German wishes are answered in English signs and lines.

---------------------------------------------------------------------------------------------------------------------

## Appendix A. GrandPlan v1 (`ReplicatedStorage/Shared/Config/GrandPlan.module.luau`, written verbatim by the integrate prewire)

Compiled with `tools/luau-compile` and type-checked with `people_harness/lsp.sh` (strict, Roblox definitions): 0 diagnostics.
*(critic: re-compiled and re-type-checked after the critic edits - DRIVE stop 19 + mesh limo data + porch keep-out + mouth walk
paths, STAIR_VOID, LIFT.model / tower y2 139, CAPS with GrandLifts and hotel 3,250: luau-compile OK, lsp 0 diagnostics.)*
Source copy: `agents/grandhotel_design/lead/GrandPlan_v1.module.luau`.

```lua
--!strict
-- GrandPlan v1 (frozen 2026-10-11, critic pass 2026-10-12; design/GRANDHOTEL_SPEC.md Appendix A). Pure data for the Meridian Grand Hotel rebuild.
-- Owner after the integrate prewire: package grandhotel_shell (A). Package grandhotel_inside (B) reads it; change requests
-- go to design/requests/grandhotel_shell.md.
-- Local frame = the CityPlan frame of intl_hotel: origin world (0, 24, 8380), identity rotation, -Z = street (north).
-- world = (x, 24 + ly, 8380 + lz). Every Vector3 below is LOCAL unless its key ends in "World".
local Plan = {}

Plan.VERSION = 1
Plan.ORIGIN = CFrame.new(0, 24, 8380)
function Plan.toWorld(v: Vector3): Vector3
	return Vector3.new(v.X, v.Y + 24, v.Z + 8380)
end
function Plan.toLocal(v: Vector3): Vector3
	return Vector3.new(v.X, v.Y - 24, v.Z - 8380)
end

-- footprint and levels (floor tops, local ly)
Plan.FOOTPRINT = { x1 = -70, x2 = 70, z1 = 0, z2 = 120 }
Plan.LEVEL = { L1 = 0.5, L2 = 17, F3 = 29, F4 = 41, F5 = 53, F6 = 65, F7 = 77, F8 = 89, F9 = 101, F10 = 113, ROOF = 126.2 }
Plan.CEILING = { L1 = 16, ATRIUM = 28, F8 = 100, F9 = 112, F10 = 124 }
Plan.ROOF_WORLD = 150.2 -- must equal MetroPlan.HOTEL_ROOF (test_plan)
Plan.ENVELOPE = {
	L1 = { x1 = -69.5, x2 = 69.5 }, F8 = { x1 = -69.5, x2 = 69.5 },
	F9 = { x1 = -60, x2 = 60 }, F10 = { x1 = -50, x2 = 50 }, ROOF = { x1 = -50, x2 = 50 },
}
Plan.CORRIDOR = { z1 = 56, z2 = 68 } -- corridors + lift landings on every floor
Plan.ATRIUM_VOID = { x1 = -24, x2 = 24, z1 = 24, z2 = 72 }
Plan.GALLERY_RING = { x1 = -30, x2 = 30, z1 = 18, z2 = 78 }
-- imperial stair hall: no F1 ceiling slab and no F2 mezzanine solid here (the side flights rise to the gallery at ly 17)
Plan.STAIR_VOID = { x1 = -30, x2 = 30, z1 = 72, z2 = 106, y1 = 16, y2 = 28 }

-- infinity pool (Terrain water on the 4-stud grid in world coordinates: x -24..24, y 116..124, z 8380..8400)
Plan.POOL = {
	mode = "terrain", -- "terrain" | "part"
	x1 = -24, x2 = 24, z1 = 0, z2 = 20, y1 = 92, y2 = 100,
	lip = { z1 = -1.2, z2 = 0, top = 100 },
	trough = { z1 = -4, z2 = -1.2, top = 99.4 },
	barrier = { z1 = -1.6, z2 = -1.2, y1 = 100, y2 = 106 },
	basin = { x1 = -25, x2 = 25, z1 = -1, z2 = 21, y1 = 89, y2 = 100 },
	fillCFrameWorld = CFrame.new(0, 120, 8390),
	fillSizeWorld = Vector3.new(48, 8, 20),
}
Plan.WATER = { color = Color3.fromRGB(40, 170, 190), transparency = 0.7, reflectance = 0.4, waveSize = 0.05, waveSpeed = 6 }
Plan.POOL_WINDOW = true -- false = opaque tiles + aqua strip
Plan.COLONNADE = { xs = { -25, -15, -5, 5, 15, 25 }, z = -3, diameter = 3.6, shaft = { y1 = 34, y2 = 89 }, capital = { y1 = 89, y2 = 91.5 },
	entablature = { x1 = -29, x2 = 29, z1 = -5, z2 = 0, y1 = 91.5, y2 = 99.4, frieze = { y1 = 93.5, y2 = 97 } } }

-- lifts (stops = LiftLogic levels 1..5; heights = local ly = servo position)
Plan.LIFT_MODE = "physics" -- "physics" | "express"
Plan.LIFT = {
	model = "GrandLifts", -- own model under Hotel_intl_hotel (not in the Atomic Shell); each car its own Atomic model
	tower = { x1 = 70, x2 = 81, z1 = 54, z2 = 70, y1 = 0, y2 = 139 }, -- car roof at stop R = 126.2 + 10 (+0.4)
	cars = {
		{ id = 1, x1 = 71, x2 = 80, z1 = 55, z2 = 61.5, door = { z1 = 56.25, z2 = 60.25 }, startLevel = 1 },
		{ id = 2, x1 = 71, x2 = 80, z1 = 62.5, z2 = 69, door = { z1 = 63.75, z2 = 67.75 }, startLevel = 5 },
	},
	stops = {
		{ id = "L", level = 1, y = 0.5, label = "L Lobby" },
		{ id = "8", level = 2, y = 89, label = "8 Skyline", key = true },
		{ id = "9", level = 3, y = 101, label = "9 Sky Spa" },
		{ id = "10", level = 4, y = 113, label = "10 Suites", key = true },
		{ id = "R", level = 5, y = 126.2, label = "R Helipad" },
	},
	capacity = 6,
	cabinHeight = 10,
	callPrompt = { x = 64, z = 62 },
}

-- drive-up (porte-cochere); DrivePlan pm_hotel uses the world values
Plan.DRIVE = {
	laneZ = -11.5,
	stop = Vector3.new(19, 0.22, -11.5), -- car pivot, heading +X (x 19: the mesh limo's rear end stays east of x 5.6)
	stopWorld = Vector3.new(19, 24.22, 8368.5),
	rearDoorOffset = 4.4, -- Drive.SEATS.limo.rearR z (part-built limo): rear door x 14.6
	meshRearDoorOffset = 8.8, -- DriveController.MESH.seats.rearR z (ExecutiveLimo): rear door x 10.2
	limo = { length = 21, width = 7.4 }, -- part-built, centred on the pivot
	meshLimo = { front = 12.44, rear = 13.32, width = 7.36 }, -- ExecutiveLimo at scale 0.95 (pivot between the axles)
	porchKeepOutZ = -2.6, -- on the porch: nothing collidable or taller than 0.6 at lz < this (limo sweep reaches lz -3.8)
	urns = { Vector3.new(-28, 0.5, -1.5), Vector3.new(-24, 0.5, -1.5), Vector3.new(24, 0.5, -1.5), Vector3.new(28, 0.5, -1.5) },
	porchLanterns = { Vector3.new(-20, 0.5, -0.8), Vector3.new(20, 0.5, -0.8) },
	door = Vector3.new(12, 3.5, -4), -- founder root after getting out, faces +Z
	doorWorld = Vector3.new(12, 27.5, 8376),
	approachWorld = { Vector3.new(-45, 24.22, 8250), Vector3.new(-45, 24.22, 8368.5) },
	departWorld = { Vector3.new(45, 24.22, 8368.5), Vector3.new(45, 24.22, 8250) },
	slab = { x1 = -54, x2 = 54, z1 = -20, z2 = -6.6, top = 0.22 },
	mouths = { { x1 = -54, x2 = -36 }, { x1 = 36, x2 = 52.6 } }, -- MetroPlan pm_harbour gaps (side 1)
	accessWorld = { { -45, 8356 }, { 45, 8356 } },
	-- MetroPlan walk paths across the mouths at road level (gaps split the sidewalk walk line; walkers must cross)
	mouthWalkWorld = { { -54.5, -53.5, -36.5, -35.5 }, { 35.5, 36.5, 52.1, 53.1 } }, -- x of sidewalk/road/road/sidewalk nodes at z 8356
	islands = { { x1 = -18, x2 = -4, z1 = -20, z2 = -16.6 }, { x1 = 4, x2 = 18, z1 = -20, z2 = -16.6 } },
	columns = { Vector3.new(-16, 0, -18.3), Vector3.new(-8, 0, -18.3), Vector3.new(8, 0, -18.3), Vector3.new(16, 0, -18.3) },
	columnDiameter = 2,
	porch = { x1 = -30, x2 = 30, z1 = -6.6, z2 = 0, top = 0.5 },
	canopy = { x1 = -30, x2 = 30, z1 = -22, z2 = 0, under = 13, top = 15.6 },
	sideDoors = { { x1 = -15, x2 = -9 }, { x1 = 9, x2 = 15 } },
	revolving = { centre = Vector3.new(0, 0.5, 4.5), diameter = 9 },
}
Plan.POSTS = { -- porch markers built by A (DoormanPost, LimoDoorMark, BellStand)
	D1 = Vector3.new(6, 0.5, -2.5), D2 = Vector3.new(-6, 0.5, -2.5), DL = Vector3.new(15, 0.5, -5.6), BS = Vector3.new(18, 0.5, 3.2),
}
Plan.KEEP_FREE = { -- CityPlan points (unchanged) + the entrances.py lobby probe
	door = Vector3.new(0, 3.5, -5), lobby = Vector3.new(-35, 3.5, 20), reception = Vector3.new(0, 3.5, 45),
	lobbyProbe = Vector3.new(-20, 1.25, 12), lobbyRadius = 4,
}

-- roof
Plan.HELIPAD_EXIT = CFrame.lookAt(Vector3.new(52, 128.7, 62), Vector3.new(60, 128.7, 62))
Plan.HELIPAD_EXIT_WORLD = CFrame.lookAt(Vector3.new(52, 152.7, 8442), Vector3.new(60, 152.7, 8442))
Plan.PAD_WORLD = Vector3.new(0, 151.2, 8408)
Plan.ROTOR_CLEAR = 16.4
Plan.HELI_ROOF = true
Plan.TURRETS = { { x1 = -50, x2 = -38, z1 = 0, z2 = 12, y2 = 158, lantern = true }, { x1 = 38, x2 = 50, z1 = 0, z2 = 12, y2 = 158 } }

-- night look
Plan.GLOW = { window = Color3.fromRGB(146, 110, 70), trim = Color3.fromRGB(240, 190, 120), fin = Color3.fromRGB(200, 150, 80),
	cove = Color3.fromRGB(204, 152, 96) }
Plan.LIT_SHARE = { -- company hour windows (ClockTime) -> share of the 210 panes lit
	{ from = 18.2, to = 22, share = 0.6 }, { from = 22, to = 24, share = 0.4 }, { from = 0, to = 1, share = 0.4 },
	{ from = 1, to = 6, share = 0.15 }, { from = 6, to = 6.3, share = 0.3 },
}
Plan.WINDOW_COUNT = 210

-- far impostor (WORLD boxes; CityLifeController builds them as ONE impostor entry)
Plan.IMPOSTOR = {
	{ name = "Impostor", x1 = -70, x2 = 70, y1 = 24, y2 = 125, z1 = 8380, z2 = 8500, color = Color3.fromRGB(232, 224, 206), material = "Limestone", glow = true },
	{ name = "ImpostorSetback", x1 = -60, x2 = 60, y1 = 125, y2 = 137, z1 = 8380, z2 = 8500, color = Color3.fromRGB(196, 208, 214), material = "SmoothPlastic" },
	{ name = "ImpostorSetback", x1 = -50, x2 = 50, y1 = 137, y2 = 150.2, z1 = 8380, z2 = 8500, color = Color3.fromRGB(196, 208, 214), material = "SmoothPlastic" },
	{ name = "ImpostorCrown", x1 = -50, x2 = -38, y1 = 150.2, y2 = 182, z1 = 8380, z2 = 8392, color = Color3.fromRGB(212, 172, 86), material = "Metal" },
	{ name = "ImpostorCrown", x1 = 38, x2 = 50, y1 = 150.2, y2 = 182, z1 = 8380, z2 = 8392, color = Color3.fromRGB(212, 172, 86), material = "Metal" },
	{ name = "ImpostorFrieze", x1 = -29, x2 = 29, y1 = 115.5, y2 = 123.4, z1 = 8374, z2 = 8380, color = Color3.fromRGB(30, 44, 74), material = "Metal" },
}

-- real lights (exactly 3 in the hotel: these two + the existing helipad edge light)
Plan.LIGHTS = {
	chandelier = { pos = Vector3.new(0, 22.5, 48), range = 40, brightness = 1.2, owner = "B" },
	canopy = { pos = Vector3.new(0, 12.6, -11), range = 30, brightness = 1.0, owner = "A" },
}

-- budgets asserted by tests
Plan.CAPS = {
	Shell = 950, GrandLifts = 120, Forecourt = 110, RooftopHelipad = 40, Interior = 450, SkylineFloor = 560, SpaFloor = 440,
	SuiteFloor = 600, hotel = 3250, serverLights = 3, clientLights = 3, rigs = 8, figures = 12, activeEmitters = 2, activeFires = 1,
	neonFace = 24, neonArea = 400, translucentArea = 25000, glassWaterGap = 12, stepRadius = 200,
}
Plan.STEP_CENTRE_WORLD = Vector3.new(0, 24, 8440)

return Plan
```

## Appendix B. GrandRooms waypoint graphs, posts and routes (from `lead/plan.py`; local x, lz at the floor top of the level)

Edges are bidirectional. Portal nodes (staff appear / vanish): L1 `SW`, `SX`, `LC1`, `LC2`; F8 `LND`, `SVP`; F9 `LND`; F10 `LND`, `SVP`; roof `LND`.
Every edge was checked against every collidable footprint and wall of the plan with a 0.9-stud rig radius (`validation: OK`); `npc_paths.py` repeats the check against the built hotel. *(critic: `plan.py` now also fails when a route step is not an edge of its floor graph - three routes did that; fixed below, `validation: OK (0 problems)` again, plans re-rendered.)* Measured route lengths (`critic2/routes.py`): bellhop 141.4, duty-manager loop 411.3 (~103 s + 16 s stops), shift change 166.4, guest walk-in 98.2, night porter SW -> PO 144.3, F8 tour of all 8 doors 422, F10 tour of all 5 doors 268, farthest door from W8 122.5 / W10 108, from the F8 / F10 landing 134.5 / 115.

### B.1 F1 lobby + porch (floor ly 0.5; porch nodes at ly 0.5, street node SP at ly 0.475)

| Post | Meaning | (x, lz) | Faces |
|---|---|---|---|
| D1 | Doorman A | (6, -2.5) | N |
| D2 | Doorman B / night porter | (-6, -2.5) | N |
| DL | doorman at the limo door | (15, -5.6) | W |
| FD | founder drop-off (DrivePlan door) | (12, -4) | S |
| BS | Bellhop (bell stand) | (18, 3.2) | N |
| R1 | Receptionist A | (40, 36) | N |
| R2 | Receptionist B | (48, 36) | N |
| RP | ReceptionistPost marker / night receptionist | (44, 36) | N |
| CK | Check in prompt | (44, 29) | - |
| CO | Concierge | (-35, 30) | N |
| CQ | Ask concierge prompt | (-35, 24.5) | - |
| LP | CityPlan lobby point (heli arrival, keep 4 free) | (-35, 20) | - |
| RX | CityPlan reception point (keep free) | (0, 45) | - |
| DX | CityPlan door point (keep free) | (0, -5) | - |
| BT | Bartender | (-50, 110.5) | N |
| BQ | Order prompt (bar) | (-50, 103) | - |
| PI | Pianist (19-23) | (-35, 90.5) | N |
| CH | Cafe host | (47, 114) | N |
| BF | Breakfast host refill | (61, 95) | E |
| SE | Security (day) / night start | (59, 50) | W |
| LC | Call lift prompt | (64, 62) | - |
| MT | Maintenance ladder (10-12) | (6, 48) | W |
| SW | Staff door (shift change) | (0, 118) | N |
| SX | Kitchen door | (62, 118) | N |

Nodes: `SP` (0, -24), `CR` (0, -10), `PO` (0, -3), `PE` (12, -3), `PW` (-12, -3), `D1` (6, -2.5), `D2` (-6, -2.5), `DL` (15, -5.6), `VI` (0, 12), `VE` (12, 4), `VW` (-12, 4), `BS` (18, 3.2), `V2` (0, 21), `AE` (18, 21), `AW` (-18, 21), `AC` (0, 30), `ANE` (20, 28), `ANW` (-20, 28), `ASE` (20, 69), `ASW` (-20, 69), `AS` (0, 71), `W1` (-27, 32), `W2` (-27, 64), `LP` (-35, 20), `CO` (-35, 30), `CB` (-27, 30), `BO1` (-55, 75), `BO2` (-45, 75), `BM` (-44, 99), `BTE` (-31, 110.5), `BTW` (-60, 110.5), `BT` (-50, 110.5), `PI` (-35, 90.5), `PIA` (-29, 92), `S1` (0, 112), `S2` (-25, 112), `S3` (25, 112), `SW` (0, 118), `U1` (-9, 106), `U2` (-9, 74), `RF` (44, 26), `RG0` (55, 27), `RG` (54.5, 31.5), `RB` (54.5, 36), `R1` (40, 36), `R2` (48, 36), `RP` (44, 36), `RW` (31, 28), `E1` (30, 10), `E2` (31, 52), `E3` (52, 50), `LH` (60, 62), `LC1` (66, 58.25), `LC2` (66, 65.75), `SE` (59, 50), `CF` (36, 82), `CT` (47, 84), `CL` (30, 114), `CH` (47, 114), `CK1` (60, 114), `SX` (62, 118), `BF` (61, 95), `MT` (6, 48)

Edges: SP-CR, CR-PO, PO-VI, VI-V2, V2-AC, PO-PE, PE-VE, VE-AE, PO-PW, PW-VW, VW-AW, D1-PO, D2-PO, D1-DL, BS-VE, VI-AE, VI-AW, AE-ANE, AW-ANW, AC-ANE, AC-ANW, ANE-ASE, ANW-ASW, ASE-AS, ASW-AS, ANW-CB, CB-W1, W1-W2, W2-ASW, CB-CO, AW-LP, W2-BO2, BO2-BM, W2-BO1, BO1-BM, BM-PIA, PIA-PI, SW-S1, S1-U1, U1-U2, U2-ASW, U2-AS, S1-S2, S2-BTE, BTE-BT, BT-BTW, S1-S3, S3-CL, CL-CH, CH-CK1, CK1-SX, ANE-RF, AE-E1, E1-RF, RF-RG0, RG0-RG, RG-RB, RB-RP, RB-R2, RP-R1, RF-RW, RW-E2, E2-E3, E3-LH, LH-LC1, LH-LC2, E3-SE, SE-LH, ASE-E2, E2-CF, CF-CT, CF-CL, CK1-BF, AC-MT

Routes:

- **Doorman limo cue: D1 -> DL (start T-3.5 s)**: D1 > DL
- **Bellhop: luggage porch -> lift (car 1)**: BS > VE > AE > E1 > RF > RW > E2 > E3 > LH > LC1
- **Duty manager loop (~2 min)**: VI > AE > E1 > RF > RW > E2 > E3 > SE > LH > E3 > E2 > ASE > AS > U2 > ASW > W2 > BO2 > BM > BO1 > W2 > W1 > CB > ANW > AW > VI
- **Shift change 07:00 / 19:00 (staff door <-> posts)**: SW > S1 > U1 > U2 > AS > ASE > E2 > RW > RF > RG0 > RG > RB > RP
- **Bartender lane**: S1 > S2 > BTE > BT > BTW
- **Breakfast host 07:00-10:30**: SX > CK1 > BF
- **Guest walk-in: sidewalk -> check-in**: SP > CR > PO > VI > V2 > AC > ANE > RF

### B.2 F8 Skyline floor (ly 89)

| Post | Meaning | (x, lz) | Faces |
|---|---|---|---|
| H8 | Housekeeper A (F8, 09-16; turndown 17:00-19:30) | (0, 76) | N |
| W8 | service lift portal (waiter / housekeeping) | (0, 116) | N |
| L8 | Call lift prompt (landing) | (64, 62) | - |
| PW | Pool window | (0, 22.5) | - |

Nodes: `LND` (66, 62), `C1` (58.5, 62), `C2` (36.5, 62), `C3` (0, 62), `C4` (-36.5, 62), `C5` (-58.5, 62), `C6` (55.5, 62), `C7` (27.75, 62), `C8` (-27.75, 62), `C9` (-55.5, 62), `D801` (-58.5, 52), `D802` (-36.5, 52), `D803` (36.5, 52), `D804` (58.5, 52), `LG` (0, 40), `D805` (-55.5, 72), `D806` (-27.75, 72), `D807` (27.75, 72), `D808` (55.5, 72), `SV` (0, 76), `SVP` (0, 116), `SV2` (0, 104)

Edges: LND-C1, C1-C6, C6-C2, C2-C7, C7-C3, C3-C8, C8-C4, C4-C9, C9-C5, C5-D801, C4-D802, C2-D803, C1-D804, C9-D805, C8-D806, C7-D807, C6-D808, C3-LG, C3-SV, SV-SV2, SV2-SVP

Routes:

- **Housekeeping round 09-16 (door to door, ~60 s per room)**: SV > C3 > C7 > D807 > C7 > C2 > C6 > D808 > C6 > C2 > D803 > C2 > C6 > C1 > D804 *(critic: C7-C6 and C2-C1 were not edges)*
- **Room service: portal -> door (knock) -> back**: SVP > SV2 > SV > C3 > C8 > D806
- **Night security round 19:30 (F8 corridor)**: LND > C1 > C6 > C2 > C7 > C3 > C8 > C4 > C9 > C5
- **Bellhop with the suitcase (from the lift)**: LND > C1 > C6 > C2 > C7 > C3 > C8 > C4 > D802

### B.3 F9 Sky Spa (ly 101)

| Post | Meaning | (x, lz) | Faces |
|---|---|---|---|
| SR | Spa receptionist (07-22) | (49, 78) | N |
| PA | Pool attendant (07-21) | (0, 34) | N |
| TH | Spa therapist (09-21) | (39, 71) | W |
| SQ | Pour water prompt | (-50, 62) | - |
| JQ | Jets on prompt | (14, 47.4) | - |
| L9 | Call lift prompt | (65, 62) | - |

Nodes: `LND` (66, 62), `TD` (61, 62), `FO` (54, 62), `FS` (40, 52), `FW` (40, 66), `GD` (31, 52), `DK` (20, 52), `DK2` (2, 50), `DECK` (0, 40), `PA` (0, 34), `TW` (-18, 41), `ST1` (-31, 52), `RL` (-31, 44), `ST2` (-50, 52), `SAU` (-50, 60), `ST3` (-10, 52), `TC1` (-10, 71), `HAM` (-20, 67), `TC2` (-10, 101), `CZ` (-22, 101), `LK` (-2, 71), `LKI` (5, 71), `GY` (31, 44), `T1D` (38, 63), `T1I` (33, 63), `TH` (39, 71), `T2D` (38, 79), `QD` (45, 90), `Q1` (45, 104), `Q2` (-2, 104), `WT` (-63, 52), `WT2` (-65, 80), `ST4` (-57, 52), `SR` (49, 78.5), `SRA` (42, 80)

Edges: LND-TD, TD-FO, FO-FS, FS-GD, GD-DK, DK-ST3, ST3-ST1, ST1-ST4, ST4-ST2, ST2-SAU, ST1-RL, DK-DK2, DK2-DECK, DECK-PA, DECK-TW, GD-GY, ST3-TC1, TC1-TC2, TC2-CZ, TC1-HAM, TC1-LK, LK-LKI, TC2-Q2, Q2-Q1, Q1-QD, QD-FW, FO-FW, FW-T1D, T1D-T1I, FW-TH, TH-T2D, ST4-WT, WT-WT2, FW-SRA, SRA-SR

Routes:

- **Pool attendant: towels deck <-> station**: PA > DECK > TW
- **Spa routine (player): sauna -> cold plunge -> lounger**: SAU > ST2 > ST4 > ST1 > ST3 > TC1 > TC2 > CZ *(critic: ST2-ST1 was not an edge)*
- **Therapist: treatment doors <-> foyer**: TH > T2D > TH > FW > T1D > T1I
- **Arrival: lift -> terrace -> spa desk**: LND > TD > FO > FW > SRA > SR

### B.4 F10 Suites (ly 113)

| Post | Meaning | (x, lz) | Faces |
|---|---|---|---|
| H10 | Housekeeper B (F10, 09-16; turndown 17:00-19:30) | (6, 76) | N |
| W10 | service lift portal | (6, 116) | N |
| L10 | Call lift prompt (bridge end) | (66, 62) | - |
| BK | Secret door prompt (occupant) | (-17.5, 48) | - |

Nodes: `LND` (67, 62), `BR` (62, 62), `EL` (55, 62), `ED` (50, 62), `K1` (27, 62), `K2` (6, 62), `K3` (-14, 62), `K4` (-22, 62), `K5` (-38, 62), `K6` (32, 62), `PH` (-22, 52), `PHH` (-20.5, 40), `PHL` (-20.5, 22), `PAN` (27, 52), `P1004` (-38, 72), `P1005` (-14, 72), `P1003` (32, 72), `SV` (6, 76), `SVP` (6, 116)

Edges: LND-BR, BR-EL, EL-ED, ED-K6, K6-K1, K1-K2, K2-K3, K3-K4, K4-K5, K4-PH, PH-PHH, PHH-PHL, K1-PAN, K5-P1004, K3-P1005, K6-P1003, K2-SV, SV-SVP

Routes:

- **Room service waiter (portal -> suite door)**: SVP > SV > K2 > K3 > K4 > PH
- **Housekeeping 09-16 (~100 s per room) + turndown 17:00-19:30**: SV > K2 > K1 > K6 > P1003 > K6 > K1 > PAN *(critic: K2-K6 was not an edge)*
- **Arrival: lift -> skybridge -> corridor**: LND > BR > EL > ED > K6 > K1 > K2 > K3 > K4

### B.5 Roof (ly 126.2)

| Post | Meaning | (x, lz) | Faces |
|---|---|---|---|
| HA | Heli attendant (around heli events) | (26, 30) | W |
| HX | HelipadExit marker (moved) | (52, 62) | E |
| LR | Call lift prompt | (66, 62) | - |

Nodes: `PADE` (18, 30), `HA` (26, 30), `RB1` (34, 62), `HX` (52, 62), `LND` (66, 62), `PGN` (46, 70), `PGE` (46, 88), `PG` (37, 88)

Edges: PADE-HA, HA-RB1, RB1-HX, HX-LND, RB1-PGN, PGN-PGE, PGE-PG

Routes:

- **Heli arrival: pad -> roof bridge -> lift (when HELI_ROOF is on)**: PADE > HA > RB1 > HX > LND

## Appendix C. Roblox APIs used (all present in `tools/API-Dump.json`; checked with `lead/apicheck.py lead/apis.txt`)
- Instances: `Part`, `WedgePart`, `Model`, `Folder`, `Seat`, `ProximityPrompt`, `PointLight`, `SpotLight`, `SurfaceLight`,
  `ParticleEmitter`, `Fire`, `SurfaceGui`, `BillboardGui`, `ScreenGui`, `TextLabel`, `TextButton`, `Frame`, `UICorner`, `UIStroke`,
  `UIListLayout`, `UIGridLayout`, `UIPadding`, `PrismaticConstraint`, `Attachment`, `WeldConstraint`, `Weld`, `Motor6D`, `Humanoid`, `Camera`.
- Services: `Workspace` (`GetServerTimeNow`, `BulkMoveTo` + `Enum.BulkMoveMode.FireCFrameChanged`, `Terrain`, `CurrentCamera`),
  `Terrain` (`FillBlock`, `WaterColor`, `WaterTransparency`, `WaterReflectance`, `WaterWaveSize`, `WaterWaveSpeed`), `Lighting.ClockTime`,
  `Players` (`PlayerRemoving`, `LocalPlayer`), `Player` (`RequestStreamAroundAsync`, `DisplayName`, `UserId`), `CollectionService`
  (`AddTag`, `GetTagged`, `GetInstanceAddedSignal`), `PhysicsService` (`RegisterCollisionGroup`, `CollisionGroupSetCollidable`),
  `ProximityPromptService.PromptTriggered`, `GuiService.SelectedObject`, `UserInputService` (`PreferredInput`, `TouchEnabled`,
  `InputBegan`), `RunService` (`RenderStepped`, `Heartbeat`), `TweenService:Create`.
- Members: `BasePart` (`CastShadow`, `CanQuery`, `CanTouch`, `CanCollide`, `CollisionGroup`, `Transparency`, `Reflectance`,
  `Anchored`, `Material`, `Color`, `Massless`, `Size`, `CFrame`), `Part.Shape`, `Model` (`ModelStreamingMode`, `PivotTo`, `GetPivot`),
  `Instance` (`SetAttribute`, `GetAttribute`, `GetAttributeChangedSignal`, `FindFirstChild`), `Seat` (`Occupant`, `Disabled`),
  `Humanoid` (`GetState`, `SeatPart`, `Sit`, `StateChanged`), `ProximityPrompt` (`ActionText`, `ObjectText`, `HoldDuration`,
  `MaxActivationDistance`, `RequiresLineOfSight`, `Exclusivity`, `Enabled`, `Triggered`, `KeyboardKeyCode`, `GamepadKeyCode`),
  lights (`Range`, `Brightness`, `Color`, `Shadows`, `Enabled`, `SurfaceLight.Face/Angle`, `SpotLight.Angle`), `ParticleEmitter`
  (`Emit`, `Rate`, `Enabled`, `Acceleration`, `Drag`, `Size`, `Color`, `Texture`, `Lifetime`, `Speed`, `LightEmission`), `Fire`
  (`Enabled`, `Size`, `Heat`), `PrismaticConstraint` (`TargetPosition`, `ActuatorType`, `Speed`, `ServoMaxForce`,
  `LinearResponsiveness`, `CurrentPosition`), `Motor6D.Transform`, `SurfaceGui` (`LightInfluence`, `Face`, `MaxDistance`),
  `BillboardGui` (`MaxDistance`, `AlwaysOnTop`, `StudsOffset`), `ScreenGui` (`ScreenInsets`, `DisplayOrder`, `ResetOnSpawn`),
  `GuiObject` (`Selectable`, `NextSelectionUp/Down/Left/Right`, `BackgroundTransparency`), `GuiButton.Activated`, `Camera.FieldOfView`.
- Enums: `Material.{Water, Marble, Limestone, Granite, Cobblestone, Foil, Metal, Glass, Neon, Carpet, Fabric, Leather, WoodPlanks, Wood,
  CeramicTiles, Basalt, Slate, Snow, Ice, Glacier, Plaster, SmoothPlastic, Concrete, Pavement}`, `HumanoidStateType.Swimming`,
  `PartType.{Cylinder, Ball, Block}`, `ModelStreamingMode.{Atomic, Default, Persistent}`, `ActuatorType.Servo`,
  `ProximityPromptExclusivity.OnePerButton`, `KeyCode.{F, ButtonX, ButtonB}` (*critic:* `ButtonY` only as a negative test - it is the phone's key), `ScreenInsets.CoreUISafeInsets`,
  `PreferredInput.{Touch, Gamepad, KeyboardAndMouse}`, `NormalId.{Top, Front}`, `Font.Fondamento`.
- Luau globals: `debug.profilebegin` / `debug.profileend` (in `tools/globalTypes.d.luau`; the mock stubs them).
- **Not used on purpose**: `Model.LevelOfDetail` (PluginSecurity), `GuiService.PreferredInput` (missing in this dump),
  `Lighting.Technology` (RobloxScriptSecurity), any `Texture` / `Decal` image, sound or animation id.

## Appendix D. Requests / texts for other owners
### D.1 To the itinerary package (**filed 2026-10-12 by the critic** as section 1 of `design/requests/grandhotel.md` - request files are named after the requesting package; copy: `agents/grandhotel_design/lead/request_itinerary.md`)
Context: design/GRANDHOTEL_SPEC.md §18.6 (Meridian Grand rebuild). The rebuild ships AFTER round 2b; its HotelService then owns
13 real rooms. So that the itinerary's hotel step can hand over without a later edit in your files, please add:

- `ItineraryService.setHotelProvider(fn: (player: Player, trip: {[string]: any}) -> {[string]: any}?)` - stores fn (nil clears it).
- In the hotel step: if a provider is set, call it in a `pcall` with the trip (fields the hotel uses if present: `clientName`
  (string), `companions` ({{name, role?, seed?}}), `returnAt` (server time of the booked return)). If it returns a table with
  `ok == true`, show "Your room: <name> <room>" in the banner / calendar and point the GPS at the `door` CFrame it returns; if it
  returns nil / not ok / errors, keep your own "Your room" marker exactly as you built it.
- Put your own fallback "Your room" marker / prompt at `CityPlan.INTL_HOTEL.reception` (or on the hotel's `ReceptionistPost`),
  not on other parts of today's hotel interior (`LiftFront`, `FloorSign`, `ReceptionDesk`, ...): the rebuild replaces them, while
  the reception point stays free and the `ReceptionistPost` stays.
- Please do not register the TripAction action name `"hotel"` with `DriverService.onTripAction` (it silently replaces an earlier
  handler); the hotel's HotelService registers `"hotel"` after round 2b.
- No money, no saved field, no new remote. The hotel registers its provider in HotelService.init (pcall'd optional require of
  ItineraryService), so both shipping orders work.
Test idea: a fake provider returning {ok = true, room = "1001", name = "Royal Penthouse", door = CFrame.new(...)} -> the banner text
and the GPS target use it; a provider that errors -> the itinerary falls back to its own marker.

### D.2 Edits the hotel packages make themselves after round 2b (no request needed; listed here so the owners know)
- PhoneService (B): reception hook with nil fall-through (§18.4). ShuttleService (B): roof arrival / start behind `HELI_ROOF`
  (§18.3). EmployeeRigDesign (B): uniforms + `hotel:` mapping (§14.1). CampusAudioConfig (B): 3 silent keys.
- DrivePlan (A): `pm_hotel` (§6.3), after the drivers fix round. MetroPlan, MetroBuilder, CityBuilder, CityLifeController (A): §5, §11,
  §18.5. `tests/metro/test_build.luau` (A): budget scope split.

### D.3 Optional, for the lead to decide (§25)
- Drivers (later, drivers-wide, not filed by this build): a one-car queue at the `pm_hotel` kerb (a second limousine waits at bay B (-17, RT, 8368.5) until stop A is free), together with the shared airport kerbs.

---------------------------------------------------------------------------------------------------------------------
End of spec. Floor plans: `out/grandhotel_design/plan_lobby.png`, `plan_guest.png`, `plan_wellness.png`, `plan_suites.png`,
`plan_roof.png` (HTML sources in `out/grandhotel_design/html/`, generator `agents/grandhotel_design/lead/plan.py`, renderer
`agents/grandhotel_design/lead/shoot.js`).

---------------------------------------------------------------------------------------------------------------------

## Critic changes (independent feasibility critic, 2026-10-12)

Scope of the check: every Roblox class / member / enum against `tools/API-Dump.json`; every referenced file, function, remote,
tag and line number against the current `work/src`, `tests`, `harness` and `agents/`; coordinates against the world dump, the
drivers' leg probe and clearance sweep, the flight sweep log and the metro walk-graph code; budgets re-measured or recounted;
round-2b ownership (`agents/stable/round2b.js`, `agents/drivers/API.md`, `agents/guests_jet/API.md`); economy, saves, ids,
company clock, user wishes, tests and shots. Nothing under `work/src` or `tests` was edited. Evidence (scripts, sandboxes,
probe output, backups of every file before the edit): `agents/grandhotel_design/critic2/` (backups in `critic2/backup/`).

**Verified and left as it was** (no change needed): all 201 + 78 API names present (only the deliberately unused
`Model.LevelOfDetail` / `GuiService.PreferredInput` / `Lighting.Technology` flagged); `LiftLogic`, `DriverService`
(`onTripAction`, `phoneHook(s, payload)`, `ALIGHT`, ride-folder attributes), `Drive.decode/segEnd`, `PhoneService.onAction` /
`runHook`, `ShuttleService.heliArrival` / `HELI_RADIUS` / heli fee, `AirTrafficController`'s generic `CityAction == "heli"`
dispatcher, `EmployeeRigDesign` (`UNIFORMS` keys, `Rig.build` signature, role line 82, `MAX_PARTS` 22), `EmployeeController.pose`,
`GuestPlan` exports and types, `CityLifeController` (`WINDOW_PARTS`, `registerGlow`, `nightLook`, `applyLook`, impostor + 5
counting), `ArchKit` helpers (`steamEmitter` uses the built-in `rbxasset://textures/particles/smoke_main.dds`, `flame`,
`artwork`, `loungeChair`, `tvScreen`, `lockers`, `aquarium`, `hash`), `CityBuilder` locals `light` / `sign` / `prompt`
(budget 40 per zone, hotel lights allocated inside MetroBuilder `towers()` before the helipad light, so keeping 3 lights keeps
the 40/40 distribution), Terrain unused elsewhere + recorded by the mock (`meta.terrainOps`), the referenced tests and tools
exist; company clock = `Ops.hour(GetServerTimeNow)` = `Lighting.ClockTime`; economy: no money path, no saved field, no new
remote, hotel stays free (the founder's Meridian Grand night is not charged anywhere; crew nights stay in
`Ops.TRIPS.abroad.hotel` 220), no asset / animation / sound ids, admin untouched; flight: heli transit at x = 0, turrets >= 38
studs to the side, no airliner pose within 200 studs of the hotel.

| # | Where | Change | Why (evidence) |
|---|---|---|---|
| CC-1 | §2.3 F1, §6.1, §6.2, §6.3 code, test_plan / test_drive, App. A `DRIVE.stop`, plan_lobby | Limo stop A pivot **x 16 -> 19**; rear doors part 14.6 / mesh 10.2, both in the east side door span | The ExecutiveLimo hook is live in DriveController: 25.76 long, rear end 13.32 behind the pivot -> at x 16 it covered x 2.7..4 of the walk gap (the spec's own MUST). Sandbox probe at x 19: 14 / 14 legs route, `pm_limo -> pm_hotel` 40.5 s |
| CC-2 | §6.1 porch row, App. A `urns` / `porchLanterns` / `porchKeepOutZ`, plan_lobby | Urns lz -3 -> **-1.5**, lanterns at **lz -0.8**; MUST: nothing collidable / > 0.6 high at lz < -2.6 | `tests/drivers/clearance.py` with the spec forecourt: **14 / 28 legs failed** (all `#mesh`: urn x 28, lanterns x +-20; the turns sweep the porch to lz -3.8); with the fix **28 / 28 pass** (`critic2/world_spec.json` vs `world_fix.json`, `sweep2.py`) |
| CC-3 | §6.1 mouths row, §21.2 MetroPlan, App. A `mouthWalkWorld`, test_shell | Road-level walk path across each drive mouth in `MetroPlan.pmPaths` + a connectivity test | MetroPlan `gaps` are lay-bys: `sidewalk()` cuts the walk line (`MetroPlan.module.luau:553-575`); without the paths CityLife walkers could no longer pass the hotel frontage |
| CC-4 | §6.3, §25 Q2, App. D.3 | Second-limo overlap **accepted as cosmetic** (decision), window corrected to "up to 90 s for a pick-up"; later bay B moved to x -17 | `DROP_PAUSE` 4 s, pick-up wait 90 s (API.md); same behaviour at every shared kerb place; bay B at -16 would let the mesh nose touch the walk gap |
| CC-5 | §6.3 | Drive times / clearance stated as measured (40.5 s, 59.8 s, 58.4 s, 33.3 s; 28/28 clear) | replaces the estimate "~30-40 s" |
| CC-6 | §5.1 lift row, §13.2, App. A `LIFT.tower.y2` | Lift tower ly 0..135 -> **0..139** | a car at stop R has its roof at ly 136.6 - it stuck out of the cap |
| CC-7 | §3, §5.1 slabs row, §7.1 stair row, App. A `STAIR_VOID`, plan_lobby | The stair hall x -30..30, lz 72..106 is open to ly 28 | the F1 ceiling (ly 16..17) and the F2 mezzanine solid (ly 17..28 outside lz 18..78) filled the space the side flights climb through (lz 78..92, ly 9 -> 17, head room to ly 22) |
| CC-8 | §5.4, §19.3 | `TransomGlow` on all **34** arches (was "20"); tagged parts ~295 / Port Meridian ~493 | §5.1 has 34 arched windows |
| CC-9 | §5.1 F8 attic row | North F8 French windows **8 wide** at 801 -64/-54, 802 -43.5/-33.5, 803 33.5/43.5, 804 54/64; no pane at x -29.5..29.5 | 10-wide windows 9 apart overlapped by 1 stud; 802 / 803 ran 2 studs behind the entablature end (x +-29) |
| CC-10 | §5.1 arched row, §2.3 F12, §19.3, §19.4 | F2 panes opaque (solid mezzanine behind them); translucent estimate 17,000 -> **~23,200** (cap 25,000 kept) + cut-list reserve (opaque N/S tower panes, -3,000) | recount from the spec geometry gave ~24,500 (`critic/translucent_est.py`; lift tower panes 5,300 alone) |
| CC-11 | §2.3 F9, §19.1 | Metro budget test counts Port Meridian with the hotel **frozen at 78** -> 24 parts left (not 102) | BASE 781 includes the old hotel; removing the hotel but keeping 781 would have handed the metro 78 hidden parts |
| CC-12 | §1, §5.1 total, §19.1, App. A `CAPS` | Hotel cap **3,000 -> 3,250**, model caps Interior 450, Skyline 560, Spa 440, Suite 600, new GrandLifts 120; estimates ~2,960; PM <= 8,429, world <= 17,980 | the lead's per-floor estimates had no partition walls / room shells; the Shell table summed to 896 with under-counted arches and no pool. Still far inside the zone (20,000) and world (30,000) caps; floors stay Atomic |
| CC-13 | §3, §5.1, §13.2, §20, §21.2, §21.4, test_shell, App. A `LIFT.model` | Lift tower, cars, landings in a new model **`GrandLifts`** (Default), each car an Atomic `GrandLiftCar`; nothing unanchored in `Shell` | moving physics assemblies inside the Atomic Shell are an untested streaming case; the lift parts pushed Shell to its cap |
| CC-14 | §7.2 CQ, §16.2, §17, App. C, tests | Concierge prompt: keyboard F, gamepad default ButtonX; **no hotel prompt uses ButtonY** | `PhoneController` toggles the phone on ButtonY / P (`PhoneController.module.luau:793-801`) |
| CC-15 | §14.2, §14.3, §14.5, §14.6, App. B, plan labels | Housekeeping 60 s (F8) / 100 s (F10) per room; turndown 17:00-19:30 sequential (overflow silent); night security 2 rounds (19:30 F8, 01:00 F10); handover = last 3 real s; room service waiter at O+12; bellhop corridor <= 34 s; arrivals start back-computed | measured graph lengths (`critic2/routes.py`): F8 tour 422 studs -> 8 x 78 s + 106 s = 730 > 630 s; F10 697 > 630; turndown 19-21 = 42.9 real s for 13 doors (3.3 s apart, 42-stud walks) broke the 5 studs/s continuity test; a 148 s round every 64 s overlapped; 18:55-19:00 is 1.8 real s; farthest door 122.5 studs made O+20 miss the O+45 knock |
| CC-16 | §17 lift panel | Two-line button labels (stop 22 pt + name 11 pt), caption "Key card needed" | "10 Suites" in one line does not fit 64 pt readably; the long caption did not fit 208 pt |
| CC-17 | §17, test_client | Hotel panels registered in `PhoneController.PANELS` at runtime (no file edit) | otherwise the phone stays open over the lift panel / sheets |
| CC-18 | §18.5, test_client | HotelController re-applies the lit pattern when panes stream back in | CityLife drops streamed-out glow parts and re-registers them with the 45 % hash |
| CC-19 | §16.1, test_service, request | TripAction action `"hotel"` reserved and asserted after every init | `onTripAction` silently overwrites an action key |
| CC-20 | App. B, `lead/plan.py`, plan PNGs | 3 routes fixed to graph edges (F8 housekeeping, F9 spa routine, F10 housekeeping); `plan.py` now fails on a non-edge route step; re-validated (0 problems) and re-rendered (LOOKED at) | C7-C6, C2-C1, ST2-ST1, K2-K6 were not edges - the spec's own test "every actor path uses only Appendix B edges" would have failed |
| CC-21 | §9.2 | PropFx contract spelled out (tag `PropFx` + attribute `Fx` = kind, `FxHinge`, `FxTravel` ...) | PropFx reads the kinds from the `Fx` attribute (`PropFxController.module.luau:190-200`) |
| CC-22 | §7.1 bar | Juice / syrup carafes + `MOCKTAILS · JUICES · COFFEE` plate; no alcohol shapes or labels | keeps the experience free of alcohol references for the content-maturity questionnaire (teen player) |
| CC-23 | §18.6, §25 Q1, App. D.1, `lead/request_itinerary.md`, **`design/requests/grandhotel.md` (new)** | Itinerary request **filed** (decision), with two additions: fallback marker at `CityPlan.INTL_HOTEL.reception` / `ReceptionistPost`, TripAction `"hotel"` reserved; filed under the requester's name (convention of `design/requests/`) | the itinerary package has not started, so the hook can land in round 2b; its own marker must not hang on parts the rebuild removes |
| CC-24 | test_shell | Helicopter corridor / hover column kept empty (measured poses) | `tests/flight/clearance.py` only sweeps poses below 150 studs above the ground; the hotel transit is at 158-190 |
| CC-25 | §0.3, §14.1, §19.1 | 9 re-verified facts added; `DriverService.template` lines 201-222 -> 247-266; parts within 512 studs 2,514 (measured), `life/measure.py` path made explicit | line drift after the drivers fix round; the dump measures 2,514 flat |
| CC-26 | §21.1 | After round 2b the hotel edits the post-2b versions of DrivePlan / MetroPlan / EmployeeRigDesign / CityLifeController / ShuttleService / ItineraryService and re-runs those owners' suites as a gate | these files are touched by drivers / guests_jet / itinerary in round 2b |
| CC-27 | §22 | New asserts (both looks at the stop and along the legs, GrandLifts, STAIR_VOID, window overlap, walk-line connectivity, heli corridor, route edges, staff timing, PANELS, stream-in, TripAction key) and 16 new negative mutations (8 A, 8 B) | every critic fix has a test that fails without it |
| CC-28 | §23 | Shots `gh_limo_mesh_stop`, `gh_spa_cutaway` (whole wellness floor), `gh_suites_cutaway` (all suites), `gh_staff_lineup` (all 22 staff); GUI previews for the two-line lift panel and the phone closing | the user's three wishes each get one picture that proves them at a glance |
| CC-29 | §25 | The lead's three questions answered (filed / accepted / closed); **no question needs the user** | all three are design or process decisions |
| CC-30 | §5.1 flags, §6.4 DL, §24, §0.3 | Tie rods at x +-4 / +-26 (never at a flag pole); DL valid for both limo looks; Studio items 14-16 (moving Atomic cars, prompt key vs phone, porch overhang / walkers); a literal `|` inside a §0.3 table cell replaced; footprint test allows the facade projections (x -76..83, lz -28..122) | small consistency fixes |

Files touched by the critic: `design/GRANDHOTEL_SPEC.md`, `design/requests/grandhotel.md` (new),
`agents/grandhotel_design/lead/plan.py`, `lead/tables.txt`, `lead/GrandPlan_v1.module.luau` (luau-compile OK, lsp 0),
`lead/request_itinerary.md`, `out/grandhotel_design/plan_*.png` + `html/` (re-rendered, all five looked at).
