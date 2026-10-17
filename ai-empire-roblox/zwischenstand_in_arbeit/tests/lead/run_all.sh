#!/usr/bin/env bash
# Runs every headless test suite of the project and prints one summary line per suite.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
# RUNALL_TAG=<name>: run in a private sandbox copy (generated test trees never race with other agents)
# RUNALL_SRC=<dir>: test that source tree instead of work/src (sandbox mode only)
if [ -n "${RUNALL_TAG:-}" ]; then
  SB="$ROOT/agents/$RUNALL_TAG/sandbox"
  python3 "$ROOT/tests/lead/sandbox.py" "$ROOT" "$SB" ${RUNALL_SRC:-} || exit 1
  cd "$SB"
fi
L=tools/luau
run() { local name="$1"; shift; local out; out=$("$@" 2>&1); local rc=$?; printf "%-22s rc=%s  %s\n" "$name" "$rc" "$(echo "$out" | grep -E "passed|failed|SUMMARY|orphanDoors|WORLD CHECK|ENTRANCES|reachable" | tail -n 1)"; }
python3 harness/make_manifest.py --src work/src --gen harness/.gen_lift >/dev/null
python3 harness/make_manifest.py --src work/src --gen harness/.gen_leadtest >/dev/null
python3 tests/gen_layout_test.py >/dev/null 2>&1
python3 tests/gen_door_test.py >/dev/null 2>&1
python3 people_harness/mkharness.py >/dev/null
python3 staff_harness/mkharness.py >/dev/null
run layout            $L tests/layout_test.luau
run door_service      $L tests/door_service_test.luau
run lift_logic        $L tests/lift_logic.luau
run lift_service      $L tests/lift_service.luau
run lift_ui           $L tests/lift_ui.luau
run snapshot          $L tests/lead/test_snapshot.luau
python3 harness/make_manifest.py --src work/src --gen harness/.gen_net >/dev/null
run net_patch         $L tests/net/test_patch.luau
run net               $L tests/net/test_net.luau
run net_e2e           $L tests/net/test_e2e.luau
run people            $L people_harness/test_people.luau
run people_client     $L people_harness/test_client.luau
run people_real       $L people_harness/test_real.luau
for t in 1 2 3 4; do run "staff_t$t" $L staff_harness/test_staff.luau -a "$t"; done
run staff_sim         $L staff_harness/test_sim.luau -a 4
python3 harness/make_manifest.py --gen agents/screens/gen >/dev/null
run screens_fake      $L agents/screens/test_screens.luau -a fake
run screens_real      $L agents/screens/test_screens.luau -a real
python3 harness/make_manifest.py --src work/src --gen harness/.gen_talk >/dev/null
run talk_dialogue     $L tests/talk/test_dialogue.luau -a .gen_talk --quiet
run talk              $L tests/talk/test_talk.luau -a .gen_talk
run talk_client       $L tests/talk/test_client.luau -a .gen_talk
run talk_real         $L tests/talk/test_real.luau -a .gen_talk 2
python3 tests/life/mkharness.py >/dev/null
run life_props        $L tests/life/test_props.luau
run life_client       $L tests/life/test_client.luau
for t in 1 2 3 4; do run "life_t$t" $L tests/life/test_life.luau -a "$t"; done
python3 harness/make_manifest.py --src work/src --gen harness/.gen_shop >/dev/null
run shop              bash -c 'cd tests/shop && ../../tools/luau test_shop.luau -a .gen_shop'
run shop_client       bash -c 'cd tests/shop && ../../tools/luau test_client.luau -a .gen_shop'
# shop package round 3 (requests/onboarding.md #6, added by onbshop_fix1): SHOP_SPEC catalogue texts come from $ROOT/design
python3 harness/make_manifest.py --src work/src --gen harness/.gen_shop2 >/dev/null
python3 tests/shop2/spec_texts.py "$ROOT/design/SHOP_SPEC.md" work/src tests/shop2/.spec_texts.luau >/dev/null
for t in server math client; do run "shop2_$t" bash -c "cd tests/shop2 && ../../tools/luau test_$t.luau -a .gen_shop2"; done
# menu package ("First steps" guide, Menu shell, Home; ONBOARDING_SPEC A + B, added by onbshop_fix1)
python3 harness/make_manifest.py --src work/src --gen harness/.gen_menu >/dev/null
python3 tests/menu/routes.py >/dev/null
run menu_server       bash -c "cd tests/menu && ../../tools/luau test_server.luau -a .gen_menu"
run menu_client_guide bash -c "cd tests/menu && ../../tools/luau test_client.luau -a .gen_menu guide"
run menu_client_menu  bash -c "cd tests/menu && ../../tools/luau test_client.luau -a .gen_menu menu"
python3 harness/make_manifest.py --src work/src --gen harness/.gen_world >/dev/null
for t in cityplan build travel vehicle client; do run "world_$t" $L tests/world/test_$t.luau -a .gen_world; done
python3 tests/buildings/mkharness.py >/dev/null
run buildings_tier0   $L tests/buildings/test_tier0.luau
run buildings_build   $L tests/buildings/test_build.luau -a all
run buildings_admin   $L tests/buildings/test_admin.luau
python3 harness/make_manifest.py --src work/src --gen harness/.gen_corefix >/dev/null
for t in ops b2b service migration net; do run "econ_$t" bash -c "cd tests/econ && ../../tools/luau test_$t.luau -a .gen_corefix"; done
run corefix           bash -c "cd tests/corefix && ../../tools/luau test_corefix.luau -a .gen_corefix"
run corefix_ui        bash -c "cd tests/corefix && ../../tools/luau test_ui.luau -a .gen_corefix"
run models            bash tests/models/run.sh
# ---- phase-2 world + round-2a package suites (added by integrate, 2026-10-10; commands from the packages' requests)
# airport (airport.md / flight.md #1): City Airport build, budgets, markers, walk graph
python3 harness/make_manifest.py --src work/src --gen harness/.gen_airport >/dev/null
run airport           $L tests/airport/test_airport.luau -a .gen_airport
# metro (metro.md #1): Port Meridian plan/build, client city life, walkers vs scenery, traffic stress (~3 min)
python3 harness/make_manifest.py --src work/src --gen harness/.gen_metro >/dev/null
for t in plan build life paths; do run "metro_$t" $L tests/metro/test_$t.luau -a .gen_metro; done
run metro_stress      $L tests/metro/stress_traffic.luau -a .gen_metro 3
# flight (flight.md #8): FlightPlan, ShuttleService, client controllers, aircraft; hull clearance sweep vs the built world
python3 harness/make_manifest.py --src work/src --gen harness/.gen_flight >/dev/null
for t in plan shuttle client aircraft; do run "flight_$t" $L tests/flight/test_$t.luau -a .gen_flight; done
run flight_clearance  bash tests/flight/run.sh --clearance-only
# shared world dump (airport.md #1/#8, metro.md #2): per-zone budgets, holes, map edge, entrances, metro walkability
run world_check       bash agents/airport/world_dump.sh --out out/runall_world
run world_entrances   python3 agents/world/entrances.py out/runall_world/world_dump.json
run metro_reach       python3 tests/metro/reach.py out/runall_world/world_dump.json
# hotelpolish (guest house: tiers 2-4 + baseline harness builds, geometry, GUI pixel density)
run hotelpolish       bash tests/hotelpolish/run.sh
# staffops (staffops.md #4; ~12 min)
python3 tests/staffops/mkharness.py >/dev/null
for t in clock absence night ops apprentice academy rack nightfault garage beacon arrival talk client perf; do run "staffops_$t" $L tests/staffops/test_staffops.luau -a "$t"; done
# phone (phone.md #2)
python3 harness/make_manifest.py --src work/src --gen harness/.gen_phone >/dev/null
run phone             bash -c "cd tests/phone && ../../tools/luau test_phone.luau -a .gen_phone"
for st in garage rich fixes touch; do run "phone_ui_$st" bash -c "cd tests/phone && ../../tools/luau test_ui.luau -a .gen_phone $st"; done
# apps (apps.md #3): HUD Next goal, Company/Hardware apps, briefing, screens; 6 UI + 3 server + 9 adversarial states
python3 harness/make_manifest.py --src work/src --gen harness/.gen_apps >/dev/null
for st in garage client save mid rich phone; do run "apps_ui_$st" bash -c "cd tests/apps && ../../tools/luau test_ui.luau -a .gen_apps $st"; done
for st in garage mid rich; do run "apps_server_$st" bash -c "cd tests/apps && ../../tools/luau test_server.luau -a .gen_apps $st"; done
for sc in garage_edge stage5 rackfull oldsave many spam midnight broke hr; do run "apps_adv_$sc" bash -c "cd tests/apps && ../../tools/luau test_adv.luau -a .gen_apps $sc"; done
# ---- round-2b package suites (added by verify2b, 2026-10-17; commands from design/requests/{drivers,guests_jet,itinerary}.md)
# drivers (drivers.md #2): DrivePlan, DriverService, DriveController, review scenarios R1-R8 / V1-V4, car clearance sweep
python3 harness/make_manifest.py --src work/src --gen harness/.gen_drivers >/dev/null
run drivers_plan      bash -c "cd tests/drivers && ../../tools/luau test_plan.luau -a .gen_drivers"
run drivers_service   bash -c "cd tests/drivers && ../../tools/luau test_service.luau -a .gen_drivers"
run drivers_client    bash -c "cd tests/drivers && ../../tools/luau test_client.luau -a .gen_drivers"
run drivers_review    bash -c "cd tests/drivers && ../../tools/luau test_review.luau -a .gen_drivers"
run drivers_review_cl bash -c "cd tests/drivers && ../../tools/luau test_review_client.luau -a .gen_drivers"
run drivers_clearance bash tests/drivers/clearance.sh
# guests_jet (guests_jet.md #1): company jet (JetService + JetController + the separation sweep), hotel guests +
# terminal passengers (GuestPlan + GuestController), airliners unchanged + bizjet budgets, hotel walks vs tiers 2-4,
# jet hull + walks vs the world (~4 min)
python3 harness/make_manifest.py --src work/src --gen harness/.gen_gj >/dev/null
run guests_jet_jet      bash -c "cd tests/guests_jet && ../../tools/luau test_jet.luau -a .gen_gj"
run guests_jet_guests   bash -c "cd tests/guests_jet && ../../tools/luau test_guests.luau -a .gen_gj"
run guests_jet_aircraft bash tests/guests_jet/aircraft.sh
run guests_jet_geometry bash tests/guests_jet/run.sh --geometry-only
# itinerary (itinerary.md #6 + fix round 2): ItineraryMath, ItineraryService scenarios, ItineraryController, review regressions
python3 harness/make_manifest.py --src work/src --gen harness/.gen_itinerary >/dev/null
run itinerary_math    bash -c "cd tests/itinerary && ../../tools/luau test_math.luau -a .gen_itinerary"
for sc in abroad jet region offer edge remote; do run "itinerary_$sc" bash -c "cd tests/itinerary && ../../tools/luau test_service.luau -a .gen_itinerary $sc"; done
run itinerary_client  bash -c "cd tests/itinerary && ../../tools/luau test_client.luau -a .gen_itinerary"
for sc in race offerwait cabin cabinctl paidticket garage stalecall abroadstart two midnight leave respawn spam endflight overhold stage5 rigcost timed together jettogether perf; do run "itinerary_review_$sc" bash -c "cd tests/itinerary && ../../tools/luau test_review.luau -a .gen_itinerary $sc"; done
# release e2e (verify2b): two founders on one server, the whole abroad business trip (shuttle / own jet) + one decline
run trip_e2e          bash -c "cd tests/verify2b && ../../tools/luau test_trip_e2e.luau -a .gen_itinerary"
