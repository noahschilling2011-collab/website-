#!/usr/bin/env bash
# verify2b: mutations the release e2e (tests/verify2b/test_trip_e2e.luau) must catch. Each one is a copy of work/src
# with one defect; the e2e must report failures for every one of them.
#   unpatched     DriverService + JetService without the itinerary hooks (design/requests/itinerary.md #1 / #2)
#   itin_pays     the itinerary's jet flight passes pay = true (JetService charges a fuel leg)
#   money_direct  ItineraryService takes $1 from the cash on Go, bypassing EconomyService
#   folder_leak   ItineraryService.finish keeps the published itinerary folder
#   rig_leak      ItineraryController (client) never destroys the companions' rigs it drops
# Usage: tests/verify2b/negative.sh
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
NEG=agents/verify2b/neg
SVC=ServerScriptService/Server/Services
rm -rf "$NEG"; mkdir -p "$NEG"
mutate() { # name file python-replacement(old, new)
  local name="$1" file="$2" old="$3" new="$4"
  rm -rf "$NEG/$name"; cp -r work/src "$NEG/$name"
  python3 - "$NEG/$name/$file" "$old" "$new" <<'PY' || return 1
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if old not in s: sys.exit("anchor not found in " + p)
open(p, "w").write(s.replace(old, new, 1))
PY
}
build_unpatched() {
  rm -rf "$NEG/unpatched"; cp -r work/src "$NEG/unpatched"
  cp agents/verify2b/backup/DriverService.before_verify2b.luau "$NEG/unpatched/$SVC/DriverService.module.luau"
  cp agents/verify2b/backup/JetService.before_verify2b.luau "$NEG/unpatched/$SVC/JetService.module.luau"
}
build_unpatched
mutate itin_pays "$SVC/ItineraryService.module.luau" 'pcall(J.fly, it.player, { to = to, companions' 'pcall(J.fly, it.player, { pay = true, to = to, companions'
mutate money_direct "$SVC/ItineraryService.module.luau" 'local function go(rec: Rec, key: string?, how: string): { [string]: any }
	local s = rec.s' 'local function go(rec: Rec, key: string?, how: string): { [string]: any }
	local s = rec.s
	if s and s.data then s.data.money -= 1 end'
mutate folder_leak "$SVC/ItineraryService.module.luau" '	if f then f:Destroy() end' '	local _ = f'
CTL=StarterPlayer/StarterPlayerScripts/Client/Controllers
mutate rig_leak "$CTL/ItineraryController.module.luau" '	for _, rg in g.rigs do rg.model:Destroy() end
	groups[uid] = nil' '	groups[uid] = nil'
rc=0; caught=0; total=0
for name in unpatched itin_pays money_direct folder_leak rig_leak; do
  total=$((total + 1))
  python3 harness/make_manifest.py --src "$NEG/$name" --gen "harness/.gen_v2b_neg_$name" >/dev/null || { echo "$name: manifest failed"; rc=1; continue; }
  out=$(cd tests/verify2b && timeout 900 ../../tools/luau test_trip_e2e.luau -a ".gen_v2b_neg_$name" 2>&1)
  line=$(echo "$out" | grep -E "trip_e2e: [0-9]+ passed" | tail -n 1)
  first=$(echo "$out" | grep -E "^FAIL|^CRASH" | head -n 2 | tr '\n' ' ')
  if echo "$line" | grep -q " 0 failed"; then echo "MISSED  $name  ($line)"; rc=1
  else caught=$((caught + 1)); echo "caught  $name  ($line)  $first"; fi
  rm -rf "harness/.gen_v2b_neg_$name"
done
echo "verify2b negative: $caught/$total mutations caught"
exit $rc
