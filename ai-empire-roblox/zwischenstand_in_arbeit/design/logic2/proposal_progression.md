# AI Empire: Progression & Goals proposal (logic2)

Date: 2026-10-17. Author: logic2 progression agent. Status: **design proposal**, read-only on the game. Nothing under
`work/`, `tests/`, `agents/stable/` or the existing `design/*` files was changed. Input for LOGIC2_SPEC.

**Lens.** Pacing curve, time to the next goal, dead zones, short / mid / long goals, milestones and celebrations, a
late-game loop so the game does not end, and how Port Meridian, the airports and the Meridian Grand become
progression rewards.

**Labels.**
- **[M]** = measured. A `file:line` or a command with its output is given.
- **[P]** = a proposed number or rule. It is a design value, not a fact about the game.
- **[A]** = an assumption, stated as one.
- **[U]** = unsure.

**Sources and paths.** Paths are relative to `scratchpad/`
(`/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad`).
- `src/<path>:<line>` = live `work/src`, read 2026-10-17 10:50–11:24 UTC.
- My simulator snapshot is `design/logic2/sim_progression/src_snap` (copy of `work/src` at 09:46:18 UTC).
  `cmp` against live `work/src` at 11:24 UTC shows every economy file I cite is byte-identical: EmpireConfig,
  EmpireMath, CompanyOps, MarketConfig, MarketMath, MarketService, PricingMath, EmpireService, TutorialMath, GoalText,
  HUD, Template, LeaderboardService, CompanyConfig, FlightPlan, CityPlan, EmpireApp and GuideController.
- Only ItineraryMath, ItineraryService and BuildingStateService differ, because the round-2b itinerary fix is running.
  Their line numbers below are the live ones.
- Simulator, scripts and outputs are in `design/logic2/sim_progression/` (Appendix B).

---------------------------------------------------------------------------------------------------------------------

## 0. Summary

### 0.1 The 8 changes, ranked

| # | Change | Fixes (audit weakness) | Sim | Effort | Risk |
|---|---|---|---|---|---|
| 1 | **P1 Meridian Branch**: a Port Meridian office bought at Innovation Campus for $300k [P]. Market pool ×1.25 and +2 client slots [P]. | #5 late-game wall, #4 world without purpose | yes | M | low–med |
| 2 | **P3 World Expansion**: endless expansion levels after Global AI HQ, plus a "Global reach" leaderboard. | #2 content ends, #10 leaderboard tie at 99 | yes | M | med |
| 3 | **P2 Be there**: if the founder is in the meeting room, the client signs in that meeting. | #4 world without purpose, #7 clients, dead zone "First region client" | yes | S–M | low–med |
| 4 | **P4 Goal card with three lines (Now / Next / Chapter)** and an honest ETA (net × 0.75 [P], shown as a range). | #8 misleading numbers, dead zones | offline | M | low |
| 5 | **P5 Milestone ladder and celebration tiers**: ~60 milestones, no cash reward, a "Grand Opening" scene on every move. | #1/#2 (nothing to look forward to) | offline | M | low |
| 6 | **P6 Save mode "Ready to move"**: HR is no longer frozen once the money is there; one-tap move call; honest text. | #6 automation traps idle players | no (audit data) | S | low |
| 7 | **P7 World reward calendar**: what each stage opens in the world, and what that place does (the Meridian Grand as the base abroad, airport status by stage). | #4 world without purpose | no | M | med (order of packages) |
| 8 | **P8 Generations**: a soft reset of the model layer only (stat cap +5 per generation). There is no building reset. | #2 model design stops at 99, #10 | no | L | high |

### 0.2 Simulator results (non-payer, seed 4242, start 16:53)

Profiles: *human* = acts every 30 s, *gpucap* = the same but buys GPUs only when servers are full,
*semi* = checks in every 5 min, buys GPUs only when servers are full. Tables are in §4.

| | Global AI HQ (min) human / gpucap / semi | Longest single goal (min) | "Every goal reached" | Revenue $/min at 300 (human) |
|---|---|---|---|---|
| Today (`F_base_*`) | 174.5 / 167.0 / 175.0 | 83 / 85 / 85 (Global HQ) | at min 210 / 193 / 200 | 116,436 |
| P1 Branch $300k (`F_p1_*`) | **166.0 / 159.5 / 165.0** | **42 / 43 / 55** | 199 / 176 / 185 | 142,988 |
| P1 + P3 (`F_p13_*`) | 166.0 / 159.5 / 165.0 | 42 / 56 / 55 | **never** (5 / 6 / 6 levels by 360) | 168,827 |
| P2 Be there (`F_p2_*`, travel blocks play) | 170.0 / 157.5 / – | 87 / 67 / – | 209 / 205 / – | 118,798 |
| P1 + P2 + P3 (`F_all_*`) | **155.0 / 147.5** / – | 69 / 82 (the jet goal during a B2B capacity crash, §3 P1 risk) | never | 168,781 |

Today's "join the meeting" (+0.15 trust) makes an active player **11.5 min slower** to Global HQ (186.0 vs 174.5,
`F_p2j_human`). With the P2 rule the same trips make him 4.5 min faster, and his first region client signs 17 min
earlier (min 50 vs 67).

### 0.3 One correction to the audit I relied on

The audit says the HUD ETA is "2.5–3× too optimistic" (AUDIT.md §3.3). That compares the *median ETA shown* with the
*whole length of the goal*. Measured per minute, the ETA is 0.70 / 0.76 / 0.62 of the real minutes left (median,
F_base runs; §4.6). So it is typically **1.3–1.6× too optimistic**. Only in the worst 10 % of minutes is it 1.8–2.6×
(p10 0.38–0.55 for office4 / office5, `out/eta_explore.md`). The fix is the same (P4), but the size is smaller.

---------------------------------------------------------------------------------------------------------------------

## 1. What I re-checked before relying on the audit

