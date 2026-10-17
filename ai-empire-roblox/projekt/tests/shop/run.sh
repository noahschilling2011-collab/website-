#!/usr/bin/env bash
# Shop package suites. usage: tests/shop/run.sh [--negative] [--decor]
#   (default)   server + client suites against work/src
#   --negative  also the 14 mutation checks (each must FAIL the suites)
#   --decor     also build tiers 1-4 with the party kit + Founder Suite into out/shop/decor_dump_tierN.json
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
python3 harness/make_manifest.py --src work/src --gen harness/.gen_shop >/dev/null 2>&1 || exit 1
rc=0
(cd tests/shop && ../../tools/luau test_shop.luau -a .gen_shop 2>&1 | grep -E "^FAIL|tests:") ; [ "${PIPESTATUS[0]}" = 0 ] || rc=1
(cd tests/shop && ../../tools/luau test_client.luau -a .gen_shop 2>&1 | grep -E "^FAIL|tests:")
for a in "$@"; do
  [ "$a" = "--negative" ] && tests/shop/negative.sh
  [ "$a" = "--decor" ] && tests/shop/decor.sh
done
exit $rc
