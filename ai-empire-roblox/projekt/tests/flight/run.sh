#!/usr/bin/env bash
# Flight package: all headless suites. Usage: tests/flight/run.sh [--src DIR] [--clearance-only] [--no-clearance] [--negative]
# flight_plan (FlightPlan maths), flight_shuttle (server: ShuttleService + CityService), flight_client
# (TravelController/ShuttleController/AirTrafficController), flight_aircraft (AircraftModel geometry, budgets,
# pilots in view from the gate lounge), flight_clearance (world dump + exact hull sweep of the shuttle, the
# ambient traffic and the VIP helicopter along every low pose; ~10 s), flight_negative (--negative: proves the
# sweep fails on the old Port Meridian centreline track).
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
SRC=work/src; ONLY=0; CLEAR=1; NEG=0
while [ $# -gt 0 ]; do case "$1" in --src) SRC="$2"; shift;; --clearance-only) ONLY=1;; --no-clearance) CLEAR=0;; --negative) NEG=1;; esac; shift; done
rc=0
if [ $ONLY -eq 0 ]; then
  python3 harness/make_manifest.py --src "$SRC" --gen harness/.gen_flight >/dev/null || exit 1
  for t in test_plan test_shuttle test_client test_aircraft; do
    tools/luau "tests/flight/$t.luau" -a .gen_flight 2>&1 | grep -E "^FAIL|^ERROR|passed" ; [ ${PIPESTATUS[0]} -eq 0 ] || rc=1
  done
fi
if [ $CLEAR -eq 1 ]; then
  if bash tests/flight/clearance_dump.sh --src "$SRC" --out out/flight_clearance >/dev/null 2>&1; then
    python3 tests/flight/clearance.py out/flight_clearance 2>&1 | grep -E "^FAIL|^HIT|^PENDING|passed|pending" ; [ ${PIPESTATUS[0]} -eq 0 ] || rc=1
  else
    echo "FAIL  flight_clearance: world dump failed (out/flight_clearance/log.txt)"; echo "flight_clearance: 0 passed, 1 failed"; rc=1
  fi
fi
if [ $NEG -eq 1 ]; then
  bash tests/flight/negative.sh --src "$SRC" | grep -E "passed|^HIT" ; [ ${PIPESTATUS[0]} -eq 0 ] || rc=1
fi
exit $rc
