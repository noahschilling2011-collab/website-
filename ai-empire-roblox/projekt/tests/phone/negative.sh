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
    # garage | rich | fixes | touch: the test_ui modes
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
PK=StarterPlayer/StarterPlayerScripts/Client/UI/Phone/PhoneKit.module.luau
mutate "no per-player chat gap" server "$PM" 'PhoneMath.CHAT_GAP = 4 ' 'PhoneMath.CHAT_GAP = 0 '
mutate "no global TextGenerator budget" server "$PM" 'PhoneMath.CHAT_GLOBAL_PER_MINUTE = 90' 'PhoneMath.CHAT_GLOBAL_PER_MINUTE = 100000'
mutate "no demo fallback on errors" server "$PS" '		return demo(if ok then "empty" else "error")' '		return "", "ai", nil'
mutate "input not filtered" server "$PS" '		local filtered = seams.filter(text, s.userId)' '		local filtered = text'
mutate "no length limit" server "$PS" 'if typeof(raw) == "string" and (utf8.len(raw) or math.huge) > PhoneMath.CHAT_MAX_CHARS then return { ok = false, err = "TOO_LONG" } end' ''
mutate "context token not forwarded" server "$PS" '		if cs.token then request.ContextToken = cs.token end' ''
mutate "no breaker after errors" server "$PS" '	if now < breaker.until_ or now < st.breaker.until_ then return demo("offline") end' ''
mutate "calls on the first scan (no baseline)" server "$PS" '	if not seen.ready then' '	if false then'
mutate "dishonest itinerary answer" server "$PS" '"The travel desk opens soon. "' '"Booked! "'
mutate "system prompt without the real stats" server "$PM" 'overall, table.concat(stats, ", "), quality,' 'overall, "", quality,'
mutate "weak models not told to be weak" server "$PM" '	if overall < 40 then' '	if overall < 0 then'
mutate "demo replies labelled as AI" server "$PM" 'PhoneMath.DEMO_LABEL = "Demo reply (offline)"' 'PhoneMath.DEMO_LABEL = "AI reply"'
mutate "sick colleagues not reported" server "$PM" '			if state == "sick" then table.insert(sick, name)' '			if state == "never" then table.insert(sick, name)'
mutate "check-in due ignores the lead time" server "$PM" '		local due = expires - (Ops.TRIPS[c.trip].days + Ops.RENEW_LEAD_DAYS) * DAY' '		local due = expires - Ops.TRIPS[c.trip].days * DAY'
mutate "signed clients not mapped to Sales" server "$PM" '	a, b = string.match(text, "^signed (.-): (.*)$")' '	a, b = string.match(text, "^signedX (.-): (.*)$")'
mutate "chat changes money" server "$PS" '		local reply, source, reason = generate(st, s.userId, cs, model, company, filtered, now)' '		local reply, source, reason = generate(st, s.userId, cs, model, company, filtered, now); data.money -= 1'
mutate "phone overlaps the HUD column" garage "$PH" '	local rightEdge = hudW + m' '	local rightEdge = m'
mutate "no landscape phone on small screens" rich "$PH" '	local shapeLandscape = sp < 0.78' '	local shapeLandscape = false'
mutate "phone stays over the Computer" garage "$PC" '	Phone.setHidden(not company or hud == true or Computer.isOpen())' '	Phone.setHidden(not company or hud == true)'
mutate "inbox not read on open" rich "$SC" '	ctx.deps.markRead(keys) -- opening the inbox reads it' '	-- markRead removed'
mutate "old news counted as unread" rich "$PC" '		for _, m in newsList do read[m.key] = true end' ''
mutate "chat input not limited" rich "$SC" '			if cut then box.Text = string.sub(box.Text, 1, cut - 1) end' ''
mutate "talk panel does not close the phone" garage "$PC" '		if Controller.PANELS[child.Name] then Phone.close() end' ''
mutate "chat thread yanks the reader down" rich "$SC" '			stick = false -- the player scrolled up' '			stick = true'
mutate "chat thread does not follow new bubbles" rich "$SC" '	list:GetPropertyChangedSignal("AbsoluteSize"):Connect(follow)' ''
# review round 1
mutate "one player's error opens the global breaker" server "$PS" '				logFailure(user, now)' '				trip(breaker, now, Phone.BREAKER_BASE, Phone.BREAKER_MAX)'
mutate "no per-player breaker" server "$PS" '		trip(st.breaker, now, Phone.PLAYER_BREAKER_BASE, Phone.PLAYER_BREAKER_MAX)' ''
mutate "unavailable errors do not stop everybody" server "$PS" '			if not created or unavailable(err) then' '			if false then'
mutate "old ContextToken on a new generator" server "$PS" '		cs = { gen = nil, sig = sig, token = nil, turns = {}, n = if cs then cs.n else 0 }' '		cs = { gen = nil, sig = sig, token = if cs then cs.token else nil, turns = if cs then cs.turns else {}, n = if cs then cs.n else 0 }'
mutate "no recap when the token is lost" server "$PS" 'UserPrompt = if cs.token then text else PhoneMath.recapPrompt(cs.turns, text)' 'UserPrompt = text'
mutate "no missed-call notice from the server" server "$PS" '			fire(s, "PHONE_UPDATE", { what = "calls", call = callPayload(c) })' ''
mutate "PHONE_UPDATE without the new item" fixes "$PS" '	fire(s, "PHONE_UPDATE", { what = "calendar", item = entry })' '	fire(s, "PHONE_UPDATE", { what = "calendar" })'
mutate "office call opens Overview" server "$PS" 'open = "empire", section = "office" })' 'open = "empire" })'
mutate "phone shows all 40 log lines" server "$PM" 'PhoneMath.NEWS_SHOWN = 20 ' 'PhoneMath.NEWS_SHOWN = 40 '
mutate "public shuttle shown to a garage company" garage "$PM" 'if typeof(shuttle) == "table" and typeof(shuttle.at) == "number" and PhoneMath.abroadRelevant(e) then' 'if typeof(shuttle) == "table" and typeof(shuttle.at) == "number" then'
mutate "calendar converted with the live clock (jitter)" fixes "$PC" 'shuttle(clock), hotels(), anchor)' 'shuttle(clock), hotels(), nil)'
mutate "client never expires a ringing call" fixes "$PC" 'clock - c.at > (tonumber(c.ring) or PhoneMath.CALL_RING) then c.state = "missed" end' 'false then c.state = "missed" end'
mutate "thread bubbles keyed by list index" fixes "$SC" 'drawn[turn] = bubble(list, turn, tonumber(turn.id) or i)' 'drawn[turn] = bubble(list, turn, i)'
mutate "home rebuilt on every cash tick" fixes "$SC" 'v.todayLine or "", tostring(v.staff == 0), v.company,' 'v.todayLine or "", tostring(v.staff == 0), v.company, tostring(v.finance and v.finance.cash),'
mutate "gamepad selection not restored after a rebuild" fixes "$PH" '		if fallback then GuiService.SelectedObject = fallback end' '		GuiService.SelectedObject = nil'
mutate "a call takes over while typing" fixes "$PH" '		if current.name == "thread" or typing() then' '		if false then'
mutate "call pop-ups ignored while open" fixes "$PC" '		elseif settings.popups then' '		elseif true then'
mutate "draft not kept" fixes "$SC" '		ctx.deps.setDraft(id, box.Text)' ''
mutate "PHONE_UPDATE refetches not coalesced" fixes "$PC" '	if pending[kind] then return end' ''
mutate "no retry after RATE_LIMIT" fixes "$PC" '	if (err == "RATE_LIMIT" or err == "NETWORK") and attempt < Controller.FETCH_RETRIES then' '	if false then'
mutate "no arrival reports" fixes "$PC" '	arrivalsOf(e, deals, clock)' ''
mutate "flight choice does not close the phone" fixes "$PC" '	FlightChoice = true, ShuttleRide = true, HeliRide = true }' '	ShuttleRide = true, HeliRide = true }'
mutate "open phone under the shuttle pass" fixes "$PH" 'Phone.ORDER_OPEN = 28 ' 'Phone.ORDER_OPEN = 15 '
mutate "honesty label small print" fixes "$SC" '		local label = Kit.text(b, turn.label, 13, F.bold, if demo then C.warn else Theme.accent)' '		local label = Kit.text(b, turn.label, 11, F.bold, if demo then C.warn else Theme.accent)'
mutate "settings row not tappable" fixes "$SC" '		Kit.onClick(top, tg.flip)' ''
mutate "banner below full size on touch" touch "$PH" '	local bannerS = if touch then math.max(1, bs) else bs' '	local bannerS = bs'
mutate "phone over the phone button on touch" touch "$PH" '	if touch then rightEdge = math.max(rightEdge, right + bpx + m) end' ''
mutate "small call buttons" touch "$PH" 'Phone.CALL_BUTTON = 48 ' 'Phone.CALL_BUTTON = 42 '
mutate "flat 28 px navigation in landscape" touch "$PH" '		local navH = 36' '		local navH = if landscape then 28 else 36'
mutate "small Clear / header back targets" touch "$PK" 'UDim2.fromOffset(88, 44), UDim2.new(1, -4, 0.5, 0)' 'UDim2.fromOffset(80, 36), UDim2.new(1, -8, 0.5, 0)' 'UDim2.fromOffset(52, 44), UDim2.fromOffset(0, -2)' 'UDim2.fromOffset(48, 40), UDim2.fromOffset(2, 0)'
mutate "phone ignores the HUD's published lane" rich "$PH" '	return if typeof(w) == "number" and w > 0 then w else Phone.HUD_WIDTH' '	return Phone.HUD_WIDTH'
mutate "landscape phone never narrows (shrinks instead)" touch "$PH" 'local width = math.clamp(w / byHeight, Phone.LANDSCAPE_MIN_W, Phone.LANDSCAPE.X)' 'local width = Phone.LANDSCAPE.X'
mutate "layout does not follow a new LaneWidth" touch "$PH" '		frame:GetAttributeChangedSignal("LaneWidth"):Connect(function() applyLayout() end)' ''
mutate "landscape call buttons scroll away under the text" rich "$SC" '		local deciding = (c.state == "ringing" or c.state == "missed") and not result' '		local deciding = false'
echo "phone negative checks: $detected of $total mutations detected"
[ "$detected" -eq "$total" ]
