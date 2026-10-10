# AI Empire: company logic with a robust economy

**Focus of this design.** The economy must stay within limits, have no exploits and be fair to every player on a server. Concretely:
- no collapse and no runaway;
- stacking copies of one model must not pay;
- a company earns the same whether anyone watches it or not;
- a player who joins a server late is not worse off;
- every new income and every new cost is sized after the market fix;
- there are only a few parameters, and each is easy to tune.

Every mechanic the user asked for is still delivered.

**Evidence.** All numbers in sections 3, 4 and 9 come from the economy simulator. It loads the real game services in the headless mock, applies this design as in-memory patches and plays a greedy bot, one tick per second.

- **Simulator and runs:** `agents/design_robust/economy/`
  - `sim.luau`: the bot
  - `patches_robust.luau`: every number of this design, overridable with `--set k=v`
  - `proposed/CompanyOps.module.luau`: the new B2B pipeline, running costs and calendar, as a loadable module
  - `proposed/MarketMath_tick.luau`: the new market tick
  - `out_G*.txt`: one output file per run
- **Reproduce:** `./par.sh "label|--robust --profile default --minutes 180"`
- **Sources:** the generated snapshot of `work/src` (taken 15:38). Its economy files match today's `work/src`, except the `session.live` merge fix in `MarketService.tick`, which does not affect the simulated numbers.

Paths below are relative to `work/src` unless they start with `agents/`. Each formula names its hook as `File:function`.

---

## 0. One-page summary

**Why the economy breaks today** (economy.md, models.md, time_staff.md):
- The NPC labs improve without limit, so player income drops to zero within 45 minutes. A player who joins late earns almost nothing from the start.
- Copies of one model add to each other: two identical models earn ×1.94 of one, ten earn ×7.9 (`out_clonetest_baseline.txt`).
- Staff cost is mostly hiring fees. Staff work is cosmetic. Employees nobody watches produce 100 % around the clock.
- Customers are five separate systems, each a once-a-day click.

**What this design does**

| # | Change | Bound it creates |
|---|---|---|
| 1 | **Market fix:** NPC labs sit in a fixed band (overall 56 → 62, then flat). Competition is softer (`FIT_SCALE` 10→20) and pools are smaller (×0.2). | No collapse. Every server and every join time sees the same market. |
| 2 | **Reach cap per office stage:** 0.14 / 0.20 / 0.35 / 0.55 / 0.75 of a segment. Model fit above 75 counts only 35 %. | No runaway. Market income grows with the building, not with stat inflation. |
| 3 | **Company nest:** the player's live models compete as one nested-logit group (λ = 0.05). Reach is shared, live product slots are 1–5, and models age. | A copy adds +4 %. Several models only pay when they are specialists or newer versions. |
| 4 | **B2B pipeline:** 12 catalogue clients. An account executive drives or flies to the client, a trust bar fills, then the client pays a daily retainer. Every step is deterministic. | A second scalable income that is capped by the catalogue and by client slots per stage. |
| 5 | **Real staff economy:** wages per game day at about ⅓ of revenue in the mid game, flat hiring fees, paid operations jobs, and output by department from the schedule. | Staff decisions matter, and output does not depend on who watches. |
| 6 | **Garage Lab stage** below today's tier 1. Old saves move up one office index. | A clear first goal at about minute 13. |
| 7 | **One calendar:** game day = 1200 s, a saved company date, a billing month of 3 days, and trips, terms and vacation counted in play time. | No real-day or game-day mismatches. |

**Casual bot results** (`out_G1_casual.txt`)
- Income: $1,730/min at minute 5 and $2,481/min at minute 10.
- Offices at minute 13.4 / 24.4 / 96.5 / 165.4.
- Income stays bounded: 65,003 / 69,144 / 77,485 $/min at minutes 240 / 300 / 360.
- Wages (hired + operations) are 42 % of income in minutes 45–60 and 29 % in minutes 120–180.

**Other runs**
- **Joining a 60-minute-old server:** the same curve, with offices at 13.4 / 24.4 / 97 / 165.8.
- **Optimizing bot** (pricing search, three product lines, three refinements): ×1.14 the casual income at minute 180, offices at 2.7 / 33.2 / 67.7 / 99.7. It plateaus at 70,680 / 77,111 / 72,929 / 83,667 (minutes 180 / 240 / 300 / 360) $/min, after a brief peak of $116k/min at minute 90.

---

## 1. Core loop and the first 10 minutes

### The loop in one paragraph (for a 13-year-old)

You start in a garage with $10,000 and an old laptop. You train an AI model and launch it. People pay a monthly subscription to use it, and other apps pay for every word your AI writes. With that money you:
- hire people;
- buy GPUs;
- train better models.

Your account executives drive to companies in Business City, or fly abroad, and sign contracts that pay you every day. When the garage is full, you move into a real headquarters. Every bigger building lets you:
- reach more customers;
- run more AI products;
- sign bigger clients.

A bigger building also costs more to run. Your models get old, so you keep training new versions. Your team only works in the daytime and takes vacations, so you need enough people.

### First 10 minutes, minute by minute

These are casual bot events in `out_G1_casual.txt`. The bot clicks instantly, so a real player is a little slower.

| Time | What the player sees | What happens in the economy |
|---|---|---|
| 0:00 | The fenced plot "Future HQ of *Nimbus Labs*" with a small garage lab at the driveway. Inside are the founder desk, the laptop, a whiteboard and 4 empty desks. Assistant goal: **"Launch your first AI."** | $10,000 cash. Quest "Open the doors" +$1,200. |
| 0:00–1:20 | Buy data packs, then press Train (100M, about 80 s on the laptop). | Training costs $1,280 plus the data packs. Quest "Feed the model" +$1,800. |
| 1:20 | **Launch.** | Quests "First run" +$2,500 and "Launch day" +$3,000. **The first subscription money comes in at about minute 1.5.** |
| 1:50 | Hire the first 4 people. The garage cap is 4: engineer, account executive, curator, researcher. | Flat agency fees of $0.8–1.4k each. Wages start at $444/min. |
| 2:15 | 5,000 users reached. Buy a consumer GPU and train a 500M model. | Quests "Word gets around" +$10,000 and "Upgrade the rig" +$1,500. |
| 3:00–6:00 | The account executive drives a leased compact ($140/day) to ByteWorks in Business City. Website briefs come from the Studio. | Studio briefs pay +$700 / +$1,300 / +$1,600 (×0.2 rule, per game day). The trip costs $110 same-day or $370 with a hotel night. |
| 4:20 | Release v2 (500M). It **replaces** v1 and takes over its users. | Income **≈ $1,730/min at minute 5**: subscriptions + API, wages −$444/min. |
| 6:40–10:00 | Morning: the staff come back. Night ran from 1:40 to 6:40 (lights dimmed, everyone at home). The clock is shared by the server, so the timing depends on when you join. The assistant shows "Move out of the garage: $12,000". | The income limit of the garage (reach cap 0.14) holds: **$2,481/min at minute 10**. |
| ≈ 13:24 | **Move to Founder Headquarters** (old tier 1). The building rises, the café opens and 4 operations staff arrive. | $12,000. Quest "Out of the garage" +$5,000. Staff cap 24, client slots 3. |

The first $ arrives about 90 s after start, at the first launch. The first B2B pilot fee ($10,500 from ByteWorks) arrives at about minute 13, on company day 2 at 12:30.

---

## 2. Office stages

`EmpireConfig.OFFICES` grows from 4 to 5 entries. Stage = office index. HQ tier = stage − 1, as used by `BuildingPlan`, `HeadquartersDesign` and `StaffAssignment`.

