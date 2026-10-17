# Offline HQ harness (Luau mock + geometry checks + renders)

Runs the headquarters generator (`ServerScriptService.Server.Services.HeadquartersDesign`) headlessly with
the Luau CLI, dumps every instance it creates, and checks/renders the result in Python. No Roblox Studio.

`ROOT` = the scratchpad dir (parent of `harness/`). Sources come from `ROOT/work/src` (default) and are
re-scanned on every run, so modules added or changed by other agents are picked up automatically.

## Commands

```bash
harness/run.sh                         # self-test + dump tiers 1-4 + frame-consistency check
harness/run.sh --check --render        # ... plus geometry/walkability reports, heatmaps, renders
TIERS="2" harness/run.sh --check       # only tier 2
harness/run.sh --src src --out out/before_run --check --render --before   # ORIGINAL game -> out/before_*

tools/luau harness/build_dump.luau -a --tier 3 [--plot | --cf x,y,z,yawDeg] [--quiet] [--allow-thread-errors]
python3 harness/check_geometry.py out/dump_tier3.json [--res 0.5] [--radius 1.0] [--start 0,0,-60] [--probe x,y,z] [--verbose]
python3 harness/render.py out/dump_tier3.json --prefix out/tier3 [--cut-z 0 --cut-z 40] [--only plan,elev,iso,section]
python3 harness/compare_dumps.py out/dump_tier1.json out/dump_tier1_plot.json
tools/luau harness/test_mock.luau      # 150 math/instance checks
python3 harness/test_check.py          # 9 synthetic walkability expectations
```

Plan tier 0 (the garage stage, package "buildings"): `TIERS="0 1 2 3 4" harness/run.sh --check` builds it like
any tier (`build_dump.luau --tier 0` forces `session.planTier = 0`, save office index 1, staff =
`BuildingPlan.GARAGE_STAGE.staff`); with 0 in TIERS the frame-consistency check also runs for tier 0.
`check_geometry.py`, `render.py` and `tests/lead/holes.py` need no flag (tier 0 has one level, no B1, no lift;
holes.py reads the tier from the dump). Tiers >= `Plan.HOTEL_MIN_TIER` (2) contain the guest house on the west
strip (x -141..-98, z 76..172). Close-ups: `render.py --view-box=x0,x1,z0,z1` (elevations/iso/sections only).

`run.sh` exit code is non-zero if the self-test, any build, or the frame check fails. A failed build prints
the Luau traceback (module path + line, e.g. `ServerScriptService.Server.Services.X:51`) and leaves no
stale `dump_tierN.json` behind.

## Files

| file | what |
|---|---|
| `mock.luau` | Roblox API mock (instances, datatypes, Enum, services, scheduler, require, JSON) |
| `classes.luau` | generated from `tools/API-Dump.json` by `gen_classes.py`: class -> superclass, properties (+type, read-only), events, functions; all enums |
| `make_manifest.py` | scans the source tree -> `manifest.luau` (tree) + `sources.luau` (file contents as long strings); `--src/--gen` for alternative trees (`run.sh --src` uses `harness/.gen_alt/`) |
| `build_dump.luau` | builds one tier, prints `@@D {json}` per instance and `@@M {json}` meta |
| `split_dump.py` | stdout -> `out/dump_tierN.json` (`{"meta":…, "instances":[…]}`) + `out/log_tierN.txt` |
| `compare_dumps.py` | local dump vs. dump built at another campus CFrame (must map back exactly) |
| `dumplib.py` | loader (converts `--plot` dumps back to building space), OBB / vertical-ray helpers |
| `check_geometry.py` | report + walkability + `out/walk_tierN_levelY.png` |
| `render.py` | plans, elevations, axonometric, sections |
| `test_mock.luau`, `test_check.py` | self-tests |

## The mock (what is faithful, what is approximated)

Faithful (errors like Roblox, so generator bugs surface):
* Reading/writing a member that does not exist on the class (per API dump) -> `X is not a valid member of Part "Office.Foo"`.
* Wrong property types (`bool expected, got string`, `Vector3 expected`), wrong enum type, read-only properties,
  enum items that do not exist (`Enum.Material.Woodd`), `Instance.new` of abstract/unknown classes,
  unsupported attribute types/names, circular parenting, `Parent` locked after `Destroy`, `.` instead of `:`
  on methods, recursive `require`, modules not returning exactly one value, `GetService` of non-services.
* `IsA` uses the full API-dump superclass chain. Property defaults for the classes used (BasePart family,
  lights, prompts, GUI, Humanoid …). Children are reachable as `inst.ChildName` (members take precedence).
* CFrame math (Angles = Rx·Ry·Rz, YXZ/Orientation, lookAt, fromMatrix, axis-angle, quaternions, Lerp=slerp,
  object/world space) is verified by `test_mock.luau` against hand-written matrices, and end-to-end by
  building tier 1 at a translated and a 37°-rotated plot CFrame (`compare_dumps.py`, deviation ~1e-8).
