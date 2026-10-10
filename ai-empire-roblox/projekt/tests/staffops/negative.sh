#!/usr/bin/env bash
# Negative check: every staffops suite must FAIL on the files as they were before the package
# (agents/staffops/orig: StaffService, StaffJobs, StaffAssignment, RecruitingService, EmployeeConfig, Dialogue,
# PropFxController, EmployeeController; StaffEvents/StaffRota removed). Prints "<n> of <m> detected".
cd "$(dirname "$0")/../.." || exit 1
python3 tests/staffops/mkharness.py --neg >/dev/null || exit 1
n=0; m=0
for t in clock absence night ops apprentice rack garage arrival talk client; do
  m=$((m+1))
  out=$(timeout 900 tools/luau tests/staffops/test_staffops.luau -a "$t" neg 2>&1); r=$?
  line=$(echo "$out" | grep -E "passed|ERROR" | tail -n 1)
  if [ $r -ne 0 ]; then n=$((n+1)); echo "detected  $t: $line"; else echo "MISSED    $t: $line"; fi
done
echo "staffops negative: $n of $m detected"
[ $n -eq $m ]
