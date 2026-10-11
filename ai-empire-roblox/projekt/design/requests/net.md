# Requests from package "net" (network & live-state foundation)

## 1. tests/lead/run_all.sh — add the net suites (lead)
Add after the `snapshot` line:
```
python3 harness/make_manifest.py --src work/src --gen harness/.gen_net >/dev/null
run net_patch         $L tests/net/test_patch.luau
run net               $L tests/net/test_net.luau
run net_e2e           $L tests/net/test_e2e.luau
```
Why: the protocol tests (StatePatch round trips incl. 2,400 randomized steps, SessionService/StateController,
MarketService live merge, 12-player end-to-end bandwidth <= 15 KB/s) should guard every later change.
Runtime: ~5 s together. Expected today: 32/0, 90/0, 9/0.
STATUS: already done (integrate: run_all runs net_patch / net / net_e2e)

## 2. Optional: urgent flag for prompt-driven actions (owners of these files)
`SessionService.markDirty(session, true)` now exists (2nd arg optional, old calls unchanged). Remote calls
are already sent after 0.1 s; actions triggered by a ProximityPrompt (not through Remote.bind) use the steady
0.5 s cadence. For snappier feedback, pass `true` in the prompt handlers only (never in tick loops):
- FacilityService prompt handler (snack/door/security actions, the `Session.get(player)` call sites at ~:166/:369/:485)
- RecruitingService.onPrompt (~:774), AssistantService prompt (~:451), VehicleService prompt (~:151), TalkService say/open.
STATUS: done by integrate (Session.markDirty(s, true) after every FacilityService prompt action and in RecruitingService.onPrompt; AssistantService / VehicleService prompts change no save data, TalkService writes none)

## 3. DebugService "reset" (DebugService.module.luau ~:51) — owner of DebugService
`session.live = { users = 0, ... }` replaces the live table and drops `live.admin` (set once by AdminService)
and the other services' fields until they rewrite them. Suggest:
`for k in session.live do session.live[k] = nil end; session.live.users = 0; session.live.revenue = 0; session.live.cost = 0; session.live.perModel = {}; session.live.npcUsers = {}`
and re-set `session.live.admin` via AdminService, or simply keep foreign fields. Debug-only, low priority.
STATUS: done by econ (live reset in place; CompanyOps summaries cleared too)

## 4. Information for ALL packages (no action needed unless noted)
- Replication is now a leaf diff (ReplicatedStorage/Shared/StatePatch): every field of `session.data` and
  `session.live` is replicated automatically and only when it changes. There is NO signature list to extend
  any more — `SessionService.profileSignature` is gone (data_ui pitfall 1 / LOGIC_BRIEF §3 "add to
  profileSignature" no longer applies; cleanProfile/profilesConsistent/StaffAssignment/Rig.Profile still do).
- New `session.live.*` fields: write them as plain data (string keys, arrays without holes, no cycles, no
  functions) — same rules as the save data. Rebuilding an equal table every tick is fine (not resent).
- Counters that change every simulation second but are not shown live: ask the net owner to add their path
  to `LAZY` in SessionService (compared every 5 s instead of every send). Today: projects/gallery
  `visitors`/`revenueTotal`, marketplace offers `users`.
- Shop package: server-only purchase records go to `data.shop.receipts` and `data.shop.order` — these two
  keys are never sent to the client (full or delta); everything else under `data.shop` replicates.
- MarketService no longer replaces `session.live`; it merges its own keys (users, revenue, cost, perModel,
  npcUsers, marketplace). Fields written by other services survive the market tick.
STATUS: already done (integrate: info)
