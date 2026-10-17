# AI Empire: verified audit findings (robloxdev_review, 2026-10-17)

Input: the 11 raw findings in `agents/robloxdev_review/FINDINGS_RAW.md` (R1-R11, from the ~08:25 UTC tree). Seven verifier
groups tried to refute each one with code reading, guard search, the headless mock and `tools/API-Dump.json`. Their
working dirs are `agents/robloxdev_review/r*/`. Nothing under `work/`, `tests/` or `agents/stable/` was edited. All probes
ran on private copies of `work/src`.

All relative paths in this file are relative to `/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad/`.

Current-tree recheck, two passes:
- **09:41:25 UTC**: `work/src` copied to `agents/robloxdev_review/final_check/src` (mock manifest `final_check/gen`). Every
  file a confirmed finding touches was byte-identical to the copy its verifier used, except
  `ItineraryService.module.luau` (round 2b edited it at 09:30, see R3). All six confirmed probes were re-run there and
  still reproduce.
- **10:14:02 UTC** (final): `work/src` copied to `agents/robloxdev_review/final_check2/src`. `diff -rq` against the 09:41
  copy: only `ItineraryService.module.luau` changed again (09:46:30; respawn-while-carried notice ~1261-1267, and the
  `offered`/`carries` helpers ~1605-1619). `go`, `cancel`, `buildFolder` and `scan` are unchanged, only shifted below
  line 1260. Re-run on this copy: the R3 probe and fix variants, all 24 `tests/itinerary` suites, and the full 8-scenario
  R2 matrix. All other confirmed findings' files are byte-identical to 09:41, so their 09:41 re-runs stand. Every fix
  patch named below applies cleanly to the 10:14 tree (`patch --dry-run`).
- At 10:19 round 2b had changed two more files. `ItineraryMath` changed one text line (~395, "waits at our jet") and
  `ShuttleService` had a comment moved (~209-236). Neither touches a finding: `IM.JET_WAIT = 90` and `JP.CONFIG.maxDelay = 240`
  are unchanged, so the R4 refutation still holds.
- Line numbers below are from the 10:14 tree.

## Result

| severity | confirmed | ids |
|---|---|---|
| critical | 0 | |
| high | 0 | |
| medium | 2 | R2, R3 |
| low | 4 | R7, R6, R10, R8 |
| refuted | 5 | R1 (raw HIGH), R4 (raw MEDIUM), R5, R9, R11 (raw LOW) |

Ownership rules used below. Files matching AssistantService, PhoneService, Phone UI, ShuttleService, CityService,
Driver\*, Drive\*, Jet\*, Guest\*, AircraftModel, AirportBuilder, EmployeeRigDesign, VehicleService and Itinerary\* are
**frozen for round 2b** until it is released. ShopService, ShopApp, ShopCore, UseSheet, ShopMath and ShopConfig belong
to the **shop package**. Save\*, Session\*, Funnel, EmpireService and Guide\* go to the **separate fix package**.
Project rules for every fix: DATA_VERSION stays 6, save changes only as additions with cleaners, economy truth stays in
CompanyOps/EmpireMath. None of the fixes below changes the save format or economy code.

---

## Confirmed findings (critical → low)

### R2 · MEDIUM · a late in-flight save commits after the release save (rollback plus 3-minute lockout)
- **Owner:** the separate fix package (SaveService, SessionService, ServerTypes). The one ShopService hunk of the full
  fix goes to the shop package. The minimal hotfix fixS touches SaveService only.
