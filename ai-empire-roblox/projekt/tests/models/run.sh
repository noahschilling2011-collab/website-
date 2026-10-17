#!/usr/bin/env bash
# Models package suites. Usage: tests/models/run.sh [plain|overlay]
#   plain (default): work/src exactly as it is
#   overlay:         additionally overlays the econ CORE_SPEC patches in memory where work/src still lacks them
#                    (load.luau prints how many; only useful while the econ package is landing)
# Suites: test_models (server: lines, successor, ageing, refinement, Lab level, MODEL_LIMIT, pricing worker)
#         test_ui x {empty, rich, full} (client: Lab + Market apps against the real server handlers)
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MODE="${1:-plain}"
python3 "$ROOT/harness/make_manifest.py" --src "$ROOT/work/src" --gen "$ROOT/harness/.gen_models" >/dev/null || exit 1
cd "$ROOT/tests/models" || exit 1
rc=0
mkdir -p "$ROOT/out/models"; OUT="$ROOT/out/models/.run_$$.txt"
timeout 900 ../../tools/luau test_models.luau -a .gen_models "$MODE" 2>&1 | tee "$OUT" || rc=1
grep -q "models: [0-9]* passed, 0 failed" "$OUT" || rc=1
for state in empty rich full; do
  timeout 600 ../../tools/luau test_ui.luau -a .gen_models "$state" 2>&1 | tee "$OUT" || rc=1
  grep -q "models_ui_$state: [0-9]* passed, 0 failed" "$OUT" || rc=1
done
rm -f "$OUT"
exit $rc
