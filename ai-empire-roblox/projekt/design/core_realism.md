# AI Empire — Core company logic, lens "REAL STARTUP SIMULATION"

Design for the company logic redesign of LOGIC_BRIEF.md. Every number in sections 2–9 is either (a) a value
chosen here and played by the economy simulator, (b) a simulator result, or (c) marked **not simulated**.

Evidence lives in `agents/design_realism/economy/` (my copy of the simulator, same depth as the original so the
`../../../harness` and `../../../tools/luau` paths work unchanged; `gen/` regenerated from `work/src` at 16:24):

| File | What it is |
|---|---|
| `patches_realism.luau` | The design as in-memory patches on the REAL sources (11 patches, list `REALISM_SET`). New mode `"@append"` inserts code before a module's final `return`, so overrides can use the module's locals. |
| `realism.luau` | Sim-side implementation of the three NEW services that do not exist in `work/src` yet: StaffService time-sheet feed, DealService (leads → pilot trip → retainer → account reviews, fleet, hotel, flights), Guest House. Money moves only through the real `EconomyService` with category tags. |
| `sim.luau` | Original bot + `--design realism`, `--seed`, `--set k=v` (tuning), ledger tags, window shares, line-aware release, "save for the next office" rule, studio repeats per company day, version refresh. |
| `nest_test.luau` | Anti-clone / product-line check on the patched `MarketMath`. |
| `out_final_casual.txt`, `out_final_opt.txt`, `out_final_late60.txt` | The three required runs (240 game minutes). |
| `out_final_s1..s4.txt`, `out_final_l1..l3.txt`, `out_final_optlate60.txt` | Robustness: other seeds (training noise, events, deal dice), late join with other seeds, optimiser joining late. |
| `out_nest_realism.txt`, `out_nest_orig.txt` | Clone check, new vs original market code. |

Reproduce: `cd agents/design_realism/economy && ../../../tools/luau sim.luau -a --design realism --profile default --minutes 240`
(add `--late 60`, `--profile opt`, `--seed n`). One casual run takes ~25 s, an opt run ~3 min.

What the bot does (unchanged from the analysis bot unless noted): claims quests, buys GPUs at ≤60 % of free cash,
buys data by quality-per-dollar, trains the largest affordable model, releases with sub $5 / API $2 / marketing
≤$5k (casual) or an optimised price/target/marketing (opt), hires the four roles in turn up to the office cap,
researches in a fixed order. New for this design: (1) when the next office costs ≤ 8 minutes of current profit it
stops other investments until it can buy it (the assistant gives exactly this advice), (2) a release goes to a
product line and replaces the live model of that line (users migrate), and at the line cap the casual default is
"new version of the weakest live product", (3) a live product older than 3600 s gets a fresh version if the new
model is at most 6 points worse, (4) studio briefs are re-delivered once per company day.

---

## 0. The design in numbers

| Thing | Today (work/src) | This design |
|---|---|---|
| First stage | Founder HQ, 24 desks, 13.5k parts | **Garage Lab**: founder + 4 hires, 2 GPU slots, ~700 parts, fenced future-HQ site |
| Stages | 4 (0 / 18k / 90k / 350k) | 5 (0 / **25k / 55k / 250k / 2.5M**), save migration office +1 |
| Start money | $25,000 | **$12,000** (new companies only) |
| Market | FIT_SCALE 10, pools 7.0M users, clones stack, NPCs uncapped | FIT_SCALE **18**, pools **1.385M** (rebalanced per line), company nest **λ 0.15**, product lines, ageing, NPC fast-follower ceiling |
| B2B | 12-client self-serve auction (≤$13/min in practice) + once-a-UTC-day contracts | **18-client pipeline**: lead → pilot trip (car / hotel / flight) → retainer per 3-day cycle → review visits; ceiling $24k/min |
| Wages | $0.20–0.50/s, around the clock, offscreen staff 100 % productive | **$1.00–1.50/s** salaried (paid always), output from the **time sheet** (on duty 08–18, lunch, 10 % vacation+sick), identical on/offscreen |
| Hiring fee | price·(1+0.05n+0.001n²) | **flat 2 game days of wage** ($2.4k–3.6k) |
| Ops staff | 12 unpaid, never eat | **paid posts** 0/6/9/12/14 (+2 guest house), $360/day each |
| New running costs | — | rent, utilities, lunches, car leases, trips (fuel, flights, hotel, per diem), guest house |
| Casual sim $/min at 5 / 10 / 60 / 180 min | 8,678 / 4,611 / 18 / 1 (collapse) | **2,682 / 3,665 / 15,427 / 72,757** |
| Casual stage times (5 seeds) | office 2 never reached | Founder HQ **8.1–8.3**, Startup Campus **18.9–34.5**, Innovation **77–94**, Global HQ **143–173 min** |

---

## 1. Core loop

**For a 13-year-old:** You start an AI company in your garage with $12,000. You buy a graphics card, collect data
and train your first AI. You launch it as an app: people subscribe and money comes in every second, day and night.
A friend's company, CloudDesk, wants to test your AI — you drive there, show it, and if they like it they pay a
pilot fee and then a fee every few game days. With the money you hire people. Engineers make training faster,
data curators collect data, researchers invent better technology, and Growth & Sales people find customers and
drive (or fly) to them — the company pays their car, hotel and plane ticket. Your team works in the daytime, eats
the lunch the chef cooks, sometimes goes on vacation or is sick, and goes home at night. A bigger office gives you
more desks, more product lines and bigger customers further away. Rival labs copy the best ideas on the server,
so you have to keep shipping better versions of your AI.

**First 10 minutes** (casual run `out_final_casual.txt`; server clock starts 08:36, see §6 for night starts):

| Time | What the player sees | What happens (code) | Money |
|---|---|---|---|
| 0:00 | Spawns at the plot: a fenced building site with a sign "Future home of ‹Company›" and a small **Garage Lab** with an open roller door, one laptop on a workbench, an empty rack, four empty desks, a whiteboard, a coffee machine, the Founder's Hatch parked outside. Assistant card: "Step 1: buy a GPU and train your first model." | `CreateCompany` → stage 1 (Garage Lab). DealService creates the scripted first lead: "Your friend at CloudDesk wants a pilot when you have a model" (reliability ≥ 24). Quest "Open the doors" +$1,200. | $13,000 (incl. daily $1,000) |
| 0:00–0:20 | Buys data and 2 consumer GPUs (rack fills), starts a 100M model on the laptop+GPUs. | Quests data +1,800, gpu +1,500. Training s100m 18 s. | |
| 0:20 | First model "Nova1" is live (developers line). Phone notification: first subscribers. | Quests train +2,500, release +3,000. First market $/s. **First recurring $ at 0:20.** | |
| 0:20 | As soon as Nova1 qualifies (reliability ≥ 24) the founder drives the Hatch out to CloudDesk (city). | DealService: pilot trip, 0.2 day (240 s), fuel $30 + per diem $50. Founder sells himself in the garage stage. | |
| 0:40 | "Word gets around" (5,000 peak users) +$10,000. First studio brief (Cedar Coffee website) +$3,500. | StudioService brief repeat per company day. | |
| 1:00–5:00 | Hires 4 people (one per desk, quest "Two pairs of hands" at 1:54). They walk in and sit down. Research "Parallel Training" starts. | Agency fee $2.4–3.6k each; wages $315/min for all 4. | |
| 2:40 | Bigger model (1B) replaces Nova1: "Nova2 replaces Nova1 — users move over." | Version rule: 90 % of users migrate. | |
| 4:20 | Founder is back: **"CloudDesk signed! Pilot +$9,000, then $18,000 per 3-day cycle ($300/min)."** | Win chance 0.45 + 0.03·(reliability − 24), capped 0.92 (the 1B model has a margin of ~15). | $20,061 at 5:00, revenue $2,682/min |
| 5–8 | Third studio brief (Field Supply shop, +$8,000), second city lead (Paper Studio) drives out. Assistant: "Founder HQ costs $25,000 — a few minutes of profit. Save for it?" | Saver rule (bot) = assistant recommendation (§8). | |
| 8:20 | Paper Studio signed (+$9,000). **"Out of the garage!"** — the building site turns into the Founder Headquarters (old tier 1), quest +$5,000. Ops staff appear: receptionist, chef, barista, security, IT, facilities. 2 product lines unlocked, leased company car for sales. | `UpgradeOffice` stage 2, PlotService rebuild tier 1. | |
| 10:00 | Second product (general/consumer line) launched next to the developer API. Lunch is served in the café. | | revenue **$3,665/min** (window 5–10 min: market 44 %, pilots 31 %, quests 17 %, retainers 7 %) |