- **Where (10:14, unchanged since the verifier's 08:42 copy):**
  - `work/src/ServerScriptService/Server/Services/SessionService.module.luau` `closeSession` 336-361: the 15 s cap is at 353, the forced `saving = true` plus release save at 357-358, and the lost-lock kick in `saveSession` at 271-276.
  - `work/src/ServerScriptService/Server/Services/SaveService.module.luau` `save` 139-179: the payload is copied with `sanitize` at 146, `waitForBudget` (50-57) runs per attempt, **a nil lock is accepted at 155**, the re-lock is at 162 and the `2 ^ attempt` backoff is at 176. `load` is at 77-135 (180 s lock, 6 tries 4 s apart).
  - `work/src/ServerScriptService/Server/Services/ShopService.module.luau` `Shop.saveNow` 397-419 (gives up at 403 and can be the stale writer at 407).
- **Failure path:**
  1. A save is in flight when the player leaves: the autosave, or a `Shop.saveNow`. It is slow because DataStore errors or throttling run it through budget waits of up to 10 s per attempt and backoffs of 2, 4 and 8 s.
  2. `closeSession` waits 15 s, then starts the release save anyway. The release save commits with `lockJobId = nil`.
  3. The older save's next attempt passes the check at line 155, because a nil lock counts as "ours". It writes its older snapshot and re-locks the key to this server.
  4. Server B sees a foreign lock younger than 180 s. It retries 6 × 4 s and kicks with "save could not be loaded". About 3 minutes later the player loads the rolled-back data.
  5. What is lost: the progress between the start of the stale save and the leave, typically tens of seconds. No Robux are lost, because the grant and its receipt id roll back together and the receipt is retried.
  6. A player cannot trigger it; it needs DataStore trouble. It also happens on BindToClose.
- **Probe:** `agents/robloxdev_review/r2_save/probe_r2.luau`, with the matrix in `r2_save/run_matrix.sh [gen fixR/gen …]` and the variants in `r2_save/make_fixes.py`. It runs the real SaveService and SessionService against a fake DataStore with optimistic UpdateAsync. A second SaveService instance plays server B.
  - Verifier, current code: queued, inflight, retry, shutdown2, stale_rejoin and fork_rejoin FAIL; control and shutdown_long PASS. Example (queued): release COMMIT money=777 lock=nil at 15.8 s, then stale COMMIT money=100 lock=SERVER-A at 20.6 s; B is kicked after 26.0 s and later loads 100.
  - fixR passes all 8 scenarios. fixS and fixA fail only the two same-server rejoin scenarios.
  - Suites stay green on all variants: shop 146/146, shop2_server 141/141, econ_service 92/92, econ_migration 95/95. luau-lsp strict reports 0 diagnostics and luau-compile succeeds.
  - Re-run on the 09:41 tree: control PASS; queued, retry and stale_rejoin FAIL (`final_check/r2_now.txt`).
  - **Re-run on the 10:14 tree, full matrix (`final_check2/r2/*.log`):** current code: control and shutdown_long PASS; queued, inflight, retry, shutdown2, stale_rejoin and fork_rejoin FAIL. That is the same as the verifier. fixR: all 8 PASS.
  - Run on a new copy: `cd agents/robloxdev_review/r2_save && ../../../tools/luau probe_r2.luau -a <scenario> <gen dir relative to r2_save>`. A failing scenario prints `RESULT <scenario> FAIL`.
- **Minimal fix (recommended: fixR, `r2_save/fixR.diff`):**
  - `SaveService.load` creates a per-session token, `SESSION_ID .. "/" .. HttpService:GenerateGUID(false)`, uses it as the lock owner and returns it as a 3rd value.
  - `SaveService.save(userId, data, release, token)` and `releaseLock(userId, token)` take the token. A nil token makes `save` return `(false, true)` and `releaseLock` return without writing.
  - The transform check becomes strict: `if meta.lockJobId ~= token then lostLock = true; return nil end`. This also refuses a released (nil) lock.
  - SessionService stores `session.lockToken` and passes it on.
  - ShopService: `deps.save` gets a 4th parameter, and `saveNow` passes `session.lockToken`.
  - ServerTypes.Session gets `lockToken: string?`.
  - `saveSession` and `saveNow` skip the "opened on another server" kick when `session.released`.
  - Keep the 15 s cap. **Do not** adopt the raw finding's uncapped wait or per-session queue: in shutdown_long the release then commits 40.7 s after BindToClose, past the ~30 s shutdown.
  - `meta.lockJobId` stays a string, so DATA_VERSION stays 6 and no cleaner is needed. Mixed old and new servers stay safe.
  - **Hotfix if only R2 is wanted (fixS, `r2_save/fixS.diff`):** change SaveService line 155 to `if meta.lockJobId ~= jobId then`.
- **Files touched:** fixR touches SaveService, SessionService, ShopService and `ServerScriptService/Server/Lib/ServerTypes.module.luau`. fixS touches SaveService only.
- **Duplicate:** this is pro review `security.md` F1 = `datastores.md` #3 (their fix_plan `DS-3/F1`). fixR is their DS-2 + DS-3 together, so it also closes `datastores.md` #2, the same-server rejoin fork.

### R3 · MEDIUM (verifier, 08:49 tree; see the current-tree note) · TripAction go/cancel loop rebuilds the replicated itinerary folder
- **Owner:** round 2b. Itinerary\* is frozen, and round 2b is changing this exact code right now.
- **Where (10:14):** `work/src/ServerScriptService/Server/Services/ItineraryService.module.luau`:
  - `go` 1118 (no `rec.declined[k]` check after the `rec.it` checks at 1125-1128; the GO_GAP check is at 1139).
  - `cancel` 1488 (`finish` without marking the key; it was 1483 at 09:41).
  - `buildFolder` 211.
  - `buildClients` 233 (new: the client team is built only from the meeting on).
  - `ItineraryService.GO_GAP = 2` at 71 (new).
  - `scan` clears `declined` at 1211.
  - Remote: `DriverService.module.luau` `Remote.bind("TripAction", {30,10})` plus per-action buckets `LIMITS.other = {8,3}`.
- **Failure path:**
  1. An exploit client alternates `TripAction {action="go", key}` and `{action="cancel"}`. The key comes in every ITINERARY Notify as `view.key`, or can be guessed.
  2. `go` accepts any running founder trip key, including declined keys and keys of expired offers.
  3. `cancel` ends only the itinerary, so the same key restarts it.
  4. Every accepted go builds `ReplicatedStorage.CompanyItinerary/Itin_<uid>`, and every cancel destroys it. Both replicate to every client.
  5. No economy, save or other-player Notify effect.
- **Probe:** `agents/robloxdev_review/r3_itin_flood/probe_flood.luau`. Run it from that dir with `../../../tools/luau probe_flood.luau -a <gen>`. It drives the real Lib/Remote and the real DriverService LIMITS, and calls through `Remotes.TripAction.OnServerInvoke`.
  - Verifier, 08:49 tree: 12 passed / 6 failed. 189 instances per go, 3 cycles/s sustained, **561 instances/s** added and the same number destroyed under ReplicatedStorage (5610 in 10 s).
  - **Re-run on the 09:41 tree (`final_check/r3_probe_now.txt`): 14 passed / 4 failed.** Round 2b's GO_GAP (2 s per founder) and the lazy client-team rigs landed in between:
    - 97 instances per go (2 rigs).
    - Paced flood 5 builds per 10 s = **47.5 instances/s** added and the same destroyed (region case 46.8/s), about 12× less.
    - **Still open:** `go with a declined key` → started (FAIL), and the same key restarts after every cancel once GO_GAP has passed.
  - **Re-run on the 10:14 tree (`final_check2/r3_probe_gen.txt`): 14 passed / 4 failed, the same numbers as 09:41** (47.5 instances/s paced, 46.8/s region, declined key still starts a trip). fixA: 15/3 (`r3_probe_gen_fixA.txt`). Full fix: 18/0 (`r3_probe_gen_fix.txt`).
  - Note for the regression test: on the 09:41 tree the probe's "go after cancel with the same key is refused" check passes only because of `RATE_LIMIT` (GO_GAP). The re-use check must wait more than GO_GAP.
- **Minimal fix:**
  - **(1) In `go()`, after the `rec.it` checks:** `if rec.declined[k] then return { ok = false, err = "DECLINED", text = "The team is handling that visit without you." } end`.
    - Patch: `agents/robloxdev_review/final_check/r3_fixA_declined_only.patch`.
    - Verified on the 09:41 copy and again on the 10:14 copy (applies with no offset): all 24 live `tests/itinerary` suites 0 failed (`final_check2/itin_fixA/`), and the declined-key bypass is closed. The probe's 3 "≤1 build per trip key" checks still fail by round 2b's design (one re-join per GO_GAP).
  - **(2) Optional, the verifier's second hunk:** in `cancel()`, set `rec.declined[it.key] = true` before `finish`.
    - Patch: `r3_itin_flood/fix_ItineraryService.patch`. It applies to the 10:14 tree with `patch -p1` (offsets +193/+241).
    - Effect: the loop is fully closed (probe 18/0, 0 replicated instances in every flood).
    - Conflict: it **contradicts round 2b's intended re-join after cancel**. It breaks 2 checks in `tests/itinerary/test_service.luau` scenario `remote`: "go right after a cancel: one moment please" and "go after GO_GAP s: ok". On the 10:14 copy that is remote 30/2; the other 23 suites stay at 0 failed (`final_check2/itin_fix/`).
    - Round 2b decides. If they adopt it, they update those 2 checks.
  - No save, economy or DATA_VERSION change. luau-compile succeeds on both variants.
- **Files touched:** `work/src/ServerScriptService/Server/Services/ItineraryService.module.luau`, plus `tests/itinerary/test_service.luau` (scenario `remote`, regression) if hunk (2) is taken.
- **Current-tree note:** by the verifier's own downgrade rule ("bystander < ~10 KB/s → LOW"), the 09:41 and 10:14 rate of about 2.5-4 KB/s per exploiter (the verifier's per-instance estimate) would be LOW. The severity stays MEDIUM here as the verifier set it, until round 2b's mitigation is released and measured in Studio.
- **Duplicate:** none. Pro review `security.md` F6 ("TripAction created but never bound") is obsolete: TripAction is now bound in DriverService.