| | 1 Garage Lab (**new**) | 2 Founder HQ (old T1) | 3 Startup Campus (old T2) | 4 Innovation Campus (old T3) | 5 Global AI HQ (old T4) |
|---|---|---|---|---|---|
| Price | start | $12,000 | $40,000 | $300,000 | $1,800,000 |
| Hired staff cap | 4 | 24 | 64 | 128 | 240 |
| Operations staff (automatic) | 0 | 4 | 8 (+2 guest house) | 12 (+2) | 16 (+2) |
| GPU slots (`HardwareConfig.slots`) | 2 | 6 | 12 | 24 | 48 (+48 with cluster research) |
| Thermal budget per cooling level | 10 | 20 | 40 | 60 | 80 |
| Market reach cap (`MarketConfig.STAGE_REACH`) | 0.14 | 0.20 | 0.35 | 0.55 | 0.75 |
| Live AI products | 1 | 2 | 3 | 4 | 5 |
| B2B client slots | 1 | 3 | 5 | 8 | 12 |
| Parallel training slots (max) | 1 | 1 | 2 | 3 | 4 |
| Base research points/s | 0.10 | 0.15 | 0.30 | 0.60 | 1.0 |
| Building upkeep per game day | $200 | $2,000 | $8,000 | $25,000 | $60,000 |
| Cafeteria | pizza ($4/person/day) | café + chef ($8) | café | café + 9 pantries | café + pantries |

### What each stage unlocks in gameplay

| Stage | Unlocks |
|---|---|
| **1 Garage** | One product line and one client: CloudDesk or ByteWorks, a city trip. Studio briefs. Laptop plus 2 GPUs. You can train up to 1B (24 GB VRAM with 2 consumer GPUs). |
| **2 Founder HQ** | 2 product lines. 3 clients: StudySpark, Pixel Games and PixelForge open. Café with chef (lunch → morale), reception (applicants arrive faster), research rooms (14 researcher desks), 6 GPU slots. |
| **3 Startup Campus** | 3 product lines. 5 clients: North Logistics, Nova Logistics and Atlas Search open. **Guest House** (the company hotel, 12 rooms; client workshops give +0.10 trust per visit). Security, IT and an HR coordinator (automatic vacation planning). 2 parallel training slots. Night shift becomes available. |
| **4 Innovation Campus** | 4 product lines. 8 clients: Ledger Finance and Helix Research open, **the first trips abroad via the airport**. A fleet manager. 3 training slots. Research desks go from 2 to 23 (the old T2→T3 jump). |
| **5 Global AI HQ** | 5 product lines. All 12 clients: Orbit Systems and Nova Infrastructure, the biggest retainers. 4 training slots. 57 research and 28 evaluation desks, Platform Ops, 48 GPU slots. |

So a bigger building means:
- more market (reach cap);
- more products;
- more and bigger clients;
- more compute and desks;
- a higher fixed cost (upkeep and operations wages).

### The Garage Lab (stage 1)

