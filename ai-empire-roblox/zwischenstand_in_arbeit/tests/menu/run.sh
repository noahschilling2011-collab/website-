#!/usr/bin/env bash
# Menu package suites ("First steps" guide, Menu shell, Home; ONBOARDING_SPEC A + B, lab requests #1 #2 #5 #6).
# Usage: tests/menu/run.sh [gen-name] [--sizes]   (default: builds harness/.gen_menu from work/src)
#   menu_server          T1-T5, T10: TutorialMath, cleaner, EmpireAction tutorial ops, ClaimQuest {all}, names, waves
#   menu_client_guide    T6 + T8 + A8/A12 + lab #1/#2/#5 + Intro: the guided path by ringed taps only (5 taps)
#   menu_client_menu     T9, T11, T12, B5, B11: Home cards, route table + grepped pairs, back rule, badges, Shop button
#   --sizes              T7/T8 geometry on the guiprev dumps of tests/menu/render.sh (out/menu/*.dump; run render.sh first)
# Mutation proof: tests/menu/negative.sh. Previews: tests/menu/render.sh -> out/menu/*.png (+ .dump for --sizes).
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
GEN=".gen_menu"; SIZES=0
for a in "$@"; do
  case "$a" in
    --sizes) SIZES=1 ;;
    *) GEN="$a" ;;
  esac
done
if [ "$GEN" = ".gen_menu" ]; then python3 harness/make_manifest.py --src work/src --gen "harness/$GEN" >/dev/null || exit 1; fi
python3 tests/menu/routes.py >/dev/null || exit 1
rc=0
suite() { # label dir file [arg]
  local label="$1" dir="$2" file="$3" arg="${4:-}"
  local out; out=$(cd "$dir" && timeout 900 ../../tools/luau "$file" -a "$GEN" $arg 2>&1); local r=$?
  local line; line=$(echo "$out" | grep -E "passed, [0-9]+ failed" | tail -n 1)
  printf "%-20s rc=%s  %s\n" "$label" "$r" "$line"
  echo "$out" | grep -E "^(FAIL|NOTE)" | head -n 20
  if [ $r -ne 0 ] || ! echo "$line" | grep -q " 0 failed"; then rc=1; fi
}
suite menu_server tests/menu test_server.luau
suite menu_client_guide tests/menu test_client.luau guide
suite menu_client_menu tests/menu test_client.luau menu
if [ $SIZES -eq 1 ]; then
  out=$(python3 tests/menu/sizes.py out/menu/*.dump 2>&1); r=$?
  printf "%-20s rc=%s  %s\n" "menu_sizes" "$r" "$(echo "$out" | tail -n 1)"
  echo "$out" | grep -E "^FAIL" | head -n 20
  [ $r -ne 0 ] && rc=1
fi
echo "menu suites: $(if [ $rc -eq 0 ]; then echo all passed; else echo FAILURES; fi)"
exit $rc
