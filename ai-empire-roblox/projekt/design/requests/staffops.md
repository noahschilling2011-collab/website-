# Requests from package "staffops" (staff calendar, absences, night crew, apprentices + Training Lead, rack repairs, first days)

Everything below is optional for correctness: staffops works today without each item (guarded / fallbacks
described per item). Public API added by staffops (files staffops owns):

- `StaffService.hour()` - the visible company hour (`CompanyOps.hour(workspace:GetServerTimeNow())`).
- `StaffService.now()` is unchanged in meaning (monotonic campus timer for Nav / cooldowns) but now starts at
  the server clock and never falls behind it, so `EmployeeConfig.hour(Staff.now())` shows the same hour as the sky.
- `StaffService.expectArrival(office, seed, fromCFrame?, hold?)` - a hire whose rig StaffAssignment builds next walks
  in from `fromCFrame` or the street, through reception (first day). With `hold` (interview hire) the rig stays
  hidden while the candidate walks out to the speed gates, until `StaffService.handoverArrival(office, seed, cf)`
  (RecruitingService calls it when the visitor rig is removed there; at most 120 s, then a normal arrival).
- `StaffService.inspect(office)` rows also carry `away, night, apprentice, event, onDuty`.
- `StaffAssignment.dressApprentice(model, on)`; `StaffAssignment.assign` is incremental and writes the office
  attribute `StaffRev` (+1 per call). Unchanged people keep their rig; new rigs of a running office start hidden
  (`OffDuty = true`) until StaffService walks them in.
- New modules `ServerScriptService/Server/Services/StaffRota` (who is on duty, pure) and `StaffEvents` (first-day
  arrivals, rack repairs, apprentice tour / training / shadowing, Training Lead coaching), required by StaffService.
