#!/usr/bin/env bash
# GUI previews of the apps package (guiprev, approximate, not Studio screenshots) -> out/apps/*.png
#   HUD with the Next goal card (desktop + iPhone landscape), Company app Clients / Money / Settings / Overview,
#   Hardware (Compute) app, the assistant briefing panel; states of tests/apps/ui_setup.luau.
# Usage: tests/apps/render.sh [filter]   (filter = substring of the output name, e.g. "hud" or "rich")
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
python3 harness/make_manifest.py --src work/src --gen harness/.gen_apps >/dev/null || exit 1
OUT=out/apps; mkdir -p "$OUT"
F="${1:-}"
rc=0
shot() { # name state viewport [--strip X] [extra args...]
  local name="$1" state="$2" vp="$3"; shift 3
  if [ -n "$F" ] && [[ "$name" != *"$F"* ]]; then return; fi
  local dpr=1; [ "$vp" = "phone" ] && dpr=2; [ "$vp" = "667x375" ] && dpr=2
  if ! python3 tools/guiprev/guiprev.py --scene tests/apps/scene_apps.luau --gen harness/.gen_apps --no-manifest \
      --state "$state" --viewport "$vp" --dpr "$dpr" --out "$OUT/$name.png" "$@" >"$OUT/$name.log" 2>&1; then
    echo "FAILED $name (see $OUT/$name.log)"; rc=1
  elif grep -q "@@ERROR" "$OUT/$name.log"; then
    echo "ERROR in scene $name:"; grep "@@ERROR" "$OUT/$name.log" | head -3; rc=1
  else
    echo "ok $OUT/$name.png"
  fi
}
# HUD: desktop + phone, empty garage / first client / saving / mid / rich
for st in garage client save mid rich; do shot "hud_$st" "$st" desktop app=none; done
for st in garage mid rich; do shot "hud_${st}_phone" "$st" phone app=none touch=1; done
shot hud_rich_abroad rich desktop app=none travel=abroad
# Company app
for st in garage mid rich; do
  for sec in clients money settings; do shot "empire_${st}_$sec" "$st" desktop --strip EmpireScroll app=empire section=$sec; done
done
shot empire_rich_overview rich desktop app=empire section=overview
shot empire_mid_money_day8 mid desktop app=empire section=money press=Day_8
shot empire_mid_clients_phone mid phone app=empire section=clients touch=1
shot empire_mid_settings_phone mid phone app=empire section=settings touch=1
# Hardware app
for st in garage mid rich; do shot "compute_$st" "$st" desktop --strip ComputeScroll app=compute; done
shot compute_mid_phone mid phone app=compute touch=1
# Assistant briefing (PeopleController panel with the real AssistantService payload)
for st in garage mid rich; do shot "brief_$st" "$st" desktop app=none brief=1; done
shot brief_mid_phone mid phone app=none brief=1 touch=1
# fix round: adversarial states and small phones (iPhone SE 667x375), the HUD next to the company phone
shot hud_garage_se garage 667x375 --insets 58,0,0,0 app=none touch=1
shot hud_mid_phone_withphone mid phone app=none touch=1 phone=1
shot hud_mid_phoneopen mid phone app=none touch=1 phone=1 phoneopen=1
shot hud_broke mid desktop app=none mod=broke
shot hud_broke_phone mid phone app=none touch=1 mod=broke
shot compute_rackfull mid desktop --strip ComputeScroll app=compute mod=rackfull
shot compute_maxed mid desktop --strip ComputeScroll app=compute mod=maxed
shot money_oldsave mid desktop --strip EmpireScroll app=empire section=money mod=oldsave
shot clients_broke mid desktop --strip EmpireScroll app=empire section=clients mod=broke
shot clients_mid_se mid 667x375 --insets 58,0,0,0 app=empire section=clients touch=1
shot clients_garage_nolive garage desktop --strip EmpireScroll app=empire section=clients
shot empire_mid_team_phone mid phone app=empire section=team touch=1
exit $rc
