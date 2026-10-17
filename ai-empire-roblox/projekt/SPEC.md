# AI EMPIRE — HQ Premium rebuild: shared specification

Read this whole file before writing code. It is the contract between all agents.

## 0. Environment

- ROOT = `/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad`
- Game sources (Luau, extracted from the .rbxlx): `ROOT/work/src/...`. Path = Roblox tree. Suffixes: `.module.luau` ModuleScript, `.server.luau` Script, `.client.luau` LocalScript. New files you create there become new ModuleScripts automatically (packer `ROOT/pack.py`).
- Original untouched sources for reference: `ROOT/src/...`.
- Roblox Studio is NOT available. Verify instead:
  - Syntax: `ROOT/tools/luau-compile --binary FILE > /dev/null`
  - Types/lint with Roblox definitions: `cd ROOT && python3 tests/mk_sourcemap.py && tools/luau-lsp analyze --platform=roblox --sourcemap=sourcemap_work.json --definitions=@roblox=tools/globalTypes.d.luau --formatter=plain FILES` (strict-mode noise like `Key 'X' not found in external type 'Instance'` already exists in the original code; but every *new* error in your files must be understood — e.g. unknown globals, wrong argument counts, misspelled properties/methods are real bugs).
  - API names: `ROOT/tools/API-Dump.json` is the official Roblox API dump (v0.741). NEVER invent a Roblox API, property, enum item or asset id. If unsure, grep the dump.
  - Headless execution: `ROOT/harness/` (another agent builds a Roblox mock + `run.sh` that executes `HeadquartersDesign.build` for tiers 1–4 and dumps every Part to JSON; `check_geometry.py` checks bounds/overlaps/walkability; `render.py` makes floor plans/elevations). Use it when it exists (see `ROOT/harness/README.md`).
- Style: `--!strict` at top; match the surrounding code (short functions, semicolons allowed, English comments, moderate comment density). No external assets: no MeshId, no TextureId, no SoundId other than the ones already in `CampusAudioConfig` (empty = silent). Built-in `rbxasset://textures/particles/...` is fine.
- Only edit the files your task owns (§9). If you need a change in a file you don't own, write it down in your final message instead.

## 1. Coordinates and the plan

Building-local studs. Origin = plot CFrame at street level (y=0 = ground floor finished floor). -Z faces the street. All generators build with `cf * CFrame.new(x, y, z)` so the building works on every plot/orientation.

`ReplicatedStorage.Shared.Config.BuildingPlan` (read it!) defines everything: levels (B1 = level -1 at y=-16, level L at y=16L, founder level = floors-1, roof = floors), envelope (`MAIN`, `PAVILION`, `GARAGE`, `SITE`), founder setback (`FOUNDER_FRONT_Z = -32`), core (`ATRIUM`, `SHAFT`, `CABIN`, `LIFT_DOOR`, `RISER`, `STAIR`, `STAIR_LAYOUT`, `WC`, `LIFT_LOBBY`), arrival points, access classes, all rooms per tier (`Plan.rooms(tier)`, each with id, level, name, kind, access, rectangle x1..x2/z1..z2, dept, desks, seats, doors, mood, style, flags `nowalls/open/fence/outdoor/hidden/pavilion/camera/meeting`), `accessAt`, `inside`, `roleAllows`, `playerAllows`, `employeeAllowed`, `liftStops`, lift wait/cabin/exit points, `levelLabel/levelName/floorTitle`.

`ReplicatedStorage.Shared.BuildingLayout` derives: `Layout.walls(tier, level)` (unique interior wall segments with door openings, finish solid|glass|panel|fence, height), `Layout.doors(tier)` (flat door list with id, level, kind, access, axis, x/z centre, w, h, inward normal, builder "interior"|"exterior"), `Layout.circulation(tier, level)` (corridor/gallery/lobby rectangles for ceilings and floor finishes), `Layout.slabs(tier, level)` (slab rectangles + holes: shaft, stair, atrium/skylight).

`ReplicatedStorage.Shared.Config.ArchPalette` = the only colour/material source.

Heights: slab top at level Y, slab 1 thick (Y-1..Y). Interior walls Y..Y+15. Suspended ceilings at Y+13 in rooms and corridors (not in the G lobby/atrium, not outdoors). Doors 9 high (10 for double/automatic), lintel above to Y+15.

