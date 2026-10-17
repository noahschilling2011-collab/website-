#!/usr/bin/env bash
# itinerary package suites: test_math (ItineraryMath, pure), test_service (ItineraryService on the real server modules,
# one scenario per run: abroad jet region offer edge remote), test_client (ItineraryController on the published state)
# and test_review (the independent reviewer's adversarial scenarios, adopted as regression tests of the review round).
# Usage: tests/itinerary/run.sh [gen-name]   (default: builds harness/.gen_itinerary from work/src)
# All runs go in parallel (each a few seconds to ~1 min).
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
GEN="${1:-.gen_itinerary}"
if [ -z "${1:-}" ]; then python3 harness/make_manifest.py --src work/src --gen "harness/$GEN" >/dev/null || exit 1; fi
TMP="$(mktemp -d)"
run_bg() { # label file [arg]
  local label="$1" file="$2" arg="${3:-}"
  ( cd tests/itinerary && timeout 1800 ../../tools/luau "$file" -a "$GEN" $arg >"$TMP/$label.out" 2>&1; echo $? >"$TMP/$label.rc" ) &
}
SERVICE="abroad jet region offer edge remote"
REVIEW="race offerwait cabin cabinctl paidticket garage stalecall abroadstart two midnight leave respawn spam endflight overhold stage5 rigcost timed together jettogether"
LABELS="itinerary_math"
run_bg itinerary_math test_math.luau
for sc in $SERVICE; do run_bg "itinerary_service_$sc" test_service.luau "$sc"; LABELS="$LABELS itinerary_service_$sc"; done
run_bg itinerary_client test_client.luau
LABELS="$LABELS itinerary_client"
for sc in $REVIEW; do run_bg "itinerary_review_$sc" test_review.luau "$sc"; LABELS="$LABELS itinerary_review_$sc"; done
wait
# the timing scenario alone (the parallel runs above share the CPU)
run_bg itinerary_review_perf test_review.luau perf; LABELS="$LABELS itinerary_review_perf"
wait
rc=0; total=0; totalFail=0
for label in $LABELS; do
  r=$(cat "$TMP/$label.rc" 2>/dev/null || echo 99)
  line=$(grep -E "passed, [0-9]+ failed" "$TMP/$label.out" | tail -n 1)
  printf "%-32s rc=%s  %s\n" "$label" "$r" "$line"
  grep -E "^FAIL|^CRASH|^perf" "$TMP/$label.out" | head -n 20
  p=$(echo "$line" | sed -nE 's/.*: ([0-9]+) passed, ([0-9]+) failed.*/\1/p'); f=$(echo "$line" | sed -nE 's/.*: ([0-9]+) passed, ([0-9]+) failed.*/\2/p')
  total=$((total + ${p:-0})); totalFail=$((totalFail + ${f:-1}))
  if [ "$r" != "0" ] || ! echo "$line" | grep -q " 0 failed"; then rc=1; fi
done
rm -rf "$TMP"
echo "itinerary suites: $total passed, $totalFail failed ($(if [ $rc -eq 0 ]; then echo all passed; else echo FAILURES; fi))"
exit $rc