| Audit claim | My check | Result |
|---|---|---|
| The audit sim = shipped code | Re-ran its 3 human profiles on my 09:46 snapshot (`run_base.sh` → `out/b_*`, and `run_final.sh` → `out/F_base_*`) | identical: STAGES 12.5/38.5/92.0/174.5, 10.0/31.5/81.5/167.0, 10.0/50.0/90.0/175.0 [M] |
| Longest wait is Innovation → Global HQ, 83–86 min | `analyze_prog.py` goal timeline | office5 83 / 85 / 85 min [M] |
| Stage 4 has few decisions | same, decisions per 10 min | stage 4: 7.4 / 5.3 / 4.8; stage 5 up to 360 min: 4.3 / 2.6 / 2.7; longest gap 13.5–30.5 min [M] |
| "Every goal reached" ends the goals | goal timeline, `src/StarterPlayer/StarterPlayerScripts/Client/UI/GoalText.module.luau:147-151` | "done" at 210 / 193 / 200 min [M] |
| HUD ETA 2.5–3× optimistic | per-minute ratio (`eta_explore.py`) | **1.3–1.6× typical**, see 0.3 [M] |
| Port Meridian part budget | `tools/luau tests/metro/test_build.luau -a ../design/logic2/sim_progression/gen` | `Port Meridian: 5253 parts (+4472 over the pre-metro city)`, budget 4,500 → **28 parts left**; `metro_build: 42 passed, 0 failed` [M] |
| Celebrations are thin | `grep` of the client | The only burst is the step-5 "First income!" (`src/.../UI/Screens/HUD.module.luau:194-199,878-905`), called once by the guide (`src/.../Controllers/GuideController.module.luau:539-541`). An office move is a 5-s toast (`src/ServerScriptService/Server/Services/EmpireService.module.luau:113`, `src/.../UI/Apps/EmpireApp.module.luau:1864-1870`) [M] |
| Ranks stop early | `src/ReplicatedStorage/Shared/Config/CompanyConfig.module.luau:90-96` | Scale-Up = 100k peak users (reached ~min 45, F_base_human row 45: 101,344 users). Unicorn = 1M. Today no run passes 266k peak users by 360 min (with P1 + P3: 452k–489k; 536k at 600 min), so ranks stop at ~min 45 [M] |

---------------------------------------------------------------------------------------------------------------------

## 2. The pacing curve: today vs target

**Today [M]** (F_base_human; gpucap and semi are similar, §4):
- Stage lengths: 12.5 / 26 / 53.5 / 82.5 min.
- Stage 5 runs to the end, and the goals end at min 210.
- Longest stretch without any "progress beat" per hour of play: 10 / 19 / 48 / 25 / 55 / 60 min. A beat is an
  office move, a research or Lab level, a quest, a new product line, a signed client or the jet.

**Target curve [P]** (an active player; the semi player may be ~1.2× slower):

| Horizon | Rule | Today | With P1–P5 (sim) |
|---|---|---|---|
| Short goal ("Now") | something to do or watch at least every **5 min** | decision gaps up to 13.5–30.5 min in stages 4–5 | stage 4 gaps 11–16.5 min (still above target, see P8) |
| Mid goal ("Next") | no single goal longer than **~45 min** | 83–85 min | 42–55 min (P1), 42–56 (P1+P3) |
| Long goal ("Chapter") | a chapter end every **30–75 min**, then endless levels | 4 office moves, then nothing | 4 moves + branch + expansion levels every 15–56 min |
| Beats | no hour with a gap > **~25 min** in the first 4 h | 48 min (h3) | 18–19 min (h3, P1 + ladder) |
| End | never "Every goal reached" | min 193–210 | never (P3) |

---------------------------------------------------------------------------------------------------------------------

## 3. The changes

### P1 · Meridian Branch: the Port Meridian office as the stage-4 reward

**Problem [M].**
- Innovation Campus → Global AI HQ is the longest wait: 83 / 85 / 85 min (§4.2).
- It is also the emptiest stretch: 7.4 / 5.3 / 4.8 decisions per 10 min, with gaps up to 18.5 min (§4.3).
- Revenue stalls inside stage 4. In F_base_human it is $80,597/min at 120 and $73,671/min at 180. Staff reaches the
  128 cap at ~min 120 (row 120: `128 R38 E43 C25 G22`). The stage reach cap is 0.40
  (`src/ReplicatedStorage/Shared/Config/MarketConfig.module.luau:171`), and the servers are only 21–43 % used
  (rows 120 / 180, "cap use"). So more GPUs or staff cannot help: the market is full.
- Port Meridian has no economic role: "the economy is the same either way"
  (`src/ServerScriptService/Server/Services/ItineraryService.module.luau:7`).
- CORE_SPEC already lists a branch office, but only as a spec idea: "stage 5, $3,000,000 … +2 client slots …
  None raises income materially" (`design/CORE_SPEC.md:976-980`).

**Change [P].**
- New purchase **Meridian Branch** = *World Expansion level 1*, available from Innovation Campus (stage ≥ 4).
- Price **$300,000** [P].
- Effects:
  - **International market**: the company's market pools × **1.25** [P], applied as `opts.poolMult` in the market
    tick. It scales only this company's target users, not other players.
  - **+2 B2B client slots** [P] in `accountLimit`, `fieldReps` and `hrNeed`. HR hires the extra field rep.
  - No running cost [P]. This keeps the simulation exact; an upkeep is an open knob, see §6.
- Goal order (`EmpireMath.nextGoal`): … Innovation Campus → Frontier research → **Meridian Branch $300K** →
  Global AI HQ.
- **In the world** (the reward you can see): the branch is a floor band of an existing Port Meridian tower lit in
  the company colour, plus the company name on an existing lobby screen.
  - This uses only attributes, `SurfaceGui` text and CityLife night-glow colour, with **0 new parts**, because only 28
    parts of the budget are left (§1).
  - The founder's first visit to the branch plays a T3 celebration (P5). The visit is optional and changes no money.
- Why $300k: sim variants show the price decides whether the branch helps or hurts the semi player.

| Branch variant (`--branch PRICE/POOL/SLOTS`) | Global HQ human / gpucap / semi | Branch bought at |
|---|---|---|
| none (today) | 174.5 / 167.0 / 175.0 | – |
| $300k / +25 % / +2 (proposed) | 166.0 / 159.5 / 165.0 | 123.5 / 116.5 / 110.0 |
| $400k / +25 % / +2 | 169.5 / 162.0 / – | 125.5 / 118.5 |
| $450k / +20 % / +2 (batch 1) | 172.5 / 166.0 / – | 126.0 / 119.5 |
| $600k / +25 % / +2 (batch 1) | 175.0 / 166.0 / **180.0 (5 min slower)** | 138.0 / 130.0 / 145.0 |

**Touches.**
- `CompanyOps`: `Ops.EXPANSION`, `expansionLevel`, `expansionPrice`, `poolMult`, `expansionSlots`, `buyExpansion`.
  Also `accountLimit` (`src/ReplicatedStorage/Shared/CompanyOps.module.luau:764-766`), `fieldReps` (:225-229) and
  `hrNeed` (:490-501).
- `MarketMath.tick`: the pool scale at `src/ReplicatedStorage/Shared/MarketMath.module.luau:132` gets the factor.
- `MarketService.tick` passes it (`src/ServerScriptService/Server/Services/MarketService.module.luau:150-151`).
- `PricingMath.context` passes the same opts (`src/ReplicatedStorage/Shared/PricingMath.module.luau:169-177`
  promises "exactly the opts MarketService.tick passes").
