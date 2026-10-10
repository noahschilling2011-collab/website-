#!/usr/bin/env bash
# staffops GUI previews (approximate, from the real client code): rack fault world GUIs + the talk panel
# lines on desktop (1280x720) and iPhone landscape (844x390) into out/staffops/.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
python3 harness/make_manifest.py --src work/src --gen harness/.gen_staffops >/dev/null || exit 1
mkdir -p out/staffops
shot() { # name state viewport [key=value...]
  local name="$1" state="$2" vp="$3"; shift 3
  local dpr=1; [ "$vp" = "phone" ] && dpr=2
  timeout 300 python3 tools/guiprev/guiprev.py --scene tests/staffops/scene_staffops.luau --gen harness/.gen_staffops --no-manifest \
    --state "$state" --viewport "$vp" --dpr $dpr --report --out "out/staffops/$name.png" "$@" >"out/staffops/.$name.log" 2>&1 \
    && echo "out/staffops/$name.png" || { echo "FAILED $name"; tail -n 5 "out/staffops/.$name.log"; }
}
shot rack rack desktop
for vp in desktop phone; do
  for st in talk_garage talk_trainer talk_rich; do shot "${vp}_${st}" "$st" "$vp"; done
  shot "${vp}_talk_apprentices" talk_trainer "$vp" ask=apprentices
done
