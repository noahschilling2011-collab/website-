#!/usr/bin/env bash
# Airport package: City Airport suite (tests/airport/test_airport.luau) + the world suites and world checks.
# Usage: tests/airport/run.sh [--src DIR] [--quick]   (default work/src; --quick = airport suite only)
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
SRC=work/src; QUICK=0
while [ $# -gt 0 ]; do case "$1" in --src) SRC="$2"; shift;; --quick) QUICK=1;; esac; shift; done
python3 harness/make_manifest.py --src "$SRC" --gen harness/.gen_airport >/dev/null || exit 1
rc=0
tools/luau tests/airport/test_airport.luau -a .gen_airport 2>&1 | grep -E "^FAIL|^ERROR|passed|airport parts|walk grid" ; [ ${PIPESTATUS[0]} -eq 0 ] || rc=1
[ $QUICK = 1 ] && exit $rc
bash tests/world/run.sh --src "$SRC" || rc=1
exit $rc
