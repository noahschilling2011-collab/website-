#!/usr/bin/env bash
# Package "buildings" tests: tier-0 runtime (garage stage), build contracts tiers 0-4 (garage, guest house),
# plan/layout invariants (tests/layout_test.luau), the admin "tier0" command, the geometry of tier 0 and the
# guest house (frame consistency, holes, reachability, budgets, job-hop corridors; private dumps in
# tests/buildings/out) and the negative checks against the original files.
# Usage: tests/buildings/run.sh            (from anywhere; writes only into tests/buildings/gen*)
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
L=tools/luau
python3 tests/buildings/mkharness.py >/dev/null || exit 1
python3 tests/gen_layout_test.py >/dev/null 2>&1
rc=0
run() { local name="$1"; shift; local out; out=$("$@" 2>&1); local r=$?; [ $r -ne 0 ] && rc=1; printf "%-22s rc=%s  %s\n" "$name" "$r" "$(echo "$out" | grep -E "passed|failed" | tail -n 1)"; }
neg() { local name="$1"; shift; local out; out=$("$@" 2>&1); local r=$?; local verdict="ok (fails on the original files)"; [ $r -eq 0 ] && { verdict="NOT DETECTED"; rc=1; }; printf "%-22s %s  %s\n" "$name" "$verdict" "$(echo "$out" | grep -E "passed|failed" | tail -n 1)"; }
run buildings_layout     $L tests/layout_test.luau
run buildings_tier0      $L tests/buildings/test_tier0.luau
run buildings_tier0_req  $L tests/buildings/test_tier0.luau -a req
run buildings_build      $L tests/buildings/test_build.luau -a all
run buildings_admin      $L tests/buildings/test_admin.luau
run buildings_geometry   python3 tests/buildings/test_geometry.py
neg buildings_tier0_neg  $L tests/buildings/test_tier0.luau -a neg
neg buildings_build_neg  $L tests/buildings/test_build.luau -a neg
exit $rc
