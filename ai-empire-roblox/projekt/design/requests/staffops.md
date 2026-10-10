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
  work / repair rate). PropFxController draws the fault (red blink, beacon, label, door banner) from them.
- Rig attributes: `Apprentice = true` (+ `LanyardColor` while dressed), `ShiftStart` / `ShiftEnd` (operations day
  shift, night crew 22 / 6; nil = night rota or the seeded personal shift), `ShadowOf` (senior's name while an
  apprentice shadows), Task ids `FirstDay`, `RackRepair`, `ApprenticeTour`, `Tour:<room id>`, `TrainingSession`,
  `TrainingLead`, `Shadowing`, `Practice`, `Coaching`; Pose `present` (EmployeeController).
- `EmployeeConfig.OPS_WAGE_PER_DAY = 720`, `OPERATIONS_JOBS[17] = "Training Lead"` (`OPTIONAL_POSTS[17]`,
  `TRAINING_LEAD_POST = 17`), `OPS_SHIFT`, `NIGHT_ROTA_POSTS`, `NIGHT_CREW`, `APPRENTICE`, `JOBS["Training Lead"]`.
- `Dialogue.facts(...)` adds `day, away = {{name, role, state, back}}, awayCount, apprentices[seed] = {name, role,
  day, skill, graduates}, apprenticeCount, rackFaults`; topics "away" (reception, trainer) and "apprentices"
  (trainer, new kind "trainer").

## 1. BuildingPlan (buildings / lead) - IT Support may enter the compute rooms (user request 23)
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

## 3b. TalkPanel (talk, client) - the panel slides under the top bar on phones (found in the staffops previews)
`TalkPanel.fitScale` fits the 640x540 panel to `workspace.CurrentCamera.ViewportSize - 24`, but the ScreenGui has
`IgnoreGuiInset = false`, so on an iPhone in landscape (844x390, 58 px top bar) the scaled panel is ~25 px taller
than the area it is centred in and its header (name, Close button) sits under the Roblox top bar
(out/staffops/phone_talk_*.png). Fit to the ScreenGui instead, e.g.
`local size = screen.AbsoluteSize; scale.Scale = math.clamp(math.min((size.Y - 16) / TalkPanel.H, (size.X - 16) / TalkPanel.W), .3, 1)`
(re-run on `screen:GetPropertyChangedSignal("AbsoluteSize")`), or subtract `GuiService:GetGuiInset()` from the
viewport. Desktop is unaffected.

## 4. tests/lead/run_all.sh (lead) - add the staffops suites
```
python3 tests/staffops/mkharness.py >/dev/null
for t in clock absence night ops apprentice rack garage arrival talk client; do run "staffops_$t" $L tests/staffops/test_staffops.luau -a "$t"; done
```
(`tests/staffops/run.sh` does the same, about 6 min; negative check: `tests/staffops/negative.sh`; GUI previews:
`tests/staffops/render.sh` -> out/staffops/.)

## 5. CORE_SPEC (lead) - decisions to record
- 5.3 / 11.1: operations staff have no visible absences: the HR relief covers vacation and sick days of a post
  (the post is never empty during opening hours). The covering day shift is 07:15-07:30 to 18:00-18:30 (seeded).
- 5.3: the company day a shift belongs to switches at 06:00 for the staff animation (the people arriving at 07:45
  are the ones who work the day that starts at 08:00); the economy's calendar still advances at 08:00.
- 5.3: at the end of a shift an employee finishes the current step but leaves within 3-11 real seconds (night
  hours pass at 21 s per hour, so a 3-minute task would keep the night crew until 08:00).
- 11.1: the Training Lead sits at a free desk of the People & Company (HR) room (else another free operations desk,
  else the reception); tour 08:20-16:00 on the first day, training session 10:00-11:30 every later day.
