#!/usr/bin/env bash
# drivers package: mutation checks - each mutation of the real sources must make a suite FAIL (proves the tests see it).
# Sources are copied to agents/drivers/neg_src (work/src is never written). Usage: tests/drivers/negative.sh [filter]
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
FILTER="${1:-}"
NEG=agents/drivers/neg_src
GEN=.gen_drivers_neg
caught=0; missed=0
mutate() { # name file suite python-old python-new
  local name="$1" file="$2" suite="$3" old="$4" new="$5"
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
  case "$suite" in
    clearance) out=$(bash tests/drivers/clearance.sh "$GEN" 2>&1); r=$? ;;
    *) out=$(cd tests/drivers && timeout 900 ../../tools/luau "$suite.luau" -a "$GEN" 2>&1); r=$? ;;
  esac
  local line; line=$(echo "$out" | grep -E "passed, [0-9]+ failed" | tail -n 1)
  if [ $r -ne 0 ] || ! echo "$line" | grep -q " 0 failed"; then
    caught=$((caught+1)); printf "caught  %-34s %s\n" "$name" "$line"
  else
    missed=$((missed+1)); printf "MISSED  %-34s %s\n" "$name" "$line"
  fi
}
P=ReplicatedStorage/Shared/DrivePlan.module.luau
D=ServerScriptService/Server/Services/DriverService.module.luau
C=StarterPlayer/StarterPlayerScripts/Client/Controllers/DriveController.module.luau
V=ServerScriptService/Server/Services/VehicleService.module.luau
E=ServerScriptService/Server/Services/EmployeeRigDesign.module.luau

mutate drivers_rule_off_by_one "$P" test_plan 'elseif stage >= Ops.DRIVER.from then 1' 'elseif stage > Ops.DRIVER.from then 1'
mutate drivers_rule_service "$P" test_service 'if stage >= Ops.DRIVER.more then 2' 'if stage >= Ops.DRIVER.more + 1 then 2'
mutate lane_outer_lane "$P" clearance '	return width / 4' '	return if width >= 44 then 0.75 * width / 2 else width / 4'
mutate uturn_swing_wide "$P" clearance 'Drive.UTURN_SWING = 10' 'Drive.UTURN_SWING = 45'
mutate kerbside_on_road "$P" test_plan '	for _, along in { 0, -16, 16, -32, 32, -48, 48 } do' '	for _, along in {} do'
mutate seat_order_swapped "$P" test_client 'Drive.SEAT_ORDER = { "driver", "rearR", "rearL", "front" }' 'Drive.SEAT_ORDER = { "driver", "rearL", "rearR", "front" }'
mutate decode_accepts_bad_who "$P" test_plan '		if code ~= "" and not Drive.OCCUPANTS[code] then return false end' '		local _ = code'
mutate no_hold_below_car "$D" test_service '	holdAt(r, carCF.Position)
	clearPrompt(r)' '	clearPrompt(r)'
mutate founder_stays_in_car "$D" test_service '	strip(r, ri, { R = true })
	local s = Session.get(player)' '	publishRide(r)
	local s = Session.get(player)'
mutate arrive_event_twice "$D" test_service '	arrivedEvent:Fire(player, r.id, placeId)' '	arrivedEvent:Fire(player, r.id, placeId); arrivedEvent:Fire(player, r.id, placeId)'
mutate busy_driver_ignored "$D" test_service '	for i = 1, c.drivers do if not busy[i] then return i end end
	return nil' '	return if c.drivers > 0 then 1 else nil'
mutate no_request_cooldown "$D" test_service 'DriverService.REQUEST_GAP = 3' 'DriverService.REQUEST_GAP = 0'
mutate barrier_never_opens "$D" test_service 'DriverService.BARRIER_LEAD = 3' 'DriverService.BARRIER_LEAD = -100'
mutate garage_stage_text "$D" test_service 'text = "Your first driver joins at the " .. stageName(Drive.FIRST_DRIVER_STAGE)' 'text = "Your first driver joins at the " .. stageName(1)'
mutate wait_never_expires "$D" test_service '			if t >= r.waitUntil then' '			if t >= r.waitUntil + 1e9 then'
mutate cancel_midride_no_kerb "$D" test_service '		if pose then at = freeSpot(pose.cf, r.zone, r.plot) end' '		local _ = pose'
mutate queue_eta_ignores_busy "$D" test_service '	local eta = math.max(0, soonest - t) + comingSeconds(pickup.id, plot, math.max(t, soonest))' '	local eta = comingSeconds(pickup.id, plot)'
mutate queued_cancel_keeps_hud "$D" test_service 'if c and c.queue then clearQueued(c.queue.player); c.queue = nil' 'if c and c.queue then c.queue = nil'
mutate field_rides_off "$D" test_service '			local ok, res = pcall(fieldRide, c, key, trip, who, false)' '			local ok, res = true, nil'
mutate client_no_camera_follow "$C" test_client '			if cam.CameraSubject ~= car.focus then cam.CameraSubject = car.focus end' '			local _ = 0'
mutate client_post_while_busy "$C" test_client '			if busyMap[i] then continue end' '			local _ = busyMap[i]'
mutate client_board_everywhere "$C" test_client '		showBoard = near' '		showBoard = true'
mutate client_companions_in_lane "$C" test_client '			local at = if standPlace then standPlace.door' '			local at = if false and standPlace then standPlace.door'
mutate vehicle_lend_keeps_car "$V" test_service '	clear(player.UserId)
	return id' '	return id'
