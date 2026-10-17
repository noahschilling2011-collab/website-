#!/usr/bin/env bash
# Lab package: proves the lab checks FAIL when a rule is broken. Each mutation is applied to a private copy of
# work/src (agents/lab/neg/src); the named suite (preview | studio | models_rich | models_full) must then report failures.
# Usage: tests/lab/negative.sh   (NEG_ONLY=<substring> runs only the matching mutations)
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
NEG="$ROOT/agents/lab/neg"
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
  python3 harness/make_manifest.py --src "$NEG/src" --gen harness/.gen_labneg >/dev/null
  local out
  case "$suite" in
    preview) out=$(cd tests/lab && timeout 900 ../../tools/luau test_labpreview.luau -a .gen_labneg 2>&1) ;;
    studio) out=$(cd tests/lab && timeout 900 ../../tools/luau test_studio.luau -a .gen_labneg 2>&1) ;;
    models_rich) out=$(cd tests/models && timeout 900 ../../tools/luau test_ui.luau -a .gen_labneg rich 2>&1) ;;
    models_full) out=$(cd tests/models && timeout 900 ../../tools/luau test_ui.luau -a .gen_labneg full 2>&1) ;;
  esac
  local line; line=$(echo "$out" | grep -E "passed, [0-9]+ failed" | tail -n 1)
  total=$((total+1))
  if echo "$line" | grep -q " 0 failed"; then echo "NOT DETECTED  $name  ($line)"; else detected=$((detected+1)); echo "detected      $name  ($line)"; fi
}
LP=StarterPlayer/StarterPlayerScripts/Client/UI/Lab/LabPreview.module.luau
DS=StarterPlayer/StarterPlayerScripts/Client/UI/Lab/DesignSteps.module.luau
ST=StarterPlayer/StarterPlayerScripts/Client/UI/Lab/Studio.module.luau
SG=StarterPlayer/StarterPlayerScripts/Client/UI/Lab/Stages.module.luau
LD=StarterPlayer/StarterPlayerScripts/Client/UI/Lab/LaunchDay.module.luau
LA=StarterPlayer/StarterPlayerScripts/Client/UI/Apps/LabApp.module.luau
MA=StarterPlayer/StarterPlayerScripts/Client/UI/Apps/MarketApp.module.luau
AI=ServerScriptService/Server/Services/AIModelService.module.luau
MM=ReplicatedStorage/Shared/ModelMath.module.luau
SP=StarterPlayer/StarterPlayerScripts/Client/UI/Lab/StudioParts.module.luau
mutate "server accepts an invalid look" preview "$AI" 'if not colorId or not emblem then return {ok=false,err="BAD_INPUT"} end' 'if false then return nil end'
mutate "server accepts an unknown target" preview "$AI" 'if not target or not MarketConfig.isTarget(target) then return {ok=false,err="BAD_INPUT"} end' ''
mutate "S1 payload without expected" preview "$AI" '			expected = training.expected,' ''
mutate "S1 payload without the refinement's old score" preview "$AI" '			before = if training.refinement then before else nil,' '			before = nil,'
mutate "estimate ignores the training plan factor" preview "$LP" '	local stats, overall = ModelMath.computeStats(size.id, focus.id, summary, specOf(data), factor, nil)' '	local stats, overall = ModelMath.computeStats(size.id, focus.id, summary, specOf(data), 1, nil)'
mutate "estimate skips the research/Lab boost" preview "$LP" '	stats, overall = EmpireMath.boostStats(stats, data.empire)
	stats, overall = ModelMath.capStats(stats)
	local rate' '	stats, overall = ModelMath.capStats(stats)
	local rate'
mutate "lock order: VRAM before research" preview "$LP" '	if size.id == "s7b" and not data.empire.research.frontier then
		lock = "FRONTIER"
	elseif ModelMath.activeModels(data) >= modelLimit() then' '	if plan.reason == "VRAM" then
		lock = "VRAM"
	elseif size.id == "s7b" and not data.empire.research.frontier then
		lock = "FRONTIER"
	elseif ModelMath.activeModels(data) >= modelLimit() then'
