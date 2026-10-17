#!/usr/bin/env bash
# corefix package suites: tests/corefix (server regression checks per verified finding + Campus app UI),
# plus the econ and models suites the corefix changes touch.
# Usage: tests/corefix/run.sh [gen-name]   (default: builds harness/.gen_corefix from work/src)
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
GEN="${1:-.gen_corefix}"
if [ -z "${1:-}" ]; then python3 harness/make_manifest.py --src work/src --gen "harness/$GEN" >/dev/null || exit 1; fi
rc=0
for t in corefix ui; do
  out=$(cd tests/corefix && timeout 900 ../../tools/luau "test_$t.luau" -a "$GEN" 2>&1)
  r=$?
  line=$(echo "$out" | grep -E "passed, [0-9]+ failed" | tail -n 1)
  printf "%-16s rc=%s  %s\n" "corefix_$t" "$r" "$line"
  echo "$out" | grep -E "^(FAIL|ERROR)" | head -n 20
  echo "$out" | grep -E "^  info" | head -n 4
  if [ $r -ne 0 ] || ! echo "$line" | grep -q " 0 failed"; then rc=1; fi
done
bash tests/econ/run.sh "$GEN" || rc=1
bash tests/models/run.sh >"$ROOT/agents/corefix/.models_last.txt" 2>&1 || rc=1
grep -E "^(models|models_ui_[a-z]+): " "$ROOT/agents/corefix/.models_last.txt" | sed 's/^/  /'
grep -E "^FAIL" "$ROOT/agents/corefix/.models_last.txt" | head -n 10
exit $rc
