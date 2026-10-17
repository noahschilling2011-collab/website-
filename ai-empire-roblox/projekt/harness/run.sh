#!/usr/bin/env bash
# Offline HQ harness: regenerate manifest, self-test the mock, dump tiers, frame-consistency check.
# usage: harness/run.sh [--check] [--render] [--src DIR] [--out DIR] [--before] [extra build_dump args...]
#   TIERS="1 3" harness/run.sh      # subset of tiers (default 1 2 3 4)
#   TIERS="0 1 2 3 4" harness/run.sh  # plan tier 0 = the garage stage (built through session.planTier); with 0
#                                    # in TIERS the frame-consistency check also runs for tier 0
#   --check      also run check_geometry.py per tier (report -> OUT/check_tierN.txt, heatmaps OUT/walk_tierN_*.png)
#   --render     also run render.py per tier (images -> OUT/tierN_*.png)
#   --src DIR    Luau source tree to load (default work/src). The generated manifest then goes to
#                harness/.gen_alt/ so it never races with a default run.
#   --out DIR    output directory (default out/)
#   --before     after rendering/checking, copy every image, dump and report into out/ with a
#                "before_" prefix (use with --src pointing at the ORIGINAL sources)
# Extra args are passed to build_dump.luau (e.g. --plot, --cf x,y,z,yaw, --allow-thread-errors).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
OUT="$ROOT/out"
LUAU="$ROOT/tools/luau"
DO_CHECK=0; DO_RENDER=0; DO_BEFORE=0; EXTRA=(); SRC=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) DO_CHECK=1 ;;
    --render) DO_RENDER=1 ;;
    --before) DO_BEFORE=1 ;;
    --src) shift; SRC="$(cd "$1" && pwd)" ;;
    --out) shift; mkdir -p "$1"; OUT="$(cd "$1" && pwd)" ;;
    *) EXTRA+=("$1") ;;
  esac
  shift
done
mkdir -p "$OUT"
TIERS="${TIERS:-1 2 3 4}"
GENARGS=()
if [ -n "${GEN:-}" ]; then
  # GEN=name gives this run its own generated manifest (parallel agents never race)
  python3 "$HERE/make_manifest.py" --src "${SRC:-$ROOT/work/src}" --gen "$HERE/.gen_$GEN" || exit 1
  GENARGS=(--gen ".gen_$GEN")
elif [ -n "$SRC" ]; then
  python3 "$HERE/make_manifest.py" --src "$SRC" --gen "$HERE/.gen_alt" || exit 1
  GENARGS=(--gen .gen_alt)
else
  python3 "$HERE/make_manifest.py" || exit 1
fi
[ -f "$HERE/classes.luau" ] || python3 "$HERE/gen_classes.py" || exit 1

if ! "$LUAU" "$HERE/test_mock.luau"; then echo "mock self-test FAILED"; exit 1; fi
if [ $DO_CHECK = 1 ]; then
  python3 "$HERE/test_check.py" | tail -n 1 || { echo "walkability self-test FAILED"; exit 1; }
fi

fail=0
printf "%-5s %-7s %9s %8s %10s %8s %7s  %s\n" tier status instances parts collidable seconds threadErr log
for t in $TIERS; do
  s=$(date +%s.%N)
  "$LUAU" "$HERE/build_dump.luau" -a --tier "$t" "${GENARGS[@]}" "${EXTRA[@]}" 2>&1 | python3 "$HERE/split_dump.py" "$OUT/dump_tier$t.json" "$OUT/log_tier$t.txt"
  st=("${PIPESTATUS[@]}")
  e=$(date +%s.%N)
  secs=$(python3 -c "print(f'{$e-$s:.2f}')")
  if [ "${st[0]}" != "0" ] || [ "${st[1]}" != "0" ]; then
    printf "%-5s %-7s %9s %8s %10s %8s %7s  %s\n" "$t" FAILED - - - "$secs" - "$OUT/log_tier$t.txt"
    echo "---- log (tier $t) ----"; grep -v "^stacktrace:\|^\[C\] function error\|build_dump.luau:[0-9]*$\|^build failed$" "$OUT/log_tier$t.txt" | tail -n 25; echo "----"
    rm -f "$OUT/dump_tier$t.json"   # never leave a stale dump behind a failed build
    fail=1; continue
  fi
  python3 - "$OUT/dump_tier$t.json" "$t" "$secs" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))["meta"]
