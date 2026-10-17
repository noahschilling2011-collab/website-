#!/usr/bin/env bash
# Negative checks of the shop package (round 3): every mutation of the shipped code must make a tests/shop2 suite FAIL.
# Private trees under agents/shop2/neg_* (never work/src). Prints one line per case and "shop2_negative: N/M detected".
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
SVC=ServerScriptService/Server/Services
LIB=ServerScriptService/Server/Lib
SH=ReplicatedStorage/Shared
UI=StarterPlayer/StarterPlayerScripts/Client/UI
total=0; detected=0
# mutate NAME SUITE FILE OLD NEW : copy work/src, replace OLD by NEW in FILE (must match once), run SUITE, expect failures
mutate() {
  if [ -n "$NEG_ONLY" ] && [[ ",$NEG_ONLY," != *",$1,"* ]]; then return; fi
  local name="$1" suite="$2" file="$3" old="$4" new="$5"; local tree="agents/shop2/neg_$name"
  rm -rf "$tree"; cp -r work/src "$tree"
  python3 - "$tree/$file" "$old" "$new" <<'PY' || { echo "MUTATION $name DID NOT APPLY"; total=$((total+1)); rm -rf "$tree"; return; }
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if s.count(old) != 1: sys.exit(1)
open(p, "w").write(s.replace(old, new, 1))
PY
  python3 harness/make_manifest.py --src "$tree" --gen "harness/.gen_shop2_neg_$name" >/dev/null 2>&1
  local out; out=$(cd tests/shop2 && timeout 300 ../../tools/luau "$suite.luau" -a ".gen_shop2_neg_$name" 2>&1)
  local summary; summary=$(echo "$out" | grep -E "^shop2_[a-z]+: [0-9]+ passed" | tail -n 1)
  local first; first=$(echo "$out" | grep -E "^FAIL" | head -n 1)
  total=$((total+1))
  if echo "$summary" | grep -qE ", [1-9][0-9]* failed"; then detected=$((detected+1)); echo "DETECTED  $name: $summary | $first"
  else echo "MISSED    $name: ${summary:-no summary}"; fi
  rm -rf "$tree" "harness/.gen_shop2_neg_$name"
}
python3 tests/shop2/spec_texts.py design/SHOP_SPEC.md work/src tests/shop2/.spec_texts.luau >/dev/null
# server (test_server)
mutate eureka_free      test_server "$SVC/EmpireService.module.luau" '	if not Economy.spend(session, def.cost, "research") then return false, "NO_MONEY" end' '	-- free'
mutate eureka_no_rp     test_server "$SVC/EmpireService.module.luau" '		e.points = math.min(100000, e.points + (if def then def.points else 0))' '		-- points kept by the server'
mutate lab_free         test_server "$SVC/EmpireService.module.luau" '		if not Economy.spend(session, cost, "lab") then return false, "NO_MONEY" end' '		-- free'
mutate eureka_unregistered test_server "$SVC/EmpireService.module.luau" '	if typeof((ShopService :: any).setRedeemHandler) == "function" then' '	if false then'
mutate no_daily_cap     test_server "$SVC/ShopService.module.luau" '	if cap and (tonumber(daily.used[key]) or 0) >= cap then' '	if false then'
mutate no_boost_full    test_server "$SVC/ShopService.module.luau" '	if left + def.seconds > ShopConfig.BOOST_MAX_LEFT then' '	if false then'
mutate boost_replaces   test_server "$SVC/ShopService.module.luau" '	shopOf(session).boosts[key] = now + left + def.seconds' '	shopOf(session).boosts[key] = now + def.seconds'
mutate voucher_on_error test_server "$SVC/ShopService.module.luau" '	if done ~= true then
		return { ok = false, err = if typeof(err) == "string" then err else "NOT_AVAILABLE" }' '	if done ~= true then
		shopOf(session).vouchers[key] = math.max(0, (tonumber(shopOf(session).vouchers[key]) or 0) - 1)
		return { ok = false, err = if typeof(err) == "string" then err else "NOT_AVAILABLE" }'
mutate no_pack_record   test_server "$SVC/ShopService.module.luau" '		shop.packs[def.key] = office' '		-- not recorded'
mutate phase3_sellable  test_server "$SVC/ShopService.module.luau" '		if def.ready == false then
			out[def.key] = false -- its feature' '		if false then
			out[def.key] = false -- its feature'
mutate investor_times   test_server "$SVC/ShopService.module.luau" '	return factor + ShopMath.revenueBonus(session.data)' '	return factor * (1 + ShopMath.revenueBonus(session.data))'
mutate kit_free_rebrand test_server "$SVC/CompanyService.module.luau" '	if not kitAllowed(session, colorId, logo) then
		return { ok = false, err = "PASS_NEEDED" }
	end
	local now = os.clock()' '	local now = os.clock()'
