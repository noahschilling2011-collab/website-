#!/usr/bin/env bash
# itinerary package: mutation checks - each mutation of the real sources must make a suite FAIL (proves the tests see it).
# Sources are copied to agents/itinerary/neg_src (work/src is never written). Usage: tests/itinerary/negative.sh [filter]
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
FILTER="${1:-}"
NEG=agents/itinerary/neg_src
GEN=.gen_itinerary_neg
caught=0; missed=0
mutate() { # name file suite(test file without .luau) scenario python-old python-new
  local name="$1" file="$2" suite="$3" sc="$4" old="$5" new="$6"
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then return; fi
  rm -rf "$NEG"; cp -r work/src "$NEG"
  python3 - "$NEG/$file" "$old" "$new" <<'PY' || { echo "MUTATION NOT APPLIED: $name"; missed=$((missed+1)); return; }
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if old not in s:
    sys.exit(1)
open(p, "w").write(s.replace(old, new, 1))
PY
  python3 harness/make_manifest.py --src "$NEG" --gen "harness/$GEN" >/dev/null || return
  local out r
  out=$(cd tests/itinerary && timeout 1800 ../../tools/luau "$suite.luau" -a "$GEN" $sc 2>&1); r=$?
  local line; line=$(echo "$out" | grep -E "passed, [0-9]+ failed" | tail -n 1)
  if [ $r -ne 0 ] || ! echo "$line" | grep -q " 0 failed"; then
    caught=$((caught+1)); printf "caught  %-34s %s\n" "$name" "$line"
  else
    missed=$((missed+1)); printf "MISSED  %-34s %s\n" "$name" "$line"
  fi
}
IMF=ReplicatedStorage/Shared/ItineraryMath.module.luau
SV=ServerScriptService/Server/Services/ItineraryService.module.luau
CT=StarterPlayer/StarterPlayerScripts/Client/Controllers/ItineraryController.module.luau
SH=ServerScriptService/Server/Services/ShuttleService.module.luau
CS=ServerScriptService/Server/Services/CityService.module.luau

# ItineraryMath
mutate renew_needs_founder "$IMF" test_math "" 'or trip.kind ~= "sign" then return false, nil end' 'then return false, nil end'
mutate no_companion_cap "$IMF" test_math "" '		if #companions >= IM.MAX_COMPANIONS then break end' '		local _ = companions'
mutate return_before_visit_end "$IMF" test_math "" '	local earliest = math.max(input.backAt, plan.hotelAt)' '	local earliest = plan.hotelAt'
mutate queued_driver_lies "$IMF" test_math "" '		return "All cars are out - the next one picks you up at " .. where .. "."' '		return "Your driver is waiting at " .. where .. " in about " .. IM.mmss(d.eta or 0) .. "."'
mutate wrong_field_rep "$IMF" test_math "" 'local rep = if k <= reps then profileOf(e, "marketer", k) else nil' 'local rep = if k <= reps then profileOf(e, "marketer", k + 1) else nil'
mutate missed_shuttle_leg "$IMF" test_math "" '			local flight, departs, boardEnd, arrives, legStart = IM.shuttleLeg("out", carTo + IM.WALK_GATE)' '			local flight, departs, boardEnd, arrives, legStart = IM.shuttleLeg("out", carTo - 400)'
# review round: honest colleague lines, short call, one label, night times, timed pick-up, chip action
mutate label_wait_at_gate_always "$IMF" test_math "" '(if n > 0 and together then " · " .. names .. " wait at the gate" elseif n > 0' '(if n > 0 then " · " .. names .. " wait at the gate" elseif n > 0'
mutate call_with_return_again "$IMF" test_math "" '.. IM.driverText(plan.driver, "abroad", at) .. " " .. close' '.. IM.driverText(plan.driver, "abroad", at) .. " Return: " .. tostring(plan.returnFlight) .. " " .. IM.atText(e, now, plan.returnAt or now) .. " (or earlier, if you like). " .. close'
mutate two_decline_labels "$IMF" test_math "" 'decline = "Not this time", cancel' 'decline = "Not now", cancel'
mutate night_reads_as_morning "$IMF" test_math "" '	if h < 8 then
		if day == today' '	if false then
		if day == today'