* Model pivot: PrimaryPart pivot, else `WorldPivot` once set, else bounding-box centre; `PivotTo` moves all
  descendant parts rigidly; `GetBoundingBox` is oriented like the pivot. Part `Size` is clamped to
  [0.001, 2048] like Roblox (the requested size is kept in the dump as `requestedSize`).
* Signals really fire (property/attribute changed, ChildAdded/DescendantAdded, Destroying, CollectionService
  instance added); handlers run in their own coroutine like `task.spawn`.

Approximations / no-ops (logged once as `[mock:once]` when used):
* No physics: `Workspace:Raycast/Blockcast/...` return nil, `GetPartBoundsInBox/GetPartsInPart` return `{}`,
  `Model:MoveTo` is a pure translation, Humanoid movement/animation calls do nothing, `Seat:Sit` no-op.
* Scheduler with a virtual clock: `task.spawn` runs immediately, `task.defer/delay` are queued, `task.wait(t)`
  yields and returns the virtual elapsed time (>= 1/60). The runner flushes the queue for 1 virtual second
  after the build (`--settle`). Frame signals (`Heartbeat` …) are never fired, so animation loops do not
  move parts. `Signal:Wait()` resumes on the next fire or after 1 virtual second. `WaitForChild` polls for
  5 virtual seconds then returns nil with an "Infinite yield possible" warning.
* `TweenService:Create(...):Play()` applies the goal immediately. BrickColor has a ~30-entry palette.
  `math.random` is seeded (20240601), `Random.new()` without seed uses 12345, GUIDs are a counter -> dumps are
  deterministic. API functions that exist but are not implemented return nil and are counted in
  `meta.mock.stubs` (run.sh prints them). The original game needs none.
* Terrain fills are recorded in `meta.terrainOps` (not voxelised).

## Runner and dump format

Session (as specified): `userId=1001`, player table `Tester`, `Template.new()` data with company
"Nimbus Labs"/cyan, `empire.office=tier`, employees = `EmpireConfig.OFFICES[tier].staff` split evenly over
researcher/engineer/curator/marketer (24 -> 6 each … 240 -> 60 each). Accent = `CompanyConfig.getColor("cyan")`.
Default `cf = CFrame.new()` (building-local); `--plot` uses `CFrame.lookAt((160,24,252),(160,24,0))`;
`--cf x,y,z,yaw` any frame. After `Design.build` the office is parented to `workspace.Plots.Plot_01` like
`PlotService.claim`. Background-thread errors make the run fail unless `--allow-thread-errors`.

Each instance: `id, parent (id), path ("Office/Departments/F1_W_1/…"), parentPath, class, name, attrs, tags`.
Attribute values: numbers/strings/bools plain; `{"Vector3":[x,y,z]}`, `{"CFrame":[x,y,z,r00..r22]}`,
`{"Color3":[r,g,b 0-255]}`, `{"EnumItem":"Enum.X.Y"}`, `UDim2/Vector2/NumberRange/...` likewise.
BaseParts add `size, cframe, color, material, transparency, canCollide, canQuery, canTouch, anchored,
collisionGroup, shape (Part), disabled (Seat)`; Models `pivot, primaryPartPath`; ProximityPrompt
`actionText, objectText, maxActivationDistance, holdDuration, requiresLineOfSight, enabled`;
Text* `text`; lights `range, brightness, lightColor, face, angle, shadows`; PathfindingModifier
`label, passThrough`; joints `part0/part1`. `meta` holds tier, campusCFrame, staff split, counts, class
histogram, timings, mock stats, collision groups (from PhysicsService calls), terrain ops, modules loaded.

## check_geometry.py — what each check means

* **Part counts** by name prefix (letters before the first digit/underscore), collidable vs. decor,
  invisible collidable parts, NPC rig parts (excluded from building stats).
* **Bounds**: oriented-box extents; parts leaving the allowed box (default x∈[-142,145], y∈[-27,200],
  z∈[-221,228]) are listed.