### R7 · LOW · decor PrivateJet/PM2 hide is lost after the model streams out and back in
- **Owner:** round 2b (Jet\* frozen).
- **Where (10:14; the file is byte-identical to 09:41):** `work/src/StarterPlayer/StarterPlayerScripts/Client/Controllers/JetController.module.luau`:
  - `hiddenDecor` 62, `privateConn` 64, `pm2Conn` 66.
  - `hidePart` 397 (skips parts already in `hiddenDecor`).
  - `restore` 403, `findDecor` 414, `setHidden` 436.
  - `updateDecor` 448 (450/454 skip while the old connection is set), called from `step` at 751.
- **Failure path:**
  1. The place streams (StreamingEnabled, TargetRadius 512, Opportunistic). Hangar 1 is about 2600 studs from the plots, so a jet owner's normal loop streams the decor jet out and back in.
  2. If the same instance comes back, `hidePart` skips its parts. If a new instance comes back, `updateDecor` never calls `setHidden`.
  3. Result: the 0.9-scale decor jet is drawn over the owner's company jet, or collides there while invisible. About 330 dead parts stay in `hiddenDecor`.
  4. The effect is client-local only.
- **Probe:** `agents/robloxdev_review/r7_r8_r11_client/probe_r7_decor_stream.luau` (all client probes: `r7_r8_r11_client/run_probes.sh [src]`).
  - Verifier: unfixed 2 passed / 3 failed (A 287/330 hidden + 43 invisible but colliding; A2 0/330; B 0/330). Fixed 5/5. guests_jet test_jet 210/0 on both trees.
  - Re-run on the 09:41 tree: identical, 2 passed / 3 failed (`final_check/r7_now.txt`).
