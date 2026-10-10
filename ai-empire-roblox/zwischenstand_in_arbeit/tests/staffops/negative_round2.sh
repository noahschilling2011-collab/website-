#!/usr/bin/env bash
# Regression negative check of the review fix round (round 2): the suites that cover the reviewer's issues
# must FAIL on the staffops files of review round 1 (agents/staffops/round1: StaffService, StaffEvents,
# StaffRota, StaffAssignment, EmployeeConfig, Dialogue, PropFxController). Prints "<n> of <m> detected".
cd "$(dirname "$0")/../.." || exit 1
python3 tests/staffops/mkharness.py --prev >/dev/null || exit 1
n=0; m=0
for t in client beacon rack nightfault ops academy absence talk perf; do
  m=$((m+1))
  out=$(timeout 1800 tools/luau tests/staffops/test_staffops.luau -a "$t" prev 2>&1); r=$?
  line=$(echo "$out" | grep -E "passed|ERROR" | tail -n 1)
  if [ $r -ne 0 ]; then n=$((n+1)); echo "detected  $t: $line"; else echo "MISSED    $t: $line"; fi
done
echo "staffops negative round 2: $n of $m detected"
[ $n -eq $m ]
