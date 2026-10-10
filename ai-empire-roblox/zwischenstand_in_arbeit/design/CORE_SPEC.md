# AI Empire: CORE_SPEC (final core company logic)

This is the binding core design for the company logic redesign of `LOGIC_BRIEF.md`. Subsystem specs (calendar/HR, customers and trips, guest house, world map, staff life, models, shop, tech/network/save) must use the numbers and functions in this document. Section 11 lists them per subsystem.

**How every number was produced.** Each number is one of three things:
- a value chosen here and played by the economy simulator;
- a simulator result (file named);
- marked **not simulated**, with its expected size.

The simulator loads the REAL game services from `work/src` (snapshot taken 2026-10-04 05:53; the economy files are identical to the 20:25 snapshot the designs used) inside the headless mock, applies this design as in-memory patches and plays greedy bots one tick per second.

**Evidence folder:** `scratchpad/agents/design_final/economy/`

| File | What it is |
|---|---|
| `patches_final.luau` | The whole design as find/replace patches on the real sources. Every number is in the table `P` at the top. Each anchor is asserted, so a patch can never miss silently. |
| `proposed/CompanyOps.module.luau` | NEW shared module (~470 lines, `--!strict`): calendar, time sheet, HR need, B2B pipeline with trips/hotel/flights, guest house, running costs, serving capacity, company jet. It is loaded by the simulator as `ReplicatedStorage.Shared.CompanyOps` and is the implementation reference. |
| `proposed/MarketMath_tick.luau` | The replacement for `MarketMath.tick` (+ `agePenalty`, `lineOf`, `playerUtility`). Also loaded as real code. Both proposed modules type-check with 0 diagnostics (`luau-lsp analyze --platform=roblox`, `--!strict`) inside a copy of today's `ReplicatedStorage` with the new `MarketConfig` constants (`agents/design_final/lsp/`). |
| `sim_final.luau` | The bot: casual / opt profiles, auto-HR, Save mode, Recommended/auto price, several companies per server (`--players`), shocks, slow players (`--think`). |
| `suite.sh` | The verification suite: 59 runs (56 of this design, 2 of today's game, 1 clone test), output `out_V_<label>.txt`. |
| `agg.py` | Turns the outputs into the tables of section 9. |
| `out_V_*.txt` | The final results quoted in this document. Other `out_*.txt` files in the folder are tuning history from before the final parameters. |

Reproduce one run with `cd agents/design_final/economy && ../../../tools/luau sim_final.luau -a --profile default --minutes 180`, or run `./suite.sh` for everything (about 1.5 hours on 4 cores).

Paths below are relative to `work/src` unless they start with `agents/` or `design/`. A hook is written `File:function` plus a line number in today's `work/src`.

---

## 0. Decision record

### 0.1 Base design and grafts

**Base design: `core_robust.md`.** Combined judge totals:
- robust 7.63 + 7.63 = **15.26**
- realism 7.78 + 7.40 = 15.18
- clarity 7.33 + 6.58 = 13.91

Robust supplies the skeleton: server-independent NPC band, stage reach caps, company nest, `CompanyOps` as one pure module with `applyFlow` categories, hash-based absences, flat hiring fees, the studio stall fix, safety rules and fixed migration clamps.

| Graft | From | Where in this spec |
|---|---|---|
| Product-line penalty (−0.6 utility outside the release line), live lines 1/2/3/4/4 | realism | 3.1, 7 |
| Scripted first CloudDesk pilot: founder drives the Founder's Hatch, ignores the departure window | realism | 1, 3.2 |
| Three trip tiers city / region / abroad with fuel, hotel, flights, per diem | realism | 3.2, 4 |
| Guest house hosts every second region/abroad pilot | realism | 3.5 |
| Time sheet TS(hour), lunch-capacity morale | realism | 5 |
| Growth & Sales are the field staff (no 5th role) | realism | 5, 8 |
| "Next goal" HUD bar with ETA, Save mode, sign on the fenced site | clarity | 8 |
| Automatic HR within a wage budget (25/40/55 %, default 40 %) | clarity | 8 |
| Serving capacity and waitlist ("12,400 waiting - buy GPUs") | clarity | 3.1 |
| Recommended price as default and auto-pricing | clarity + robust | 7, 8 |
| Lab levels as a repeatable researcher sink; all stats capped at 99 | clarity | 7 |
| Money shown per game day | clarity | 6 |
| Guest house slightly net positive (+$320/day) | robust | 3.5 |

**Rejected:**
- realism's server-coupled NPC ceiling;
- clarity's market numbers (FIT 20, pools ×0.5, NPC asymptote 72);
- robust's 5th role (account executive);
- robust's `PLAYER_RIVAL_WEIGHT = 0` (replaced by a documented 0.15).

### 0.2 Must-fix items and their status

Every must-fix of both judges, with its status. "Sim" means it is verified in section 9.

| # | Must-fix | Resolution | Status |
|---|---|---|---|
| 1 | NPC ceiling coupled to the best player on the server | NPC band is fixed: start ×1.2, at most 64 per stat, API floor $1. It never reads players. A veteran next to a newcomer is simulated (runs D_*). | fixed, sim |
| 2 | Overall above 99 | `EmpireMath.boostStats` caps every core stat at 99; refinement caps at 99; Lab levels add to `core` before the cap. | fixed, sim (best model 99.0 max) |
| 3 | Income or net falls after the Global HQ move | Net per minute 5-20 / 20-40 / 40-60 min after the move is shown per run in 9.5. HR need caps keep stage-5 hiring productive. | sim, see 9.5 |
| 4 | Startup Campus bought with 4 staff | Price is $100k. Auto-HR keeps hiring in Save mode until half the desks are full. Staff at the move: 9.5. | fixed, sim |
| 5 | Minutes 5-10 pay less than today ($7,007/min) | Today's game in this sim pays $6,867/min in minutes 5-10. The design pays $7,707-9,852 (casual, 12 runs) and $9,853 in the main casual run ($6,453 recurring). | fixed, sim |
| 6 | Garage can be skipped | Leaving the garage needs the first signed client **and** $27,000. Garage times: 9.4. | fixed, sim (33/36 runs in 8-12 min; 3 runs ≤ 0.9 min short, see 9.6) |
| 7 | Several live models give almost nothing | Line penalty + nest: 4 matching specialists = ×1.47-1.51, 4 clones = ×1.08. The one-line probe is in 9.7. | fixed, sim |
| 8 | MIGRATIONS[5] nil guard | Guarded transform (2.4). | spec |
| 9 | Clarity runaway | Clarity market numbers not used. Opt plateau: 9.2. | sim |
| 10 | Unsimulated multiplayer, slow player | 5 multi-company runs (D_*), 2 slow-player runs (`--think 30`) | sim |
| 11 | Late money sink | Lab levels (≈$1.09M in total) and the company jet ($900k + $8,500/day) are simulated. A branch office and cosmetics are spec only. | partly sim |
| 12 | Robust: one seed only | 4 seeds × 3 start hours × 3 profiles (36 runs) | sim |
| 13 | 5 product slots vs 4 lines | Lines are 1/2/3/4/4; no 5th slot. | fixed |
| 14 | Opt spike/fall after Global HQ | Opt revenue and net after the move: 9.2, 9.5. | sim |
| 15 | 5th role touches 13 files | No 5th role. Growth & Sales hold `fieldReps` field duty (8.1). | fixed |
| 16 | `PLAYER_RIVAL_WEIGHT=0` is a product change | Set to **0.15** (all other players together weigh 0.15 of one company). Runs at 0 / 0.15 / 0.3 are in 9.7. | decided, sim |
| 17 | Thin mid-game cash, no shock test | Two shock runs (outage at 45 min, −90 % cash at 60 min) and the unpaid-leave rule (8.3) | sim (the rule itself is spec) |
| 18 | `Template.migrate:218` clamps the office to 1..4 | Clamp becomes `1..#EmpireConfig.OFFICES` (2.4). | spec |
| 19 | Reach stacking per model | Reach is computed per company and segment: max hype + Σ organic, capped once (3.1). | fixed (real code in sim) |
| 20 | Snapshot bandwidth | `LAZY` paths and a byte budget (11.8). | spec |
| 21 | Parallel training risk | v1 ships 1 slot. DATA_VERSION 6 reserves `trainings` (7.6). | spec |
| 22 | Bots are lower bounds | Slow-player runs plus the goal bar and Save mode. Stage targets are read against both bots. | sim |

---

## 1. Core loop and the first 10 minutes

### 1.1 The game in one paragraph (for a 13-year-old)

You start an AI company in your garage with $10,000, an old laptop and room for five people. You train an AI model and launch it as an app or an API. People pay every month, and apps pay for every word your AI writes. Your friend at CloudDesk wants to try your AI, so you drive over in your own car. When they sign, they pay you every day. With the money you:
- hire people;
- buy GPUs, so your servers can handle more users;
- train better models.

When you have signed your first client and saved $27,000, you move out of the garage into a real headquarters. Every bigger building gives you more desks, more product lines, bigger clients further away (a hotel night in Business City, a flight to Port Meridian) and more servers. It also costs more rent. Your team works 08:00-18:00, eats the chef's lunch, takes holidays and goes home at night, while your servers keep earning. Your models get old, so you keep shipping new versions.

### 1.2 First 10 minutes, minute by minute

Casual bot, day start 08:36, file `out_V_walk_h86.txt`. The bot clicks every second, so a human is slower: the goal bar shows the same steps.

| Time | What the player sees | Economy |
|---|---|---|
| 0:00 | Spawns at the **Garage Lab** next to the plaza. Inside: 5 team desks, the glazed founder corner, a 3-blade GPU shelf, coffee machine, sofa, WC. The rest of the plot is a fenced site with a sign: "Future HQ of Nimbus Labs — first client + $27,000". Goal bar: **"Train your first AI"**. | Cash $11,000 ($10,000 start + $1,000 daily login). Quest "Open the doors" +$1,200, "Feed the model" +$1,800. |
| 0:00-1:18 | Train Nova1 (100M) on the laptop. | $1,280 training. |
| 1:18 | **Release** into the Consumer Chat line. The Recommended price is pre-selected. | Quests +$2,500 and +$3,000. **First $ at 1:18.** |
| 1:21 | Phone: "Your friend at CloudDesk wants a pilot." The founder's Hatch drives out (the scripted pilot leaves even outside office hours). | City trip: 240 s (0.2 day), $80 (fuel $30 + per diem $50). |
| 1:42 | HR hires 3 people (engineer, curator, researcher). They walk in and sit down. Research "Parallel Training" starts. | Flat fees $1,200 / $800 / $1,000. Wages $531/min. Quest +$2,500. |
| 2:00 | 5,000 users. Three consumer GPUs fill the garage rack (3 slots). | Quests +$10,000 and +$1,500. |
| 2:06-3:00 | Nova2 (500M) trains. "Nova2 replaces Nova1, users move over." | 90 % of users migrate. |
| 2:48-3:36 | Three studio briefs delivered. | +$1,750 / +$3,250 / +$4,000 |
| 5:00 | | **$3,368/min** revenue |
| 5:21 | **"CloudDesk signed! Pilot +$9,000, then $9,000 per day."** The founder drives straight on to ByteWorks. | +$450/min recurring |
| 6:00 | Nova3 replaces Nova2. | |
| 8:00 | Founder at ByteWorks: "trust 92 %", drives again. | |
| 10:00 | Goal bar: "Founder HQ $27,000 — about 0 min". | **$6,898/min** revenue |
| 10:12 | **Out of the garage.** The site becomes Founder Headquarters. 8 operations staff arrive (reception, security, facilities, IT, barista, chef, kitchen team, fleet). A second product line opens; the Developer API launches at 10:24. | $27,000; quest +$5,000. |

The same casual bot with a 16:53 start (`out_V_main_casual.txt`, night after 100 s) leaves the garage at 7.5 min. Over the 12 casual seed × hour runs the garage lasts 7.5-10.9 min; over all 36 runs 7.1-11.1 min (9.4).

---

## 2. Office stages

### 2.1 Stage table

`EmpireConfig.OFFICES` gets 5 entries. Stage = office index, and plan tier = stage − 1 via `Plan.tierForOffice` with `Plan.OFFICE_TIER_OFFSET = 1`.

| | 1 Garage Lab (**new**) | 2 Founder HQ (old T1) | 3 Startup Campus (old T2) | 4 Innovation Campus (old T3) | 5 Global AI HQ (old T4) |
|---|---|---|---|---|---|
| Plan tier (building) | 0 | 1 | 2 | 3 | 4 |
| Price | start | **$27,000** + first signed client | **$100,000** | **$380,000** | **$1,900,000** |
| Hired staff cap | 5 | 24 | 64 | 128 | 240 |
| GPU slots `HardwareConfig.slots` | 3 | 6 | 12 | 24 | 48 (×1.5 with Distributed Cluster → 72) |
| Thermal budget per cooling level | 10 | 20 | 40 | 60 | 80 |
| Market reach cap `STAGE_REACH` | 0.25 | 0.25 | 0.30 | 0.40 | 0.55 |
| Brand reach `BRAND_REACH` (added to base reach) | 0 | 0.02 | 0.05 | 0.09 | 0.15 |
| Live product lines `PRODUCT_SLOTS` | 1 | 2 | 3 | 4 | 4 |
| B2B client slots | 2 (founder only) | 4 | 7 | 10 | 14 |
| Field reps needed `ceil((slots−2)/2)` | 0 | 1 | 3 | 4 | 6 |
| Farthest trip | city | city | region (City Hotel night) | abroad (Port Meridian) | abroad |
| Operations posts (automatic, paid) | 0 | 8 | 12 + 2 guest house | 14 + 2 | 16 + 2 |
| Upkeep: rent + utilities per game day | $300 | $2,500 | $9,000 | $24,000 | $48,000 |
| Lunch per person per game day | $6 (pizza) | $8 (chef) | $8 | $8 | $8 |
| Kitchen capacity (lunches/day) | pizza | 120 | 145 | 205 | 235 |
| Base research points/s | 0.10 | 0.15 | 0.30 | 0.60 | 1.00 |
| Training slots (v1 / v2) | 1 / 1 | 1 / 1 | 1 / 2 | 1 / 3 | 1 / 4 |
| Guest house (12 rooms) | – | – | yes (`Plan.HOTEL_MIN_TIER = 2`) | yes | yes |
| Company jet purchasable | – | – | – | yes ($900k) | yes |

Price hook: `EmpireService.upgrade:80`. The garage gate is new and returns `{ok=false, err="FIRST_CLIENT"}` when `e.office == 1 and e.contractsCompleted < 1`. The goal bar shows it as "Sign your first client".

### 2.2 What each stage unlocks

| Stage | Departments and rooms that start working | Revenue streams | Fleet and travel | Other |
|---|---|---|---|---|
| 1 Garage Lab | one shared lab (5 desks, any role), the founder corner, the assistant's desk, a 3-slot GPU shelf, pizza | 1 product line, studio briefs, city clients CloudDesk / Paper Studio / ByteWorks sold by the **founder** (max 2 accounts) | the founder's own car (owned, no lease) | no operations staff, no lift, no research rooms (points still accrue at 0.10/s) |
| 2 Founder HQ | all 9 tier-1 departments, café + kitchen (chef → lunch → morale), reception, gym/sauna (half wellness), data hall with 6 slots | 2 lines, 4 client slots (Pixel Games, StudySpark, North Logistics, Civic Support open) | 1 leased car for the first Growth & Sales field rep ($100/day), B1 garage and fleet office | 8 paid operations posts, HR plans vacations, applicants arrive at reception |
| 3 Startup Campus | Product Studio, Platform, 2nd datalab, full wellness, People & Company (HR) | 3 lines, 7 slots, **region clients** (PixelForge, Ledger Finance, Orbit Games, Atlas Search: day workshop in Business City + City Hotel night) | 3 field cars | **Guest house** opens (12 rooms, hosts every 2nd region/abroad pilot), night shift toggle available |
| 4 Innovation Campus | research floor (research desks 2 → 23), 2nd evaluation lab, hardware lab, labs | 4 lines, 10 slots, **abroad client** Helix Research (Port Meridian via the airport, flights + 2 nights), Delta Robotics, Nova Logistics, Mosaic Worlds | 4 field cars; company jet purchasable | all 16 operations posts staffed |
| 5 Global AI HQ | 57 research + 28 evaluation desks, 2nd control room, Platform Ops, Cluster Control, 48 GPU slots | 14 slots, frontier clients Orbit Systems, Nova Infrastructure, Frontier Science ($105k-180k per day) | 6 field cars | 2 extra operations staff on a night rota (security + IT) |

### 2.3 The Garage Lab (plan tier 0)

Already built by the buildings package:
- `Plan.GARAGE_LAB` x 60..112, z −118..−78;
- rooms G0_LAB (5 desks), G0_FOUNDER (1 desk), G0_ASSIST, G0_WC, G0_PORCH;
- fenced construction site `Plan.CONSTRUCTION`;
- car spot `Plan.GARAGE_STAGE_SPAWN`;
- generators `RoomKitsGarage` and `HeadquartersDesign:58` (`GarageStage` attribute).

This spec fixes its placeholders (`BuildingPlan:25-30`):

| `Plan.GARAGE_STAGE` field | Value | Meaning |
|---|---|---|
| `desks` | 6 | founder desk + 5 team desks |
| `staff` | **5** | hired people that fit = `EmpireConfig.OFFICES[1].staff` |
| `blades` | **3** | lit GPU blades = `HardwareConfig.slots` at stage 1. More blades may be built and shown dimmed ("locked until Founder HQ"). |

**Who works there:** the founder (player), up to 5 hires of any role (desks `Role=any`) and the executive assistant at G0_ASSIST, who greets visitors. There are no operations staff, so the founder orders pizza ($6 per person per day).

**The site sign** (a SurfaceGui on the hoarding) shows the goal-bar text for stage 2: "Future HQ of ⟨company⟩ — first client ✓/✗ — $x / $27,000".

### 2.4 Migration of old saves (office index +1)

- **Version and transform.** `GameConfig.DATA_VERSION` 5 → 6. `Template.MIGRATIONS[5]`:
  ```lua
  MIGRATIONS[5] = function(d)
      local e = d.empire
      if typeof(e) ~= "table" then return end
      if d.company then
          e.office = math.clamp(math.floor(tonumber(e.office) or 1) + 1, 2, 5) -- old tier k -> stage k+1 (same building)
      else
          e.office = 1 -- never founded: start in the garage
      end
      d.trainings = if typeof(d.trainings) == "table" then d.trainings else {} -- reserved for slots 2..4 (7.6)
  end
  ```
- **Clamps.** `Template.migrate:218` changes from `math.clamp(...,1,4)` to `math.clamp(..., 1, #EmpireConfig.OFFICES)`. Without this, migrated tier-4 saves fall back to stage 4.
- **Constants.**
  - `Plan.OFFICE_TIER_OFFSET` 0 → 1 (`BuildingPlan:136`).
  - `NPCService.init:66` `d.empire.office=2` → `3`, so NPC labs keep 12 GPU slots and thermal 40.
- **Office-index users** (grep `empire.office`, `OFFICES[`):
  - use `Plan.tierForOffice`:
    - `PlotService.refresh:90-91` compares the `OfficeTier` attribute with the **raw** office index today;
    - `StaffAssignment:53`, `HeadquartersDesign:49` already convert;
    - `VehicleService` (garage spawn at tier 0 = `GARAGE_STAGE_SPAWN`);
    - `LiftService` (no lift at tier 0);
    - `DoorService`, `FacilityService`, `BuildingStateService`, `RecruitingService` visitor routes, `AssistantService`;
  - stay on the office index: `HardwareConfig.slots/thermal`, `EmpireMath.bonuses.points`, `EmpireService.upgrade/hire`, `MarketConfig.STAGE_REACH/PRODUCT_SLOTS`, `CompanyOps.STAGES`;
  - `AdminService:22,30,157,183,191,197`: commands `stage1..stage5` set the office index; `tier0..tier4` stay as building-tier aliases through `Plan.officeForTier`;
  - `EmpireApp`/`CampusApp` office tab lists 5 stages.
- **Starting money.** `GameConfig.START_MONEY` 25,000 → **10,000**. It only affects `Template.new`, i.e. new saves.
- **Quests** (`EmpireConfig.QUESTS`):
  - "Out of the garage" (`office` ≥ 2): desc becomes "Move from the garage into your first HQ."
  - "Reliable supplier": "Sign three business clients." It counts `contractsCompleted`, which the B2B pipeline increments.
  - Migrated old tier-1 saves may claim the $5,000 once; that is harmless.
- **Old fields.**
  - `empire.contracts` (UTC days) is kept but ignored.
  - `empire.customers` / `businessRevenue` stay as empty compatibility fields: the lease auction is removed.

---

## 3. Income sources

### 3.1 Consumer and API market (fixed)

**Hooks:**
- `MarketMath.tick` is replaced by `agents/design_final/economy/proposed/MarketMath_tick.luau`;
- `MarketMath.fit` gets a soft cap; `MarketConfig` gets new constants;
- `MarketService.entry:48-51` adds `target`, `player = not s.isNPC`, `company = s.userId`;
- `MarketService.tick:184` passes `opts = {stage, capacity, reachCap}`;
- the `businesses` table `:20` becomes empty and the auction is removed.

For segment *s* (developers, students, businesses, consumers), live player model *k*, NPC model *n*:

1. **Fit with a soft cap:** `fitEff = fit` if fit ≤ 75, else `75 + 0.35·(fit − 75)` (`MarketMath.fit`).
2. **Utility:**
   ```
   u_k = (fitEff_k − 50)/FIT_SCALE − sens_s·price_k/norm
         − LINE_PENALTY·[lineOf(target_k) ≠ s]
         − AGE.maxFit·min(1, vage_k/AGE.full)/FIT_SCALE
   ```
   with `FIT_SCALE = 30`, `LINE_PENALTY = 0.6`, `AGE = {maxFit = 8, full = 3600}`.
   - `lineOf`: developers → developers, students → students, businesses → businesses, general → consumers.
   - `vage` = seconds since the model's last version (release or refinement).
3. **Company nest** (one company = one nest, λ = `NEST_LAMBDA` = 0.05):
   - `IV = u_max + λ·ln Σ_k e^{(u_k − u_max)/λ}`
   - `den = e^{outside} + Σ_n e^{u_n} + (PLAYER_RIVAL_WEIGHT/C)·Σ_c e^{u_best,c} + e^{IV}`
     - C = number of other founded player companies;
     - u_best,c = the best utility of company c in this segment;
     - `PLAYER_RIVAL_WEIGHT = 0.15`.
   - `share_k = e^{IV}/den · e^{u_k/λ}/Σ_j e^{u_j/λ}`.
4. **Company reach:**
   ```
   reach_s = clamp(base(rep) + BRAND_REACH[stage] + max_k hype_k·e^{−age_k/600} + Σ_k organic_k,
                   0, min(0.9, STAGE_REACH[stage], reachCap))
   reachCap = min(STAGE_REACH[stage], 0.20 + 0.012·O_growth,office)   -- CompanyOps.reachCap
   ```
   Each model's organic drifts toward `0.6·share_k`, so the sum follows the company share. Launches do not stack.
5. **Target users:** `pool_s·POOL_SCALE·reach_s·share_k`.
   - Pools: developers 250,000, students 375,000, businesses 60,000, consumers 700,000; `POOL_SCALE = 1.5`.
   - `REPUTATION.userScale` = 500,000 (was 2,000,000).
6. **Serving capacity** (`CompanyOps.capacity`), in "500M-model users":
   ```
   capacity = max(0, throughput·thermal − reservedB2B)·15,000·(1 + 1.0·(1 − e^{−O_eng/20}))
   load     = Σ target_k·SERVE_UNITS[size_k]     -- SERVE_UNITS: 100M 0.5, 500M 1, 1B 1.4, 3B 2.2, 7B 3
   served   = min(1, capacity/load)
   ```
   - Users ease toward `target·served` (rise 40 s, fall 120 s).
   - `waitlist = Σ target·(1 − served)` is published in `live.waitlist`, `live.capacity`, `live.load`.
7. **Revenue per second (unchanged per user):** `users·sub/3600` or `users·tokens/1e6·api/3600`, multiplied by:
   - marketing `1 + 0.4·(1 − e^{−O_growth,office/10}) + 0.15·[Global Distribution]` (`EmpireMath.bonuses.revenue`);
   - the market cycle (`MarketService.tick:186`, ×1.0-1.2, mean ×1.08);
   - (Investor pass only) `ShopConfig.INVESTOR_MULTIPLIER` = 1.10, applied after shares.
   - Serving cost: tokens × size.serveCost × `bonuses.serving`. Power: `throughput·0.025 $/s` while anything is live (unchanged).

**NPC rival fix** (`NPCService`):
- Each of the 3 labs starts at its s500m stats ×1.2, capped at 64 per stat. Overall is 55.9 at server start.
- Each training adds `(2+6q)/√(1+it)` but never above 64 (`NPCService:86`). Overall reaches 61.8 after about 10 minutes and stays there on every server, forever.
- The API price floor is $1.00 (was $0.25, `NPCService:119`).
- No player data is ever read. A newcomer and a veteran meet the same rivals.

**Anti-clone rule.** One live model per product line (`releaseModel` replaces the line's live model), the company nest (a copy adds +4 %) and shared reach.

Clone test on the real patched `MarketMath` (`out_V_E_clonetest.txt`: s1b models, reputation 30, 1 hour, vs the 3 NPC labs):

| Live set | Stage 3 | Stage 5 |
|---|---|---|
| 1 model (creative, consumer line) | 8,147 $/min = 1.00 | 11,373 $/min = 1.00 |
| 2 / 3 / 4 identical clones, same line | ×1.04 / ×1.07 / ×1.08 | ×1.04 / ×1.06 / ×1.08 |
| 2 lines (consumer creative + developer coding) | ×1.18 | ×1.17 |
| 4 lines, same balanced weights | ×1.32 | ×1.30 |
| **4 lines, matching specialists** | **×1.51** | **×1.47** |

For comparison, today's code gives ×1.94 / ×4.44 / ×7.88 for 2 / 5 / 10 clones (robust `out_clonetest_baseline.txt`). A clone is worthless; a specialist per line pays ×1.47-1.51.

### 3.2 B2B clients: sales pipeline → trips → daily retainers

**Hook:** `CompanyOps.step(session, dt, Economy, clock)`, called from `EmpireService.tick` right after wages (`:163`). It replaces:
- `EmpireService.deliver` (daily contracts, `:100-116`);
- the server-wide lease auction (`MarketService.tickGlobal`, `businesses`).

Clients are per player, so there is no race between players.

**Catalogue** `CompanyOps.CLIENTS`. Retainers are $ per game day. Tokens are M tokens per billing month; together they reserve compute. Every name exists as a building in `CityPlan` CLIENTS.

| Client (id) | Needs | Stage | Retainer/day | Tokens | Trip | Building |
|---|---|---|---:|---:|---|---|
| CloudDesk (helpdesk, **scripted first**) | reliability ≥ 24 | 1 | 9,000 | 40 | city | downtown |
| Paper Studio (paper) | creativity ≥ 30 | 1 | 9,000 | 50 | city | downtown |
| ByteWorks (code) | coding ≥ 36 | 1 | 13,500 | 70 | city | downtown |
| Pixel Games (pixel) | coding ≥ 40 | 2 | 13,500 | 90 | city | downtown |
| StudySpark (study) | math ≥ 40 | 2 | 13,500 | 90 | city | downtown |
| North Logistics (north) | reasoning ≥ 42 | 2 | 15,000 | 100 | city | downtown |
| Civic Support (civic) | reliability ≥ 46 | 2 | 18,000 | 120 | city | downtown |
| PixelForge (creative) | creativity ≥ 48 | 3 | 24,000 | 160 | region | downtown + City Hotel |
| Ledger Finance (ledger) | math ≥ 50 | 3 | 27,000 | 180 | region | downtown + City Hotel |
| Orbit Games (orbitgames) | coding ≥ 52 | 3 | 30,000 | 200 | region | downtown + City Hotel |
| Atlas Search (atlas) | knowledge ≥ 55 | 3 | 36,000 | 240 | region | downtown + City Hotel |
| Delta Robotics (delta) | reasoning ≥ 60 | 4 | 45,000 | 300 | region | downtown + City Hotel |
| Nova Logistics (enterprise) | reliability ≥ 62 | 4 | 54,000 | 360 | region | downtown + City Hotel |
| Mosaic Worlds (mosaic) | creativity ≥ 65 | 4 | 63,000 | 420 | region | downtown + City Hotel |
| Helix Research (helix) | math ≥ 70 | 4 | 78,000 | 520 | abroad | Port Meridian tower |
| Orbit Systems (frontier) | reasoning ≥ 75 | 5 | 105,000 | 700 | abroad | Port Meridian tower |
| Nova Infrastructure (nova) | coding ≥ 80 | 5 | 135,000 | 900 | abroad | Port Meridian tower |
| Frontier Science (science) | reasoning ≥ 86 | 5 | 180,000 | 1,200 | abroad | Port Meridian tower |

All 18 together pay $868,500/day. The 14 best (the stage-5 slot cap) pay $823,500/day = **$41,175/min**, which is the hard B2B ceiling.

**Pipeline**, every tick, fully automatic:

1. **Eligible lead:** `office ≥ client.stage`, the trip tier is allowed at this stage, and the best live model has `stats[stat] ≥ minimum`.
2. **Who sells:**
   - The **founder** sells city clients and holds ≤ 2 accounts (`FOUNDER_ACCOUNTS`).
   - **Field reps** = Growth & Sales people on field duty, `min(heads, ceil((slots − 2)/2))`. Each holds ≤ 2 accounts (`ACCOUNTS_PER_REP`) and makes one trip at a time.
   - The account limit is `min(stage slots, 2 + 2·reps)`.
3. **Pick:** renewals first, i.e. accounts whose term ends within (trip days + 0.5) days. Otherwise the highest retainer that is eligible, not already travelled to, and fits capacity (`Σ tokens ≤ throughput·100·thermal`).
4. **Departure:** 08:00-15:00 on the visible server clock (`DEPART`), only when `cash ≥ trip cost + $500` and `cash ≥ 0`. The scripted first pilot (CloudDesk, first client) leaves at any hour.
5. **Trip plan** (`CompanyOps.tripPlan`), cost paid at departure:

| Tier | Days away | Crew (pilot / check-in) | Hotel | Cost pilot / check-in |
|---|---|---|---|---|
| city | 0.2 (240 s) | 1 / 1 | – | fuel $30 + per diem $50 = **$80** / $80 |
| region | 1.0 | 2 (rep + engineer) / 1 | 1 night, City Hotel $140 | 90 + 2·(140 + 50) = **$470** / $280 |
| abroad | 2.0 | 2 / 1 | 2 nights, Meridian Grand $220 | airport fuel 40 + 2·(flight 700 + 2·220 + 2·50) = **$2,520** / $1,280 |
| abroad with the company jet | 1.5 | 2 / 1 | 1 night | jet fuel 1,500 + 2·(220 + 2·50) = **$2,140** / $1,820 |
| hosted at the guest house (every 2nd region/abroad pilot from stage 3) | 1.0 | crew stays home | client sleeps 2 nights at the guest house | 2 guests × 2 nights × $60 = **$240** |

6. **Trust** per visit (deterministic, no dice; shown as "trust 67 %"):
   ```
   trust += clamp(0.5 + 0.025·(bestStat − minimum) + 0.05·(avg field-rep skill − 3)
                  + 0.10·hosted + 0.5·[scripted first client] + 0.05·[abroad by jet], 0.35, 1)
   ```
   The founder counts as skill 3. The client signs when trust ≥ 1 and an account slot is free.
7. **Sign:**
   - pilot fee = 1 day of retainer, paid at once (ledger category `pilot`, counts as revenue);
   - reputation +1.5; `contractsCompleted` +1;
   - the retainer flows at `retainer/1200` per second (category `b2b`);
   - serving cost `tokens·serveCost/3600` per second (`b2bserve`);
   - compute is reserved: `deals.reserved = Σ tokens/100`. Training then runs at `max(0.3, 1 − reserved/throughput)` (`EmpireMath.trainingRate`), and consumer capacity is reduced by the same amount.
8. **Term:** 6 game days. A check-in visit before the end renews it for 6 more days; the account does not lapse while that trip is under way.
9. **Lost when:** the term ends without a visit, no live model meets the need any more, or capacity is gone. Each case gets a news line with the reason.

**Player hooks.** Remote `DealAction {action = "pin" | "skip" | "joinMeeting", clientId}` (RecruitAction pattern, rate 4/2). The founder can drive to the client's lobby and press the `CityService.setMeetingHandler` prompt: +0.15 trust on that visit (**not simulated**, optional).

### 3.3 Pilots (the old contracts)

The old once-per-UTC-day `CONTRACTS` click is gone; `EmpireConfig.CONTRACTS = {}`. Its clients are in the catalogue, and the **pilot fee** on signing replaces the reward. It is booked with `applyFlow(..., "pilot")`, so it counts toward `totalRevenue` and the "Seven figures" quest. Today's `grant` did not count.

### 3.4 Studio

`StudioService.deliver:67`: `day = floor(empire.seconds/1200)` (one delivery per brief per **game day of play**, was the real UTC day). The reward is ×0.5 (`studioScale`), so the 5 briefs pay ≤ $19,000 per game day.

Stall-bug fix (`StudioService:21`): when the source model is retired with `replacedBy`, follow the chain (≤ 8 hops) to the live successor.

### 3.5 Guest house (company hotel)

From stage 3 (`Plan.HOTEL_MIN_TIER = 2`; rooms H0/H1, `Plan.HOTEL`, `RoomKitsHotel`).

| Item | Value per game day |
|---|---|
| Outside guests | 12 rooms × 60 % × $300 = **+$2,160** |
| Utilities | −$400 |
| 2 posts (OpsIndex 13 Hotel Reception, 14 Housekeeping) | −2 × $720 = −$1,440 |
| **Net** | **+$320** (it never makes big money) |

**Real job.** Every second region/abroad pilot (not the founder's) is **hosted** at HQ: the client team sleeps 2 nights in the guest house ($240 internal cost), and the visit takes 1 day, needs no flight and gives +0.10 trust. Candidates from far away also stay overnight (flavour).

Office attributes `HotelRooms = 12` and `HotelGuests` = 7 (outside guests: 12 × 0.6, rounded) + 2 per hosted client team currently in-house.

### 3.6 Retail and one-offs

- Retail is unchanged: `FacilityService.economyTick:512-523`, $12 per ticket per 30 s, tickets = retailLevel + ⌊staff/24⌋.
- Quests total $77,000 once.
- The daily login stays on the real UTC day: $1,000 + $500·(streak − 1).

### 3.7 Income shares

Windows ending at minutes 10, 60 and 180. All values are $/min and come from the ledger categories in the sim. Opt and late-join runs are in the second table.

| Source | Casual 5-10 | Casual 45-60 | Casual 120-180 |
|---|---:|---:|---:|
| Consumer + API market | 6,006 (61 %) | 35,622 (72 %) | 62,732 (78 %) |
| B2B retainers | 420 (4 %) | 5,320 (11 %) | 17,025 (21 %) |
| Pilot fees | 1,800 (18 %) | 6,000 (12 %) | 0 |
| Studio | 3 (0 %) | 18 (0 %) | 76 (0 %) |
| Guest house | – | 108 (0 %) | 108 (0 %) |
| Retail | 24 (0 %) | 72 (0 %) | 146 (0 %) |
| Quests | 1,600 (16 %) | 2,667 (5 %) | – |
| **Total** (recurring) | **9,853** (6,453) | **49,806** (41,140) | **80,086** (80,086) |

Source: `out_V_main_casual.txt`. B2B (retainers + pilots) is 22 % at 10 min, 23 % at 60 min and 21 % at 180 min, so it is the second engine.

Opt and late-join runs, same windows (`out_V_main_opt.txt`, `out_V_main_late60.txt`):

| Source | Opt 5-10 | Opt 45-60 | Opt 120-180 | Late60 5-10 | Late60 45-60 | Late60 120-180 |
|---|---:|---:|---:|---:|---:|---:|
| Market | 6,335 (62 %) | 46,857 (79 %) | 93,313 (77 %) | 5,957 (61 %) | 35,473 (77 %) | 63,202 (78 %) |
| B2B retainers | 420 (4 %) | 6,030 (10 %) | 22,660 (19 %) | 420 (4 %) | 4,281 (9 %) | 16,593 (20 %) |
| Pilot fees | 1,800 (18 %) | 6,000 (10 %) | 5,500 (5 %) | 1,800 (18 %) | 3,600 (8 %) | 1,300 (2 %) |
| Quests | 1,600 (16 %) | – | – | 1,600 (16 %) | 2,667 (6 %) | – |
| Studio, retail, guest house | 27 (0 %) | 199 (0 %) | 372 (0 %) | 27 (0 %) | 198 (0 %) | 327 (0 %) |
| **Total** | **10,182** | **59,086** | **121,844** | **9,804** | **46,218** | **81,422** |

---

## 4. Costs

All recurring costs are booked per second with `EconomyService.applyFlow(session, revenue, cost, category)`. The 4th argument is new and feeds `empire.ledger` (Appendix A) and the P&L screen. They are shown "per game day". Each is also added to `session.live.cost`, so the client money extrapolation stays right.

| Cost | Formula / numbers | Hook |
|---|---|---|
| **Wages (hired)** | Salary per game day, accrued every second, day and night, including paid vacation and sick days: researcher **$3,600**, engineer **$4,320**, curator **$2,700**, Growth & Sales **$4,320**. `ROLES.wage` = 3.0 / 3.6 / 2.25 / 3.6 $/s × the profile multiplier `w` (0.5-2). Night crew ×1.3 (**not simulated**). | `EmpireConfig.ROLES`, `EmpireMath.bonuses.wage`, `EmpireService.tick:163` |
| **Hiring fee** | **Flat** agency fee: $1,000 / 1,200 / 800 / 1,200 (about ⅓ of a day's wage). Was price·(1 + 0.05n + 0.001n²). Interview hires: fee × the candidate's ask (unchanged rule). | `EmpireMath.hireCost` |
| **Operations staff** | 0 / 8 / 12 / 14 / 16 posts (+2 guest house from stage 3) × **$720/day** = `EmployeeConfig.OPS_WAGE_PER_DAY`. Staffed, relieved and covered by HR automatically. | `CompanyOps.step` (`ops`) |
| **Upkeep** (rent, utilities, insurance, cleaning supplies) | $300 / 2,500 / 9,000 / 24,000 / 48,000 per game day | `CompanyOps.STAGES.upkeep` (`upkeep`) |
| **Lunch** | (hired + ops) × 0.9 present × $6 (garage pizza) or $8 (chef) per game day | `food` |
| **Fleet leases** | $100 per game day per field-rep car. The boss's cars stay owned purchases (`CampusConfig.CARS`, Executive Limo = pass). | `fleet` |
| **Trips** | table in 3.2, paid at departure: fuel, flights, hotel nights, per diem | `trips` |
| **Guest house** | utilities $400/day (+2 posts in `ops`) | `guest` |
| **Company jet** | $900,000 once (stage ≥ 4); running 2 pilots × $3,000 + upkeep $2,500 = **$8,500/day**; fuel $1,500 per abroad trip | `jet`, `jetbuy` |
| **Serving + power** | unchanged: tokens × serveCost × (0.85 Quantization) × (1 − 0.2·(1 − e^{−O_eng/10})); power `throughput·0.025 $/s` while serving; B2B serving likewise | `MarketMath`, `MarketService:202`, `CompanyOps` |
| **Company phones** | $10 per employee per game day (hired + ops). **Not simulated**: ≤ $2,100/day = 0.2 % of costs at stage 5. | `ops` |
| **Drivers, Training Lead, apprentices** | Drivers $720/day each (1 from stage 2, 2 from stage 4); Training Lead $900/day (stage ≥ 3); apprentices 40 % of the role wage. **Not simulated**: < 0.5 % of costs. | `ops`, `wages` |
| **Investments** (not running costs) | offices, GPUs, cooling, training, data, research, Lab levels, marketing, hiring fees, jet; refinement plan.cost × (1 + 0.5·iteration), ≤ 3 per model | unchanged services |

### 4.1 Cost shares (casual, running costs only)

| Running cost | 5-10 | 45-60 | 120-180 |
|---|---:|---:|---:|
| Wages, hired | 772 (71 %) | 11,497 (81 %) | 24,823 (80 %) |
| Operations staff | 142 (13 %) | 504 (4 %) | 591 (2 %) |
| Upkeep | 69 (6 %) | 450 (3 %) | 1,445 (5 %) |
| Serving + power | 73 (7 %) | 1,679 (12 %) | 3,944 (13 %) |
| Trips (fuel, hotel, flights, per diem) | 32 (3 %) | 0 | 130 (0 %) |
| Fleet, food, guest house, B2B serving | 5 (0 %) | 73 (1 %) | 141 (0 %) |
| **Total** (% of income) | **1,093 (11 %)** | **14,204 (29 %)** | **31,074 (39 %)** |
| All wages (hired + ops) as % of income | 9 % | **24 %** | **32 %** |

Source: `out_V_main_casual.txt`. Wages are the dominant cost; travel, hotel, cars and lunch are visible P&L lines but stay below 1 %.

Cumulative over 240 min (casual ledger):
- wages $5.01M, hiring fees $210k (4 % of wages; today's game: 143 %), operations $128k, upkeep $299k;
- trips $13.4k (fuel, City Hotel and Meridian Grand nights, flights, per diem), fleet $4.7k, lunch $10.7k, guest house $4.2k, jet running $19.2k;
- against market $13.07M, retainers $3.42M and pilot fees $0.81M.

---

## 5. Staff and department production

### 5.1 One formula, watched or not

For role *r* with hired profiles *i* (skill k_i 1..5):

```
H_r = Σ_i f(k_i),   f(k) = (7 + k)/10                       -- WorkforceMath.factor / capacity
O_r = ( min(H_r, S_r) + 0.5·max(0, H_r − S_r) ) · A · M(stage) · Q_r
```

- `S_r` = seats of the role's departments in the current building (table 5.2).
- `A` = availability = **0.90**: the mean share present after vacation (8.3 %) and sick days (1.7 %).
  - It is computed per person from saved data (5.3). In the sim it is used as its expectation.
- `M` = morale (5.4): 0.95 / 1.035 / 1.05 / 1.05 / 1.05 by stage at full kitchen staffing.
- `Q_r` = room quality: 1.10 when the role's specialist room (datalab, control, lab, evaluation, hwlab, platform, studio) is staffed ≥ 50 %, else 1.0.
  - Without a facilities post on duty it is −0.05.
  - **Not simulated** (Q = 1), so the sim understates output by 0-10 %.

**Level vs stock outputs.**
- Outputs that act as a level use `O_r` directly and never flicker: training speed, marketing multiplier, serving cost and capacity, reach cap.
- Outputs that accrue a stock use `O_r · duty(clock)`: research points and curated tokens.
  - `duty = TS(hour)/0.5538` is normalised to a mean of exactly 1 per game day (`CompanyOps.duty`).
  - So research stops at night, daily totals do not depend on when you play, and logging in at night gains nothing.

**Implementation.**
- `WorkforceMath.count(e, role)` returns O_r computed from saved data only. The patched line is `WorkforceMath:34-38`; seats and morale come from `CompanyOps`.
- The StaffService state machine (`StaffService:380-420`) **no longer feeds money**. It only animates the schedule: who is on duty comes from the same `TS`/shift data. It still publishes `live.workforce.states` for screens.
- The offscreen 100 % branch (`:383-384`) and the 0.75 weight for walking are removed from the economy.
- **A company produces exactly the same whether its owner, a visitor or nobody stands near it.**

**What each role produces:**

| Role | Output (O = O_r) | Hook |
|---|---|---|
| ML Engineer | training speed `1 + 0.15·O` (+ research); serving cost ×(1 − 0.2·(1 − e^{−O/10})); serving capacity ×(1 + 1.0·(1 − e^{−O/20})); training slots v2 `min(stage cap, 1 + ⌊O/8⌋)` | `EmpireMath.bonuses.speed/serving`, `CompanyOps.capacity` |
| AI Researcher | research points/s `(base(stage) + 0.6·O) × duty`; core-stat bonus on new models `⌊50·(1 − e^{−O/10})⌋/10` (≤ +5) | `EmpireMath.bonuses.points/core` |
| Data Curator | curated tokens/s `300,000·O` × duty; quality 0.65 (0.85 with Data Cleaning) | `EmpireService.tick:155` |
| Growth & Sales | `reps = min(heads, ceil((slots−2)/2))` go on field duty (cars, trips, accounts); the rest are in-office `O_g = O·(heads − reps)/heads` → marketing `1 + 0.4·(1 − e^{−O_g/10})`, reach cap `0.20 + 0.012·O_g` | `CompanyOps.fieldReps/growthO/reachCap`, `EmpireMath.bonuses.revenue` |

### 5.2 Seats and what every room kind produces

Seats per role and stage (`CompanyOps.SEATS`, from `Plan.rooms(tier)` desks; computed on today's plan with `agents/design_final/economy/seats.luau`):
- researcher = design + research + ½ evaluation (+3 First AI design desks at T1);
- engineer = engineering + training + ½ evaluation;
- curator = data (+3 First AI data desks at T1);
- Growth & Sales = growth + deployment.

| Role | Garage | T1 | T2 | T3 | T4 |
|---|---:|---:|---:|---:|---:|
| Researcher | 5 shared | 15 | 26 | 50 | 93 |
| Engineer | 5 shared | 16 | 28 | 56 | 85 |
| Data curator | 5 shared | 14 | 32 | 32 | 32 |
| Growth & Sales | 5 shared | 16 | 34 | 34 | 71 |

Every room kind in `Plan.rooms(0..4)` (the full list from today's plan):

| Room kinds | Department / job | What it produces | Simulated? |
|---|---|---|---|
| `garage_lab`, `garage_founder`, `garage_assist`, `garage_porch`, `garage_wc` | garage stage: 5 shared desks, founder, assistant, applicants wait on the porch | seats for all 4 roles (5 shared) | seats yes |
| `team` (dept data/design/research/engineering/training/growth), `focus` | that department's seats | O_r (Q 1.0) | yes |
| `architecture` (Model Architecture) | research | seats; Q 1.1 when staffed (part of the core-stat bonus) | seats yes, Q no |
| `datalab` (Data Quality Lab) | data | seats; Q 1.1; staffed ≥ 50 % → curated quality +0.05 | seats yes, rest no |
| `control` (Training Control) | training | seats; Q 1.1; when staffed, training events auto-resolve (existing `autoResolve`) and the night crew may run here | seats yes |
| `evaluation`, `lab`, `hwlab` | evaluation / research / engineering | seats; Q 1.1; hwlab staffed → GPU-fault events −50 % | seats yes |
| `platform`, `studio` | engineering / growth | seats; Q 1.1; platform → B2B capacity +5 %, studio → Studio build rate +10 % | seats yes, bonuses no |
| `launch`, `support` (Deployment & Growth, Customer Desk, Customer & Support) | Growth & Sales | in-office O_g (marketing, reach cap), field-rep home desks, account screens | yes |
| `first_ai`, `prototype`, `secret_lab` | first AI studio (3 data + 3 design desks), founder labs | seats at T1; founder UI | seats yes |
| `hr` | People & Company (HR) | vacation/shift planner (≤ 10 % of a team away), apprentices' training room | rule yes (as A) |
| `cafe`, `kitchen_boh`, `pantry` | chef, kitchen team, café host, barista; pantry lunch counters (15 lunches each, stage ≥ 4) | lunches → morale M | M yes (table) |
| `gym`, `sauna`, `lounge`, `recovery`, `terrace`, `roof_terrace`, `pavilion_roof` | wellness and breaks | wellness → morale M; breaks are inside the 0.94 time-sheet factor | yes (inside M, TS) |
| `meeting`, `project_meeting`, `boardroom` | meetings count as work (weight 1.0, was 0.8); the Project Room hosts model reviews; the boardroom hosts hosted-pilot meetings | part of TS (no −20 %) | yes (TS) |
| `datahall`, `compute`, `itdesk`, `ups`, `machine`, `plant`, `roof_tech`, `roof_solar` | compute + IT | GPU slots per stage (blades lit per GPU, locked blades dimmed); the IT post fixes rack faults | slots yes, faults no |
| `lobby`, `visitor_lounge`, `showroom`, `garden_lobby`, `security` | reception, security | client and candidate visits; reception needed for hosted pilots, security for the night crew; showroom = the hosted-pilot demo | no (rules) |
| `garage`, `fleet`, `workshop`, `b1_lobby`, `delivery` | fleet manager, drivers | leased field cars in the 19 bays, departures through the barrier, the boss's car | costs yes |
| `guestroom`, `hotel_lobby`, `hotel_breakfast`, `hotel_workshop`, `hotel_office`, `hotel_pantry`, `hotel_service`, `hotel_corridor`, `hotel_stair` | guest house (posts 13, 14) | room income, hosted pilots, workshop room for client teams | money yes (flows) |
| `founder_office`, `founder_assist`, `founder_library`, `founder_bath`, `vault`, `archive` | founder floor | founder UI, company report (unchanged) | – |
| `mailroom`, `print`, `phone`, `storage`, `restrooms`, `wc`, `showers`, `spine`, `atrium`, `stair`, `liftpit`, `roof_lobby`, `service_passage`, `secret_passage`, `pavilion_corridor` | circulation and decoration | **no economic effect**; the building tour says so honestly | – |

### 5.3 Working hours, night, vacation, sick days

**Shifts.** Unchanged seed shifts (`EmployeeConfig.personalityFromSeed:174-180`): start 7.75-9.0, finish 16.5-18.0, lunch 11.75-13.5 for 1 h.

**Time sheet** (expected share of a team at work at hour h; `CompanyOps.timesheet`):

```
TS(h) = clamp((h − 7.75)/1.25, 0, 1) · clamp((18 − h)/1.5, 0, 1) · (1 − lunch(h)) · 0.94
lunch(h) = overlap([h−1, h], [11.75, 13.5]) / 1.75
```

| Hour | 7.5 | 8 | 8.5 | 9-11 | 12 | 12.5 | 13-13.5 | 14 | 15-16.5 | 17 | 17.5 | 18-7.5 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| TS | 0 | 0.19 | 0.56 | 0.94 | 0.81 | 0.54 | 0.40 | 0.67 | 0.94 | 0.63 | 0.31 | 0 |
| duty = TS/0.5538 | 0 | 0.34 | 1.02 | 1.70 | 1.45 | 0.97 | 0.73 | 1.21 | 1.70 | 1.13 | 0.57 | 0 |

The real-time day average is **0.5538** (900 s day + 300 s night).

**Night** is 18:00-08:00, 300 real seconds. Everybody is off duty except an optional night crew. Servers keep serving, and retainers and subscriptions keep paying, 24/7.

**Vacation** (automatic HR, no new profile fields):
- Each employee takes 1 day in every 12 company days (8.3 %).
- The day in each 12-day cycle is `vday(seed, cycle) = Employee.hash(seed·31 + cycle) % 12`, with `cycle = floor(companyDay/12)`.
- **HR collision shift** (pure function of the department's sorted seeds): if more than `ceil(0.10 · team)` people share a vacation day, the extra people (highest seed first) move to the next day of the cycle with room.
- Vacation is paid. Absent rigs use the OFF_DUTY pattern (`StaffService.sync`, `OffDuty = true`, desk released). `employees[role]` never changes, so nothing is rebuilt.

**Sick days:** a person is sick on company day d when `Employee.hash(seed·7919 + d) % 1000 < 17` (1.7 %). That is one day; it is paid; the phone says "Mia is sick today".

**Why hash-based:** every server, the UI and the economy agree on who is away, and **no staff-profile field is added**. That avoids the `cleanProfile` / `profilesConsistent` / `StaffAssignment.profile` / `Rig.Profile` sync trap (`profileSignature` no longer exists since the net package moved to leaf diffs).

**Night shift** (optional per department; stage ≥ 3; needs a security post on duty):
- The overflow heads beyond the day seats (up to the seat count) move to a night crew working 22:00-06:00. They count 1.0 instead of 0.5, at wage ×1.3.
- It only pays when a department is over its desks.
- Saved as `empire.nightShift[dept] = true`. **Not simulated** (the auto-HR need rule keeps every department within its seats).

### 5.4 Morale: the chef and lunch

```
M = clamp(0.90 + 0.10·lunch + 0.03·wellness + 0.02·barista, 0.90, 1.05)      -- CompanyOps.morale
lunch = min(1, lunchesPerDay / (heads · 0.9))
```

- **lunchesPerDay:**
  - pizza: lunch 0.5;
  - from stage 2: chef 70 + kitchen team 50 = 120;
  - stage 3: + café host 25 = 145, the café limit (53 seats × 2.75 turns);
  - stage ≥ 4: + 15 per pantry lunch counter (T3: 4 → 205; T4: 6 → 235).
- **wellness:** 0 / 0.5 / 1 / 1 / 1 by stage. **barista:** 1 when the barista post is staffed.
- Result at full staffing: M = 0.95 / 1.035 / 1.05 / 1.05 / 1.05.
- A kitchen post that is empty for a day (e.g. a disabled post) lowers lunch and M by up to 0.10. HR relief covers breaks and vacation, so this normally never happens.
- Office attribute `LunchesServed` (life package) is the real count.

### 5.5 Operations staff: paid jobs with a real function

Posts are `EmployeeConfig.OPERATIONS_JOBS` (OpsIndex 1..16). All posts are staffed automatically from the stage on, at **$720 per game day** each. They:
- get lunch in their own window;
- take breaks only with relief cover (no coffee breaks that leave the post empty);
- can be talked to.

| Stage | Posts (OpsIndex) | Count |
|---|---|---|
| 2 Founder HQ | 1 Reception, 3 Security, 5 Facilities, 6 IT Support, 7 Barista, 8 Chef, 9 Kitchen Team, 12 Fleet | 8 |
| 3 Startup Campus | + 2 Reception, 10 Cafe Host, 15 Cleaner, 16 Mailroom; guest house: 13 Hotel Reception, 14 Housekeeping | 12 + 2 |
| 4 Innovation Campus | + 4 Security (garage booth), 11 Facilities | 14 + 2 |
| 5 Global AI HQ | + night rota: 1 security guard, 1 IT on call (no new station: they use posts 3 and 6 at night) | 16 + 2 |

| Post | Function in the economy (what breaks if it is empty) | Simulated? |
|---|---|---|
| Reception | client and candidate check-in; hosted pilots need reception on duty | wage yes, rule no |
| Security | night crew and after-hours client visits need it; the garage barrier | wage yes |
| Facilities, Cleaner | keep Q_r (−0.05 without) | wage yes, Q no |
| IT Support | fixes rack faults (capacity −1 unit per fault until fixed: 60 s with IT, 300 s without) | wage yes, faults no |
| Barista | +0.02 morale | yes (in M) |
| Chef, Kitchen Team, Cafe Host | lunches → morale | yes (in M) |
| Fleet | without it, at most 2 field trips at once (from stage 3 all field reps may travel) | wage yes |
| Mailroom | flavour (contracts and badges) | wage yes |
| Hotel Reception, Housekeeping | run the guest house | wage + flows yes |

`EmployeeConfig.OPS_WAGE_PER_DAY = 720` lets TalkService state the real pay.

---

## 6. Calendar: one clock

| Thing | Unit / rule | Where |
|---|---|---|
| Game day | 1200 s: 900 s for 08:00-18:00, 300 s for the night | `EmployeeConfig.hour:188` (unchanged) |
| Visible hour (sky, lights, who is at work, departures) | `CompanyOps.hour(workspace:GetServerTimeNow() % 1200)`, one per server, restart-proof. Replaces `local time=54` (`StaffService:37`) and drives `Lighting.ClockTime` (`:370`) and `CompanyHour`. | `StaffService.tick` |
| **Company date** (saved) | `empire.calendar = {day = 1, index}`: `day` +1 whenever the server day index `floor(clock/1200)` changes while the company is online | `CompanyOps.advanceCalendar` |
| Durations (trips, terms, vacation cycles) | play seconds `empire.seconds` (persisted, online only) | `CompanyOps.step` |
| Payroll | rates per game day, accrued every second; the P&L shows one pay slip per company day (24 people 6/6/6/6: "Day 4 payroll −$89,640") | `EmpireService.tick` |
| Retainers | per game day, accrued per second; term 6 days; pilot = 1 day | `CompanyOps` |
| Hotel nights | per traveller: region 1, abroad 2 (1 with the jet); hosted client 2 nights at the guest house | `CompanyOps.tripPlan` |
| Billing month | `GAME_MONTH_SECONDS` = 3600 s = 3 game days. Subscription and API prices stay "per month". The UI shows money **per game day** and adds "(month = 3 days)" next to prices. | `MarketMath` |
| Studio briefs | once per brief per game day of play | `StudioService.deliver` |
| Vacation / sick | company days (5.3) | hash functions |
| Market cycles | 300 s (unchanged) | `EmpireConfig.cycle` |
| Daily login reward | **real** UTC day (a real-life login reward) | `EmpireService.daily` |
| Offline | nothing runs offline (`lastSeen` stays unread); trips and terms pause | – |

The news log stamps both, e.g. "day 8 11:54: signed Ledger Finance: pilot $27,000, retainer $27,000/day". In the casual 240-min run the company reached calendar day 13.

---

## 7. AI models

### 7.1 Product lines
- Release target = product line: Consumer Chat (`general` → consumers), Study app (`students`), Developer API (`developers`), Business API (`businesses`).
- A model is offered in every segment but loses 0.6 utility outside its line (≈ 18 fit points at FIT_SCALE 30). So a specialist owns its line.
- Live lines per stage: 1 / 2 / 3 / 4 / 4 (`MarketConfig.PRODUCT_SLOTS`). `AIModelService.releaseModel:459` returns `LINE_LIMIT` when a new line would exceed the stage.

### 7.2 One live model per line (anti-clone) and versions
- A release into a line that already has a live model **is the new version** (`releaseModel`, after `:484`):
  - it takes over `MIGRATE = 0.9` of the predecessor's users per segment and its organic word of mouth;
  - the predecessor becomes `retired` with `replacedBy = newId` (its users are moved, not wiped);
  - studio projects and B2B accounts follow automatically, because B2B checks the best live stat.
- Same-name versioning (`versionFor`) stays.
- The model cap of 80 (`AIModelService:316/347`) moves to `GameConfig.MODEL_LIMIT = 80` and counts only non-retired models.

### 7.3 Ageing
- −8 fit points × min(1, vage/3600 s), i.e. at most −0.27 utility after 3 game days. `vage` resets on release and on refinement.
- This makes "ship a new version" a recurring task. The casual bot retrains a line when a new model beats its aged quality by ≥ 3.

### 7.4 Refinement, fixed and capped (`AIModelService.improveModel:397`, `finish:209`)
- Additive gain per core stat: `(1 + 4·dataQuality)·qualityMod/√(1 + iterations)`. It was proportional and compounding.
- At most **3** refinements per model (`REFINE_LIMIT`, err `REFINE_LIMIT`). Cost = plan.cost × (1 + 0.5·iterations).
- The model **stays live** while refining (`resumeLive` path; serving uses the old weights). The log text "Serving paused until completion" must change to "Serving continues with the current version".
- Each refinement resets `vage`. All stats ≤ 99.

### 7.5 Stats cap, Lab levels, research
- `EmpireMath.boostStats`: **every** core stat ≤ 99 (was only reliability).
- **Lab levels** (`EmpireService.labLevel`, remote `EmpireAction {action="labLevel"}`): repeatable after the whole research tree.
  - Level L → L+1 costs `floor(200·1.35^L)` research points and `$floor(6000·1.6^L)`.
  - Each level gives +1 core stat on future models (in `bonuses.core`, before the 99 cap). Max level 10.
  - All 10 levels cost $1,089,509 and 10,914 points. In the casual run they run from 53 to 123 min.
- After the tree and level 10, research keeps a quarter of its desks (HR need, 8.1) for model reviews. This is honest: nothing more to research.

### 7.6 Training slots
- **v1 ships one training slot.** `data.training` stays exactly as today, so its ~30 readers are unchanged. DATA_VERSION 6 adds the empty map `data.trainings = {}` (string keys "2".."4") reserved for v2.
- **v2:**
  - slots = `min({1,1,2,3,4}[stage], 1 + ⌊O_eng/8⌋)`;
  - **one job per slot** (a new model or a refinement);
  - slot 1 stays `data.training`;
  - GPU throughput is split equally across running jobs, so the total speed is unchanged.
- **Not simulated** (the bot trains one job at a time; jobs take 12-140 s).

### 7.7 Release forecast and Recommended price
- `LabApp:943` (forecast) and `:723` (market-check ranking, today the static `NPC_MODELS`) must use live rivals (`live.marketplace.offers` with `target`, `company`, NPC flag) and the patched `MarketMath`, exactly as `sim_final.luau: portfolioProfit` does.
- The release card pre-selects **Recommended**: the forecast-optimal subscription in {$5, $10} and API price in {$1, $2, $3, $4} over 30 minutes, with marketing ≤ $5,000. This is the casual bot's release rule.
- **Auto-price** (default on for every model) re-runs the same forecast every 300 s (one market cycle) over 15 minutes and applies the best menu price.
  - One-line explanation, e.g. "Servers 97 % full → Chat price raised to $10".
  - A manual price switches auto-price off for that model (`model.release.auto = false`).

---

## 8. Automation: what runs by itself, what the player decides

### 8.1 Rules (all simulated unless marked)

| Runs automatically | Rule | Player decides / can override |
|---|---|---|
| **HR hiring** (default on, `empire.hr.auto`) | Every 20 s HR hires one person into the department with the lowest `heads/need` that is below its **need** (`CompanyOps.hrNeed`):<br>- researchers: their seats while research or Lab levels remain, then ¼;<br>- engineers and curators: their seats;<br>- Growth & Sales: field reps + max(24, the heads that reach the stage's reach cap).<br>Hiring happens only while payroll (hired + ops) after the hire ≤ **budget × trailing income** (5-min average; budget 25 / **40** / 55 %). The first 3 hires are always allowed. In Save mode HR stops once half the desks are filled. | wage-budget slider; hire/fire manually; per-department target |
| **Vacation, sick cover, shifts, relief** | 5.3 (hash + 10 % collision cap), breaks with relief | night shift per department (stage ≥ 3) |
| **Sales** | lead → pilot trip → trust → sign → check-ins (3.2) | pin / skip a client; join a meeting in person (+0.15 trust, not simulated) |
| **Travel desk** | car from the fleet, hotel, flights, jet if owned, hosted pilots | – |
| **Fleet** | one leased car per field rep ($100/day), returned when not needed | buy the boss's cars, Executive Limo pass |
| **Pricing** | Recommended at release + auto-price every 300 s (7.7) | any manual price |
| **Purchasing** | lunch, utilities, guest-house running, phones | GPUs, cooling, data, research, Lab levels, office, jet |
| **Model operations** | the successor retires the predecessor and migrates users; training events auto-resolve when Training Control is staffed (existing `autoResolve`, 25 s) | train (size, focus, recipe, line), release, refine |
| **Save mode** | switches on when the next office is < 8 minutes of net profit away (`(price + 2·reserve − cash)/net < 8`, reserve = max($1,500, 2 min of payroll)). It is off in the garage until the first client has signed. It pauses: research and Lab levels, trainings above 30 % of free cash, HR beyond half the desks, and ordinary GPU and cooling purchases. It still allows GPU buys that pay back within 5 minutes when servers are > 85 % full. | toggle auto/off |

### 8.2 The "Next goal" bar and the assistant
- `EmpireMath.nextGoal(data) → {id, text, have, need, etaMinutes}` is a pure function shown in the HUD next-step card (`Screens/HUD.module.luau: nextStep:63`, which today nudges quests at :127-131). Its text is the first recommendation of `AssistantService.insight:226`.
- ETA = (price + 2·reserve − cash)/net profit per minute. Order:
  1. Train your first AI
  2. Release it
  3. Sign your first client (CloudDesk)
  4. Founder HQ $27,000
  5. Second product line
  6. Startup Campus $100,000
  7. First region client
  8. Innovation Campus $380,000
  9. Frontier research (7B)
  10. Global AI HQ $1.9M
  11. All 4 lines at 90+
  12. Lab level 10
  13. Company jet
- `AssistantService.briefing:113` gets sections **Today**, **Customers**, **Money** and **Models**, built only from real state. Examples:
  - "Day 9 · 10:30 · 41 of 64 at work, 4 on vacation, 1 sick, 2 at Ledger Finance (back tomorrow 08:00, City Hotel $140)."
  - "Servers 92 % full, 12,400 waiting — a Workstation GPU serves 48,000 more."
  - "Atlas Search needs knowledge 55 (your best: 51)."
  - "Your Coding line is 41 min old (−5 fit)."
  - "Growth team at full effect (24 in the office)."
- Every automatic action writes one line to `empire.deals.news` (≤ 40 entries; the phone shows the newest 20). That covers B2B trips, signings and losses (simulated) and HR hires, price changes and Save mode (spec). It is the "why" feed in the company phone.

### 8.3 Safety rules (automation can never bankrupt the company)
- Trips only when cash ≥ trip cost + $500, and never while cash < 0 (simulated).
- HR never hires beyond need or budget (simulated).
- Cash < 0 for one full game day → night crews and trips pause (spec).
- Cash < −2 days of payroll → the newest hires go on **unpaid leave**: profile kept, no output, no wage, until cash > 1 day of payroll (stored as `empire.unpaidLeave = n`, the last n profiles of the role list).
  - **Not simulated as a rule**: no run went below $0 (9.7). The −90 % cash shock run stayed positive.

---

## 9. Targets check (simulator evidence)

**Profiles.**
- **casual** = `--profile default`. Recommended price at release (menu sub {5, 10} / API {1-4}, marketing ≤ $5k), auto-price every 300 s, auto-HR at 40 %, Save mode, one model per free line.
- **opt** = `--profile opt`. Full price and marketing search (up to $100k), 3 refinements per model; otherwise the same rules.
- **late60** = casual founding on a server that has already run 60 minutes.

All bots act every second (lower bound for a human). `C_slow30` acts every 30 s.

Column notes:
- *wages* = hired + operations staff per minute, with the share of revenue;
- *cost* = all running costs (wages, ops, upkeep, food, fleet, trips, guest house, serving, power, jet);
- *B2B* = retainers per minute (accounts);
- *best model* = the best model trained so far; *live lines* = the live product lines (gen = Consumer Chat, dev = Developer API, stu = Study app, bus = Business API);
- *NPC best* = the best NPC lab model overall.

Garage start money is $10,000 + the $1,000 daily login.

### 9.1 (a) Casual, fresh server — `out_V_main_casual.txt` (start 16:53)

| min | money $ | revenue $/min | running cost $/min | wages (share) | B2B $/min (accounts) | staff (R E C G) | office | best model | live lines | NPC best |
|---:|---:|---:|---:|---:|---:|---|---|---|---|---:|
| 0 | 11,000 | 0 | 0 | 0 (0%) | 0 (0) | 0 (R0 E0 C0 G0) | 1 Garage | - | - | 55.9 |
| 5 | 11,402 | 3,254 | 592 | 531 (16%) | 0 (0) | 3 (R1 E1 C1 G0) | 1 Garage | s500m 47.1 | gen | 61.5 |
| 10 | 5,438 | 9,307 | 2,052 | 1,782 (19%) | 450 (1) | 8 (R2 E2 C2 G2) | 2 Founder HQ | s500m 47.4 | gen/dev | 61.8 |
| 20 | 37,262 | 17,086 | 5,287 | 4,770 (28%) | 2,025 (3) | 24 (R6 E6 C6 G6) | 2 Founder HQ | s1b 56.4 | gen/dev | 61.8 |
| 30 | 82,940 | 18,223 | 5,370 | 4,770 (26%) | 2,025 (3) | 24 (R6 E6 C6 G6) | 2 Founder HQ | s3b 59.4 | gen/dev | 61.8 |
| 45 | 58,551 | 34,085 | 11,635 | 10,089 (30%) | 2,775 (4) | 52 (R12 E13 C15 G12) | 3 Startup Campus | s3b 64.3 | gen/stu/dev | 61.8 |
| 60 | 71,328 | 45,185 | 15,653 | 12,330 (27%) | 7,275 (7) | 64 (R15 E16 C18 G15) | 3 Startup Campus | s7b 80.5 | gen/dev/stu | 61.8 |
| 90 | 50,024 | 52,020 | 17,745 | 13,626 (26%) | 7,275 (7) | 70 (R17 E20 C18 G15) | 4 Innovation | s7b 86.3 | stu/dev/bus/gen | 61.8 |
| 120 | 396,035 | 77,016 | 30,701 | 24,831 (32%) | 17,025 (10) | 128 (R38 E43 C25 G22) | 4 Innovation | s7b 99.0 | gen/bus/dev/stu | 61.8 |
| 180 | 271,535 | 82,168 | 38,894 | 31,599 (38%) | 17,025 (10) | 159 (R38 E67 C25 G29) | 5 Global HQ | s7b 99.0 | dev/stu/gen/bus | 61.8 |
| 240 | 3,260,487 | 118,915 | 46,963 | 38,160 (32%) | 40,275 (14) | 192 (R38 E85 C32 G37) | 5 Global HQ | s7b 99.0 | gen/bus/dev/stu | 61.8 |

Office stages reached at minute 7.5 / 31.5 / 85.7 / 167.8; lowest cash $1,791 at minute 3.1

Later: $123,027/min at 300 min and $124,606/min at 360 min (`out_V_plateau360.txt`), with cash $7.2M / $11.2M. The company jet was bought at 194.8 min and Lab levels 1-10 between 53 and 123 min.

### 9.2 (b) Opt profile, fresh server — `out_V_main_opt.txt`

| min | money $ | revenue $/min | running cost $/min | wages (share) | B2B $/min (accounts) | staff (R E C G) | office | best model | live lines | NPC best |
|---:|---:|---:|---:|---:|---:|---|---|---|---|---:|
| 0 | 11,000 | 0 | 0 | 0 (0%) | 0 (0) | 0 (R0 E0 C0 G0) | 1 Garage | - | - | 55.9 |
| 5 | 13,258 | 3,199 | 578 | 531 (17%) | 0 (0) | 3 (R1 E1 C1 G0) | 1 Garage | s500m 47.1 | gen | 61.5 |
| 10 | 7,394 | 9,020 | 2,208 | 1,998 (22%) | 450 (1) | 9 (R2 E3 C2 G2) | 2 Founder HQ | s500m 47.4 | gen/dev | 61.8 |
| 20 | 74,998 | 18,444 | 3,330 | 2,961 (16%) | 2,025 (3) | 14 (R3 E4 C3 G4) | 2 Founder HQ | s1b 55.1 | dev/gen | 61.8 |
| 30 | 21,523 | 23,051 | 7,264 | 6,435 (28%) | 2,025 (3) | 32 (R7 E8 C9 G8) | 3 Startup Campus | s1b 61.3 | gen/dev/stu | 61.8 |
| 45 | 109,779 | 42,627 | 13,239 | 12,330 (29%) | 2,025 (3) | 64 (R15 E16 C18 G15) | 3 Startup Campus | s1b 68.9 | dev/gen/stu | 61.8 |
| 60 | 313,623 | 52,395 | 15,051 | 12,330 (24%) | 6,525 (6) | 64 (R15 E16 C18 G15) | 3 Startup Campus | s7b 81.7 | gen/stu/dev | 61.8 |
| 90 | 150,457 | 87,197 | 28,798 | 24,831 (28%) | 13,725 (9) | 128 (R38 E43 C25 G22) | 4 Innovation | s7b 91.3 | stu/dev/gen/bus | 61.8 |
| 120 | 1,281,824 | 92,351 | 29,260 | 24,831 (27%) | 17,625 (10) | 128 (R38 E43 C25 G22) | 4 Innovation | s7b 99.0 | gen/stu/dev/bus | 61.8 |
| 180 | 2,561,433 | 136,246 | 45,105 | 38,160 (28%) | 34,125 (13) | 192 (R38 E85 C32 G37) | 5 Global HQ | s7b 99.0 | dev/bus/gen/stu | 61.8 |
| 240 | 8,108,875 | 134,626 | 44,917 | 38,160 (28%) | 40,875 (14) | 192 (R38 E85 C32 G37) | 5 Global HQ | s7b 99.0 | gen/stu/dev/bus | 61.8 |

Office stages reached at minute 7.1 / 22.0 / 63.9 / 130.8; lowest cash $1,710 at minute 7.7

Opt vs casual revenue: ×1.16 at 60 min, ×1.66 at 180 min (opt is already at Global HQ), ×1.13 at 240 min. Both plateau, at $135k and $124k/min. The jet was bought at 150.8 min.

### 9.3 (c) Casual, joining a server that is 60 minutes old — `out_V_main_late60.txt`

| min | money $ | revenue $/min | running cost $/min | wages (share) | B2B $/min (accounts) | staff (R E C G) | office | best model | live lines | NPC best |
|---:|---:|---:|---:|---:|---:|---|---|---|---|---:|
| 0 | 11,000 | 0 | 0 | 0 (0%) | 0 (0) | 0 (R0 E0 C0 G0) | 1 Garage | - | - | 61.8 |
| 5 | 11,269 | 3,219 | 592 | 531 (16%) | 0 (0) | 3 (R1 E1 C1 G0) | 1 Garage | s500m 47.1 | gen | 61.8 |
| 10 | 5,094 | 9,273 | 2,052 | 1,782 (19%) | 450 (1) | 8 (R2 E2 C2 G2) | 2 Founder HQ | s500m 47.4 | gen/dev | 61.8 |
| 20 | 36,650 | 17,027 | 5,286 | 4,770 (28%) | 2,025 (3) | 24 (R6 E6 C6 G6) | 2 Founder HQ | s1b 56.4 | gen/dev | 61.8 |
| 30 | 81,585 | 18,203 | 5,371 | 4,770 (26%) | 2,025 (3) | 24 (R6 E6 C6 G6) | 2 Founder HQ | s3b 59.4 | gen/dev | 61.8 |
| 45 | 57,621 | 34,082 | 11,635 | 10,089 (30%) | 2,775 (4) | 52 (R12 E13 C15 G12) | 3 Startup Campus | s3b 64.3 | gen/stu/dev | 61.8 |
| 60 | 40,071 | 42,945 | 15,675 | 12,330 (29%) | 5,475 (6) | 64 (R15 E16 C18 G15) | 3 Startup Campus | s7b 76.5 | dev/gen/stu | 61.8 |
| 90 | 51,547 | 51,835 | 19,102 | 14,598 (28%) | 7,275 (7) | 75 (R20 E22 C18 G15) | 4 Innovation | s7b 88.4 | gen/dev/stu/bus | 61.8 |
| 120 | 61,261 | 72,393 | 30,457 | 24,831 (34%) | 13,125 (9) | 128 (R38 E43 C25 G22) | 4 Innovation | s7b 99.0 | dev/gen/stu/bus | 61.8 |
| 180 | 184,436 | 71,989 | 33,961 | 27,279 (38%) | 17,025 (10) | 139 (R38 E53 C25 G23) | 5 Global HQ | s7b 99.0 | gen/dev/bus/stu | 61.8 |
| 240 | 2,561,416 | 117,246 | 47,277 | 38,160 (33%) | 33,525 (13) | 192 (R38 E85 C32 G37) | 5 Global HQ | s7b 99.0 | gen/dev/bus/stu | 61.8 |

Office stages reached at minute 7.6 / 31.6 / 84.7 / 174.9; lowest cash $1,761 at minute 3.2

The NPC labs are at 61.8 from minute 0 (the band). The curve is the fresh-server curve within ±6 % at every row up to 120 min.

Further late joins:
- server 180 min old (`C_late180`): stages 7.9 / 28.6 / 82.8 / 167.4, $85,220/min at 180;
- opt joining at 60 (`C_optlate60`): 7.5 / 18.7 / 61.4 / 128.3.

Today's game for comparison (same bot, `C_baseline_late60`): at most $7/min from the start.

### 9.4 Seeds × start hours (36 runs, 180 min each) — `out_V_B_*.txt`

Four RNG seeds (training noise, events) × three start hours (08:36, 12:00, 16:53). "16.9" = 16:53, when night falls after 100 s.

| run | Founder HQ | Startup Campus | Innovation | Global HQ | $/min at 5 / 10 | income min 5-10 (recurring) | wages % at 30/45/60/90/120 | $/min at 180 | lowest cash |
|---|---:|---:|---:|---:|---|---|---|---:|---:|
| casual_s11_h12 | 10.8 | 29.1 | 81.0 | 163.2 | 2,661 / 7,778 | 7,707 (5,907) | 24/35/25/28/28 | 101,346 | 1,651 |
| casual_s11_h16.9 | 8.2 | 24.9 | 79.5 | 159.9 | 3,296 / 9,037 | 9,608 (6,208) | 33/33/29/32/33 | 95,889 | 1,564 |
| casual_s11_h8.6 | 10.5 | 31.9 | 85.4 | 163.4 | 3,109 / 6,873 | 8,266 (6,466) | 25/27/29/26/32 | 93,183 | 1,635 |
| casual_s23_h12 | 10.7 | 32.0 | 95.7 | 165.9 | 2,708 / 7,738 | 7,765 (5,965) | 22/35/26/22/30 | 98,827 | 1,526 |
| casual_s23_h16.9 | 9.5 | 31.3 | 84.6 | 168.3 | 3,174 / 7,816 | 9,007 (6,207) | 26/28/29/28/32 | 82,209 | 1,524 |
| casual_s23_h8.6 | 10.4 | 29.1 | 76.5 | 165.2 | 3,238 / 6,951 | 8,400 (6,600) | 27/28/28/34/32 | 87,353 | 1,521 |
| casual_s4242_h12 | 10.6 | 29.5 | 80.2 | 167.9 | 2,885 / 7,672 | 7,835 (6,035) | 24/33/23/29/29 | 99,566 | 1,597 |
| casual_s4242_h16.9 | 7.5 | 32.1 | 83.2 | 167.1 | 3,254 / 9,307 | 9,852 (6,452) | 26/31/27/28/34 | 80,860 | 1,792 |
| casual_s4242_h8.6 | 10.2 | 31.9 | 84.2 | 168.1 | 3,368 / 6,898 | 8,485 (6,685) | 25/27/29/27/34 | 84,348 | 1,528 |
| casual_s7_h12 | 10.9 | 28.3 | 78.4 | 159.2 | 2,801 / 7,517 | 8,303 (6,503) | 23/37/23/30/29 | 117,036 | 1,558 |
| casual_s7_h16.9 | 9.4 | 28.0 | 83.8 | 168.4 | 3,151 / 8,104 | 9,120 (6,320) | 24/29/27/29/34 | 81,130 | 1,798 |
| casual_s7_h8.6 | 10.2 | 31.5 | 86.2 | 165.6 | 3,277 / 7,113 | 8,577 (6,777) | 27/28/27/26/32 | 87,195 | 1,542 |
| late60_s11_h12 | 10.8 | 31.3 | 93.5 | 171.1 | 2,685 / 7,763 | 7,703 (5,903) | 23/33/25/22/30 | 92,742 | 1,536 |
| late60_s11_h16.9 | 11.1 | 29.1 | 82.2 | 164.3 | 3,459 / 5,474 | 7,059 (5,259) | 25/30/28/31/34 | 89,942 | 1,567 |
| late60_s11_h8.6 | 10.4 | 35.6 | 87.9 | 174.9 | 3,137 / 7,068 | 8,431 (6,631) | 25/26/29/25/34 | 74,495 | 1,631 |
| late60_s23_h12 | 10.8 | 28.9 | 85.4 | 169.8 | 2,752 / 7,700 | 7,718 (5,918) | 23/33/24/24/27 | 95,365 | 1,539 |
| late60_s23_h16.9 | 9.9 | 31.7 | 86.4 | 166.0 | 3,261 / 7,212 | 8,956 (6,156) | 24/31/27/25/34 | 85,911 | 1,554 |
| late60_s23_h8.6 | 10.5 | 35.4 | 76.8 | 170.8 | 3,222 / 6,719 | 8,209 (6,409) | 25/26/27/34/34 | 78,628 | 1,523 |
| late60_s4242_h12 | 10.6 | 33.3 | 90.3 | 172.2 | 2,857 / 7,649 | 7,807 (6,007) | 19/30/24/24/29 | 84,008 | 1,577 |
| late60_s4242_h16.9 | 7.6 | 31.8 | 84.9 | 164.9 | 3,219 / 9,273 | 9,802 (6,402) | 26/30/28/27/34 | 87,001 | 1,762 |
| late60_s4242_h8.6 | 10.2 | 29.1 | 76.3 | 165.8 | 3,244 / 6,953 | 8,493 (6,693) | 26/30/28/34/33 | 88,693 | 1,639 |
| late60_s7_h12 | 10.7 | 28.6 | 96.0 | 171.3 | 2,764 / 7,876 | 7,865 (6,065) | 25/36/26/23/29 | 91,371 | 1,584 |
| late60_s7_h16.9 | 9.8 | 23.9 | 78.9 | 163.8 | 3,657 / 7,588 | 9,255 (6,455) | 30/35/28/35/34 | 89,425 | 1,538 |
| late60_s7_h8.6 | 10.2 | 32.4 | 81.8 | 169.2 | 3,238 / 7,087 | 8,532 (6,732) | 25/28/28/30/34 | 81,261 | 1,514 |
| opt_s11_h12 | 10.2 | 23.4 | 69.3 | 130.6 | 2,583 / 8,492 | 8,253 (6,453) | 27/27/20/27/24 | 148,214 | 1,671 |
| opt_s11_h16.9 | 10.7 | 22.0 | 65.0 | 126.2 | 2,635 / 6,182 | 7,637 (5,837) | 29/28/24/29/28 | 121,632 | 1,884 |
| opt_s11_h8.6 | 9.8 | 25.6 | 57.6 | 130.0 | 3,099 / 7,754 | 9,970 (7,170) | 25/24/21/28/28 | 131,832 | 1,645 |
| opt_s23_h12 | 10.1 | 25.6 | 66.1 | 128.6 | 2,522 / 8,256 | 8,176 (6,376) | 25/29/20/27/24 | 152,184 | 1,729 |
| opt_s23_h16.9 | 8.9 | 22.3 | 61.9 | 126.7 | 2,541 / 7,901 | 9,715 (6,315) | 32/26/24/28/29 | 116,926 | 1,559 |
| opt_s23_h8.6 | 9.7 | 25.7 | 64.6 | 129.6 | 2,941 / 7,575 | 9,788 (6,988) | 26/24/25/28/30 | 138,413 | 1,529 |
| opt_s4242_h12 | 8.6 | 26.5 | 71.2 | 134.2 | 2,631 / 9,546 | 8,621 (5,821) | 21/30/21/27/25 | 150,869 | 2,094 |
| opt_s4242_h16.9 | 7.1 | 22.0 | 63.9 | 130.7 | 3,199 / 9,020 | 10,180 (6,780) | 28/29/24/28/27 | 136,356 | 1,703 |
| opt_s4242_h8.6 | 9.6 | 28.1 | 57.4 | 127.2 | 3,308 / 8,255 | 10,137 (7,337) | 22/23/22/28/28 | 138,996 | 1,658 |
| opt_s7_h12 | 10.3 | 29.9 | 70.4 | 136.1 | 3,434 / 7,588 | 7,967 (6,167) | 20/29/21/27/25 | 158,855 | 1,549 |
| opt_s7_h16.9 | 9.2 | 26.5 | 63.3 | 127.1 | 3,988 / 9,286 | 10,605 (7,205) | 22/29/23/30/28 | 140,692 | 1,569 |
| opt_s7_h8.6 | 9.6 | 26.7 | 64.7 | 126.5 | 3,213 / 8,560 | 10,360 (7,560) | 24/25/24/29/28 | 141,210 | 1,655 |

Summary (min / median / max over 12 runs per profile):

| | Founder HQ | Startup Campus | Innovation | Global HQ | $/min at 5 | $/min at 10 | income 5-10 | wages 45-60 / 120-180 | lowest cash |
|---|---|---|---|---|---|---|---|---|---|
| casual | 7.5 / 10.3 / 10.9 | 24.9 / 30.4 / 32.1 | 76.5 / 83.5 / 95.7 | 159.2 / 165.8 / 168.4 | 2,661 / 3,162 / 3,368 | 6,873 / 7,705 / 9,307 | 7,707 / 8,442 / 9,852 | 24-30 % / 31-32 % | $1,521 |
| late60 | 7.6 / 10.4 / 11.1 | 23.9 / 31.5 / 35.6 | 76.3 / 85.2 / 96.0 | 163.8 / 169.5 / 174.9 | 2,685 / 3,220 / 3,657 | 5,474 / 7,400 / 9,273 | 7,059 / 8,320 / 9,802 | 23-28 % / 31-32 % | $1,514 |
| opt | 7.1 / 9.6 / 10.7 | 22.0 / 25.6 / 29.9 | 57.4 / 64.7 / 71.2 | 126.2 / 129.1 / 136.1 | 2,522 / 3,020 / 3,988 | 6,182 / 8,256 / 9,546 | 7,637 / 9,752 / 10,605 | 20-23 % / 27-28 % | $1,529 |

Wage share sampled at 30/45/60/90/120 min:

| Profile | Samples in 25-45 % | Below 25 % | Above 45 % | Median |
|---|---|---|---|---|
| casual | 52 of 60 | 8 (lowest 22 %) | 0 | 28 % |
| late60 | 50 of 60 | 10 (lowest 19 %) | 0 | 28 % |
| opt | 39 of 60 | 21 (lowest 20 %) | 0 | 27 % |

### 9.5 Office moves: staff at the move and net profit before and after

`net before` = average net profit in the 10 minutes before the move; then 5-20, 20-40 and 40-60 minutes after. The market cycle alone swings revenue by ±10 % every 5 minutes, so short windows are noisy.

| Run | Move | Staff at move | Net before | 5-20 after | 20-40 after | 40-60 after |
|---|---|---:|---:|---:|---:|---:|
| main casual | Startup Campus at 31.5 | 24 of 24 | 13,364 | 18,748 | 32,239 | 35,110 |
| main casual | Innovation at 85.7 | 64 of 64 | 33,884 | 36,975 | 50,592 | 50,027 |
| main casual | **Global HQ at 167.8** | 128 of 128 | 48,810 | 49,736 | **67,025** | **70,034** |
| main opt | Global HQ at 130.8 | 128 | 66,353 | 66,257 | 87,162 | 95,032 |
| main late60 | Global HQ at 174.9 | 128 | 51,445 | 47,568 (−8 %) | 66,408 | 69,412 |
| C_optlate60 | Global HQ at 128.3 | 128 | 68,278 | 69,600 | 79,222 | 100,491 |
| 12 opt seed runs | Global HQ at 126-136 | 128 | 60.9-66.7k | 66.5-73.9k | 81.0-92.1k | 81.5-99.4k |
| 24 casual/late60 seed runs | Global HQ at 159-175 | 128 | 48.2-52.5k | 41.3-51.0k (−20 % … +3 %, cut by the 180-min end) | – | – |

**Global HQ is never a net loss once it has run 20 minutes:** +30 % to +37 % net 20-40 minutes after the move in every 240-min run. In the first 5-20 minutes net can dip by up to 20 %:
- new staff are paid before the stage-5 clients (abroad, 2-day trips) sign;
- the reach cap rises only as Growth & Sales are hired;
- the window contains market-cycle lows.

Revenue itself does not fall: the per-minute trace in `--trace 155:195` (seed 4242, 12:00) shows 75k → 105k $/min within 25 minutes. The assistant must say so at the move ("New HQ: profit dips for ~15 minutes while 60 new people start").

Startup Campus is bought with 22-24 of 24 Founder-HQ desks filled in the casual seed runs (late60 20-24, opt 14-24), so its 64 desks are full 10-20 minutes later. This fixes the 4-staff campus of realism.

### 9.6 Brief targets: met or missed

| Target (brief §5 + judges) | Result | Verdict |
|---|---|---|
| Clear first goal, first $ fast | Goal bar; first release and first $ at 1.3 min; CloudDesk signed ≈ 5.3 min (the scripted 240-s trip leaves at ≈ 1.3 min) | **met** |
| ≥ $1-3k/min by minute 5-10 | casual $2,661-3,368 at 5 and $6,873-9,307 at 10 (12 runs); late60 $2,685-3,657 / $5,474-9,273; slow player $3,134 / $6,392 | **met** (above the band) |
| Minutes 5-10 pay at least today's game | today, same bot: $6,867/min (`C_baseline`, window 5-10). Design: casual $7,707-9,852 (median 8,442), late60 $7,059-9,802, opt $7,637-10,605. Recurring part (no quests) median $6,386 (casual) = 7 % below today's all-recurring $6,867, but it keeps growing while today's collapses ($759/min at 30, $18 at 60). | **met** for total income; recurring part slightly below |
| Garage stage 8-12 min, every play style (judges) | 33 of 36 seed runs in 8-12; the 3 misses are 7.1 / 7.5 / 7.6 min (all seed 4242 at the 16:53 night start); slow player 12.0 / 12.5 | **mostly met** (3 runs up to 0.9 min short; slow player 0.5 min long) |
| "Office 2" = Startup Campus at 25-40 min (casual) | casual 24.9-32.1 (11/12 inside, one 0.1 min early); late60 23.9-35.6 (11/12, one 1.1 min early); slow 31.0; 4 casual players on one server 25.4-33.7 | **met** (2 runs ≤ 1.1 min early) |
| "Office 3" = Innovation at 70-100 min | casual 76.5-95.7, late60 76.3-96.0, slow 85.0, newcomer next to two veterans 99.0 | **met** (24/24) |
| "Office 4" = Global HQ at 2.5-3.5 h | casual 159.2-168.4, late60 163.8-174.9, slow 175.0; opt 126-136 (a skilled player is 2.1-2.3 h) | **met** for casual (24/24); opt faster by design |
| No collapse | worst drop between two report minutes: −5.2 % (normal runs), −11 % (no-hire probe); lowest cash in any of the 56 design runs $1,514; outage shock (−50 % users, −$25k) and fine shock (−90 % cash) both recover with stage times within 7 min of the unshocked run | **met** |
| No runaway, bounded growth | casual 118.9k / 123.0k / 124.6k $/min at 240 / 300 / 360; opt 136.2k at 180, 134.6k at 240. Hard bounds: `STAGE_REACH` × pools, capacity, B2B ceiling $41k/min, 99 stat cap | **met** (cash piles up late, see risks) |
| Wages 25-45 % of revenue in the mid game | casual 52/60 samples in band (median 28 %), windows 24-30 % (45-60) and 31-32 % (120-180); opt 39/60 (median 27 %, window 45-60 at 20-23 %) | **met** for casual; opt runs leaner (20-23 % at 45-60 min) |
| Late joiner OK | NPC band identical on every server (61.8); late60 within ±6 % of fresh; server 180 min old same stage times; newcomer next to an opt veteran (`D_vet_new60`, weight 0.15): 11.6 / 36.9 / 100.2 / not by 180 (weight 0: 8.7 / 21.1 / 78.6 / 162.9; weight 0.3: 11.8 / 34.8 / 93.7 / 178.4); newcomer next to two veterans: 7.8 / 34.4 / 99.0 / 178.3 | **met**, with a measured 7-9 % revenue cost of a veteran at minute 60 |
| Staff decisions matter | no hires: $21,958/min at 180 vs $82,168 (×3.7), net at 60 $11.8k vs $29.5k (×2.5), never reaches Global HQ; HR budget 25 %: $59.8k at 180 and no Global HQ by 180; 55 %: same as 40 % (needs bind) | **met** (note: a no-hire company buys Campus/Innovation earlier, 20.5 / 72.6 min, by saving instead of investing, then stalls) |
| Several live models meaningful | one-line probe: $56.5k vs $82.2k at 180 (−31 %), Global HQ 179.1 vs 167.8 min; clone test ×1.04-1.08 vs specialists ×1.47-1.51 | **met** |
| Global HQ not a net loss | +30-37 % net 20-40 min after the move (all 240-min runs); a dip of up to 20 % in the first 5-20 min | **met after 20 min** |
| Model overall ≤ 99 | best model 99.0 at most in all runs | **met** |
| Watched = unwatched | by construction: money reads only saved data and the clock | **met (design)** |

### 9.7 Stress, multiplayer and probes (180 min unless stated)

| Run | Stages | $/min at 30 / 60 / 180 | Net at 60 / 180 | Note |
|---|---|---|---|---|
| `C_nohire` (never hire) | 7.2 / 20.5 / 72.6 / – | 12,291 / 13,843 / 21,958 | 11,849 / 17,752 | stalls at stage 4 |
| `C_overhire` (hire to cap whenever cash allows) | 9.2 / 30.7 / 82.6 / 155.6 | 16,063 / 44,979 / 103,400 | 28,985 / 47,331 | lowest cash $2,094: over-hiring cannot bankrupt |
| `C_oneline` (one product line) | 7.5 / 35.6 / 86.0 / 179.1 | 13,638 / 36,744 / 56,460 | 21,813 / 26,404 | several lines pay |
| `C_hr25` / `C_hr55` | 7.5 / 30.7 / 84.7 / – and 7.5 / 32.1 / 82.7 / 167.8 | 15,075 / 38,408 / 59,845 and 18,368 / 45,968 / 82,356 | 27,712 / 38,918 and 30,218 / 43,423 | the slider matters downward |
| `C_slow30` (acts every 30 s) | **12.0 / 31.0 / 85.0 / 175.0** | 17,206 / 42,972 / 71,750 | 27,433 / 37,922 | human-like: all windows hold |
| `C_slow30_late60` | 12.5 / 21.5 / 85.0 / 173.5 | 14,479 / 44,142 / 73,496 | 28,518 / 38,885 | |
| `C_shock_outage45` (users −50 %, −$25k at 45) | 7.5 / 31.5 / 84.5 / 174.6 | 18,223 / 45,351 / 71,781 | 29,794 / 37,587 | recovers |
| `C_shock_fine60` (cash −90 % at 60) | 7.5 / 31.5 / 83.5 / 166.5 | 18,223 / 45,185 / 86,703 | 29,532 / 46,938 | cash stays > 0 |
| `D_4casual` (4 casual companies, one server) | 7.9-10.5 / 25.4-33.7 / 82.0-86.5 / 164.8-176.8 | 17,184-19,964 / 42,625-45,091 / 70,409-85,283 | | equals cost each other 0-6 % |
| `D_vet_new60` w 0 / 0.15 / 0.3 (newcomer) | 8.7 / 21.1 / 78.6 / 162.9 · 11.6 / 36.9 / 100.2 / – · 11.8 / 34.8 / 93.7 / 178.4 | 19,855 / 43,412 / 93,755 · 14,270 / 39,896 / 75,744 · 16,866 / 39,385 / 68,713 | | the veteran keeps 130.6-134.2 for Global HQ in all three |
| `D_2vet_new120` (newcomer at server minute 120, two opt veterans) | 7.8 / 34.4 / 99.0 / 178.3 | 17,802 / 39,975 / 74,371 | 25,009 / 42,433 | |
| `C_baseline` (today's game, same bot) | none | 759 / 18 / 1 | −352 / −369 | collapse; cash −$41,880; NPC best 213 |
| `C_baseline_late60` | none | 2 / 1 / 1 | −9 / −9 | |
| `E_clonetest` | – | – | – | table in 3.1 |

The three D_vet runs differ in bot path as well as weight (w 0.3 gave the newcomer an earlier Global HQ than w 0.15), so the weight effect is within run-to-run noise. **Decision: `PLAYER_RIVAL_WEIGHT = 0.15`.** Players still compete a little for users; a veteran, a Robux buyer or a crowded server can never take more than that share of anyone's market.

---

## 10. Risks, and what to cut first

### Risks
1. **Bots are lower bounds.** Both bots react every 1 s and follow Save mode perfectly. The slow-player runs (`--think 30`, 9.7) show the size of the effect. All prices are single knobs (`P.prices`); re-tune after a play-test, not before.
2. **The garage length depends on the start hour.** A night start lets the scripted CloudDesk pilot sign during the night, so the garage can end at ~7 min (bot). A day start that misses the 15:00 departure window for the second client waits up to 9.5 min. The goal bar makes the wait readable ("CloudDesk signs at 12:10"). Lever: price `P.prices[2]`. Sweep of the 12 casual seed × hour runs (`sweep_garage.sh`): median garage length 9.8 min at $24k, 10.2 at $26k, 10.3 at $27k and 13.3 at $28k. It jumps above $27k because the second pilot fee is then needed.
3. **Late cash piles up.** Lab levels ($1.09M) and the jet ($0.9M + $8,500/day) absorb part of it; casual still holds $3.3M at 240 min and opt $8.1M. The next sinks are spec only:
   - a **Port Meridian branch office** (stage 5, $3,000,000, upkeep $12,000/day, +2 client slots = at most +$1,350/min, a visible tower floor with the company logo);
   - guest-house suites ($150k, cosmetic);
   - cosmetics.
   None raises income materially.
4. **Multiplayer.** With `PLAYER_RIVAL_WEIGHT = 0.15` all other players together count as 0.15 of one company per segment. A veteran costs a newcomer about 8-10 % of revenue at minute 60 (9.7). With 12 players on a server the weight is still 0.15 in total, by construction. The 4-casual run in 9.7 shows the effect of equals.
5. **Unsimulated pieces** and their bound:
   - room quality Q (+0-10 % output);
   - night shift (only pays above seats, which HR never exceeds);
   - parallel training (v2);
   - rack faults (−1 GPU unit for 60-300 s);
   - founder joins a meeting (+0.15 trust);
   - phones, drivers and apprentices (< 0.7 % of costs together);
   - unpaid leave (never triggered);
   - the branch office.
   Each is a bounded multiplier or a < 1 % cost line.
6. **Save and rollout.** DATA_VERSION 6 is a one-way step: a server on old code kicks players whose save is already v6 (data_ui pitfall 5). Ship the server code before the first v6 save. The migration changes only `empire.office` and adds `trainings`; every other new field is a pure addition filled by `EmpireMath.new` + `Template.migrate`.
7. **Bandwidth.** New replicated state must follow 11.8 (LAZY paths, capped lists).
8. **Stage-5 data desks.** Curator seats stay 32 at T2-T4, so HR stops curators at 32 (need = seats). Data is not a bottleneck in any run. If more curators are wanted, the building needs more data desks.

### Cut first if time runs out (each cut leaves section 9 essentially unchanged)

| Order | Cut | Fallback |
|---|---|---|
| 1 | Parallel training (v2) | 1 slot (already v1) |
| 2 | Night shift toggle, room quality Q, rack faults | Q = 1, no faults (= the sim) |
| 3 | Company jet | Abroad trips by airline only (sim shows jet < 1 % of costs) |
| 4 | Guest-house paying guests | Building kept as the hosted-pilot venue (+0.10 trust) |
| 5 | Drivers, apprentices, phone cost | Plain ops posts |
| 6 | Hosted pilots | All pilots travel (trip cost +$1-3k over 4 h, −0.10 trust on those visits) |

**Never cut** (they hold the economy together):
- the NPC band;
- `STAGE_REACH` + `reachCap`;
- the company nest + one model per line + line penalty;
- additive capped refinement and the 99 cap;
- schedule-based staff output (watched = unwatched);
- flat hiring fees + wages per day;
- the B2B catalogue with slots and field reps;
- the garage gate;
- the migration clamp fix.

---

## 11. Interfaces for subsystem designers

These are the numbers and functions the subsystem specs must use. The source of truth in code is `ReplicatedStorage/Shared/CompanyOps.module.luau` (copy `agents/design_final/economy/proposed/CompanyOps.module.luau`; `B2B_SCALE` and `UPKEEP_SCALE` are simulator knobs and stay 1; the module type-checks with 0 diagnostics under luau-lsp `--!strict` once `MarketConfig.STAGE_REACH` exists). Never re-derive a number in a subsystem; require `CompanyOps` or the config named here.

### 11.1 Calendar and HR
- **Clock:**
  - `CompanyOps.DAY = 1200`;
  - `CompanyOps.hour(clock)` with `clock = workspace:GetServerTimeNow()`: 900 s for 08-18, 300 s for 18-08;
  - `CompanyOps.timesheet(h)`, `CompanyOps.TS_MEAN = 0.5538`, `CompanyOps.duty(clock)`;
  - company date `CompanyOps.advanceCalendar(e, clock)` → `empire.calendar.day`;
  - stamps `CompanyOps.stamp(e, clock)` → "day 8 11:54".
- **Availability:**
  - `CompanyOps.AVAILABILITY = 0.90`;
  - vacation `vday(seed, cycle) = Employee.hash(seed*31 + cycle) % 12`, `cycle = floor(day/12)`;
  - sick `Employee.hash(seed*7919 + day) % 1000 < 17`;
  - HR collision cap `ceil(0.10·team)` per department and day; overflow moves to the next free day of the cycle, highest seed first.
  - A person absent today is `OffDuty`, desk released, `employees[role]` unchanged.
- **Who is on duty** (animation only): seed shifts `EmployeeConfig.personalityFromSeed`, plus absences, plus the night crew 22:00-06:00. Ops posts follow the day shift with relief; at stage 5 security and IT have a night rota.
- **Auto-HR:**
  - `CompanyOps.hrNeed(e, role)` (needs: 8.1), with `GROWTH_OFFICE_MAX = 24`, `RESEARCH_AFTER = 0.25`;
  - wage budget slider 0.25 / **0.40** / 0.55 of the 5-minute trailing income; one hire per 20 s; 3 starter hires always allowed;
  - Save mode: HR stops at 50 % of desks.
- **Pay:**
  - wages per game day: researcher 3,600, engineer 4,320, curator 2,700, Growth & Sales 4,320 (× profile `w`);
  - night crew ×1.3;
  - ops posts `EmployeeConfig.OPS_WAGE_PER_DAY = 720`;
  - Training Lead $900/day;
  - apprentices: wage 0.4×, skill 1 rising +1 per 3 company days to 3, graduation after 9 days (k = 3, w = 1). They are kept in `empire.apprentices[tostring(seed)] = {day = hireDay}`, never in the profile.
  - Hiring fee: apprentice 50 %, agency hire flat `ROLES.price`.
- **Posts per stage:** 5.5 (8 / 12+2 / 14+2 / 16+2).
- **Unpaid leave** trigger: cash < −2 × daily payroll; release: cash > 1 × daily payroll; `empire.unpaidLeave` (count of newest hires).

### 11.2 Customers, trips, fleet, hotel costs
- **Catalogue:** `CompanyOps.CLIENTS` (3.2). Map a client to its building **by name**: `CityPlan.clientOffice(client.name)` (case-insensitive name lookup; all 18 names exist). Do not map by id: Orbit Games is `orbit` and Frontier Science is `frontier` in CityPlan's business keys, while the catalogue uses `orbitgames` and `science` (`frontier` = Orbit Systems, as in the old CONTRACTS).
- **Constants:**

| Constant | Value |
|---|---|
| `PILOT_DAYS` | 1 |
| `TERM_DAYS` | 6 |
| `RENEW_LEAD_DAYS` | 0.5 |
| `ACCOUNTS_PER_REP` | 2 |
| `FOUNDER_ACCOUNTS` | 2 (city only) |
| `DEPART` | 08:00-15:00 |
| `CASH_MARGIN` | 500 |
| `FIRST_CLIENT_TRUST` | 0.5 |
| `FLEET_LEASE` | 100 $/day per field car |

- **Trips:** `TRIPS.city {0.2 day, crew 1, fuel 30}`, `region {1 day, crew 2, 1 night, hotel 140, fuel 90}`, `abroad {2 days, crew 2, 2 nights, hotel 220, flight 700, fuel 40}`, `PER_DIEM = 50` per traveller per started day.
  - Hosted pilot `HOSTED {nightCost 60, guests 2, nights 2, trust 0.10}`.
  - Jet `JET {price 900000, stage 4, pilots 2, pilotWage 3000, upkeep 2500, fuel 1500, days 1.5, nights 1, trust 0.05}`.
  - Functions: `CompanyOps.tripPlan(kind, crew, hosted, jet) → duration s, nights, cost`; `CompanyOps.trustGain(e, data, client, hosted, founder)`.
- **Who travels:**
  - city pilot: 1 field rep (or the founder in the garage);
  - region/abroad pilot: field rep + 1 engineer. In the game both travellers count as absent for the trip (excluded from O like vacation). The sim does not remove the engineer: at most 3 engineers of 16-85, i.e. ≤ 2-6 % of engineering output while trips run.
  - check-ins: 1 rep.
  - Field reps = `CompanyOps.fieldReps(e)` = the first `n` Growth & Sales profiles in `staffProfiles.marketer`.
- **Visible travel** (world package):
  - city/region: a leased compact leaves the B1 bay through the barrier and parks at the client's `parking` bay;
  - region adds a City Hotel night (`CityPlan.CITY_HOTEL`);
  - abroad: car to `CityPlan.AIRPORT.carParkBays`, the shuttle (or the company jet) to Port Meridian, 2 nights at `CityPlan.INTL_HOTEL`.
  - Economic durations are fixed in game days and do **not** wait for the shuttle timetable. The visible shuttle only shows them when players are near.
- **Saved state** `empire.deals`:
  - `accounts[id] = {expires, since, founder, renewing}`, `trust[id]`;
  - `tripList[] = {client, kind = "sign"|"renew", back, founder, hosted}`;
  - counters `signed, lost, nights, trips, reserved, pilots, hosted, flights, jetFlights`;
  - `news[]` (≤ 40 strings, newest first).
- **Money:** pilot fees `applyFlow(s, fee, 0, "pilot")`; retainers category `b2b`; costs `trips`, `fleet`, `b2bserve`.

### 11.3 Guest house
- `CompanyOps.GUEST = {rooms = 12, occupancy = 0.6, rate = 300, utilities = 400, staff = 2}`; net +$320/game day; from stage 3 (`Plan.HOTEL_MIN_TIER = 2`).
- Hosted pilots: every 2nd region/abroad pilot of a field rep (`deals.pilots % 2 == 1`). The client team (2 NPC guests) arrives at 18:00, sleeps 2 nights, holds the workshop in `hotel_workshop`/boardroom, and adds +0.10 trust.
- Attributes: `HotelRooms = 12`, `HotelGuests = round(12·0.6) + 2·(hosted teams in house)`.
- Posts OpsIndex 13 (Hotel Reception) and 14 (Housekeeping), $720/day each.

### 11.4 World map (city, airport, abroad)
- Trip tiers ↔ zones:
  - city and region = Business City downtown (14 offices; region adds the City Hotel night);
  - abroad = Port Meridian (4 towers: Helix Research, Orbit Systems, Nova Infrastructure, Frontier Science);
  - abroad unlocks at **stage 4**, region at stage 3.
- `CityPlan.TRAVEL.ticket = 700`: the player's own return ticket, the same as `TRIPS.abroad.flight`.
- `City.TIME_ZONE_OFFSET = 0` (same time zone, one Lighting clock).
- The company jet (stage ≥ 4, $900,000) parks in the airport hangar and is flown by 2 company pilots ($3,000/day each, inside `JET`). The public shuttle stays free for players with a ticket.
- Drivers (ops/fleet job, $720/day; 1 from stage 2, 2 from stage 4): the number of simultaneous chauffeur rides = number of drivers. No economic effect beyond their wage.

### 11.5 Staff life, chef, talk, animation, work items
- StaffService **never** writes money or `Workforce.set`. Department output comes from `WorkforceMath.count` (5.1).
- Screens and talk read:
  - `CompanyOps.seats(e, role)`, `CompanyOps.morale(e)`, `CompanyOps.fieldReps(e)`, `CompanyOps.capacity(data)`;
  - `live.ops` (`b2b`, `accounts`, `travelling`, `reps`, `ops`, the cost/min of each category);
  - `live.waitlist`, `live.capacity`, `live.load`.
- Kitchen: lunches per day 120 / 145 / 205 / 235 (stage 2-5); `LunchesServed` is the real count; morale formula 5.4.
- Department screen line: "⟨Dept⟩ · staffed/seats · output · morale %", e.g. "AI Research · 10/12 · +5.6 RP/s · 104 %".
- **Work items** (request 15): each employee's item and its progress source:
  - training run → `trainingRate`;
  - research project → RP/s;
  - dataset batch → curated tokens/s;
  - campaign → `O_g`;
  - client deal → `deals.trust[id]`;
  - support tickets → live users of their line;
  - hotel guests → `HotelGuests`.
  Aggregate per department, never per employee per frame.
- Ops pay for talk lines: `OPS_WAGE_PER_DAY = 720`.

### 11.6 Models
- **Lines and versions:**
  - `MarketConfig.PRODUCT_SLOTS = {1,2,3,4,4}`;
  - `LINE_OF = {developers="developers", students="students", businesses="businesses", general="consumers"}`;
  - `LINE_PENALTY = 0.6`; `NEST_LAMBDA = 0.05`; `MIGRATE = 0.9` (users moved to the successor).
- **Market constants:** `AGE = {maxFit = 8, full = 3600}`; fit soft cap 75 / slope 0.35; `FIT_SCALE = 30`; `SERVE_UNITS = {s100m 0.5, s500m 1, s1b 1.4, s3b 2.2, s7b 3}`.
- **Refinement:** `REFINE_LIMIT = 3`, cost × (1 + 0.5·it), gain (1 + 4q)·qualityMod/√(1 + it), stays live.
- **Stats:** every core stat ≤ 99.
- **Lab levels:** pts `200·1.35^L`, cash `6000·1.6^L`, +1 core, max 10.
- **Training slots:** v1 = 1 (`data.training`); v2 slots `min({1,1,2,3,4}[stage], 1 + ⌊O_eng/8⌋)` in `data.trainings["2".."4"]`.
- `GameConfig.MODEL_LIMIT = 80` (non-retired only).
- **Pricing:** Recommended / auto-price menus sub {5, 10}, API {1, 2, 3, 4}, marketing ≤ $5,000 at release; auto-price period 300 s, forecast horizon 900 s.
- **Model chat** (request 16) reads `model.name/stats/overall/sizeId/focusId` only and has **no** economic effect.

### 11.7 Shop (Robux)
- Cash packs: share of the **next** office price: Seed 0.25, Series A 0.75, Series B 2.0.
  - Garage: $6,750 / $20,250 / $54,000.
  - At stage 5: base = 1.9M × `ShopConfig.CASH.topFactor` = **1.0** (was 3.5), because there is nothing left to buy but sinks.
  - `CASH.minimum = 2,000`.
- `ShopConfig.INVESTOR_MULTIPLIER = 1.10` (was 1.2). It applies to the player's own **market** revenue after shares (`MarketService.tick:187`), never to B2B, never to other players.
- Never sell: market share, hype, NPC changes, B2B trust.
- Executive Limo pass: cosmetic car. Headhunter voucher: one applicant with k ≥ 4.

### 11.8 Tech, network, save
- **Remotes** (add to `Net.FUNCTIONS`; bind with `{burst = 4, perSecond = 2, company = true}`):
  - `DealAction {action = "pin" | "skip" | "joinMeeting", clientId}`;
  - `EmpireAction {action = "labLevel" | "buyJet" | "hrBudget" | "hrAuto" | "nightShift" | "saveMode" | "autoPrice", ...}`.
  - Errors: `FIRST_CLIENT`, `LINE_LIMIT`, `REFINE_LIMIT`, `MAX_LEVEL`, `PREREQUISITE`, `NO_POINTS`, `OWNED`, `OFFICE`, `NO_MONEY` (English texts in `ActionController`).
- **Tick order** (`Main.server.luau` per-session loop): `AIModelService.tick` → `MarketService.tick` → `StudioService.tick` → `EmpireService.tick` (wages, then `CompanyOps.step`). `MarketService.tickGlobal` keeps only the API-access marketplace (the lease auction is removed).
- **Money API:** `EconomyService.applyFlow(session, revenue, cost, category?)`. The 4th argument is optional; the default is "market". It adds to `empire.ledger` (Appendix A).
- **Replication:**
  - `SessionService` LAZY paths (5 s): `empire.deals.news`, `empire.deals.trust`, `empire.ledger`, `live.ops`, `live.waitlist`, `live.load`.
  - News is capped at 40 (client shows 20) and the ledger at 7 days × ≤ 24 categories.
  - Budget: the new persistent fields add ≤ 6 KB to a full snapshot (deals ≤ 3 KB, ledger ≤ 2.5 KB, the rest < 0.5 KB) and ≤ 0.5 KB/s per player in deltas. Check with `tests/net/test_e2e.luau` (12 players ≤ 15 KB/s today).
- **Save:** DATA_VERSION 6, `MIGRATIONS[5]` (2.4), clamp fix, defaults and cleaners (Appendix A). No new staff-profile fields.

---

## Appendix A: new and changed data fields

| Field | Default (`EmpireMath.new` / `Template.new`) | `Template.migrate` cleaner |
|---|---|---|
| `empire.office` | 1 | migration +1 (2.4); clamp `1..#OFFICES` |
| `empire.calendar` | `{day = 1}` (`index` set on first tick) | table; `day` integer ≥ 1; `index` number or nil |
| `empire.deals` | `{accounts = {}, trust = {}, tripList = {}, news = {}, signed = 0, lost = 0, nights = 0, trips = 0, reserved = 0, pilots = 0, hosted = 0, flights = 0, jetFlights = 0}` | drop accounts/trust whose id is not in `CLIENTS`; `tripList` ≤ 16 entries with valid client and kind; `news` ≤ 40 strings ≤ 120 chars; numbers finite ≥ 0 (`CompanyOps.ensure` does the type part) |
| `empire.labLevel` | 0 | integer 0..10 |
| `empire.jet` | false | boolean |
| `empire.hr` | `{auto = true, budget = 0.40}` | budget ∈ {0.25, 0.40, 0.55} |
| `empire.saveMode` | `"auto"` | "auto" or "off" |
| `empire.nightShift` | `{}` | keys ∈ department ids, values true |
| `empire.apprentices` | `{}` | keys = tostring(seed) of existing profiles; `{day}` integer |
| `empire.unpaidLeave` | 0 | integer 0..staff |
| `empire.ledger` | `{}` | ≤ 7 day keys (tostring(day)); each ≤ 24 categories; numbers finite |
| `data.trainings` | `{}` | string keys "2".."4" only (empty in v1) |
| `model.market.vage` | 0 at release | number ≥ 0 (older live models: = `age`) |
| `model.replacedBy` | nil | valid model id or nil |
| `model.release.auto` | true | boolean |
| `empire.contracts`, `customers`, `businessRevenue` | kept | ignored (compatibility) |

There are no new `staffProfiles` fields (absences are hashes, apprentices are a separate map).

## Appendix B: tuning knobs (all in `patches_final.luau` `P` or `CompanyOps`)

| Knob | Value | Effect |
|---|---|---|
| `OFFICES.price` | 0 / 27k / 100k / 380k / 1.9M | stage timing (garage length vs Founder-HQ price: risk 2) |
| garage gate | first signed client | minimum garage length |
| `START_MONEY` | 10,000 | garage cushion |
| `OFFICES.staff` | 5 / 24 / 64 / 128 / 240 | caps |
| `HardwareConfig.slots` | 3 / 6 / 12 / 24 / 48 (×1.5 cluster) | compute per stage |
| thermal | 20 × {0.5, 1, 2, 3, 4} × cooling | heat |
| `STAGE_REACH` / `BRAND_REACH` | 0.25/0.25/0.30/0.40/0.55 and 0/0.02/0.05/0.09/0.15 | market per stage (main anti-runaway) |
| reachCap | 0.20 + 0.012·O_growth,office | value of in-office Growth & Sales |
| `FIT_SCALE`, soft cap | 30; 75 / 0.35 | how much quality beats rivals |
| pools, `POOL_SCALE`, userScale | 250k/375k/60k/700k, ×1.5, 5e5 | market size |
| `NEST_LAMBDA`, `LINE_PENALTY` | 0.05, 0.6 | clone value, specialist value |
| `AGE` | 8 fit / 3600 s | version treadmill |
| `MIGRATE` | 0.9 | users kept by a successor |
| NPC band | ×1.2 start, 64 cap, API ≥ $1 | competition |
| `PLAYER_RIVAL_WEIGHT` | 0.15 | player-vs-player pressure |
| `CAP_PER_UNIT`, `ENG_CAP`, `ENG_K` | 15,000, 1.0, 20 | serving capacity |
| wages | 3.0 / 3.6 / 2.25 / 3.6 $/s | wage share |
| fees | 1,000 / 1,200 / 800 / 1,200 | hiring cost |
| `AVAILABILITY` | 0.90 | vacation + sick |
| morale | 0.95 / 1.035 / 1.05 / 1.05 / 1.05 | lunch and wellness |
| marketing | 1 + 0.4·(1 − e^{−O/10}) | Growth value |
| B2B catalogue, slots | 3.2; 2/4/7/10/14 | second engine; ceiling $41k/min |
| `ACCOUNTS_PER_REP`, `TERM_DAYS` | 2, 6 | field staff, trip load |
| upkeep | 300 / 2.5k / 9k / 24k / 48k per day | fixed cost per building |
| ops posts, `OPS_WAGE` | 0/8/12/14/16 (+2), 720 | fixed staff cost |
| `studioScale` | 0.5 | studio share |
| Lab levels | 200·1.35^L pts, 6000·1.6^L $, max 10 | researcher sink |
| jet | $900k + $8,500/day | late sink |

## Appendix C: simulator notes

**Simulated as real code** (patched real sources + the two proposed modules):
- the stage table, garage gate, start money, slots/thermal;
- market tick (nest, lines, ageing, reach caps, brand reach, capacity/waitlist, player weight), NPC band;
- wages, fees, ops posts, upkeep, food, fleet;
- the whole B2B pipeline with trips, hotel nights, flights, jet, hosted pilots, trust, renewals, capacity reservation;
- guest-house flows, studio per game day + the stall fix, refinement fix, stats cap, Lab levels;
- the duty curve for research and data, seat/overflow rule, availability, morale table;
- calendar, ledger categories.

**Bot behaviour** (`sim_final.luau`):
- claims quests; buys data by quality per dollar;
- trains the largest affordable size that its servers can serve, for the weakest line; releases with Recommended price (casual) or a full price + marketing search (opt);
- auto-price every 300 s; auto-HR (`hrNeed`, budget 0.40, 20 s gap); Save mode (8 min); GPU buys up to 60 % of free cash and "servers full" upgrades;
- research in a fixed order, then Lab levels; buys the jet only when the next office is already affordable;
- opt also refines up to 3×.

**Injected or approximated:** availability as its expectation 0.90 (not per person); morale as the full-staffing table; guest-house occupancy fixed at 60 %; the travelling engineer is not removed from engineering output.

**Not simulated:** visuals, parallel training, night shift, Q, rack faults, unpaid leave, founder meetings, phones/drivers/apprentices costs, Investor pass, branch office.

---

## Decisions (integrate, 2026-10-10)

Recorded by the integration lead before round 2b (requests corefix #12, staffops #5 and #10, apps #7 / #9). Where a
decision deviates from the text above, this section wins.

**From the econ/models build (corefix #12)**
- 2.4: `MIGRATIONS[5]` also empties `customers` / `businessRevenue` and normalises product lines: one live model per
  line (the best overall is kept, the others retire into it with `replacedBy`, users × MIGRATE plus organic growth
  move over); lines beyond `PRODUCT_SLOTS[stage]` with the fewest users go back to "trained" with their release data.
- 11.8 budgets at the caps: a news line is ≤ 80 bytes incl. the stamp (`CompanyOps.NEWS_CHARS`); the replicated
  ledger holds 4 of the 7 saved company days with ≤ 16 categories per side and day.
- 7.7 auto-price: the first cycle runs 150 s after the company starts ticking (the design bot's phase), then every 300 s.
- 5.5 / 10 rack faults: one fault takes 1 compute unit off line (`FAULT.units`), as written (the econ build first took
  whole GPUs).
- 11.1: the Training Lead ($900/day) is paid only while the company has apprentices; `Ops.graduate` drops
  `empire.apprentices` entries whose seed no current profile has (staffops #6), so stale entries never pay him.

**Staff calendar and operations (staffops #5)**
- 5.3 / 11.1: operations staff have no visible absences: HR relief covers vacation and sick days of a post, the post is
  never empty in opening hours. The covering day shift is 07:15–07:30 to 18:00–18:30 (seeded).
- 5.3: the company day a shift belongs to switches at 06:00 for the staff animation (people arriving at 07:45 work the
  day that starts at 08:00); the economy's calendar still advances at 08:00. "Who's away today?" lists the people of
  that shift day (06:00–08:00 already the coming day).
- 5.3: at the end of a shift an employee finishes the current step but leaves within 3–11 real seconds (night hours
  pass at 21 s per hour).
- 11.1: the Training Lead sits at a free desk of the People & Company (HR) room (else another free operations desk,
  else the reception); tour 08:20–16:00 on the first day in groups of at most 4; the daily training session
  (10:00–11:30) is held in the meeting room nearest to the Training Lead's desk with enough free seats (the HR room
  has no class seating).
- 5.5: stage 5 night rota = two separate people (OPERATIONS_JOBS 18 / 19) who take over posts 3 and 6 at the day
  person's shift end and leave at their shift start; below stage 5 the day guard of post 3 stays on while a
  department runs a night crew (no extra pay).
- 5.5 (staffops #10): visible operations staff follow the table of 5.5 exactly: a post is staffed only from the stage
  at which `CompanyOps.STAGES[].ops` pays it (`EmployeeConfig.POST_FROM_STAGE`: posts 2, 10, 15, 16 from stage 3;
  4, 11 from stage 4; the others from stage 2; guest-house posts 13 / 14 where the guest house stands). Stage 2 shows
  8 post holders, stage 3 12 + 2, stage 4 14 + 2, stage 5 16 + 2 — the same principle as drivers and pilots: a person
  is visible iff the economy pays them.
- 11.1 / user request 23: IT Support has compute clearance (BuildingPlan `ROLE_CLEARANCE.support.compute`), so the IT
  post walks to the faulty rack itself; the remote fix from the corridor remains only as a fallback.
- Not adopted (staffops #7): a hire-day exemption from vacation / sick draws would need a new saved map
  (`hiredOn`) and changes `CompanyOps.presence`; a hire who draws an absence on day 1 walks in on the next working day.

**Player settings and actions**
- Appendix A: `empire.prefs = { autoTrips = false }` (phone #1; a pure addition, no DATA_VERSION bump; the Template
  cleaner keeps only the boolean `autoTrips`). The itinerary package reads it through `PhoneService.setting`.
- `EmpireAction {action = "nightShift", role, on}` sets every department of a role atomically; `DealAction pin / skip`
  accept an explicit boolean `on` (idempotent; without it they toggle as before). `live.compute.faults[i].eta` = the
  remaining repair seconds at the current rate in whole 5 s steps. `HardwareConfig.SERVE_POWER = 0.025`.
- 11.4: `CityPlan.TRAVEL.ticket = 700` is now in the code (was 1500).
- Ledger lines: car purchases book "cars", Robux cash packs "shop".

**Open (not decided in this round)**
- 8.1 "per-department HR target" (apps #7): no field or action yet; HR auto + the wage budget remain the player's HR
  levers. Needs an econ design (`e.hr.targets`, `Ops.hrNeed`) before a UI.
- LOGIC_BRIEF 15 "work items" (apps #9): no work-item system; screens, briefing and talk show the training run, the
  research job and studio projects (real state). A later econ/staff design.
- Computer window touch scale (apps #8): deferred to the lab package, which designs its Studio against the current
  0.432 window scale and plans a coordinated Computer chrome request (LAB_SPEC 3.2).
