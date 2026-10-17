# verify2b: integration fixes (release check of round 2b, 2026-10-17)

Every change is minimal and additive. The files as they were before are in `agents/verify2b/backup/`.

## Game code (work/src)

| # | file | what | why (integration defect) | evidence |
|---|---|---|---|---|
| 1 | `ServerScriptService/Server/Services/DriverService.module.luau` | Applied `agents/itinerary/sb_drivers/drivers_request1.patch`: 3 hunks in `scanTrips`, plus a lazy, pcall'd `ItineraryService` lookup. DriverService starts no field car for a new trip while `ItineraryService.pending(userId, key)`, none while `carries(userId, key)`, and no field car home for a trip the founder's car brings home. | design/requests/itinerary.md #1 had STATUS "open (patch ready)". Without the patch, the field rep + engineer left in a company car before the assistant's call, so on every normal stage the founder travelled alone ("... went ahead"). The LOGIC_BRIEF 24 headline was therefore never delivered. | e2e on the unpatched tree: 41 failures (`tests/verify2b/negative.sh`, `unpatched`). Patched: e2e 0 failed, `itinerary_review_together` strict branch. |
| 2 | `ServerScriptService/Server/Services/JetService.module.luau` | Applied `agents/itinerary/sb_jet/guests_jet_request2.patch`. In `pending()`, staff trips held by `ItineraryService.holds` wait for the founder's own flight, and his companions already aboard take no extra seat. | itinerary.md #2 had STATUS "open (patch ready)". The field-staff jet left ~1 s after the trip started. A jet owner was therefore always put on the shuttle ("... already fly out"), and the staff flew separately. | e2e: Ben is offered our jet, his colleagues are aboard his flight, and there is no separate staff flight. `itinerary_review_jettogether` strict branch. |
| 3 | `ServerScriptService/Server/Services/BuildingStateService.module.luau` | Changed the LiveScreen footer `"%s needs %d GB more VRAM · Open Lab → GPUs or choose a smaller model size"` to `"... · Open Lab → GPUs or pick a smaller size"`. | The menu package renamed "Open Hardware" to "Open Lab → GPUs" (2026-10-12). The footer grew to 73-75 characters, over the 72-character footer budget. `screens_fake` and `screens_real` have reported `SUMMARY problems=9` in every run_all since, but rc stayed 0. | `agents/screens/test_screens.luau fake` and `real`: problems went from 9 to 0. The worst case is now 67 characters. |

## Tests / tooling

| # | file | what | why | evidence |
|---|---|---|---|---|
| 4 | `tests/lead/run_all.sh` | Added the round-2b suites: drivers (6 lines, drivers.md #2), guests_jet (4 lines, guests_jet.md #1), itinerary (itinerary.md #6: math, 6 service scenarios, client, 21 review scenarios incl. perf, run sequentially) and the release e2e `trip_e2e`. | The three packages' suites were missing from run_all. | `agents/verify2b/runall.txt`: 145 suites |
| 5 | `tests/itinerary/test_review.luau`, helper `toFlight` (scenario `stage5`) | `toFlight` now accepts the jet path: the state goes from pickup to flight in one step, with no "airport" state. | With fix 2, a stage-5 jet owner gets our jet. `itinerary_review_stage5` then failed "in the air -- airport flight" in the preliminary run_all. The scenario already allowed `plan.how == "jet"`; only the helper assumed the shuttle. | stage5 passes 9/0 on both the patched and the unpatched tree. |
| 6 | `tests/itinerary/test_review.luau`, scenario `garage` | Added a stage-3 case whose only driver is already out with a city visit's field rep. The region call must then queue the car honestly: a real ETA and no driver named. | With fix 1, the existing stage-3 case gets the free driver, so the queued-ETA branch was no longer exercised. The mutation `queued_eta_dropped` was MISSED (55/56). | garage passes 14/0 (patched) and 16/0 (unpatched). `tests/itinerary/negative.sh`: 56/56 caught. |
| 7 | `tests/guests_jet/negative.sh`, mutation `staff_leave_before_car` | Re-anchored the mutation to the patched line of `JetService.pending`. | Fix 2 changed the mutated line, giving "MUTATION TARGET NOT FOUND" (21/22). | `--no-world`: 22/22 caught |
| 8 | new `tests/verify2b/test_trip_e2e.luau`, `tests/verify2b/negative.sh` | An end-to-end business trip for two founders on the real server modules and the real company tick, plus Ada's client (ItineraryController, DriveController). `negative.sh` has 5 mutations the e2e must catch. | Release task (3). | `trip_e2e: 113 passed, 0 failed`; negative.sh: 5/5 caught |
| 9 | `design/requests/{drivers,guests_jet,itinerary}.md` | Added STATUS "done by verify2b" to drivers #2, guests_jet #1, itinerary #1, #2 and #6. | Bookkeeping. | (none) |

## Verification after the changes
- Compile and `luau-lsp analyze` are clean on DriverService and JetService.
- run_all (`RUNALL_TAG=verify2b`): 145 suites, all rc=0, 0 failed, 239,205 checks, 27 min (`agents/verify2b/runall.txt`).
- Mutation suites: drivers 57/57, guests_jet 22/22 (`--no-world`), itinerary 56/56, verify2b e2e 5/5.
- harness `--check`: 4 tiers ok, 0 thread errors, frame consistency OK, all targets reachable, part counts unchanged.
- Pack + roundtrip: ROUNDTRIP OK (`out/verify2b/AIEmpire_r2b.rbxlx`). The tested snapshot is packed separately as `out/verify2b/AIEmpire_r2b_tested.rbxlx`, also ROUNDTRIP OK.
- **Drift warning:** another agent (onbshop_fix1) edited 22 work/src files (UI texts / apps / Kit / Tutorial / AIModelService / CompanyService / BuildingStateService texts) while run_all was running. `AIEmpire_r2b.rbxlx` contains those edits, and run_all did not cover them. The e2e, screens and the itinerary suites were re-run on that tree: all green.