mutate no_cooldown      test_server "$SVC/CompanyService.module.luau" '	if last and now - last < CompanyService.REBRAND_COOLDOWN then' '	if false then'
mutate headhunt_random  test_server "$SVC/RecruitingService.module.luau" '  if Recruiting.traits(s.userId,a.serial).k==4 then' '  if true then'
mutate clean_nan_boost  test_server "$LIB/Template.module.luau" '			if finite(v) and v > 0 then
				shop.boosts[key] = v' '			if v ~= nil then
				shop.boosts[key] = v'
mutate no_floor         test_server "$SH/ShopMath.module.luau" '	return math.min(rate * f, workTotal / ModelConfig.TRAINING.minSeconds)' '	return rate * f'
# pure (test_math)
mutate no_min_saving    test_math "$SH/ShopMath.module.luau" '	if forBuy and out.seconds < ShopConfig.EUREKA_MIN_SAVING then' '	if false then'
mutate no_rp_short      test_math "$SH/ShopMath.module.luau" '		if forBuy and have >= pts then' '		if false then'
mutate gate_in_guide    test_math "$SH/ShopMath.module.luau" '	if typeof(data) ~= "table" or not data.company or TutorialMath.active(data) then' '	if typeof(data) ~= "table" or not data.company then'
mutate no_error_pause   test_math "$SH/ShopMath.module.luau" '	if ui.lastErrorAt ~= nil and ui.clock ~= nil and ui.clock - ui.lastErrorAt < 10 then' '	if false then'
mutate studio_any_lock  test_math "$SH/ShopMath.module.luau" '	if after and after.lock ~= nil then' '	if false then'
mutate studio_training  test_math "$SH/ShopMath.module.luau" '	if data.training ~= nil then' '	if false then'
mutate mutates_snapshot test_math "$SH/ShopMath.module.luau" '	out.empire.research = table.clone(data.empire.research or {})' '	out.empire.research = data.empire.research'
mutate text_changed     test_math "$SH/Config/ShopConfig.module.luau" 'Every Eureka button in the game shows the time it saves.' 'Best value: skip all the waiting!'
# client (test_client)
mutate auto_redeem      test_client "$UI/Shop/ShopCore.module.luau" '			if not ShopCore.use(voucher, p.target, o) then' '			ShopCore.redeem(voucher, p.target)
			if false then'
mutate no_pending_limit test_client "$UI/Shop/ShopCore.module.luau" 'os.clock() - p.at < ShopCore.PENDING_SECONDS then' 'true then'
mutate no_lazy_price    test_client "$UI/Shop/ShopCore.module.luau" '	if def and def.id > 0 and ShopCore.priceOf("product", def.id) == nil and ShopMath.gateOpen(snapshot.data) then' '	if false then'
mutate sheet_no_redeem  test_client "$UI/Shop/ShopCore.module.luau" '		local ok, result = Action.call("ShopAction", payload, true)' '		local ok, result = true, ({} :: any)'
# geometry (T18, tests/shop2/sizes.py): render one phone dump from the mutated tree, the size suite must FAIL
mutate_geo() { # NAME FILE OLD NEW SCENE-OPTIONS...
  if [ -n "$NEG_ONLY" ] && [[ ",$NEG_ONLY," != *",$1,"* ]]; then return; fi
  local name="$1" file="$2" old="$3" new="$4"; shift 4; local tree="agents/shop2/neg_$name"
  rm -rf "$tree"; cp -r work/src "$tree"
  python3 - "$tree/$file" "$old" "$new" <<'PY' || { echo "MUTATION $name DID NOT APPLY"; total=$((total+1)); rm -rf "$tree"; return; }
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if s.count(old) != 1: sys.exit(1)
open(p, "w").write(s.replace(old, new, 1))
PY
  python3 harness/make_manifest.py --src "$tree" --gen "harness/.gen_shop2_neg_$name" >/dev/null 2>&1
  local dump="agents/shop2/neg_$name.phone.dump"
  python3 tools/guiprev/guiprev.py --scene tests/shop2/scene_shop.luau --gen "harness/.gen_shop2_neg_$name" --no-manifest --passes 3 \
    --state mid --viewport phone --dpr 1 --out "agents/shop2/neg_$name.png" --save-dump "$dump" touch=1 "$@" >/dev/null 2>&1
  local out; out=$(python3 tests/shop2/sizes.py "$dump" 2>&1)
  total=$((total+1))
  if echo "$out" | grep -qE "^shop2_sizes: [0-9]+ passed, [1-9][0-9]* failed"; then detected=$((detected+1)); echo "DETECTED  $name: $(echo "$out" | grep -m1 ^FAIL)"
  else echo "MISSED    $name: $(echo "$out" | tail -n 1)"; fi
  rm -rf "$tree" "harness/.gen_shop2_neg_$name" "$dump" "agents/shop2/neg_$name.png"
}
mutate_geo changelook_narrow "$UI/Apps/ShopApp.module.luau" 'local pw = if long then 220 else 170' 'local pw = 170' catalog=1 page=shop.style owned=identityKit
echo "shop2_negative: $detected/$total detected"
[ "$detected" = "$total" ]
