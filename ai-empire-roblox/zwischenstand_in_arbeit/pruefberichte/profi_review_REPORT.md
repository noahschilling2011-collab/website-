# AI Empire: pre-release review of snap_lab_1150

**Target:** `agents/stable/snap_lab_1150`, which is exactly the code in `AIEmpire_Stand_2026-10-11_ki-studio.rbxlx` (Luau `--!strict`). Reviewed 2026-10-17, read-only; scratch files are in `agents/robloxreview/`.

**Inputs:** finder results and verifier verdicts for the security and DataStore lenses. For the performance lens the input had finder results only, because it was cut off before the verdicts. The report author re-checked P1-P7 against the snapshot code, and their severities are the author's. The UI/typing lens (`ui_types.md`) was not an input and is not covered here.

**Rules for every fix:**
- Economy truth stays in CompanyOps/EmpireMath.
- No fix changes the save format, and `meta.lockJobId` stays a string, so old saves keep loading.
- Admin stays username-based.
- No asset or animation ids, and no paid random items.
- Line numbers refer to the snapshot. Re-locate them in `work/src` before editing.

## Verdict at a glance

| severity | count | findings |
|---|---|---|
| critical | 0 | none |
| high | 2 | DS-1, P1 |
| medium | 5 | DS-3 (= F1), DS-2, P4, P2, P3 |
| low | 8 | F2, DS-4, F3, F5, F4, P5, P6, P7 |

No path was found that creates money, items or paid goods.

**Fix before publishing:** DS-1, DS-3, DS-2 and DS-4. They are one small SaveService/SessionService patch plus one ShopService line. The patch is already written and probed: `agents/robloxreview/fix.diff`, applied in `agents/robloxreview/patched/`.

**Strongly recommended:** P1, a cheap client-side change. Everything else can ship in the next update.

## Findings (most severe first)

### DS-1 (high): BindToClose does not wait for final saves that PlayerRemoving already started
*DataStores lens. Verifier: real, high.*

- **Where:** `ServerScriptService/Server/Services/SessionService.module.luau:332-357` (early return at 334, `released = true` at 337) and `:380-397`.
- **What goes wrong:** PlayerRemoving's `closeSession` yields inside the final `UpdateAsync`. At shutdown, BindToClose calls `closeSession` again for each listed session. Each call returns at once because `released` is already set, so `pending` reaches 0 and the callback returns while the real save is still in flight.
- **Failure path:** the last player on a server leaves, so the server closes (`Enum.CloseReason.ServerEmpty` is in API-Dump). This hits every solo or small server, and also players removed during a developer shutdown. Progress since the last autosave is lost (90 s interval plus up to 15 s stagger), and the lock is left behind, so a quick rejoin is kicked for up to 180 s.
- **Evidence:** `probe_save.luau -a bindtoclose`: the callback returned at t=0.40 s with stored money=100, and the final save committed 777 at t=2.40 s. The verifier re-ran it and got the same result. Roblox's sample stalls shutdown until saves finish (https://create.roblox.com/docs/reference/engine/classes/DataModel#BindToClose).
- **Fix:** add a module counter `local closing = 0`.
  - In `closeSession`, do `closing += 1` after `released = true`, and `closing -= 1` after `sessions[player] = nil`.
  - In BindToClose, use `while (pending > 0 or closing > 0) and os.clock() - started < 25 do task.wait(0.25) end`.
  - This is in `fix.diff`; the patched probe stores 777.

### P1 (high, re-checked by the report author): the client poses every rig within 120 studs at 30 Hz, on every floor
- **Where:** `StarterPlayer/StarterPlayerScripts/Client/Controllers/EmployeeController.module.luau:394-462`.
  - Rate at :422: `if distance < Config.NEAR then 1/30 else 0.2`, with NEAR=120 (EmployeeConfig:5).
  - `OffDuty` is read every frame for every rig at :407.
  - A new pose table is built at :216.
- **What goes wrong:** distance is 3-D only, so rigs behind floors are posed too. Each pose costs about 12 GetAttribute calls, FindFirstChildOfClass, FindFirstChild, a table of 6 CFrames and 6 `Motor6D.Transform` writes.
- **Failure path:** a tier-3/4 owner on a phone in their own HQ, which is the core loop for the most engaged players. The phone poses 256 of 258 rigs, 238 of them on other floors. That is 7,690 poses/s, 46,140 Transform writes/s and 92,380 GetAttribute/s, plus about 7.7k tables and 46k CFrames of garbage per second. The likely result is frame drops and heat. Visitors pay the same.
- **Evidence:** `perf/probe_employee_client.luau` (`perf/out2/probe_employee_client.txt`). The mock's 6.4 ms/frame is interpreter time, so only the ratio counts. PropFxController already culls by height (VERTICAL 24).
- **Fix (client only):**
  - `local sameFloor = math.abs(root.Position.Y - camera.CFrame.Position.Y) < 12`
  - `cache.next = time + (if sameFloor and distance < 60 then 1/30 elseif sameFloor and distance < Config.NEAR then 0.1 else 0.2)`
  - Move the `OffDuty` read behind `time < cache.next`, or cache it with `GetAttributeChangedSignal("OffDuty")`.
  - In `perf/patched` this gives 1,600 poses/s (-79 %) and mock frame time 6.4 to 2.3 ms.
  - With no Animator tracks (the project uses no animation ids), Transform holds between poses, so rigs posed less often do not snap.