Envelope responsibility: facades on the envelope lines of levels -1..founder (main block x=±82, z=-48, setback z=-32 on the founder level, back z=80 for levels ≥2, pavilion x=±82 / z=160 on levels 0–1, garage x=-94/112, z=-64/88) are built by the EXTERIOR generator, including exterior doors (`builder=="exterior"` in `Layout.doors`). Interior walls (all other lines, incl. the z=80 link wall on levels 0–1 and all roof head-house walls/fences) come from `Layout.walls` and are built by the INTERIOR generator together with their doors.

## 2. Office model structure (built by `HeadquartersDesign.build`)

`Office` (Model; attributes `OwnerUserId`, `OfficeTier`, `FloorCount`, `CampusCFrame`, `FacilitiesVersion=3`) with child Folders:

| Folder | Content | Owner |
|---|---|---|
| `Structure` | slabs, structural columns, atrium railings, skylight | Exterior |
| `Facade` | one Model per side/zone (`Facade_Front`, ...) | Exterior |
| `Site` | plaza, landscape, stores, garden, service yard, garage shell, ramp, barrier | Exterior |
| `Core` | stair internals, shaft walls, riser blocks, head houses | Core |
| `Lift` | `LiftCabin` Model, `LiftGuide` Part, `Landing_<level>` Models | Core (geometry) / LiftService (behaviour) |
| `Walls` | `Level_<n>` Models with wall segment parts | Interior |
| `Doors` | door Models (contract §3) | built by Interior/Exterior via `ArchKit.door` |
| `Rooms` | one Model per room, named `room.id`, `ModelStreamingMode=Atomic`, attributes `RoomId, RoomName, RoomKind, Level, AccessClass` | Interior / SpecialRooms |
| `Circulation` | corridor ceilings, floor finishes, lights, wayfinding signs, benches | Interior |
| `Cameras` | camera Parts (§6) | everyone who builds a room with `camera=true` + Exterior |
| `Navigation` | NavigationNode parts | Interior/Special/Core |
| `Blades` | GPU blade Parts in the compute room racks (PlotService colours them; attribute `Lit`) | SpecialRooms |
| `Employees`, `OperationsEmployees` | created by staff assignment | Staff |

Named instances other services look up (search with `office:FindFirstChild(name, true)`; consumers must use recursive search): `SignAnchor` (direct child of Office! Part with SurfaceGui `Sign` → TextLabel `Label`, PlotService writes the company name), `ReceptionSign`, `KitchenBrand` (Part with a SurfaceGui containing a TextLabel), `GarageSpawn` (Part, attribute `SpawnCFrame` = `cf * Plan.GARAGE_SPAWN`), `KitchenCoffeeMachine` (Part; StaffService adds steam ParticleEmitter `CoffeeSteam` if missing), `Door_G_FRIDGE` (fridge door model).

## 3. Door model contract (ArchKit.door builds, DoorService drives)

