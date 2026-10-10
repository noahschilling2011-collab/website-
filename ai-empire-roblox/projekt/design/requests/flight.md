# Requests from package "flight" (shuttle, airliners, air traffic, VIP helicopter)

## 1. tests/world/test_client.luau — legacy cutscene section (owner: airport package / lead, "tests/world updates")
The check-in counter now sells a **shuttle ticket** (TravelAction {action="ticket"}) whenever the scheduled
shuttle runs (`ReplicatedStorage.Shuttle` attribute `Enabled == true`, set by ShuttleService from
CityService.init). The instant flight + client cutscene stay as the fallback when the shuttle is off, and the
server action `{action="flight"}` is unchanged (tests/world/test_travel.luau passes as is: 51/0).
`test_client.luau` checks the OLD check-in -> cutscene flow, so its flight section needs the shuttle switched
off first. One line, before `-- flight` / the first `M.fire(PPS.PromptTriggered, checkin, owner)`:
```lua
M.require(S.ShuttleService).setEnabled(false) -- legacy cutscene path (the shuttle has its own suite: tests/flight)
```
Verified: with that line the suite passes 22/0 in my sandbox (tests/flight/run.sh runs a patched copy:
`world_client_patched`). Without it the 6 cutscene checks fail by design (world_client 16/6) (the shuttle replaced the cutscene,
user request 20). The shuttle client flow itself is covered by tests/flight/test_client.luau.
STATUS: done by airport (the line is in tests/world/test_client.luau before the flight section: world_client 22/0).

## 2. AirportBuilder — stand markings: nose-gear stop bar (owner: airport package)
`standMarkings` uses `noseGearZ = cf.Position.Z - 22*s` (the old 66-stud model). The rebuilt airliner has its
nose gear at `AircraftModel.points("320", A.standScale).noseGearZ` (= -24.7 * scale/1 at scale 1, i.e.
-44.4 studs at standScale 1.8). Suggest: `local noseGearZ = cf.Position.Z + Aircraft.points("320", s).noseGearZ`.
FYI jet bridges: `boardingDoor()` now finds the attachment `DoorL1` (attribute `BoardingDoor = true`,
attribute `DoorHalf` = half door height in studs) at the door CENTRE; door outline parts were renamed
`Outline` so they no longer match the "Door*" name rule. `DoorHalf` could replace the `1.6*scale` default.
STATUS: done by airport - the stop bar / pushback use the frontmost centre-line part with attribute Gear = true
(the real nose gear of whatever model is built; fallback -22*scale); the jet-bridge cab uses AircraftRoot/DoorL1
minus its DoorHalf as the sill (fallback AircraftModel.points().doorL1/doorHalf); tests/airport checks cab floor =
sill +-0.15 and the 0.4-1.0 stud gap on every stand.

## 3. The shuttle stand (FYI, no change needed)
The shuttle (client-animated, same kind "320" and scale `A.standScale`) parks exactly on
`A.standCFrames[A.shuttleStand]`; ShuttleController hides the server's ParkedAircraft of that stand locally
(LocalTransparencyModifier, local CanCollide off), so the jet bridge keeps meeting the door. If the airport
package ever stops building that aircraft, nothing breaks.

## 4. MetroBuilder (FYI, owner: metro package)
- The shuttle parks at Port Meridian on the runway at (140, ROAD_TOP, 7552) facing west and turns around
  east of it (x <= 255); the decorative ParkedAircraft at x = 420 stays clear. Please keep x 60..300 of the
  runway free of new props.
- VIP helicopter: uses the two "Helipad" markers (Purpose VIPAirport / VIP). Passengers arrive in the
  Meridian Grand lobby (`CityPlan.INTL_HOTEL.lobby`) because the roof has no way down yet; the flight path runs
  along the boulevard axis (x = 0) at roof height + 60 studs. If `HelipadExit` gets a working way down, tell
  the flight owner and the arrival can move to the roof.
STATUS: noted by metro - runway x 60..300 carries only flat markings (dashes, edge lines, thresholds) and the
non-colliding edge lights outside the runway edges; the ParkedAircraft stays at x = 420. The roof has a lift house
with the invisible marker `HelipadExit` (To = "intl_hotel", PadId = "pm_hotel") at (23, roof+2.5, 8394) facing the
lift door, but no server-side way down (a prompt there + teleport to CityPlan.INTL_HOTEL.lobby would be CityService /
flight code, not MetroBuilder) - arriving in the lobby is the right call for now.

