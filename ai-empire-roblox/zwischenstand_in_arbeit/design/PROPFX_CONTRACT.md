# PropFx contract (package "life") — v1.1

Owner: package "life" (ArchKit, room kits, FacilityService, WorkstationService, StaffService, PropFxController,
EmployeeController). Other packages (buildings/hotel annex, city, talk) may build props that follow this
contract; the easiest way is `ArchKit.fx(inst, kinds, attrs)` (sets the tag and the attributes below).

## 1. Who does what

* **Server, build time** (room kits): tag the prop root, set the static attributes, prebuild every
  ParticleEmitter / Fire **disabled**. Never moves a PropFx part afterwards.
* **Server, run time**: writes only the state attributes `FxState` / `FxUntil` (one write per use) or sets
  `OccupiedBy` on a linked workstation (WorkstationService already does). No per-frame writes, no
  TweenService, no emitter toggling on the server.
* **Client** (`StarterPlayer…Controllers.PropFxController`): registry of every `PropFx` root (GetTagged +
  tag added/removed signals → works with streaming), home poses captured client-side on registration
  (and again after a stream-in, because a streamed-in instance registers anew), all animation local.

## 2. Root

CollectionService tag **`PropFx`** on the prop root: a `BasePart`, or a `Model` (use
`ModelStreamingMode = Atomic` for multi-part props so they stream in complete).

Moving parts must be `Anchored = true`, `CanCollide = false` (CanTouch/CanQuery false for details) and must
never be `Seat`s (seated characters are welded to them).

## 3. Static attributes (build time)