- **Minimal fix (JetController hunks @@-61, @@-395 and @@-433 of `r7_r8_r11_client/fix_r7_r8_r11.patch`; the @@-795 hunk is the optional R11 hardening):**
  - (1) `hidePart` always re-applies LocalTransparencyModifier=1, CanCollide=false and CanQuery=false, and records the original CanCollide only the first time it sees a part.
  - (2) Replace `setHidden` with `applyDecor(d, m, hide)`, which keeps one record per decor model (model, live, hide, conn). When the instance or its liveness changes, it disconnects, prunes dead or replaced parts from `hiddenDecor`, and then hides and reconnects DescendantAdded, or restores.
- **Files touched:** `work/src/StarterPlayer/StarterPlayerScripts/Client/Controllers/JetController.module.luau`.
- **Duplicate:** none.

### R6 · LOW · Funnel.custom has no memo: restart/skip spam logs unlimited "TutorialSkipped" events
- **Owner:** the separate fix package (Funnel).
- **Where (10:14; the file is byte-identical to 09:41):**
  - `work/src/ServerScriptService/Server/Lib/Funnel.module.luau` `Funnel.custom` 63-71 (LogCustomEvent at 69, no memo) and `_reset` 74.
  - `work/src/ServerScriptService/Server/Services/EmpireService.module.luau` `tutorialAction` 428: `skip` at 432 calls `Funnel.custom` at 436, and `restart` at 446 re-arms the skip.
  - Bound at 624 with `Remote.bind("EmpireAction", …)` {burst 4, 2/s}.
