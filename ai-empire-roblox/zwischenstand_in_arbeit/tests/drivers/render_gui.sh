#!/usr/bin/env bash
# drivers package: GUI previews of the ride HUD and the destination sheet (desktop 1280x720 + iPhone landscape 844x390)
# into out/drivers/gui/. Usage: tests/drivers/render_gui.sh [filter]
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
python3 harness/make_manifest.py --src work/src --gen harness/.gen_drivers_gui >/dev/null || exit 1
mkdir -p out/drivers/gui
FILTER="${1:-}"
for st in hud_coming hud_waiting hud_board hud_queued hud_toast riding sheet_free sheet_busy sheet_riding sheet_abroad sheet_far; do
  for vp in desktop phone; do
    name="${vp}_${st}"
    if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then continue; fi
    dpr=1; [ "$vp" = "phone" ] && dpr=2
    timeout 600 python3 tools/guiprev/guiprev.py --scene tests/drivers/scene_drive.luau --gen harness/.gen_drivers_gui --no-manifest --state "$st" \
      --viewport "$vp" --dpr $dpr --out "out/drivers/gui/$name.png" --report >"out/drivers/gui/.$name.log" 2>&1 \
      && echo "out/drivers/gui/$name.png $(grep -c 'clipped\|overlap\|wider\|taller' out/drivers/gui/.$name.log) report lines" || { echo "FAILED $name"; tail -n 5 "out/drivers/gui/.$name.log"; }
  done
done
