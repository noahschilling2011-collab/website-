#!/usr/bin/env bash
# itinerary package: GUI previews of the trip banner (+ HUD, ride panel, phone call sheet / calendar) on the real server
# state machine, desktop 1280x720 and iPhone landscape 844x390, into out/itinerary/. Usage: tests/itinerary/render_gui.sh [filter]
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
python3 harness/make_manifest.py --src work/src --gen harness/.gen_itinerary_gui >/dev/null || exit 1
mkdir -p out/itinerary
FILTER="${1:-}"
for st in countdown offer call pickup timed airport deboard limo meeting hotel return calendar collapsed region; do
  for vp in desktop phone; do
    name="${vp}_${st}"
    if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then continue; fi
    dpr=1; [ "$vp" = "phone" ] && dpr=2
    timeout 900 python3 tools/guiprev/guiprev.py --scene tests/itinerary/scene_trip.luau --gen harness/.gen_itinerary_gui --no-manifest --state "$st" \
      --viewport "$vp" --dpr $dpr --out "out/itinerary/$name.png" --report >"out/itinerary/.$name.log" 2>&1 \
      && echo "out/itinerary/$name.png $(grep -c 'clipped\|overlap\|wider\|taller' out/itinerary/.$name.log) report lines" || { echo "FAILED $name"; tail -n 5 "out/itinerary/.$name.log"; }
  done
done