- **Severity note:** drop to medium if a device profile shows well under 1 ms per frame.

### DS-3 = F1 (medium): a late autosave lands after the release save, rolls back and re-locks the key
*DataStores and security lenses, merged. Verifiers: both real; the security verifier said medium, the DataStore verifier low. This report uses medium, the same as DS-2, because the impact is the same: a silent rollback plus a 180 s lockout.*

- **Where:**
  - `SessionService.module.luau:346-354`: waits only 15 s on `session.saving`, then saves with release.
  - `SaveService.module.luau:146`: payload snapshot taken at call time.
  - `:148-177`: waitForBudget up to 10 s, then `task.wait(2^attempt)`.
  - `:155`: only a foreign lock is refused.
  - `:162`: a non-release save writes `lockJobId = jobId`.
  - The same race exists with `Shop.saveNow` (ShopService:335-357).
- **What goes wrong:** during a DataStore hiccup an autosave can run past 15 s. The release save commits the new data with lock=nil. The autosave's retry then accepts the nil lock, writes the older snapshot and re-locks the key for this server.
- **Failure path:** the player leaves during throttling. The next join elsewhere is kicked after 6x4 s. After 180 s the player loads the older snapshot. Receipts stay consistent: they roll back together with the grant, and `saveNow` refuses closing sessions (ShopService:341), so Roblox retries. Nobody can trigger this on purpose.
- **Evidence:**
  - `probe_save.luau -a stale_autosave`: the final save wrote 777/nil at 16.6 s, then the autosave wrote 100/MOCK-JOB at 19.4 s.
  - `sec_probe/probe_save.luau`: "money=1000 lockJobId=THIS_SERVER -> CONFIRMED".
- **Fix:**
  - In `SaveService.save`, use a strict check: `if meta.lockJobId ~= jobId then lostLock = true; return nil end`. It also refuses nil; a live session always holds its lock because `load` writes it.
  - Combine it with the DS-2 token.
  - In `saveSession` (SessionService:272), kick only `if lostLock and not release and not session.released`.
  - The strict check is in `fix.diff`; the `not session.released` guard is new. F1's alternative `releasing[key]` flag is then unnecessary.

### DS-2 (medium): a rejoin on the same server loads stale data, which later overwrites the newer final save
*DataStores lens. Verifier: real, medium.*

