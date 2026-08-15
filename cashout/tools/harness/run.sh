#!/usr/bin/env bash
# Faehrt beide Kopflaeufe. Braucht python3 und die Standalone-Luau-CLI.
#   tools/harness/run.sh [pfad/zu/luau]
set -euo pipefail

LUAU="${1:-luau}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 "$HERE/build.py" round.lua harness_round.lua
"$LUAU" "$HERE/harness_round.lua"

python3 "$HERE/build.py" edgecases.lua harness_edgecases.lua
"$LUAU" "$HERE/harness_edgecases.lua"

python3 "$HERE/build.py" raid.lua harness_raid.lua
"$LUAU" "$HERE/harness_raid.lua"

python3 "$HERE/build.py" sim.lua harness_sim.lua
"$LUAU" "$HERE/harness_sim.lua"