c = m["counts"]
print(f"{sys.argv[2]:<5} {'ok':<7} {c['instances']:>9} {c['parts']:>8} {c['collidable']:>10} {sys.argv[3]:>8} {m['mock']['threadErrors']:>7}  log_tier{sys.argv[2]}.txt")
if m["mock"]["stubs"]:
    print("      unimplemented API calls (stubs):", ", ".join(f"{k} x{v}" for k, v in m["mock"]["stubs"].items()))
PY
  grep -h "^\[warn\]\|^\[mock:" "$OUT/log_tier$t.txt" | sort | uniq -c | head -n 15 | sed 's/^/      /'
done

# Frame consistency: the same tier built at a translated and at a rotated plot CFrame must map back
# onto the building-local dump exactly (catches mixed local/world math in the generator and in the mock).
if [ -f "$OUT/dump_tier1.json" ] && [ $fail = 0 ]; then
  "$LUAU" "$HERE/build_dump.luau" -a --tier 1 --plot --quiet "${GENARGS[@]}" 2>&1 | python3 "$HERE/split_dump.py" "$OUT/dump_tier1_plot.json" "$OUT/log_tier1_plot.txt" \
    && python3 "$HERE/compare_dumps.py" "$OUT/dump_tier1.json" "$OUT/dump_tier1_plot.json" || fail=1
  "$LUAU" "$HERE/build_dump.luau" -a --tier 1 --cf "-37.5,11,90,37" --quiet "${GENARGS[@]}" 2>&1 | python3 "$HERE/split_dump.py" "$OUT/dump_tier1_rot.json" "$OUT/log_tier1_rot.txt" \
    && python3 "$HERE/compare_dumps.py" "$OUT/dump_tier1.json" "$OUT/dump_tier1_rot.json" || fail=1
fi

# Plan tier 0 (garage stage, only when requested in TIERS): the same frame-consistency check.
case " $TIERS " in *" 0 "*)
  if [ -f "$OUT/dump_tier0.json" ] && [ $fail = 0 ]; then
    "$LUAU" "$HERE/build_dump.luau" -a --tier 0 --plot --quiet "${GENARGS[@]}" 2>&1 | python3 "$HERE/split_dump.py" "$OUT/dump_tier0_plot.json" "$OUT/log_tier0_plot.txt" \
      && python3 "$HERE/compare_dumps.py" "$OUT/dump_tier0.json" "$OUT/dump_tier0_plot.json" || fail=1
    "$LUAU" "$HERE/build_dump.luau" -a --tier 0 --cf "-37.5,11,90,37" --quiet "${GENARGS[@]}" 2>&1 | python3 "$HERE/split_dump.py" "$OUT/dump_tier0_rot.json" "$OUT/log_tier0_rot.txt" \
      && python3 "$HERE/compare_dumps.py" "$OUT/dump_tier0.json" "$OUT/dump_tier0_rot.json" || fail=1
  fi ;;
esac

if [ $DO_CHECK = 1 ]; then
  for t in $TIERS; do
    [ -f "$OUT/dump_tier$t.json" ] || continue
    python3 "$HERE/check_geometry.py" "$OUT/dump_tier$t.json" --img-prefix "$OUT/walk_tier$t" > "$OUT/check_tier$t.txt" 2>&1 || fail=1
    echo "== check tier $t (full report: $OUT/check_tier$t.txt)"; sed -n '/^== SUMMARY/,$p' "$OUT/check_tier$t.txt" | tail -n +2
  done
fi
if [ $DO_RENDER = 1 ]; then
  for t in $TIERS; do
    [ -f "$OUT/dump_tier$t.json" ] || continue
    python3 "$HERE/render.py" "$OUT/dump_tier$t.json" --prefix "$OUT/tier$t" | tail -n 1 || fail=1
  done
fi
if [ $DO_BEFORE = 1 ]; then
  for t in $TIERS; do
    for f in "$OUT"/tier${t}_*.png "$OUT"/walk_tier${t}_*.png "$OUT/dump_tier$t.json" "$OUT/check_tier$t.txt"; do
      [ -f "$f" ] && cp "$f" "$ROOT/out/before_$(basename "$f")"
    done
  done
  echo "copied before_* files into $ROOT/out"
fi
exit $fail
