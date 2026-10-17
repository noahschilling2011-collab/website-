#!/usr/bin/env bash
# guests_jet: all headless suites. Usage: tests/guests_jet/run.sh [--src DIR] [--quick] [--negative]
#   guests_jet_jet        JetService + JetController (+ CityService world) in the mock: API, validation, flights,
#                         arrival placement, slots, prompt, respawn, ferry, timelines, shared hangar, ride camera, LOD,
#                         seated rigs vs the bizjet skin / glazing / fuselage (80 pilot + 40 companion builds)
#   guests_jet_guests     GuestPlan + GuestController: guest counts, schedules by hour, unique seats / rooms, walls
#                         (BuildingPlan rooms + doors), terminal timing vs FlightPlan, caps, client figures
#   guests_jet_aircraft   AircraftModel: 320 / 380 unchanged at every LOD vs the round-2b baseline, bizjet budgets
#   guests_jet_hotel_paths  every hotel walk vs the built guest house (harness dumps tiers 2-4; built here if missing)
#   guests_jet_clearance  jet hull sweep (all flights, both PM slots) + pilots' / companions' / passengers' walks vs
#                         the built world (world dump ~1 min)
#   --quick: skip the two geometry suites; --geometry-only: only those two; --negative: also run negative.sh
#   (mutations that must fail)
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
SRC=work/src; QUICK=0; NEG=0; GEO=0
while [ $# -gt 0 ]; do case "$1" in --src) SRC="$2"; shift;; --quick) QUICK=1;; --geometry-only) GEO=1;; --negative) NEG=1;; esac; shift; done
GEN=harness/.gen_gj_run_$$
rc=0
python3 harness/make_manifest.py --src "$SRC" --gen "$GEN" >/dev/null || exit 1
if [ $GEO -eq 0 ]; then
  for t in test_jet test_guests; do
    (cd tests/guests_jet && ../../tools/luau "$t.luau" -a "$(basename $GEN)") 2>&1 | grep -E "^FAIL|^ERROR|passed" ; [ ${PIPESTATUS[0]} -eq 0 ] || rc=1
  done
  bash tests/guests_jet/aircraft.sh --src "$SRC" 2>&1 | grep -E "^FAIL|passed" ; [ ${PIPESTATUS[0]} -eq 0 ] || rc=1
fi
if [ $QUICK -eq 0 ]; then
  OUT=out/guests_jet/run_$$; mkdir -p "$OUT"
  (cd tests/guests_jet && ../../tools/luau hotel_walks.luau -a "$(basename $GEN)") > "$OUT/hotel_walks.txt" 2>&1
  DUMPS=""
  for t in 2 3 4; do
    D=out/guests_jet/hq/dump_tier$t.json
    if [ "$SRC" != "work/src" ] || [ ! -f "$D" ]; then
      D="$OUT/dump_tier$t.json"
      tools/luau harness/build_dump.luau -a --tier $t --gen "$(basename $GEN)" --quiet | python3 harness/split_dump.py "$D" "$OUT/log_tier$t.txt" >/dev/null || { echo "FAIL  hotel dump tier $t"; rc=1; }
    fi
    DUMPS="$DUMPS $D"
  done
  python3 tests/guests_jet/hotel_paths.py "$OUT/hotel_walks.txt" $DUMPS 2>&1 | grep -E "^FAIL|^WALK|passed" ; [ ${PIPESTATUS[0]} -eq 0 ] || rc=1
  if bash tests/guests_jet/world_dump.sh --src "$SRC" --out "$OUT/world" >/dev/null 2>&1; then
    python3 tests/guests_jet/clearance.py "$OUT/world" 2>&1 | grep -E "^FAIL|^HIT|^WALK|passed" ; [ ${PIPESTATUS[0]} -eq 0 ] || rc=1
  else
    echo "FAIL  guests_jet_clearance: world dump failed ($OUT/world/log.txt)"; echo "guests_jet_clearance: 0 passed, 1 failed"; rc=1
  fi
  [ $rc -eq 0 ] && rm -rf "$OUT"
fi
rm -rf "$GEN"
if [ $NEG -eq 1 ]; then bash tests/guests_jet/negative.sh | tail -n 3; [ ${PIPESTATUS[0]} -eq 0 ] || rc=1; fi
exit $rc