Every door except kind `opening` is a Model in `Office.Doors`, `ModelStreamingMode=Atomic`, named `Door_<DoorDef.id>`, CollectionService tag `CampusDoor`.
Attributes: `DoorId`, `DoorKind` (glass | glassdouble | solid | secure | flush | bookcase | vault | autoslide | service | cubicle | fridge | gate), `AccessClass`, `RoomId`, `DoorOwner` (number), `SecureNormal` (Vector3, WORLD space unit vector pointing into the protected side), `AutoOpen` (bool: automatic sensor door, e.g. entrance), `HoldOpen` (seconds, default 5), `Hidden` (bool), `Exterior` (bool), `DoorState` (written by DoorService: closed|opening|open|closing|locked).
Children:
- `Frame` (Model): jambs, head, threshold, optional side lights — static, never moved.
- `Leaf1` [, `Leaf2`] (Model): EVERY moving part (slab, glass, handles, kick plate, books on a bookcase…). No PrimaryPart; `WorldPivot` = hinge axis CFrame for swing leaves (so rotating the pivot swings around the hinge), any CFrame for sliding leaves. Attributes `ClosedPivot` (CFrame) and `OpenPivot` (CFrame) in world space. DoorService animates with `leaf:PivotTo(ClosedPivot:Lerp(OpenPivot, alpha))`. All leaf parts Anchored. The main slab part of each leaf carries a `PathfindingModifier` (`PassThrough=true`, `Label=AccessClass`).
- `Sensor` (Part, Transparency 1, CanCollide/CanQuery/CanTouch false): box covering the doorway + leaf sweep on both sides. DoorService treats any character root inside it as "doorway occupied".
- `PromptOut` / `PromptIn` (Parts; card reader, push plate, handle, special book spine…): each holds a ProximityPrompt with attributes `CampusAction="door"`, `Value=<DoorId>`, `Public=true`, `Side="out"|"in"`. `PromptIn` is on the protected side (egress: always allowed). Readers have a child Part `ReaderLight` (Neon) that DoorService recolours (good/bad/busy from ArchPalette.status*). Hidden doors (flush, bookcase): the outside prompt has attribute `OwnerUserId=<owner>` instead of `Public` (the client then shows it only to the founder), neutral ObjectText ("Panel", "Book"), `MaxActivationDistance <= 6`, no visible sign.
- Kinds: `autoslide` = two leaves sliding apart into side pockets, `AutoOpen=true`; `glassdouble` double swing glass; `glass` single swing glass; `solid` timber swing; `secure` metal-framed timber swing with reader both sides; `service` painted metal swing with reader; `flush` timber panel flush with wall panelling (push-to-open, no frame visible); `bookcase` full shelving unit with books (Leaf1 contains shelves+books) sliding sideways into the wall cavity; `vault` thick round/rect safe door swinging 100°; `cubicle` light swing (WC cubicles, no access check, owner of fixture logic stays FacilityService); `fridge` appliance door; `gate` barrier arm / fence gate.

## 4. Lift contract (Core builds geometry, LiftService drives)

`Office.Lift`:
- `LiftGuide`: anchored invisible Part (1×1×1, CanCollide false) at cabin floor-top height of B1: `cf * CFrame.new(0, Plan.levelY(-1), cabinCenterZ)` where cabinCenterZ = (CABIN.z1+CABIN.z2)/2 = 60.8.
- `LiftCabin` (Model, Atomic, attribute `CurrentLevel=0`): built resting at level 0 (G). Parts (all Anchored=true as built, LiftService will unanchor+weld): `CabinFloor` (12×0.5×12 top at level Y, centre x=0 z=60.8 — the assembly root), walls/ceiling/handrail/light parts, `CabinPanel` (Part with ProximityPrompt `CampusAction="liftPanel"`, `Public=true`, `MaxActivationDistance=6`), `CabinDisplay` (Part with SurfaceGui `Display` → TextLabels `Level`, `Arrow`, `Status`), two cabin door leaves `CabinDoorL`, `CabinDoorR` (single Parts, 3.05×10×0.3 closing a 6-stud centre opening x∈[-3,3], at the cabin front z≈55.1, sliding 3.0 outward (they stay within the cabin width), attributes `ClosedOffset` and `OpenOffset` = CFrame relative to CabinFloor.CFrame). A PointLight/SurfaceLight inside. Cabin interior clear ≥ 11×11, height ≥ 10. Capacity 6 (Plan.CABIN.capacity).
- `Landing_<level>` (Model, attribute `LiftStop=<level>`, `LevelLabel`): `DoorL`, `DoorR` (Parts, anchored, 3.05×10×0.3 closing the 6-stud opening x∈[-3,3] (Plan.LIFT_DOOR) at z≈53.6 just in front of the shaft front wall (z 53.75..54.25), attributes `ClosedCFrame`, `OpenCFrame` world CFrames — each slides 3.0 outward behind the wall face), `CallButton` (Part with ProximityPrompt `CampusAction="liftCall"`, `Value=<level>`, `Public=true`, ActionText "Call lift"), `Indicator` (Part above the doors with SurfaceGui `Display` → TextLabels `Level`, `Arrow`, `Status`), `WaitMarker` (invisible Part at `Plan.liftWaitPoint(level,1)` area, attribute `LiftStop=<level>`), `Sill`.
- Shaft walls, landing door leaves, sills, pit and head house parts carry attribute `LiftShaft=true` (LiftService puts them in collision group `LiftShaft`, which does not collide with group `LiftCabin`).
- Stops: every level from -1 to roof (`Plan.liftStops(tier)`).