- Blade / rack-door attributes written by StaffEvents (server, on change only): `FxState` ("broken" / "idle"),
  `FaultSlot` (CompanyOps fault slot), `FaultUntil` (server time of the economy's own repair estimate: remaining
  work / repair rate), `FaultWorker` (job title of the person on it, e.g. "IT Support" / "ML Engineer"; nil =
  nobody yet) and `FaultFix` ("walk" on the way, "rack" at the rack, "remote" = IT's remote fix from the corridor).
  PropFxController draws the fault (red blink, one beacon + label per rack, door banner) from them.
- Rig attributes: `Apprentice = true` (+ `LanyardColor` while dressed), `ShiftStart` / `ShiftEnd` (operations day
  shift, night crew 22 / 6; nil = night rota or the seeded personal shift), `ShadowOf` (senior's name while an
  apprentice shadows), Task ids `FirstDay`, `RackRepair`, `ApprenticeTour`, `Tour:<room id>`, `TrainingSession`,
  `TrainingLead`, `Shadowing`, `Practice`, `Coaching`; Pose `present` (EmployeeController).
- `EmployeeConfig.OPS_WAGE_PER_DAY = 720`, `OPERATIONS_JOBS[17] = "Training Lead"` (`OPTIONAL_POSTS[17]`,
  `TRAINING_LEAD_POST = 17`), `OPS_SHIFT`, `NIGHT_ROTA_POSTS`, `NIGHT_CREW`, `APPRENTICE`, `JOBS["Training Lead"]`.
- Round 2: `OPERATIONS_JOBS[18] = "Security"`, `[19] = "IT Support"` = the stage-5 night rota people
  (`NIGHT_ROTA = {[18]=3,[19]=6}`: they use the stations of posts 3 / 6 at night; CompanyOps.STAGES[5].ops = 16
  already pays them), `NIGHT_ROTA_SHIFT`, `workdayOffset(hour)`, `APPRENTICE.tourGroup = 4`, `APPRENTICE.badgeWidth`.
  Rig attribute `NightRotaOf` (3 / 6) on the night rota rigs. PropFxController honours `FxFar` / `FxVertical`.
- `Dialogue.facts(...)` adds `day, away = {{name, role, state, back}}, awayCount, apprentices[seed] = {name, role,
  day, skill, graduates}, apprenticeCount, rackFaults`; topics "away" (reception, trainer) and "apprentices"
  (trainer, new kind "trainer").

## 1. BuildingPlan (buildings / lead) - IT Support may enter the compute rooms (user request 23)  [STILL OPEN - most important]
`ROLE_CLEARANCE.support` has no `compute`, so the IT Support post can never reach a data-hall / compute-room rack
(both are access class "compute"). Today StaffEvents therefore sends the nearest ENGINEER (who has compute
clearance) whenever the IT post cannot reach the faulty rack; the economy still uses its IT-on-duty repair
speed (60 s / 300 s), so nothing is wrong, only the wrong person walks. To let IT do the repairs:
```lua
-- BuildingPlan.module.luau, ROLE_CLEARANCE
support = { public = true, staff = true, technical = true, guest = true, compute = true },
```
(compute rooms are dead ends behind secure doors, so other operations staff gain no shortcut through them; the
tour of the apprentices may then also stop at the data hall.) No staffops change needed: `pickWorker` prefers
IT Support automatically once `Plan.employeeAllowed("support", tier, rackPoint)` is true.
Round 2 (reviewer: "IT never visibly repairs a rack"): until this line is applied, staffops sends the IT post to
the corridor in front of the rack room's door for a REMOTE fix (laptop / phone poses, blade `FaultFix = "remote"`,
label "IT Support · remote fix", talk line "I'm fixing a rack fault remotely from out here: IT has no access to the
compute rooms."). An engineer walks to the rack only when no IT post is free (garage, IT busy / off duty). With
the line applied, the tests in tests/staffops (rack suite: "remote fix exactly when IT may not enter the rack room")
switch to expecting IT at the rack automatically.

## 2. EmployeeRigDesign (world package) - Training Lead uniform + apprentice look at build time
- `UNIFORMS["Training Lead"] = {shirt=rgb(46,126,112), trousers=rgb(44,50,66), shoes=rgb(40,34,30)}` and
  `LANYARD` green for the trainer (staffops recolours the rig after `Rig.build` today: torso/sleeves teal, trousers
  navy, lanyard green - identical tones, so adding the entry changes nothing visible).
- Optional: a `young = true` build option (no beard, no grey hair, build scale x0.94 inside `at()`) instead of the
  post-build `Model:ScaleTo(0.94)` StaffAssignment uses now (Studio check: R6 feet may float ~0.2 studs while
  anchored, the same order as today's 0.92..1.06 build spread).

## 3. TalkService (talk) - exact hour + relief/shadow facts (optional)
- `context().hour`: `EmployeeConfig.hour(Staff.now())` already matches the sky now (the timer is phase-locked to the
  server clock); `Staff.hour()` is the exact value if you prefer it.
- `subject()`: pass the rig attribute `ShadowOf` (string) as `sub.shadowOf`; Dialogue would then say "I'm sitting
  with Mia Weber today ..." (today it says "a senior colleague").

## 3b. TalkPanel (talk, client) - the panel slides under the top bar on phones (found in the staffops previews)  [STILL OPEN - confirmed by the round-1 review with the HUD + phone button mounted; out/staffops/phone_talk_*.png still show it]
`TalkPanel.fitScale` fits the 640x540 panel to `workspace.CurrentCamera.ViewportSize - 24`, but the ScreenGui has
`IgnoreGuiInset = false`, so on an iPhone in landscape (844x390, 58 px top bar) the scaled panel is ~25 px taller
than the area it is centred in and its header (name, Close button) sits under the Roblox top bar
(out/staffops/phone_talk_*.png). Fit to the ScreenGui instead, e.g.
`local size = screen.AbsoluteSize; scale.Scale = math.clamp(math.min((size.Y - 16) / TalkPanel.H, (size.X - 16) / TalkPanel.W), .3, 1)`
(re-run on `screen:GetPropertyChangedSignal("AbsoluteSize")`), or subtract `GuiService:GetGuiInset()` from the
viewport. Desktop is unaffected.

## 4. tests/lead/run_all.sh (lead) - add the staffops suites  [STILL OPEN - the regression run covers no staffops suite]
```
python3 tests/staffops/mkharness.py >/dev/null
for t in clock absence night ops apprentice academy rack nightfault garage beacon arrival talk client perf; do run "staffops_$t" $L tests/staffops/test_staffops.luau -a "$t"; done
```
(`tests/staffops/run.sh` does the same, about 12 min; negative checks: `tests/staffops/negative.sh` (files before the
package) and `tests/staffops/negative_round2.sh` (files of review round 1); GUI previews: `tests/staffops/render.sh`
-> out/staffops/.)

## 5. CORE_SPEC (lead) - decisions to record
- 5.3 / 11.1: operations staff have no visible absences: the HR relief covers vacation and sick days of a post
  (the post is never empty during opening hours). The covering day shift is 07:15-07:30 to 18:00-18:30 (seeded).
- 5.3: the company day a shift belongs to switches at 06:00 for the staff animation (the people arriving at 07:45
  are the ones who work the day that starts at 08:00); the economy's calendar still advances at 08:00.
- 5.3: at the end of a shift an employee finishes the current step but leaves within 3-11 real seconds (night
  hours pass at 21 s per hour, so a 3-minute task would keep the night crew until 08:00).
- 11.1: the Training Lead sits at a free desk of the People & Company (HR) room (else another free operations desk,
  else the reception); tour 08:20-16:00 on the first day (groups of at most 4, one run after another for a big
  batch), training session 10:00-11:30 every later day.
- 11.1 (deviation, round 2): the daily training session is held in the meeting room nearest to the Training Lead's
  HR desk with enough free seats for the group + the trainer, not in the HR room itself: the HR room has 3-5 desks
  and a 3-chair interview table, no seats for a class and no whiteboard station. Optional buildings request: a
  "Meeting" seat row + whiteboard in the HR room (RoomKitsWork.kitHr) would let StaffEvents.sessionRoom prefer it.
- 5.5 (round 2): stage 5 night rota = two separate people (OPERATIONS_JOBS 18 / 19) who take over posts 3 and 6 at
  exactly the day person's own shift end and leave at their shift start the next morning; the day guard and the
  day IT go home. Below stage 5 the day guard of post 3 stays on while a department runs a night crew (CompanyOps
  pays no extra guard there).
- 5.3 (round 2): "Who's away today?" lists the people of the shift day (06:00-08:00 already the coming day), read
  from live.workforce.hour.

## 6. CompanyOps (econ / lead) - drop apprentices entries without a profile  [new, round 2]
`Ops.apprenticeCount` counts every key of `empire.apprentices`, so an entry whose seed no current profile has (a list
truncated by `EmpireMath.syncProfiles`, an admin edit, a migration) keeps paying the Training Lead ($900/day from
stage 3, `Ops.TRAINING_LEAD`) and `Ops.graduate` never removes it (it iterates the profiles). staffops now places no
Training Lead for such an entry (StaffAssignment.apprenticeSeeds = the rule of StaffRota / Dialogue.facts: only seeds of
the current profiles 1..employees[role]). Suggested fix in `Ops.graduate` (runs at every day change):
```lua
-- after the graduation loop: entries without a current profile are stale
local live: {[string]:boolean} = {}
for role, list in e.staffProfiles do
	local n = math.max(0, math.floor(tonumber(e.employees and e.employees[role]) or 0))
	if typeof(list) == "table" then for i = 1, math.min(n, #list) do local p = list[i]; if typeof(p) == "table" and typeof(p.s) == "number" then live[tostring(p.s)] = true end end end
end
for key in map do if not live[key] then map[key] = nil end end
```
(or the same in the Template cleaner). Test: tests/staffops academy suite "stale apprentice entry" (staffops side).

## 7. CompanyOps (econ) - no absence on the hire day  [new, round 2, optional but players will notice]
`CompanyOps.presence` can put a person on vacation (1/12) or sick (1.7 %) on the day they are hired, so a hire the
player just paid for (or auto-HR announced in the news) does not walk in that day. staffops follows the economy (the
person is away, the first-day arrival happens on the next working day). Suggested: a hire-day exemption, e.g.
`empire.hiredOn[tostring(seed)] = day` written by EmpireService.hire / auto-HR (one entry per hire, dropped after the
day like the apprentice map) and in `Ops.presence`: `if hiredToday(seed) then out[i] = "present"` before the
vacation / sick rules (the vacation day of that cycle then simply falls on another day: skip it, no collision shift).

## 8. BuildingStateService (apps) - data-hall screen: who repairs the fault  [new, round 2]
Line ~373 says "IT on the way" whenever `compute.it` is true, but the worker can be an ML Engineer, IT doing a remote
fix, or nobody (stage 3 at night). StaffEvents now writes the truth on the blade of each fault slot:
`FaultWorker` (job title or nil) and `FaultFix` ("walk" / "rack" / "remote"). Suggested screen line:
```lua
local blade = blades and blades:GetChildren()[f.slot]
local who = blade and blade:GetAttribute("FaultWorker")
local fix = blade and blade:GetAttribute("FaultFix")
local state = if who == nil then (if compute.it then "waiting for IT" else "no IT on duty")
	elseif fix == "walk" then who .. " on the way" elseif fix == "remote" then who .. " · remote fix" else who .. " repairing"
-- string.format("Rack R%d fault · %s · %s", slot, gpuLabel, state)
```
(the same wording as the rack label of PropFxController.rackText).
STATUS: done by apps (BuildingStateService data hall: "Rack R2 fault · Workstation GPU · IT Support · remote fix" /
"ML Engineer on the way" / "... repairing" / "waiting for IT" / "no IT on duty" from FaultWorker / FaultFix;
tests/apps/test_server.luau mid checks all four)

## 9. EmployeeRigDesign (world) - badge width (optional, cosmetic)  [new, round 2]
The EmployeeBadge is 150 px; "Apprentice · Growth Manager" needs ~180 px at 12 px bold. staffops widens an
apprentice's badge to 190 px (TextScaled with a UITextSizeConstraint max 12 for very long names) and restores 150 px at
graduation. Optional: build every badge with `TextScaled = true` + `UITextSizeConstraint.MaxTextSize = 12` so long
regular names never overflow either.


## 10. Lead decision - operations posts built vs posts CompanyOps pays (found in round 2, not changed)
StaffAssignment places one rig per built OperationsStation post. The built posts per plan tier (harness dumps,
out/staffops/harness/dump_tier*.json) are more than CORE_SPEC 5.5 / CompanyOps.STAGES[].ops pay: tier 1 (stage 2)
14 posts vs 8 paid, tier 2 (stage 3) 14 + 2 guest house vs 12 + 2, tier 3 14 + 2 vs 14 + 2, tier 4 16 + 2 (incl. the
new night rota 318 / 319) vs 16 + 2. Either (a) staffops places only the posts of the stage (e.g.
`EmployeeConfig.POST_FROM_STAGE = {[2]=3,[4]=4,[10]=3,[11]=4,[15]=3,[16]=3}`, others from stage 2; a small
StaffAssignment change plus test updates in staff_harness / tests/buildings), or (b) econ pays every built post.
Tell staffops which one; nothing was changed because it alters the visible life of every HQ stage.