Robustness: revenue at minute 5 is $2,483–3,341/min and at minute 10 $3,067–5,268/min over all 11 final runs; the
garage phase ends at 8.1–8.3 min for casual players (10.0 for the optimiser joining a 60-minute-old server).

---

## 2. Office stages

### 2.1 Stage table

`EmpireConfig.OFFICES` gets five entries with new fields (`tier` = building tier for BuildingPlan, 0 = garage).

| # | Stage | Building | Price | Staff cap | GPU slots | Thermal base (×cooling) | Rent $/day | Utilities $/day | Paid ops posts | Product lines (live models) | Training slots | Base RP/s |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | **Garage Lab** | tier 0 (new) | 0 | 4 | 2 | 10 | 0 | 60 | 0 | 1 | 1 | 0.10 |
| 2 | Founder Headquarters | tier 1 | 25,000 | 24 | 6 | 20 | 1,200 | 300 | 6 | 2 | 1 | 0.15 |
| 3 | Startup Campus | tier 2 | 55,000 | 64 | 12 | 40 | 3,600 | 900 | 9 (+2 guest house) | 3 | 2 | 0.30 |
| 4 | Innovation Campus | tier 3 | 250,000 | 128 | 24 | 60 | 9,600 | 2,000 | 12 (+2) | 4 | 3 | 0.60 |
| 5 | Global AI Headquarters | tier 4 | 2,500,000 | 240 | 48 (+48 cluster) | 80 | 24,000 | 4,000 | 14 (+2) | 4 | 4 | 1.00 |

"Price" = fit-out + deposit (paid once); rent is the recurring cost (§4). A game day is 1200 s, so $1,200/day = $60/min.

### 2.2 What each stage unlocks (gameplay)

| Stage | Departments / rooms | Revenue streams | Fleet & travel | Other |
|---|---|---|---|---|
| Garage Lab | one shared room: 4 desks (any role), workbench, 2-slot rack, whiteboard, sofa | 1 product line, studio briefs, **city pilots sold by the founder** (founder leads 4/day, founder alone on trips) | the founder's own car (no lease) | no chef (pizza $12/lunch, lunch counts half for morale), no HR, no ops staff, no lift |
| Founder HQ | all 9 departments of tier 1 (data, design, research, evaluation, engineering, training, growth, deployment, operations), café + kitchen, gym/sauna (half wellness), reception | 2 lines, **region clients** (overnight trips, hotel) | leased cars for field sales, `ceil(S/3)` ≤ 19 bays | chef → lunch morale, 6 paid ops posts, HR plans vacation automatically |
| Startup Campus | product studio, customer & support, People & Company office (HR), full wellness | 3 lines, **abroad clients** (airport, flights, 2 hotel nights) | + fleet manager post | **Guest House** (12 rooms, hotel_site.md "west wing"): hosts every second regional/abroad pilot at HQ, outside guests pay; 2 training slots |
| Innovation Campus | research floor (23→ seats), evaluation labs | 4 lines, top research clients (Helix, Orbit Systems) | | 3 training slots |
| Global AI HQ | advanced labs, platform ops, cluster control | frontier clients (Nova Infrastructure $225k, Frontier Science $300k per cycle) | | 4 training slots, 48 slots (+48 with Distributed Cluster) |

### 2.3 The Garage Lab (new tier 0) and the plot around it

- **Building**: one storey, 42 × 40 studs, on the east front lawn at plot-local x 20..62, z −200..−160 (lawn
  x 12..70, z −217..−120, `ExteriorDesign:942-946`; lawn props inside the footprint are skipped at tier 0), roller door facing the visitor bays (x 72..90),
  so the founder's car stands where the driveway already is. Contents: 4 desks + founder desk (Computer stations,
  `Role=any`), workbench with the laptop, 1 rack with 2 GPU slots (RackBlades lit per GPU like today), whiteboard,
  coffee machine (CoffeeSteam), mini fridge, sofa, pizza boxes, string lights, 1 TV screen (`P.journey`).
  Budget ≈ 450 parts, ≤ 4 lights.
- **Site**: the rest of `Plan.SITE` is a fenced building site — hoarding panels along the plaza line
  (z −120) and around the HQ footprint (x −96..112, z −64..160), two branded banners "Future home of ‹Company›",
  a site container, survey stakes, gravel pad where the HQ will stand. Budget ≈ 250 parts. Total ≈ 700 parts vs
  13,534 for a tier-1 plot: new players cost the server 5 % of today.
- **Upgrade**: `Plot.refresh` rebuilds as tier 1; the garage is removed and a 6-part plaque "Where ‹Company›
  started" stays on the lawn. No lift (LiftService skips tier 0), no ops posts, no garage B1.
- **Who fits**: the founder (player) + 4 hires. Staff rigs use `StaffAssignment` with the 4 garage desks;
  the assistant stands at the door.

### 2.4 Old saves (office index +1) and code that uses the index

- `GameConfig.DATA_VERSION` 5 → 6; `Template.MIGRATIONS[5] = function(data) local e = data.empire; if e then e.office = if data.company then math.clamp((tonumber(e.office) or 1) + 1, 2, 5) else 1 end end`
  (a never-founded save starts in the garage; a founded save keeps its building: old 1→2 … old 4→5).
  `quests.office` stays claimed. Old `empire.contracts` (UTC days) are dropped by the cleaner; the old clients'
  pilots become available again in the deal pipeline.
- New helper `EmpireMath.tier(e) = (EmpireConfig.OFFICES[e.office] or OFFICES[2]).tier`. Every use of the index
  that means **the building** reads the tier; uses that mean **progress** (prices, caps, client stages) keep the
  index. Grep finds `.office`/`OFFICES[` in 26 files; the building ones:
  `HeadquartersDesign.build:39` (`tier = clamp(office,1,4)` → `EmpireMath.tier`; tier 0 → new `GarageLabDesign.build`),
  `PlotService.refresh:85-92` (compare `OfficeTier` attribute with the tier), `StaffAssignment`, `WorkstationService`,
  `LiftService` (tier 0: no lift), `DoorService`, `InteriorDesign`, `CoreDesign`, `ExteriorDesign`, `EmployeeNavigation`,
  `CampusService`, `BuildingStateService`, `FacilityService` (`Plan.inside(tier,…)`), `RecruitingService` (visitor routes),
  `AssistantService`, `VehicleService` (garage spawn: tier 0 = in front of the Garage Lab), `SecurityController`,
  `EmpireApp`/`CampusApp` (office tab lists 5 stages). Progress ones: `HardwareConfig.slots/thermal`,
  `EmpireMath.bonuses`, `EmpireService.upgrade/hire`, `AdminService` (commands `tier0..tier4`, `:22` max stage).
- `NPCService.init:283` `d.empire.office=2` → `3` (keeps NPC slots/thermal as today).
- `BuildingPlan.TIER_FLOORS`/`THEMES_BY_TIER` stay 1..4; add `Plan.GARAGE_LAB` rectangle + `Plan.floors(0)=1`.
- Tests/harness: `harness/build_dump.luau --tier 0` for the garage dump; admin `tier1..4` keep their meaning
  (building tiers) and `tier0` is new.

---

## 3. Income sources

### 3.1 Consumer / developer market (MarketMath.tick, MarketConfig)

Product lines = release targets: **Developer API** (`developers`), **Study app** (`students`), **Enterprise API**
(`businesses`), **Consumer chat** (`general` → segment `consumers`).

- Utility of model *i* in segment *s*: `u = (fit − 50)/18 − sens·price/norm − 0.6·[line(i) ≠ s] − ageing(age)`,
  `ageing = min(0.6, max(0, age − 2400 s)·0.15/1200 s)`. (FIT_SCALE 10 → **18**; `LINE_PENALTY 0.6`; `AGEING`.)
