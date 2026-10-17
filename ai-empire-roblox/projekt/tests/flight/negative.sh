#!/usr/bin/env bash
# Flight package: proves the clearance sweep catches real clipping. Builds a copy of the sources with the old
# Port Meridian ground line (runway centreline, FlightPlan.PM_LINE = PRZ) and expects tests/flight/clearance.py
# to FAIL on the arrival hall / towers. Exit 0 = the sweep failed as it must.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
SRC=work/src; [ "${1:-}" = "--src" ] && SRC="$2"
T=out/flight_negative; rm -rf "$T"; mkdir -p "$T"; cp -r "$SRC" "$T/src"
F="$T/src/ReplicatedStorage/Shared/FlightPlan.module.luau"
grep -q "^FP.PM_LINE=PRZ-11" "$F" || { echo "negative: PM_LINE line not found"; exit 1; }
sed -i 's/^FP.PM_LINE=PRZ-11/FP.PM_LINE=PRZ/' "$F"
bash tests/flight/clearance_dump.sh --src "$T/src" --out "$T/dump" >/dev/null 2>&1 || { echo "negative: dump failed"; exit 1; }
out=$(python3 tests/flight/clearance.py "$T/dump" 2>&1)
rm -rf "$T/src"
if echo "$out" | grep -q "HIT .*PortMeridian/ArrivalTerminal"; then
  echo "flight_negative: 1 passed, 0 failed (the sweep catches the hall on the old centreline track)"
  echo "$out" | grep "HIT" | head -4
  exit 0
fi
echo "$out" | tail -5
echo "flight_negative: 0 passed, 1 failed"; exit 1
