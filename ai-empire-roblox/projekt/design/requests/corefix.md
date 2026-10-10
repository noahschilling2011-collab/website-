# Requests from package "corefix" (verified findings of the econ/models build that live in files corefix does not own)

corefix owns the econ + models files (with the same "ONLY" limits). Everything below is outside them. The game
works without each item; each one closes a verified finding or makes another part match CORE_SPEC exactly.
Public API added by corefix (all in files corefix owns):
- `CompanyOps.post(e, text, clock?)`: one news line stamped with THIS company's day and the visible hour
  ("day 8 11:54: ..."). Use it for every automatic action outside `Ops.step` (never write `deals.news` directly).
- `CompanyOps.clip(s, n)`: cut a string to n bytes on a UTF-8 character boundary.
- News lines are <= `CompanyOps.NEWS_CHARS` = 80 bytes incl. the 14-byte stamp (Appendix A allows <= 120; 80 keeps
  the 3 KB deals budget of 11.8). Keep texts short, e.g. "rep to Helix Research: pilot, flight + 2 nights, $2,520".
- Replicated (client) view of `empire.deals`: accounts `{expires, renewing?}`, tripList `{client, kind, back,
  founder?, hosted?}`, newest 20 news, trust (0.001 steps), counters. `since`, `crew`, `left` stay on the server;
  `live.ops.trips` carries name, tier and crew of every trip. Replicated `empire.ledger`: newest
  `CompanyOps.LEDGER_SHOWN` = 4 company days (7 saved), <= `CompanyOps.LEDGER_CATEGORIES` = 16 lines per side and day.
- Apprentices: `HireEmployee {roleId, apprentice = true}` (stage >= 3, else `OFFICE`): 50 % fee, skill 1 -> 3,
  40 % wage, regular after 9 company days (news line "apprentice X graduated"). The Training Lead ($900/day) is
  paid only while the company has apprentices.
- Office attribute `SiteGoal` (garage stage only): "Future HQ of <company>\nFirst client: signed|not yet\n$x / $27,000
  saved"; EmpireService also writes it into the site board's `Body` label (whole $1,000 steps, only on change).
- Marketplace offers carry `vage` in whole 30 s steps (`MarketService.OFFER_AGE_STEP`), compared lazily.
- `EconomyService.spend/grant` without a category book "other" (the P&L always adds up to the change in cash).