mutate "data plan stops later than the bot" preview "$LP" '		if not bestPack or bestGain < 0.3 / 1000 then' '		if not bestPack or bestGain < 0.1 / 1000 then'
mutate "best I can afford ignores the reserve" preview "$LP" '	local free = money - LabPreview.reserve(data)' '	local free = money'
mutate "next version off by one" preview "$MM" '	return math.max(count, highest) + 1
end

-- Model look' '	return math.max(count, highest) + 2
end

-- Model look'
mutate "refineCheck forgets the new-data rule" preview "$LP" '	if summary.total < model.dataUsed.total + 1e8 then
		local tokens' '	if false then
		local tokens'
mutate "first model defaults to Quick pass" studio "$DS" '				StateController.setRecipe("steady")
			end
			if LabState.name == "" then' '				StateController.setRecipe("rapid")
			end
			if LabState.name == "" then'
mutate "first model opens at step 1" studio "$DS" '			elseif typeof(opts.prefill) == "table" or firstOpen then
				step = 6' '			elseif typeof(opts.prefill) == "table" then
				step = 6' '			elseif LabPreview.isFirstModel(data) then
				step = 6
' '			elseif false then
				step = 6
'
mutate "touch controls not restored" studio "$ST" '		touchSaved = nil
		GuiService.TouchControlsEnabled = saved' '		touchSaved = nil'
mutate "input stays bound after close" studio "$ST" '		ContextActionService:UnbindAction(Studio.ACTION)' ''
mutate "Studio survives Computer.close" studio "$ST" '		if not frameHost.Visible and Studio.mode ~= "closed" then' '		if false then'
mutate "openRelease skips the reveal" studio "$LA" '	if not LabState.wasRevealed(modelId) then
		LabApp.openReveal(modelId)
		return
	end' ''
mutate "reveal shows a record without the payload rule" studio "$SG" '				elseif model.overall > math.max(previousBest, before or 0) then' '				elseif true then'
mutate "campaign not preselected" studio "$LD" '		marketing = PricingMath.recommendedMarketing(money, EmpireMath.bonuses(data.empire).wage)
		campaignId = "recommended"' '		marketing = 0
		campaignId = "none"'
mutate "no chat button in the Market" studio "$MA" '		chat.Name = "Chat"' '		chat.Name = "Chat2"'
mutate "refine on the reveal not pre-checked" studio "$SG" '		Kit.setDisabled(refine, not check.ok)' ''
mutate "Launch Day line tiles lose their short name" models_full "$LD" '		local option = Parts.optionTile(bodies[1], "Line_" .. line.target, UDim2.fromOffset(col * 333, row * 110), Vector2.new(321, 98), 2, 26, 24, line.short)' '		local option = Parts.optionTile(bodies[1], "Line_" .. line.target, UDim2.fromOffset(col * 333, row * 110), Vector2.new(321, 98), 2, 26, 24, line.label)'
mutate "Lab home drops the stat-cap line" models_rich "$LA" '		capNote.Text = `Every stat caps at {STAT_CAP}.`' '		capNote.Text = ""'
mutate "disabled tiles reveal their hidden Text" studio "$SP" '	if button:GetAttribute("HiddenText") == true then' '	if false then'
mutate "phone Review breakdown never opens" studio "$DS" '			breakdownOpen = true
			refresh()' '			refresh()'
mutate "line successor drops the bot rule (keeps the live size, Standard)" preview "$LP" '	local pick = LabPreview.successorPick(data, live, target, focusId, money, saveMode)
	local sizeId = if pick then pick.sizeId elseif ModelConfig.getSize(model.sizeId)' '	local pick = nil
	local sizeId = if pick then pick.sizeId elseif ModelConfig.getSize(model.sizeId)'
