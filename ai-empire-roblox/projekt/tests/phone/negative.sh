#!/usr/bin/env bash
# Phone package: proves the phone checks FAIL when a rule is broken. Each mutation is applied to a private copy of
# work/src (agents/phone/neg/src); the named suite must then report failures.
# Usage: tests/phone/negative.sh
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
NEG="$ROOT/agents/phone/neg"
detected=0; total=0
mutate() { # name suite(server|garage|rich) file find replace
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
  python3 harness/make_manifest.py --src "$NEG/src" --gen harness/.gen_phoneneg >/dev/null
  local out
  case "$suite" in
    server) out=$(cd tests/phone && timeout 900 ../../tools/luau test_phone.luau -a .gen_phoneneg 2>&1) ;;
    *) out=$(cd tests/phone && timeout 900 ../../tools/luau test_ui.luau -a .gen_phoneneg "$suite" 2>&1) ;;
  esac
  local line; line=$(echo "$out" | grep -E "passed, [0-9]+ failed" | tail -n 1)
  total=$((total+1))
  if echo "$line" | grep -q " 0 failed"; then echo "NOT DETECTED  $name  ($line)"; else detected=$((detected+1)); echo "detected      $name  ($line)"; fi
}
PS=ServerScriptService/Server/Services/PhoneService.module.luau
PM=ReplicatedStorage/Shared/PhoneMath.module.luau
PC=StarterPlayer/StarterPlayerScripts/Client/Controllers/PhoneController.module.luau
PH=StarterPlayer/StarterPlayerScripts/Client/UI/Screens/Phone.module.luau
SC=StarterPlayer/StarterPlayerScripts/Client/UI/Phone/PhoneScreens.module.luau
mutate "no per-player chat gap" server "$PM" 'PhoneMath.CHAT_GAP = 4 ' 'PhoneMath.CHAT_GAP = 0 '
mutate "no global TextGenerator budget" server "$PM" 'PhoneMath.CHAT_GLOBAL_PER_MINUTE = 90' 'PhoneMath.CHAT_GLOBAL_PER_MINUTE = 100000'
mutate "no demo fallback on errors" server "$PS" '		return demo(if ok then "empty" else "error")' '		return "", "ai", nil'
mutate "input not filtered" server "$PS" '		local filtered = seams.filter(text, s.userId)' '		local filtered = text'
mutate "no length limit" server "$PS" 'if typeof(raw) == "string" and (utf8.len(raw) or math.huge) > PhoneMath.CHAT_MAX_CHARS then return { ok = false, err = "TOO_LONG" } end' ''
mutate "context token not forwarded" server "$PS" '		if cs.token then request.ContextToken = cs.token end' ''
mutate "no breaker after errors" server "$PS" '	if now < breaker.until_ then return demo("offline") end' ''
mutate "calls on the first scan (no baseline)" server "$PS" '	if not seen.ready then' '	if false then'
mutate "dishonest itinerary answer" server "$PS" '"The travel desk opens soon. "' '"Booked! "'
mutate "system prompt without the real stats" server "$PM" 'overall, table.concat(stats, ", "), quality,' 'overall, "", quality,'
mutate "weak models not told to be weak" server "$PM" '	if overall < 40 then' '	if overall < 0 then'
mutate "demo replies labelled as AI" server "$PM" 'PhoneMath.DEMO_LABEL = "Demo reply (offline)"' 'PhoneMath.DEMO_LABEL = "AI reply"'
mutate "sick colleagues not reported" server "$PM" '			if state == "sick" then table.insert(sick, name)' '			if state == "never" then table.insert(sick, name)'
mutate "check-in due ignores the lead time" server "$PM" '		local due = expires - (Ops.TRIPS[c.trip].days + Ops.RENEW_LEAD_DAYS) * DAY' '		local due = expires - Ops.TRIPS[c.trip].days * DAY'
mutate "signed clients not mapped to Sales" server "$PM" '	a, b = string.match(text, "^signed (.-): (.*)$")' '	a, b = string.match(text, "^signedX (.-): (.*)$")'
mutate "chat changes money" server "$PS" '		local reply, source, reason = generate(cs, model, company, filtered, now)' '		local reply, source, reason = generate(cs, model, company, filtered, now); data.money -= 1'
mutate "phone overlaps the HUD column" garage "$PH" '	local rightEdge = hudW + m' '	local rightEdge = m'
mutate "no landscape phone on small screens" rich "$PH" '	local shapeLandscape = sp < 0.78' '	local shapeLandscape = false'
mutate "phone stays over the Computer" garage "$PC" '	Phone.setHidden(not company or hud == true or Computer.isOpen())' '	Phone.setHidden(not company or hud == true)'
mutate "inbox not read on open" rich "$SC" '	ctx.deps.markRead(keys) -- opening the inbox reads it' '	-- markRead removed'
mutate "old news counted as unread" rich "$PC" '		for _, m in newsList do read[m.key] = true end' ''
mutate "chat input not limited" rich "$SC" '			if cut then box.Text = string.sub(box.Text, 1, cut - 1) end' ''
mutate "talk panel does not close the phone" garage "$PC" '		if Controller.PANELS[child.Name] then Phone.close() end' ''
echo "phone negative checks: $detected of $total mutations detected"
[ "$detected" -eq "$total" ]
