#!/usr/bin/env bash
# Lab package: proves the lab checks FAIL when a rule is broken. Each mutation is applied to a private copy of
# work/src (agents/lab/neg/src); the named suite (preview | studio | models_rich | models_full) must then report failures.
# Usage: tests/lab/negative.sh
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
NEG="$ROOT/agents/lab/neg"
detected=0; total=0
mutate() { # name suite file find replace [find replace ...]
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
mutate "first model opens at step 1" studio "$DS" '			elseif LabPreview.isFirstModel(data) or typeof(opts.prefill) == "table" then
				step = 6' '			elseif typeof(opts.prefill) == "table" then
				step = 6'
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
echo "lab negative checks: $detected of $total mutations detected"
[ "$detected" -eq "$total" ]