- **Failure path:**
  1. Before the first release, any client alternates the `restart` and `skip` tutorial ops at 2/s. A normal player can also do it by hand: the Skip button, then Goals → Restart.
  2. Each skip after a restart logs `TutorialSkipped` again, about 3,600 per hour per client.
  3. Effect: analytics only. Funnel steps are memoized, and money, unlocks and saves are not affected.
- **Probe:** `agents/robloxdev_review/r6_r10_tutorial/probe_r6_skip_spam.luau`. Run it from that dir with `../../../tools/luau probe_r6_skip_spam.luau -a gen|gen_fixed`.
  - Verifier: 120 accepted calls, 0 RATE_LIMIT and 61 TutorialSkipped in 60 s (6 passed / 1 failed). Fixed: 1 event (7/0). menu_server 111/0, menu_client_guide 83/0, menu_client_menu 45/0.
  - Re-run on the 09:41 tree: the same 61 events, 6 passed / 1 failed (`final_check/r6_now.txt`).
- **Minimal fix (`r6_r10_tutorial/fix_r6_funnel.diff`):** add a weak-keyed memo, `local sentCustom: { [Player]: { [string]: boolean } } = setmetatable({}, { __mode = "k" }) :: any`. In `Funnel.custom`, return when `memo[name]` is already set; otherwise set it and log as now. Add `table.clear(sentCustom :: any)` to `_reset`. If product wants each skip step counted, memo on `name .. "|" .. value` (at most 6 per session). EmpireService stays unchanged.
- **Files touched:** `work/src/ServerScriptService/Server/Lib/Funnel.module.luau`.
- **Duplicate:** none.

### R10 · LOW · the tutorial guide beam is not rebuilt after a respawn in step 1
- **Owner:** the separate fix package (Guide\*).
- **Where (10:14; the file is byte-identical to 09:41):** `work/src/StarterPlayer/StarterPlayerScripts/Client/Controllers/GuideController.module.luau` `updateBeam` 293. The HRP guard is at 297-299, the `if far and not pointer.beam` build at 301-318, and the near branch at 319-328. POINTER_NEAR is at 40.
- **Failure path:**
  1. The beam and `GuideFrom` attachment are parented to the HumanoidRootPart. After a Reset or a fall into the void, `pointer.beam` is still non-nil, so no beam is built on the new HRP.
  2. The beam comes back only after walking within 10 studs of the terminal and away again, or after a step or menu change.
  3. Effect: cosmetic. The HUD action, ring, chip, Highlight and billboard still guide the player.
- **Probe:** `agents/robloxdev_review/r6_r10_tutorial/probe_r10_respawn_beam.luau` (`-a gen|gen_fixed`). It covers both the Destroy and the parent-to-nil respawn.
  - Verifier: 6 passed / 4 failed unfixed, 10/0 fixed. The menu suites are unchanged.
  - Re-run on the 09:41 tree: 6 passed / 4 failed ("GuideBeam on new HRP: false" in both modes) (`final_check/r10_now.txt`).