- `EmpireService.empireAction`: action `"expand"`, next to `buyJet` at `EmpireService.module.luau:501`.
- `EmpireMath.nextGoal` (:195-232), `GoalText`, EmpireApp Office tab button, AssistantService briefing line.
- MetroBuilder / CityLife: floor-glow attribute.
- All of this is exactly what `sim.luau` patches in memory (header of `run_final.sh`).

**Save.**
- `empire.expansion = { level = 0 }` in `EmpireMath.new` (:15-27).
- Cleaner in `Template.cleanCompany`: `level = clamp(floor(level), 0, 99)`, else 0. This is the same pattern as
  `prefs` (`src/ServerScriptService/Server/Lib/Template.module.luau:378-381`).
- No DATA_VERSION change. Old saves start at level 0.

**Test.**
- Sim: `run_final.sh` rows `F_p1_*` and `F_p1x_*` (§4).
- New mock suite `tests/expansion` [P]:
  - gates `OFFICE`, `NO_MONEY` and `MAX_LEVEL`;
  - the price table;
  - `accountLimit` +2;
  - `poolMult` reaches both `MarketService.tick` opts and `PricingMath.context` (equal);
  - the cleaner on bad types / NaN / negative values;
  - an old save migrates to level 0.
- `tests/metro/test_build.luau` part budget unchanged (+0 parts).
- `tests/econ` net budget for the replicated `expansion` field.

**Effort / risk.** M.
- Income rises after the branch: +44 % at min 180 and +23 % at min 300 (human) [M]. That is the purpose, but it
  makes late cash grow (P3 is the sink).
- **Watch-out [M]**: the +2 slots reserve compute. In 1 of 18 runs (`F_all_gpucap`, min 160–186) the B2B reserve
  left no serving capacity: cap use 732 %, users fell from 255,988 to 34,166.
  - The bot made this worse: its GPU rule returns early when capacity is 0 (`sim.luau` `capacityUpgrade`,
    `if not Ops or cap <= 0 ...`). A kid sees "servers full".
  - B2B signing checks `tokenCap` = all compute (`CompanyOps.module.luau:768-771,873,903`), not the compute left for
    users. Proposal: cap B2B reservations at 60 % of compute [P]; not simulated.

---

### P3 · World Expansion: the late-game loop that does not end

**Problem [M].**
- "Every goal reached" comes at min 210 / 193 / 200 (F_base). After that the card says "Keep shipping new
  versions…" (`GoalText.module.luau:148-149`).
- After Global HQ there are 0.8 / 0.6 / 0.7 beats per 30 min.
- Cash piles up with nothing to buy: $10.7M / $11.9M / $11.7M at min 360 (F_base rows 360).
- Leaderboards tie: `overall` = `bestOverall` (`src/ServerScriptService/Server/Services/LeaderboardService.module.luau:8,15`),
  and every core stat is capped at 99 (`src/ReplicatedStorage/Shared/EmpireMath.module.luau:159`).

**Change [P].**
- World Expansion levels 2, 3, … from Global AI HQ.
- Price of the next level, for L ≥ 1: **$1.5M × 1.5^(L−1)** [P]. Level 2 costs $1.5M, level 3 $2.25M, level 4
  $3.375M, level 5 $5.06M, level 6 $7.59M, level 7 $11.4M.
- Each level adds **+10 % market pool** [P]. Pool factor = 1.25 + 0.10 × (L−1).
- No cap (sim max 30).
- Income per level grows linearly while price grows geometrically. So levels slow down: the measured gaps are
  15–20 → 22–30 → 25–31 → 41–45 → 56 min.
- **Naming and world.** Level 1 is the Meridian Branch. Each further level lights one more floor of the Port
  Meridian tower and adds one more pin on the phone's world map ("Port Meridian Business District", "Harbour
  Exchange", … [P], names only).
  - No new places, so no part budget. Kids still see the skyline turn their colour.
- **Goal card**: after the jet, the last goal is always "World expansion level N $X". It is never "Every goal
  reached".
- **Leaderboard**: a new mode `reach` = expansion level × 1,000,000 + peak users [P]. This breaks the 99 tie and
  uses the same OrderedDataStore path (`LeaderboardService.module.luau:36-41`; `OrderedDataStore:SetAsync` /
  `GetSortedAsync` checked in the API dump, Appendix A).

**Touches.** Same modules as P1 (one system), plus `LeaderboardService` (mode list `:8`, `values` `:14-22`).

**Save.** The same `empire.expansion.level`. Nothing else.

**Test.**
- Sim rows `F_p13_*` (§4.1) and the 600-min check `L_p13_human` (§4.7).
- Mock:
  - price(L) for L = 0..10;
  - level gates by stage;
  - leaderboard value function, tie-break;
  - cleaner clamp.

**Effort / risk.** M.
- Revenue at 360 is $177k–198k vs $120k–125k today (+47–58 %) [M]. Cash at 360 drops to $0.9M–7.0M.
- The growth is bounded: linear in level, and levels come slower and slower. §4.7 checks a 10-h horizon.
- Other players weigh only 0.15 in the market (`MarketConfig.module.luau:174`), so a high-level veteran changes a
  newcomer's share very little (CORE_SPEC 9.7 measured ≤ 5–10 % for today's veterans).
- **Honest limit [M]**: P3 is a *goal* loop, not a *decision* loop. Stage-5 decisions per 10 min stay 4.4 / 2.8 / 3.1
  (vs 4.3 / 2.6 / 2.7 today). Decisions need P8 or other lenses.

---

### P2 · Be there: the founder in the meeting closes the deal

**Problem [M].**
- "First region client" sits on the card for 28 / 20 / 20 min with nothing to do (F_base 39→67, 32→52, 50→70). The
  hint is "Reps keep visiting" (`GoalText.module.luau:262-276`).
- A region pilot is a 1-game-day trip (20 real min). Abroad is 2 days (40 min)
  (`CompanyOps.module.luau:109-113`, `Ops.DAY = 1200` at :30).
- Trust per visit is `0.5 + 0.025 (best − minimum) + …` (:749-757), so two visits are common.
- Joining the meeting in person adds only +0.15 (:43, :755). That is the only economic effect of the whole
  itinerary, airport and hotel (`ItineraryService.module.luau:7,24`).
- **Measured**: with today's rule an active player who joins every region / abroad / hosted meeting reaches Global
  HQ **11.5 min later** (186.0 vs 174.5, `F_p2j_human`, 8 meetings, 56 min travelling).
  - **Assumption [A]**: the sim player makes no decisions while he travels.
  - The HUD Menu button opens from anywhere (`HUD.module.luau:534`), so a real kid could manage on the way. The
    optimistic variant is below.