* **Degenerate**: NaN/inf, any size < 0.05, >= 2048, Roblox-clamped sizes, non-orthonormal rotations.
* **Duplicates**: collidable parts with identical CFrame and size (rounded to 0.001).
* **Walkability** (1-stud grid, `--res 0.5` for finer, ~2x slower):
  1. *Surfaces*: for every solid part (CanCollide, collision group collides with `Default`, not a door,
     not an NPC rig) a vertical ray through each cell centre is intersected with the oriented box; the
     exit height is a walkable top. Rotated ramps are exact; `WedgePart` = box cut by its slope plane
     (**assumption: high side at local +Z/Back, slope faces Front/-Z** — not verified in Studio);
     Ball = sphere; Cylinder and CornerWedge are treated as their box. Tops closer than 0.35 merge.
  2. *Clearance*: a surface at height h is standable if (a) no solid under the cell centre intersects
     [h+0.3, h+5.0], and (b) no solid whose footprint is within the agent radius (default 1.3, exact 2-D
     distance to the footprint polygon) intersects [h+1.6, h+5.0] (lower things are steppable).
  3. *Edges*: 8-neighbours with |Δh| <= 1.6; diagonal moves need both orthogonal neighbours. Components via
     union-find; reachable = component of the node nearest to `--start` (default (0,0,-60), front plaza).
  4. *Doors* (attribute `DoorLeaf`, `DoorOpenCFrame` or `ClosedCFrame`, or name matching
     `Door(?!Frame|Transom)|Gate`) are open (non-blocking).
  5. *Lifts* (`--lift auto|stops|doors|volume|none`): parts with attribute `LiftStop` are linked into one
     component (nodes within 2.5 studs / ±3); otherwise parts with `LiftFloor` + "Door" in the name (original
     building) link the point 4 studs in front (LookVector) of each landing door; parts with
     `LiftShaftVolume` (or non-collidable `LiftShaft*`) link every node inside them.
  * Targets (reachable = some reachable node within 2.5 studs horizontally and ±3 vertically):
    Models with `InteractionPosition`; Seats (2.5 studs in front along LookVector, or any side — both
    numbers reported); parts with `NavigationNode`; doors (3 studs from the door plane on both sides; lift
    doors only the landing side); lift landing points; ProximityPrompts (a reachable body point within
    `MaxActivationDistance` of the part's box, line of sight ignored).
  * Heatmaps `out/walk_tierN_levelY.png` for y = -24, 0, 16, … roof: green reachable, orange standable but
    not reachable (desk tops, isolated pockets), grey surface without clearance, dark obstacle in the body
    band, red dots unreachable targets, blue dots reachable targets, star = start. True top view: +X right,
    front (-Z) at the top. `--probe x,y,z` prints the nodes/obstacles around a point.
* Known limits: passages are only guaranteed to be found if wider than 2·radius + grid size (2.6-3.6 studs
  at the defaults; `--radius 1.0` is lenient, used for comparison below); no jumping; NPC rigs ignored;
  the office is evaluated alone — streets/terrain around the plot are not in the dump, so e.g. the arrival
  path and east garden show up as cut off by small gaps that the surrounding world may cover.

## render.py

* `*_plan_yY.png`: horizontal section, parts intersecting [Y+0.5, Y+7] as filled footprint polygons (real
  colour; glass translucent; non-collidable decor faint; invisible collidable parts dashed magenta), floor
  surfaces near Y as light underlay, labels for Models/large Parts with `RoomName`/`RoomId`, 20-stud scale
  bar, 0.33 stud/px, same frame for every level/tier (front at the top, like the heatmaps).
* `*_elev_{front,back,left,right}.png`: orthographic, part-level painter's (far first), Lambert shading of
  each visible face, alpha = 1 - Transparency, dotted lines every 16 studs (floor heights).
  front = viewer at -Z looking +Z (+X appears on the LEFT).
* `*_iso.png`: axonometric from front-left above (az 35°, el 30°), face-level painter's with faces split
  into <= 4-stud tiles to reduce sorting errors.
* `*_section_zZ.png` (default z=0): front view of everything behind the plane; axis-aligned boxes are
  clipped, cut faces dark red.
* Approximations: painter's sorting can mis-order intersecting parts; balls are camera-facing discs,
  cylinders 12-gons, corner wedges boxes; parts < 0.3 studs in every axis are skipped in the far views.

## Before state (original game, `out/before_*`)

| tier | instances | parts | collidable (building) | NPC rig parts | workstations reachable | seats (any side) | nav nodes | doors | lift landings | prompts |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 5707 | 3322 | 1536 | 598 | 123/138 | 116/124 | 29/29 | 37/39 | 5/5 | 175/175 |
| 2 | 9201 | 5031 | 1900 | 1256 | 173/190 | 164/172 | 50/51 | 45/49 | 6/6 | 242/242 |
| 3 | 13754 | 7148 | 2264 | 2316 | 226/245 | 212/220 | 71/73 | 53/59 | 7/7 | 309/309 |
| 4 | 22173 | 11120 | 2992 | 4180 | 329/352 | 308/316 | 113/117 | 69/79 | 9/9 | 443/443 |

(radius 1.3, 1-stud grid; tier 1 with `--radius 1.0`: workstations 136/138, doors 39/39.) Typical real
findings: lunch-seat `InteractionPosition`s lie under the dining tables, the recovery lounge is only
reachable through a 1.4-stud slot, the floor-1 stair door opens into a pocket closed off by chairs, and
5 site parts (driveway/arrival/garden foundations) leave the allowed box.

Runtime (this container): dump 0.3 s (tier 1) … 1.4 s (tier 4); check 1.5 … 5 s (9 s at `--res 0.5`);
render 5 … 10 s; full `run.sh --check --render` for 4 tiers ≈ 50 s.
