#!/usr/bin/env bash
# Menu package: proves the menu checks FAIL when a rule is broken. Each mutation is applied to a private copy of
# work/src (agents/menu/neg/src); the named suite (server | guide | menu | sizes) must then report failures.
# Usage: tests/menu/negative.sh   (NEG_ONLY=<substring> runs only the matching mutations)
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
NEG="$ROOT/agents/menu/neg"
detected=0; total=0
mutate() { # name suite file find replace [find replace ...]
  local name="$1" suite="$2" file="$3"
  if [ -n "${NEG_ONLY:-}" ] && [[ "$name" != *$NEG_ONLY* ]]; then return; fi
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
  python3 harness/make_manifest.py --src "$NEG/src" --gen harness/.gen_menuneg >/dev/null
  local out
  case "$suite" in
    server) out=$(cd tests/menu && timeout 900 ../../tools/luau test_server.luau -a .gen_menuneg 2>&1) ;;
    guide) out=$(cd tests/menu && timeout 900 ../../tools/luau test_client.luau -a .gen_menuneg guide 2>&1) ;;
    menu) out=$(cd tests/menu && timeout 900 ../../tools/luau test_client.luau -a .gen_menuneg menu 2>&1) ;;
    sizes*) # one guiprev render ("sizes" = guide step 1 on the phone; "sizes|state|viewport|key=value ..."), then
      # the size checker on its dump (the dump name starts with the viewport: phone_ / desktop_)
      local st=guide1 vp=phone extra=""
      if [[ "$suite" == *"|"* ]]; then IFS='|' read -r _ st vp extra <<< "$suite"; fi
      local touch=""; [ "$vp" = "phone" ] && touch="touch=1"
      rm -f "$NEG"/*_neg.dump
      python3 tools/guiprev/guiprev.py --scene tests/menu/scene_menu.luau --gen harness/.gen_menuneg --no-manifest \
        --state "$st" --viewport "$vp" --out "$NEG/sizes.png" --save-dump "$NEG/${vp}_neg.dump" $touch $extra >/dev/null 2>&1
      out=$(python3 tests/menu/sizes.py "$NEG/${vp}_neg.dump" 2>&1) ;;
  esac
  local line; line=$(echo "$out" | grep -E "passed, [0-9]+ failed" | tail -n 1)
  total=$((total+1))
  if echo "$line" | grep -q " 0 failed"; then echo "NOT DETECTED  $name  ($line)"; else detected=$((detected+1)); echo "detected      $name  ($line)"; fi
}
TM=ReplicatedStorage/Shared/TutorialMath.module.luau
TP=ServerScriptService/Server/Lib/Template.module.luau
ES=ServerScriptService/Server/Services/EmpireService.module.luau
FN=ServerScriptService/Server/Lib/Funnel.module.luau
HUD=StarterPlayer/StarterPlayerScripts/Client/UI/Screens/HUD.module.luau
GD=StarterPlayer/StarterPlayerScripts/Client/UI/Screens/Guide.module.luau
GC=StarterPlayer/StarterPlayerScripts/Client/Controllers/GuideController.module.luau
CO=StarterPlayer/StarterPlayerScripts/Client/UI/Screens/Computer.module.luau
HA=StarterPlayer/StarterPlayerScripts/Client/UI/Apps/HomeApp.module.luau
TO=StarterPlayer/StarterPlayerScripts/Client/UI/Toast.module.luau

# server / pure (T1-T5)
mutate "step 2 falls back to step 1 when the Studio closes" server "$TM" 'if (studio and mode == "design") or saved >= 2 then' 'if (studio and mode == "design") then'
mutate "cleaner keeps an unclamped step" server "$TP" 'local step = if finite(t.step) then math.clamp(math.floor(t.step), 0, TutorialMath.STEPS) else 0' 'local step = if typeof(t.step) == "number" then t.step else 0'
mutate "op step skips the reachable check" server "$ES" '		if n > TutorialMath.reachable(data) + 1 then return {ok=false, err="BAD_INPUT"} end
' ''
mutate "op done before a release" server "$ES" '		if (tonumber(data.stats.modelsReleased) or 0) < 1 then return {ok=false, err="NOT_READY"} end
' ''
mutate "ClaimQuest all does not mark the quests" server "$ES" '			data.empire.quests[def.id] = true
			data.empire.xp += def.xp' '			data.empire.xp += def.xp'
mutate "assistantName formula drifts from AssistantService" server "$TM" '(math.floor(math.abs(owner)) * 13 + 4242)' '(math.floor(math.abs(owner)) * 13 + 4243)'
mutate "funnel steps sent twice per session" server "$FN" '	if memo[n] then
		return
	end' ''
# client guide (T6, T8, A8, A12, lab requests)
mutate "HUD action renamed (ring target lost)" guide "$HUD" '		b.Name = "GuideAction"' '		b.Name = "GuideButton"'
mutate "guide objects become Active (could sink taps)" guide "$GD" '	obj.Active = false' '	obj.Active = true'
mutate "no redirect to the Studio in steps 1-2" guide "$GC" '	if home then
		return "lab", "design"
	end' ''
mutate "guide selects the HUD button in the world (gamepad)" guide "$GC" '			ringObj = target
			Guide.setRing(target)' '			ringObj = target
			Guide.setRing(target)
			game:GetService("GuiService").SelectedObject = target'
mutate "L1 bound at High priority (would beat the Studio)" guide "$CO" 'Enum.ContextActionPriority.Medium.Value, Enum.KeyCode.ButtonL1' 'Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonL1'
mutate "ring stays on under the locked card" guide "$GC" ' or Computer.lockedShown() then' ' then'
mutate "Toast.hold ignored (lab #5)" guide "$TO" '	if holding and (kind == "info" or kind == "success") then' '	if false then'
mutate "score in the TRAINING_COMPLETE toast (lab #1)" guide "$HUD" 'Toast.show("success", "Training complete! Tap the goal card for the reveal.", 5)' 'Toast.show("success", "Training complete! Overall " .. tostring(payload.overall) .. ".", 5)'
# client menu (T9, T11, T12, B5, B11)
mutate "campus/building lands on Campus instead of Office" menu "$CO" 'building = "team.office" }' 'building = "team.campus" }'
mutate "back from a sub-tab jumps straight to Home" menu "$CO" '		if current ~= default then
			selectPage(default)
			return
		end' ''
mutate "a Shop card on Home" menu "$HA" '	-- 5. fillers (never during the guide, never invented)
	if not TutorialMath.active(data) then' '	-- 5. fillers (never during the guide, never invented)
	add({ key = "shop", kind = "idea", caption = "IDEA", title = "Visit the Shop", line = "", button = "OPEN SHOP ›", route = "page:shop.shop" })
	if not TutorialMath.active(data) then'
mutate "the Shop gets a NEW badge" menu "$CO" 'if not snapshot or key == "shop" or string.sub(key, 1, 5) == "shop." then' 'if not snapshot then' '		if unlocked and entry.id ~= "shop" then' '		if unlocked then' '	if not table.find(TutorialMath.SEEN_KEYS, key) or seenLocal[key] then
		return false
	end' '	if (key ~= "shop" and not table.find(TutorialMath.SEEN_KEYS, key)) or seenLocal[key] then
		return false
	end'
mutate "NEW pills during the guide" menu "$CO" '	if TutorialMath.active(data) then
		return false
	end
	local t = data.empire.tutorial' '	local t = data.empire.tutorial'
mutate "HUD Shop button during the guide" menu "$HUD" '	if TutorialMath.active(data) then
		return false
	end
	local studio = false' '	local studio = false'
# geometry (T7)
mutate "phone guide buttons 60 px (39 pt < 44 pt)" sizes "$HUD" 'local TOUCH_BUTTON = 70' 'local TOUCH_BUTTON = 60'
mutate "guide line 4 lines tall (column below the jump button)" sizes "$HUD" 'guideLine.Size = if compact then UDim2.new(1, 0, 0, 48) else UDim2.new(1, 0, 0, 24)' 'guideLine.Size = if compact then UDim2.new(1, 0, 0, 120) else UDim2.new(1, 0, 0, 24)'
mutate "chip drawn over the HUD buttons" sizes "$GD" '		c.Position = UDim2.fromOffset(anchor.x - 10 - w, rect.y + rect.h / 2 - c.AbsoluteSize.Y / 2)' '		c.Position = UDim2.fromOffset(anchor.x + 10, rect.y + rect.h / 2 - c.AbsoluteSize.Y / 2)'
mutate "Home card line fixed at 106 px (2 lines run into the button / ring)" "sizes|client|phone|app=home fresh=1" "$HA" '				ui.line.Position = UDim2.fromOffset(0, if oneLine then 78 else 106)
				ui.line.Size = UDim2.new(1, 0, 0, if oneLine or tall then 54 else 27)' '				ui.line.Position = UDim2.fromOffset(0, 106)
				ui.line.Size = UDim2.new(1, 0, 0, 54)'
mutate "Skip text back on the step bar" sizes "$HUD" '	skip.AnchorPoint = Vector2.new(1, 0.5)
	skip.Position = UDim2.fromScale(1, 0.5)' '	skip.AnchorPoint = Vector2.new(1, 0)
	skip.Position = UDim2.new(1, 0, 0, -32)'
mutate "Next goal caption 15 px on phones (9.7 pt)" "sizes|mid|phone|" "$HUD" 'stepCaption.TextSize = if compact then 19 else 14' 'stepCaption.TextSize = if compact then 15 else 14'
mutate "desktop Collect bar 34 px (31 px < 44 px)" "sizes|handoff|desktop|" "$HUD" '			reward.Size = UDim2.new(1, 0, 0, 48)
			reward.TextSize = 15' '			reward.Size = UDim2.new(1, 0, 0, 34)
			reward.TextSize = 15'
mutate "phone tip keeps the caption line (column below the jump button)" "sizes|client|phone|tip=1" "$HUD" 'captionRow.Visible = not guiding and not (compact and tipOn)' 'captionRow.Visible = not guiding'
mutate "phone progress text 17 px (11.0 pt)" "sizes|mid|phone|" "$HUD" 'progressText.TextSize = if compact then 19 else 13' 'progressText.TextSize = if compact then 17 else 13'
mutate "sub-tab NEW pill 18 px (10.8 pt)" "sizes|client|phone|app=home fresh=1" "$CO" 'local pill = Kit.text(b, "NEW", 21, F.bold, C.bg)' 'local pill = Kit.text(b, "NEW", 18, F.bold, C.bg)'
echo "menu negative: $detected of $total mutations detected"
[ "$detected" -eq "$total" ]
