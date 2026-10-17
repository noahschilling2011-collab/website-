#!/usr/bin/env bash
# guests_jet: negative checks - each mutation of the sources must make the named suite FAIL (proves the tests
# detect it). Usage: tests/guests_jet/negative.sh [--no-world]   (--no-world skips the slow clearance mutation)
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
WORLD=1; [ "${1:-}" = "--no-world" ] && WORLD=0
OUT=out/guests_jet/negative; rm -rf "$OUT"; mkdir -p "$OUT"
pass=0; fail=0
mutate() { # name file python-old python-new suite
	local name="$1" file="$2" old="$3" new="$4" suite="$5"
	local SRC="$OUT/src_$name"; local GEN=harness/.gen_gj_neg_$name
	rm -rf "$SRC"; cp -r work/src "$SRC"
	if ! python3 - "$SRC/$file" "$old" "$new" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if old not in s:
    print("MUTATION TARGET NOT FOUND in " + p); sys.exit(2)
open(p, "w").write(s.replace(old, new, 1))
PY
	then echo "FAIL  $name: mutation did not apply"; fail=$((fail+1)); return; fi
	python3 harness/make_manifest.py --src "$SRC" --gen "$GEN" >/dev/null 2>&1
	local out
	case "$suite" in
		jet) out=$(cd tests/guests_jet && ../../tools/luau test_jet.luau -a "$(basename $GEN)" 2>&1);;
		guests) out=$(cd tests/guests_jet && ../../tools/luau test_guests.luau -a "$(basename $GEN)" 2>&1);;
		aircraft) out=$(bash tests/guests_jet/aircraft.sh --src "$SRC" 2>&1);;
		clearance) bash tests/guests_jet/world_dump.sh --src "$SRC" --out "$OUT/world_$name" >/dev/null 2>&1; out=$(python3 tests/guests_jet/clearance.py "$OUT/world_$name" 2>&1);;
	esac
	local summary; summary=$(echo "$out" | grep -E "passed, [0-9]+ failed" | tail -1)
	local nf; nf=$(echo "$summary" | sed -E 's/.* ([0-9]+) failed.*/\1/')
	if [ -n "$nf" ] && [ "$nf" -gt 0 ]; then
		echo "ok    $name -> $suite fails ($summary)"; echo "$out" | grep -E "^FAIL" | head -2 | sed 's/^/        /'; pass=$((pass+1))
	else
		echo "FAIL  $name: $suite did not detect the mutation ($summary)"; fail=$((fail+1))
	fi
	rm -rf "$SRC" "$GEN"
}
GPF=ReplicatedStorage/Shared/GuestPlan.module.luau
JSF=ServerScriptService/Server/Services/JetService.module.luau
JCF=StarterPlayer/StarterPlayerScripts/Client/Controllers/JetController.module.luau
JPF=ReplicatedStorage/Shared/JetPlan.module.luau
mutate corridor_in_wall "$GPF" 'for _,z in {79.6,86,122,126.5,140.5,154.5,168.5} do n("c0_"..z,-120,Y0,z) end' 'for _,z in {79.6,86,122,126.5,140.5,154.5,168.5} do n("c0_"..z,if z==126.5 then -128 else -120,Y0,z) end' guests
mutate no_room_cap "$GPF" 'return math.clamp(g,0,math.min(r,GP.HOTEL_CAP,#GP.HOTEL_ROOMS))' 'return math.max(g,0)' guests
mutate boarding_early "$GPF" 'local call=B0+4+(i-1)*3.6' 'local call=B0-40+(i-1)*3.6' guests
mutate seat_shared "$GPF" 'local bfSeat=GP.BREAKFAST_SEATS[perm(#GP.BREAKFAST_SEATS,"bf:"..plotSeed..":"..d)[g] or 1]' 'local bfSeat=GP.BREAKFAST_SEATS[1]' guests
mutate jet_for_everyone "$JSF" 'return s~=nil and typeof(s.data)=="table" and typeof(s.data.empire)=="table" and s.data.empire.jet==true' 'return s~=nil and typeof(s.data)=="table"' jet
mutate shared_hangar_clash "$JCF" 'if not st.flying then return st.parkedAt=="abroad" end' 'if not st.flying then return true end' jet
mutate arrival_misplaced "$JPF" 'local base=if dest=="abroad" then JP.ARRIVAL.abroad else JP.ARRIVAL.home' 'local base=if dest=="abroad" then JP.ARRIVAL.home else JP.ARRIVAL.home' jet
ACF=ReplicatedStorage/Shared/AircraftModel.module.luau
mutate arm_through_skin "$JCF" '	r.outerHidden=hide
	for _,p in r.outer do p.LocalTransparencyModifier=if hide or r.visible==false then 1 else 0 end' '	r.outerHidden=false
	for _,p in r.outer do p.LocalTransparencyModifier=if r.visible==false then 1 else 0 end' jet
