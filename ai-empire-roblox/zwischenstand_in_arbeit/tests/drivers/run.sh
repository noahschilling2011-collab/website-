#!/usr/bin/env bash
# drivers package suites: test_plan (DrivePlan), test_service (DriverService on the real server modules), test_client
# (DriveController on the real published state), test_review / test_review_client (the review round's adversarial
# scenarios + one check per review issue) and the clearance sweep (every leg vs the real geometry).
# Usage: tests/drivers/run.sh [gen-name]   (default: builds harness/.gen_drivers from work/src)
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
GEN="${1:-.gen_drivers}"
if [ -z "${1:-}" ]; then python3 harness/make_manifest.py --src work/src --gen "harness/$GEN" >/dev/null || exit 1; fi
rc=0
suite() { # label command...
  local label="$1"; shift
  local out; out=$("$@" 2>&1); local r=$?
  local line; line=$(echo "$out" | grep -E "passed, [0-9]+ failed" | tail -n 1)
  printf "%-18s rc=%s  %s\n" "$label" "$r" "$line"
  echo "$out" | grep -E "^FAIL|^CRASH" | head -n 20
  if [ $r -ne 0 ] || ! echo "$line" | grep -q " 0 failed"; then rc=1; fi
}
suite drivers_plan bash -c "cd tests/drivers && timeout 900 ../../tools/luau test_plan.luau -a $GEN"
suite drivers_service bash -c "cd tests/drivers && timeout 900 ../../tools/luau test_service.luau -a $GEN"
suite drivers_client bash -c "cd tests/drivers && timeout 900 ../../tools/luau test_client.luau -a $GEN"
suite drivers_review bash -c "cd tests/drivers && timeout 900 ../../tools/luau test_review.luau -a $GEN"
suite drivers_review_client bash -c "cd tests/drivers && timeout 900 ../../tools/luau test_review_client.luau -a $GEN"
suite drivers_clearance bash tests/drivers/clearance.sh "$GEN"
echo "drivers suites: $(if [ $rc -eq 0 ]; then echo all passed; else echo FAILURES; fi)"
exit $rc
