# Requests from package "world" (Business City, airport, Port Meridian, travel, limo)

## 1. tests/lead/run_all.sh — add the world suites (lead)
Append:
```
python3 harness/make_manifest.py --src work/src --gen harness/.gen_world >/dev/null
for t in cityplan build travel vehicle client; do run "world_$t" $L tests/world/test_$t.luau -a .gen_world; done
```
Why: route graph / drivable bounds, the built world (budgets, streaming modes, prompts, free roads),
the flight state machine with the real PlotService, VehicleService bounds + limo gate, and the client
(cutscene, GPS). Runtime < 2 s together. Expected today: 172/0, 24/0, 51/0, 27/0, 22/0.
The geometry checks (holes, entrance reachability with check_geometry) run with `tests/world/run.sh`
(~15 s); `tests/world/negative.sh` proves the tests fail on the pre-change files and on mutations.
STATUS: already done (integrate: run_all runs world_{cityplan,build,travel,vehicle,client}; the dump checks run as world_check / world_entrances)

## 2. ActionController.module.luau — message for the new BuyCar error (owner of ActionController)
Add to `MESSAGES`: `NEEDS_PASS = "This car comes with the Executive Limousine game pass.",`
Why: `BuyCar {carId="limo"}` returns `NEEDS_PASS` without the pass; CampusApp calls it non-silently, so
today the player sees "Something went wrong." (TravelController shows its own texts for TravelAction.)
STATUS: done by econ

## 3. CampusApp.module.luau `fleet()` (~:93-104) — pass cars (owner of CampusApp)
`CampusConfig.CARS` now has `{id="limo", pass="limo", price=0, ...}`. The fleet card currently shows
"Included with your company" for price 0 and a "Buy · $0" button. Suggested change inside the loop:
- `if def.pass then` subtitle "Game pass car · top speed ..." instead of the price text;
- owned = `s.data.empire.campus.cars[def.id] == true or (s.live.shop and s.live.shop.passes and s.live.shop.passes[def.pass] == true)`
  (`live.shop.passes` is published by ShopService.publish);
- not owned: button text "Get the pass" -> open the Shop app (Computer app id "shop") instead of calling
  BuyCar; owned: first press `BuyCar {carId="limo"}` (adds it to the fleet), then "Collect in B1" ->
  `SpawnCar {carId=def.id}`.
Server side is already safe: BuyCar/SpawnCar check `ShopService.owns(player,"limo")` every time
(stored `cars.limo=true` alone never spawns it).
STATUS: done by econ (pass cars: "Get the pass" opens the shop, "Add to fleet", "Collect")

## 4. AdminService `fleet` (~:49) — FYI only
It sets `cars[id]=true` for every car incl. the limo; spawning the limo still needs the pass
(`ShopService.debugGrantPass(session,"limo")` for testing). No change required.
STATUS: already done (integrate: FYI only)

## 5. pack.py — Workspace streaming (lead) — nothing new required
Workspace streaming properties are NotScriptable. pack.py already sets what the world needs:
StreamingEnabled=true, StreamingMinRadius=128, StreamingTargetRadius=512, ModelStreamingBehavior=Improved,
StreamOutBehavior=Opportunistic, StreamingIntegrityMode=MinimumRadiusPause. Keep them. Notes:
- Port Meridian is ~4,400 studs from the airport; flights use `Player:RequestStreamAroundAsync` before the
  server PivotTo, and MinimumRadiusPause additionally pauses the client until the arrival area is loaded.
- Building interiors are Atomic models; 7 skyline shells (towers >= 6 floors, City Hotel, control tower,
  ~300 parts) are Persistent so the city skyline shows from the campus beyond the 512-stud radius.
- Do NOT raise StreamingTargetRadius for the city: the whole new world is only ~3,000 parts.
STATUS: already done (integrate: pack.py / agents/stable/pack_stable.py set the streaming properties)

## 6. Customers / trips packages — API to use (no file change needed)
- `CityPlan.clientOffice(idOrName, "contract"|"business")` -> destination with `door`, `lobby`,
  `reception`, `meeting` CFrames, 4 `parking` bay CFrames (downtown), `drive` point, `zone`
  ("downtown" or "abroad"). 14 downtown offices + 4 Port Meridian towers cover every name in
  EmpireConfig.CONTRACTS and MarketService.businesses (tests/world/test_cityplan checks it; if a client is
  renamed or added, add it to CityPlan's CLIENTS table).
- `CityPlan.route(fromPos, toPos)` / `routeTo(fromPos, destId)` -> road polyline for client-drawn NPC cars;
  `nil, "FLIGHT_REQUIRED"` between home and abroad.
- `CityService.setMeetingHandler(function(player, clientId, prompt) ... end)` replaces the placeholder
  notice of the "Start meeting" prompts (attribute `ClientId` on prompt and table).
- `CityService.guide(player, destinationId)` draws the GPS route on that player's client (appointments).
- `CityService.state(player)` / `isAway(player)` -> "home" | "flying" | "abroad"; Player attribute
  `TravelState` (nil = home) for UI (HUD "Abroad · Port Meridian").
- `CityPlan.CITY_HOTEL`, `CityPlan.INTL_HOTEL`, `CityPlan.AIRPORT` (carPark, carParkBays, checkin, gates,
  arrival), `CityPlan.ABROAD` (arrival, checkin) for hotel nights / trips.
- Receptionist placeholder posts: parts named `ReceptionistPost` (attributes `CityPost` = "reception" |
  "hotel_reception", `BuildingId`, `ClientId`) in every office/tower and both hotels — the staff/talk
  packages can place an NPC there.
STATUS: deferred to itinerary (customers / trips API: clientOffice, route, meeting handler, guide, state; drivers use CityPlan.route as well)
STATUS: done by itinerary (uses CityPlan.clientOffice / CITY_HOTEL / INTL_HOTEL / AIRPORT / ABROAD, CityService.guide + state + trips, the existing "Start meeting" prompts via EmpireService's meeting handler; CityService gained the additive City.onMeeting(fn) listener so the itinerary follows the prompt at once)

## 7. EconomyService — FYI
A cancelled flight (player respawned/left while the arrival area streamed) refunds the ticket with
`Economy.grant` and subtracts it from `stats.totalCost` again (CityService.flight). If the economy package
adds a dedicated refund/categorised flow, swap it in there.
STATUS: econ: EconomyService.grant/spend/applyFlow take an optional ledger category now; the CityService call is re-filed in design/requests/econ.md #4 (not an econ file)
