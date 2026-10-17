#!/usr/bin/env bash
# GUI previews of the menu package (guiprev, approximate, not Studio screenshots) -> out/menu/*.png
#   the "First steps" guide (HUD card, ring, dim, chip, Studio rings), the hand-off, the Intro, the Menu (Home, pages,
#   locked card) at 844x390 (iPhone 12-14 landscape, @2x) and 1280x720. Usage: tests/menu/render.sh [filter] [outdir]
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
python3 harness/make_manifest.py --src work/src --gen harness/.gen_menu >/dev/null || exit 1
OUT="${2:-out/menu}"; mkdir -p "$OUT"
F="${1:-}"
rc=0
shot() { # name state viewport [extra args...]
  local name="$1" state="$2" vp="$3"; shift 3
  if [ -n "$F" ] && [[ "$name" != *"$F"* ]]; then return; fi
  local dpr=1; [ "$vp" = "phone" ] && dpr=2
  local touch=""; [ "$vp" = "phone" ] && touch="touch=1"
  if ! python3 tools/guiprev/guiprev.py --scene tests/menu/scene_menu.luau --gen harness/.gen_menu --no-manifest --report \
      --state "$state" --viewport "$vp" --dpr "$dpr" --out "$OUT/$name.png" --save-dump "$OUT/$name.dump" $touch "$@" >"$OUT/$name.log" 2>&1; then
    echo "FAILED $name (see $OUT/$name.log)"; rc=1
  elif grep -q "@@ERROR" "$OUT/$name.log"; then
    echo "ERROR in scene $name:"; grep "@@ERROR" "$OUT/$name.log" | head -3; rc=1
  else
    echo "ok $OUT/$name.png"
  fi
}
for vp in phone desktop; do
  shot "${vp}_guide1_greeting" guide1 $vp
  shot "${vp}_guide1_after_dim" guide1b $vp
  shot "${vp}_guide2_studio_buy" guide2 $vp
  shot "${vp}_guide2_studio_start" guide2s $vp
  shot "${vp}_guide3_training" guide3 $vp
  shot "${vp}_guide3_decide" guide3d $vp
  shot "${vp}_guide4_launch" guide4 $vp
  shot "${vp}_guide4_reveal" guide4r $vp
  shot "${vp}_guide4_launchday" guide4l $vp
  shot "${vp}_guide5_income" guide5 $vp
  shot "${vp}_handoff" handoff $vp
  shot "${vp}_intro" intro $vp
  shot "${vp}_intro_customize" introc $vp
  shot "${vp}_menu_home_guide" guide1b $vp page=home.today
  shot "${vp}_menu_locked" guide1b $vp page=home.today locked=market
  shot "${vp}_menu_home_fresh" client $vp app=home fresh=1
  shot "${vp}_menu_home_mid" mid $vp app=home
  shot "${vp}_menu_home_rich" rich $vp app=home
  shot "${vp}_menu_money" mid $vp app=home section=money
  shot "${vp}_menu_goals" save $vp app=home section=goals
  shot "${vp}_menu_lab_models" mid $vp app=lab
  shot "${vp}_menu_lab_research" mid $vp app=empire section=research
  shot "${vp}_menu_lab_gpus" mid $vp app=compute
  shot "${vp}_menu_market" mid $vp app=market
  shot "${vp}_menu_clients" mid $vp app=empire section=clients
  shot "${vp}_menu_team_staff" mid $vp app=empire section=team
  shot "${vp}_menu_team_campus" mid $vp app=campus
  shot "${vp}_menu_team_settings" mid $vp app=empire section=settings
  shot "${vp}_menu_shop" mid $vp app=shop
  shot "${vp}_hud_normal" mid $vp
  shot "${vp}_hud_shop_button" client $vp studio=1
  shot "${vp}_hud_tip" client $vp tip=1
  shot "${vp}_hud_collect_shop" handoff $vp studio=1
done
exit $rc
