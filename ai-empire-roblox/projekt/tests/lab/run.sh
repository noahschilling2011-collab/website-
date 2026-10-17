#!/usr/bin/env bash
# Lab package suites (Model Studio). Usage: tests/lab/run.sh [gen-name]   (default: builds harness/.gen_lab from work/src)
#   test_labpreview  LabPreview vs the real server handlers (honesty), preset = today's numbers, S1 payload,
#                    server validation of look/target
#   test_studio      the Studio UI in the mock: lifecycle, first-model path + tap budget, tiles, error routing,
#                    reveal record rule, Launch Day, gamepad, touch controls, sizes, scale, chat buttons
#   models_ui x3     tests/models/test_ui.luau (empty/rich/full) must stay green unchanged (Lab home + Launch Day strings)
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
GEN="${1:-.gen_lab}"
if [ -z "${1:-}" ]; then python3 harness/make_manifest.py --src work/src --gen "harness/$GEN" >/dev/null || exit 1; fi
rc=0
suite() { # label dir file [arg]
  local label="$1" dir="$2" file="$3" arg="${4:-}"
  local out; out=$(cd "$dir" && timeout 900 ../../tools/luau "$file" -a "$GEN" $arg 2>&1); local r=$?
  local line; line=$(echo "$out" | grep -E "passed, [0-9]+ failed" | tail -n 1)
  printf "%-18s rc=%s  %s\n" "$label" "$r" "$line"
  echo "$out" | grep -E "^(FAIL|NOTE)" | head -n 20
  if [ $r -ne 0 ] || ! echo "$line" | grep -q " 0 failed"; then rc=1; fi
}
suite lab_preview tests/lab test_labpreview.luau
suite lab_studio tests/lab test_studio.luau
for s in empty rich full; do suite "models_ui_$s" tests/models test_ui.luau "$s"; done
echo "lab suites: $(if [ $rc -eq 0 ]; then echo all passed; else echo FAILURES; fi)"
exit $rc
