#!/usr/bin/env bash
# econ package: proves the econ suites FAIL when the economy is broken. Each mutation is applied to a private
# copy of work/src (agents/econ/neg/src), the matching suite must report failures. Prints one line each.
# Usage: tests/econ/negative.sh
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
NEG="$ROOT/agents/econ/neg"
detected=0; total=0
mutate() { # name suite file find replace [find2 replace2]
  local name="$1" suite="$2" file="$3"
  rm -rf "$NEG/src"; mkdir -p "$NEG"; cp -r work/src "$NEG/src"
  python3 - "$NEG/src/$file" "${@:4}" <<'EOF' || { echo "MUTATION ANCHOR MISSING: $name"; return; }
import sys
p, pairs = sys.argv[1], sys.argv[2:]
s = open(p).read()
for i in range(0, len(pairs), 2):
    a, b = pairs[i], pairs[i + 1]
    if s.count(a) != 1:
        sys.exit(1)
    s = s.replace(a, b)
open(p, "w").write(s)
EOF
  python3 harness/make_manifest.py --src "$NEG/src" --gen harness/.gen_econneg >/dev/null
  local out; out=$(cd tests/econ && ../../tools/luau "test_$suite.luau" -a .gen_econneg 2>&1)
  local line; line=$(echo "$out" | grep -E "passed, [0-9]+ failed" | tail -n 1)
  total=$((total+1))
  if echo "$line" | grep -q " 0 failed"; then echo "NOT DETECTED  $name  ($line)"; else detected=$((detected+1)); echo "detected      $name  ($line)"; fi
}
ES=ServerScriptService/Server/Services/EmpireService.module.luau
TP=ServerScriptService/Server/Lib/Template.module.luau
OPS=ReplicatedStorage/Shared/CompanyOps.module.luau
WM=ReplicatedStorage/Shared/WorkforceMath.module.luau
SS=ServerScriptService/Server/Services/SessionService.module.luau
EC=ServerScriptService/Server/Services/EconomyService.module.luau
mutate "garage gate removed" service "$ES" 'if e.office == 1 and (tonumber(e.contractsCompleted) or 0) < 1 then return {ok=false, err="FIRST_CLIENT"} end' ''
mutate "MIGRATIONS[5] without +1" migration "$TP" 'e.office = math.clamp(math.floor(tonumber(e.office) or 1) + 1, 2, 5)' 'e.office = math.clamp(math.floor(tonumber(e.office) or 1), 1, 5)'
mutate "old office clamp 1..4" migration "$TP" 'e.office = math.clamp(math.floor(tonumber(e.office) or 1),1,#EmpireConfig.OFFICES)' 'e.office = math.clamp(math.floor(tonumber(e.office) or 1),1,4)'
mutate "no scripted first-client trust" b2b "$OPS" 'Ops.FIRST_CLIENT_TRUST = 0.5' 'Ops.FIRST_CLIENT_TRUST = 0'
mutate "HR vacation collision cap off" ops "$OPS" 'local cap = math.max(1, math.ceil(0.10 * #seeds))' 'local cap = 99'
mutate "watched staff feed the economy again" ops "$WM" 'function Math.set(_empire: any,_counts: any?) end' 'local reports: any=setmetatable({},{__mode="k"}) function Math.set(_empire: any,_counts: any?) reports[_empire]=_counts end' ' return ops.output(empire,role)' ' local r=reports[empire] if r and r[role] then return r[role] end return ops.output(empire,role)'
mutate "trips ignore the cash margin" b2b "$OPS" 'if data.money - committed < cost + Ops.CASH_MARGIN then return false end' ''
mutate "replicated news not trimmed" net "$SS" 'if type(news) == "table" and #news > NEWS_SHOWN then' 'if false then'
mutate "ledger keeps 30 days" service "$EC" 'EconomyService.LEDGER_DAYS = CompanyOps.LEDGER_DAYS' 'EconomyService.LEDGER_DAYS = 30'
mutate "rack faults never repaired without IT" ops "$OPS" 'local rate = if Ops.itOnDuty(e, clock) then 1 / F.it else 1 / F.alone' 'local rate = if Ops.itOnDuty(e, clock) then 1 / F.it else 0'
mutate "unpaid leave still paid" ops "$OPS" 'local paid = n - (leave[role.id] or 0)' 'local paid = n'
rm -rf "$NEG/src" harness/.gen_econneg
echo "econ negative: $detected of $total mutations detected"
[ "$detected" -eq "$total" ]
