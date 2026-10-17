#!/usr/bin/env bash
# Metro package (Port Meridian + client city life): headless suites + world dump checks + walkability.
# Usage: tests/metro/run.sh [--src DIR] [--no-dump]   (default work/src; ~5 min)
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
SRC=work/src; DUMP=1
while [ $# -gt 0 ]; do case "$1" in --src) SRC="$2"; shift;; --no-dump) DUMP=0;; esac; shift; done
python3 harness/make_manifest.py --src "$SRC" --gen harness/.gen_metro >/dev/null || exit 1
rc=0
for t in test_plan test_build test_life test_paths; do
  tools/luau "tests/metro/$t.luau" -a .gen_metro 2>&1 | grep -E "^FAIL|^ERROR|^PERF|passed" ; [ ${PIPESTATUS[0]} -eq 0 ] || rc=1
done
# traffic over 3 more seeds x 5 foci (Port Meridian + downtown): no overlaps in a lane or in world space (oriented
# boxes car-car, walker in car), no red-light runs, plus 2 x 240 s at the busiest foci: no gridlock / starving walkers (~3 min)
tools/luau tests/metro/stress_traffic.luau -a .gen_metro 3 2>&1 | grep -E "^FAIL|^ERROR|^stress|passed" ; [ ${PIPESTATUS[0]} -eq 0 ] || rc=1
if [ $DUMP = 1 ]; then
  agents/metro/world_dump.sh --src "$SRC" --out out/metro/dump --no-render 2>&1 | grep -E "^parts|lights|hole check abroad|WORLD CHECK"
  python3 tests/metro/reach.py out/metro/dump/world_dump.json || rc=1
fi
exit $rc