mutate "server forgets the model's training plan (recipeId)" preview "$AI" '	extra.recipeId = recipeId' ''
mutate "breakdown explains today's empty data instead of the plan" studio "$DS" '		local bd = LabPreview.breakdown(dview, s)' '		local bd = LabPreview.breakdown(data, s)'
# fix round 1 (review: function + UX)
mutate "suggestion prefill drops its data plan (2-tap path trains on today's data)" studio "$LP" '		plan = if pick and pick.plan.cost > 0 then pick.plan else nil,' '		plan = nil,'
mutate "reveal marks the model revealed when it opens (HUD path skips to Launch Day)" studio "$SG" '		LabState.revealing = modelId
		local id0 = modelId' '		LabState.revealing = modelId
		if modelId then LabState.markRevealed(modelId) end
		local id0 = modelId'
mutate "Studio opens behind a closed Computer" studio "$ST" '	if not hostReady() then
		return
	end' ''
mutate "refined live model ranked by its old plan" studio "$SG" '	local release = model.release
	if release and ModelConfig.getLine(release.target) then
		return release.target
	end' ''
mutate "ceiling = the size's raw potential (old 'Max score')" preview "$LP" '	ceilingKey, ceilingValue = key, best
	return best' '	return size.potential'
mutate "BUY DATA PLAN re-enabled before the snapshot (double tap buys twice / starts)" studio "$DS" '		if bought > 0 then
			-- the suggestion' '		busy = nil
		if false then
			-- the suggestion'
mutate "first-model defaults on every open (player's pick lost)" studio "$DS" '			elseif LabPreview.isFirstModel(data) and not data.training and not LabState.firstDefaults then' '			elseif LabPreview.isFirstModel(data) and not data.training then'
mutate "TRAINING_COMPLETE switches modes while designing" studio "$LA" '				offerReveal(id) -- busy elsewhere in the Studio: a banner, no mode switch' '				LabApp.openReveal(id)'
mutate "Deep tile says 'Too little data' whatever fails" studio "$DS" '					last = deepWhy or "Overfits now"' '					last = "Too little data"'
mutate "refinement counts up from the server placeholder" studio "$SG" '		local from = if payload.refinement == true and typeof(payload.before) == "number" then payload.before
			elseif' '		local from = if false then 0
			elseif'
mutate "gamepad selection can leave the Studio" studio "$ST" '	root.SelectionGroup = true' '	root.SelectionGroup = false'
mutate "cash below the reserve still green" studio "$DS" '			moneyTiles[3].value.TextColor3 = if after < 0 then C.bad elseif after < reserve then C.warn else C.good' '			moneyTiles[3].value.TextColor3 = if after < 0 then C.bad else C.good'
mutate "Lab home re-renders under the open Studio" studio "$LA" '		-- the opaque Studio covers the Lab home: it re-renders when the Studio closes (onClosed above)
		if parent.Visible and navigation.isOpen() and not Studio.isOpen() then' '		if parent.Visible and navigation.isOpen() then'
mutate "picked look survives START" studio "$DS" '			LabState.colorId = nil
			LabState.emblem = nil
			done =' '			done ='
mutate "suggest skips the free product line" preview "$LP" '	if #lives < ModelMath.productSlots(data.empire.office) then' '	if false then'
mutate "ceremony title back in the toast lane" studio "$ST" '	local ct = Parts.label(root, "", 44, F.display, C.text, UDim2.fromOffset(172, 32), UDim2.fromOffset(330, 54))' '	local ct = Parts.label(root, "", 44, F.display, C.text, UDim2.new(0.5, -165, 0, 32), UDim2.fromOffset(330, 54), Enum.TextXAlignment.Center)'
mutate "NO_DATA steps use today's empty data" studio "$DS" '			local deltas = LabPreview.deltas(dview, s, "focusId", viewMoney)' '			local deltas = LabPreview.deltas(data, s, "focusId", money)'
echo "lab negative checks: $detected of $total mutations detected"
[ "$detected" -eq "$total" ]