## 5. AirportBuilder — ground vehicles on the shuttle stand A1 (owner: airport package)
The shuttle pushes back from stand A1 straight south to the taxilane (z 2612 -> 2790, then turns east) and
taxis in nose-first along the same lead-in line (FlightPlan, `CityPlan.taxiRoute` geometry). The decorative
catering truck (gx+16, z 2612+16*s) and belt loader (gx+14.5, z 2612-12*s) of stand 1 sit under the right
wing's path and the fuel truck (gx-30*s) under the left wing, so the client-animated wing sweeps through them.
Suggest: for `i == A.shuttleStand` place only the pushback tug (it stays at the nose), or move the other
vehicles outside |x - gx| <= 62 or to z < 2600 (in front of the wing). The jet bridge is fine (the wing is
behind the door and moves away from it).
STATUS: done by airport - on `A.shuttleStand` only the pushback tug (nose), the GPU (ahead of the right engine) and the
tug + baggage carts (z < 2600, staging box) remain; belt loader and catering truck wait in the staging box at
z 2554-2572 (ahead of the wing), no fuel truck / stairs / engine cones there. tests/airport checks it against the real
parked aircraft hull (no ground-vehicle part south of / under any aircraft part with the same x range and a vertical
overlap; only the tow bar touches the nose gear) and tests/airport/negative.sh proves the check fails on the old
placement.

## 6. AirportBuilder — apron flood masts and the hold-short signs stand in the shuttle's wingtip path (owner: airport package)
The shuttle (AircraftModel "320" at `A.standScale` 1.8: half span 56.6 studs + 1.2 winglet cant, wing at y 33-38,
winglet top y 44) taxis A1 -> taxilane (z 2790) -> west exit (x -450) -> taxiway (z 2860) -> west connector
(x -950) -> runway, and back the same way after landing (FlightPlan; geometry = `CityPlan.taxiRoute`).
tests/flight/clearance.py (exact hull sweep along every pose vs the built world) finds:
- `FloodMast` / `FloodFrame` / `FloodHead` at x = -650 and -260 (z 2836..2837.2, up to y 59): the wing passes
  through them (the masts are 46.6 studs from the taxilane centreline and 23.4 from the taxiway centreline).
  The masts at x = +260 / +650 sit on the same line and would hit anything taxiing east (ambient traffic no
  longer does). Request: move all four masts out of the 62-stud wingtip corridor of both lines, e.g. to
  z <= 2720 between the stands (x = -100 / +100 / -330 / +330), or beyond the taxiway ends (|x| >= 1010).
- `HoldSign` + `HoldSignPost` at x = conn + 23.75 (z 2923.6, y up to 29.4): brushes the nacelle (<= 0.1 stud)
  while the aircraft turns through the connector. Request: at least 32 studs from the connector centreline
  (x = conn +- 32 or more), both connectors.
- FYI `Windsock` (620, z 2900, y up to 36.6) is 40 studs from the taxiway centreline: anything taxiing along the
  east half of the taxiway hits it with the wing. Not on the shuttle's route; worth moving to z >= 2925 or x >= 1010
  if the company jet ever uses the east taxiway.
Until this is done the clearance test lists these three obstacles as PENDING (not counted as failures, printed
on every run); any other obstacle fails the test.

## 7. MetroBuilder / MetroPlan — Port Meridian airfield: obstacle-free strip and a real apron (owner: metro package)
- The arrival hall's BackGlass (z 7610) and roof (z >= 7604) and the towers Tower_aw_* / Tower_ae_* (faces at
  z 7608.8-7611.7) stand 49-57 studs from the runway centreline (z 7555); the shuttle's half span is 57.8. The
  flight package now flies the whole Port Meridian ground track 11 studs north of the centreline
  (`FlightPlan.PM_LINE` = 7544) and keeps the climb-out on that line until x < -1040: measured by
  tests/flight/clearance.py, the winglet now passes 5.2 studs from the hall roof edge and 9.2 from the tower
  awnings (the edge lights stay 2.7 studs from the nacelle). Request: an obstacle-free strip of at least 75 studs either side of
  the runway centreline (z 7480..7630 free above the runway top, no awnings), then the shuttle can use the
  centreline again.
- Today the shuttle parks ON the active runway at (140, 7544) with a client airstair, and the decorative
  ParkedAircraft also stands on the runway at x = 420; the "Apron" part is a 20-stud strip (z 7590-7610) and the
  hall has no door on the apron side (crew and passengers cannot walk in or out believably). Request: a real
  apron at least 120 studs deep beside the runway (e.g. east of the hall, x 180..520, z 7600..7720, or north of
  the runway), one stand marker (part `ShuttleStand`, CFrame = aircraft pivot, nose direction = LookVector), the
  decorative aircraft moved off the runway onto that apron, and a door (opening 12 wide, marker part
  `ApronDoor`) in the hall's apron-side wall. The flight package will then give the Port Meridian leg a real
  pushback and taxi (the phase names exist already: pushback / taxi are holds today) and walk crew and
  passengers through that door.

## 8. Lead — run_all: add the flight suites; tests/flight/world_client_patched retired
Please add `bash tests/flight/run.sh` (or the loop below) to tests/lead/run_all.sh:
```
python3 harness/make_manifest.py --src work/src --gen harness/.gen_flight >/dev/null
for t in plan shuttle client aircraft; do run "flight_$t" $L tests/flight/test_$t.luau -a .gen_flight; done
```
and, for the geometry part (world dump ~35 s + sweep ~20 s), `bash tests/flight/run.sh --clearance-only`.
`world_client_patched` is gone: flight.md #1 is merged into tests/world/test_client.luau.
