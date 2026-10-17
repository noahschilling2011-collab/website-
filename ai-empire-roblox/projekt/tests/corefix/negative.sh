#!/usr/bin/env bash
# corefix package: proves the corefix checks FAIL when a fix is reverted. Each mutation (the pre-fix code) is
# applied to a private copy of work/src (agents/corefix/neg/src); the named suite must report failures.
# Usage: tests/corefix/negative.sh
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
NEG="$ROOT/agents/corefix/neg"
detected=0; total=0
mutate() { # name suite file find replace [find2 replace2]
  local name="$1" suite="$2" file="$3"
  rm -rf "$NEG/src"; mkdir -p "$NEG"; cp -r work/src "$NEG/src"
  python3 - "$NEG/src/$file" "${@:4}" <<'PYEOF' || { echo "MUTATION ANCHOR MISSING: $name"; total=$((total+1)); return; }
import sys
p, pairs = sys.argv[1], sys.argv[2:]
s = open(p).read()
for i in range(0, len(pairs), 2):
    a, b = pairs[i], pairs[i + 1]
    if s.count(a) != 1:
        sys.exit(1)
    s = s.replace(a, b)
open(p, "w").write(s)
PYEOF
  python3 harness/make_manifest.py --src "$NEG/src" --gen harness/.gen_corefixneg >/dev/null
  local out
  case "$suite" in
    corefix|ui) out=$(cd tests/corefix && timeout 900 ../../tools/luau "test_$suite.luau" -a .gen_corefixneg 2>&1) ;;
    *) out=$(cd tests/econ && ../../tools/luau "test_$suite.luau" -a .gen_corefixneg 2>&1) ;;
  esac
  local line; line=$(echo "$out" | grep -E "passed, [0-9]+ failed" | tail -n 1)
  total=$((total+1))
  if echo "$line" | grep -q " 0 failed"; then echo "NOT DETECTED  $name  ($line)"; else detected=$((detected+1)); echo "detected      $name  ($line)"; fi
}
PS=ServerScriptService/Server/Services/PricingService.module.luau
OPS=ReplicatedStorage/Shared/CompanyOps.module.luau
ES=ServerScriptService/Server/Services/EmpireService.module.luau
EC=ServerScriptService/Server/Services/EconomyService.module.luau
SS=ServerScriptService/Server/Services/SessionService.module.luau
MS=ServerScriptService/Server/Services/MarketService.module.luau
TP=ServerScriptService/Server/Lib/Template.module.luau
CA=StarterPlayer/StarterPlayerScripts/Client/UI/Apps/CampusApp.module.luau
mutate "auto-price first cycle 15-44 s (econ build)" corefix "$PS" 'local first = math.clamp(tonumber((P :: any).autoFirst) or 150, 0, P.autoPeriod)' 'local first = 15 + math.abs(math.floor(session.userId)) % 30'
mutate "trip cash checked against stale cash" corefix "$OPS" 'if data.money - committed < cost + Ops.CASH_MARGIN then return false end' 'if data.money < cost + Ops.CASH_MARGIN then return false end'
mutate "rack fault takes the whole GPU" corefix "$OPS" 'throughput = math.min(F.units, r.throughput)' 'throughput = r.throughput'
mutate "news outside step not stamped per company" corefix "$OPS" 'Ops.news(d, text, Ops.stamp(e, clock or workspace:GetServerTimeNow()))' 'Ops.news(d, text, "day 40 10:00")'
mutate "Save mode news without debounce" corefix "$ES" 'Empire.SAVE_NEWS_HOLD = 20' 'Empire.SAVE_NEWS_HOLD = 0'
mutate "autoPrice coerces a non-boolean on" corefix "$ES" 'models.setAutoPrice(session, modelId, p.on)' 'models.setAutoPrice(session, modelId, p.on == true)'
mutate "uncategorised spend not booked" corefix "$EC" 'book(session, "o", category or "other", amount)' 'if category then book(session, "o", category, amount) end'
mutate "Training Lead paid without apprentices" corefix "$OPS" 'if stageIdx >= Ops.TRAINING_LEAD.from and Ops.apprenticeCount(e) > 0 then' 'if stageIdx >= Ops.TRAINING_LEAD.from then'
mutate "apprentice hire path removed" corefix "$ES" 'local apprentice=payload.apprentice==true' 'local apprentice=false'
mutate "site board label not written" corefix "$ES" 'if body then (body :: TextLabel).Text = goal end' ''
mutate "replicated accounts not compacted" corefix "$SS" '		out.accounts = accounts' ''
mutate "offer vage per second again" corefix "$MS" 'Market.OFFER_AGE_STEP = 30' 'Market.OFFER_AGE_STEP = 1'
mutate "news clipped by bytes (UTF-8 split)" corefix "$OPS" 'table.insert(d.news, 1, Ops.clip(line, Ops.NEWS_CHARS))' 'table.insert(d.news, 1, string.sub(line, 1, Ops.NEWS_CHARS))'
mutate "lease customers kept on load" corefix "$TP" '	e.customers = {}
	e.businessRevenue = 0
	-- P&L ledger' '	-- P&L ledger' '		e.customers = {}
		e.businessRevenue = 0
		-- one live' '		-- one live'
mutate "migration keeps clones / extra lines" migration "$TP" '		Template.normaliseLines(d)' ''
mutate "vage not LAZY" net "$SS" 'marketplace = { offers = { ["*"] = { users = true, vage = true } } },' 'marketplace = { offers = { ["*"] = { users = true } } },'
mutate "replicated ledger all 7 days" net "$SS" 'local LEDGER_SHOWN = CompanyOps.LEDGER_SHOWN' 'local LEDGER_SHOWN = 7'
mutate "garage directory lists R and B1" ui "$CA" '	if tier<1 then return Plan.floorTitle(tier,0) end -- the Garage Lab: one level, no roof terrace, no B1' ''
mutate "garage shows HQ cards" ui "$CA" 'for _,card in {pavilion,services,top,garage,wellness} do card.Visible=hq end' ''
rm -rf "$NEG/src" harness/.gen_corefixneg
echo "corefix negative: $detected of $total mutations detected"
[ "$detected" -eq "$total" ]