- **Company nest (anti-clone), λ = 0.15**: per company *c* and segment,
  `W_c = e^(m_c − pivot)·(Σ_i e^((u_i − m_c)/λ))^λ`, model share `= W_c/den · e^((u_i − m_c)/λ)/Σ_j e^((u_j − m_c)/λ)`,
  `den = e^(outside − pivot) + Σ_c W_c`. Two identical clones raise the company weight by 2^0.15 = 1.11 (today: 2.0).
- **Company reach**: `R_c = clamp(base(rep) + max_i hype_i + Σ_i organic_i, 0, 0.9)`; organic_i follows
  `0.6·share_i` as today, so the sum follows the company share — clones cannot each bring their own reach.
- **Pools rebalanced so every line is worth building** (users): developers 250k (was 400k), students 375k (1.5M),
  businesses 60k (100k), consumers 700k (5M); `REPUTATION.userScale` 500k (2M). Revenue potential per cycle at
  default prices: 1.5M / 1.9M / 1.4M / 3.5M.
- Revenue/serving as today (`users·sub` or `Mtokens·api`, per 3600 s), × marketing multiplier
  `1 + 0.8·(1 − e^(−G/6)) + 0.15·distribution`, G = day-average working Growth & Sales FTE (§5), × market cycle.
- **Live cap** = product lines of the stage; a release into a line that has a live model is a **new version**
  (§7.3).
- **NPC rival fix (NPCService.tick)**: per-stat ceiling `C = max(58 + 8·(1 − e^(−t_server/7200)), min(95, best live player model − 10))`
  ("rival labs copy the best ideas on the server and stay ~10 behind"); each NPC training moves every core stat
  **and reliability** by `max((2+6q)/√(1+it), 0.5·(C − stat))` but never above C; API price floor **$1.00**
  (was 0.25, the race to the bottom); a new NPC version resets its ageing. In the runs the best NPC sits at 58–63
  until the player passes ~70 and then trails the leader (e.g. 74.8 → 91.3 when the player ships 93.8 → 103.8).

Clone check (`nest_test.luau`: s1b models at overall 62 vs 3 NPC labs at 58, reputation 30, one hour):