LiftService behaviour (server): PrismaticConstraint (Servo) between `LiftGuide` and `CabinFloor`, cabin unanchored, all cabin parts welded to CabinFloor (door leaves via `Weld` whose `C0` animates), server network owner (`SetNetworkOwner(nil)`), trapezoidal motion profile by updating `TargetPosition`, collective (SCAN) scheduling of hall/car calls, door safety via the door zone, overload hold, NPC tickets. Players are carried physically by the moving floor; no PivotTo in normal operation.

## 5. Workstations and activities (unchanged contract — StaffService/WorkstationService rely on it)

`ArchKit.station(...)` returns a Model (Atomic) with attributes `WorkstationId` (unique per office), `WorkstationType="Computer"`, `Department`, `Role="any"`, `PreferredRole` (from DepartmentConfig.DEPARTMENTS[dept].role or "any"), `Capacity=1`, `Floor` (level), `RoomAccess` (room.access), `HomeRoom` (room.id), `OwnerUserId`, `InteractionPosition` (Vector3 world: where an NPC stands before sitting, ~1.2 studs beside the chair, reachable), `SeatPosition` (CFrame world of the Seat). Contains a `Seat` named `ChairSeat` (LookVector towards the desk), a screen Part named `DisplayContent` with `LiveScreen=<kind>` + `WorkstationId` + `JourneyStep` (data=1, compute=2, design=3, training=4, evaluation=5, deployment=6, growth=7), tagged `CompanyScreen`, an owner ProximityPrompt (`App`, `Section`). Tag `Workstation`.
`ArchKit.activity(...)` = invisible interaction point Model (types: Whiteboard, Pipeline, ServerRack, Conversation, Dining, Meeting, Coffee, Snack, Fridge, Lounge, Service) with the same attributes (+ optional Seat child, `FacingPosition`, `MeetingRoom`, `ConversationGroup`).
Meeting seats: `Meeting` activities with `MeetingRoom=<room.meeting>` (G project room = "ProjectRoom", boardroom = "Boardroom").

## 6. Prompts, screens, cameras, nav

- Owner prompt (opens Computer app on the client): attributes `OwnerUserId=<owner>`, `App` (empire|lab|data|compute|market|studio|arena|campus), optional `Section` (empire: overview, team, research, contracts, milestones, office, board; lab: evaluation, release; campus: building, access, fleet, shops).
- Public facility prompt: `Public=true`, `CampusAction=<id>`, `Value=<v>`, optional `OwnerOnly=true`. Actions: `door`, `liftCall`, `liftPanel`, `snack` (Value=snack id), `card`, `security`, `ownerComputer` (Value=app id), `toilet`, `flush`, `tap`, `shower`, `sauna`, `workout` (Value=machine id), `report`, `modelSafe`, `sit` (on workstation chairs; Value nil), `spawnCar` (VehicleService), `fleet`.
- Fixture keys (replace float coordinate matching): toilet `ToiletSeat` (Seat, Disabled=true) + `FlushButton` + `ToiletWater` share attribute `FixtureKey`; tap `Tap` + `TapWater` share `FixtureKey`; shower `ShowerHead` + `ShowerWater` share `FixtureKey`; treadmill/bike moving details carry `BeltMachine`/`BikeMachine` + `BeltHome`/`SpinBase` as before; sauna heater `SaunaHeater` with ParticleEmitter `Steam`.
- Screens: Part with attribute `LiveScreen=<kind>`, tag `CompanyScreen`, SurfaceGui `Desktop` with TextLabels `Header`, `Body`, `Footer` and Frame `ProgressTrack` → Frame `Fill` (exactly what `ArchKit.screen` / old `OfficeKit.screen` builds). Kinds: existing `data, engineering, training, compute, research, design, evaluation, growth, deployment, milestones, history, journey, lobby, boardroom, founder, secondary`; new `reception, showroom, customers, product, hr, security, vault, secretlab, meeting, cafe, fleet, platform, prototype, directory`.
- Cameras: Part in `Office.Cameras` named `CampusCamera_<id>` with attributes `CameraId`, `CameraName`, `ViewCFrame` (world CFrame the client camera uses), `Level`, `RoomId`, `Private` (bool: founder/hidden rooms). Never in wc/restrooms/showers/founder_bath/sauna (`Plan.NO_CAMERA`).
- Navigation nodes: `ArchKit.node` (attribute `NavigationNode=<kind>`, `Floor`, tag `NavigationNode`).
- Access volumes: for every room whose access is not public/staff, an invisible non-colliding Part covering the room (height 14) with a `PathfindingModifier` `Label=<AccessClass>` (Nav sets costs per role).
- CollectionService tags in use: `CampusDoor`, `Workstation`, `CompanyScreen`, `NavigationNode`, `CompanyEmployee`, `ClusterFan`.