mutate no_timed_pickup "$IMF" test_review timed 'and input.schedule ~= false and shift > IM.PICKUP_SLACK then' 'and false then'
mutate chip_without_action "$IMF" test_client "" '			b.action = "Press Start meeting at the table"' '			b.action = ""'
# fix round 2: honest companion tags in the calendar / offer banner, the jet has no gate
mutate calendar_car_claims_with "$IMF" test_math "" 'elseif plan.ahead then " · " .. names .. " went ahead" else with' 'else with'
mutate offer_tag_with_always "$IMF" test_math "" '		elseif pl and pl.ahead then " · " .. names .. (if pl.aheadBy == "air" then " fly ahead" else " went ahead")' '		elseif false then ""'
mutate jet_ahead_at_gate "$IMF" test_math "" 'elseif plan.how == "jet" then " at our jet."' 'elseif false then " at our jet."'
# ItineraryService
mutate charges_money "$SV" test_service abroad '	it.booking = true' '	it.booking = true; pcall(function() (require :: any)(script.Parent.EconomyService).spend(it.s, 100, "travel") end)'
mutate builtin_calls_kept "$SV" test_service abroad '	Phone.BUILTIN_TRIP_CALLS = false' '	Phone.BUILTIN_TRIP_CALLS = true'
mutate offer_without_delay "$SV" test_service abroad 'ItineraryService.OFFER_DELAY = 1.5' 'ItineraryService.OFFER_DELAY = 0'
mutate joined_not_seen "$SV" test_service abroad '		if trip and trip.joined == true then
			it.joinedAt = t' '		if false then
			it.joinedAt = t'
mutate calendar_left_behind "$SV" test_service abroad '	removePrompt(it)
	clearCalendar(it)
	local f = it.folder' '	removePrompt(it)
	local f = it.folder'
mutate checkin_from_anywhere "$SV" test_service abroad ' or (p - part.Position).Magnitude > ItineraryService.PROMPT_RANGE then return end' ' then return end'
mutate notify_every_step "$SV" test_service abroad '	if sig ~= rec.lastSig then' '	if true then'
mutate countdown_never_starts "$SV" test_service offer '	if o.countdownEnd and t >= o.countdownEnd then' '	if false then'
mutate booking_not_dropped "$SV" test_service jet '		pcall(Shuttle.unbook, player)' '		local _ = 0'
mutate queue_ignores_time_left "$SV" test_service edge 'elseif t and not rec.declined[k] and IM.left(e, t) >= IM.QUEUE_MIN_LEFT then' 'elseif t and not rec.declined[k] then'
mutate trip_over_ignored "$SV" test_service edge '			finish(it, "over", "The " .. it.client.name .. " visit is over - no need to travel any more.")
			return' '			local _ = 0'
mutate remote_key_unchecked "$SV" test_service remote '	if p.key ~= nil and IM.validKey(p.key) == nil then return { ok = false, err = "BAD_INPUT" } end' ''
# review round (ItineraryService)
mutate offer_does_not_hold "$SV" test_review offerwait '	if o then return o.key == tripKey and o.tier == "abroad" and o.plan.from == "home" and #o.plan.companions > 0 end' '	if o then return false end'
mutate stale_decline_claims_alone "$SV" test_review stalecall '	if it and (key == nil or it.key == key) then
		return' '	if false then
		return'
mutate abroad_start_double_presence "$SV" test_review abroadstart '	if on and it.joinAt and it.joinAt > it.showAt then it.showAt = it.joinAt end' ''
mutate same_chairs "$SV" test_review two '	if not it.meetingOn then it.seatSet = seatSetFor(it) end' '	it.seatSet = 1'
mutate team_vanishes_at_hotel "$SV" test_service abroad '	if it.meetingOn then it.meetingEnded = it.meetingEnded or now() end
	it.arrivedAt = nil
	it.room = nil' '	it.meetingOn = false
	it.arrivedAt = nil
	it.room = nil'