| Live set | Revenue $/min | vs 1 model |
|---|---:|---:|
| 1 model (consumer line) | 8,497 | 1.00 |
| 2 identical clones | 9,618 | 1.13 |
| 4 identical clones | 10,864 | 1.28 |
| 1 model (developer line, +8 coding) | 8,306 | 0.98 |
| consumer + developer line | 10,828 | 1.27 |
| 4 lines (each +8 in its line's stat) | 14,536 | 1.71 |

Specialists beat clones (1.27 vs 1.13 for two, 1.71 vs 1.28 for four). For comparison, the original code gives
1.19 / 1.21 for 2 / 4 clones in this setup (`out_nest_orig.txt`); my reading is that at this high share its
per-model reach is already near the 0.9 cap, so clones add little here, while models.md measured +70 % / +122 %
for 2 / 3 clones at reputation 0, where per-model reach stacks.

Hooks: `MarketMath.tick:85-165` (replace), new `MarketMath.lineUtility`, `MarketConfig:30-105` (pools,
FIT_SCALE, NEST_LAMBDA, LINE_PENALTY, AGEING, LINE_OF), `MarketService.entry:48-51` (+`company`, `target`),
`MarketService.tickGlobal:125-168` (remove the `businesses` auction), `NPCService.tick:294-340`,
`LabApp:722,942` (forecast/ranking must use `live.marketplace.offers` as rivals with company + target, as the sim does).

### 3.2 B2B customers: sales pipeline → on-site trips → retainers (new DealService)

One client catalogue `ClientConfig` (new `ReplicatedStorage/Shared/Config/ClientConfig`) replaces
`EmpireConfig.CONTRACTS`, `MarketService.businesses` and is the place for client visits. Retainer = $ per billing
cycle (3600 s = 3 company days), pilot fee = retainer/2, SLA load = retainer/150 M tokens per cycle.

| Client | Where | Needs | From stage | Retainer/cycle | = $/min |
|---|---|---|---:|---:|---:|
| CloudDesk | city | reliability ≥ 24 | 1 | 18,000 | 300 |
| Pixel Games | city | coding ≥ 30 | 1 | 15,000 | 250 |
| Paper Studio | city | creativity ≥ 32 | 1 | 18,000 | 300 |
| ByteWorks | city | coding ≥ 38, coding focus | 1 | 27,000 | 450 |
| North Logistics | city | reasoning ≥ 36 | 2 | 22,000 | 367 |
| StudySpark | city | math ≥ 40, reasoning focus | 2 | 27,000 | 450 |
| Civic Support | city | reliability ≥ 48 | 2 | 36,000 | 600 |
| PixelForge | region | creativity ≥ 48 | 2 | 45,000 | 750 |
| Ledger Finance | region | math ≥ 50 | 2 | 56,000 | 933 |
| Orbit Games | region | coding ≥ 52 | 3 | 56,000 | 933 |
| Atlas Search | region | knowledge ≥ 55 | 3 | 68,000 | 1,133 |
| Delta Robotics | region | reasoning ≥ 60 | 3 | 84,000 | 1,400 |
| Nova Logistics | abroad | reliability ≥ 62 | 3 | 90,000 | 1,500 |
| Mosaic Worlds | abroad | creativity ≥ 65 | 3 | 100,000 | 1,667 |
| Helix Research | abroad | math ≥ 70 | 4 | 125,000 | 2,083 |
| Orbit Systems | abroad | reasoning ≥ 72 | 4 | 175,000 | 2,917 |
| Nova Infrastructure | abroad | coding ≥ 78 | 5 | 225,000 | 3,750 |
| Frontier Science | abroad | reasoning ≥ 85 | 5 | 300,000 | 5,000 |

Ceiling with every client signed: $1.49M per cycle = **$24,800/min**.

Pipeline (all automatic, §8):
1. **Lead** (office hours 08–18 only): leads/day = founder (4 in the garage, 1 afterwards) + 1.0 per *working*
   Growth & Sales FTE. A lead is an idle client of a reachable stage; qualified clients are preferred. At most
   `2 + floor(S/2)` qualified leads + pilots open; an unqualified lead shows "needs coding 52" and expires after 3 days.
2. **Pilot trip** (departures 08:00–15:00): crew = 1 sales + 1 engineer (garage: founder alone, city only), needs a
   free fleet car. City 0.2 day, region 1 day + 1 hotel night per traveller, abroad 2 days + 2 hotel nights +
   flights. From Startup Campus every second regional/abroad pilot is **hosted at HQ** instead (guest house, §3.5).
3. **Decision** at the end of the trip: `p = clamp(0.45 + 0.03·(best model stat − minimum) + 0.05·hosted, 0.15, 0.92)`.
   Win → pilot fee now, retainer starts, reputation +1.5, `contractsCompleted` +1 (quest "Reliable supplier" now
   "Sign three customers"). Loss → client cools down 1 day.
4. **Retainer**: paid per second (`retainer/3600`) while the best qualifying live model meets the need **and** SLA
   capacity is free (`Σ tokens ≤ throughput·100·thermal`, biggest accounts first); serving cost `tokens·serveCost`.
5. **Renewal every cycle**: a review visit must have happened (1 sales, same travel rules) else 35 % churn; active
   accounts > `2 + 3·S` → 50 % churn; model no longer qualifies → account lost.

Sim results: 23 / 19 / 21 pilots, 15 / 16 / 16 wins, 28–34 review visits, 41–47 hotel nights and 11–14 flight
tickets per 4 hours (casual / opt / late 60). Churn never triggered in the bot runs (reviews always happened,
accounts never exceeded the load limit). First city deal at 4.3 min in every run, first region deal at 39–64 min,
first abroad deal at 88–139 min.

Hooks: new `DealService` (`init` binds `DealAction` {pitch-join, cancel, pause-account}; `tick(session, dt)`
called from `Main.server.luau:316-332` after `EmpireService.tick`), saved `empire.deals[clientId] = {s, t, r, rv}`
and `empire.trips[]` (stable staff ids = profile seed `s`, never list index — `EmpireService.fire:59`),
`EmpireMath.new:12-17` defaults, `Template.migrate` cleaner after `:140`, `EmpireService.deliver:100-116` removed,
`P.customers` screen (`BuildingStateService:409-434`), assistant section "Customers".

### 3.3 Pilots (the old daily contracts)

The six `CONTRACTS` are now the pilot step of their clients (CloudDesk, ByteWorks, StudySpark, PixelForge, Nova
Logistics, Orbit Systems). Pilot fee = half a cycle ($7.5k–150k), paid once per signing; a lost or churned client
can be pitched again after its cooldown, so there is no once-per-UTC-day click any more.

### 3.4 Studio (agency gigs)

Unchanged formulas (`StudioConfig.BRIEFS` $3.5k–11k, build cost $650–1,600, work on GPUs), but each brief can be
delivered once per **company day** instead of once per UTC day (`StudioService.deliver:62-72`:
`day = floor(empire.seconds/1200)`). It is the garage-stage side income (30 % of income in minutes 0–5) and
3 % of all income over four hours ($411k of $12.3M).

### 3.5 Guest House (from Startup Campus)

Building as recommended in `hotel_site.md` (west wing, 12 rooms). Money: outside guests **+$864/day**
(12 rooms × 45 % × $160), running cost **−$250/day** + 2 ops posts (reception, housekeeping, $720/day) → about
−$106/day net. Its value is operational: every second regional/abroad pilot is hosted at HQ (client team stays
2 × nights × $60 internal cost, no flights/hotel, +0.05 win chance, crew still busy 1 day). In the sim: 7–9 hosted
pilots per run, guest-house income 0–1 % of income. **Simulated as injected income/cost terms** (no rooms, no guests).

### 3.6 Retail, quests, daily

Unchanged: retail $12 per ticket every 30 s, tickets = retail level + floor(staff/24) (re-implemented in the sim,
`FacilityService.economyTick:512-523`), quests $77k once, daily login $1,000 + $500·(streak−1) (real UTC day).

### 3.7 Income shares (sim windows, `out_final_*.txt` "Shares per window")

| Window | Casual | Opt | Late join (server 60 min old) |
|---|---|---|---|
| 0–10 min | quests 34 %, market 23 %, studio 20 %, pilots 20 %, retainers 2 % ($8,925/min) | quests 41 %, market 27 %, pilots 24 %, studio 5 %, retainers 3 % ($7,479/min) | quests 42 %, market 25 %, pilots 25 %, studio 5 %, retainers 3 % ($7,270/min) |
| 50–70 min | market 75 %, studio 11 %, retainers 8 %, pilots 5 % ($21,348/min) | market 81 %, retainers 8 %, pilots 6 %, quests 5 % ($42,603/min) | market 73 %, retainers 11 %, pilots 11 %, quests 4 % ($20,698/min) |
| 170–190 min | market 70 %, retainers 19 %, pilots 8 %, studio 2 % ($88,659/min) | market 65 %, retainers 26 %, pilots 8 % ($82,812/min) | market 68 %, retainers 32 % ($47,981/min) |
| whole 240 min (casual ledger, $12.29M) | market 72.6 %, retainers 18.1 %, pilots 4.9 %, studio 3.3 %, quests 0.6 %, retail 0.3 %, guest house 0.1 % | | |

B2B (retainers + pilots) is 22 % at 10 min, 13 % at 60 min and 27–34 % at 180 min; in minutes 235–240 retainers
alone are 32–37 % because the catalogue is nearly full while the market stays flat.

---

## 4. Costs

### 4.1 Formulas

| Cost | Formula (all $ per second unless noted; ×1200 = per game day) | Hook |
|---|---|---|
| **Wages** | Σ profiles `wage·w`: researcher **1.25** ($1,500/day), engineer **1.50** ($1,800), data curator **1.00** ($1,200), Growth & Sales **1.50** ($1,800). Salaried: paid while working, at night, on vacation, sick or travelling. Optional night crew (§5.6): +25 % for those heads. | `EmpireConfig.ROLES:10-15`, `EmpireMath.payroll:71-82`, `EmpireService.tick:162` |
| **Hiring fee** | agency hire: flat **2 game days of wage** = 3,000 / 3,600 / 2,400 / 3,600 (was 2.8k–6k growing with n²). Interview hires follow automatically: `Recruiting.hireCost:115` = `EmpireMath.hireCost` × the candidate's ask, wage = role wage × ask. | `EmpireMath.hireCost:112-114` |
| **Paid vacation / sick** | no extra cash cost (salary continues); cost = lost output (10 % of person-days). | §5.3 |
| **Ops staff** | **$0.30/s ($360/day)** per paid post: 0 / 6 / 9 / 12 / 14 by stage, +2 guest-house posts from stage 3 | `EmpireConfig.OPS_WAGE`, `EmpireMath.bonuses` |
| **Rent** | per day 0 / 1,200 / 3,600 / 9,600 / 24,000 | `EmpireService.tick` bill "rent" |
| **Utilities** | per day 60 / 300 / 900 / 2,000 / 4,000, plus serving power `throughput·0.025` while a model is live (today's rule) | bill "utilities", `MarketService:202` |
| **Lunch** | per present employee per workday: **$8** (chef, HQ stages) or **$12** (pizza, garage): `staff·0.9·price/1200` | bill "food" |
| **Fleet leases** | **$70/day** per leased compact for field sales; cars = `min(19, ceil(S/3))` from Founder HQ; the boss's car is owned (Founder's Hatch $0, or bought ones) | bill "fleet", `CampusConfig.CARS` + `campus.fleet` |
| **Trips** | fuel city $30 / region $90 / airport $40 per trip; **flights $700** per traveller (round trip, abroad); **hotel $140** (region) / **$220** (abroad) per traveller-night; per diem $50 per traveller per started day. Pilot crew 2 (garage 1), review 1. | DealService |
| | → city pilot $130, region pilot $470, abroad pilot $2,520; review: city $80, region $280, abroad $1,280 | |
| **Guest house** | $250/day + 2 ops posts; hosted client night $60 | GuestHouse in DealService |
| **Serving** | `Mtokens·serveCost·(0.85 with quantization)` for market users and B2B SLA tokens | `MarketMath`, DealService |
| Capex (unchanged) | training, data, GPUs, cooling, research, marketing, office price | |

### 4.2 Cost shares (sim, running costs only; capex listed apart)

| Window | Casual | Opt | Late join |
|---|---|---|---|
| 0–10 min | opex $716/min = 8 % of income: wages 36 %, studio builds 35 %, serving 20 %, ops 3 %, trips 3 %, rent 1 % | opex 6 %: wages 52 %, studio 28 %, serving 7 %, ops 4 %, trips 5 %, rent 2 % | opex 7 %: wages 43 %, studio 27 %, serving 17 %, trips 5 % |
| 50–70 min | opex $6,683/min = 31 % of income: wages 75 %, serving 11 %, studio 4 %, ops 3 %, rent 3 %, trips (hotel+flights) 2 %, utilities 1 % | opex 20 %: wages 86 %, rent 5 %, serving 4 %, ops 3 % | opex 28 %: wages 80 %, serving 9 %, ops 3 %, rent 3 %, trips 2 % |
| 170–190 min | opex $26,167/min = 30 % of income: wages 72 %, serving 19 %, rent 5 %, ops 1 %, utilities 1 % | opex 27 %: wages 85 %, serving 6 %, rent 5 % | opex 52 %: wages 74 %, serving 18 %, rent 5 % |
| whole 240 min casual | wages $2.60M, serving/power $0.72M, hiring fees $0.76M, rent $157k, ops $57k, utilities $28k, trips $21k (hotel 7.5k, flights 7.7k, fuel 2.2k, per diem 3.2k), food $12k, fleet $9.5k, guest house $4.4k | | |

Wages are now the dominant cost (hiring fees are 29 % of wages over 4 h, were 143 %). Travel, hotel, cars and
lunch are visible P&L lines but together ≈ 1–2 % of running costs — real enough to notice, too small to hurt.

---

## 5. Staff and department production

### 5.1 The formula (identical watched or not)

For role r (its departments d ∈ D(r)):

`O_r(t) = [ min(H_r, Seats_r) + 0.5·max(0, H_r − Seats_r) − Away_r ] · TS(hour) · (1 − 0.10) · M · Q`

- `H_r` = Σ skill factors `(7+k)/10` of the hired profiles (`WorkforceMath.capacity`, absent people skipped).
- `Seats_r` = desks of the role's departments in the current building (BuildingPlan `room.desks`):

| Role (departments) | Garage | Tier 1 | Tier 2 | Tier 3 | Tier 4 |
|---|---:|---:|---:|---:|---:|
| Data curator (data) | 4 shared | 11 | 32 | 32 | 32 |
| Researcher (design, research, ½ evaluation) | 4 shared | 12 | 26 | 50 | 93 |
| Engineer (engineering, training, ½ evaluation) | 4 shared | 16 | 29 | 56 | 85 |
| Growth & Sales (growth, deployment) | 4 shared | 16 | 34 | 34 | 71 |

  Overflow staff work at 50 % (hot desks, meeting rooms); at tier 4 the 60 curators of a balanced team give
  32 + 14 = 46 — a visible reason to rebalance or to add data desks.
- `Away_r` = people on a trip (sales, engineers), on vacation or sick (in the sim: trips explicit, vacation+sick as
  the 10 % expectation).
- `TS(hour)` = **time sheet**, the expected share of a team at work at that hour, from the existing seed-uniform
  shifts (start 7.75–9.0, finish 16.5–18.0, lunch start 11.75–13.5 for 1 h) and 0.94 for short breaks:

| Hour | 7.5 | 8 | 8.5 | 9–11 | 12 | 12.5 | 13–13.5 | 14 | 15–16.5 | 17 | 17.5 | 18–7.5 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| TS | 0 | 0.19 | 0.56 | 0.94 | 0.81 | 0.54 | 0.40 | 0.67 | 0.94 | 0.63 | 0.31 | 0 |

  Real-time day average (1200 s, 900 s are 08–18): **0.554**; with absence **0.499**.
- `M` = morale = `0.88 + 0.08·lunch + 0.04·wellness`: lunch = min(1, lunch capacity / present staff), capacity
  145/day (53 café seats × 2.75 turns in the 11:45–14:30 window; garage pizza = 0.5), wellness 0 / 0.5 / 1
  (garage / tier 1 / tier 2+). Sim: M = 0.92 garage, 0.98 tier 1, 1.00 tiers 2–3, **0.97 at tier 4** (240 staff
  > 145 lunches → a second canteen or pantry lunch counters raise it back).
- `Q` = room quality 1.0 team/focus rooms, 1.1 specialist rooms (datalab, control, lab, evaluation, hwlab,
  platform, studio), −0.05 without a facilities post. **Not simulated (Q = 1 in the sim).**

What the output does (on-shift coefficients and the resulting day average per hired head, M = 1):

| Role | Output per working FTE | Day average per head | Hook |
|---|---|---|---|
| Engineer | training speed +0.25 | +0.125; training slots `min(stage.trainSlots, 1 + floor(avg O_eng/6))` | `EmpireMath.bonuses.speed`, `trainingRate:127-129` |
| Researcher | 1.1 RP/s | 0.55 RP/s | `bonuses.points` |
| Data curator | 550k tokens/s at q 0.65 (0.85 with Data Cleaning) | 274k tokens/s | `EmpireService.tick:152-160` |
| Growth & Sales | marketing multiplier via day average G; 1 lead/day; field crew; account capacity +3 | | `bonuses.revenue`, DealService |

Implementation: `StaffService.tick` (`:340-369`) reports `counts[role] = O_r(t)` and `counts.avg[role]` (same with
the day-average TS) for every company — **the rig states no longer feed the economy**, they only show it (a rig
that is at lunch is at lunch because the time sheet says so). This removes "watching lowers income" and the
offscreen-100 % bug (time_staff.md pitfalls 1, 4, 5) and costs nothing when nobody is near. New
`WorkforceMath.average(e, role)`; `EmployeeConfig.timesheet(hour)`, `ABSENCE`, `TIMESHEET_DAY_AVERAGE`.

### 5.2 Night

18:00–08:00 (300 real seconds) everybody is off duty (TS = 0) except an optional night crew (§5.6). Subscriptions,
retainers and serving run 24/7 (servers do not sleep); training runs at base GPU speed without the engineer
bonus; no curation, no research points, no new leads, no trip departures after 15:00.

### 5.3 Vacation and sick days (HR, automatic)

- Profile field `v` = vacation balance; every worked company day adds 0.1 day. HR books a day off when `v ≥ 1`,
  never more than **15 % of a department** away at once, and not during a trip.
- Sick: daily roll `2 % + 4 %·(1 − M)/0.12` (2 % at full morale, up to 6 % at M = 0.88), 1 day.
- Expected absence ≈ **10 %** of person-days (the sim uses this expectation); salary continues.
- Stored as profile field `a = {k = "vac"|"sick"|"trip", u = untilDay}` (must be added together to
  `EmpireMath.cleanProfile/profilesConsistent:26-49`, `SessionService.profileSignature:50-66`,
  `StaffAssignment.profile:24-33`, `Rig.Profile`). Absent rigs use the OFF_DUTY pattern (`StaffService.sync:94-101`),
  `employees[role]` never changes, so no rig rebuild.

### 5.4 Morale from lunch and wellness

The chef and kitchen team cook; employees eat in the café in the lunch window (existing LunchSeat flow, plate
instead of the brown block). Lunch capacity per day: chef 70, kitchen team +50, café host +25, capped by
53 seats × 2.75 turns = 145. Morale moves output by up to 12 %; at tier 4 the 145-lunch cap costs 3 %.
Gym/sauna (players today) get employee "Workout" break stations → wellness share.

### 5.5 Ops staff become paid jobs with a function

| Post (stage) | Function in the economy | Simulated? |
|---|---|---|
| Reception ×1–2 (2+) | checks in clients/applicants; hosted pilots get +0.05 only with reception on duty | wage yes, effect no |
| Security ×1–2 (2+) | needed for a night crew and for hosting clients after hours | wage yes |
| Chef (2+), Kitchen team (3+), Café host (4+) | lunch capacity 70 / +50 / +25 → morale | wage + morale (as 145 cap) |
| Barista (2+) | break factor 0.94 → 0.96 | wage yes, effect no |
| IT Support (2+) | GPU-failure training event weight −50 % | wage yes, effect no |
| Facilities ×1–2 (2+) | keeps room quality Q (−0.05 without) | wage yes, effect no |
| Fleet manager (3+) | car leases −10 %, keeps the 19 bays | wage yes, effect no |
| Guest-house reception + housekeeping (3+) | runs the guest house | wage yes |
| Data-hall technician, Mailroom (5) | SLA capacity +5 % | wage yes, effect no |

Ops staff follow day shifts (security: day + night rota) and take breaks only when a colleague of the same job is
present (fixes "posts stand empty", staff_life.md). `EmployeeConfig.OPERATIONS_JOBS:11` per stage,
`StaffService` break rule at `:154`.

### 5.6 Night shift (optional, player toggle per department)

Training Control and Customer & Support can run a night crew: N heads move to 18–08 with TS 0.9, +25 % wage, and
need a security post on duty. Use case: 24/7 training speed before a big launch. **Not simulated** (default off).

### 5.7 What each room kind produces

| Room kinds | Production |
|---|---|
| team, focus (dept data/design/research/evaluation/engineering/training/growth/deployment) | seats of that department (Q 1.0) |
| architecture, datalab, control, evaluation, lab, hwlab, platform, studio | seats with Q 1.1; datalab staffed ≥ 50 % → curated quality +0.05; hwlab staffed → GPU-failure events −50 %; platform → SLA capacity +5 %/working FTE; studio → Studio build rate +10 %/working FTE (not simulated) |
| launch, support (Launch & Marketing, Customer Desk, Customer & Support, Partnerships) | Growth & Sales seats: marketing multiplier, leads, account capacity |
| hr (People & Company Office) | HR planner: vacation cap 15 % (garage/founder-planned 20 %), applicants arrive 25 % faster |
| first_ai (G_FIRSTAI) | design + data seats (fix its missing `dept`, building_meaning pitfall 7) |
| meeting, project_meeting, boardroom | meetings count as work (weight 1.0, no −20 %); post-training review in the Project Room; boardroom = hosted pilot meetings |
| pantry, lounge, recovery, terraces, roof | breaks (inside the 0.94 factor) and wellness |
| café + kitchen | lunch capacity → morale |
| gym, sauna | wellness → morale |
| data hall, compute ops, IT desk | GPU slots/blades (locked blades above the stage cap shown dimmed), SLA capacity, IT post |
| lobby, visitor lounge, showroom | reception, applicants, client visits; showroom demo = the +0.05 hosted bonus |
| garage, fleet office, workshop | leased fleet cars in the 19 bays, departures through the barrier |
| guest house (new) | hotel nights for hosted clients, outside guests |
| WC, showers, print, phone, mailroom, storage, UPS, corridors, roof tech | no economic effect (decoration/circulation) |

### 5.8 Value of one more person (computed from the formulas at the casual 60-min state)

| Role | Value per head | Wage |
|---|---|---|
| Growth & Sales (16 seated, G = 8) | +1.76 % market multiplier ≈ **+$148/min** + 0.5 leads/day | $90/min |
| Growth & Sales (32 seated, G = 16) | +0.46 % ≈ +$39/min (same base) | $90/min |
| Data curator | 16.4M tokens/min ≈ $41/min at repo price, $99/min at books-quality price | $60/min |
| Researcher | 33 RP/min; 16 researchers finish the 1,765-RP tree in 3.4 min | $75/min |
| Engineer | +0.125 training speed; the 2nd/3rd/4th training slot at 12/24/36 heads | $90/min |

Diminishing returns are real: the 17th sales hire is worth 1.6× its wage, the 33rd 0.45×. Researchers have no use
after the tree today; proposal: after the tree, RP become **published papers** (+1 reputation target per 200 RP,
max +20 → base reach +0.06) — **not simulated**, which is why the bot's researchers are dead weight late.

---

## 6. Calendar

- **World clock (per server, shared, restart-proof)**: `Calendar.worldSeconds() = workspace:GetServerTimeNow() % 1200`;
  `hour = EmployeeConfig.hour(worldSeconds)` (unchanged 900 s day 08–18, 300 s night). Replaces the local
  `time = 54` (`StaffService:33`) and drives `Lighting.ClockTime` (`StaffService:329`), `CompanyHour`, the time
  sheet, trip departures and lunch. Same hour on every server, so a player can found the company in the evening or
  at night. Normal departures wait for 08:00–15:00 (worst case ~9.5 real minutes after a 15:00 start); the
  **scripted first CloudDesk pilot ignores the departure window** so the first-10-minutes beat does not depend on
  the clock (the sim started at 08:36, so this rule was not exercised).
- **Company calendar (per player, saved)**: `empire.calendar = {day, lastHour}` (default in `EmpireMath.new:12-17`,
  cleaned in `Template.migrate`, advanced in `EmpireService.tick:129`); `day` +1 each time the world
  clock passes 08:00 while the player is online (≈ `empire.seconds/1200`). All company timers count in
  **company seconds** (`empire.seconds`, persisted play time): trip `backAt`, lead expiry (3 days), loss cooldown
  (1 day), churn cooldown (2 days), vacation `untilDay`, sick days, retainer `renewAt` (3600 s). Offline nothing
  advances (no offline progress; honest and exploit-free).
- **Payroll**: wages accrue per second; the P&L shows one pay slip per company day (e.g. 64 staff at Startup Campus:
  "Day 4 payroll −$100,800" = 64 × $1,575 average).
- **Billing cycle** = `GAME_MONTH_SECONDS` = 3600 s = 3 company days; the UI says "per cycle (3 days)" instead
  of "per month". Subscription prices, API prices and retainers are per cycle (no economy change).
- **Hotel nights**: one per traveller per night (18:00–08:00) a trip spans: region trips 1, abroad 2.
- **Real UTC day** only for the daily login reward. Contracts (now pilots) and studio briefs use company days.
- UI wording: wages "per day" (not "per game month", e.g. `RecruitingService:367` template), prices "per cycle".
- Abroad is in the same time zone (simple and honest; world_map.md's 600-s shift needs a client-side clock).

---

## 7. AI models

1. **Product lines**: release target = line (developers / students / businesses / general). Utility −0.6 outside
   the line, so a model is strongest in its line; four lines are worth 1.71× one model, four clones 1.28×.
2. **Live cap** = lines of the stage (1/2/3/4/4). At the cap a release must name the model it replaces.
3. **Versions**: `ReleaseModel{replaces = id}` copies 90 % of the old model's users per segment and its organic
   word of mouth into the new model, then retires the old one (`retireModel` no longer wipes users that moved).
   Same-name models keep `versionFor`. Sim: 9–11 releases per run, 4–10 of them replace a predecessor.
4. **Ageing**: −0.15 utility per company day after 2 days live, max −0.6 (≈ 11 fit points). New versions reset it,
   so shipping matters; the casual bot refreshes a product older than 3600 s.
5. **Anti-clone**: company nest λ 0.15 + company-level reach (§3.1).
6. **Parallel training**: `PlayerData.trainings[slot]` (map), ONE job per slot, slots
   `min(stage.trainSlots, 1 + floor(avg O_eng/6))`, GPU throughput split equally among running jobs. Readers of
   `data.training` listed in models.md must move to the map (DATA_VERSION 6 migration wraps the old single job as
   slot 1). **Not simulated** (the bot trains one model at a time).
7. **Refinement fixed**: additive gain `(2 + 8q)·qualityMod/√(1 + iterations)` per core stat (no compounding),
   stats ≤ 99 and ≤ release stats + 12; the model **stays live** while its refinement runs (serving uses the old
   weights); it takes a training slot. Patch `r_refine` is applied in all runs (additive, ≤ 99); the bot does not
   refine, so the +12 cap and "stays live" are **not simulated**.
8. **B2B uses models too**: the best live model per client stat qualifies; specialists (coding focus for
   ByteWorks, reasoning focus for StudySpark) unlock clients a balanced model cannot.

Hooks: `AIModelService.releaseModel:459-490`, `retireModel:508-519`, `improveModel:397-423`, `finish:206-216`,
`startTraining:295-395`, `Types.TrainingState:57-72,101`, `EmpireMath.trainingRate:127-129`, `LabApp:126`.

---

## 8. Automation

| Runs automatically | Player decides | Player can step in |
|---|---|---|
| HR: shifts, lunch, vacation/sick planning (≤ 15 % per dept), desk/department assignment by seats, field duty, payroll | how many people per role (hire/fire), agency vs interview hires | night crew per department |
| Sales: leads, choosing the best qualifying model, pilot trips, reviews, renewals | which products exist (train, release line, price, marketing) | "Join the pitch": drive your own car to the client (+0.1 win chance, optional) |
| Travel desk: car from the fleet, hotel booking, flights, guest-house hosting | office upgrades, GPUs/cooling, research | pause an account / cancel a pilot |
| Ops staff: reception, kitchen, IT, facilities, fleet | data purchases (manual by default) | |
| Billing: subscriptions, retainers, rent, utilities, leases, lunches | | |

The assistant (`AssistantService.briefing:112-223`) gets three sections built only from real state:
**Today** (company day, hour, "41 of 64 at work, 4 on vacation, 1 sick, 2 on a trip to Ledger Finance (back
tomorrow 10:00, hotel 2 nights $280)"), **Customers** (pipeline: leads with what they need, pilots on the road,
accounts, $/min, next reviews, SLA capacity used), **Money** (P&L by category from the tagged ledger:
`EconomyService.spend/grant/applyFlow(session, amount, tag)` → `empire.ledger[day][tag]`, last 7 days).
Recommendation rules in priority order: "Founder HQ costs $25,000 = 4 min of profit — save?", "Ledger Finance
needs math 50, your best is 47", "SLA capacity full: Frontier Science is paused — buy GPUs", "Your Developer API is
3 days old (−0.3 appeal) — ship a new version", "Research desks full; next office adds 24", "Lunch capacity 145 <
216 present: morale 97 %".

---

## 9. Targets check (brief §5)

| Target | Result (casual = 5 seeds fresh + 4 late; opt = 2 runs) | Met? |
|---|---|---|
| ≥ $1–3k/min by minute 5–10 | min 5: **$2,483–3,341/min**; min 10: **$3,067–5,268/min** (all 11 runs) | yes |
| Clear first goal | scripted CloudDesk pilot signed at **4.3 min** (+$9k, +$300/min); "Out of the garage" quest | yes |
| "Office 2" ~25–40 min (= Startup Campus, old office 2) | casual fresh **18.9, 19.7, 30.9, 32.9, 34.5**; late **20.3, 32.4, 36.0, 37.1**; opt 17.5 / 20.7 | median 32.4, 3 of 9 casual early |
| "Office 3" ~70–100 min (Innovation) | casual **77.2–94.3**, late 76.6–106.6; opt 55.5 / 70.0 | yes (1 run at 107) |
| "Office 4" ~2.5–3.5 h (Global HQ) | casual **143–173 min**, late 153–193; opt 115 / 125 | yes (2 runs 143–145) |
| New garage stage short and sweet | ends at 8.1–8.3 min (opt late 10.0) | yes |
| Wages 25–45 % of revenue mid game (30–120 min) | casual median **28 %**: 28 of 45 samples in 25–45 %, 15 below (15–24 %), 2 above (47 %, 55 %); opt median 23 % | mostly; optimiser below band |
| No collapse | revenue rises in every run until ~120–180 min; the largest later fall is −27 % (late join: $59.4k at 120 → $43.1k at 180 min, rivals catching up after a 7B launch), then it recovers ($60.6k at 240); money at the report marks never below $604 | yes |
| No runaway | revenue stays at **$40–88k/min** for 180–240 min with 240 staff (the analysis' NPC-cap lever ran away to $1.41M/min); money at 240 min $0.95–5.0M (casual, 9 runs), $6.0–6.3M (opt) — late cash piles up with nothing left to buy (see risks) | bounded |
| Late joiner OK | server 60 min old: min 5 $2,530, min 10 $3,067, stages 8.3 / 36.0 / 82.0 / 163.3 (the NPC curve starts at 61 instead of 48) | yes |
| Every room has a job | §5.7 | design |

### 9.1 Casual (profile default) — `out_final_casual.txt`

| min | money $ | revenue $/min | cost $/min | wages $/min (share) | staff (R E C S) | office | best model | NPC best | B2B $/min (accounts) | live lines |
|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---:|
| 0 | 13,000 | 0 | 0 | 0 (-) | 0 (R0 E0 C0 S0) | 1 | - | 47.9 | 0 (0) | 0 |
| 5 | 20,061 | 2,682 | 505 | 315 (12%) | 4 (R1 E1 C1 S1) | 1 | s1b 43.8 | 58.0 | 300 (1) | 1 |
| 10 | 604 | 3,665 | 725 | 423 (12%) | 4 (R1 E1 C1 S1) | 2 | s1b 48.4 | 58.6 | 600 (2) | 2 |
| 20 | 4,457 | 5,566 | 1,062 | 513 (9%) | 4 (R1 E1 C1 S1) | 3 | s1b 48.4 | 59.2 | 850 (3) | 2 |
| 30 | 5,198 | 8,462 | 2,087 | 1,608 (19%) | 18 (R4 E5 C5 S4) | 3 | s500m 52.0 | 59.8 | 1,217 (4) | 2 |
| 45 | 15,040 | 10,403 | 4,681 | 4,203 (40%) | 51 (R13 E13 C13 S12) | 3 | s500m 52.0 | 60.5 | 1,217 (4) | 2 |
| 60 | 43,290 | 15,427 | 6,084 | 5,238 (34%) | 64 (R16 E16 C16 S16) | 3 | s1b 58.3 | 61.1 | 1,967 (5) | 2 |
| 90 | 27,333 | 35,551 | 11,389 | 8,442 (24%) | 104 (R26 E26 C26 S26) | 4 | s7b 71.4 | 62.2 | 4,900 (8) | 2 |
| 120 | 1,137,615 | 69,964 | 17,979 | 10,332 (15%) | 128 (R32 E32 C32 S32) | 4 | s7b 93.8 | 74.8 | 6,400 (9) | 3 |
| 180 | 1,174,119 | 72,757 | 26,364 | 19,188 (26%) | 240 (R60 E60 C60 S60) | 5 | s7b 103.8 | 91.3 | 15,133 (14) | 3 |

Stages: 2 at 8.3, 3 at 19.7, 4 at 84.3, 5 at 143.2 min. (240 min: $4.17M, $58,453/min, NPC 93.8.)
"cost" = running costs per minute (wages, ops, rent, utilities, food, fleet, serving, B2B serving, guest house).
"best model" = best trained (the "s1b 43.8" at minute 5 is a 1B model on too little data — the bot's choice).

### 9.2 Optimiser (profile opt) — `out_final_opt.txt`

| min | money $ | revenue $/min | cost $/min | wages $/min (share) | staff (R E C S) | office | best model | NPC best | B2B $/min (accounts) | live lines |
|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---:|
| 0 | 13,000 | 0 | 0 | 0 (-) | 0 (R0 E0 C0 S0) | 1 | - | 47.9 | 0 (0) | 0 |
| 5 | 13,490 | 2,483 | 358 | 315 (13%) | 4 (R1 E1 C1 S1) | 1 | s500m 43.1 | 58.0 | 300 (1) | 1 |
| 10 | 4,204 | 5,268 | 563 | 423 (8%) | 4 (R1 E1 C1 S1) | 2 | s500m 47.5 | 58.6 | 600 (2) | 2 |
| 20 | 5,725 | 6,703 | 1,085 | 738 (11%) | 7 (R2 E2 C2 S1) | 3 | s500m 47.5 | 59.2 | 850 (3) | 2 |
| 30 | 10,428 | 11,963 | 3,232 | 2,868 (24%) | 34 (R8 E9 C9 S8) | 3 | s500m 50.4 | 59.7 | 1,217 (4) | 3 |
| 45 | 71,132 | 24,827 | 5,834 | 5,238 (21%) | 64 (R16 E16 C16 S16) | 3 | s1b 58.9 | 60.5 | 2,750 (6) | 3 |
| 60 | 23,469 | 30,531 | 8,139 | 7,092 (23%) | 87 (R22 E22 C22 S21) | 4 | s1b 62.9 | 61.1 | 2,750 (6) | 4 |
| 90 | 1,377,888 | 51,755 | 12,596 | 10,332 (20%) | 128 (R32 E32 C32 S32) | 4 | s3b 86.8 | 76.8 | 5,567 (9) | 4 |
| 120 | 46,900 | 50,760 | 17,889 | 14,778 (29%) | 184 (R46 E46 C46 S46) | 5 | s3b 86.8 | 76.8 | 10,550 (12) | 4 |
| 180 | 3,672,854 | 72,772 | 22,421 | 19,188 (26%) | 240 (R60 E60 C60 S60) | 5 | s3b 96.4 | 86.4 | 23,883 (16) | 4 |

Stages: 2 at 8.3, 3 at 17.5, 4 at 55.5, 5 at 115.0 min. The optimiser runs 4 product lines and the full B2B
catalogue by 180 min. (240 min: $6.31M, $60,526/min.)

### 9.3 Joining a server that is 60 minutes old (casual, `--late 60`) — `out_final_late60.txt`

| min | money $ | revenue $/min | cost $/min | wages $/min (share) | staff (R E C S) | office | best model | NPC best | B2B $/min (accounts) | live lines |
|---:|---:|---:|---:|---:|---|---:|---|---:|---:|---:|
| 0 | 13,000 | 0 | 0 | 0 (-) | 0 (R0 E0 C0 S0) | 1 | - | 61.0 | 0 (0) | 0 |
| 5 | 14,222 | 2,530 | 327 | 225 (9%) | 3 (R1 E1 C1 S0) | 1 | s500m 44.2 | 61.3 | 300 (1) | 1 |
| 10 | 4,210 | 3,067 | 520 | 333 (11%) | 3 (R1 E1 C1 S0) | 2 | s500m 47.5 | 61.5 | 600 (2) | 1 |
| 20 | 5,074 | 4,518 | 1,388 | 1,143 (25%) | 13 (R3 E4 C3 S3) | 2 | s500m 47.5 | 61.8 | 850 (3) | 1 |
| 30 | 19,987 | 7,553 | 1,865 | 1,593 (21%) | 19 (R5 E5 C5 S4) | 2 | s500m 52.5 | 62.2 | 1,217 (4) | 2 |
| 45 | 8,659 | 10,254 | 3,248 | 2,808 (27%) | 33 (R8 E9 C8 S8) | 3 | s500m 52.5 | 62.7 | 1,967 (5) | 2 |
| 60 | 9,135 | 12,866 | 6,010 | 5,238 (41%) | 64 (R16 E16 C16 S16) | 3 | s1b 57.9 | 63.0 | 1,967 (5) | 2 |
| 90 | 30,793 | 34,631 | 11,225 | 9,387 (27%) | 116 (R29 E29 C29 S29) | 4 | s1b 74.0 | 64.0 | 5,833 (9) | 2 |
| 120 | 854,942 | 59,445 | 20,141 | 10,332 (17%) | 128 (R32 E32 C32 S32) | 4 | s7b 95.8 | 80.4 | 5,833 (9) | 2 |
| 180 | 123,840 | 43,109 | 25,385 | 19,188 (45%) | 240 (R60 E60 C60 S60) | 5 | s7b 95.8 | 85.8 | 15,133 (14) | 2 |

Stages: 2 at 8.3, 3 at 36.0, 4 at 82.0, 5 at 163.3 min. (240 min: $2.56M, $60,575/min.) Baseline for
comparison (today's code, `out_casual_late60.txt`): at most $7/min from the start.

### 9.4 Robustness (other seeds)

| Run | Founder HQ | Startup Campus | Innovation | Global HQ | rev min 5 / 10 | wage share 30/45/60/90/120 |
|---|---:|---:|---:|---:|---|---|
| casual seed 0 | 8.3 | 19.7 | 84.3 | 143.2 | 2,682 / 3,665 | 19/40/34/24/15 % |
| casual seed 1 | 8.3 | 30.9 | 77.2 | 155.9 | 2,885 / 4,095 | 28/25/31/31/20 % |
| casual seed 2 | 8.2 | 34.5 | 94.3 | 173.0 | 3,341 / 3,850 | 24/35/55/19/28 % |
| casual seed 3 | 8.3 | 18.9 | 82.1 | 144.6 | 2,692 / 3,920 | 26/29/30/28/24 % |
| casual seed 4 | 8.1 | 32.9 | 80.0 | 164.8 | 2,955 / 3,325 | 23/30/28/31/21 % |
| late 60, seed 0 | 8.3 | 36.0 | 82.0 | 163.3 | 2,530 / 3,067 | 21/27/41/27/17 % |
| late 60, seed 1 | 8.3 | 37.1 | 76.6 | 152.8 | 2,707 / 4,109 | 31/24/42/29/18 % |
| late 60, seed 2 | 8.3 | 32.4 | 106.6 | 192.9 | 2,586 / 3,809 | 26/35/47/33/41 % |
| late 60, seed 3 | 8.3 | 20.3 | 80.2 | 156.6 | 2,596 / 3,989 | 19/38/32/28/20 % |
| opt | 8.3 | 17.5 | 55.5 | 115.0 | 2,483 / 5,268 | 24/21/23/20/29 % |
| opt, late 60 | 10.0 | 20.7 | 70.0 | 124.8 | 1,857 / 4,224 | 23/23/24/12/18 % |

### 9.5 What is simulated, injected, or not simulated

- **Real code, patched** (`patches_realism.luau`): stage table, start money, GPU slots/thermal, time sheet,
  workforce day average, bonuses/wages/fees/fleet count, market (nest, lines, pools, reach, ageing, FIT 18),
  removal of the lease auction, NPC ceiling/catch-up/price floor, running costs in `EmpireService.tick`,
  studio per company day, additive refinement.
- **New logic injected in the sim** (`realism.luau`, would become StaffService feed / DealService / GuestHouse):
  time-sheet workforce report with seats, absence and morale; the whole deal pipeline incl. trip time, crew
  availability, fleet cars, fuel/flight/hotel/per-diem cash flows, retainers, SLA capacity, reviews and churn;
  guest-house income/cost terms and hosted pilots. No car drives and no guest sleeps — only time and money.
- **Not simulated**: parallel training slots, refinement behaviour (cap, stays live), room quality Q, ops-post
  side effects (IT, barista, facilities, reception, fleet manager, data-hall), night crew, published papers,
  individual vacation/sick rolls (expectation 10 % used), training slowdown from SLA load, players sharing the
  market (the sim has one player), "Join the pitch".

---

## 10. Risks and what to cut first

**Risks**
1. **Several players share one market.** With 6–12 strong companies each player's consumer share shrinks (the sim
   has one player). Mitigation (not simulated): scale line pools with founded player companies,
   `pool·(0.7 + 0.3·n)` capped at n = 6; B2B is per player, so a crowded server still earns from deals.
2. **The 7B spike.** Between ~90 and ~130 min a 7B model at 90–105 overall outruns the NPCs (gap 15–20 for a few
   cycles) and revenue jumps 2× before rivals catch up; the s7b overall > 99 comes from today's model math
   (Frontier +6, Architecture +4, deep recipe ×1.25). If it feels too strong: cap core stats at 99 in
   `EmpireMath.boostStats` (one line).
3. **Late cash has nothing to buy.** $0.95–6.3M at 240 min. Needs late sinks the brief already wants: Robux-free
   prestige items (second campus/city office, private jet for abroad trips, guest-house upgrades) — design work.
4. **Researchers are useless after the tree** until "published papers" (§5.8) or another repeatable research use exists.
5. **Bot noise.** Single runs are chaotic (a 1B model on thin data at minute 2 changes everything); conclusions use
   11 runs, not one. A human may play slower than the bot in the first minutes (the bot clicks every second).
6. **Wage share for optimisers** sits at ~22 % (below 25 %): good players will find staff cheap. Acceptable, or
   raise wages 10 % at stages 4–5 only.
7. **DATA_VERSION 6 + new profile fields** touch five places at once (cleanProfile, profilesConsistent,
   profileSignature, StaffAssignment.profile, Rig.Profile) and the training map; a rolling update can kick players
   on old servers (data_ui.md pitfall 5).
8. **Evening/night start**: later pilots wait for office hours (up to ~9.5 real minutes); only the scripted first
   pilot is exempt. The app and the studio pay meanwhile.
9. **Snapshot size**: `empire.deals`, `trips`, `ledger` must be omitted from unchanged deltas like `staffProfiles`.
10. **Minute 5 is lower than today's peak.** Today's code pays $8,678/min at minute 5 and then collapses (4,611 at
    10, 1,906 at 20, 93 at 45); this design pays $2,682 at 5 and keeps growing (3,665 / 5,566 / 10,403). If testers
    find minutes 2–6 slow, raise the developer and student pools by 30 % (`poolDev`, `poolStud`) — those lines carry
    the first model — and re-run the sim; or give the scripted CloudDesk pilot a shorter first trip.

**Cut order if time runs out** (each cut leaves the curve of §9 essentially unchanged, because none of these carry more than ~1 % of income or cost in the sim):
1. Night crew toggle, ops-post side effects, room quality Q (not in the sim anyway).
2. Published papers and the parallel-training map (keep one training slot; the sim never used more).
3. Guest House building (keep it as a stage-3 line item; < 1 % of income).
4. Review visits and churn (accounts simply renew; trips then only for pilots; churn never fired in the sim).
5. Abroad trips as flights (treat them as long region trips; travel is < 1 % of costs, but the airport story is lost).
6. Never cut: the market fix (nest, lines, NPC ceiling), the time-sheet workforce, wages/fee rebalance, the
   Garage stage + migration, and city/region pilots + retainers — together they carry the curve in §9.
