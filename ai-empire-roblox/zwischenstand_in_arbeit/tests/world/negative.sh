#!/usr/bin/env bash
# Negative checks for the world package: the tests must FAIL against the pre-change files (tests/world/orig)
# and against deliberate mutations. Private trees under agents/world/neg_* (never work/src).
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
SVC=ServerScriptService/Server/Services
mk() { # name; then: file sed-expression  OR  "orig" file...
  local name="$1"; shift; local tree="agents/world/neg_$name"
  rm -rf "$tree"; cp -r work/src "$tree"
  if [ "$1" = "orig" ]; then shift; for f in "$@"; do cp "tests/world/orig/$(basename "$f")" "$tree/$f"; done
  else sed -i "$2" "$tree/$1"; grep -q "NEGMARK" "$tree/$1" || { echo "mutation $name did not apply"; exit 1; }; fi
  python3 harness/make_manifest.py --src "$tree" --gen "harness/.gen_world_neg_$name" >/dev/null
}
run() { tools/luau "tests/world/$1.luau" -a ".gen_world_neg_$2" 2>&1 | grep -E "^FAIL|^ERROR|passed" | head -${3:-5}; }
mk vehicle orig $SVC/VehicleService.module.luau
echo "--- original VehicleService (expect FAILs: downtown/airport reset, limo, rebuild):"; run test_vehicle vehicle 30
mk plot orig $SVC/PlotService.module.luau
echo "--- original PlotService (expect ERROR: no away check hook):"; run test_travel plot 3
mk noaway $SVC/PlotService.module.luau 's/local away=awayCheck;if away and away(player) then return end/-- NEGMARK away check removed/'
echo "--- mutation: sendHome ignores the travel state (expect 'rebuild did NOT pull' FAIL):"; run test_travel noaway 3
mk campus orig $SVC/CampusService.module.luau
echo "--- original CampusService (expect corridor/support/directory FAILs):"; run test_build campus 5
mk offroad ReplicatedStorage/Shared/Config/CityPlan.module.luau 's/w_1500=v(-340,1500)/w_1500=v(-300,1500)--[[NEGMARK]]/'
echo "--- mutation: a graph node off the street (expect 'on asphalt' FAIL):"; run test_cityplan offroad 3
mk nohold $SVC/CityService.module.luau 's/	root.Anchored=true -- held until/	-- NEGMARK no hold/'
echo "--- mutation: character not held during the flight (expect 'held' FAIL):"; run test_travel nohold 3
# geometry negatives: a blocked office entrance and a missing corridor support must be caught by the dump checks
mk blocked $SVC/CityBuilder.module.luau 's/local dw=if b.interior=="hotel" then 14 else City.OFFICE.doorWidth/local dw=if b.interior=="hotel" then 14 else 0 -- NEGMARK door closed/'
agents/world/world_dump.sh --src agents/world/neg_blocked --out out/world_neg >/dev/null 2>&1
echo "--- mutation: office entrances closed (expect UNREACHABLE offices):"; python3 agents/world/entrances.py out/world_neg/world_dump.json | grep -E "UNREACHABLE|ENTRANCES" | head -4
mk nosupport $SVC/CampusService.module.luau 's/		block(folder,"LinkSupport",r,BASE,GROUND,stone)/		-- NEGMARK no support/'
agents/world/world_dump.sh --src agents/world/neg_nosupport --out out/world_neg 2>&1 | grep -E "hole check district|WORLD CHECK"
rm -rf agents/world/neg_* harness/.gen_world_neg_* out/world_neg
