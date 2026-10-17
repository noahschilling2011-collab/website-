# Requests / interfaces from package "guests_jet" (company jet, hotel guests, terminal passengers)

## 1. Lead — run_all: add the guests_jet suites
Append to tests/lead/run_all.sh:
```
# guests_jet (round 2b + fix round 1): company jet (JetService + JetController + the separation sweep), hotel guests +
# terminal passengers (GuestPlan + GuestController), airliners unchanged + bizjet budgets, hotel walks vs tiers 2-4,
# jet hull + walks vs the world (~4 min)
python3 harness/make_manifest.py --src work/src --gen harness/.gen_gj >/dev/null
run guests_jet_jet      bash -c "cd tests/guests_jet && ../../tools/luau test_jet.luau -a .gen_gj"
run guests_jet_guests   bash -c "cd tests/guests_jet && ../../tools/luau test_guests.luau -a .gen_gj"
run guests_jet_aircraft bash tests/guests_jet/aircraft.sh
run guests_jet_geometry bash tests/guests_jet/run.sh --geometry-only
```
Expected today (fix round 1): guests_jet_jet 210/0, guests_jet_guests 205/0, guests_jet_aircraft 27/0,
guests_jet_geometry = hotel_paths 4/0 + clearance 18/0 (the last summary line is the clearance one).
The aircraft suite no longer reads agents/stable/src_r2b_base: it compares against the committed fingerprints
tests/guests_jet/aircraft_base.json (count + sha256 per airliner kind / LOD, made from src_r2b_base with
`tests/guests_jet/aircraft.sh --write-base agents/stable/src_r2b_base`), so it runs inside a RUNALL_TAG sandbox
(verified: agents/guests_jet/sandbox, see the final report). tests/guests_jet/negative.sh: every mutation detected
(`--no-world` skips the slow clearance one).
New files (no owner yet besides this package): `ReplicatedStorage/Shared/JetPlan.module.luau`,
`ReplicatedStorage/Shared/GuestPlan.module.luau` (pure maths, required by JetService / JetController / GuestController).
STATUS: done by verify2b (2026-10-17): the four lines are in tests/lead/run_all.sh; negative.sh mutation
staff_leave_before_car re-anchored to JetService.pending as patched by itinerary.md #2 (agents/verify2b/FIXES.md).

## 2. itinerary — the company jet API (no change needed)
See agents/guests_jet/API.md: `JetService.available(player) -> (ok, reason, info)`, `JetService.fly(player, {to,
companions, onArrive}) -> {ok, flightId, departAt, arriveAt, doneAt, delay, slot, to, destination, err}`,
`JetService.onArrive(fn) -> disconnect`, `JetService.status(player)`. The founder is placed at `JetPlan.ARRIVAL.abroad`
(next to the VIP limousine stand, MetroPlan.VIP_LIMO.stand) / `JetPlan.ARRIVAL.home` (City Airport arrivals, the shuttle's
arrival point), so the limo / driver pick-up can start right there. Jet trips' money stays in CompanyOps (Ops.JET).
STATUS: open (info)
STATUS: done by itinerary (used: available, fly without pay + onArrive, staffOf; the jet is planned when available() is ok, JET_BUSY with purpose "staff" -> shuttle + "already flying to Port Meridian" in the call)

## 3. cabin (later package) — the bizjet's cabin
AircraftModel kind "bizjet" (JetPlan.SCALE 1.6 = 46 x 41.6 x 15.5 studs) has a glazed cockpit with two seats (pilot rig
roots `points.captain` / `points.firstOfficer` at x -+1.05, y 5.75, z -16.1: the cockpit is narrower than two seated rigs,
so JetController hides each seated pilot's / companion's window-side arm - `JetController.windowArm(seat)`; the seat
test in tests/guests_jet/test_jet.luau checks 80 pilot and 40 companion builds against the skin, glazing and fuselage),
a compact panel and six cream club seats (`points.cabinSeats`, facing pairs + table), cabin floor y 3.6, ceiling 9.2, wall x ±3.0,
z -12..4.5, door L1 with an integrated airstair (`AircraftModel.setAirstair`). The founder's window-seat camera is
`points.cabinCamera` (seat 3); companions use seats 1, 2, 4 (JetPlan.COMPANION_SEATS). A richer cabin (galley, lavatory,
side ledges, lights) can be added inside these bounds; keep the attachment names and `points()` contract.
STATUS: open (info)

## 4. Everyone — what the clients show (FYI)
* `workspace.CompanyJetClient` (JetController): the local company's jet in Hangar 1 (the airport's decorative
  `Hangar/PrivateJet` is hidden locally while the company owns a jet), every jet outside the hangar / on the PM stands
  (`PM2` ParkedAircraft hidden locally while a jet uses slot 2), pilots, companions, tug, a local hangar light.
