#!/usr/bin/env bash
# Fresh HQ dumps by BUILDING PLAN TIER for the Blender previews: out/blenderprev/dumps/dump_tier{0..4}.json
# (scene hqN = plan tier N). Since the 5-stage EmpireConfig.OFFICES (1 = Garage Lab, 2..5 = "Founder
# Headquarters" .. "Global AI Headquarters" = plan tiers 1..4) office stage = plan tier + 1; harness/build_dump.luau
# only accepts --tier 0..4, so this uses the blenderprev copy build_dump_stage.luau (--tier = office stage).
# Usage: tools/blenderprev/hq_dumps.sh [--out DIR] [plan tiers, default "0 1 2 3 4"]
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
OUT=out/blenderprev/dumps
if [ "${1:-}" = "--out" ]; then OUT="$2"; shift 2; fi
PLANS="${*:-0 1 2 3 4}"
mkdir -p "$OUT"
python3 harness/make_manifest.py --src work/src --gen harness/.gen_blenderprev >/dev/null || exit 1
fail=0
for p in $PLANS; do
  office=$((p + 1))
  tools/luau tools/blenderprev/build_dump_stage.luau -a --tier $office --gen .gen_blenderprev --quiet 2>&1 \
    | python3 harness/split_dump.py "$OUT/dump_tier$p.json.tmp" "$OUT/log_tier$p.txt"
  st=("${PIPESTATUS[@]}")
  if [ "${st[0]}" = 0 ] && [ "${st[1]}" = 0 ]; then
    mv "$OUT/dump_tier$p.json.tmp" "$OUT/dump_tier$p.json"; echo "plan tier $p (office $office): $(cat "$OUT/log_tier$p.txt" | tail -1)"
  else
    rm -f "$OUT/dump_tier$p.json.tmp"; echo "plan tier $p FAILED, see $OUT/log_tier$p.txt"; fail=1
  fi
done
exit $fail
