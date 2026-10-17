#!/usr/bin/env bash
# Negative checks for the airport package: tests/airport/test_airport.luau must FAIL on deliberate mutations
# of AirportBuilder (private trees under agents/airport/neg_*, never work/src). Prints one line per mutation:
# "CAUGHT <name>: <first FAIL line>" or "MISSED <name>"; exit 1 if any mutation is missed.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
F=ServerScriptService/Server/Services/AirportBuilder.module.luau
missed=0
neg() { # name, sed expression, expected FAIL substring
  local name="$1" expr="$2" want="$3" tree="agents/airport/neg_$1"
  rm -rf "$tree"; cp -r work/src "$tree"
  sed -i "$expr" "$tree/$F"
  grep -q "NEGMARK" "$tree/$F" || { echo "MISSED $name (mutation did not apply)"; missed=1; rm -rf "$tree"; return; }
  python3 harness/make_manifest.py --src "$tree" --gen "harness/.gen_airport_neg_$name" >/dev/null
  local out; out=$(tools/luau tests/airport/test_airport.luau -a ".gen_airport_neg_$name" 2>&1 | grep -E "^FAIL|^ERROR")
  local hit; hit=$(echo "$out" | grep -F "$want" | head -1)
  if [ -n "$hit" ]; then echo "CAUGHT $name: ${hit:0:150}"; else echo "MISSED $name (wanted '$want'; got: $(echo "$out" | head -1))"; missed=1; fi
  rm -rf "$tree" "harness/.gen_airport_neg_$name"
}
neg bridge_gap 's/local c=door+normal\*(0.6+4.5)/local c=door+normal*(3+4.5) -- NEGMARK/' "cab opening"
neg door_centre 's/return door.Position-Vector3.new(0,half,0),n.Unit/return door.Position,n.Unit -- NEGMARK/' "door sill"
neg door_shut 's/local DOORS={-150,0,150,A.arrivalsDoor}/local DOORS={-150,150,A.arrivalsDoor} -- NEGMARK/' "doors + arrivals exit open"
neg no_jet_marker 's/local marker=invisible(mk(jf,"CompanyJetStand"/local marker=invisible(mk(jf,"JetStandX"--[[NEGMARK]]/' "CompanyJetStand marker"
neg post_in_desk 's/airportPost(m,"lounge",Vector3.new(-252.5,F+3,2492)/airportPost(m,"lounge",Vector3.new(-246.5,F+3,2492)--[[NEGMARK]]/' "walkable"
neg brand 's/"SKYLINE RESTAURANT"/"STARBUCKS"--[[NEGMARK]]/' "brand names"
neg shadow 's/if decor then p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false end/if decor then p.CanCollide=false;p.CanTouch=false;p.CanQuery=false end -- NEGMARK/' "casts no shadow"
neg no_lounge_tag 's/m:AddTag("BusinessLounge");/-- NEGMARK /' "BusinessLounge model"
neg checkin_attr 's/q:SetAttribute("CityAction","checkin");q:SetAttribute("FlightTo","abroad")/q:SetAttribute("CityAction","checkin") -- NEGMARK/' "check-in counters"
neg shuttle_gse 's/if i==A.shuttleStand then/if false then -- NEGMARK/' "shuttle stand A1"
neg edge_slit 's/local EDGE=City.HARBOUR.x2 -- 1150/local EDGE=City.HARBOUR.x2+4 -- NEGMARK/' "map edge"
neg old_board 's/"BOARDING TIMES AT GATE "..SHUTTLE_GATE,/"09:25  PM 103  PORT MERIDIAN   A2  ON TIME", -- NEGMARK/' "flight info"
neg one_pad 's/local n=math.max(1,math.floor((x2-x1)\/2.6))/local n=1 -- NEGMARK/' "CityPlan.AIRPORT.seats"
neg tray_clip 's/local tz=if t0>2470 then 2475 else 2470/local tz=2470 -- NEGMARK/' "tray stacks"
neg catering_up 's/vehicle(gse,at(gx+60,2563,0),"Catering",nil,true)/vehicle(gse,at(gx+60,2563,0),"Catering") -- NEGMARK/' "staging box"
exit $missed
