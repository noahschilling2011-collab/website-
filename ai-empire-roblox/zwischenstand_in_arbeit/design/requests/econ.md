# Requests from package "econ" (company economy, calendar, B2B pipeline, costs, servers, save v6)

The econ code works without any of these (guarded reads / fallbacks); each item makes another part of the
game match CORE_SPEC exactly. Public API of the econ side: `ReplicatedStorage/Shared/CompanyOps` (calendar,
time sheet, presence, outputs, HR need, trips, trust, capacity, rack faults, guest house, Lab cost),
`EmpireMath.nextGoal(data, live)`, `EconomyService.applyFlow(session, revenue, cost, category?)` (and
`spend/grant(session, amount, category?)`), remotes `EmpireAction` / `DealAction`.

## 1. StaffService (owner of the staff-life / HR visuals package) — ONE visible clock (CORE_SPEC 6)
File `ServerScriptService/Server/Services/StaffService.module.luau`. Today the shown hour comes from a
private counter `local time=54` (line ~30): `local hour=Config.hour(time);Lighting.ClockTime=hour` in
`Staff.tick` and `hour=function() return Config.hour(time) end` in `Jobs.bind`. The economy uses the server
clock: `CompanyOps.hour(workspace:GetServerTimeNow())` decides trip departures (08:00-15:00), research /
data duty (nothing at night), IT on duty for rack faults, and stamps the news ("day 8 11:54").
Change (keep `time` as the monotonic timer for all e.next / cooldowns):
```lua
local Ops=require(ReplicatedStorage.Shared.CompanyOps)
...
local hour=Ops.hour(workspace:GetServerTimeNow());Lighting.ClockTime=hour            -- Staff.tick
Jobs.bind({..., hour=function(): number return Ops.hour(workspace:GetServerTimeNow()) end, ...})
```
and use `math.floor(workspace:GetServerTimeNow()/1200)` instead of `math.floor(time/1200)` for the lunch day.
Why: otherwise the sky/lights and who is at the desks disagree with what the company does (the founder's
car "leaves at night", research stops while the office looks busy). Note: the mock clock starts at 16:53
(`1.7e9 % 1200`), so staff tests that expect a morning start need `opt.hour` like the economy simulator.
Also for that package (CORE_SPEC 5.3/11.1): who is away today is `CompanyOps.presence(e, role)`
("present" | "vacation" | "sick" | "leave" | "trip", per profile index) -> `OffDuty = true`, desk released.
STATUS: done by staffops (see corefix.md #1)

## 2. EmployeeConfig (owner: life / talk) — operations pay constant (CORE_SPEC 5.5, talk request 6)
Add `Config.OPS_WAGE_PER_DAY = 720`. `CompanyOps.OPS_WAGE` already reads it (fallback 720) and books
$720 per post per game day; TalkService can then state the real pay.
STATUS: done by staffops

## 3. FacilityService (owner: life) — retail as its own ledger line
`economyTick` (~:512-523) books the shop ticket revenue with `Economy.applyFlow(s, revenue, 0)`, which now
lands in the P&L line "market". Change to `Economy.applyFlow(s, revenue, 0, "retail")`.
STATUS: done by staffops (retail ticket income and the seller share book "retail", snack / retail-upgrade purchases "campus")

## 4. CityService (owner: world) — the player's own flight tickets in the ledger
Ticket purchase / refund: `Economy.spend(session, ticket, "travel")` and `Economy.grant(session, ticket, "travel")`
(the refund also subtracts from `stats.totalCost` as today). Optional, P&L only.
STATUS: done by flight (CityService.flight and ShuttleService ticket / VIP helicopter: spend and refund on "travel";
tests/flight/test_shuttle checks the refund line).

## 5. tests/lead/run_all.sh (lead) — add the econ suites
```
python3 harness/make_manifest.py --src work/src --gen harness/.gen_econ >/dev/null
for t in ops b2b service migration net; do run "econ_$t" bash -c "cd tests/econ && ../../tools/luau test_$t.luau -a .gen_econ"; done
```
Expected: 173/0, 61/0, 83/0, 83/0, 11/0 (about 15 s together). Mutation proof: `tests/econ/negative.sh`
(11 of 11 mutations detected). Economy check against CORE_SPEC 9: `agents/econ/run_sim.sh <label> [args]`
(real work/src, no patches).
STATUS: already done (integrate: run_all runs econ_{ops,b2b,service,migration,net} on harness/.gen_corefix)

## 6. Later UI package (HUD / phone / Empire app) — what the econ state offers
- `EmpireMath.nextGoal(snapshot.data, snapshot.live)` -> `{id, text, have, need, etaMinutes?}` (CORE_SPEC 8.2 order).
- `live.ops` (lazy, 5 s): `b2b, guest` ($/min income), `<cat>Cost` ($/min per cost line: wages, ops, upkeep,
  food, fleet, guest, jet, b2bserve), `accounts, limit, slots, reps, ops, drivers, guests, day, paused, saveMode,
  income` (5-min trailing $/min), `travelling, trips = {{client, name, kind, tier, back, founder, hosted, crew}}`.
- `live.compute = {units, lost, reserved, slots, it, faults = {{slot, gpu, since}}}`; `live.capacity`,
  `live.waitlist`, `live.load`, `live.demand` (users in 500M-model units).
- `data.empire.deals`: `accounts[id] = {expires, since, founder, renewing}` (play seconds = `empire.seconds`),
  `trust[id]`, `tripList`, counters, `news` (the client gets the newest 20 of 40), `pinned`, `skip[id]`.
- `data.empire.ledger[tostring(day)] = {i = {cat = $}, o = {cat = $}}` (7 days), `calendar.day`,
  `hr = {auto, budget}`, `saveMode`, `labLevel`, `jet`, `nightShift[dept]`, `unpaidLeave`.
- Remotes: `EmpireAction {action = "labLevel" | "buyJet" | "hrBudget" (budget 0.25/0.40/0.55) | "hrAuto" (on) |
  "nightShift" (dept, on) | "saveMode" (mode "auto"/"off") | "autoPrice" (model, on)}`,
  `DealAction {action = "pin" | "skip" | "joinMeeting", clientId}`; error texts are in ActionController.
- `Format.perDay(perSecond)` ("+$12,345/day") and `Format.dayClock(day, hour)` ("Day 8 · 11:54").
- EmpireApp still shows the old "customers" card (lease auction, always empty now) and CONTRACTS (empty):
  replace with the B2B accounts / pipeline view.
STATUS: done by apps (HUD Next goal + per-day money, Company app Clients / Money / Settings from deals, ledger, hr, saveMode, nightShift, apprentices, jet; Hardware app from live.compute / capacity / load / waitlist / ops; lease card removed)

## 7. Later visual package (servers, guest house, trips)
- Office attributes written by EmpireService on change: `RackFaults` ("3,7" = failed blade slots; slot i =
  the i-th child of `Office.Blades` in PlotService's lighting order, best GPU first), `ServerFaults` (count),
  `HotelRooms` (12) and `HotelGuests` (7 + 2 per hosted client team) from stage 3. IT fixes a fault in 60 s
  while `live.compute.it` is true (IT post on duty), otherwise 300 s: the IT walk to the rack can use that.
- Trips as data only (`live.ops.trips`): cars / NPCs / flights are not created by the econ package.
STATUS: done by staffops (RackFaults / ServerFaults slots mirrored on the blades as FxState/FaultSlot/FaultUntil; IT or an engineer walks to the rack and repairs until CompanyOps clears the fault; PropFxController draws the fault)
