#!/usr/bin/env bash
# apps package suites (HUD Next goal, Company app Clients/Money/Settings, Hardware app, assistant briefing, screens,
# security titles). Usage: tests/apps/run.sh [gen-name]   (default: builds harness/.gen_apps from work/src)
# Every suite prints "<name>: N passed, M failed"; exit code 1 when any suite fails or crashes.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
GEN="${1:-.gen_apps}"
if [ -z "${1:-}" ]; then python3 harness/make_manifest.py --src work/src --gen "harness/$GEN" >/dev/null || exit 1; fi
rc=0
run() {
  local name="$1"; shift
  local out; out=$(cd tests/apps && timeout 900 ../../tools/luau "$@" 2>&1); local r=$?
  local line; line=$(echo "$out" | grep -E "passed, [0-9]+ failed" | tail -n 1)
  printf "%-20s rc=%s  %s\n" "$name" "$r" "$line"
  echo "$out" | grep -E "^FAIL" | head -n 20
  if [ $r -ne 0 ] || ! echo "$line" | grep -q " 0 failed"; then rc=1; fi
}
for st in garage client save mid rich phone; do run "apps_ui_$st" test_ui.luau -a "$GEN" "$st"; done
for st in garage mid rich; do run "apps_server_$st" test_server.luau -a "$GEN" "$st"; done
for sc in garage_edge stage5 rackfull oldsave many spam midnight broke hr; do run "apps_adv_$sc" test_adv.luau -a "$GEN" "$sc"; done
exit $rc
