#!/usr/bin/env bash
# drivers package: car clearance of every DrivePlan leg (plots 1 + 7 at home, Port Meridian) against the real
# geometry: the shared world dump and the HQ dumps of tiers 1-4 (drivers exist from stage 2 = plan tier 1).
# Dumps: out/drivers/dump_tier{1..4}.json (GEN=drivers harness/run.sh --out out/drivers) and
# out/drivers/base/world/world_dump.json (tools/blenderprev/world_dump.sh --out out/drivers/base/world); missing
# dumps are built first. Usage: tests/drivers/clearance.sh [gen-name]
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
GEN="${1:-.gen_drivers}"
if [ -z "${1:-}" ]; then python3 harness/make_manifest.py --src work/src --gen "harness/$GEN" >/dev/null || exit 1; fi
for t in 1 2 3 4; do
  if [ ! -f out/drivers/dump_tier$t.json ]; then TIERS="1 2 3 4" GEN=drivers harness/run.sh --out out/drivers >/dev/null 2>&1 || { echo "harness failed"; exit 1; }; break; fi
done
if [ ! -f out/drivers/base/world/world_dump.json ]; then tools/blenderprev/world_dump.sh --out out/drivers/base/world >/dev/null 2>&1 || { echo "world dump failed"; exit 1; }; fi
mkdir -p out/drivers
(cd tests/drivers && ../../tools/luau probe_legs.luau -a "$GEN" > ../../out/drivers/legs.txt 2>&1) || { echo "probe failed"; tail -5 out/drivers/legs.txt; exit 1; }
if grep -q "NOLEG" out/drivers/legs.txt && ! grep -q "NOLEG count	0" out/drivers/legs.txt; then echo "drivers_clearance: unroutable legs"; grep NOLEG out/drivers/legs.txt | head; exit 1; fi
python3 tests/drivers/clearance.py out/drivers/legs.txt out/drivers/base/world/world_dump.json \
  out/drivers/dump_tier1.json out/drivers/dump_tier2.json out/drivers/dump_tier3.json out/drivers/dump_tier4.json | grep -v "^  \|^legs "