**Change [P].**
- When the founder joins a running pilot meeting (the existing `EmpireService.joinMeeting`,
  `EmpireService.module.luau:563-577`, reached by the CityService "Start meeting" prompt and the itinerary's meeting
  step), **the client signs in that meeting**:
  - the account starts now and the pilot fee is paid now, the same booking as `CompanyOps.step` :846-855;
  - but only if the best live model meets the client's minimum (`Ops.eligible`, :758-762) and a client slot is free.
- Otherwise today's +0.15 trust applies, so the existing tests stay valid
  (`tests/itinerary/test_service.luau:257-265` "meeting adds exactly 0.15 trust").
- The field rep still comes home on the CORE_SPEC clock. The economy trip is never shortened, and the itinerary
  itself still books no money: the close happens in EmpireService.
- **Hosted pilots**: a "Meet the guests" prompt in the guest-house lounge at HQ does the same [P]. It is a 1-minute
  walk.
- **Card / assistant texts**: "Atlas Search meets your rep in Business City now. Be there and sign today (about
  3 min drive)."

**Touches.**
- `CompanyOps`: `Ops.closeAtMeeting`, which reuses the signing block.
- `EmpireService.joinMeeting`, plus its result text in the meeting handler registered in `EmpireService.init` (:631-650).
- The itinerary meeting step: banner text only (`ItineraryMath` texts).
- A guest-house prompt (BuildingPlan / FacilityService, [U] which file owns the lounge prompts).
- `GoalText` region / client hints; AssistantService call text.

**Save.** None. Accounts, trust and `trip.joined` are already saved (`Template.module.luau:341`).

**Test.**
- Sim rows `F_p2_*`, `F_p2tp_human`, `F_p2j_human`.
- Mock:
  - join → account created when eligible and a slot is free;
  - not eligible → +0.15 only;
  - slots full → +0.15 only;
  - the trip returns after a close → no double signing and no trust left;
  - the hosted prompt;
  - range check `TOO_FAR` (`EmpireService.module.luau:578,597-609`) unchanged;
  - `tests/itinerary` texts updated ("signed in the meeting").

**Effort / risk.** S–M.
- **Measured effect (pessimistic travel)**:
  - first region client at min 50 / 35 instead of 67 / 52;
  - Global HQ 170.0 / 157.5 instead of 174.5 / 167.0;
  - 9–10 meetings, all closed;
  - 62–64 min travelling in 300 min.
