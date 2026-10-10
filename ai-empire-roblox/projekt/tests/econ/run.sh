#!/usr/bin/env bash
# econ package test suites (CompanyOps units, B2B pipeline, services + remotes, save migration, network budget).
# Usage: tests/econ/run.sh [gen-name]   (default: builds harness/.gen_econ from work/src)
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
GEN="${1:-.gen_econ}"
if [ -z "${1:-}" ]; then python3 harness/make_manifest.py --src work/src --gen "harness/$GEN" >/dev/null || exit 1; fi
rc=0
for t in ops b2b service migration net; do
  out=$(cd tests/econ && ../../tools/luau "test_$t.luau" -a "$GEN" 2>&1)
  r=$?
  line=$(echo "$out" | grep -E "passed, [0-9]+ failed" | tail -n 1)
  printf "%-16s rc=%s  %s\n" "econ_$t" "$r" "$line"
  echo "$out" | grep -E "^(FAIL|ERROR)" | head -n 20
  echo "$out" | grep -E "^  " | head -n 8
  if [ $r -ne 0 ] || ! echo "$line" | grep -q " 0 failed"; then rc=1; fi
done
exit $rc
