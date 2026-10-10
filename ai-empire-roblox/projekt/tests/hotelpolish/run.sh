#!/usr/bin/env bash
# Package "hotelpolish" tests (guest house as a real small hotel). Builds tiers 2-4 of the current tree and
# a baseline tier 2 with the pre-package RoomKitsHotel/ExteriorDesign (agents/stable/src_p2_base_0805) into
# tests/hotelpolish/out (private generated manifests .gen_hotelpolish_t / .gen_hotelpolish_tb) plus a tier-2
# dump with GUI layout fields (tests/hotelpolish/gui_dump.luau -> out/gui_tier2.json), runs the geometry check
# on each tier and tests/hotelpolish/test_hotel.py on the dumps.
# Usage: tests/hotelpolish/run.sh            (works in the main tree and in a run_all sandbox)
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
OUT="$ROOT/tests/hotelpolish/out"; mkdir -p "$OUT/base"
SRC="$ROOT/work/src"
BASE_FILES="$ROOT/agents/stable/src_p2_base_0805/ServerScriptService/Server/Services"
[ -d "$BASE_FILES" ] || BASE_FILES="/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad/agents/stable/src_p2_base_0805/ServerScriptService/Server/Services"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cp -r "$SRC" "$TMP/src"
for f in RoomKitsHotel ExteriorDesign; do cp "$BASE_FILES/$f.module.luau" "$TMP/src/ServerScriptService/Server/Services/"; done
TIERS="2 3 4" GEN=hotelpolish_t harness/run.sh --out "$OUT" --check > "$OUT/harness.txt" 2>&1 || { tail -n 30 "$OUT/harness.txt"; echo "hotelpolish: 0 passed, 1 failed"; exit 1; }
TIERS="2" GEN=hotelpolish_tb harness/run.sh --src "$TMP/src" --out "$OUT/base" > "$OUT/harness_base.txt" 2>&1 || { tail -n 30 "$OUT/harness_base.txt"; echo "hotelpolish: 0 passed, 1 failed"; exit 1; }
# tier 2 again with GUI layout fields (SurfaceGui pixels per stud / light influence, frames) -> out/gui_tier2.json
tools/luau tests/hotelpolish/gui_dump.luau -a --tier 2 --gen .gen_hotelpolish_t --quiet 2>&1 | python3 harness/split_dump.py "$OUT/gui_tier2.json" "$OUT/gui_log_tier2.txt" || { tail -n 30 "$OUT/gui_log_tier2.txt"; echo "hotelpolish: 0 passed, 1 failed"; exit 1; }
python3 tests/hotelpolish/test_hotel.py --out "$OUT" --tiers 2,3,4
