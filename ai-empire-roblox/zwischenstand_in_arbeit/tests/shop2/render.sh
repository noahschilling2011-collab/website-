#!/usr/bin/env bash
# GUI previews of the shop package (guiprev, approximate, not Studio screenshots) at 844x390 (iPhone landscape, @2x)
# and 1280x720 -> out/shop/*.png (+ .dump for tests/shop2/sizes.py). Usage: tests/shop2/render.sh [filter] [outdir]
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
python3 harness/make_manifest.py --src work/src --gen harness/.gen_shop2 >/dev/null || exit 1
OUT="${2:-out/shop}"; mkdir -p "$OUT"
F="${1:-}"
rc=0
ALL="pipeline,cleaning,architecture,quantization,alignment,distribution,frontier,cluster"
shot() { # name state viewport [scene options...]
  local name="$1" state="$2" vp="$3"; shift 3
  if [ -n "$F" ] && [[ "$name" != *"$F"* ]]; then return; fi
  local dpr=1 touch=""; [ "$vp" = "phone" ] && { dpr=2; touch="touch=1"; }
  # focus=<Name> scrolls with the previous pass's layout: 2 passes (pass 1 lays out, pass 2 scrolls)
  local passes=3; [[ " $* " == *" focus="* ]] && passes=2
  if ! python3 tools/guiprev/guiprev.py --scene tests/shop2/scene_shop.luau --gen harness/.gen_shop2 --no-manifest --report --passes $passes \
      --state "$state" --viewport "$vp" --dpr "$dpr" --out "$OUT/$name.png" --save-dump "$OUT/$name.dump" $touch "$@" >"$OUT/$name.log" 2>&1; then
    echo "FAILED $name (see $OUT/$name.log)"; rc=1
  elif grep -q "@@ERROR" "$OUT/$name.log"; then
    echo "ERROR in scene $name:"; grep "@@ERROR" "$OUT/$name.log" | head -3; rc=1
  else
    echo "ok $OUT/$name.png"
  fi
}
for vp in phone desktop; do
  # the Shop page (5 tabs)
  shot "${vp}_shop_home" mid $vp catalog=1 page=shop.home vouchers=eureka:1,keynote:2,headhunter:1
  shot "${vp}_shop_home_soon" mid $vp page=shop.home
  shot "${vp}_shop_home_preview" mid $vp studio=1 page=shop.home
  shot "${vp}_shop_speedups" mid $vp catalog=1 page=shop.speedups
  shot "${vp}_shop_boosts" mid $vp catalog=1 page=shop.boosts boost=keynote:760 daily=keynote:1 vouchers=overclock:1
  shot "${vp}_shop_style" mid $vp catalog=1 page=shop.style owned=serverGlow
  shot "${vp}_shop_extras" mid $vp catalog=1 page=shop.extras
  shot "${vp}_shop_home_categories" mid $vp catalog=1 page=shop.home scroll=420
  shot "${vp}_shop_extras_cash" mid $vp catalog=1 page=shop.extras packs=seed scroll=330
  shot "${vp}_shop_extras_packs" mid $vp catalog=1 page=shop.extras packs=seed scroll=640
  shot "${vp}_shop_style_shows" mid $vp catalog=1 page=shop.style owned=identityKit scroll=560
  shot "${vp}_shop_style_kit" mid $vp catalog=1 page=shop.style owned=identityKit
  # use sheets (SHOP_SPEC 5.3)
  shot "${vp}_sheet_eureka_idle" mid $vp catalog=1 app=empire section=research points=0 vouchers=eureka:1 sheet=eureka:quantization
  shot "${vp}_sheet_eureka_running" mid $vp catalog=1 app=empire section=research job=quantization:10 vouchers=eureka:1 sheet=eureka
  shot "${vp}_sheet_eureka_lab" mid $vp catalog=1 app=lab research=$ALL lab=3 points=0 vouchers=eureka:1 sheet=eureka:lab
  shot "${vp}_sheet_last_epoch" mid $vp catalog=1 trainingview=1 training=0.5 vouchers=lastEpoch:1 sheet=lastEpoch
  shot "${vp}_sheet_keynote" mid $vp catalog=1 page=shop.boosts vouchers=keynote:1 sheet=keynote
  shot "${vp}_sheet_overclock" mid $vp catalog=1 page=shop.boosts training=0.4 vouchers=overclock:1 sheet=overclock
  shot "${vp}_sheet_received" mid $vp catalog=1 app=empire section=research points=0 vouchers=eureka:1 received=eureka:quantization
  # Eureka buttons in context
  shot "${vp}_research_eureka" mid $vp catalog=1 app=empire section=research points=0 focus=Research_quantization
  shot "${vp}_research_running" mid $vp catalog=1 app=empire section=research job=quantization:10 vouchers=eureka:2 focus=Research_quantization
  shot "${vp}_research_running_short" mid $vp catalog=1 app=empire section=research job=pipeline:10 research=cleaning vouchers=eureka:1 focus=Research_pipeline
  shot "${vp}_lab_card_eureka" mid $vp catalog=1 app=lab research=$ALL lab=3 points=0 focus=LabButtons
  shot "${vp}_lab_card_owned" mid $vp catalog=1 app=lab research=$ALL lab=3 points=100000 vouchers=eureka:1 focus=LabButtons
  shot "${vp}_studio_7b_skip" mid $vp catalog=1 studio7b=1 vram=128 money=900000 points=0
  shot "${vp}_studio_7b_vram" mid $vp catalog=1 studio7b=1 vram=96 money=900000
  shot "${vp}_studio_7b_review" mid $vp catalog=1 review7b=1 vram=128 money=900000 vouchers=eureka:1
  shot "${vp}_training_last_epoch" mid $vp catalog=1 trainingview=1 training=0.1
  shot "${vp}_training_overclock" mid $vp catalog=1 trainingview=1 training=0.3 boost=overclock:540 vouchers=lastEpoch:2
  shot "${vp}_reveal_stage_lights" mid $vp catalog=1 trainingview=1 training=0.9 owned=stageLights reveal=1.2
  # cosmetics + boosts outside the shop
  shot "${vp}_settings_rebrand" mid $vp catalog=1 app=empire section=settings
  shot "${vp}_settings_rebrand_kit" mid $vp catalog=1 app=empire section=settings owned=identityKit
  shot "${vp}_settings_rebrand_more" mid $vp catalog=1 app=empire section=settings scroll=230
  shot "${vp}_home_boosts" mid $vp catalog=1 app=home boost=keynote:760,overclock:500 training=0.5
  shot "${vp}_guide_no_offer" mid $vp catalog=1 tutorial=1 app=empire section=research points=0 focus=Research_quantization
done
exit $rc
