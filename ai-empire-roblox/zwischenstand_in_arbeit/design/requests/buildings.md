# Requests from package "buildings" (garage stage = plan tier 0, guest house = hotel annex)

Context: `Office:GetAttribute("OfficeTier")` is the PLAN tier (0 = garage stage, 1..4 = the HQ buildings).
`BuildingPlan.tierForOffice(officeIndex)` / `officeForTier(planTier)` map save office indices to plan tiers
through `Plan.OFFICE_TIER_OFFSET` (0 today = identity; the save migration sets it to 1). `HeadquartersDesign.tierFor(session)`
= `session.planTier` (session-only admin/harness override, never saved) or `Plan.tierForOffice(session.data.empire.office)`.

## 1. PlotService.refresh — compare plan tiers (REQUIRED; blocks the admin "tier0" command and the migration)
File `ServerScriptService/Server/Services/PlotService.module.luau`, function `Plot.refresh`:
```
local tier=session.data.empire.office
if office:GetAttribute("OfficeTier")~=tier then
```
→
```
local tier=session.data.empire.office                -- office index: keep for EmpireConfig.OFFICES[tier].name below
local planTier=Design.tierFor(session)               -- HeadquartersDesign.tierFor (Design is already required there)
if office:GetAttribute("OfficeTier")~=planTier then
```
Why: OfficeTier holds the plan tier. (a) Today the admin command "tier0" sets `session.planTier = 0`, but refresh
compares OfficeTier (1) with the office index (1) and never rebuilds, so AdminService answers `TIER_NOT_BUILT`
and undoes itself (tested: tests/buildings/test_admin.luau case (a)). (b) After the save migration (office 1 =
plan tier 0, OFFICE_TIER_OFFSET = 1) the old comparison would differ on EVERY refresh and rebuild the office
on each training start, GPU purchase, hire... With the change, test_admin.luau case (b) (a PlotService double
with exactly this comparison) passes: tier0 builds the garage, refreshes keep it, tier1/tier2 go back.
Nothing else in refresh needs to change (occupants(p, oldTier) already uses the plan tier attribute).
STATUS: done by econ (PlotService.refresh compares Design.tierFor(session); tests/econ + buildings_admin pass)

## 1b. StaffService — car commuters and the plan tier (REQUIRED for the garage stage and the migration)
File `ServerScriptService/Server/Services/StaffService.module.luau`:
- `commute(e)`: `local base=if e.garage then Plan.GARAGE_ARRIVAL else Plan.ARRIVAL` →
  `local base=Plan.staffArrival(e.tier,e.garage)` (BuildingPlan; identical for plan tiers 1..4: B1 garage /
  plaza; plan tier 0: the visitor bays in front of the garage (81, 3, -152) / the plaza).
- `sync(p,s)`: `tier=s.data.empire.office,` → the built plan tier:
  `tier=(function(): number local t=office:GetAttribute("OfficeTier");return if typeof(t)=="number" then t else Plan.tierForOffice(s.data.empire.office) end)(),`