mutate driver_without_cap "$E" test_service ' if uniform and uniform.driverCap and fits(3) then' ' if false and uniform and uniform.driverCap and fits(3) then'
# ---- review round 1: every fix must be seen by a test
mutate r1_door_delay_hidden "$C" test_review_client '	-- "before": parked at the start of the first leg' '	if pose and pose.phase == "before" then return nil end
	-- "before": parked at the start of the first leg'
mutate r2_door_delay_cancel_rides_on "$D" test_review '	if k and t < r.segs[k].t0 then
		local segs: { Drive.Seg } = {}' '	if false then
		local segs: { Drive.Seg } = {}'
mutate r2_rider_kept_after_leaving "$D" test_review '	release(r, at)
	r.dropped = true
	clearRider(r)' '	release(r, at)
	r.dropped = true'
mutate r3_stand_double_booking "$D" test_review '		if standState == "idle" then return 0, "stand" end' '		if true then return 0, "stand" end'
mutate rB_idle_limo_inside_moving "$C" test_review_client '	if not near or not stand or (standState ~= nil and standState ~= "idle") then' '	if not near or not stand then'
mutate r4_no_pickup_at_shuttle_arrival "$P" test_review '		for _, rect in Drive.PM_STAND_AREA do' '		for _, rect in {} do'
mutate r5_sheet_bookable_without_pickup "$D" test_review '		if not sh.pickup then' '		if false then'
mutate r6_ride_survives_other_city "$D" test_review '		if rider and (r.state == "coming" or r.state == "waiting") and zoneOf(rider) ~= r.zone then' '		if false then'
mutate r7_second_car_for_rep "$D" test_service '			local ok, how, after = pcall(endOutbound, c, info)' '			local ok, how, after = true, "none", nil'
mutate r8_reps_drive_themselves "$D" test_review '	local d = freeDriver(c)
	if not d then return nil end
	local t = now()
	local plot = c.plot' '	local d = freeDriver(c) or 0
	local t = now()
	local plot = c.plot'
mutate r9_legs_per_plot "$P" test_review '	local perPlot = string.sub(fromId, 1, 3) == "hq_" or string.sub(toId, 1, 3) == "hq_"' '	local perPlot = true'
mutate r10_fast_limo "$P" test_plan '		for i, cl in classes do if cl == "road" then classes[i] = "metro" end end' '		local _ = classes'
mutate r11_one_bucket "$D" test_review '		local kind = if op == "status" or op == "places" then "read" else "write"' '		local kind = "write"'
mutate r12_queue_old_pickup "$D" test_review '			q.pickup = here.id
		end
	end
	local ok, res = pcall(startHome, c, q, d)' '			local _ = here
		end
	end
	local ok, res = pcall(startHome, c, q, d)'
mutate r13_leave_destroys_cars "$D" test_review '	local any = next(c.rides) ~= nil' '	local any = false'
mutate r14_spot_ignores_props "$D" test_review '		if ok and typeof(hits) == "table" and #hits == 0 then return spot end' '		if ok then return spot end'
mutate rA_seated_full_size "$C" test_review_client '					if math.abs(sc - 1) > 1e-3 then pcall(function() (s :: Seat).model:ScaleTo(sc) end) end' '					local _ = sc'
mutate rA_arms_swing_out "$C" test_review_client 'DriveController.ARMS = { driver = { 1.25, 0 }, passenger = { 0.62, 0 } }' 'DriveController.ARMS = { driver = { 1.25, -0.5 }, passenger = { 0.62, -0.5 } }'
mutate rC_hud_under_toast "$C" test_review_client '	local target = DriveController.hudTop(toastBottom(h.root), h.scale.Scale)' '	local target = 10'
mutate rC_toast_vs_screengui "$C" test_review_client '	local target = DriveController.hudTop(toastBottom(h.root), h.scale.Scale)' '	local target = DriveController.hudTop(toastBottom(h.gui :: any), h.scale.Scale)'
mutate rD_no_marker "$C" test_review_client '	local show = v ~= nil and car ~= nil and v.folder:GetAttribute("State") == "waiting"' '	local show = false'
mutate rE_small_touch "$C" test_review_client '	if compact then return { h = 96, btn = 72,' '	if compact then return { h = 96, btn = 48,'
mutate rF_head_in_view "$C" test_review_client '					d.LocalTransparencyModifier = 1' '					d.LocalTransparencyModifier = 0'
mutate rH_no_idle_car "$C" test_review_client '		if garageBusy[company :: Folder] then continue end' '		if true then continue end'
mutate rH_idle_lights_on "$C" test_review_client '			lightsOff(built.model)' '			local _ = lightsOff'
mutate rH_car_pops "$C" test_review_client '	if at and car.speed < 0.5 and not atStand' '	if false and at and car.speed < 0.5 and not atStand'
mutate r8_passengers_vanish "$C" test_review_client '	if pose.phase ~= "waiting" or pose.index < 1 then return pose.who, {}, nil end' '	if true then return pose.who, {}, nil end'
mutate r9_decode_far_rides "$C" test_review_client '		local pose = if own or not farFrom(v, cam) then poseOf(v, time) else nil' '		local pose = poseOf(v, time)'
mutate night_post "$C" test_review_client '	local onPost = Drive.onPost(t)' '	local onPost = true'
mutate mesh_wheelbase "$C" test_review_client '	if look == "limo" and findMesh() then return MESH.wheelbase end' '	local _ = MESH'
mutate mesh_interior_always "$C" test_review_client '	local hide = dist > MESH.far' '	local hide = false'
mutate alighted_face_car "$C" test_review_client '			if standPlace and gotOut[s.code] then' '			if false then'
rm -rf "$NEG"
echo "drivers_negative: $caught passed, $missed failed"
[ $missed -eq 0 ]