mutate no_deboard_pause "$SV" test_service abroad '			elseif withThem then
				-- the colleagues walk off' '			elseif false then
				-- the colleagues walk off'
mutate queued_eta_dropped "$SV" test_review garage 'eta = if queued then queuedEta(player, pickup.id, plot) else eta' 'eta = if queued then nil else eta'
mutate go_spam_folders "$SV" test_service remote '	if rec.goAt and t0 - rec.goAt < ItineraryService.GO_GAP and t0 >= rec.goAt then' '	if false then'
mutate status_every_step "$SV" test_review perf 'ItineraryService.STATUS_POLL = 1' 'ItineraryService.STATUS_POLL = 0'
# ShuttleService (additive company booking)
mutate booking_not_free "$SH" test_service abroad 'tickets[player.UserId]={to=destination,price=0,session=s,at=t,prepaid=true,companions=companions,trip=tripKey}' 'tickets[player.UserId]={to=destination,price=1,session=s,at=t,prepaid=true,companions=companions,trip=tripKey}'
mutate race_flies_ahead "$SH" test_review race 'and not held[key] and not itinHolds(player.UserId,t.key) then' 'and not held[key] then'
mutate cabin_without_colleagues "$SH" test_review cabin '	boardCompanions(ticket,player,st)' ''
mutate paid_ticket_not_refunded "$SH" test_review paidticket '			refund(held.session or s,held.price)' ''
mutate back_leg_ignores_holds "$SH" test_review overhold '			if owner and tk and itinHolds(tonumber(owner) or 0,tk) then continue end -- ... or will (his itinerary)' ''
mutate banner_go_keeps_call "$SV" test_review stalecall '	endCall(rec, offered)' ''
# CityService (meeting listeners)
mutate meeting_listeners_off "$CS" test_service abroad 'for _,fn in table.clone(meetingFns) do' 'for _,fn in {} do'
# ItineraryController
mutate cancel_without_confirm "$CT" test_client "" '						if os.clock() > entry.confirmUntil then' '						if false then'
mutate followers_ignore_showat "$CT" test_client "" '(typeof(showAt) ~= "number" or t >= showAt)' 'true'
mutate followers_while_anchored "$CT" test_client "" 'and r and not r.Anchored and' 'and r and'
mutate two_cancel_buttons "$CT" test_client "" '	return b.compact or rideShown' '	return b.compact'
mutate offer_folds_on_phone "$CT" test_client "" '	if v.state == "offer" or v.state == "countdown" then return false end
	if userToggled' '	if userToggled'
# review round (ItineraryController)
mutate followers_at_his_height "$CT" test_client "" '			local y = point.Y
			local gy = rg.groundY' '			local y = p.Y
			local gy = rg.groundY'
mutate followers_jump_with_him "$CT" test_client "" '			if gy and gy > point.Y - 6 and gy < point.Y + 3 then y = gy end' ''
mutate cap_counts_founders "$CT" test_client "" '			if groups[uid] and not groups[uid].leaving or rigs + n <= Controller.MAX_FOLLOWERS then
				follow[uid] = f
				rigs += n' '			if true then
				follow[uid] = f
				rigs += 1'
mutate pop_in "$CT" test_client "" '		alpha = 1, groundY = nil' '		alpha = 0, groundY = nil'
mutate vanish_instead_of_fade "$CT" test_client "" '		else
			leaveGroup(g, "fade")
		end' '		else
			dropGroup(uid)
		end'
mutate no_boarding_walk "$CT" test_client "" '			leaveGroup(g, "board")' '			leaveGroup(g, "fade")'
mutate no_pose_lod "$CT" test_client "" '	if d > Controller.POSE_FAR then return end' ''
mutate teams_share_chairs "$CT" test_client "" '		local seats = IM.seatsFor(spot, set)
		local tm: Team' '		local seats = spot.clients
		local tm: Team'
rm -rf "$NEG"
echo "itinerary negative checks: $caught caught, $missed missed"
[ $missed -eq 0 ]
