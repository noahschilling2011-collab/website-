# Requests from package "life" for files it does not own

Contract for everything below: design/PROPFX_CONTRACT.md.

## 1. StaffAssignment.module.luau — optional hotel posts (no warning)
`EmployeeConfig.OPERATIONS_JOBS` now has 16 jobs (13 "Hotel Reception", 14 "Housekeeping", 15 "Cleaner",
16 "Mailroom"). Posts 13/14 exist only when the hotel annex is built, so every build currently warns
`Missing OperationsStation posts (OpsIndex 13, 14) in tier N`.
Change in `Assignment.assign`, operations loop (lines ~108-120): skip optional posts silently:
```lua
if not post or not work then
 if not EmployeeConfig.OPTIONAL_POSTS[i] then table.insert(missing,i) end
 continue
end
```
(`EmployeeConfig.OPTIONAL_POSTS = {[13]=true,[14]=true}` already exists.) The staff test still expects one
warning for the deliberately missing post 4, which stays non-optional.
STATUS: already done (integrate: StaffAssignment skips EmployeeConfig.OPTIONAL_POSTS / annex posts silently)

## 2. EmployeeRigDesign.module.luau — uniforms for the new jobs
`UNIFORMS` (line ~42) has no entry for the new job titles, so these four wear office clothes. Add e.g.:
```lua
["Hotel Reception"]={shirt=rgb(236,236,230),jacket=rgb(82,46,58),trousers=rgb(44,48,56),shoes=rgb(30,28,28),skirt=true},
Housekeeping={shirt=rgb(196,214,220),trousers=rgb(70,74,82),shoes=rgb(60,48,38),apron=rgb(236,236,230)},
Cleaner={shirt=rgb(52,92,150),trousers=rgb(52,56,62),shoes=rgb(40,34,30),hivis=rgb(204,222,70)},
Mailroom={shirt=rgb(150,112,70),trousers=rgb(56,62,70),shoes=rgb(60,48,38)},
```
`Config.isFeminine` alternates presentation over all 16 posts (unchanged rule, range = #OPERATIONS_JOBS).
STATUS: already done (integrate: EmployeeRigDesign.UNIFORMS has Hotel Reception, Housekeeping, Cleaner, Mailroom)

## 3. TalkService / Dialogue (talk package)
* StaffService no longer handles "EmployeeTalk" prompts (removed as agreed); TalkService owns them.
* `StaffService.recordOf(model)` returns the live record (state, task.id, station.id/room, role, name,
  `lunch.phase`, `jobStep`) for "what are you doing" lines. Read only, no new network traffic.
* New job titles need lines: "Cleaner", "Mailroom", "Hotel Reception", "Housekeeping"; `Dialogue.isPublicJob`
  probably wants "Hotel Reception" public. The talk package's change of the ops prompt `ObjectText` to
  "Name · Job" broke `staff_harness/test_staff.luau` ("name matches presentation"); I updated that test to
  compare the name prefix (staff_harness is mine).
STATUS: already done (integrate: TalkService owns the prompts; Dialogue has lines for the new jobs; talk suites pass)

## 4. Buildings package (hotel annex + BuildingPlan)
* Build the hotel posts as `Service` activities `OperationsStation13` (front desk, seated) and
  `OperationsStation14` (housekeeping cart) with job points on the post (contract §9):
  13: `JobPoint_greet` / `JobFace_greet`, `JobPoint_printer` / `JobFace_printer` / `JobProp_printer`
  (a PropFx `paper,blink` badge printer with that PropId); 14: `JobPoint_cart`, `JobPoint_room1..4`
  (+ `JobFace_*`). Missing points are skipped (optional steps).
* Access class "guest" (hotel rooms): FacilityService already refuses with "Hotel rooms are for guests."
  (`DENY.guest`). Needs `Plan.CLASSES` + `Plan.playerAllows` handling in BuildingPlan.
* Props in hotel rooms can use `ArchKit.fx` / the new builders (vending, waterCooler, deskPrinter ...).
STATUS: already done (integrate: buildings built OperationsStation13 / 14 with the job points; Plan.CLASSES + playerAllows handle "guest")

## 5. DoorService.module.luau — remote barrier (optional)
The garage guard's patrol ends at the ramp foot ("checks the barrier" = looks up the ramp, pose inspect):
`Doors.requestNPC` only accepts NPCs within 8 studs of the door, and the street barrier is ~100 studs up the
ramp. If the guard should really open it, add e.g. `Doors.requestNPC(npc, door, {remote = true})` for the
`Door_SITE_BARRIER` that skips the range check when the NPC stands in B1_GARAGE.
STATUS: deferred to drivers (the fleet car leaves through Door_SITE_BARRIER; if drivers want the barrier to open for it or for the guard, DoorService needs a remote flag - optional today, the guard's 'check' is a pose)
STATUS: done by drivers (no DoorService change needed: DriverService opens Door_SITE_BARRIER for every company car with the existing Doors.requestNPC through an invisible support-role proxy NPC "DriverProxy" inside the office, placed 3 studs inside the barrier, from 3 s before until 2 s after the car's pass time, at most once per second; the guard's patrol is untouched. tests/drivers/test_service checks the calls)

## 6. EmployeeNavigation.module.luau — nothing required
Job hops inside a room use direct `Humanoid:MoveTo` (StaffJobs) and are counted in the office movers cap
(`StaffService` counts `e.nav or e.hop`). Cross-room steps use `Nav.go` unchanged.
STATUS: already done (integrate: nothing required)

## 7. Talk package requests to "life" files: DONE
`design/requests/talk.md` items 1-3 are implemented in the life files: `StaffService.hold/release`,
EmployeeController head turn + gesture (`TalkingTo` / `TalkFace`), office attribute `LunchesServed`
(see PROPFX_CONTRACT §10). The talk suites pass against the current tree (1687/113/31/150, 0 failed).
STATUS: already done (integrate: done by life)

## 8. Lead / pack
* New modules: `ServerScriptService/Server/Services/StaffJobs.module.luau` (required by StaffService).
* run_all.sh: please add the life suites (all write only into tests/life/):
  ```
  python3 tests/life/mkharness.py >/dev/null
  run life_props        $L tests/life/test_props.luau
  run life_client       $L tests/life/test_client.luau
  for t in 1 2 3 4; do run "life_t$t" $L tests/life/test_life.luau -a "$t"; done   # tier 4 takes ~3 min
  ```
  plus, after a harness build into out/life: `python3 tests/life/test_routes.py --out out/life` and
  `python3 tests/life/check_props_geometry.py --out out/life --base <baseline dumps>`.
* `PropFxController` replaced the stub (init() signature kept); Main.client already requires it.
* `CompanyHour` is now written when the shown hour changes by 0.1 h (every ~9 s), not every 0.2 s.
STATUS: already done (integrate: run_all has life_props, life_client, life_t1..t4; StaffJobs is in the tree)