## 7. Server APIs

DoorService (`ServerScriptService.Server.Services.DoorService`):
`init()`, `setAuthorizer(fn: (player, office, door) -> (boolean, string?))`, `register(office)`, `unregister(office)`, `tick(dt)`, `request(player, door: Model, side: string?) -> (boolean, string?)`, `requestNPC(npc: Model, door: Model) -> boolean`, `state(door) -> string`, `isPassable(door) -> boolean` (open), `doorsNear(office, position, radius) -> {Model}`, `find(office, doorId) -> Model?`, `lockAll(office, locked)`, `inspect(office) -> {...}`.

LiftService (`...Services.LiftService`):
`init(authorize: (player, ownerId) -> boolean)`, `attach(office)`, `detach(office)` (evacuate riders first: documented emergency exception), `tick(dt)`, `hallCall(player, office, level) -> (boolean, string?)`, `carCall(player, office, level) -> (boolean, string?)`, `panel(player, office) -> payload` (stops with allowed flags, current level, passenger flag), `isPassenger(office, character) -> boolean`, `riding(character) -> boolean`, `npcCall(office, npc, fromLevel, toLevel) -> ticket?`, `npcTicket(ticket) -> {state, target}` (state: waiting|board|riding|exit|done|failed), `npcCancel(ticket)`, `inspect(office)`.

FacilityService keeps `hasCard`, `issueCard`, `handle`, `tick`, `economyTick`, `init`; `openEmployeeDoor(npc, door)` becomes a thin wrapper around `DoorService.requestNPC`.

## 8. Quality bar