- **Optimistic travel** (`--travelplay`): Global HQ 172.5.
- Risks:
  - The travel times are assumptions [A]: region 3 + 3 min, abroad 10 + 8 min, hosted 1 + 1 min. They come from the
    itinerary plan estimates (`src/ReplicatedStorage/Shared/ItineraryMath.module.luau:34-40`: MEETING_TALK 20 s,
    WALK_GATE 40 s, LIMO_SECS 50 s, RIDE_HOME 110 s, HOTEL_AFTER 120 s) and the shuttle interval of 360 s
    (`src/ReplicatedStorage/Shared/FlightPlan.module.luau:37`).
  - Active players progress faster than semi-idle ones. That is intended (audit weakness #3).
  - Stage 4 can start earlier with weaker models. In F_p2_human stage 4 starts at 66 and runs 104 min, so the
    stage-4 wall needs P1 together with P2.

---

### P4 · Goal card with three lines (Now / Next / Chapter) and an honest ETA

**Problem [M].**
- The card shows one goal (`GoalText.describe`, `GoalText.module.luau:125-152`).
- ETA = `(price + 2·reserve − cash) / net` (`EmpireMath.module.luau:200-203`). It shows 0.70 / 0.76 / 0.62 of the
  real minutes left (median), and is within ±50 % only 57 / 65 / 39 % of the minutes (§4.6).
- The region goal gives no action. The end state is "Every goal reached".

**Change [P].**
- **NOW** (≤ 5 min, one line, one tap): the first true item of
  1. a training decision is pending;
  2. a trained model is ready to reveal / launch;
  3. a meeting can be joined (P2);
  4. servers > 85 % full → a GPU;
  5. a free product line;
  6. an affordable research / Lab level;
  7. a milestone was just reached (P5).

  New pure function `EmpireMath.nowAction(data, live)`, using real state only.
- **NEXT** (the stage goal): today's `nextGoal`, with **ETA = gap / (0.75 × net)** [P], shown as a range rounded to
  5 min ("about 25–35 min") with "if you keep spending like now".
  - In the sim, ×0.75 gives median 0.93 / 1.02 / 0.83 and 83 / 88 / 74 % of minutes within ±50 % (today 57 / 65 /
    39 %). On the proposal runs it gives 0.98–1.13 and 70–83 % (§4.6).
  - Cash-slope ETAs were worse: 39–54 % (`out/eta_explore.md`).
  - Re-fit the factor after launch: log goal id, ETA shown and real minutes with `AnalyticsService:LogCustomEvent`
    (present in the API dump, Appendix A).
- **CHAPTER** (the long goal): "Chapter n of 6" with 3–5 named steps, a progress bar and a T3 celebration at the end
  (P5). Times are from F_all_human / F_p13_human; the chapters are [P].

| Chapter | Steps | Ends about |
|---|---|---|
| 1 Garage | train · launch · CloudDesk · Founder HQ | 10–13 min |
| 2 Founder HQ | 2nd line · first research · 3 clients · Startup Campus | 32–50 min |
| 3 Startup Campus | 3rd line · first region client (be there) · guest house · Innovation Campus | 66–92 min |
| 4 Port Meridian | Frontier research · Helix Research · Meridian Branch · Global AI HQ | 148–166 min |
| 5 Global | 4 lines at 90+ · Lab 10 · jet (optional) · Expansion 2–3 | 194–236 min |
| 6+ World tour | expansion levels · milestone tracks · (Generations, P8) | endless |

**Touches.** `EmpireMath` (`nowAction`, the ETA factor), `GoalText`, the HUD card (compact phone: NOW line + NEXT bar),
HomeApp "Today".

**Save.** None. Chapters are derived from state; the "chapter celebrated" flag goes in P5's `milestones`.

**Test.**
- Offline ETA table (§4.6).
- GoalText mock tests (pure function: snapshot in, view out).
- guiprev 844×390 and 1280×720 for the three-line card.

**Effort / risk.** M / low. The factor 0.75 is fitted on bot behaviour [A]; a real kid may spend differently, hence
the range and the re-fit.

---

### P5 · Milestone ladder and celebration tiers

**Problem [M].**
- One celebration burst in the whole game (§1). Office moves are a 5-s toast.
- Ranks stop at Scale-Up around min 45 (§1). The 12 quests are done by ~55 min (AUDIT.md §7.1).
- Longest stretch without any beat: 48 / 40 / 40 min in hour 3 and 55–60 min in hour 5 (§4.4).
- The founder office already has a "COMPANY MILESTONES" wall screen that only shows counters
  (`src/ServerScriptService/Server/Services/BuildingStateService.module.luau:437`).

**Change [P].**
- **Ladder** of ~60 milestones in 6 tracks, with these thresholds [P]:

| Track | Thresholds |
|---|---|
| peak users | 10k, 25k, 50k, 100k, 150k, 200k, 250k, 300k, 400k, 500k, 750k, 1M |
| market revenue | $10k … $50M (15 steps) |
| team size | 5, 10, 25, 50, 75, 100, 128, 150, 200, 240 |
| best model | 50, 60, 70, 80, 90, 95, 99 |
| clients | 1, 3, 5, 7, 10, 12, 14, 16 |
| world | first region client, first abroad client, Meridian Branch, each expansion level |

- **Rewards are never cash or random.** A milestone gives:
  - a trophy on the milestone wall screen;
  - a news line;
  - a title for the company card;
  - an optional Roblox badge via `BadgeService:AwardBadgeAsync`, with owner-created ids that default to 0 = off
    (like the shop ids). `AwardBadge` is deprecated in the dump; use the Async one (Appendix A).

  So the economy is unchanged, and the offline evaluation is exact.
- **Celebration tiers**:

| Tier | For | What plays |
|---|---|---|
| T1 | small steps | toast, at most 1 per 60 s (batched) |
| T2 | track steps ≥ 100k users / $1M / 50 staff, the 4th line, … | the existing HUD burst (`celebrateHook`) and staff in the room cheer (existing EmployeeController poses, e.g. "present") |
| T3 "Grand Opening" | office moves, Meridian Branch, expansion levels, chapter ends | 6-s full-screen card with the new name; staff gather at the entrance; client-side confetti via `ParticleEmitter:Emit`; tweened UI (`TweenService:Create`) |

  Every tier respects reduced motion (`GuiService.ReducedMotionEnabled`, as `HUD.module.luau:201-206` already does).
- **Ranks**: tie the rank to milestones reached [P], so it keeps moving.

**Touches.**
- New `Shared/Config/MilestoneConfig` + `Shared/MilestoneMath` (pure).
- `EmpireService.tick`: detection + news + badge.
- HUD / Toast, BuildingStateService milestone screen, `CompanyConfig.rankFor`.

**Save.**
- `empire.milestones = { [id] = minuteReached }`, additive.
- Cleaner: known ids only, finite numbers ≥ 0, ≤ 200 entries.
- Replicate only a count + the last 5 (CORE_SPEC 11.8 budgets).

**Test.**
- Offline beats table (§4.4): 45–48 milestones fire per run.
- The longest beat gap in hour 3 drops from 48 / 40 / 40 to 26 / 20 / 28 min. With P1 + P3 + ladder it is 18–20 min.
- Beats per 30 min after Global HQ rise from 0.6–0.8 to 1.9–2.1 (2.8–3.1 with P1 + P3).
- Mock:
  - each milestone fires once;
  - it survives a rejoin;
  - the cleaner drops unknown ids;
  - badge id 0 → no BadgeService call.

**Effort / risk.** M / low. The risk is noise, so T1 is batched. **Limit [M]**: in hour 6 the gap stays ~50 min,
because the ladder runs out.

---

### P6 · Save mode "Ready to move" (no freeze) and an honest Save-mode text

**Problem [M].**
- Save mode stops auto-HR at half the desks (`CompanyOps.module.luau:557`).
- It stays on while the next office is affordable but not bought (:538-545).
- The audit's `afk_tut` was in Save mode for all 174 min, with $758k in the garage while Founder HQ costs $27k
  (AUDIT.md §7.4).
- The card says "research, Lab levels and big buys wait until the move" (`GoalText.module.luau:231`), but only HR
  pauses (`CompanyOps.module.luau:557`).

**Change [P].**
- Save mode gets two states:
  - **Saving** (cash < price + 2 reserve): HR pauses at half the desks, as today.
  - **Ready** (cash ≥ price + 2 reserve): HR resumes, but automation never spends below price + 2 reserve. The HR
    fee check uses `money − price`.
- The assistant calls once: "Ready to move into Startup Campus: tap to move". The card shows a big MOVE button and
  plays the T3 scene on tap.
- An optional setting "Move automatically when ready" defaults to **off**. The move is a moment the kid should see.
  Also, auto-hiring an idle company can cut net profit (AUDIT.md §7.4, afk_hq).
- Text: "Save mode: HR hires up to half the desks until you have $X."

**Touches.**
- `CompanyOps.saveMode` / `hrAllowed`; `EmpireService.autoHire` (`EmpireService.module.luau:199-219`).
- `GoalText:231`; AssistantService / PhoneService call.

**Save.** `empire.prefs.autoMove` boolean (extend the prefs cleaner, `Template.module.luau:380-381`).

**Test.**
- Mock:
  - the Ready state resumes HR;
  - HR never takes cash below price + 2 reserve;
  - one call per stage.
- Re-run the audit's `afk_*` profiles. Expected effect is small (garage cap 5) [A], not simulated here.

**Effort / risk.** S / low.

---

### P7 · World reward calendar: Port Meridian, the airports and the Meridian Grand

**Problem [M].**
- The world has no gameplay hook (`ItineraryService.module.luau:7,24`). The jet is "a money sink that adds
  convenience, not income" (`CompanyOps.module.luau:115`).
- The planned airport concept already makes Port Meridian "the reward city for stage 4 and 5" with lounges and
  status, but "The tier never changes money" (`design/airports/concept_gameplay.md:12,138`).
- GRANDHOTEL_SPEC is binding: "Economy: no change … No new saved field … No new remote"
  (`design/GRANDHOTEL_SPEC.md` §0.4). The hotel is built before any airport work.

**Change [P].** One calendar that ties each place to a progression function.

| Stage | Opens in the world | What it does for progression | Change |
|---|---|---|---|
| 1–2 | home city, CloudDesk etc. | founder trips (today) | – |
| 3 | Business City offices, City Hotel | **be there**: a region pilot signs in the meeting (P2); about 3 min drive | P2 |
| 3 | guest house | "Meet the guests": a hosted pilot signs in the meeting | P2 |
| 4 | Port Meridian, Helix Research tower, airport Business→Founder status (airport concept §2) | abroad pilot signs in the meeting (P2); **Meridian Branch** (P1); jet purchasable | P1, P2 |
| 4 | **Meridian Grand** = the founder's base abroad | *Breakfast briefing* [P]: a night the founder stays after a PM meeting renews every Port Meridian account due within the next game day, at the hotel. No rep trip is needed, which frees reps for new pilots. **Not simulated**; small effect | P7 |
| 5 | frontier client towers (`src/ReplicatedStorage/Shared/Config/CityPlan.module.luau:306-309`) | frontier pilots signed in the meeting; each expansion level lights a PM tower floor | P2, P3 |

- The hotel rules stay intact. The breakfast renewal is an economy rule in `CompanyOps` / `EmpireService`, triggered
  by the existing reserved `TripAction {action = "hotel"}` route (GRANDHOTEL_SPEC §0.4 channels).
- It ships **after** grandhotel packages A + B, as its own small package. No hotel-package file gets economy code.

**Touches.** CompanyOps (`renewAtHotel`), EmpireService / DriverService `onTripAction("hotel")` handler, GoalText
chapter texts, the airport tier table (concept's AirportPlan).

**Save.** None (derived from stage and accounts).

**Test.**
- Mock: renewals due within one game day renew once, the others do not.
- `tests/itinerary` hotel step.
- Sim: add a `--hotel` switch before shipping (not done here).

**Effort / risk.** M / med. The risk is package order: it depends on grandhotel A/B and the itinerary fix landing
first.

---

### P8 · Generations: a soft reset of the model layer only (and why no prestige reset)

**Problem [M].**
- Stats cap at 99 (`EmpireMath.module.luau:159`). The first 99.0 model comes at 115.5 min and all lines are at 99
  by 139 min (AUDIT.md §3.2).
- Research is done at ~57 min and Lab 10 at ~127 min (AUDIT.md §7.1).
- After that, model design has no target, and stage-5 decisions stay at 2.6–4.4 per 10 min even with P3 (§4.3).

**Why not a full prestige reset.** The owner's core wish is a company that grows into a huge building
(LOGIC_BRIEF §1 items 10 and 13). Resetting the building would destroy what kids show friends. It would also fight
the 5-stage building code (`EmpireConfig.OFFICES`, BuildingPlan tiers). So the building, staff and money are never
reset.

**Change [P], not simulated.**
- After Lab 10 + Global AI HQ, the research "Generation 2" becomes available ($3M + 15,000 RP [P]).
- Effects:
  - stat cap +5 for new models (99 → 104 → 109 …);
  - Lab levels 11–15 for this generation;
  - a B2B "Gen-2 contracts" tier needing stats above 99 (higher retainers [P]);
  - the leaderboard shows "Gen 2 · 103.5".
- The 99 models stay live. Nothing is taken away; the Lab gets a target again.
- **Before adopting**: probe `MarketMath.utility` with stats > 99 in the sim. [U] how the market reacts above 99:
  untested.

**Touches.** EmpireMath.boostStats cap, EmpireConfig research, CompanyOps clients, LeaderboardService, LabApp texts.

**Save.** `empire.generation = 1`, additive with a cleaner.

**Test.** Sim probe first, then mock.

**Effort / risk.** L / high.

---------------------------------------------------------------------------------------------------------------------

## 4. Simulation: method and before / after tables

**Method.**
- `design/logic2/sim_progression/sim.luau` is the audit's simulator. It loads the real modules into the headless mock
  and plays through the real remotes, with these additions:
  - **in-memory patches** of the proposed rules (P1 / P3 `--branch` / `--expand`, P2 `--attend`). They are listed in
    the `PATCHES` block and never touch `work/src`;
  - bot rules: buy the next expansion level with the office reserve rule; the founder attends rep / hosted pilot
    meetings, one at a time, using the [A] travel minutes, with no decisions while travelling unless `--travelplay`;
  - read-only milestone counters in the GOAL lines.
- Without flags the sim is byte-for-byte the audit's behaviour: `F_base_*` = audit stage times (§1).
- Limits:
  - The bot never walks. Travel is modelled as busy time.
  - The bot buys Lab levels before money goals. A goal-following kid might buy the branch earlier, so the
    Branch-time numbers are conservative.
  - One server, no other players.

### 4.1 Stage times, expansion and income (`out/tables_final.md`)

| run | Founder HQ | Startup | Innovation | Branch | Global HQ | stage 4 | expansion L2..L6 (min) | rev $/min @180 / @300 | net $/min @300 |
|---|---|---|---|---|---|---|---|---|---|
| F_base_human | 12.5 | 38.5 | 92.0 | – | 174.5 | 82.5 | – | 73,671 / 116,436 | 69,414 |
| F_base_gpucap | 10.0 | 31.5 | 81.5 | – | 167.0 | 85.5 | – | 84,173 / 120,170 | 72,882 |
| F_base_semi | 10.0 | 50.0 | 90.0 | – | 175.0 | 85.0 | – | 71,744 / 119,151 | 72,231 |
| F_p1_human | 12.5 | 38.5 | 92.0 | 123.5 | **166.0** | 74.0 | – | 106,219 / 142,988 | 94,091 |
| F_p1_gpucap | 10.0 | 31.5 | 81.5 | 116.5 | **159.5** | 78.0 | – | 121,718 / 145,442 | 96,129 |
| F_p1_semi | 10.0 | 50.0 | 90.0 | 110.0 | **165.0** | 75.0 | – | 107,665 / 142,706 | 93,854 |
| F_p1x_human ($400k) | 12.5 | 38.5 | 92.0 | 125.5 | 169.5 | 77.5 | – | 102,901 / 142,988 | 94,079 |
| F_p1x_gpucap ($400k) | 10.0 | 31.5 | 81.5 | 118.5 | 162.0 | 80.5 | – | 115,844 / 145,442 | 96,129 |
| F_p2_human | 12.5 | 38.5 | 66.0 | – | 170.0 | 104.0 | – | 72,529 / 118,798 | 71,015 |
| F_p2tp_human (travel play) | 12.5 | 38.5 | 87.0 | – | 172.5 | 85.5 | – | 76,052 / 119,040 | 71,680 |
| F_p2_gpucap | 10.0 | 31.5 | 91.0 | – | 157.5 | 66.5 | – | 105,328 / 120,652 | 73,401 |
| F_p2j_human (today's +0.15) | 12.5 | 38.5 | 96.0 | – | **186.0** | 90.0 | – | 72,738 / 119,406 | 71,895 |
| F_p13_human | 12.5 | 38.5 | 92.0 | 123.5 | 166.0 | 74.0 | 214 / 236 / 266 / 308 | 106,219 / 168,827 | 118,256 |
| F_p13_gpucap | 10.0 | 31.5 | 81.5 | 116.5 | 159.5 | 78.0 | 196 / 222 / 252 / 294 / 350 | 121,718 / 180,057 | 128,651 |
| F_p13_semi | 10.0 | 50.0 | 90.0 | 110.0 | 165.0 | 75.0 | 200 / 230 / 255 / 300 / 355 | 107,665 / 168,543 | 118,295 |
| F_all_human | 12.5 | 38.5 | 66.0 | 77.0 | **155.0** | 89.0 | 194 / 236 / 266 / 308 | 126,411 / 168,781 | 117,755 |
| F_all_gpucap | 10.0 | 31.5 | 91.0 | 101.5 | **147.5** | 56.5 | 186 / 250 / 280 / 322 | 59,517\* / 163,117 | 112,379 |
| F_alltp_human | 12.5 | 38.5 | 87.0 | 113.5 | 162.0 | 75.0 | 206 / 228 / 258 / 302 / 360 | 120,118 / 169,060 | 118,139 |

\* the B2B-reserve capacity crash, see P1 risk.

Global HQ move payoff (net $/min 10 min before → 5–20 min after the move, `office moves` lines):
- today: 49,807 → 47,365 (human), 48,759 → 49,940 (gpucap), 45,781 → 50,696 (semi);
- P1: 66,292 → 71,503, 69,260 → 67,891, 60,955 → 70,355.

Cash at min 360:
- today: $10.7M / $11.9M / $11.7M;
- P1 + P3: $7.0M / $1.4M / $0.9M (the sink works).

### 4.2 Longest single goal on the card (minutes)

| run | longest goal | "every goal reached" |
|---|---|---|
| F_base_human / gpucap / semi | office5 83 / 85 / 85 | 210 / 193 / 200 |
| F_p1_human / gpucap / semi | office5 42 / 43 / 55 (branch 32 / 35 / 20 before it) | 199 / 176 / 185 |
| F_p13_human / gpucap / semi | 42 / expand6 56 / 55 | never |
| F_p2_human / gpucap | office5 87 / 67 (region goal 11 / 3 instead of 28 / 20) | 209 / 205 |
| F_all_human / gpucap | office5 69 / jet 82\* | never |

### 4.3 Real decisions per 10 min by stage (decision moments; longest gap)

| run | stage 3 | stage 4 | stage 5 |
|---|---|---|---|
| F_base_human | 17.8 (12.1; 7.0) | 7.4 (5.6; 13.5) | 4.3 (3.6; 20.0) |
| F_base_gpucap | 18.4 (13.2; 7.0) | 5.3 (4.4; 18.5) | 2.6 (1.9; 30.5) |
| F_p1_human | 17.8 (12.1; 7.0) | 8.1 (6.1; 13.5) | 5.0 (4.4; 29.5) |
| F_p1_gpucap | 18.4 (13.2; 7.0) | 6.0 (5.3; 11.0) | 2.6 (1.7; 33.5) |
| F_p13_human | 17.8 (12.1; 7.0) | 8.1 (6.1; 13.5) | 4.4 (3.8; 27.5) |
| F_p2_human | 14.2 (8.4; 15.0) | 9.4 (6.4; 24.5) | 5.0 (4.0; 38.5) |
| F_all_human | 14.2 (8.4; 15.0) | 9.6 (4.8; 20.5) | 4.2 (3.3; 38.5) |

Reading: P1 adds a decision and some GPU buys to stage 4. The pessimistic P2 travel removes decisions while away (an
upper bound of its cost). None of P1–P3 fixes the stage-5 decision rate, which is P8's job.

### 4.4 Progress beats: longest stretch without a beat per hour (min); with the P5 ladder

| run | h1 | h2 | h3 | h4 | h5 | h6 | beats / 30 min after Global HQ |
|---|---|---|---|---|---|---|---|
| F_base_human | 10 → 7 | 19 → 14 | **48 → 26** | 25 → 13 | 55 → 33 | 60 → 46 | 0.8 → 2.1 |
| F_base_gpucap | 12 → 8 | 18 → 10 | 40 → 20 | 30 → 16 | 60 → 39 | 60 → 40 | 0.6 → 1.9 |
| F_base_semi | 10 → 8 | 15 → 9 | 40 → 28 | 25 → 16 | 55 → 31 | 60 → 55 | 0.7 → 2.0 |
| F_p13_human | 10 → 7 | 19 → 14 | 19 → 18 | 14 → 14 | 34 → 31 | 52 → 52 | 1.4 → 3.0 |
| F_p13_gpucap | 12 → 8 | 18 → 10 | 22 → 18 | 22 → 12 | 42 → 39 | 50 → 50 | 1.5 → 3.0 |
| F_p13_semi | 10 → 8 | 15 → 9 | 30 → 20 | 17 → 17 | 45 → 39 | 55 → 52 | 1.5 → 3.1 |

The left value is today's beats; the right value adds the P5 ladder. Milestones change no money, so the right side is
exact.

### 4.5 Founder meetings (P2)

| run | meetings | closed in the meeting | min travelling (of 300) | first region client (min) |
|---|---|---|---|---|
| F_base_human / gpucap | – | – | – | 67 / 52 |
| F_p2_human / gpucap | 10 / 9 | 10 / 9 | 64 / 62 | **50 / 35** |
| F_p2tp_human | 9 | 9 | 62 | 50 |
| F_p2j_human (today's rule) | 8 | 0 (+0.15 each) | 56 | 67 |

### 4.6 ETA honesty (money goals; ETA shown ÷ real minutes left, every minute it is shown)

| run | today: median | today: within 0.67–1.5× | proposed ×0.75: median | proposed: within |
|---|---|---|---|---|
| F_base_human | 0.70 | 57 % | 0.93 | 83 % |
| F_base_gpucap | 0.76 | 65 % | 1.02 | 88 % |
| F_base_semi | 0.62 | 39 % | 0.83 | 74 % |
| F_p13_human / gpucap / semi | 0.76 / 0.85 / 0.78 | 61 / 77 / 64 % | 1.02 / 1.13 / 1.04 | 75 / 83 / 79 % |
| F_all_human / gpucap | 0.78 / 0.77 | 62 / 59 % | 1.03 / 1.02 | 77 / 70 % |

Factor scan on 6 base runs (937 samples, `out/eta_explore.md`):

| factor | ×1.0 | ×0.8 | ×0.75 | ×0.7 | ×0.6 |
|---|---|---|---|---|---|
| median | 0.71 | 0.89 | 0.95 | 1.02 | 1.18 |
| within ±50 % | 58 % | 81 % | 83 % | 84 % | 76 % |

Cash-slope estimators reach only 25–54 %.

### 4.7 Long horizon (600 min): does the P3 loop run away?

`run_long.sh`: `L_base_human` and `L_p13_human`, 600 min, think 30. Revenue and net are 10-minute means from the
GOAL lines.

| min | today: rev / net $/min | today: cash | P1 + P3: rev / net $/min | P1 + P3: cash | P1 + P3: level |
|---|---|---|---|---|---|
| 240 | 119,557 / 72,533 | $2.1M | 172,469 / 122,715 | $0.7M | 3 |
| 360 | 130,213 / 83,157 | $10.7M | 191,186 / 140,271 | $7.0M | 5 |
| 480 | 122,499 / 75,838 | $18.8M | 206,861 / 155,151 | $4.7M | 7 |
| 599 | 131,928 / 84,786 | **$27.2M** | 224,978 / 172,441 | $5.4M | 8 |

Level times (min):

| L1 | L2 | L3 | L4 | L5 | L6 | L7 | L8 |
|---|---|---|---|---|---|---|---|
| 123.5 | 213.5 | 235.5 | 266.5 | 308.0 | 365.5 | 448.5 | 565.0 |

The gaps between levels: 22, 31, 41.5, 57.5, 83, 116.5 min.

Reading:
- **No runaway.** After min 360 revenue grows +18 % in 4 h. Today it is +1 %, while cash piles up to $27M with nothing
  to buy.
- **The loop never ends, but it slows.** After ~6 h of play a level is a 1.5–2 h goal. That is idle-game cadence and
  needs P8 or live events (another lens) to keep short goals coming.
- A growth of ×1.4 instead of ×1.5 [P] would keep levels nearer 60 min until ~8 h (not simulated).

---------------------------------------------------------------------------------------------------------------------

## 5. How Port Meridian, the airports and the Meridian Grand become rewards (one view)

- **Stage 4 is "Chapter 4: Port Meridian".** Its goals are Helix Research (abroad), the Meridian Branch and Global
  AI HQ. Each one is either a trip there or something you see there.
- **Going there pays.** With P2 a meeting you attend in Port Meridian signs the client on the spot. Today the same
  trip is pure cost: 11.5 min slower to Global HQ (`F_p2j_human`).
- **The skyline is the scoreboard.** The branch and each expansion level light a floor in your colour, with
  0 parts (budget: 28 parts left).
- **The Meridian Grand is home abroad** (P7 breakfast briefing). The hotel package itself stays economy-free, as its
  spec demands.
- **Airport status** (Business at stage 3, Founder at stage 4, from the airport concept) stays a convenience. It
  never sells progress for Robux (`design/airports/concept_gameplay.md:81-82`).

---------------------------------------------------------------------------------------------------------------------

## 6. Risks, open knobs, owner decisions

1. **Bot ≠ kid.** All stage times are a bot on one seed. The bot buys Lab levels before money goals and never walks.
   Re-tune after a play-test; every number above is a single knob.
2. **Income growth late (P1 + P3).** +45–58 % revenue at 300–360 min. A 10-h check is in §4.7. Option: a branch
   upkeep (CORE_SPEC suggested $12,000/day for its stage-5 branch, `design/CORE_SPEC.md:977`). It is not simulated
   here; a re-run is needed if added.
3. **B2B reserve can starve serving** (P1 +2 slots; 1 of 18 runs). Cap reservations at 60 % of compute [P], or show
   "B2B is using X % of your servers" on the Compute app.
4. **Travel time assumptions** (P2) are not measured in Studio [A]. If abroad meetings take 25+ min, abroad
   "be there" is still positive only for players who can play on the phone during the trip.
5. **Package order.** P7 after grandhotel A / B and the itinerary fix. P2 touches EmpireService + CompanyOps only
   (the itinerary stays economy-free).
6. **Owner decisions:** the branch price ($300k vs $400k), the expansion growth (×1.5), the auto-move default (off),
   and badge ids (0 = off until created on create.roblox.com).

## 7. Reproduce

```bash
cd design/logic2/sim_progression
./run_base.sh        # batch 0: baseline check (sim_v1.luau) -> out/b_*
./run_prog.sh        # batch 1: exploratory variants (sim_v1.luau) -> out/p1_* p2* p3_* all_* p1b_*
./run_final.sh       # batch 2: the reported runs (sim.luau) -> out/F_*
./run_long.sh        # 600-min check -> out/L_*
python3 -I analyze_prog.py out F_base_human F_base_gpucap F_base_semi F_p1_human F_p1_gpucap F_p1_semi \
  F_p1x_human F_p1x_gpucap F_p2_human F_p2tp_human F_p2_gpucap F_p2j_human F_p13_human F_p13_gpucap F_p13_semi \
  F_all_human F_all_gpucap F_alltp_human > out/tables_final.md
python3 -I eta_explore.py out/F_base_*.txt ../audit/sim/out/{a_human_s7,semi120,a_bot}.txt
python3 -I apicheck_prog.py ../../../tools/API-Dump.json
```

All runs: `rc=0` (`out/run_*_log.txt`), 42–186 s each. `gen/` is `harness/make_manifest.py` output of `src_snap`.

## Appendix A. Roblox APIs named (all in `tools/API-Dump.json`, `out/apicheck_out.txt`: 18 checked, 0 missing)

- `BadgeService:AwardBadgeAsync`, `BadgeService:UserHasBadgeAsync`. `AwardBadge` exists but is tagged Deprecated,
  so it is not used.
- `DataStoreService:GetOrderedDataStore`, `OrderedDataStore:SetAsync`, `OrderedDataStore:GetSortedAsync`.
- `TweenService:Create`, `ParticleEmitter:Emit`, `GuiService.ReducedMotionEnabled` (Hidden / ReadOnly; read in a
  pcall as HUD does).
- `SurfaceGui`, `ProximityPrompt.Triggered`, `Instance:SetAttribute` / `GetAttribute`, `Workspace:GetServerTimeNow`.
- `AnalyticsService:LogCustomEvent` (and `LogProgressionEvent`, optional).
- `Player.Idled`, `Players.PlayerRemoving`.

## Appendix B. Files (all under `design/logic2/sim_progression/`)

- `sim.luau`: final simulator (audit sim + proposal patches + milestone counters + split expansion prices).
- `sim_v1.luau`: the version used for batches 0 / 1.
- `run_base.sh`, `run_prog.sh`, `run_final.sh`, `run_long.sh`.
- `analyze_prog.py` (tables), `eta_explore.py` (ETA formulas), `apicheck_prog.py`.
- `out/tables_final.md`, `out/tables_batch1.md`, `out/eta_explore.md`, `out/apicheck_out.txt`, `out/*.txt` (raw runs).
- `src_snap/` (+ `src_snap.time`, `src_snap.md5`), `gen/`.
