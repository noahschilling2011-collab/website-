# Requests from package "talk" (talk to everyone)

TalkService already works without any of these (feature-detected / optional attributes); each request
makes a conversation more correct or richer. Attribute names below are what TalkService/Dialogue read today.

## 1. StaffService (life) — pause an employee while someone talks to them  [most important]
File: `ServerScriptService/Server/Services/StaffService.module.luau`. Add two public functions:

```lua
-- TalkService: pause / resume one employee for a conversation. Keeps identity, task and the station
-- reservation; a walk in progress is cancelled like LOD sleep (resumeWalk) and resumed on release.
function Staff.hold(model: Model, face: Vector3): boolean
function Staff.release(model: Model)
```
Behaviour wanted:
- `hold`: `local e = records[model]`; return false if nil / dead / OFF_DUTY / LEAVING / riding the lift
  (`Nav.liftBusy(e)`). Otherwise `e.talkHold = true`; if `e.nav` and `e.state=="WALKING"` keep the walk
  like `setLod(e,"sleep")` does (`e.resumeWalk = e.station~=nil and e.walkTask~=nil`, `Nav.cancel(e)`,
  `e.walkTask` kept); ops job hops (`StaffJobs` `e.hop`) likewise paused; if not seated:
  `e.humanoid:MoveTo(e.root.Position)` and `e.root.Anchored = true`. Return true.
- While `e.talkHold`: skip `security(e)`, `Nav.tick`, `leave`, `selectTask`, `Jobs.tick/next` for that
  employee (LOD may still change; keep counting it in the economy exactly as before — do NOT change its
  `Activity`/state, so `EmployeeConfig.productive` and all economy numbers stay identical).
- `release`: `e.talkHold = nil`; resume like the wake branch of `setLod` (`walk(e,e.walkTask,e.station)` if
  `resumeWalk`, else `e.next = math.min(e.next, time + 1)`); ops jobs continue with their next step.