- **Where:** `SaveService.module.luau:16` (`SESSION_ID` = `game.JobId`), `:84`, `:104` (this server's own lock counts as free) and `:155` (a nil lock is accepted). `SessionService.onPlayerAdded` (:292) is keyed by Player and never sees the old session.
- **Failure path:** the old final save is slow (the 15 s wait or the 2/4/8 s retries). The player rejoins the same server by following a friend or on a private server. The new load locks at once. The old final save commits 777 with lock=nil. The new autosave then overwrites it with the stale 100.
- **Evidence:** `probe_save.luau -a rejoin`: commits at 0.80 s (100), 6.40 s (777) and 6.80 s (100). Patched, the new load waits for the old token and then gets 777.
- **Fix:** one token per session.
  - In `load`: `local jobId = SESSION_ID .. "/" .. HttpService:GenerateGUID(false)`, returned as a third value.
  - Keep it in a typed `lockToken: string?` Session field (better than the `(session :: any)` cast in fix.diff).
  - Pass it to `save(userId, data, release, token)`, `releaseLock(userId, token)` and ShopService `deps.save` (4th argument).
  - `lockJobId` stays a string, so old saves load; a lock from an old-version server just counts as foreign, as today.
  - The patched copy passes Shop 146/146, econ_migration 95/95 and econ_service 92/92, and luau-lsp strict reports 0 diagnostics.

### P4 (medium, re-checked by the report author): a whole HQ is built, and on upgrade destroyed and rebuilt, in one server frame
- **Where:** `HeadquartersDesign.module.luau:52-79`, with the generator loop at 73-76 and no yield anywhere in the generators. Callers: `PlotService.module.luau:144` (claim) and `:98` (refresh: `office:Destroy()` then build).
- **Cost:** tier 4 is 47,628 instances, 475,580 property writes, 28,151 SetAttribute and 2,432 AddTag in one call (`perf/probe_build_cost.luau`). Tier 1 is 20,910 instances.
- **Failure path:** a tier-4 player joins, or anyone upgrades. Every player rubber-bands, and doors, the lift and NPCs stall. Nearby clients then get the whole tree at once. Stall length on a live server is unsure.
- **Fix:**
  - Build unparented as now, but `task.wait()` between generators and every N rooms in RoomKitsWork, RoomKitsSpecial and RoomKitsPavilion. Parent once at the end.
  - Add a per-plot `p.building` flag. A refresh during a build only sets `p.dirty`, and refresh re-runs after the build.
  - After the build, require `p.owner == session.player and not session.closed`, otherwise destroy the new office.
  - No save change.

### P2 (medium, re-checked by the report author): streaming radii are too large for these offices
- **Where:** `pack.py:128-133` (published place).
  - Settings: MinRadius 128, TargetRadius 512, StreamOutBehavior Opportunistic, IntegrityMode 2 (MinimumRadiusPause).
  - API-Dump tags these Workspace properties NotScriptable, so they can only be set in the place file.
- **What goes wrong:** one tier-4 office is 28,341 parts.
  - Arrival plaza: 125,526 office parts within 512 studs with tier-4 neighbours, 60,042 with tier-1 neighbours.
  - Tier-4 lobby: 23,510 parts inside the 128-stud pause radius.
  - Per the docs, in MinimumRadiusPause mode "all client-side simulation is paused when content is not streamed in up to the minimum radius" (https://create.roblox.com/docs/reference/engine/enums/StreamingIntegrityMode).
- **Failure path:** a phone player joins a full server, respawns or is sent home and stays frozen until those parts arrive. Low-memory phones then stream content back out, which causes pop-in. Effect on memory and FPS: unsure.
- **Evidence:** `perf/stream_budget3.py` with the real plot layout and dumps built from the snapshot. The shared world is only 14,749 parts. The only part budget test covers tier 0 (<4000, `tests/buildings/test_build.luau:222`).
- **Fix:**
  - Set TargetRadius 256 (27,235 parts, -78 %) and MinRadius 64 (5,196 parts in the lobby).
  - The skyline is already Persistent.
  - Add per-tier office part budgets.
  - Before shipping, check in Studio that AirTraffic, CityLife and the travel arrival still work at 256.

### P3 (medium, re-checked by the report author): server Humanoids keep their state machine on while anchored or parked
- **Where:** `StaffService.module.luau:485-512`.
  - Only "sleep" sets `EvaluateStateMachine=false` (:498); "reduced" does nothing on the server.
  - The LOD uses 3-D distance only (:572).
  - `park` (:125-128) anchors rigs but leaves the state machine on.
- **Evidence:** `perf/probe_staff_server*.luau`.
  - 10:30, tier 4, founder in the lobby: all 258 rigs evaluate, but only 31 roots are unanchored.
  - 23:00: 256 rigs are parked and hidden, and all 258 still evaluate.
- **Failure path:** five or six big offices put 700-1,500 live state machines on one server. Heartbeat time grows, and doors, the lift and remotes lag for everyone. The size of the gain is unsure.
- **Fix:** set `EvaluateStateMachine=false` wherever a rig is anchored to stand or park.
  - Places: `park` (StaffService:127), leave (:454), WorkstationService standing stations (:192/:207), StaffJobs:81/295 and StaffEvents:103.
  - `Nav.go` (EmployeeNavigation:160) and StaffEvents:206 already turn it back on before a walk.
  - Leave seated stations (WorkstationService:197-198) until Studio confirms the sitting pose still works. The client reads `Humanoid.SeatPart` (EmployeeController:426), which API-Dump tags ReadOnly and NotReplicated; otherwise publish a `Seated` attribute.
  - Economy is unchanged (CORE_SPEC 5.1).

### F2 (low): joinMeeting trusts the client-controlled position, so a teleport gives a free abroad meeting
*Security lens. Verifier: real, lowered to low.*

- **Where:** `EmpireService.module.luau:439-453` (40-stud `MEETING_RANGE` at :421) and the prompt path at :476-482 with `CityService.module.luau:139-148`. Neither path reads `City.state` (CityService:47-50).
- **Failure path:** without the $700 ticket, an exploiter moves his root next to an abroad office (for example Helix) and invokes `joinMeeting`. He gets `joined=true` and +0.15 trust (CompanyOps:43/755). This is a self-only shortcut: $700 and one flight per visit.
- **Evidence:** `sec_probe/probe_net.luau` P1.
- **Fix:** in both paths, lazily require CityService, then refuse with `{ok=false, err="TOO_FAR"}` unless `City.state(session.player) == (if client.trip == "abroad" then "abroad" else "home")`. Flights (CityService:159) and the shuttle (ShuttleService:426) both set `abroad`, so legitimate travellers pass.

### DS-4 (low): one failed probe at boot turns saving off for the server's lifetime
*DataStores lens. Verifier: real, lowered to low.*

- **Where:** `SaveService.module.luau:59-74`: a single `GetAsync("__probe")` with no retry, after which `load` returns "storage unavailable" (:79-81).
- **Failure path:** one transient error at boot means every player routed to that server is kicked until it empties, and leaderboards are off there. No data is lost.
- **Evidence:** `probe_save.luau -a init_fail`.
- **Fix:** `if RunService:IsStudio() then candidate:GetAsync("__probe") end; store = candidate`. Live servers rely on the existing load and save retries. This is in `fix.diff`.

### F3 (low): a driver can noclip his own car into another company's HQ, even the founder-only vault, and leave it there
*Security lens. Verifier: real, low.*

- **Where:** `VehicleService.module.luau:124` (the driver gets network ownership) and :171-178 (only checks FLOOR_LIMIT, `CityPlan.drivable`, a distance bound and velocity). `FacilityService.module.luau:515` lets VehicleSeat occupants skip the access guard.
- **Failure path:** he steps the car through walls in 30-stud moves, gets out (the guard moves him, the car stays), and the car blocks the room. The victim cannot remove it. Prompts inside stay access-checked, so this is griefing, and it needs an exploit.
- **Evidence:** `sec_probe/probe_car.luau`.
- **Fix:** in `Vehicles.tick` at :174, add `or insideForeignHQ(position, userId)`. The helper loops `Plot.all()` and returns true when `p.owner and p.office and p.owner.UserId ~= ownerId and Plan.inside(tier, p.cframe:PointToObjectSpace(pos))`, with tier from the `OfficeTier` attribute. Plan and Plot are already required, and the existing branch ejects the driver and resets the car.

### F5 (low): a visitor can keep an owner's public NPC busy indefinitely
*Security lens. Verifier: real, low.*

- **Where:** `TalkService.module.luau:385-388` (`own` at :375).
- **Failure path:** the visitor keeps re-opening a talk with another company's receptionist or barista. The owner gets NPC_BUSY, as asserted by `tests/talk/test_talk.luau:209-214`. The hold safety release after 120 s (StaffService:475) forces him to re-open, but he can. Dialogue only, no economy effect.
- **Fix:** at :386, `if busy and not busy.closed and busy.player ~= player then if own then finish(busy, busy.farewell, true) else return refuse(player, i, "NPC_BUSY", viaPrompt) end end`. Update the test.

### F4 (low): GrantGuestCard pushes a Tool and a toast to any online player without consent
*Security lens. Verifier: real, low.*

- **Where:** `FacilityService.module.luau:260-266` and issueCard :87-97, which destroys and re-creates the card.
- **Failure path:** repeated grants (burst 3, then 1/s) re-create the victim's card, unequipping it if held, and re-send the toast. The client deduplicates identical text, so one granter keeps one sticky toast alive. Alts can fill the toast stack. Minor harassment.
- **Fix:** if a valid grant exists, only extend the expiry (the `guests` entry and the existing `cards[tool].expires`) and return ok with no new Tool and no toast. Add a 60 s per-(granter, target) cooldown.

### P5 (low, re-checked by the report author): every live screen within 120 studs is re-rendered at 1 Hz, whatever floor it is on
- **Where:** `BuildingStateService.module.luau:766-792`, interval rule at :785.
- **Cost:** in a tier-4 lobby, 407 screens per second are re-rendered, 385 of them on other floors, and this repeats per occupied office. Only about 60 Text changes/s replicate, so the cost is server CPU.
- **Fix:** track the nearest player's position, and use the 6 s interval also when `math.abs(screen.Position.Y - nearest.Y) > 12`.

### P6 (low, re-checked by the report author): door leaves are animated on the server with PivotTo every Heartbeat
- **Where:** `DoorService.module.luau:260-267` and :290-296, duration 0.6 s.
- **Cost:** about 6,200 replicated part CFrame writes per minute per tier-4 office. The bookcase door alone has 65 leaf parts. Doors may look like they step on phones.
- **Fix:** replicate `DoorState` plus `DoorMovedAt`, and animate the leaves on the client with PropFxController's existing `hinge` and `slider` kinds (:36). The server keeps `setCollision` and the timers.

### P7 (low, re-checked by the report author): GPU buy/sell, hire, fire and training steps run several full recursive office scans
- **Where:** `PlotService.module.luau:107` and :118-121 (7 recursive FindFirstChild calls plus FindFirstChildWhichIsA over 47,627 descendants). Callers: ComputeService:44/75/88, EmpireService:56/83/108/287 and AIModelService:354/550/581. Hire and fire add a full GetDescendants pass.
- **Fix:** cache SignAnchor/Label and the board GUIs per office at build time, or search only `office.Site` and `office.Facade`.

## Rejected by the verifiers (not findings)

| id | claim | why it is not a finding |
|---|---|---|
| F6 | TripAction (Net:62) is never bound | No handler runs, so nothing can be bypassed. Hygiene: bind a `NOT_AVAILABLE` stub. |
| F7 | A game pass is trusted from PromptGamePassPurchaseFinished | Unreachable: all pass ids are 0 (ShopConfig:63-68, `passById` returns nil for ids <= 0). Re-check before real ids are set. |
| DS-5 | Studio writes the live store | Only editors in Studio can do it, by design (SaveService header). |
| DS-6 | Repeated lock kicks for up to 180 s | The lock works as designed; its common cause is DS-1. |
| DS-7 | 8 s sleep after the last failed save | Harmless nit. `fix.diff` removes it anyway. |

## Checked and OK

**Remotes and validation**
- 49 of 50 Net.FUNCTIONS go through Remote.bind with per-player token buckets, a session check, the company gate, a payload replaced by `{}` when it is not a table, and a pcall that returns a generic SERVER_ERROR. The 50th is F6.
- Guard rejects NaN and inf and checks ids and text (UTF-8, control, zero-width and bidi characters). TextFilter fails closed on live servers.
- The server never calls InvokeClient.

**Money and purchases**
- ProcessReceipt validates every field, grants with no yield between grant and record, returns PurchaseGranted only after a successful save, and is idempotent through `shop.receipts` (capped at 100, not replicated).
- All prices are server-side. Spend and grant reject NaN, inf and negative amounts.
- Checked: GPU, data, cooling, upgrade, research, lab, jet, cars and retail; one-shot rewards (quest, daily, deliver); vouchers; BuyModelAccess; the snack cap of 16.
- Handlers that yield re-check state afterwards.

**Ownership**
- Every lookup uses the caller's own session.
- Range checks: prompts 12-16 studs, doors 10 studs.
- Doors use card and access class, and the lift checks integer levels, card and floor. The car seat is owner-only, and vehicle input is capped at 30 Hz.
- Talk accepts only options the server offered.
- Username admin is as designed and not exploitable beyond that; DebugService is Studio or DEV_USER_IDS only (empty).

**DataStores**
- Player data is written only through UpdateAsync. A failed or invalid load kicks without overwriting, and saves from a newer version are refused. NaN is sanitized, a foreign lock blocks the load, and a lost lock stops saving.
- Migration survived fuzzing, and old v5 to v6 saves load (95/95).
- The worst-case record is 150,810 characters, 3.6 % of the documented 4,194,304 per key (https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits).
- The leaderboard's 6 GetSortedAsync calls per 3 min are under the documented 5 + numPlayers x 2 per minute.

**Performance that is fine**
- The staff tick is bounded, with at most 2 path jobs at a time and NPC network owner nil.
- Heartbeat connections disconnect when idle, caches are weak, and per-player tables are cleaned on leave.
- Every GUI sets MaxDistance, no light casts shadows, and PropFx uses a vertical LOD with one BulkMoveTo per frame.
- CityLife caps at 60 walkers and 25 cars, and AirTraffic has a LOD.
- Attribute churn is 22/s, and a State delta takes 1.3-1.7 ms in the mock.

**Tests**
- At release: 99/99 green.
- Report author's run on 2026-10-17 (`agents/robloxreview/report/runall.txt`): 99 suites, 233,039 checks passed and 31 failed, all in 8 suites:

  | suite | failed checks |
  |---|---|
  | shop | 13 |
  | shop_client | 3 |
  | models_ui_full | 2 |
  | apps_ui_garage | 5 |
  | apps_ui_client | 2 |
  | apps_ui_save | 2 |
  | apps_ui_mid | 2 |
  | apps_ui_rich | 2 |

- This is test drift. Those test files were rewritten after the release (apps 10-11 17:26, models 17:29, shop 10-12 06:51/07:19) and expect later UI, for example "Shop entry in the Menu rail".
- `run_all` usually prints rc=0 even when checks fail, so read the "N failed" count.
- No suite covers save locking or BindToClose. Turn `probe_save.luau` (bindtoclose, rejoin, stale_autosave, init_fail) into a regression suite.

**APIs checked in API-Dump** (`report/apicheck.py`): GenerateGUID, EvaluateStateMachine, SeatPart (ReadOnly, NotReplicated), the Streaming* properties and StreamOutBehavior (NotScriptable), MinimumRadiusPause, Opportunistic, GetAttributeChangedSignal, IsStudio, PreSimulation, Heartbeat, GetDataStore, GetRequestBudgetForRequestType, UpdateAsync, GetAsync, BindToClose, JobId, CloseReason.ServerEmpty, ProcessReceipt, PromptGamePassPurchaseFinished, UserOwnsGamePassAsync, SignalPromptGamePassPurchaseFinished (RobloxScriptSecurity), Kick, RequestStreamAroundAsync, PivotTo, Motor6D.Transform, SetNetworkOwner, LocalTransparencyModifier, OnServerInvoke, VehicleSeat.Occupant.

## Only Roblox Studio or real devices can confirm
1. **DS-1:** real shutdown timing. Join alone, earn money, leave, rejoin within 10 s, before and after the fix. The exact BindToClose grace period is unsure.
2. **P1:** frame time with the MicroProfiler on a mid-range phone in a tier-3/4 lobby. This decides high or medium.
3. **P2:** memory and the join/respawn freeze at 512/128 versus 256/64. Check that AirTraffic, CityLife and the arrival look right at 256.
4. **P3:** whether SeatPart and the sitting pose survive with the state machine off, plus server Humanoid time.
5. **P4:** stall length with the server MicroProfiler on a tier-4 join and an upgrade.
6. **P6:** door smoothness on a phone.
7. **F7:** before setting real pass ids, whether a client can make the server's PromptGamePassPurchaseFinished fire. If unsure, confirm with UserOwnsGamePassAsync before persisting.
8. **F4:** how the toast stack looks with two or three granters.
9. **F6:** whether the engine queues calls to an unbound RemoteFunction is unsure; a stub makes the question moot.
10. **Kick:** whether `Player:Kick` on a player who already left is a silent no-op is unsure; the DS-3 guard avoids the call.

## Files
All in `/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad/agents/robloxreview/`:
- `fix_plan.json`, `fix.diff`, `patched/`
- `security.md`, `datastores.md`, `performance.md`
- `probe_save.luau`, `sec_probe/`, `perf/`
- `report/runall.txt`, `report/apicheck.py`

## Addendum (lead, 2026-10-17): verifier verdicts the report input lost

The report step received a truncated input (60k chars): the performance verifier verdicts and the whole UI/typing lens were cut off. Below are the adversarial verifier verdicts from the workflow journal. Where the verifier severity differs from the report author's (P1: verifier medium, author high; P2/P3: verifier low, author medium), the fix package uses the verifier severity unless a probe on work/src shows more.

NOTE: the snapshot predates the menu package. UI-1 (old Computer at 5-9 pt on phones) is partly replaced by the new Menu in work/src; the old tabs that the menu still hosts were measured at 11.2 pt by the menu package (P3 not built). Re-check every UI finding on work/src before fixing.

| id | real | verifier severity | finding | where | verifier reason |
|---|---|---|---|---|---|
| P1 | True | medium | Client poses every rig within 120 studs at 30 Hz, on every floor (no vertical cull) | StarterPlayer/StarterPlayerScripts/Client/Controllers/EmployeeController.module.luau:394-466 (rate at 422, OffDuty read every frame at 407, new pose table at 216) | Confirmed in the snapshot. EmployeeController.module.luau:394-462 runs every PreSimulation over all rigs, with no vertical or floor test. Line 422 gives every rig within Config.NEAR=120 a 1/30 s period (EmployeeConfig:5). Line 407 calls GetAttribute('OffDuty') on every rig every frame, before the `time < cache.next` early-out at 419. Line 216 builds a new 6-entry table per pose. PropFxController:2 |
| P2 | True | low | StreamingTargetRadius 512 pulls ~4.4 offices (125k parts); MinRadius 128 + MinimumRadiusPause holds 23.5k parts in the pause radius | pack.py (published place settings: AIEmpire_Stand_2026-10-11_ki-studio.rbxlx):128-133 | Only half of this holds. The values are confirmed in pack.py:128-133 and in out/rel1150/AIEmpire_Stand_2026-10-11_ki-studio.rbxlx (Min 128, Target 512, StreamOutBehavior 2=Opportunistic, StreamingIntegrityMode 2=MinimumRadiusPause, matching the API-Dump enum values). REFUTED part: StreamingTargetRadius 512 is not excessive. Roblox documents 1024 as the default and recommended target radius (https: |
| P3 | True | low | Server keeps the Humanoid state machine on for anchored and parked rigs; the 'reduced' LOD does nothing on the server | ServerScriptService/Server/Services/StaffService.module.luau:485-512 (EvaluateStateMachine=false only for sleep at 498), 572 (LOD by 3-D distance only), 125-128 (park) | The code is as described. EvaluateStateMachine=false is set only in setLod('sleep') (StaffService:498). park() (:125-128) and leave() (:454) anchor the root and set OffDuty but leave the state machine on. The 'reduced' LOD has no server effect: grep shows only `~= 'sleep'` checks, and the client never reads SimulationLOD. The code itself treats parked rigs as state-machine-off: on waking from slee |
| P4 | True | medium | A whole headquarters is built (and on upgrade destroyed and rebuilt) in one synchronous server frame | ServerScriptService/Server/Services/HeadquartersDesign.module.luau:52-82 (generator loop 73-76); callers PlotService.module.luau:144 (claim) and :98 (refresh rebuild) | Confirmed. HeadquartersDesign.build (:52-82) runs every generator plus staff assignment in one synchronous call. grep finds no task.wait/defer/delay/spawn in HeadquartersDesign, ArchKit, Exterior, Core, Interior, RoomKits*, StaffAssignment or EmployeeRigDesign. I re-ran perf/probe_build_cost.luau on the snapshot: tier 4 builds 47,628 instances with 475,580 property writes, 28,151 SetAttribute and  |
| P5 | True | low | Every live screen within 120 studs is re-rendered at 1 Hz, regardless of floor | ServerScriptService/Server/Services/BuildingStateService.module.luau:766-792 (interval rule at 785) | Confirmed. In BuildingStateService.tick (:766-792) the interval is chosen by 3-D distance to the nearest player only (`if distance<120 then 1 else 6`, :785), so screens on other floors inside 120 studs are re-presented every second. The probe output shows 407 rewrites/s in a tier-4 lobby, 385 of them on other floors. write() compares label.Text first, so replication is small (60 changes/s, ~3.3 KB |
| P6 | False | low | Door leaves are animated on the server by PivotTo every Heartbeat and replicated as CFrame changes | ServerScriptService/Server/Services/DoorService.module.luau:260-266 (apply -> leaf.model:PivotTo), 294 (Heartbeat while animating) | The mechanism is real: DoorService:260-266 calls PivotTo on the leaves from a Heartbeat connection, which exists only while a door animates. The harm is not shown. Using the finding's own numbers, 26 cycles/min x 72 steps x 3.4 leaf parts comes to ~100 replicated part CFrames per second per office. That is a small replication load, sent only to clients that have the door streamed in. The 65-part b |
| P7 | False | low | Every GPU buy/sell or hire runs several full recursive scans of the office tree | ServerScriptService/Server/Services/PlotService.module.luau:107, 119 (refresh); callers ComputeService.module.luau:44,75, EmpireService.module.luau:56,83; StaffAssignment.module.luau:219 | PlotService:107 and :119 do run 7 recursive FindFirstChild calls over ~47.6k descendants on each Plot.refresh, but the cost is bounded and the spam path costs the player. BuyGPU and SellGPU are rate-limited (burst 4, 2/s each, ComputeService:93-94). buyGPU returns RACK_FULL or NO_MONEY before refresh, and sellGPU needs an owned GPU and refunds less than the price, so spamming burns the attacker's  |
| UI-1 | True | high | On phones the whole Computer (all 9 apps), the Intro and every toast render at 5-9 pt, with 12-30 pt tap targets | StarterPlayer/StarterPlayerScripts/Client/UI/UIRoot.module.luau:11-28 (also Computer.module.luau:208,267-342,351; Toast.module.luau:95; Intro.module.luau:42-230) | Confirmed. UIRoot.module.luau:11-28 scales the 1280x720 canvas uniformly to min(750/1280, 311/720) = 0.432 on an 844x390 phone with the 58/47/21/47 insets. Computer.module.luau has no touch boost. Its open tween at :106-107 targets Scale = 1, and Kit.isTouch is only used by HUD (COMPACT_BOOST), EmpireApp and Lab/Studio. probe_phone_pt.luau multiplies TextSize by every ancestor UIScale, which is co |
| UI-2 | True | medium | CCTV restores a stale Scriptable camera when it was opened during a shuttle ride or flight cutscene, leaving the camera stuck | StarterPlayer/StarterPlayerScripts/Client/Controllers/SecurityController.module.luau:102 (captures old camera), 43-44 (restores it) | Confirmed by reading the code. show() at SecurityController:102 saves old.kind while a ride or cutscene owns the camera (Scriptable). Its RenderStepped (:137-140) forces Scriptable every frame while `target` is set. So after ShuttleController.closeRide (:545-556) or the cutscene end (TravelController:125) sets Custom once, the CCTV switches it back to Scriptable on the next frame. Back -> close()  |
| UI-3 | True | low | Interview, assistant briefing and lift panels fit Camera.ViewportSize but sit in an inset ScreenGui, so the header goes under the top bar and the footer or Close leaves the screen on small phones | StarterPlayer/StarterPlayerScripts/Client/UI/Screens/Conversation.module.luau:46-50 (+ PeopleController.module.luau:59-62, CampusController.module.luau:49) | The geometry error is real. Conversation:46-50, PeopleController:59-62 and CampusController:49 size the panel from Camera.ViewportSize, which api-docs.json calls 'the dimensions of the device safe area', so it includes the 58 pt top-bar band. The panel is centred in a ScreenGui with the default insets, while TalkPanel:41-50 correctly uses screen.AbsoluteSize. The impact is overstated. On an iPhone |
| UI-4 | True | low | GPS destination list while driving runs off the bottom of every phone screen; City Airport can never be tapped | StarterPlayer/StarterPlayerScripts/Client/Controllers/TravelController.module.luau:282, 287 | The overflow is real. TravelController:282/287 places a raw-pixel box at (0,16,.5,-120) and expands it to a fixed 330 px. The 280 px list window ends at 417.5 pt on an iPhone 14 (390 screen) and 420.5 on an iPhone SE (375). The scroll canvas holds 19 entries, so the last entries (City Airport) can never be scrolled into view. 'City Airport can never be tapped' only holds inside the GPS, though. Th |
| UI-5 | True | medium | 'Open live campus cameras' in the Campus app opens the CCTV behind the still-open Computer window, dim layer and blur | StarterPlayer/StarterPlayerScripts/Client/UI/Apps/CampusApp.module.luau:81 | Confirmed. CampusApp:81 calls Security.open without closing the Computer. Nothing closes the Computer when CampusSecurity appears (only PhoneController.PANELS closes the phone). The CCTV ScreenGui (DisplayOrder 55) has transparent regions, so the 'live view' is whatever lies below: the Computer window at Overlay DisplayOrder 20 (BackgroundTransparency 0.03, (1,-40,1,-28)), the dim layer and AIEmpi |
| TEST-1 | False | low | run_all does not verify the shipped build: the Model Studio suite is missing, suites have drifted to later packages, and failed checks still show rc=0 | tests/lead/run_all.sh:12 (run()) and the suite list 19-102 (no tests/lab) | Refuted on its core claim. The release has a green baseline and a frozen test tree: agents/stable/snap_lab_1150_runall.txt (10-11 12:26, no failures) and, pushed with the release, ai-empire-roblox/projekt/run_all_2026-10-11_ki-studio.txt plus projekt/tests/ (run_all.sh is identical, and tests/lab is included). The failures in runall.txt come from the scratchpad tests tree, which later packages edi |
| TEST-2 | False | low | CreateCompany, the first action of every new player, is covered by no run_all suite (server or Intro) | ServerScriptService/Server/Services/CompanyService.module.luau:20-61 (client: StarterPlayer/StarterPlayerScripts/Client/UI/Screens/Intro.module.luau:320-356) | This is a coverage gap, not a defect. The gap itself is true: no released suite calls CreateCompany or mounts the Intro. But reading CompanyService.module.luau:20-61, every branch is correct: the ALREADY_FOUNDED pre-check, Guard.text -> BAD_NAME, logo/colour/spec validation -> BAD_INPUT, a nil filter result -> FILTER_DOWN, a mismatch -> NAME_FILTERED, the post-yield recheck of session.closed/compa |
| UI-6 | False | low | 19 controller inits run in sequence without isolation and StateController.init() comes last, so one throwing init leaves every player on 'Connecting...' | StarterPlayer/StarterPlayerScripts/Client/Main.client.luau:80-101 | Hypothetical. The finding itself says no init throws today, and its own probe boots every one of the 19 inits successfully in an empty streaming workspace. The failure only appears with an injected exception. Future stub replacements are not a defect in the released snapshot. It is a robustness suggestion (pcall the inits, init StateController first), not a concrete failure path. |
| UI-7 | False | low | Gamepad: the Intro (first screen) and the Computer set no SelectedObject and bind no ButtonB | StarterPlayer/StarterPlayerScripts/Client/UI/Screens/Computer.module.luau:95-136 (also Intro.module.luau:299-332) | The code observation is correct (Computer.open/close and Intro.showNew set no GuiService.SelectedObject and bind no ButtonB), but reachability and harm don't hold. No project document (CORE_SPEC, notes, game_description, README) declares console as a target. The brief's 'gamepad friendly' line is about the phone hub, which does handle gamepad. PC players with a gamepad still have a mouse. Even on  |
| UI-8 | True | low | Boarding-pass panel draws over the HUD column on phones, covering 'Open company' and the goal card while a pass is held | StarterPlayer/StarterPlayerScripts/Client/Controllers/ShuttleController.module.luau:440-441 | Confirmed. ShuttlePass (DisplayOrder 25, above the HUD at 10) is anchored at (1,-16,0.5,40) with a raw 270x96 size. On an 844x390 screen with insets that is x 511..781, y 205.5..301.5. The guiprev render hud_broke_phone.png (2x) puts 'Open company' at x 596..790, y 258..303 and the goal card at y 176..252, so the pass covers the main HUD button and the bottom of the goal card from check-in until b |
