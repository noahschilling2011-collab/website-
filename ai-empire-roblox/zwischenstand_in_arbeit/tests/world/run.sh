#!/usr/bin/env bash
# World package: all headless suites + the world dump checks (budgets, holes, entrance reachability).
# Usage: tests/world/run.sh [--src DIR]   (default work/src)
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
SRC=work/src; [ "${1:-}" = "--src" ] && SRC="$2"
python3 harness/make_manifest.py --src "$SRC" --gen harness/.gen_world >/dev/null || exit 1
rc=0
for t in test_cityplan test_build test_travel test_vehicle test_client; do
  tools/luau "tests/world/$t.luau" -a .gen_world 2>&1 | grep -E "^FAIL|^ERROR|passed" ; [ ${PIPESTATUS[0]} -eq 0 ] || rc=1
done
agents/airport/world_dump.sh --src "$SRC" --out out/world 2>&1 | grep -E "^parts|new parts|terminal interior|lights|hole check|map edge|prompts|WORLD CHECK" ; [ ${PIPESTATUS[0]} -eq 0 ] || rc=1
python3 agents/world/entrances.py out/world/world_dump.json | tail -1 ; [ ${PIPESTATUS[0]} -eq 0 ] || rc=1
exit $rc