Why: in the garage stage a third of the staff (car commuters, `e.garage`) are parked off duty / start their
walk at `Plan.GARAGE_ARRIVAL` = B1 (y -13), which at plan tier 0 is inside the solid ground (measured in
tests/buildings/test_tier0.luau: lowest employee root y -13.0, Employee_2 OFF_DUTY). And after the migration the
office index is plan tier + 1, so every Plan.* call of StaffService/EmployeeNavigation (e.tier) would use the
wrong building. Both edits are applied verbatim to a private test tree (tests/buildings/mkharness.py REQUESTS,
tree gen_req): `tools/luau tests/buildings/test_tier0.luau -a req` → 35 passed, 0 failed (incl. "no employee
below the ground floor"). Same pattern elsewhere for the migration: BuildingStateService line ~603
(`math.clamp(math.floor(d.empire.office or 1),...)` fallback) should use the office's OfficeTier.
STATUS: done by econ (commute uses Plan.staffArrival(e.tier, e.garage); sync uses the built OfficeTier; BuildingStateService fallback uses Plan.tierForOffice)

## 2. Save migration (lead, as planned) — what the buildings package already supports
- `BuildingPlan.OFFICE_TIER_OFFSET = 1` (one line in BuildingPlan, may be flipped by the lead) → office 1 builds
  plan tier 0 (garage), office 5 builds plan tier 4. Admin "tier0".."tier4" then map through `Plan.officeForTier`
  automatically (no session override needed).
- EmpireConfig.OFFICES gets the new entry 1 "Garage" (staff cap = `Plan.GARAGE_STAGE.staff` = 5 placeholder,
  desks 6 incl. founder, GPU blade slots `Plan.GARAGE_STAGE.blades` = 6 placeholder; all "-- tuned by CORE_SPEC").
- The guest house appears from `Plan.HOTEL_MIN_TIER` = 2 (plan tier 2 = "Startup Campus" = office index 2 today,
  3 after the migration). If CORE_SPEC wants it earlier (e.g. plan tier 1 "Founder Headquarters"), change that
  one number (checked headlessly with HOTEL_MIN_TIER = 1: tier 1 builds, 0 holes, all guest-house targets reachable).
- harness/build_dump.luau builds tier 0 through `session.planTier = 0`; after the migration it can use office 1.
- EmpireConfig.QUESTS "Out of the garage" (target = office 2, desc "Upgrade to Startup Studio") then still means
  "leave the garage" (office 2 = plan tier 1 = "Founder Headquarters"); only its desc needs the new office name.
STATUS: done by econ (DATA_VERSION 6, MIGRATIONS[5], OFFICE_TIER_OFFSET = 1, 5 stages, GARAGE_STAGE staff 5 / blades 3, quest text)

## 3. VehicleService — car pick-up notice (small)
File `ServerScriptService/Server/Services/VehicleService.module.luau`, `Vehicles.init`, PromptTriggered handler,
`spawnCar` branch: the notice is hard-coded "Your car is waiting in the B1 pick-up bay." The garage stage has no
B1; its `GarageSpawn` marker carries the attribute `PickupText` = "Your car is parked in front of the garage.".
Change: `local marker=plot and plot.office and plot.office:FindFirstChild("GarageSpawn",true); local pick=marker and marker:GetAttribute("PickupText")`
and use `if typeof(pick)=="string" then pick else "Your car is waiting in the B1 pick-up bay."` as the ok text.
The tier-0 spawn spot is in front of the garage door (`Plan.GARAGE_STAGE_SPAWN`, building-local (107, 4, -136));
a static company van (scenery, `Office.Site.GarageForecourt.CompanyVan`) stands in the bay beside it (tested: no
van part inside a 7.4 x 15 car footprint around the spawn).
STATUS: done by econ (PickupText of the GarageSpawn marker)

## 4. BuildingStateService.scan — screens in the garage stage (small)
`local tier=math.clamp(math.floor(tonumber(office:GetAttribute("OfficeTier")) or 1),1,#Plan.TIER_FLOORS)` →
`local tier=Plan.clampTier(tonumber(office:GetAttribute("OfficeTier")) or 1)` (BuildingPlan.clampTier: 0..4).
Why: at plan tier 0 the clamp to 1 makes `roomOf` look up tier-1 rooms, so garage screens get no/wrong room names.
STATUS: done by econ (Plan.clampTier)

## 5. FacilityService (package "life") — guest refusal text: already present
`DENY.guest` exists. Guest-class rooms (guest rooms, corridors, breakfast, workshop) refuse card holders through
`Plan.playerAllows`; the founder may enter; the guest house lobby is public. No request.
STATUS: already done (integrate: FacilityService DENY.guest + Plan.playerAllows; no request)

## 6. Talk package — room purposes / hotel attributes
New room kinds for Dialogue room purposes: garage_lab, garage_founder, garage_assist, garage_wc, garage_porch
(plan tier 0) and hotel_lobby, hotel_breakfast, hotel_pantry, hotel_service, hotel_office, hotel_corridor,
hotel_workshop, hotel_stair, guestroom (guest house). Office attributes set at build: `GarageStage = true`
(tier 0), `HotelRooms = 12` (tiers with the guest house). `HotelGuests` is left to the hotel-guest package.
STATUS: done by integrate (GarageStage / HotelRooms are set at build, HotelGuests by EmpireService; Dialogue ROOM_TEXT now has purposes for garage_lab/founder/assist/wc/porch, hotel_lobby/breakfast/pantry/service/office/workshop and guestroom - corridors and stairs stay without a purpose by the talk rule)

## 7. For the later hotel-guest NPC package (no change needed now; what exists)
- Role `guest` = {public, guest} (BuildingPlan ROLE_CLEARANCE); support staff have guest clearance.
- Per guest room one activity `WorkstationType = "GuestBed"` (`<room>_Guest`, attributes `GuestRoom`,
  `RoomNumber` (101..104, 201..208), `Suite` on 208; RoomAccess guest), lobby `Waiting` seats `H0_LOBBY_Wait1..4`,
  breakfast `Dining` seats `H0_BREAKFAST_Dining1..20` (Department kitchen, RoomAccess guest, `TablePoint`),
  breakfast `Coffee` x2 at the buffet machine (`PantryCoffee` PropFx), workshop `Meeting` seats
  `MeetingRoom = "HotelWorkshop"` (10). All reachable (check_geometry, tests/buildings/test_geometry.py).
- Operations posts 13 "Hotel Reception" (H0_LOBBY, seated; job points greet, printer + PropId HotelKeyPrinter)
  and 14 "Housekeeping" (H0_LINEN; job points cart, room1..room4 in the ground-floor guest rooms). The in-room
  hops of both are verified walkable for a body of radius 1.0.
- Navigation: `Plan.annexAt(tier, p)` = "hotel" inside the guest house; EmployeeNavigation never uses the HQ lift
  for routes that start or end there (stairs = one walked path, fallback via `Plan.stairEntryFor(annex, level)`).
- Entrance: automatic door H0_LOBBY_D1 on the east facade (x -98, z 90) facing the WestPath; apron + canopy;
  wayfinding post where the colonnade ends (x -93, z 70); terrace exit H0_CORRIDOR_D1 to the garden.
STATUS: deferred to guests_jet (info for the hotel-guest NPCs: GuestBed activities, lobby / breakfast seats, posts 13 / 14, annex navigation)