## 1. StaffService (later staff-life / HR package) - ONE visible clock (CORE_SPEC 6, 5.3, 11.1) [major finding]
Not in corefix's StaffService scope ("ONLY: arrival fix, tier mapping, no money writes"), so re-filed from
econ request 1 with the exact change. File `ServerScriptService/Server/Services/StaffService.module.luau`:
```lua
local Ops=require(ReplicatedStorage.Shared.CompanyOps)
local function shownHour(): number return Ops.hour(workspace:GetServerTimeNow()) end
-- sync (spawn placement, ~:84):   local hour=shownHour()
-- Staff.tick (~:363):             local hour=shownHour();Lighting.ClockTime=hour
-- Staff.init Jobs.bind (~:346):   hour=function(): number return shownHour() end
-- lunch day (~:134, :162):        math.floor(workspace:GetServerTimeNow()/1200) instead of math.floor(time/1200)
```
Same in `StaffJobs.module.luau` (life): the three `math.floor(time / 1200)` lunch-day computations (countPlate,
lunch end, officeTick) -> `math.floor(workspace:GetServerTimeNow() / 1200)`, so `LunchesServed` resets with the
visible day. Keep `time` as the monotonic timer (e.next, cooldowns, Nav.pump). Then the sky, `Lighting.ClockTime`,
`CompanyHour` and who sits at the desks agree with trip departures (08:00-15:00), research/data duty (nothing at
night), IT on duty and the news stamps. Absences (CORE_SPEC 5.3): `CompanyOps.presence(e, role)[i]` is "present" |
"vacation" | "sick" | "leave" | "trip" for profile i -> anything but "present" = `OffDuty = true`, desk released,
`employees[role]` unchanged. Test note: the mock's server clock starts at 16:53 (`1.7e9 % 1200`), so staff/life/
talk suites that expect a morning need a fixed clock (e.g. a `Staff.clockOffset` for tests, or advance
`M.Sched.now` to 08:30 before building). Verified headlessly: exactly this patch in a private tree
(`agents/corefix/clock_src`, `RUNALL_SRC=agents/corefix/clock_src RUNALL_TAG=corefix/clock tests/lead/run_all.sh`,
log `agents/corefix/runall_clock.txt`): it compiles, 36 of 39 suites stay at 0 failed; staff_sim (1 failed),
life_t1 ("lunch happened", "wellness break happened") and buildings_tier0 ("staff take coffee breaks in the garage
coffee corner") fail only because the mock clock shows 16:53 -> night after 100 s, i.e. the tests need the
morning clock above, not a code fix.
STATUS: done by staffops (StaffService/StaffJobs: hour, Lighting.ClockTime, CompanyHour, schedules and the lunch day from CompanyOps.hour(workspace:GetServerTimeNow()); the timer `time` starts at the server clock and never falls behind it; absences via CompanyOps.presence -> OffDuty, desk released; staff_harness/test_sim, tests/life/test_life and tests/buildings/test_tier0 start at 08:36 via Sched.now)

## 2. HUD "Next goal" bar (later UI package, `Client/UI/Screens/HUD.module.luau`) (CORE_SPEC 8.2) [major finding]
`HUD.nextStep`: once `snapshot.data.company` exists, show `EmpireMath.nextGoal(snapshot.data, snapshot.live)`:
`{id, text, have, need, etaMinutes?}` -> title = text, progress = have/need, "~N min" from etaMinutes (nil = no
ETA, 0 = "ready"). Today a new player sees "Next step 1/7 Get training data" instead of "Train your first AI".
STATUS: done by apps (HUD.describe words EmpireMath.nextGoal: title = text, bar = have/need, ETA from etaMinutes ("ready" at 0, none when nil), Save-mode tag, tap opens the app; tests/apps/test_ui garage/client/save/mid/rich/phone)

## 3. AssistantService.briefing (owner of the assistant) (CORE_SPEC 8.2) [part of a major finding]
Add the sections Today / Customers / Money / Models from real state only: `CompanyOps.presence` per role (at
work / vacation / sick / trip counts), `data.empire.deals.accounts` (+ `CompanyOps.client(id)` for names and needs),
`live.ops.trips`, `live.capacity/load/waitlist`, `model.market.vage` ("Your Coding line is 41 min old (-5 fit)":
`ModelMath.ageFit`), `CompanyOps.hrNeed` ("Growth team at full effect"). At an office move say "New HQ: profit dips
for ~15 minutes while new people start" (CORE_SPEC 9.5).
STATUS: done by apps (sections Today / Customers / Money / Models first from CompanyOps.presence, deals.accounts, live.ops.trips, the ledger, live.capacity/load/waitlist, ModelMath.ageFit, reachCap; the Next goal is recommendation 1; New HQ note after an office move; tests/apps/test_server)

## 4. EmpireApp (later UI package) - the player decisions of CORE_SPEC 8.1 / 3.2 / 6 [major finding]
No client sends hrBudget / hrAuto / saveMode / buyJet / nightShift / DealAction / apprentice hires yet:
- replace the legacy "Contracts" tab (`EmpireConfig.CONTRACTS = {}`) and the plan text "3. Deliver client
  contracts" (:149) with a "Clients" tab from `data.empire.deals`: accounts with days left
  (`(expires - empire.seconds)/1200`), trust bars (`deals.trust[id]`), trips under way (`live.ops.trips`), pin / skip
  buttons -> `DealAction {action="pin"|"skip", clientId}`;
- a "P&L" card per company day from `empire.ledger[day] = {i = {cat = $}, o = {cat = $}}` (4 days replicated);
- a settings card: wage budget 25/40/55 % (`EmpireAction {action="hrBudget", budget}`), HR auto (`hrAuto`, on),
  Save mode auto/off (`saveMode`, mode), "Buy company jet $900,000" (`buyJet`, stage >= 4), night shift per
  department (`nightShift`, dept, on; stage >= 3), "Hire apprentice" per role (`HireEmployee {roleId, apprentice=true}`,
  stage >= 3);
- remove the "Monthly business customers" / "Business MRR" card (:371-380): the lease auction is gone,
  `empire.customers` is always empty and `businessRevenue` 0 (corefix empties them in old saves).
The error texts exist in ActionController (FIRST_CLIENT, OFFICE, OWNED, MAX_LEVEL, ...).
STATUS: done by apps (Clients tab with pipeline cards + Pin/Skip/Join -> DealAction, Money tab = ledger P&L today + 4 days + running rates, Settings tab = hrAuto / hrBudget / saveMode / nightShift per role / apprentice hires / buyJet / Lab link; Contracts tab and the Business MRR card removed)

## 5. BuildingStateService (owner of the screens) - lease readers
`empire.customers` / `businessRevenue` are empty compatibility fields now (CORE_SPEC 2.4; corefix clears stale
values on load). Replace the readers with the B2B accounts:
- :344 "API customers %d" -> `CompanyOps.client` names / count of `data.empire.deals.accounts`;
- :409-419 `P.customers` ("API customers N · $X/min from leases") -> accounts with retainer/day
  (`client.retainer`) and `live.ops.b2b` ($/min);
- :552-553 "API leases %d" -> accounts count; the training-share line should read "projects" only.
STATUS: done by apps (customers / growth / platform screens read deals.accounts + live.ops.b2b + live.compute.reserved; no lease text left; reception shows today's trips; data hall shows load, faults, reserved compute; new fleet-office screen B1_FLEET)

## 6. CityPlan (world / airport package) - player ticket $700 (CORE_SPEC 11.4) [major finding]
`ReplicatedStorage/Shared/Config/CityPlan.module.luau:31`: `ticket=1500` -> `ticket=700` (= `CompanyOps.TRIPS.abroad.flight`).
tests/world/test_travel.luau reads the value from the config, so it needs no change.

## 7. SecurityController (client, owner of the camera UI) - floor titles by plan tier
`Client/Controllers/SecurityController.module.luau:29-32` `tier()` returns the office index; since
`Plan.OFFICE_TIER_OFFSET = 1` the titles are one building off (garage level 0 shows "G · Reception, atrium ...").
Change to `return Plan.tierForOffice(if snapshot then snapshot.data.empire.office else 1)` (CORE_SPEC 2.4).
STATUS: done by apps (SecurityController.tier() = Plan.tierForOffice(office); buttons in English)

## 8. Ledger categories in other packages' files (P&L lines; they already land in "other")
- FacilityService:588 `Economy.grant(s,net)` -> `Economy.grant(s,net,"retail")` (CORE_SPEC 3.6 retail line);
  :245 seller share -> `"retail"`; :241 / :256 / :275 snack and campus purchases -> `"campus"`;
- RecruitingService:710 interview hire `Economy.spend(s,cost)` -> `Economy.spend(s,cost,"hire")` (agency hires
  already book "hire");
- VehicleService:193 `Economy.spend(s,def.price)` -> `"cars"`;
- AssistantService:435 coffee run -> `"campus"`, :322 / :407 refunds -> `Economy.grant(rec.session,rec.paid,"campus")`;
- ShopService:379 Robux cash pack -> `EconomyService.grant(session, amount, "shop")`.
STATUS: FacilityService (retail / campus) and RecruitingService (interview hire -> "hire") done by staffops; VehicleService, AssistantService and ShopService are not staffops files
STATUS: AssistantService part done by apps (coffee run spend and both refunds book "campus"); VehicleService and ShopService still open

## 9. EmployeeConfig (owner: life / talk) - operations pay constant (CORE_SPEC 5.5, 11.5)
Add `Config.OPS_WAGE_PER_DAY = 720`. `CompanyOps.OPS_WAGE` reads it (fallback 720); TalkService can then state
the real pay of operations staff.
STATUS: done by staffops (EmployeeConfig.OPS_WAGE_PER_DAY = 720)

## 10. ComputeApp (owner of the Compute app) - GPU split hint
`Client/UI/Apps/ComputeApp.module.luau:85`: "More training compute leaves less capacity for projects and business
customers." -> "... for studio projects." (`trainingShare` affects projects only; B2B reserves compute itself).
STATUS: done by apps (ComputeApp: "... for studio projects. Business clients reserve their own compute.")

## 11. Lead - run_all.sh and the sandbox
- Add the suites (each prints "<name>: N passed, M failed"):
  ```
  python3 harness/make_manifest.py --src work/src --gen harness/.gen_corefix >/dev/null
  for t in ops b2b service migration net; do run "econ_$t" bash -c "cd tests/econ && ../../tools/luau test_$t.luau -a .gen_corefix"; done
  run corefix           bash -c "cd tests/corefix && ../../tools/luau test_corefix.luau -a .gen_corefix"
  run corefix_ui        bash -c "cd tests/corefix && ../../tools/luau test_ui.luau -a .gen_corefix"
  run models            bash tests/models/run.sh
  ```
- `tests/lead/sandbox.py` symlinks `tools`; Luau `require` does not follow the symlink, so
  `tests/models/ui_setup.luau` (`require("../../tools/guiprev/guidump")`, also used by tests/corefix/test_ui.luau)
  fails inside a RUNALL sandbox. Copy `tools/guiprev` into the sandbox instead of linking the whole `tools` dir.

## 12. CORE_SPEC (lead) - decisions to record
- 2.4 MIGRATIONS[5] also empties `customers`/`businessRevenue` and normalises product lines (one live model per
  line, best overall kept, users x MIGRATE + organic move, replacedBy; lines beyond PRODUCT_SLOTS[stage] with the
  fewest users go back to "trained", release data kept).
- 11.8 budgets at the caps: news 80 bytes per line, replicated ledger 4 of 7 days, <= 16 categories per side.
- 7.7 auto-price: first cycle 150 s after the company starts ticking (the design bot's phase), then every 300 s.
- 5.5/10 rack faults: 1 compute unit per fault (`FAULT.units`), as written; the econ build took whole GPUs.
- 11.1 Training Lead: paid only while there are apprentices.