- **Minimal fix (`r6_r10_tutorial/fix_r10_guide.diff`):** right after the HRP guard, insert `local oldBeam, oldA0 = pointer.beam, pointer.a0; if oldBeam and (not oldA0 or oldA0.Parent ~= hrp or oldBeam.Parent ~= hrp) then oldBeam:Destroy(); if oldA0 then oldA0:Destroy() end; pointer.beam = nil; pointer.a0 = nil end`. The existing far branch then rebuilds the beam within one 0.2 s update.
- **Files touched:** `work/src/StarterPlayer/StarterPlayerScripts/Client/Controllers/GuideController.module.luau`.
- **Duplicate:** none.

### R8 · LOW · GuestController plotCache is never pruned (client memory leak, bounded by distinct owners seen)
- **Owner:** round 2b (Guest\* frozen).
- **Where (10:14; the file is byte-identical to 09:41):** `work/src/StarterPlayer/StarterPlayerScripts/Client/Controllers/GuestController.module.luau`. `Guests.STALE` is at 37 and `plotCache` at 52. `findPlots` runs from 236 to 287; it only ever adds entries (259-262).
- **Failure path:** every hotel owner who came within 240 studs of the camera keeps an entry for the rest of the session. An entry holds the office Instance and the day's actor list, about 100 KB of heap. Typical growth is about 1-5 MB over hours. There is no correctness effect.
- **Probe:** `agents/robloxdev_review/r7_r8_r11_client/probe_r8_plotcache.luau` (with `probe_r8_size.luau` for the per-entry size).
  - Verifier: unfixed +101.5 KB per departed owner and 204 destroyed offices referenced (1 passed / 2 failed). Fixed −0.4 KB, 0 referenced (3/3). test_guests 205/0 on both trees.
  - Re-run on the 09:41 tree: identical, 1 passed / 2 failed (`final_check/r8_now.txt`).
- **Minimal fix (GuestController hunks of `r7_r8_r11_client/fix_r7_r8_r11.patch`):** add `Guests.FORGET = 120`. At the end of `findPlots`, add `for seed, rec in plotCache do if now - rec.seen > Guests.FORGET then plotCache[seed] = nil end end`.
- **Files touched:** `work/src/StarterPlayer/StarterPlayerScripts/Client/Controllers/GuestController.module.luau`.
- **Duplicate:** none.

---

## Refuted
- **R1** (raw HIGH, game-pass event trusted): it is not shown that a non-owner can forge the server-side PromptGamePassPurchaseFinished.
  - Owner replay is harmless (1 flag, no save churn).
  - The path is unreachable today: every pass id is 0, so `passById(0)` returns nil.
  - Real gap: an unconfirmed event is cached in `data.shop.passes`. That is low, optional hardening for the shop package: `onPassPurchaseFinished` (ShopService:313, `setPass(session, def.key, true, true)` at 328) should pass `persist=false`, and `tests/shop/test_shop.luau` L326 needs an update. Patch: `r1_pass/fix_ShopService.patch`, probe `r1_pass/probe_r1.luau` (14/0 with the fix).
  - Do **not** poll UserOwnsGamePassAsync before granting.
  - Duplicate of pro review `security.md` F7. The pro review's own verifiers also rejected F7 (`REPORT.md`, "Rejected by the verifiers": unreachable, pass ids 0).
- **R4** (raw MEDIUM, jet flies a car-held founder): unreachable. `jetwait` needs a RUNWAY_BUSY `eta <= IM.JET_WAIT` (90), but `JetService.fly` only answers RUNWAY_BUSY with eta > `JP.CONFIG.maxDelay` (240) or nil. This was rechecked on the 09:41 tree (ItineraryMath:41, JetPlan:44, ItineraryService:773). The prompt route fails the 20-stud server check (265 studs closest in the probe).
  - Optional guard (round 2b, frozen): `JetService.fly` after the SeatPart check at 501 adds `if r.Anchored then return {ok=false,err="LEAVE_VEHICLE"} end`. Patch: `r4_jet_driver/fix_r4_optional.diff`, probe `r4_jet_driver/probe_r4.luau`.
