# Requests / interfaces from package "guests_jet" (company jet, hotel guests, terminal passengers)

## 1. Lead — run_all: add the guests_jet suites
Append to tests/lead/run_all.sh:
```
# guests_jet (round 2b): company jet (JetService + JetController), hotel guests + terminal passengers (GuestPlan +
# GuestController), airliners unchanged + bizjet budgets, hotel walks vs tiers 2-4, jet hull + walks vs the world (~3 min)
python3 harness/make_manifest.py --src work/src --gen harness/.gen_gj >/dev/null
run guests_jet_jet      bash -c "cd tests/guests_jet && ../../tools/luau test_jet.luau -a .gen_gj"
run guests_jet_guests   bash -c "cd tests/guests_jet && ../../tools/luau test_guests.luau -a .gen_gj"
run guests_jet_aircraft bash tests/guests_jet/aircraft.sh
run guests_jet_geometry bash tests/guests_jet/run.sh --geometry-only
```
Expected today: guests_jet_jet 146/0, guests_jet_guests 284/0, guests_jet_aircraft 27/0, guests_jet_geometry =
hotel_paths 4/0 + clearance 18/0 (the last summary line is the clearance one). tests/guests_jet/negative.sh: 10/10
mutations detected (`--no-world` skips the slow one: 9/9).
New files (no owner yet besides this package): `ReplicatedStorage/Shared/JetPlan.module.luau`,
`ReplicatedStorage/Shared/GuestPlan.module.luau` (pure maths, required by JetService / JetController / GuestController).
STATUS: open

## 2. itinerary — the company jet API (no change needed)
See agents/guests_jet/API.md: `JetService.available(player) -> (ok, reason, info)`, `JetService.fly(player, {to,
companions, onArrive}) -> {ok, flightId, departAt, arriveAt, doneAt, delay, slot, to, destination, err}`,
`JetService.onArrive(fn) -> disconnect`, `JetService.status(player)`. The founder is placed at `JetPlan.ARRIVAL.abroad`
(next to the VIP limousine stand, MetroPlan.VIP_LIMO.stand) / `JetPlan.ARRIVAL.home` (City Airport arrivals, the shuttle's
arrival point), so the limo / driver pick-up can start right there. Jet trips' money stays in CompanyOps (Ops.JET).
STATUS: open (info)

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
STATUS: open (info)

## 5. flight (ShuttleController) — the ride GUI hides the captain's announcements in the window seat
`openRide()` creates `ShuttleRide` with `DisplayOrder = 80`; its cabin-wall UIStroke (Thickness 1800) covers the whole
screen except the window, and the Toasts live in UIRoot's top layer (`AIEmpire_Top`, DisplayOrder 30) - so the
"This is your captain..." / seat-belt toasts are invisible while the view is "Window seat" (cockpit / outside views
hide the window frame, so they show there). Suggested change: `gui.DisplayOrder = 28` (above HUD 10 / Computer 20 /
intro 25, below the toasts 30) - JetController's JetRide uses 28 for the same reason. Also consider the flight info box
at the bottom (`AnchorPoint (0.5, 1)`, `Position (0.5, 0, 1, -28)`): on an 844x390 phone the box at the top overlaps the
window oval (guiprev: out/guests_jet/gui_jetride_phone.png shows the jet's bottom layout).
STATUS: open
