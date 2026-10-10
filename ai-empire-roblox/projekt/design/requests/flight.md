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
- `Windsock` / `WindsockPole` (620, z 2900, y up to 36.6) stand 40 studs from the taxiway centreline. Since round 4 the
  visiting airliners (AirTrafficController: land east, east connector, taxiway west to remote stand R2 at (575, 2700),
  later push back onto the taxiway and taxi east) pass it and the wing goes through it (tests/flight/clearance.py:
  depth 1.3). Request: move it to z >= 2925 (between taxiway and runway, beyond 62 studs) or x >= 1010. The mast at
  (650, 2836.6) and the east hold-short sign (x 973.8) are on that route too (same requests as above).
Until this is done the clearance test lists these obstacles as PENDING (not counted as failures, printed on every
run: 14 hits today - shuttle 6, visiting airliners 8); any other obstacle fails the test.

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
STATUS: done by metro (apron, stands, door; the strip only where metro owns the obstacles) - 2026-10-10.
- Apron `MetroPlan.APRON`: concrete, top = `APRON.top` (GROUND + 0.25), rects x 160..548 / z 7590..7688 and
  x 204..548 / z 7688..7721.5 (132 studs deep east of x 204), fenced towards the city, open to the runway. Painted:
  taxi line from the runway edge at x = `APRON.taxiX` (340) bending onto the stand centreline z 7664, stop bars at
  pivot - 50, stand numbers, red safety boxes, a passenger walkway from the door to stand 1's forward left door.
- Stand 1: part `ShuttleStand` under PortMeridian/Airfield (invisible, no collision; CFrame = `APRON.stand` =
  pivot (252, GROUND + 0.25, 7664), LookVector = -X (nose west, ~x 192, towards the hall); attributes
  Stand = "PM1", Purpose = "Shuttle", Door = Vector3 of the door). DoorL1 lands at (210.7, 7670.2); the airstair
  foot (~z 7690) is on the apron and reachable from the hall (tests/metro/reach.py). The whole hull (measured
  AircraftModel "320" bands at scale 1.8, fin top 42) is free of every visible part (tests/metro/test_build).
- Stand 2: the decorative `ParkedAircraft` (pivot `APRON.stand2` = (480, GROUND + 0.25, 7664), facing west,
  attribute Stand = "PM2") with an airstair, power unit, tug + baggage carts. 102 studs between stand 1's tail
  (x 318) and stand 2's nose (x 420) for the pushback / turn; nothing stands on the runway any more.
- `ApronDoor` (invisible, no collision, 12 wide x 11.5 high, LookVector = +X out to the apron) in the hall's east
  wall at x 159.25, z 7655..7667 (between baggage claim and the news kiosk); the wall is cut with a lintel above
  12 studs, the opening is free (test_build), "STAND 1 · SHUTTLE" over it and a docking board above.
- The VIP airport helipad moved to the heliport east of the apron: `MetroPlan.HELIPADS.airport` = (604, GROUND + 1,
  7670), fence gates south-west and east, VIP helicopter terminal x 652..688. Your clearance sweep (clearance_dump.sh
  copied with a private gen dir + clearance.py) passes 18/0 on the new layout; only the 6 City Airport PENDING
  items (flight.md #6) remain. `tests/flight/test_plan.luau` still uses the old pad (310, 7648) as a maths example -
  harmless, but you may want the real `MetroPlan.HELIPADS.airport.cf` there.
- Strip: the airport-district towers west of the hall now start at z 7632 (77 studs off the centreline) and face
  south (no north awnings). Still inside 75 studs: the arrival hall (CityPlan.ABROAD.terminal z 7610, roof from
  z 7604; owner airport - moving it means moving check-in, lounge, arrival point and plaza) and the parked wings on
  the apron (z >= 7607.25, 52 off the centreline). Keep `PM_LINE` = 7544 while rolling past the apron: wingtip
  clearance there 7607.25 - 7601.8 = 5.4 studs (hall roof edge 5.2 as you measured).

## 8. Lead — run_all: add the flight suites; tests/flight/world_client_patched retired
Please add `bash tests/flight/run.sh` (or the loop below) to tests/lead/run_all.sh:
```
python3 harness/make_manifest.py --src work/src --gen harness/.gen_flight >/dev/null
for t in plan shuttle client aircraft; do run "flight_$t" $L tests/flight/test_$t.luau -a .gen_flight; done
```
and, for the geometry part (world dump ~35 s + sweep ~20 s), `bash tests/flight/run.sh --clearance-only`.
`world_client_patched` is gone: flight.md #1 is merged into tests/world/test_client.luau.

## 7b. Update (flight, round 4): the Port Meridian apron is in use
FlightPlan reads `MetroPlan.APRON` (stand 1 = `stand`, `taxiX`, `door`): arrival roll-out on FlightPlan.PM_LINE to
x = taxiX - 70, taxi north along the taxi line and nose-in onto stand 1; departure = pushback east along the stand line,
nose swung north onto the taxi line (the tail reaches z ~7734, 13 studs past the apron's city edge at 7721.5, at
~15 studs height - the clearance sweep finds nothing there today; keep that strip free of anything taller than 12
studs), taxi north, left onto the runway, take-off roll west on PM_LINE. Boarding / passengers use the hall's apron
door (FlightPlan.PM_DOOR) and the client airstairs at the forward left door; a local pushback tug serves stand 1.
Nothing more is needed from metro for the shuttle; the runway's obstacle-free strip request above still stands for
the roll-out / take-off on PM_LINE.

## 9. Lead (FYI) — tests/flight/run.sh
`bash tests/flight/run.sh` today: flight_plan 95/0, flight_shuttle 111/0, flight_client 90/0, flight_aircraft 45/0,
flight_clearance 18/0 (14 pending, other packages). Request #8 (add it to run_all) still stands.


## 10. Status (flight, round 5, 2026-10-10 ~16:00 UTC) - still open: #6 (airport) and #8 (lead)
- #6 AirportBuilder (owner airport): unchanged in today's sources, re-measured with `bash tests/flight/run.sh`:
  14 PENDING hits (shuttle 6: FloodMast x = -650 / -260 with the wing up to 1.03 deep, HoldSign x = -926.2 with the
  nacelle up to 0.55; visiting airliners 8: FloodMast x = 650, Windsock / WindsockPole (620, 2900), HoldSign
  x = 973.8). The fix is only in AirportBuilder (`runway()` HoldSign/HoldSignPost at x + 23.75 -> x +- 32 or more;
  the four FloodMast/FloodFrame/FloodHead at z 2836 -> z <= 2720 between stands or |x| >= 1010; Windsock/Pole
  at (620, rw.z1 - 40) -> z >= 2925 or x >= 1010). FlightPlan cannot route round them: the masts stand 3 studs
  off the taxiway edge and the shuttle's half span is 57.8. The clearance suite turns each PENDING into a
  failure as soon as the obstacle list changes, so a moved mast is verified automatically.
- #8 tests/lead/run_all.sh (owner lead): still runs no flight suite (47 suites today). The block to add is in #8;
  `bash tests/flight/run.sh` today: flight_plan 95/0, flight_shuttle 111/0, flight_client 90/0, flight_aircraft
  45/0, flight_clearance 18/0 (+14 pending above), `--negative` 1/0.
- metro #7 note taken: tests/flight/test_plan.luau now uses the real pads (MetroPlan.HELIPADS.airport / hotel).
