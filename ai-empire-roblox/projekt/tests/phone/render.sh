#!/usr/bin/env bash
# Phone package: GUI previews of every phone screen (desktop 1280x720 and iPhone landscape 844x390) into out/phone/.
# Usage: tests/phone/render.sh [filter]   (filter = substring of the image name, e.g. "phone_" or "thread")
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
python3 harness/make_manifest.py --src work/src --gen harness/.gen_phone >/dev/null || exit 1
mkdir -p out/phone
FILTER="${1:-}"
shot() { # name state viewport screen [extra...]
  local name="$1" state="$2" vp="$3" screen="$4"; shift 4
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then return; fi
  local dpr=1; [ "$vp" = "phone" ] && dpr=2
  timeout 600 python3 tools/guiprev/guiprev.py --scene tests/phone/scene_phone.luau --gen harness/.gen_phone --no-manifest --state "$state" \
    --viewport "$vp" --dpr $dpr --out "out/phone/$name.png" "screen=$screen" "$@" >/dev/null 2>"out/phone/.$name.err" \
    && echo "out/phone/$name.png" || { echo "FAILED $name"; tail -n 5 "out/phone/.$name.err"; }
}
for vp in desktop phone; do
  shot "${vp}_garage_home" garage $vp home
  shot "${vp}_garage_messages" garage $vp messages
  shot "${vp}_garage_chat" garage $vp chat
  shot "${vp}_garage_calendar" garage $vp calendar
  shot "${vp}_rich_closed" rich $vp closed
  shot "${vp}_rich_banner" rich $vp banner
  shot "${vp}_rich_home" rich $vp home
  shot "${vp}_rich_messages" rich $vp messages
  shot "${vp}_rich_message" rich $vp message
  shot "${vp}_rich_calls" rich $vp calls
  shot "${vp}_rich_call" rich $vp call
  shot "${vp}_rich_callresult" rich $vp callresult
  shot "${vp}_rich_calendar" rich $vp calendar
  shot "${vp}_rich_contacts" rich $vp contacts
  shot "${vp}_rich_dial" rich $vp dial
  shot "${vp}_rich_chat" rich $vp chat
  shot "${vp}_rich_thread" rich $vp thread
  shot "${vp}_rich_settings" rich $vp settings
done
shot "touch_rich_banner" rich phone banner touch=1
