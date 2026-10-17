#!/usr/bin/env bash
# Negative checks for the shop package: the same tests must FAIL against the lead's original ShopService
# stub and against deliberate mutations of ShopService / Template / DebugService / ShopApp.
# Private trees under agents/shop/neg_* (never work/src). Prints one line per case and "negative: N/M detected".
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
SVC=ServerScriptService/Server/Services
LIB=ServerScriptService/Server/Lib
APP=StarterPlayer/StarterPlayerScripts/Client/UI/Apps
SHOPUI=StarterPlayer/StarterPlayerScripts/Client/UI/Shop # shop package (round 3): purchase hints moved to ShopCore
total=0; detected=0
# mutate NAME TEST FILE OLD NEW : copy work/src, replace OLD by NEW in FILE (must match), run TEST, expect failures
mutate() {
  local name="$1" test="$2" file="$3" old="$4" new="$5"; local tree="agents/shop/neg_$name"
  rm -rf "$tree"; cp -r work/src "$tree"
  if [ "$file" = "STUB" ]; then
    printf -- '--!strict\nlocal ShopService = {}\nfunction ShopService.init() end\nreturn ShopService\n' > "$tree/$SVC/ShopService.module.luau"
  else
    python3 - "$tree/$file" "$old" "$new" <<'EOF' || { echo "mutation $name did not apply"; exit 1; }
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if old not in s: sys.exit(1)
open(p, "w").write(s.replace(old, new, 1))
EOF
  fi
  python3 harness/make_manifest.py --src "$tree" --gen "harness/.gen_shop_neg_$name" >/dev/null 2>&1
  local out; out=$(cd tests/shop && ../../tools/luau "$test.luau" -a ".gen_shop_neg_$name" 2>&1)
  local summary; summary=$(echo "$out" | grep -E "tests: [0-9]+ passed" | tail -n 1)
  local first; first=$(echo "$out" | grep -E "^FAIL" | head -n 1)
  total=$((total+1))
  if echo "$summary" | grep -qE ", [1-9][0-9]* failed"; then detected=$((detected+1)); echo "DETECTED  $name: $summary | $first"
  else echo "MISSED    $name: ${summary:-no summary} "; fi
  rm -rf "$tree" "harness/.gen_shop_neg_$name"
}
mutate stub          test_shop STUB "" ""
mutate norecord      test_shop "$SVC/ShopService.module.luau" "if shop.receipts[purchaseId] == nil then" "if true then"
mutate ackfailed     test_shop "$SVC/ShopService.module.luau" "if Shop.saveNow(session) then" "if Shop.saveNow(session) or true then"
mutate nowait        test_shop "$SVC/ShopService.module.luau" "local session = waitForSession(player)" "local session = deps.getSession(player)"
mutate noslot        test_shop "$SVC/ShopService.module.luau" "while session.saving and waited < SAVE_WAIT_SECONDS do" "while false do"
mutate notrim        test_shop "$SVC/ShopService.module.luau" "		trimReceipts(shop)
" ""
mutate nocache       test_shop "$SVC/ShopService.module.luau" "setPass(session, def.key, shopOf(session).passes[def.key] == true, false) -- fallback cache" "-- no fallback cache"
mutate nobought      test_shop "$SVC/ShopService.module.luau" "if owns == true or not (bought and bought[def.key]) then" "if true then"
mutate noclean       test_shop "$LIB/Template.module.luau" "	raw.shop = Template.cleanShop(raw.shop)" "	-- no cleaner"
mutate resetshop     test_shop "$SVC/DebugService.module.luau" "			(session.data :: any).shop = shop" "			-- shop dropped"
mutate resetlive     test_shop "$SVC/DebugService.module.luau" "		local live = session.live
" "		session.live = { users = 0, revenue = 0, cost = 0, perModel = {}, npcUsers = {} } :: any
		local live = session.live
"
mutate clientgrant   test_client "$SHOPUI/ShopCore.module.luau" "				Toast.show(\"info\", \"Purchase received. Adding it to your company...\")" "				Action.call(\"ShopAction\", { action = \"redeem\", key = \"party\" }, true)"
mutate clientprice   test_client "$APP/ShopApp.module.luau" "	return ShopCore.priceOf(item.kind, def.id) ~= nil" "	return true"
mutate clientsoon    test_client "$APP/ShopApp.module.luau" "soon.Visible = not listed and not studio and not anyVoucher" "soon.Visible = false"
echo "negative: $detected/$total detected"
