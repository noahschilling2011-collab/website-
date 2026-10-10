# AI Empire: core company logic, "player clarity and fun" lens

Lens: a 13-year-old Roblox player should always see **one next goal**, see the company **grow visibly**, read **round numbers they understand** ("$1,800 per day", "servers 92 % full"), and find **every system on a screen or in the app**. Where a realistic mechanic would confuse, it is simplified, but everything the user asked for is present at least in a simple form.

All paths are relative to `scratchpad/work/src` unless marked. Line numbers refer to work/src as read on 2026-10-03.

**Evidence base.** Every number in sections 3, 4 and 9 comes from the economy simulator.
- Files are in `scratchpad/agents/design_clarity/economy/`:
  - `sim2.luau`: a copy of `logic_understand/economy/sim.luau`, extended.
  - `patches2.luau`: the design's numbers, written as in-memory patches on the real sources.
  - `runset2.sh` and `summarize.py`.
  - The outputs: `out2_*.txt`.
- The simulator loads the **real** MarketService, EmpireService, AIModelService, NPCService, StudioService, DatasetService, ComputeService and CompanyService in the harness mock. The design's changes are applied as source patches.
- Mechanics that have no code yet are injected as cash flows computed from real game state. They are labelled **[model]** below:
  - client pipeline, trips, hotel nights and car leases;
  - campus services (operations staff, lunch, utilities);
  - guest house;
  - Lab levels;
  - the shift-calendar productivity factor that feeds the patched WorkforceMath.
- Retail stays re-implemented, as in the original sim.
- Snapshot: the sim uses the `gen/sources.luau` snapshot of work/src from 15:38. Since then, work/src changed only replication and stub files: GameConfig REPLICATE_*, the MarketService `session.live` merge, SessionService deltas, and the City/Shop/Talk stubs. I diffed these; none of them change an economy formula.

---

## 1. Core loop and the first 10 minutes

### The game in one paragraph (for a 13-year-old)
You start an AI company in a garage. Your team collects data, and your GPUs train AI models from it. You launch each model as an **app** (people pay every month) or an **API** (developers and businesses pay for what they use). Your **servers** decide how many users you can handle. Meanwhile your salesperson drives to **business clients**. When a client signs, they pay you **every day**. With the money you hire people, buy GPUs, train better models and move into a **bigger office**. Every office unlocks something new: departments, product lines, bigger clients, a guest house, flights abroad. Your team works from 08:00 to 18:00, goes home at night and takes holidays. Your apps keep earning while they sleep.

### Always one next goal (HUD "Next goal" bar)
- The HUD always shows exactly one goal, its progress and an ETA. Example: `Next: Move into Founder HQ - $14,200 / $20,000 - about 3 min`.
- The ETA is the price minus your cash, divided by net profit per minute.
- When the goal is less than about 15 minutes away, the bar offers **Save mode**. Save mode pauses automatic hiring and optional spending (fine-tunes, research, Lab levels, extra marketing).
- The casual simulation bot plays exactly like this. The rule is `goalFloor` in sim2.luau.
- Goal order:
  1. first model
  2. first release
  3. first client
  4. Founder HQ
  5. fill 2 product lines
  6. Startup Campus
  7. first regional client
  8. Innovation Campus
  9. 7B model
  10. Global HQ
  11. all 4 lines at 90+
- Code hooks:
  - Add `EmpireMath.nextGoal(data)`, a pure function.
  - Show it in the HUD next-step slot (`HUD:127-131`).
  - Feed it to the assistant's `insight()` (`AssistantService:225`).

### First 10 minutes, minute by minute
"Human" times are what a real player needs. "Sim" is the casual bot, which reacts every 10 s (`out2_casual.txt`). Start cash is $10,000 plus the $1,000 daily reward.

