#!/usr/bin/env bash
# Negative checks for the net package: the same tests against the PRE-CHANGE files (tests/net/orig)
# must fail. Builds private trees under agents/net/neg_* (never touches work/src).
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
mk() { # name, then pairs "relative/target/path:origfile"
  local name="$1"; shift; local tree="agents/net/neg_$name"
  rm -rf "$tree"; cp -r work/src "$tree"
  for pair in "$@"; do cp "tests/net/orig/${pair#*:}" "$tree/${pair%%:*}"; done
  python3 harness/make_manifest.py --src "$tree" --gen "harness/.gen_net_neg_$name" >/dev/null
}
mk market "ServerScriptService/Server/Services/MarketService.module.luau:MarketService.module.luau"
echo "--- original MarketService (expect live-field FAILs):"
tools/luau tests/net/test_net.luau -a ".gen_net_neg_market" 2>&1 | grep -E "^FAIL  market|net tests:"
mk session "ServerScriptService/Server/Services/SessionService.module.luau:SessionService.module.luau" \
  "StarterPlayer/StarterPlayerScripts/Client/Controllers/StateController.module.luau:StateController.module.luau" \
  "ReplicatedStorage/Shared/Config/GameConfig.module.luau:GameConfig.module.luau"
echo "--- original SessionService/StateController/GameConfig (expect bandwidth FAIL):"
tools/luau tests/net/test_e2e.luau -a ".gen_net_neg_session" 2>&1 | grep -E "^FAIL|^ERROR|e2e tests:" | head -8
