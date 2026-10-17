# Requests from package "itinerary" (the founder's business trip, LOGIC_BRIEF 24)

Filed 2026-10-12. The itinerary works without every item below; each one names what happens today. API for other
packages: `ItineraryService.claims(userId, tripKey)`, `.pending(userId, tripKey)`, `.state(player)`,
`.summary(session)`, `.setHotelProvider(fn)` (header of ServerScriptService/Server/Services/ItineraryService.module.luau;
tripKey = `client..":"..left`, the key DriverService / JetService / ShuttleService already share). Published state:
Player attribute `Itinerary` (current step, nil = none), `ReplicatedStorage.CompanyItinerary/Itin_<userId>`.

## 1. drivers - let the founder's car take the trip's field rep + engineer
Today DriverService starts the field ride of a new pilot trip at once, so the trip's rep + engineer leave in a company
car before the assistant's call rings (ItineraryService waits `OFFER_DELAY` = 1.5 s so the call names the driver who is
really free and says honestly "... are already on the way to the airport and meet you there"). On a stage with one
driver the founder then waits for the next free car (example: out/itinerary/desktop_region.png, "Booked · next free car
in about 4:07"). Suggested (additive, DriverService only):
- when a field ride would start for `tripKey`, skip it while `ItineraryService.pending(userId, tripKey)` is true and look
  again a few seconds later (the offer is open for at most `ItineraryMath.OFFER_TTL` = 600 s; `pending` turns false when
  the founder declines / the offer expires);
- start no field ride while `ItineraryService.claims(userId, tripKey)` is true: the founder's own ride already carries
  them (`Driver.request(..., passengers = {rep, engineer})`).
Use an optional pcall'd require of ItineraryService (it requires DriverService itself). Also see guests_jet.md #8
(`DriverService.fieldEta`): with it the company jet waits for the car instead of flying ahead empty.
UPDATE 2026-10-17 (itinerary fix round 2, review: "brief 24 headline not delivered on any normal stage"): a ready,
tested patch is `agents/itinerary/sb_drivers/drivers_request1.patch` (3 hunks, additive, DriverService.scanTrips only):
skip a new trip's field ride while `ItineraryService.pending(userId, key)` (looked at again on the next scan), start
none while `ItineraryService.carries(userId, key)` (he said Go, the rep + engineer ride in his car - new API, see the
header), and no field ride home for a trip his car brings home. Apply: `patch work/src/ServerScriptService/Server/
Services/DriverService.module.luau < agents/itinerary/sb_drivers/drivers_request1.patch`. Verified on a sandbox copy
(`bash agents/itinerary/sandboxes.sh`): tests/itinerary/test_review.luau "together" switches to its strict branch
(stages 2-5: no field car before the call, the call says "travel(s) with you", the founder's car carries the
colleague(s), no field car meanwhile) 14/0; abroad 91/0, jet 34/0, race 6/0 unchanged. Without the patch the scenario
checks the honest fallback (the call says "went ahead", carry follows the field car). The drivers' own suites pass
on the patched copy (#1 + #2, `bash tests/drivers/run.sh .gen_itin_sb_both`): plan 229/0, service 166/0, client 49/0,
review 71/0, review_client 48/0, clearance 3542/0.
STATUS: done by verify2b (2026-10-17): drivers_request1.patch applied to work/src (integration fix, agents/verify2b/FIXES.md #1);
tests/itinerary/test_review.luau "garage" got a stage-3 case with the only driver out (the queued branch stays covered).

## 2. guests_jet - the founder flies the jet with his field staff
Today JetService starts the field-staff jet flight about one second after a CompanyOps abroad trip starts (fieldEta is
not exported yet, guests_jet.md #8), so when the founder says "Go" the jet is `JET_BUSY` (purpose "staff"): the itinerary
books the shuttle and the call says "Mia from Growth & Sales and Leo from Engineering are already flying to Port Meridian
and meet you there" (tests/itinerary/test_service.luau jet scenario). Suggested (JetService only): keep a fresh staff
trip in `wait_out` while `ItineraryService.pending(userId, key)` or `ItineraryService.claims(userId, key)` is true;
`JetService.fly(player, {to = "abroad"})` from the itinerary then takes the waiting staff along (`result.staff`), as
the API already describes. `JetService.summon` is not used by the itinerary: with the jet in Hangar 1 and the founder
in Port Meridian the return is booked on the shuttle (no waiting for the jet's empty leg).
UPDATE 2026-10-17 (fix round 2): ready, tested patch `agents/itinerary/sb_jet/guests_jet_request2.patch` (JetService
only): `pending()` skips staff trips while `ItineraryService.holds(userId, key)` unless the flight is the founder's
own (`founder = true` from `JetService.fly`), and the founder's companions already aboard take no extra seat (else a
2-person staff trip never fits next to his 2 companions with MAX_COMPANIONS = 3 and stays `wait_out` - a second
staff flight would fly them again). Verified on sandbox copies (`bash agents/itinerary/sandboxes.sh`): test_review
"jettogether" strict branch 8/0 with this patch alone and with #1 + #2 (the staff jet waits while he is asked, the
call books our jet, his jet flight marks the staff trip flown, no second staff flight); test_service jet 33/0 (its
staff-jet check is patch-aware). The guests_jet suites pass on the patched copy (`bash tests/guests_jet/run.sh --src
agents/itinerary/sb_both/src --quick`): jet 210/0, guests 205/0, aircraft 27/0.
STATUS: done by verify2b (2026-10-17): guests_jet_request2.patch applied to work/src (agents/verify2b/FIXES.md #2); test_review
"stage5" helper toFlight accepts the jet path.

## 3. phone - one calendar entry per flight
`PhoneMath.calendar` adds the public timetable entry "Shuttle PM 101 to Port Meridian" (greyed, `public = true`) next
to the itinerary's own item "itin:<seq>:flight" for the same departure (out/itinerary/desktop_calendar.png shows both).
Suggested: skip the public shuttle entry when an `extra` item of kind "flight" has `at` within 1 s of `shuttle.at`.
STATUS: open

## 4. flight - arrival toasts during an itinerary
`ShuttleController` `onLeg()` shows "Welcome to Port Meridian! Your return flight is included - check in at the counters
to fly home." and "Welcome back to City Airport! Your car waits in the car park west of the terminal." after every
landing. During an itinerary the return is pre-booked (company booking `ShuttleService.book`, no counter needed) and the
company driver waits at the arrivals kerb, and the itinerary's banner + phone message already say what is next
("Arrived in Port Meridian - the VIP limousine is waiting ..."). Suggested: skip both toasts while
`player:GetAttribute("Itinerary") ~= nil`.
STATUS: open

## 5. drivers - DriveHUD ride panel over the HUD company card on a phone
On 844x390 (guiprev, out/itinerary/phone_return.png / phone_pickup.png) the top-centre `RidePanel` reaches under the
HUD column (company card, top right). The itinerary banner already slides below the ride panel and folds while it is
shown (no second "Cancel"). Suggested: cap the ride panel width at the space left of the HUD column (`LaneWidth`
attribute the HUD publishes) on compact screens.
STATUS: open

## 6. lead - tests/lead/run_all.sh lines
```
python3 harness/make_manifest.py --src work/src --gen harness/.gen_itinerary >/dev/null
run itinerary_math    bash -c "cd tests/itinerary && ../../tools/luau test_math.luau -a .gen_itinerary"
for sc in abroad jet region offer edge remote; do run "itinerary_$sc" bash -c "cd tests/itinerary && ../../tools/luau test_service.luau -a .gen_itinerary $sc"; done
run itinerary_client  bash -c "cd tests/itinerary && ../../tools/luau test_client.luau -a .gen_itinerary"
```
(or `bash tests/itinerary/run.sh`, ~3 s; mutations: `bash tests/itinerary/negative.sh`, 25 must all be caught).
GUI previews: `bash tests/itinerary/render_gui.sh` (24 PNGs into out/itinerary/, ~2 min).
UPDATE 2026-10-17 (fix round 2): the package now also has the review regression suite. Simplest: one line
`run itinerary bash tests/itinerary/run.sh` (builds .gen_itinerary, 29 runs in parallel, ~10 s, prints
"itinerary suites: N passed, M failed", exit 0 only when all pass). Or the lines above plus
`for sc in race offerwait cabin cabinctl paidticket garage stalecall abroadstart two midnight leave respawn spam endflight overhold stage5 rigcost timed together jettogether; do run "itinerary_review_$sc" bash -c "cd tests/itinerary && ../../tools/luau test_review.luau -a .gen_itinerary $sc"; done`
and `run itinerary_review_perf bash -c "cd tests/itinerary && ../../tools/luau test_review.luau -a .gen_itinerary perf"`
(the perf scenario times ItineraryService.tick against DriverService.tick: run it outside the parallel batch or allow
its 1 ms floor). Mutations: `bash tests/itinerary/negative.sh` - 56 must all be caught (~1 min). Patch sandboxes for
#1 / #2: `bash agents/itinerary/sandboxes.sh`. The drivers and guests_jet suites are missing from run_all as well
(review spec gap).
STATUS: done by verify2b (2026-10-17): the individual lines (math, 6 service scenarios, client, 21 review scenarios incl.
perf, sequential) + the drivers / guests_jet suites + the release e2e tests/verify2b/test_trip_e2e.luau are in run_all.

## 7. lead (owner of people_harness) - greeting test vs the "First steps" guide
onboarding.md #1 (skip the assistant's greeting toast while `TutorialMath.active`) is ready as a one-line change in
AssistantService but breaks people_harness/test_people.luau ("greets once on the founder floor", "greeting not
repeated"): its fixture company is `Template.new()`, so the guide counts as running. Please set
`gs.data.empire.tutorial = {done = true}` in that fixture (an established stage-3 company has finished the guide); then
the guard can land (see onboarding.md #1 STATUS).
STATUS: open

## 8. phone - end a ringing call: `PhoneService.endCall(session, callId)`
When the founder says Go on the banner (or the auto-trip countdown runs out), the assistant's call keeps ringing; a
late "Not this time" on it is answered harmlessly today ("You're already on your way to Helix Research - use Cancel
trip in the banner if you'd rather stay.", ItineraryService.phoneHook, test_review "stalecall"), but the call sheet
should simply close. Suggested (PhoneService, additive): `function Phone.endCall(s, id: string)` - drops the call `id`
from the session's ringing calls and fires the same PHONE_UPDATE the phone sends when a call is answered (the client
closes the sheet / clears the badge); unknown ids are ignored. ItineraryService already calls it whenever it exists
(`(Phone :: any).endCall`, pcall'd; test_review "stalecall" checks the call with a stub).
STATUS: open

## 9. phone - the founder's own trip at the top of the calendar
The calendar sorts "now" items first (the field rep's "Under way" trip), so on a phone the founder's own itinerary
items (pick-up, flight, meeting, hotel, return; keys "itin:<seq>:<step>", added with `addCalendarItem`) sit below the
fold (review: out/itinerary/phone_calendar.png). Suggested (PhoneMath.calendar): a pinned group "Your trip" above
"Under way" for extra items whose key starts with "itin:" (or an optional `pin = true` field on addCalendarItem that
PhoneService copies), sorted by `at` among themselves. The itinerary sends nothing new for it.
STATUS: open

## 10. flight - no second boarding walk of the founder's colleagues (ShuttlePassengers)
Since fix round 2 the colleagues of a company booking join the leg's Passengers when the founder boards
(ShuttleService.boardCompanions: Passenger<n> with PassengerName / Company / Leg + `CompanionOf = <founder userId>`),
so ShuttlePassengers walks them off the aircraft at the destination like the field staff (review: "0 of 2 colleagues
in Passengers"). On the boarding side the itinerary's own followers already walk the shuttle's boarding path into the
cabin (ItineraryController, Pax.path / Pax.along). A client whose boarding group starts AFTER the founder boarded
(it came near the aircraft late) would also walk these templates from the gate - a second copy. Suggested
(ShuttlePassengers.step, boarding window only): skip templates with the attribute `CompanionOf` when `reverse` is
false; keep them for the deboarding walk.
STATUS: open