**The building.** A detached 2-car garage converted into an office, about 24 × 16 studs, on the front lawn next to the driveway (x 70..92, z −200..−150 is today's visitor-parking strip). It holds:
- the founder's desk and 4 desks with laptops;
- a whiteboard wall;
- a 2-slot GPU shelf with the old laptop, which lights a blade per GPU;
- a coffee machine, a fridge, a sofa and pizza boxes;
- a roll-up door, open in the daytime.

The Founder's Hatch stays parked outside.

**The plot.** The rest of the plot is a fenced construction site:
- hoarding with "Future HQ of ⟨company⟩", a progress board ("Move out of the garage: $x / $12,000") and a site cabin;
- the existing visitor bays;
- no B1 garage, ramp or barrier yet.

**Staff.** Founder plus 4 hires, 5 people in total, which matches the request for "founder + 3–5 people". No operations staff: the founder answers the door and orders pizza, which costs $4 per person per game day.

**Code.** A new `GarageDesign` generator (about 400 parts, 4 lights) that `HeadquartersDesign.build` uses when `office == 1`. Rigs come from `StaffAssignment`, which needs only 4 desks plus the founder for this stage. The `Intro` text already says "You start in a garage" (Intro.module.luau:114).

### Migration of old saves (office index +1)

- **Version and transform.** `GameConfig.DATA_VERSION` 5 → 6. `Template.MIGRATIONS[5] = function(d) if d.company and d.empire then d.empire.office = math.clamp((tonumber(d.empire.office) or 1) + 1, 2, 5) end end`. Old buildings stay the same: old tier k becomes stage k+1, which is still HQ tier k.
- **Clamps.** `Template.migrate:125` clamp becomes `1..5`. `NPCService.init` sets `d.empire.office = 3` so the NPCs keep their 12 slots.
- **Office index users to change** (from grep):
  - `HardwareConfig.slots/thermal`: 5-entry tables;
  - `EmpireMath.bonuses` points;
  - `HeadquartersDesign:39`, `BuildingStateService:99/121/603`, `StaffAssignment:46`, `StaffService:69`, `FacilityService:402/440`, `DoorService:446` (the `OfficeTier` attribute becomes the HQ tier = stage − 1, and 0 means the garage);
  - `AdminService` tier1..4 → stage1..5;
  - `EmpireMath.progress` "office";
  - tests.
- **Starting money.** `GameConfig.START_MONEY` 25,000 → 10,000. This affects new companies only, because `Template.new` is used only for new saves.
- **Quest.** The quest "Out of the garage" (target office ≥ 2) finally matches its name. Old saves at old tier 1 can now claim its $5,000 once. That is harmless.

---

## 3. Income sources

### 3.1 Consumer and API market (fixed)

**Hook:** `MarketMath.tick` is replaced; the full text is in `agents/design_robust/economy/proposed/MarketMath_tick.luau`. Also `MarketMath.fit`, `MarketMath.agePenalty` (new) and `MarketService.tick`.

For each segment *s*, live player model *k* and NPC model *n*:

1. **Fit with a soft cap.** `fitEff = fit` if fit ≤ 75, otherwise `75 + 0.35·(fit − 75)`. This is in `MarketMath.fit`.
2. **Utility.** `u_k = (fitEff_k − 50 − 8·min(1, vage_k/3600)) / 20 − sens_s·price_k/norm`. `FIT_SCALE` is 20 (was 10). `vage` is the model's version age; see 7.
3. **Company nest.** `IV = u_max + λ·ln Σ_k e^{(u_k−u_max)/λ}` with λ = `NEST_LAMBDA` = 0.05. Then:
   - `share_nest = e^IV / (e^{outside} + Σ_n e^{u_n} + e^IV)`;
   - `share_k = share_nest · e^{u_k/λ} / Σ_j e^{u_j/λ}`.
4. **Company reach.** `reach_s = min(STAGE_REACH[stage], 0.01 + 0.3·rep/100 + max_k hype_k·e^{−age_k/600} + Σ_k organic_k)`. Each model's organic share drifts toward `0.6·share_k`, so its sum equals the single-model value.
5. **Users.** `target_k = pool_s · POOL_SCALE(0.2) · reach_s · share_k`. Users ease toward it as today (rise 40 s, fall 120 s).
6. **Revenue.** Unchanged per user: `users·sub/3600` per second, or `users·tokens/1e6·api/3600`. Then it is multiplied by:
   - marketing `1 + 0.6·(1 − e^{−O_growth/10})`;
   - Global Distribution research +0.15;
   - the market cycle factor, which averages ×1.08 (`MarketService.tick`).

**The NPC rival fix (`NPCService`).**
- Each of the 3 labs starts at its s500m stats ×1.2, capped at 64 per stat, so overall is about 56.
- Further training is capped at 64 per stat. Overall reaches 61.8 within about 10 minutes and then stays flat on every server forever.
- The NPC API price can no longer undercut below $1.00 (was $0.25).
- Result: the market a player meets does not depend on server age. That removes the root cause of the old collapse and of the late-joiner problem.

**Other players.**
- `MarketConfig.PLAYER_RIVAL_WEIGHT = 0`. `MarketService.tick` passes only NPC models as rivals, so other players' models no longer take your consumers.
- Cash bought with Robux therefore cannot hurt anyone (monetization.md), and a rich player cannot crush a newcomer with a cheap clone.
- Players still meet each other in:
  - the API-access marketplace (`BuyModelAccess`, unchanged);
  - leaderboards;
  - visits.
- The knob can be raised later if competition between players is wanted.

**Anti-clone rule.** Nest plus shared reach plus product slots. Market-only test on the real code (`--clonetest`: s1b overall 62, reputation 30, one hour), revenue relative to one model:

| Live set | Today | This design |
|---|---|---|
| 2 identical clones | ×1.94 | ×1.04 |
| 3 identical clones | ×2.82 | ×1.07 |
| 5 identical clones | ×4.44 | ×1.11 (5 = the stage-5 product cap) |
| 10 identical clones | ×7.88 | ×1.15 (blocked: slots) |
| best single specialist (creative) | ×1.24 | ×1.20 |
| 3 specialists (coding + reasoning + creative) | ×3.14 | ×1.29 |

Copies are now worth almost nothing. A specialist portfolio is worth +8 % over the best single specialist in the consumer market. Specialists pay mostly through B2B, because clients ask for different stats (3.2), and through newer versions (7).

**Upper bound.** At share 1, market revenue ≤ about $124k/min × reach cap at $5 / $2 prices. In practice the share is ≤ 0.5, so the bound is about $47k/min at stage 5 before multipliers. In the casual run the market part is about $43k/min in minutes 120–180 and about $48k/min at minute 360 ($77,485 total − $29,250 B2B).

### 3.2 B2B clients: sales pipeline, trips, daily retainers

**Hook:** `CompanyOps.step(session, dt, Economy, clock)`, called from `EmpireService.tick` after wages. It is pure and deterministic, and the full module is in `agents/.../proposed/CompanyOps.module.luau`. It replaces:
- the server-wide lease auction (`MarketService.tickGlobal` / `businesses`), which is removed;
- `EmpireService.deliver` (the daily contracts).

**One catalogue per player** (`CompanyOps.CLIENTS`; it keeps the old `CONTRACTS` ids, so old `empire.contracts` stays harmless). Retainers are shown after `B2B_SCALE` 1.5.

| Client | Wants | Stage | Retainer / game day | Tokens/month | Trip |
|---|---|---|---|---|---|
| CloudDesk | reliability ≥ 24 | 1 | $6,000 | 50 | city |
| ByteWorks | coding ≥ 36 | 1 | $10,500 | 100 | city |
| StudySpark | math ≥ 40 | 2 | $13,500 | 120 | city |
| Pixel Games | coding ≥ 45 | 2 | $18,000 | 160 | city |
| PixelForge | creativity ≥ 48 | 2 | $21,000 | 200 | city |
| North Logistics | reasoning ≥ 52 | 3 | $30,000 | 300 | city |
| Nova Logistics | reliability ≥ 58 | 3 | $36,000 | 400 | city |
| Atlas Search | knowledge ≥ 62 | 3 | $45,000 | 500 | city |
| Ledger Finance | math ≥ 66 | 4 | $60,000 | 700 | abroad |
| Helix Research | math ≥ 72 | 4 | $82,500 | 900 | abroad |
| Orbit Systems | reasoning ≥ 78 | 5 | $112,500 | 1,400 | abroad |
| Nova Infrastructure | coding ≥ 84 | 5 | $150,000 | 2,000 | abroad |

All 12 together pay $585k per game day, about $29k/min. That is the hard B2B ceiling.

**Pipeline**, every tick, automatic:

1. **Leads.** A client is a lead when the office stage is high enough, the best live model has the stat, and inference capacity is free: `Σ tokens ≤ GPU throughput·100·thermal` (today's lease rule).
2. **Pick.** A free account executive (AE) takes the first job in this order:
   - a renewal whose term ends within (trip length + 0.5 day);
   - otherwise the highest retainer it may still sign, while accounts plus pending signings stay below `min(stage client slots, 3·AEs)`.
3. **Trip.** Trips start only between 08:30 and 16:00 on the visible server clock, and only when cash ≥ trip cost + $500.
   - **City:** the AE drives a leased company car to Business City. A meeting that starts before 13:00 returns the same day after 0.3 game day (6 real minutes). Otherwise the meeting runs past 18:00: one hotel night, back at 09:00.
   - **Abroad:** AE + engineer drive to the airport, fly, sleep 2 hotel nights, and are back after 2 game days.
4. **Trust.** Each visit adds `p = clamp(0.5 + 0.025·(stat − required) + 0.05·(average AE skill − 3) + 0.10·[guest house], 0.35, 1)`. The client signs when trust ≥ 1. There are no dice: the same company always gets the same result. The UI shows "trust 67 %".
5. **Sign.**
   - The pilot fee (one day of retainer) is paid at once. This replaces the old daily contract reward.
   - Reputation +1.5.
   - The retainer flows per second at `retainer/1200`, plus serving cost `tokens·serveCost/3600`.
   - Its compute is reserved: training runs at `max(0.3, 1 − reserved/throughput)` (`EmpireMath.trainingRate`).
6. **Term and renewal.** The term is 6 game days (2 billing months). The AE makes a check-in trip before it ends; the account does not lapse while that trip is under way. A client is lost when the term ends without a visit, when no live model meets the requirement any more, or when capacity is gone.

**Sizing (casual run).**
- B2B is 20 % (+ 12 % pilot fees) of income in minutes 45–60 and 19 % (+ 6 % pilot fees) in minutes 120–180.
- It holds 11 accounts at minute 240 ($21,750/min) and all 12 by minute 300 ($29,250/min, the hard ceiling).
- Trips cost 1 % of running costs.

**What is simulated.** The pipeline runs in the simulator exactly as written, as a module loaded into the real tree. Movement and driving are not simulated, and neither is the engineer's 2-day absence on abroad trips (only the cost of the second traveller is). The design draws cars on the client only (world_map.md), and the money does not depend on them.

**Player hooks.** A remote `DealAction {pin, skip, joinMeeting}`, using the `RecruitAction` pattern.
- If the founder drives to the meeting himself and presses "Join meeting" in the client's lobby, the visit adds +0.15 trust.
- This is optional and not simulated.

### 3.3 Pilots and contracts

The old `CONTRACTS` daily click on real UTC days is replaced by the **pilot fee**: the first day of a retainer is paid on signing.
- It counts as revenue: `applyFlow` category `pilot`.
- Quest "Reliable supplier" (3 contracts) counts signed deals (`e.contractsCompleted`).
- Pilots are 12 % of income in minutes 45–60 and 6 % in minutes 120–180. They come in bursts when a stage opens new clients.

### 3.4 Studio

`StudioService.deliver` changes in two ways:
- The cooldown is the **game day of play time** (`floor(empire.seconds/1200)`) instead of the real day.
- The reward is ×0.2 (`studioScale`), so the five briefs pay at most $7,600 per game day, about $380/min.

A real bug was found and fixed while simulating: a studio project stalls forever when its source model is retired. With `replaces` (7), a retired model records `replacedBy` and `StudioService.source` follows it.

Studio share: 13 % of income in minutes 5–10 (the early boost), and about 1 % or less later.

### 3.5 Guest House (company hotel)

From stage 3. Site and part budget as in hotel_site.md: 12 rooms, west wing.

**Money**
- Outside guests: `12 rooms × 60 % × $300/night` = $2,160 per game day income.
- Costs: utilities $400 per day, plus 2 operations staff (housekeeper and night receptionist, $720/day each).
- Net ≈ +$320 per day. It never earns big money; that is deliberate.

**Function**
- Client workshops: +0.10 trust per visit in the B2B pipeline.
- Candidates from far away stay overnight.

In the simulator it is an injected flow inside `CompanyOps.step` (`guest`, $108/min). Room bookings and guest NPCs are not simulated.

### 3.6 Retail

The Campus Arcade is unchanged: `FacilityService.economyTick`, $12/ticket. It stays flavour at under 1 % of income. The simulator re-implements it as before.

### 3.7 One-offs

- Quests total $77k.
- The daily login reward stays on real UTC days, because it is a real-life login reward.
- These are an onboarding cushion and dominate only the first minutes.

### 3.8 Robux

Robux cannot create market income:
- the market does not compete with other players;
- `PLAYER_RIVAL_WEIGHT` is 0;
- nothing sold changes market shares.

Cash packs follow monetization.md: a fixed share of the *next office price*, never minutes of income. Ids default to 0, which keeps the shop hidden.

### Income shares (casual run `out_G1_casual.txt`)

These are averages over the windows ending at minutes 10, 60 and 180.

| Income source | min 5–10 | min 45–60 | min 120–180 |
|---|---:|---:|---:|
| Consumer + API market | 2,213 (86 %) | 10,324 (60 %) | 42,738 (75 %) |
| Studio briefs + published projects | 323 (13 %) | 161 (1 %) | 106 (0 %) |
| Retail (arcade) | 24 (1 %) | 72 (0 %) | 166 (0 %) |
| B2B retainers | – | 3,435 (20 %) | 10,760 (19 %) |
| Pilot fees (signing) | – | 2,000 (12 %) | 3,350 (6 %) |
| Guest house | – | 108 (1 %) | 108 (0 %) |
| Quests | – | 1,000 (6 %) | – |
| **Total** | **2,560/min** | **17,100/min** | **57,228/min** |

---

## 4. Costs

All recurring costs are booked per second through `EconomyService.applyFlow`, with a new 4th argument `category` that the ledger and UI read. They are shown per game day.

| Cost | Formula and numbers | Hook |
|---|---|---|
| **Wages (hired roles)** | Salary per game day. It accrues every second, day and night, including paid vacation and sick days, as for real salaried staff. Researcher $2,040, engineer $2,448, curator $1,530, growth manager $2,448, account executive $2,856 (×1.7 of the base table in `patches_robust.luau`; $1.28–2.38 per second). A night-crew member costs ×1.3. | `EmpireConfig.ROLES.wage`, `EmpireMath.bonuses.wage`, `EmpireService.tick` |
| **Hiring fee** | **Flat** agency fee of about half a day's wage: $1,000 / 1,200 / 800 / 1,200 / 1,400. It was quadratic and dominated staff cost. Interview hires keep their own price. | `EmpireMath.hireCost` |
| **Operations staff** | Count per stage 0 / 4 / 8 / 12 / 16 (+2 with the guest house). $720 per game day each. Hired, replaced and covered automatically by HR. | `CompanyOps.step` (`ops`) |
| **Building upkeep** | $200 / 2,000 / 8,000 / 25,000 / 60,000 per game day. Covers power for lights, HVAC, cleaning supplies, insurance and rent for the garage. | `CompanyOps.STAGES.upkeep` |
| **Cafeteria food** | (hired + operations staff) × $8 per game day ($4 pizza in the garage). Lunch is a free perk for staff. | `CompanyOps.step` (`food`) |
| **Fleet leases** | One leased compact per account executive, $140 per game day. The boss's own cars stay one-off purchases (`CampusConfig.CARS`). | `CompanyOps.FLEET_LEASE` |
| **Trips** | City same-day: car $50 + per diem $60 = $110. City overnight: + hotel $200 + 1 per diem = $370. Abroad (2 people): 2 × (flight $1,400 + 2 nights × $280 + 2 days × $80 per diem) + car $50 = $4,290. Paid at departure. | `CompanyOps.tripPlan` |
| **Guest house** | Utilities $400 per day + 2 operations staff. | `CompanyOps.GUEST` |
| **Serving + power** | Unchanged: tokens × size serveCost per month, × (1 − 0.2·(1 − e^{−O_eng/10})) from engineers, × 0.85 with Quantization research. Power is throughput·$0.025/s while serving. B2B serving uses the same rule. | `MarketMath.tick`, `MarketService.tick`, `CompanyOps.step` |
| **Investments** (not running costs) | Training (work × costPerWork), data packs, GPUs, cooling, research, marketing, offices: all unchanged. Refinement costs plan.cost × (1 + 0.5·iteration), with at most 3 per model. | unchanged services |

### Cost shares (casual run)

| Running cost | min 5–10 | min 45–60 | min 120–180 |
|---|---:|---:|---:|
| Wages, hired roles | 444 (85 %) | 6,880 (87 %) | 15,862 (78 %) |
| Building upkeep | 10 (2 %) | 400 (5 %) | 1,675 (8 %) |
| Fleet leases | 7 (1 %) | 21 (0 %) | 30 (0 %) |
| Trips (fuel, flights, hotels, per diem) | 22 (4 %) | 7 (0 %) | 158 (1 %) |
| Cafeteria food | 1 (0 %) | 30 (0 %) | 65 (0 %) |
| Consumer serving + power | 36 (7 %) | 229 (3 %) | 2,047 (10 %) |
| Operations staff wages | – | 360 (5 %) | 539 (3 %) |
| Guest house utilities | – | 20 (0 %) | 20 (0 %) |
| B2B serving | – | 3 (0 %) | 47 (0 %) |
| **Total** | **520/min** (20 % of income) | **7,950/min** (46 % of income) | **20,443/min** (36 % of income) |
| *All wages (hired + operations) as % of income* | 17 % | 42 % | 29 % |

Hired wages plus operations wages are the dominant running cost, about 80 % of all running costs. The brief asked for staff decisions to matter, and they do: the bot only hires while profit stays above 25 % of revenue, which is the assistant's rule (8). The wage share settles between 29 % and 42 % of income in the mid and late game.

---

## 5. Staff and department production

### 5.1 One formula, watched or not

For department *d*, seats `S_d` come from `BuildingPlan` room desks (cached `Plan.deptSeats(tier)`):

> **O_d = ( Σ_{first S_d people} f(k_i) + 0.5 · Σ_{overflow} f(k_i) + 1.0 · Σ_{night crew ≤ S_d} f(k_i) ) × A_d(day) × M × Q_d**

- **f(k) = (7 + k)/10.** Skill 1–5, unchanged (`WorkforceMath.factor`).
- **A_d(day)** is the share of the department present that company day. Vacation and sick days are a pure function of (profile seed, company day); see 5.3. The mean is 0.90.
- **M** is morale (5.4), between 0.90 and 1.05.
- **Q_d** is room quality: 1.10 if the department's specialist room is in use, otherwise 1.0. The specialist rooms are datalab, control, evaluation, lab, hwlab, platform and studio.

**What changes**
- `WorkforceMath.count(e, role)` returns Σ O_d over the role's departments. It is computed from saved data only.
- The StaffService state machine no longer feeds money. It only animates the schedule, and it publishes `live.workforce.states` for the UI.
- So **a company produces exactly the same whether you, a visitor or nobody is near it.** The old "offscreen = 100 %, around the clock" branch (StaffService:342-352) and the 0.75 weight for walking are gone from the economy.

**In the simulator.** O = capacity × 0.90, with M = Q = 1 and no overflow. Production M is 1.0–1.05 and Q is 1.0–1.1, so the simulator understates staff output by 0–15 %. The only overflow under a casual staffing mix is at stage 5: 59 curators for 32 data desks, which gives about 23 % fewer curated tokens than simulated. Data is not the bottleneck there; see risks.

**Day and night**
- Output that accrues (research points, curated tokens, pipeline progress) is multiplied by `duty(clock)`. That is the share of staff on duty at that visible hour, normalised to a mean of exactly 1 per game day (`CompanyOps.duty`):
  - 0 at night;
  - 1.60 at 10:00 (the average employee is on duty 62.5 % of real time);
  - lower at lunch.
- So research stops at night, daily totals do not depend on when you play, and logging in at night is not an exploit.
- Output that acts as a level (marketing multiplier, serving cost, training speed) uses O_d and does not flicker. Users keep paying at night, because servers run 24/7.

### 5.2 What each department produces (every room kind mapped)

Seats per HQ tier T1/T2/T3/T4 come from building_meaning.md. The garage has 4 desks plus the founder.

| Department (role) | Rooms (`kind`) | Seats T1/T2/T3/T4 | Output | Hook |
|---|---|---|---|---|
| Data Ops (curator) | team "Data Operations", **datalab** | 11/32/32/32 | 300k curated tokens/s × O × duty; quality 0.65, or 0.85 after Data Cleaning, +0.05 while the datalab is staffed | `EmpireService.tick` curator block |
| Research, Design, Evaluation (researcher) | architecture, team "Architecture", **lab**, **evaluation**, focus, first_ai, secret_lab, prototype, project_meeting (reviews) | 14/29/55/107 | research points 0.6·O × duty; architecture bonus +5·(1 − e^{−O/10}) on every core stat of new models; stats capped at 99 | `EmpireMath.bonuses.points/core`, `boostStats` |
| Engineering, Training (engineer) | team "AI Engineering", **control**, **hwlab**, **platform** | 14/26/51/71 | training speed +0.15·O (as today); serving cost ×(1 − 0.2·(1 − e^{−O/10})); training slots `min(stage cap, 1 + ⌊O/8⌋)`; Training Control auto-resolves training events (existing `autoResolve`) | `EmpireMath.bonuses.speed/serving`, `AIModelService` |
| Growth (growth manager) | launch, team "Growth", **studio**, showroom | 12/25/25/45 (minus the customer desks below) | consumer revenue ×(1 + 0.6·(1 − e^{−O/10})): +5.7 % for the first person, +38 % at 10, +52 % at 20 | `EmpireMath.bonuses.revenue` |
| Deployment and Customers (account executive) | launch "Deployment & Growth", **support** (Customer Desk, Customer & Support) | 4+3/9+/9+/26+ | B2B accounts ≤ 3 per AE; trust +0.05 per skill step | `CompanyOps.step` |
| HR (HR coordinator, operations) | hr, F_ASSISTANTS | from T2 | automatic vacation and shift planning (≤ 10 % of a team away; without HR ≤ 15 %); applicants arrive 25 % faster | `RecruitingService.tick`, vacation plan |
| Kitchen and café (chef, kitchen team, café host, barista) | kitchen_boh, café, pantry | all | lunch capacity → morale (5.4) | StaffService lunch stages |
| Wellness | gym, sauna, lounge, recovery, terraces, roof | T2+ | morale +0.03 when present | morale |
| Data hall (IT) | datahall, compute ops, itdesk, ups | all | GPU slots per stage; IT on duty halves the "GPU failure" training event weight | `HardwareConfig.slots`, `ModelMath.rollEvent` |
| Reception and security | lobby, visitor_lounge, security | all | client and candidate visits; required for the guest house and night shift | RecruitingService, CompanyOps |
| Fleet | garage, fleet, workshop | all | leased cars; without a fleet manager (before stage 4) at most 2 trips at once | `CompanyOps` |
| Meeting rooms and boardroom | meeting, project_meeting, boardroom | all | meetings count as work (weight 1.0 in the schedule, no longer −20 %); the Project Room hosts model reviews | `EmployeeConfig.productive` |
| Decoration and circulation | print, phone, mailroom, delivery, storage, spine, corridors, WC, showers | all | none, and that is stated honestly in the assistant's building tour | – |

### 5.3 Working hours, night, vacation, sick days

**Shifts.** Today's personal shifts from the seed stay: start 07:45–09:00, end 16:30–18:00, lunch window. The on-duty curve (time_staff.md) is 0 % from 18:30 to 07:30 and 100 % from 09:30 to 15:30. Night means off duty.

**Night shift (optional, per department).** The player toggles a department, for example Data Ops. HR moves the overflow people beyond the day seats into a night crew, up to S_d.
- They work 22:00–06:00 on the visible clock. The department's lights stay on.
- They count 1.0 instead of 0.5, at a wage ×1.3.
- Night shift therefore pays only when a department is over its desks. It is a choice for big buildings, not a free +25 %.
- It needs security on duty (stage ≥ 3).
- Not simulated: the casual bot never exceeds seats before stage 5.

**Vacation**
- Each employee takes 1 day in every 12 company days (8.3 %). The day is `hash(seed, floor(day/12)) % 12`.
- HR shifts collisions so that at most 10 % of a department is away on one day.
- Vacation is paid.

**Sick days.** 1.7 % per person-day, also `hash(seed, day)`.

**Why this is robust**
- Absences are a pure function of saved data, so nothing new is stored per person.
- No new profile fields are needed, which avoids the 5-place profile-sync trap (`cleanProfile` / `profileSignature` / ...).
- Every server shows the same people away.
- The economy and the visible building use the same list. Absent rigs get `OffDuty = true` and their desk is freed (`WorkstationService.release`); `StaffKey` is untouched, so nothing is rebuilt.

### 5.4 Morale: the chef and lunch

> M = clamp(0.90 + 0.10·lunch + 0.03·wellness + 0.02·barista, 0.90, 1.05)

**Lunch share.** `lunch = min(1, meals / heads)`, where meals per game day = `min(60 × kitchen staff, 3 × café seats + 20 × pantries)`. Café seats are 53. The garage gets pizza, so lunch = 1 there.

**Automatic staffing gives M by stage:**

| Stage | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| M | 1.00 | 1.00 | 1.05 | 1.05 | 1.05 |

At stage 5, pantry lunches are needed. Without them lunch = 0.62 and M = 1.01.

**Lunch in the building** is a staged trip: counter → the chef plates (`Facility.deliverSnack` pattern from the assistant) → seat → plate on the table → dish return.
- Operations staff eat in their own window and never leave a post uncovered: HR relief cover, and no coffee breaks for posts (fixes StaffService:154).
- Morale moves only ±5–10 %, so a missing chef on vacation is visible but never a crash.

### 5.5 Operations staff become paid jobs with a real function

| Stage | Jobs (cumulative) |
|---|---|
| 2 (4) | receptionist, chef, kitchen assistant, facilities |
| 3 (8 + 2) | + lobby security, barista, IT admin, HR coordinator; guest house: housekeeper, night receptionist |
| 4 (12 + 2) | + visitor host, garage security, fleet manager, 2nd kitchen assistant |
| 5 (16 + 2) | + 2nd chef, café host, plant-room facilities, 2nd IT admin |

**Pay and posts.** $720 per game day each. Today's 12 operations posts (EmployeeConfig `OPERATIONS_JOBS`, RKS posts 301–312) cover stages 2–4. Stage 5 adds 4 posts.

**Functions:**
- facilities keep Q_d (1 per 40 rooms);
- reception and security enable visits and the guest house;
- kitchen staff provide lunch → M;
- IT protects GPUs;
- HR planning keeps absences ≤ 10 % (≤ 15 % without);
- the fleet manager allows more than 2 trips at once.

Everyone can be talked to. Lines come from real state, for example: chef "Served 41 lunches today, 3 left", or reception "2 visitors expected: ByteWorks at 14:00".

---

## 6. Calendar: one clock

| Thing | Unit | Where it is counted |
|---|---|---|
| Game day | 1200 s: 900 s for 08:00–18:00, 300 s for the night (unchanged, `EmployeeConfig.hour`) | – |
| Visible hour (sky, lights, who is at work) | server clock `workspace:GetServerTimeNow() % 1200`, one per server. It replaces the local `time = 54` in StaffService, so restarts keep the hour and all servers agree. | `StaffService`, `Lighting.ClockTime` |
| **Company date** (saved) | `empire.calendar = {day, index}`: +1 each time the visible clock passes 08:00 while the company is online | `CompanyOps.advanceCalendar` |
| Durations: trips, retainer terms, vacation | play seconds `empire.seconds`, which run at the same rate | `CompanyOps.step` |
| Billing month | 3 game days = `GAME_MONTH_SECONDS` 3600 s (unchanged). Subscription and API prices stay "per month". | `MarketMath.tick` |
| Payroll | rates per game day, accrued every second. The UI shows "payroll $x/day". | `EmpireService.tick` |
| Retainers | per game day, accrued every second. Term 6 days = 2 months. Pilot = 1 day. | `CompanyOps.step` |
| Hotel nights | city: 1 if a meeting starts at or after 13:00 (ends after 18:00); abroad: 2 per trip; counted per traveller | `CompanyOps.tripPlan` |
| Vacation | 1 day in 12 per person, by company date | vacation plan (5.3) |
| Studio briefs, old contracts | game day of play time (were real UTC days) | `StudioService.deliver` |
| Daily login reward | **real** UTC day: it is a login reward and stays real | `EmpireService.daily` |
| Market cycles | 300 s (a quarter of a game day), unchanged | `EmpireConfig.cycle` |
| Offline time | nothing runs offline (`lastSeen` stays unread); trips and terms pause. Consistent with today. | – |

The news log shows company date and visible hour together, for example "day 8 11:54: signed Ledger Finance: pilot $60,000, retainer $60,000/day". In the casual run the company was on day 19 after 360 minutes.

---

## 7. AI models: several live models that matter

**Product lines.** The focus (Balanced, Coding, Reasoning, Creative) is the product line.
- Live product slots per stage are 1 / 2 / 3 / 4 / 5 (`MarketConfig.PRODUCT_SLOTS`, checked in `AIModelService.releaseModel`, error `PRODUCT_SLOTS`).
- Every live model is offered in every segment. Customers pick the company's best model for their segment (the nest).
- So a coding model wins developers, a creative model wins consumers, and a reasoning or math model wins students and math clients.

**Anti-clone.** Nest λ = 0.05, shared reach and slots (table in 3.1). A copy is worth +4 %.

**Versions replace their predecessors.** `ReleaseModel {replaces = oldId}`:
- the successor copies `market.users` and `organic` and launches with them, so it never starts from zero;
- the old model becomes `retired` with `replacedBy`, and no users are wiped;
- studio projects and B2B accounts follow it.
- The bot uses this for every new version. Example: "release Nova4 … (replaces Nova3)".

**Ageing.** `−8 fit points × min(1, vage/3600)`, where `vage` is the time since the last version (release or refinement).
- An unchanged model loses up to 0.4 utility over 3 game days. That is about −25 to −33 % users at the same rank, never a collapse.
- In the 360-minute run the casual bot, once it had a 7B at the 99 cap, released a same-quality successor every 47–51 minutes (minutes 160, 212, 260, 307, 354). That is a steady R&D sink of about $2k/min.

**Refinement, fixed and capped** (`AIModelService.improveModel` / `finish`):
- gain per core stat `(1 + 4·dataQuality)·qualityMod / √(1 + iteration)`, additive (was proportional and compounding);
- at most **3 refinements** per model (`REFINE_LIMIT`);
- cost × (1 + 0.5·iteration);
- the model **stays live** while refining;
- each refinement resets `vage`;
- all stats ≤ 99 (`EmpireMath.boostStats`).
- Opt-bot example: Nova8 went 59.1 → 61.2 → 63.5 → … over three refinements costing $13.6k / $20.2k / $26.8k (`out_G2_opt.txt`).

**Parallel training.** `data.training` becomes `data.trainings[slot]`, migrated in DATA_VERSION 6 as `trainings[1] = training`.
- Slots = `min(stage cap {1,1,2,3,4}, 1 + ⌊O_engineering/8⌋)`.
- **One job per slot**: a new model or a refinement.
- GPU throughput is split equally across running jobs, so two jobs at once are not faster in total. The gain is that slow and quick projects can run side by side.
- About 30 readers of `data.training` need updating (models.md). This is **not simulated**: the bot trains one job at a time, and training jobs take 12–140 s, so the money curve is barely affected.

**Release forecast.** The release forecast must use the live rivals: fix `LabApp:942/722`, which still uses the static `NPC_MODELS`. It pre-selects the forecast-optimal price ("Recommended"). In the simulator, optimal pricing alone is worth ×1.12 at minute 180 and ×1.31 averaged over minutes 120–180 (`out_G4_optprice.txt` vs casual), so a good default narrows the gap between casual and skilled players.

**Model list cap.** The cap of 80 moves to `GameConfig` and counts only non-retired models.

---

## 8. Automation: the company runs itself

| Runs automatically | Player decides | How the assistant explains it (from real numbers) |
|---|---|---|
| **HR:** operations staffing per stage, vacation and sick cover, relief at posts, night crews when a department has night shift on | Build and buy: office, GPUs, cooling, data | "Moving to Startup Campus ($40,000) unlocks 3 products, 5 clients and the Guest House. At today's profit: about 6 minutes." |
| **Sales:** pick client, plan trip, book car, flight and hotel, renewals, trust | Hire and fire, or set a target headcount per role ("HR, hire to 6 engineers") | "Mia is driving to North Logistics (trust 76 %), back 09:00 tomorrow, hotel $200." |
| **Fleet:** lease and return cars per AE | Which model to train (size, focus, recipe), when to release, price and marketing (with "Recommended") | "Your Coding line is 41 minutes old (−7 fit). A successor would bring back about $3.1k/min." |
| **Finance:** payroll, retainers, bills, ledger categories | Research order | "Payroll is 36 % of income. Hiring more growth managers adds about $120/min each; a new account executive adds $0 (no free client slots)." |
| **Kitchen and guest house:** lunch service, room bookings | Night shift per department | "Data Ops has 59 curators for 32 desks. A night shift would move 27 of them from half to full output (+13.5 effective curators) for +30 % of their wage." |
| **Training events:** auto-resolved when Training Control is staffed (existing `autoResolve`) | Optional: pin or skip a client, join a client meeting in person | "ByteWorks will renew on day 8: check-in trip planned." |

**Safety rules**, all deterministic, so automation can never bankrupt the company:
- Sales only travel when cash ≥ trip cost + $500.
- HR never hires beyond the player's target.
- If cash < 0 for one game day, night crews and new trips pause.
- If cash < −2 days of payroll, the newest hires go on *unpaid leave*: their profiles are kept, they produce nothing and earn no wage, until cash > 1 day of payroll. This last rule is **not simulated**; in no run did cash go below 0 (see 9).

**Hook.** `AssistantService.briefing` gets new sections "Operations", "Customers" and "Models". `recommend` order puts these first: an aged model, a free client slot, the next office, seat overflow.

---

## 9. Targets check (simulator evidence)

**Bot profiles**
- **Casual = `--profile default`:** the game's launch defaults, sub $5 / API $2, marketing ≤ $5k.
- **Opt = `--profile opt --portfolio --refine 3`:** pricing search on the real market code, three product lines, 3 refinements per model.

Both bots:
- hire round-robin;
- hire account executives only up to ⌈client slots/3⌉ + 1;
- hire only while profit stays above 25 % of revenue;
- save for the next office once it is less than 8 minutes of profit away;
- train a successor when a new model beats the effective (aged) quality by ≥ 3.

### (a) Casual, fresh server (`out_G1_casual.txt`)

| min | money | revenue/min | cost/min | of which hired wages | B2B retainers/min (accounts) | staff | office stage | best model | live | NPC best |
|---:|---:|---:|---:|---:|---:|---:|---|---|---:|---:|
| 0 | 11,000 | 0 | 0 | 0 | 0 (0) | 0 | 1 Garage | - | 0 | 55.9 |
| 5 | 2,397 | 1,730 | 490 | 444 | 0 (0) | 4 | 1 Garage | s500m 47.6 | 1 | 61.5 |
| 10 | 4,698 | 2,481 | 501 | 444 | 0 (0) | 4 | 1 Garage | s500m 47.6 | 1 | 61.8 |
| 20 | 6,681 | 4,787 | 2,435 | 2,101 | 825 (2) | 19 | 2 Founder HQ | s500m 49.8 | 1 | 61.8 |
| 30 | 8,866 | 7,727 | 3,881 | 2,968 | 1,725 (3) | 27 | 3 Startup Campus | s500m 55.2 | 1 | 61.8 |
| 45 | 19,946 | 11,283 | 7,507 | 6,477 | 2,775 (4) | 60 | 3 Startup Campus | s1b 57.2 | 1 | 61.8 |
| 60 | 38,214 | 18,703 | 8,031 | 6,900 | 4,275 (5) | 64 | 3 Startup Campus | s1b 68.2 | 1 | 61.8 |
| 90 | 238,739 | 26,003 | 8,139 | 6,900 | 4,275 (5) | 64 | 3 Startup Campus | s1b 75.4 | 1 | 61.8 |
| 120 | 337,359 | 46,379 | 17,978 | 13,694 | 6,075 (6) | 128 | 4 Innovation | s7b 94.3 | 1 | 61.8 |
| 180 | 448,359 | 62,226 | 31,902 | 25,566 | 16,125 (10) | 240 | 5 Global HQ | s7b 99.0 | 1 | 61.8 |

Later minutes: min 240: $65,003/min, min 300: $69,144/min, min 360: $77,485/min. Offices reached at minute 13.4 / 24.4 / 96.5 / 165.4.

### (b) Opt profile, fresh server (`out_G2_opt.txt`)

| min | money | revenue/min | cost/min | of which hired wages | B2B retainers/min (accounts) | staff | office stage | best model | live | NPC best |
|---:|---:|---:|---:|---:|---:|---:|---|---|---:|---:|
| 0 | 11,000 | 0 | 0 | 0 | 0 (0) | 0 | 1 Garage | - | 0 | 55.9 |
| 5 | 3,291 | 2,155 | 838 | 566 | 0 (0) | 5 | 2 Founder HQ | s500m 47.0 | 2 | 61.5 |
| 10 | 4,979 | 3,676 | 1,716 | 1,433 | 0 (0) | 13 | 2 Founder HQ | s500m 47.0 | 2 | 61.8 |
| 20 | 8,340 | 5,992 | 2,718 | 2,402 | 675 (1) | 22 | 2 Founder HQ | s500m 50.3 | 2 | 61.8 |
| 30 | 42,216 | 9,286 | 2,959 | 2,601 | 675 (1) | 24 | 2 Founder HQ | s1b 61.2 | 2 | 61.8 |
| 45 | 21,649 | 26,167 | 7,911 | 6,900 | 3,900 (5) | 64 | 3 Startup Campus | s1b 67.2 | 3 | 61.8 |
| 60 | 32,507 | 35,647 | 8,227 | 6,900 | 3,900 (5) | 64 | 3 Startup Campus | s1b 75.6 | 3 | 61.8 |
| 90 | 859,609 | 116,493 | 17,224 | 13,694 | 7,950 (7) | 128 | 4 Innovation | s7b 96.1 | 3 | 61.8 |
| 120 | 1,233,519 | 76,653 | 30,481 | 25,566 | 12,000 (9) | 240 | 5 Global HQ | s7b 96.1 | 3 | 61.8 |
| 180 | 5,260,318 | 70,680 | 30,433 | 25,566 | 21,750 (11) | 240 | 5 Global HQ | s7b 99.0 | 3 | 61.8 |

Later minutes: min 240: $77,111/min, min 300: $72,929/min, min 360: $83,667/min. Offices reached at minute 2.7 / 33.2 / 67.7 / 99.7.

### (c) Casual, joining a server that is already 60 minutes old (`out_G3_late60.txt`)

| min | money | revenue/min | cost/min | of which hired wages | B2B retainers/min (accounts) | staff | office stage | best model | live | NPC best |
|---:|---:|---:|---:|---:|---:|---:|---|---|---:|---:|
| 0 | 11,000 | 0 | 0 | 0 | 0 (0) | 0 | 1 Garage | - | 0 | 61.8 |
| 5 | 2,277 | 1,679 | 490 | 444 | 0 (0) | 4 | 1 Garage | s500m 47.6 | 1 | 61.8 |
| 10 | 4,442 | 2,475 | 501 | 444 | 0 (0) | 4 | 1 Garage | s500m 47.6 | 1 | 61.8 |
| 20 | 6,474 | 4,785 | 2,435 | 2,101 | 825 (2) | 19 | 2 Founder HQ | s500m 49.8 | 1 | 61.8 |
| 30 | 8,634 | 7,718 | 3,881 | 2,968 | 1,725 (3) | 27 | 3 Startup Campus | s500m 55.2 | 1 | 61.8 |
| 45 | 19,472 | 11,205 | 7,501 | 6,477 | 2,775 (4) | 60 | 3 Startup Campus | s1b 57.2 | 1 | 61.8 |
| 60 | 34,855 | 18,269 | 8,018 | 6,900 | 4,275 (5) | 64 | 3 Startup Campus | s1b 68.3 | 1 | 61.8 |
| 90 | 229,698 | 25,966 | 8,134 | 6,900 | 4,275 (5) | 64 | 3 Startup Campus | s1b 75.4 | 1 | 61.8 |
| 120 | 322,851 | 46,327 | 17,976 | 13,694 | 6,075 (6) | 128 | 4 Innovation | s7b 94.3 | 1 | 61.8 |
| 180 | 436,800 | 62,261 | 31,905 | 25,566 | 16,125 (10) | 240 | 5 Global HQ | s7b 99.0 | 1 | 61.8 |

Offices reached at minute 13.4 / 24.4 / 97 / 165.8. Server 180 minutes old (`out_G7_late180.txt`): offices at 13.4 / 39.4 / 85 / 145.6, $59,901/min at minute 180. Opt profile at server age 60 (`out_G9_optlate60.txt`): offices at 13.4 / 28.2 / 63.4 / 98.6, $93,995/min at minute 180.

### Robustness and stress runs

| Run | Result |
|---|---|
| Today's game, casual (`out_G8_baseline.txt`) | 8,678 → 93 → 1 $/min at minutes 5 / 45 / 180, cash −42,564: **collapse** (reproduces economy.md) |
| Today's game, opt pricing (`out_G11_baseline_opt.txt`) | 9,389 → 209 → 1 $/min, cash −52,775: **collapse** |
| This design, nobody hired (`out_G5_nohire.txt`) | 1,582 → 6,775 → 17,082 $/min at minutes 5 / 60 / 180; offices 2.2 / 45.6 / 141.1; lowest cash $303 (minute 8): staff matter (about ×3.6 at minute 180) and there is no collapse without them |
| This design, hire to cap whenever cash allows (`out_G6_overhire.txt`) | 1,730 → 18,283 → 61,399 $/min at minutes 5 / 60 / 180; offices 13.4 / 28.9 / 93.2 / 159.8; lowest cash $334 (minute 4.3): over-hiring does not bankrupt |
| Casual + 3 product lines + refinement (`out_G10_casualpf.txt`) | 1,615 → 16,612 → 53,915 $/min at minutes 5 / 60 / 180; offices 13.4 / 49.5 / 102.5 / 164.9; lowest cash $119 (minute 10.8). That is −13 % at minute 180 but +10 % on average over minutes 120–180 against one product line: a portfolio is a choice, not an exploit. |
| Opt pricing, one product line (`out_G4_optprice.txt`) | 1,835 → 25,873 → 69,971 $/min at minutes 5 / 60 / 180; offices 2.5 / 34.7 / 72.5 / 117.2; lowest cash $2,262 (minute 4) |
| Clone stacking (`out_clonetest.txt`) | 2 / 5 / 10 clones = ×1.04 / ×1.11 / ×1.15 (today ×1.94 / ×4.44 / ×7.88) |

### Targets against results

| Brief target | Result (casual unless stated) | Met? |
|---|---|---|
| A clear first goal; ≥ $1–3k/min by minute 5–10 | First $ at minute 1.5; $1,730/min at minute 5; $2,481/min at minute 10; goal "Move out of the garage", reached at 13.4 | yes |
| Office 2 (Startup Campus = stage 3) at 25–40 min | 24.4 (late joiner 24.4, server 180 min old 39.4) | yes, at the early edge (24.4 is 0.6 min before the window) |
| Office 3 (Innovation = stage 4) at 70–100 min | 96.5 (late 97, 180-min server 85) | yes |
| Office 4 (Global HQ = stage 5) at 2.5–3.5 h | 165.4 (late 165.8, 180-min server 145.6) | yes (the 180-min server is slightly early, at 2.4 h) |
| No collapse | No run below $1.4k/min from minute 5 on; lowest cash in any run: $119 (G10_casualpf, minute 10.8) | yes |
| No runaway (bounded, grows with the company) | Casual plateaus at 65,003 / 69,144 / 77,485 (min 240 / 300 / 360). Opt at minute 360 $83,667/min. Hard ceilings: reach cap × pool, 12 clients ($29k/min) | yes |
| Wages 25–45 % of revenue in the mid game | 42 % (minutes 45–60), 29 % (120–180); opt 21 % / 25 % | yes for casual; the opt bot runs leaner (21–25 %) |
| Late joiner OK | Same curve within ±13 % at every sampled minute (server age 60 and 180); offices within ±20 minutes; the NPC level is identical (61.8) | yes |
| Several live models meaningful, no clone stacking | Clones ×1.04–1.15; specialists ×1.29 in the market, plus different B2B clients | yes |
| Watched = unwatched | By construction (5.1): money reads only saved data and the clock | yes (design) |

---

## 10. Risks, and what to cut first

### Risks

1. **Bot ≠ player.** The bots react every second and play perfectly greedy. A real casual player will be slower: the offices probably come 10–30 % later. All prices are single knobs in `patches_robust.luau` → `EmpireConfig.OFFICES`, so they can be tuned after a play-test.
2. **Casual vs skilled gap.** At the plateau, opt earns only ×1.05–1.19 of casual income (minutes 180–360). In the mid game the gap is large: ×1.9 at minute 60 and ×4.5 at minute 90, where opt peaks briefly at $116k/min after three fresh 7B launches with $100k of marketing. Opt gets to the top office 66 minutes earlier. The "Recommended price" default (7) closes most of the pricing part. If the gap still feels too big, lower `API_PRICE.max` from 20 to 8.
3. **Market with no player competition** (`PLAYER_RIVAL_WEIGHT = 0`). This is fairer and more robust, but players no longer "fight" over users. If the owner wants that back, raise the weight to 0.2–0.3 and re-check late joiners, because a dominant player would then lower everyone's share.
4. **Stage-5 data desks.** Curator desks stay at 32 from T2 to T4. Under a balanced hiring mix the overflow rule cuts tokens by about 23 % at stage 5. Not a money risk, but the building should get more data desks, or the assistant should advise fewer curators or a night shift.
5. **Unsimulated pieces:**
   - parallel training slots;
   - night shift;
   - the unpaid-leave safety;
   - morale and room-quality multipliers (simulated as 1.0, which is conservative);
   - founder-joined meetings;
   - all visuals (cars, guests, lunch walks).
   None of them can raise income by more than about 15 %, because each is a bounded multiplier.
6. **Migration.** DATA_VERSION 6 plus the training → trainings change: a server still on the old code kicks players whose save already has version 6 (data_ui.md pitfall 5). Ship server code before the first v6 save, as with every version bump.
7. **Bandwidth.** `empire.deals.news` (≤ 40 strings) and `calendar` must be sent lazily (`REPLICATE_LAZY_SECONDS`), never 2× per second.
8. **Garage art.** The garage generator plus the fenced site are new geometry. It must not break `PlotService` rebuilds, the car spawn or the visitor bays.

### Cut first if time runs out, in this order

| Order | Cut | Fallback |
|---|---|---|
| 1 | Parallel training slots | Keep one training at a time (the money curve barely changes) |
| 2 | Night shift | Overflow people count 0.5 |
| 3 | Guest-house paying guests | Keep the building as a client workshop venue only |
| 4 | Morale and room quality | Fixed at 1.0, which is what the simulator assumed |
| 5 | Abroad trips | Treat all clients as city trips; keep the airport visual |

**Never cut**, because they hold the economy together:
- the NPC band;
- `STAGE_REACH`;
- the company nest and product slots;
- additive and capped refinement;
- EV-based staff output;
- flat hiring fees;
- the B2B catalogue ceiling.

---

## Appendix A: every tuning knob

| Knob (file) | Value | Effect |
|---|---|---|
| `OFFICES.price` (EmpireConfig) | 0 / 12k / 40k / 300k / 1.8M | office timing |
| `OFFICES.staff` | 4 / 24 / 64 / 128 / 240 | staff cap per stage |
| `STAGE_REACH` (MarketConfig) | 0.14 / 0.20 / 0.35 / 0.55 / 0.75 | market ceiling per stage (main anti-runaway) |
| `POOL_SCALE` | 0.2 (and `REPUTATION.userScale` 4e5) | market size |
| `FIT_SCALE` | 20 | how much quality beats rivals |
| fit soft cap | above 75 counts ×0.35 | anti stat inflation |
| `NEST_LAMBDA` | 0.05 | value of a copy (+4 %) |
| `AGE` | 8 fit points over 3600 s | treadmill strength |
| `PRODUCT_SLOTS` | 1–5 | live products per stage |
| NPC band (NPCService) | ×1.2 at start, cap 64 per stat, API floor $1 | the competition level |
| wages (ROLES) | $1,530–2,856 per game day | wage share |
| fees (ROLES.price) | $800–1,400 flat | hiring cost |
| `AVAILABILITY` (CompanyOps) | 0.90 | vacation and sick |
| marketing curve | 1 + 0.6·(1 − e^{−O/10}) | growth managers' value |
| `B2B_SCALE` (CompanyOps) | 1.5 | B2B share |
| trust formula | 0.5 + 0.025·margin + 0.05·(skill − 3) + 0.1·guest | visits per deal |
| `STAGES.upkeep` | $200 … $60k per day | fixed cost per building |
| `studioScale` | 0.2 | studio share |
| `START_MONEY` | 10,000 | garage length |

## Appendix B: simulator notes

**How the patches load.** `sim.luau --robust` loads `patches_robust.luau`, which adds `CompanyOps` as a new ModuleScript and applies find/replace and range patches to the real sources. Every `assert` must find its anchor, so a patch can never silently miss.

**Simulated:**
- market (new tick), NPC band, nest, ageing, reach caps, product slots and successor releases;
- wages and fees, operations, upkeep, food and fleet;
- B2B pipeline with trips, hotel nights, trust, renewals and capacity;
- studio per game day;
- duty-curve accrual;
- refinement fix;
- stage-based slots and thermal;
- the garage stage and start money.

**Modelled as injected flows:** guest-house income and costs, trips (money only).

**Not simulated:** visuals, parallel training, night shift, morale/Q variation, unpaid leave, player-joined meetings, Robux.

**Simulator changes in my copy:**
- 5-role hiring;
- the profit-margin hiring rule;
- saving for the next office;
- ageing-aware successor releases;
- `--portfolio`, `--clonetest`, `--overhire`, `--set`;
- ledger categories;
- windowed share report;
- a debug note when a studio build fails.

The bot logic is otherwise the logic_understand bot.
