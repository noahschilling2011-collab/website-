#!/usr/bin/env bash
# Phone package suites: test_phone (PhoneMath + PhoneService, server) and test_ui (client: garage, rich, the review
# round's scenarios "fixes" and a small touch phone "touch").
# Usage: tests/phone/run.sh [gen-name]   (default: builds harness/.gen_phone from work/src)
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
GEN="${1:-.gen_phone}"
if [ -z "${1:-}" ]; then python3 harness/make_manifest.py --src work/src --gen "harness/$GEN" >/dev/null || exit 1; fi
rc=0
suite() { # label file [state]
  local label="$1" file="$2" state="${3:-}"
  local out; out=$(cd tests/phone && timeout 900 ../../tools/luau "$file" -a "$GEN" $state 2>&1); local r=$?
  local line; line=$(echo "$out" | grep -E "passed, [0-9]+ failed" | tail -n 1)
  printf "%-18s rc=%s  %s\n" "$label" "$r" "$line"
  echo "$out" | grep -E "^FAIL" | head -n 20
  if [ $r -ne 0 ] || ! echo "$line" | grep -q " 0 failed"; then rc=1; fi
}
suite phone test_phone.luau
suite phone_ui_garage test_ui.luau garage
suite phone_ui_rich test_ui.luau rich
suite phone_ui_fixes test_ui.luau fixes
suite phone_ui_touch test_ui.luau touch
echo "phone suites: $(if [ $rc -eq 0 ]; then echo all passed; else echo FAILURES; fi)"
exit $rc