* `workspace.GuestLife` (GuestController): hotel guests (<= 12 per plot, nearest 2 plots within 240 studs) and terminal
  passengers (<= 40, City Airport hall incl. CityLifeController's own 30 ambient walkers / Port Meridian hall + apron
  walkway). Both are client-only, no server writes, no network traffic.
* AirportBuilder (additive, guests_jet): `Hangar/HangarInterior` - jet parking markings, crew corner, workbench, a light
  lining on the upper hangar walls (`HangarLining` / `LiningTrim`, non-colliding, above HY+9), neon strips, banner.
STATUS: open (info)

## 5. flight (ShuttleController) — the ride GUI hides the captain's announcements and the phone in the window seat
`openRide()` creates `ShuttleRide` with `DisplayOrder = 80`; its cabin-wall UIStroke (Thickness 1800) covers the whole
screen except the window: the Toasts (UIRoot top layer `AIEmpire_Top`, DisplayOrder 30) - "This is your captain..." /
seat-belt toasts - and the phone (Phone.ORDER_CLOSED 15 / ORDER_OPEN 28) are invisible / unreachable while the view is
"Window seat". Suggested change (what JetController's JetRide does since fix round 1, `Jet.RIDE_ORDER`):
`gui.DisplayOrder = 14` (above the HUD 10, below the phone launcher 15, the open phone 28 and the toasts 30), so the
itinerary / calendar / calls stay reachable during the flight. Also consider the flight info box at the bottom
(`AnchorPoint (0.5, 1)`, `Position (0.5, 0, 1, -28)`): on an 844x390 phone the box at the top overlaps the window oval
(guiprev: out/guests_jet/gui_fix1_window_phone_phone.png shows the jet's bottom layout with the phone button).
STATUS: open


## 6. Lead / econ — record a design decision in CORE_SPEC (jet fuel of the founder's own flights)
LOGIC_BRIEF 23c: the jet "costs fuel". CompanyOps charges `Ops.JET.fuel` ($1,500) per B2B abroad jet trip (tripPlan);
the founder's private flights cost nothing so far. Since fix round 1 a flight started from the owner prompt at the
airstair charges one leg, `JetService.FUEL_LEG = Ops.JET.fuel / 2` = $750, via `EconomyService.spend(s, 750, "jet")`
(P&L line "jet", already shown by EmpireApp / AssistantService; not enough cash -> "You need $750 for the jet fuel.").
API flights (`JetService.fly` without `pay = true`: itinerary trips that CompanyOps already charges) cost nothing.
Please add one line to CORE_SPEC (jet section): "Founder prompt flights: $750 fuel per leg (JetService, P&L jet);
itinerary jet trips are charged by CompanyOps.tripPlan only." No saved field, no new remote.
STATUS: open

## 7. itinerary — what changed in the jet API (fix round 1)
agents/guests_jet/API.md is current: `fly` can return `RUNWAY_BUSY` (+ `eta`; the jet departs only into a slot clear of
the shuttle, the ambient airliners and other company jets, waiting up to 240 s while boarding), `pay = true` charges
the fuel leg (do NOT pass it for CompanyOps tripPlan jet trips), field staff waiting for the jet join the founder's
flight (`result.staff`), `JetService.summon(player)` fetches the jet to Port Meridian for a founder who went by
shuttle (the `JET_AT_HOME` case), placement uses `JetPlan.arrivalSpots(dest)` (first free spot within 9 studs of
`JetPlan.ARRIVAL.*`), `available()` reports `JET_BUSY` with `info.purpose = "staff" | "position"` while the jet flies
field staff. Please add an integration test (companions = the real field rep, booking from the phone, summon) when
ItineraryService lands.
STATUS: open (info)
STATUS: done by itinerary (integration test tests/itinerary/test_service.luau jet scenario on the real JetService: booking from the phone call, founder jet out + home, no money moved, RUNWAY_BUSY -> wait then fly, JET_BUSY -> shuttle with a message, jet away -> the call books the shuttle, staff jet with the real field rep + engineer -> shuttle for the founder; summon is not used - see design/requests/itinerary.md #2)

## 8. drivers — `DriverService.fieldEta(userId, tripKey) -> number?` (answer to drivers.md §8, option (a))
JetService now waits for the company car before a field-staff flight leaves Hangar 1: when a CompanyOps abroad trip
starts it calls `DriverService.fieldEta(userId, tripKey)` once (tripKey = `tostring(trip.client)..":"..tostring(trip.left)`)
and lets the travellers board only after that many seconds (capped at 240 s). Please export it from DriverService:
seconds until the field ride of that trip reaches the City Airport departures kerb, `nil` when there is no such ride
(no driver paid, not an abroad trip, ride already done). Tested with a stub in tests/guests_jet/test_jet.luau.
STATUS: open