- **R5** (raw LOW, stepRide error drops the held founder under the road): nothing in the riding branch can throw before `release`. All DrivePlan calls return nil instead of throwing, and the rest is pcall'd or runs after `r.hold = nil`. Worst case is a fall, a death and about 7 s to respawn at home; nothing stays stuck.
  - Optional `safeSpot` hardening (DriverService, round 2b frozen): `r5_ride_release/fix.diff`, probe `r5_ride_release/probe_r5.luau`.
- **R9** (raw LOW, DriveController per-frame allocations): measured, not harmful. The patterns cost about 5 µs and 1.9 KB per frame (worst case kerb scene ~95 µs, 8.4 KB). That is 2-11 % of `DriveController.step` and about 0.1-1 % of a 16.7 ms frame. Rig posing dominates instead. No fix; the analysis is in `r9_drive_perf/NOTES.md`.
- **R11** (raw LOW, 30 s WaitForChild timeout for CompanyDrivers/CompanyJets): not reachable in normal play.
  - `Main.server.luau` builds both synchronously, in 0.38-0.93 s in the mock, before any client can reach `game.Loaded`. Only an outage-time hang of more than 30 s in SaveService's probe GetAsync could cause it.
  - Optional ChildAdded-loop hardening (Jet\*/Drive\*, round 2b frozen): the DriveController and JetController @@-795 hunks of `r7_r8_r11_client/fix_r7_r8_r11.patch`, probe `r7_r8_r11_client/probe_r11_startup.luau`.
  - This matches pro review `ui_types.md` "Checked and OK" for the 30 s client waits.

## Cross-check with the pro review of the older snapshot (`agents/robloxreview/*.md`, snap_lab_1150)
| here | pro review | relation |
|---|---|---|
| R2 | security.md F1; datastores.md #3 (fix_plan `DS-3/F1`) | **duplicate**. The recommended fixR = DS-2 + DS-3 |
| (R2 fix) | datastores.md #2 (fix_plan `DS-2`, same-server rejoin fork) | closely related, closed by the same fixR (stale_rejoin/fork_rejoin PASS) |
| R1 (refuted) | security.md F7 (finder: low, latent, "unsure"); REPORT.md lists F7 under "Rejected by the verifiers" (unreachable, pass ids 0) | **duplicate**, and both reviews reject it. The pro fix (confirm via UserOwnsGamePassAsync before persisting) is close to the verifier's persist=false hardening, but the verifier rejects its "poll before granting" part |
| R3 | security.md F6 (TripAction unbound; REPORT.md also rejected it) | not a duplicate. F6 is obsolete on the current tree |
| R11 (refuted) | ui_types.md "Checked and OK" (30 s client waits in task.spawn) | consistent |
| R4, R5, R6, R7, R8, R9, R10 | none | new in this audit (the drivers/jet/guests/itinerary/menu code postdates snap_lab_1150) |

Still open from the pro review and not part of R1-R11: **datastores.md #1 / fix_plan `DS-1` (high)**. BindToClose returns before the PlayerRemoving final save commits. The R2 probe shows it on the current tree: the callback returns at 0.40 s and the commit lands at 2.40 s. It lives in the same SessionService code as R2, so the separate fix package should apply DS-1 together with fixR. Also optional: datastores.md #7 (no `task.wait` after the last failed attempt, SaveService:176).

## Only Studio/live can confirm
- **R2:**
  - Live UpdateAsync timing: how long a call can yield or queue before it errors, how the per-key write cooldown queues requests, and whether same-key requests from one server stay in order. If they are strictly ordered, only the error/backoff path remains, and that path does not depend on ordering.
  - How often GetRequestBudgetForRequestType returns 0 under load.
  - That yielding threads die once the BindToClose callbacks return, and the real shutdown grace period (~30 s).
  - That `Player:Kick` on a player who already left is a no-op.
