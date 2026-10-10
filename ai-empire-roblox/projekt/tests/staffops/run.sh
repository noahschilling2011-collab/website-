#!/usr/bin/env bash
# staffops suites (each prints "staffops_<suite>: N passed, M failed"); exit code != 0 if any suite fails.
cd "$(dirname "$0")/../.." || exit 1
python3 tests/staffops/mkharness.py >/dev/null || exit 1
rc=0
for t in clock absence night ops apprentice rack garage arrival talk client; do
  out=$(tools/luau tests/staffops/test_staffops.luau -a "$t" 2>&1); r=$?
  echo "$out" | grep -E "^FAIL|passed|ERROR" | grep -v "^\[warn\]"
  [ $r -ne 0 ] && rc=1
done
if [ -f tests/staffops/test_ui.luau ]; then
  out=$(cd tests/staffops && ../../tools/luau test_ui.luau 2>&1); r=$?
  echo "$out" | grep -E "^FAIL|passed|ERROR"
  [ $r -ne 0 ] && rc=1
fi
exit $rc