| attribute | type | meaning |
|---|---|---|
| `Fx` | string | comma-separated kinds, e.g. `"steam,blink"` (do not combine two *motion* kinds on one root) |
| `FxAxis` | string | `"x"`, `"y"` or `"z"`: local axis of the root part (Part root) or of the model pivot (Model root) |
| `FxRate` | number | spin: rad/s · belt: studs/s · blink: Hz · flow: shimmer Hz (defaults per kind) |
| `FxTravel` | number | slider: studs · hinge: radians · belt: period in studs · flow (bob): studs |
| `FxHinge` | Vector3 | hinge axis point in root-local space (Part) / pivot space (Model) |
| `FxIdle` | string | `"off"` (default: rest at home) · `"slow"` (motion at 25 %) · `"on"` (always runs) |
| `FxStation` | string | WorkstationId of a station/activity model: working while it has `OccupiedBy` |
| `FxGate` | string | `"Training"` (office attribute `Training == true`) · `"Hour"` (office `CompanyHour` in [8, 18)) · `"Lift"` (office lift cabin `LiftState == "MOVING"`) · `"Meeting"` (office `MeetingRoom == FxMeeting` and `MeetingUntil > now`) |
| `FxMeeting` | string | meeting room id for `FxGate = "Meeting"` |
| `FxColor` | Color3 | blink / glow colour while working |
| `FxText` | string | screen: overlay text while working |
| `FxSeconds` | number | how long one player use runs (default 4) |
| `PropId` | string | id unique per office for props addressed by NPC jobs and prompts |
| `Machine` | number | workout machine number (the `workout` prompt's Value) on belts / flywheels / rower fans |

Part-level flags inside a Model root (or on the root part itself):

| attribute | on | meaning |
|---|---|---|
| `FxMove` | BasePart | this part moves with the root's motion kind (spin/slider/hinge). If no part of a Model carries `FxMove`, every BasePart of the model moves. |
| `FxShow` | BasePart | flow: transparency while working (idle = the transparency it was built with) |
| `FxGlow` | BasePart | blink/flame: this part takes `FxColor` (Neon) while working |
| `FxLink` | BasePart | arm: index of the deepest joint (1..3) that moves this part |
| `FxJoint1..3` | Model (arm) | CFrame of joint k in model-pivot space (home pose). Joint 1 turns about its local Y, joints 2–3 about local Z |
| `FxOut` | BasePart | paper: the part the sheets come out of (default: root part / PrimaryPart / first part) |

## 4. Kinds

| kind | client behaviour while working |
|---|---|
| `spin` | rotate about `FxAxis` through the part centre (Part root) or the pivot (Model root), `FxRate` rad/s |
| `belt` | translate along `FxAxis`: offset = (t·rate) mod travel − travel/2 (treadmill stripes) |
| `flow` | parts with `FxShow` (or the root) become visible at that transparency and shimmer; with `FxTravel` they also bob along `FxAxis` (toilet flush) |
| `steam` | every ParticleEmitter under the root `Enabled = true` (prebuilt disabled) |
| `flame` | every Fire under the root `Enabled = true`; `FxGlow` parts glow `FxColor` |
| `blink` | `FxGlow` parts (or the root) alternate home colour ↔ `FxColor` at `FxRate` Hz |
| `hinge` | eased (0.45 s) rotation by `FxTravel` rad about `FxAxis` through `FxHinge` |
| `slider` | eased (0.8 s) translation by `FxTravel` studs along `FxAxis` |
| `paper` | a client-only sheet slides out of the root (−Z face) every 1.6 s |
| `screen` | client-only overlay on the root's first SurfaceGui: `FxText` while working, "FAULT · IT NOTIFIED" while broken |
| `arm` | robot arm pick-and-place loop through `FxJoint1..3` |
| `breathe` | transparency breathing (GPU rack blades with attribute `Lit == true`) |
| `leds` | Frames named `LED<n>` in the root's SurfaceGui flicker (always near the camera, faster while working) |
| `ticker` | the TextLabel of the root's SurfaceGui scrolls at `FxRate` px/s (use `FxIdle = "on"`) |

Slider with `FxRate > 0` oscillates (0 → travel → 0, `FxRate` cycles per second) instead of holding the
offset; flow with `FxTravel ≠ 0` bobs the same way (toilet flush). `blink` with `FxRate = 0` is a steady glow.

## 5. State (server, rare writes)

* `FxState`: `"idle"` | `"working"` | `"broken"`
* `FxUntil`: `workspace:GetServerTimeNow()` seconds — working until then (one write per use, expires by itself)

Client rule: **broken** if `FxState == "broken"`; **working** if `FxUntil > now`, or `FxState == "working"`,
or the `FxStation` model has `OccupiedBy`, or the `FxGate` holds; otherwise **idle** (→ `FxIdle`).

## 6. LOD (client)

Active set rebuilt every 0.5 s from the camera: < 60 studs → every frame, 60–120 studs → 10 Hz,
beyond 120 studs or more than 24 studs above/below → reset once to the home pose and sleep.
CFrames are written in one batch per frame with
`workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)`.
Legacy tags are still understood: `ClusterFan` (+`FanHome`) = spin gated by Training; `BeltHome` /
`SpinBase` attributes are only read when no home was captured.

## 7. Server entry points

* Player prompt: `ArchKit.action(part, "prop", objectText, <PropId>, opts)` → FacilityService ACTIONS.prop:
  distance (16), 0.3 s throttle, room access class, per-prop cooldown (`FxSeconds` + 1), then
  `FxUntil = now + FxSeconds`. The root is the prompt part's nearest PropFx ancestor, else the prop whose
  `PropId` equals the prompt's Value (a controller beside its robot arm). Founder-only: `opts.ownerOnly = true`.
* Workout machines: the `workout` routine sets `FxUntil` on every PropFx root with `Machine = <Value>` and
  `PlayerUntil` on its FxStation (employees keep off a machine a player uses; a player is refused while an
  employee occupies it).
* Station attributes WorkstationService applies on perform / undoes on release: `JobPose` (rig Pose),
  `JobItem` (rig Holding), `UseProp` (PropId kept working while occupied), `StandCFrame` (snap onto a
  machine such as a treadmill, back to the InteractionPosition on release), `PlayerUntil` (blocks NPCs).
* NPC: `WorkstationService.useProp(office, propId, seconds)` (one write), coffee machines get `FxUntil`
  from `WorkstationService.perform`, `FxStation` props follow `OccupiedBy`.
* Faults (IT job): the server tags a station screen `PropFx` with `Fx = "screen"`, `FxState = "broken"`
  and sets it back to `"idle"` when fixed.

## 8. NPCs: rig attributes (client renders)

* `Pose` (string, optional): stir, pour, plate, chop, wash, wipe, push, carry, write, reach, inspect, scan,
  greet, typeStand, type, sort, plug, run, cycle, row, lift, relax, eat, phone, shower. Without `Pose` the
  client derives one from `Activity` / `WorkstationType` / `Task`.
* `Holding` (string, optional): cup, snack, plate, tray, pan, knife, sponge, laptop, blade, parcel, mopcart,
  marker, badge, dumbbell, keys. Rendered client-side (no server part). The founder assistant keeps her
  server `EmployeeCup` + `HoldingCup` (people tests rely on it); the client never draws a second cup then.
* `TablePoint` (Vector3, optional): where the client puts the meal plate while `Pose == "eat"`.

## 9. Operations posts with job points (for other packages, e.g. the hotel annex)

A post is a `Service` activity `OperationsStation<i>` with `OpsIndex = i`. Job steps move between named
points stored as attributes on the post model (all world space):
`JobPoint_<name>` (Vector3 stand point at root height, like InteractionPosition), `JobFace_<name>`
(Vector3 look-at point), optional `JobProp_<name>` (PropId used during that step) and `JobPose_<name>`
(overrides the step's pose at this point).
EmployeeConfig.JOBS[<job title>] lists the steps; a step whose point is missing runs in place at the post.
Hotel jobs: 13 "Hotel Reception" uses points `greet`, `printer`; 14 "Housekeeping" uses `cart`, `room1`..`room4`.

## 10. Live staff records (for the talk package)

`StaffService.recordOf(model)` returns the live record of an employee / operations rig (read only):
`state`, `task.id`, `station.id` / `station.room`, `role`, `name`, `lunch.phase`, `jobStep` - enough for
"what are you doing right now" dialogue without new network traffic.

Conversation hold (talk request 1, implemented): `StaffService.hold(model, face) -> boolean` pauses one
employee (false while unknown, dead, asleep (LOD), OFF_DUTY / LEAVING / INACTIVE or in the lift). State,
`Activity`, task, station and the economy weight stay unchanged; a route in progress is cancelled and
re-issued with its own callback on `StaffService.release(model)`; an operations hop stops in place and walks
on; the lunch line waits for a held guest; held employees are not drafted into meetings. Auto-release after
120 s. The client (EmployeeController) turns the head towards the rig attribute `TalkFace` (±70°) and plays
the talking gesture while `TalkingTo` is set (unless typing at a seated desk).

Office attribute `LunchesServed` (number): plates handed out in the current campus day (one write per plate,
reset to 0 when the day changes).

## 11. Movers cap

`EmployeeConfig.MAX_MOVING_PER_OFFICE` (20) bounds walkers (navigation routes + direct job hops) per office.
Employees start new walks (tasks, breaks, lunch, end-of-shift departures) only below
`EmployeeConfig.moverCap(role)` = 20 - `OPS_MOVER_RESERVE` (3); operations staff may use the reserve, so the
kitchen team / chef / fleet always get a slot. A cross-room job walk that finds the cap full waits in place
(up to 30 s) instead of failing.