mutate pilots_old_seats "$ACF" 'captain=CFrame.new(-1.05,5.75,-16.1),firstOfficer=CFrame.new(1.05,5.75,-16.1)' 'captain=CFrame.new(-1.15,6.2,-16.4),firstOfficer=CFrame.new(1.15,6.2,-16.4)' jet
# fix round (review_guests_jet)
mutate heli_sends_jet_home "$JSF" 'if trip and trip.to=="abroad" then return if trip.kind=="heli" then "abroad" else "flying" end' 'if trip and trip.to=="abroad" and trip.kind~="heli" then return "flying" end' jet
mutate no_ambient_window "$JPF" 'local r=spanAt(sp.rwy,roll);add("rwy",r[1],r[2])' 'local r=spanAt(sp.rwy,roll)' jet
mutate no_apron_window "$JPF" 'add("apron",spanAt(sp.apron,tl.duration)[1],tl.duration)' 'local _=0' jet
mutate departs_into_conflict "$JSF" '	if not clear then
		local later' '	if false then
		local later' jet
mutate empty_departs_into_conflict "$JSF" 'if not clear then j.retryAt=t+JetService.RETRY;return nil end' 'local _=clear' jet
mutate staff_leave_before_car "$JSF" 'if st.state==state and st.readyAt<=t and (founder or not itinHolds(j.userId,key)) then' 'if st.state==state and (founder or not itinHolds(j.userId,key)) then' jet
mutate same_arrival_spot "$JSF" 'if not taken then return cf end' 'if true then return cf end' jet
mutate leave_drops_jet "$JSF" '			if j.flight and flying(j,now()) then
				-- everyone near' '			if false then
				-- everyone near' jet
mutate staff_never_flown "$JSF" '		if #outsT>0 then
			local slot=freeSlot(j.userId,t)' '		if false then
			local slot=freeSlot(j.userId,t)' jet
mutate ride_covers_phone "$JCF" 'Jet.RIDE_ORDER=14' 'Jet.RIDE_ORDER=28' jet
mutate toast_says_vip_apron "$JCF" 'Your jet waits "..JP.slot(slot).where' 'Your jet waits "..JP.slot(1).where' jet
mutate guests_depend_on_n "$GPF" 'local eveningOk=eveningWant(plotSeed,g,d)' 'local eveningOk=eveningWant(plotSeed,g,d) and g<=math.ceil((_n or 12)*0.7)' guests
mutate airliner_changed "$ACF" 'circles={{y=13.7,r=7.2}},barrel={-49.4,33}' 'circles={{y=13.7,r=7.3}},barrel={-49.4,33}' aircraft
if [ $WORLD -eq 1 ]; then
	mutate jet_into_hangar_wall "$JPF" 'JP.HOME_PARK=CFrame.lookAt(v(-930,HY,HZ),v(-1000,HY,HZ))' 'JP.HOME_PARK=CFrame.lookAt(v(-980,HY,HZ),v(-1050,HY,HZ))' clearance
fi
rm -rf "$OUT"
echo "guests_jet_negative: $pass passed, $fail failed"
[ $fail -eq 0 ]
