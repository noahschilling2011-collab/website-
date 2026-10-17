#!/usr/bin/env bash
# Talk package: all headless suites (Dialogue, TalkService, TalkController/TalkPanel client smoke test).
# Usage: tests/talk/run.sh [--samples]   (--samples prints one sample conversation per job)
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
python3 harness/make_manifest.py --src work/src --gen harness/.gen_talk >/dev/null || exit 1
Q="--quiet"; [ "${1:-}" = "--samples" ] && Q=""
rc=0
tools/luau tests/talk/test_dialogue.luau -a .gen_talk $Q 2>&1 | grep -vE "^stacktrace|^\[C\]|^\./" ; [ ${PIPESTATUS[0]} -eq 0 ] || rc=1
tools/luau tests/talk/test_talk.luau -a .gen_talk 2>&1 | grep -E "FAIL|ERROR|passed" ; [ ${PIPESTATUS[0]} -eq 0 ] || rc=1
tools/luau tests/talk/test_client.luau -a .gen_talk 2>&1 | grep -E "FAIL|ERROR|passed" ; [ ${PIPESTATUS[0]} -eq 0 ] || rc=1
for t in 1 2 4; do tools/luau tests/talk/test_real.luau -a .gen_talk $t 2>&1 | grep -E "FAIL|ERROR|passed" ; [ ${PIPESTATUS[0]} -eq 0 ] || rc=1; done
exit $rc
