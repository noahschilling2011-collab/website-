#!/usr/bin/env bash
# shop package (SHOP_SPEC phases 1 + 2) suites. usage: tests/shop2/run.sh [--negative] [--render] [--sizes]
#   (default)   shop2_server (T1-T12, T25, phase 2), shop2_math (T13-T16, T21 + T9/T10 pure parts),
#               shop2_client (T13/T15/T16 UI, T17, sheets, rebrand, tabs); plus the round-1 suites tests/shop/run.sh
#   --negative  the mutation checks of tests/shop2/negative.sh (each must FAIL a suite)
#   --render    GUI previews -> out/shop (tests/shop2/render.sh)     --sizes  T18 on out/shop/*.dump
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
python3 harness/make_manifest.py --src work/src --gen harness/.gen_shop2 >/dev/null 2>&1 || exit 1
python3 tests/shop2/spec_texts.py design/SHOP_SPEC.md work/src tests/shop2/.spec_texts.luau >/dev/null || exit 1
rc=0
for t in test_server test_math test_client; do
  out=$(cd tests/shop2 && ../../tools/luau $t.luau -a .gen_shop2 2>&1)
  echo "$out" | grep -E "^FAIL|^shop2_[a-z]+: [0-9]+ passed"
  echo "$out" | grep -qE "^shop2_[a-z]+: [0-9]+ passed, 0 failed" || rc=1
done
bash tests/shop/run.sh | grep -E "tests:|^FAIL" ; [ "${PIPESTATUS[0]}" = 0 ] || rc=1
for a in "$@"; do
  [ "$a" = "--negative" ] && { bash tests/shop2/negative.sh || rc=1; }
  [ "$a" = "--render" ] && { bash tests/shop2/render.sh || rc=1; }
  [ "$a" = "--sizes" ] && { python3 tests/shop2/sizes.py out/shop/*.dump | tail -n 1; [ "${PIPESTATUS[0]}" = 0 ] || rc=1; }
done
exit $rc