- Every room is a designed space: floor finish, ceiling with integrated lights, skirting, wall treatment, furniture matching its kind, readable nameplate at the door, free walking routes (≥ 4 studs between furniture rows, ≥ 3 behind chairs, door swing areas clear), 1–2 light objects per room.
- Vary furniture deterministically (use `room.style`, `room.id` hashes) — no identical copy-paste offices.
- Part budget per tier-4 building: Exterior ≤ 4000 parts, Core ≤ 900, Interior (walls+circulation+work/founder floors) ≤ 7500, SpecialRooms ≤ 3500. Light objects ≤ 240 total. Detail parts (< 1 stud, decorative) get `CanCollide=false, CanTouch=false, CanQuery=false`.
- Collision: furniture keeps simple collidable bodies (desk top + legs collide; tiny props don't). Seats `CanTouch=false` on workstations (NPC-controlled), `CanTouch=true` on lounge/meeting/café/bench seats so players can sit by walking into them.
- Glass: Transparency `ArchPalette.glassTransparency`, never stack two glass layers in the same view line.
- No floating parts: everything rests on a floor or is fixed to a wall/ceiling.
- Atrium edges, terraces, roof edges, stair voids: railings ≥ 3.6 studs high.

## 9. File ownership

| Agent | Owns (create/edit) |
|---|---|
| Lead (me) | `BuildingPlan`, `BuildingLayout`, `ArchPalette`, `HeadquartersDesign` (orchestrator), `pack.py`, tests |
| ArchKit | `Services/ArchKit.module.luau` (+ its README `ROOT/docs/ArchKit.md`) |
| Exterior | `Services/ExteriorDesign.module.luau`, `Services/CampusService.module.luau` (district street trees inside plots) |
| Core | `Services/CoreDesign.module.luau` |
| Interior | `Services/InteriorDesign.module.luau`, `Services/RoomKitsWork.module.luau` |
| SpecialRooms | `Services/RoomKitsSpecial.module.luau` |
| Lift | `Services/LiftService.module.luau`, `Client/Controllers/CampusController.module.luau` (lift UI part) |
| Door/Access | `Services/DoorService.module.luau`, `Services/FacilityService.module.luau`, `Services/PlotService.module.luau`, `Services/VehicleService.module.luau` (spawn lookup only), `Shared/CampusMath`, `Shared/Config/DepartmentConfig`, `Shared/Config/CampusConfig`, `Server/Main.server.luau` |
| Staff | `Services/StaffService`, `Services/EmployeeNavigation`, `Services/WorkstationService`, `Services/EmployeeRigDesign`, `Services/StaffAssignment.module.luau` (new), `Shared/Config/EmployeeConfig` |
| Screens | `Services/BuildingStateService`, `Services/AdminService`, `Client/UI/AdminPanel`, `Client/Controllers/SecurityController`, `Client/Controllers/BuildingEffectsController`, `Client/Controllers/WorldController`, `Client/UI/Apps/*.luau` (openSection only + CampusApp texts), `Shared/Config/CampusAudioConfig` |

Old generators `DepartmentDesign`, `OfficeFacilitiesDesign`, `OfficeDesign`, `OfficeKit` will be deleted by the lead once nothing requires them.

## 10. Activities, operations staff, wayfinding (addendum)

Activity types (`WorkstationType` of `ArchKit.activity` models) that generators must provide and StaffService uses:
- `Computer` (workstations, every work room; see §5), `Whiteboard` (team rooms, labs, research: 1 per room, in front of a wall board), `Pipeline` (data rooms: in front of a data-pipeline wall/board), `LabBench` (labs, evaluation labs, hardware labs, prototype lab: standing at an instrument bench; Department = room dept), `ServerRack` (compute room service aisle, Department "compute", RoomAccess "compute"; one per rack front), `Meeting` (every meeting chair, `MeetingRoom = room.meeting` or room.id; Department "evaluation" for the G project room, "executive" for the boardroom), `Conversation` (pairs at corridor nooks/front lounges: two points facing each other, `ConversationGroup`), `Coffee` (pantries on every work floor + café coffee machine; 1–3 per pantry), `Snack` (café counter), `Fridge` (café fridge, next to `Door_G_FRIDGE`), `Dining` (café chairs, with the Seat child), `Lounge` (lounge sofas, roof/pavilion-roof seats, recovery lounge; with Seat child), `Service` (operations staff posts, see below).
Department names for kitchen/social activities: "kitchen" (café, pantries), "lounge", "roof", "social".

Operations staff posts (built by SpecialRooms, used by StaffAssignment): 12 `Service` activities named `OperationsStation1..12`, Department "operations", Role "support", attribute `OpsIndex = i`, at:
1–2 reception desk (G lobby, seated, with Seat), 3 lobby security desk near the entrance (G), 4 garage security booth (B1, near the ramp foot), 5 facilities (B1 workshop), 6 IT support (G IT desk), 7 barista (café counter), 8 chef (kitchen), 9 kitchen team (kitchen), 10 café host (café), 11 facilities (B1 plant room/spine), 12 fleet (B1 fleet office). RoomAccess = the room's access class (support has public/staff/technical clearance).

Wayfinding: each lift lobby gets a floor directory (`ArchKit.wayfinding`) listing the non-hidden rooms of that level with arrows (west/east); room nameplates next to every door (non-hidden rooms; restricted rooms show `Plan.CLASS_LABEL[access]`); the G lobby gets a building directory for all levels (Plan.floorTitle) and a live `directory` screen; corridor junctions get small arrow signs. No floating billboards.

## 11. Room build pipeline (addendum)

Order inside `HeadquartersDesign.build`: Exterior → Core → InteriorDesign → RoomKitsWork → RoomKitsSpecial → RoomKitsPavilion → StaffAssignment.
- `InteriorDesign.build(ctx)` creates one Model per room in `Office.Rooms` (name = room.id, Atomic, attributes RoomId/RoomName/RoomKind/Level/AccessClass) and stores them in `ctx.rooms[room.id]`; builds all interior walls + interior doors (`Layout.walls`, `Kit.wall`, parents doors to `Office.Doors`), the generic room finish for EVERY indoor room (floor finish, ceiling with integrated lights by `room.mood`, unless the kind is in its no-ceiling list: lobby atrium area, stair, garage, compute (open services ceiling), outdoor rooms, sauna gets timber), nameplates next to doors, security cameras for rooms with `camera=true` (not in `Plan.NO_CAMERA` kinds), access volumes (§6) for every restricted room, circulation finishes (`Layout.circulation`): ceilings, floors, lights, wayfinding (§10), front-lounge furniture on work floors (x −22..22, z −48..−16: sofas, `Conversation` pairs, plants), lift lobby furnishing (bench, plant, floor directory).
- Kit modules then add furniture/fixtures/stations/screens/prompts/activities INSIDE `ctx.rooms[id]` (create the model if missing) and never rebuild walls, floors, ceilings or cameras.
  - `RoomKitsWork` kinds: team, architecture, datalab, control, evaluation, launch, support, studio, platform, lab, hwlab, hr, focus, phone, meeting, pantry, lounge, print, wc, boardroom, founder_office, founder_assist, founder_library, founder_bath, terrace.
  - `RoomKitsSpecial` kinds (G + B1): lobby, atrium, datahall, ups, visitor_lounge, showroom, project_meeting, compute, first_ai, itdesk, cafe, kitchen_boh, delivery, mailroom, garage, b1_lobby, plant, fleet, workshop, storage, spine, liftpit, service_passage. Also the 12 operations stations (§10).
  - `RoomKitsPavilion` kinds (pavilion + roof): pavilion_corridor, gym, recovery, sauna, restrooms, showers, garden_lobby, security, archive, secret_passage, secret_lab, prototype, vault, roof_lobby, roof_terrace, roof_tech, roof_solar, machine, pavilion_roof.
- Named instance added: `CompanyStele` (Part with SurfaceGui TextLabel, plaza pylon; PlotService will write the company name like ReceptionSign).

## 12. Realism upgrade (addendum — supersedes earlier statements where they conflict)

- PUBLIC FRONT OF HOUSE: the reception hall `G_LOBBY` (x −22..22, z −48..−20), `G_VISITOR`, `G_SHOWROOM` and `G_CAFE` are class `public`: anyone may enter without a card (`Plan.playerAllows` returns true for public). The main entrance `G_ENTRANCE` is AccessClass `public` → its automatic doors open for everybody approaching from either side. The House Kitchen café therefore sells to visitors without a card.
- BADGE SPEED GATES: a 3.6-high glass barrier line at z = −20 (x −22..22) separates the public hall from the staff atrium `G_ATRIUM` (kind `atrium`, x −22..22, z −20..36, class staff). `Layout.walls` returns this line as finish `barrier` (height 3.6) with five door openings of kind `speedgate` (lanes 3 studs; one accessible lane 4.5 at x=−14). Kit.door kind `speedgate`: two stainless/glass gate cabinets (pedestals ≈1.5 wide, 3.4 high) on the lane sides with glass flaps that swing/retract open; `AutoOpen=true` behaviour: opens for an authorized person (card holder/owner/employee NPC via requestNPC) approaching from the public side and for anyone leaving from the staff side; reader on the public side. The visitor lounge connects to the west staff corridor only through a staff door (`G_VISITOR_D1`, secure side = corridor; `DoorDef.inward` already points into the protected corridor).
- DOUBLE-HEIGHT RECEPTION HALL: on level 1 the area `Plan.LOBBY_VOID` (x −22..22, z −48..−24) is open (slab hole kind `lobbyvoid`); the front gallery strip z −24..−16 on level 1 becomes a bridge between the hall void and the atrium void (glass balustrades on both sides). The front facade lantern over the entrance therefore spans G + level 1 (y 0..32) as one tall glazed hall front.
- DATA HALL: B1 gets a real data centre hall `B1_DATAHALL` (kind `datahall`, class compute, x −94..−22, z −64..64, doors from the B1 lift lobby and a second secure exit to the garage). The garage room shrinks to x −22..112. `Plan.GARAGE_ARRIVAL` moved to (40, −13, 10). The G compute room is now "Compute Operations" (kind compute: operations/monitoring with a showcase cluster behind glass).
- Kit additions: wall finish `barrier`, door kind `speedgate`; data-centre grade rack (`Kit.serverRack`) — see the ArchKit doc once updated.
- Wall thickness (from Core integration): solid/panel interior walls are 1.0 thick centred on their line (stair inner faces at x −21.5/−7.5, z 54.5); glass partitions ~0.4. `DoorDef.swing="out"` (stair doors) swings away from the room onto the lobby. The lift portal cladding/jambs stand proud of the shaft front wall to z≈52.95 on every landing — keep furniture/finishes clear of x −8..8, z 50..54 in lift lobbies.