- **R3:**
  - The replicated bytes per go/cancel cycle and their effect on bystanders. Run a 2-client Studio test with a server command-bar loop firing TripAction go/cancel. Watch `Stats.DataSendKbps` on the server, `DataReceiveKbps` on the bystander and the MicroProfiler (Rig.build, replication).
  - If the bystander gets under ~10 KB/s, downgrade to LOW. On the 09:41 and 10:14 trees (47.5 instances/s) that is expected.
  - Real server CPU for Rig.build.
- **R7:**
  - Which variant the engine actually does when a Luau-referenced decor part streams back in: the same instance with properties re-replicated (A), the same instance with local changes lost (A2), or a new instance (B).
  - The order of DescendantAdded relative to property re-application.
  - Whether the decor jet visibly overlaps or collides in the hangar after an office-and-back trip. The fix covers all three variants.
- **R6:**
  - The AnalyticsService per-server throttle for custom events, and whether spam can starve other players' funnel events.
  - How the Creator Dashboard aggregates them. Studio sends no analytics, and the mock has no AnalyticsService.
- **R10:**
  - That the rebuilt untextured 0.4-width Beam is visible (already flagged [A] in the code).
  - The real respawn timing.
  - The place's Workspace.PlayerCharacterDestroyBehavior. The fix handles both Destroy and parent-to-nil.
- **R8:** the real client heap per entry (the mock models Vector3/CFrame as tables), and that a server-destroyed office the client still references holds no descendants.
- **Refuted items (for completeness):**
  - R1: whether a non-owner can forge PromptGamePassPurchaseFinished. This cannot be tested in Studio, and trying it live is against the ToS. Also how long UserOwnsGamePassAsync lags after a purchase, and what it returns in Studio after a test purchase.
  - R4: that an anchored, server-held root stays server-authoritative.
  - R5: the fall below the road, the respawn after ~5 s, and freeSpot on real geometry.
  - R9: device cost of the engine bridge calls on iOS (ScriptProfiler/MicroProfiler with about 6 cars near the camera).
  - R11: the engine time of CityService.init, and whether game.Loaded can fire during SaveService's probe GetAsync yield.

## Paths
- Verdict files: `agents/robloxdev_review/VERIFIED.md` (this file), `agents/robloxdev_review/fix_plan.json`, `agents/robloxdev_review/ZUSAMMENFASSUNG.md`.
- Verifier dirs (probes, patches, NOTES.md): `agents/robloxdev_review/r1_pass`, `r2_save`, `r3_itin_flood`, `r4_jet_driver`, `r5_ride_release`, `r6_r10_tutorial`, `r7_r8_r11_client`, `r9_drive_perf`.
- Current-tree recheck: `agents/robloxdev_review/final_check/`.
  - Snapshot: `src` and `gen`, with `SNAPSHOT_TIME`.
  - Probe output: `r2_now.txt`, `r3_probe_now.txt`, `r3_probe_now_fix.txt`, `r3_probe_now_fixA.txt`, `r6_now.txt`, `r7_now.txt`, `r8_now.txt`, `r10_now.txt`.
  - R3 fix: `r3_fixA_declined_only.patch`. Itinerary suite runs: `run_itin_suites.sh`, `itin_base/`, `itin_fix/`, `itin_fixA/`.
- Final recheck (10:14): `agents/robloxdev_review/final_check2/`.
  - Snapshot: `src` and `gen`, with `SNAPSHOT_TIME`. R3 variants: `src_fixA`/`gen_fixA` (declined-only) and `src_fix`/`gen_fix` (both hunks).
  - Probe output: `r3_probe_gen.txt`, `r3_probe_gen_fixA.txt`, `r3_probe_gen_fix.txt`; the R2 matrix is in `r2/<scenario>__final_check2.log` (current code) and `r2/<scenario>__fixR.log`.
  - Itinerary suite runs: `run_itin_suites.sh <gen> <outdir>`, `itin_base/`, `itin_fixA/`, `itin_fix/` (summaries in `itin_*.txt`).
- All paths are relative to `/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad/`.