| Time (human) | What the player sees and does | Money |
|---|---|---|
| 0:00 | Spawns at the **garage** at the front of their plot. The rest of the site is a fenced, levelled lot with hoarding: "Future HQ of Nimbus Labs - opens at $20,000". The assistant greets them. Goal 1: "Train your first AI". | $11,000 |
| 0:30 | At the garage laptop: buy *Web Crawl Chunk* ($1,200), or scrape for free. Quest "Feed the model" pays +$1,800. | |
| 1:00 | Train a **100M** model on the laptop (80 s, $1,280). The fan spins and the whiteboard shows the loss curve. | |
| 2:30 | Training finishes (quest +$2,500). **Release**: pick a product line. The app recommends the best fit, for example *Developer API*. The price is set automatically (standard: $5 per month or $2 per 1M tokens). | |
| **2:40** | **First $ comes in.** The user counter climbs (rise time about 40 s), the money counter ticks, and quest "Launch day" pays +$3,000. *Sim: release and first $ at 1.3-1.4 min.* | ~$1,000/min after 1 min |
| 3-4 | 5,000 users: quest "Word gets around" +$10,000 (sim 2.0 min). Buy a **Consumer GPU** ($2,500, quest +$1,500), then a **Workstation GPU** ($14,000) for the 3-slot garage rack. The servers now hold about 29,000 users (sim 2.0-2.5 min). Hire 2 people (engineer, researcher); quest +$2,500. | Sim min 5: **$1,824/min** |
| 5-9 | **First lead**: "Pixel Games needs Coding 22+. You qualify." The **founder** drives there (your Founder's Hatch; it runs automatically if you are busy). The meeting takes 240 s (about 2.7 game hours). Signed: +$2,000 pilot fee, then **$2,000 per day** ($100/min). The goal bar switches to Founder HQ, and Save mode starts. | |
| 9-10 | Training the next model (500M; sim 10.0 min). | Sim min 10: **$2,146/min** (1 client) |
| **~10** | **Move into Founder HQ** (sim 10.2 min; 9.8-14.3 across 5 runs). The HQ is built on the site. 24 desks, café with chef, AI Research room, Customer Desk, B1 garage. New goal: "Fill your 2nd product line". | |

---

## 2. Office stages

| # | Stage | Price | Hired staff cap | GPU slots | Thermal base | Base RP/s | Product lines | Training slots (max) | Salary level | Operations staff | Utilities / rent per day |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | **Founder's Garage** (NEW) | start | 4 (+ founder) | 3 (+ laptop) | 10 | 0.10 (banked) | 1 | 1 | ×1.0 | 0 | $300 rent |
| 2 | Founder HQ (old tier 1) | $20,000 | 24 | 6 | 20 | 0.15 | 2 | 1 | ×1.0 | 6 | $2,000 |
| 3 | Startup Campus (old tier 2) | $90,000 | 64 | 12 | 40 | 0.30 | 3 | 2 | ×1.25 | 9 (+2 guest house) | $6,000 |
| 4 | Innovation Campus (old tier 3) | $300,000 | 128 | 24 | 60 | 0.60 | 4 | 3 | ×1.5 | 12 (+2) | $15,000 |
| 5 | Global AI HQ (old tier 4) | $2,400,000 | 240 | 48 (+48 Distributed Cluster) | 80 | 1.0 | 4 | 4 | ×1.8 | 14 (+2) | $35,000 |

Old office prices were 0 / 18k / 90k / 350k for four tiers. Thermal follows the old rule of 20 × office: the garage gets 10, and the old tier n keeps its old budget.

### What each stage unlocks in gameplay
Every unlock is listed on the upgrade card and in the Office tab, so the reason to move is always visible.
- **Garage:**
  - Train, release one product line, hire 4 people (any of the 4 lab roles).
  - The founder sells: 2 client accounts, city clients only.
  - No research (points are banked) and no cafeteria (pizza is delivered: the meal cost applies, morale ×0.95).
- **Founder HQ:**
  - AI Research room and the research tree.
  - **Account Managers** (new field role) and the **company car fleet** in B1.
  - Café with chef (lunch, morale).
  - Reception (client visits, interviews), Customer Desk.
  - 2nd product line, studio jobs (Product Studio), city clients up to $8k per day.
- **Startup Campus:**
  - **Guest House** (12 rooms, hotel_site.md west wing).
  - **Regional clients** (overnight trips, hotel nights).
  - HR office (vacation planner, better applicants).
  - 3rd product line, 2nd training slot, wellness (gym and sauna feed morale).
- **Innovation Campus:**
  - 4th product line, research labs (23 research seats), 3rd training slot.
  - **Airport and international clients** (flights, abroad hotel).
  - Night shift option.
- **Global AI HQ:**
  - Frontier clients ($90-120k per day), Platform Ops and Cluster Control, 4th training slot, 48 GPU slots, 7B training at scale.

### The garage stage (new building)
- **Where:** a single-storey garage of 48 × 40 studs at building-local x 70..118, z −140..−100. Its door faces −Z onto the existing driveway (x 92..112, z −217..−146; ExteriorDesign:949). The founder's car parks in front.
- **The rest of the site:**
  - Front lawns and visitor parking stay.
  - The building footprint (MAIN, PAVILION and B1 envelope, BuildingPlan:17-19) becomes a levelled gravel lot with construction hoarding along the plaza line.
  - Props: survey stakes, a site container and a big sign. The sign is a SurfaceGui showing the next-goal price, so the empty site is the goal made visible.
- **Inside:**
  - founder desk + 4 desks (seat Role = any);
  - a 3-slot GPU shelf (blades light per GPU, like the data hall);
  - roadmap whiteboard, coffee machine, fridge, sofa, roller door;
  - the assistant's corner.
- **Budget:** about 600-900 parts. The tier-1 HQ is 13,534 parts.
- **Who works there:** the founder (player) and up to 4 hires. No operations staff; the assistant acts as co-founder and greets visitors. Staff walk in from the street (no garage commute).

### Code changes for the extra stage
1. **Configuration:**
   - `EmpireConfig.OFFICES` (EmpireConfig:4-9) becomes 5 entries.
   - `HardwareConfig.slots` becomes the table {3,6,12,24,48} (HardwareConfig:52-54).
   - `HardwareConfig.thermal` becomes the budget table {10,20,40,60,80}·cooling (:56-60).
   - `GameConfig.START_MONEY` becomes 10,000 (applies to new saves only).
2. **Mapping to building tiers:** add `Plan.tierForOffice(office) = office − 1`, where 0 = garage. Every building call that takes a tier goes through it:
   - `BuildingPlan.floors/theme/rooms` and `TIER_FLOORS` (BuildingPlan:14, 79, 114-131);
   - `PlotService.refresh` (`OfficeTier` attribute, :85-93);
   - `StaffAssignment.assign` (:46);
   - `HeadquartersDesign.build` (calls the new `GarageDesign.build` for 0);
   - BuildingStateService screens;
   - the admin tier commands (become `garage`, `tier1`..`tier4`).
3. **Office-index users that need +1:**
   - `NPCService.init` `d.empire.office=2` becomes 3 (NPCService:66);
   - contract and client `office`/`stage` fields;
   - quest "Out of the garage" (`kind="office", target=2` now means "leave the garage", EmpireConfig:43; this quest finally means what its name says).
4. **Migrating old saves** (keep their building):
   - Bump `GameConfig.DATA_VERSION` from 5 to 6.
   - Add `MIGRATIONS[5] = function(d) d.empire.office = math.clamp((d.empire.office or 1) + 1, 2, 5) end` (Template:44-49). Old tier 1 becomes stage 2, and so on. No old save lands in the garage.
   - `Template.migrate` fills the new fields (`labLevel`, `clients`, `calendar`) from `EmpireMath.new`.
   - Rolling-update risk: data_ui.md pitfall 5. Ship the migration with the release that understands version 6.
5. **Tests:** headless tests that build tiers 1-4 call `tierForOffice`; add a garage build test (part count, door, desks).

---

## 3. Income sources

| Source | Formula (design) | Code hook | Share of income, casual (5-10 / 45-60 / 120-180 min) | Opt profile |
|---|---|---|---|---|
| **Apps and APIs** (consumer market) | below | MarketMath.tick (:85), MarketService.tick (:171) | **80 % / 85 % / 88 %** | 84 / 92 / 91 % |
| **Business clients** (retainers + pilot fees) [model] | below | new `ClientService` (merges EmpireConfig.CONTRACTS, MarketService.businesses, StudioConfig.BRIEFS) | **19 % / 10 % / 11 %** | 7 / 7 / 9 % |
| Studio jobs | unchanged briefs ($3.5k-11k), now repeatable every 3 game days; published sites pay (q−20)·2 per game month | StudioService.deliver (:62-72, the day key at :67) | 0 % / 4 % / 1 % | ~0 % |
| Guest house [model] | 12 rooms × occupancy × $450 per night, once per game day | new `GuestHouseService` (hotel_site.md) | – / 1 % / 0.1 % | – / 1 % / 0.1 % |
| Retail (arcade shop) | unchanged: $12 per ticket every 30 s, tickets = retailLevel + ⌊staff/24⌋ | FacilityService.economyTick (:514) | 1 % / 0 % / 0 % | ~0 % |
| Quests and daily reward | unchanged one-offs ($77k total, plus $1,000 + $500 per streak day) | EmpireService.quest/daily | big in minutes 0-4 | |

### (a) Apps and APIs: the fixed consumer market
- **Product lines**: Chat app (General/consumers), Study app (students), Developer API (developers), Business API (businesses). The release target becomes the product line.
- A model reaches its own segment fully and the other three at **25 %** (`reach × lineFactor`, lineFactor 1 or 0.25).
- **Demand:**
  - The per-segment softmax stays as it is, with **FIT_SCALE 20** (was 10): utility = (fit − 50)/20 − sens·price/norm − freshness.
  - Target users = pool × reach × share.
  - **Pools ×0.5:** developers 200k, students 750k, businesses 50k, consumers 2.5M. Reputation userScale is 1M.
- **Freshness (ageing):** penalty = min(0.5, max(0, age − 2400 s)/4800 s) in utility. That is −5 stat points per game day after 2 days, at most −10. The UI shows "Freshness 100 % → 50 %".
- **Serving capacity (the visible limiter):**
  - served users = min(demand, capacity);
  - capacity = GPU throughput × **6,000** × thermal × (1 + 0.6·(1 − e^(−E/10))), where E = productive engineers;
  - revenue and serving cost are scaled by served/demand;
  - users above capacity form a **waitlist**, shown as "12,400 waiting - buy GPUs".
- Users served per GPU: laptop 3,000 / consumer 6,000 / workstation 19,200 / accelerator 54,000 / datacenter 168,000 / pod 1.2M.
- **Revenue per served user per minute** before the growth multiplier: Chat $5 = $0.083; Chat $10 = $0.167; Dev API $2 = $0.10; Business API $2 = $0.40 ($4 = $0.80).
- **Price menus (simple):** subscriptions Free / $5 / $10 (the $20 tier is removed); API $1 / $2 / $3 / $4 per 1M tokens (max was 20). Business price sensitivity 0.35 → 0.6.
  - Migration: release prices are clamped to the menu.
- **Auto-pricing (on by default; the Growth team runs it, the player can override):**
  - A line whose model leads the best rival by 15 points or more uses premium ($10 / $4).
  - If the servers are at least 95 % full, the busiest line goes up one step ("Servers full, so the price went up. Buy GPUs to grow.").
  - If the servers are below 75 % full and the line isn't leading, its price steps back toward standard ($5 / $2).
  - The player reads it as one sentence in the Growth screen.
  - Effect in the sim: with auto-pricing off (always $5/$2), Global HQ arrived at 174.7 min instead of 151.3 (`out2_casual_fixedprice.txt`).
- **Growth managers:** revenue × (1 + 1.0·(1 − e^(−G/8))), G = productive growth managers, **day-averaged**. Awareness builds and fades over about a day, so night doesn't dent revenue. This replaces +8 % per head, which was linear and uncapped (EmpireMath:121).

**The NPC-rival fix (no arms race, no compounding):**
- Each NPC release adds `stat += (72 − stat) × 0.12` per core stat (NPCService:86). Stats approach 72; the NPC overall reaches about 65.9 at 60 min, 68.3 at 180 min, and never more than 72.
- NPC market age resets on every release, so NPCs stay "fresh" competitors.
- The static `MarketConfig.NPC_MODELS` stays unused live (the existing behaviour). Fix the LabApp forecast to use the live rivals (models.md).
- Why this does not run away: the player can exceed the NPCs, but income is bounded by pools × reach, by **capacity** (GPU slots per stage) and by the stats cap of 99.

**Anti-clone rule: one live model per product line.**
- Releasing into an occupied line **replaces** the old model. The new one inherits **90 % of its users** and its organic awareness; the old one is retired.
- The stage decides how many lines you may run (1 / 2 / 3 / 4 / 4).
- Clones are impossible, and every extra model is a new segment. This is clearer than a nested-logit λ.
- Hook: `AIModelService.releaseModel` (:459-490, after :484) plus a stage-line check.

### (b) Business clients: sales pipeline → trip → monthly retainer [model]
One catalogue of 18 clients, merged from the 6 contracts, 12 lease businesses and 5 briefs. Each client is per player (not shared on the server), so late joiners are not blocked.

| Stage | Clients (need → $ per game day) | Where |
|---|---|---|
| 1 Garage | CloudDesk Reliability 24 → 2,400; Pixel Games Coding 22 → 2,000; North Logistics Reasoning 25 → 2,400; Paper Studio Creativity 28 → 2,200; ByteWorks Coding 38 → 3,600 | Business City (240 s trip, no hotel) |
| 2 HQ | StudySpark Math 40 → 5,000; Ledger Math 42 → 6,000; Orbit Games Coding 45 → 7,000; Atlas Knowledge 48 → 8,000; Civic Reliability 48 → 6,500 | city |
| 3 Campus | PixelForge Creativity 50 → 14,000; Nova Logistics Reliability 58 → 18,000; Delta Robotics Reasoning 60 → 20,000; Mosaic Creativity 63 → 24,000 | region: 1 game day, 1 hotel night |
| 4 Innovation | Helix Math 68 → 40,000; Orbit Systems Reasoning 72 → 50,000 | abroad: 2 days, flight + 2 nights |
| 5 Global | Nova Infrastructure Coding 78 → 90,000; Frontier Science Reasoning 84 → 120,000 | abroad |

How the pipeline works (all automatic; every step appears on the Customer Desk screen and in the Clients tab):
1. **Leads.** The founder finds 1 lead per 180 s until the first Account Manager is hired. Each Account Manager finds 1 lead per 240 s × on-duty share (no leads at night). A lead waits 1 game day.
2. **Qualify.** The best live model's stat must be at least the client's need. Otherwise the lead is lost with an assistant hint: "Atlas Search wanted Knowledge 48. Train a knowledge model."
3. **Trip.** A free seller drives the company car during work hours (08-17). City trips take 240 s; regional trips take 1,200 s with 1 hotel night; trips abroad take 2,400 s with 2 nights.
4. **Win chance** = clamp(0.55 + 0.03·(stat − need) + 0.10·[Guest House and the client is regional/abroad], 0.3, 0.95).
5. **Signed.** The client pays a **pilot fee of 1 day's retainer**, then the **retainer continuously for 8 game days** (160 min, about 2.7 billing months of 3 days). The retainer is shown per day ("+$2,400/day") because one billing month is 3 game days.
6. **Renewal.** A city review visit; the client's need rises by +2. If the model no longer qualifies, the client leaves ("churn").
- **Capacity:** the founder holds 2 accounts; each Account Manager holds 3 accounts and makes 1 trip at a time.
- The catalogue caps B2B income at $421,100 per day, which is $21,055/min. The opt run reached exactly that with 18 accounts.
- Sim casual: 14 accounts at 180 min, 24 trips, 17 hotel nights; $1.12M of client income over 3 h.
- The old once-a-day contract click (EmpireService.deliver :100-116, UTC day) is removed. Its rewards become the pilot fees. Quest "Reliable supplier" now counts signed clients (`contractsCompleted`).

### (c) Contracts and pilots, studio, guest house, retail
- **Pilots** are now part of client deals; see above.
- **Studio:** the same briefs, but `deliveries[brief]` keys on `⌊empire.seconds/3600⌋` (3 game days) instead of the UTC day (StudioService:67). In the sim, studio earned $105k in 3 h.
- **Guest house** (stage ≥ 3):
  - Occupancy = 0.35 + 0.5·reputation/100. Income = 12 × occupancy × $450 per game day.
  - Running cost = 2 staff × $800 + $600 utilities per game day.
  - That is roughly break-even: +$25/min at reputation 30, +$66/min at reputation 60.
  - Its real job is **winning big clients** (+10 % win chance on regional and abroad deals) and hosting client delegations visibly.
  - I keep it honest and small rather than making a hotel that out-earns the AI business.
- **Retail:** unchanged and tiny ($24/min base). Optional later boost; not needed for the balance.

---

## 4. Costs

| Cost | Formula (design) | Code hook | Share of running costs, casual (5-10 / 45-60 / 120-180 min) |
|---|---|---|---|
| **Wages** | Salary per game day, paid continuously (shown per day and per minute), including nights and paid vacation. Researcher **$1,800**, Engineer **$2,160**, Data Curator **$1,440**, Growth Manager **$1,800**, Account Manager **$2,160** per day (was $240-600). Multiplied by the **salary level** of the stage (1 / 1 / 1.25 / 1.5 / 1.8) and the profile wage multiplier `w`. | `EmpireConfig.ROLES` (:10-15), `EmpireMath.bonuses` wage (:118-120), `EmpireService.tick` (:162) | **80 % / 78 % / 82 %** |
| **Hiring fee** (cut) | Flat = 1 day of base salary ($1,440-2,160). The old fee was $2.8-6k and grew with n². | `EmpireMath.hireCost` (:112-114) | (an investment) 31 % of all spending at 45-60 min; 440k over 3 h vs 2.39M wages, so wages now dominate staff cost |
| Paid vacation and sick days | No extra cost (salary continues); output is lost: presence 0.92 | WorkforceMath (section 5) | – |
| Night shift (optional, stage 4+) | +50 % salary for the night crew of Data Ops, Training Control or Customer Desk | `EmpireMath.payroll` (:71-82) | not simulated |
| **Fleet leases** | $150 per game day per Account Manager car. The boss's Founder's Hatch is free (owned). Other cars stay player purchases for driving. | `CampusConfig.CARS` (:15-20) gets `lease`; new `campus.fleet` | 0-0.1 % |
| **Trips** | City: $80 fuel. Region: $200 + $250 per hotel night. Abroad: $1,800 flight + $150 taxi + $350 per night × 2. Billed via `Economy.applyFlow` when a trip starts. | ClientService | 6 % / 2 % / 0 % (13.5k over 3 h) |
| **Cafeteria food** | $15 per person per game day (lunch cooked by the chef; pizza in the garage) | campus services | inside "campus" |
| **Campus services** | Operations staff {0,6,9,12,14} × $800 per day + utilities {300, 2,000, 6,000, 15,000, 35,000} per day + food | new `CampusOps.perDay(stage)` charged in `EmpireService.tick` | **6 % / 12 % / 6 %** |
| Guest house running cost | $2,200 per game day | GuestHouseService | 0 % / 2 % / 0 % |
| Serving and power | Unchanged: tokens × serveCost (×0.85 with quantization) + throughput × 0.025 $/s while serving; scaled by served share | MarketService.tick (:192-202) | 8 % / 5 % / 12 % |
| Rent | Only the garage pays rent ($300 per day). HQ stages are bought; their running cost is the utilities line. | | |

- Investments (one-off, by player choice): offices, GPUs, cooling, training, data, research, Lab levels, marketing, hiring fees.
- At 120-180 min, casual spends 45 % of all outflow on the office move, 9 % on training and 8 % on research.

---

## 5. Staff and department production

### One formula, watched or not
For each department d:

**O_d = Σ over people seated in d of factor(k_i) · p_i(t) · M · Q_d + 0.5 · (the same sum for overflow people without a department seat)**

- **factor(k) = (7 + k)/10**: the existing skill rule (WorkforceMath:20).
- Simulation note: the sim applies p̄ per role (Σ factor × schedule factor). It does not model the seat limit or the 0.5 overflow weight; those only bind at tier 4, where data desks stay at 32 (building_meaning.md).
- **p_i(t)**: the *expected* productivity from the person's own calendar. It is always used for the economy, so it is identical whether anyone is watching:
  - 0 when absent (vacation, sick, trip) or outside their shift. Shifts come from the seed: start 7.75-9.0, finish 16.5-18.0 (EmployeeConfig:59-65).
  - 0.4 inside their lunch window (lunch start + 1.1 h).
  - otherwise 0.95 (coffee and walking).
- The visible state machine (StaffService) follows the same schedule but **only drives animation**. The money no longer depends on LOD.
- Population average over a game day, including presence 0.92: **p̄ = 0.531** (computed in sim2.luau from the seed distributions).
- **M (morale)** = 0.85 + 0.10·lunchServed + 0.05·wellness.
  - lunchServed = min(1, kitchen capacity / staff present). Kitchen capacity is 40 meals per kitchen post per day.
  - Wellness is 1 when the gym and sauna exist (stage 3+).
  - Garage: pizza, so M = 0.95. HQ with chef: 0.95-1.0. Campus+: up to 1.0.
  - The sim assumes M = 1 (not simulated).
- **Q_d (room quality)** = 1.0 for team rooms, 1.15 for specialist labs. Not simulated; it is a small bonus for the big labs that only exist at higher stages.
- **Night** (18:00-08:00, 300 s real) is off duty for everyone, except the optional night crew (stage 4+).
- **Code hooks:**
  - `WorkforceMath.count` (:34) returns Σ factor·p_i·M·Q per role or department. Add `setSchedule` (as patched in the sim) or a per-person `expected(e, profile, hour, day)`.
  - Remove the offscreen 100 % branch (StaffService:342-344, 352).
  - `WorkforceMath.capacity` (:21) skips absent profiles.
  - StaffService publishes `live.workforce.dept`. The session.live merge fix is already in work/src (MarketService:204-207).

### Vacation and sick days (automatic HR)
- Every employee earns **1 vacation day per 10 game days** worked. One game day is 20 real minutes.
- **HR plans it automatically:**
  - at most 10 % of a department absent at once;
  - never the only person of a role;
  - booked one game day ahead and shown on the HR screen ("Tomorrow: Mia, Jonas on vacation").
- **Sick days:** deterministic hash(seed, day) < 0.02, so 2 % of person-days. Wellness halves it.
- Absent people are hidden (the existing `OffDuty` pattern) and their desk is released. The `employees[role]` counts never change, so no rig rebuild (time_staff.md pitfall 3).
- New profile field `a = {kind, untilDay}` plus `v` (vacation balance). It must be added together in:
  - `cleanProfile`/`profilesConsistent` (EmpireMath:26-49);
  - `SessionService.profileSignature`;
  - `StaffAssignment.profile`;
  - `Rig.Profile`.

### Morale from lunch: the chef's real job
- Lunch becomes queue → counter → tray → seat → eat → dish return. The chef and kitchen team plate meals, using the assistant coffee-flow pattern (AssistantService:279-344).
- Each meal served counts toward lunchServed. If the kitchen is understaffed, the morale bar drops and the café screen says so.
- Kitchen posts per stage: 1 / 2 / 3 / 3 (garage: pizza).

### Operations staff become paid jobs with a function
Operations posts are hired automatically with the stage ("campus package"), paid $800 per game day each (the "Campus services" cost line), get lunch and breaks with relief cover, and can be talked to (TalkService).

| Post | Stage | Function (what changes if the post is empty) |
|---|---|---|
| Reception | 2 (2nd at 3) | Checks in clients, candidates and hotel guests. Client visits and interviews at HQ need it (in the garage the founder does it). |
| Security | 2 (2nd at 4) | Badge gates and garage barrier. Required for client visits and for the night crew (data hall watch). |
| Chef | 2 | Lunch, which feeds morale M |
| Kitchen team | 3 | More meals per day, which feeds morale |
| Barista | 2 | Coffee breaks count 0.6 instead of 0.4 (shorter breaks) |
| Café host | 4 | +50 % lunch seatings (53 seats turn over faster) |
| Facilities (cleaning) | 2 (2nd at 4) | Keeps Q_d at its value (dirty rooms −5 %) |
| IT support | 2 (2nd at 5) | Keeps GPU uptime 100 % (without it, capacity −5 %) |
| Fleet manager | 3 | Trips start the moment a seller is free (otherwise +60 s prep) |
| HR coordinator | 5 (the HR room exists from stage 3; until then HR is automatic) | Vacation planner; applicant quality +1 star |
| Hotel reception, housekeeping | 3 (guest house) | Guest-house occupancy works |

These are always staffed automatically, so the "if empty" effects only show during their breaks with no relief, or if the player disables a post. They give each job a visible, explainable purpose without adding a management chore.

### What each department produces (every room kind)
Seats per department come from `Plan.rooms` desks (building_meaning.md); `Plan.deptSeats(tier)` caches them.

| Department (rooms) | Role | Output |
|---|---|---|
| Data Ops (datalab, data rooms) | Data Curator | **1,000,000 tokens/s per productive curator** (was 300k; offsets p̄ = 0.53), quality 0.65 → 0.85 with Data Cleaning (EmpireService:152-160) |
| AI Research, Model Architecture, Experiment/Advanced labs | Researcher | 0.6 research points/s each (existing) → research tree, then **Lab levels**: points 200·1.35^L + $6,000·1.6^L, +1 core stat on future models per level, 10 levels maximum (patch on `EmpireMath.bonuses.core`) |
| AI Engineering, Training Control, Evaluation, Build & CI | ML Engineer | training speed +15 % each (existing); **serving capacity × (1 + 0.6(1 − e^(−E/10)))**; training slots = 1 + ⌊E/6⌋ capped by the stage |
| Product & Growth, Deployment | Growth Manager | app revenue × (1 + 1.0(1 − e^(−G/8))) (day-averaged awareness); runs auto-pricing |
| Customer Desk, Customer & Support, Partnerships | **Account Manager (new role `sales`)** | leads, pitches, trips, 3 accounts each, company car |
| HR / People & Ops | HR coordinator (operations) | vacation planning, hiring speed and quality (RecruitingService ARRIVAL :46) |
| Data hall, compute ops, IT desk | (GPUs) + IT | GPU slots per stage; blades above the slot cap shown dimmed "locked" |
| Café + kitchen | chef, kitchen, barista, host | lunch, which feeds morale |
| Gym, sauna, terraces, lounges | – | wellness (+0.05 morale, half as many sick days); breaks |
| Meeting rooms, Project Room, boardroom | – | meetings count as work (p = 1, was 0.8); the pre-release review in the Project Room shows the model's line forecast |
| Showroom, lobby, visitor lounge | reception | city-client visits and candidates (+5 % win chance on city clients from stage 2) |
| B1 garage, fleet office | fleet manager | Account Manager cars visibly leave and return; trips |
| Guest House | hotel staff | +10 % win chance on regional/abroad clients; room income |
| Founder floor, vault, security, library | – | founder UI (unchanged) |
| Print, phone, mail, storage, circulation | – | decoration (honest: no economy) |

---

## 6. Calendar: one saved calendar
- **World clock (what you see):**
  - day = 1,200 s, of which 900 s are 08:00-18:00 and 300 s are night (EmployeeConfig.hour :73-76, unchanged);
  - hour = `EmployeeConfig.hour(workspace:GetServerTimeNow() % 1200 + OFFSET)`, so all servers show the same hour and it survives restarts;
  - `Lighting.ClockTime`, shifts, lunch, trips (08-17 only) and night use it;
  - replaces `local time=54` (StaffService:33).
- **Company calendar (saved per player):**
  - `day = ⌊empire.seconds / 1200⌋ + 1`, from persisted play time (EmpireService:134); the HUD shows "Day 14 · 10:30";
  - it advances only while the player is online, so nothing expires offline (there is still no offline progress, as today).
  - Vacation days, sick days, trip durations, hotel nights, retainer lengths (8 days), renewals and the guest-house night are all counted in **company days or play seconds**.
- **Payroll** is continuous per second, shown per day. There is no lump at 18:00, so the money extrapolation (StateController:134-140) stays correct.
- **GAME_MONTH_SECONDS = 3600** (3 game days) stays as the subscription billing unit. The UI says "/month (3 days)". It is also the studio repeat period.
- **Real-day items:** only the daily login reward stays on the UTC day (Roblox convention). The old daily contracts are removed.

---

## 7. AI models
- **Several live models matter:**
  - up to 4 product lines, each serving its own segment (others at 25 %);
  - the stage unlocks lines 1 / 2 / 3 / 4 / 4;
  - in the sim the casual bot ran 2 lines at 20 min, 3 at 45 min and 4 at 120 min.
- **Anti-clone:** one live model per line. Clones are impossible by rule.
- **Versions:** a release into an occupied line replaces the predecessor and migrates 90 % of its users and its organic awareness. The predecessor moves to an archive; the model cap of 80 counts only non-archived models (AIModelService:316/347).
- **Ageing:** freshness penalty after 2 game days, −5 stat points per day, at most −10 (MarketMath.tick: agePenalty in the utility).
  - Sim effect: the bot retrains a line when its effective overall falls 3+ below a new model.
  - Without the freshness cap (max 1.0 in an early test), income dropped by half at 120 min, which is why the cap is 0.5.
- **Training slots** come from engineering capacity: 1 + ⌊E/6⌋, capped by the stage (1/1/2/3/4).
  - Change `data.training` into `data.trainings[slot]` with **one training per slot** (models.md lists all 30 readers of `data.training`).
  - Not simulated: the sim keeps 1 slot, which is conservative.
- **Refinement ("Fine-tune"), fixed and capped:**
  - gain = (2 + 8·dataQuality)·qualityMod/√(1 + iterations), additive instead of proportional to the stat (AIModelService:209);
  - stats capped at 99; at most 3 fine-tunes per model;
  - the model **stays live** while fine-tuning (AIModelService:415); a fine-tune occupies a training slot.
- **Stats cap 99** for every core stat (`EmpireMath.boostStats` :135), so research and Lab levels can never push past "perfect".
- Release UI: "Product shelf" with 4 slots showing model, freshness, users, price and served/waitlist. The LabApp forecast uses the live rivals (models.md fix).

---

## 8. Automation: what runs by itself, what the player decides

| Automatic (default ON) | Player decides |
|---|---|
| **HR:** hires by department need while salaries stay ≤ **40 % of income** (slider 25/40/55 %; 3 starter hires are always allowed); plans vacations; covers breaks; dismisses nobody automatically | which **departments** get priority; the HR budget slider; firing |
| **Sales:** finds leads, qualifies them, sends the founder or an Account Manager, signs, renews; hotel and fuel billed automatically | train a model for a client's need (the assistant says which) |
| **Trips:** car, route, hotel, flight; visible cars leaving through the barrier (client-side) | optional: drive to a city meeting yourself (+10 % win chance) |
| **Pricing:** auto-price rules (section 3) | override any line's price |
| **Purchasing:** food, coffee, utilities, guest house | buy GPUs, cooling, data |
| **Model operations:** retire the predecessor on replacement; event decisions auto-resolve after 25 s (existing) | **train** (size, focus, recipe), **release** (which line), fine-tune |
| **Save mode** offered by the goal bar | accept or ignore |
| | upgrade office, research, Lab levels |

**How the assistant explains it** (`AssistantService.briefing` :112-223):
- New sections "Today", "Clients" and "Next goal", built from real numbers. Examples:
  - "Day 14 · 10:30 · 2 on vacation, Jonas at Nova Logistics (hotel tonight $250)."
  - "Servers 97 % full → Chat app price raised to $10. A Workstation GPU adds 19,200 users."
  - "Atlas Search needs Knowledge 48 (your best: 44)."
- One-line "why" for every automatic action, in a feed in the company phone app (Toast shows only one message at a time; data_ui.md pitfall 9).

---

## 9. Targets check (simulation)
Profiles:
- **casual** = launch defaults with auto-pricing; reacts every 10 s; follows the goal bar.
- **opt** = the full portfolio and price optimiser, reacting every 1 s; the upper bound.
- **late** = the player founds the company on a server that already ran 60 min, so the NPCs are at about 66.

Every run stops at 180 min unless marked.

### (a) Casual: `out2_casual.txt`
| min | money | revenue/min | running cost/min | wages/min (% of rev) | apps / clients $/min | staff | office | best model | served / capacity | NPC best |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 11,000 | 0 | 15 | 0 | 0 / 0 | 0 | 1 | – | 0 / 0 | 47.9 |
| 5 | 12,394 | **1,824** | 236 | 198 (11 %) | 1,822 / 0 | 2 | 1 | s100m 41.8 | 17,820 / 29,531 | 54.5 |
| 10 | 22,265 | **2,146** | 237 | 198 (9 %) | 2,043 / 100 | 2 | 1 | s100m 41.8 | 22,602 / 29,616 | 57.6 |
| 20 | 43,921 | 7,591 | 935 | 468 (6 %) | 7,188 / 400 | 5 | 2 | s500m 46.8 | 51,907 / 67,664 | 61.1 |
| 30 | 49,460 | 7,017 | 935 | 468 (7 %) | 6,614 / 400 | 5 | 2 | s500m 46.8 | 72,207 / 119,094 | 63.5 |
| 45 | 12,148 | 9,816 | 3,430 | 2,475 (25 %) | 9,166 / 520 | 21 | 3 | s500m 48.7 | 75,014 / 135,893 | 65.1 |
| 60 | 23,946 | 17,518 | 7,606 | 6,390 (36 %) | 16,400 / 980 | 55 | 3 | s500m 58.7 | 119,280 / 198,375 | 65.9 |
| 90 | 77,022 | 48,682 | 16,998 | 14,823 (30 %) | 43,662 / 4,855 | 107 | 4 | s1b 79.9 | 250,957 / 416,428 | 67.7 |
| 120 | 385,890 | 103,074 | 22,417 | 17,685 (17 %) | 96,838 / 6,055 | 128 | 4 | s7b 99.0 | 330,081 / 794,389 | 68.1 |
| 180 | 1,596,471 | 104,252 | 46,109 | 39,658 (38 %) | 93,506 / 10,555 | 240 | 5 | s7b 99.0 | 327,497 / 831,280 | 68.3 |
| 240* | – | 121,452 | – | – | – | 240 | 5 | – | – | – |
| 300* | 8,654,675 | 118,762 | 46,503 | 39,658 (33 %) | 97,496 / 21,055 | 240 | 5 | s7b 99.0 | 329,920 / 2,735,702 | 68.5 |

\* From `out2_casual_300.txt`, which is the identical run extended to 300 min.

### (b) Opt: `out2_opt.txt`
| min | money | revenue/min | running cost/min | wages/min (%) | staff | office | best | NPC |
|---|---|---|---|---|---|---|---|---|
| 0 | 11,000 | 0 | 15 | 0 | 0 | 1 | – | 47.9 |
| 5 | 14,760 | 2,294 | 397 | 360 (16 %) | 4 | 1 | s500m 47.3 | 54.5 |
| 10 | 15,506 | 8,018 | 421 | 360 (4 %) | 4 | 1 | s500m 47.3 | 57.6 |
| 20 | 78,803 | 6,127 | 750 | 360 (6 %) | 4 | 2 | s500m 47.3 | 61.1 |
| 30 | 8,402 | 11,775 | 2,959 | 2,025 (17 %) | 17 | 3 | s1b 50.9 | 63.5 |
| 45 | 20,369 | 22,359 | 8,216 | 7,200 (32 %) | 62 | 3 | s1b 59.3 | 65.1 |
| 60 | 195,163 | 22,218 | 8,465 | 7,425 (33 %) | 64 | 3 | s1b 59.3 | 65.9 |
| 90 | 225,662 | 195,258 | 22,024 | 17,685 (9 %) | 128 | 4 | s7b 99.0 | 67.7 |
| 120 | 2,379,018 | 199,406 | 46,082 | 39,658 (20 %) | 240 | 5 | s7b 99.0 | 68.3 |
| 180 | 11,659,623 | 209,534 | 46,012 | 39,658 (19 %) | 240 | 5 | s7b 99.0 | 68.5 |

### (c) Joining a 60-minute-old server: `out2_casual_late60.txt`, `out2_opt_late60.txt`
| min | casual: money | rev/min | cost/min | staff | office | best | NPC | opt: rev/min | staff | office |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 11,000 | 0 | 15 | 0 | 1 | – | 65.9 | 0 | 0 | 1 |
| 5 | 2,387 | **1,165** | 343 | 3 | 1 | s500m 47.9 | 66.2 | 2,286 | 3 | 1 |
| 10 | 6,153 | **1,773** | 435 | 4 | 1 | s500m 47.9 | 66.5 | 5,721 | 5 | 2 |
| 20 | 2,651 | 3,315 | 801 | 4 | 2 | s500m 49.2 | 67.1 | 6,816 | 10 | 2 |
| 30 | 7,627 | 5,153 | 1,815 | 14 | 2 | s500m 55.0 | 67.7 | 9,341 | 17 | 3 |
| 45 | 89,833 | 7,385 | 2,297 | 19 | 2 | s500m 55.0 | 68.1 | 19,105 | 47 | 3 |
| 60 | 10,162 | 9,586 | 4,791 | 32 | 3 | s500m 57.9 | 68.3 | 23,267 | 64 | 3 |
| 90 | 126,512 | 25,216 | 8,676 | 64 | 3 | s1b 74.8 | 68.4 | 88,693 | 128 | 4 |
| 120 | 42,969 | 36,671 | 19,047 | 116 | 4 | s1b 81.0 | 68.5 | 167,008 | 240 | 5 |
| 180 | 2,023,973 | 98,331 | 22,668 | 128 | 4 | s7b 99.0 | 68.5 | 182,650 | 240 | 5 |

### Office stage times (minutes)
| Run | Founder HQ (2) | Startup Campus (3) | Innovation (4) | Global HQ (5) |
|---|---|---|---|---|
| casual (seed 4242, starts 08:36) | 10.2 | 36.3 | 81.5 | 151.3 |
| casual seed 99 | 9.8 | 26.8 | 80.0 | 149.5 |
| casual seed 7 (200 min) | 10.3 | 53.2 | 91.5 | 180.3 |
| casual, starts 16:53 (night falls after 100 s) | 10.7 | 42.5 | 87.8 | 158.2 |
| casual, 1 s reactions | 14.3 | 46.9 | 84.2 | 159.1 |
| **casual, late +60** (200 min) | 17.0 | 48.3 | 105.8 | 185.5 |
| opt | 11.0 | 22.6 | 66.3 | 102.6 |
| opt, late +60 | 7.6 | 24.9 | 68.0 | 109.0 |
| **today's game** (same casual bot, `--baseline`) | never | never | never | – |

### Brief targets
| Target | Result |
|---|---|
| Clear first goal; first $ quickly | Goal bar. First model live and first $ at **1.4 min** (sim); about 2.5-3 min for a human. |
| ≥ $1-3k/min by minute 5-10 | casual **$1,824 / $2,146** (5 runs: 1,663-1,932 at min 5; 1,970-2,603 at min 10). Late joiner $1,165 / $1,773. **Met.** |
| "Office 2" (Startup Campus) at 25-40 min | median **42.5** (26.8-53.2). **Close**: 2 of 5 fresh runs inside, 2 at 42-47, 1 at 53. The garage adds an earlier goal (Founder HQ at **~10 min**). |
| "Office 3" (Innovation) at 70-100 min | **80-92** in every fresh run; late joiner 105.8. **Met.** |
| "Office 4" (Global) at 2.5-3.5 h | **149.5-180.3 min**; late joiner 185.5. **Met** (one run 0.5 min early). |
| Wages 25-45 % of revenue in the mid game | casual 45/60/90/120 min: **25 / 36 / 30 / 17 %**. The 120-min dip: the 7B model doubled revenue while the stage-4 staff cap of 128 was already full, so HR could not hire. It returns to 38 % at 180 min after Global HQ (240 staff, salary ×1.8). Opt: 32 / 33 / 9 / 20 %. Mostly met; the post-7B dip is a known gap. |
| Staff decisions matter | without hires (`--hire none`): revenue at 180 min **$26.7k vs $104k**, and Global HQ is never reached. HR budget 25 % vs 55 %: Global at 155 vs 158 min (the budget matters less than the stage caps). |
| No collapse | Revenue rises in steps and never falls below the previous stage's level (the only dip is −8 % at 30 min). Today's game collapses to **$2/min** and −$47,756 cash in the same bot (`out2_base_casual.txt`). |
| No runaway | Plateau: casual $104k → $121k → $119k at 180/240/300 min; opt $195k → $210k at 90-180 min. Bounded by pools, capacity and the 99 cap. **But cash piles up**: $8.7M at 300 min (casual), $11.7M at 180 min (opt). See the risks. |
| Late joiner OK | Founder HQ at 17 min (vs 10), $1.2-1.8k/min in minutes 5-10; reaches every stage. B2B clients are per player, so they work regardless of server age. **Met.** |

### Other probes (casual unless noted)
- No client pipeline (`--noclients`): Global HQ never reached in 180 min. Clients are the "second engine" (19 % of income at minutes 5-10).
- Auto-pricing off: Global at 174.7 min instead of 151.3.
- These come from a single run each; the variance across seeds is ±10-25 min for Campus.

---

## 10. Risks, and what to cut first

**Risks**
1. **End-game cash pile.** Income is bounded, but at stage 5 there is nothing to buy: $8.7M at 300 min. Needs an end-game sink that adds goals without raising income:
   - regional offices abroad (repeatable buildings);
   - "Moonshot" research;
   - cosmetics.
   This is a content task, not a balance one.
2. **Skill gap.** Opt earns about 2× casual at the plateau and reaches Global at 103 min vs ~150. Auto-pricing closes part of the gap. A further lever if needed: soften `bizSens` or the premium rule.
3. **Multiplayer market.** The sim has one human player. With 12 players, the shared softmax splits demand, so per-player app income falls. Mitigations already in the design:
   - capacity, not demand, limits most players early;
   - clients are per player.
   Test with 2-4 sim players before release.
4. **Many new pieces of state:** profiles (absence, vacation), clients, calendar, trainings map, Lab level. Each needs `Template.migrate` cleaners and a DATA_VERSION 6 step. The rolling-update kick risk applies.
5. **Variance in the Campus timing** (27-53 min). It comes from night phase and model-training luck. Acceptable, but the goal bar's ETA must be honest.
6. **Not simulated** (designed, numbers given, effect unverified):
   - morale and room quality;
   - department seat limits and the overflow weight;
   - parallel training slots;
   - the night crew;
   - multiplayer;
   - a human's real reaction times beyond the 10 s bot.
7. **The bot is greedy and smart about saving.** A distracted human may be slower. The goal bar and Save mode are part of the design for exactly that reason.

**Cut order if time runs out** (each cut keeps the economy runnable):
1. Night crew, room quality Q, café host and barista effects (pure flavour).
2. Guest-house booking simulation: keep the building and a fixed +10 % win chance for regional clients, with no room income.
3. Abroad trips as physical travel: keep them as timers with costs (the world-map city and airport visuals can come later).
4. Lab levels (researchers then idle after the tree; raise the research tree costs instead).
5. Parallel training slots (keep 1 slot; the sim already uses 1).
6. Auto-pricing quality rule (keep only "servers full → +1 step").

**Never cut:**
- the NPC fix;
- serving capacity;
- product lines and the anti-clone rule;
- the flat hiring fee and real salaries;
- the expected-value workforce formula;
- the garage stage and the save migration;
- the client pipeline (it carries late joiners and the B2B story the user asked for).

---

### Appendix A: code hooks per system (file:function)
| System | Change | Where |
|---|---|---|
| Stages | 5 office entries, slot and thermal tables, start money, `tierForOffice`, garage generator, DATA_VERSION 6 + MIGRATIONS[5] (office + 1) | EmpireConfig.OFFICES (:4-9); HardwareConfig.slots/thermal (:52-60); GameConfig (:6, :19); BuildingPlan (:14, :79-131, new `tierForOffice`); PlotService.refresh (:83-99); StaffAssignment.assign (:45-46); HeadquartersDesign.build + new GarageDesign; Template MIGRATIONS (:44-49); NPCService.init (:66); AdminService tier commands |
| Roles and pay | salaries, flat fee, `sales` role, salary level per stage | EmpireConfig.ROLES (:10-15); EmpireMath.hireCost (:112-114) and bonuses (:115-126); EmployeeConfig.ROLES/TASKS (:9-31, add `sales` tasks at Customer Desk); DepartmentConfig (`customers` department) |
| Workforce | expected-value productivity, absences, morale | WorkforceMath.count/capacity (:21-38); StaffService tick (:327-369; offscreen branches :342-352); EmployeeConfig.productive (:89-95) and a new `onDuty(e,hour,day)`; profile fields via EmpireMath cleanProfile/profilesConsistent (:26-49), SessionService.profileSignature, StaffAssignment.profile, Rig.Profile |
| Market | FIT 20, pools ×0.5, price menus, business sensitivity, freshness, line factor, capacity, growth curve, NPC curve | MarketConfig (:30-88); MarketMath.tick (:85-165) + utility (:40); MarketService.entry (:48-51) and tick (:184-205); EmpireMath.bonuses.revenue (:121); NPCService.tick (:86, the release line after it) |
| Models | one model per line + migration, line limit per stage, fine-tune fix and cap, stats cap 99, slots map | AIModelService.releaseModel (:459-490), improveModel (:397-423), finish (:190-233), startTraining (:295-395); EmpireMath.boostStats (:130-139); Types.TrainingState (:57-72, :101) and the 30 readers listed in models.md |
| Clients | new ClientService (leads, trips, retainers), one catalogue, remote `ClientAction`, removal of the auction and daily contracts | new `ServerScriptService/Server/Services/ClientService` (tick in Main's per-player loop); EmpireMath.new (:12-17: `clients={accounts={},pipeline={},cool={}}`); Template.migrate cleaner; MarketService businesses/leases (:20-34, :125-167) removed; EmpireService.deliver (:100-116) removed; Net.FUNCTIONS; BuildingStateService P.customers (:409-434) |
| Trips and fleet | car lease per Account Manager, client-side cars leaving through the barrier, hotel and flight bills | CampusConfig.CARS (:15-20, `lease`); CampusMath.new (`fleet`); VehicleService build split (vehicles.md hook 2); DoorService barrier open for client-drawn cars; TravelController (client); Economy.applyFlow |
| Campus services | operations staff wages, food, utilities per stage | EmpireService.tick (:162-163, add `CampusOps.perDay(stage)/1200` to the flow and to `live.cost`); EmployeeConfig.OPERATIONS_JOBS (:11) per stage; StaffService break check (:154) with relief cover |
| Guest house | building, occupancy income, workshop bonus | BuildingPlan `HOTEL` + `guest` class (hotel_site.md hooks); new GuestHouseService; ClientService win chance |
| Calendar | world hour from server time; company day from `empire.seconds`; studio key; contracts removed | StaffService (:33, :327-329) via a new shared `Clock` module; `Staff.now()` (:382); StudioService.deliver (:67); EmpireService.daily stays on the UTC day |
| Clarity UI | next-goal bar, Save mode, auto-price explanations, product shelf, clients tab, HR calendar | HUD (:127-131); AssistantService.briefing (:112-223) and insight (:225); EmpireApp tabs (:462, :493); LabApp release view (forecast fix :722/:942); MarketApp (:286-431); BuildingStateService screens |

### Reproduce
```
cd scratchpad/agents/design_clarity/economy
./runset2.sh casual "--profile default --think 10 --minutes 180"
./runset2.sh opt "--profile opt --minutes 180"
./runset2.sh casual_late60 "--profile default --think 10 --late 60 --minutes 200"
python3 summarize.py out2_casual.txt      # tables and the cost/income shares
```
- Design numbers are the defaults in `patches2.luau`; override them with `--set key=value`.
- Today's game: `--baseline`.