- Safety: auto-release after 120 s (`e.talkHoldUntil`), in case a release is ever lost.
Why: without it TalkService can only turn a standing, anchored NPC towards the player. Walking NPCs keep
walking, and operations staff hop to their next job point every 3–30 s, so they often walk off in the
middle of a conversation. TalkService then ends the conversation with TOO_FAR once the player is more
than 16 studs away. TalkService already calls these when they exist
(`typeof(Staff.hold)=="function"`): `hold` once when a conversation opens, `release` exactly once when it
ends (bye, close, idle 60 s, walk-away, NPC removed, player leaves, session closing). It does NOT call
`release` when `hold` returned false or threw. After a successful `hold`, TalkService turns an anchored,
non-seated NPC to face the player and turns it back afterwards, so StaffService should not rewrite the
root CFrame while `e.talkHold` is set.
STATUS: already done (integrate: StaffService.hold / release, life.md #7)

## 2. EmployeeController (life, client) — look at the person you talk to
File: `StarterPlayer/StarterPlayerScripts/Client/Controllers/EmployeeController.module.luau`, in `pose` / the
PreSimulation loop. While the rig has the attribute `TalkingTo` (number userId, set by TalkService):
- Neck: yaw towards the rig attribute `TalkFace` (Vector3, world position of the player; written on open and
  after every answer), clamped to ±70° relative to the torso. This also covers seated NPCs, which
  TalkService never rotates.
- Arms: the existing TALKING gesture (`right=.6+.35*sin(t*1.7)`, `left=.2+.12*sin(t*1.2)`) unless seated
  and typing.
Only in the NEAR LOD band (as now). No server writes.
STATUS: already done (integrate: EmployeeController TalkingTo / TalkFace head turn + gesture, life.md #7)

## 3. StaffJobs / StaffService (life) — lunches served today
Set the office attribute `LunchesServed` (number) = plates handed out in the current campus day (reset when
`math.floor(time/1200)` changes). That is one attribute write per served plate, e.g. in `Jobs.officeTick`
where `table.remove(q, 1)` hands the tray over. TalkService reads it for the chef, kitchen team, barista
and café host ("17 lunches served today"). Without it they don't claim any count (tested).
STATUS: already done (integrate: office attribute LunchesServed, life.md #7)

## 4. Hotel annex (buildings / hotel package) — guests
When the hotel exists, set office attributes `HotelGuests` (number of guests tonight) and `HotelRooms` (room
count). TalkService then lets Hotel Reception / Housekeeping talk about them; until then they say honestly
that the hotel isn't taking guests yet. If the hotel adds BuildingPlan rooms, send the room ids to the talk
owner. They go into `Dialogue.placeIds` (directions "Where is …?").
STATUS: already done (integrate: HotelRooms at build, HotelGuests from EmpireService; hotel room ids / purposes: buildings.md #6)

## 5. Lead — run_all.sh: add the talk suites
After the `screens_real` line (or anywhere after the generic manifests):
```
python3 harness/make_manifest.py --src work/src --gen harness/.gen_talk >/dev/null
run talk_dialogue     $L tests/talk/test_dialogue.luau -a .gen_talk --quiet
run talk              $L tests/talk/test_talk.luau -a .gen_talk
run talk_client       $L tests/talk/test_client.luau -a .gen_talk
run talk_real         $L tests/talk/test_real.luau -a .gen_talk 2
```
Expected today: 1687/0, 113/0, 31/0, 150/0 (about 4 s together). Negative checks: `tests/talk/negative.sh`
(original stubs + 5 mutations of TalkService must fail; all do).
STATUS: already done (integrate: run_all runs talk_dialogue / talk / talk_client / talk_real)

## 6. Economy owners (CORE_SPEC) — operations staff pay (optional)
If operations staff get a wage (core_clarity: "$800 per game day each"), expose it as a config number
(e.g. `EmployeeConfig.OPS_WAGE_PER_DAY`). Tell the talk owner, and ops staff can then answer
"Tell me about yourself" with their real pay, as hired staff already do (`role.wage × profile.w`). Until then
ops staff never mention pay, because no real number exists.
STATUS: econ part done (CompanyOps.OPS_WAGE = EmployeeConfig.OPS_WAGE_PER_DAY or 720, CORE_SPEC 5.5); the EmployeeConfig constant itself is re-filed in design/requests/econ.md #2 (not an econ file)
STATUS: EmployeeConfig.OPS_WAGE_PER_DAY = 720 added by staffops

## 7. CampusMath (lead / whoever owns it) — operations staff all share one surname (optional, cosmetic)
File: `ReplicatedStorage/Shared/CampusMath.module.luau`, `Math.staffName`. For consecutive indices (operations
staff are 301..316) `k` is consecutive, so `(k // #list)` and therefore the last name is the same for the whole
block: every operations rig of a company is "… Rossi" (seen in every tier dump: "Lina Rossi · Reception",
"Ben Rossi · Security", "Luca Rossi · Chef" …). Talking to them makes it obvious. Suggested change (names of
operations staff are not saved, so no save impact; hired staff use profile names): pick the last name from an
independent hash, e.g. `Config.LAST_NAMES[(Employee.hash(o*13+index*7) % #Config.LAST_NAMES) + 1]`, keeping the
first name rule (presentation) as is. Check people/staff tests that compare generated names first.
STATUS: already done (integrate: CampusMath.staffName steps operations surnames by #list + 1 past the hired range)

## 8. Info (no action)
- TalkService writes no session data and no `session.live` fields, so the net package's urgent
  `markDirty` is not needed. Conversation traffic is Notify `TALK_OPEN` / `TALK_CLOSE` / `TALK_NOTICE` plus
  the `TalkAction` RemoteFunction (rate limit 6 burst, 3/s, plus a 0.3 s per-conversation answer interval).
- Rig attributes written by TalkService: `TalkingTo`, `TalkFace` (one write each on open/close, `TalkFace`
  once per answer). TalkController hides a rig's talk prompt for everyone while `TalkingTo` is set.
- Read only (no writes): rig `HomeWorkstation`, station `WorkstationId` / `WorkstationType` / `HomeRoom` /
  `Department` (indexed once per office), station `OccupiedBy` ("8 desks in there, 5 in use right now",
  counted per answer), `StaffService.recordOf(model).lunch.phase` (queue / seat / tray return; pcall-guarded).
- A 1 s server sweep ends conversations whose player walked more than 16 studs away from the NPC (or that
  ran 600 s); the NPC says its farewell (Notify TALK_CLOSE) and is released. It does nothing while no
  conversation is open.
- New rooms (hotel annex etc.): a room kind without an authored purpose is simply not offered for "What's
  this room for?" (`Dialogue.explainsRoom`). Send new room kinds to the talk owner for a purpose line.
- Front-of-house talk prompts get `Public=true` and ObjectText "Name · Job" at build time
  (EmployeeRigDesign; jobs per `Dialogue.isPublicJob`: Reception, Security, Barista, Chef, Cafe Host,
  Hotel Reception). WorldController's existing Public rule shows them to visitors.
- Studio check: `RequiresLineOfSight=true` (unchanged) on the head prompt. Please verify that the seated
  receptionist and the security desk can be talked to from the visitor side of the counter.
STATUS: already done (integrate: info)
